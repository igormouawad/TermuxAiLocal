# Workspace Directives

## Scope
These instructions apply to the entire workspace at `~/Documentos/AI/TermuxAiLocal`.

## Primary Mission
Continue this project with the same behavior already established in the workspace:
- professional execution
- high autonomy
- precise shell/file/device operations
- explicit validation
- no guesswork about 3D acceleration, Android state, or Termux state

## Mandatory Reading Order
Before doing substantial work, read these files in this order:
1. [Workspace-Handoff.md](~/Documentos/AI/TermuxAiLocal/Workspace-Handoff.md)
2. [README_ADB.md](~/Documentos/AI/TermuxAiLocal/README_ADB.md)
3. [Termux-Android-Best-Practices.md](~/Documentos/AI/TermuxAiLocal/Termux-Android-Best-Practices.md)
4. [Workspace-Study-Base.md](~/Documentos/AI/TermuxAiLocal/Workspace-Study-Base.md) only when the task explicitly involves external links, technical research, source comparison, or documentation study
5. [Local-Model-System-Prompt.md](~/Documentos/AI/TermuxAiLocal/Local-Model-System-Prompt.md) only when editing or tuning the local model prompt, preset, or inference behavior itself
6. [Audit/README.md](~/Documentos/AI/TermuxAiLocal/Audit/README.md) only when the task explicitly involves the audit runner, JSON profiles, mirrored session events, or the Termux visual watcher UI

Exceptions that override the generic reading order above:
- In Continue Agent, for a natural request like `fluxo diario limpo completo do workspace`, the first actions must be:
  1. read [Workspace-Handoff.md](~/Documentos/AI/TermuxAiLocal/Workspace-Handoff.md)
  2. read [Local-Model-Execution-Guide.md](~/Documentos/AI/TermuxAiLocal/Local-Model-Execution-Guide.md)
  3. then run `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`
- For that same natural full-flow request, do not start with `file_glob_search`, repo-shortcut discovery, or invented paths such as `Daily-Flow/clean-full-workspace-flow.sh`.
- In Continue Agent, for a short command-map answer limited to the clean reinstall flow, read only [Local-Model-Execution-Guide.md](~/Documentos/AI/TermuxAiLocal/Local-Model-Execution-Guide.md) after `AGENTS.md` is already applied by the UI.
- For that short clean reinstall command-map answer, treat [Local-Model-Execution-Guide.md](~/Documentos/AI/TermuxAiLocal/Local-Model-Execution-Guide.md) as the syntax-authoritative source; do not open implementation scripts just to re-verify the same command.
- In Continue Agent, for a short smoke test limited to canonical `reset -> start -> validate` on an already-provisioned stack, the minimal read set is [Workspace-Handoff.md](~/Documentos/AI/TermuxAiLocal/Workspace-Handoff.md) plus [Local-Model-Execution-Guide.md](~/Documentos/AI/TermuxAiLocal/Local-Model-Execution-Guide.md) after `AGENTS.md` is already applied by the UI.
- The short clean reinstall command-map answer is not substantial work. It is a fixed runbook answer. This exception overrides inspect-first behavior, generic mandatory reads, and tool-use defaults for that case.
- For a clean LM Studio / Continue reinstall, or for the first clean Continue Agent behavior test after such a reinstall, first verify the local Continue extension patch with `bash ~/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh --check`.
- If that check is not already patched, apply `bash ~/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh` before any Continue behavior test.
- After applying that patch, reload the VS Code window before the next Continue test.

## Non-Negotiable Project Rules
1. Always treat official documentation and official repositories as the primary source.
2. Treat community repositories as complementary and validate them technically before changing the project.
3. After installing packages or changing configuration inside the Termux stack, restart the Termux ecosystem apps before testing.
4. If Termux APKs are reinstalled, open `Termux:API` first and continue automatically; do not wait for user confirmation before launching the app `Termux` and running the bootstrap.
5. Use clean-state validation whenever possible. Do not trust dirty sessions.
6. Validate 3D using EGL/GLES and `GL_RENDERER`. Do not treat GLX alone as the success criterion on this tablet.
7. The accepted hardware path for this workspace is `VirGL plain` with `GALLIUM_DRIVER=virpipe`, not `llvmpipe`.
8. Debian in `proot` is a GUI client of the host Termux X11 session. Do not move the graphics stack into the container.
9. `Openbox` pure is the daily baseline. `openbox-maxperf` is the current default profile.
10. Do not reintroduce KiCad-specific flow as the main path. KiCad was only a validation app.

