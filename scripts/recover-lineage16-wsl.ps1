[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-20.04-Lineage16',
    [string]$InstallLocation = 'E:\WSL\Ubuntu-20.04-Lineage16',
    [string]$BuildRoot = '/build/lineage16-blueberry',
    [string]$InstallSource = '',
    [string]$RootFsArchive = 'E:\WSL\ubuntu2004_x64\install.tar.gz',
    [string]$ExistingVhdPath = 'E:\WSL\Ubuntu-22.04\ext4.vhdx',
    [int]$Jobs = 4,
    [switch]$UseExistingVhd,
    [switch]$ForceRecreate,
    [switch]$InstallPrereqs,
    [switch]$SkipSync,
    [switch]$SkipBootstrap
)

$ErrorActionPreference = 'Stop'

function Get-RegisteredDistro {
    param(
        [string]$Name
    )

    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $root)) {
        return $null
    }

    return Get-ChildItem $root | ForEach-Object {
        $item = Get-ItemProperty $_.PSPath
        [pscustomobject]@{
            DistributionName = $item.DistributionName
            BasePath = $item.BasePath
            Version = $item.Version
            State = $item.State
        }
    } | Where-Object { $_.DistributionName -eq $Name } | Select-Object -First 1
}

function Write-PortConfig {
    param(
        [string]$Name,
        [string]$Location,
        [string]$Root
    )

    $projectRoot = Split-Path $PSScriptRoot -Parent
    $configDir = Join-Path $projectRoot 'memory'
    $configPath = Join-Path $configDir 'lineage16-wsl.json'
    $artifactRoot = "\\wsl$\$Name$($Root.Replace('/', '\'))\out\target\product\blueberry"

    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    $payload = [ordered]@{
        updated_at = (Get-Date).ToString('s')
        distro = $Name
        install_location = $Location
        build_root = $Root
        artifact_root = $artifactRoot
    }

    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Encoding UTF8
    return $configPath
}

