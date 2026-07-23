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

### 2026-07-20 - fail-closed-candidate-no-launch-install

- Status: android-pass
- Scope: scene-route
- Hypothesis: exact repaired ARM64 candidate 85DB41BB...E5C52 can replace the
  stale installed APK under a strict cool gate without launching RPCSX or
  leaving its process alive.
- Changed files/settings: device package net.rpcsx.easy was updated with
  adb install -r; no activity, game, firmware, cache, or emulator setting was
  opened or changed. No source changed during the device action.
- Rollback: reinstall the prior pinned APK 59D5658E...91BD02; no rollback is
  currently indicated because exact identity and stopped-state checks passed.
- Windows result: host APK was 72,829,500 bytes with exact SHA-256
  85DB41BB7A62AB81009889C1CB5DC021C8D27847DACFA0997E8E5FBA080E5C52;
  the ARM64-only candidate and no-launch installer contracts passed before
  device contact.
- Thor result: pinned serial c3ca0370 passed the three-sample cool gate at
  31.3 -> 30.9 -> 31.5 C; maximum was 31.5 C and end-to-start rise was
  +0.2 C. adb install -r reported success, installed base.apk matched
  the exact host SHA-256, PID was absent before and after, and post-install
  battery/skin/silicon were 22.0/30.0/34.3 C.
- Visual correctness: not exercised; no RPCSX activity or game launched.
- FPS/frame-time: none; installation identity is not a speed, frame-time,
  flicker, gameplay, stability, or thermal-win measurement.
- Capture paths:
  debug-captures/android-speed-sprint/20260720-201536-thor-input-strict-cool-gate
  and
  debug-captures/android-speed-sprint/20260720-201549-fail-closed-debug-boot-no-launch-install.
- Decision: installed-exact-no-launch / android-pass for installed identity
  only. Device work ended immediately after verification; no retry or
  follow-up ADB action ran.
- Next: after a separate independently cool interval, run exactly one
  self-stopping ThorCoolTitle proof with pinned serial c3ca0370. Require the
  nonce-bound accepted boot handshake, exact sync checkpoint, stable real
  Eternal Sonata title, clean fatal evidence, thermal pass, and absent final
  PID before granting any timing or speed credit.

### 2026-07-20 - managed-profile-custom-config-refusal

- Status: failed
- Scope: scene-route
- Hypothesis: installed launcher-aware candidate 85DB41BB...E5C52 would
  accept its nonce-bound debug boot and reach one self-stopping real-title
  proof under the ThorCoolTitle profile.
- Changed files/settings: no source changed before the run. The route set
  its pinned lower-power startup properties, then reset them on failure.
  It did not replace or edit the existing BLUS30161 custom YAML.
- Rollback: none required; the route force-stopped RPCSX and reset its
  experiment properties.
- Windows result: exact candidate/profile/analyzer/visual/log-sync host
  contracts passed immediately before device contact.
- Thor result: exact installed base.apk matched 85DB41BB...E5C52 on pinned
  serial c3ca0370. Strict preflight was 31.3 -> 31.5 -> 31.7 C. The
  request-specific handshake rejected after 712 ms with
  reason=managed-profile-not-applied, custom=true, enabled=false,
  applied=false, stale=false, error=null. The app was force-stopped before
  the PPU-ready/title poll; final PID was absent. The failure-post-stop
  battery/skin/silicon snapshot was 22.0/30.0/38.1 C.
- Visual correctness: not exercised; no title screenshot was taken and the
  RPCSX launcher was not accepted as game evidence.
- FPS/frame-time: none; no game boot or comparable timing occurred.
- Capture paths:
  debug-captures/android-speed-sprint/20260720-202356-thor-input-custom.
- Decision: managed-profile-custom-config-refusal / failed /
  not-comparable. The repaired handshake saved the device from a blind
  90-second poll, but grants no speed, gameplay, flicker, stability, or
  thermal-win credit. No retry or follow-up ADB action ran.
- Next: make the benchmark route invoke the app-supported, backup-first
  custom-to-managed transition explicitly; build a new APK host-side.

### 2026-07-20 - backup-first-managed-profile-repair

- Status: windows-pass
- Scope: scene-route
- Hypothesis: a debug-only explicit replacement request can make the
  deterministic Thor profile apply even when BLUS30161 has a user custom
  YAML, while preserving that YAML through the existing backup path.
- Changed files/settings: MainActivity consumes and removes the
  thorReplaceCustomProfile extra, then calls a new title-ID form of the
  existing replace-custom-with-recommended API only when both managed and
  replacement flags are requested. thor_input_macro.ps1 supplies that flag.
  Candidate verification now requires the request and replacement-method
  strings in packaged DEX. No native-core code changed.
- Rollback: remove the replacement extra/call and restore candidate
  85DB41BB...E5C52. On the future device transition, the pre-existing
  backupCustomConfig(target) call copies the user YAML before
  target.writeText(body), providing a file-level rollback.
- Windows result: PowerShell parsing and diff checks pass; the focused
  PPU/profile, title analyzer, visual, log-sync, candidate, ARM64, and
  optimized-package contracts pass. The complete Thor suite is 62/62.
  :app:compileThortestKotlin passed in 9 s and explicit ARM64-only
  :app:assembleThortest passed in 14 s.
- Thor result: none after the refusal; no additional ADB query, install,
  launch, or temperature read ran during the repair.
- Visual correctness: host replay only; the known real title remains
  accepted and both saved launcher captures remain rejected.
- FPS/frame-time: none; this is route integrity and reversible profile
  setup, not a measured speed or thermal win.
- Artifact result: exact ARM64 APK
  089655E248BBFC323C04363244F5EE97953766041EFE3FD96CCCBF3A396F00EF
  is 72,829,872 bytes. Its DEX contains thorDebugBootRequestId, the accepted
  handshake marker, thorReplaceCustomProfile, and
  replaceCustomWithRecommendedConfigForTitleId. Merged core remains
  CB06FE9C5DDAA1F009217C3886295C4283810A95F4262BC4AA5B369363C5BBF2
  / 1,304,043,704 bytes; packaged core remains
  5F7938BB5A0A29DB67FA95A0008B3EFF82B2CCBBFE527E631A25A6B6C16F6CA6
  / 62,978,792 bytes.
- Capture paths: existing refusal capture above; no new raw capture.
- Decision: route-tooling / windows-pass. The successor is pinned but
  uninstalled and device-unmeasured, so it receives no speed, FPS,
  flicker, gameplay, stability, or temperature credit.
- Next: use one later independently cool round for exact no-launch install
  of 089655E2...6F00EF, then another cool round for one self-stopping
  ThorCoolTitle proof. Require accepted handshake, real title, sync/fatal
  completeness, thermal pass, and absent final PID before timing credit.

### 2026-07-20 - backup-first-candidate-install-hot-refusal

- Status: failed
- Scope: config-driver
- Hypothesis: exact backup-first candidate 089655E2...6F00EF could be installed
  without launching RPCSX after a new strict cool preflight.
- Changed files/settings: none. The gate force-stopped RPCSX and reset the
  experiment properties before sampling. The installer was not invoked.
- Rollback: none required; no APK, game, cache, firmware, or custom YAML was
  changed.
- Windows result: exact candidate, DEX markers, ARM64/native identity, strict
  cool-gate, and no-launch installer contracts passed before device contact.
- Thor result: pinned serial c3ca0370 refused at pre-run sample 1 because
  silicon was 45.8 C, above the strict below-35 C launch ceiling. Battery/skin
  were 22.0/30.0 C. The failure-post-stop silicon snapshot was 49.0 C and PID
  was absent. No second sample, install, launch, query, or retry ran.
- Visual correctness: not exercised; no activity or game launched.
- FPS/frame-time: none; this grants no speed or thermal-win credit.
- Capture paths:
  debug-captures/android-speed-sprint/20260720-204254-thor-input-strict-cool-gate.
- Decision: preflight-refused-hot / failed. Candidate 089655E2...6F00EF remains
  uninstalled; the last proven installed identity remains 85DB41BB...E5C52.
- Next: wait for a genuinely independent cooling interval, then attempt the
  exact no-launch install once. Do not combine that install with runtime; keep
  the self-stopping ThorCoolTitle proof for another later cool round.

### 2026-07-20 - backup-first-candidate-exact-no-launch-install

- Status: installed-exact-no-launch
- Scope: config-driver
- Hypothesis: exact backup-first candidate 089655E2...6F00EF can replace the
  prior installed APK without launching RPCSX after a fresh strict cool gate.
- Changed files/settings: installed only the frozen ARM64 ThorTest APK. The
  emulator was force-stopped at both boundaries; no game, firmware, cache, or
  custom YAML was opened by an activity in this round.
- Rollback: reinstall a prior exact APK through the same no-launch workflow.
  The candidate's future debug-only managed-profile transition retains the
  backup-first custom-YAML path, but that transition was not exercised here.
- Windows result: exact host APK SHA-256
  089655E248BBFC323C04363244F5EE97953766041EFE3FD96CCCBF3A396F00EF and
  size 72,829,872 bytes revalidated. All 63/63 Thor host contracts pass; the
  strict-gate and no-launch installer focused contracts passed immediately
  before device contact.
- Thor result: pinned serial c3ca0370 passed the three-sample gate at
  32.1 -> 32.1 -> 31.9 C (maximum 32.1 C, rise -0.2 C), with battery/skin
  22.0/30.0 C. `adb install -r` reported Success. Expected, host, and installed
  base.apk SHA-256 all equal 089655E2...6F00EF. PID was absent before and after;
  post-install battery/skin/silicon were 22.0/30.0/33.7 C. No activity launched
  and no follow-up ADB query or retry ran.
- Visual correctness: not exercised; no emulator or game activity launched.
- FPS/frame-time: none. Installation identity and bounded temperature grant no
  speed, gameplay, stability, flicker, or thermal-win credit.
- Capture paths:
  debug-captures/android-speed-sprint/20260720-210930-thor-input-strict-cool-gate;
  debug-captures/android-speed-sprint/20260720-210942-custom-profile-backup-thortest-apk-install.
- Decision: installed-exact-no-launch / route-tooling. The frozen candidate is
  now the proven installed identity and remains runtime-unmeasured.
- Next: after a separate independently cool interval, run exactly one
  self-stopping ThorCoolTitle proof pinned to 089655E2...6F00EF. Require the
  accepted custom-to-managed handshake, real title stabilization, complete
  sync/fatal evidence, bounded thermals, and absent final PID before any timing
  or stability credit.

### 2026-07-20 - two-worker-ppu-startup-thermal-counterproof

- Status: failed
- Scope: config-driver
- Hypothesis: exact installed backup-first candidate 089655E2...6F00EF could
  complete the managed-profile transition and reach a stable real title under
  the self-stopping ThorCoolTitle profile.
- Changed files/settings before the run: none. The route used the pinned
  installed APK, Direct input, RSX/SPU limits 256/64, 500/100 ms RSX/SPU
  budgets, cache affinity 0x07, Vulkan hit-only preload, frame wait, and the
  68/72 C early/hard thermal guard.
- Rollback: the route force-stopped RPCSX and reset its properties. PID was
  absent after failure; no retry or follow-up ADB action ran.
- Windows result: exact candidate/profile/analyzer/artifact contracts passed
  before device contact.
- Thor result: pinned serial c3ca0370 matched installed SHA-256
  089655E248BBFC323C04363244F5EE97953766041EFE3FD96CCCBF3A396F00EF.
  Preflight was 31.7 -> 32.3 -> 31.7 C and the nonce-bound debug boot was
  accepted in 689 ms. The first screenshot 1.245 s later was still pre-title.
  Silicon was 47.0 C there, then reached 69.5 C before the ten-second wait
  completed; the 68 C early guard force-stopped below the 72 C hard limit.
  Failure post-stop was 47.4 C with battery/skin 22.0/30.0 C, PID absent, and
  zero targeted fatal hits.
- Runtime diagnosis: the managed log contained `Max LLVM Compile Threads: 2`
  and the log showed `PPUW.1.1` through `PPUW.7.1` compilation activity.
  Process CPU was about 25%, RSS was about 5,658 MB, big CPU cores were active while the GPU
  stayed at 401 MHz, and silicon rose 47.0 -> 69.5 C in roughly 1.8 seconds.
  This isolates cold PPU LLVM compile concurrency as the immediate heat burst;
  it does not prove a gameplay bottleneck or speedup.
- Visual correctness: title, field, menu, and battle were not reached. The one
  frame was neither the RPCSX launcher nor a valid Eternal Sonata title.
- FPS/frame-time: none; no comparison-ready scene or end-to-end title timing
  exists.
- Capture path:
  debug-captures/android-speed-sprint/20260720-211548-thor-input-custom.
- Decision: thermal-stop-before-title / failed / not-comparable. Grant no
  speed, FPS, flicker, gameplay, stability, or thermal-win credit.

### 2026-07-20 - blus30161-single-ppu-compile-worker-successor

- Status: windows-pass
- Scope: config-driver
- Hypothesis: serializing only Eternal Sonata's cold PPU LLVM compile work can
  lower the burst that stopped the two-worker route while preserving the
  global two-worker Thor default for other titles.
- Changed files/settings: the BLUS30161 managed profile now sets
  `Max LLVM Compile Threads: 1`. The analyzer requires the runtime row, its
  synthetic counterproof fails closed when missing, and the pinned artifact
  contract requires the packaged DEX marker. No native-core code changed.
- Rollback: remove the title-specific setting to restore the inherited global
  `Max LLVM Compile Threads: 2` value.
- Windows result: all 64/64 `test_thor_*.ps1` contracts pass. The explicit
  ARM64-only optimized ThorTest build completed in 15 s, and the artifact,
  activation, analyzer-counterproof, ABI, optimized-variant, and package/core
  identity gates pass.
- Artifact result: exact uninstalled APK
  A3FC89F71C215DBF1F3DB12D6A6C4ACA2E62F9C6740F8DDC97736F3D2837DDDF
  is 72,829,996 bytes. Merged core remains
  CB06FE9C5DDAA1F009217C3886295C4283810A95F4262BC4AA5B369363C5BBF2
  / 1,304,043,704 bytes; packaged core remains
  5F7938BB5A0A29DB67FA95A0008B3EFF82B2CCBBFE527E631A25A6B6C16F6CA6
  / 62,978,792 bytes.
- Thor result: none for the successor. It is not installed and has no runtime
  thermal, timing, FPS, visual, flicker, gameplay, or stability credit.
- Decision: bounded cold-start thermal candidate / windows-pass. This is not a
  measured speedup or temperature win.
- Next: use one later independently cool round for exact no-launch install of
  A3FC89F7...37DDDF, then a different independently cool round for one
  self-stopping ThorCoolTitle proof. Require exact identity, the one-thread
  runtime activation row, stable real title, complete fatal/log evidence,
  bounded thermals, and absent final PID before any comparison credit.

