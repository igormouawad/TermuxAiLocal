#!/usr/bin/env bash

TERMUX_WORKSPACE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUXAI_AUDIT_HOST_ROOT_DEFAULT="${TERMUX_WORKSPACE_ROOT}/Audit/runs"
TERMUXAI_AUDIT_DEVICE_ROOT_DEFAULT="/data/data/com.termux/files/home/.cache/termux-ai-local/audit/sessions"
TERMUXAI_HOST_CACHE_ROOT_DEFAULT="${XDG_CACHE_HOME:-$HOME/.cache}/termux-ai-local"
TERMUXAI_ADB_CACHE_DIR_DEFAULT="${TERMUXAI_HOST_CACHE_ROOT_DEFAULT}/adb"

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
  termux::audit_failure "$command_text" "$error_text" "$impact_text" "$next_step_text"
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
  termux::audit_step_begin "$current" "$total" "$context" "$label" "$percent"
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
  termux::audit_step_finish "$status_label" "$current" "$total" "$context" "$message" "$percent"
}

termux::progress_note() {
  local context="$1"
  local message="$2"

  printf '[%s] %s\n' "$context" "$message"
  termux::audit_note "$context" "$message"
}

termux::audit_enabled() {
  case "${TERMUXAI_AUDIT:-1}" in
    0|false|FALSE|no|NO)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

termux::audit_timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

termux::audit_slug() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'
}

termux::audit_json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

termux::audit_append_host_event() {
  local json_line="$1"

  if [ -z "${TERMUXAI_AUDIT_EVENTS_FILE:-}" ]; then
    return 0
  fi

  printf '%s\n' "$json_line" >> "$TERMUXAI_AUDIT_EVENTS_FILE"
}

termux::audit_append_host_step_log() {
  local text="$1"
  local ts

  if [ -z "${TERMUXAI_AUDIT_CURRENT_STEP_LOG:-}" ]; then
    return 0
  fi

  ts="$(termux::audit_timestamp)"
  printf '[%s] %s\n' "$ts" "$text" >> "$TERMUXAI_AUDIT_CURRENT_STEP_LOG"
}

termux::audit_mirror_remote_append() {
  local file_path="$1"
  local payload="$2"
  local remote_command

  if [ -z "${TERMUXAI_AUDIT_DEVICE_ID:-}" ] || [ -z "${TERMUXAI_AUDIT_DEVICE_DIR:-}" ] || [ -z "${TERMUXAI_AUDIT_DEVICE_READY:-}" ]; then
    return 0
  fi

  printf -v remote_command 'mkdir -p %q && payload=%q && printf '\''%%s\n'\'' "$payload" >> %q' \
    "$TERMUXAI_AUDIT_DEVICE_DIR" \
    "$payload" \
    "$file_path"

  adb -s "${TERMUXAI_AUDIT_DEVICE_ID}" shell "run-as com.termux sh -lc $(printf '%q' "$remote_command")" >/dev/null 2>&1 || true
}

termux::audit_emit_record() {
  local event_type="$1"
  local level="$2"
  local message="$3"
  local extra_json="${4:-}"
  local ts json_line

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    return 0
  fi

  ts="$(termux::audit_timestamp)"
  json_line="{\"ts\":\"$(termux::audit_json_escape "$ts")\",\"type\":\"$(termux::audit_json_escape "$event_type")\",\"level\":\"$(termux::audit_json_escape "$level")\",\"message\":\"$(termux::audit_json_escape "$message")\",\"session_id\":\"$(termux::audit_json_escape "${TERMUXAI_AUDIT_SESSION_ID:-}")\""
  if [ -n "$extra_json" ]; then
    json_line="${json_line},${extra_json}"
  fi
  json_line="${json_line}}"

  termux::audit_append_host_event "$json_line"
  termux::audit_mirror_remote_append "${TERMUXAI_AUDIT_DEVICE_EVENTS_FILE:-}" "$json_line"
}

