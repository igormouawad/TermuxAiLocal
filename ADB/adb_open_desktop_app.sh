#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/termux_common.sh
source "${WORKSPACE_ROOT}/lib/termux_common.sh"
# shellcheck source=../lib/android_desktop_layout.sh
source "${WORKSPACE_ROOT}/lib/android_desktop_layout.sh"

DEVICE_ID=''
DISPLAY_ID=0
PACKAGE_NAME=''
COMPONENT_NAME=''
SSH_PACKAGE='com.server.auditor.ssh.client'
WITH_OPENBOX=0
FOCUS_TARGET='auto'
REFLOW_ONLY=0
TOTAL_STEPS=5
CURRENT_STEP=0
AUDIT_OWNER=0
SSH_MODE='auto'
SSH_ENABLED=1

BASE_LAYOUT_WIDTH=2496
BASE_LAYOUT_HEIGHT=1392
SAFE_INNER_MARGIN_LEFT=32
SAFE_INNER_MARGIN_TOP=24
SAFE_INNER_MARGIN_RIGHT=32
SAFE_INNER_MARGIN_BOTTOM=10
BASE_NOEXTRA_X11_BOUNDS='0 0 828 710'
BASE_NOEXTRA_TERMUX_BOUNDS='0 746 828 1392'
BASE_NOEXTRA_SSH_BOUNDS='860 746 2496 1392'
BASE_NOEXTRA_PRIMARY_BOUNDS='860 0 2496 710'
BASE_EXTRA_X11_BOUNDS='0 0 828 710'
BASE_EXTRA_TERMUX_BOUNDS='0 746 828 1392'
BASE_EXTRA_PRIMARY_BOUNDS='860 0 2496 710'
BASE_EXTRA_SSH_BOUNDS='860 746 1670 1392'
BASE_EXTRA_SECONDARY_BOUNDS='1686 746 2496 1392'
BASE_WORKSTATION_FIXED_X11_BOUNDS='1097 0 2496 848'
BASE_WORKSTATION_REDUCED_TERMUX_BOUNDS='0 0 1073 646'
BASE_WORKSTATION_PRIMARY_BOUNDS='0 653 1073 1392'
BASE_WORKSTATION_MULTIAPP_X11_BOUNDS='1097 0 2496 710'
BASE_WORKSTATION_SECONDARY_BOUNDS='1097 746 2496 1392'

TARGET_PACKAGE=''
TARGET_COMPONENT=''
TARGET_TASK_ID=''
DESK_ID=''
DISPLAY_BOUNDS=''
X11_BOUNDS=''
TERMUX_BOUNDS=''
SSH_BOUNDS=''
PRIMARY_BOUNDS=''
SECONDARY_AREA_BOUNDS=''
USABLE_BOUNDS=''
TERMUX_TASK_ID=''
X11_TASK_ID=''
SSH_TASK_ID=''
SECONDARY_TASK_IDS=()
SECONDARY_PACKAGES=()

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
  bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_open_desktop_app.sh --package PACKAGE
  bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_open_desktop_app.sh --component PKG/ACT

Opcoes:
  --device SERIAL          usa explicitamente esse alvo ADB
  --package PACKAGE        resolve a activity principal pelo pacote
  --component PKG/ACT      usa uma activity explicita
  --display ID             display Android alvo (padrao: 0)
  --ssh-package PACKAGE    pacote do cliente SSH no trio auxiliar
  --with-ssh              força o cliente SSH como janela auxiliar
  --without-ssh           omite o cliente SSH e amplia o Termux
  --with-openbox           garante a sessao Openbox antes da abertura do app
  --focus auto|app|termux|x11|ssh
  --reflow-only            reaplica o layout atual sem abrir um novo app

