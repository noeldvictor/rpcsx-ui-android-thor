# Eternal Sonata SPU HLE Candidate Atlas

- Generated: 2026-05-26T15:10:27.5127070-04:00
- Run root: C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab
- Recent run dirs scanned: 16
- Valid field runs used: 6
- Field-like runs excluded by fatal logs: 1

## Reading

- Top stable bucket: PC 0x25cc, CellSpursKernelGroup / CellSpursKernel0, 6.86 GB over 6 valid run(s), recommendation spu-hle-codegen-priority.
- No candidate in the valid field set has RSX-local bytes. Broad SPU-to-Vulkan compute remains parked; target SPU kernel HLE/codegen/verifier first.

## Valid Runs

- 20260526-144112-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows: first field screenshot-0117s.png at 117s
- 20260526-142353-cpu4-loader-control-left200x2-visualgate-windows-windows: first field screenshot-0117s.png at 117s
- 20260526-140709-cpu4-loader-control-left200-visualgate-windows-windows: first field screenshot-0117s.png at 117s
- 20260526-132810-cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows-windows: first field screenshot-0195s-post-load-complete-dismiss-18s.png at 195s
- 20260526-072403-cpu4-titleload-down160-lateloadcomplete-dismiss-directleft200-visualgate-windows-windows: first field screenshot-0199s-post-load-complete-dismiss-18s.png at 199s
- 20260526-031038-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows: first field screenshot-0136s-accepted-field-check.png at 136s

## Excluded Runs

- 20260526-032955-cpu4-titleload-down160-firstbattle-battleroute-windows-windows: fatal-log-hit, rpcs3.stderr.txt: RPCS3: PPU[0x100000c] Thread () [0x002aedd0]: VM: Access violation reading location 0x40 (unmapped memory)

## Candidate Buckets

| Rank | Recommendation | PC | Group | SPU | Fit | Dispatch | Runs | Records | Patterns | Total | GET | PUT | List GET | RSX | Max Job |
| ---: | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | spu-hle-codegen-priority | 0x25cc | CellSpursKernelGroup | CellSpursKernel0 | spu-kernel-hle | tiny-dispatch-trap | 6 | 4340 | 159 | 6.86 GB | 1.01 GB | 5.84 GB | 0 B | 0 B | 6.16 MB |
| 2 | spu-hle-codegen-priority | 0x451c | TCX_CellSpursKernelGroup | TCX_CellSpursKernel0 | spu-kernel-hle | tiny-dispatch-trap | 6 | 2397 | 2397 | 5.49 GB | 1,012.09 MB | 2.03 GB | 2.46 GB | 0 B | 27.59 MB |
| 3 | too-small-parked | 0x451c | TCX_CellSpursKernelGroup | TCX_CellSpursKernel0 | too-small | tiny-dispatch-trap | 6 | 2208 | 2208 | 1.35 GB | 265.38 MB | 498.90 MB | 615.58 MB | 0 B | 1,023.55 KB |
| 4 | too-small-parked | 0x451c | TCX_CellSpursKernelGroup | TCX_CellSpursKernel0 | too-small | needs-batching | 6 | 385 | 385 | 72.35 MB | 15.68 MB | 24.15 MB | 32.53 MB | 0 B | 436.86 KB |
| 5 | spu-hle-codegen-candidate | 0x451c | TCX_CellSpursKernelGroup | TCX_CellSpursKernel1 | spu-kernel-hle | tiny-dispatch-trap | 2 | 2 | 2 | 6.91 MB | 1.25 MB | 2.64 MB | 3.02 MB | 0 B | 3.62 MB |
| 6 | too-small-parked | 0x25cc | CellSpursKernelGroup | CellSpursKernel0 | too-small | needs-batching | 4 | 4 | 2 | 2.37 MB | 463.44 KB | 1.91 MB | 0 B | 0 B | 788.61 KB |
| 7 | too-small-parked | 0x451c | TCX_CellSpursKernelGroup | TCX_CellSpursKernel0 | too-small | low | 6 | 286 | 115 | 2.09 MB | 1,014.33 KB | 347.47 KB | 780.95 KB | 0 B | 105.23 KB |
| 8 | too-small-parked | 0x25cc | CellSpursKernelGroup | CellSpursKernel0 | too-small | low | 2 | 2 | 1 | 599.47 KB | 109.72 KB | 489.75 KB | 0 B | 0 B | 299.73 KB |

## Repeated Patterns

