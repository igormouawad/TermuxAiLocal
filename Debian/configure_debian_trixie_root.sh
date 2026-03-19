#!/usr/bin/env bash

set -euo pipefail

PROOT_USER="igor"
SCRIPT_LOG="/tmp/configure-debian-root-$(date +%Y%m%d-%H%M%S).log"
TOTAL_STEPS=9
CURRENT_STEP=0
LAST_STEP_LOG=""
APT_NONINTERACTIVE_OPTS=(
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confnew
)

progress_bar() {
  local current="$1"
  local total="$2"
  local width=24
  local filled=0
  local empty=0

  if [ "$total" -gt 0 ]; then
    filled=$((current * width / total))
  fi
  empty=$((width - filled))

  printf '['
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%*s' "$empty" '' | tr ' ' '.'
  printf ']'
}

safe_slug() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'
}

command_text() {
  local out=""
  local arg

  for arg in "$@"; do
    if [ -n "$out" ]; then
      out="${out} "
    fi
    printf -v out '%s%q' "$out" "$arg"
  done

  printf '%s\n' "$out"
}

fail() {
  local command_text="$1"
  local error_text="$2"
  local impact_text="$3"
  local next_step_text="$4"

  printf 'FALHA DETECTADA\n' >&2
  printf -- '- comando: %s\n' "$command_text" >&2
  printf -- '- erro: %s\n' "$error_text" >&2
  printf -- '- impacto: %s\n' "$impact_text" >&2
  printf -- '- próximo passo recomendado: %s\n' "$next_step_text" >&2
  printf -- '- log geral: %s\n' "$SCRIPT_LOG" >&2

  if [ -n "$LAST_STEP_LOG" ] && [ -s "$LAST_STEP_LOG" ]; then
    printf -- '- log da etapa: %s\n' "$LAST_STEP_LOG" >&2
    tail -n 40 "$LAST_STEP_LOG" >&2 || true
  fi

  exit 1
}

run_step() {
  local label="$1"
  shift
  local slug
  local status

  CURRENT_STEP=$((CURRENT_STEP + 1))
  slug="$(safe_slug "$label")"
  LAST_STEP_LOG="/tmp/root-step-$(printf '%02d' "$CURRENT_STEP")-${slug}.log"
  : > "$LAST_STEP_LOG"

  printf '\n%s (%s/%s) %s\n' "$(progress_bar "$CURRENT_STEP" "$TOTAL_STEPS")" "$CURRENT_STEP" "$TOTAL_STEPS" "$label" | tee -a "$SCRIPT_LOG"
  printf '[cmd] %s\n' "$(command_text "$@")" | tee -a "$SCRIPT_LOG"

  set +e
  "$@" 2>&1 | tee "$LAST_STEP_LOG" | tee -a "$SCRIPT_LOG"
  status=${PIPESTATUS[0]}
  set -e

  if [ "$status" -ne 0 ]; then
    fail \
      "$(command_text "$@")" \
      "Saída completa registrada em ${LAST_STEP_LOG}." \
      'A configuração root do Debian Trixie foi interrompida.' \
      'Corrigir o erro retornado e repetir a configuração dentro do proot.'
  fi
}

ensure_group() {
  local group_name="$1"

  if ! getent group "$group_name" >/dev/null 2>&1; then
    groupadd "$group_name"
  fi
}

ensure_dns() {
  local resolv_file="/etc/resolv.conf"

  rm -f "$resolv_file"
  cat <<'EOF' >"$resolv_file"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
  chmod 644 "$resolv_file"
  printf 'DNS forçado em %s.\n' "$resolv_file"
}

ensure_hosts() {
  local hosts_file="/etc/hosts"
  cat <<'EOF' >"$hosts_file"
127.0.0.1 localhost
::1 localhost
151.101.94.132 deb.debian.org
151.101.66.132 security.debian.org
EOF
  printf 'Hosts estáticos gravados em %s.\n' "$hosts_file"
}

configure_locale() {
  if grep -Eq '^[# ]*en_US.UTF-8 UTF-8' /etc/locale.gen; then
    sed -i -E 's/^[# ]*(en_US.UTF-8 UTF-8)$/\1/' /etc/locale.gen
  fi
  locale-gen en_US.UTF-8
  update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
}