Politica visual:
  - desktop mode Samsung sempre ativo
  - app alvo em janela principal
  - Termux:X11, Termux e SSH continuam visiveis em janelas auxiliares
  - apps extras visiveis entram em grade compacta abaixo do app principal
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

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A abertura do app no desktop mode foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e repetir a operacao.' \
    "$@"
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
    'O helper host-side chamado por esta abertura falhou.' \
    'Inspecionar a saida retornada e repetir a operacao.'

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
    --display)
      shift
      DISPLAY_ID="${1:-0}"
      shift || true
      ;;
    --display=*)
      DISPLAY_ID="${1#*=}"
      shift
      ;;
    --package)
      shift
      PACKAGE_NAME="${1:-}"
      shift || true
      ;;
    --package=*)
      PACKAGE_NAME="${1#*=}"
      shift
      ;;
    --component)
      shift
      COMPONENT_NAME="${1:-}"
      shift || true
      ;;
    --component=*)
      COMPONENT_NAME="${1#*=}"
      shift
      ;;
    --ssh-package)
      shift
      SSH_PACKAGE="${1:-$SSH_PACKAGE}"
      shift || true
      ;;
    --ssh-package=*)
      SSH_PACKAGE="${1#*=}"
      shift
      ;;
    --with-ssh)
      SSH_MODE='on'
      shift
      ;;
    --without-ssh)
      SSH_MODE='off'
      shift
      ;;
    --with-openbox)
      WITH_OPENBOX=1
      shift
      ;;
    --reflow-only)
      REFLOW_ONLY=1
      shift
      ;;
    --focus)
      shift
      FOCUS_TARGET="${1:-auto}"
      shift || true
      ;;
    --focus=*)
      FOCUS_TARGET="${1#*=}"
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

if [ -n "$COMPONENT_NAME" ] && [ -z "$PACKAGE_NAME" ]; then
  PACKAGE_NAME="${COMPONENT_NAME%%/*}"
fi

if [ "$REFLOW_ONLY" -ne 1 ]; then
  [ -n "$PACKAGE_NAME" ] || fail \
    'validacao de argumentos' \
    'Nenhum --package nem --component informado.' \
    'O helper nao sabe qual app Android deve abrir em modo desktop.' \
    'Usar --package PACKAGE ou --component PKG/ACT.'
fi

case "$FOCUS_TARGET" in
  auto|app|termux|x11|ssh)
    ;;
  *)
    fail \
      'validacao de argumentos' \
      "Foco final invalido: $FOCUS_TARGET" \
      'O helper nao sabe qual janela deve receber o foco final.' \
      'Usar --focus auto, --focus app, --focus termux, --focus x11 ou --focus ssh.'
      ;;
esac

DEVICE_ID="$(termux::resolve_target_device "$DEVICE_ID")"
termux::audit_session_begin 'Abertura de app Android em desktop mode' "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
termux::prechange_audit_gate 'Abertura de app Android em desktop mode' 'desktop_app_launch' "$DEVICE_ID"

resolve_ssh_enabled() {
  case "$SSH_MODE" in
    on)
      printf '1\n'
      ;;
    off)
      printf '0\n'
      ;;
    *)
      if [ "$(termux::operator_context)" = 'android_ssh' ]; then
        printf '1\n'
      else
        printf '0\n'
      fi
      ;;
  esac
}

SSH_ENABLED="$(resolve_ssh_enabled)"

resolve_focus_target() {
  if [ "$FOCUS_TARGET" != 'auto' ]; then
    printf '%s\n' "$FOCUS_TARGET"
    return 0
  fi

  if [ "$(termux::operator_context)" = 'android_ssh' ]; then
    printf '%s\n' 'ssh'
    return 0
  fi

  printf '%s\n' 'app'
}

FOCUS_TARGET="$(resolve_focus_target)"

if [ "$SSH_ENABLED" -eq 0 ] && [ "$FOCUS_TARGET" = 'ssh' ]; then
  fail \
    'validacao de argumentos' \
    'Foco final em ssh solicitado, mas o layout atual está configurado sem cliente SSH.' \
    'No workstation local o Terminus não deve ser reaberto por padrão.' \
    'Usar --with-ssh ou escolher foco em app, termux ou x11.'
fi

