#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

ACTION='status'
DEVICE_ID=''
DISPLAY_ID=0
WINDOWING_MODE=5
PACKAGE_NAME=''
COMPONENT_NAME=''
TASK_ID=''
BOUNDS_TEXT=''
FOCUS_AFTER=1
FORCE_FREEFORM=1

usage() {
  cat <<'EOF'
Uso:
  bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh status
  bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh on
  bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh off
  bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh toggle
  bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh open --package PACKAGE [--bounds 'L T R B']
  bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh resize --package PACKAGE --bounds 'L T R B'
  bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_desktop_mode.sh focus --package PACKAGE

Acoes:
  status   mostra o estado atual do desktop mode Samsung e o foco atual.
  on       garante desktop mode ativo no display padrao.
  off      garante desktop mode desligado no display padrao.
  toggle   alterna o desktop mode no display padrao.
  open     garante desktop mode ativo, abre um app e opcionalmente aplica bounds.
  resize   redimensiona/reposiciona uma task existente.
  focus    traz uma task existente para frente.

Selecao do alvo:
  --device SERIAL          usa explicitamente esse device ADB.
  --display ID             display Android alvo (padrao: 0).
  --package PACKAGE        resolve a activity principal pelo pacote.
  --component PKG/ACT      usa um componente Android explicito.
  --task-id ID             opera sobre uma task ja existente.
  --bounds 'L T R B'       bounds absolutos para resize/reposicionamento.
  --no-focus               nao tenta trazer a task para frente ao final.
  --no-force-freeform      em open, nao passa --windowingMode 5 explicitamente.

Notas:
  - neste Samsung, o estado confiavel do modo desktop vem de `wm shell desktopmode dump`
  - quando desktop mode esta ativo, apps resizable tendem a abrir em FREEFORM automaticamente
  - o helper usa o caminho mais deterministico: pode forcar --windowingMode 5, mover para o desk ativo e aplicar resize explicito
EOF
}

fail() {
  termux::fail "$@"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    status|on|off|toggle|open|resize|focus)
      ACTION="$1"
      shift
      ;;
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
    --task-id)
      shift
      TASK_ID="${1:-}"
      shift || true
      ;;
    --task-id=*)
      TASK_ID="${1#*=}"
      shift
      ;;
    --bounds)
      shift
      BOUNDS_TEXT="${1:-}"
      shift || true
      ;;
    --bounds=*)
      BOUNDS_TEXT="${1#*=}"
      shift
      ;;
    --no-focus)
      FOCUS_AFTER=0
      shift
      ;;
    --no-force-freeform)
      FORCE_FREEFORM=0
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

if [ -n "$BOUNDS_TEXT" ] && ! printf '%s\n' "$BOUNDS_TEXT" | grep -Eq '^[0-9]+ [0-9]+ [0-9]+ [0-9]+$'; then
  fail \
    'validação de --bounds' \
    "Formato inválido: ${BOUNDS_TEXT}" \
    'O helper não consegue reposicionar a janela com bounds malformados.' \
    "Usar --bounds 'L T R B', por exemplo --bounds '150 120 1200 900'."
fi

termux::require_host_command \
  adb \
  'Não é possível controlar o desktop mode Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID="$(termux::resolve_target_device "$DEVICE_ID")"

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'O comando de desktop mode falhou no device Android.' \
    'Corrigir a conectividade ADB ou o erro retornado e repetir a operação.' \
    "$@"
}

desktop_dump() {
  adb -s "$DEVICE_ID" shell wm shell desktopmode dump 2>/dev/null | tr -d '\r'
}

desktop_active() {
  desktop_dump | grep -Fq 'inDesktopWindowing=true'
}

active_desk_id() {
  local dump_output="$1"
  local desk_id

  desk_id="$(
    printf '%s\n' "$dump_output" \
      | sed -nE 's/^[[:space:]]*activeDesk=([0-9]+).*/\1/p' \
      | head -n1
  )"

  if [ -n "$desk_id" ]; then
    printf '%s\n' "$desk_id"
    return 0
  fi

  if ! printf '%s\n' "$dump_output" | grep -Fq 'inDesktopWindowing=true'; then
    return 0
  fi

  printf '%s\n' "$dump_output" \
    | sed -nE 's/^[[:space:]]*Desk #([0-9]+):.*/\1/p' \
    | head -n1
}

