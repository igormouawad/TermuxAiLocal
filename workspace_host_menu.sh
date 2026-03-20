#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR"
DEVICE_ID=""

# shellcheck source=lib/termux_common.sh
source "${WORKSPACE_ROOT}/lib/termux_common.sh"

declare -a ACTION_IDS=()
declare -a ACTION_CATEGORIES=()
declare -a ACTION_LABELS=()
declare -a ACTION_PREVIEWS=()
declare -a ACTION_HANDLERS=()
declare -a ACTION_CONFIRM=()
declare -a ACTION_NOTES=()

usage() {
  cat <<EOF
Uso:
  bash ${WORKSPACE_ROOT}/workspace_host_menu.sh
  bash ${WORKSPACE_ROOT}/workspace_host_menu.sh --list
  bash ${WORKSPACE_ROOT}/workspace_host_menu.sh --run ACTION_ID [--yes]

Modos:
  --list        Lista os itens do menu com os comandos associados.
  --run ID      Executa um item diretamente pelo ACTION_ID ou numero.
  --yes         Pula a confirmacao interativa para --run.

Selecao de device:
  - por padrao, o menu prefere um unico alvo ADB USB em estado device
  - sem USB, o menu tenta recuperar automaticamente um unico alvo ADB por Wi‑Fi
  - com multiplos devices, exporte TERMUXAI_DEVICE_ID=SERIAL antes de executar
EOF
}

add_action() {
  ACTION_IDS+=("$1")
  ACTION_CATEGORIES+=("$2")
  ACTION_LABELS+=("$3")
  ACTION_PREVIEWS+=("$4")
  ACTION_HANDLERS+=("$5")
  ACTION_CONFIRM+=("$6")
  ACTION_NOTES+=("$7")
}

resolve_device_id() {
  if [[ -n "$DEVICE_ID" ]]; then
    printf '%s\n' "$DEVICE_ID"
    return 0
  fi

  DEVICE_ID="$(termux::resolve_target_device)"
  printf '%s\n' "$DEVICE_ID"
}

run_workspace_script() {
  local relative_path="$1"
  shift
  bash "${WORKSPACE_ROOT}/${relative_path}" "$@"
}

run_termux_device_command() {
  local device_id

  device_id="$(resolve_device_id)"
  run_workspace_script "ADB/adb_termux_send_command.sh" --device "$device_id" "$@"
}

deploy_termux_menu_to_device() {
  local device_id
  local target="/data/local/tmp/termux_workspace_menu.sh"

  device_id="$(resolve_device_id)"

  termux::adb_run \
    "$device_id" \
    'O deploy do menu Termux falhou ao transferir o arquivo para o dispositivo.' \
    'Verificar a conectividade ADB e tentar novamente.' \
    push \
    "${WORKSPACE_ROOT}/Install/termux_workspace_menu.sh" \
    "$target" >/dev/null

  termux::adb_run \
    "$device_id" \
    'O deploy do menu Termux falhou ao marcar o payload como executavel.' \
    'Verificar o filesystem temporario do dispositivo e tentar novamente.' \
    shell \
    chmod \
    755 \
    "$target" >/dev/null

  run_workspace_script \
    "ADB/adb_termux_send_command.sh" \
    --device "$device_id" \
    -- \
    "mkdir -p \"\$HOME/bin\" && install -m 755 \"$target\" \"\$HOME/bin/termux-workspace-menu\" && command -v \"\$HOME/bin/termux-workspace-menu\""
}

handler_smoke_openbox() {
  run_workspace_script "ADB/adb_reset_termux_stack.sh" --focus termux
  run_workspace_script "ADB/adb_start_desktop.sh" --with-gpu --profile openbox-maxperf openbox
  run_workspace_script "ADB/adb_validate_baseline.sh" --desktop=openbox --profile=openbox-maxperf --with-gpu --report
}

