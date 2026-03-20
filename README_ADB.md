# TermuxAiLocal

## Objetivo do projeto

Este projeto organiza o provisionamento de uma stack Termux/Termux:X11 em dispositivo Android ARM64 com uma arquitetura explícita e verificável.

- ADB orquestra.
- Termux executa.
- `adb shell` não equivale ao contexto real do app Termux.
- Documentação complementar: veja `Termux-Android-Best-Practices.md` para um runbook simplificado sobre foco de atividades, `run-as` vs UI e checagens de virgl/glmark2.
- a execução automática host-side agora prioriza transporte síncrono via `run-as com.termux` quando o APK debug do GitHub permite isso
- quando `run-as` não está disponível, o projeto ainda mantém fallback por foco/UI no app Termux
- o mecanismo oficial `RUN_COMMAND` do ecossistema Termux continua relevante, mas o usuário `shell` do ADB não consegue acioná-lo diretamente neste fluxo host-side sem um app companheiro com a permissão adequada
- O payload continua sendo executado manualmente dentro do app Termux.

## Raiz oficial do projeto

`~/Documentos/AI/TermuxAiLocal`

Os scripts host-side resolvem essa raiz dinamicamente a partir do diretório do repositório e compartilham a biblioteca `lib/termux_common.sh` para padronizar falhas, checagem de dependências, seleção do alvo ADB e execução remota com `adb -s`.

Seleção de device ADB:

- com `TERMUXAI_DEVICE_ID` ou `--device SERIAL`, a escolha continua explícita e tem precedência total
- sem seleção explícita, os wrappers host-side preferem o alvo ADB direto por USB quando ele existir
- sem USB disponível, os wrappers tentam autodetectar um único alvo por rede/Wi‑Fi
- se não houver um alvo Wi‑Fi já conectado, os wrappers tentam recuperar automaticamente o ADB por rede nesta ordem:
  - `adb reconnect offline`
  - endpoints já vistos pelo `adb devices -l`
  - descoberta `adb mdns services`
  - último endpoint Wi‑Fi válido em cache local do host
  - varredura curta de portas no último IP Wi‑Fi válido em cache local do host
- em cenários ambíguos, como múltiplos alvos USB ou múltiplos alvos por rede, a execução falha e exige `TERMUXAI_DEVICE_ID=SERIAL` ou `--device SERIAL`

Observação importante sobre persistência:

- em Android 11+ o mecanismo oficial é `Wireless debugging`
- o workspace consegue recuperar a conexão automaticamente quando o serviço continua disponível e apenas o endpoint mudou
- o Android não oferece um modo suportado pelo projeto para manter `Wireless debugging` permanentemente ligado através de reboot ou quando o sistema realmente desabilita esse serviço
- quando o próprio Android desligar o `Wireless debugging`, a recuperação totalmente automática deixa de ser possível sem USB ou intervenção na UI do dispositivo
- quando não houver USB e a recuperação automática por Wi‑Fi falhar:
  - se o Codex estiver rodando por SSH a partir do próprio tablet (`Terminus`), o próximo passo recomendado deve ser ativar manualmente `Wireless debugging`
  - se o Codex estiver rodando localmente no workstation Linux, o próximo passo recomendado deve ser conectar o tablet por USB
- o helper comum detecta esse contexto automaticamente por `SSH_CONNECTION`/`SSH_CLIENT` combinados com o IP Android conhecido em cache; para depuração, o comportamento pode ser forçado com `TERMUXAI_OPERATOR_CONTEXT=android_ssh|local_workstation|auto`
- neste Samsung `SM-X736B`, o workspace validou um caminho prático adicional quando o USB está presente:
  - `settings put global adb_wifi_enabled 1`
  - descoberta curta da porta de `connect`
  - `adb connect IP:porta`
- esse caminho fica encapsulado em:
  - `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_wifi_debug.sh connect`
- trate esse fluxo como validação específica do device, não como API Android oficialmente documentada e portátil

Tudo que é referente à instalação fica dentro de `Install/`.

Tudo que é referente ao Debian Trixie em proot para apps GUI fica dentro de `Debian/`.

Entry point interativo do host:

- `workspace_host_menu.sh`: menu host-side com os comandos canonicos mais usados do workspace.

Uso rapido:

- listar itens do menu do host:
  - `bash ~/Documentos/AI/TermuxAiLocal/workspace_host_menu.sh --list`
- executar um item do host por `ACTION_ID`:
  - `bash ~/Documentos/AI/TermuxAiLocal/workspace_host_menu.sh --run stack_status --yes`
- listar itens do menu no Termux:
  - `termux-workspace-menu --list`
- executar um item do menu no Termux por `ACTION_ID`:
  - `termux-workspace-menu --run status_brief --yes`

## Distinção entre apps Android e pacotes internos do Termux

Apps Android obrigatórios:

- `com.termux`
- `com.termux.api`
- `com.termux.x11`

APKs recomendados para ARM64:

- Termux: `termux-app_v0.118.3+github-debug_arm64-v8a.apk`
- Termux:API: `termux-api-app_v0.53.0+github.debug.apk`
- Termux:X11: `app-arm64-v8a-debug.apk` da nightly

Pacotes internos do Termux são instalados depois, já dentro do app Termux, pelo payload `Install/install_termux_stack.sh`. Eles não substituem os apps Android e não devem ser confundidos com eles.

## Layout de instalação

- `Install/adb_provision.sh`: provisionamento host-side do payload principal.
- `Install/adb_reinstall_termux_official.sh`: reinstalação limpa dos APKs oficiais, reenvio dos payloads e bootstrap automático pós-reinstalação.
- `Install/install_termux_stack.sh`: payload principal executado dentro do app Termux.
- `Install/install_termux_repo_bootstrap.sh`: bootstrap fino executado dentro do app Termux recém-instalado.
- `Install/termux_workspace_menu.sh`: fonte do menu interativo instalado no `~/bin` do Termux como `termux-workspace-menu`.
- `Install/.cache/termux-apks/`: cache local de APKs e metadados de release usados pela reinstalação.

## Layout operacional

