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

## Corrected split-worker proof and parallel warm-cache successor

Outer cool gate:

`debug-captures/android-speed-sprint/20260717-180503-thor-input-corrected-split-rsx-runtime-cool-gate`

RPCSX stayed absent while silicon sampled `32.7 -> 33.5 -> 33.5 C`; the
`+0.8 C` rise passed the strict `1 C` limit. Battery/skin were
`23.0 / 30.0 C`. The independently sampled route preflight then held
`33.5 -> 33.5 -> 33.5 C`. Prelaunch power state matched the preceding route:
performance mode `0`, fan mode `4`, quick performance/fan `1`, battery saver
`0`, WALT CPU governors, and `msm-adreno-tz` GPU governor.

Guarded route:

`debug-captures/android-speed-sprint/20260717-180556-thor-input-corrected-split-rsx-workers-bounded-title-proof`

The corrected parser and managed profile activated exactly as intended:
`debug.rpcsx.thor.rsx_cache_workers=0` produced `load=2, compile=1`; RSX
preload was `256/939`, SPU preload was `64/1,165`, and the Vulkan driver cache
accepted the `4,899,180`-byte seed. PID `19045` was established at
`18:06:08.9548702`; the first two-second runtime poll at
`18:06:11.6752655` was already `68.2 C`. The guard therefore force-stopped
immediately at the `68 C` early threshold, `2.720395 s` after establishment
and below the `72 C` hard limit. Post-stop silicon was `46.2 C`, PID was
absent, and the targeted fatal/access-violation/device-lost/unknown-draw scan
had zero matches. The stop happened during `wait:12000`, before Start, title
polling, or any screenshot.

The split is not a speed or thermal win. Under the same power state, the prior
two-compile-worker route first sampled `65.4 C` at `2.658222 s` after PID and
stopped at `68.7 C` after `3.266820 s`. Corrected matched startup timestamps
were also later: worker activation `1.158017` versus `1.035883`, Vulkan-cache
save `1.674479` versus `1.502757`, PPU OPD `1.691140` versus `1.513522`, SPU
limit `2.446624` versus `2.253982`, and SPU interpreter `2.588600` versus
`2.394806`. The current log ended at `2.678867` while the SPU workers were
still compiling, whereas the two-worker route finished all 64 functions at
`2.794049`. Reject the automatic 2-load/1-compile split; it adds about
`0.19 s` before the SPU lane without lowering the observed thermal spike.

The same logs expose removable work without a correctness tradeoff. A warm
Android cache scheduled its first periodic checkpoint at 256 creates, exactly
the bounded preload size, then synchronously serialized and rewrote the same
`4,899,180`-byte cache before PPU startup (`pipelines=256` in the corrected
run, `257` in the prior run). The host successor now uses the same capped,
dynamic worker count for load and compile, so auto mode returns to
`load=2, compile=2`. It also moves only Android's validated-warm first
checkpoint to 512 creates. Cold/rejected seeds retain 32/64/128/... crash-safe
checkpoints, desktop warm caches retain 256, normal/final shutdown still
persists all progress, and omitted RSX/SPU entries retain their normal runtime
cache-miss paths.

Host validation passed the RSX, Vulkan-cache, SPU, PPU-logging, optimized
variant, single-core-load, thermal, and visual-route source contracts. The
optimized ARM64 core built successfully in `77.3 s`. The first unscoped APK
was rejected by the arm64 gate because it also contained x86_64; the required
arm64-only package then passed in `19 s`:
`:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a -PbuildBundledRpcsxCore=true`.

Exact host-only candidate:

- merged core: `1,305,549,504` bytes, SHA-256
  `2B62F62ED746BB41A0E6B9CB188C963B2CFF827FDABA187B304C7CF14B03ADBA`;
- stripped core: `62,842,792` bytes, SHA-256
  `BD2BB6225FE91BBE10C23FB4DA866158839F17919104B49CD75C8ED7CF566C4E`;
