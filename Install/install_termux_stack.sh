#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

CACHE_DIR="${HOME}/.cache/termux-stack"
LOG_DIR="${CACHE_DIR}/logs"
mkdir -p "$HOME/bin" "$CACHE_DIR" "$LOG_DIR"

SCRIPT_LOG="${LOG_DIR}/install-termux-stack-$(date +%Y%m%d-%H%M%S).log"
TOTAL_STEPS=12
CURRENT_STEP=0
LAST_STEP_LOG=""
DEFAULT_X11_RESOLUTION="${TERMUX_X11_DEFAULT_RESOLUTION:-1920x1080}"
DEFAULT_X11_PROFILE="${TERMUX_X11_DEFAULT_PROFILE:-balanced}"
TERMUX_X11_BALANCED_RESOLUTION="${TERMUX_X11_BALANCED_RESOLUTION:-${DEFAULT_X11_RESOLUTION}}"
TERMUX_X11_PERFORMANCE_RESOLUTION="${TERMUX_X11_PERFORMANCE_RESOLUTION:-1280x720}"
TERMUX_X11_SHOW_ADDITIONAL_KBD_DEFAULT="${TERMUX_X11_SHOW_ADDITIONAL_KBD_DEFAULT:-false}"
TERMUX_X11_ADDITIONAL_KBD_VISIBLE_DEFAULT="${TERMUX_X11_ADDITIONAL_KBD_VISIBLE_DEFAULT:-false}"
TERMUX_X11_SWIPE_DOWN_ACTION_DEFAULT="${TERMUX_X11_SWIPE_DOWN_ACTION_DEFAULT:-no action}"
TERMUX_MAIN_REPO_URL="${TERMUX_MAIN_REPO_URL:-https://packages-cf.termux.dev/apt/termux-main}"
TERMUX_ROOT_REPO_URL="${TERMUX_ROOT_REPO_URL:-https://packages-cf.termux.dev/apt/termux-root}"
TERMUX_X11_REPO_URL="${TERMUX_X11_REPO_URL:-https://packages-cf.termux.dev/apt/termux-x11}"
PKG_NONINTERACTIVE_OPTS=(
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confnew
)

now() {
  date '+%H:%M:%S'
}

log_blank_line() {
  printf '\n' | tee -a "$SCRIPT_LOG"
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
    printf -- '- últimas linhas da etapa:\n' >&2
    tail -n 40 "$LAST_STEP_LOG" >&2 || true
  fi

  exit 1
}

run_step() {
  local label="$1"
  shift
  local slug
  local status
  local summary

  CURRENT_STEP=$((CURRENT_STEP + 1))
  slug="$(safe_slug "$label")"
  LAST_STEP_LOG="${LOG_DIR}/$(printf '%02d' "$CURRENT_STEP")-${slug}.log"
  : > "$LAST_STEP_LOG"

  summary="$(progress_bar "$CURRENT_STEP" "$TOTAL_STEPS") (${CURRENT_STEP}/${TOTAL_STEPS}) ${label}"
  log_blank_line
  log_line "$summary"
  log_line "Comando: $(command_text "$@")"

  set +e
  "$@" 2>&1 | tee "$LAST_STEP_LOG" | tee -a "$SCRIPT_LOG"
  status=${PIPESTATUS[0]}
  set -e

  if [ "$status" -ne 0 ]; then
    fail \
      "$(command_text "$@")" \
      "Saída completa registrada em ${LAST_STEP_LOG}." \
      'A instalação da stack Termux foi interrompida.' \
      'Corrigir o erro mostrado acima e executar novamente no app Termux.'
  fi

  log_line "Etapa concluída: ${label}"
}

append_once() {
  local file_path="$1"
  local line_text="$2"

  if ! grep -Fqx "$line_text" "$file_path" 2>/dev/null; then
    printf '%s\n' "$line_text" >> "$file_path"
  fi
}

ensure_termux_context() {
  if [ ! -d "/data/data/com.termux/files/usr" ] || [ "${PREFIX:-}" != "/data/data/com.termux/files/usr" ] || ! command -v pkg >/dev/null 2>&1; then
    fail \
      'validação do ambiente Termux' \
      'Este script deve ser executado dentro do app Termux.' \
      'Os binários e pacotes esperados não estão disponíveis neste contexto.' \
      'Abrir o app Termux e executar manualmente bash /data/local/tmp/install_termux_stack.sh.'
  fi
}

prepare_termux_shell() {
  touch "$HOME/.bashrc"
  append_once "$HOME/.bashrc" 'export PATH="$HOME/bin:$PATH"'

  export PATH="$HOME/bin:$PATH"
  export TERMUX_STACK_DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
  export DISPLAY="$TERMUX_STACK_DISPLAY"
  export XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  export TERMUX_PKG_NO_MIRROR_SELECT=1

  log_line "HOME/bin garantido no PATH."
  log_line "DISPLAY=${DISPLAY}"
  log_line "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
  log_line "TERMUX_PKG_NO_MIRROR_SELECT=${TERMUX_PKG_NO_MIRROR_SELECT}"
  log_line "Log da instalação: ${SCRIPT_LOG}"
}

configure_termux_repos() {
  mkdir -p "${PREFIX}/etc/apt/sources.list.d" "${PREFIX}/etc/termux/mirrors"

  cat > "${PREFIX}/etc/apt/sources.list" <<EOF
deb ${TERMUX_MAIN_REPO_URL} stable main
EOF

  cat > "${PREFIX}/etc/termux/mirrors/default" <<EOF
# This file is sourced by pkg
# Termux origin repo. Behind cloudflare cache.
# Termux | https://packages.termux.dev
# Termux origin repo behind cloudflare cache.
WEIGHT=10
MAIN="${TERMUX_MAIN_REPO_URL}"
ROOT="${TERMUX_ROOT_REPO_URL}"
X11="${TERMUX_X11_REPO_URL}"
EOF

  rm -rf "${PREFIX}/etc/termux/chosen_mirrors"
  ln -s "${PREFIX}/etc/termux/mirrors/default" "${PREFIX}/etc/termux/chosen_mirrors"

  if [ -f "${PREFIX}/etc/apt/sources.list.d/x11.list" ] || command -v termux-x11-preference >/dev/null 2>&1 || dpkg -s x11-repo >/dev/null 2>&1; then
    cat > "${PREFIX}/etc/apt/sources.list.d/x11.list" <<EOF
deb ${TERMUX_X11_REPO_URL} x11 main
EOF
  fi

  printf 'Repo principal=%s\n' "$TERMUX_MAIN_REPO_URL"
  printf 'Mirror default root=%s\n' "$TERMUX_ROOT_REPO_URL"
  printf 'chosen_mirrors=%s\n' "${PREFIX}/etc/termux/chosen_mirrors"
  if [ -f "${PREFIX}/etc/apt/sources.list.d/x11.list" ]; then
    printf 'Repo x11=%s\n' "$TERMUX_X11_REPO_URL"
  else
    printf 'Repo x11 ainda não disponível; será fixado após instalar x11-repo.\n'
  fi
}

cleanup_existing_termux_gui_state() {
  local cache_root="${HOME}/.cache/termux-stack"

  pkill -f '^openbox( |$)|openbox-session' >/dev/null 2>&1 || true
  pkill -f '^aterm( |$)' >/dev/null 2>&1 || true
  pkill -f '^xterm( |$)' >/dev/null 2>&1 || true
  pkill -f '^xfce4-session( |$)|^xfwm4( |$)|^xfdesktop( |$)|^xfce4-panel( |$)|^xfce4-terminal( |$)|^xfsettingsd( |$)|^Thunar( |$)|^thunar( |$)' >/dev/null 2>&1 || true
  pkill -f '^dbus-daemon .*--session' >/dev/null 2>&1 || true
  pkill -f 'virgl_test_server_android' >/dev/null 2>&1 || true
  pkill -x termux-x11 >/dev/null 2>&1 || true
  pkill -f '^termux-x11 com\.termux\.x11 ' >/dev/null 2>&1 || true
  pkill -f 'termux-x11 .*:1|termux-x11 :1|com\.termux\.x11\.Loader' >/dev/null 2>&1 || true

  rm -rf "$HOME/.cache/sessions" >/dev/null 2>&1 || true
  rm -rf "${cache_root}/openbox" >/dev/null 2>&1 || true
  rm -rf "${cache_root}/dbus" >/dev/null 2>&1 || true
  rm -f "${cache_root}/"*.log >/dev/null 2>&1 || true
  rm -f "$HOME/.config/termux-stack/session.env" "$HOME/.config/termux-stack/driver.env" >/dev/null 2>&1 || true

  printf 'Estado gráfico anterior limpo.\n'
}

normalize_termux_x11_wrapper() {
  local wrapper_path="${PREFIX}/bin/termux-x11"

  if [ ! -f "$wrapper_path" ]; then
    printf 'Wrapper termux-x11 ausente em %s; nenhuma normalização aplicada.\n' "$wrapper_path"
    return 0
  fi

  if grep -Fq -- '--nice-name="termux-x11 com.termux.x11 $*"' "$wrapper_path"; then
    printf 'Wrapper termux-x11 já está alinhado ao upstream atual.\n'
    return 0
  fi

  cat > "$wrapper_path" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
[ -z "${LD_LIBRARY_PATH+x}" ] || export XSTARTUP_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
[ -z "${LD_PRELOAD+x}" ] || export XSTARTUP_LD_PRELOAD="$LD_PRELOAD"
[ -z "${CLASSPATH+x}" ] || export XSTARTUP_CLASSPATH="$CLASSPATH"
export CLASSPATH=/data/data/com.termux/files/usr/libexec/termux-x11/loader.apk
unset LD_LIBRARY_PATH LD_PRELOAD
exec /system/bin/app_process -Xnoimage-dex2oat / --nice-name="termux-x11 com.termux.x11 $*" com.termux.x11.Loader "$@"
EOF

  chmod 700 "$wrapper_path"
  printf 'Wrapper termux-x11 normalizado com --nice-name upstream.\n'
}

install_termux_common_lib() {
  mkdir -p "$HOME/.config/termux-stack"

  cat > "$HOME/.config/termux-stack/termux-stack-common.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

TERMUX_X11_DEFAULT_RESOLUTION="${TERMUX_X11_DEFAULT_RESOLUTION:-1920x1080}"
TERMUX_X11_BALANCED_RESOLUTION="${TERMUX_X11_BALANCED_RESOLUTION:-${TERMUX_X11_DEFAULT_RESOLUTION}}"
TERMUX_X11_PERFORMANCE_RESOLUTION="${TERMUX_X11_PERFORMANCE_RESOLUTION:-1280x720}"
TERMUX_STACK_DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
TERMUX_STACK_SESSION_ENV_FILE="${HOME}/.config/termux-stack/session.env"
TERMUX_STACK_DRIVER_ENV_FILE="${HOME}/.config/termux-stack/driver.env"
TERMUX_OPENBOX_DEFAULT_PROFILE="${TERMUX_OPENBOX_DEFAULT_PROFILE:-openbox-maxperf}"
TERMUX_VULKAN_WRAPPER_ICD="${TERMUX_VULKAN_WRAPPER_ICD:-${PREFIX:-/data/data/com.termux/files/usr}/share/vulkan/icd.d/wrapper_icd.aarch64.json}"
export TERMUX_X11_DEFAULT_RESOLUTION TERMUX_X11_BALANCED_RESOLUTION TERMUX_X11_PERFORMANCE_RESOLUTION TERMUX_STACK_DISPLAY
export TERMUX_STACK_SESSION_ENV_FILE TERMUX_STACK_DRIVER_ENV_FILE TERMUX_OPENBOX_DEFAULT_PROFILE TERMUX_VULKAN_WRAPPER_ICD

stack_now() {
  date '+%H:%M:%S'
}

stack_line() {
  printf '[%s] %s\n' "$(stack_now)" "$*"
}

stack_progress_bar() {
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

stack_normalize_openbox_profile() {
  case "${1:-${TERMUX_OPENBOX_DEFAULT_PROFILE:-openbox-maxperf}}" in
    stable|openbox-stable)
      printf 'openbox-stable\n'
      ;;
    maxperf|performance|openbox-maxperf)
      printf 'openbox-maxperf\n'
      ;;
    compat|openbox-compat)
      printf 'openbox-compat\n'
      ;;
    vulkan|vulkan-exp|openbox-vulkan-exp)
      printf 'openbox-vulkan-exp\n'
      ;;
    *)
      return 1
      ;;
  esac
}

