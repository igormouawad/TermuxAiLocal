#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

DISTRO_ALIAS="debian-trixie-gui"
PROOT_USER="igor"
RESET_DISTRO=0
ROOT_SCRIPT_LOCAL="/data/local/tmp/configure_debian_trixie_root.sh"
USER_SCRIPT_LOCAL="/data/local/tmp/configure_debian_trixie_user_igor.sh"
GUI_LAUNCHER_SCRIPT_LOCAL="/data/local/tmp/run_gui_in_debian.sh"
ROOT_SCRIPT_DISTRO="/root/configure_debian_trixie_root.sh"
USER_SCRIPT_DISTRO="/usr/local/bin/configure_debian_trixie_user_igor.sh"
PROOT_DISTRO_CACHE="${PREFIX}/var/lib/proot-distro/dlcache"
DEBIAN_ROOTFS_TARBALL="debian-trixie-aarch64-pd-v4.37.0.tar.xz"
DEBIAN_ROOTFS_URL="https://easycli.sh/proot-distro/${DEBIAN_ROOTFS_TARBALL}"
DEBIAN_ROOTFS_SHA="9bd3b19ff7cd300c7c7bf33124b726eb199f4bab9a3b1472f34749c6d12c9195"

CACHE_DIR="${HOME}/.cache/termux-stack"
LOG_DIR="${CACHE_DIR}/logs"
mkdir -p "$HOME/bin" "$LOG_DIR"

SCRIPT_LOG="${LOG_DIR}/install-debian-trixie-gui-$(date +%Y%m%d-%H%M%S).log"
TOTAL_STEPS=11
CURRENT_STEP=0
LAST_STEP_LOG=""
PKG_NONINTERACTIVE_OPTS=(
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confnew
)

now() {
  date '+%H:%M:%S'
}

log_plain() {
  printf '%s\n' "$*" | tee -a "$SCRIPT_LOG"
}

log_line() {
  printf '[%s] %s\n' "$(now)" "$*" | tee -a "$SCRIPT_LOG"
}

progress_bar() {
  local current="$1"
  local total="$2"
  local width=28
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
  LAST_STEP_LOG="${LOG_DIR}/debian-$(printf '%02d' "$CURRENT_STEP")-${slug}.log"
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
      'A preparação Debian GUI foi interrompida no Termux.' \
      'Corrigir o erro retornado e repetir a execução no app Termux.'
  fi
}

append_once() {
  local file_path="$1"
  local line_text="$2"

  if ! grep -Fqx "$line_text" "$file_path" 2>/dev/null; then
    printf '%s\n' "$line_text" >> "$file_path"
  fi
}

ensure_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    fail \
      "test -f \"$file_path\"" \
      'Arquivo obrigatório ausente em /data/local/tmp.' \
      'O payload Debian GUI não está completo no dispositivo.' \
      'Reexecutar Debian/adb_provision_debian_trixie_gui.sh no host.'
  fi
}

ensure_rootfs_archive() {
  mkdir -p "$PROOT_DISTRO_CACHE"
  local archive_path="$PROOT_DISTRO_CACHE/$DEBIAN_ROOTFS_TARBALL"

  if [ ! -f "$archive_path" ]; then
    log_line "Baixando rootfs Debian Trixie" \
      && curl --fail --silent --show-error --location \
        --output "$archive_path" "$DEBIAN_ROOTFS_URL"
  fi

  if ! command -v sha256sum >/dev/null 2>&1; then
    fail \
      'verificação de SHA-256' \
      'sha256sum não está instalado no Termux.' \
      'Não é possível validar a integridade do rootfs.' \
      'Instalar sha256sum (package coreutils) e executar novamente.'
  fi

  local actual_sha
  actual_sha=$(sha256sum "$archive_path" | awk '{ print $1 }')
  if [ "$actual_sha" != "$DEBIAN_ROOTFS_SHA" ]; then
    rm -f "$archive_path"
    fail \
      'integridade do rootfs Debian' \
      "SHA-256 inesperado: $actual_sha" \
      'O rootfs baixado parece corrompido.' \
      'Reexecutar o script e garantir conectividade com easycli.sh.'
  fi

  printf '%s' "$archive_path"
}

install_rootfs_from_archive() {
  local rootfs_dir="$1"
  local archive_path="$2"

  rm -rf "$rootfs_dir"
  mkdir -p "$rootfs_dir"
  log_line "Extraindo rootfs Debian manualmente"
  tar -xJf "$archive_path" -C "$rootfs_dir" \
    --warning=no-unknown-keyword --delay-directory-restore \
    --preserve-permissions --strip-components=1
}

