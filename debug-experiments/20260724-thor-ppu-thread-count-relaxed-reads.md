# Thor Android PPU-thread-count relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in PPU scheduling and VM
locking. Thor was not contacted.

## Baseline

`g_cfg.core.ppu_threads` is a range-bounded `cfg::_int<1, 8>` with default two
and no dynamic flag. It is an independent scalar that selects how many PPU
slots scheduler and VM-lock loops inspect; it does not publish queue, thread,
or lock payload.

The generic ordered config conversion nevertheless emitted 11 acquire loads
across seven linked Android ARM64 functions. The same source function was
inlined into `awake_unlocked`, so ten runtime source sites became eleven linked
sites:

| Linked function | Baseline PPU-count `LDAR` sites | Baseline size |
|---|---:|---:|
| `awake_unlocked` | 4 | `0x650` |
| `schedule_all` | 2 | `0x460` |
| `count_non_sleeping_threads` | 1 | `0x5c` |
| `ppu_state` | 1 | `0x2fc` |
| `vm::passive_lock` | 1 | `0x1b8` |
| `vm::writer_lock` | 2 | `0x460` |
| outlined `awake_unlocked` lambda | code-size tracking only | `0x1e0` |

The predecessor merged core was
`AB8AE9A07D4B2FEDA8B86C20C2936D9FDE71580CEDF6379FE3C936910FC48550`,
1,304,328,192 bytes.

## Change

Android scheduler sites now read the count through
`get_ppu_thread_count_for_scheduler()`, which uses the existing relaxed
`cfg::_int::observe()`. VM lock sites use an equivalent local helper. Desktop
explicitly retains ordered `get()` reads.

Each observation remains atomic and live, so a different count configured
between emulator sessions is still read normally. No process-global cache was
introduced. The backing lock array remains sized to the declared maximum of
eight, so every allowed observed count is in bounds.

The range-lock writer now observes the immutable count once and reuses it for
its two sequential scans. This removes one load entirely and ensures both scans
cover the same slot range. PPU queue traversal, thread state, range-lock bits,
notifications, and memory publication ordering are unchanged.

Official RPCS3 `master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` remains the upstream reference.
This is a local Android configuration-read code-generation refinement.

## Exact ARM64 proof

The predecessor's 11 count loads were `LDAR` instructions after separately
forming `g_cfg + 0x13c`. The successor contains ten direct relaxed loads of the
form `LDR Wn, [Xm, #0x13c]`; the second writer-lock observation no longer
exists.

Successor sites:

```text
15f2c44  LDR w8,  [x25, #0x13c]
15f2c6c  LDR w9,  [x25, #0x13c]
15f2d2c  LDR w28, [x25, #0x13c]
15f2f54  LDR w8,  [x8,  #0x13c]
15f3324  LDR w10, [x10, #0x13c]
15f33ac  LDR w26, [x8,  #0x13c]
15f47b4  LDR w8,  [x8,  #0x13c]
15f4dd0  LDR w9,  [x9,  #0x13c]
3766bf0  LDR w10, [x10, #0x13c]
3766f80  LDR w21, [x8,  #0x13c]
```

Exact affected symbol sizes:

| Linked function | Successor size | Change |
|---|---:|---:|
| `awake_unlocked` | `0x650` | unchanged after block padding |
| outlined `awake_unlocked` lambda | `0x1e0` | unchanged after block padding |
| `schedule_all` | `0x440` | -32 bytes |
| `count_non_sleeping_threads` | `0x54` | -8 bytes |
| `ppu_state` | `0x2f8` | -4 bytes |
| `vm::passive_lock` | `0x1b4` | -4 bytes |
| `vm::writer_lock` | `0x440` | -32 bytes |
| Total | | -80 bytes |

The same disassembly ranges retain 60 `LDAR`/`LDARB` instructions for actual
thread, queue, state, and lock synchronization. No dynamic call count was
captured, so this round claims no executed-barrier total, FPS, power, or
thermal delta.

The unstripped merged core grows 168 bytes from debug/layout metadata. The
runtime-relevant stripped core shrinks 32 bytes and the APK shrinks 24 bytes.

## Verification

Passed:

- Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor symbol and disassembly comparison;
- source contract proving non-dynamic range, all scheduler/VM call sites,
  relaxed Android reads, ordered desktop reads, and one reused writer snapshot;
- ThorTest ARM64-only APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `72/72` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK:
  `6F9C32F70FDDF949554F8BE147E755CDD5966A7B578AEF95C06CBDCF1F293FDB`,
  72,837,104 bytes.
- Merged ARM64 core:
  `FBAC81A595F5A97668168AA8803B788DB4AC8DC13CFF6DBED7CB6E7DFE790676`,
  1,304,328,360 bytes.
- Packaged ARM64 core:
  `85E7B139AB5ADFE775A6A8F6C4BA7BC637034D39F60FA179FD1931F3ACFCF2E7`,
  62,988,984 bytes.
- APK native entry matches the packaged-core hash and size exactly.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, stability, power, flicker, or temperature credit.
