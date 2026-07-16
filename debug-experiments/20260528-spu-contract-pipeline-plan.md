# SPU Contract Pipeline Plan

- Date: 2026-05-28
- Title: Eternal Sonata `BLUS30161`
- Classification: `analysis`, `spu-contract-scaffold`
- Not speed, not `gpu-migration-credit`, not a 200% gate result.

## Decision

The next smart SPU lane is not manual Ghidra lookup. It is a repeatable
contract compiler:

`runtime logs -> SPU window extractor -> Ghidra headless -> contract JSON -> emulator verifier -> fast path`

SPU work stays verify-only until field, Options/menu, and first-battle visuals
are clean with zero relevant mismatches, zero descriptor overflow, and zero
fatal log hits.

## First Artifact

`tools/spu_contract_pipeline.ps1`

Current seed command:

```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

Current outputs:

- `spu-contracts\BLUS30161\latest-summary.md`
- `spu-contracts\BLUS30161\index.json`
- `spu-contracts\BLUS30161\verify-counter-plan.md`
- `spu-contracts\BLUS30161\verify-counter-plan.json`
- `spu-contracts\BLUS30161\BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0.json`
- `spu-contracts\BLUS30161\BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0.json`

## Contract Lanes

- `0x25cc/0x9e4000`: MFC descriptor and PUT-heavy DMA family. CPU/SPU
  HLE/codegen first; GPU compute remains parked.
- `0x451c`: TCX/SPURS list-copy and descriptor pressure. Contract and verify
  before fast mode.
- SPURS/wait HLE: reduce busy-loop and scheduler pressure while preserving
  GETLLAR/PUTLLC semantics.
- Optional patch lane: reversible, title-gated, offline-only, and separate
  from emulator speed claims.

## Acceptance Gate

Before any fast path:

- Exact runtime anchor: title, image signature, PC, group, SPU name.
- Cell contract: MFC order, tags, waits, DMA alignment/size, local-store range,
  and reservation behavior preserved.
- Verify-only emulator counters exist for the contract.
- Field, Options/menu, and first-battle visuals pass.
- `output_mismatch=0`, `descriptor_overflow=0`, and `fatal_log_hits=0`.

## Next Code Step

Wire one selected contract, likely `0x25cc/0x9e4000`, into a verify-only
emulator counter keyed by title, image signature, PC, group, command shape, and
GET/PUT direction. Do not enable bodyfast/codegen until that counter survives
the full visual gate.

## 2026-05-28 Verify-Counter Plan Output

Update:

- `tools\spu_contract_pipeline.ps1` now emits a concrete verify-counter plan in
  both JSON and Markdown.
- Priority 1: `mfc-descriptor-family-25cc-9e4000`, contract
  `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`.
- Priority 2: `tcx-spurs-descriptor-family-451c`, contract
  `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`.
- The priority-1 lane records 11 predicates and 22 required counters, including
  hits, bytes, GET/PUT splits, rejects, duration, command fields, hashes,
  `output_mismatches`, `descriptor_overflow`, and `fatal_log_hits`.
- The generated source anchors exist in the local `rpcs3-upstream` checkout:
  `SPUThread.cpp` and `SPULLVMRecompiler.cpp`.

Classification:

- `analysis`.
- `verify-counter-plan`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement only the priority-1 verify-only counter lane first. Keep
  `bodyfast`, `codegen-fast`, and `vulkan-compute` blocked until field,
  Options/menu, and first-battle visuals pass with zero mismatches, zero
  descriptor overflow, and zero fatal log hits.

## 2026-05-28 Source-Alignment Output

Update:

- `tools\spu_contract_pipeline.ps1` now emits
  `spu-contracts\BLUS30161\source-alignment.json` and
  `spu-contracts\BLUS30161\source-alignment.md`.
- The alignment was generated from
  `20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows`.
- Windows upstream has all checked priority-1 `0x25cc/0x9e4000` predicate
  patterns present in `SPUThread.cpp`: runtime family classifier, tag check,
  size check, EA family, and existing callsite.
- Windows upstream also has the `0x451c` dynamic-list predicate and LLVM verify
  callout anchors present.
- Vendored RPCSX has the generic Thor DMA probe hooks, but the checked
  `0x25cc`/`0x451c` contract predicates are absent there.

Classification:

- `analysis`.
- `source-alignment`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Add explicit contract-id labeled verify-only counters and reject buckets in
  the Windows upstream hooks for `mfc-descriptor-family-25cc-9e4000`.
- Do not port this to vendored RPCSX or enable `bodyfast`, `codegen-fast`, or
  `vulkan-compute` until field, Options/menu, and first-battle visual gates pass
  with zero mismatches, zero descriptor overflow, and zero fatal log hits.

## 2026-05-28 Verify-Counter Schema Output

Update:

- `tools\spu_contract_pipeline.ps1` now emits
  `spu-contracts\BLUS30161\verify-counter-schema.json` and
  `spu-contracts\BLUS30161\verify-counter-schema.md`.
- The schema is for priority-1 lane
  `mfc-descriptor-family-25cc-9e4000`, contract
  `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`.
- Required verify-only environment:
  `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` and
  `RPCS3_ES_SPU_HLE_25CC_BODY=disabled-or-verify-only`.
- Blocked fast values include `RPCS3_ES_SPU_HLE_VERIFY=skip/fast`,
  `RPCS3_ES_SPU_HLE_25CC_BODY=fast`, `RPCS3_ES_GPU_PROBE=fast`, and any
  Vulkan compute fast path.
- Predicate/reject buckets are now explicit for title, image signature, PC,
  group, SPU name, command, list bit, tag, size, EAH/EAL family, local-store
  range, MFC shuffling, accurate DMA, and fast mode.
- Existing upstream counters were mapped to the schema: family hits/bytes,
  GET/PUT split, EA family split, shadow hashes, output match/mismatch,
  descriptor overflow, and body PUT rejects.

Classification:

- `analysis`.
- `verify-counter-schema`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement only the parseable log-label/reject-bucket row for this contract in
  the Windows upstream hooks.
- Do not change copy/body behavior, port to vendored RPCSX, or enable fast mode.

## 2026-05-28 Verify Log-Row Scaffold

Update:

- `tools\spu_contract_pipeline.ps1` now emits
  `spu-contracts\BLUS30161\verify-logrow-implementation.json` and
  `spu-contracts\BLUS30161\verify-logrow-implementation.md`.
- The scaffold targets a single additional parseable Windows upstream notice row:
  `Eternal Sonata SPU contract verifier` with
  `hle_mode=contract-25cc-9e4000` and
  `contract_id=BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`.
- It reuses existing upstream 25cc family, shadow, descriptor, and body verifier
  rows instead of adding behavior changes.
- Required keys include contract identity, image/PC/tag/size/EAL, hits, bytes,
  GET/PUT split, reject buckets, mismatch/overflow, hashes, cause, and status.
- The upstream RPCS3 checkout is currently dirty with unrelated work, so this
  round deliberately produced a repo-local scaffold and did not edit upstream
  C++ directly.

Classification:

- `analysis`.
- `verify-logrow-implementation-scaffold`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Isolate the dirty upstream checkout, then apply only the log-only row.
- Do not modify memcpy/body behavior, port to vendored RPCSX, or enable fast
  mode before clean field, Options/menu, and first-battle verifier captures.

## 2026-05-28 Verify Log-Row Parser

Update:

- Added `tools\parse_spu_contract_verify_log.ps1` for future
  `Eternal Sonata SPU contract verifier` rows.
- The parser loads `spu-contracts\BLUS30161\verify-logrow-implementation.json`,
  filters only matching verifier rows, and validates required keys,
  `hle_mode`, full contract id, GET/PUT hit split, `output_mismatch=0`, and
  `desc_overflow=0`.
- The generated scaffold example now includes all required fields and the full
  contract id.
- Validation result: the generated example parsed as `accepted_rows=1`,
  `rejected_rows=0`; a noise line parsed as `rows=0` with
  `no contract verifier rows found`.
- The parser always emits `promotion_ready=false`; field, Options/menu,
  first-battle visuals, host grade, and fatal-log checks remain external gates.

Classification:

- `analysis`.
- `verify-logrow-parser`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- When the upstream checkout is isolated, implement only the log-only verifier
  row and run this parser on the resulting RPCS3 log before any fast/body/codegen
  path is considered.

## 2026-05-28 Strict Verify Log-Row Gate

Update:

- `tools\parse_spu_contract_verify_log.ps1` now supports strict verifier gating
  flags: `-RequireAcceptedRow`, `-RequireNoRejected`, `-MinContractHits`, and
  `-FailOnGate`.
- `spu-contracts\BLUS30161\verify-logrow-implementation.json` and `.md` now
  include the strict parser command for future RPCS3 logs:
  `.\tools\parse_spu_contract_verify_log.ps1 -LogPath <RPCS3.log> -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`.
- Validated parser behavior:
  generated zero-hit example parses in non-strict mode; a synthetic one-hit row
  passes strict mode; the zero-hit example and a noise-only input both exit `2`
  under strict `-MinContractHits 1 -FailOnGate`.
- The gate is still parser/counter consistency only. It is not speed, not GPU
  migration, not first-battle proof, and not a 200% candidate.

Classification:

- `analysis`.
- `verify-logrow-strict-gate`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement the log-only upstream row only after isolating the dirty upstream
  checkout, then require this strict parser gate before any bodyfast/codegen or
  GPU fast-path promotion discussion.

## 2026-07-15 Windows 25cc Contract-Row Hardening

Update:

- The deterministic harness refiner found no strong new route base: six of the
  eight newest runs were cutscene/non-field, one was a black overlay, and the
  newest run only reached loaded-field triage. No gameplay run was spent on
  that weak route.
- The Windows upstream checkout was clean, so the existing priority-1
  `0x25cc / 0x9e4000` contract row was audited and fixed in local commit
  `7bddf372c566ef5958ec9093e935f3744d8aca5e`.
- `reject_eah` had incorrectly compared `desc.eal`; it now remains zero for
  recorded descriptors because the runtime classifier rejects non-zero EAH
  before descriptor creation.
- Contract identity fields are fixed to `pc=0x25cc`, `tag=31`, `size=16384`,
  and `eal=0x9e4000`. Output mismatch and last hashes now come only from the
  matching family-1 descriptors, not the most recent unrelated 25cc family.
- The parser/schema now reject wrong title/image/PC/group/SPU/transfer anchors,
  incorrect byte-per-hit totals, inconsistent reject-bucket totals, body fast
  mode, and non-zero `reject_fast_mode`.

Offline validation:

- Windows Release build command:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 8`.
- Result: success in `1688.7 s`; `sys_spu.cpp` compiled and LTCG linked
  `build-msvc\bin\rpcs3.exe`.
