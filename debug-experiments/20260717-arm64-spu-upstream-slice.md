# ARM64 SPU upstream slice audit ? 2026-07-17

## Scope

- Target: AYN Thor Max, Android ARM64, Eternal Sonata `BLUS30161`.
- Upstream reference: local `rpcs3-upstream` checkout through July 2026.
- Android base before this slice: `1f622a134`.
- Thermal policy: host-only audit and build. No ADB query, install, launch, or
  gameplay route was performed.
- Reduced-loop emission remains retired. This slice does not re-enable it.

## Compatibility classification

The audit rewrote upstream `rpcs3/` paths to the vendored
`app/src/main/cpp/rpcsx/rpcs3/` paths, then ran forward and reverse
`git apply --check` against the current Android tree.

| Classification | Upstream commits | Decision |
| --- | --- | --- |
| Forward-clean | `1ec3de9`, `3301674`, `2f2ac69` | Port `1ec3de9` and `2f2ac69`; skip `3301674` because it fixes big-endian host channel waits and Thor is little-endian ARM64. |
| Already exact | `03647fd`, `e3b1b55` | No action. |
| Outside the filtered source paths | `d25972e`, `5758ab1`, `6647c5a` | `d25972e` is already covered by the Android tree's stricter `use_spu_i8mm()` JIT feature gate. The other two are non-performance compatibility fixes outside this title's active path. |
| Diverged, partial, or dependency-bound | `1627757`, `4542020`, `45c6e93`, `7d0df30`, `320e8d6`, `53d76db`, `61a2604`, `7e436f9`, `dff29a7`, `a87d175`, `2d1be09`, `4a92d96`, `6349ea2`, `3164d44`, `e429f8c`, `18fe6ee`, `35f65c2`, `fa5b899`, `3f27cb8`, `09d602f`, `a7fc31f`, `700ca26` | Do not force whole-commit ports. Several overlap existing Android UDOT, shuffle, FCGT, checksum, and I8MM slices; the rest require newer shared analyzer/emitter structure. |
| Unavailable in the shallow reference | `f39d82f` | No claim; the referenced object was not locally available and the offline audit did not fetch it. |

SVE and SVE2 candidates were excluded from Thor promotion. They are not enabled
without an observed device feature report and a separate correctness proof.

## Selected upstream slices

### `1ec3de9` ? SPU analyzer no-regmod fix

The analyzer now exits the default register-modification path when
`spu_itype::zregmod` is set. This prevents an instruction that does not modify
a target register from poisoning `m_regmod`. It is a five-line,
source-compatible correctness fix and does not alter the Android gate surface.

### `2f2ac69` ? idiomatic ARM64 FSM lowering

ARM64 lowering for `FSM`, `FSMH`, `FSMB`, and `FSMBI` now uses vector
mask/compare forms that upstream reports compile to two NEON instructions,
instead of LLVM's scalar fallback. The non-ARM64 path is unchanged. The patch is
29 lines, architecture-gated, and applied without prerequisite refactors.

No Eternal Sonata opcode-frequency proof exists for these four instructions, so
this is a plausible general ARM64 codegen improvement, not a measured game FPS
claim.

## Validation

Command:

`gradlew.bat :app:buildCMakeRelWithDebInfo[arm64-v8a] --no-daemon --console=plain --offline`

Result:

- `BUILD SUCCESSFUL`.
- Built native artifact:
  `app/build/intermediates/cxx/RelWithDebInfo/724a6w64/obj/arm64-v8a/librpcsx-android.so`
- Size: `1,351,013,200` bytes.
- SHA-256:
  `D9077BB56FC92459A1663D9F4493B7150EB2CDB6091E85E26762E01EEE6DA654`
- `git diff --check`: clean.

## Promotion state

Classification: `build-proven`, `device-unmeasured`.

This slice receives no Thor FPS, frame-pacing, flicker, or stability credit yet.
A future cool-device round must use the established field, first-battle, and
menu route and stop immediately on a fatal VM/SPU fault or visible corruption.

## Later guarded bounded-cache follow-up

Capture:

`debug-captures/android-speed-sprint/20260717-145831-thor-input-oldest-spu-bounded-early-start-rsx1`

- This was the only launch in a separately cool round. RPCSX was absent and the
  strict three-sample preflight was `33.1 -> 34.3 -> 33.9 C` with
  `performance_mode=0`, `fan_mode=4`, quick performance/fan enabled, and
  battery saver off.
- The route kept the installed oldest-first APK and exact RSX `256/939`, SPU
  `64/1165`, and Vulkan seed `4,899,180` controls, but reduced RSX preload to
  one worker and sent direct Start presses at about 4.7 and 8.0 seconds after
  process establishment.
- One-worker RSX preload took `0.911 s` from the limit notice to the saved-cache
  line, versus `0.601 s` in the matched two-worker retry. Total startup reached
  the SPU `Workers built 64 programs` line at emulated `3.038952 s`, `0.299 s`
  later than the two-worker retry. Do not promote one RSX worker as a speed
  setting.
- Poll 3 showed a transient progress frame at `30.812 s`; the other four polls
  were black. Neither early Start press produced a title-menu proof.
- The `72 C` guard stopped the process at `72.3 C`, `82.291 s` after process
  establishment. Immediate post-stop silicon was `59.4 C`; PID was absent.
  Targeted fatal, access-violation, and unknown-draw counts were all zero.
- This is a failed title/speed proof. The longer thermal window cannot be
  credited to one worker because it came from a different cool round.

## Android SPU diagnostic hot-path follow-up

The guarded log identified avoidable work in `SPULLVMRecompiler.cpp`:

- `SPU Debug` was false, but 16 decrementer-read functions emitted full SPU
  disassemblies; the captured RPCSX log was `529,579` bytes.
- More importantly, upstream and the local fork built a complete disassembly
  string for every compiled SPU function before deciding whether any diagnostic
  needed it. The bounded startup alone compiled 64 cached programs, followed by
  runtime cache misses.

The host successor now:

- scans for the existing decrementer-read condition first;
- materializes the disassembly only when SPU debug output or the retained
  desktop diagnostic needs it;
- preserves full dumps for explicit SPU debug mode and non-Android builds;
- emits one concise Android notice instead of a full function dump when
  `SPU Debug=false`; and
- preserves the same outer string for later LLVM verification diagnostics.

Validation: exact Android ARM64 syntax-only compilation and the extended
`tools/test_thor_spu_cache_preload.ps1` contract pass. The full host command
`gradlew.bat :app:buildCMakeRelWithDebInfo[arm64-v8a] --offline --no-daemon
--console=plain` completed successfully in `1m 27s`. The built native artifact
is
`app/build/intermediates/cxx/RelWithDebInfo/2t5h1l52/obj/arm64-v8a/librpcsx-android.so`,
size `1,304,469,376` bytes, SHA-256
`95B02FF463B0A4A36448F9422612FBD76C3DC1028CE060898A90AAA307796A0A`.
`git diff --check` is clean. No APK was assembled, installed, or launched.
Classification: `build-proven`, `device-unmeasured`; grant no FPS, thermal,
flicker, title, gameplay, or stability credit yet.
