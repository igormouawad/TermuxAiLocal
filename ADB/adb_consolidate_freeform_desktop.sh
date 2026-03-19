#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

TERMUX_COMPONENT='com.termux/.app.TermuxActivity'
TERMUX_TOKEN='com.termux/.app.TermuxActivity'
X11_COMPONENT='com.termux.x11/.MainActivity'
X11_TOKEN='com.termux.x11/.MainActivity'
SSH_PACKAGE='com.server.auditor.ssh.client'
SSH_TOKEN='com.server.auditor.ssh.client/'
OPENBOX_PROFILE='openbox-maxperf'
FOCUS_TARGET='ssh'
RESTART_APPS=0
ENSURE_OPENBOX=1
WINDOWING_MODE=5
DISPLAY_ID=0
DESK_ID=''
BASE_DISPLAY_WIDTH=2560
BASE_DISPLAY_HEIGHT=1600
BASE_TERMUX_BOUNDS='32 96 1105 742'
BASE_SSH_BOUNDS='32 749 1105 1488'
BASE_X11_BOUNDS='1129 96 2528 944'
X11_UI_REMOTE='/sdcard/Download/adb_consolidate_freeform_desktop.xml'
X11_UI_LOCAL="$(mktemp)"

cleanup() {
  rm -f "$X11_UI_LOCAL"
}

trap cleanup EXIT

usage() {
  printf 'Uso: %s [--restart] [--no-openbox] [--focus termux|x11|ssh] [--ssh-package PACKAGE] [--profile openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp]\n' "$0"
  printf '  --restart     fecha Termux, Termux:X11 e o cliente SSH antes de reabrir tudo em freeform.\n'
  printf '  --no-openbox  apenas consolida as janelas; não sobe a sessão Openbox/X11.\n'
  printf '  --focus       escolhe a janela final em foco: termux, x11 ou ssh.\n'
  printf '  --ssh-package pacote Android do cliente SSH a ser posicionado na coluna esquerda inferior.\n'
  printf '  --profile     perfil Openbox a garantir quando a sessão X11 estiver inativa.\n'
  printf 'Layout aprovado no tablet atual: Termux no topo esquerdo, SSH embaixo à esquerda e Termux:X11 à direita sem sobras pretas acima/abaixo.\n'
}

fail() {
  termux::fail "$@"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart)
      RESTART_APPS=1
      shift
      ;;
    --no-openbox)
      ENSURE_OPENBOX=0
      shift
      ;;
    --focus)
      shift
      FOCUS_TARGET="${1:-ssh}"
      shift || true
      ;;
    --focus=*)
      FOCUS_TARGET="${1#*=}"
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
    --profile)
      shift
      OPENBOX_PROFILE="${1:-$OPENBOX_PROFILE}"
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
    *)
      usage >&2
      exit 1
      ;;
  esac
done

case "$FOCUS_TARGET" in
  termux|x11|ssh)
    ;;
  *)
    fail \
      'validação de argumentos' \
      "Foco final inválido: $FOCUS_TARGET" \
      'O helper não sabe qual janela deve receber foco ao final da consolidação.' \
      'Usar --focus termux, --focus x11 ou --focus ssh.'
      ;;
esac

if ! termux::openbox_profile_valid "$OPENBOX_PROFILE"; then
  fail \
    'validação de argumentos' \
    "Perfil Openbox inválido: $OPENBOX_PROFILE" \
    'A consolidação não consegue garantir uma sessão gráfica com perfil desconhecido.' \
    'Usar openbox-stable, openbox-maxperf, openbox-compat ou openbox-vulkan-exp.'
fi

termux::require_host_command \
  adb \
  'Não é possível consolidar o desktop Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID="$(termux::resolve_target_device)"

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A consolidação do desktop freeform foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

termux_command() {
  local command_text="$1"
  shift

  bash "${SCRIPT_DIR}/adb_termux_send_command.sh" \
    --device "$DEVICE_ID" \
    "$@" \
    -- "$command_text"
}

