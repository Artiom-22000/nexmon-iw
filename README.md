# nexmon-iw (bcm4375b1 truth layer)

nexmon monitor mode on the Samsung Galaxy S21 (SM-G991B, bcm4375b1) is switched
**inside the Wi-Fi firmware** — the kernel/nl80211 never sees it. These wrappers
make everyday tools report and drive it truthfully.

**The deliverable:** a self-contained Magisk module
(`module/` directory → flashable `nexmon-iw-main-v1.5.zip`).

## What the module does

1. **Firmware patch**: bind-mounts the patched `bcmdhd_sta.bin_b1` (nexmon
   bcm4375b1) over `/vendor/firmware/bcmdhd_sta.bin_b1` at boot — this part
   originally lived in the separate `bcm_mon_boot` module (looked at its source;
   integrated here; that module gets auto-disabled by the installer).
2. **`iw` wrapper** (`system/bin/iw`, real binary kept as `iw.bin`):
   * passes everything through to the real iw unchanged, except
   * `iw dev` / `iw dev <if> info` / `iw <if> info`: "type managed" → "type
     monitor" whenever the firmware is (recorded) in monitor mode;
   * adds `iw nexmon [status|on|off|toggle|raw]`.
3. **`nexutil` on the ROM** (`system/bin/nexutil` wrapper + static
   `nexutil.bin`; this ROM ships no nexutil of its own):
   * records every successful `-g0x613/-s0x613/-g1555/-s1555 ± -vN` toggle to
     a boot_id-stamped state file — this is the **only** authoritative
     nexmon switch on this firmware;
   * `-m2`/`-m0` (WLC_SET_MONITOR) are passed through but **not** recorded:
     on bcm4375b1 they do not arm the nexmon radiotap stream (verified:
     airodump stays empty after `-m2`, fills with `-g0x613 -i -v2`), and a
     short note points to the real toggle;
   * `nexutil -m` prints the truthful recorded state (the firmware's
     `0x80000000` constant is garbage, never reported as ON);
   * bare `-g0x613 -i` (write-only ioctl on this patch: would *disable*
     monitor) is intercepted and prints a hexdump of the recorded state;
   * records are refused when the real binary reports
     `__nex_driver_io: error` (this binary exits 0 even on failed ioctls).
4. **File capabilities**: a tiny freestanding aarch64 helper (`nexcap`, raw
   `setxattr`, mock-verified 20-byte vfs-cap v2 layout + effective flag)
   applies `CAP_NET_ADMIN+ep` to every real nexutil binary at boot, so the
   firmware ioctls work from any context whose bounding set includes
   `CAP_NET_ADMIN` (plain adb shell, app-side root, chroot root). The only
   known-exceptional context is `adb shell su` on our device: its bounding set
   is `0x80` (SETUID only) so exec of any file-capability binary fails with
   EPERM — use plain `adb shell nexutil ...` instead of `su -c`.
5. **Chroot integration**: the installer/boot script wraps `nexutil` inside
   both `/data/local/nhsystem` kali chroots (originals kept as `nexutil.bin`,
   wrappers use `#!/bin/sh` — the chroot's dash — because the chroot may not
   have `/system` mounted early) and installs an `iw` wrapper (kali-arm64),
   all reading/writing the same state file; `service.sh` chroot-executes a
   self-test and logs it.
6. **Shared state**: `/data/local/nhsystem/kali-arm64/tmp/nexmon/nexmon.state`
   (= `/tmp/nexmon/nexmon.state` in the kali-arm64 chroot), bind-mounted over
   `kalifs/tmp/nexmon`, mode 666 in a 777 dir so uid 2000/shell, cap-less root
   and chroot-root can all read/write it. A *file* bind mount cannot be
   replaced by `mv` (EBUSY), hence the dedicated subdirectory.
7. **Hijacker bridge**: Hijacker (com.hijacker) bundles its own 32-bit nexutil
   and extracts it to its private dir at first run; the module finds it,
   keeps it as `nexutil.bin` and installs the wrapper (recording into the
   shared state) + file caps. If Hijacker re-extracts, the next boot re-wraps.
   Never use Hijacker's own "install nexmon" on this device (it ships
   S7-era firmware).
8. **libfakeioctl delivery (v1.4+)**: Hijacker's Java side does
   `System.load("/vendor" + "/lib" + "/libfakeioctl.so")` (32-bit ARM, from its
   APK assets). The module magic-mounts the same file as
   `/vendor/lib/libfakeioctl.so` and `/vendor/lib64/libfakeioctl.so`, so the
   app-side loading finds it on both ABIs (on arm64 the 32-bit lib fails to
   load, which the app handles the same as "not found"; the 32-bit app process
   gets a working hook). The file is inert otherwise — nothing else loads it.
   (Hijacker itself was abandoned on this device — the lib stays harmlessly.)
 9. **Stryker app VM integration (v1.5+)**: Stryker (com.zalexdev.stryker)
   doesn't use a chroot — it boots a *user-mode Linux* VM whose rootfs is the
   directory `/data/local/stryker/release`, with its own `/proc`, `/sys` and a
   tmpfs `/tmp` (state there is per-VM-session), and a `hostfs` share mounted
   at `/host`. The installer wraps that VM's `nexutil` (original kept as
   `nexutil.bin`, wrapper at `usr/local/bin/nexutil`) and `iw` (original kept
   as `iw.real`, wrapper at `usr/sbin/iw` with auto-detect — the copy a user
   had made earlier pointed `REAL_IW` at *itself* and fork-bombed). The boot
   script creates `release/tmp/nexmon` so the layout is ready for a future
   share-based state hookup.

