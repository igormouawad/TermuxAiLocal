#!/usr/bin/env bash

set -euo pipefail

EXPECTED_USER=""
ENV_FILE="${HOME}/.config/termux-stack/env.sh"
SCRIPT_LOG="/tmp/configure-debian-user-$(date +%Y%m%d-%H%M%S).log"
TOTAL_STEPS=10
CURRENT_STEP=0
LAST_STEP_LOG=""

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

progress_percent() {
  local current="$1"
  local total="$2"

  if [ "$total" -le 0 ] 2>/dev/null; then
    printf '100\n'
    return 0
  fi

  printf '%s\n' $((current * 100 / total))
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
  local percent

  CURRENT_STEP=$((CURRENT_STEP + 1))
  slug="$(safe_slug "$label")"
  LAST_STEP_LOG="/tmp/user-step-$(printf '%02d' "$CURRENT_STEP")-${slug}.log"
  : > "$LAST_STEP_LOG"
  percent="$(progress_percent "$CURRENT_STEP" "$TOTAL_STEPS")"

  printf '\n[DEBIAN-USER] %s (%s/%s %s%%) %s\n' "$(progress_bar "$CURRENT_STEP" "$TOTAL_STEPS")" "$CURRENT_STEP" "$TOTAL_STEPS" "$percent" "$label" | tee -a "$SCRIPT_LOG"
  printf '[DEBIAN-USER:CMD] %s\n' "$(command_text "$@")" | tee -a "$SCRIPT_LOG"

  set +e
  "$@" 2>&1 | tee "$LAST_STEP_LOG" | tee -a "$SCRIPT_LOG"
  status=${PIPESTATUS[0]}
  set -e

  if [ "$status" -ne 0 ]; then
    fail \
      "$(command_text "$@")" \
      "Saída completa registrada em ${LAST_STEP_LOG}." \
      'A configuração do ambiente do usuário Debian foi interrompida.' \
      'Corrigir o erro retornado e repetir a configuração dentro do proot.'
  fi

  printf '[DEBIAN-USER:OK %s%%] Etapa concluída: %s\n' "$percent" "$label" | tee -a "$SCRIPT_LOG"
}

append_once() {
  local file_path="$1"
  local line_text="$2"

  if ! grep -Fqx "$line_text" "$file_path" 2>/dev/null; then
    printf '%s\n' "$line_text" >> "$file_path"
  fi
}

prepare_runtime_dirs() {
  mkdir -p \
    "$HOME/bin" \
    "$HOME/.config/termux-stack" \
    "$HOME/.config/openbox" \
    "$HOME/.config/tint2" \
    "$HOME/Desktop" \
    "$HOME/Documents" \
    "$HOME/Downloads" \
    "$HOME/Projects" \
    "/tmp/runtime-${EXPECTED_USER}"
  chmod 700 "/tmp/runtime-${EXPECTED_USER}"
}

write_env_file() {
  cat > "$ENV_FILE" <<EOF
#!/usr/bin/env bash

export HOME="/home/${EXPECTED_USER}"
export USER="${EXPECTED_USER}"
export LOGNAME="${EXPECTED_USER}"
export SHELL="/bin/bash"
export TERMUX_STACK_DISPLAY="\${TERMUX_STACK_DISPLAY:-:1}"
export DISPLAY="\${TERMUX_STACK_DISPLAY}"
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/tmp/runtime-${EXPECTED_USER}}"
export XDG_SESSION_TYPE="x11"
export XDG_CURRENT_DESKTOP="\${XDG_CURRENT_DESKTOP:-Openbox}"
export DESKTOP_SESSION="\${DESKTOP_SESSION:-openbox}"
export TERM="\${TERM:-xterm-256color}"
export LANG="\${LANG:-en_US.UTF-8}"
export LC_ALL="\${LC_ALL:-en_US.UTF-8}"
export PATH="$HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TERMUX_X11_WM="\${TERMUX_X11_WM:-openbox}"
export TERMUX_GUI_RENDERER="\${TERMUX_GUI_RENDERER:-hardware}"
export TERMUX_GUI_PULSE_SERVER="\${TERMUX_GUI_PULSE_SERVER:-\${PULSE_SERVER:-127.0.0.1}}"
export PULSE_SERVER="\${PULSE_SERVER:-\$TERMUX_GUI_PULSE_SERVER}"
export GALLIUM_DRIVER="\${GALLIUM_DRIVER:-virpipe}"
export TERMUX_X11_DISTRO_USER="\${TERMUX_X11_DISTRO_USER:-${EXPECTED_USER}}"
export TERMUX_HOST_HOME="\${TERMUX_HOST_HOME:-/data/data/com.termux/files/home}"
export TERMUX_HOST_APPLICATIONS_DIR="\${TERMUX_HOST_APPLICATIONS_DIR:-\$TERMUX_HOST_HOME/.local/share/applications}"
export TERMUX_HOST_DEBIAN_WRAPPERS_DIR="\${TERMUX_HOST_DEBIAN_WRAPPERS_DIR:-\$TERMUX_HOST_HOME/bin/debian-apps}"
export GDK_BACKEND="\${GDK_BACKEND:-x11}"
export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-xcb}"
export SDL_VIDEODRIVER="\${SDL_VIDEODRIVER:-x11}"
unset LIBGL_ALWAYS_SOFTWARE
unset WAYLAND_DISPLAY
EOF
  chmod 644 "$ENV_FILE"
}

