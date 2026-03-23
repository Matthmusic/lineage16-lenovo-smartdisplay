# Lenovo Smart Display Revival Report
*Updated: 2026-03-12*

## Goal

Document exactly how the Lenovo Smart Display 10" (`blueberry`) was brought back from a post-TWRP soft-brick to a booting Android state with working `adb`.

This report replaces the old mental model of:

- black screen forever
- no `fastboot`
- no `adb`
- impossible recovery without guessing

That is no longer the situation.

## Final Result

At the end of the recovery:

- the device boots again
- the screen is alive
- Android is reachable through `adb`
- the active UI is the IoT launcher, not the factory test UI
- the factory launcher package is disabled for user `0`

Current confirmed state:

- serial: `HUA07UK0`
- `adb` state: `device`
- current build: `iot_msm8x53_som-userdebug 7.0 NYC eng.ego.20180510.175752 test-keys`
- current visible screen: `Android Things 0.4.5-N`
- current footer message: `Not connected peripheral I/O ports`
- current fingerprint: `Things/iot_msm8x53_som/msm8x53_som:7.0/NYC/ego05101757:userdebug/test-keys`
- current focused activity: `com.android.iotlauncher/.DefaultIoTLauncher`
- disabled package: `com.a3nod.lenovo.sparrowfactory`

## Root Cause

The breakage started after this sequence:

1. flash TWRP `boot.img` to `boot_b`
2. switch active slot to `b`
3. reboot

That image was not actually bootable on this device.

The result was not a dead motherboard. It was a boot-chain failure that dropped the Qualcomm SoC into emergency USB states.

## Observable Failure States

The device passed through several distinct states:

### 1. Black screen + no Android transport

- no display output
- no `adb`
- no `fastboot`

### 2. Qualcomm `900E`

Windows showed:

- `Qualcomm HS-USB Diagnostics 900E`
- later `QUSB__BULK` on `VID_05C6&PID_900E`

Meaning:

- the SoC was still alive
- the boot ROM still answered
- but the device was not yet in the flashable Qualcomm mode

### 3. Qualcomm `9008`

After hardware help, the device reached:

- `QDLoader 9008`
- later `QUSB__BULK` on `VID_05C6&PID_9008`

This was the first truly writable state.

### 4. Android USB `901D`

After the exact factory restore, the device switched to:

- `VID_05C6&PID_901D`

This is not EDL. It is an Android USB mode carrying `diag,adb`.

That transition was the first hard proof that the low-level boot chain was alive again.

## What Did Not Work

Several paths were tested and ruled out:

### Wrong QFIL XML path

An unrelated `CD-18781Y` package was available in QFIL, but its layout did not match the Smart Display A/B partition map.

That route was rejected because:

- partition names did not match the local backup layout
- it risked writing the wrong sectors

### Pure software recovery from `900E`

Windows plus `edl` could talk Sahara in `900E`, but that was not enough to flash storage reliably.

What worked there:

- Sahara handshake
- reset
- basic ROM-level communication

What did not work there:

- reliable firehose upload for full recovery
- real storage repair

### Partial restore loops

Before the exact GPT was known, multiple partial restores were attempted:

- boot only
- slot A boot chain
- large stock slot restore
- wipe userdata

These were not sufficient because the partition map itself was wrong.

## The Actual Turning Point

The real breakthrough came from two discoveries:

### 1. The device needed a real `9008` path

A homemade EDL cable was used to force the Qualcomm device from `900E` to `9008`.

Without that step, there was no reliable write path.

### 2. The reconstructed GPT was wrong

The workspace already contained the exact local package:

- `C:\Users\Matthieu MAUREL\Downloads\Blueberry-factory-S0.28.20-4757977-debug`

From that package, `partition-table.img` was parsed and used to recover the real factory GPT.

That changed everything:

- partition offsets became exact
- partition sizes became exact
- restore logic stopped guessing

## Recovery Timeline

## Phase 1: Regain a flashable Qualcomm state

Steps:

1. Rebind the Qualcomm USB device to `WinUSB` where needed.
2. Use a homemade EDL cable to force `9008`.
3. Verify that Windows sees a real flashable Qualcomm transport.

Outcome:

- `9008` obtained
- firehose communication possible

## Phase 2: Repair the partition map

The local factory package was used to extract the exact GPT.

Actions:

1. split `partition-table.img` into primary and backup GPT blocks
2. write exact primary GPT
3. write exact backup GPT
4. read GPT back to confirm partition names and offsets

Outcome:

- exact factory layout restored
- `boot_a`, `boot_b`, `system_a`, `system_b`, `vendor_a`, `vendor_b`, and other partitions could be written safely

## Phase 3: Restore a bootable image set

The script path used for that phase:

- `scripts/edl-restore-blueberry-factory.ps1`

This wrote:

