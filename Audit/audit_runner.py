#!/usr/bin/env python3
from __future__ import annotations

import argparse
import codecs
import json
import os
import pty
import selectors
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

APP_NAME = "TermuxAiLocal Audit Runner"
APP_VERSION = "2026.03"
DEFAULT_REFRESH_HZ = 3.0
DEFAULT_POLL_MS = 120
DEFAULT_TAIL_LINES = 18
DEFAULT_EVENT_LINES = 16
DEFAULT_LOG_DIR = "./Audit/runs"
DEFAULT_KILL_GRACE_SECONDS = 3.0
DEFAULT_REPORT_WIDTH = 140
DEFAULT_FINAL_DELAY_SECONDS = 3.0
COMPACT_LAYOUT_WIDTH = 150
COMPACT_LAYOUT_HEIGHT = 34
BRIDGE_META_MARKER_BEGIN = "__CODEX_TERMUX_META_BEGIN__"
BRIDGE_META_MARKER_END = "__CODEX_TERMUX_META_END__"


def iso_now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def parse_iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is not None:
        return parsed.astimezone().replace(tzinfo=None)
    return parsed


def slugify(value: str) -> str:
    result = []
    for char in value:
        if char.isalnum() or char in "._-":
            result.append(char)
        else:
            result.append("_")
    slug = "".join(result).strip("._-")
    return slug or "step"


def escape_pipe(text: str) -> str:
    return text.replace("|", "\\|")


def normalize_exit_code(value: int | None) -> int:
    if value is None:
        return 1
    if value < 0:
        return 128 + abs(value)
    return value


def split_terminal_text(text: str) -> list[str]:
    return [item for item in text.replace("\r", "\n").split("\n") if item != ""]


def split_stream_buffer(text: str) -> tuple[list[str], str]:
    items = text.replace("\r", "\n").split("\n")
    if text.endswith("\n") or text.endswith("\r"):
        return [item for item in items if item != ""], ""
    return [item for item in items[:-1] if item != ""], items[-1]


def short_message(text: str, limit: int = 320) -> str:
    stripped = " ".join(text.split())
    if len(stripped) <= limit:
        return stripped
    return stripped[: limit - 3] + "..."


def is_bridge_meta_payload(text: str) -> bool:
    return BRIDGE_META_MARKER_BEGIN in text and BRIDGE_META_MARKER_END in text


def is_bridge_internal_command(text: str) -> bool:
    lowered = text.lower()
    return "codex-bridge/termux-bridge-" in lowered and (
        "stdout_file=" in lowered
        or "stderr_file=" in lowered
        or "status_file=" in lowered
        or "done_file=" in lowered
        or "pid_file=" in lowered
        or BRIDGE_META_MARKER_BEGIN.lower() in lowered
    )


def terminal_size(console: Any | None) -> tuple[int, int]:
    if console is not None:
        try:
            size = console.size
            width = max(0, int(size.width))
            height = max(0, int(size.height))
            if width and height:
                return width, height
        except Exception:
            pass
    fallback = shutil.get_terminal_size((DEFAULT_REPORT_WIDTH, 40))
    return max(0, fallback.columns), max(0, fallback.lines)


def should_use_compact_layout(console: Any | None) -> bool:
    layout_override = os.environ.get("TERMUXAI_AUDIT_LAYOUT", "").strip().lower()
    if layout_override == "compact":
        return True
    if layout_override == "wide":
        return False
    width, height = terminal_size(console)
    return width <= COMPACT_LAYOUT_WIDTH or height <= COMPACT_LAYOUT_HEIGHT


def build_key_value_group(
    rich: RichBundle,
    items: list[tuple[str, str]],
    *,
    value_limit: int = 320,
) -> Any:
    rows: list[Any] = []
    for label, value in items:
        row = rich.Text(f"{label}: ", style="bold cyan")
        row.append(short_message(value or "-", limit=value_limit), style="white")
        rows.append(row)
    return rich.Group(*rows) if rows else rich.Text("-")


class RichUnavailable(RuntimeError):
    pass


@dataclass
class RichBundle:
    box: Any
    Console: Any
    Group: Any
    Layout: Any
    Live: Any
    Panel: Any
    ProgressBar: Any
    Table: Any
    Text: Any


def require_rich() -> RichBundle:
    try:
        from rich import box
        from rich.console import Console, Group
        from rich.layout import Layout
        from rich.live import Live
        from rich.panel import Panel
        from rich.progress_bar import ProgressBar
        from rich.table import Table
        from rich.text import Text
    except ModuleNotFoundError as exc:  # pragma: no cover - depends on environment
        raise RichUnavailable(
            "rich não está disponível. Instale com `python -m pip install rich` no ambiente que vai renderizar a UI."
        ) from exc

    return RichBundle(
        box=box,
        Console=Console,
        Group=Group,
        Layout=Layout,
        Live=Live,
        Panel=Panel,
        ProgressBar=ProgressBar,
        Table=Table,
        Text=Text,
    )


@dataclass
class Step:
    name: str
    command: list[str] | str
    description: str = ""
    cwd: str | None = None
    shell: bool = False
    timeout: int | None = None
    continue_on_error: bool = False
    env: dict[str, str] = field(default_factory=dict)
    severity: str = "error"
    pty: bool = False
    line_buffered: bool = False
    force_color: bool = False
    expected_returncodes: list[int] = field(default_factory=lambda: [0])
    tags: list[str] = field(default_factory=list)


@dataclass
class ExecStepState:
    status: str = "pending"
    return_code: int | None = None
    started_at: float | None = None
    finished_at: float | None = None
    duration_s: float = 0.0
    stdout_lines: int = 0
    stderr_lines: int = 0
    combined_lines: int = 0
    output_path: str = ""
    pid: int | None = None
    last_output_at: float | None = None
    mode: str = "pipe"
    timeout_triggered: bool = False
    warning_count: int = 0
    error_count: int = 0


@dataclass
class SessionStepState:
    seq: int
    name: str
    description: str = ""
    context: str = ""
    status: str = "pending"
    severity: str = "info"
    rc: int | None = None
    started_at: str | None = None
    finished_at: str | None = None
    duration_s: float = 0.0
    current: int | None = None
    total: int | None = None
    percent: int | None = None
    command: str = ""
    tags: list[str] = field(default_factory=list)
    log_path: str = ""
    last_message: str = ""
    warning_count: int = 0
    error_count: int = 0


