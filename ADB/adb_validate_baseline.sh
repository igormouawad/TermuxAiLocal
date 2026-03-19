#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$SCRIPT_DIR"
WITH_GPU_CHECK=0
REPORT_ENABLED=0
STRESS_SECONDS=0
DESKTOP_PROFILE="openbox"
XFCE_WM="xfwm4"
OPENBOX_PROFILE="openbox-maxperf"
WM_EXPLICIT=0
ANDROID_PRIMARY_USER="0"
X11_UI_REMOTE="/sdcard/Download/termux_x11_baseline_validation.xml"
TERMUX_OUTPUT_LOCAL="$(mktemp)"
X11_UI_LOCAL="$(mktemp)"
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_ROOT="${PROJECT_ROOT}/reports/validate-baseline-${RUN_TIMESTAMP}"
REPORT_SUMMARY="${REPORT_ROOT}/summary.txt"

write_report() {
  local line="$1"

  if [ "$REPORT_ENABLED" -ne 1 ]; then
    return 0
  fi

  mkdir -p "$REPORT_ROOT"
  printf '%s\n' "$line" >> "$REPORT_SUMMARY"
}

persist_artifacts() {
  if [ "$REPORT_ENABLED" -ne 1 ]; then
    return 0
  fi

  mkdir -p "$REPORT_ROOT"

  if [ -s "$TERMUX_OUTPUT_LOCAL" ]; then
    cp "$TERMUX_OUTPUT_LOCAL" "${REPORT_ROOT}/termux-output.log"
  fi

  if [ -s "$X11_UI_LOCAL" ]; then
    cp "$X11_UI_LOCAL" "${REPORT_ROOT}/termux-x11-ui.xml"
  fi
}

cleanup() {
  persist_artifacts
  rm -f "$TERMUX_OUTPUT_LOCAL" "$X11_UI_LOCAL"
}

trap cleanup EXIT

fail() {
  local command_text="$1"
  local error_text="$2"
  local impact_text="$3"
  local next_step_text="$4"

  termux::print_failure "$command_text" "$error_text" "$impact_text" "$next_step_text"
  write_report "status=failed"
  write_report "command=${command_text}"
  write_report "error=${error_text}"
  write_report "impact=${impact_text}"
  write_report "next_step=${next_step_text}"
  exit 1
}

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A validação baseline foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

collect_device_metadata() {
  local manufacturer
  local model
  local android_version
  local board_platform
  local refresh_settings

  manufacturer=$(run_adb shell getprop ro.product.manufacturer | tr -d '\r')
  model=$(run_adb shell getprop ro.product.model | tr -d '\r')
  android_version=$(run_adb shell getprop ro.build.version.release | tr -d '\r')
  board_platform=$(run_adb shell getprop ro.board.platform | tr -d '\r')
  refresh_settings=$(run_adb shell settings list system | grep -E 'peak_refresh_rate|min_refresh_rate' || true)
  refresh_settings=$(printf '%s' "$refresh_settings" | tr '\n' ';' | sed 's/;$//')

  write_report "manufacturer=${manufacturer}"
  write_report "model=${model}"
  write_report "android_version=${android_version}"
  write_report "board_platform=${board_platform}"
  write_report "refresh_settings=${refresh_settings}"
}

require_in_text() {
  local output_text="$1"
  local needle="$2"
  local description="$3"

  if ! printf '%s\n' "$output_text" | grep -Fq "$needle"; then
    fail \
      "$description" \
      "Trecho esperado não encontrado: $needle" \
      'A validação baseline não encontrou a evidência textual esperada no retorno do helper.' \
      'Inspecionar a saída capturada, corrigir o helper alvo e repetir a validação.'
  fi
}

send_termux_command() {
  local command_text="$1"
  local timeout_seconds="$2"
  shift 2

  local output
  local status
  local expected_text
  local -a helper_args=(--device "$DEVICE_ID")

  if [ "$timeout_seconds" -gt 0 ]; then
    helper_args+=(--timeout "$timeout_seconds")
  fi

  for expected_text in "$@"; do
    helper_args+=(--expect "$expected_text")
  done

  set +e
  output=$(bash "${PROJECT_ROOT}/adb_termux_send_command.sh" "${helper_args[@]}" -- "$command_text" 2>&1)
  status=$?
  set -e

  printf '## %s\n%s\n\n' "$command_text" "$output" >> "$TERMUX_OUTPUT_LOCAL"

  if [ "$status" -ne 0 ]; then
    fail \
      "execução do helper adb_termux_send_command.sh para: ${command_text}" \
      "$output" \
      'A validação baseline não conseguiu executar o comando no contexto Termux.' \
      'Corrigir a causa do erro de transporte ou do helper remoto e repetir a validação.'
  fi

  printf '%s\n' "$output"
}

