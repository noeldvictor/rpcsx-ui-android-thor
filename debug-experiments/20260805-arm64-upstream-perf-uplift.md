# 2026-08-05 ARM64 upstream perf uplift port

- Status: `failed`
- Title ID: BLUS30161
- Game: Eternal Sonata
- Platform scope: `android-thor`
- Created: 2026-08-05
- Last updated: 2026-08-05

Source: Whatcookie (Malcolm Jestadt), "PS3 emulation is fast on ARM now",
2026-08-04. He is the author of the upstream commits ported here. Local
transcript via `yt-dlp` + `faster-whisper`, kept out of the repo.

## Ported

Commit `2401dcc7f`, 12 files, +611/-24. Builds clean for `arm64-v8a`.

- `busy_wait` timer scaling in `rx/include/rx/asm.hpp`. Thor's 8 Gen 2 runs
  `CNTFRQ_EL0` at 19.2MHz against RPCS3's ~3GHz x86 assumption, so
  `busy_wait(3000)` blocked about 156us instead of ~1us. Added
  `arm_timer_scale` / `init_arm_timer_scale()`, called from
  `_rpcsx_initialize`. Upstream attributes +25% perf / -10% power to this
  single fix on ARM.
- `pause()` emits `isb` instead of `yield`. `YIELD` is an SMT hint and a no-op
  on SMP cores, so it never throttled the spin.
- SPU `SHUFB` and PPU `VPERM` emit `TBL2`/`TBX2` rather than the emulated x86
  `PSHUFB` sequence. Upstream measures +8%.
- Enabling mechanism for the above: `thread_ctrl::silent_exit`,
  `jit_compiler::try_add`/`try_fin`, `run_recoverable_llvm`, and
  `compile_spu_llvm_with_retry`. Retries a block with `m_use_tbl2` cleared when
  the LLVM error contains
  `Cannot scavenge register without an emergency spill slot`.

Two deliberate deviations from upstream are recorded in `AGENTS.md`.

## Device run: failed, not-comparable

Exact APK `82E7E397...BADAD`, 100,240,864 bytes, installed on pinned serial
`c3ca0370` under strict cool gate `20260805-144019-thor-input-strict-cool-gate`.
Install capture `20260805-144040-arm64-uplift-20260805` confirms the installed
hash matched and RPCSX PID was absent after install.

Run capture `20260805-144131-thor-input-custom`:

- Preflight silicon `33.9 -> 34.7 -> 34.3 C`, battery `22.0 C`, skin `30.0 C`.
  All within the 40 C launch limit.
- Debug boot handshake accepted in `705 ms` at `14:41:46`.
- Post-run guard fired at `14:41:48` with silicon `71.1 C` on
  `thermal_zone44/cpu-1-9`, above the `68 C` early stop and below the `72 C`
  hard limit. RPCSX was force-stopped.
- Heat was entirely CPU-side. The hot zones were `cpu-1-9` `71.1`, `cpu-1-1`
  `66.2`, `cpu-1-10` `65.4`, `cpu-1-8` `65.0`, while every `gpuss-*` zone
  stayed between `36.4` and `44.4 C`.

Classification: `thermal-stop-before-title` / `failed` / `not-comparable`.
No speed, FPS, gameplay, stability, flicker, or thermal-win credit.

## Why this run proves nothing about the port

The invocation passed no `-Macro`, so the harness booted the title and took the
post-run snapshot about two seconds later with no route gates, no readiness
poll, and no screenshots. There is no title proof, no timing, and no logcat
with SPU/PPU compile rows, so there is nothing to compare against any prior
capture. This is an invocation defect, not a result.

The `34.3 -> 71.1 C` rise inside roughly seven seconds is consistent with the
known cold PPU/SPU LLVM compile spike already recorded for
`20260720-211548-thor-input-custom`. It is not evidence for or against the
`busy_wait` change.

## Next

- Re-run on a fresh cool round with an explicit macro carrying
  `gate:ppu-ready`, a title-menu visual check, and `shot:` steps, so the run
  yields a title proof and comparable timings.
- Capture logcat and confirm whether any block logged
  `Retrying without TBL2/TBX2`. A low retry count would confirm the scavenger
  fallback behaves as upstream describes (about 3 blocks in 10,000).
- Only after a clean title proof does any `busy_wait` speed claim become
  measurable.

## Regression: busy_wait scaling dropped Thor to ~1 FPS. Reverted.

User reported roughly 1 FPS on the installed `82E7E397...BADAD` build. Cause was
the `busy_wait` timer scaling, and it was a porting error.

Upstream scales `busy_wait` because its call sites pass x86-derived counts tuned
for a ~3GHz timer. This fork had already solved that problem the other way: the
hot spin sites were hand-retuned against Thor's real 19.2MHz generic timer and
already pass generic-timer ticks directly.

- `busy_wait(100)` in `util/Thread.cpp:2618`, `Emu/RSX/RSXThread.cpp:2840`
- `profiled_busy_wait(..., 200)` in `Emu/Memory/vm.cpp` x3, `RSXFIFO.cpp`
- `profiled_busy_wait(..., 300)` in `SPUThread.cpp` x4, `CPUThread.cpp` x2
- `profiled_busy_wait(..., 500)` in `SPUThread.cpp` x4, `vm.cpp` x2

`arm_timer_scale` resolves to 1 on Thor because `19200000 / 30000000` truncates
to 0 and falls back, so the applied scale was purely the `/100`. That divided
already-correct values a second time:

| call | before | after |
| --- | --- | --- |
| `busy_wait(100)` | 5.2 us | 52 ns |
| `busy_wait(300)` | 15.6 us | 156 ns |
| `busy_wait(500)` | 26 us | 260 ns |

Collapsing the backoff on contended reservations, SPU channels and mutexes
produces a lock convoy with cacheline ping-pong across all eight cores, which
matches the observed ~1 FPS.

`rx::get_tsc()` reads `cntvct_el0`, so the timer source was never the variable.
The call-site calibration was.

Reverted the scaling. Also reverted `pause()` from `isb` back to `yield`: `isb`
is probably the better throttle, but it changes per-iteration spin cost and
these counts were tuned with `yield`, so it must be measured alone.

Ruled out as causes, from live logcat during the 1 FPS session: zero
`Retrying without TBL2/TBX2` and zero `compiled successfully without TBL2`
records, so the scavenger retry path never fired and the SHUFB/TBL2 work is not
implicated. That work is retained.

Fixed APK `49FCB2F5...7FED7`, 100,239,664 bytes, installed with `adb install -r`
rather than the gated installer, because this is a regression fix rather than a
measured run. It carries no cool-gate capture and earns no speed credit.

Lesson recorded in `AGENTS.md`: before porting an upstream ARM tuning fix, check
whether this fork already compensated at the call sites. Two fixes for one
problem multiply.