wait_for_desktop_state() {
  local expected_state="$1"
  local timeout_seconds="${2:-10}"
  local deadline_seconds

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    if [ "$expected_state" = 'on' ] && desktop_active; then
      return 0
    fi

    if [ "$expected_state" = 'off' ] && ! desktop_active; then
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep 0.5
  done

  return 1
}

toggle_desktop_mode() {
  adb -s "$DEVICE_ID" shell wm shell desktopmode toggleDesktopWindowingInDefaultDisplay >/dev/null 2>&1 || true
}

ensure_desktop_mode() {
  local desired_state="$1"

  case "$desired_state" in
    on)
      if desktop_active; then
        return 0
      fi
      toggle_desktop_mode
      wait_for_desktop_state on 12 || fail \
        'wm shell desktopmode toggleDesktopWindowingInDefaultDisplay' \
        "$(desktop_dump)" \
        'O modo desktop não entrou em estado ativo dentro do tempo esperado.' \
        'Confirmar visualmente o launcher Samsung e repetir a operação.'
      ;;
    off)
      if ! desktop_active; then
        return 0
      fi
      toggle_desktop_mode
      wait_for_desktop_state off 12 || fail \
        'wm shell desktopmode toggleDesktopWindowingInDefaultDisplay' \
        "$(desktop_dump)" \
        'O modo desktop não saiu para o modo tablet dentro do tempo esperado.' \
        'Confirmar visualmente o launcher Samsung e repetir a operação.'
      ;;
    *)
      fail \
        'validação do estado desejado do desktop mode' \
        "Estado inválido: ${desired_state}" \
        'O helper não sabe se deve ligar ou desligar o desktop mode.' \
        'Usar on ou off.'
      ;;
  esac
}

resolve_component() {
  local package_name="$1"
  local resolved_component

  resolved_component="$(
    adb -s "$DEVICE_ID" shell cmd package resolve-activity --brief "$package_name" 2>/dev/null \
      | tr -d '\r' \
      | awk 'NF { line = $0 } END { print line }'
  )"

  if [ -z "$resolved_component" ] || ! printf '%s\n' "$resolved_component" | grep -Fq '/'; then
    fail \
      "cmd package resolve-activity --brief $package_name" \
      "${resolved_component:-sem saída}" \
      'A activity principal do pacote não pôde ser resolvida.' \
      'Confirmar que o app está instalado e repetir a operação.'
  fi

  printf '%s\n' "$resolved_component"
}

task_id_by_package() {
  local package_name="$1"

  adb -s "$DEVICE_ID" shell cmd activity stack list 2>/dev/null | awk -v package_name="$package_name" '
    $0 ~ ("taskId=[0-9]+: " package_name "/") && $0 ~ /visible=true/ {
      line = $0
      sub(/^.*taskId=/, "", line)
      sub(/:.*/, "", line)
      print line
      exit
    }

    $0 ~ ("taskId=[0-9]+: " package_name "/") && fallback == "" {
      fallback = $0
    }

    END {
      if (fallback != "") {
        line = fallback
        sub(/^.*taskId=/, "", line)
        sub(/:.*/, "", line)
        print line
      }
    }
  '
}

resolve_task_id() {
  if [ -n "$TASK_ID" ]; then
    printf '%s\n' "$TASK_ID"
    return 0
  fi

  if [ -z "$PACKAGE_NAME" ]; then
    fail \
      'resolução da task alvo' \
      'Nenhum --task-id nem --package informado.' \
      'O helper não consegue localizar qual janela deve ser manipulada.' \
      'Informar --task-id ID ou --package PACKAGE.'
  fi

  TASK_ID="$(task_id_by_package "$PACKAGE_NAME" || true)"
  if [ -z "$TASK_ID" ]; then
    fail \
      "resolução da task do pacote $PACKAGE_NAME" \
      'Task ausente.' \
      'O app alvo não possui task detectável no momento.' \
      'Abrir o app antes, ou usar a ação open do helper.'
  fi

  printf '%s\n' "$TASK_ID"
}

