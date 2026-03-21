from __future__ import annotations

from adapters.adb.runtime import current_focus, desktopmode_dump, parse_desktopmode_state
from adapters.termux.runtime import critical_app_status
from core.models import DetectionResult, PreflightResult


def run_preflight(detection: DetectionResult) -> PreflightResult:
    warnings: list[str] = []
    errors: list[str] = []
    critical_apps: dict[str, bool] = {}
    desktop_mode_active: bool | None = None
    active_desk = ""
    visible_tasks: list[str] = []
    focus_summary = ""

    if not detection.adb_device_id or detection.adb_state != "device":
        errors.append("Nenhum target ADB em estado device está disponível para preflight detalhado.")
        return PreflightResult(
            detection=detection,
            critical_apps=critical_apps,
            desktop_mode_active=None,
            active_desk="",
            visible_tasks=[],
            focus_summary="",
            errors=errors,
            warnings=warnings,
            capabilities=_capabilities_for(detection),
        )

    critical_apps = critical_app_status(detection.adb_device_id)
    dump_output = desktopmode_dump(detection.adb_device_id)
    desktop_state = parse_desktopmode_state(dump_output)
    desktop_mode_active = bool(desktop_state["active"])
    active_desk = str(desktop_state["active_desk"])
    visible_tasks = [str(item) for item in desktop_state["visible_tasks"]]
    focus_summary = current_focus(detection.adb_device_id)

    if not critical_apps.get("com.termux.api", False):
        warnings.append("Termux:API não foi detectado como pacote instalado.")
    if detection.scenario == "SCENARIO_2_ANDROID_WIFI":
        warnings.append("Cenário Android+Wi-Fi exige execução com proteção de sessão ativa.")
    if not desktop_mode_active:
        warnings.append("Desktop mode não está ativo no momento do preflight.")

    return PreflightResult(
        detection=detection,
        critical_apps=critical_apps,
        desktop_mode_active=desktop_mode_active,
        active_desk=active_desk,
        visible_tasks=visible_tasks,
        focus_summary=focus_summary,
        errors=errors,
        warnings=warnings,
        capabilities=_capabilities_for(detection),
    )


def _capabilities_for(detection: DetectionResult) -> dict[str, bool]:
    return {
        "can_use_adb": detection.adb_available and detection.adb_state == "device",
        "can_run_mutations": detection.scenario == "SCENARIO_1_LINUX_USB",
        "must_protect_host_session": detection.scenario == "SCENARIO_2_ANDROID_WIFI",
        "requires_manual_wifi_enable": detection.scenario == "SCENARIO_2_ANDROID_WIFI",
    }
