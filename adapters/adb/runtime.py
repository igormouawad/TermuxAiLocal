from __future__ import annotations

import re
from typing import Any

from core.process import run_command


DEVICE_LINE_RE = re.compile(r"^(?P<serial>\S+)\s+(?P<status>\S+)(?P<rest>.*)$")


def adb_available() -> bool:
    try:
        completed = run_command(["adb", "version"], timeout=8)
    except FileNotFoundError:
        return False
    return completed.returncode == 0


def adb_devices_output() -> str:
    return run_command(["adb", "devices", "-l"], timeout=12).stdout


def parse_adb_devices(output: str) -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("List of devices attached"):
            continue
        match = DEVICE_LINE_RE.match(line)
        if not match:
            continue
        serial = match.group("serial")
        status = match.group("status")
        rest = match.group("rest").strip()
        devices.append(
            {
                "serial": serial,
                "status": status,
                "transport": (
                    "usb"
                    if (" usb:" in f" {rest}" or ":" not in serial)
                    else "network"
                ),
                "model": _extract_token(rest, "model"),
                "transport_id": _extract_token(rest, "transport_id"),
                "raw": line,
            }
        )
    return devices


def _extract_token(raw: str, key: str) -> str:
    for token in raw.split():
        if token.startswith(f"{key}:"):
            return token.split(":", 1)[1]
    return ""


def adb_get_state(serial: str = "") -> str:
    command = ["adb"]
    if serial:
        command += ["-s", serial]
    command += ["get-state"]
    result = run_command(command, timeout=8)
    if result.returncode != 0:
        return "unavailable"
    return result.stdout.strip() or "unknown"


def adb_shell(serial: str, *args: str, timeout: int = 12) -> str:
    command = ["adb"]
    if serial:
        command += ["-s", serial]
    command += ["shell", *args]
    return run_command(command, timeout=timeout).stdout.replace("\r", "")


def desktopmode_dump(serial: str) -> str:
    return adb_shell(serial, "wm", "shell", "desktopmode", "dump", timeout=12)


def parse_desktopmode_state(dump_output: str) -> dict[str, Any]:
    active = "inDesktopWindowing=true" in dump_output
    active_desk = ""
    visible_tasks: list[str] = []
    current_desk = ""
    in_current_desk = False

    for line in dump_output.splitlines():
        stripped = line.strip()
        if stripped.startswith("activeDesk="):
            active_desk = stripped.split("=", 1)[1].strip()
        elif stripped.startswith("Desk #"):
            desk_marker = stripped.split(":", 1)[0]
            current_desk = desk_marker.split("#", 1)[1]
            in_current_desk = current_desk == active_desk
        elif in_current_desk and "visibleTasks=[" in stripped:
            content = stripped.split("visibleTasks=[", 1)[1].split("]", 1)[0]
            visible_tasks = [item.strip() for item in content.split(",") if item.strip()]
            break

    return {
        "active": active,
        "active_desk": "" if active_desk == "null" else active_desk,
        "visible_tasks": visible_tasks,
    }


def list_packages(serial: str) -> set[str]:
    output = adb_shell(serial, "pm", "list", "packages", timeout=18)
    packages: set[str] = set()
    for line in output.splitlines():
        if line.startswith("package:"):
            packages.add(line.split(":", 1)[1].strip())
    return packages


def current_focus(serial: str) -> str:
    output = adb_shell(serial, "dumpsys", "window", timeout=16)
    focus_lines = [
        line.strip()
        for line in output.splitlines()
        if "mCurrentFocus" in line or "mFocusedApp" in line
    ]
    return " | ".join(focus_lines[-4:])