validate_desktop_processes() {
  local process_output
  local wm_pattern

  case "$DESKTOP_PROFILE" in
    openbox)
      process_output="$(send_termux_command \
        'pgrep -af "openbox|aterm|xterm|dbus-daemon|virgl_test_server_android" || true' \
        8
      )"
      if ! printf '%s\n' "$process_output" | grep -Eq '(^| )openbox($| )|openbox-session'; then
        fail \
          'validação de processos do desktop openbox' \
          'Processo openbox não foi encontrado.' \
          'A sessão gráfica leve não parece estar totalmente funcional.' \
          'Reiniciar a sessão com start-openbox-x11 e repetir a validação.'
      fi
      write_report 'desktop_processes=openbox_ok'
      ;;
    xfce)
      process_output="$(send_termux_command \
        'pgrep -af "xfce4-session|xfce4-panel|xfwm4|openbox" || true' \
        8
      )"
      if ! printf '%s\n' "$process_output" | grep -Eq '(^| )xfce4-session($| )'; then
        fail \
          'validação de processos do desktop xfce' \
          'Processo xfce4-session não encontrado.' \
          'A sessão XFCE não parece estar totalmente funcional.' \
          'Reiniciar a sessão com start-xfce-x11 e repetir a validação.'
      fi
      if ! printf '%s\n' "$process_output" | grep -Eq '(^| )xfce4-panel($| )'; then
        fail \
          'validação de processos do desktop xfce' \
          'Processo xfce4-panel não encontrado.' \
          'A sessão XFCE não parece estar totalmente funcional.' \
          'Reiniciar a sessão com start-xfce-x11 e repetir a validação.'
      fi
      wm_pattern="$(termux::desktop_process_pattern "$DESKTOP_PROFILE" "$XFCE_WM")"
      if ! printf '%s\n' "$process_output" | grep -Eq "$wm_pattern"; then
        fail \
          'validação de processos do desktop xfce' \
          "WM ${XFCE_WM} não encontrado." \
          'A sessão XFCE não parece estar totalmente funcional.' \
          'Reiniciar a sessão com start-xfce-x11 e repetir a validação.'
      fi
      write_report 'desktop_processes=xfce_ok'
      ;;
  esac
}

for arg in "$@"; do
  case "$arg" in
    --with-gpu)
      WITH_GPU_CHECK=1
      ;;
    --report)
      REPORT_ENABLED=1
      ;;
    --stress-seconds=*)
      STRESS_SECONDS="${arg#*=}"
      ;;
    --desktop=*)
      DESKTOP_PROFILE="${arg#*=}"
      ;;
    --profile=*)
      OPENBOX_PROFILE="${arg#*=}"
      ;;
    --wm=*)
      XFCE_WM="${arg#*=}"
      WM_EXPLICIT=1
      ;;
    openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp)
      DESKTOP_PROFILE='openbox'
      OPENBOX_PROFILE="$arg"
      ;;
    --wm)
      fail \
        'validação de argumentos' \
        'Use --wm=xfwm4 ou --wm=openbox.' \
        'A validação não consegue inferir o WM do XFCE sem um valor explícito.' \
        'Fornecer --wm=xfwm4 ou --wm=openbox.'
      ;;
    --help|-h)
      printf 'Uso: %s [--with-gpu] [--report] [--stress-seconds=N] [--desktop=openbox|xfce] [--profile=openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp] [--wm=xfwm4|openbox]\n' "$0"
      printf '  --with-gpu  inclui start-virgl + check-gpu-termux na validação.\n'
      printf '  --report    salva resumo, saída dos helpers e dumps XML em reports/.\n'
      printf '  --stress-seconds=N  mantém a sessão Openbox/X11 ativa por N segundos antes do encerramento.\n'
      printf '  --desktop=perfil  escolhe openbox ou xfce para a validação do desktop.\n'
      printf '  --profile=...  escolhe o perfil do Openbox puro.\n'
      printf '  --wm=...    escolhe o WM do XFCE; use openbox para substituir o xfwm4.\n'
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $arg" \
        'A execução não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --with-gpu, --report, --stress-seconds=N, --desktop=openbox|xfce, --profile=..., --wm=xfwm4|openbox ou --help.'
      ;;
  esac
done

