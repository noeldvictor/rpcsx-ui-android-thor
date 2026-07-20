# PS3 Emulation Performance Research Refresh

- Date: 2026-07-18
- Target: RPCSX/RPCS3 on AYN Thor, Snapdragon 8 Gen 2 / Adreno 740
- Question: which recent primary research mechanisms could improve PS3
  emulation performance per watt without repeating disproven repo experiments?
- Decision: prioritize compact hot-function profiling and selective native
  SPU/PPU replacement; keep broad GPU offload and global scheduler changes
  parked.

## Current Project Evidence

- Reduced-loop emission is deterministically corrupt on fresh Thor caches.
- The current 0x25cc body reached only 15 GET operations / 245,760 bytes and
  changed verifier-off host CPU by about -0.9%, which is noise.
- The 0x25cc/0x451c field traffic has zero RSX-local overlap and frequent CPU
  synchronization, so it is not a proven GPU-resident batch.
- Global busy-wait, scheduler, and one-worker RSX changes regressed throughput
  or failed to reduce thermal pressure.
- ARM64 LLVM specialization, alias cleanup, persistent native objects, and
  removal of redundant startup work remain the evidence-backed lane.

## Primary Sources And Translation

### Selective native function offload

[Partial Cross-Compilation and Mixed Execution for Accelerating Dynamic Binary
Translation](https://arxiv.org/abs/2512.00487) combines LLVM/QEMU emulation
with selected host-native functions. Its results emphasize that benefit depends
on hot functions and low guest/host transition counts; light functions with
callbacks can remain slower.

Project translation: the SPU contract compiler is the right architecture, but
the current 0x25cc body is too cold. Profile compact per-function/block dynamic
counts first, then replace one large, low-transition SPU or PPU function with a
title/signature-gated native implementation and byte-exact shadow verifier.

### JIT specialization and hot/cold separation

[Deegen: A JIT-Capable VM Generator for Dynamic
Languages](https://arxiv.org/abs/2411.11469) attributes its performance to
specialization, type-check removal, strength reduction, slow-path outlining,
hot/cold splitting, and tiered execution.

Project translation: current KnownFPClass, native ARM64 SPU lowering, SELB
compile cleanup, and persistent native-object work match these mechanisms.
Future candidates need dynamic execution counts, not merely static opcode-family
coverage.

### Race to idle is workload-dependent

[Racing to Idle: Energy Efficiency of Matrix Multiplication on Heterogeneous
CPU and GPU Architectures](https://arxiv.org/abs/2507.20063) shows large,
compute-bound matrix multiplication can finish faster and use less total energy
on a GPU despite higher instantaneous power.

Project translation: GPU offload can lower Thor temperature only when the job
is sufficiently large, parallel, and avoids immediate CPU readback. The current
0x25cc/0x451c evidence violates that gate, so broad SPU-to-Vulkan work remains
parked. Reconsider only after an RSX-consumed or stable batched kernel appears.

### Heterogeneous scheduling needs segmented, measured decisions

[A Survey of Real-time Scheduling on Accelerator-based Heterogeneous
Architecture for Time Critical Applications](https://arxiv.org/abs/2505.11970)
separates serial CPU segments from data-parallel accelerator segments and
highlights dependency and contention costs.

[Towards Energy Efficient Co-Scheduling in
HPC](https://arxiv.org/abs/2604.17640) uses lightweight runtime profiling
because resource scaling is workload-dependent and nonlinear.

Project translation: do not globally change Thor affinity, spin policy, or
worker count. Keep any power/worker policy optional, scene-measured, and
rollback-safe. The existing Android ADPF and startup-affinity switches remain
experiments, not defaults.

## Ranked Next Experiments

1. Add compact saturating dynamic counters keyed by SPU image, compiled
   function entry, and block; emit one summary at stop. Reuse the clean
   first-battle route and reject candidates whose boundary count is too high.
2. Feed the hottest large function into the existing SPU contract pipeline.
   Require exact inputs/outputs, MFC ordering, reservation behavior, and clean
   field/Options/first-battle verification before fast mode.
3. For a proven low-transition function, compare native ARM64 HLE against LLVM
   JIT under a matched clean Windows route before Android promotion.
4. Reopen Vulkan compute only if a capture proves stable batching plus
   RSX-consumed output or no critical-path CPU readback.

Reference Windows proof command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -WindowsInputBackend PadApi -WindowsGameScreen 1
```

No Windows or Thor gameplay run was needed for this research/host-source round.

## 2026-07-20 Official upstream refresh

A network refresh advanced official RPCS3 `origin/master` from `357b7d446` to
`ee37ef277`. The only new commit was a macOS-only MoltenVK 1.4.2 package and
Game Mode change. It has no Android, ARM64, SPU, PPU, RSX, Vulkan-runtime, or
scheduler source delta applicable to AYN Thor.

The preceding official ARM64/SPU performance families were checked against the
current fork's semantic anchors, including ROTQBY/TBL, I8MM GBH/GBB, ARM64
checksum reduction, hardware wait helpers, LQX/LQD/STQX/STQD canonicalization,
SELB, SHUFB splats, KnownFPClass, FMA dependency selection, thread identity,
and local-store mirrors. They are already represented in the current source or
have a recorded title-specific adaptation. Do not duplicate them under a new
name.

The primary-research conclusion remains unchanged: selective native handling
and coordination reduction are useful only at measured hot, low-transition
boundaries. The current candidate already carries the correctness-clean
VBlank-assisted frame-poll wait and other proven host reductions. Preserve the
one-change proof boundary until its deterministic log-sync successor produces
comparison-complete Thor evidence; broad GPU offload, global scheduler changes,
and speculative worker reductions remain parked.
