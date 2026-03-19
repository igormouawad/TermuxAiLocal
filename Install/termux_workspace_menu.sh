#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

if [[ "${PREFIX:-}" != "/data/data/com.termux/files/usr" ]]; then
  printf 'Este menu deve ser executado dentro do app Termux.\n' >&2
  exit 1
fi

export PATH="$HOME/bin:$PATH"

declare -a ACTION_IDS=()
declare -a ACTION_CATEGORIES=()
declare -a ACTION_LABELS=()
declare -a ACTION_PREVIEWS=()
declare -a ACTION_HANDLERS=()
declare -a ACTION_CONFIRM=()
declare -a ACTION_NOTES=()

usage() {
  cat <<'EOF'
Uso:
  termux-workspace-menu
  termux-workspace-menu --list
  termux-workspace-menu --run ACTION_ID [--yes]

Modos:
  --list        Lista os itens do menu e os comandos associados.
  --run ID      Executa um item diretamente pelo ACTION_ID ou numero.
  --yes         Pula a confirmacao interativa para --run.
EOF
}

add_action() {
  ACTION_IDS+=("$1")
  ACTION_CATEGORIES+=("$2")
  ACTION_LABELS+=("$3")
  ACTION_PREVIEWS+=("$4")
  ACTION_HANDLERS+=("$5")
  ACTION_CONFIRM+=("$6")
  ACTION_NOTES+=("$7")
}

require_helper() {
  local helper_name="$1"

  if ! command -v "$helper_name" >/dev/null 2>&1; then
    printf 'Helper ausente no Termux: %s\n' "$helper_name" >&2
    return 1
  fi
}

require_payload() {
  local payload_path="$1"

  if [[ ! -f "$payload_path" ]]; then
    printf 'Payload ausente: %s\n' "$payload_path" >&2
    return 1
  fi
}

run_required_helper() {
  local helper_name="$1"
  shift

  require_helper "$helper_name"
  "$helper_name" "$@"
}

run_payload_script() {
  local payload_path="$1"

  require_payload "$payload_path"
  bash "$payload_path"
}

handler_status() {
  run_required_helper termux-stack-status
}

handler_status_brief() {
  run_required_helper termux-stack-status --brief
}

handler_resolution_show() {
  run_required_helper set-x11-resolution show
}

handler_start_x11() {
  run_required_helper start-termux-x11
}

handler_stop_x11() {
  run_required_helper stop-termux-x11
}

handler_resolution_balanced() {
  run_required_helper set-x11-resolution balanced
}

handler_resolution_performance() {
  run_required_helper set-x11-resolution performance
}

handler_resolution_native() {
  run_required_helper set-x11-resolution native
}

handler_resolution_custom() {
  local value

  require_helper set-x11-resolution
  read -r -p 'Resolucao custom (LARGURAxALTURA): ' value
  if [[ -z "${value:-}" ]]; then
    printf 'Resolucao vazia; cancelado.\n'
    return 0
  fi
  run_required_helper set-x11-resolution custom "$value"
}

handler_start_virgl_plain() {
  run_required_helper start-virgl plain
}

handler_start_virgl_gl() {
  run_required_helper start-virgl gl
}

handler_start_virgl_vulkan() {
  run_required_helper start-virgl vulkan
}

handler_stop_virgl() {
  run_required_helper stop-virgl
}

handler_check_gpu() {
  run_required_helper check-gpu-termux
}

handler_start_openbox() {
  run_required_helper start-openbox
}

handler_start_openbox_stable() {
  run_required_helper start-openbox-stable
}

handler_start_openbox_maxperf() {
  run_required_helper start-openbox-maxperf
}

handler_start_daily_openbox() {
  handler_start_openbox_maxperf
}

handler_start_openbox_compat() {
  run_required_helper start-openbox-compat
}

handler_start_openbox_vulkan() {
  run_required_helper start-openbox-vulkan-exp
}

handler_stop_openbox() {
  run_required_helper stop-openbox-x11
}

handler_start_xfce() {
  run_required_helper start-xfce-x11
}

handler_start_xfce_openbox() {
  run_required_helper start-xfce-x11 --wm openbox
}

handler_start_xfce_detached() {
  run_required_helper start-xfce-x11-detached
}

handler_stop_xfce() {
  run_required_helper stop-xfce-x11
}

handler_start_maxperf_openbox() {
  run_required_helper start-maxperf-x11 openbox
}

handler_start_maxperf_xfce() {
  run_required_helper start-maxperf-x11 xfce
}

handler_x11_demo() {
  run_required_helper run-in-x11 --app aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'
}

handler_glmark2() {
  run_required_helper run-glmark2-x11
}

handler_debian_xeyes() {
  run_required_helper run-gui-debian --label XEyes -- xeyes
}

