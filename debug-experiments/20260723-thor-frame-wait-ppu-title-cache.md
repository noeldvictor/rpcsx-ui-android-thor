# Thor frame-wait PPU-lifetime title cache

Date: 2026-07-23

## Outcome

The Android Eternal Sonata frame-poll path now evaluates its exact
`BLUS30161` title gate once when each PPU object is constructed. The result is
immutable for that PPU lifetime. The hot `sys_timer_usleep` wrapper and its
post-sleep fallback read the cached byte instead of comparing the nine-byte
emulator title string on every eligible 100 us call.

This is host-verified `stackable-cpu-pressure` work. It is not measured FPS,
temperature, power, flicker, gameplay, stability, or end-to-end speed credit.

## Correctness boundary

Both normal and savestate PPU constructors initialize the flag with the exact
string comparison:

```cpp
is_thor_es_title(Emu.GetTitleID() == "BLUS30161")
```

The frame-wait path retains its exact main-PPU ID, CIA, 100 us sleep, object,
divisor, counter, renderer, and setting gates. A different game creates new
PPU objects and therefore receives a new exact title decision. If the title is
not available at construction, the flag is false and the optimization fails
closed. There is no process-lifetime title result that can remain enabled
across a game change.

Unchanged functional behavior includes:

- `Off`, diagnostic `Wait`, and production `Fast` modes;
- the one-millisecond completion wait and relaxed waiter registration stores;
- the final acquire publication load before the guest counter read;
- the cached 0-500 us handler grace and 100 us wait quantum;
- continuous rearm, completion tracking, and the normal timer fallback; and
- full diagnostic counters/logging only in `Wait`.

## Dynamic relevance

Saved correctness-clean continuous-rearm routes recorded:

| Route | Eligible calls |
|---|---:|
| Title | 34,612 |
| First battle | 105,181 |
| Options | 33,485 |
| Total | 173,278 |

The predecessor's first title gate executed a 23-instruction linked string
block for every eligible call. The successor executes one `LDRB`, one compare,
and one branch. This removes at least 20 linked title-gate instructions per
eligible call, or at least 3,465,560 instruction executions over the three
saved routes. The fallback contained a second identical string block, but its
route hit count is not included, so this is conservative.

## Exact ARM64 proof

Predecessor merged core
`9658E6571DEE57A72C50481325E2A32E83E9F44AEDAEE781528C71A3875A3C28`
implemented the first string gate at `0x16d1710..0x16d1768` and the fallback
gate at `0x16d17d4..0x16d182c`. Each loaded string size/storage and compared
the eight-byte prefix plus final byte. `sys_timer_usleep` was `0x590` bytes.

Successor merged core
`2A61C4EA1B0DD6CA3FB3A8B9D0064A1C7A0CD32B82CF20D2FB0EA5DFA69E7DDD`
contains exactly two direct immutable title loads:

```text
16d1714: ldrb  w8, [x19, #0x9f9]
16d1718: cmp   w8, #0x1
16d171c: b.ne  normal_timer_path
...
16d18f4: ldrb  w8, [x19, #0x9f9]
16d18f8: cmp   w8, #0x1
16d18fc: b.ne  normal_fallback_path
```

The linked function contains none of the old inlined title words
`0x4c42`, `0x5355`, `0x3033`, or `0x3631`. `sys_timer_usleep` is now `0x4d4`
bytes: 188 bytes smaller, a 13.2% reduction. The bounded wait, registration
stores, final publication acquire, grace wait, completion update, and fallback
remain present.

## Verification

Passed:

- focused frame-poll source and PPU-lifetime title-cache contract;
- Android ARM64 RelWithDebInfo native build;
- exact linked ARM64 direct-byte/no-string-word assertion;
- ThorTest ARM64-only APK build;
- exact ARM64 APK/merged-core identity contract;
- exact candidate artifact/APK-entry identity contract;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK: `D65C474CC1A31CFED9969D2D5288385D3182F71C41269DAEF7D5FF53F844C3EA`,
  72,837,616 bytes.
- Merged ARM64 core:
  `2A61C4EA1B0DD6CA3FB3A8B9D0064A1C7A0CD32B82CF20D2FB0EA5DFA69E7DDD`,
  1,304,324,952 bytes.
- Packaged ARM64 core:
  `405A08CA4E8E20BA48D2C83A52893ABEBDBBB85B55898D6C4CE086C1A9CE3646`,
  62,989,080 bytes.

No ADB query, install, launch, temperature poll, device wait, or other Thor
contact occurred. The APK is host-built and device-unmeasured.
