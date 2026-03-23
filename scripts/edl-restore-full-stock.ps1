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
$trimDir = Join-Path $ProjectRoot 'restore_runtime_exact'

if (-not (Test-Path $edlScript)) {
    throw "edl.py not found: $edlScript"
}
if (-not (Test-Path $slotResetScript)) {
    throw "slot reset helper not found: $slotResetScript"
}

New-Item -ItemType Directory -Force -Path $trimDir | Out-Null

function New-TrimmedImage {
    param(
        [string]$SourcePath,
        [string]$OutputPath,
        [long]$ExactSize
    )

    $inStream = [System.IO.File]::OpenRead($SourcePath)
    try {
        $outStream = [System.IO.File]::Create($OutputPath)
        try {
            $buffer = New-Object byte[] (1024 * 1024)
            $remaining = $ExactSize
            while ($remaining -gt 0) {
                $toRead = [Math]::Min($buffer.Length, $remaining)
                $read = $inStream.Read($buffer, 0, $toRead)
                if ($read -le 0) {
                    throw "Unexpected EOF while trimming $SourcePath"
                }
                $outStream.Write($buffer, 0, $read)
                $remaining -= $read
            }
        }
        finally {
            $outStream.Dispose()
        }
    }
    finally {
        $inStream.Dispose()
    }
}