- arm64-only ThorTest APK: `73,572,618` bytes, SHA-256
  `24F3F26785681A96AFD152574FB82206FC5EBDDF508F194ADDF46DE575E3F87F`;
  and
- export surface: 34 defined dynamic symbols, 583 explicit relocations, 391
  jump slots, and 44,219 encoded relocation bytes.

Classification: the device route is `failed-thermal-guard` and
`split-worker-rejected`, with no title/FPS/flicker/gameplay/stability credit.
The parallel/warm-checkpoint successor is `startup-performance-candidate`,
`host-verified`, `device-unmeasured`. It was not installed or launched in this
round. Only a separately cool no-launch round may install the exact APK; a
different independently cool round is required for one bounded guarded proof.

## Parallel candidate install gate rejected

Capture:

`debug-captures/android-speed-sprint/20260717-184037-thor-input-parallel-rsx-warm-checkpoint-install-cool-gate`

This was deliberately a no-boot, force-stop-only gate before installing exact
candidate APK SHA-256
`24F3F26785681A96AFD152574FB82206FC5EBDDF508F194ADDF46DE575E3F87F`.
The route first force-stopped RPCSX and reset RSX workers/RSX limit/SPU limit
to `0/0/0`, Vulkan cache to `on`, and all three Eternal Sonata experiment
switches to `off`. `BootGame=False`; no input macro or install command ran.

Battery/skin stayed `23.0 / 30.0 C`. Silicon sampled
`33.9 -> 33.9 -> 35.1 C`. Sample three was at or above the strict `35 C`
absolute ceiling, and its `+1.2 C` rise would also exceed the `1 C` trend
limit. The guard failed closed and force-stopped RPCSX. Do not retry, install,
or query again in this round.

This rejection exposed an evidence gap: the preflight call was outside the
macro's standard `try/catch`, so the capture retained its force-stop and full
thermal log but not the usual failure PID/snapshot files. Do not infer a
post-failure PID from those missing files. The host successor moves preflight
inside the standard failure path and includes `ForceStop` in catch cleanup;
future rejections preserve the failure text, a post-stop thermal sample, PID
and standard snapshots when requested, while still running before any boot.
Thermal/visual source contracts and PowerShell AST parsing pass. The emulator
APK and native core are unchanged.

Classification: `rejected-preflight`, `candidate-not-installed`,
`device-runtime-unmeasured`, plus host-only `thermal-evidence-tooling`. The
next device step remains one later strict cool install-only gate; runtime proof
belongs to a different independently cool round.

## Parallel candidate installed after later cool gate

Later no-boot gate:

`debug-captures/android-speed-sprint/20260717-184845-thor-input-parallel-rsx-warm-checkpoint-install-cool-gate-retry`

RPCSX was force-stopped and its PID remained absent. Battery/skin held
`23.0 / 30.0 C`; all three silicon samples were `33.1 C`, below the strict
`35 C` ceiling with zero rise. The gate completed without booting or driving
input, so the exact candidate was eligible for install in this later round.

Install capture:

`debug-captures/android-speed-sprint/20260717-185027-parallel-rsx-warm-checkpoint-apk-install`

The streamed install completed in `8.543 s`. The host APK remained exactly
`73,572,618` bytes with SHA-256
`24F3F26785681A96AFD152574FB82206FC5EBDDF508F194ADDF46DE575E3F87F`,
and the installed package's `base.apk` produced the same SHA-256. PID was
absent before and after install. Idle properties were reset to RSX workers,
RSX preload, and SPU preload `0/0/0`; Vulkan pipeline cache was `on`; PPU
interpreter, dispatch probe, and async draw barrier were all `off`.