handler_daily_flow() {
  run_workspace_script "ADB/adb_reset_termux_stack.sh" --focus termux
  run_workspace_script "ADB/adb_start_desktop.sh" --with-gpu --profile openbox-maxperf openbox
  run_workspace_script "ADB/adb_validate_baseline.sh" --desktop=openbox --profile=openbox-maxperf --with-gpu --report
  run_termux_device_command -- 'termux-stack-status --brief'
  run_workspace_script "ADB/adb_start_desktop.sh" --with-gpu --profile openbox-maxperf openbox
  run_workspace_script "ADB/adb_run_x11_command.sh" aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'
  run_termux_device_command --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'
}

handler_reset_focus() {
  run_workspace_script "ADB/adb_reset_termux_stack.sh" --focus "$1"
}

handler_start_desktop_profile() {
  run_workspace_script "ADB/adb_start_desktop.sh" --with-gpu --profile openbox-maxperf "$1"
}

handler_validate_desktop_profile() {
  run_workspace_script "ADB/adb_validate_baseline.sh" --desktop="$1" --profile=openbox-maxperf --with-gpu --report
}

handler_resolution_profile() {
  run_workspace_script "ADB/adb_set_x11_resolution.sh" "$1"
}

handler_reset_termux() {
  handler_reset_focus termux
}

handler_reset_x11() {
  handler_reset_focus x11
}

handler_start_openbox() {
  handler_start_desktop_profile openbox
}

handler_consolidate_freeform_desktop() {
  run_workspace_script "ADB/adb_consolidate_freeform_desktop.sh" --focus ssh
}

handler_restart_freeform_desktop() {
  run_workspace_script "ADB/adb_consolidate_freeform_desktop.sh" --restart --focus ssh
}

handler_open_settings_desktop() {
  run_workspace_script "ADB/adb_open_desktop_app.sh" --package com.android.settings
}

handler_desktop_mode_status() {
  run_workspace_script "ADB/adb_desktop_mode.sh" status
}

handler_desktop_mode_on() {
  run_workspace_script "ADB/adb_desktop_mode.sh" on
}

handler_desktop_mode_off() {
  run_workspace_script "ADB/adb_desktop_mode.sh" off
}

handler_adb_wifi_status() {
  run_workspace_script "ADB/adb_wifi_debug.sh" status
}

handler_adb_wifi_connect() {
  run_workspace_script "ADB/adb_wifi_debug.sh" connect
}

handler_adb_wifi_disable() {
  run_workspace_script "ADB/adb_wifi_debug.sh" disable
}

handler_adb_wifi_tcpip() {
  run_workspace_script "ADB/adb_wifi_debug.sh" tcpip
}

handler_start_xfce() {
  handler_start_desktop_profile xfce
}

handler_validate_openbox() {
  handler_validate_desktop_profile openbox
}

handler_validate_xfce() {
  handler_validate_desktop_profile xfce
}

handler_stack_status() {
  run_termux_device_command -- 'termux-stack-status --brief'
}

handler_x11_demo() {
  run_workspace_script "ADB/adb_run_x11_command.sh" aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'
}

handler_debian_xeyes() {
  run_termux_device_command --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'
}

handler_resolution_show() {
  handler_resolution_profile show
}

handler_resolution_balanced() {
  handler_resolution_profile balanced
}

handler_resolution_performance() {
  handler_resolution_profile performance
}

handler_phantom_config() {
  run_workspace_script "ADB/adb_configure_phantom_processes.sh"
}

handler_provision_termux() {
  run_workspace_script "Install/adb_provision.sh"
}

handler_reinstall_termux() {
  run_workspace_script "Install/adb_reinstall_termux_official.sh"
}

handler_debian_provision() {
  run_workspace_script "Debian/adb_provision_debian_trixie_gui.sh"
}

handler_debian_install() {
  run_workspace_script "Debian/adb_install_debian_trixie_gui.sh"
}

