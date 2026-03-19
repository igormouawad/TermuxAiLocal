#!/usr/bin/env bash

TERMUX_WORKSPACE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

termux::stderr() {
  printf '%s\n' "$*" >&2
}

termux::print_failure() {
  local command_text="$1"
  local error_text="$2"
  local impact_text="$3"
  local next_step_text="$4"

  termux::stderr 'FALHA DETECTADA'
  printf -- '- comando: %s\n' "$command_text" >&2
  printf -- '- erro: %s\n' "$error_text" >&2
  printf -- '- impacto: %s\n' "$impact_text" >&2
  printf -- '- próximo passo recomendado: %s\n' "$next_step_text" >&2
}

termux::fail() {
  termux::print_failure "$@"
  exit 1
}

termux::progress_percent() {
  local current="$1"
  local total="$2"

  if [ "$total" -le 0 ] 2>/dev/null; then
    printf '100\n'
    return 0
  fi

  printf '%s\n' $((current * 100 / total))
}

termux::progress_bar() {
  local current="$1"
  local total="$2"
  local width="${3:-24}"
  local filled=0
  local empty

  if [ "$total" -gt 0 ] 2>/dev/null; then
    filled=$((current * width / total))
  fi
  empty=$((width - filled))

  printf '['
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%*s' "$empty" '' | tr ' ' '.'
  printf ']'
}

termux::progress_step() {
  local current="$1"
  local total="$2"
  local context="$3"
  local label="$4"
  local percent

  percent="$(termux::progress_percent "$current" "$total")"
  printf '[%s] %s (%s/%s %s%%) %s\n' \
    "$context" \
    "$(termux::progress_bar "$current" "$total")" \
    "$current" \
    "$total" \
    "$percent" \
    "$label"
}

termux::progress_result() {
  local status_label="$1"
  local current="$2"
  local total="$3"
  local context="$4"
  local message="$5"
  local percent

  percent="$(termux::progress_percent "$current" "$total")"
  printf '[%s:%s %s%%] %s\n' "$context" "$status_label" "$percent" "$message"
}

termux::progress_note() {
  local context="$1"
  local message="$2"

  printf '[%s] %s\n' "$context" "$message"
}

termux::require_host_command() {
  local binary_name="$1"
  local impact_text="$2"
  local next_step_text="$3"

  if ! command -v "$binary_name" >/dev/null 2>&1; then
    termux::fail \
      "command -v $binary_name" \
      "$binary_name não encontrado no PATH." \
      "$impact_text" \
      "$next_step_text"
  fi
}

termux::adb_device_list() {
  local device_list

  device_list=$(adb devices -l 2>&1) || termux::fail \
    'adb devices -l' \
    "$device_list" \
    'Não foi possível consultar dispositivos ADB.' \
    'Verificar cabo, autorização USB e serviço ADB.'

  printf '%s\n' "$device_list"
}

