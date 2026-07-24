# Eternal Sonata 25cc Route-Safety Audit

- Generated: `2026-07-24T19:13:56.3180899-04:00`
- Classification: source/RAG route-safety audit, not speed, not GPU migration credit, not promotion evidence.

## Latest unsafe 25cc run

- Run: `20260724-185816-cpu4-loader-control-left200x2-diag200-25cc-dirsplit-fieldproof-windows`
- Visual status: `NO_FIELD_LIKE_SCREENSHOT`; gate: `failed`.`; first field-like: `none.`
  - `cutscene-or-nonfield-small-png`: `18`.
- Contract rows: rows=161, hits=326, bytes=5341184, GET=160, PUT=166, output_mismatch=0, desc_overflow=0

## Source alignment

- SPU hook source: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp`
- Contract log source: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\lv2\sys_spu.cpp`
- `compute_es_spu_hle_shadow_hash`: line 1952
- `begin_es_spu_hle_shadow_sample`: line 1974
- `finish_es_spu_hle_shadow_sample`: line 2098
- `record_es_spu_hle_25cc_shadow_sample`: line 1989
- `std::memcmp(src, dst, cmd.size)`: line 2110
- compact contract row logger: line 1667
- verbose trace opt-in: line 451

## Route-safety read

- The active 25cc shadow verifier is behavior-preserving, but it samples matched 16 KiB transfers by hashing source and destination before the DMA, then hashing destination and comparing source/destination after the DMA.
- For the latest unsafe run this implies about `20.375` MiB of extra payload reads in the SPU MFC hot path before any logging cost, based on `326` contract hits at 16 KiB and four full payload passes per hit.
- The compact logger already suppresses deep trace rows by default, so the remaining likely perturbation is payload sampling cost/timing, not text log volume.
- Counts and descriptor shape are still valuable, but promotion must remain blocked unless a full-payload verification mode proves zero mismatch/overflow across field, Options/menu, and first battle.

## Recommended next source change

- Add an explicit 25cc shadow payload mode, for example `RPCS3_ES_SPU_HLE_25CC_SHADOW_PAYLOAD=full|sampled|counts`, defaulting route-repair runs to `counts` or sparse `sampled`.
- Emit a `payload_mode=` field in the strict contract row and teach the parser to reject promotion unless `payload_mode=full`.
- In counts/sampled mode, keep descriptor GET/PUT/family/bytes/overflow counters but avoid or sparsely run the 16 KiB source/destination hashing and memcmp path.
- Only after a counts/sampled 25cc run reaches clean field should a full-payload verifier rerun be attempted, followed by Options/menu and first battle before any body/codegen/Vulkan fast mode.

## Patch artifact

- Proposed upstream patch: `spu-contracts\BLUS30161\25cc-shadow-payload-mode-upstream.patch`
- Intended target checkout: `..\rpcs3-upstream`
- Apply/build gate: apply the patch to the sibling Windows upstream checkout, rebuild RPCS3, then run `Verify25ccShadow` with `EternalSonataSpuHle25ccShadowPayload Counts` for route repair only.
- Promotion gate: rerun with `EternalSonataSpuHle25ccShadowPayload Full` and parse with `-RequiredPayloadMode Full` before field + Options/menu + first-battle evidence can count.

## 2026-07-24 19:32 ET - upstream source applied

- The payload-mode split is now applied to sibling checkout ..\\rpcs3-upstream and the repo-local patch artifact has been regenerated from that actual source diff.
- Build and route proof are still pending; counts/sampled mode is route-repair evidence only, while promotion still requires full payload mode plus valid field, Options/menu, and first-battle proof.