stack_openbox_profile_resolution() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1

  case "$profile" in
    openbox-maxperf)
      printf 'performance\n'
      ;;
    *)
      printf 'balanced\n'
      ;;
  esac
}

stack_openbox_profile_dbus() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1

  case "$profile" in
    openbox-stable|openbox-compat)
      printf 'on\n'
      ;;
    *)
      printf 'off\n'
      ;;
  esac
}

stack_openbox_profile_virgl_mode() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1

  case "$profile" in
    openbox-compat)
      printf 'gl\n'
      ;;
    openbox-vulkan-exp)
      printf 'vulkan\n'
      ;;
    *)
      printf 'plain\n'
      ;;
  esac
}

stack_openbox_profile_driver_profile() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1

  case "$profile" in
    openbox-compat)
      printf 'virgl-angle\n'
      ;;
    openbox-vulkan-exp)
      printf 'virgl-vulkan\n'
      ;;
    *)
      printf 'virgl-plain\n'
      ;;
  esac
}

stack_openbox_profile_gl_version() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1

  case "$profile" in
    openbox-compat)
      printf '4.0\n'
      ;;
    *)
      printf '4.3COMPAT\n'
      ;;
  esac
}

stack_openbox_profile_gles_version() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1
  printf '3.2\n'
}

stack_openbox_dbus_address() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1
  printf 'unix:path=%s/.cache/termux-stack/dbus/%s.bus\n' "$HOME" "$profile"
}

stack_source_env_file() {
  local env_file="$1"

  if [ -f "$env_file" ]; then
    # shellcheck source=/dev/null
    . "$env_file"
  fi
}

stack_load_session_env() {
  stack_source_env_file "$TERMUX_STACK_SESSION_ENV_FILE"
}

stack_load_driver_env() {
  stack_source_env_file "$TERMUX_STACK_DRIVER_ENV_FILE"
}

stack_reset_driver_env() {
  unset LIBGL_ALWAYS_SOFTWARE || true
  unset WAYLAND_DISPLAY || true
  unset VK_ICD_FILENAMES || true
  unset EPOXY_USE_ANGLE || true
  unset MESA_VK_WSI_PRESENT_MODE || true
  unset MESA_VK_WSI_DEBUG || true
  unset MESA_SHADER_CACHE || true
  unset vblank_mode || true
}

stack_cleanup_gui_state() {
  local keep_x11="${1:-0}"
  local keep_virgl="${2:-0}"
  local cache_root="${HOME}/.cache/termux-stack"

  pkill -f '^openbox( |$)|openbox-session' >/dev/null 2>&1 || true
  pkill -f '^aterm( |$)' >/dev/null 2>&1 || true
  pkill -f '^xterm( |$)' >/dev/null 2>&1 || true
  pkill -f '^tint2( |$)|^rofi( |$)|^dunst( |$)|^xfsettingsd( |$)|^obconf-qt( |$)|^lxappearance( |$)' >/dev/null 2>&1 || true
  pkill -f '^xfce4-session( |$)|^xfwm4( |$)|^xfdesktop( |$)|^xfce4-panel( |$)|^xfce4-terminal( |$)|^xfsettingsd( |$)|^Thunar( |$)|^thunar( |$)' >/dev/null 2>&1 || true
  pkill -f '^dbus-daemon .*--session' >/dev/null 2>&1 || true

  if [ "$keep_virgl" != '1' ]; then
    pkill -f 'virgl_test_server_android' >/dev/null 2>&1 || true
  fi

  if [ "$keep_x11" != '1' ]; then
    pkill -x termux-x11 >/dev/null 2>&1 || true
    pkill -f '^termux-x11 com\.termux\.x11 ' >/dev/null 2>&1 || true
    pkill -f 'termux-x11 .*:1|termux-x11 :1|com\.termux\.x11\.Loader' >/dev/null 2>&1 || true
  fi

  rm -rf "$HOME/.cache/sessions" >/dev/null 2>&1 || true
  rm -rf "${cache_root}/openbox" >/dev/null 2>&1 || true
  rm -rf "${cache_root}/dbus" >/dev/null 2>&1 || true
  rm -f "${cache_root}/"*.log >/dev/null 2>&1 || true
}

stack_write_openbox_env_files() {
  local profile resolution_profile dbus_mode virgl_mode driver_profile dbus_address

  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1
  resolution_profile="$(stack_openbox_profile_resolution "$profile")"
  dbus_mode="$(stack_openbox_profile_dbus "$profile")"
  virgl_mode="$(stack_openbox_profile_virgl_mode "$profile")"
  driver_profile="$(stack_openbox_profile_driver_profile "$profile")"
  dbus_address="$(stack_openbox_dbus_address "$profile")"

  mkdir -p "$(dirname "$TERMUX_STACK_SESSION_ENV_FILE")" "$HOME/.cache/termux-stack/dbus"

  cat > "$TERMUX_STACK_SESSION_ENV_FILE" <<STACKSESSIONEOF
#!/data/data/com.termux/files/usr/bin/bash
export TERMUX_STACK_DISPLAY=":1"
export DISPLAY="\${TERMUX_STACK_DISPLAY}"
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-\${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
export TERMUX_OPENBOX_PROFILE="${profile}"
export TERMUX_X11_SESSION_PROFILE="${profile}"
export TERMUX_X11_RESOLUTION_PROFILE="${resolution_profile}"
export TERMUX_DRIVER_PROFILE="${driver_profile}"
export TERMUX_VIRGL_MODE="${virgl_mode}"
export TERMUX_OPENBOX_DBUS="${dbus_mode}"
export TERMUX_STACK_DBUS_ADDRESS="${dbus_address}"
STACKSESSIONEOF

  if [ "$dbus_mode" = 'on' ]; then
    printf 'export DBUS_SESSION_BUS_ADDRESS="%s"\n' "$dbus_address" >> "$TERMUX_STACK_SESSION_ENV_FILE"
  else
    printf 'unset DBUS_SESSION_BUS_ADDRESS\n' >> "$TERMUX_STACK_SESSION_ENV_FILE"
  fi

  cat > "$TERMUX_STACK_DRIVER_ENV_FILE" <<STACKDRIVEREOF
#!/data/data/com.termux/files/usr/bin/bash
unset LIBGL_ALWAYS_SOFTWARE
unset WAYLAND_DISPLAY
unset VK_ICD_FILENAMES
unset EPOXY_USE_ANGLE
unset MESA_VK_WSI_PRESENT_MODE
unset MESA_VK_WSI_DEBUG
unset MESA_SHADER_CACHE
unset vblank_mode
export TERMUX_DRIVER_PROFILE="${driver_profile}"
export TERMUX_VIRGL_MODE="${virgl_mode}"
export GALLIUM_DRIVER="virpipe"
export MESA_NO_ERROR="1"
export LIBGL_DRI3_DISABLE="1"
export MESA_GL_VERSION_OVERRIDE="$(stack_openbox_profile_gl_version "$profile")"
export MESA_GLES_VERSION_OVERRIDE="$(stack_openbox_profile_gles_version "$profile")"
STACKDRIVEREOF

  case "$profile" in
    openbox-maxperf)
      printf 'export vblank_mode="0"\n' >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      ;;
    openbox-compat)
      printf 'export EPOXY_USE_ANGLE="1"\n' >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      ;;
    openbox-vulkan-exp)
      printf 'export EPOXY_USE_ANGLE="1"\n' >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      printf 'export MESA_VK_WSI_PRESENT_MODE="mailbox"\n' >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      printf 'export MESA_VK_WSI_DEBUG="blit"\n' >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      printf 'export MESA_SHADER_CACHE="512MB"\n' >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      printf 'export vblank_mode="0"\n' >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      if [ -f "$TERMUX_VULKAN_WRAPPER_ICD" ]; then
        printf 'export VK_ICD_FILENAMES="%s"\n' "$TERMUX_VULKAN_WRAPPER_ICD" >> "$TERMUX_STACK_DRIVER_ENV_FILE"
      fi
      ;;
  esac

  chmod 600 "$TERMUX_STACK_SESSION_ENV_FILE" "$TERMUX_STACK_DRIVER_ENV_FILE"
}

stack_openbox_background_color() {
  local profile
  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1

  case "$profile" in
    openbox-stable)
      printf '#1f1f1f\n'
      ;;
    openbox-compat)
      printf '#1f2233\n'
      ;;
    openbox-vulkan-exp)
      printf '#151922\n'
      ;;
    *)
      printf '#20242b\n'
      ;;
  esac
}

stack_write_tint2_user_config() {
  local tint2_dir

  tint2_dir="$HOME/.config/tint2"
  mkdir -p "$tint2_dir"

  cat > "$tint2_dir/tint2rc" <<'TINT2RCEOF'
# Managed by TermuxAiLocal

# Background 1: panel
rounded = 0
border_width = 0
border_sides = TBLR
background_color = #16181d 92
border_color = #16181d 92
background_color_hover = #16181d 92
border_color_hover = #16181d 92
background_color_pressed = #16181d 92
border_color_pressed = #16181d 92

# Background 2: inactive task
rounded = 4
border_width = 0
border_sides = TBLR
background_color = #232730 88
border_color = #232730 88
background_color_hover = #2c313d 96
border_color_hover = #2c313d 96
background_color_pressed = #303646 100
border_color_pressed = #303646 100

# Background 3: active task / button
rounded = 4
border_width = 0
border_sides = TBLR
background_color = #3a404d 96
border_color = #3a404d 96
background_color_hover = #454d5f 100
border_color_hover = #454d5f 100
background_color_pressed = #4f586d 100
border_color_pressed = #4f586d 100

# Background 4: tooltip
rounded = 3
border_width = 1
border_sides = TBLR
background_color = #f3f1e8 100
border_color = #8d8d8d 100
background_color_hover = #f3f1e8 100
border_color_hover = #8d8d8d 100
background_color_pressed = #f3f1e8 100
border_color_pressed = #8d8d8d 100

panel_items = PTSC
panel_size = 100% 34
panel_margin = 0 4
panel_padding = 8 4 8
panel_background_id = 1
wm_menu = 1
panel_dock = 1
panel_position = top center horizontal
panel_layer = normal
panel_monitor = all
panel_shrink = 0
autohide = 0
strut_policy = follow_size
panel_window_name = tint2
disable_transparency = 0
mouse_effects = 1
font_shadow = 0
mouse_hover_icon_asb = 100 0 10
mouse_pressed_icon_asb = 100 0 0

taskbar_mode = single_desktop
taskbar_hide_if_empty = 0
taskbar_padding = 6 0 6
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_name = 0
taskbar_hide_inactive_tasks = 0
taskbar_hide_different_monitor = 0
taskbar_hide_different_desktop = 0
taskbar_always_show_all_desktop_tasks = 0
taskbar_distribute_size = 1
taskbar_sort_order = none
task_align = center

task_text = 1
task_icon = 1
task_centered = 0
urgent_nb_of_blink = 100000
task_maximum_size = 220 34
task_padding = 8 4 8
task_font = sans 8
task_tooltip = 1
task_font_color = #eceff4 100
task_icon_asb = 100 0 0
task_background_id = 2
task_active_background_id = 3
task_urgent_background_id = 3
task_iconified_background_id = 2
mouse_left = toggle_iconify
mouse_middle = none
mouse_right = close
mouse_scroll_up = prev_task
mouse_scroll_down = next_task

systray_padding = 6 0 6
systray_background_id = 0
systray_sort = ascending
systray_icon_size = 18
systray_icon_asb = 100 0 0
systray_monitor = primary
systray_name_filter =

time1_format = %H:%M
time1_font = sans bold 9
clock_font_color = #eceff4 100
clock_padding = 8 0
clock_background_id = 0
clock_tooltip = %A, %d %b %Y

tooltip_show_timeout = 0.2
tooltip_hide_timeout = 0.1
tooltip_padding = 6 4
tooltip_background_id = 4
tooltip_font_color = #181818 100

button = new
button_icon = /data/data/com.termux/files/usr/share/icons/AdwaitaLegacy/24x24/places/start-here.png
button_text =
button_tooltip = Launcher de aplicativos
button_font = sans bold 8
button_font_color = #eceff4 100
button_background_id = 3
button_centered = 1
button_padding = 8 4 0
button_max_icon_size = 18
button_lclick_command = openbox-launcher
button_rclick_command = openbox-file-manager
button_mclick_command = openbox-terminal
TINT2RCEOF

  chmod 644 "$tint2_dir/tint2rc"
}

