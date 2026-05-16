# 20260515-spu-image-patchless-fastdeploy

- Status: `windows-pass`
- Title ID: `BLUS30161`
- Game: Eternal Sonata
- Platform scope: `shared-core`, `windows-lab`, `android-thor`
- Owner: Codex + user
- Created: 2026-05-15
- Last updated: 2026-05-15

## Hypothesis

Eternal Sonata repeatedly starts and joins short-lived SPU thread groups. The same SPU image is redeployed thousands of times during early runtime, so `sys_spu_image::deploy` may be spending unnecessary time hashing, patch-probing, and logging an image that already proved patchless. After the first full deploy reports zero applied patches for a thread slot, subsequent starts can use a patchless segment-copy path that preserves copy/fill semantics while skipping the hash/patch walk.

## Change

Classification: `shared-core`

Windows upstream files:

- `rpcs3/Emu/Cell/lv2/sys_spu.h`
- `rpcs3/Emu/Cell/lv2/sys_spu.cpp`

Android vendored files:

- `app/src/main/cpp/rpcsx/kernel/cellos/include/cellos/sys_spu.h`
- `app/src/main/cpp/rpcsx/kernel/cellos/src/sys_spu.cpp`

Companion log-noise reductions:

- `cellSysutilGetSystemParamInt`: warning to trace.
- SPU reduced-loop analysis and LLVM block-build messages: notice/success/todo to trace.
- SPU block weight stats: trace only.

## Rollback

Revert the `patchless_image_deploy` flag, `deploy_segments`, and `applied_count` plumbing. The fallback path is the previous full `sys_spu_image::deploy` call for every thread start.

## Safety Read

- First deploy for each SPU thread slot still runs the full deploy path.
- Fast path is only enabled when the full path reports `applied_count == 0`.
- Games with active SPU patches keep using the full deploy path.
- Segment copy and zero-fill behavior is preserved.
- Residual risk: if patch availability changes after the first patchless deploy inside the same process, this fast path would not notice. That is not expected during normal runtime, but it is the reason this should stay tracked until Thor proof is clean.

## Windows Result

Build:

- `cmake --build build-msvc --config Release --target rpcs3 -- /m`
- Result: success, produced `build-msvc/bin/rpcs3.exe`.

Pre-change warm baseline:

- Capture: `debug-captures/windows-lab/20260515-163011-eternal-sonata-warm-quietest-log/`
- Mode: GUI visible
- Duration: 180 seconds
- Log: 13,817 lines, 861,497 bytes
- `Loaded SPU image`: 30
- `sys_spu_thread_group_start`: 31,465 by 0:02:43
- `sys_spu_thread_group_join`: 31,465 by 0:02:43
- Fatal/error syscall lines: 0

Post-change visible run:

- Capture: `debug-captures/windows-lab/20260515-164038-eternal-sonata-spu-image-fastpath/`
- Mode: GUI visible
- Duration: 180 seconds
- Log: 13,745 lines, 854,133 bytes
- Booted ISO from command line, title `ETERNAL SONATA`, serial `BLUS30161`
- `Loaded SPU image`: 6
- `sys_spu_thread_group_start`: 31,594 by 0:02:43
- `sys_spu_thread_group_join`: 31,594 by 0:02:43
- Fatal/error syscall lines: 0

Post-change no-GUI run:

- Capture: `debug-captures/windows-lab/20260515-164456-eternal-sonata-nogui-fastpath/`
- Mode: `NoGui`
- Duration: 90 seconds
- Log: 13,562 lines, 845,123 bytes
- Booted ISO from command line, title `ETERNAL SONATA`, serial `BLUS30161`
- `Loaded SPU image`: 6
- `sys_spu_thread_group_start`: 15,871
- `sys_spu_thread_group_join`: 15,871
- Fatal/error syscall lines: 0

Agent-control proof:

- Capture: `debug-captures/windows-lab/20260515-165534-eternal-sonata-input-macro-proof/`
- Mode: `NoGui`
- Input macro: `start:150;wait:800;cross:150;wait:800;cross:150;wait:800;cross:150`
- Result: booted ISO from command line, loaded default keyboard pad for `BLUS30161`, sent macro tokens, and stopped under script control.
- `Loaded SPU image`: 6
- Fatal/error syscall lines: 0

Popup suppression:

- A manual PowerShell launch accidentally passed the ISO path without safe quoting, causing RPCS3 to try `C:/Users/leanerdesigner/Documents/New` and show `RPCS3: Fatal Error`.
- Windows lab fix: `--no-gui`/lab-marked fatal errors now log to stderr and terminate instead of opening `fatal_error_dialog`; `tools/windows_rpcs3_lab.ps1` sets `RPCS3_LAB_NO_FATAL_DIALOG=1`.
- Workflow rule: do not manually launch paths with spaces; use the lab script so quoting, process lifetime, logs, and popup suppression stay owned by automation.

FPS overlay / route probe:

- Windows lab now forces the RPCS3 performance overlay on, enables framerate and frametime graphs, and keeps the window title format as `FPS: %F | %R | %V | %T [%t]`.
- Capture: `debug-captures/windows-lab/20260515-170220-eternal-sonata-route-probe-fps-overlay/`
- Mode: `NoGui`
- Input macro: Start/Cross pulses after boot.
- Result: booted ISO from command line, loaded keyboard pad, accepted macro dispatch, and stopped under script control.
- `Loaded SPU image`: 6
- `sys_spu_thread_group_start`: 27,345 by 0:02:12
- `sys_spu_thread_group_join`: 27,345 by 0:02:12
- Fatal/error syscall lines: 0

Official DB + visual proof:

- Source: RPCS3 official config API `https://api.rpcs3.net/config/?api=v1`.
- Current `BLUS30161` database config:
  - `Video:`
  - `Frame limit: PS3 Native`
  - `Write Color Buffers: true`
- This conflicts with the older Eternal Sonata wiki page text that says no custom settings are recommended, so the Windows lab should trust the live config API/package DB for automated runs and still cite the wiki for notes/known issues.
- Capture: `debug-captures/windows-lab/20260515-171218-eternal-sonata-visual-db-proof/`
- Log result: `Found database config for: 'BLUS30161'` and `Applying database config`.
- Screenshot artifacts: `screenshots/screenshot-0018s.png`, `screenshots/screenshot-0033s.png`, `screenshots/screenshot-0048s.png`.
- Visual status: capture lane works and shows FPS overlay in the game window. This run only reached early logo/boot visuals, so it does not yet prove the black texture spots are fixed in gameplay.

Decision:

- Windows pass for correctness and for eliminating repeated SPU image deploy work.
- Not a drastic speed win by itself. The start/join storm remains almost unchanged, so the bigger opportunity is now below or around `sys_spu_thread_group_start/join`, not merely image deploy hashing/logging.
- Keep the patch as a small shared-core optimization candidate, but do not celebrate it as the Eternal Sonata fix.

## Android Thor Result

Pending.

Next Android proof step after Windows input/scene automation:

- Build and push dev core with `tools/build_push_thor_core.ps1`.
- Run Eternal Sonata first scene on AYN Thor with quiet logging.
- Compare FPS/frame pacing, CPU hot threads, RSS, and SPU start/join counters against the current Thor baseline.

## Next Experiment

The next drastic-speed direction should target the SPU group churn directly:

- Measure time spent inside `sys_spu_thread_group_start`, `sys_spu_thread_group_join`, SPURS wake/wait, SPU thread lifecycle, and LS setup.
- Add timing buckets around those functions in the Windows lab first.
- Use a deterministic input macro or savestate-like route to get from boot/title into the first playable area, then reuse the same route on Thor.
- If group start/join overhead dominates, test a gated group reuse or lifecycle fast path that preserves SPURS semantics.