task_windowing_mode() {
  local task_id="$1"

  adb -s "$DEVICE_ID" shell cmd activity stack list 2>/dev/null | awk -v task_id="$task_id" '
    /^RootTask id=/ {
      current_mode = ""
      next
    }

    /mWindowingMode=/ {
      if (match($0, /mWindowingMode=[^ ]+/)) {
        current_mode = substr($0, RSTART + length("mWindowingMode="), RLENGTH - length("mWindowingMode="))
      }
      next
    }

    $0 ~ ("taskId=" task_id ":") {
      if (current_mode != "") {
        print current_mode
        exit
      }
    }
  '
}

wait_for_task_windowing_mode() {
  local task_id="$1"
  local expected_mode="$2"
  local timeout_seconds="${3:-10}"
  local deadline_seconds
  local current_mode

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    current_mode="$(task_windowing_mode "$task_id" || true)"
    if [ "$current_mode" = "$expected_mode" ]; then
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep 0.3
  done

  return 1
}

ensure_task_in_active_desk() {
  local task_id="$1"
  local desk_id="$2"
  local current_mode

  current_mode="$(task_windowing_mode "$task_id" || true)"
  if [ "$current_mode" = 'freeform' ]; then
    return 0
  fi

  adb -s "$DEVICE_ID" shell wm shell desktopmode moveTaskToDesk "$task_id" "$desk_id" >/dev/null 2>&1 || true

  wait_for_task_windowing_mode "$task_id" freeform 10 || fail \
    "wm shell desktopmode moveTaskToDesk $task_id $desk_id" \
    "$(adb -s "$DEVICE_ID" shell dumpsys activity containers 2>/dev/null | tr -d '\r')" \
    'A task não entrou em FREEFORM depois da conversão para o desk ativo.' \
    'Confirmar que o modo desktop segue ativo e repetir a operação.'
}

resize_task_to_bounds() {
  local task_id="$1"
  local bounds_text="$2"
  local left
  local top
  local right
  local bottom

  read -r left top right bottom <<<"$bounds_text"

  adb -s "$DEVICE_ID" shell cmd activity task resizeable "$task_id" 3 >/dev/null 2>&1 || true
  run_adb shell cmd activity task resize "$task_id" "$left" "$top" "$right" "$bottom" >/dev/null
}

focus_task() {
  local task_id="$1"
  local component_name="${2:-}"

  if desktop_active; then
    adb -s "$DEVICE_ID" shell wm shell desktopmode moveTaskToFront "$task_id" >/dev/null 2>&1 || true
    sleep 0.5
  fi

  if [ -n "$component_name" ]; then
    adb -s "$DEVICE_ID" shell cmd activity start-activity \
      --display "$DISPLAY_ID" \
      --activity-reorder-to-front \
      -n "$component_name" \
      >/dev/null 2>&1 || true
    sleep 0.5
  fi
}

print_status() {
  local dump_output
  local desktop_state='inactive'
  local desk_id='none'
  local focus_output

  dump_output="$(desktop_dump)"
  if printf '%s\n' "$dump_output" | grep -Fq 'inDesktopWindowing=true'; then
    desktop_state='active'
  fi

  desk_id="$(active_desk_id "$dump_output" || true)"
  if [ -z "$desk_id" ]; then
    desk_id='none'
  fi

  focus_output="$(termux::current_focus "$DEVICE_ID" 2>/dev/null || true)"

  printf 'DEVICE=%s\n' "$DEVICE_ID"
  printf 'DESKTOP_MODE=%s\n' "$desktop_state"
  printf 'ACTIVE_DESK=%s\n' "$desk_id"
  printf '%s\n' "$focus_output"
  printf '%s\n' "$dump_output" | sed -n '1,60p'
}

