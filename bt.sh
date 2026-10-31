#!/system/bin/sh
# NetHunter BT bring-up for bcm4375b1 (Floppy kernel, nexmon-iw module)
# Attaches the BT controller to the kernel stack as hci0 so the kali
# chroot's bluez tools can use it. Run as root: sh /data/adb/modules/nexmon-iw/bt.sh
# Undo: kill btattach (or reboot), then re-enable Android bluetooth.
L=/data/adb/modules/nexmon-iw/bt.log
K=/data/local/nhsystem/kali-arm64
{
    echo "=== bt.sh $(date) ==="
    /system/bin/svc bluetooth disable
    stop vendor.bluetooth-1-0 2>/dev/null
    sleep 2

    KDEV=$K/dev/ttySAC1
    touch $KDEV 2>/dev/null
    mount -o bind /dev/ttySAC1 $KDEV 2>/dev/null
    chcon u:object_r:bt_device:s0 $KDEV 2>/dev/null
    chmod 666 $KDEV

    # cold power cycle via the bcm43xx rfkill (bt_en gpio)
    echo 0 > /sys/class/rfkill/rfkill2/state 2>/dev/null
    sleep 3
    echo 1 > /sys/class/rfkill/rfkill2/state 2>/dev/null
    sleep 2
    dmesg | grep -a "Power On" | tail -1

    # attach (needs the module overlay firmware: system/etc/firmware/brcm/BCM.hcd)
    chroot $K /usr/bin/btattach -B /dev/ttySAC1 -P bcm &
    sleep 25

    chroot $K /usr/bin/btmgmt --index 0 power on 2>&1
    chroot $K /usr/bin/btmgmt --index 0 info 2>&1 | head -8
    echo "=== hci0 ready for NetHunter (kill btattach to release) ==="
} > $L 2>&1
