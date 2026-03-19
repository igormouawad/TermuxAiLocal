# Workspace Handoff

## Purpose
This file is the short continuity package for the current validated state of the workspace.

Use it for:
- current state
- canonical commands
- current Continue behavior
- open issues that still matter

Do not treat this file as a historical changelog.

## Current Script Audit State
- Workspace migration state is now consolidated for active tooling:
  - the workspace itself no longer contains references to the pre-`AI/` project root
  - active Codex state now points to `/home/igor/Documentos/AI/TermuxAiLocal`
  - stale VS Code `workspaceStorage` for the old TermuxAiLocal root was removed
  - the current Codex thread entry was retargeted to the new root in `~/.codex/state_5.sqlite`
  - if a future Codex prompt still offers an old workspace, treat that as stale log/history noise first, not validated active state
- Session closure state for this round:
  - consolidated backup created at:
    - `/home/igor/Documentos/Backups/TermuxAiLocal-gtp-5.4-xhigh-fast-v6-consolidated-20260319-112100.tar.gz`
    - checksum:
      - `/home/igor/Documentos/Backups/TermuxAiLocal-gtp-5.4-xhigh-fast-v6-consolidated-20260319-112100.tar.gz.sha256`
  - active configuration/state validation passed for:
    - `/home/igor/.codex/config.toml`
    - `/home/igor/.codex/rules/default.rules`
    - `/home/igor/.codex/history.jsonl`
    - `/home/igor/.config/Code/User/globalStorage/storage.json`
    - `~/.codex/state_5.sqlite` logical thread state
  - the current Codex thread now resolves to `/home/igor/Documentos/AI/TermuxAiLocal`
  - this workspace is not a Git repository, so this closure round was validated by path scans and state inspection instead of `git status`
  - residual references to the pre-`AI/` root may still exist in append-only historical logs such as `~/.codex/log/codex-tui.log` or old VS Code log directories; these are not active workspace-selection state
- The latest pre-refactor backup after moving the workspace under `AI/` was created at:
  - `/home/igor/Documentos/Backups/TermuxAiLocal-gtp-5.4-xhigh-fast-v5-moved-20260319-102313.tar.gz`
  - checksum:
    - `/home/igor/Documentos/Backups/TermuxAiLocal-gtp-5.4-xhigh-fast-v5-moved-20260319-102313.tar.gz.sha256`
- The host now has `shellcheck 0.10.0` installed for static auditing.
- The latest script refactor round focused on removing duplication in the validated host-side paths, without changing canonical commands:
  - `lib/termux_common.sh`
  - `ADB/adb_start_desktop.sh`
  - `ADB/adb_validate_baseline.sh`
  - `workspace_host_menu.sh`
  - `Install/termux_workspace_menu.sh`
  - `Install/install_termux_stack.sh`
- Key structural changes:
  - desktop profile / WM / start / stop / expectation logic is now centralized in `lib/termux_common.sh`
  - `adb_start_desktop.sh` now uses the shared desktop helpers and no longer repeats identical branches
  - `adb_validate_baseline.sh` no longer duplicates desktop mapping logic and no longer keeps two nearly identical Termux command wrappers
  - `workspace_host_menu.sh` and `termux_workspace_menu.sh` now use small generic runner helpers instead of repeating many near-identical handlers
  - `install_termux_stack.sh` had small cleanup for logging helpers
- Important no-regression decision:
  - a live probe confirmed that `adb_termux_send_command.sh --interactive-shell -- 'termux-stack-status --brief'` is still fragile on the current device state
  - therefore `adb_validate_baseline.sh` was intentionally kept on the already validated `run-as+spool` path for its Termux commands
  - do not migrate baseline/start flows to `--interactive-shell` unless that transport is fixed first
- Static validation after the refactor:
  - `bash -n` passed on all repo `*.sh` files
  - `shellcheck` is clean on the main refactored files except for informational SC2016 cases where literal shell lines are intentionally written into other files
- Runtime validation after the refactor:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --device RX2Y901WJ2E -- 'termux-stack-status --brief'`: passed
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`: passed
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report`: passed
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/workspace_host_menu.sh --run daily_flow --yes`: passed after the workspace move
  - latest baseline report:
    - `/home/igor/Documentos/AI/TermuxAiLocal/ADB/reports/validate-baseline-20260319-105623/summary.txt`
  - updated Termux menu was redeployed and validated with:
    - `termux-workspace-menu --list`
  - clean reinstall helper now also passed end-to-end with automatic post-install continuation:
    - automatic reboot when orphaned Termux/X11 processes survived uninstall
    - automatic open of `Termux:API`
    - automatic launch of the app `Termux`
    - automatic execution of `bash /data/local/tmp/install_termux_repo_bootstrap.sh`
    - baseline revalidation after reinstall
    - Debian GUI reprovision plus `xeyes` validation after reinstall