stack_write_rofi_user_config() {
  local rofi_dir

  rofi_dir="$HOME/.config/rofi"
  mkdir -p "$rofi_dir"

  cat > "$rofi_dir/termux-openbox.rasi" <<'ROFIRASIEOF'
/* Managed by TermuxAiLocal */

configuration {
  modi: "drun,window,run";
  show-icons: true;
  drun-display-format: "{name}";
  disable-history: false;
  display-drun: "Apps";
  display-window: "Windows";
  display-run: "Run";
  sidebar-mode: true;
  font: "Sans 9";
}

* {
  bg0: #11141b;
  bg1: #1a1f29;
  bg2: #242b38;
  bg3: #2f3848;
  fg0: #eef1f7;
  fg1: #b8c0cc;
  accent: #7aa2f7;
  urgent: #f7768e;
  border: #7aa2f7;
  border-radius: 10px;
}

window {
  width: 42%;
  location: north;
  anchor: north;
  x-offset: 0px;
  y-offset: 42px;
  border: 2px;
  border-radius: 10px;
  border-color: @border;
  background-color: @bg0;
}

mainbox {
  spacing: 10px;
  padding: 10px;
  background-color: transparent;
}

inputbar {
  children: [ prompt, entry ];
  spacing: 10px;
  padding: 10px 12px;
  border: 0px;
  border-radius: 8px;
  background-color: @bg1;
}

prompt {
  text-color: @accent;
  background-color: transparent;
}

entry {
  text-color: @fg0;
  background-color: transparent;
  placeholder: "Search apps, windows or run commands";
  placeholder-color: @fg1;
}

message {
  enabled: false;
}

listview {
  lines: 10;
  columns: 1;
  cycle: true;
  dynamic: true;
  scrollbar: false;
  layout: vertical;
  spacing: 6px;
  padding: 2px;
  background-color: transparent;
}

element {
  padding: 8px 10px;
  border: 0px;
  border-radius: 8px;
  background-color: transparent;
  text-color: @fg0;
}

element normal.urgent,
element alternate.urgent {
  text-color: @urgent;
}

element selected.normal,
element selected.active {
  background-color: @bg2;
  text-color: @fg0;
}

element selected.urgent {
  background-color: @urgent;
  text-color: #101319;
}

element-icon {
  size: 22px;
  background-color: transparent;
}

element-text {
  vertical-align: 0.5;
  text-color: inherit;
  background-color: transparent;
}
ROFIRASIEOF

  chmod 644 "$rofi_dir/termux-openbox.rasi"
}

stack_write_openbox_user_config() {
  local profile background_color openbox_dir

  profile="$(stack_normalize_openbox_profile "${1:-}")" || return 1
  background_color="$(stack_openbox_background_color "$profile")"
  openbox_dir="$HOME/.config/openbox"

  stack_write_tint2_user_config
  stack_write_rofi_user_config

  mkdir -p "$openbox_dir" "$HOME/bin"

  cat > "$HOME/bin/openbox-terminal" <<'OPENBOXTERMINALEOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

session_file="$HOME/.config/termux-stack/session.env"
driver_file="$HOME/.config/termux-stack/driver.env"

if [ -f "$session_file" ]; then
  # shellcheck source=/dev/null
  . "$session_file"
fi
if [ -f "$driver_file" ]; then
  # shellcheck source=/dev/null
  . "$driver_file"
fi

distro_user="${TERMUX_X11_DISTRO_USER:-igor}"

if command -v run-gui-debian >/dev/null 2>&1; then
  exec run-gui-debian --label 'Debian Terminal' -- xfce4-terminal --working-directory="/home/${distro_user}" --title='Debian Terminal'
fi

if command -v aterm >/dev/null 2>&1; then
  exec aterm -geometry 100x30+20+20 -e bash -l
fi

if command -v xterm >/dev/null 2>&1; then
  exec xterm -geometry 100x30+20+20 -e bash -l
fi

printf 'Nenhum terminal leve esta disponivel no Termux.\n' >&2
exit 1
OPENBOXTERMINALEOF

  cat > "$HOME/bin/openbox-launcher" <<'OPENBOXLAUNCHEREOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

session_file="$HOME/.config/termux-stack/session.env"
driver_file="$HOME/.config/termux-stack/driver.env"

if [ -f "$session_file" ]; then
  # shellcheck source=/dev/null
  . "$session_file"
fi
if [ -f "$driver_file" ]; then
  # shellcheck source=/dev/null
  . "$driver_file"
fi

applications_dir="$HOME/.local/share/applications"
mkdir -p "$applications_dir"

cat > "$applications_dir/openbox-terminal.desktop" <<'EOF2'
[Desktop Entry]
Type=Application
Name=Terminal
Exec=/data/data/com.termux/files/home/bin/openbox-terminal
Terminal=false
StartupNotify=true
Categories=System;TerminalEmulator;
EOF2

cat > "$applications_dir/openbox-files.desktop" <<'EOF2'
[Desktop Entry]
Type=Application
Name=Files
Exec=/data/data/com.termux/files/home/bin/openbox-file-manager
Terminal=false
StartupNotify=true
Categories=System;FileManager;
EOF2

cat > "$applications_dir/openbox-settings.desktop" <<'EOF2'
[Desktop Entry]
Type=Application
Name=Settings
Exec=/data/data/com.termux/files/home/bin/openbox-settings
Terminal=false
StartupNotify=true
Categories=Settings;DesktopSettings;
EOF2

if command -v proot-distro >/dev/null 2>&1; then
  (timeout 6 proot-distro login --no-arch-warning --user igor --shared-tmp debian-trixie-gui -- /home/igor/bin/sync-termux-desktop-entries >/dev/null 2>&1 || true) &
fi

if command -v rofi >/dev/null 2>&1; then
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_DATA_DIRS="$HOME/.local/share"
  exec rofi \
    -show drun \
    -theme "$HOME/.config/rofi/termux-openbox.rasi" \
    -drun-reload-desktop-cache \
    -drun-match-fields name,generic,exec,categories,comment
fi

printf 'rofi nao encontrado. Reaplique o payload do Openbox funcional.\n' >&2
exit 1
OPENBOXLAUNCHEREOF

  cat > "$HOME/bin/openbox-file-manager" <<'OPENBOXFILEMANAGEREOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

session_file="$HOME/.config/termux-stack/session.env"
driver_file="$HOME/.config/termux-stack/driver.env"

if [ -f "$session_file" ]; then
  # shellcheck source=/dev/null
  . "$session_file"
fi
if [ -f "$driver_file" ]; then
  # shellcheck source=/dev/null
  . "$driver_file"
fi

if command -v run-gui-debian >/dev/null 2>&1; then
  exec run-gui-debian --label 'Arquivos' -- thunar
fi

if command -v thunar >/dev/null 2>&1; then
  exec thunar
fi

if command -v pcmanfm >/dev/null 2>&1; then
  exec pcmanfm
fi

exec "$HOME/bin/openbox-terminal"
OPENBOXFILEMANAGEREOF

  cat > "$HOME/bin/openbox-settings" <<'OPENBOXSETTINGSEOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

session_file="$HOME/.config/termux-stack/session.env"
driver_file="$HOME/.config/termux-stack/driver.env"

if [ -f "$session_file" ]; then
  # shellcheck source=/dev/null
  . "$session_file"
fi
if [ -f "$driver_file" ]; then
  # shellcheck source=/dev/null
  . "$driver_file"
fi

if command -v run-gui-debian >/dev/null 2>&1; then
  if run-gui-debian --label 'Aparencia' -- lxappearance >/dev/null 2>&1; then
    exit 0
  fi
  exec run-gui-debian --label 'Openbox Settings' -- obconf
fi

if command -v xfce4-settings-manager >/dev/null 2>&1 && [ "${TERMUX_OPENBOX_DBUS:-off}" = 'on' ]; then
  exec xfce4-settings-manager
fi

if command -v lxappearance >/dev/null 2>&1; then
  exec lxappearance
fi

if command -v obconf-qt >/dev/null 2>&1; then
  exec obconf-qt
fi

printf 'Nenhuma ferramenta de configuracao grafica esta disponivel.\n' >&2
exit 1
OPENBOXSETTINGSEOF

  cat > "$HOME/bin/openbox-reconfigure" <<'OPENBOXRECONFIGUREEOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

session_file="$HOME/.config/termux-stack/session.env"
driver_file="$HOME/.config/termux-stack/driver.env"

if [ -f "$session_file" ]; then
  # shellcheck source=/dev/null
  . "$session_file"
fi
if [ -f "$driver_file" ]; then
  # shellcheck source=/dev/null
  . "$driver_file"
fi

exec openbox --reconfigure
OPENBOXRECONFIGUREEOF

  chmod 755 \
    "$HOME/bin/openbox-terminal" \
    "$HOME/bin/openbox-launcher" \
    "$HOME/bin/openbox-file-manager" \
    "$HOME/bin/openbox-settings" \
    "$HOME/bin/openbox-reconfigure"

  cat > "$openbox_dir/environment" <<'OPENBOXENVEOF'
#!/data/data/com.termux/files/usr/bin/sh
export PATH="$HOME/bin:$PATH"
export DESKTOP_SESSION="openbox"
export XDG_CURRENT_DESKTOP="Openbox"
export _JAVA_AWT_WM_NONREPARENTING=1

session_file="$HOME/.config/termux-stack/session.env"
driver_file="$HOME/.config/termux-stack/driver.env"

if [ -f "$session_file" ]; then
  . "$session_file"
fi
if [ -f "$driver_file" ]; then
  . "$driver_file"
fi
OPENBOXENVEOF

  cat > "$openbox_dir/autostart" <<OPENBOXAUTOSTARTEOF
#!/data/data/com.termux/files/usr/bin/sh
if command -v xsetroot >/dev/null 2>&1; then
  xsetroot -cursor_name left_ptr -solid '${background_color}'
fi

if command -v tint2 >/dev/null 2>&1 && ! pgrep -x tint2 >/dev/null 2>&1; then
  tint2 >/dev/null 2>&1 &
fi

if [ "\${TERMUX_OPENBOX_DBUS:-off}" = 'on' ]; then
  if command -v xfsettingsd >/dev/null 2>&1 && ! pgrep -x xfsettingsd >/dev/null 2>&1; then
    xfsettingsd >/dev/null 2>&1 &
  fi
  if command -v dunst >/dev/null 2>&1 && ! pgrep -x dunst >/dev/null 2>&1; then
    dunst >/dev/null 2>&1 &
  fi
fi
OPENBOXAUTOSTARTEOF

  cat > "$openbox_dir/menu.xml" <<'OPENBOXMENUXMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Openbox">
    <separator label="Workspace" />
    <item label="Launch Applications">
      <action name="Execute">
        <command>openbox-launcher</command>
        <startupnotify>
          <enabled>yes</enabled>
        </startupnotify>
      </action>
    </item>
    <item label="Terminal">
      <action name="Execute">
        <command>openbox-terminal</command>
        <startupnotify>
          <enabled>yes</enabled>
        </startupnotify>
      </action>
    </item>
    <item label="File Manager">
      <action name="Execute">
        <command>openbox-file-manager</command>
        <startupnotify>
          <enabled>yes</enabled>
        </startupnotify>
      </action>
    </item>
    <item label="Settings">
      <action name="Execute">
        <command>openbox-settings</command>
        <startupnotify>
          <enabled>yes</enabled>
        </startupnotify>
      </action>
    </item>
    <item label="Refresh Debian Launchers">
      <action name="Execute">
        <command>/data/data/com.termux/files/usr/bin/bash -lc 'command -v sync-termux-desktop-entries >/dev/null 2>&1 &amp;&amp; sync-termux-desktop-entries || printf "sync-termux-desktop-entries indisponivel\\n"'</command>
      </action>
    </item>
    <separator />
    <menu id="client-list-combined-menu" />
    <separator />
    <item label="Reconfigure Openbox">
      <action name="Execute">
        <command>openbox-reconfigure</command>
      </action>
    </item>
    <item label="Restart Openbox">
      <action name="Restart" />
    </item>
    <item label="Stop Openbox session">
      <action name="Exit">
        <prompt>yes</prompt>
      </action>
    </item>
  </menu>
</openbox_menu>
OPENBOXMENUXMLEOF

  cat > "$openbox_dir/rc.xml" <<'OPENBOXRCXMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <margins>
    <top>40</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
  <desktops>
    <number>4</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Main</name>
      <name>Web</name>
      <name>Files</name>
      <name>Tools</name>
    </names>
    <popupTime>500</popupTime>
  </desktops>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    <keybind key="W-space">
      <action name="Execute">
        <command>openbox-launcher</command>
      </action>
    </keybind>
    <keybind key="W-Return">
      <action name="Execute">
        <command>openbox-terminal</command>
      </action>
    </keybind>
    <keybind key="W-e">
      <action name="Execute">
        <command>openbox-file-manager</command>
      </action>
    </keybind>
    <keybind key="W-comma">
      <action name="Execute">
        <command>openbox-settings</command>
      </action>
    </keybind>
    <keybind key="W-r">
      <action name="Reconfigure" />
    </keybind>
    <keybind key="A-F4">
      <action name="Close" />
    </keybind>
    <keybind key="W-1">
      <action name="Desktop">
        <desktop>1</desktop>
      </action>
    </keybind>
    <keybind key="W-2">
      <action name="Desktop">
        <desktop>2</desktop>
      </action>
    </keybind>
    <keybind key="W-3">
      <action name="Desktop">
        <desktop>3</desktop>
      </action>
    </keybind>
    <keybind key="W-4">
      <action name="Desktop">
        <desktop>4</desktop>
      </action>
    </keybind>
    <keybind key="W-S-1">
      <action name="SendToDesktop">
        <desktop>1</desktop>
        <follow>yes</follow>
      </action>
    </keybind>
    <keybind key="W-S-2">
      <action name="SendToDesktop">
        <desktop>2</desktop>
        <follow>yes</follow>
      </action>
    </keybind>
    <keybind key="W-S-3">
      <action name="SendToDesktop">
        <desktop>3</desktop>
        <follow>yes</follow>
      </action>
    </keybind>
    <keybind key="W-S-4">
      <action name="SendToDesktop">
        <desktop>4</desktop>
        <follow>yes</follow>
      </action>
    </keybind>
  </keyboard>
  <menu>
    <file>menu.xml</file>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
    <submenuHideDelay>300</submenuHideDelay>
    <applicationIcons>yes</applicationIcons>
  </menu>
  <applications>
    <application class="FreeCAD">
      <position force="yes">
        <x>center</x>
        <y>40</y>
      </position>
    </application>
  </applications>
</openbox_config>
OPENBOXRCXMLEOF

  chmod 700 "$openbox_dir/autostart"
  chmod 644 "$openbox_dir/environment" "$openbox_dir/menu.xml" "$openbox_dir/rc.xml"
}