if [ -n "$PACKAGE_NAME" ] || [ -n "$COMPONENT_NAME" ]; then
  TARGET_COMPONENT="${COMPONENT_NAME:-$(desktop::resolve_component "$DEVICE_ID" "$PACKAGE_NAME" || true)}"
  [ -n "$TARGET_COMPONENT" ] || fail \
    "cmd package resolve-activity --brief $PACKAGE_NAME" \
    'A activity principal do pacote nao foi resolvida.' \
    'O helper nao consegue abrir o app alvo no desktop sem um componente valido.' \
    'Confirmar que o pacote esta instalado e repetir.'

TARGET_PACKAGE="${TARGET_COMPONENT%%/*}"

if [ "$SSH_ENABLED" -eq 0 ] && [ "$TARGET_PACKAGE" = "$SSH_PACKAGE" ]; then
  fail \
    'validacao da política de desktop do workstation' \
    'O pacote alvo é o cliente SSH, mas o contexto atual está configurado sem Terminus.' \
    'A diretiva consolidada para workstation local omite o Terminus do layout.' \
    'Usar --with-ssh se a reabertura do cliente SSH for realmente necessária.'
fi
fi

core_focus_target() {
  case "$TARGET_PACKAGE" in
    com.termux)
      printf '%s\n' 'termux'
      ;;
    com.termux.x11)
      printf '%s\n' 'x11'
      ;;
    "$SSH_PACKAGE")
      printf '%s\n' 'ssh'
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_core_workspace() {
  local helper_args=()

  if [ "$WITH_OPENBOX" -eq 0 ]; then
    helper_args+=(--no-openbox)
  fi

  if [ "$SSH_ENABLED" -eq 1 ]; then
    helper_args+=(--with-ssh)
  else
    helper_args+=(--without-ssh)
  fi

  case "$FOCUS_TARGET" in
    ssh|termux|x11)
      helper_args+=(--focus "$FOCUS_TARGET")
      ;;
    *)
      if [ "$SSH_ENABLED" -eq 1 ]; then
        helper_args+=(--focus ssh)
      else
        helper_args+=(--focus termux)
      fi
      ;;
  esac

  run_workspace_helper "ADB/adb_consolidate_desktop_mode.sh" "${helper_args[@]}" >/dev/null
}

refresh_core_tasks() {
  TERMUX_TASK_ID="$(desktop::task_id_by_package "$DEVICE_ID" 'com.termux' || true)"
  X11_TASK_ID="$(desktop::task_id_by_package "$DEVICE_ID" 'com.termux.x11' || true)"
  if [ "$SSH_ENABLED" -eq 1 ]; then
    SSH_TASK_ID="$(desktop::task_id_by_package "$DEVICE_ID" "$SSH_PACKAGE" || true)"
  else
    SSH_TASK_ID=''
  fi

  [ -n "$TERMUX_TASK_ID" ] || fail \
    'resolucao da task do Termux' \
    'task ausente' \
    'O app Termux nao ficou visivel no desktop antes de abrir o app alvo.' \
    'Repetir a consolidacao do trio e tentar novamente.'

  [ -n "$X11_TASK_ID" ] || fail \
    'resolucao da task do Termux:X11' \
    'task ausente' \
    'O app Termux:X11 nao ficou visivel no desktop antes de abrir o app alvo.' \
    'Repetir a consolidacao do trio e tentar novamente.'

  if [ "$SSH_ENABLED" -eq 1 ]; then
    [ -n "$SSH_TASK_ID" ] || fail \
      "resolucao da task do cliente SSH $SSH_PACKAGE" \
      'task ausente' \
      'O cliente SSH nao ficou visivel no desktop antes de abrir o app alvo.' \
      'Repetir a consolidacao do trio e tentar novamente.'
  fi
}

collect_secondary_tasks() {
  local task_id
  local package_name
  SECONDARY_TASK_IDS=()
  SECONDARY_PACKAGES=()

  while IFS=$'\t' read -r task_id package_name _; do
    [ -n "$task_id" ] || continue
    [ -n "$package_name" ] || continue

    case "$package_name" in
      "$TARGET_PACKAGE"|com.termux|com.termux.x11|"$SSH_PACKAGE"|com.termux.api|com.sec.android.app.launcher|com.android.launcher3|com.android.systemui)
        continue
        ;;
    esac

    case "$task_id" in
      "$TARGET_TASK_ID"|"$TERMUX_TASK_ID"|"$X11_TASK_ID"|"$SSH_TASK_ID")
        continue
        ;;
    esac

    SECONDARY_TASK_IDS+=("$task_id")
    SECONDARY_PACKAGES+=("$package_name")
  done < <(desktop::visible_task_table "$DEVICE_ID" | sort -rn)
}

