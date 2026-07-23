# 2026-07-23 Thor PPU Thread-Reuse and Thermal-Headroom Audit

## Result

- Classification: host-only upstream rejection plus a guarded next direction.
- Installed candidate remains exact APK `490418F9...D95BF63` and stopped.
- No ADB query, install, launch, APK rebuild, or device measurement occurred.
- Official PPU current-thread recycling commit `24a1576629c711dc688ddccb908e1936aec13333`
  is parked for the current proof lane.

## Upstream PPU Audit

Three official RPCS3 PPU LLVM commits were compared with the vendored Android
path:

- `f05ece47ce67ecb48cb79cb3d244e7cc7c6eb7c9` is already present: the JIT
  module manager has 256 FNV-distributed buckets and no dormant large-module
  shared mutex;
- `b90eef3fa70e247b193cd6b4b1cb7a54d5874990` is already present: worker
  creation checks before and after the compiler-core semaphore and unlocks on
  the failed second check;
- `24a1576629c711dc688ddccb908e1936aec13333` is absent: upstream creates one
  fewer named worker and recycles the calling thread as the final compiler.

The remaining commit is not a fix for the measured regression. Its code is
inside `if (!workload.empty())`, so it runs only for cold PPU cache misses. The
Thor counterproof was an all-hit warm set whose delay occurred later during
object admission/linking. With the managed two-thread cap, recycling changes
`2 named workers + waiting caller` into `1 named worker + compiling caller`;
it does not reduce the two active compile lanes.

On this fork, `thread_op::operator()` owns the Android `0x07` little-core
affinity and low-priority scopes. Recycling would therefore repurpose the
foreign cache-preparation JNI caller, contrary to the deliberate current
contract that only named workers enter those scopes. The RAII restoration is
plausible, but there is no device evidence that this improves temperature or
startup time, and stacking it now would invalidate clean attribution of the
installed default-scheduler warm-link fix.

`tools/test_thor_ppu_compile_caller_isolation.ps1` now locks the current proof
boundary: both already-ported concurrency fixes remain, two named workers own
cold compilation, and no current-thread recycling marker/call is present.

## Current Primary Guidance

Android's current Thermal API guidance explicitly recommends adapting worker
count, worker affinity, frame rate, or fidelity before throttling and warns
that thermal-headroom queries more often than once per 10 seconds may return
`NaN`:

- <https://developer.android.com/games/optimize/adpf/thermal>

The native Performance Hint API is intended for periodic workloads such as
frame production, with target and actual durations reported every cycle. That
matches the existing opt-in RSX frame hint, not one-shot PPU compilation:

- <https://developer.android.com/ndk/reference/group/a-performance-hint>

A 2024 asymmetric-ARM study also supports workload-aware task allocation
across heterogeneous cores, but it is not emulator- or Snapdragon-specific
and does not justify changing Thor affinity without measurement:

- <https://arxiv.org/abs/2402.04090>

Vulkan's official guidance still favors persistent pipeline-cache reuse to
avoid draw-time compilation; that path is already implemented and validated
in this fork:

- <https://docs.vulkan.org/samples/latest/samples/performance/pipeline_cache/README.html>

## Next Experiment Boundary

After the installed candidate gets one separately cool title proof, the next
host change should be a default-off, API-29-safe native Thermal API capability
probe:

1. resolve API-31 thermal functions dynamically rather than importing them;
2. sample once before cold PPU compilation and no more frequently than every
   10 seconds;
3. log headroom/status, selected worker count, and affinity without changing
   scheduling in the first diagnostic build;
4. only after matched support/temperature evidence, compare fixed two-little-
   core compilation with a headroom-driven `1 <-> 2` worker policy;
5. keep runtime PPU/SPU/RSX/audio/render threads outside the startup policy.

This design targets sustainable temperature directly and preserves clean
attribution. It earns no speed, thermal, flicker, gameplay, or stability
credit until device-measured.

## Observation-Only Probe Implemented

The host follow-through implements the first diagnostic boundary without
changing scheduling:

- the Gradle/CMake build gate is default-off;
- normal Android and desktop builds compile the probe to constant no-ops;
- the diagnostic Android build resolves the API-30/31 Thermal API entry points
  from `libandroid.so`, preserving the app's API-29 load boundary;
- the property and title gates restrict one process-lifetime sample to
  `BLUS30161`;
- the sample logs headroom, thermal status, PPU worker count, and affinity,
  always with `scheduling=unchanged`;
- route tooling resets the transient property before launch and after both
  success and failure.

ARM64 native builds passed with the diagnostic both enabled and disabled. The
diagnostic compile tree contains the probe definition; the final default-off
tree contains zero such definitions. All `69/69` Thor host contracts pass,
including the new build/route gate. The exact candidate artifact contract
still passes for APK `490418F9...D95BF63`, merged core
`9049E583...5AB749E`, and packaged core `C0007C41...CDED102`.

No APK was rebuilt, installed, or launched for this implementation pass, and
no ADB query occurred. The exact installed candidate remains stopped and
authoritative. This diagnostic therefore earns no speed, temperature,
flicker, gameplay, or stability credit. Its first permitted runtime use is a
separately guarded title proof; only supported, repeatable headroom evidence
can justify a later `1 <-> 2` PPU startup-worker experiment.