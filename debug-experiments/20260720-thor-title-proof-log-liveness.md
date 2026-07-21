# Thor title reach and runtime-log liveness

- Date: 2026-07-20
- Title: Eternal Sonata `BLUS30161`
- Device: AYN Thor Max `c3ca0370`
- Runtime capture:
  `debug-captures/android-speed-sprint/20260720-104152-thor-input-custom`
- Runtime classification: `title-proof-log-incomplete` / `not-comparable`
- Exact installed APK: `24FCC44E...736FE2`
- Device routes this round: one

## One exact, guarded route

The first command used unsupported host selector `-Scene title` and was
rejected by PowerShell parameter binding before any ADB/device access. The one
real route used `-Scene field` only to satisfy the wrapper's selector; the
hard-pinned `ThorCoolTitle` macro remained exactly:

```text
gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop
```

Before thermal preflight or boot, the route proved:

- package `net.rpcsx.easy`;
- exactly one installed `/base.apk`;
- expected and actual installed APK SHA-256 both
  `24FCC44EAF76C956EFFB8AA1F7B768D3181F917DAC632CBB5A7E3D707C736FE2`;
  and
- `match=True`.

The strict three-sample preflight passed:

- silicon `32.3 -> 31.9 -> 31.9 C`, maximum `32.3 C` against `35 C`;
- rise `-0.4 C` against the `+1 C` maximum;
- battery `22.0 C` against `34 C`; and
- skin `30.0 C` against `40 C`.

PID `13727` was established once. The bounded PPU/title gate recorded:

- first screenshot at `1.412 s`: no title;
- first title candidate at `19.295 s`, magenta classification `11.4%`;
- required second stable title candidate at `24.710 s`; and
- final title proof SHA-256
  `F0D03AC65C872CF22D97AAA8B00935E58FF38488A8D94814690D799D6E6C5B73`.

The macro executed its exact five tokens and `stop` force-stopped the package.
The saved post-proof PID probe is empty with `exit=1`.

## Thermal evidence

No thermal guard row failed. Selected silicon samples were:

- `41.3 C` at the first screenshot;
- `48.2 C` at the first title candidate, the run maximum;
- `44.9 C` at the stable-title sample;
- `45.8 C` at the final title proof; and
- `40.9 C` post-stop.

The two preceding installed-candidate routes stopped before title at
`71.1 C` and `72.7 C`. Reaching and stabilizing the title at a `48.2 C`
maximum is a large practical startup/thermal-progress signal. It is not yet a
controlled thermal win: this APK includes several stacked changes, and the
runtime activation evidence needed to attribute them was not durable.

## Fail-closed evidence result

The title image, title gate, exact APK, properties, thermal record, token
sequence, and self-stop evidence all passed. However, both live guest-health
and post-stop pulls of `RPCSX.log` were only `2,671` bytes and ended at
emulator timestamp `0.010546 s`, while the game visibly continued to title.
All 11 required native activation rows were therefore absent:

- RSX preload limit, `500 ms` load budget, and deferred fallback;
- two RSX workers and exact `0x07` load affinity;
- SPU preload limit, two-worker pool, `100 ms` compile budget, and exact
  `0x07` affinity;
- Vulkan warm hit-only activation; and
- managed `Set DAZ and FTZ: true`.

The saved log contains zero targeted fatal strings, but its truncation means
full fatal cleanliness is also unproven. The analyzer correctly grants no
comparison or speed credit and now classifies this exact shape as
`title-proof-log-incomplete`, rather than generic `activation-incomplete`.

## Host-only log durability repair

The Android Log Writer had replaced the original 10 ms idle poll with an
unbounded atomic wait plus producer notification. The captured file proves
that a small final batch can remain memory-only until Android force-stop if
the event path does not provide liveness; previous noisy runs generated enough
output to persist later timestamps and did not expose this shape.

Notification remains the normal zero-delay path. Android now applies a
one-second timeout to the already-armed atomic wait:

- a normal producer commit still wakes immediately;
- the arm/recheck protocol and shutdown wake are unchanged;
- a missed or ineffective notification delays persistence by at most one
  second;
- Android idle wakeups remain bounded at `<=1/s`, versus roughly `100/s` in
  the old 10 ms polling implementation; and
- desktop retains its original 10 ms path exactly.

The analyzer also records the latest emulator timestamp in captured guest
logs and fail-closed diagnoses a stable title plus missing activation rows and
a sub-one-second log as incomplete evidence.

## Host verification and exact successor

Host-only verification passed:

- focused event-writer and cool-title analyzer contracts;
- replay of this capture as `title-proof-log-incomplete`, with title, exact
  APK, self-stop, `48.2 C` maximum, and `0.010546 s` latest log retained;
