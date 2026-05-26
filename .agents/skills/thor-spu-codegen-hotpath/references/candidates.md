# SPU / Codegen Candidate Notes

## Current Positive Signal

Reduced-loop emission is controlled by:

```powershell
.\tools\set_thor_logging.ps1 -Mode ReducedLoopEmit
```

Manual quiet+emit pattern for FPS sweeps:

```powershell
.\tools\set_thor_logging.ps1 -Mode Quiet
adb shell setprop debug.rpcsx.thor.spu_reduced_loop_emit 1
```

Cache files:

- normal: `spu-safe-v1-tane.dat`
- reduced-loop: `spu-safe-thor-rl-v1-tane.dat`

Do not mix or rename these casually; cache pollution invalidates speed comparisons.

## 2026-05-16 Results

- Earlier reduced-loop field captures: about `19.6-19.9 FPS`, menu about `20.18 FPS`.
- Retake after RSX work: reduced-loop + all-fence field about `19.10 FPS`, clean visuals.
- Reduced-loop + host-fence field about `17.60 FPS`; do not combine by default.
- Battle validation remains missing.

## Hot SPU / DMA Map

- Hot image: `0x958dfe208b686622`.
- Hot PCs: `0x25cc` and `0x451c`.
- Android DMA profile showed roughly 4.29 GB sampled DMA in field and zero RSX-local bytes.
- Exact output replay cache had no mismatches but also no repeat hits; not the breakthrough.
- Windows kernel capsule field scout `20260519-175217-eternal-sonata-field-stock-qualcomm-windows` saw `1.39 GB` observed DMA, `1583` capsule rows, `0 B` RSX-local traffic, and all rows classified `reservation-risk` due AtomicStat/PUTLLC16 entanglement around the hot work.
- Use `-EternalSonataKernelCapsule Profile` for observe-only capsule logging. It is not a fast path and should not be promoted to GPU compute unless a later capture finds a `gpu-batch-candidate` or `rsx-consumed` capsule.

## 2026-05-20 PUTLLC16 Pair Scout

Windows profile run:

- `debug-captures/windows-lab/20260520-192818-putllc16-pair-profile-field-windows`
- Pair candidates:
  - `Y01tfnsGZ1qQrTV61LSta6n5KLw7` at `put_pc=0xb40`, offsets `0x2330/0x2340`, entry `0xa7c`.
  - `79w5SL0uvyoiJN6A3tK6iKKkqTYr` at `put_pc=0x156c`, offsets `0x1940/0x1950`, entry `0x1470`.

Fast result:

- Temporarily allowing `Y01tfnsGZ1qQrTV61LSta6n5KLw7` failed in
  `debug-captures/windows-lab/20260520-193706-putllc16-pair-fast-uncap240-field-windows`.
- Failure signal: `CellSpursKernel0` access violation writing `0xffdead00`,
  SPU PC `0x01320`, before the field checkpoint.
- `allowed_pair_patterns` is intentionally empty. The pair detector is
  profile/scout-only until a verifier proves complete 128-byte line semantics,
  reservation event behavior, and no SPURS invariant failure.

Decision: failed fast path; keep the scaffold as diagnostic only. It is not a
speed win, not GPU migration, and not a Thor-port candidate.

## Candidate Priority

1. Broaden reduced-loop correctness and coverage.
2. Build reservation-loop/codegen/HLE verifier work around the hot AtomicStat/PUTLLC16 loops.
3. Use Ghidra/disasm around hot PCs to find stable bulk loops.
4. Keep SPU/MFC fast paths verify-first.
5. Avoid broad GPU-offload of SPURS control loops; only batch large stable jobs.
