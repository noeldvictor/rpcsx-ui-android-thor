# Eternal Sonata Save + Ghidra SPURS Superpath Probe

- Status: windows-pass for gated cache correctness; semaphore direct fast path is Android-correct but not an FPS win; join-spin parked by default
- Game: Eternal Sonata `BLUS30161`
- Platform target: AYN Thor Max first, Base/Pro compatible unless a later result says otherwise
- Windows role: route and debug from the same save/checkpoint
- Android role: final FPS, frame pacing, thermal, memory, and visual correctness proof

## Save Sync

- Thor save pulled from `/storage/emulated/0/Android/data/net.rpcsx.easy/files/config/dev_hdd0/home/00000001/savedata/BLUS3016100`.
- Local ignored checkpoint: `save-checkpoints/eternal-sonata/thor-20260515-190657/BLUS3016100`.
- Windows RPCS3 install target: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\dev_hdd0\home\00000001\savedata\BLUS3016100`.
- Manifest: `save-checkpoints/eternal-sonata/thor-20260515-190657/manifest.json`.

## Ghidra Findings

- Decrypted PRX source: Thor cache `cache/ppu_progs/BLUS30161-WHnKAK6U9UApL2YMgjU3c5ozpTUM-libsre.sprx/prog.prx`.
- Ghidra run: `debug-captures/ghidra-libsre-20260515-191052/`.
- Prior hot log address: `libsre:0x00cc948c`, LR `0x00cc945c`, thread `SpursHdlr0`, group `CellSpursKernelGroup`, `max_num=1`, `max_run=1`.
- The raw PRX import has a `0x100` file/address skew for useful text bytes. For the observed run, guest `0x00cc930c` maps to Ghidra import address `0x0000940c`, and guest `0x00cc948c` maps to `0x0000958c`.
- Ghidra shows the hot handler repeatedly scanning SPURS workload slots, checking workload state/ready masks, toggling handler flags, using `sync`, and entering syscalls for start/join/event-like behavior.
- This supports the existing runtime observation: the painful loop is a SPURS handler churn path around `sys_spu_thread_group_start` / `sys_spu_thread_group_join`, not a plain boot failure.

## Superpath Hypothesis

Build a gated Eternal Sonata SPURS fast path that detects this exact signature:

- title `BLUS30161`
- thread name containing `SpursHdlr0` / `TCX_SpursHdlr0`
- module/CIA/LR matching the translated `libsre` handler family
- SPU group name ending `CellSpursKernelGroup`
- `max_num=1`, `max_run=1`, `cause=SYS_SPU_THREAD_GROUP_JOIN_GROUP_EXIT`, `status=0`
- repeated start/join churn with monotonically increasing `stop_count`

Possible wins to test, in order:

1. Avoid redundant SPU image deploy and CPU re-init when the same single-SPU group restarts with unchanged image/args.
2. Add a narrow scheduler wake/coalescing path for repeated single-SPU SPURS start/join cycles.
3. Detect no-progress join churn and reduce host wait/notify overhead without changing guest-visible cause/status.
4. Only after proof, consider a per-title `BLUS30161` fast path that caches the recognized SPURS handler state.

## Windows Implementation

- Windows upstream lab repo: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Core files touched:
  - `rpcs3/Emu/Cell/lv2/sys_spu.h`
  - `rpcs3/Emu/Cell/lv2/sys_spu.cpp`
- Launcher files touched:
  - `tools/windows_rpcs3_lab.ps1`
  - `tools/eternal_sonata_speed_sprint.ps1`
- Gate:
  - `RPCS3_ES_SPURS_SUPERPATH=detect` logs the hot loop only.
  - `RPCS3_ES_SPURS_SUPERPATH=cache` enables the cached SPU segment deploy path.
  - `RPCS3_ES_SPURS_JOIN_SPIN=N` optionally tests bounded join spinning; default is off because the Windows run missed every spin attempt.
- The cache path is title/signature scoped to `BLUS30161`, `SpursHdlr0`/`TCX_SpursHdlr0`, `CellSpursKernelGroup`, `max_num=1`, and `max_run=1`.
- The cache path does not skip SPU execution, does not skip `cpu_init()`, and does not spoof join cause/status. It only reuses materialized SPU image segment bytes after the normal deploy path proves no SPU patches were applied.
- Build command passed:

```powershell
cmake --build build-msvc --config Release --target rpcs3 --parallel 8
```

## Windows Results

- Detect run: `debug-captures/windows-lab/20260515-192807-eternal-sonata-superpath-detect/`
  - Detected `PPU[0x1000009] SpursHdlr0` at `libsre:0x00cc9470`, LR `0x00cc945c`, group `0x4000200` named `CellSpursKernelGroup`.
  - After roughly 60 seconds: about 4,776 starts and 4,775 joins, about 94 start/join cycles per second.
  - Deploy/init cost was tiny on Windows; cumulative join wait dominated.
- Cache run: `debug-captures/windows-lab/20260515-192925-eternal-sonata-superpath-cache/`
  - One cache build of 1,920 bytes, then thousands of cache hits.
  - No fatal dialog and no visible title/preload corruption in screenshots.
- Join-spin probe run: `debug-captures/windows-lab/20260515-193614-eternal-sonata-superpath-cache-spin/`
  - `RPCS3_ES_SPURS_JOIN_SPIN` equivalent default test had 0 spin hits and all misses on Windows.
  - It slightly worsened join timing, so join spin is now optional and off by default.
- Final cache-only sanity run: `debug-captures/windows-lab/20260515-194147-eternal-sonata-superpath-cache-final/`
  - Cache hits confirmed again.
  - `spin_hits=0`, `spin_misses=0`, confirming no accidental spin overhead.
  - Screenshot reached title shader preload with `Loading pipeline object 86 of 86`.
- Semaphore direct fast probe:
  - Ghidra EBOOT run `debug-captures/ghidra-eboot-20260515-212237/` identified the hot `main_thread` wrappers around `sys_semaphore_wait` at `0x0031c168..0x0031c1bc` and `sys_semaphore_post` at `0x0031c550..0x0031c620`.
  - `debug-captures/windows-lab/20260515-221405-eternal-sonata-sema-direct-sampled-boot/` reached title cleanly at 60 FPS with sampled logging and about `16,384` direct semaphore fast hits by 43 seconds.
  - `debug-captures/windows-lab/20260515-221536-eternal-sonata-field-sema-direct-sampled-windows/` reached the routed story/field path with clean screenshots and about `59,392` direct semaphore fast hits by 2:03, with direct wait/post both active.
  - This is a real hot-path candidate because it replaces simple uncontended semaphore wait/post traffic after a normal lookup proves the semaphore object. It does not fast-path queueing, wakeups, invalid IDs, destruction, or contended waits.
  - Do not claim a Windows FPS win from this yet. Host-normalized lab snapshots were added after these runs, and the current PC can be high-contention when Vita3K or other emulator work is active. Rerun `Off` vs `Fast` with matching host-contention grade before comparing speed.

## Android Results

- Android port:
  - file: `app/src/main/cpp/rpcsx/kernel/cellos/src/sys_semaphore.cpp`
  - gate: `debug.rpcsx.thor.es_sema_superpath=off|profile|fast`
  - title/thread/CIA scope: `BLUS30161`, `main_thread`, wait wrapper `0x31c168..0x31c1bc`, post wrapper `0x31c550..0x31c620`
  - default: off
- Dev-core push:
  - run dir: `debug-captures/20260516-055044-es-sema-superpath-dev-core-push`
  - active internal core: `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`
  - core SHA256: `FA2FADBE4E666B6A21255925A5BB15CE39ACACF354E80C2F3B3AF05FA06602AC`
- Field A/B, stock Qualcomm driver, NeutralCore:
  - Off: `debug-captures/android-speed-sprint/20260516-055612-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `17.43 FPS`, correct field visuals.
  - Fast: `debug-captures/android-speed-sprint/20260516-060122-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `17.03 FPS`, correct field visuals.
  - Fast logging confirmed the gate hit roughly `98,304` semaphore operations by field time, including about `57,911` direct wait hits and `40,381` direct post hits.
- Interpretation: this wrapper path is genuinely hot and correctness-safe enough to leave as a gated experiment, but the first field route is not bottlenecked on these syscall wrappers. Keep it off for normal FPS testing and push deeper into SPU/MFC work or RSX/Vulkan traffic.

## Interpretation

- The first cache superpath is stable enough for a Thor experiment, but it is probably not the dramatic speed win by itself because the SPU image deploy bytes are small and Windows deploy/init timing is already negligible.
- The real hot cost is the repeated SPURS handler start/join workload around the single-SPU `CellSpursKernelGroup`.
- The direct semaphore fast path is more interesting than the segment cache for raw syscall volume because Eternal Sonata pounds uncontended wait/post wrappers tens of thousands of times during the route. Android proof shows it works, but it does not materially move field FPS, so it should no longer be treated as the main speed lever.
- The next serious win should target what the SPU workload is doing between start and join, or the PPU-side event/semaphore/timer choreography around that handler, not just segment copy.
- Good next candidates:
  - correlate `SpursHdlr0` start/join with PPU-side `sys_event_queue_receive`, `sys_semaphore_wait/post`, and `sys_timer_usleep` logs;
  - profile or instrument the SPU image hash `SPU-c551925d5640eb35b80dc1281f8509336eca9765`;
  - test whether Android/Thor spends more relative time in deploy/init than Windows before porting the cache path;
  - keep investigating SPU reduced-loop/codegen work, because the hot work appears to be real SPU/PPU workload, not merely syscall wrapper overhead.

## Acceptance

- Must be gated and off by default until proven.
- Must preserve field, battle, and menu visuals.
- Must not reintroduce the previous rtime reservation `SIGBUS` failure path.
- First pass target: at least 20% sustained Thor FPS/frame-time improvement.
- Big win target: clear evidence that the SPURS superpath can move Eternal Sonata toward playable/full speed on Thor.
