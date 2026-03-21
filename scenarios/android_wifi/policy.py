from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PolicyDecision:
    decision: str
    risk_level: str
    blocking_reasons: list[str]
    next_step: str


SAFE_ACTIONS = {
    "inspect_state",
    "continue_patch_check",
}

CAUTION_ACTIONS = {
    "desktop_app_launch",
    "desktop_layout_apply",
    "x11_runtime_launch",
    "x11_resolution_change",
}

UNSAFE_ACTIONS = {
    "desktop_mode_control",
    "desktop_layout_restart",
    "stack_reset",
    "desktop_stack_start",
    "baseline_validation",
    "wifi_control_usb",
    "termux_provision",
    "termux_reinstall",
    "debian_provision",
    "debian_install",
}


class AndroidWifiPolicy:
    def evaluate(self, action_class: str) -> PolicyDecision:
        if action_class in SAFE_ACTIONS:
            return PolicyDecision(
                decision="ALLOW",
                risk_level="SAFE",
                blocking_reasons=[],
                next_step="A ação é observável e não deve interferir na sessão hospedeira do Codex.",
            )

        if action_class in CAUTION_ACTIONS:
            return PolicyDecision(
                decision="ALLOW",
                risk_level="CAUTION",
                blocking_reasons=[],
                next_step="Executar apenas mantendo a sessão hospedeira preservada e validar o resultado por evidência observável.",
            )

        return PolicyDecision(
            decision="BLOCK",
            risk_level="UNSAFE_FOR_IN_PROCESS_EXECUTION",
            blocking_reasons=[
                "Ação incompatível com session safety no cenário Android + ADB por Wi‑Fi.",
                "O fluxo pode desestabilizar, reiniciar, minimizar criticamente ou interromper o terminal hospedeiro.",
            ],
            next_step="Trocar para o cenário Linux+USB ou executar um caminho indireto/manual que preserve a sessão hospedeira.",
        )


ANDROID_WIFI_POLICY = AndroidWifiPolicy()