- all `59/59` `tools/test_thor_*.ps1` contracts;
- optimized ARM64 native build in `96.4 s`;
- ARM64-only optimized ThorTest assembly in `98.3 s`;
- 34-symbol export surface, relocation bounds, optimized test-hook contract,
  ABI contents, merged-core identity, and APK-entry identity; and
- no remaining Gradle, Java, Ninja, Clang, CMake, or emulator build process.

Exact uninstalled ARM64-only successor:

- APK: `72,839,336` bytes,
  `E69ABCB05E2028C32197D4358E94F0EA8AF2E42366F75D8335AE40BB7A208073`;
- merged core: `1,304,689,776` bytes,
  `857B0A5A4E9F7BC5E8337A07137D446166022E6C9DBB695EC298FDFF9100877E`;
- stripped core/APK entry: `63,015,752` bytes,
  `CC2FF22E6D190B97E58E1466E139FB4DAC711F988A91FFF2C01D13B1CB5EA3CA`.

Relative to installed candidate `24FCC44E...736FE2`, the APK is `+20` bytes,
the merged core is `+64` bytes, and the stripped-core length is unchanged.
This successor is not installed and receives no device credit.

No second device query, launch, or retry ran. After a later independently cool
interval, spend one round only on strict no-launch installation of exact APK
`E69ABCB0...8073`, proving matching on-device hash and absent PID. Reserve a
different cool round for one self-stopping `ThorCoolTitle` proof. Until that
proof captures all activation/fatal evidence, grant no sustained FPS,
temperature-win, flicker, field, battle, menu, gameplay, or stability credit.

## Exact no-launch successor installation

A later independently cool install-only round used strict gate capture
`debug-captures/android-speed-sprint/20260720-113643-thor-input-strict-cool-gate`.
Its three silicon samples were `32.7`, `32.3`, and `32.7 C`, for a `32.7 C`
maximum and `0.0 C` rise. The gate did not boot the emulator.

Install capture
`debug-captures/android-speed-sprint/20260720-113655-log-liveness-thortest-apk-install`
then proved:

- status `installed-exact-no-launch`;
- host and installed `base.apk` SHA-256 both
  `E69ABCB05E2028C32197D4358E94F0EA8AF2E42366F75D8335AE40BB7A208073`;
- PID absent before and after installation;
- no emulator launch and no install failure; and
- post-install battery `23.0 C`, skin `30.0 C`, and silicon `34.7 C`.

This banks exact identity only. It grants no runtime, title, FPS, flicker,
gameplay, stability, or temperature-win credit. The device round stopped after
installation. In a separate independently cool round, the next permitted
device action is one self-stopping `ThorCoolTitle` proof of this exact installed
candidate, with durable activation/fatal-log evidence required for comparison.

## Exact successor runtime counterproof

A separate cool round ran the one permitted self-stopping title route against
exact installed APK `E69ABCB0...8073`. Capture
`debug-captures/android-speed-sprint/20260720-114321-thor-input-custom` proved:

- installed and expected APK SHA-256 matched exactly;
- preflight silicon was `32.7 -> 33.1 -> 33.1 C`, with a `33.1 C` maximum
  and `+0.4 C` rise;
- the first title candidate appeared at `18.517 s` and the stable candidate at
  `24.044 s`;
- final title proof SHA-256 was
  `2BF2FDAA155E1ABF207ED4334A469EC4654E6FEBDC5FA74574A27E4ABCFAAEFD`;
- maximum silicon was `48.2 C`, final proof silicon was `46.6 C`, and the
  post-stop sample was `40.1 C`;
- the exact macro reached `stop`, and the saved post-proof PID was absent; and
- there were no property mismatches, thermal failures, or targeted fatal hits
  in the available log prefix.

The result remains `title-proof-log-incomplete` / `not-comparable`. The full
post-stop log was again only `2,671` bytes, now ending at emulator timestamp
`0.009551 s`; all 11 required activation rows were absent. This directly
disproves the one-second background-wait timeout as a sufficient durability
repair. The evidence is consistent with the low-priority writer failing to
run during the startup compilation burst, but the capture proves only that
notification plus timeout was insufficient, not the scheduler mechanism by
itself. Grant no speed, FPS, thermal-win, flicker, gameplay, or stability
credit from this route. No second device action ran.

## Deterministic pre-pull log synchronization

The next host-only repair no longer asks the evidence path to infer writer
liveness from elapsed time:

- a Thor debug-only broadcast invokes a new optional JNI/core `syncLogs` API;
- the core calls `logs::listener::sync_all()`;
- Android explicit sync wakes the event-driven file writer before waiting for
  the ring buffer to drain, then performs the existing file sync;
- `Assert-ThorGuestHealthy` performs this synchronous request before reading
  `RPCSX.log`; and
