[CmdletBinding()]
param(
    [string]$PythonExe,
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path $PSScriptRoot -Parent
}

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $PythonExe = Join-Path $ProjectRoot '.venv-edl\Scripts\python.exe'
}

if (-not (Test-Path $PythonExe)) {
    throw "Python executable not found: $PythonExe"
}

$edlRoot = Join-Path $ProjectRoot 'tools\edl'
if (-not (Test-Path $edlRoot)) {
    throw "edl repository not found: $edlRoot"
}

$script = @'
import sys
sys.path.insert(0, r"{EDL_ROOT}")

from edlclient.Library.Connection.usblib import usb_class
from edlclient.Library.sahara import sahara

portconfig = [[0x05C6, 0x900E, -1]]
cdc = usb_class(portconfig=portconfig, loglevel=10)
cdc.timeout = 1500

print("Waiting for 05c6:900e ...")
if not cdc.connect():
    print("No 900E device detected.")
    raise SystemExit(1)

print(f"Connected VID:PID = {cdc.vid:04x}:{cdc.pid:04x}")
s = sahara(cdc, loglevel=10)
resp = s.connect()
print(f"Sahara response: {resp}")
result = s.cmd_reset()
print(f"Sahara reset result: {result}")
raise SystemExit(0 if result else 1)
'@.Replace('{EDL_ROOT}', $edlRoot.Replace('\', '\\'))

$tempScript = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.py')

try {
    [System.IO.File]::WriteAllText($tempScript, $script, [System.Text.UTF8Encoding]::new($false))
    & $PythonExe $tempScript
    exit $LASTEXITCODE
}
finally {
    if (Test-Path $tempScript) {
        Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
    }
}
