[CmdletBinding()]
param(
    [int]$Port = 8765,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$dashboardScript = Join-Path $PSScriptRoot 'device-dashboard.py'
$pythonExe = Join-Path $projectRoot '.venv-edl\Scripts\python.exe'

if (-not (Test-Path $dashboardScript)) {
    throw "Dashboard script not found: $dashboardScript"
}

if (-not (Test-Path $pythonExe)) {
    $pythonCmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $pythonExe = $pythonCmd.Source
    }
    else {
        throw 'No Python interpreter found.'
    }
}

$url = "http://127.0.0.1:$Port"
Write-Host "Starting dashboard on $url"

if (-not $NoBrowser) {
    Start-Job -ScriptBlock {
        param($TargetUrl)
        Start-Sleep -Seconds 1
        Start-Process $TargetUrl
    } -ArgumentList $url | Out-Null
}

& $pythonExe $dashboardScript --port $Port
