---
name: thor-measurement-validity
description: Decide whether an on-device Thor A/B or simpleperf profile is valid before you believe its number. Use when running tools/thor_savestate_ab.sh, tools/thor_title_ab.sh or tools/thor_profile_game.sh, when reading a simpleperf capture of the Android emulator, when quoting cores/FPS/power/crash rates from the device, or when a lever sweep keeps returning nothing.
---

# Thor Measurement Validity

## Scope

Use this repo-only skill for the VALIDITY of a device-side number, not for
deciding what to optimize and not for promotion.

Compose it with:

- `thor-windows-android-ab` for same-scene Windows against Thor identity.
- `ps3-speed-proof-gate` when the result might be called a win.
- `ps3-continual-harness-refiner` or `codex-goal-loop` when the sweep is circular.
- `thor-experiment-ledger` for the durable record.

Every rule below comes from a measurement that was WRONG here on 2026-08-22 or
2026-08-23. The number that was wrong is given.

## Hard Rules

- **Print evidence that the run was in the state you meant to measure.** A
  Transformers A/B advanced through cutscenes with button presses and gave
  **3.78 and 5.89 cores for ONE configuration**, because each run landed in a
  different scene.
- **Grep the log for a fatal error before you read a profile.** A capture read
  **90.79% in one SPU thread**, which was written up as a hot loop. The RSX had
  died 35 s earlier and `Frames: 0 in 10.00s` was in the log throughout.
- **Report `[min..max]`, not only the mean.** Overlapping ranges mean "not
  shown". The RSX FIFO pause ladder and the `vm_writer_lock` spin count were both
  rejected on this rule.
- **Never quote n=1.** One arm read 10351 mW against 7545 and was reported as a
  +37% power regression; the second arm of the same configuration read 6593 mW,
  below both controls.
- **Read the lever back off the device and print it with every arm.** A harness
  fed `printf '%s'` into `while read`, which drops a line with no trailing
  newline, so EVERY arm ran unset and the two arms agreed perfectly. Only a
  missing counter line exposed it.
- **Never pool arms that differ in more than one setting.** "About 2 boots in 5
  crashed at 20 us" mixed FIFO and reservation settings; the controlled retest
  crashed 0 times in 4.
- **A measured win is not automatically a correct default.** Ask what it costs in
  correctness and who chose the current value.

## Noise Floors, Measured

| workload | spread of ONE configuration |
| --- | --- |
| gated title screen | +/-0.2% |
| restored savestate | +/-5% |
| pressing through cutscenes | about +/-50%, unusable |

A claim smaller than the floor of its workload is not a result.

## Harnesses

| tool | workload | arms are |
| --- | --- | --- |
| `tools/thor_savestate_ab.sh` | restored savestate | `debug.rpcsx.thor.*` properties |
| `tools/thor_title_ab.sh` | title screen, gated | config keys |
| `tools/thor_profile_game.sh` | boots, waits for real frames | profile capture |

Keep these properties if you write another harness:

- Each arm needs a FRESH PROCESS. Every `debug.rpcsx.thor.*` property is read
  once into a static and cached for the life of the process.
- Restore every property and config on EVERY exit path, including interrupt.
- Run from a frozen copy. Editing a script while bash executes it killed a run
  with `unexpected EOF` at a line that had no syntax error.
- Write device config files through `run-as`. A file written as `shell` is one
  the app cannot rewrite.
- Prefer per-thread CPU with `THREAD_MATCH`. `rsx::thread` is 0.51 of 2.90 cores,
  so a lever saving 30% of that thread moves the process total by 5% and hides in
  the noise.

## Reading A Profile

- `simpleperf` needs `run-as`, because `perf_event_paranoid` blocks the direct
  form. `-PrpcsxThorDebuggable=1` keeps `CMAKE_BUILD_TYPE=RelWithDebInfo`, so the
  profile still describes the shipped core.
- Symbols need a symfs tree holding the UNSTRIPPED `librpcsx-android.so` from
  `app/build/intermediates/cxx/RelWithDebInfo/*/obj/arm64-v8a/`.
- **`unknown[+X]` is the JIT arena, not a symbol.** All recompiled guest code
  collapses onto one entry under `--sort symbol`, `--sort vaddr_in_file` AND
  `report-sample`. Never quote a percentage against it as if it were a function.
- An SPU fault at `0xffdeadXX` is an emulator trap, not a wild pointer. Read the
  stored tag: `HALT` at `+00` means the guest ran a halt instruction, `TAG` at
  `+04` is an illegal MFC tag update, `BIJT` at `+20`.
- Check whether a `grep` was truncated before you conclude something is absent. A
  `head -12` hid upstream's whole SPURS limiter behind this repo's probe code.

## Before You Report

- The app is stopped, the device is near idle temperature, and
  `getprop | grep debug.rpcsx.thor` shows nothing set.
- Raw numbers and ranges go to `CLAUDE.md` through `thor-experiment-ledger`. A
  negative result that is written down is worth as much as a win.