- Executable SHA256:
  `BDCD118BB513178A72885B072840316048B5FD8DE1D144640CF5CB55ABAC47B5`.
- Strict synthetic parser matrix: valid target row exited `0`; wrong EAL,
  wrong bytes, wrong reject total, body fast, and fast reject bucket each
  exited `2` with the intended rejection reason.
- No RPCS3 gameplay launch, ADB action, deployment, Thor launch, sensor query,
  or device profiler was used.

Classification:

- `analysis`.
- `verify-only-contract-accounting`.
- Build validated, runtime capture pending.
- Not speed, not `gpu-migration-credit`, and not a 200% gate candidate.

Next:

- Use the rebuilt Windows binary for one bounded `verify-25cc-shadow` capture
  only when the state-aware route reaches a valid field/menu/battle checkpoint.
- Require the strict parser gate and clean visuals before considering any
  body/codegen specialization; do not port this lane to Android yet.

## 2026-07-15 Source-Aligned Runtime Contract Proof

Update:

- The first bounded corrected-contract replay on the older instrumented source
  failed after field load with unknown draw commands, a PPU VM access violation
  at `0x002aedd0`, and corrupt crash-overlay visuals. Its `473` accepted
  contract rows and zero mismatch/overflow proved parser consistency only.
- Source alignment found the checkout missing upstream RPCS3 commit `e379fba`,
  which implements PPU reservation priority over SPUs and disables the unsafe
  CellSpurs JobChain acquire pattern. It was applied locally as
  `e12beb222fea26fa5e5f86fa507ad91536fa4d60`.
