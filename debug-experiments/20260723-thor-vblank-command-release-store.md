# Thor VBlank command release store

Date: 2026-07-23

## Outcome

The Android HLE VBlank-handler path now publishes `cmd_notify = 1` with a
release atomic store instead of a sequentially consistent atomic swap whose
old value was discarded. Desktop retains the original store. The queued PPU
command, wake, handler execution, completion token, one-waiter notification,
and all fallbacks are unchanged.

This is host-verified `stackable-cpu-pressure` work. It removes a needless
read-modify-write and acquire barrier from a repeated cross-thread wake path.
It is not a measured FPS, temperature, power, flicker, gameplay, stability, or
end-to-end speed result.

## Queue and consumer audit

`ppu_thread::cmd_list` reserves queue space, writes command-tail entries, then
atomically publishes the command head. `cmd_notify` is a level-triggered wake
hint, not ownership of the command payload.

The two consumer forms are safe with release publication:

- `ppu_thread::cmd_wait` exchanges the atomic command head before waiting,
  waits on `cmd_notify`, clears it, then rechecks the command head;
- the interrupt-service loop uses `cmd_notify.exchange(0)` before waiting and
  re-enters its service/queue checks after wake.

The VBlank producer never uses the previous notify value. Multiple producers
may all store `1`; the queue recheck is the authoritative lost-wake defense.
Release ordering is sufficient to make preceding queue writes visible to the
consumers' existing atomic operations.

Saved correctness-clean routes contain 2,703 title, 8,719 first-battle, and
2,704 Options VBlank edges. When the HLE VBlank handler is active, its command
publication can occur once per edge.

## Change

`publish_vblank_command_ready()` is inlined at the HLE VBlank handler site:

- Android calls `notify.release(1)`;
- non-Android retains `notify.store(1)`.

The focused contract requires command queueing before release publication,
publication before `notify_one`, and unchanged upstream behavior. It rejects a
direct sequentially consistent store inside `post_vblank_event`.

## Exact ARM64 proof

Predecessor merged core
`4683AB54D3448CF9E166027693298831D7B3D53FB669D2EABC82C83A7D9E7724`
emitted an acquire-release swap for the command-ready flag:

```text
3835a10: swpal w9, w8, [x8]
```

Successor merged core
`7CA9F1D9B0D33BC1C17FBA26A6B8E4E0F29ED9017E2891211BA7B5CCA41666A8`
emits a release store:

```text
3835934: ldaddl x9, x8, [x8]
38359a4: ldaddl w8, w8, [x0]
38359a8: bl   0x15a4020 <atomic_wait_engine::notify_one>
3835a10: stlr w9, [x8]
3835a1c: bl   0x15a4020 <atomic_wait_engine::notify_one>
```

The first three lines retain the prior raw-edge and completion publication.
The final two lines prove release command publication followed by the existing
wake. `post_vblank_event` remains `0x120` bytes. `sys_timer_usleep` retains its
prior `0x6ec` size and one grace-accessor call.

## Verification

- Focused frame-poll/command-order contract: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact packaged-core `SWPAL -> STLR` disassembly: passed.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `69/69` Thor host contracts: passed before documentation and repeated
  before commit.
- `git diff --check`: passed.

Exact host-only successor:

- APK: `5C949AB5CB4F5A1CFC5F3BE227BF726E1FD183454D7991FF823AE90E4B8AE185`,
  72,838,236 bytes.
- merged ARM64 core:
  `7CA9F1D9B0D33BC1C17FBA26A6B8E4E0F29ED9017E2891211BA7B5CCA41666A8`,
  1,304,307,992 bytes.
- packaged ARM64 core:
  `FFA11A60863F1A68D1FAE837762D4EBB52F59598411730950F64C7871F2DD099`,
  62,988,904 bytes.

No ADB query, install, launch, temperature poll, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
