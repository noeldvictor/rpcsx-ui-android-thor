# Android disabled RSX-auditor overhead removal

## Goal

Remove default-off RSX diagnostic bookkeeping from normal Android Vulkan hot paths while preserving Vulkan/emulation behavior and every separate RSX behavior experiment.

## Scope and safety

- Host-only implementation and verification on 2026-07-19.
- No ADB, APK install, emulator launch, thermal query, or gameplay run was performed.
- This is a code-generation/CPU-pressure candidate, not yet a measured Thor FPS or temperature result.
- Classification: `stackable-cpu-pressure`.

## Pre-change evidence

- The Vulkan RSX auditor has 22 source recording call sites and 20 inline recorder/report definitions.
- With `debug.rpcsx.thor.rsx_auditor` unset/off, every recorder still entered `enabled()`, incremented `g_property_poll_counter`, loaded `g_cached_enabled`, and polled the Android property every 4096 records.
- Baseline ARM64 artifact: build hash `71q4o5w2`, `librpcsx-android.so` size `1,306,458,576` bytes.
- The baseline library contained 65 `rsx_auditor` symbol lines, five retained `record_*` symbols, 41 enabled-recorder accounting-state symbol lines, and the auditor property string.
- In baseline disassembly, the image-barrier caller contained three `LDADD` instructions and one `__system_property_get` call. The buffer- and texture-barrier callers each made two calls to recorder helpers.

## Change

- Normal Android builds now default `RPCSX_THOR_RSX_AUDITOR=OFF`.
- In that build, public `rsx_auditor::enabled()` is an always-inline compile-time `false`, so recorder bodies and call sites fold away under optimized compilation.
- Diagnostic accounting remains available through `-PrpcsxThorRsxAuditor=true` or `RPCSX_THOR_RSX_AUDITOR_BUILD=true` at build time.
- Non-Android builds retain the existing full auditor.
- The DMA-fence, depth-feedback, texture-barrier, and blit-source-resolve behavior getters remain independent and runtime-configurable.

## Behavior contract

- No Vulkan command, barrier, render-pass, queue, cache, pipeline, synchronization, title gate, or frame-timing behavior changed.
- Only recorder counters, reporting, and the disabled auditor property poll are compiled out.
- The four behavior-control properties and their polling state remain in the Android library:
  - `debug.rpcsx.thor.rsx_dma_fence`
  - `debug.rpcsx.thor.rsx_depth_feedback`
  - `debug.rpcsx.thor.rsx_texture_barrier`
  - `debug.rpcsx.thor.rsx_blit_source_resolve`

## Verification

- `tools/test_thor_rsx_auditor_build_gate.ps1`: PASS.
- Wait-profiler, Eternal Sonata frame-poll, and multi-sensor thermal-guard contracts: PASS.
- Complete host-only `tools/test_thor_*.ps1` regression suite: 40/40 PASS.
- New PowerShell contract AST parse: PASS.
- `git diff --check`: PASS.
- ARM64 RelWithDebInfo native build: PASS. The configured cache records `RPCSX_THOR_RSX_AUDITOR:BOOL=OFF`; a final cached verification reported `BUILD SUCCESSFUL`.
- Merged-library symbol audit: 65 -> 10 total auditor symbol lines, 5 -> 0 retained recorder symbols, and 41 -> 0 enabled-recorder accounting-state lines. The ten survivors are the preserved behavior controls and their poll state.
- Property-string audit: the auditor string fell 1 -> 0 while all four behavior-control strings remained.
- Hot barrier disassembly audit: the new combined image/buffer/texture barrier range has zero auditor calls, zero `LDADD` instructions, and zero auditor property reads. The baseline image path had three `LDADD`s plus one property call, while baseline buffer and texture paths each had two recorder calls.
- The unstripped library is 236,040 bytes smaller (`1,306,458,576` -> `1,306,222,536`). This is supporting code-removal evidence, not a runtime metric.
- Thor A/B and thermal proof: pending a separate cool-device session.

## Rollback / diagnostics

Build with `-PrpcsxThorRsxAuditor=true` to restore the complete recorder/reporting path for a diagnostic APK. Revert the Gradle, CMake, header, and contract changes to remove the build gate entirely.
