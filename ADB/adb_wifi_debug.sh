#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/termux_common.sh
source "${WORKSPACE_ROOT}/lib/termux_common.sh"

ACTION="status"
USB_DEVICE_ID=""
TCPIP_PORT="5555"
AUDIT_OWNER=0

finish_audit() {
  local exit_code=$?

  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap finish_audit EXIT

usage() {
  cat <<EOF
Uso:
  bash ${WORKSPACE_ROOT}/ADB/adb_wifi_debug.sh status [--device SERIAL]
  bash ${WORKSPACE_ROOT}/ADB/adb_wifi_debug.sh connect [--device SERIAL]
  bash ${WORKSPACE_ROOT}/ADB/adb_wifi_debug.sh disable [--device SERIAL]
  bash ${WORKSPACE_ROOT}/ADB/adb_wifi_debug.sh tcpip [--port 5555] [--device SERIAL]

Regras:
  - este helper usa USB como transporte de controle
  - ele não escolhe um alvo ADB por rede como device principal
  - o fluxo connect liga adb_wifi_enabled, descobre a porta de connect e executa adb connect
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    status|connect|disable|tcpip)
      ACTION="$1"
      shift
      ;;
    --device)
      [ "$#" -ge 2 ] || termux::fail \
        "$0 --device" \
        'Faltou informar o serial USB.' \
        'O helper não consegue selecionar o device correto.' \
        'Repetir com --device SERIAL.'
      USB_DEVICE_ID="$2"
      shift 2
      ;;
    --port)
      [ "$#" -ge 2 ] || termux::fail \
        "$0 --port" \
        'Faltou informar a porta TCP.' \
        'O helper não consegue usar o modo adb tcpip.' \
        'Repetir com --port 5555 ou outra porta válida.'
      TCPIP_PORT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      termux::fail \
        "$0 $*" \
        "Argumento não suportado: $1" \
        'O helper não consegue continuar com parâmetros inválidos.' \
        'Usar status, connect, disable, tcpip, --device ou --port.'
      ;;
  esac
done

resolve_usb_device() {
  local device_list
  local usb_count
  local usb_id

  if [ -n "$USB_DEVICE_ID" ]; then
    case "$USB_DEVICE_ID" in
      *:*)
        termux::fail \
          "$0 --device $USB_DEVICE_ID" \
          'Foi informado um serial de rede; este helper exige USB como transporte de controle.' \
          'A ativação/configuração por USB não pode continuar usando um endpoint de rede.' \
          'Repetir com o serial USB real ou sem --device.'
        ;;
    esac
    printf '%s\n' "$USB_DEVICE_ID"
    return 0
  fi

  device_list="$(termux::adb_device_list)"
  usb_count=$(
    printf '%s\n' "$device_list" \
      | awk 'NR > 1 && $2 == "device" && ($0 ~ / usb:/ || $1 !~ /:/) { count++ } END { print count + 0 }'
  )
  usb_id=$(
    printf '%s\n' "$device_list" \
      | awk 'NR > 1 && $2 == "device" && ($0 ~ / usb:/ || $1 !~ /:/) { print $1; exit }'
  )

  if [ "$usb_count" -eq 1 ]; then
    printf '%s\n' "$usb_id"
    return 0
  fi

  if [ "$usb_count" -gt 1 ]; then
    termux::fail \
      'adb devices -l' \
      "$device_list" \
      'Há múltiplos alvos USB em estado device; este helper não pode escolher sozinho.' \
      'Repetir com --device SERIAL_USB.'
  fi

  termux::fail \
    'adb devices -l' \
    "$device_list" \
    'Nenhum alvo USB em estado device foi encontrado.' \
    'Conectar o tablet por USB e repetir.'
}

list_network_devices() {
  adb devices -l 2>/dev/null \
    | awk 'NR > 1 && $2 == "device" && $1 ~ /:/ { print $1 }'
}

resolve_wifi_ip() {
  local usb_device="$1"
  local route_output
  local ip_addr

  route_output="$(adb -s "$usb_device" shell ip route get 1.1.1.1 2>/dev/null | tr -d '\r')"
  ip_addr="$(
    printf '%s\n' "$route_output" \
      | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }'
  )"

  if [ -n "$ip_addr" ]; then
    printf '%s\n' "$ip_addr"
    return 0
  fi

  route_output="$(adb -s "$usb_device" shell ip -f inet addr show wlan0 2>/dev/null | tr -d '\r')"
  ip_addr="$(
    printf '%s\n' "$route_output" \
      | awk '/inet / { split($2, parts, "/"); print parts[1]; exit }'
  )"

  if [ -n "$ip_addr" ]; then
    printf '%s\n' "$ip_addr"
    return 0
  fi

  termux::fail \
    "adb -s \"$usb_device\" shell ip route get 1.1.1.1" \
    "$route_output" \
    'Não foi possível determinar o IP Wi‑Fi atual do tablet.' \
    'Confirmar que o Wi‑Fi do Android está conectado antes de repetir.'
}

