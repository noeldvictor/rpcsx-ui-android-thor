# Eternal Sonata 0x25cc Pattern Family

- Generated: 2026-05-26T15:16:25.7451467-04:00
- Run root: C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab
- Recent run dirs scanned: 16
- Valid field runs used: 6
- Field-like runs excluded by fatal logs: 1
- Scope: title `BLUS30161`, image `0x958dfe208b686622`, `CellSpursKernelGroup` / `CellSpursKernel0`, PC `0x25cc`.
- Classification: `analysis`, `spu-hle-25cc-pattern-family`, not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## Reading

- Total selected `0x25cc` traffic: 6.86 GB over 2 EA bucket(s), with 0 B RSX-local bytes.
- Top EA bucket: `0x9e4000`, 6.86 GB over 4340 records, 159 pattern(s), 34,782.089 ms.
- RSX-local traffic is still `0 B`; this is CPU/SPU HLE/codegen target sizing, not GPU migration.
- The broad target is the repeated `0x9e4000` EA family, not the earlier exact `eal=0xa1c000` redundant-copy skip.

## Valid Runs

- 20260526-144112-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows: first field screenshot-0117s.png at 117s
- 20260526-142353-cpu4-loader-control-left200x2-visualgate-windows-windows: first field screenshot-0117s.png at 117s
- 20260526-140709-cpu4-loader-control-left200-visualgate-windows-windows: first field screenshot-0117s.png at 117s
- 20260526-132810-cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows-windows: first field screenshot-0195s-post-load-complete-dismiss-18s.png at 195s
- 20260526-072403-cpu4-titleload-down160-lateloadcomplete-dismiss-directleft200-visualgate-windows-windows: first field screenshot-0199s-post-load-complete-dismiss-18s.png at 199s
- 20260526-031038-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows: first field screenshot-0136s-accepted-field-check.png at 136s

## EA Buckets

| Rank | EA | Runs | Records | Patterns | Total | GET | PUT | Duration ms | RSX | Max Job |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `0x9e4000` | 6 | 4340 | 159 | 6.86 GB | 1.01 GB | 5.84 GB | 34,782.089 | 0 B | 6.16 MB |
| 2 | `0x4f0b80` | 6 | 6 | 3 | 2.95 MB | 573.16 KB | 2.39 MB | 37.359 | 0 B | 788.61 KB |

## Top Clusters