## Workspace Identity
- Root: `/home/igor/Documentos/AI/TermuxAiLocal`
- Main Android device: `RX2Y901WJ2E`
- Host: Linux workstation
- Daily desktop baseline: `Openbox`
- Daily profile: `openbox-maxperf`
- Accepted 3D path: `VirGL plain` with `GALLIUM_DRIVER=virpipe`
- Display baseline: `Termux:X11` on `DISPLAY=:1`

## Current LM Studio State
- LM Studio UI is installed from `LM-Studio-0.4.6-1-x64.AppImage`.
- The selected model is `lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-GGUF` in `Q6_K`.
- The validated model load state is:
  - `n_parallel = 1`
  - `n_ctx = 49152`
  - `n_seq_max = 1`
  - `n_slots = 1`
- The current Continue binding in `/home/igor/.continue/config.yaml` is:
  - `provider = openai`
  - `model = qwen3-coder-30b-a3b-instruct`
  - `apiBase = http://127.0.0.1:1234/v1`
  - `temperature = 0.0`
  - `topP = 0.1`
  - `topK = 1`
  - `maxTokens = 384`
- The local Continue extension patch helper is:
  - `/home/igor/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh`
- That helper now patches two Continue extension behaviors:
  - terminal failures always surface a visible `FALHA DETECTADA` banner in tool output
  - `llm/streamChat` and `chatDescriber/describe` webview errors log only compact metadata instead of stringifying the full message payload
- Canonical patch check:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh --check`
- Canonical patch apply:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh`

## Canonical Host Commands
- Interactive host menu:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/workspace_host_menu.sh`
- Clean reset:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`
- Start validated desktop:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
- Authoritative baseline validation:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report`
- Real Termux command from host:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --device RX2Y901WJ2E --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`
- Host-side X11 app launch:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'`
- Hard close of the Android `Termux:X11` app:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_stop_termux_x11.sh`

## Clean Daily Flow
The natural full flow is 7 steps:
1. `adb_reset_termux_stack.sh --focus termux`
2. `adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
3. `adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report`
4. `adb_termux_send_command.sh --device RX2Y901WJ2E -- 'termux-stack-status --brief'`
5. `adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
6. `adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'`
7. `adb_termux_send_command.sh --device RX2Y901WJ2E --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`

Reason:
- `adb_validate_baseline.sh` may finish with the tested desktop stopped
- so a new desktop start may be required before later X11 or Debian GUI probes

## Clean Reinstall Flow
The canonical clean reinstall answer is exactly this one host command:
1. `bash /home/igor/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh`

Important:
- do not replace this with Play Store or F-Droid advice
- do not answer with `termux-change-repo`
- do not answer with `pkg update && pkg upgrade`
- do not answer with `proot-distro install debian`
- the helper now opens `Termux:API`, launches `Termux`, waits for the shell to become ready, and runs `bash /data/local/tmp/install_termux_repo_bootstrap.sh` automatically
- if orphaned Termux/X11/GUI processes survive uninstall and Android blocks clean ADB termination, the helper now reboots the device automatically and resumes the reinstall

## Reinstall And Mirror State
- The clean reinstall helper is:
  - `/home/igor/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh`
- The bootstrap payload now fixes Termux mirrors before the first `pkg` operation.
- The fixed mirror is `packages-cf.termux.dev`.
- The bootstrap writes:
  - `sources.list`
  - `mirrors/default`
  - `chosen_mirrors`
- It also exports `TERMUX_PKG_NO_MIRROR_SELECT=1`.
- Result already validated:
  - clean reinstall no longer falls into mirror benchmark/testing during bootstrap

## Current Validated Android / Termux State
- Clean reinstall of `com.termux`, `com.termux.api`, and `com.termux.x11` was revalidated.
- Clean reinstall state now enforces zero-state before APK install.
- A reboot may be required when orphaned processes survive uninstall.
- After clean reinstall, there is no longer a manual stop point at `Termux:API`; the validated flow continues automatically into the real app `Termux` and runs the bootstrap.
- The validated automatic reinstall helper now handles both unstable branches seen in practice:
  - a freshly reinstalled app shell not yet ready for `run-as+spool`
  - orphaned Termux/X11/proot GUI processes that only disappear after a device reboot
- The current payloads also ship the Termux-side interactive menu:
  - source in repo: `/home/igor/Documentos/AI/TermuxAiLocal/Install/termux_workspace_menu.sh`
  - installed helper in Termux: `~/bin/termux-workspace-menu`
