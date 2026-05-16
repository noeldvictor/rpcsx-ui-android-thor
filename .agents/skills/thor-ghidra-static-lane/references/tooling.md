# Thor Ghidra Tooling

## Local Baseline

- Ghidra home: `C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\ghidra_12.0.4_PUBLIC`
- Headless runner: `support\analyzeHeadless.bat`
- Repo headless helper: `tools/run_thor_ghidra_prx_probe.ps1`
- Repo decompile script: `tools/ghidra_scripts/DecompileAddresses.java`

The local Ghidra install has a PowerPC big-endian 64-bit language with 32-bit
addressing: `PowerPC:BE:64:64-32addr`. That is the PPU lane. There is no
built-in SPU processor in the checked local Ghidra install, so SPU analysis
needs either RPCS3 disassembly output or an experimental SPU extension.

## Clean External Tools

### Ps3GhidraScripts

Source: https://github.com/clienthax/Ps3GhidraScripts

Use for PPU PRX/ELF analysis. The README says to load PS3 PRX/ELF files as
big-endian `PowerISA-Altivec-64-32addr`, run `AnalyzePs3Binary.java` before
auto-analysis, then run `DefinePs3Syscalls.java` after analysis. The project
also notes limitations: relocations are not currently supported, and some
Cell-specific vector load/store instructions may hurt decompilation.

Latest checked release during this sprint: `1.0106`, published 2026-05-14,
with a Ghidra 12.0.4 zip asset.

### GhidraSPU

Source: https://github.com/aerosoul94/GhidraSPU

Use as an experimental SPU processor lane for local-store ELF captures. Treat
it as WIP: test on ignored SPU dumps first, compare against RPCS3/SPU log
disassembly, and do not make correctness claims from decompiler output alone.

## Existing Repo Hooks

- `dump_executable(...)` in `app/src/main/cpp/rpcsx/rpcs3/Emu/System.cpp`
  writes decrypted executable data from the emulator's own loaded PPU modules
  when PPU debug is enabled.
- `tools/run_thor_ghidra_prx_probe.ps1` sets `debug.rpcsx.thor.dump_prx`,
  pulls a local module dump from Thor cache, and runs Ghidra headless over
  selected addresses.
- `spu_thread::capture_memory_as_elf(...)` in
  `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp` can package SPU local
  store as an ELF-like artifact. Use this for SPU hot loops once a runtime
  probe names the PC/block/image.

## Eternal Sonata First Target

The current Thor wait profiler says the field scene is dominated by SPU
reservation polling:

- `spu_getllar_retry`: about 8.44M calls in the sampled field run.
- `spu_getllar`: about 1.56M calls.
- `vm_passive`: secondary, about 1.20M calls.

Therefore the next Ghidra/static-analysis job is:

1. Add or use a low-overhead probe that logs top `GETLLAR` retry keys:
   SPU image hash, PC, block hash, reservation address, and thread/group name.
2. Capture/disassemble only the top hot SPU LS window.
3. Decide whether the loop is a known SPURS/reservation wait, a reduced-loop
   codegen candidate, an MFC/list-copy pattern, or a bad wakeup/backoff path.
4. Patch the emulator side behind a debug property or BLUS30161 signature gate.