| Rank | PC | Pattern | Group | SPU | Runs | Records | Total | RSX | Fit |
| ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | 0x25cc | 0xf7bf30bddad5855f | CellSpursKernelGroup | CellSpursKernel0 | 6 | 334 | 510.38 MB | 0 B | spu-kernel-hle |
| 2 | 0x25cc | 0x30540805202a855f | CellSpursKernelGroup | CellSpursKernel0 | 6 | 322 | 492.05 MB | 0 B | spu-kernel-hle |
| 3 | 0x25cc | 0x209c1716c9de855f | CellSpursKernelGroup | CellSpursKernel0 | 6 | 316 | 482.88 MB | 0 B | spu-kernel-hle |
| 4 | 0x25cc | 0x4318b5fc803b855f | CellSpursKernelGroup | CellSpursKernel0 | 6 | 301 | 459.96 MB | 0 B | spu-kernel-hle |
| 5 | 0x25cc | 0xb86b87ed0d1f8093 | CellSpursKernelGroup | CellSpursKernel0 | 6 | 123 | 192.92 MB | 0 B | spu-kernel-hle |
| 6 | 0x25cc | 0xff1468682a558093 | CellSpursKernelGroup | CellSpursKernel0 | 6 | 110 | 172.53 MB | 0 B | spu-kernel-hle |
| 7 | 0x25cc | 0x4b67e9a0b6538093 | CellSpursKernelGroup | CellSpursKernel0 | 6 | 104 | 163.12 MB | 0 B | spu-kernel-hle |
| 8 | 0x25cc | 0x3f80928e6a918093 | CellSpursKernelGroup | CellSpursKernel0 | 6 | 94 | 147.43 MB | 0 B | spu-kernel-hle |
| 9 | 0x25cc | 0x3a7a67fa73e2dcff | CellSpursKernelGroup | CellSpursKernel0 | 6 | 12 | 18.83 MB | 0 B | spu-kernel-hle |
| 10 | 0x25cc | 0x2c757b5c95b1a4a7 | CellSpursKernelGroup | CellSpursKernel0 | 6 | 10 | 15.65 MB | 0 B | spu-kernel-hle |
| 11 | 0x25cc | 0x49dc569c9b18f0ff | CellSpursKernelGroup | CellSpursKernel0 | 6 | 6 | 9.19 MB | 0 B | spu-kernel-hle |
| 12 | 0x451c | 0x246fde8761757347 | TCX_CellSpursKernelGroup | TCX_CellSpursKernel0 | 6 | 152 | 38.00 KB | 0 B | too-small |
| 13 | 0x451c | 0xebb868e836c7df23 | TCX_CellSpursKernelGroup | TCX_CellSpursKernel0 | 6 | 14 | 7.00 KB | 0 B | too-small |
| 14 | 0x25cc | 0x792d71852e37dcff | CellSpursKernelGroup | CellSpursKernel0 | 5 | 18 | 28.25 MB | 0 B | spu-kernel-hle |
| 15 | 0x25cc | 0x26470bda5c81dcff | CellSpursKernelGroup | CellSpursKernel0 | 5 | 13 | 20.40 MB | 0 B | spu-kernel-hle |
| 16 | 0x25cc | 0x17e0ff971a75a4a7 | CellSpursKernelGroup | CellSpursKernel0 | 5 | 10 | 15.65 MB | 0 B | spu-kernel-hle |
| 17 | 0x451c | 0x49b05f1208af6465 | TCX_CellSpursKernelGroup | TCX_CellSpursKernel0 | 5 | 6 | 14.34 KB | 0 B | too-small |
| 18 | 0x25cc | 0x9c4d64ff0a1c9823 | CellSpursKernelGroup | CellSpursKernel0 | 4 | 162 | 273.43 MB | 0 B | spu-kernel-hle |
| 19 | 0x25cc | 0x95cedb5ff3de9823 | CellSpursKernelGroup | CellSpursKernel0 | 4 | 145 | 244.73 MB | 0 B | spu-kernel-hle |
| 20 | 0x25cc | 0xc4e7ec394d77f62b | CellSpursKernelGroup | CellSpursKernel0 | 4 | 144 | 242.36 MB | 0 B | spu-kernel-hle |
| 21 | 0x25cc | 0xf68d32bc2886f62b | CellSpursKernelGroup | CellSpursKernel0 | 4 | 130 | 218.80 MB | 0 B | spu-kernel-hle |
| 22 | 0x25cc | 0x4761323927fcb13 | CellSpursKernelGroup | CellSpursKernel0 | 4 | 131 | 213.62 MB | 0 B | spu-kernel-hle |
| 23 | 0x25cc | 0x2c5fadfec0f0cb13 | CellSpursKernelGroup | CellSpursKernel0 | 4 | 128 | 208.73 MB | 0 B | spu-kernel-hle |
| 24 | 0x25cc | 0xc27c7fd824c8354b | CellSpursKernelGroup | CellSpursKernel0 | 4 | 115 | 188.08 MB | 0 B | spu-kernel-hle |
| 25 | 0x25cc | 0x8bf74edab149354b | CellSpursKernelGroup | CellSpursKernel0 | 4 | 101 | 165.18 MB | 0 B | spu-kernel-hle |