configure_rootfs_locales() {
  local rootfs_dir="$1"
  log_line "Configurando locales dentro do rootfs Debian"
  sed -i -E 's/#[[:space:]]?(en_US.UTF-8[[:space:]]+UTF-8)/\1/g' \
    "$rootfs_dir/etc/locale.gen"
  proot -0 --rootfs="$rootfs_dir" --link2symlink \
    /usr/bin/env -i DEBIAN_FRONTEND=noninteractive HOME=/root LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    dpkg-reconfigure locales
}

register_android_users() {
  local rootfs_dir="$1"
  local passwd_file="$rootfs_dir/etc/passwd"
  local shadow_file="$rootfs_dir/etc/shadow"
  local group_file="$rootfs_dir/etc/group"
  local gshadow_file="$rootfs_dir/etc/gshadow"
  local termux_user
  termux_user=$(id -un)
  local termux_uid
  termux_uid=$(id -u)
  local termux_gid
  termux_gid=$(id -g)

  printf 'aid_%s:x:%s:%s:Termux:/:/sbin/nologin\n' "$termux_user" "$termux_uid" "$termux_gid" >> "$passwd_file"
  printf 'aid_%s:*:18446:0:99999:7:::\n' "$termux_user" >> "$shadow_file"

  paste <(id -Gn | tr ' ' '\n') <(id -G | tr ' ' '\n') | while read -r group_name group_id; do
    printf 'aid_%s:x:%s:root,aid_%s\n' "$group_name" "$group_id" "$termux_user" >> "$group_file"
    if [ -f "$gshadow_file" ]; then
      printf 'aid_%s:*::root,aid_%s\n' "$group_name" "$termux_user" >> "$gshadow_file"
    fi
  done
}

manual_rootfs_install() {
  local rootfs_dir="${PREFIX}/var/lib/proot-distro/installed-rootfs/${DISTRO_ALIAS}"
  local archive_path
  archive_path=$(ensure_rootfs_archive)
  install_rootfs_from_archive "$rootfs_dir" "$archive_path"
  configure_rootfs_locales "$rootfs_dir"
  register_android_users "$rootfs_dir"
  local plugin_dst="${PREFIX}/etc/proot-distro/${DISTRO_ALIAS}.override.sh"
  if [ ! -f "$plugin_dst" ]; then
    cp "${PREFIX}/etc/proot-distro/debian.sh" "$plugin_dst"
  fi
  log_line "Rootfs Debian implantado manualmente no alias ${DISTRO_ALIAS}"
}

prepare_termux_shell() {
  touch "$HOME/.bashrc"
  append_once "$HOME/.bashrc" 'export PATH="$HOME/bin:$PATH"'

  export PATH="$HOME/bin:$PATH"
  export XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none

  printf 'PATH atualizado com %s/bin\n' "$HOME"
  printf 'XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR"
  printf 'Log da instalação Debian=%s\n' "$SCRIPT_LOG"
}

remove_distro_if_requested() {
  local installed_rootfs_dir="${PREFIX}/var/lib/proot-distro/installed-rootfs/${DISTRO_ALIAS}"

  if [ "$RESET_DISTRO" -eq 1 ] && [ -d "$installed_rootfs_dir" ]; then
    proot-distro remove "$DISTRO_ALIAS"
  else
    printf 'Reset do Debian não solicitado ou rootfs inexistente; mantendo estado atual.\n'
  fi
}

install_distro_if_needed() {
  local installed_rootfs_dir="${PREFIX}/var/lib/proot-distro/installed-rootfs/${DISTRO_ALIAS}"

  if [ -d "$installed_rootfs_dir" ]; then
    printf 'Rootfs %s já presente; pulando instalação do Debian base.\n' "$DISTRO_ALIAS"
    return 0
  fi

  if proot-distro install --override-alias "$DISTRO_ALIAS" debian >/dev/null 2>&1; then
    return 0
  fi

  log_line "proot-distro install falhou; instalando rootfs manualmente"
  manual_rootfs_install
  return 0
}

copy_payloads_into_distro() {
  proot-distro copy "$ROOT_SCRIPT_LOCAL" "${DISTRO_ALIAS}:${ROOT_SCRIPT_DISTRO}"
  proot-distro copy "$USER_SCRIPT_LOCAL" "${DISTRO_ALIAS}:${USER_SCRIPT_DISTRO}"
  proot-distro login --no-arch-warning "$DISTRO_ALIAS" -- chmod 755 "$ROOT_SCRIPT_DISTRO" "$USER_SCRIPT_DISTRO"
}

configure_root_payload() {
  root_command=(/bin/bash "$ROOT_SCRIPT_DISTRO" --user "$PROOT_USER")

  proot-distro login --no-arch-warning "$DISTRO_ALIAS" -- "${root_command[@]}"
}

configure_user_payload() {
  proot-distro login --no-arch-warning --user "$PROOT_USER" --shared-tmp "$DISTRO_ALIAS" -- /bin/bash "$USER_SCRIPT_DISTRO"
}