termux::resolve_single_device() {
  local device_list
  local usb_count
  local usb_id
  local network_count
  local network_id
  local device_count

  device_list="$(termux::adb_device_list)"

  usb_count=$(
    printf '%s\n' "$device_list" \
      | awk 'NR > 1 && $2 == "device" && ($0 ~ / usb:/ || $1 !~ /:/) { count++ } END { print count + 0 }'
  )
  usb_id=$(
    printf '%s\n' "$device_list" \
      | awk 'NR > 1 && $2 == "device" && ($0 ~ / usb:/ || $1 !~ /:/) { print $1; exit }'
  )
  network_count=$(
    printf '%s\n' "$device_list" \
      | awk 'NR > 1 && $2 == "device" && $0 !~ / usb:/ && $1 ~ /:/ { count++ } END { print count + 0 }'
  )
  network_id=$(
    printf '%s\n' "$device_list" \
      | awk 'NR > 1 && $2 == "device" && $0 !~ / usb:/ && $1 ~ /:/ { print $1; exit }'
  )
  device_count=$(
    printf '%s\n' "$device_list" \
      | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }'
  )

  if [ "$usb_count" -eq 1 ]; then
    printf '%s\n' "$usb_id"
    return 0
  fi

  if [ "$usb_count" -gt 1 ]; then
    termux::fail \
      'adb devices -l' \
      "$device_list" \
      'Há múltiplos alvos ADB diretos/USB em estado device; a escolha automática não é segura.' \
      'Desconectar os alvos extras ou repetir com `TERMUXAI_DEVICE_ID=SERIAL` / `--device SERIAL`.'
  fi

  if [ "$network_count" -eq 1 ]; then
    printf '%s\n' "$network_id"
    return 0
  fi

  if [ "$network_count" -gt 1 ]; then
    termux::fail \
      'adb devices -l' \
      "$device_list" \
      'Não há USB disponível e existem múltiplos alvos ADB via rede em estado device; a escolha automática não é segura.' \
      'Desconectar os alvos extras ou repetir com `TERMUXAI_DEVICE_ID=SERIAL` / `--device SERIAL`.'
  fi

  if [ "$device_count" -eq 0 ]; then
    termux::fail \
      'adb devices -l' \
      "$device_list" \
      'Nenhum dispositivo em estado device foi encontrado.' \
      'Conectar via USB ou reconectar o endpoint ADB por Wi‑Fi antes de prosseguir.'
  fi

  termux::fail \
    'adb devices -l' \
    "$device_list" \
    'Os alvos ADB presentes não puderam ser classificados de forma confiável em USB ou rede.' \
    'Executar `adb devices -l` manualmente e repetir com `TERMUXAI_DEVICE_ID=SERIAL` / `--device SERIAL`.'
}

termux::resolve_target_device() {
  local preferred_device_id="${1:-}"

  termux::require_host_command \
    adb \
    'Os wrappers host-side do workspace não conseguem orquestrar o dispositivo Android.' \
    'Instalar Android Platform Tools no host e tentar novamente.'

  if [ -n "$preferred_device_id" ]; then
    printf '%s\n' "$preferred_device_id"
    return 0
  fi

  if [ -n "${TERMUXAI_DEVICE_ID:-}" ]; then
    printf '%s\n' "${TERMUXAI_DEVICE_ID}"
    return 0
  fi

  termux::resolve_single_device
}

termux::run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1 && [ "$timeout_seconds" -gt 0 ] 2>/dev/null; then
    timeout -k 2s "${timeout_seconds}s" "$@"
    return $?
  fi

  "$@"
}

termux::adb_run() {
  local device_id="$1"
  local impact_text="$2"
  local next_step_text="$3"
  shift 3

  local output
  local status
  local timeout_seconds="${TERMUX_ADB_TIMEOUT_SECONDS:-0}"

  if ! output=$(termux::run_with_timeout "$timeout_seconds" adb -s "$device_id" "$@" 2>&1); then
    status=$?
    if [ "$status" -eq 124 ]; then
      output="Comando ADB excedeu ${timeout_seconds}s.
${output}"
    fi
    termux::fail \
      "adb -s \"$device_id\" $*" \
      "$output" \
      "$impact_text" \
      "$next_step_text"
  fi

  printf '%s\n' "$output"
}

termux::current_focus() {
  local device_id="$1"

  adb -s "$device_id" shell dumpsys window | grep -E 'mCurrentFocus|mFocusedApp' | tail -4
}

termux::wait_for_focus() {
  local device_id="$1"
  local focus_token="$2"
  local timeout_seconds="${3:-8}"
  local poll_interval_seconds="${4:-0.25}"
  local deadline_seconds
  local focus_output

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    focus_output="$(termux::current_focus "$device_id" 2>/dev/null || true)"

    if printf '%s\n' "$focus_output" | grep -Fq "$focus_token"; then
      printf '%s\n' "$focus_output"
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep "$poll_interval_seconds"
  done

  return 1
}

termux::start_activity_and_wait() {
  local device_id="$1"
  local component_name="$2"
  local focus_token="$3"
  local timeout_seconds="${4:-8}"

  if ! adb -s "$device_id" shell am start -n "$component_name" >/dev/null 2>&1; then
    return 1
  fi

  termux::wait_for_focus "$device_id" "$focus_token" "$timeout_seconds"
}