compute_scaled_layout() {
  local usable_left
  local usable_top
  local usable_right
  local usable_bottom
  local display_left
  local display_top
  local display_right
  local display_bottom
  local display_width
  local display_height

  read -r usable_left usable_top usable_right usable_bottom <<<"$(desktop::usable_bounds "$DEVICE_ID")"
  display_left=$((usable_left + SAFE_INNER_MARGIN_LEFT))
  display_top=$((usable_top + SAFE_INNER_MARGIN_TOP))
  display_right=$((usable_right - SAFE_INNER_MARGIN_RIGHT))
  display_bottom=$((usable_bottom - SAFE_INNER_MARGIN_BOTTOM))
  display_width=$((display_right - display_left))
  display_height=$((display_bottom - display_top))

  DISPLAY_BOUNDS="${display_left} ${display_top} ${display_right} ${display_bottom}"
  USABLE_BOUNDS="${usable_left} ${usable_top} ${usable_right} ${usable_bottom}"

  if [ "$SSH_ENABLED" -eq 1 ]; then
    if [ "${#SECONDARY_TASK_IDS[@]}" -eq 0 ]; then
      X11_BOUNDS="$(desktop::scale_bounds "$BASE_NOEXTRA_X11_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      TERMUX_BOUNDS="$(desktop::scale_bounds "$BASE_NOEXTRA_TERMUX_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      SSH_BOUNDS="$(desktop::scale_bounds "$BASE_NOEXTRA_SSH_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      PRIMARY_BOUNDS="$(desktop::scale_bounds "$BASE_NOEXTRA_PRIMARY_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      SECONDARY_AREA_BOUNDS=''
    else
      X11_BOUNDS="$(desktop::scale_bounds "$BASE_EXTRA_X11_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      TERMUX_BOUNDS="$(desktop::scale_bounds "$BASE_EXTRA_TERMUX_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      SSH_BOUNDS="$(desktop::scale_bounds "$BASE_EXTRA_SSH_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      PRIMARY_BOUNDS="$(desktop::scale_bounds "$BASE_EXTRA_PRIMARY_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      SECONDARY_AREA_BOUNDS="$(desktop::scale_bounds "$BASE_EXTRA_SECONDARY_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
    fi
  else
    SSH_BOUNDS=''
    TERMUX_BOUNDS="$(desktop::scale_bounds "$BASE_WORKSTATION_REDUCED_TERMUX_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
    PRIMARY_BOUNDS="$(desktop::scale_bounds "$BASE_WORKSTATION_PRIMARY_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"

    if [ "${#SECONDARY_TASK_IDS[@]}" -eq 0 ]; then
      X11_BOUNDS="$(desktop::scale_bounds "$BASE_WORKSTATION_FIXED_X11_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      SECONDARY_AREA_BOUNDS=''
    else
      X11_BOUNDS="$(desktop::scale_bounds "$BASE_WORKSTATION_MULTIAPP_X11_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
      SECONDARY_AREA_BOUNDS="$(desktop::scale_bounds "$BASE_WORKSTATION_SECONDARY_BOUNDS" "$BASE_LAYOUT_WIDTH" "$BASE_LAYOUT_HEIGHT" "$display_left" "$display_top" "$display_width" "$display_height")"
    fi
  fi
}

secondary_grid_shape() {
  local count="$1"
  local rows=1
  local cols=1

  if [ "$count" -le 1 ]; then
    rows=1
    cols=1
  elif [ "$count" -le 3 ]; then
    rows=1
    cols="$count"
  elif [ "$count" -le 6 ]; then
    rows=2
    cols=$(((count + 1) / 2))
  elif [ "$count" -le 12 ]; then
    rows=3
    cols=$(((count + 2) / 3))
  else
    rows=4
    cols=$(((count + 3) / 4))
  fi

  printf '%s %s\n' "$rows" "$cols"
}