### 2026-07-20 - single-ppu-worker-install-hot-refusal

- Status: failed
- Scope: config-driver
- Hypothesis: exact one-worker candidate A3FC89F7...37DDDF could be installed
  without launching RPCSX after a fresh strict cool preflight.
- Changed files/settings: none. The gate force-stopped RPCSX and reset all
  experiment properties before sampling. The no-launch installer was not
  invoked.
- Rollback: none required; no APK, activity, game, firmware, cache, or custom
  YAML changed.
- Windows result: the one-worker source contract, exact candidate artifact,
  strict cool gate, and no-launch installer contracts passed before contact.
- Thor result: pinned serial c3ca0370 refused at pre-run sample 1 because
  silicon was 47.4 C, above the strict below-35 C ceiling. Battery/skin were
  23.0/30.0 C. Failure post-stop silicon was 45.3 C and `failure-pid.txt`
  proves RPCSX absent. No second thermal sample, install, launch, retry, or
  follow-up device query ran.
- Visual correctness and FPS/frame-time: not exercised; no activity launched.
- Capture path:
  debug-captures/android-speed-sprint/20260720-214440-thor-input-strict-cool-gate.
- Decision: preflight-refused-hot / failed. Exact candidate
  A3FC89F7...37DDDF remains host-verified and uninstalled; installed APK
  089655E2...6F00EF remains unchanged. Grant no speed, FPS, temperature,
  flicker, gameplay, or stability credit.
- Next: wait for a genuinely independent cool interval and make one new
  install-only attempt. Runtime proof still belongs to a different later cool
  round.

### 2026-07-20 - blus30161-ppu-compile-efficiency-core-affinity-successor

- Status: windows-pass
- Scope: config-driver
- Hypothesis: the existing one-thread BLUS30161 PPU LLVM cap can avoid the
  measured big-core heat burst more effectively if that temporary cold compile
  work uses Thor's 0x07 efficiency-core mask, without leaking the mask into
  runtime emulation.
- Changed files/settings: PPU cold object compilation now reads the existing
  Android-only, BLUS30161-only startup cache-worker mask. A scoped guard first
  captures the caller or helper thread's current affinity, applies the mask
  only when that capture succeeds, records exact requested/effective evidence,
  and restores the prior mask on every normal or exceptional exit. Mask-off,
  other-title, desktop, and runtime PPU/SPU/RSX/render scheduling are unchanged.
  The capture analyzer now requires the PPU affinity row, treats mismatch as an
  activation failure, and includes a synthetic missing-row counterproof. The
  artifact contract scans the packaged native core for the durable marker.
- Rollback: remove the scoped affinity guard and PPU activation requirement;
  the independent title-specific Max LLVM Compile Threads: 1 cap remains a
  separate reversible control.
- Windows result: focused affinity, evidence-logging, analyzer, and PPU-cap
  contracts pass. ARM64 RelWithDebInfo compilation completed in 114.1 s;
  explicit ARM64-only optimized ThorTest packaging completed in 53 s. The full
  suite passes 64/64 test_thor_*.ps1 contracts, including ABI, optimized
  variant, native marker, exact core/APK identity, and analyzer counterproofs.
- Artifact result: exact uninstalled APK
  EDDC3DF146A6914CE73BA7AE6B562F2FF702089D8C1424315CE3DFBD4F2A7039
  is 72,829,932 bytes. Merged core
  FF170281B171E01D97131F750F425410E4863BD357D1A175580F2A0F53EB5627
  is 1,304,045,272 bytes; packaged core
  60BA247434D131111F0CE2DE426AF1C31A679F2424A9534149979D0FA990AC49
  is 62,979,016 bytes and matches the APK entry exactly. It supersedes the
  uninstalled one-worker APK A3FC89F7...37DDDF. Installed device identity
  remains 089655E2...6F00EF.
- Thor result: none. No ADB query, install, launch, retry, or temperature read
  ran in this host-only round.
- Visual correctness and FPS/frame-time: not exercised. This is a bounded
  cold-start thermal candidate, not a measured speed, temperature, flicker,
  gameplay, or stability win.
- Decision: retain / windows-pass / device-unmeasured. The change directly
  addresses the isolated PPU LLVM big-core heat source while restoring runtime
  affinity, but earns no comparison credit until Thor proves it.
- Next: after a genuinely independent cool interval, run one strict no-launch
  install of exact APK EDDC3DF1...2A7039. Reserve one later independently cool
  self-stopping ThorCoolTitle run for exact identity, one-thread and PPU
  affinity activation, real-title stabilization, complete fatal/log evidence,
  bounded thermals, and absent final PID. Do not combine install and runtime.

### 2026-07-20 - ppu-efficiency-core-candidate-exact-no-launch-install

- Status: installed-exact-no-launch
- Scope: config-driver
- Hypothesis: exact efficiency-core-affinity candidate EDDC3DF1...2A7039 can
  replace the two-worker installed APK under the strict cool gate without
  launching or leaving RPCSX active.
- Changed files/settings: installed only the frozen ARM64 ThorTest APK with
  adb install -r. The route force-stopped RPCSX at both boundaries. It did not
  open the emulator, game, firmware, cache, or managed/custom profile.
- Rollback: reinstall a prior exact APK through the same cool no-launch route;
  no rollback is indicated because identity and stopped-state checks passed.
- Windows result: exact APK/core identity, native PPU-affinity marker,
  ARM64-only package, strict gate, and no-launch installer contracts passed
  immediately before device contact.
- Thor result: pinned serial c3ca0370 passed the three-sample gate at
  31.5 -> 31.7 -> 31.9 C (maximum 31.9 C, rise +0.4 C), with battery/skin
  22.0/30.0 C. adb install -r returned Success. Expected, host, and installed
  base.apk SHA-256 all equal
  EDDC3DF146A6914CE73BA7AE6B562F2FF702089D8C1424315CE3DFBD4F2A7039.
  PID was absent before and after; post-install battery/skin/silicon were
  22.0/30.0/33.3 C. No activity launched and no follow-up ADB query or retry
  ran.
- Visual correctness and FPS/frame-time: not exercised. Installation identity
  and bounded install temperature grant no speed, thermal, gameplay, flicker,
  or stability credit.
- Capture paths:
  debug-captures/android-speed-sprint/20260720-222048-thor-input-strict-cool-gate;
  debug-captures/android-speed-sprint/20260720-222101-ppu-efficiency-core-thortest-apk-install.
- Decision: installed-exact-no-launch / route-tooling. The candidate is now
  frozen on-device and RPCSX is stopped.
- Next: stop this device round. After a different independently cool interval,
  run exactly one self-stopping ThorCoolTitle proof pinned to EDDC3DF1...2A7039.
  Require exact identity, Max LLVM Compile Threads: 1, exact PPU 0x07 affinity
  activation, stable real title, complete log/fatal evidence, bounded thermals,
  and absent final PID before granting comparison credit.

### 2026-07-20 - ppu-efficiency-core-cold-compile-runtime-counterproof

- Status: failed
- Scope: config-driver
- Hypothesis: serializing BLUS30161 cold PPU LLVM compilation on Thor's `0x07`
  efficiency-core mask can remove the measured big-core thermal burst while
  still reaching a stable title within the bounded proof window.
- Changed files/settings: no source or profile changed for the run. The exact
  installed APK used Direct input, `Max LLVM Compile Threads: 1`, RSX/SPU
  limits `256/64`, RSX/SPU budgets `500/100 ms`, cache affinity `0x07`, Vulkan
  hit-only preload, frame wait, and the `68/72 C` early/hard thermal guard.
  Normal cold compilation populated 12 PPU object-cache entries before stop.
- Rollback: the route force-stopped RPCSX and reset experiment properties.
  PID was absent after failure. No retry or follow-up ADB action ran.
- Windows result: exact candidate, profile, analyzer, artifact, durable-log,
  and thermal contracts passed before device contact.
- Thor result: pinned serial `c3ca0370` matched installed SHA-256
  `EDDC3DF146A6914CE73BA7AE6B562F2FF702089D8C1424315CE3DFBD4F2A7039`.
  Preflight was `31.7 -> 32.3 -> 31.7 C` and the nonce-bound debug boot was
  accepted in `136 ms`. The managed profile logged
  `Max LLVM Compile Threads: 1`; all 13 started module compiles logged exact
  `requested=0x7,effective=0x7` PPU affinity. Twelve completed between emulator
  times `1.684` and `88.208 s`; `libresc.sprx` was still compiling at stop.
- Thermal result: the first post-boot sample was the `53.0 C` run maximum. It
  fell to `42.1 C` by the next poll and generally remained `38.9-45.8 C`
  through the bounded run; the post-stop sample was `43.3 C`. This is a large
  cold-compile heat reduction versus capture
  `20260720-211548-thor-input-custom`, whose unpinned two-worker path reached
  `69.5 C` and triggered the early guard before title. It is not an end-to-end
  thermal win because neither route produced a comparison-ready scene.
- Visual correctness: five bounded polls remained pre-title. Cyan coverage was
  `51.935%` after the first frame while the progress-bar metric rose from `0`
  to `10.749%`; title, launcher, black-frame, field, menu, and battle checks
  never passed. The visual-classifier result remained fail-closed.
- FPS/frame-time: none. The title did not stabilize within the 90-second gate,
  so there is no startup-speed, FPS, frame-time, or gameplay comparison.
- Fatal/stopped state: zero targeted fatal hits, thermal guard did not fire,
  the self-stopping failure path completed, and final PID was absent.
- Capture path:
  `debug-captures/android-speed-sprint/20260720-222640-thor-input-custom`.
- Decision: `route-failed-before-title` / thermal-progress / failed /
  not-comparable. The affinity control fixed the immediate heat burst but the
  one-worker little-core cold path is slower than the bounded startup target;
  grant no speed, FPS, flicker, gameplay, stability, or end-to-end thermal-win
  credit.
- Next: do not retry in this device round. After a genuinely independent cool
  interval, allow at most one identical self-stopping warm-cache continuation.
  It can test whether the 12 newly completed objects make title reach practical
  while preserving the thermal improvement. If it still misses title, prepare
  a host-only successor that keeps PPU compile affinity separate from runtime
  workers and evaluates two compile workers on little cores; do not clear the
  device cache merely to manufacture a cold benchmark.

### 2026-07-20 - two-little-core-ppu-compile-successor

- Status: windows-pass
- Scope: config-driver
- Hypothesis: two cold PPU LLVM workers confined to Thor's three Cortex-A510
  cores can recover most of the serial candidate's startup throughput without
  returning to the unpinned big-core heat burst.
- Changed files/settings: the BLUS30161 managed profile now explicitly uses
  `Max LLVM Compile Threads: 2`. A new PPU-only policy helper returns the
  existing nonzero startup-worker override when present and otherwise defaults
  this title's Android cold PPU compilation to mask `0x07`. PPU compilation
  continues using the scoped affinity guard, so both helper and caller workers
  restore their prior masks before runtime. Desktop, other titles, and runtime
  PPU/SPU/RSX/audio/render scheduling are unchanged. The analyzer, synthetic
  counterproof, artifact marker, and source contracts now fail closed unless
  the two-thread row and exact `requested=0x7,effective=0x7` activation exist.
- Rollback: set the managed title profile back to one compile thread and remove
  `get_ppu_compile_worker_affinity_mask`, returning PPU compilation to the
  explicit startup-worker property only. No device rollback is needed because
  this candidate has not been installed.
- Windows result: focused thermal-cap, affinity, durable-evidence, analyzer,
  profile, artifact, and explicit ARM64-only ABI contracts pass. Optimized
  ARM64 native compilation completed in 88 s. The first generic package was
  correctly rejected from candidate use because it included x86-64; corrected
  `-PrpcsxAndroidAbis=arm64-v8a :app:assembleThortest` completed in 24 s. The
  complete host suite passes 64/64 `test_thor_*.ps1` contracts.
- Artifact result: exact host-only APK
  `B5B5DB6B0C9E076E82DAA9D9E183028D8B286CA667B5CF686A116A19B4074522`
  is 72,829,976 bytes and contains only ARM64 RPCSX libraries. Merged core
  `1F3671B9A3803FCE81BBE732327B209A6BDDFC27D04A94DF9BFB776100333C00`
  is 1,304,047,216 bytes. Packaged core
  `EA4451EA1D7050203F7C1FBF57F7108AA05E5470E95D90D7E7C32D2FBA81E615`
  is 62,979,016 bytes and matches the APK entry exactly.
- Thor result: none. No ADB query, install, launch, retry, temperature read, or
  cache mutation occurred. Exact installed APK remains
  `EDDC3DF146A6914CE73BA7AE6B562F2FF702089D8C1424315CE3DFBD4F2A7039`.
- Visual correctness and FPS/frame-time: not exercised. This is an uninstalled
  bounded cold-start throughput candidate, not a measured speed, temperature,
  FPS, flicker, gameplay, or stability result.
- Decision: retain / windows-pass / device-unmeasured. The change directly
  addresses the measured one-worker timeout while preserving the proven
  little-core thermal envelope in normal product launches, but earns no
  comparison credit until Thor proves it.
- Next: after a genuinely independent cool interval, run one strict no-launch
  install of exact APK `B5B5DB6B...B4074522`. Stop after exact on-device hash
  and absent-PID proof. Reserve one self-stopping `ThorCoolTitle` run for a
  different later cool round; require the two-thread row, exact PPU `0x07`
  affinity, real title stabilization, complete fatal/log evidence, bounded
  thermals, and absent final PID before any startup-speed or thermal credit.

### 2026-07-20 - two-little-core-ppu-candidate-exact-no-launch-install

- Status: installed-exact-no-launch
- Scope: config-driver
- Hypothesis: exact two-worker little-core candidate B5B5DB6B...B4074522 can
  replace the one-worker installed APK under the strict cool gate without
  launching RPCSX or leaving its process active.
- Changed files/settings: installed only the frozen ARM64 ThorTest APK with
  `adb install -r`. The route force-stopped RPCSX at both boundaries. It did
  not open the emulator, game, firmware, cache, or managed/custom profile.
- Rollback: reinstall a prior exact APK through the same cool no-launch route;
  no rollback is indicated because identity and stopped-state checks passed.
- Windows result: immediately before device contact, the candidate manifest
  matched the 72,829,976-byte APK and its merged/packaged cores; the APK
  contained only ARM64 RPCSX libraries. Candidate-artifact, strict-gate, and
  no-launch-installer contracts passed.