- `Audit/audit_runner.py`: runner visual canônico com modos `exec`, `watch` e `summarize`.
- `Audit/profiles/`: perfis JSON de referência e smoke tests controlados.
- `ADB/adb_reset_termux_stack.sh`: reset e preparação do ecossistema Termux.
- `ADB/adb_configure_phantom_processes.sh`: leitura/aplicação do override recomendado para limitar menos o Android contra `phantom processes`.
- `ADB/adb_validate_baseline.sh`: validação reproduzível do baseline e geração de relatórios.
- `ADB/adb_start_desktop.sh`: subida host-side do desktop suportado.
- `ADB/adb_consolidate_freeform_desktop.sh`: consolida o desktop mode aprovado de forma contextual: no workstation local, `Termux` ampliado + `Termux:X11`; em `android_ssh`, mantém o trio com cliente SSH.
- `ADB/adb_open_desktop_app.sh`: entrypoint canônico para abrir um app Android visível em desktop mode, preservando o workspace base contextual e aplicando o layout `Foco grande`.
- `ADB/adb_open_desktop_app.sh --reflow-only`: reaplica o layout atual do desktop mode sem abrir uma activity nova; sem `--package`, escolhe o app extra visível mais recente como janela principal do reflow.
- `ADB/adb_run_workspace_regression.sh`: wrapper host-side único para regressão canônica do workspace, com suites `smoke`, `daily`, `desktop-layout` e `full`.
- `ADB/adb_run_x11_command.sh`: execução remota de apps e scripts no display X11 `:1`.
- `ADB/adb_stop_termux_x11.sh`: encerra a app Android `Termux:X11` por `adb` sem resetar o ecossistema inteiro.
- `ADB/adb_set_x11_resolution.sh`: aplicação host-side dos perfis de resolução do Termux:X11.
- `ADB/adb_termux_send_command.sh`: helper host-side para execução síncrona no contexto do Termux, com `run-as` como caminho preferencial, retorno estruturado de `stdout`/`stderr`/`exit code` e fallback por UI apenas quando necessário.
- `ADB/adb_wifi_debug.sh`: helper host-side para inspecionar, ligar, desligar e conectar o ADB por Wi‑Fi usando USB como transporte de controle.
- Para helpers X11/GPU sensíveis, o mesmo wrapper agora suporta disparo no shell real do app Termux com polling estruturado por spool, evitando regressões causadas por namespace divergente do `run-as`.

