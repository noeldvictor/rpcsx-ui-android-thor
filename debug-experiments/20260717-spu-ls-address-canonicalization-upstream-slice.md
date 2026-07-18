# SPU Local-Store Address Canonicalization Upstream Slice

Date: 2026-07-17
Title: Eternal Sonata, BLUS30161
Target: AYN Thor / Android ARM64
Classification: host-verified upstream performance candidate; device-unmeasured

## Upstream trigger

The official RPCS3 checkout contains:

- introducing commit: `9bf67f031288b3197ed07d2305da273a6ebe65bc`
- subject: `SPU LLVM: Discourage memory mirrors use on LQD/STQD`
- later specialization disable: `1d657c4e6330057d02f1470bb2b1036578c9807e`
- later non-aligned safety revert/current tip: `0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861`

The introducing patch canonicalized constant local-store offsets so LLVM would
not see multiple unrelated host addresses aliasing the same mirrored SPU local
storage. Its original scope also added STQD/LQD specialization and non-aligned
LQX/STQX reuse. Current official upstream no longer enables those parts:

- `1d657c4` disables the STQD/LQD specialization.
- `0fcb15a` removes non-16-byte-aligned LQX/STQX reuse.
- Current tip retains canonical negative offsets for aligned constant LQX/STQX.

This adaptation follows the current composition, not the broader introducing
patch.

## Adaptation

Changed:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`
- `tools/test_thor_spu_lqx_stqx_address_reuse.ps1`

`make_negative_LS_offset` preserves the low local-store address bits while
sign-extending an out-of-range constant into the negative mirror. Aligned
constant LQX/STQX specializations now add that canonical offset to the masked
dynamic operand. This gives LLVM one consistent address family for the same
mirrored local storage and can improve alias analysis/code generation.

The adaptation intentionally does not add the current-tip-disabled STQD/LQD
specialization. It also retains the current safety behavior:

1. Constant reuse is accepted only when `remainder == 0`.
2. Non-aligned operands use `(a + b) & 0x3fff0`.
3. The reverted remainder-adjustment fragments remain absent.

The updated contract requires the canonical helper and both canonical aligned
sites, rejects the old positive modulo form, retains both generic fallbacks,
and continues to reject non-aligned specialization.

## Title relevance

The clean saved first-battle SPU image capture at
`debug-captures/windows-lab/20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows/spu-images`
contains 146 covered instruction rows across 57 disassembly files:

- LQX: 94
- STQX: 52

Overlapping function/PC captures can repeat guest instructions. These counts
prove broad static presence in title-relevant SPU code but are not unique
instruction counts or dynamic execution frequency.

The rebuilt official current tip already completed the full BLUS30161 route in
`debug-captures/windows-lab/20260717-221500-upstream0fcb15a-ftz-on-warm-allcore-uncap240-first-battle-windows`.
It reached Path-to-Tenuto field and active first battle, survived the 150-second
bound, and had zero targeted fatal/access-violation/device-lost/assertion hits.
Its 12 battle FPS samples averaged 120.016. This is a correctness counterproof
for the current upstream composition, not a controlled speed comparison for
this slice.

## Cache and rollback

This changes generated SPU host code only. The normal SPU disk cache retains
guest program identities/data rather than persisted ARM machine code, so no
guest-program cache version bump is needed. JIT host code is rebuilt in memory.

Rollback is a local revert to positive modulo canonicalization. The generic
non-aligned fallback is always present and no title-specific switch was added.

## Host validation

Passed without contacting the Thor:

- updated LQX/STQX canonicalization and safety contract
- ARM64 decrementer, widening-multiply, KnownFPClass, and SPU cache contracts
- reduced-loop audit safety gates; Android emission remains disabled
- ARM64 RelWithDebInfo compile/link of `SPULLVMRecompiler.cpp`
- optimized ThorTest APK contract
- ARM64-only APK/core hash contract
- native export surface: 34 defined dynamic symbols, 583 explicit relocations, 391 jump slots, 44,219 encoded relocation bytes
- PowerShell AST parsing and `git diff --check`

## Exact host-only candidate

- APK: `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK SHA-256: `8BF896E8E2F99547523E53F803111DFE6BA330DA3C00644AE7B4C0BA790C28C7`
- APK size: `73,574,098` bytes
- merged ARM64 core SHA-256: `4DB962F71A258E2716E50AA3E8E28DC8A1201973D94765F6AF61B2BF57D78F83`
- merged ARM64 core size: `1,305,613,176` bytes
- stripped ARM64 core SHA-256: `1248939384924BD016A620DE0BFA3E999CF90A8DAB0928693EB2FBDD03B3D154`
- stripped ARM64 core size: `62,846,264` bytes

No ADB query, install, launch, or thermal poll ran in this host-only round. The
Thor remains stopped on installed APK `24F3F267...F87F`. Candidate
`8BF896E8...28C7` is uninstalled and has no device speed, temperature, flicker,
gameplay, or stability credit. A later install must first pass the strict
independently cool three-sample gate; runtime proof belongs to a different cool
round.
