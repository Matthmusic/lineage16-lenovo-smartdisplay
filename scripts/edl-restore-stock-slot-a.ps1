[CmdletBinding()]
param(
    [string]$PythonExe,
    [string]$ProjectRoot,
    [string]$LoaderPath,
    [int]$TimeoutSeconds = 0
)

$ErrorActionPreference = 'Stop'

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path $PSScriptRoot -Parent
}

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $PythonExe = Join-Path $ProjectRoot '.venv-edl\Scripts\python.exe'
}

if ([string]::IsNullOrWhiteSpace($LoaderPath)) {
    $LoaderPath = 'C:\Users\Matthieu MAUREL\Downloads\amber_blueberry_firehose\amber_bluebbery_prog_emmc_firehose_8953_ddr.mbn'
}

$PythonExe = (Resolve-Path $PythonExe).Path
$LoaderPath = (Resolve-Path $LoaderPath).Path

$edlScript = Join-Path $ProjectRoot 'tools\edl\edl.py'
$slotResetScript = Join-Path $ProjectRoot 'scripts\edl-firehose-slot-reset.py'
if (-not (Test-Path $edlScript)) {
    throw "edl.py not found: $edlScript"
}
if (-not (Test-Path $slotResetScript)) {
    throw "slot reset helper not found: $slotResetScript"
}

$images = @(
    @{ Partition = 'sbl1_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\sbl1_a_exact.img') },
    @{ Partition = 'aboot_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\aboot_a_exact.img') },
    @{ Partition = 'rpm_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\rpm_a_exact.img') },
    @{ Partition = 'tz_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\tz_a_exact.img') },
    @{ Partition = 'devcfg_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\devcfg_a_exact.img') },
    @{ Partition = 'cmnlib_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\cmnlib_a_exact.img') },
    @{ Partition = 'keymaster_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\keymaster_a_exact.img') },
    @{ Partition = 'oem_bootloader_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\oem_bootloader_a_exact.img') },
    @{ Partition = 'bluetooth_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\bluetooth_a_exact.img') },
    @{ Partition = 'drm_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\drm_a_exact.img') },
    @{ Partition = 'dsp_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\dsp_a_exact.img') },
    @{ Partition = 'modem_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\modem_a_exact.img') },
    @{ Partition = 'vbmeta_a'; File = (Join-Path $ProjectRoot 'backup\vbmeta_a_64k.img') },
    @{ Partition = 'boot_a'; File = (Join-Path $ProjectRoot 'backup\boot_a_32mb.img') },
    @{ Partition = 'misc'; File = (Join-Path $ProjectRoot 'backup\misc.img') },
    @{ Partition = 'system_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\system_a_exact.img') },
    @{ Partition = 'vendor_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\vendor_a_exact.img') },
    @{ Partition = 'oem_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\oem_a_exact.img') }
)

foreach ($item in $images) {
    if (-not (Test-Path $item.File)) {
        throw "Missing image for $($item.Partition): $($item.File)"
    }
}

$deadline = if ($TimeoutSeconds -gt 0) { (Get-Date).AddSeconds($TimeoutSeconds) } else { $null }

Write-Host 'Waiting for Qualcomm QDLoader 9008...'
while ($true) {
    $device = Get-PnpDevice -PresentOnly |
        Where-Object { $_.InstanceId -match 'VID_05C6&PID_9008' -or $_.FriendlyName -match '9008|QDLoader|QUSB__BULK' } |
        Select-Object -First 1

    if ($device) {
        Write-Host "Detected: $($device.FriendlyName)"
        break
    }

    if ($deadline -and (Get-Date) -ge $deadline) {
        throw 'Timed out waiting for Qualcomm QDLoader 9008.'
    }

    Start-Sleep -Seconds 2
}

$commonArgs = @(
    $edlScript,
    '--memory=emmc',
    "--loader=$LoaderPath",
    '--vid=0x05c6',
    '--pid=0x9008'
)

function Invoke-EdlChecked {
    param(
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    $output = & $PythonExe @Arguments 2>&1
    $output | ForEach-Object { Write-Host $_ }

    $joined = ($output | Out-String)
    if ($LASTEXITCODE -ne 0 -or
        $joined -match "Couldn't detect partition" -or
        $joined -match 'Error:' -or
        $joined -match 'Traceback') {
        throw $FailureMessage
    }
}

foreach ($item in $images) {
    $resolvedFile = (Resolve-Path $item.File).Path
    $sizeMiB = [Math]::Round((Get-Item $resolvedFile).Length / 1MB, 2)
    Write-Host "Writing $($item.Partition) ($sizeMiB MiB)..."
    Invoke-EdlChecked -Arguments ($commonArgs + @('w', $item.Partition, $resolvedFile)) -FailureMessage "edl write failed for $($item.Partition)."
}

Write-Host 'Forcing slot a and resetting device...'
& $PythonExe $slotResetScript
if ($LASTEXITCODE -ne 0) {
    throw 'slot a + reset helper failed.'
}

Write-Host 'Core stock slot A restore completed.'