termux::wait_for_activity_task_id() {
  local device_id="$1"
  local activity_token="$2"
  local timeout_seconds="${3:-8}"
  local poll_interval_seconds="${4:-0.3}"
  local deadline_seconds
  local task_id

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    task_id="$(termux::activity_task_id "$device_id" "$activity_token" || true)"
    if [ -n "$task_id" ]; then
      printf '%s\n' "$task_id"
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep "$poll_interval_seconds"
  done

  return 1
}

termux::activity_task_id() {
  local device_id="$1"
  local activity_token="$2"

  adb -s "$device_id" shell dumpsys activity activities 2>/dev/null | awk -v activity_token="$activity_token" '
    index($0, "Task{") {
      current_task_id = $0
      sub(/^.*#/, "", current_task_id)
      sub(/[^0-9].*$/, "", current_task_id)
      if (current_task_id !~ /^[0-9]+$/) {
        current_task_id = ""
      }
    }

    index($0, activity_token) {
      if (current_task_id != "") {
        print current_task_id
        exit
      }
    }
  '
}

termux::package_pid() {
  local device_id="$1"
  local package_name="$2"

  adb -s "$device_id" shell pidof "$package_name" 2>/dev/null | tr -d '\r' | awk '{ print $1; exit }'
}

termux::wait_for_package_process() {
  local device_id="$1"
  local package_name="$2"
  local timeout_seconds="${3:-8}"
  local poll_interval_seconds="${4:-0.5}"
  local deadline_seconds
  local package_pid

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    package_pid="$(termux::package_pid "$device_id" "$package_name" || true)"
    if [ -n "$package_pid" ]; then
      printf '%s\n' "$package_pid"
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep "$poll_interval_seconds"
  done

  return 1
}

termux::ensure_termux_api_running() {
  local device_id="$1"
  local timeout_seconds="${2:-10}"

  if termux::wait_for_package_process "$device_id" 'com.termux.api' 1 >/dev/null 2>&1; then
    return 0
  fi

  if ! adb -s "$device_id" shell am start -W -n 'com.termux.api/.activities.TermuxAPILauncherActivity' >/dev/null 2>&1; then
    return 1
  fi

  termux::wait_for_package_process "$device_id" 'com.termux.api' "$timeout_seconds" >/dev/null
}

termux::desktop_mode_dump() {
  local device_id="$1"

  adb -s "$device_id" shell wm shell desktopmode dump 2>/dev/null | tr -d '\r'
}

termux::desktop_mode_active() {
  local device_id="$1"

  termux::desktop_mode_dump "$device_id" | grep -Fq 'inDesktopWindowing=true'
}

termux::wait_for_desktop_mode_state() {
  local device_id="$1"
  local expected_state="$2"
  local timeout_seconds="${3:-12}"
  local deadline_seconds

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    if [ "$expected_state" = 'on' ] && termux::desktop_mode_active "$device_id"; then
      return 0
    fi

    if [ "$expected_state" = 'off' ] && ! termux::desktop_mode_active "$device_id"; then
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep 0.5
  done

  return 1
}

termux::prepare_android_reboot_state() {
  local device_id="$1"

  adb -s "$device_id" shell am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
  adb -s "$device_id" shell cmd activity kill com.termux.x11 >/dev/null 2>&1 || true
  adb -s "$device_id" shell cmd activity kill com.termux >/dev/null 2>&1 || true
  adb -s "$device_id" shell cmd activity kill com.termux.api >/dev/null 2>&1 || true
  adb -s "$device_id" shell cmd activity kill com.server.auditor.ssh.client >/dev/null 2>&1 || true
  adb -s "$device_id" shell am force-stop com.termux.x11 >/dev/null 2>&1 || true
  adb -s "$device_id" shell am force-stop com.termux >/dev/null 2>&1 || true
  adb -s "$device_id" shell am force-stop com.termux.api >/dev/null 2>&1 || true
  adb -s "$device_id" shell am force-stop com.server.auditor.ssh.client >/dev/null 2>&1 || true

  if termux::desktop_mode_active "$device_id"; then
    adb -s "$device_id" shell wm shell desktopmode toggleDesktopWindowingInDefaultDisplay >/dev/null 2>&1 || true
    termux::wait_for_desktop_mode_state "$device_id" off 12 || true
  fi

  adb -s "$device_id" shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
  sleep 1
}

termux::ensure_termux_workspace_ready() {
  local device_id="$1"
  local focus_target="${2:-termux}"
  local output
  local status

  case "$focus_target" in
    termux|x11|ssh)
      ;;
    *)
      return 1
      ;;
  esac

  set +e
  output="$(
    TERMUXAI_DEVICE_ID="$device_id" \
      bash "${TERMUX_WORKSPACE_ROOT}/ADB/adb_desktop_mode.sh" on 2>&1
  )"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    return 1
  fi

  set +e
  output="$(
    TERMUXAI_DEVICE_ID="$device_id" \
      bash "${TERMUX_WORKSPACE_ROOT}/ADB/adb_consolidate_freeform_desktop.sh" \
        --no-openbox \
        --focus "$focus_target" 2>&1
  )"
  status=$?
  set -e

  [ "$status" -eq 0 ]
}

