#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$SCRIPT_DIR"
PROFILE="${1:-performance}"
CUSTOM_RESOLUTION="${2:-}"
TOTAL_STEPS=2
CURRENT_STEP=0
AUDIT_OWNER=0

finish_audit() {
  local exit_code=$?

  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap finish_audit EXIT

case "$PROFILE" in
  --help|-h)
    printf 'Uso: %s [performance|balanced|native|show|custom LARGURAxALTURA]\n' "$0"
    exit 0
    ;;
esac

fail() {
  termux::fail "$@"
}

step_begin() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  termux::progress_step "$CURRENT_STEP" "$TOTAL_STEPS" 'HOST' "$1"
}

step_ok() {
  termux::progress_result 'OK' "$CURRENT_STEP" "$TOTAL_STEPS" 'HOST' "$1"
}

termux::require_host_command \
  adb \
  'Não é possível ajustar a resolução do Termux:X11 a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_target_device)
termux::audit_session_begin 'Ajuste de resolução do Termux:X11' "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
case "$PROFILE" in
  show)
    ;;
  *)
    termux::prechange_audit_gate 'Ajuste de resolução do Termux:X11' 'x11_resolution_change' "$DEVICE_ID"
    ;;
esac

case "$PROFILE" in
  performance|balanced|native|show)
    command_text="set-x11-resolution ${PROFILE}"
    ;;
  custom)
    if ! printf '%s' "$CUSTOM_RESOLUTION" | grep -Eq '^[0-9]+x[0-9]+$'; then
      fail \
        "validação de argumentos" \
        "Resolução custom inválida: ${CUSTOM_RESOLUTION}" \
        "A resolução não pode ser aplicada." \
        "Usar custom LARGURAxALTURA, por exemplo: custom 1280x800."
    fi
    command_text="set-x11-resolution custom ${CUSTOM_RESOLUTION}"
    ;;
  *)
    fail \
      "validação de argumentos" \
      "Perfil inválido: ${PROFILE}" \
      "A resolução não pode ser aplicada." \
      "Usar performance, balanced, native, show ou custom LARGURAxALTURA."
    ;;
esac

case "$PROFILE" in
  performance|balanced|custom)
    expected_text='Resolução do Termux:X11 ajustada para'
    ;;
  native)
    expected_text='Resolução do Termux:X11 ajustada para nativa.'
    ;;
  show)
    expected_text='displayResolutionMode'
    ;;
esac

step_begin 'Preparando o desktop mode livre antes do ajuste de resolução'
if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O host não conseguiu garantir o desktop mode livre obrigatório antes do ajuste de resolução.' \
    'Reconstruir o desktop mode aprovado e repetir a operação.'
fi
step_ok 'Desktop mode ativo e janelas base prontas.'
termux::audit_launch_device_watch "$DEVICE_ID"

step_begin "Aplicando o perfil de resolução ${PROFILE} no Termux:X11"
bash "${PROJECT_ROOT}/adb_termux_send_command.sh" \
  --device "$DEVICE_ID" \
  --expect "$expected_text" \
  -- "$command_text"
step_ok "Resolução ${PROFILE} enviada sem erro ao Termux:X11."

printf 'Resolução enviada ao dispositivo %s.\n' "$DEVICE_ID"
printf 'Linha enviada: %s\n' "$command_text"
