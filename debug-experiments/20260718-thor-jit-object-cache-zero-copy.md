# 2026-07-18 Thor JIT Object-Cache Zero-Copy

## Result

- Implemented a correctness-neutral host optimization for cached LLVM object
  loading.
- Decompressed object bytes now move into an owning LLVM `MemoryBuffer`
  instead of allocating a second exact-size buffer and copying every byte.
- ARM64 native compilation, ARM64-only optimized ThorTest packaging, and all
  relevant source/APK/export contracts pass.
- Classify this as `installed-exact-no-launch` and `not-comparable`.
- The exact APK is now installed after a separately cool no-launch gate. It was
  not launched. No speed, FPS, flicker, stability, or runtime-temperature
  credit is claimed.

## Why this path was selected

The matched full Thor log is:

`debug-captures/android-speed-sprint/20260717-185725-thor-input-parallel-rsx-warm-checkpoint-bounded-title-proof/failure-RPCSX.log`

It records 47 `PPU: LLVM: Loaded module` events:

- 42 EBOOT object loads from about `1.802-2.244 s`;
- 5 runtime/PRX object loads from about `2.828-2.949 s`;
- RSX cache workers already run from about `1.040 s`;
- bounded SPU preload starts around `2.247 s`.

This object-load work therefore overlaps the hottest startup interval already
identified in the thermal failure. The old compressed-cache path performed:

1. compressed file read into `cached_data`;
2. gzip inflate into `out`;
3. a second allocation through `WritableMemoryBuffer`;
4. a full `memcpy` from `out` into that second buffer.

The new `vector_memory_buffer` owns the moved `out` vector directly and
adds the trailing null byte required by LLVM. Object bytes, cache keys,
validation, object parsing, symbol resolution, and LLVM ownership lifetime are
unchanged. The uncompressed raw-cache fallback is also unchanged.

## Upstream audit

The comparison checkout was at RPCS3 commit
`a18afa4037b25af1b285cdf109e1d6250b478234`.
`Utilities/JITLLVM.cpp` still contained the same second allocation and
`memcpy` sequence at lines 511 and 519-520. This round is a local optimization,
not an upstream cherry-pick.

## Research decision

- Coordinated mobile CPU/GPU/memory control is more promising than letting
  independent governors maximize concurrent startup work:
  <https://arxiv.org/abs/2507.02135>
- CPU/GPU co-scheduling work supports treating scheduling and power limits as a
  system-wide optimization problem:
  <https://arxiv.org/abs/2405.03831>
- Sustained mobile measurements show why cold peak throughput is not enough for
  promotion:
  <https://arxiv.org/abs/2603.23640>
- GPU energy sweet spots are architecture- and workload-specific, so any Thor
  operating-point change needs guarded per-scene A/B proof:
  <https://arxiv.org/abs/2607.00819>
- JIT code-cache research supports reducing compilation and cache-materializing
  overhead instead of discarding reusable code:
  <https://arxiv.org/abs/1810.09555>

Android ADPF remains a later sustained-workload lane:
<https://developer.android.com/games/optimize/adpf/thermal> and
<https://developer.android.com/games/optimize/adpf>.

- Thermal Headroom follows slow-moving sensors and needs multiple samples. The
  observed startup guard failure developed in about `3.275 s`, so headroom is
  not a safe direct control loop for this hotspot.
- Performance Hint sessions target long-lived periodic thread groups. The
  cache-load workers here are short startup phases.
- Power Efficiency Mode requires API 35 and runtime support. Thor support has
  not been probed because this round intentionally performed no device action.

ADPF may later provide capability-gated telemetry and sustained emulation hints,
but it was not mixed into this single-variable startup optimization.

## Host verification

- `tools/test_thor_jit_object_cache_buffer.ps1`: pass.
- `tools/test_thor_cache_phase_pacing.ps1`: pass.
- ARM64 RelWithDebInfo native build: pass.
- ARM64-only optimized ThorTest assembly: pass.
- ThorTest APK ABI contract: pass.
- optimized test-hook contract: pass.
- RSX cache preload contract: pass.
- SPU cache preload contract: pass.
- multi-sensor thermal guard contract: pass.
- core export/relocation contract: pass (34 dynamic exports, 583 explicit
  relocations, 391 `JUMP_SLOT` relocations, 44,219 encoded relocation bytes).
- `git diff --check`: pass before ledger update.

Exact ARM64 ThorTest artifact:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,574,302` bytes.
- APK SHA-256:
  `E69D671D2B6F74BAC6DEAF2A3A08D7DC98877B0F8654E7C89AC2A0BA68B6C509`
- Merged ARM64 core size: `1,305,620,720` bytes.
- Merged ARM64 core SHA-256:
  `519D94C4B93433B41EA780EE0F481CAE1486C89EF594D578E893518EF2F6A68E`
- Packaged stripped core size: `62,847,384` bytes.
- Packaged stripped core SHA-256:
  `C08490978D7BE045A995578CEC7A812AF9BBC43F2BEF942ACECD380DD0E06BA6`

## Device install-only evidence

Strict no-launch gate:

- Capture:
  `debug-captures/android-speed-sprint/20260718-123118-thor-input-jit-object-cache-zero-copy-install-cool-gate`
- Device serial: `c3ca0370`.
- `BootGame: False`; `ForceStop: True`.
- Silicon samples: `31.5 -> 31.9 -> 31.3 C`.
- Maximum silicon: `31.9 C`; net trend: `-0.2 C`.

Exact no-launch install:

- Capture:
  `debug-captures/android-speed-sprint/20260718-123159-jit-object-cache-zero-copy-thortest-apk-install`
- Status: `installed-exact-no-launch`.
- Cool-gate age at validation: `0.5 minutes`.
- Host and on-device `base.apk` SHA-256 both equal
  `E69D671D2B6F74BAC6DEAF2A3A08D7DC98877B0F8654E7C89AC2A0BA68B6C509`.
- RPCSX PID was absent before and after installation.
- Controls remained RSX workers/limit and SPU limit `0/0/0`, Vulkan cache
  `on`, and PPU interpreter/dispatch/async-draw experiments `off`.
- Post-install temperatures: battery `22.0 C`, skin `30.0 C`, silicon
  `34.1 C`.
- Emulator launch: no.

This is install identity and thermal-safety evidence only. Classify it as
`installed-exact-no-launch` and `not-comparable`.

## Next guarded step

Keep the Thor stopped for the completed install round. Only a later
independently cool round may run one bounded title proof with the existing
thermal guard. Keep cache-phase pacing off so the decompressed-buffer ownership
change remains the only active startup variable. Compare the PPU object-load
window, process-to-title or guard arrival, temperature slope, and visual
correctness against the matched control. Reject it if the change only shifts
timing or if the title/menu flicker persists.