- The new workspace menus were validated end-to-end:
  - host menu list: `workspace_host_menu.sh --list`
  - host menu run: `workspace_host_menu.sh --run stack_status --yes`
  - Termux menu deploy: `workspace_host_menu.sh --run deploy_termux_menu --yes`
  - Termux menu list: `termux-workspace-menu --list`
  - Termux menu run: `termux-workspace-menu --run status_brief --yes`

## Current Validated Baseline State
- Baseline post-reinstall validation passed.
- Latest authoritative baseline report:
  - `/home/igor/Documentos/AI/TermuxAiLocal/ADB/reports/validate-baseline-20260319-105623/summary.txt`
- Expected success markers:
  - `status=success`
  - `Display unificado: :1`
- `Openbox profile: openbox-maxperf`
- `Virgl/EGL: OK`
- `GL_RENDERER: virgl`
- Current live stack probe after Debian reprovision:
  - `X11=display-ready VIRGL=ativo MODE=plain DESKTOP=openbox WM=openbox RES=1280x720 PROFILE=performance OPENBOX_PROFILE=openbox-maxperf DRIVER=virgl-plain DBUS=active DISPLAY=:1`
- Debian GUI was reinstalled after the clean Termux APK reinstall and revalidated with:
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/Debian/adb_provision_debian_trixie_gui.sh`
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/Debian/adb_install_debian_trixie_gui.sh`
  - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_termux_send_command.sh --device RX2Y901WJ2E --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`

## Latest Host / Device Fixes
- The launcher catalog on the live device was pruned again and dead entries were removed from the exported Debian app set.
- The current useful Debian launcher exports now include:
  - `FreeCAD`
  - `KiCad`
  - `KiCad Gerber Viewer`
  - `KiCad Image Converter`
  - `KiCad PCB Calculator`
  - `KiCad PCB Editor (Standalone)`
  - `KiCad Schematic Editor (Standalone)`
  - `Thunar File Manager`
  - `Bulk Rename`
- A keyboard regression on the Android host was investigated after the physical `m` key stopped working.
- The validated cause was Android accessibility mouse keys, not Openbox or Termux:X11.
- Verified host setting found during the incident:
  - `accessibility_mouse_keys_enabled=1`
- The setting was reverted and revalidated:
  - `adb shell settings get secure accessibility_mouse_keys_enabled`
  - current validated value: `0`
- Termux:X11 pointer-related prefs at the time of validation were:
  - `showMouseHelper=false`
  - `pointerCapture=false`
  - `preferScancodes=false`
- This means the validated fix was on the Android host accessibility layer, not in the workspace Openbox config.

## Openbox Desktop Research Direction
- Goal now is no longer just "Openbox starts".
- Goal now is a functional native Openbox desktop on host Termux, still using `Termux:X11` on `:1`.
- Primary official anchors:
  - `termux/termux-x11`
  - `termux/termux-packages` openbox package
  - `termux/proot-distro`
- Important official finding:
  - Openbox autostart and environment are run by `openbox-session`, not by raw `openbox`
  - the current workspace launcher still executes raw `openbox --sm-disable`
  - this likely explains why the desktop is validated but still minimal
- Practical implication:
  - the next implementation should pivot the launcher toward `openbox-session` semantics and user config in `~/.config/openbox`
  - likely files to manage:
    - `~/.config/openbox/autostart`
    - `~/.config/openbox/menu.xml`
    - `~/.config/openbox/rc.xml`
    - `~/.config/openbox/environment`
- Community reference ranking:
  - `sabamdarif/termux-desktop`: good reference for Openbox UX composition on top of Termux:X11
  - `modded-ubuntu/modded-ubuntu`: not aligned with the workspace desktop baseline because it is Ubuntu-in-proot plus VNC-first
- Candidate native Openbox components already available as Termux packages:
  - `tint2`
  - `rofi`
  - `feh`
  - `thunar`
  - `lxappearance`
  - `obconf-qt`
  - `dunst`
  - `xfce4-settings`
  - `picom` or `xcompmgr`
- Preferred direction:
  - keep host graphics and window manager native in Termux
  - keep Debian/proot only as GUI client path
  - borrow package choice and UX ideas from `termux-desktop`, not its full monolithic installer

## Openbox Functional Desktop Implemented
- The Openbox host desktop was upgraded from a bare WM launch to a lightweight functional desktop.
- Main implementation lives in:
  - `/home/igor/Documentos/AI/TermuxAiLocal/Install/install_termux_stack.sh`
- New lightweight desktop components now installed in the host Termux stack:
  - `tint2`
  - `rofi`
  - `thunar`
  - `obconf-qt`
  - `lxappearance`
  - `dunst`
  - `xfce4-settings`
  - `xorg-xsetroot`
- Managed Openbox user config is now written to:
  - `~/.config/openbox/environment`
  - `~/.config/openbox/autostart`
  - `~/.config/openbox/menu.xml`
- Managed panel config is now written to:
  - `~/.config/tint2/tint2rc`
- The panel now exposes a lightweight launcher button:
  - icon-only launcher on the left side of the panel
  - left click: `openbox-launcher` via `rofi`
  - right click: `openbox-file-manager`
  - middle click: `openbox-terminal`
- The top `tint2` panel now uses dock semantics (`panel_dock = 1`), so maximized apps reserve space below the bar instead of opening behind it.
- Managed helper launchers are now installed in `~/bin`:
  - `openbox-terminal`
  - `openbox-launcher`
  - `openbox-file-manager`
  - `openbox-settings`
  - `openbox-reconfigure`
- `openbox-launcher` now auto-syncs Debian `.desktop` entries into the host catalog before opening `rofi`.
- This closes the gap where apps installed with `apt` in Debian, such as KiCad, would not appear in the launcher until a manual sync.
- The launcher sync is now bounded/backgrounded so `rofi` itself does not block on `proot-distro login`.
- The current device launcher was manually reapplied from the validated payload after drift was found in `~/bin/openbox-launcher`; this restored Debian sync plus `rofi -drun-reload-desktop-cache` on the live Termux host.
- Termux-side `stop-termux-x11` only stops the `termux-x11` process. It cannot `force-stop` the Android app activity from inside the app sandbox.
- When the visual `Termux:X11` app itself must disappear, use the host helper `adb_stop_termux_x11.sh`.
- Session behavior:
  - `start-openbox-x11` now writes the Openbox user config before launch
  - it prefers `openbox-session` semantics when possible
  - because the Termux `openbox-session` path currently depends on PyXDG, the validated host path falls back to:
    - `openbox --startup "$HOME/.config/openbox/autostart" --sm-disable`
  - this fallback is intentional and validated
- `openbox-maxperf` remains the daily performance profile:
  - `DBUS=off`
  - `tint2` is always started
  - `dunst` and `xfsettingsd` are only started when the profile enables DBus
- Real validation completed:
  - canonical baseline passed:
    - `/home/igor/Documentos/AI/TermuxAiLocal/ADB/reports/validate-baseline-20260317-231947/summary.txt`
  - stack probe after start showed:
    - `X11=display-ready`
    - `VIRGL=ativo`
    - `DESKTOP=openbox`
    - `DISPLAY=:1`
  - `openbox-file-manager` launched successfully inside X11
- device screenshot confirmed a functional desktop with panel, terminal, and Thunar:
  - `/tmp/openbox-functional-thunar.png`
- device screenshot also confirmed the new `Menu` button on the panel opening the launcher:
  - `/tmp/openbox-menu-button.png`
- device screenshot after refinement confirmed the launcher as an icon-only button on the panel:
  - `/tmp/openbox-launcher-icon.png`
- second refinement now validated:
  - the host Openbox panel moved to the top edge to avoid visual conflict with the Android bottom bar
  - `rofi` now uses a managed compact theme in `~/.config/rofi/termux-openbox.rasi`
  - `openbox-terminal` now prefers Debian `xfce4-terminal` with title `Debian Terminal`
  - `openbox-launcher` now restricts `drun` discovery to the local curated catalog in `~/.local/share/applications`
  - the launcher now shows Debian-exported entries plus local Openbox entries instead of the noisy XFCE host settings catalog
  - duplicate terminal entries were removed from the Debian export; the launcher now keeps only the canonical `Terminal` entrypoint
  - host Openbox now also writes `~/.config/openbox/rc.xml` with daily-use hotkeys:
    - `Super+Space` launcher
    - `Super+Enter` terminal
    - `Super+E` file manager
    - `Super+,` settings
    - `Super+1..4` switch workspace
    - `Super+Shift+1..4` send window to workspace
  - validation on device:
    - panel config shows `panel_position = top center horizontal`
    - `rofi` theme file exists and is active
    - `rc.xml` contains the managed hotkeys
  - screenshot proof:
    - `/tmp/openbox-lapidado.png`
    - `/tmp/openbox-lapidado-3.png`
    - `/tmp/openbox-terminal-unico-2.png`
- The Termux-side interactive menu now exposes a daily-use entrypoint:
  - `ID=daily_openbox`
  - label: `Iniciar desktop diario acelerado`
  - command: `start-openbox-maxperf`
  - validated result: the menu action starts `Termux:X11`, `VirGL plain`, and `Openbox` in the accepted daily profile
- Daily Openbox start is now silent:
  - `start-openbox-x11` / `start-openbox-maxperf` no longer auto-open a terminal window
  - they also do not launch GPU probe apps such as `glxgears`
  - real validation after `start-openbox-maxperf` showed:
    - `openbox` running
    - `virgl_test_server_android` running
    - no `aterm`, `xterm`, or `xfce4-terminal`
    - no `glxgears` or `es2gears`
- Practical result:
  - the desktop is still light and performance-oriented
  - but it is now usable as a real desktop instead of only a validated Openbox process

## Debian User `igor` Strengthened
- The Debian `proot` user `igor` remains the correct place for per-user Linux settings.
- The host Openbox desktop still belongs to Termux; Debian remains a GUI client path.
- The Debian root config now also installs:
  - `tint2`
  - `rofi`
  - `obconf`
  - `lxappearance`
  - `dunst`
- The Debian user config for `igor` now creates:
  - `~/Desktop`
  - `~/Documents`
  - `~/Downloads`
  - `~/Projects`
  - `~/.config/openbox`
  - `~/.config/tint2`
- The Debian user config now installs launchers in `/home/igor/bin`:
  - `openbox-terminal`
  - `openbox-launcher`
  - `openbox-file-manager`
  - `openbox-settings`
  - `start-openbox-termux-x11`
  - existing `run-gui-termux*` launchers remain
- The Debian user config now writes:
  - `/home/igor/.config/termux-stack/env.sh`
  - `/home/igor/.config/openbox/environment`
  - `/home/igor/.config/openbox/autostart`
  - `/home/igor/.config/openbox/menu.xml`
  - `/home/igor/.config/openbox/rc.xml`
  - `/home/igor/.config/tint2/tint2rc`
  - `/home/igor/.bash_aliases`
- Validated state after reprovision:
  - `sudo -n true` works for `igor`
  - `env.sh` loads as:
    - `DISPLAY=:1`
    - `XDG_RUNTIME_DIR=/tmp/runtime-igor`
    - `TERMUX_X11_WM=openbox`
    - `TERMUX_GUI_RENDERER=hardware`
    - `GALLIUM_DRIVER=virpipe`
  - Debian-side packages and launchers were confirmed present
- Practical caveat:
  - inside `proot`, `id` still shows Android-style `aid_*` groups at runtime
  - treat that as a `proot` identity quirk, not as evidence that `sudoers`, launchers, or the Debian-side user setup failed

## Host Openbox Now Presents Debian First
- The host Openbox desktop now behaves as a shell for Debian GUI usage instead of exposing host Termux apps by default.
- Host-side helpers generated by `/home/igor/Documentos/AI/TermuxAiLocal/Install/install_termux_stack.sh` now prefer Debian apps when `run-gui-debian` exists:
  - `openbox-terminal` -> Debian terminal as `igor`
  - `openbox-file-manager` -> Debian `thunar` as `igor`
  - `openbox-settings` -> Debian `lxappearance` / `obconf`
- Debian now exports launcher entries back into the host Openbox launcher:
  - user helper: `/home/igor/bin/sync-termux-desktop-entries`
  - host destination:
    - `/data/data/com.termux/files/home/.local/share/applications`
    - `/data/data/com.termux/files/home/bin/debian-apps`
  - managed desktop-entry prefix:
    - `debian-igor-*.desktop`
- Debian root now installs an apt hook:
  - `/etc/apt/apt.conf.d/90termux-sync-desktop`
  - effect:
    - after apt/dpkg operations in the Debian proot, the desktop-entry sync helper is re-run automatically
- Real validation completed:
  - host Openbox launcher now shows Debian app entries with icons:
    - `/tmp/openbox-debian-launcher.png`
  - host Openbox terminal now opens a Debian terminal as `igor`
  - host Openbox file manager now opens Debian `thunar` rooted at `/home/igor`
  - screenshot proof:
    - `/tmp/openbox-debian-shell.png`
- Practical result:
  - from the user's point of view inside Openbox, the visible workspace is now Debian-first
  - Termux remains the host graphics/runtime layer underneath, but no longer dominates the day-to-day GUI entrypoints

## Termux:X11 Additional Keys Bar Hidden By Default
- The blocking bottom row `ESC / - HOME UP END PGUP ...` was confirmed to be the Termux:X11 additional keys bar, not the Android navigation bar.
- Official Termux:X11 references used:
  - keyboard toggle and gestures in `termux/termux-x11` README
  - command-line preferences in `termux/termux-x11` README
- Live device state was confirmed with:
  - `showAdditionalKbd="true"`
  - `additionalKbdVisible="true"`
  - `extra_keys_config="[['ESC','/',{key: '-', popup: '|'},'HOME','UP','END','PGUP', ...]]"`
- The live fix already applied on device:
  - `termux-x11-preference showAdditionalKbd:false additionalKbdVisible:false swipeDownAction:"no action"`
- The payload was updated so future reprovision/reinstall keeps this default:
  - `/home/igor/Documentos/AI/TermuxAiLocal/Install/install_termux_stack.sh`
  - it now applies the hidden additional-keys preference set as part of the default Termux:X11 preferences
  - `~/bin/start-termux-x11` also reasserts these preferences when starting X11
- If the user ever wants the bar back temporarily:
  - `termux-x11-preference showAdditionalKbd:true additionalKbdVisible:true swipeDownAction:"toggle additional key bar"`

## Continue Current Behavior
- Good:
  - natural full-flow execution is good
  - minimal repair with current stack is good
  - stop-on-failure for explicit ordered lists is good
  - Debian install and Debian GUI launch use the new host-side wrappers correctly
- Good reference sessions:
  - full natural flow:
    - `/home/igor/.continue/sessions/7fa3a0f6-5c98-4f6e-9f95-69dc76af7e21.json`
  - minimal repair:
    - `/home/igor/.continue/sessions/b7555d5b-e2e7-4f55-b464-304e3c5ea5c4.json`
  - stop-on-failure:
    - `/home/igor/.continue/sessions/c9be4daf-8ff6-491b-a240-b5f4b6a5f41c.json`
  - clean reinstall command-map:
    - `/home/igor/.continue/sessions/61f70c7d-a654-48d8-8eae-88207f36abd0.json`
  - synthetic stop-on-failure with raw shell:
    - `/home/igor/.continue/sessions/be6af55b-dc35-4f08-aef3-c5225403aa7a.json`
  - explicit 2-step success sequencing:
    - `/home/igor/.continue/sessions/3b46a797-ae7f-4eba-95e5-6ff52c0b6eac.json`

## Continue Current Open Issue
- The remaining inflation problem is not the model load config.
- The remaining inflation problem is large rule and runbook reads inside Continue.
- The biggest offender was this file when read in full.
- For short Continue command-map questions limited to the clean reinstall flow:
  - after `AGENTS.md`, the model should read only `Local-Model-Execution-Guide.md`
  - it should not read this file
- For short Continue smoke tests limited to canonical `reset -> start -> validate`:
  - the minimal read set is this file plus `Local-Model-Execution-Guide.md`
- The previous synthetic raw-shell stop-on-failure residual is now closed.
- The main residual risk is operational, not behavioral:
  - Continue extension reinstall or update can overwrite the local patch in `~/.vscode/extensions/.../out/extension.js`
  - the canonical recovery is the workspace helper above
- A separate renderer-stability issue was also identified and mitigated:
  - before the latest patch, a failed `llm/streamChat` path could stringify the entire webview message payload into the renderer log
  - that created a very large error object precisely on the error path and could present as VS Code closing after `Error handling webview message` and `Error: Connection error.`
  - the canonical recovery is the same helper above

## Latest Continue Retune
- The short reinstall command-map retune materially improved the Continue behavior.
- Current good reference session:
  - `/home/igor/.continue/sessions/3c439e2e-73fc-4e6f-a4b1-05e02416f9af.json`
- Verified behavior in that session:
  - it read only `Workspace-Handoff.md` and `Local-Model-Execution-Guide.md`
  - it did not read `Install/adb_reinstall_termux_official.sh`
  - it did not read `Install/install_termux_repo_bootstrap.sh`
  - it did not read `Install/install_termux_stack.sh`
  - it returned the canonical one-step reinstall answer
- Prompt-size improvement measured in the LM Studio log:
  - initial prompt: about `4203` tokens
  - after `Workspace-Handoff.md`: about `6328` tokens
  - after `Local-Model-Execution-Guide.md`: about `9212` tokens
- Practical conclusion:
  - context no longer explodes for this question
  - the remaining residual is that the model still reads `Workspace-Handoff.md` first even though the ideal answer no longer needs it

## Latest Full-Flow Continue Retest
- Natural prompt used:
  - `Execute o fluxo diario limpo completo do workspace e pare na primeira falha. TESTE-FULLFLOW-PRO-1`
- Verified from the LM Studio log:
  - initial prompt: about `4198` tokens
  - after `Workspace-Handoff.md`: about `6593` tokens
  - after `Local-Model-Execution-Guide.md`: about `9477` tokens
  - after step 1 output: about `9667` tokens
  - after step 2 output: about `11031` tokens
  - after step 3 output: about `11265` tokens
  - after step 4 output: about `11482` tokens
- Verified behavior:
  - it read only `Workspace-Handoff.md` and `Local-Model-Execution-Guide.md`
  - it emitted canonical absolute commands with required flags
  - it advanced through:
    1. `adb_reset_termux_stack.sh --focus termux`
    2. `adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
    3. `adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu --report`
    4. `adb_termux_send_command.sh --device RX2Y901WJ2E -- 'termux-stack-status --brief'`
