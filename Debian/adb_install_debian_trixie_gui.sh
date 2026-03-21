#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/termux_common.sh
source "$(cd -- "${SCRIPT_DIR}/.." && pwd)/lib/termux_common.sh"

PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FORWARDED_ARGS=()
DEVICE_ID=""
PROOT_USER=""
PROOT_SUDO_MODE=""
PROOT_USER_PASSWORD_HASH=""
USER_CONFIG_LOCAL=""
USER_CONFIG_STAGE=""
USER_CONFIG_REMOTE=""
TOTAL_STEPS=4
CURRENT_STEP=0
AUDIT_OWNER=0

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

cleanup() {
  local exit_code=$?

  if [ -n "${USER_CONFIG_LOCAL:-}" ] && [ -f "$USER_CONFIG_LOCAL" ]; then
    rm -f "$USER_CONFIG_LOCAL"
  fi

  if [ -n "${USER_CONFIG_STAGE:-}" ] && [ -n "${DEVICE_ID:-}" ]; then
    adb -s "$DEVICE_ID" shell rm -f "$USER_CONFIG_STAGE" >/dev/null 2>&1 || true
  fi

  if [ -n "${USER_CONFIG_REMOTE:-}" ] && [ -n "${DEVICE_ID:-}" ]; then
    adb -s "$DEVICE_ID" shell "run-as com.termux sh -lc $(printf '%q' "rm -f $USER_CONFIG_REMOTE")" >/dev/null 2>&1 || true
  fi

  if [ "$AUDIT_OWNER" -eq 1 ]; then
    termux::audit_session_finish "$exit_code"
  fi
}

trap cleanup EXIT

run_adb() {
  termux::adb_run \
    "$DEVICE_ID" \
    'A instalação Debian GUI foi interrompida.' \
    'Corrigir a conectividade ADB ou o erro retornado e executar novamente.' \
    "$@"
}

validate_proot_user() {
  local candidate="$1"

  if ! printf '%s' "$candidate" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
    fail \
      'validação do nome do usuário Debian' \
      "Nome inválido: ${candidate}" \
      'O usuário Debian não pode ser criado com um identificador inseguro ou incompatível.' \
      'Usar apenas letras minúsculas, números, _ ou -, começando por letra minúscula ou _.'
  fi
}

validate_sudo_mode() {
  case "${1:-}" in
    password|nopasswd)
      return 0
      ;;
    *)
      fail \
        'validação do modo sudo' \
        "Modo inválido: ${1:-<vazio>}" \
        'A política de sudo do usuário Debian ficou indefinida.' \
        'Usar password ou nopasswd.'
      ;;
  esac
}

hash_password_from_stdin() {
  if ! command -v openssl >/dev/null 2>&1; then
    fail \
      'command -v openssl' \
      'openssl não está disponível no host.' \
      'A senha do usuário Debian não pode ser convertida para um hash seguro antes do envio.' \
      'Instalar openssl no host e repetir a operação.'
  fi

  openssl passwd -6 -stdin
}

resolve_noninteractive_user_setup() {
  if [ -z "$PROOT_USER_PASSWORD_HASH" ] && [ -n "${TERMUXAI_DEBIAN_PASSWORD_HASH:-}" ]; then
    PROOT_USER_PASSWORD_HASH="$TERMUXAI_DEBIAN_PASSWORD_HASH"
  fi

  if [ -z "$PROOT_USER_PASSWORD_HASH" ] && [ -n "${TERMUXAI_DEBIAN_PASSWORD:-}" ]; then
    PROOT_USER_PASSWORD_HASH="$(printf '%s' "$TERMUXAI_DEBIAN_PASSWORD" | hash_password_from_stdin)"
  fi

  if [ -n "$PROOT_USER" ] && [ -n "$PROOT_SUDO_MODE" ] && [ -n "$PROOT_USER_PASSWORD_HASH" ]; then
    return 0
  fi

  return 1
}