class ExecRunner:
    def __init__(
        self,
        steps: list[Step],
        *,
        logs_dir: str = DEFAULT_LOG_DIR,
        refresh_hz: float = DEFAULT_REFRESH_HZ,
        poll_ms: int = DEFAULT_POLL_MS,
        tail_lines: int = DEFAULT_TAIL_LINES,
        event_lines: int = DEFAULT_EVENT_LINES,
        no_screen: bool = False,
        ascii_only: bool = False,
        save_reports: bool = True,
        session_label: str | None = None,
    ) -> None:
        self.steps = steps
        self.states = [ExecStepState() for _ in steps]
        self.current_index: int | None = None
        self.process: subprocess.Popen[bytes] | None = None
        self.abort_requested = False
        self.hard_kill_deadline: float | None = None
        self.refresh_hz = max(1.0, refresh_hz)
        self.poll_s = max(0.04, poll_ms / 1000.0)
        self.tail_lines = max(4, tail_lines)
        self.event_lines = max(4, event_lines)
        self.no_screen = no_screen
        self.save_reports = save_reports
        self.started_at = time.time()
        self.finished_at: float | None = None
        self.logs_dir = Path(logs_dir)
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        self.run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.run_dir = self.logs_dir / f"run-{self.run_id}"
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.events_path = self.run_dir / "events.jsonl"
        self.summary_json_path = self.run_dir / "summary.json"
        self.manifest_json_path = self.run_dir / "manifest.json"
        self.summary_md_path = self.run_dir / "summary.md"
        self.report_html_path = self.run_dir / "report.html"
        self.report_svg_path = self.run_dir / "report.svg"
        self.report_txt_path = self.run_dir / "report.txt"
        self.events_fp = self.events_path.open("a", encoding="utf-8")
        self.step_output_fps: dict[int, Any] = {}
        self.recent_output: deque[tuple[str, int, str]] = deque(maxlen=self.tail_lines)
        self.recent_events: deque[dict[str, Any]] = deque(maxlen=self.event_lines)
        self.last_live_refresh = 0.0
        self.session_label = session_label or "Runner local"
        self.rich: RichBundle | None = None
        self.console: Any | None = None
        self.screen_symbols = {
            "pending": ("[ ]" if ascii_only else "○", "grey58"),
            "running": ("[>]" if ascii_only else "▶", "cyan"),
            "success": ("[OK]" if ascii_only else "✔", "green"),
            "failed": ("[X]" if ascii_only else "✖", "red"),
            "skipped": ("[~]" if ascii_only else "⤼", "yellow"),
        }

    def close(self) -> None:
        for fp in self.step_output_fps.values():
            try:
                fp.close()
            except Exception:
                pass
        try:
            self.events_fp.close()
        except Exception:
            pass

    def total_duration(self) -> float:
        return (self.finished_at or time.time()) - self.started_at

    def counts(self) -> dict[str, int]:
        counts = {"pending": 0, "running": 0, "success": 0, "failed": 0, "skipped": 0}
        for state in self.states:
            counts[state.status] = counts.get(state.status, 0) + 1
        return counts

    def overall_progress(self) -> float:
        done = sum(1 for state in self.states if state.status in {"success", "failed", "skipped"})
        return done / max(1, len(self.states))

    def severity_counts(self) -> dict[str, int]:
        counts = {"info": 0, "warn": 0, "error": 0, "critical": 0}
        for step, state in zip(self.steps, self.states):
            if state.status == "failed":
                counts[step.severity] = counts.get(step.severity, 0) + 1
        return counts

    def overall_health(self) -> tuple[str, str]:
        sev = self.severity_counts()
        if sev.get("critical", 0) > 0 or sev.get("error", 0) > 0:
            return ("FAIL", "red")
        if sev.get("warn", 0) > 0:
            return ("WARN", "yellow")
        if self.counts()["failed"] > 0:
            return ("FAIL", "red")
        return ("PASS", "green")

    def ensure_rich(self) -> None:
        if self.rich is None:
            self.rich = require_rich()
            self.console = self.rich.Console(color_system="auto")

    def style_for_status(self, status: str) -> tuple[str, str]:
        return self.screen_symbols.get(status, ("?", "white"))

    def use_compact_layout(self) -> bool:
        return should_use_compact_layout(self.console)

    def normalize_command(self, step: Step) -> list[str] | str:
        command: list[str] | str = step.command
        if step.shell:
            if isinstance(command, list):
                command = shlex.join(command)
            return command
        if isinstance(command, str):
            command = shlex.split(command)
        if step.line_buffered and shutil.which("stdbuf"):
            command = ["stdbuf", "-oL", "-eL", *command]
        return command

    def command_display(self, step: Step) -> str:
        command = self.normalize_command(step)
        if isinstance(command, str):
            return command
        return shlex.join(command)

    def open_step_log(self, index: int) -> None:
        path = self.run_dir / f"step-{index + 1:02d}.log"
        self.states[index].output_path = str(path)
        self.step_output_fps[index] = path.open("a", encoding="utf-8")

    def write_step_output(self, index: int, stream: str, line: str) -> None:
        fp = self.step_output_fps[index]
        fp.write(f"[{iso_now()}] [{stream}] {line}\n")
        fp.flush()

    def emit_event(
        self,
        *,
        event_type: str,
        level: str,
        message: str,
        step_index: int | None = None,
        extra: dict[str, Any] | None = None,
    ) -> None:
        payload: dict[str, Any] = {
            "ts": iso_now(),
            "type": event_type,
            "level": level,
            "message": message,
        }
        if step_index is not None:
            payload["step_index"] = step_index
            payload["seq"] = step_index + 1
        if extra:
            payload.update(extra)
        self.events_fp.write(json.dumps(payload, ensure_ascii=False) + "\n")
        self.events_fp.flush()
        self.recent_events.append(payload)

    def emit_output(self, *, index: int, stream: str, line: str) -> None:
        clean_line = line.rstrip("\r\n")
        self.write_step_output(index, stream, clean_line)
        self.recent_output.append((stream, index, clean_line))
        state = self.states[index]
        state.last_output_at = time.time()
        if stream == "stdout":
            state.stdout_lines += 1
        elif stream == "stderr":
            state.stderr_lines += 1
        else:
            state.combined_lines += 1
        lowered = clean_line.lower()
        if "warning" in lowered or "warn" in lowered:
            state.warning_count += 1
        if "error" in lowered or "failed" in lowered or "fatal" in lowered:
            state.error_count += 1

    def build_env(self, step: Step) -> dict[str, str]:
        env = os.environ.copy()
        env.update({str(k): str(v) for k, v in step.env.items()})
        if step.force_color:
            env.setdefault("TERM", os.environ.get("TERM", "xterm-256color"))
            env.setdefault("CLICOLOR_FORCE", "1")
            env.setdefault("FORCE_COLOR", "3")
            env.setdefault("PY_COLORS", "1")
        return env

    def spawn_pipe(self, step: Step) -> subprocess.Popen[bytes]:
        command = self.normalize_command(step)
        return subprocess.Popen(
            command,
            shell=step.shell,
            cwd=step.cwd,
            env=self.build_env(step),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            start_new_session=(os.name == "posix"),
        )

    def spawn_pty(self, step: Step) -> tuple[subprocess.Popen[bytes], int]:
        master_fd, slave_fd = pty.openpty()
        command = self.normalize_command(step)
        process = subprocess.Popen(
            command,
            shell=step.shell,
            cwd=step.cwd,
            env=self.build_env(step),
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            bufsize=0,
            start_new_session=(os.name == "posix"),
            close_fds=True,
        )
        os.close(slave_fd)
        return process, master_fd

    def terminate_running_process(self, sig: int) -> None:
        if not self.process or self.process.poll() is not None:
            return
        try:
            if os.name == "posix":
                os.killpg(self.process.pid, sig)
            elif sig == signal.SIGTERM:
                self.process.terminate()
            else:
                self.process.kill()
        except Exception:
            pass

    def request_abort(self, *_: object) -> None:
        self.abort_requested = True
        self.emit_event(event_type="note", level="warn", message="Interrupção solicitada pelo usuário.", step_index=self.current_index)
        if self.process and self.process.poll() is None:
            self.terminate_running_process(signal.SIGTERM)
            self.hard_kill_deadline = time.time() + DEFAULT_KILL_GRACE_SECONDS

    def handle_runtime_conditions(self, index: int) -> None:
        step = self.steps[index]
        state = self.states[index]
        now = time.time()

        if step.timeout and state.started_at and not state.timeout_triggered and (now - state.started_at) > step.timeout:
            state.timeout_triggered = True
            self.emit_event(
                event_type="timeout",
                level="error",
                message=f"Timeout excedido ({step.timeout}s). Enviando SIGTERM.",
                step_index=index,
            )
            self.terminate_running_process(signal.SIGTERM)
            self.hard_kill_deadline = now + DEFAULT_KILL_GRACE_SECONDS

        if self.abort_requested and self.process and self.process.poll() is None and self.hard_kill_deadline is None:
            self.hard_kill_deadline = now + DEFAULT_KILL_GRACE_SECONDS

        if self.hard_kill_deadline and self.process and self.process.poll() is None and now >= self.hard_kill_deadline:
            self.emit_event(
                event_type="kill",
                level="error",
                message="Processo não encerrou a tempo; enviando SIGKILL.",
                step_index=index,
            )
            self.terminate_running_process(signal.SIGKILL)
            self.hard_kill_deadline = None

    def drain_pipe_streams(self, proc: subprocess.Popen[bytes], index: int) -> None:
        assert proc.stdout is not None
        assert proc.stderr is not None
        selector = selectors.DefaultSelector()
        selector.register(proc.stdout, selectors.EVENT_READ, data="stdout")
        selector.register(proc.stderr, selectors.EVENT_READ, data="stderr")
        decoders = {
            "stdout": codecs.getincrementaldecoder("utf-8")(errors="replace"),
            "stderr": codecs.getincrementaldecoder("utf-8")(errors="replace"),
        }
        partial = {"stdout": "", "stderr": ""}

        while selector.get_map():
            events = selector.select(timeout=self.poll_s)
            if not events:
                self.handle_runtime_conditions(index)
                if proc.poll() is not None:
                    for key in list(selector.get_map().values()):
                        stream = key.data
                        remainder = partial[stream] + decoders[stream].decode(b"", final=True)
                        if remainder:
                            for line in split_terminal_text(remainder):
                                self.emit_output(index=index, stream=stream, line=line)
                        selector.unregister(key.fileobj)
                        try:
                            key.fileobj.close()
                        except Exception:
                            pass
                    break
                continue

            for key, _ in events:
                stream = key.data
                try:
                    chunk = os.read(key.fileobj.fileno(), 65536)
                except OSError:
                    chunk = b""
                if not chunk:
                    remainder = partial[stream] + decoders[stream].decode(b"", final=True)
                    if remainder:
                        for line in split_terminal_text(remainder):
                            self.emit_output(index=index, stream=stream, line=line)
                    selector.unregister(key.fileobj)
                    try:
                        key.fileobj.close()
                    except Exception:
                        pass
                    continue
                text = decoders[stream].decode(chunk)
                combined = partial[stream] + text
                lines, partial[stream] = split_stream_buffer(combined)
                for line in lines:
                    self.emit_output(index=index, stream=stream, line=line)
            self.handle_runtime_conditions(index)

    def drain_pty_stream(self, proc: subprocess.Popen[bytes], index: int, master_fd: int) -> None:
        selector = selectors.DefaultSelector()
        selector.register(master_fd, selectors.EVENT_READ)
        decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        partial = ""
        try:
            while selector.get_map():
                events = selector.select(timeout=self.poll_s)
                if not events:
                    self.handle_runtime_conditions(index)
                    if proc.poll() is not None:
                        remainder = partial + decoder.decode(b"", final=True)
                        if remainder:
                            for line in split_terminal_text(remainder):
                                self.emit_output(index=index, stream="pty", line=line)
                        break
                    continue

                for key, _ in events:
                    try:
                        chunk = os.read(key.fd, 65536)
                    except OSError:
                        chunk = b""
                    if not chunk:
                        remainder = partial + decoder.decode(b"", final=True)
                        if remainder:
                            for line in split_terminal_text(remainder):
                                self.emit_output(index=index, stream="pty", line=line)
                        selector.unregister(key.fd)
                        break
                    text = decoder.decode(chunk)
                    combined = partial + text
                    lines, partial = split_stream_buffer(combined)
                    for line in lines:
                        self.emit_output(index=index, stream="pty", line=line)
                self.handle_runtime_conditions(index)
        finally:
            try:
                selector.close()
            except Exception:
                pass
            try:
                os.close(master_fd)
            except Exception:
                pass

    def mark_skipped_from(self, start_index: int) -> None:
        for idx in range(start_index, len(self.steps)):
            state = self.states[idx]
            if state.status == "pending":
                state.status = "skipped"
                self.emit_event(
                    event_type="step_finish",
                    level="warn",
                    message=f"Etapa pulada: {self.steps[idx].name}",
                    step_index=idx,
                    extra={"status": "skipped", "return_code": None},
                )

    def matches_expected_rc(self, step: Step, return_code: int | None) -> bool:
        return return_code in set(step.expected_returncodes)

    def refresh_if_needed(self, live: Any, *, force: bool = False) -> None:
        now = time.time()
        if force or (now - self.last_live_refresh) >= (1.0 / self.refresh_hz):
            live.update(self.render(), refresh=True)
            self.last_live_refresh = now

    def run_headless(self) -> int:
        exit_code = 0
        self.emit_event(
            event_type="session_start",
            level="info",
            message=f"Sessão iniciada: {self.session_label}",
            extra={"mode": "exec", "run_dir": str(self.run_dir), "step_count": len(self.steps)},
        )
        for index, step in enumerate(self.steps):
            if self.abort_requested:
                self.mark_skipped_from(index)
                exit_code = max(exit_code, 130)
                break

            self.current_index = index
            state = self.states[index]
            state.status = "running"
            state.started_at = time.time()
            state.mode = "pty" if step.pty else "pipe"
            self.open_step_log(index)

            command_display = self.command_display(step)
            self.emit_event(
                event_type="step_start",
                level="info",
                message=f"Iniciando etapa {index + 1}/{len(self.steps)}: {step.name}",
                step_index=index,
                extra={
                    "name": step.name,
                    "description": step.description,
                    "severity": step.severity,
                    "tags": step.tags,
                    "command": command_display,
                    "current": index + 1,
                    "total": len(self.steps),
                },
            )
            self.emit_event(event_type="command", level="info", message=command_display, step_index=index, extra={"command": command_display})
            print(f"[AUDIT] ({index + 1}/{len(self.steps)}) {step.name}")
            print(f"[AUDIT:CMD] {command_display}")
            try:
                if step.pty:
                    self.process, master_fd = self.spawn_pty(step)
                else:
                    self.process = self.spawn_pipe(step)
                    master_fd = -1
            except Exception as exc:
                state.status = "failed"
                state.return_code = 999
                state.finished_at = time.time()
                state.duration_s = state.finished_at - (state.started_at or state.finished_at)
                self.emit_event(
                    event_type="step_finish",
                    level="error",
                    message=f"Falha ao iniciar processo: {exc}",
                    step_index=index,
                    extra={"status": "failed", "return_code": 999, "duration_s": round(state.duration_s, 3)},
                )
                print(f"[AUDIT:FAIL] {step.name} rc=999")
                exit_code = max(exit_code, 1)
                if not step.continue_on_error:
                    self.mark_skipped_from(index + 1)
                    break
                continue

            state.pid = self.process.pid
            self.hard_kill_deadline = None
            if step.pty:
                self.drain_pty_stream(self.process, index, master_fd)
            else:
                self.drain_pipe_streams(self.process, index)
            self.process.wait()

            state.return_code = self.process.returncode
            state.finished_at = time.time()
            state.duration_s = state.finished_at - (state.started_at or state.finished_at)
            self.process = None
            self.hard_kill_deadline = None

            if self.abort_requested and state.return_code not in (0, None):
                state.status = "failed"
            elif self.matches_expected_rc(step, state.return_code):
                state.status = "success"
            else:
                state.status = "failed"

            level = "info" if state.status == "success" else ("warn" if step.severity == "warn" else "error")
            self.emit_event(
                event_type="step_finish",
                level=level,
                message=f"Etapa concluída: {step.name} | status={state.status} | rc={state.return_code}",
                step_index=index,
                extra={"status": state.status, "return_code": state.return_code, "duration_s": round(state.duration_s, 3)},
            )
            print(f"[AUDIT:{'OK' if state.status == 'success' else 'FAIL'}] {step.name} rc={state.return_code} dur={state.duration_s:.2f}s")
            if state.status == "failed":
                exit_code = max(exit_code, normalize_exit_code(state.return_code))
                if not step.continue_on_error:
                    self.mark_skipped_from(index + 1)
                    break

        self.finished_at = time.time()
        self.emit_event(
            event_type="session_finish",
            level="info" if exit_code == 0 else "error",
            message=f"Sessão finalizada com exit_code={exit_code}",
            extra={"exit_code": exit_code, "health": self.overall_health()[0]},
        )
        self.write_summary(exit_code)
        if self.save_reports:
            self.write_reports()
        return exit_code

    def run_live(self) -> int:
        self.ensure_rich()
        assert self.rich is not None
        signal.signal(signal.SIGINT, self.request_abort)
        signal.signal(signal.SIGTERM, self.request_abort)
        self.write_manifest()
        exit_code = 0
        self.emit_event(
            event_type="session_start",
            level="info",
            message=f"Sessão iniciada: {self.session_label}",
            extra={"mode": "exec", "run_dir": str(self.run_dir), "step_count": len(self.steps)},
        )

        with self.rich.Live(
            self.render(),
            console=self.console,
            refresh_per_second=self.refresh_hz,
            screen=not self.no_screen,
            transient=False,
            auto_refresh=False,
        ) as live:
            for index, step in enumerate(self.steps):
                if self.abort_requested:
                    self.mark_skipped_from(index)
                    exit_code = max(exit_code, 130)
                    break

                state = self.states[index]
                self.current_index = index
                state.status = "running"
                state.started_at = time.time()
                state.mode = "pty" if step.pty else "pipe"
                self.open_step_log(index)

                command_display = self.command_display(step)
                self.emit_event(
                    event_type="step_start",
                    level="info",
                    message=f"Iniciando etapa {index + 1}/{len(self.steps)}: {step.name}",
                    step_index=index,
                    extra={
                        "name": step.name,
                        "description": step.description,
                        "severity": step.severity,
                        "tags": step.tags,
                        "command": command_display,
                        "current": index + 1,
                        "total": len(self.steps),
                    },
                )
                self.emit_event(event_type="command", level="info", message=command_display, step_index=index, extra={"command": command_display})
                self.refresh_if_needed(live, force=True)

                try:
                    if step.pty:
                        self.process, master_fd = self.spawn_pty(step)
                    else:
                        self.process = self.spawn_pipe(step)
                        master_fd = -1
                except Exception as exc:
                    state.status = "failed"
                    state.return_code = 999
                    state.finished_at = time.time()
                    state.duration_s = state.finished_at - (state.started_at or state.finished_at)
                    self.emit_event(
                        event_type="step_finish",
                        level="error",
                        message=f"Falha ao iniciar processo: {exc}",
                        step_index=index,
                        extra={"status": "failed", "return_code": 999, "duration_s": round(state.duration_s, 3)},
                    )
                    exit_code = max(exit_code, 1)
                    self.refresh_if_needed(live, force=True)
                    if not step.continue_on_error:
                        self.mark_skipped_from(index + 1)
                        break
                    continue

                state.pid = self.process.pid
                self.hard_kill_deadline = None
                if step.pty:
                    self.drain_pty_stream(self.process, index, master_fd)
                else:
                    self.drain_pipe_streams(self.process, index)
                self.process.wait()

                state.return_code = self.process.returncode
                state.finished_at = time.time()
                state.duration_s = state.finished_at - (state.started_at or state.finished_at)
                self.process = None
                self.hard_kill_deadline = None

                if self.abort_requested and state.return_code not in (0, None):
                    state.status = "failed"
                elif self.matches_expected_rc(step, state.return_code):
                    state.status = "success"
                else:
                    state.status = "failed"

                level = "info" if state.status == "success" else ("warn" if step.severity == "warn" else "error")
                self.emit_event(
                    event_type="step_finish",
                    level=level,
                    message=f"Etapa concluída: {step.name} | status={state.status} | rc={state.return_code} | duração={state.duration_s:.2f}s",
                    step_index=index,
                    extra={"status": state.status, "return_code": state.return_code, "duration_s": round(state.duration_s, 3)},
                )
                self.refresh_if_needed(live, force=True)

                if state.status == "failed":
                    exit_code = max(exit_code, normalize_exit_code(state.return_code))
                    if not step.continue_on_error:
                        self.mark_skipped_from(index + 1)
                        break

            self.finished_at = time.time()
            self.emit_event(
                event_type="session_finish",
                level="info" if exit_code == 0 else "error",
                message=f"Sessão finalizada com exit_code={exit_code}",
                extra={"exit_code": exit_code, "health": self.overall_health()[0]},
            )
            self.write_summary(exit_code)
            if self.save_reports:
                self.write_reports()
            self.refresh_if_needed(live, force=True)
        return exit_code

    def run(self) -> int:
        signal.signal(signal.SIGINT, self.request_abort)
        signal.signal(signal.SIGTERM, self.request_abort)
        self.write_manifest()
        wants_rich = (not self.no_screen) or self.save_reports
        rich_ready = False
        if wants_rich:
            try:
                self.ensure_rich()
                rich_ready = True
            except RichUnavailable:
                if not self.no_screen:
                    raise
                self.save_reports = False

        if rich_ready:
            return self.run_live()
        return self.run_headless()

    def render_header(self) -> Any:
        assert self.rich is not None
        counts = self.counts()
        progress = self.overall_progress()
        progress_pct = int(progress * 100)
        health, health_color = self.overall_health()
        current_name = "aguardando"
        if self.current_index is not None and self.current_index < len(self.steps):
            current_name = self.steps[self.current_index].name
        compact = self.use_compact_layout()

        header = self.rich.Table.grid(expand=True)
        if compact:
            header.add_column(ratio=1)
            header.add_row(self.rich.Text(f"{APP_NAME} {APP_VERSION}", style="bold white on blue"))
            header.add_row(self.rich.Text(f"Run: {self.run_id}", style="bold cyan"))
            header.add_row(self.rich.Text(f"Atual: {current_name}", style="bold magenta"))
            header.add_row(
                self.rich.Text(
                    f"Health {health} | Duração {self.total_duration():.1f}s | Host {socket.gethostname()}",
                    style=f"bold {health_color}" if health != "PASS" else "white",
                )
            )
            header.add_row(
                self.rich.Text(
                    f"OK {counts['success']}  FAIL {counts['failed']}  RUN {counts['running']}  SKIP {counts['skipped']}  PEND {counts['pending']}",
                    style="white",
                )
            )
            header.add_row(self.rich.Text(f"Refresh {self.refresh_hz:.1f}Hz / Poll {self.poll_s * 1000:.0f}ms", style="white"))
        else:
            header.add_column(ratio=4)
            header.add_column(ratio=2)
            header.add_column(ratio=2)
            header.add_row(
                self.rich.Text(f"{APP_NAME} {APP_VERSION}", style="bold white on blue"),
                self.rich.Text(f"Run ID: {self.run_id}", style="bold cyan"),
                self.rich.Text(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), style="bold white"),
            )
            header.add_row(
                self.rich.Text(f"Atual: {current_name}", style="bold magenta"),
                self.rich.Text(f"Health: {health}", style=f"bold {health_color}"),
                self.rich.Text(f"Duração: {self.total_duration():.1f}s", style="white"),
            )
            header.add_row(
                self.rich.Text(
                    f"OK {counts['success']}  FAIL {counts['failed']}  RUN {counts['running']}  SKIP {counts['skipped']}  PEND {counts['pending']}",
                    style="white",
                ),
                self.rich.Text(f"Host: {socket.gethostname()}", style="cyan"),
                self.rich.Text(f"Refresh {self.refresh_hz:.1f}Hz / Poll {self.poll_s * 1000:.0f}ms", style="white"),
            )
        group = self.rich.Group(
            header,
            self.rich.ProgressBar(total=100, completed=progress_pct, width=None),
            self.rich.Text(f"{progress_pct}% concluído", style="bold green"),
        )
        return self.rich.Panel(group, border_style="blue", box=self.rich.box.ROUNDED)

    def render_pipeline(self) -> Any:
        assert self.rich is not None
        if self.use_compact_layout():
            rows: list[Any] = []
            for idx, (step, state) in enumerate(zip(self.steps, self.states), start=1):
                icon, color = self.style_for_status(state.status)
                heading = self.rich.Text(f"{idx:02d} {icon} ", style=f"bold {color}")
                heading.append(step.name, style="bold white" if idx - 1 == self.current_index and state.status == "running" else "white")
                if step.severity:
                    heading.append(f" [{step.severity}]", style="yellow" if step.severity == "warn" else "red" if step.severity in {"error", "critical"} else "cyan")
                output_count = state.stdout_lines + state.stderr_lines + state.combined_lines
                meta = self.rich.Text(
                    f"status={state.status}  rc={'-' if state.return_code is None else state.return_code}  tempo={'-' if not state.duration_s else f'{state.duration_s:.1f}s'}  out={output_count}",
                    style="white",
                )
                rows.append(heading)
                rows.append(meta)
            if not rows:
                rows.append(self.rich.Text("Aguardando etapas.", style="white"))
            return self.rich.Panel(self.rich.Group(*rows), title="Pipeline", border_style="cyan", box=self.rich.box.ROUNDED)

        table = self.rich.Table(expand=True, box=self.rich.box.SIMPLE_HEAVY)
        table.add_column("#", justify="right", width=3)
        table.add_column("Status", width=12)
        table.add_column("Sev", width=8)
        table.add_column("Etapa", ratio=3)
        table.add_column("RC", justify="right", width=6)
        table.add_column("Tempo", justify="right", width=10)
        table.add_column("Out", justify="right", width=12)

        for idx, (step, state) in enumerate(zip(self.steps, self.states), start=1):
            icon, color = self.style_for_status(state.status)
            name = step.name
            if idx - 1 == self.current_index and state.status == "running":
                name = f"[bold]{name}[/bold]"
            output_count = state.stdout_lines + state.stderr_lines + state.combined_lines
            sev_style = {"info": "cyan", "warn": "yellow", "error": "bright_red", "critical": "red"}.get(step.severity, "white")
            table.add_row(
                str(idx),
                f"[{color}]{icon} {state.status}[/{color}]",
                f"[{sev_style}]{step.severity}[/{sev_style}]",
                name,
                "-" if state.return_code is None else str(state.return_code),
                f"{state.duration_s:.1f}s" if state.duration_s else "-",
                str(output_count),
            )
        return self.rich.Panel(table, title="Pipeline", border_style="cyan", box=self.rich.box.ROUNDED)

    def render_current(self) -> Any:
        assert self.rich is not None
        if self.current_index is None:
            return self.rich.Panel("Aguardando execução.", title="Etapa atual", border_style="magenta", box=self.rich.box.ROUNDED)

        step = self.steps[self.current_index]
        state = self.states[self.current_index]
        if self.use_compact_layout():
            details = [
                ("Nome", step.name),
                ("Descrição", step.description or "-"),
                ("Comando", self.command_display(step)),
                ("Diretório", step.cwd or os.getcwd()),
                ("Modo", "PTY" if step.pty else "PIPE"),
                ("Shell", "sim" if step.shell else "não"),
                ("PID", "-" if state.pid is None else str(state.pid)),
                ("Timeout", "-" if step.timeout is None else f"{step.timeout}s"),
                ("RC esperado", ", ".join(str(value) for value in step.expected_returncodes)),
                ("Falha", "continuar" if step.continue_on_error else "parar"),
                ("Tags", ", ".join(step.tags) if step.tags else "-"),
            ]
            return self.rich.Panel(
                build_key_value_group(self.rich, details, value_limit=220),
                title="Etapa atual",
                border_style="magenta",
                box=self.rich.box.ROUNDED,
            )

        grid = self.rich.Table.grid(expand=True)
        grid.add_column(style="bold cyan", width=14)
        grid.add_column(style="white")
        grid.add_row("Nome", step.name)
        grid.add_row("Descrição", step.description or "-")
        grid.add_row("Comando", self.command_display(step))
        grid.add_row("Diretório", step.cwd or os.getcwd())
        grid.add_row("Modo", "PTY" if step.pty else "PIPE")
        grid.add_row("Shell", "sim" if step.shell else "não")
        grid.add_row("PID", "-" if state.pid is None else str(state.pid))
        grid.add_row("Timeout", "-" if step.timeout is None else f"{step.timeout}s")
        grid.add_row("RC esperado", ", ".join(str(value) for value in step.expected_returncodes))
        grid.add_row("Falha", "continuar" if step.continue_on_error else "parar")
        grid.add_row("Tags", ", ".join(step.tags) if step.tags else "-")
        return self.rich.Panel(grid, title="Etapa atual", border_style="magenta", box=self.rich.box.ROUNDED)

    def render_output(self) -> Any:
        assert self.rich is not None
        if not self.recent_output:
            return self.rich.Panel("Sem saída recente.", title="Saída recente", border_style="green", box=self.rich.box.ROUNDED)
        rows: list[Any] = []
        for stream, index, line in self.recent_output:
            stream_style = {"stdout": "bright_green", "stderr": "bright_red", "pty": "bright_cyan"}.get(stream, "white")
            prefix = self.rich.Text(f"[{index + 1:02d}:{stream}] ", style=f"bold {stream_style}")
            prefix.append_text(self.rich.Text.from_ansi(line[:600]))
            rows.append(prefix)
        return self.rich.Panel(self.rich.Group(*rows), title="Saída recente", border_style="green", box=self.rich.box.ROUNDED)

    def render_events(self) -> Any:
        assert self.rich is not None
        if not self.recent_events:
            return self.rich.Panel("Sem eventos.", title="Eventos", border_style="yellow", box=self.rich.box.ROUNDED)
        rows: list[Any] = []
        color_by_level = {"info": "cyan", "warn": "yellow", "error": "red"}
        for event in self.recent_events:
            color = color_by_level.get(str(event.get("level", "")), "white")
            label = f"{event.get('ts', '')} {str(event.get('level', '')).upper():<5}"
            seq = event.get("seq")
            if seq is not None:
                label += f" S{int(seq):02d}"
            row = self.rich.Text(label + " ", style=f"bold {color}")
            row.append(str(event.get("message", ""))[:240], style="white")
            rows.append(row)
        return self.rich.Panel(self.rich.Group(*rows), title="Eventos", border_style="yellow", box=self.rich.box.ROUNDED)

    def render_footer(self) -> Any:
        assert self.rich is not None
        if self.use_compact_layout():
            lines = self.rich.Group(
                self.rich.Text(f"Arquivos: {self.run_dir}", style="white"),
                self.rich.Text("Ctrl+C encerra com auditoria salva", style="bold magenta"),
                self.rich.Text(
                    "report.html/report.svg/report.txt gerados no fim" if self.save_reports else "reports desativados",
                    style="bold green" if self.save_reports else "white",
                ),
            )
            return self.rich.Panel(lines, border_style="blue", box=self.rich.box.ROUNDED)
        text = self.rich.Text()
        text.append("Arquivos: ", style="bold cyan")
        text.append(str(self.run_dir), style="white")
        text.append(" | Ctrl+C encerra com auditoria salva", style="bold magenta")
        if self.save_reports:
            text.append(" | report.html/report.svg/report.txt gerados no fim", style="bold green")
        return self.rich.Panel(text, border_style="blue", box=self.rich.box.ROUNDED)

    def render(self) -> Any:
        assert self.rich is not None
        layout = self.rich.Layout()
        compact = self.use_compact_layout()
        layout.split_column(
            self.rich.Layout(name="header", size=9 if compact else 7),
            self.rich.Layout(name="main", ratio=1),
            self.rich.Layout(name="footer", size=5 if compact else 3),
        )
        if compact:
            layout["main"].split_column(
                self.rich.Layout(name="current", ratio=2),
                self.rich.Layout(name="pipeline", ratio=3),
                self.rich.Layout(name="output", ratio=2),
                self.rich.Layout(name="events", ratio=2),
            )
        else:
            layout["main"].split_row(self.rich.Layout(name="left", ratio=3), self.rich.Layout(name="right", ratio=2))
            layout["left"].split_column(self.rich.Layout(name="pipeline", ratio=2), self.rich.Layout(name="output", ratio=2))
            layout["right"].split_column(self.rich.Layout(name="current", ratio=2), self.rich.Layout(name="events", ratio=2))
        layout["header"].update(self.render_header())
        layout["pipeline"].update(self.render_pipeline())
        layout["output"].update(self.render_output())
        layout["current"].update(self.render_current())
        layout["events"].update(self.render_events())
        layout["footer"].update(self.render_footer())
        return layout

    def build_final_summary_renderable(self) -> Any:
        assert self.rich is not None
        files = self.rich.Table.grid(expand=False)
        files.add_column(style="bold cyan")
        files.add_column(style="white")
        files.add_row("Run dir", str(self.run_dir))
        files.add_row("Events", str(self.events_path))
        files.add_row("Summary", str(self.summary_json_path))
        files.add_row("Manifest", str(self.manifest_json_path))
        files.add_row("Markdown", str(self.summary_md_path))
        files.add_row("HTML", str(self.report_html_path))
        files.add_row("SVG", str(self.report_svg_path))
        files.add_row("Text", str(self.report_txt_path))
        return self.rich.Group(
            self.render_header(),
            self.render_pipeline(),
            self.render_events(),
            self.rich.Panel(files, title="Artefatos", border_style="green", box=self.rich.box.ROUNDED),
        )

    def write_reports(self) -> None:
        report_text = self.build_summary_markdown(self.summary_payload())
        self.report_txt_path.write_text(report_text, encoding="utf-8")
        try:
            self.ensure_rich()
        except RichUnavailable:
            return
        assert self.rich is not None
        report_console = self.rich.Console(record=True, width=DEFAULT_REPORT_WIDTH)
        report_console.print(self.build_final_summary_renderable())
        report_console.save_text(str(self.report_txt_path), clear=False)
        report_console.save_html(str(self.report_html_path), clear=False, inline_styles=True)
        report_console.save_svg(str(self.report_svg_path), clear=False, title=f"{APP_NAME} {self.run_id}")

    def write_manifest(self) -> None:
        manifest = {
            "app": APP_NAME,
            "version": APP_VERSION,
            "mode": "exec",
            "run_id": self.run_id,
            "session_label": self.session_label,
            "started_at": iso_now(),
            "cwd": os.getcwd(),
            "host": socket.gethostname(),
            "python": sys.version,
            "step_count": len(self.steps),
            "steps": [
                {
                    "index": idx + 1,
                    "name": step.name,
                    "command": step.command,
                    "description": step.description,
                    "cwd": step.cwd,
                    "shell": step.shell,
                    "timeout": step.timeout,
                    "continue_on_error": step.continue_on_error,
                    "severity": step.severity,
                    "pty": step.pty,
                    "line_buffered": step.line_buffered,
                    "force_color": step.force_color,
                    "expected_returncodes": step.expected_returncodes,
                    "tags": step.tags,
                    "env_keys": sorted(step.env.keys()),
                }
                for idx, step in enumerate(self.steps)
            ],
        }
        self.manifest_json_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    def summary_payload(self, exit_code: int | None = None) -> dict[str, Any]:
        health, _ = self.overall_health()
        return {
            "app": APP_NAME,
            "version": APP_VERSION,
            "mode": "exec",
            "run_id": self.run_id,
            "exit_code": exit_code if exit_code is not None else 0,
            "health": health,
            "started_at": datetime.fromtimestamp(self.started_at).isoformat(timespec="seconds"),
            "finished_at": datetime.fromtimestamp(self.finished_at or time.time()).isoformat(timespec="seconds"),
            "duration_s": round(self.total_duration(), 3),
            "counts": self.counts(),
            "severity_counts": self.severity_counts(),
            "run_dir": str(self.run_dir),
            "files": {
                "events_jsonl": str(self.events_path),
                "summary_json": str(self.summary_json_path),
                "manifest_json": str(self.manifest_json_path),
                "summary_md": str(self.summary_md_path),
                "report_html": str(self.report_html_path),
                "report_svg": str(self.report_svg_path),
                "report_txt": str(self.report_txt_path),
            },
            "steps": [
                {
                    "index": idx + 1,
                    "name": step.name,
                    "severity": step.severity,
                    "tags": step.tags,
                    "status": state.status,
                    "return_code": state.return_code,
                    "duration_s": round(state.duration_s, 3),
                    "stdout_lines": state.stdout_lines,
                    "stderr_lines": state.stderr_lines,
                    "combined_lines": state.combined_lines,
                    "warning_count": state.warning_count,
                    "error_count": state.error_count,
                    "output_path": state.output_path,
                }
                for idx, (step, state) in enumerate(zip(self.steps, self.states))
            ],
        }

    def write_summary(self, exit_code: int) -> None:
        summary = self.summary_payload(exit_code)
        self.summary_json_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        self.summary_md_path.write_text(self.build_summary_markdown(summary), encoding="utf-8")

    def build_summary_markdown(self, summary: dict[str, Any]) -> str:
        lines = [
            f"# {APP_NAME}",
            "",
            f"- Run ID: `{summary['run_id']}`",
            f"- Mode: `{summary.get('mode', 'exec')}`",
            f"- Health: **{summary['health']}**",
            f"- Exit code: `{summary['exit_code']}`",
            f"- Duration: `{summary['duration_s']}` s",
            f"- Run dir: `{summary['run_dir']}`",
            "",
            "## Steps",
            "",
            "| # | Status | Severity | Name | RC | Duration | Output |",
            "|---:|---|---|---|---:|---:|---:|",
        ]
        for step in summary["steps"]:
            output_total = step.get("stdout_lines", 0) + step.get("stderr_lines", 0) + step.get("combined_lines", 0)
            lines.append(
                f"| {step['index']} | {step['status']} | {step['severity']} | {escape_pipe(step['name'])} | {step['return_code']} | {step['duration_s']} | {output_total} |"
            )
        lines.extend(
            [
                "",
                "## Files",
                "",
                f"- events.jsonl: `{summary['files']['events_jsonl']}`",
                f"- summary.json: `{summary['files']['summary_json']}`",
                f"- manifest.json: `{summary['files']['manifest_json']}`",
                f"- summary.md: `{summary['files']['summary_md']}`",
                f"- report.txt: `{summary['files']['report_txt']}`",
                f"- report.html: `{summary['files']['report_html']}`",
                f"- report.svg: `{summary['files']['report_svg']}`",
            ]
        )
        return "\n".join(lines) + "\n"


