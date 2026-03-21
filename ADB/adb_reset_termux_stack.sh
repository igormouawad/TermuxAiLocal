#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

FOCUS_APP="termux"
REBOOT_IF_NEEDED=0
TOTAL_STEPS=3
CURRENT_STEP=0
AUDIT_OWNER=0

finish_audit() {
  local exit_code=$?

  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap finish_audit EXIT

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

step_note() {
  termux::progress_note 'HOST' "$1"
}

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'O reset do ecossistema Termux foi interrompido.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

current_focus() {
  termux::current_focus "$DEVICE_ID"
}

current_termux_processes() {
  termux::list_termux_processes "$DEVICE_ID"
}

kill_termux_side_processes() {
  set +e
  bash "${SCRIPT_DIR}/adb_termux_send_command.sh" \
    --device "$DEVICE_ID" \
    --expect 'TERMUX_REMOTE_RESET_OK' \
    -- 'for helper in stop-openbox-x11 stop-xfce-x11 stop-virgl stop-termux-x11; do command -v "$helper" >/dev/null 2>&1 && "$helper" >/dev/null 2>&1 || true; done; pkill -f "^aterm( |$)|^xterm( |$)|^openbox( |$)|openbox-session|^xfce4-session( |$)|^xfwm4( |$)|^xfdesktop( |$)|^xfce4-panel( |$)|^xfce4-terminal( |$)|^xfsettingsd( |$)|^Thunar( |$)|^thunar( |$)|virgl_test_server_android|^termux-x11( |$)|^termux-x11 com\\.termux\\.x11 |termux-x11 .*:1|termux-x11 :1|com\\.termux\\.x11\\.Loader|^dbus-daemon .*--session" >/dev/null 2>&1 || true; rm -rf "$HOME/.cache/sessions" "$HOME/.cache/termux-stack/openbox" "$HOME/.cache/termux-stack/dbus" >/dev/null 2>&1 || true; rm -f "$HOME"/.cache/termux-stack/*.log "$HOME/.config/termux-stack/session.env" "$HOME/.config/termux-stack/driver.env" >/dev/null 2>&1 || true; printf "TERMUX_REMOTE_RESET_OK\n"' \
    >/dev/null 2>&1
  set -e
}

reboot_device_for_clean_state() {
  termux::prepare_android_reboot_state "$DEVICE_ID"
  adb -s "$DEVICE_ID" reboot >/dev/null 2>&1 || true
  if ! termux::wait_for_device_ready "$DEVICE_ID" 120; then
    fail \
      'espera pela volta do endpoint ADB após reinicialização do dispositivo' \
      "O endpoint $DEVICE_ID não voltou ao estado device dentro do tempo esperado." \
      'O reset não conseguiu retomar o controle ADB do dispositivo após o reboot.' \
      'Se o fluxo estiver usando ADB por Wi-Fi, reconectar o endpoint atual e repetir o reset.'
  fi
  if ! termux::wait_for_boot_completed "$DEVICE_ID" 180; then
    fail \
      'espera pelo boot completo após reinicialização do dispositivo' \
      'O Android não sinalizou boot completo dentro do tempo esperado.' \
      'O reset não conseguiu restaurar um estado limpo do dispositivo.' \
      'Desbloquear o tablet, aguardar o boot terminar e repetir o reset.'
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --focus)
      shift
      FOCUS_APP="${1:-termux}"
      shift || true
      ;;
    --reboot-if-needed)
      REBOOT_IF_NEEDED=1
      shift
      ;;
    --help|-h)
      printf 'Uso: %s [--focus termux|x11] [--reboot-if-needed]\n' "$0"
      printf '  --focus termux  reconstrói o desktop mode e deixa foco final no app Termux.\n'
      printf '  --focus x11     reconstrói o desktop mode e deixa foco final no app Termux:X11.\n'
      printf '  --reboot-if-needed  reinicia o dispositivo se resíduos persistentes impedirem o reset limpo.\n'
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'O reset não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --focus termux|x11, --reboot-if-needed ou --help.'
      ;;
  esac
