# Title recipes

What each title needs on the Thor, what it refused, and what is still open.

**Read the row before you spend device time.** Every entry here cost at least
one session. Two titles needed opposite fixes, so a setting that wins on one
title is not a default for the next one.

`tools/thor_game_workup.sh` triages a title and proposes settings. This file is
the memory behind it. The skill `thor-game-workup` is the procedure.

## How to read a row

- **Signature** is the profile, not a guess. Take it with `--profile`.
- **Shipped** is in `GameSettingsDatabase.kt`.
- **Refused** means measured and rejected. Do not test it again.
- **Workload** is the scene that repeats, and its measured spread.

---

## BLUS30161, Eternal Sonata

**State 2026-08-23: boots and renders at 30.00 FPS.** The SPURS boot stall
this title was known for no longer reproduces. If the debug boot is refused
with `managed-profile-not-applied` and `EACCES`, check the owner of
`config_BLUS30161.yml`: a config owned by `shell` cannot be replaced by the
app, and that looks exactly like a title that will not boot.


**State: boots, renders, and reaches gameplay through a savestate.**

| | |
| --- | --- |
| Signature | VM range locking 12.7% of all cycles. `process_mfc_cmd` 12.69%, `vm::writer_lock` 8.60%, `vm::passive_lock` 3.13%. |
| Shipped | `Accurate SPU Reservations: true`. |
| Workload | A restored savestate, 25.7 to 25.9 FPS at 3.1 cores. Spread +/-5% on cores, +/-0.6% on FPS. |
| Load | 5.26 cores in real gameplay. The intro is 3.0 cores and never leaves the 30 FPS cap. |

**Refused, with the number:**

| Lever | Result |
| --- | --- |
| `Accurate SPU Reservations: false` | -10.6% CPU, ranges apart. REVERTED on correctness, not on the number. |
| `rsx_fifo_pause_ladder=64` | Null. 1.9% worse, inside the noise. Huge reach, no benefit. |
| `vm_writer_lock` spin count | Null. |

**Reach that matters:** `spu_selfloop_park` reads about 49,000 entries per window
at `pc=0x00cc4`. This is the title the park was measured on, and it gives -45%
CPU here.

**Open:** the intro cannot show a performance change. It sits at 29.65 to 29.67
FPS across four minutes, so frames cannot move. Use the savestate.

---

## BLUS30357, Transformers: War for Cybertron

**State: boots and reaches its menus. It halts its own SPU at a rare interval.**

| | |
| --- | --- |
| Signature, before the fix | VM range locking 29.1% of all cycles. `vm::range_lock_internal` 15.37%, `vm::writer_lock` 10.69%. |
| Signature, after the fix | `vm::writer_lock` 0.63%, kernel 4.38%, JIT guest code 85.35%. The emulator now runs the game. |
| Shipped | `RSX FIFO Accuracy: Atomic`, `Driver Wake-Up Delay: 50`, `Shader Mode: Async with Shader Interpreter`, `Frame limit: 30`, `SPU Block Size: Safe`, `Accurate SPU Reservations: true`. |
| Workload | The title screen, gated. It needs no input and it is heavy: 70.7% CPU with SPU at 56.1%. Spread +/-0.2%. |

**Refused, with the number:**

| Lever | Result |
| --- | --- |
| `SPU loop detection: true` | REJECTED. Hotter. Both arms pinned at the thermal cap of 20 FPS, 2 of 2. |
| `SPU Block Size: Mega` | REJECTED. Fell to 0.70 and 1.68 FPS, 2 of 2. |
| `Preferred SPU Threads: 2` | Null. 2.614 against 2.617 cores. |
| `Accurate SPU Reservations: false` | -8.4% CPU, ranges apart. REVERTED on correctness. |
| `Driver Wake-Up Delay: 20` against 50 | 0.4% apart, ranges overlap. The delay is free and it fixes nothing. |

**Two traps this title set:**

1. **It read as slow and it was hanging.** With the default `Fast` FIFO the RSX
   thread died about 35 seconds in. The emulator did not stop: one SPU thread
   span at about 90% of the process, 0.00 FPS, 87 to 94 C, forever.
2. **A profile of the hang looked like a hot loop.** It read 90.79% in one SPU
   thread. `Frames: 0 in 10.00s` was in the log the whole time.

**Open: the SPU halt.** The guest SPURS kernel runs `HGT`, `HLGT` or `HEQ` and
stops itself at `0xffdead00`. The Dead FIFO 1.3 seconds later is downstream.

Ruled out so far:

- Our SPURS HLE. It has no semantic difference from upstream RPCS3.
- A missing SPURS limiter. It is present.
- An upstream patch. None exists.
- The wake-up delay. 12 boots at 20 and 15 boots at 50 gave no fault.
- `RSX FIFO Accuracy`. 27 boots on Atomic and 10 on Fast gave no fault.

The fault is rarer than 1 in 37 controlled boots. The trap decoder now prints
the trap name and the SPURS limiter state, so the next occurrence names itself.

---

## Folklore

**State: boots and renders at 60 FPS.**

| | |
| --- | --- |
| Workload | The title screen does NOT repeat. The same setting gave 51.0 C and 90.1 C, and process totals in two clusters 46% apart. |
| Better workload | PPU precompile with the cache cleared. The work is fixed and the emulator stamps its own clock. |

`ppu_budget_mb=4096` is 19% faster than 1536 here, for 22% more energy. On
Transformers the same lever gives nothing, because compile concurrency is heat
and the big cluster throttles near 94 C.

**Do not A/B a lever on this title screen.** Eight attempts resolved nothing.
The precompile workload resolved a 21% effect in four arms.

---

## BLUS30126

**State: dies in PPU precompile with a Scudo abort in `PPUW.1.1`.**

There is no bootable disc image here, so the title that the raised compile
budget makes riskier is the one title that cannot be tested. If a game stops
booting, this is the first thing to undo:

    adb shell setprop debug.rpcsx.thor.ppu_budget_mb 1536

---

## What the two profiled titles prove together

**There is no shared lever.** Eternal Sonata was reservation bound and VM-lock
bound. Transformers was too, at more than double the share, and after the fix it
is guest code bound. The self-loop park is worth 45% on one title and reads
`entries=0` on the other.

**Profile the title. Do not copy a recipe.**