def parse_expected_returncodes(value: Any) -> list[int]:
    if not isinstance(value, list):
        raise ValueError("expected_returncodes must be a list of integers.")
    return [int(item) for item in value]


def load_steps(config_path: str | None) -> list[Step]:
    if config_path is None:
        return default_steps()

    data = json.loads(Path(config_path).read_text(encoding="utf-8"))
    defaults: dict[str, Any] = {}
    raw_steps: Any
    if isinstance(data, list):
        raw_steps = data
    elif isinstance(data, dict) and isinstance(data.get("steps"), list):
        raw_steps = data["steps"]
        defaults = dict(data.get("defaults", {}))
    else:
        raise ValueError("Config JSON must be a list or an object containing a 'steps' list.")

    steps: list[Step] = []
    for raw in raw_steps:
        if not isinstance(raw, dict):
            raise ValueError("Each step must be a JSON object.")
        merged = {**defaults, **raw}
        steps.append(
            Step(
                name=str(merged["name"]),
                command=merged["command"],
                description=str(merged.get("description", "")),
                cwd=merged.get("cwd"),
                shell=bool(merged.get("shell", False)),
                timeout=int(merged["timeout"]) if merged.get("timeout") is not None else None,
                continue_on_error=bool(merged.get("continue_on_error", False)),
                env={str(k): str(v) for k, v in dict(merged.get("env", {})).items()},
                severity=str(merged.get("severity", "error")),
                pty=bool(merged.get("pty", False)),
                line_buffered=bool(merged.get("line_buffered", False)),
                force_color=bool(merged.get("force_color", False)),
                expected_returncodes=parse_expected_returncodes(merged.get("expected_returncodes", [0])),
                tags=[str(item) for item in list(merged.get("tags", []))],
            )
        )
    return steps


