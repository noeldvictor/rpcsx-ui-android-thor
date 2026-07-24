# Thor Android timer-config relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in timer and scheduler hot
paths, including Eternal Sonata `BLUS30161`. Thor was not contacted.

## Baseline

Two standalone configuration scalars were read with acquire ordering in hot
Android paths because their generic config wrappers exposed only ordered
accessors:

- dynamic enum `sleep_timers_accuracy` in `sys_timer_usleep`,
  `lv2_obj::awake_unlocked`, and every eligible `lv2_obj::wait_timeout` loop;
- non-dynamic integer `clocks_scale` at scaled `wait_timeout` entry.

Neither scalar publishes dependent object state. Each read only selects local
timing arithmetic or a scheduler branch. The predecessor exact ARM64 emitted:

| Function/site | Baseline instruction | Baseline symbol size |
|---|---|---:|
| `awake_unlocked` accuracy | `15f2eac: LDAR w10, [x10]` | `0x670` |
| `wait_timeout` clock scale | `15f5100: LDAR w9, [x9]` | `0x230` |
| `wait_timeout` accuracy | `15f51c0: LDAR w8, [x27]` | `0x230` |
| `sys_timer_usleep` accuracy | `16d1888: LDAR w8, [x8]` | `0x494` |

The predecessor merged core was
`22D1DDC69BB3F7E0C2DEB3038CF381D5C1B44826125C70EAEBCBF05142C64FB6`,
1,304,324,496 bytes.

## Change

`cfg::_enum` now exposes explicit `observe()` backed by the existing relaxed
`atomic_t::observe()`, matching the prior `cfg::_int::observe()` accessor.
Android timer/scheduler call sites use relaxed reads for the two independent
scalars; desktop explicitly retains ordered `get()` reads.

The dynamic accuracy setting remains atomic and is still read live at every
original decision. A concurrent setting change may produce the adjacent old or
new enum for one decision, both valid outcomes for this independent scalar.
Clock scale remains read only inside the existing `scale` branch. The
`is_create_thread || ...` short circuit remains, so create-thread wakeups do
not gain a config read.

No wait state, queue payload, notification, timeout, guest memory, or
publication ordering changed. All state/token/queue acquire operations remain.
Official RPCS3 `master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` remains the upstream reference.

## Exact ARM64 proof

The successor exact ARM64 emits plain immediate-offset loads at all four sites:

| Function/site | Successor instruction | Successor symbol size | Size change |
|---|---|---:|---:|
| `awake_unlocked` accuracy | `15f2ea4: LDR w10, [x11, #0x1744]` | `0x650` | -32 bytes |
| `wait_timeout` clock scale | `15f50d0: LDR w8, [x8, #0x157c]` | `0x218` | -24 bytes total |
| `wait_timeout` accuracy | `15f5188: LDR w8, [x8, #0x1744]` | `0x218` | included above |
| `sys_timer_usleep` accuracy | `16d183c: LDR w8, [x21, #0x1744]` | `0x48c` | -8 bytes |

The three symbols shrink 64 bytes combined. Exact disassembly also confirms
that their unrelated synchronization `LDAR`/`LDARB` operations remain.

Saved clean route counters provide one conservative dynamic lower bound:

| Route | Total `usleep` | Frame waits returning early | Normal sleep-path reads removed |
|---|---:|---:|---:|
| Title | 79,952 | 34,542 | 45,410 |
| First battle | 245,726 | 105,145 | 140,581 |
| Options | 258,641 | 33,484 | 225,157 |
| Total | 584,319 | 173,171 | 411,148 |

Thus the known normal `sys_timer_usleep` path alone avoids 411,148 accuracy
acquire barriers. Relaxed clock-scale and accuracy reads inside
`wait_timeout`, plus eligible `awake_unlocked` scheduler reads, are additional
unclaimed savings because no exact per-site dynamic counters were captured.
This does not claim FPS, power, or temperature improvement.

Adding the inline enum accessor changes RelWithDebInfo type/debug metadata
across rebuilt translation units, growing the unstripped merged core by 3,696
bytes. The runtime-relevant stripped core shrinks 96 bytes and the APK shrinks
296 bytes.

## Verification

Passed:

- Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor linked ARM64 symbol and disassembly comparison;
- source contract covering both config accessors, all four Android sites,
  desktop ordered reads, and scheduler short-circuit structure;
- ThorTest ARM64-only APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `71/71` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK:
  `BAE484CCB9024EB84FA4022A470ADB7E83C038C0392E958F86F57881B92D87DE`,
  72,837,128 bytes.
- Merged ARM64 core:
  `AB8AE9A07D4B2FEDA8B86C20C2936D9FDE71580CEDF6379FE3C936910FC48550`,
  1,304,328,192 bytes.
- Packaged ARM64 core:
  `298AC1FD5735658B3F77F2489A6DCF6A3A6A5E73E7E0CBB0487886C21D5A1850`,
  62,989,016 bytes.
- APK native entry matches the packaged-core hash and size exactly.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, stability, power, flicker, or temperature credit.
