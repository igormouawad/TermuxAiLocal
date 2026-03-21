#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

DEVICE_ID=""
TIMEOUT_SECONDS=0
FOCUS_TERMUX=1
PRESS_ENTER=1
REQUIRE_TERMUX_FOCUS=1
FORCE_UI=0
INTERACTIVE_SHELL=0
QUIET_OUTPUT=0
QUIET_FAILURE_TAIL_LINES=80
AUDIT_OWNER=0

TERMUX_UI_REMOTE="/sdcard/Download/adb_termux_send_command.xml"
TERMUX_UI_LOCAL="$(mktemp)"

TERMUX_HOME="/data/data/com.termux/files/home"
TERMUX_PREFIX="/data/data/com.termux/files/usr"
TERMUX_TMPDIR="/data/data/com.termux/files/usr/tmp"
TERMUX_BASH="/data/data/com.termux/files/usr/bin/bash"
TERMUX_PATH="${TERMUX_HOME}/bin:${TERMUX_PREFIX}/bin:/system/bin:/system/xbin"
REQUEST_ID="termux-bridge-$(date +%Y%m%d-%H%M%S)-$$"
REQUEST_ROOT="${TERMUX_TMPDIR}/codex-bridge"
REQUEST_DIR="${REQUEST_ROOT}/${REQUEST_ID}"
REQUEST_RUNNER="${REQUEST_DIR}/runner.sh"
REQUEST_LAUNCHER="${REQUEST_DIR}/launch.sh"
REQUEST_STDOUT="${REQUEST_DIR}/stdout.log"
REQUEST_STDERR="${REQUEST_DIR}/stderr.log"
REQUEST_STATUS="${REQUEST_DIR}/exit_code"
REQUEST_DONE="${REQUEST_DIR}/done"
REQUEST_PID="${REQUEST_DIR}/pid"
POLL_INTERVAL_SECONDS="${TERMUX_BRIDGE_POLL_INTERVAL_SECONDS:-0.25}"
START_GRACE_SECONDS="${TERMUX_BRIDGE_START_GRACE_SECONDS:-5}"
META_MARKER_BEGIN='__CODEX_TERMUX_META_BEGIN__'
META_MARKER_END='__CODEX_TERMUX_META_END__'

EXPECT_TEXTS=()

