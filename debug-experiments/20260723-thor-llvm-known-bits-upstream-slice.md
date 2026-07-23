# 2026-07-23 Thor LLVM KnownBits Upstream Slice

## Result

- Classification: host-verified upstream correctness and JIT-quality candidate.
- Fresh official RPCS3 tip audited: `7a90d09cfe3c31bf95c3cb63c6301c5c0824c531`.
- Exact new host-only ThorTest APK:
  `490418F9A43B287C376CB9D121C5C3BC93E1AFDEA51ED618BA6AB5882D95BF63`.
- It supersedes the uninstalled `87761DAD...083CC` candidate.
- No device query, install, launch, FPS, temperature, flicker, gameplay, or
  stability credit accompanies this host-only slice.

## Upstream Audit

The official mirror was fetched over Git SSH without checking out or changing
its pre-existing dirty submodules. Four new July 21 LLVM commits applied to the
vendored CPU translator:

- `85c59207f7049aea83f765ed8bb419a01643ad69`: expose bitcasted `v128`
  constants before constant extraction;
- `2aeb08f929a0299e5f31811b73a00326e5475f0a`: reject LLVM KnownBits analysis
  when a value may derive from an incomplete PHI graph;
- `d75543a5b1f61cb00fb7e6e2852b519792131ddf`: preserve safe scalar and vector
  constant-mask facts through a bounded fallback;
- `8b05c8cc1f831913a84560b304a8d15a07f4662c`: correct vector reduction so OR
  uses bits set in every lane and AND uses bits clear in every lane.

The other fresh upstream commits were CLI, Qt, BSD, or generic warning changes
and do not target Thor's measured startup/runtime paths.

## Code Contract

`is_known_bits_safe()` now walks at most 256 values, treats loads as leaves,
and fails closed on every PHI ancestor. Safe graphs still use LLVM's full
`computeKnownBits`; unsafe graphs retain only directly provable OR/AND facts.
This prevents one-pass, incomplete IR from selecting an unsound ARM64 fast
lowering without discarding common constant-mask optimizations.

Static source coverage contains 11 current consumers: two generic ARM64
infinite-shift paths and nine SPU LLVM lowering queries. This is coverage, not
dynamic execution or speed proof.

`tools/test_thor_llvm_known_bits_safety.ps1` locks the PHI fail-closed walk,
the corrected all-lanes/any-lanes masks, the scalar fallback, and bitcast-first
`v128` extraction. The old unguarded direct query is forbidden.

## Host Verification

Passed:

- focused LLVM KnownBits source contract;
- ARM64 `buildCMakeRelWithDebInfo`;
- optimized ThorTest build with explicit `arm64-v8a` packaging;
- ARM64-only APK and optimized test-hook gates;
- exact APK/core and embedded ZIP-entry identity gates;
- core export surface (`35` defined dynamic symbols, `587` explicit
  relocations, `390` `JUMP_SLOT`, `44,142` encoded relocation bytes);
- all `67/67` Thor host contracts before final documentation;
- `git diff --check`.

Exact host artifact:

- APK: `490418F9A43B287C376CB9D121C5C3BC93E1AFDEA51ED618BA6AB5882D95BF63`,
  `72,838,428` bytes;
- merged core:
  `9049E58356F013413230F339BBDCEADC09DD5B44A1835CA5A229824185AB749E`,
  `1,304,306,328` bytes;
- packaged core:
  `C0007C413932FC65C3CD01CDE70507987D335B0156A2A014508356A57CDED102`,
  `62,988,824` bytes;
- the APK's `lib/arm64-v8a/librpcsx-android.so` entry matches the packaged core
  exactly and no RPCSX x86_64 library remains in the accepted APK.

## Device Boundary

Thor remains stopped on installed APK `3DFB5F55...A34A78`. The rejected hot
install gate remains authoritative for that round. This new candidate must
first pass one future strict, independently cool, no-launch installation; only
a later separately cool self-stopping title proof may earn performance,
thermal, flicker, or stability credit.