done

case "$FOCUS_APP" in
  termux|x11)
    ;;
  *)
    fail \
      'validação de argumentos' \
      "Foco inválido: $FOCUS_APP" \
      'O app final a receber foco é desconhecido.' \
      'Usar --focus termux ou --focus x11.'
    ;;
esac

termux::require_host_command \
  adb \
  'Não é possível resetar os apps do tablet a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_target_device)
termux::audit_session_begin 'Reset do ecossistema Termux' "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
termux::prechange_audit_gate 'Reset do ecossistema Termux' 'stack_reset' "$DEVICE_ID"

step_begin 'Encerrando apps Android e resíduos controlados do ecossistema Termux'
kill_termux_side_processes
run_adb shell am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null
run_adb shell cmd activity kill com.termux.x11 >/dev/null
run_adb shell cmd activity kill com.termux >/dev/null
run_adb shell cmd activity kill com.termux.api >/dev/null
run_adb shell am force-stop com.termux.x11 >/dev/null
run_adb shell am force-stop com.termux >/dev/null
run_adb shell am force-stop com.termux.api >/dev/null
sleep 1
step_ok 'Apps principais encerrados e limpeza remota best-effort aplicada.'

step_begin 'Validando clean-state de processos antes da reconstrução do desktop'
if ! termux::wait_for_no_termux_processes "$DEVICE_ID" 8; then
  if [ "$REBOOT_IF_NEEDED" -eq 1 ]; then
    step_note 'Processos persistentes detectados; acionando reboot limpo controlado.'
    reboot_device_for_clean_state
  fi
fi

if ! termux::wait_for_no_termux_processes "$DEVICE_ID" 8; then
  fail \
    'encerramento completo dos processos Termux no dispositivo' \
    "$(current_termux_processes)" \
    'O reset terminou com processos residuais do ecossistema Termux, o que invalida o clean-state do projeto.' \
    'Executar novamente com --reboot-if-needed ou eliminar os processos residuais antes de repetir o fluxo.'
fi
step_ok "Clean-state confirmado. Processos remanescentes: $(termux::termux_process_count "$DEVICE_ID")"

step_begin 'Reconstruindo o desktop mode livre aprovado do workspace'
workspace_ready=0
if termux::ensure_termux_workspace_ready "$DEVICE_ID" "$FOCUS_APP"; then
  workspace_ready=1
else
  if [ "$REBOOT_IF_NEEDED" -eq 1 ]; then
    reboot_device_for_clean_state
    if termux::ensure_termux_workspace_ready "$DEVICE_ID" "$FOCUS_APP"; then
      workspace_ready=1
    fi
  fi
fi

if [ "$workspace_ready" -ne 1 ]; then
  fail \
    'reabertura validada do ecossistema Termux' \
    "$(current_focus)" \
    'O reset terminou sem conseguir restaurar o desktop mode livre obrigatório do workspace.' \
    'Repetir o reset, preferencialmente com --reboot-if-needed, para reconstruir o layout operacional do projeto.'
fi
step_ok 'Desktop livre reconstruído com sucesso no Android.'
termux::audit_launch_device_watch "$DEVICE_ID"

printf 'Ecossistema Termux reiniciado no dispositivo %s.\n' "$DEVICE_ID"
printf 'Foco final solicitado: %s\n' "$FOCUS_APP"
printf 'Layout final: desktop mode livre com Termux, Termux:X11 e cliente SSH nas janelas aprovadas.\n'
printf 'Termux:API: fora do desktop visível; a app só entra automaticamente no reinstall limpo.\n'
printf 'Processos remanescentes após o reset: %s\n' "$(termux::termux_process_count "$DEVICE_ID")"
printf '%s\n' "$(current_focus)"