secondary_grid_bounds() {
  local index="$1"
  local count="$2"
  local rows
  local cols
  local left
  local top
  local right
  local bottom
  local width
  local height
  local cell_width
  local cell_height
  local row
  local col
  local cell_left
  local cell_top
  local cell_right
  local cell_bottom

  read -r rows cols <<<"$(secondary_grid_shape "$count")"
  read -r left top right bottom <<<"$SECONDARY_AREA_BOUNDS"

  width=$((right - left))
  height=$((bottom - top))
  cell_width=$((width / cols))
  cell_height=$((height / rows))
  row=$((index / cols))
  col=$((index % cols))

  cell_left=$((left + (col * cell_width)))
  cell_top=$((top + (row * cell_height)))

  if [ "$col" -eq $((cols - 1)) ]; then
    cell_right="$right"
  else
    cell_right=$((cell_left + cell_width))
  fi

  if [ "$row" -eq $((rows - 1)) ]; then
    cell_bottom="$bottom"
  else
    cell_bottom=$((cell_top + cell_height))
  fi

  printf '%s %s %s %s\n' "$cell_left" "$cell_top" "$cell_right" "$cell_bottom"
}

ensure_task_on_desktop() {
  local task_id="$1"
  local label="$2"

  if ! desktop::ensure_task_in_active_desk "$DEVICE_ID" "$task_id" "$DESK_ID"; then
    fail \
      "desktopmode moveTaskToDesk $task_id $DESK_ID" \
      "$(adb -s "$DEVICE_ID" shell wm shell desktopmode dump 2>/dev/null | tr -d '\r')" \
      "A task $label nao ficou visivel no desk ativo do desktop mode." \
      'Confirmar que o desktop mode segue ativo e repetir a operacao.'
  fi
}

resize_task() {
  local task_id="$1"
  local bounds_text="$2"
  local label="$3"

  run_adb shell cmd activity task resizeable "$task_id" 3 >/dev/null
  run_adb shell cmd activity task resize "$task_id" ${bounds_text} >/dev/null
  printf '%s task=%s bounds=[%s]\n' "$label" "$task_id" "$bounds_text"
}

focus_selected_window() {
  local task_id="$1"
  local bounds_text="$2"
  local focus_token="$3"
  local component_name="${4:-}"
  local left
  local top
  local right
  local bottom
  local tap_x
  local tap_y

  read -r left top right bottom <<<"$bounds_text"
  tap_x=$(((left + right) / 2))
  tap_y=$(((top + bottom) / 2))

  desktop::focus_task "$DEVICE_ID" "$DISPLAY_ID" "$task_id" "$component_name"
  run_adb shell input tap "$tap_x" "$tap_y" >/dev/null

  if ! wait_for_focused_task "$task_id" 8 0.25; then
    if [ -n "$focus_token" ] && termux::wait_for_focus "$DEVICE_ID" "$focus_token" 2 0.25 >/dev/null 2>&1; then
      return 0
    fi
    fail \
      "foco final na task $task_id" \
      "$(termux::current_focus "$DEVICE_ID")" \
      'O Android nao trouxe a janela selecionada para frente.' \
      'Tocar manualmente na janela desejada no tablet ou repetir a operacao.'
  fi
}

wait_for_focused_task() {
  local task_id="$1"
  local timeout_seconds="${2:-8}"
  local poll_interval_seconds="${3:-0.25}"
  local deadline_seconds
  local focus_output

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    focus_output="$(adb -s "$DEVICE_ID" shell dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' | tail -6 2>/dev/null || true)"

    if printf '%s\n' "$focus_output" | grep -Fq " t${task_id}"; then
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep "$poll_interval_seconds"
  done

  return 1
}

