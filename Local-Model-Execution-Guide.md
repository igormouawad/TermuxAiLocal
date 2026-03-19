# Local Model Execution Guide

## Purpose
This file is the short command-level runbook for this workspace.

Use it for:
- exact commands
- execution contexts
- canonical flow mapping
- validated stop points

For command-map answers, the canonical commands written in this file are already syntax-authoritative. Do not open implementation scripts just to re-verify the same commands.

## Critical Continue Priorities
- For a natural Continue request like `fluxo diario limpo completo do workspace`, first read `Workspace-Handoff.md`, then read this file, and only then emit the first terminal tool call.
- For that same full-flow request, the first terminal tool call must be `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`.
- For that same full-flow request, do not start with `file_glob_search`, repo-shortcut discovery, or invented paths such as `Daily-Flow/clean-full-workspace-flow.sh`.
- For a short Continue smoke test on an already-provisioned stack, read only `Workspace-Handoff.md` and this file after `AGENTS.md` is already applied.
- For a short Continue command-map answer limited to the clean reinstall flow, read only this file after `AGENTS.md` is already applied.
- For that same short Continue clean reinstall command-map answer, prefer zero tool calls and answer directly from `AGENTS.md` plus this file.
- For that same short Continue clean reinstall command-map answer, considering `read_file` is already the wrong branch; answer directly instead.
- For a clean LM Studio / Continue reinstall, or for the first clean Continue Agent behavior test after such a reinstall, verify the local Continue extension patch before any Continue behavior test.
- Canonical check command:
  - `bash ~/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh --check`
- If that check is not already patched, apply:
  - `bash ~/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh`
- After applying that patch, reload VS Code before the next Continue test.
- For `fluxo diario limpo completo`, execute the full canonical 7-step flow, not the shorter 3-step smoke test.
- For that full-flow request, do not invent a shortcut script path such as `Daily-Flow/clean-full-workspace-flow.sh`; emit the 7 canonical absolute commands directly.
- In Continue Agent, for that full-flow request, read `Workspace-Handoff.md` and this file before the first terminal tool call.
- For natural recovery requests such as `com o stack atual` or `apenas o necessario`, prefer one targeted state check plus the smallest verified repair instead of a full reset.
- For a natural minimal-repair request that explicitly wants one X11 app and then one Debian GUI app, do not branch into generic host Linux discovery or package management; use the Termux stack probe plus the canonical wrappers.
- For explicit ordered command lists with `pare na primeira falha`, stop immediately after the first requested command that shows `FALHA DETECTADA` or `Command failed with exit code`.
- For explicit ordered command lists with `pare na primeira falha`, if a raw shell step itself is an intentional non-zero-exit probe such as `exit 7`, `exit 1`, or `false`, stop after that step even if the Continue terminal transcript does not print the exit code cleanly.
- For that same synthetic stop-on-failure case, empty terminal output is still not success. The command text already marks that executed step as the failure boundary.
- Example: if step 1 is `bash -lc "echo STEP1 >/tmp/continue-step1; exit 7"` and step 2 is `bash -lc "echo STEP2 >/tmp/continue-step2"`, run step 1 and stop. Do not run step 2.

## Read This Before Acting
For substantial work:
1. `AGENTS.md`
2. `Workspace-Handoff.md`
3. `README_ADB.md`
4. `Termux-Android-Best-Practices.md`
5. this file
6. `Workspace-Study-Base.md` only for research or external source analysis

For command-level workflow, testing, execution, validation, provisioning, recovery, or command-map answers:
- this file is mandatory
- `Local-Model-System-Prompt.md` does not replace this file
- answer from the validated workspace helpers, not from generic Android or generic Termux memory

