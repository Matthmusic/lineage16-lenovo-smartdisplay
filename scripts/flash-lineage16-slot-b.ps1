[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('auto', 'fastboot', 'edl')]
    [string]$Transport = 'auto',

    [string]$ArtifactDir,
    [string]$BootImage,
    [string]$SystemImage,
    [string]$VendorImage,
    [string]$VbmetaImage,
    [string]$DtboImage,
    [string]$PythonExe,
    [string]$LoaderPath,

    [switch]$ArmSlotSwitch,
    [switch]$Reboot,
    [switch]$AutoRollbackOnNoAdb
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

function Invoke-Checked {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Wait-ForFastboot {
    param(
        [string]$FastbootExe,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $output = (& $FastbootExe devices | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($output)) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Wait-ForAdb {
    param(
        [string]$AdbExe,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $output = (& $AdbExe devices | Out-String)
        if ($LASTEXITCODE -eq 0 -and $output -match '\sdevice(\s|$)') {
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Get-CurrentSlot {
    param(
        [string]$AdbExe,
        [string]$FastbootExe
    )

    if ($AdbExe) {
        $slot = (& $AdbExe shell getprop ro.boot.slot_suffix 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $slot) {
            return $slot.TrimStart('_')
        }
    }

    if ($FastbootExe) {
        $lines = & $FastbootExe getvar current-slot 2>&1
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $lines) {
                if ($line -match 'current-slot:\s*([ab])') {
                    return $Matches[1]
                }
            }
        }
    }

    throw 'Unable to determine the active slot.'
}

function Get-ImagePath {
    param(
        [string]$ExplicitPath,
        [string]$ArtifactDir,
        [string[]]$Candidates,
        [switch]$Optional
    )

    if ($ExplicitPath) {
        return (Resolve-Path $ExplicitPath).Path
    }

    foreach ($candidate in $Candidates) {
        $path = Join-Path $ArtifactDir $candidate
        if (Test-Path $path) {
            return (Resolve-Path $path).Path
        }
    }

    if ($Optional) {
        return $null
    }

    throw "Missing build artifact. Tried: $($Candidates -join ', ') in $ArtifactDir"
}

function Assert-ImageSize {
    param(
        [string]$Path,
        [int64]$MaxBytes,
        [string]$Partition
    )

    if (-not $Path) {
        return
    }

    $size = (Get-Item $Path).Length
    if ($size -gt $MaxBytes) {
        throw "Image too large for ${Partition}: $size bytes > $MaxBytes bytes ($Path)"
    }
}

function Test-Qualcomm9008 {
    $device = Get-PnpDevice -PresentOnly | Where-Object {
        $_.InstanceId -match 'VID_05C6&PID_9008' -or $_.FriendlyName -match '9008|QDLoader|QUSB__BULK'
    } | Select-Object -First 1
    return $null -ne $device
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$defaultArtifactDir = '\\wsl$\Ubuntu-20.04-Lineage16\build\lineage16-blueberry\out\target\product\blueberry'
$configPath = Join-Path $projectRoot 'memory\lineage16-wsl.json'

if ([string]::IsNullOrWhiteSpace($ArtifactDir)) {
    if (Test-Path $configPath) {
        try {
            $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
            if ($config.artifact_root) {
                $ArtifactDir = [string]$config.artifact_root
            }
        }
        catch {
            $ArtifactDir = $defaultArtifactDir
        }
    }

    if ([string]::IsNullOrWhiteSpace($ArtifactDir)) {
        $ArtifactDir = $defaultArtifactDir
    }
}

$adbExe = Resolve-ToolPath -Names @('adb.exe', 'adb') -Fallback 'C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\adb.exe'
$fastbootExe = Resolve-ToolPath -Names @('fastboot.exe', 'fastboot') -Fallback 'C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\fastboot.exe'

if (-not $adbExe) {
    throw 'adb.exe not found.'
}

if (-not $fastbootExe) {
    throw 'fastboot.exe not found.'
}

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $PythonExe = Join-Path $projectRoot '.venv-edl\Scripts\python.exe'
}
if ([string]::IsNullOrWhiteSpace($LoaderPath)) {
    $LoaderPath = 'C:\Users\Matthieu MAUREL\Downloads\amber_blueberry_firehose\amber_bluebbery_prog_emmc_firehose_8953_ddr.mbn'
}

$PythonExe = if (Test-Path $PythonExe) { (Resolve-Path $PythonExe).Path } else { $null }
$LoaderPath = if (Test-Path $LoaderPath) { (Resolve-Path $LoaderPath).Path } else { $null }

$images = [ordered]@{
    boot_b = @{
        path = Get-ImagePath -ExplicitPath $BootImage -ArtifactDir $ArtifactDir -Candidates @('boot.img')
        max = 33554432
    }
    system_b = @{
        path = Get-ImagePath -ExplicitPath $SystemImage -ArtifactDir $ArtifactDir -Candidates @('system.img')
        max = 536870912
    }
    vendor_b = @{
        path = Get-ImagePath -ExplicitPath $VendorImage -ArtifactDir $ArtifactDir -Candidates @('vendor.img')
        max = 134217728
    }
    vbmeta_b = @{
        path = Get-ImagePath -ExplicitPath $VbmetaImage -ArtifactDir $ArtifactDir -Candidates @('vbmeta.img')
        max = 65536
    }
}

$dtboPath = Get-ImagePath -ExplicitPath $DtboImage -ArtifactDir $ArtifactDir -Candidates @('dtbo.img') -Optional
if ($dtboPath) {
    $images['dtbo_b'] = @{
        path = $dtboPath
        max = 33554432
    }
}

foreach ($entry in $images.GetEnumerator()) {
    Assert-ImageSize -Path $entry.Value.path -MaxBytes $entry.Value.max -Partition $entry.Key
}

$currentSlot = Get-CurrentSlot -AdbExe $adbExe -FastbootExe $fastbootExe
if ($currentSlot -ne 'a') {
    throw "Refusing to flash slot b while current slot is '$currentSlot'."
}

$effectiveTransport = $Transport
if ($effectiveTransport -eq 'auto') {
    $fastbootDevices = (& $fastbootExe devices | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($fastbootDevices)) {
        $effectiveTransport = 'fastboot'
    }
    else {
        & $adbExe reboot bootloader
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to reboot to bootloader for slot b flash.'
        }
        if (-not (Wait-ForFastboot -FastbootExe $fastbootExe)) {
            if (Test-Qualcomm9008) {
                $effectiveTransport = 'edl'
            }
            else {
                throw 'Device did not appear in fastboot and is not in 9008 either.'
            }
        }
        else {
            $effectiveTransport = 'fastboot'
        }
    }
}

Write-Host "Using transport: $effectiveTransport"

if ($effectiveTransport -eq 'fastboot') {
    foreach ($entry in $images.GetEnumerator()) {
        $partition = $entry.Key
        $path = $entry.Value.path
        if ($PSCmdlet.ShouldProcess($partition, "fastboot flash $path")) {
            Invoke-Checked -Exe $fastbootExe -Arguments @('flash', $partition, $path) -FailureMessage "fastboot flash failed for $partition"
        }
    }

    if ($ArmSlotSwitch -and $PSCmdlet.ShouldProcess('slot b', 'fastboot set_active')) {
        Invoke-Checked -Exe $fastbootExe -Arguments @('set_active', 'b') -FailureMessage 'fastboot set_active b failed.'
    }

    if ($Reboot -and $PSCmdlet.ShouldProcess('device', 'fastboot reboot')) {
        Invoke-Checked -Exe $fastbootExe -Arguments @('reboot') -FailureMessage 'fastboot reboot failed.'
        if ($ArmSlotSwitch) {
            if (-not (Wait-ForAdb -AdbExe $adbExe)) {
                Write-Warning 'No adb transport detected within 120 seconds after slot b reboot.'
                if ($AutoRollbackOnNoAdb) {
                    & (Join-Path $PSScriptRoot 'rollback-blueberry-slot-a.ps1') -PreferFastboot -Reboot
                    if ($LASTEXITCODE -ne 0) {
                        throw 'Auto-rollback to slot a failed after slot b boot timeout.'
                    }
                }
            }
        }
    }
}
elseif ($effectiveTransport -eq 'edl') {
    if (-not $PythonExe -or -not $LoaderPath) {
        throw 'EDL transport requested but Python or loader is missing.'
    }

    $edlScript = Join-Path $projectRoot 'tools\edl\edl.py'
    $slotResetScript = Join-Path $PSScriptRoot 'edl-firehose-slot-reset.py'

    foreach ($entry in $images.GetEnumerator()) {
        $partition = $entry.Key
        $path = $entry.Value.path
        if ($PSCmdlet.ShouldProcess($partition, "edl write $path")) {
            & $PythonExe $edlScript '--memory=emmc' "--loader=$LoaderPath" '--vid=0x05c6' '--pid=0x9008' 'w' $partition $path
            if ($LASTEXITCODE -ne 0) {
                throw "edl write failed for $partition"
            }
        }
    }

    if ($ArmSlotSwitch -and $PSCmdlet.ShouldProcess('slot b', 'edl setactiveslot')) {
        & $PythonExe $slotResetScript 'b'
        if ($LASTEXITCODE -ne 0) {
            throw 'edl slot switch to b failed.'
        }
    }
}
else {
    throw "Unsupported transport: $effectiveTransport"
}

Write-Host "Slot b payload staged from $ArtifactDir"