def default_steps() -> list[Step]:
    return [
        Step(
            name="Contexto do host",
            description="Hostname, kernel, usuário e release do sistema.",
            command=["bash", "-lc", "hostnamectl || true; echo; uname -a; echo; id; echo; cat /etc/os-release 2>/dev/null | sed -n '1,8p'"],
            severity="info",
            continue_on_error=True,
            tags=["host", "identity"],
            line_buffered=True,
        ),
        Step(
            name="Storage e memória",
            description="Visão rápida de blocos, mountpoints, uso de disco e memória.",
            command=["bash", "-lc", "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS; echo; df -hT /; echo; free -h"],
            severity="warn",
            continue_on_error=True,
            tags=["storage", "memory"],
            line_buffered=True,
        ),
        Step(
            name="Rede",
            description="Interfaces, endereços e rota padrão.",
            command=["bash", "-lc", "ip -brief a; echo; ip route | sed -n '1,20p'"],
            severity="warn",
            continue_on_error=True,
            tags=["network"],
            line_buffered=True,
        ),
    ]


class SessionModel:
    def __init__(self, session_dir: Path, *, event_lines: int = DEFAULT_EVENT_LINES, tail_lines: int = DEFAULT_TAIL_LINES) -> None:
        self.session_dir = session_dir
        self.manifest_path = session_dir / "manifest.json"
        self.events_path = session_dir / "events.jsonl"
        self.summary_json_path = session_dir / "summary.json"
        self.summary_md_path = session_dir / "summary.md"
        self.report_txt_path = session_dir / "report.txt"
        self.manifest: dict[str, Any] = {}
        self.steps: dict[int, SessionStepState] = {}
        self.recent_events: deque[dict[str, Any]] = deque(maxlen=event_lines)
        self.recent_activity: deque[str] = deque(maxlen=tail_lines)
        self.current_seq: int | None = None
        self.session_started_at: str | None = None
        self.session_finished_at: str | None = None
        self.exit_code: int | None = None
        self.health: str = "PASS"
        self.last_events_size = 0
        self.loaded = False

    def counts(self) -> dict[str, int]:
        counts = {"pending": 0, "running": 0, "success": 0, "failed": 0, "skipped": 0}
        for step in self.steps.values():
            counts[step.status] = counts.get(step.status, 0) + 1
        return counts

    def total_steps(self) -> int:
        manifest_steps = self.manifest.get("step_count")
        if isinstance(manifest_steps, int) and manifest_steps > 0:
            return manifest_steps
        return max(len(self.steps), 0)

    def overall_progress(self) -> float:
        total = max(self.total_steps(), 1)
        done = sum(1 for step in self.steps.values() if step.status in {"success", "failed", "skipped"})
        return done / total

    def current_label(self) -> str:
        if self.current_seq is None:
            return "aguardando"
        step = self.steps.get(self.current_seq)
        if step is None:
            return "aguardando"
        return step.name

    def sorted_steps(self) -> list[SessionStepState]:
        return [self.steps[key] for key in sorted(self.steps.keys())]

    def load_manifest(self) -> None:
        if self.manifest_path.is_file():
            self.manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
            if not self.loaded:
                self.session_started_at = self.manifest.get("started_at")
            self.loaded = True

    def update(self) -> None:
        self.load_manifest()
        if not self.events_path.exists():
            return
        size = self.events_path.stat().st_size
        if size < self.last_events_size:
            self.last_events_size = 0
            self.steps.clear()
            self.recent_events.clear()
            self.recent_activity.clear()
            self.current_seq = None
            self.session_finished_at = None
            self.exit_code = None
            self.health = "PASS"
        with self.events_path.open("r", encoding="utf-8") as handle:
            handle.seek(self.last_events_size)
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                self.process_event(event)
            self.last_events_size = handle.tell()

    def ensure_step(self, seq: int, name: str) -> SessionStepState:
        if seq not in self.steps:
            self.steps[seq] = SessionStepState(seq=seq, name=name)
        elif name and self.steps[seq].name == f"Etapa {seq}":
            self.steps[seq].name = name
        return self.steps[seq]

    def process_event(self, event: dict[str, Any]) -> None:
        event_type = str(event.get("type", "note"))
        seq_raw = event.get("seq")
        seq = int(seq_raw) if isinstance(seq_raw, int) or (isinstance(seq_raw, str) and seq_raw.isdigit()) else None
        message = str(event.get("message", ""))

        if event_type == "command" and is_bridge_internal_command(message):
            return
        if event_type == "command_result" and is_bridge_meta_payload(message):
            return

        self.recent_events.append(event)

        if event_type == "session_start":
            self.session_started_at = str(event.get("ts", self.session_started_at or ""))
        elif event_type == "session_finish":
            self.session_finished_at = str(event.get("ts", ""))
            exit_code = event.get("exit_code")
            self.exit_code = int(exit_code) if isinstance(exit_code, int) else self.exit_code
            health = event.get("health")
            if isinstance(health, str) and health:
                self.health = health
        elif event_type == "step_start":
            if seq is None:
                return
            name = str(event.get("name") or event.get("label") or message or f"Etapa {seq}")
            step = self.ensure_step(seq, name)
            step.description = str(event.get("description", step.description))
            step.context = str(event.get("context", step.context))
            step.status = "running"
            step.started_at = str(event.get("ts", step.started_at or ""))
            step.severity = str(event.get("severity", step.severity or "info"))
            step.current = int(event["current"]) if isinstance(event.get("current"), int) else step.current
            step.total = int(event["total"]) if isinstance(event.get("total"), int) else step.total
            step.percent = int(event["percent"]) if isinstance(event.get("percent"), int) else step.percent
            if isinstance(event.get("tags"), list):
                step.tags = [str(item) for item in event.get("tags", [])]
            if isinstance(event.get("log_path"), str):
                step.log_path = str(event["log_path"])
            if isinstance(event.get("command"), str):
                step.command = str(event["command"])
            step.last_message = message
            self.current_seq = seq
            self.recent_activity.append(f"S{seq:02d} {step.name}")
        elif event_type == "step_finish":
            if seq is None:
                return
            step = self.ensure_step(seq, str(event.get("name") or f"Etapa {seq}"))
            status = str(event.get("status") or "success")
            step.status = status
            step.finished_at = str(event.get("ts", ""))
            if isinstance(event.get("return_code"), int):
                step.rc = int(event["return_code"])
            if isinstance(event.get("duration_s"), (int, float)):
                step.duration_s = float(event["duration_s"])
            step.last_message = message
            if status == "failed":
                self.health = "FAIL"
            elif status == "skipped" and self.health == "PASS":
                self.health = "WARN"
            if self.current_seq == seq and status != "running":
                self.current_seq = None
            self.recent_activity.append(f"S{seq:02d} {step.name} -> {status}")
        elif event_type == "command":
            if seq is not None:
                step = self.ensure_step(seq, f"Etapa {seq}")
                step.command = str(event.get("command") or message)
                step.last_message = message
            self.recent_activity.append(short_message(message))
        elif event_type in {"command_result", "note", "failure", "timeout", "kill", "log"}:
            if seq is not None:
                step = self.ensure_step(seq, f"Etapa {seq}")
                step.last_message = message
                if event_type == "failure":
                    step.status = "failed"
                    self.health = "FAIL"
                if event_type == "note" and "warn" in str(event.get("level", "")).lower():
                    step.warning_count += 1
                if event_type in {"failure", "timeout", "kill"}:
                    step.error_count += 1
            self.recent_activity.append(short_message(message))
        else:
            self.recent_activity.append(short_message(message))

    def summary_payload(self) -> dict[str, Any]:
        counts = self.counts()
        if self.exit_code is None:
            if counts["failed"] > 0:
                self.exit_code = 1
            elif self.session_finished_at:
                self.exit_code = 0
        if counts["failed"] > 0 and self.health == "PASS":
            self.health = "FAIL"
        return {
            "app": APP_NAME,
            "version": APP_VERSION,
            "mode": str(self.manifest.get("mode", "watch")),
            "run_id": str(self.manifest.get("run_id", self.manifest.get("session_id", self.session_dir.name))),
            "label": str(self.manifest.get("session_label", self.manifest.get("label", self.session_dir.name))),
            "exit_code": self.exit_code if self.exit_code is not None else 0,
            "health": self.health,
            "started_at": self.session_started_at or "",
            "finished_at": self.session_finished_at or "",
            "duration_s": round(self.duration_seconds(), 3),
            "counts": counts,
            "run_dir": str(self.session_dir),
            "files": {
                "events_jsonl": str(self.events_path),
                "summary_json": str(self.summary_json_path),
                "summary_md": str(self.summary_md_path),
                "report_txt": str(self.report_txt_path),
                "manifest_json": str(self.manifest_path),
            },
            "steps": [
                {
                    "index": step.seq,
                    "name": step.name,
                    "description": step.description,
                    "context": step.context,
                    "status": step.status,
                    "severity": step.severity,
                    "return_code": step.rc,
                    "duration_s": round(step.duration_s, 3),
                    "command": step.command,
                    "tags": step.tags,
                    "log_path": step.log_path,
                    "last_message": step.last_message,
                }
                for step in self.sorted_steps()
            ],
        }

    def duration_seconds(self) -> float:
        if not self.session_started_at:
            return 0.0
        start_dt = parse_iso_datetime(self.session_started_at)
        end_dt = parse_iso_datetime(self.session_finished_at) if self.session_finished_at else datetime.now()
        if start_dt is None or end_dt is None:
            return 0.0
        return max(0.0, (end_dt - start_dt).total_seconds())