run_termux_helper() {
  local command_text="$1"
  shift
  local output

  output="$(termux_command "$command_text" "$@" 2>&1)" || fail \
    "$command_text" \
    "$output" \
    'O helper remoto no app Termux falhou durante a consolidação do desktop.' \
    'Inspecionar a saída remota e repetir a operação.'

  printf '%s\n' "$output"
}

termux_stack_status_line() {
  local output
  local status_line

  output="$(termux_command 'termux-stack-status --brief' 2>&1)" || fail \
    'termux-stack-status --brief' \
    "$output" \
    'O helper não conseguiu confirmar o estado atual da stack Termux.' \
    'Restaurar o ecossistema Termux e repetir a consolidação.'

  status_line="$(printf '%s\n' "$output" | awk '/^X11=/{ print; exit }')"
  if [ -z "$status_line" ]; then
    fail \
      'termux-stack-status --brief' \
      "$output" \
      'A saída do status do Termux não trouxe a linha resumida esperada.' \
      'Inspecionar a conectividade do app Termux e repetir a consolidação.'
  fi

  printf '%s\n' "$status_line"
}

wait_for_stack_fragment() {
  local expected_fragment="$1"
  local timeout_seconds="${2:-12}"
  local deadline_seconds
  local status_line

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    status_line="$(termux_stack_status_line)"
    if printf '%s\n' "$status_line" | grep -Fq "$expected_fragment"; then
      printf '%s\n' "$status_line"
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep 1
  done

  return 1
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
      'A activity principal do app não pôde ser resolvida para o modo desktop.' \
      'Confirmar que o pacote está instalado no device e repetir a consolidação.'
  fi

  printf '%s\n' "$resolved_component"
}

display_bounds() {
  local bounds_text
  local width_height
  local width
  local height

  bounds_text="$(
    adb -s "$DEVICE_ID" shell cmd activity stack list 2>/dev/null \
      | awk '
          /^RootTask id=/ && match($0, /bounds=\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]/) {
            bounds = substr($0, RSTART, RLENGTH)
            parsed = bounds
            gsub(/bounds=\[/, "", parsed)
            gsub(/\]\[/, " ", parsed)
            gsub(/\]/, "", parsed)
            gsub(/,/, " ", parsed)
            split(parsed, parts, /[[:space:]]+/)
            if (parts[1] != "" && parts[4] != "") {
              width = parts[3] - parts[1]
              height = parts[4] - parts[2]
              area = width * height
              if (area > best_area) {
                best_area = area
                best_bounds = bounds
              }
            }
          }

          END {
            if (best_bounds != "") {
              print best_bounds
            }
          }
        '
  )"

  if [ -n "$bounds_text" ]; then
    printf '%s\n' "$bounds_text" | sed -E 's/.*\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\].*/\1 \2 \3 \4/'
    return 0
  fi

  width_height="$(
    adb -s "$DEVICE_ID" shell wm size 2>/dev/null \
      | tr -d '\r' \
      | awk -F': ' '/Physical size:/ { print $2; exit }'
  )"

  if [ -z "$width_height" ] || ! printf '%s\n' "$width_height" | grep -Eq '^[0-9]+x[0-9]+$'; then
    fail \
      'detecção da geometria do display Android' \
      "${width_height:-sem saída}" \
      'O helper não conseguiu calcular os bounds do desktop livre.' \
      'Confirmar que o device está em desktop mode/freeform e repetir a consolidação.'
  fi

  width="${width_height%x*}"
  height="${width_height#*x}"
  if [ "$height" -gt "$width" ]; then
    printf '0 0 %s %s\n' "$height" "$width"
  else
    printf '0 0 %s %s\n' "$width" "$height"
  fi
}

