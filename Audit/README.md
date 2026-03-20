# Audit Runner

`Audit/audit_runner.py` é a implementação canônica do runner visual deste workspace. Ele foi assimilado do bundle `AUDIT_RUNNER`, mas adaptado ao modelo real do projeto:

- wrappers shell continuam sendo a fonte de verdade da lógica operacional;
- a UI principal aparece no app `Termux` do Android;
- sessões host-side são espelhadas para o Termux por eventos JSON leves;
- os artefatos persistentes ficam no host em `Audit/runs/`.

## Modos

- `exec`: executa um perfil JSON com UI Rich e logs persistentes.
- `watch`: observa uma sessão espelhada já em andamento.
- `summarize`: resume uma sessão existente sem depender de `rich`.

Exemplos:

```bash
python3 Audit/audit_runner.py exec Audit/profiles/demo_host_exec.json --no-screen --no-reports
python3 Audit/audit_runner.py summarize Audit/runs/SESSAO
```

No Termux, após provisionamento do stack:

```bash
termux-audit-run demo_host_exec.json --no-screen --no-reports
termux-audit-watch /data/data/com.termux/files/home/.cache/termux-ai-local/audit/sessions/SESSAO
termux-audit-summarize /data/data/com.termux/files/home/.cache/termux-ai-local/audit/sessions/SESSAO
```

## Arquitetura

### 1. Sessões `exec`

O próprio runner executa os steps do JSON e grava:

- `manifest.json`
- `events.jsonl`
- `summary.json`
- `summary.md`
- `report.txt`
- `report.html` e `report.svg` quando `rich` está disponível
- `step-XXXX.log`

### 2. Sessões espelhadas do host

Os wrappers shell públicos usam hooks em `lib/termux_common.sh`:

- `termux::audit_session_begin`
- `termux::audit_step_begin`
- `termux::audit_step_finish`
- `termux::audit_note`
- `termux::audit_command`
- `termux::audit_command_result`
- `termux::audit_session_finish`

O host mantém a sessão canônica em `Audit/runs/<session-id>`.
Quando há device ADB disponível, a mesma sessão é espelhada para:

`/data/data/com.termux/files/home/.cache/termux-ai-local/audit/sessions/<session-id>`

O watcher do Termux lê `manifest.json` + `events.jsonl` desse espelho e renderiza a UI.

Para o launch automático vindo do host:

- cada sessão espelhada recebe um launcher curto e efêmero em `~/bin/termux-audit-watch-current`
- isso evita digitar no Android um comando longo com o path completo do espelho
- nos wrappers que reconstroem o desktop/Termux, o launcher é disparado só depois do `workspace ready`
- o `watch` já aceita timestamps ISO com e sem timezone no mesmo espelho

### 3. Sessões aninhadas

`workspace_host_menu.sh` abre uma sessão pai por ação.
Wrappers chamados por ele não criam uma segunda sessão; eles só anexam seus eventos à sessão já ativa.

## Perfis

Perfis úteis neste diretório:

- `demo_host_exec.json`: smoke local seguro.
- `demo_failure.json`: falha controlada com `continue_on_error=true`.
- `demo_timeout.json`: timeout controlado.
- `termux_openbox_smoke.json`: smoke básico do stack no próprio Termux.
- `demo_enterprise_bundle.json`: cópia de referência do bundle original.

## Dependências

No host:

- `python3` é suficiente para `summarize` e `exec --no-screen --no-reports`.
- `rich` é necessário para UI full-screen e relatórios HTML/SVG.

No Termux canônico:

- `python`
- `rich`

Essas dependências são provisionadas por `Install/install_termux_stack.sh`.

## Integração com os scripts existentes

Os scripts host-side foram integrados de forma incremental:

- a lógica operacional não foi migrada para JSON;
- o runner atua como camada visual e de auditoria;
- se a UI do Termux não puder ser aberta, os wrappers continuam funcionando no modo textual atual.

Desligar a auditoria visual:

```bash
TERMUXAI_AUDIT=0 bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox
```

## Manutenção

Para adicionar um novo perfil:

1. crie um JSON em `Audit/profiles/`
2. siga o formato enterprise:
   - lista de steps ou objeto com `defaults` + `steps`
   - campos suportados: `name`, `description`, `command`, `cwd`, `shell`, `timeout`, `continue_on_error`, `env`, `severity`, `pty`, `line_buffered`, `force_color`, `expected_returncodes`, `tags`
3. valide localmente com:

```bash
python3 Audit/audit_runner.py exec Audit/profiles/NOVO.json --no-screen --no-reports
```

Para alterar o protocolo do espelho host -> Termux:

1. ajuste os hooks em `lib/termux_common.sh`
2. preserve `manifest.json` e `events.jsonl`
3. valide:
   - lint shell
   - smoke `exec`
   - `summarize`
   - um wrapper host-side real

## Limites conhecidos

- o watcher no Termux depende de `python` + `rich` no próprio app.
- o espelho em tempo real prioriza eventos estruturados; ele não replica todo stdout bruto do host para evitar overhead excessivo.
- `ADB/adb_termux_send_command.sh` não abre uma sessão própria para evitar recursão; quando ele é chamado por wrappers auditados, os eventos entram na sessão pai.