stack_openbox_current_profile() {
  if [ -n "${TERMUX_OPENBOX_PROFILE:-}" ]; then
    stack_normalize_openbox_profile "$TERMUX_OPENBOX_PROFILE"
    return 0
  fi

  if [ -f "$TERMUX_STACK_SESSION_ENV_FILE" ]; then
    (
      # shellcheck source=/dev/null
      . "$TERMUX_STACK_SESSION_ENV_FILE"
      stack_normalize_openbox_profile "${TERMUX_OPENBOX_PROFILE:-${TERMUX_X11_SESSION_PROFILE:-${TERMUX_OPENBOX_DEFAULT_PROFILE:-openbox-maxperf}}}"
    )
    return 0
  fi

  stack_normalize_openbox_profile "${TERMUX_OPENBOX_DEFAULT_PROFILE:-openbox-maxperf}"
}

stack_current_driver_profile() {
  if [ -n "${TERMUX_DRIVER_PROFILE:-}" ]; then
    printf '%s\n' "$TERMUX_DRIVER_PROFILE"
    return 0
  fi

  if [ -f "$TERMUX_STACK_DRIVER_ENV_FILE" ]; then
    (
      # shellcheck source=/dev/null
      . "$TERMUX_STACK_DRIVER_ENV_FILE"
      printf '%s\n' "${TERMUX_DRIVER_PROFILE:-$(stack_openbox_profile_driver_profile "$(stack_openbox_current_profile)")}"
    )
    return 0
  fi

  stack_openbox_profile_driver_profile "$(stack_openbox_current_profile)"
}

stack_dbus_session_state() {
  local expected_mode

  expected_mode="$(stack_openbox_profile_dbus "$(stack_openbox_current_profile)" 2>/dev/null || printf 'off')"
  if pgrep -f '^dbus-daemon .*--session' >/dev/null 2>&1; then
    printf 'active\n'
    return 0
  fi

  if [ "$expected_mode" = 'on' ]; then
    printf 'expected-on\n'
    return 0
  fi

  printf 'off\n'
}

stack_pref_value() {
  local key="$1"

  if ! command -v termux-x11-preference >/dev/null 2>&1; then
    return 1
  fi

  termux-x11-preference list 2>/dev/null | awk -F'"' -v target="$key" '$2 == target { print $4; exit }'
}

stack_show_resolution() {
  local pref_output=""

  if command -v termux-x11-preference >/dev/null 2>&1; then
    pref_output="$(termux-x11-preference list 2>/dev/null | grep -E 'displayResolutionMode|displayResolutionExact|displayResolutionCustom|displayScale' || true)"
    if [ -n "$pref_output" ]; then
      printf '%s\n' "$pref_output"
    elif stack_x11_running; then
      printf 'displayResolutionMode=indisponivel\n'
      printf 'displayResolutionExact=indisponivel\n'
      printf 'displayScale=indisponivel\n'
    else
      printf 'displayResolutionMode=desconhecido (Termux:X11 inativo)\n'
      printf 'displayResolutionExact=desconhecido (Termux:X11 inativo)\n'
      printf 'displayScale=desconhecido (Termux:X11 inativo)\n'
    fi
  else
    printf 'displayResolutionMode=indisponivel\n'
  fi
}

stack_current_resolution() {
  local exact_resolution=""
  local mode_value=""

  if ! command -v termux-x11-preference >/dev/null 2>&1; then
    printf '%s\n' "${TERMUX_X11_DEFAULT_RESOLUTION:-unknown}"
    return 0
  fi

  exact_resolution="$(stack_pref_value displayResolutionExact || true)"
  mode_value="$(stack_pref_value displayResolutionMode || true)"

  case "$mode_value" in
    exact)
      if [ -n "$exact_resolution" ]; then
        printf '%s\n' "$exact_resolution"
        return 0
      fi
      ;;
    native)
      printf 'native\n'
      return 0
      ;;
  esac

  printf '%s\n' "${TERMUX_X11_DEFAULT_RESOLUTION:-unknown}"
}

stack_current_profile() {
  local mode_value=""
  local current_resolution=""

  mode_value="$(stack_pref_value displayResolutionMode || true)"
  current_resolution="$(stack_current_resolution)"

  case "$mode_value" in
    native)
      printf 'native\n'
      return 0
      ;;
  esac

  if [ "$current_resolution" = "${TERMUX_X11_PERFORMANCE_RESOLUTION:-1280x720}" ]; then
    printf 'performance\n'
    return 0
  fi

  if [ "$current_resolution" = "${TERMUX_X11_BALANCED_RESOLUTION:-${TERMUX_X11_DEFAULT_RESOLUTION:-1920x1080}}" ] \
    || [ "$current_resolution" = "${TERMUX_X11_DEFAULT_RESOLUTION:-1920x1080}" ]; then
    printf 'balanced\n'
    return 0
  fi

  if [ -n "$current_resolution" ]; then
    printf 'custom\n'
    return 0
  fi

  printf '%s\n' "${TERMUX_X11_DEFAULT_PROFILE:-balanced}"
}

stack_x11_running() {
  pgrep -f 'termux-x11 .*:1|termux-x11 :1' >/dev/null 2>&1
}

stack_virgl_running() {
  pgrep -f 'virgl_test_server_android' >/dev/null 2>&1
}

stack_virgl_mode() {
  local virgl_pid
  virgl_pid=$(pgrep -f 'virgl_test_server_android' | head -n 1)

  if [ -z "$virgl_pid" ]; then
    printf 'off\n'
    return 0
  fi

  if ps -o args= "$virgl_pid" 2>/dev/null | grep -Fq -- '--angle-vulkan'; then
    printf 'angle-vulkan\n'
    return 0
  fi

  if ps -o args= "$virgl_pid" 2>/dev/null | grep -Fq -- '--angle-gl'; then
    printf 'angle-gl\n'
    return 0
  fi

  printf 'plain\n'
}

stack_xfce_base_ready() {
  pgrep -f '^xfce4-session( |$)|^xfce4-panel( |$)' >/dev/null 2>&1
}

stack_selected_xfce_wm() {
  case "${TERMUX_X11_WM:-xfwm4}" in
    openbox|xfwm4)
      printf '%s\n' "${TERMUX_X11_WM:-xfwm4}"
      ;;
    *)
      printf 'xfwm4\n'
      ;;
  esac
}

stack_xfce_wm_label() {
  if pgrep -f '^openbox( |$)' >/dev/null 2>&1; then
    printf 'openbox\n'
    return 0
  fi

  if pgrep -f '^xfwm4( |$)' >/dev/null 2>&1; then
    printf 'xfwm4\n'
    return 0
  fi

  printf 'none\n'
}

stack_xfce_wm_matches() {
  local expected_wm="${1:-$(stack_selected_xfce_wm)}"
  local current_wm

  current_wm="$(stack_xfce_wm_label)"
  [ "$current_wm" = "$expected_wm" ]
}

stack_xfce_ready() {
  stack_xfce_base_ready && stack_xfce_wm_matches
}

stack_xfce_base_ready_in_distro() {
  local distro_alias="${TERMUX_X11_DISTRO_ALIAS:-debian-trixie-gui}"
  local distro_user="${TERMUX_X11_DISTRO_USER:-igor}"

  proot-distro login --no-arch-warning --user "$distro_user" --shared-tmp "$distro_alias" -- \
    /bin/bash -lc 'pgrep -f "^xfce4-session( |$)|^xfce4-panel( |$)" >/dev/null 2>&1' \
    >/dev/null 2>&1
}

stack_xfce_wm_matches_in_distro() {
  local distro_alias="${TERMUX_X11_DISTRO_ALIAS:-debian-trixie-gui}"
  local distro_user="${TERMUX_X11_DISTRO_USER:-igor}"
  local expected_wm="${1:-$(stack_selected_xfce_wm)}"

  proot-distro login --no-arch-warning --user "$distro_user" --shared-tmp "$distro_alias" -- \
    /bin/bash -lc "pgrep -f '^${expected_wm}( |$)' >/dev/null 2>&1" \
    >/dev/null 2>&1
}

stack_xfce_ready_in_distro() {
  stack_xfce_base_ready_in_distro && stack_xfce_wm_matches_in_distro
}

stack_xfce_wm_label_in_distro() {
  local distro_alias="${TERMUX_X11_DISTRO_ALIAS:-debian-trixie-gui}"
  local distro_user="${TERMUX_X11_DISTRO_USER:-igor}"

  proot-distro login --no-arch-warning --user "$distro_user" --shared-tmp "$distro_alias" -- /bin/bash -lc '
    if pgrep -f "^openbox( |$)" >/dev/null 2>&1; then
      printf "openbox\n"
      exit 0
    fi

    if pgrep -f "^xfwm4( |$)" >/dev/null 2>&1; then
      printf "xfwm4\n"
      exit 0
    fi

    printf "none\n"
  ' 2>/dev/null
}

stack_x11_app_reachable() {
  command -v termux-x11-preference >/dev/null 2>&1 && termux-x11-preference list >/dev/null 2>&1
}

stack_openbox_running() {
  pgrep -f '^openbox( |$)|openbox-session' >/dev/null 2>&1
}

stack_x11_socket_path() {
  local display_name="${1:-:1}"
  local display_number="${display_name#:}"
  printf '%s/.X11-unix/X%s\n' "${TMPDIR:-/data/data/com.termux/files/usr/tmp}" "$display_number"
}

stack_x11_display_probe() {
  local display_name="${1:-:1}"
  local probe_log="${2:-/dev/null}"
  local socket_path

  if command -v xrdb >/dev/null 2>&1; then
    DISPLAY="$display_name" xrdb -query >/dev/null 2>"$probe_log" && return 0
    return 1
  fi

  socket_path="$(stack_x11_socket_path "$display_name")"
  [ -S "$socket_path" ] && return 0

  return 1
}