- Thor result: pinned serial `c3ca0370` passed the three-sample gate at
  `33.5 -> 34.1 -> 34.1 C` (maximum `34.1 C`, rise `+0.6 C`), with
  battery/skin `23.0/30.0 C`. `adb install -r` returned `Success`. Expected,
  host, and installed `base.apk` SHA-256 all equal
  `B5B5DB6B0C9E076E82DAA9D9E183028D8B286CA667B5CF686A116A19B4074522`.
  PID was absent before and after; post-install battery/skin/silicon were
  `23.0/30.0/35.9 C`. No activity launched and no follow-up ADB query or retry
  ran.
- Visual correctness and FPS/frame-time: not exercised. Installation identity
  and bounded install temperature grant no speed, thermal, gameplay, flicker,
  or stability credit.
- Capture paths:
  `debug-captures/android-speed-sprint/20260720-230635-thor-input-strict-cool-gate`;
  `debug-captures/android-speed-sprint/20260720-230647-two-little-core-ppu-thortest-apk-install`.
- Decision: installed-exact-no-launch / route-tooling. The candidate is now
  frozen on-device and RPCSX is stopped.
- Next: stop this device round. After a different independently cool interval,
  run exactly one self-stopping `ThorCoolTitle` proof pinned to
  B5B5DB6B...B4074522. Require `Max LLVM Compile Threads: 2`, exact PPU
  `requested=0x7,effective=0x7` activation, stable real title, complete
  log/fatal evidence, bounded thermals, and absent final PID before granting
  startup-speed, FPS, thermal, flicker, gameplay, or stability credit.

### 2026-07-21 - two-little-core-ppu-runtime-counterproof

- Status: failed
- Scope: config-driver
- Hypothesis: two BLUS30161 cold PPU LLVM workers confined to Thor's three
  Cortex-A510 cores can restore enough startup throughput to reach a stable
  title inside 90 seconds while preserving the one-worker thermal envelope.
- Changed files/settings: no source or profile changed for the run. Exact
  installed APK B5B5DB6B...B4074522 used the pinned `ThorCoolTitle` profile:
  two PPU compile workers, cache affinity `0x07`, RSX/SPU limits `256/64`,
  RSX/SPU budgets `500/100 ms`, Vulkan hit-only preload, and the `68/72 C`
  early/hard thermal guard. Normal compilation extended the existing cache.
- Rollback: the failure path force-stopped RPCSX and reset experiment
  properties. PID was absent after failure. No retry or follow-up ADB action
  ran.
- Windows result: exact candidate artifact, ARM64 ABI, profile, and fail-closed
  analyzer contracts passed immediately before device contact.
- Thor result: pinned serial `c3ca0370` matched installed SHA-256
  `B5B5DB6B0C9E076E82DAA9D9E183028D8B286CA667B5CF686A116A19B4074522`.
  Preflight was `30.5 -> 30.1 -> 30.1 C`; the nonce-bound debug boot was
  accepted in `698 ms`. The managed profile logged
  `Max LLVM Compile Threads: 2` and `Set DAZ and FTZ: true`. PPU lanes 1 and 2
  both compiled, and all 18 affinity activation rows were exact
  `requested=0x7,effective=0x7`.
- Compile progress: the warmed cache reported 17 `Module exists` hits.
  Twenty-one LLVM object variants started, 19 completed, and two remained
  active when the captured log ended at emulator time `91.945861 s`. The
  prior one-worker route reported 5 hits, 13 starts, and 12 completions by
  `88.208 s`; its 12 completed objects helped warm this run and the remaining
  module mix differs, so the higher completion count is startup-progress
  evidence, not a matched throughput or end-to-end speed result. Peak logged
  RSS rose from 5,877 MiB to 6,052 MiB across those non-matched cache states.
- Thermal result: silicon preflight was `30.5 -> 30.1 -> 30.1 C`, run maximum
  was `47.4 C`, most later samples stayed `38.9-47.0 C`, and
  failure-post-stop was `45.3 C`. No thermal guard fired. This remains
  non-comparable to the one-worker run because initial temperature, cache
  state, and work mix differ.
- Visual correctness: five readiness frames remained pre-title. Frames 2-5
  held `51.935%` cyan while the progress-bar metric rose
  `2.932% -> 14.658% -> 19.544% -> 23.453%`; title, launcher, and black-frame
  classifiers stayed false. Field, menu, battle, and flicker were not tested.
- FPS/frame-time: none. The title did not stabilize inside the 90-second gate,
  so the capture is not comparison-ready and receives no speed credit.
- Fatal/stopped state: the complete failure log reached emulator time
  `91.945861 s`, zero targeted fatal hits were found, the route force-stopped,
  and saved failure PID evidence was absent. The analyzer classifies
  `route-failed-before-title` with maximum silicon `47.4 C`.
- Capture path:
  `debug-captures/android-speed-sprint/20260721-105440-thor-input-custom`.
- Decision: `route-failed-before-title` / thermal-progress / failed /
  not-comparable. Two little-core workers are thermally viable in this warmed
  compile window but still do not meet the title-start target. Grant no
  startup-speed, FPS, thermal-win, flicker, gameplay, or stability credit.
- Next: do not contact Thor again in this device round. Analyze the pre-title
  firmware-PRX load/compile breadth on the host and identify a correctness-safe
  way to avoid or pre-materialize unnecessary startup objects. Any successor
  must pass host contracts and a later independently cool, single self-stopping
  proof; do not clear the device cache or retry merely to finish compilation.
### 2026-07-21 - stopped-emulator-firmware-ppu-prewarm-successor

- Status: windows-pass
- Scope: config-driver
- Hypothesis: compiling Eternal Sonata's required LLE firmware PRXs through
  the existing stopped-emulator Prepare Cache action can remove the measured
  90-second pre-title cold work from normal launch without increasing launch
  temperature or changing emulated behavior.
- Changed files/settings: explicit BLUS30161 preparation now requires the
  applied managed profile, loads it into the native configuration, mirrors the
  three LLVM compatibility fixups used by boot, verifies LLVM plus two workers
  plus hardware FTZ, and restores the previous global configuration on every
  exit. The workload adds dev_flash/sys/external only for this title and leaves
  RPCS3's existing HLE/LLE firmware filter authoritative. The caller fails
  closed for disabled, stale, or custom settings. The redundant host-side
  recursive enumeration was removed because ppu_precompile already recurses.
- Rollback: remove the precompileFirmwareModules workload flag and managed
  config scope, restore the former game-root-only queue, and remove the app-side
  BLUS30161 gate. Existing cache objects remain versioned and safe to ignore.
- Host result: the focused config/firmware contract, raw-object-cache contract,
  FTZ/NJ cache-identity contract, worker-affinity contract, Kotlin compilation,
  optimized ARM64 native build, ARM64-only APK build, ABI gate, optimized
  variant gate, pinned artifact gate, and complete 65/65 Thor host suite pass.
  Native compilation took 141.4 seconds and packaging took 88.1 seconds.
- Artifact result: exact host-only APK
  3B6ACA6D3E393197FFFB35D58FC6F7DAE947CEC35C6DA091DC20368478C76404 is
  72,828,756 bytes. Merged core
  4D1B95CE4FD70C41992DEECCFCB0DA3566B2F8694E86A353E8C186ECCB9AA849 is
  1,304,106,936 bytes. Packaged core
  00721AA0501871D0E872056BEF3D2BB5CB73FF4F75677597BFF92602502159F8 is
  62,975,080 bytes and matches the APK entry.
- Thor result: none. No ADB query, install, launch, cache preparation, retry,
  or temperature read ran. Exact installed APK remains B5B5DB6B...B4074522.
- Visual correctness and FPS/frame-time: not exercised. This successor earns
  no startup-speed, FPS, temperature, flicker, field, menu, battle, gameplay,
  or stability credit until a later independently cool proof.
- Decision: retain / windows-pass / device-unmeasured. The code pre-materializes
  the exact same firmware PPU objects normal boot requested; it does not skip
  compilation, modules, guest work, or correctness checks.
- Next: after a separate independently cool interval, install the exact APK
  with the no-launch gate. In a later cool round, run Prepare Cache once while
  stopped and capture its activation/completion evidence. Only a still later
  cool round may run one self-stopping title proof; do not combine these into a
  heat-soak sequence.
### 2026-07-22 - firmware-ppu-prewarm-successor-install

- Status: installed-exact-no-launch
- Scope: route-tooling
- Hypothesis: the exact host-validated firmware-prewarm successor can be
  installed without launching RPCSX or materially heating the Thor, preserving
  a clean boundary before the later stopped-emulator cache-preparation round.
- Changed files/settings: no source, profile, firmware, or runtime cache was
  changed during validation. The strict-cool gate force-stopped RPCSX and the
  installer used adb install -r on exact APK 3B6ACA6D...C76404. The app was
  never launched.
- Rollback: reinstall the prior pinned B5B5DB6B...B4074522 APK with the same
  no-launch gate. No rollback is needed from this successful install.
- Host result: exact candidate artifact, ARM64-only ABI, optimized variant,
  pinned hashes, and no-launch installer contracts passed immediately before
  device contact.
- Thor result: pinned serial c3ca0370 passed the three-sample gate at
  33.1 -> 33.1 -> 32.5 C (maximum 33.1 C, rise -0.6 C), with battery/skin
  23.0/30.0 C. adb install -r returned Success. Expected, host, and installed
  base.apk SHA-256 all equal
  3B6ACA6D3E393197FFFB35D58FC6F7DAE947CEC35C6DA091DC20368478C76404.
  PID was absent before and after, no activity launched, and post-install
  battery/skin/silicon were 23.0/30.0/36.5 C.
- Visual correctness and FPS/frame-time: not exercised. Installation identity
  and bounded install temperature grant no speed, thermal-win, gameplay,
  flicker, or stability credit.
- Capture paths:
  debug-captures/android-speed-sprint/20260722-144216-thor-input-strict-cool-gate;
  debug-captures/android-speed-sprint/20260722-144228-firmware-ppu-prewarm-thortest-apk-install.
- Decision: installed-exact-no-launch / route-tooling. The successor is now
  frozen on-device and RPCSX is stopped.
- Next: stop this device round. After a different independently cool interval,
  run exactly one stopped-emulator Prepare Cache action for BLUS30161. Require
  the managed-profile/firmware activation row, successful completion, bounded
  thermals, and absent final PID. Reserve title launch for another later cool
  round; do not combine cache preparation and title proof.

### 2026-07-22 - deterministic-firmware-prewarm-route-successor

- Status: windows-pass
- Scope: route-tooling
- Hypothesis: a debug-only external cache-preparation action plus a
  self-stopping host controller can execute the existing firmware PPU prewarm
  deterministically without Compose navigation, game boot, or an unbounded hot
  process, making the next Thor cache round both reproducible and thermally
  fail-closed.
- Changed files/settings: MainActivity now accepts only exact action
  net.rpcsx.THOR_DEBUG_PREPARE_CACHE in Thor test builds. It requires a safe
  request ID, absolute game path, exact BLUS30161 title, explicit managed-profile
  requirement, active core, no concurrent preparation, and a successfully
  applied managed profile. It constructs a synthetic game record, never starts
  RPCSXActivity, consumes every matching rejection before Compose, and logs
  rejected, accepted, and callback-finished evidence. The native workload now
  carries title identity and logs completion only after ppu_precompile
  returns. tools/invoke_thor_cache_prepare.ps1 pins the candidate APK, serial,
  title, and legal local game path; hashes installed base.apk before preflight;
  requires three sub-35 C samples with no more than +1 C rise; confirms then
  stops on sustained 56 C, stops immediately at 68 C below the 72 C hard
  limit, caps runtime at 150 seconds, and requires ordered accepted/activated/
  completed/finished rows plus absent final PID. It contains no game-boot,
  custom-profile replacement, uninstall, clear-data, or monkey route.
- Rollback: remove maybeStartThorDebugCachePreparation, the workload title
  field/completion row, and the dedicated harness/contracts. The installed
  3B6ACA6D...C76404 APK is unchanged and does not include this successor.
- Host result: :app:compileThortestKotlin passed in 18.8 seconds. Optimized
  ARM64 RelWithDebInfo native compilation passed in 64.6 seconds, and explicit
  ARM64-only ThorTest packaging passed in 21.3 seconds. The focused route and
  firmware contracts, DEX/native artifact markers, optimized variant, ABI,
  35-export surface, exact packaged-core identity, and complete 66/66
  test_thor_*.ps1 suite pass. Host-only -Action Status reports no device
  contact and the exact 35/56/68/72 C guard policy.
- Artifact result: exact host-only APK
  1DCDBBEB01FFF2A3F04A40A8D503D9ECC3F6CBDD1BEFB9FDE97C8252826F4885
  is 72,831,772 bytes. Merged core
  A1BB2700458A21DC91903D43F1291ABA75D08C55CBAEDA480023D74496A9D728
  is 1,304,111,840 bytes. Packaged core
  34D0401E36ACEC7FC5E4B3D18D96AC42F0BF3CAA3A2795657053DD0AA8561A1F
  is 62,975,480 bytes and matches the APK entry exactly.
- Thor result: none. No ADB query, install, launch, temperature read, cache
  mutation, retry, or follow-up device action ran. Exact installed APK remains
  3B6ACA6D...C76404 and the prior device round remains closed.
- Visual correctness and FPS/frame-time: not exercised. This is route tooling,
  not a speed, temperature, FPS, flicker, field, menu, battle, gameplay, or
  stability result.
- Decision: retain / windows-pass / device-unmeasured / route-tooling. The
  successor makes the already-implemented prewarm safely invokable and proves
  completion ordering, but grants no performance credit until later device
  evidence exists.
- Next: after a genuinely independent cooldown, install exact APK
  1DCDBBEB...6F4885 through one strict no-launch round and stop. In a different
  later cool round, run exactly one invoke_thor_cache_prepare.ps1 -Action Run
  action and require exact identity, ordered completion evidence, bounded
  thermals, complete logs, and absent PID. Reserve title/field/menu/battle proof
  for still another cool round; never combine these steps into a heat soak.

### 2026-07-22 - deterministic-prewarm-route-exact-no-launch-install

- Status: installed-exact-no-launch
- Scope: route-tooling
- Hypothesis: exact deterministic-prewarm successor 1DCDBBEB...6F4885 can
  replace the previous installed APK under the strict cool gate without
  launching RPCSX, mutating cache/firmware/profile state, or leaving a process
  active.
- Changed files/settings: no source, profile, firmware, runtime cache, or
  experiment control changed. The strict gate and installer force-stopped
  RPCSX at both boundaries and used only adb install -r on the frozen ARM64
  ThorTest APK. No activity launch path ran.
- Rollback: reinstall exact prior APK 3B6ACA6D...C76404 through the same strict
  no-launch flow. No rollback is indicated because identity and stopped-state
  evidence passed.
- Host result: immediately before device contact, the candidate artifact,
  packaged native/DEX markers, strict gate, and no-launch installer contracts
  passed. Expected host APK SHA-256 was
  1DCDBBEB01FFF2A3F04A40A8D503D9ECC3F6CBDD1BEFB9FDE97C8252826F4885.
