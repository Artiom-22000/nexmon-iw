#!/system/bin/sh
# nexmon-iw module :: late_start service (slim)
# 1. re-applies file caps (idempotent)
# 2. installs the real nexutil into the Stryker VM if that rootfs exists
# 3. spawns the valloop daemon (bt-on / bt-off privileged worker)
MODDIR=${0%/*}
LOGFILE="$MODDIR/nexmon-iw.log"

{
    echo "=== nexmon-iw service.sh $(date) ==="
    . "$MODDIR/lib.sh"
    nexmon_iw_apply "service"

    # --- Stryker VM nexutil -------------------------------------------------
    SK=/data/local/stryker/release
    if [ -d "$SK/usr/local/bin" ]; then
        cp -f "$MODDIR/system/bin/nexutil" "$SK/usr/local/bin/nexutil" 2>/dev/null &&
            chmod 755 "$SK/usr/local/bin/nexutil" &&
            echo "stryker: nexutil installed to $SK/usr/local/bin/nexutil"
        nexmon_iw_apply "stryker"
    else
        echo "stryker: /data/local/stryker/usr/local/bin does not exist, skipped"
    fi

    # --- valloop daemon (bt-on / bt-off worker) ------------------------------
    if [ -f "$MODDIR/valloop.sh" ] && ! [ -n "$(pidof valloop.sh 2>/dev/null)" ]; then
        ( sh "$MODDIR/valloop.sh" >/dev/null 2>&1 & )
        echo "valloop: spawned"
    fi

    echo "=== service done ==="
} >> "$LOGFILE" 2>&1
chmod 644 "$LOGFILE" 2>/dev/null