get_global_setting() {
  local usb_device="$1"
  local setting_name="$2"

  adb -s "$usb_device" shell settings get global "$setting_name" 2>/dev/null | tr -d '\r'
}

set_global_setting() {
  local usb_device="$1"
  local setting_name="$2"
  local setting_value="$3"

  adb -s "$usb_device" shell settings put global "$setting_name" "$setting_value" >/dev/null
}

show_status() {
  local usb_device
  local wifi_ip
  local network_devices

  usb_device="$(resolve_usb_device)"
  wifi_ip="$(resolve_wifi_ip "$usb_device")"
  network_devices="$(list_network_devices || true)"

  printf 'USB_DEVICE=%s\n' "$usb_device"
  printf 'WIFI_IP=%s\n' "$wifi_ip"
  printf 'ADB_ENABLED=%s\n' "$(get_global_setting "$usb_device" adb_enabled)"
  printf 'ADB_WIFI_ENABLED=%s\n' "$(get_global_setting "$usb_device" adb_wifi_enabled)"
  printf 'ADB_ALLOWED_CONNECTION_TIME=%s\n' "$(get_global_setting "$usb_device" adb_allowed_connection_time)"
  printf 'NETWORK_DEVICES=%s\n' "${network_devices:-none}"
  printf 'MDNS_SERVICES_START\n'
  timeout 5 adb mdns services || true
  printf 'MDNS_SERVICES_END\n'
}

enable_and_connect() {
  local usb_device
  local wifi_ip
  local candidate
  local connected_endpoint=""
  local total_steps=5

  usb_device="$(resolve_usb_device)"

  termux::progress_step 1 "$total_steps" HOST "Resolver o transporte USB de controle"
  termux::progress_result OK 1 "$total_steps" HOST "USB de controle: ${usb_device}"

  termux::progress_step 2 "$total_steps" HOST "Ler o IP Wi‑Fi atual do tablet"
  wifi_ip="$(resolve_wifi_ip "$usb_device")"
  termux::progress_result OK 2 "$total_steps" HOST "IP Wi‑Fi atual: ${wifi_ip}"

  termux::progress_step 3 "$total_steps" HOST "Ativar adb_wifi_enabled pelo USB"
  set_global_setting "$usb_device" adb_wifi_enabled 1
  sleep 2
  if [ "$(get_global_setting "$usb_device" adb_wifi_enabled)" != "1" ]; then
    termux::progress_result FAIL 3 "$total_steps" HOST "adb_wifi_enabled não permaneceu em 1"
    termux::fail \
      "adb -s \"$usb_device\" shell settings put global adb_wifi_enabled 1" \
      'O Android não manteve o flag adb_wifi_enabled em 1.' \
      'O ADB por Wi‑Fi não pode ser ativado por esse caminho.' \
      'Verificar a UI de Wireless debugging ou usar adb tcpip como alternativa.'
  fi
  termux::progress_result OK 3 "$total_steps" HOST "adb_wifi_enabled=1 confirmado"

  termux::progress_step 4 "$total_steps" HOST "Descobrir e testar endpoints de connect"
  termux::adb_disconnect_offline_network_targets
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    termux::progress_note HOST "Tentando ${candidate}"
    if termux::adb_try_connect_endpoint "$candidate"; then
      connected_endpoint="$candidate"
      break
    fi
  done < <(termux::adb_scan_candidate_endpoints_for_ip "$wifi_ip")

  if [ -z "$connected_endpoint" ]; then
    termux::progress_result FAIL 4 "$total_steps" HOST "Nenhum endpoint Wi‑Fi aceitou adb connect"
    termux::fail \
      "scan/connect em ${wifi_ip}" \
      'Nenhuma porta descoberta respondeu como endpoint válido de adb connect.' \
      'O ADB por Wi‑Fi não ficou operacional neste boot.' \
      'Repetir a tentativa ou usar adb tcpip como alternativa.'
  fi
  termux::adb_disconnect_offline_network_targets
  termux::progress_result OK 4 "$total_steps" HOST "Endpoint Wi‑Fi conectado: ${connected_endpoint}"

  termux::progress_step 5 "$total_steps" HOST "Confirmar o estado final dos transportes ADB"
  printf 'WIFI_ENDPOINT=%s\n' "$connected_endpoint"
  adb devices -l
  termux::progress_result OK 5 "$total_steps" HOST "ADB por Wi‑Fi disponível sem desligar o USB"
}

