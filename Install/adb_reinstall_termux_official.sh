#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/termux_common.sh
source "${WORKSPACE_ROOT}/lib/termux_common.sh"

INSTALL_ROOT="$SCRIPT_DIR"
MAIN_PAYLOAD_SOURCE="${INSTALL_ROOT}/install_termux_stack.sh"
BOOTSTRAP_SOURCE="${INSTALL_ROOT}/install_termux_repo_bootstrap.sh"
TERMUX_MENU_SOURCE="${INSTALL_ROOT}/termux_workspace_menu.sh"
AUDIT_RUNNER_SOURCE="${WORKSPACE_ROOT}/Audit/audit_runner.py"
AUDIT_PROFILES_SOURCE="${WORKSPACE_ROOT}/Audit/profiles"
TERMUX_SEND_COMMAND_SCRIPT="${WORKSPACE_ROOT}/ADB/adb_termux_send_command.sh"
MAIN_PAYLOAD_TARGET="/data/local/tmp/install_termux_stack.sh"
BOOTSTRAP_TARGET="/data/local/tmp/install_termux_repo_bootstrap.sh"
TERMUX_MENU_TARGET="/data/local/tmp/termux_workspace_menu.sh"
AUDIT_RUNNER_TARGET="/data/local/tmp/termuxai_audit_runner.py"
AUDIT_PROFILES_TARGET="/data/local/tmp/termuxai_audit_profiles"
DOWNLOAD_DIR="${INSTALL_ROOT}/.cache/termux-apks"
TERMUX_APP_API="https://api.github.com/repos/termux/termux-app/releases/latest"
TERMUX_API_API="https://api.github.com/repos/termux/termux-api/releases/latest"
TERMUX_X11_API="https://api.github.com/repos/termux/termux-x11/releases/tags/nightly"
DRY_RUN=0
TOTAL_STEPS=12
CURRENT_STEP=0
REQUIRED_PACKAGES=(
  "com.termux"
  "com.termux.api"
  "com.termux.x11"
)
ADB_INSTALL_FLAGS=(
  "-r"
  "-g"
)
SPECIAL_ACCESS_PACKAGES=(
  "com.termux"
  "com.termux.api"
)
SHARED_STORAGE_RESIDUE_PATHS=(
  "/sdcard/Android/data/com.termux"
  "/sdcard/Android/data/com.termux.api"
  "/sdcard/Android/data/com.termux.x11"
  "/sdcard/Android/media/com.termux"
  "/sdcard/Android/media/com.termux.api"
  "/sdcard/Android/media/com.termux.x11"
  "/sdcard/Download/termux_ui_now.xml"
  "/sdcard/Download/termux_ui_now2.xml"
  "/sdcard/Download/termux_x11_baseline_validation.xml"
  "/sdcard/Download/codex-termux-bootstrap.xml"
)
TMP_RESIDUE_PATHS=(
  "/data/local/tmp/install_termux_stack.sh"
  "/data/local/tmp/install_termux_repo_bootstrap.sh"
  "/data/local/tmp/termux_workspace_menu.sh"
  "/data/local/tmp/termuxai_audit_runner.py"
  "/data/local/tmp/termuxai_audit_profiles"
  "/data/local/tmp/adb-x11-command-*.sh"
  "/data/local/tmp/glmark2-score-*.log"
)
AUDIT_OWNER=0
BOOTSTRAP_AUDIT_HELPER_PID=""

log_step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  termux::progress_step "$CURRENT_STEP" "$TOTAL_STEPS" 'HOST' "$1"
}

log_ok() {
  termux::progress_result 'OK' "$CURRENT_STEP" "$TOTAL_STEPS" 'HOST' "$1"
}

fail() {
  termux::fail "$@"
}

