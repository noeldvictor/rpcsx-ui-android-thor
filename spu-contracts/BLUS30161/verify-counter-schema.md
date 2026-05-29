# SPU Verify Counter Schema

- Generated: `2026-05-29T16:11:41.8769009-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
- Lane: `mfc-descriptor-family-25cc-9e4000`
- Contract: `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
- Classification: `analysis`, `verify-counter-schema`, not speed, not `gpu-migration-credit`, not a 200% gate candidate.

## Required Environment

- `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow`
- `RPCS3_ES_SPU_HLE_25CC_BODY=disabled-or-verify-only`
- Blocked: `RPCS3_ES_SPU_HLE_VERIFY=skip, RPCS3_ES_SPU_HLE_VERIFY=fast, RPCS3_ES_SPU_HLE_25CC_BODY=fast, RPCS3_ES_GPU_PROBE=fast, vulkan-compute-fast-path`

## Predicate And Reject Buckets

| Field | Op | Value | Reject bucket |
| --- | --- | --- | --- |
| `title_id` | `equals` | `BLUS30161` | `reject_title` |
| `image_sig` | `equals` | `0x958dfe208b686622` | `reject_image_sig` |
| `pc` | `equals` | `0x25cc` | `reject_pc` |
| `group` | `equals` | `CellSpursKernelGroup` | `reject_group` |
| `spu_name` | `equals` | `CellSpursKernel0` | `reject_spu_name` |
| `base_cmd` | `in` | `MFC_GET_CMD,MFC_PUT_CMD` | `reject_cmd` |
| `list_bit` | `equals` | `False` | `reject_list` |
| `tag` | `equals` | `31` | `reject_tag` |
| `size` | `equals` | `0x4000` | `reject_size` |
| `eah` | `equals` | `0x0` | `reject_eah` |
| `eal` | `equals` | `0x9e4000` | `reject_eal_family` |
| `lsa` | `local-store-range` | `lsa + size <= SPU_LS_SIZE` | `reject_lsa_range` |
| `mfc_transfers_shuffling` | `equals` | `False` | `reject_mfc_shuffle` |
| `spu_accurate_dma` | `equals` | `False` | `reject_accurate_dma` |
| `fast_mode` | `equals` | `False` | `reject_fast_mode` |

## Existing Upstream Counters
- `spu_hle_25cc_family_hits`
- `spu_hle_25cc_family_success`
- `spu_hle_25cc_family_fail`
- `spu_hle_25cc_family_bytes`
- `spu_hle_25cc_family_total_us`
- `spu_hle_25cc_family_max_total_us`
- `spu_hle_25cc_family_get_hits`
- `spu_hle_25cc_family_put_hits`
- `spu_hle_25cc_family_ea9e4000_hits`
- `spu_hle_25cc_family_ea4f0b80_hits`
- `spu_hle_25cc_family_exact_a1c000_hits`
- `spu_hle_25cc_family_other_ea_hits`
- `spu_hle_25cc_family_last_family`
- `spu_hle_25cc_family_last_pc`
- `spu_hle_25cc_family_last_cmd`
- `spu_hle_25cc_family_last_tag`
- `spu_hle_25cc_family_last_size`
- `spu_hle_25cc_family_last_lsa`
- `spu_hle_25cc_family_last_eal`
- `spu_hle_25cc_shadow_hits`
- `spu_hle_25cc_shadow_bytes`
- `spu_hle_25cc_shadow_get_hits`
- `spu_hle_25cc_shadow_put_hits`
- `spu_hle_25cc_shadow_ea9e4000_hits`
- `spu_hle_25cc_shadow_src_repeats`
- `spu_hle_25cc_shadow_dst_pre_repeats`
- `spu_hle_25cc_shadow_dst_post_repeats`
- `spu_hle_25cc_shadow_dst_changed`
- `spu_hle_25cc_shadow_dst_unchanged`
- `spu_hle_25cc_shadow_output_match`
- `spu_hle_25cc_shadow_output_mismatch`
- `spu_hle_25cc_shadow_last_src_hash`
- `spu_hle_25cc_shadow_last_dst_pre_hash`
- `spu_hle_25cc_shadow_last_dst_post_hash`
- `spu_hle_25cc_shadow_desc_overflow`
- `spu_hle_25cc_body_put_rejects`

## Counters To Add Or Label
- `contract_id=mfc-descriptor-family-25cc-9e4000`
- `contract_hits`
- `contract_bytes`
- `contract_get_hits`
- `contract_put_hits`
- `contract_reject_total`
- `reject_title`
- `reject_image_sig`
- `reject_pc`
- `reject_group`
- `reject_spu_name`
- `reject_cmd`
- `reject_list`
- `reject_tag`
- `reject_size`
- `reject_eah`
- `reject_eal_family`
- `reject_lsa_range`
- `reject_mfc_shuffle`
- `reject_accurate_dma`
- `reject_fast_mode`
- `last_src_hash`
- `last_dst_pre_hash`
- `last_dst_post_hash`

## Parser Acceptance
- contract_id is present in the log row
- contract_hits == spu_hle_25cc_family_ea9e4000_hits for the 0x9e4000 lane
- contract_hits == contract_get_hits + contract_put_hits
- spu_hle_25cc_shadow_output_mismatch == 0
- spu_hle_25cc_shadow_desc_overflow == 0
- fatal_log_hits == 0
- visual_gate in field, Options/menu, and first-battle is clean before promotion

## Implementation Sites

| File | Area | Action |
| --- | --- | --- |
| `rpcs3\Emu\Cell\SPUThread.h` | `es_gpu_probe_state_t` | add contract-id/reject bucket fields only if log labeling cannot derive them |
| `rpcs3\Emu\Cell\SPUThread.cpp` | `get_es_mfc_25cc_runtime_family_raw` | preserve predicate; optionally split reject reasons in a verify-only helper |
| `rpcs3\Emu\Cell\SPUThread.cpp` | `record_es_mfc_dynamic_cmd` | label 0x9e4000 family rows with contract_id and reject buckets |
| `rpcs3\Emu\Cell\SPUThread.cpp` | `record_es_spu_hle_25cc_shadow_sample` | reuse src/dst hashes, mismatch, descriptor overflow, and direction fields |
| `rpcs3\Emu\Cell\lv2\sys_spu.cpp` | `probe log dump` | emit contract_id, reject buckets, existing family counters, shadow hashes, mismatch, and overflow in one parseable row |

Next action: Implement the log-label/reject-bucket row for the priority-1 lane; do not change copy/body behavior.
