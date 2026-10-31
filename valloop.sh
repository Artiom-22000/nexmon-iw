#!/system/bin/sh
# nexmon-iw validation loop (child of magiskd service context = full caps)
M=/data/adb/modules/nexmon-iw
T=/data/local/tmp/.nexval
K=/data/local/nhsystem/kali-arm64
NX=/system/bin/nexutil

echo "[-] valloop started $(date)" > $M/valloop.log

bt_up() {
    L=$M/bt.log
    [ -d /sys/class/bluetooth/hci0 ] && { echo "[-] hci0 already up $(date)" >> $L; return 0; }
    echo "[-] bt-up $(date)" >> $L
    /system/bin/svc bluetooth disable >> $L 2>&1
    stop vendor.bluetooth-1-0 >> $L 2>&1
    sleep 2
    KDEV=$K/dev/ttySAC1
    touch $KDEV 2>/dev/null
    mount -o bind /dev/ttySAC1 $KDEV 2>> $L
    chcon u:object_r:bt_device:s0 $KDEV 2>> $L
    chmod 666 $KDEV
    BTRF=$(grep -l "bcm43xx Bluetooth" /sys/class/rfkill/rfkill*/name 2>/dev/null | head -1 | xargs dirname)
    echo "BTRF=$BTRF" >> $L
    echo 0 > $BTRF/state 2>> $L
    sleep 3
    echo 1 > $BTRF/state 2>> $L
    sleep 2
    echo "rfkill state now: $(cat $BTRF/state 2>&1)" >> $L
    dmesg | grep -a "Power On" | tail -1 >> $L
    chroot $K /usr/bin/btattach -B /dev/ttySAC1 -P bcm >> $L 2>&1 &
    sleep 35
    chroot $K /usr/bin/btmgmt --index 0 power on >> $L 2>&1
    chroot $K /usr/bin/btmgmt --index 0 info 2>&1 | head -6 >> $L
    echo "[-] bt-up done $(date), hci0: $(ls /sys/class/bluetooth/ 2>&1)" >> $L
}

bt_down() {
    L=$M/bt.log
    echo "[-] bt-down $(date)" >> $L
    kill $(pidof btattach) 2>/dev/null
    umount $K/dev/ttySAC1 2>/dev/null
    start vendor.bluetooth-1-0 >> $L 2>&1
    /system/bin/svc bluetooth enable >> $L 2>&1
    echo "[-] bt-down done, android bt restoring $(date)" >> $L
}