- Practical conclusion:
  - the natural full-flow prompt is also in a controlled context range now
  - the major prompt-inflation regression is no longer present in this scenario either

## Latest Local System-Prompt Retune
- `Local-Model-System-Prompt.md` was rewritten to be shorter and more principle-based.
- The new shape is:
  - core mental model
  - operating loop
  - compact canonical playbooks
  - a few short good-vs-bad examples
- Goal:
  - reduce rigid rule spam
  - improve generalization
  - keep exact command fidelity
- Direct LM Studio API probes after this retune:
  - clean reinstall command-map:
    - output was exactly:
      1. `bash /home/igor/Documentos/AI/TermuxAiLocal/Install/adb_reinstall_termux_official.sh`
  - full clean flow fallback without tools:
    - output was the exact canonical 7-step command list
- Practical conclusion:
  - the local model now behaves better with a shorter prompt plus examples than it did with the older long prose-only version

## Continue UI Automation Notes
- Reliable command-palette command to focus the input:
  - `Continue: Add to Chat`
- Reliable command-palette command for a fresh chat:
  - `Continue: New Session`
- Use `Enter` to submit the prompt.
- Use `Ctrl+Enter` to interrupt an ongoing generation.
- For high-confidence UI tests, validate the state in two phases:
  1. new session visible
  2. prompt visibly present in the Continue input before pressing `Enter`

