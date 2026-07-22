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