termux::audit_step_begin() {
  local current="$1"
  local total="$2"
  local context="$3"
  local label="$4"
  local percent="$5"
  local seq step_log

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    return 0
  fi

  seq=$(( ${TERMUXAI_AUDIT_STEP_SEQ:-0} + 1 ))
  TERMUXAI_AUDIT_STEP_SEQ="$seq"
  export TERMUXAI_AUDIT_STEP_SEQ
  export TERMUXAI_AUDIT_CURRENT_STEP_SEQ="$seq"
  step_log="${TERMUXAI_AUDIT_SESSION_DIR}/step-$(printf '%04d' "$seq")-$(termux::audit_slug "$context-$label").log"
  : > "$step_log"
  export TERMUXAI_AUDIT_CURRENT_STEP_LOG="$step_log"

  termux::audit_append_host_step_log "ETAPA ${seq} | contexto=${context} | etapa-local=${current}/${total} | ${label}"
  termux::audit_emit_record \
    "step_start" \
    "info" \
    "${label}" \
    "\"seq\":${seq},\"current\":${current},\"total\":${total},\"percent\":${percent},\"context\":\"$(termux::audit_json_escape "$context")\",\"label\":\"$(termux::audit_json_escape "$label")\",\"name\":\"$(termux::audit_json_escape "$label")\",\"log_path\":\"$(termux::audit_json_escape "$step_log")\""
}

termux::audit_step_finish() {
  local status_label="$1"
  local current="$2"
  local total="$3"
  local context="$4"
  local message="$5"
  local percent="$6"
  local seq status_value

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ] || [ -z "${TERMUXAI_AUDIT_CURRENT_STEP_SEQ:-}" ]; then
    return 0
  fi

  seq="${TERMUXAI_AUDIT_CURRENT_STEP_SEQ}"
  case "$status_label" in
    OK|PASS|SUCCESS)
      status_value="success"
      ;;
    SKIP|SKIPPED)
      status_value="skipped"
      ;;
    *)
      status_value="failed"
      ;;
  esac

  termux::audit_append_host_step_log "RESULTADO ${seq} | status=${status_value} | ${message}"
  termux::audit_emit_record \
    "step_finish" \
    "$([ "$status_value" = "success" ] && printf 'info' || printf 'error')" \
    "$message" \
    "\"seq\":${seq},\"current\":${current},\"total\":${total},\"percent\":${percent},\"context\":\"$(termux::audit_json_escape "$context")\",\"status\":\"$(termux::audit_json_escape "$status_value")\""
  unset TERMUXAI_AUDIT_CURRENT_STEP_SEQ TERMUXAI_AUDIT_CURRENT_STEP_LOG
}

termux::audit_note() {
  local context="$1"
  local message="$2"
  local extra_json=""

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    return 0
  fi

  if [ -n "${TERMUXAI_AUDIT_CURRENT_STEP_SEQ:-}" ]; then
    extra_json="\"seq\":${TERMUXAI_AUDIT_CURRENT_STEP_SEQ},\"context\":\"$(termux::audit_json_escape "$context")\""
  else
    extra_json="\"context\":\"$(termux::audit_json_escape "$context")\""
  fi
  termux::audit_append_host_step_log "NOTA | ${message}"
  termux::audit_emit_record "note" "info" "$message" "$extra_json"
}

termux::audit_failure() {
  local command_text="$1"
  local error_text="$2"
  local impact_text="$3"
  local next_step_text="$4"
  local extra_json=""

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    return 0
  fi

  if [ -n "${TERMUXAI_AUDIT_CURRENT_STEP_SEQ:-}" ]; then
    extra_json="\"seq\":${TERMUXAI_AUDIT_CURRENT_STEP_SEQ},"
  fi
  extra_json="${extra_json}\"command\":\"$(termux::audit_json_escape "$command_text")\",\"error\":\"$(termux::audit_json_escape "$error_text")\",\"impact\":\"$(termux::audit_json_escape "$impact_text")\",\"next_step\":\"$(termux::audit_json_escape "$next_step_text")\""
  termux::audit_append_host_step_log "FALHA | comando=${command_text}"
  termux::audit_append_host_step_log "FALHA | erro=${error_text}"
  termux::audit_emit_record "failure" "error" "$error_text" "$extra_json"
}

