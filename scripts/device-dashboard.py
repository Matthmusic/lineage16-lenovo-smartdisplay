from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import threading
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
HTML_PATH = SCRIPTS_DIR / "device-dashboard.html"
DEFAULT_VENV_PYTHON = PROJECT_ROOT / ".venv-edl" / "Scripts" / "python.exe"
DEFAULT_ADB = Path(r"C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\adb.exe")
DEFAULT_FASTBOOT = Path(r"C:\Program Files (x86)\Touch Portal\plugins\adb\platform-tools\fastboot.exe")
DEFAULT_LOADER = Path(
    r"C:\Users\Matthieu MAUREL\Downloads\amber_blueberry_firehose\amber_bluebbery_prog_emmc_firehose_8953_ddr.mbn"
)
DEFAULT_BOOT_IMAGE = PROJECT_ROOT / "backup" / "boot_a_32mb.img"
DEFAULT_FACTORY_DIR = Path(r"C:\Users\Matthieu MAUREL\Downloads\Blueberry-factory-S0.28.20-4757977-debug")
DEFAULT_FACTORY_PARTITION_TABLE = DEFAULT_FACTORY_DIR / "partition-table.img"
DEFAULT_GOLDEN_BASELINE_ROOT = PROJECT_ROOT / "memory" / "golden-baseline"
DEFAULT_WSL_CONFIG_PATH = PROJECT_ROOT / "memory" / "lineage16-wsl.json"
JOB_STATE_ROOT = PROJECT_ROOT / "memory" / "dashboard-jobs"
DEFAULT_LINEAGE16_DISTRO = "Ubuntu-20.04-Lineage16"
DEFAULT_LINEAGE16_SOURCE_DISTRO = "Ubuntu-20.04"
DEFAULT_LINEAGE16_INSTALL_LOCATION = r"E:\WSL\Ubuntu-20.04-Lineage16"
DEFAULT_LINEAGE16_ROOTFS_ARCHIVE = Path(r"E:\WSL\ubuntu2004_x64\install.tar.gz")
DEFAULT_LINEAGE16_BUILD_ROOT = "/build/lineage16-blueberry"


def default_artifact_root(distro: str = DEFAULT_LINEAGE16_DISTRO, build_root: str = DEFAULT_LINEAGE16_BUILD_ROOT) -> Path:
    return Path(rf"\\wsl$\{distro}{build_root.replace('/', '\\')}\out\target\product\blueberry")


def iso_now() -> str:
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def job_stamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def safe_name(value: str) -> str:
    return "".join(char if char.isalnum() or char in {"-", "_"} else "-" for char in value)


def resolve_tool(names: list[str], fallback: Path | None = None) -> Path | None:
    for name in names:
        resolved = shutil.which(name)
        if resolved:
            return Path(resolved)
    if fallback and fallback.exists():
        return fallback
    return None


def run_command(command: list[str], timeout: int = 8) -> dict[str, Any]:
    try:
        result = subprocess.run(
            command,
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            timeout=timeout,
            errors="replace",
            check=False,
        )
        return {
            "ok": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
        }
    except FileNotFoundError:
        return {"ok": False, "returncode": None, "stdout": "", "stderr": "command not found"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "returncode": None, "stdout": "", "stderr": "command timed out"}


def run_powershell_json(script: str) -> list[dict[str, Any]]:
    result = run_command(["powershell.exe", "-NoProfile", "-Command", script], timeout=10)
    if not result["stdout"]:
        return []
    try:
        parsed = json.loads(result["stdout"])
    except json.JSONDecodeError:
        return []
    if isinstance(parsed, list):
        return parsed
    if isinstance(parsed, dict):
        return [parsed]
    return []