stack_desktop_label() {
  local wm_label

  if stack_xfce_base_ready; then
    wm_label="$(stack_xfce_wm_label)"
    if [ "$wm_label" != 'none' ]; then
      printf 'xfce-termux-%s\n' "$wm_label"
      return 0
    fi
  fi

  if command -v proot-distro >/dev/null 2>&1; then
    if stack_xfce_base_ready_in_distro; then
      wm_label="$(stack_xfce_wm_label_in_distro)"
      if [ "$wm_label" != 'none' ]; then
        printf 'xfce-debian-%s\n' "$wm_label"
        return 0
      fi

      printf 'xfce-debian\n'
      return 0
    fi
  fi

  if stack_openbox_running; then
    printf 'openbox\n'
    return 0
  fi

  printf 'inativo\n'
}

stack_wait_for_x11_display() {
  local display_name="$1"
  local attempts="${2:-12}"
  local probe_log="${HOME}/.cache/termux-stack/x11-probe.log"
  local attempt

  mkdir -p "$(dirname "$probe_log")"
  : > "$probe_log"

  for attempt in $(seq 1 "$attempts"); do
    if stack_x11_display_probe "$display_name" "$probe_log"; then
      return 0
    fi
    if [ "$attempt" -eq "$attempts" ] && ! command -v xrdb >/dev/null 2>&1; then
      printf 'Probe X11 sem xrdb: socket %s ainda não está pronto.\n' "$(stack_x11_socket_path "$display_name")" >"$probe_log"
    fi
    sleep 1
  done

  stack_line "Falha: o display ${display_name} ainda não aceita conexões X11."
  if [ -s "$probe_log" ]; then
    sed -n '1,80p' "$probe_log" >&2
  fi
  return 1
}

stack_x11_state() {
  local display_name="${1:-:1}"

  if stack_x11_display_probe "$display_name"; then
    printf 'display-ready\n'
    return 0
  fi

  if stack_x11_running; then
    printf 'process-started\n'
    return 0
  fi

  if stack_x11_app_reachable; then
    printf 'activity-open\n'
    return 0
  fi

  printf 'stopped\n'
}
EOF

  chmod 700 "$HOME/.config/termux-stack/termux-stack-common.sh"
}

install_termux_helpers() {
  install_termux_common_lib

  cat > "$HOME/bin/stop-termux-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

if command -v am >/dev/null 2>&1; then
  am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
fi

pkill -x termux-x11 >/dev/null 2>&1 || true
pkill -f '^termux-x11 com\.termux\.x11 ' >/dev/null 2>&1 || true
pkill -f 'termux-x11 .*:1|termux-x11 :1|com\.termux\.x11\.Loader' >/dev/null 2>&1 || true

for _attempt in 1 2 3 4 5; do
  if ! pgrep -x termux-x11 >/dev/null 2>&1 \
    && ! pgrep -f '^termux-x11 com\.termux\.x11 ' >/dev/null 2>&1 \
    && ! pgrep -f 'termux-x11 .*:1|termux-x11 :1|com\.termux\.x11\.Loader' >/dev/null 2>&1; then
    printf 'termux-x11 encerrado. A activity Android pode permanecer aberta; para fechar a app use o helper host-side.\n'
    exit 0
  fi
  sleep 1
done

printf 'Falha: o processo termux-x11 permaneceu ativo.\n' >&2
exit 1
EOF

  cat > "$HOME/bin/termux-stack-status" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
WITH_GPU=0
BRIEF=0

if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
else
  printf 'Biblioteca comum ausente em %s\n' "$COMMON_LIB" >&2
  exit 1
fi

stack_load_session_env
export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gpu)
      WITH_GPU=1
      shift
      ;;
    --brief)
      BRIEF=1
      shift
      ;;
    --help|-h)
      printf 'Uso: %s [--brief] [--gpu]\n' "$0"
      exit 0
      ;;
    *)
      printf 'Argumento não suportado: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

x11_state='parado'
virgl_state='parado'
virgl_mode="$(stack_virgl_mode)"
desktop_state="$(stack_desktop_label)"
desktop_wm='none'
resolved_x11_state="$(stack_x11_state "$DISPLAY")"
default_resolution="${TERMUX_X11_DEFAULT_RESOLUTION:-unknown}"
default_profile="${TERMUX_X11_DEFAULT_PROFILE:-balanced}"
current_resolution="$(stack_current_resolution)"
current_profile="$(stack_current_profile)"
session_profile="$(stack_openbox_current_profile 2>/dev/null || printf 'openbox-maxperf')"
driver_profile="$(stack_current_driver_profile 2>/dev/null || printf 'virgl-plain')"
dbus_state="$(stack_dbus_session_state 2>/dev/null || printf 'off')"

case "$resolved_x11_state" in
  display-ready)
    x11_state='display-ready'
    ;;
  process-started)
    x11_state='process-started'
    ;;
  activity-open)
    x11_state='activity-open'
    ;;
  *)
    x11_state='parado'
    ;;
esac

if stack_virgl_running; then
  virgl_state='ativo'
fi

case "$desktop_state" in
  *-openbox|openbox)
    desktop_wm='openbox'
    ;;
  *-xfwm4)
    desktop_wm='xfwm4'
    ;;
esac

if [ "$BRIEF" -eq 1 ]; then
  printf 'X11=%s VIRGL=%s MODE=%s DESKTOP=%s WM=%s RES=%s PROFILE=%s OPENBOX_PROFILE=%s DRIVER=%s DBUS=%s DISPLAY=%s\n' \
    "$x11_state" "$virgl_state" "$virgl_mode" "$desktop_state" "$desktop_wm" "$current_resolution" "$current_profile" "$session_profile" "$driver_profile" "$dbus_state" "$DISPLAY"
  exit 0
fi

stack_line 'Resumo do stack Termux/X11'
printf 'DISPLAY=%s\n' "${DISPLAY:-${TERMUX_STACK_DISPLAY:-:1}}"
printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
printf 'termux-x11=%s\n' "$x11_state"
printf 'virgl=%s\n' "$virgl_state"
printf 'desktop=%s\n' "$desktop_state"
printf 'wm=%s\n' "$desktop_wm"
printf 'helpers=%s\n' "$HOME/bin"
stack_show_resolution
printf 'virgl-mode=%s\n' "$virgl_mode"
printf 'openbox-profile=%s\n' "$session_profile"
printf 'driver-profile=%s\n' "$driver_profile"
printf 'dbus=%s\n' "$dbus_state"
printf 'current-profile=%s\n' "$current_profile"
printf 'default-resolution=%s\n' "$default_resolution"
printf 'default-profile=%s\n' "$default_profile"

if [ "$WITH_GPU" -eq 1 ]; then
  if command -v check-gpu-termux >/dev/null 2>&1; then
    printf '\n'
    check-gpu-termux
  else
    printf 'check-gpu-termux não encontrado.\n' >&2
    exit 1
  fi
fi
EOF

  cat > "$HOME/bin/start-termux-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
fi

export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"

stack_line "$(stack_progress_bar 1 3) (1/3) Verificando termux-x11"
if [ "$(stack_x11_state "$DISPLAY")" = 'display-ready' ]; then
  printf 'termux-x11 já aceita conexões em :1.\n'
  "$HOME/bin/termux-stack-status" --brief || true
  exit 0
fi

stack_line "$(stack_progress_bar 2 3) (2/3) Iniciando servidor termux-x11"
if command -v am >/dev/null 2>&1; then
  am start -n com.termux.x11/.MainActivity >/dev/null 2>&1 || true
fi
if stack_x11_running; then
  printf 'Processo termux-x11 já existe sem display pronto; reiniciando a sessão X11.\n'
  if command -v stop-termux-x11 >/dev/null 2>&1; then
    stop-termux-x11 >/dev/null 2>&1 || true
    sleep 1
  fi
fi
if stack_x11_running; then
  printf 'Processo termux-x11 ainda permaneceu ativo; aguardando a surface do display :1.\n'
else
  termux-x11 :1 >/dev/null 2>&1 &
  disown || true
  sleep 2
fi

stack_line "$(stack_progress_bar 3 3) (3/3) Validando display :1"
if ! stack_wait_for_x11_display "$DISPLAY" 12; then
  printf 'Falha: o display %s não ficou pronto.\n' "$DISPLAY" >&2
  exit 1
fi

if command -v termux-x11-preference >/dev/null 2>&1; then
  termux-x11-preference \
    showAdditionalKbd:false \
    additionalKbdVisible:false \
    swipeDownAction:"no action" >/dev/null 2>&1 || true
fi

printf 'termux-x11 iniciado em :1.\n'
stack_show_resolution
"$HOME/bin/termux-stack-status" --brief || true
EOF

  cat > "$HOME/bin/start-virgl" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
fi

export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
VIRGL_ANDROID_LIBDIR="${PREFIX}/opt/virglrenderer-android/lib"

mode="${1:-${TERMUX_VIRGL_MODE:-plain}}"

case "$mode" in
  plain)
    virgl_args=()
    ;;
  gl)
    virgl_args=(--angle-gl)
    ;;
  vulkan)
    virgl_args=(--angle-vulkan)
    ;;
  *)
    printf 'Modo inválido para start-virgl: %s\n' "$mode" >&2
    printf 'Use: plain, gl ou vulkan.\n' >&2
    exit 1
    ;;
esac

stack_line "$(stack_progress_bar 1 3) (1/3) Verificando servidor virgl"
virgl_process_count="$(pgrep -fc 'virgl_test_server_android' || true)"
current_mode="$(stack_virgl_mode)"

if [ "${virgl_process_count:-0}" -gt 1 ]; then
  printf 'Foram encontrados %s processos virgl; reiniciando em modo %s.\n' "$virgl_process_count" "$mode"
  pkill -f 'virgl_test_server_android' >/dev/null 2>&1 || true
  sleep 1
elif [ "${virgl_process_count:-0}" -eq 1 ] && [ "$current_mode" = "$mode" ]; then
  printf 'virgl_test_server_android já está em execução no modo %s.\n' "$mode"
  "$HOME/bin/termux-stack-status" --brief || true
  exit 0
elif [ "${virgl_process_count:-0}" -eq 1 ]; then
  printf 'virgl_test_server_android já está em execução no modo %s; reiniciando em %s.\n' "$current_mode" "$mode"
  pkill -f 'virgl_test_server_android' >/dev/null 2>&1 || true
  sleep 1
fi

stack_line "$(stack_progress_bar 2 3) (2/3) Iniciando virgl no modo ${mode}"
# Restrict the child lookup path to the package-private virgl libs so it
# still resolves libepoxy/libvirglrenderer, but keeps EGL/GLES on Android's
# native stack instead of Termux Mesa's software loader.
virgl_ld_library_path="${VIRGL_ANDROID_LIBDIR}"
if command -v setsid >/dev/null 2>&1 && command -v nohup >/dev/null 2>&1; then
  nohup setsid env LD_LIBRARY_PATH="$virgl_ld_library_path" virgl_test_server_android "${virgl_args[@]}" >/dev/null 2>&1 < /dev/null &
elif command -v setsid >/dev/null 2>&1; then
  setsid env LD_LIBRARY_PATH="$virgl_ld_library_path" virgl_test_server_android "${virgl_args[@]}" >/dev/null 2>&1 < /dev/null &
elif command -v nohup >/dev/null 2>&1; then
  nohup env LD_LIBRARY_PATH="$virgl_ld_library_path" virgl_test_server_android "${virgl_args[@]}" >/dev/null 2>&1 < /dev/null &
else
  env LD_LIBRARY_PATH="$virgl_ld_library_path" virgl_test_server_android "${virgl_args[@]}" >/dev/null 2>&1 &
fi
disown || true
sleep 1

stack_line "$(stack_progress_bar 3 3) (3/3) Validando processo"
if ! stack_virgl_running; then
  printf 'Falha: o processo virgl_test_server_android não permaneceu ativo.\n' >&2
  exit 1
fi

printf 'virgl_test_server_android iniciado em modo %s.\n' "$mode"
"$HOME/bin/termux-stack-status" --brief || true
EOF

  cat > "$HOME/bin/stop-virgl" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

pkill -f 'virgl_test_server_android' >/dev/null 2>&1 || true

for _attempt in 1 2 3 4 5; do
  if ! pgrep -f 'virgl_test_server_android' >/dev/null 2>&1; then
    printf 'virgl_test_server_android encerrado.\n'
    exit 0
  fi
  sleep 1
done

printf 'Falha: o processo virgl_test_server_android permaneceu ativo.\n' >&2
exit 1
EOF

  cat > "$HOME/bin/check-gpu-termux" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
fi

export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
stack_load_session_env
stack_reset_driver_env
stack_load_driver_env