open_action() {
  local component_name
  local resolved_task_id
  local desk_id

  ensure_desktop_mode on

  component_name="$COMPONENT_NAME"
  if [ -z "$component_name" ]; then
    if [ -z "$PACKAGE_NAME" ]; then
      fail \
        'abertura de app no desktop mode' \
        'Nenhum --package nem --component informado.' \
        'O helper não sabe qual app deve abrir em janela.' \
        'Usar --package PACKAGE ou --component PKG/ACT.'
    fi
    component_name="$(resolve_component "$PACKAGE_NAME")"
  fi

  if [ "$FORCE_FREEFORM" -eq 1 ]; then
    run_adb shell cmd activity start-activity \
      --display "$DISPLAY_ID" \
      --windowingMode "$WINDOWING_MODE" \
      -W \
      -n "$component_name" >/dev/null
  else
    run_adb shell cmd activity start-activity \
      --display "$DISPLAY_ID" \
      -W \
      -n "$component_name" >/dev/null
  fi

  resolved_task_id="$(termux::wait_for_activity_task_id "$DEVICE_ID" "$component_name" 10 0.25 || true)"
  if [ -z "$resolved_task_id" ]; then
    fail \
      "abertura da activity $component_name" \
      'A activity foi iniciada, mas nenhuma task detectável apareceu a tempo.' \
      'O helper não consegue aplicar foco ou resize sem task id.' \
      'Repetir a operação ou abrir o app manualmente uma vez.'
  fi

  TASK_ID="$resolved_task_id"
  PACKAGE_NAME="${component_name%%/*}"

  desk_id="$(active_desk_id "$(desktop_dump)" || true)"
  if [ -n "$desk_id" ]; then
    ensure_task_in_active_desk "$TASK_ID" "$desk_id"
  fi

  if [ -n "$BOUNDS_TEXT" ]; then
    resize_task_to_bounds "$TASK_ID" "$BOUNDS_TEXT"
  fi

  if [ "$FOCUS_AFTER" -eq 1 ]; then
    focus_task "$TASK_ID" "$component_name"
  fi

  printf 'OPENED task=%s component=%s\n' "$TASK_ID" "$component_name"
  adb -s "$DEVICE_ID" shell cmd activity stack list | sed -n "/taskId=${TASK_ID}:/,+2p"
}

resize_action() {
  local resolved_task_id

  [ -n "$BOUNDS_TEXT" ] || fail \
    'resize de janela no desktop mode' \
    'Nenhum --bounds informado.' \
    'O helper não sabe para onde mover ou redimensionar a janela.' \
    "Usar --bounds 'L T R B'."

  resolved_task_id="$(resolve_task_id)"
  resize_task_to_bounds "$resolved_task_id" "$BOUNDS_TEXT"

  if [ "$FOCUS_AFTER" -eq 1 ]; then
    focus_task "$resolved_task_id" "$COMPONENT_NAME"
  fi

  printf 'RESIZED task=%s bounds=[%s]\n' "$resolved_task_id" "$BOUNDS_TEXT"
  adb -s "$DEVICE_ID" shell cmd activity stack list | sed -n "/taskId=${resolved_task_id}:/,+2p"
}

focus_action() {
  local resolved_task_id
  local component_name="$COMPONENT_NAME"

  if [ -z "$component_name" ] && [ -n "$PACKAGE_NAME" ]; then
    component_name="$(resolve_component "$PACKAGE_NAME")"
  fi

  resolved_task_id="$(resolve_task_id)"
  if desktop_active; then
    focus_task "$resolved_task_id"
  else
    focus_task "$resolved_task_id" "$component_name"
  fi

  printf 'FOCUSED task=%s\n' "$resolved_task_id"
  termux::current_focus "$DEVICE_ID" || true
}

case "$ACTION" in
  status)
    print_status
    ;;
  on)
    ensure_desktop_mode on
    print_status
    ;;
  off)
    ensure_desktop_mode off
    print_status
    ;;
  toggle)
    toggle_desktop_mode
    sleep 1
    print_status
    ;;
  open)
    open_action
    ;;
  resize)
    resize_action
    ;;
  focus)
    focus_action
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