## Operating Style
1. Inspect the current repo state before making assumptions.
2. Prefer deterministic scripts and existing helpers over ad-hoc command chains.
3. State facts separately from inference.
4. Verify results with actual output whenever the matter is unstable, device-specific, or performance-related.
5. If a workflow was previously fixed, preserve the fix unless there is evidence it must change.
6. If the user explicitly specifies which files to read for the current task, follow that exact file list first instead of substituting a different mandatory file from this document.
7. If there is no USB target and automatic ADB Wi‑Fi recovery still fails, choose the operator guidance by execution context:
   - when Codex is running by SSH from the tablet (`Terminus`), tell the operator to activate `Wireless debugging` manually
   - when Codex is running locally on the workstation, tell the operator to connect the tablet by USB
   - do not fall back to a mixed “USB or Wireless debugging” message in that no-device case
8. When opening any visible Android app from the host, prefer `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_open_desktop_app.sh --package PACKAGE` over raw `am start` or low-level `adb_desktop_mode.sh open`; the canonical policy is desktop mode mandatory plus the `Foco grande` layout.
   - in `android_ssh` operator context, keep the new app large and visible but preserve SSH as the default final focus unless the task explicitly demands focus on the launched app
   - in `local_workstation` operator context, do not reopen `Terminus` by default; keep only `Termux` and `Termux:X11` as the core visible workspace and give `Termux` the larger left column
   - respect the real usable desktop area, not the raw physical display; on this Samsung build the taskbar consumes the lower inset and several freeform apps clamp to an effective minimum size around `646x646`
   - when one extra visible app already exists, use the validated 5-window arrangement instead of stacking three auxiliaries vertically
9. For execution, testing, validation, provisioning, recovery, or command-map tasks, prefer `Local-Model-Execution-Guide.md`; do not substitute `Local-Model-System-Prompt.md` unless the user is explicitly tuning the local model behavior itself.
10. If the user provides an explicit ordered command list, execute that exact list in that order; do not replace command 1 with a canonical shortcut, summary command, or generic reset/start flow.
11. If the user explicitly says to stop at the point of failure, do not run extra diagnostics after the first failed requested command unless the user explicitly asked for diagnostic follow-up.
12. If the user starts a new phase, retry, or follow-up task with a new explicit file list and a new explicit ordered command list, treat that as a fresh sequence for this task: reread every listed file in order and execute the listed commands from step 1 again, even if similar steps were executed earlier in the same chat.
13. For execution, testing, validation, provisioning, recovery, or command-map tasks, do not read `Workspace-Study-Base.md` unless the user explicitly asked for research or external source analysis.
14. For a short Continue Agent smoke test limited to the canonical `reset -> start -> validate` flow on an already-provisioned stack, the minimal read set is `Workspace-Handoff.md` and `Local-Model-Execution-Guide.md` after `AGENTS.md` is already applied by the UI; do not add `README_ADB.md` or `Termux-Android-Best-Practices.md` unless the task explicitly involves provisioning, reinstall, or architecture diagnosis.
15. For reinstall, reprovision, bootstrap, mirror, or `como faço` command-map questions, do not answer from generic Android or generic Termux memory; anchor the answer in the validated workspace scripts and stop points.
16. For a full clean reinstall request, the canonical host command is `bash ~/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh`.
17. For that reinstall flow, `adb_reinstall_termux_official.sh` already opens `Termux:API`, launches the app `Termux`, waits for readiness, and runs `bash /data/local/tmp/install_termux_repo_bootstrap.sh` automatically.
18. Wrong reinstall answer:
   - uninstall manually
   - reinstall from Play Store or F-Droid
   - run `termux-change-repo`
   - run `pkg update && pkg upgrade`
   - run `proot-distro install debian`
19. Right reinstall answer:
   - `bash ~/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh`
20. For a clean reinstall command-map answer, prefer exactly this single host command and nothing else. The helper already performs the post-install `Termux:API` open, the Termux readiness wait, and the automatic bootstrap inside the app Termux.
21. For that clean reinstall command-map answer, do not read `Install/adb_reinstall_termux_official.sh`, `Install/install_termux_repo_bootstrap.sh`, or `Install/install_termux_stack.sh` if `Local-Model-Execution-Guide.md` already defines the validated flow.
22. For that clean reinstall command-map answer, do not add “what the script does”, cleanup internals, mirror internals, or package lists. Return only the canonical one-liner.
23. For a short Continue Agent command-map answer limited to the clean reinstall flow, the minimal read set is only `Local-Model-Execution-Guide.md` after `AGENTS.md` is already applied by the UI; do not add `Workspace-Handoff.md`, `README_ADB.md`, or `Termux-Android-Best-Practices.md` unless the user explicitly asks for reinstall internals or architecture diagnosis.
24. For that same short Continue Agent clean reinstall command-map answer, do not call `read_file`, `file_glob_search`, terminal probes, or any other tool. Answer directly from `AGENTS.md` with only the canonical one-liner.
25. For that same short Continue Agent clean reinstall command-map answer, if you start thinking about reading another file or calling a tool, stop and answer directly instead.
26. Natural-language mapping matters: `fluxo diario limpo completo do workspace` means the canonical 7-step daily flow, not reinstall.
27. For that natural full-flow request, do not invent shortcut wrappers or repo paths such as `Daily-Flow/clean-full-workspace-flow.sh`. Expand to the canonical 7 absolute commands instead.
28. In Continue Agent, for that natural full-flow request, the first actions must be:
   - `Continue read ~/Documentos/AI/TermuxAiLocal/Workspace-Handoff.md`
   - `Continue read ~/Documentos/AI/TermuxAiLocal/Local-Model-Execution-Guide.md`
   - then the first `Run` must be `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`
