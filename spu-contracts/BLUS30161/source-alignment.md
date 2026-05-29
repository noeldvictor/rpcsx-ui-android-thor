# SPU Contract Source Alignment

- Generated: `2026-05-29T16:11:41.8769009-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
- Classification: `analysis`, `source-alignment`, not speed, not `gpu-migration-credit`, not a 200% gate candidate.

| Source | Lane | Feature | Status | Patterns |
| --- | --- | --- | --- | ---: |
| `windows-upstream` | `mfc-descriptor-family-25cc-9e4000` | `25cc runtime family predicate` | `present` | 5/5 |
| `windows-upstream` | `tcx-spurs-descriptor-family-451c` | `451c dynamic list predicate` | `present` | 3/3 |
| `windows-upstream` | `verify-only-emulator-counters` | `SPU HLE verify hooks` | `present` | 4/4 |
| `windows-upstream` | `llvm-verify-candidate` | `LLVM verify callout` | `present` | 4/4 |
| `vendored-rpcsx-core` | `generic-dma-probe` | `Thor generic DMA probe` | `present` | 3/3 |
| `vendored-rpcsx-core` | `mfc-descriptor-family-25cc-9e4000` | `Vendored 25cc/451c contract predicates` | `absent` | 0/3 |

## Conclusions
- The Windows upstream source already contains the priority-1 25cc runtime-family predicate for the 0x9e4000 descriptor family.
- The Windows upstream source also contains the 451c dynamic-list classifier, but it should stay priority 2.
- The vendored RPCSX core currently has a generic Thor DMA probe, not the Windows 25cc/451c contract predicate lane.
- The next non-duplicative implementation step is explicit verify-only contract counters and reject buckets in the Windows upstream hooks.

## Pattern Lines

### windows-upstream: 25cc runtime family predicate

- File: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp`
- Expectation: Priority-1 contract can be keyed by image, PC, tag, size, EA family, and command shape.
- Interpretation: If present, the next useful change is counter labeling/reject accounting, not inventing a new predicate.
- `get_es_mfc_25cc_runtime_family_raw`: line 656
- `cmd.tag != 31`: line 672
- `cmd.size != 0x4000`: line 673
- `cmd.eal == 0x9e4000`: line 683
- `get_es_mfc_25cc_runtime_family(spu, cmd)`: line 1938

### windows-upstream: 451c dynamic list predicate

- File: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp`
- Expectation: Priority-2 contract can reuse the existing 451c list-family classifier after the 25cc lane is labeled.
- Interpretation: Use as a second lane after the 25cc verify counters are explicit.
- `get_es_mfc_451c_dynamic_list_family`: line 616
- `spu->pc != 0x451c`: line 580
- `record_es_mfc_dynamic_cmd`: line 711

### windows-upstream: SPU HLE verify hooks

- File: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp`
- Expectation: Verify-only counters should extend existing HLE verification hooks instead of adding fast mode.
- Interpretation: Use these hooks for contract-id counters, reject buckets, and source/destination hashes.
- `RPCS3_ES_SPU_HLE_VERIFY`: line 349
- `record_es_spu_hle_verify_candidate`: line 1883
- `is_es_spu_hle_25cc_shadow_enabled`: line 401
- `is_es_spu_hle_25cc_body_enabled`: line 455

### windows-upstream: LLVM verify callout

- File: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp`
- Expectation: LLVM-generated paths can report the same contract counters as interpreter/MFC paths.
- Interpretation: Keep this in verify-only parity before any codegen-fast path.
- `exec_es_spu_hle_verify_candidate`: line 4401
- `pc != 0x25cc`: line 4412
- `else if (pc == 0x451c)`: line 4497
- `spu_es_hle_verify_candidate`: line 5511

### vendored-rpcsx-core: Thor generic DMA probe

- File: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\app\src\main\cpp\rpcsx\kernel\cellos\src\sys_spu.cpp`
- Expectation: Vendored core has generic DMA profiling, but this is not the 25cc/451c contract lane.
- Interpretation: Do not port or enable Android fast paths during the Windows gate; use this only as later porting context.
- `thor_es_dma_superpath_mode`: line 288
- `record_thor_es_dma_seen`: line 428
- `log_thor_es_dma_probe`: line 455

### vendored-rpcsx-core: Vendored 25cc/451c contract predicates

- File: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\app\src\main\cpp\rpcsx\kernel\cellos\src\sys_spu.cpp`
- Expectation: These should remain absent or partial until Windows proof is clean enough to port.
- Interpretation: Current vendored core is not the implementation target for this heartbeat lane.
- `get_es_mfc_25cc_runtime_family_raw`: missing
- `get_es_mfc_451c_dynamic_list_family`: missing
- `record_es_mfc_dynamic_cmd`: missing

Next action: Add contract-id labeled verify-only counters for mfc-descriptor-family-25cc-9e4000, then re-run field, Options/menu, and first-battle gates before any fast path.