cleanup() {
  local exit_code=$?

  rm -f "$TERMUX_UI_LOCAL"

  if [ "${AUDIT_OWNER:-0}" -eq 1 ] 2>/dev/null; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap cleanup EXIT

fail() {
  termux::fail "$@"
}

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A automação do terminal Termux foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

run_adb_internal() {
  local output
  local status
  local timeout_seconds="${TERMUX_ADB_TIMEOUT_SECONDS:-0}"
  local command_text

  command_text="adb -s \"$DEVICE_ID\" $*"

  if ! output=$(termux::run_with_timeout "$timeout_seconds" adb -s "$DEVICE_ID" "$@" 2>&1); then
    status=$?
    if [ "$status" -eq 124 ]; then
      output="Comando ADB excedeu ${timeout_seconds}s.
${output}"
    fi
    termux::fail \
      "$command_text" \
      "$output" \
      'A automação interna do bridge do Termux foi interrompida.' \
      'Corrigir a conectividade ADB ou o erro retornado e executar novamente.'
  fi

  printf '%s\n' "$output"
}

output_matches_expectation() {
  local output_text="$1"
  local expected_text

  if [ "${#EXPECT_TEXTS[@]}" -eq 0 ]; then
    return 0
  fi

  for expected_text in "${EXPECT_TEXTS[@]}"; do
    if printf '%s\n' "$output_text" | grep -Fq "$expected_text"; then
      return 0
    fi
  done

  return 1
}

tail_text_lines() {
  local text="$1"
  local line_count="$2"

  if [ -z "$text" ]; then
    return 0
  fi

  printf '%s\n' "$text" | tail -n "$line_count"
}

dump_termux_ui() {
  run_adb_internal shell uiautomator dump "$TERMUX_UI_REMOTE" >/dev/null
  run_adb_internal shell cat "$TERMUX_UI_REMOTE" > "$TERMUX_UI_LOCAL"
}

wait_for_termux_text() {
  local timeout_seconds="$1"
  local elapsed=0
  local expected_text

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    dump_termux_ui

    for expected_text in "${EXPECT_TEXTS[@]}"; do
      if grep -Fq "$expected_text" "$TERMUX_UI_LOCAL"; then
        return 0
      fi
    done

    sleep 1
    elapsed=$((elapsed + 1))
  done

  fail \
    'espera por retorno no app Termux' \
    "Nenhum dos trechos esperados apareceu no terminal Termux: ${EXPECT_TEXTS[*]}" \
    'O comando foi digitado, mas o retorno esperado não ficou visível dentro do prazo.' \
    'Reabrir o app Termux, confirmar o foco do terminal e repetir a operação.'
}

current_focus() {
  termux::current_focus "$DEVICE_ID"
}

ensure_termux_focus() {
  local attempts=0

  while [ "$attempts" -lt 5 ]; do
    if termux::wait_for_focus "$DEVICE_ID" 'com.termux/.app.TermuxActivity' 1 0.2 >/dev/null 2>&1; then
      return 0
    fi

    run_adb_internal shell am start -n com.termux/.app.TermuxActivity >/dev/null
    run_adb_internal shell input tap 400 500 >/dev/null
    sleep 0.3
    attempts=$((attempts + 1))
  done

  fail \
    'validação de foco do app Termux' \
    "Foco atual após tentativas: $(current_focus)" \
    'O comando não pode ser digitado com segurança no terminal certo.' \
    'Resetar o ecossistema Termux, confirmar o foco e tentar novamente.'
}

send_text_chunk() {
  local chunk="$1"

  if [ -z "$chunk" ]; then
    return 0
  fi

  run_adb_internal shell input text "$chunk" >/dev/null
}

send_command_text_via_ui() {
  local command_text="$1"
  local chunk=""
  local index char

  for ((index = 0; index < ${#command_text}; index++)); do
    char="${command_text:index:1}"

    case "$char" in
      ' ')
        send_text_chunk "$chunk"
        chunk=""
        run_adb_internal shell input keyevent 62 >/dev/null
        ;;
      '/')
        send_text_chunk "$chunk"
        chunk=""
        run_adb_internal shell input keyevent 76 >/dev/null
        ;;
      *)
        chunk+="$char"
        ;;
    esac
  done

  send_text_chunk "$chunk"
}

run_as_supported() {
  adb -s "$DEVICE_ID" shell run-as com.termux id >/dev/null 2>&1
}

run_as_exec_out() {
  local remote_command="$1"

  run_adb_internal exec-out run-as com.termux /system/bin/sh -c "$remote_command"
}

build_run_as_start_command() {
  local quoted_home
  local quoted_prefix
  local quoted_tmpdir
  local quoted_path
  local quoted_ld_path
  local quoted_bash
  local quoted_command_text
  local quoted_request_root
  local quoted_request_dir
  local quoted_request_runner
  local quoted_request_launcher
  local quoted_request_stdout
  local quoted_request_stderr
  local quoted_request_status
  local quoted_request_done
  local quoted_request_pid

  printf -v quoted_home '%q' "$TERMUX_HOME"
  printf -v quoted_prefix '%q' "$TERMUX_PREFIX"
  printf -v quoted_tmpdir '%q' "$TERMUX_TMPDIR"
  printf -v quoted_path '%q' "$TERMUX_PATH"
  printf -v quoted_ld_path '%q' "${TERMUX_PREFIX}/lib"
  printf -v quoted_bash '%q' "$TERMUX_BASH"
  printf -v quoted_command_text '%q' "$COMMAND_TEXT"
  printf -v quoted_request_root '%q' "$REQUEST_ROOT"
  printf -v quoted_request_dir '%q' "$REQUEST_DIR"
  printf -v quoted_request_runner '%q' "$REQUEST_RUNNER"
  printf -v quoted_request_launcher '%q' "$REQUEST_LAUNCHER"
  printf -v quoted_request_stdout '%q' "$REQUEST_STDOUT"
  printf -v quoted_request_stderr '%q' "$REQUEST_STDERR"
  printf -v quoted_request_status '%q' "$REQUEST_STATUS"
  printf -v quoted_request_done '%q' "$REQUEST_DONE"
  printf -v quoted_request_pid '%q' "$REQUEST_PID"

  cat <<EOF
export HOME=$quoted_home
export PREFIX=$quoted_prefix
export TMPDIR=$quoted_tmpdir
export PATH=$quoted_path
export LD_LIBRARY_PATH=$quoted_ld_path
export TERM=xterm-256color
request_root=$quoted_request_root
request_dir=$quoted_request_dir
runner_script=$quoted_request_runner
launcher_script=$quoted_request_launcher
stdout_file=$quoted_request_stdout
stderr_file=$quoted_request_stderr
status_file=$quoted_request_status
done_file=$quoted_request_done
pid_file=$quoted_request_pid
mkdir -p "\$request_root"
rm -rf "\$request_dir"
mkdir -p "\$request_dir"
rm -f "\$status_file" "\$done_file" "\$pid_file"
cat >"\$runner_script" <<'RUNNER_EOF'
#!$TERMUX_BASH
set -euo pipefail
export HOME=$quoted_home
export PREFIX=$quoted_prefix
export TMPDIR=$quoted_tmpdir
export PATH=$quoted_path
export LD_LIBRARY_PATH=$quoted_ld_path
export TERM=xterm-256color
request_dir=$quoted_request_dir
stdout_file=$quoted_request_stdout
stderr_file=$quoted_request_stderr
status_file=$quoted_request_status
done_file=$quoted_request_done
pid_file=$quoted_request_pid
cd $quoted_home
printf '%s\n' "\$\$" >"\$pid_file"
status=0
if $quoted_bash -lc $quoted_command_text >"\$stdout_file" 2>"\$stderr_file"; then
  status=0
else
  status=\$?
fi
printf '%s\n' "\$status" >"\$status_file"
touch "\$done_file"
RUNNER_EOF
chmod 700 "\$runner_script"
: >"\$stdout_file"
: >"\$stderr_file"
nohup $quoted_bash "\$runner_script" >/dev/null 2>&1 < /dev/null &
printf 'REQUEST_ID=%s\n' '$REQUEST_ID'
printf 'REQUEST_DIR=%s\n' "\$request_dir"
EOF
}

build_interactive_prepare_command() {
  local quoted_home
  local quoted_prefix
  local quoted_tmpdir
  local quoted_path
  local quoted_bash
  local quoted_command_text
  local quoted_request_root
  local quoted_request_dir
  local quoted_request_runner
  local quoted_request_launcher
  local quoted_request_stdout
  local quoted_request_stderr
  local quoted_request_status
  local quoted_request_done
  local quoted_request_pid

  printf -v quoted_home '%q' "$TERMUX_HOME"
  printf -v quoted_prefix '%q' "$TERMUX_PREFIX"
  printf -v quoted_tmpdir '%q' "$TERMUX_TMPDIR"
  printf -v quoted_path '%q' "$TERMUX_PATH"
  printf -v quoted_bash '%q' "$TERMUX_BASH"
  printf -v quoted_command_text '%q' "$COMMAND_TEXT"
  printf -v quoted_request_root '%q' "$REQUEST_ROOT"
  printf -v quoted_request_dir '%q' "$REQUEST_DIR"
  printf -v quoted_request_runner '%q' "$REQUEST_RUNNER"
  printf -v quoted_request_launcher '%q' "$REQUEST_LAUNCHER"
  printf -v quoted_request_stdout '%q' "$REQUEST_STDOUT"
  printf -v quoted_request_stderr '%q' "$REQUEST_STDERR"
  printf -v quoted_request_status '%q' "$REQUEST_STATUS"
  printf -v quoted_request_done '%q' "$REQUEST_DONE"
  printf -v quoted_request_pid '%q' "$REQUEST_PID"

  cat <<EOF
export HOME=$quoted_home
export PREFIX=$quoted_prefix
export TMPDIR=$quoted_tmpdir
export PATH=$quoted_path
export TERM=xterm-256color
request_root=$quoted_request_root
request_dir=$quoted_request_dir
runner_script=$quoted_request_runner
launcher_script=$quoted_request_launcher
stdout_file=$quoted_request_stdout
stderr_file=$quoted_request_stderr
status_file=$quoted_request_status
done_file=$quoted_request_done
pid_file=$quoted_request_pid
mkdir -p "\$request_root"
rm -rf "\$request_dir"
mkdir -p "\$request_dir"
rm -f "\$status_file" "\$done_file" "\$pid_file"
cat >"\$runner_script" <<'RUNNER_EOF'
#!$TERMUX_BASH
set -euo pipefail
export HOME=$quoted_home
export PREFIX=$quoted_prefix
export TMPDIR=$quoted_tmpdir
export PATH=$quoted_path
export TERM=xterm-256color
request_dir=$quoted_request_dir
stdout_file=$quoted_request_stdout
stderr_file=$quoted_request_stderr
status_file=$quoted_request_status
done_file=$quoted_request_done
pid_file=$quoted_request_pid
cd $quoted_home
printf '%s\n' "\$\$" >"\$pid_file"
status=0
if $quoted_bash -lc $quoted_command_text >"\$stdout_file" 2>"\$stderr_file"; then
  status=0
else
  status=\$?
fi
printf '%s\n' "\$status" >"\$status_file"
touch "\$done_file"
RUNNER_EOF
cat >"\$launcher_script" <<'LAUNCHER_EOF'
#!$TERMUX_BASH
set -euo pipefail
runner_script=$quoted_request_runner
nohup "\$runner_script" >/dev/null 2>&1 < /dev/null &
LAUNCHER_EOF
chmod 700 "\$runner_script" "\$launcher_script"
: >"\$stdout_file"
: >"\$stderr_file"
printf 'REQUEST_ID=%s\n' '$REQUEST_ID'
printf 'REQUEST_DIR=%s\n' "\$request_dir"
printf 'REQUEST_LAUNCHER=%s\n' "\$launcher_script"
EOF
}

extract_direct_section() {
  local raw_output="$1"
  local marker_begin="$2"
  local marker_end="$3"

  awk -v begin="$marker_begin" -v end="$marker_end" '
    $0 == begin { capture=1; next }
    $0 == end { capture=0; exit }
    capture { print }
  ' <<<"$raw_output"
}

emit_command_output() {
  local stdout_text="$1"
  local stderr_text="$2"

  if [ -n "$stdout_text" ]; then
    printf '%s\n' "$stdout_text"
  fi
  if [ -n "$stderr_text" ]; then
    printf '%s\n' "$stderr_text"
  fi
}

build_run_as_meta_command() {
  local quoted_request_stdout
  local quoted_request_stderr
  local quoted_request_status
  local quoted_request_done
  local quoted_request_pid

  printf -v quoted_request_stdout '%q' "$REQUEST_STDOUT"
  printf -v quoted_request_stderr '%q' "$REQUEST_STDERR"
  printf -v quoted_request_status '%q' "$REQUEST_STATUS"
  printf -v quoted_request_done '%q' "$REQUEST_DONE"
  printf -v quoted_request_pid '%q' "$REQUEST_PID"

  cat <<EOF
stdout_file=$quoted_request_stdout
stderr_file=$quoted_request_stderr
status_file=$quoted_request_status
done_file=$quoted_request_done
pid_file=$quoted_request_pid
stdout_size=0
stderr_size=0
done=0
exit_code=
pid_value=
pid_alive=
if [ -f "\$stdout_file" ]; then
  stdout_size=\$(wc -c < "\$stdout_file" 2>/dev/null || printf '0')
fi
if [ -f "\$stderr_file" ]; then
  stderr_size=\$(wc -c < "\$stderr_file" 2>/dev/null || printf '0')
fi
if [ -f "\$done_file" ]; then
  done=1
fi
if [ -f "\$status_file" ]; then
  exit_code=\$(cat "\$status_file" 2>/dev/null || true)
fi
if [ -f "\$pid_file" ]; then
  pid_value=\$(cat "\$pid_file" 2>/dev/null || true)
fi
case "\$pid_value" in
  ''|*[!0-9]*)
    ;;
  *)
    if kill -0 "\$pid_value" >/dev/null 2>&1; then
      pid_alive=1
    else
      pid_alive=0
    fi
    ;;