class SessionWatcher:
    def __init__(
        self,
        session_dir: Path,
        *,
        refresh_hz: float = DEFAULT_REFRESH_HZ,
        event_lines: int = DEFAULT_EVENT_LINES,
        tail_lines: int = DEFAULT_TAIL_LINES,
        ascii_only: bool = False,
        final_delay_seconds: float = DEFAULT_FINAL_DELAY_SECONDS,
    ) -> None:
        self.session_dir = session_dir
        self.refresh_hz = max(1.0, refresh_hz)
        self.model = SessionModel(session_dir, event_lines=event_lines, tail_lines=tail_lines)
        self.final_delay_seconds = max(0.0, final_delay_seconds)
        self.finish_seen_at: float | None = None
        self.rich = require_rich()
        self.console = self.rich.Console(color_system="standard" if ascii_only else "auto")
        self.screen_symbols = {
            "pending": ("[ ]" if ascii_only else "○", "grey58"),
            "running": ("[>]" if ascii_only else "▶", "cyan"),
            "success": ("[OK]" if ascii_only else "✔", "green"),
            "failed": ("[X]" if ascii_only else "✖", "red"),
            "skipped": ("[~]" if ascii_only else "⤼", "yellow"),
        }

    def style_for_status(self, status: str) -> tuple[str, str]:
        return self.screen_symbols.get(status, ("?", "white"))

    def use_compact_layout(self) -> bool:
        layout_override = os.environ.get("TERMUXAI_AUDIT_LAYOUT", "").strip().lower()
        if layout_override == "wide":
            return False
        if layout_override in {"compact", "", "auto"}:
            return True
        return should_use_compact_layout(self.console)

    def render_header(self) -> Any:
        counts = self.model.counts()
        progress_pct = int(self.model.overall_progress() * 100)
        label = str(self.model.manifest.get("label", self.model.manifest.get("session_label", self.session_dir.name)))
        current_name = self.model.current_label()
        compact = self.use_compact_layout()

        header = self.rich.Table.grid(expand=True)
        health_style = f"bold {'green' if self.model.health == 'PASS' else 'yellow' if self.model.health == 'WARN' else 'red'}"
        if compact:
            header.add_column(ratio=1)
            header.add_row(self.rich.Text(f"{APP_NAME} {APP_VERSION}", style="bold white on blue"))
            header.add_row(self.rich.Text(f"Sessão: {label}", style="bold cyan"))
            header.add_row(self.rich.Text(f"Atual: {current_name}", style="bold magenta"))
            header.add_row(
                self.rich.Text(
                    f"Health {self.model.health} | Duração {self.model.duration_seconds():.1f}s | Host {self.model.manifest.get('host', '-')}",
                    style=health_style,
                )
            )
            header.add_row(
                self.rich.Text(
                    f"OK {counts['success']}  FAIL {counts['failed']}  RUN {counts['running']}  SKIP {counts['skipped']}  PEND {counts['pending']}",
                    style="white",
                )
            )
            header.add_row(self.rich.Text(f"Refresh {self.refresh_hz:.1f}Hz", style="white"))
        else:
            header.add_column(ratio=4)
            header.add_column(ratio=2)
            header.add_column(ratio=2)
            header.add_row(
                self.rich.Text(f"{APP_NAME} {APP_VERSION}", style="bold white on blue"),
                self.rich.Text(f"Sessão: {label}", style="bold cyan"),
                self.rich.Text(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), style="bold white"),
            )
            header.add_row(
                self.rich.Text(f"Atual: {current_name}", style="bold magenta"),
                self.rich.Text(f"Health: {self.model.health}", style=health_style),
                self.rich.Text(f"Duração: {self.model.duration_seconds():.1f}s", style="white"),
            )
            header.add_row(
                self.rich.Text(
                    f"OK {counts['success']}  FAIL {counts['failed']}  RUN {counts['running']}  SKIP {counts['skipped']}  PEND {counts['pending']}",
                    style="white",
                ),
                self.rich.Text(f"Host: {self.model.manifest.get('host', '-')}", style="cyan"),
                self.rich.Text(f"Refresh {self.refresh_hz:.1f}Hz", style="white"),
            )
        group = self.rich.Group(
            header,
            self.rich.ProgressBar(total=100, completed=progress_pct, width=None),
            self.rich.Text(f"{progress_pct}% concluído", style="bold green"),
        )
        return self.rich.Panel(group, border_style="blue", box=self.rich.box.ROUNDED)

    def render_pipeline(self) -> Any:
        if self.use_compact_layout():
            rows: list[Any] = []
            for step in self.model.sorted_steps():
                icon, color = self.style_for_status(step.status)
                heading = self.rich.Text(f"{step.seq:02d} {icon} ", style=f"bold {color}")
                heading.append(step.name or "-", style="bold white" if step.status == "running" else "white")
                if step.context:
                    heading.append(f" [{step.context}]", style="cyan")
                meta = self.rich.Text(
                    f"status={step.status}  rc={'-' if step.rc is None else step.rc}  tempo={'-' if step.duration_s == 0 else f'{step.duration_s:.1f}s'}",
                    style="white",
                )
                rows.append(heading)
                rows.append(meta)
            if not rows:
                rows.append(self.rich.Text("Aguardando eventos...", style="white"))
            return self.rich.Panel(self.rich.Group(*rows), title="Pipeline", border_style="cyan", box=self.rich.box.ROUNDED)

        table = self.rich.Table(expand=True, box=self.rich.box.SIMPLE_HEAVY)
        table.add_column("#", justify="right", width=4)
        table.add_column("Status", width=12)
        table.add_column("Ctx", width=8)
        table.add_column("Etapa", ratio=3)
        table.add_column("RC", justify="right", width=6)
        table.add_column("Tempo", justify="right", width=10)
        for step in self.model.sorted_steps():
            icon, color = self.style_for_status(step.status)
            table.add_row(
                str(step.seq),
                f"[{color}]{icon} {step.status}[/{color}]",
                step.context or "-",
                step.name,
                "-" if step.rc is None else str(step.rc),
                "-" if step.duration_s == 0 else f"{step.duration_s:.1f}s",
            )
        if not self.model.sorted_steps():
            table.add_row("-", "-", "-", "Aguardando eventos...", "-", "-")
        return self.rich.Panel(table, title="Pipeline", border_style="cyan", box=self.rich.box.ROUNDED)

    def render_current(self) -> Any:
        seq = self.model.current_seq
        if seq is None:
            return self.rich.Panel("Aguardando etapas.", title="Etapa atual", border_style="magenta", box=self.rich.box.ROUNDED)
        step = self.model.steps.get(seq)
        if step is None:
            return self.rich.Panel("Aguardando etapas.", title="Etapa atual", border_style="magenta", box=self.rich.box.ROUNDED)
        if self.use_compact_layout():
            details = [
                ("Nome", step.name),
                ("Contexto", step.context or "-"),
                ("Descrição", step.description or "-"),
                ("Comando", step.command or "-"),
                ("Mensagem", step.last_message or "-"),
                (
                    "Progresso",
                    "-" if step.current is None or step.total is None else f"{step.current}/{step.total} ({step.percent or 0}%)",
                ),
            ]
            return self.rich.Panel(
                build_key_value_group(self.rich, details, value_limit=220),
                title="Etapa atual",
                border_style="magenta",
                box=self.rich.box.ROUNDED,
            )
        grid = self.rich.Table.grid(expand=True)
        grid.add_column(style="bold cyan", width=14)
        grid.add_column(style="white")
        grid.add_row("Nome", step.name)
        grid.add_row("Contexto", step.context or "-")
        grid.add_row("Descrição", step.description or "-")
        grid.add_row("Comando", step.command or "-")
        grid.add_row("Mensagem", step.last_message or "-")
        grid.add_row("Progresso", "-" if step.current is None or step.total is None else f"{step.current}/{step.total} ({step.percent or 0}%)")
        return self.rich.Panel(grid, title="Etapa atual", border_style="magenta", box=self.rich.box.ROUNDED)

    def render_activity(self) -> Any:
        if not self.model.recent_activity:
            return self.rich.Panel("Sem atividade recente.", title="Atividade recente", border_style="green", box=self.rich.box.ROUNDED)
        rows = [self.rich.Text(item[:320], style="white") for item in self.model.recent_activity]
        return self.rich.Panel(self.rich.Group(*rows), title="Atividade recente", border_style="green", box=self.rich.box.ROUNDED)

    def render_events(self) -> Any:
        if not self.model.recent_events:
            return self.rich.Panel("Sem eventos.", title="Eventos", border_style="yellow", box=self.rich.box.ROUNDED)
        rows: list[Any] = []
        color_by_level = {"info": "cyan", "warn": "yellow", "error": "red"}
        for event in self.model.recent_events:
            color = color_by_level.get(str(event.get("level", "")), "white")
            label = f"{event.get('ts', '')} {str(event.get('level', '')).upper():<5}"
            seq = event.get("seq")
            if seq is not None:
                label += f" S{int(seq):02d}"
            row = self.rich.Text(label + " ", style=f"bold {color}")
            row.append(str(event.get("message", ""))[:240], style="white")
            rows.append(row)
        return self.rich.Panel(self.rich.Group(*rows), title="Eventos", border_style="yellow", box=self.rich.box.ROUNDED)

    def render_footer(self) -> Any:
        if self.use_compact_layout():
            lines = self.rich.Group(
                self.rich.Text(f"Sessão espelhada: {self.session_dir}", style="white"),
                self.rich.Text(
                    "sessão finalizada" if self.model.session_finished_at else "aguardando conclusão",
                    style="bold green" if self.model.session_finished_at else "bold magenta",
                ),
            )
            return self.rich.Panel(lines, border_style="blue", box=self.rich.box.ROUNDED)
        text = self.rich.Text()
        text.append("Sessão espelhada: ", style="bold cyan")
        text.append(str(self.session_dir), style="white")
        if self.model.session_finished_at:
            text.append(" | sessão finalizada", style="bold green")
        else:
            text.append(" | aguardando conclusão", style="bold magenta")
        return self.rich.Panel(text, border_style="blue", box=self.rich.box.ROUNDED)

    def render(self) -> Any:
        layout = self.rich.Layout()
        compact = self.use_compact_layout()
        layout.split_column(
            self.rich.Layout(name="header", size=9 if compact else 7),
            self.rich.Layout(name="main", ratio=1),
            self.rich.Layout(name="footer", size=4 if compact else 3),
        )
        if compact:
            layout["main"].split_column(
                self.rich.Layout(name="current", ratio=2),
                self.rich.Layout(name="pipeline", ratio=3),
                self.rich.Layout(name="activity", ratio=2),
                self.rich.Layout(name="events", ratio=2),
            )
        else:
            layout["main"].split_row(self.rich.Layout(name="left", ratio=3), self.rich.Layout(name="right", ratio=2))
            layout["left"].split_column(self.rich.Layout(name="pipeline", ratio=2), self.rich.Layout(name="activity", ratio=2))
            layout["right"].split_column(self.rich.Layout(name="current", ratio=2), self.rich.Layout(name="events", ratio=2))
        layout["header"].update(self.render_header())
        layout["pipeline"].update(self.render_pipeline())
        layout["activity"].update(self.render_activity())
        layout["current"].update(self.render_current())
        layout["events"].update(self.render_events())
        layout["footer"].update(self.render_footer())
        return layout

    def run(self) -> int:
        with self.rich.Live(
            self.render(),
            console=self.console,
            refresh_per_second=self.refresh_hz,
            screen=True,
            transient=False,
            auto_refresh=False,
        ) as live:
            while True:
                self.model.update()
                live.update(self.render(), refresh=True)
                if self.model.session_finished_at:
                    if self.finish_seen_at is None:
                        self.finish_seen_at = time.time()
                    elif time.time() - self.finish_seen_at >= self.final_delay_seconds:
                        break
                time.sleep(1.0 / self.refresh_hz)
        return self.model.exit_code if self.model.exit_code is not None else 0


