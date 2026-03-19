#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$SCRIPT_DIR"
PROFILE="${1:-performance}"
CUSTOM_RESOLUTION="${2:-}"

case "$PROFILE" in
  --help|-h)
    printf 'Uso: %s [performance|balanced|native|show|custom LARGURAxALTURA]\n' "$0"
    exit 0
    ;;
esac

fail() {
  termux::fail "$@"
}

termux::require_host_command \
  adb \
  'Não é possível ajustar a resolução do Termux:X11 a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_single_device)

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

if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O host não conseguiu garantir o split-screen obrigatório nem o app Termux:API ativo antes do ajuste de resolução.' \
    'Restaurar Termux, Termux:X11 e Termux:API e repetir a operação.'
fi

bash "${PROJECT_ROOT}/adb_termux_send_command.sh" \
  --device "$DEVICE_ID" \
  --expect "$expected_text" \
  -- "$command_text"

printf 'Resolução enviada ao dispositivo %s.\n' "$DEVICE_ID"
printf 'Linha enviada: %s\n' "$command_text"
