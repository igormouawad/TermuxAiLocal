from __future__ import annotations

from pathlib import Path


def workspace_root() -> Path:
    return Path(__file__).resolve().parents[1]


def audit_runs_root() -> Path:
    return workspace_root() / "Audit" / "runs"


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path
