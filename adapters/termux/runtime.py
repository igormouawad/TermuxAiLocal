from __future__ import annotations

from adapters.adb.runtime import list_packages


CRITICAL_PACKAGES = (
    "com.termux",
    "com.termux.api",
    "com.termux.x11",
)


OPTIONAL_ANDROID_APPS = (
    "com.server.auditor.ssh.client",
)


def critical_app_status(serial: str) -> dict[str, bool]:
    packages = list_packages(serial)
    result = {package: (package in packages) for package in CRITICAL_PACKAGES}
    for package in OPTIONAL_ANDROID_APPS:
        result[package] = package in packages
    return result
