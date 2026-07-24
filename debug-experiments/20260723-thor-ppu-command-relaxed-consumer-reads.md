# Thor PPU command relaxed consumer reads

Date: 2026-07-23

## Outcome

Android PPU asynchronous-command consumers now read their FIFO position and
already-published command tails with relaxed atomics. Generic `lf_fifo::peek`,
desktop PPU behavior, command-head publication/acquisition, and release-only
FIFO completion remain unchanged.

This is host-verified `stackable-cpu-pressure`. It removes acquire barriers
from command polling, tail-position lookup, tail loads, and completion-position
lookup while retaining the authoritative acquire on the command head. It is
not a measured FPS, temperature, power, flicker, gameplay, stability, or
end-to-end speed result.

## Single-consumer and payload-ordering proof

Each `ppu_thread` owns one command queue. Repository-wide callsite inspection
found command consumption only in `ppu_thread::cpu_task` and
`fs_aio_thread::non_task`; each loop calls `cmd_wait`, optionally reads tails
through `cmd_get`, and then calls `cmd_pop` on that same owning thread.
Producers call reservation/publication paths but never consume the pop counter.

The FIFO control word carries positions, not element readiness:

1. producers atomically reserve unique low-half push-counter ranges;
2. producers write command tails and release-publish the head last;
3. `cmd_wait` indexes the consumer-owned high-half pop counter and acquires the
   head with `exchange(cmd64{})`;
4. only after that acquire may `cmd_get` read published tails;
5. `cmd_pop` clears tails and release-completes the range before any slot can be
   reused.

The high-half position is modified only by the consumer's completion CAS, so
its reads need atomic coherence but no acquire ordering. A relaxed load after
the consumer's own prior completion cannot move before that sequenced-before
operation, and concurrent producer changes to the low half do not change the
selected pop index.

Command tails are covered by the producer's release head store and the
consumer's acquire head exchange. They remain reserved until the later release
completion, so relaxed post-head tail loads cannot race with slot reuse. The
head exchange deliberately remains `SWPAL`, and the completion deliberately
remains `CASL`.

`lf_fifo::peek_relaxed` exists only under `#ifdef __ANDROID__`. A PPU member
helper selects it on Android and retains generic `peek()` on desktop;
`cmd_get` similarly selects `observe()` only on Android and retains `load()` on
desktop. The focused contract locks all three consumer position sites, the
post-head tail access, the upstream baseline, and every existing reservation,
publication, completion, and notification invariant.

## Exact ARM64 proof

Immediate predecessor merged core
`8E486141D81AE27EFB7110A7DD0EF019EB4CF23410C0173FBB44A8E845BD0807`
used acquire position and tail reads:

```text
353cee8: ldar  x8, [x8]              // cmd_wait position
353cf04: swpal xzr, x26, [x8]        // command-head acquire
...
353d80c: ldar  x8, [x8]              // cmd_get tail
353d830: ldar  x8, [x8]              // cmd_get position
...
353d0cc: ldar  xzr, [x8]             // cmd_pop position
353d0d0: ldr   x10, [x19, #0x970]    // completion control
353d0f0: casl  x9, x11, [x8]         // release completion
```

Successor merged core
`39F1C9BF94F17A1E29F1CEC32B7DB20B1EFDA9C0464C60DA5B7ECFE62BE30143`
uses ordinary atomic loads while retaining the synchronization points:

```text
353cee4: ldr   x8, [x19, #0x970]     // cmd_wait position
353cf00: swpal xzr, x26, [x8]        // command-head acquire retained
...
353d7e8: ldr   x8, [x8, x10, lsl #3] // cmd_get tail
353d804: ldr   x8, [x19, #0x970]     // cmd_get position
...
353d0a8: ldr   xzr, [x19, #0x970]    // cmd_pop position
353d0ac: ldr   x9, [x19, #0x970]     // completion control
353d0d4: casl  x8, x10, [x11]        // release completion retained
```

`ppu_thread::cpu_task` shrank from `0x1ecc` to `0x1ec4` bytes.

## Verification

- Focused `tools/test_thor_ppu_command_publication.ps1` reservation,
  publication, consumer-read, completion, clear, upstream, and desktop
  contracts passed.
- ARM64 native build returned `BUILD SUCCESSFUL`.
- ARM64-only Thor APK packaging returned `BUILD SUCCESSFUL`.
- Exact merged ARM64 disassembly confirmed `LDAR -> LDR` for the targeted
  position/tail reads, retained `SWPAL` head acquisition, and retained `CASL`
  completion.
- All `69/69` non-artifact host contracts passed before repinning.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed after repinning.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.

Exact host artifacts:

- APK: `D5F2E5BB69768E327005BB3BA75A039079599E1E47FD93AEFCD0703B9ED4ADD0`,
  `72,838,084` bytes.
- Merged core: `39F1C9BF94F17A1E29F1CEC32B7DB20B1EFDA9C0464C60DA5B7ECFE62BE30143`,
  `1,304,308,552` bytes.
- Stripped/packaged core:
  `59F25E23860475F39E505738DBB85BF733B127E45B5D6C191C99FBC509EB9853`,
  `62,989,000` bytes.

## Device status

Thor was not contacted: no ADB query, install, launch, temperature poll, wait,
or device load occurred. A later explicitly authorized, independently cool
field/menu/battle comparison remains required before any measured speed,
stability, flicker, or thermal credit.
