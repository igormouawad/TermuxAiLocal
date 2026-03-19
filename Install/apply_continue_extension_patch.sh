#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Usage:
  bash ${WORKSPACE_ROOT}/Install/apply_continue_extension_patch.sh [--check] [--target /abs/path/to/extension.js]

Modes:
  --check   Only report whether the Continue extension patch is present.
  --target  Override the default Continue extension.js path discovery.

Default target discovery:
  $HOME/.vscode/extensions/continue.continue-*/out/extension.js
EOF
}

mode="apply"
target=""

while (($#)); do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --target)
      shift
      if (($# == 0)); then
        echo "Missing value for --target" >&2
        usage >&2
        exit 64
      fi
      target="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$target" ]]; then
  mapfile -t matches < <(compgen -G "$HOME/.vscode/extensions/continue.continue-*/out/extension.js" || true)
  if ((${#matches[@]} == 0)); then
    echo "PATCH_STATUS=missing" >&2
    echo "PATCH_TARGET=" >&2
    exit 2
  fi
  target="$(printf '%s\n' "${matches[@]}" | sort -V | tail -n 1)"
fi

python3 - "$target" "$mode" <<'PY'
from pathlib import Path
import sys

target = Path(sys.argv[1]).expanduser()
mode = sys.argv[2]

terminal_patch_marker = 'const failureBanner = `FALHA DETECTADA\\n- comando: ${command}'
webview_patch_marker = 'const isLargeStreamMessage = ["llm/streamChat", "chatDescriber/describe"].includes(msg.messageType);'

success_old = """const status = "Command completed";
                    resolve6([
                      {
                        name: "Terminal",
                        description: "Terminal command output",
                        content: terminalOutput,
                        status
                      }
                    ]);"""

success_new = """const status = "Command completed";
                    const content = terminalOutput || status;
                    resolve6([
                      {
                        name: "Terminal",
                        description: "Terminal command output",
                        content,
                        status
                      }
                    ]);"""

failure_old = """const status = `Command failed with exit code ${code}`;
                    resolve6([
                      {
                        name: "Terminal",
                        description: "Terminal command output",
                        content: terminalOutput,
                        status
                      }
                    ]);"""

failure_new = """const status = `Command failed with exit code ${code}`;
                    const failureBanner = `FALHA DETECTADA\\n- comando: ${command}\\n- erro: ${status}\\n- impacto: O comando falhou.\\n- proximo passo recomendado: Se o usuario pediu para parar na falha, nao execute o proximo comando solicitado.`;
                    const content = terminalOutput ? `${terminalOutput}${terminalOutput.endsWith("\\n") ? "" : "\\n"}${failureBanner}` : failureBanner;
                    resolve6([
                      {
                        name: "Terminal",
                        description: "Terminal command output",
                        content,
                        status
                      }
                    ]);"""

catch_old = """const status = `Command failed with: ${error44.message || error44.toString()}`;
              return [
                {
                  name: "Terminal",
                  description: "Terminal command output",
                  content: error44.stderr ?? error44.toString(),
                  status
                }
              ];"""

catch_new = """const status = `Command failed with: ${error44.message || error44.toString()}`;
              const failureBanner = `FALHA DETECTADA\\n- comando: ${command}\\n- erro: ${status}\\n- impacto: O comando falhou.\\n- proximo passo recomendado: Se o usuario pediu para parar na falha, nao execute o proximo comando solicitado.`;
              const content = error44.stderr ? `${error44.stderr}${error44.stderr.endsWith("\\n") ? "" : "\\n"}${failureBanner}` : failureBanner;
              return [
                {
                  name: "Terminal",
                  description: "Terminal command output",
                  content,
                  status
                }
              ];"""

webview_old = """              const stringified = JSON.stringify({ msg }, null, 2);
              console.error(
                `Error handling webview message: ${stringified}

${e22}`
              );
              if (stringified.includes("llm/streamChat") || stringified.includes("chatDescriber/describe")) {
                return;
              }"""

webview_new = """              const isLargeStreamMessage = ["llm/streamChat", "chatDescriber/describe"].includes(msg.messageType);
              const loggedPayload = isLargeStreamMessage ? JSON.stringify({
                messageType: msg.messageType,
                messageId: msg.messageId,
                title: msg.data?.title ?? null,
                messagesCount: Array.isArray(msg.data?.messages) ? msg.data.messages.length : void 0
              }, null, 2) : JSON.stringify({ msg }, null, 2);
              console.error(
                `Error handling webview message: ${loggedPayload}

${e22}`
              );
              if (isLargeStreamMessage) {
                return;
              }"""

if not target.exists():
    print("PATCH_STATUS=missing")
    print(f"PATCH_TARGET={target}")
    sys.exit(2)

text = target.read_text(encoding="utf-8")
terminal_patched = terminal_patch_marker in text
terminal_patchable = all(snippet in text for snippet in (success_old, failure_old, catch_old))
webview_patched = webview_patch_marker in text
webview_patchable = webview_old in text

if terminal_patched and webview_patched:
    state = "patched"
elif (terminal_patched or terminal_patchable) and (webview_patched or webview_patchable):
    state = "unpatched"
else:
    state = "unsupported"

print(f"PATCH_STATUS={state}")
print(f"PATCH_TARGET={target}")

if mode == "check":
    sys.exit(0 if state == "patched" else 1)

if state == "patched":
    print("PATCH_APPLY=already_patched")
    sys.exit(0)

if state != "unpatched":
    print("PATCH_APPLY=unsupported_layout")
    sys.exit(3)

if terminal_patchable:
    text = text.replace(success_old, success_new, 1)
    text = text.replace(failure_old, failure_new, 1)
    text = text.replace(catch_old, catch_new, 1)

if webview_patchable:
    text = text.replace(webview_old, webview_new, 1)

if terminal_patch_marker not in text or webview_patch_marker not in text:
    print("PATCH_APPLY=failed_verification")
    sys.exit(4)

target.write_text(text, encoding="utf-8")
print("PATCH_APPLY=applied")
PY
