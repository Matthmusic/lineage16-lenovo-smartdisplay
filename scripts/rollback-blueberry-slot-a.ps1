[CmdletBinding()]
param(
    [ValidateSet('normal', 'factory')]
    [string]$EdlBundle = 'normal',

    [switch]$PreferFastboot,
    [switch]$Reboot,
    [switch]$RefreshStockBoot
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

function Test-Fastboot {
    param([string]$FastbootExe)

    $output = (& $FastbootExe devices | Out-String).Trim()
    return ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($output))
}

function Wait-ForFastboot {
    param(
        [string]$FastbootExe,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Fastboot -FastbootExe $FastbootExe) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Test-Qualcomm9008 {
    $device = Get-PnpDevice -PresentOnly | Where-Object {
        $_.InstanceId -match 'VID_05C6&PID_9008' -or $_.FriendlyName -match '9008|QDLoader|QUSB__BULK'
    } | Select-Object -First 1
    return $null -ne $device
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$adbExe = Resolve-ToolPath -Names @('adb.exe', 'adb') -Fallback 'C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\adb.exe'
$fastbootExe = Resolve-ToolPath -Names @('fastboot.exe', 'fastboot') -Fallback 'C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\fastboot.exe'

if (-not $adbExe) {
    throw 'adb.exe not found.'
}
if (-not $fastbootExe) {
    throw 'fastboot.exe not found.'
}

$usedPath = $null

if (-not (Test-Fastboot -FastbootExe $fastbootExe)) {
    if ($PreferFastboot) {
        & $adbExe reboot bootloader
        if ($LASTEXITCODE -eq 0 -and (Wait-ForFastboot -FastbootExe $fastbootExe)) {
            $null = $true
        }
    }
}

if (Test-Fastboot -FastbootExe $fastbootExe) {
    if ($RefreshStockBoot) {
        & (Join-Path $PSScriptRoot 'restore-stock-boot.ps1') -Slot both -SetActive a -Reboot:$Reboot
        if ($LASTEXITCODE -ne 0) {
            throw 'Stock boot refresh failed during rollback.'
        }
        $usedPath = 'fastboot+stock-boot'
    }
    else {
        & $fastbootExe set_active a
        if ($LASTEXITCODE -ne 0) {
            throw 'fastboot set_active a failed.'
        }
        if ($Reboot) {
            & $fastbootExe reboot
            if ($LASTEXITCODE -ne 0) {
                throw 'fastboot reboot failed after slot a selection.'
            }
        }
        $usedPath = 'fastboot-slot-a'
    }
}
elseif (Test-Qualcomm9008) {
    $scriptName = if ($EdlBundle -eq 'factory') {
        'edl-restore-blueberry-factory.ps1'
    }
    else {
        'edl-restore-blueberry-normal.ps1'
    }
    & (Join-Path $PSScriptRoot $scriptName)
    if ($LASTEXITCODE -ne 0) {
        throw "EDL rollback failed via $scriptName."
    }
    $usedPath = $scriptName
}
else {
    throw 'No fastboot or Qualcomm 9008 path available for rollback.'
}

Write-Host "Rollback path used: $usedPath"