termux::dump_ui_xml() {
  local device_id="$1"
  local remote_path="$2"
  local local_path="$3"

  adb -s "$device_id" shell uiautomator dump "$remote_path" >/dev/null 2>&1 || return 1
  adb -s "$device_id" shell cat "$remote_path" > "$local_path" || return 1
}

termux::x11_surface_showing() {
  local device_id="$1"

  adb -s "$device_id" shell dumpsys activity activities 2>/dev/null | awk '
    /Task\{/ {
      current_task_visible = ($0 ~ /visible=true visibleRequested=true/)
      current_task_has_x11 = 0
      current_task_surface = 0
    }

    /com\.termux\.x11\/\.MainActivity/ {
      current_task_has_x11 = 1
      if (current_task_visible && current_task_surface) {
        print "x11-surface-ok"
        exit
      }
    }

    /mLastSurfaceShowing=true/ {
      current_task_surface = 1
      if (current_task_visible && current_task_has_x11) {
        print "x11-surface-ok"
        exit
      }
    }

    /mHoldScreenWindow=Window\{.* com\.termux\.x11\/com\.termux\.x11\.MainActivity\}/ {
      print "x11-surface-ok"
      exit
    }
  ' | grep -Fq 'x11-surface-ok'
}

termux::wait_for_x11_surface() {
  local device_id="$1"
  local remote_path="$2"
  local local_path="$3"
  local timeout_seconds="${4:-10}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if termux::dump_ui_xml "$device_id" "$remote_path" "$local_path" \
      && grep -Fq 'com.termux.x11:id/lorieView' "$local_path"; then
      return 0
    fi

    if termux::x11_surface_showing "$device_id"; then
      return 0
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

termux::append_shell_word() {
  local current_text="$1"
  local word="$2"
  local quoted_word

  printf -v quoted_word '%q' "$word"
  if [ -n "$current_text" ]; then
    printf '%s %s\n' "$current_text" "$quoted_word"
    return 0
  fi

  printf '%s\n' "$quoted_word"
}

termux::list_termux_processes() {
  local device_id="$1"

  adb -s "$device_id" shell ps -A -o USER,PID,UID,PPID,NAME,ARGS 2>/dev/null | awk '
    NR == 1 || /com\.termux|com\.termux\.api|com\.termux\.x11|termux-x11|com\.termux\.x11\.Loader/ {
      print
    }
  '
}

termux::termux_process_count() {
  local device_id="$1"

  termux::list_termux_processes "$device_id" | awk 'NR > 1 { count++ } END { print count + 0 }'
}

termux::wait_for_no_termux_processes() {
  local device_id="$1"
  local timeout_seconds="${2:-10}"
  local poll_interval_seconds="${3:-0.5}"
  local deadline_seconds

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    if [ "$(termux::termux_process_count "$device_id")" -eq 0 ]; then
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep "$poll_interval_seconds"
  done

  return 1
}

termux::wait_for_boot_completed() {
  local device_id="$1"
  local timeout_seconds="${2:-180}"
  local deadline_seconds
  local boot_completed
  local dev_bootcomplete

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    if adb -s "$device_id" get-state >/dev/null 2>&1; then
      boot_completed="$(adb -s "$device_id" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      dev_bootcomplete="$(adb -s "$device_id" shell getprop dev.bootcomplete 2>/dev/null | tr -d '\r' || true)"
      if [ "$boot_completed" = '1' ] && { [ -z "$dev_bootcomplete" ] || [ "$dev_bootcomplete" = '1' ]; }; then
        return 0
      fi
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep 2
  done

  return 1
}

termux::wait_for_device_ready() {
  local device_id="$1"
  local timeout_seconds="${2:-120}"
  local deadline_seconds
  local device_state

  deadline_seconds=$(( $(date +%s) + timeout_seconds ))

  while :; do
    device_state="$(adb -s "$device_id" get-state 2>/dev/null | tr -d '\r' || true)"
    if [ "$device_state" = 'device' ]; then
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline_seconds" ]; then
      break
    fi

    sleep 2
  done

  return 1
}

termux::desktop_profile_valid() {
  case "${1:-}" in
    openbox|xfce)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

termux::openbox_profile_valid() {
  case "${1:-}" in
    openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

termux::xfce_wm_valid() {
  case "${1:-}" in
    xfwm4|openbox)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

termux::xfce_wm_pattern() {
  case "${1:-xfwm4}" in
    openbox)
      printf '(^| )openbox($| )|openbox --replace'
      ;;
    *)
      printf '(^| )xfwm4($| )'
      ;;
  esac
}

termux::desktop_process_pattern() {
  local desktop_profile="${1:-}"
  local xfce_wm="${2:-xfwm4}"

  case "$desktop_profile" in
    openbox)
      printf '(^| )openbox($| )|openbox-session'
      ;;
    xfce)
      termux::xfce_wm_pattern "$xfce_wm"
      ;;
    *)
      return 1
      ;;
  esac
}