esac
printf '%s\n' '$META_MARKER_BEGIN'
printf 'done=%s\n' "\$done"
printf 'stdout_size=%s\n' "\$stdout_size"
printf 'stderr_size=%s\n' "\$stderr_size"
printf 'exit_code=%s\n' "\$exit_code"
printf 'pid=%s\n' "\$pid_value"
printf 'pid_alive=%s\n' "\$pid_alive"
printf '%s\n' '$META_MARKER_END'
EOF
}

fetch_run_as_meta() {
  run_as_exec_out "$(build_run_as_meta_command)"
}

fetch_remote_file_delta() {
  local remote_file="$1"
  local offset_bytes="$2"
  local quoted_remote_file

  printf -v quoted_remote_file '%q' "$remote_file"

  run_as_exec_out "
remote_file=$quoted_remote_file
offset_bytes=$offset_bytes
if [ -f \"\$remote_file\" ]; then
  dd if=\"\$remote_file\" bs=1 skip=\"\$offset_bytes\" 2>/dev/null || true
fi
"
}

cleanup_run_as_request() {
  local quoted_request_dir

  printf -v quoted_request_dir '%q' "$REQUEST_DIR"
  adb -s "$DEVICE_ID" shell run-as com.termux /system/bin/sh -c "rm -rf $quoted_request_dir" >/dev/null 2>&1 || true
}

run_command_via_run_as() {
  local start_output
  local meta_output
  local exit_code=""
  local done_flag=""
  local stdout_size=0
  local stderr_size=0
  local new_stdout_size=""
  local new_stderr_size=""
  local stdout_delta=""
  local stderr_delta=""
  local stdout_output=""
  local stderr_output=""
  local combined_output=""
  local started_at
  local duration_seconds
  local start_request_id
  local finished=0
  local pid_value=""
  local pid_alive=""
  local settle_attempts
  local elapsed_seconds

  started_at="$(date +%s)"
  if [ "${AUDIT_OWNER:-0}" -eq 1 ] 2>/dev/null; then
    termux::audit_note 'HOST' 'Transporte selecionado: run-as+spool.'
    termux::audit_command "$ORIGINAL_COMMAND_TEXT"
  fi
  start_output="$(run_as_exec_out "$(build_run_as_start_command)")"
  start_request_id="$(sed -n 's/^REQUEST_ID=//p' <<<"$start_output" | head -n 1)"

  if [ "$start_request_id" != "$REQUEST_ID" ]; then
    fail \
      'inicialização do job síncrono via run-as' \
      "$start_output" \
      'O host não conseguiu confirmar a criação do job remoto no contexto do app Termux.' \
      'Inspecionar o helper remoto e repetir a operação.'
  fi

  while [ "$finished" -eq 0 ]; do
    meta_output="$(fetch_run_as_meta)"
    done_flag="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^done=//p' | head -n 1)"
    new_stdout_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stdout_size=//p' | head -n 1)"
    new_stderr_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stderr_size=//p' | head -n 1)"
    exit_code="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^exit_code=//p' | head -n 1)"
    pid_value="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid=//p' | head -n 1)"
    pid_alive="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid_alive=//p' | head -n 1)"

    if [[ "$new_stdout_size" =~ ^[0-9]+$ ]] && [ "$new_stdout_size" -gt "$stdout_size" ]; then
      stdout_delta="$(fetch_remote_file_delta "$REQUEST_STDOUT" "$stdout_size")"
      stdout_output+="$stdout_delta"
      if [ "$QUIET_OUTPUT" -eq 0 ]; then
        printf '%s\n' "$stdout_delta"
      fi
      stdout_size="$new_stdout_size"
    fi

    if [[ "$new_stderr_size" =~ ^[0-9]+$ ]] && [ "$new_stderr_size" -gt "$stderr_size" ]; then
      stderr_delta="$(fetch_remote_file_delta "$REQUEST_STDERR" "$stderr_size")"
      stderr_output+="$stderr_delta"
      if [ "$QUIET_OUTPUT" -eq 0 ]; then
        printf '%s\n' "$stderr_delta" >&2
      fi
      stderr_size="$new_stderr_size"
    fi

    if [ "$done_flag" = '1' ] && [[ "${exit_code:-}" =~ ^[0-9]+$ ]]; then
      finished=1
      break
    fi

    elapsed_seconds=$(( $(date +%s) - started_at ))

    if [ "$done_flag" != '1' ] \
      && [ -z "${exit_code:-}" ] \
      && [ -z "${pid_value:-}" ] \
      && [ "$stdout_size" -eq 0 ] \
      && [ "$stderr_size" -eq 0 ] \
      && [ "$elapsed_seconds" -ge "$START_GRACE_SECONDS" ]; then
      fail \
        'bootstrap do job síncrono via run-as+spool' \
        "O request remoto não gerou pid/status/output dentro de ${START_GRACE_SECONDS}s. Request ID=${REQUEST_ID} Request Dir=${REQUEST_DIR}" \
        'O job no contexto do app Termux ficou preso antes de iniciar de fato, então o polling permaneceria infinito.' \
        'Inspecionar o request remoto, corrigir a preparação do runner e repetir a operação.'
    fi

    if [ "$done_flag" != '1' ] && [[ "${pid_value:-}" =~ ^[0-9]+$ ]] && [ "${pid_alive:-}" = '0' ]; then
      settle_attempts=0
      while [ "$settle_attempts" -lt 4 ]; do
        sleep 0.2
        meta_output="$(fetch_run_as_meta)"
        done_flag="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^done=//p' | head -n 1)"
        exit_code="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^exit_code=//p' | head -n 1)"
        pid_value="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid=//p' | head -n 1)"
        pid_alive="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid_alive=//p' | head -n 1)"
        if [ "$done_flag" = '1' ] && [[ "${exit_code:-}" =~ ^[0-9]+$ ]]; then
          finished=1
          break
        fi
        settle_attempts=$((settle_attempts + 1))
      done

      if [ "$finished" -eq 1 ]; then
        break
      fi

      fail \
        'execução síncrona via run-as+spool' \
        "O processo remoto terminou sem gravar done/status. PID=${pid_value} Request ID=${REQUEST_ID} Request Dir=${REQUEST_DIR}" \
        'O job no contexto do app Termux morreu antes de registrar o estado final, então a sincronização ficou inconsistente.' \
        'Inspecionar stdout/stderr do request remoto e corrigir a causa da terminação prematura.'
    fi

    if [ "${TIMEOUT_SECONDS:-0}" -gt 0 ] && [ $(( $(date +%s) - started_at )) -ge "$TIMEOUT_SECONDS" ]; then
      fail \
        'execução síncrona via run-as+spool' \
        "O comando excedeu ${TIMEOUT_SECONDS}s. Request ID=${REQUEST_ID} Request Dir=${REQUEST_DIR}" \
        'O job remoto no contexto do app Termux não concluiu dentro do limite configurado.' \
        'Inspecionar o request remoto, reduzir o escopo do comando ou aumentar pontualmente o timeout.'
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done

  meta_output="$(fetch_run_as_meta)"
  new_stdout_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stdout_size=//p' | head -n 1)"
  new_stderr_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stderr_size=//p' | head -n 1)"
  exit_code="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^exit_code=//p' | head -n 1)"

  if [[ "$new_stdout_size" =~ ^[0-9]+$ ]] && [ "$new_stdout_size" -gt "$stdout_size" ]; then
    stdout_delta="$(fetch_remote_file_delta "$REQUEST_STDOUT" "$stdout_size")"
    stdout_output+="$stdout_delta"
    if [ "$QUIET_OUTPUT" -eq 0 ]; then
      printf '%s\n' "$stdout_delta"
    fi
    stdout_size="$new_stdout_size"
  fi

  if [[ "$new_stderr_size" =~ ^[0-9]+$ ]] && [ "$new_stderr_size" -gt "$stderr_size" ]; then
    stderr_delta="$(fetch_remote_file_delta "$REQUEST_STDERR" "$stderr_size")"
    stderr_output+="$stderr_delta"
    if [ "$QUIET_OUTPUT" -eq 0 ]; then
      printf '%s\n' "$stderr_delta" >&2
    fi
    stderr_size="$new_stderr_size"
  fi

  duration_seconds=$(( $(date +%s) - started_at ))
  combined_output="$stdout_output"
  if [ -n "$stderr_output" ]; then
    if [ -n "$combined_output" ]; then
      combined_output+=$'\n'
    fi
    combined_output+="$stderr_output"
  fi

  if ! [[ "${exit_code:-}" =~ ^[0-9]+$ ]]; then
    fail \
      'parse do metadado do job síncrono via run-as' \
      "$meta_output" \
      'O host não conseguiu determinar o exit code do comando executado no contexto do Termux.' \
      'Revisar o request remoto e repetir a operação.'
  fi

  if [ "$exit_code" -ne 0 ]; then
    if [ "$QUIET_OUTPUT" -eq 1 ]; then
      combined_output="$(tail_text_lines "$combined_output" "$QUIET_FAILURE_TAIL_LINES")"
    fi
    fail \
      "execução remota no contexto Termux retornou ${exit_code}" \
      "${combined_output}
Request ID=${REQUEST_ID}
Request Dir=${REQUEST_DIR}" \
      'O comando executou no contexto do app Termux, mas terminou com erro.' \
      'Corrigir o helper remoto ou o comando solicitado antes de repetir a operação.'
  fi

  if ! output_matches_expectation "$combined_output"; then
    if [ "$QUIET_OUTPUT" -eq 1 ]; then
      combined_output="$(tail_text_lines "$combined_output" "$QUIET_FAILURE_TAIL_LINES")"
    fi
    fail \
      'validação do retorno em transporte síncrono run-as' \
      "Nenhum dos trechos esperados apareceu na saída do comando: ${EXPECT_TEXTS[*]}
Request ID=${REQUEST_ID}
Request Dir=${REQUEST_DIR}" \
      'O comando executou no contexto do app Termux, mas o retorno não correspondeu ao estado esperado.' \
      'Inspecionar a saída capturada, corrigir o helper alvo e repetir a operação.'
  fi

  if [ "${AUDIT_OWNER:-0}" -eq 1 ] 2>/dev/null; then
    termux::audit_command_result "$exit_code" "$combined_output"
  fi

  cleanup_run_as_request
  termux::stderr 'Transporte usado: run-as+spool'
  termux::stderr "Request ID: ${REQUEST_ID}"
  termux::stderr "Duração: ${duration_seconds}s"
}

run_command_via_interactive_shell() {
  local prepare_output
  local meta_output
  local exit_code=""
  local done_flag=""
  local stdout_size=0
  local stderr_size=0
  local new_stdout_size=""
  local new_stderr_size=""
  local stdout_delta=""
  local stderr_delta=""
  local stdout_output=""
  local stderr_output=""
  local combined_output=""
  local started_at
  local duration_seconds
  local prepared_request_id
  local prepared_launcher=""
  local finished=0
  local pid_value=""
  local pid_alive=""
  local settle_attempts
  local elapsed_seconds

  if ! run_as_supported; then
    fail \
      'validação do transporte interactive-shell+spool' \
      'run-as com.termux indisponível para preparação/polling.' \
      'O transporte interativo com spool exige o APK debug do GitHub com run-as funcional.' \
      'Usar os APKs oficiais debug do workspace ou recorrer explicitamente ao fallback por UI.'
  fi

  prepare_output="$(run_as_exec_out "$(build_interactive_prepare_command)")"
  prepared_request_id="$(sed -n 's/^REQUEST_ID=//p' <<<"$prepare_output" | head -n 1)"
  prepared_launcher="$(sed -n 's/^REQUEST_LAUNCHER=//p' <<<"$prepare_output" | head -n 1)"

  if [ "$prepared_request_id" != "$REQUEST_ID" ] || [ -z "$prepared_launcher" ]; then
    fail \
      'preparação do job interativo com spool' \
      "$prepare_output" \
      'O host não conseguiu preparar o request que será disparado no shell real do app Termux.' \
      'Inspecionar o helper remoto e repetir a operação.'
  fi

  if [ "$FOCUS_TERMUX" -eq 1 ] || [ "$REQUIRE_TERMUX_FOCUS" -eq 1 ]; then
    ensure_termux_focus
  fi

  if [ "${AUDIT_OWNER:-0}" -eq 1 ] 2>/dev/null; then
    termux::audit_note 'HOST' 'Transporte selecionado: interactive-shell+spool.'
    termux::audit_command "$ORIGINAL_COMMAND_TEXT"
  fi

  send_command_text_via_ui "$prepared_launcher"

  if [ "$PRESS_ENTER" -eq 1 ]; then
    run_adb_internal shell input keyevent 66 >/dev/null
  fi

  started_at="$(date +%s)"

  while [ "$finished" -eq 0 ]; do
    meta_output="$(fetch_run_as_meta)"
    done_flag="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^done=//p' | head -n 1)"
    new_stdout_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stdout_size=//p' | head -n 1)"
    new_stderr_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stderr_size=//p' | head -n 1)"
    exit_code="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^exit_code=//p' | head -n 1)"
    pid_value="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid=//p' | head -n 1)"
    pid_alive="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid_alive=//p' | head -n 1)"

    if [[ "$new_stdout_size" =~ ^[0-9]+$ ]] && [ "$new_stdout_size" -gt "$stdout_size" ]; then
      stdout_delta="$(fetch_remote_file_delta "$REQUEST_STDOUT" "$stdout_size")"
      stdout_output+="$stdout_delta"
      if [ "$QUIET_OUTPUT" -eq 0 ]; then
        printf '%s\n' "$stdout_delta"
      fi
      stdout_size="$new_stdout_size"
    fi

    if [[ "$new_stderr_size" =~ ^[0-9]+$ ]] && [ "$new_stderr_size" -gt "$stderr_size" ]; then
      stderr_delta="$(fetch_remote_file_delta "$REQUEST_STDERR" "$stderr_size")"
      stderr_output+="$stderr_delta"
      if [ "$QUIET_OUTPUT" -eq 0 ]; then
        printf '%s\n' "$stderr_delta" >&2
      fi
      stderr_size="$new_stderr_size"
    fi

    if [ "$done_flag" = '1' ] && [[ "${exit_code:-}" =~ ^[0-9]+$ ]]; then
      finished=1
      break
    fi

    elapsed_seconds=$(( $(date +%s) - started_at ))

    if [ "$done_flag" != '1' ] \
      && [ -z "${exit_code:-}" ] \
      && [ -z "${pid_value:-}" ] \
      && [ "$stdout_size" -eq 0 ] \
      && [ "$stderr_size" -eq 0 ] \
      && [ "$elapsed_seconds" -ge "$START_GRACE_SECONDS" ]; then
      fail \
        'bootstrap do job interativo com spool' \
        "O request remoto não gerou pid/status/output dentro de ${START_GRACE_SECONDS}s. Request ID=${REQUEST_ID} Request Dir=${REQUEST_DIR}" \
        'O job disparado no shell real do app Termux ficou preso antes de iniciar de fato, então o polling permaneceria infinito.' \
        'Inspecionar o request remoto, corrigir a preparação do runner e repetir a operação.'
    fi

    if [ "$done_flag" != '1' ] && [[ "${pid_value:-}" =~ ^[0-9]+$ ]] && [ "${pid_alive:-}" = '0' ]; then
      settle_attempts=0
      while [ "$settle_attempts" -lt 4 ]; do
        sleep 0.2
        meta_output="$(fetch_run_as_meta)"
        done_flag="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^done=//p' | head -n 1)"
        exit_code="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^exit_code=//p' | head -n 1)"
        pid_value="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid=//p' | head -n 1)"
        pid_alive="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^pid_alive=//p' | head -n 1)"
        if [ "$done_flag" = '1' ] && [[ "${exit_code:-}" =~ ^[0-9]+$ ]]; then
          finished=1
          break
        fi
        settle_attempts=$((settle_attempts + 1))
      done

      if [ "$finished" -eq 1 ]; then
        break
      fi

      fail \
        'execução interativa via shell real + spool' \
        "O processo remoto terminou sem gravar done/status. PID=${pid_value} Request ID=${REQUEST_ID} Request Dir=${REQUEST_DIR}" \
        'O job disparado no shell real do app Termux morreu antes de registrar o estado final, então a sincronização ficou inconsistente.' \
        'Inspecionar stdout/stderr do request remoto e corrigir a causa da terminação prematura.'
    fi

    if [ "${TIMEOUT_SECONDS:-0}" -gt 0 ] && [ $(( $(date +%s) - started_at )) -ge "$TIMEOUT_SECONDS" ]; then
      fail \
        'execução interativa via shell real + spool' \
        "O comando excedeu ${TIMEOUT_SECONDS}s. Request ID=${REQUEST_ID} Request Dir=${REQUEST_DIR}" \
        'O job disparado no shell real do app Termux não concluiu dentro do limite configurado.' \
        'Inspecionar o request remoto, reduzir o escopo do comando ou aumentar pontualmente o timeout.'
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done

  meta_output="$(fetch_run_as_meta)"
  new_stdout_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stdout_size=//p' | head -n 1)"
  new_stderr_size="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^stderr_size=//p' | head -n 1)"
  exit_code="$(extract_direct_section "$meta_output" "$META_MARKER_BEGIN" "$META_MARKER_END" | sed -n 's/^exit_code=//p' | head -n 1)"

  if [[ "$new_stdout_size" =~ ^[0-9]+$ ]] && [ "$new_stdout_size" -gt "$stdout_size" ]; then
    stdout_delta="$(fetch_remote_file_delta "$REQUEST_STDOUT" "$stdout_size")"
    stdout_output+="$stdout_delta"
    if [ "$QUIET_OUTPUT" -eq 0 ]; then
      printf '%s\n' "$stdout_delta"
    fi
    stdout_size="$new_stdout_size"
  fi

  if [[ "$new_stderr_size" =~ ^[0-9]+$ ]] && [ "$new_stderr_size" -gt "$stderr_size" ]; then
    stderr_delta="$(fetch_remote_file_delta "$REQUEST_STDERR" "$stderr_size")"
    stderr_output+="$stderr_delta"
    if [ "$QUIET_OUTPUT" -eq 0 ]; then
      printf '%s\n' "$stderr_delta" >&2
    fi
    stderr_size="$new_stderr_size"
  fi

  duration_seconds=$(( $(date +%s) - started_at ))
  combined_output="$stdout_output"
  if [ -n "$stderr_output" ]; then
    if [ -n "$combined_output" ]; then
      combined_output+=$'\n'
    fi
    combined_output+="$stderr_output"
  fi

  if ! [[ "${exit_code:-}" =~ ^[0-9]+$ ]]; then
    fail \
      'parse do metadado do job interativo com spool' \
      "$meta_output" \
      'O host não conseguiu determinar o exit code do comando executado no shell real do Termux.' \
      'Revisar o request remoto e repetir a operação.'
  fi

  if [ "$exit_code" -ne 0 ]; then
    if [ "$QUIET_OUTPUT" -eq 1 ]; then
      combined_output="$(tail_text_lines "$combined_output" "$QUIET_FAILURE_TAIL_LINES")"
    fi
    fail \
      "execução interativa no shell real do Termux retornou ${exit_code}" \
      "${combined_output}
Request ID=${REQUEST_ID}
Request Dir=${REQUEST_DIR}" \
      'O comando executou no shell real do app Termux, mas terminou com erro.' \
      'Corrigir o helper remoto ou o comando solicitado antes de repetir a operação.'
  fi

  if ! output_matches_expectation "$combined_output"; then
    if [ "$QUIET_OUTPUT" -eq 1 ]; then
      combined_output="$(tail_text_lines "$combined_output" "$QUIET_FAILURE_TAIL_LINES")"
    fi
    fail \
      'validação do retorno em transporte interactive-shell+spool' \
      "Nenhum dos trechos esperados apareceu na saída do comando: ${EXPECT_TEXTS[*]}
Request ID=${REQUEST_ID}
Request Dir=${REQUEST_DIR}" \
      'O comando executou no shell real do app Termux, mas o retorno não correspondeu ao estado esperado.' \
      'Inspecionar a saída capturada, corrigir o helper alvo e repetir a operação.'
  fi

  if [ "${AUDIT_OWNER:-0}" -eq 1 ] 2>/dev/null; then
    termux::audit_command_result "$exit_code" "$combined_output"
  fi

  cleanup_run_as_request
  termux::stderr 'Transporte usado: interactive-shell+spool'
  termux::stderr "Request ID: ${REQUEST_ID}"
  termux::stderr "Duração: ${duration_seconds}s"
  termux::stderr "Linha enviada ao shell real do Termux: ${ORIGINAL_COMMAND_TEXT}"
}

run_command_via_ui() {
  if [ "$FOCUS_TERMUX" -eq 1 ]; then
    ensure_termux_focus
  elif [ "$REQUIRE_TERMUX_FOCUS" -eq 1 ]; then
    ensure_termux_focus
  fi

  if [ "${AUDIT_OWNER:-0}" -eq 1 ] 2>/dev/null; then
    termux::audit_note 'HOST' 'Transporte selecionado: ui-fallback.'
    termux::audit_command "$ORIGINAL_COMMAND_TEXT"
  fi

  send_command_text_via_ui "$COMMAND_TEXT"

  if [ "$PRESS_ENTER" -eq 1 ]; then
    run_adb_internal shell input keyevent 66 >/dev/null
  fi

  if [ "${#EXPECT_TEXTS[@]}" -gt 0 ] && [ "$TIMEOUT_SECONDS" -gt 0 ]; then
    wait_for_termux_text "$TIMEOUT_SECONDS"
  fi

  if [ "${AUDIT_OWNER:-0}" -eq 1 ] 2>/dev/null; then
    termux::audit_command_result 0 'Comando enviado via fallback de UI sem erro explícito.'
  fi

  termux::stderr "Transporte usado: ui-fallback"
}

build_command_text_from_args() {
  local command_text=""
  local arg

  for arg in "$@"; do
    command_text="$(termux::append_shell_word "$command_text" "$arg")"
  done

  printf '%s\n' "$command_text"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      shift
      DEVICE_ID="${1:-}"
      shift || true
      ;;
    --expect)
      shift
      EXPECT_TEXTS+=("${1:-}")
      shift || true
      ;;
    --timeout)
      shift
      TIMEOUT_SECONDS="${1:-0}"
      shift || true
      ;;
    --no-focus)
      FOCUS_TERMUX=0
      shift
      ;;
    --no-enter)
      PRESS_ENTER=0
      shift
      ;;
    --no-focus-check)
      REQUIRE_TERMUX_FOCUS=0
      shift
      ;;
    --force-ui)
      FORCE_UI=1
      shift
      ;;
    --interactive-shell)
      INTERACTIVE_SHELL=1
      shift
      ;;
    --quiet-output)
      QUIET_OUTPUT=1
      shift
      ;;
    --help|-h)
      printf 'Uso: %s [--device SERIAL] [--expect texto] [--timeout N] [--force-ui] [--interactive-shell] [--quiet-output] -- comando\n' "$0"
      printf '  sem --device, o helper prefere USB quando houver um alvo direto conectado; sem USB, tenta um unico alvo por rede. Em casos ambiguos, use --device SERIAL ou TERMUXAI_DEVICE_ID=SERIAL.\n'
      printf '  --expect texto   pode ser repetido; qualquer ocorrência satisfaz a validação.\n'
      printf '  --timeout N      watchdog opcional do job síncrono run-as; sem ele, a espera fica explícita até o fim.\n'
      printf '  --force-ui       ignora run-as+spool e força o transporte legado por foco/UI.\n'
      printf '  --interactive-shell  prepara o request via run-as, mas dispara o comando no shell real do app Termux e faz polling estruturado do resultado.\n'
      printf '  --quiet-output   suprime o streaming contínuo de stdout/stderr; útil para jobs longos no Continue.\n'
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -eq 0 ]; then
  fail \
    'validação de argumentos' \
    'Nenhum comando foi informado.' \
    'Não há conteúdo para executar no Termux.' \
    'Passar o comando após --.'