if ! command -v es2_info >/dev/null 2>&1; then
  printf 'es2_info não encontrado. Instale mesa-demos antes de executar este diagnóstico.\n' >&2
  exit 1
fi

driver_profile="${TERMUX_DRIVER_PROFILE:-$(stack_current_driver_profile 2>/dev/null || printf 'virgl-plain')}"

stack_line 'Resumo do diagnóstico GPU'
printf 'DISPLAY=%s\n' "$DISPLAY"
printf 'XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR"
printf 'virgl=%s\n' "$(stack_virgl_running && printf ativo || printf parado)"
printf 'desktop=%s\n' "$(stack_desktop_label)"
printf 'driver-profile=%s\n' "$driver_profile"

run_es2_probe() {
  local probe_name="$1"
  shift
  local probe_output
  local probe_status

  printf '\nPROBE=%s\n' "$probe_name"

  set +e
  probe_output=$(env "$@" timeout 20s es2_info 2>&1)
  probe_status=$?
  set -e

  printf '%s\n' "$probe_output" | grep -E 'EGL_VERSION|EGL_VENDOR|GL_VENDOR|GL_VERSION|GL_RENDERER' || true
  printf 'es2_info exit code: %s\n' "$probe_status"

  return "$probe_status"
}

run_es2gears_probe() {
  local probe_name="$1"
  shift
  local probe_output
  local probe_status

  printf 'ES2GEARS=%s\n' "$probe_name"

  set +e
  probe_output=$(env "$@" timeout 6s es2gears_x11 2>&1)
  probe_status=$?
  set -e

  printf '%s\n' "$probe_output" | grep 'frames in' || printf '%s\n' "$probe_output"
  printf 'es2gears_x11 exit code: %s\n' "$probe_status"

  return "$probe_status"
}

run_glx_probe() {
  local probe_output
  local probe_status

  if ! command -v glxinfo >/dev/null 2>&1; then
    printf 'glxinfo indisponível neste ambiente; pulando teste GLX.\n'
    return 0
  fi

  printf 'GLX_PROBE=%s\n' "$driver_profile"

  set +e
  probe_output=$(env DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" LIBGL_ALWAYS_INDIRECT=1 timeout 20s glxinfo -B 2>&1)
  probe_status=$?
  set -e

  printf '%s\n' "$probe_output"
  printf 'glxinfo exit code: %s\n' "$probe_status"

  return "$probe_status"
}

if run_es2_probe "$driver_profile" DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"; then
  run_es2gears_probe "$driver_profile" DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" || true
  if ! run_glx_probe; then
    printf 'Aviso: a trilha GLX continua instável neste dispositivo; prefira apps EGL/GLES com o perfil atual.\n'
  fi
  if [ "${1:-}" = "--gears" ]; then
    if command -v timeout >/dev/null 2>&1 && command -v es2gears_x11 >/dev/null 2>&1; then
      env DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" timeout 5s es2gears_x11
    else
      printf 'es2gears_x11 opcional indisponível neste ambiente.\n'
    fi
  fi
  exit 0
fi

printf 'EGL/GLES do perfil atual indisponível ou instável neste dispositivo; tentando fallback GLX em software.\n'

if command -v glxinfo >/dev/null 2>&1 && run_glx_fallback_output=$(env DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" LIBGL_ALWAYS_SOFTWARE=1 timeout 20s glxinfo -B 2>&1); then
  printf '%s\n' "$run_glx_fallback_output"
  printf 'glxinfo exit code: 0\n'
  if [ "${1:-}" = "--gears" ]; then
    if command -v timeout >/dev/null 2>&1 && command -v glxgears >/dev/null 2>&1; then
      env DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" LIBGL_ALWAYS_SOFTWARE=1 timeout 5s glxgears
    else
      printf 'glxgears opcional indisponível neste ambiente.\n'
    fi
  fi
  exit 0
fi

exit 1
EOF

  cat > "$HOME/bin/start-openbox-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
fi

export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
profile="${TERMUX_OPENBOX_PROFILE:-${TERMUX_X11_SESSION_PROFILE:-openbox-maxperf}}"
OPENBOX_LOG="${HOME}/.cache/termux-stack/start-openbox-x11.log"
OPENBOX_RUNTIME_DIR="${HOME}/.cache/termux-stack/openbox"

usage() {
  printf 'Uso: %s [--profile openbox-stable|openbox-maxperf|openbox-compat|openbox-vulkan-exp]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      shift
      profile="${1:-}"
      shift || true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Argumento não suportado para start-openbox-x11: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! profile="$(stack_normalize_openbox_profile "$profile")"; then
  printf 'Perfil Openbox inválido: %s\n' "${profile:-}" >&2
  usage >&2
  exit 1
fi

resolution_profile="$(stack_openbox_profile_resolution "$profile")"
dbus_mode="$(stack_openbox_profile_dbus "$profile")"
virgl_mode="$(stack_openbox_profile_virgl_mode "$profile")"
driver_profile="$(stack_openbox_profile_driver_profile "$profile")"

if ! command -v openbox >/dev/null 2>&1; then
  printf 'openbox não encontrado. Reinstale o payload ou instale openbox no Termux.\n' >&2
  exit 1
fi

if [ "$dbus_mode" = 'on' ] && ! command -v dbus-daemon >/dev/null 2>&1; then
  printf 'dbus-daemon não encontrado. Reinstale o payload ou instale dbus no Termux.\n' >&2
  exit 1
fi

start_session_dbus() {
  local bus_path

  bus_path="${TERMUX_STACK_DBUS_ADDRESS#unix:path=}"
  mkdir -p "$(dirname "$bus_path")"
  rm -f "$bus_path" >/dev/null 2>&1 || true
  pkill -f '^dbus-daemon .*--session' >/dev/null 2>&1 || true
  dbus-daemon --session --address="$TERMUX_STACK_DBUS_ADDRESS" --fork --nopidfile >/dev/null 2>&1
}

write_openbox_runtime_launchers() {
  mkdir -p "$OPENBOX_RUNTIME_DIR"

  cat > "$OPENBOX_RUNTIME_DIR/openbox-session.sh" <<'LAUNCHOPENBOX'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
session_file="$HOME/.config/termux-stack/session.env"
driver_file="$HOME/.config/termux-stack/driver.env"
if [ -f "$session_file" ]; then
  # shellcheck source=/dev/null
  . "$session_file"
fi
if [ -f "$driver_file" ]; then
  # shellcheck source=/dev/null
  . "$driver_file"
fi
if command -v openbox-session >/dev/null 2>&1 && command -v python >/dev/null 2>&1; then
  if python - <<'PY' >/dev/null 2>&1
from xdg import BaseDirectory  # noqa: F401
PY
  then
    exec openbox-session
  fi
fi
exec openbox --startup "$HOME/.config/openbox/autostart" --sm-disable
LAUNCHOPENBOX

  chmod 700 "$OPENBOX_RUNTIME_DIR/openbox-session.sh"
}

mkdir -p "$HOME/.cache/termux-stack"
mkdir -p "$OPENBOX_RUNTIME_DIR"
stack_write_openbox_env_files "$profile"
stack_write_openbox_user_config "$profile"
stack_load_session_env
stack_cleanup_gui_state 0 0

stack_line "$(stack_progress_bar 1 6) (1/6) Aplicando perfil ${profile}"
set-x11-resolution "$resolution_profile"
if [ "$profile" = 'openbox-vulkan-exp' ] && [ ! -f "$TERMUX_VULKAN_WRAPPER_ICD" ]; then
  printf 'Aviso: wrapper Vulkan não encontrado em %s; usando somente angle-vulkan experimental.\n' "$TERMUX_VULKAN_WRAPPER_ICD"
fi

stack_line "$(stack_progress_bar 2 6) (2/6) Garantindo termux-x11"
start-termux-x11

stack_line "$(stack_progress_bar 3 6) (3/6) Validando display :1"
if ! stack_wait_for_x11_display "$DISPLAY" 12; then
  printf 'Abra o app Termux:X11 e repita a operação.\n' >&2
  exit 1
fi

stack_line "$(stack_progress_bar 4 6) (4/6) Iniciando trilha 3D ${driver_profile}"
start-virgl "$virgl_mode"

stack_line "$(stack_progress_bar 5 6) (5/6) Iniciando sessão Openbox"
if [ "$dbus_mode" = 'on' ]; then
  start_session_dbus
fi
write_openbox_runtime_launchers
if command -v setsid >/dev/null 2>&1 && command -v nohup >/dev/null 2>&1; then
  nohup setsid "$OPENBOX_RUNTIME_DIR/openbox-session.sh" >"$OPENBOX_LOG" 2>&1 < /dev/null &
elif command -v setsid >/dev/null 2>&1; then
  setsid "$OPENBOX_RUNTIME_DIR/openbox-session.sh" >"$OPENBOX_LOG" 2>&1 < /dev/null &
elif command -v nohup >/dev/null 2>&1; then
  nohup "$OPENBOX_RUNTIME_DIR/openbox-session.sh" >"$OPENBOX_LOG" 2>&1 < /dev/null &
else
  "$OPENBOX_RUNTIME_DIR/openbox-session.sh" >"$OPENBOX_LOG" 2>&1 &
fi
disown || true

stack_line "$(stack_progress_bar 6 6) (6/6) Validando sessão gráfica"
for _attempt in 1 2 3 4 5 6 7 8; do
  if stack_openbox_running; then
    break
  fi
  sleep 1
done

if ! stack_openbox_running; then
  printf 'Falha: o processo openbox não permaneceu ativo.\n' >&2
  if [ -s "$OPENBOX_LOG" ]; then
    sed -n '1,120p' "$OPENBOX_LOG" >&2
  fi
  exit 1
fi

for _attempt in 1 2 3 4 5; do
  if stack_openbox_running; then
    printf 'OPENBOX_PROFILE_OK PROFILE=%s DRIVER=%s DBUS=%s\n' "$profile" "$driver_profile" "$dbus_mode"
    "$HOME/bin/termux-stack-status" --brief || true
    exit 0
  fi
  sleep 1
done

printf 'Falha: a sessão Openbox/X11 não permaneceu ativa.\n' >&2
if [ -s "$OPENBOX_LOG" ]; then
  sed -n '1,120p' "$OPENBOX_LOG" >&2
fi
exit 1
EOF

cat > "$HOME/bin/stop-openbox-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
  stack_cleanup_gui_state 0 1
else
  pkill -f '^xterm( |$)' >/dev/null 2>&1 || true
  pkill -f '^aterm( |$)' >/dev/null 2>&1 || true
  pkill -f '^openbox( |$)|openbox-session' >/dev/null 2>&1 || true
  pkill -f '^dbus-daemon .*--session' >/dev/null 2>&1 || true
  pkill -f 'termux-x11 .*:1|termux-x11 :1' >/dev/null 2>&1 || true
  rm -f "$HOME/.cache/termux-stack/dbus/"*.bus >/dev/null 2>&1 || true
fi

printf 'Sessão Openbox/X11 encerrada.\n'
EOF

  cat > "$HOME/bin/start-openbox-stable" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec "$HOME/bin/start-openbox-x11" --profile openbox-stable "$@"
EOF

  cat > "$HOME/bin/start-openbox" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec "$HOME/bin/start-openbox-maxperf" "$@"
EOF

  cat > "$HOME/bin/start-openbox-maxperf" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec "$HOME/bin/start-openbox-x11" --profile openbox-maxperf "$@"
EOF

  cat > "$HOME/bin/start-openbox-compat" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec "$HOME/bin/start-openbox-x11" --profile openbox-compat "$@"
EOF

  cat > "$HOME/bin/start-openbox-vulkan-exp" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec "$HOME/bin/start-openbox-x11" --profile openbox-vulkan-exp "$@"
EOF

  cat > "$HOME/bin/start-xfce-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
fi

export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
export DESKTOP_SESSION="xfce"
export XDG_CURRENT_DESKTOP="XFCE"
XFCE_LOG="${HOME}/.cache/termux-stack/start-xfce-x11.log"
wm="${TERMUX_X11_WM:-xfwm4}"
backend="${TERMUX_X11_DESKTOP_BACKEND:-termux}"

DISTRO_ALIAS="${TERMUX_X11_DISTRO_ALIAS:-debian-trixie-gui}"
DISTRO_USER="${TERMUX_X11_DISTRO_USER:-igor}"
DEBIAN_LAUNCHER="/home/${DISTRO_USER}/bin/start-xfce-termux-x11"
export TERMUX_X11_DISTRO_ALIAS="$DISTRO_ALIAS"
export TERMUX_X11_DISTRO_USER="$DISTRO_USER"

usage() {
  printf 'Uso: %s [--wm xfwm4|openbox] [--backend termux|debian]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --wm)
      shift
      wm="${1:-}"
      shift || true
      ;;
    xfwm4|openbox)
      wm="$1"
      shift
      ;;
    --backend)
      shift
      backend="${1:-}"
      shift || true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Argumento não suportado para start-xfce-x11: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$wm" in
  xfwm4|openbox)
    ;;
  *)
    printf 'WM inválido para start-xfce-x11: %s\n' "$wm" >&2
    printf 'Use: xfwm4 ou openbox.\n' >&2
    exit 1
    ;;
