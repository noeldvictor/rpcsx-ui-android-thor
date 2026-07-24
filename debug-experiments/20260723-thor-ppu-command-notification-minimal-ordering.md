# Thor PPU command notification minimal ordering

Date: 2026-07-23

## Outcome

Android PPU asynchronous-command notification now uses the minimum ordering
needed on both sides of the level-triggered wake flag:

- every command producer release-stores `cmd_notify = 1` after the queue head,
  then calls `notify_one`;
- the command consumer atomically clears `cmd_notify = 0` with relaxed ordering
  after `atomic_wait_engine::wait` returns.

The queue head remains the authoritative payload publication. Desktop retains
its original sequentially consistent notification stores/clear. The separate
interrupt-disestablish consumer exchange is unchanged.

This removes two remaining Android `SWPAL` producer exchanges and the consumer
clear's `STLR` barrier. It is host-verified `stackable-cpu-pressure`, not a
measured FPS, temperature, power, flicker, gameplay, stability, or end-to-end
speed result.

## Ordering proof

### Producer publication

Each producer calls `cmd_list` before `notify_cmd_ready`. `cmd_list` writes raw
command tails, then release-publishes the command head. Android
`notify_cmd_ready` release-stores the level flag and then wakes one waiter. The
second release store preserves queue-head-before-flag-before-wake ordering.

`sys_ppu_thread_start` and `lv2_int_serv::join` previously duplicated a
sequentially consistent `cmd_notify.store(1)` plus `notify_one`. Routing both
through the existing helper preserves their order and wake behavior while
removing the unused old-value/acquire half on Android. The helper's desktop
branch remains the original sequentially consistent store.

### Consumer clear

The wake flag carries no command payload and no producer consumes data from its
zero value. `atomic_wait_engine::wait` compares the flag atomically and returns
to `cmd_wait`, which clears the flag and immediately retries the authoritative
command-head acquire exchange.

The clear therefore needs atomicity and modification order, but neither acquire
nor release ordering:

- if the relaxed clear precedes a producer's release store, the producer leaves
  `1` and notifies;
- if the clear follows a producer's flag store, that producer has already
  release-published its queue head, and the immediate `SWPA` head RMW consumes
  the newest head modification;
- if another queued command exists, the consumer probes its reserved head
  before waiting again;
- queue-slot reuse remains ordered independently by `CASL -> LDADDA`.

A relaxed atomic store is therefore sufficient for the payload-free clear.
Producer flag stores remain release operations because they order queue
publication before wake visibility.

## Exact ARM64 proof

Immediate predecessor merged core
`888767BB876410E18D669509FD4C7F67AEDF8F71BEA5E236C76EF3F3746869E9`
used a release clear and two sequentially consistent producer exchanges:

```text
353cee0: stlr  wzr, [x20]       // consumer clear
168a140: swpal w8, w8, [x0]     // sys_ppu_thread_start producer
164b2bc: swpal w9, w8, [x8]     // lv2_int_serv::join producer
```

Successor merged core
`C354674DA1213F5F5D660BF48B99440529EF3B901712A99EAD164D305EC94B66`
emits:

```text
353cea0: str   wzr, [x20]       // relaxed consumer clear
168a140: stlr  w8, [x0]         // release producer
164b2bc: stlr  w8, [x0]         // release producer
```

The separate interrupt-disestablish consumer retains its `SWPAL` at
`0x164bef4`. The PPU queue data handoffs remain:

```text
3540ad0: ldadda x9, x23, [x8]   // acquire slot reuse
3540bcc: stlr   x9, [x8]        // release payload publication
353cec0: swpa   xzr, x26, [x8]  // acquire payload consumption
353d094: casl   x8, x10, [x11] // release slot completion
```

`ppu_thread::cpu_task` remains `0x1ec4` bytes.

## Verification

- Focused `tools/test_thor_ppu_command_publication.ps1` requires the relaxed
  clear, both helper-routed producers, the Android release/desktop default
  split, and the complete queue-handoff contract.
- Optimized ARM64 native build returned `BUILD SUCCESSFUL`.
- ARM64-only Thor APK packaging returned `BUILD SUCCESSFUL`.
- Exact merged ARM64 disassembly confirmed `STR`, both producer `STLR`s, and
  retained `LDADDA/STLR/SWPA/CASL` data handoffs.
- All `69/69` non-artifact host contracts passed before repinning.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed after repinning.

Exact host artifacts:

- APK: `130CDBBA591C4675F55A8290C9CF292C78DB81E1B902AADAD235A4686B6D6DD8`,
  `72,837,756` bytes.
- Merged core: `C354674DA1213F5F5D660BF48B99440529EF3B901712A99EAD164D305EC94B66`,
  `1,304,307,216` bytes.
- Stripped/packaged core:
  `18F720A84344E9C5B334A585078973A48AE6AB5181280137227B59765E8B3756`,
  `62,988,856` bytes.

## Device status

Thor was not contacted: no ADB query, install, launch, temperature poll, wait,
or device load occurred. A later explicitly authorized, independently cool
field/menu/battle comparison remains required before any measured speed,
stability, flicker, or thermal credit.