- the route force-stops and fails closed unless the ordered broadcast reports
  native synchronization success.

Normal gameplay adds no polling, timer, elevated writer priority, or producer
flush. The hook exists only in the Thor debug harness and runs at an explicit
evidence boundary.

Host verification passed:

- focused event-writer, debug-sync, cool-title, plain-log, single-open, export,
  optimized-test-hook, and ARM64 APK contracts;
- optimized ARM64-only ThorTest assembly in `124 s`;
- `35` exact `_rpcsx_*` exports, `587` explicit relocations, `390` jump slots,
  and `44,134` encoded relocation bytes; and
- exact successor APK `691EE8A7...F5E2D3`, `72,841,008` bytes, merged core
  `1DA06245...947409`, `1,304,691,520` bytes, and packaged core
  `B42CB1EA...9C78B6`, `63,015,960` bytes.

This successor is host-only and uninstalled. It receives no device credit.
The next separately cool round is installation only: prove exact on-device APK
SHA-256 and absent PID without launching. Reserve a different later cool round
for one self-stopping title/log proof.

## Deterministic-sync install thermal refusal

The next independently gated install-only round stopped safely before install.
Strict-gate capture
`debug-captures/android-speed-sprint/20260720-120535-thor-input-strict-cool-gate`
measured `40.5 C` silicon at `pre-run-1-of-3`, above the `35 C` launch
limit. Battery was `23.0 C` and skin was `30.0 C`. The harness force-stopped
RPCSX, saved an absent PID, and refused the remaining two preflight samples and
the install. Its post-stop evidence measured `41.3 C` silicon, `23.0 C`
battery, and `30.0 C` skin.

No APK was installed, no emulator was launched, and no retry or second device
query ran. Exact candidate `691EE8A7...F5E2D3` remains host-only and receives
no device, speed, FPS, thermal-win, flicker, gameplay, or stability credit.
After a later independently cool interval, retry only the strict no-launch
installation; reserve runtime proof for another separate cool round.

## Host artifact identity and upstream audit

Host-only follow-up added
`tools/test_thor_cool_title_candidate_artifact.ps1`. It validates the pinned
candidate data file and fails closed unless all four identities agree:

- APK `691EE8A7...F5E2D3`, `72,841,008` bytes;
- merged core `1DA06245...947409`, `1,304,691,520` bytes;
- stripped core `B42CB1EA...9C78B6`, `63,015,960` bytes; and
- the APK's single ARM64 core entry with the same stripped length/hash.

All `61/61` `test_thor_*.ps1` contracts pass, including the exact artifact,
cool-title profile, deterministic sync, no-launch installer, thermal, visual,
ABI, export, and optimized-variant gates. The candidate APK/core bytes and
pinned SHA-256 values are unchanged.

A fresh official RPCS3 fetch advanced `origin/master` through `ee37ef277`;
the only new change after the prior audit is macOS/MoltenVK-specific. No new
Android/ARM64 performance slice is available to stack before this candidate is
measured. No build, APK install, emulator launch, ADB query, or Thor access ran
in this host round. Exact candidate `691EE8A7...F5E2D3` remains uninstalled.

## Exact deterministic-sync installation

A later independently cool install-only round passed strict gate capture
`debug-captures/android-speed-sprint/20260720-122048-thor-input-strict-cool-gate`.
Its silicon samples were `33.5`, `34.3`, and `33.9 C`, for a `34.3 C` maximum
and `+0.4 C` rise. Battery and skin stayed at `23.0` and `30.0 C`.
`BootGame` was false and RPCSX was force-stopped.

Install capture
`debug-captures/android-speed-sprint/20260720-122101-deterministic-log-sync-thortest-apk-install`
proved:

- status `installed-exact-no-launch`;
- expected, host, and installed `base.apk` SHA-256 all exactly
  `691EE8A725A0B545BF98BDEA03998CD4CDA7D34ABB48A6FF650D0F01F4F5E2D3`;
- APK size `72,841,008` bytes;
- PID absent before and after installation;
- no emulator launch and no installation failure; and
- post-install battery `23.0 C`, skin `30.0 C`, and silicon `35.1 C`.

This banks exact identity only. It grants no runtime, speed, FPS, thermal-win,
flicker, gameplay, or stability credit. No retry or second device query ran.
The next permitted device action, after a separately cool interval, is one
self-stopping `ThorCoolTitle` proof of exact installed `691EE8A7...F5E2D3`,
requiring synchronized success plus complete activation/fatal-log evidence.

### 2026-07-20 - deterministic-sync-title-preflight-refusal

- Status: failed
- Scope: scene-route
- Hypothesis: exact installed `691EE8A7...F5E2D3` was cool and stable enough
  for one self-stopping title/log proof.