def build_summary_markdown(summary: dict[str, Any]) -> str:
    lines = [
        f"# {APP_NAME}",
        "",
        f"- Label: `{summary.get('label', summary.get('run_id', ''))}`",
        f"- Mode: `{summary.get('mode', '')}`",
        f"- Health: **{summary['health']}**",
        f"- Exit code: `{summary['exit_code']}`",
        f"- Duration: `{summary['duration_s']}` s",
        f"- Run dir: `{summary['run_dir']}`",
        "",
        "## Steps",
        "",
        "| # | Status | Severity | Context | Name | RC | Duration |",
        "|---:|---|---|---|---|---:|---:|",
    ]
    for step in summary["steps"]:
        lines.append(
            f"| {step['index']} | {step['status']} | {step.get('severity', 'info')} | {escape_pipe(step.get('context', ''))} | {escape_pipe(step['name'])} | {step['return_code']} | {step['duration_s']} |"
        )
    lines.extend(
        [
            "",
            "## Files",
            "",
            f"- events.jsonl: `{summary['files']['events_jsonl']}`",
            f"- summary.json: `{summary['files']['summary_json']}`",
            f"- summary.md: `{summary['files']['summary_md']}`",
            f"- report.txt: `{summary['files']['report_txt']}`",
            f"- manifest.json: `{summary['files']['manifest_json']}`",
        ]
    )
    return "\n".join(lines) + "\n"