## Next HLE Verifier Target

- Target: PC 0x25cc, CellSpursKernelGroup / CellSpursKernel0, image 0x958dfe208b686622.
- Shape: 6.86 GB total over 4340 record(s), GET 1.01 GB, PUT 5.84 GB, list GET 0 B, RSX 0 B, max job 6.16 MB.
- Stability: 6 valid run(s), 159 pattern signature(s), 1 max-DMA EA value(s).
- Latest valid disasm window: C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260526-144112-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\spu-images\BLUS30161-spu-image-958dfe208b686622-entry-00818-pc-025cc-group-CellSpursKernelGroup-spu-0-CellSpursKernel0.disasm.txt

| Rank | Pattern | Runs | Records | Total | RSX |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | 0xf7bf30bddad5855f | 6 | 334 | 510.38 MB | 0 B |
| 2 | 0x30540805202a855f | 6 | 322 | 492.05 MB | 0 B |
| 3 | 0x209c1716c9de855f | 6 | 316 | 482.88 MB | 0 B |
| 4 | 0x4318b5fc803b855f | 6 | 301 | 459.96 MB | 0 B |
| 5 | 0xb86b87ed0d1f8093 | 6 | 123 | 192.92 MB | 0 B |
| 6 | 0xff1468682a558093 | 6 | 110 | 172.53 MB | 0 B |

Disasm cue:

```text
	000025ac:	30 81 40 28	lqa        r40,0xa00
	000025b0:	1c 33 2a 55	ai         r85,r84,0xcc
	000025b4:	33 80 b1 a7	lqr        r39,0x2b40
	000025b8:	42 15 e8 03	ila        r3,0x2bd0
	000025bc:	33 80 c2 8a	lqr        r10,0x2bd0
	000025c0:	40 80 00 d6	il         r86,1
	000025c4:	12 00 61 89	hbrr       0x25e8,0x28d0
	000025c8:	40 80 01 53	il         r83,2
	000025cc:	3e e2 00 a5	cdd        r37,sp,8
	000025d0:	0f 01 d4 26	roti       r38,r40,7
	000025d4:	b4 89 93 27	shufb      r36,r38,r38,r39
	000025d8:	b2 02 92 25	shufb      r16,r36,r10,r37 #i64[1]
	000025dc:	23 80 be 90	stqr       r16,0x2bd0
	000025e0:	34 00 2a 8f	lqd        r15,0(r85)
	000025e4:	3b 95 47 84	rotqby     r4,r15,r85
	000025e8:	33 00 5d 00	brsl       lr,0x28d0
	000025ec:	34 00 2a 8d	lqd        r13,0(r85)
	000025f0:	3b 95 46 8c	rotqby     r12,r13,r85
	000025f4:	0b 63 2b 54	shl        r84,r86,r12
	000025f8:	21 a0 0b 54	wrch       MFC_WrTagMask,r84
	000025fc:	21 a0 0b d3	wrch       MFC_WrTagUpdate,r83 #ALL
	00002600:	01 a0 0c 02	rdch       r2,MFC_RdTagStat
	00002604:	34 02 c0 80	lqd        lr,0xb0(sp)
	00002608:	35 80 00 09	hbr        0x262c,lr
	0000260c:	1c 28 00 81	ai         sp,sp,0xa0
	00002610:	34 ff c0 d0	lqd        r80,-0x10(sp)
	00002614:	34 ff 80 d1	lqd        r81,-0x20(sp)
	00002618:	34 ff 40 d2	lqd        r82,-0x30(sp)
	0000261c:	34 ff 00 d3	lqd        r83,-0x40(sp)
```

Verifier contract:

- Gate first on title BLUS30161, image 0x958dfe208b686622, group CellSpursKernelGroup, SPU CellSpursKernel0, and PC 0x25cc.
- Start with verify mode only: record the MFC command descriptor and touched GET/PUT ranges, run the stock path, then compare the candidate result before any fast return.
- Do not use Vulkan compute for this bucket unless a later trace shows RSX-consumed data; this target is currently an SPU HLE/codegen/verifier target, not GPU migration credit.

## Classification

- analysis, not gpu-migration-credit, not windows-micro-win, not a 200% gate candidate.
- Use this atlas to choose a verify-gated SPU HLE/codegen target, then prove field/menu/battle visuals before fast mode.