- Changed files/settings: none; the hard-pinned `ThorCoolTitle` profile was
  used unchanged.
- Rollback: not applicable; RPCSX was force-stopped before boot.
- Windows result: not applicable.
- Thor result: the exact installed APK hash matched, but the three preflight
  silicon samples were `32.7`, `32.7`, and `33.9 C`. The `+1.2 C` rise
  exceeded the strict `+1.0 C` limit even though the `33.9 C` maximum remained
  below the `35 C` launch ceiling. Battery and skin stayed at `23.0` and
  `30.0 C`; the saved post-stop PID was absent.
- Visual correctness: not reached; the emulator and game did not boot.
- FPS/frame-time: none.
- Capture paths:
  `debug-captures/android-speed-sprint/20260720-122921-thor-input-custom`.
- Decision: `preflight-refused-rise` / `not-comparable`. Grant no speed, FPS,
  thermal-win, title, flicker, gameplay, or stability credit. No retry or
  second device query ran.
- Next: after a separately cool interval, retry only one exact installed
  `ThorCoolTitle` proof with the same safety limits.

### 2026-07-20 - frame-poll-log-clock-throttle

- Status: proposed
- Scope: windows-android-ab
- Hypothesis: retain the active frame-poll optimization and its required first
  activation row while removing routine monotonic-clock reads from its
  diagnostic throttle on Android.
- Changed files/settings:
  `app/src/main/cpp/rpcsx/kernel/cellos/src/sys_timer.cpp` now admits the first
  log probe and one probe per `1,024` calls before applying the unchanged
  five-second wall-time throttle;
  `tools/test_thor_es_frame_poll_wait.ps1` locks the ordering and reduction.
- Rollback: remove `thor_es_frame_poll_log_probe_mask` and the early call-count
  predicate; wait semantics and configuration are otherwise untouched.
- Windows result: saved matched title log
  `debug-captures/windows-lab/20260719-014837-es-frame-poll-wait1ms-title/RPCS3.log`
  contains a `93,786`-call delta over `47.022 s`, or `1,994.5 calls/s`. The
  representative outlined-logger and clock-probe counts both fall from
  `93,786` to `92`, over `99.9%`.
- Thor result: none; this source successor is not in the installed APK.
- Visual correctness: unchanged by construction; the edit touches diagnostics
  after the exact title/thread/CIA/object gate, not guest wait behavior.
- FPS/frame-time: no device or FPS claim.
- Capture paths: the saved Windows log above; ARM64 temporary object
  `rpcsx-thor-frame-log-throttle-sys_timer.o` is ignored build evidence only.
- Decision: host-verified `stackable-cpu-pressure`, not a measured speed win.
  Direct optimized ARM64 compilation passed with only existing deprecation
  warnings. Object size is `1,698,616` bytes, SHA-256
  `2752E4CDA79D73CD455EE034C7BE1E5AE8ED5C66E788123BA69E5969F39EF10A`.
  ARM64 disassembly places the `#0x3ff` call-site branch before the outlined
  logger and therefore before `get_system_time()`. All `61/61` Thor host
  contracts pass.
- Next: keep exact installed `691EE8A7...F5E2D3` frozen for its separately
  cool deterministic-log proof. Only after that result should this successor
  be assembled, pinned, and considered for a later install/proof round.

### 2026-07-20 - durable-log-checkpoint-successor

- Status: windows-pass
- Scope: scene-route
- Hypothesis: an explicit evidence sync must return a unique native checkpoint,
  drain committed log data without relying on background-writer scheduling,
  and prove that exact checkpoint exists after the pull.
- Changed files/settings: Android `file_writer::sync()` may drain committed
  batches on its caller under the existing writer mutex; `_rpcsx_syncLogs`
  emits and returns a monotonic checkpoint; JNI/Kotlin/broadcast plumbing
  carries that sequence; the Thor macro requires the exact pulled marker;
  focused contracts lock the path. The frame-poll clock-throttle successor is
  included in the assembled candidate.
- Rollback: revert the checkpoint return plumbing and Android caller-side
  drain; restore the previous Boolean broadcast result. Normal producer and
  background-writer behavior is otherwise unchanged.
- Windows result: direct ARM64 compilation passed for `native-lib.cpp`,
  `rpcsx-android.cpp`, and `logs.cpp`. The latter two object identities were
  `852373AB...B79FB` / `15,268,448` bytes and
  `162C9E9D...ECFCD` / `2,394,960` bytes; the JNI wrapper was
  `5A51346D...001B` / `377,136` bytes. The optimized ARM64-only ThorTest build
  passed in `622.4 s`.