scale_bounds() {
  local base_bounds="$1"
  local display_left="$2"
  local display_top="$3"
  local display_width="$4"
  local display_height="$5"
  local base_left
  local base_top
  local base_right
  local base_bottom
  local scaled_left
  local scaled_top
  local scaled_right
  local scaled_bottom

  read -r base_left base_top base_right base_bottom <<<"$base_bounds"

  scaled_left=$((display_left + (base_left * display_width / BASE_DISPLAY_WIDTH)))
  scaled_top=$((display_top + (base_top * display_height / BASE_DISPLAY_HEIGHT)))
  scaled_right=$((display_left + (base_right * display_width / BASE_DISPLAY_WIDTH)))
  scaled_bottom=$((display_top + (base_bottom * display_height / BASE_DISPLAY_HEIGHT)))

  printf '%s %s %s %s\n' "$scaled_left" "$scaled_top" "$scaled_right" "$scaled_bottom"
}

compute_layout() {
  local display_left
  local display_top
  local display_right
  local display_bottom
  local display_width
  local display_height

  read -r display_left display_top display_right display_bottom <<<"$(display_bounds)"
  display_width=$((display_right - display_left))
  display_height=$((display_bottom - display_top))

  TERMUX_BOUNDS="$(scale_bounds "$BASE_TERMUX_BOUNDS" "$display_left" "$display_top" "$display_width" "$display_height")"
  SSH_BOUNDS="$(scale_bounds "$BASE_SSH_BOUNDS" "$display_left" "$display_top" "$display_width" "$display_height")"
  X11_BOUNDS="$(scale_bounds "$BASE_X11_BOUNDS" "$display_left" "$display_top" "$display_width" "$display_height")"
  DISPLAY_BOUNDS="${display_left} ${display_top} ${display_right} ${display_bottom}"
}

start_freeform_activity() {
  local component_name="$1"
  local activity_token="$2"
  local label="$3"
  local task_id

  run_adb shell cmd activity start-activity \
    --display "$DISPLAY_ID" \
    --windowingMode "$WINDOWING_MODE" \
    -W \
    -n "$component_name" \
    >/dev/null

  task_id="$(termux::wait_for_activity_task_id "$DEVICE_ID" "$activity_token" 10 0.25 || true)"
  if [ -z "$task_id" ]; then
    fail \
      "abertura da janela $label" \
      "A activity $component_name não gerou uma task detectável." \
      'O Android não criou a janela livre esperada para esse app.' \
      'Reabrir o app manualmente no tablet e repetir a consolidação.'
  fi

  printf '%s\n' "$task_id"
}

resolve_desktop_desk_id() {
  local dump_output
  local desk_id

  dump_output="$(
    adb -s "$DEVICE_ID" shell wm shell desktopmode dump 2>/dev/null \
      | tr -d '\r'
  )"

  desk_id="$(
    printf '%s\n' "$dump_output" \
      | sed -nE 's/^[[:space:]]*Desk #([0-9]+):.*/\1/p' \
      | head -n1
  )"

  if [ -z "$desk_id" ]; then
    fail \
      'wm shell desktopmode dump' \
      "${dump_output:-sem saída}" \
      'O Android não expôs um desk ativo para o modo desktop/freeform.' \
      'Confirmar que o dispositivo está em desktop mode antes de consolidar as janelas.'
  fi

  printf '%s\n' "$desk_id"
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

move_task_to_desktop_desk() {
  local task_id="$1"
  local label="$2"
  local current_mode

  current_mode="$(task_windowing_mode "$task_id" || true)"
  if [ "$current_mode" = 'freeform' ]; then
    return 0
  fi

  # Samsung's desktopmode shell often prints "Not implemented." even when the
  # task is actually converted into a desktop freeform window. Validate by
  # polling the real task mode instead of trusting the raw command text.
  adb -s "$DEVICE_ID" shell wm shell desktopmode moveTaskToDesk "$task_id" "$DESK_ID" >/dev/null 2>&1 || true

  if ! wait_for_task_windowing_mode "$task_id" freeform 10; then
    fail \
      "desktopmode moveTaskToDesk $task_id $DESK_ID" \
      "$(adb -s "$DEVICE_ID" shell cmd activity stack list 2>/dev/null | tr -d '\r')" \
      "A task $label não entrou em modo freeform depois da conversão para o desktop." \
      'Confirmar que o Android está em desktop mode e repetir a consolidação.'
  fi
}

