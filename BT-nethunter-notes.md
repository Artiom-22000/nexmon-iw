# NetHunter Bluetooth on bcm4375b1 (Floppy + nexmon-iw)

## Kernel side (already in build 1412+)
- RFCOMM+TTY, HIDP, full hci_sock (Samsung's Android-14 gutting never
  applied to Floppy), HCIUART+BCM transport, bcm43xx controller driver.
- Added: CONFIG_BT_BNEP=y (+MC/PROTO filters) — the only missing piece.

## Why hci0 doesn't exist by default
Android's vendor HAL (android.hardware.bluetooth@1.0-service) drives the
BCM4375 **directly over /dev/ttySAC1** (HIDL model, userspace H4+patchram
at 3 Mbaud) — the kernel stack is bypassed entirely. hci0 only appears
when the *kernel* attaches the controller.

## Bring-up (module bt.sh — run as root)
    sh /data/adb/modules/nexmon-iw/bt.sh

Sequence (see module/bt.sh):
1. Android BT off, vendor HAL stopped (`stop vendor.bluetooth-1-0`)
2. Bind-mount the labeled /dev/ttySAC1 into the kali chroot /dev
   (chcon u:object_r:bt_device:s0 — a raw mknod node is SELinux-denied)
3. Cold power-cycle the chip via rfkill2 ("bcm43xx Bluetooth") — the HAL
   leaves the UART mid-state; a power cycle resets it to ROM defaults
4. `btattach -B /dev/ttySAC1 -P bcm` inside the chroot (default baud;
   do NOT pass -S — the chip answers at the kernel default after reset)
5. Firmware: the kernel requests `brcm/BCM.hcd`; the module overlays
   `/vendor/firmware/bcm4375B1_murata.hcd` as
   `system/etc/firmware/brcm/BCM.hcd` (magisk) — build 0000 → 0176
6. `btmgmt --index 0 power on`

Result: hci0 powered, addr 43:75:B1:00:76:93, name
"BCM4375B1 Palette 1RH NR 2db Ant0 [Baseline: 0176]".

## Teardown
    kill btattach   (or reboot), then re-enable Android bluetooth.

## Gotchas learned
- btattach must get the in-chroot path (/dev/ttySAC1), not the host path
- The chroot /dev node disappears on reboot (static chroot /dev) —
  bind-mount (not mknod; unlabeled nodes are SELinux-denied)
- The rfkill unblock must come from the magiskd context (the plain
  `su` context cannot even read rfkill sysfs on this ROM)
- The firmware stage takes ~19 s; give btattach time before checking
- semco_sem vs murata hcd: murata works on o1s (SM-G991B); swap in
  bcm4375B1_semco_sem.hcd if the module reports a wrong palette