## Latest Continue Retune
- `AGENTS.md` now carries explicit natural-language mapping:
  - `fluxo diario limpo completo do workspace` -> canonical 7-step daily flow
  - `com o stack atual` / `apenas o necessario` -> minimal repair
  - `reinstalacao limpa completa do Termux` -> one-step host reinstall flow
- `Local-Model-Execution-Guide.md` and `.continue/rules/termux-ai-local.md` now mark the runbook as syntax-authoritative for command-map answers, so the model should not reopen implementation scripts just to re-verify the same reinstall command.
- Additional hardening added after newer Continue regressions:
  - for natural minimal-repair requests that mention one X11 app and then `xeyes` in Debian:
    - wrong branch: `ps -ef`, `which xeyes`, `sudo apt install`, host X11 discovery
    - right branch: `termux-stack-status --brief` -> smallest verified repair -> host X11 wrapper -> Debian GUI wrapper
  - for natural full-flow requests:
    - wrong branch: `Daily-Flow/clean-full-workspace-flow.sh`, invented repo shortcuts, `file_glob_search` before runbook reads
    - right branch in Continue:
      1. read this file
      2. read `Local-Model-Execution-Guide.md`
      3. first `Run` = `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`
- Latest short reinstall Continue retest:
  - prompt: `Como faco uma reinstalacao limpa completa do Termux? TESTE-REINSTALL-PRO-17`
  - verified behavior:
    - it read only `Local-Model-Execution-Guide.md`
    - it returned the canonical one-step reinstall answer in the Continue UI
    - it did not reopen `Install/adb_reinstall_termux_official.sh` in that successful retest
