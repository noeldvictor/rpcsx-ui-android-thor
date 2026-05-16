# Ghidra And PS3 Static Tooling Delta - 2026-05-16

## Verdict

Ghidra should be a first-class lane for the Eternal Sonata speed sprint, but it
must stay anchored to runtime evidence. The clean workflow is:

1. Thor/Windows profiler names a hot guest PC, block, module, image hash, or
   RSX callsite.
2. Ghidra explains the local PPU/SPU code shape.
3. We patch emulator-side behavior behind a gate.
4. Field, battle, and menu prove correctness.

No sketchy side quests: no random decryption loaders, no exploit tooling, no
patched game binaries, no redistribution. Use emulator-produced diagnostic
dumps from the user's local owned run and keep all dumps/projects ignored.

## Tool Search Results

### Ps3GhidraScripts

- Source: https://github.com/clienthax/Ps3GhidraScripts
- Latest checked release: `1.0106`, published 2026-05-14.
- The release list includes a `ghidra_12.0.4_PUBLIC_20260514_Ps3GhidraScripts.zip`
  asset that matches the local Ghidra 12.0.4 install.
- Use for PPU PRX/ELF imports/exports/NID/syscall naming.
- The README recommends big-endian `PowerISA-Altivec-64-32addr`, running
  `AnalyzePs3Binary.java` before auto-analysis, then `DefinePs3Syscalls.java`.
- Known limits from the README: relocations are not currently supported, and
  some Cell-specific vector instructions may break decompilation.

### GhidraSPU

- Source: https://github.com/aerosoul94/GhidraSPU
- Purpose: SPU processor implementation for Ghidra.
- Status: work in progress and much smaller/staler than Ps3GhidraScripts, but
  still the cleanest candidate for importing SPU local-store captures into
  Ghidra.
- Use only as a compare/inspection tool. Confirm any SPU finding against RPCS3
  disassembly/runtime logs before changing emulator behavior.

### Ghidra Built-In PowerPC

The local Ghidra 12.0.4 install already exposes:

- `PowerPC:BE:64:64-32addr` - PowerPC 64-bit big endian with Altivec and
  32-bit addressing.

That is the PPU analysis baseline and lines up with the Ps3GhidraScripts
language guidance.

### Existing Repo Hooks

- `tools/run_thor_ghidra_prx_probe.ps1` already pulls a Thor PRX dump and runs
  Ghidra headless over selected addresses.
- `tools/ghidra_scripts/DecompileAddresses.java` dumps nearby instructions,
  references, and decompiled C for supplied addresses.
- `tools/thor_ooda.ps1` already has a profile-driven Ghidra auto-probe path.
- `dump_executable(...)` in `System.cpp` writes loaded/decrypted PPU modules
  when the emulator has the module data.
- `spu_thread::capture_memory_as_elf(...)` can package SPU local store as an
  ELF-like capture for focused SPU inspection.

## Current Eternal Sonata Application

The newest wait-site profiler run changed the Ghidra target. The hot path is
not a generic Vulkan mystery:

- total profiled waits: `11,250,000`;
- `spu_getllar_retry`: `8,442,390` calls;
- `spu_getllar`: `1,556,660` calls;
- `vm_passive`: `1,197,687` calls;
- RSX FIFO/semaphore waits were not the dominant wait family in this field run.

So the next static-analysis target is the SPU reservation loop behind
`GETLLAR`/retry. Ghidra should be fed a hot SPU PC/image/block, not the whole
game.

## Next Implementation Slice

1. Add a gated `GETLLAR` retry profiler that records top SPU image hash, PC,
   block hash, reservation address, retry count, and group/thread name.
2. Capture/disassemble the top SPU local-store window.
3. Try GhidraSPU on that ignored SPU ELF capture; compare output against RPCS3
   disassembly.
4. Use Ps3GhidraScripts for PPU-side SPURS/syscall wrapper addresses when the
   runtime probe points to a PPU module/callsite.
5. Convert the finding into one of these emulator-side patches:
   - reduced-loop/codegen improvement;
   - GETLLAR/PUTLLC wake/backoff specialization;
   - MFC/list-copy superpath;
   - PPU syscall/SPURS callsite fast path.

## Acceptance

A Ghidra/static result counts only if it names:

- runtime run/capture source;
- module/image/hash plus address or PC;
- exact suspected emulator bottleneck;
- proposed gate/rollback property;
- field, battle, and menu correctness checks.
