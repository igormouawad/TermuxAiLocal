#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

DISTRO_ALIAS="debian-trixie-gui"
PROOT_USER="igor"
RENDERER="hardware"
RUN_MODE="background"
TERMUX_GUI_PULSE_SERVER=""
APP_LABEL="Aplicativo"

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
  exit 1
}

desktop_is_active() {
  pgrep -f '^openbox( |$)|openbox-session|^xterm( |$)|^xfce4-session( |$)|^xfwm4( |$)|^xfdesktop( |$)|^xfce4-panel( |$)|termux-x11 .*:1|termux-x11 :1' >/dev/null 2>&1
}

ensure_hardware_path() {
  local start_output

  if pgrep -f 'virgl_test_server_android' >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v start-virgl >/dev/null 2>&1; then
    fail \
      'command -v start-virgl' \
      'O helper start-virgl não está disponível no Termux.' \
      'O caminho 3D por hardware não pode ser inicializado.' \
      'Reinstalar ou reprovisionar a stack principal do Termux antes de tentar novamente.'
  fi

  if ! start_output=$(start-virgl 2>&1); then
    fail \
      'start-virgl' \
      "$start_output" \
      'O servidor virgl do host Termux não subiu corretamente.' \
      'Corrigir a falha do baseline gráfico e repetir o lançamento do aplicativo.'
  fi

  sleep 2

  if ! pgrep -f 'virgl_test_server_android' >/dev/null 2>&1; then
    fail \
      'validação do start-virgl' \
      'O processo virgl_test_server_android não permaneceu ativo.' \
      'O aplicativo não terá renderização por hardware no host Termux.' \
      'Revalidar o baseline com GPU antes de tentar novamente.'
  fi
}

usage() {
  printf 'Uso: %s [--alias nome] [--user igor] [--renderer hardware|software|virgl] [--background|--foreground] [--pulse-server tcp:127.0.0.1:4713] [--label nome] -- comando [args...]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --alias)
      shift
      DISTRO_ALIAS="${1:-}"
      shift || true
      ;;
    --user)
      shift
      PROOT_USER="${1:-}"
      shift || true
      ;;
    --renderer)
      shift
      RENDERER="${1:-hardware}"
      shift || true
      ;;
    --pulse-server)
      shift
      TERMUX_GUI_PULSE_SERVER="${1:-}"
      shift || true
      ;;
    --label)
      shift
      APP_LABEL="${1:-Aplicativo}"
      shift || true
      ;;
    --foreground)
      RUN_MODE="foreground"
      shift
      ;;
    --background)
      RUN_MODE="background"
      shift
      ;;
    --help|-h)
      usage
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
    'Nenhum comando Debian foi informado para o launcher genérico.' \
    'O helper não sabe qual aplicativo GUI precisa iniciar.' \
    'Usar run-gui-debian -- comando [args...].'
fi

if [ ! -d '/data/data/com.termux/files/usr' ] || [ "${PREFIX:-}" != '/data/data/com.termux/files/usr' ] || ! command -v proot-distro >/dev/null 2>&1; then
  fail \
    'validação do ambiente Termux' \
    'Este launcher precisa ser executado dentro do app Termux com proot-distro disponível.' \
    'O aplicativo não pode ser lançado no contexto esperado.' \
    'Abrir o app Termux, garantir que proot-distro esteja instalado e repetir a operação.'
fi

if [ -z "$DISTRO_ALIAS" ] || [ -z "$PROOT_USER" ]; then
  fail \
    'validação de argumentos' \
    'Alias e usuário Debian precisam ser não vazios.' \
    'Não é possível localizar o launcher correto dentro do proot.' \
    'Fornecer valores válidos com --alias e --user.'
fi

if ! desktop_is_active; then
  fail \
    'validação da sessão X11 :1' \
    'Nenhuma sessão Openbox/XFCE ativa foi detectada em :1.' \
    'O aplicativo GUI não terá onde desenhar a interface gráfica.' \
      'Subir o desktop com start-openbox, start-openbox-maxperf ou o launcher ADB equivalente antes de lançar o aplicativo.'
fi

if [ ! -d "${PREFIX}/var/lib/proot-distro/installed-rootfs/${DISTRO_ALIAS}" ]; then
  fail \
    "test -d \"${PREFIX}/var/lib/proot-distro/installed-rootfs/${DISTRO_ALIAS}\"" \
    'A instância Debian solicitada não está instalada.' \
    'Não há proot Debian pronto para receber o aplicativo GUI.' \
    'Executar primeiro bash /data/local/tmp/install_debian_trixie_gui.sh no app Termux.'
fi

case "$RENDERER" in
  hardware|virgl)
    ensure_hardware_path
    ;;
  software)
    ;;
  *)
    fail \
      'validação de argumentos' \
      "Renderer não suportado: $RENDERER" \
      'O launcher não sabe como configurar a trilha gráfica do aplicativo.' \
      'Usar hardware, software ou virgl.'
    ;;
esac

launcher_command=(
  proot-distro login
  --no-arch-warning
  --user "$PROOT_USER"
  --shared-tmp
  "$DISTRO_ALIAS"
  --
  env
  TERMUX_GUI_RENDERER="$RENDERER"
  TERMUX_GUI_PULSE_SERVER="$TERMUX_GUI_PULSE_SERVER"
  "/home/${PROOT_USER}/bin/run-gui-termux"
)

launcher_command+=("$@")

if [ "$RUN_MODE" = 'foreground' ]; then
  exec "${launcher_command[@]}"
fi

launch_name="$(basename "$1")"
launch_log="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/${launch_name}-debian-launch.log"
nohup "${launcher_command[@]}" >"$launch_log" 2>&1 &
disown || true

printf '%s enviado ao Debian com sucesso.\n' "$APP_LABEL"
printf 'Alias: %s\n' "$DISTRO_ALIAS"
printf 'Usuário: %s\n' "$PROOT_USER"
printf 'Renderer: %s\n' "$RENDERER"
printf 'Comando: %s\n' "$1"
printf 'Log: %s\n' "$launch_log"