Fluxo único de regressão recomendado para manutenção:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_workspace_regression.sh --suite full
```

Esse wrapper:

- abre uma sessão pai única de audit para todo o fluxo
- reutiliza os wrappers já validados do workspace
- mantém o fluxo diário canônico intacto
- acrescenta a regressão visual do desktop mode com `adb_open_desktop_app.sh`
- termina testando o reflow explícito sem abrir um app novo

Observação:

- o wrapper de regressão não substitui o mapeamento natural já documentado para `fluxo diario limpo completo`; ele é um entrypoint de manutenção e regressão
- no contexto local do workstation, o layout base não reabre `Terminus`; o `Termux` ocupa a coluna esquerda ampliada por padrão

## Layout Debian

- `Debian/adb_provision_debian_trixie_gui.sh`: provisiona no dispositivo os payloads Debian GUI e imprime tanto o comando manual no Termux quanto o wrapper host-side síncrono de instalação.
- `Debian/adb_install_debian_trixie_gui.sh`: executa do host a instalação Debian GUI dentro do app Termux, via `run-as+spool`, sem watchdog remoto e com saída contida.
- `Debian/install_debian_trixie_gui.sh`: payload principal executado dentro do app Termux para instalar e configurar o Debian Trixie no `proot-distro`.
- `Debian/configure_debian_trixie_root.sh`: configuração interna do Debian como `root`, incluindo pacotes GUI base, `sudo`, grupos e criação/ajuste do usuário Debian escolhido pelo operador.
- `Debian/configure_debian_trixie_user.sh`: configuração interna do usuário Debian escolhido, incluindo envs e launchers estável/experimental.
- `Debian/run_gui_in_debian.sh`: launcher Termux-side genérico para abrir qualquer app GUI do Debian no X11 `:1` já existente.

## Telemetria de execução e progresso

Os scripts agora deixam explícito onde a etapa está rodando, sem adicionar loops extras nem mudar o caminho validado do runtime:

- wrappers host-side mostram:
  - `[HOST] ...`
  - `[HOST:OK ...]`
- payloads executados dentro do app Termux mostram:
  - `[TERMUX] ...`
  - `[TERMUX:CMD] ...`
  - `[TERMUX:OK ...]`
- payloads internos do Debian mostram:
  - `[DEBIAN-ROOT] ...`
  - `[DEBIAN-ROOT:CMD] ...`
  - `[DEBIAN-ROOT:OK ...]`
  - `[DEBIAN-USER] ...`
  - `[DEBIAN-USER:CMD] ...`
  - `[DEBIAN-USER:OK ...]`
- falhas continuam no contrato único:
  - `FALHA DETECTADA`

Camada visual canônica:

- os wrappers host-side públicos agora também geram uma sessão persistente em `Audit/runs/<session-id>`
- quando o device ADB está disponível e o runner já foi instalado no Termux, a sessão é espelhada para:
  - `/data/data/com.termux/files/home/.cache/termux-ai-local/audit/sessions/<session-id>`
- o app Termux passa a mostrar essa sessão com:
  - `termux-audit-watch`
- para o launch automático host-side, o espelho atual também ganha um launcher curto e efêmero:
  - `~/bin/termux-audit-watch-current`
- wrappers que reestabilizam o desktop/Termux primeiro e só depois abrem a UI:
  - o watcher nasce depois do `workspace ready`, para não morrer junto com resets/reaberturas do próprio ecossistema Termux
- o runner principal instalado no Termux também expõe:
  - `termux-audit-run`
  - `termux-audit-summarize`
- se a UI do Termux não puder ser aberta, os wrappers continuam funcionando no modo textual atual, sem regressão do fluxo operacional

Objetivo:

- mostrar porcentagem e etapa atual
- deixar claro o contexto real da execução
- confirmar sucesso ou falha por etapa
- sem reduzir a performance do fluxo já validado

## Função dos scripts

`Install/adb_provision.sh`:

- valida `adb`
- prioriza o device conectado diretamente por USB; sem USB, tenta um único alvo por rede/Wi‑Fi
- em cenários ambíguos, exige seleção explícita via `TERMUXAI_DEVICE_ID` ou pelas flags suportadas pelo helper
- audita os apps Android obrigatórios no usuário principal Android suportado pelo ADB (`--user 0`)
- transfere o payload `Install/install_termux_stack.sh` para `/data/local/tmp/install_termux_stack.sh`
- transfere também `Audit/audit_runner.py` e os perfis JSON para `/data/local/tmp/termuxai_audit_*`
- aplica `chmod +x` no payload
- garante o desktop mode livre do workspace e restaura `Termux`, `Termux:X11` e o cliente SSH no arranjo aprovado
- orienta a execução manual do payload

`Install/adb_reinstall_termux_official.sh`:

- valida `adb`, `curl` e `python3` no host
- exibe etapas host-side com porcentagem e confirmações explícitas de sucesso
- prioriza o device conectado diretamente por USB; sem USB, tenta um único alvo por rede/Wi‑Fi
- ainda exige ABI `arm64-v8a`; em cenários ambíguos, exige seleção explícita
- resolve por GitHub API as releases oficiais mais recentes de `termux-app`, `termux-api` e `termux-x11`
- com `--dry-run`, valida releases e downloads no host sem tocar a instalação atual do dispositivo
- baixa apenas APKs oficiais do owner `termux`
- mantém o cache host-side em `Install/.cache/termux-apks/`
- desinstala `com.termux`, `com.termux.api` e `com.termux.x11` para evitar mistura de assinatura/origem
- limpa apenas resíduos controlados do projeto em `/data/local/tmp` e arquivos temporários conhecidos
- reinstala os APKs oficiais por `adb install -r -g`
- reaplica grants e app-ops pós-instalação para reduzir prompts manuais no dispositivo:
  - `POST_NOTIFICATIONS`
  - whitelist de bateria para os três pacotes
  - `SYSTEM_ALERT_WINDOW`, `MANAGE_EXTERNAL_STORAGE`, `WRITE_SETTINGS` e `GET_USAGE_STATS` em `com.termux` e `com.termux.api`
- reenviа `Install/install_termux_stack.sh` e `Install/install_termux_repo_bootstrap.sh` para `/data/local/tmp`
- reenviа também o audit runner e os perfis JSON para `/data/local/tmp/termuxai_audit_*`
- abre `Termux:API`, lança o app `Termux`, espera o shell real ficar pronto e roda o bootstrap fino automaticamente
- só depois dessa confirmação o fluxo deve seguir para o app Termux com o bootstrap manual

`ADB/adb_validate_baseline.sh`:

- valida `adb` e trabalha sobre o alvo ADB selecionado
- reinicia `com.termux`, `com.termux.x11` e `com.termux.api` antes do teste
- valida o desktop escolhido com `--desktop=openbox|xfce`
- confirma por retorno síncrono dos helpers a presença dos comandos de start e stop do desktop selecionado
- sobe a sessão escolhida, abre o app `Termux:X11`, valida o `SurfaceView` e também os processos centrais do desktop
- encerra a sessão com o helper correspondente
- com `--with-gpu`, também executa `start-virgl` e `check-gpu-termux`
- para `XFCE`, a subida host-side usa `start-xfce-x11-detached` para não prender a shell foreground do app Termux; a validação passa a depender do estado real da sessão e não de eco textual visível no terminal
- com `--with-gpu`, a validação roda `check-gpu-termux` só depois de a sessão gráfica já estar ativa em `:1`
- com `--report`, salva resumo, saída dos helpers e dumps XML em `reports/validate-baseline-<timestamp>/`
- coleta no relatório metadados básicos do dispositivo, como fabricante, modelo, Android, plataforma e refresh rate
- com `--stress-seconds=N`, mantém a sessão do desktop/X11 viva por `N` segundos antes do encerramento para testar estabilidade curta

`ADB/adb_run_x11_command.sh`:

- envia um comando ao app Termux para execução explícita no contexto X11 `:1`
- usa `run-in-x11 --app` por padrão
- com `--with-virgl`, sobe `start-virgl` usando o modo ativo do perfil X11 antes do comando
- com `--xterm`, executa o comando dentro de uma nova janela `xterm`
- com `--script arquivo_local`, envia um script do host para `/data/local/tmp/` e o executa no X11 sem depender de quoting frágil via teclado Android
- quando `run-as` está disponível, o retorno do helper volta ao host de forma síncrona para validação imediata
- os wrappers host-side deixam de descartar a saída remota e passam a devolvê-la ao host para auditoria e troubleshooting

`ADB/adb_set_x11_resolution.sh`:

- aplica perfis de resolução do Termux:X11 a partir do host
- abre `Termux:X11` e `Termux` antes de disparar `set-x11-resolution`
- aceita `performance`, `balanced`, `native`, `show` e `custom LARGURAxALTURA`

`ADB/adb_consolidate_freeform_desktop.sh`:

- abre o workspace base diretamente em `windowingMode=freeform`
- aplica por padrão o layout contextual aprovado no tablet atual:
  - em `android_ssh`:
    - `Termux` no topo esquerdo
    - cliente SSH (`Terminus`/`com.server.auditor.ssh.client`) embaixo à esquerda
    - `Termux:X11` à direita
  - em `local_workstation`:
    - `Termux` ampliado na coluna esquerda
    - `Termux:X11` à direita
    - `Terminus` não é reaberto por padrão
- com `--restart`, fecha os apps gerenciados e recria o layout completo para teste de reabertura
- se a sessão gráfica estiver inativa, sobe `Openbox` com o perfil pedido sem voltar a layouts legados do Android

`ADB/adb_open_desktop_app.sh`:

- é o caminho canônico para abrir apps Android visíveis durante o trabalho host-side
- sempre garante `desktop mode` antes da abertura
- mantém o workspace base contextual visível:
  - em `android_ssh`, `Termux` + `Termux:X11` + SSH
  - em `local_workstation`, `Termux` + `Termux:X11`
- aplica a política visual `Foco grande`:
  - app recém-aberto como janela principal
  - base contextual compactada em janelas auxiliares
  - a área útil real do desktop é medida a partir das insets da `StatusBar` e da `TaskbarWindow`, então o layout não usa mais `2560x1600` bruto
  - quando já existe 1 app extra visível, o helper usa um arranjo de 5 janelas compatível com o limite real do Samsung:
    - `X11` no topo esquerdo
    - `Termux` embaixo à esquerda
    - app principal grande no topo direito
    - SSH e o app extra lado a lado na faixa inferior direita
  - isso evita que janelas mínimas do Samsung caiam atrás da taskbar ou se sobreponham fora da área útil
- foco final padrão:
  - em contexto local no workstation, o foco final padrão continua sendo o app recém-aberto
  - quando o operador está no próprio tablet via `Terminus`, o helper mantém o foco final no SSH por padrão para preservar o controle da sessão
- exemplo:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_open_desktop_app.sh --package com.android.settings
```