function Resolve-ExactImage {
    param(
        [string]$Path,
        [long]$ExactSize
    )

    $resolved = (Resolve-Path $Path).Path
    $size = (Get-Item $resolved).Length
    if ($size -eq $ExactSize) {
        return $resolved
    }
    if ($size -lt $ExactSize) {
        throw "Image too small: $resolved ($size bytes, expected $ExactSize)"
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($resolved)
    $ext = [System.IO.Path]::GetExtension($resolved)
    $trimmed = Join-Path $trimDir ("{0}_{1}{2}" -f $name, $ExactSize, $ext)
    if (-not (Test-Path $trimmed) -or (Get-Item $trimmed).Length -ne $ExactSize) {
        Write-Host "Trimming $resolved to $ExactSize bytes..."
        New-TrimmedImage -SourcePath $resolved -OutputPath $trimmed -ExactSize $ExactSize
    }
    return $trimmed
}

$images = @(
    @{ Partition = 'persist'; File = (Join-Path $ProjectRoot 'backup\persist.img'); ExactSize = 8388608L },
    @{ Partition = 'modem_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\modem_a_exact.img'); ExactSize = 33554432L },
    @{ Partition = 'modem_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\modem_b_exact.img'); ExactSize = 33554432L },
    @{ Partition = 'drm_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\drm_a_exact.img'); ExactSize = 4194304L },
    @{ Partition = 'drm_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\drm_b_exact.img'); ExactSize = 4194304L },
    @{ Partition = 'bluetooth_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\bluetooth_a_exact.img'); ExactSize = 524288L },
    @{ Partition = 'bluetooth_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\bluetooth_b_exact.img'); ExactSize = 524288L },
    @{ Partition = 'rpm_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\rpm_a_exact.img'); ExactSize = 524288L },
    @{ Partition = 'rpm_b'; File = (Join-Path $ProjectRoot 'backup\rpm_b.img'); ExactSize = 524288L },
    @{ Partition = 'aboot_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\aboot_a_exact.img'); ExactSize = 1048576L },
    @{ Partition = 'aboot_b'; File = (Join-Path $ProjectRoot 'backup\aboot_b.img'); ExactSize = 1048576L },
    @{ Partition = 'sbl1_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\sbl1_a_exact.img'); ExactSize = 524288L },
    @{ Partition = 'sbl1_b'; File = (Join-Path $ProjectRoot 'backup\sbl1_b.img'); ExactSize = 524288L },
    @{ Partition = 'tz_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\tz_a_exact.img'); ExactSize = 2097152L },
    @{ Partition = 'tz_b'; File = (Join-Path $ProjectRoot 'backup\tz_b.img'); ExactSize = 2097152L },
    @{ Partition = 'devcfg_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\devcfg_a_exact.img'); ExactSize = 262144L },
    @{ Partition = 'devcfg_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\devcfg_b_exact.img'); ExactSize = 262144L },
    @{ Partition = 'modemst1'; File = (Join-Path $ProjectRoot 'backup\modemst1.img'); ExactSize = 1572864L },
    @{ Partition = 'modemst2'; File = (Join-Path $ProjectRoot 'backup\modemst2.img'); ExactSize = 1572864L },
    @{ Partition = 'misc'; File = (Join-Path $ProjectRoot 'backup\misc.img'); ExactSize = 1048576L },
    @{ Partition = 'fsc'; File = (Join-Path $ProjectRoot 'backup\fsc.img'); ExactSize = 1024L },
    @{ Partition = 'ssd'; File = (Join-Path $ProjectRoot 'backup\ssd.img'); ExactSize = 8192L },
    @{ Partition = 'DDR'; File = (Join-Path $ProjectRoot 'backup\DDR.img'); ExactSize = 32768L },
    @{ Partition = 'fsg'; File = (Join-Path $ProjectRoot 'backup\fsg.img'); ExactSize = 1572864L },
    @{ Partition = 'sec'; File = (Join-Path $ProjectRoot 'backup\sec.img'); ExactSize = 16384L },
    @{ Partition = 'boot_a'; File = (Join-Path $ProjectRoot 'backup\boot_a_32mb.img'); ExactSize = 33554432L },
    @{ Partition = 'boot_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\boot_b_32mb.img'); ExactSize = 33554432L },
    @{ Partition = 'system_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\system_a_exact.img'); ExactSize = 536870912L },
    @{ Partition = 'system_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\system_b_exact.img'); ExactSize = 536870912L },
    @{ Partition = 'vbmeta_a'; File = (Join-Path $ProjectRoot 'backup\vbmeta_a_64k.img'); ExactSize = 65536L },
    @{ Partition = 'vbmeta_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\vbmeta_b_64k.img'); ExactSize = 65536L },
    @{ Partition = 'vendor_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\vendor_a_exact.img'); ExactSize = 134217728L },
    @{ Partition = 'vendor_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\vendor_b_exact.img'); ExactSize = 134217728L },
    @{ Partition = 'oem_bootloader_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\oem_bootloader_a_exact.img'); ExactSize = 4194304L },
    @{ Partition = 'oem_bootloader_b'; File = (Join-Path $ProjectRoot 'backup\oem_bootloader_b.img'); ExactSize = 4194304L },
    @{ Partition = 'factory'; File = (Join-Path $ProjectRoot 'backup\factory.img'); ExactSize = 33554432L },
    @{ Partition = 'factory_bootloader'; File = (Join-Path $ProjectRoot 'backup\factory_bootloader.img'); ExactSize = 16777216L },
    @{ Partition = 'devinfo'; File = (Join-Path $ProjectRoot 'backup\devinfo.img'); ExactSize = 1048576L },
    @{ Partition = 'keystore'; File = (Join-Path $ProjectRoot 'backup\keystore.img'); ExactSize = 524288L },
    @{ Partition = 'config'; File = (Join-Path $ProjectRoot 'backup\config.img'); ExactSize = 524288L },
    @{ Partition = 'cmnlib_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\cmnlib_a_exact.img'); ExactSize = 1048576L },
    @{ Partition = 'cmnlib_b'; File = (Join-Path $ProjectRoot 'backup\cmnlib_b.img'); ExactSize = 1048576L },
    @{ Partition = 'dsp_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\dsp_a_exact.img'); ExactSize = 16777216L },
    @{ Partition = 'dsp_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\dsp_b_exact.img'); ExactSize = 16777216L },
    @{ Partition = 'limits'; File = (Join-Path $ProjectRoot 'backup\limits.img'); ExactSize = 32768L },
    @{ Partition = 'dip'; File = (Join-Path $ProjectRoot 'backup\dip.img'); ExactSize = 1048576L },
    @{ Partition = 'syscfg'; File = (Join-Path $ProjectRoot 'backup\syscfg.img'); ExactSize = 524288L },
    @{ Partition = 'mcfg'; File = (Join-Path $ProjectRoot 'backup\mcfg.img'); ExactSize = 4194304L },
    @{ Partition = 'keymaster_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\keymaster_a_exact.img'); ExactSize = 1048576L },
    @{ Partition = 'keymaster_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\keymaster_b_exact.img'); ExactSize = 1048576L },
    @{ Partition = 'apdp'; File = (Join-Path $ProjectRoot 'backup\apdp.img'); ExactSize = 262144L },
    @{ Partition = 'msadp'; File = (Join-Path $ProjectRoot 'backup\msadp.img'); ExactSize = 262144L },
    @{ Partition = 'dpo'; File = (Join-Path $ProjectRoot 'backup\dpo.img'); ExactSize = 8192L },
    @{ Partition = 'oem_a'; File = (Join-Path $ProjectRoot 'restore_trimmed\oem_a_exact.img'); ExactSize = 524288000L },
    @{ Partition = 'oem_b'; File = (Join-Path $ProjectRoot 'restore_trimmed\oem_b_exact.img'); ExactSize = 524288000L }
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
    $resolvedFile = Resolve-ExactImage -Path $item.File -ExactSize $item.ExactSize
    $sizeMiB = [Math]::Round((Get-Item $resolvedFile).Length / 1MB, 2)
    Write-Host "Writing $($item.Partition) ($sizeMiB MiB)..."
    Invoke-EdlChecked -Arguments ($commonArgs + @('w', $item.Partition, $resolvedFile)) -FailureMessage "edl write failed for $($item.Partition)."
}

Write-Host 'Forcing slot a and resetting device...'
& $PythonExe $slotResetScript
if ($LASTEXITCODE -ne 0) {
    throw 'slot a + reset helper failed.'
}

Write-Host 'Full stock restore completed.'
