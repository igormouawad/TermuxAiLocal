# TermuxAiLocal

Automacao deterministica via host para Termux, Termux:X11 e Debian GUI em Android ARM64.

O projeto organiza um fluxo verificavel para provisionar, reinstalar, validar e operar uma stack grafica leve com Openbox e VirGL via ADB, com diagnostico explicito, recuperacao em estado limpo e rotinas reproduziveis.

## O que este repositorio faz

- provisiona a stack principal do Termux a partir do host
- reinstala os APKs oficiais do ecossistema Termux de forma limpa
- valida baseline de desktop, X11 e GPU com relatorio
- inicia o desktop suportado com perfil diario validado
- executa comandos X11 e apps Debian GUI a partir do host
- espelha sessoes host-side para uma UI visual no app Termux com logs persistentes leves
- preserva um fluxo operacional reproducivel para uso diario

## Arquitetura resumida

- `ADB/`: automacao host-side e wrappers ADB
- `Audit/`: runner visual, perfis JSON, watcher da sessao espelhada e docs de manutencao
- `Install/`: provisionamento, bootstrap e reinstalacao limpa
- `Debian/`: instalacao e launchers do Debian GUI em `proot`
- `lib/`: helpers compartilhados entre os scripts
- `Workspace-Handoff.md`: estado validado atual e comandos canonicos
- `README_ADB.md`: documentacao operacional detalhada

## Requisitos

- host Linux com `adb`, `bash`, `curl` e `python3`
- dispositivo Android ARM64
- apps `com.termux`, `com.termux.api` e `com.termux.x11`
- foco em validacao real por saida de comando, sem assumir estado limpo
- `TERMUXAI_DEVICE_ID=SERIAL` continua sendo a selecao explicita preferencial quando voce quiser fixar um alvo
- sem selecao explicita, os wrappers preferem o device conectado por USB
- sem USB, os wrappers tentam um unico endpoint por rede/Wi-Fi
- com ambiguidade, selecione explicitamente com `TERMUXAI_DEVICE_ID=SERIAL`

## Inicio rapido

Provisionamento inicial:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Install/adb_provision.sh
```

Fluxo diario validado:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report
```

Reinstalacao limpa canonica:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh
```

## Principios do workspace

- ADB orquestra; Termux executa
- `adb shell` nao substitui o contexto real do app Termux
- a UI canonica de auditoria agora vive no app Termux e consome eventos JSON espelhados pelo host
- o criterio aceito de 3D e EGL/GLES com `GL_RENDERER=virgl`
- o caminho grafico aceito neste workspace e `VirGL plain` com `GALLIUM_DRIVER=virpipe`
- o baseline diario suportado e `Openbox` com perfil `openbox-maxperf`

## Documentacao principal

- `README_ADB.md`
- `Audit/README.md`
- `Workspace-Handoff.md`
- `Termux-Android-Best-Practices.md`
- `Local-Model-Execution-Guide.md`

## Licenca

Este projeto e distribuido sob a licenca Apache-2.0. Veja `LICENSE`.
