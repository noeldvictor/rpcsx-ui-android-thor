# Eternal Sonata 0x25cc Pattern Hash Targets

- Generated: 2026-05-26 15:58:22 -04:00
- Classification: `analysis`, `spu-hle-25cc-pattern-hash-targets`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% moving-gameplay gate candidate.

## Inputs

- Atlas CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-experiments\20260526-25cc-pattern-family.csv`
- Latest shadow run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows`
- Runtime pattern CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows\eternal-sonata-25cc-runtime-family-patterns.csv`
- Shadow CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows\eternal-sonata-spu-hle-25cc-shadow-profile.csv`
- Target CSV: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-experiments\20260526-25cc-pattern-hash-targets.csv`

## Summary

- Atlas `0x9e4000` HLE candidates: 159 groups, 6.86 GB.
- Latest shadow-run runtime candidates: 16 groups, 1.03 GB.
- Top-16 atlas groups seen in latest shadow run: 4 groups, 1.56 GB atlas bytes, 188.60 MB latest-run bytes.
- Shadow verifier: 12108 hits, 189.19 MB, GET/PUT 12108/0, changed/unchanged 810/11298, match/mismatch 12108/0.
- Exact EA buckets remain too narrow: ea9e4000=807, exact_a1c000=807, other_matching_ea=10493.

## Top Hash Targets

| Rank | Pattern | Runtime | Atlas Records | Atlas Bytes | Atlas Share | Runtime Records | Runtime Bytes | GET Share | PUT Share | Max Cmds | Body Gap |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | `0xf7bf30bddad5855f` | no | 334 | 510.38 MB | 7.27% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 2 | `0x30540805202a855f` | yes | 322 | 492.05 MB | 7.00% | 33 | 50.43 MB | 15.6% | 84.4% | 159 | `put-heavy-get-only-body-caps-coverage` |
| 3 | `0x209c1716c9de855f` | yes | 316 | 482.88 MB | 6.87% | 39 | 59.60 MB | 15.6% | 84.4% | 159 | `put-heavy-get-only-body-caps-coverage` |
| 4 | `0x4318b5fc803b855f` | yes | 301 | 459.96 MB | 6.55% | 35 | 53.48 MB | 15.6% | 84.4% | 159 | `put-heavy-get-only-body-caps-coverage` |
| 5 | `0x9c4d64ff0a1c9823` | no | 162 | 273.43 MB | 3.89% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 6 | `0x95cedb5ff3de9823` | no | 145 | 244.73 MB | 3.48% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 7 | `0xc4e7ec394d77f62b` | no | 144 | 242.36 MB | 3.45% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 8 | `0xf68d32bc2886f62b` | no | 130 | 218.80 MB | 3.11% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 9 | `0x4761323927fcb13` | no | 131 | 213.62 MB | 3.04% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 10 | `0x2c5fadfec0f0cb13` | no | 128 | 208.73 MB | 2.97% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 11 | `0xb86b87ed0d1f8093` | no | 123 | 192.92 MB | 2.75% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 12 | `0xc27c7fd824c8354b` | no | 115 | 188.08 MB | 2.68% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 13 | `0xff1468682a558093` | no | 110 | 172.53 MB | 2.46% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 14 | `0x637bd86e83c7d933` | no | 102 | 171.14 MB | 2.44% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 15 | `0x8bf74edab149354b` | no | 101 | 165.18 MB | 2.35% | 0 | 0 B | 0.0% | 0.0% | 0 | `not-seen-in-latest-shadow-run` |
| 16 | `0x4b67e9a0b6538093` | yes | 104 | 163.12 MB | 2.32% | 16 | 25.09 MB | 15.2% | 84.8% | 173 | `put-heavy-get-only-body-caps-coverage` |

## Reading

- Several high-ranked repeated groups are visible in both the multi-run atlas and latest shadow run, enough to make the next step a verifier/instrumentation change rather than another route scout.
- The matched latest-run rows are strongly PUT-heavy. The current `0x25cc` body copy fast path only accepts GET, so a GET-only body cannot cover the main bytes in these groups.
- Pattern signature should remain a scout key, not the only fast predicate. The safe verifier key needs title `BLUS30161`, image `0x958dfe208b686622`, PC `0x25cc`, tag `31`, size `0x4000`, MFC direction, LSA, EAL, source hash, destination-before hash, destination-after hash, and output-match status.
- Broad SPU-to-Vulkan compute remains parked because these rows still report zero RSX-local bytes and tiny one-job dispatch risk.

## Next Implementation Slice

- Extend the runtime `0x25cc` shadow verifier to aggregate rows by pattern/descriptor plus direction, not just exact command-level EA buckets.
- Emit GET and PUT hash summaries separately for the top target groups, including changed/unchanged and output-match/mismatch.
- Keep fast/body mode off until the pattern-level verifier is clean in field, menu/Options, and first battle.
