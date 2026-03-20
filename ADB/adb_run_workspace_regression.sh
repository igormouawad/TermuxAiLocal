#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/termux_common.sh
source "${WORKSPACE_ROOT}/lib/termux_common.sh"

DEVICE_ID=''
SUITE='full'
PRIMARY_PACKAGE='com.android.settings'
SECONDARY_PACKAGE=''
AUTO_SECONDARY=1
FINAL_FOCUS='auto'
TOTAL_STEPS=0
CURRENT_STEP=0
AUDIT_OWNER=0

SECONDARY_CANDIDATES=(
  'com.sec.android.app.popupcalculator'
  'com.android.calculator2'
  'com.google.android.calculator'
  'com.sec.android.app.myfiles'
  'com.google.android.documentsui'
  'com.android.documentsui'
)

cleanup() {
  local exit_code=$?

  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso:
  bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_workspace_regression.sh [--suite smoke|daily|desktop-layout|full]

Opcoes:
  --device SERIAL              usa explicitamente esse alvo ADB
  --suite NAME                 smoke | daily | desktop-layout | full (padrao: full)
  --primary-package PACKAGE    app principal para o teste de desktop mode (padrao: com.android.settings)
  --secondary-package PACKAGE  app secundario explicito para a grade compacta
  --no-secondary               testa o desktop mode sem tentar um app secundario
  --focus auto|app|termux|x11|ssh

Suites:
  smoke           reset -> start -> validate
  daily           fluxo diario canonico de 7 passos
  desktop-layout  trio base + app principal + app secundario opcional + reflow
  full            fluxo diario + regressao de layout em desktop mode
EOF
}

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

run_workspace_helper() {
  local helper_path="$1"
  shift
  local output

  output="$(
    TERMUXAI_DEVICE_ID="$DEVICE_ID" \
      bash "${WORKSPACE_ROOT}/${helper_path}" "$@" 2>&1
  )" || fail \
    "bash ${WORKSPACE_ROOT}/${helper_path} $*" \
    "$output" \
    'O helper chamado pela regressão do workspace falhou.' \
    'Inspecionar a etapa retornada pelo audit e repetir o fluxo.'

  printf '%s\n' "$output"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      shift
      DEVICE_ID="${1:-}"
      shift || true
      ;;
    --device=*)
      DEVICE_ID="${1#*=}"
      shift
      ;;
    --suite)
      shift
      SUITE="${1:-$SUITE}"
      shift || true
      ;;
    --suite=*)
      SUITE="${1#*=}"
      shift
      ;;
    --primary-package)
      shift
      PRIMARY_PACKAGE="${1:-$PRIMARY_PACKAGE}"
      shift || true
      ;;
    --primary-package=*)
      PRIMARY_PACKAGE="${1#*=}"
      shift
      ;;
    --secondary-package)
      shift
      SECONDARY_PACKAGE="${1:-}"
      AUTO_SECONDARY=0
      shift || true
      ;;
    --secondary-package=*)
      SECONDARY_PACKAGE="${1#*=}"
      AUTO_SECONDARY=0
      shift
      ;;
    --no-secondary)
      AUTO_SECONDARY=0
      SECONDARY_PACKAGE=''
      shift
      ;;
    --focus)
      shift
      FINAL_FOCUS="${1:-$FINAL_FOCUS}"
      shift || true
      ;;
    --focus=*)
      FINAL_FOCUS="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

case "$SUITE" in
  smoke)
    TOTAL_STEPS=3
    ;;
  daily)
    TOTAL_STEPS=7
    ;;
  desktop-layout)
    TOTAL_STEPS=4
    ;;
  full)
    TOTAL_STEPS=11
    ;;
  *)
    fail \
      'validacao de argumentos' \
      "Suite invalida: $SUITE" \
      'O runner de regressao nao sabe qual conjunto de etapas deve executar.' \
      'Usar --suite smoke, daily, desktop-layout ou full.'
      ;;
esac

case "$FINAL_FOCUS" in
  auto|app|termux|x11|ssh)
    ;;
  *)
    fail \
      'validacao de argumentos' \
      "Foco final invalido: $FINAL_FOCUS" \
      'O teste de desktop mode nao sabe qual janela deve receber o foco final.' \
      'Usar --focus auto, app, termux, x11 ou ssh.'
      ;;
esac

termux::require_host_command \
  adb \
  'Nao e possivel executar a regressao do workspace sem o cliente ADB no host.' \
  'Instalar Android Platform Tools no workstation e repetir o comando.'

DEVICE_ID="$(termux::resolve_target_device "$DEVICE_ID")"
termux::audit_session_begin "Regressao do workspace (${SUITE})" "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"