Observação importante sobre transporte host-side:

- o projeto usa APKs GitHub debug do ecossistema Termux, o que viabiliza `run-as com.termux` como transporte síncrono e mais confiável para comandos remotos
- isso reduz dependência de foco, teclado Android e polling por XML quando comparado ao fluxo puramente baseado em UI
- no caminho `run-as`, não há timeout oculto por padrão; o `--timeout` vira uma política explícita do chamador, e não uma limitação invisível do transporte
- se o dispositivo ou build não permitir `run-as`, o fallback continua existindo, mas deve ser tratado como compatibilidade e não como caminho preferencial

`ADB/adb_reset_termux_stack.sh`:

- faz reset completo de `com.termux`, `com.termux.x11` e `com.termux.api`
- executa também uma limpeza remota best-effort da sessão gráfica anterior dentro do contexto do app Termux, removendo Openbox/XFCE, terminais leves, `virgl`, `dbus` de sessão e caches controlados do projeto
- mata e valida a remoção dos processos residuais do ecossistema Termux antes de reabrir os apps
- mantém `Termux:API` fora do desktop visível; a app só entra automaticamente no reinstall limpo
- reabre o desktop mode livre do workspace no layout contextual aprovado para o contexto do operador
- permite escolher o foco final com `--focus termux|x11`
- deve ser o primeiro passo de qualquer fluxo novo e o passo obrigatório depois de qualquer falha de automação

`ADB/adb_configure_phantom_processes.sh`:

- lê o estado atual de `settings_enable_monitor_phantom_procs` e `activity_manager/max_phantom_processes`
- aplica o override recomendado por ADB com `device_config set_sync_disabled_for_tests persistent`
- grava `max_phantom_processes=2147483647`
- grava `settings_enable_monitor_phantom_procs=false`
- valida o resultado também em `dumpsys activity settings`

`lib/termux_common.sh`:

- concentra a infraestrutura compartilhada dos scripts host-side
- padroniza `fail`, checagem de binários do host, resolução de device ADB único e wrapper `adb -s`
- reduz divergência entre provisionamento, reset, reinstall, validação e automação de UI

Observação importante sobre perfis Android:

- a auditoria host-side do projeto considera o usuário principal Android (`user 0`)
- apps instalados apenas em `Secure Folder` ou outro perfil inacessível ao shell ADB não satisfazem a validação do projeto
- `SecurityException` do Package Manager deve ser tratada como falha real de contexto/permissão, não como confirmação de app ausente

`Install/install_termux_stack.sh`:

- valida que está rodando dentro do app Termux
- agora marca explicitamente no log o contexto `TERMUX`, o comando da etapa e a confirmação de sucesso
- fixa antes do primeiro `pkg` o mirror default upstream do Termux em `packages-cf.termux.dev` (`main`, `root`, `x11`) e grava `sources.list`/`etc/termux/mirrors/default`
- atualiza os pacotes via `pkg`, incluindo `pkg update -y` e `pkg upgrade -y`
- instala `python` no Termux e aplica `python -m pip install --upgrade rich`
- publica o runner e os perfis em `~/.local/share/termux-ai-local/audit/`
- instala em `~/bin`:
  - `termux-audit-run`
  - `termux-audit-watch`
  - `termux-audit-summarize`
- instala `x11-repo` antes dos demais pacotes
- instala `termux-x11-nightly`, `termux-api`, `virglrenderer-android`, `mesa-demos`, `pulseaudio`, `dbus`, `openbox`, `aterm`, `xterm` e `glmark2`
- instala também um perfil XFCE funcional com `xfce4-session`, `xfce4-panel`, `xfce4-terminal`, `xfdesktop`, `xfwm4` e `thunar`
- cria os utilitários `~/bin/start-termux-x11`, `~/bin/start-virgl`, `~/bin/stop-virgl`, `~/bin/check-gpu-termux`, `~/bin/start-openbox-x11`, `~/bin/start-openbox`, `~/bin/start-openbox-stable`, `~/bin/start-openbox-maxperf`, `~/bin/start-openbox-compat`, `~/bin/start-openbox-vulkan-exp`, `~/bin/stop-openbox-x11`, `~/bin/start-xfce-x11`, `~/bin/start-xfce-x11-detached`, `~/bin/start-maxperf-x11` e `~/bin/stop-xfce-x11`
- cria também `~/bin/run-in-x11` para lançar comandos explicitamente dentro do display `:1`
- cria também `~/bin/run-glmark2-x11` para lançar o benchmark no X11 com o perfil de driver ativo e recusar execução sem `start-virgl`
- cria também `~/bin/set-x11-resolution` para aplicar perfis de resolução diretamente do app Termux
- instala também `~/bin/termux-workspace-menu` como menu interativo dos helpers e payloads locais do projeto
- o helper `~/bin/termux-stack-status` imprime o estado de `X11`, `VIRGL`, `virgl-mode`, `DESKTOP`, `WM`, `RES`, `PROFILE`, `OPENBOX_PROFILE`, `DRIVER` e `DBUS`, além de manter um modo `--brief` para avaliações rápidas
- `start-virgl` aceita `plain`, `gl` e `vulkan`, usando `plain` por padrão no perfil agressivo de performance 3D; o helper agora restringe `LD_LIBRARY_PATH` ao diretório privado `.../opt/virglrenderer-android/lib`, o que preserva `libepoxy.so`/`libvirglrenderer.so` do pacote sem arrastar `libEGL/libGLES` do Mesa do Termux para dentro do host `virgl`
- `check-gpu-termux` prioriza o diagnóstico EGL/GLES com `virpipe` e mantém fallback GLX em software quando necessário
- `start-openbox-x11 --profile openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp` sobe um baseline gráfico leve com envs de sessão/driver separadas; `openbox-maxperf` é o padrão diário, `openbox-stable` preserva um modo mais conservador, `openbox-compat` usa a trilha `virgl_angle` e `openbox-vulkan-exp` ativa o wrapper Vulkan experimental
- o launcher do Openbox agora sobe primeiro o processo `openbox` e só então abre o terminal leve; isso elimina a janela espúria `true` observada em versões anteriores e evita validar sessão apenas porque um terminal sobreviveu
- `start-xfce-x11` sobe o XFCE completo no display `:1` e aceita `--wm xfwm4|openbox`; `xfwm4` continua sendo o padrão e `openbox` substitui apenas o window manager, sem trocar o desktop inteiro
- `start-xfce-x11-detached` dispara `start-xfce-x11` em background, já garantindo a activity do `Termux:X11`, e é o launcher usado pelos wrappers host-side para não sequestrar o prompt do app Termux
- `start-maxperf-x11 [openbox|xfce]` virou o atalho explícito para benchmark/perfil agressivo: reinicia a sessão, força `1280x720`, reinicia o `virgl` em `plain` e sobe `Openbox` puro ou `XFCE --wm openbox`
- o payload agora grava `1920x1080` como resolução padrão do `Termux:X11`; `TERMUX_X11_BALANCED_RESOLUTION` fica em `1920x1080` e `TERMUX_X11_PERFORMANCE_RESOLUTION` passa a `1280x720` por padrão
- o payload agora também grava `showAdditionalKbd=false`, `additionalKbdVisible=false` e `swipeDownAction=no action`, removendo por padrão a fileira extra `ESC / - HOME UP END PGUP` do `Termux:X11`
- o painel `tint2` do Openbox diário agora fica no topo, o launcher `rofi` usa tema gerenciado e o Openbox grava `~/.config/openbox/rc.xml` com hotkeys diárias (`Super+Space`, `Super+Enter`, `Super+E`, `Super+,`, `Super+1..4`)
- `openbox-terminal` agora prefere o `xfce4-terminal` do Debian e `openbox-launcher` passou a enxergar só o catálogo local curado em `~/.local/share/applications`, evitando a poluição de atalhos internos do XFCE host
- `openbox-launcher` agora também dispara a sincronização dos atalhos Debian antes de abrir o `rofi`, então apps recém-instalados por `apt` no Debian aparecem no launcher sem exigir `sync-termux-desktop-entries` manual
- `start-openbox-x11` e `start-openbox-maxperf` agora sobem o desktop diário sem abrir terminal automático nem probes GPU visuais; terminal e launcher ficam disponíveis só por botão/hotkey quando o usuário quiser
- `set-x11-resolution performance` agora é o preset agressivo do projeto para reduzir fill-rate no tablet; use `balanced` para voltar ao desktop cheio em `1920x1080`
- `termux-stack-status` agora calcula `RES` e `PROFILE` a partir do `termux-x11-preference list` real, então `PROFILE=performance` só aparece quando o `1280x720` está de fato aplicado
- os helpers de X11 usam o processo `termux-x11` no display correto como fonte de verdade; a activity Android `com.termux.x11` por si só não garante `:0` nem `:1`
- no fluxo `:1`, `run-in-x11` aceita como evidência válida a sessão Openbox/X11 viva, mesmo quando o processo `termux-x11 :1` não permanece listado no Termux
- comandos que precisem rodar dentro do X11 devem usar `run-in-x11` no Termux ou `ADB/adb_run_x11_command.sh` no host

