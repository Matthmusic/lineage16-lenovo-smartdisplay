[CmdletBinding()]
param(
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

function Resolve-ToolPath {
    param(
        [string[]]$Names,
        [string]$Fallback
    )

    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }

    if ($Fallback -and (Test-Path $Fallback)) {
        return (Resolve-Path $Fallback).Path
    }

    return $null
}

function New-Utf8DirectoryFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path $Path -Parent
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Content | Out-File -FilePath $Path -Encoding utf8
}

function Invoke-Adb {
    param(
        [string[]]$Arguments
    )

    $output = & $script:AdbExe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed: $($Arguments -join ' ')"
    }
    return ($output | Out-String).Trim()
}

function Get-AdbProp {
    param(
        [string]$Name
    )

    return (Invoke-Adb -Arguments @('shell', 'getprop', $Name))
}

function Get-Inventory {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    Get-ChildItem -Recurse -File $Path |
        Sort-Object FullName |
        Select-Object FullName, Length, LastWriteTimeUtc
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $projectRoot "memory\golden-baseline\$timestamp"
}

$AdbExe = Resolve-ToolPath -Names @('adb.exe', 'adb') -Fallback 'C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\adb.exe'
if (-not $AdbExe) {
    throw 'adb.exe not found.'
}

$adbDevices = & $AdbExe devices -l
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to query adb devices.'
}

$deviceLine = ($adbDevices | Select-String 'device product:').Line | Select-Object -First 1
if (-not $deviceLine) {
    throw 'No adb device detected. Refusing to freeze a baseline without a live device.'
}

$usbSnapshot = Get-PnpDevice -PresentOnly | Where-Object {
    $_.InstanceId -match 'VID_05C6&PID_9008|VID_05C6&PID_900E|VID_05C6&PID_901D|VID_18D1' -or
    $_.FriendlyName -match '9008|900E|901D|QUSB|Qualcomm|Fastboot|Android|ADB'
} | Sort-Object FriendlyName | Select-Object Status, Class, FriendlyName, InstanceId

$baseline = [ordered]@{
    captured_at = (Get-Date).ToString('o')
    adb_device = $deviceLine.Trim()
    slot_suffix = Get-AdbProp 'ro.boot.slot_suffix'
    build_display_id = Get-AdbProp 'ro.build.display.id'
    build_fingerprint = Get-AdbProp 'ro.build.fingerprint'
    build_release = Get-AdbProp 'ro.build.version.release'
    verified_boot_state = Get-AdbProp 'ro.boot.verifiedbootstate'
    usb_config = Get-AdbProp 'sys.usb.config'
    product_device = Get-AdbProp 'ro.product.device'
    product_model = Get-AdbProp 'ro.product.model'
    packages = [ordered]@{
        iotlauncher = (Invoke-Adb -Arguments @('shell', 'pm', 'path', 'com.android.iotlauncher'))
        sparrowfactory = (Invoke-Adb -Arguments @('shell', 'pm', 'path', 'com.a3nod.lenovo.sparrowfactory'))
        disabled = (Invoke-Adb -Arguments @('shell', 'pm', 'list', 'packages', '-d'))
    }
}

$hashTargets = @(
    'scripts\edl-restore-blueberry-factory.ps1',
    'scripts\edl-restore-blueberry-normal.ps1',
    'scripts\restore-stock-boot.ps1',
    'scripts\edl-firehose-slot-reset.py',
    'backup\boot_a_32mb.img',
    'blueberry_manifest_lineage16.xml',
    'C:\Users\Matthieu MAUREL\Downloads\Blueberry-factory-S0.28.20-4757977-debug\partition-table.img'
) | Where-Object { Test-Path $_ }

$hashes = foreach ($path in $hashTargets) {
    $resolved = (Resolve-Path $path).Path
    $hash = Get-FileHash -Algorithm SHA256 -Path $resolved
    [ordered]@{
        path = $resolved
        algorithm = $hash.Algorithm
        sha256 = $hash.Hash
        length = (Get-Item $resolved).Length
    }
}

$inventories = [ordered]@{
    backup = Get-Inventory (Join-Path $projectRoot 'backup')
    restore_trimmed = Get-Inventory (Join-Path $projectRoot 'restore_trimmed')
    vendor_blueberry = Get-Inventory (Join-Path $projectRoot 'vendor_blueberry')
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
($baseline | ConvertTo-Json -Depth 8) | Out-File -FilePath (Join-Path $OutputDir 'baseline.json') -Encoding utf8
($usbSnapshot | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $OutputDir 'usb_snapshot.json') -Encoding utf8
($hashes | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $OutputDir 'recovery_hashes.json') -Encoding utf8
($inventories | ConvertTo-Json -Depth 6) | Out-File -FilePath (Join-Path $OutputDir 'artifact_inventory.json') -Encoding utf8
New-Utf8DirectoryFile -Path (Join-Path $OutputDir 'adb_devices.txt') -Content (($adbDevices | Out-String).Trim())
New-Utf8DirectoryFile -Path (Join-Path $OutputDir 'operator_recovery_quickstart.txt') -Content @"
Blueberry golden baseline quickstart
===================================

1. Keep slot a as the known-good baseline.
2. Flash experimental builds to slot b only.
3. If slot b fails:
   - prefer fastboot rollback to slot a
   - otherwise use scripts\edl-restore-blueberry-normal.ps1
4. Do not flash GPT, Qualcomm boot chain, or eMMC boot partitions during normal bring-up.
5. Do not test TWRP or a custom recovery before Lineage 16 boots with adb.
"@

Write-Host "Golden baseline captured in $OutputDir"
