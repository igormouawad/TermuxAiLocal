#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

MODE="apply"

fail() {
  termux::fail "$@"
}

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A configuração de phantom processes foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

read_android_release() {
  run_adb shell getprop ro.build.version.release | tr -d '\r'
}

read_android_sdk() {
  run_adb shell getprop ro.build.version.sdk | tr -d '\r'
}

read_settings_monitor() {
  run_adb shell settings get global settings_enable_monitor_phantom_procs | tr -d '\r'
}

read_device_config_limit() {
  run_adb shell /system/bin/device_config get activity_manager max_phantom_processes | tr -d '\r'
}

read_activity_manager_limit() {
  run_adb shell dumpsys activity settings | grep -i 'max_phantom_processes=' | tail -1 | tr -d '\r'
}

print_status() {
  local android_release android_sdk monitor_value config_limit activity_limit

  android_release="$(read_android_release)"
  android_sdk="$(read_android_sdk)"
  monitor_value="$(read_settings_monitor)"
  config_limit="$(read_device_config_limit)"
  activity_limit="$(read_activity_manager_limit || true)"

  printf 'Dispositivo: %s\n' "$DEVICE_ID"
  printf 'Android: %s (SDK %s)\n' "$android_release" "$android_sdk"
  printf 'settings_enable_monitor_phantom_procs=%s\n' "${monitor_value:-<vazio>}"
  printf 'device_config activity_manager/max_phantom_processes=%s\n' "${config_limit:-<vazio>}"
  if [ -n "${activity_limit:-}" ]; then
    printf 'ActivityManager: %s\n' "$activity_limit"
  fi
}

apply_recommended_override() {
  run_adb shell /system/bin/device_config set_sync_disabled_for_tests persistent >/dev/null
  run_adb shell /system/bin/device_config put activity_manager max_phantom_processes 2147483647 >/dev/null
  run_adb shell settings put global settings_enable_monitor_phantom_procs false >/dev/null
}

validate_override() {
  local monitor_value config_limit activity_limit

  monitor_value="$(read_settings_monitor)"
  config_limit="$(read_device_config_limit)"
  activity_limit="$(read_activity_manager_limit || true)"

  if [ "$monitor_value" != 'false' ]; then
    fail \
      'settings get global settings_enable_monitor_phantom_procs' \
      "Valor inesperado após aplicação: ${monitor_value}" \
      'O monitor global de phantom processes não ficou desativado.' \
      'Reaplicar o ajuste, revisar permissões ADB e repetir a validação.'
  fi

  if [ "$config_limit" != '2147483647' ]; then
    fail \
      '/system/bin/device_config get activity_manager max_phantom_processes' \
      "Valor inesperado após aplicação: ${config_limit}" \
      'O limite de phantom processes não ficou elevado no device_config.' \
      'Reaplicar o ajuste, revisar permissões ADB e repetir a validação.'
  fi

  if ! printf '%s\n' "$activity_limit" | grep -Fq 'max_phantom_processes=2147483647'; then
    fail \
      'dumpsys activity settings' \
      "ActivityManager não refletiu o valor esperado: ${activity_limit}" \
      'O serviço de atividade não está expondo o override aplicado.' \
      'Reaplicar o ajuste ou reiniciar o dispositivo antes de continuar.'
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --status)
      MODE="status"
      shift
      ;;
    --apply)
      MODE="apply"
      shift
      ;;
    --help|-h)
      printf 'Uso: %s [--status|--apply]\n' "$0"
      printf '  --status  apenas lê o estado atual do monitor/limite de phantom processes.\n'
      printf '  --apply   aplica o override recomendado e valida o resultado.\n'
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'O helper não sabe qual operação precisa executar.' \
        'Usar --status, --apply ou --help.'
      ;;
  esac
done

termux::require_host_command \
  adb \
  'Não é possível configurar o dispositivo Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID="$(termux::resolve_single_device)"

if [ "$MODE" = 'status' ]; then
  print_status
  exit 0
fi

apply_recommended_override
validate_override
print_status
