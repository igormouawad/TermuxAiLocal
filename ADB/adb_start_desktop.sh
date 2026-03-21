#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$SCRIPT_DIR"
DESKTOP_PROFILE="openbox"
XFCE_WM="xfwm4"
OPENBOX_PROFILE="openbox-maxperf"
WM_EXPLICIT=0
WITH_GPU=0
MAX_PERF=0
TOTAL_STEPS=3
CURRENT_STEP=0
X11_UI_REMOTE="/sdcard/Download/adb_start_desktop_x11.xml"
X11_UI_LOCAL="$(mktemp)"
AUDIT_OWNER=0

cleanup() {
  local exit_code=$?

  rm -f "$X11_UI_LOCAL"
  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap cleanup EXIT

usage() {
  printf 'Uso: %s [--with-gpu] [--maxperf] [--wm xfwm4|openbox] [--profile openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp] [openbox|xfce|openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp]\n' "$0"
  printf '  --with-gpu  inclui start-virgl e check-gpu-termux antes da validação final.\n'
  printf '  --maxperf   aplica o perfil agressivo: 1280x720 + virgl plain + Openbox.\n'
  printf '  --wm        escolhe o window manager do XFCE; use openbox para substituir o xfwm4.\n'
  printf '  --profile   seleciona o perfil do Openbox puro.\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-gpu)
      WITH_GPU=1
      shift
      ;;
    --maxperf)
      MAX_PERF=1
      shift
      ;;
    --wm)
      shift
      XFCE_WM="${1:-}"
      WM_EXPLICIT=1
      shift || true
      ;;
    --wm=*)
      XFCE_WM="${1#*=}"
      WM_EXPLICIT=1
      shift
      ;;
    --profile)
      shift
      OPENBOX_PROFILE="${1:-}"
      shift || true
      ;;
    --profile=*)
      OPENBOX_PROFILE="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    openbox|xfce)
      DESKTOP_PROFILE="$1"
      shift
      ;;
    openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp)
      DESKTOP_PROFILE='openbox'
      OPENBOX_PROFILE="$1"
      shift
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if ! termux::xfce_wm_valid "$XFCE_WM"; then
  printf 'WM inválido: %s\n' "$XFCE_WM" >&2
  printf 'Use xfwm4 ou openbox.\n' >&2
  exit 1
fi

if ! termux::openbox_profile_valid "$OPENBOX_PROFILE"; then
  printf 'Perfil Openbox inválido: %s\n' "$OPENBOX_PROFILE" >&2
  printf 'Use openbox-stable, openbox-maxperf, openbox-compat ou openbox-vulkan-exp.\n' >&2
  exit 1
fi

if [ "$DESKTOP_PROFILE" != 'xfce' ] && [ "$WM_EXPLICIT" -eq 1 ]; then
  printf 'O parâmetro --wm só se aplica ao perfil xfce.\n' >&2
  exit 1
fi

if [ "$MAX_PERF" -eq 1 ]; then
  WITH_GPU=1
  if [ "$DESKTOP_PROFILE" = 'xfce' ]; then
    if [ "$WM_EXPLICIT" -eq 1 ] && [ "$XFCE_WM" != 'openbox' ]; then
      printf 'O perfil --maxperf para XFCE exige Openbox como WM.\n' >&2
      exit 1
    fi
    XFCE_WM='openbox'
  elif [ "$DESKTOP_PROFILE" = 'openbox' ]; then
    OPENBOX_PROFILE='openbox-maxperf'
  fi
fi

if [ "$WITH_GPU" -eq 1 ] && [ "$MAX_PERF" -ne 1 ]; then
  TOTAL_STEPS=4
fi

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

run_termux_helper() {
  local command_text="$1"
  shift

  local expected_text
  local -a helper_args=(--device "$DEVICE_ID")

  for expected_text in "$@"; do
    helper_args+=(--expect "$expected_text")
  done

  bash "${PROJECT_ROOT}/adb_termux_send_command.sh" "${helper_args[@]}" -- "$command_text"
}

