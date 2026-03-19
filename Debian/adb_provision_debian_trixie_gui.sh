#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REMOTE_DIR="/data/local/tmp"
PAYLOAD_FILES=(
  "install_debian_trixie_gui.sh"
  "configure_debian_trixie_root.sh"
  "configure_debian_trixie_user.sh"
  "run_gui_in_debian.sh"
)
FORWARDED_ARGS=()
TOTAL_STEPS=3
CURRENT_STEP=0

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

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'O provisionamento Debian GUI foi interrompido.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
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
      printf '  --alias nome          usa um alias customizado no proot-distro.\n'
      printf '  --reset-distro        remove e recria o Debian antes da configuração.\n'
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'O provisionamento não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --alias, --reset-distro ou --help.'
      ;;
  esac
done

termux::require_host_command \
  adb \
  'Não é possível orquestrar o dispositivo Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

step_begin 'Resetando o workspace e preparando o desktop livre base'
bash "${PROJECT_ROOT}/ADB/adb_reset_termux_stack.sh" --focus termux >/dev/null

DEVICE_ID=$(termux::resolve_target_device)
step_ok 'Reset concluído e device resolvido para o provisionamento Debian.'

step_begin 'Enviando os payloads Debian GUI para /data/local/tmp'
for file_name in "${PAYLOAD_FILES[@]}"; do
  if [ ! -f "${SCRIPT_DIR}/${file_name}" ]; then
    fail \
      "test -f \"${SCRIPT_DIR}/${file_name}\"" \
      'Payload Debian ausente no host.' \
      'Não há script suficiente para concluir o provisionamento Debian GUI.' \
      'Garantir que todos os scripts da pasta Debian existam no repositório.'
  fi

  run_adb push "${SCRIPT_DIR}/${file_name}" "${REMOTE_DIR}/${file_name}" >/dev/null
  run_adb shell chmod 755 "${REMOTE_DIR}/${file_name}" >/dev/null
done
step_ok 'Payloads Debian GUI enviados e marcados como executáveis.'

step_begin 'Reconstruindo o desktop livre antes da instalação manual ou síncrona'
if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O provisionamento Debian terminou sem conseguir restaurar o desktop mode livre obrigatório do workspace.' \
    'Reconstruir o desktop livre aprovado e repetir o provisionamento.'
fi
step_ok 'Desktop livre pronto para a etapa Debian seguinte.'

install_command=(bash /data/local/tmp/install_debian_trixie_gui.sh)
if [ "${#FORWARDED_ARGS[@]}" -gt 0 ]; then
  install_command+=("${FORWARDED_ARGS[@]}")
fi

printf 'Provisionamento Debian GUI concluído no host.\n'
printf 'Dispositivo: %s\n' "$DEVICE_ID"
printf 'Payloads enviados para: %s\n' "$REMOTE_DIR"
printf 'Execute manualmente no app Termux:\n'
printf '%s\n' "${install_command[*]}"
printf 'Ou, do host com sincronização real e saída contida:\n'
printf 'bash %s/Debian/adb_install_debian_trixie_gui.sh\n' "$PROJECT_ROOT"
printf 'Depois disso, rode apps GUI com run-gui-debian dentro do Termux.\n'
