# Thor SPU Local-Store Mirror Coverage

- Date: 2026-07-18
- Subsystem: SPU LLVM / local-store virtual memory
- Upstream source: RPCS3 `8cc37e036d6bfd85a3afcf1794490246ec61ac25`
- Decision: `stability-alignment`
- Device state: host-only; no ADB, install, launch, or temperature read

## Problem

The vendored core already contained the current RPCS3 canonical address path
for aligned LQX/STQX and LQD/STQD expressions, but `spu_thread` still reserved
five local-store-sized regions and mapped only the center plus one alias on
each side.

LQD/STQD can add all three of:

- a canonical aligned constant in `[-0x40000, 0x3fff0]`;
- a masked local-store base in `[0, 0x3fff0]`;
- a signed ten-bit quadword displacement in `[-0x2000, 0x1ff0]`.

Including the final byte of the 16-byte vector access, the specialized address
range is `[-270336, 532447]`. The old three-copy mapping covered only
`[-262144, 524287]`, leaving an 8 KiB underflow and an 8,160-byte overflow.
The compiler optimization was therefore not fully backed by the runtime
mapping contract.

## Change

- Reserve seven local-store-sized virtual regions and center LS at region 3.
- Map five aliases at offsets `-2, -1, 0, +1, +2`.
- Unmap all five aliases and release the matching seven-region reservation.
- Fail closed when a critical mapping fails, lands at a different address, or
  reports an unexpected error.
- Return an empty error string on a successful `shm::map_critical` operation.

The extra 512 KiB per SPU is reserved virtual address space. All five mappings
alias the same 256 KiB shared local-store object; this does not create five
independent LS data copies.

## Verification

- `tools/test_thor_spu_ls_mirror_coverage.ps1`
  - proves the old range is insufficient at both ends;
  - proves five aliases cover every byte in the specialized range;
  - checks reserve/map/unmap/release symmetry and fail-closed mapping results.
- Existing LQX/STQX and LQD/STQD canonicalization contracts pass.
- All 32 `tools/test_thor*.ps1` host contracts pass.
- Optimized ARM64 RelWithDebInfo native build passes.
- Optimized `thortest` APK build passes.
- ARM64-only package identity, optimized-variant, and export-surface contracts
  pass.

## Exact Host Artifacts

- APK:
  - bytes: `73,696,614`
  - SHA-256: `B87299DF156455409D4DEE0E174CCED451C16278A1D468CC2BBB358E0172BF03`
- Merged ARM64 core:
  - bytes: `1,306,304,160`
  - SHA-256: `1BB8ED2D812ED6AD9A0B97C9DDFEBBAD82441DB815E352C1E7BA0FE4CFB49BEC`
- Stripped/packaged ARM64 core:
  - bytes: `63,137,832`
  - SHA-256: `6A02E15AAC2BED21F7E4964DCAF122B9D92481676A52DDAC0C866723483BB4EA`
- Export surface: 34 defined exports, 590 explicit relocations, 392 jump
  slots, and 44,285 encoded relocation bytes.

## Classification

This closes a concrete out-of-range stability hole underneath a previously
ported compiler optimization. It receives no FPS, temperature, flicker, or
gameplay credit until a later independently cool device proof.
