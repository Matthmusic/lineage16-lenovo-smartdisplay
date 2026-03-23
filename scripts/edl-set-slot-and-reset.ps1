[CmdletBinding()]
param(
    [string]$PythonExe,
    [string]$ProjectRoot,
    [string]$LoaderPath,
    [ValidateSet('a', 'b')]
    [string]$Slot = 'a',
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
if (-not (Test-Path $edlScript)) {
    throw "edl.py not found: $edlScript"
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
    "--loader=$LoaderPath",
    '--vid=0x05c6',
    '--pid=0x9008'
)

Write-Host "Setting active slot to $Slot..."
& $PythonExe @commonArgs 'setactiveslot' $Slot
if ($LASTEXITCODE -ne 0) {
    throw "edl setactiveslot failed for slot $Slot."
}

Write-Host 'Resetting device...'
& $PythonExe @commonArgs 'reset'
if ($LASTEXITCODE -ne 0) {
    throw 'edl reset failed.'
}

Write-Host "Active slot set to $Slot and reset command sent."
