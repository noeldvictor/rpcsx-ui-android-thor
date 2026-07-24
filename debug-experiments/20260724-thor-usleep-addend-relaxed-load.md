# Thor Android usleep-addend relaxed load

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in the guest micro-sleep
path, including Eternal Sonata `BLUS30161`. Thor was not contacted.

## Baseline

`sys_timer_usleep` reads the dynamic `g_cfg.core.usleep_addend` setting on every
nonzero guest micro-sleep. The setting is one independently atomic integer and
does not publish dependent state, but `cfg::_int` exposed only its ordered
implicit conversion and `get()` accessors. On Android ARM64, the predecessor
therefore emitted an acquire load for the setting:

```text
16d169c: adrp x8, ...
16d16a0: ldar w8, [x8]
16d16a4: cbz w8, ...
```

The predecessor merged core was
`CA4D4B933D35DAEA4298FEDBFE5E7D08A46437E9A7ACE1691C23655BC236C42F`,
1,304,323,264 bytes. Its `sys_timer_usleep` symbol was `0x49c` bytes.

Saved clean Windows routes report 79,952 title, 245,726 first-battle, and
258,641 Options `usleep` calls: 584,319 total calls through this setting read.

## Change

`cfg::_int` now exposes an explicit `observe()` accessor backed by the existing
relaxed `atomic_t::observe()` operation. Android `sys_timer_usleep` uses that
accessor for `usleep_addend`; desktop retains the original ordered implicit
conversion.

The value remains atomic, dynamically configurable, and read on every call. A
call may observe the adjacent old or new scalar value during a concurrent live
setting change, which is already valid for this independent per-call timing
adjustment. No dependent object state is published by this integer. Sleep
saturation, accuracy, wait ordering, notifications, title gates, fallbacks,
and syscall results are unchanged.

Official RPCS3 `master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` remains the upstream reference.
This is a local Android hot-path memory-order refinement.

## Exact ARM64 proof

The successor `sys_timer_usleep` symbol is `0x494` bytes, 8 bytes smaller. The
same dynamic setting read is now a plain load:

```text
16d1690: adrp x21, ...
16d1694: ldr  x21, [x21, #0xaa0]
16d1698: ldr  w8, [x21, #0x178c]
16d169c: cbz  w8, ...
```

The acquire loads used later for actual wait/publication synchronization remain
in the symbol. Only the independent usleep-addend load changed from `LDAR` to
`LDR`. Saved title/battle/Options routes therefore avoid 584,319 acquire
barriers in this syscall path while preserving a live atomic read per call.
This count does not claim FPS, power, or temperature improvement.

The linked RelWithDebInfo core grew 1,232 bytes because adding the inline
`cfg::_int` member changes debug/type metadata across rebuilt translation
units; the stripped core size is unchanged. The hot symbol itself shrank by 8
bytes and the packaged APK shrank by 12 bytes.

## Verification

Passed:

- Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor linked ARM64 symbol and disassembly comparison;
- source contract proving Android relaxed access, desktop ordered access, and
  `cfg::_int::observe()` forwarding to relaxed `atomic_t::observe()`;
- ThorTest ARM64-only APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK:
  `1BAA60FBCDB494539B0E015846FDFAF819A11EE799665FE96B4E9267857B65FA`,
  72,837,424 bytes.
- Merged ARM64 core:
  `22D1DDC69BB3F7E0C2DEB3038CF381D5C1B44826125C70EAEBCBF05142C64FB6`,
  1,304,324,496 bytes.
- Packaged ARM64 core:
  `8B9A104BC0FB6A3115836CD51FA3945C272409B16BC4537193093F327C7FD0A8`,
  62,989,112 bytes.
- APK native entry matches the packaged-core hash and size exactly.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, stability, power, flicker, or temperature credit.