- Thor result: predecessor capture
  `debug-captures/android-speed-sprint/20260720-125534-thor-input-custom`
  reached first/stable title candidates in `19.745/25.482 s`, peaked at
  `49.0 C`, self-stopped, and saved an absent PID. Its broadcast returned
  `result=-1, data="synced"`, but the pulled log remained `2,671` bytes and
  ended at `0.009870 s`. That is the direct counterproof this successor fixes.
  The successor is not installed or device-measured.
- Visual correctness: predecessor stable-title screenshot passed; successor
  is unmeasured on device.
- FPS/frame-time: none; no verified in-game speed claim.
- Capture paths:
  `debug-captures/android-speed-sprint/20260720-125534-thor-input-custom`;
  built artifacts remain ignored under `app/build/`.
- Decision: predecessor is `title-proof-log-incomplete` / `not-comparable`.
  Successor is host-verified `route-tooling` plus the existing
  `stackable-cpu-pressure` clock-probe reduction. Exact pinned artifacts are:
  APK `71CFA42A0F88AC378B8AB98F8198D067814B45D7F0DC974426D16049425BD12B`
  / `72,841,908` bytes; merged core
  `9F58A31660FBDC8F05BE9F98714562F1CBF305EB4E791943741F5B3292D2E43D`
  / `1,304,693,416` bytes; stripped core and APK entry
  `576C5108E8BA9B9DE2F31AE7F4A69910433FE79477ADC5AC477E9A4282F3D5F1`
  / `63,015,912` bytes. Artifact identity, ARM64 ABI, optimized variant,
  checkpoint durability, event writer, the 35-export surface, and all `61/61`
  Thor host contracts pass. No ADB query, install, launch, or Thor contact ran
  in this host repair/build.
- Next: after a separately cool interval, perform only a strict no-launch
  installation of exact APK `71CFA42A...5BD12B`, proving installed hash and
  absent PID. Reserve one later cool round for the self-stopping title/log
  proof; credit FPS or temperature only if the exact checkpoint and all
  activation/correctness evidence are durable.

### 2026-07-20 - durable-checkpoint-install-only

- Status: android-pass
- Scope: config-driver
- Hypothesis: exact successor `71CFA42A...5BD12B` can replace the predecessor
  without launching RPCSX and while staying inside the strict cool boundary.
- Changed files/settings: installed the exact pinned ThorTest APK with
  `adb install -r`; no emulator setting or runtime property was changed.
- Rollback: reinstall a previously pinned exact APK through the same strict
  no-launch workflow; no rollback is currently needed.
- Windows result: host artifact contract already proved APK, merged core,
  stripped core, and APK-entry identity.
- Thor result: strict no-boot gate `20260720-134017-thor-input-strict-cool-gate`
  passed silicon samples `33.5`, `33.9`, and `33.9 C`, maximum `33.9 C`, rise
  `+0.4 C`; battery/skin stayed `24.0/30.0 C`. Install capture
  `20260720-134030-durable-log-checkpoint-thortest-apk-install` reports
  `installed-exact-no-launch`; expected, host, and installed SHA-256 are all
  `71CFA42A0F88AC378B8AB98F8198D067814B45D7F0DC974426D16049425BD12B`.
  PID was absent before and after; post-install battery/skin/silicon were
  `24.0/30.0/35.7 C`.
- Visual correctness: not exercised; no activity or game launched.
- FPS/frame-time: none.
- Capture paths:
  `debug-captures/android-speed-sprint/20260720-134017-thor-input-strict-cool-gate`;
  `debug-captures/android-speed-sprint/20260720-134030-durable-log-checkpoint-thortest-apk-install`.
- Decision: `installed-exact-no-launch` / `route-tooling`. Installation banks
  device identity only and grants no speed, FPS, thermal-win, flicker,
  gameplay, or stability credit. Stop this device round; do not query, retry,
  or launch.
- Next: after a separate independently cool interval, run exactly one
  self-stopping `ThorCoolTitle` proof. Require the exact durable sync
  checkpoint plus activation, fatal-log, stable-title, PID-stop, visual, and
  thermal evidence before any comparison or performance credit.

### 2026-07-20 - durable-checkpoint-title-activation-gap

- Status: failed
- Scope: scene-route
- Hypothesis: exact installed checkpoint successor `71CFA42A...5BD12B`
  would produce a comparison-ready, self-stopping `ThorCoolTitle` proof.
- Changed files/settings: none on device; the hard-pinned title profile set
  RSX workers/preload/load budget to `2/256/500 ms`, SPU preload/compile
  budget to `64/100 ms`, cache-worker affinity to `0x7`, Vulkan driver cache
  and hit-only preload on, ADPF and phase pacing off, and Quiet logging.
- Rollback: the route reset all experiment properties, force-stopped RPCSX,
  and saved an absent post-run PID.