write_gui_launchers() {
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

  cat > "$HOME/bin/start-xfce-termux-x11" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="${HOME}/.config/termux-stack/env.sh"
wm="${TERMUX_X11_WM:-xfwm4}"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

usage() {
  printf 'Uso: %s [--wm xfwm4|openbox]\n' "$0"
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
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Argumento não suportado para start-xfce-termux-x11: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$wm" in
  xfwm4|openbox)
    ;;
  *)
    printf 'WM inválido para start-xfce-termux-x11: %s\n' "$wm" >&2
    printf 'Use: xfwm4 ou openbox.\n' >&2
    exit 1
    ;;
esac

export TERMUX_X11_WM="$wm"

cd "$HOME"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
mkdir -p "$HOME/.cache"
rm -rf "$HOME/.cache/sessions" >/dev/null 2>&1 || true

if [ "$wm" = 'xfwm4' ] && ! command -v xfwm4 >/dev/null 2>&1; then
  printf 'xfwm4 não encontrado dentro do Debian.\n' >&2
  exit 1
fi

if [ "$wm" = 'openbox' ] && ! command -v openbox >/dev/null 2>&1; then
  printf 'openbox não encontrado dentro do Debian.\n' >&2
  exit 1
fi

pkill -f '^xfce4-session( |$)|^xfwm4( |$)|^openbox( |$)|^xfce4-panel( |$)|^xfsettingsd( |$)|^xfdesktop( |$)|^Thunar( |$)|^thunar( |$)' >/dev/null 2>&1 || true

xfce_launch_message() {
  printf 'Iniciando sessão XFCE em %s com WM=%s.\n' "$DISPLAY" "$wm"
}

(
  sleep 4
  xfconf-query -c xfce4-session -p /general/SaveOnExit -n -t bool -s false >/dev/null 2>&1 || true
  xfconf-query -c xfce4-session -p /startup/ssh-agent/enabled -n -t bool -s false >/dev/null 2>&1 || true
  xfconf-query -c xfce4-session -p /startup/gpg-agent/enabled -n -t bool -s false >/dev/null 2>&1 || true
  pkill -f '^xfdesktop( |$)|^Thunar( |$)|^thunar( |$)|^xfsettingsd( |$)' >/dev/null 2>&1 || true
  rm -rf "$HOME/.cache/sessions" >/dev/null 2>&1 || true
) >/dev/null 2>&1 &
disown || true

if [ "$wm" = 'openbox' ]; then
  (
    sleep 5
    DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" openbox --replace >/dev/null 2>&1
  ) >/dev/null 2>&1 &
  disown || true
fi

xfce_launch_message
exec dbus-launch --exit-with-session sh -lc 'xfce4-session --disable-tcp'
EOF
  chmod 755 "$HOME/bin/start-xfce-termux-x11"

  cat > "$HOME/bin/run-gui-termux" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="${HOME}/.config/termux-stack/env.sh"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

if [ "$#" -eq 0 ]; then
  printf 'Uso: %s comando [args...]\n' "$0" >&2
  exit 1
fi

renderer="${TERMUX_GUI_RENDERER:-hardware}"
pulse_server="${TERMUX_GUI_PULSE_SERVER:-${PULSE_SERVER:-}}"

