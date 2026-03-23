[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-20.04-Lineage16'
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

$shellScript = Join-Path $PSScriptRoot 'install-lineage16-wsl-prereqs.sh'
if (-not (Test-Path $shellScript)) {
    throw "Missing prerequisite script: $shellScript"
}

$shellScriptWsl = Convert-ToWslPath $shellScript

& wsl.exe -d $Distro -- bash $shellScriptWsl
if ($LASTEXITCODE -ne 0) {
    throw "WSL prerequisite installation failed on $Distro."
}

Write-Host "Lineage 16 WSL prerequisites installed on $Distro"
