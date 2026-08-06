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

## Backlog re-audit: the talk's series was already in

Re-audited the four ranked items by diffing the vendored files against
`origin/master` blobs rather than reading commit titles, because the shallow
`rpcs3-upstream` checkout makes commit archaeology unreliable. All four were
already present, so the ledger's "not yet ported" list was stale:

- Checksum/compare: present, and ahead of `35f65c224`. The vendored path has
  both the unrolled `checksum_parts`/`aarch64_neon_uabd` form and the rolled
  `acc_phi` loop, matching `origin/master`.
- `FCGT`: the `#if defined(ARCH_ARM64)` `bsl` inline-asm block is byte-identical
  to upstream. Only the surrounding `register_intrinsic`/`std::bitset` shape
  differs, which is structural, not an ARM gap.
- `FSM`/`FSMH`/`FSMB`/`FSMBI`, `USHL` in `inf_shl`/`inf_lshr`, and the `ROTQBY`
  TBL helpers: present at every upstream call site.
- Multiply widening: all six non-SVE `smull`/`umull` sites present. The only
  absent upstream sites are the SVE-only `sve_smullt`/`sve_umullt` top halves.

Also verified the rule `AGENTS.md` records about retry factories: all three
`compile_spu_llvm_with_retry` call sites pass a factory matching their own
site's `make_llvm_recompiler` arguments, so none silently drops `magn` or
`use_native_object_cache`.

## SHA-3 BCAX, commit `8b45c9fe7`

`EQV` and both `SHUFB` selector paths now emit `BCAX` directly. NEON has no
XNOR, so `~(a ^ b)` costs an EOR plus a NOT; `BCAX(a, ~0, b)` is `a ^ ~b` in
one instruction. `SHUFB`'s selector `(c & ~0x60) ^ 0x0f` is
`BCAX(0x0f, c, 0x60)`, replacing a BIC plus an EOR. Upstream notes LLVM should
form BCAX here on its own and does not.

Safety, all verified in source rather than assumed:

- `utils::has_sha3()` reads `HWCAP_SHA3`, and Thor reports `sha3`.
- `JITLLVM.cpp` already pushed `+sha3`/`-sha3` to `setMAttrs`, so selection is
  legal on Thor and impossible elsewhere.
- Bundled LLVM 20.1.3 defines `SHA3_pattern` for `bcaxu`/`eor3u` on `v2i64`,
  which is the overload the helpers request, so there is no "cannot select"
  path.
- `bcax()`/`eor3()` fall back to the arithmetic form when `m_use_sha3` is clear,
  so no caller branches and non-SHA-3 ARM hosts keep the previous codegen.

Contract tests: `tools/test_thor_spu_arm64_bcax_lowering.ps1` (new) pins all of
the above. `tools/test_thor_spu_shufb_splat_lowering.ps1` was failing because it
still asserted TBL2/TBX2 were parked; it now asserts the real rule, that they
are allowed only while the scavenger retry owner and the `m_use_tbl2` gate
exist. `eor3()` has no call site yet.

## Device round: baseline captured, boot not yet achieved

Instruction-level A/B rather than an FPS claim. The SPU native-object cache key
hashes the optimized IR plus target/CPU/feature identity, so a codegen change
invalidates stale objects by construction and a fresh compile is guaranteed to
reflect the new lowering.

Baseline, pulled from the 10 pre-change objects under
`BLUS30161/.../spu-native-v2` dated 2026-07-23 and disassembled with NDK
`llvm-objdump`: `bcax=0`, `eor=27`, `tbl=50`.

Exact APK `7CD49709...2FE40` (thortest) installed on pinned serial `c3ca0370`
under strict cool gate `20260805-212321-thor-input-strict-cool-gate`, install
capture `20260805-212341-bcax-sha3-apk-install`, hash matched, PID absent after
install.

Two boot attempts, neither reached the title:

- `20260805-212413-thor-input-custom`: invocation defect, not a result. The run
  omitted `-BootGame`, so the game never started and all eight readiness polls
  classified `dark_percent=100` with `ppu_compilation_screen_present=False`.
  The emulator log stops after VFS mount, which confirms no boot was requested.
- Second attempt with `-BootGame` and the installed-APK hash bound: rejected at
  preflight with silicon `46.2 C` against the `40 C` launch limit, residual heat
  from the first attempt. `cpu-1-9` is the governing sensor.

Classification so far: `route-tooling` for the first attempt and
`thermal-preflight-refusal` for the second. No speed, FPS, gameplay, stability,
or thermal-win credit, and no BCAX emission proof yet.

Note for the next round: a host-side probe that filters only
`cpu|gpu|soc|...` thermal zones read `34 C` a minute before the harness
measured `46.2 C`. Trust the harness preflight, not an ad-hoc zone scan.
