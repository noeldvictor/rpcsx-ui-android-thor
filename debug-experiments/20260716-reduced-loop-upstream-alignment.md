# Reduced-Loop Upstream Source Alignment

- Date: 2026-07-16
- Title: Eternal Sonata `BLUS30161`
- Classification: `parked`, `full-port-required`
- Speed credit: none
- Device work: none in this host-only audit

## Outcome

The Android reduced-loop emitter must remain retired. The exact SPU function
that fails under the vendored emitter is valid under current upstream RPCS3,
but upstream and vendored RPCSX do not implement the same analyzer contract.

A partial register patch is not a credible repair. The next implementation must
port the complete upstream analyzer/emitter island and preserve Android gating
around it; until then, detector-only mode is the only allowed Android mode.

## Exact runtime evidence

### Current upstream control

Run:

`debug-captures/windows-lab/20260715-230705-clean-upstream1269ebf-allcore-uncap240-frame-scaled20-first-battle-speed-windows`

- Exact function `0x330f0-WxCJa6i2qC1kMGp5oLZ1C9A9viee` was built.
- Upstream detected reduced loops at `0x33170` and `0x331e8`.
- The log contains `453` reduced-loop detections overall.
- The route reached correct Path-to-Tenuto field and first battle with zero
  actionable fatal hits and about `120 FPS` gameplay.
- This proves the guest function and the complete upstream reduced-loop path can
  coexist correctly. It does not prove the vendored Android port.

### Vendored Android counterproof

Run:

`debug-captures/android-speed-sprint/20260716-232243-thor-input-eternal-sonata-battle-intro-route`

- Fresh cache: `spu-safe-thor-rl-u2-v2-v1-tane.dat`.
- At emulated `0:01:34.829866`, `CellSpursKernel0` entered function
  `0x330f0` and faulted reading unmapped `0x8d230480`.
- Fresh-cache U4 and U2/no-reuse runs reproduce the same function, PC, and
  address fault, excluding unroll count, invariant-result reuse, and stale
  cache as the root cause.
- The route stopped before a valid field/battle FPS sample. Classification:
  `failed`, not a speed result.

## Source scope

The six named upstream reduced-loop commits alone change roughly 2,804 lines
added and 279 removed across seven core files:

| Commit | Role |
| --- | --- |
| `a863e94` | Integrated reduced-loop detection |
| `2e4ee9c` | LLVM emitter |
| `37a07ae` | FM/FMA/FCGT optimization |
| `a03a78d` | Runtime completability verification |
| `13de823` | Register and external-origin fix |
| `02eb549` | Second-block register-update fix |

The ancestry range also contains 18 commits that touch the seven relevant
analyzer/emitter files. Those include CEQHI recognition, address reuse,
floating-point hints, memory/context classification, pure-opcode tagging,
bitset bounds, unknown-target handling, and later analyzer fixes. Treat those
as dependencies to audit, not unrelated noise.

The custom Android implementation began in `590de263c` with 846 additions
across its gated detector/emitter patch. Its detector is a post-analysis scan
over `m_bbs` summaries and opcode reconstruction. Current upstream instead
tracks reduced-loop state inside the primary analyzer dataflow and carries:

- per-register origin sets, including external origins for memory, `RDCH`, and
  `RCHCNT`;
- integrated `reduced_loop_all` state;
- loop arguments, dictators, writes, conditional second-block updates, and
  not-NaN hints derived during analysis;
- member-scoped LLVM reduced-loop state consumed by the emitted instructions;
- runtime completability checks before entering the optimized body.

The vendored source lacks the integrated `origin_t`,
`add_register_origin`, `reduced_loop_all`, and `m_reduced_loop_info`
architecture. The July register-safety patch approximated only part of the
second-block fix and did not make the analyzer source-equivalent.

## Reproducible audit

Run:

```powershell
.\tools\audit_spu_reduced_loop_alignment.ps1
```

Use `-FailOnIncomplete` in a host gate. Current expected classification is
`full-port-required`. The audit also verifies the Android native clamp and
that public tooling cannot select the retired emitter.

## Port prerequisites

1. Baseline-align the seven analyzer/emitter files through the full upstream
   dependency sequence, not only the six commits named above.
2. Preserve RPCSX/Android integration separately: native emit clamp, isolated
   cache identity, debug properties, logging, and ARM64 build compatibility.
3. Build the complete ARM64 RelWithDebInfo core and run host-side static/audit
   gates before deploying anything.
4. Prove field, Options/menu, and first battle with the full implementation.
   No partial or detect-only result receives speed credit.
5. Spend at most one short, temperature-gated Thor route in a separately cool
   round, then force-stop and analyze on the host.

Next code action: prepare a full SPU-island compatibility diff against the
vendored base and resolve analyzer APIs as a unit. Do not re-enable emission
while that port is incomplete.