collect_user_setup_interactively() {
  local username="$PROOT_USER"
  local password_one=""
  local password_two=""
  local sudo_answer=""

  if resolve_noninteractive_user_setup; then
    return 0
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    fail \
      'coleta interativa da configuração Debian' \
      'O wrapper host-side precisa perguntar nome, senha e política de sudo, mas a shell atual não é interativa e nenhuma senha foi fornecida por ambiente.' \
      'O usuário Debian não pode ser definido com segurança neste contexto.' \
      'Executar o wrapper em um terminal interativo ou definir TERMUXAI_DEBIAN_PASSWORD_HASH.'
  fi

  while :; do
    if [ -z "$username" ]; then
      printf 'Nome do usuário Debian: '
      IFS= read -r username
    fi

    if [ -z "$username" ]; then
      printf 'O nome do usuário não pode ficar vazio.\n' >&2
      continue
    fi

    if printf '%s' "$username" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
      break
    fi

    printf 'Nome inválido. Use apenas letras minúsculas, números, _ ou -, começando por letra minúscula ou _.\n' >&2
    username=""
  done

  while :; do
    printf 'Senha do usuário Debian: '
    IFS= read -r -s password_one
    printf '\n'
    printf 'Confirme a senha: '
    IFS= read -r -s password_two
    printf '\n'

    if [ -z "$password_one" ]; then
      printf 'A senha não pode ficar vazia.\n' >&2
      continue
    fi

    if [ "$password_one" != "$password_two" ]; then
      printf 'As senhas não conferem. Tente novamente.\n' >&2
      continue
    fi

    break
  done

  while :; do
    if [ -n "$PROOT_SUDO_MODE" ]; then
      validate_sudo_mode "$PROOT_SUDO_MODE"
      break
    fi

    printf 'Sudo deve exigir senha? [S/n]: '
    IFS= read -r sudo_answer
    case "${sudo_answer:-S}" in
      S|s|'')
        PROOT_SUDO_MODE='password'
        ;;
      N|n)
        PROOT_SUDO_MODE='nopasswd'
        ;;
      *)
        printf 'Resposta inválida. Digite S para sudo com senha ou N para sudo sem senha.\n' >&2
        continue
        ;;
    esac
    break
  done

  PROOT_USER="$username"
  PROOT_USER_PASSWORD_HASH="$(printf '%s' "$password_one" | hash_password_from_stdin)"
  unset password_one password_two sudo_answer username
}

write_user_config_local() {
  USER_CONFIG_LOCAL="$(mktemp)"
  chmod 600 "$USER_CONFIG_LOCAL"
  printf 'PROOT_USER=%q\n' "$PROOT_USER" > "$USER_CONFIG_LOCAL"
  printf 'PROOT_SUDO_MODE=%q\n' "$PROOT_SUDO_MODE" >> "$USER_CONFIG_LOCAL"
  printf 'PROOT_USER_PASSWORD_HASH=%q\n' "$PROOT_USER_PASSWORD_HASH" >> "$USER_CONFIG_LOCAL"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reset-distro)
      FORWARDED_ARGS+=("$1")
      shift
      ;;
    --user)
      if [ "$#" -lt 2 ]; then
        printf 'Uso: %s [--alias nome] [--reset-distro] [--user nome] [--sudo-mode password|nopasswd]\n' "$0" >&2
        exit 1
      fi
      PROOT_USER="$2"
      shift 2
      ;;
    --sudo-mode)
      if [ "$#" -lt 2 ]; then
        printf 'Uso: %s [--alias nome] [--reset-distro] [--user nome] [--sudo-mode password|nopasswd]\n' "$0" >&2
        exit 1
      fi
      PROOT_SUDO_MODE="$2"
      shift 2
      ;;
    --alias)
      if [ "$#" -lt 2 ]; then
        printf 'Uso: %s [--alias nome] [--reset-distro] [--user nome] [--sudo-mode password|nopasswd]\n' "$0" >&2
        exit 1
      fi
      FORWARDED_ARGS+=("$1" "$2")
      shift 2
      ;;
    --help|-h)
      printf 'Uso: %s [--alias nome] [--reset-distro] [--user nome] [--sudo-mode password|nopasswd]\n' "$0"
      printf '  Executa de forma síncrona o payload /data/local/tmp/install_debian_trixie_gui.sh no shell real do app Termux.\n'
      printf '  O wrapper pergunta nome do usuário, senha e política de sudo antes de iniciar a configuração Debian.\n'
      printf '  Para automação não interativa, exporte TERMUXAI_DEBIAN_PASSWORD_HASH ou TERMUXAI_DEBIAN_PASSWORD.\n'
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'A instalação Debian GUI não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --alias, --reset-distro, --user, --sudo-mode ou --help.'
      ;;
  esac