resolve_secondary_package() {
  local package_name
  local package_list

  if [ -n "$SECONDARY_PACKAGE" ]; then
    printf '%s\n' "$SECONDARY_PACKAGE"
    return 0
  fi

  if [ "$AUTO_SECONDARY" -ne 1 ]; then
    return 1
  fi

  package_list="$(adb -s "$DEVICE_ID" shell pm list packages 2>/dev/null | tr -d '\r' || true)"

  for package_name in "${SECONDARY_CANDIDATES[@]}"; do
    if printf '%s\n' "$package_list" | grep -Fxq "package:${package_name}"; then
      printf '%s\n' "$package_name"
      return 0
    fi
  done

  return 1
}

run_smoke_sequence() {
  step_begin 'Resetando o ecossistema Termux e reconstruindo o desktop aprovado'
  run_workspace_helper 'ADB/adb_reset_termux_stack.sh' --focus termux >/dev/null
  step_ok 'Reset canônico concluído.'

  step_begin 'Subindo o desktop Openbox com GPU no perfil diário'
  run_workspace_helper 'ADB/adb_start_desktop.sh' --with-gpu --profile openbox-maxperf openbox >/dev/null
  step_ok 'Desktop Openbox diário iniciado.'

  step_begin 'Executando a validação autoritativa do baseline'
  run_workspace_helper 'ADB/adb_validate_baseline.sh' --desktop=openbox --profile=openbox-maxperf --with-gpu --report >/dev/null
  step_ok 'Baseline validado com relatório.'
}

run_daily_tail_sequence() {
  step_begin 'Lendo o status resumido do stack no shell real do Termux'
  run_workspace_helper 'ADB/adb_termux_send_command.sh' -- 'termux-stack-status --brief' >/dev/null
  step_ok 'Status resumido do stack coletado.'

  step_begin 'Reabrindo o desktop validado antes do teste X11'
  run_workspace_helper 'ADB/adb_start_desktop.sh' --with-gpu --profile openbox-maxperf openbox >/dev/null
  step_ok 'Desktop reaberto para os testes visuais.'

  step_begin 'Abrindo um app X11 leve no display :1'
  run_workspace_helper 'ADB/adb_run_x11_command.sh' aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1' >/dev/null
  step_ok 'Demo leve do X11 concluída.'

  step_begin 'Abrindo xeyes no Debian pela integração GUI validada'
  run_workspace_helper 'ADB/adb_termux_send_command.sh' --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes' >/dev/null
  step_ok 'Launcher Debian GUI validado com xeyes.'
}

run_desktop_layout_sequence() {
  local resolved_secondary=''

  step_begin 'Reconstruindo o trio canônico antes do teste de layout em desktop mode'
  run_workspace_helper 'ADB/adb_consolidate_freeform_desktop.sh' --restart --focus ssh >/dev/null
  step_ok 'Trio base reaberto e estável.'

  step_begin "Abrindo ${PRIMARY_PACKAGE} com o layout Foco grande"
  run_workspace_helper 'ADB/adb_open_desktop_app.sh' --package "$PRIMARY_PACKAGE" --focus "$FINAL_FOCUS" >/dev/null
  step_ok "App principal ${PRIMARY_PACKAGE} aberto em desktop mode."

  step_begin 'Tentando abrir um app secundário para validar a grade compacta'
  resolved_secondary="$(resolve_secondary_package || true)"
  if [ -n "$resolved_secondary" ]; then
    termux::progress_note 'HOST' "App secundário escolhido: ${resolved_secondary}"
    run_workspace_helper 'ADB/adb_open_desktop_app.sh' --package "$resolved_secondary" --focus "$FINAL_FOCUS" >/dev/null
    step_ok "App secundário ${resolved_secondary} aberto e arranjado."
  else
    termux::progress_note 'HOST' 'Nenhum app secundário compatível foi encontrado; seguindo apenas com o app principal.'
    step_ok 'Layout principal validado sem app secundário adicional.'
  fi

  step_begin 'Reaplicando o layout atual sem abrir app novo para validar o reflow explícito'
  run_workspace_helper 'ADB/adb_open_desktop_app.sh' --reflow-only --focus "$FINAL_FOCUS" >/dev/null
  step_ok 'Reflow explícito do desktop mode concluído.'
}

case "$SUITE" in
  smoke)
    run_smoke_sequence
    ;;
  daily)
    run_smoke_sequence
    run_daily_tail_sequence
    ;;
  desktop-layout)
    run_desktop_layout_sequence
    ;;
  full)
    run_smoke_sequence
    run_daily_tail_sequence
    run_desktop_layout_sequence
    ;;
esac

printf 'Regressao %s concluida no device %s.\n' "$SUITE" "$DEVICE_ID"
printf 'App principal do layout: %s\n' "$PRIMARY_PACKAGE"
printf 'Foco final solicitado: %s\n' "$FINAL_FOCUS"