def probe_paths(paths: list[str], timeout: int = 4) -> dict[str, dict[str, Any]]:
    quoted = ", ".join("'" + path.replace("'", "''") + "'" for path in paths)
    script = f"""
$targets = @({quoted})
$result = foreach ($path in $targets) {{
  if (Test-Path -LiteralPath $path) {{
    $item = Get-Item -LiteralPath $path
    [pscustomobject]@{{
      path = $path
      exists = $true
      size = if ($item.PSIsContainer) {{ $null }} else {{ $item.Length }}
    }}
  }} else {{
    [pscustomobject]@{{
      path = $path
      exists = $false
      size = $null
    }}
  }}
}}
$result | ConvertTo-Json -Compress
"""
    result = run_command(["powershell.exe", "-NoProfile", "-Command", script], timeout=timeout)
    if not result["ok"] or not result["stdout"]:
        return {path: {"exists": False, "size": None} for path in paths}
    try:
        payload = json.loads(result["stdout"])
    except json.JSONDecodeError:
        return {path: {"exists": False, "size": None} for path in paths}
    if isinstance(payload, dict):
        payload = [payload]
    discovered: dict[str, dict[str, Any]] = {path: {"exists": False, "size": None} for path in paths}
    for item in payload:
        if isinstance(item, dict) and item.get("path") in discovered:
            discovered[item["path"]] = {"exists": bool(item.get("exists")), "size": item.get("size")}
    return discovered


def tail_lines(path: Path, max_lines: int = 300) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    lines = text.splitlines()
    return lines[-max_lines:]