esac

case "$backend" in
  termux|debian)
    ;;
  *)
    printf 'Backend inválido para start-xfce-x11: %s\n' "$backend" >&2
    printf 'Use: termux ou debian.\n' >&2
    exit 1
    ;;
esac

export TERMUX_X11_WM="$wm"
export TERMUX_X11_DESKTOP_BACKEND="$backend"

xfce_success_message() {
  printf 'Sessão XFCE iniciada em %s com WM=%s.\n' "$1" "$wm"
}

xfce_schedule_wm_replace() {
  if [ "$wm" != 'openbox' ]; then
    return 0
  fi

  (
    sleep 5
    DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" openbox --replace >/dev/null 2>&1
  ) >/dev/null 2>&1 &
  disown || true
}

mkdir -p "$HOME/.cache/termux-stack"

if [ "$backend" = 'debian' ] \
  && command -v proot-distro >/dev/null 2>&1 \
  && [ -d "${PREFIX}/var/lib/proot-distro/installed-rootfs/${DISTRO_ALIAS}" ] \
  && proot-distro login --no-arch-warning --user "$DISTRO_USER" --shared-tmp "$DISTRO_ALIAS" -- test -x "$DEBIAN_LAUNCHER" >/dev/null 2>&1; then

  stack_line "$(stack_progress_bar 1 4) (1/4) Garantindo termux-x11"
  start-termux-x11

  stack_line "$(stack_progress_bar 2 4) (2/4) Validando display :1"
  if ! stack_wait_for_x11_display "$DISPLAY" 12; then
    printf 'Abra o app Termux:X11 e repita a operação.\n' >&2
    exit 1
  fi

  stack_line "$(stack_progress_bar 3 4) (3/4) Iniciando XFCE via Debian (${DISTRO_ALIAS}/${DISTRO_USER})"
  proot-distro login --no-arch-warning --user "$DISTRO_USER" --shared-tmp "$DISTRO_ALIAS" -- env TERMUX_X11_WM="$wm" /bin/bash "$DEBIAN_LAUNCHER" >"$XFCE_LOG" 2>&1 &
  disown || true

  stack_line "$(stack_progress_bar 4 4) (4/4) Validando sessão Debian"
  for _attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if stack_xfce_ready_in_distro; then
      xfce_success_message "$DISPLAY"
      "$HOME/bin/termux-stack-status" --brief || true
      exit 0
    fi
    sleep 1
  done

  printf 'Falha: a sessão XFCE via Debian não permaneceu ativa.\n' >&2
  if [ -s "$XFCE_LOG" ]; then
    sed -n '1,160p' "$XFCE_LOG" >&2
  fi
  exit 1
fi

if [ "$backend" = 'debian' ]; then
  printf 'Backend Debian solicitado, mas o launcher XFCE do proot não está pronto.\n' >&2
  printf 'Reinstale ou reprovisione a stack Debian antes de repetir a operação.\n' >&2
  exit 1
fi

if ! command -v xfce4-session >/dev/null 2>&1; then
  printf 'xfce4-session não encontrado. Reinstale o payload ou instale os pacotes XFCE no Termux.\n' >&2
  exit 1
fi

if [ "$wm" = 'xfwm4' ] && ! command -v xfwm4 >/dev/null 2>&1; then
  printf 'xfwm4 não encontrado. Reinstale o payload ou instale os pacotes XFCE no Termux.\n' >&2
  exit 1
fi

if [ "$wm" = 'openbox' ] && ! command -v openbox >/dev/null 2>&1; then
  printf 'openbox não encontrado. Reinstale o payload ou instale openbox no Termux.\n' >&2
  exit 1
fi

if ! command -v xterm >/dev/null 2>&1; then
  printf 'xterm não encontrado. Reinstale o payload ou instale xterm no Termux.\n' >&2
  exit 1
fi

mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"

cat > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<'XFWMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="100"/>
    <property name="move_opacity" type="int" value="100"/>
    <property name="resize_opacity" type="int" value="100"/>
    <property name="shadow_opacity" type="int" value="0"/>
    <property name="titleless_maximize_active" type="bool" value="false"/>
  </property>
</channel>
XFWMEOF

cat > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" <<'XFDESKEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty"/>
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="0"/>
    <property name="file-icons" type="empty">
      <property name="show-home" type="bool" value="false"/>
      <property name="show-filesystem" type="bool" value="false"/>
      <property name="show-trash" type="bool" value="false"/>
      <property name="show-removable" type="bool" value="false"/>
    </property>
  </property>
</channel>
XFDESKEOF

cat > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml" <<'XFPANELEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="empty">
    <property name="dark-mode" type="bool" value="false"/>
  </property>
</channel>
XFPANELEOF

cat > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" <<'XFSESSIONEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="SaveOnExit" type="bool" value="false"/>
  </property>
  <property name="startup" type="empty">
    <property name="ssh-agent" type="empty">
      <property name="enabled" type="bool" value="false"/>
    </property>
    <property name="gpg-agent" type="empty">
      <property name="enabled" type="bool" value="false"/>
    </property>
  </property>
</channel>
XFSESSIONEOF

cat > "$HOME/.config/xfce4/xinitrc" <<'XINITEOF'
#!/data/data/com.termux/files/usr/bin/bash
exec xfce4-session --disable-tcp
XINITEOF
chmod +x "$HOME/.config/xfce4/xinitrc"

stack_cleanup_gui_state 0 0

stack_line "$(stack_progress_bar 1 4) (1/4) Garantindo termux-x11"
start-termux-x11

stack_line "$(stack_progress_bar 2 4) (2/4) Validando display :1"
if ! stack_wait_for_x11_display "$DISPLAY" 12; then
  printf 'Abra o app Termux:X11 e repita a operação.\n' >&2
  exit 1
fi

stack_line "$(stack_progress_bar 3 4) (3/4) Iniciando XFCE no próprio Termux"
dbus-launch --exit-with-session sh -lc 'xfce4-session --disable-tcp' >"$XFCE_LOG" 2>&1 &
disown || true
xfce_schedule_wm_replace
(
  sleep 4
  DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" xfconf-query -c xfce4-session -p /general/SaveOnExit -n -t bool -s false >/dev/null 2>&1 || true
  DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" xfconf-query -c xfce4-session -p /startup/ssh-agent/enabled -n -t bool -s false >/dev/null 2>&1 || true
  DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" xfconf-query -c xfce4-session -p /startup/gpg-agent/enabled -n -t bool -s false >/dev/null 2>&1 || true
  pkill -f '^xfdesktop( |$)|^Thunar( |$)|^thunar( |$)|^xfsettingsd( |$)' >/dev/null 2>&1 || true
  rm -rf "$HOME/.cache/sessions" >/dev/null 2>&1 || true
) >/dev/null 2>&1 &
disown || true

stack_line "$(stack_progress_bar 4 4) (4/4) Validando sessão gráfica"
for _attempt in 1 2 3 4 5 6; do
  if stack_xfce_ready; then
    xfce_success_message "$DISPLAY"
    "$HOME/bin/termux-stack-status" --brief || true
    exit 0
  fi
  sleep 1
done

printf 'Falha: a sessão XFCE/X11 não permaneceu ativa.\n' >&2
if [ -s "$XFCE_LOG" ]; then
  sed -n '1,160p' "$XFCE_LOG" >&2
fi
exit 1
EOF

  cat > "$HOME/bin/start-xfce-x11-detached" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

wm="${1:-xfwm4}"

case "$wm" in
  xfwm4|openbox)
    ;;
  *)
    printf 'WM inválido para start-xfce-x11-detached: %s\n' "$wm" >&2
    printf 'Use: xfwm4 ou openbox.\n' >&2
    exit 1
    ;;
esac

mkdir -p "$HOME/.cache/termux-stack"
launch_log="$HOME/.cache/termux-stack/start-xfce-x11-detached.log"

if command -v am >/dev/null 2>&1; then
  am start -n com.termux.x11/.MainActivity >/dev/null 2>&1 || true
fi

nohup bash -lc "start-xfce-x11 --wm ${wm}" >"$launch_log" 2>&1 < /dev/null &
disown || true

printf 'XFCE_DETACHED_OK WM=%s\n' "$wm"
printf 'XFCE_DETACHED_LOG=%s\n' "$launch_log"
EOF
  chmod +x "$HOME/bin/start-xfce-x11-detached"

cat > "$HOME/bin/stop-xfce-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
  stack_cleanup_gui_state 0 1
else
  pkill -f '^xfce4-session( |$)|^xfwm4( |$)|^xfdesktop( |$)|^xfce4-panel( |$)|^xfce4-terminal( |$)|^xfsettingsd( |$)|^openbox( |$)|^Thunar( |$)|^thunar( |$)' >/dev/null 2>&1 || true
  pkill -f '^dbus-daemon .*--session' >/dev/null 2>&1 || true
  pkill -f 'termux-x11 .*:1|termux-x11 :1' >/dev/null 2>&1 || true
fi

printf 'Sessão XFCE/X11 encerrada.\n'
EOF

  cat > "$HOME/bin/run-in-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
fi

export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
stack_load_session_env
stack_reset_driver_env
stack_load_driver_env

mode="app"

case "${1:-}" in
  --app)
    shift
    ;;
  --xterm)
    mode="xterm"
    shift
    ;;
esac

if [ "$#" -eq 0 ]; then
  printf 'Uso: run-in-x11 [--app|--xterm] comando [args...]\n' >&2
  exit 1
fi

if ! "$HOME/bin/termux-stack-status" --brief | grep -Eq 'DESKTOP=(xfce|xfce-debian|xfce-termux|openbox)'; then
  printf 'Nenhuma sessão X11 ativa foi detectada em :1. Inicie com start-openbox-x11 ou start-xfce-x11 antes de usar run-in-x11.\n' >&2
  exit 1
fi

if [ "$mode" = "xterm" ]; then
  if ! command -v xterm >/dev/null 2>&1; then
    printf 'xterm não encontrado. Reinstale o payload ou instale xterm no Termux.\n' >&2
    exit 1
  fi

  profile_label="${TERMUX_OPENBOX_PROFILE:-$(stack_openbox_current_profile 2>/dev/null || printf 'openbox-maxperf')}"
  xterm -hold -e "$@" >/dev/null 2>&1 &
  disown || true
  printf 'Comando iniciado em xterm no X11 (%s) com perfil %s.\n' "$DISPLAY" "$profile_label"
  exit 0
fi

profile_label="${TERMUX_OPENBOX_PROFILE:-$(stack_openbox_current_profile 2>/dev/null || printf 'openbox-maxperf')}"
"$@" >/dev/null 2>&1 &
disown || true
printf 'Aplicação iniciada no X11 (%s) com perfil %s.\n' "$DISPLAY" "$profile_label"
EOF

  cat > "$HOME/bin/run-glmark2-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_LIB="${HOME}/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_LIB" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_LIB"
fi

export DISPLAY="${TERMUX_STACK_DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/data/data/com.termux/files/usr/tmp}}"
stack_load_session_env
stack_reset_driver_env
stack_load_driver_env

if ! pgrep -f 'virgl_test_server_android' >/dev/null 2>&1; then
  printf 'virgl_test_server_android não está em execução. Rode start-virgl antes do benchmark.\n' >&2
  exit 1
fi

if ! "$HOME/bin/termux-stack-status" --brief | grep -Eq 'DESKTOP=(xfce|xfce-debian|xfce-termux|openbox)'; then
  printf 'Nenhuma sessão X11 ativa foi detectada em :1. Inicie um desktop antes do benchmark.\n' >&2
  exit 1
fi

if command -v glmark2-es2 >/dev/null 2>&1; then
  benchmark_bin='glmark2-es2'