wait_for_desktop_processes() {
  local pattern="$1"
  local timeout_seconds="$2"
  local elapsed=0
  local process_output

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if [ "$DESKTOP_PROFILE" = 'xfce' ]; then
      set +e
      process_output=$(bash "${PROJECT_ROOT}/adb_termux_send_command.sh" \
        --device "$DEVICE_ID" \
        -- 'pgrep -af "xfce4-session|xfce4-panel|xfwm4|openbox" || true' 2>&1)
      set -e

      if printf '%s\n' "$process_output" | grep -Eq '(^| )xfce4-session($| )' \
        && printf '%s\n' "$process_output" | grep -Eq '(^| )xfce4-panel($| )' \
        && printf '%s\n' "$process_output" | grep -Eq "$pattern"; then
        return 0
      fi
    else
      set +e
      process_output=$(bash "${PROJECT_ROOT}/adb_termux_send_command.sh" \
        --device "$DEVICE_ID" \
        -- 'pgrep -af "openbox|aterm|xterm|dbus-daemon|virgl_test_server_android" || true' 2>&1)
      set -e

      if printf '%s\n' "$process_output" | grep -Eq "$pattern"; then
        return 0
      fi
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  fail \
    'validação de processos do desktop' \
    'Os processos esperados do desktop não foram encontrados.' \
    'A sessão gráfica não ficou ativa após a subida.' \
    'Inspecionar o terminal Termux para mensagens adicionais e repetir a subida.'
}

termux::require_host_command \
  adb \
  'Não é possível subir o desktop via host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_target_device)
termux::audit_session_begin 'Subida do desktop Termux/X11' "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"

step_begin 'Preparando o desktop mode livre e as janelas base do workspace'
if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O host não conseguiu garantir o desktop mode livre obrigatório antes da subida do desktop.' \
    'Reconstruir o desktop mode aprovado e repetir a operação.'
fi
step_ok 'Desktop mode ativo e janelas base disponíveis.'
termux::audit_launch_device_watch "$DEVICE_ID"

if ! termux::desktop_profile_valid "$DESKTOP_PROFILE"; then
  fail \
    'validação de argumentos' \
    "Desktop inválido: $DESKTOP_PROFILE" \
    'O desktop solicitado não pode ser iniciado.' \
    'Usar xfce ou openbox.'
fi

start_command="$(termux::desktop_start_command "$DESKTOP_PROFILE" "$OPENBOX_PROFILE" "$XFCE_WM" "$MAX_PERF")"
expected_text="$(termux::desktop_start_message "$DESKTOP_PROFILE" "$OPENBOX_PROFILE" "$XFCE_WM" "$MAX_PERF")"
process_pattern="$(termux::desktop_process_pattern "$DESKTOP_PROFILE" "$XFCE_WM")"

if [ "$WITH_GPU" -eq 1 ] && [ "$MAX_PERF" -ne 1 ]; then
  step_begin 'Garantindo servidor VirGL antes da sessão gráfica'
  run_termux_helper \
    'start-virgl' \
    'virgl_test_server_android iniciado em modo' \
    'virgl_test_server_android já está em execução'

  run_termux_helper \
    'termux-stack-status --brief' \
    'VIRGL=ativo'
  step_ok 'VirGL ativo e confirmado no estado atual da stack.'
fi

step_begin "Iniciando a sessão ${DESKTOP_PROFILE} no shell real do Termux"
run_termux_helper "$start_command" "$expected_text"
step_ok "Sessão ${DESKTOP_PROFILE} iniciada sem erro."

step_begin 'Validando surface X11, processos do desktop e renderer atual'
if ! termux::wait_for_x11_surface "$DEVICE_ID" "$X11_UI_REMOTE" "$X11_UI_LOCAL" 12; then
  fail \
    'subida da surface do Termux:X11' \
    'A surface lorieView não apareceu.' \
    'O app Termux:X11 não exibiu a superfície gráfica esperada.' \
    'Reabrir o app Termux:X11 e repetir a operação.'
fi
wait_for_desktop_processes "$process_pattern" 15

if [ "$WITH_GPU" -eq 1 ]; then
  bash "${PROJECT_ROOT}/adb_termux_send_command.sh" \
    --device "$DEVICE_ID" \
    --expect 'GL_RENDERER: virgl' \
    -- 'check-gpu-termux'
fi
step_ok 'Surface X11, processos e renderer passaram na validação.'

printf 'Desktop iniciado com sucesso no dispositivo %s.\n' "$DEVICE_ID"
printf 'Perfil: %s\n' "$DESKTOP_PROFILE"
if [ "$DESKTOP_PROFILE" = 'openbox' ]; then
  printf 'Openbox profile: %s\n' "$OPENBOX_PROFILE"
fi
if [ "$WITH_GPU" -eq 1 ]; then
  printf 'Virgl/EGL: OK\n'
fi
if [ "$MAX_PERF" -eq 1 ]; then
  printf 'Modo: maxperf\n'
fi
printf 'Comando: %s\n' "$start_command"
printf 'Surface X11: OK\n'
printf 'Processos do desktop: OK\n'
printf 'Display unificado: :1\n'
