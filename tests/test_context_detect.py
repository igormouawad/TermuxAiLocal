from __future__ import annotations

import unittest

from adapters.adb.runtime import parse_adb_devices, parse_desktopmode_state
from context.detect import classify_scenario


class DetectScenarioTests(unittest.TestCase):
    def test_parse_usb_device(self) -> None:
        output = """List of devices attached
RX2Y901WJ2E            device usb:1-11 product:gts11xx model:SM_X736B device:gts11 transport_id:1
"""
        devices = parse_adb_devices(output)
        self.assertEqual(len(devices), 1)
        self.assertEqual(devices[0]["transport"], "usb")
        self.assertEqual(devices[0]["serial"], "RX2Y901WJ2E")

    def test_parse_desktop_dump_visible_tasks(self) -> None:
        dump_output = """
DesktopModeController
  inDesktopWindowing=true
  activeDesk=7
  Desk #7:
    visibleTasks=[12, 13, 14]
"""
        parsed = parse_desktopmode_state(dump_output)
        self.assertTrue(parsed["active"])
        self.assertEqual(parsed["active_desk"], "7")
        self.assertEqual(parsed["visible_tasks"], ["12", "13", "14"])

    def test_classify_linux_usb(self) -> None:
        scenario, risk, confidence, reasons, evidence = classify_scenario(
            host_kind="linux_workstation",
            terminal_kind="konsole",
            operator_context="local_workstation",
            adb_available=True,
            adb_transport="usb",
            adb_state="device",
            adb_device_id="RX2Y901WJ2E",
            devices=[{"serial": "RX2Y901WJ2E", "status": "device", "transport": "usb"}],
        )
        self.assertEqual(scenario, "SCENARIO_1_LINUX_USB")
        self.assertEqual(risk, "low")
        self.assertEqual(confidence, "high")
        self.assertFalse(reasons)
        self.assertTrue(evidence)


if __name__ == "__main__":
    unittest.main()
