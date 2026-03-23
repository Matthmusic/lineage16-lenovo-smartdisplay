[CmdletBinding()]
param(
    [string]$PythonExe,
    [string]$ProjectRoot,
    [string]$LoaderPath,
    [string]$FactoryDir,
    [string]$StartAtPartition
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

if ([string]::IsNullOrWhiteSpace($FactoryDir)) {
    $FactoryDir = 'C:\Users\Matthieu MAUREL\Downloads\Blueberry-factory-S0.28.20-4757977-debug'
}

$PythonExe = (Resolve-Path $PythonExe).Path
$LoaderPath = (Resolve-Path $LoaderPath).Path
$FactoryDir = (Resolve-Path $FactoryDir).Path

$edlScript = Join-Path $ProjectRoot 'tools\edl\edl.py'
$slotResetScript = Join-Path $ProjectRoot 'scripts\edl-firehose-slot-reset.py'
$runtimeDir = Join-Path $ProjectRoot 'restore_factory_runtime'
$partitionTable = Join-Path $FactoryDir 'partition-table.img'
$ptPrimary = Join-Path $runtimeDir 'pt_primary_factory.bin'
$ptBackup = Join-Path $runtimeDir 'pt_backup_factory.bin'
$backupStartSector = 7634911

if (-not (Test-Path $edlScript)) {
    throw "edl.py not found: $edlScript"
}
if (-not (Test-Path $slotResetScript)) {
    throw "slot reset helper not found: $slotResetScript"
}
if (-not (Test-Path $partitionTable)) {
    throw "partition-table.img not found: $partitionTable"
}

New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

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
        $joined -match 'Traceback' -or
        $joined -match 'Error:' -or
        $joined -match 'failed\.') {
        throw $FailureMessage
    }
}

function Split-FactoryPartitionTable {
    param(
        [string]$SourcePath,
        [string]$PrimaryPath,
        [string]$BackupPath
    )

    $bytes = [System.IO.File]::ReadAllBytes($SourcePath)
    if ($bytes.Length -ne 34304) {
        throw "Unexpected partition-table.img size: $($bytes.Length)"
    }

    $primary = New-Object byte[] 17408
    $backup = New-Object byte[] 16896
    [Array]::Copy($bytes, 0, $primary, 0, $primary.Length)
    [Array]::Copy($bytes, $primary.Length, $backup, 0, $backup.Length)

    [System.IO.File]::WriteAllBytes($PrimaryPath, $primary)
    [System.IO.File]::WriteAllBytes($BackupPath, $backup)
}

