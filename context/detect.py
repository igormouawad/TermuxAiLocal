from __future__ import annotations

import os
import platform
import subprocess
from pathlib import Path

from adapters.adb.runtime import adb_available, adb_devices_output, adb_get_state, parse_adb_devices
from core.models import DetectionResult


def detect_scenario() -> DetectionResult:
    host_kind = detect_host_kind()
    terminal_kind = detect_terminal_kind()
    known_android_ip = read_known_android_ip()
    ssh_remote_ip = detect_ssh_remote_ip()
    operator_context = detect_operator_context(ssh_remote_ip, known_android_ip)
    adb_is_available = adb_available()
    devices = parse_adb_devices(adb_devices_output() if adb_is_available else "")
    adb_transport = classify_transport(devices)
    adb_device_id = classify_device_id(devices, adb_transport)
    adb_state = adb_get_state(adb_device_id) if adb_device_id else ("device" if devices else "unavailable")
    scenario, session_risk, confidence, unsafe_reasons, evidence = classify_scenario(
        host_kind=host_kind,
        terminal_kind=terminal_kind,
        operator_context=operator_context,
        adb_available=adb_is_available,
        adb_transport=adb_transport,
        adb_state=adb_state,
        adb_device_id=adb_device_id,
        devices=devices,
    )

    return DetectionResult(
        scenario=scenario,
        host_kind=host_kind,
        terminal_kind=terminal_kind,
        operator_context=operator_context,
        adb_available=adb_is_available,
        adb_state=adb_state,
        adb_transport=adb_transport,
        adb_device_id=adb_device_id,
        known_android_ip=known_android_ip,
        ssh_remote_ip=ssh_remote_ip,
        session_risk=session_risk,
        confidence=confidence,
        unsafe_reasons=unsafe_reasons,
        evidence=evidence,
        adb_devices=devices,
    )


def detect_host_kind() -> str:
    system = platform.system().lower()
    if system == "linux":
        return "linux_workstation"
    return system or "unknown"


def detect_terminal_kind() -> str:
    if os.environ.get("KONSOLE_VERSION"):
        return "konsole"
    if os.environ.get("SSH_CONNECTION") or os.environ.get("SSH_CLIENT"):
        return "android_ssh_client"
    parent_chain = read_parent_command_chain()
    if "konsole" in parent_chain:
        return "konsole"
    if "sshd" in parent_chain:
        return "android_ssh_client"
    return "unknown"


def read_parent_command_chain() -> str:
    try:
        result = subprocess.run(
            ["ps", "-o", "comm=", "-p", str(os.getppid())],
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=4,
            check=False,
        )
    except Exception:
        return ""
    return result.stdout.strip().lower()


def detect_ssh_remote_ip() -> str:
    for key in ("SSH_CONNECTION", "SSH_CLIENT"):
        raw = os.environ.get(key, "").strip()
        if raw:
            return raw.split()[0]
    return ""


def read_known_android_ip() -> str:
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "termux-ai-local" / "adb"
    ip_file = cache_root / "last_network_ip"
    if not ip_file.exists():
        return ""
    return ip_file.read_text(encoding="utf-8").strip()


def detect_operator_context(ssh_remote_ip: str, known_android_ip: str) -> str:
    override = os.environ.get("TERMUXAI_OPERATOR_CONTEXT", "auto").strip()
    if override in {"android_ssh", "local_workstation"}:
        return override
    if ssh_remote_ip and known_android_ip and ssh_remote_ip == known_android_ip:
        return "android_ssh"
    return "local_workstation"


def classify_transport(devices: list[dict[str, object]]) -> str:
    usable = [device for device in devices if device.get("status") == "device"]
    usb = [device for device in usable if device.get("transport") == "usb"]
    network = [device for device in usable if device.get("transport") == "network"]
    if len(usb) == 1 and not network:
        return "usb"
    if len(network) == 1 and not usb:
        return "wifi"
    if usb and network:
        return "mixed"
    if len(usb) > 1 or len(network) > 1:
        return "ambiguous"
    return "none"


def classify_device_id(devices: list[dict[str, object]], transport: str) -> str:
    usable = [device for device in devices if device.get("status") == "device"]
    if transport == "usb":
        return next((str(device["serial"]) for device in usable if device.get("transport") == "usb"), "")
    if transport == "wifi":
        return next((str(device["serial"]) for device in usable if device.get("transport") == "network"), "")
    return ""


def classify_scenario(
    *,
    host_kind: str,
    terminal_kind: str,
    operator_context: str,
    adb_available: bool,
    adb_transport: str,
    adb_state: str,
    adb_device_id: str,
    devices: list[dict[str, object]],
) -> tuple[str, str, str, list[str], list[str]]:
    unsafe_reasons: list[str] = []
    evidence: list[str] = []

    if not adb_available:
        unsafe_reasons.append("adb_not_available")
    if adb_state not in {"device", "unknown"} and adb_device_id:
        unsafe_reasons.append(f"adb_state_{adb_state}")
    if adb_transport == "ambiguous":
        unsafe_reasons.append("multiple_transport_candidates")
    if adb_transport == "mixed":
        unsafe_reasons.append("usb_and_wifi_simultaneously_visible")
    if adb_transport == "none":
        unsafe_reasons.append("no_adb_device_in_state_device")

    evidence.append(f"host_kind={host_kind}")
    evidence.append(f"terminal_kind={terminal_kind}")
    evidence.append(f"operator_context={operator_context}")
    evidence.append(f"adb_transport={adb_transport}")
    evidence.append(f"adb_device_count={len([d for d in devices if d.get('status') == 'device'])}")

    if (
        host_kind == "linux_workstation"
        and operator_context == "local_workstation"
        and adb_transport == "usb"
        and adb_device_id
        and adb_state == "device"
    ):
        evidence.append("usb_target_available_on_local_workstation")
        return ("SCENARIO_1_LINUX_USB", "low", "high", unsafe_reasons, evidence)

    if (
        host_kind == "linux_workstation"
        and operator_context == "android_ssh"
        and adb_transport == "wifi"
        and adb_device_id
        and adb_state == "device"
    ):
        evidence.append("android_ssh_session_with_wifi_adb_target")
        return ("SCENARIO_2_ANDROID_WIFI", "high", "high", unsafe_reasons, evidence)

    if operator_context == "android_ssh":
        unsafe_reasons.append("android_ssh_without_valid_wifi_transport")
        evidence.append("android_ssh_context_requires_session_safety")
        return ("UNKNOWN_OR_UNSAFE", "high", "medium", unsafe_reasons, evidence)

    if unsafe_reasons:
        return ("UNKNOWN_OR_UNSAFE", "medium", "medium", unsafe_reasons, evidence)

    return ("UNKNOWN_OR_UNSAFE", "medium", "low", unsafe_reasons, evidence)
