---
name: thor-game-workup
description: Triage and then speed up ANY PS3 title on the Thor, title-agnostic, by hand or through the `thor` MCP tools (thor_state, thor_boot, thor_sample, thor_press). Use when a game does not boot, hangs, crashes, runs slow, or gets hot, and when you must decide which lever to try next from a profile. Use before you sweep settings, and use it to avoid a repeat of an experiment this repo already did.
---

# Thor Game Workup

## Scope

Use this skill to answer two questions about one title, in this order:

1. Does the title work?
2. If it works, what makes it faster?

**The order is not a preference.** This project measured Transformers for a week
as a slow title. It was a hanging title. Every number from that week described a
dead emulator.

This skill is title-agnostic. The older skills in `.agents/skills/` are for
Eternal Sonata (`BLUS30161`) or for one subsystem. Compose with them:

- `thor-measurement-validity` decides if a number is valid. This skill decides
  what to do next.
- `thor-adb-operator` for device access rules.
- `thor-experiment-ledger` to record the result.
- `ps3-speed-proof-gate` before you call a result a win.

## The one command

    tools/thor_game_workup.sh BLUS30357 "/storage/.../game.iso"
    tools/thor_game_workup.sh --repeats 3 --profile BLUS30161 "/storage/.../es.iso"

It does the preflight, boots the title, names the failure, and stops. With
`--repeats` it also measures the steady state and prints the noise floor of the
rig. It proposes settings. It never writes a game profile.

## Step 1. Triage: name the failure

**Do not say "it does not work". Name the cause.** Each row below is a failure
this repo diagnosed on the device. The tool tests them in this order.

| Signal in the log | Cause | What to do |
| --- | --- | --- |
| no log file | instrument fault | The boot intent failed. Say nothing about the game. |
| `Force stopping` more than once in logcat | another session kills our package | Stop. The measurement is void. An external kill leaves NO crash signature. |
| `0xffdead` | the guest halted its own SPU | A guest assertion. Read the trap tag. NOT a settings problem. |
| `Dead FIFO` | the RSX queue died | Try `RSX FIFO Accuracy: Atomic`. Look for an SPU trap first. |
| `Scudo` | PPU precompile ran out of memory | Set `ppu_budget_mb` to 1536. It is concurrency, not footprint. |
| `Still waiting for a Surface` | the screen was asleep | Run `svc power stayon true`. A 0x0 SurfaceView makes no surface. |
| `Fatal signal` | native crash | Read the signal and the thread. |
| process gone, no signature | a guard page killed it | ART reads guest registers as an `ArtMethod*`. Check the SPU scratchpad size. |
| 0 FPS and `LLVM: Compiling module` | precompile is not complete | Wait. A cold large EBOOT can take ten minutes. |
| 0 FPS, high CPU, no error | hang | This is the Transformers shape. It reads as slow until you count frames. |
| low FPS and `Compiling shaders` | shader stall | Use `Shader Mode: Async with Shader Interpreter`. |

### The trap tags

An SPU fault at `0xffdeadXX` is an emulator trap. The recompiler writes a tag
there to report an illegal condition. The handler decodes it and prints the
SPURS state with it.

| Address | Tag | Meaning |
| --- | --- | --- |
| `0xffdead00` | `HALT` | The guest ran `HGT`, `HLGT` or `HEQ` and stopped itself. |
| `0xffdead04` | `TAG` | An illegal MFC tag update. |
| `0xffdead20` | `BIJT` | An external tail call in a true function. |
| `0xffdeadf0` | - | An invalid MFC slot. |

**A `HALT` is the guest's own assertion.** The emulator gave the guest something
it did not expect. Do not sweep settings for it. Read the SPURS state line.

## Step 2. Prove the workload before you measure it

**A negative result needs a workload that could have produced a positive one.**
Two checks, both cheap:

1. **Is it capped?** A flat 29.6x in every sample means the frames cannot move.
   Read the CPU, or take the cores away with `tools/thor_starve_ab.sh`.
2. **Is it loaded?** Compare the cores busy against real gameplay for that title.
   A workload at half load hides a regression.

