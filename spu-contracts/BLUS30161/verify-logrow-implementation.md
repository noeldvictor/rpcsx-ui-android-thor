# SPU Verify Log-Row Implementation Scaffold

- Generated: `2026-05-29T10:20:58.9920302-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
- Lane: `mfc-descriptor-family-25cc-9e4000`
- Contract: `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
- Classification: `analysis`, `verify-logrow-implementation-scaffold`, not speed, not `gpu-migration-credit`, not a 200% gate candidate.

## Target Row

- Prefix: `Eternal Sonata SPU contract verifier`
- HLE mode: `contract-25cc-9e4000`
- Example: `Eternal Sonata SPU contract verifier: hle_mode=contract-25cc-9e4000 contract_id=BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0 title=BLUS30161 mode=profile verify_mode=verify-25cc-shadow body_mode=disabled group_name="CellSpursKernelGroup" spu_name="CellSpursKernel0" entry=0x0 image_sig=0x958dfe208b686622 pc=0x25cc tag=31 size=16384 eal=0x9e4000 contract_hits=0 contract_bytes=0 contract_get_hits=0 contract_put_hits=0 contract_reject_total=0 reject_title=0 reject_image_sig=0 reject_pc=0 reject_group=0 reject_spu_name=0 reject_cmd=0 reject_list=0 reject_tag=0 reject_size=0 reject_eah=0 reject_eal_family=0 reject_lsa_range=0 reject_mfc_shuffle=0 reject_accurate_dma=0 reject_fast_mode=0 output_mismatch=0 desc_overflow=0 last_src_hash=0x0 last_dst_pre_hash=0x0 last_dst_post_hash=0x0 cause=0x0 status=0x0`
- Strict parser command: `.\tools\parse_spu_contract_verify_log.ps1 -LogPath <RPCS3.log> -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`

Required keys:
- `hle_mode`
- `contract_id`
- `title`
- `mode`
- `verify_mode`
- `body_mode`
- `group_name`
- `spu_name`
- `entry`
- `image_sig`
- `pc`
- `tag`
- `size`
- `eal`
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
- `output_mismatch`
- `desc_overflow`
- `last_src_hash`
- `last_dst_pre_hash`
- `last_dst_post_hash`
- `cause`
- `status`

## Existing Rows To Reuse

| Row | File | Use |
| --- | --- | --- |
| `Eternal Sonata SPU HLE 25cc family verifier` | `rpcs3\Emu\Cell\lv2\sys_spu.cpp` | family hits, bytes, GET/PUT split, EA-family split, last command fields |
| `Eternal Sonata SPU HLE 25cc shadow verifier` | `rpcs3\Emu\Cell\lv2\sys_spu.cpp` | shadow hits, hashes, output match/mismatch, descriptor overflow context |
| `Eternal Sonata SPU HLE 25cc shadow descriptor` | `rpcs3\Emu\Cell\lv2\sys_spu.cpp` | per-descriptor family, direction, command shape, hashes, mismatch, overflow |
| `Eternal Sonata SPU HLE 25cc body verifier` | `rpcs3\Emu\Cell\lv2\sys_spu.cpp` | body verify/fast guard visibility and PUT rejects |

## Derived Fields

| Target | Source |
| --- | --- |
| `contract_hits` | spu_hle_25cc_shadow_ea9e4000_hits or sum(desc.hits where desc.family == 1) |
| `contract_bytes` | sum(desc.bytes where desc.family == 1 and desc.eal == 0x9e4000) |
| `contract_get_hits` | sum(desc.hits where desc.family == 1 and desc.direction == 1) |
| `contract_put_hits` | sum(desc.hits where desc.family == 1 and desc.direction == 2) |
| `output_mismatch` | spu_hle_25cc_shadow_output_mismatch or sum matching descriptor output_mismatch |
| `desc_overflow` | spu_hle_25cc_shadow_desc_overflow |
| `last_src_hash` | spu_hle_25cc_shadow_last_src_hash |
| `last_dst_pre_hash` | spu_hle_25cc_shadow_last_dst_pre_hash |
| `last_dst_post_hash` | spu_hle_25cc_shadow_last_dst_post_hash |

## Reject Buckets

| Bucket | Source |
| --- | --- |
| `reject_title` | derived before title gate; should stay zero inside BLUS30161-only logger |
| `reject_image_sig` | increment when image_sig != 0x958dfe208b686622 |
| `reject_pc` | increment when pc != 0x25cc |
| `reject_group` | increment when group_name != CellSpursKernelGroup |
| `reject_spu_name` | increment when spu_name != CellSpursKernel0 |
| `reject_cmd` | increment when base command is not MFC GET or PUT |
| `reject_list` | increment when MFC list bit is set |
| `reject_tag` | increment when tag != 31 |
| `reject_size` | increment when size != 0x4000 |
| `reject_eah` | increment when eah != 0 |
| `reject_eal_family` | increment when eal != 0x9e4000 for this priority-1 row |
| `reject_lsa_range` | increment when lsa + size exceeds SPU_LS_SIZE |
| `reject_mfc_shuffle` | increment when MFC transfer shuffling is enabled |
| `reject_accurate_dma` | increment when accurate DMA is enabled |
| `reject_fast_mode` | increment when verify skip/fast, 25cc body fast, GPU fast, or Vulkan compute fast path is active |

## Implementation Order

| Step | File | Action |
| ---: | --- | --- |
| 1 | `rpcs3\Emu\Cell\lv2\sys_spu.cpp` | emit one additional parseable notice row after the existing 25cc shadow descriptor rows |
| 2 | `rpcs3\Emu\Cell\SPUThread.cpp` | if reject buckets cannot be derived at dump time, add a verify-only classifier helper that mirrors get_es_mfc_25cc_runtime_family_raw without changing behavior |
| 3 | `rpcs3\Emu\Cell\SPUThread.h` | add persistent reject-bucket counters only if the dump-time derivation is insufficient |
| 4 | `tools/windows log parser` | accept only rows with contract_id=BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0 and hle_mode=contract-25cc-9e4000 |

## Acceptance Checks
- No memcpy/body/fast path behavior changes in the first patch.
- The row appears under RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow.
- The row does not appear under blocked fast modes except as reject_fast_mode > 0.
- The strict parser command exits 0 only when at least one accepted row exists and contract_hits >= 1.
- contract_hits equals contract_get_hits + contract_put_hits.
- output_mismatch == 0 and desc_overflow == 0 are required before any promotion.
- Field, Options/menu, and first-battle visual gates are still required.

Next action: Apply the log-only row in the Windows upstream checkout after isolating or stashing unrelated upstream changes; then run field/Options/first-battle verifier captures.