handler_patch_check() {
  run_workspace_script "Install/apply_continue_extension_patch.sh" --check
}

handler_patch_apply() {
  run_workspace_script "Install/apply_continue_extension_patch.sh"
}

handler_deploy_termux_menu() {
  deploy_termux_menu_to_device
}

register_actions() {
  add_action \
    "smoke_openbox" \
    "Fluxos canonicos" \
    "Smoke test canonico do Openbox" \
    $'bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux\nbash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox\nbash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report' \
    "handler_smoke_openbox" \
    "1" \
    "Fluxo curto e reprodutivel para validar reset, desktop e baseline."

  add_action \
    "daily_flow" \
    "Fluxos canonicos" \
    "Fluxo diario limpo completo" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'" \
    "handler_daily_flow" \
    "1" \
    "Fluxo canonicamente completo do workspace em 7 passos."

  add_action \
    "reset_termux" \
    "ADB / Termux" \
    "Resetar ecossistema com foco final no Termux" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux" \
    "handler_reset_termux" \
    "1" \
    "Reconstrói o desktop livre aprovado e limpa residuos controlados."

  add_action \
    "reset_x11" \
    "ADB / Termux" \
    "Resetar ecossistema com foco final no Termux:X11" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus x11" \
    "handler_reset_x11" \
    "1" \
    "Mesmo reset canônico, mas deixando o foco final no Termux:X11 dentro do desktop livre."

  add_action \
    "start_openbox" \
    "ADB / Termux" \
    "Subir desktop Openbox validado" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox" \
    "handler_start_openbox" \
    "1" \
    "Sobe o desktop diario com VirGL e DISPLAY=:1."

  add_action \
    "freeform_consolidate" \
    "ADB / Termux" \
    "Consolidar desktop livre aprovado" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_consolidate_freeform_desktop.sh --focus ssh" \
    "handler_consolidate_freeform_desktop" \
    "0" \
    "Aplica o layout aprovado: Termux no topo esquerdo, Terminus embaixo e Termux:X11 à direita."

  add_action \
    "freeform_restart" \
    "ADB / Termux" \
    "Fechar e reconstruir desktop livre aprovado" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_consolidate_freeform_desktop.sh --restart --focus ssh" \
    "handler_restart_freeform_desktop" \
    "1" \
    "Reconstrói o layout livre aprovado; use com cautela porque o cliente SSH Android pode não retomar a sessão sozinho."

  add_action \
    "desktop_open_settings" \
    "ADB / Termux" \
    "Abrir Configurações no desktop" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_open_desktop_app.sh --package com.android.settings" \
    "handler_open_settings_desktop" \
    "0" \
    "Exemplo canônico de app Android aberto em desktop mode com layout de foco grande."

  add_action \
    "desktop_mode_status" \
    "ADB / Termux" \
    "Inspecionar o desktop mode Samsung" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh status" \
    "handler_desktop_mode_status" \
    "0" \
    "Lê o estado real do wm shell desktopmode dump, desk ativo e foco atual."

  add_action \
    "desktop_mode_on" \
    "ADB / Termux" \
    "Ligar desktop mode Samsung" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh on" \
    "handler_desktop_mode_on" \
    "0" \
    "Ativa o desktop mode no display padrão de forma idempotente."

  add_action \
    "desktop_mode_off" \
    "ADB / Termux" \
    "Desligar desktop mode Samsung" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh off" \
    "handler_desktop_mode_off" \
    "0" \
    "Sai do desktop mode e volta para o launcher/tablet mode."

  add_action \
    "adb_wifi_status" \
    "ADB / Termux" \
    "Inspecionar o estado do ADB por Wi‑Fi via USB" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_wifi_debug.sh status" \
    "handler_adb_wifi_status" \
    "0" \
    "Lê adb_wifi_enabled, IP Wi‑Fi, alvos de rede atuais e mDNS usando USB como transporte de controle."

  add_action \
    "adb_wifi_connect" \
    "ADB / Termux" \
    "Ligar e conectar o ADB por Wi‑Fi via USB" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_wifi_debug.sh connect" \
    "handler_adb_wifi_connect" \
    "0" \
    "Ativa adb_wifi_enabled, descobre a porta de connect e deixa USB + Wi‑Fi ativos ao mesmo tempo."

  add_action \
    "adb_wifi_disable" \
    "ADB / Termux" \
    "Desligar o ADB por Wi‑Fi via USB" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_wifi_debug.sh disable" \
    "handler_adb_wifi_disable" \
    "0" \
    "Desconecta alvos de rede e volta adb_wifi_enabled para 0."

  add_action \
    "adb_wifi_tcpip" \
    "ADB / Termux" \
    "Ativar o modo adb tcpip 5555 via USB" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_wifi_debug.sh tcpip" \
    "handler_adb_wifi_tcpip" \
    "0" \
    "Usa a alternativa oficial adb tcpip 5555 mantendo o USB como controle."

  add_action \
    "start_xfce" \
    "ADB / Termux" \
    "Subir desktop XFCE validado" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf xfce" \
    "handler_start_xfce" \
    "1" \
    "Mantem o mesmo perfil base, mas sobe XFCE."

  add_action \
    "validate_openbox" \
    "ADB / Termux" \
    "Validar baseline Openbox com relatorio" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report" \
    "handler_validate_openbox" \
    "1" \
    "Executa a validacao autoritativa e grava artefatos em ADB/reports."

  add_action \
    "validate_xfce" \
    "ADB / Termux" \
    "Validar baseline XFCE com relatorio" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=xfce --profile=openbox-maxperf --with-gpu --report" \
    "handler_validate_xfce" \
    "1" \
    "Executa a validacao autoritativa do XFCE."

  add_action \
    "stack_status" \
    "ADB / Termux" \
    "Ler termux-stack-status --brief" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'" \
    "handler_stack_status" \
    "0" \
    "Probe rapido do estado atual do stack no shell real do Termux."

  add_action \
    "x11_demo" \
    "ADB / Termux" \
    "Abrir um aterm leve no X11" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'" \
    "handler_x11_demo" \
    "0" \
    "Teste leve de lancamento no display :1."

  add_action \
    "debian_xeyes" \
    "ADB / Termux" \
    "Abrir xeyes no Debian via run-gui-debian" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'" \
    "handler_debian_xeyes" \
    "0" \
    "Teste rapido do launcher Debian GUI ja provisionado."

  add_action \
    "resolution_show" \
    "ADB / Termux" \
    "Mostrar resolucao atual do Termux:X11" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_set_x11_resolution.sh show" \
    "handler_resolution_show" \
    "0" \
    "Le as preferencias reais do Termux:X11."

  add_action \
    "resolution_balanced" \
    "ADB / Termux" \
    "Aplicar perfil de resolucao balanced" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_set_x11_resolution.sh balanced" \
    "handler_resolution_balanced" \
    "1" \
    "Reaplica a resolucao diaria cheia."

  add_action \
    "resolution_performance" \
    "ADB / Termux" \
    "Aplicar perfil de resolucao performance" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_set_x11_resolution.sh performance" \
    "handler_resolution_performance" \
    "1" \
    "Reaplica 1280x720 para reduzir fill-rate."

  add_action \
    "phantom_processes" \
    "ADB / Termux" \
    "Aplicar override de phantom processes" \
    "bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_configure_phantom_processes.sh" \
    "handler_phantom_config" \
    "1" \
    "Aplica o override recomendado para reduzir limitacao agressiva do Android."

  add_action \
    "provision_termux" \
    "Instalacao e payloads" \
    "Enviar payload principal e bootstrap para o dispositivo" \
    "bash ~/Documentos/AI/TermuxAiLocal/Install/adb_provision.sh" \
    "handler_provision_termux" \
    "1" \
    "Prepara o device e para no bootstrap manual dentro do app Termux."

  add_action \
    "reinstall_termux" \
    "Instalacao e payloads" \
    "Reinstalacao limpa completa dos 3 APKs Termux" \
    "bash ~/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh" \
    "handler_reinstall_termux" \
    "1" \
    "Fluxo canonico de reinstall com bootstrap automatico apos abrir Termux:API e Termux."

  add_action \
    "debian_provision" \
    "Instalacao e payloads" \
    "Provisionar payloads Debian GUI no device" \
    "bash ~/Documentos/AI/TermuxAiLocal/Debian/adb_provision_debian_trixie_gui.sh" \
    "handler_debian_provision" \
    "1" \
    "Envia payloads Debian GUI e imprime o fluxo host-side/manual correspondente."

  add_action \
    "debian_install" \
    "Instalacao e payloads" \
    "Instalar Debian GUI a partir do host" \
    "bash ~/Documentos/AI/TermuxAiLocal/Debian/adb_install_debian_trixie_gui.sh" \
    "handler_debian_install" \
    "1" \
    "Executa a instalacao Debian no shell real do Termux."

  add_action \
    "continue_patch_check" \
    "Continue / VS Code" \
    "Verificar patch local do Continue" \
    "bash ~/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh --check" \
    "handler_patch_check" \
    "0" \
    "Confere se o patch estrutural do Continue segue ativo."

  add_action \
    "continue_patch_apply" \
    "Continue / VS Code" \
    "Aplicar ou reaplicar patch local do Continue" \
    "bash ~/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh" \
    "handler_patch_apply" \
    "1" \
    "Reaplica o patch do Continue apos update ou reinstall da extensao."

  add_action \
    "deploy_termux_menu" \
    "Continue / VS Code" \
    "Copiar o menu do Termux para o dispositivo atual" \
    "adb push ~/Documentos/AI/TermuxAiLocal/Install/termux_workspace_menu.sh /data/local/tmp/termux_workspace_menu.sh
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'mkdir -p \"\$HOME/bin\" && install -m 755 /data/local/tmp/termux_workspace_menu.sh \"\$HOME/bin/termux-workspace-menu\"'" \
    "handler_deploy_termux_menu" \
    "0" \
    "Instala ou atualiza o helper termux-workspace-menu no Termux atual."
}

