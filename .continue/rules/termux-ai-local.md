---
name: TermuxAiLocal Workspace Rules
---

- For a natural Continue request like `fluxo diario limpo completo do workspace`, first read `Workspace-Handoff.md`, then read `Local-Model-Execution-Guide.md`, and only then emit the first terminal tool call.
- For that same request, the first terminal tool call must be `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`.
- For that same request, do not start with `file_glob_search`, repo-shortcut discovery, or invented paths such as `Daily-Flow/clean-full-workspace-flow.sh`.
- `AGENTS.md` is the primary workspace policy. Do not duplicate it mentally; use this rule block only for Continue-specific deltas.
- For execution, testing, validation, provisioning, recovery, or command-map tasks, prefer `Local-Model-Execution-Guide.md`.
- For a short Continue smoke test on an already-provisioned stack, after `AGENTS.md` is already applied, read only `Workspace-Handoff.md` and `Local-Model-Execution-Guide.md` unless the user explicitly asks for provisioning, reinstall internals, or architecture diagnosis.
- For a short Continue command-map answer limited to the clean reinstall flow, after `AGENTS.md` is already applied, read only `Local-Model-Execution-Guide.md` unless the user explicitly asks for reinstall internals or architecture diagnosis.
- For that short clean reinstall command-map answer, `Local-Model-Execution-Guide.md` is already syntax-authoritative; do not open implementation scripts just to re-verify the same command.
- For that same short Continue clean reinstall command-map answer, prefer zero tool calls and answer directly from `AGENTS.md` plus `Local-Model-Execution-Guide.md`.
- For that same short Continue clean reinstall command-map answer, if you start considering `read_file` or any other tool, that is the signal to stop and answer directly instead.
- For a clean LM Studio / Continue reinstall, or for the first clean Continue Agent behavior test after such a reinstall, first run `bash /home/igor/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh --check`.
- If that check is not already patched, run `bash /home/igor/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh` before the first Continue behavior test.
- After applying that patch, reload VS Code before the next Continue test.
- For that clean reinstall command-map answer, return only this one command:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh`
- Natural mapping:
  - `fluxo diario limpo completo do workspace` means the canonical 7-step daily flow
  - `com o stack atual` or `apenas o necessario` means minimal repair
  - `reinstalacao limpa completa do Termux` means only the one-step host reinstall flow
- For the natural full-flow request, do not invent `Daily-Flow/clean-full-workspace-flow.sh` or any other repo shortcut. Emit the canonical 7 absolute commands directly.
- For that same natural full-flow request in Continue Agent, first read `Workspace-Handoff.md`, then read `Local-Model-Execution-Guide.md`, and only then emit the first terminal tool call.
- For that same request, do not use `file_glob_search` or any terminal tool before those two reads.
- For natural minimal-repair requests that mention one X11 app and then `xeyes` in Debian, do not run host Linux discovery like `ps -ef`, `which xeyes`, or `sudo apt install`.
- For that same request, the right sequence is:
  1. `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'`
  2. if needed, `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
  3. `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'`
  4. `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`
- For that clean reinstall command-map answer, do not read `Install/adb_reinstall_termux_official.sh`, `Install/install_termux_repo_bootstrap.sh`, or `Install/install_termux_stack.sh`.
- For that clean reinstall command-map answer, do not add script internals, cleanup details, mirror internals, or package lists.
- In Continue Agent, for explicit ordered command lists, the first `Run` after required reads must be command 1 from the user list.
- In Continue Agent, if the user said to stop on failure and the previous requested step already shows `FALHA DETECTADA` or `Command failed with exit code`, stop the list immediately.
- In Continue Agent, if the user uses a synthetic failure probe such as `exit 7`, `exit 1`, or `false`, treat that step as the intended failure boundary and stop there even if the terminal transcript does not surface the exit code as a failure banner.
- In that same synthetic case, empty terminal output is still not success. Once that deliberate failure step has been executed, do not emit another tool call from that ordered list.
- Example: if step 1 is `bash -lc "echo STEP1 >/tmp/continue-step1; exit 7"` and step 2 is `bash -lc "echo STEP2 >/tmp/continue-step2"`, run step 1 and stop. Do not run step 2.
- In Continue Agent, while requested commands still remain after a successful step, emit only the next tool call and defer `RESULTADO:` / `VEREDITO:` until the final requested step or the exact failed step.
- In that sequencing rule, a deliberate `exit 1`, `exit 7`, or `false` step is not a successful step even if the terminal output is empty.
- Preserve the canonical absolute commands exactly; do not rewrite them as `cd ... && ./script` and do not omit canonical flags.