case "$renderer" in
  software)
    export LIBGL_ALWAYS_SOFTWARE=1
    unset GALLIUM_DRIVER || true
    ;;
  hardware|virgl)
    unset LIBGL_ALWAYS_SOFTWARE || true
    export GALLIUM_DRIVER=virpipe
    ;;
  *)
    printf 'Renderer inválido para o launcher GUI: %s\n' "$renderer" >&2
    printf 'Use hardware, software ou virgl.\n' >&2
    exit 1
    ;;
esac

if [ -n "$pulse_server" ]; then
  export PULSE_SERVER="$pulse_server"
fi

exec dbus-run-session -- "$@"
EOF
  chmod 755 "$HOME/bin/run-gui-termux"

  cat > "$HOME/bin/run-gui-termux-virgl" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

export TERMUX_GUI_RENDERER=virgl
exec "$HOME/bin/run-gui-termux" "$@"
EOF
  chmod 755 "$HOME/bin/run-gui-termux-virgl"

  cat > "$HOME/bin/run-gui-termux-software" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

export TERMUX_GUI_RENDERER=software
exec "$HOME/bin/run-gui-termux" "$@"
EOF
  chmod 755 "$HOME/bin/run-gui-termux-software"

  cat > "$HOME/bin/run-gui-termux-xfce" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

exec "$HOME/bin/run-gui-termux" "$@"
EOF
  chmod 755 "$HOME/bin/run-gui-termux-xfce"

  cat > "$HOME/bin/run-gui-termux-xfce-virgl" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

exec "$HOME/bin/run-gui-termux-virgl" "$@"
EOF
  chmod 755 "$HOME/bin/run-gui-termux-xfce-virgl"

  cat > "$HOME/bin/run-gui-termux-xfce-software" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

exec "$HOME/bin/run-gui-termux-software" "$@"
EOF
  chmod 755 "$HOME/bin/run-gui-termux-xfce-software"
}

write_openbox_launchers() {
  cat > "$HOME/bin/openbox-terminal" <<EOF
#!/usr/bin/env bash

set -euo pipefail

if command -v xfce4-terminal >/dev/null 2>&1; then
  exec xfce4-terminal --disable-server --working-directory="/home/${EXPECTED_USER}" --title='Debian Terminal'
fi

exec xterm
EOF
  chmod 755 "$HOME/bin/openbox-terminal"

  cat > "$HOME/bin/openbox-launcher" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

if command -v rofi >/dev/null 2>&1; then
  exec rofi -show drun -modi drun,run,window -show-icons
fi

printf 'rofi não encontrado dentro do Debian.\n' >&2
exit 1
EOF
  chmod 755 "$HOME/bin/openbox-launcher"

  cat > "$HOME/bin/openbox-file-manager" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

if command -v thunar >/dev/null 2>&1; then
  exec thunar
fi

exec "$HOME/bin/openbox-terminal"
EOF
  chmod 755 "$HOME/bin/openbox-file-manager"

  cat > "$HOME/bin/openbox-settings" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

if command -v lxappearance >/dev/null 2>&1; then
  exec lxappearance
fi

if command -v obconf >/dev/null 2>&1; then
  exec obconf
fi

printf 'Nenhuma ferramenta de configuracao do Openbox esta disponivel.\n' >&2
exit 1
EOF
  chmod 755 "$HOME/bin/openbox-settings"

  cat > "$HOME/bin/start-openbox-termux-x11" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="${HOME}/.config/termux-stack/env.sh"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

cd "$HOME"
mkdir -p "$XDG_RUNTIME_DIR" "$HOME/.cache"
chmod 700 "$XDG_RUNTIME_DIR"

pkill -f '^openbox( |$)|^tint2( |$)|^dunst( |$)|^xfsettingsd( |$)|^Thunar( |$)|^thunar( |$)' >/dev/null 2>&1 || true

printf 'Iniciando Openbox do Debian em %s.\n' "$DISPLAY"
exec dbus-launch --exit-with-session openbox-session
EOF
  chmod 755 "$HOME/bin/start-openbox-termux-x11"
}

