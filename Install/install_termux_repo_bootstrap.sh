#!/data/data/com.termux/files/usr/bin/bash

set -euo pipefail

MAIN_PAYLOAD="/data/local/tmp/install_termux_stack.sh"
TOTAL_STEPS=3
CURRENT_STEP=0
TERMUX_MAIN_REPO_URL="${TERMUX_MAIN_REPO_URL:-https://packages-cf.termux.dev/apt/termux-main}"
TERMUX_ROOT_REPO_URL="${TERMUX_ROOT_REPO_URL:-https://packages-cf.termux.dev/apt/termux-root}"
TERMUX_X11_REPO_URL="${TERMUX_X11_REPO_URL:-https://packages-cf.termux.dev/apt/termux-x11}"

progress_bar() {
  local current="$1"
  local total="$2"
  local width=20
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

log_step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf '%s (%s/%s) %s\n' "$(progress_bar "$CURRENT_STEP" "$TOTAL_STEPS")" "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
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
  exit 1
}

prime_termux_repos() {
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

  printf 'Mirror default principal fixado em %s\n' "$TERMUX_MAIN_REPO_URL"
  printf 'Mirror default root fixado em %s\n' "$TERMUX_ROOT_REPO_URL"
  printf 'Mirror default x11 fixado em %s\n' "$TERMUX_X11_REPO_URL"
  printf 'chosen_mirrors fixado em %s\n' "${PREFIX}/etc/termux/mirrors/default"
}

log_step 'Validando contexto real do app Termux'
if [ ! -d "/data/data/com.termux/files/usr" ] || [ "${PREFIX:-}" != "/data/data/com.termux/files/usr" ] || ! command -v pkg >/dev/null 2>&1; then
  fail \
    "validação do ambiente Termux" \
    "Este bootstrap deve ser executado dentro do app Termux recém-instalado." \
    "O script não está no contexto real necessário para reinstalar a stack do projeto." \
    "Abrir o app Termux e executar manualmente bash /data/local/tmp/install_termux_repo_bootstrap.sh."
fi

log_step 'Validando payload principal em /data/local/tmp'
if [ ! -f "$MAIN_PAYLOAD" ]; then
  fail \
    "test -f \"$MAIN_PAYLOAD\"" \
    "Payload principal ausente em $MAIN_PAYLOAD." \
    "O bootstrap não consegue delegar para a instalação completa do projeto." \
    "Rodar novamente o script host-side para reenviar os payloads ao dispositivo."
fi

if [ ! -r "$MAIN_PAYLOAD" ]; then
  fail \
    "test -r \"$MAIN_PAYLOAD\"" \
    "Payload principal sem permissão de leitura para o app Termux." \
    "O bootstrap não consegue delegar para a instalação completa do projeto." \
    "Reexecutar o script host-side ou corrigir as permissões do payload em /data/local/tmp."
fi

log_step 'Fixando mirror default do Termux antes do primeiro pkg'
prime_termux_repos

log_step 'Delegando para o payload principal do projeto'
printf 'Bootstrap do repositório validado no Termux.\n'
printf 'Payload principal: %s\n' "$MAIN_PAYLOAD"

exec bash "$MAIN_PAYLOAD"