Workload quality, measured on this device:

| workload | spread of ONE configuration |
| --- | --- |
| PPU precompile, cache cleared | best, the work is fixed and self-timed |
| gated title screen | +/-0.2% |
| restored savestate | +/-5% |
| button presses through cutscenes | about +/-50%, unusable |

**Prefer a workload with fixed, finite work.** Precompile has a natural unit and
the emulator stamps its own clock. A free-running scene has no unit.

## Step 3. Profile, then pick the lever from the profile

**Do not pick a lever from a manual.** Ten manual-derived predictions were
measured here and ten were refuted. Profile first, then read this table.

| Hot in the profile | What it means | Lever to try |
| --- | --- | --- |
| `vm::range_lock_internal`, `vm::writer_lock` | reservation contention | `Accurate SPU Reservations: false`. It is a CORRECTNESS setting. Propose only. |
| `spu_thread::process_mfc_cmd` | SPU DMA | The MFC path. No shipped lever yet. |
| `rsx::thread::run_FIFO`, `sched_yield` | the RSX starves | Read the FIFO accuracy. Every park lever failed here. Do not build a sixth. |
| `vk::wait_for_event`, Turnip | the GPU is the limit | CPU levers cannot help. Stop. |
| JIT code (`unknown`) dominant | the emulator runs the game | Lock tuning is finished. Look at code generation. |
| `iso_dev::read_dir` | ISO directory reads | The directory cache covers this. |
| `memcpy_opt` | bulk copies | Price it first. 3.1% of 5.19% is 0.16%. |

**`unknown[+X]` is the JIT arena, not a symbol.** All recompiled guest code
collapses onto one entry. Never quote a percentage against it as a function.

**Read the log for a fatal error before you read a profile.** One capture here
read 90.79% in one SPU thread. The RSX had died 35 seconds earlier.

## Step 4. What this repo already tried

**Per title, read [`docs/arm64/title-recipes.md`](../../../docs/arm64/title-recipes.md)
first.** It gives the profile signature, the shipped settings, and every lever
each title refused, with the number. Two titles needed opposite fixes, so a
setting that wins on one title is not a default for the next one.

The table below is the global list. **Read it before you spend device time.**
Each row cost at least one session.

| Lever | Result |
| --- | --- |
| `lv2_spin=0` | SHIPPED. 69% less PPU thread CPU. |
| `spu_selfloop_park=100` | SHIPPED. 45% less CPU on Eternal Sonata. `entries=0` on other titles. |
| `getllar_busy_percent=0` | SHIPPED. 9% less CPU. |
| `ppu_budget_mb=4096` | SHIPPED. 19% faster precompile for 22% more energy. |
| `RSX FIFO Accuracy: Atomic` | SHIPPED for Transformers. It stops the Dead FIFO symptom. |
| `Accurate SPU Reservations: false` | Measured -10.6% and -8.4%. REVERTED on correctness. |
| `SPU loop detection: true` | REJECTED. Hotter, 2 of 2 arms hit the thermal cap. |
| `SPU Block Size: Mega` | REJECTED. Fell to 0.70 and 1.68 FPS. |
| `Preferred SPU Threads: 2` | Null. |
| RSX FIFO park, all five forms | REJECTED. Every form trades frames for CPU. |
| `rsx_fifo_pause_ladder` | Null, and 1.9% worse. |
| `host_mutex_spin=0` | RETRACTED the same day. Does not replicate. |
| `dma_nontemporal` | Closed by arithmetic. 0.16% of cycles. |
| ADPF | Null on a capped scene. |
| `LOAD_OP_CLEAR` | Correct and CPU-neutral. Turnip already folds it. |
| `LAZILY_ALLOCATED` tile memory | CLOSED. Render targets need `SAMPLED`. |
| SHUFB TBL2+ORR | Closed. 1.7% in the real sequence, below the noise. |
| `guest_preflight` | Default 0. It halved the frame rate. |

**A lever with no reach and a lever with no effect give the same number.**
Instrument the mechanism, then choose a workload that runs it. The self-loop
park read `entries=0` on two titles and 49,000 per window on a third.

