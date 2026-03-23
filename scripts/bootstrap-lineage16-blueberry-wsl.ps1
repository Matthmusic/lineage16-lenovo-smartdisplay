[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-20.04-Lineage16',
    [string]$BuildRoot = '/build/lineage16-blueberry',
    [int]$Jobs = 4,
    [switch]$SkipSync
)

$ErrorActionPreference = 'Stop'

function Convert-ToWslPath {
    param(
        [string]$WindowsPath
    )

    $resolved = (Resolve-Path $WindowsPath).Path
    $drive = $resolved.Substring(0, 1).ToLowerInvariant()
    $tail = $resolved.Substring(2).Replace('\', '/')
    return "/mnt/$drive$tail"
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $projectRoot 'blueberry_manifest_lineage16.xml'
$seedRoot = Join-Path $projectRoot 'lineage16_seed'
$shellScript = Join-Path $PSScriptRoot 'bootstrap-lineage16-blueberry-wsl.sh'

foreach ($path in @($manifestPath, $seedRoot, $shellScript)) {
    if (-not (Test-Path $path)) {
        throw "Missing required path: $path"
    }
}

$shellScriptWsl = Convert-ToWslPath $shellScript
$manifestWsl = Convert-ToWslPath $manifestPath
$seedRootWsl = Convert-ToWslPath $seedRoot
$skipFlag = if ($SkipSync) { '1' } else { '0' }

& wsl.exe -d $Distro -- bash $shellScriptWsl $BuildRoot $manifestWsl $seedRootWsl $Jobs $skipFlag
if ($LASTEXITCODE -ne 0) {
    throw 'WSL Lineage 16 bootstrap failed.'
}

Write-Host "Parallel Lineage 16 checkout prepared in $BuildRoot on $Distro"