if ! [[ "$STRESS_SECONDS" =~ ^[0-9]+$ ]]; then
  fail \
    'validação de argumentos' \
    "Valor inválido para --stress-seconds: ${STRESS_SECONDS}" \
    'A duração do teste de permanência precisa ser numérica.' \
    'Usar um inteiro como --stress-seconds=30.'
fi

if ! termux::desktop_profile_valid "$DESKTOP_PROFILE"; then
    fail \
      'validação de argumentos' \
      "Perfil de desktop inválido: ${DESKTOP_PROFILE}" \
      'A validação não sabe qual sessão gráfica precisa checar.' \
      'Usar --desktop=openbox ou --desktop=xfce.'
fi

if ! termux::openbox_profile_valid "$OPENBOX_PROFILE"; then
    fail \
      'validação de argumentos' \
      "Perfil Openbox inválido: ${OPENBOX_PROFILE}" \
      'A validação não sabe qual baseline do Openbox precisa conferir.' \
      'Usar openbox-stable, openbox-maxperf, openbox-compat ou openbox-vulkan-exp.'
fi

if ! termux::xfce_wm_valid "$XFCE_WM"; then
    fail \
      'validação de argumentos' \
      "WM do XFCE inválido: ${XFCE_WM}" \
      'A validação não sabe qual window manager precisa confirmar dentro do XFCE.' \
      'Usar --wm=xfwm4 ou --wm=openbox.'
fi

if [ "$DESKTOP_PROFILE" != 'xfce' ] && [ "$WM_EXPLICIT" -eq 1 ]; then
  fail \
    'validação de argumentos' \
    '--wm só pode ser usado junto com --desktop=xfce.' \
    'A combinação solicitada não corresponde a um fluxo de desktop suportado.' \
    'Remover --wm ou usar --desktop=xfce.'
fi

write_report "timestamp=${RUN_TIMESTAMP}"
write_report "project_root=${PROJECT_ROOT}"
write_report "with_gpu_check=${WITH_GPU_CHECK}"
write_report "xfce_wm=${XFCE_WM}"
write_report "openbox_profile=${OPENBOX_PROFILE}"
write_report "stress_seconds=${STRESS_SECONDS}"
write_report "desktop_profile=${DESKTOP_PROFILE}"

termux::require_host_command \
  adb \
  'Não é possível validar o dispositivo Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID=$(termux::resolve_target_device)

write_report "device_id=${DEVICE_ID}"
collect_device_metadata

packages_output=$(run_adb shell pm list packages --user "$ANDROID_PRIMARY_USER")

for package_name in com.termux com.termux.api com.termux.x11; do
  if ! printf '%s\n' "$packages_output" | grep -Fxq "package:${package_name}"; then
    fail \
      "auditoria de apps Android obrigatórios no usuário ${ANDROID_PRIMARY_USER}" \
      "App ausente ou inacessível: ${package_name}" \
      'O baseline não pode ser validado sem os apps Android principais.' \
      'Instalar os apps Android obrigatórios no usuário principal do Android e executar novamente.'
  fi
done

write_report 'android_package_audit=ok'

bash "${PROJECT_ROOT}/adb_reset_termux_stack.sh" --focus x11 >/dev/null
if ! termux::wait_for_package_process "$DEVICE_ID" 'com.termux.api' 10 >/dev/null; then
  fail \
    'validação do app Termux:API após reset' \
    "$(run_adb shell ps -A -o NAME,ARGS | grep -F 'com.termux.api' || true)" \
    'O reset terminou sem o processo do app Termux:API ativo, o que foge do estado limpo exigido pelo projeto.' \
    'Restaurar o ecossistema Termux pelo helper de reset e repetir a validação.'
fi
if ! termux::wait_for_x11_surface "$DEVICE_ID" "$X11_UI_REMOTE" "$X11_UI_LOCAL" 10; then
  fail \
    'subida da surface do Termux:X11' \
    'A surface lorieView não apareceu.' \
    'O app Termux:X11 não exibiu a superfície gráfica esperada.' \
    'Reabrir o app Termux:X11 e repetir a operação.'
fi
write_report 'termux_stack_reset=ok'
write_report 'termux_api_process=ok'
write_report 'termux_x11_surface=ok'

desktop_start_helper_name="$(termux::desktop_start_helper "$DESKTOP_PROFILE" 0)"
desktop_stop_helper_name="$(termux::desktop_stop_helper "$DESKTOP_PROFILE")"
desktop_start_command_text="$(termux::desktop_start_command "$DESKTOP_PROFILE" "$OPENBOX_PROFILE" "$XFCE_WM" 0)"
desktop_stop_command_text="$(termux::desktop_stop_command "$DESKTOP_PROFILE")"
desktop_start_expectation="$(termux::desktop_start_message "$DESKTOP_PROFILE" "$OPENBOX_PROFILE" "$XFCE_WM" 0)"
desktop_stop_expectation="$(termux::desktop_stop_message "$DESKTOP_PROFILE")"