- Thor result: pinned serial c3ca0370 passed the three-sample gate at
  34.7 -> 32.7 -> 33.5 C (maximum 34.7 C, rise -1.2 C), with battery/skin
  23.0/30.0 C. adb install -r returned Success. Expected, host, and installed
  base.apk SHA-256 all equal
  1DCDBBEB01FFF2A3F04A40A8D503D9ECC3F6CBDD1BEFB9FDE97C8252826F4885.
  PID was absent before and after, no activity launched, and post-install
  battery/skin/silicon were 23.0/30.0/35.1 C. No retry or follow-up device
  action ran.
- Visual correctness and FPS/frame-time: not exercised. Installation identity
  and bounded temperature grant no speed, thermal-win, gameplay, flicker, or
  stability credit.
- Capture paths:
  debug-captures/android-speed-sprint/20260722-151931-thor-input-strict-cool-gate;
  debug-captures/android-speed-sprint/20260722-151943-bounded-firmware-prewarm-route-thortest-apk-install.
- Decision: installed-exact-no-launch / route-tooling. Exact successor is now
  frozen on-device and RPCSX is stopped.
- Next: stop this device round. After a different independently cool interval,
  run exactly one tools/invoke_thor_cache_prepare.ps1 -Action Run action.
  Require exact APK identity, accepted/activated/completed/finished ordering,
  complete logs, bounded thermals, no game boot, and absent final PID. Reserve
  title and gameplay proof for a still later cool round.

### 2026-07-22 - deterministic-prewarm-route-shell-quote-failure

- Status: failed
- Scope: route-tooling
- Hypothesis: the exact installed deterministic-prewarm successor can run one
  stopped-emulator firmware/PPU cache preparation after the strict cool gate,
  with ordered completion evidence and no game boot.
- Changed files/settings: the device attempt changed no profile, APK, core, or
  experiment control. After the failed command, the host harness was fixed to
  pass the game path through a POSIX single-quoted remote-shell literal,
  including apostrophe escaping. It now omits RPCSX.log when the current
  request ID never reaches app logcat, so an older remote log cannot be
  mistaken for current evidence.
- Rollback: revert ConvertTo-ThorRemoteShellLiteral and pass the raw GamePath
  argument again. Do not roll back: the capture directly proves that form is
  split and reparsed by the device shell.
- Host result: focused cache-route parsing/quoting/status checks pass, including
  spaces, parentheses, apostrophes, and newline rejection. All 66/66
  tools/test_thor_*.ps1 contracts pass. The correction is host tooling only;
  installed APK 1DCDBBEB...6F4885 needs no rebuild or reinstall.
- Thor result: capture 20260722-152936-firmware-ppu-prewarm matched installed
  base.apk SHA-256
  1DCDBBEB01FFF2A3F04A40A8D503D9ECC3F6CBDD1BEFB9FDE97C8252826F4885.
  The strict gate passed silicon 33.5 -> 32.7 -> 33.1 C (maximum 33.5 C,
  rise -0.4 C), battery/skin 23.0/30.0 C. The unquoted path then produced
  `/system/bin/sh: syntax error: unexpected '('`; MainActivity never started,
  runtime elapsed was zero seconds, accepted/activated/completed/finished were
  all false, PID was absent before and after, and post-stop silicon was 33.9 C.
  No retry or follow-up device action ran.
- Visual correctness and FPS/frame-time: not exercised. The route did not enter
  RPCSX, so this grants no cache, speed, thermal-win, gameplay, flicker, or
  stability credit. The pulled RPCSX.log is pre-existing and is explicitly not
  current-run evidence.
- Capture path:
  debug-captures/android-speed-sprint/20260722-152936-firmware-ppu-prewarm.
- Decision: failed / route-not-entered / thermally-safe. Retain the quoting fix
  and stale-log guard; exact successor remains installed with RPCSX stopped.
- Next: stop this device round. After another independently cool interval, run
  exactly one tools/invoke_thor_cache_prepare.ps1 -Action Run action. Require
  the quoted path in intent-start.txt, exact APK identity, ordered accepted /
  activated / completed / finished evidence, bounded thermals, no game boot,
  and absent final PID. Reserve title/gameplay proof for a still later round.

### 2026-07-22 - deterministic-prewarm-iso-root-timeout-and-successor

- Status: windows-pass / device-failed / successor-uninstalled
- Scope: route-tooling
- Hypothesis: the stopped-emulator prewarmer must resolve an ISO to that
  disc's exact EBOOT/PARAM.SFO/root before compiling; otherwise treating the
  ISO as a direct executable can broaden recursive scanning to the entire ROM
  collection and defeat the thermal/runtime bound.
- Changed files/settings: cache preparation now opens a selected ISO through
  the existing read-only iso_dev virtual filesystem, registers only its unique
  virtual prefix for the synchronous compile lifetime, resolves exactly
  PS3_GAME/USRDIR/EBOOT.BIN and PS3_GAME/PARAM.SFO, validates the requested
  title ID, and supplies PS3_GAME as the explicit scan root. Invalid ISO,
  EBOOT, PARAM.SFO, title, or root inputs fail closed. It does not mount or
  mutate the global /dev_bdvd VFS route. The host harness now treats accepted
  and callback-finished as logcat evidence while deriving native
  activated/completed markers from the pulled current RPCSX.log, where native
  logging actually writes them.
- Rollback: revert the prepare-only ISO resolver, explicit workload scan/SFO
  paths, current-native-log marker check, and candidate pin. Do not roll back:
  the bounded capture directly proves the old parent-directory behavior.
- Host result: all 66/66 test_thor_*.ps1 contracts pass. The focused route and
  host-only Status checks pass. The ARM64 RelWithDebInfo native build and
  ARM64-only :app:assembleThortest build pass. Exact successor APK
  BBAD241DB2BDA4510B7F8892DAEB1B8C9E51E010E6C43799E183537574550B89 is
  72,834,260 bytes. Merged core
  E1B05DC9AA985B575068A67BE129109D7FCE629FFE63586D31C55E4EABD499C6 is
  1,304,256,928 bytes. Packaged core
  83EB9B0762990BCC5BC4244D0452F75C6AEC3CE35DAF700F8734A59B7BC58B28 is
  62,984,088 bytes and matches the APK entry exactly.
- Thor result: capture
  debug-captures/android-speed-sprint/20260722-154128-firmware-ppu-prewarm
  matched installed APK 1DCDBBEB...6F4885 and passed preflight at
  33.7 -> 32.7 -> 33.3 C. MainActivity accepted the exact BLUS30161 request
  and native activation is present in the current RPCSX.log. The old native
  route then reported missing PARAM.SFO, tried to load the ISO as an
  executable, failed it, and scanned /storage/2664-21DE/Roms/ps3 plus firmware.
  At the 150.11-second hard bound it had reached file 68/142 and module 42/44;
  no native completion or callback-finished row exists. Silicon peaked at
  55.4 C, post-stop silicon was 38.6 C, battery/skin stayed 23.0/30.0 C, PID
  was absent at both boundaries, and no game boot occurred. No further device
  action ran after this capture.
- Visual correctness and FPS/frame-time: not exercised. The failed prewarm
  grants no startup-speed, FPS, temperature, flicker, field, menu, battle,
  gameplay, or stability credit. Partial firmware cache objects may exist,
  but cache preparation is not complete.
- Decision: retain-successor / wrong-input-root-counterproof /
  bounded-timeout / device-unmeasured-successor. Exact successor
  BBAD241D...550B89 is built and pinned but is not installed.
- Next: keep Thor idle. After a separate independently cool interval, install
  exact successor BBAD241D...550B89 through one strict no-launch round and
  stop. In another independently cool round, run one bounded cache preparation
  and require source=iso with a virtual PS3_GAME scan root, exact BLUS30161
  PARAM.SFO, native completion, callback-finished, bounded thermals, no game
  boot, and absent final PID. Reserve title/gameplay proof for a later round.

### 2026-07-22 - strict-cool-gate-host-stream-refusal

- Status: failed / route-tooling / no-install
- Scope: route-tooling
- Hypothesis: the exact ISO-root successor can be installed without launch
  immediately after one strict three-sample cool gate.
- Changed files/settings: the device gate changed no APK, profile, firmware,
  runtime cache, or game state. The host wrapper now suppresses the nested
  input macro's PowerShell information stream while requesting a
  machine-readable capture path, so an external child process emits exactly
  one success-stream path instead of a human Write-Host line plus the path.
  The strict-gate contract requires this information-stream suppression.
- Rollback: remove 6>$null from the nested input-macro call and its contract.
  Do not roll back: the saved host refusal demonstrates the duplicate external
  process output.
- Host result: exact candidate BBAD241D...550B89 and the no-launch install,
  strict-cool, candidate artifact, and host-only Status contracts passed before
  device contact. The corrected focused strict-cool contract and host-only
  Status pass afterward.
- Thor result: strict gate capture
  debug-captures/android-speed-sprint/20260722-160903-thor-input-strict-cool-gate
  passed at 32.7 -> 33.1 -> 32.9 C, maximum 33.1 C, rise +0.2 C, with
  battery/skin 23.0/30.0 C. Post-run silicon was 33.9 C. The outer host command
  then saw two stdout lines and refused before install_thor_apk_no_launch.ps1
  was invoked. No adb install or activity launch occurred, and no retry or
  follow-up device query ran.
- Visual correctness and FPS/frame-time: not exercised. This grants no cache,
  speed, temperature, FPS, flicker, field, menu, battle, gameplay, or stability
  credit.
- Decision: failed / host-output-parser / thermally-safe / no-install. Exact
  successor BBAD241D...550B89 remains uninstalled; installed APK logically
  remains 1DCDBBEB...6F4885 because the install script was never called.
- Next: stop this device round. After a separate independently cool interval,
  invoke the corrected strict gate and exact no-launch installer once, then
  stop. Reserve cache preparation and title/gameplay proof for two still later
  independently cool rounds.

### 2026-07-22 - bounded-iso-root-successor-exact-no-launch-install

- Status: installed-exact-no-launch
- Scope: route-tooling
- Hypothesis: exact bounded-ISO-root successor BBAD241D...550B89 can replace
  the old installed cache-preparation APK under the strict cool gate without
  launching RPCSX or changing firmware, cache, profile, or game state.
- Changed files/settings: no source, profile, firmware, runtime cache, or
  experiment control changed. The strict gate and installer force-stopped
  RPCSX at both boundaries and used only adb install -r on the frozen ARM64
  ThorTest APK. No activity launch path ran.
- Rollback: reinstall exact prior APK 1DCDBBEB...6F4885 through the same strict
  no-launch flow. No rollback is indicated because identity and stopped-state
  evidence passed.
- Host result: immediately before device contact, the strict-cool, no-launch
  installer, and candidate-artifact contracts passed. Exact host APK SHA-256
  BBAD241DB2BDA4510B7F8892DAEB1B8C9E51E010E6C43799E183537574550B89 and
  size 72,834,260 bytes matched the pinned candidate.
- Thor result: pinned serial c3ca0370 passed the three-sample gate at
  32.9 -> 32.9 -> 33.5 C (maximum 33.5 C, rise +0.6 C), with battery/skin
  23.0/30.0 C. adb install -r returned Success. Expected, host, and installed
  base.apk SHA-256 all equal
  BBAD241DB2BDA4510B7F8892DAEB1B8C9E51E010E6C43799E183537574550B89.
  PID was absent before and after, no activity launched, and post-install
  battery/skin/silicon were 23.0/30.0/35.1 C. No retry or follow-up device
  action ran.
- Visual correctness and FPS/frame-time: not exercised. Installation identity
  and bounded temperature grant no speed, thermal-win, gameplay, flicker, or
  stability credit.
- Capture paths:
  debug-captures/android-speed-sprint/20260722-162508-thor-input-strict-cool-gate;
  debug-captures/android-speed-sprint/20260722-162521-bounded-iso-root-successor-thortest-apk-install.
- Decision: installed-exact-no-launch / route-tooling. Exact successor is now
  frozen on-device and RPCSX is stopped.
- Next: stop this device round. After a different independently cool interval,
  run exactly one tools/invoke_thor_cache_prepare.ps1 -Action Run action.
  Require source=iso, a virtual PS3_GAME scan root, exact BLUS30161 PARAM.SFO,
  ordered native completion plus callback-finished evidence, bounded thermals,
  no game boot, and absent final PID. Reserve title and gameplay proof for a
  still later cool round.

### 2026-07-22 - bounded-iso-root-native-thread-crash-and-host-successor

- Status: device-failed / host-fixed / successor-uninstalled
- Scope: route-tooling and native stability
- Hypothesis: exact installed bounded-ISO-root successor BBAD241D...550B89
  can finish stopped-emulator BLUS30161 PPU/firmware cache preparation within
  the 150-second and thermal bounds without entering the game-boot path.
- Thor result: capture
  debug-captures/android-speed-sprint/20260722-164057-firmware-ppu-prewarm
  matched the exact installed APK and passed preflight at
  33.9 -> 32.9 -> 33.1 C. The ISO resolver then proved the exact
  PS3_GAME/PARAM.SFO/USRDIR/EBOOT.BIN root, and main PPU analysis completed
  with 12,082 functions and 154,267 blocks. Native compilation crashed at
  emulator time about 1.294 seconds in ppu_initialize before its first module
  compile. Silicon peaked at only 34.7 C, post-stop was 33.5 C,
  battery/skin stayed 23.0/30.0 C, no game boot occurred, and PID was absent
  after the controlled stop. The old harness did not recognize the dead
  process and therefore waited 152.49 host seconds before reporting timeout.
- Root cause: exact merged core E1B05DC9...99C6 symbolization maps the original
  0x20 read to thread_ctrl::set_name from PPUThread.cpp's caller-participation
  block. Cache preparation enters synchronously from the raw Kotlin/JNI
  RPCSX-PrepareCa thread, so thread_ctrl::get_current() is null and that
  foreign thread cannot be renamed as an RPCSX named_thread.
- Changed files/settings: PPU LLVM compilation now follows current upstream's
  full named-worker-pool design. The configured two compile lanes remain two
  active named workers; the foreign JNI caller only waits for the group and no
  longer executes thread_op or calls thread_ctrl::set_name. The cache harness
  also recognizes target-package libc fatal-signal and ActivityManager
  process-death rows, fails within the next logcat poll, records the death in
  README.md, force-stops, and retains final PID/thermal evidence. No device,
  profile, firmware, cache, or game state changed during the host repair.
- Rollback: restore current-thread participation and remove the process-health
  helper. Do not roll back: the saved symbolized crash proves the caller
  violates thread_ctrl::set_name's named-thread precondition, while current
  upstream already keeps compilation entirely inside named_thread_group.