termux::desktop_start_helper() {
  local desktop_profile="${1:-}"
  local max_perf="${2:-0}"

  case "$desktop_profile" in
    openbox)
      printf 'start-openbox-x11'
      ;;
    xfce)
      if [ "$max_perf" -eq 1 ]; then
        printf 'start-maxperf-x11'
      else
        printf 'start-xfce-x11-detached'
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

termux::desktop_stop_helper() {
  case "${1:-}" in
    openbox)
      printf 'stop-openbox-x11'
      ;;
    xfce)
      printf 'stop-xfce-x11'
      ;;
    *)
      return 1
      ;;
  esac
}

termux::desktop_start_command() {
  local desktop_profile="${1:-}"
  local openbox_profile="${2:-openbox-maxperf}"
  local xfce_wm="${3:-xfwm4}"
  local max_perf="${4:-0}"

  case "$desktop_profile" in
    openbox)
      printf 'start-openbox-x11 --profile %s' "$openbox_profile"
      ;;
    xfce)
      if [ "$max_perf" -eq 1 ]; then
        printf 'start-maxperf-x11 xfce'
      else
        printf 'start-xfce-x11-detached %s' "$xfce_wm"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

termux::desktop_stop_command() {
  termux::desktop_stop_helper "${1:-}"
}

termux::desktop_start_message() {
  local desktop_profile="${1:-}"
  local openbox_profile="${2:-openbox-maxperf}"
  local xfce_wm="${3:-xfwm4}"
  local max_perf="${4:-0}"

  case "$desktop_profile" in
    openbox)
      printf 'OPENBOX_PROFILE_OK PROFILE=%s' "$openbox_profile"
      ;;
    xfce)
      if [ "$max_perf" -eq 1 ]; then
        printf 'Perfil 3D de máxima performance aplicado (xfce).'
      else
        printf 'XFCE_DETACHED_OK WM=%s' "$xfce_wm"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

termux::desktop_stop_message() {
  case "${1:-}" in
    openbox)
      printf 'Sessão Openbox/X11 encerrada.'
      ;;
    xfce)
      printf 'Sessão XFCE/X11 encerrada.'
      ;;
    *)
      return 1
      ;;
  esac
}
