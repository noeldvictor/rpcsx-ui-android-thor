# ARM64 SPU SHUFB single-source fast paths

Date: 2026-07-17

Status: ARM64 build-proven; Thor runtime performance and correctness remain unproven.

## Upstream audit

Candidate upstream commits:

- d85f1c7 RSX hardware spin_wait: already represented by the local
  rx::spin_wait implementation and Vulkan flush-request users.
- e7165cb one-shot semaphore cacheline wait: already represented by local
  rx::spin_on_cacheline_once, RSX interrupt handling, and semaphore callback.
- 09d602f SPU LLVM SHUFB refactor: not directly applicable because this tree
  deliberately retained only the ARM64 single-table subset.
- a7fc31f additional SHUFB splat/special-index paths: useful on ARM64, but
  its full two-source path depends on the larger upstream TBL2/TBX2 register-
  scavenger retry work that this tree does not carry.
- 700ca26 SELB refactor: mostly structural cleanup; no narrow Thor runtime
  win was isolated in this pass.

## Selected adaptation

SPULLVMRecompiler.cpp now uses LLVM known-mask bits to recognize when a
dynamic SHUFB can only select one source vector. This includes masks with a
known source-select bit even when ra and rb differ.

The ARM64 path emits only the upstream one-table forms:

- direct vector select for splat-or-zero masks;
- one TBL for ordinary single-source permutations;
- one TBX plus a small special-value table for masks that can request zero,
  0xff, or 0x80;
- a compact splat table path for constant source bytes.

Two-source TBL2/TBX2 lowering remains excluded. Those masks continue through
the established fallback, preserving the local JIT stability boundary.

## Host-only verification

- Exhaustive byte-level model: all 256 possible control bytes match the
  reference SHUFB result for the single-source, splat, and splat-or-zero
  formulas.
- git diff --check: clean.
- Android ARM64 RelWithDebInfo native build: passed.
- Build artifact:
  - path: app/build/intermediates/cxx/RelWithDebInfo/724a6w64/obj/arm64-v8a/librpcsx-android.so
  - size: 1,351,027,888 bytes
  - SHA-256: 6E00D877AF52FA3E7FA0CBF583B3E0A45ACDF7B8F37E574DCE10654B4DF93E09
  - modified UTC: 2026-07-17T05:06:49.2669734Z

No APK install, ADB query, launch, or Thor workload was performed. A measured
speed claim still requires cool-device field, first-battle, and menu evidence
under the bounded thermal harness.