- Host result: focused cache-route and firmware tests pass; the process-health
  helper also matches both target-death rows in the saved failing logcat. All
  66/66 test_thor_*.ps1 contracts pass. Optimized ARM64 native compilation
  passed in
  69.8 seconds; ARM64-only ThorTest packaging passed in 28 seconds. The ABI,
  optimized variant, exact artifact, packaged-core identity, and 35-export
  surface gates pass.
- Artifact result: exact host-only APK
  95DF7F6CAEDC70762AECAD7620ECBBB6CA515B286FBF05B88870A17CCEED6D36
  is 72,834,216 bytes. Merged core
  15353CF12FCA6BA99902646732236E807910639BC25244063F6BE9C29F7E6996
  is 1,304,250,032 bytes. Packaged core
  32B0BD6D8B75308B18BD940EFB31036FDAAD1F786EFA559E34C82310E804A0E2
  is 62,983,368 bytes and matches the APK entry exactly.
- Visual correctness and FPS/frame-time: not exercised. The crash invalidates
  cache completion and the successor is host-only, so this grants no startup
  speed, FPS, temperature-win, flicker, field, menu, battle, gameplay, or
  stability credit.
- Decision: failed / host-fixed / successor-uninstalled / not-comparable. The
  ISO-root fix is proven, the raw-thread crash has a build-verified repair, and
  the harness no longer burns the full runtime bound after a native death.
- Next: keep Thor idle. In one later independently cool round, install exact
  APK 95DF7F6C...ED6D36 through the strict no-launch gate and stop. In a
  different later cool round, run one bounded cache preparation and require
  source=iso, named PPU workers, native completion, callback-finished, bounded
  thermals, no game boot, and absent final PID. Reserve title/field/menu/battle
  correctness and speed proof for still later cool rounds.

### 2026-07-22 - named-worker-cache-successor-exact-no-launch-install

- Status: installed-exact-no-launch
- Scope: route-tooling and native-stability candidate identity
- Hypothesis: exact named-worker cache successor 95DF7F6C...ED6D36 can
  replace the crashing installed APK under the strict cool gate without
  launching RPCSX or changing firmware, cache, profile, or game state.
- Changed files/settings: no source, profile, firmware, runtime cache, or
  experiment control changed. The strict gate and installer force-stopped
  RPCSX at both boundaries and used only adb install -r on the frozen ARM64
  ThorTest APK. No activity launch or cache-preparation path ran.
- Rollback: reinstall exact prior APK BBAD241D...550B89 through the same strict
  no-launch flow. No rollback is indicated because exact identity and stopped
  state passed; the prior APK contains the proven raw-thread crash.
- Host result: strict-cool, no-launch installer, candidate artifact, ABI,
  optimized variant, and exact packaged-core gates passed before contact.
  Expected APK SHA-256 was
  95DF7F6CAEDC70762AECAD7620ECBBB6CA515B286FBF05B88870A17CCEED6D36.
- Thor result: pinned serial c3ca0370 passed the three-sample gate at
  33.1 -> 33.3 -> 33.1 C (maximum 33.3 C, rise 0.0 C), with battery/skin
  23.0/30.0 C. adb install -r returned Success. Expected, host, and installed
  base.apk SHA-256 all equal
  95DF7F6CAEDC70762AECAD7620ECBBB6CA515B286FBF05B88870A17CCEED6D36.
  PID was absent before and after, no activity launched, and post-install
  battery/skin/silicon were 23.0/30.0/35.3 C. No retry or follow-up device
  query ran.
- Capture paths:
  debug-captures/android-speed-sprint/20260722-170704-thor-input-strict-cool-gate;
  debug-captures/android-speed-sprint/20260722-170716-named-worker-cache-successor-thortest-apk-install.
- Visual correctness and FPS/frame-time: not exercised. Installation grants
  exact candidate identity only, with no speed, temperature-win, FPS, flicker,
  field, menu, battle, gameplay, cache-completion, or stability credit.
- Decision: installed-exact-no-launch / route-tooling. Exact successor is now
  frozen on-device and RPCSX is stopped.
- Next: stop this device round. After a different independently cool interval,
  run exactly one tools/invoke_thor_cache_prepare.ps1 -Action Run action and
  require source=iso, named PPU workers, native completion,
  callback-finished, bounded thermals, no game boot, and absent final PID.
  Reserve title and gameplay correctness/speed proof for later cool rounds.

### 2026-07-22 - named-worker-cache-preparation-progress

- Status: stable-native-thread-fix / bounded-progress / not-comparable
- Scope: native stability and stopped-emulator cache preparation
- Hypothesis: exact installed named-worker successor 95DF7F6C...ED6D36 can
  compile BLUS30161 PPU cache objects without the raw JNI caller crash while
  preserving exact source, affinity, stopped-process, and thermal bounds.
- Thor result: capture
  debug-captures/android-speed-sprint/20260722-172750-firmware-ppu-prewarm
  matched the exact installed APK. Preflight silicon was
  32.1 -> 31.9 -> 31.9 C. The exact ISO, virtual PS3_GAME root, EBOOT,
  PARAM.SFO, and BLUS30161 title resolved; native preparation activated; and
  named PPU workers reported requested=0x7,effective=0x7 affinity. The process
  remained alive in PPU LLVM work instead of crashing at about 1.294 seconds.
  Sixteen modules compiled and progress reached 16/41 before the 150-second
  bound; 18 module jobs had started. Runtime was 152.514 seconds, peak silicon
  was 55.4 C, average runtime silicon was 40.77 C, and post-stop silicon was
  36.1 C. Native completion and callback-finished were absent, PID was absent
  at both boundaries, and no fatal or game-boot evidence exists. No retry or
  follow-up device action ran.
- Visual correctness and FPS/frame-time: not exercised. The capture proves
  the raw-thread crash is fixed and cache work progresses, but it does not
  prove complete cache preparation, faster startup, higher FPS, lower
  gameplay temperature, field/menu/battle correctness, or flicker removal.
- Decision: retain named-worker design / clean resumable progress /
  bounded-timeout / not-comparable. Grant native-stability credit only.

### 2026-07-22 - upstream-named-thread-fix-and-resumable-successor

- Status: host-pass / successor-uninstalled
- Scope: native worker correctness and thermally bounded cache continuation
- Root cause: the vendored named_thread_group constructor predates upstream
  RPCS3 commit d8710c431d88ff59bc73f21bc7c3453ebe460151. Its final-context
  check used m_count - 1, which underflows for a one-thread group, and its
  thread slot/name arithmetic duplicates an earlier worker for larger groups.
  The saved run's PPUW.1.1-only tags exposed the naming defect even though
  overlapping compilations prove both configured lanes ran.
- Changed files/settings: port the upstream constructor fix exactly. Only
  named PPU compile workers enter the affinity scope; the foreign JNI caller
  waits. Cache preparation now defaults to a 90-second checkpoint and accepts
  timeout as a clean checkpoint only with exact ISO source, exact named-worker
  affinity, measurable compiled progress, no completion/callback, no process
  death or native fatal, no game boot, and an absent final PID. All other
  failures remain fail-closed. JITLLVM writes completed cache objects through
  fs::pending_file and commit(), so a controlled stop preserves completed
  objects without exposing a half-written final object.
- Host result: focused route, progress/fatal classifier, firmware, constructor,
  atomic-write, host-only Status, ABI, optimized-variant, artifact-identity,
  packaged-core, and export-surface checks pass. The optimized ARM64 native
  build and ARM64-only ThorTest APK build pass. Exact host-only successor APK
  A7216402BDBFE9F14762D9C2C2F2E5A2B857D828D327E2D9A6E50C8C6433D15C
  is 72,834,080 bytes. Merged core
  36B6B7110BD07B7983E0339D93B64BB714B44E4592B52107B8036945B9C22797
  is 1,304,242,880 bytes. Packaged core
  0AB29DC734CC3444D5A6F1976281703A25A3137C385535D4CD90A62B6033B9E3
  is 62,983,352 bytes and matches the APK entry exactly.
- Thor result: successor A7216402...3D15C is host-only and uninstalled. The
  device still has exact 95DF7F6C...ED6D36 stopped. No device contact occurred
  while building, validating, or documenting this successor.
- Decision: retain / host-pass / successor-uninstalled / no measured speed.
  In a later independently cool round, install only the exact successor under
  the strict no-launch gate and stop. In a different cool round, run one
  90-second checkpoint. Require full cache completion before separate
  title/field/menu/battle correctness and matched speed/thermal proofs.

### 2026-07-22 - resumable-cache-successor-exact-no-launch-install

- Status: installed-exact-no-launch
- Scope: native-stability candidate identity
- Hypothesis: exact upstream-constructor/resumable-cache successor
  A7216402...3D15C can replace the prior installed APK under the strict cool
  gate without launching RPCSX or changing firmware, runtime cache, profile,
  or game state.
- Changed files/settings: no source, profile, firmware, runtime cache, or
  experiment control changed. The strict gate and installer force-stopped
  RPCSX at both boundaries and used only adb install -r on the frozen ARM64
  ThorTest APK. No activity launch or cache-preparation path ran.
- Host result: exact candidate artifact contract passed immediately before
  device contact. Expected APK SHA-256 was
  A7216402BDBFE9F14762D9C2C2F2E5A2B857D828D327E2D9A6E50C8C6433D15C,
  size 72,834,080 bytes.
- Thor result: pinned serial c3ca0370 passed the three-sample strict gate at
  30.5 -> 30.9 -> 31.5 C (maximum 31.5 C, rise +1.0 C), with battery/skin
  23.0/30.0 C. adb install -r returned success. Expected, host, and installed
  base.apk SHA-256 all equal A7216402...3D15C. PID was absent before and
  after, no activity launched, and post-install battery/skin/silicon were
  23.0/30.0/33.5 C. No retry or follow-up device action ran.
- Capture paths:
  debug-captures/android-speed-sprint/20260722-180609-thor-input-strict-cool-gate;
  debug-captures/android-speed-sprint/20260722-180621-upstream-named-thread-resumable-cache-successor-thortest-apk-install.
- Visual correctness and FPS/frame-time: not exercised. Installation identity
  and bounded temperature grant no cache, speed, thermal-win, gameplay,
  flicker, or runtime-stability credit.
- Decision: installed-exact-no-launch / route-tooling. Exact successor is now
  frozen on-device and RPCSX is stopped. After a separate independently cool
  interval, run one 90-second cache checkpoint. Reserve title/field/menu/
  battle correctness and matched speed/thermal proof for later cool rounds.

### 2026-07-22 - resumable-cache-runtime-proof-tightening

- Status: host-pass / installed-successor-unchanged
- Scope: cache reuse, named-worker throughput, and fail-closed proof
- Changed files/settings: the host parser now extracts distinct PPUW worker
  names and whether the run loaded existing PPU objects. A timed-out checkpoint
  is accepted only with at least two distinct compile workers, at least one
  loaded object, at least one newly compiled object, exact source/affinity,
  no fatal/process death/game boot, and absent final PID. Full native and
  callback completion still bypass timeout classification normally.
- Replay result: saved first-run capture 20260722-172750 reports 16 compiled,
  zero loaded, and only worker name PPUW.1.1. It therefore remains the
  pre-upstream-fix first population run and cannot be relabeled as a resumable
  successor checkpoint. The next run must prove both PPUW.1.1/PPUW.1.2-style
  distinct lanes and reuse of the 16 atomically committed objects.
- Upstream audit: current local upstream's later ARM64 SPU LLVM recovery
  commit a87d17529 is a large retry/recovery backport for rare TBL2 register
  scavenger failures, not evidence for this measured PPU-cache bottleneck.
  The small 2f9f79eea PPU correctness fixes are likewise unrelated to the
  observed cache path. Neither is stacked before the installed successor's
  proof, preserving attribution and avoiding another rebuild/install cycle.
- Host result: focused cache-route/firmware contracts and all 66/66 Thor host
  contracts pass; Status is device-free and exposes the two-worker and
  validated cache-reuse requirements. Exact installed APK A7216402...3D15C is
  unchanged.
- Thor result: none. No ADB query, launch, cache action, or thermal read ran
  after the no-launch installation round.
- Decision: retain proof tightening / no speed credit. After a separate
  independent cooldown, run one 90-second checkpoint and stop regardless of
  result. Require full cache completion before title/gameplay measurements.

### 2026-07-22 - two-worker-resumable-cache-checkpoint

- Status: cache-progress-checkpoint / native-worker-correctness /
  thermal-progress / not-comparable
- Scope: stopped-emulator PPU cache reuse and bounded continuation
- Thor result: exact installed APK A7216402...3D15C passed strict preflight at
  30.9 -> 30.7 -> 30.9 C, exact ISO/root/title resolution, managed two-worker
  activation, and exact requested/effective affinity 0x7. Distinct worker names
  PPUW.1.1 and PPUW.1.2 prove the upstream named-thread constructor fix on the
  device. Sixteen prior objects were validated as LLVM: Module exists; ten new
  objects compiled and progress reached 10/25, leaving 15 modules for a later
  continuation. The 89.7-second runtime averaged 38.10 C, peaked at 40.2 C, had
  zero samples at or above 50 C, and ended at 39.4 C; post-stop was 34.9 C. No
  native fatal, process death, callback completion, game boot, or residual PID
  occurred. Capture:
  debug-captures/android-speed-sprint/20260722-183628-firmware-ppu-prewarm.
- Host false-negative and fix: the live harness rejected the timeout because it
  required Loaded module reuse. Stopped-emulator PPU preparation validates and
  skips durable objects through LLVM: Module exists before building its remaining
  workload, so it never emits the title-boot Loaded module row. The parser now
  counts both forms as reuse, reports existing/reused counts, and the route
  contract uses an exact Module exists fixture. Local replay of this capture is
  reuse=16, compiled=10, workers=2, latest=10/25 and satisfies the corrected
  checkpoint contract. Exact APK/core bytes are unchanged.
- Decision: retain the installed successor and corrected host proof. This is a
  clean, cool cache-progress checkpoint and native worker correctness proof, not
  an FPS, startup-speed, gameplay, flicker, or controlled thermal win. No retry
  or follow-up ADB action ran. After another independent cooldown, run at most one
  more 90-second checkpoint; require full native/callback completion before title,
  field, menu, and first-battle measurements.

### 2026-07-22 - second-resumable-cache-checkpoint

- Status: cache-progress-checkpoint / thermal-progress / not-comparable
- Scope: stopped-emulator PPU cache reuse and bounded continuation
- Thor result: exact installed APK A7216402...3D15C passed strict preflight at
  31.5 -> 31.3 -> 31.1 C, exact ISO/root/title resolution, two distinct PPUW
  workers, and exact requested/effective affinity 0x7. All 26 durable objects
  from the preceding rounds validated as LLVM: Module exists; ten new objects
  compiled and progress reached 10/15, leaving five modules. The 90-second
  runtime averaged 37.84 C and peaked at 39.0 C; post-stop was 35.5 C. No
  native fatal, process death, callback completion, game boot, or residual PID
  occurred. Capture:
  debug-captures/android-speed-sprint/20260722-190850-firmware-ppu-prewarm.
