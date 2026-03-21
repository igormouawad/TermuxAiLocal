from __future__ import annotations

from scenarios.android_wifi.policy import ANDROID_WIFI_POLICY
from scenarios.linux_usb.policy import LINUX_USB_POLICY
from scenarios.unknown_unsafe.policy import UNKNOWN_UNSAFE_POLICY


def resolve_policy(scenario_name: str):
    if scenario_name == "SCENARIO_1_LINUX_USB":
        return LINUX_USB_POLICY
    if scenario_name == "SCENARIO_2_ANDROID_WIFI":
        return ANDROID_WIFI_POLICY
    return UNKNOWN_UNSAFE_POLICY