resize_task() {
  local task_id="$1"
  local bounds_text="$2"
  local label="$3"
  local left
  local top
  local right
  local bottom

  read -r left top right bottom <<<"$bounds_text"

  adb -s "$DEVICE_ID" shell cmd activity task resizeable "$task_id" 3 >/dev/null 2>&1 || true
  run_adb shell cmd activity task resize "$task_id" "$left" "$top" "$right" "$bottom" >/dev/null
  printf '%s task=%s bounds=[%s,%s][%s,%s]\n' "$label" "$task_id" "$left" "$top" "$right" "$bottom"
}

refresh_layout_tasks() {
  TERMUX_TASK_ID="$(task_id_by_package 'com.termux')"
  X11_TASK_ID="$(task_id_by_package 'com.termux.x11')"
  SSH_TASK_ID="$(task_id_by_package "$SSH_PACKAGE")"

  [ -n "$TERMUX_TASK_ID" ] || fail \
    'resolução da task do Termux' \
    'task ausente' \
    'A task do app Termux não foi encontrada para reaplicar o layout desktop.' \
    'Reabrir o app Termux no tablet e repetir a consolidação.'

  [ -n "$X11_TASK_ID" ] || fail \
    'resolução da task do Termux:X11' \
    'task ausente' \
    'A task do app Termux:X11 não foi encontrada para reaplicar o layout desktop.' \
    'Reabrir o app Termux:X11 no tablet e repetir a consolidação.'

  [ -n "$SSH_TASK_ID" ] || fail \
    "resolução da task do cliente SSH $SSH_PACKAGE" \
    'task ausente' \
    'A task do cliente SSH não foi encontrada para reaplicar o layout desktop.' \
    'Reabrir o cliente SSH no tablet e repetir a consolidação.'
}

apply_layout_to_current_tasks() {
  move_task_to_desktop_desk "$TERMUX_TASK_ID" 'Termux'
  move_task_to_desktop_desk "$X11_TASK_ID" 'Termux:X11'
  move_task_to_desktop_desk "$SSH_TASK_ID" 'SSH client'

  compute_layout

  TERMUX_LAYOUT_RESULT="$(resize_task "$TERMUX_TASK_ID" "$TERMUX_BOUNDS" 'Termux')"
  SSH_LAYOUT_RESULT="$(resize_task "$SSH_TASK_ID" "$SSH_BOUNDS" 'SSH')"
  X11_LAYOUT_RESULT="$(resize_task "$X11_TASK_ID" "$X11_BOUNDS" 'Termux:X11')"
}

ensure_openbox_session() {
  local status_line
  local start_command
  local start_message

  status_line="$(termux_stack_status_line)"
  if printf '%s\n' "$status_line" | grep -Fq 'DESKTOP=openbox' \
    && printf '%s\n' "$status_line" | grep -Fq 'X11=display-ready'; then
    printf '%s\n' "$status_line"
    return 0
  fi

  if ! printf '%s\n' "$status_line" | grep -Fq 'VIRGL=ativo'; then
    run_termux_helper 'start-virgl plain' \
      --expect 'virgl_test_server_android iniciado em modo plain' \
      --expect 'virgl_test_server_android já está em execução' \
      >/dev/null
  fi

  start_command="$(termux::desktop_start_command openbox "$OPENBOX_PROFILE" xfwm4 0)"
  start_message="$(termux::desktop_start_message openbox "$OPENBOX_PROFILE" xfwm4 0)"
  run_termux_helper "$start_command" --expect "$start_message" >/dev/null

  if ! termux::wait_for_x11_surface "$DEVICE_ID" "$X11_UI_REMOTE" "$X11_UI_LOCAL" 15; then
    fail \
      "$start_command" \
      'A surface do Termux:X11 não apareceu após a subida do Openbox.' \
      'A sessão gráfica não ficou pronta no modo desktop livre.' \
      'Reabrir a janela do Termux:X11 e repetir a consolidação.'
  fi

  if ! wait_for_stack_fragment 'DESKTOP=openbox' 15 >/dev/null; then
    fail \
      "$start_command" \
      "$(termux_stack_status_line)" \
      'A sessão Openbox não ficou ativa depois do start remoto.' \
      'Inspecionar o terminal Termux no tablet e repetir a consolidação.'
  fi

  wait_for_stack_fragment 'X11=display-ready' 15 || true
  termux_stack_status_line
}