termux::audit_command() {
  local command_text="$1"
  local extra_json=""

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    return 0
  fi

  if [ -n "${TERMUXAI_AUDIT_CURRENT_STEP_SEQ:-}" ]; then
    extra_json="\"seq\":${TERMUXAI_AUDIT_CURRENT_STEP_SEQ},"
  fi
  extra_json="${extra_json}\"command\":\"$(termux::audit_json_escape "$command_text")\""
  termux::audit_append_host_step_log "CMD | ${command_text}"
  termux::audit_emit_record "command" "info" "$command_text" "$extra_json"
}

termux::audit_command_result() {
  local rc="$1"
  local output_text="$2"
  local extra_json=""
  local message

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    return 0
  fi

  if [ -n "$output_text" ]; then
    termux::audit_append_host_step_log "$output_text"
  fi

  message="$output_text"
  if [ -n "$message" ]; then
    message="$(printf '%s\n' "$message" | tail -n 20)"
  else
    message="Comando concluído sem saída textual."
  fi

  if [ -n "${TERMUXAI_AUDIT_CURRENT_STEP_SEQ:-}" ]; then
    extra_json="\"seq\":${TERMUXAI_AUDIT_CURRENT_STEP_SEQ},"
  fi
  extra_json="${extra_json}\"return_code\":${rc}"
  termux::audit_emit_record \
    "command_result" \
    "$([ "$rc" -eq 0 ] 2>/dev/null && printf 'info' || printf 'error')" \
    "$message" \
    "$extra_json"
}

termux::audit_manifest_write() {
  local label="$1"
  local script_path="$2"
  local device_id="${3:-}"
  local manifest_path="$TERMUXAI_AUDIT_MANIFEST_FILE"

  cat > "$manifest_path" <<EOF
{
  "app": "TermuxAiLocal Audit Runner",
  "version": "2026.03",
  "mode": "mirror",
  "session_id": "$(termux::audit_json_escape "${TERMUXAI_AUDIT_SESSION_ID}")",
  "label": "$(termux::audit_json_escape "$label")",
  "session_label": "$(termux::audit_json_escape "$label")",
  "script_path": "$(termux::audit_json_escape "$script_path")",
  "cwd": "$(termux::audit_json_escape "$(pwd)")",
  "host": "$(termux::audit_json_escape "$(hostname)")",
  "started_at": "$(termux::audit_json_escape "$(termux::audit_timestamp)")",
  "device_id": "$(termux::audit_json_escape "$device_id")",
  "step_count": 0
}
EOF
}

termux::audit_launch_device_watch() {
  local device_id="$1"
  local launcher_name
  local launcher_path
  local watch_command
  local watcher_started
  local kill_previous

  if [ -z "$device_id" ]; then
    return 0
  fi

  launcher_name="${TERMUXAI_AUDIT_DEVICE_LAUNCHER_NAME:-termux-audit-watch-current}"
  launcher_path="/data/data/com.termux/files/home/bin/${launcher_name}"
  if ! adb -s "$device_id" shell "run-as com.termux test -x $launcher_path" >/dev/null 2>&1; then
    return 0
  fi

  kill_previous=$'pids="$(ps -ef | awk \'/audit_runner\\.py watch/ && $0 !~ /awk/ {print $2}\')"\nif [ -n "$pids" ]; then\n  kill $pids >/dev/null 2>&1 || true\n  sleep 0.2\nfi'
  adb -s "$device_id" shell "run-as com.termux sh -lc $(printf '%q' "$kill_previous")" >/dev/null 2>&1 || true

  watch_command="bin/${launcher_name}"
  TERMUXAI_AUDIT=0 TERMUXAI_AUDIT_SKIP_UI=1 bash "${TERMUX_WORKSPACE_ROOT}/ADB/adb_termux_send_command.sh" \
    --device "$device_id" \
    --force-ui \
    --no-focus \
    -- "$watch_command" >/dev/null 2>&1 || true

  watcher_started=0
  for _ in 1 2 3 4 5; do
    if adb -s "$device_id" shell "run-as com.termux sh -lc 'ps -ef | grep -F \"audit_runner.py watch ${TERMUXAI_AUDIT_SESSION_ID}\" | grep -v grep >/dev/null'" >/dev/null 2>&1; then
      watcher_started=1
      break
    fi
    sleep 0.1
  done

  [ "$watcher_started" -eq 1 ] || true
}

