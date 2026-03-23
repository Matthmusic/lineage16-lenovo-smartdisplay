# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Android device tree for **Lenovo Smart Display 10" (SD-X701F)**, codename **blueberry**. The goal is to run TWRP 8.1 recovery (and eventually LineageOS) on a device that shipped with Android Things 8.1.

- **SoC**: Qualcomm MSM8953 (Snapdragon 625), ARM 32-bit
- **Related device**: Lenovo ThinkSmart View (CD-18781Y, codename "starfire") — same SoC, LineageOS 15.1 exists
- **Partition scheme**: A/B seamless updates, no dedicated recovery partition
- **Display**: Himax HX83100A panel, 800×1280 portrait, rotation 270°
- **Stock**: Android Things 8.1, `verifiedbootstate=orange` (AVB unlocked, fastboot works)

## Building

Build runs via **GitHub Actions** only (no local Linux build environment). Push to `main` triggers the workflow automatically, or run it manually via `workflow_dispatch`.

```bash
# Trigger a build manually
gh workflow run "Build TWRP for Lenovo Smart Display 10 (blueberry)" --repo Matthmusic/android_device_lenovo_blueberry

# Download the resulting boot.img
gh run download <run-id> --repo Matthmusic/android_device_lenovo_blueberry --name twrp-blueberry-recovery --dir ./out
```

The workflow: syncs TWRP 8.1 OMNI manifest → copies this device tree into `device/lenovo/blueberry/` → builds `bootimage` → uploads `boot.img` as artifact.

## Flashing

```bash
fastboot flash boot_b out/boot.img
fastboot set_active b
fastboot reboot
```

To revert to stock (slot a):
```bash
fastboot set_active a
fastboot reboot
```

## Key Build Constraints

- **TWRP 8.1 = Python 2**: The entire AOSP 8.1 build system uses Python 2. The workflow sets `python` → `python2` via `python-is-python2`. Do NOT change this to Python 3 or the build will break with `print` statement syntax errors throughout `build/tools/`.
- **Java 8 required**: TWRP 8.1 requires JDK 1.8.x. `openjdk-11-jdk` will be rejected at build time.
- **Ubuntu 20.04 container**: Required for `libncurses5` (the prebuilt `clang-4053586` links against `libncurses.so.5`). Ubuntu 22.04+ does not provide this.
- **Prebuilt kernel**: `prebuilt/zImage` is the stock kernel extracted from `boot_a`. No kernel compilation happens.

## Device Tree Files

| File | Purpose |
|------|---------|
| `BoardConfig.mk` | Main build config: arch, kernel addresses, A/B flags, TWRP display settings |
| `omni_blueberry.mk` | Product definition: brand, model, density, rotation |
| `AndroidProducts.mk` | Registers the product with the build system |
| `recovery.fstab` | Partition mount table for TWRP (A/B: system/vendor/boot use `slotselect`) |
| `vendorsetup.sh` | Registers `omni_blueberry-eng` lunch combo |
| `omni.dependencies` | Empty `[]` — suppresses roomservice warning |
| `prebuilt/zImage` | Stock kernel extracted from `boot_a.img` (20MB, ARM 32-bit) |

## Critical Kernel Parameters

Extracted from stock `boot_a.img` — must not be changed:
```
BASE:        0x10000000
KERNEL ADDR: 0x10008000  (base + 0x8000)
RAMDISK OFF: 0x01000000
TAGS OFFSET: 0x00000100
PAGE SIZE:   2048
CMDLINE:     console=ttyMSM0,115200,n8 earlyprintk androidboot.hardware=msm8x53
             androidboot.bootdevice=7824900.sdhci firmware_class.path=/oem/firmware
             androidboot.selinux=permissive
```

## Known Workarounds in the Workflow

- **roomservice.py**: Replaced with a no-op. It would try to fetch the device from OMNI Gerrit (not there), and also has Python 2/3 issues.
- **check_radio_versions.py**: Replaced with a no-op. No radio images needed for recovery builds.
- **`post_process_props.py` patch**: `iteritems()` → `items()` via sed (Python 3 safety net, even though `python` = Python 2).