- Decision: retain the exact installed successor and completed objects. This is
  a second clean cache-progress checkpoint, not startup-speed, FPS, gameplay,
  flicker, stability, or controlled thermal-win evidence. No retry or follow-up
  ADB action ran. Do not contact Thor again in this round. After a separate
  independent cooldown, run one final 90-second checkpoint and require full
  native completion plus callback-finished before attempting the separately
  cooled title proof.

### 2026-07-22 - title-timing-proof-hardening

- Status: host-pass / device-unchanged
- Scope: auditable title-startup baseline and launcher rejection
- Changed files/settings: the cool-title analyzer now parses the first valid
  title frame, the second consecutive stable title frame, and their elapsed
  window from ppu-ready-gate.log. Comparison-ready status requires both exact
  timings and current image-replay title validity. Invalid or unstable visuals
  clear the timing fields so an old launcher-classifier row cannot become a
  startup claim.
- Host result: the synthetic ready fixture reports first=1200 ms, stable=6500
  ms, and window=5300 ms. Removing elapsed timing produces
  proof-sequence-incomplete, while replay of saved capture
  20260720-104152-thor-input-custom remains launcher-ui-instead-of-title with
  null timings. The focused analyzer/profile checks and all 66/66 Thor host
  contracts pass.
- Thor result: none. No ADB query, thermal read, launch, cache action, or other
  device contact occurred. Exact installed APK A7216402...3D15C and its core
  remain frozen.
- Decision: retain. This improves startup measurement fidelity but grants no
  speed, FPS, gameplay, flicker, stability, or thermal-win credit. After an
  independent cooldown, finish the five remaining cache modules; reserve the
  separately cooled title proof as the first valid startup baseline.

### 2026-07-22 - third-cache-checkpoint-and-phase-aware-progress

- Status: cache-progress-checkpoint / initial-eboot-complete /
  firmware-scan-progress / thermal-progress / not-comparable
- Scope: stopped-emulator title-cache completion, firmware scan continuation,
  and truthful bounded-progress reporting
- Thor result: exact installed APK A7216402...3D15C passed strict preflight at
  30.7 -> 30.7 -> 30.7 C, exact ISO/root/title resolution, requested/effective
  affinity 0x7, and six distinct named PPUW worker instances across successive
  title and firmware work groups. All five modules in the initial EBOOT
  workload compiled by emulator time 62.05 s. The route then scanned firmware
  through file 70 of 142 and completed 8 of the 11 modules discovered so far;
  three known modules remained, with two libhttp objects in flight at the
  bounded stop. In total the run validated/reused 114 durable objects and
  compiled eight new objects. Twenty-five runtime thermal samples averaged
  37.416 C, ranged from 35.1 to 48.6 C, included one sample at or above 45 C
  and zero at or above 50 C, and fell to 33.7 C post-stop. Logcat contains no
  target fatal signal, FATAL EXCEPTION, ANR, crash, or VK_ERROR_DEVICE_LOST;
  the controller's final force-stop left PID absent and no game boot occurred.
  Capture:
  debug-captures/android-speed-sprint/20260722-194141-firmware-ppu-prewarm.
- Host diagnosis: the previous progress regex accepted only `Progress: module`
  rows. On final EBOOT completion RPCSX immediately switches to
  `Progress: file ..., module 5 of 5`, so the parser ignored the completion row
  and reported stale 4/5 with one remaining. Later firmware rows were likewise
  invisible, hiding that the module total grows as additional SPRX files are
  scanned.
- Host fix and replay: the parser now accepts both progress forms, separately
  reports initial EBOOT completion, firmware file position, and the latest
  discovered module count, and labels remaining modules as known rather than
  final. The exact saved log replays as EBOOT 5/5 complete, firmware file
  70/142, discovered modules 8/11, and three known remaining. A fixture locks
  this phase transition, and the focused cache-preparation route contract
  passes. This is host-only tooling; APK and core bytes remain frozen.
- Decision: retain the completed cache objects and corrected proof tooling.
  This checkpoint proves bounded cache progress and initial EBOOT completion,
  not startup speed, FPS, gameplay correctness, flicker removal, sustained
  stability, or a controlled thermal win. No retry or follow-up ADB action ran
  in this round. After a separate independent cooldown, run at most one more
  bounded checkpoint and stop; repeat across later cool rounds until native
  completion plus callback-finished is captured, then reserve a different cool
  round for the first auditable title baseline.

### 2026-07-22 - cache-prewarm-thermal-ceiling-tightening

- Status: host-pass / device-unchanged
- Scope: resumable cache-preparation thermal safety
- Rationale: cache objects are atomically committed and resumable, so the
  stopped-emulator prewarm gains nothing from approaching the generic runtime
  `68/72 C` stop/hard limits. A cooler early stop preserves completed work and
  moves unfinished compilation to a later independent round.
- Changed files/settings: the cache-only controller now takes an immediate
  confirmation sample at `50 C`, stops if that level persists, stops directly
  at `55 C`, and retains a `60 C` hard ceiling. The strict below-`35 C`
  three-sample launch gate, maximum `+1 C` preflight trend, 90-second bound,
  exact APK/title/source checks, no-game-boot route, forced stop, and final PID
  absence remain unchanged.
- Host result: device-free Status reports probe/stop/hard thresholds
  `50/55/60 C`, and the focused cache-preparation contract passes. Exact frozen
  APK A7216402...3D15C and core bytes are unchanged; no ADB query, temperature
  read, launch, or cache mutation occurred.
- Decision: retain as safety hardening. It grants no speed, FPS, gameplay,
  flicker, stability, or measured thermal-win credit. Use only after a fresh
  independent cooldown for one bounded continuation, then stop regardless of
  completion or thermal result.

### 2026-07-22 - fourth-cache-checkpoint-and-warm-phase-accounting

- Status: cache-progress-checkpoint / warm-eboot-complete /
  firmware-scan-progress / thermal-progress / not-comparable
- Scope: stopped-emulator firmware cache continuation and truthful warm-EBOOT
  phase reporting
- Thor result: exact installed APK A7216402...3D15C passed strict preflight at
  `30.5 -> 29.9 -> 30.3 C`, exact ISO/root/title resolution, requested/effective
  affinity `0x7`, and 18 distinct named PPUW worker instances across successive
  firmware work groups. The already-complete EBOOT phase returned without a
  standalone module-progress row. Firmware scanning resumed through file
  `83/142` and reached `16/21` discovered modules, leaving five known modules
  in the scanned workload and 59 files still to enumerate. The run reused 122
  validated objects and compiled 16 new objects. Twenty-six runtime thermal
  samples averaged `38.10 C`, ranged from `35.5` to `49.4 C`, included one
  sample at or above `45 C`, and had zero samples at or above the new `50 C`
  confirmation threshold. Post-stop silicon was `34.5 C`.
- Health result: the request was accepted and native preparation activated.
  Native completion and callback-finished remain absent. Saved log replay has
  no target native fatal, process death, FATAL EXCEPTION, ANR,
  `VK_ERROR_DEVICE_LOST`, game boot, or residual PID. The only broad-text
  `crash` match is the ordinary exported firmware module name
  `sys_crashdump`, not a process-health event. No retry or follow-up device
  command ran.
- Host diagnosis and fix: when all EBOOT objects are warm, `ppu_initialize()`
  emits no `Progress: module` row and firmware enumeration begins directly at
  `Progress: file ..., module 0 of 1`. Those counters belong to the growing
  SPRX scan. The old phase-aware parser incorrectly reported EBOOT `0/1` and
  incomplete. It now derives EBOOT numeric progress only from non-file rows,
  treats entry into firmware enumeration as proof that the preceding EBOOT
  phase returned successfully, and reports the no-row case explicitly. A warm
  fixture locks `file 83/142, module 16/21` without inventing EBOOT counters;
  replay of the preceding checkpoint remains EBOOT `5/5` complete.
- Visual correctness and FPS/frame-time: not exercised. This is durable cache
  progress under the tighter controller, not startup-speed, FPS, gameplay,
  flicker, sustained-stability, or controlled thermal-win evidence.
- Decision: retain the exact installed successor and newly committed objects.
  Do not contact Thor again in this round. After another independent cooldown,
  run at most one bounded cache continuation. Require native completion plus
  callback-finished before a separately cooled auditable title baseline, then
  field/menu/first-battle correctness and matched performance/thermal proof.

### 2026-07-22 - cache-checkpoint-thermal-summary-hardening

- Status: host-pass / device-unchanged
- Scope: durable near-limit thermal accounting for resumable cache rounds
- Changed files/settings: the cache controller retains every valid runtime
  silicon sample, including an immediate confirmation sample, and writes the
  count, average, minimum, peak, count at/above `45 C`, and count at/above the
  dynamic `50 C` probe threshold into each capture README. Empty or
  preflight-refused runs return a deterministic zero/null summary instead of
  inventing measurements.
- Host result: the pure summary fixture proves average/minimum/maximum and both
  inclusive threshold counts; replay of capture 20260722-201353 produces
  `26` samples, average `38.10 C`, minimum `35.5 C`, maximum `49.4 C`, one
  sample at/above `45 C`, and zero at/above `50 C`. The focused route,
  PowerShell AST, and full Thor host suite pass.
- Thor result: none after the preceding checkpoint. No ADB query, temperature
  read, launch, cache action, or other device contact occurred. Frozen APK and
  core identity remain unchanged.
- Decision: retain as safety/evidence hardening. It grants no startup-speed,
  FPS, gameplay, flicker, stability, or measured thermal-win credit. Use the
  richer capture summary only in a later independently cool cache round.

### 2026-07-22 - cache-independent-cooldown-gate

- Status: host-pass / device-unchanged
- Scope: prevent accidental rapid cache retries even when instantaneous
  temperature has already fallen
- Changed files/settings: before resolving ADB, the cache controller finds the
  latest timestamped `firmware-ppu-prewarm` capture, parses its durable README
  completion time, and requires a full 30-minute interval. Missing or malformed
  latest README evidence fails closed. Device-free Status exposes the latest
  capture, completed/ready timestamps, readiness, and remaining seconds. The
  existing three-sample below-`35 C` thermal gate still runs independently
  after the time gate passes.
- Host result: deterministic fixtures prove the waiting boundary, the exact
  ready boundary, no-history behavior, and integer remaining seconds. Source
  order requires the refusal gate before `Resolve-ThorAdb`. Live device-free
  Status found checkpoint 20260722-201353 completed at
  `20:15:42.0340706-04:00`, ready at `20:45:42.0340706-04:00`, and correctly
  reported not-ready during the interval. The focused route and full Thor host
  suite pass.
- Thor result: none after the preceding checkpoint. Status is explicitly
  device-free; no ADB query, thermal read, launch, or cache action occurred.
- Decision: retain. This is a safety invariant, not speed, FPS, gameplay,
  flicker, stability, or thermal-win evidence. A later Run must pass both the
  time gate and the fresh three-sample temperature gate.

### 2026-07-22 - fifth-cache-checkpoint

- Status: cache-progress-checkpoint / warm-eboot-complete /
  firmware-scan-progress / thermal-progress / not-comparable
- Scope: stopped-emulator firmware cache continuation under enforced time and
  temperature gates
- Thor result: the host time crossed the exact prior ready boundary at
  `20:45:42.548-04:00`; the controller then independently passed exact
  installed APK A7216402...3D15C, ISO/root/title, requested/effective affinity
  `0x7`, and strict preflight `30.9 -> 30.9 -> 30.5 C`. The warm EBOOT phase
  returned without standalone compile progress. Firmware scanning advanced to
  file `92/142`; the current growing workload reached `15/19`, leaving four
  known modules and 50 files still to enumerate. The run reused 138 validated
  objects and compiled 15 new objects, exactly continuing from the prior
  round's 122 reused plus 16 compiled objects.
- Thermal result: the new durable summary recorded 25 runtime samples,
  average `38.3 C`, minimum `35.1 C`, peak `48.2 C`, two samples at/above
  `45 C`, zero at/above the `50 C` confirmation threshold, and post-stop
  silicon `34.3 C`. No thermal guard fired.
- Health result: request acceptance and native activation passed. Native
  completion and callback-finished remain absent. Saved log replay has no
  target native fatal, process death, FATAL EXCEPTION, ANR,
  `VK_ERROR_DEVICE_LOST`, game boot, or residual PID. No retry or follow-up
  device command ran.
- Progress interpretation: firmware module totals are reconstructed per run
  while additional files are discovered and already cached modules are skipped;
  therefore prior `16/21` versus current `15/19` is not regression or a
  cumulative counter. Durable continuity is proven by reuse rising `122 -> 138`
  and firmware file position rising `83 -> 92` while new objects compile.
- Visual correctness and FPS/frame-time: not exercised. This is bounded cache
  progress, not startup-speed, FPS, gameplay, flicker, sustained-stability, or
  controlled thermal-win evidence.
- Decision: retain the frozen installed candidate and completed objects. No
  more Thor contact before the new capture's 30-minute gate passes. Continue
  one bounded round at a time until native completion plus callback-finished,
  then reserve a separate cool round for title and later field/menu/battle
  correctness, performance, flicker, stability, and thermal proof.

### 2026-07-22 - sixth-cache-round-thermal-stop

- Status: thermal-stop-with-durable-cache-progress / safety-pass /
  firmware-scan-progress / not-comparable
- Thor result: capture `20260722-211758-firmware-ppu-prewarm` passed exact
  installed APK A7216402...3D15C, ISO/root/title, requested/effective affinity
  `0x7`, and strict preflight `31.3 -> 31.5 -> 30.1 C`. It reused 153
  validated objects, compiled 16 new objects, and advanced the firmware scan
  from file `92/142` to `104/142`; the current discovered workload reached
  `16/18`, leaving two known modules and 38 files still to enumerate.
- Thermal result: the controller ran for `77.817 s`. Twenty-two runtime samples
  averaged `38.2 C`, minimum `35.9 C`, and stayed at or below `39.0 C` through
  sample 21. Sample 22 rose to `55.4 C`, so the controller immediately
  force-stopped at the `55 C` early threshold below the `60 C` hard ceiling.
  Post-stop silicon was `35.5 C`; battery/skin were `22.0/30.0 C`.
- Health result: request acceptance, native activation, exact source, and named
  workers passed. Native completion and callback-finished remain absent. The
  saved capture reports no native fatal, process death, FATAL EXCEPTION, ANR,
  game boot, or residual PID. No follow-up ADB query or retry ran.
