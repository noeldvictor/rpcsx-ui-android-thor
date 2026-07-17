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
`git diff --check` is clean.

## ThorTest package and no-launch installation

The exact build was packaged host-side with:

`gradlew.bat :app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a
-PbuildBundledRpcsxCore=true --offline --no-daemon --console=plain`

Result:

- `BUILD SUCCESSFUL` in `53s`.
- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`,
  `73,573,554` bytes, SHA-256
  `853098D6BDD700A1008957C6977D6863B2E87F2FE95842F4D1F0AD3CF2FCFB22`.
- Merged core SHA-256: `95B02FF4...0A0A`.
- Packaged stripped core SHA-256: `BE37AE118E7E87C2030A2D6EBB55A2A1EA7964360BA3CCDEF6851CE298B868E4`.
- `tools/test_thor_arm64_apk.ps1` and
  `tools/test_thor_optimized_apk_contract.ps1` both pass.

The exact APK was installed without launch on the AYN Thor at
`2026-07-17T15:44-04:00` after a separately cool, PID-absent preflight:

- model/device: `AYN Thor` / `kalama`, Android 13;
- strict silicon samples: `32.7 -> 32.3 -> 32.7 C`, with `0.0 C` net rise;
- battery/skin: `24.0 / 30.0 C`;
- power state: performance mode `0`, fan mode `4`, quick performance/fan `1`,
  and battery saver `0`;
- `adb install -r` result: `Success`;
- installed `base.apk` SHA-256:
  `853098D6BDD700A1008957C6977D6863B2E87F2FE95842F4D1F0AD3CF2FCFB22`,
  exactly matching the host candidate; and
- post-install state: RPCSX PID absent, silicon `33.1 C`, battery `24.0 C`.

The experiment controls remained at their safe idle defaults: RSX preload
`preload`, RSX worker/limit overrides `0/0`, SPU preload limit `0`, Vulkan
pipeline cache `on`, and the title-specific HLE/repair/probe switches `off`.
No emulator route ran in this install round. Classification:
`installed-exact`, `device-runtime-unmeasured`; grant no FPS, thermal-runtime,
flicker, title, gameplay, or stability credit. A different independently cool
round may spend exactly one guarded bounded route with RSX limit `256`, SPU
limit `64`, normal two-worker/auto scheduling, and Vulkan cache on.

## Guarded proof preflight rejection

Capture:

`debug-captures/android-speed-sprint/20260717-155546-thor-input-lazy-spu-bounded-title-proof`

- A read-only outer gate first verified the exact installed APK
  `853098D6...FB22`, PID absence, the matched AYN power state, and silicon
  `32.7 -> 32.3 -> 32.3 C`.
- The route harness then ran its independent lossless telemetry preflight and
  measured `32.5 -> 33.5 -> 33.9 C`. The `1.4 C` rise exceeded the strict
  `1.0 C` limit.
- The harness failed closed before `debug-boot.txt`, process establishment,
  input, or any emulator workload, and issued the normal force-stop.

Classification: `preflight-rejected`, `device-runtime-unmeasured`. No route
ran and no speed, title, FPS, flicker, gameplay, thermal-runtime, or stability
credit exists. Do not retry in this round.

## Android PPU loader logging follow-up

The previous `529,579`-byte RPCSX log contained `1,284` successful function
export rows and `176` successful function import rows. Together those `1,460`
rows occupied `267,555` bytes (`50.52%` of the log). Current upstream retains
the same notice-level behavior.

The Android build now compiles out successful per-symbol PPU function export,
variable export, and function import logging. It also avoids the corresponding
function/variable-name lookup and formatting. Module summaries, invalid
function errors, illegal-descriptor warnings, duplicate-link diagnostics, and
the full desktop log remain intact.

Validation:

- `tools/test_thor_ppu_loader_logging.ps1`: pass;
- PowerShell AST parse and `git diff --check`: pass;
- optimized ARM64 build: `BUILD SUCCESSFUL in 1m 3s`;
- merged core: `1,304,460,552` bytes, SHA-256
  `A2C16F88C7ED459C0C88294461ECD0B8401804A9BC348C6F8E02ED1C519554C7`;
- ThorTest package: `BUILD SUCCESSFUL in 21s`, `73,573,150` bytes, SHA-256
  `11648B07ACC8631DA83429CC857A7633BF5A6DA4D4D2330C89FDCCFE9DC9B98B`;
- packaged stripped core: `62,842,760` bytes, SHA-256
  `6D4F70BA833FA2DCB4E2C4A26CE698EB4D0953B188DA6BDEE7405365592CD048`; and
- ARM64 APK, optimized ThorTest, SPU cache preload, and PPU loader logging
  contracts: pass.

The exact APK was installed without launching RPCSX in a later independently
cool round. The lossless 27-zone silicon preflight was
`31.9 -> 31.9 -> 31.7 C` (`-0.2 C` net rise), RPCSX was stopped, and the AYN
power state matched performance mode `0`, fan mode `4`, quick performance/fan
`1`, and battery saver `0`. `adb install -r` succeeded; the installed
`base.apk` SHA-256 is exactly
`11648B07ACC8631DA83429CC857A7633BF5A6DA4D4D2330C89FDCCFE9DC9B98B`.
RPCSX remained stopped and post-install silicon was `33.1 C`.

Classification: `installed-exact`, `device-runtime-unmeasured`; grant no
speed, FPS, flicker, title, gameplay, thermal-runtime, or stability credit.
This install round is closed. Only a different independently cool round may
spend one guarded bounded route with RSX limit `256`, SPU limit `64`, normal
two-worker/auto scheduling, and Vulkan cache on.

## Guarded PPU-log-pruned proof

Capture:

`debug-captures/android-speed-sprint/20260717-162053-thor-input-ppu-log-pruned-bounded-title-proof`

The exact installed APK passed an outer `32.5 -> 31.5 -> 31.5 C` query and the
harness's independent `33.1 -> 33.9 -> 33.1 C` preflight with matched AYN
power state. RSX preload `256/939`, automatic two-worker scheduling, SPU
preload `64/1,165`, and the `4,899,180`-byte Vulkan driver cache all activated.

Silicon reached `64.2 C` at the first runtime poll and `77.1 C` only `5.681 s`
after process establishment. The `72 C` guard force-stopped RPCSX during the
initial 12-second wait, before Start input, title polling, or screenshots.
Failure-post-stop silicon was `50.6 C`, a later read-only sample was `45.3 C`,
and the PID remained absent.

The Android logging change is dynamically proven: compared with the preceding
`529,579`-byte / `6,482`-line log, this capture produced `145,305` bytes /
`1,402` lines. Successful per-symbol PPU linkage rows fell from `1,462` to
zero, all `44` module summaries remained, and the `16` SPU decrementer notices
used the concise Android form. Targeted guest/native/Vulkan/unknown-draw fatal
matches were zero. The process-to-guard window remained effectively unchanged
from the earlier matched two-worker route (`5.737 s`).

Classification: `failed-thermal-guard`, `device-runtime-unmeasured`. The log
I/O reduction is proven but thermally neutral; grant no title, FPS, flicker,
gameplay, or stability credit. Do not retry in this round. Host follow-up is a
split RSX preload scheduler: preserve two cheap load workers but use one hot
pipeline compile worker in Android auto mode, while retaining explicit worker
overrides for rollback and comparison.

## Split RSX preload-worker candidate

The two matched auto/two-worker routes reached their thermal guards after
`5.737 s` and `5.681 s`. The intervening explicit one-worker route stayed
within its `72 C` ceiling for `82.291 s`, although it reached neither title nor
a comparable speed checkpoint and started the PPU path `0.299 s` later.

Android auto mode now retains two workers for parallel cached-pipeline file
loading/unpacking but uses one worker for the expensive Vulkan pipeline compile
phase. A positive `debug.rpcsx.thor.rsx_cache_workers` override or explicit
shader compiler thread count remains authoritative, and desktop behavior is
unchanged.

Validation:

- RSX preload, Vulkan cache, thermal guard, optimized-variant, SPU preload, PPU
  loader logging, and ARM64 APK contracts: pass;
- PowerShell AST parsing and `git diff --check`: pass;
- optimized ARM64 build: `BUILD SUCCESSFUL in 1m 35s`;
- merged core: `1,304,462,264` bytes, SHA-256
  `B955729BAFE4EE6610637F467222632AB315EC65AF01CE4D899371E6F1113CAC`;
- ThorTest package: `BUILD SUCCESSFUL in 26s`;
- APK: `73,572,162` bytes, SHA-256
  `3C572601110144DB33B8B7F997F2D0AD2E5D078F90D7D9067A73F7A566CC1282`;
- packaged stripped core: `62,842,936` bytes, SHA-256
  `BFAE054B9FA86A44B0EF7733055F33A49F9490DC2B9AF49F7D4F6AB84A934EB4`;
  and
- explicit worker overrides and configured runtime cache-miss fallback remain
  covered by the source contract.

The exact APK was installed without launching RPCSX after a separately cool,
PID-absent preflight. Capture:

`debug-captures/android-speed-sprint/20260717-170146-split-rsx-thortest-apk-install`

The first host parse rejected the samples as unknown because direct Windows
ADB invocation collapsed the thermal-zone separators. The original raw files
were preserved; host-only normalization recovered 30 silicon sensors per
sample without another device query. The strict samples were
`33.9 -> 33.9 -> 33.3 C` (`-0.6 C` net rise), with battery/skin
`24.0 / 30.0 C`. Power state remained performance mode `0`, fan mode `4`,
quick performance/fan `1`, and battery saver `0`.

`adb install -r` returned `Success`; the installed `base.apk` SHA-256 is
`3C572601110144DB33B8B7F997F2D0AD2E5D078F90D7D9067A73F7A566CC1282`,
exactly matching the `73,572,162`-byte host candidate. RPCSX was absent before
and after the install. Post-install silicon was `35.1 C`, so device activity
ended there. RSX worker/RSX limit/SPU limit are `0/0/0`, Vulkan cache is `on`,
and the three Eternal Sonata experiment switches are `off`.

Classification: `device-install-proven`, `device-runtime-unmeasured`; grant no
speed, thermal-runtime, title, FPS, flicker, gameplay, or stability credit.
This install-only round is closed. A different independently cool round may
spend exactly one guarded bounded proof.

## Runtime thermal confirmation guard

The latest two-worker route sampled `64.2 C` and then `77.1 C` only `2.986 s`
later. The requested `72 C` ceiling therefore overshot by `5.1 C` before the
normal two-second sleep plus telemetry round trip could react.

The Thor input route now defaults to a `72 C` hard silicon limit. Normal cool
polling remains two seconds, but a sample at or above `60 C` (the default
12-degree confirmation window) immediately requests a second lossless thermal
snapshot without another sleep. An initial or confirmed sample at or above
`68 C` (four degrees of early-stop headroom) force-stops RPCSX. The existing
battery, skin, unknown-sensor, and absolute silicon checks remain fail-closed;
the three-sample cool preflight is unchanged. Both thresholds are bounded
parameters and the speed-sprint wrapper forwards them.

Host verification passed the thermal, visual-route, optimized-variant,
single-core-load, and split-RSX-worker contracts plus PowerShell AST parsing
and `git diff --check`. Replaying the captured values classifies `64.2 C` as
`confirm` with probe/stop thresholds `60/68 C`, and `77.1 C` as `stop`.

Classification: `route-tooling`, `thermal-safety-candidate`,
`device-unmeasured`. No Thor install or launch occurred, and the replay cannot
prove the temperature an immediate live confirmation will observe. Grant no
speed, title, FPS, flicker, gameplay, thermal-runtime, or stability credit.
The split-worker APK remains unchanged at
`3C572601110144DB33B8B7F997F2D0AD2E5D078F90D7D9067A73F7A566CC1282`
and is now installed exactly after the no-launch round above. Use only a
different independently cool round for its first guarded runtime proof.

## Split-worker guarded proof and auto-mode correction

Outer cool gate:

`debug-captures/android-speed-sprint/20260717-171210-split-rsx-workers-runtime-cool-gate`

The exact installed APK and absent RPCSX PID were re-proved before launch.
Battery/skin were `23.0 / 30.0 C`; silicon was
`33.5 -> 32.7 -> 33.5 C` (`0.0 C` net rise). The independently sampled route
preflight was `33.9 -> 33.1 -> 33.9 C`, also with `0.0 C` net rise and the
same AYN power state.

Guarded route:

`debug-captures/android-speed-sprint/20260717-171312-thor-input-split-rsx-workers-bounded-title-proof`

The route exposed a configuration bug before it could evaluate the intended
split: the activation row was `Shader cache preload workers: load=2,
compile=2`, not `load=2, compile=1`. `debug.rpcsx.thor.rsx_cache_workers=0`
was documented and set as auto mode, but the native parser accepted only
positive values and treated zero as absent. Eternal Sonata's managed profile
then supplied its explicit two-thread value.

All other matched startup controls activated: RSX preload `256/939`, SPU
preload `64/1,165`, and the `4,899,180`-byte Vulkan cache. Against the preceding
two-worker capture, matched core timestamps differed by only about `4.5-7.2
ms`; this is the same behavior, not a speed result. The live safety successor
did work: the first runtime sample was `65.4 C`, it requested an immediate
confirmation, and the confirmation measured `68.7 C` only `0.609 s` later.
RPCSX was force-stopped at the `68 C` early threshold below the `72 C` hard
limit, before Start input, title polling, or screenshots. Failure-post-stop
silicon was `46.2 C`, the standard snapshot was `44.1 C`, and PID was absent.
Targeted guest/native/Vulkan/unknown-draw matches were zero.

Classification: `failed-thermal-guard`, `split-worker-not-activated`; grant no
speed, title, FPS, flicker, gameplay, or stability credit. The live
confirmation/early-stop guard is proven, but the intended scheduling change is
not.

The host successor makes zero a real Android auto override while preserving
positive property overrides and explicit config behavior when the property is
absent. Thor startup defaults and the managed Eternal Sonata profile now use
shader compiler threads `0`; profile version `14` migrates existing global
settings. The manual profile tool also defaults to auto, and the RSX contract
now rejects zero-parser or managed-profile regressions.

Validation:

- RSX preload, Vulkan cache, SPU preload, PPU logging, thermal guard, visual
  route, single-core load, optimized variant, ARM64 APK, and export-surface
  contracts: pass;
- PowerShell AST parsing and `git diff --check`: pass;
- optimized ARM64 native build: `BUILD SUCCESSFUL in 13s` after the initial
  clean object build completed;
- merged core: `1,305,550,152` bytes, SHA-256
  `B1920245781695F51DF4698355A0830C02B30ABBEE780DE52FFBABE921649F1A`;
- ThorTest package: `BUILD SUCCESSFUL in 2m 10s`;
- APK: `73,572,242` bytes, SHA-256
  `D463FED6A9535E55575B0FABC0CA87454CA391F7F340664186DAAA7AE4A424F8`;
  and
- packaged stripped core: `62,842,968` bytes, SHA-256
  `992921FC2ECFE1C6C67CFFFF04F2137676F4E4D6F3C51F8B274750B54C23CEB9`.

This corrected APK is host-only and not installed. Classification:
`thermal-stability-candidate`, `device-unmeasured`. A later separately cool
round may install it without launch; only a different independently cool round
may spend its guarded runtime proof.

## Corrected auto-worker no-launch install

Cool gate:

`debug-captures/android-speed-sprint/20260717-175708-thor-input-corrected-rsx-auto-worker-install-cool-gate`

The input harness was invoked with `ForceStop` and no boot path. Battery/skin
were `23.0 / 30.0 C`, silicon was `33.5 -> 32.7 -> 33.5 C` (`0.0 C` rise),
and RPCSX remained absent. No emulator activity or route input was allowed.

Install capture:

`debug-captures/android-speed-sprint/20260717-175947-corrected-rsx-auto-worker-thortest-apk-install`

The exact `73,572,242`-byte APK SHA-256
`D463FED6A9535E55575B0FABC0CA87454CA391F7F340664186DAAA7AE4A424F8`
installed successfully through streamed `adb install -r`. The installed
`base.apk` hash matches exactly. RPCSX PID was absent before and after install.
Idle properties are RSX workers/RSX limit/SPU limit `0/0/0`, Vulkan cache
`on`, and PPU interpreter/dispatch probe/async draw barrier all `off`.
Post-install battery/skin/silicon were `23.0 / 30.0 / 34.7 C`.

Classification: `device-install-proven`, `device-runtime-unmeasured`. Grant
no startup, thermal-runtime, title, FPS, flicker, gameplay, or stability
credit. Do not launch in this install round. One later independently cool
round may spend one bounded guarded proof and must first prove the intended
`Shader cache preload workers: load=2, compile=1` activation row under the
same RSX `256`, SPU `64`, Vulkan-cache-on controls.