- Latest full-flow Continue retest:
  - prompt: `Execute o fluxo diario limpo completo do workspace e pare na primeira falha. TESTE-FULLFLOW-PRO-4`
  - verified behavior:
    - it read `Workspace-Handoff.md` then `Local-Model-Execution-Guide.md`
    - the first `Run` returned to the canonical command:
      - `bash /home/igor/Documentos/AI/TermuxAiLocal/ADB/adb_reset_termux_stack.sh --focus termux`
    - this recovered the natural-language mapping that had briefly regressed toward reinstall
- Latest minimal-repair Continue retest:
  - prompt: `Com o stack atual, faca apenas o necessario para abrir um app X11 leve e depois xeyes no Debian. TESTE-MINREPAIR-PRO-2`
  - verified from the LM Studio log:
    - it started with `adb_termux_send_command.sh --device RX2Y901WJ2E -- 'termux-stack-status --brief'`
    - it then ran `adb_run_x11_command.sh aterm -title TESTE-X11 -e sh -lc 'printf X11_OK; sleep 1'`
    - it then ran `adb_termux_send_command.sh --device RX2Y901WJ2E --expect 'XEyes enviado ao Debian com sucesso.' -- 'run-gui-debian --label XEyes -- xeyes'`
    - it did not run `ps -ef`, `which xeyes`, `sudo apt install`, or host Linux package management
