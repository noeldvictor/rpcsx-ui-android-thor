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

**The trigger is built and verified on the device.**

    adb shell setprop debug.rpcsx.thor.spu_ls_dump CellSpursKernel0
    # boot the title, let it run, then:
    adb exec-out shell cat \
      /storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/spu_ls_CellSpursKernel0.bin \
      > debug-captures/spu_ls_CellSpursKernel0.bin

It writes 262144 bytes, which is the whole local store, and it reports the file
and the program counter through `spu_log`. It runs from `perf_monitor`, so no
SPU path pays for it. The default is off.

**A flat scan cannot tell code from data.** A first scan of the Transformers
image found 146 halt-shaped words. Four of them are constants: `0x7f454c46` is
the `\\x7fELF` magic, `0x7fefffff` is the high word of a double, and
`0x4fc903ca` is a float. A real guest assert compares against 0 or -1, so filter
on the operand and mark the rest as suspect.

The decoder index is `inst >> 21`, from `Emu/Cell/SPUOpcodes.h`:

| kind | index | kind | `inst >> 24` |
| --- | --- | --- | --- |
| `HGT` | `0x258` | `HGTI` | `0x4f` |
| `HLGT` | `0x2d8` | `HLGTI` | `0x5f` |
| `HEQ` | `0x3d8` | `HEQI` | `0x7f` |

Keep the image and the map in `debug-captures/`, which is not tracked.

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

## When Ghidra is worth it, and when it is not

**Tested 2026-08-23 on the dumped SPURS kernel, both halves.**

### You do NOT need Ghidra to DECODE SPU code

`Emu/Cell/SPUOpcodes.h` holds the emulator's own decode table, `{class, value,
GET(NAME)}`, and it parses in a few lines:

    ent = re.findall(r'\{\s*(\d+)\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*GET\((\w+)\)', src)
    # index is `inst >> 21`; an entry of magnitude m covers value<<m .. |m ones

**199 opcodes, zero setup, and it CANNOT disagree with the recompiler**, because
it is the same table the recompiler decodes with. That is a stronger guarantee
than any external disassembler gives.

### You DO need it for STRUCTURE, and a linear scan cannot fake it

A scan of the SPURS image found 141 halt sites asserting against 0 or -1, and
classifying what produced each checked value gave `XSWD` 69, `SFI` 43, `AND` 6,
`LQD` 4. **That classification is not trustworthy**, because a linear scan
cannot tell code from data, and one "halt site" in the same image is the
`\x7fELF` magic in a data region.

The obvious statistical fix does not work. Measuring how much of each 4 KB page
decodes as valid SPU instructions gives **99 to 100% on every page**, because
the SPU opcode space is dense and almost any word decodes to something. The test
cannot separate code from data at all.

So the things only Ghidra gives you here are:

* what is actually code, by following control flow from entry points;
* where a function starts and ends;
* who calls whom, so "is this halt even reachable from job dispatch?" is
  answerable;
* a backward slice from one instruction to the value it consumed.

### The trigger

**Use Ghidra when you have a runtime ANCHOR, and not before.** With a program
counter from the trap decoder, the job is bounded and decisive: follow control
flow back from that one address to the invariant that failed, in about an hour.

Without an anchor it is 141 candidate sites in somebody else's SPURS kernel with
no way to rank them. That is the unbounded exploration this lane exists to
refuse.

**For PPU and PRX work the balance is different**: PowerPC has real symbols,
`Ps3GhidraScripts` resolves NIDs, and the decompiler output is worth reading. On
SPU the decode is free and only the structure is scarce.