print_action_entry() {
  local index="$1"
  printf '%2d) %-22s %s\n' "$((index + 1))" "${ACTION_IDS[$index]}" "${ACTION_LABELS[$index]}"
}

print_actions() {
  local last_category=""
  local i

  for i in "${!ACTION_IDS[@]}"; do
    if [[ "${ACTION_CATEGORIES[$i]}" != "$last_category" ]]; then
      printf '\n[%s]\n' "${ACTION_CATEGORIES[$i]}"
      last_category="${ACTION_CATEGORIES[$i]}"
    fi
    print_action_entry "$i"
  done
}

print_action_details() {
  local index="$1"

  printf 'ID: %s\n' "${ACTION_IDS[$index]}"
  printf 'Categoria: %s\n' "${ACTION_CATEGORIES[$index]}"
  printf 'Descricao: %s\n' "${ACTION_LABELS[$index]}"
  if [[ -n "${ACTION_NOTES[$index]}" ]]; then
    printf 'Nota: %s\n' "${ACTION_NOTES[$index]}"
  fi
  printf 'Comando(s):\n%s\n' "${ACTION_PREVIEWS[$index]}"
}

list_actions_verbose() {
  local last_category=""
  local i

  for i in "${!ACTION_IDS[@]}"; do
    if [[ "${ACTION_CATEGORIES[$i]}" != "$last_category" ]]; then
      printf '\n[%s]\n' "${ACTION_CATEGORIES[$i]}"
      last_category="${ACTION_CATEGORIES[$i]}"
    fi
    printf '%s\n' "ID=${ACTION_IDS[$i]}"
    printf 'LABEL=%s\n' "${ACTION_LABELS[$i]}"
    printf 'COMMANDS:\n%s\n' "${ACTION_PREVIEWS[$i]}"
    if [[ -n "${ACTION_NOTES[$i]}" ]]; then
      printf 'NOTE=%s\n' "${ACTION_NOTES[$i]}"
    fi
    printf -- '---\n'
  done
}

