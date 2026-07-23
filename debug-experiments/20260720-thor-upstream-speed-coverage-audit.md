# Thor current-upstream speed coverage audit

- Date: 2026-07-20
- Target: AYN Thor Max / Snapdragon 8 Gen 2 / Adreno 740
- Title: Eternal Sonata `BLUS30161`
- Classification: `host-only-upstream-audit` / `not-comparable`
- Device routes: zero

## Decision

Do not stack another runtime change onto exact uninstalled APK
`E69ABCB05E2028C32197D4358E94F0EA8AF2E42366F75D8335AE40BB7A208073`
before its logging-liveness proof. The current official ARM64, SPU LLVM, PPU
LLVM, IdManager, and Vulkan descriptor-pool performance slices are already in
the Android fork, are inapplicable to Thor, or have a recorded correctness or
attribution counterproof.

This is a deliberate evidence freeze, not a speed claim. It avoids obscuring
the already promising `19.295 s` first-title and `48.2 C` peak result with an
untested extra variable.

The fail-closed `ThorCoolTitle` candidate manifest is now pinned to the exact
successor rather than the older installed APK. Until the separate install-only
round succeeds, a runtime proof therefore refuses the old installation before
thermal preflight or boot.

## Official source window

The official RPCS3 commit history was checked at:

- <https://github.com/RPCS3/rpcs3/commits/master/>; and
- local `rpcs3-upstream` `origin/master` `357b7d446`.

The local comparison worktree has only its seven pre-existing dirty dependency
submodules. None was read through, modified, staged, or reset.

## Candidate coverage

| Official change | Thor decision | Existing fork evidence |
| --- | --- | --- |
| `9b3a916af`, SPU FMA select dependency shortening | already adapted | `65102bf31`; ARM64 FMA and KnownFPClass contracts pass |
| `e9f833a2e`, PPU hardware-FTZ/NJ acceleration | already adapted and host-positive | `54a43ed8c`; matched Windows first-battle CPU fell `47.83% -> 37.60%` at unchanged ~120 FPS |
| `aec0917a8` / `d0fdd9bb6` / `fa418f0db`, SPU KnownFPClass | already adapted | `683577431`; clamp, multiply/equality, and FMA analysis contract passes |
| `2cacaa2da`, IdManager removal concurrency | already adapted | `ff19a12b5`; indexed removal/withdraw paths are present |
| `8e370c2cf` / `bf85a3fdd`, Vulkan descriptor-pool autoscaling/debounce | already adapted | `76f95af3b`; min/max scaling and two-step growth debounce are present |
| `4e49c5319` / `5d62ee4b4`, native thread identity/publication | already adapted | `7b94e397f`; cached kernel TID and atomic parent/child handle publication are present |
| `b35e4434a` / `21d533675`, reduced-loop state/ARM64 safety | already aligned | `bcac8b97a`; the unsafe custom Android reduced-loop emitter remains retired |
| `6349ea2ee`, SVE multiply lowering | inapplicable | Snapdragon 8 Gen 2 does not expose the required 128-bit SVE/SVE2 path; the runtime feature gate remains fail-closed |
| `50df95d6c` / `cdbc43712`, vector NaN/denormal shortcuts | AVX-512-only portion inapplicable | the ARM-relevant FTZ mechanism is the separately adapted `e9f833a2e` slice |
| `d755124c4`, SPU ASMJIT comparisons | inapplicable | Android uses SPU LLVM, not x86 ASMJIT |

No newer official Vulkan/ARM64 change in the inspected window supersedes these
paths. Correctness-only or unrelated commits are not counted as speed work.

## Dynamic hot-path counterproofs

The existing state-aware Windows profiles also reject a speculative new
superpath:

- the leading battle SPU block accounts for `28.4%` of active samples but
  crosses about `238` times per second and has only `1.304` samples per entry;
- leading guest PPU blocks are approximately one sample per observed entry;
- accounted RSX setup/upload/draw/flip work is about `2.1 ms` inside a
  `33.3 ms` frame; and
- long semaphore waits belong to paired background workers, while the
  `SpursHdlr0` join averages under `1 ms`.

Those shapes do not amortize native guest/host boundaries and do not identify
an RSX bottleneck. Reopening them without new evidence would add code and
verification cost without a credible performance-per-watt mechanism.

## Retained evidence-backed work

The next exact candidate keeps the changes that do have direct evidence:

- PPU hardware FTZ, with a matched `21.4%` Windows process-CPU reduction;
- the one-millisecond VBlank-assisted frame-poll wait, with a matched `14.2%`
  battle host-CPU reduction and clean field/battle/menu routes;
- continuous frame-poll rearm, which removed `99.98%` of fallback sleeps in
  the Windows first-battle route while preserving the 30 FPS cap;
- Thor 30 FPS surface pacing plus FIFO presentation for the title-scoped
  managed profile;
- bounded RSX/SPU startup work and efficiency-core compile affinity; and
- the Android log-liveness repair required to prove all of the above at
  runtime.

## Next safe proof sequence

1. In a later independently cool round, use only the strict no-launch installer
   for exact APK `E69ABCB0...8073`; prove host/device hash equality and absent
   PID, then stop.
2. In a different independently cool round, run one self-stopping
   `ThorCoolTitle` proof and require durable activation/fatal evidence.
