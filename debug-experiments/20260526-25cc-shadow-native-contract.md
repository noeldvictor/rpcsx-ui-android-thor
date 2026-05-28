# Eternal Sonata 0x25cc Shadow Native Contract

- Generated: 2026-05-28 13:06:05 -04:00
- Classification: `analysis`, `spu-hle-25cc-shadow-native-contract`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% moving-gameplay gate candidate.

## Inputs

- Hash target CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-experiments\20260526-25cc-pattern-hash-targets.csv`
- Shadow run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows`
- Shadow profile CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-spu-hle-25cc-shadow-profile.csv`
- Runtime pattern CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-runtime-family-patterns.csv`
- Source root inspected: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`
- Contract CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-experiments\20260526-25cc-shadow-native-contract.csv`

## Contract Summary

- Selected shadow verifier output is `fatal-run sizing evidence only`: `11988` hits, `187.31 MB`, GET/PUT `5688/6300`, changed/unchanged `3325/8663`, match/mismatch `11988/0`.
- Runtime-seen target patterns are PUT-heavy: `5` groups, `274.17 MB` latest-run bytes, GET `42.65 MB` (`15.6%`), PUT `231.52 MB` (`84.4%`).
- Multi-run atlas coverage for those runtime-seen groups is `2.09 GB`.
- Therefore a GET-only body copy can only prove a minority of the runtime-seen hot byte mass. Direction-split PUT shadow evidence is now visible, but it must be reproved on clean field/menu/battle visuals before any bodyfast or skip promotion.

## Runtime-Seen PUT-Heavy Targets

| Rank | Pattern | Atlas Bytes | Runtime Records | Runtime Bytes | GET | PUT | Max Cmds | Body Gap |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | `0x209c1716c9de855f` | 482.88 MB | 48 | 73.35 MB | 11.44 MB (15.6%) | 61.91 MB (84.4%) | 159 | `put-heavy-get-only-body-caps-coverage` |
| 2 | `0xf7bf30bddad5855f` | 510.38 MB | 39 | 59.60 MB | 9.29 MB (15.6%) | 50.30 MB (84.4%) | 159 | `put-heavy-get-only-body-caps-coverage` |
| 3 | `0x4318b5fc803b855f` | 459.96 MB | 38 | 58.07 MB | 9.05 MB (15.6%) | 49.01 MB (84.4%) | 159 | `put-heavy-get-only-body-caps-coverage` |
| 4 | `0x30540805202a855f` | 492.05 MB | 38 | 58.07 MB | 9.05 MB (15.6%) | 49.01 MB (84.4%) | 159 | `put-heavy-get-only-body-caps-coverage` |
| 5 | `0xb86b87ed0d1f8093` | 192.92 MB | 16 | 25.09 MB | 3.81 MB (15.2%) | 21.28 MB (84.8%) | 173 | `put-heavy-get-only-body-caps-coverage` |

## Source Anchors

| Area | Anchor |
| --- | --- |
| 25cc runtime family predicate | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:656` |
| shadow candidate gate | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1921` |
| shadow hash | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1952` |
| shadow begin | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1974` |
| 25cc shadow recorder | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1989` |
| 25cc body copy | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:2161` |
| MFC shadow begin hook | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:4423` |
| MFC shadow finish hook | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:4586` |
| GPU-probe pattern signature | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:2499` |
| LLVM verifier candidate | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp:4401` |
| dynamic MFC fallback signal | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp:5707` |

## Native Patch Contract

The next productive source/run step should use or extend the verify-only C++ descriptor instrumentation. Do not add another planning report before either proving these counters on a clean route or patching the active source if the binary lacks them.

Required behavior:

- Keep stock DMA execution active. Fast/body mode stays off.
- Preserve the current title/image/PC/tag/size/non-list/LS-range gates.
- Add a pattern or descriptor key to the 0x25cc shadow path: direction, raw/base command, tag, size, LSA, EAL, runtime family, and max-DMA pattern signature or equivalent descriptor hash.
- Record GET and PUT rows separately. A run that still emits PUT `0` is a verifier failure, not a speed result.
- For both directions, record source hash, destination-before hash, destination-after hash, destination changed/unchanged, and output match/mismatch after stock execution.
- If PUT semantics need reversed source/destination naming, make that explicit in the CSV columns rather than reusing GET labels ambiguously.
- Emit one aggregate CSV row per pattern/descriptor plus direction, with rejects and bytes, so the top rows above can be accepted or killed one by one.
- Keep command-level buckets `ea9e4000`, `exact_a1c000`, `ea4f0b80`, and `other` only as accounting buckets. They are not broad fast predicates.

Acceptance for the next run:

- Field route must remain visually clean.
- Pattern/descriptor shadow output must include nonzero PUT rows for the targets above or explain a concrete reject reason.
- GET and PUT output mismatch counts must be zero before any fast/body path is considered.
- Menu/Options and first-battle visual proof are still required before this can become stackable speed work.

## Parked Paths

- Broad SPU-to-Vulkan compute remains parked. The latest evidence still has `0 B` RSX-local or indirect RSX-resource overlap, so this is CPU/SPU verifier work, not GPU migration.
- Exact-EA skip/body paths remain parked. The evidence says the broad family is pattern/descriptor shaped, not a single command-level EA.
- More route movement reruns are parked until this verifier emits direction-split shadow data.
