from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PolicyDecision:
    decision: str
    risk_level: str
    blocking_reasons: list[str]
    next_step: str


class LinuxUsbPolicy:
    def evaluate(self, action_class: str) -> PolicyDecision:
        return PolicyDecision(
            decision="ALLOW",
            risk_level="SAFE",
            blocking_reasons=[],
            next_step="O cenário local por USB está apto para execução direta com validação normal.",
        )


LINUX_USB_POLICY = LinuxUsbPolicy()
