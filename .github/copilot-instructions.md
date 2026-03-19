# TermuxAiLocal Workspace Instructions

## Architecture
- ADB orquestra. O app Termux executa.
- `adb shell` nunca substitui o contexto real do app Termux.
- O alvo principal do projeto e das pesquisas é melhorar estabilidade, performance e especialmente o caminho 3D no ambiente Termux/Termux:X11.

## Operational Baseline
- Antes de qualquer fluxo novo, executar `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`.
- Antes de digitar qualquer comando no tablet, confirmar por ADB qual app está focado.
- Se qualquer fluxo falhar, resetar completamente `com.termux`, `com.termux.x11` e `com.termux.api`, reabrir os apps e só então continuar.

## Execution Priorities
- Preferir evidência real do tablet a suposições locais.
- Para 3D, tratar `virgl` e `EGL/GLES` como caminho principal.
- Medir antes de mudar defaults quando a tarefa for de performance.

## Agent Workflow
- Para pesquisa, estudo e descoberta de melhorias novas, usar o agent `ASK`.
- O `ASK` deve trazer fatos, opções, riscos e hipóteses testáveis para o ambiente atual.
- O `PLAN` deve transformar a saída do `ASK` em um plano objetivo para execução pelo agent principal.
- O agent principal executa mudanças e validações no workspace e no tablet.