- Windows result: not applicable.
- Thor result: strict preflight passed `33.9 -> 34.7 -> 34.3 C`, maximum
  `34.7 C` and net rise `+0.4 C`. First/stable title candidates appeared at
  `18.620/24.361 s`. Silicon peaked at `48.6 C` and post-run was `40.9 C`;
  battery/skin stayed `24.0/30.0 C`. PID was absent after the controlled stop.
- Visual correctness: the deterministic title gate accepted two consecutive
  title frames and the final screenshot with `title_menu_present=True`,
  `title_magenta_percent=11.4`, `dark_percent=0.104`, and no compilation or
  black frame. `04-title-proof.png` is `1,201,546` bytes with SHA-256
  `B8ED43E4CFC4E1001DE25D923E1F3F31C9304ECAE7E6698ECB7BF1579E5D672F`.
- Log correctness: the ordered broadcast returned `checkpoint:1` and the
  pulled log contains exact native row `Thor debug log sync checkpoint: 1` at
  emulated `26.076926 s`. This dynamically proves the caller-side batch drain
  and checkpoint durability repair. The file contained no targeted fatal hit,
  but all 11 required optimization-activation rows were absent because the
  Quiet/configured channel levels filtered their Notice severity.
- FPS/frame-time: none; title timing is not comparison-valid without complete
  activation and safety evidence.
- Capture path:
  `debug-captures/android-speed-sprint/20260720-134641-thor-input-custom`.
- Decision: `activation-incomplete` / `not-comparable`. Grant no speed, FPS,
  thermal-win, flicker, gameplay, or stability credit. Do not retry or perform
  another device action in this thermal round.
- Next: make only the bounded Android activation/fallback facts survive Quiet
  logging and preserve fatal/error file evidence, then build and pin a
  host-verified successor for a later cool install-only round.

### 2026-07-20 - bounded-android-evidence-successor

- Status: windows-pass
- Scope: scene-route
- Hypothesis: preserve Quiet logging performance while making the next title
  proof self-describing and fail-closed.
- Changed files/settings:
  Android emits the 11 required RSX/SPU/Vulkan/managed-FTZ activation rows at
  Always, plus the affinity, Vulkan, and phase-pacing fallback facts. Desktop
  keeps Notice behavior for shared rows. Android fatal/error messages bypass
  configured channel silence, while the independent property-driven logcat
  filter remains unchanged. `tools/test_thor_android_evidence_logging.ps1`
  locks these constraints, and the exact candidate pin now names the rebuilt
  artifact.
- Rollback: restore the affected activation/fallback calls to Notice/Warning,
  remove the Android critical-severity bypass and managed FTZ fact, and repin
  the predecessor. Emulation, cache, scheduling, rendering, and property
  behavior are otherwise unchanged.
- Windows result: focused contracts passed `11/11`; the complete Thor host
  suite passed `62/62`. Optimized ARM64 native build passed in `407.9 s` and
  the ARM64-only ThorTest APK passed in `78.2 s`. Artifact identity, packaged
  core identity, optimized variant, ABI, and export checks pass. The merged
  core has `35` defined dynamic symbols, `587` explicit relocations,
  `390` `JUMP_SLOT` entries, and `44,134` encoded relocation bytes. The
  stripped/package core contains all `11/11` required activation strings.
- Thor result: none. No ADB query, installation, launch, or device read ran
  after the failed title proof. Exact predecessor `71CFA42A...5BD12B` remains
  installed and stopped; the successor is device-unmeasured.
- Visual correctness: unchanged by construction; this edit changes only
  bounded diagnostic visibility.
- FPS/frame-time: none. The included frame-poll clock-probe reduction remains
  host-proven stackable CPU-pressure work, not measured Thor speed.
- Exact pinned artifacts:
  APK `59D5658EC31130F2CD8FD8F4E02700DFF3BD1AF52B7E89F25CF167EF5C91BD02` /
  `72,828,856` bytes; merged core
  `CB06FE9C5DDAA1F009217C3886295C4283810A95F4262BC4AA5B369363C5BBF2` /
  `1,304,043,704` bytes; stripped/package core
  `5F7938BB5A0A29DB67FA95A0008B3EFF82B2CCBBFE527E631A25A6B6C16F6CA6` /
  `62,978,792` bytes.
- Decision: host-verified `route-tooling` plus the existing
  `stackable-cpu-pressure` change. No speed, FPS, temperature, flicker,
  gameplay, or stability credit exists until device comparison passes.
- Next: only after a separate independently cool interval, run one strict
  no-launch installation of exact APK `59D5658E...91BD02`. Reserve one later
  cool round for a self-stopping title proof requiring all 11 activation rows,
  exact durable checkpoint, clean fatal scan, stable title, thermal pass, and
  absent PID before any comparison credit.