elif command -v glmark2 >/dev/null 2>&1; then
  benchmark_bin='glmark2'
else
  printf 'glmark2 não encontrado. Instale o pacote glmark2 no Termux.\n' >&2
  exit 1
fi

printf 'Benchmark=%s DISPLAY=%s DRIVER_PROFILE=%s VIRGL_MODE=%s\n' \
  "$benchmark_bin" "$DISPLAY" "${TERMUX_DRIVER_PROFILE:-$(stack_current_driver_profile 2>/dev/null || printf 'virgl-plain')}" "${TERMUX_VIRGL_MODE:-$(stack_virgl_mode)}"
env DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$benchmark_bin" "$@"
EOF

  cat > "$HOME/bin/start-maxperf-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

desktop_profile="${1:-openbox}"

case "$desktop_profile" in
  openbox)
    desktop_command=(start-openbox-x11 --profile openbox-maxperf)
    ;;
  xfce)
    set-x11-resolution performance
    start-virgl plain
    desktop_command=(start-xfce-x11 --wm openbox)
    ;;
  *)
    printf 'Uso: %s [openbox|xfce]\n' "$0" >&2
    exit 1
    ;;
esac

stop-xfce-x11 >/dev/null 2>&1 || true
stop-openbox-x11 >/dev/null 2>&1 || true
stop-virgl >/dev/null 2>&1 || true

"${desktop_command[@]}"

printf 'Perfil 3D de máxima performance aplicado (%s).\n' "$desktop_profile"
"$HOME/bin/termux-stack-status" --brief || true
EOF

  cat > "$HOME/bin/set-x11-resolution" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

COMMON_FILE="$HOME/.config/termux-stack/termux-stack-common.sh"
if [ -f "$COMMON_FILE" ]; then
  # shellcheck source=/dev/null
  source "$COMMON_FILE"
fi

profile="${1:-balanced}"
default_resolution="${TERMUX_X11_DEFAULT_RESOLUTION:-1920x1080}"
balanced_resolution="${TERMUX_X11_BALANCED_RESOLUTION:-$default_resolution}"
performance_resolution="${TERMUX_X11_PERFORMANCE_RESOLUTION:-1280x720}"

if ! command -v termux-x11-preference >/dev/null 2>&1; then
  printf 'termux-x11-preference não encontrado. Reinstale o payload ou instale termux-x11-nightly no Termux.\n' >&2
  exit 1
fi

case "$profile" in
  performance)
    mode="exact"
    resolution="$performance_resolution"
    ;;
  balanced)
    mode="exact"
    resolution="$balanced_resolution"
    ;;
  native)
    mode="native"
    resolution=""
    ;;
  custom)
    if [ "$#" -lt 2 ]; then
      printf 'Uso: set-x11-resolution custom LARGURAxALTURA\n' >&2
      exit 1
    fi
    mode="exact"
    resolution="$2"
    ;;
  show)
    termux-x11-preference list | grep -E 'displayResolutionMode|displayResolutionExact|displayResolutionCustom|displayScale'
    exit 0
    ;;
  *)
    printf 'Perfil inválido: %s\n' "$profile" >&2
    printf 'Use: performance, balanced, native, custom LARGURAxALTURA ou show.\n' >&2
    exit 1
    ;;
esac

if [ "$mode" = "native" ]; then
  termux-x11-preference displayResolutionMode:native
  printf 'Resolução do Termux:X11 ajustada para nativa.\n'
  termux-x11-preference list | grep -E 'displayResolutionMode|displayResolutionExact|displayResolutionCustom|displayScale' || true
  exit 0
fi

if ! printf '%s' "$resolution" | grep -Eq '^[0-9]+x[0-9]+$'; then
  printf 'Formato de resolução inválido: %s\n' "$resolution" >&2
  exit 1
fi

termux-x11-preference displayResolutionMode:"$mode" displayResolutionExact:"$resolution"
printf 'Resolução do Termux:X11 ajustada para %s (%s).\n' "$resolution" "$profile"
termux-x11-preference list | grep -E 'displayResolutionMode|displayResolutionExact|displayResolutionCustom|displayScale' || true
EOF

  chmod +x \
    "$HOME/bin/stop-termux-x11" \
    "$HOME/bin/termux-stack-status" \
    "$HOME/bin/start-termux-x11" \
    "$HOME/bin/start-virgl" \
    "$HOME/bin/stop-virgl" \
    "$HOME/bin/check-gpu-termux" \
    "$HOME/bin/start-openbox-x11" \
    "$HOME/bin/start-openbox" \
    "$HOME/bin/start-openbox-stable" \
    "$HOME/bin/start-openbox-maxperf" \
    "$HOME/bin/start-openbox-compat" \
    "$HOME/bin/start-openbox-vulkan-exp" \
    "$HOME/bin/stop-openbox-x11" \
    "$HOME/bin/start-xfce-x11" \
    "$HOME/bin/start-maxperf-x11" \
    "$HOME/bin/stop-xfce-x11" \
    "$HOME/bin/run-in-x11" \
    "$HOME/bin/run-glmark2-x11" \
    "$HOME/bin/set-x11-resolution"

  if [ -f /data/local/tmp/termux_workspace_menu.sh ]; then
    install -m 755 /data/local/tmp/termux_workspace_menu.sh "$HOME/bin/termux-workspace-menu"
  else
    log_line 'Menu do workspace ausente em /data/local/tmp/termux_workspace_menu.sh; helper termux-workspace-menu nao instalado.'
  fi
}

apply_default_x11_preferences() {
  local pref_output=""
  local pref_status=0
  local filtered_output=""
  local -a pref_args=()

  if ! command -v termux-x11-preference >/dev/null 2>&1; then
    log_line 'termux-x11-preference ainda indisponível; pulando preferências padrão do X11.'
    return 0
  fi

  if ! printf '%s' "$DEFAULT_X11_RESOLUTION" | grep -Eq '^[0-9]+x[0-9]+$'; then
    fail \
      'validação da resolução padrão do Termux:X11' \
      "Formato inválido para TERMUX_X11_DEFAULT_RESOLUTION: ${DEFAULT_X11_RESOLUTION}" \
      'A preferência de resolução padrão do X11 não pode ser aplicada.' \
      'Definir TERMUX_X11_DEFAULT_RESOLUTION como LARGURAxALTURA, por exemplo 1920x1080.'
  fi

  pref_args=(
    "displayResolutionMode:exact"
    "displayResolutionExact:${DEFAULT_X11_RESOLUTION}"
    "showAdditionalKbd:${TERMUX_X11_SHOW_ADDITIONAL_KBD_DEFAULT}"
    "additionalKbdVisible:${TERMUX_X11_ADDITIONAL_KBD_VISIBLE_DEFAULT}"
    "swipeDownAction:${TERMUX_X11_SWIPE_DOWN_ACTION_DEFAULT}"
  )

  set +e
  pref_output="$(termux-x11-preference "${pref_args[@]}" 2>&1)"
  pref_status=$?
  set -e
  filtered_output="$(printf '%s\n' "$pref_output" | grep -Ev '^Could not open module param file .*/large_page_conf$' || true)"

  if [ "$pref_status" -ne 0 ]; then
    if printf '%s\n' "$filtered_output" | grep -Fq 'Failed to obtain response from app.'; then
      log_line 'Termux:X11 ainda não estava ativo; as preferências padrão serão reaplicadas quando o app abrir.'
      return 0
    fi
    fail \
      'termux-x11-preference displayResolutionMode:exact ... showAdditionalKbd:false ...' \
      "${filtered_output:-$pref_output}" \
      'As preferências padrão do X11 não puderam ser gravadas.' \
      'Abrir o app Termux:X11, validar a instalação do termux-x11-nightly e repetir a operação.'
  fi

  if [ -n "$filtered_output" ] && ! printf '%s\n' "$filtered_output" | grep -Fq 'Failed to obtain response from app.'; then
    printf '%s\n' "$filtered_output" >> "$SCRIPT_LOG"
  fi
  if [ -n "$filtered_output" ] && printf '%s\n' "$filtered_output" | grep -Fq 'Failed to obtain response from app.'; then
    log_line 'Termux:X11 ainda não estava aberto; as preferências gravadas serão refletidas quando o app iniciar.'
  fi

  log_line "Preferências padrão do Termux:X11 fixadas: resolução ${DEFAULT_X11_RESOLUTION} (${DEFAULT_X11_PROFILE}) e barra extra oculta."
}

print_summary() {
  log_blank_line
  log_line 'Instalação base concluída no Termux.'
  log_line "Perfil padrão do X11: ${DEFAULT_X11_PROFILE}"
  log_line "Resolução padrão do X11: ${DEFAULT_X11_RESOLUTION}"
  log_line "Perfil diário Openbox: ${TERMUX_OPENBOX_DEFAULT_PROFILE:-openbox-maxperf}"
  log_line "Perfil performance definido para: ${TERMUX_X11_PERFORMANCE_RESOLUTION}"
  log_line "Log geral: ${SCRIPT_LOG}"
  printf 'Helpers instalados:\n'
  printf -- '- %s/bin/stop-termux-x11\n' "$HOME"
  printf -- '- %s/bin/termux-stack-status\n' "$HOME"
  printf -- '- %s/bin/start-termux-x11\n' "$HOME"
  printf -- '- %s/bin/start-virgl\n' "$HOME"
  printf -- '- %s/bin/stop-virgl\n' "$HOME"
  printf -- '- %s/bin/start-openbox-x11\n' "$HOME"
  printf -- '- %s/bin/start-openbox\n' "$HOME"
  printf -- '- %s/bin/start-openbox-stable\n' "$HOME"
  printf -- '- %s/bin/start-openbox-maxperf\n' "$HOME"
  printf -- '- %s/bin/start-openbox-compat\n' "$HOME"
  printf -- '- %s/bin/start-openbox-vulkan-exp\n' "$HOME"
  printf -- '- %s/bin/openbox-terminal\n' "$HOME"
  printf -- '- %s/bin/openbox-launcher\n' "$HOME"
  printf -- '- %s/bin/openbox-file-manager\n' "$HOME"
  printf -- '- %s/bin/openbox-settings\n' "$HOME"
  printf -- '- %s/bin/openbox-reconfigure\n' "$HOME"
  printf -- '- %s/bin/start-xfce-x11\n' "$HOME"
  printf -- '- %s/bin/start-xfce-x11-detached\n' "$HOME"
  printf -- '- %s/bin/start-maxperf-x11\n' "$HOME"
  printf -- '- %s/bin/check-gpu-termux\n' "$HOME"
  printf -- '- %s/bin/set-x11-resolution\n' "$HOME"
  if [ -x "$HOME/bin/termux-workspace-menu" ]; then
    printf -- '- %s/bin/termux-workspace-menu\n' "$HOME"
  fi
  printf 'Estado atual:\n'
  "$HOME/bin/termux-stack-status" || true
  printf 'Reinicie Termux e Termux:X11 antes de validar o ambiente.\n'
}

ensure_termux_context

log_line 'Preparando instalação da stack Termux.'
run_step 'Preparando shell do Termux' prepare_termux_shell
run_step 'Limpando resíduos gráficos da instalação anterior' cleanup_existing_termux_gui_state
run_step 'Fixando repositório principal do Termux' configure_termux_repos
run_step 'Atualizando índice de pacotes pkg' pkg update -y
run_step 'Atualizando pacotes instalados do Termux' pkg upgrade -y "${PKG_NONINTERACTIVE_OPTS[@]}"
run_step 'Instalando repositório X11' pkg install -y "${PKG_NONINTERACTIVE_OPTS[@]}" x11-repo
run_step 'Fixando repositório X11 do Termux' configure_termux_repos
run_step 'Atualizando índice de pacotes após habilitar o repositório X11' pkg update -y
run_step \
  'Instalando pacotes base do stack X11/XFCE/virgl' \
  pkg install -y "${PKG_NONINTERACTIVE_OPTS[@]}" termux-x11-nightly termux-api virglrenderer-android mesa-demos pulseaudio dbus openbox aterm xterm xfce4-session xfce4-panel xfce4-terminal xfdesktop xfwm4 xfce4-settings thunar tint2 rofi dunst obconf-qt lxappearance xorg-xsetroot glmark2
run_step 'Normalizando wrapper termux-x11' normalize_termux_x11_wrapper
run_step 'Gerando helpers do projeto no Termux' install_termux_helpers
run_step 'Aplicando preferências padrão do Termux:X11' apply_default_x11_preferences
print_summary