open_target_app() {
  desktop::start_desktop_activity "$DEVICE_ID" "$DISPLAY_ID" "$TARGET_COMPONENT"

  TARGET_TASK_ID="$(termux::wait_for_activity_task_id "$DEVICE_ID" "$TARGET_COMPONENT" 10 0.25 || true)"
  [ -n "$TARGET_TASK_ID" ] || fail \
    "abertura da activity $TARGET_COMPONENT" \
    'A activity foi iniciada, mas nenhuma task detectavel apareceu a tempo.' \
    'Sem task id o helper nao consegue aplicar o layout visual.' \
    'Repetir a operacao ou abrir o app manualmente uma vez.'
}

resolve_existing_target_app() {
  local task_id
  local package_name

  if [ -n "$TARGET_PACKAGE" ]; then
    TARGET_TASK_ID="$(desktop::task_id_by_package "$DEVICE_ID" "$TARGET_PACKAGE" || true)"
    [ -n "$TARGET_TASK_ID" ] || fail \
      "resolucao da task atual para ${TARGET_PACKAGE}" \
      'task ausente' \
      'O modo --reflow-only foi pedido, mas o app alvo nao esta visivel no desktop.' \
      'Abrir o app primeiro com --package PACKAGE ou repetir o reflow quando ele estiver visivel.'
    return 0
  fi

  while IFS=$'\t' read -r task_id package_name _; do
    [ -n "$task_id" ] || continue
    [ -n "$package_name" ] || continue

    case "$package_name" in
      com.termux|com.termux.x11|"$SSH_PACKAGE"|com.termux.api|com.sec.android.app.launcher|com.android.launcher3|com.android.systemui)
        continue
        ;;
    esac

    TARGET_TASK_ID="$task_id"
    TARGET_PACKAGE="$package_name"
    TARGET_COMPONENT="$(desktop::resolve_component "$DEVICE_ID" "$TARGET_PACKAGE" || true)"
    return 0
  done < <(desktop::visible_task_table "$DEVICE_ID" | sort -rn)

  fail \
    'resolucao do app extra visivel para reflow' \
    'nenhuma task extra visivel encontrada' \
    'O helper nao encontrou um app extra visivel para reaplicar o layout Foco grande.' \
    'Abrir um app Android com --package PACKAGE antes de usar --reflow-only.'
}

apply_focus_large_layout() {
  local secondary_count="${#SECONDARY_TASK_IDS[@]}"
  local index=0
  local secondary_bounds

  ensure_task_on_desktop "$TARGET_TASK_ID" "$TARGET_PACKAGE"
  ensure_task_on_desktop "$X11_TASK_ID" 'Termux:X11'
  ensure_task_on_desktop "$TERMUX_TASK_ID" 'Termux'
  if [ "$SSH_ENABLED" -eq 1 ]; then
    ensure_task_on_desktop "$SSH_TASK_ID" 'SSH'
  fi

  for index in "${!SECONDARY_TASK_IDS[@]}"; do
    ensure_task_on_desktop "${SECONDARY_TASK_IDS[$index]}" "${SECONDARY_PACKAGES[$index]}"
  done

  compute_scaled_layout

  resize_task "$TARGET_TASK_ID" "$PRIMARY_BOUNDS" "$TARGET_PACKAGE"
  resize_task "$X11_TASK_ID" "$X11_BOUNDS" 'Termux:X11'
  resize_task "$TERMUX_TASK_ID" "$TERMUX_BOUNDS" 'Termux'
  if [ "$SSH_ENABLED" -eq 1 ]; then
    resize_task "$SSH_TASK_ID" "$SSH_BOUNDS" 'SSH'
  fi

  if [ "$secondary_count" -gt 0 ]; then
    for index in "${!SECONDARY_TASK_IDS[@]}"; do
      secondary_bounds="$(secondary_grid_bounds "$index" "$secondary_count")"
      resize_task "${SECONDARY_TASK_IDS[$index]}" "$secondary_bounds" "${SECONDARY_PACKAGES[$index]}"
    done
  fi
}