termux::audit_attach_device() {
  local device_id="$1"
  local stage_path
  local launcher_stage_path
  local launcher_local_path
  local events_stage_path
  local remote_install
  local launcher_path

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ] || [ -n "${TERMUXAI_AUDIT_DEVICE_READY:-}" ]; then
    return 0
  fi

  export TERMUXAI_AUDIT_DEVICE_ID="$device_id"
  export TERMUXAI_AUDIT_DEVICE_DIR="${TERMUXAI_AUDIT_DEVICE_ROOT:-${TERMUXAI_AUDIT_DEVICE_ROOT_DEFAULT}}/${TERMUXAI_AUDIT_SESSION_ID}"
  export TERMUXAI_AUDIT_DEVICE_EVENTS_FILE="${TERMUXAI_AUDIT_DEVICE_DIR}/events.jsonl"
  export TERMUXAI_AUDIT_DEVICE_MANIFEST_FILE="${TERMUXAI_AUDIT_DEVICE_DIR}/manifest.json"
  export TERMUXAI_AUDIT_DEVICE_LAUNCHER_NAME="termux-audit-watch-current"
  launcher_path="/data/data/com.termux/files/home/bin/${TERMUXAI_AUDIT_DEVICE_LAUNCHER_NAME}"

  stage_path="/data/local/tmp/${TERMUXAI_AUDIT_SESSION_ID}-manifest.json"
  launcher_stage_path="/data/local/tmp/${TERMUXAI_AUDIT_SESSION_ID}-watch.sh"
  launcher_local_path="$(mktemp)"
  cat > "$launcher_local_path" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export HOME="/data/data/com.termux/files/home"
export PREFIX="/data/data/com.termux/files/usr"
export TMPDIR="\${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
export PATH="\${HOME}/bin:\${PREFIX}/bin:/system/bin:/system/xbin"
export LD_LIBRARY_PATH="\${PREFIX}/lib"
exec "\${HOME}/bin/termux-audit-watch" ${TERMUXAI_AUDIT_DEVICE_DIR} --final-delay 8
EOF
  adb -s "$device_id" push "${TERMUXAI_AUDIT_MANIFEST_FILE}" "$stage_path" >/dev/null 2>&1 || {
    rm -f "$launcher_local_path"
    return 0
  }
  adb -s "$device_id" push "$launcher_local_path" "$launcher_stage_path" >/dev/null 2>&1 || {
    rm -f "$launcher_local_path"
    return 0
  }
  rm -f "$launcher_local_path"
  if [ -s "${TERMUXAI_AUDIT_EVENTS_FILE:-}" ]; then
    events_stage_path="/data/local/tmp/${TERMUXAI_AUDIT_SESSION_ID}-events.jsonl"
    adb -s "$device_id" push "${TERMUXAI_AUDIT_EVENTS_FILE}" "$events_stage_path" >/dev/null 2>&1 || events_stage_path=""
  fi
  adb -s "$device_id" shell chmod 644 "$stage_path" >/dev/null 2>&1 || true
  adb -s "$device_id" shell chmod 755 "$launcher_stage_path" >/dev/null 2>&1 || true
  if [ -n "$events_stage_path" ]; then
    adb -s "$device_id" shell chmod 644 "$events_stage_path" >/dev/null 2>&1 || true
    printf -v remote_install 'mkdir -p %q && install -m 600 %q %q && install -m 600 %q %q && install -m 755 %q %q' \
      "${TERMUXAI_AUDIT_DEVICE_DIR}" \
      "$stage_path" \
      "${TERMUXAI_AUDIT_DEVICE_MANIFEST_FILE}" \
      "$events_stage_path" \
      "${TERMUXAI_AUDIT_DEVICE_EVENTS_FILE}" \
      "$launcher_stage_path" \
      "$launcher_path"
  else
    printf -v remote_install 'mkdir -p %q && install -m 600 %q %q && : > %q && install -m 755 %q %q' \
      "${TERMUXAI_AUDIT_DEVICE_DIR}" \
      "$stage_path" \
      "${TERMUXAI_AUDIT_DEVICE_MANIFEST_FILE}" \
      "${TERMUXAI_AUDIT_DEVICE_EVENTS_FILE}" \
      "$launcher_stage_path" \
      "$launcher_path"
  fi
  adb -s "$device_id" shell "run-as com.termux sh -lc $(printf '%q' "$remote_install")" >/dev/null 2>&1 || return 0
  adb -s "$device_id" shell rm -f "$stage_path" "$launcher_stage_path" ${events_stage_path:+"$events_stage_path"} >/dev/null 2>&1 || true

  export TERMUXAI_AUDIT_DEVICE_READY=1
}

