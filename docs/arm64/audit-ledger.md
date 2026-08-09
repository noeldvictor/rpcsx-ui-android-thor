# Codebase-vs-manuals audit: method, coverage, and what is left

The goal is a systematic check of the whole native codebase against the vendored
ARM64 manuals, aimed at making the emulator faster or cooler. This file is the
ledger, so the sweep can be resumed mechanically instead of restarted.

## The method that works, and the one that does not

**Does not work: sweeping the manual for slow instructions and hunting for them.**
Tried repeatedly this session. Four predictions derived that way, four refuted:

| prediction from the manual | measured | verdict |
| --- | --- | --- |
| `ISB` beats `YIELD` for spin | **+23% cycles** | regression, rejected |
| XOR/OR tree beats `MLA` in `cmp_rdata` | 0.3% | noise, no change |
| UMA direct upload avoids staging copies | 8.5 KB/frame | negligible, closed |
| shift-by-immediate beats shift-by-register | both `V13` | no difference, killed on paper |

The one that was killed on paper is the cheapest and the model to copy: read the
exact table row *before* building anything.

**Works: establish reach first, then optimality.** Every real defect this session
came from asking "does this code run at all, and with what?" rather than "is this
instruction ideal":

* `mov_rdata` — an ARM64 `#elif` containing only comments, so the copy every
  reservation validates against did nothing. Two titles could not boot.
* the RSX auditor — `enabled()` is `constexpr false` on Android without
  `RPCSX_THOR_RSX_AUDITOR`, so its property could never work.
* 1.88 W — a leaked emulator process at 210% CPU, found with `top`, not a manual.

## Coverage so far

| area | how checked | result |
| --- | --- | --- |
| Empty/neutralised arch branches | `tools/check_empty_arch_branches.py`, 1,489 files | 1 found (`mov_rdata`), fixed; now clean and guarded |
| NEON intrinsic inventory | all 1,489 non-3rdparty sources | 696 distinct; top of list is sse2neon |
| **sse2neon reach** | includers of `Emu/CPU/sse2neon.h` | **only 2**: `SPUInterpreter.cpp` (cold — both decoders are LLVM) and `ProgramStateCache.cpp` (already `vrev16q_u8`, AVX-512 behind `ARCH_X64`). Closed |
| Narrow-pipe ASIMD ops | every X3 table row narrower than `V` | see [`microarchitecture.md`](microarchitecture.md); shifts all `V13`, 8-bit `SDOT` full width |
| `cmp_rdata` lowering | X3 pipe tables + A/B on device | `MLA` is `V02`, but 0.3% — not worth churning |
| `pause()` / spin instruction | X3 + 3-arm A/B | `YIELD` ≈ `nop` confirmed; `ISB` +23%. Default kept |
| AES | X3 §4.6 | wants 4 blocks interleaved, we do 1 — real, but 35 ms of boot total |
| SDOT/UDOT | source + device log | present, `HWCAP_ASIMDDP`-gated, **on** |
| SVE | `HWCAP_SVE` on device | **absent on this chip**; two video chapters inapplicable |
| GPU tile memory | Adreno guide + `VkPhysicalDeviceMemoryProperties` | type 3 `LAZILY_ALLOCATED` exists and is **never used** — open |
| `LOAD_OP_CLEAR` | on-device counters | **51/51 clears eligible**; key bit and plumbing landed, call site pending |

## What is left, in priority order

1. **Profile before auditing further.** The theoretical sweeps are exhausted;
   what remains is to find the hot code and check *that* against the manuals.
   Blocked on a debuggable build: `simpleperf` refuses with *"Package
   net.rpcsx.easy doesn't exist or isn't debuggable/profileable"*. Rebuild with
   `-PrpcsxThorDebuggable=1`, profile Eternal Sonata (the SPU-heavy title, SPU
   47.1%), then audit the top symbols.
2. **`LOAD_OP_CLEAR` call site** — 100% eligibility measured, infrastructure
   landed, the remaining work is state handling around `m_current_renderpass_key`
   and its two caches. See [`adreno-tiler.md`](adreno-tiler.md).
3. **Transient attachments on tile memory** — `TRANSIENT_ATTACHMENT` +
   `LAZILY_ALLOCATED` appear nowhere in the VK backend, and the vendor documents
   the saving as a power win. See [`uma-bar-heap.md`](uma-bar-heap.md).
4. **§4.2, spill GPRs to vector registers** — aimed exactly at a JIT under
   register pressure. Whether LLVM exposes it is unestablished.

## Standing rule for this audit

A row in a manual is a hypothesis. It earns a code change only after a
measurement on this device, and the measurement has to be of a workload where
the code is actually hot — `cmp_rdata` looked critical at 10 million calls, and
those calls only existed because of a deadlock that has since been fixed.
