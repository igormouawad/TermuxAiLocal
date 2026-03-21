from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PolicyDecision:
    decision: str
    risk_level: str
    blocking_reasons: list[str]
    next_step: str


class UnknownUnsafePolicy:
    def evaluate(self, action_class: str) -> PolicyDecision:
        if action_class == "inspect_state":
            return PolicyDecision(
                decision="ALLOW",
                risk_level="SAFE",
                blocking_reasons=[],
                next_step="Apenas leitura de estado é permitida enquanto o cenário permanece ambíguo.",
            )

        return PolicyDecision(
            decision="BLOCK",
            risk_level="UNSAFE_FOR_IN_PROCESS_EXECUTION",
            blocking_reasons=[
                "O cenário operacional não pôde ser classificado com segurança.",
                "A política enterprise exige degradação segura antes de mutações.",
            ],
            next_step="Resolver o transporte, o device ou o contexto do operador antes de executar mutações.",
        )


UNKNOWN_UNSAFE_POLICY = UnknownUnsafePolicy()
