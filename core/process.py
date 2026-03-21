from __future__ import annotations

import subprocess
from typing import Iterable


def run_command(
    args: Iterable[str],
    *,
    timeout: int | None = None,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=check,
    )