### 2026-07-20 - bounded-evidence-successor-install-only

- Status: android-pass
- Scope: config-driver
- Hypothesis: exact host-verified evidence successor `59D5658E...91BD02` can
  replace the installed predecessor without booting RPCSX or exceeding the
  strict cool boundary.
- Changed files/settings: installed the exact pinned ThorTest APK with
  streamed `adb install -r`. The installer force-stopped RPCSX before and
  after, reset experimental controls to their safe defaults, and did not
  launch an activity.
- Rollback: reinstall a prior exact pinned APK through the same no-launch
  workflow; no rollback is currently needed.
- Windows result: the candidate artifact, no-launch installer, and strict-gate
  contracts passed immediately before device work.
- Thor result: strict no-boot gate
  `debug-captures/android-speed-sprint/20260720-142534-thor-input-strict-cool-gate`
  passed silicon samples `34.3 -> 34.3 -> 34.3 C`, maximum `34.3 C` and
  rise `0.0 C`. Battery/skin were `25.0/30.0 C`; gate post-stop silicon was
  `35.1 C`. Install capture
  `debug-captures/android-speed-sprint/20260720-142605-bounded-android-evidence-thortest-apk-install`
  reports `installed-exact-no-launch`. Expected, host, and installed
  `base.apk` SHA-256 all match
  `59D5658EC31130F2CD8FD8F4E02700DFF3BD1AF52B7E89F25CF167EF5C91BD02`.
  PID was absent before and after; post-install battery/skin/silicon were
  `25.0/30.0/35.9 C`.
- Visual correctness: not exercised; the emulator and game did not boot.
- FPS/frame-time: none.
- Capture paths: the strict gate and install captures above.
- Decision: `installed-exact-no-launch` / `route-tooling`. Installation banks
  exact device identity only and grants no speed, FPS, thermal-win, flicker,
  gameplay, or stability credit. No second device query, retry, or launch ran.
- Next: after a separate independently cool interval, run exactly one
  self-stopping `ThorCoolTitle` proof. Require all 11 durable activation rows,
  the exact sync checkpoint, clean critical/fatal evidence, stable title,
  thermal pass, and absent PID before any timing comparison or speed credit.

### 2026-07-20 - bounded-evidence-title-device-selection-refusal

- Status: failed
- Scope: scene-route
- Command: .\tools\eternal_sonata_speed_sprint.ps1 -Action
  AndroidRouteScene -AndroidStartupProfile ThorCoolTitle -Label
  bounded-evidence-successor-title-proof
- Hypothesis: after the independent cooling interval, the exact installed
  evidence successor could enter its single self-stopping ThorCoolTitle proof.
- Changed files/settings: none on device. Host-only artifact/profile contracts
  passed immediately before the attempt. The route resolver ran before logging
  or emulator properties could be applied.
- Rollback: none required.
- Windows result: exact pinned APK 59D5658E...91BD02, packaged core
  5F7938BB...6F6CA6, the ThorCoolTitle profile, capture analyzer, and durable
  Android evidence-logging contracts all passed.
- Thor result: the invocation failed closed at 2026-07-20T14:52-04:00 because
  adb reported two online serials, 80167523365051 and c3ca0370. The wrapper
  required explicit selection and exited before a thermal preflight or app
  launch. No retry or follow-up ADB query ran.
- Visual correctness: not exercised; no route capture exists.
- FPS/frame-time: none.
- Capture paths: none; refusal occurred before capture creation.
- Decision: device-selection-refused / route-tooling. This grants no APK
  identity, temperature, speed, FPS, flicker, gameplay, or stability credit.
  Preserve the last proven installed identity from the prior no-launch capture
  and do not infer current PID or temperature without a future gate.
- Next: after another independent interval, invoke the same pinned
  ThorCoolTitle route exactly once with AndroidSerial c3ca0370. Let its
  identity and three-sample thermal gates decide whether launch is allowed;
  do not probe or retry separately.

### 2026-07-20 - bounded-evidence-launcher-counterproof

- Status: failed
- Scope: scene-route
- Hypothesis: exact installed successor `59D5658E...91BD02` would complete one
  comparison-ready, self-stopping `ThorCoolTitle` proof on pinned Thor
  `c3ca0370`.
- Changed files/settings: no device files changed. The exact pinned profile set
  the already-recorded `2/256/500 ms` RSX cache controls, `64/100 ms` SPU
  preload/compile budgets, cache-worker mask `0x7`, persistent/hit-only Vulkan
  cache on, ADPF/phase pacing off, and Quiet logging.
- Rollback: the route reset experiment properties, force-stopped RPCSX, and
  recorded an absent post-run PID.
