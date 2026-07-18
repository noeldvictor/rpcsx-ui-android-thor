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

### Compact body-fast trial

- Run: `debug-captures/windows-lab/20260718-171415-allcore-padapi6-verify25cc-compact-bodyfast-first-battle`
- Binary SHA-256: `93C165977F5921068B37466441AF820C6D789FF148C2B36D168F8C24121DD3D7`
- Same deterministic route and capped all-core configuration, with `Verify25ccShadow` plus the 25cc body set to `Fast`.
- Correct title/load/field/tutorial/active battle, including a clean battle frame at the 150-second cutoff. The formal visual/fatal gate passed, and unknown draw, VM access violation, Vulkan device loss, assertion, frozen-emulation, and terminated-thread counts were all zero.
- The contract stream reported zero output mismatch and zero descriptor overflow. The strict parser intentionally rejected all 809 rows because `body_mode=fast` is blocked from promotion; this is the expected fail-closed result.
- The final body verifier state recorded 15 handled GETs / 245,760 bytes and 15 rejected PUTs that fell back to the normal path. This is narrow coverage, not a complete 25cc replacement.
- Matched late RPCS3 CPU samples averaged 21.9% versus 25.5% body-off, but this comparison was confounded: body-off verification hashed 16 KiB payloads while fast mode bypassed shadow hashing. The later verifier-off isolation supersedes this apparent reduction.
- Log size was 2,660,465 bytes. Compact mode now retains the body-verifier aggregate while suppressing unrelated deep traces.

### Verifier-off body-fast isolation

- The verifier was disabled on both sides so neither route performed payload hashing. The existing clean control was `20260718-164415-allcore-padapi4-verifier-off-f677-first-battle`.
- Initial body-fast run `20260718-172640-allcore-padapi7-bodyfast-compact-verifieroff-first-battle` emitted 1,368 body rows at the inherited 10 Hz cadence. It remained visually/fatal clean, but late RPCS3 CPU averaged 19.45% versus 17.0% control and its log grew to 2,248,945 bytes.
- The body-only compact profiler was reduced to 1 Hz and rebuilt as SHA-256 `482C641CBA5BA8D144445B6C59F595C6E65E5027494D124704BF162F158C8150`.
- Final isolation `20260718-173347-allcore-padapi8-bodyfast-compact1hz-verifieroff-first-battle` again reached correct active battle through 150s with zero unknown draw/fatal rows. It emitted 145 body rows, and the log fell to 1,455,245 bytes, only 94,339 bytes above control.
- Final body coverage was still just 15 GETs / 245,760 bytes, with 15 PUTs rejected to the normal synchronized path.
- Late RPCS3 CPU averaged 16.85% versus 17.0% control, a `-0.9%` difference that is well inside two-sample noise. The actual shortcut has no demonstrated speed or temperature value and is parked.

## Code changes

- `tools/windows_rpcs3_lab.ps1` now requires three consecutive fatal-looking Path-to-Tenuto frames before aborting, so a transient black loading frame cannot end a valid route.
- The same live Windows route now treats `unknown draw command` as actionable and fails closed, matching the post-run promotion gate.
- `rpcs3-upstream/rpcs3/Emu/Cell/lv2/sys_spu.cpp` now makes `verify-25cc-shadow` compact by default: it emits the strict aggregate contract row but suppresses generic GPU/MFC/shadow/descriptor traces. `RPCS3_ES_SPU_HLE_VERIFY_VERBOSE=1` restores the deep trace. Body-fast runs retain their focused body-verifier aggregate without restoring unrelated trace volume.
- Standalone body-fast profiling now uses the same compact path and a 1 Hz aggregate cadence, preventing experimental logging from masquerading as emulation cost.

## Current research direction

- [Partial Cross-Compilation and Mixed Execution for Accelerating Dynamic Binary Translation](https://arxiv.org/abs/2512.00487) supports selective native execution of eligible hot functions. Its reported QEMU results are not transferable numbers, but the architecture matches the title-gated 25cc HLE lane.
- [Boosting Cross-Architectural Emulation Performance by Foregoing the Intermediate Representation Model](https://arxiv.org/abs/2501.03427) reinforces direct translation for common ISA pairs. Its proof-of-concept speedup is not an RPCSX forecast.
- [Dissecting the Impact of Mobile DVFS Governors](https://arxiv.org/abs/2507.02135) shows that independently managed CPU/GPU/memory governors can leave large performance-per-energy gains unused.
- [Phase Matters](https://arxiv.org/abs/2606.27906) shows that accelerator mapping must be phase-specific and can materially reduce steady-state temperature and energy on a modern Qualcomm SoC. The workload and SoC differ from Thor, so only the method transfers.
- Android's current [ADPF guide](https://developer.android.com/games/optimize/adpf), [Thermal API](https://developer.android.com/games/optimize/adpf/thermal), and [Frame Pacing library](https://developer.android.com/games/sdk/frame-pacing/) support sustainable target-duration hints, proactive thermal headroom response, and correct Vulkan presentation pacing.

## Decision and next proof

1. Keep the compact verifier and strict unknown-draw gate.
2. Park the current 25cc body: verifier-off isolation showed no meaningful CPU reduction, only 15 GET hits, and 15 PUT fallbacks.
3. Profile a materially hotter execution family before building another title-gated body; require verify/body-verify mode with zero mismatch/overflow before any Android promotion.
4. Audit ADPF at the actual native frame and worker-thread boundaries. A Java-only session around the wrapper threads would not measure the PPU/SPU/RSX work cycles accurately.
5. Only after a separately cool preflight may one bounded Thor route test an already host-proven candidate. The device remains stopped.
