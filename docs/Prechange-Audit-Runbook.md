# Prechange Audit Runbook

## Purpose

Executar uma auditoria estruturada antes de mutações relevantes, com:

- cenário detectado
- preflight
- inventário resumido
- decisão de risco por ação
- próximo passo acionável

## Public commands

Detectar cenário:

```bash
python3 ~/Documentos/AI/TermuxAiLocal/orchestration/cli.py detect-scenario --format json
```

Executar preflight:

```bash
python3 ~/Documentos/AI/TermuxAiLocal/orchestration/cli.py preflight --format json
```

Gerar auditoria pré-mudança:

```bash
python3 ~/Documentos/AI/TermuxAiLocal/orchestration/cli.py prechange-audit \
  --operation "desktop mode restart" \
  --action-class desktop_layout_restart \
  --format text
```

## Report artifacts

Os relatórios ficam em:

`Audit/runs/prechange-*/`

Arquivos gerados:

- `prechange_audit.json`
- `prechange_audit.md`

## Integration model

- wrappers públicos chamam o prechange audit automaticamente quando são a sessão pai
- wrappers aninhados não abrem auditoria adicional para evitar ruído
- o menu host-side passa a auditar a ação selecionada antes do handler real

## Operator guidance

- cenário local com USB:
  - o fluxo pode seguir normalmente
- cenário Android + Wi‑Fi:
  - qualquer ação classificada como `UNSAFE_FOR_IN_PROCESS_EXECUTION` deve ser bloqueada
  - o próximo passo correto é mudar para o workstation por USB ou usar um caminho indireto/manual
