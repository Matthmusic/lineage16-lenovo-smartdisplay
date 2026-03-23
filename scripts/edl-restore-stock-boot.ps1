[CmdletBinding()]
param(
    [string]$PythonExe,
    [string]$ProjectRoot,
    [string]$LoaderPath,
    [string]$BootImage,
    [ValidateSet('a', 'b', '')]
    [string]$SetActiveSlot = 'a',
    [int]$TimeoutSeconds = 0
)

$ErrorActionPreference = 'Stop'

# Force UTF-8 so Python progress output does not crash on legacy Windows code pages.
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

if ([string]::IsNullOrWhiteSpace($BootImage)) {
    $BootImage = Join-Path $ProjectRoot 'backup\boot_a_32mb.img'
}

$PythonExe = (Resolve-Path $PythonExe).Path
$LoaderPath = (Resolve-Path $LoaderPath).Path
$BootImage = (Resolve-Path $BootImage).Path

if ((Get-Item $BootImage).Length -ne 33554432) {
    throw "Expected a 32 MiB boot image, got $((Get-Item $BootImage).Length) bytes: $BootImage"
}

$edlScript = Join-Path $ProjectRoot 'tools\edl\edl.py'
if (-not (Test-Path $edlScript)) {
    throw "edl.py not found: $edlScript"
}

$logsDir = Join-Path $ProjectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$deadline = if ($TimeoutSeconds -gt 0) { (Get-Date).AddSeconds($TimeoutSeconds) } else { $null }

Write-Host 'Waiting for Qualcomm QDLoader 9008...'
while ($true) {
    $device = Get-PnpDevice -PresentOnly |
        Where-Object { $_.InstanceId -match 'VID_05C6&PID_9008' -or $_.FriendlyName -match '9008|QDLoader' } |
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

Write-Host 'Reading GPT...'
& $PythonExe @commonArgs 'printgpt'
if ($LASTEXITCODE -ne 0) {
    throw 'edl printgpt failed.'
}

Write-Host 'Writing boot_a...'
& $PythonExe @commonArgs 'w' 'boot_a' $BootImage
if ($LASTEXITCODE -ne 0) {
    throw 'edl write failed for boot_a.'
}

Write-Host 'Writing boot_b...'
& $PythonExe @commonArgs 'w' 'boot_b' $BootImage
if ($LASTEXITCODE -ne 0) {
    throw 'edl write failed for boot_b.'
}

$setActiveArgs = @(
    $edlScript,
    "--loader=$LoaderPath",
    '--vid=0x05c6',
    '--pid=0x9008'
)

if (-not [string]::IsNullOrWhiteSpace($SetActiveSlot)) {
    Write-Host "Setting active slot to $SetActiveSlot..."
    & $PythonExe @setActiveArgs 'setactiveslot' $SetActiveSlot
    if ($LASTEXITCODE -ne 0) {
        throw "edl setactiveslot failed for slot $SetActiveSlot."
    }
}

$resetArgs = @(
    $edlScript,
    "--loader=$LoaderPath",
    '--vid=0x05c6',
    '--pid=0x9008'
)

Write-Host 'Resetting device...'
& $PythonExe @resetArgs 'reset'
if ($LASTEXITCODE -ne 0) {
    throw 'edl reset failed.'
}

Write-Host "Restored stock boot image on boot_a and boot_b: $BootImage"