function Invoke-WslChecked {
    param(
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    & wsl.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Invoke-WslClone {
    param(
        [string]$SourceDistro,
        [string]$TargetDistro,
        [string]$TargetLocation
    )

    if (Test-Path $TargetLocation) {
        $existingItems = Get-ChildItem -Force -Path $TargetLocation -ErrorAction SilentlyContinue
        if ($existingItems) {
            throw "Target location already exists and is not empty: $TargetLocation"
        }
    }
    else {
        New-Item -ItemType Directory -Force -Path $TargetLocation | Out-Null
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'smartdisplay-wsl'
    $tempTar = Join-Path $tempRoot "$TargetDistro.tar"
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    if (Test-Path $tempTar) {
        Remove-Item -Force -Path $tempTar
    }

    try {
        Invoke-WslChecked -Arguments @('--export', $SourceDistro, $tempTar, '--format', 'tar') -FailureMessage "WSL export failed for $SourceDistro."
        Invoke-WslChecked -Arguments @('--import', $TargetDistro, $TargetLocation, $tempTar, '--version', '2') -FailureMessage "WSL import failed for $TargetDistro."
    }
    finally {
        if (Test-Path $tempTar) {
            Remove-Item -Force -Path $tempTar -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WslImportArchive {
    param(
        [string]$TargetDistro,
        [string]$TargetLocation,
        [string]$ArchivePath
    )

    if (-not (Test-Path $ArchivePath)) {
        throw "WSL rootfs archive not found: $ArchivePath"
    }

    if (Test-Path $TargetLocation) {
        $existingItems = Get-ChildItem -Force -Path $TargetLocation -ErrorAction SilentlyContinue
        if ($existingItems) {
            throw "Target location already exists and is not empty: $TargetLocation"
        }
    }
    else {
        New-Item -ItemType Directory -Force -Path $TargetLocation | Out-Null
    }

    Write-Host "Importing clean WSL rootfs from $ArchivePath to $TargetLocation"
    Invoke-WslChecked -Arguments @('--import', $TargetDistro, $TargetLocation, $ArchivePath, '--version', '2') -FailureMessage "WSL import failed for $TargetDistro."
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$bootstrapScript = Join-Path $PSScriptRoot 'bootstrap-lineage16-blueberry-wsl.ps1'
$prereqScript = Join-Path $PSScriptRoot 'install-lineage16-wsl-prereqs.ps1'
if (-not (Test-Path $bootstrapScript)) {
    throw "Missing bootstrap script: $bootstrapScript"
}
if ($InstallPrereqs -and -not (Test-Path $prereqScript)) {
    throw "Missing prerequisite script: $prereqScript"
}

$existing = Get-RegisteredDistro -Name $Distro
if ($ForceRecreate -and $existing) {
    if ($existing.BasePath) {
        $InstallLocation = $existing.BasePath
    }
    Invoke-WslChecked -Arguments @('--unregister', $Distro) -FailureMessage "WSL unregister failed for $Distro."
    if (Test-Path $InstallLocation) {
        Remove-Item -Recurse -Force -Path $InstallLocation
    }
    $existing = $null
}

if (-not $existing) {
    if ($UseExistingVhd) {
        if (-not (Test-Path $ExistingVhdPath)) {
            throw "Existing VHD not found: $ExistingVhdPath"
        }
        Invoke-WslChecked -Arguments @('--import-in-place', $Distro, $ExistingVhdPath) -FailureMessage "WSL import-in-place failed for $Distro."
        $existing = Get-RegisteredDistro -Name $Distro
        if (-not $existing) {
            throw "WSL import-in-place finished without registering $Distro."
        }
        $InstallLocation = Split-Path $ExistingVhdPath -Parent
    }
    else {
        $sourceDistro = $null
        if (-not [string]::IsNullOrWhiteSpace($InstallSource)) {
            $sourceDistro = Get-RegisteredDistro -Name $InstallSource
            if ($InstallSource -eq $Distro) {
                throw "InstallSource cannot be the same distro as the target: $Distro"
            }
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $InstallLocation -Parent) | Out-Null
        if ($sourceDistro) {
            Invoke-WslClone -SourceDistro $InstallSource -TargetDistro $Distro -TargetLocation $InstallLocation
        }
        elseif (-not [string]::IsNullOrWhiteSpace($RootFsArchive) -and (Test-Path $RootFsArchive)) {
            Invoke-WslImportArchive -TargetDistro $Distro -TargetLocation $InstallLocation -ArchivePath $RootFsArchive
        }
        else {
            Invoke-WslChecked -Arguments @('--install', $Distro, '--location', $InstallLocation, '--no-launch') -FailureMessage "WSL install failed for $Distro."
        }
        $existing = Get-RegisteredDistro -Name $Distro
        if (-not $existing) {
            throw "WSL distro creation finished without registering $Distro."
        }
    }
}
else {
    $InstallLocation = $existing.BasePath
}

$configPath = Write-PortConfig -Name $Distro -Location $InstallLocation -Root $BuildRoot
Write-Host "WSL port config written to $configPath"

if ($InstallPrereqs) {
    & powershell.exe -ExecutionPolicy Bypass -File $prereqScript -Distro $Distro
    if ($LASTEXITCODE -ne 0) {
        throw "Lineage 16 prerequisite installation failed on $Distro."
    }
}

if (-not $SkipBootstrap) {
    $bootstrapArgs = @(
        '-ExecutionPolicy', 'Bypass',
        '-File', $bootstrapScript,
        '-Distro', $Distro,
        '-BuildRoot', $BuildRoot,
        '-Jobs', $Jobs
    )
    if ($SkipSync) {
        $bootstrapArgs += '-SkipSync'
    }

    & powershell.exe @bootstrapArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Lineage 16 bootstrap failed on $Distro."
    }
}

Write-Host "Lineage 16 WSL recovery complete for $Distro"