while true; do
    if [ ! -f $T ]; then sleep 2; continue; fi
    id=$(head -c 16 $T 2>/dev/null | tr -d '\r\n ')
    rm -f $T
    L=$M/val$id.log
    echo "[-] test $id $(date)" >> $L
    case $id in
        on)
            bt_up
            ;;
        off)
            bt_down
            ;;
        1)
            ifconfig wlan0 up 2>> $L
            $NX -m0 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            $NX -k6 >> $L 2>&1
            echo "type=$(cat /sys/class/net/wlan0/type)" >> $L
            echo "iwconfig:" >> $L
            chroot $K /usr/sbin/iwconfig wlan0 2>&1 | head -6 >> $L
            ;;
        2)
            echo "airodump (10s on wlan0, PLAIN no-preload):" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 10 \
                /usr/sbin/airodump-ng -w /tmp/nexcap -c 6 wlan0 >> $L 2>&1
            echo "airodump rc=$?" >> $L
            ls -la /tmp/nexcap* 2>/dev/null >> $L 2>&1
            ;;
        3)
            echo "aireplay test (PLAIN no-preload):" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 25 \
                /usr/sbin/aireplay-ng --test wlan0 >> $L 2>&1
            echo "aireplay rc=$?" >> $L
            ;;
        4)
            $NX -g0x613 -i -v0 >> $L 2>&1
            echo "type=$(cat /sys/class/net/wlan0/type)" >> $L
            echo "disarm:" >> $L
            chroot $K /usr/sbin/iwconfig wlan0 2>&1 | head -2 >> $L
            ;;
        5)
            ifconfig wlan0 up 2>> $L
            $NX -m0 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            $NX -k6 >> $L 2>&1
            $NX -k 2>&1 | head -1 >> $L
            echo "type=$(cat /sys/class/net/wlan0/type)" >> $L
            echo "wext channel set 11 via iwconfig:" >> $L
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 11 2>&1 | head -3 >> $L
            echo "wext read back:" >> $L
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 2>&1 | grep -iE 'Channel|Frequency' | head -2 >> $L
            echo "dmesg chanspec:" >> $L
            dmesg 2>/dev/null | grep -E 'nexmon: chanspec' | tail -3 >> $L
            ;;
        6)
            # cap-context experiment: which masks are exec-able from a
            # zero-cap su session? (flex the file masks)
            NCX=/data/adb/modules/nexmon-iw/nexcap
            cp /data/adb/nexget /data/adb/cap_n 2>/dev/null
            cp /data/adb/nexget /data/adb/cap_1k 2>/dev/null
            cp /data/adb/nexget /data/adb/cap_2k 2>/dev/null
            cp /data/adb/nexget /data/adb/cap_3k 2>/dev/null
            chmod 755 /data/adb/cap_* 2>/dev/null
            "$NCX" /data/adb/cap_n 2>&1
            "$NCX" -m 1000 /data/adb/cap_1k 2>&1
            "$NCX" -m 2000 /data/adb/cap_2k 2>&1
            "$NCX" -m 3000 /data/adb/cap_3k 2>&1
            echo "capped: cap_n cap_1k cap_2k cap_3k (phase 1 done)" >> $L
            ;;
        8)
            # ch7 injection test: alias order (chanspec BEFORE arm), then
            # airodump on ch7 (retune ground truth: user's networks live there)
            # followed by aireplay --test against the found APs.
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -2 >> $L
            echo "type=$(cat /sys/class/net/wlan0/type)" >> $L
            echo "airodump 12s on ch7 (PLAIN):" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 12 \
                /usr/sbin/airodump-ng -w /tmp/nex7 -c 7 wlan0 >> $L 2>&1
            echo "aireplay --test on ch7 (PLAIN):" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 25 \
                /usr/sbin/aireplay-ng --test wlan0 >> $L 2>&1
            echo "aireplay rc=$?" >> $L
            ls -la /tmp/nex7* 2>/dev/null >> $L
            ;;
        9)
            # directed injection test: broadcast probes go unanswered even
            # with working injection; directed probes to a live AP get ACKs/
            # probe responses if frames truly reach the air.
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            echo "aireplay -9 directed at 50:88:11:C8:2B:B2:" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 30 \
                /usr/sbin/aireplay-ng -9 -a 50:88:11:C8:2B:B2 wlan0 >> $L 2>&1
            echo "aireplay rc=$?" >> $L
            ;;
        10)
            # realistic flow: airodump first (its osdep open normalizes the
            # iface), then directed aireplay against the AP it just saw.
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot $K /usr/bin/timeout -k 5 -s KILL 8 \
                /usr/sbin/airodump-ng -w /tmp/nex10 -c 7 wlan0 >> $L 2>&1
            echo "airodump rc=$?" >> $L
            echo "aireplay -9 directed at 50:88:11:C8:2B:B2:" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 30 \
                /usr/sbin/aireplay-ng -9 -a 50:88:11:C8:2B:B2 wlan0 >> $L 2>&1
            echo "aireplay rc=$?" >> $L
            ;;
        11)
            # exact known-good case-8 sequence + directed aireplay at the end
            sleep 5   # let svc-wifi-disable teardown finish before arming
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -2 >> $L
            echo "type=$(cat /sys/class/net/wlan0/type)" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 10 \
                /usr/sbin/airodump-ng -w /tmp/nex11 -c 7 wlan0 >> $L 2>&1
            echo "airodump rc=$?" >> $L
            echo "aireplay -9 directed at 50:88:11:C8:2B:B2:" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 30 \
                /usr/sbin/aireplay-ng -9 -a 50:88:11:C8:2B:B2 wlan0 >> $L 2>&1
            echo "aireplay rc=$?" >> $L
            ;;
        12)
            # ground-truth probe: does the RAW nexmon stream deliver frames?
            # nexsniff binds ALL ifaces, prints per-packet lines.
            sleep 5
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -1 >> $L
            echo "nexsniff 40 packets:" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 15 /tmp/nexmon/nexsniff 40 >> $L 2>&1
            echo "airodump 8s:" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 8 /usr/sbin/airodump-ng -c 7 wlan0 >> $L 2>&1
            ;;
        13)
            # where do the beacons go? tcpdump -i any labels every frame
            # with its arrival interface. 80 frames, link-level header.
            sleep 5
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -1 >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 15 \
                /usr/bin/tcpdump -Z root -i any -c 80 -e -q 2>&1 | strings | grep -avE "^listening" | head -40 >> $L
            ;;
        14)
            # beacon probe: full 802.11 decode on wlan0, WITH a re-arm after
            # the channel set (theory: chanspec write re-engages mgmt filter)
            sleep 5
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -1 >> $L
            $NX -g0x613 -i -v2 >> $L 2>&1
            echo "tcpdump wlan0 (decoded):" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 12 \
                /usr/bin/tcpdump -Z root -i wlan0 -c 100 2>&1 | strings | grep -aiE "beacon|probe|assoc|auth|deauth|data|ack" | head -30 >> $L
            echo "aireplay -9:" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 30 \
                /usr/sbin/aireplay-ng -9 -a 50:88:11:C8:2B:B2 wlan0 >> $L 2>&1
            echo "aireplay rc=$?" >> $L
            ;;
        15)
            # functional injection test without beacons: deauth the station
            # of the user's own AP; if the deauths reach the air, the client
            # re-associates and airodump sees the assoc/auth/EAPOL frames.
            sleep 5
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -1 >> $L
            echo "aireplay -0 5 (deauth) to station of 50:88:11:C8:2B:B2:" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 20 \
                /usr/sbin/aireplay-ng -0 5 -a 50:88:11:C8:2B:B2 \
                -c 9C:53:22:BA:8A:42 --ignore-negative-one wlan0 >> $L 2>&1
            echo "aireplay rc=$?" >> $L
            echo "airodump 14s after deauth (watch station return):" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 14 \
                /usr/sbin/airodump-ng -c 7 wlan0 >> $L 2>&1
            ;;
        16)
            # direct kernel-inject test: nexinject sends 10 deauths through
            # the packet socket (dhd_nexmon_mon_tx path), then airodump
            # watches ch7 for the client re-associating (proof of TX).
            sleep 5
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -1 >> $L
            echo "nexinject (10 deauths, kernel 408 path):" >> $L
            /data/local/tmp/nexinject 10 >> $L 2>&1
            echo "airodump 14s on ch7 (watch re-assoc):" >> $L
            chroot $K /usr/bin/timeout -k 5 -s KILL 14 \
                /usr/sbin/airodump-ng -c 7 wlan0 >> $L 2>&1
            echo "nexinject tcpdump crosscheck:" >> $L
            /data/local/tmp/nexinject 3 >> $L 2>&1
            chroot $K /usr/bin/timeout -k 5 -s KILL 6 \
                /usr/bin/tcpdump -Z root -i wlan0 -c 30 2>&1 | strings | head -12 >> $L
            ;;
        17)
            # injection verdict: tcpdump in background DURING nexinject —
            # clients kicked by the deauth re-authenticate within seconds.
            sleep 5
            ifconfig wlan0 up 2>> $L
            $NX -k7 >> $L 2>&1
            $NX -g0x613 -i -v2 >> $L 2>&1
            chroot /data/local/stryker/release /usr/sbin/iwconfig wlan0 channel 7 2>&1 | head -1 >> $L
            chroot $K /usr/bin/tcpdump -Z root -i wlan0 -U -w /tmp/inj.cap >/dev/null 2>&1 &
            TCPPID=$!
            sleep 1
            echo "nexinject 10 deauths while capturing:" >> $L
            /data/local/tmp/nexinject 10 >> $L 2>&1
            sleep 4
            kill $TCPPID 2>/dev/null
            sleep 1
            echo "capture dump (deauth/auth/assoc lines):" >> $L
            chroot $K /usr/bin/tcpdump -Z root -i lo -r /tmp/inj.cap 2>/dev/null >/dev/null
            chroot $K /usr/bin/tcpdump -Z root -r /tmp/inj.cap -c 400 2>&1 | strings | grep -aicE "deauth|auth|assoc" >> $L
            chroot $K /usr/bin/tcpdump -Z root -r /tmp/inj.cap 2>&1 | strings | grep -aiE "deauth|auth entication|associat" | head -12 >> $L
            ;;
        18)
            # NetHunter BT bring-up: attach BCM4375 (ttySAC1). Stop the HAL,
            # power-cycle via the correct rfkill (by name), then sweep
            # speed/protocol combos until the controller answers HCI Reset.
            sleep 3
            /system/bin/svc bluetooth disable >> $L 2>&1
            stop vendor.bluetooth-1-0 >> $L 2>&1
            sleep 2
            KDEV=$K/dev/ttySAC1
            touch $KDEV 2>/dev/null
            mount -o bind /dev/ttySAC1 $KDEV 2>> $L
            chcon u:object_r:bt_device:s0 $KDEV 2>> $L
            chmod 666 $KDEV
            cp /vendor/firmware/bcm4375B1_murata.hcd /data/local/tmp/bcm.hcd
            chmod 644 /data/local/tmp/bcm.hcd
            BTRF=$(grep -l "bcm43xx Bluetooth" /sys/class/rfkill/rfkill*/name 2>/dev/null | head -1 | xargs dirname)
            echo "BT rfkill: $BTRF state=$(cat $BTRF/state)" >> $L
            echo 0 > $BTRF/state 2>> $L; sleep 2; echo 1 > $BTRF/state 2>> $L; sleep 2
            dmesg 2>/dev/null | grep -a "\[BT\] Bluetooth Power" | tail -2 >> $L
            for speed in 115200 3000000 9600; do
                echo 0 > $BTRF/state 2>> $L; sleep 2; echo 1 > $BTRF/state 2>> $L; sleep 1
                echo "=== try speed=$speed bcm ===" >> $L
                chroot $K /usr/bin/timeout -k 3 -s KILL 8 \
                    /usr/bin/btattach -B $KDEV -P bcm -S $speed >> $L 2>&1
                sleep 2
                dmesg 2>/dev/null | grep -aE "hci0: (BCM|command)" | tail -2 >> $L
                [ "$(ls /sys/class/bluetooth/ 2>/dev/null)" != "" ] && break
            done
            echo "sysfs: $(ls /sys/class/bluetooth/ 2>&1)" >> $L
            echo "btmgmt info:" >> $L
            chroot $K /usr/bin/btmgmt info 2>&1 | head -8 >> $L
            dmesg 2>/dev/null | grep -aE "hci0: (BCM|command)|Patch" | tail -6 >> $L
            ;;

        19)
            # run the module's NetHunter BT bring-up script (detached)
            sh /data/adb/modules/nexmon-iw/bt.sh
            sleep 30
            tail -14 /data/adb/modules/nexmon-iw/bt.log >> $L 2>&1
            ;;

        *)
            echo "unknown test: $id" >> $L
            ;;
    esac
done