- Latest full-flow stabilization:
  - prompt: `Execute o fluxo diario limpo completo do workspace e pare na primeira falha. TESTE-FULLFLOW-PRO-10`
  - verified behavior:
    - no invented `Daily-Flow/clean-full-workspace-flow.sh`
    - no initial `file_glob_search`
    - it started with `Workspace-Handoff.md` then `Local-Model-Execution-Guide.md`
    - then `adb_reset_termux_stack.sh --focus termux`
    - then `adb_start_desktop.sh --with-gpu --profile openbox-maxperf openbox`
- Practical audit note:
  - when the Continue session JSON lags or reuses titles, the LM Studio server log is the more reliable source of truth for the exact recent tool-call sequence
- Remaining residual:
  - the synthetic raw-shell stop-on-failure residual is closed locally
  - practical fix:
    - `/home/igor/.vscode/extensions/continue.continue-1.2.17-linux-x64/out/extension.js` now injects failure text into `run_terminal_command` output when a command exits non-zero without stdout/stderr
    - the failure content now includes `FALHA DETECTADA` plus the failed command and exit code
    - the patch is now reappliable through `/home/igor/Documentos/AI/TermuxAiLocal/Install/apply_continue_extension_patch.sh`
  - validated result:
    - in `/home/igor/.continue/sessions/be6af55b-dc35-4f08-aef3-c5225403aa7a.json`, step 1 `exit 7` ran and step 2 did not run
    - host markers confirmed `STEP1=yes` and `STEP2=no`
    - LM Studio log showed the tool output text contained the failure banner before the model decided the next step
  - regression check:
    - `/home/igor/.continue/sessions/3b46a797-ae7f-4eba-95e5-6ff52c0b6eac.json` confirmed ordinary 2-step success sequencing still works
  - operational rule from now on:
    - after a clean LM Studio / Continue reinstall, or before the first clean Continue Agent behavior test, run the patch check helper and apply it if needed before trusting Continue stop-on-failure behavior
  - for real workspace wrappers that emit `FALHA DETECTADA` or `Command failed with exit code`, the stop-on-failure policy remains the relevant criterion