finish_audit() {
  local exit_code=$?

  if [ -n "$BOOTSTRAP_AUDIT_HELPER_PID" ]; then
    kill "$BOOTSTRAP_AUDIT_HELPER_PID" >/dev/null 2>&1 || true
    wait "$BOOTSTRAP_AUDIT_HELPER_PID" >/dev/null 2>&1 || true
  fi

  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap finish_audit EXIT

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A reinstalação oficial da stack Termux foi interrompida no dispositivo Android.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

run_adb_best_effort() {
  adb -s "$DEVICE_ID" "$@" >/dev/null 2>&1 || true
}

ensure_host_dependency() {
  local binary_name="$1"

  termux::require_host_command \
    "$binary_name" \
    'O script não consegue resolver releases oficiais ou transferir os payloads ao dispositivo.' \
    "Instalar $binary_name no host e executar novamente."
}

ensure_termux_send_command_helper() {
  if [ ! -f "$TERMUX_SEND_COMMAND_SCRIPT" ]; then
    fail \
      "test -f \"$TERMUX_SEND_COMMAND_SCRIPT\"" \
      "Helper host-side ausente para bootstrap automatico do app Termux." \
      "A reinstalacao terminou sem o wrapper canonico para continuar no shell real do Termux." \
      "Restaurar ADB/adb_termux_send_command.sh no workspace e repetir a reinstalacao."
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      printf 'Uso: %s [--dry-run]\n' "$0"
      printf '  --dry-run  valida device, releases e downloads sem desinstalar ou instalar APKs.\n'
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'O fluxo de reinstalação não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --dry-run ou --help.'
      ;;
  esac
done

if [ "$DRY_RUN" -eq 1 ]; then
  TOTAL_STEPS=7
else
  TOTAL_STEPS=15
fi

resolve_device() {
  DEVICE_ID=$(termux::resolve_target_device)
  termux::audit_session_begin 'Reinstalação oficial do ecossistema Termux' "$0" "$DEVICE_ID"
  AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
}

verify_device_abi() {
  local abi

  abi=$(run_adb shell getprop ro.product.cpu.abi | tr -d '\r')

  if [ "$abi" != "arm64-v8a" ]; then
    fail \
      "adb -s \"$DEVICE_ID\" shell getprop ro.product.cpu.abi" \
      "ABI detectada: $abi" \
      "O fluxo atual foi desenhado apenas para os APKs ARM64 oficiais do projeto." \
      "Usar um dispositivo arm64-v8a ou adaptar explicitamente a seleção de assets."
  fi
}

fetch_release_json() {
  local api_url="$1"
  local output_file="$2"
  local curl_output

  if ! curl_output=$(curl --fail --silent --show-error --location "$api_url" -o "$output_file" 2>&1); then
    fail \
      "curl --fail --silent --show-error --location \"$api_url\" -o \"$output_file\"" \
      "$curl_output" \
      "Não foi possível consultar a API oficial de releases do ecossistema Termux." \
      "Verificar conectividade do host e repetir a operação."
  fi

  if [ ! -s "$output_file" ]; then
    fail \
      "download da API $api_url" \
      "Resposta vazia recebida da API." \
      "O script não consegue resolver os APKs oficiais a instalar." \
      "Repetir a operação quando a API responder corretamente."
  fi
}

resolve_asset_url() {
  local json_file="$1"
  local repo_label="$2"
  local regex_pattern="$3"
  local resolved_url

  if ! resolved_url=$(python3 - "$json_file" "$regex_pattern" 2>&1 <<'PY'
import json
import re
import sys

json_path = sys.argv[1]
pattern = re.compile(sys.argv[2])

with open(json_path, 'r', encoding='utf-8') as handle:
    payload = json.load(handle)

matches = []
for asset in payload.get('assets', []):
    name = asset.get('name', '')
    url = asset.get('browser_download_url', '')
    if pattern.fullmatch(name):
        matches.append(url)

if len(matches) != 1:
    sys.stderr.write(f'matches={len(matches)}\n')
    for candidate in matches:
        sys.stderr.write(candidate + '\n')
    sys.exit(1)

print(matches[0])
PY
  ); then
    fail \
      "seleção do asset oficial de $repo_label" \
      "$resolved_url" \
      "O script não conseguiu identificar de forma inequívoca o APK oficial correto para esse componente." \
      "Ajustar a regex de seleção ou revisar a release upstream antes de repetir a operação."
  fi

  if ! printf '%s\n' "$resolved_url" | grep -Eq '^https://github\.com/termux/'; then
    fail \
      "validação da URL oficial de $repo_label" \
      "URL resolvida fora do owner termux: $resolved_url" \
      "A cadeia de origem dos APKs ficou insegura para este fluxo." \
      "Revisar a resposta da API e permitir apenas URLs oficiais do ecossistema termux."
  fi

  printf '%s\n' "$resolved_url"
}

download_asset() {
  local asset_url="$1"
  local output_path="$2"
  local curl_output

  if ! curl_output=$(curl --fail --silent --show-error --location "$asset_url" -o "$output_path" 2>&1); then
    fail \
      "curl --fail --silent --show-error --location \"$asset_url\" -o \"$output_path\"" \
      "$curl_output" \
      "O APK oficial não pôde ser baixado no host." \
      "Verificar conectividade do host ou o estado da release oficial e repetir."
  fi

  if [ ! -s "$output_path" ]; then
    fail \
      "download do asset $asset_url" \
      "Arquivo baixado vazio em $output_path." \
      "O fluxo não pode continuar com APK possivelmente corrompido." \
      "Remover o arquivo vazio e repetir a operação."
  fi
}

cleanup_project_residue() {
  local package_name
  local path_name

  log_step 'Limpando resíduos controlados do projeto no dispositivo.'

  for package_name in "${REQUIRED_PACKAGES[@]}"; do
    run_adb_best_effort shell am force-stop "$package_name"
    run_adb_best_effort shell pm clear "$package_name"
    run_adb_best_effort shell cmd appops reset "$package_name"
    run_adb_best_effort shell dumpsys deviceidle whitelist -"$package_name"
  done

  run_adb_best_effort shell sh -lc '
    pkill -x termux-x11 >/dev/null 2>&1 || true
    pkill -x virgl_test_server_android >/dev/null 2>&1 || true
    pkill -x openbox >/dev/null 2>&1 || true
    pkill -x aterm >/dev/null 2>&1 || true
    pkill -x xeyes >/dev/null 2>&1 || true
    pkill -x dbus-run-session >/dev/null 2>&1 || true
    pkill -x proot >/dev/null 2>&1 || true
  '

  for path_name in "${TMP_RESIDUE_PATHS[@]}"; do
    run_adb_best_effort shell sh -lc "rm -f $path_name"
  done

  for path_name in "${SHARED_STORAGE_RESIDUE_PATHS[@]}"; do
    run_adb_best_effort shell sh -lc "rm -rf $path_name"
  done

  log_ok 'Resíduos controlados do projeto limpos no dispositivo.'
}

list_residual_termux_processes() {
  adb -s "$DEVICE_ID" shell ps -A -o NAME,ARGS 2>/dev/null | grep -E 'com\.termux|termux-x11|virgl_test_server_android|openbox|xfce|proot|xeyes|aterm|dbus-run-session' || true
}

uninstall_existing_termux_apps() {
  local package_name
  local uninstall_output
  local package_path_output

  for package_name in "${REQUIRED_PACKAGES[@]}"; do
    log_step "Desinstalando $package_name, se presente."
    run_adb_best_effort shell am force-stop "$package_name"
    run_adb_best_effort shell pm clear "$package_name"
    set +e
    uninstall_output=$(adb -s "$DEVICE_ID" uninstall "$package_name" 2>&1)
    local uninstall_status=$?
    set -e

    if [ "$uninstall_status" -ne 0 ] && ! printf '%s\n' "$uninstall_output" | grep -Fq 'Unknown package'; then
      set +e
      package_path_output=$(adb -s "$DEVICE_ID" shell cmd package path "$package_name" 2>&1)
      local package_path_status=$?
      set -e

      if [ "$package_path_status" -ne 0 ] || [ -z "$package_path_output" ] || printf '%s\n' "$package_path_output" | grep -Fq 'Unable to find package'; then
        log_step "$package_name já não está instalado de forma íntegra; seguindo com a limpeza."
        continue
      fi

      fail \
        "adb -s \"$DEVICE_ID\" uninstall $package_name" \
        "$uninstall_output" \
        "A limpeza da fonte anterior do ecossistema Termux falhou." \
        "Resolver o erro de uninstall e repetir antes de tentar instalar APKs de outra origem."
    fi
  done
}

verify_residue_cleanup() {
  local packages_output
  local package_name
  local path_name
  local residue_output
  local process_output
  local matched_paths

  packages_output=$(run_adb shell pm list packages --user 0)
  for package_name in "${REQUIRED_PACKAGES[@]}"; do
    if printf '%s\n' "$packages_output" | grep -Fxq "package:${package_name}"; then
      fail \
        "verificação de remoção de $package_name" \
        "$packages_output" \
        "A limpeza antes da reinstalação deixou um dos pacotes Termux ainda instalado no user 0." \
        "Corrigir a remoção do pacote antes de reinstalar."
    fi
  done

  residue_output=""
  for path_name in "${SHARED_STORAGE_RESIDUE_PATHS[@]}"; do
    matched_paths=$(adb -s "$DEVICE_ID" shell sh -lc "for p in $path_name; do [ -e \"\$p\" ] && echo \"\$p\"; done" 2>/dev/null || true)
    if [ -n "$matched_paths" ]; then
      residue_output="${residue_output}${matched_paths}\n"
    fi
  done
  for path_name in "${TMP_RESIDUE_PATHS[@]}"; do
    matched_paths=$(adb -s "$DEVICE_ID" shell sh -lc "for p in $path_name; do [ -e \"\$p\" ] && echo \"\$p\"; done" 2>/dev/null || true)
    if [ -n "$matched_paths" ]; then
      residue_output="${residue_output}${matched_paths}\n"
    fi
  done

  if [ -n "$residue_output" ]; then
    fail \
      'verificação de resíduos em shared storage e /data/local/tmp' \
      "$residue_output" \
      'A limpeza controlada deixou resíduos acessíveis do projeto no dispositivo.' \
      'Remover os caminhos remanescentes antes de reinstalar.'
  fi

  process_output=$(list_residual_termux_processes)
  if [ -n "$process_output" ]; then
    fail \
      'verificação de processos residuais do ecossistema Termux' \
      "$process_output" \
      'A limpeza antes da reinstalação deixou processos Termux/X11/GUI vivos no dispositivo.' \
      'Encerrar esses processos antes de reinstalar.'
  fi
}

reboot_if_residual_processes_remain() {
  local process_output

  process_output="$(list_residual_termux_processes)"
  if [ -z "$process_output" ]; then
    return 0
  fi

  TOTAL_STEPS=$((TOTAL_STEPS + 1))
  log_step 'Processos residuais sobreviveram ao uninstall; reiniciando o dispositivo para concluir a limpeza.'
  termux::prepare_android_reboot_state "$DEVICE_ID"
  adb -s "$DEVICE_ID" reboot >/dev/null 2>&1 || true

  if ! termux::wait_for_device_ready "$DEVICE_ID" 180; then
    fail \
      "espera pela volta do endpoint ADB $DEVICE_ID após reboot automático" \
      'O endpoint ADB não voltou ao estado device dentro do tempo esperado.' \
      'A reinstalação limpa ficou sem canal ADB para continuar após a limpeza por reboot.' \
      'Se o fluxo estiver usando Wireless debugging, reconectar o endpoint atual e repetir a reinstalação.'
  fi

  if ! termux::wait_for_boot_completed "$DEVICE_ID" 240; then
    fail \
      "adb -s \"$DEVICE_ID\" reboot" \
      'O dispositivo não voltou com boot completo após o reboot automático da reinstalação.' \
      'A limpeza dos resíduos do ecossistema Termux não pôde ser concluída.' \
      'Aguardar o boot terminar no dispositivo e repetir a reinstalação limpa.'
  fi

  cleanup_project_residue
  log_ok 'Reboot concluído e limpeza reaplicada após os processos residuais.'
}

install_apk() {
  local apk_path="$1"
  local install_output

  log_step "Instalando $(basename "$apk_path")."

  if ! install_output=$(adb -s "$DEVICE_ID" install "${ADB_INSTALL_FLAGS[@]}" "$apk_path" 2>&1); then
    fail \
      "adb -s \"$DEVICE_ID\" install ${ADB_INSTALL_FLAGS[*]} \"$apk_path\"" \
      "$install_output" \
      "O Package Manager Android recusou a instalação do APK oficial." \
      "Revisar assinatura/origem instalada anteriormente e repetir o fluxo limpo."
  fi

  if ! printf '%s\n' "$install_output" | grep -Fq 'Success'; then
    fail \
      "adb -s \"$DEVICE_ID\" install ${ADB_INSTALL_FLAGS[*]} \"$apk_path\"" \
      "$install_output" \
      "A instalação do APK não retornou sucesso inequívoco." \
      "Revisar a saída do Package Manager e repetir após corrigir o problema."
  fi
}

grant_runtime_permission_best_effort() {
  local package_name="$1"
  local permission_name="$2"

  adb -s "$DEVICE_ID" shell pm grant "$package_name" "$permission_name" >/dev/null 2>&1 || true
}

grant_appop_best_effort() {
  local package_name="$1"
  local op_name="$2"

  adb -s "$DEVICE_ID" shell cmd appops set --user 0 "$package_name" "$op_name" allow >/dev/null 2>&1 || true
}

whitelist_battery_best_effort() {
  local package_name="$1"

  adb -s "$DEVICE_ID" shell dumpsys deviceidle whitelist +"$package_name" >/dev/null 2>&1 || true
}

apply_post_install_grants() {
  local package_name

  log_step 'Aplicando grants e app-ops pós-instalação para reduzir prompts no dispositivo.'

  for package_name in "${REQUIRED_PACKAGES[@]}"; do
    grant_runtime_permission_best_effort "$package_name" "android.permission.POST_NOTIFICATIONS"
    grant_appop_best_effort "$package_name" "POST_NOTIFICATION"
    whitelist_battery_best_effort "$package_name"
  done

  for package_name in "${SPECIAL_ACCESS_PACKAGES[@]}"; do
    grant_appop_best_effort "$package_name" "SYSTEM_ALERT_WINDOW"
    grant_appop_best_effort "$package_name" "MANAGE_EXTERNAL_STORAGE"
    grant_appop_best_effort "$package_name" "WRITE_SETTINGS"
    grant_appop_best_effort "$package_name" "GET_USAGE_STATS"
  done

  log_ok 'Permissões e app-ops pós-instalação aplicados.'
}

verify_post_install_grants() {
  local package_name
  local package_dump

  for package_name in "${REQUIRED_PACKAGES[@]}"; do
    package_dump=$(run_adb shell dumpsys package "$package_name")
    if ! printf '%s\n' "$package_dump" | grep -Fq 'android.permission.POST_NOTIFICATIONS: granted=true'; then
      fail \
        "verificação de POST_NOTIFICATIONS para $package_name" \
        "$package_dump" \
        "A reinstalação terminou sem conceder a permissão de notificação, o que aumenta a chance de prompt manual logo no primeiro uso." \
        "Revisar os grants pós-instalação antes de repetir o fluxo."
    fi
  done
}

verify_installed_packages() {
  local packages_output
  local package_name

  packages_output=$(run_adb shell pm list packages --user 0)

  for package_name in "${REQUIRED_PACKAGES[@]}"; do
    if ! printf '%s\n' "$packages_output" | grep -Fxq "package:${package_name}"; then
      fail \
        "verificação pós-instalação de $package_name" \
        "$packages_output" \
        "A reinstalação dos apps Android obrigatórios ficou incompleta." \
        "Repetir o fluxo ou revisar por que o pacote não ficou visível no user 0."
    fi
  done
}

stage_payloads() {
  log_step 'Enviando payload principal e bootstrap para /data/local/tmp.'
  if [ ! -f "$MAIN_PAYLOAD_SOURCE" ]; then
    fail \
      "test -f \"$MAIN_PAYLOAD_SOURCE\"" \
      "Payload principal ausente no host." \
      "O bootstrap fresco não terá o que executar dentro do app Termux." \
      "Garantir que Install/install_termux_stack.sh exista no repositório."
  fi

  if [ ! -f "$BOOTSTRAP_SOURCE" ]; then
    fail \
      "test -f \"$BOOTSTRAP_SOURCE\"" \
      "Bootstrap fino ausente no host." \
      "O app Termux recém-instalado não terá o entrypoint previsto para reaplicar a stack." \
      "Garantir que Install/install_termux_repo_bootstrap.sh exista no repositório."
  fi

  if [ ! -f "$TERMUX_MENU_SOURCE" ]; then
    fail \
      "test -f \"$TERMUX_MENU_SOURCE\"" \
      "Menu Termux ausente no host." \
      "A reinstalacao nao conseguira reenviar o helper visual do lado Termux." \
      "Garantir que Install/termux_workspace_menu.sh exista no repositorio."
  fi

  if [ ! -f "$AUDIT_RUNNER_SOURCE" ]; then
    fail \
      "test -f \"$AUDIT_RUNNER_SOURCE\"" \
      "Audit runner ausente no host." \
      "A reinstalação limpa não conseguirá reenviar a UI canônica de auditoria." \
      "Garantir que Audit/audit_runner.py exista no repositório."
  fi

  if [ ! -d "$AUDIT_PROFILES_SOURCE" ]; then
    fail \
      "test -d \"$AUDIT_PROFILES_SOURCE\"" \
      "Perfis do audit runner ausentes no host." \
      "A reinstalação limpa não conseguirá reenviar os perfis de auditoria para o Termux." \
      "Garantir que Audit/profiles exista no repositório."
  fi

  run_adb push "$MAIN_PAYLOAD_SOURCE" "$MAIN_PAYLOAD_TARGET" >/dev/null
  run_adb push "$BOOTSTRAP_SOURCE" "$BOOTSTRAP_TARGET" >/dev/null
  run_adb push "$TERMUX_MENU_SOURCE" "$TERMUX_MENU_TARGET" >/dev/null
  run_adb push "$AUDIT_RUNNER_SOURCE" "$AUDIT_RUNNER_TARGET" >/dev/null
  run_adb shell rm -rf "$AUDIT_PROFILES_TARGET" >/dev/null
  run_adb shell mkdir -p "$AUDIT_PROFILES_TARGET" >/dev/null
  for audit_profile in "$AUDIT_PROFILES_SOURCE"/*.json; do
    run_adb push "$audit_profile" "$AUDIT_PROFILES_TARGET/$(basename "$audit_profile")" >/dev/null
  done
  run_adb shell chmod 755 "$MAIN_PAYLOAD_TARGET" "$BOOTSTRAP_TARGET" "$TERMUX_MENU_TARGET" >/dev/null
  run_adb shell chmod 644 "$AUDIT_RUNNER_TARGET" >/dev/null
  log_ok 'Payload principal, bootstrap, menu e audit runner enviados para /data/local/tmp.'
}

print_summary() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Dry-run concluído no dispositivo %s.\n' "$DEVICE_ID"
  else
    printf 'Reinstalação oficial Android concluída no dispositivo %s.\n' "$DEVICE_ID"
  fi
  printf 'Termux APK: %s\n' "$TERMUX_APP_APK"
  printf 'Termux:API APK: %s\n' "$TERMUX_API_APK"
  printf 'Termux:X11 APK: %s\n' "$TERMUX_X11_APK"
  if [ "$DRY_RUN" -eq 0 ]; then
    printf 'Payload principal enviado para: %s\n' "$MAIN_PAYLOAD_TARGET"
    printf 'Bootstrap fino enviado para: %s\n' "$BOOTSTRAP_TARGET"
    printf 'Menu Termux enviado para: %s\n' "$TERMUX_MENU_TARGET"
    printf 'Audit runner enviado para: %s\n' "$AUDIT_RUNNER_TARGET"
    printf 'Perfis do audit runner enviados para: %s\n' "$AUDIT_PROFILES_TARGET"
    printf 'Termux:API foi aberto automaticamente durante o fluxo.\n'
    printf 'Bootstrap fino executado automaticamente no app Termux.\n'
  fi
}

ensure_termux_ready_for_bootstrap() {
  local ready_output=""
  local ready_status

  log_step 'Abrindo o app Termux e aguardando o shell ficar pronto para o bootstrap.'

  for _ in 1 2 3 4 5 6 7 8; do
    termux::start_activity_and_wait "$DEVICE_ID" 'com.termux/.app.TermuxActivity' 'com.termux/.app.TermuxActivity' 12 >/dev/null 2>&1 || true
    sleep 1

    set +e
    ready_output=$(bash "$TERMUX_SEND_COMMAND_SCRIPT" --device "$DEVICE_ID" -- 'command -v pkg >/dev/null 2>&1 && echo TERMUX_READY || echo TERMUX_NOT_READY' 2>&1)
    ready_status=$?
    set -e

    if [ "$ready_status" -eq 0 ] && printf '%s\n' "$ready_output" | grep -Fq 'TERMUX_READY'; then
      log_ok 'App Termux pronto para receber o bootstrap.'
      return 0
    fi

    sleep 2
  done

  fail \
    'bootstrap de readiness do shell real do app Termux' \
    "$ready_output" \
    'O host nao conseguiu estabilizar o shell real do app Termux apos a reinstalacao.' \
    'Abrir o app Termux manualmente, confirmar que ele inicia corretamente e repetir a reinstalacao.'
}

run_termux_repo_bootstrap() {
  local bootstrap_log
  local bootstrap_output
  local bootstrap_status

  log_step 'Executando o bootstrap fino automaticamente dentro do app Termux.'
  bootstrap_log="$(mktemp)"

  termux::audit_note 'HOST' 'Termux voltou após a reinstalação; preparando o watcher do audit para reaparecer assim que o runner estiver disponível.'
  termux::audit_reattach_device "$DEVICE_ID"

  (
    for _ in $(seq 1 180); do
      if adb -s "$DEVICE_ID" shell "run-as com.termux sh -lc 'export HOME=/data/data/com.termux/files/home; export PREFIX=/data/data/com.termux/files/usr; export PATH=/data/data/com.termux/files/home/bin:/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin; command -v termux-audit-watch >/dev/null 2>&1'" >/dev/null 2>&1; then
        termux::audit_note 'HOST' 'Audit runner reinstalado no Termux; relançando o watcher visual no app.'
        termux::audit_reattach_device "$DEVICE_ID"
        termux::audit_launch_device_watch "$DEVICE_ID"
        exit 0
      fi
      sleep 1
    done
    exit 0
  ) &
  BOOTSTRAP_AUDIT_HELPER_PID=$!

  set +e
  bash "$TERMUX_SEND_COMMAND_SCRIPT" --device "$DEVICE_ID" -- "bash $BOOTSTRAP_TARGET" 2>&1 | while IFS= read -r bootstrap_line || [ -n "$bootstrap_line" ]; do
    printf '%s\n' "$bootstrap_line"
    printf '%s\n' "$bootstrap_line" >> "$bootstrap_log"
    case "$bootstrap_line" in
      \[*\]*|Mirror\ default*|chosen_mirrors=*|Repo\ *|Bootstrap\ do\ repositório*|Payload\ principal:*|Helpers\ instalados:*|-\ /*|DISPLAY=*|XDG_RUNTIME_DIR=*|termux-x11=*|virgl=*|desktop=*|wm=*|virgl-mode=*|openbox-profile=*|driver-profile=*|dbus=*|current-profile=*|default-resolution=*|default-profile=*|Reinicie\ Termux*|Estado\ atual:*)
        termux::audit_note 'TERMUX' "$bootstrap_line"
        ;;
    esac
  done
  bootstrap_status=${PIPESTATUS[0]}
  set -e

  if [ -n "$BOOTSTRAP_AUDIT_HELPER_PID" ]; then
    wait "$BOOTSTRAP_AUDIT_HELPER_PID" >/dev/null 2>&1 || true
    BOOTSTRAP_AUDIT_HELPER_PID=""
  fi

  if [ "$bootstrap_status" -ne 0 ]; then
    bootstrap_output="$(tail -n 120 "$bootstrap_log" || true)"
    rm -f "$bootstrap_log"
    fail \
      "bash \"$TERMUX_SEND_COMMAND_SCRIPT\" --device \"$DEVICE_ID\" -- \"bash $BOOTSTRAP_TARGET\"" \
      "$bootstrap_output" \
      'A reinstalacao dos APKs terminou, mas o bootstrap fino automatico falhou dentro do app Termux.' \
      'Corrigir o erro do bootstrap e repetir a reinstalacao limpa.'
  fi

  rm -f "$bootstrap_log"
  termux::audit_reattach_device "$DEVICE_ID"
  termux::audit_launch_device_watch "$DEVICE_ID"
  log_ok 'Bootstrap fino executado com sucesso dentro do app Termux.'
}

log_step 'Validando dependências do host.'
ensure_host_dependency adb
ensure_host_dependency curl
ensure_host_dependency python3
ensure_termux_send_command_helper
log_ok 'Dependências do host e helper de bootstrap validados.'

log_step 'Resolvendo o dispositivo ADB alvo.'
resolve_device
log_ok "Dispositivo ADB selecionado: $DEVICE_ID"

log_step 'Validando ABI do dispositivo.'
verify_device_abi
log_ok 'ABI ARM64 validada para a reinstalação oficial.'

mkdir -p "$DOWNLOAD_DIR"

TERMUX_APP_JSON="${DOWNLOAD_DIR}/termux-app-latest.json"
TERMUX_API_JSON="${DOWNLOAD_DIR}/termux-api-latest.json"
TERMUX_X11_JSON="${DOWNLOAD_DIR}/termux-x11-nightly.json"

log_step 'Consultando releases oficiais do ecossistema Termux.'
fetch_release_json "$TERMUX_APP_API" "$TERMUX_APP_JSON"
fetch_release_json "$TERMUX_API_API" "$TERMUX_API_JSON"
fetch_release_json "$TERMUX_X11_API" "$TERMUX_X11_JSON"
log_ok 'Metadados oficiais de release obtidos com sucesso.'

log_step 'Selecionando os assets oficiais compatíveis com ARM64.'
TERMUX_APP_URL=$(resolve_asset_url "$TERMUX_APP_JSON" "termux-app" 'termux-app_v.+\+github-debug_arm64-v8a\.apk')
TERMUX_API_URL=$(resolve_asset_url "$TERMUX_API_JSON" "termux-api" 'termux-api-app_v.+\+github\.debug\.apk')
TERMUX_X11_URL=$(resolve_asset_url "$TERMUX_X11_JSON" "termux-x11" 'app-arm64-v8a-debug\.apk')

TERMUX_APP_APK="${DOWNLOAD_DIR}/$(basename "$TERMUX_APP_URL")"
TERMUX_API_APK="${DOWNLOAD_DIR}/$(basename "$TERMUX_API_URL")"
TERMUX_X11_APK="${DOWNLOAD_DIR}/$(basename "$TERMUX_X11_URL")"
log_ok 'Assets oficiais ARM64 resolvidos para os três APKs.'

log_step 'Baixando os APKs oficiais no host.'
download_asset "$TERMUX_APP_URL" "$TERMUX_APP_APK"
download_asset "$TERMUX_API_URL" "$TERMUX_API_APK"
download_asset "$TERMUX_X11_URL" "$TERMUX_X11_APK"
log_ok 'APKs oficiais baixados no host.'

if [ "$DRY_RUN" -eq 1 ]; then
  log_step 'Dry-run ativo: pulando uninstall/install e staging no dispositivo.'
  log_ok 'Dry-run encerrado sem alterações no dispositivo.'
  print_summary
  exit 0
fi

cleanup_project_residue
uninstall_existing_termux_apps
reboot_if_residual_processes_remain
verify_residue_cleanup

install_apk "$TERMUX_APP_APK"
install_apk "$TERMUX_API_APK"
install_apk "$TERMUX_X11_APK"

verify_installed_packages
apply_post_install_grants
verify_post_install_grants
stage_payloads

log_step 'Abrindo Termux:API e seguindo automaticamente para o bootstrap no app Termux.'
if ! termux::ensure_termux_api_running "$DEVICE_ID" 12; then
  fail \
    'abertura obrigatória do app Termux:API após reinstalação' \
    "$(adb -s "$DEVICE_ID" shell ps -A -o NAME,ARGS 2>/dev/null | grep -F 'com.termux.api' || true)" \
    'A reinstalação terminou sem conseguir abrir e confirmar o app Termux:API, o que viola o protocolo obrigatório do projeto.' \
    'Abrir Termux:API manualmente, configurar o app e repetir a etapa se necessário.'
fi
log_ok 'Termux:API aberto e confirmado após a reinstalação.'

ensure_termux_ready_for_bootstrap
run_termux_repo_bootstrap

print_summary