- Rebuilt identity is `0.0.41-597-e12beb22`; executable SHA256 is
  `C31622E54441A6946A9AFC6986E8F7C9193F55541E158B2959BEE95B07AA3CC9`.
- The identical bounded route then stayed visually correct on a moving field
  through `185s`, with all five host snapshots external-clean and zero targeted
  fatal/draw/access/Vulkan/device-lost/assertion signatures.
- Strict parser result: `732` rows, `732` accepted, `0` rejected, `1878` hits,
  `30769152` bytes, output mismatch `0`, descriptor overflow `0`.
- The route did not enter battle despite checkpoint filenames. This is a valid
  field runtime counterproof, not first-battle or speed proof.

Harness hardening:

- Clean/battle visual gates now require a fatal-clean `RPCS3.log`.
- BattleRoute rejects durations below its fixed `220s` late-proof deadline.
- Dominant verifier record types use direct dispatch, and synchronous generic
  probe summaries are deferred for logs above `32 MiB` so a completed run does
  not appear hung.

Classification:

- `analysis`.
- `verify-only-contract-runtime-proof`.
- `valid-moving-field-counterproof`.
- Not speed, not `gpu-migration-credit`, not first battle, and not a 200% gate
  candidate.

Next:

- Re-prove Options/menu and enter a real first battle on the exact rebuilt
  binary before any 25cc body/codegen specialization or Android port.
- Keep verifier/body-fast separation: shadow verify on, body off, fixed config,
  strict parser, manual visuals, and fatal-clean log for every promotion proof.