## Host Desktop State
- KDE idle lock was disabled persistently on the host.
- The host should not lock and ask for a password while long Continue tests are running.

## FreeCAD Placement Fix
- Do not treat the FreeCAD-under-`tint2` issue as a generic Openbox placement problem anymore.
- The canonical top-panel config is still:
  - `panel_dock = 1`
  - `panel_position = top center horizontal`
  - `strut_policy = follow_size`
- That canonical panel config now exists both in the workspace payload and in the current live Termux `tint2rc`.
- The remaining misplacement was application-specific:
  - `xprop` / `wmctrl` on the live window showed `WM_NORMAL_HINTS` with `user specified location`
  - FreeCAD was reopening itself with an explicit top-edge Y coordinate, so panel struts/margins alone were not enough
- Persistent fix now implemented:
  - `Debian/configure_debian_trixie_root.sh` installs `wmctrl`
  - `Debian/configure_debian_trixie_user_igor.sh` exports a special wrapper for `FreeCAD`
  - that wrapper launches FreeCAD and then repositions the mapped window with `wmctrl -x -r freecad.FreeCAD -e 0,0,40,-1,-1`
- Live validation after reapplied wrapper:
  - `wmctrl -lxG` showed the FreeCAD window at `x=0 y=40`
  - `xprop` showed `WM_NORMAL_HINTS` with `user specified location: 0, 40`
- Interpretation:
  - `tint2` / Openbox global config was necessary but not sufficient
  - the stable fix is global dock semantics plus an app-specific correction for FreeCAD's restored geometry
- Root cause of the earlier regression after reset/start:
  - the workspace payload in `Install/install_termux_stack.sh` was already correct
  - but the installed live copy at `~/.config/termux-stack/termux-stack-common.sh` was stale and still regenerated `tint2rc` with `panel_dock = 0`
- Current validated live state after replacing that installed common library and restarting the stack:
  - `~/.config/tint2/tint2rc` keeps `panel_dock = 1` even after `adb_reset_termux_stack.sh` + `adb_start_desktop.sh`
  - the FreeCAD wrapper exported by `sync-termux-desktop-entries` now uses `wmctrl -x -r freecad.FreeCAD -e 0,0,60,-1,-1`
  - visual validation on device shows the full titlebar below the top `tint2` panel

## What Not To Break
- Do not move graphics ownership into Debian.
- Do not reintroduce KiCad-specific flow as the main path.
- Do not treat `llvmpipe` as success.
- Do not use generic `cd ... && ./script` shortcuts in place of canonical absolute `bash /home/igor/...` commands.
- Do not continue after `FALHA DETECTADA` if the user asked to stop on failure.

## Next Best Action
- If the task is execution, testing, validation, provisioning, recovery, or command-map behavior:
  - prefer `/home/igor/Documentos/AI/TermuxAiLocal/Local-Model-Execution-Guide.md`
- If the task is only a short Continue clean reinstall command-map answer:
  - read only `Local-Model-Execution-Guide.md`
- If the task is only a short Continue smoke test for `reset -> start -> validate`:
  - read this file and `Local-Model-Execution-Guide.md`
