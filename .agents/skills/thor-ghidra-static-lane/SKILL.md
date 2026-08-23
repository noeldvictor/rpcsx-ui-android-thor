---
name: thor-ghidra-static-lane
description: Use for repo-local Ghidra/static-analysis work on ANY PS3 title for RPCSX/RPCS3 Thor, including PPU PRX/ELF decompilation, SPU local-store dumps, Ps3GhidraScripts, GhidraSPU trials, runtime-to-static hot-address mapping, and legal offline no-sketchy optimization workflows. Use it BEFORE a fault too: to build the SPURS halt map that names a guest assertion, and to fingerprint a title's engine, SDK and PRX imports so triage starts with knowledge instead of a boot.
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

## Work you can do BEFORE a fault

**Most of this lane starts from runtime evidence. Two jobs do not, and both
make a later diagnosis much faster.** Do them once for each title. Compose with
`thor-game-workup`, which owns the triage procedure.

### 1. The SPURS halt map

**This is the highest value item.** A guest that halts its own SPU stops at
`0xffdead00`. The handler prints the program counter. A program counter alone
does not name the assertion that failed.

The SPURS kernel comes from `libsre` in the firmware, and its image is the same
on every boot. So you can map the halt program counters BEFORE the fault:

1. Boot the title one time. The boot does not need to fail.
2. Capture the local store of the `CellSpursKernel0` thread.
3. Disassemble the image. Use `GhidraSPU`, or the emulator's own
   `Emu/Cell/SPUDisAsm.cpp`, which is already in this tree.
4. Record every `HGT`, `HLGT` and `HEQ` with its address and its condition.
5. Write the map to `debug-captures/spurs-halt-map-<titleId>.md`.

A trap then resolves in one lookup. Folklore stalls at SPU `pc=0x12b0` in
`CellSpursKernel0`, and Transformers halts in the same module, so one map can
serve more than one title.

**Say which part is built.** The disassembler and the Ghidra SPU lane exist. A
trigger that writes the local store to a file on demand does NOT exist yet.
Build that trigger before you promise the map.

### 2. The static title fingerprint

Read the disc image before you boot it. Each answer below changes the triage,
and none of them needs the device.

| Read this | It tells you |
| --- | --- |
| `PARAM.SFO` | the title id, the title name, and the firmware version the title needs |
| engine strings in the EBOOT | the engine. `UnrealEngine3` and `CookedPS3` mean UE3, which streams job binaries through SPURS |
| the imported PRX list | if the title uses SPURS at all. No `libsre` means our SPURS defects cannot reach it |
| the count of embedded SPU ELF images | how much SPU work to expect |
| the module size estimate | the PPU precompile time, and the risk of a Scudo abort |

**Engine tells you which failures are plausible.** A UE3 title streams
near-identical job binaries through the same local store addresses, so it
exercises the SPU block verification checksum and the SPURS job path hard.
Transformers is UE3, and its first load compiles PPU modules of 4,000 to 9,500
functions for 585 seconds.

**Do not turn a fingerprint into a prediction.** It says which failures are
possible. It does not say which one happened. The workup tool still decides.

## Workflow

1. Start from runtime evidence:
   - simpleperf symbol/sample;
   - `debug.rpcsx.thor.wait_profiler`;
   - DMA/GPU probe image hash and hot PC;
   - OODA crash/log address;
   - RenderDoc/RSX event identity.
2. For SPU hot windows, run the contract pipeline before manual exploration:

```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir <run-dir> -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000
```

3. Map the runtime evidence to a guest artifact:
   - PPU/PRX: module name plus address, then `tools/run_thor_ghidra_prx_probe.ps1`.
   - SPU: image hash plus PC/block hash/raddr, then SPU LS capture or RPCS3 SPU disassembly.
4. Analyze only the hot window first. Prefer decompiling or disassembling
   a few functions/loops over importing the entire title.
5. Convert the static finding into emulator-side work:
   - SPU reduced-loop/codegen candidate;
   - GETLLAR/PUTLLC/MFC wait specialization;
   - syscall/SPURS fast path;
   - title/signature-gated CPU or GPU superpath.
6. Validate on field, battle, and menu before claiming a speed win.

Static findings for SPU must tighten `spu-contracts\BLUS30161\*.json`; they
must not become one-off notes or skip verify-only emulator checks.

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
