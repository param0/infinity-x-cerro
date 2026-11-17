# Project Infinity X 17 for nubia Z60 Ultra (cerro) — unofficial build

*[Русская версия](README.md)*

Android 17 (SDK 37) on the nubia Z60 Ultra / NX721J. Built from Project
Infinity X sources, branch `17`, on device trees by nukisystems and
Evolution-X-Devices.

The device tree existed, but it would not build against Android 17 and did
not work once it did. What is here: the build script, the thirteen fixes it
took, and a ready package. Every fix was found on the running device — from
logs, a disassembler, window dumps and screenshots — not by guesswork.

| | |
|---|---|
| Version | `Project_Infinity-X-4.2-cerro-17.11.2026` |
| Android | 17, SDK 37, security patch 2026-11-01 |
| Variant | GAPPS, UNOFFICIAL, userdebug |
| Maintainer | sasha_paramonov |

This build is **unofficial**. Project Infinity X does not support it, and
whoever flashes it owns the consequences.

---

## Installation

### Before you start

* Unlocked bootloader.
* A recovery that can `adb sideload` a full OTA package: this ROM's own
  recovery, OrangeFox or TWRP for cerro all work.
* `adb` and `fastboot` on your computer (Google's `platform-tools`).

The package is a **full OTA** carrying `payload.bin`. It installs to the
inactive slot and **does not touch `/data`**: apps, settings and files stay
where they are. Updating over a previous build therefore needs no wipe.

You only need to wipe `/data` in two cases: you are coming from a different
ROM, or the system misbehaves after installing — another ROM leaves settings
in `/data` that this one reads differently. See
[Dirty flashing](#dirty-flashing-what-to-expect).

### Step 1. Download and rejoin

The package is split in two because GitHub refuses files larger than 2 GiB.
Download **both** parts and `SHA256SUMS` from the
[release](../../releases/latest) into the same folder.

Linux / macOS:

```sh
cat Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip.part-* \
  > Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip
sha256sum -c SHA256SUMS
```

Windows (PowerShell):

```powershell
cmd /c copy /b Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip.part-00 ^
  + Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip.part-01 ^
  Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip
Get-FileHash Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip -Algorithm SHA256
```

Checking the sum is not a formality: `adb sideload` on a truncated archive
fails with `E: footer is wrong` or dies at 47%, and you lose time wondering
whether the recovery or the file is at fault.

Expected sum:

```
7f84ca74b673aea0a78af3397eba0d46b8edef3c4f57b2867c7c4c9de3939f8f
```

### Step 2. Flash

```sh
adb reboot sideload-auto-reboot
adb sideload Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip
```

The `-auto-reboot` suffix matters: the recovery enters sideload mode
directly and reboots itself when the install finishes. Plain
`adb reboot sideload` leaves you to exit the mode by hand.

If the phone drops you into the recovery menu instead, pick
**Apply update → Apply from ADB** and repeat the second command.

Installation takes 3–6 minutes. The recovery shows the real progress;
`adb sideload` sitting at 47% has not hung — that is the normal pause while
`payload.bin` is unpacked.

### Step 3. First boot

The first start takes 3–7 minutes while apps are optimised, longer if you
came from another ROM.

### If you want root

The OTA rewrites `init_boot` in the slot it installs to. Any KernelSU /
ReSuKiSU / Magisk patch is lost on update — that is expected.

Order matters: flash the OTA **first**, boot, confirm things work, and
**only then** patch the `init_boot.img` **from this same build**. The image
is attached to the release next to the package parts.

```sh
adb reboot bootloader
fastboot flash init_boot init_boot_patched.img
fastboot reboot
```

Patching an image from a different build gives you a boot loop.

### Recovery

The release includes `recovery.img` from this same build. You need it in two
cases: your current recovery cannot `adb sideload`, or you want the stock
recovery back after OrangeFox or TWRP.

```sh
adb reboot bootloader
fastboot flash recovery recovery.img
fastboot reboot recovery
```

The partition is slot-suffixed: check the active slot with
`adb shell getprop ro.boot.slot_suffix` and name it explicitly if needed
(`recovery_a` or `recovery_b`).

### Rolling back

The device is A/B: the previous system stays in the other slot until you
flash something else. From fastboot:

```sh
fastboot --set-active=other
fastboot reboot
```

This works exactly once, and only until the next OTA install.

---

## What works

Everything essential: calls and SIM, mobile data, Wi-Fi, Bluetooth, NFC,
cameras, the under-display fingerprint reader, sensors, audio, Dolby Atmos,
gesture navigation, Play services.

## What does not

* **ViPER4Android cannot be built.** Its native part requires a
  `libviperaidl` module that is published nowhere. The dead reference to it
  has been removed from the audio effects configuration.
* **Play certification** is absent on a fresh install, as on any custom ROM.
  Google's own route fixes it — register the device at
  `google.com/android/uncertified`. Nothing to do with this build.

---

## What was fixed

Thirteen changes in short. The first five are what it takes to build at all;
the rest fix the behaviour of a system that already boots.

| # | Symptom | Fix |
|---|---|---|
| 1 | Tree hard-requires `NubiaParts`, absent from every manifest | project added to the local manifest |
| 2 | codec2 blobs allocate 272 bytes for a 288-byte class → heap corruption | patched the `movz` immediate in three blobs |
| 3 | New public SELinux types without a compat mapping → build fails | added `202504.ignore.cil` |
| 4 | Treble labelling on A17: app domain declared in vendor policy | domain moved to platform policy |
| 5 | No `infinity_cerro` product | generated from `lineage_cerro` |
| 6 | SystemUI died in a loop creating the navigation bar | retry instead of a fatal exception |
| 7 | Status bar clock would not centre, icons drawn over it | clock moved to its own container |
| 8 | "About phone" fields empty | properties moved to `product.prop` |
| 9 | Dolby Atmos never started | sepolicy + VINTF manifest + compatibility matrix |
| 10 | No black dot over the under-display front camera | implemented from scratch |
| 11 | `nubia_parts` could not reach the Trust service | sepolicy rule added |
| 12 | Wi-Fi location subsystem logging at debug level around the clock | lowered to warnings |
| 13 | Audio config referencing a non-existent library | reference removed |

<details>
<summary><b>In detail: why each fix is what it is</b></summary>

### 1. NubiaParts is a hard dependency

`device/nubia/sm8650-common/common.mk:409` pulls the app in with a hard
`inherit-product`, not `inherit-product-if-exists`. Neither the Project
Infinity X nor the Evolution X manifest contains that project, and the
tree's own `lineage.dependencies` does not mention it either. Without it
`lunch` dies on `packages/apps/NubiaParts/config.mk does not exist`.

We take `Evolution-X-Devices/packages_apps_NubiaParts` branch `cnb`:
nukisystems has no Android 17 branch at all.

### 2. codec2 ABI: 272 → 288 bytes

The tree ships a tripwire its maintainer left — `c2_store_abi_check` with
`static_assert(sizeof(ComponentStore) == 272)`. On Android 17 the class grew
to **288**.

Bumping the number in the assertion was not an option. The QTI blobs call
`operator new` with the size baked in at their own build time, and
`ComponentStore` inherits `RefBase` virtually, so the reference counter sits
at the tail of the object. With a larger class, writing to it lands past the
end of the allocation: that is heap corruption inside the codec2 service —
broken video and recording crashes — not an honest build error.

The real size was obtained from the compiler without building: take the
ready clang command from `out/siso_failed_commands.sh`, feed it a probe with
an undefined template — `ShowSize<sizeof(T)> x;` — and clang prints the
number in the error text.

What gets patched is the `movz w0` immediate before `bl operator new`:

```
mov w0, #264 = 00 21 80 52   (stock)
mov w0, #272 = 00 22 80 52   (the tree's own Android 16 patch)
mov w0, #288 = 00 24 80 52   (what A17 needs)
```

In three files: `vendor.qti.media.c2@1.0-service`,
`vendor.qti.media.c2audio@1.0-service`, and — found separately — in
`vendor.dolby.media.c2@1.0-service` from the Dolby tree, which still carried
the stock 264. The same number is updated in `extract-files.py` so that
re-extracting blobs from the phone produces the correct patch.

Do not confuse this with the `280` in `c2.dolby.store.so`: that is the size
of their own `DolbyC2Store` class, visible from the constructor called right
after the allocation. Leave it alone.

### 3. SELinux compat mapping

NubiaParts declares its own public types `sysfs_fan` and `sysfs_gamekey`.
Every new public type must appear in the compat mapping of the newest API
level, or `treble_sepolicy_tests` treats it as a vendor-policy compatibility
break.

The tree only has `private/compat/202404/202404.ignore.cil`, for Android 16.
On Android 17 `PlatformSepolicyVersion = 202604`, the newest compat level is
**202504**, and there was no file for it.

### 4. Treble labelling

From `BOARD_API_LEVEL >= 202604` a new test is enforced: platform apps must
carry a `coredomain` type, and `coredomain` may not be declared in vendor
policy. The NubiaParts apps install to `system_ext/priv-app`, so they are
platform apps, yet the tree declares the `nubia_parts` domain in
`sepolicy/vendor`.

Laid out the way AOSP does it for `system_app`: type in `public`, attributes
and rules in `private`, and only the vendor-type access left in `vendor` —
vendor policy can see platform public types and nothing else.

The `sysfs_leds:file` rule went away with it: a `coredomain` may not touch
those (a neverallow in `coredomain.te`, with only init, apexd, ueventd, vold
and system_app excepted). It was not needed anyway — the actual nodes are
relabelled to `sysfs_fan` and `sysfs_gamekey` in `genfs_contexts`.

### 6. SystemUI died creating the navigation bar

78 records in dropbox within one second, 125 crashes in a single boot log:

```
BadTokenException: Unable to add window -- another window of type 2019
                   already exists           (2019 = TYPE_NAVIGATION_BAR)
  at NavigationBar.onInit
  at NavigationBarControllerImpl.createNavigationBar
  at CommandQueueInitializer.start
```

The exception propagated, took down `KeyguardService` and with it the whole
of SystemUI; that restarted, hit the same foreign window and died again.
Hence the slow boot with a broken shell — the white system power menu is
drawn by `system_server` while SystemUI is dead — and the death on every
navigation settings change.

The window belongs to **the launcher**: on a phone in gesture mode Launcher3
always creates a `Taskbar` window of type `TYPE_NAVIGATION_BAR`. That is by
design, and SystemUI is supposed to yield, handing its duties to
`TaskbarDelegate`.

Two changes: a guard against creating a second bar for the same display and,
more importantly, a bounded retry in place of the fatal exception. The
foreign window goes away as soon as its owner leaves.

> **A trap worth naming.** Do **not** disable
> `com.android.wm.shell.enable_taskbar_on_phones`, tempting as it looks.
> That flag *is* the handover. Disable it and SystemUI will try to create its
> own window, leaving you with no navigation at all.

### 7. Centred status bar clock

Choosing the centre position pinned the clock to the left edge, with
notification icons drawn over the digits.

`@id/clock_center` lived inside `@id/centered_area` — a horizontal
`LinearLayout` with `gravity="center"` — while `StatusBarRoot.kt` adds a
`MATCH_PARENT`-wide `ComposeView` for popup chips to that same container. A
full-width child eats all the free space, so there is nothing left for
`gravity` to distribute.

The clock moved to its own `@id/clock_center_area`; `centered_area` stays in
place, empty, because both `StatusBarRoot.kt` (via `requireViewById`) and
`PhoneStatusBarView` still need it.

### 8. "About phone" properties

Two attempts failed before one worked.

Via `vendor.prop` — impossible: properties on the vendor partition are set
by init in the `vendor_init` context, which may not set the `default_prop`
type, so they silently stay empty:

```
avc: denied { set } for property=ro.product.marketname
     scontext=u:r:vendor_init:s0 tcontext=u:object_r:default_prop:s0
```

Via `PRODUCT_PRODUCT_PROPERTIES` — also no: that is a make list, split on
whitespace, so values were truncated to their first word (`nubia` instead of
`nubia Z60 Ultra`).

A `product.prop` file works: its lines land in `product/etc/build.prop`
verbatim.

### 9. Dolby Atmos

Three layers, and all three were missing.

**sepolicy.** The `dms-hal-2-0` service crashed every 5 seconds on denials
against `vendor_audio_prop`, a type from QTI policy that the Dolby tree
knows nothing about. One `set_prop` closes it.

**A VINTF declaration.** The service then exited with status 1, silently:

```
hwservicemanager: getTransport: Cannot find entry
  vendor.dolby.hardware.dms@2.0::IDms/default
  in either framework or device VINTF manifest
```

The manifest goes exactly where the device tree already looks —
`BoardConfigCommon.mk` contains
`-include hardware/dolby/configs/vintf/config.mk`, and branch `cnb` has no
such directory. `PRODUCT_COPY_FILES` is not an option: the build answers
"VINTF metadata found in PRODUCT_COPY_FILES".

**A compatibility matrix.** The manifest alone is not enough —
`check_vintf` requires the HAL to be allowed in a matrix, or the build fails
with "instances are in the device manifest but not specified in framework
compatibility matrix".

The side effect of fixing this shows up in battery use: while the service
was failing, init set `sys.init.updatable_crashing=1` and ran
`flags_health_check` every 5 seconds, and the Dolby app crashed along with
it — thousands of crashes accumulated in the log.

Branch `cnb` rather than `cnb-aidl` is not a matter of taste: the device
manifest declares HIDL audio
(`android.hardware.audio.effect @7.0::IEffectsFactory`), and the library
names in `audio_effects.xml` — `libswdap.so`, `libdlbvol.so`,
`libswgamedap.so` — are exactly the `cnb` ones; `cnb-aidl` names them
differently.

### 10. Black dot over the under-display camera

On cerro the front camera sits under the panel. While pixels above it are
lit, the sensor shoots through them, so stock turns that patch off while the
front camera is in use.

The tree had a **stub** for this: `CameraHelper` detected the front camera in
`onCameraAvailable`/`onCameraUnavailable` and both branches were empty — and
nothing ever sent the broadcast that would register the callback in the first
place.

Implemented in `NubiaPartsHelper`: an `Application` with
`android:persistent` and a system overlay window holding a black oval. Three
non-obvious details:

* the window calls `setTrustedOverlay()`, or the dot comes out
  semi-transparent — `TYPE_SYSTEM_OVERLAY` counts as
  `isSystemAlertWindowType()`, and `DisplayPolicy` force-clamps alpha to
  `mMaximumObscuringOpacityForTouch` (0.8) for an untrusted window carrying
  `FLAG_NOT_TOUCHABLE`. Holding `INTERNAL_SYSTEM_WINDOW` is not enough;
* one function decides visibility, not the display-change handler: otherwise
  a refresh-rate switch mid-fade-out restored the dot to full opacity and it
  stayed forever — exactly what happened while recording video messages;
* screen rotation is mapped to whichever edge the camera physically ended up
  on.

The default geometry was tuned on the device: 72 × 71 px, offset 3 right and
18 down, a soft 260 ms scale animation. All of it is adjustable live, with no
rebuild:

```sh
adb shell settings put secure udc_dot_offset_y 20
adb shell settings put secure udc_dot_anim_ms 350
adb shell settings put secure udc_dot_enabled 0
```

### 12. Wi-Fi location debug logging

`lowi.conf` arrives from stock with `LOWI_LOG_LEVEL = 4`, which is
`EL_DEBUG` by the file's own legend. In a release build the subsystem writes
a debug stream around the clock: 2624 lines in a single log window, i.e. CPU
time and logd writes for nothing. Set to 2 — warnings and errors still come
through.

For contrast: `DEBUG_LEVEL` in `gps.conf` is already at its minimum, so
there is nothing to turn down there, and the wlan driver ships no logging
config in the blobs, so we did not guess.

</details>

---

## Dirty flashing: what to expect

If you install this over another Android 17 ROM without a wipe, some of the
"bugs" will not be ours. `/data` holds settings the new system reads
differently. Observed in practice:

| Symptom | Cause | Fix without reflashing |
|---|---|---|
| No navigation bar and no back gesture at all | `force_show_navbar` = 0 from the previous ROM | `content insert --uri content://lineagesettings/system --bind name:s:force_show_navbar --bind value:s:1`, then reboot |
| Back gesture gone, everything else fine | taskbar enabled | turn the taskbar off in navigation settings |
| An app crashing every ten seconds | leftover of the previous ROM in `/data/app` | uninstall it |
| Odd theme, wrong icons | `theme_customization_overlay_packages` points at overlays that do not exist here | clear the value |

`force_show_navbar` is read by `DisplayPolicy.updateSettings()` and the value
lives in `/data` — restarting SystemUI is not enough, you need a reboot.

---

## Trees and revisions

The revisions this release was built from:

| project | path | branch | commit |
|---|---|---|---|
| [`manifest`](https://github.com/ProjectInfinity-X/manifest) | `.repo/manifests` | [`17`](https://github.com/ProjectInfinity-X/manifest/tree/17) | [`657f87c`](https://github.com/ProjectInfinity-X/manifest/commit/657f87c) |
| [`android_device_nubia_cerro`](https://github.com/nukisystems/android_device_nubia_cerro) | `device/nubia/cerro` | [`cnb`](https://github.com/nukisystems/android_device_nubia_cerro/tree/cnb) | [`a6f0c88`](https://github.com/nukisystems/android_device_nubia_cerro/commit/a6f0c88) |
| [`android_device_nubia_sm8650-common`](https://github.com/nukisystems/android_device_nubia_sm8650-common) | `device/nubia/sm8650-common` | [`cnb`](https://github.com/nukisystems/android_device_nubia_sm8650-common/tree/cnb) | [`011ffef`](https://github.com/nukisystems/android_device_nubia_sm8650-common/commit/011ffef) |
| [`proprietary_vendor_nubia_cerro`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_cerro) | `vendor/nubia/cerro` | [`cnb`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_cerro/-/tree/cnb) | [`c28dcb4`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_cerro/-/commit/c28dcb4) |
| [`proprietary_vendor_nubia_sm8650-common`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_sm8650-common) | `vendor/nubia/sm8650-common` | [`cnb`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_sm8650-common/-/tree/cnb) | [`9bc8a04`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_sm8650-common/-/commit/9bc8a04) |
| [`packages_apps_NubiaParts`](https://github.com/Evolution-X-Devices/packages_apps_NubiaParts) | `packages/apps/NubiaParts` | [`cnb`](https://github.com/Evolution-X-Devices/packages_apps_NubiaParts/tree/cnb) | [`09b3a58`](https://github.com/Evolution-X-Devices/packages_apps_NubiaParts/commit/09b3a58) |
| [`hardware_dolby`](https://github.com/Evolution-X-Devices/hardware_dolby) | `hardware/dolby` | [`cnb`](https://github.com/Evolution-X-Devices/hardware_dolby/tree/cnb) | [`8b67465`](https://github.com/Evolution-X-Devices/hardware_dolby/commit/8b67465) |
| [`kernel_nubia_sm8650`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650) | `kernel/nubia/sm8650` | [`cnb`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650/tree/cnb) | [`ce0a3f0`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650/commit/ce0a3f0) |
| [`kernel_nubia_sm8650-devicetrees`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-devicetrees) | `kernel/nubia/sm8650-devicetrees` | [`cnb`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-devicetrees/tree/cnb) | [`2047747`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-devicetrees/commit/2047747) |
| [`kernel_nubia_sm8650-modules`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-modules) | `kernel/nubia/sm8650-modules` | [`cnb`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-modules/tree/cnb) | [`4efca25`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-modules/commit/4efca25) |

Branch `cnb` is Cinnamon Bun, the Android 17 codename. The Android 16 branch
is called `bka` (Baklava).

---

## Patches

`patches/` holds ready diffs against the commits listed above.

| file | tree | contents |
|---|---|---|
| `0001-device_nubia_cerro.patch` | `device/nubia/cerro` | the `infinity_cerro` product, `product.prop` with the About-phone properties, hooking product.prop up in BoardConfig |
| `0002-device_nubia_sm8650-common.patch` | `device/nubia/sm8650-common` | `ComponentStore` size in both ABI checks and in `extract-files.py`, reserved partition sizes, the dead ViPER reference |
| `0003-packages_apps_NubiaParts.patch` | `packages/apps/NubiaParts` | domain moved to platform policy, the 202504 compat mapping, Trust service access, the whole UDC black dot |
| `0004-hardware_dolby.patch` | `hardware/dolby` | `vendor_audio_prop` sepolicy, the VINTF manifest and the compatibility matrix |
| `0005-frameworks_base_SystemUI.patch` | `frameworks/base` | retry instead of a crash when creating the navigation bar, the centred-clock container |
| `0006-proprietary_vendor_nubia_sm8650-common.patch` | `vendor/nubia/sm8650-common` | LOWI log level |

Apply them from the root of the matching tree:

```sh
cd device/nubia/cerro && git apply /path/to/patches/0001-device_nubia_cerro.patch
```

**The codec2 blob patch is deliberately not among the diffs.** It changes
four bytes in three proprietary executables, and shipping those here would
mean redistributing somebody else's binaries. The build script does it
itself, idempotently: it looks for a `movz w0` holding the stock or
intermediate value and writes 288. See step 5 in `build-infinity-cerro.sh`.

---

## Building from source

```sh
bash build-infinity-cerro.sh
```

The script does everything: `repo init`/`sync` of branch `17`, writing
`.repo/local_manifests/cerro.xml` with the trees from the table above,
applying all thirteen fixes **idempotently**, and running `m bacon`.

Useful overrides:

```sh
NO_SYNC=1    bash build-infinity-cerro.sh   # rebuild without syncing
SYNC_ONLY=1  bash build-infinity-cerro.sh   # sources only
WITH_GAPPS=false bash build-infinity-cerro.sh
VARIANT=user bash build-infinity-cerro.sh
BUILD_THREADS=8 bash build-infinity-cerro.sh
```

You need roughly 300 GB free (sources ~145 GB, `out/` ~155 GB) and a
distrobox container named `rom` — the script enters it on its own and holds
a `systemd-inhibit` lock so the machine stays awake.

Every fix in the script carries a comment explaining the cause: what broke,
what the build or the device printed, and why the solution looks the way it
does. The patches in `patches/` do the same thing, but they are easier to
read and review.

---

## Licences

The build script and the black-dot code (`UdcDot.java`) are Apache-2.0.

The device trees, the kernel, `hardware/dolby` and the vendor blobs belong to
their authors (nukisystems, Evolution-X-Devices, Qualcomm, nubia) and are not
duplicated here — the table above pins the exact revisions.