write_openbox_config() {
  cat > "$HOME/.config/openbox/environment" <<'EOF'
#!/usr/bin/env sh

[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"
export PATH="$HOME/bin:$PATH"
export XDG_CURRENT_DESKTOP="Openbox"
export DESKTOP_SESSION="openbox"
export _JAVA_AWT_WM_NONREPARENTING=1
EOF

  cat > "$HOME/.config/openbox/autostart" <<'EOF'
#!/usr/bin/env sh

if command -v xsetroot >/dev/null 2>&1; then
  xsetroot -cursor_name left_ptr -solid '#20242b'
fi

if command -v tint2 >/dev/null 2>&1 && ! pgrep -x tint2 >/dev/null 2>&1; then
  tint2 >/dev/null 2>&1 &
fi

if command -v xfsettingsd >/dev/null 2>&1 && ! pgrep -x xfsettingsd >/dev/null 2>&1; then
  xfsettingsd >/dev/null 2>&1 &
fi

if command -v dunst >/dev/null 2>&1 && ! pgrep -x dunst >/dev/null 2>&1; then
  dunst >/dev/null 2>&1 &
fi
EOF

  cat > "$HOME/.config/openbox/menu.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Openbox">
    <item label="Aplicativos">
      <action name="Execute">
        <command>openbox-launcher</command>
      </action>
    </item>
    <item label="Terminal">
      <action name="Execute">
        <command>openbox-terminal</command>
      </action>
    </item>
    <item label="Arquivos">
      <action name="Execute">
        <command>openbox-file-manager</command>
      </action>
    </item>
    <item label="Configuracoes">
      <action name="Execute">
        <command>openbox-settings</command>
      </action>
    </item>
    <separator />
    <menu id="client-list-combined-menu" />
    <separator />
    <item label="Reconfigurar Openbox">
      <action name="Reconfigure" />
    </item>
    <item label="Sair da sessao">
      <action name="Exit">
        <prompt>yes</prompt>
      </action>
    </item>
  </menu>
</openbox_menu>
EOF

  cat > "$HOME/.config/openbox/rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
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
  </keyboard>
</openbox_config>
EOF

  cat > "$HOME/.config/tint2/tint2rc" <<'EOF'
# Managed by TermuxAiLocal

rounded = 0
border_width = 0
border_sides = TBLR
background_color = #16181d 92
border_color = #16181d 92
background_color_hover = #16181d 92
border_color_hover = #16181d 92
background_color_pressed = #16181d 92
border_color_pressed = #16181d 92

rounded = 4
border_width = 0
border_sides = TBLR
background_color = #232730 88
border_color = #232730 88
background_color_hover = #2c313d 96
border_color_hover = #2c313d 96
background_color_pressed = #303646 100
border_color_pressed = #303646 100

rounded = 4
border_width = 0
border_sides = TBLR
background_color = #3a404d 96
border_color = #3a404d 96
background_color_hover = #454d5f 100
border_color_hover = #454d5f 100
background_color_pressed = #4f586d 100
border_color_pressed = #4f586d 100

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
panel_size = 100% 30
panel_margin = 0 0
panel_padding = 6 4 6
panel_background_id = 1
wm_menu = 1
panel_dock = 1
panel_position = bottom center horizontal
panel_layer = normal
panel_monitor = all
panel_shrink = 0
autohide = 0
strut_policy = follow_size
panel_window_name = tint2
disable_transparency = 0
mouse_effects = 1

taskbar_mode = single_desktop
taskbar_hide_if_empty = 0
taskbar_padding = 4 0 4
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_name = 0
taskbar_distribute_size = 1
task_align = left

task_text = 1
task_icon = 1
task_centered = 1
urgent_nb_of_blink = 100000
task_maximum_size = 180 30
task_padding = 6 3 6
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

systray_padding = 4 0 4
systray_background_id = 0
systray_sort = ascending
systray_icon_size = 18
systray_icon_asb = 100 0 0

time1_format = %H:%M
time1_font = sans bold 9
clock_font_color = #eceff4 100
clock_padding = 6 0
clock_background_id = 0

tooltip_show_timeout = 0.2
tooltip_hide_timeout = 0.1
tooltip_padding = 6 4
tooltip_background_id = 4
tooltip_font_color = #181818 100

button = new
button_icon = start-here
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
EOF

  chmod 755 "$HOME/.config/openbox/autostart"
  chmod 644 "$HOME/.config/openbox/environment" "$HOME/.config/openbox/menu.xml" "$HOME/.config/openbox/rc.xml" "$HOME/.config/tint2/tint2rc"
}

write_shell_extras() {
  cat > "$HOME/.bash_aliases" <<'EOF'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias envgui='source "$HOME/.config/termux-stack/env.sh"'
EOF

  cat > "$HOME/.config/termux-stack/bash_prompt.sh" <<'EOF'
export PS1='\u@\h:\w\$ '
EOF

  chmod 644 "$HOME/.bash_aliases" "$HOME/.config/termux-stack/bash_prompt.sh"
}

write_termux_desktop_sync_helper() {
  cat > "$HOME/bin/sync-termux-desktop-entries" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

ENV_FILE="${HOME}/.config/termux-stack/env.sh"

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  . "$ENV_FILE"
fi

expected_user="${TERMUX_X11_DISTRO_USER:-$(id -un)}"
host_home="${TERMUX_HOST_HOME:-/data/data/com.termux/files/home}"
applications_dir="${TERMUX_HOST_APPLICATIONS_DIR:-$host_home/.local/share/applications}"
wrappers_dir="${TERMUX_HOST_DEBIAN_WRAPPERS_DIR:-$host_home/bin/debian-apps}"
host_data_home="$host_home/.local/share"
managed_prefix="debian-${expected_user}-"

safe_slug() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '-'
}

trim_exec_codes() {
  printf '%s' "$1" \
    | sed -E 's/[[:space:]]+%[fFuUdDnNickvm]//g; s/%[fFuUdDnNickvm]//g' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

escape_squote() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

resolve_icon() {
  local icon_name="$1"
  local candidate
  local rootfs_icon_dirs=(
    /usr/share/pixmaps
    /usr/share/icons/hicolor/48x48/apps
    /usr/share/icons/hicolor/32x32/apps
    /usr/share/icons/hicolor/24x24/apps
    /usr/share/icons/hicolor/22x22/apps
    /usr/share/icons/hicolor/16x16/apps
  )

  if [ -z "$icon_name" ]; then
    return 0
  fi

  if [ -f "$icon_name" ]; then
    printf '%s\n' "$icon_name"
    return 0
  fi

  for candidate in \
    "$icon_name" \
    "${icon_name}.png" \
    "${icon_name}.svg" \
    "${icon_name}.xpm"; do
    for dir in "${rootfs_icon_dirs[@]}"; do
      if [ -f "$dir/$candidate" ]; then
        printf '%s\n' "$dir/$candidate"
        return 0
      fi
    done
  done
}

extract_value() {
  local key="$1"
  local file="$2"
  awk -F= -v key="$key" '
    $0=="[Desktop Entry]" {in_entry=1; next}
    in_entry && /^\[/ {exit}
    in_entry && $1==key {
      sub(/^[^=]*=/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

is_useful_launcher() {
  local categories="$1"
  local name="$2"
  local normalized_name

  normalized_name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"

  case "$name" in
    Accessibility|Appearance|Color\ Profiles|Customize\ Look\ and\ Feel|Default\ Applications|Desktop|Display|Keyboard|Mouse*|Notifications|Removable\ Drives\ and\ Media|Screensaver|Session\ and\ Startup|Settings*|Window\ Manager|Workspaces|Panel|Power\ Manager|Preferred\ Applications|Color|Rofi|Rofi\ Theme\ Selector|File\ Manager|Mail\ Reader|Web\ Browser|Log\ Out|Tint2)
      return 1
      ;;
  esac

  case "$normalized_name" in
    xterm|uxterm|terminal\ emulator|xfce\ terminal)
      return 1
      ;;
  esac

  if printf '%s' "$categories" | grep -Eq '(^|;)(Settings|DesktopSettings|X-XFCE-SettingsDialog)(;|$)'; then
    return 1
  fi

  return 0
}

mkdir -p "$applications_dir" "$wrappers_dir" "$host_data_home"

find "$applications_dir" -maxdepth 1 -type f -name "${managed_prefix}*.desktop" -delete
find "$wrappers_dir" -maxdepth 1 -type f -name "${managed_prefix}*" -delete

desktop_sources=(
  /usr/share/applications/*.desktop
  "$HOME/.local/share/applications"/*.desktop
)

for desktop_file in "${desktop_sources[@]}"; do
  [ -f "$desktop_file" ] || continue

  type_value="$(extract_value Type "$desktop_file")"
  name_value="$(extract_value Name "$desktop_file")"
  exec_value="$(extract_value Exec "$desktop_file")"
  icon_value="$(extract_value Icon "$desktop_file")"
  nodisplay_value="$(extract_value NoDisplay "$desktop_file")"
  hidden_value="$(extract_value Hidden "$desktop_file")"
  terminal_value="$(extract_value Terminal "$desktop_file")"
  categories_value="$(extract_value Categories "$desktop_file")"

  [ "$type_value" = "Application" ] || continue
  [ -n "$name_value" ] || continue
  [ -n "$exec_value" ] || continue
  [ "${nodisplay_value:-false}" != "true" ] || continue
  [ "${hidden_value:-false}" != "true" ] || continue
  [ "${terminal_value:-false}" != "true" ] || continue
  is_useful_launcher "${categories_value:-}" "$name_value" || continue

  sanitized_exec="$(trim_exec_codes "$exec_value")"
  [ -n "$sanitized_exec" ] || continue

  slug="$(safe_slug "$name_value")"
  wrapper_path="$wrappers_dir/${managed_prefix}${slug}"
  desktop_out="$applications_dir/${managed_prefix}${slug}.desktop"
  escaped_label="$(escape_squote "$name_value")"
  escaped_exec="$(escape_squote "$sanitized_exec")"
  resolved_icon="$(resolve_icon "$icon_value" || true)"

  if [ "$name_value" = "FreeCAD" ]; then
    cat > "$wrapper_path" <<EOF2
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec run-gui-debian --label '${escaped_label}' -- /bin/sh -lc '
${escaped_exec} &
app_pid=\$!
if command -v wmctrl >/dev/null 2>&1; then
  i=0
  while [ \$i -lt 40 ]; do
    sleep 0.25
    wmctrl -x -r freecad.FreeCAD -e 0,0,60,-1,-1 >/dev/null 2>&1 || true
    i=\$((i + 1))
  done
fi
wait "\$app_pid"
'
EOF2
  else
    cat > "$wrapper_path" <<EOF2
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec run-gui-debian --label '${escaped_label}' -- /bin/sh -lc 'exec ${escaped_exec}'
EOF2
  fi
  chmod 755 "$wrapper_path"

  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Name=%s\n' "$name_value"
    printf 'Exec=%s\n' "$wrapper_path"
    printf 'Terminal=false\n'
    printf 'StartupNotify=true\n'
    if [ -n "${resolved_icon:-}" ]; then
      printf 'Icon=%s\n' "$resolved_icon"
    elif [ -n "${icon_value:-}" ]; then
      printf 'Icon=%s\n' "$icon_value"
    fi
    if [ -n "${categories_value:-}" ]; then
      printf 'Categories=%s\n' "$categories_value"
    fi
  } > "$desktop_out"
done

printf 'Desktop entries Debian sincronizados para o launcher do host em %s\n' "$applications_dir"
EOF
  chmod 755 "$HOME/bin/sync-termux-desktop-entries"
}

wire_shell_startup() {
  touch "$HOME/.profile" "$HOME/.bashrc" "$HOME/.xprofile" "$HOME/.xsessionrc"
  append_once "$HOME/.profile" 'export PATH="$HOME/bin:$PATH"'
  append_once "$HOME/.profile" '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"'
  append_once "$HOME/.profile" '[ -f "$HOME/.bash_aliases" ] && . "$HOME/.bash_aliases"'
  append_once "$HOME/.bashrc" 'export PATH="$HOME/bin:$PATH"'
  append_once "$HOME/.bashrc" '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"'
  append_once "$HOME/.bashrc" '[ -f "$HOME/.bash_aliases" ] && . "$HOME/.bash_aliases"'
  append_once "$HOME/.bashrc" '[ -f "$HOME/.config/termux-stack/bash_prompt.sh" ] && . "$HOME/.config/termux-stack/bash_prompt.sh"'
  append_once "$HOME/.xprofile" '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"'
  append_once "$HOME/.xsessionrc" '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"'
}

validate_user_environment() {
  test -f "$ENV_FILE"
  test -x "$HOME/bin/run-gui-termux"
  test -x "$HOME/bin/run-gui-termux-virgl"
  test -x "$HOME/bin/run-gui-termux-software"
  test -x "$HOME/bin/run-gui-termux-xfce"
  test -x "$HOME/bin/run-gui-termux-xfce-virgl"
  test -x "$HOME/bin/run-gui-termux-xfce-software"
  test -x "$HOME/bin/start-xfce-termux-x11"
  test -x "$HOME/bin/openbox-terminal"
  test -x "$HOME/bin/openbox-launcher"
  test -x "$HOME/bin/openbox-file-manager"
  test -x "$HOME/bin/openbox-settings"
  test -x "$HOME/bin/start-openbox-termux-x11"
  test -x "$HOME/bin/sync-termux-desktop-entries"
  test -f "$HOME/.config/openbox/autostart"
  test -f "$HOME/.config/openbox/menu.xml"
  test -f "$HOME/.config/openbox/rc.xml"
  test -f "$HOME/.config/tint2/tint2rc"
  test -f "$HOME/.bash_aliases"
  grep -Fqx '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"' "$HOME/.profile"
  grep -Fqx '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"' "$HOME/.bashrc"
  grep -Fqx '[ -f "$HOME/.bash_aliases" ] && . "$HOME/.bash_aliases"' "$HOME/.profile"
  grep -Fqx '[ -f "$HOME/.bash_aliases" ] && . "$HOME/.bash_aliases"' "$HOME/.bashrc"
  grep -Fqx '[ -f "$HOME/.config/termux-stack/bash_prompt.sh" ] && . "$HOME/.config/termux-stack/bash_prompt.sh"' "$HOME/.bashrc"
  grep -Fqx '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"' "$HOME/.xprofile"
  grep -Fqx '[ -f "$HOME/.config/termux-stack/env.sh" ] && . "$HOME/.config/termux-stack/env.sh"' "$HOME/.xsessionrc"
  /bin/bash -lc '. "$HOME/.config/termux-stack/env.sh"; printf "DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nTERMUX_X11_WM=%s\nTERMUX_GUI_RENDERER=%s\nGALLIUM_DRIVER=%s\n" "$DISPLAY" "$XDG_RUNTIME_DIR" "$TERMUX_X11_WM" "$TERMUX_GUI_RENDERER" "$GALLIUM_DRIVER"'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user)
      shift
      EXPECTED_USER="${1:-}"
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
        'A configuração do ambiente do usuário Debian não pode continuar com parâmetros desconhecidos.' \
        'Usar apenas --user ou --help.'
      ;;
  esac
done

if [ -z "$EXPECTED_USER" ]; then
  EXPECTED_USER="$(id -un)"
fi

if [ "$(id -un)" != "$EXPECTED_USER" ]; then
  fail \
    'id -un' \
    "Este script precisa ser executado como ${EXPECTED_USER} dentro do Debian." \
    'A configuração do ambiente do usuário alvo não pode ser garantida.' \
    "Executar via proot-distro login --user ${EXPECTED_USER} ..."
fi

run_step 'Preparando diretórios de runtime e configuração' prepare_runtime_dirs
run_step 'Gerando arquivo de ambiente do usuário Debian' write_env_file
run_step 'Gerando launchers GUI do usuário Debian' write_gui_launchers
run_step 'Gerando launchers Openbox do usuário Debian' write_openbox_launchers
run_step 'Gerando configuração Openbox e painel do usuário Debian' write_openbox_config
run_step 'Gerando extras de shell do usuário Debian' write_shell_extras
run_step 'Gerando helper de sync dos atalhos Debian para o host' write_termux_desktop_sync_helper
run_step 'Conectando env.sh ao shell interativo do usuário' wire_shell_startup
run_step 'Validando ambiente, launchers e variáveis do usuário' validate_user_environment
run_step 'Sincronizando atalhos Debian para o launcher do Openbox host' "$HOME/bin/sync-termux-desktop-entries"

printf '\nConfiguração do usuário Debian concluída.\n'
printf 'Usuário: %s\n' "$EXPECTED_USER"
printf 'Env file: %s\n' "$ENV_FILE"
printf 'Launcher do desktop XFCE: %s/bin/start-xfce-termux-x11\n' "$HOME"
printf 'Launcher opcional Openbox no Debian: %s/bin/start-openbox-termux-x11\n' "$HOME"
printf 'Launcher genérico GUI: %s/bin/run-gui-termux\n' "$HOME"
printf 'Launcher hardware explícito: %s/bin/run-gui-termux-virgl\n' "$HOME"
printf 'Launcher fallback software: %s/bin/run-gui-termux-software\n' "$HOME"
printf 'Log geral: %s\n' "$SCRIPT_LOG"