termux::audit_reset_device_attachment() {
  unset TERMUXAI_AUDIT_DEVICE_ID TERMUXAI_AUDIT_DEVICE_DIR TERMUXAI_AUDIT_DEVICE_READY
  unset TERMUXAI_AUDIT_DEVICE_EVENTS_FILE TERMUXAI_AUDIT_DEVICE_MANIFEST_FILE TERMUXAI_AUDIT_DEVICE_LAUNCHER_NAME
}

termux::audit_reattach_device() {
  local device_id="$1"

  if ! termux::audit_enabled || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ] || [ -z "$device_id" ]; then
    return 0
  fi

  termux::audit_reset_device_attachment
  termux::audit_attach_device "$device_id"
}

termux::audit_session_begin() {
  local label="$1"
  local script_path="${2:-$0}"
  local device_id="${3:-}"
  local host_root

  if ! termux::audit_enabled; then
    export TERMUXAI_AUDIT_SESSION_OWNER=0
    return 0
  fi

  if [ -n "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    export TERMUXAI_AUDIT_SESSION_OWNER=0
    if [ -n "$device_id" ] && [ -z "${TERMUXAI_AUDIT_DEVICE_READY:-}" ]; then
      termux::audit_attach_device "$device_id"
    fi
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    export TERMUXAI_AUDIT_SESSION_OWNER=0
    return 0
  fi

  host_root="${TERMUXAI_AUDIT_HOST_ROOT:-${TERMUXAI_AUDIT_HOST_ROOT_DEFAULT}}"
  mkdir -p "$host_root"

  TERMUXAI_AUDIT_SESSION_ID="mirror-$(date +%Y%m%d-%H%M%S)-$$"
  export TERMUXAI_AUDIT_SESSION_ID
  export TERMUXAI_AUDIT_SESSION_DIR="${host_root}/${TERMUXAI_AUDIT_SESSION_ID}"
  export TERMUXAI_AUDIT_EVENTS_FILE="${TERMUXAI_AUDIT_SESSION_DIR}/events.jsonl"
  export TERMUXAI_AUDIT_MANIFEST_FILE="${TERMUXAI_AUDIT_SESSION_DIR}/manifest.json"
  export TERMUXAI_AUDIT_SUMMARY_FILE="${TERMUXAI_AUDIT_SESSION_DIR}/summary.json"
  export TERMUXAI_AUDIT_SUMMARY_MD_FILE="${TERMUXAI_AUDIT_SESSION_DIR}/summary.md"
  export TERMUXAI_AUDIT_REPORT_TXT_FILE="${TERMUXAI_AUDIT_SESSION_DIR}/report.txt"
  export TERMUXAI_AUDIT_LABEL="$label"
  export TERMUXAI_AUDIT_STEP_SEQ=0
  export TERMUXAI_AUDIT_SESSION_OWNER=1
  mkdir -p "${TERMUXAI_AUDIT_SESSION_DIR}"
  : > "${TERMUXAI_AUDIT_EVENTS_FILE}"

  termux::audit_manifest_write "$label" "$script_path" "$device_id"
  termux::audit_emit_record \
    "session_start" \
    "info" \
    "Sessão iniciada: ${label}" \
    "\"label\":\"$(termux::audit_json_escape "$label")\",\"script_path\":\"$(termux::audit_json_escape "$script_path")\",\"device_id\":\"$(termux::audit_json_escape "$device_id")\""

  if [ -n "$device_id" ]; then
    termux::audit_attach_device "$device_id"
  fi
}

termux::audit_session_finish() {
  local exit_code="$1"
  local summary_cmd

  if ! termux::audit_enabled || [ "${TERMUXAI_AUDIT_SESSION_OWNER:-0}" -ne 1 ] 2>/dev/null || [ -z "${TERMUXAI_AUDIT_SESSION_DIR:-}" ]; then
    return 0
  fi

  termux::audit_emit_record \
    "session_finish" \
    "$([ "$exit_code" -eq 0 ] 2>/dev/null && printf 'info' || printf 'error')" \
    "Sessão finalizada com exit_code=${exit_code}" \
    "\"exit_code\":${exit_code}"

  summary_cmd=(python3 "${TERMUX_WORKSPACE_ROOT}/Audit/audit_runner.py" summarize "${TERMUXAI_AUDIT_SESSION_DIR}")
  "${summary_cmd[@]}" >/dev/null 2>&1 || true

  unset TERMUXAI_AUDIT_SESSION_OWNER TERMUXAI_AUDIT_SESSION_ID TERMUXAI_AUDIT_SESSION_DIR
  unset TERMUXAI_AUDIT_EVENTS_FILE TERMUXAI_AUDIT_MANIFEST_FILE TERMUXAI_AUDIT_SUMMARY_FILE TERMUXAI_AUDIT_SUMMARY_MD_FILE
  unset TERMUXAI_AUDIT_REPORT_TXT_FILE TERMUXAI_AUDIT_LABEL TERMUXAI_AUDIT_STEP_SEQ TERMUXAI_AUDIT_CURRENT_STEP_SEQ
  unset TERMUXAI_AUDIT_CURRENT_STEP_LOG TERMUXAI_AUDIT_DEVICE_ID TERMUXAI_AUDIT_DEVICE_DIR TERMUXAI_AUDIT_DEVICE_READY
  unset TERMUXAI_AUDIT_DEVICE_EVENTS_FILE TERMUXAI_AUDIT_DEVICE_MANIFEST_FILE
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

termux::host_cache_root() {
  local cache_root="${TERMUXAI_HOST_CACHE_ROOT:-$TERMUXAI_HOST_CACHE_ROOT_DEFAULT}"
  mkdir -p "$cache_root"
  printf '%s\n' "$cache_root"
}

termux::adb_cache_dir() {
  local cache_dir="${TERMUXAI_ADB_CACHE_DIR:-$TERMUXAI_ADB_CACHE_DIR_DEFAULT}"
  mkdir -p "$cache_dir"
  printf '%s\n' "$cache_dir"
}

termux::adb_cache_file() {
  local file_name="$1"
  printf '%s/%s\n' "$(termux::adb_cache_dir)" "$file_name"
}

termux::adb_cached_network_endpoint() {
  local cache_file

  cache_file="$(termux::adb_cache_file last_network_endpoint)"
  if [ -r "$cache_file" ]; then
    tr -d '\r\n' < "$cache_file"
  fi
}

termux::adb_cached_network_ip() {
  local cache_file

  cache_file="$(termux::adb_cache_file last_network_ip)"
  if [ -r "$cache_file" ]; then
    tr -d '\r\n' < "$cache_file"
  fi
}

termux::adb_cache_network_endpoint() {
  local endpoint="$1"
  local ip_part endpoint_file ip_file

  case "$endpoint" in
    *:*)
      ip_part="${endpoint%%:*}"
      ;;
    *)
      return 0
      ;;
  esac

  endpoint_file="$(termux::adb_cache_file last_network_endpoint)"
  ip_file="$(termux::adb_cache_file last_network_ip)"
  printf '%s\n' "$endpoint" > "$endpoint_file"
  printf '%s\n' "$ip_part" > "$ip_file"
}

