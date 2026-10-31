#!/system/bin/sh
# nexmon-iw :: customize.sh (slim)
# Ships: patched nexmon wifi firmware, BT firmware (brcm/BCM.hcd),
# the real nexutil (/system/bin + Stryker VM if present), nexcap,
# and the bt-on / bt-off commands. No wrappers: the kernel reports
# monitor state natively (Floppy nexmon-native patch).
SKIPUNZIP=0

ui_print " "
ui_print "  nexmon-iw v1.6 :: bcm4375b1 (kernel-native monitor)"
ui_print "  nexmon wifi fw + BT fw + nexutil + bt-on/bt-off"
ui_print " "

MODEL=$(getprop ro.product.model 2>/dev/null)
case "$MODEL" in
    SM-G97*|SM-G98*|SM-G99*) ui_print "- device: $MODEL (bcm4375b1, firmware patch applies)" ;;
    *) ui_print "- device: $MODEL NOTE: bundled nexmon firmware targets S10/S20/S21!";;
esac

rm -rf "$MODPATH/META-INF" 2>/dev/null

set_perm_recursive "$MODPATH" 0 0 0755 0644 2>/dev/null
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/lib.sh"          0 0 0755
set_perm "$MODPATH/nexcap"          0 0 0755
set_perm "$MODPATH/valloop.sh"      0 0 0755
set_perm "$MODPATH/bt.sh"           0 0 0755
set_perm "$MODPATH/bt-on"           0 0 0755
set_perm "$MODPATH/bt-off"          0 0 0755
set_perm "$MODPATH/system/bin/nexutil" 0 0 0755

# ---------------------------------------------------------------------------
# hand the wifi firmware job over from bcm_mon_boot (one owner)
# ---------------------------------------------------------------------------
if [ -d /data/adb/modules/bcm_mon_boot ]; then
    touch /data/adb/modules/bcm_mon_boot/disable
    ui_print "- bcm_mon_boot disabled (its firmware bind moved here)"
fi

# ---------------------------------------------------------------------------
# clean up wrappers installed by previous module versions (< v1.6):
# the kali chroots carried nexutil/iw wrappers with .bin backups; the
# kernel reports monitor state natively now, restore the originals.
# ---------------------------------------------------------------------------
for K in /data/local/nhsystem/* /data/local/stryker/release; do
    [ -d "$K" ] || continue
    for d in "$K" "$K/usr/local/bin"; do
        if [ -f "$d/nexutil.bin" ]; then
            mv -f "$d/nexutil.bin" "$d/nexutil" 2>/dev/null
            chmod 755 "$d/nexutil" 2>/dev/null
            ui_print "- restored $d/nexutil (wrapper removed)"
        fi
    done
    # chroot iw wrappers (kali: /usr/local/bin/iw; stryker: iw.real kept by app)
    if grep -q NEXMON_IW_WRAPPER "$K/usr/local/bin/iw" 2>/dev/null; then
        rm -f "$K/usr/local/bin/iw"
        ui_print "- removed $K/usr/local/bin/iw wrapper"
    fi
done
if [ -f /data/local/stryker/release/usr/sbin/iw.real ]; then
    mv -f /data/local/stryker/release/usr/sbin/iw.real \
          /data/local/stryker/release/usr/sbin/iw 2>/dev/null
    ui_print "- restored stryker /usr/sbin/iw"
fi

# ---------------------------------------------------------------------------
# Stryker VM nexutil (install now if the VM rootfs exists; service.sh
# re-installs at every boot while the folder is present)
# ---------------------------------------------------------------------------
SK=/data/local/stryker/release
if [ -d "$SK/usr/local/bin" ]; then
    cp -f "$MODPATH/system/bin/nexutil" "$SK/usr/local/bin/nexutil" 2>/dev/null
    chmod 755 "$SK/usr/local/bin/nexutil" 2>/dev/null
    ui_print "- nexutil installed to stryker VM"
else
    ui_print "- stryker VM not present (skipped; installed at boot if it appears)"
fi

ui_print " "
ui_print "  Reboot to activate. Then:"
ui_print "    nexmon: nexutil -g0x613 -i -v2   (or the aliases)  -> iw dev shows monitor"
ui_print "    bluetooth: bt-on  /  bt-off      (any root shell)"
ui_print " "