The one post-install sample recorded battery/skin/silicon at
`23.0 / 30.0 / 35.1 C`. No app launch, game boot, input, or runtime route ran.
Classification is `device-install-proven`, `device-runtime-unmeasured`.
Grant no startup, thermal-runtime, title, FPS, flicker, gameplay, or stability
credit in this round.

The exact APK is now installed and the package is stopped. One different,
independently cool round may spend one guarded bounded title proof. It must
first prove `Shader cache preload workers: load=2, compile=2`, retain the
RSX `256` and SPU `64` preload bounds, and show that the validated-warm Vulkan
cache does not synchronously rewrite at 256 creates before any speed claim.

## Parallel warm-checkpoint proof and SPU diagnostic-pruning successor

Outer no-boot cool gate:

`debug-captures/android-speed-sprint/20260717-185632-thor-input-parallel-rsx-warm-checkpoint-runtime-cool-gate`

RPCSX remained absent while silicon sampled `32.7 -> 33.1 -> 33.5 C`.
The `+0.8 C` trend passed the strict `1 C` limit, so this independently cool
round was eligible for exactly one guarded route.

Guarded route:

`debug-captures/android-speed-sprint/20260717-185725-thor-input-parallel-rsx-warm-checkpoint-bounded-title-proof`

The inner preflight passed at `33.1 -> 32.7 -> 32.9 C`. Prelaunch power state
matched the preceding comparison: performance mode `0`, fan mode `4`, quick
performance/fan `1`, low-power mode `0`, WALT CPU governors, and
`msm-adreno-tz` GPU governor. The exact installed APK remained
`24F3F26785681A96AFD152574FB82206FC5EBDDF508F194ADDF46DE575E3F87F`.

The intended controls activated: the validated `4,899,180`-byte Vulkan seed
logged first checkpoint `512`, RSX loaded `256/939`, shader workers were
`load=2, compile=2`, and SPU loaded `64/1,165`. There was no synchronous
`Saved Vulkan driver pipeline cache` row at the old 256-create boundary.
Matched core timestamps were effectively neutral versus the earlier two-worker
route: workers `1.040324` versus `1.035883`, PPU OPD `1.505481` versus
`1.513522`, SPU limit `2.246577` versus `2.253982`, interpreter `2.389662`
versus `2.394806`, and 64 SPU functions `2.820287` versus `2.794049`.

PID `29808` was established at `18:57:38.2202918`. Silicon reached `61.0 C`
at `18:57:40.9124255`; the immediate confirmation was `61.8 C` about
`0.615 s` later. The next normal poll reached `68.2 C` at
`18:57:44.3031403`, about `6.083 s` after PID, so the harness force-stopped
at the early threshold below the `72 C` hard limit. The prior matched route
stopped about `3.267 s` after PID, so removing the unchanged 256-create cache
rewrite broadened this startup thermal window by about `2.82 s`. That is
startup-window evidence only; thermal variance prevents treating it as an FPS
or general speed result. The stop occurred during the initial 12-second wait,
before Start, title polling, or screenshots. Failure-post-stop silicon was
`51.4 C`, PID was absent, and the targeted fatal/access-violation/device-lost/
unknown-draw scan had zero matches. The one `Channel Loop Pattern Detected`
row is an SPU compiler diagnostic, not a native fatal.

Classification: `failed-thermal-guard`, with the parallel-worker and warm
checkpoint-deferral activation proven. Grant startup thermal-window credit
only; grant no title, FPS, flicker, gameplay, or stability credit. Do not retry
or query the device again in this round.

The captured `failure-RPCSX.log` was still `145,215` bytes / `1,401` lines.
The emulated 3-5 second interval alone contained `278` timed rows / `42,156`
bytes. Repeated compiler-only diagnostics included 16 RdDec notices, 32
`mpy32` rows, 78 nonzero-constant `MFC_EAH` rows, 23 GETLLAR rows, 17 PUTLLC
break rows plus 17 formatted summaries, and the channel-pattern row. These
messages do not change emitted code or compiler analysis.