| Rank | Hint | EA | Pattern | Runs | Records | Total | Share | Duration ms | Max DMA | Cmds | Fit | Risk |
| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 1 | broaden-25cc-verify-ea-family | `0x9e4000` | `0xf7bf30bddad5855f` | 6 | 334 | 510.38 MB | 7.27% | 2,943.292 | 16384 | 159 | spu-kernel-hle | tiny-dispatch-trap |
| 2 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x30540805202a855f` | 6 | 322 | 492.05 MB | 7.00% | 3,163.505 | 16384 | 159 | spu-kernel-hle | tiny-dispatch-trap |
| 3 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x209c1716c9de855f` | 6 | 316 | 482.88 MB | 6.87% | 2,601.205 | 16384 | 159 | spu-kernel-hle | tiny-dispatch-trap |
| 4 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x4318b5fc803b855f` | 6 | 301 | 459.96 MB | 6.55% | 2,968.541 | 16384 | 159 | spu-kernel-hle | tiny-dispatch-trap |
| 5 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x9c4d64ff0a1c9823` | 4 | 162 | 273.43 MB | 3.89% | 1,080.789 | 16384 | 317 | spu-kernel-hle | tiny-dispatch-trap |
| 6 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x95cedb5ff3de9823` | 4 | 145 | 244.73 MB | 3.48% | 952.649 | 16384 | 317 | spu-kernel-hle | tiny-dispatch-trap |
| 7 | broaden-25cc-verify-ea-family | `0x9e4000` | `0xc4e7ec394d77f62b` | 4 | 144 | 242.36 MB | 3.45% | 894.726 | 16384 | 316 | spu-kernel-hle | tiny-dispatch-trap |
| 8 | broaden-25cc-verify-ea-family | `0x9e4000` | `0xf68d32bc2886f62b` | 4 | 130 | 218.80 MB | 3.11% | 931.718 | 16384 | 316 | spu-kernel-hle | tiny-dispatch-trap |
| 9 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x4761323927fcb13` | 4 | 131 | 213.62 MB | 3.04% | 893.409 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 10 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x2c5fadfec0f0cb13` | 4 | 128 | 208.73 MB | 2.97% | 778.162 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 11 | broaden-25cc-verify-ea-family | `0x9e4000` | `0xb86b87ed0d1f8093` | 6 | 123 | 192.92 MB | 2.75% | 1,262.466 | 16384 | 173 | spu-kernel-hle | tiny-dispatch-trap |
| 12 | broaden-25cc-verify-ea-family | `0x9e4000` | `0xc27c7fd824c8354b` | 4 | 115 | 188.08 MB | 2.68% | 722.540 | 16384 | 306 | spu-kernel-hle | tiny-dispatch-trap |
| 13 | broaden-25cc-verify-ea-family | `0x9e4000` | `0xff1468682a558093` | 6 | 110 | 172.53 MB | 2.46% | 1,277.959 | 16384 | 173 | spu-kernel-hle | tiny-dispatch-trap |
| 14 | profile-only | `0x9e4000` | `0x637bd86e83c7d933` | 1 | 102 | 171.14 MB | 2.44% | 696.651 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 15 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x8bf74edab149354b` | 4 | 101 | 165.18 MB | 2.35% | 630.689 | 16384 | 306 | spu-kernel-hle | tiny-dispatch-trap |
| 16 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x4b67e9a0b6538093` | 6 | 104 | 163.12 MB | 2.32% | 910.927 | 16384 | 173 | spu-kernel-hle | tiny-dispatch-trap |
| 17 | profile-only | `0x9e4000` | `0x1ab8ac861b5cd933` | 1 | 92 | 154.36 MB | 2.20% | 679.193 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 18 | broaden-25cc-verify-ea-family | `0x9e4000` | `0x3f80928e6a918093` | 6 | 94 | 147.43 MB | 2.10% | 919.235 | 16384 | 173 | spu-kernel-hle | tiny-dispatch-trap |
| 19 | profile-only | `0x9e4000` | `0x6fe22f6f1b14d933` | 1 | 85 | 142.62 MB | 2.03% | 516.553 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 20 | profile-only | `0x9e4000` | `0x2baa1e01e61d933` | 1 | 84 | 140.94 MB | 2.01% | 484.997 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 21 | profile-only | `0x9e4000` | `0xf78730e1345b55b` | 1 | 86 | 139.79 MB | 1.99% | 615.826 | 16384 | 294 | spu-kernel-hle | tiny-dispatch-trap |
| 22 | profile-only | `0x9e4000` | `0xb50bded0b53355b` | 1 | 84 | 136.54 MB | 1.94% | 518.760 | 16384 | 294 | spu-kernel-hle | tiny-dispatch-trap |
| 23 | profile-only | `0x9e4000` | `0x518af699993af103` | 1 | 81 | 135.91 MB | 1.93% | 537.552 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 24 | profile-only | `0x9e4000` | `0x6d6ae03541acb55b` | 1 | 82 | 133.29 MB | 1.90% | 545.813 | 16384 | 294 | spu-kernel-hle | tiny-dispatch-trap |
| 25 | profile-only | `0x9e4000` | `0x16566aac139cf103` | 1 | 75 | 125.84 MB | 1.79% | 734.977 | 16384 | 305 | spu-kernel-hle | tiny-dispatch-trap |
| 26 | profile-only | `0x9e4000` | `0x92c046f871df355b` | 1 | 76 | 123.54 MB | 1.76% | 614.222 | 16384 | 294 | spu-kernel-hle | tiny-dispatch-trap |
| 27 | profile-only | `0x9e4000` | `0x699ebd5be035e6b` | 1 | 69 | 112.16 MB | 1.60% | 557.298 | 16384 | 294 | spu-kernel-hle | tiny-dispatch-trap |
| 28 | profile-only | `0x9e4000` | `0xcaffc417825e5e6b` | 1 | 67 | 108.91 MB | 1.55% | 593.775 | 16384 | 294 | spu-kernel-hle | tiny-dispatch-trap |
| 29 | profile-only | `0x9e4000` | `0x6cf9c3008f9b6c1b` | 1 | 30 | 50.49 MB | 0.72% | 232.551 | 16384 | 316 | spu-kernel-hle | tiny-dispatch-trap |
| 30 | profile-only | `0x9e4000` | `0x3137dda27695777b` | 1 | 30 | 49.06 MB | 0.70% | 144.791 | 16384 | 306 | spu-kernel-hle | tiny-dispatch-trap |

## Verifier Contract

- Keep fast mode off. Start with verify-only logging for the `0x9e4000` EA family under the existing `BLUS30161` / image / group / SPU / PC gate.
- Record command descriptors, source/destination hashes, touched GET/PUT byte ranges, and whether the stock path changes destination data before considering any HLE/codegen specialization.
- Do not route this to Vulkan compute unless a future capture shows RSX-consumed data; current evidence is CPU/SPU codegen/HLE only.

## Classification

- `analysis`, `spu-hle-25cc-pattern-family`, not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.