handler_login_debian() {
  run_required_helper login-debian-gui
}

handler_repo_bootstrap() {
  run_payload_script /data/local/tmp/install_termux_repo_bootstrap.sh
}

handler_install_stack_payload() {
  run_payload_script /data/local/tmp/install_termux_stack.sh
}

handler_install_debian_payload() {
  run_payload_script /data/local/tmp/install_debian_trixie_gui.sh
}

register_actions() {
  add_action \
    "status" \
    "Status e diagnostico" \
    "Mostrar termux-stack-status completo" \
    "termux-stack-status" \
    "handler_status" \
    "0" \
    "Leitura completa do estado atual do stack."

  add_action \
    "status_brief" \
    "Status e diagnostico" \
    "Mostrar termux-stack-status --brief" \
    "termux-stack-status --brief" \
    "handler_status_brief" \
    "0" \
    "Probe rapido do stack."

  add_action \
    "resolution_show" \
    "Status e diagnostico" \
    "Mostrar resolucao atual do Termux:X11" \
    "set-x11-resolution show" \
    "handler_resolution_show" \
    "0" \
    "Le as preferencias reais do Termux:X11."

  add_action \
    "start_x11" \
    "X11 e resolucao" \
    "Subir Termux:X11 em :1" \
    "start-termux-x11" \
    "handler_start_x11" \
    "1" \
    "Sobe o servidor X11 do host Termux."

  add_action \
    "stop_x11" \
    "X11 e resolucao" \
    "Parar Termux:X11" \
    "stop-termux-x11" \
    "handler_stop_x11" \
    "1" \
    "Encerra a activity/processo do Termux:X11."

  add_action \
    "resolution_balanced" \
    "X11 e resolucao" \
    "Aplicar resolucao balanced" \
    "set-x11-resolution balanced" \
    "handler_resolution_balanced" \
    "1" \
    "Reaplica a resolucao cheia do desktop."

  add_action \
    "resolution_performance" \
    "X11 e resolucao" \
    "Aplicar resolucao performance" \
    "set-x11-resolution performance" \
    "handler_resolution_performance" \
    "1" \
    "Reaplica 1280x720 para reduzir fill-rate."

  add_action \
    "resolution_native" \
    "X11 e resolucao" \
    "Aplicar resolucao nativa" \
    "set-x11-resolution native" \
    "handler_resolution_native" \
    "1" \
    "Volta ao modo nativo do app Termux:X11."

  add_action \
    "resolution_custom" \
    "X11 e resolucao" \
    "Aplicar resolucao custom" \
    "set-x11-resolution custom LARGURAxALTURA" \
    "handler_resolution_custom" \
    "1" \
    "Pede a resolucao e aplica via helper do projeto."

  add_action \
    "start_virgl_plain" \
    "VirGL e GPU" \
    "Subir VirGL plain" \
    "start-virgl plain" \
    "handler_start_virgl_plain" \
    "1" \
    "Modo diario de aceleracao aceito no projeto."

  add_action \
    "start_virgl_gl" \
    "VirGL e GPU" \
    "Subir VirGL gl" \
    "start-virgl gl" \
    "handler_start_virgl_gl" \
    "1" \
    "Perfil de compatibilidade para testes."

  add_action \
    "start_virgl_vulkan" \
    "VirGL e GPU" \
    "Subir VirGL vulkan" \
    "start-virgl vulkan" \
    "handler_start_virgl_vulkan" \
    "1" \
    "Perfil experimental Vulkan."

  add_action \
    "stop_virgl" \
    "VirGL e GPU" \
    "Parar VirGL" \
    "stop-virgl" \
    "handler_stop_virgl" \
    "1" \
    "Encerra o servidor VirGL."

  add_action \
    "check_gpu" \
    "VirGL e GPU" \
    "Rodar check-gpu-termux" \
    "check-gpu-termux" \
    "handler_check_gpu" \
    "0" \
    "Valida EGL/GLES e GL_RENDERER."

  add_action \
    "daily_openbox" \
    "Uso diario" \
    "Iniciar desktop diario acelerado" \
    "start-openbox-maxperf" \
    "handler_start_daily_openbox" \
    "1" \
    "Sobe o desktop leve do dia a dia com Openbox, VirGL plain e perfil de performance." 

  add_action \
    "start_openbox" \
    "Openbox" \
    "Subir Openbox default" \
    "start-openbox" \
    "handler_start_openbox" \
    "1" \
    "Atalho diario para o perfil Openbox padrao."

  add_action \
    "start_openbox_stable" \
    "Openbox" \
    "Subir Openbox stable" \
    "start-openbox-stable" \
    "handler_start_openbox_stable" \
    "1" \
    "Perfil mais conservador."

  add_action \
    "start_openbox_maxperf" \
    "Openbox" \
    "Subir Openbox maxperf" \
    "start-openbox-maxperf" \
    "handler_start_openbox_maxperf" \
    "1" \
    "Perfil diario validado."

  add_action \
    "start_openbox_compat" \
    "Openbox" \
    "Subir Openbox compat" \
    "start-openbox-compat" \
    "handler_start_openbox_compat" \
    "1" \
    "Perfil de compatibilidade."

  add_action \
    "start_openbox_vulkan" \
    "Openbox" \
    "Subir Openbox Vulkan experimental" \
    "start-openbox-vulkan-exp" \
    "handler_start_openbox_vulkan" \
    "1" \
    "Perfil Vulkan experimental."

  add_action \
    "stop_openbox" \
    "Openbox" \
    "Parar sessao Openbox" \
    "stop-openbox-x11" \
    "handler_stop_openbox" \
    "1" \
    "Encerra a sessao Openbox e terminais leves."

  add_action \
    "start_xfce" \
    "XFCE" \
    "Subir XFCE padrao" \
    "start-xfce-x11" \
    "handler_start_xfce" \
    "1" \
    "Subida foreground do XFCE."

  add_action \
    "start_xfce_openbox" \
    "XFCE" \
    "Subir XFCE usando Openbox como WM" \
    "start-xfce-x11 --wm openbox" \
    "handler_start_xfce_openbox" \
    "1" \
    "Mantem XFCE, trocando apenas o window manager."

  add_action \
    "start_xfce_detached" \
    "XFCE" \
    "Subir XFCE detached" \
    "start-xfce-x11-detached" \
    "handler_start_xfce_detached" \
    "1" \
    "Nao sequestra o prompt foreground."

  add_action \
    "stop_xfce" \
    "XFCE" \
    "Parar sessao XFCE" \
    "stop-xfce-x11" \
    "handler_stop_xfce" \
    "1" \
    "Encerra a sessao XFCE."

  add_action \
    "start_maxperf_openbox" \
    "XFCE" \
    "Fluxo maxperf com Openbox" \
    "start-maxperf-x11 openbox" \
    "handler_start_maxperf_openbox" \
    "1" \
    "Atalho agressivo de benchmark com Openbox."

  add_action \
    "start_maxperf_xfce" \
    "XFCE" \
    "Fluxo maxperf com XFCE" \
    "start-maxperf-x11 xfce" \
    "handler_start_maxperf_xfce" \
    "1" \
    "Atalho agressivo de benchmark com XFCE."

  add_action \
    "x11_demo" \
    "Apps e benchmark" \
    "Abrir aterm leve no X11" \
    "run-in-x11 --app aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'" \
    "handler_x11_demo" \
    "0" \
    "Teste leve do display :1."

  add_action \
    "glmark2" \
    "Apps e benchmark" \
    "Rodar glmark2 no X11" \
    "run-glmark2-x11" \
    "handler_glmark2" \
    "1" \
    "Benchmark onscreen do X11 atual."

  add_action \
    "debian_xeyes" \
    "Apps e benchmark" \
    "Abrir xeyes no Debian" \
    "run-gui-debian --label XEyes -- xeyes" \
    "handler_debian_xeyes" \
    "0" \
    "Teste rapido do launcher Debian GUI."

  add_action \
    "login_debian" \
    "Apps e benchmark" \
    "Entrar no Debian GUI" \
    "login-debian-gui" \
    "handler_login_debian" \
    "1" \
    "Abre a sessao interativa do Debian."

  add_action \
    "repo_bootstrap" \
    "Manutencao" \
    "Rodar bootstrap fino do Termux" \
    "bash /data/local/tmp/install_termux_repo_bootstrap.sh" \
    "handler_repo_bootstrap" \
    "1" \
    "Usado apos reinstall limpa dos APKs."

  add_action \
    "install_stack_payload" \
    "Manutencao" \
    "Rodar payload principal da stack Termux" \
    "bash /data/local/tmp/install_termux_stack.sh" \
    "handler_install_stack_payload" \
    "1" \
    "Reaplica o payload principal do projeto dentro do app Termux."

  add_action \
    "install_debian_payload" \
    "Manutencao" \
    "Rodar payload principal Debian GUI" \
    "bash /data/local/tmp/install_debian_trixie_gui.sh" \
    "handler_install_debian_payload" \
    "1" \
    "Instala ou reaplica o Debian GUI dentro do app Termux."
}