## Capture (works via the existing aliases)

Capture does **not** go through the wrappers — the classic path is:

```sh
svc wifi disable            # release the AP (adb or rom terminal)
ifconfig wlan0 up
nexmon_enable2g             # k1 + monitor — or 5g / -k<your AP's channel>
nexutil -k6/20              # pin a channel with traffic on it (know its band)
airodump-ng wlan0           # the alias preloads libnexmonkali.so (engine:
                            # envelope faking + nexmon frame plumbing)
```

Notes learned on this device:

* airodump refuses `wlan0` while still *connected* — libnexmonkali queries the
  firmware live (`WLC_GET_MONITOR`) and reports `ARPHRD_ETHER` unless the firmware
  is actually in radiotap state. Disconnect first (`svc wifi disable`).
* **`nexutil -m2` does not work for capture on this firmware** — it flips the
  generic dhd monitor flag, the nexmon radiotap stream stays off, and airodump's
  table stays empty even though the wrapper's note-worthy flags all look fine.
  The nexmon vendor variable is what matters: `-g0x613 -i -v2` (that is what
  the `nexmon_enable2g/5g` aliases use, and what `iw nexmon on` issues).
* Wrong channel = empty table even with delivery working; `nexutil -k <ch>`
  readback verifies (`0x1006`-style chanspec echo).
* `chroot/nexsniff` (freestanding, in this repo + on device at
  `/tmp/nexmon/nexsniff`) is the delivery ground-truth probe used to debug all
  of this; `chroot/libnexmon_arph.so` is a minimal shim kept for experiments —
  the real engine is the preexisting `usr/local/lib/libnexmonkali.so`.


## State resolution order (iw)

1. `NEXMON_FORCE` env override → 2. state file (fresh boot_id only) →
3. `nexutil -m` (garbage constants classified as garbage) →
4. unknown ⇒ plain iw passthrough (never degrades).

## After the firmware resets

Rebooting or toggling Wi-Fi resets monitor mode silently. `nexutil -g0x613 -i
-v0` (or `iw nexmon off`) resyncs the record, `-v2` re-enables.

## Files in the repo

* `module/` — the complete Magisk module (zip with `zip -r`), flashable via the
  Magisk app; also mirrored to `/sdcard/Download/nexmon-iw-main-v1.5.zip` on
  the device. `fw/bcmdhd_sta.bin_b1` is the patched nexmon firmware.
* `test/run.sh` — 50 POSIX-sh checks (`sh`/`bash`/`dash`), fakes in `test/`.
* `install.sh`/`uninstall.sh` — adb-side helpers around the module flow.

## Fresh-device flashing (v1.5+)

The zip is self-contained (wrappers, `nexutil.bin`/`iw.bin`, `nexcap`, firmware)
and installs cleanly on a factory-reset device:

* with no chroots present, chroot deploy/bridge steps are skipped gracefully —
  the wrappers, file caps and state recording still work on the plain ROM
  (toggle test needs the shared state dir, which the installer creates;
  `libnexmonkali.so` and the `nexmon_enable2g/5g`/`nexmon_disable` aliases are
  part of the NetHunter chroot setup, not of this module);
* a **model guard** protects other devices: the bundled S10/S20/S21
  (`bcm4375b1`) firmware binds only on `SM-G97*/SM-G98*/SM-G99*` models, or
  when `/data/adb/nexmon_force_fw` exists — other devices keep their stock
  wifi firmware (and until a matching firmware patch exists, also stock
  monitor behavior; wrappers keep working regardless);
* the old `bcm_mon_boot` module, if present, is auto-disabled by the installer.

## Known limits

* Truth is a recorded best-effort: it is in sync with `nexutil`/`iw nexmon`
  actions by definition, but actions done via other tools (e.g. raw wl ioctl
  scripts) bypass the record. After reboot the file is boot_id-invalidated,
  which matches the firmware reset to OFF. `-m2`/`-m0` are passthrough-only
  (see above) — only `0x613` writes can change the record.
* WLC_GET_MONITOR never tells the truth on this ROM (`0x80000000`), and ioctl
  0x613 is write-only — recorded state is the best available source.
* `iw dev` type-rewrite only fires when the wrapper believes monitor is ON;
  with unknown state it stays silent (passthrough).
