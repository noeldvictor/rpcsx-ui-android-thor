# 2026-07-19 Thor disabled RSX behavior-experiment overhead

## Result

Bank as host-verified `stackable-cpu-pressure`.

Normal Android play builds now compile out four parked RSX behavior controls:

- `debug.rpcsx.thor.rsx_dma_fence`;
- `debug.rpcsx.thor.rsx_depth_feedback`;
- `debug.rpcsx.thor.rsx_texture_barrier`; and
- `debug.rpcsx.thor.rsx_blit_source_resolve`.

Their stock behavior is expressed as compile-time constants: all-command DMA
fencing remains active, normal depth feedback and texture barriers remain
active, and fused/verify blit-source resolve remains inactive. Desktop retains
the runtime controls. An explicit Android diagnostic build can restore them
with either `-PrpcsxThorRsxExperiments=true` or
`RPCSX_THOR_RSX_EXPERIMENTS_BUILD=true`.

This is not a measured FPS, temperature, flicker, gameplay, or stability win.
No APK was assembled, installed, or launched, and no ADB command ran.

## Why this slice

The four controls were already off for normal play, but their getters still
incremented relaxed atomic polling counters in DMA, render-target, texture, and
blit paths. They periodically refreshed Android properties even while each
experiment was disabled. The experiments are parked behind the Windows/host
proof gates; none has the required correctness-locked 200% evidence for a Thor
play default.

Normal play therefore paid diagnostic dispatch and polling overhead for
behavior that it must not select. This slice removes that work without changing
the active fence, barrier, feedback, or resolve result.

## Implementation

- Added a default-off Gradle/CMake build gate named
  `RPCSX_THOR_RSX_EXPERIMENTS`.
- On normal Android, six public behavior helpers are `constexpr false`:
  `use_host_read_dma_fence`, `persist_readonly_depth_feedback`,
  `skip_texture_barrier`, `fuse_blit_source_resolve`,
  `verify_blit_source_resolve`, and `test_blit_source_resolve`.
- Desktop and explicit diagnostic builds retain the original runtime getters,
  parsers, Android properties, and environment controls.
- The experiment-only `cs_resolve_blit_task`, helper/scratch maps,
  `resolve_blit_image*` implementations, and cleanup are excluded from normal
  Android translation rather than left for the linker to discover as empty
  container state.
- Added `tools/test_thor_rsx_experiments_build_gate.ps1` and updated the
  RSX-auditor contract message to describe the separate behavior gate.

## ARM64 proof

RelWithDebInfo artifacts:

- baseline CMake hash `2q3p4q3l`: `1,305,382,384` bytes;
- candidate CMake hash `4k1e1a74`: `1,305,060,904` bytes;
- whole-library delta: `-321,480` bytes.

The first constant-folding build was `1,305,270,312` bytes (`-112,072`).
Structurally gating the otherwise unused compute-resolve implementation removed
a further `209,408` bytes.

Selected binary inventory:

| Inventory | Baseline | Candidate |
| --- | ---: | ---: |
| Four Android property strings | 4 | 0 |
| Selected mode symbols | 10 | 0 |
| Cached-mode and poll-counter state | 48 bytes | 0 |
| Selected resolve-helper symbols | 15 | 0 |
| Resolve-helper text | 5,164 bytes | 0 |
| Resolve RTTI/vtable/name data | 108 bytes | 0 |
| Resolve helper/scratch container state | 80 bytes | 0 |

The five directly affected stable functions total `20,868 -> 19,804` bytes
(`-1,064`):

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `upload_scaled_image` | 11,992 | 11,424 | -568 |
| `render_target::memory_barrier` | 2,468 | 2,136 | -332 |
| `cached_texture_section::dma_transfer` | 4,656 | 4,448 | -208 |
| `texture_cache::create_new_texture` | 1,632 | 1,552 | -80 |
| `texture_cache::insert_texture_barrier` | 120 | 244 | +124 |

For the same five functions, a conservative disassembly count of `ldadd*`
instructions plus direct selected auditor/property-poll calls changed as
follows:

| Function | Baseline | Candidate | Removed |
| --- | ---: | ---: | ---: |
| `render_target::memory_barrier` | 4 | 2 | 2 |
| `texture_cache::create_new_texture` | 5 | 3 | 2 |
| `cached_texture_section::dma_transfer` | 3 | 1 | 2 |
| `upload_scaled_image` | 22 | 18 | 4 |
| `texture_cache::insert_texture_barrier` | 0 | 0 | 0 |
| **Total** | **34** | **24** | **10** |

Candidate disassembly has no `rsx_auditor` or `__system_property_get` reference
in those affected functions. The 24 remaining atomic instructions belong to
normal emulator synchronization and counters; they are not claimed as removed.

## Verification

- `tools/test_thor_rsx_experiments_build_gate.ps1`: pass.
- `tools/test_thor_rsx_auditor_build_gate.ps1`: pass.
- Full isolated-child-process `tools/test_thor_*.ps1` suite: `47/47` pass.
- PowerShell AST parse for the new contract: pass.
- `git diff --check`: pass.
- Incremental ARM64 `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in
  `1m 6s` after the structural gate.
- Candidate CMake cache: RSX experiments, RSX auditor, wait profiler, syscall
  stats, SPURS probe, draw-stream probe, semaphore superpath, and PPU/SPU
  experiments all `OFF`.
- No ADB, APK install, launch, screenshot, thermal query, or gameplay route ran.

Two mistyped Gradle assembly task names failed during host verification before
any compilation. They did not touch the device or affect the successful native
proof above.

## Decision

Keep this cleanup in the accumulated Thor candidate. It removes recurring
default-off experiment work from normal Vulkan paths and removes the unused
compute-resolve implementation, while preserving exact production semantics
and a deliberate diagnostic opt-in.

Do not claim an FPS or thermal delta from size/disassembly evidence. The next
runtime proof remains one independently cool, hard-temperature-guarded Thor
A/B over the accumulated production build, after the user explicitly says the
device is cool and ready.