- exact GPT
- working boot chain
- system/vendor/oem partitions
- supporting singleton partitions
- userdata erase

The result was not yet the final user environment, but it was enough to make the device boot.

## Phase 4: First visible resurrection

After the exact factory restore, the device no longer fell back to `9008`.

Instead:

- it booted visibly
- the screen showed `sparrow factory`
- Windows exposed `VID_05C6&PID_901D`

That meant:

- the device was no longer in a deep brick state
- Android was running
- the visible UI was a factory test application, not the normal launcher

## Phase 5: Fix Windows USB on `901D`

The `901D` parent device was initially broken by an old unsigned Qualcomm filter.

Problem:

- Windows attached `qcfilter`
- Code 52
- no reliable `adb`

Fix:

1. replace the parent binding with the Microsoft composite USB driver
2. keep the ADB child interface on `WinUSB`
3. add Qualcomm vendor ID `0x05c6` to:
   - `C:\Users\Matthieu MAUREL\.android\adb_usb.ini`

Outcome:

- `adb` became visible
- Android shell access returned

## Phase 6: Identify the real UI problem

Once `adb` was back, the foreground activity was inspected.

What was found:

- the running package was `com.a3nod.lenovo.sparrowfactory`
- its activities included:
  - `.NavigationActivity`
  - `.MoreActivity`

At the same time, the normal launcher was already present:

- `com.android.iotlauncher`

So the issue was no longer low-level boot. It was simply that the factory app was the active launcher.

## Phase 7: Force the normal launcher

Actions:

1. explicitly start:
   - `com.android.iotlauncher/.IoTHome`
2. confirm the activity stack
3. force-stop the factory app
4. relaunch the normal IoT launcher

That switched focus, but persistence across reboot still needed to be checked.

## Phase 8: Prevent the factory app from taking over again

The cleanest reversible move was:

- disable `com.a3nod.lenovo.sparrowfactory` for user `0`

Command outcome:

- `Package com.a3nod.lenovo.sparrowfactory new state: disabled-user`

Then the device was rebooted and observed.

## Phase 9: Confirm persistence after reboot

After reboot:

- the device came back on `901D`
- `adb` returned automatically
- it did not fall back to `9008`
- current focused activity remained the normal IoT launcher path

Confirmed foreground:

- `com.android.iotlauncher/.DefaultIoTLauncher`

This is the current stable recovered state.

## Files Added or Updated During Recovery

### Core recovery scripts

- `scripts/edl-restore-blueberry-factory.ps1`
- `scripts/edl-restore-blueberry-normal.ps1`
- `scripts/edl-firehose-slot-reset.py`

### Dashboard and operator tooling

- `scripts/device-dashboard.py`
- `scripts/device-dashboard.html`
- `scripts/start-device-dashboard.ps1`

### Local transport fix

- `C:\Users\Matthieu MAUREL\.android\adb_usb.ini`

## What The Device Is Running Right Now

Important nuance:

The device is alive, but the current running build is not the original Android Things 8.1 backup image set.

Current running build:

- Android 7.0 userdebug
- test-keys
- IoT launcher active
- screen text `Android Things 0.4.5-N / Not connected peripheral I/O ports`

This is enough to prove that the hardware and Android boot path are alive again.

## What Remains Optional

There is still an optional cleanup path if the goal is to return to the backup-derived environment rather than stay on the current recovered debug build.

Prepared fallback:

- `scripts/edl-restore-blueberry-normal.ps1`

Purpose:

- keep the correct factory GPT
- rewrite the partition set from the local backups
- try to move from the current recovered debug image to the locally backed-up normal image set

That is a next-step decision, not a prerequisite for saying the device was revived.

## Operational Lessons

### 1. `900E` is not enough

If the device is stuck in `900E`, you may still be able to talk to the boot ROM, but that does not mean the storage is repairable yet.

### 2. `9008` is the real write path

The meaningful recovery starts only once the device is in a true flashable Qualcomm mode.

### 3. Wrong rawprogram XML is dangerous

If the package layout does not match the device GPT, do not flash it blind.

### 4. Exact GPT matters more than "mostly right"

The recovery only became repeatable after using the exact `partition-table.img` for this model.

### 5. "Device alive" is not the same as "right launcher"

The move from dead screen to `sparrow factory` was already a recovery success.
The final polish was simply taking back the foreground UI.

## Bottom Line

The Smart Display was not magically revived by one flash.

It came back because the recovery path was made precise:

1. force `9008`
2. use the exact factory GPT
3. restore a known-good bootable image set
4. repair Windows USB on `901D`
5. recover `adb`
6. replace the factory UI with the normal IoT launcher
7. disable the factory launcher so it stays out of the way

Current outcome:

- the device is alive
- Android is booting
- `adb` works
- the normal launcher is in front
- the old "hard dead / only 9008 forever" narrative is obsolete