install_termux_helpers() {
  install -m 755 "$GUI_LAUNCHER_SCRIPT_LOCAL" "$HOME/bin/run-gui-debian"

  cat > "$HOME/bin/login-debian-gui" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec proot-distro login --no-arch-warning --user ${PROOT_USER} --shared-tmp ${DISTRO_ALIAS}
EOF
  chmod 755 "$HOME/bin/login-debian-gui"
}

validate_debian_user_ready() {
  proot-distro login --no-arch-warning "$DISTRO_ALIAS" -- \
    /bin/bash -lc "id ${PROOT_USER} && sudo -l -U ${PROOT_USER}"

  proot-distro login --no-arch-warning --user "$PROOT_USER" --shared-tmp "$DISTRO_ALIAS" -- \
    /bin/bash -lc '
      id
      sudo -n true
      test -f "$HOME/.config/termux-stack/env.sh"
      test -x "$HOME/bin/run-gui-termux"
      test -x "$HOME/bin/run-gui-termux-xfce"
      test -x "$HOME/bin/start-xfce-termux-x11"
      . "$HOME/.config/termux-stack/env.sh"
      printf "DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nTERMUX_X11_WM=%s\nTERMUX_GUI_RENDERER=%s\nGALLIUM_DRIVER=%s\n" \
        "$DISPLAY" "$XDG_RUNTIME_DIR" "$TERMUX_X11_WM" "$TERMUX_GUI_RENDERER" "$GALLIUM_DRIVER"
    '
}

print_summary() {
  printf '\nDebian Trixie preparado para apps GUI no Termux.\n'
  printf 'Alias do proot-distro: %s\n' "$DISTRO_ALIAS"
  printf 'Usuário Debian: %s\n' "$PROOT_USER"
  printf 'Helpers instalados em: %s/bin\n' "$HOME"
  printf 'Log geral: %s\n' "$SCRIPT_LOG"
  printf 'Para abrir um shell Debian do usuário alvo: login-debian-gui\n'
  printf 'Para iniciar qualquer app GUI com 3D: run-gui-debian -- comando [args...]\n'
  printf 'O render padrão do launcher genérico ficou em hardware; fallback explícito em software continua disponível.\n'
  printf 'Antes de lançar apps GUI, suba ou valide a sessão Openbox/X11 em :1.\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --alias)
      shift
      DISTRO_ALIAS="${1:-}"
      shift || true
      ;;
    --reset-distro)
      RESET_DISTRO=1
      shift
      ;;
    --help|-h)
      printf 'Uso: %s [--alias nome] [--reset-distro]\n' "$0"
      exit 0
      ;;
    *)
      fail \
        'validação de argumentos' \
        "Argumento não suportado: $1" \
        'A instalação não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --alias, --reset-distro ou --help.'
      ;;
  esac
done

if [ -z "$DISTRO_ALIAS" ]; then
  fail \
    'validação de argumentos' \
    'O alias do proot-distro não pode ser vazio.' \
    'Não há como localizar ou criar a instância Debian correta.' \
    'Informar um alias não vazio com --alias.'
fi

if [ ! -d '/data/data/com.termux/files/usr' ] || [ "${PREFIX:-}" != '/data/data/com.termux/files/usr' ] || ! command -v pkg >/dev/null 2>&1; then
  fail \
    'validação do ambiente Termux' \
    'Este script deve ser executado dentro do app Termux.' \
    'Os binários e pacotes esperados não estão disponíveis neste contexto.' \
    'Abrir o app Termux e executar manualmente bash /data/local/tmp/install_debian_trixie_gui.sh.'
fi

ensure_file "$ROOT_SCRIPT_LOCAL"
ensure_file "$USER_SCRIPT_LOCAL"
ensure_file "$GUI_LAUNCHER_SCRIPT_LOCAL"

run_step 'Preparando shell do Termux para o provisionamento Debian' prepare_termux_shell
run_step 'Atualizando índice de pacotes pkg' pkg update -y
run_step 'Atualizando pacotes instalados do Termux' pkg upgrade -y "${PKG_NONINTERACTIVE_OPTS[@]}"
run_step 'Instalando dependências Termux para proot-distro' pkg install -y "${PKG_NONINTERACTIVE_OPTS[@]}" proot-distro pulseaudio dbus
run_step 'Resetando o Debian existente quando solicitado' remove_distro_if_requested
run_step 'Instalando rootfs Debian base se necessário' install_distro_if_needed
run_step 'Copiando payloads internos para o Debian' copy_payloads_into_distro
run_step 'Executando configuração root do Debian' configure_root_payload
run_step 'Executando configuração do usuário Debian alvo' configure_user_payload
run_step 'Validando usuário Debian, sudo e ambiente gráfico' validate_debian_user_ready
run_step 'Instalando helpers finais no Termux' install_termux_helpers
print_summary