function Get-PartitionSizesFromFactoryTable {
    param(
        [string]$SourcePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($SourcePath)
    $sectorSize = 512
    $headerOffset = $sectorSize

    $entryStartLba = [BitConverter]::ToUInt64($bytes, $headerOffset + 72)
    $entryCount = [BitConverter]::ToUInt32($bytes, $headerOffset + 80)
    $entrySize = [BitConverter]::ToUInt32($bytes, $headerOffset + 84)

    $result = @{}
    for ($i = 0; $i -lt $entryCount; $i++) {
        $offset = ($entryStartLba * $sectorSize) + ($i * $entrySize)
        $typeGuid = $bytes[$offset..($offset + 15)]
        if (($typeGuid | Measure-Object -Sum).Sum -eq 0) {
            continue
        }

        $firstLba = [BitConverter]::ToUInt64($bytes, $offset + 32)
        $lastLba = [BitConverter]::ToUInt64($bytes, $offset + 40)
        $nameBytes = $bytes[($offset + 56)..($offset + 127)]
        $name = [System.Text.Encoding]::Unicode.GetString($nameBytes).Trim([char]0)
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $sectorCount = ($lastLba - $firstLba + 1)
        $result[$name] = [int64]$sectorCount * $sectorSize
    }

    return $result
}

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

function Resolve-PartitionWritePath {
    param(
        [string]$Partition,
        [string]$Path,
        [hashtable]$PartitionSizes
    )

    $resolved = (Resolve-Path $Path).Path
    $size = (Get-Item $resolved).Length
    if (-not $PartitionSizes.ContainsKey($Partition)) {
        return $resolved
    }

    $exactSize = [int64]$PartitionSizes[$Partition]
    if ($size -le $exactSize) {
        return $resolved
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($resolved)
    $ext = [System.IO.Path]::GetExtension($resolved)
    $trimmed = Join-Path $runtimeDir ("{0}_{1}{2}" -f $name, $exactSize, $ext)
    if (-not (Test-Path $trimmed) -or (Get-Item $trimmed).Length -ne $exactSize) {
        Write-Host "Trimming $resolved to $exactSize bytes for $Partition..."
        New-TrimmedImage -SourcePath $resolved -OutputPath $trimmed -ExactSize $exactSize
    }
    return $trimmed
}

$commonArgs = @(
    $edlScript,
    '--memory=emmc',
    "--loader=$LoaderPath",
    '--vid=0x05c6',
    '--pid=0x9008'
)

$device = Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -match 'VID_05C6&PID_9008' -or $_.FriendlyName -match '9008|QDLoader|QUSB__BULK' } |
    Select-Object -First 1

if (-not $device) {
    throw 'Qualcomm 9008 non detecte.'
}

Split-FactoryPartitionTable -SourcePath $partitionTable -PrimaryPath $ptPrimary -BackupPath $ptBackup
$partitionSizes = Get-PartitionSizesFromFactoryTable -SourcePath $partitionTable

if ([string]::IsNullOrWhiteSpace($StartAtPartition)) {
    Write-Host 'Writing exact factory GPT...'
    Invoke-EdlChecked -Arguments ($commonArgs + @('ws', '0', $ptPrimary)) -FailureMessage 'Failed to write factory GPT primary.'
    Invoke-EdlChecked -Arguments ($commonArgs + @('ws', [string]$backupStartSector, $ptBackup)) -FailureMessage 'Failed to write factory GPT backup.'
    Invoke-EdlChecked -Arguments ($commonArgs + @('printgpt')) -FailureMessage 'Failed to read GPT after factory GPT write.'
}

$images = @(
    @{ Partition = 'persist'; File = (Join-Path $FactoryDir 'persist.img') },
    @{ Partition = 'modem_a'; File = (Join-Path $FactoryDir 'modem_a.img') },
    @{ Partition = 'modem_b'; File = (Join-Path $FactoryDir 'modem.img') },
    @{ Partition = 'drm_a'; File = (Join-Path $FactoryDir 'drm.img') },
    @{ Partition = 'drm_b'; File = (Join-Path $FactoryDir 'drm.img') },
    @{ Partition = 'bluetooth_a'; File = (Join-Path $FactoryDir 'bluetooth.img') },
    @{ Partition = 'bluetooth_b'; File = (Join-Path $FactoryDir 'bluetooth.img') },
    @{ Partition = 'sbl1_a'; File = (Join-Path $FactoryDir 'sbl1.img') },
    @{ Partition = 'sbl1_b'; File = (Join-Path $FactoryDir 'sbl1.img') },
    @{ Partition = 'aboot_a'; File = (Join-Path $FactoryDir 'aboot.img') },
    @{ Partition = 'aboot_b'; File = (Join-Path $FactoryDir 'aboot.img') },
    @{ Partition = 'rpm_a'; File = (Join-Path $FactoryDir 'rpm.img') },
    @{ Partition = 'rpm_b'; File = (Join-Path $FactoryDir 'rpm.img') },
    @{ Partition = 'tz_a'; File = (Join-Path $FactoryDir 'tz.img') },
    @{ Partition = 'tz_b'; File = (Join-Path $FactoryDir 'tz.img') },
    @{ Partition = 'devcfg_a'; File = (Join-Path $FactoryDir 'devcfg.img') },
    @{ Partition = 'devcfg_b'; File = (Join-Path $FactoryDir 'devcfg.img') },
    @{ Partition = 'modemst1'; File = (Join-Path $ProjectRoot 'backup\modemst1.img') },
    @{ Partition = 'modemst2'; File = (Join-Path $ProjectRoot 'backup\modemst2.img') },
    @{ Partition = 'fsc'; File = (Join-Path $ProjectRoot 'backup\fsc.img') },
    @{ Partition = 'ssd'; File = (Join-Path $ProjectRoot 'backup\ssd.img') },
    @{ Partition = 'DDR'; File = (Join-Path $ProjectRoot 'backup\DDR.img') },
    @{ Partition = 'fsg'; File = (Join-Path $ProjectRoot 'backup\fsg.img') },
    @{ Partition = 'sec'; File = (Join-Path $ProjectRoot 'backup\sec.img') },
    @{ Partition = 'boot_a'; File = (Join-Path $FactoryDir 'boot_a.img') },
    @{ Partition = 'boot_b'; File = (Join-Path $FactoryDir 'boot.img') },
    @{ Partition = 'system_a'; File = (Join-Path $FactoryDir 'system_a.img') },
    @{ Partition = 'system_b'; File = (Join-Path $FactoryDir 'system.img') },
    @{ Partition = 'vbmeta_a'; File = (Join-Path $FactoryDir 'vbmeta_a.img') },
    @{ Partition = 'vbmeta_b'; File = (Join-Path $FactoryDir 'vbmeta.img') },
    @{ Partition = 'vendor_a'; File = (Join-Path $FactoryDir 'vendor_a.img') },
    @{ Partition = 'vendor_b'; File = (Join-Path $FactoryDir 'vendor.img') },
    @{ Partition = 'oem_a'; File = (Join-Path $FactoryDir 'oem_a.img') },
    @{ Partition = 'oem_b'; File = (Join-Path $FactoryDir 'oem.img') },
    @{ Partition = 'oem_bootloader_a'; File = (Join-Path $ProjectRoot 'backup\oem_bootloader_a.img') },
    @{ Partition = 'oem_bootloader_b'; File = (Join-Path $ProjectRoot 'backup\oem_bootloader_b.img') },
    @{ Partition = 'factory'; File = (Join-Path $ProjectRoot 'backup\factory.img') },
    @{ Partition = 'factory_bootloader'; File = (Join-Path $ProjectRoot 'backup\factory_bootloader.img') },
    @{ Partition = 'devinfo'; File = (Join-Path $ProjectRoot 'backup\devinfo.img') },
    @{ Partition = 'keystore'; File = (Join-Path $ProjectRoot 'backup\keystore.img') },
    @{ Partition = 'config'; File = (Join-Path $ProjectRoot 'backup\config.img') },
    @{ Partition = 'cmnlib_a'; File = (Join-Path $FactoryDir 'cmnlib.img') },
    @{ Partition = 'cmnlib_b'; File = (Join-Path $FactoryDir 'cmnlib.img') },
    @{ Partition = 'dsp_a'; File = (Join-Path $FactoryDir 'dsp.img') },
    @{ Partition = 'dsp_b'; File = (Join-Path $FactoryDir 'dsp.img') },
    @{ Partition = 'limits'; File = (Join-Path $ProjectRoot 'backup\limits.img') },
    @{ Partition = 'dip'; File = (Join-Path $ProjectRoot 'backup\dip.img') },
    @{ Partition = 'syscfg'; File = (Join-Path $ProjectRoot 'backup\syscfg.img') },
    @{ Partition = 'mcfg'; File = (Join-Path $ProjectRoot 'backup\mcfg.img') },
    @{ Partition = 'keymaster_a'; File = (Join-Path $FactoryDir 'keymaster.img') },
    @{ Partition = 'keymaster_b'; File = (Join-Path $FactoryDir 'keymaster.img') },
    @{ Partition = 'apdp'; File = (Join-Path $ProjectRoot 'backup\apdp.img') },
    @{ Partition = 'msadp'; File = (Join-Path $ProjectRoot 'backup\msadp.img') },
    @{ Partition = 'dpo'; File = (Join-Path $ProjectRoot 'backup\dpo.img') }
)

foreach ($item in $images) {
    if (-not (Test-Path $item.File)) {
        throw "Missing image for $($item.Partition): $($item.File)"
    }
}

$startFound = [string]::IsNullOrWhiteSpace($StartAtPartition)

if ($startFound) {
    Write-Host 'Erasing misc before factory restore...'
    Invoke-EdlChecked -Arguments ($commonArgs + @('e', 'misc')) -FailureMessage 'Failed to erase misc.'
}

foreach ($item in $images) {
    if (-not $startFound) {
        if ($item.Partition -eq $StartAtPartition) {
            $startFound = $true
        }
        else {
            continue
        }
    }

    $writePath = Resolve-PartitionWritePath -Partition $item.Partition -Path $item.File -PartitionSizes $partitionSizes
    Write-Host "Erasing $($item.Partition)..."
    Invoke-EdlChecked -Arguments ($commonArgs + @('e', $item.Partition)) -FailureMessage "Failed to erase $($item.Partition)."
    Write-Host "Writing $($item.Partition) from $([System.IO.Path]::GetFileName($writePath))..."
    Invoke-EdlChecked -Arguments ($commonArgs + @('w', $item.Partition, $writePath)) -FailureMessage "Failed to write $($item.Partition)."
}

Write-Host 'Erasing userdata...'
Invoke-EdlChecked -Arguments ($commonArgs + @('e', 'userdata')) -FailureMessage 'Failed to erase userdata.'

Write-Host 'Forcing slot b and resetting device...'
& $PythonExe $slotResetScript 'b'
if ($LASTEXITCODE -ne 0) {
    throw 'slot b + reset helper failed.'
}

Write-Host 'Exact blueberry factory restore completed.'
