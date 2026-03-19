#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FORWARDED_ARGS=()

fail() {
  termux::fail "$@"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reset-distro)
      FORWARDED_ARGS+=("$1")
      shift
      ;;
    --alias)
      if [ "$#" -lt 2 ]; then
        printf 'Uso: %s [--alias nome] [--reset-distro]\n' "$0" >&2
        exit 1
      fi
      FORWARDED_ARGS+=("$1" "$2")
      shift 2
      ;;
    --help|-h)
      printf 'Uso: %s [--alias nome] [--reset-distro]\n' "$0"
      printf '  Executa de forma síncrona o payload /data/local/tmp/install_debian_trixie_gui.sh no shell real do app Termux.\n'
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'A instalação Debian GUI não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --alias, --reset-distro ou --help.'
      ;;
  esac
done

termux::require_host_command \
  adb \
  'Não é possível orquestrar o dispositivo Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID="$(termux::resolve_single_device)"

if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O host não conseguiu garantir o split-screen obrigatório nem o app Termux:API ativo antes da instalação Debian.' \
    'Restaurar Termux, Termux:X11 e Termux:API e repetir a operação.'
fi

install_command='bash /data/local/tmp/install_debian_trixie_gui.sh'
if [ "${#FORWARDED_ARGS[@]}" -gt 0 ]; then
  for arg in "${FORWARDED_ARGS[@]}"; do
    install_command="$(termux::append_shell_word "$install_command" "$arg")"
  done
fi

bash "${PROJECT_ROOT}/ADB/adb_termux_send_command.sh" \
  --device "$DEVICE_ID" \
  --quiet-output \
  --expect 'Debian Trixie preparado para apps GUI no Termux.' \
  -- "$install_command"

helper_check_output="$(
  bash "${PROJECT_ROOT}/ADB/adb_termux_send_command.sh" \
    --device "$DEVICE_ID" \
    --expect '/data/data/com.termux/files/home/bin/run-gui-debian' \
    -- 'command -v run-gui-debian'
)"

printf 'Instalação Debian GUI concluída com sucesso no dispositivo %s.\n' "$DEVICE_ID"
printf 'Helper Debian GUI: %s\n' "$(printf '%s\n' "$helper_check_output" | head -n 1)"