fi

DEVICE_ID="$(termux::resolve_target_device "$DEVICE_ID")"

if [ "$#" -eq 1 ]; then
COMMAND_TEXT="$1"
else
  COMMAND_TEXT="$(build_command_text_from_args "$@")"
fi

ORIGINAL_COMMAND_TEXT="$COMMAND_TEXT"

termux::audit_session_begin 'Comando direto no Termux' "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
if [ "$AUDIT_OWNER" -eq 1 ] 2>/dev/null; then
  termux::audit_step_begin 1 1 'HOST' 'Executando comando direto no Termux' 100
  termux::audit_note 'HOST' "Dispositivo alvo: ${DEVICE_ID}"
fi

if [ "$FORCE_UI" -eq 1 ] && [ "$INTERACTIVE_SHELL" -eq 1 ]; then
  fail \
    'validação de argumentos' \
    'Os modos --force-ui e --interactive-shell são mutuamente exclusivos.' \
    'O helper não sabe qual transporte deve priorizar.' \
    'Usar apenas um dos modos especiais por execução.'
fi

if [ "$INTERACTIVE_SHELL" -eq 1 ]; then
  run_command_via_interactive_shell
elif [ "$FORCE_UI" -eq 0 ] && run_as_supported; then
  run_command_via_run_as
else
  run_command_via_ui
fi

if [ "$AUDIT_OWNER" -eq 1 ] 2>/dev/null; then
  termux::audit_step_finish 'OK' 1 1 'HOST' 'Comando direto no Termux concluído.' 100
fi

termux::stderr "Comando enviado ao Termux no dispositivo ${DEVICE_ID}."
termux::stderr "Linha enviada: ${ORIGINAL_COMMAND_TEXT}"
