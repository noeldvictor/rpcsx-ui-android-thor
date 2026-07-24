# Thor RSX flip command release store

Date: 2026-07-23

## Outcome

The Android RSX flip-handler path now uses the same release-store PPU command
publication as the HLE VBlank-handler path. Both paths queue their command,
release-store `cmd_notify = 1`, then call `notify_one`. Desktop retains both
original sequentially consistent stores.

This is host-verified `stackable-cpu-pressure` work. It removes a second
needless read-modify-write and acquire barrier from a per-frame RSX-to-PPU
command path. It is not a measured FPS, temperature, power, flicker, gameplay,
stability, or end-to-end speed result.

## Shared synchronization contract

The preceding VBlank command audit proved the PPU command queue head is the
authoritative atomic publication and consumers exchange/recheck either the
command head or notification flag after wake. The flip handler uses the same
`intr_thread`, `cmd_list`, `cmd_notify`, and `notify_one` protocol.

The helper is therefore generalized from `publish_vblank_command_ready` to
`publish_ppu_command_ready` and used at exactly two RSX producer sites:

- `rsx::thread::post_vblank_event` for the HLE VBlank handler;
- `rsx::thread::handle_emu_flip` for the guest flip handler.

The focused contract requires exactly two Android helper calls, queue-before-
store-before-wake ordering at both sites, absence of direct RSX sequentially
consistent stores, and exactly two unchanged desktop stores.

The flip handler is a per-submitted-frame path when the guest handler is
active. Saved clean routes run at 60 FPS for title/Options and 30 FPS for field
and first battle, but this round did not add an intrusive dynamic flip-callback
counter.

## Exact ARM64 proof

Predecessor merged core
`7CA9F1D9B0D33BC1C17FBA26A6B8E4E0F29ED9017E2891211BA7B5CCA41666A8`
already had a release store for the VBlank command, but the flip command still
used a sequentially consistent swap:

```text
3835a10: stlr  w9, [x8]
3837398: swpal w24, w8, [x8]
```

Successor merged core
`796BBF971578D96F8FF55B23600914A2D761DC50F039301731CE4FA2FEAD7303`
uses release stores at both sites:

```text
3835a10: stlr w9, [x8]
3835a1c: bl   0x15a4020 <atomic_wait_engine::notify_one>
383738c: bl   0x3540a20 <ppu_thread::cmd_list>
3837398: stlr w24, [x8]
38373a4: bl   0x15a4020 <atomic_wait_engine::notify_one>
```

The flip sequence proves queue, release publication, then wake. The prior
release VBlank edge/completion token and one grace-accessor call remain intact.

## Verification

- Focused frame-poll/RSX command-order contract: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact packaged-core two-`STLR` disassembly: passed.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `69/69` Thor host contracts: passed before documentation and repeated
  before commit.
- `git diff --check`: passed.

Exact host-only successor:

- APK: `E8B84EAAB9AA8B9C0019DF93917BDD0D4C5F6D11EA30C4F01A84B51C8D867100`,
  72,838,236 bytes.
- merged ARM64 core:
  `796BBF971578D96F8FF55B23600914A2D761DC50F039301731CE4FA2FEAD7303`,
  1,304,307,912 bytes.
- packaged ARM64 core:
  `FB5329EFB3A63C244FB45B4BEAF2DC4C4BE49061C46A20383DF884F4E0771FFA`,
  62,988,904 bytes.

No ADB query, install, launch, temperature poll, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
