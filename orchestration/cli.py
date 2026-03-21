#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[1]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from core import exit_codes
from context.detect import detect_scenario
from context.prechange_audit import build_prechange_audit
from context.preflight import run_preflight


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Enterprise orchestration helpers for TermuxAiLocal")
    subparsers = parser.add_subparsers(dest="command", required=True)

    detect_parser = subparsers.add_parser("detect-scenario", help="Detecta o cenário operacional atual")
    detect_parser.add_argument("--format", choices=("json", "text", "shell"), default="json")

    preflight_parser = subparsers.add_parser("preflight", help="Executa o preflight detalhado")
    preflight_parser.add_argument("--format", choices=("json", "text"), default="json")

    audit_parser = subparsers.add_parser("prechange-audit", help="Gera auditoria pré-mudança e aplica policy gating")
    audit_parser.add_argument("--operation", required=True)
    audit_parser.add_argument("--action-class", required=True)
    audit_parser.add_argument("--format", choices=("json", "text", "shell"), default="text")

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.command == "detect-scenario":
        detection = detect_scenario()
        return emit_detection(detection, args.format)

    detection = detect_scenario()
    preflight = run_preflight(detection)

    if args.command == "preflight":
        return emit_preflight(preflight, args.format)

    audit_result = build_prechange_audit(
        detection=detection,
        preflight=preflight,
        operation=args.operation,
        action_class=args.action_class,
    )
    write_audit_reports(audit_result)
    return emit_prechange_audit(audit_result, args.format)


def emit_detection(detection, output_format: str) -> int:
    payload = detection.to_dict()
    if output_format == "json":
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    elif output_format == "shell":
        print(f"SCENARIO={payload['scenario']}")
        print(f"OPERATOR_CONTEXT={payload['operator_context']}")
        print(f"ADB_TRANSPORT={payload['adb_transport']}")
        print(f"ADB_DEVICE_ID={payload['adb_device_id']}")
    else:
        print(f"scenario={payload['scenario']}")
        print(f"host_kind={payload['host_kind']}")
        print(f"terminal_kind={payload['terminal_kind']}")
        print(f"operator_context={payload['operator_context']}")
        print(f"adb_transport={payload['adb_transport']}")
        print(f"adb_device_id={payload['adb_device_id']}")
        print(f"session_risk={payload['session_risk']}")
    return exit_codes.OK


def emit_preflight(preflight, output_format: str) -> int:
    payload = preflight.to_dict()
    if output_format == "json":
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print(f"scenario={payload['detection']['scenario']}")
        print(f"desktop_mode_active={payload['desktop_mode_active']}")
        print(f"active_desk={payload['active_desk']}")
        print(f"visible_tasks={','.join(payload['visible_tasks']) or 'none'}")
        print(f"errors={len(payload['errors'])}")
        print(f"warnings={len(payload['warnings'])}")
    return exit_codes.OK if not payload["errors"] else exit_codes.PRECONDITION_FAILED


def write_audit_reports(audit_result) -> None:
    json_path = Path(audit_result.report_json)
    md_path = Path(audit_result.report_md)
    json_path.write_text(json.dumps(audit_result.to_dict(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    md_path.write_text(render_markdown(audit_result), encoding="utf-8")


def emit_prechange_audit(audit_result, output_format: str) -> int:
    payload = audit_result.to_dict()
    exit_code = exit_codes.OK if audit_result.decision == "ALLOW" else exit_codes.ACTION_BLOCKED

    if output_format == "json":
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    elif output_format == "shell":
        print(f"DECISION={audit_result.decision}")
        print(f"RISK_LEVEL={audit_result.risk_level}")
        print(f"SCENARIO={audit_result.detection.scenario}")
        print(f"OPERATOR_CONTEXT={audit_result.detection.operator_context}")
        print(f"REPORT_DIR={audit_result.report_dir}")
        print(f"REPORT_JSON={audit_result.report_json}")
        print(f"REPORT_MD={audit_result.report_md}")
        print(f"NEXT_STEP={audit_result.next_step}")
    else:
        print(render_markdown(audit_result))

    return exit_code


def render_markdown(audit_result) -> str:
    detection = audit_result.detection
    preflight = audit_result.preflight
    lines = [
        "# Prechange Audit",
        "",
        f"- operation: `{audit_result.operation}`",
        f"- action_class: `{audit_result.action_class}`",
        f"- decision: `{audit_result.decision}`",
        f"- risk_level: `{audit_result.risk_level}`",
        f"- scenario: `{detection.scenario}`",
        f"- operator_context: `{detection.operator_context}`",
        f"- adb_transport: `{detection.adb_transport}`",
        f"- adb_device_id: `{detection.adb_device_id or 'none'}`",
        "",
        "## Evidence",
    ]
    lines.extend(f"- {item}" for item in detection.evidence)
    lines.extend(
        [
            "",
            "## Preflight",
            f"- desktop_mode_active: `{preflight.desktop_mode_active}`",
            f"- active_desk: `{preflight.active_desk or 'none'}`",
            f"- visible_tasks: `{', '.join(preflight.visible_tasks) if preflight.visible_tasks else 'none'}`",
            f"- focus_summary: `{preflight.focus_summary or 'none'}`",
            "",
            "## Inventory",
            f"- shell_script_count: `{audit_result.inventory['shell_script_count']}`",
            f"- python_script_count: `{audit_result.inventory['python_script_count']}`",
            f"- doc_count: `{audit_result.inventory['doc_count']}`",
            "",
            "## Reusable Assets",
        ]
    )
    lines.extend(f"- `{item}`" for item in audit_result.reusable_assets)
    lines.extend(["", "## Consolidate Or Rewrite"])
    lines.extend(f"- {item}" for item in audit_result.consolidate_or_rewrite)
    lines.extend(["", "## Migration Plan"])
    lines.extend(f"- {item}" for item in audit_result.migration_plan)
    if audit_result.blocking_reasons:
        lines.extend(["", "## Blocking Reasons"])
        lines.extend(f"- {item}" for item in audit_result.blocking_reasons)
    lines.extend(["", "## Next Step", f"- {audit_result.next_step}"])
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    raise SystemExit(main())