stop_desktop_apps() {
  run_adb shell am force-stop com.termux.x11 >/dev/null
  run_adb shell am force-stop com.termux >/dev/null
  run_adb shell am force-stop "$SSH_PACKAGE" >/dev/null
  sleep 2
}

clear_termux_api_ui() {
  adb -s "$DEVICE_ID" shell am force-stop com.termux.api >/dev/null 2>&1 || true
}

focus_task() {
  local task_id="$1"
  local bounds_text="$2"
  local focus_token
  local left
  local top
  local right
  local bottom
  local tap_x
  local tap_y

  read -r left top right bottom <<<"$bounds_text"
  tap_x=$(((left + right) / 2))
  tap_y=$(((top + bottom) / 2))

  case "$FOCUS_TARGET" in
    termux)
      focus_token='com.termux/'
      ;;
    x11)
      focus_token='com.termux.x11/'
      ;;
    ssh)
      focus_token="$SSH_PACKAGE/"
      ;;
  esac

  adb -s "$DEVICE_ID" shell wm shell desktopmode moveTaskToFront "$task_id" >/dev/null 2>&1 || true
  run_adb shell input tap "$tap_x" "$tap_y" >/dev/null

  if ! termux::wait_for_focus "$DEVICE_ID" "$focus_token" 8 0.25 >/dev/null; then
    fail \
      "foco final na task $task_id" \
      "$(termux::current_focus "$DEVICE_ID")" \
      'O Android não trouxe a janela solicitada para frente ao final da consolidação.' \
      'Tocar na janela desejada manualmente no tablet ou repetir a operação.'
  fi
}

SSH_COMPONENT="$(resolve_component "$SSH_PACKAGE")"
DESK_ID="$(resolve_desktop_desk_id)"

clear_termux_api_ui

if [ "$RESTART_APPS" -eq 1 ]; then
  stop_desktop_apps
fi

TERMUX_TASK_ID="$(start_freeform_activity "$TERMUX_COMPONENT" "$TERMUX_TOKEN" 'Termux')"
X11_TASK_ID="$(start_freeform_activity "$X11_COMPONENT" "$X11_TOKEN" 'Termux:X11')"
SSH_TASK_ID="$(start_freeform_activity "$SSH_COMPONENT" "$SSH_TOKEN" 'SSH client')"

apply_layout_to_current_tasks

STATUS_LINE='não solicitado'
if [ "$ENSURE_OPENBOX" -eq 1 ]; then
  STATUS_LINE="$(ensure_openbox_session)"
  refresh_layout_tasks
  apply_layout_to_current_tasks
fi

case "$FOCUS_TARGET" in
  termux)
    focus_task "$TERMUX_TASK_ID" "$TERMUX_BOUNDS"
    ;;
  x11)
    focus_task "$X11_TASK_ID" "$X11_BOUNDS"
    ;;
  ssh)
    focus_task "$SSH_TASK_ID" "$SSH_BOUNDS"
    ;;
esac

printf 'Desktop freeform consolidado no dispositivo %s.\n' "$DEVICE_ID"
printf 'Display: [%s]\n' "$DISPLAY_BOUNDS"
printf '%s\n' "$TERMUX_LAYOUT_RESULT"
printf '%s\n' "$SSH_LAYOUT_RESULT"
printf '%s\n' "$X11_LAYOUT_RESULT"
printf 'Cliente SSH: %s\n' "$SSH_COMPONENT"
printf 'Openbox: %s\n' "$OPENBOX_PROFILE"
printf 'Foco final: %s\n' "$FOCUS_TARGET"
printf 'Stack: %s\n' "$STATUS_LINE"
