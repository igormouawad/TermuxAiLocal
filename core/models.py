from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class DetectionResult:
    scenario: str
    host_kind: str
    terminal_kind: str
    operator_context: str
    adb_available: bool
    adb_state: str
    adb_transport: str
    adb_device_id: str
    known_android_ip: str
    ssh_remote_ip: str
    session_risk: str
    confidence: str
    unsafe_reasons: list[str] = field(default_factory=list)
    evidence: list[str] = field(default_factory=list)
    adb_devices: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class PreflightResult:
    detection: DetectionResult
    critical_apps: dict[str, bool]
    desktop_mode_active: bool | None
    active_desk: str
    visible_tasks: list[str]
    focus_summary: str
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    capabilities: dict[str, bool] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["detection"] = self.detection.to_dict()
        return payload


@dataclass
class PrechangeAuditResult:
    operation: str
    action_class: str
    decision: str
    risk_level: str
    detection: DetectionResult
    preflight: PreflightResult
    inventory: dict[str, Any]
    migration_plan: list[str]
    reusable_assets: list[str]
    consolidate_or_rewrite: list[str]
    blocking_reasons: list[str] = field(default_factory=list)
    next_step: str = ""
    report_dir: str = ""
    report_json: str = ""
    report_md: str = ""

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["detection"] = self.detection.to_dict()
        payload["preflight"] = self.preflight.to_dict()
        return payload