termux::ssh_remote_ip() {
  if [ -n "${SSH_CONNECTION:-}" ]; then
    printf '%s\n' "${SSH_CONNECTION%% *}"
    return 0
  fi

  if [ -n "${SSH_CLIENT:-}" ]; then
    printf '%s\n' "${SSH_CLIENT%% *}"
    return 0
  fi

  return 1
}

termux::known_android_ip() {
  local cached_ip cached_endpoint

  if [ -n "${TERMUXAI_LAST_ANDROID_IP:-}" ]; then
    printf '%s\n' "${TERMUXAI_LAST_ANDROID_IP}"
    return 0
  fi

  cached_ip="$(termux::adb_cached_network_ip)"
  if [ -n "$cached_ip" ]; then
    printf '%s\n' "$cached_ip"
    return 0
  fi

  cached_endpoint="$(termux::adb_cached_network_endpoint)"
  case "$cached_endpoint" in
    *:*)
      printf '%s\n' "${cached_endpoint%%:*}"
      return 0
      ;;
  esac

  return 1
}

termux::operator_context() {
  local requested_context="${TERMUXAI_OPERATOR_CONTEXT:-auto}"
  local remote_ip known_ip

  case "$requested_context" in
    android_ssh|local_workstation)
      printf '%s\n' "$requested_context"
      return 0
      ;;
    auto|'')
      ;;
    *)
      requested_context='auto'
      ;;
  esac

  remote_ip="$(termux::ssh_remote_ip 2>/dev/null || true)"
  known_ip="$(termux::known_android_ip 2>/dev/null || true)"

  if [ -n "$remote_ip" ] && [ -n "$known_ip" ] && [ "$remote_ip" = "$known_ip" ]; then
    printf '%s\n' 'android_ssh'
    return 0
  fi

  printf '%s\n' 'local_workstation'
}

