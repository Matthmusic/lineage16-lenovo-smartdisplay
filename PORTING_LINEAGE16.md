# LineageOS 16 Porting Workflow

## Current Starting Point

- Device is alive on Android Things and reachable through `adb`.
- Current active slot is expected to stay `_a` during bring-up.
- Golden baseline snapshot is captured under `memory/golden-baseline/`.
- Parallel Lineage 16 workspace is bootstrapped in WSL at `/build/lineage16-blueberry`.
- Primary Windows workspace is now intended to be `E:\SMARTDISPLAY`.
- Planned clean WSL build target is `Ubuntu-20.04` on `E:`, tracked in `memory/lineage16-wsl.json`.
- Current infrastructure blocker is distro provisioning on `E:`:
  - the original `Ubuntu-22.04` distro is still registered on `C:`
  - `C:` remains too small for a full Android build workflow
  - the stale partial copy on `E:` is quarantined as `E:\WSL\Ubuntu-22.04-stale-copy`
  - `wsl --install ... --location` is rejected on this host for legacy distro installs
  - cloning the existing `Ubuntu-22.04` via `wsl --export | wsl --import` failed because the source distro carries a dirty `/build` tree

## Current WSL Recovery Path

- Recovery script:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\recover-lineage16-wsl.ps1`
- What it does:
  - creates or re-registers a dedicated build distro on `E:`
  - writes `memory/lineage16-wsl.json`
  - relaunches the guarded Lineage 16 bootstrap on that distro
- Default target is now a clean `Ubuntu-20.04` build distro on `E:`.
- If the copied VHD on `E:` is ever trusted again:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\recover-lineage16-wsl.ps1 -UseExistingVhd -Distro Ubuntu-22.04-Lineage16 -InstallLocation E:\WSL\Ubuntu-22.04-Lineage16`
- Known current limitation:
  - on this machine, the script still needs a non-legacy install/import path because `wsl --install ... --location` is refused by WSL

## Parallel Source Layout

- Local manifest: `blueberry_manifest_lineage16.xml`
- Seed device tree: `lineage16_seed/device/lenovo/blueberry`
- Seed vendor tree: `lineage16_seed/vendor/lenovo/blueberry`

The seed tree is intentionally separate from `lineage_src/device_blueberry`. Do not port in place.

## Operator Scripts

- Capture baseline:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\freeze-blueberry-golden-baseline.ps1`
- Bootstrap WSL tree:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-lineage16-blueberry-wsl.ps1`
- Recover WSL on `E:` and bootstrap in one step:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\recover-lineage16-wsl.ps1`
- Flash Lineage 16 on slot `b`:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\flash-lineage16-slot-b.ps1 -ArmSlotSwitch -Reboot`
- Roll back to slot `a`:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\rollback-blueberry-slot-a.ps1 -PreferFastboot -Reboot`

## Guardrails

- Keep `slot a` as the known-good baseline until Lineage 16 reaches boot + adb on `slot b`.
- Normal bring-up must not write GPT, Qualcomm boot chain partitions, or eMMC boot partitions.
- Do not test TWRP or any custom recovery before a stable Lineage 16 boot with adb.
- The vendor fallback from `blueberry` to `starfire` is explicit and temporary.
- Recovery actions in the dashboard stay hidden until `Recovery Mode` is armed.

## First Success Criteria

- `breakfast blueberry` succeeds in `/build/lineage16-blueberry`
- Minimal artifacts exist:
  - `boot.img`
  - `system.img`
  - `vendor.img`
  - `vbmeta.img`
- Slot `b` boots LineageOS 16 and `adb devices` reports `device`
