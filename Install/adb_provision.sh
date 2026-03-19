#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

INSTALL_ROOT="$SCRIPT_DIR"
PAYLOAD_SOURCE="${INSTALL_ROOT}/install_termux_stack.sh"
BOOTSTRAP_SOURCE="${INSTALL_ROOT}/install_termux_repo_bootstrap.sh"
TERMUX_MENU_SOURCE="${INSTALL_ROOT}/termux_workspace_menu.sh"
PAYLOAD_TARGET="/data/local/tmp/install_termux_stack.sh"
BOOTSTRAP_TARGET="/data/local/tmp/install_termux_repo_bootstrap.sh"
TERMUX_MENU_TARGET="/data/local/tmp/termux_workspace_menu.sh"
ANDROID_PRIMARY_USER="0"
REQUIRED_APPS=(
  "com.termux"
  "com.termux.api"
  "com.termux.x11"
)

fail() {
  termux::fail "$@"
}

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A etapa de provisionamento foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

termux::require_host_command \
  adb \
  'Não é possível orquestrar o dispositivo Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_target_device)

if [ ! -f "$PAYLOAD_SOURCE" ]; then
  fail \
    "test -f \"$PAYLOAD_SOURCE\"" \
    "Payload ausente no host." \
    "Não há script para transferir ao dispositivo." \
    "Garantir que Install/install_termux_stack.sh exista no repositório."
fi

if [ ! -f "$BOOTSTRAP_SOURCE" ]; then
  fail \
    "test -f \"$BOOTSTRAP_SOURCE\"" \
    "Bootstrap fino ausente no host." \
    "Não há bootstrap para delegar ao payload principal dentro do app Termux." \
    "Garantir que Install/install_termux_repo_bootstrap.sh exista no repositório."
fi

if [ ! -f "$TERMUX_MENU_SOURCE" ]; then
  fail \
    "test -f \"$TERMUX_MENU_SOURCE\"" \
    "Menu Termux ausente no host." \
    "Nao ha helper visual do lado Termux para transferir ao dispositivo." \
    "Garantir que Install/termux_workspace_menu.sh exista no repositorio."
fi

packages_output=$(adb -s "$DEVICE_ID" shell pm list packages --user "$ANDROID_PRIMARY_USER" 2>&1) || fail \
  "adb -s \"$DEVICE_ID\" shell pm list packages --user \"$ANDROID_PRIMARY_USER\"" \
  "$packages_output" \
  "Não foi possível auditar os apps Android obrigatórios." \
  "Resolver a falha retornada pelo Package Manager e tentar novamente."

if printf '%s' "$packages_output" | grep -Fq 'SecurityException'; then
  fail \
    "adb -s \"$DEVICE_ID\" shell pm list packages --user \"$ANDROID_PRIMARY_USER\"" \
    "$packages_output" \
    "O Package Manager retornou SecurityException; o estado dos apps no usuário principal Android não pôde ser validado." \
    "Validar se os apps estão instalados no usuário principal suportado pelo ADB e tentar novamente."
fi

missing_apps=()
for package_name in "${REQUIRED_APPS[@]}"; do
  if ! printf '%s\n' "$packages_output" | grep -Fxq "package:${package_name}"; then
    missing_apps+=("$package_name")
  fi
done

if [ "${#missing_apps[@]}" -gt 0 ]; then
  fail \
    "auditoria de apps Android obrigatórios no usuário ${ANDROID_PRIMARY_USER}" \
    "Apps ausentes ou inacessíveis no usuário principal: ${missing_apps[*]}" \
    "O perfil principal suportado pelo ADB não atende aos pré-requisitos obrigatórios do projeto." \
    "Instalar os apps Android obrigatórios no usuário principal do Android e executar o script novamente."
fi

run_adb push "$PAYLOAD_SOURCE" "$PAYLOAD_TARGET" >/dev/null
run_adb push "$BOOTSTRAP_SOURCE" "$BOOTSTRAP_TARGET" >/dev/null
run_adb push "$TERMUX_MENU_SOURCE" "$TERMUX_MENU_TARGET" >/dev/null
run_adb shell chmod +x "$PAYLOAD_TARGET" >/dev/null
run_adb shell chmod +x "$BOOTSTRAP_TARGET" >/dev/null
run_adb shell chmod +x "$TERMUX_MENU_TARGET" >/dev/null

if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O provisionamento terminou sem conseguir restaurar o split-screen obrigatório nem confirmar o app Termux:API em execução.' \
    'Reabrir Termux, Termux:X11 e Termux:API ou repetir o provisionamento.'
fi

printf 'Provisionamento concluído no host.\n'
printf 'Dispositivo: %s\n' "$DEVICE_ID"
printf 'Payload enviado para: %s\n' "$PAYLOAD_TARGET"
printf 'Bootstrap enviado para: %s\n' "$BOOTSTRAP_TARGET"
printf 'Menu Termux enviado para: %s\n' "$TERMUX_MENU_TARGET"
printf 'Execute manualmente no app Termux:\n'
printf 'bash /data/local/tmp/install_termux_repo_bootstrap.sh\n'
printf 'Após instalação, atualização ou mudanças relevantes, reinicie Termux, Termux:X11 e Termux:API.\n'
