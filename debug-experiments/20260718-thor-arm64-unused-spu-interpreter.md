# Thor ARM64 Unused SPU Interpreter Removal

Date: 2026-07-18

Status: host-verified, uninstalled, device-unmeasured

## Goal

Reduce AYN Thor PS3 cold-start CPU work and thermal pressure without changing
the ARM64 LLVM SPU execution path. The Thor was deliberately not contacted in
this round after prior rapid thermal trips.

## Finding

`spu_cache::initialize()` unconditionally built a generated all-opcode LLVM
interpreter for both Dynamic and LLVM decoder modes. Repository-wide ownership
and call-site audit shows that module is unreachable in ARM64 LLVM mode:

1. Both normal and save-state-restored ARM64 LLVM `spu_thread` constructors
   assign `make_llvm_recompiler()` to `jit`. The x86 path alone assigns
   `make_fast_llvm_recompiler()`.
2. `spu_thread::cpu_task()` enters the gateway/JIT loop whenever `jit` is
   present. Its only direct `g_interpreter` call is the mutually exclusive
   `jit == nullptr` branch.
3. The regular LLVM compiler's instruction fallback calls `exec_fall<F>`,
   which invokes the existing C++ instruction handler. It does not call the
   generated interpreter or read `g_interpreter_table`.
4. The sole runtime read of `g_interpreter_table` is inside `spu_fast`.
   `spu_fast::compile()` explicitly rejects non-x86-64 architectures.
5. Current upstream RPCS3 retains the same initialization condition, ARM64
   regular-recompiler ownership, direct C++ fallback, and x86-only table
   consumer. No newer upstream replacement was available to transplant.
6. If LLVM is absent, `make_llvm_recompiler()` for a normal ARM64 LLVM thread
   throws rather than returning a null interpreter-backed fallback. Skipping
   the generated interpreter therefore does not remove a hidden recovery path.

The generated module is still required and retained for Dynamic mode, where it
is executed directly. It is also retained for non-ARM64 LLVM, where the x86
`spu_fast` tier consumes its exported per-instruction table.

## Change

The interpreter-build decision now always includes Dynamic mode and includes
LLVM mode only when the target is not ARM64. ARM64 LLVM logs:

`SPU Runtime: Skipped unused all-opcode LLVM interpreter on ARM64.`

Everything after that decision remains unchanged: cached-program discovery,
analysis, preload workers, normal program LLVM compilation, on-demand dispatch,
and direct C++ instruction fallbacks. The previously added native-object cache
remains usable for bounded program preload; its interpreter-object path remains
available on architectures that still build the generated interpreter.

This is not a lower-performance baseline tier and does not defer guest work
into gameplay. It removes a whole LLVM module construction, optimization,
backend emission, link, and instruction-table export whose outputs have no
ARM64 LLVM consumer.

## Expected Benefit And Limits

The structural benefit is stronger than caching the same module: every ARM64
LLVM start avoids the work, including a cold first launch. Expected effects are
shorter SPU startup and less transient CPU energy/memory pressure, which may
help the Thor reach the title with less heat. Packaged binary size does not
materially shrink because Dynamic mode still needs the interpreter generator.

No startup-time, FPS, temperature, flicker, field, menu, battle, or stability
claim follows from host compilation. The change targets startup latency and
heat, not steady-state emulation FPS.

## Host Verification

No ADB, install, launch, device read, or other Thor action ran.

- New focused ownership/call-graph contract:
  `tools/test_thor_spu_arm64_interpreter_skip.ps1`: pass.
- SPU native-object-cache compatibility contract: pass.
- All 28 `tools/test_thor_*.ps1` contracts: pass.
- Optimized ARM64 native target: `BUILD SUCCESSFUL` in 51 seconds.
- ARM64-only optimized ThorTest APK: `BUILD SUCCESSFUL` in 23 seconds.
- Exact APK/ABI contract: pass.
- Export surface remains 34 defined dynamic symbols, 587 explicit
  relocations, 391 jump slots, and 44,253 encoded relocation bytes.
- Packaged ARM64 core exactly matches the stripped ARM64 core.
- Packaged core contains both the ARM64 skip log and the revised native-object
  cache activation row.
- `git diff --check`: pass before documentation finalization.

Exact host-only artifacts:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,696,106` bytes
- APK SHA-256:
  `A63EEBC09C8021F053D4F6024997E7D72636B259AB61DCAEED41AE429E552F94`
- merged ARM64 core size: `1,306,276,816` bytes
- merged ARM64 core SHA-256:
  `52F69AC0309A5A3263C5F6405E3CE60874983FD2E2C9248584482BB7E4596096`
- stripped/packaged core size: `63,136,792` bytes
- stripped/packaged core SHA-256:
  `251EA11B451EEB0C89C594BD57F45FEDA3046DD49485A50CFA8BD42524617D9C`

## Device Boundary

The candidate is uninstalled and `device-unmeasured`. Keep RPCSX stopped while
the Thor is hot. A later independently cool round may install without launch,
then a separate cool round may run one bounded title proof under the existing
multi-sensor early-stop guard. The first runtime proof must contain the new
ARM64 skip log and must not contain the interpreter-built success row before
comparing startup time or peak temperature with an exact control.

Rollback is the single initialization-condition commit; no cache migration or
property reset is required.