print_action_entry() {
  local index="$1"
  printf '%2d) %-22s %s\n' "$((index + 1))" "${ACTION_IDS[$index]}" "${ACTION_LABELS[$index]}"
}

print_actions() {
  local last_category=""
  local i

  for i in "${!ACTION_IDS[@]}"; do
    if [[ "${ACTION_CATEGORIES[$i]}" != "$last_category" ]]; then
      printf '\n[%s]\n' "${ACTION_CATEGORIES[$i]}"
      last_category="${ACTION_CATEGORIES[$i]}"
    fi
    print_action_entry "$i"
  done
}

print_action_details() {
  local index="$1"

  printf 'ID: %s\n' "${ACTION_IDS[$index]}"
  printf 'Categoria: %s\n' "${ACTION_CATEGORIES[$index]}"
  printf 'Descricao: %s\n' "${ACTION_LABELS[$index]}"
  if [[ -n "${ACTION_NOTES[$index]}" ]]; then
    printf 'Nota: %s\n' "${ACTION_NOTES[$index]}"
  fi
  printf 'Comando(s):\n%s\n' "${ACTION_PREVIEWS[$index]}"
}

list_actions_verbose() {
  local last_category=""
  local i

  for i in "${!ACTION_IDS[@]}"; do
    if [[ "${ACTION_CATEGORIES[$i]}" != "$last_category" ]]; then
      printf '\n[%s]\n' "${ACTION_CATEGORIES[$i]}"
      last_category="${ACTION_CATEGORIES[$i]}"
    fi
    printf 'ID=%s\n' "${ACTION_IDS[$i]}"
    printf 'LABEL=%s\n' "${ACTION_LABELS[$i]}"
    printf 'COMMANDS:\n%s\n' "${ACTION_PREVIEWS[$i]}"
    if [[ -n "${ACTION_NOTES[$i]}" ]]; then
      printf 'NOTE=%s\n' "${ACTION_NOTES[$i]}"
    fi
    printf -- '---\n'
  done
}