termux::no_device_next_step() {
  local recovery_attempted="${1:-0}"
  local operator_context

  operator_context="$(termux::operator_context)"

  case "$operator_context" in
    android_ssh)
      if [ "$recovery_attempted" -eq 1 ] 2>/dev/null; then
        printf '%s' 'Ative manualmente a Depuração por Wi‑Fi no tablet; a recuperação automática já testou os endpoints conhecidos e você pode repetir o mesmo comando em seguida.'
      else
        printf '%s' 'Ative manualmente a Depuração por Wi‑Fi no tablet e repita o mesmo comando.'
      fi
      ;;
    *)
      if [ "$recovery_attempted" -eq 1 ] 2>/dev/null; then
        printf '%s' 'Conecte o tablet por USB ao workstation Linux e repita o comando; esse é o caminho de recuperação validado quando o ADB por Wi‑Fi não está mais disponível.'
      else
        printf '%s' 'Conecte o tablet por USB ao workstation Linux e repita o comando.'
      fi
      ;;
  esac
}

termux::adb_network_device_present() {
  local device_list="$1"

  printf '%s\n' "$device_list" \
    | awk 'NR > 1 && $2 == "device" && $0 !~ / usb:/ && $1 ~ /:/ { found=1 } END { exit(found ? 0 : 1) }'
}

termux::adb_disconnect_offline_network_targets() {
  local serial

  while IFS= read -r serial; do
    [ -n "$serial" ] || continue
    adb disconnect "$serial" >/dev/null 2>&1 || true
  done < <(
    adb devices -l 2>/dev/null \
      | awk 'NR > 1 && $2 == "offline" && $1 ~ /:/ { print $1 }'
  )
}

termux::adb_mdns_candidate_endpoints() {
  adb mdns services 2>/dev/null \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+' \
    | sort -u
}

termux::adb_try_connect_endpoint() {
  local endpoint="$1"
  local output=""
  local timeout_seconds="${TERMUXAI_WIFI_CONNECT_TIMEOUT_SECONDS:-5}"

  case "$endpoint" in
    *:*)
      ;;
    *)
      return 1
      ;;
  esac

  output="$(termux::run_with_timeout "$timeout_seconds" adb connect "$endpoint" 2>&1 || true)"

  if adb devices -l 2>/dev/null | awk -v target="$endpoint" 'NR > 1 && $1 == target && $2 == "device" { found=1 } END { exit(found ? 0 : 1) }'; then
    termux::adb_cache_network_endpoint "$endpoint"
    return 0
  fi

  case "$output" in
    *"connected to "*)
      termux::adb_cache_network_endpoint "$endpoint"
      return 0
      ;;
  esac

  return 1
}

