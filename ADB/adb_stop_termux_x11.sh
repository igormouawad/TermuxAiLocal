#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

fail() {
  termux::fail "$@"
}

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'O encerramento do Termux:X11 foi interrompido.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

termux::require_host_command \
  adb \
  'Não é possível encerrar o Termux:X11 a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_single_device)

set +e
bash "${SCRIPT_DIR}/adb_termux_send_command.sh" \
  --device "$DEVICE_ID" \
  -- 'for helper in stop-openbox-x11 stop-xfce-x11 stop-termux-x11; do command -v "$helper" >/dev/null 2>&1 && "$helper" >/dev/null 2>&1 || true; done; pkill -f "^rofi( |$)|^tint2( |$)|^openbox( |$)|openbox-session|^xfce4-session( |$)|^xfwm4( |$)|^xfdesktop( |$)|^xfce4-panel( |$)|^xfce4-terminal( |$)|^xfsettingsd( |$)|^Thunar( |$)|^thunar( |$)|^aterm( |$)|^xterm( |$)|^termux-x11( |$)|^termux-x11 com\\.termux\\.x11 |termux-x11 .*:1|termux-x11 :1|com\\.termux\\.x11\\.Loader" >/dev/null 2>&1 || true' \
  >/dev/null 2>&1
set -e

run_adb shell am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null
run_adb shell cmd activity kill com.termux.x11 >/dev/null
run_adb shell am force-stop com.termux.x11 >/dev/null
sleep 1

printf 'Termux:X11 encerrado no dispositivo %s.\n' "$DEVICE_ID"
printf '%s\n' "$(termux::current_focus "$DEVICE_ID")"
