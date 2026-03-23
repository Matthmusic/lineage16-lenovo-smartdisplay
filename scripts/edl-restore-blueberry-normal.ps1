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
$runtimeDir = Join-Path $ProjectRoot 'restore_normal_runtime'
$partitionTable = Join-Path $FactoryDir 'partition-table.img'
$ptPrimary = Join-Path $runtimeDir 'pt_primary_factory.bin'
$ptBackup = Join-Path $runtimeDir 'pt_backup_factory.bin'
$backupStartSector = 7634911
$backupDir = Join-Path $ProjectRoot 'backup'
$trimmedDir = Join-Path $ProjectRoot 'restore_trimmed'

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

function Get-ExistingImage {
    param(
        [string[]]$Candidates,
        [string]$Partition
    )

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Missing image for $Partition. Tried: $($Candidates -join ', ')"
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
    @{ Partition = 'persist'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'persist.img')) -Partition 'persist' },
    @{ Partition = 'modem_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'modem_a_exact.img'), (Join-Path $backupDir 'modem_a.img')) -Partition 'modem_a' },
    @{ Partition = 'modem_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'modem_b_exact.img'), (Join-Path $backupDir 'modem_b.img')) -Partition 'modem_b' },
    @{ Partition = 'drm_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'drm_a_exact.img'), (Join-Path $backupDir 'drm_a.img')) -Partition 'drm_a' },
    @{ Partition = 'drm_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'drm_b_exact.img'), (Join-Path $backupDir 'drm_b.img')) -Partition 'drm_b' },
    @{ Partition = 'bluetooth_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'bluetooth_a_exact.img'), (Join-Path $backupDir 'bluetooth_a.img')) -Partition 'bluetooth_a' },
    @{ Partition = 'bluetooth_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'bluetooth_b_exact.img'), (Join-Path $backupDir 'bluetooth_b.img')) -Partition 'bluetooth_b' },
    @{ Partition = 'sbl1_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'sbl1_a_exact.img'), (Join-Path $backupDir 'sbl1_a.img')) -Partition 'sbl1_a' },
    @{ Partition = 'sbl1_b'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'sbl1_b.img')) -Partition 'sbl1_b' },
    @{ Partition = 'aboot_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'aboot_a_exact.img'), (Join-Path $backupDir 'aboot_a.img')) -Partition 'aboot_a' },
    @{ Partition = 'aboot_b'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'aboot_b.img')) -Partition 'aboot_b' },
    @{ Partition = 'rpm_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'rpm_a_exact.img'), (Join-Path $backupDir 'rpm_a.img')) -Partition 'rpm_a' },
    @{ Partition = 'rpm_b'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'rpm_b.img')) -Partition 'rpm_b' },
    @{ Partition = 'tz_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'tz_a_exact.img'), (Join-Path $backupDir 'tz_a.img')) -Partition 'tz_a' },
    @{ Partition = 'tz_b'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'tz_b.img')) -Partition 'tz_b' },
    @{ Partition = 'devcfg_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'devcfg_a_exact.img'), (Join-Path $backupDir 'devcfg_a.img')) -Partition 'devcfg_a' },
    @{ Partition = 'devcfg_b'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'devcfg_b.img')) -Partition 'devcfg_b' },
    @{ Partition = 'modemst1'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'modemst1.img')) -Partition 'modemst1' },
    @{ Partition = 'modemst2'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'modemst2.img')) -Partition 'modemst2' },
    @{ Partition = 'fsc'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'fsc.img')) -Partition 'fsc' },
    @{ Partition = 'ssd'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'ssd.img')) -Partition 'ssd' },
    @{ Partition = 'DDR'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'DDR.img')) -Partition 'DDR' },
    @{ Partition = 'fsg'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'fsg.img')) -Partition 'fsg' },
    @{ Partition = 'sec'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'sec.img')) -Partition 'sec' },
    @{ Partition = 'misc'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'misc.img')) -Partition 'misc' },
    @{ Partition = 'boot_a'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'boot_a_32mb.img'), (Join-Path $backupDir 'boot_a.img')) -Partition 'boot_a' },
    @{ Partition = 'boot_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'boot_b_32mb.img'), (Join-Path $backupDir 'boot_b.img')) -Partition 'boot_b' },
    @{ Partition = 'system_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'system_a_exact.img'), (Join-Path $backupDir 'system_a.img')) -Partition 'system_a' },
    @{ Partition = 'system_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'system_b_exact.img'), (Join-Path $backupDir 'system_b.img')) -Partition 'system_b' },
    @{ Partition = 'vbmeta_a'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'vbmeta_a_64k.img'), (Join-Path $backupDir 'vbmeta_a.img')) -Partition 'vbmeta_a' },
    @{ Partition = 'vbmeta_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'vbmeta_b_64k.img'), (Join-Path $backupDir 'vbmeta_b.img')) -Partition 'vbmeta_b' },
    @{ Partition = 'vendor_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'vendor_a_exact.img'), (Join-Path $backupDir 'vendor_a.img')) -Partition 'vendor_a' },
    @{ Partition = 'vendor_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'vendor_b_exact.img'), (Join-Path $backupDir 'vendor_b.img')) -Partition 'vendor_b' },
    @{ Partition = 'oem_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'oem_a_exact.img'), (Join-Path $backupDir 'oem_a.img')) -Partition 'oem_a' },
    @{ Partition = 'oem_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'oem_b_exact.img'), (Join-Path $backupDir 'oem_b.img')) -Partition 'oem_b' },
    @{ Partition = 'oem_bootloader_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'oem_bootloader_a_exact.img'), (Join-Path $backupDir 'oem_bootloader_a.img')) -Partition 'oem_bootloader_a' },
    @{ Partition = 'oem_bootloader_b'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'oem_bootloader_b.img')) -Partition 'oem_bootloader_b' },
    @{ Partition = 'factory'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'factory.img')) -Partition 'factory' },
    @{ Partition = 'factory_bootloader'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'factory_bootloader.img')) -Partition 'factory_bootloader' },
    @{ Partition = 'devinfo'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'devinfo.img')) -Partition 'devinfo' },
    @{ Partition = 'keystore'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'keystore.img')) -Partition 'keystore' },
    @{ Partition = 'config'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'config.img')) -Partition 'config' },
    @{ Partition = 'cmnlib_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'cmnlib_a_exact.img'), (Join-Path $backupDir 'cmnlib_a.img')) -Partition 'cmnlib_a' },
    @{ Partition = 'cmnlib_b'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'cmnlib_b.img')) -Partition 'cmnlib_b' },
    @{ Partition = 'dsp_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'dsp_a_exact.img'), (Join-Path $backupDir 'dsp_a.img')) -Partition 'dsp_a' },
    @{ Partition = 'dsp_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'dsp_b_exact.img'), (Join-Path $backupDir 'dsp_b.img')) -Partition 'dsp_b' },
    @{ Partition = 'limits'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'limits.img')) -Partition 'limits' },
    @{ Partition = 'dip'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'dip.img')) -Partition 'dip' },
    @{ Partition = 'syscfg'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'syscfg.img')) -Partition 'syscfg' },
    @{ Partition = 'mcfg'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'mcfg.img')) -Partition 'mcfg' },
    @{ Partition = 'keymaster_a'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'keymaster_a_exact.img'), (Join-Path $backupDir 'keymaster_a.img')) -Partition 'keymaster_a' },
    @{ Partition = 'keymaster_b'; File = Get-ExistingImage -Candidates @((Join-Path $trimmedDir 'keymaster_b_exact.img'), (Join-Path $backupDir 'keymaster_b.img')) -Partition 'keymaster_b' },
    @{ Partition = 'apdp'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'apdp.img')) -Partition 'apdp' },
    @{ Partition = 'msadp'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'msadp.img')) -Partition 'msadp' },
    @{ Partition = 'dpo'; File = Get-ExistingImage -Candidates @((Join-Path $backupDir 'dpo.img')) -Partition 'dpo' }
)

$startFound = [string]::IsNullOrWhiteSpace($StartAtPartition)

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

Write-Host 'Forcing slot a and resetting device...'
& $PythonExe $slotResetScript 'a'
if ($LASTEXITCODE -ne 0) {
    throw 'slot a + reset helper failed.'
}

Write-Host 'Blueberry normal restore from backups completed.'