resolve_action_index() {
  local token="$1"
  local i

  if [[ "$token" =~ ^[0-9]+$ ]]; then
    if (( token >= 1 && token <= ${#ACTION_IDS[@]} )); then
      printf '%s\n' "$((token - 1))"
      return 0
    fi
    return 1
  fi

  for i in "${!ACTION_IDS[@]}"; do
    if [[ "${ACTION_IDS[$i]}" == "$token" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done

  return 1
}

confirm_execution() {
  local index="$1"
  local answer

  if [[ "${ACTION_CONFIRM[$index]}" != "1" ]]; then
    return 0
  fi

  read -r -p "Executar este item? [s/N] " answer
  case "${answer:-}" in
    s|S|y|Y|yes|YES)
      return 0
      ;;
    *)
      printf 'Execucao cancelada.\n'
      return 1
      ;;
  esac
}

run_action_index() {
  local index="$1"
  local handler="${ACTION_HANDLERS[$index]}"
  local status=0
  local audit_owner=0

  termux::audit_session_begin "Menu host: ${ACTION_IDS[$index]}" "$0"
  audit_owner="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
  termux::audit_note 'HOST' "Executando ação ${ACTION_IDS[$index]}: ${ACTION_LABELS[$index]}"

  set +e
  "$handler"
  status=$?
  set -e

  if [ "$audit_owner" -eq 1 ]; then
    termux::audit_session_finish "$status"
  fi

  return "$status"
}

interactive_menu() {
  local selection
  local index

  while :; do
    printf '\n=== Menu do Workspace Host ===\n'
    print_actions
    printf '\nDigite o numero ou ACTION_ID. Use q para sair.\n'
    read -r -p "> " selection

    case "${selection:-}" in
      q|Q|quit|exit)
        return 0
        ;;
      '')
        continue
        ;;
    esac

    if ! index="$(resolve_action_index "$selection")"; then
      printf 'Opcao invalida: %s\n' "$selection" >&2
      continue
    fi

    if ! confirm_execution "$index"; then
      continue
    fi

    printf '\n'
    if ! run_action_index "$index"; then
      printf '\nFalha ao executar %s.\n' "${ACTION_IDS[$index]}" >&2
    else
      printf '\nConcluido: %s\n' "${ACTION_IDS[$index]}"
    fi

    printf '\nPressione Enter para voltar ao menu...'
    read -r _
  done
}

RUN_ID=""
LIST_ONLY=0
AUTO_YES=0

while (($#)); do
  case "$1" in
    --list)
      LIST_ONLY=1
      shift
      ;;
    --run)
      shift
      if (($# == 0)); then
        printf 'Falta valor para --run.\n' >&2
        usage >&2
        exit 64
      fi
      RUN_ID="$1"
      shift
      ;;
    --yes)
      AUTO_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Argumento desconhecido: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

register_actions

if (( LIST_ONLY == 1 )); then
  list_actions_verbose
  exit 0
fi

if [[ -n "$RUN_ID" ]]; then
  if ! action_index="$(resolve_action_index "$RUN_ID")"; then
    printf 'ACTION_ID invalido: %s\n' "$RUN_ID" >&2
    exit 64
  fi

  print_action_details "$action_index"
  printf '\n'

  if (( AUTO_YES == 0 )) && ! confirm_execution "$action_index"; then
    exit 0
  fi

  run_action_index "$action_index"
  exit 0
fi

interactive_menu
