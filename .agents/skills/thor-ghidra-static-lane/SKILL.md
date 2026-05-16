---
name: thor-ghidra-static-lane
description: Use for repo-local Ghidra/static-analysis work on Eternal Sonata BLUS30161 and RPCSX/RPCS3 Thor performance, including PPU PRX/ELF decompilation, SPU local-store dumps, Ps3GhidraScripts, GhidraSPU trials, runtime-to-static hot-address mapping, and legal offline no-sketchy optimization workflows.
---

# Thor Ghidra Static Lane

## Scope

Use this repo-only skill when static analysis should explain a measured Thor
or Windows hot path. Keep it tied to performance work: SPU reservation loops,
MFC/DMA jobs, SPURS/syscall churn, PPU callsites, or RSX setup logic.

Do not use this lane for broad game decompilation, bypass tooling, patched game
binaries, online cheating, exploit work, or redistribution. Use emulator-produced
diagnostic dumps from the user's own local run, and keep dumps/projects under
ignored `debug-captures/`.

## Workflow

1. Start from runtime evidence:
   - simpleperf symbol/sample;
   - `debug.rpcsx.thor.wait_profiler`;
   - DMA/GPU probe image hash and hot PC;
   - OODA crash/log address;
   - RenderDoc/RSX event identity.
2. Map the runtime evidence to a guest artifact:
   - PPU/PRX: module name plus address, then `tools/run_thor_ghidra_prx_probe.ps1`.
   - SPU: image hash plus PC/block hash/raddr, then SPU LS capture or RPCS3 SPU disassembly.
3. Analyze only the hot window first. Prefer decompiling or disassembling
   a few functions/loops over importing the entire title.
4. Convert the static finding into emulator-side work:
   - SPU reduced-loop/codegen candidate;
   - GETLLAR/PUTLLC/MFC wait specialization;
   - syscall/SPURS fast path;
   - title/signature-gated CPU or GPU superpath.
5. Validate on field, battle, and menu before claiming a speed win.

## Tooling

Read `references/tooling.md` before installing, updating, or changing Ghidra
tooling. Current clean tools are:

- local Ghidra 12.0.4 headless/GUI;
- Ghidra built-in PowerPC `PowerPC:BE:64:64-32addr` for PPU;
- `Ps3GhidraScripts` for PS3 PPU imports/exports/NIDs/syscalls;
- experimental `GhidraSPU` for SPU local-store ELF/dumps;
- repo scripts `tools/run_thor_ghidra_prx_probe.ps1` and
  `tools/ghidra_scripts/DecompileAddresses.java`.

## Acceptance

A Ghidra finding is useful only if it names the exact runtime anchor, guest
module/image, address/PC/block, suspected emulator bottleneck, proposed gated
change, and the correctness checks needed to prove it.