disable_wifi_debugging() {
  local usb_device
  local total_steps=3
  local flag_value

  usb_device="$(resolve_usb_device)"

  termux::progress_step 1 "$total_steps" HOST "Resolver o transporte USB de controle"
  termux::progress_result OK 1 "$total_steps" HOST "USB de controle: ${usb_device}"

  termux::progress_step 2 "$total_steps" HOST "Desconectar alvos ADB por rede"
  while IFS= read -r endpoint; do
    [ -n "$endpoint" ] || continue
    adb disconnect "$endpoint" >/dev/null 2>&1 || true
  done < <(adb devices -l 2>/dev/null | awk 'NR > 1 && $1 ~ /:/ { print $1 }')
  termux::progress_result OK 2 "$total_steps" HOST "Transportes de rede desconectados"

  termux::progress_step 3 "$total_steps" HOST "Desativar adb_wifi_enabled"
  set_global_setting "$usb_device" adb_wifi_enabled 0
  sleep 2
  termux::adb_disconnect_offline_network_targets
  flag_value="$(get_global_setting "$usb_device" adb_wifi_enabled)"
  if [ "$flag_value" != "0" ]; then
    termux::progress_result FAIL 3 "$total_steps" HOST "adb_wifi_enabled permaneceu em ${flag_value}"
    termux::fail \
      "adb -s \"$usb_device\" shell settings put global adb_wifi_enabled 0" \
      "adb_wifi_enabled permaneceu em ${flag_value}." \
      'O Android não confirmou o desligamento do ADB por Wi‑Fi.' \
      'Verificar o estado real em settings/dumpsys antes de repetir.'
  fi
  printf 'ADB_WIFI_ENABLED=%s\n' "$flag_value"
  adb devices -l
  termux::progress_result OK 3 "$total_steps" HOST "ADB por Wi‑Fi desativado no Android"
}

enable_tcpip_mode() {
  local usb_device
  local wifi_ip
  local total_steps=5
  local tcpip_output

  usb_device="$(resolve_usb_device)"

  termux::progress_step 1 "$total_steps" HOST "Resolver o transporte USB de controle"
  termux::progress_result OK 1 "$total_steps" HOST "USB de controle: ${usb_device}"

  termux::progress_step 2 "$total_steps" HOST "Ler o IP Wi‑Fi atual do tablet"
  wifi_ip="$(resolve_wifi_ip "$usb_device")"
  termux::progress_result OK 2 "$total_steps" HOST "IP Wi‑Fi atual: ${wifi_ip}"

  termux::progress_step 3 "$total_steps" HOST "Limpar alvos ADB por rede já existentes"
  while IFS= read -r endpoint; do
    [ -n "$endpoint" ] || continue
    adb disconnect "$endpoint" >/dev/null 2>&1 || true
  done < <(adb devices -l 2>/dev/null | awk 'NR > 1 && $1 ~ /:/ { print $1 }')
  termux::progress_result OK 3 "$total_steps" HOST "Estado de rede anterior limpo"

  termux::progress_step 4 "$total_steps" HOST "Reiniciar o adb em modo tcpip"
  tcpip_output="$(adb -s "$usb_device" tcpip "$TCPIP_PORT" 2>&1)" || termux::fail \
    "adb -s \"$usb_device\" tcpip $TCPIP_PORT" \
    "$tcpip_output" \
    'O ADB não entrou em modo tcpip.' \
    'Verificar o transporte USB e tentar novamente.'
  sleep 2
  termux::progress_result OK 4 "$total_steps" HOST "$(printf '%s' "$tcpip_output" | tr -d '\r')"

  termux::progress_step 5 "$total_steps" HOST "Conectar ao endpoint tcpip"
  adb connect "${wifi_ip}:${TCPIP_PORT}" >/dev/null
  termux::adb_disconnect_offline_network_targets
  printf 'TCPIP_ENDPOINT=%s:%s\n' "$wifi_ip" "$TCPIP_PORT"
  adb devices -l
  termux::progress_result OK 5 "$total_steps" HOST "ADB tcpip conectado"
}

main() {
  USB_DEVICE_ID="$(resolve_usb_device)"
  termux::audit_session_begin 'Controle do ADB por Wi‑Fi via USB' "$0" "$USB_DEVICE_ID"
  AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"

  case "$ACTION" in
    status)
      ;;
    *)
      termux::prechange_audit_gate 'Controle do ADB por Wi‑Fi via USB' 'wifi_control_usb' "$USB_DEVICE_ID"
      ;;
  esac

  case "$ACTION" in
    status)
      show_status
      ;;
    connect)
      enable_and_connect
      ;;
    disable)
      disable_wifi_debugging
      ;;
    tcpip)
      enable_tcpip_mode
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