## 2026-07-15 Exact-Binary Options Proof

Update:

- Run `20260715-223137-cpu4-verify25cc-e379fba-options-fastselect-windows`
  used the same repaired `e12beb22` binary and capped verifier configuration as
  the clean moving-field proof.
- Manual screenshots confirmed correct title selection and the full Options page
  at `78s`, `88s`, and `130s`, with no missing UI, flicker, or corruption.
- Six host snapshots were external-clean; targeted fatal/draw/access/Vulkan/
  device-lost/assertion counts were all zero.
- Strict contract gate passed `461/461` rows with `957` hits, `15679488` bytes,
  zero rejected rows, output mismatches, or descriptor overflow.
- The large-log post-run ceiling deferred the `45.1 MB` generic summary and let
  the wrapper finish normally.

Classification:

- `valid-options-counterproof`.
- `verify-only-contract-runtime-proof`.
- Not speed, not first battle, and not a promotion result.

Next:

- Enter and hold a genuine first battle on the exact repaired binary. Do not
  rerun capped field or Options, enable bodyfast, or port the contract to Android
  before that proof.

## 2026-07-15 Current-Upstream Normal-Scheduler Baseline

Update:

- Adaptive load gating replaced unsafe fixed-delay save dismissal; a late fixed
  dismissal had produced `VK_ERROR_DEVICE_LOST` and black output.
- Both verifier-on and all-probes-off custom-fork routes failed after movement
  under CPU affinity `0x0f`. Clean current upstream reproduced guest PPU
  `0x002aedd0` reading `0x40` under the same four-core cap, so that failure is a
  scheduler-stress result rather than verifier proof.
- Current upstream `1269ebff` was made buildable on MSVC with local zlib commit
  `c433cc7` and preserved curl/wolfSSL compatibility commit `6311394472`.
  Exact Release executable SHA256:
  `7A9E5E0CA3465359E8E6339D14B29359A9847CBAD9450C8AC087218B404AEC28`.
- Normal scheduling cleared the same adaptive route: correct field, real
  tutorial prompt, active first battle, and held battle through `175s`, with
  zero actionable fatal signatures and clean host evidence.
- The capped 34-sample title series averaged `29.9947 FPS` (`29.96` to
  `30.02`). This is a correctness baseline only.
- Explicit macro screenshots now provide a dark/small crash-overlay fallback
  when the live RPCS3 log is delayed, preventing a frozen overlay from being
  mislabeled as a battle screenshot.

Classification:

- `valid-current-upstream-first-battle-baseline`.
- `four-core-affinity-stress-failure`.
- Not speed, not `gpu-migration-credit`, and not a 200% gate candidate.

Next:

- Run one uncapped all-core current-upstream field-to-first-battle measurement
  with all custom paths off and the same adaptive/fatal/visual gates.
- Do not use the monolithic custom fork for promotion and do not spend Thor
  heat until the Windows route demonstrates stable 200% moving gameplay.

## 2026-07-15 Windows 200% Gate Cleared

Result:

- Clean current upstream `1269ebff`, normal all-core scheduling, `240/240`
  frame/vblank, Accurate SPU Reservations on, Accurate SPU DMA off, and all
  custom probes/fast modes off reached the correct Path-to-Tenuto field and
  first battle in
  `20260715-230705-clean-upstream1269ebf-allcore-uncap240-frame-scaled20-first-battle-speed-windows`.
- Thirty field/battle samples averaged `120.002 FPS` (`119.85` to `120.38`),
  with correct battle visuals through `150s`, zero actionable fatal hits, and
  external-clean host evidence.
- Exact matching Options run
  `20260715-231132-clean-upstream1269ebf-allcore-uncap240-frame-scaled20-options-speed-windows`
  held the complete page through `70s` and averaged `240.072 FPS` across six
  samples, with zero actionable fatal hits and clean host evidence.
- The full Windows field/menu/first-battle 200% requirement is therefore met.

Harness contract:

- Use `gate_title_menu`, `gate_load_target`, `gate_load_complete`, `gate_field`,
  and `gate_first_battle_prompt` for uncapped routes.
- At title `240 FPS`, use a `20 ms` directional pulse; longer `80/300 ms`
  pulses repeat past Load into Options. Scale movement by guest frame count.
- The load-target classifier now accepts one candidate path, avoiding repeated
  full-run screenshot scans.

Next:

- Thor is no longer blocked by the Windows proof gate, but device work must be
  thermally bounded: read temperature first, do not launch if hot, and use one
  short baseline/port validation rather than a heat-soak.
- Treat the `120 FPS` result as a Windows performance envelope, not predicted
  Thor FPS. Any Android claim still needs real Adreno frame-time and visual
  evidence.