`Install/install_termux_repo_bootstrap.sh`:

- valida que está rodando no app Termux recém-instalado
- agora mostra porcentagem real por etapa e confirmação explícita antes de delegar ao payload principal
- fixa antes de delegar o mirror default upstream do Termux em `packages-cf.termux.dev` (`main`, `root`, `x11`) para evitar o fluxo interativo de teste de mirrors no primeiro `pkg`
- valida a presença do payload principal em `/data/local/tmp/install_termux_stack.sh`
- delega para o payload principal sem duplicar a lógica de instalação/configuração do projeto

`Debian/install_debian_trixie_gui.sh`:

- valida que está rodando dentro do app Termux
- agora sinaliza explicitamente no log que o provisionamento Debian está executando no contexto `TERMUX`
- atualiza os pacotes via `pkg`
- garante `proot-distro`, `pulseaudio` e `dbus` no host Termux
- instala uma instância Debian Trixie dedicada com alias próprio no `proot-distro`
- copia os payloads internos do Debian para dentro do rootfs
- coleta ou recebe nome do usuário Debian, senha e política de sudo
- executa a configuração root e depois a configuração do usuário Debian escolhido
- instala os helpers `run-gui-debian` e `login-debian-gui` em `~/bin`

`Debian/configure_debian_trixie_root.sh`:

- atualiza o `apt` do Debian Trixie
- agora marca cada etapa com contexto `DEBIAN-ROOT`, comando executado e confirmação explícita de sucesso
- instala `sudo`, `dbus-x11`, `pulseaudio`, `mesa-utils`, `mesa-utils-extra`, `x11-apps`, `xauth`, `xterm`, `openbox`, `xfce4-session`, `xfce4-panel`, `xfwm4`, `xfce4-terminal`, `xfce4-settings`, `thunar` e `glmark2`
- cria ou atualiza o usuário Debian escolhido pelo operador
- adiciona esse usuário aos grupos Debian relevantes (`sudo`, `audio`, `video`, `render`, `input`, `plugdev`, `users`)
- configura `sudo` com ou sem senha conforme a política escolhida

`Debian/configure_debian_trixie_user.sh`:

- cria o runtime X11 do usuário em `/tmp/runtime-<usuario>`
- agora marca cada etapa com contexto `DEBIAN-USER`, comando executado e confirmação explícita de sucesso
- grava um arquivo de ambiente para `DISPLAY=:1`, `XDG_RUNTIME_DIR`, `TERMUX_X11_WM`, locale e modo de renderização padrão em hardware
- cria `~/bin/start-xfce-termux-x11`, que sobe o XFCE dentro do Debian e aceita `--wm xfwm4|openbox`
- cria `~/bin/run-gui-termux` como launcher genérico em hardware com `GALLIUM_DRIVER=virpipe`
- cria `~/bin/run-gui-termux-virgl` como alias explícito do launcher de hardware
- cria `~/bin/run-gui-termux-software` como fallback manual com `LIBGL_ALWAYS_SOFTWARE=1`

`Debian/run_gui_in_debian.sh`:

- exige uma sessão X11/desktop já ativa no display `:1`
- entra no Debian Trixie pelo `proot-distro`
- troca para o usuário Debian gravado em `~/.config/termux-stack/debian-gui.env` ou informado via `--user`
- lança qualquer aplicativo GUI em hardware por padrão
- sobe `start-virgl` automaticamente quando o modo de hardware é solicitado e o servidor ainda não está ativo
- aceita `--renderer hardware|software|virgl`, com `software` apenas como fallback explícito

