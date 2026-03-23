[CmdletBinding()]
param(
    [string]$PythonExe,
    [string]$ProjectRoot,
    [string]$LoaderPath
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

$device = Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -match 'VID_05C6&PID_9008' -or $_.FriendlyName -match '9008|QDLoader|QUSB__BULK' } |
    Select-Object -First 1

if (-not $device) {
    throw 'Qualcomm 9008 non detecte.'
}

$commonArgs = @(
    $edlScript,
    '--memory=emmc',
    "--loader=$LoaderPath",
    '--vid=0x05c6',
    '--pid=0x9008'
)

Write-Host 'Erasing userdata...'
& $PythonExe @($commonArgs + @('e', 'userdata'))
if ($LASTEXITCODE -ne 0) {
    throw 'userdata erase failed.'
}

Write-Host 'Forcing slot a and resetting device...'
& $PythonExe $slotResetScript
if ($LASTEXITCODE -ne 0) {
    throw 'slot a + reset helper failed.'
}

Write-Host 'userdata wipe + reset completed.'
