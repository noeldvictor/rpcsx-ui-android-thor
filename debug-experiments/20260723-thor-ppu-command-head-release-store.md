# Thor PPU command-head release store

Date: 2026-07-23

## Outcome

Android now publishes each asynchronous PPU command queue head with a release
store instead of a sequentially consistent atomic exchange. This applies to
both `ppu_thread::cmd_push` and `ppu_thread::cmd_list`; desktop retains the
original store behavior.

This is host-verified `stackable-cpu-pressure`. It removes an unnecessary
read-modify-write and acquire barrier from the common PPU asynchronous-command
publication path, including RSX VBlank, flip, and user callbacks. It is not a
measured FPS, temperature, power, flicker, gameplay, stability, or end-to-end
speed result.

## Synchronization contract

`lf_fifo::push_begin` atomically reserves a unique queue range. `cmd_list` then
writes every command tail through relaxed raw stores and publishes the head
last. The consumer treats a zero head as not ready and consumes a published
head with `cmd_queue[cmd_queue.peek()].exchange(cmd64{})`.

The Android head release store therefore synchronizes with the consumer's
acquiring exchange and makes all preceding tail writes visible. No producer
uses the old head value, so a read-modify-write is unnecessary. Multi-producer
ordering remains controlled by the FIFO reservation positions, and the
consumer cannot advance past an unpublished zero head. `cmd_push` follows the
same single-head contract without a tail.

The helper is Android-specific:

- Android: `slot.release(command)`;
- desktop: unchanged `slot = command`;
- exactly two helper calls cover `cmd_push` and `cmd_list`;
- the queue consumer remains the original atomic exchange.

The vendored tree contains 18 `cmd_list` references and the active source
callers include the HLE VBlank callback, RSX flip handler, GCM flip command,
RSX user command, interrupt service, and PPU thread startup paths. This makes
the queue head a more general publication point than any individual callback
flag.

## Exact ARM64 proof

Predecessor merged core
`796BBF971578D96F8FF55B23600914A2D761DC50F039301731CE4FA2FEAD7303`
published the `cmd_list` head with an atomic swap:

```text
3540b44: ldr   x9, [x19]
3540b48: add   x8, x8, x10, lsl #3
3540b4c: swpal x9, x8, [x8]
```

Successor merged core
`F128D577451F1A734EAFE6F26A6FAA9BAA046DE96BB4199F5FEF213E83EC5B01`
publishes the same head with a one-way release store:

```text
3540b44: ldr  x9, [x19]
3540b48: add  x8, x8, x10, lsl #3
3540b4c: stlr x9, [x8]
```

The tail remains a normal `STR` at `0x3540a74`, before the release head. The
consumer source remains the atomic `exchange(cmd64{})` acquisition.

## Verification

- Focused contract: `tools/test_thor_ppu_command_publication.ps1` passed.
- Optimized ARM64 native build passed in 65 seconds:
  `./gradlew.bat :app:buildCMakeRelWithDebInfo[arm64-v8a]`.
- ARM64-only Thor APK packaging passed in 9 seconds:
  `./gradlew.bat :app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a -PbuildBundledRpcsxCore=true`.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.

Exact host artifacts:

- APK: `AB4803B7E0C41A1DB2C7C08730C20A788A25CBA153075FD18CFB7F0C5E93614F`,
  `72,838,396` bytes.
- Merged core: `F128D577451F1A734EAFE6F26A6FAA9BAA046DE96BB4199F5FEF213E83EC5B01`,
  `1,304,307,280` bytes.
- Stripped/packaged core:
  `29C2A237F2D1CBA4DFCEED11FE111ED56CF932BACF6C68978C0AADAC6F85E337`,
  `62,988,904` bytes.

## Device status and next action

Thor was not contacted: no ADB query, install, launch, polling, wait, or thermal
load occurred. The candidate remains host-only. A later explicitly authorized,
independently cool field/menu/battle comparison is still required before any
measured speed, stability, flicker, or thermal credit.

The remaining direct sequentially consistent RSX command-ready stores in
`rsx_methods.cpp` are a separate candidate. Audit and change them independently
so queue-head and wake-flag effects remain bisectable.
