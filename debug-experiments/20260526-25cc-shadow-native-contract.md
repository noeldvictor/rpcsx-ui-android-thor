# Eternal Sonata 0x25cc Shadow Native Contract

- Generated: 2026-05-26 16:04:58 -04:00
- Classification: `analysis`, `spu-hle-25cc-shadow-native-contract`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% moving-gameplay gate candidate.

## Inputs

- Hash target CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-experiments\20260526-25cc-pattern-hash-targets.csv`
- Shadow run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows`
- Shadow profile CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows\eternal-sonata-spu-hle-25cc-shadow-profile.csv`
- Runtime pattern CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows\eternal-sonata-25cc-runtime-family-patterns.csv`
- Source root inspected: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`
- Contract CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-experiments\20260526-25cc-shadow-native-contract.csv`

## Contract Summary

- Latest clean shadow verifier output is GET-only: `12108` hits, `189.19 MB`, GET/PUT `12108/0`, changed/unchanged `810/11298`, match/mismatch `12108/0`.
- Runtime-seen target patterns are PUT-heavy: `4` groups, `188.60 MB` latest-run bytes, GET `29.31 MB` (`15.5%`), PUT `159.29 MB` (`84.5%`).
- Multi-run atlas coverage for those runtime-seen groups is `1.56 GB`.
- Therefore a GET-only body copy can only prove a minority of the runtime-seen hot byte mass. The next source change must make PUT-side shadow semantics visible before any bodyfast or skip promotion.

## Runtime-Seen PUT-Heavy Targets

| Rank | Pattern | Atlas Bytes | Runtime Records | Runtime Bytes | GET | PUT | Max Cmds | Body Gap |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | `0x209c1716c9de855f` | 482.88 MB | 39 | 59.60 MB | 9.29 MB (15.6%) | 50.30 MB (84.4%) | 159 | `put-heavy-get-only-body-caps-coverage` |
| 2 | `0x4318b5fc803b855f` | 459.96 MB | 35 | 53.48 MB | 8.34 MB (15.6%) | 45.14 MB (84.4%) | 159 | `put-heavy-get-only-body-caps-coverage` |
| 3 | `0x30540805202a855f` | 492.05 MB | 33 | 50.43 MB | 7.86 MB (15.6%) | 42.56 MB (84.4%) | 159 | `put-heavy-get-only-body-caps-coverage` |
| 4 | `0x4b67e9a0b6538093` | 163.12 MB | 16 | 25.09 MB | 3.81 MB (15.2%) | 21.28 MB (84.8%) | 173 | `put-heavy-get-only-body-caps-coverage` |

## Source Anchors

| Area | Anchor |
| --- | --- |
| 25cc runtime family predicate | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:656` |
| shadow candidate gate | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1921` |
| shadow hash | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1952` |
| shadow begin | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1974` |
| 25cc shadow recorder | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1989` |
| 25cc body copy | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:2100` |
| MFC shadow begin hook | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:4362` |
| MFC shadow finish hook | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:4996` |
| GPU-probe pattern signature | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:2438` |
| LLVM verifier candidate | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp:4401` |
| dynamic MFC fallback signal | `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp:5707` |

## Native Patch Contract

The next productive patch should be a verify-only C++ instrumentation change. Do not add another planning report before this source slice.

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