done

termux::require_host_command \
  adb \
  'Não é possível orquestrar o dispositivo Android a partir do host.' \
  'Instalar Android Platform Tools no host e tentar novamente.'

DEVICE_ID="$(termux::resolve_target_device)"
termux::audit_session_begin 'Instalação síncrona do Debian GUI' "$0" "$DEVICE_ID"
AUDIT_OWNER="${TERMUXAI_AUDIT_SESSION_OWNER:-0}"
step_begin 'Coletando usuário Debian, senha e política de sudo no host'
collect_user_setup_interactively
validate_proot_user "$PROOT_USER"
validate_sudo_mode "$PROOT_SUDO_MODE"
write_user_config_local
step_ok "Configuração Debian coletada para o usuário ${PROOT_USER}."

step_begin 'Reconstruindo o desktop mode do workspace antes da instalação Debian'
if ! termux::ensure_termux_workspace_ready "$DEVICE_ID" termux; then
  fail \
    'preparação validada do ecossistema Termux' \
    "$(termux::current_focus "$DEVICE_ID")" \
    'O host não conseguiu garantir o desktop mode obrigatório antes da instalação Debian.' \
    'Reconstruir o desktop mode aprovado e repetir a operação.'
fi
step_ok 'Desktop mode pronto para o payload Debian.'
termux::audit_launch_device_watch "$DEVICE_ID"

step_begin 'Enviando a configuração segura do usuário para o dispositivo'
USER_CONFIG_STAGE="/data/local/tmp/debian-user-setup-stage-${DEVICE_ID}-$$.env"
USER_CONFIG_REMOTE="/data/data/com.termux/files/usr/tmp/debian-user-setup-${DEVICE_ID}-$$.env"
run_adb push "$USER_CONFIG_LOCAL" "$USER_CONFIG_STAGE" >/dev/null
run_adb shell chmod 644 "$USER_CONFIG_STAGE" >/dev/null
run_adb shell "run-as com.termux sh -lc $(printf '%q' "install -m 600 $USER_CONFIG_STAGE $USER_CONFIG_REMOTE")" >/dev/null
step_ok 'Arquivo temporário de configuração Debian copiado para o tmp privado do app Termux.'

install_command='bash /data/local/tmp/install_debian_trixie_gui.sh'
if [ "${#FORWARDED_ARGS[@]}" -gt 0 ]; then
  for arg in "${FORWARDED_ARGS[@]}"; do
    install_command="$(termux::append_shell_word "$install_command" "$arg")"
  done
fi
install_command="$(termux::append_shell_word "$install_command" --user)"
install_command="$(termux::append_shell_word "$install_command" "$PROOT_USER")"
install_command="$(termux::append_shell_word "$install_command" --sudo-mode)"
install_command="$(termux::append_shell_word "$install_command" "$PROOT_SUDO_MODE")"
install_command="$(termux::append_shell_word "$install_command" --user-config)"
install_command="$(termux::append_shell_word "$install_command" "$USER_CONFIG_REMOTE")"

step_begin 'Executando o payload Debian no shell real do Termux e validando o helper final'
bash "${PROJECT_ROOT}/ADB/adb_termux_send_command.sh" \
  --device "$DEVICE_ID" \
  --quiet-output \
  --expect 'Debian Trixie preparado para apps GUI no Termux.' \
  -- "$install_command"

helper_check_output="$(
  bash "${PROJECT_ROOT}/ADB/adb_termux_send_command.sh" \
    --device "$DEVICE_ID" \
  --expect '/data/data/com.termux/files/home/bin/run-gui-debian' \
  -- 'command -v run-gui-debian'
)"
step_ok 'Payload Debian concluído e helper run-gui-debian validado.'

printf 'Instalação Debian GUI concluída com sucesso no dispositivo %s.\n' "$DEVICE_ID"
printf 'Helper Debian GUI: %s\n' "$(printf '%s\n' "$helper_check_output" | head -n 1)"
