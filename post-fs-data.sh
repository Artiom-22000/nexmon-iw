#!/system/bin/sh
# nexmon-iw module :: post-fs-data (slim)
# 1. bind-mounts the patched nexmon firmware over the vendor firmware file
# 2. file caps for nexutil + the air* tools
MODDIR=${0%/*}
LOGFILE="$MODDIR/nexmon-iw.log"

{
    echo "=== nexmon-iw post-fs-data.sh $(date) ==="
    echo "context: $(id -Z 2>/dev/null)"

    setenforce 0 2>/dev/null
    echo "setenforce: $(getenforce 2>/dev/null)"

    # --- firmware patch (nexmon bcmdhd_sta for bcm4375b1) ---------------------
    # the bundled firmware is built for the S10/S20/S21 bcm4375b1 family
    # (18.41.117, SM-G991B S21). On any other device DO NOT clobber its own
    # Wi-Fi firmware; bypass with: touch /data/adb/nexmon_force_fw
    FW_SRC="$MODDIR/fw/bcmdhd_sta.bin_b1"
    FW_DST="/vendor/firmware/bcmdhd_sta.bin_b1"
    MODEL=$(getprop ro.product.model 2>/dev/null)
    case "$MODEL" in
        SM-G97*|SM-G98*|SM-G99*) OK=1 ;;
        *)
            if [ -e /data/adb/nexmon_force_fw ]; then
                OK=1
                echo "firmware: model '$MODEL' not in the known bcm4375b1 family, FORCED by marker"
            else
                OK=0
                echo "firmware: model '$MODEL' is not the S10/S20/S21 family; NOT binding (wifi left stock)"
                echo "firmware: touch /data/adb/nexmon_force_fw and reboot to force"
            fi
            ;;
    esac
    if [ "$OK" = 1 ] && [ -f "$FW_SRC" ] && [ -f "$FW_DST" ]; then
        if mount --bind "$FW_SRC" "$FW_DST" 2>&1; then
            echo "firmware: bind-mounted (sha $(sha1sum "$FW_DST" 2>/dev/null | sed 's/ .*//'))"
        else
            echo "firmware: bind mount FAILED (is bcm_mon_boot already handling this?)"
        fi
    else
        [ "$OK" = 1 ] && echo "firmware: source or destination missing, skipped"
    fi

    # --- file caps ------------------------------------------------------------
    . "$MODDIR/lib.sh"
    nexmon_iw_apply "post-fs-data"
    echo "=== post-fs-data done ==="
} >> "$LOGFILE" 2>&1
