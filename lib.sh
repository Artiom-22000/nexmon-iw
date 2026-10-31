#!/system/bin/sh
# nexmon-iw module library (slim) -- sourced by post-fs-data.sh / service.sh.
# Expects $MODDIR set. Runs inside the Magisk daemon context (root, full caps).
# The kernel (nexmon-native monitor patch) is the source of truth now; this
# library only applies file capabilities so the tools work from every context.

nexmon_iw_apply() {
    tag=$1

    BB=/data/adb/magisk/busybox
    [ -x "$BB" ] || BB=/system/xbin/busybox_nh

    NC="$MODDIR/nexcap"
    # vfs cap v2 + effective flag, CAP_NET_ADMIN
    CAPVAL_HEX=0100000200100000000000000000000000000000
    CAPVAL_B64=0sAQAAAgAQAAAAAAAAAAAAAAAAAAA=
    # NET_ADMIN|NET_RAW for the air* tools in the kali chroots (raw packet
    # sockets + WEXT monitor ioctls need both)
    CAPVAL_AIR_HEX=010000020030000000000000000000000000000000
    CAPVAL_AIR_B64=0sAQAAAgAwAAAAAAAAAAAAAAAAAAA=

    set_cap_one() {
        f=$1
        m=$2
        if [ -n "$m" ]; then
            if [ -x "$NC" ] && "$NC" -m "$m" "$f" >/dev/null 2>&1; then
                echo "caps(nexcap -m $m): $f OK"
                return 0
            fi
            if "$BB" setfattr -n security.capability -v "$CAPVAL_AIR_B64" "$f" >/dev/null 2>&1; then
                echo "caps(setfattr -m $m 0s): $f OK"
                return 0
            fi
        fi
        if [ -x "$NC" ] && "$NC" "$f" >/dev/null 2>&1; then
            echo "caps(nexcap): $f OK"
            return 0
        fi
        if "$BB" setfattr -n security.capability -v "0x$CAPVAL_HEX" "$f" >/dev/null 2>&1; then
            echo "caps(setfattr 0x): $f OK"
            return 0
        fi
        if "$BB" setfattr -n security.capability -v "$CAPVAL_B64" "$f" >/dev/null 2>&1; then
            echo "caps(setfattr 0s): $f OK"
            return 0
        fi
        echo "caps: FAILED on $f"
        return 1
    }

    cap_one() {
        f=$1
        m=$2
        [ -f "$f" ] || { echo "caps: (absent) $f"; return 0; }
        chmod 755 "$f" 2>/dev/null
        set_cap_one "$f" "$m"
    }

    echo "[$tag] === file capabilities ==="
    cap_one "$MODDIR/system/bin/nexutil"
    for d in /data/local/nhsystem/kali-arm64 /data/local/nhsystem/kalifs \
             /data/local/stryker/release; do
        cap_one "$d/nexutil"
        cap_one "$d/usr/local/bin/nexutil"
        # air* tools: NET_ADMIN|NET_RAW so channel changes from any context
        # reach the kernel nexmon bridge (airodump-ng hopping, aireplay)
        for sub in usr/bin usr/sbin; do
            cap_one "$d/$sub/airodump-ng" 3000
            cap_one "$d/$sub/aireplay-ng" 3000
            cap_one "$d/$sub/iwconfig" 3000
        done
    done
    return 0
}
