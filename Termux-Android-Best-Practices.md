# Termux + Android Best Practices for Openbox/X11/Virgl Workflows

This note captures the cleaned-up flow for the Termux/X11 stack, including the host automation and the Debian GUI environment. It also references the aspects of the Android security model that the automation must respect.

## 1. Android and Termux hygiene

- Always use user `0` on the device. Validate with `adb shell pm list users` and reject `SecurityException` outputs.
- Keep the device awake while experimenting: `adb shell settings put global stay_on_while_plugged_in 3` and ensure animations are set to `0`.
- Restart Termux, Termux:X11 and the managed GUI state before each run. The host reset helper (`ADB/adb_reset_termux_stack.sh`) automates this and rebuilds the validated desktop mode layout, optionally leaving focus on either Termux or Termux:X11.
- After each non-reinstall restart of the GUI pair, restore the approved desktop mode layout: `Termux` filling the left column, `Termux:X11` in the upper-right slot, the SSH client below it in the lower-right slot, and `Termux:API` kept off the visible desktop.
- The reset helper now also performs a best-effort cleanup of managed Openbox/XFCE/VirGL/DBus leftovers inside the Termux app context, so a new test starts from a genuinely clean GUI state.
- When `run-as com.termux` is available (debug APK), use `ADB/adb_termux_send_command.sh` with structured spool transport. For X11/GPU-sensitive helpers, prefer the interactive-shell spool mode so the command executes in the real Termux shell namespace while the host still receives stdout/stderr/exit code.
- If the tablet is being used interactively for unrelated work, pause host automation first. Before any new ADB/device action, ask the operator to stop using the tablet and restore the approved desktop trio if needed.

## 2. Automation and status tracking

- The Termux payload installs `termux-stack-status`, `start-openbox`, `start-openbox-stable`, `start-openbox-maxperf`, `start-openbox-compat`, `start-openbox-vulkan-exp`, `start-xfce-x11`, `start-virgl`, `stop-virgl`, `start-maxperf-x11`, `run-in-x11`, `run-glmark2-x11` and other helpers. Each helper pumps status lines into Termux so you can watch stages, errors and the progress bar from the terminal.
- Host wrappers now emit `[HOST]` / `[HOST:OK ...]`; Termux payloads emit `[TERMUX]` / `[TERMUX:CMD]` / `[TERMUX:OK ...]`; Debian payloads emit `[DEBIAN-ROOT]` or `[DEBIAN-USER]`. This makes it explicit where the current stage is executing without changing the validated runtime path.
- `termux-stack-status --brief` now prints `X11`, `VIRGL`, `MODE`, `DESKTOP`, `WM`, `RES` and `PROFILE` plus the `DISPLAY`. The default (non-brief) output adds explicit lines for `virgl-mode`, `current-profile`, `default-resolution` and `default-profile`.
- The host scripts capture these outputs via `adb_termux_send_command` and stream them back to the host automation logs so failures are easier to trace.
- `virgl_test_server_android` is relaunchable with `start-virgl plain|gl|vulkan`; the helper now restricts `LD_LIBRARY_PATH` to the package-private `virglrenderer-android` directory, which keeps `libepoxy.so`/`libvirglrenderer.so` private without accidentally pulling Mesa's `libEGL/libGLES` software stack into the host server.
- `start-openbox-x11 --profile ...` is the primary lightweight desktop path. It now validates the real `openbox` process first and only then spawns the lightweight terminal, preventing false positives caused by a lone surviving terminal.
- `start-xfce-x11` accepts `--wm xfwm4|openbox`; `xfwm4` remains available, while `openbox` is treated only as an XFCE window manager replacement.
- `start-xfce-x11-detached` launches the same XFCE session in background and is the preferred entrypoint for host-side automation, since it preserves the interactive Termux shell instead of leaving it occupied by the desktop startup sequence.
- `start-maxperf-x11 [openbox|xfce]` is the deterministic "aggressive profile" entrypoint: it resets the session, reapplies `1280x720`, restarts virgl in `plain`, and then launches either pure Openbox or `XFCE --wm openbox`.

## 3. Resolution and GPU tuning

- The stack now defaults to `1920x1080` for `balanced` and `1280x720` for `performance`. The environment variables `TERMUX_X11_BALANCED_RESOLUTION` and `TERMUX_X11_PERFORMANCE_RESOLUTION` allow you to override those defaults without touching the scripts again.
- Use `set-x11-resolution` to reapply a profile. `custom LARGURAxALTURA` still accepts `1280x720` when you need to reduce fill-rate, and the helper echoes the applied mode/resolution plus a `termux-x11-preference list`.
- The host launcher now accepts `ADB/adb_start_desktop.sh --maxperf openbox|xfce`, which maps to the same aggressive profile and forces `Openbox` as the XFCE WM when `xfce` is selected.
- Run `glmark2-es2` (or the packaged `run-glmark2-x11` helper) with `GALLIUM_DRIVER=virpipe` once virgl is active. The host `ADB/adb_run_x11_command.sh --with-virgl run-glmark2-x11` also injects the appropriate renderer environment and streams the benchmark output to the host.
- Do not compare onscreen `glmark2` scores directly with `glmark2-es2 --off-screen`: onscreen is dominated by display resolution and desktop/compositor overhead, while `--off-screen` is the cleaner renderer comparison.
- Keep `check-gpu-termux` handy: it now enumerates `es2_info`, `es2gears_x11` and a `glxinfo` fallback so you can tell whether EGL/GLES is functioning or whether you need to force software. On this tablet, the success criterion is `GL_RENDERER: virgl (Mali-G925-Immortalis MC12)` from the EGL/GLES probe, not GLX stability.

## 4. Debian GUI

- The Debian helper scripts install `sudo`, `mesa-utils`, `x11-apps`, `glmark2`, `openbox` and the generic GUI stack needed for arbitrary apps.
- The Debian install flow now asks the operator for the Debian username, password, and whether sudo should require a password. The chosen user is added to the relevant groups, gets the matching sudoers policy, and receives `~/.config/termux-stack/env.sh` plus `~/.config/termux-stack/debian-gui.env` so Termux-side launchers can derive `DISPLAY`, `XDG_RUNTIME_DIR`, `TERMUX_X11_WM`, `TERMUX_X11_DISTRO_ALIAS`, and `TERMUX_X11_DISTRO_USER` dynamically.
- `run-gui-termux` is now the generic Debian-side launcher: it loads the shared env, sets `GALLIUM_DRIVER=virpipe` for hardware mode (or `LIBGL_ALWAYS_SOFTWARE` for software mode), and runs `dbus-run-session -- "$@"`.
- `run-gui-debian -- comando [args...]` is the Termux-side entrypoint for arbitrary Debian GUI apps.
- Use `proot-distro login --shared-tmp ...` for Debian GUI clients so the proot shares runtime/tmp state with the host Termux session. Before launching an app, ensure `termux-stack-status` reports `DESKTOP=openbox` or `DESKTOP=xfce-*`, plus `X11=display-ready`. Debian-level helper logs live under `/tmp` for quick inspection.

## 5. Summary

- The automation now prints richer diagnostics back to both the Termux prompt and the host logs. When things fail, consult the logs under `$HOME/.cache/termux-stack/logs` and the status output around the failure.
- When you update scripts or helpers, reinstall the Termux stack following the host provisioning flow (`Install/adb_provision.sh` -> Termux payload) and revalidate using `ADB/adb_validate_baseline.sh --desktop=openbox --profile=openbox-maxperf --with-gpu` before consolidating.