3. Only after that proof, spend another cool round on the existing bounded
   field/first-battle comparison. Record FPS, frame pacing, visual correctness,
   time/temperature slope, and exact core identity.

Until those gates pass, retain `not-comparable`: no sustained FPS, flicker,
field, battle, menu, gameplay, stability, or controlled temperature-win credit.

## Host verification

- APK: `72,839,336` bytes,
  `E69ABCB05E2028C32197D4358E94F0EA8AF2E42366F75D8335AE40BB7A208073`;
- merged core: `1,304,689,776` bytes,
  `857B0A5A4E9F7BC5E8337A07137D446166022E6C9DBB695EC298FDFF9100877E`;
- stripped/package core: `63,015,752` bytes,
  `CC2FF22E6D190B97E58E1466E139FB4DAC711F988A91FFF2C01D13B1CB5EA3CA`;
- all `59/59` Thor host contracts passed before the manifest repin; and
- the focused cool-title profile contract and `git diff --check` are rerun
  after the repin.


## 2026-07-22 official-tip refresh

The official `master` tip is now `8604f1c5d83fbd256e3e29fdccee4ead805c2689`;
the read-only local comparison checkout remains at `ee37ef277`. Four July 21
LLVM commits after that checkout form one relevant sequence:

- `85c59207f`: look through bitcasts when extracting a constant `v128`;
- `2aeb08f92`: reject `computeKnownBits` results whose value graph reaches a
  PHI, because single-pass IR emission may not have added the back edge yet;
- `d75543a5b`: recover safe OR/AND constant known bits when the full analysis
  is rejected; and
- `8b05c8cc1`: correct the fallback's per-lane all/any bit combination.

The Android fork does not contain this sequence: `get_known_bits` still calls
`llvm::computeKnownBits` directly, and `get_const_vector<v128>` does not look
through bitcasts. The PHI safety fix is plausibly relevant to stability because
the historical Thor failure includes corrupted SPU-produced guest-memory draw
records consumed by the PPU parser, but no capture currently attributes that
failure to known-bit analysis. Treat that relationship as a hypothesis, not
proof or performance credit.

Do not port/build the series before the exact installed A7216402...3D15C cache
baseline and title proof finish. Rebuilding would overwrite the frozen host
artifact and obscure whether the named-worker/cache changes improved startup.
After that baseline, port the four commits as one ordered unit, run optimized
ARM64 and all Thor contracts, and make cache compatibility explicit before any
install. No Thor contact occurred during this refresh.

## 2026-07-22 translator/cache compatibility refinement

Current-source call-site inspection narrows the required cache handling:

- Every get_known_bits consumer is in SPULLVMRecompiler.cpp; none is in the
  PPU translator.
- get_const_vector<v128> is consumed by both PPU and SPU LLVM paths.
- The Thor title route keeps the optional persistent SPU native-object cache
  off, so its normal SPU program cache is recompiled through the current LLVM
  translator on each launch.
- PPU LLVM objects are persistent and their v7-kusa identity does not encode
  translator source version.

Therefore, a later port needs two explicit compatibility decisions. Preserve
the normal SPU program list, but bump both the thor-spu-native-v2 key and
spu-native-v2 directory if the optional native-object experiment is retained.
For PPU objects, add a BLUS30161-scoped compiler-identity bit or deliberately
bump the global PPU cache version before expecting the bitcast extraction
change to execute. Do not silently reuse old PPU objects and call the port
tested. This is host-only planning; it does not change the frozen APK, grant a
stability result, or justify invalidating the current baseline before its cache
and title proof are complete.

## 2026-07-22 live upstream follow-up

Status: research-only / parked until the frozen warm-cache baseline completes

Official RPCS3 master gained a four-commit CPUTranslator sequence after the
local comparison checkout's `ee37ef277` tip:

- `2aeb08f929a0299e5f31811b73a00326e5475f0a` rejects LLVM known-bit facts
  whose value ancestry reaches an incompletely emitted PHI node;
- `85c59207f7049aea83f765ed8bb419a01643ad69` looks through bitcasts when
  extracting constant `v128` values;
- `d75543a5b1f61cb00fb7e6e2852b519792131ddf` restores a narrow PHI-safe
  known-bits fallback for immediate OR/AND operations with constant operands;
- `8b05c8cc1f831913a84560b304a8d15a07f4662c` corrects the vector-lane
  aggregation used by that fallback.

Primary commits:

- https://github.com/RPCS3/rpcs3/commit/2aeb08f929a0299e5f31811b73a00326e5475f0a
- https://github.com/RPCS3/rpcs3/commit/85c59207f7049aea83f765ed8bb419a01643ad69
- https://github.com/RPCS3/rpcs3/commit/d75543a5b1f61cb00fb7e6e2852b519792131ddf
- https://github.com/RPCS3/rpcs3/commit/8b05c8cc1f831913a84560b304a8d15a07f4662c

This sequence is a credible JIT-correctness follow-up if Thor still flickers or
faults after the exact warm-cache field/menu/battle baseline. It is not yet a
measured Eternal Sonata hot path or speed win. Do not merge it into the frozen
candidate: CPUTranslator changes require an explicit PPU/SPU cache-identity
audit and a fresh verify-only Windows field/menu/battle proof before any later
Android build. No repository source, APK, core, cache, or device state changed
in this research step, and it earns no FPS, thermal, flicker, or stability
credit.
