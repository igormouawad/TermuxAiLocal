from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

from core.models import DetectionResult, PrechangeAuditResult, PreflightResult
from core.paths import audit_runs_root, ensure_dir, workspace_root
from scenarios import resolve_policy


PUBLIC_ENTRYPOINTS = (
    "workspace_host_menu.sh",
    "ADB/adb_consolidate_desktop_mode.sh",
    "ADB/adb_open_desktop_app.sh",
    "ADB/adb_run_workspace_regression.sh",
    "ADB/adb_desktop_mode.sh",
    "ADB/adb_wifi_debug.sh",
    "Install/adb_provision.sh",
    "Install/adb_reinstall_termux_official.sh",
    "Debian/adb_provision_debian_trixie_gui.sh",
    "Debian/adb_install_debian_trixie_gui.sh",
)


def build_prechange_audit(
    *,
    detection: DetectionResult,
    preflight: PreflightResult,
    operation: str,
    action_class: str,
) -> PrechangeAuditResult:
    policy = resolve_policy(detection.scenario)
    decision = policy.evaluate(action_class)
    inventory = inventory_workspace()
    reusable_assets = [
        "lib/termux_common.sh",
        "lib/android_desktop_layout.sh",
        "Audit/audit_runner.py",
        "workspace_host_menu.sh",
        "ADB/adb_desktop_mode.sh",
    ]
    consolidate_or_rewrite = [
        "formalizar detecção de cenário fora dos wrappers shell",
        "centralizar preflight e prechange audit em camada estruturada",
        "usar adapters/scenarios/orchestration como contrato novo",
        "reduzir acoplamento direto do menu às regras distribuídas em shell",
    ]
    migration_plan = [
        "Adicionar arquitetura nova paralela sem remover entrypoints principais.",
        "Delegar wrappers públicos para a camada nova de contexto/auditoria.",
        "Validar em cenário real e só então aposentar redundâncias secundárias.",
    ]

    report_dir = ensure_dir(
        audit_runs_root() / f"prechange-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{Path(operation).name}"
    )

    return PrechangeAuditResult(
        operation=operation,
        action_class=action_class,
        decision=decision.decision,
        risk_level=decision.risk_level,
        detection=detection,
        preflight=preflight,
        inventory=inventory,
        migration_plan=migration_plan,
        reusable_assets=reusable_assets,
        consolidate_or_rewrite=consolidate_or_rewrite,
        blocking_reasons=decision.blocking_reasons,
        next_step=decision.next_step,
        report_dir=str(report_dir),
        report_json=str(report_dir / "prechange_audit.json"),
        report_md=str(report_dir / "prechange_audit.md"),
    )


def inventory_workspace() -> dict[str, Any]:
    root = workspace_root()
    shell_scripts = sorted(str(path.relative_to(root)) for path in root.rglob("*.sh"))
    python_scripts = sorted(str(path.relative_to(root)) for path in root.rglob("*.py"))
    docs = sorted(str(path.relative_to(root)) for path in root.rglob("*.md"))

    return {
        "workspace_root": str(root),
        "shell_script_count": len(shell_scripts),
        "python_script_count": len(python_scripts),
        "doc_count": len(docs),
        "public_entrypoints": [path for path in PUBLIC_ENTRYPOINTS if (root / path).exists()],
        "legacy_risk_clusters": [
            "detecção de contexto ainda concentrada em helpers shell",
            "regras de safety do cenário Android ainda dependem de diretivas/documentação",
            "preflight e mutação ainda aparecem misturados em wrappers públicos",
        ],
    }