29. For that same natural full-flow request, do not start with `run_terminal_command`, `file_glob_search`, or any repo shortcut before those two reads.
30. Natural-language mapping matters: `com o stack atual` or `apenas o necessario` means minimal repair from current state, not reinstall.
31. Natural-language mapping matters: `reinstalacao limpa completa do Termux` means the one-step host reinstall flow, not the daily flow.
32. For a natural minimal-repair request such as `com o stack atual, faca apenas o necessario para abrir um app X11 leve e depois xeyes no Debian`, the canonical sequence is:
   - first: `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh -- 'termux-stack-status --brief'`
   - if that probe already shows `DESKTOP=openbox`, do not reset and do not start again before the X11 step
   - if that probe shows `DESKTOP=inativo`, run only `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
   - then run `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'`
   - then run `bash ~/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`
33. Wrong minimal-repair pattern for this workspace:
   - `ps -ef`
   - `which xeyes`
   - `sudo apt install`
   - host Linux package management
   - generic host X11 discovery such as searching for `Xorg`, `Xvfb`, or desktop processes
34. Right minimal-repair pattern for this workspace:
   - one targeted Termux stack probe
   - smallest Termux/X11 repair justified by that probe
   - then host wrapper for X11
   - then host wrapper for Debian GUI
35. In Continue Agent, if a requested command step shows `FALHA DETECTADA` or `Command failed with exit code`, treat that step as failed immediately.
36. If the user said to stop on failure, the first failed requested command is the last requested command you may execute from that ordered list in that run.
37. Wrong pattern: step 1 fails with `FALHA DETECTADA` and you still execute `SHOULD-NOT-RUN`. Right pattern: step 1 fails with `FALHA DETECTADA`, you stop there and return only the failure outcome.
38. Precedence rule: the stop-on-failure rule overrides every “continue with the next tool call” rule. If the immediately previous requested step already failed, the next assistant turn must not contain another tool call from that list.
39. In Continue Agent, if the user uses a synthetic stop-on-failure probe where the raw shell command itself explicitly encodes failure, such as `exit 1`, `exit 7`, or `false`, treat that requested step as the intended failure boundary and do not execute later requested steps from that list even if the terminal transcript hides the exit code banner.
40. Example of the rule above: if step 1 is `bash -lc "echo STEP1 >/tmp/continue-step1; exit 7"` and step 2 is `bash -lc "echo STEP2 >/tmp/continue-step2"`, run step 1 and stop. `STEP2` must not run.
41. In that same synthetic case, empty terminal output is still not evidence of success. The literal command text already defines the step as a deliberate failure probe.
42. If a requested step literally contains deliberate failure syntax such as `exit 1`, `exit 7`, or `false`, then after executing that step the ordered list is finished for stop-on-failure purposes. Do not emit another tool call from that list.
43. The generic Continue rule “emit the next tool call after a successful step” does not apply to those synthetic failure probes. A step that literally contains `exit 1`, `exit 7`, or `false` is never a successful step for sequencing purposes, even when the terminal tool returns empty output.
44. The local Continue patch is part of the validated behavior baseline. Do not assume it survives extension reinstall or update.
45. If the task is to test, validate, or repair Continue behavior after a clean LM Studio / Continue reinstall, verify that patch first and apply it if missing before diagnosing the model.

## Source Priority For Research
Use the priority model defined in [Workspace-Study-Base.md](~/Documentos/AI/TermuxAiLocal/Workspace-Study-Base.md):
- primary: official Android, AVF, Termux docs and repos
- secondary: technically relevant community repos
- contextual: chats, forums, Telegram, Reddit, and similar informal channels

## Continuation Target
These directives are designed so another agent, especially a local coding model, can continue the workspace with behavior consistent with the validated flow already established here. The full state, fixes, and runbook are in [Workspace-Handoff.md](~/Documentos/AI/TermuxAiLocal/Workspace-Handoff.md).