## Step 5. When a report says "it used to be faster"

**Measure the two builds. Do not hunt levers.** Build the good commit the user
names, keep both APKs, and alternate the installs inside one session.

    tools/thor_build_ab.sh

The absolute number drifts between sessions. One configuration gave 11.86 FPS in
one session and 9.89 in another. Interleave the INSTALLS, not only the arms.

**If the builds separate, bisect.** Four builds at about ninety seconds each
found a defect that hours of reading missed, and reading produced four confident
wrong answers first.

## Refusals

The tool refuses on each of these. Keep them if you write another harness.

- The device does not answer. An unreachable device returns empty like a dead
  process.
- The battery is below 20%. The device is shared.
- A dev-core override is active. Then the APK you installed is not what runs.
- The screen is asleep. Then no surface exists and the renderer waits forever.

And it cleans up on EVERY exit path. A harness that leaves a property set
poisons the next measurement. Twelve orphaned stressors ran for hours here after
a dropped link.

## What this skill does NOT do

It does not ship a setting. It prints what it would suggest.

**A measured win is not automatically a correct default.** `Accurate SPU
Reservations: false` measured -10.6% and is not shipped, because upstream
documents that it breaks titles and the emulator's own source shows the path.
Ask what a win costs in correctness, and ask who chose the current value.

# Driving it through the MCP tools

The `thor` MCP server (`tools/thor_mcp/server.py`, wired in `.mcp.json`) is the
mechanism. This skill is the policy. Use the tools instead of writing a bash
harness: every harness defect in this repo came from retyping the same loop.

    thor_state       everything at once: reachable, pid, temp, status, telemetry,
                     compile progress, config IN EFFECT, live SPURS
    thor_cooldown    force-stop FIRST, then cool
    thor_boot        boot a title; freshCompile=true turns the SPU cache OFF
    thor_wait_ready  wait for real frames, never a fixed sleep
    thor_screenshot  PNG plus whether a movie is playing
    thor_press       press pad buttons in the guest
    thor_sample      process and per-thread CPU; REFUSES a bad window
    thor_log         the log tail, filtered
    thor_setprop     set a property AND read it back
    thor_stop        stop everything and prove the device is quiet

## The loop

1. `thor_state`. If it is not reachable, stop. An unreachable device answers
   empty exactly like a dead process.
2. `thor_cooldown`.
3. `thor_boot` with `freshCompile: true` when DIAGNOSING. The SPU object cache
   is on by default and replaces a compile with a stored object, so a fault
   could be an artifact of a stale object rather than the change.
4. `thor_wait_ready`, never a sleep.
5. `thor_screenshot`, and READ IT. Decide what the screen asks for.
6. `thor_press` only then. A press during an intro is correctly ignored, and
   that reads exactly like a broken API.
7. `thor_sample`. Take the refusals seriously; see below.
8. `thor_stop`, and confirm the DEVICE is quiet.

## What `thor_sample` refuses, and why you must not work around it

- **A movie is playing.** A cutscene cannot resolve a measurement. One
  configuration measured 3.78 and 5.89 cores on consecutive rounds here.
- **The thermal guard is engaged.** The arm is then measuring the guard's frame
  cap, not the lever. Two arms read exactly 20.00 FPS for that reason.

A `void: true` result is a RESULT. Do not average it, and do not retry until it
passes.

## Two things the tools give you that a bash harness did not

**Reach.** `thor_state` carries the park and FIFO counters. A lever with no
reach and a lever with no effect give the same number; the SPU self-loop park
was written off twice on a scene where its counter reads `entries=0`.

**The config in effect.** `thor_state` reports what the EMULATOR has, not what a
file says. A harness once fed its spec through `printf | while read`, which
drops the only line, so every arm ran unset and the arms agreed perfectly.

## It proposes, it does not ship

No tool writes a game profile or an engine default. Hand the user a diff.

# PAUSE. The game does not wait while you think.

**This is the rule that makes every other observation mean something.**

