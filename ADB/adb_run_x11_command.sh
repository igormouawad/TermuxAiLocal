#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$SCRIPT_DIR"
MODE="--app"
LOCAL_SCRIPT=""
WITH_VIRGL=0
TOTAL_STEPS=3
CURRENT_STEP=0
AUDIT_OWNER=0
X11_UI_REMOTE="/sdcard/Download/adb_run_x11_command_x11.xml"
X11_UI_LOCAL="$(mktemp)"

cleanup() {
  local exit_code=$?

  rm -f "$X11_UI_LOCAL"
  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap cleanup EXIT

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
    'A execução remota no X11 foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

append_word() {
  local current_text="$1"
  local word="$2"

  termux::append_shell_word "$current_text" "$word"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-virgl)
      WITH_VIRGL=1
      shift
      ;;
    --xterm)
      MODE="--xterm"
      shift
      ;;
    --script)
      shift
      if [ "$#" -eq 0 ]; then
        printf 'Uso: %s [--with-virgl] [--xterm] [--script arquivo_local] comando [args...]\n' "$0" >&2
        exit 1
      fi
      LOCAL_SCRIPT="$1"
      shift
      ;;
    --help|-h)
      printf 'Uso: %s [--with-virgl] [--xterm] [--script arquivo_local] comando [args...]\n' "$0"
      printf '  --with-virgl  sobe start-virgl usando o modo ativo do perfil X11 antes do comando.\n'
      printf '  --xterm       executa o comando em uma nova janela xterm.\n'
      printf '  --script      envia um script local e o executa no contexto X11.\n'
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [ -z "$LOCAL_SCRIPT" ] && [ "$#" -eq 0 ]; then
  printf 'Uso: %s [--with-virgl] [--xterm] [--script arquivo_local] comando [args...]\n' "$0" >&2
  exit 1
fi

if [ -n "$LOCAL_SCRIPT" ] && [ ! -f "$LOCAL_SCRIPT" ]; then
  fail \
    "test -f \"$LOCAL_SCRIPT\"" \
    'Script local não encontrado.' \
    'Não há conteúdo para enviar ao contexto X11 do dispositivo.' \
      'Informar um caminho de script existente no host.'
fi

if [ "$WITH_VIRGL" -eq 1 ]; then
  TOTAL_STEPS=4
fi

termux::require_host_command \
  adb \
  'Não é possível orquestrar a execução no X11 a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_target_device)
termux::audit_session_begin 'Execução de comando X11 via host wrapper' "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
step_begin 'Preparando desktop mode livre e verificando a janela do Termux:X11'
if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O host não conseguiu garantir o desktop mode livre obrigatório antes da execução no X11.' \
    'Reconstruir o desktop livre aprovado e repetir a operação.'
fi

if ! termux::wait_for_x11_surface "$DEVICE_ID" "$X11_UI_REMOTE" "$X11_UI_LOCAL" 10; then
  fail \
    'subida da surface do Termux:X11' \
    'A surface lorieView não apareceu.' \
    'O app Termux:X11 não exibiu a superfície gráfica esperada.' \
    'Reabrir o app Termux:X11 e repetir a operação.'
fi
step_ok 'Workspace pronto e surface X11 confirmada.'
termux::audit_launch_device_watch "$DEVICE_ID"

command_text="run-in-x11 ${MODE}"

if [ -n "$LOCAL_SCRIPT" ]; then
  remote_script="/data/local/tmp/adb-x11-command-$(date +%Y%m%d-%H%M%S)-$$.sh"
  run_adb push "$LOCAL_SCRIPT" "$remote_script" >/dev/null
  run_adb shell chmod 755 "$remote_script" >/dev/null

  command_text="$(append_word "$command_text" 'sh')"
  command_text="$(append_word "$command_text" "$remote_script")"
else
  for arg in "$@"; do
    command_text="$(append_word "$command_text" "$arg")"
  done
fi

if [ "$MODE" = '--xterm' ]; then
  expected_text='Comando iniciado em xterm no X11'
else
  expected_text='Aplicação iniciada no X11'
fi

if [ "$WITH_VIRGL" -eq 1 ]; then
  step_begin 'Garantindo servidor VirGL para a execução no X11'
  bash "${PROJECT_ROOT}/adb_termux_send_command.sh" \
    --device "$DEVICE_ID" \
    --expect 'virgl_test_server_android iniciado em modo' \
    --expect 'virgl_test_server_android já está em execução' \
    -- 'mode=plain; if [ -f "$HOME/.config/termux-stack/session.env" ]; then . "$HOME/.config/termux-stack/session.env"; mode="${TERMUX_VIRGL_MODE:-plain}"; fi; start-virgl "$mode"'
  step_ok 'VirGL garantido para o contexto X11.'
fi

step_begin 'Montando a linha final e preparando o contexto de execução'
step_ok "Destino selecionado: ${MODE#--} no display :1."

step_begin 'Executando o comando no contexto X11 apropriado'
bash "${PROJECT_ROOT}/adb_termux_send_command.sh" \
  --device "$DEVICE_ID" \
  --expect "$expected_text" \
  -- "$command_text"
step_ok 'Comando enviado ao X11 sem erro.'

printf 'Comando enviado ao X11 no dispositivo %s.\n' "$DEVICE_ID"
printf 'Modo: %s\n' "$MODE"
if [ "$WITH_VIRGL" -eq 1 ]; then
  printf 'Virgl: solicitado conforme o perfil X11 ativo\n'
fi
printf 'Linha enviada: %s\n' "$command_text"

if [ -n "$LOCAL_SCRIPT" ]; then
  printf 'Script enviado: %s\n' "$LOCAL_SCRIPT"
fi
