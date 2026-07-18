# 2026-07-18 Eternal Sonata 0x25cc verifier first-battle proof

## Outcome

The all-core PadAPI first-battle route now has a clean, compact Windows proof for the `BLUS30161` `0x25cc / 0x9e4000` SPU contract. The compact verifier reached correct active battle and stayed there through the 150-second cutoff at the 30 FPS cap. The strict parser accepted every row, and the visual/fatal gate passed.

This is correctness and measurement-tooling evidence, not a speed claim. The verifier body remained disabled, and no Android build, install, launch, ADB query, or Thor temperature check ran in this round.

## Matched routes

### Verbose verifier counterproof

- Run: `debug-captures/windows-lab/20260718-162946-allcore-padapi3-verify25cc-f677-first-battle`
- Binary SHA-256: `D194961209318AEFA4AEDAE909649F3E3A245A76D8B84CEF9A074D04A63237E8`
- Configuration: all-core, PadAPI, 30 FPS, vblank 60, Accurate SPU Reservations on, Accurate SPU DMA off, `Verify25ccShadow`, 25cc body off.
- Route: title 48s, load target 68s, load complete 85s, field 87s, tutorial 102s, active battle 108s, live 118s, hold 129s, alive through 150s.
- Contract: 792/792 accepted rows, 1,587 hits, 26,001,408 bytes, zero output mismatches, zero descriptor overflow.
- Visuals: sampled tutorial, active, live, hold, and 150-second frames were correct.
- Failure: guest TTY emitted `unknown draw command (30b12f20)` and `(3e7a0000)` at emulated `0:02:13.748`; the strict visual/log gate therefore rejects promotion.
- Log size: 65,986,967 bytes.

### Verifier-off control

- Run: `debug-captures/windows-lab/20260718-164415-allcore-padapi4-verifier-off-f677-first-battle`
- Same binary, route, all-core scheduler, PadAPI, frame cap, vblank, and SPU accuracy settings; verifier and every experiment were off.
- Correct title/load/field/tutorial/active-battle route through 150s at about 30 FPS.
- Fatal scan: zero unknown draw, VM access violation, Vulkan device loss, assertion, frozen-emulation, or terminated-thread rows.
- Strict Windows visual gate passed.
- Log size: 1,360,906 bytes.

The one matched control does not prove deterministic causality, because stock routes can occasionally emit the same guest diagnostic. It does show that the verbose verifier is a timing/logging perturbation: it wrote about 48.5 times as much log data as the control while its emulation body was disabled.

### Compact verifier proof

- Run: `debug-captures/windows-lab/20260718-165758-allcore-padapi5-verify25cc-compact-first-battle`
- Binary SHA-256: `3F050FD5C4C0D167E7415E85A50E0E67E81E53234012A563165779430698BBCF`
- Same route and configuration as the verbose verifier; the emulation body remained off.
- Correct title/load/field/tutorial/active battle, with a clean active-battle frame at the 150-second cutoff.
- Fatal scan: zero unknown draw, VM access violation, Vulkan device loss, assertion, frozen-emulation, or terminated-thread rows.
- Contract: 803/803 accepted rows, 1,607 hits, 26,329,088 bytes, zero output mismatches, zero descriptor overflow, `strict_gate_pass=true`.
- `total_contract_rejects=22501` counts observed non-contract descriptor families; it is not parser rejection. Parser rejected rows remained zero.
- Log size: 2,134,596 bytes, a 96.765% reduction from the verbose verifier and only 56.851% above the verifier-off control.
- Host external-contention gate stayed clean. A nonsensical one-sample aggregate GPU percentage made the overall host grade high, so this capped run must not be used for speed comparison.

## Code changes

- `tools/windows_rpcs3_lab.ps1` now requires three consecutive fatal-looking Path-to-Tenuto frames before aborting, so a transient black loading frame cannot end a valid route.
- The same live Windows route now treats `unknown draw command` as actionable and fails closed, matching the post-run promotion gate.
- `rpcs3-upstream/rpcs3/Emu/Cell/lv2/sys_spu.cpp` now makes `verify-25cc-shadow` compact by default: it emits the strict aggregate contract row but suppresses generic GPU/MFC/shadow/descriptor traces. `RPCS3_ES_SPU_HLE_VERIFY_VERBOSE=1` restores the deep trace. Enabling the 25cc body also retains full body diagnostics.

## Current research direction

- [Partial Cross-Compilation and Mixed Execution for Accelerating Dynamic Binary Translation](https://arxiv.org/abs/2512.00487) supports selective native execution of eligible hot functions. Its reported QEMU results are not transferable numbers, but the architecture matches the title-gated 25cc HLE lane.
- [Boosting Cross-Architectural Emulation Performance by Foregoing the Intermediate Representation Model](https://arxiv.org/abs/2501.03427) reinforces direct translation for common ISA pairs. Its proof-of-concept speedup is not an RPCSX forecast.
- [Dissecting the Impact of Mobile DVFS Governors](https://arxiv.org/abs/2507.02135) shows that independently managed CPU/GPU/memory governors can leave large performance-per-energy gains unused.
- [Phase Matters](https://arxiv.org/abs/2606.27906) shows that accelerator mapping must be phase-specific and can materially reduce steady-state temperature and energy on a modern Qualcomm SoC. The workload and SoC differ from Thor, so only the method transfers.
- Android's current [ADPF guide](https://developer.android.com/games/optimize/adpf), [Thermal API](https://developer.android.com/games/optimize/adpf/thermal), and [Frame Pacing library](https://developer.android.com/games/sdk/frame-pacing/) support sustainable target-duration hints, proactive thermal headroom response, and correct Vulkan presentation pacing.

## Decision and next proof

1. Keep the compact verifier and strict unknown-draw gate.
2. Run a matched, host-only 25cc body-off/body-fast first-battle A/B with compact logging. Require zero unknown draw/fatal rows, correct field/tutorial/active battle, and strict contract success before accepting CPU-time evidence.
3. Do not port the fast body to Android until that host gate is clean.
4. Audit ADPF at the actual native frame and worker-thread boundaries. A Java-only session around the wrapper threads would not measure the PPU/SPU/RSX work cycles accurately.
5. Only after a separately cool preflight may one bounded Thor route test an already host-proven candidate. The device remains stopped.
