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