- Progress interpretation: the controller correctly classifies the thermal
  stop as failed rather than a normal checkpoint. Atomic object writes mean the
  16 completed modules should remain reusable, but the next independently cool
  run must prove continuity by reusing at least 169 objects before granting
  durable-progress credit for this stopped round.
- Visual correctness and FPS/frame-time: not exercised. This safety stop is not
  startup-speed, FPS, gameplay, flicker, sustained-stability, or thermal-win
  evidence.
- Decision: keep Thor stopped and do not contact it again before both the new
  30-minute interval (ready no earlier than `2026-07-22T21:49:31.1302428-04:00`)
  and a fresh strict cool gate pass. Continue with one bounded cache round only;
  require native completion plus callback-finished before the separately cooled
  title and field/menu/battle proof.

### 2026-07-22 - post-thermal-stop-cache-bound-tightening

- Status: host-safety-hardening / no-device-contact / not-comparable
- Saved-trace basis: the latest `55.4 C` sample arrived about `76.3 s` after
  its first runtime sample; the earlier `20260722-172750` spike arrived about
  `73.3 s` after its first sample. In the latest native log, eleven new objects
  were already atomically committed by emulator time `68.587 s`, while the
  next compile burst began at `73.992 s` and continued through `79.818 s`.
- Host change: stopped-emulator cache preparation now defaults to `70 s`
  rather than `90 s`. After every thermal decision it checks the elapsed bound
  before pulling logcat, and its final poll sleep is capped to the exact
  remaining milliseconds. The native/APK/cache identity and two-worker
  `0x07` compile contract are unchanged.
- Verification: the focused cache-route and thermal-guard contracts pass;
  host-only Status reports `max_seconds=70`, `device_contact=False`, and the
  candidate artifact gate still proves APK `A7216402...3D15C`, merged core
  `36B6B711...22797`, and packaged core `0AB29DC7...B9E3` exactly.
- Decision: no Thor contact occurred. This is a conservative safety change,
  not startup-speed, FPS, gameplay, flicker, stability, or thermal-win proof.
  After the independent cooldown, allow only one new 70-second round under the
  unchanged strict cool gate and require reuse of at least 169 objects before
  crediting the stopped round's 16 atomic writes.

### 2026-07-22 - thermal-stop-reuse-floor

- Status: host-evidence-hardening / no-device-contact / not-comparable
- The cache controller now derives a reuse floor from the latest failed
  thermal-stop README. Exact latest evidence `reused=153` plus `compiled=16`
  produces `minimum_required_reused_modules=169` in device-free Status.
- A clean bounded timeout can become `cache-progress-checkpoint` only when the
  current capture reuses at least that floor in addition to the existing
  source, worker, progress, health, thermal, game-boot, and final-PID gates.
  Full native/callback completion remains independently acceptable.
- Verification: focused fixtures prove floor `169`, reset to baseline `1`
  after a normal checkpoint, and reject malformed thermal-stop continuity
  evidence. The cache route contract passes and Status remains
  `device_contact=False`.
- Decision: no Thor contact occurred and exact APK/core/cache bytes are
  unchanged. This prevents false durable-progress credit; it is not speed,
  FPS, gameplay, flicker, stability, or thermal-win evidence.

### 2026-07-22 - recent-log-poll-and-seventh-cache-checkpoint

- Status: cache-progress-checkpoint / continuity-pass / safety-pass /
  firmware-scan-progress / not-comparable
- Scope: lower-overhead bounded cache polling plus one independently cooled
  stopped-emulator continuation
- Hypothesis and host change: repeated full-buffer `adb logcat -d` reads grow
  with the run and are unnecessary for the live health loop. Runtime polling
  now reads only the newest 500 threadtime rows, latches accepted/finished
  markers once observed, and still pulls and saves the complete final logcat
  after force-stop. Rollback is `Read-FreshLogcat` in the polling loop; native,
  APK, cache, thermal, and no-game-boot behavior are unchanged. The focused
  cache route, thermal guard, and frozen candidate artifact contracts pass.
- Thor result: after device-free Status proved the 30-minute interval complete,
  exact installed APK A7216402...3D15C and the strict gate passed at
  `30.9 -> 30.1 -> 30.3 C`. Capture
  `20260722-215019-firmware-ppu-prewarm` reused exactly 169 validated objects,
  satisfying the required continuity floor from the preceding thermal stop,
  and compiled 16 new objects. Firmware scanning advanced from file `104/142`
  to `118/142`; the current discovered workload reached `16/18`, leaving two
  known modules and 24 files still to enumerate.
- Thermal result: the 70.024-second bounded runtime produced 20 samples with
  average `38.0 C`, minimum `35.9 C`, peak `48.2 C`, one sample at/above
  `45 C`, and zero samples at/above the `50 C` confirmation threshold.
  Post-stop silicon was `34.1 C`; no thermal guard fired. This safely avoids
  the prior trace's post-73-second danger window, but different cool rounds
  prevent a controlled thermal-win claim.
- Health and evidence result: request acceptance, exact ISO/title/root,
  native activation, affinity `requested=0x7,effective=0x7`, and named workers
  passed. The full final logcat was retained (`120,648` bytes); the accepted
  marker appeared once and the polling latch survived later log growth. Native
  completion and callback-finished remain absent. Saved evidence has zero
  target fatal signals or unplanned process-death markers, `RPCSXActivity` rows,
  game boot, or residual PID. No retry or follow-up ADB command ran.
- Visual correctness and FPS/frame-time: not exercised. This is durable cache
  and controller-safety progress, not startup-speed, FPS, flicker, gameplay,
  sustained-stability, or temperature-win evidence.
- Decision and next: retain the polling cap, frozen installed candidate, and
  committed objects. Do not contact Thor again before
  `2026-07-22T22:21:44.5031527-04:00` and a fresh strict cool gate. Continue
  with at most one 70-second cache round; require native completion plus
  callback-finished before a separately cooled title baseline and later
  field/menu/first-battle correctness and performance proof.

### 2026-07-22 - cumulative-checkpoint-reuse-floor

- Status: host-evidence-hardening / no-device-contact / not-comparable
- Scope: prove atomic cache persistence after every bounded checkpoint
- Gap and change: the earlier controller raised the reuse floor only after a
  thermal stop and reset it to one after a normal progress checkpoint. A later
  run could therefore earn checkpoint credit without proving the newest normal
  checkpoint objects persisted. Both `cache-progress-checkpoint` and thermal
  stop evidence now require the next run to reuse at least the prior
  `reused + compiled` total. Other statuses retain the baseline floor.
- Current result: device-free Status reads capture
  `20260722-215019-firmware-ppu-prewarm` and now reports
  `minimum_required_reused_modules=185` from `169 + 16`, rather than `1`.
  Malformed checkpoint and malformed thermal-stop evidence both fail closed.
- Verification: the focused cache-route and thermal-guard contracts pass; the
  frozen candidate gate still proves APK A7216402...3D15C, merged core
  36B6B711...22797, and packaged core 0AB29DC7...B9E3 exactly. Status reports
  `device_contact=False`; no ADB resolution, temperature read, launch, or cache
  mutation occurred.
- Decision and next: retain the cumulative floor. This is evidence integrity,
  not startup-speed, FPS, gameplay, flicker, stability, or thermal-win credit.
  After the existing cooldown and a fresh strict cool gate, allow at most one
  70-second continuation and refuse checkpoint credit below 185 reused objects.

### 2026-07-22 - completed-firmware-cache-preparation

- Status: cache-prepared-exact-no-game-boot / continuity-pass / safety-pass /
  not-comparable
- Scope: one independently cooled, stopped-emulator completion round
- Hypothesis: the cumulative 185-object floor survived, and the remaining 24
  firmware files could finish inside the tightened 70-second thermal envelope.
- Changed files/settings: none on device; exact installed APK
  A7216402...3D15C, frozen core/cache identity, two-worker configuration,
  hardware FTZ, and `0x07` cache-worker affinity remained unchanged.
- Rollback: normal game boot does not invoke the debug-only prepare-cache
  intent; the package was force-stopped and no runtime setting changed.
- Thor result: capture
  `debug-captures/android-speed-sprint/20260722-222211-firmware-ppu-prewarm`
  reused exactly 185 validated objects, satisfied the cumulative continuity
  floor, compiled 24 new objects, finished firmware scan `142/142`, reached
  discovered module progress `24/24`, and reported both native preparation
  completion and callback finished. Runtime completed in `59.58 s`, below the
  `70 s` bound. Exact installed APK, ISO/root/title resolution, named workers,
  and every logged affinity row at `requested=0x7,effective=0x7` passed.
- Thermal result: strict preflight was `31.1 -> 30.5 -> 30.1 C`. Seventeen
  runtime samples averaged `37.8 C`, ranged from `33.5` to `46.6 C`, included
  one sample at/above `45 C`, and zero at/above the `50 C` confirmation
  threshold. Post-stop battery/skin/silicon were `22.0/30.0/33.3 C`; no
  thermal guard fired.
- Health result: request acceptance, native activation/completion, callback,
  full final logcat retention, and absent PID before/after passed. Saved
  evidence has no target native fatal, unplanned process death, FATAL
  EXCEPTION, ANR, `VK_ERROR_DEVICE_LOST`, RPCSXActivity/game boot, or residual
  PID. No retry or follow-up ADB action ran.
- Visual correctness: not exercised; the game never booted.
- FPS/frame-time: not measured.
- Decision: the cache-preparation prerequisite is complete and the exact
  frozen candidate remains the next baseline. This does not prove startup
  speed, FPS, flicker removal, gameplay correctness, sustained stability, or a
  controlled thermal win. Do not contact Thor again before a separate
  independent cooldown. Next run exactly one self-stopping `ThorCoolTitle`
  baseline, then reserve later cool rounds for field, full Options/menu, first
  battle, matched FPS/frame pacing, flicker, fatal cleanliness, and thermals.

### 2026-07-22 - completed-cache-title-thermal-stop

- Status: failed
- Scope: scene-route
- Hypothesis: the completed exact PPU/firmware cache would let the frozen
  candidate reach a stable title inside the guarded cool-start envelope.
- Changed files/settings: the device ran exact installed APK
  `A7216402...3D15C` with the pinned `ThorCoolTitle` profile: Direct input,
  RSX `256` / `500 ms`, SPU `64` / `100 ms`, two cache workers, affinity
  `0x07`, Vulkan cache plus hit-only preload, hardware FTZ, quiet logs, and the
  `68/72 C` early/hard guard. No APK, core, cache, or device setting changed.
- Rollback: the macro force-stopped the package and reset its experiment
  properties. The host-only successor profile tightens the same route to a
  `64/68 C` early/hard guard with a `52 C` confirmation threshold; the APK and
  prepared cache remain frozen.
- Windows result: not applicable; this was the first post-cache Thor title
  baseline.
- Thor result: capture
  `debug-captures/android-speed-sprint/20260722-225338-thor-input-custom`
  matched the exact installed APK and passed preflight at
  `31.3 -> 30.9 -> 30.9 C`. Debug boot was accepted. The first title poll at
  `1.243 s` was still a pale pre-title frame and sampled `50.6 C`; the next
  wait sample reached `65.0 C`, requested confirmation, and confirmed
  `69.9 C` about `0.649 s` later. The wrapper force-stopped below the `72 C`
  hard limit. Post-stop battery/skin/silicon were `22.0/30.0/44.1 C`, Android
  thermal status was `0`, and final PID evidence was absent.
- Runtime evidence: managed `Set DAZ and FTZ: true`, the validated
  `4,899,180`-byte Vulkan seed, RSX `load=2, compile=2`, exact RSX affinity,
  the `500 ms` load budget (`40/256` attempted), SPU two-worker affinity, and
  the `100 ms` SPU budget (`5/64` built) activated. The saved guest log reached
  emulator time `4.077166 s`; no PPU compile-affinity row appeared before the
  stop, so the analyzer correctly reports activation incomplete in addition
  to the thermal failure.
- Visual correctness: failed before title. The only saved frame is the
  pale/gray pre-title transition, with `title_menu_present=False` and one
  unstable PPU-ready sample. No field, menu, battle, or flicker proof exists.
- FPS/frame-time: none.
- Decision: `thermal-stop-before-title` / `failed` / `not-comparable`.
  `ready_for_comparison=False` and `speed_credit=False`; grant no startup-speed,
  FPS, thermal-win, flicker, gameplay, or stability credit. The burst was
  CPU-side: the hottest CPU sensor reached `69.9 C` while the hottest saved
  GPU sensor was `35.2 C`.
- Next: do not contact Thor again in this round. Keep the exact APK/cache
  frozen, use the tightened `64/68 C` title profile for any later independently
  cool proof, and investigate the post-cache CPU/SPU startup burst host-side
  before another one-shot route.

### 2026-07-23 - failure-cleanup-proof

- Status: host-evidence-hardening / no-device-contact / not-comparable
- Authoritative failed title capture:
  `20260723-023526-thor-input-custom` remains
  `thermal-stop-before-title`: exact APK and `7/7` native-object reuse passed,
  silicon peaked at `63.0 C`, title was not reached, and final PID was absent.
- Gap and change: the macro now writes a batched 21-property reset readback on
  failed booted routes, but the analyzer previously validated only the normal
  success cleanup file. It now parses
  `startup-profile-failure-reset-effective.txt` independently and reports
  `failure_cleanup_ready` plus exact failure-reset mismatches without hiding
  the primary thermal/fatal/preflight classification.
- Current evidence: the old failed capture predates that readback, so its
  archived analysis honestly reports `failure_cleanup_ready=False` and all
  `21` reset facts missing while retaining `process_absent_at_failure=True`.
  A future capture can earn cleanup readiness only with absent PID and all
  21 safe values.
- Verification: synthetic complete and leaked-property failure paths pass,
  PowerShell parses, `git diff --check` passes, and all `66/66` Thor host
  contracts pass.
- Decision and next: this is cleanup-proof hardening, not speed, FPS, thermal,
  flicker, gameplay, or stability credit. The installed APK/core remain frozen.
  Do not contact Thor before the title-sourced cooldown opens at
  `2026-07-23T03:05:48.9964640-04:00`; then run at most one guarded cooler
  `64 RSX / 200 ms, 17 SPU / 25 ms` title proof.

### 2026-07-23 - recorded-device-cooldown-source

- Status: host thermal-safety repair / no-device-contact / not-comparable
- Counterexample: archiving `cool-title-analysis.json` updated the capture
  directory mtime, and the controller incorrectly moved cooldown readiness
  from `03:05:48` to `03:25:27` despite reporting `device_contact=False`.
- Change: title completion now uses the newest ISO timestamp recorded by ADB
  evidence headers and bounded runtime/thermal logs. Mutable host analysis
  files and directory mtimes cannot create false device activity; missing
  recorded evidence fails closed.