resolve_action_index() {
  local token="$1"
  local i

  if [[ "$token" =~ ^[0-9]+$ ]]; then
    if (( token >= 1 && token <= ${#ACTION_IDS[@]} )); then
      printf '%s\n' "$((token - 1))"
      return 0
    fi
    return 1
  fi

  for i in "${!ACTION_IDS[@]}"; do
    if [[ "${ACTION_IDS[$i]}" == "$token" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done

  return 1
}

confirm_execution() {
  local index="$1"
  local answer

  if [[ "${ACTION_CONFIRM[$index]}" != "1" ]]; then
    return 0
  fi

  read -r -p "Executar este item? [s/N] " answer
  case "${answer:-}" in
    s|S|y|Y|yes|YES)
      return 0
      ;;
    *)
      printf 'Execucao cancelada.\n'
      return 1
      ;;
  esac
}

run_action_index() {
  local index="$1"
  local handler="${ACTION_HANDLERS[$index]}"

  "$handler"
}

interactive_menu() {
  local selection
  local index

  while :; do
    printf '\n=== Menu do Workspace no Termux ===\n'
    print_actions
    printf '\nDigite o numero ou ACTION_ID. Use q para sair.\n'
    read -r -p "> " selection

    case "${selection:-}" in
      q|Q|quit|exit)
        return 0
        ;;
      '')
        continue
        ;;
    esac

    if ! index="$(resolve_action_index "$selection")"; then
      printf 'Opcao invalida: %s\n' "$selection" >&2
      continue
    fi

    if ! confirm_execution "$index"; then
      continue
    fi

    printf '\n'
    if ! run_action_index "$index"; then
      printf '\nFalha ao executar %s.\n' "${ACTION_IDS[$index]}" >&2
    else
      printf '\nConcluido: %s\n' "${ACTION_IDS[$index]}"
    fi

    printf '\nPressione Enter para voltar ao menu...'
    read -r _
  done
}

RUN_ID=""
LIST_ONLY=0
AUTO_YES=0

while (($#)); do
  case "$1" in
    --list)
      LIST_ONLY=1
      shift
      ;;
    --run)
      shift
      if (($# == 0)); then
        printf 'Falta valor para --run.\n' >&2
        usage >&2
        exit 64
      fi
      RUN_ID="$1"
      shift
      ;;
    --yes)
      AUTO_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Argumento desconhecido: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

register_actions

if (( LIST_ONLY == 1 )); then
  list_actions_verbose
  exit 0
fi

if [[ -n "$RUN_ID" ]]; then
  if ! action_index="$(resolve_action_index "$RUN_ID")"; then
    printf 'ACTION_ID invalido: %s\n' "$RUN_ID" >&2
    exit 64
  fi

  print_action_details "$action_index"
  printf '\n'

  if (( AUTO_YES == 0 )) && ! confirm_execution "$action_index"; then
    exit 0
  fi

  run_action_index "$action_index"
  exit 0
fi

interactive_menu
