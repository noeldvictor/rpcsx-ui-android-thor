# Thor VBlank edge release publication

Date: 2026-07-23

## Outcome

The Android VBlank thread now publishes the 64-bit monotonic `vblank_count`
edge with a release atomic increment instead of a sequentially consistent
increment. Desktop retains the original increment. Every live reader remains
an acquire load, the completion token remains independently release-published,
and all frame-poll and flip behavior is unchanged.

This is host-verified `stackable-cpu-pressure` work. It removes the unused
acquire half of one atomic RMW per VBlank. It is not a measured FPS,
temperature, power, flicker, gameplay, stability, or end-to-end speed result.

## Writer and reader audit

Repository-wide source inspection finds one live increment producer:
`vblank_thread` calls `rsx::thread::post_vblank_event`, whose first operation
publishes the edge. The other writes are reset/deserialization operations
outside the live VBlank producer phase.

Live readers are:

- three observations in the exact BLUS30161 frame-poll wait/fallback path; and
- two observations in PS3 frame-limit flip handling.

The producer consumes no state through `vblank_count`, so acquire ordering on
the increment cannot make any later producer work visible. Release ordering
retains publication of preceding VBlank-thread work, atomic modification order,
and synchronization with the existing acquire readers.

Saved correctness-clean routes show this is repeated:

- title: 2,703 VBlank edges;
- first battle: 8,719 VBlank edges;
- Options: 2,704 VBlank edges.

## Change

`publish_vblank_edge()` is inlined at the sole live increment site:

- Android uses `__atomic_fetch_add(..., __ATOMIC_RELEASE)`;
- non-Android retains `count++`.

The focused contract locks the helper, release ordering, call site, absence of
a direct Android sequentially consistent increment, and unchanged upstream
behavior.

## Exact ARM64 proof

Predecessor merged core
`D0A038D4E681CC97CF76E4E021D377854D0AC1CD1054A0966BAFB32B3C2051C0`
emitted a sequentially consistent 64-bit edge increment:

```text
3835934: ldaddal x9, x8, [x8]
```

Successor merged core
`4683AB54D3448CF9E166027693298831D7B3D53FB669D2EABC82C83A7D9E7724`
emits release-only publication:

```text
3835934: ldaddl x9, x8, [x8]
38359a4: ldaddl w8, w8, [x0]
38359a8: bl 0x15a4020 <atomic_wait_engine::notify_one>
```

The second line is the independent 32-bit completion token retained from the
prior successor. Exact flip readers remain acquire loads at `0x383725c` and
`0x38373b4`. The packaged `sys_timer_usleep` also retains the prior `0x6ec`
size and one grace-accessor call site.

## Verification

- Focused frame-poll wait contract: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact packaged-core producer/reader disassembly: passed.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `69/69` Thor host contracts: passed before documentation and repeated
  before commit.
- `git diff --check`: passed.

Exact host-only successor:

- APK: `64A44CA9AE6176D7E5B54D869058351996FFBF6975C8673855799880BFACCE39`,
  72,838,240 bytes.
- merged ARM64 core:
  `4683AB54D3448CF9E166027693298831D7B3D53FB669D2EABC82C83A7D9E7724`,
  1,304,307,864 bytes.
- packaged ARM64 core:
  `74D21D344267967A98C3DD79D19999C8FDE790B55FED0BE6F68D7DF3A3F55F8C`,
  62,988,904 bytes.

No ADB query, install, launch, temperature poll, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