if core_focus="$(core_focus_target 2>/dev/null)"; then
  step_begin "App alvo faz parte do trio base; reaplicando o layout canônico com foco em ${core_focus}"
  if [ "$WITH_OPENBOX" -eq 1 ]; then
    run_workspace_helper "ADB/adb_consolidate_desktop_mode.sh" --focus "$core_focus" >/dev/null
  else
    run_workspace_helper "ADB/adb_consolidate_desktop_mode.sh" --no-openbox --focus "$core_focus" >/dev/null
  fi
  step_ok "Layout canônico reaplicado com foco em ${core_focus}."
  exit 0
fi

step_begin 'Garantindo o desktop mode e o trio base antes de abrir o app alvo'
ensure_core_workspace
step_ok 'Desktop mode ativo e trio base visível.'

step_begin "$(
  if [ "$REFLOW_ONLY" -eq 1 ]; then
    printf '%s' 'Resolvendo o app visível que deve permanecer como janela principal'
  else
    printf 'Abrindo %s como janela principal no desktop mode' "$TARGET_PACKAGE"
  fi
)"
DESK_ID="$(desktop::active_desk_id "$DEVICE_ID" || true)"
[ -n "$DESK_ID" ] || fail \
  'wm shell desktopmode dump' \
  "$(desktop::dump "$DEVICE_ID")" \
  'O Android não expôs um desk ativo para o modo desktop.' \
  'Confirmar que o tablet está em desktop mode e repetir a operação.'
if [ "$REFLOW_ONLY" -eq 1 ]; then
  resolve_existing_target_app
  step_ok "A task atual de ${TARGET_PACKAGE} foi detectada para o reflow."
else
  open_target_app
  step_ok "A task principal de ${TARGET_PACKAGE} foi detectada."
fi

step_begin 'Coletando o trio base e possíveis apps auxiliares já visíveis'
refresh_core_tasks
collect_secondary_tasks
step_ok "Core trio detectado e ${#SECONDARY_TASK_IDS[@]} app(s) extra(s) adicional(is) mapeado(s)."

step_begin 'Aplicando o layout Foco grande e redimensionando as janelas visíveis'
apply_focus_large_layout
step_ok 'Layout visual reaplicado com janela principal dominante.'

step_begin "Entregando o foco final para ${FOCUS_TARGET}"
case "$FOCUS_TARGET" in
  app)
    focus_selected_window "$TARGET_TASK_ID" "$PRIMARY_BOUNDS" "${TARGET_PACKAGE}/" "$TARGET_COMPONENT"
    ;;
  termux)
    focus_selected_window "$TERMUX_TASK_ID" "$TERMUX_BOUNDS" 'com.termux/' 'com.termux/.app.TermuxActivity'
    ;;
  x11)
    focus_selected_window "$X11_TASK_ID" "$X11_BOUNDS" 'com.termux.x11/' 'com.termux.x11/.MainActivity'
    ;;
  ssh)
    focus_selected_window "$SSH_TASK_ID" "$SSH_BOUNDS" "${SSH_PACKAGE}/"
    ;;
esac
step_ok "Foco final entregue para ${FOCUS_TARGET}."

printf 'Desktop mode preparado no device %s.\n' "$DEVICE_ID"
printf 'App alvo: %s\n' "$TARGET_COMPONENT"
printf 'Task alvo: %s\n' "$TARGET_TASK_ID"
printf 'Area util: [%s]\n' "$USABLE_BOUNDS"
printf 'Area interna: [%s]\n' "$DISPLAY_BOUNDS"
printf 'Bounds principais: [%s]\n' "$PRIMARY_BOUNDS"
if [ "$SSH_ENABLED" -eq 1 ]; then
  printf 'Bounds auxiliares: X11=[%s] TERMUX=[%s] SSH=[%s]\n' "$X11_BOUNDS" "$TERMUX_BOUNDS" "$SSH_BOUNDS"
else
  printf 'Bounds auxiliares: X11=[%s] TERMUX=[%s] SSH=[omitido]\n' "$X11_BOUNDS" "$TERMUX_BOUNDS"
fi
printf 'Apps auxiliares extras: %s\n' "${#SECONDARY_TASK_IDS[@]}"
printf 'Foco final: %s\n' "$FOCUS_TARGET"