- Verification: a synthetic later analysis JSON cannot change the parsed
  device completion, the real capture resolves to
  `2026-07-23T02:35:48.9151347-04:00`, readiness is restored to
  `03:05:48.9151347`, and all `66/66` Thor host contracts pass.
- Decision and next: no cooldown was shortened below real device evidence and
  no Thor command ran. Wait for the restored guard, then allow one cooler title
  proof only.

### 2026-07-23 - cooler-title-preflight-refusal

- Status: preflight-refused-hot / no-game-launch / safety-pass /
  not-comparable
- Scope: the one allowed action after the title-sourced cooldown, using the
  cooler `64 RSX / 200 ms, 17 SPU / 25 ms` title profile.
- Thor result: capture `20260723-030615-thor-input-custom` matched the exact
  installed APK but refused at the first preflight sample. The hottest silicon
  sensor was `35.5 C`, above the strict below-`35 C` launch ceiling. The debug
  boot intent was never issued, the game never started, no screenshot/gameplay
  frame was taken, and no retry occurred.
- Cleanup: failure PID evidence was absent and the new failure-reset proof
  matched all `21/21` safe property values. Maximum recorded silicon remained
  `35.5 C`; battery/skin were `24.0/30.0 C`.
- Evidence repair: the pulled `failure-RPCSX.log` was byte-identical to the
  prior launched capture and therefore stale. The collector now skips guest-log
  pulls when no boot request was issued, and the analyzer trusts activation,
  fatal, and native-object rows only after an accepted nonce-bound handshake.
  Reanalysis reports `guest_log_trusted=False`, native objects `0/7`, no fatal
  hits, and the same primary `preflight-refused-hot` classification.
- Verification: focused analyzer/thermal tests and all `66/66` Thor host
  contracts pass.
- Decision and next: grant no startup-speed, FPS, thermal-win, gameplay,
  flicker, or stability credit. Device-free Status sets the next earliest
  contact to `2026-07-23T03:36:27.5707936-04:00`; do not retry in this round.

### 2026-07-23 - minimal-preflight-refusal-cleanup

- Status: host thermal-safety improvement / no-device-contact / not-comparable
- Measured trigger: the no-launch refusal command occupied `16.7 s`; after its
  thermal stop, the generic failure path collected a full activity/window/
  memory/frequency/cache postmortem even though no boot intent had been issued.
- Change: a pre-boot refusal now retains the already-recorded post-stop thermal
  sample, performs exactly one PID query, and then records the existing batched
  21-property reset proof. Full postmortem and guest-log collection remain
  unchanged after an actual debug-boot request.
- Verification: macro AST/source contracts and all `66/66` Thor host contracts
  pass. No device measurement is claimed until a later independently cooled
  refusal or launch exercises it.
- Upstream audit: official July 21 RPCS3 patches `85c5920`, `2aeb08f`, and
  `d75543a` improve LLVM known-bit/constant analysis but do not execute when the
  measured PPU path reuses already-compiled objects. The vendored core already
  contains the relevant July 1 PPU worker/concurrency changes and ARM64 SPU
  compare optimization. No unrelated upstream patch was imported.
- Decision: this reduces unnecessary device contact after a safe refusal; it
  is not emulator FPS/startup/thermal-win evidence. Keep the installed candidate
  frozen and the cooldown intact.

### 2026-07-23 - cooler-title-runtime-counterproof

- Status: thermal-stop-before-title / startup-stage-progress /
  safe-counterproof / not-comparable
- Scope: one exact-APK `ThorCoolTitle` action after the recorded cooldown;
  capture `20260723-033645-thor-input-custom`. No retry or later device query
  ran.
- Identity and controls: installed APK
  `5044976A53036961883A3723ECE8C54811B6AEB45D4EB1116ACD802D40D83E5C`
  matched. Preflight passed at `32.1 -> 32.3 -> 31.9 C`; power state matched
  the prior title attempt (`performance_mode=0`, `fan_mode=4`, WALT governors).
  The guest proved RSX `64/200 ms`, SPU `17/25 ms`, two workers, affinity
  `0x7`, Vulkan cache hit-only, and native cache `on`.
- Startup staging: RSX attempted `18/64` rather than the prior `41/256`; PPU
  warm-object reuse began at emulator `1.384 s` rather than `1.732 s`, and the
  bounded SPU phase finished at `1.820 s` rather than `2.264 s`. This is
  roughly `348-444 ms` of guest-stage progress only.
- Counterproof: the first runtime poll was `61.4 C`, immediate confirmation
  was `61.8 C`, and the route force-stopped below the `68 C` hard limit before
  title. Post-stop was `46.2 C`, PID was absent, all `21/21` failure-reset
  properties matched, and targeted fatal hits were zero. The prior route
  confirmed at `63.0 C`; different transient shapes and no title make this
  insufficient for a thermal-win claim.
- Native-cache gap: the `25 ms` budget processed only six programs and loaded
  `6/7` durable native objects; the proof gate correctly rejected comparison.
  The host successor keeps the smaller 17-program prefix but raises only the
  SPU compile budget midpoint to `50 ms`, between the failed `25 ms` bound and
  the prior hot `100 ms` bound. Analyzer fixtures and profile contracts now
  require `50 ms`.
- Decision and next: no startup-speed, FPS, thermal-win, gameplay, flicker, or
  stability credit. Device-free Status refuses contact before
  `2026-07-23T04:07:07.7409903-04:00`. A later independently cool round may
  run at most one exact title proof; it must load all `7/7` native objects and
  reach the real title before any field/menu/battle work.

### 2026-07-23 - fifty-ms-preflight-refusal

- Status: preflight-refused-hot / no-game-launch / safety-pass /
  not-comparable
- Scope: one guarded `ThorCoolTitle` action with the corrected
  `64 RSX / 200 ms, 17 SPU / 50 ms` profile; capture
  `20260723-040730-thor-input-custom`. No retry or later device query ran.
- Result: preflight samples were `34.5 -> 34.5 -> 35.1 C`; the third sample
  crossed the strict below-`35 C` launch ceiling. Debug boot was never
  requested, guest-log evidence is untrusted/absent, native reuse is `0/7`,
  and no screenshot, title, or gameplay frame exists.
- Cleanup: PID was absent and all `21/21` transient properties matched their
  safe reset values. Maximum silicon was `35.1 C`.
- Decision: grant no startup-speed, FPS, thermal-win, gameplay, flicker, or
  stability credit. Recorded device completion was
  `2026-07-23T04:07:45.1904512-04:00`; no contact is allowed before
  `04:37:45.1904512-04:00`.

### 2026-07-23 - warm-ppu-link-affinity-host-candidate

- Status: host candidate / uninstalled / unmeasured / not-comparable
- Measured trigger: both launched counterproofs spent a repeatable
  `0.363-0.364 s` between the fully warm PPU reuse marker and the next warm
  module while the caller thread had no startup affinity gate. Cold PPU
  compile workers already used the BLUS30161 efficiency-core mask.
- Change: Android BLUS30161 fully warm linking now temporarily applies the
  existing startup affinity mask (`0x7` by profile), logs requested/effective
  state, and restores the exact prior caller mask on scope exit. The gate
  requires `workload.empty()` and retained validated objects; cold
  compilation, runtime PPU execution, desktop, and other titles are unchanged.
  The title analyzer accepts either cold compile-worker or warm-link affinity
  proof and fails closed on a warm-link mismatch.
- Build and identity: ARM64 native build passed in `95.7 s`; ARM64-only
  optimized `assembleThortest` passed in `127.9 s`. APK
  `81BAF133B6442E5AC3856D76E091187D772C660FE68EC1DFC78177B914D54BC2`
  is `72,835,284` bytes; merged core
  `5E90A68D4D3600CFC67C191B7DADD90053784A9D3D6304216C39B98B51EBE6BC`
  is `1,304,260,536` bytes; stripped/APK core
  `5A1C89DFFE2447BBE510A2778D835ACEAAB2A5D15DAA946443E56082D793D53A`
  is `62,985,608` bytes.
- Verification: ARM64 ABI, optimized variant, exact artifact/embedded marker,
  focused analyzer/affinity, PowerShell parse, `git diff --check`, and all
  `66/66` Thor host contracts pass.
- Decision and next: this is a measured-path hypothesis, not a speed or
  thermal win. The new APK is not installed or launched; installed
  `5044976A...D83E5C` remains frozen. After an independently cool interval,
  use one no-launch install round; a later separate round must prove exact
  identity, `7/7` reuse, title, field, menu, battle, frame pacing, flicker,
  stability, and sustained thermals before credit.

### 2026-07-23 - warm-ppu-finalize-affinity-exact-no-launch-install

- Status: installed-exact-no-launch / host-scope-repaired /
  runtime-unmeasured / not-comparable
- Pre-install audit: `jit_compiler::add()` only admits validated objects;
  LLVM's actual `finalizeObject()` is called by `jit->fin()` after the original
  RAII block. APK `81BAF133...D54BC2` was therefore superseded before device
  installation rather than testing an incomplete scope.
- Change: the BLUS30161 fully warm affinity lifetime now spans object admission
  and every first-use `jit->fin()`, explicitly restores the exact prior caller
  mask before symbol resolution, and retains destructor restoration for every
  stop/error/empty-JIT early return. Cold compilation, runtime PPU execution,
  desktop, other titles, and post-finalization symbol/application work remain
  unchanged. The source contract proves admission -> finalization -> restore
  -> symbol-resolution order.
- Build and identity: optimized ARM64-only `assembleThortest` passed in
  `80.6 s`. APK
  `351C67488203F63AD79B98A9CE9884CA2D6F7F42A0E73C1178A78ECBF5A1181E`
  is `72,835,876` bytes; merged core
  `5319D7390B932039ECCF03B8FA45D84852C1AD17DC40FB9889BBA1F0AA0CE0B6`
  is `1,304,271,400` bytes; stripped/APK core
  `C550C01152577CF3523035CD06229A20A0B5AEFB64EF275F7C922E5684DB09AA`
  is `62,985,816` bytes. ABI, optimized variant, embedded marker, exact
  artifact, focused affinity, and all `66/66` Thor host contracts pass.
- Thor result: the one combined no-boot round first passed strict gate
  `20260723-043753-thor-input-strict-cool-gate` at
  `32.3 -> 31.9 -> 31.7 C` (maximum `32.3 C`, rise `-0.6 C`). Capture
  `20260723-043805-ppu-warm-finalize-affinity-thortest-apk-install` proves
  `adb install -r` success and exact host/on-device APK identity. PID was
  absent before and after, no activity launched, all captured transient
  controls were safe, and post-install battery/skin/silicon were
  `23.0/30.0/33.7 C`. No retry or later device query ran.
- Cooldown evidence repair: host-only status previously rejected the prior
  old-candidate title capture before considering the newer exact install.
  Title routes now require a real 64-hex installed-hash record plus the exact
  safe title macro/stop metadata, but candidate identity is left to the
  analyzer/runtime gate. This preserves old-title thermal contact without
  granting it new-candidate correctness. Status selects the install at
  `04:38:12.6406001-04:00`, reports `device_contact=False`, and refuses contact
  until `05:08:12.6406001-04:00`.
- Decision and next: installation is identity/safety proof only. After that
  independently cool interval, spend at most one corrected `64 RSX / 200 ms,
  17 SPU / 50 ms` title round. Require exact affinity activation, all `7/7`
  native objects, title visual proof, absent fatal hits, safe cleanup, and
  measured warm-link timing before field/menu/battle work or any performance
  claim.

### 2026-07-23 - warm-ppu-link-timing-proof

- Status: host analyzer hardening / no-device-contact / not-comparable
- Change: the title analyzer deduplicates timestamped successful warm-affinity
  events, selects the event with the largest object count, and records its
  start time, the next warm module start, object count, event count, and
  millisecond interval. Comparison-ready now requires at least two ordered
  events and a positive interval.
- Verification: a synthetic `41`-object event at `1.384222 s` followed by a
  one-object event at `1.690222 s` reports exactly `306 ms`; persisted JSON
  retains every value, truncated evidence fails activation, and all `66/66`
  Thor host contracts pass.
- Decision: no APK/core or device state changed. The later one-shot title
  proof can now compare the corrected interval directly with prior
  `363-364 ms` old-candidate observations without granting speed credit unless
  title correctness and thermal gates also pass.
### 2026-07-23 - warm-ppu-finalization-affinity-counterproof-and-host-repair

- Status: thermal-stop-before-title / decisive timing regression /
  host successor built / successor uninstalled / not-comparable
- Thor counterproof: the single guarded `ThorCoolTitle` attempt produced
  `20260723-050847-thor-input-custom`. Exact installed APK and debug boot
  passed after preflight `32.3 -> 32.1 -> 32.1 C`; `8/7` durable SPU native
  objects loaded and no fatal hit was recorded. The route never reached title.
  Silicon rose through `47.4`, `63.4`, and confirmed `70.3 C`; the hard guard
  force-stopped at the `68 C` limit. Post-stop was `48.6 C`, PID was absent,
  and all `21/21` transient properties matched safe values. No retry or later
  device query ran.
- Timing counterproof: matched captures measured the fully warm primary
  `41`-object event to the next one-object module at `364.325 ms`
  (`20260723-023526`), `363.002 ms` (`20260723-033645`), and `1946.229 ms`
  in the new capture. Extending the `0x7` efficiency-core affinity through
  `jit->fin()` was therefore about `5.36x` slower on this observed interval.
- Host repair: BLUS30161 warm-cache object admission remains temporarily
  affinity-gated, but the exact caller mask is now restored before
  `jit->fin()`, symbol resolution, and later runtime work. Destructor
  restoration remains for early exits. `ThorCoolGameplay` adds exact-candidate
  field/menu/battle routes with the same strict thermal envelope, verified
  force-stop after every macro, and gameplay captures as cooldown sources.
- Rebuilt identity: optimized ARM64-only `assembleThortest` passed in
  `1m29s`. APK
  `3DFB5F5560775C843210BC80B16943DE20C9887D0DD250DF666B2F9AC2A34A78`
  is `72,835,176` bytes; merged core
  `A21A5095E482DE1889454DF16200C04F51D5EA296AE0F91C727835086EFC1DBA`
  is `1,304,269,848` bytes; stripped/APK core
  `05085F2195CEE804EF9371373FB747D3D0D2CA249B50FB908A6C09483A22F909`
  is `62,985,688` bytes. Exact artifact, ABI, optimized-variant, affinity
  ordering, and all `66/66` Thor host contracts pass.
- Decision and next: grant no speed, FPS, thermal-win, gameplay, flicker, or
  stability credit. The repaired successor is host-built but not installed.
  After an independently cool interval, use one separate no-launch install
  round; only a later cool exact-title pass may unlock separate field, menu,
  and battle measurements.
