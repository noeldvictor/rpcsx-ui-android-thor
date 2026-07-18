# 2026-07-18 Thor JIT Object-Cache Zero-Copy

## Result

- Implemented a correctness-neutral host optimization for cached LLVM object
  loading.
- Decompressed object bytes now move into an owning LLVM `MemoryBuffer`
  instead of allocating a second exact-size buffer and copying every byte.
- ARM64 native compilation, ARM64-only optimized ThorTest packaging, and all
  relevant source/APK/export contracts pass.
- The exact APK was installed after a separately cool no-launch gate, then one
  later independently cool runtime was attempted.
- Classify the runtime as `failed-thermal-guard` and `not-comparable`.
- No speed, FPS, flicker, stability, title, gameplay, or temperature-improvement
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

## Guarded runtime evidence

Outer no-launch gate:

- Capture:
  `debug-captures/android-speed-sprint/20260718-123644-thor-input-jit-object-cache-zero-copy-runtime-cool-gate`
- Silicon samples: `31.7 -> 31.7 -> 31.5 C`.
- RPCSX remained stopped.

Only runtime:

- Capture:
  `debug-captures/android-speed-sprint/20260718-123726-thor-input-jit-object-cache-zero-copy-bounded-title-proof`
- Inner preflight: `31.3 -> 31.1 -> 32.3 C`; the `+1.0 C` rise was at the
  strict allowed limit.
- Exact effective controls: cache-phase pacing `off`, RSX auto workers
  `0` (runtime `load=2, compile=2`), RSX preload `256/939`, SPU preload
  `64/1,165`, Vulkan cache `on`.
- PID `23426` established at `12:37:39.1706413`.
- First runtime sample was `59.4 C` at `+2.668 s`.
- The next sample was `78.3 C` at `+5.658 s`; the 72 C hard guard
  force-stopped RPCSX.
- Failure-post-stop silicon was `49.4 C`; captured PID was absent.
- The route failed during the initial 12-second wait, before Start/title, so no
  screenshot, FPS, flicker, menu, gameplay, or stability evidence exists.
- Targeted fatal/access/device-lost/unknown-draw hits: `0`.

The matched full-log control is:

`debug-captures/android-speed-sprint/20260717-185725-thor-input-parallel-rsx-warm-checkpoint-bounded-title-proof`

Cached PPU object-load comparison:

- EBOOT load span: `441.866 -> 436.319 ms` (`-5.547 ms`, about `-1.3%`).
- Runtime/PRX load span: `121.495 -> 114.969 ms` (`-6.526 ms`, about
  `-5.4%`).
- First-to-final cached module: `1,147.522 -> 1,094.236 ms`
  (`-53.286 ms`, about `-4.6%`).
- Final cached module timestamp: `2.949298 -> 2.892478 s` (`-56.820 ms`).
- RSX worker start shifted `1.040324 -> 1.036731 s`; bounded SPU preload
  shifted `2.246577 -> 2.237521 s`.

This is a one-run startup micro-timing signal only. It is too small and too
thermally confounded to promote, and the candidate did not reach any visual
correctness gate.

## Thermal-guard repair

The failed runtime exposed an unsafe sampling gap. A `59.4 C` reading sat
just below the old `60 C` probe, then the next bounded poll observed
`78.3 C`. Host tooling now:

- widens the default probe window from `12 C` to `16 C`, moving the probe
  threshold from `60 C` to `56 C` under the 72 C hard limit;
- takes the immediate confirmation sample as before;
- force-stops if that confirmation remains at or above the probe threshold,
  instead of waiting another poll for the 68 C early threshold;
- preserves the 68 C early stop and 72 C hard ceiling;
- forwards the same safer default through the Eternal Sonata wrapper.

`tools/test_thor_thermal_guard.ps1` includes the observed `59.4 C` case and
requires `silicon-temperature-confirmed-near-limit` to stop. Thermal tests and
PowerShell AST parsing pass. This repair is host-verified only; no second device
launch ran.

## Next guarded step

Keep the Thor stopped after the failed runtime. The zero-copy change may remain
as a small correctness-neutral startup improvement, but reject it as a thermal
fix by itself. Do not spend another device round until host work removes a
larger class of startup work. The strongest next audit is the PPU cache path's
apparent validate-then-load double decompression; preserve corrupted-cache
detection while eliminating redundant inflation if the source flow confirms it.

A later independently cool proof must use the repaired 56 C confirmed-probe
guard. It receives no credit unless it stays below the hard ceiling and reaches
the required visual gates.