### Variáveis e integração corretas

- `DISPLAY=:1` identifica o display X11 do host Termux; isso é env de sessão, não env de driver gráfico.
- `XDG_RUNTIME_DIR` define o diretório de runtime/sockets da sessão; isso é essencial para `dbus`, X11 e integração entre host e clientes.
- `GALLIUM_DRIVER=virpipe` é a env específica do driver 3D e deve ser tratada separadamente das envs de sessão.
- `TERMUX_X11_WM=xfwm4|openbox` escolhe apenas o window manager do XFCE; não muda o desktop nem substitui a pilha 3D.
- `proot-distro login --shared-tmp ...` é o caminho suportado para clientes GUI Debian porque mantém o compartilhamento de temporários/sockets com o host Termux:X11.

## Fluxo de reinstalação limpa

Quando o objetivo for remover a stack Termux atual, trocar a origem dos APKs com segurança e reinstalar tudo do zero, usar o fluxo abaixo.

1. No host, executar:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh
```

2. O script host-side vai:

- consultar as releases oficiais atuais de `termux/termux-app`, `termux/termux-api` e `termux/termux-x11`
- baixar os APKs ARM64 compatíveis
- limpar os resíduos controlados do projeto antes da reinstalação:
  - pacotes `com.termux`, `com.termux.api` e `com.termux.x11` no `user 0`
  - resíduos conhecidos em `/sdcard/Download`
  - payloads e artefatos controlados em `/data/local/tmp`
  - processos órfãos do ecossistema Termux/X11/GUI, com reboot do dispositivo quando o Android não permitir encerramento limpo por ADB
- desinstalar `com.termux`, `com.termux.api` e `com.termux.x11`
- reinstalar os três apps Android a partir da mesma origem oficial
- validar que a limpeza prévia realmente removeu os resíduos controlados antes de prosseguir
- reenviar o payload principal e o bootstrap fino para `/data/local/tmp`
- abrir o app `Termux:API` recém-instalado
- abrir o app `Termux` recém-instalado
- esperar o shell real do app Termux ficar pronto
- executar automaticamente:

```bash
bash /data/local/tmp/install_termux_repo_bootstrap.sh
```

3. O bootstrap fino valida o contexto do app Termux e delega para:

```bash
bash /data/local/tmp/install_termux_stack.sh
```

4. Após o payload terminar, reiniciar Termux e Termux:X11 antes das validações do baseline.

## Regra de origem dos APKs

- `com.termux`, `com.termux.api` e `com.termux.x11` devem vir da mesma origem para evitar conflito de assinatura e `sharedUserId`
- não misturar F-Droid, GitHub e Google Play no mesmo conjunto de apps Termux
- ao trocar de fonte, desinstalar toda a família Termux antes de reinstalar
- neste projeto, o fluxo de reinstalação limpa passa a usar GitHub oficial do owner `termux` como fonte única

## Fluxo atual

1. Instalar manualmente os apps Android obrigatórios no dispositivo.
2. Rodar `Install/adb_provision.sh` no host.

```bash
bash ~/Documentos/AI/TermuxAiLocal/Install/adb_provision.sh
```
3. O script transfere o payload e abre o app Termux.
4. Executar manualmente no app Termux:

```bash
bash /data/local/tmp/install_termux_stack.sh
```

5. Após instalação, atualização ou mudanças relevantes, reiniciar Termux e Termux:X11.
5.1. Antes de qualquer fluxo novo, e sempre que um fluxo falhar, resetar completamente o ecossistema Termux:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux
```

5.1.1. O reset host-side agora restaura automaticamente o layout obrigatório do projeto em desktop mode livre:

- `Termux` no topo esquerdo
- `Termux:X11` à direita
- cliente SSH embaixo à esquerda
- `Termux:API` fora do desktop visível

5.2. Antes de digitar qualquer novo comando via ADB, confirmar qual app está focado:

```bash
adb -s "$DEVICE_ID" shell dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' | tail -6
```

5.3. Antes de testes longos com muitos subprocessos, aplicar o override recomendado para `phantom process killing`:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_configure_phantom_processes.sh --apply
```

## Fluxo Debian Trixie + Apps GUI

1. No host, preparar e enviar os payloads Debian GUI:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Debian/adb_provision_debian_trixie_gui.sh
```

2. O script host-side vai resetar o ecossistema Termux, reenviar os payloads Debian GUI para `/data/local/tmp/` e abrir o app Termux.

3. No app Termux, executar o payload principal:

```bash
bash /data/local/tmp/install_debian_trixie_gui.sh
```

Ou, diretamente do host com sincronização real:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Debian/adb_install_debian_trixie_gui.sh
```

4. Depois da instalação do Debian Trixie e do usuário escolhido, garantir uma sessão gráfica ativa em `:1`.

No host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh xfce
```

Ou no próprio Termux:

```bash
start-xfce-x11
```

5. Lançar qualquer app GUI em hardware por padrão.

No Termux:

```bash
run-gui-debian -- xterm
```

Para utilitários OpenGL/EGL:

```bash
run-gui-debian -- es2_info
run-gui-debian -- glmark2
run-gui-debian -- xterm -hold -e fastfetch
```

6. Para fallback manual em software, usar explicitamente esse renderer:

No Termux:

```bash
run-gui-debian --renderer software -- xterm
```

7. Para manter um launcher explícito de hardware com nome semântico, o alias `virgl` continua aceito:

No Termux:

```bash
run-gui-debian --renderer virgl -- glmark2
```

Observações importantes do fluxo Debian:

- o padrão do projeto agora é `hardware`, validado neste tablet com `virgl_test_server_android` ativo e renderer `virgl`
- `run-gui-debian -- comando [args...]` é o launcher oficial para qualquer app GUI do Debian, preservando `DISPLAY`, `--shared-tmp` e `GALLIUM_DRIVER=virpipe` no modo `hardware`
- a validação baseline do projeto continua sendo a stack Termux/X11/Openbox ou XFCE já existente; o Debian GUI é uma camada adicional, não substituta

6. Para validar o baseline de forma reproduzível a partir do host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh
```

6.1. Para validar explicitamente o perfil leve estável:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-stable
```

6.2. Para validar explicitamente o perfil funcional:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=xfce
```

7. Para incluir também a trilha gráfica segura via `virgl` + EGL/GLES:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --with-gpu
```