The host successor now avoids that work on Android when `SPU Debug=false`:
it skips the full per-function RdDec diagnostic scan; suppresses the MFC_EAH,
nonconstant MFC command, and `mpy32` messages; and avoids formatting/sorting
PUTLLC/channel break diagnostics and channel-loop messages. Pattern analysis,
statistics, IR generation, cache identity, and runtime behavior are unchanged.
Desktop and Android `SPU Debug=true` retain full diagnostics. GETLLAR logging
is deliberately unchanged.

Recompiling the older fork also exposed a pre-existing signed/unsigned
`narrow<s8>` failure in legacy x64 displacement emission. The companion
compatibility fix converts the known-small offsets to signed 32-bit before the
checked byte narrow, consistent with current upstream intent and without
changing emitted offsets. Both affected ARM64 native objects compile, and the
optimized native link plus ARM64-only ThorTest assembly pass.

Host validation:

- SPU, RSX, Vulkan-cache, optimized-variant, ARM64 APK, export-surface,
  single-core-load, thermal, and visual-route contracts: pass;
- PowerShell AST parsing and `git diff --check`: pass;
- export surface: 34 defined dynamic symbols, 583 explicit relocations, 391
  jump slots, and 44,219 encoded relocation bytes;
- merged core: `1,305,550,384` bytes, SHA-256
  `2C2691F02E11F2A0E98A3CAF5BEF6F37718510886C38E6CFC85F58AF647DC71E`;
- stripped core: `62,842,632` bytes, SHA-256
  `0834EF20267B6CF34F0CE064156D10B8B59503910BF9A0789A1A6C584FD3BDB7`;
  and
- ARM64-only ThorTest APK: `73,573,042` bytes, SHA-256
  `D6204DA24E8BDE90270382C38283AD9A07E41111BCA8FF966D524C52AB372747`.

The diagnostic-pruned APK is `host-verified`, `device-unmeasured`, and was
not installed or launched. A later separately cool round may perform only its
strict no-launch install; any guarded runtime proof belongs to a different
independently cool round.

## Android PPU verbose-success logging successor

The deterministic refiner was run with `-MaxRuns 8 -NoWrite` so the two
unrelated untracked refiner files remained untouched. It confirmed the clean
current-upstream Windows field/first-battle plus Options gate is complete and
that no CPU4 rerun is warranted. Its next runtime action is a thermally gated
Thor proof, which is deferred because this continuation is not a separately
cool device round. No ADB query, install, launch, or device mutation ran.

Saved evidence from
`20260717-185725-thor-input-parallel-rsx-warm-checkpoint-bounded-title-proof`
shows `PPU Debug: false`, yet normal successful loader/discovery diagnostics
still produced 135 unique rows / 18,521 characters including CRLF:

- 35 `Found valid roaming SPU code` rows;
- 23 ELF segment rows;
- 31 ELF section rows;
- 10 normal PRX `Loaded to` rows; and
- 36 special management-export rows.

Those rows represent about 12.8% of the `145,215`-byte captured startup log.
They also perform symbol-name lookup and message formatting inside active PPU
load/SPU-discovery loops, but they do not affect guest memory, hashing,
segment/section processing, export registration, SPU discovery, or emitted
code.

The host successor gates exactly those ten verbose-success log sites on
Android behind `PPU Debug`. Android `PPU Debug=false` now skips their symbol
lookup, formatting, and log I/O while all loader/discovery work still runs.
Desktop and Android `PPU Debug=true` retain the full diagnostics. Exported and
imported module summaries, executable/PRX/SPU hashes, invalid-function errors,
illegal-descriptor warnings, allocation errors, and all other loader failures
remain visible. The strengthened PPU loader contract requires all ten gates
and each expected message family, preventing a partial regression.

Host validation:

- the changed `PPUModule.cpp` ARM64 object compiles successfully;
- optimized ARM64 native link: `BUILD SUCCESSFUL in 42s`;
- ARM64-only ThorTest assembly: `BUILD SUCCESSFUL in 12s`;
- PPU-loader, SPU, RSX, Vulkan-cache, optimized-variant, ARM64 APK,
  export-surface, single-core-load, thermal, and visual-route contracts: pass;
- PowerShell AST parsing and `git diff --check`: pass;
- export surface remains 34 defined dynamic symbols, 583 explicit
  relocations, 391 jump slots, and 44,219 encoded relocation bytes;
- merged core: `1,305,555,520` bytes, SHA-256
  `47791529B906E96FCBEDE80F5075CD1B196F2D743CD7F456E861FA5C050D4BE6`;
- stripped core: `62,843,048` bytes, SHA-256
  `49A2AD0EF8882210CA38C7558AA4B2AB22873941A1957BD6281680D4EB0AD66E`;
  and
- ARM64-only ThorTest APK: `73,572,978` bytes, SHA-256
  `3798B97506BF5C2DCD6B1EE5DFF137EF3BCE993C86D3756A409AFAB219315AA1`.

This exact APK supersedes the host-only `D6204DA2...2747` candidate before
either was installed. Classification is `host-verified logging-pressure
candidate`, `device-unmeasured`, not a speed or stability result. A later
separately cool round may perform only the strict no-launch install of
`3798B975...5AA1`; one different independently cool round is required for a
bounded guarded runtime proof.

## PPU/SPU log-pruned install-only gate rejected on thermal trend

The deterministic refiner was rerun with `-MaxRuns 8 -NoWrite`; it again
reported that the clean current-upstream Windows field/first-battle plus
Options gate is complete and that no CPU4 rerun is warranted. Repository
`HEAD` matched `origin/master`, and the exact ThorTest candidate remained
`73,572,978` bytes with SHA-256
`3798B97506BF5C2DCD6B1EE5DFF137EF3BCE993C86D3756A409AFAB219315AA1`.

The separate install-only cool gate is captured at
`debug-captures/android-speed-sprint/20260717-200043-thor-input-ppu-spu-log-pruned-thortest-install-cool-gate`.
It used `BootGame=False`, `ForceStop=True`, three samples at two-second
intervals, a strict sub-`35 C` silicon ceiling, and a maximum `+1 C` rise.
Battery and skin held at `23.0 / 30.0 C`; silicon measured
`31.9 -> 32.5 -> 33.1 C`. Although every sample stayed below the absolute
ceiling, the net `+1.2 C` rise exceeded the trend limit, so the harness failed
closed before the `stop` macro and force-stopped RPCSX. Failure-post-stop
silicon was `33.1 C`, and `failure-pid.txt` records `pidof net.rpcsx.easy`
exit `1` (PID absent).

No APK install, emulator launch, gameplay route, follow-up ADB query, or retry
ran after the failure. The previously installed exact APK
`24F3F267...F87F` therefore remains unchanged; candidate
`3798B975...5AA1` remains `host-verified`, `device-unmeasured`, and uninstalled.
Classification: `install-deferred-thermal-trend`, with no speed, title, FPS,
flicker, gameplay, or stability credit. Only a later independently cool round
may repeat this strict install-only gate.

## Latest lower-temperature research and SPU KnownFPClass successor

A primary-source review was completed host-side without another Thor query,
install, launch, or retry. The useful direction is to reduce work per emulated
frame and specialize only proven phases, rather than force a blanket CPU mask:

- Phase Matters (June 2026) reports up to a `10.47 C` steady-state reduction
  and `2.52x` lower energy from phase-specific heterogeneous placement on a
  Snapdragon 8 Elite mobile vision-language workload
  (<https://arxiv.org/abs/2606.27906>). This is supporting evidence for
  phase-aware policy only, not an emulator temperature forecast.
- System-Level Dynamic Binary Translation Using Automatically-Learned
  Translation Rules reports a `1.36x` SPEC CINT2006 mean over QEMU 6.1 and
  `1.15x` on real applications by removing coordination overhead and improving
  generated-code scheduling (<https://arxiv.org/abs/2402.09688>).
- Partial Cross-Compilation and Mixed Execution reports up to `13x` over DBT
  by selectively replacing functions with native execution
  (<https://arxiv.org/abs/2512.00487>). For RPCSX this supports a long-term,
  correctness-gated title/HLE superpath lane; it does not justify a broad
  shortcut or claim that those gains transfer to PS3 emulation.
- Android's Performance Hint API is available on Android 12+, but its
  power-efficiency preference is API 35; Thor's Android 13 cannot request that
  mode. A basic session whose actual work duration exceeds its target can ask
  the system for more performance and therefore is not yet a safe cooling
  control without measured per-cycle deadlines. Android also recommends
  thermal headroom polling no more frequently than every ten seconds
  (<https://source.android.com/docs/core/perf/performance-hint-api>,
  <https://developer.android.com/games/optimize/adpf/thermal>,
  <https://developer.android.com/reference/android/os/PerformanceHintManager.Session.html>).

Existing Thor evidence remains decisive for scheduling: the unrestricted
`0xFF` process mask beat `0xF8` by about `19%` in the matched static field,
OldNeutral/AltNeutral collapsed near `2.2 FPS`, and prime-only RSX isolation
regressed. Keep OS scheduling as the baseline; do not infer a thermal fix from
fewer runnable cores.

Fresh official RPCS3 `origin/master` was audited at `1d657c4`. The relevant
upstream SPU LLVM cluster is `aec0917a86044449cae6b5c5e08fa0fbb83bd2f2`,
`d0fdd9bb6d096eca0c88eb98583d2fc728c67979`, and
`fa418f0dbb76ce60a9bf4eef741405564836f010`. Their LLVM
`KnownFPClass` analysis was adapted to this older fork: clamp, FM, FCEQ,
FCMEQ, FMA, FNMS, and FMS paths can now prove that NaN, infinity, zero, or
subnormal handling is unnecessary and avoid emitting redundant masks,
comparisons, clamps, or multiply/add work. A dedicated contract requires the
helper, all analysis families, KnownFPClass propagation through FMA variants,
and removal of the legacy constant-only zero classifier.

The ARM64 native build completed incrementally, and the ARM64-only ThorTest
assembly completed in `56 s`. All eleven host contracts pass: PPU loader, SPU
cache, SPU KnownFPClass, RSX cache, Vulkan cache, optimized variant, ARM64 APK,
export surface, single-core load, thermal, and visual route. PowerShell AST
parsing and `git diff --check` also pass. Export surface remains 34 defined
dynamic symbols, 583 explicit relocations, 391 jump slots, and 44,219 encoded
relocation bytes.

Exact host artifacts:

- merged core: `1,305,591,152` bytes, SHA-256
  `287CF4832EA4ABBE15611B477080A31399B0EB7B1055C889D70556BE3A8FDC85`;
- stripped core: `62,843,448` bytes, SHA-256
  `59960428AAB41201C388444CE5A1E80944A6738FA98C87C9FF89D2F561E8E891`;
  and
- ARM64-only ThorTest APK: `73,573,278` bytes, SHA-256
  `8DAFBB2F05D9FB249A06645B5E6774A7E266B7142F59D8F811644E0B81B9A1DF`.

The exact `8DAFBB2F...A1DF` APK supersedes uninstalled host candidate
`3798B975...5AA1`, but is still `host-verified`, `device-unmeasured`, and
uninstalled. The device remains on exact APK `24F3F267...F87F`. Grant no FPS,
temperature, flicker, gameplay, or stability credit. Only a later independently
cool round may spend the strict install-only gate; a guarded runtime proof must
remain a different independently cool round.
