# Thor frame-wait relaxed setting caches

Date: 2026-07-23

## Outcome

The Eternal Sonata frame-poll path now caches its immutable wait mode,
continuous-rearm setting, and handler-grace bound in constant-initialized
atomic sentinels. Hot readers use direct relaxed `LDRB`/`LDR` loads; property
and environment parsing remains in outlined cold initializers. Cheap PPU ID,
CIA, and sleep-duration gates now reject unrelated timer calls before title or
cached-setting work. The fallback path reads the mode once and reuses it for
the diagnostic-only counter.

This is host-verified `stackable-cpu-pressure` work. It is not measured FPS,
temperature, power, flicker, gameplay, stability, or end-to-end speed credit.

## Correctness boundary

Each cached setting is a self-contained atomic value. Readers consume no
separate data through it, so steady-state relaxed loads are sufficient. The
first reader computes the same process-lifetime property/environment value and
publishes it atomically with release ordering; a concurrent first reader may
compute the same immutable value without a data race. This preserves the old
process-lifetime caching behavior while removing compiler guard state.

Unchanged functional behavior includes:

- `Off`, diagnostic `Wait`, and production `Fast` values;
- exact BLUS30161, main-PPU, CIA, sleep, object, divisor, threshold, renderer,
  and registration gates;
- the one-millisecond event wait and relaxed registration stores;
- final acquire token publication before the guest counter read;
- the cached 0-500 us grace bound and 100 us wait quantum;
- continuous rearm, completion tracking, and the original timer fallback; and
- full counters/logging in diagnostic `Wait`, with stats compiled out of
  production `Fast`.

## Dynamic relevance

Saved correctness-clean continuous-rearm routes recorded:

| Route | Eligible calls | Continuous rearms | Progress after grace |
|---|---:|---:|---:|
| Title | 34,612 | 992 | 1,136 |
| First battle | 105,181 | 2,447 | 4,595 |
| Options | 33,485 | 742 | 1,229 |
| Total | 173,278 | 4,181 | 6,960 |

Every eligible call previously executed a compiler guard `LDARB` plus a second
mode `LDRB`. Every continuous rearm executed the guarded boolean helper. Every
post-grace progress event proves at least one guarded grace lookup, so 6,960 is
a conservative lower bound for that accessor.

Across the three routes, the successor therefore removes at least 184,419
acquire guard loads and 184,419 redundant second value loads. Inlining the
continuous/grace fast checks also removes at least 11,141 helper calls. Calls
rejected before the diagnostic `calls` counter and grace lookups without
post-grace progress are not included, so these counts are conservative.

## Exact ARM64 proof

Predecessor merged core
`97A485B5428ABD32E8DC41069017D0C4E4A3104A435E849FA15B94CF91C735CB`
contained three frame-poll C++ guard variables. Its mode path used `LDARB` on
the guard then `LDRB` on the value; continuous/grace used `0x74`/`0x70` helper
frames with `LDARB`, a second value load, and guarded initialization.

Successor merged core
`9658E6571DEE57A72C50481325E2A32E83E9F44AEDAEE781528C71A3875A3C28`
contains no frame-poll guard variables. Exact production code emits:

```text
16d16e4: ldr   w8,  [x19, #0x10]   ; cheap PPU gate first
...
16d1920: ldrb  w0,  [x8, #0x548]   ; relaxed mode cache
16d1924: cbz   w0,  0x16d1ae4      ; cold initializer only
16d1934: cmp   w8,  #0x3           ; Fast
...
16d1a64: ldrb  w11, [x11, #0x5e0] ; relaxed continuous cache
...
16d1b34: ldr   w20, [x8]
16d1b38: strb  w9,  [x10, x25]
16d1b3c: ldr   w9,  [x8]
16d1b50: mov   w2,  #0x3e8
16d1b58: bl    thread_ctrl::wait_on(..., 1000)
16d1b60: strb  wzr, [x21, x25]
16d1b64: ldar  w9,  [x8]           ; publication acquire retained
...
16d1b84: ldr   x20, [x8, #0x4f0]  ; relaxed grace cache
16d1b98: mov   w0,  #0x64
16d1ba0: bl    thread_ctrl::wait_for(...)
16d1bd4: str   x8,  [x9, #0x560]   ; functional completion retained
```

`sys_timer_usleep` shrinks from `0x5b4` to `0x590` bytes. The full diagnostic
specialization remains outlined and is not selected by managed `Fast` profiles.
An exact assertion rejected guard symbols, `__cxa_guard_*`, cache `LDARB`s, or
missing wait/publication/fallback instructions.

## Verification

Passed:

- focused frame-poll source/cache/gate-order contract;
- Android ARM64 RelWithDebInfo native build;
- exact linked ARM64 cache and wait/publication contract;
- ThorTest ARM64-only APK build;
- exact ARM64 APK/merged-core identity contract;
- exact candidate artifact/APK-entry identity contract;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check` before documentation.

Exact host-only artifact:

- APK: `9B244D209DFCE58E92DFF134CA0A71B146252FB5AE1DE396060104A7F4463F53`, 72,837,528 bytes.
- merged ARM64 core: `9658E6571DEE57A72C50481325E2A32E83E9F44AEDAEE781528C71A3875A3C28`, 1,304,325,056 bytes.
- packaged ARM64 core: `B7150001DB2A7E85427E5C57DDE943520CFC4C4E6513C9267762D235EB5BE8F7`, 62,989,080 bytes.

No ADB query, install, launch, temperature poll, wait, or other Thor contact
occurred. The APK is host-built and device-unmeasured.