## Inspection Budget
- Read the mandatory files first and stop exploring if they already answer the workflow.
- For a short Continue smoke test limited to canonical `reset -> start -> validate`, do not add `README_ADB.md` or `Termux-Android-Best-Practices.md` unless the task explicitly involves reinstall, provisioning, or architecture diagnosis.
- For a short Continue clean reinstall command-map answer, do not add `Workspace-Handoff.md`, `README_ADB.md`, or `Termux-Android-Best-Practices.md`.
- If the user provides an explicit ordered command list, command 1 must be the first shell action after the required file reads unless a real blocker exists.
- Do not insert `cd ... && pwd`, bare `pwd`, `ls`, `find`, or `grep` before command 1 of an explicit list.
- Do not read implementation files when this runbook already defines the validated flow.
- Do not probe the same large file many times just to restate the same fact.
- For Continue behavior repair after LM Studio / Continue reinstall, do not patch the extension manually in place from memory if the workspace helper already exists. Use the canonical helper above.

## Execution Contexts

### Host shell
This is the Linux workstation shell.

Use it for:
- `ADB/*.sh`
- `Install/*.sh`
- `Debian/*.sh`
- screenshots and Android-side orchestration

### Android `adb shell`
This is not the real Termux app shell.

Use it only for:
- `dumpsys`
- package checks
- task and window inspection
- screenshots

### Real shell inside the Termux app
Device selection:
- explicit `TERMUXAI_DEVICE_ID=SERIAL` or `--device SERIAL` still wins
- without an explicit selection, host wrappers prefer a directly connected USB target
- if USB is absent, host wrappers try a single network/Wi‑Fi target
- ambiguous cases still fail and require `TERMUXAI_DEVICE_ID=SERIAL` or `--device SERIAL`

Host wrapper:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'
```

Default mode:
- standard synchronous mode

Reserve `--interactive-shell` for:
- `pkg`
- `proot-distro`
- manual bootstrap commands the user explicitly wants inside the visual Termux prompt
- helpers that depend on the visible session env

### X11 app context on display `:1`
Host wrapper:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'
```

### Debian GUI client context
Termux-side launcher:

```bash
run-gui-debian --label XEyes -- xeyes
```

From the host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'
```

## Non-Negotiable Rules
- Do not treat `adb shell` as the real Termux shell.
- Do not treat “desktop opened” as proof of 3D acceleration.
- Validate 3D with EGL/GLES and `GL_RENDERER`.
- Accept `virgl`.
- Reject `llvmpipe`.
- Debian is a GUI client of the host X11 session.
- Do not move the graphics stack into Debian.
- `Openbox` pure is the daily baseline.
- `openbox-maxperf` is the default profile.
- After reinstalling Termux APKs, open `Termux:API` and continue automatically into the app `Termux`; do not wait for user confirmation before the bootstrap.

## Canonical Host Commands
- Clean reset:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux
```

This reset now rebuilds the approved Samsung desktop mode/freeform layout instead of any legacy Android split layout.

- Start validated desktop:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox
```

- Authoritative baseline validation:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report
```

- Real Termux shell probe from host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'
```

- Host-side X11 app launch:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'
```

- Consolidate the approved Android freeform desktop layout:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_consolidate_freeform_desktop.sh --focus ssh
```

- Debian GUI app from host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'
```

## Canonical Natural Flow Mapping

### Full clean flow
Natural requests such as `fluxo diario limpo completo` mean this exact 7-step order:
Preparation in Continue Agent:
1. `Continue read ~/Documentos/AI/TermuxAiLocal/Workspace-Handoff.md`
2. `Continue read ~/Documentos/AI/TermuxAiLocal/Local-Model-Execution-Guide.md`

Runtime order:
1. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`
2. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
3. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report`
4. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'`
5. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
6. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'`
7. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`

Wrong branch for that same request:
- `Daily-Flow/clean-full-workspace-flow.sh`
- any invented repo shortcut
- `cd ... && ./script` in place of the canonical absolute commands
- `file_glob_search` before the two required Continue reads

Reason:
- step 3 may leave `DESKTOP=inativo`
- therefore step 5 is required before later X11 and Debian GUI probes

### Short smoke test
Natural requests such as `smoke test canonico` mean this exact 3-step order:
1. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`
2. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
3. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report`

### Minimal repair
Natural requests such as `com o stack atual` or `apenas o necessario` mean:
1. inspect current state with one targeted probe
2. apply the smallest verified repair
3. do not reset the whole ecosystem unless the probe justifies it

For the concrete natural request `com o stack atual, faca apenas o necessario para abrir um app X11 leve e depois xeyes no Debian`, the canonical order is:
1. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'`
2. if step 1 already shows `DESKTOP=openbox`, do not reset and do not start again yet
3. if step 1 shows `DESKTOP=inativo`, run `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
4. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'`
5. `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`