termux::adb_scan_candidate_endpoints_for_ip() {
  local ip_addr="$1"
  local scan_range="${TERMUXAI_WIFI_SCAN_RANGE:-32000-50000}"
  local scan_parallel="${TERMUXAI_WIFI_SCAN_PARALLEL:-64}"
  local scan_timeout="${TERMUXAI_WIFI_SCAN_TIMEOUT_SECONDS:-25}"
  local range_start range_end

  if ! command -v nc >/dev/null 2>&1; then
    return 0
  fi

  case "$scan_range" in
    *-*)
      range_start="${scan_range%-*}"
      range_end="${scan_range#*-}"
      ;;
    *)
      return 0
      ;;
  esac

  if ! [ "$range_start" -ge 1 ] 2>/dev/null || ! [ "$range_end" -ge "$range_start" ] 2>/dev/null; then
    return 0
  fi

  termux::run_with_timeout "$scan_timeout" bash -lc '
    seq "$1" "$2" \
      | xargs -n1 -P"$3" sh -c '"'"'
          host="$1"
          port="$2"
          nc -z -w1 "$host" "$port" >/dev/null 2>&1 && printf "%s:%s\n" "$host" "$port"
        '"'"' _ "$4" \
      | sort -u
  ' _ "$range_start" "$range_end" "$scan_parallel" "$ip_addr" 2>/dev/null || true
}

termux::adb_attempt_wifi_recovery() {
  local before_list after_list candidate endpoint cached_endpoint cached_ip

  before_list="$(adb devices -l 2>&1 || true)"

  if printf '%s\n' "$before_list" | awk 'NR > 1 && $2 == "device" { found=1 } END { exit(found ? 0 : 1) }'; then
    return 0
  fi

  adb reconnect offline >/dev/null 2>&1 || true
  termux::adb_disconnect_offline_network_targets

  after_list="$(adb devices -l 2>&1 || true)"
  if printf '%s\n' "$after_list" | awk 'NR > 1 && $2 == "device" { found=1 } END { exit(found ? 0 : 1) }'; then
    return 0
  fi

  cached_endpoint="$(termux::adb_cached_network_endpoint)"
  cached_ip="$(termux::adb_cached_network_ip)"

  for candidate in \
    "$cached_endpoint" \
    $(printf '%s\n' "$after_list" | awk 'NR > 1 && $1 ~ /:/ { print $1 }') \
    $(termux::adb_mdns_candidate_endpoints)
  do
    [ -n "$candidate" ] || continue
    termux::adb_try_connect_endpoint "$candidate" || true
  done

  after_list="$(adb devices -l 2>&1 || true)"
  if printf '%s\n' "$after_list" | awk 'NR > 1 && $2 == "device" { found=1 } END { exit(found ? 0 : 1) }'; then
    termux::adb_disconnect_offline_network_targets
    return 0
  fi

  if [ -n "$cached_ip" ]; then
    while IFS= read -r endpoint; do
      [ -n "$endpoint" ] || continue
      termux::adb_try_connect_endpoint "$endpoint" || true
    done < <(termux::adb_scan_candidate_endpoints_for_ip "$cached_ip")
  fi

  termux::adb_disconnect_offline_network_targets

  after_list="$(adb devices -l 2>&1 || true)"
  printf '%s\n' "$after_list" | awk 'NR > 1 && $2 == "device" { found=1 } END { exit(found ? 0 : 1) }'
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
  local recovery_attempted=0

  refresh_device_list() {
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
  }

  refresh_device_list

  if [ "$device_count" -eq 0 ]; then
    recovery_attempted=1
    if termux::adb_attempt_wifi_recovery; then
      refresh_device_list
    fi
  fi

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
    termux::adb_cache_network_endpoint "$network_id"
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
      "$(termux::no_device_next_step "$recovery_attempted")"
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
  local command_text

  command_text="adb -s \"$device_id\" $*"
  termux::audit_command "$command_text"

  if ! output=$(termux::run_with_timeout "$timeout_seconds" adb -s "$device_id" "$@" 2>&1); then
    status=$?
    if [ "$status" -eq 124 ]; then
      output="Comando ADB excedeu ${timeout_seconds}s.
${output}"
    fi
    termux::audit_command_result "$status" "$output"
    termux::fail \
      "$command_text" \
      "$output" \
      "$impact_text" \
      "$next_step_text"
  fi

  termux::audit_command_result 0 "$output"
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
      bash "${TERMUX_WORKSPACE_ROOT}/ADB/adb_consolidate_desktop_mode.sh" \
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
