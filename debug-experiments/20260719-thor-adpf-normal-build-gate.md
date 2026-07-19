# Thor normal-build ADPF experiment removal

Date: 2026-07-19
Status: host-verified `stackable-cpu-pressure`; device-unmeasured

## Problem

The Android RSX Performance Hint experiment defaults off, but normal builds
still called `adpf_rsx_hint::requested()` from every Vulkan
`VKGSRender::begin()` and `VKGSRender::flip()`. Its function-local static
made the property read one-time, yet the steady default-off path still executed
a guard load/branch plus an enabled-value load/branch at both hot boundaries.

The hint remains unproven on Thor. Paying its selection overhead in every normal
draw and present conflicts with the current priority of removing unnecessary
CPU work and heat rather than merely asking Android for different scheduling.

## Change

- Added default-off build option `RPCSX_THOR_ADPF_RSX_HINT`.
- Normal Android exposes compile-time-false `requested()` and no-op
  `begin()/finish()`, allowing both callsite blocks to disappear.
- Explicit diagnostic builds retain the complete API-29-safe dynamic
  `libandroid.so` path, power-efficiency preference, timing, reporting,
  title gate, failure shutdown, and runtime property control.
- Opt in only for a diagnostic artifact with
  `-PrpcsxThorAdpfRsxHint=true` or
  `RPCSX_THOR_ADPF_RSX_HINT_BUILD=true`.
- Desktop behavior is unchanged.

## Binary evidence

Baseline normal ARM64 core:

- size: 1,304,708,688 bytes;
- `VKGSRender::begin()`: 1,000 bytes;
- `VKGSRender::flip()`: 10,224 bytes;
- six ADPF state/guard symbols: 97 bytes;
- three ADPF helper functions: 596 bytes;
- ten selected property, API, and report strings present.

Normal gated ARM64 core:

- size: 1,304,691,384 bytes (`-17,304`);
- `VKGSRender::begin()`: 164 bytes (`-836`, `-83.6%`);
- `VKGSRender::flip()`: 9,416 bytes (`-808`, `-7.90%`);
- the two hot functions total 11,224 -> 9,580 bytes (`-1,644`);
- no selected ADPF symbol or string remains.

The explicit diagnostic ARM64 build passed in 814.7 seconds. It retained
`property_requested()`, the property/API strings, and the original
1,000/10,224-byte hot functions. The final normal ARM64 build passed in
786.8 seconds.

## Verification

- All 54 Thor contracts pass, including the strengthened ADPF build-gate test.
- The final core retains 34 defined dynamic symbols, 587 explicit relocations,
  391 `JUMP_SLOT` relocations, 44,155 encoded relocation bytes, and all 13
  active Eternal Sonata frame-poll symbols.
- `git diff --check` passes.
- Official RPCS3 was refreshed from `a7d90852d` to `357b7d446`. The only
  two new commits were an unused-argument warning annotation in
  `SPURecompiler.h` and VFS exception source-location metadata; neither is a
  Thor runtime optimization.

## Device boundary

No APK was assembled or installed for this change, and no ADB query, launch,
screenshot, or device workload occurred. The previously installed exact APK
`7CDD38E4...E5F9` remains force-stopped. No FPS, temperature, flicker,
gameplay, or runtime-stability credit is claimed.

## Decision

Keep the normal-build gate. It removes unproven experiment selection work from
every Vulkan draw/present while retaining a separately buildable diagnostic
path for the future matched ADPF A/B.