If the emulator is not paused while you look at it, it keeps running. The
screenshot you reason about is already stale, the scene has moved on, and the
button you press lands somewhere you never saw. That is not a small race: an
intro advances several scenes in the time it takes to read one picture.

So the tools PAUSE BY DEFAULT:

| tool | pause behaviour |
| --- | --- |
| `thor_screenshot` | pauses, captures, and STAYS paused |
| `thor_state` | pauses before reading |
| `thor_press` | RESUMES, presses, then re-pauses |
| `thor_sample` | REFUSES while paused |

`thor_press` resumes on its own because a paused guest cannot see a button, and
it puts the emulator back the way it found it. So the loop is:

    thor_screenshot   -> paused, and the picture is true
    (decide)          -> the game is not moving while you decide
    thor_press START  -> resumes, presses, re-pauses
    thor_screenshot   -> paused again, see what changed

**`thor_sample` refuses while paused, and that refusal is correct.** A paused
emulator measures about 0.3 cores against 3.9 running. A sample taken paused is
not a small error, it is a number about nothing.

Pass `pause: false` only when you deliberately want a live reading, such as
watching a frame rate settle.

# Detecting a movie: TWO sources, because one was not enough

`GET /scene` reports `source`:

| source | what it means |
| --- | --- |
| `cellVdec` | the guest decodes through Sony's decoder |
| `open-video-file` | the guest holds a video container open, such as a `.bik` |
| `none` | neither, which is NOT proof that the screen shows the game |

**This was got wrong, and the way it was wrong is the lesson.** Transformers
plays `FMV_intro.bik`. The first probe watched `cellVdec` only, reported
`videoDecoding: false` for the whole intro, and a measurement was taken OF A
MOVIE. Many PS3 games ship Bink and decode it in their own SPU code, so Sony's
decoder never fires and `vdecUnits` stays 0 for the entire run.

So `"movie"` beside `"vdecUnits": 0` is not a contradiction. Read `source`.

**A real-time engine cutscene is detected by neither**, because it neither
decodes nor opens a container. Judge that from a PAUSED screenshot.

# DRIVING A GAME: pause, screenshot, LOOK, decide, press. Never a blind sequence.

**This is not a preference. A blind press sequence corrupts the run.**

The failed way, and it failed on this title today: skip the intro, then fire
`START`, `CROSS`, `CROSS`, `CROSS` on a timer and assume the menus advanced. The
arm came back `INVALID (no 3D scene: fps=0.00 cores=1.100)` and the game was
sitting on the **Hasbro logo**, because the presses had landed on whatever
happened to be on screen.

## Why a timer cannot work here

**Transformers plays SEVERAL intro movies back to back**: Activision, Hasbro, a
developer logo, then the FMV. A fixed sequence desynchronises the moment any one
of them runs long or short.

**And `/scene` alone is not enough to skip them.** It reports `videoDecoding`
from an open `.bik`, so it goes FALSE in the GAP BETWEEN two movies. A skip loop
that breaks on the first "not a movie" exits mid-intro and then presses blind.
Measured: the probe read `source: none` while the Hasbro logo was on screen.

## The loop that works

    POST /pause          the game stops. It does not advance while you think.
    adb exec-out screencap -p > shot.png
    READ THE SCREENSHOT  decide what this screen is asking for
    POST /pad/press?...  thor_press resumes, presses, and re-pauses
    POST /pause          look again, confirm what changed

`thor_press` already resumes and re-pauses on its own, because a paused guest
cannot see a button.

**Pausing is the part that makes it correct**, not the part that makes it
tidy. Without it the screenshot is stale before it is read, and the button lands
on a scene nobody looked at. Verified: 3.91 cores running, 0.33 paused.

## What a script may and may not do

A script MAY: boot, cool, wait for frames, sample, and REFUSE an arm whose gate
does not pass.

A script MAY NOT: decide which button to press. That needs eyes on the picture.
So an experiment that requires navigation is driven by hand to the scene, and
then a savestate is captured so the scene is reproducible without navigating
again.

**Capture the savestate the FIRST time you reach the scene.** Reaching the
Decepticon Campaign by hand cost six minutes; restoring it costs one command.
