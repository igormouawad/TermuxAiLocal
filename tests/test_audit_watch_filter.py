import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from Audit.audit_runner import SessionModel


class AuditWatchFilterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = TemporaryDirectory()
        self.session_dir = Path(self.temp_dir.name)
        (self.session_dir / "manifest.json").write_text(
            '{"mode":"mirror","label":"teste","started_at":"2026-03-21T12:00:00"}',
            encoding="utf-8",
        )
        (self.session_dir / "events.jsonl").write_text("", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def build_model(self) -> SessionModel:
        return SessionModel(self.session_dir)

    def test_skips_internal_bridge_command_event(self) -> None:
        model = self.build_model()
        model.process_event(
            {
                "type": "command",
                "message": "adb -s RX exec-out run-as com.termux /system/bin/sh -c stdout_file=/tmp/codex-bridge/termux-bridge-1/stdout.log",
                "seq": 1,
            }
        )
        self.assertEqual([], list(model.recent_events))
        self.assertEqual([], list(model.recent_activity))

    def test_skips_internal_bridge_meta_result(self) -> None:
        model = self.build_model()
        model.process_event(
            {
                "type": "command_result",
                "message": "__CODEX_TERMUX_META_BEGIN__\ndone=0\nstdout_size=0\nstderr_size=0\nexit_code=\npid=1\npid_alive=1\n__CODEX_TERMUX_META_END__",
                "seq": 1,
            }
        )
        self.assertEqual([], list(model.recent_events))
        self.assertEqual([], list(model.recent_activity))

    def test_keeps_real_failure_event(self) -> None:
        model = self.build_model()
        model.process_event(
            {
                "type": "failure",
                "level": "error",
                "message": "Falha real do comando alvo.",
                "seq": 1,
            }
        )
        self.assertEqual(1, len(model.recent_events))
        self.assertEqual("FAIL", model.health)


if __name__ == "__main__":
    unittest.main()