configure_user_and_groups() {
  local group_name
  local group_list='sudo,audio,video,render,input,plugdev,users'
  local env_keep_vars=(
    DISPLAY
    XDG_RUNTIME_DIR
    XDG_SESSION_TYPE
    XDG_CURRENT_DESKTOP
    DESKTOP_SESSION
    DBUS_SESSION_BUS_ADDRESS
    PULSE_SERVER
    TERMUX_GUI_RENDERER
    TERMUX_GUI_PULSE_SERVER
    TERMUX_X11_WM
    GALLIUM_DRIVER
    LIBGL_ALWAYS_SOFTWARE
    GDK_BACKEND
    QT_QPA_PLATFORM
    SDL_VIDEODRIVER
    XAUTHORITY
    LANG
    LC_ALL
    TERM
  )
  local env_keep_joined=""

  for group_name in sudo audio video render input plugdev users; do
    ensure_group "$group_name"
  done

  if id -u "$PROOT_USER" >/dev/null 2>&1; then
    usermod -s /bin/bash -aG "$group_list" "$PROOT_USER"
  else
    useradd -m -s /bin/bash -G "$group_list" "$PROOT_USER"
  fi

  env_keep_joined="${env_keep_vars[*]}"

  cat > "/etc/sudoers.d/${PROOT_USER}" <<EOF
Defaults:${PROOT_USER} env_keep += "${env_keep_joined}"
${PROOT_USER} ALL=(ALL:ALL) NOPASSWD: ALL
EOF
  chmod 440 "/etc/sudoers.d/${PROOT_USER}"

  if ! visudo -cf "/etc/sudoers.d/${PROOT_USER}" >/dev/null 2>&1; then
    fail \
      "visudo -cf /etc/sudoers.d/${PROOT_USER}" \
      'A regra sudoers gerada para o usuário alvo é inválida.' \
      'O sudo sem senha não pode ser habilitado com segurança.' \
      'Revisar a sintaxe do arquivo sudoers antes de prosseguir.'
  fi

  install -d -m 755 "/home/${PROOT_USER}"
  install -d -m 755 "/home/${PROOT_USER}/bin"
  install -d -m 700 "/tmp/runtime-${PROOT_USER}"
  chown -R "${PROOT_USER}:${PROOT_USER}" "/home/${PROOT_USER}" "/tmp/runtime-${PROOT_USER}"

  printf 'Usuário alvo=%s\n' "$PROOT_USER"
  printf 'Grupos aplicados=%s\n' "$group_list"
  printf 'Variáveis preservadas no sudo=%s\n' "$env_keep_joined"
}

validate_user_configuration() {
  local expected_groups=(
    sudo
    audio
    video
    render
    input
    plugdev
    users
  )
  local group_name

  id "$PROOT_USER"
  getent passwd "$PROOT_USER"

  for group_name in "${expected_groups[@]}"; do
    if ! id -nG "$PROOT_USER" | tr ' ' '\n' | grep -Fx "$group_name" >/dev/null 2>&1; then
      printf 'Grupo obrigatório ausente para %s: %s\n' "$PROOT_USER" "$group_name" >&2
      return 1
    fi
  done

  sudo -l -U "$PROOT_USER"
  su - "$PROOT_USER" -c 'sudo -n true'
}

install_termux_desktop_sync_hook() {
  cat > /etc/apt/apt.conf.d/90termux-sync-desktop <<EOF
DPkg::Post-Invoke-Success {
  "if [ -x /home/${PROOT_USER}/bin/sync-termux-desktop-entries ]; then su - ${PROOT_USER} -c /home/${PROOT_USER}/bin/sync-termux-desktop-entries >/tmp/sync-termux-desktop-entries.log 2>&1 || true; fi";
};
APT::Update::Post-Invoke-Success {
  "if [ -x /home/${PROOT_USER}/bin/sync-termux-desktop-entries ]; then su - ${PROOT_USER} -c /home/${PROOT_USER}/bin/sync-termux-desktop-entries >/tmp/sync-termux-desktop-entries.log 2>&1 || true; fi";
};
EOF
  chmod 644 /etc/apt/apt.conf.d/90termux-sync-desktop
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user)
      shift
      PROOT_USER="${1:-}"
      shift || true
      ;;
    --help|-h)
      printf 'Uso: %s [--user nome]\n' "$0"
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'A configuração root não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --user ou --help.'
      ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  fail \
    'id -u' \
    'Este script precisa ser executado como root dentro do Debian.' \
    'Não é possível instalar pacotes nem criar usuários de forma confiável.' \
    'Entrar no proot Debian como root e executar novamente.'
fi

export DEBIAN_FRONTEND=noninteractive

run_step 'Garantindo resolução DNS do Debian' ensure_dns
run_step 'Aplicando mapeamento de hosts estáticos' ensure_hosts

run_step 'Atualizando índices apt do Debian' apt-get update
run_step 'Atualizando pacotes já instalados no Debian' apt-get "${APT_NONINTERACTIVE_OPTS[@]}" upgrade -y
run_step \
  'Instalando pacotes base do Debian/X11/Openbox' \
  apt-get "${APT_NONINTERACTIVE_OPTS[@]}" install -y sudo dbus-x11 pulseaudio mesa-utils mesa-utils-extra x11-apps xauth ca-certificates locales xterm xfce4-session xfce4-panel xfwm4 xfce4-terminal xfce4-settings thunar openbox obconf glmark2 tint2 rofi lxappearance dunst wmctrl
run_step 'Configurando locale do Debian' configure_locale
run_step 'Configurando usuário alvo, grupos e sudoers' configure_user_and_groups
run_step 'Instalando hook de sync de atalhos Debian para o Openbox host' install_termux_desktop_sync_hook
run_step 'Validando usuário alvo, grupos e sudo sem senha' validate_user_configuration

printf '\nConfiguração root Debian concluída.\n'
printf 'Usuário alvo: %s\n' "$PROOT_USER"
printf 'Pacotes GUI base instalados: sim\n'
printf 'Log geral: %s\n' "$SCRIPT_LOG"