def summarize_session(session_dir: Path) -> int:
    manifest_path = session_dir / "manifest.json"
    summary_path = session_dir / "summary.json"

    if manifest_path.is_file() and summary_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            existing_summary = json.loads(summary_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            manifest = {}
            existing_summary = {}
        if manifest.get("mode") == "exec" and existing_summary:
            markdown = build_summary_markdown(existing_summary)
            (session_dir / "summary.md").write_text(markdown, encoding="utf-8")
            (session_dir / "report.txt").write_text(markdown, encoding="utf-8")
            return int(existing_summary.get("exit_code", 0))

    model = SessionModel(session_dir)
    model.update()
    summary = model.summary_payload()
    session_dir.mkdir(parents=True, exist_ok=True)
    (session_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    markdown = build_summary_markdown(summary)
    (session_dir / "summary.md").write_text(markdown, encoding="utf-8")
    (session_dir / "report.txt").write_text(markdown, encoding="utf-8")
    return 0 if summary.get("exit_code", 0) == 0 else int(summary.get("exit_code", 1))


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Runner visual e auditoria persistente do TermuxAiLocal.")
    subparsers = parser.add_subparsers(dest="subcommand")

    exec_parser = subparsers.add_parser("exec", help="Executa um perfil JSON com UI e logs persistentes.")
    exec_parser.add_argument("config", nargs="?", help="Path do JSON com steps.")
    exec_parser.add_argument("--logs-dir", default=DEFAULT_LOG_DIR, help="Diretório onde as runs serão salvas.")
    exec_parser.add_argument("--refresh-hz", type=float, default=DEFAULT_REFRESH_HZ, help="Frequência de refresh da UI.")
    exec_parser.add_argument("--poll-ms", type=int, default=DEFAULT_POLL_MS, help="Intervalo de poll dos streams.")
    exec_parser.add_argument("--tail-lines", type=int, default=DEFAULT_TAIL_LINES, help="Linhas recentes mantidas em memória.")
    exec_parser.add_argument("--event-lines", type=int, default=DEFAULT_EVENT_LINES, help="Eventos recentes mantidos em memória.")
    exec_parser.add_argument("--no-screen", action="store_true", help="Desativa alternate screen e usa saída textual simples.")
    exec_parser.add_argument("--ascii", action="store_true", help="Usa símbolos ASCII.")
    exec_parser.add_argument("--no-reports", action="store_true", help="Não gera HTML/SVG/TXT finais.")
    exec_parser.add_argument("--label", default="Runner local", help="Rótulo lógico da sessão.")

    watch_parser = subparsers.add_parser("watch", help="Renderiza no terminal uma sessão espelhada por eventos.")
    watch_parser.add_argument("session_dir", help="Diretório da sessão a observar.")
    watch_parser.add_argument("--refresh-hz", type=float, default=DEFAULT_REFRESH_HZ, help="Frequência de refresh da UI.")
    watch_parser.add_argument("--tail-lines", type=int, default=DEFAULT_TAIL_LINES, help="Linhas/atividades recentes em memória.")
    watch_parser.add_argument("--event-lines", type=int, default=DEFAULT_EVENT_LINES, help="Eventos recentes em memória.")
    watch_parser.add_argument("--ascii", action="store_true", help="Usa símbolos ASCII.")
    watch_parser.add_argument("--final-delay", type=float, default=DEFAULT_FINAL_DELAY_SECONDS, help="Segundos para manter o resumo final antes de sair.")

    summarize_parser = subparsers.add_parser("summarize", help="Resume uma sessão existente sem depender de Rich.")
    summarize_parser.add_argument("session_dir", help="Diretório da sessão a resumir.")

    return parser


def main() -> int:
    parser = build_arg_parser()
    args = parser.parse_args()

    if args.subcommand in (None, "exec"):
        config = getattr(args, "config", None)
        try:
            steps = load_steps(config)
        except Exception as exc:
            print(f"Erro ao carregar configuração: {exc}", file=sys.stderr)
            return 2
        runner = ExecRunner(
            steps,
            logs_dir=getattr(args, "logs_dir", DEFAULT_LOG_DIR),
            refresh_hz=getattr(args, "refresh_hz", DEFAULT_REFRESH_HZ),
            poll_ms=getattr(args, "poll_ms", DEFAULT_POLL_MS),
            tail_lines=getattr(args, "tail_lines", DEFAULT_TAIL_LINES),
            event_lines=getattr(args, "event_lines", DEFAULT_EVENT_LINES),
            no_screen=getattr(args, "no_screen", False),
            ascii_only=getattr(args, "ascii", False),
            save_reports=not getattr(args, "no_reports", False),
            session_label=getattr(args, "label", "Runner local"),
        )
        try:
            return runner.run()
        except RichUnavailable as exc:
            print(str(exc), file=sys.stderr)
            return 2
        finally:
            runner.close()

    if args.subcommand == "watch":
        try:
            watcher = SessionWatcher(
                Path(args.session_dir),
                refresh_hz=args.refresh_hz,
                event_lines=args.event_lines,
                tail_lines=args.tail_lines,
                ascii_only=args.ascii,
                final_delay_seconds=args.final_delay,
            )
            return watcher.run()
        except RichUnavailable as exc:
            print(str(exc), file=sys.stderr)
            return 2

    if args.subcommand == "summarize":
        return summarize_session(Path(args.session_dir))

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
