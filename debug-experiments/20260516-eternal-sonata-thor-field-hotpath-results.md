# Eternal Sonata Thor Field Hot-Path Results - 2026-05-16

## Scope

- Game: Eternal Sonata `BLUS30161`
- Device: AYN Thor Max
- Scene: first playable field
- Driver: stock Qualcomm
- Cache state: warm SPU/PPU/shader caches
- Core label: `es-fast-busy-wait` dev core
- Active core SHA256: `53D8E9964A3E2E2045A50FC60AEDB08A545B4F2E4630AA6BD4994FDFF8BF36B1`
- Correctness gate: screenshot visual check for field, no obvious black spots, missing textures, or menu overlays in tested field captures

SPU/PPU caches were not cleared for these speed sweeps. Rebuild the Android native
core for C++ changes, but clear SPU/PPU caches only when changing recompiler
behavior, cache keys, timing semantics that are baked into generated code, or
when running a deliberately labeled cold-cache baseline.

## RSX Depth Texture Barrier Skip

Hypothesis: Eternal Sonata field was breaking the render pass once per frame for
a depth-only texture barrier; title-gated skipping might avoid GMEM/system-memory
traffic on Adreno.

Changed files/settings:

- `VKRenderTargets.cpp` gated `render_target::texture_barrier` skip for
  `BLUS30161`.
- `thor_rsx_auditor.h` classified color versus depth texture barriers.
- `tools/set_thor_logging.ps1` added texture-barrier skip modes.
- Rollback switch: `debug.rpcsx.thor.rsx_texture_barrier=off`.

Thor result:

- Classify/off capture:
  `debug-captures/android-speed-sprint/20260516-124222-eternal-sonata-field-stock-qualcomm-scene`
- Forced depth-skip capture:
  `debug-captures/android-speed-sprint/20260516-124727-eternal-sonata-field-stock-qualcomm-scene`
- Off auditor sample: about `18.93 FPS`, `rp_break=60`,
  `tex_depth=60`.
- Depth-skip sample: about `19.49 FPS`, `rp_break=0`,
  `tex_skip=60`, `forced_skip=60`.

Status: `parked`. This is a real mechanical reduction and field visuals survived,
but the win is only about 3 percent and does not meet the first 20 percent target.
Do not expand it until battle and menu prove correctness.

## Semaphore Fast Path

Hypothesis: the previous semaphore path might reduce field wait overhead.

Thor result:

- Valid capture:
  `debug-captures/android-speed-sprint/20260516-130400-eternal-sonata-field-stock-qualcomm-scene`
- Result: about `19.28 FPS`, field visually correct.

Status: `parked`. Neutral in the field scene; not the dramatic speed path.

## Global ARM64 Busy-Wait Batching

Hypothesis: simpleperf showed `rx::get_tsc()` and `rx::busy_wait()` as huge CPU
costs, so polling `cntvct_el0` less often inside Android/ARM64 busy waits might
free CPU.

Changed files/settings:

- `rx/include/rx/asm.hpp` added opt-in Android/ARM64 modes behind
  `debug.rpcsx.thor.fast_busy_wait`.
- `tools/set_thor_logging.ps1` added `FastBusyWaitLight`, `FastBusyWait`, and
  `FastBusyWaitAggressive`.
- Rollback switch: `debug.rpcsx.thor.fast_busy_wait=off`.

Thor A/B result:

| Mode | Capture | FPS overlay | Visual result |
| --- | --- | ---: | --- |
| off | `debug-captures/android-speed-sprint/20260516-132621-eternal-sonata-field-stock-qualcomm-scene` | `19.35` | correct field |
| fast | `debug-captures/android-speed-sprint/20260516-133117-eternal-sonata-field-stock-qualcomm-scene` | `18.15` | correct field |
| light | `debug-captures/android-speed-sprint/20260516-133619-eternal-sonata-field-stock-qualcomm-scene` | `17.72` | correct field |

Light-mode simpleperf:

- Report:
  `debug-captures/android-speed-sprint/20260516-133619-eternal-sonata-field-stock-qualcomm-scene/simpleperf-report-app.txt`
- Raw data:
  `debug-captures/android-speed-sprint/20260516-133619-eternal-sonata-field-stock-qualcomm-scene/es_field_fast_busy_wait_light.data`
- Still hot: `spu_thread::process_mfc_cmd()` about `28.77%`,
  `spu_llvm_recompiler::exec_mfc_cmd<false>()` about `28.14%`,
  `rsx::thread::run_FIFO()` about `24.46%`, `rx::get_tsc()` about `19.48%`,
  `rx::busy_wait()` about `18.08%`.

Status: `failed`. Global busy-wait batching preserved field visuals but reduced
FPS. The likely failure mode is added synchronization latency in tight SPU/RSX
wait loops. Keep the code gated/off only if useful for future profiling; do not
promote it as a speed path.

## Next Action

The real target is still timing/synchronization, but it needs callsite surgery:

1. Add low-overhead per-callsite counters/timing for `rx::busy_wait()` callers,
   especially SPU MFC/PUTLLC, RSX FIFO, mutex/sema, and VM reservation waits.
2. Attack the biggest stable caller, not global `busy_wait()`.
3. Inspect the unknown JIT block that stays near 15-17 percent self time and
   map it back to SPU/PPU generated code.
4. Keep RSX work focused on `load_texture_env`, `load_program`,
   `upload_vertex_data`, and texture upload churn; the depth barrier alone is
   not enough.
5. Re-test field, first battle, and menu before counting any speed win.

## Wait-Profiler Follow-Up

The first callsite profiler pass found a concrete static-analysis target:

- Capture:
  `debug-captures/android-speed-sprint/20260516-140131-eternal-sonata-field-stock-qualcomm-scene`
- Total profiled waits: `11,250,000`.
- SPU reservation waits dominated: `spu_getllar_retry=8,442,390` calls and
  `spu_getllar=1,556,660` calls.
- Secondary core wait: `vm_passive=1,197,687` calls.
- RSX FIFO and generic semaphore waits were not the dominant wait sites in this
  field sample.

Next slice: add a gated `GETLLAR` retry probe that records top SPU image hash,
PC, block hash, reservation address, and thread/group name, then feed the top
hot SPU local-store window into the Ghidra/static-analysis lane documented in
`debug-experiments/20260516-ghidra-ps3-tooling.md`.