def load_wsl_config() -> dict[str, str]:
    default = {
        "distro": DEFAULT_LINEAGE16_DISTRO,
        "install_location": DEFAULT_LINEAGE16_INSTALL_LOCATION,
        "build_root": DEFAULT_LINEAGE16_BUILD_ROOT,
        "artifact_root": str(default_artifact_root()),
    }
    if not DEFAULT_WSL_CONFIG_PATH.exists():
        return default
    try:
        payload = json.loads(DEFAULT_WSL_CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return default
    if not isinstance(payload, dict):
        return default
    return {
        "distro": str(payload.get("distro") or default["distro"]),
        "build_root": str(payload.get("build_root") or default["build_root"]),
        "artifact_root": str(payload.get("artifact_root") or default["artifact_root"]),
        "install_location": str(payload.get("install_location") or default["install_location"]),
        "updated_at": str(payload.get("updated_at") or ""),
    }


def collect_usb_devices() -> list[dict[str, str]]:
    script = r"""
$devices = Get-PnpDevice -PresentOnly | Where-Object {
  $_.InstanceId -match 'VID_05C6&PID_9008|VID_05C6&PID_900E|VID_05C6&PID_901D|VID_18D1' -or
  $_.FriendlyName -match '9008|900E|901D|QUSB|Qualcomm|Fastboot|Android|ADB'
} | Select-Object Status, Class, FriendlyName, InstanceId
$devices | ConvertTo-Json -Compress
"""
    entries = []
    for item in run_powershell_json(script):
        entries.append(
            {
                "status": item.get("Status", ""),
                "class_name": item.get("Class", ""),
                "friendly_name": item.get("FriendlyName", ""),
                "instance_id": item.get("InstanceId", ""),
            }
        )
    return entries


def parse_adb_devices(output: str) -> list[dict[str, str]]:
    devices = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith("List of devices"):
            continue
        parts = line.split()
        devices.append(
            {
                "serial": parts[0],
                "state": parts[1] if len(parts) > 1 else "",
                "details": " ".join(parts[2:]) if len(parts) > 2 else "",
            }
        )
    return devices


def parse_fastboot_devices(output: str) -> list[dict[str, str]]:
    devices = []
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        devices.append(
            {
                "serial": parts[0],
                "details": " ".join(parts[1:]) if len(parts) > 1 else "",
            }
        )
    return devices


def adb_shell(adb_path: Path | None, *args: str, timeout: int = 12) -> str:
    if not adb_path:
        return ""
    result = run_command([str(adb_path), "shell", *args], timeout=timeout)
    return result["stdout"] if result["ok"] else ""


def collect_adb_context(adb_path: Path | None, adb_devices: list[dict[str, str]]) -> dict[str, str]:
    if not adb_path or not adb_devices:
        return {}

    props = {
        "slot_suffix": adb_shell(adb_path, "getprop", "ro.boot.slot_suffix"),
        "fingerprint": adb_shell(adb_path, "getprop", "ro.build.fingerprint"),
        "build_display_id": adb_shell(adb_path, "getprop", "ro.build.display.id"),
        "release": adb_shell(adb_path, "getprop", "ro.build.version.release"),
        "verified_boot_state": adb_shell(adb_path, "getprop", "ro.boot.verifiedbootstate"),
        "usb_config": adb_shell(adb_path, "getprop", "sys.usb.config"),
        "model": adb_shell(adb_path, "getprop", "ro.product.model"),
    }

    focus_dump = adb_shell(adb_path, "dumpsys", "window", "windows")
    props["focus"] = ""
    for line in focus_dump.splitlines():
        if "mCurrentFocus" in line or "mFocusedApp" in line:
            props["focus"] = line.strip()
            break

    disabled = adb_shell(adb_path, "pm", "list", "packages", "-d", timeout=20)
    props["disabled_factory"] = "com.a3nod.lenovo.sparrowfactory" if "com.a3nod.lenovo.sparrowfactory" in disabled else ""
    return {key: value.strip() for key, value in props.items() if value.strip()}


def detect_build_artifacts(artifact_root: str) -> dict[str, Any]:
    artifact_dir = Path(artifact_root)
    image_paths = {
        "boot": artifact_dir / "boot.img",
        "system": artifact_dir / "system.img",
        "vendor": artifact_dir / "vendor.img",
        "vbmeta": artifact_dir / "vbmeta.img",
        "dtbo": artifact_dir / "dtbo.img",
    }
    probed = probe_paths([str(artifact_dir)] + [str(path) for path in image_paths.values()])
    images: dict[str, dict[str, Any]] = {}
    ready = True
    for name, path in image_paths.items():
        entry = probed.get(str(path), {"exists": False, "size": None})
        exists = bool(entry["exists"])
        images[name] = {
            "exists": exists,
            "path": str(path),
            "size": entry["size"] if exists else None,
        }
        if name != "dtbo" and not exists:
            ready = False
    root_exists = bool(probed.get(str(artifact_dir), {"exists": False})["exists"])
    return {
        "root": str(artifact_dir),
        "exists": root_exists,
        "ready": root_exists and ready,
        "images": images,
    }


def latest_baseline_snapshot() -> dict[str, str]:
    if not DEFAULT_GOLDEN_BASELINE_ROOT.exists():
        return {}
    candidates = [item for item in DEFAULT_GOLDEN_BASELINE_ROOT.iterdir() if item.is_dir()]
    if not candidates:
        return {}
    latest = sorted(candidates, key=lambda item: item.name)[-1]
    return {"name": latest.name, "path": str(latest)}


def compute_state(
    adb_devices: list[dict[str, str]],
    fastboot_devices: list[dict[str, str]],
    usb_devices: list[dict[str, str]],
) -> tuple[dict[str, str], str]:
    has_9008 = any("VID_05C6&PID_9008" in item["instance_id"] or "9008" in item["friendly_name"] for item in usb_devices)
    has_900e = any("VID_05C6&PID_900E" in item["instance_id"] or "900E" in item["friendly_name"] for item in usb_devices)
    has_901d = any("VID_05C6&PID_901D" in item["instance_id"] or "901D" in item["friendly_name"] for item in usb_devices)
    has_broken_qdloader = any(
        ("VID_05C6&PID_9008" in item["instance_id"] or "9008" in item["friendly_name"])
        and item["status"].lower() != "ok"
        and item["class_name"] == "Ports"
        for item in usb_devices
    )
    has_broken_901d = any(
        ("VID_05C6&PID_901D" in item["instance_id"] or "901D" in item["friendly_name"])
        and item["status"].lower() != "ok"
        for item in usb_devices
    )

    if fastboot_devices:
        return (
            {"code": "fastboot", "label": "Fastboot disponible"},
            "Le bootloader est visible. Le device est hors du brick profond et les actions fastboot redeviennent pertinentes.",
        )
    if adb_devices:
        return (
            {"code": "adb", "label": "ADB disponible"},
            "L'appareil expose Android via adb. Le sujet n'est plus EDL mais l'acces logiciel normal et la sortie propre du mode factory. Si l'ecran affiche Android Things 0.4.5-N avec 'Not connected peripheral I/O ports', c'est coherent avec ce build IoT de reference.",
        )
    if has_9008:
        return (
            {"code": "qualcomm_9008", "label": "Qualcomm 9008"},
            (
                "Le mode EDL est present mais rebinde sur le driver Qualcomm casse. "
                "Repasser le 9008 sur WinUSB avant de relancer la restauration stock."
                if has_broken_qdloader else
                "Le mode EDL flashable est present. L'action utile dans cet etat est le restore factory exact, pas les anciens restores partiels."
            ),
        )
    if has_901d:
        return (
            {"code": "android_901d", "label": "Android / Factory 901D"},
            (
                "Le device n'est plus en 9008 et le dernier constat visuel est 'sparrow factory'. Le blocage restant est cote driver Windows sur le PID 901D."
                if has_broken_901d else
                "Le device expose le mode Android USB diag,adb (PID 901D). Le brick profond semble passe; si le driver ADB est bon, adb devrait redevenir visible."
            ),
        )
    if has_900e:
        return (
            {"code": "qualcomm_900e", "label": "Qualcomm 900E"},
            "Le SoC repond en Sahara, mais pas encore dans le mode flash 9008.",
        )
    if usb_devices:
        return (
            {"code": "unknown", "label": "USB detecte"},
            "Un peripherique lie au device est visible, mais aucun transport utile n'est confirme.",
        )
    return (
        {"code": "none", "label": "Aucun transport utile"},
        "Ni adb, ni fastboot, ni Qualcomm exploitable n'ont ete detectes.",
    )


def compute_phase(state_code: str, recovery_armed: bool) -> dict[str, str]:
    if recovery_armed:
        return {
            "code": "recovery_mode",
            "label": "Recovery Mode",
            "description": "Les actions EDL/debrick sont armees. Les operations de recovery redeviennent visibles.",
        }
    if state_code in {"android_901d", "adb", "fastboot"}:
        return {
            "code": "port_mode",
            "label": "Port Mode",
            "description": "Mode normal de portage. Slot a reste la baseline, slot b est reserve aux essais.",
        }
    if state_code == "qualcomm_9008":
        return {
            "code": "recovery_standby",
            "label": "Recovery standby",
            "description": "EDL est disponible, mais les actions de recovery restent masquees tant qu'elles ne sont pas armees.",
        }
    if state_code == "qualcomm_900e":
        return {
            "code": "edl_transition",
            "label": "Transition 900E vers 9008",
            "description": "Le SoC repond au boot ROM, mais il faut encore atteindre un mode flashable.",
        }
    return {
        "code": "diagnostic",
        "label": "Diagnostic transport",
        "description": "Aucun chemin stable n'est confirme. La priorite est d'identifier le transport actif.",
    }


def build_session_notes(state_code: str, recovery_armed: bool, artifacts_ready: bool) -> list[str]:
    notes: list[str] = []
    if state_code == "adb":
        notes.extend(
            [
                "Le slot a est la baseline a geler avant tout essai custom.",
                "Ne pas tester TWRP ou une recovery custom avant un boot Lineage 16 stable avec adb.",
            ]
        )
    if state_code == "qualcomm_9008":
        notes.append("Le device est en 9008. Le recovery reste derriere un armement explicite.")
    if state_code == "qualcomm_900e":
        notes.append("Le 900E permet un handshake Sahara mais pas un flash utile.")
    if artifacts_ready:
        notes.append("Les artefacts Lineage 16 minimaux existent deja: boot, system, vendor, vbmeta.")
    else:
        notes.append("Les artefacts Lineage 16 ne sont pas encore complets. Le flash slot b restera masque.")
    if recovery_armed:
        notes.append("Recovery Mode est arme: les actions EDL sont visibles tant que ce mode reste actif.")
    else:
        notes.append("Recovery Mode est desarme: les actions EDL sont masquees pour eviter les clics accidentels.")
    return notes


@dataclass
class Job:
    action_id: str
    label: str
    command: list[str]
    cwd: Path
    started_at: str
    log_path: str | None = None
    status_path: str | None = None
    process: subprocess.Popen[str] | None = None
    status: str = "starting"
    ended_at: str | None = None
    returncode: int | None = None
    lines: deque[str] = field(default_factory=lambda: deque(maxlen=300))

    def is_running(self) -> bool:
        return self.process is not None and self.process.poll() is None

    def summary(self) -> dict[str, Any]:
        return {
            "id": self.action_id,
            "label": self.label,
            "command": " ".join(self.command),
            "status": self.status,
            "started_at": self.started_at,
            "ended_at": self.ended_at,
            "returncode": self.returncode,
            "log_path": self.log_path,
            "lines": list(self.lines),
        }


class JobManager:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        JOB_STATE_ROOT.mkdir(parents=True, exist_ok=True)
        self._jobs: dict[str, Job] = {}
        self._archived_jobs = self._load_archived_jobs()

    def _load_archived_jobs(self) -> dict[str, dict[str, Any]]:
        archived: dict[str, dict[str, Any]] = {}
        for status_path in sorted(JOB_STATE_ROOT.glob("*.json")):
            try:
                payload = json.loads(status_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(payload, dict) or not payload.get("id"):
                continue

            log_path = Path(str(payload.get("log_path") or ""))
            payload["lines"] = tail_lines(log_path) if log_path else []
            if payload.get("status") == "running":
                payload["status"] = "detached"
            archived[str(payload["id"])] = payload
        return archived

    def _log_path_for(self, action_id: str) -> Path:
        return JOB_STATE_ROOT / f"{safe_name(action_id)}-{job_stamp()}.log"

    def _status_path_for(self, action_id: str) -> Path:
        return JOB_STATE_ROOT / f"{safe_name(action_id)}.json"

    def _append_log(self, job: Job, line: str) -> None:
        if not job.log_path:
            return
        with Path(job.log_path).open("a", encoding="utf-8") as handle:
            handle.write(line.rstrip() + "\n")

    def _write_status(self, job: Job) -> None:
        if not job.status_path:
            return
        payload = job.summary()
        payload["cwd"] = str(job.cwd)
        Path(job.status_path).write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
        self._archived_jobs[job.action_id] = payload

    def start(self, action_id: str, label: str, command: list[str], cwd: Path) -> Job:
        with self._lock:
            existing = self._jobs.get(action_id)
            if existing and existing.is_running():
                return existing

            log_path = self._log_path_for(action_id)
            status_path = self._status_path_for(action_id)
            process = subprocess.Popen(
                command,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                errors="replace",
            )
            job = Job(
                action_id=action_id,
                label=label,
                command=command,
                cwd=cwd,
                started_at=iso_now(),
                log_path=str(log_path),
                status_path=str(status_path),
                process=process,
                status="running",
            )
            job.lines.append(f"$ {' '.join(command)}")
            self._append_log(job, f"$ {' '.join(command)}")
            self._write_status(job)
            self._jobs[action_id] = job

        threading.Thread(target=self._pump_output, args=(job,), daemon=True).start()
        threading.Thread(target=self._watch_process, args=(job,), daemon=True).start()
        return job

    def _pump_output(self, job: Job) -> None:
        assert job.process and job.process.stdout
        for line in job.process.stdout:
            with self._lock:
                message = line.rstrip()
                job.lines.append(message)
                self._append_log(job, message)
                self._write_status(job)

    def _watch_process(self, job: Job) -> None:
        assert job.process
        code = job.process.wait()
        with self._lock:
            if job.status != "stopped":
                job.status = "finished" if code == 0 else "failed"
            job.returncode = code
            job.ended_at = iso_now()
            self._write_status(job)

    def stop(self, action_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(action_id)
            if not job or not job.is_running():
                return False
            pid = job.process.pid if job.process else None
            job.status = "stopping"

        if pid is not None:
            subprocess.run(["taskkill.exe", "/PID", str(pid), "/T", "/F"], capture_output=True, text=True, check=False)

        with self._lock:
            if job:
                job.status = "stopped"
                job.ended_at = iso_now()
                job.returncode = job.process.poll() if job.process else None
                job.lines.append("Process stopped by dashboard.")
                self._append_log(job, "Process stopped by dashboard.")
                self._write_status(job)
        return True

    def summaries(self) -> list[dict[str, Any]]:
        with self._lock:
            summaries = [job.summary() for job in self._jobs.values()]
            active_ids = {job["id"] for job in summaries}
            summaries.extend(job for action_id, job in self._archived_jobs.items() if action_id not in active_ids)
            return sorted(summaries, key=lambda item: str(item.get("started_at") or ""))

    def is_running(self, action_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(action_id)
            return bool(job and job.is_running())


class DashboardState:
    def __init__(self) -> None:
        self.jobs = JobManager()
        self.python_path = resolve_tool(["python.exe", "python"], DEFAULT_VENV_PYTHON if DEFAULT_VENV_PYTHON.exists() else None)
        self.adb_path = resolve_tool(["adb.exe", "adb"], DEFAULT_ADB)
        self.fastboot_path = resolve_tool(["fastboot.exe", "fastboot"], DEFAULT_FASTBOOT)
        self.recovery_armed = False
        self.wsl_config = load_wsl_config()

    def set_recovery_mode(self, armed: bool) -> None:
        self.recovery_armed = armed

    def action_definitions(self) -> dict[str, dict[str, Any]]:
        self.wsl_config = load_wsl_config()
        distro = self.wsl_config["distro"]
        build_root = self.wsl_config["build_root"]
        install_location = self.wsl_config.get("install_location") or DEFAULT_LINEAGE16_INSTALL_LOCATION
        artifact_root = self.wsl_config["artifact_root"]
        return {
            "provision_lineage16_clean_wsl": {
                "label": "Provisionner WSL clean E:",
                "description": "Importe une Ubuntu 20.04 dediee depuis l'archive locale sur E:, puis ecrit memory/lineage16-wsl.json sans lancer la sync.",
                "always_visible": True,
                "command": [
                    "powershell.exe",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(SCRIPTS_DIR / "recover-lineage16-wsl.ps1"),
                    "-Distro",
                    distro,
                    "-InstallLocation",
                    install_location,
                    "-BuildRoot",
                    build_root,
                    "-InstallSource",
                    DEFAULT_LINEAGE16_SOURCE_DISTRO,
                    "-ForceRecreate",
                    "-SkipBootstrap",
                ],
            },
            "install_lineage16_wsl_prereqs": {
                "label": "Installer prerequis WSL",
                "description": "Installe les dependances de build et repo dans la distro dediee, avec sortie verbeuse pour le suivi.",
                "always_visible": True,
                "command": [
                    "powershell.exe",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(SCRIPTS_DIR / "install-lineage16-wsl-prereqs.ps1"),
                    "-Distro",
                    distro,
                ],
            },
            "recover_lineage16_wsl": {
                "label": "Workflow complet WSL 16.0",
                "description": "Provisionne la distro clean si besoin, installe les prerequis, ecrit la config WSL et lance le bootstrap Lineage 16.",
                "always_visible": True,
                "command": [
                    "powershell.exe",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(SCRIPTS_DIR / "recover-lineage16-wsl.ps1"),
                    "-Distro",
                    distro,
                    "-InstallLocation",
                    install_location,
                    "-BuildRoot",
                    build_root,
                    "-InstallSource",
                    DEFAULT_LINEAGE16_SOURCE_DISTRO,
                    "-InstallPrereqs",
                ],
            },
            "bootstrap_lineage16_wsl": {
                "label": "Bootstrap WSL 16.0",
                "description": "Initialise le checkout Lineage 16 parallele dans WSL a partir du manifest et du seed blueberry.",
                "always_visible": True,
                "command": [
                    "powershell.exe",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(SCRIPTS_DIR / "bootstrap-lineage16-blueberry-wsl.ps1"),
                    "-Distro",
                    distro,
                    "-BuildRoot",
                    build_root,
                ],
            },
            "capture_baseline": {
                "label": "Capturer la baseline",
                "description": "Fige l'etat adb/USB actuel, les hashes de recovery et l'inventaire des artefacts valides.",
                "states": {"adb"},
                "command": ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(SCRIPTS_DIR / "freeze-blueberry-golden-baseline.ps1")],
            },
            "flash_lineage16_slot_b": {
                "label": "Flasher Lineage16 sur slot b",
                "description": "Valide les artefacts, ecrit uniquement boot/system/vendor/vbmeta du slot b, puis bascule sur b.",
                "states": {"adb", "fastboot"},
                "requires_artifacts": True,
                "command": [
                    "powershell.exe",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(SCRIPTS_DIR / "flash-lineage16-slot-b.ps1"),
                    "-ArtifactDir",
                    artifact_root,
                    "-ArmSlotSwitch",
                    "-Reboot",
                ],
            },
            "rollback_slot_a": {
                "label": "Rollback vers slot a",
                "description": "Revient vers le slot a par fastboot si possible, puis passe en recovery EDL seulement si necessaire.",
                "states": {"adb", "fastboot", "qualcomm_9008"},
                "command": [
                    "powershell.exe",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(SCRIPTS_DIR / "rollback-blueberry-slot-a.ps1"),
                    "-PreferFastboot",
                    "-Reboot",
                ],
            },
            "sahara_reset": {
                "label": "Sahara Reset 900E",
                "description": "Envoie un reset Sahara au device actuellement en 900E.",
                "states": {"qualcomm_900e"},
                "requires_recovery_arm": True,
                "command": ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(SCRIPTS_DIR / "sahara-reset-900e.ps1")],
            },
            "edl_restore_factory": {
                "label": "Restore factory exact",
                "description": "Reecrit la GPT factory exacte et le jeu de partitions de recuperation factory.",
                "states": {"qualcomm_9008"},
                "requires_recovery_arm": True,
                "command": ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(SCRIPTS_DIR / "edl-restore-blueberry-factory.ps1")],
            },
            "edl_restore_normal": {
                "label": "Restore normal depuis backups",
                "description": "Reecrit la GPT exacte puis les partitions Android Things depuis les backups locaux.",
                "states": {"qualcomm_9008"},
                "requires_recovery_arm": True,
                "command": ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(SCRIPTS_DIR / "edl-restore-blueberry-normal.ps1")],
            },
        }

    def visible_actions(self, state_code: str, artifacts: dict[str, Any]) -> list[dict[str, Any]]:
        actions = self.action_definitions()
        return [
            {
                "id": action_id,
                "label": action["label"],
                "description": action["description"],
                "running": self.jobs.is_running(action_id),
                "dangerous": bool(action.get("requires_recovery_arm")),
            }
            for action_id, action in actions.items()
            if (
                (action.get("always_visible") or state_code in action.get("states", set()))
                and (not action.get("requires_recovery_arm") or self.recovery_armed)
                and (not action.get("requires_artifacts") or artifacts.get("ready"))
            )
        ]

    def visible_assets(self, state_code: str, artifacts: dict[str, Any], adb_context: dict[str, str]) -> dict[str, dict[str, Any]]:
        assets = {
            "manifest_16": {"exists": (PROJECT_ROOT / "blueberry_manifest_lineage16.xml").exists(), "path": str(PROJECT_ROOT / "blueberry_manifest_lineage16.xml")},
            "seed_tree": {"exists": (PROJECT_ROOT / "lineage16_seed").exists(), "path": str(PROJECT_ROOT / "lineage16_seed")},
            "golden_baseline_root": {"exists": DEFAULT_GOLDEN_BASELINE_ROOT.exists(), "path": str(DEFAULT_GOLDEN_BASELINE_ROOT)},
            "dashboard_jobs": {"exists": JOB_STATE_ROOT.exists(), "path": str(JOB_STATE_ROOT)},
            "wsl_config": {"exists": DEFAULT_WSL_CONFIG_PATH.exists(), "path": str(DEFAULT_WSL_CONFIG_PATH)},
            "wsl_rootfs_archive": {"exists": DEFAULT_LINEAGE16_ROOTFS_ARCHIVE.exists(), "path": str(DEFAULT_LINEAGE16_ROOTFS_ARCHIVE)},
            "loader": {"exists": DEFAULT_LOADER.exists(), "path": str(DEFAULT_LOADER)},
            "factory_package": {"exists": DEFAULT_FACTORY_DIR.exists(), "path": str(DEFAULT_FACTORY_DIR)},
            "partition_table": {"exists": DEFAULT_FACTORY_PARTITION_TABLE.exists(), "path": str(DEFAULT_FACTORY_PARTITION_TABLE)},
            "lineage16_artifacts": {"exists": artifacts.get("exists", False), "path": artifacts.get("root", "")},
        }
        if state_code in {"adb", "fastboot"}:
            assets["boot_image"] = {"exists": DEFAULT_BOOT_IMAGE.exists(), "path": str(DEFAULT_BOOT_IMAGE)}
        if adb_context.get("slot_suffix"):
            assets["current_slot"] = {"exists": True, "path": adb_context["slot_suffix"]}
        return assets

    def collect(self) -> dict[str, Any]:
        adb_result = {"stdout": "", "stderr": "adb not found"}
        fastboot_result = {"stdout": "", "stderr": "fastboot not found"}
        adb_devices: list[dict[str, str]] = []
        fastboot_devices: list[dict[str, str]] = []

        if self.adb_path:
            adb_result = run_command([str(self.adb_path), "devices", "-l"])
            adb_devices = parse_adb_devices(adb_result["stdout"])

        if self.fastboot_path:
            fastboot_result = run_command([str(self.fastboot_path), "devices"])
            fastboot_devices = parse_fastboot_devices(fastboot_result["stdout"])

        usb_devices = collect_usb_devices()
        adb_context = collect_adb_context(self.adb_path, adb_devices)
        self.wsl_config = load_wsl_config()
        artifacts = detect_build_artifacts(self.wsl_config["artifact_root"])
        latest_baseline = latest_baseline_snapshot()
        state, recommendation = compute_state(adb_devices, fastboot_devices, usb_devices)
        phase = compute_phase(state["code"], self.recovery_armed)

        return {
            "timestamp": iso_now(),
            "state": state,
            "phase": phase,
            "mode": {
                "recovery_armed": self.recovery_armed,
                "label": "Recovery Mode" if self.recovery_armed else "Port Mode",
            },
            "recommendation": recommendation,
            "session_notes": build_session_notes(state["code"], self.recovery_armed, artifacts["ready"]),
            "tools": {
                "python": {"available": self.python_path is not None, "path": str(self.python_path) if self.python_path else None},
                "adb": {"available": self.adb_path is not None, "path": str(self.adb_path) if self.adb_path else None},
                "fastboot": {"available": self.fastboot_path is not None, "path": str(self.fastboot_path) if self.fastboot_path else None},
                "edl_py": {"available": (PROJECT_ROOT / "tools" / "edl" / "edl.py").exists(), "path": str(PROJECT_ROOT / "tools" / "edl" / "edl.py")},
            },
            "wsl_config": self.wsl_config,
            "adb_context": adb_context,
            "artifacts": artifacts,
            "latest_baseline": latest_baseline,
            "assets": self.visible_assets(state["code"], artifacts, adb_context),
            "adb": {"devices": adb_devices, "stderr": adb_result["stderr"]},
            "fastboot": {"devices": fastboot_devices, "stderr": fastboot_result["stderr"]},
            "usb_devices": usb_devices,
            "jobs": self.jobs.summaries(),
            "actions": self.visible_actions(state["code"], artifacts),
        }

    def start_action(self, action_id: str) -> dict[str, Any]:
        action = self.action_definitions().get(action_id)
        if not action:
            raise KeyError(action_id)
        return self.jobs.start(action_id, action["label"], action["command"], PROJECT_ROOT).summary()

    def stop_action(self, action_id: str) -> bool:
        return self.jobs.stop(action_id)


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "SmartDisplayDashboard/2.0"

    @property
    def dashboard(self) -> DashboardState:
        return self.server.dashboard  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, content: str) -> None:
        body = content.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            self._send_html(HTML_PATH.read_text(encoding="utf-8"))
            return
        if path == "/api/status":
            self._send_json(self.dashboard.collect())
            return
        self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path.startswith("/api/actions/"):
            action_id = path.rsplit("/", 1)[-1]
            try:
                payload = self.dashboard.start_action(action_id)
            except KeyError:
                self._send_json({"error": f"unknown action: {action_id}"}, HTTPStatus.NOT_FOUND)
                return
            self._send_json(payload, HTTPStatus.ACCEPTED)
            return

        if path == "/api/recovery/arm":
            self.dashboard.set_recovery_mode(True)
            self._send_json({"ok": True, "recovery_armed": True})
            return

        if path == "/api/recovery/disarm":
            self.dashboard.set_recovery_mode(False)
            self._send_json({"ok": True, "recovery_armed": False})
            return

        if path.startswith("/api/jobs/") and path.endswith("/stop"):
            action_id = path.strip("/").split("/")[2]
            if not self.dashboard.stop_action(action_id):
                self._send_json({"error": f"job not running: {action_id}"}, HTTPStatus.NOT_FOUND)
                return
            self._send_json({"ok": True})
            return

        self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)


def main() -> None:
    parser = argparse.ArgumentParser(description="Smart Display recovery and porting dashboard")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), DashboardHandler)
    server.dashboard = DashboardState()  # type: ignore[attr-defined]
    print(f"Dashboard running on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
