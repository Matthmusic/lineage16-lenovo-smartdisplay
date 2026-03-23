[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('a', 'b', 'both')]
    [string]$Slot = 'both',

    [ValidateSet('a', 'b')]
    [string]$SetActive = 'a',

    [string]$BootImage,

    [switch]$Reboot
)

$ErrorActionPreference = 'Stop'

function Resolve-Fastboot {
    $cmd = Get-Command fastboot.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $fallback = 'C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\fastboot.exe'
    if (Test-Path $fallback) {
        return $fallback
    }

    throw 'fastboot.exe was not found in PATH or the Touch Portal platform-tools location.'
}

$projectRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($BootImage)) {
    $BootImage = Join-Path $projectRoot 'backup\boot_a_32mb.img'
}

$BootImage = (Resolve-Path $BootImage).Path
$bootItem = Get-Item $BootImage
if ($bootItem.Length -ne 33554432) {
    throw "Expected an exact 32 MiB boot image, got $($bootItem.Length) bytes: $BootImage"
}

$fastboot = Resolve-Fastboot
$devices = (& $fastboot devices | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($devices)) {
    throw 'No device detected in fastboot mode.'
}

$targets = switch ($Slot) {
    'a' { @('boot_a') }
    'b' { @('boot_b') }
    'both' { @('boot_a', 'boot_b') }
}

foreach ($partition in $targets) {
    if ($PSCmdlet.ShouldProcess($partition, "flash $BootImage")) {
        & $fastboot flash $partition $BootImage
        if ($LASTEXITCODE -ne 0) {
            throw "fastboot flash failed for $partition"
        }
    }
}

if ($PSCmdlet.ShouldProcess("slot $SetActive", 'set_active')) {
    & $fastboot set_active $SetActive
    if ($LASTEXITCODE -ne 0) {
        throw "fastboot set_active failed for slot $SetActive"
    }
}

if ($Reboot -and $PSCmdlet.ShouldProcess('device', 'reboot')) {
    & $fastboot reboot
    if ($LASTEXITCODE -ne 0) {
        throw 'fastboot reboot failed'
    }
}

Write-Host "Restored stock boot image: $BootImage"
Write-Host "Flashed partitions: $($targets -join ', ')"
Write-Host "Active slot: $SetActive"