start_helper_output="$(send_termux_command "command -v ${desktop_start_helper_name}" 0 "/data/data/com.termux/files/home/bin/${desktop_start_helper_name}")"
stop_helper_output="$(send_termux_command "command -v ${desktop_stop_helper_name}" 0 "/data/data/com.termux/files/home/bin/${desktop_stop_helper_name}")"

require_in_text "$start_helper_output" "/data/data/com.termux/files/home/bin/${desktop_start_helper_name}" 'confirmação do helper de start do desktop'
require_in_text "$stop_helper_output" "/data/data/com.termux/files/home/bin/${desktop_stop_helper_name}" 'confirmação do helper de stop do desktop'

if [ "$WITH_GPU_CHECK" -eq 1 ] && [ "$DESKTOP_PROFILE" = 'xfce' ]; then
  send_termux_command \
    'start-virgl' \
    0 \
    'virgl_test_server_android iniciado em modo' \
    'virgl_test_server_android já está em execução' \
    >/dev/null

  virgl_status_output="$(send_termux_command 'termux-stack-status --brief' 0 'VIRGL=ativo')"
  require_in_text "$virgl_status_output" 'VIRGL=ativo' 'verificação do servidor virgl'
fi

send_termux_command "$desktop_start_command_text" 0 "$desktop_start_expectation" >/dev/null

validate_desktop_processes
write_report "desktop_start=${DESKTOP_PROFILE}_ok"

if [ "$WITH_GPU_CHECK" -eq 1 ]; then
  if [ "$DESKTOP_PROFILE" = 'openbox' ]; then
    virgl_status_output="$(send_termux_command 'termux-stack-status --brief' 0 'VIRGL=ativo')"
    require_in_text "$virgl_status_output" 'VIRGL=ativo' 'verificação do servidor virgl'
  fi
  gpu_probe_output="$(send_termux_command 'check-gpu-termux' 0 'GL_RENDERER: virgl')"
  require_in_text "$gpu_probe_output" 'es2_info exit code: 0' 'execução do diagnóstico EGL/GLES'
  require_in_text "$gpu_probe_output" 'GL_RENDERER: virgl' 'renderer acelerado via virgl'
  write_report 'gpu_phase=ok'
fi

if [ "$STRESS_SECONDS" -gt 0 ]; then
  printf 'Mantendo sessão %s/X11 ativa por %s segundos.\n' "$DESKTOP_PROFILE" "$STRESS_SECONDS"
  write_report "desktop_stress_seconds=${STRESS_SECONDS}"
  sleep "$STRESS_SECONDS"
  if ! termux::wait_for_x11_surface "$DEVICE_ID" "$X11_UI_REMOTE" "$X11_UI_LOCAL" 3; then
    fail \
      'surface do Termux:X11 após permanência' \
      'A surface do Termux:X11 não permaneceu observável pelas fontes host-side disponíveis.' \
      'A validação perdeu a evidência necessária para confirmar a estabilidade curta do display X11.' \
      'Repetir a validação e inspecionar o estado real do app Termux:X11.'
  fi
  validate_desktop_processes
  write_report "desktop_stress=${DESKTOP_PROFILE}_ok"
fi

desktop_stop_output="$(send_termux_command "$desktop_stop_command_text" 0 "$desktop_stop_expectation")"
require_in_text "$desktop_stop_output" "$desktop_stop_expectation" 'encerramento limpo da sessão do desktop/X11'

write_report "desktop_stop=${DESKTOP_PROFILE}_ok"
write_report 'status=success'

printf 'Validação baseline concluída com sucesso.\n'
printf 'Dispositivo: %s\n' "$DEVICE_ID"
printf 'Desktop/X11 (%s): OK\n' "$DESKTOP_PROFILE"

if [ "$WITH_GPU_CHECK" -eq 1 ]; then
  printf 'Virgl/EGL: OK\n'
else
  printf 'Virgl/EGL: não validado nesta execução\n'
fi

printf 'Display unificado: :1\n'
printf 'Script raiz: %s\n' "$PROJECT_ROOT/adb_validate_baseline.sh"

if [ "$REPORT_ENABLED" -eq 1 ]; then
  printf 'Relatório: %s\n' "$REPORT_SUMMARY"
  printf 'Artefatos: %s\n' "$REPORT_ROOT"
fi
