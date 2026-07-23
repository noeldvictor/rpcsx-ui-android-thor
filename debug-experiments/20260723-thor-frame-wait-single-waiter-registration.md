# Thor frame-wait single-waiter registration

Date: 2026-07-23

## Outcome

The Android Eternal Sonata VBlank-assisted frame-poll path no longer performs
two sequentially consistent read-modify-write operations for every bounded
wait. Its existing title, main-PPU, call-site, object, divisor, counter,
one-millisecond timeout, handler-completion, grace, continuous-rearm, and
fallback gates are unchanged.

This is host-verified `stackable-cpu-pressure` work. It is not a measured FPS,
temperature, power, flicker, gameplay, or end-to-end speed result.

## Why this is dynamically relevant

Only the exact main PPU (`0x01000000`) can enter the optimized path. No other
source site registers a VBlank waiter, and the RSX side only needs to know
whether that one PPU is registered.

The saved correctness-clean continuous-rearm routes reached:

- title: 34,542 event waits, formerly 69,084 waiter-counter RMW operations;
- first battle: 105,145 event waits, formerly 210,290 RMW operations;
- Options: 33,484 event waits, formerly 66,968 RMW operations.

The count therefore provided no extra semantics while repeatedly issuing
cache-coherent RMW traffic between the main PPU and RSX/VBlank threads.

## Change

- `atomic_t<u32> vblank_waiters` became the explicit single-waiter
  `atomic_t<bool> vblank_waiter_registered`.
- The main PPU registers and clears that flag with release stores.
- RSX/VBlank checks remain acquire loads through `atomic_t<bool>`.
- The 32-bit completion token, acquire token reads, handler-ordered increment,
  notification, one-millisecond bound, and original fallback remain intact.
- The Windows comparison tree remains unchanged; this optimization is scoped
  to the Android/Thor vendored core.

The focused contract now locks the single-waiter type, release-store protocol,
absence of the Android RMW waiter counter, completion ordering, and all prior
safety gates.

## ARM64 code-generation proof

The previous ARM64 object emitted two `LDADDAL` instructions in
`sys_timer_usleep`, one for registration and one for deregistration. The exact
successor emits:

```text
STLRB w8,  [x23]
...
STLRB wzr, [x23]
```

There is no waiter-registration `LDADDAL` left in the linked function. The
function shrank from `0x6f4` to `0x6f0` bytes. The completion-token loads
remain `LDAR`, preserving the synchronization that makes guest handler writes
visible before the counter is checked.

## Verification

- `tools/test_thor_es_frame_poll_wait.ps1`: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest APK build: passed.
- Exact merged-core disassembly: two `STLRB`, zero waiter `LDADDAL`.
- All `69/69` `tools/test_thor_*.ps1` host contracts: passed.
- `git diff --check`: passed.

Exact host-only successor:

- APK: `A02338006A7E1ADB718751B5C79003CBF000C02D65B680B0596E3143D2455045`,
  72,838,240 bytes.
- merged ARM64 core:
  `8083882174649FC66F828C9DBD8AEBCEB26F1D3288BF16AC4B48FFF5F58E636D`,
  1,304,307,480 bytes.
- packaged ARM64 core:
  `2EFCB6B3B4D2E36B29E7F09CA6CF730875D6BCEC8D86EF742A86461E1647C32D`,
  62,988,904 bytes.

No ADB query, install, launch, or temperature poll occurred. The APK is
host-built and device-unmeasured.