8. Para persistir artefatos da validação no host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --with-gpu --report
```

9. Para validar baseline com permanência controlada da sessão:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=xfce --with-gpu --report --stress-seconds=30
```

10. Para enviar um comando ao X11 `:1` a partir do host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh xterm
```

11. Para executar um comando dentro de uma nova janela `xterm` no X11:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --xterm xterm
```

12. Para executar um script local no contexto X11 de forma robusta:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --xterm --script /caminho/no/host/meu-teste-x11.sh
```

12.1. Para lançar um app no X11 já exigindo virgl:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --with-virgl glmark2
```

12.2. Para rodar o benchmark pelo helper dedicado:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --with-virgl run-glmark2-x11
```

13. Para iniciar o desktop XFCE no display `:1`:

```bash
start-xfce-x11
```

13.1. Para iniciar o desktop a partir do host já validando virgl/EGL:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu xfce
```

14. Para encerrar a sessão XFCE de forma limpa:

```bash
stop-xfce-x11
```

15. Para aplicar a resolução recomendada de performance no próprio Termux:

```bash
set-x11-resolution performance
```

16. Para aplicar uma resolução balanceada:

```bash
set-x11-resolution balanced
```

17. Para voltar ao modo nativo:

```bash
set-x11-resolution native
```

18. Para aplicar a resolução a partir do host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_set_x11_resolution.sh performance
```

## Observação de arquitetura

O projeto não assume, nesta v1, que `adb shell` consiga reproduzir o mesmo contexto do app Termux. Por isso o payload continua manual no app, mesmo com ADB cuidando da orquestração no host.

## Runbook ADB para 3D e performance

### Estado atual auditado no dispositivo

- fabricante: `samsung`
- modelo: `SM-X736B`
- Android: `16`
- stack gráfica exposta: `mali`, plataforma `mt6991`
- refresh configurado: `min_refresh_rate=120`, `peak_refresh_rate=120`, `refresh_rate_mode=1`
- modo de economia de energia: `low_power=0`
- animações do sistema: `window_animation_scale=0`, `transition_animation_scale=0`, `animator_duration_scale=0`
- `zram_enabled=1`
- pacotes Samsung relevantes presentes: `com.samsung.gamedriver.mt6991`, `com.samsung.android.game.gos`, `com.samsung.android.game.gamehome`, `com.samsung.android.game.gametools`, `com.samsung.gpuwatchapp`

### Ajustes seguros já aplicados por ADB

- whitelist de idle para `com.termux`
- whitelist de idle para `com.termux.api`
- whitelist de idle para `com.termux.x11`

- `stay_on_while_plugged_in=3` para manter a tela ativa enquanto o dispositivo estiver alimentado por USB/AC

Comandos correspondentes:

```bash
adb -s "$DEVICE_ID" shell dumpsys deviceidle whitelist +com.termux
adb -s "$DEVICE_ID" shell dumpsys deviceidle whitelist +com.termux.api
adb -s "$DEVICE_ID" shell dumpsys deviceidle whitelist +com.termux.x11
adb -s "$DEVICE_ID" shell settings put global stay_on_while_plugged_in 3
```

### Auditoria ADB recomendada

Usar esta sequência para analisar o estado do dispositivo antes de tentar tuning adicional:

```bash
adb -s "$DEVICE_ID" devices -l
adb -s "$DEVICE_ID" shell pm list users 2>&1
adb -s "$DEVICE_ID" shell getprop ro.product.manufacturer
adb -s "$DEVICE_ID" shell getprop ro.product.model
adb -s "$DEVICE_ID" shell getprop ro.build.version.release
adb -s "$DEVICE_ID" shell getprop ro.hardware.egl
adb -s "$DEVICE_ID" shell getprop ro.board.platform
adb -s "$DEVICE_ID" shell settings get global low_power
adb -s "$DEVICE_ID" shell settings get global animator_duration_scale
adb -s "$DEVICE_ID" shell settings get global transition_animation_scale
adb -s "$DEVICE_ID" shell settings get global window_animation_scale
adb -s "$DEVICE_ID" shell settings list system | grep -E 'peak_refresh_rate|min_refresh_rate|screen_brightness_mode'
adb -s "$DEVICE_ID" shell settings list secure | grep -E 'refresh_rate_mode|game|performance'
adb -s "$DEVICE_ID" shell cmd package list features | grep -Ei 'vulkan|opengl|gles'
adb -s "$DEVICE_ID" shell dumpsys deviceidle whitelist | grep -E 'com.termux|com.termux.api|com.termux.x11'
adb -s "$DEVICE_ID" shell pm path com.samsung.gamedriver.mt6991
```

### O que ADB pode configurar com segurança para este projeto

- garantir `USB debugging` e `adb` funcionais
- fixar a auditoria de pacotes Android com `pm list packages --user 0`
- manter tela ativa durante sessões longas quando ligado à energia
- reduzir custo visual do sistema com animações em `0`
- colocar `com.termux`, `com.termux.api` e `com.termux.x11` na whitelist de idle
- verificar se o dispositivo está em 120 Hz e sem `low_power`

### O que não deve ser forçado por ADB neste projeto

- `cmd game mode` para `com.termux` ou `com.termux.x11`: esses apps não são do tipo `game`, então o framework rejeita o comando
- desativar `GOS` (`com.samsung.android.game.gos`) ou o driver Samsung do sistema: isso foge do suporte normal do Android, pode regredir estabilidade térmica e não é requisito do fluxo Termux
- forçar `4x MSAA`, `Disable HW overlays` ou `Force GPU rendering` como tuning permanente: essas opções são pensadas para depuração/UI Android e não são o caminho principal do Termux:X11 com `virglrenderer-android`
- tentar selecionar manualmente driver ANGLE/Game Driver para apps Termux via shell sem evidência clara de suporte do framework

### Ajustes manuais Samsung recomendados

Esses pontos não são confiáveis por ADB genérico e devem ser conferidos manualmente no tablet:

1. Manter a taxa de atualização em 120 Hz ou modo equivalente de alta fluidez.
2. Confirmar que o modo de economia de energia está desligado.
3. Definir bateria como irrestrita para `Termux`, `Termux:API` e `Termux:X11`, se a One UI expuser essa opção separadamente da whitelist do `deviceidle`.
4. Se houver `RAM Plus`, testar em valor mínimo ou desligado para reduzir pressão de swap em sessões gráficas longas.
5. Não usar `Game Booster` como estratégia principal para Termux, porque o framework de game mode não reconhece `com.termux` como app de jogo.

### Interpretação correta para 3D no Termux

- 120 Hz, tela ativa e apps fora do idle ajudam responsividade e evitam suspensão agressiva.
- isso não garante aceleração 3D total dentro do Termux:X11 por si só.
- no `SM-X736B` testado, a trilha `GLX` com `virpipe` continua instável: `glxinfo -B` pode falhar com `SIGSEGV` e `glxgears` pode falhar em `glXCreateContext`.
- no mesmo dispositivo, a trilha `EGL/GLES` com `virpipe` funciona e expõe renderer acelerado real, inclusive com `GL_RENDERER: virgl (Mali-G925-Immortalis MC12)` no modo plain e `GL_RENDERER: virgl (ANGLE (... Vulkan ...))` no modo `ANGLE Vulkan`.
- a regressão observada para `GL_RENDERER: virgl (LLVMPIPE ...)` vinha do launcher antigo de `start-virgl`, que acrescentava `$PREFIX/lib` ao `LD_LIBRARY_PATH` do servidor e fazia o host `virgl` puxar o `libEGL/libGLES` do Mesa do Termux; a versão consolidada usa apenas o diretório privado do `virglrenderer-android`
- o default operacional do projeto passa a ser `start-virgl` em modo `plain`, porque esse perfil é a base agressiva de performance 3D adotada agora para o tablet; `vulkan` continua disponível como modo alternativo para comparação.
- se `check-gpu-termux` cair para `llvmpipe`, o problema já não é mais de configuração básica do Android ou de ADB: passa a ser do caminho gráfico no ambiente Termux.

### Resultado prático validado

- para iniciar o servidor 3D no modo recomendado: `start-virgl`
- para forçar um modo específico: `start-virgl plain`, `start-virgl gl` ou `start-virgl vulkan`
- para reiniciar apenas o servidor 3D: `stop-virgl`
- para validar a trilha acelerada correta neste tablet: `check-gpu-termux`
- para subir o desktop diário já no perfil agressivo: `start-openbox` ou `start-openbox-maxperf`
- para deixar a sessão Openbox aberta de forma persistente, use `start-openbox` ou `start-openbox-maxperf`; a validação host-side sobe e encerra a sessão no final por desenho, então não deve ser usada quando o objetivo é “deixar o desktop aberto”
- para subir o desktop mais leve no perfil agressivo: `start-openbox-maxperf`
- para subir o desktop mais leve no perfil de compatibilidade: `start-openbox-compat`
- para subir o desktop mais leve no perfil Vulkan experimental: `start-openbox-vulkan-exp`
- para encerrar a sessão leve de forma limpa: `stop-openbox-x11`
- para subir um desktop mais completo e funcional com foco em performance 3D: `start-xfce-x11`
- para subir o mesmo desktop sem ocupar a shell foreground do Termux: `start-xfce-x11-detached`
- para manter XFCE, mas trocar só o WM para Openbox: `start-xfce-x11 --wm openbox`
- para aplicar o perfil agressivo completo direto no Termux: `start-maxperf-x11` ou `start-maxperf-x11 xfce`
- para encerrar a sessão XFCE: `stop-xfce-x11`
- para aplicar a melhor resolução de performance neste tablet: `set-x11-resolution performance` (`1280x720`)
- para aplicar uma resolução intermediária: `set-x11-resolution balanced`
- para restaurar a resolução nativa: `set-x11-resolution native`
- para aplicar a resolução a partir do host: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_set_x11_resolution.sh performance`
- para validar esse baseline a partir do host sem repetir a coleta manual: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh`
- para validar explicitamente o perfil Openbox diário: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf`
- para validar explicitamente o perfil Openbox estável: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-stable`
- para validar explicitamente o perfil XFCE: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=xfce`
- para validar explicitamente o perfil XFCE com Openbox como WM: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=xfce --wm=openbox`
- para validar o baseline incluindo o caminho gráfico seguro: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --with-gpu`
- para salvar resumo e dumps XML da validação: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --with-gpu --report`
- para segurar a sessão X11 por um intervalo curto e testar estabilidade: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=xfce --with-gpu --report --stress-seconds=30`
- para executar um app diretamente no display `:1`: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh xterm`
- para abrir um app em uma nova janela terminal do X11: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --xterm xterm`
- para executar um script local no X11 sem depender de quoting do teclado Android: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --xterm --script /caminho/no/host/meu-teste-x11.sh`
- para executar um app no X11 exigindo virgl e `GALLIUM_DRIVER=virpipe`: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --with-virgl glmark2`
- para rodar o benchmark 3D pelo helper dedicado: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh --with-virgl run-glmark2-x11`
- para subir o XFCE já com validação do renderer acelerado: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu xfce`
- para subir o XFCE já com Openbox como WM e validação do renderer acelerado: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --wm openbox xfce`
- para subir o perfil agressivo completo a partir do host: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --maxperf openbox`
- para manter XFCE, mas no perfil agressivo do host: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --maxperf xfce`
- neste hardware, trate `es2_info` e `es2gears_x11` como evidência principal de aceleração; não use `glxinfo` sozinho como verdade absoluta sobre o estado do `virgl`
- `glmark2` onscreen e `glmark2-es2 --off-screen` não são comparáveis diretamente; o score onscreen sofre com resolução, composição e custo do desktop, enquanto `--off-screen` isola melhor o renderer bruto
- medição recente no perfil final `XFCE + Openbox` com `glmark2-es2 --off-screen` em `plain`: `glmark2 Score: 502`
- tentativa equivalente em `vulkan` continuou exibindo avisos de `DRI3` e `ZINK`, sem evidência concreta de ganho sobre `plain`; por isso o default do projeto permanece em `plain`
- para este tablet, a recomendação prática passa a ser: `Openbox` puro como baseline leve e persistente, `openbox-maxperf` como perfil agressivo, e `XFCE --wm openbox` apenas quando você quiser uma sessão mais completa sem abandonar a trilha gráfica já validada
- para ganho de performance, a base agressiva deste build é `1280x720`: não mantém `16:10`, mas é aceita pelo `termux-x11-preference` e reduz fortemente a carga de renderização

### Regra operacional

Use ADB para:

- auditar dispositivo
- aplicar ajustes de energia e sessão seguros
- abrir apps e mover payloads

Não use ADB para concluir que a aceleração 3D está correta sem evidência real de dentro do app Termux.