Wrong branch for that same request:
- `ps -ef`
- `which xeyes`
- `sudo apt install`
- host X11 discovery
- host desktop discovery

## Clean APK Reinstall Flow
The canonical clean reinstall answer is exactly this one host command:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh
```

What the helper does after reinstalling the APKs:
- opens `Termux:API`
- launches the app `Termux`
- waits for the real Termux shell to become ready
- runs `bash /data/local/tmp/install_termux_repo_bootstrap.sh` automatically

For this answer:
- do not call `read_file`
- do not call `file_glob_search`
- do not call terminal probes
- do not read `Install/adb_reinstall_termux_official.sh`
- do not read `Install/install_termux_repo_bootstrap.sh`
- do not read `Install/install_termux_stack.sh`
- do not explain cleanup internals, package lists, mirror internals, or the automatic bootstrap details unless the user explicitly asks for internals
- do not replace this flow with Play Store, F-Droid, `termux-change-repo`, or generic `pkg update`

## Debian Flow
Provision payloads from host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Debian/adb_provision_debian_trixie_gui.sh
```

Install from host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/Debian/adb_install_debian_trixie_gui.sh
```

Restart the Termux ecosystem after Debian install:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox
```

Launch Debian GUI app from host:

```bash
bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'
```

## Success Signatures
- baseline report: `status=success`
- desktop: `OPENBOX_PROFILE_OK PROFILE=openbox-maxperf`
- display: `Display unificado: :1`
- 3D: `GL_RENDERER: virgl`
- Debian GUI: launcher message succeeded and a real process exists

## Warnings That Are Not Automatic Failure
- GLX instability on this tablet
- `glxinfo exit code: 139`
- `es2gears_x11 exit code: 124`
- `libEGL warning: DRI3 error`

These warnings are acceptable if EGL/GLES still reports `virgl`.

## Failure Handling
- After package or config changes, restart the Termux ecosystem before validation.
- If `adb_provision.sh` ran, stop and wait for the manual bootstrap inside the real Termux app before continuing.
- If the user asked to stop on failure, do not run diagnostics after the first failed requested command unless the user explicitly asked for diagnostics.
- If a wrapper already exists for the job, use the wrapper instead of inventing a new chain of raw commands.

## Continue Agent Explicit Lists
- Required file reads already satisfy the initial inspection requirement.
- After those reads, command 1 must run immediately unless a real blocker exists.
- While requested commands remain, keep emitting the next tool call instead of replacing it with a final text summary.
- If the user asks for `RESULTADO:` and `VEREDITO:` after each step, keep those summaries short and do not let them replace the next required tool call.
- In Continue, `Run` and `Continue read` are the primary execution transcript.
- For explicit ordered lists with `pare na primeira falha`, a deliberate `exit 1|7` or `false` step is not successful merely because the terminal tool returned no text.
- Therefore the generic sequencing rule “after a successful step, emit the next tool call” applies only to ordinary successful steps. It does not apply to deliberate failure probes.
- The validated local Continue behavior also depends on the workspace helper `Install/apply_continue_extension_patch.sh`. After clean extension reinstall or update, reapply it before relying on Continue stop-on-failure behavior.

## Continue UI Notes
- Reliable command-palette command to focus the input:
  - `Continue: Add to Chat`
- Reliable command-palette command for a fresh chat:
  - `Continue: New Session`
- Use `Enter` to submit.
- Use `Ctrl+Enter` to interrupt generation.