- Windows result: not applicable.
- Thor result: exact APK identity matched. Strict preflight stayed
  `33.9 -> 33.9 -> 33.9 C`; silicon peaked at `50.6 C` and post-run was
  `40.5 C`; battery/skin stayed within the guard. The ordered log sync returned
  checkpoint `1`, no targeted fatal was present, and the process was stopped.
- Visual correctness: failed. Frames 02-04 and `04-title-proof.png` show the
  RPCSX game library, not Eternal Sonata. The old classifier accepted cover
  art because center magenta was `11.4%`; the same frame also has a
  `58.306%` near-white horizontal row. Current replay classifies all three poll
  frames `launcher_ui_present=True`, `title_menu_present=False`, so readiness
  is not stable. The prior capture `20260720-134641-thor-input-custom` is
  pixel-equivalent for these metrics and is superseded by the same result.
- FPS/frame-time: none. The `18.913/24.310 s` and earlier
  `18.620/24.361 s` values are launcher timings, not title timings.
- Capture paths:
  `debug-captures/android-speed-sprint/20260720-145444-thor-input-custom` and
  `debug-captures/android-speed-sprint/20260720-134641-thor-input-custom`.
- Decision: `launcher-ui-instead-of-title` / `failed-visual-gate` /
  `not-comparable`. Grant no speed, FPS, thermal-win, flicker, gameplay, or
  stability credit. No additional ADB/device action ran in this round.
- Next: repair debug-boot acceptance evidence and launcher rejection host-side
  before producing another APK.

### 2026-07-20 - fail-closed-debug-boot-launcher-repair

- Status: windows-pass
- Scope: scene-route
- Hypothesis: a request-specific boot handshake plus launcher-aware visual
  replay will prevent route misses from consuming a hot 90-second poll or
  becoming false title/speed evidence.
- Changed files/settings: `MainActivity` now emits nonce-bound accepted/rejected
  debug-boot rows at Warning, enters `RPCSXActivity` before composing the game
  library on accepted cold starts, and reports managed-profile/library/path
  rejection reasons. `thor_input_macro.ps1` clears stale logcat, passes a fresh
  request ID, requires its exact acknowledgement within 30 seconds, and
  force-stops before visual routing on rejection/timeout. The visual classifier
  rejects the bright RPCSX launcher row; the capture analyzer reclassifies the
  actual poll PNGs and requires an accepted handshake. Focused synthetic tests
  cover valid title, launcher, missing handshake, and rejected handshake.
- Rollback: restore the old void debug-boot helper, remove the nonce handshake,
  and remove `launcher_ui_present`; no emulator-core behavior changed.
- Windows result: known real title replay remains accepted at `1.792%` white;
  both false launcher captures reject at `58.306%`. Focused contracts pass,
  all `62/62` `test_thor_*.ps1` contracts pass, PowerShell parsing and diff
  checks pass, and `:app:compileThortestKotlin` succeeds in `29 s`.
- Thor result: none after the failed capture; no ADB query, install, launch, or
  device read ran during this repair.
- Visual correctness: host replay only; correct title accepted, RPCSX launcher
  rejected, readiness false for all three saved launcher poll frames.
- FPS/frame-time: none; this is measurement integrity and avoided startup/UI
  work, not a measured gameplay-speed claim.
- Capture paths: existing two counterproof captures above; no new raw capture.
- Artifact result: the first wrapper timed out after `304 s`, then its late
  default-ABI output was correctly rejected because it contained x86-64 and was
  `100,223,304` bytes. A clean explicit
  `-PrpcsxAndroidAbis=arm64-v8a :app:assembleThortest` completed in `124.5 s`.
  Exact ARM64 APK is `85DB41BB7A62AB81009889C1CB5DC021C8D27847DACFA0997E8E5FBA080E5C52`
  / `72,829,500` bytes. Its three DEX files contain the nonce and accepted-boot
  markers. Merged core remains
  `CB06FE9C5DDAA1F009217C3886295C4283810A95F4262BC4AA5B369363C5BBF2`
  / `1,304,043,704` bytes; packaged core remains
  `5F7938BB5A0A29DB67FA95A0008B3EFF82B2CCBBFE527E631A25A6B6C16F6CA6`
  / `62,978,792` bytes. ARM64-only ABI and candidate identity contracts pass.
- Decision: retain as `route-tooling` and startup-overhead reduction. A fresh
  exact host candidate is pinned, but it is uninstalled/device-unmeasured and
  receives no speed, FPS, temperature, flicker, gameplay, or stability credit.
- Next: use separate independently cool rounds for exact no-launch install and
  one self-stopping proof. Do not route installed old APK
  `59D5658E...91BD02` with the new mandatory handshake tool.
