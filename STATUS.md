# Smart Display Status
*Updated: 2026-03-13*

## Current State

- Device is alive again.
- Screen is no longer black.
- Current foreground launcher is `com.android.iotlauncher/.DefaultIoTLauncher`.
- `adb` works again with serial `HUA07UK0`.
- USB parent device is now `USB\VID_05C6&PID_901D` on the standard Microsoft composite driver.
- The factory app `com.a3nod.lenovo.sparrowfactory` is disabled for user `0`, so it no longer steals focus after boot.
- The Qualcomm DIAG child interface still has a broken Windows driver, but it is not blocking normal Android access.

## What Happened

The device was soft-bricked after flashing an unvalidated TWRP `boot.img` to `boot_b` and switching the active slot to `b`.

That caused:

- black screen
- loss of `fastboot`
- loss of `adb`
- fallback to Qualcomm `900E`

The device was brought back by moving from `900E` to `9008`, restoring the exact factory GPT, reflashing a working factory image set, fixing the Windows USB binding for `901D`, regaining `adb`, then forcing the normal IoT launcher and disabling the factory test launcher.

## Final Technical State

- `adb devices -l` shows:
  - `HUA07UK0 device product:iot_msm8x53_som model:iot_msm8x53_som device:msm8x53_som`
- Current running build:
  - `iot_msm8x53_som-userdebug 7.0 NYC eng.ego.20180510.175752 test-keys`
- Current on-screen UI:
  - `Android Things 0.4.5-N`
  - `Not connected peripheral I/O ports`
- Current fingerprint:
  - `Things/iot_msm8x53_som/msm8x53_som:7.0/NYC/ego05101757:userdebug/test-keys`
- Current focused activity:
  - `com.android.iotlauncher/.DefaultIoTLauncher`
- Disabled package:
  - `com.a3nod.lenovo.sparrowfactory`

## Important Files

- Detailed rescue report:
  - `RECOVERY_REPORT.md`
- Dashboard:
  - `scripts/device-dashboard.py`
  - `scripts/device-dashboard.html`
- Exact factory restore path used to recover a bootable state:
  - `scripts/edl-restore-blueberry-factory.ps1`
- Prepared fallback to restore the local backup set on the correct GPT:
  - `scripts/edl-restore-blueberry-normal.ps1`

## What Is No Longer True

The old status assumptions are obsolete and must not be reused:

- the device is not stuck in `900E`
- the device is not stuck in `9008`
- `fastboot` is not the active recovery path anymore
- "TWRP compiled but not flashed" is no longer relevant
- the old `900E/9008` recovery path is no longer the active blocker

## Next Practical Steps

1. Keep the current Android Things build on `slot a` as the golden baseline.
   A real baseline snapshot now exists under `memory/golden-baseline/20260312-162451`.
2. Use the new parallel Lineage 16 workflow:
   - manifest: `blueberry_manifest_lineage16.xml`
   - seed trees: `lineage16_seed/device/lenovo/blueberry` and `lineage16_seed/vendor/lenovo/blueberry`
   - WSL bootstrap: `scripts/bootstrap-lineage16-blueberry-wsl.ps1`
3. Use only the guarded bring-up path for custom flashes:
   - baseline capture: `scripts/freeze-blueberry-golden-baseline.ps1`
   - slot b flash: `scripts/flash-lineage16-slot-b.ps1`
   - rollback to slot a: `scripts/rollback-blueberry-slot-a.ps1`
4. The dashboard is now porting-oriented:
   - `Port Mode` by default
   - `Recovery Mode` must be armed explicitly before any EDL action is shown
5. Do not attempt another TWRP or any custom recovery before Lineage 16 reaches boot + adb on `slot b`.

## Active Blocker

- The Lineage 16 source bootstrap exists, but full `repo sync` and build are currently blocked by WSL distro placement.
- The root cause is infrastructure, not the porting scaffolding:
  - `C:` still has too little free space for a full Android build workflow
  - the original `Ubuntu-22.04` distro is still registered on `C:`
  - the old partial copy on `E:` has been quarantined as `E:\WSL\Ubuntu-22.04-stale-copy`
  - `wsl --install ... --location` is rejected on this host for legacy distro installs
  - cloning `Ubuntu-22.04` to a new distro on `E:` failed because the source export is dirty
- A dedicated recovery script is now ready:
  - `scripts/recover-lineage16-wsl.ps1`
- Working directory cleanup is in progress:
  - `E:\SMARTDISPLAY` is now the intended primary Windows workspace
  - `memory/lineage16-wsl.json` points the dashboard and guarded flash flow at the planned `Ubuntu-20.04` build distro on `E:`
- The intended next path is:
  1. provision a clean secondary distro on `E:` through a non-legacy import/install path
  2. run `scripts/recover-lineage16-wsl.ps1`
  3. continue bootstrap/sync/build on the dedicated `E:` distro
