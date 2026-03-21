# Scenario Decision Matrix

## Canonical scenario classes

- `SCENARIO_1_LINUX_USB`
  - host local no workstation Linux
  - target ADB ativo por USB
  - risco de sessão baixo
  - mutações completas permitidas

- `SCENARIO_2_ANDROID_WIFI`
  - operador conectado por SSH a partir do tablet
  - target ADB ativo por Wi‑Fi
  - risco de sessão alto
  - ações que possam desestabilizar o terminal hospedeiro devem ser bloqueadas ou degradadas

- `UNKNOWN_OR_UNSAFE`
  - device ausente
  - transporte ambíguo
  - contexto insuficiente
  - segurança operacional não comprovada

## Action classes

- `inspect_state`
- `desktop_mode_control`
- `desktop_layout_apply`
- `desktop_layout_restart`
- `desktop_app_launch`
- `stack_reset`
- `desktop_stack_start`
- `baseline_validation`
- `x11_resolution_change`
- `x11_runtime_launch`
- `wifi_control_usb`
- `termux_provision`
- `termux_reinstall`
- `debian_provision`
- `debian_install`

## Policy summary

- `SCENARIO_1_LINUX_USB`
  - todas as classes acima são permitidas

- `SCENARIO_2_ANDROID_WIFI`
  - `inspect_state`: `SAFE`
  - `desktop_app_launch`, `desktop_layout_apply`, `x11_runtime_launch`, `x11_resolution_change`: `CAUTION`
  - caminho validado nesta fase:
    - `desktop_app_launch` pode reabrir `Termux`, `Termux:X11` e apps extras no desktop mode
    - o foco final padrão deve voltar ao `Terminus` hospedado em `com.server.auditor.ssh.client/.ssh.terminal.TerminalActivity`
    - o cliente SSH existente deve ser reutilizado em vez de relançado pelo launcher principal
  - `desktop_mode_control`, `desktop_layout_restart`, `stack_reset`, `desktop_stack_start`, `baseline_validation`, `wifi_control_usb`, `termux_provision`, `termux_reinstall`, `debian_provision`, `debian_install`: `UNSAFE_FOR_IN_PROCESS_EXECUTION`

- `UNKNOWN_OR_UNSAFE`
  - somente `inspect_state` é permitido
