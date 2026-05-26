# CPU/SPU to CPU/GPU Translation Research

- Status: `research-plan`
- Game: Eternal Sonata `BLUS30161`
- Device target: AYN Thor Max first, Base/Pro later
- Created: 2026-05-18

## Current Reading

The captures do not yet support a broad "run SPU on GPU" rewrite. The field
scene is still dominated by SPU/MFC work around image `0x958dfe208b686622`,
hot PCs `0x25cc` and `0x451c`, with zero sampled RSX-local bytes. That makes
the strongest path a recognized SPU-kernel/codegen replacement first, and a
GPU path only after we prove the job is bulk, stable, and either GPU-consumed
or large enough to amortize transfer, dispatch, barriers, and verification.

The previous crash history matters. The rtime-keyed reservation notifier port
caused deterministic `SIGBUS BUS_ADRALN` crashes, and the later busy-wait /
GETLLAR speed knobs did not beat the reduced-loop baseline. So the next
experiments should avoid changing reservation semantics or global wait behavior
until the generated work body is understood.

## Papers And Systems That Map To This

### Cell BE Compiler/Runtime Work

IBM's Cell papers are still the most literal mental model for this project:
SPU work wins when software overlaps DMA and compute and when compilers expose
the Cell's heterogeneous parallelism.

- `Chip multiprocessing and the Cell Broadband Engine`
  https://research.ibm.com/publications/chip-multiprocessing-and-the-cell-broadband-engine
- `Using advanced compiler technology to exploit the performance of the Cell
  Broadband Engine architecture`
  https://research.ibm.com/publications/using-advanced-compiler-technology-to-exploit-the-performance-of-the-cell-broadband-enginetm-architecture

Project read: our `0x25cc` / `0x451c` hot PCs look like exactly this class of
MFC command issue / wait / transfer choreography. The correct translation target
is probably not "GPU executes SPU instructions"; it is "recognize the stable
SPU kernel and compile the repeated transfer/computation pattern better."

### Binary Hotspot Extraction To GPU

GXBIT proposes a two-phase route: first profile/extract parallel hot spots from
binary code, then generate hybrid CPU/GPU execution.

- `Two-phase execution of binary applications on CPU/GPU machines`
  https://www.sciencedirect.com/science/article/abs/pii/S0045790614000299

Project read: our `GpuSuperpathScout` and summary classifier are already the
right first phase. The missing second phase is not Vulkan yet; it is a stricter
candidate proof that the hot SPU loop has no loop-carried dependency that would
make offload a tiny-dispatch trap.

### Vectorized Binary Translation

VectorVisor runs many copies of a CPU-like program on GPU threads and handles
system-call-like behavior with continuations.

- `VectorVisor: A Binary Translation Scheme for Throughput-Oriented GPU
  Acceleration`
  https://www.usenix.org/conference/atc23/presentation/ginzburg

Project read: useful as a warning. Eternal Sonata field is not many independent
server requests; it is tightly synchronized SPU/PPU/RSX state. The idea only
becomes relevant if we find many independent instances of the same SPU kernel
with delayed consumption and no immediate CPU readback.

### Batched Emulator Work On GPU

CuLE is the relevant emulator-side warning label: it gets its GPU win by
running thousands of Atari instances concurrently and rendering frames directly
on the GPU, avoiding CPU/GPU communication bandwidth as a bottleneck.

- `Accelerating Reinforcement Learning through GPU Atari Emulation`
  https://arxiv.org/abs/1907.08467

Project read: this supports batching/residency, not tiny one-off SPU DMA
dispatches. Eternal Sonata has one latency-sensitive game instance, so GPU work
needs either many independent jobs per batch or RSX-local consumption. A single
16 KB SPU DMA ladder is not enough.

### Explicit Parallel IR Translation

Ocelot shows dynamic translation of an explicitly parallel IR across CPU/GPU
targets, including dynamic target switching.

- `The Design and Implementation of Ocelot's Dynamic Binary Translator from PTX
  to Multi-Core x86`
  https://repository.gatech.edu/entities/publication/df78c2e2-085f-4159-a0ed-7bbbbe86ca81
- `Translating GPU Binaries to Tiered SIMD Architectures with Ocelot`
  https://repository.gatech.edu/bitstreams/3b7b9a6b-149c-4fca-8e1c-6cfd8e99eaad/download

Project read: if we do GPU translation, the sane design is to lift a recognized
SPU kernel into a small explicit parallel IR first. Translating raw arbitrary
SPU control flow straight to SPIR-V would reproduce the hardest parts of a
general DBT.

### SPMD-On-SIMD And Compiler Vectorization

ISPC and Parsimony argue that SPMD-style code can map cleanly onto CPU SIMD and
modern compiler flows.

- `ispc: A SPMD Compiler for High-Performance CPU Programming`
  https://llvm.org/pubs/2012-05-13-InPar-ispc.html
- `Parsimony: Enabling SIMD/Vector Programming in Standard Compiler Flows`
  https://research.nvidia.com/publication/2023-02_parsimony-enabling-simdvector-programming-standard-compiler-flows

Project read: Thor's first win should keep mining ARM64 LLVM/NEON/dotprod,
because the reduced-loop path already moved the needle and avoids CPU/GPU
handoff costs. GPU compute should compete against a serious CPU SIMD baseline,
not against the pre-optimized Debug-core numbers.

### Dependence Analysis Before Offload

AutoTornado combines static dependence/purity analysis with runtime support for
heterogeneous loop parallelization.

- `Can We Run in Parallel? Automating Loop Parallelization for TornadoVM`
  https://arxiv.org/abs/2205.03590
- TornadoVM FAQ, especially runtime codegen to OpenCL/PTX/SPIR-V and loop
  suitability notes:
  https://www.tornadovm.org/faq

Project read: for the SPU lane, build a candidate proof that looks more like
dependence analysis than wishful dispatch. For a given image/hash/PC, log input
ranges, output ranges, loop-carried addresses, command type, and consumer timing
before generating a fast path.

### Vulkan As A Compute Target

Recent OpenMP-to-Vulkan work shows a plausible path from higher-level loop
regions to Vulkan shaders/SPIR-V, including mobile/embedded GPUs.

- `High-level Programming of Vulkan-based GPUs Through OpenMP`
  https://link.springer.com/article/10.1007/s10766-026-00816-8
- MLIR SPIR-V dialect docs:
  https://mlir.llvm.org/docs/Dialects/SPIR-V/
- Khronos SPIR-V overview:
  https://www.khronos.org/spirv/

Project read: the first prototype can be handcrafted GLSL/SPIR-V, but the
longer-term shape should be "recognized SPU loop -> small kernel IR -> SPIR-V"
with `spirv-opt` and cached pipelines. Do not build a generic SPU-to-SPIR-V
compiler first.

### CPU/GPU Load Balancing

GROMACS is a good example of CPU SIMD and GPU acceleration coexisting with
load-balancing instead of blindly moving all work to the accelerator.

- `Heterogeneous Parallelization and Acceleration of Molecular Dynamics
  Simulations in GROMACS`
  https://arxiv.org/abs/2006.09167

Project read: the likely end state is mixed execution. SPU reduced-loop/codegen
keeps latency-sensitive work on CPU; GPU handles only large, repeatable,
data-parallel jobs whose outputs can stay near RSX/Vulkan.

### Compute Plus Graphics Sharing

VUDA is CUDA/Vulkan and not directly portable to Adreno Android, but its
message is important: compute/graphics wins depend on sharing execution and
memory without copy-heavy ping-pong.

- `VUDA: Breaking CUDA-Vulkan Isolation for Spatial Sharing of Compute and
  Graphics on the Same GPU`
  https://arxiv.org/abs/2605.01352

Project read: if we ever offload to GPU, keep it inside the existing Vulkan
renderer/device path where possible. A separate API path or per-job readback is
almost certainly a loss.

### Mobile GPU Reality

Qualcomm's own OpenCL optimization note starts from the uncomfortable truth
that mobile workloads are often memory-bound, and barriers/local memory can
erase theoretical compute wins.

- `Better OpenCL performance on Qualcomm Adreno GPU - memory optimization`
  https://www.qualcomm.com/news/onq/2016/06/better-opencl-performance-qualcomm-adreno-gpu-memory-optimization
- Khronos Vulkan synchronization guide:
  https://docs.vulkan.org/guide/latest/synchronization.html
- Khronos Vulkan synchronization examples:
  https://docs.vulkan.org/guide/latest/synchronization_examples.html

Project read: the summarizer's `tiny-dispatch-trap` and `dispatch_risk` labels
are not bookkeeping; they are the difference between a speed path and adding
more stalls to an already synchronized emulator.

## Experiment Ladder

### 1. Finish CPU-side SPU reduced-loop parity

Priority: highest.

Local status: reduced-loop u4 is still the only real speed signal. Upstream
commits worth checking against local Android are:

- `37a07ae` - optimize `FM`, `FMA`, and `FCGT` in reduced loop.
- `619fe7b` - classify SPU memory and context memory instructions.
- `13de823` - fix register origin for reduced loop.
- `02eb549` - fix register updates in second block of reduced loop.
- `1627757` / `4542020` - dotprod work for `GB`/`SUMB` style operations.

Concrete next step: diff local `SPUCommonRecompiler.cpp`,
`SPULLVMRecompiler.cpp`, `SPURecompiler.h`, and `CPUTranslator.h` against those
upstream commits, then port only the missing correctness/optimizer pieces behind
the existing reduced-loop cache key.

### 2. Dynamic MFC command shape proof

Priority: high.

The hot PCs both hit non-constant `MFC_Cmd` warnings:

- `[0x25cc] MFC_Cmd: $11 is not a constant`
- `[0x451c] MFC_Cmd: $12 is not a constant`

Concrete next step: add a low-overhead `BLUS30161` / image-gated probe that
counts command values and surrounding `LSA/EAL/Size/TagID` shapes at these PCs.
If the runtime values collapse to a tiny set, emit a guarded fast path that
avoids generic `spu_exec_mfc_cmd` overhead for those stable shapes.

This is "CPU SPU translation to better CPU" rather than GPU, but it directly
targets the captured bottleneck and avoids the previous reservation crash class.

### Windows MFC Shape Probe - 2026-05-18

Status: `windows-shape-proof`.

Added a Windows lab probe for the hot SPU MFC command sites:

- `tools/windows_rpcs3_lab.ps1 -EternalSonataMfcShapeProbe Profile`
- `tools/eternal_sonata_speed_sprint.ps1 -EternalSonataMfcShapeProbe Profile`
- Process env: `RPCS3_ES_MFC_SHAPE_PROBE=profile`
- Summary output:
  `eternal-sonata-mfc-shape-profile.csv` plus an `MFC Shape Profile` table in
  `eternal-sonata-gpu-probe-summary.md`.

The first unthrottled run proved the hook worked but produced a huge
`RPCS3.log`, so the lab patch now rate-limits MFC shape logs to about one
sample per 100 ms when no RSX-local traffic is present.

Clean field capture:

- Run dir:
  `debug-captures/windows-lab/20260518-160806-spu-mfc-shape-profile-throttled-windows/`
- Host grade: clean across five snapshots.
- Window routing: RPCS3 moved to `\\.\DISPLAY2`.
- Visual result: correct-looking first playable field screenshot at
  `screenshots/screenshot-0147s.png`, overlay around `30 FPS`.
- Ghidra refresh:
  `debug-captures/ghidra-spu-window-20260518-mfc-shape/spu-hot-window-ghidra.txt`.
- Build proof:
  `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed after the probe, with only the usual `LNK4098` warning.

Summary:

- GPU probe records: `1428`.
- MFC shape records: `17083` raw, `502` aggregated.
- Total observed DMA bytes: about `1,164.46 MB`.
- RSX-local traffic: `0` records.
- Offload fit mix: `610` `spu-kernel-hle`, `818` `too-small`.
- Hot PC bytes:
  - `0x25cc`: `475` records, about `750.44 MB`, max DMA `16 KB`;
  - `0x451c`: `953` records, about `414.02 MB`, max DMA `16 KB`.

Top shape findings:

- `0x0a70`: `GETLLAR` (`cmd=0xd0`) dominated the sampled shape table with
  `714,685` hits against fixed `LSA=0x4a00`, `EA=0x8ab280`, size `128`.
- `0x25cc`: stable large-copy ladder, mostly `GET` (`cmd=0x40`), tag `31`,
  size `16 KB`, repeated LSAs such as `0x3000`, `0x7000`, `0xb000`, `0xf000`,
  and later `0x13000..0x3b000`. A small sampled `PUT` ladder (`cmd=0x20`) uses
  the same size/tag shape.
- `0x451c`: noisier small/list DMA issuer, with frequent `GET` rows at sizes
  `128`/`256`, list/fence GET rows (`cmd=0x46`), and many smaller `cmd=0x42`
  shapes.

Reading:

- This is a stronger SPU/codegen/HLE target than a GPU target. The hot path is
  stable enough to specialize, but still produces zero RSX-local bytes.
- The cleanest first fast path is not a replay cache and not Vulkan compute. It
  is a verify-gated dynamic-MFC specialization for image
  `0x958dfe208b686622`, especially the `0x25cc` 16 KB GET ladder.
- `0x451c` needs more grouping before fast mode because it has many small/list
  shapes and a `tiny-dispatch-trap` profile.
- Reservation semantics remain off-limits for this slice: the `GETLLAR` signal
  is real, but previous wait/notifier changes did not beat reduced-loop and once
  hit the `SIGBUS` crash class.

### Windows MFC Ladder Cost Profile - 2026-05-19

Status: `windows-cost-proof`.

Added timing counters to the Windows `0x25cc` MFC ladder probe:

- `check_us`: time spent in the generic `do_dma_check` safety comparison;
- `transfer_us`: time spent in direct `do_dma_transfer` when ladder `Fast` is
  active;
- `total_us`: whole gated ladder helper time;
- `max_*`: worst single-hit timings.

The PowerShell summarizer now keeps old logs readable by defaulting missing
timing fields to zero and emits timing totals in the `MFC 0x25cc Ladder Gate`
section plus `eternal-sonata-mfc-ladder-profile.csv`.

Build proof:

- `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed after the timing patch, with the usual `LNK4098` warning.

Compatibility checks:

- PowerShell parser creation passed.
- Old Windows ladder logs `20260518-162907-mfc-ladder-verify-windows` and
  `20260518-163226-mfc-ladder-fast-windows` re-summarized cleanly with zeroed
  timing fields.

Verify run:

- Run dir:
  `debug-captures/windows-lab/20260519-000432-mfc-ladder-cost-profile-fieldbattle-windows-windows/`
- Window routing:
  RPCS3 moved to `\\.\DISPLAY2`.
- Host grade:
  clean across five snapshots.
- Visual route:
  matched the paired run and stayed visually correct, but this macro landed in
  the story/tree cutscene rather than a first-battle proof.
- Counts:
  `9,588` eligible `0x25cc` 16 KB GET ladder hits, `9,588` verify hits, zero
  generic-ordering blocks, zero ordering mismatches, zero RSX-local records.
- Timing:
  `check=0.099 ms`, `transfer=0.000 ms`, `total=0.367 ms`; average total only
  `0.038 us` per eligible hit.

Fast run:

- Run dir:
  `debug-captures/windows-lab/20260519-000651-mfc-ladder-cost-profile-fieldbattle-fast-windows-windows/`
- Window routing:
  RPCS3 moved to `\\.\DISPLAY2`.
- Host grade:
  clean across five snapshots.
- Visual route:
  paired story/tree cutscene screenshots matched Verify, including the
  `0058s` subtitle frame.
- Counts:
  `9,633` eligible hits, `9,633` fast hits, zero blocks, zero mismatches, zero
  RSX-local records.
- Timing:
  `check=0.104 ms`, `transfer=10.448 ms`, `total=11.547 ms`; average transfer
  `1.085 us` per 16 KB hit, max single transfer/total `55 us`.

Reading:

- The ladder shortcut is safe enough to keep as a probe, but it is not a
  200% Windows speed track and not a GPU-offload candidate by itself.
- The generic ordering check is too cheap to matter, and the direct 16 KB copy
  work is only about `10.4 ms` across this whole route. Moving that copy to GPU
  would still need the SPU-local consumer to move too, otherwise synchronization
  and readback dominate.
- The next useful Windows-only work is to time and specialize the SPU body or
  LLVM non-constant `MFC_Cmd` fallback around `0x25cc`, then repeat for the
  noisier `0x451c` issuer. If a recognized body is stable and data-parallel,
  lift that body to the recognized-kernel IR described below.

### Windows Dynamic MFC Fallback Profile - 2026-05-19

Status: `windows-fallback-closed`.

Added a Windows-only timing scout for the LLVM non-constant `MFC_Cmd` fallback
path. The probe is gated by the existing `RPCS3_ES_MFC_LADDER=verify|fast`
switch, title `BLUS30161`, image `0x958dfe208b686622`, and hot PCs
`0x25cc` / `0x451c` / `0x0a70`. It measures the path that reaches
`spu_write_channel`, sets `ch_mfc_cmd.cmd`, and calls `process_mfc_cmd`.

New summary output:

- `Eternal Sonata MFC dynamic probe:` log rows;
- `eternal-sonata-mfc-dynamic-profile.csv`;
- `Dynamic MFC Cmd Fallback` table in `eternal-sonata-gpu-probe-summary.md`.

Build proof:

- `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed after the dynamic timing patch, with only the usual `LNK4098` warning.

Field run:

- Run dir:
  `debug-captures/windows-lab/20260519-093723-mfc-dynamic-fallback-profile-field-windows-windows/`
- Route:
  default Windows `field` route through `tools/eternal_sonata_speed_sprint.ps1`.
- Window routing:
  RPCS3 moved to `\\.\DISPLAY2`.
- Host grade:
  clean across five snapshots.
- Visual result:
  correct-looking Path to Tenuto field at `screenshots/screenshot-0147s.png`,
  overlay around `30 FPS`, with no obvious missing foliage/menu-overlay damage.

Summary:

- RSX-local traffic records: `0`.
- Offload fit mix: `809` `too-small`, `607` `spu-kernel-hle`.
- Ladder check remained tiny: `6,933` eligible `0x25cc` hits, zero
  blocks/mismatches, `0.257 ms` total probe-side time.
- Dynamic `MFC_Cmd` fallback:
  - `91,647` hits, all successful;
  - `306.80 MB` dynamic MFC bytes;
  - `31.248 ms` total, `0.341 us/hit` average, `62 us` max single hit;
  - `0x25cc`: `14,805` hits / `13.075 ms`;
  - `0x451c`: `76,842` hits / `18.173 ms`;
  - command mix: `84,239` GET, `7,408` PUT, `29,162` list, `0` atomic.

Top dynamic shape totals:

- `0x451c cmd=0x46` list/fence GET: `70,344` hits, `16.456 ms`,
  `82,550,712` nominal bytes, `27,060` list hits.
- `0x25cc cmd=0x20` PUT ladder: `14,805` hits, `13.075 ms`,
  `231,172,976` nominal bytes.
- `0x451c cmd=0x40` GET: `5,769` hits, `1.421 ms`.
- `0x451c cmd=0x42` GET+fence: `729` hits, `0.296 ms`.

Disasm read:

- `0x25cc` sits in a short MFC/tag update/wait helper: load command words,
  call `0x28d0`, write tag mask/update, read tag status, and return.
- `0x451c` is the tight small/list MFC issuer loop: choose size, write
  `MFC_Size`, `MFC_TagID`, dynamic `MFC_Cmd`, update address/remaining bytes,
  and branch back to `0x449c`.

Reading:

- This closes the dynamic `MFC_Cmd` wrapper as the big win. It is real traffic,
  but only about `31 ms` across a full Windows field route.
- A guarded helper that skips `spu_write_channel` might be nice cleanup, but it
  cannot plausibly satisfy the 200% moving-gameplay Windows gate.
- The next CPU-load target must be deeper than MFC command issue: either the
  SPU consumer/body after these DMA transfers, a broader list-transfer/copy
  batching path with a measured wait reduction, or an RSX-local consumer found
  by a later scout. Do not port this probe or a fallback helper to Thor.

### Windows MFC List / Wait / Exact-PC Profile - 2026-05-19

Status: `windows-wait-closed-next-atomic-loop-hle`.

Added Windows-only timing scouts for the hot list-transfer body and MFC
TagStat/AtomicStat reads. The final revision also logs a 64-slot exact JIT-PC
histogram for fast LLVM RDCH reads and dumps disassembly windows for those PCs.

Build and parser proof:

- `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed after the list/wait probe, the LLVM RDCH fast probe, and the widened
  exact-PC64/disasm patch, with only the usual `LNK4098` warning.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` parser creation passed after
  each summarizer change.

Runs:

- `debug-captures/windows-lab/20260519-103601-mfc-list-wait-profile-field-windows-windows/`
- `debug-captures/windows-lab/20260519-104437-mfc-llvm-rdch-fast-profile-field-windows-windows/`
- `debug-captures/windows-lab/20260519-110116-mfc-wait-hotpc-disasm-field-windows-windows/`
- `debug-captures/windows-lab/20260519-111316-mfc-wait-exact-pc-field-windows-windows/`
- `debug-captures/windows-lab/20260519-112044-mfc-wait-exact-pc64-disasm-field-windows-windows/`

Visual / host proof:

- Final Windows runs routed RPCS3 to `\\.\DISPLAY2` with
  `-WindowsGameScreen 1`.
- Host contention was clean; no Vita3K or competing emulator was active.
- Final exact-PC64 screenshot
  `debug-captures/windows-lab/20260519-112044-mfc-wait-exact-pc64-disasm-field-windows-windows/screenshots/screenshot-0146s.png`
  shows the Path to Tenuto field rendering correctly at about `30 FPS`.

Findings:

- RSX-local traffic remained `0`, with `0` indirect RSX resource overlap.
- List-transfer timing stays tiny. The field runs saw about `28.6k` to `31.4k`
  hot list calls, all successful, with only about `9-10 ms` summed timing even
  before correcting for cumulative log snapshots.
- Dynamic non-constant `MFC_Cmd` fallback stays tiny too: about `31-35 ms`
  summed route timing, still too small for the 200% moving-gameplay gate.
- Generic `get_ch_value` wait timing saw no blocking route. The LLVM fast RDCH
  probe saw TagStat/AtomicStat reads, but they were all fast inline reads with
  `0` blocking reads.
- The final exact-PC64 summary uses per-SPU peak counters instead of summing
  cumulative snapshots. It found `18,568` peak exact-PC reads with only `189`
  overflow reads beyond the 64-slot table.
- Top JIT-PC blocks:
  - `0xa74`: `7,872` AtomicStat reads;
  - `0xad8`: `1,583` AtomicStat reads;
  - `0x344`: `1,373` AtomicStat reads;
  - `0x664`: `1,373` AtomicStat reads;
  - `0x2734`: `781` TagStat reads.
- Disassembly read:
  - `0xa74` / `0xad8` is a GETLLAR + PUTLLC reservation update loop. The RDCH
    instruction is at `0xaf0`, then the block updates local scratch and issues
    PUTLLC at `0xb40`, retrying back to `0xad8` on AtomicStat failure.
  - `0x344` / `0x664` is another GETLLAR/AtomicStat retry loop around local
    scratch at `0x100`-`0x1e0`, with a branch from `0x664` back to `0x324`.
  - `0x2734` sits in a related MFC command / AtomicStat / follow-up GETLLAR
    path, not a bulk GPU-friendly compute body.

Reading:

- This closes the list-transfer and wait-channel branches as the big speed
  lane. They are valuable as signposts, not as offload payload.
- The next Windows target is SPU reservation/atomic-loop specialization:
  title/image-gated HLE or reduced-loop/codegen around the GETLLAR/PUTLLC
  sequences at `0xa74` / `0xad8` and `0x344` / `0x664`, with byte/hash
  verification before fast mode.
- Do not port this to Thor and do not build a Vulkan compute path from these
  loops. The loop is fine-grained SPU reservation control; GPU only becomes
  interesting if a later scout finds a stable bulk data-parallel body behind it.

## 2026-05-19 PUTLLC16 Analyzer Correlation

Change:

- Extended `tools/summarize_eternal_sonata_gpu_probe.ps1` to parse upstream SPU
  analyzer lines:
  - `GETLLAR pattern entry point`;
  - `PUTLLC16 Pattern Detected!`;
  - `PUTLLC pattern breakage`.
- The summarizer now writes
  `eternal-sonata-putllc16-profile.csv` and adds a `PUTLLC16 Analyzer` section.
- Detected patterns and breakage PCs are sorted by nearby/exact MFC wait-PC
  correlation so hot reservation loops are visible first.

Validation:

- Parser creation passed.
- Re-summarized trusted Windows run:
  `debug-captures/windows-lab/20260519-112044-mfc-wait-exact-pc64-disasm-field-windows-windows`.

Result:

- Analyzer records: `42` total.
- GETLLAR entry records: `22`.
- PUTLLC16 detected records: `8`.
- PUTLLC pattern breakage records: `12`.
- Hottest detected pattern:
  - pattern hash `620oYSe8uQqq9eTkhWfMqoEXX0us`;
  - function `0xa30-1gJ45f2oQ0UtLQQEPGf2yFdAaYCQ`;
  - PUT PC `0xad4`;
  - nearby wait PC `0xad8`;
  - `1,583` nearby AtomicStat reads.
- Hottest breakage:
  - cause `35`;
  - reason `LQR/STQR store after prior invalid LS access`;
  - break PC `0xb20`;
  - LSA PC `0xad8`;
  - `1,583` exact AtomicStat reads.

Reading:

- The top `0xad8` reservation loop is already seen by the upstream PUTLLC16
  optimizer, but the same loop also has a recognizer breakage. That is more
  promising than a blind GPU dispatch: first explain the partial coverage and
  prove whether a title/image/hash-gated CPU reduced-loop tweak drops hot
  AtomicStat traffic without changing results.
- The detected PUTLLC16 route is CPU/SPU codegen/HLE work, not RSX-on-GPU work.
  Keep the GPU goal alive, but do not move this specific fine-grained atomic
  loop to Vulkan unless a later body scout exposes a stable bulk data-parallel
  payload behind it.

## 2026-05-19 Accurate SPU Reservations A/B

Change:

- Added a Windows-only per-run config override:
  - `tools/windows_rpcs3_lab.ps1 -SpuAccurateReservations Keep|On|Off`;
  - `tools/eternal_sonata_speed_sprint.ps1 -WindowsSpuAccurateReservations
    Keep|On|Off`.
- The wrapper writes `rpcs3-run-config.yml` into the capture directory and
  passes it through RPCS3 `--config`; the global RPCS3 config remains unchanged.

Runs:

- `20260519-121538-putllc16-accurate-reservations-off-field-windows-windows`
  - `Accurate SPU Reservations: false`;
  - clean host, RPCS3 routed to `\\.\DISPLAY2`;
  - correct Path to Tenuto field screenshot;
  - capped around `30 FPS`, so it cannot prove a performance win.
- `20260519-122221-putllc16-accurate-on-uncap240-field-windows-windows`
  - `Accurate SPU Reservations: true`;
  - frame limit off, vblank `240`;
  - clean host, routed to `\\.\DISPLAY2`;
  - route landed in Options at about `240 FPS`.
- `20260519-122507-putllc16-accurate-off-uncap240-field-windows-windows`
  - `Accurate SPU Reservations: false`;
  - frame limit off, vblank `240`;
  - clean host, routed to `\\.\DISPLAY2`;
  - route landed in Options at about `240 FPS`.

Reading:

- Disabling Accurate SPU Reservations did not expose a visible speed win in this
  pass. The uncapped pair hit the 240 FPS ceiling in menu/options, not moving
  field gameplay, and CPU totals were similar.
- Keep the override for future controlled A/B runs, but do not promote it and
  do not port any related behavior to Thor.
- The next useful Windows-only step is not another global reservation config
  flip; it is a title/image/hash-gated verifier around the `0xad8` reservation
  loop that can prove exact output/state equivalence before replacing only that
  loop.

## 2026-05-19 GPU-Port Accounting

Question:

- How much have we ported to GPU versus original?

Answer:

- Original RPCS3 already renders PS3 RSX graphics through the Vulkan GPU
  renderer. That baseline GPU use is not new project porting.
- New project CPU/SPU-to-GPU promoted replacement: `0 B`, `0%`.
- Latest SPU/MFC capture with the new scoreboard:
  `20260519-121538-putllc16-accurate-reservations-off-field-windows-windows`.
  It reports:
  - promoted CPU/SPU -> GPU replacement: `0` records, `0 B`, `0.000%`;
  - direct RSX-local scout traffic: `0` records, `0 B`, `0.000%`;
  - indirect SPU-DMA/RSX-resource overlap: `0` records, `0 B`, `0.000%`.
- Earlier RSX fused-resolve and depth-readonly work is GPU/RSX-side
  experimentation, but it is not counted as ported/promoted work because it has
  not crossed the stable 200% moving-gameplay field/menu/battle gate.

Reading:

- We have mapped a lot of where the CPU time is *not* GPU-portable yet. That is
  useful, but the honest counter is still zero for new CPU/SPU load moved to
  GPU.
- Next GPU-accounting movement needs either nonzero RSX-local SPU traffic or a
  verified RSX-local render-path replacement. Current `0xad8` reservation-loop
  work is CPU/SPU specialization, not GPU offload.

## 2026-05-19 PUTLLC16 Relaxed Reservation A/B

Question:

- Can the hot Eternal Sonata `0xad4`/`0xad8` PUTLLC16 reservation loop produce a
  clean Windows micro-win if we let only that recognized pattern use the older
  relaxed reservation code path?

Implementation:

- Added `RPCS3_ES_PUTLLC16_RELAXED=1` in local `rpcs3-upstream`.
- Exposed it as:
  - `tools/windows_rpcs3_lab.ps1 -EternalSonataPutllc16Reservations Relaxed`;
  - `tools/eternal_sonata_speed_sprint.ps1 -EternalSonataPutllc16Reservations Relaxed`.
- Scope is intentionally narrow:
  - title `BLUS30161`;
  - SPU PUTLLC16 pattern PC `0xad4`;
  - default behavior remains accurate/off.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` now writes `putllc16_res`
  into the PUTLLC16 runtime CSV and summary table.

Verification:

- Built Windows RPCS3:
  `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`.
- Cleared only BLUS30161 SPU cache files before recompiling hot code for the
  A/B runs.
- Relaxed capped field run:
  `20260519-142740-putllc16-relaxed-pc0ad4-field-windows-windows`.
  - Routed to `\\.\DISPLAY2`.
  - Correct-looking Path to Tenuto field screenshot.
  - About `30 FPS`.
  - Host CPU samples near field: `22.8%`, `22.6%`.
  - PUTLLC16 runtime peak: `2169` hits, `648` success, `1521` fail,
    `putllc16_res=relaxed-pc0ad4`.
- Accurate capped field run:
  `20260519-144511-putllc16-accurate-capped-field-windows-windows`.
  - Routed to `\\.\DISPLAY2`.
  - Correct-looking Path to Tenuto field screenshot.
  - About `30 FPS`.
  - Host CPU samples near field: `22.7%`, `21.5%`.
  - PUTLLC16 runtime peak: `2083` hits, `133` success, `1950` fail,
    `putllc16_res=accurate`.
- Relaxed uncapped run:
  `20260519-143410-putllc16-relaxed-pc0ad4-uncap240-field-windows-windows`.
  - Routed to Options at about `240 FPS`, not moving field gameplay.
- Accurate uncapped run:
  `20260519-143836-putllc16-accurate-uncap240-field-windows-windows`.
  - Reached field around `120 FPS`.

Reading:

- This did not clear the `windows-micro-win` bar. The capped field host samples
  are basically flat/noisy, and the uncapped pair is route-mismatched.
- The relaxed path changed reservation success/fail shape, but not in a way we
  can call a stable speed improvement.
- GPU-port counter remains `0 B / 0%`; this is CPU/SPU reservation specialization,
  not GPU offload.
- Keep the switch default-off for more precise probes, but do not port it to Thor.

Next:

- Build an exact verifier/state-hash probe around the `0xad8` reservation loop:
  reservation address, `rtime`, `raddr`, LS source/dest hash, atomic-stat result,
  and post-loop branch outcome. Only after that should we try a title-gated fast
  replacement for the loop.

## 2026-05-20 PUTLLC16 Pair Scout

Question:

- Can the hot Eternal Sonata `0xad8` reservation loop be collapsed by treating
  the two PC-relative `LQR/STQR` slots in the same 128-byte reservation line as
  a recognized pair?

Implementation:

- Added `RPCS3_ES_PUTLLC16_PAIR=profile|fast` in local `rpcs3-upstream`.
- Exposed it as:
  - `tools/windows_rpcs3_lab.ps1 -EternalSonataPutllc16Pair Profile|Fast`;
  - `tools/eternal_sonata_speed_sprint.ps1 -EternalSonataPutllc16Pair Profile|Fast`.
- Analyzer profiling now records pair-shaped PC-relative accesses instead of
  immediately discarding every multi-slot reservation pattern.
- Fast mode only activates for hashes in `allowed_pair_patterns`; that allowlist
  is empty after the failed test below.

Profile result:

- Field profile run:
  `debug-captures/windows-lab/20260520-192818-putllc16-pair-profile-field-windows`.
- Candidates:
  - `Y01tfnsGZ1qQrTV61LSta6n5KLw7`, `put_pc=0xb40`, offsets `0x2330/0x2340`,
    entry `0xa7c`;
  - `79w5SL0uvyoiJN6A3tK6iKKkqTYr`, `put_pc=0x156c`, offsets `0x1940/0x1950`,
    entry `0x1470`.

Fast result:

- Temporarily allowing `Y01tfnsGZ1qQrTV61LSta6n5KLw7` did not reach field:
  `debug-captures/windows-lab/20260520-193706-putllc16-pair-fast-uncap240-field-windows`.
- Failure signal: `CellSpursKernel0` access violation writing `0xffdead00`,
  SPU PC `0x01320`.

Reading:

- This proves the analyzer can see the pair shape, but the first fast shortcut
  violated guest/SPURS invariants. The reservation loop is more than a
  two-chunk memory compare/write.
- Keep `RPCS3_ES_PUTLLC16_PAIR` as a Windows-only diagnostic. Do not add an
  allowlisted fast hash until a verify path compares the full 128-byte
  reservation line, `raddr/rtime`, event/notification behavior, and post-loop
  branch state.
- GPU-port counter remains `0 B / 0%`; this is CPU/SPU reservation
  specialization, not RSX/Vulkan offload.

### 3. Recognized-kernel IR before Vulkan

Priority: medium.

If the MFC/body proof exposes a data-parallel inner body, lift only that body
into a tiny project-owned IR:

- input ranges and alignment;
- output ranges;
- scalar constants;
- vector ops;
- consumer timing;
- verification hash.

Backends can then be:

- ARM64 LLVM/NEON/dotprod for low-latency mode;
- Vulkan compute/SPIR-V for bulk mode;
- CPU reference for verify mode.

Do not translate arbitrary SPU control flow. Translate recognized kernels.

### 4. Verify-only GPU mirror

Priority: medium/low until an RSX-consumed candidate appears.

First GPU mode should run CPU/SPU normally and mirror the candidate on GPU:

- persistent Vulkan buffers;
- one cached pipeline per recognized kernel signature;
- batched dispatches where possible;
- no per-job GPU readback unless the batch is large;
- compare output hashes at safe synchronization points.

Fast mode only comes after repeated field, battle, and menu verify-clean runs.

### 5. RSX-adjacent GPU superpaths

Priority: scene-dependent.

This becomes attractive only if `GpuSuperpathScout`, RenderDoc, AGI, or the RSX
auditor proves outputs are consumed by GPU resources. Candidate classes:

- texture preparation / swizzle / decode;
- vertex transform or skinning buffers;
- particles;
- render-prep buffers;
- persistent graphics+compute shared resources.

The depth texture barrier skip proved a small mechanical win, but not a large
one. Treat it as supporting evidence for RSX-local surgery, not the main path.

## Guardrails

- Do not change reservation notifier semantics in the same slice as codegen or
  GPU work.
- Do not enable fast GPU mode without verify-only history.
- Do not use Debug native cores for FPS claims.
- Do not benchmark GPU ideas without field, first battle, and menu correctness.
- Do not count an offload win unless CPU hot threads drop without GPU queue or
  barrier stalls replacing them.
- Leave all new paths gated by title, image hash, PC/range signature, and a
  single rollback property.

## Decision

2026-05-19 field update: the Windows-only capsule recorder now exists as
`RPCS3_ES_KERNEL_CAPSULE=profile`. Capture
`debug-captures/windows-lab/20260519-175217-eternal-sonata-field-stock-qualcomm-windows`
reached the correct field and logged `1.39 GB` observed DMA with `1583` capsule
rows, but all rows landed in `reservation-risk` with `0 B` RSX-local traffic.
That keeps the current hot SPU kernel on the CPU-SIMD/HLE/reservation-loop track
until a later RSX-consumed capture proves a GPU-resident body.

The interesting idea is real, but the order matters:

1. mine reduced-loop and ARM64 codegen harder;
2. prove and specialize dynamic MFC command shapes at `0x25cc` / `0x451c`;
3. lift any stable bulk body into a tiny recognized-kernel IR;
4. only then test CPU+GPU split with verify-only Vulkan mirrors.

That gives us a path toward CPU/SPU translation to CPU+GPU without repeating the
crash-prone synchronization experiments.

## 2026-05-21 Moving-Loop Kernel Capsule Profile

Question:

- Does the clean delayed-confirm moving-field route reveal any SPU kernel
  capsule that is more GPU-shaped than the earlier field and battle scouts?

Run:

- `debug-captures/windows-lab/20260521-234607-cpu4-kernel-capsule-movingloop-profile-windows/`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-kernel-capsule-movingloop-profile -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataKernelCapsule Profile -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host checks were clean from prelaunch through postrun.
- Screenshots reached field start and movement:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0150s-move2.png`, and `screenshot-0162s-late.png`.
- The fatal/crash/Vulkan/validation scan had no real failures. Matches were
  normal config/export/disassembly/save-load text, not a runtime crash or Vulkan
  validation issue.
- Tagged FPS was noisy and not a speed proof: title bar about `28.69`, `33.54`,
  `38.35`, `35.26`; overlay about `31.13`, `30.93`, `42.91`, `28.86`.

Result:

- GPU/DMA candidate rows: `1592`.
- Kernel capsule rows: `1746`.
- Total observed DMA: `2,502.81 MB`.
- Largest single job: `13.32 MB` in `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`.
- Direct RSX-local traffic: `0` records, `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0` records.
- Offload fit: `spu-kernel-hle=1157`, `too-small=435`.
- GPU port scoreboard stayed at `0` promoted CPU/SPU-to-GPU records and `0 B`.
- Kernel capsule classifier: `18,737,301` capsule records, `2,502.81 MB`,
  `0 B` RSX-local bytes, `17,400,687` wait reads,
  `15,747,765` atomic reads, and `0` GPU-batch candidates.
- Every capsule row classified as `reservation-risk`; top PC was `0x451c`.
- Hot PC split: `0x451c` had `862` rows / `1,323.02 MB`; `0x25cc` had
  `730` rows / `1,179.80 MB`.
- Dynamic MFC fallback timing was measurable but not huge:
  `297,849` hits, `594.36 MB`, `237.957 ms` total, with `0x451c` contributing
  `274,484` hits / `214.432 ms` and `0x25cc` contributing `23,365` hits /
  `23.525 ms`.
- Exact wait-PC histogram again pointed at reservation/atomic loops, led by
  `0xa74`, `0x11e8`, `0xd28`, `0xad8`, `0x664`, and `0x344`.

Reading:

- This confirms the field and battle capsule scouts on the actual moving route:
  the hot work is large enough to matter, but it is not RSX-consumed and not a
  stable GPU batch candidate.
- Broad SPU-to-Vulkan compute is still the wrong move here. The evidence points
  to SPU kernel HLE, reduced-loop/codegen, or a reservation-loop verifier around
  `0x451c` / `0x25cc`.
- Classification: `parked` Windows migration scout, not `gpu-migration-credit`,
  not `windows-micro-win`, and not a 200% gate candidate.

Next:

- Build a verify-first reservation-loop/codegen probe around the hot AtomicStat
  blocks (`0xa74`, `0xad8`, related `0x451c` body) or a reduced-loop/HLE
  recognizer for the stable kernel signatures.
- Only revisit GPU/Vulkan compute for these SPU capsules if a future trace shows
  nonzero RSX-local bytes, indirect RSX overlap, or a real batched output that
  can be verified without immediate readback.

## 2026-05-22 Moving PUTLLC16 Pair Profile

Question:

- Do the known two-slot PUTLLC16 reservation-line candidates repeat on the
  clean delayed-confirm moving route, and can the summarizer preserve those rows
  as structured evidence?

Run:

- `debug-captures/windows-lab/20260522-001415-cpu4-putllc16-pair-profile-movingloop-windows/`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-putllc16-pair-profile-movingloop -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataPutllc16Pair Profile -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host checks were clean across five snapshots.
- Screenshots reached field start and movement:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- Fatal/crash/Vulkan/validation scan had no real failures. Matches were normal
  config/export/disassembly/save-load text.
- Tagged FPS was noisy and not used as a speed proof: title bar about `32.12`,
  `35.89`, `32.49`, `33.93`; overlay about `26.78`, `40.71`, `28.10`,
  `30.95`.

Tooling fix:

- `tools/summarize_eternal_sonata_gpu_probe.ps1` now preserves pure
  PUTLLC16-analyzer runs even when there are zero GPU/DMA candidate records.
- It also parses `PUTLLC16 Pair Pattern Candidate!` rows into
  `eternal-sonata-putllc16-profile.csv`, with pair offsets, write/access masks,
  and `no_notify`.
- Parser creation passed, and both this moving run plus the older
  `20260520-192818-putllc16-pair-profile-field-windows` capture re-summarized.

Result:

- GPU/DMA records: `0`. This run was a reservation analyzer, not a GPU/DMA
  scout.
- PUTLLC16 analyzer records: `42`.
- GETLLAR entry records: `22`.
- Ordinary PUTLLC16 detected patterns: `7`.
- Pair candidates: `2`.
- Pattern breakage records: `11`.
- Repeated pair candidates:
  - `Y01tfnsGZ1qQrTV61LSta6n5KLw7`, function
    `0xa7c-7PiXnkUPiv7ZdGvUkndsHKRu6ZNZ`, `put_pc=0xb40`, offsets
    `0x2330/0x2340`, write/access mask `0x18`.
  - `79w5SL0uvyoiJN6A3tK6iKKkqTYr`, function
    `0x1470-oHsUCKuwyVhNKsuxgWcL6ELHMUGa`, `put_pc=0x156c`, offsets
    `0x1940/0x1950`, write/access mask `0x30`.
- These are the same two pair candidates from the older field profile.
- Breakage reasons were mostly invalid-LS-access follow-ups:
  `cause=37` LQA/STQA (`4` rows), `cause=16` LQD/STQD (`3` rows), plus
  `cause=8` (`2` rows), `cause=23` LQX/STQX (`1` row), and `cause=35`
  LQR/STQR (`1` row).

Reading:

- The pair candidates are stable enough to justify a verifier, but not a fast
  shortcut. The prior attempt to allowlist `Y01...` crashed with
  `CellSpursKernel0` writing `0xffdead00`, so the missing semantics are still
  real.
- This is CPU/SPU reservation-loop/codegen work, not GPU migration, and it does
  not move the 200% gate.
- Classification: `parked` SPU/codegen verifier lead, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Add a verify-only PUTLLC16 pair checker before any fast mode. It should
  compare the full 128-byte reservation line, `raddr`, `rtime`, reservation
  event/notification behavior, and post-loop branch state for `Y01...` and
  `79w...`.
- Keep `allowed_pair_patterns` empty until that verifier survives moving field,
  menu/Options, and first-battle visuals.

## 2026-05-22 PUTLLC16 Pair Verify Run

Question:

- Can the two repeated PUTLLC16 pair candidates be shadow-checked on the clean
  moving route without enabling the unsafe fast shortcut?

Implementation:

- Added `RPCS3_ES_PUTLLC16_PAIR=verify` in the Windows lab build. It is exposed
  as `-EternalSonataPutllc16Pair Verify` in
  `tools/windows_rpcs3_lab.ps1` and
  `tools/eternal_sonata_speed_sprint.ps1`.
- `Verify` only emits the pair pattern for the two known hashes:
  `Y01tfnsGZ1qQrTV61LSta6n5KLw7` and
  `79w5SL0uvyoiJN6A3tK6iKKkqTYr`. `allowed_pair_patterns` stays empty for
  `Fast`.
- The verifier logs shadow assumptions (`raddr`, `rtime`, main reservation
  line, changed-slot mask, expected-slot mask) and then branches to the stock
  PUTLLC fallback. It does not perform the two-slot fast write.
- The summarizer now writes
  `eternal-sonata-putllc16-pair-verify-profile.csv` and parses
  `Eternal Sonata PUTLLC16 pair verify:` rows.

Build and parser verification:

- Windows Release build passed:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 6`.
- `git diff --check` passed for the touched upstream and repo tooling files
  with only LF-to-CRLF warnings.
- A synthetic parser row produced a valid pair-verify CSV.

Run:

- `debug-captures/windows-lab/20260522-010110-cpu4-putllc16-pair-verify-movingloop-windows/`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-putllc16-pair-verify-movingloop -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataPutllc16Pair Verify -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention was clean across five snapshots.
- The route reached field and movement screenshots:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- Fatal/crash/access-violation/Vulkan-validation scan had no real runtime
  failures. The only fatal match was the static config line
  `Show fatal error hints: false`.
- Visual caveat: the late screenshot showed black flower-tile sprites at the
  bottom-left edge that were not present in the prior profile late screenshot.
  Treat this run as visual-suspect until repeated or the verify fallback is made
  demonstrably transparent.

Result:

- GPU/DMA records: `0`; this was a reservation verifier, not a GPU/DMA scout.
- PUTLLC16 analyzer records: `42`.
- Pair candidates repeated the same two hashes as the profile run:
  `Y01...` at `0xb40` and `79w...` at `0x156c`.
- PUTLLC16 pair verify rows: `1741`.
- Peak grouped verifier counts: `63` hits, `63` in-range, `63` `raddr`
  matches, `63` `rtime` matches, `63` main-line matches, `4` changed hits,
  `61` no-extra-dirty hits, and `2` extra-dirty hits.
- The extra-dirty cases mean the two-slot shortcut is still not semantically
  safe. The verifier also showed runtime changed masks that can differ from the
  expected pair-slot mask, so the pair offset/dirty-slot mapping needs another
  pass before any fast path.

Reading:

- This is useful CPU/SPU reservation-loop evidence, but it is not a speed win
  and not GPU migration.
- The prior `Y01...` fast allowlist crash now has a plausible explanation:
  some live hits violate the two-slot dirty assumption.
- Classification: `parked` / visual-suspect verifier result. Keep default off,
  keep `Fast` unallowlisted, and do not port to Thor.

Next:

- Fix the verifier so the expected-slot mask is derived from the actual
  PUTLLC LS-line dirty slots, not only the currently decoded pair destinations.
- Add a post-fallback shadow result that records whether stock PUTLLC succeeded
  and whether `raddr`/event state changed as expected.
- Repeat moving field after that fix; only then consider menu/Options and
  first-battle verifier proof.

## 2026-05-22 PUTLLC16 Pair Mask Follow-Up

Question:

- Was the prior `last_changed_mask=0x18` / `last_expected_mask=0xc`
  discrepancy only a verifier logging bug, or evidence that the two-slot
  shortcut is still semantically unsafe?

Implementation:

- Extended the Windows `RPCS3_ES_PUTLLC16_PAIR=verify` logging with
  `decoded_mask_match`, `pattern_mask_match`, `last_decoded_mask`, and
  `last_pattern_mask`.
- First attempt packed the analyzer write mask into unused high bits of the
  pair pattern and passed it as an extra LLVM helper argument. That built, but
  the moving-field verifier run
  `debug-captures/windows-lab/20260522-012314-cpu4-putllc16-pair-patternmask-verify-movingloop-windows/`
  black-screened the game image while leaving the RPCS3 overlay visible.
- Matched control
  `debug-captures/windows-lab/20260522-013005-cpu4-putllc16-pair-off-control-movingloop-windows/`
  rendered the same moving-field route, so the high-bit/extra-helper-argument
  approach is classified `failed` and should not be reused.
- Safer rebuild removed the extra helper argument and derives the known pattern
  masks inside the title/image/PC-gated verifier: `0xb40 -> 0x18`,
  `0x156c -> 0x30`.

Build and parser verification:

- Windows Release build passed after the failed helper-argument attempt and
  again after the safer PC-mask verifier.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` now exports the decoded and
  pattern mask counters in `eternal-sonata-putllc16-pair-verify-profile.csv`
  and reports those sums even for pure PUTLLC16 analyzer runs with zero
  GPU/DMA records.

Run:

- `debug-captures/windows-lab/20260522-013829-cpu4-putllc16-pair-pcmask-verify-movingloop-windows/`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-putllc16-pair-pcmask-verify-movingloop -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataPutllc16Pair Verify -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 175 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention was clean across four snapshots.
- Screenshots reached field start and movement:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- Fatal/crash/access-violation/Vulkan-validation scan had no real runtime
  failures. The only fatal match was the static config line
  `Show fatal error hints: false`.
- Visual caveat: field start and movement rendered, but the late screenshot
  still showed bottom-left black flower-tile edge artifacts. Treat this as
  visual-suspect until a clean matched field route repeats.

Result:

- GPU/DMA records: `0`; this remains a reservation verifier, not a GPU/DMA
  scout.
- PUTLLC16 analyzer records: `42`.
- PUTLLC16 pair verify rows: `1471`.
- Peak grouped verifier counts: `42` hits, `42` in-range, `42` `raddr`
  matches, `41` `rtime` matches, `42` main-line matches, `4` changed hits,
  `40` no-extra-dirty hits, and `2` extra-dirty hits.
- Decoded-mask / pattern-mask matches: `40 / 40`.
- Representative last masks: `last_changed_mask=0x18`,
  `last_decoded_mask=0xc`, and `last_pattern_mask=0x18`.

Reading:

- The logging ambiguity is fixed: the runtime can now separate the decoded
  destination mask from the known analyzer pattern mask.
- The fast two-slot shortcut is still unsafe because `2` peak hits dirty bytes
  outside the expected pair mask, and one hit lost the `rtime` match.
- This is useful SPU reservation/codegen evidence, but it is not a speed win,
  not GPU migration, and not a 200% gate candidate.

Classification:

- `parked` / visual-suspect verifier evidence.
- Keep `Fast` unallowlisted and default off.

Next:

- Do not reuse the high-bit pattern payload or extra helper-argument approach.
- Add a post-fallback shadow result that records stock PUTLLC success/failure
  and event/raddr state without consuming guest-visible channel state.
- If the verifier ever reaches zero extra-dirty and clean field visuals, repeat
  menu/Options and first-battle proof before considering any fast shortcut.

## 2026-05-22 PUTLLC16 Pair Post-Fallback Probe

Question:

- After the verifier falls back to stock PUTLLC, does stock actually succeed and
  clear reservation state for the same pair hits, or are the unsafe cases
  ordinary stock failures?

Implementation:

- Added a verify-only post-fallback probe after `exec_mfc_cmd<false>` in the
  `putllc16_pair` LLVM path.
- The post probe reads non-consuming state only: `ch_atomic_stat.get_value()`,
  `ch_atomic_stat.get_count()`, `raddr`, and `ch_events.load().events`.
- Added counters/log fields:
  `post_hits`, `post_atomic_ready`, `post_success`, `post_failure`,
  `post_atomic_other`, `post_raddr_zero`, `post_raddr_same`,
  `post_lr_event_set`, `last_post_atomic`, `last_post_raddr`, and
  `last_post_events`.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` now exports those fields in
  `eternal-sonata-putllc16-pair-verify-profile.csv` and reports post stock
  success/failure in the summary.
- `Fast` remains unallowlisted. This is a shadow verifier only.

Build:

- Windows Release build passed:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 6`.

Run:

- `debug-captures/windows-lab/20260522-020059-cpu4-putllc16-pair-postprobe-verify-movingloop-windows/`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-putllc16-pair-postprobe-verify-movingloop -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataPutllc16Pair Verify -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 175 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention was clean across four snapshots.
- Screenshots reached field start and movement:
  `screenshot-0131s-start.png`, `screenshot-0141s-move1.png`,
  `screenshot-0150s-move2.png`, and `screenshot-0162s-late.png`.
- Fatal/crash/access-violation/Vulkan-validation scan had no real runtime
  failures. The only fatal match was the static config line
  `Show fatal error hints: false`.
- Visual caveat: the field rendered, but the late screenshot still has the
  bottom-left black flower-tile edge seen in this verifier route family. Treat
  this as visual-suspect, not promotion-clean.

Result:

- GPU/DMA records: `0`.
- PUTLLC16 analyzer records: `42`.
- PUTLLC16 pair verify rows: `1465`.
- Peak grouped verifier counts: `28` hits, `28` in-range, `28` `raddr`
  matches, `28` `rtime` matches, `28` main-line matches, `4` changed hits,
  `26` no-extra-dirty hits, and `2` extra-dirty hits.
- Decoded-mask / pattern-mask matches: `26 / 26`.
- Post stock counters: `28` post hits, `28` atomic-ready, `28` stock successes,
  `0` stock failures, `0` atomic-other, `28` post-raddr-zero, `0`
  post-raddr-same, and `17` LR-event-set.
- Representative last values: `last_changed_mask=0x18`,
  `last_decoded_mask=0xc`, `last_pattern_mask=0x18`,
  `last_post_atomic=0x0`, `last_post_raddr=0x0`, and
  `last_post_events=0x0`.

Reading:

- Stock PUTLLC is succeeding and clearing reservation state for every matched
  pair verifier hit in this run.
- The unsafe signal is therefore not stock failure; it is the attempted
  replacement's incomplete local-store dirty coverage. The pair shortcut still
  cannot be allowlisted while `extra_dirty` is nonzero.
- This remains CPU/SPU reservation/codegen evidence, not GPU migration, not a
  speed win, and not a 200% gate candidate.

Classification:

- `parked` / visual-suspect verifier evidence.

Next:

- Park the two-slot PUTLLC fast shortcut unless a future verifier can explain
  and cover the extra-dirty slots.
- A more promising SPU path is a reduced-loop/codegen/HLE recognizer around the
  surrounding reservation loop, or return to the RSX render-pass-local source
  read problem for GPU-residency work.

## 2026-05-22 SPU Reservation-Loop Pivot Gate

Question:

- After the RSX source-break prefill and small render-pass-local routes were
  rejected, what is the narrowest Windows-only SPU/codegen target that can still
  move meaningful CPU-bound work toward a safe fast path?

Evidence read:

- Re-read repo-local skills `codex-goal-loop`, `ps3-debug-knowledge`,
  `ps3-speed-proof-gate`, `ps3-rsx-experiment-gate`, and
  `thor-spu-codegen-hotpath`.
- Reused the latest moving-field kernel capsule run:
  `debug-captures/windows-lab/20260521-234607-cpu4-kernel-capsule-movingloop-profile-windows/`.
- Reused the latest PUTLLC16 pair post-fallback run:
  `debug-captures/windows-lab/20260522-020059-cpu4-putllc16-pair-postprobe-verify-movingloop-windows/`.
- Inspected local Windows source only:
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUCommonRecompiler.cpp`
  and
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp`.
- This slice did not launch gameplay, build, use Android, use ADB, or touch
  Thor.

Structured evidence:

- Kernel capsule by hot PC on the clean moving route:
  - `0x451c`: `862` rows, `1323.02 MB`, `16,990,133` wait reads,
    `15,622,685` AtomicStat reads, `1,367,448` TagStat reads, `0` RSX bytes,
    `0` GPU-batch candidates.
  - `0x25cc`: `730` rows, `1179.80 MB`, `323,628` wait reads,
    `38,714` AtomicStat reads, `284,914` TagStat reads, `0` RSX bytes,
    `0` GPU-batch candidates.
- Exact wait-PC peaks again point at reservation/atomic loops:
  `0xa74` had `113,348` AtomicStat reads, `0xd28` and `0x11e8` had
  `26,291` each, `0xad8` had `23,526`, and `0x344` / `0x664` had
  `19,602` each.
- The latest pair verifier still has no safe replacement:
  `1465` verify rows, official peak grouped hits `28`, `2` extra-dirty hits,
  decoded/pattern matches `26 / 26`, and post-stock PUTLLC success/failure
  `28 / 0`.

Static/code read:

- `SPUCommonRecompiler.cpp` already has the useful scaffolds:
  `atomic16_t` for GETLLAR/PUTLLC16 pattern analysis, `rchcnt_loop_t` for
  RDCH/RCHCNT loop detection, and `reduced_loop_t` for general reduced-loop
  detection.
- `SPULLVMRecompiler.cpp` emits optimized reduced-loop IR when the analyser
  attaches `inst_attr::reduced_loop`.
- The existing reduced-loop machinery is mainly arithmetic/control-flow
  oriented. It treats memory and channel reads as external origins or break
  conditions, so it does not currently collapse the hot reservation/channel loop
  as a whole.

Disasm read:

- `0xa74` / `0xad8` is the concrete first target, not a vague "SPU on GPU":
  it issues `GETLLAR`, reads `MFC_RdAtomicStat`, edits the reservation line at
  `0x2db0` / `0x2dc0`, issues `PUTLLC`, reads `MFC_RdAtomicStat` again, and
  branches back to `0xad8` on failure.
- `0x25cc` is downstream tag-wait helper work: it calls the MFC command helper,
  then writes `MFC_WrTagMask`, writes `MFC_WrTagUpdate`, and reads
  `MFC_RdTagStat`.
- `0x451c` is the dynamic MFC command issue loop: it writes `MFC_Cmd`, advances
  EAL/size state, and iterates chunk/list traffic.

Reading:

- Broad SPU-to-Vulkan compute is still parked. The current moving route has
  large hot SPU/MFC traffic, but `0 B` RSX-local traffic and `0` GPU-batch
  candidates, so a GPU mirror would probably add synchronization/readback before
  proving useful work belongs on the GPU.
- The next viable speed lane is a verify-first full reservation-loop recognizer,
  not the two-slot PUTLLC shortcut. It should title/image/PC-gate the
  `0xa74` / `0xad8` loop, log loop entry/exit counts, GETLLAR/PUTLLC success,
  AtomicStat failure loops, branch counts, dirty-slot coverage, raddr/rtime,
  event/notify state, and post-loop observable state while always falling back
  to stock execution.
- If that verifier proves stable, the first fast shape should be CPU-side
  codegen/HLE or reduced-loop specialization. A GPU path only becomes honest
  after the recognized loop exposes a batched output that avoids immediate
  CPU readback or is later proven RSX-consumed.

Classification:

- `analysis`, `spu-reservation-loop-next-gate`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Add a Windows-only profile/verify mode for the whole `0xa74` / `0xad8`
  reservation loop, preferably reusing the existing PUTLLC16 analyzer and
  reduced-loop metadata instead of introducing a separate broad heuristic.
- Keep `RPCS3_ES_PUTLLC16_PAIR=Fast` unallowlisted and default off.
- Do not port to Thor, run ADB, or call this GPU progress until Windows proves
  a clean fast mode with field, menu/Options, and first-battle visuals.

## 2026-05-22 SPU Reservation-Loop Summary Tool

Question:

- Can the existing Windows captures be reduced into a repeatable narrow target
  table so the next code slice does not re-read raw CSVs by hand?

Implementation:

- Added `tools/summarize_eternal_sonata_spu_reservation_loop.ps1`.
- The tool reads:
  - `eternal-sonata-kernel-capsule-profile.csv`;
  - `eternal-sonata-mfc-wait-pc-profile.csv`;
  - `eternal-sonata-putllc16-pair-verify-profile.csv`.
- It emits a Markdown summary with kernel bytes by hot PC, exact wait-PC peaks,
  PUTLLC16 pair verifier peaks, and a conservative next-decision label.

Run:

- Command:
  `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -KernelRunDir .\debug-captures\windows-lab\20260521-234607-cpu4-kernel-capsule-movingloop-profile-windows -PairRunDir .\debug-captures\windows-lab\20260522-020059-cpu4-putllc16-pair-postprobe-verify-movingloop-windows -Top 12`.
- Output:
  `debug-captures/windows-lab/20260522-020059-cpu4-putllc16-pair-postprobe-verify-movingloop-windows/eternal-sonata-spu-reservation-loop-summary.md`.
- This was Windows-only analysis. It did not launch gameplay, build, use
  Android, use ADB, or touch Thor.

Result:

- Kernel capsule rows: `1746`.
- MFC wait exact-PC rows: `90759`.
- PUTLLC16 pair verifier rows: `1465`.
- Total kernel bytes: `2502.81 MB`.
- Total RSX-local bytes: `0.00 MB`.
- Total GPU-batch candidate flags: `0`.
- Peak pair hits / extra-dirty / post-failure: `24 / 5 / 6`.
- Hot PC summary:
  - `0x451c`: `862` rows, `1323.02 MB`, `16,990,133` wait reads,
    `15,622,685` AtomicStat reads, `0` RSX bytes.
  - `0x25cc`: `730` rows, `1179.80 MB`, `323,628` wait reads,
    `284,914` TagStat reads, `0` RSX bytes.
- Exact wait-PC peaks again choose the reservation-loop front:
  `0xa74` at `113,348` AtomicStat reads and `0xad8` at `23,526`
  AtomicStat reads, both ending near `0xb44`.

Reading:

- The tool classifies the current evidence as `whole-loop-verify-first`.
- Broad SPU Vulkan compute stays parked because the summarized kernel capsules
  still show zero RSX-local bytes and zero GPU-batch candidates.
- The isolated two-slot PUTLLC16 pair shortcut stays unsafe because the summary
  still sees extra-dirty and post-failure evidence.

Classification:

- `analysis`, `tooling`, `spu-reservation-loop-summary`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Use this summary output as the preflight for the next C++ code slice: a
  profile/verify hook for the whole `0xa74` / `0xad8` reservation retry loop.

## 2026-05-22 Whole-Loop Verifier Hook Preflight

Question:

- What is the narrowest Windows-only hook point for a whole reservation-loop
  verifier, before changing any SPU reservation semantics or claiming GPU
  migration?

Evidence read:

- Re-read repo-local loop, debug-knowledge, speed-proof, and RSX experiment
  gate skills, plus the latest AGENTS and CPU/SPU ledger notes.
- Inspected local Windows source only:
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp`,
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUCommonRecompiler.cpp`,
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp`,
  and
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.h`.
- Reran the reservation-loop summary tool over the latest moving kernel-capsule
  and PUTLLC16 pair verifier captures.
- This was Windows-only source/tooling analysis. It did not launch gameplay,
  build, run Android, use ADB, or touch Thor.

Implementation:

- Extended `tools/summarize_eternal_sonata_spu_reservation_loop.ps1` with a
  `Whole-Loop Hook Preflight` section when the evidence classifies as
  `whole-loop-verify-first`.
- Fixed the new PowerShell Markdown output to use literal single-quoted strings
  for backtick-heavy lines, avoiding control-character output such as NUL or
  carriage-return escapes.

Run:

- Command:
  `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -KernelRunDir .\debug-captures\windows-lab\20260521-234607-cpu4-kernel-capsule-movingloop-profile-windows -PairRunDir .\debug-captures\windows-lab\20260522-020059-cpu4-putllc16-pair-postprobe-verify-movingloop-windows -Top 12`.
- Output:
  `debug-captures/windows-lab/20260522-020059-cpu4-putllc16-pair-postprobe-verify-movingloop-windows/eternal-sonata-spu-reservation-loop-summary.md`.

Result:

- The summary still reports `2502.81 MB` kernel bytes, `0.00 MB` RSX-local
  bytes, `0` GPU-batch candidate flags, and pair peak hits / extra-dirty /
  post-failure of `24 / 5 / 6`.
- Exact wait-PC evidence includes the reservation-loop front:
  `0xa74` has `113,348` AtomicStat reads, `0xad8` has `23,526`, and both end
  near `0xb44`.
- `SPULLVMRecompiler.cpp::get_rdch()` already splits fast channel reads from
  blocking fallback and can call a verifier for `RDCH(MFC_RdAtomicStat)` with
  the compiled `m_pos`.
- `SPUThread.cpp::get_ch_value(MFC_RdAtomicStat)` is the interpreter/blocking
  parity hook and already records MFC wait probes through the same title/image
  gate family.
- `SPULLVMRecompiler.cpp::WRCH(MFC_Cmd)` and
  `SPUThread.cpp::set_ch_value(MFC_Cmd)` are the secondary GETLLAR/PUTLLC
  command hooks if RDCH counters alone cannot reconstruct loop entry, retry,
  and exit.

Reading:

- The next C++ slice should add a default-off
  `RPCS3_ES_RESERVATION_LOOP=profile|verify` gate, title-gated to `BLUS30161`
  and SPU-image-gated to `0x958dfe208b686622`.
- First-pass counters should be loop entries, retry reads, GETLLAR command
  hits, PUTLLC command hits, AtomicStat success/failure/other values,
  `raddr`/`rtime` match, dirty-slot mask, LR event state, and post-loop
  observable state.
- Do not change PUTLLC semantics, reservation notification, or SPU-to-Vulkan
  execution in the first hook slice. This is a verifier plan, not a fast path.

Classification:

- `analysis`, `tooling`, `whole-loop-hook-preflight`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Add the Windows-only `RPCS3_ES_RESERVATION_LOOP=profile` C++ hook using RDCH
  first, then add WRCH command counters only if the RDCH trace cannot explain
  loop entry/retry/exit.

## 2026-05-22 Reservation-Loop Profile Hook

Question:

- Can the whole-loop verifier path be wired as a default-off Windows profile
  switch and proven to emit the exact `0xa74` / `0xad8` AtomicStat counters
  without changing reservation semantics?

Implementation:

- In local Windows `rpcs3-upstream`, added `RPCS3_ES_RESERVATION_LOOP=profile|verify`
  mode plumbing to:
  - `rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`, enabling the existing LLVM
    `RDCH(MFC_RdAtomicStat)` fast-read probe;
  - `rpcs3/Emu/Cell/SPUThread.cpp`, enabling interpreter/blocking parity for
    the existing MFC wait probe under the same title/image gate;
  - `rpcs3/Emu/Cell/lv2/sys_spu.cpp`, adding `reservation_mode=` to MFC wait
    and exact-PC log rows and allowing the new mode to summarize.
- Exposed the switch in Windows wrappers:
  `tools/windows_rpcs3_lab.ps1 -EternalSonataReservationLoop Profile|Verify`
  and
  `tools/eternal_sonata_speed_sprint.ps1 -EternalSonataReservationLoop Profile|Verify`.
- Updated `tools/summarize_eternal_sonata_gpu_probe.ps1` so MFC wait CSVs
  preserve the new `reservation_mode` column.
- No fast path was added. This hook only enables existing profile counters.

Build and parser verification:

- Windows Release build passed:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 6`.
- `git diff --check` passed for the touched C++ and PowerShell files, with only
  existing LF-to-CRLF warnings.
- PowerShell parser tokenization passed for the touched Windows wrapper and
  summarizer scripts.

Run:

- `debug-captures/windows-lab/20260522-172631-cpu4-reservation-loop-profile-field-windows/`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-profile-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Profile -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 155 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention summary: `clean` across `5` snapshots.
- Screenshots reached the correct Path to Tenuto field:
  `screenshots/screenshot-0118s.png` and `screenshots/screenshot-0133s.png`.
- Manual visual check of `screenshot-0133s.png`: field, character, overlay, and
  foliage rendered correctly; no obvious black-screen or route mismatch.
- Error scan found `0` access violations, `0` Vulkan validation hits, `0`
  validation errors, `0` unhandled exceptions, and `0` fatal PPU/SPU/RSX rows.

Result:

- GPU summary records: `1123`.
- MFC wait rows: `1255`.
- MFC wait exact-PC rows: `63363`.
- MFC wait total reads: `11,468,917`, all fast reads, `0` blocking reads.
- MFC wait AtomicStat / TagStat reads: `10,394,340 / 1,074,577`.
- Hot reservation front peaks:
  - `0xa74`: `108,103` reads, all AtomicStat, last PC `0xb44`;
  - `0xad8`: `19,193` reads, all AtomicStat, last PC `0xb44`;
  - `0xb44`: `6` reads in the exact-PC peak table.
- Combined exact-PC rows for `0xa74` / `0xad8` / `0xb44` summed
  `6,946,103` AtomicStat reads across cumulative log snapshots.
- The summary still shows `0 B` RSX-local traffic and offload fit
  `spu-kernel-hle=764`, `too-small=359`.

Reading:

- The profile hook is live and captures the same reservation-loop front without
  changing PUTLLC, notification, or reservation state.
- Because all observed wait reads were fast channel reads in this run, the next
  useful code slice is not a scheduler wait sleep; it is a loop/body verifier
  around the repeated AtomicStat/retry logic and surrounding GETLLAR/PUTLLC
  command sequence.
- This still does not prove a GPU offload. A GPU path remains honest only if a
  later verifier exposes batched output that avoids immediate CPU readback or is
  proven RSX-consumed.

Classification:

- `analysis`, `profile-hook`, `whole-loop-verifier-scaffold`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Add minimal GETLLAR/PUTLLC command counters under the same
  `RPCS3_ES_RESERVATION_LOOP=profile` gate so the RDCH exact-PC histogram can
  be tied to loop entry, retry, and exit counts before any fast-path proposal.

## 2026-05-22 Reservation-Loop Command Correlation Hook

Question:

- Can the reservation-loop profile mode tie the hot `RDCH(MFC_RdAtomicStat)`
  exact-PC counters to the surrounding GETLLAR and PUTLLC command PCs without
  changing reservation semantics?

Implementation:

- In local Windows `rpcs3-upstream`, added default-off command/atomic counters
  under `RPCS3_ES_RESERVATION_LOOP=profile`:
  - `rpcs3/Emu/Cell/SPUThread.h` now stores reservation-loop command totals,
    exact-PC command buckets, and atomic outcome counters;
  - `rpcs3/Emu/Cell/SPUThread.cpp` records GETLLAR/PUTLLC/PUTLLUC/PUTQLLUC
    command issue PCs and AtomicStat outcome updates when the title is
    `BLUS30161` and the SPU image is `0x958dfe208b686622`;
  - `rpcs3/Emu/Cell/lv2/sys_spu.cpp` logs
    `Eternal Sonata reservation loop cmd probe:` and exact-PC rows at SPU
    group join.
- Updated `tools/summarize_eternal_sonata_gpu_probe.ps1` to parse/export:
  - `eternal-sonata-reservation-loop-cmd-profile.csv`;
  - `eternal-sonata-reservation-loop-cmd-pc-profile.csv`;
  - a `Reservation Loop Commands` summary section.
- No fast path was added. No PUTLLC semantics, reservation notification, or
  SPU-to-GPU execution changed.

Build and parser verification:

- Windows Release build passed:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 6`.
- `git diff --check` passed for the touched C++ and PowerShell files, with only
  LF-to-CRLF warnings.
- PowerShell parser tokenization passed for the updated GPU probe summarizer.

Runs:

- First run:
  `debug-captures/windows-lab/20260522-182308-cpu4-reservation-loop-cmd-profile-field-windows/`.
  This proved the new atomic outcome logging path was live, but the command
  issue counters were zero because the first helper reused the generic
  `get_es_mfc_base_cmd()` mask, which strips bits that are part of the atomic
  command values (`GETLLAR=0xd0`, `PUTLLC=0xb4`). This run is superseded.
- Corrected run:
  `debug-captures/windows-lab/20260522-183215-cpu4-reservation-loop-cmd-profile2-field-windows/`.
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-cmd-profile2-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Profile -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 155 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention summary: `clean` across `5` snapshots.
- Error scan found `0` access violations, `0` real fatal rows, `0` Vulkan
  validation hits, `0` validation errors, `0` unhandled exceptions, `0`
  SIGSEGV rows, and `0` SIGBUS rows.
- Screenshots:
  - `screenshots/screenshot-0117s.png` rendered a night/close camera scene with
    character, overlay, sky, and geometry visible.
  - `screenshots/screenshot-0133s.png` was a dark transition-like frame.
- Because these screenshots are not the accepted Path to Tenuto field visual,
  this run is not a visual proof run and cannot be used for speed-gate credit.

Result:

- GPU summary records: `1165`.
- MFC dynamic/list/wait/exact-PC rows:
  `1165 / 703 / 1260 / 64454`.
- Reservation loop command rows:
  `1259` aggregate rows and `34191` exact-PC rows.
- Total observed DMA bytes: `1777.17 MB`.
- RSX-local traffic records: `0`.
- Offload fit mix: `spu-kernel-hle=800`, `too-small=365`.
- Peak reservation command totals:
  - command hits: `120,319`;
  - GETLLAR / PUTLLC commands: `69,613 / 50,706`;
  - Atomic updates: `120,393`;
  - GETLLAR success / PUTLLC success / PUTLLC failure:
    `69,687 / 50,384 / 322`.
- Exact-PC correlation peaks:
  - `0xa70`: `61,474` GETLLAR commands and `63,642` GETLLAR-success atomic
    updates;
  - `0xa74`: `61,474` AtomicStat reads in the paired wait histogram;
  - `0xad4`: `16,373` PUTLLC commands, `16,259` successes, `114` failures;
  - `0xad8`: `16,373` AtomicStat reads in the paired wait histogram;
  - secondary pairs include `0x340 -> 0x344`, `0x660 -> 0x664`,
    `0xb64 -> 0xb68`, `0xc24 -> 0xc28`, and `0x3930 -> 0x3934`.

Reading:

- The hook now proves the hot retry front is a CPU/SPU reservation loop, not
  hidden GPU-resident RSX work.
- The strongest whole-loop candidate is the verified command/read pair:
  `GETLLAR at 0xa70` -> `AtomicStat read at 0xa74`, followed by
  `PUTLLC at 0xad4` -> `AtomicStat read at 0xad8`.
- This is good verifier scaffolding for a future HLE/codegen replacement, but
  it still does not justify a one-dispatch-per-reservation GPU path. The loop
  has immediate CPU-visible atomic status and no observed RSX-local consumer.

Classification:

- `analysis`, `profile-hook`, `not-comparable-visual`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Add a verify-only whole-loop recognizer that groups the correlated
  `0xa70/0xa74/0xad4/0xad8` sequence into loop attempts, retry counts, and
  exit outcomes, then compare stock observable state after the loop. Keep the
  switch default-off and keep fast mode unavailable until the verifier survives
  clean field/menu/battle visuals.

## 2026-05-22 Whole-Loop Recognizer Preflight Summary

Question:

- Can the existing captures be summarized into a concrete whole-loop verifier
  target before adding another C++ hook?

Implementation:

- Extended `tools/summarize_eternal_sonata_spu_reservation_loop.ps1` with a
  `-CommandRunDir` input.
- The tool now reads:
  - `eternal-sonata-reservation-loop-cmd-profile.csv`;
  - `eternal-sonata-reservation-loop-cmd-pc-profile.csv`;
  - command-run `eternal-sonata-mfc-wait-pc-profile.csv`.
- It pairs command PCs with the next exact wait/read PC (`cmd_pc + 4`) for the
  same SPU group and worker, then reports command/read and atomic/read deltas.
- The calculation uses fields from the same peak row instead of mixing
  independent maxima across cumulative snapshots.

Command:

- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -KernelRunDir .\debug-captures\windows-lab\20260521-234607-cpu4-kernel-capsule-movingloop-profile-windows -PairRunDir .\debug-captures\windows-lab\20260522-020059-cpu4-putllc16-pair-postprobe-verify-movingloop-windows -CommandRunDir .\debug-captures\windows-lab\20260522-183215-cpu4-reservation-loop-cmd-profile2-field-windows -Top 12`

Output:

- `debug-captures/windows-lab/20260522-183215-cpu4-reservation-loop-cmd-profile2-field-windows/eternal-sonata-spu-reservation-loop-summary.md`.

Verification:

- PowerShell parser check passed for the updated summarizer.
- The summary regenerated from actual Windows captures without starting a new
  emulator run.
- No Android, ADB, or Thor work was run.
- This step reused the prior command-correlation run. That run's screenshots
  were already classified as night/transition rather than accepted Path to
  Tenuto field, so this remains non-visual tooling evidence.

Result:

- Decision: `whole-loop-recognizer-preflight`.
- Kernel capsule rows: `1746`; total kernel bytes: `2502.81 MB`.
- RSX-local bytes / GPU-batch flags: `0.00 MB / 0`.
- PUTLLC16 pair peak hits / extra-dirty / post-failure:
  `24 / 5 / 6`, so the isolated pair shortcut stays unsafe.
- Reservation command rows / exact-PC rows / command-run wait-PC rows:
  `1259 / 34191 / 64454`.
- Peak command snapshot:
  `116214` hits, `67180` GETLLAR, `49034` PUTLLC, `116275` atomic updates,
  `176` PUTLLC failures.
- Primary command/read pairs:
  - `0xa70 -> 0xa74`: `61474` GETLLAR commands and `61474` AtomicStat reads,
    command/read delta `0`, atomic/read delta `2168`;
  - `0xad4 -> 0xad8`: `16373` PUTLLC commands and `16373` AtomicStat reads,
    command/read delta `0`, atomic/read delta `0`, `114` PUTLLC failures.
- Secondary coherent command/read pairs include:
  `0x340 -> 0x344`, `0x660 -> 0x664`, `0xb64 -> 0xb68`,
  `0xc24 -> 0xc28`, and `0x3930 -> 0x3934`.

Reading:

- The strongest verifier target is now concrete: a PC-gated recognizer should
  watch `0xa70` GETLLAR, `0xa74` AtomicStat, `0xad4` PUTLLC, and `0xad8`
  AtomicStat as one loop front.
- This is useful CPU/SPU/HLE/codegen scaffolding, not proof that the loop
  belongs on Vulkan compute. The loop still exposes immediate CPU-visible
  AtomicStat state and the captures still show zero RSX-local consumer traffic.
- The `0xa70` atomic/read delta means the verifier should track command issue,
  status update, and RDCH read as separate events instead of assuming a single
  one-to-one counter everywhere.

Classification:

- `analysis`, `tooling`, `whole-loop-recognizer-preflight`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Add a verify-only recognizer that groups the four primary PCs into loop
  attempts, retry counts, success/failure exits, `raddr`/`rtime`, dirty-slot
  state, and post-loop observable state.
- Keep `RPCS3_ES_RESERVATION_LOOP=verify` default-off and do not change
  PUTLLC semantics or dispatch anything to GPU until field/menu/battle visuals
  prove the verifier is correct.

## 2026-05-22 Whole-Loop Verify Hook Smoke

Question:

- Can the `0xa70` GETLLAR / `0xa74` AtomicStat / `0xad4` PUTLLC /
  `0xad8` AtomicStat front be grouped into stock loop attempts and exit
  outcomes without changing reservation semantics?

Implementation:

- Added a default-off `RPCS3_ES_RESERVATION_LOOP=verify` path in local Windows
  `rpcs3-upstream`.
- `rpcs3/Emu/Cell/SPUThread.h` now stores whole-loop verify counters:
  attempts, GETLLAR commands/successes, PUTLLC commands, completed exits,
  success/failure/unexpected outcomes, `raddr`/`rtime`/main-line matches,
  dirty-slot masks, and post-loop `raddr`/LR-event observations.
- `rpcs3/Emu/Cell/SPUThread.cpp` records the verify state machine from the
  existing command and atomic hooks. It is title-gated to `BLUS30161`, image
  gated through the existing Eternal Sonata probe path, and falls through to
  stock MFC behavior.
- `rpcs3/Emu/Cell/lv2/sys_spu.cpp` logs
  `Eternal Sonata reservation loop verify probe:` at SPU group join.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` now exports
  `eternal-sonata-reservation-loop-verify-profile.csv` and adds a
  `Reservation Loop Verify` summary section.
- No fast path was added. No PUTLLC semantics, reservation notification, or
  SPU-to-GPU/Vulkan dispatch changed.

Build and parser verification:

- Windows Release build passed:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 6`.
- PowerShell parser tokenization passed for the updated GPU probe summarizer.
- A synthetic verify row produced the expected verify CSV fields:
  attempts `10`, completed `8`, success `7`, failure `1`, unexpected `0`,
  last command PC `0xad4`, changed mask `0x18`.
- `git diff --check` passed for the touched repo-local files, with only
  LF-to-CRLF warnings.

Run:

- `debug-captures/windows-lab/20260522-200806-cpu4-reservation-loop-verify-preflight-field-windows/`.
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-verify-preflight-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 155 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention summary: `clean` across `5` snapshots.
- Error scan found `0` access violations, `0` real fatal rows, `0`
  Vulkan-error rows, `0` validation rows, `0` unhandled exceptions, `0`
  SIGSEGV rows, and `0` SIGBUS rows.
- Screenshots:
  - `screenshots/screenshot-0117s.png` reached the accepted green field view
    with player character, environment, overlay, and geometry visible.
  - `screenshots/screenshot-0133s.png` stayed in the same accepted field view
    with movement/particle effects visible.
- The run ended by the scripted `155s` wall-time stop, not by a crash.
- `rpcs3` was not left running and no `RPCS3_ES*` process environment variable
  remained in this shell.

Result:

- MFC wait exact-PC peak reads: `240,776`.
- Peak AtomicStat wait PCs:
  - `0xa74`: `116,252` reads;
  - `0xad8`: `24,384` reads.
- Reservation command peak:
  - command hits: `187,379`;
  - GETLLAR / PUTLLC commands: `144,139 / 43,240`;
  - atomic updates: `191,635`;
  - GETLLAR success / PUTLLC success / PUTLLC failure:
    `148,395 / 27,274 / 15,966`.
- Verify totals:
  - attempts / completed: `116,256 / 24,388`;
  - success / failure / unexpected: `9,022 / 15,366 / 4,256`;
  - dirty multi-slot observations: `0`.
- Peak verify row:
  - attempts `116,252`, completed `24,384`, success `9,018`,
    failure `15,366`, unexpected `4,256`;
  - `raddr` matches `24,384`, `rtime` matches `18,477`,
    main-line matches `23,544`;
  - dirty `0/24384/0`;
  - post `raddr_zero/same = 24384/0`;
  - LR event set `24,365`.

Reading:

- The verifier hook is live and groups real stock loop attempts/exits on the
  accepted field route.
- The good sign is that dirty multi-slot observations are `0` and `raddr`
  matches every completed PUTLLC attempt in the peak row.
- The caveat is important: `4,256` unexpected transitions remain, and the
  last atomic PC often appears as the post-update PC (`0xb40`, sometimes other
  follow-on PCs) rather than the PUTLLC issue PC. The next slice should bind
  the PUTLLC issue event to the later AtomicStat update/read before any
  replacement logic is considered.
- This is still CPU/SPU reservation-loop HLE/codegen evidence. It is not GPU
  migration credit, not a speed win, and not a 200% gate candidate.

Classification:

- `analysis`, `verify-hook-smoke`, `field-visual-smoke`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Refine the verifier state machine so command issue PCs, atomic update PCs,
  and RDCH read PCs are recorded as separate linked events.
- Repeat verify-only field/menu/battle visuals after the unexpected-transition
  count is explained. Keep fast mode and GPU dispatch unavailable.

## 2026-05-22 Reservation-Loop Linked Update Verifier

Question:

- Can the verifier explain the post-update `last_atomic_pc` values by linking
  atomic-status updates back to the last primary GETLLAR/PUTLLC command issue,
  without changing reservation semantics?

Implementation:

- Extended the default-off `RPCS3_ES_RESERVATION_LOOP=verify` counters in local
  Windows `rpcs3-upstream` to split command issue, atomic-status update, and
  attempted guest RDCH read buckets.
- The update-state path now links GETLLAR updates to the last `0xa70`
  command and PUTLLC success/failure updates to the last `0xad4` command,
  instead of requiring the current SPU PC to still be the issue PC.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` now parses the new optional
  verify fields, exports them to the verify CSV, and reports linked/unlinked
  updates plus read buckets in the `Reservation Loop Verify` section.
- No fast path was added. No PUTLLC semantics, reservation notification,
  scheduler behavior, or SPU-to-GPU/Vulkan dispatch changed.

Build and parser verification:

- Windows Release build passed after parking the failed titleless read gate:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 6`.
- `git diff --check` passed for the touched C++ files and the summarizer, with
  only LF-to-CRLF warnings.
- PowerShell parser tokenization passed for the updated GPU probe summarizer.

Clean run:

- `debug-captures/windows-lab/20260522-205341-cpu4-reservation-loop-directread-verify-field-windows/`.
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-directread-verify-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -MaxSeconds 155`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention summary: `clean` across `5` snapshots.
- Error scan found no access-violation, real fatal, Vulkan-error, validation,
  unhandled-exception, SIGSEGV, or SIGBUS hits.
- Screenshots `screenshot-0117s.png` and `screenshot-0133s.png` both show the
  accepted Path to Tenuto green field with player character, geometry, overlay,
  and movement/particle state visible.
- The run ended by the scripted `155s` wall-time stop, not by a crash.
- `rpcs3` was not left running and no `RPCS3_ES*` process environment variable
  remained in this shell.

Result:

- Verify totals:
  - attempts / completed: `87012 / 40477`;
  - success / failure / unexpected: `29935 / 10542 / 55374`;
  - linked / unlinked atomic updates: `106466 / 55374`;
  - AtomicStat read bucket GETLLAR / PUTLLC / unexpected: `0 / 0 / 0`;
  - dirty multi-slot observations: `0`;
  - last PCs: `0xad4->0xb40->0x0`.
- Peak verify row:
  - `raddr` matches `19454`, `rtime` matches `15679`,
    main-line matches `18927`;
  - dirty `0/19454/0`;
  - post `raddr_zero/same = 40477/0`;
  - LR event set `40355`.
- Existing MFC exact-PC evidence remains the authoritative guest RDCH read
  source for this slice:
  - peak exact-PC `0xa74` reads: `87012`;
  - peak TagStat / AtomicStat reads: `18328 / 186731`;
  - total MFC wait TagStat / AtomicStat reads: `1059893 / 9330099`.

Failed follow-up:

- `debug-captures/windows-lab/20260522-210255-cpu4-reservation-loop-titlelessread-verify-field-windows/`
  widened the RDCH read counter to mode-only/titleless scope.
- That run is invalid for proof: RPCS3 froze with
  `VM: Access violation reading location 0x4 (unmapped memory)` followed by
  `SYS: Emulation has been frozen!`; screenshots are not valid field proof.
- Its verify counters still showed a zero AtomicStat read bucket
  (`0 / 0 / 0 / 0`), so the wider read hook did not solve the RDCH linkage
  problem before it added crash risk.
- The titleless condition was reverted back behind
  `is_es_reservation_loop_verify_enabled()` and the Release rebuild passed.

Reading:

- Linked update accounting is useful: it explains why `last_atomic_pc` can be a
  post-update PC such as `0xb40` while still belonging to a prior `0xad4`
  PUTLLC issue.
- The high unlinked count is still the blocker. This verifier is not
  replacement-safe and should not feed a fast path yet.
- The in-hook RDCH read bucket remained zero even though the MFC exact-PC table
  clearly sees the `0xa74` AtomicStat reads. The next RDCH slice should move to
  the SPU recompiler/interpreter RDCH lowering or do a post-process join in the
  summarizer; do not keep widening broad MFC wait side effects.
- This is CPU/SPU verifier/HLE/codegen evidence only. It is not GPU migration
  credit, not a speed win, and not a 200% gate candidate.

Classification:

- `analysis`, `verify-hook-refinement`, `field-visual-smoke`,
  `failed-titleless-read-gate`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Trace `RDCH(MFC_RdAtomicStat)` at the recompiler/interpreter lowering point,
  or teach the summarizer to join command/update rows with existing exact-PC
  MFC wait rows.
- Keep fast mode and GPU dispatch unavailable until command, update, and RDCH
  read stages line up through field/menu/battle visuals.

## 2026-05-22 Reservation-Loop RDCH Join Summary

Question:

- Can the existing exact-PC MFC wait histogram recover RDCH/read-stage evidence
  for the verify rows without widening live MFC hooks again?

Implementation:

- `tools/summarize_eternal_sonata_gpu_probe.ps1` now builds a post-process
  `Reservation Loop RDCH Join` from peak reservation-loop verify rows and the
  existing exact-PC MFC wait table.
- The join is keyed by title, group, SPU, entry, and SPU image signature, then
  pairs `0xa70 -> 0xa74` GETLLAR/RDCH and `0xad4 -> 0xad8` PUTLLC/RDCH.
- The summarizer now emits
  `eternal-sonata-reservation-loop-rdch-join-profile.csv`.
- This is log analysis only. No emulator runtime behavior, PUTLLC semantics,
  reservation notification, scheduler behavior, or GPU dispatch changed.

Verification:

- PowerShell parser tokenization passed for the updated summarizer.
- `git diff --check` passed for the summarizer, with only LF-to-CRLF warnings.
- Re-ran the summarizer on the clean field capture
  `debug-captures/windows-lab/20260522-205341-cpu4-reservation-loop-directread-verify-field-windows/`.
- The regenerated summary has no NUL bytes and includes one RDCH join row plus
  the new RDCH join CSV.
- No Android, ADB, Thor, or new RPCS3 gameplay run was used for this slice.

Result on the clean field capture:

- Exact-PC AtomicStat reads GETLLAR / PUTLLC: `87012 / 19454`.
- In-hook AtomicStat reads / exact-PC AtomicStat reads: `0 / 106466`.
- Exact-PC reads minus in-hook reads: `106466`.
- GETLLAR read coverage: `87012 / 87012 = 100.000%`.
- PUTLLC read coverage: `19454 / 40477 = 48.062%`.
- Linked / unlinked updates: `106466 / 55374`.
- Joined unexpected verifier transitions: `55374`.
- Last PCs remain `0xad4->0xb40->0x0`.

Reading:

- The post-process join is useful and safer than more broad read hooks: it
  recovers read-stage evidence from already logged exact-PC counters.
- `exact_atomic_reads == update_linked` on this peak row, which means the
  exact-PC table is coherent enough to explain the linked update population.
- GETLLAR entry is no longer the mystery: exact `0xa74` reads cover every
  verify attempt.
- The unresolved blocker is the PUTLLC/read/post-branch side: only about half
  of completed exits have matching peak `0xad8` reads, while unlinked and
  unexpected transitions remain high.
- Next work should target the `0xad8` RDCH/post-branch path or state-machine
  accounting around PUTLLC exits, not another broad MFC wait side-effect hook.
- This is CPU/SPU verifier/HLE/codegen evidence only. It is not GPU migration
  credit, not a speed win, and not a 200% gate candidate.

Classification:

- `analysis`, `verify-tooling`, `rdch-join`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Use the RDCH join table to focus the next verifier pass on `0xad8` and the
  post-branch PCs (`0xb40` / `0xca4`) that consume the PUTLLC status.
- Keep all fast/HLE/GPU replacement paths unavailable until this can survive
  field/menu/battle visuals with explained unexpected transitions.

## 2026-05-22 PUTLLC Exit Disasm Scout

Question:

- What raw SPU instruction windows sit behind the verifier's `0xad8` /
  post-branch ambiguity, and what should the next safe verifier actually
  target?

Inputs:

- Clean field capture:
  `debug-captures/windows-lab/20260522-205341-cpu4-reservation-loop-directread-verify-field-windows/`.
- Existing artifacts only:
  - `eternal-sonata-mfc-wait-pc-profile.csv`;
  - `eternal-sonata-reservation-loop-cmd-pc-profile.csv`;
  - SPU disassembly sidecars under `spu-images/`.
- This was Windows-only offline analysis. No Android, ADB, Thor, new RPCS3
  gameplay run, or runtime code change was used.

Findings:

- The current verifier hook labels (`0xa70`, `0xa74`, `0xad4`, `0xad8`) are
  probe/recompiler PCs, while the raw disassembly window shows the hot SPU
  instruction lane as:
  - `0xaec`: `wrch MFC_Cmd` GETLLAR;
  - `0xaf0`: `rdch MFC_RdAtomicStat`;
  - `0xb40`: `wrch MFC_Cmd` PUTLLC;
  - `0xb44`: `rdch MFC_RdAtomicStat`;
  - `0xb48`: `brnz r17,0xad8` retry;
  - `0xb78`: `brz r16,0xcc4` post-success guard.
- A second nearby reservation lane exists:
  - `0xc6c`: `wrch MFC_Cmd` GETLLAR;
  - `0xc70`: `rdch MFC_RdAtomicStat`;
  - `0xca4`: `wrch MFC_Cmd` PUTLLC;
  - `0xca8`: `rdch MFC_RdAtomicStat`;
  - `0xcac`: `brnz r56,0xc58` retry;
  - success exits through `0xcb0..0xcc0 -> 0x29b0`.
- The old unsafe PUTLLC16 pair candidate at `0xb40` is the raw PUTLLC command
  in the first lane, not a standalone safe replacement point. The later
  `cntb/ceq/brz` guard after `0xb44` is part of the success path and explains
  why two-slot shortcutting stayed unsafe.
- Exact-PC counters still show the verifier pair as `0xa74` / `0xad8` at the
  hook/probe level. Raw disassembly addresses such as `0xaf0`, `0xb44`,
  `0xc70`, and `0xca8` appear in sidecars but should not be mixed with hook
  labels as if they were the same coordinate space.

Reading:

- The `0xad8` gap is not simply "missing RDCH logging." It is a coordinate and
  control-flow issue: hook PCs identify the recognizer lane, while the actual
  SPU success/failure branch happens at raw `0xb44`/`0xb48` and the following
  guard at `0xb78`.
- The next verifier should name both coordinates explicitly: hook PC for
  counter joins, raw SPU PC for instruction-window reasoning.
- A replacement candidate must prove the whole exit micro-control flow:
  GETLLAR, LS edits, PUTLLC, RDCH status, retry branch, post-success guard,
  and final exit state. A local PUTLLC or two-slot write shortcut is not safe.
- This remains CPU/SPU verifier/HLE/codegen groundwork. It is not GPU
  migration credit, not a speed win, and not a 200% gate candidate.

Classification:

- `analysis`, `disasm-scout`, `verify-tooling`, not `gpu-migration-credit`,
  not `windows-micro-win`, not a 200% gate candidate.

Next:

- Extend the verify/logging model to record both hook PCs and raw instruction
  PCs for PUTLLC exit lanes, especially `0xb40/0xb44/0xb48/0xb78` and
  `0xca4/0xca8/0xcac`.
- Keep fast/HLE/GPU replacement disabled until the full exit path is verified
  on field, menu/Options, and first battle.

## 2026-05-22 Reservation-Loop Raw Lane Table

Question:

- Can the GPU probe summarizer turn the SPU disassembly sidecars into a
  machine-readable raw-lane map, so the next verifier does not mix exact-PC
  counter/focus PCs with raw SPU instruction PCs?

Change:

- `tools/summarize_eternal_sonata_gpu_probe.ps1` now emits
  `eternal-sonata-reservation-loop-raw-lane-profile.csv`.
- The new table parses `spu-images/*.disasm.txt`, extracts complete raw
  `GETLLAR -> AtomicStat -> PUTLLC -> AtomicStat -> retry` lanes, merges
  nearby sidecar windows by title/entry/image/group/SPU, and joins the raw
  PCs with existing reservation command/read exact-PC counter peaks.
- The table deliberately names the generalized post-retry field
  `raw_next_branch_*`, not `post_guard`, because only some lanes have a clear
  post-success guard like `0xb78`.

Verification:

- PowerShell parser tokenization passed.
- `git diff --check` passed for the summarizer, with only LF-to-CRLF
  warnings.
- Re-ran the summarizer on clean Windows capture
  `debug-captures/windows-lab/20260522-205341-cpu4-reservation-loop-directread-verify-field-windows/`.
- The regenerated summary has no NUL bytes.
- The source capture remains the accepted clean field capture with screen 1,
  clean host checks, and screenshots `screenshot-0117s.png` /
  `screenshot-0133s.png`.
- No Android, ADB, Thor, new RPCS3 gameplay, fast path, HLE replacement, or
  GPU dispatch was used.

Result:

- Raw SPU reservation lanes found: `8`.
- Raw PUTLLC command/read counter peaks across lanes: `12009 / 12009`.
- Highest raw-lane PUTLLC evidence is now `0xbe0/0xbe4 -> 0xc24/0xc28`,
  retry `0xc2c -> 0xbcc`, next branch `0xcac -> 0xc58`, with PUTLLC
  command/read peaks `11936 / 11936`. Its GETLLAR side is still attributed
  asymmetrically (`0xbe0` raw GETLLAR but high exact-PC GETLLAR focus at
  `0xb64/0xb68`), which reinforces that the next live verifier must log
  focus PC and raw instruction PC together.
- The old unsafe `0xb40` lane is now represented cleanly as
  `0xaec/0xaf0 -> 0xb40/0xb44`, retry `0xb48 -> 0xad8`, next branch
  `0xb78 -> 0xcc4`, with direct raw command/read peaks `7 / 7`.
- The nearby `0xca4` lane is represented as
  `0xc6c/0xc70 -> 0xca4/0xca8`, retry `0xcac -> 0xc58`, next branch
  `0xcc0 -> 0x29b0`, with direct raw command/read peaks `4 / 4`.

Reading:

- The next verifier/HLE recognizer should not be hardcoded only around the
  old `0xb40` PUTLLC16 shortcut. It should cover the hotter `0xc24/0xc28`
  lane and keep the `0xb40/0xb44` plus `0xca4/0xca8` lanes as explicit
  secondary exits.
- The table is useful verifier targeting because it separates raw SPU
  instruction PCs from exact-PC counter/focus PCs. It does not move work to
  the GPU by itself and does not prove speed.
- A future CPU-to-GPU or HLE path still needs a verify-first whole-loop model:
  GETLLAR, AtomicStat read, local-store edits, PUTLLC, AtomicStat read, retry
  branch, next-branch/post-success state, reservation clear/event state, and
  field/menu/battle visuals.

Classification:

- `analysis`, `verify-tooling`, `raw-lane-table`, not `gpu-migration-credit`,
  not `windows-micro-win`, not a 200% gate candidate.

Next:

- Extend the live reservation-loop verifier to log both the exact-PC
  counter/focus PC and the raw SPU instruction PC for at least
  `0xb64/0xb68 -> 0xc24/0xc28`, `0xaec/0xaf0 -> 0xb40/0xb44`, and
  `0xc6c/0xc70 -> 0xca4/0xca8`.
- Keep all fast/HLE/GPU replacement paths disabled until these lanes are
  explained and survive field, menu/Options, and first battle.

## 2026-05-22 Reservation-Loop Raw-PC Verify Smoke

Question:

- Can the live Windows reservation-loop verifier log lane identity and raw SPU
  instruction PCs separately from the exact-PC/focus counters, so the next
  whole-loop recognizer does not mix coordinate spaces?

Change:

- Local Windows `rpcs3-upstream` now tracks reservation-loop lanes under
  `RPCS3_ES_RESERVATION_LOOP=verify`.
- The verifier records `lane`, `last_raw_cmd_pc`, `last_raw_atomic_pc`,
  `last_raw_read_pc`, `last_retry_pc`, and `last_next_branch_pc` in addition
  to the existing command/update/read focus PCs.
- The first lane table covers:
  - lane 1: `0xaec/0xaf0 -> 0xb40/0xb44`, retry `0xb48`, next `0xb78`;
  - lane 2: `0xbe0/0xbe4 -> 0xc24/0xc28`, retry `0xc2c`, next `0xcac`;
  - lane 3: `0xc6c/0xc70 -> 0xca4/0xca8`, retry `0xcac`, next `0xcc0`.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` parses and exports the new
  fields in `eternal-sonata-reservation-loop-verify-profile.csv`, carries them
  through the RDCH join rows, and displays them in the reservation-loop verify
  summary table.
- No PUTLLC semantics, fast path, HLE path, SPU-to-GPU dispatch, Android,
  ADB, or Thor work was used.

Verification:

- `cmake --build build-msvc --config Release --target rpcs3 -- /m` passed in
  `rpcs3-upstream`; only the existing `libcmt.lib` defaultlib warning was
  observed near link.
- PowerShell parser tokenization passed for
  `tools/summarize_eternal_sonata_gpu_probe.ps1`.
- `git diff --check` passed for the touched runtime/parser/note files, with
  only LF-to-CRLF warnings.
- Windows smoke command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-rawpc-verify-field-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -MaxSeconds 150 -ScreenshotEverySeconds 16 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 3
```

- Run directory:
  `debug-captures/windows-lab/20260522-225524-cpu4-reservation-loop-rawpc-verify-field-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks from prelaunch through postrun.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  fatal exceptions, assertion failures, and aborts found no real runtime hit;
  only the normal config line `Show fatal error hints: false` matched the word
  `fatal`.
- The regenerated GPU-probe summary has no NUL bytes.
- Visual check: `screenshot-0136s.png` and `screenshot-0142s.png` were still
  on `Now Loading...`; this is not accepted Path to Tenuto field proof.

Result:

- Reservation loop verify records: `1258`.
- RDCH join records: `1`.
- Raw-lane records: `8`.
- Total observed DMA bytes: `1420.68 MB`.
- RSX-local traffic records: `0`.
- Offload fit mix: `spu-kernel-hle=827`, `too-small=347`.
- Verify totals: attempts/completed `74588 / 25715`,
  success/failure/unexpected `16753 / 8962 / 20695`.
- Atomic updates linked/unlinked: `94606 / 20695`.
- Live verifier lane grouping exported only lanes `1` and `3`:
  - lane `1`: max attempts/completed `74585 / 25711`, last raw PCs
    `0xb40 -> 0xb40 -> 0x0`, retry/next `0xb48 -> 0xb78`;
  - lane `3`: max attempts/completed `53559 / 18544`, last raw PCs
    `0xca4 -> 0xca4 -> 0x0`, retry/next `0xcac -> 0xcc0`.
- The raw-lane table in the same run still finds the hottest raw PUTLLC lane
  as `0xbe0/0xbe4 -> 0xc24/0xc28`, retry `0xc2c -> 0xbcc`, next branch
  `0xcac -> 0xc58`, with command/read peaks `5565 / 5565`.
- Follow-up CSV check confirms lane 2 evidence exists in the exact-PC side
  tables: `eternal-sonata-reservation-loop-cmd-pc-profile.csv` has paired
  `0xb64` GETLLAR and `0xc24` PUTLLC rows at `5565` hits, and
  `eternal-sonata-mfc-wait-pc-profile.csv` has paired `0xb68` and `0xc28`
  AtomicStat rows at `5565` reads. `eternal-sonata-reservation-loop-verify-profile.csv`
  still groups only lane `1` and lane `3`, so the next fix is live verifier
  state attribution/logging for lane 2, not another raw-lane discovery pass.

Reading:

- The new lane/raw-PC fields work and are now parseable from real Windows
  captures.
- This smoke did not reach the accepted field visual, so it cannot be used as
  speed evidence or correctness proof for a fast path.
- Lane 2/`0xc24` remains the important gap: it is hottest in the raw-lane table
  but absent from the live verifier grouping. That likely means the verifier
  attribution still keys on the wrong focus/raw coordinate for that lane.
- This is still CPU/SPU verifier and eventual HLE/codegen groundwork. It is
  not GPU migration credit, not a Windows micro-win, and not a 200% gate
  candidate.

Classification:

- `analysis`, `verify-tooling`, `live-raw-pc-log-smoke`,
  `not-comparable-visual`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Either rerun this exact verifier with a longer field route to recover
  accepted field screenshots, or first fix the lane 2 attribution so
  `0xc24/0xc28` appears in live verify rows.
- Do not add a fast/HLE/GPU replacement until lanes 1/2/3 are explained and the
  verifier survives field, menu/Options, and first battle.

## 2026-05-22 Reservation-Loop Lane Join Tooling

Question:

- Can the summarizer preserve the lane 2 evidence that exists in exact-PC
  command/read counters even when the live verifier aggregate row last reports
  only lane 1 or lane 3?

Change:

- `tools/summarize_eternal_sonata_gpu_probe.ps1` now writes
  `eternal-sonata-reservation-loop-lane-join-profile.csv`.
- The new join uses the known lane map, command exact-PC rows, AtomicStat
  exact-PC rows, raw disassembly lanes, and live verify rows. It is a
  post-process targeting table only; it does not change RPCS3 runtime behavior.
- No Android, ADB, Thor, gameplay rerun, fast path, HLE path, or GPU dispatch
  was used.

Verification:

- PowerShell parser tokenization passed.
- `git diff --check` passed for the summarizer with only LF-to-CRLF warnings.
- Re-running the summarizer on
  `debug-captures/windows-lab/20260522-225524-cpu4-reservation-loop-rawpc-verify-field-windows-windows/`
  completed successfully with a longer timeout after an initial 120s timeout on
  the large `62 MB` log.
- The regenerated summary has no NUL bytes.
- The source run remains the previous clean-host screen-1 run, but its checked
  screenshots `screenshot-0136s.png` and `screenshot-0142s.png` were still
  `Now Loading...`, so this remains not comparable as field visual proof.

Result:

- Lane-join rows: `3`.
- Known lane exact-PC PUTLLC command/read peaks: `20017 / 20017`.
- Lanes with exact-PC evidence but no live verify lane rows: `1`.
- Lane 1:
  `0xa70:69018 / 0xa74:69018 -> 0xad4:14448 / 0xad8:14448`,
  raw `4 / 4`, live verify rows `448`, class `live-verify-seen`.
- Lane 2:
  `0xb64:5565 / 0xb68:5565 -> 0xc24:5565 / 0xc28:5565`,
  raw `5565 / 5565`, live verify rows `0`, class
  `exact-pc-seen-live-verify-missing`.
- Lane 3:
  `0xc6c:4 / 0xc70:4 -> 0xca4:4 / 0xca8:4`,
  raw `4 / 4`, live verify rows `810`, class `live-verify-seen`.

Reading:

- Lane 2 was not missing from the actual MFC command/read evidence. It was
  missing from the live verify aggregate because that row preserves only the
  current/last lane state instead of per-lane totals.
- The next runtime step should add per-lane live aggregation or lane-specific
  rows before designing any whole-loop fast path.
- This still points at CPU/SPU whole-loop verifier/HLE/codegen groundwork, not
  RSX-local GPU work. A future CPU-to-GPU attempt must first prove this loop's
  full control flow and state semantics.

Classification:

- `analysis`, `verify-tooling`, `lane-join`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Add per-lane live verifier aggregate counters/rows in Windows
  `rpcs3-upstream` so lane 2 reports its own attempts/completions and
  success/failure/unexpected counts.
- Then rerun long enough to reach accepted field visuals before any fast/HLE/GPU
  replacement exists.

## 2026-05-23 Reservation-Loop Per-Lane Live Verifier

Question:

- Can the live Windows reservation-loop verifier retain per-lane counters so the
  hot lane 2 `0xb64/0xb68 -> 0xc24/0xc28` evidence survives beyond the last
  aggregate lane snapshot?

Change:

- Local Windows `rpcs3-upstream` now keeps per-lane live verifier counters under
  `RPCS3_ES_RESERVATION_LOOP=verify` and emits
  `Eternal Sonata reservation loop verify lane:` rows at SPU group join.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` parses both
  `verify probe` and `verify lane` rows, records `scope`, prefers lane-scoped
  rows when present, and exports `scope` to
  `eternal-sonata-reservation-loop-verify-profile.csv`.
- No PUTLLC semantics, reservation notification, HLE path, SPU-to-GPU dispatch,
  Android, ADB, or Thor work was used.

Verification:

- `cmake --build build-msvc --config Release --target rpcs3 -- /m` passed in
  `rpcs3-upstream`; only the existing `libcmt.lib` defaultlib warning was
  observed near link.
- Windows smoke command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-perlane-verify-field-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -MaxSeconds 150 -ScreenshotEverySeconds 16 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 3
```

- Run directory:
  `debug-captures/windows-lab/20260523-001429-cpu4-reservation-loop-perlane-verify-field-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks from prelaunch through postrun.
- Visual check: `screenshots/screenshot-0142s.png` reached the accepted Path to
  Tenuto field with overlay around the high-20s FPS band. This is a visual
  smoke only, not a speed comparison.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  fatal exceptions, assertion failures, and aborts found no real runtime hit;
  only the normal config line `Show fatal error hints: false` matched the word
  `fatal`.
- The regenerated GPU-probe summary has no NUL bytes.

Result:

- Summary totals: `1511.92 MB` observed DMA, `0` RSX-local traffic records,
  `0` indirect RSX overlap records, offload fit `spu-kernel-hle=750` /
  `too-small=389`.
- Reservation verify totals: attempts/completed `184481 / 62767`,
  success/failure/unexpected `40689 / 22078 / 49183`,
  linked/unlinked atomic updates `233104 / 49183`.
- Live read buckets are still empty:
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads `0 / 0 / 0 / 0`.
  The exact-PC AtomicStat table remains the read-stage source until RDCH
  lowering is instrumented directly.
- Lane-join rows: `3`, with all known lanes classified `live-verify-seen`.
- Lane 1:
  `0xa70:169075 / 0xa74:169075 -> 0xad4:34625 / 0xad8:34625`,
  raw `7 / 7`, verify rows `1794`, verify attempts/completed
  `182300 / 61605`, success/failure/unexpected `39780 / 21825 / 48042`,
  retry/next `0xb48 -> 0xb78`.
- Lane 2:
  `0xb64:13223 / 0xb68:13223 -> 0xc24:13223 / 0xc28:13223`,
  raw `13223 / 13223`, verify rows `1168`, verify attempts/completed
  `13223 / 26966`, success/failure/unexpected `26544 / 422 / 27486`,
  retry/next `0xc2c -> 0xcac`.
- Lane 3:
  `0xc6c:22 / 0xc70:22 -> 0xca4:22 / 0xca8:22`,
  raw `22 / 22`, verify rows `1360`, verify attempts/completed
  `78495 / 25147`, success/failure/unexpected `15568 / 9579 / 19150`,
  retry/next `0xcac -> 0xcc0`.

Reading:

- The previous lane 2 gap is fixed at the live verifier/logging layer. The hot
  `0xc24/0xc28` lane now has per-lane attempts, completions, outcomes, raw PCs,
  and retry/next-branch evidence from a real field-reaching Windows run.
- This still points at CPU/SPU whole-loop verifier, reduced-loop/codegen, or
  title-gated HLE. It is not a GPU migration by itself and it does not prove a
  speed improvement.
- The next real verifier gap is RDCH read-stage ownership. The current MFC
  exact-PC table sees the reads, but live verifier read buckets stay at zero, so
  the next hook should instrument `SPULLVMRecompiler.cpp::get_rdch()` /
  interpreter RDCH lowering or keep the exact-PC join as the authoritative
  read-stage table.

Classification:

- `analysis`, `verify-tooling`, `per-lane-live-verifier`, `field-visual-smoke`,
  not `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate
  candidate.

Next:

- Add a narrow RDCH-lowering verifier or whole-loop state table that ties
  command issue, atomic update, guest read, retry branch, next branch, raddr,
  rtime, LR event, and local-store dirty masks for lanes 1/2/3.
- Do not add fast/HLE/GPU replacement until the whole-loop model survives field,
  menu/Options, and first battle.

## 2026-05-23 Reservation-Loop Fast RDCH Live Verifier

Question:

- Can the live verifier observe LLVM fast `RDCH(MFC_RdAtomicStat)` reads, not
  just command issue and atomic-status updates, so lanes 1/2/3 become full
  command -> update -> guest-read state-machine evidence?

Change:

- Local Windows `rpcs3-upstream` now exposes a narrow
  `spu_thread::record_es_reservation_loop_verify_atomic_read(...)` wrapper and
  calls it from the LLVM fast `RDCH` probe when `ch == MFC_RdAtomicStat`.
- This reuses the same verifier path already used by blocking/interpreter
  channel reads. It does not change SPU channel semantics, PUTLLC behavior,
  reservation notification, HLE, fast replacement, GPU dispatch, Android, ADB,
  or Thor state.

Verification:

- `cmake --build build-msvc --config Release --target rpcs3 -- /m` passed in
  `rpcs3-upstream`; only the existing `libcmt.lib` defaultlib warning was
  observed near link.
- Windows smoke command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-rdchfast-verify-field-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -MaxSeconds 150 -ScreenshotEverySeconds 16 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 3
```

- Run directory:
  `debug-captures/windows-lab/20260523-004018-cpu4-reservation-loop-rdchfast-verify-field-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks from prelaunch through postrun.
- Visual check: `screenshots/screenshot-0142s.png` reached the accepted Path to
  Tenuto field with clean-looking field rendering. The overlay showed about the
  low-40s FPS band, but this is not a matched speed comparison.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  fatal exceptions, assertion failures, and aborts found no real runtime hit;
  only the normal config line `Show fatal error hints: false` matched the word
  `fatal`.
- The regenerated GPU-probe summary has no NUL bytes.

Result:

- Summary totals: `1579.88 MB` observed DMA, `0` RSX-local traffic records,
  `0` indirect RSX overlap records, offload fit `spu-kernel-hle=742` /
  `too-small=387`.
- Reservation verify totals: attempts/completed `85183 / 23985`,
  success/failure/unexpected `15088 / 8897 / 3930`,
  linked/unlinked atomic updates `109168 / 3930`.
- Live read buckets are now populated:
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `109168 / 85183 / 23985 / 0`.
- Lane 1:
  `0xa70:77636 / 0xa74:77636 -> 0xad4:16438 / 0xad8:16438`,
  verify rows `1237`, attempts/completed `77637 / 16439`,
  reads GETLLAR/PUTLLC/unexpected `77637 / 16439 / 0`,
  success/failure/unexpected `7542 / 8897 / 3930`, retry/next
  `0xb48 -> 0xb78`.
- Lane 2:
  `0xb64:7541 / 0xb68:7541 -> 0xc24:7542 / 0xc28:7542`,
  raw `7542 / 7542`, verify rows `1153`, attempts/completed
  `7542 / 7542`, reads GETLLAR/PUTLLC/unexpected `7542 / 7542 / 0`,
  success/failure/unexpected `7542 / 0 / 0`, retry/next `0xc2c -> 0xcac`.
- Lane 3:
  `0xc6c:1 / 0xc70:1 -> 0xca4:1 / 0xca8:1`, verify rows `635`,
  attempts/completed `1 / 1`, reads GETLLAR/PUTLLC/unexpected `1 / 1 / 0`,
  success/failure/unexpected `1 / 0 / 0`, retry/next `0xcac -> 0xcc0`.

Reading:

- The RDCH blind spot is closed for the LLVM fast path. Lane 2 is now a clean
  end-to-end verifier candidate in this field smoke: command issue, atomic
  update, guest reads, raw PCs, and retry/next metadata are all visible.
- Lane 1 still has failures/unexpected transitions, which likely means the
  future replacement must model retry and post-success guard behavior instead
  of treating the lane as a simple PUTLLC16 shortcut.
- This is still CPU/SPU verifier and whole-loop/HLE/codegen groundwork. It does
  not move work to the GPU and does not prove speed.

Classification:

- `analysis`, `verify-tooling`, `rdchfast-live-verifier`,
  `field-visual-smoke`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

Next:

- Build a verify-only whole-loop state table for lanes 1/2/3 that records
  retry branch taken/not-taken and next-branch/post-success state alongside the
  existing command/update/read counters.
- Keep all fast/HLE/GPU replacement paths disabled until that state table
  survives field, menu/Options, and first battle.

## 2026-05-23 Reservation-Loop Branch-State Verifier

Question:

- Can the Windows-only live verifier record retry and next-branch outcomes for
  the known reservation-loop lanes without changing PUTLLC, reservation, HLE,
  GPU, Android, ADB, or Thor behavior?

Change:

- Local Windows `rpcs3-upstream` now records verify-only branch counters for
  `BRZ`, `BRNZ`, and unconditional `BR` at the current lane branch PCs:
  `0xb48`, `0xb78`, `0xc2c`, `0xcac`, and `0xcc0`.
- The verifier logs aggregate and per-lane
  `retry_branches/taken/fallthrough`, `next_branches/taken/fallthrough`, and
  last branch PC/target/taken fields.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` parses those fields and adds
  branch R/N columns to the reservation lane join.

Verification:

- `cmake --build build-msvc --config Release --target rpcs3 -- /m` passed in
  `rpcs3-upstream`; only the existing `libcmt.lib` warning was observed.
- Windows smoke command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-branchstate-verify-field-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -MaxSeconds 150 -ScreenshotEverySeconds 16 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 3
```

- Run directory:
  `debug-captures/windows-lab/20260523-011702-cpu4-reservation-loop-branchstate-verify-field-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks from prelaunch through postrun.
- Visual check: `screenshots/screenshot-0136s.png` and
  `screenshots/screenshot-0142s.png` reached the accepted Path to Tenuto field.
  The overlay was around the high-30s/low-40s FPS band, but this is not a
  matched speed comparison.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failures, assertions, unhandled exceptions, aborts, and fatal
  errors found no real runtime hit; only the normal config line
  `Show fatal error hints: false` matched the word `fatal`.
- The regenerated GPU-probe summary has no NUL bytes.

Result:

- Summary totals: `1,713,219,984 B` observed DMA, `0` RSX-local traffic
  records, offload fit `spu-kernel-hle=796` / `too-small=317`.
- Reservation verify peak totals: attempts/completed
  `143754 / 41456`, success/failure/unexpected `24151 / 17305 / 6136`,
  and AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `185210 / 143754 / 41456 / 0`.
- Lane 1:
  attempts/completed/success/failure/unexpected
  `129299 / 27324 / 10062 / 17262 / 6124`, branch R/N
  `1/0/1 / 1/1/0`, retry/next `0xb48 -> 0xb78`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `13910 / 13910 / 13910 / 0 / 0`, branch R/N
  `13910/13910/0 / 0/0/0`, retry/next `0xc2c -> 0xcac`.
- Lane 3:
  attempts/completed/success/failure/unexpected `2 / 2 / 1 / 1 / 0`,
  branch R/N `2/1/1 / 1/1/0`, retry/next `0xcac -> 0xcc0`.

Reading:

- Lane 2 is now the cleanest whole-loop verifier candidate: command issue,
  atomic update, guest RDCH reads, branch retry behavior, and field visuals all
  line up in this Windows smoke.
- Lane 1 is still unsafe/noisy. It has many failures and unexpected transitions,
  and the current branch hook does not explain the hot failure count through the
  raw `0xb48` branch counter. The dumped SPU windows still show `0xb48 brnz
  r17,0xad8` and `0xb78 brz r16,0xcc4`, so the gap is attribution/execution
  state, not missing disassembly.
- This still points at a verify-first lane-2-only HLE/reduced-loop/codegen
  candidate or a lane-1 attribution fix. It does not move work to GPU and it
  does not prove speed.

Classification:

- `analysis`, `verify-tooling`, `branch-state-verifier`,
  `field-visual-smoke`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

Next:

- Prefer a narrow lane-2-only verify/HLE sketch or add focused-lane branch
  attribution for lane 1 before any broader whole-loop fast path.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Reservation-Loop Branch-State Menu Smoke

Question:

- Does the branch-state verifier stay stable through the Windows title
  menu/Options visual route before any lane-2-only fast/HLE experiment?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-reservation-loop-branchstate-verify-menu-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -MaxSeconds 170 -ScreenshotEverySeconds 16 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 4
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-013528-cpu4-reservation-loop-branchstate-verify-menu-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks from prelaunch through postrun.
- Visual check: `screenshots/screenshot-0095s.png`,
  `screenshots/screenshot-0101s.png`, and `screenshots/screenshot-0158s.png`
  show the Eternal Sonata title menu with `OPTIONS` visible/selected.
  `screenshots/screenshot-0126s.png` is an attract/transition visual, so this
  is a menu smoke only, not field or first-battle proof.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failures, assertions, unhandled exceptions, aborts, and fatal
  errors found no real runtime hit; only the normal config line
  `Show fatal error hints: false` matched the word `fatal`.
- The regenerated GPU-probe summary has no NUL bytes.

Result:

- Summary totals: `1,791,459,488 B` observed DMA, `0` RSX-local traffic
  records, offload fit `spu-kernel-hle=802` / `too-small=375`.
- Reservation verify peak totals: attempts/completed
  `250938 / 67374`, success/failure/unexpected `35841 / 31533 / 10917`,
  and AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `382157 / 250938 / 67374 / 0`.
- Lane 1:
  attempts/completed/success/failure/unexpected
  `233018 / 49454 / 17921 / 31533 / 10917`, branch R/N
  `2/1/1 / 1/1/0`, retry/next `0xb48 -> 0xb78`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `17920 / 17920 / 17920 / 0 / 0`, branch R/N
  `17920/17920/0 / 0/0/0`, retry/next `0xc2c -> 0xcac`.
- Lane 3:
  attempts/completed/success/failure/unexpected `19 / 19 / 1 / 18 / 0`,
  branch R/N `19/18/1 / 1/1/0`, retry/next `0xcac -> 0xcc0`.

Reading:

- Lane 2 stayed exact through the title-menu smoke, matching the field result:
  every observed lane-2 attempt completed successfully, no unexpected lane-2
  reads were logged, and every retry branch was taken.
- Lane 1 and lane 3 are still noisy and should not be replaced broadly. Lane 1
  carries the large failure/unexpected count; lane 3 had 18 failures in this
  route.
- This remains verifier/HLE groundwork only. It does not move work to GPU, does
  not prove a speedup, and does not count toward the 200% moving-gameplay gate.

Classification:

- `analysis`, `verify-tooling`, `branch-state-verifier`,
  `menu-visual-smoke`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

Next:

- Before any default-off lane-2 fast/HLE experiment, run either a first-battle
  branch-state verifier smoke or a lane-2-only verify/HLE dry-run that leaves
  lanes 1 and 3 untouched.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Reservation-Loop Branch-State Battle-Route Attempt

Question:

- Does the branch-state verifier survive the first-battle Windows route, giving
  the missing battle visual checkpoint before any lane-2-only fast/HLE dry-run?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-reservation-loop-branchstate-verify-battle-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -MaxSeconds 360 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 180 -ScreenshotMaxCount 8
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-020532-cpu4-reservation-loop-branchstate-verify-battle-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks.
- Visual check: `screenshots/screenshot-0118s.png` is a clean moving-field
  image, not a first-battle image. Later screenshots at roughly `169s`, `231s`,
  and `291s` were skipped because the game window was not found.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failures, assertions, unhandled exceptions, aborts, and fatal
  errors found no real runtime hit. The log still contains ordinary RPCS3/game
  boot noise such as the frame-limit enum warning, `CELL_ESRCH`, save-data
  callback failures, and the normal config line `Show fatal error hints: false`.
- The regenerated GPU-probe summary has no NUL bytes.

Result:

- Summary totals: `1,022.55 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=500` / `too-small=376`.
- Reservation verify peak totals: attempts/completed
  `115168 / 31293`, success/failure/unexpected `17461 / 13832 / 5395`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `146461 / 115168 / 31293 / 0`, and dirty multi-slot observations `3`.
- Lane 1:
  attempts/completed/success/failure/unexpected
  `106431 / 22556 / 8729 / 13827 / 5395`, branch R/N
  `1/0/1 / 1/1/0`, retry/next `0xb48 -> 0xb78`.
- Lane 2:
  attempts/completed/success/failure/unexpected `8728 / 8728 / 8728 / 0 / 0`,
  branch R/N `8728/8728/0 / 0/0/0`, dirty `0/8725/3`, retry/next
  `0xc2c -> 0xcac`.
- Lane 3:
  attempts/completed/success/failure/unexpected `6 / 6 / 1 / 5 / 0`,
  branch R/N `6/5/1 / 1/1/0`, retry/next `0xcac -> 0xcc0`.

Reading:

- The route did not prove first-battle visual correctness. It only gave another
  field visual plus verifier counters, so it cannot complete the field/menu/
  battle safety ladder.
- Lane 2 remains the cleanest branch-state candidate by success/failure/
  unexpected counters, but the repeated dirty multi-slot observations mean the
  next lane-2-only fast/HLE dry-run must validate or model dirty masks. Do not
  reduce lane 2 to the old simple two-slot PUTLLC shortcut.
- Lane 1 and lane 3 remain unsafe/noisy.
- This still does not move work to GPU and does not prove speed.

Classification:

- `analysis`, `verify-tooling`, `not-comparable-visual`,
  `battle-route-miss`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

Next:

- Fix the first-battle route or screenshot/window capture before calling the
  branch-state verifier battle-clean.
- After field, menu/Options, and first battle are all visually proven, the next
  default-off implementation step is a lane-2-only verify/HLE dry-run that
  leaves lanes 1 and 3 on stock behavior and records dirty-mask mismatches.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Reservation-Loop Field-Hold Route Isolate

Question:

- Was the previous first-battle verifier miss caused by the screenshot/window
  capture layer, or by the post-field battle movement macro?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-branchstate-fieldhold-windowcheck-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:45000;shot:100;wait:45000;shot:100" -MaxSeconds 230 -ScreenshotEverySeconds 30 -ScreenshotStartSeconds 115 -ScreenshotMaxCount 5
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-023630-cpu4-reservation-loop-branchstate-fieldhold-windowcheck-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks. RPCS3 stayed alive until the lab stopped PID
  `4960` after `230s` total wall time.
- Visual check: `screenshots/screenshot-0117s.png`,
  `screenshots/screenshot-0163s.png`, `screenshots/screenshot-0208s.png`,
  `screenshots/screenshot-0209s.png`, `screenshots/screenshot-0212s.png`,
  and `screenshots/screenshot-0215s.png` all remain on the Path to Tenuto field
  with clean-looking rendering.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failures, assertions, unhandled exceptions, aborts, and fatal
  errors found no real runtime hit. The log still contains ordinary RPCS3/game
  boot noise such as the frame-limit enum warning, `CELL_ESRCH`, save-data
  callback failures, and the normal config line `Show fatal error hints: false`.
- The regenerated GPU-probe summary has no NUL bytes.

Result:

- Summary totals: `2,961.60 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=1343` / `too-small=451`.
- Reservation verify peak totals: attempts/completed
  `109441 / 35502`, success/failure/unexpected `23923 / 11579 / 4470`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `144943 / 109441 / 35502 / 0`, and dirty multi-slot observations `0`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `12145 / 12145 / 12145 / 0 / 0`, branch R/N
  `12145/12145/0 / 0/0/0`, dirty `0/12145/0`, retry/next
  `0xc2c -> 0xcac`.

Reading:

- The screenshot/window-capture layer is not the likely cause of the previous
  battle miss. The same verifier plus the same field load held a live game
  window and produced late screenshots through `215s`.
- The previous `battle-route-miss` is therefore most likely in the post-field
  movement/confirm route or the timing used before that movement.
- Lane 2 again looks like the safest future HLE target in a stable field-hold
  route, and this run had zero dirty multi-slot observations for that lane.
- This remains route/tooling evidence. It does not move work to GPU, does not
  prove speed, and does not satisfy first-battle proof.

Tooling Change:

- `tools/eternal_sonata_speed_sprint.ps1` now keeps a separate `$loadBattle`
  sequence for `-Scene battle`, using the older Windows route that previously
  reached the active first-battle UI, instead of reusing the shorter field
  loader before the left/down-left movement.

Classification:

- `analysis`, `route-tooling`, `field-hold-windowcheck`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Run the patched Windows battle route with `-EternalSonataReservationLoop Verify`
  and require screenshots of the tutorial prompt or active first-battle UI
  before calling branch-state verifier coverage battle-clean.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Patched Reservation-Loop Battle Route Miss

Question:

- Does restoring the older Windows battle load/skip sequence make the
  branch-state verifier reach first battle again?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-reservation-loop-branchstate-patched-battle-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -MaxSeconds 360 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 14
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-030522-cpu4-reservation-loop-branchstate-patched-battle-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/postrun host checks. Exit code was
  `exited`; no `rpcs3` process remained after the run.
- Visual check: the only captured screenshot,
  `screenshots/screenshot-0131s.png`, is still the Path to Tenuto field with
  an enemy visible, not the tutorial prompt or active first-battle UI.
  Screenshots at roughly `182s`, `244s`, and `304s` were skipped because the
  game window was not found.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failures, assertions, unhandled exceptions, aborts, and fatal
  errors found no real runtime hit. The scan only matched ordinary config text
  and `_sys_ppu_thread_exit` aborted warnings from the game/RPCS3.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,322.58 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=608` / `too-small=375`.
- Reservation verify peak totals: attempts/completed
  `95135 / 24885`, success/failure/unexpected `13018 / 11867 / 4010`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `120020 / 95135 / 24885 / 0`, and dirty multi-slot observations `1`.
- Lane 2:
  attempts/completed/success/failure/unexpected `7015 / 7015 / 7015 / 0 / 0`,
  branch R/N `7015/7014/1 / 1/0/1`, dirty `0/7014/1`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `1005`, class
  `live-verify-seen`.

Reading:

- The restored `-Scene battle` load/skip sequence still did not produce a
  first-battle visual. It only proved another clean field visual before the
  window disappeared, so this is not comparable to the accepted first-battle
  route from earlier RSX proofs.
- The battle miss is now most likely in the post-field movement leg or timing,
  not in the field loader or screenshot layer.
- Lane 2 remains success-clean, but the one dirty multi-slot observation plus
  one retry fallthrough and one next-branch record means it is not safe to move
  lane 2 into a fast/HLE/GPU replacement from this route.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `analysis`, `route-tooling`, `patched-battle-route-miss`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Do not run another blind full battle proof yet.
- Isolate the post-field movement leg: field loader plus left-only movement and
  screenshot, then field loader plus left/down-left movement and screenshot.
- Also compare the same movement route with `-EternalSonataReservationLoop Off`
  versus `Verify` to check whether the verifier perturbs route timing before
  any lane-2 fast/HLE dry-run.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Reservation-Loop Left-Only Movement Isolate

Question:

- Is the route loss caused by the first left analog movement, or only by the
  later left+down diagonal/confirm leg?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-route-leftonly-verify-isolate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;ls_left:2600;wait:12000;shot:100;wait:45000;shot:100;wait:25000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 105 -ScreenshotMaxCount 8
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-033549-cpu4-reservation-loop-route-leftonly-verify-isolate-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/postrun host checks. Exit code was
  `exited`; no `rpcs3` process remained after the run.
- Visual check: the only captured screenshot,
  `screenshots/screenshot-0117s.png`, is clean Path to Tenuto field before the
  left movement. Screenshots after `ls_left:2600`, at roughly `132s`, `177s`,
  and `203s`, were skipped because the game window was not found.
- Error scan for access violations, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failures, assertions, unhandled exceptions, aborts, and fatal
  errors found no real runtime hit. The scan only matched ordinary config text
  and `_sys_ppu_thread_exit` aborted warnings from the game/RPCS3.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,031.71 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=523` / `too-small=349`.
- Reservation verify peak totals: attempts/completed
  `78574 / 21299`, success/failure/unexpected `11384 / 9915 / 3363`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `99873 / 78574 / 21299 / 0`, and dirty multi-slot observations `1`.
- Lane 2:
  attempts/completed/success/failure/unexpected `6737 / 6737 / 6737 / 0 / 0`,
  branch R/N `6737/6737/0 / 0/0/0`, dirty `0/6736/1`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `897`, class `live-verify-seen`.

Reading:

- The window loss reproduces after the first left-only movement, before the
  left+down diagonal or battle-confirm leg can run. This narrows the route
  failure to movement timing/control state, not the diagonal segment alone.
- The stable field-hold route from `20260523-023630...` proves the screenshot
  layer can keep capturing this scene for more than `200s` when movement is not
  applied. The left movement is therefore the current route variable to isolate.
- Lane 2 remains success-clean in this route, but the missing post-movement
  visual plus one dirty multi-slot observation means no lane-2 fast/HLE/GPU
  replacement should start yet.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `analysis`, `route-tooling`, `leftonly-window-loss`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Compare the same field route with no movement at the same shot timings, then
  try shorter/stepped left pulses such as `ls_left:400;wait:600;ls_left:400`
  before reintroducing left+down movement.
- If shorter movement still loses the window, run the same movement isolate
  with `-EternalSonataReservationLoop Off` to check whether verifier logging
  perturbs input timing.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Reservation-Loop Stepped-Left Movement Isolate

Question:

- Can shorter left analog pulses keep the field route alive after the long
  `ls_left:2600` hold lost the window?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-route-stepleft-verify-isolate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;ls_left:400;wait:600;ls_left:400;wait:600;ls_left:400;wait:12000;shot:100;wait:45000;shot:100;wait:25000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 105 -ScreenshotMaxCount 8
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-040555-cpu4-reservation-loop-route-stepleft-verify-isolate-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks across prelaunch/postlaunch/postrun plus samples
  at about `204s` and `210s`. The lab stopped PID `3832` after the `215s` wall
  limit; no `rpcs3` process remained after the run.
- Visual check: `screenshots/screenshot-0117s.png` is clean Path to Tenuto
  field before movement. `screenshots/screenshot-0132s.png` and later
  screenshots are capturable but show RPCS3's
  `The PS3 application has likely crashed` overlay with corrupted/transition
  visuals, not correct field or battle.
- Error scan found a real fatal runtime hit:
  `VM: Access violation reading location 0x40 (unmapped memory)` at
  `0:02:01.199312`. The scan also matched ordinary config text and normal
  `_sys_ppu_thread_exit` aborted warnings.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,063.90 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=514` / `too-small=370`.
- Reservation verify peak totals: attempts/completed
  `80323 / 29609`, success/failure/unexpected `21081 / 8528 / 2876`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `109932 / 80323 / 29609 / 0`, and dirty multi-slot observations `0`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `16381 / 16381 / 16381 / 0 / 0`, branch R/N
  `16381/16380/1 / 1/0/1`, dirty `0/16381/0`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `910`, class
  `live-verify-seen`.

Reading:

- Shorter left pulses keep the window capturable, unlike the long left hold,
  but they drive the route into a real guest/runtime crash. This is not a
  usable battle-route repair.
- Lane 2 remains success-clean by PUTLLC verifier counters, but the fatal
  access violation, corrupted visuals, and retry/next branch anomaly mean this
  route cannot authorize any lane-2 fast/HLE/GPU replacement.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `failed`, `route-tooling`, `stepleft-crash`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Rerun this exact stepped movement with `-EternalSonataReservationLoop Off`.
  If it still crashes, the route/input timing is the culprit. If it survives,
  the verifier is perturbing the route and lane-2 HLE work must wait for a
  lower-impact verifier or a battle route that is clean under Verify.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Stepped-Left Movement With Verifier Off

Question:

- Does the stepped-left route still crash when
  `-EternalSonataReservationLoop Off` removes the live verifier?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-route-stepleft-off-isolate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Off -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;ls_left:400;wait:600;ls_left:400;wait:600;ls_left:400;wait:12000;shot:100;wait:45000;shot:100;wait:25000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 105 -ScreenshotMaxCount 8
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-043546-cpu4-reservation-loop-route-stepleft-off-isolate-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean host checks across prelaunch/postlaunch/postrun plus samples
  at about `204s` and `210s`. The lab stopped PID `15964` after the `215s`
  wall limit; no `rpcs3` process remained after the run.
- Visual check: `screenshots/screenshot-0117s.png` is already a blue/star
  transition, not the accepted Path to Tenuto field. `screenshot-0132s.png`
  and later screenshots remain in that blue/star transition with only the
  performance overlay visible, not correct field or battle.
- Error scan found a real fatal runtime hit:
  `VM: Access violation reading location 0x14 (unmapped memory)` at
  `0:02:03.080835`; `rpcs3.stderr.txt` reports the same fault.
- No reservation-loop verifier counters or GPU-probe summary were emitted,
  because the verifier/probe path was intentionally off.

Result:

- The route still produced a fatal VM access violation with the verifier off,
  but it did not begin from the accepted field visual state. This makes it
  evidence that the macro/route can crash without verifier logging, not clean
  proof that the accepted field route itself is verifier-independent.

Reading:

- The live reservation-loop verifier is not required to make this exact
  stepped-left macro crash. The route/input state is at least part of the
  problem.
- Because the first screenshot was already the wrong visual state, this run is
  not a clean A/B against the `Verify` stepped-left crash. Do not use it to
  authorize lane-2 fast/HLE/GPU work.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `failed`, `route-tooling`, `stepleft-off-crash`, `not-comparable-visual`,
  not `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate
  candidate.

Next:

- Force/prove the accepted Path to Tenuto field visual before any movement,
  then add movement in smaller state-aware chunks. A good next isolate is a
  pre-movement field screenshot plus one short `ls_left:200..400` pulse and an
  immediate screenshot, stopping before long waits or repeat pulses.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Short-Left200 State-Aware Verifier Isolate

Question:

- Can the verifier route first prove the accepted Path to Tenuto field state,
  then survive one tiny left movement pulse without losing the window or
  crashing?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-shortleft200-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:2000;ls_left:200;wait:1000;shot:100;wait:4000;shot:100" -MaxSeconds 145 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 112 -ScreenshotMaxCount 6
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-050601-cpu4-reservation-loop-shortleft200-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0126s/postrun host checks.
  Host contention summary was clean across 4 snapshots, the lab stopped PID
  `25808` at the 145s wall limit, exit code was `exited`, and no `rpcs3`
  process remained after the run.
- Visual check: `screenshots/screenshot-0117s.png` is clean Path to Tenuto
  before movement; `screenshots/screenshot-0121s.png` is clean Path to Tenuto
  after the `ls_left:200` pulse; `screenshots/screenshot-0142s.png` is still
  clean field with no crash overlay.
- Clean fatal scan found no `Access violation`, SIGSEGV/SIGBUS, Vulkan
  validation/VK_ERROR, verification failure, assertion, unhandled exception, or
  likely-crashed hit. `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,496.72 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=715` / `too-small=376`.
- Reservation verify peak totals: attempts/completed
  `118764 / 33205`, success/failure/unexpected `20164 / 13041 / 4980`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `151969 / 118764 / 33205 / 0`, and dirty multi-slot observations `3`.
- Lane 2:
  attempts/completed/success/failure/unexpected `9352 / 9352 / 9352 / 0 / 0`,
  branch R/N `9352/9352/0 / 0/0/0`, dirty `0/9350/2`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `1115`, class
  `live-verify-seen`.

Reading:

- This repairs the immediate route isolate: one very small, state-aware left
  pulse survives cleanly after the accepted field visual is proven first.
- It does not prove first battle, longer movement, diagonal movement, or a
  lane-2 fast/HLE/GPU replacement. Lane 2 remains the cleanest candidate, but
  the run still has dirty multi-slot observations and lane-3 noise.
- The hot observed traffic remains large SPU-kernel/HLE-shaped work with zero
  RSX-local records. This keeps the likely CPU-to-GPU path in SPU-kernel
  replacement/reduced-loop/codegen research, not naive RSX-local offload.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `analysis`, `route-tooling`, `shortleft200-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Extend the same state-aware route gradually: prove field, apply two tiny left
  pulses with immediate screenshots, then only later reintroduce longer left
  or diagonal movement.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Short-Left200x2 State-Aware Verifier Isolate

Question:

- Does the state-aware verifier route survive two tiny left movement pulses,
  after first proving the accepted Path to Tenuto field visual?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-shortleft200x2-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:2000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:4000;shot:100" -MaxSeconds 155 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 112 -ScreenshotMaxCount 7
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-053627-cpu4-reservation-loop-shortleft200x2-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0129s/sample-0150s/postrun host
  checks. Host contention summary was clean across 5 snapshots, the lab
  stopped PID `3784` at the 155s wall limit, exit code was `exited`, and no
  `rpcs3` process remained after the run.
- The Codex shell wrapper timed out after the lab postrun while the expensive
  summarizer phase was still pending, so the summary was regenerated manually
  with `tools/summarize_eternal_sonata_gpu_probe.ps1`.
- Visual check: `screenshots/screenshot-0117s.png` is clean Path to Tenuto
  before movement; `screenshots/screenshot-0124s.png` is clean Path to Tenuto
  after the second `ls_left:200` pulse; `screenshots/screenshot-0152s.png`
  remains clean field with no crash overlay.
- Clean fatal scan found no `Access violation`, SIGSEGV/SIGBUS, Vulkan
  validation/VK_ERROR, verification failure, assertion, unhandled exception, or
  likely-crashed hit. `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,680.85 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=796` / `too-small=366`.
- Reservation verify peak totals: attempts/completed
  `118400 / 32342`, success/failure/unexpected `17870 / 14472 / 5419`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `150742 / 118400 / 32342 / 0`, and dirty multi-slot observations `0`.
- Lane 2:
  attempts/completed/success/failure/unexpected `9016 / 9016 / 9016 / 0 / 0`,
  branch R/N `9016/9016/0 / 0/0/0`, dirty `0/9016/0`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `1200`, class
  `live-verify-seen`.

Reading:

- Two tiny state-aware left pulses survive cleanly, so the route is improving
  from the earlier one-pulse proof without reproducing the long-left window
  loss or three-step crash.
- This still does not prove first battle, longer movement, diagonal movement,
  or a lane-2 fast/HLE/GPU replacement. Lane 2 is cleaner here than the
  one-pulse run, but lane 1 remains noisy and lane 3 still fails most tries.
- The observed hot work is again SPU-kernel/HLE-shaped with zero RSX-local
  records, so this supports continuing SPU-kernel replacement/codegen scouting
  once the route can cover field/menu/battle. It is not an RSX-local GPU win.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `analysis`, `route-tooling`, `shortleft200x2-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Continue the state-aware ladder: either three `ls_left:200` pulses or one
  `ls_left:400` pulse with immediate screenshots. Reintroduce diagonal
  movement only after the left ladder stays visually clean.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Short-Left200x3 State-Aware Verifier Isolate

Question:

- Does the state-aware verifier route still survive if the left ladder is
  extended from two tiny `ls_left:200` pulses to three?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-shortleft200x3-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:2000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:4000;shot:100" -MaxSeconds 165 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 112 -ScreenshotMaxCount 8
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-060613-cpu4-reservation-loop-shortleft200x3-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0132s/sample-0150s/postrun host
  checks. Host contention summary was clean across 5 snapshots, the lab
  stopped PID `25648` at the 165s wall limit, exit code was `exited`, and no
  `rpcs3` process remained after the run.
- Visual check failed: `screenshots/screenshot-0117s.png` was already black
  with only the performance overlay before movement, and
  `screenshots/screenshot-0127s.png` plus `screenshots/screenshot-0162s.png`
  were still black. This is not accepted Path to Tenuto field and cannot be
  compared to the one-pulse or two-pulse clean field runs.
- Clean fatal scan found no `Access violation`, SIGSEGV/SIGBUS, Vulkan
  validation/VK_ERROR, verification failure, assertion, unhandled exception, or
  likely-crashed hit. `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,324.58 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=671` / `too-small=655`.
- Reservation verify peak totals: attempts/completed
  `137228 / 36899`, success/failure/unexpected `19141 / 17758 / 5908`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `174127 / 137228 / 36899 / 0`, and dirty multi-slot observations `1`.
- Lane 2:
  attempts/completed/success/failure/unexpected `9568 / 9568 / 9568 / 0 / 0`,
  branch R/N `9568/9568/0 / 0/0/0`, dirty `0/9567/1`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `1339`, class
  `live-verify-seen`.

Reading:

- This run is a visual route failure, not a clean extension of the two-pulse
  proof. The first screenshot was already black, so the invalid state cannot be
  blamed specifically on the third pulse.
- Lane 2 remains counter-clean, but the black visual invalidates the route and
  blocks any lane-2 fast/HLE/GPU dry-run from using this capture.
- The hot work remains SPU-kernel/HLE-shaped with zero RSX-local traffic, but
  the visual mismatch means this capture is only useful as a failed route note,
  not as GPU migration or speed evidence.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `failed`, `route-tooling`, `shortleft200x3-black-visual`,
  `not-comparable-visual`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Do not continue the three-pulse branch as-is. Rerun a two-pulse confirm or a
  single state-aware `ls_left:400` pulse with immediate screenshots, and keep
  the pre-movement field proof as the accept/reject gate.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Short-Left400 State-Aware Verifier Isolate

Question:

- Does one larger state-aware `ls_left:400` pulse survive after first proving
  the accepted Path to Tenuto field visual?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-shortleft400-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100" -MaxSeconds 160 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 112 -ScreenshotMaxCount 8
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-063610-cpu4-reservation-loop-shortleft400-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0139s/sample-0150s/postrun host
  checks. Host contention summary was clean across 5 snapshots, the lab
  stopped PID `25004` at the 160s wall limit, exit code was `exited`, and no
  `rpcs3` process remained after the run.
- Visual check: `screenshots/screenshot-0117s.png` is clean Path to Tenuto
  before movement; `screenshots/screenshot-0121s.png` is clean Path to Tenuto
  after the `ls_left:400` pulse; `screenshots/screenshot-0152s.png` remains
  clean field with no crash overlay.
- Clean fatal scan found no `Access violation`, SIGSEGV/SIGBUS, Vulkan
  validation/VK_ERROR, verification failure, assertion, unhandled exception, or
  likely-crashed hit. `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,760.42 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=811` / `too-small=407`.
- Reservation verify peak totals: attempts/completed
  `116943 / 31982`, success/failure/unexpected `17454 / 14528 / 5297`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `148925 / 116943 / 31982 / 0`, and dirty multi-slot observations `2`.
- Lane 2:
  attempts/completed/success/failure/unexpected `8725 / 8725 / 8725 / 0 / 0`,
  branch R/N `8725/8724/1 / 1/0/1`, dirty `0/8723/2`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `1248`, class
  `live-verify-seen`.

Reading:

- A single `ls_left:400` pulse is visually clean when the accepted field state
  is proven first. That makes it a better next route primitive than the
  visually invalid three-pulse `ls_left:200` run.
- Lane 2 remains success-clean, but the retry/next branch anomaly and two
  dirty multi-slot observations mean lane-2 fast/HLE/GPU replacement is still
  blocked.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local records,
  again pointing toward SPU-kernel replacement/reduced-loop/codegen once route
  proof covers field/menu/battle.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `analysis`, `route-tooling`, `shortleft400-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Use the clean `ls_left:400` primitive for the next route ladder: either two
  `ls_left:400` state-aware pulses with immediate screenshots, or one tiny
  diagonal micro-pulse after the clean left pulse. Keep pre-movement field
  proof as the accept/reject gate.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and branch anomalies are
  explained or modeled.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Left400-Diag200 State-Aware Verifier Isolate

Question:

- Does the clean `ls_left:400` route primitive survive a tiny diagonal
  `combo:ls_left+ls_down:200` pulse while keeping accepted field visuals?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-left400-diag200-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100" -MaxSeconds 170 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 112 -ScreenshotMaxCount 9
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-070740-cpu4-reservation-loop-left400-diag200-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0141s/sample-0150s/postrun host
  checks. Host contention summary was clean across 5 snapshots, the lab
  stopped PID `6592` at the 170s wall limit, exit code was `exited`, and no
  `rpcs3` process remained after the run.
- Visual check: `screenshots/screenshot-0117s.png` is clean Path to Tenuto
  before movement; `screenshots/screenshot-0121s.png` is clean after
  `ls_left:400`; `screenshots/screenshot-0124s.png` is clean after
  `combo:ls_left+ls_down:200`; `screenshots/screenshot-0162s.png` remains
  clean field with no crash overlay.
- Clean fatal scan found no `Access violation`, SIGSEGV/SIGBUS, Vulkan
  validation/VK_ERROR, verification failure, assertion, unhandled exception, or
  likely-crashed hit. `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,798.43 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=846` / `too-small=408`.
- Reservation verify peak totals: attempts/completed
  `116619 / 30398`, success/failure/unexpected `15641 / 14757 / 5287`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `147017 / 116619 / 30398 / 0`, and dirty multi-slot observations `0`.
- Lane 2:
  attempts/completed/success/failure/unexpected `7818 / 7818 / 7818 / 0 / 0`,
  branch R/N `7818/7818/0 / 0/0/0`, dirty `0/7818/0`, retry/next
  `0xc2c -> 0xcac`, lane-join verify rows `1282`, class
  `live-verify-seen`.

Reading:

- The tiny diagonal pulse is a clean extension of the accepted left400 field
  primitive. This is the first recent diagonal state-aware route step that
  keeps field visuals valid through the late screenshots.
- Lane 2 is cleaner than the previous left400 run because retry/next branch
  anomalies and dirty multi-slot observations disappear in the lane-2 row.
  Lane 1 remains noisy and lane 3 still fails most attempts, so a broad
  whole-loop fast path remains unsafe.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local records.
  That still points toward SPU-kernel replacement/reduced-loop/codegen after
  field/menu/battle route proof, not an immediate RSX-local GPU dispatch path.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `analysis`, `route-tooling`, `left400-diag200-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Extend the accepted route one notch at a time: either increase the diagonal
  micro-pulse after `ls_left:400`, or add one second accepted-field movement
  step with immediate screenshots.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and the lane-1/lane-3
  behavior is either modeled or explicitly excluded.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Left400-Diag400 State-Aware Verifier Isolate

Question:

- Does the clean `ls_left:400` plus diagonal route survive a longer
  `combo:ls_left+ls_down:400` pulse while keeping accepted field visuals?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-left400-diag400-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100" -MaxSeconds 175 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 112 -ScreenshotMaxCount 9
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-073611-cpu4-reservation-loop-left400-diag400-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0142s/sample-0150s/postrun host
  checks. Host contention summary was clean across 5 snapshots, the lab
  stopped PID `20188` at the 175s wall limit, exit code was `exited`, and no
  `rpcs3` process remained after the run.
- The outer command timed out after the lab ended but before the automatic
  summary finished. Re-running `tools/summarize_eternal_sonata_gpu_probe.ps1`
  on the run directory generated the summary successfully.
- Visual check: `screenshots/screenshot-0117s.png` is clean Path to Tenuto
  before movement; `screenshots/screenshot-0121s.png` is clean after
  `ls_left:400`; `screenshots/screenshot-0124s.png` is clean after
  `combo:ls_left+ls_down:400`; `screenshots/screenshot-0172s.png` remains
  clean field with no crash overlay.
- Clean fatal scan found no `Access violation`, SIGSEGV/SIGBUS, Vulkan
  validation/VK_ERROR, verification failure, assertion, unhandled exception, or
  likely-crashed hit. `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `2,010.89 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=937` / `too-small=413`.
- Reservation verify peak totals: attempts/completed
  `103976 / 31586`, success/failure/unexpected `20039 / 11547 / 3533`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `135562 / 103976 / 31586 / 0`, and dirty multi-slot observations `1`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `11912 / 11912 / 11912 / 0 / 0`, branch R/N `11912/11912/0 / 0/0/0`,
  dirty `0/11911/1`, retry/next `0xc2c -> 0xcac`, lane-join verify rows
  `1381`, class `live-verify-seen`.

Reading:

- The longer diagonal pulse is visually clean. The route ladder can now move
  further than the earlier two tiny left pulses and the failed three-pulse
  branch without losing the field visual.
- Lane 2 remains success-clean and branch-clean, but the single dirty
  multi-slot observation means it is still not a safe fast/HLE/GPU replacement
  target by itself. Lane 1 remains noisy and lane 3 is still not broadly clean.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local records.
  This keeps the future GPU/optimization target on SPU-kernel replacement,
  reduced-loop/codegen, or a carefully modeled lane-2 whole-loop path, not
  immediate RSX-local dispatch.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `analysis`, `route-tooling`, `left400-diag400-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Add one more accepted-field movement step or use this clean diagonal
  primitive to rebuild the first-battle route with immediate screenshots.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and the dirty-slot cases
  are modeled or excluded.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Left400-Diag400x2 State-Aware Verifier Invalid Route

Question:

- Can the clean `left400 + diag400` route be extended with a second
  `combo:ls_left+ls_down:400` step?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-left400-diag400x2-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100" -MaxSeconds 185 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 112 -ScreenshotMaxCount 10
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-080631-cpu4-reservation-loop-left400-diag400x2-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0144s/sample-0150s/sample-0180s
  and postrun host checks. Host contention summary was clean across 6
  snapshots, the lab stopped PID `25128` at the 185s wall limit, exit code was
  `exited`, and no `rpcs3` process remained after the run.
- The outer command timed out after the lab ended but before the automatic
  summary finished. Re-running `tools/summarize_eternal_sonata_gpu_probe.ps1`
  on the run directory generated the summary successfully.
- Visual check failed: `screenshots/screenshot-0117s.png` is already the
  blue/star transition screen before movement, not accepted Path to Tenuto
  field. `screenshots/screenshot-0121s.png`, `screenshot-0124s.png`,
  `screenshot-0127s.png`, and `screenshot-0182s.png` remain in that transition.
- Clean fatal scan found no `Access violation`, SIGSEGV/SIGBUS, Vulkan
  validation/VK_ERROR, verification failure, assertion, unhandled exception, or
  likely-crashed hit. `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `2,370.21 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=1270` / `too-small=213`.
- Reservation verify peak totals: attempts/completed
  `117033 / 32907`, success/failure/unexpected `17432 / 15475 / 4627`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `149940 / 117033 / 32907 / 0`, and dirty multi-slot observations `1`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `10323 / 10323 / 10323 / 0 / 0`, branch R/N `10323/10322/1 / 1/0/1`,
  dirty `0/10322/1`, retry/next `0xc2c -> 0xcac`, lane-join verify rows
  `1500`, class `live-verify-seen`.

Reading:

- This is not a clean route extension. The invalid visual state is present
  before any movement, so the second diagonal cannot be judged.
- Lane 2 is counter-success-clean, but the visual route is invalid and the
  dirty/branch anomaly reappears. This capture cannot support a lane-2
  fast/HLE/GPU replacement.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local records,
  but because the visuals are wrong this is only a failed route note, not a
  GPU migration or speed result.
- This does not move work to GPU, does not prove speed, and does not satisfy
  the first-battle leg of the 200% gate.

Classification:

- `failed`, `route-tooling`, `left400-diag400x2-transition-visual`,
  `not-comparable-visual`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Do not build on this branch. Revert to the last accepted
  `left400-diag400` field primitive and re-prove the field visual before any
  extra movement or first-battle route.
- If the transition repeats, add a stricter state-aware accept gate or a longer
  post-load wait before movement rather than adding more controller input.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Left400-Diag400x2 Late-Field Verifier Battle Crash

Question:

- Was the previous `left400 + diag400x2` failure caused by entering movement
  during a transition, and can a longer post-load settle reach first battle?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-left400-diag400x2-latefield-verify-stateaware-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:30000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 124 -ScreenshotMaxCount 10
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-083632-cpu4-reservation-loop-left400-diag400x2-latefield-verify-stateaware-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample-0157s/sample-0180s/postrun host
  checks. Host contention summary was clean across 5 snapshots, the lab
  stopped PID `19412` at the 205s wall limit, exit code was `exited`, and no
  `rpcs3` process remained after the run.
- Visual check: `screenshots/screenshot-0129s.png` is accepted Path to Tenuto
  before movement. `screenshot-0134s.png` is clean after `ls_left:400`, and
  `screenshot-0137s.png` is clean after the first `combo:ls_left+ls_down:400`.
  `screenshot-0140s.png` is black/loading, and
  `screenshots/screenshot-0204s.png` reaches active first-battle UI but has
  the RPCS3 `The PS3 application has likely crashed` overlay.
- Fatal scan found a real crash:
  `PPU[0x100000c] Thread () [0x002aedd0]: VM: Access violation reading location 0x40 (unmapped memory)`.
  `rpcs3.stderr.txt` contains the same access violation, and stdout is empty.
- `eternal-sonata-gpu-probe-summary.md` has no NUL bytes.

Result:

- Summary totals: `1,450.55 MB` observed DMA, `0` RSX-local traffic records,
  offload fit `spu-kernel-hle=677` / `too-small=404`.
- Reservation verify peak totals: attempts/completed
  `119921 / 37021`, success/failure/unexpected `23099 / 13922 / 5245`,
  AtomicStat reads / GETLLAR / PUTLLC / unexpected reads
  `156942 / 119921 / 37021 / 0`, and dirty multi-slot observations `2`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `14248 / 14248 / 14248 / 0 / 0`, branch R/N `14248/14247/1 / 1/0/1`,
  dirty `0/14246/2`, retry/next `0xc2c -> 0xcac`, lane-join verify rows
  `1100`, class `live-verify-seen`.

Reading:

- The longer settle fixes the pre-movement visual problem and gets the route
  through clean field movement into the battle transition, but the first-battle
  visual is invalid because RPCS3 reports a real PPU access violation and the
  crash overlay is visible.
- This is a useful first-battle route lead, not a first-battle proof. It says
  the movement can reach battle, but either the route/input state, verifier
  perturbation, or existing core bug trips the guest before it can be accepted.
- Lane 2 remains success-clean by counters but reintroduces dirty/branch
  anomalies, so it still cannot be used for a lane-2 fast/HLE/GPU replacement.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local records.
  This is not GPU migration or a speed result.

Classification:

- `failed`, `route-tooling`, `latefield-diag400x2-battle-crash`, not
  `first-battle-proof`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

Next:

- Isolate the crash: rerun the late-field route with
  `-EternalSonataReservationLoop Off`, or keep the verifier but remove the
  second diagonal and capture battle entry. Use the same longer post-load
  settle because it correctly reaches accepted field before movement.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and dirty-slot cases are
  modeled or excluded.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Left400-Diag400x2 Late-Field Verifier-Off Isolate

Question:

- Is the late-field `left400 + diag400x2` battle crash caused by the
  reservation-loop verifier, or can the same route fail without that probe?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-left400-diag400x2-latefield-off-isolate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Off -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:30000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 124 -ScreenshotMaxCount 10
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-090816-cpu4-reservation-loop-left400-diag400x2-latefield-off-isolate-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch, postlaunch, and postrun host checks. Host
  contention summary was clean across 3 snapshots, stdout/stderr were empty,
  and no `rpcs3` process remained after the run.
- Visual check: `screenshots/screenshot-0129s.png` is accepted Path to Tenuto
  before movement. `screenshot-0133s.png` is clean after `ls_left:400`, and
  `screenshot-0136s.png` is clean after the first
  `combo:ls_left+ls_down:400`.
- The run failed after the second diagonal/battle-transition window. The lab
  reported `Screenshot skipped at 145s: game window was not found` and again
  at `157s`; `screenshots/screenshot-0139s.png` is a browser capture, not
  RPCS3 gameplay.
- Fatal scan found no `Access violation`, `VM: Access`, SIGSEGV/SIGBUS,
  `likely crashed`, verification failure, assertion, unhandled exception, or
  `VK_ERROR`.
- The RPCS3 log still ended with guest/RSX corruption signals:
  `unknown draw command=60`, `Unknown/illegal instruction=51`, and
  `Unexpected instruction=50`.
- No `eternal-sonata-gpu-probe-summary.md` exists because the reservation/GPU
  probe path was deliberately off.

Result:

- Turning the verifier off removes the visible first-battle `0x40` PPU access
  violation seen in the verifier-on run, but it does not produce a clean battle
  proof. The emulator/window disappears earlier, and the final captured image
  is not gameplay.
- Because the route still fails without the verifier, the second diagonal or
  route state is unsafe enough that lane-2 HLE/GPU dry-runs would be
  premature. The verifier may change the exact failure shape, but it is not the
  only blocker.
- This run has no reservation counters, no RSX-local traffic accounting, and no
  promoted CPU/SPU/PPU GPU migration credit.

Classification:

- `failed`, `route-tooling`, `latefield-diag400x2-off-window-loss`,
  `not-first-battle-proof`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Keep the longer post-load settle, but remove the second diagonal and capture
  first-battle entry from the clean `left400 + diag400` primitive.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and dirty-slot cases are
  modeled or excluded.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Left400-Diag400 Late-Field Battle-Wait Verifier Miss

Question:

- If the second diagonal is removed, does the long-settle
  `left400 + diag400` primitive safely reach or approach first battle under
  the reservation-loop verifier?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-left400-diag400-latefield-battlewait-verify-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:30000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100;wait:30000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 124 -ScreenshotMaxCount 12
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-093617-cpu4-reservation-loop-left400-diag400-latefield-battlewait-verify-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample/postrun host checks. Host
  contention summary was clean across 5 snapshots. The lab stopped PID
  `21084` at the 225s wall limit, stdout/stderr were empty, and no `rpcs3`
  process remained after the run.
- Visual check failed before movement: `screenshots/screenshot-0129s.png`,
  `screenshot-0133s.png`, `screenshot-0136s.png`, `screenshot-0153s.png`,
  `screenshot-0204s.png`, and `screenshot-0224s.png` are all
  `Now Loading...`, not accepted Path to Tenuto field or battle.
- Clean fatal scan found no `Access violation`, `VM: Access`, SIGSEGV/SIGBUS,
  Vulkan validation/VK_ERROR, verification failure, assertion, unhandled
  exception, or likely-crashed hit.
- The normal GPU-probe summarizer timed out on the 108 MB log, so this entry
  uses a narrow `rg` parser over the exact probe rows instead of a generated
  `eternal-sonata-gpu-probe-summary.md`.

Result:

- Narrow parser totals: `1,869` GPU-candidate records,
  `2,497.55 MB` observed DMA, and `0` RSX-local bytes.
- Reservation verify aggregate peak:
  attempts/completed/success/failure/unexpected
  `84183 / 22609 / 12273 / 10336 / 3698`, AtomicStat reads / GETLLAR /
  PUTLLC / unexpected `125421 / 84183 / 22609 / 0`, dirty multi-slot `2`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `6136 / 6136 / 6136 / 0 / 0`, AtomicStat reads / GETLLAR / PUTLLC /
  unexpected `12272 / 6136 / 6136 / 0`, dirty multi-slot `2`, retry
  `6136/6136/1`, next `1/0/1`, PCs `0xc2c -> 0xcac`.

Reading:

- This run is not a valid movement or first-battle proof because the field was
  never accepted before input. The route timing is still too brittle; adding or
  removing movement is not meaningful until the macro proves accepted field
  before the first stick input.
- The absence of crashes is useful, but it does not clear the route. Lane 2 is
  still counter-success-clean, yet dirty/branch anomalies remain and the visual
  state is invalid, so no lane-2 fast/HLE/GPU replacement should start from
  this run.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local bytes, but
  this is not GPU migration or speed evidence.

Classification:

- `failed`, `route-tooling`, `latefield-diag400-loading-visual`,
  `not-comparable-visual`, not `first-battle-proof`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Add a stronger or longer accepted-field wait/gate before any movement, then
  rerun the clean `left400 + diag400` primitive.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and dirty-slot cases are
  modeled or excluded.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Fieldgate60 Left400-Diag400 Verifier Primitive

Question:

- Does delaying movement until about 60s after the final Cross produce a stable
  accepted-field base for the `left400 + diag400` route primitive?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-left400-diag400-fieldgate60-verify-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:60000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100;wait:30000;shot:100" -MaxSeconds 255 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 150 -ScreenshotMaxCount 12
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-100642-cpu4-reservation-loop-left400-diag400-fieldgate60-verify-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample/postrun host checks. Host
  contention summary was clean across 5 snapshots. The lab stopped PID `2556`
  at the 255s wall limit, stdout/stderr were empty, and no `rpcs3` process
  remained after the run.
- Visual check: `screenshots/screenshot-0159s.png` is accepted Path to Tenuto
  before movement; `screenshot-0163s.png` is clean after `ls_left:400`;
  `screenshot-0166s.png` is clean after `combo:ls_left+ls_down:400`;
  `screenshot-0183s.png`, `screenshot-0214s.png`, and `screenshot-0250s.png`
  remain clean field with no crash overlay.
- Clean fatal scan found no `Access violation`, `VM: Access`, SIGSEGV/SIGBUS,
  Vulkan validation/VK_ERROR, verification failure, assertion, unhandled
  exception, or likely-crashed hit.
- The normal GPU-probe summarizer timed out on the 109 MB log, so this entry
  uses a narrow `rg` parser over the exact probe rows instead of a generated
  `eternal-sonata-gpu-probe-summary.md`.

Result:

- Narrow parser totals: `1,925` GPU-candidate records,
  `3,206.52 MB` observed DMA, and `0` RSX-local bytes.
- Reservation verify aggregate peak:
  attempts/completed/success/failure/unexpected
  `108329 / 29626 / 17419 / 13611 / 5099`, AtomicStat reads / GETLLAR /
  PUTLLC / unexpected `163468 / 108329 / 29626 / 0`, dirty multi-slot `3`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `8709 / 8709 / 8709 / 0 / 0`, AtomicStat reads / GETLLAR / PUTLLC /
  unexpected `17418 / 8709 / 8709 / 0`, dirty multi-slot `3`, retry
  `8709/8709/1`, next `1/0/1`, PCs `0xc2c -> 0xcac`.

Reading:

- The stronger field gate fixes the prior loading-visual miss and gives a
  stable accepted-field base for this route. It does not reach first battle;
  it is field-route scaffolding only.
- Lane 2 remains success-clean, but dirty multi-slot and branch anomalies
  still block a fast/HLE/GPU replacement. The visual route is clean field only,
  not menu or battle.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local bytes.
  This run does not move new work to GPU, does not prove speed, and does not
  satisfy the 200% gate.

Classification:

- `analysis`, `route-tooling`, `fieldgate60-left400-diag400-field-clean`, not
  `first-battle-proof`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

Next:

- Use `fieldgate60` as the route base and add a stronger movement leg from
  accepted field, with immediate screenshots before and after movement.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and dirty-slot cases are
  modeled or excluded.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Fieldgate60 Left400-Diag400-Diag200 Verifier Miss

Question:

- Can the stable fieldgate60 route base tolerate one smaller extra
  `combo:ls_left+ls_down:200` pulse without hitting the unstable second
  diagonal edge?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-fieldgate60-left400-diag400-diag200-verify-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:60000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100;wait:30000;shot:100" -MaxSeconds 275 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 150 -ScreenshotMaxCount 14
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-103704-cpu4-reservation-loop-fieldgate60-left400-diag400-diag200-verify-windows-windows/`.
- The lab kept RPCS3 on `\\.\DISPLAY2`, applied CPU affinity `0x0F`, and
  reported clean prelaunch/postlaunch/sample/postrun host checks. Host
  contention summary was clean across 6 snapshots. The lab stopped PID
  `27384` at the 275s wall limit, stdout/stderr were empty, and no `rpcs3`
  process remained after the run.
- Visual check failed before movement: `screenshots/screenshot-0159s.png`,
  `screenshot-0169s.png`, `screenshot-0216s.png`, and
  `screenshot-0270s.png` are all `Now Loading...`, not accepted Path to Tenuto
  field or battle.
- Clean fatal scan found no `Access violation`, `VM: Access`, SIGSEGV/SIGBUS,
  Vulkan validation/VK_ERROR, verification failure, assertion, unhandled
  exception, or likely-crashed hit.
- The normal GPU-probe summarizer would be too expensive for this 135 MB log,
  so this entry uses a narrow `rg` parser over exact probe rows.

Result:

- Narrow parser totals: `2,330` GPU-candidate records,
  `3,210.10 MB` observed DMA, and `0` RSX-local bytes.
- Reservation verify aggregate peak:
  attempts/completed/success/failure/unexpected
  `130690 / 35831 / 18781 / 17050 / 5923`, AtomicStat reads / GETLLAR /
  PUTLLC / unexpected `194854 / 130690 / 35831 / 0`, dirty multi-slot `2`.
- Lane 2:
  attempts/completed/success/failure/unexpected
  `9390 / 9390 / 9390 / 0 / 0`, AtomicStat reads / GETLLAR / PUTLLC /
  unexpected `18780 / 9390 / 9390 / 0`, dirty multi-slot `2`, retry
  `9390/9390/1`, next `1/0/1`, PCs `0xc2c -> 0xcac`.

Reading:

- The extra movement cannot be judged because accepted field was never reached
  before input. Fieldgate60 improved one run, but it is not deterministic
  enough to be trusted without an actual screenshot/state accept gate.
- Lane 2 remains counter-success-clean, but dirty/branch anomalies and invalid
  visuals still block any fast/HLE/GPU replacement.
- The hot traffic remains SPU-kernel/HLE-shaped with zero RSX-local bytes.
  This run does not move new work to GPU, does not prove speed, and does not
  satisfy the 200% gate.

Classification:

- `failed`, `route-tooling`, `fieldgate60-diag200-loading-visual`,
  `not-comparable-visual`, not `first-battle-proof`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Add an explicit accepted-field screenshot/state gate before movement, or
  make the loader wait longer/stabler, before adding any more route movement.
- Keep lane-2 HLE/GPU dry-runs blocked until field, menu/Options, and first
  battle are visually clean under the verifier route and dirty-slot cases are
  modeled or excluded.
- Keep Android/Thor untouched until Windows proves the 200% moving-gameplay
  gate with correct field, menu/Options, and first battle visuals.

## 2026-05-23 Windows Visual Gate Helper

Question:

- Can the Windows lab cheaply reject loading-screen and wrong-window route
  captures before their SPU/RSX counters get mistaken for usable movement
  evidence?

Tool:

- Added `tools/check_eternal_sonata_windows_visual_gate.ps1`.
- The helper scans a run directory's `screenshots/*.png`, sorts screenshots by
  the `screenshot-0000s.png` timestamp, and classifies each image by PNG byte
  size. The default field-like threshold is `1,000,000` bytes.
- It writes `eternal-sonata-windows-visual-gate-summary.md` into the run
  directory and can fail the command when `-RequireFieldLike`,
  `-RequireFieldAtOrBeforeSeconds`, or `-RequireNoInvalidAfterFirstField` is
  not satisfied.

Validation:

```powershell
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260523-100642-cpu4-reservation-loop-left400-diag400-fieldgate60-verify-windows-windows -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260523-103704-cpu4-reservation-loop-fieldgate60-left400-diag400-diag200-verify-windows-windows -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260523-090816-cpu4-reservation-loop-left400-diag400x2-latefield-off-isolate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260523-093617-cpu4-reservation-loop-left400-diag400-latefield-battlewait-verify-windows-windows -RequireFieldLike
```

Result:

- Accepted fieldgate60 route passed: `20260523-100642...` had `17`
  screenshots, status `FIELD_LIKE_PRESENT`, and first field-like image
  `screenshot-0159s.png` at `159s` / `2.50 MB`.
- Loading-only fieldgate60-diag200 route failed: `20260523-103704...` had
  `20` screenshots, status `NO_FIELD_LIKE_SCREENSHOT`, and failed both
  `-RequireFieldLike` and `-RequireFieldAtOrBeforeSeconds 160`.
- Loading-only late-field route failed: `20260523-093617...` had `17`
  screenshots and status `NO_FIELD_LIKE_SCREENSHOT`.
- Verifier-off window-loss route now fails when requiring no invalid frames
  after first field: `20260523-090816...` had first field-like image
  `screenshot-0129s.png` at `129s` / `2.50 MB`, then
  `screenshot-0139s.png` fell to `73.02 KB` and is classified
  `invalid-small-png-loading-black-or-wrong-window`.

Reading:

- The accepted-field and loading-screen split is strong enough for automated
  triage in the current route family. It is not OCR and it is not final
  correctness proof, but it prevents a repeat of treating `Now Loading...`
  counters as movement-route evidence.
- This helper also catches a late wrong-window/window-loss sequence that a
  simple "any field screenshot exists" check would miss.
- The result does not move CPU/SPU/PPU work to GPU and does not measure speed;
  it makes the next Windows-only HLE/GPU experiment less likely to start from
  invalid visuals.

Classification:

- `analysis`, `route-tooling`, `windows-visual-gate-helper`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- For future Windows movement and first-battle route attempts, run the visual
  gate before accepting counters:

```powershell
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\RUN -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
```

- Keep lane-2 HLE/GPU dry-runs blocked until the route has accepted field
  screenshots, no later small invalid screenshots, and separate menu/Options
  plus first-battle visual proof.

## 2026-05-23 Windows Visual Gate Sprint Integration

Question:

- Can the accepted-field visual gate be part of the normal Windows sprint
  command so invalid route captures fail immediately instead of becoming
  manual cleanup work later?

Change:

- `tools/eternal_sonata_speed_sprint.ps1` now accepts:
  `-WindowsVisualGate Off|FieldLike|FieldByDeadline|CleanAfterField`,
  `-WindowsVisualGateFieldSeconds`, and
  `-WindowsVisualGateMinFieldPngBytes`.
- The default is `Off`, so existing Windows and Android command shapes remain
  unchanged.
- After a `WindowsScene` lab run, the wrapper finds the newest matching
  `debug-captures/windows-lab/*-$Label-windows` directory and invokes
  `tools/check_eternal_sonata_windows_visual_gate.ps1`.

Validation:

```powershell
$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\eternal_sonata_speed_sprint.ps1), [ref]$null, [ref]$errors)
$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\check_eternal_sonata_windows_visual_gate.ps1), [ref]$null, [ref]$errors)
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260523-100642-cpu4-reservation-loop-left400-diag400-fieldgate60-verify-windows-windows -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField -NoWriteSummary
.\tools\eternal_sonata_speed_sprint.ps1 -Action ToolStatus -WindowsVisualGate CleanAfterField
```

Result:

- PowerShell parser checks passed for both edited scripts.
- The visual helper still passed the accepted fieldgate60 route:
  `FIELD_LIKE_PRESENT`, first field-like screenshot `screenshot-0159s.png` at
  `159s` / `2.50 MB`.
- `ToolStatus` accepted the new sprint parameter and completed the existing
  tooling check. No Windows emulator route was launched in this validation
  step.

Reading:

- Future route commands can now add
  `-WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160`.
  That is the right default for movement/first-battle verifier work because it
  rejects both "never reached accepted field" and "field was reached, then the
  window/loading state collapsed" captures.
- This does not move any CPU/SPU/PPU work to GPU and does not measure speed.
  It is route tooling that protects the next SPU HLE/codegen or RSX/GPU
  experiment from invalid visual evidence.

Classification:

- `analysis`, `route-tooling`, `sprint-visual-gate-integration`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Run the next Windows-only first-battle verifier attempt with:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-fieldgate60-next-battle-route-verify-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:60000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:2000;combo:ls_left+ls_down:120;wait:1000;shot:100;wait:15000;shot:100;wait:30000;shot:100" -MaxSeconds 265 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 150 -ScreenshotMaxCount 14
```

- If the visual gate fails, classify the run as `failed` / `not-comparable`
  before reading SPU counters. If it passes and reaches battle cleanly, use the
  reservation-loop lane counters to decide whether a lane-2 HLE/codegen dry-run
  can be attempted.

## 2026-05-23 Fieldgate60 Next-Battle Route Visual-Gate Rejection

Question:

- Can the accepted fieldgate60 base tolerate a tiny extra diagonal pulse
  (`combo:ls_left+ls_down:120`) while the new sprint visual gate rejects bad
  pre-field captures?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-fieldgate60-next-battle-route-verify-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:60000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:2000;combo:ls_left+ls_down:120;wait:1000;shot:100;wait:15000;shot:100;wait:30000;shot:100" -MaxSeconds 265 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 150 -ScreenshotMaxCount 14
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-120632-cpu4-reservation-loop-fieldgate60-next-battle-route-verify-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host grade was clean across prelaunch, postlaunch, sample, and postrun
  checks. The lab stopped PID `15924` at the `265s` limit, stdout/stderr were
  empty, and no `rpcs3` process remained after the run.
- Visual gate failed. All `18` screenshots from `screenshot-0159s.png` through
  `screenshot-0260s.png` were only `31-32 KB` and classified
  `invalid-small-png-loading-black-or-wrong-window`. Manual spot checks of
  `screenshot-0159s.png` and `screenshot-0260s.png` show a black frame with
  the performance overlay, not Path to Tenuto field or battle.
- Fatal scan found no real `Access violation`, `VM: Access`, SIGSEGV/SIGBUS,
  Vulkan validation/VK_ERROR, verification failure, assertion, unhandled
  exception, or likely-crashed hit. The only match was the harmless config text
  `Show fatal error hints: false`.

Result:

- GPU probe summary was generated, but the visual route is invalid and the
  counters must not be used as movement proof.
- Summary totals: `1,764` records, `1,740.39 MB` observed DMA, `0`
  RSX-local traffic, offload fit `too-small=905` / `spu-kernel-hle=859`.
- Reservation verify aggregate:
  attempts/completed `157353 / 40856`, success/failure/unexpected
  `21746 / 19110 / 6714`, AtomicStat reads / GETLLAR / PUTLLC / unexpected
  `198209 / 157353 / 40856 / 0`, dirty multi-slot `1`.
- Lane 2 stayed counter-clean but visually unusable: primary lane-2 row
  attempts/completed/success/failure/unexpected `8300 / 8300 / 8300 / 0 / 0`,
  dirty `0/8299/1`, retry `8300/8300/0`, next `0/0/0`, PCs
  `0xc2c -> 0xcac`; secondary lane-2 row `2805 / 2805 / 2805 / 0 / 0`,
  dirty `0/2805/0`.

Reading:

- The new sprint visual gate worked: it rejected a black-screen run before
  lane counters could be mistaken for valid movement evidence.
- This route did not reach accepted field at all, so the tiny extra movement
  pulse cannot be evaluated. The prior fieldgate60 success is still useful but
  not deterministic.
- The hot traffic again points at SPU-kernel/HLE/codegen around `0x451c` and
  `0x25cc` with zero RSX-local bytes, but this run is not a valid proof path
  for a lane-2 fast/HLE/GPU dry-run.
- The helper previously printed gate failures but the outer sprint command did
  not report a nonzero exit. `tools/check_eternal_sonata_windows_visual_gate.ps1`
  now throws on gate failure, and validation confirmed the accepted route still
  passes while this black route fails with a nonzero PowerShell result.

Classification:

- `failed`, `route-tooling`, `fieldgate60-next-battle-black-visual`,
  `not-comparable-visual`, not `first-battle-proof`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Do not extend this route. First rerun the exact accepted fieldgate60
  primitive under `-WindowsVisualGate CleanAfterField` before adding any battle
  movement:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-fieldgate60-rerun-visualgate-verify-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:60000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100;wait:30000;shot:100" -MaxSeconds 255 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 150 -ScreenshotMaxCount 12
```

- Keep lane-2 fast/HLE/GPU dry-runs blocked until field, menu/Options, and
  first-battle visuals are clean under the verifier route.

## 2026-05-23 Continual Harness Refiner Adaptation

Question:

- Can we adapt the useful part of
  `https://github.com/sethkarten/continual-harness` into this repo's PS3 speed
  process without creating a fake infinite autopilot or weakening the Windows
  200% proof gate?

Implementation:

- Added repo-local skill
  `.agents/skills/ps3-continual-harness-refiner/SKILL.md`.
- Added tool `tools/ps3_harness_refiner.ps1`.
- Updated `tools/check_eternal_sonata_windows_visual_gate.ps1` so invalid
  screenshots are split into:
  - `black-overlay-small-png` for current `20-60 KB` black/perf-overlay
    captures;
  - `loading-like-small-png` for current `90-160 KB` loading captures;
  - `wrong-window-or-other-small-png` for other small screenshots;
  - `field-like-large-png` for screenshots at or above `1,000,000` bytes.

Validation commands:

```powershell
$errors=$null; $tokens=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'tools\ps3_harness_refiner.ps1'), [ref]$tokens, [ref]$errors)
$errors=$null; $tokens=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'tools\check_eternal_sonata_windows_visual_gate.ps1'), [ref]$tokens, [ref]$errors)
.\tools\ps3_harness_refiner.ps1 -MaxRuns 6 -NoWrite
```

Refiner result:

- The 6-run window correctly found:
  - `2` black/perf-overlay pre-field runs:
    `20260523-124401...` and `20260523-120632...`;
  - `2` loading-like pre-field runs:
    `20260523-103704...` and `20260523-093617...`;
  - `1` wrong-window/other small-screenshot run:
    `20260523-090816...`;
  - `2` invalid-visual runs with clean lane-2 counters, proving counters alone
    must not start a lane-2 HLE/GPU fast mode;
  - `2` recent summaries with zero RSX-local traffic, so broad SPU-to-Vulkan
    compute remains parked unless a new scout proves RSX-consumed data.

Current refiner decision:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8
```

Reading:

- This is the repo-local version of a continual harness: a trajectory-window
  refiner that catches repeated invalid work and produces one next safe action.
- It does not edit code automatically, does not bypass Codex Desktop limits,
  does not run Android/ADB, and does not weaken the field/menu/battle visual
  proof gate.
- The immediate blocker remains pre-field visual state/loader nondeterminism,
  not a lack of extra stick movement.

Classification:

- `route-tooling`, `process-harness`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate result.

Next:

- Use the refiner before every resumed Windows speed-loop slice.
- Do the suggested loader/control or equivalent black-overlay route control
  before any more movement, lane-2 HLE, or SPU-to-GPU dry-run.

## 2026-05-23 Fieldgate60 Rerun Visual-Gate Rejection

Question:

- Was the earlier accepted fieldgate60 field primitive still reproducible once
  the sprint visual gate was wired into the normal Windows route?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-fieldgate60-rerun-visualgate-verify-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:60000;shot:100;wait:2000;ls_left:400;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:400;wait:1000;shot:100;wait:4000;shot:100;wait:12000;shot:100;wait:30000;shot:100" -MaxSeconds 255 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 150 -ScreenshotMaxCount 12
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-124401-cpu4-reservation-loop-fieldgate60-rerun-visualgate-verify-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host grade was clean across prelaunch, postlaunch, sample, and postrun
  checks. The lab stopped PID `21292` at the `255s` limit, stdout/stderr were
  empty, and no `rpcs3` process remained after the run.
- Visual gate failed. All `17` screenshots from `screenshot-0159s.png` through
  `screenshot-0250s.png` were `31-33 KB` and classified
  `invalid-small-png-loading-black-or-wrong-window`. Manual spot checks of
  `screenshot-0159s.png` and `screenshot-0250s.png` show black frames with
  only the performance overlay, not accepted Path to Tenuto field.
- Fatal scan found no real `Access violation`, `VM: Access`, SIGSEGV/SIGBUS,
  Vulkan validation/VK_ERROR, verification failure, assertion, unhandled
  exception, or likely-crashed hit. The only match was the harmless config text
  `Show fatal error hints: false`.

Result:

- GPU probe summary was generated, but the visual route is invalid and the
  counters must not be used as movement proof.
- Summary totals: `1,736` records, `1,707.01 MB` observed DMA, `0`
  RSX-local traffic, offload fit `too-small=876` / `spu-kernel-hle=860`.
- Reservation verify aggregate:
  attempts/completed `92603 / 26825`, success/failure/unexpected
  `16437 / 10388 / 4152`, AtomicStat reads / GETLLAR / PUTLLC / unexpected
  `119428 / 92603 / 26825 / 0`, dirty multi-slot `1`.
- Lane 2 remained counter-clean but visually unusable:
  attempts/completed/success/failure/unexpected `8216 / 8216 / 8216 / 0 / 0`,
  dirty `0/8215/1`, retry `8216/8216/0`, next `0/0/0`, PCs
  `0xc2c -> 0xcac`.

Reading:

- The exact fieldgate60 primitive is no longer reproducible enough to use as a
  route base. Two consecutive gated runs (`20260523-120632...` and
  `20260523-124401...`) produced black/perf-overlay frames instead of accepted
  field.
- This moves the blocker earlier than battle movement: the next issue is
  pre-field load/state nondeterminism or black-render route state, not the
  extra diagonal input itself.
- The summary again points at SPU-kernel/HLE/codegen work around `0x451c` and
  `0x25cc` with zero RSX-local bytes, but this run is not valid evidence for
  fast/HLE/GPU promotion.

Classification:

- `failed`, `route-tooling`, `fieldgate60-rerun-black-visual`,
  `not-comparable-visual`, not `first-battle-proof`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Stop adding movement on this route until the pre-field visual state is
  reliable again.
- Next useful Windows-only step is tooling or route reset: add a black-overlay
  classification bucket to `check_eternal_sonata_windows_visual_gate.ps1`, then
  run a short no-movement loader/control to distinguish `Now Loading...`,
  black/perf-overlay, and accepted Path to Tenuto before more SPU lane work.
- Keep lane-2 fast/HLE/GPU dry-runs blocked until field, menu/Options, and
  first-battle visuals are clean under the verifier route.

## 2026-05-23 Loader-Control Visualgate Pass

Question:

- After two black/perf-overlay fieldgate60 runs, can a no-movement loader
  control regain a reliable accepted-field baseline before we add movement or
  start lane-2 HLE/GPU dry-runs?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-131933-cpu4-loader-control-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host grade was clean across all `6` snapshots. The lab stopped PID `3120`
  at the `190s` limit, stdout/stderr were empty, and no `rpcs3` process
  remained after the run.
- Visual gate passed: all `10` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), the deadline check passed by `160s`, and no black/loading/
  wrong-window frames appeared after field.
- Manual visual spot check of `screenshot-0117s.png` shows the correct Path to
  Tenuto field with character, pumpkin enemy, and performance overlay, not a
  loading or black-overlay frame.
- Fatal scan found no real `Access violation`, `VM: Access`, SIGSEGV/SIGBUS,
  Vulkan validation/VK_ERROR, verification failure, assertion, unhandled
  exception, or likely-crashed hit.

Result:

- GPU probe summary: `1,442` records, `2,227.01 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1035`, `too-small=407`.
- Hot PCs remain the CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,127.98 MB` and `0x25cc` at `1,099.03 MB`.
- Dynamic MFC fallback timing was still small relative to the whole run:
  `256,904` hits, `187.039 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `10533 / 10533 / 10533 / 0 / 0`,
  retry `10533 / 10533 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- The black-overlay route problem is controllable when we remove movement and
  use the shorter no-movement loader control. This restores a valid field base
  for the next route step.
- The result is not a speed win and not GPU migration credit. It is route
  tooling that prevents invalid counters from driving HLE/GPU decisions.
- The repeated zero RSX-local result still parks broad SPU-to-Vulkan compute.
  Any future CPU/SPU-to-GPU move needs a new RSX-consumed scout or a verify-
  first title/signature-gated kernel path.
- `tools/ps3_harness_refiner.ps1` was updated after the run so the newest
  valid loader-control resolves the black-overlay blocker and now suggests a
  single `ls_left:200` state-aware movement step with `CleanAfterField`. It
  still blocks lane-2 HLE/GPU fast modes while visuals are not proven across
  field/menu/first battle.

Classification:

- `analysis`, `route-tooling`, `loader-control-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Run one small movement step from this loader-control base, not battle
  movement and not lane-2 HLE/GPU fast mode:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10
```

## 2026-05-23 Loader-Control Left200 Visualgate Pass

Question:

- Can the refiner's valid no-movement loader-control route survive one tiny
  state-aware movement step under the normal Windows visual gate?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-134631-cpu4-loader-control-left200-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- The Codex command timed out while post-run summarization was still being
  cleaned up, so the visual gate and GPU probe summary were regenerated
  manually after confirming no `rpcs3` process remained.
- Visual gate passed: all `14` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), and there were `0` invalid screenshots after first field.
- Manual spot checks of `screenshot-0135s.png` after the `ls_left:200` pulse
  and `screenshot-0200s.png` at the end show clean Path to Tenuto field
  visuals with the performance overlay, not loading/black/wrong-window frames.
- Host grade was clean across all `6` snapshots. stdout/stderr were empty,
  no `rpcs3` process remained after the run, and `rg` found no real
  `Access violation`, `VM: Access`, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failure, assertion, unhandled exception, or likely-crashed hit.

Result:

- GPU probe summary: `1,619` records, `2,634.86 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1156`, `too-small=463`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,585.18 MB` and `0x25cc` at `1,049.68 MB`.
- Dynamic MFC fallback timing remains small relative to the whole run:
  `346,759` hits, `228.452 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `6260 / 6260 / 6260 / 0 / 0`,
  retry `6260 / 6260 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- This confirms the refiner's loader-control route can survive one small
  movement pulse under `CleanAfterField`, which is a route-quality step toward
  first-battle proof.
- It is not a speed win and not GPU migration credit. The repeated `0`
  RSX-local result still parks broad SPU-to-Vulkan compute until a scout proves
  RSX-consumed data.
- `tools/ps3_harness_refiner.ps1` now recognizes this valid left200 run and
  advances the next suggestion to exactly one second tiny `ls_left:200` pulse,
  avoiding a duplicate repeat of the same experiment.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Try one second tiny left pulse from this clean loader-control-left200 base,
  still not battle movement and not lane-2 HLE/GPU fast mode:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## 2026-05-23 Loader-Control Left200x2 Visualgate Pass

Question:

- Can the clean loader-control route survive two tiny state-aware left pulses
  under the normal Windows visual gate, without reopening lane-2 HLE/GPU fast
  modes too early?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-140429-cpu4-loader-control-left200x2-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Visual gate passed: all `16` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0138s.png` after the second `ls_left:200`
  pulse and `screenshot-0210s.png` at the end show clean Path to Tenuto field
  visuals with the performance overlay.
- Host grade was clean across all `7` snapshots. stdout/stderr were empty,
  no `rpcs3` process remained after the lab stop, and `rg` found no real
  `Access violation`, `VM: Access`, SIGSEGV/SIGBUS, Vulkan validation/VK_ERROR,
  verification failure, assertion, unhandled exception, or likely-crashed hit.

Result:

- GPU probe summary: `1,681` records, `2,672.88 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1163`, `too-small=518`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,609.27 MB` and `0x25cc` at `1,063.61 MB`.
- Dynamic MFC fallback timing remains small relative to the whole run:
  `351,731` hits, `225.039 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `6892 / 6892 / 6892 / 0 / 0`,
  retry `6892 / 6892 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- This is a second stable movement step from the loader-control base, so the
  route is becoming useful again after the black-overlay/Now Loading failures.
- It is not a speed win and not GPU migration credit. The repeated `0`
  RSX-local result still parks broad SPU-to-Vulkan compute unless a new scout
  proves RSX-consumed data.
- `tools/ps3_harness_refiner.ps1` now recognizes the valid left200x2 run and
  advances the next suggestion to exactly one tiny diagonal micro-pulse instead
  of repeating left200x2.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x2-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

Next:

- Try one tiny diagonal micro-pulse from this clean loader-control-left200x2
  base, still not lane-2 HLE/GPU fast mode:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## 2026-05-23 Loader-Control Left200x2 Diag200 Visualgate Rejection

Question:

- Can the clean loader-control-left200x2 field route survive one tiny diagonal
  `combo:ls_left+ls_down:200` micro-pulse under the normal Windows visual gate?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-141907-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Initial byte-size-only triage was fooled by large cutscene frames, so
  `tools/check_eternal_sonata_windows_visual_gate.ps1` was tightened with a
  sampled color heuristic that rejects large blue/red/dark non-field frames as
  `cutscene-or-nonfield-large-png`.
- With the improved gate, the run is `NO_FIELD_LIKE_SCREENSHOT`, not accepted
  Path to Tenuto. The large screenshots are night/tree or red dialogue
  cutscene frames; later screenshots from `screenshot-0190s.png` onward are
  black/perf-overlay frames with `The PS3 application has likely crashed`.
- Host grade was clean across all `6` snapshots. stdout was empty, no `rpcs3`
  process remained, and stderr contained SPU fatal `Unknown STOP code` lines
  from several `TCX_CellSpursKernel*` threads.

Result:

- GPU probe summary exists but is route-invalid: `1,419` records,
  `2,074.52 MB` observed DMA, `0` RSX-local records, `0` indirect RSX
  overlap records.
- Offload fit: `spu-kernel-hle=1007`, `too-small=412`.
- Hot PCs remain CPU/SPU HLE/codegen candidates: `0x451c` at `1,144.13 MB`
  and `0x25cc` at `930.39 MB`.
- Dynamic MFC fallback timing stayed small relative to the whole run:
  `258,910` hits, `183.660 ms` total.
- Lane 2 counters stayed clean but visually unusable:
  attempts/completed/success/failure/unexpected `10519 / 10519 / 10519 / 0 / 0`,
  retry `10519 / 10519 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- The tiny diagonal route is not a valid next base. It entered a non-field
  cutscene path and then crashed, so no counters from this capture may drive
  lane-2 HLE/GPU decisions.
- The latest actual clean route boundary remains `loader-control-left200x2`.
  Before any diagonal or first-battle rebuilding, re-prove that clean boundary
  under the improved visual gate.
- The repeated `0` RSX-local result still parks broad SPU-to-Vulkan compute
  unless a new scout proves RSX-consumed data.
- `tools/ps3_harness_refiner.ps1` now recognizes
  `cutscene-or-nonfield-large-png` runs and suggests re-proving
  `loader-control-left200x2` instead of repeating diagonal movement.

Classification:

- `failed`, `route-tooling`, `diag200-cutscene-nonfield-crash`,
  `not-comparable-visual`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

Next:

- Re-prove the last clean loader-control-left200x2 route with the improved
  visual gate before adding any diagonal or lane-2 HLE/GPU fast mode:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-confirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## 2026-05-23 Loader-Control Left200x2 Confirm Visualgate Pass

Question:

- After the diagonal `combo:ls_left+ls_down:200` route fell into a non-field
  cutscene and then crashed, can the last clean left200x2 boundary still be
  trusted under the improved visual gate?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-confirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-144243-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate passed: all `16` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0138s.png` after the second `ls_left:200`
  pulse and `screenshot-0210s.png` at the end show clean Path to Tenuto field
  visuals with the performance overlay.
- Host grade was clean across all `7` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.

Result:

- GPU probe summary: `1,691` records, `2,746.23 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1254`, `too-small=437`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,453.57 MB` and `0x25cc` at `1,292.67 MB`.
- Dynamic MFC fallback timing remains small relative to the whole route:
  `331,036` hits, `276.324 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `10976 / 10976 / 10976 / 0 / 0`,
  retry `10976 / 10976 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- The left200x2 route boundary is re-confirmed under the improved color-aware
  visual gate. The diagonal branch remains rejected, but the field base is not
  poisoned by that crash.
- This is route/harness proof, not a speed win and not GPU migration credit.
  The repeated `0` RSX-local result still parks broad SPU-to-Vulkan compute
  unless a new scout proves RSX-consumed data.
- The refiner initially tried to repeat `diag200` after the confirm pass, which
  would have rediscovered the same cutscene/crash. `tools/ps3_harness_refiner.ps1`
  now detects a recent rejected `loader-control-left200x2-diag200` branch and
  blocks repeating it even when the latest left200x2 base is valid.
- The next useful step should use this confirmed field base to build safer
  route control or try one left-only micro-pulse (`left200x3`) that avoids the
  rejected diagonal path; lane-2 HLE/GPU fast modes still need field/menu/first-
  battle visuals before promotion.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x2-confirm-field-clean`,
  not `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate
  candidate.

## 2026-05-23 Loader-Control Left200x3 Visualgate Pass

Question:

- Can the confirmed left200x2 field base survive one more left-only
  `ls_left:200` micro-pulse while avoiding the rejected diagonal branch?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x3-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-145846-cpu4-loader-control-left200x3-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate passed: all `18` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.49 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0141s.png` after the third `ls_left:200`
  pulse and `screenshot-0220s.png` at the end show clean Path to Tenuto field
  visuals with the performance overlay.
- Host grade was clean across all `6` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.

Result:

- GPU probe summary: `1,567` records, `2,503.59 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1170`, `too-small=397`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,305.89 MB` and `0x25cc` at `1,197.70 MB`.
- Dynamic MFC fallback timing remains small relative to the route:
  `293,709` hits, `199.240 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `15927 / 15927 / 15927 / 0 / 0`,
  retry `15927 / 15927 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- The left-only route can advance to three tiny pulses without falling into the
  diagonal cutscene/crash path.
- This is route/harness proof, not a speed win and not GPU migration credit.
  The repeated `0` RSX-local result still parks broad SPU-to-Vulkan compute
  unless a new scout proves RSX-consumed data.
- `tools/ps3_harness_refiner.ps1` now recognizes `loader-control-left200x3`
  as its own newest valid boundary, instead of treating it like a generic
  `left200` run. Current suggestion is one more left-only micro-pulse
  (`left200x4`) while keeping `diag200` and lane-2 HLE/GPU fast modes blocked.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x3-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x4 Visualgate Rejection

Question:

- Can the clean left200x3 field base survive one more left-only `ls_left:200`
  pulse under the visual gate?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x4-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 235 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 13
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-151309-cpu4-loader-control-left200x4-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate failed before accepted field: all `20` screenshots from
  `screenshot-0117s.png` through `screenshot-0230s.png` were
  `black-overlay-small-png` (`57-59 KB`), with no field-like screenshot at or
  before `160s`.
- Manual spot checks of `screenshot-0117s.png` and `screenshot-0230s.png`
  show a character on a black background with the performance overlay, not Path
  to Tenuto field.
- Host grade was clean across all `6` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.

Result:

- GPU probe summary is route-invalid: `1,840` records, `2,136.17 MB` observed
  DMA, `0` RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1096`, `too-small=744`.
- Hot PCs remain CPU/SPU HLE/codegen candidates:
  `0x451c` at `1,221.38 MB` and `0x25cc` at `914.79 MB`.
- Dynamic MFC fallback timing remains small relative to the route:
  `256,632` hits, `255.000 ms` total.
- Lane 2 stayed counter-clean but visually unusable:
  attempts/completed/success/failure/unexpected `9708 / 9708 / 9708 / 0 / 0`,
  retry `9708 / 9708 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- This does not disprove the left200x4 movement itself, because the run was
  black-overlayed before accepted field and before movement evidence was valid.
  Treat all counters from this capture as route-invalid.
- The latest clean route boundary remains `loader-control-left200x3`.
- `tools/ps3_harness_refiner.ps1` now backs off from a latest black-overlay
  run to the newest clean loader-control boundary, instead of resetting all the
  way to no-movement control. Current suggestion is to re-prove
  `loader-control-left200x3` before trying left200x4 again.

Classification:

- `failed`, `route-tooling`, `left200x4-black-overlay-pre-field`,
  `not-comparable-visual`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x3 Reconfirm Visualgate Pass

Question:

- After the left200x4 attempt black-overlayed before accepted field, can the
  newest clean left200x3 boundary still be trusted under `CleanAfterField`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x3-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-161002-cpu4-loader-control-left200x3-reconfirm-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate passed: all `18` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0141s.png` after the third `ls_left:200`
  pulse and `screenshot-0220s.png` at the end show clean Path to Tenuto field
  visuals with the performance overlay.
- Host grade was clean across all `6` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.

Result:

- GPU probe summary: `1,762` records, `2,850.30 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1345`, `too-small=417`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x25cc` at `1,442.67 MB` and `0x451c` at `1,407.63 MB`.
- Dynamic MFC fallback timing remains small relative to the route:
  `321,579` hits, `293.901 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `12188 / 12188 / 12188 / 0 / 0`,
  retry `12188 / 12188 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- The left200x3 boundary is re-confirmed after the black-overlayed x4 capture.
  That previous x4 capture remains invalid evidence, not a movement verdict.
- This is route/harness proof, not a speed win and not GPU migration credit.
  The repeated `0` RSX-local result still parks broad SPU-to-Vulkan compute
  unless a new scout proves RSX-consumed data.
- The refiner now allows one exact left-only `left200x4` retry under
  `CleanAfterField`, while keeping `diag200` and lane-2 HLE/GPU fast modes
  blocked until field/menu/first-battle visuals are clean.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x3-reconfirm-field-clean`,
  not `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate
  candidate.

## 2026-05-23 Loader-Control Left200x4 Visualgate Pass

Question:

- After re-proving the left200x3 boundary, can the exact fourth left-only
  `ls_left:200` pulse survive accepted-field visual gating?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x4-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 235 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 13
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-162652-cpu4-loader-control-left200x4-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate passed: all `20` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0144s.png` after the fourth `ls_left:200`
  pulse and `screenshot-0230s.png` at the end show clean Path to Tenuto field
  visuals with the performance overlay.
- Host grade was clean across all `6` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.

Result:

- GPU probe summary: `1,848` records, `2,942.31 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1400`, `too-small=448`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x25cc` at `1,486.75 MB` and `0x451c` at `1,455.56 MB`.
- Dynamic MFC fallback timing remains small relative to the route:
  `330,025` hits, `277.599 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `9718 / 9718 / 9718 / 0 / 0`,
  retry `9718 / 9718 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- The exact left200x4 movement can be field-clean when started from the
  re-proved left200x3 boundary. The earlier black-overlayed x4 capture remains
  route-invalid, not a contradiction.
- This is route/harness proof, not a speed win and not GPU migration credit.
  The repeated `0` RSX-local result still parks broad SPU-to-Vulkan compute
  unless a new scout proves RSX-consumed data.
- `tools/ps3_harness_refiner.ps1` now recognizes `loader-control-left200x4`
  as its own newest valid boundary, instead of falling back to generic
  `left200`. Current suggestion is one more left-only micro-pulse
  (`left200x5`) while keeping `diag200` and lane-2 HLE/GPU fast modes blocked.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x4-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x5 Visualgate Pass

Question:

- Can the clean left200x4 field base survive one more left-only `ls_left:200`
  pulse under `CleanAfterField`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x5-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 245 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-175727-cpu4-loader-control-left200x5-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate passed: all `22` screenshots were `field-like-large-png`;
  `screenshot-0118s.png` reached accepted Path to Tenuto at `118s`
  (`2.50 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0158s.png` after the fifth `ls_left:200`
  pulse settled and `screenshot-0240s.png` at the end show clean Path to
  Tenuto field visuals with the performance overlay.
- Host grade was clean across all `7` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.

Result:

- GPU probe summary: `1,740` records, `2,683.45 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1240`, `too-small=500`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,542.25 MB` and `0x25cc` at `1,141.19 MB`.
- Dynamic MFC fallback timing remains small relative to the route:
  `341,832` hits, `236.955 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `4992 / 4992 / 4992 / 0 / 0`,
  retry `4992 / 4992 / 0`, next `0 / 0 / 0`, PCs `0xc2c -> 0xcac`.

Reading:

- The left-only route can advance to five tiny pulses without falling into the
  rejected diagonal cutscene path or the black-overlay state.
- This is route/harness proof, not a speed win and not GPU migration credit.
  The repeated `0` RSX-local result still parks broad SPU-to-Vulkan compute
  unless a new scout proves RSX-consumed data.
- `tools/ps3_harness_refiner.ps1` now parses arbitrary `loader-control-left200xN`
  counts and emits the next left-only pulse command generically. Current
  suggestion is `left200x6`, with `diag200` and lane-2 HLE/GPU fast modes still
  blocked until field/menu/first-battle visuals are clean.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x5-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x6 Visualgate Pass

Question:

- Can the clean left200x5 field base survive one more left-only `ls_left:200`
  pulse under `CleanAfterField`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x6-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 255 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 15
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-181904-cpu4-loader-control-left200x6-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate passed: all `24` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0150s.png` after the sixth `ls_left:200`
  pulse and `screenshot-0250s.png` at the end show clean Path to Tenuto field
  visuals with the performance overlay.
- Host grade was clean across all `7` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.

Result:

- GPU probe summary: `2,074` records, `3,345.03 MB` observed DMA, `0`
  RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1530`, `too-small=544`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,918.42 MB` and `0x25cc` at `1,426.61 MB`.
- Dynamic MFC fallback timing remains small relative to the route:
  `424,739` hits, `301.682 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `8887 / 8887 / 8887 / 0 / 0`,
  retry `0xc2c -> 0xcac`.

Reading:

- The left-only route can advance to six tiny pulses without falling into the
  rejected diagonal cutscene path or the black-overlay state.
- This is route/harness proof, not a speed win and not GPU migration credit.
  The repeated `0` RSX-local result still parks broad SPU-to-Vulkan compute
  unless a new scout proves RSX-consumed data.
- `tools/ps3_harness_refiner.ps1` now treats `loader-control-left200x6` as
  the newest valid boundary. Current suggestion is `left200x7`, with
  `diag200` and lane-2 HLE/GPU fast modes still blocked until
  field/menu/first-battle visuals are clean.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x6-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x7 Fatal Rejection

Question:

- Can the clean left200x6 field base survive one more left-only `ls_left:200`
  pulse under `CleanAfterField`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x7-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 265 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 16
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-183422-cpu4-loader-control-left200x7-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Host grade was clean across all `7` snapshots. stdout was empty, no
  `rpcs3` process remained after the lab stop, and stderr contained a real
  access violation.
- The byte-size visual gate reported `FIELD_LIKE_PRESENT`: `26`
  `field-like-large-png` screenshots, first accepted screenshot
  `screenshot-0117s.png` at `117s`, and `0` small invalid screenshots after
  first field.
- Manual spot checks override that triage: `screenshot-0153s.png` after the
  seventh `ls_left:200` pulse and `screenshot-0260s.png` at the end show the
  RPCS3 `The PS3 application has likely crashed` overlay plus a corrupted /
  frozen field image.
- Fatal scan hit `rpcs3.stderr.txt` and `RPCS3.log`:
  `PPU[0x100000c] ... VM: Access violation reading location 0x40` at
  `0x002aedd0`.

Result:

- GPU probe summary is invalid for promotion: `1,138` records, `1,491.74 MB`
  observed DMA, `0` RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=675`, `too-small=463`.
- Hot PCs still point to CPU/SPU HLE/codegen, not broad GPU compute:
  `0x451c` at `885.67 MB` and `0x25cc` at `606.06 MB`.
- Dynamic MFC fallback timing was `192,205` hits and `120.372 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `5695 / 5695 / 5695 / 0 / 0`,
  retry `0xc2c -> 0xcac`, but these counters are not actionable because the
  run crashed.

Reading:

- The seventh left-only micro-pulse is the current boundary failure. Do not
  extend to `left200x8` from this evidence.
- This also exposed a harness gap: byte-size/color screenshot triage can pass
  a large field screenshot while the RPCS3 fatal overlay is present. The
  refiner now reads stderr/stdout/RPCS3.log fatal patterns and classifies such
  runs as `failed-fatal-log`.
- Current refiner suggestion is to re-prove
  `loader-control-left200x6-reconfirm-visualgate-windows`, or repair route
  control, before adding another movement pulse. `diag200` and lane-2 HLE/GPU
  fast modes remain blocked.

Classification:

- `failed`, `route-tooling`, `loader-control-left200x7-fatal-access-violation`,
  `not-comparable-fatal`, not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x6 Reconfirm Black-Overlay Rejection

Question:

- After the `left200x7` fatal access violation, can the newest clean
  `left200x6` boundary be re-proved under `CleanAfterField`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x6-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 255 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 15
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-185249-cpu4-loader-control-left200x6-reconfirm-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Host grade was clean across all `7` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan included
  `Unknown STOP code` plus access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, and unhandled-exception patterns with no hits.
- Visual gate failed: all `24` screenshots were `black-overlay-small-png`,
  from `screenshot-0117s.png` through `screenshot-0250s.png`; no field-like
  screenshot appeared by `160s`.
- Manual spot checks of `screenshot-0117s.png` and `screenshot-0250s.png`
  show a black screen with only the performance overlay, not Path to Tenuto.

Result:

- GPU probe summary is route-invalid: `2,039` records, `1,961.11 MB`
  observed DMA, `0` RSX-local records, `0` indirect RSX overlap records.
- Offload fit: `too-small=1086`, `spu-kernel-hle=953`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,196.20 MB` and `0x25cc` at `764.91 MB`.
- Dynamic MFC fallback timing was `245,151` hits and `191.155 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `6156 / 6156 / 6156 / 0 / 0`,
  retry `0xc2c -> 0xcac`, but these counters are not actionable because the
  visual route is invalid.

Reading:

- The x6 boundary remains the newest clean boundary only because the earlier
  `20260523-181904...` pass was clean; this reconfirm attempt itself is
  invalid.
- Do not extend to `left200x8`, and do not start lane-2 HLE/GPU fast mode from
  these counters.
- The current refiner still points to re-proving or repairing the x6 boundary.
  Repeated `0` RSX-local evidence continues to park broad SPU-to-Vulkan compute
  unless a future scout proves RSX-consumed data.

Classification:

- `failed`, `route-tooling`, `loader-control-left200x6-reconfirm-black-overlay`,
  `not-comparable-visual`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Harness Refiner Reconfirm Backoff Patch

Question:

- After the `left200x6` reconfirm black-overlayed, can the process harness
  avoid looping the same invalid command and choose the safer next proof?

Change:

- Updated `tools/ps3_harness_refiner.ps1` to detect when the newest run is a
  `loader-control` reconfirm that black-overlayed before accepted field.
- Updated `.agents/skills/ps3-continual-harness-refiner/SKILL.md` so failed
  reconfirms back off one movement pulse, or repair route control, instead of
  repeating the same failed command.

Verification:

```powershell
$path = "C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\tools\ps3_harness_refiner.ps1"
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
```

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Result:

- Parser validation passed.
- Refiner report:
  `debug-captures/windows-lab/_ps3-harness-refiner-latest.md`.
- The newest x6 reconfirm remains `failed-black-overlay-visual`; the x7 run is
  now explicitly `failed-fatal-log`; three invalid visual/fatal runs still had
  clean lane-2 counters, so HLE/GPU fast modes stay blocked.
- The next action is no longer the same x6 reconfirm and not x8. It now backs
  off to:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x5-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 245 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14
```

Reading:

- This prevents duplicate invalid heartbeat work and keeps the Windows-only
  sprint pointed at route proof before more movement or GPU/HLE lane changes.
- Repeated `0` RSX-local evidence still parks broad SPU-to-Vulkan compute.

Classification:

- `process-harness`, `route-tooling`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x5 Reconfirm Visualgate Pass

Question:

- After the `left200x6` reconfirm black-overlayed, can the safer backed-off
  `left200x5` boundary be re-proved under `CleanAfterField`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x5-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 245 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-191818-cpu4-loader-control-left200x5-reconfirm-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- The lab stopped RPCS3 at the intended `245s`, but the outer shell timeout
  fired before the sprint wrapper completed its own summary stage. I recovered
  by running the visual gate, fatal scan, image spot checks, and a streaming
  PowerShell log aggregation separately.
- Visual gate passed: all `22` screenshots were `field-like-large-png`;
  `screenshot-0117s.png` reached accepted Path to Tenuto at `117s`
  (`2.50 MB`), the deadline check passed by `160s`, and there were `0`
  invalid screenshots after first field.
- Manual spot checks of `screenshot-0147s.png` after the fifth `ls_left:200`
  pulse and `screenshot-0240s.png` at the end show clean Path to Tenuto field
  visuals with no black overlay, crash overlay, or cutscene route drift.
- Host grade was clean across all `7` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after recovery, and the fatal scan found no
  `Unknown STOP code`, access, VM, SIGSEGV/SIGBUS, Vulkan, verification,
  assertion, likely-crashed, or unhandled-exception hits.

Result:

- Manual GPU/DMA aggregation from `RPCS3.log`: `1,978` candidate rows,
  `3,314.40 MB` observed DMA, `0` RSX-local traffic records, `0` RSX-local
  bytes, `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1511`, `too-small=467`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,756.01 MB` and `0x25cc` at `1,558.39 MB`.
- Dynamic MFC fallback: `395,966` hits, all successful, `786.22 MB`, and
  `257.992 ms` total; PC mix `0x451c=365,305 / 228.864 ms`,
  `0x25cc=30,661 / 29.128 ms`.
- MFC wait probe: `17,791,339` reads, all fast, `0` blocking reads,
  `1,966,990` TagStat and `15,824,349` AtomicStat reads.
- A minimal `eternal-sonata-gpu-probe-summary.md` was written for this run so
  the refiner can see `0` RSX-local and the offload fit without waiting on the
  full summarizer's huge CSV path.

Reading:

- The backed-off x5 boundary is clean again. This validates the refiner's
  "do not loop a failed reconfirm" rule, but it does not re-promote x6 by
  itself.
- Repeated `0` RSX-local evidence continues to park broad SPU-to-Vulkan compute
  unless a future scout proves RSX-consumed data.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8` now treats this x5 reconfirm as
  the newest valid route and suggests exactly one x6 left-only micro-pulse with
  `CleanAfterField`; `left200x8`, `diag200`, and lane-2 HLE/GPU fast modes stay
  blocked.

Classification:

- `analysis`, `route-tooling`, `loader-control-left200x5-reconfirm-field-clean`,
  not `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate
  candidate.

## 2026-05-23 Loader-Control Left200x6 Reretry Black-Overlay Rejection

Question:

- After the backed-off `left200x5` reconfirm passed, can a single x6
  left-only retry prove a stable six-pulse moving field boundary?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x6-reretry-after-x5-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 255 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 15
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-193616-cpu4-loader-control-left200x6-reretry-after-x5-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Host grade was clean across all `7` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained after the lab stop, and the fatal scan found no
  access violation, STOP code, SIGSEGV/SIGBUS, likely-crashed overlay,
  assertion, or unhandled-exception hit.
- Visual gate failed: all `24` screenshots from `screenshot-0117s.png`
  through `screenshot-0250s.png` were `black-overlay-small-png` around
  `31-32 KB`, with no field-like screenshot by `160s`.
- Manual checks of `screenshot-0117s.png` and `screenshot-0250s.png` show a
  black screen with the performance overlay, not Path to Tenuto.

Result:

- GPU probe summary is route-invalid: `1,809` records, `1,830.97 MB`
  observed DMA, `0` RSX-local traffic records, and `0` indirect RSX overlap
  records.
- Offload fit: `spu-kernel-hle=931`, `too-small=878`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,006.27 MB` and `0x25cc` at `824.71 MB`.
- Dynamic MFC fallback timing was `209,498` hits and `182.763 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `7529 / 7529 / 7529 / 0 / 0`,
  retry `0xc2c -> 0xcac`, but these counters remain invalid because the visual
  route is black.

Reading:

- The x6 boundary is not stable enough to extend. We now have one clean x6
  pass, one x6 reconfirm black-overlay failure, and one x6 reretry black-overlay
  failure.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8` now recommends re-proving the
  newest clean x5 boundary again before any more left-only movement. It does
  not suggest x7, x8, diagonal movement, or lane-2 HLE/GPU fast mode.
- Repeated `0` RSX-local evidence continues to park broad SPU-to-Vulkan compute
  unless a future scout proves RSX-consumed data.

Classification:

- `failed`, `route-tooling`,
  `loader-control-left200x6-reretry-after-x5-black-overlay`,
  `not-comparable-visual`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Loader-Control Left200x5 Second Reconfirm Visualgate Pass

Question:

- After the x6 reretry black-overlayed, can the x5 route boundary still be
  re-proved cleanly, and should the refiner keep trying x6 automatically?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x5-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 245 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14
```

Verification:

- Run directory:
  `debug-captures/windows-lab/20260523-204735-cpu4-loader-control-left200x5-reconfirm-visualgate-windows-windows/`.
- RPCS3 stayed on screen 1 / `\\.\DISPLAY2`; CPU affinity `0x0F` was
  applied.
- Visual gate passed: all `22` screenshots were `field-like-large-png`, first
  accepted field was `screenshot-0117s.png` at `117s` (`2.50 MB`), and there
  were `0` invalid screenshots after first field.
- Manual spot checks of `screenshot-0147s.png` after the fifth left pulse and
  `screenshot-0240s.png` at the end show clean Path to Tenuto field visuals
  with no black overlay or crash overlay.
- Host grade was clean across `7` snapshots. stdout/stderr were empty, no
  `rpcs3` process remained, and fatal scan found no real access violation,
  STOP code, SIGSEGV/SIGBUS, likely-crashed overlay, assertion, or unhandled
  exception.

Result:

- GPU probe summary: `1,943` records, `3,149.80 MB` observed DMA, `0`
  RSX-local traffic records, and `0` indirect RSX overlap records.
- Offload fit: `spu-kernel-hle=1493`, `too-small=450`.
- Hot PCs remain CPU/SPU HLE/codegen candidates, not broad GPU compute:
  `0x451c` at `1,586.63 MB` and `0x25cc` at `1,563.17 MB`.
- Dynamic MFC fallback timing was `362,680` hits and `295.515 ms` total.
- Lane 2 stayed clean by counters:
  attempts/completed/success/failure/unexpected `7788 / 7788 / 7788 / 0 / 0`,
  retry `0xc2c -> 0xcac`.

Reading:

- x5 is still clean. x6 is now explicitly unstable: one clean x6 pass, then two
  black-overlay x6 failures in the recent window.
- Repeated `0` RSX-local evidence continues to park broad SPU-to-Vulkan compute
  unless a future scout proves RSX-consumed data.
- The refiner was patched so a lower-boundary pass no longer causes an
  automatic rerun of the same next movement count after that count has failed
  twice recently. It now blocks automatic x6 movement and asks for route-control
  repair or SPU kernel HLE/codegen/verifier analysis.

Classification:

- `analysis`, `route-tooling`,
  `loader-control-left200x5-second-reconfirm-field-clean`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 Harness Refiner Repeated-Next-Failure Patch

Question:

- Can the refiner avoid oscillating between clean x5 reconfirms and repeated
  black-overlay x6 reruns?

Change:

- Updated `tools/ps3_harness_refiner.ps1` to count failures for the next
  loader-control movement count. If the next count has already failed twice in
  the recent window, the refiner blocks an automatic rerun and asks for
  route-control repair or SPU kernel HLE/codegen/verifier analysis.
- Updated `.agents/skills/ps3-continual-harness-refiner/SKILL.md` with the
  repeated-next-failure rule.

Verification:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\ps3_harness_refiner.ps1), [ref]$tokens, [ref]$errors) | Out-Null
```

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Result:

- Parser validation passed.
- Refiner report:
  `debug-captures/windows-lab/_ps3-harness-refiner-latest.md`.
- The next action is now:
  `Do not repeat loader-control-left200x6. It failed 2 time(s) in the recent
  window after a lower clean boundary; repair route control or switch to SPU
  kernel HLE/codegen/verifier analysis before another movement run.`
- The suggested command is intentionally only a comment, not another automatic
  movement capture.

Classification:

- `process-harness`, `route-tooling`, duplicate-run prevention, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Candidate Atlas From Valid Field Captures

Question:

- With x6 movement now blocked by repeated visual failures, which stable SPU
  hot buckets should drive the next Windows-only HLE/codegen/verifier step?

Change:

- Added `tools/summarize_eternal_sonata_spu_hle_candidates.ps1`.
- The tool reads recent Windows capture folders, keeps only runs whose
  `eternal-sonata-windows-visual-gate-summary.md` reports
  `FIELD_LIKE_PRESENT`, aggregates `eternal-sonata-gpu-probe-records.csv`, and
  writes:
  - `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.md`
  - `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.csv`

Verification:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_spu_hle_candidates.ps1), [ref]$tokens, [ref]$errors) | Out-Null
```

```powershell
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 12 -Top 12
```

Result:

- Parser validation passed.
- The atlas scanned `12` recent Windows run directories and used `8` visually
  valid field runs.
- Top bucket: PC `0x25cc`, `CellSpursKernelGroup` /
  `CellSpursKernel0`, `spu-kernel-hle`, `tiny-dispatch-trap`, `6223`
  records, `9.91 GB` total, `8` runs seen, `0 B` RSX-local.
- Second bucket: PC `0x451c`, `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`, `spu-kernel-hle`, `tiny-dispatch-trap`, `3883`
  records, `9.53 GB` total, `8` runs seen, `0 B` RSX-local.
- The repeated-pattern table is dominated by stable `0x25cc`
  `CellSpursKernel0` patterns across all `8` valid runs.

Reading:

- This turns the repeated zero-RSX-local scout evidence into a ranked SPU
  HLE/codegen target list instead of another route-control loop.
- Broad SPU-to-Vulkan compute remains parked for these jobs because no valid
  field bucket showed RSX-local bytes.
- Next Windows-only experiment should inspect/specialize/verify the `0x25cc`
  `CellSpursKernel0` bucket first, then `0x451c`, with fast mode disabled until
  a CPU-vs-candidate verifier is clean.

Classification:

- `analysis`, `spu-hle-targeting`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Next-Target Dossier

Question:

- Can the valid-field atlas name the first verifier target precisely enough to
  start a narrow SPU HLE/codegen experiment instead of another broad scout?

Change:

- Extended `tools/summarize_eternal_sonata_spu_hle_candidates.ps1` with a
  `Next HLE Verifier Target` section.
- The new section picks the top `spu-hle-codegen-priority` bucket, finds the
  newest valid run's matching SPU disassembly window, lists the top repeated
  pattern signatures for that bucket, and writes the first verify-mode
  contract.

Verification:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_spu_hle_candidates.ps1), [ref]$tokens, [ref]$errors) | Out-Null
```

```powershell
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 12 -Top 12
```

Result:

- Parser validation passed.
- The generated latest atlas now selects PC `0x25cc`,
  `CellSpursKernelGroup` / `CellSpursKernel0`, image
  `0x958dfe208b686622`.
- Shape remains `9.91 GB` total over `6223` records, `1.45 GB` GET,
  `8.46 GB` PUT, `0 B` list GET, `0 B` RSX-local, and max job `5.64 MB`.
- Stability remains `8` valid runs, `252` pattern signatures, and one
  max-DMA EA value.
- Latest disasm window:
  `debug-captures/windows-lab/20260523-204735-cpu4-loader-control-left200x5-reconfirm-visualgate-windows-windows/spu-images/BLUS30161-spu-image-958dfe208b686622-entry-00818-pc-025cc-group-CellSpursKernelGroup-spu-0-CellSpursKernel0.disasm.txt`.
- The cue around `0x25cc` builds a local command descriptor, calls `0x28d0`,
  then waits on `MFC_WrTagMask`, `MFC_WrTagUpdate ALL`, and
  `MFC_RdTagStat`. This reinforces a verify-gated SPU/MFC kernel target, not
  a render-side GPU residency target.

Reading:

- First verifier gate should be title `BLUS30161`, image
  `0x958dfe208b686622`, group `CellSpursKernelGroup`, SPU
  `CellSpursKernel0`, PC `0x25cc`, and the stable `0x9e4000` max-DMA EA
  family observed in recent valid runs.
- Verify mode should record the MFC command descriptor and touched GET/PUT
  ranges, run stock behavior, compare the candidate result, and leave fast mode
  disabled until repeated clean field/menu/battle proof exists.
- Because this bucket still has `0 B` RSX-local traffic, it is not
  `gpu-migration-credit`; the route remains SPU HLE/codegen/verifier first.

Classification:

- `analysis`, `spu-hle-target-dossier`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Atlas Fatal-Clean Correction

Question:

- Should field-like screenshots be enough for the HLE candidate atlas, or must
  fatal logs also exclude a run?

Change:

- Updated `tools/summarize_eternal_sonata_spu_hle_candidates.ps1` so valid
  atlas runs require both `FIELD_LIKE_PRESENT` and no fatal/crash/access
  signature in `rpcs3.stderr.txt`, `rpcs3.stdout.txt`, `RPCS3.log`, or
  `windows-rpcs3-lab.txt`.
- Added an `Excluded Runs` section to the atlas.
- Optimized the `RPCS3.log` fatal check to scan the tail instead of the whole
  large log; this kept the latest atlas run around `9.0s` after the fix.

Verification:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_spu_hle_candidates.ps1), [ref]$tokens, [ref]$errors) | Out-Null
```

```powershell
Measure-Command { .\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 12 -Top 12 | Out-Null }
```

Result:

- Parser validation passed.
- Latest atlas now uses `7` fatal-clean field runs instead of `8`.
- It excludes
  `20260523-183422-cpu4-loader-control-left200x7-visualgate-windows-windows`
  because `rpcs3.stderr.txt` reports:
  `VM: Access violation reading location 0x40`.
- Corrected top bucket: PC `0x25cc`, `CellSpursKernelGroup` /
  `CellSpursKernel0`, `spu-kernel-hle`, `tiny-dispatch-trap`, `5849`
  records, `9.32 GB` total, `7` valid runs, `0 B` RSX-local.
- Corrected second bucket: PC `0x451c`, `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`, `spu-kernel-hle`, `tiny-dispatch-trap`, `3582`
  records, `8.89 GB` total, `7` valid runs, `0 B` RSX-local.

Reading:

- The first HLE verifier target does not change: `0x25cc`
  `CellSpursKernel0` remains the clean top bucket.
- The atlas is now safer for future automation because a fatal-but-field-like
  capture cannot inflate HLE/codegen priority totals.
- This is harness hygiene and targeting evidence, not GPU migration and not a
  speed win.

Classification:

- `process-harness`, `spu-hle-targeting`, `fatal-clean-atlas`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Verifier Source Hook Map

Question:

- Where should the first Windows-only `0x25cc` HLE/codegen verifier attach so
  it sees both runtime MFC commands and LLVM-inlined constant MFC commands?

Source inspection:

```powershell
rg -n "RPCS3_ES_MFC|MFC_Cmd|process_mfc_cmd|do_dma_transfer|do_dma_check" rpcs3\Emu\Cell -g "*.cpp" -g "*.h"
```

Key sites in local `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`:

- `rpcs3/Emu/Cell/SPUThread.cpp`
  - Existing env gates live near the top for `RPCS3_ES_DMA_SUPERPATH`,
    `RPCS3_ES_MFC_LADDER`, `RPCS3_ES_KERNEL_CAPSULE`, and
    `RPCS3_ES_RESERVATION_LOOP`.
  - `try_es_mfc_25cc_ladder()` is already the narrowest concrete `0x25cc`
    candidate gate: title `BLUS30161`, image `0x958dfe208b686622`,
    `pc == 0x25cc`, `MFC_GET_CMD`, tag `31`, size `0x4000`, EA below RSX
    local memory, LS offset family `0x3000`, no MFC transfer shuffling, and
    no accurate DMA.
  - `process_mfc_cmd()` records current MFC shape/reservation state, then
    handles ordinary GET/PUT through `do_dma_check()` and `do_dma_transfer()`.
  - `set_ch_value(MFC_Cmd)` has the dynamic command timing hook and calls
    `process_mfc_cmd()`.
- `rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`
  - `is_es_mfc_llvm_channel_probe_enabled()` already keeps LLVM-side MFC wait
    probes alive for ladder/capsule/reservation modes.
  - The constant `WRCH MFC_Cmd` path can inline GET/PUT copies in LLVM when the
    command and size are known, instead of calling `process_mfc_cmd()`.
  - The same block falls back to `exec_mfc_cmd()` when list DMA, atomics, debug
    mode, MMIO, barriers/fences, or non-constant command shapes require the C++
    path.
- `rpcs3/Emu/Cell/lv2/sys_spu.cpp`
  - Existing summary rows already include MFC ladder, dynamic command, list
    transfer, wait, and wait-PC probe counters. This is the right place to emit
    a future `Eternal Sonata SPU HLE verifier:` row once both runtime and LLVM
    paths have counters.

Reading:

- A runtime-only verifier is insufficient because the hot `0x25cc` route can be
  represented by LLVM-emitted direct copies. That path may never pass through
  `process_mfc_cmd()` for the ordinary GET/PUT case.
- The first verify-only implementation should add a new
  `RPCS3_ES_SPU_HLE_VERIFY=profile|verify` style gate that records a shared
  candidate row from both:
  - runtime `try_es_mfc_25cc_ladder()` / `process_mfc_cmd()`; and
  - LLVM constant `MFC_Cmd` GET/PUT copy generation before the direct-copy
    block.
- Fast mode should stay absent. The first pass should only prove that the
  verifier sees the same `0x25cc` command family from both paths and can
  compare touched LS/EA ranges without changing behavior.

Classification:

- `analysis`, `source-hook-map`, `spu-hle-targeting`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Verifier Scaffold

Question:

- Can the Windows source lab grow a verify-only `0x25cc` HLE counter that sees
  both ordinary runtime MFC commands and LLVM-inlined constant MFC direct
  copies before any fast path exists?

Change:

- Updated local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` only.
- Added `RPCS3_ES_SPU_HLE_VERIFY` instrumentation in:
  - `rpcs3/Emu/Cell/SPUThread.h`
  - `rpcs3/Emu/Cell/SPUThread.cpp`
  - `rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`
  - `rpcs3/Emu/Cell/lv2/sys_spu.cpp`
- The runtime path records candidates before the existing `0x25cc` ladder
  check in `process_mfc_cmd()`.
- The LLVM path records candidates from the direct-copy `WRCH MFC_Cmd` block
  before emitted loads/stores, so it does not miss copies that bypass
  `process_mfc_cmd()`.
- The summary row is `Eternal Sonata SPU HLE verifier:` and splits
  `runtime_hits` from `llvm_hits`.

Gate:

- Title `BLUS30161`.
- SPU image `0x958dfe208b686622`.
- PC `0x25cc`.
- `MFC_GET_CMD`, tag `31`, size `0x4000`.
- EA below RSX local memory.
- LS offset family `0x3000`.
- No MFC transfer shuffling and no accurate DMA.
- Fast mode is absent; this is only a verifier/counter scaffold.

Verification:

```powershell
cmake --build 'C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc' --config Release --target rpcs3 --parallel 6
```

Result:

- First build attempt failed in `SPULLVMRecompiler.cpp` because the verifier
  call tried to `zext<u32>` already-`u32` LLVM values for `lsa` and `eal`.
- Fixed the call to pass `lsa.value` and `eal.value`.
- Second build succeeded and produced
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\rpcs3.exe`.

Reading:

- This is a necessary source scaffold for the first clean `0x25cc` HLE/codegen
  verifier.
- It is not a speed win, not GPU migration credit, and not 200% gate evidence
  because no routed field/menu/battle capture has run with the new env gate yet.
- Next Windows-only step: run a field capture with `RPCS3_ES_SPU_HLE_VERIFY`
  enabled, confirm `runtime_hits` and/or `llvm_hits`, then teach the summarizer
  to parse the new row.

Classification:

- `source-verifier-scaffold`, `build-pass`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Verifier Harness Support

Question:

- Can the Windows sprint harness run and summarize the new
  `RPCS3_ES_SPU_HLE_VERIFY` scaffold without ad hoc environment-variable
  setup?

Change:

- Added `-EternalSonataSpuHleVerify Verify` to:
  - `tools/windows_rpcs3_lab.ps1`
  - `tools/eternal_sonata_speed_sprint.ps1`
- The Windows lab now logs the verifier mode, sets/resets
  `RPCS3_ES_SPU_HLE_VERIFY`, allocates the usual `spu-images` dump directory,
  and runs the probe summarizer when the verifier is enabled.
- Extended `tools/summarize_eternal_sonata_gpu_probe.ps1` to parse
  `Eternal Sonata SPU HLE verifier:` rows, export
  `eternal-sonata-spu-hle-verify-profile.csv`, and report `runtime_hits` vs
  `llvm_hits` in a `SPU HLE Verifier` section.

Verification:

```powershell
$scripts = @(
  'tools\windows_rpcs3_lab.ps1',
  'tools\eternal_sonata_speed_sprint.ps1',
  'tools\summarize_eternal_sonata_gpu_probe.ps1'
)
foreach($script in $scripts){
  $tokens=$null
  $errors=$null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script), [ref]$tokens, [ref]$errors) | Out-Null
}
```

```powershell
git diff --check -- tools/windows_rpcs3_lab.ps1 tools/eternal_sonata_speed_sprint.ps1 tools/summarize_eternal_sonata_gpu_probe.ps1
```

```powershell
.\tools\summarize_eternal_sonata_gpu_probe.ps1 -RunDir TEMP_HLE_FIXTURE -LogPath TEMP_HLE_FIXTURE\RPCS3.log -Top 5
```

Result:

- All three PowerShell parser checks passed.
- `git diff --check` passed with only the repo's usual LF-to-CRLF warnings.
- A synthetic verifier log row produced:
  - `SPU HLE verifier records: 1`
  - `Hits: 4`
  - `Runtime hits: 1`
  - `LLVM direct-copy hits: 3`
  - `eternal-sonata-spu-hle-verify-profile.csv`

Reading:

- The next heartbeat can run the real Windows field route without manually
  setting process env vars.
- This is harness support only. No gameplay route, screenshot, or FPS result
  exists for the verifier yet.

Next command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -EternalSonataSpuHleVerify Verify -WindowsInputBackend PadApi -WindowsGameScreen 1 -MaxSeconds 170 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4 -WindowsVisualGate FieldLike
```

Classification:

- `harness-support`, `parser-pass`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Verifier Field Capture

Question:

- Does the verify-only `RPCS3_ES_SPU_HLE_VERIFY` scaffold see the real
  Eternal Sonata field `0x25cc` target during a clean Windows route?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -EternalSonataSpuHleVerify Verify -WindowsInputBackend PadApi -WindowsGameScreen 1 -MaxSeconds 170 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4 -WindowsVisualGate FieldLike
```

Run:

- `debug-captures/windows-lab/20260523-215127-eternal-sonata-field-stock-qualcomm-windows`
- RPCS3 moved to `\\.\DISPLAY2`, input backend `PadApi`.
- Host contention stayed `clean` across `5` snapshots.
- Visual gate: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshots/screenshot-0117s.png` at `117s`, all `6` screenshots
  field-like by the triage gate.
- Manual screenshot spot check: `screenshot-0117s.png` and
  `screenshot-0165s.png` show the correct Path to Tenuto field with no obvious
  black-overlay/loading/wrong-window issue.
- Fatal/crash scan found no access violation, unhandled exception, assertion,
  SIGBUS/SIGSEGV, Vulkan error, or verification failure lines.

Counters:

- GPU probe records: `1283`.
- Total observed DMA bytes: `1,509.44 MB`.
- Direct RSX-local traffic: `0` records / `0 B`.
- Indirect RSX-resource overlap: `0` records.
- Offload fit mix: `spu-kernel-hle=808`, `too-small=475`.
- Hot PCs: `0x25cc` sum `972.26 MB`; `0x451c` sum `537.18 MB`.

SPU HLE verifier:

- Verifier records: `611`.
- Hits: `9153`.
- Runtime hits: `9153`.
- LLVM direct-copy hits: `0`.
- Candidate bytes: `143.02 MB`.
- All verifier hits were `pc=0x25cc`, `MFC_GET_CMD` / observed `cmd=0x40`,
  tag `31`, size `0x4000`, `CellSpursKernel0`, image
  `0x958dfe208b686622`.
- Dominant shape: `610` rows at `lsa=0x3b000`, `eal=0xa1c000`; one early row
  at `lsa=0xb000`, `eal=0x4f8b80`.

Reading:

- The runtime verifier is real and is seeing the clean `0x25cc` SPU-kernel HLE
  target in a visually valid field route.
- The LLVM direct-copy verifier hook stayed quiet in this route. That means the
  immediate next source step should be to inspect whether this path is not
  using LLVM direct-copy for the gated command, or whether the LLVM hook is too
  narrow.
- This remains a CPU/SPU HLE/codegen lane. The capture again shows zero
  RSX-local traffic, so broad SPU-to-Vulkan compute stays parked unless a later
  scout proves repeated RSX-consumed data.

Next action:

- Windows-only source analysis around the `0x25cc` LLVM direct-copy gate and
  runtime `0x3b000 -> 0xa1c000` shape. Add a narrower shadow verifier/HLE
  contract before any fast mode.

Classification:

- `spu-hle-verifier-field-pass`, `runtime-visibility-pass`,
  `llvm-direct-copy-miss`, not `gpu-migration-credit`, not
  `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Verifier Dynamic-Command Explanation

Question:

- Did the LLVM direct-copy verifier miss the hot `0x25cc` path, or is this
  field route using a dynamic MFC command path that never enters that LLVM
  direct-copy block?

Source/log finding:

- `rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp` records the runtime verifier
  before `try_es_mfc_25cc_ladder()` in `process_mfc_cmd()`.
- `rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp` records the LLVM
  verifier only from the constant `WRCH MFC_Cmd` direct-copy block.
- The real field log contains:
  - `RPCS3.log:10715`: `SPU: [0x25cc] MFC_Cmd: $11 is not a constant`
  - `RPCS3.log:7923`: `SPU: [0x451c] MFC_Cmd: $12 is not a constant`
- Therefore the hot field path is not a silent direct-copy miss. It is using a
  dynamic MFC command and falling through runtime handling, which matches
  `runtime_hits=9153` and `llvm_hits=0`.

Harness change:

- Extended `tools/summarize_eternal_sonata_gpu_probe.ps1` to count
  `MFC_Cmd: $REG is not a constant` compiler fallback warnings.
- Added an `SPU HLE Shape Summary` to collapse repeated verifier rows by
  path/PC/cmd/tag/size/LSA/EA/group/SPU/image.
- Added an `SPU HLE Compiler Fallback Hints` table so future captures explain
  whether zero `llvm_hits` means dynamic-command fallback or missing coverage.

Verification:

```powershell
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path 'tools\summarize_eternal_sonata_gpu_probe.ps1'),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
```

```powershell
.\tools\summarize_eternal_sonata_gpu_probe.ps1 `
  -RunDir 'debug-captures\windows-lab\20260523-215127-eternal-sonata-field-stock-qualcomm-windows' `
  -Top 12
```

Result:

- Parser check passed.
- The summary now reports `SPU HLE non-constant MFC warnings: 5`.
- Dominant shape: `610` records, `9150` hits, `9150` runtime hits, `0` LLVM
  hits, `142.97 MB`, path `1`, `pc=0x25cc`, `cmd=0x40`, tag `31`, size
  `0x4000`, `lsa=0x3b000`, `eal=0xa1c000`, `CellSpursKernel0`, image
  `0x958dfe208b686622`.
- Compiler fallback hints include `0x25cc` using `$11` and `0x451c` using
  `$12`, each at the real log line above.

Reading:

- Do not chase the LLVM direct-copy fast path for this field route unless a
  later capture shows nonzero `llvm_hits`.
- The sharper next Windows-only target is a dynamic-command shadow verifier/HLE
  contract for the stable runtime shape `0x25cc`, `0x40`, `tag=31`,
  `size=0x4000`, `0x3b000 -> 0xa1c000`.
- The SPU disasm focus PC is still useful for image/route identity, but the
  runtime PC tag does not mean the shown focus-window instruction itself is the
  `wrch`; keep this ambiguity explicit in future notes.

Classification:

- `analysis`, `harness-support`, `dynamic-command-hle-target`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Shadow Contract Field Capture

Question:

- For the stable runtime `0x25cc` shape, is the exact
  `0x3b000 -> 0xa1c000` GET a clean copy contract, and does it show enough
  redundancy to justify a later guarded HLE/skip verifier?

Source change:

- Added a build-passing verify-only `Eternal Sonata SPU HLE shadow verifier:`
  row in local `rpcs3-upstream`.
- It is gated by the existing `RPCS3_ES_SPU_HLE_VERIFY` switch and only records
  the exact shape:
  - title `BLUS30161`
  - image `0x958dfe208b686622`
  - `pc=0x25cc`
  - `cmd=0x40`
  - tag `31`
  - size `0x4000`
  - `lsa=0x3b000`
  - `eal=0xa1c000`
- For that shape, it hashes source, destination-before, and destination-after,
  then records output match/mismatch and whether the destination changed.
- No fast path exists.

Build verification:

```powershell
cmake --build 'C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc' `
  --config Release `
  --target rpcs3 `
  --parallel 6
```

Result:

- Build succeeded and produced
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\rpcs3.exe`.

Field command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-contract-field-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike
```

Run:

- `debug-captures/windows-lab/20260523-222320-hle-shadow-contract-field-windows-windows`
- RPCS3 moved to `\\.\DISPLAY2`, input backend `PadApi`.
- Host contention stayed `clean` across `5` snapshots.
- Visual gate: `FIELD_LIKE_PRESENT`.
- First field-like screenshot: `screenshots/screenshot-0117s.png` at `117s`.
- All `6` screenshots were classified `field-like-large-png`; invalid
  screenshots after first field-like: `0`.
- Manual screenshot spot check: `screenshot-0117s.png` and
  `screenshot-0165s.png` show the correct Path to Tenuto field with no obvious
  black-overlay/loading/wrong-window issue.
- Refined fatal/crash scan found no real access violation, unhandled exception,
  assertion failure, SIGBUS/SIGSEGV, verification failure, Vulkan error, or
  fatal lines. The generic `Show fatal error hints: false` config line is not a
  crash.

Counters:

- Total observed DMA bytes: `1,555.16 MB`.
- Direct RSX-local traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier hits: `9498`.
- Runtime hits: `9498`.
- LLVM direct-copy hits: `0`.
- Candidate bytes: `148.41 MB`.
- Non-constant compiler hints still include `0x25cc` using `$11` and `0x451c`
  using `$12`.

Shadow aggregation from `RPCS3.log`:

- Shadow rows: `633`.
- Shadow hits: `633`.
- Exact-shape bytes: `9.89 MB`.
- Shape: `pc=0x25cc`, `lsa=0x3b000`, `eal=0xa1c000`.
- `output_match=633`.
- `output_mismatch=0`.
- `dst_changed=0`.
- `dst_unchanged=633`.
- `src_repeats=0`.
- Unique source hashes: `633`.
- Every shadow row had `last_dst_pre_hash == last_src_hash ==
  last_dst_post_hash`.

Reading:

- This is better than just "runtime path is dynamic": the exact `0x3b000 ->
  0xa1c000` shape behaved as an idempotent/redundant copy in this field route.
- The broader HLE verifier summary's `148.36 MB` for the `last_lsa=0x3b000`
  group is an aggregate-last-shape view, not proof that every hit was that exact
  shape. The exact shadow lane measured `9.89 MB`.
- Because source hashes were unique, this is not a replay-cache target. It is a
  possible guarded HLE/skip target if field/menu/battle all prove the
  destination is already equal before the copy.
- This remains CPU/SPU HLE/codegen work. It is not GPU migration credit and not
  a speed win yet.

Next action:

- Add first-class parser/CSV/summary support for `Eternal Sonata SPU HLE shadow
  verifier:` rows.
- Then repeat field/menu/battle shadow verification or add a guarded skip
  verifier that can count skipped bytes without enabling fast mode by default.

Classification:

- `spu-hle-shadow-field-pass`, `redundant-copy-hle-candidate`,
  `verify-only`, not `gpu-migration-credit`, not `windows-micro-win`, not a
  200% gate candidate.

## 2026-05-23 SPU HLE Shadow Parser Support

Question:

- Can the GPU probe summarizer make the new shadow verifier row first-class so
  later field/menu/battle runs do not need one-off PowerShell aggregation?

Change:

- Added `-SpuHleShadowCsvPath` to
  `tools/summarize_eternal_sonata_gpu_probe.ps1`.
- Added parser support for `Eternal Sonata SPU HLE shadow verifier:` rows.
- The summarizer now writes
  `eternal-sonata-spu-hle-shadow-profile.csv`.
- The summary now includes a `SPU HLE Shadow Verifier` section and a shape
  table keyed by `pc`, `cmd`, `tag`, size, `lsa`, `eal`, group, SPU, and image.

Verification:

```powershell
$tokens=$null; $errors=$null; `
  [System.Management.Automation.Language.Parser]::ParseFile( `
    (Resolve-Path 'tools\summarize_eternal_sonata_gpu_probe.ps1'), `
    [ref]$tokens, `
    [ref]$errors) | Out-Null; `
  if($errors){ $errors | Format-List *; exit 1 } else { 'parser ok' }

.\tools\summarize_eternal_sonata_gpu_probe.ps1 `
  -RunDir 'debug-captures\windows-lab\20260523-222320-hle-shadow-contract-field-windows-windows' `
  -Top 12
```

Result:

- Parser check passed.
- `git diff --check -- tools/summarize_eternal_sonata_gpu_probe.ps1` passed
  with the existing LF-to-CRLF warning only.
- The rerun summary now reports:
  - SPU HLE shadow records: `633`.
  - SPU HLE shadow CSV:
    `debug-captures/windows-lab/20260523-222320-hle-shadow-contract-field-windows-windows/eternal-sonata-spu-hle-shadow-profile.csv`.
  - Shadow hits: `633`.
  - Candidate bytes: `9.89 MB`.
  - Output match/mismatch: `633 / 0`.
  - Destination changed/unchanged: `0 / 633`.
  - Unique source hashes: `633`.
  - Shadow shape row: `pc=0x25cc`, `cmd=0x40`, tag `31`, size `16384`,
    `lsa=0x3b000`, `eal=0xa1c000`, group `CellSpursKernelGroup`,
    SPU `CellSpursKernel0`, image `0x958dfe208b686622`.

Reading:

- This is harness support, not a speed result.
- The exact shadow lane is now durable evidence for a guarded HLE/skip verifier
  candidate.
- The broader SPU HLE verifier row still has aggregate-last-shape semantics;
  the shadow section is the exact copy-contract proof surface.

Next action:

- Repeat this exact shadow verifier through menu/Options and first battle, or
  add a guarded skip verifier that proves `dst_pre == src` before counting any
  skipped copy as a micro-win candidate.

Classification:

- `harness-support`, `parser-pass`, `shadow-csv-pass`, `verify-only`, not
  `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.

## 2026-05-23 SPU HLE Shadow Options Capture

Question:

- Does the exact `0x25cc` shadow-copy contract survive the title Options route,
  not just the field route?

First attempt:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene menu `
  -Label hle-shadow-contract-menu-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 130 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 60 `
  -ScreenshotMaxCount 8
```

Result:

- Run:
  `debug-captures/windows-lab/20260523-224541-hle-shadow-contract-menu-windows-windows`.
- Host grade: `clean` across `5` snapshots, RPCS3 stayed on `\\.\DISPLAY2`.
- Manual screenshots showed the old menu macro fired while the title intro was
  still running (`screenshot-0068s.png`, `screenshot-0086s.png`), then selected
  the wrong title item and landed in a loading/new-game transition by
  `screenshot-0130s.png`.
- The shadow counters were still clean (`517` rows / `8.08 MB`,
  `output_mismatch=0`, `dst_changed=0`), but this run is route-invalid for
  Options proof.

Harness repair:

- Updated `tools/eternal_sonata_speed_sprint.ps1` so `-Scene menu` sends one
  `cross` after the intro wait to skip/settle to the title menu before moving
  down to Options.
- Parser check passed:

```powershell
$tokens=$null; $errors=$null; `
  [System.Management.Automation.Language.Parser]::ParseFile( `
    (Resolve-Path 'tools\eternal_sonata_speed_sprint.ps1'), `
    [ref]$tokens, `
    [ref]$errors) | Out-Null; `
  if($errors){ $errors | Format-List *; exit 1 } else { 'parser ok' }
```

Repaired command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene menu `
  -Label hle-shadow-contract-options-skipintro-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 140 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 60 `
  -ScreenshotMaxCount 8 `
  -InputMacro "wait:65000;cross:180;wait:9000;shot:100;down:220;wait:1000;shot:100;down:220;wait:16000;shot:100;cross:180;wait:8000;shot:100;wait:6000;shot:100"
```

Repaired result:

- Run:
  `debug-captures/windows-lab/20260523-225235-hle-shadow-contract-options-skipintro-windows-windows`.
- Host grade: `clean` across `5` snapshots, RPCS3 stayed on `\\.\DISPLAY2`.
- Manual screenshots `screenshot-0104s.png` and `screenshot-0130s.png` show the
  full title Options page, with no obvious black/loading/wrong-window issue.
- Refined fatal scan found no real crash/access/Vulkan/assertion/fatal hits;
  only the generic `Show fatal error hints: false` config line matched.
- Summary counters:
  - total observed DMA bytes: `1,133.99 MB`;
  - direct RSX-local scout traffic: `0`;
  - indirect SPU-DMA/RSX-resource overlap: `0`;
  - SPU HLE verifier rows: `608`;
  - SPU HLE verifier hits/runtime/LLVM: `9108 / 9108 / 0`;
  - SPU HLE verifier candidate bytes: `142.31 MB`;
  - shadow rows/hits/bytes: `607 / 607 / 9.48 MB`;
  - shadow output match/mismatch: `607 / 0`;
  - shadow destination changed/unchanged: `0 / 607`;
  - unique source hashes: `607`;
  - shadow shape: `pc=0x25cc`, `cmd=0x40`, tag `31`, size `16384`,
    `lsa=0x3b000`, `eal=0xa1c000`, image `0x958dfe208b686622`.

Reading:

- The exact shadow-copy contract now has field plus title Options visual proof.
- It remains verify-only CPU/SPU HLE evidence. It is not GPU migration credit,
  not a Windows micro-win, and not a 200% gate candidate.
- The next proof gap is first battle, then a guarded skip verifier that counts
  potential skipped bytes only when `dst_pre == src`.

Classification:

- First attempt: `failed-route`, `not-comparable-options`.
- Repaired run: `spu-hle-shadow-options-pass`, `redundant-copy-hle-candidate`,
  `verify-only`, not `gpu-migration-credit`, not `windows-micro-win`, not a
  200% gate candidate.

## 2026-05-23 SPU HLE Shadow Battle Capture

Question:

- Does the exact `0x25cc` shadow-copy contract survive the active first-battle
  route after already passing field and title Options?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-shadow-contract-battle-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 340 `
  -ScreenshotEverySeconds 20 `
  -ScreenshotStartSeconds 170 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260523-230125-hle-shadow-contract-battle-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host grade: `clean` across `5` snapshots.
- `windows-rpcs3-lab.txt` shows the route reached screenshots at `0131s`,
  `0183s`, `0244s`, and `0305s` through `0312s`.
- The outer Codex command timed out while post-run summarization was still
  pending, but the lab run itself stopped cleanly at the requested max seconds.
  Manual summarizer rerun succeeded:

```powershell
.\tools\summarize_eternal_sonata_gpu_probe.ps1 `
  -RunDir 'debug-captures\windows-lab\20260523-230125-hle-shadow-contract-battle-windows-windows' `
  -Top 12
```

Visual / fatal proof:

- Manual screenshot checks:
  - `screenshots/screenshot-0244s.png`: active first-battle UI with Polka,
    health, action wheel, and battlefield visible.
  - `screenshots/screenshot-0309s.png`: same clean active battle state later in
    the route.
- Refined fatal scan found no real crash/access/Vulkan/assertion/fatal hits;
  only the generic `Show fatal error hints: false` config line matched.

Summary counters:

- Total observed DMA bytes: `3,739.20 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `1604`.
- SPU HLE verifier hits/runtime/LLVM: `24048 / 24048 / 0`.
- SPU HLE verifier candidate bytes: `375.75 MB`.
- Shadow rows/hits/bytes: `1603 / 1603 / 25.05 MB`.
- Shadow output match/mismatch: `1603 / 0`.
- Shadow destination changed/unchanged: `0 / 1603`.
- Unique source hashes: `1603`.
- Shadow shape: `pc=0x25cc`, `cmd=0x40`, tag `31`, size `16384`,
  `lsa=0x3b000`, `eal=0xa1c000`, group `CellSpursKernelGroup`,
  SPU `CellSpursKernel0`, image `0x958dfe208b686622`.

Reading:

- The exact `0x25cc` shadow-copy contract now has field, title Options, and
  first-battle visual/fatal-clean proof.
- Across those three scenes, the exact shape always had `output_mismatch=0`,
  `dst_changed=0`, and `dst_unchanged=hits`, with unique source hashes. This is
  now a concrete guarded-copy-skip/HLE verifier candidate.
- It is still CPU/SPU HLE/codegen work. It is not GPU migration credit, not a
  Windows micro-win, not a speed win, and not a 200% gate candidate.
- The next Windows-only implementation step is a guarded skip verifier/counter:
  only skip or count skippable bytes when `dst_pre_hash == src_hash`, keep the
  default behavior stock, and then run matched field/menu/battle A/B before
  calling it a micro-win.

Classification:

- `spu-hle-shadow-battle-pass`, `redundant-copy-hle-candidate`,
  `verify-only`, not `gpu-migration-credit`, not `windows-micro-win`, not a
  200% gate candidate.

## 2026-05-23 SPU HLE Guarded Skip Field Smoke

Question:

- Can the exact `0x25cc` shadow-copy contract safely become a default-off
  guarded skip path on Windows, while proving it only returns early when
  `dst_pre == src`?

Implementation:

- Local `rpcs3-upstream` now parses `RPCS3_ES_SPU_HLE_VERIFY=skip` as a guarded
  skip mode. `verify` still only records the shadow contract.
- The runtime skip remains gated to title `BLUS30161`, image
  `0x958dfe208b686622`, `pc=0x25cc`, `cmd=0x40`, tag `31`, size `0x4000`,
  `lsa=0x3b000`, `eal=0xa1c000`, accurate DMA off, and MFC shuffling off.
- The fast return happens only when the pre-sample has
  `src_hash == dst_pre_hash` and `memcmp(src,dst,size)==0`.
- Added shadow counters:
  `skip_hits`, `skip_bytes`, `skip_misses`, `skip_miss_bytes`.
- `tools/windows_rpcs3_lab.ps1` and
  `tools/eternal_sonata_speed_sprint.ps1` now expose
  `-EternalSonataSpuHleVerify Skip`.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` exports and summarizes the
  skip counters in `eternal-sonata-spu-hle-shadow-profile.csv`.

Build / parser:

```powershell
cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6
```

- Build passed.
- PowerShell parser checks passed for the Windows lab, sprint wrapper, and GPU
  probe summarizer.
- `git diff --check` passed for the touched files, with only CRLF warnings.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-guardedskip-field-windows `
  -EternalSonataSpuHleVerify Skip `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike
```

Run:

- `debug-captures/windows-lab/20260523-233852-hle-shadow-guardedskip-field-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host grade: `clean` across `5` snapshots.
- Visual gate passed: first field-like screenshot `screenshot-0118s.png` at
  `118s`, `0` invalid screenshots after field-like output.
- Manual screenshot check: `screenshots/screenshot-0165s.png` is clean Path to
  Tenuto field with Polka visible, no black/loading/wrong-window issue.
- Fatal scan found no real crash/access/likely-crashed/assertion/fatal hits;
  only the normal `Show fatal error hints: false` config line matched.

Summary counters:

- Total observed DMA bytes: `1,624.49 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `675`.
- SPU HLE verifier hits/runtime/LLVM: `10113 / 10113 / 0`.
- SPU HLE verifier candidate bytes: `158.02 MB`.
- Shadow rows/hits/bytes: `674 / 674 / 10.53 MB`.
- Shadow output match/mismatch: `674 / 0`.
- Shadow destination changed/unchanged: `0 / 674`.
- Guarded skip hits/bytes: `674 / 10.53 MB`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `674`.

Reading:

- This is the first correctness-clean guarded fast return for the exact
  `0x25cc` redundant copy shape, but it only proves a field smoke.
- It moves redundant CPU memory-copy work into a CPU/SPU HLE skip, not onto the
  GPU. Count it as a CPU-load reduction candidate, not `gpu-migration-credit`.
- Do not call this a speed win yet. The route was not a matched A/B against a
  same-build verify/baseline run, and title Options plus first battle are still
  missing in skip mode.

Next action:

- Run matched Windows `Verify` versus `Skip` field A/B on the same build and
  route, then repeat skip-mode title Options and first-battle visual/fatal
  proof before preserving it as a bankable `windows-micro-win`.

Classification:

- `spu-hle-guarded-skip-field-pass`, `windows-micro-candidate`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-23 SPU HLE Guarded Skip Same-Build Verify Field

Question:

- Can a same-build `Verify` run provide the baseline half of the guarded-skip
  field A/B?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-verify-ab-field-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike
```

Run:

- `debug-captures/windows-lab/20260523-235000-hle-shadow-verify-ab-field-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Visual gate passed: first field-like screenshot `screenshot-0118s.png` at
  `118s`, `0` invalid screenshots after field-like output.
- Manual screenshot check: `screenshots/screenshot-0165s.png` is clean Path to
  Tenuto field.
- Fatal scan found no real crash/access/likely-crashed/assertion/fatal hits;
  only the normal `Show fatal error hints: false` config line matched.
- Host grade: `high`, with CPU sampled at `100%` during the `134s`, `150s`,
  and postrun snapshots. This blocks timing comparison.

Summary counters:

- Total observed DMA bytes: `1,523.48 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `628`.
- SPU HLE verifier hits/runtime/LLVM: `9408 / 9408 / 0`.
- SPU HLE verifier candidate bytes: `147.00 MB`.
- Shadow rows/hits/bytes: `627 / 627 / 9.80 MB`.
- Shadow output match/mismatch: `627 / 0`.
- Shadow destination changed/unchanged: `0 / 627`.
- Guarded skip hits/bytes: `0 / 0 B`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `627`.

Comparison to previous skip field smoke:

- Skip field run:
  `debug-captures/windows-lab/20260523-233852-hle-shadow-guardedskip-field-windows-windows`.
- Skip field visual/fatal/host status: clean field, clean fatal scan, host grade
  `clean`.
- Skip field counters: `674` shadow rows / `10.53 MB`, `skip_hits=674`,
  `skip_bytes=10.53 MB`, `skip_misses=0`, `output_mismatch=0`,
  `dst_changed=0`.

Reading:

- The same-build `Verify` run preserves the same exact-copy contract and gives
  visual/counter parity with `Skip`.
- It cannot be used as a timing baseline because the host was contended.
- The guarded skip remains a `windows-micro-candidate`, not a
  `windows-micro-win`.

Next action:

- Rerun matched clean-host field A/B. Prefer doing the `Verify` half only when
  host sampling is clean, or add a harness guard that aborts/rejects speed A/B
  when midrun CPU hits the high-contention threshold.

Classification:

- `spu-hle-verify-field-parity`, `not-comparable-host`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-23 Windows Host Contention Gate For Speed A/B

Question:

- Can the harness prevent another dirty-host run from being mistaken for a
  speed baseline?

Change:

- Added `-HostContentionGate Off|Warn|Fail` to
  `tools/windows_rpcs3_lab.ps1`.
- Added sprint-wrapper pass-through
  `-WindowsHostContentionGate Off|Warn|Fail` to
  `tools/eternal_sonata_speed_sprint.ps1`.
- `Fail` requires the worst host snapshot to be `clean`. If any prelaunch,
  postlaunch, periodic, or postrun sample is `moderate` or `high`, the lab logs
  `Host contention gate failed`, writes `host-contention-gate-failed.txt` in the
  run dir, and throws only after the run dir, copied log, and summary have been
  written.

Verification:

- PowerShell parser checks passed for `tools/windows_rpcs3_lab.ps1` and
  `tools/eternal_sonata_speed_sprint.ps1`.
- `git diff --check` passed for the touched harness/docs files with only the
  repo's normal LF-to-CRLF warnings.

Reading:

- This is process hygiene, not a speed or GPU migration result.
- Future matched `Verify`/`Skip` field A/B runs for the SPU HLE guarded skip
  should use `-WindowsHostContentionGate Fail`. If the host is dirty, classify
  the run as `not-comparable-host` and rerun instead of banking a micro-win.

Classification:

- `process-harness`, `windows-proof-gate`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 SPU HLE Guarded Skip Clean-Host Verify Field

Question:

- Can the `Verify` half of the guarded-skip field A/B be rerun under the new
  host-contention gate so it is not blocked by dirty-host timing?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-verify-ab-cleanhost-field-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate Fail
```

Run:

- `debug-captures/windows-lab/20260524-000612-hle-shadow-verify-ab-cleanhost-field-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host-contention gate passed: worst host grade `clean` across `5` snapshots.
- Visual-gate helper passed: first field-like screenshot `screenshot-0117s.png`
  at `117s`, `0` invalid screenshots after first field-like output.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.
- The outer command hit the Codex tool timeout after the lab copied `RPCS3.log`;
  the saved run was complete, and the visual gate plus GPU/SPU summary were run
  manually afterward from the run directory.

Summary counters:

- Total observed DMA bytes: `1,501.62 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `609`.
- SPU HLE verifier hits/runtime/LLVM: `9123 / 9123 / 0`.
- SPU HLE verifier candidate bytes: `142.55 MB`.
- Shadow rows/hits/bytes: `608 / 608 / 9.50 MB`.
- Shadow output match/mismatch: `608 / 0`.
- Shadow destination changed/unchanged: `0 / 608`.
- Guarded skip hits/bytes: `0 / 0 B`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `608`.

Reading:

- This replaces the dirty-host `Verify` run as the clean field parity half.
- It still proves only the no-skip verifier path and the exact-copy contract.
- Do not call the guarded skip a `windows-micro-win` yet. The next required
  proof is a gated clean `Skip` field half, then title Options and first-battle
  skip visual/fatal-clean runs.

Classification:

- `spu-hle-verify-cleanhost-field-parity`, `windows-micro-candidate-support`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 SPU HLE Guarded Skip Clean-Host Skip Field

Question:

- Can the `Skip` half of the guarded-skip field A/B pass under the same
  host-contention gate as the clean `Verify` half?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-guardedskip-ab-cleanhost-field-windows `
  -EternalSonataSpuHleVerify Skip `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate Fail
```

Run:

- `debug-captures/windows-lab/20260524-001814-hle-shadow-guardedskip-ab-cleanhost-field-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host-contention gate passed: worst host grade `clean` across `5` snapshots.
- Visual-gate helper passed: first field-like screenshot `screenshot-0117s.png`
  at `117s`, `0` invalid screenshots after first field-like output.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.

Summary counters:

- Total observed DMA bytes: `1,603.07 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `671`.
- SPU HLE verifier hits/runtime/LLVM: `10053 / 10053 / 0`.
- SPU HLE verifier candidate bytes: `157.08 MB`.
- Shadow rows/hits/bytes: `670 / 670 / 10.47 MB`.
- Shadow output match/mismatch: `670 / 0`.
- Shadow destination changed/unchanged: `0 / 670`.
- Guarded skip hits/bytes: `670 / 10.47 MB`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `670`.

Comparison to clean `Verify` half:

- Clean `Verify` field run:
  `debug-captures/windows-lab/20260524-000612-hle-shadow-verify-ab-cleanhost-field-windows-windows`.
- Verify visual/fatal/host status: field-like, fatal-clean, host grade `clean`.
- Verify counters: `608` shadow rows / `9.50 MB`, `output_mismatch=0`,
  `dst_changed=0`, `skip_hits=0`.

Reading:

- The clean field A/B parity pair is now complete for the exact `0x25cc`
  redundant-copy shape.
- `Skip` only returned early after proving `dst_pre == src`; all skip attempts
  were hits, and there were no guarded-skip misses.
- This removes a small amount of CPU memory-copy work, not GPU work. It is
  still not a `windows-micro-win` because no FPS/frame-time delta was measured,
  and skip mode still needs title Options plus first-battle visual/fatal-clean
  proof.

Classification:

- `spu-hle-guarded-skip-cleanhost-field-parity`,
  `windows-micro-candidate-support`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 SPU HLE Guarded Skip Title Options

Question:

- Does guarded `Skip` mode keep the title Options screen visually/fatally clean
  after the clean field A/B pair?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene menu `
  -Label hle-shadow-guardedskip-options-cleanhost-windows `
  -EternalSonataSpuHleVerify Skip `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 125 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 70 `
  -ScreenshotMaxCount 6 `
  -WindowsHostContentionGate Fail
```

Run:

- `debug-captures/windows-lab/20260524-002613-hle-shadow-guardedskip-options-cleanhost-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host-contention gate passed: worst host grade `clean` across `5` snapshots.
- Manual screenshot check: `screenshots/screenshot-0104s.png` and
  `screenshots/screenshot-0115s.png` show the full title Options page with no
  obvious menu corruption, black overlay, or wrong-window capture.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.

Summary counters:

- Total observed DMA bytes: `973.56 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `504`.
- SPU HLE verifier hits/runtime/LLVM: `7548 / 7548 / 0`.
- SPU HLE verifier candidate bytes: `117.94 MB`.
- Shadow rows/hits/bytes: `503 / 503 / 7.86 MB`.
- Shadow output match/mismatch: `503 / 0`.
- Shadow destination changed/unchanged: `0 / 503`.
- Guarded skip hits/bytes: `503 / 7.86 MB`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `503`.

Reading:

- Guarded `Skip` mode now has clean Windows proof for field and title Options.
- This is still CPU-side redundant-copy removal, not GPU migration credit.
- Do not call it a `windows-micro-win` yet: first-battle skip visual/fatal
  proof and a matched speed/frame-time delta are still missing.

Classification:

- `spu-hle-guarded-skip-options-pass`, `windows-micro-candidate-support`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 SPU HLE Guarded Skip First Battle

Question:

- Does guarded `Skip` mode keep the first battle visually/fatally clean after
  the clean field A/B pair and title Options proof?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-shadow-guardedskip-battle-cleanhost-windows `
  -EternalSonataSpuHleVerify Skip `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -MaxSeconds 330 `
  -ScreenshotEverySeconds 20 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8 `
  -WindowsHostContentionGate Fail
```

Run:

- `debug-captures/windows-lab/20260524-003446-hle-shadow-guardedskip-battle-cleanhost-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host-contention gate passed: worst host grade `clean` across `5` snapshots.
- Manual screenshot check: `screenshots/screenshot-0244s.png` and
  `screenshots/screenshot-0311s-01.png` show active first-battle UI with Polka,
  battle commands, and no obvious menu, terrain, lighting, or overlay
  corruption.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.

Summary counters:

- Total observed DMA bytes: `3,714.18 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `1610`.
- SPU HLE verifier hits/runtime/LLVM: `24138 / 24138 / 0`.
- SPU HLE verifier candidate bytes: `377.16 MB`.
- Shadow rows/hits/bytes: `1609 / 1609 / 25.14 MB`.
- Shadow output match/mismatch: `1609 / 0`.
- Shadow destination changed/unchanged: `0 / 1609`.
- Guarded skip hits/bytes: `1609 / 25.14 MB`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `1609`.

Reading:

- Guarded `Skip` mode now has clean Windows correctness proof for field, title
  Options, and active first battle.
- This is still CPU-side redundant-copy removal, not GPU migration credit.
- Do not call it a `windows-micro-win` yet: the next required proof is a
  matched clean speed/frame-time delta on the same route, scene, config, and
  host grade.

Classification:

- `spu-hle-guarded-skip-battle-pass`, `windows-micro-candidate-support`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 SPU HLE Guarded Skip Uncapped Verify Baseline Rejected

Question:

- Can the `Verify` half of the guarded-skip field A/B be measured uncapped at
  frame/vblank `240/240` under the same clean-host gate?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-verify-ab-uncap240-field-cleanhost-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate Fail
```

Run:

- `debug-captures/windows-lab/20260524-004919-hle-shadow-verify-ab-uncap240-field-cleanhost-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Visual gate passed after a manual rerun of
  `tools/check_eternal_sonata_windows_visual_gate.ps1 -RequireFieldLike
  -RequireNoInvalidAfterFirstField`: first field-like screenshot
  `screenshot-0117s.png` at `117s`.
- Manual screenshot check: `screenshots/screenshot-0150s.png` shows clean Path
  to Tenuto field gameplay with overlay around `111.65` to `112.88 FPS`.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.
- Host-contention gate failed: worst host grade `moderate` because uncapped
  gameplay itself drove total host CPU/GPU high. Samples:
  - `sample-0133s`: total CPU `56.3%`, GPU engine sum `72.5%`, RPCS3 process
    CPU `47.9%`.
  - `sample-0150s`: total CPU `59.1%`, GPU engine sum `72.5%`, RPCS3 process
    CPU `46.4%`.

Summary counters:

- Total observed DMA bytes: `1,795.12 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `392`.
- SPU HLE verifier hits/runtime/LLVM: `5868 / 5868 / 0`.
- SPU HLE verifier candidate bytes: `91.69 MB`.
- Shadow rows/hits/bytes: `391 / 391 / 6.11 MB`.
- Shadow output match/mismatch: `391 / 0`.
- Shadow destination changed/unchanged: `0 / 391`.
- Guarded skip hits/bytes: `0 / 0 B`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `391`.

Reading:

- This is a useful harness finding, not a usable speed baseline. The current
  `Fail` host gate uses absolute total CPU/GPU thresholds, so uncapped RPCS3
  self-load can make an otherwise externally clean run fail.
- Do not compare this against a future `Skip` run as a `windows-micro-win`.
- Next speed-proof step should either use `-WindowsHostContentionGate Warn`
  with explicit external-process/process-counter review, or add an
  external-contention-only gate before re-running the `Verify`/`Skip` uncapped
  pair.

Classification:

- `not-comparable-host-gate`, `process-harness`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 External Host Contention Gate For Uncapped A/B

Question:

- Can the Windows harness separate real external host contention from RPCS3's
  own uncapped CPU/GPU load, so uncapped speed A/B runs are not rejected by the
  absolute `Fail` gate?

Change:

- `tools/windows_rpcs3_lab.ps1` now accepts `-HostContentionGate ExternalFail`.
- `tools/eternal_sonata_speed_sprint.ps1` now accepts
  `-WindowsHostContentionGate ExternalFail`.
- Host snapshots now record both:
  - `contention_grade`: absolute total CPU/GPU/memory/process contention.
  - `external_contention_grade`: competing emulator, hot non-run process, or
    memory-pressure contention with the current RPCS3 run process excluded.
- `ExternalFail` fails only when `external_contention_grade` is not `clean`;
  it still writes `host-contention-gate-failed.txt` on failure.
- `.agents/skills/ps3-speed-proof-gate/SKILL.md` now says capped/parity runs
  should prefer `Fail`, while uncapped `240/240` speed A/B should prefer
  `ExternalFail`.

Verification:

- PowerShell parser checks passed for:
  - `tools/windows_rpcs3_lab.ps1`
  - `tools/eternal_sonata_speed_sprint.ps1`
- Parameter smoke checks accepted `ExternalFail` through:
  - `tools/eternal_sonata_speed_sprint.ps1 -Action ToolStatus
    -WindowsHostContentionGate ExternalFail`
  - `tools/windows_rpcs3_lab.ps1 -Action LocateGame
    -HostContentionGate ExternalFail`
- `git diff --check` passed for the touched harness/docs files with only the
  repo's normal LF-to-CRLF warnings.

Reading:

- This is process harness work, not a speed result.
- The rejected uncapped `Verify` run remains invalid as a baseline because it
  was run before `ExternalFail` existed.
- Next speed-proof step is to rerun the `Verify`/`Skip` uncapped field pair
  with `-WindowsHostContentionGate ExternalFail`, then compare only if route,
  visuals, logs, and external-contention grade match.

Classification:

- `process-harness`, `speed-proof-gate`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c List-Family Descriptor Clusters

Question:

- Can the clean no-movement `0x451c` family rows produce actionable descriptor
  clusters for the next HLE/codegen verifier, instead of only broad tag/size
  buckets?

Change:

- Extended `tools/summarize_eternal_sonata_451c_list_family_run.ps1` to emit:
  - `eternal-sonata-451c-list-family-quick-clusters.csv`;
  - `Hot Descriptor Clusters`, sorted by hits;
  - `Slowest Descriptor Clusters`, sorted by total measured time;
  - `Predicate Seeds` for copy/pasteable verify-only recognizer predicates.

Verification:

- PowerShell language parser passed.
- Synthetic smoke log still passed and emitted a one-row cluster table.
- Clean no-movement run command:

```powershell
.\tools\summarize_eternal_sonata_451c_list_family_run.ps1 `
  -RunDir 'debug-captures/windows-lab/20260524-195528-hle-451c-listfamily-verify-nomove-reproof-windows' `
  -Top 10
```

Result:

- Re-parsed the clean run in about `6.46s`.
- Row CSV remained `699` rows.
- Cluster CSV imported successfully with `286` descriptor clusters.
- Top hit cluster:
  `pc=0x451c cmd=0x46 tag=0 size=16 lsa=0x1b000 eal=0x3f530`,
  `57` rows, `4,440` hits, `5.28%` of family hits, `2.043 ms`.
- Next hit clusters:
  - `tag=1 size=8 lsa=0x8c00 eal=0x3f430`, `3,094` hits;
  - `tag=1 size=8 lsa=0x6000 eal=0x3f430`, `2,516` hits;
  - `tag=1 size=8 lsa=0x8400 eal=0x3f430`, `2,158` hits;
  - `tag=1 size=8 lsa=0x5c00 eal=0x3f430`, `1,528` hits,
    but `13.633 ms`.
- Exact-cluster coverage is fragmented:
  - top `1` cluster: `4,440` hits, `5.28%`;
  - top `5` clusters: `13,736` hits, `16.33%`;
  - top `10` clusters: `19,931` hits, `23.69%`;
  - top `32` clusters: `35,559` hits, `42.27%`;
  - top `64` clusters: `50,006` hits, `59.44%`.
- Slowest cluster:
  `tag=0 size=8 lsa=0xa400 eal=0x3f730`, `1` row, `190` hits,
  `14.707 ms`, `77.405 us/hit`, max row `14.578 ms`.
- Other slow clusters were mostly `tag0/size8` and `tag1/size8` outliers,
  including `tag=1 size=8 lsa=0x5c00 eal=0x3f430` at `13.633 ms`
  and `tag=0 size=8 lsa=0x6000 eal=0x3f730` at `8.329 ms`.
- Direct RSX-local bytes remained `0 B`.

Reading:

- Exact descriptor predicates are useful for verifier smoke tests but are too
  fragmented to be the final speed body.
- The higher-value implementation target is still broad `0x46` family/list
  descriptor batching or codegen recognition, especially around the small
  `tag0/size8`, `tag1/size8`, `tag0/size16`, and `tag1/size16` families.
- This is still CPU/SPU HLE/codegen prep, not GPU migration. The data again
  argues against one-dispatch-per-descriptor Vulkan compute because no
  RSX-local/RSX-consumed traffic appeared.

Classification:

- `process-harness`, `spu-hle-451c-list-family-tooling`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c List-Family Quick Parser

Question:

- Can we recover the clean no-movement `0x451c` list-family evidence without
  waiting for the full GPU probe summarizer when that broad parser times out on
  a large Windows heartbeat capture?

Change:

- Added `tools/summarize_eternal_sonata_451c_list_family_run.ps1`.
- The parser is intentionally narrow. It reads only:
  - `Eternal Sonata SPU HLE 451c list family verifier:`;
  - `Eternal Sonata MFC dynamic probe:`;
  - `Eternal Sonata MFC list transfer probe:`;
  - `Eternal Sonata GPU candidate probe:`.
- It writes:
  - `eternal-sonata-451c-list-family-quick-summary.md`;
  - `eternal-sonata-451c-list-family-quick-rows.csv`.
- PowerShell `continue` was removed from the `ForEach-Object` parser pipeline
  after it caused silent script-level exits. The parser now uses normal branch
  flow.

Verification:

- PowerShell language parser passed for
  `tools/summarize_eternal_sonata_451c_list_family_run.ps1`.
- Synthetic smoke log passed with `1` list-family row, correct family shares,
  dynamic/list/GPU totals, and `0 B` direct RSX-local bytes.
- Clean field run command:

```powershell
.\tools\summarize_eternal_sonata_451c_list_family_run.ps1 `
  -RunDir 'debug-captures/windows-lab/20260524-195528-hle-451c-listfamily-verify-nomove-reproof-windows' `
  -Top 8
```

Result:

- Parsed the clean no-movement run in about `6.31s`.
- Wrote:
  - `debug-captures/windows-lab/20260524-195528-hle-451c-listfamily-verify-nomove-reproof-windows/eternal-sonata-451c-list-family-quick-summary.md`;
  - `debug-captures/windows-lab/20260524-195528-hle-451c-listfamily-verify-nomove-reproof-windows/eternal-sonata-451c-list-family-quick-rows.csv`.
- CSV imported successfully with `699` rows.
- Summary preserved the important clean-run facts:
  - visual status `FIELD_LIKE_PRESENT`;
  - first field-like screenshot `screenshot-0117s.png` at `117s`;
  - fatal scan clean;
  - `699` list-family rows;
  - `84,124` list-family hits;
  - success/fail `84,124 / 0`;
  - descriptor bytes `1.30 MB`;
  - timing `97.566 ms`, average `1.160 us/hit`;
  - dynamic MFC `1,285` rows / `223,347` hits / `449.94 MB`;
  - `0x25cc=17,925 / 43.789 ms`, `0x451c=205,422 / 161.322 ms`;
  - list-transfer `84,124` calls / `72.014 ms`;
  - GPU candidate rows/total DMA `1,285 / 1.86 GB`;
  - direct RSX-local bytes `0 B`.

Reading:

- This makes the clean `0x451c` list-family capture usable for future
  HLE/codegen sizing despite the full summarizer timeout.
- It does not change runtime behavior, does not enable fast mode, and does not
  move CPU/SPU work to GPU.
- The latest clean evidence still says the `0x451c` dynamic `0x46` list-family
  work is an SPU HLE/codegen/batching target with no direct RSX-local traffic.

Classification:

- `process-harness`, `spu-hle-451c-list-family-tooling`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c Dynamic List-Seed Verify Counter Hook

Question:

- Can the `0x451c` predicate sketch for the two hottest dynamic list-control
  seeds become a compile-checked Windows verifier hook without changing stock
  MFC/list behavior?

Change:

- Local Windows `rpcs3-upstream` now adds verify-only counters for the top two
  dynamic `0x451c` `MFC_GETLF_CMD` seeds:
  - `tag=0`, `size=16`, `lsa=0x1b000`, EA `0x3f530..0x3f730`;
  - `tag=1`, `size=8`, `lsa=0x5c00`, EA `0x3f430..0x3f630`.
- The hook is gated by title/image/PC, `RPCS3_ES_SPU_HLE_VERIFY=verify`,
  non-accurate DMA, and non-shuffled MFC transfers.
- It logs `Eternal Sonata SPU HLE 451c list seed verifier:` with seed hit,
  success/fail, descriptor-byte, and timing counters.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` now parses the row, exports
  `eternal-sonata-spu-hle-451c-list-seed-profile.csv`, and writes a Markdown
  `SPU HLE 0x451c List-Seed Verifier` section.

Verification:

```powershell
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\tools\summarize_eternal_sonata_gpu_probe.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null

cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" `
  --config Release --target rpcs3 --parallel 6

.\tools\summarize_eternal_sonata_gpu_probe.ps1 `
  -RunDir .\debug-captures\windows-lab\20260524-124605-window-title-sample-smoke `
  -Top 4
```

Results:

- PowerShell parser check passed.
- Release `rpcs3` build passed.
- Old Windows smoke log summarized successfully and reported
  `SPU HLE 0x451c list-seed records: 0`, preserving compatibility.
- Synthetic one-line parser smoke produced the new Markdown section and parsed
  `seed1_hits=30`, `seed2_hits=12`.

Reading:

- This is the smallest safe C++ step after the predicate sketch: it proves the
  recognizer compiles and the parser can ingest the row.
- It does not skip, batch, offload, or speed up anything yet; stock DMA/list
  behavior remains the truth path.
- The next useful Windows step is a clean field capture with
  `-EternalSonataSpuHleVerify Verify` at the safe `left200` boundary to measure
  how often the two seeds fire in a real route before any HLE/codegen body is
  attempted.

Classification:

- `windows-lab`, `spu-hle-451c-list-seed-verify-hook`, counter-only HLE/codegen
  prep, not `windows-micro-win`, not `gpu-migration-credit`, not 200% evidence.

## 2026-05-24 0x451c List-Seed Verify Field Measurement

Question:

- Do the two compile-checked `0x451c` list-control seeds fire often enough on
  the clean one-pulse Windows field route to justify turning them into the next
  fast/HLE body?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-listseed-verify-left200 `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 10 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-185632-hle-451c-listseed-verify-left200-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host gate passed: worst total and external contention were both `clean`.
- Visual gate passed:
  - status `FIELD_LIKE_PRESENT`;
  - first field-like screenshot `screenshot-0118s.png` at `118s`;
  - `14` field-like screenshots;
  - `0` invalid screenshots after first field.
- Manual image checks of `screenshot-0118s.png` and `screenshot-0200s.png`
  showed the Path to Tenuto field after the one-pulse route, with no obvious
  black-overlay state.
- Fatal scan found no real access/crash/Vulkan/assertion pattern in
  `RPCS3.log`, `rpcs3.stderr.txt`, or `rpcs3.stdout.txt`.
- `window-title-samples.csv`: `17` samples, average `34.25 FPS`, min `26.91`,
  max `39.19`. This is not a speed comparison because there is no matched A/B.

Counters:

- SPU HLE `0x451c` list-seed rows: `336`.
- List-seed hits / success / fail: `707 / 707 / 0`.
- Seed1 / seed2 hits: `205 / 502`.
- Descriptor bytes: `7.1 KB`.
- List-seed timing: `0.241 ms` total, `0.341 us/hit`, max `2 us`.
- Dynamic MFC hits: `286,445`, success/fail `286,445 / 0`, total `255.744 ms`.
- MFC list-transfer calls: `108,122`, success/fail `108,122 / 0`, total
  `94.570 ms`, descriptor bytes `1.68 MB`.
- RSX-local traffic records: `0`.
- Indirect RSX resource overlap records: `0`.
- New promoted CPU/SPU to GPU replacement remains `0 B / 0.000%`.

Reading:

- The C++ list-seed verifier is working on a clean route.
- The top two seed predicates are much too narrow to be the speed body by
  themselves in this route: only `707` hits and `0.241 ms`, while the broader
  dynamic/list `0x451c` lanes still dominate.
- Do not enable fast mode for these two seeds. The better next Windows-only
  step is to broaden the recognizer across more `0x46` list-control families or
  measure a general list-descriptor/control batching contract, still stock
  behavior first.

Classification:

- `spu-hle-451c-list-seed-field-measurement`, `windows-lab`,
  `counter-only`, not `windows-micro-win`, not `gpu-migration-credit`,
  not a 200% gate candidate.

## 2026-05-24 0x451c Dynamic 0x46 Family Coverage Scout

Question:

- After the clean field measurement showed only `707` hits for the two-seed
  C++ verifier, how much of the real `0x451c` dynamic list-control lane did
  those seeds actually cover?

Change:

- `tools/summarize_eternal_sonata_451c_contract.ps1` now adds a
  `Dynamic 0x46 Family Coverage` section.
- The section reports total dynamic `0x46` descriptors, hits, bytes, time,
  top-two predicate coverage, and the highest-cost `0x46` descriptor families.

Verification:

```powershell
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\tools\summarize_eternal_sonata_451c_contract.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null

.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
```

Results:

- PowerShell parser check passed.
- Contract report regenerated:
  `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.md`.
- Valid fatal-clean field runs used: `12`.
- Dynamic MFC `0x451c`: `1,102,871` hits / `988.05 MB`.
- List-transfer `0x451c`: `450,773` calls / `6.99 MB` descriptor bytes.
- Top runtime-cost lane: `small-list-control`, `540.333 ms`,
  `721,481` hits, `645.50 MB`, `508` descriptors.
- Broad dynamic `0x46` family: `721,481` hits, `645.50 MB`,
  `540.333 ms`.
- Current top-two predicate coverage:
  - `46,272` hits (`6.41%`);
  - `44.65 MB`;
  - `62.857 ms` (`11.63%`).
- Top descriptor remains `cmd=0x46`, `tag=0`, `size=16`, `lsa=0x1b000`,
  EA `0x3f530..0x3f730`, but it covers only `4.56%` of broad `0x46` hits.

Reading:

- The two-seed C++ verifier is useful as a smoke hook, but it is not the speed
  body. Fast mode for just those seeds would attack only a small fraction of
  the measured lane.
- The next Windows-only verifier should either:
  - broaden the title/image/PC-gated recognizer to more `0x46` descriptor
    families while preserving stock behavior; or
  - move down a level and measure `do_list_transfer` descriptor/control
    batching directly.
- Broad SPU-to-Vulkan remains parked: the valid captures still show no
  RSX-local or indirect RSX-resource overlap for this bucket.

Classification:

- `analysis`, `spu-hle-451c-broad-0x46-coverage`, process/harness scout,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 0x451c Dynamic 0x46 Coverage Ladder

Question:

- If the exact top-two `0x46` seeds are too narrow, should the next verifier
  broaden by adding more exact descriptors or by recognizing larger tag/size
  families?

Change:

- Extended `tools/summarize_eternal_sonata_451c_contract.ps1` so the
  `Dynamic 0x46 Family Coverage` section now also emits:
  - a top-N descriptor coverage ladder; and
  - tag/size family buckets for all dynamic `0x46` descriptors.

Verification:

```powershell
$null = [System.Management.Automation.PSParser]::Tokenize(
  (Get-Content .\tools\summarize_eternal_sonata_451c_contract.ps1 -Raw),
  [ref]$null
)

.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
```

Results:

- Parser check passed.
- Contract report regenerated:
  `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.md`.
- The broad dynamic `0x46` lane remains `508` descriptors, `721,481` hits,
  `645.50 MB`, and `540.333 ms`.
- Current top-two predicate coverage remains low:
  `46,272` hits (`6.41%`) and `62.857 ms` (`11.63%`).
- Top-N exact descriptor coverage:
  - top `32`: `178,446` hits (`24.73%`), `294.701 ms` (`54.54%`);
  - top `64`: `305,570` hits (`42.35%`), `369.076 ms` (`68.31%`);
  - top `128`: `460,874` hits (`63.88%`), `443.204 ms` (`82.02%`).
- Tag/size family buckets collapse the whole lane into six broad families:
  - tag `1`, size `8`: `270,707` hits (`37.52%`), `187.243 ms`
    (`34.65%`);
  - tag `0`, size `8`: `180,494` hits (`25.02%`), `107.059 ms`
    (`19.81%`);
  - tag `0`, size `16`: `112,254` hits (`15.56%`), `106.495 ms`
    (`19.71%`);
  - tag `1`, size `16`: `92,022` hits (`12.75%`), `96.532 ms`
    (`17.87%`);
  - tag `1`, size `24`: `38,091` hits (`5.28%`), `25.578 ms`
    (`4.73%`);
  - tag `0`, size `24`: `27,913` hits (`3.87%`), `17.426 ms`
    (`3.23%`).

Reading:

- Adding exact seed after exact seed is probably the wrong next shape: top
  `32` descriptors are already more than a tiny predicate, yet still cover only
  about a quarter of hits.
- A verify-only broad `0x46` tag/size-family recognizer is now the cleaner next
  C++ step if we stay at the dynamic command layer.
- The alternative remains `do_list_transfer` descriptor/control batching, which
  may be a better implementation hook than a giant exact-descriptor table.
- This is still analysis/harness work only: stock behavior unchanged, no speed
  claim, no GPU migration, no 200% gate progress.

Classification:

- `analysis`, `spu-hle-451c-dynamic-0x46-family-ladder`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c Dynamic 0x46 List-Family Verifier Hook

Question:

- Can we turn the broad tag/size family ladder into a compile-checked
  verify-only C++ hook without changing stock MFC/list behavior?

Change:

- Added a new verify-only recognizer in local Windows `rpcs3-upstream`:
  `Eternal Sonata SPU HLE 451c list family verifier:`.
- It is gated by the existing safe conditions:
  - HLE verify mode only;
  - title/image/PC through the hot image path;
  - image `0x958dfe208b686622`;
  - PC `0x451c`;
  - `MFC_GETLF_CMD`;
  - `eah == 0`;
  - no accurate DMA and no MFC transfer shuffling.
- It counts the six measured broad `0x46` tag/size families:
  - tag `1`, size `8`;
  - tag `0`, size `8`;
  - tag `0`, size `16`;
  - tag `1`, size `16`;
  - tag `1`, size `24`;
  - tag `0`, size `24`.
- Stock behavior is unchanged: the hook only records counters after the normal
  dynamic MFC command path returns.
- `tools/summarize_eternal_sonata_gpu_probe.ps1` now parses this log row,
  exports `eternal-sonata-spu-hle-451c-list-family-profile.csv`, and emits an
  `SPU HLE 0x451c List-Family Verifier` Markdown section.

Touched files:

- `rpcs3-upstream/rpcs3/Emu/Cell/SPUThread.cpp`
- `rpcs3-upstream/rpcs3/Emu/Cell/SPUThread.h`
- `rpcs3-upstream/rpcs3/Emu/Cell/lv2/sys_spu.cpp`
- `tools/summarize_eternal_sonata_gpu_probe.ps1`

Verification:

```powershell
$null = [System.Management.Automation.PSParser]::Tokenize(
  (Get-Content .\tools\summarize_eternal_sonata_gpu_probe.ps1 -Raw),
  [ref]$null
)

cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" `
  --config Release --target rpcs3 --parallel 6
```

Results:

- PowerShell parser check passed.
- Release build passed and produced
  `rpcs3-upstream/build-msvc/bin/rpcs3.exe`.
- Synthetic parser smoke passed:
  `family-parser hits=42 tag1_size8=20 total_us=1234`.
- A full re-summary of the latest `54 MB` Windows run log was attempted after
  the parser change but timed out at `180s`; use a fresh shorter field run for
  real family counters instead of relying on that old giant log.

Reading:

- This is the first compile-checked broad-family counter hook for the dynamic
  `0x46` lane. It should answer whether the six tag/size families seen in the
  contract atlas actually light up in the live left200 field route.
- It is still not a fast path, not GPU migration, not speed, and not a 200%
  gate candidate.
- The next Windows-only step is a clean field capture with:
  `-EternalSonataSpuHleVerify Verify`, `-WindowsInputBackend PadApi`,
  `-WindowsGameScreen 1`, `-WindowsVisualGate CleanAfterField`, and the known
  left200 macro, then summarize the new
  `eternal-sonata-spu-hle-451c-list-family-profile.csv`.

Classification:

- `counter-only`, `spu-hle-451c-list-family-verifier-hook`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c List-Family Verify Field Attempt Rejected

Question:

- Does the new broad `0x451c` list-family verifier produce live field counters
  on the Windows left200 route without changing stock behavior?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-listfamily-verify-left200 `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 10 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-193629-hle-451c-listfamily-verify-left200-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host contention stayed clean: `6` host snapshots, worst external `clean`,
  worst total `clean`.
- No real crash/access/likely-crashed/assertion/Vulkan-device-lost pattern was
  found in the checked stdout/stderr/lab log and RPCS3 log tail.
- Title samples existed (`17` samples, average `38.40 FPS`), but they are not
  comparable because the visual route failed.

Visual gate:

- Status: `NO_FIELD_LIKE_SCREENSHOT`.
- First field-like screenshot: none.
- Required field-like screenshot by `160s`: failed.
- Class counts: `1` `wrong-window-or-other-small-png`, `13`
  `black-overlay-small-png`.
- Manual checks:
  - `screenshot-0117s.png` shows a starry/cutscene-like sky, not Path to
    Tenuto field gameplay.
  - `screenshot-0200s.png` is the same dark/starry/black-overlay state, still
    not field gameplay.

Counters from the invalid route:

- SPU HLE `0x451c` list-family rows: `488`.
- List-family hits: `63,783`; success/fail `63,783 / 0`.
- Family split:
  - tag1/size8: `4,857`;
  - tag0/size8: `4,851`;
  - tag0/size16: `20,569`;
  - tag1/size16: `20,217`;
  - tag1/size24: `6,584`;
  - tag0/size24: `6,705`.
- List-family descriptor bytes: `1.00 MB`.
- List-family timing: `83.234 ms` total, `1.305 us/hit` average,
  `7,124 us` max.
- Dynamic MFC fallback: `193,214` hits, `701.10 MB`, `268.515 ms`;
  PC split `0x25cc=36,965 / 94.276 ms`, `0x451c=156,249 / 174.239 ms`.
- MFC list transfer: `63,783` calls, `1.00 MB` descriptor bytes,
  `59.352 ms`, all at `0x451c`.
- GPU migration scoreboard remains zero: new promoted CPU/SPU-to-GPU
  replacement `0 B / 0.000%`, direct RSX-local `0 B`, indirect overlap `0 B`.

Parser follow-up:

- `tools/summarize_eternal_sonata_gpu_probe.ps1` parsed successfully after a
  string literal fix for the list-family reading. The previous double-quoted
  dynamic `0x46` phrase had interpreted backtick-zero as a NUL escape in the
  generated Markdown; future summaries now keep the literal backtick text.
- Re-running the full summarizer on this run timed out at `180s`, so the
  already generated counters above are kept as smoke evidence only.

Reading:

- The broad-family hook fires and sees all six families, but this run failed
  the visual proof gate. The numbers are useful only as counter smoke and
  parser validation.
- Do not make a list-family fast path from this run, do not compare its title
  FPS, and do not count it as a Windows micro-win or GPU migration credit.
- Next Windows-only work should repair or re-prove the `left200` route with the
  same verifier before trusting family timing, or add a route-control guard
  that rejects this starry/black-overlay state earlier.

Classification:

- `failed-cutscene-or-nonfield-visual`, `counter-smoke-only`,
  `spu-hle-451c-list-family-route-invalid`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c List-Family No-Movement Reproof

Question:

- Can the broad `0x451c` list-family verifier be measured on a clean Windows
  field route after the left200 attempt landed in starry/black-overlay state?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-listfamily-verify-nomove-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 8 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-195528-hle-451c-listfamily-verify-nomove-reproof-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host contention stayed clean: `5` host snapshots, worst external `clean`,
  worst total `clean`.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.
- Title samples existed (`12` samples, average `33.78 FPS`, min `28.29`,
  max `40.35`), but this is not a matched speed comparison.
- The outer Codex command timed out at `300s` after the lab had stopped RPCS3
  at `170s`, so the full GPU summarizer did not finish for this run. A narrow
  log parse was used for the counters below.

Visual gate:

- Status: `FIELD_LIKE_PRESENT`.
- First field-like screenshot: `screenshot-0117s.png` at `117s`.
- Invalid screenshots after first field-like: `0`.
- Required field-like screenshot by `160s`: passed.
- Class counts: `10` `field-like-large-png`.
- Manual check: `screenshot-0150s.png` shows clean Path to Tenuto field
  gameplay with the character visible, no black overlay, and no starry/cutscene
  route drift.

Counters from the clean route:

- SPU HLE `0x451c` list-family rows: `699`.
- List-family hits: `84,124`; success/fail `84,124 / 0`.
- Family split:
  - tag1/size8: `7,439`;
  - tag0/size8: `7,451`;
  - tag0/size16: `26,207`;
  - tag1/size16: `25,749`;
  - tag1/size24: `8,577`;
  - tag0/size24: `8,701`.
- List-family descriptor bytes: `1.30 MB`.
- List-family timing: `97.566 ms` total, about `1.160 us/hit` average,
  `14,578 us` max single row.
- Dynamic MFC probe: `223,347` hits, `450.0 MB`, `205.111 ms`;
  PC split `0x25cc=17,925 / 43.789 ms`, `0x451c=205,422 / 161.322 ms`.
- MFC list transfer: `84,124` calls, `1.30 MB` descriptor bytes,
  `72.014 ms`, all at `0x451c`, all GET list calls.
- GPU candidate rows: `1,285`, `1.86 GB` total observed DMA, direct
  RSX-local bytes `0`.

Reading:

- This reproof rescues the broad-family measurement from the previous invalid
  left200 capture. The family hook is alive on a clean field route and covers a
  large enough body to stay interesting for `0x451c` list-control/HLE/codegen
  work.
- It still does not move work to GPU, and it is not a speed proof. It is target
  sizing for a future preserve-order list-control or descriptor batching
  experiment.
- Repeated zero RSX-local bytes still park broad SPU-to-Vulkan compute. The
  candidate remains CPU/SPU HLE or codegen around `MFC_Cmd`,
  `process_mfc_cmd()`, and `do_list_transfer()`.

Classification:

- `valid-field-triage`, `spu-hle-451c-list-family-target-sizing`,
  `analysis`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  200% gate candidate.

## 2026-05-24 0x451c Dynamic Seed Predicate Sketch

Question:

- Can the `0x451c` contract report turn the top dynamic `0x46` seed table into
  a concrete verify-only C++ predicate shape for the next `SPUThread.cpp` edit?

Change:

- Extended `tools/summarize_eternal_sonata_451c_contract.ps1` with a
  `C++ Verifier Predicate Sketch` section.
- The sketch uses only the top two runtime-cost `0x46` seeds from the current
  valid-field corpus:
  - `cmd=0x46`, `tag=0`, `size=16`, `lsa=0x1b000`,
    EA `0x3f530..0x3f730`;
  - `cmd=0x46`, `tag=1`, `size=8`, `lsa=0x5c00`,
    EA `0x3f430..0x3f630`.
- It is intentionally pseudocode: reuse the existing BLUS30161/image/PC gate,
  reject accurate-DMA and shuffled-MFC modes, require `MFC_GETLF_CMD`, log
  verifier counters, and return to the stock MFC/list path.

Verification:

```powershell
$errors=$null; $tokens=$null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\tools\summarize_eternal_sonata_451c_contract.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
Select-String -Path .\debug-captures\windows-lab\_eternal-sonata-451c-contract-latest.md `
  -Pattern "C\+\+ Verifier Predicate Sketch","MFC_GETLF_CMD","0x1b000","0x5c00"
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

Result:

- Parser validation passed.
- The refreshed contract report emits `C++ Verifier Predicate Sketch` with both
  top seed clauses.
- The refiner still blocks repeated `loader-control-left200x2` movement reruns
  and points to SPU kernel HLE/codegen/verifier work.

Reading:

- This is the next C++ edit map, not a fast path. First implementation should
  add verify counters for these two list-control seeds and then fall through to
  stock behavior.
- It does not change GPU offload accounting. Newly promoted CPU/SPU-to-GPU work
  remains `0`, and broad SPU-to-Vulkan compute stays parked until a future
  scout proves RSX-consumed data.

Classification:

- `process-harness`, `spu-hle-451c-dynamic-seed-predicate`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 0x451c Contract Scout Shadow-Safety Upgrade

Question:

- Can the 0x451c contract scout report both heat and fast-path safety, so the
  loop does not keep rediscovering that the top descriptor is hot but not
  copy-elision safe?

Change:

- `tools/summarize_eternal_sonata_451c_contract.ps1` now reads
  `eternal-sonata-spu-hle-shadow-profile.csv` from the same valid field runs as
  the dynamic/list MFC contract scout.
- It emits `shadow-verify` rows into
  `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.csv`.
- It adds a `Top Shadow Safety Buckets` Markdown table with output match,
  mismatch, destination-change, skip-hit, EA, and verdict columns.

Verification:

- Ran:

```powershell
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
```

- The script completed successfully and refreshed:
  - `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.md`;
  - `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.csv`.
- CSV grouping now shows `569` `dynamic-mfc` rows, `538` `list-transfer` rows,
  and `1` `shadow-verify` row.
- `git diff --check` passed for the changed script and notes, with only the
  repo's normal LF-to-CRLF warnings.

Result:

- Dynamic MFC `0x451c`: `838,543` hits / `749.16 MB`.
- List-transfer `0x451c`: `342,651` calls / `5.31 MB` descriptor bytes.
- Shadow verifier `0x451c`: `3,647` hits / `911.75 KB`, `3,425` matches,
  `222` mismatches, `3,647` destination changes, `0` skip hits.
- The exact descriptor `cmd=0x40`, `tag=31`, `size=256`, `lsa=0x4a00`,
  EA `0x8ab280` is now classified as `not-skip-safe`.

Reading:

- This is a harness and analysis upgrade, not a speed win.
- It confirms the current best 0x451c direction is preserve-order HLE/codegen or
  descriptor batching, not copy elision.
- It also keeps broad SPU-to-Vulkan compute parked because valid field captures
  still show `0` direct RSX-local traffic and `0` indirect overlap.

Classification:

- `process-harness`, `spu-hle-451c-contract-safety`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c Shadow Hash-Family Analysis

Question:

- Does the exact 0x451c verifier bucket have stable source/output families that
  could justify payload replay/cache, or is it mostly descriptor/codegen
  overhead around real DMA movement?

Source:

- Run:
  `debug-captures/windows-lab/20260524-162146-hle-451c-contract-verify-left200-windows-windows`.
- CSV:
  `eternal-sonata-spu-hle-shadow-profile.csv`.
- Filter: `last_pc == 0x451c`.

Results:

- Rows / hits / bytes: `870 / 3647 / 911.75 KB`.
- Unique source hashes: `868`.
- Unique destination-pre hashes: `864`.
- Unique destination-post hashes: `868`.
- Output match / mismatch: `3425 / 222`.
- Destination changed: `3647`.
- Top source hash family: `0xfadf1838217a88de`, `44` hits / `11.0 KB`,
  `41` matches, `3` mismatches.
- No source family showed broad replay potential; the top full
  source/pre/post hash triple was the same `44` hits / `11.0 KB`.

Reading:

- This reinforces that 0x451c is not a payload replay/cache lane.
- Every observed hit changed LS destination data, and the source/output family
  set is high-entropy across the clean field run.
- The useful next Windows-only 0x451c experiment should reduce descriptor/list
  overhead or specialize preserve-order direct-copy/codegen behavior, while
  still performing the DMA. Do not attempt 0x451c copy elision from this proof.
- This is also still not a GPU lane: RSX-local and indirect overlap for the run
  remained `0`.

Classification:

- `analysis`, `spu-hle-451c-hash-family`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c Runtime-Cost Contract Ranking

Question:

- Can the `0x451c` contract scout rank descriptor buckets by measured runtime
  cost and proposed implementation lane, instead of only by hits or bytes?

Change:

- `tools/summarize_eternal_sonata_451c_contract.ps1` now computes
  `AvgUsPerHit`, `AvgBytesPerHit`, and `CandidateLane` for dynamic/list MFC
  descriptor buckets.
- It adds a `Top Runtime-Cost Descriptors` table and writes the new columns to
  `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.csv`.
- Candidate lanes are currently `exact-get-preserve-copy`,
  `small-list-control`, `large-preserve-copy`, `preserve-order-mfc`, and
  `list-descriptor-batch`.

Verification:

```powershell
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
Import-Csv .\debug-captures\windows-lab\_eternal-sonata-451c-contract-latest.csv |
  Select-Object -First 1 Kind,Cmd,Tag,Size,Lsa,TotalMs,AvgUsPerHit,AvgBytesPerHit,CandidateLane
```

- The report refreshed successfully.
- The Markdown report contains `Top runtime-cost descriptor` and
  `Top Runtime-Cost Descriptors`.
- The CSV first row is `dynamic-mfc`, `cmd=0x40`, `tag=31`, `size=256`,
  `lsa=0x4a00`, `TotalMs=100.605`, `AvgUsPerHit=0.750`,
  `AvgBytesPerHit=954.7`, lane `exact-get-preserve-copy`.

Result:

- Dynamic MFC `0x451c` total remains `838,543` hits / `749.16 MB`.
- List-transfer `0x451c` total remains `342,651` calls / `5.31 MB`
  descriptor bytes.
- Top runtime-cost descriptor:
  - `dynamic-mfc`, `cmd=0x40`, `tag=31`, `size=256`, `lsa=0x4a00`;
  - EA `0x8ab280`;
  - `100.605 ms`, `134,185` hits, `122.17 MB`, `0.750 us/hit`;
  - lane `exact-get-preserve-copy`.
- Next runtime-cost descriptors are mostly `cmd=0x46` small-list-control and
  list-transfer/list-descriptor buckets.
- Shadow safety did not change: the exact `0x451c` bucket is still
  `not-skip-safe` with `3,647` shadow hits, `222` mismatches, `3,647`
  destination changes, and `0` skip hits.

Reading:

- The highest measured cost is the exact small GET, followed by list-control and
  list-descriptor overhead. That makes preserve-order direct-copy/codegen
  specialization and batching many small MFC/list operations the next useful
  Windows-only work.
- This does not create a GPU migration lane. Valid field captures still show
  `0` direct RSX-local traffic and `0` indirect SPU-DMA/RSX-resource overlap.
- This does not prove speed or the 200% gate. It is a ranking tool for the next
  HLE/codegen experiment.

Classification:

- `process-harness`, `spu-hle-451c-runtime-cost-ranking`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 0x451c Lane Totals And Code-Path Map

Question:

- Is the next `0x451c` HLE/codegen slice still the exact `0x40` GET, or do
  lane totals say the bigger target is many small list-control/list-descriptor
  operations?

Change:

- Extended `tools/summarize_eternal_sonata_451c_contract.ps1` with a
  `Runtime-Cost Lane Totals` section.
- Lane totals group descriptor buckets by `CandidateLane`, aggregate hits,
  bytes, descriptor count, total measured time, and average microseconds per
  hit.
- Inspected the local Windows `rpcs3-upstream` MFC source path to map each lane
  to a plausible hook point before touching fast mode.

Verification:

```powershell
$errors=$null; $tokens=$null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\tools\summarize_eternal_sonata_451c_contract.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

- Parser validation passed.
- The report refreshed successfully and now includes `Runtime-Cost Lane Totals`.
- The refiner still blocks another `loader-control-left200x2` movement run and
  recommends SPU kernel HLE/codegen/verifier analysis.

Result:

Lane totals across the same `12` valid fatal-clean field runs:

| Rank | Lane | Descriptors | Hits | Bytes | Total ms | Avg us/hit |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | `small-list-control` | 443 | 542,190 | 483.95 MB | 397.914 | 0.734 |
| 2 | `list-descriptor-batch` | 538 | 342,651 | 5.31 MB | 279.314 | 0.815 |
| 3 | `large-preserve-copy` | 120 | 155,765 | 137.45 MB | 110.705 | 0.711 |
| 4 | `exact-get-preserve-copy` | 1 | 134,185 | 122.17 MB | 100.605 | 0.750 |
| 5 | `preserve-order-mfc` | 5 | 6,403 | 5.59 MB | 4.516 | 0.705 |

Source-path map:

- Dynamic MFC command writes flow through `MFC_Cmd`, then
  `process_mfc_cmd()`, then `do_dma_check()` / `do_dma_transfer()`.
- The exact `0x451c` GET verifier currently hooks the runtime GET path before
  `do_dma_transfer()`. Shadow evidence says it must preserve the copy, not skip
  it.
- List commands flow through the list branch of `process_mfc_cmd()`, then
  `do_list_transfer()`.
- `do_list_transfer()` already has a six-element GET inliner and per-item inline
  copy path, so the larger lane is probably descriptor/list-control overhead or
  dynamic-command recognition, not a brand-new one-dispatch-per-list GPU path.
- `SPULLVMRecompiler.cpp` still falls back for hot dynamic `MFC_Cmd` values when
  the command register is not constant, matching earlier logs for `0x451c`.

Reading:

- The best single hook is still the exact `0x40/tag31/256/0x4a00` GET, but the
  biggest lane total is now `small-list-control`, followed by
  `list-descriptor-batch`.
- This shifts the next useful Windows-only implementation step toward either a
  dynamic-command codegen recognizer or a list-control/list-descriptor batching
  verifier, instead of trying another copy-elision skip.
- This remains CPU/SPU HLE/codegen work. There is still `0` RSX-local traffic and
  `0` indirect RSX overlap, so broad SPU-to-Vulkan compute remains parked.

Classification:

- `process-harness`, `spu-hle-451c-lane-total-map`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 0x451c Implementation Hook Shortlist

Question:

- Can the `0x451c` contract report name the exact C++ hook point and next
  verifier for each lane, so the next heartbeat can implement instead of
  re-reading the same source map?

Change:

- Added `Get-LaneHookPoint` and `Get-LaneNextExperiment` helpers to
  `tools/summarize_eternal_sonata_451c_contract.ps1`.
- The report now includes an `Implementation Hook Shortlist` table after lane
  totals.
- A first report run caught a helper scoping mistake in `Add-SetValue`; fixed it
  and reran parser plus report generation.

Verification:

```powershell
$errors=$null; $tokens=$null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\tools\summarize_eternal_sonata_451c_contract.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
```

- Parser validation passed after the fix.
- The refreshed report contains `Implementation Hook Shortlist`.
- The report still uses `12` valid fatal-clean field runs and keeps the same
  lane totals.

Hook shortlist:

| Rank | Lane | Total ms | Hook point | Next verifier |
| ---: | --- | ---: | --- | --- |
| 1 | `small-list-control` | 397.914 | `SPUThread.cpp: MFC_Cmd -> process_mfc_cmd list branch; SPULLVMRecompiler.cpp dynamic MFC_Cmd fallback` | Verify a title/image/PC-gated dynamic-command recognizer for hot `0x46` descriptors before fast mode. |
| 2 | `list-descriptor-batch` | 279.314 | `SPUThread.cpp: do_list_transfer descriptor walker and six-element GET inliner` | Add descriptor-batch counters around `do_list_transfer()` and prove whether decode/control overhead can be reduced. |
| 3 | `large-preserve-copy` | 110.705 | `SPUThread.cpp: do_dma_transfer preserve-copy backend` | Preserve DMA semantics and test vectorized/copy-backend specialization, not skip. |
| 4 | `exact-get-preserve-copy` | 100.605 | `SPUThread.cpp: process_mfc_cmd -> do_dma_transfer exact 0x451c GET` | Specialize exact GET codegen/copy dispatch while preserving destination writes; copy elision is blocked. |

Reading:

- The next concrete implementation slice should be a verify-only dynamic
  command/list-control recognizer around `0x451c` and hot `0x46` descriptors.
- The exact `0x40` GET is still a useful single descriptor, but it is no longer
  the largest lane by total measured cost.
- This is a CPU/SPU HLE/codegen shortlist only. It still has no RSX-local or
  indirect RSX overlap evidence and must not be called GPU migration or speed
  proof.

Classification:

- `process-harness`, `spu-hle-451c-hook-shortlist`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 0x451c Dynamic Recognizer Seed Set

Question:

- Which exact `0x46` descriptor shapes should the next verify-only C++
  recognizer target first?

Change:

- Added a `Dynamic Command Recognizer Seeds` table to
  `tools/summarize_eternal_sonata_451c_contract.ps1`.
- The table filters `CandidateLane == small-list-control` and `cmd == 0x46`,
  sorts by measured runtime cost, and emits a copyable verifier seed key:
  title, image, PC, command, tag, size, LSA, and EA range.

Verification:

```powershell
$errors=$null; $tokens=$null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path .\tools\summarize_eternal_sonata_451c_contract.ps1),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
Import-Csv .\debug-captures\windows-lab\_eternal-sonata-451c-contract-latest.csv |
  Where-Object { $_.CandidateLane -eq 'small-list-control' } |
  Sort-Object {[double]$_.TotalMs} -Descending |
  Select-Object -First 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

- Parser validation passed.
- The report refreshed successfully and contains `Dynamic Command Recognizer
  Seeds`.
- The refiner still blocks `loader-control-left200x2` movement reruns and points
  back to SPU kernel HLE/codegen/verifier work.

Top recognizer seeds:

| Rank | Seed | Hits | Bytes | Total ms | Runs |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | `title=BLUS30161,image=0x958dfe208b686622,pc=0x451c,cmd=0x46,tag=0,size=16,lsa=0x1b000,ea=0x3f530..0x3f730` | 24,705 | 23.92 MB | 29.614 | 3 |
| 2 | `title=BLUS30161,image=0x958dfe208b686622,pc=0x451c,cmd=0x46,tag=1,size=8,lsa=0x5c00,ea=0x3f430..0x3f630` | 10,273 | 9.88 MB | 24.661 | 3 |
| 3 | `title=BLUS30161,image=0x958dfe208b686622,pc=0x451c,cmd=0x46,tag=1,size=16,lsa=0x4c00,ea=0x3f430..0x3f630` | 1,821 | 1.45 MB | 14.227 | 3 |
| 4 | `title=BLUS30161,image=0x958dfe208b686622,pc=0x451c,cmd=0x46,tag=0,size=8,lsa=0x6800,ea=0x3f730..0x3f730` | 671 | 714.12 KB | 11.962 | 2 |

Reading:

- The first verify-only recognizer should target the top two seeds, not the
  whole `0x46` universe.
- The EA ranges are tiny descriptor/control regions around `0x3f430..0x3f730`,
  so this still smells like CPU/SPU descriptor/list-control overhead, not a GPU
  resident data path.
- Keep broad SPU-to-Vulkan compute parked. This seed set is for HLE/codegen
  recognition and later speed testing only after field/menu/battle proof.

Classification:

- `process-harness`, `spu-hle-451c-dynamic-recognizer-seeds`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 SPU HLE 0x451c Verify-Only Contract Proof

Question:

- Can the current top `0x451c` MFC descriptor be proved on a clean Windows field
  route as a stable HLE/codegen contract candidate, without enabling a fast path?

Change:

- Local Windows `rpcs3-upstream` now treats the exact Eternal Sonata descriptor
  `pc=0x451c`, `cmd=0x40`, `tag=31`, `size=256`, `lsa=0x4a00`,
  EA `0x8ab280`, image `0x958dfe208b686622`, group
  `TCX_CellSpursKernelGroup` / `TCX_CellSpursKernel0` as a `Verify` shadow
  candidate.
- `Skip` / `Fast` is still blocked for `0x451c`; the skip path remains limited
  to the older exact `0x25cc` guarded shape.
- After the run, the disabled-mode guard was moved ahead of candidate checks so
  stock/off modes do no extra shape work.

Build:

- `cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6`
- Build passed and produced `build-msvc\bin\rpcs3.exe`.
- Existing warning only: `LNK4098` defaultlib conflict.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-contract-verify-left200-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 10
```

Run:

- `debug-captures/windows-lab/20260524-162146-hle-451c-contract-verify-left200-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`; CPU affinity `0x0F` applied.
- Visual gate passed as `FIELD_LIKE_PRESENT`; first field screenshot was
  `screenshots/screenshot-0117s.png`.
- Manual checks of `screenshot-0117s.png` and `screenshot-0200s.png` show clean
  Path to Tenuto field visuals after the one-pulse movement route.
- Fatal scan found no access violation, likely-crashed line, assertion, Vulkan
  device-loss line, or unhandled exception.
- `window-title-samples.csv` had `17` samples, average `30.17 FPS`, median
  `29.80`, min `25.64`, max `35.73`.

Counters:

- SPU HLE verifier records: `1580`.
- SPU HLE shadow records: `1579`.
- MFC dynamic records: `1580`.
- MFC list-transfer records: `840`.
- RSX-local traffic records: `0`.
- Indirect RSX resource overlap records: `0`.
- Offload fit mix: `spu-kernel-hle=1141`, `too-small=439`.

Exact `0x451c` shadow bucket:

- Rows / hits / bytes: `870 / 3647 / 911.8 KB`.
- Output match / mismatch: `3425 / 222`.
- Destination changed / unchanged: `3647 / 0`.
- Skip hits / misses: `0 / 0`.
- Unique source hashes: `868`.
- Interpretation: this is not a redundant-copy skip candidate. The exact GET is
  hot and targetable, but a fast path must preserve DMA semantics or reduce
  codegen/descriptor overhead rather than eliding the transfer.

Exact `0x451c` MFC traffic in this run:

- Dynamic rows / hits / bytes: `870 / 271497 / 253.66 MB`.
- Dynamic success / fail: `271497 / 0`.
- Dynamic time in `pc451c_us`: `222.712 ms`.
- List-transfer rows / calls / descriptor bytes: `840 / 110821 / 1.71 MB`.
- List-transfer success / fail: `110821 / 0`.
- List-transfer time in `pc451c_us`: `93.600 ms`.

Refreshed contract scout:

- `.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12`
  now includes this clean field run.
- Valid fatal-clean field runs used: `12`.
- Dynamic `0x451c` hits / bytes: `838543 / 749.16 MB`.
- List-transfer `0x451c` calls / descriptor bytes: `342651 / 5.31 MB`.
- Top dynamic descriptor remains `cmd=0x40`, `tag=31`, `size=256`,
  `lsa=0x4a00`, EA `0x8ab280`, now `134185` hits / `122.17 MB` across
  `3` valid runs.

Reading:

- This is a useful, clean HLE/codegen target proof for the current largest SPU
  lane.
- It is not speed proof: the run stayed around `30 FPS`, and no fast path was
  enabled.
- It is not GPU migration credit: newly promoted CPU/SPU-to-GPU replacement,
  direct RSX-local scout traffic, and indirect SPU-DMA/RSX-resource overlap all
  remained `0`.
- Broad SPU-to-Vulkan compute remains parked. The next useful Windows-only step
  is a narrower `0x451c` codegen/HLE verifier that classifies descriptor
  overhead, stable source/output families, and safe batching opportunities
  before any GPU experiment.

Classification:

- `spu-hle-451c-contract-proof`, analysis / HLE-codegen target proof,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 Harness Refiner Latest-Failure Lower-Boundary Patch

Question:

- Can the continual refiner block a repeated `left200x2` black-overlay
  failure when the latest run is the failure itself, not the clean lower
  boundary run?

Change:

- Updated `tools/ps3_harness_refiner.ps1` so the repeated-next-loader-control
  guard uses the newest valid loader-control lower boundary when the latest run
  is not valid.
- Updated `.agents/skills/ps3-continual-harness-refiner/SKILL.md` with the
  same rule: a latest failed next movement count must still be compared against
  the newest valid lower boundary before suggesting more movement.

Verification:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\ps3_harness_refiner.ps1), [ref]$tokens, [ref]$errors) | Out-Null
```

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

Result:

- Parser validation passed.
- The refiner now reports:
  `repeated-next-loader-control-failure` for `loader-control-left200x2`,
  because that movement count failed `2` times in the recent window after a
  lower clean `left200` boundary.
- The next action is:
  `Do not repeat loader-control-left200x2. It failed 2 time(s) in the recent
  window after a lower clean boundary; repair route control or switch to SPU
  kernel HLE/codegen/verifier analysis before another movement run.`
- The suggested command is intentionally only a comment, not another automatic
  movement capture.

Classification:

- `process-harness`, `route-tooling`, duplicate-run prevention, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 SPU HLE Atlas Refresh After Route Block

Question:

- With `left200x2` blocked by repeated black-overlay failures, which
  fatal-clean Windows field captures should drive the next CPU/SPU speed
  surgery?

Command:

```powershell
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 20 -Top 16
```

Result:

- Refreshed atlas:
  `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.md`.
- CSV:
  `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.csv`.
- Recent run dirs scanned: `20`.
- Valid field runs used: `13`.
- Field-like runs excluded by fatal logs: `0`.
- Top bucket remains `0x451c`, now stronger after including the latest clean
  field captures:
  - group/SPU: `TCX_CellSpursKernelGroup` / `TCX_CellSpursKernel0`;
  - recommendation: `spu-hle-codegen-priority`;
  - total: `11.19 GB`;
  - records: `5013`;
  - GET / PUT / list GET: `2.43 GB` / `3.98 GB` / `4.79 GB`;
  - max job: `22.08 MB`;
  - RSX-local: `0 B`.
- Second bucket is `0x25cc` with `10.43 GB`, but the exact guarded skip shape
  remains demoted by the title-CSV A/B where `Verify` averaged `116.57 FPS`
  and `Skip` averaged `111.32 FPS`.
- Latest valid disassembly cue for `0x451c`:
  `debug-captures/windows-lab/20260524-152813-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows/spu-images/BLUS30161-spu-image-958dfe208b686622-entry-00818-pc-0451c-group-TCX_CellSpursKernelGroup-spu-0-TCX_CellSpursKernel0.disasm.txt`.

Reading:

- This is useful speed-target selection, not a speed result.
- No candidate in the valid field set has RSX-local bytes, so broad
  SPU-to-Vulkan compute remains parked.
- The next Windows-only speed-surgery step should be a verify-only `0x451c`
  MFC descriptor/range/body HLE or codegen contract. Do not start fast mode or
  GPU migration credit until the verifier proves correctness and field/menu/
  first-battle visuals survive.

Classification:

- `analysis`, `spu-hle-codegen-priority`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c MFC Contract Scout

Question:

- Can the `0x451c` HLE/codegen priority bucket be narrowed into concrete
  command/tag/size/LSA descriptor shapes before touching fast-path code?

Change:

- Added `tools/summarize_eternal_sonata_451c_contract.ps1`.
- The tool scans recent Windows run directories, keeps only fatal-clean
  `FIELD_LIKE_PRESENT` field runs, imports:
  - `eternal-sonata-mfc-dynamic-profile.csv`;
  - `eternal-sonata-mfc-list-transfer-profile.csv`.
- It filters to title `BLUS30161`, image `0x958dfe208b686622`,
  `TCX_CellSpursKernelGroup` / `TCX_CellSpursKernel0`, and last PC `0x451c`.
- It aggregates descriptor buckets by dynamic/list kind, command, tag, size,
  LSA, EA range, hits/calls, bytes, timing, and run count.

Verification:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_451c_contract.ps1), [ref]$tokens, [ref]$errors) | Out-Null
```

```powershell
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
```

Result:

- Parser validation passed.
- Output:
  `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.md`.
- CSV:
  `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.csv`.
- Valid fatal-clean field runs used: `12`.
- Dynamic MFC `0x451c` hits: `567,046`.
- Dynamic MFC observed bytes: `507.25 MB`.
- List-transfer `0x451c` calls: `231,830`.
- List descriptor bytes observed: `3.59 MB`.
- Top dynamic descriptor:
  - command: `0x40`;
  - tag: `31`;
  - size: `256`;
  - LSA: `0x4a00`;
  - runs: `2`;
  - records: `333`;
  - hits: `90,673`;
  - bytes: `83.34 MB`;
  - timing: `54.666 ms` total, max `6741 us`;
  - EA range: `0x8ab280` to `0x8ab280`.
- Top list-transfer descriptor:
  - command: `0x46`;
  - tag: `1`;
  - size: `8`;
  - LSA: `0x8c00`;
  - runs: `2`;
  - records: `110`;
  - calls: `9,154`;
  - descriptor bytes: `140.10 KB`.

Reading:

- This narrows the first `0x451c` verifier from "the whole dynamic/list bucket"
  to a concrete exact descriptor: `cmd=0x40`, `tag=31`, `size=256`,
  `lsa=0x4a00`, `ea=0x8ab280`.
- The next code step should be verify-only: shadow this exact descriptor,
  record source/destination or descriptor-state hashes, and prove whether the
  body/output contract is stable before any fast return.
- This is still CPU/SPU HLE/codegen target selection. It is not a speed result,
  not GPU migration credit, and not 200% evidence. Vulkan compute stays parked
  because the valid field set still has `0 B` RSX-local bytes for the bucket.

Classification:

- `analysis`, `spu-hle-451c-contract-scout`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 Loader-Control Left200 Reconfirm After Fatal Control

Question:

- After the no-movement route-control fatal/black-overlay rejection, can the
  newest clean one-pulse `left200` field boundary be re-proved before any
  further movement, HLE fast mode, or GPU-offload experiment?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-left200-reconfirm-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 10
```

Run:

- `debug-captures/windows-lab/20260524-152813-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows`.
- The outer Codex shell command timed out at `420s`, but the lab itself
  stopped RPCS3 at the intended `205s` wall-time limit and wrote the run log.
- RPCS3 stayed on `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host contention summary stayed `clean`; external host summary stayed `clean`
  across `6` snapshots.
- Lab exit code: `exited`; no `rpcs3` process remained afterward.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first accepted field screenshot
  `screenshot-0117s.png` at `117s` (`2.49 MB`), `14` field-like screenshots,
  and `0` invalid screenshots after first field.
- Manual checks of `screenshot-0136s.png` after the one `ls_left:200` pulse
  and `screenshot-0200s.png` at the end show clean Path to Tenuto field, no
  black overlay, and no obvious texture corruption.
- Fatal scan found no real access violation, likely-crashed, STOP, assertion,
  Vulkan validation, or unhandled-exception hit.
- `window-title-samples.csv` contained `17` samples, average `32.64 FPS`,
  min `22.85`, max `37.30`. This is route-control context only, not a speed
  claim.

Counters:

- The full PowerShell GPU-probe summarizer timed out before writing the final
  summary Markdown, but it produced the main CSVs. Manual aggregation from
  those CSVs is below.
- GPU probe rows: `1,626`.
- Total observed DMA bytes: `2,561.65 MB`.
- Largest single job: `14.98 MB` in `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`, hot PC `0x451c`.
- Direct RSX-local scout traffic: `0` records.
- Offload fit mix: `spu-kernel-hle=1200`, `too-small=426`.
- Dynamic MFC hits: `296,247`, success/fail `296,247 / 0`,
  bytes `614.87 MB`, timing `204.668 ms`.
- Dynamic MFC PC mix: `0x451c=271,282` hits / `180.705 ms`,
  `0x25cc=24,965` hits / `23.963 ms`.
- MFC list-transfer calls: `110,940`, success/fail `110,940 / 0`,
  all at `0x451c`, timing `101.879 ms`, direction mix `get=110,940`.

Reading:

- This repairs the newest accepted-field movement boundary after the
  no-movement fatal control. The safe boundary is again exactly one
  `ls_left:200` pulse.
- It is not a speed result and not GPU migration credit. The run is CPU4 /
  reservation-loop verify route-control, and direct RSX-local traffic remains
  `0`.
- The refiner now says a second tiny `left200` pulse can be tried with
  `CleanAfterField`, but lane-2 HLE/GPU dry-runs remain blocked until visuals
  are clean for the deeper route and later menu/first-battle proof.

Classification:

- `analysis`, `route-tooling`,
  `loader-control-left200-reconfirm-field-clean-after-fatal-control`,
  not `windows-micro-win`, not `gpu-migration-credit`,
  not a 200% gate candidate.

## 2026-05-24 Loader-Control Left200x2 Retry Rejection After Clean Left200

Question:

- After re-proving the clean one-pulse `left200` field boundary, can the route
  safely extend by one more `ls_left:200` pulse with `CleanAfterField`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-left200x2-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -MaxSeconds 215 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 11
```

Run:

- `debug-captures/windows-lab/20260524-154613-cpu4-loader-control-left200x2-visualgate-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host contention stayed `clean`; external host stayed `clean` across `7`
  snapshots.
- Lab stopped RPCS3 at the intended `215s` wall-time limit; exit code
  `exited`; no active `rpcs3` process remained afterward.
- The sprint wrapper exited nonzero only because the visual gate failed.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`, `16` screenshots all
  `black-overlay-small-png`, first screenshot `screenshot-0117s.png`
  `57,176` bytes, later screenshots `34,977` bytes, and required field by
  `160s` failed.
- Manual `screenshot-0138s.png` shows a dark/starfield-like background with the
  performance overlay, not Path to Tenuto.
- Fatal scan found no real access violation, likely-crashed, STOP, assertion,
  Vulkan validation, or unhandled-exception hit.
- `window-title-samples.csv` contained `20` samples, average `31.31 FPS`,
  min `31.21`, max `33.30`; these samples are invalid for speed because the
  visual route is wrong.

Counters from invalid visual route:

- GPU probe rows: `1,760`.
- Total observed DMA bytes: `2,782.60 MB`.
- Largest single job: `10.88 MB` in `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`, hot PC `0x451c`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- Offload fit mix: `spu-kernel-hle=1551`, `too-small=209`.
- GPU Port Scoreboard: promoted CPU/SPU -> GPU replacement `0` records /
  `0 B`; direct RSX-local `0` records / `0 B`; indirect overlap `0` /
  `0 B`.
- Hot PC totals: `0x25cc=2,175.78 MB`, `0x451c=606.82 MB`.
- Dynamic MFC hits: `170,860`, success/fail `170,860 / 0`,
  bytes `761.92 MB`, timing `158.906 ms`.
- Dynamic MFC PC mix: `0x451c=128,087` hits / `118.725 ms`,
  `0x25cc=42,773` hits / `40.181 ms`.
- MFC list-transfer calls: `52,423`, all at `0x451c`, timing `23.130 ms`,
  direction mix `get=52,423`.
- Reservation loop verify records: `6,919`.
- Refiner lane-2 summary stayed clean, but this is blocked evidence because
  visuals failed.

Reading:

- `left200x2` has now failed again immediately after a clean `left200`
  boundary. Do not repeat it as the next automatic step.
- The newest valid movement boundary remains exactly one `ls_left:200` pulse.
- The counters again show `0` RSX-local and `0` indirect overlap, so broad
  SPU-to-Vulkan compute remains parked.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8` now chooses route control instead
  of more movement: re-prove no-movement loader/control or add/use a
  black-overlay route-control detector before any movement or lane-2 HLE/GPU
  dry-run.

Classification:

- `failed`, `route-tooling`,
  `loader-control-left200x2-retry-black-overlay-after-clean-left200`,
  `not-comparable-visual`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 No-Movement Route-Control Fatal Black-Overlay Rejection

Question:

- After the `left200x2` black-overlay rejection, can the no-movement CPU4
  loader-control route re-prove a clean field boundary?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260524-151406-cpu4-loader-control-visualgate-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host contention summary stayed `clean` across `6` snapshots.
- Lab stopped RPCS3 at the intended `190s` wall-time limit; exit code
  `exited`; no active `rpcs3` process was left afterward.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`. The first screenshot
  (`screenshot-0117s.png`, `236,973` bytes) was classified
  `wrong-window-or-other-small-png`; the next `9` screenshots from `132s`
  through `190s` were all `black-overlay-small-png` at `34,484` bytes.
- Manual checks match the gate: `screenshot-0117s.png` shows a sky/starfield
  style non-field frame, and `screenshot-0150s.png` is a black-overlay frame,
  not Path to Tenuto.
- Fatal scan found a real access violation:
  `VM: Access violation reading location 0x14` at PPU PC `0x002c067c`.
- `window-title-samples.csv` contained `13` samples, average `34.55 FPS`,
  min `34.46`, max `35.58`; these samples are invalid for speed because the
  route visual state and fatal scan failed.

Counters from invalid route:

- Total observed DMA bytes: `1,477.26 MB`.
- Largest single job: `11.34 MB` in `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- Offload fit mix: `spu-kernel-hle=715`, `too-small=251`.
- GPU Port Scoreboard: promoted CPU/SPU -> GPU replacement `0` records /
  `0 B`; direct RSX-local `0` records / `0 B`; indirect overlap `0` /
  `0 B`.
- Dynamic MFC hits: `172,123`, success/fail `172,123 / 0`,
  bytes `365.47 MB`.
- Dynamic MFC PC mix: `0x451c=157,878` hits / `237.341 ms`,
  `0x25cc=14,245` hits / `14.133 ms`.
- MFC list-transfer calls: `64,773`, all at `0x451c`,
  timing `121.253 ms`, direction mix `get=64,773`.
- Reservation loop verify records: `3,612`.
- Reservation lane join: known exact-PC PUTLLC command/read peaks
  `53,069 / 53,069`.

Reading:

- The route-control problem is now before movement, not just at `left200x2`.
  The earlier clean `left200` boundary should be treated as stale until the
  no-movement field route is re-proved.
- The counters again point at SPU HLE/codegen/reservation-loop work and repeat
  the same `0` RSX-local / `0` indirect-overlap signal, so broad SPU-to-Vulkan
  compute remains parked.
- Do not start movement, lane-2 HLE fast mode, or GPU-offload experiments from
  this state. The next Windows-only step should repair route control or make the
  black-overlay/fatal detector block the route before any performance proof.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8` now flags the latest run as
  `failed-fatal-log`, notes `3/8` recent black-overlay pre-field runs and `2/8`
  fatal-log runs, and chooses a single safe next action: re-prove
  `loader-control-left200x1` with `CleanAfterField` before adding another pulse.

Classification:

- `failed`, `route-tooling`, `loader-control-no-movement-black-overlay-fatal`,
  `not-comparable-visual`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c Verify Telemetry And Route Reproof

Question:

- Did the `0x451c` verify-only telemetry hook produce useful dynamic/list MFC
  evidence, and is the Windows route still clean after the latest fatal/black
  capture?

Change under test:

- `rpcs3-upstream/rpcs3/Emu/Cell/SPUThread.cpp` now lets
  `RPCS3_ES_SPU_HLE_VERIFY=verify` enable the existing Eternal Sonata hot-image
  dynamic/list MFC telemetry path. This is instrumentation only, not a fast
  path and not a skip.

Build:

```powershell
cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6
```

Result:

- Build succeeded and produced
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\rpcs3.exe`.

Telemetry run:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-verify-telemetry-field-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate ExternalFail
```

Run:

- `debug-captures/windows-lab/20260524-135719-hle-451c-verify-telemetry-field-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`, with external host grade `clean`.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`, `6` screenshots all
  `black-overlay-small-png` around `34.55 KB`.
- Manual `screenshot-0150s.png` check shows a blue/black overlay state with
  FPS overlay only, not Path to Tenuto field.
- Fatal scan found a real crash:
  `VM: Access violation reading location 0x14` at `PPU[0x1000000]`
  PC `0x002c067c`.
- Title samples were flat at `99.57 FPS`, but they are invalid for speed
  because the run crashed/black-overlayed.

Telemetry evidence from the invalid run:

- SPU HLE verifier records: `274`.
- SPU HLE shadow records: `273`.
- MFC dynamic records: `655`.
- MFC list transfer records: `348`.
- Total observed DMA bytes: `1,157.28 MB`.
- Dynamic MFC hits: `155,363`, success/fail `155,363 / 0`,
  bytes `303.46 MB`, total timing `97.616 ms`.
- Dynamic MFC PC mix: `0x451c=146,590` hits / `66.156 ms`,
  `0x25cc=8,773` hits / `31.46 ms`.
- MFC list-transfer calls: `56,893`, all successful, PC mix
  `0x451c=56,893` hits / `31.045 ms`, direction mix `get=56,893`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- GPU Port Scoreboard remains `0` promoted CPU/SPU -> GPU replacement,
  `0 B` direct RSX-local, and `0 B` indirect overlap.

Reading:

- The instrumentation change worked: `Verify` can now light up dynamic MFC and
  list-transfer telemetry without using `MFC_LADDER`.
- The run itself is invalid for speed, visual proof, and HLE/GPU promotion due
  the access violation and black-overlay screenshots.
- The useful signal is target selection only: `0x451c` is the dominant dynamic
  MFC/list-transfer issuer, but the list issuing body itself is still only
  tens of milliseconds across the route. The next HLE/codegen scout should look
  beyond one-dispatch GPU copies and into the SPU consumer/body or a verified
  larger `0x451c` contract.
- Repeated `0` RSX-local/overlap evidence still parks broad SPU-to-Vulkan
  compute.

Classification:

- `spu-hle-451c-telemetry-unlocked`, `failed-fatal-log`,
  `failed-black-overlay-visual`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

Route-control reproof:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260524-141706-cpu4-loader-control-visualgate-windows-windows`.
- The outer shell command timed out after `300s`, but the lab had already
  stopped RPCS3 at the intended `190s` wall-time limit and wrote the run log.
- RPCS3 stayed on `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host contention summary: `clean`, external `clean`, across `6` snapshots.
- Visual gate passed after manual post-processing:
  `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.50 MB`), `10` field-like screenshots,
  and `0` invalid screenshots after first field.
- Manual `screenshot-0190s.png` check shows clean Path to Tenuto field with
  Polka visible and no black-overlay corruption.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.
- No `rpcs3` process remained after the run.
- `window-title-samples.csv` contained `13` samples, average `31.83 FPS`,
  min `29.86`, max `36.16`. This is route-control context only, not a speed
  baseline, because the run is CPU4/reservation-loop verify and not matched
  against a candidate.
- The GPU probe summarizer timed out on the `79.7 MB` log during the heartbeat,
  so no new counter summary is banked from this route-control run.

Reading:

- The newest safe boundary is a clean no-movement CPU4 field route. Use this
  before adding another HLE/codegen verifier or GPU experiment.
- The failed `0x451c` telemetry run must not drive speed claims. Its counters
  can guide target choice only.

Classification:

- `route-tooling`, `loader-control-field-clean-after-fatal-reproof`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

## 2026-05-24 Loader-Control Left200 Reproof After Fatal

Question:

- After re-proving the no-movement field boundary, can the Windows route add
  one small state-aware movement pulse without repeating the black-overlay or
  fatal-log failure?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-left200-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 10
```

Run:

- `debug-captures/windows-lab/20260524-143730-cpu4-loader-control-left200-visualgate-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host contention summary: `clean`, external `clean`, across `6` snapshots.
- Lab stopped RPCS3 at the intended `205s` wall-time limit; exit code
  `exited`; no `rpcs3` process remained afterward.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.49 MB`), `14` field-like screenshots,
  `0` invalid screenshots after first field, and required field by `160s`
  passed.
- Manual `screenshot-0135s.png` after the `ls_left:200` pulse and
  `screenshot-0200s.png` at the end show clean Path to Tenuto field with
  Polka, no black overlay, and no obvious texture corruption.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.
- `window-title-samples.csv` contained `17` samples, average `32.35 FPS`,
  min `27.89`, max `37.35`. This is route-control context only, not a speed
  claim.

Counters:

- Total observed DMA bytes: `2,611.38 MB`.
- Largest single job: `22.08 MB` in `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- Offload fit mix: `spu-kernel-hle=1190`, `too-small=427`.
- GPU Port Scoreboard: promoted CPU/SPU -> GPU replacement `0` records /
  `0 B`; direct RSX-local `0` records / `0 B`; indirect overlap `0` /
  `0 B`.
- Dynamic MFC hits: `319,520`, success/fail `319,520 / 0`,
  bytes `613.71 MB`.
- Dynamic MFC PC mix: `0x451c=296,059` hits / `210.411 ms`,
  `0x25cc=23,461` hits / `24.085 ms`.
- MFC list-transfer PC mix: `0x451c=121,014` hits / `83.873 ms`,
  direction mix `get=121,014`.
- Reservation loop verify records: `6,052`.
- Reservation lane join: known exact-PC PUTLLC command/read peaks
  `28,134 / 28,134`, with `0` lanes missing live verify rows.

Reading:

- This repairs the immediate route-control problem after the fatal/black
  `0x451c` telemetry run. The newest safe route boundary is now one
  `ls_left:200` movement pulse.
- The run again says the hot work is SPU HLE/codegen/reservation-loop work,
  not broad SPU-to-Vulkan compute: `0` direct RSX-local and `0` indirect
  overlap.
- The `0x451c` list/dynamic MFC issuer remains the hottest measured target,
  but this run is not a speed A/B and not a GPU migration path.
- Next useful step is either one more tiny route movement proof if the refiner
  asks for it, or a verify-only `0x451c` body/descriptor contract from this
  clean route boundary. Do not start lane-2 HLE/GPU fast mode from counters
  alone.

Classification:

- `route-tooling`, `loader-control-left200-field-clean-after-fatal-reproof`,
  `spu-hle-codegen-target-support`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 Loader-Control Left200x2 Black-Overlay Rejection

Question:

- Can the newest clean one-pulse route boundary safely extend by one more
  `ls_left:200` pulse, or does it repeat the invalid black-overlay route
  failure?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-left200x2-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -MaxSeconds 215 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 11
```

Run:

- `debug-captures/windows-lab/20260524-150020-cpu4-loader-control-left200x2-visualgate-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`; CPU affinity `0x0F` was applied.
- Host contention summary: `clean`, external `clean`, across `7` snapshots.
- Lab stopped RPCS3 at the intended `215s` wall-time limit; exit code
  `exited`.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.
- No `rpcs3` process remained afterward.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; `16` screenshots were all
  `black-overlay-small-png` around `55 KB`, and no field-like screenshot was
  found by `160s`.
- Manual `screenshot-0138s.png` and `screenshot-0210s.png` checks show a
  black background with the character model and performance overlay, not Path
  to Tenuto field. This is real route/visual failure, not a byte-size heuristic
  false negative.
- `window-title-samples.csv` contained `20` samples, average `45.02 FPS`,
  min `37.41`, max `53.29`; those samples are invalid for speed because the
  route visual state is wrong.

Counters from invalid visual route:

- Total observed DMA bytes: `1,951.13 MB`.
- Largest single job: `4.38 MB` in `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- Offload fit mix: `spu-kernel-hle=1025`, `too-small=665`.
- GPU Port Scoreboard: promoted CPU/SPU -> GPU replacement `0` records /
  `0 B`; direct RSX-local `0` records / `0 B`; indirect overlap `0` /
  `0 B`.
- Dynamic MFC hits: `234,452`, success/fail `234,452 / 0`,
  bytes `494.21 MB`.
- Dynamic MFC PC mix: `0x451c=216,943` hits / `148.184 ms`,
  `0x25cc=17,509` hits / `17.296 ms`.
- MFC list-transfer PC mix: `0x451c=87,842` hits / `76.429 ms`,
  direction mix `get=87,842`.
- Reservation loop verify records: `6,166`.
- Reservation lane join: known exact-PC PUTLLC command/read peaks
  `28,005 / 28,004`, with `0` lanes missing live verify rows.

Reading:

- `left200x2` is currently not a valid route boundary from this launch shape.
  It should not be used for speed, HLE fast-mode, or GPU-offload decisions.
- The previous `left200` run remains the newest clean movement boundary.
- Counters remain useful only as target-selection context and repeat the same
  direction: no RSX-local traffic, no indirect overlap, and dominant `0x451c`
  dynamic/list MFC issuer traffic. Broad SPU-to-Vulkan compute stays parked.
- The next refiner action should back off to the clean `left200` boundary or
  improve route-state detection before trying more movement. Do not infer a
  speed win from the higher title FPS in the invalid black scene.

Classification:

- `failed`, `route-tooling`, `loader-control-left200x2-black-overlay`,
  `not-comparable-visual`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 SPU HLE Guarded Skip Title-FPS CSV A/B

Question:

- Does the new machine-readable `window-title-samples.csv` confirm the earlier
  manual screenshot impression that the guarded `0x25cc` skip is a small
  Windows speed win?

Commands:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-verify-titlecsv-uncap240-field-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate ExternalFail
```

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-skip-titlecsv-uncap240-field-windows `
  -EternalSonataSpuHleVerify Skip `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate ExternalFail
```

Runs:

- Verify:
  `debug-captures/windows-lab/20260524-125346-hle-shadow-verify-titlecsv-uncap240-field-windows-windows`.
- Skip:
  `debug-captures/windows-lab/20260524-125942-hle-shadow-skip-titlecsv-uncap240-field-windows-windows`.
- Both stayed on `\\.\DISPLAY2`, used PadApi, frame/vblank `240/240`,
  and passed `ExternalFail` with external host grade `clean` across all
  `5` host snapshots while total self-load was `moderate`.
- Both visual gates passed: first field-like screenshot at `117s`, `6`
  field-like screenshots each, and `0` invalid screenshots after first
  field-like output.
- Manual `screenshot-0150s.png` checks show clean Path to Tenuto field in
  both runs. The title bar read `120.17 FPS` for Verify and `113.84 FPS`
  for Skip at that screenshot.
- Fatal scans found no real crash/access/likely-crashed/assertion/Vulkan hit
  in either run.

Title-FPS CSV comparison:

| Mode | Samples | Average FPS | Median FPS | Min FPS | Max FPS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Verify | 8 | 116.57 | 117.88 | 106.85 | 120.17 |
| Skip | 8 | 111.32 | 112.80 | 97.85 | 116.24 |

Counter summary:

| Mode | Observed DMA | HLE verifier hits | HLE bytes | Shadow hits | Shadow bytes | Skip hits | Skip bytes | Skip misses | RSX-local/overlap |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Verify | 1,520.90 MB | 4,668 | 72.94 MB | 311 | 4.86 MB | 0 | 0 B | 0 | 0 / 0 |
| Skip | 1,782.72 MB | 5,328 | 83.25 MB | 355 | 5.55 MB | 355 | 5.55 MB | 0 | 0 / 0 |

Reading:

- The guarded skip remains correctness-clean for the exact `0x25cc`,
  `cmd=0x40`, tag `31`, size `0x4000`, `lsa=0x3b000`,
  `eal=0xa1c000` runtime shape. It removes redundant CPU/SPU copy work only
  after proving `dst_pre == src`, and this run had `0` skip misses,
  `0` mismatches, and `0` destination changes.
- The new title-FPS CSV evidence does not support banking this as a speed win.
  In this matched pair, `Verify` beat `Skip` on average, median, screenshot
  `0150s`, and max title FPS.
- This also remains `0` promoted CPU/SPU-to-GPU work and `0` RSX-local
  traffic. It is CPU/SPU HLE correctness work, not GPU migration credit.
- Do not keep rerunning this exact skip expecting the 200% gate. The next
  useful step is either lower-overhead same-process frame-time extraction if
  we still want to understand the noise, or a bigger HLE/codegen target around
  `0x451c` / broader `0x25cc` bodies.

Classification:

- `spu-hle-guarded-skip-titlecsv-ab-demoted`,
  `correctness-clean-hle-experiment`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 SPU HLE Candidate Atlas Refresh After Skip Demotion

Question:

- After the exact `0x25cc` guarded skip lost the title-FPS A/B, which SPU HLE
  or codegen target should the Windows-only loop pursue next?

Command:

```powershell
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 12 -Top 12
```

Output:

- Markdown:
  `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.md`.
- CSV:
  `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.csv`.
- Recent run dirs scanned: `12`.
- Valid field runs used: `9`.
- Field-like runs excluded by fatal logs: `0`.
- Included the new title-CSV `Verify` and `Skip` runs:
  - `20260524-125346-hle-shadow-verify-titlecsv-uncap240-field-windows-windows`;
  - `20260524-125942-hle-shadow-skip-titlecsv-uncap240-field-windows-windows`.

Top candidate buckets:

| Rank | PC | Group / SPU | Runs | Records | Total | GET | PUT | List GET | RSX | Max Job | Recommendation |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | `0x451c` | `TCX_CellSpursKernelGroup` / `TCX_CellSpursKernel0` | 9 | 3741 | 8.25 GB | 1.86 GB | 2.89 GB | 3.49 GB | 0 B | 4.66 MB | `spu-hle-codegen-priority` |
| 2 | `0x25cc` | `CellSpursKernelGroup` / `CellSpursKernel0` | 9 | 3823 | 6.01 GB | 910.95 MB | 5.12 GB | 0 B | 0 B | 1.72 MB | `spu-hle-codegen-priority` |

Reading:

- `0x451c` is now the largest stable Windows field HLE/codegen target after the
  exact `0x25cc` redundant-copy skip was demoted. Its aggregate is bigger and
  includes list GET traffic that the tiny skip did not address.
- No valid atlas bucket has RSX-local bytes. Broad SPU-to-Vulkan compute stays
  parked; the next Windows-only step should be SPU HLE/codegen/verifier work,
  not GPU compute dispatches.
- The next verifier should gate on title `BLUS30161`, image
  `0x958dfe208b686622`, group `TCX_CellSpursKernelGroup`, SPU
  `TCX_CellSpursKernel0`, and PC `0x451c`. Start in verify mode by recording
  the MFC descriptor plus touched GET/PUT/list ranges and comparing the stock
  result before any fast return.
- `0x25cc` remains useful as a broader body/codegen target, but do not rerun
  the exact guarded redundant-copy skip expecting a speed win.

Classification:

- `analysis`, `spu-hle-codegen-target-refresh`,
  not `gpu-migration-credit`, not `windows-micro-win`,
  not a 200% gate candidate.

## 2026-05-24 SPU HLE Guarded Skip Uncapped Verify External Gate Baseline

Question:

- Does the new `ExternalFail` gate allow a valid uncapped `Verify` baseline for
  the guarded-skip field A/B while still recording RPCS3 self-load separately?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-verify-ab-uncap240-externalgate-field-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate ExternalFail
```

Run:

- `debug-captures/windows-lab/20260524-010351-hle-shadow-verify-ab-uncap240-externalgate-field-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host gate passed: worst total host grade `moderate`, worst external host
  grade `clean` across `5` snapshots.
- Visual gate passed: first field-like screenshot `screenshot-0117s.png` at
  `117s`, `0` invalid screenshots after first field-like output.
- Manual screenshot check: `screenshots/screenshot-0150s.png` shows clean Path
  to Tenuto field gameplay. Overlay reads about `113.40` to `114.29 FPS`, with
  displayed field 1% low around `109.3`.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.

Summary counters:

- Total observed DMA bytes: `1,741.67 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `331`.
- SPU HLE verifier hits/runtime/LLVM: `4953 / 4953 / 0`.
- SPU HLE verifier candidate bytes: `77.39 MB`.
- Shadow rows/hits/bytes: `330 / 330 / 5.16 MB`.
- Shadow output match/mismatch: `330 / 0`.
- Shadow destination changed/unchanged: `0 / 330`.
- Guarded skip hits/bytes: `0 / 0 B`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `330`.

Reading:

- This is the first valid uncapped `Verify` baseline half under the new
  external-only host gate.
- It is not a speed result by itself and not GPU migration credit.
- The next matched proof is the same field route with
  `-EternalSonataSpuHleVerify Skip`, frame/vblank `240/240`, and
  `-WindowsHostContentionGate ExternalFail`. Only compare if route, visuals,
  fatal scan, and external host grade match.

Classification:

- `spu-hle-verify-uncap240-externalgate-baseline`,
  `windows-micro-candidate-support`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 SPU HLE Guarded Skip Uncapped Skip External Gate Half

Question:

- Does the matched `Skip` half of the uncapped field A/B show a clean enough
  speed/frame-time delta to bank the guarded 0x25cc redundant-copy skip as a
  `windows-micro-win`?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-skip-ab-uncap240-externalgate-field-windows `
  -EternalSonataSpuHleVerify Skip `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate ExternalFail
```

Run:

- `debug-captures/windows-lab/20260524-121714-hle-shadow-skip-ab-uncap240-externalgate-field-windows-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host gate passed: worst total host grade `moderate`, worst external host
  grade `clean` across `5` snapshots.
- Visual gate passed: first field-like screenshot `screenshot-0118s.png` at
  `118s`, `0` invalid screenshots after first field-like output.
- Manual screenshot check: `screenshots/screenshot-0150s.png` shows clean Path
  to Tenuto field gameplay. Title FPS was about `117.65`; overlay instant FPS
  was about `119.78`; overlay CPU utilization showed PPU/SPU/RSX/total around
  `11.7 / 20.1 / 7.7 / 39.4%`.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.

Matched Verify baseline:

- `debug-captures/windows-lab/20260524-010351-hle-shadow-verify-ab-uncap240-externalgate-field-windows-windows`.
- Same route class, frame/vblank `240/240`, PadApi, `\\.\DISPLAY2`, and
  `ExternalFail` with external host grade `clean`.
- Manual `screenshot-0150s.png` showed title FPS about `114.29`, overlay
  instant FPS about `113.40`, and overlay CPU utilization around
  PPU/SPU/RSX/total `14.1 / 23.2 / 8.5 / 45.8%`.

Summary counters:

- Total observed DMA bytes: `1,784.57 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `388`.
- SPU HLE verifier hits/runtime/LLVM: `5808 / 5808 / 0`.
- SPU HLE verifier candidate bytes: `90.75 MB`.
- Shadow rows/hits/bytes: `387 / 387 / 6.05 MB`.
- Shadow output match/mismatch: `387 / 0`.
- Shadow destination changed/unchanged: `0 / 387`.
- Guarded skip hits/bytes: `387 / 6.05 MB`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `387`.

Reading:

- The guarded skip did real CPU-side work removal for the exact 0x25cc runtime
  shape and stayed correctness-clean in field under the matched external host
  gate.
- It is still not GPU migration credit: it removes redundant CPU/SPU copy work,
  while RSX-local and indirect overlap remain `0`.
- The screenshot point is encouraging: instant/title FPS and displayed CPU load
  improved versus the Verify baseline.
- Do not bank it as `windows-micro-win` yet. The Skip screenshot's rolling
  average and 1% low did not clearly beat Verify (`avg` about `112.0`, 1% about
  `77.6`, versus Verify `avg` about `114.4`, 1% about `109.3`), so this remains
  a noisy single-point A/B. The next speed proof should repeat the matched A/B,
  or add a direct frame-time/overlay extraction so the delta is measured from a
  comparable window instead of one manual screenshot.

Classification:

- `spu-hle-guarded-skip-uncap240-externalgate-skip-half`,
  `windows-micro-candidate-support`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 SPU HLE Guarded Skip Repeat Uncapped A/B

Question:

- If we immediately repeat the same uncapped field A/B in reverse order after
  the first noisy `Verify -> Skip` pair, does the guarded skip keep showing a
  usable FPS/frame-time or CPU-load improvement?

Commands:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-verify-ab2-uncap240-externalgate-field-windows `
  -EternalSonataSpuHleVerify Verify `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate ExternalFail
```

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-shadow-skip-ab2-uncap240-externalgate-field-windows `
  -EternalSonataSpuHleVerify Skip `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 4 `
  -WindowsVisualGate FieldLike `
  -WindowsHostContentionGate ExternalFail
```

Runs:

- Verify:
  `debug-captures/windows-lab/20260524-122732-hle-shadow-verify-ab2-uncap240-externalgate-field-windows-windows`.
- Skip:
  `debug-captures/windows-lab/20260524-123334-hle-shadow-skip-ab2-uncap240-externalgate-field-windows-windows`.
- Both runs stayed on `\\.\DISPLAY2`.
- Both visual gates passed with `0` invalid screenshots after first field-like
  output.
- Both stayed external-host-clean across all `5` host snapshots.
- Fatal scans found no real crash/access/likely-crashed/assertion/Vulkan hit.

Manual late screenshot comparison:

| Pair | Mode | Screenshot | Title FPS | Overlay FPS | Overlay Avg | Overlay 1% | Overlay CPU Total | RPCS3 Host CPU |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | Verify | `20260524-010351.../screenshot-0150s.png` | 114.29 | 113.40 | 114.4 | 109.3 | 45.8% | 46.6% |
| 1 | Skip | `20260524-121714.../screenshot-0150s.png` | 117.65 | 119.78 | 112.0 | 77.6 | 39.4% | 43.7% |
| 2 | Verify | `20260524-122732.../screenshot-0150s.png` | 94.44 | 96.92 | 90.2 | 79.5 | 40.2% | 44.3% |
| 2 | Skip | `20260524-123334.../screenshot-0150s.png` | 109.27 | 106.96 | 110.0 | 101.5 | 39.9% | 82.2% |

Repeat Skip summary counters:

- Total observed DMA bytes: `1,880.04 MB`.
- Direct RSX-local scout traffic: `0`.
- Indirect SPU-DMA/RSX-resource overlap: `0`.
- SPU HLE verifier rows: `404`.
- SPU HLE verifier hits/runtime/LLVM: `6048 / 6048 / 0`.
- SPU HLE verifier candidate bytes: `94.50 MB`.
- Shadow rows/hits/bytes: `403 / 403 / 6.30 MB`.
- Shadow output match/mismatch: `403 / 0`.
- Shadow destination changed/unchanged: `0 / 403`.
- Guarded skip hits/bytes: `403 / 6.30 MB`.
- Guarded skip misses/bytes: `0 / 0 B`.
- Unique source hashes: `403`.

Reading:

- The guarded skip continues to be correctness-clean and it removes a real,
  exactly-gated CPU/SPU redundant-copy path. That part is solid.
- This still is not GPU migration credit: no direct RSX-local scout traffic and
  no indirect RSX-resource overlap appeared in either repeat.
- The speed signal is stronger than the first single pair: title FPS and
  instant overlay FPS favor `Skip` in both pairs, and the second pair also
  favors `Skip` on rolling average and 1% low.
- Do not bank it as `windows-micro-win` yet. The first pair's rolling 1% low
  moved against `Skip`, and the second Skip host snapshot reported high RPCS3
  self CPU (`82.2%`) despite the overlay CPU total being low. This needs direct
  frame-time/overlay extraction or a longer same-process window before it is
  durable enough to stack with other micro-wins.

Classification:

- `spu-hle-guarded-skip-repeat-ab-stronger-candidate`,
  `windows-micro-candidate-support`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 Windows Title-FPS Sampling Harness

Question:

- Can the Windows lab record machine-readable RPCS3 title-bar FPS samples so
  the next guarded-skip A/B does not depend on manual screenshot title reading?

Change:

- `tools/windows_rpcs3_lab.ps1` now writes `window-title-samples.csv` in each
  run directory.
- The CSV schema is:
  `timestamp,elapsed_seconds,phase,fps,window_title`.
- Samples are captured whenever the lab saves a screenshot and whenever it
  saves a periodic host snapshot.
- The parser reads the existing configured window title format
  `FPS: %F | %R | %V | %T [%t]`.
- The run log also writes `Window title sample [...]` rows for quick scanning.
- `.agents/skills/ps3-speed-proof-gate/SKILL.md` now says to prefer this CSV
  when it exists, especially for uncapped A/B.

Verification:

- PowerShell parser checks passed for:
  - `tools/windows_rpcs3_lab.ps1`
  - `tools/eternal_sonata_speed_sprint.ps1`
- Windows smoke command:

```powershell
.\tools\windows_rpcs3_lab.ps1 `
  -Action Run `
  -Label window-title-sample-smoke `
  -Mode NoGui `
  -MaxSeconds 45 `
  -InputMacro "wait:25000;shot:100" `
  -InputBackend PadApi `
  -ScreenshotEverySeconds 15 `
  -ScreenshotStartSeconds 25 `
  -ScreenshotMaxCount 1 `
  -GameScreen 1 `
  -HostContentionGate ExternalFail `
  -FrameLimit 240 `
  -VblankRate 240 `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-124605-window-title-sample-smoke`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host gate passed: worst total host grade `moderate`, worst external host
  grade `clean`.
- Fatal scan found no real crash/access/likely-crashed/assertion/Vulkan hit.
- `window-title-samples.csv` imported successfully and contained:
  - screenshot `0028s`: `102.14 FPS`;
  - duplicate screenshot `0028s-01`: `83.97 FPS`;
  - host sample `0030s`: `102.62 FPS`.

Reading:

- This is process harness work, not a speed result.
- Future uncapped `Verify`/`Skip` A/B runs can compare multiple title-FPS CSV
  samples instead of one hand-read screenshot.
- This still does not provide 1% low/frame-time by itself; it is enough to make
  title-FPS comparisons reproducible and less squishy.

Classification:

- `process-harness`, `speed-proof-gate`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c List-Family Source Hook Map

Question:

- Given the clean list-family counters and cluster fragmentation, where should
  the next verify-only `0x451c` HLE/codegen hook live in source?

Inputs:

- Refiner says not to repeat `loader-control-left200x2`; switch to route repair
  or SPU kernel HLE/codegen/verifier analysis.
- `ps3-debug-knowledge` search for `0x451c list-family` returned the current
  standing notes: the clean no-movement reproof is valid, the invalid left200
  run is counter-only, exact clusters are fragmented, and broad SPU-to-Vulkan
  remains parked.
- Clean quick-cluster CSV:
  `debug-captures/windows-lab/20260524-195528-hle-451c-listfamily-verify-nomove-reproof-windows/eternal-sonata-451c-list-family-quick-clusters.csv`.
- Source inspected in local Windows `rpcs3-upstream`; no source edits were made
  in this step.

Counter checks:

- Top exact-cluster coverage remains too fragmented for an exact fast path:
  - top `1`: `4,440` hits, `5.28%`;
  - top `5`: `13,736` hits, `16.33%`;
  - top `10`: `19,931` hits, `23.69%`;
  - top `32`: `35,559` hits, `42.27%`;
  - top `64`: `50,006` hits, `59.44%`;
  - top `128`: `67,961` hits, `80.79%`.
- Broad family totals from the same clean run:
  - `tag=1,size=8`: `95` clusters, `38,798` hits, `46.12%`,
    `38.757 ms`;
  - `tag=0,size=8`: `61` clusters, `17,395` hits, `20.68%`,
    `39.021 ms`;
  - `tag=0,size=16`: `58` clusters, `13,782` hits, `16.38%`,
    `8.396 ms`;
  - `tag=1,size=16`: `52` clusters, `10,060` hits, `11.96%`,
    `6.625 ms`;
  - `tag=1,size=24`: `12` clusters, `2,148` hits, `2.55%`,
    `1.563 ms`;
  - `tag=0,size=24`: `8` clusters, `1,941` hits, `2.31%`,
    `3.204 ms`.
- Direct RSX-local bytes remain `0 B`.

Source map:

- `rpcs3/Emu/Cell/SPUThread.cpp`
  - `451-472`: `is_es_mfc_451c_dynamic_list_verify_candidate(...)`
    gates title/image/PC, `MFC_GETLF_CMD`, non-shuffled MFC, and non-accurate
    DMA.
  - `498-535`: `get_es_mfc_451c_dynamic_list_family(...)` maps the six broad
    tag/size families.
  - `538-634`: `record_es_mfc_dynamic_cmd(...)` records dynamic `MFC_Cmd`
    timing and family counters after `process_mfc_cmd()`.
  - `636-686`: `record_es_mfc_list_transfer(...)` records list-transfer timing
    around `do_list_transfer(...)`.
  - `4485-4565`: `do_list_transfer(...)` starts the descriptor walker and
    already fetches six 8-byte descriptors at a time (`fetch_size = 6`) before
    descriptor checks.
  - `6596-6635`: `process_mfc_cmd()` list-command case times candidate
    `do_list_transfer(...)` calls for the probes.
  - `8069-8080`: WRCH `MFC_Cmd` runtime path sets `ch_mfc_cmd.cmd`, calls
    `process_mfc_cmd()`, then records dynamic timing.
- `rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`
  - `5222-5233`: `exec_mfc_cmd<Saveable>()` calls `process_mfc_cmd()`.
  - `5417-5429`: constant list commands, including `MFC_GETLF_CMD`, store the
    command and call `exec_mfc_cmd<true>()`.
  - `5706-5708`: non-constant `MFC_Cmd` falls back to the unoptimized WRCH
    implementation. The clean captures already showed `0x451c` emits this
    warning, so the hot path is still runtime C++ `process_mfc_cmd()` today.

Reading:

- The next code hook should not be another exact seed verifier. Exact clusters
  are too fragmented and would miss most work.
- The useful verify-only target is a broad-family descriptor-batch counter in
  or immediately around `do_list_transfer(...)`, keyed by the existing
  title/image/PC/list-command gate and the six tag/size families.
- A future fast mode, if the verifier proves repeated descriptor shapes and
  clean outputs, should be a C++ list-family/list-descriptor batch path first.
  LLVM dynamic-command recognition can follow, but the current hot `0x451c`
  route is not in the constant-command LLVM direct path.
- This is CPU/SPU HLE/codegen preparation, not GPU migration: the capture still
  has `0 B` RSX-local traffic and no evidence of GPU-consumed SPU data.

Classification:

- `source-analysis`, `spu-hle-451c-list-family-hook-map`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## 2026-05-24 0x451c Descriptor-Batch Accounting Hook

Question:

- Can we observe the actual descriptor walker shape behind the hot `0x451c`
  list-family rows before designing an HLE/codegen batch path?

Change:

- In local Windows `rpcs3-upstream`, added verify-only descriptor-batch
  accounting to `spu_thread::do_list_transfer(...)`, gated by the existing
  `get_es_mfc_451c_dynamic_list_family(...)`,
  `RPCS3_ES_SPU_HLE_VERIFY=verify`, BLUS30161 image
  `0x958dfe208b686622`, and PC `0x451c`.
- New log row: `Eternal Sonata SPU HLE 451c descriptor batch verifier:`.
- Counters cover calls, descriptor bytes, fetch groups, existing stock
  six-descriptor fast groups/descriptors, generic slow descriptors,
  nonzero/zero/stall descriptors, inline GET/PUT descriptors, slow DMA
  fallback descriptors, and six broad family call buckets.
- Updated the quick list-family parser and full GPU probe summarizer to read
  and export descriptor-batch rows.

Verification:

- PowerShell AST parser checks passed for both updated tools.
- `git diff --check` passed for the touched parser and source files, with only
  LF/CRLF warnings.
- Synthetic quick parser row produced rows/calls `1 / 7`, fast/slow
  descriptors `12 / 5`, and inline_get/dma descriptors `4 / 1`.
- Synthetic full summarizer row exported
  `eternal-sonata-spu-hle-451c-desc-batch-profile.csv`.
- MSVC Release build passed:
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\rpcs3.exe`.

Reading:

- This does not move work to GPU and does not claim speed.
- It narrows the next CPU/SPU HLE/codegen step by measuring whether the
  existing `do_list_transfer(...)` descriptor body has batchable shape beyond
  fragmented exact seeds.
- Keep broad SPU-to-Vulkan compute parked until RSX-local or RSX-consumed data
  appears.

Classification:

- `analysis`, `verify-only-instrumentation`,
  `spu-hle-451c-descriptor-batch-accounting`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Run a Windows-only no-movement field proof with
  `-EternalSonataSpuHleVerify Verify`, parse descriptor-batch counters, then
  decide whether a C++ list-family batch fast path is worth a verify shadow.

## 2026-05-24 0x451c Descriptor-Batch Field Proof

Question:

- Does the new `do_list_transfer(...)` descriptor-batch accounting produce
  useful counters on a clean Eternal Sonata field route?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-descbatch-verify-nomove `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 8 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-205813-hle-451c-descbatch-verify-nomove-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host contention was clean: `5` snapshots, worst external `clean`, worst
  total `clean`.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `0` invalid screenshots after first
  field-like, and field-like-by-`160s` passed.
- Manual visual check: `screenshot-0150s.png` shows clean Path to Tenuto field
  gameplay with the character visible, no black overlay, and no
  starry/cutscene route drift.
- Fatal scan was clean; the only `fatal` pattern was the config line
  `Show fatal error hints: false`.
- Title samples existed (`12` samples, average `33.31 FPS`, min `29.77`, max
  `36.18`), but this is not a matched speed comparison.

Counters:

- Quick parser and full GPU probe summary both completed.
- SPU HLE `0x451c` list-family records: `766`.
- SPU HLE `0x451c` descriptor-batch records: `766`.
- List-family hits/calls: `91,049`; success/fail `91,049 / 0`.
- List-family descriptor bytes: `1.42 MB`.
- List-family timing: `93.097 ms` total, `1.022 us/hit` average.
- Dynamic MFC: `240,621` hits, `447.25 MB`, `212.403 ms`.
- Dynamic PC split: `0x25cc=16,453 / 39.951 ms`,
  `0x451c=224,168 / 172.452 ms`.
- MFC list-transfer calls/timing: `91,049 / 72.051 ms`.
- Descriptor-batch calls: `91,049`.
- Descriptor bytes: `1,487,232`.
- Fetch groups: `91,049`.
- Stock fast groups/descriptors: `0 / 0`.
- Generic slow descriptors: `185,904`.
- Descriptor item split:
  - nonzero descriptors: `183,743`;
  - zero descriptors: `2,161`;
  - stall descriptors: `0`;
  - inline GET descriptors: `183,743`;
  - inline PUT descriptors: `0`;
  - slow DMA fallback descriptors: `0`.
- Broad-family call buckets:
  - family 1: `7,852`;
  - family 2: `7,771`;
  - family 3: `28,236`;
  - family 4: `27,761`;
  - family 5: `9,577`;
  - family 6: `9,852`.
- GPU candidate rows: `1,303`; total observed DMA `1.88 GB`.
- Direct RSX-local bytes: `0 B`.
- Full summary offload fit mix remained CPU/SPU-shaped:
  `spu-kernel-hle=908`, `too-small=395`.

Reading:

- The new hook proves the hot `0x451c` list path is currently generic
  descriptor/control work: every measured descriptor stayed on the slow
  generic path, and all nonzero descriptors were inline GET list entries.
- The existing six-descriptor stock fast counter stayed at `0`, so the useful
  next experiment is not another exact seed. It is a verify-shadow C++
  preserve-order batch path for inline GET descriptors in `do_list_transfer()`.
- There is still no RSX-local or GPU-consumed evidence here, so this is not a
  SPU-to-Vulkan dispatch candidate yet. Broad SPU-to-Vulkan remains parked.
- This run is valid target sizing and visual/fatal proof for descriptor-batch
  accounting, but it is not a speed comparison and not a 200% gate candidate.

Classification:

- `valid-field-triage`, `spu-hle-451c-descriptor-batch-target-sizing`,
  `analysis`, not `windows-micro-win`, not `gpu-migration-credit`, not a 200%
  gate candidate.

Next:

- Add a verify-only C++ shadow path inside `do_list_transfer()` that batches the
  observed inline GET descriptors and compares against the stock per-descriptor
  behavior. Only after clean field/menu/battle proof should a fast mode be
  considered.

## 2026-05-24 0x451c Shadow-Batch Scout Hook

Question:

- Before writing a real fast path, how much of the observed inline-GET
  descriptor body is batchable as groups rather than one descriptor at a time?

Change:

- In local Windows `rpcs3-upstream`, extended the existing verify-only
  `do_list_transfer(...)` descriptor-batch accounting with shadow eligibility
  counters.
- The hook inspects each fetched list-descriptor block under the same
  BLUS30161/image/PC/family gate and only when the command is GET-list
  inline-compatible. It does not change stock MFC/list behavior.
- New logged fields include:
  - `shadow_groups`, `shadow_single_groups`, `shadow_multi_groups`;
  - `shadow_full_groups`, `shadow_partial_groups`;
  - `shadow_desc`, `shadow_bytes`;
  - `shadow_uniform_size_groups`, `shadow_mixed_size_groups`;
  - `shadow_zero_rejects`, `shadow_stall_rejects`,
    `shadow_raw_rejects`;
  - `shadow_max_desc`, `shadow_max_bytes`, `shadow_last_desc`,
    `shadow_last_bytes`, `shadow_last_first_ea`,
    `shadow_last_last_ea`.
- Updated `tools/summarize_eternal_sonata_451c_list_family_run.ps1` to
  summarize the shadow counters.
- Updated `tools/summarize_eternal_sonata_gpu_probe.ps1` to parse and export
  the same fields in
  `eternal-sonata-spu-hle-451c-desc-batch-profile.csv`.

Verification:

- PowerShell AST parser checks passed for both updated tools.
- Synthetic quick parser smoke read the new shadow fields and reported:
  `shadow groups total=3`, `shadow desc=8`, `shadow bytes=256 B`.
- Synthetic full summarizer smoke exported shadow CSV fields including
  `shadow_groups=3`, `shadow_desc=8`, and
  `shadow_last_first_ea=0x3f430`.
- `git diff --check` passed for the touched parser and C++ files, with only
  LF/CRLF warnings.
- MSVC Release build passed:
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\rpcs3.exe`.

Reading:

- This is still verifier/scout code only. It does not move work to GPU, skip
  stock DMA, or claim speed.
- The previous clean field proof showed `183,743` inline GET descriptors and
  `0` stock six-descriptor fast groups. The new shadow fields are meant to
  split that body into single-descriptor versus multi-descriptor groups so a
  preserve-order C++ batch path can be designed with less guesswork.
- Broad SPU-to-Vulkan compute remains parked because the latest field proof
  still had `0 B` direct RSX-local traffic.

Classification:

- `analysis`, `verify-only-instrumentation`, `spu-hle-451c-shadow-batch-scout`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

Next:

- Run the same Windows-only no-movement `-EternalSonataSpuHleVerify Verify`
  field route and parse the new `shadow_*` counters. If multi-descriptor
  shadow groups cover enough of the inline-GET body, the next implementation
  can be a verify-shadow preserve-order batch copier before any fast mode.

## 2026-05-24 0x451c Shadow-Batch Field Attempt Rejected

Question:

- Can the new `shadow_*` descriptor-batch counters be measured on the same
  no-movement field route that previously proved descriptor-batch accounting?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-shadowbatch-verify-nomove `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 8 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-211842-hle-451c-shadowbatch-verify-nomove-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host contention was clean: `5` snapshots, worst external `clean`, worst
  total `clean`.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; all `10` screenshots were
  `black-overlay-small-png`.
- Manual visual check: `screenshot-0150s.png` shows a blue/black crash-like
  frame with RPCS3's "application has likely crashed" overlay, not Path to
  Tenuto gameplay.
- Fatal scan was not clean:
  `PPU[0x1000000] Thread (main_thread) [0x002c067c]: VM: Access violation reading location 0x14`.
- Title samples existed, but the run is not comparable because the game was in
  a crash/black-overlay state.

Counter Smoke:

- Quick parser completed after the visual failure.
- List-family rows/hits: `501 / 63,204`.
- Dynamic MFC hits/timing: `167,879 / 160.607 ms`.
- Dynamic PC split: `0x25cc=12,933 / 31.127 ms`,
  `0x451c=154,946 / 129.480 ms`.
- MFC list-transfer calls/timing: `63,204 / 64.478 ms`.
- Descriptor-batch rows/calls: `501 / 63,204`.
- Slow descriptors: `129,472`.
- Inline GET descriptors: `128,664`.
- Zero descriptors/rejects: `808`.
- Shadow groups:
  - total: `63,204`;
  - single: `9,752`;
  - multi: `53,452`;
  - full: `62,396`;
  - partial: `808`.
- Shadow descriptors/bytes: `128,664 / 309.99 MB`.
- Shadow uniform/mixed groups: `9,793 / 53,411`.
- Shadow rejects: zero `808`, stall `0`, raw `0`.
- Shadow max block after parser fix: `3` descriptors / `23.59 KB`.
- Direct RSX-local bytes: `0 B`.

Parser Fix:

- The quick parser initially summed `shadow_max_desc` and `shadow_max_bytes`
  across log rows, which made the max block fields look impossible.
- Fixed `tools/summarize_eternal_sonata_451c_list_family_run.ps1` so those
  fields are tracked with `Update-Max`, then re-ran the parser on this capture.
- Parser AST check passed after the fix.

Reading:

- This run proves the new logging/parsing path emits data, but it is not valid
  gameplay evidence. The crash/black-overlay visual state and access violation
  reject it for speed, correctness, and fast-path design.
- The counter smoke is interesting because most shadow groups are multi
  descriptor groups and all nonzero work still fits inline GET, but a clean
  route is required before using that as implementation evidence.
- The crash happened after adding a read-only verifier. It may be route
  nondeterminism, logging overhead, or a bug in the instrumentation; do not
  assume either way from one invalid run.

Classification:

- `failed-black-overlay-visual`, `failed-fatal-log`,
  `spu-hle-451c-shadow-batch-counter-smoke-only`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Re-prove the shadow counters on a clean field route, or first trim/guard the
  instrumentation if the same access violation repeats. Do not design or enable
  a fast mode from this invalid capture.

## 2026-05-24 0x451c Shadow-Batch Reproof Rejected

Question:

- Was the prior shadow-batch failure just a one-off access violation, or does
  this verifier currently destabilize or stall the no-movement field route?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-shadowbatch-verify-nomove-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 8 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-213048-hle-451c-shadowbatch-verify-nomove-reproof-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host contention stayed clean: `5` snapshots, worst external `clean`, worst
  total `clean`.
- Fatal scan was clean.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; all `10` screenshots were
  `loading-like-small-png`.
- Manual visual check: `screenshot-0150s.png` is the `Now Loading...` screen at
  about `120 FPS`, not Path to Tenuto field gameplay.
- Window title samples averaged about `120.01 FPS`, min `119.8`, max `120.15`,
  but this is loading-screen speed and not comparable gameplay evidence.

Counter Smoke:

- Quick parser completed after the visual failure.
- List-family rows/hits: `479 / 28,941`.
- Dynamic MFC hits/timing: `97,363 / 126.185 ms`.
- Dynamic PC split: `0x25cc=27,173 / 66.359 ms`,
  `0x451c=70,190 / 59.826 ms`.
- MFC list-transfer calls/timing: `28,941 / 18.461 ms`.
- Descriptor-batch rows/calls: `479 / 28,941`.
- Slow descriptors: `57,061`.
- Inline GET descriptors: `57,061`.
- Shadow groups:
  - total: `28,941`;
  - single: `5,210`;
  - multi: `23,731`;
  - full: `28,941`;
  - partial: `0`.
- Shadow descriptors/bytes: `57,061 / 168.59 MB`.
- Shadow uniform/mixed groups: `5,210 / 23,731`.
- Shadow rejects: zero `0`, stall `0`, raw `0`.
- Shadow max block: `3` descriptors / `19.92 KB`.
- Direct RSX-local bytes: `0 B`.

Reading:

- This second attempt did not reproduce the access violation, but it still did
  not reach valid field visuals. The route sat on loading-like frames, so the
  counters remain smoke only.
- The shadow classifier keeps showing many multi-descriptor inline-GET groups,
  but two failed visual proofs in a row block using those counters as fast-path
  design evidence.
- Broad SPU-to-Vulkan compute remains parked because direct RSX-local traffic
  stayed `0 B`.

Classification:

- `failed-loading-visual`,
  `spu-hle-451c-shadow-batch-counter-smoke-only`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Do not rerun the exact shadow-batch no-movement route again as the next loop.
  Trim or guard the shadow instrumentation, or fall back to the last clean
  descriptor-batch verifier route, then require a clean field proof before any
  preserve-order batch copier or fast mode.

## 2026-05-24 0x451c Shadow-Batch Guard And Clean Descriptor Reproof

Question:

- Can we keep the useful `0x451c` descriptor-batch verifier clean while moving
  the risky `shadow_*` classifier behind an explicit opt-in?

Change:

- In local Windows `rpcs3-upstream`, normal
  `RPCS3_ES_SPU_HLE_VERIFY=verify` still records the descriptor-batch verifier
  but no longer runs the extra `shadow_*` descriptor classifier.
- The shadow classifier is now gated behind
  `RPCS3_ES_SPU_HLE_VERIFY=verify-shadow`.
- `tools/windows_rpcs3_lab.ps1` and
  `tools/eternal_sonata_speed_sprint.ps1` accept
  `-EternalSonataSpuHleVerify VerifyShadow` for that explicit risky scout.

Verification:

- PowerShell AST checks passed for:
  - `tools/windows_rpcs3_lab.ps1`;
  - `tools/eternal_sonata_speed_sprint.ps1`.
- `git diff --check` passed for touched Windows scripts and C++ files, with
  only LF/CRLF warnings.
- MSVC Release build passed:
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\rpcs3.exe`.

Field Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-descbatch-verify-shadowgated-nomove `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 8 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-214435-hle-451c-descbatch-verify-shadowgated-nomove-windows`.
- RPCS3 stayed on `\\.\DISPLAY2`.
- Host contention stayed clean: `5` snapshots, worst external `clean`, worst
  total `clean`.
- Fatal scan was clean.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like
  `screenshot-0117s.png`, and `0` invalid screenshots after first field-like.
- Manual visual check: `screenshot-0150s.png` is clean Path to Tenuto field
  gameplay with the character visible near the save point.

Counters:

- Window title samples averaged `31.86 FPS`, min `27.98`, max `37.13`.
  This is route sanity only, not a speed comparison.
- List-family rows/hits: `732 / 85,769`.
- Dynamic MFC hits/timing: `228,128 / 257.383 ms`.
- Dynamic PC split: `0x25cc=17,573 / 43.502 ms`,
  `0x451c=210,555 / 213.881 ms`.
- MFC list-transfer calls/timing: `85,769 / 103.864 ms`.
- Descriptor-batch rows/calls: `732 / 85,769`.
- Slow descriptors: `173,988`.
- Inline GET descriptors: `171,828`.
- Zero descriptors: `2,160`; stall descriptors: `0`.
- Shadow groups/descriptors/bytes: `0 / 0 / 0 B`, as intended for normal
  `Verify`.
- Direct RSX-local bytes: `0 B`.

Reading:

- The clean descriptor-batch lane is restored. The two failed shadow-batch
  attempts should be treated as a separate risky scout, not as the default
  verifier.
- This is useful HLE/codegen target-sizing and route stabilization. It is not a
  speed win, not GPU migration credit, and not 200% evidence.
- Broad SPU-to-Vulkan compute remains parked because direct RSX-local traffic is
  still `0 B`.

Classification:

- `valid-field-triage`, `spu-hle-451c-descriptor-batch-target-sizing`,
  `harness-guard`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  200% gate candidate.

Next:

- Keep normal `Verify` for clean descriptor-batch work. Use `VerifyShadow` only
  after adding route-control repair or narrowing the shadow classifier further.
  The next speed-relevant code path should be a preserve-order CPU-side batch
  copier/verifier for the inline GET descriptor body, still behind a correctness
  gate, while broad GPU compute remains parked until RSX-consumed data appears.

## 2026-05-24 0x451c Harness Refiner HLE-Baseline Override

Question:

- Can the continual harness stop steering back to generic loader-control
  movement after the clean descriptor-batch `Verify` route restored the current
  HLE baseline?

Change:

- Updated `tools/ps3_harness_refiner.ps1` to recognize a latest clean
  `0x451c` descriptor-batch / `descbatch` run as an HLE descriptor baseline.
- The refiner now emits a resolved-control anti-pattern
  `hle-descriptor-baseline-clean` when the newest run is a valid field
  descriptor-batch proof.
- In that state, the suggested command is intentionally a comment, not another
  movement or `VerifyShadow` rerun.

Verification:

- PowerShell AST parse of `tools/ps3_harness_refiner.ps1` passed.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` now chooses:
  `Latest clean descriptor-batch Verify route restored the HLE baseline; do not
  rerun VerifyShadow or movement now. Next step is a bounded preserve-order
  inline-GET batch copier/verifier design while broad SPU-to-Vulkan remains
  parked.`
- The report still keeps the older black/loading/fatal shadow attempts visible
  as blockers, but they no longer override the newest clean HLE baseline.

Reading:

- This is process/tooling only. It prevents the loop from wasting another
  Windows capture on loader-control movement when the current technical next
  step is source-level HLE/codegen design around `do_list_transfer()`.
- The current HLE baseline remains the clean run
  `debug-captures/windows-lab/20260524-214435-hle-451c-descbatch-verify-shadowgated-nomove-windows`.
- Broad SPU-to-Vulkan remains parked because repeated captures still show
  `0 B` direct RSX-local traffic.

Classification:

- `harness-guard`, `analysis`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Inspect the `do_list_transfer()` inline GET descriptor body and implement a
  verify-gated preserve-order inline-GET batch copier/verifier as the next
  Windows-only HLE/codegen step. Keep `VerifyShadow` opt-in only.

## 2026-05-24 0x451c Preserve-Order Inline-GET Batch Copier Design

Question:

- What exact C++ path should be specialized next, now that the clean
  descriptor-batch baseline is restored and broad SPU-to-Vulkan still has
  `0 B` RSX-local traffic?

Source Inspection:

- Inspected local Windows `rpcs3-upstream` only; no Android/ADB/Thor work.
- `rpcs3/Emu/Cell/SPUThread.cpp::do_list_transfer()` starts at line `4603`.
- The existing list walker fetches six descriptors at a time at lines
  `4666-4678`.
- The current upstream vector fast path starts around `4735`. It only helps
  when the six descriptors have matching size, no stall bits, same compatible
  region, and a listed size case. The latest clean run reported `0` stock fast
  groups, so the hot Eternal Sonata `0x451c` shape is missing this path.
- The real hot body is the generic inline GET branch at lines `5039-5112`.
  It records the DMA/payload, copies the payload into LS, then advances
  `arg_lsa` by `align(size, 16)` for one descriptor at a time.

Required Semantics For The Next Helper:

- Gate by the existing `0x451c` family predicate:
  title `BLUS30161`, image `0x958dfe208b686622`, SPU PC `0x451c`,
  `MFC_GETLF_CMD`, no shuffled MFC, and no accurate DMA.
- Consider only the current fetched descriptor group (`fetch_size == 6`) and
  preserve descriptor order.
- Reject or stop before any descriptor with:
  - stall-and-notify bit set;
  - zero transfer size;
  - `addr >= RAW_SPU_BASE_ADDR`;
  - non-GET optimized command.
- For every accepted descriptor, preserve the current stock destination
  address formula:
  `this->ls + arg_lsa + (addr & 0xf)`, then advance `arg_lsa` by
  `align(size, 16)`.
- Keep the existing `record_es_gpu_probe_dma()` and
  `record_es_dma_superpath_payload()` calls per descriptor so the counters stay
  comparable.
- Do not touch PUT descriptors, range locks, RSX-local paths, or the existing
  six-uniform fast path in the first implementation.

Implementation Shape:

- Add a verify-gated helper beside the descriptor-batch accounting, likely a
  small `try_es_mfc_451c_inline_get_batch(...)` local helper or static helper
  that consumes `items[index..valid_desc)`.
- First mode should be a correctness/counter mode, not a fast default. It can
  report accepted batch groups/descriptors/bytes and why the batch stopped.
- The later fast mode can replace several passes through the generic
  one-descriptor branch with one tight preserve-order loop over the same fetched
  descriptor group. That is CPU-side HLE/codegen work, not GPU migration.

Reading:

- This is the right next CPU/SPU speed lane because the clean capture measured
  `171,828` inline GET descriptors, `0` stock fast descriptors, and `0 B`
  RSX-local bytes.
- The proposed helper targets loop/control overhead and copy specialization in
  the C++ MFC path. It does not claim a speed win yet and should not be ported
  to Thor before the Windows 200% gate.

Classification:

- `source-analysis`, `spu-hle-451c-preserve-order-batch-design`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Implement the verify-gated batch-counter/helper fields, rebuild Windows
  `rpcs3`, then run the clean no-movement field route with
  `-EternalSonataSpuHleVerify Verify` and parse the new batch coverage before
  any fast mode exists.

## 2026-05-24 0x451c Preserve-Order Batch Coverage Hook

Question:

- Can normal `Verify` measure the `0x451c` preserve-order inline-GET batch
  opportunity without enabling the heavier/riskier `VerifyShadow` classifier?

Change:

- Added descriptor-batch `preserve_*` counters in local Windows
  `rpcs3-upstream`.
- The new counter path runs only under the existing Eternal Sonata
  descriptor-family predicate and normal list-transfer flow. It scans the
  fetched descriptor group in order, stops before stall, zero-size, or RAW-SPU
  descriptors, and records accepted groups/descriptors/bytes plus stop reasons.
- No payload copy, skip, DMA replacement, Vulkan work, or fast path is enabled.
  Stock behavior remains unchanged.
- Updated the narrow `451c` list-family summarizer and the full GPU probe CSV
  export to parse/report the new preserve-order fields.

Verification:

- Windows MSVC Release build passed:
  `cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6 -- /nodeReuse:false`.
- PowerShell AST checks passed for:
  `tools/summarize_eternal_sonata_451c_list_family_run.ps1` and
  `tools/summarize_eternal_sonata_gpu_probe.ps1`.
- `git diff --check` passed for the touched Windows RPCS3 files and parser
  files, with only expected LF-to-CRLF warnings.
- Backward-compat parser check on the old clean run
  `debug-captures/windows-lab/20260524-214435-hle-451c-descbatch-verify-shadowgated-nomove-windows`
  still reports preserve-order counters as `0` because that log predates the
  new fields.
- A tiny synthetic GPU-probe parser test parsed the new preserve fields and
  exported `preserve_groups=7`, `preserve_desc=31`,
  `preserve_bytes=496`, `preserve_max_desc=6`, and
  `preserve_last_first_ea=0x3f430`.

Reading:

- This is a measurement hook only. It is not a speed win, not GPU migration
  credit, and not 200% evidence.
- The hook prepares the next clean no-movement field run to answer whether most
  of the `171,828` prior inline GET descriptors are batchable in descriptor
  order under normal `Verify`.
- Broad SPU-to-Vulkan compute remains parked because the clean baseline still
  had `0 B` direct RSX-local traffic.

Classification:

- `verify-only-instrumentation`,
  `spu-hle-451c-preserve-order-batch-coverage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Run the clean no-movement field route with
  `-EternalSonataSpuHleVerify Verify`, parse preserve-order coverage, and only
  then decide whether to implement a verify-gated preserve-order batch copier.

## 2026-05-24 0x451c Preserve-Order Coverage Field Reproof Failed

Question:

- Does the new normal-`Verify` preserve-order coverage hook survive the clean
  no-movement field route and produce usable batchability counters?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-preserve-verify-nomove `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -MaxSeconds 170 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 8 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:10000;shot:100" `
  -EternalSonataSpuHleVerify Verify
```

Run:

- `debug-captures/windows-lab/20260524-222145-hle-451c-preserve-verify-nomove-windows`

Verification:

- RPCS3 launched through the Windows lab on `\\.\DISPLAY2`.
- Host contention was clean/external-clean for all snapshots.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; all `10` screenshots were
  classified as `black-overlay-small-png` around `35-36 KB`.
- Fatal scan hit:
  `PPU[0x1000000] Thread (main_thread) [0x0007dccc]: VM: Access violation reading location 0x4 (unmapped memory)`.
- Window title samples averaged about `30.12 FPS` (`29.28` min,
  `30.45` max), but this is invalid because the run was black/fatal.

Counters:

- List-family rows/hits: `234 / 15,041`.
- Dynamic MFC rows/hits: `319 / 38,794`.
- Dynamic PC split: `0x25cc=2,661 / 6.339 ms`,
  `0x451c=36,133 / 14.712 ms`.
- Descriptor-batch rows/calls: `234 / 15,041`.
- Inline GET descriptors: `29,660`.
- Preserve-order groups/descriptors/bytes before the fatal:
  `15,041 / 29,660 / 87.92 MB`.
- Preserve coverage matched all logged inline GET descriptors in this invalid
  prefix: `29,660 / 29,660`; max accepted descriptor count was `3`.
- Preserve stops: `zero=0`, `stall=0`, `raw=0`.
- Direct RSX-local bytes: `0 B`.

Reading:

- The new counter path did emit useful-looking coverage data, but the run is
  invalid for promotion, speed, and correctness because the visuals were black
  and the log had a fatal access violation.
- Treat the `100%` pre-fatal preserve coverage only as a weak implementation
  smoke signal. It is not clean HLE evidence and must be re-proven in a valid
  field route before any copier/fast mode.
- Broad SPU-to-Vulkan remains parked because direct RSX-local traffic is still
  `0 B`.
- The refiner now correctly backs off to loader/control reproof after this
  fatal-black run.

Classification:

- `failed-fatal-log`, `failed-black-overlay-visual`, `not-comparable`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

Next:

- Do not add movement, `VerifyShadow`, or a preserve-order copier yet.
- Re-prove a no-movement loader/control field route with `CleanAfterField`
  before trusting the new coverage hook.

## 2026-05-24 Loader-Control Reproof After Preserve Fatal

Question:

- Was the prior black/fatal preserve-coverage reproof a general
  route/host/display failure, or is the base Windows loader-control path still
  healthy?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-visualgate-after-preserve-fatal `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260524-222901-cpu4-loader-control-visualgate-after-preserve-fatal-windows`

Verification:

- RPCS3 launched through the Windows lab on `\\.\DISPLAY2`; host checks were
  clean/external-clean.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `10` field-like screenshots, and `0`
  invalid screenshots after first field.
- Clean fatal scan found no fatal log marker, access violation,
  likely-crashed, `Unknown STOP`, assertion, unhandled exception, segfault,
  `VK_ERROR`, or device-lost hits.
- Window-title samples averaged `32.45 FPS` (`27.22` min, `39.24` max), but
  this is route/control context only, not a speed comparison.

Counters:

- HLE descriptor preserve counters were absent because
  `-EternalSonataSpuHleVerify` was off for this loader-control reproof.
- GPU probe observed `2,300.40 MB` total DMA, with `0 B` direct RSX-local
  traffic and `0 B` indirect SPU-DMA/RSX-resource overlap.
- GPU Port Scoreboard stayed at promoted CPU/SPU -> GPU replacement
  `0 records / 0 B / 0.000%`.
- Offload fit remained CPU/SPU HLE-shaped:
  `spu-kernel-hle=1093`, `too-small=412`.
- Reservation-loop verify was active:
  `5,664` verify records, attempts/completed `109,830 / 30,752`,
  success/failure/unexpected `17,124 / 13,628 / 5,182`.

Reading:

- The route/host/display control path is healthy after the preserve fatal.
  The prior preserve-coverage run remains invalid and isolated as a
  black/fatal HLE-Verify run, not as proof of a general loader failure.
- Broad SPU-to-Vulkan remains parked because this clean reproof again shows
  `0 B` direct RSX-local and `0 B` overlap.
- The harness refiner now suggests using this newest valid loader-control as
  the route base for one small state-aware movement step with
  `CleanAfterField`, while keeping lane-2 HLE/GPU fast modes blocked.

Classification:

- `valid-field-triage`, `route-control-reproof`, `analysis`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Use the newest valid loader-control route as the base for the next small
  Windows-only movement proof.
- Do not enable `VerifyShadow`, a preserve-order copier, Android/ADB/Thor work,
  or a GPU-offload claim until field/menu/battle correctness and the Windows
  200% gate are proven.

## 2026-05-24 Left200 After Preserve-Reproof Rejection

Question:

- Can the newest clean loader-control route tolerate one small state-aware
  `ls_left:200` movement pulse before returning to HLE/codegen or GPU lane work?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-left200-after-preserve-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 10
```

Run:

- `debug-captures/windows-lab/20260524-224306-cpu4-loader-control-left200-after-preserve-reproof-windows`

Verification:

- RPCS3 launched through the Windows lab on `\\.\DISPLAY2`; CPU affinity
  `0x0F` was applied.
- Host contention was clean/external-clean across all `6` snapshots.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`, no field-like screenshot by
  `160s`, and all `14` screenshots were `black-overlay-small-png`
  (`32.71-33.43 KB`).
- Clean fatal scan found no fatal log marker, access violation,
  likely-crashed, `Unknown STOP`, assertion, unhandled exception, segfault,
  `VK_ERROR`, or device-lost hits.
- Window-title samples were not usable as speed proof because the visuals were
  black-overlay: `17` samples, avg `48.94 FPS`, min `37.60`, max `59.16`.

Counters:

- The full GPU probe summarizer timed out on this invalid large log, so the
  narrow 0x451c quick parser was used for route/counter triage.
- Dynamic MFC rows/hits: `1,661 / 187,484`.
- Dynamic MFC bytes/timing: `391.98 MB / 222.374 ms`.
- Dynamic PC split: `0x25cc=15,253 / 15.323 ms`,
  `0x451c=172,231 / 207.051 ms`.
- Dynamic command split: `get=179,836`, `put=7,648`, `list=71,253`,
  `atomic=0`.
- MFC list-transfer calls/timing: `71,253 / 85.154 ms`, descriptor bytes
  `1.07 MB`.
- GPU candidate rows/total DMA: `1,661 / 1.59 GB`.
- Direct RSX-local bytes: `0 B`.

Reading:

- One small left pulse after the clean loader-control reproof did not survive
  visual proof. This is a route/control rejection, not a speed result and not
  HLE/GPU evidence.
- The refiner now flags repeated black-overlay pre-field captures and says to
  stop adding movement until a no-movement loader/control is re-proven or a
  black-overlay route-control guard is added.
- Broad SPU-to-Vulkan remains parked because this run again shows `0 B`
  direct RSX-local traffic.

Classification:

- `failed-black-overlay-visual`, `route-control-rejection`,
  `not-comparable`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  200% gate candidate.

Next:

- Do not repeat the same left200 movement command.
- Re-prove a no-movement loader/control with `CleanAfterField`, or add/use a
  black-overlay route-control guard before more movement or lane-2 HLE/GPU
  dry-runs.

## 2026-05-24 Loader-Control Reproof After Left200 Black Overlay

Question:

- After the left200 route-control rejection, is the no-movement Windows
  loader/control path still healthy enough to use as the next route base?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-after-left200-black-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260524-225725-cpu4-loader-control-after-left200-black-reproof-windows`

Verification:

- RPCS3 launched through the Windows lab on `\\.\DISPLAY2`; CPU affinity
  `0x0F` was applied.
- Host contention was clean/external-clean across all `6` snapshots.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `10` field-like screenshots, `0`
  invalid screenshots after first field, and required field by `160s` passed.
- Clean fatal scan found no fatal log marker, access violation,
  likely-crashed, `Unknown STOP`, assertion, unhandled exception, segfault,
  `VK_ERROR`, or device-lost hits.
- Window-title samples averaged `32.39 FPS` (`28.55` min, `38.84` max), route
  reproof only and not a speed comparison.

Counters:

- GPU probe observed `2,208.10 MB` total DMA.
- GPU Port Scoreboard stayed at promoted CPU/SPU -> GPU replacement
  `0 records / 0 B / 0.000%`, direct RSX-local scout traffic
  `0 records / 0 B / 0.000%`, and indirect overlap
  `0 records / 0 B / 0.000%`.
- Offload fit mix: `spu-kernel-hle=1057`, `too-small=372`.
- Hot PC totals: `0x451c=1,107.26 MB` over `750` records and
  `0x25cc=1,100.85 MB` over `679` records.
- Reservation-loop verify records: `5,494`.
- Reservation-loop attempts/completed: `120,265 / 34,100`; success/failure/
  unexpected: `20,325 / 13,775 / 5,594`.

Reading:

- The no-movement loader/control route recovered cleanly after the left200
  black-overlay rejection. The failure is movement/route-control-sensitive, not
  a general Windows lab/display failure.
- This is a route-control repair, not a speed win, not a GPU migration credit,
  and not HLE fast-path evidence.
- Broad SPU-to-Vulkan remains parked because direct RSX-local traffic and
  indirect overlap are still `0 B`.
- The refiner now allows one small state-aware movement step from this clean
  base while keeping lane-2 HLE/GPU fast modes blocked. Because the last exact
  left200 pulse black-overlayed, do not trust movement counters unless the next
  run passes the visual gate.

Classification:

- `valid-field-triage`, `route-control-reproof`, `analysis`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- If continuing route work, use this clean loader-control run as the base and
  add only one guarded movement step with `CleanAfterField`.
- Do not start `VerifyShadow`, preserve-order copier, Android/ADB/Thor work, or
  GPU-offload promotion from counters alone.

## 2026-05-24 Harness Refiner First-Movement Failure Guard

Question:

- Should the refiner suggest the exact `loader-control-left200` movement again
  after that first movement black-overlayed once and a later no-movement
  loader/control reproof passed?

Change:

- `tools/ps3_harness_refiner.ps1` now blocks the first failed
  `loader-control-left200` step after a clean no-movement boundary instead of
  waiting for two failures.
- `.agents/skills/ps3-continual-harness-refiner/SKILL.md` now carries the same
  reusable rule for future heartbeat turns.

Verification:

- PowerShell parser validation passed for
  `tools/ps3_harness_refiner.ps1`.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` now reports:
  `Do not auto-rerun loader-control-left200. It already failed after a clean
  no-movement boundary`.
- The dry run emits `single-next-loader-control-failure` and the suggested
  command is a comment, not another `left200` movement run.

Reading:

- This prevents a duplicate invalid Windows capture and keeps the sprint moving
  toward route-control repair or focused SPU kernel HLE/codegen/verifier work.
- It is process tooling only. It does not move CPU/SPU/PPU work to GPU, does
  not prove speed, and does not advance the 200% moving-gameplay gate.

Classification:

- `process-harness`, `route-control-guard`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Do not repeat the exact `loader-control-left200` run. Add/use black-overlay
  route control, shrink/change the movement pulse, or switch to focused SPU
  kernel HLE/codegen/verifier analysis before another movement run.

## 2026-05-24 0x451c Contract Scout Refresh

Question:

- After blocking the duplicate `left200` route, what is the safest next
  Windows-only CPU/SPU speed lane around hot PC `0x451c`?

Command:

```powershell
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.md`
- `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.csv`

Verification:

- The scout used `4` valid fatal-clean field runs from the last `8` Windows
  captures and skipped `0` fatal-clean field runs.
- Dynamic MFC `0x451c` coverage: `907,525` hits, `818.67 MB` observed.
- List-transfer `0x451c` coverage: `369,655` calls, `5.75 MB` descriptor
  bytes.
- Top runtime-cost lane was `small-list-control`: `588,183` hits,
  `531.29 MB`, `633.479 ms`, `449` descriptors.
- Top single descriptor was the exact GET preserve-copy bucket
  `0x40/tag31/size256/lsa0x4a00`: `143,497` hits, `130.69 MB`,
  `128.886 ms`.
- Broad `0x46` list-control coverage is too wide for a two-seed fast path:
  top two predicate seeds cover only `30,992` hits (`5.27%`) and
  `72.229 ms` (`11.40%`).
- Shadow verifier evidence blocks copy-elision for the exact `0x451c` bucket:
  `5,867` shadow hits, `1.43 MB` shadowed, `288` output mismatches,
  `5,867` destination changes, and `0` skip hits.

Reading:

- The next useful CPU/SPU lane is not a GPU dispatch and not a copy skip. It is
  either a broader verify-only `0x46` family recognizer or deeper
  `do_list_transfer` descriptor batching that preserves DMA order.
- The best broad family is `tag=0,size=8`: `103` descriptors, `139,985` hits,
  `122.50 MB`, and `206.189 ms`; the sibling `tag=1,size=8` family has
  `116` descriptors, `235,120` hits, `211.25 MB`, and `196.756 ms`.
- Vulkan compute remains parked for this bucket because the valid field set
  still has `0 B` RSX-local bytes.

Classification:

- `analysis`, `spu-hle-codegen-targeting`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Add a verify-only `0x46` tag/size family recognizer or descriptor-batch
  family counters before any fast path. Preserve DMA ordering and destination
  writes; do not attempt copy-elision or GPU compute from this evidence.

## 2026-05-24 0x451c Family Verify No-Movement Reproof

Question:

- Does the current verify-only `0x451c` list-family/descriptor-batch
  instrumentation survive a fresh no-movement Windows field route after the
  contract scout said the broad family path is the next CPU/SPU lane?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-family-verify-nomove-after-contract `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260524-232051-hle-451c-family-verify-nomove-after-contract-windows`

Verification:

- RPCS3 launched through the Windows lab on `\\.\DISPLAY2`; CPU affinity
  `0x0F` was applied.
- Host contention stayed clean/external-clean across all `6` snapshots.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `10` field-like screenshots, `0` invalid
  screenshots after first field, and required field by `160s` passed.
- Clean fatal scan found no fatal log marker, access violation,
  likely-crashed, `Unknown STOP`, assertion, unhandled exception, segfault,
  `VK_ERROR`, or device-lost hits.
- Window-title samples averaged `34.79 FPS` (`31.39` min, `42.96` max), but
  this is route/instrumentation context only, not a speed comparison.

Counters:

- GPU probe observed `2,247.62 MB` total DMA.
- GPU Port Scoreboard stayed at promoted CPU/SPU -> GPU replacement
  `0 records / 0 B / 0.000%`, direct RSX-local scout traffic
  `0 records / 0 B / 0.000%`, and indirect overlap
  `0 records / 0 B / 0.000%`.
- Offload fit mix stayed CPU/SPU-shaped: `spu-kernel-hle=1058`,
  `too-small=419`.
- `0x451c` hot-PC total: `813` records, `1,163.79 MB`; `0x25cc` hot-PC
  total: `664` records, `1,083.84 MB`.
- Focused list-family parser found `784` family rows, `97,695` hits,
  `97,695 / 0` success/fail, `1.52 MB` descriptor bytes, and `134.531 ms`
  total family verifier timing.
- Family split: `tag0_size16=30,067` (`30.78%`),
  `tag1_size16=29,586` (`30.28%`), `tag0_size24=10,569` (`10.82%`),
  `tag1_size24=10,312` (`10.56%`), `tag0_size8=8,597` (`8.80%`),
  `tag1_size8=8,564` (`8.77%`).
- Descriptor-batch preserve-order coverage was substantial:
  `97,695` groups, `196,590` descriptors, `519.30 MB`, max `3`
  descriptors / `30.39 KB` per group, with `95,175` full groups and
  `2,520` zero stops.
- The refreshed contract scout including this run now reports dynamic MFC
  `0x451c` coverage of `924,058` hits / `831.41 MB` and broad `0x46`
  list-control coverage of `604,052` hits / `545.56 MB` / `688.173 ms`.

Reading:

- The verify-only family recognizer is field-clean and fatal-clean in a fresh
  no-movement route. That gives us a stable CPU/SPU HLE/codegen target surface.
- The hottest family in this run is `tag0_size16`, not the earlier broad
  aggregate's `tag0_size8`. This argues for batch/family-level verifier
  design, not a tiny two-seed fast path.
- Copy-elision and Vulkan compute remain blocked: destination writes must be
  preserved, and this run again shows `0 B` direct RSX-local traffic.

Classification:

- `valid-field-triage`, `spu-hle-codegen-targeting`, `analysis`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Design the next verifier around preserve-order `0x46` family descriptor
  batches, with command/tag/size/family coverage and destination-write
  preservation. Do not repeat `left200`, do not enable a fast path, and do not
  port this to GPU/Thor from this evidence.

## 2026-05-24 0x451c Batch-Shape Summarizer

Question:

- Can we turn the fresh field-clean `0x451c` descriptor-batch/list-family CSVs
  into a narrow implementation surface for the next CPU/SPU HLE/codegen
  experiment?

Tooling:

- Added `tools/summarize_eternal_sonata_451c_batch_shape.ps1`.
- Parser check passed: `batch-shape syntax ok`.
- Ran it against
  `debug-captures/windows-lab/20260524-232051-hle-451c-family-verify-nomove-after-contract-windows`.
- Wrote:
  `debug-captures/windows-lab/20260524-232051-hle-451c-family-verify-nomove-after-contract-windows/eternal-sonata-451c-batch-shape-summary.md`
  and
  `debug-captures/windows-lab/20260524-232051-hle-451c-family-verify-nomove-after-contract-windows/eternal-sonata-451c-batch-shape-families.csv`.

Batch shape:

- Preserve-order groups: `97,695`; descriptors: `196,590`; bytes:
  `519.30 MB`.
- Average preserve descriptors/group: `2.012`; average bytes/group:
  `5.44 KB`.
- Multi-descriptor groups: `80,534` (`82.43%`); full groups: `95,175`
  (`97.42%`); zero stops: `2,520` (`2.58%`).
- Nonzero descriptor split is all inline GET: `196,590 / 196,590`
  (`100.00%`), inline PUT `0`, DMA fallback `0`.
- Top preserve-order family by calls is `tag0_size16`: `30,067` calls
  (`30.78%`), estimated `39.470 ms`.
- The sibling `tag1_size16` is `29,586` calls (`30.28%`), estimated
  `38.732 ms`.

Reading:

- This is a better next implementation target than the earlier tiny two-seed
  fast path. The stable shape is a preserve-order inline-GET family batch path:
  mostly multi-descriptor/full groups, exact `BLUS30161`/image/PC/command and
  six tag-size families.
- The path still must preserve destination writes and DMA ordering. This is
  not copy-elision.
- GPU migration credit stays at `0 B`: the current evidence is CPU-side
  SPU/DMA/list-control work with `0 B` direct RSX-local traffic, so Vulkan
  compute remains parked for this bucket.

Classification:

- `analysis`, `harness-tooling`, `spu-hle-codegen-targeting`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Design a verify-only preserve-order `0x451c` family batch path in RPCS3 code,
  gated on title/image/SPU PC/command/tag-size family, before any fast mode or
  Windows A/B speed claim.

## 2026-05-24 0x451c Exact Preserve-Family Counters

Question:

- Can the next Windows capture report exact preserve-order group/descriptor/byte
  totals per `0x451c` tag-size family instead of estimating family bytes from
  mixed rows?

Change:

- In local `rpcs3-upstream`, added exact per-family preserve counters to the
  `0x451c` descriptor-batch verifier:
  `preserve_familyN_groups`, `preserve_familyN_desc`, and
  `preserve_familyN_bytes` for families `1..6`.
- Updated the `Eternal Sonata SPU HLE 451c descriptor batch verifier:` log row
  in `rpcs3/Emu/Cell/lv2/sys_spu.cpp` to emit those exact fields.
- Updated `tools/summarize_eternal_sonata_gpu_probe.ps1` to parse/export the
  new fields while remaining compatible with older logs.
- Updated `tools/summarize_eternal_sonata_451c_batch_shape.ps1` to prefer exact
  preserve-family fields when present, and keep the old estimate path for older
  captures.

Verification:

- PowerShell parser checks passed for `summarize_eternal_sonata_gpu_probe.ps1`
  and `summarize_eternal_sonata_451c_batch_shape.ps1`.
- `summarize_eternal_sonata_451c_batch_shape.ps1 -NoWrite` still summarizes the
  latest old field-clean capture and labels per-family bytes as estimated
  because those older logs do not contain the new exact fields.
- Windows RPCS3 build passed:
  `cmake --build C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`.

Reading:

- This is a verifier/tooling improvement for the next CPU/SPU HLE/codegen step.
  It gives the next capture exact family-level preserve-order batching evidence
  before any fast path.
- It does not change emulator behavior unless `RPCS3_ES_SPU_HLE_VERIFY` is
  enabled, and it does not move any work to GPU.
- GPU migration credit remains `0 B`; broad SPU-to-Vulkan compute stays parked
  until a capture proves RSX-consumed or GPU-resident data.

Classification:

- `harness-tooling`, `analysis`, `spu-hle-codegen-targeting`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Run one fresh Windows field-clean `Verify` capture with the rebuilt RPCS3 and
  `-WindowsGameScreen 1`, then rerun the batch-shape summarizer to consume the
  exact `preserve_family*` fields. Keep fast mode disabled.

## 2026-05-24 0x451c Exact Preserve-Family Field Capture

Question:

- Do the new exact per-family preserve counters survive a fresh Windows
  field-clean `Verify` route, and do they sharpen the next `0x451c`
  HLE/codegen target?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-exact-preserve-family-verify-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260524-235400-hle-451c-exact-preserve-family-verify-field-windows`

Verification:

- RPCS3 launched from the rebuilt Windows `rpcs3-upstream` Release binary and
  stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `6` snapshots.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `10` field-like screenshots, `0` invalid
  screenshots after first field, and required field by `160s` passed.
- Manual check of `screenshot-0150s.png` shows correct Path to Tenuto field
  gameplay with no obvious visual corruption.
- Fatal-marker scan found no access violation, likely-crashed overlay,
  `VK_ERROR`, device-lost, assertion, unhandled exception, segfault, or
  `Unknown STOP` hits.
- `window-title-samples.csv` recorded `13` samples averaging `33.75 FPS`
  (`30.14` min, `37.45` max). This is instrumentation context, not a speed
  comparison.

Counters:

- GPU probe observed `2,168.94 MB` total DMA.
- GPU Port Scoreboard stayed at promoted CPU/SPU -> GPU replacement
  `0 records / 0 B / 0.000%`, direct RSX-local scout traffic
  `0 records / 0 B / 0.000%`, and indirect overlap
  `0 records / 0 B / 0.000%`.
- Offload fit mix remained CPU/SPU-shaped: `spu-kernel-hle=1042`,
  `too-small=432`.
- `0x451c` hot-PC total: `802` records / `1,075.59 MB`; `0x25cc` hot-PC
  total: `672` records / `1,093.35 MB`.
- Batch-shape summarizer consumed the new exact `preserve_family*` fields:
  `91,259` preserve-order groups, `182,664` descriptors, `478.57 MB`,
  average `2.002` descriptors/group and `5.37 KB`/group.
- Multi-descriptor groups: `74,460` (`81.59%`); full groups: `88,838`
  (`97.35%`); zero stops: `2,421` (`2.65%`).
- Nonzero descriptor split is still all inline GET:
  `182,664 / 182,664` (`100.00%`), inline PUT `0`, DMA fallback `0`.
- Exact preserve-family bytes:
  `tag0_size16=151.85 MB`, `tag1_size16=148.72 MB`,
  `tag0_size24=75.68 MB`, `tag1_size24=73.38 MB`,
  `tag0_size8=14.59 MB`, `tag1_size8=14.35 MB`.
- Top family by groups remains `tag0_size16`: `27,749` groups (`30.41%`),
  followed by `tag1_size16`: `27,345` groups (`29.96%`).

Reading:

- The new exact preserve-family counters are field-clean and useful. They show
  the implementation target is not merely small descriptor bytes; it is
  preserve-order inline-GET copy traffic totaling nearly `479 MB`, mostly in
  the two size-16 families.
- This strengthens the next CPU/SPU lane: design a verify-only family-batch
  copier/codegen path that preserves destination writes and MFC/list ordering.
- It still is not GPU migration. The fresh run again has `0 B` direct RSX-local
  and `0 B` indirect overlap, so broad SPU-to-Vulkan compute stays parked.

Classification:

- `valid-field-triage`, `harness-tooling`, `spu-hle-codegen-targeting`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Design the guarded `0x451c` preserve-order family batch verifier/body in
  `do_list_transfer()`, starting with size-16 families, and keep it verify-only
  until field/menu/Options/first-battle proof and matched Windows A/B exist.

## 2026-05-25 0x451c Size-16 Batch-Candidate Counters

Question:

- Can we narrow the next `0x451c` preserve-order batch body to the two
  size-16 list-command families before writing any fast path?

Change:

- In local `rpcs3-upstream`, extended the verify-only descriptor-batch counters
  in `do_list_transfer()` with exact `size16_candidate_*` fields.
- A size-16 candidate is now counted only for family `3` (`tag0_size16`) or
  family `4` (`tag1_size16`) when the preserve-order group is multi-descriptor,
  full, nonzero, non-stalled, and non-RAW-SPU. Stock DMA behavior is unchanged.
- The descriptor-batch log now emits aggregate candidate groups/descriptors/bytes,
  family-3 and family-4 splits, reject counts, and last candidate shape.
- Updated `tools/summarize_eternal_sonata_gpu_probe.ps1` to parse/export the new
  fields while preserving compatibility with older captures.
- Updated `tools/summarize_eternal_sonata_451c_batch_shape.ps1` to report the
  size-16 full-batch candidate totals when a new capture contains them.

Verification:

- PowerShell parser checks passed for `summarize_eternal_sonata_gpu_probe.ps1`
  and `summarize_eternal_sonata_451c_batch_shape.ps1`.
- The batch-shape summarizer still reads the previous exact-preserve field
  capture with old CSV fields and does not invent size-16 candidate totals.
- Windows RPCS3 build passed:
  `cmake --build C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`.

Reading:

- This is a compile-proven verifier/tooling slice, not a runtime proof yet.
- It should tell the next fresh Windows field capture exactly how much of the
  `0x451c` preserve-order traffic is covered by a first two-descriptor
  size-16 batch body.
- GPU migration credit remains `0 B`: this still targets CPU/SPU list-control
  overhead and preserves destination writes.

Classification:

- `harness-tooling`, `analysis`, `spu-hle-codegen-targeting`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Run one fresh Windows field-clean `Verify` capture with the rebuilt binary and
  `-WindowsGameScreen 1`, then rerun the batch-shape summarizer. If the
  size-16 candidate counters match most family-3/family-4 preserve bytes with
  zero rejects, design the first guarded preserve-order batch body.

## 2026-05-25 0x451c Size-16 Candidate Runtime Smoke Failed Visual Gate

Question:

- Do the new size-16 candidate counters emit in a Windows runtime capture, and
  can the capture be used as field-clean proof for the next `0x451c` batch body?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-size16-candidate-verify-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-001633-hle-451c-size16-candidate-verify-field-windows`

Verification:

- RPCS3 launched from the rebuilt Windows `rpcs3-upstream` Release binary and
  stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `6` snapshots.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; all `10` screenshots were
  `black-overlay-small-png`.
- Manual check of `screenshot-0150s.png` confirms black gameplay output with
  only the performance overlay visible. The title/overlay FPS was around
  `49 FPS`, but this is not usable field evidence.
- Fatal-marker scan found only the config line `Show fatal error hints: false`,
  no real access violation, likely-crashed overlay, `VK_ERROR`, device-lost,
  assertion, unhandled exception, segfault, or `Unknown STOP` hit.
- `window-title-samples.csv` recorded `13` samples averaging `49.31 FPS`
  (`39.24` min, `56.69` max). This is invalid-visual context only.

Counters:

- GPU probe observed `1,472.09 MB` total DMA.
- GPU Port Scoreboard stayed at promoted CPU/SPU -> GPU replacement
  `0 records / 0 B / 0.000%`, direct RSX-local scout traffic
  `0 records / 0 B / 0.000%`, and indirect overlap
  `0 records / 0 B / 0.000%`.
- Offload fit mix remained CPU/SPU-shaped: `spu-kernel-hle=718`,
  `too-small=811`.
- `0x451c` hot-PC total: `1,124` records / `845.88 MB`; `0x25cc` hot-PC
  total: `405` records / `626.21 MB`.
- Batch-shape summarizer consumed the new `size16_candidate*` fields:
  preserve-order groups `67,344`, descriptors `132,438`, bytes `389.82 MB`;
  multi-descriptor groups `55,251` (`82.04%`); full groups `67,344`
  (`100.00%`); zero stops `0`.
- Size-16 full-batch candidate counters reported `45,408` groups,
  `90,816` descriptors, `249.27 MB`, and `0` rejects. Split:
  `tag0_size16=23,086` groups / `127.36 MB`, `tag1_size16=22,322`
  groups / `121.91 MB`.

Reading:

- The new counters are runtime-visible and parser-visible, but this run is not
  field-clean. Treat the size-16 numbers as a smoke check only, not as body
  promotion evidence.
- The black-overlay route failure means do not design or enable a fast path from
  this capture alone, even though the candidate counters look strong.
- GPU migration credit remains `0 B`: this still targets CPU/SPU list-control
  overhead and preserves destination writes.

Classification:

- `failed-black-overlay-visual`, `harness-tooling-smoke`, not
  `valid-field-triage`, not `windows-micro-win`, not `gpu-migration-credit`,
  not a 200% gate candidate.

Next:

- Re-prove the size-16 candidate counters on a field-clean `Verify` route before
  designing the first guarded preserve-order batch body. Do not repeat movement;
  use the black-overlay route-control guidance from the continual harness
  refiner or rerun the no-movement field route only after confirming no active
  RPCS3/RPCSX process is present.

## 2026-05-25 Continual Refiner HLE Size-16 Black-Overlay Priority

Question:

- After the latest `0x451c` size-16 candidate capture black-overlayed, can the
  continual refiner prevent an older loader-control failure from steering the
  next HLE/codegen step?

Change:

- Updated `tools/ps3_harness_refiner.ps1` to detect when the newest run is an
  HLE/SPU `0x451c` size-16 candidate capture with `black-overlay-small-png`
  visuals.
- Added a dedicated `hle-size16-candidate-black-overlay` blocker so those
  counters are explicitly marked smoke-only and cannot justify body design or a
  fast path.
- Added a reproof command shape that keeps the route no-movement, Windows-only,
  `-WindowsGameScreen 1`, `EternalSonataSpuHleVerify Verify`, and
  `CleanAfterField`.
- Updated `.agents/skills/ps3-continual-harness-refiner/SKILL.md` with the same
  reusable rule.

Verification:

- Confirmed no active `rpcs3`/`rpcsx` process before changing the harness.
- PowerShell parser check passed for `tools/ps3_harness_refiner.ps1`.
- Dry-run refiner now says:
  `Latest 0x451c size-16 candidate capture black-overlayed; discard it for body
  design, confirm no active RPCS3/RPCSX process, then re-prove the no-movement
  HLE Verify route with CleanAfterField before implementing a batch body.`
- The suggested command is the intended field-clean reproof:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-451c-size16-candidate-reproof-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -WindowsHostContentionGate ExternalFail -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8`

Reading:

- This is harness/process work only. It does not move work to the GPU, does not
  speed up gameplay, and does not count toward the 200% Windows gate.
- It protects the next useful `0x451c` SPU HLE/codegen step by refusing to use
  black-overlay counters as promotion evidence.

Classification:

- `process-harness`, `failed-black-overlay-guard`, `spu-hle-codegen-targeting`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

Next:

- Run the suggested no-movement size-16 `Verify` reproof only after confirming
  no active `rpcs3`/`rpcsx` process. If it reaches a clean field with fatal-clean
  logs, rerun the batch-shape summarizer and then design the first guarded
  preserve-order size-16 batch body.

## 2026-05-25 0x451c Size-16 Candidate Reproof Field-Clean

Question:

- Do the new `0x451c` size-16 candidate counters survive a field-clean Windows
  no-movement `Verify` capture after the prior black-overlay smoke run?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-size16-candidate-reproof-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-003434-hle-451c-size16-candidate-reproof-field-windows`

Verification:

- Confirmed no active `rpcs3`/`rpcsx` process before the run.
- RPCS3 launched from the rebuilt Windows `rpcs3-upstream` Release binary and
  stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `6` snapshots.
- The parent shell hit its `360s` timeout after RPCS3 had already stopped at the
  scripted `190s` wall limit, so post-processing was completed manually.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `10` field-like screenshots, `0` invalid
  screenshots after first field, and required field by `160s` passed.
- Manual check of `screenshot-0150s.png` shows correct Path to Tenuto field
  gameplay with no obvious visual corruption.
- Fatal-marker scan found no real access violation, likely-crashed overlay,
  `VK_ERROR`, device-lost, assertion, unhandled exception, segfault, or
  `Unknown STOP` hit.
- `window-title-samples.csv` recorded `13` samples averaging `33.74 FPS`
  (`24.78` min, `40.72` max). This is instrumentation context, not a speed
  comparison.

Counters:

- GPU probe observed `2,268.20 MB` total DMA.
- GPU Port Scoreboard stayed at promoted CPU/SPU -> GPU replacement
  `0 records / 0 B / 0.000%`, direct RSX-local scout traffic
  `0 records / 0 B / 0.000%`, and indirect overlap
  `0 records / 0 B / 0.000%`.
- Offload fit mix remained CPU/SPU-shaped: `spu-kernel-hle=1100`,
  `too-small=376`.
- `0x451c` hot-PC total: `781` records / `1,139.06 MB`; `0x25cc` hot-PC
  total: `695` records / `1,129.14 MB`.
- Batch-shape summarizer consumed the field-clean `size16_candidate*` fields:
  preserve-order groups `96,156`, descriptors `192,905`, bytes `505.98 MB`;
  multi-descriptor groups `78,946` (`82.10%`); full groups `93,644`
  (`97.39%`); zero stops `2,512` (`2.61%`).
- Size-16 full-batch candidates: `58,631` groups, `117,262` descriptors,
  `317.63 MB`, `60.97%` of preserve groups, `60.79%` of preserve descriptors,
  and `0` rejects. Split:
  `tag0_size16=29,567` groups / `160.58 MB`; `tag1_size16=29,064` groups /
  `157.05 MB`.

Reading:

- The size-16 candidate counters are now field-clean proof, not just runtime
  smoke. They cover about `318 MB` of the `0x451c` preserve-order inline-GET
  work in this no-movement field route.
- This is still a CPU/SPU HLE/codegen target, not GPU migration. The fresh run
  again has `0 B` direct RSX-local and `0 B` indirect overlap, so broad
  SPU-to-Vulkan compute remains parked.
- Updated the continual refiner so this valid size-16 HLE reproof is treated as
  the current HLE/codegen baseline. Its next action is now a bounded
  preserve-order inline-GET batch copier/verifier design, not another movement
  rerun.

Classification:

- `valid-field-triage`, `harness-tooling`, `spu-hle-codegen-targeting`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Inspect the `rpcs3-upstream` `do_list_transfer()` path and implement the first
  verify-gated preserve-order size-16 inline-GET batch body. Keep fast mode
  disabled until matched Windows field/menu/Options/first-battle A/B proves
  correctness and measurable timing or CPU-load reduction.

## 2026-05-25 0x451c Size-16 Verify Body Build

Question:

- Can the field-clean `0x451c` size-16 candidate route be turned into a narrow
  verify-gated body without enabling a fast/skip mode or touching Android/Thor?

Changed:

- In local Windows `rpcs3-upstream`, added a bounded `do_list_transfer()` body
  for Eternal Sonata `BLUS30161`, SPU image `0x958dfe208b686622`, PC `0x451c`,
  `MFC_GETLF_CMD`, and the existing `Verify` HLE gate only.
- The body handles only size-16 list families, which means two 8-byte list
  descriptors, not 16-byte payloads. It requires two nonzero inline-GET
  descriptors, no stall bit, no RAW-SPU EA, and preserves the stock destination
  rule `arg_lsa + (ea & 0xf)` with `align(size, 16)` advancement.
- Added `size16_body_*` counters to the SPU HLE descriptor-batch log so the next
  capture can prove whether the new body executed and what share of the
  `58,631` clean candidates it covered.
- Updated `tools/summarize_eternal_sonata_gpu_probe.ps1` and
  `tools/summarize_eternal_sonata_451c_batch_shape.ps1` to parse/report the new
  body counters. Old logs default those fields to zero.

Verification:

- Confirmed no active `rpcs3`/`rpcsx`/build process before starting the edit.
- PowerShell parser checks passed for both summarizers.
- Windows RPCS3 Release build passed:
  `cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6`.
- Re-ran the GPU probe summarizer and batch-shape summarizer on the latest
  field-clean run
  `debug-captures/windows-lab/20260525-003434-hle-451c-size16-candidate-reproof-field-windows`.
  The descriptor-batch CSV now includes the `size16_body_*` columns, and the old
  run remains body-zero as expected.
- Stopped idle MSBuild node-reuse workers after the build so the next heartbeat
  will not misread them as an active sprint task.

Reading:

- This is the first executable HLE/codegen body for the clean `0x451c` size-16
  candidate, but it has not yet been gameplay-proven. It is not a speed win and
  not GPU migration credit.
- Broad SPU-to-Vulkan compute stays parked because the latest field-clean
  evidence still shows `0 B` direct RSX-local and `0 B` indirect RSX overlap.

Classification:

- `codegen-hle-body-built`, `windows-only`, `spu-hle-codegen-targeting`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Run a Windows-only field `Verify` capture with the rebuilt binary and require
  clean field visuals plus nonzero `size16_body_*` counters. If that survives,
  repeat menu/Options and first-battle visual proof before any timing or CPU-load
  claim.

## 2026-05-25 0x451c Size-16 Body Black-Overlay Rejection

Question:

- Does the first executable size-16 body preserve visuals when it handles the
  field-clean `0x451c` candidates?

Body-on command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-size16-body-verify-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Body-on run:

- `debug-captures/windows-lab/20260525-010824-hle-451c-size16-body-verify-field-windows`

Body-on result:

- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`, all `10` screenshots were
  `black-overlay-small-png` around `32-33 KB`.
- Manual check of `screenshot-0150s.png` confirms black scene output with only
  the performance overlay visible.
- Fatal-marker scan found no real crash/access/Vulkan/assertion/STOP hit.
- Host contention stayed clean/external-clean across all `6` snapshots.
- The body did execute: `size16_body_groups=45,505`,
  `size16_body_desc=91,010`, `size16_body_bytes=251.21 MB`, which was `100%`
  of the size-16 candidates in that capture.
- Window title samples averaged `49.78 FPS`, but this is invalid speed evidence
  because visuals were black.

Immediate guardrail:

- Moved the size-16 body behind explicit opt-in env
  `RPCS3_ES_SPU_HLE_SIZE16_BODY`.
- Added `-EternalSonataSpuHleSize16Body Off|Verify` to
  `tools/windows_rpcs3_lab.ps1` and `tools/eternal_sonata_speed_sprint.ps1`.
  Default is `Off`; plain `-EternalSonataSpuHleVerify Verify` no longer runs the
  body.
- Rebuilt Windows RPCS3 Release successfully after adding the guard.

Body-off reproof command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-size16-body-off-reproof-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Body-off run:

- `debug-captures/windows-lab/20260525-012014-hle-451c-size16-body-off-reproof-field-windows`

Body-off verification:

- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, all `10` screenshots field-like, `0`
  invalid screenshots after first field.
- Manual check of `screenshot-0150s.png` shows correct Path to Tenuto field
  gameplay.
- Fatal-marker scan found no real crash/access/Vulkan/assertion/STOP hit.
- Host contention stayed clean/external-clean across all `6` snapshots.
- Body counters stayed off: `size16_body_groups=0`, `size16_body_desc=0`,
  `size16_body_bytes=0`.
- Candidate counters remained present: `53,608` groups, `107,216` descriptors,
  `290.88 MB`.
- Window title samples averaged `32.53 FPS`. This is baseline context, not a
  speed comparison.

Harness update:

- `tools/ps3_harness_refiner.ps1` now detects a body-on black-overlay followed
  by a clean body-off reproof and blocks automatic body reruns.
- `.agents/skills/ps3-continual-harness-refiner/SKILL.md` carries the same
  rule.
- Dry-run refiner now says:
  `Latest body-off Verify reproof is clean after the size16 body-on path
  black-overlayed; keep the body opt-in/off and inspect/repair the body copy
  semantics before rerunning it.`

Reading:

- This was a useful negative result: the body moved a real chunk of CPU-side
  list work into the new optimized body, but visuals went black. It must stay
  off by default.
- The clean body-off reproof means the baseline HLE/candidate instrumentation is
  still healthy.
- This is not a speed win, not GPU migration credit, and not a 200% gate
  candidate.

Classification:

- `failed-black-overlay-visual`, `body-executed-invalid`, `guarded-off`,
  `spu-hle-codegen-targeting`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Inspect the two-descriptor body against stock `do_list_transfer()` semantics.
  Do not rerun body-on until the copy semantics are narrowed or repaired behind
  `-EternalSonataSpuHleSize16Body Verify`.

## 2026-05-25 0x451c Size-16 Body Release-Exit Field Pass

Question:

- Does routing the repaired opt-in size-16 body through the stock common
  `range_lock->release(0)` exit preserve field visuals?

Changed:

- In local Windows `rpcs3-upstream`, changed the two-descriptor body completion
  from a direct `return true` to a `break` so successful body execution reaches
  the stock `range_lock->release(0); return true;` exit.
- Kept the body behind explicit opt-in
  `-EternalSonataSpuHleSize16Body Verify`; default remains off.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so a field-clean body run is treated as
  correctness-only proof until menu/Options and first-battle also pass.

Build:

```powershell
cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6
```

- Windows RPCS3 Release build passed. The existing LNK4098 warning remained,
  but `build-msvc\bin\rpcs3.exe` was produced.

Body-on field proof:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label hle-451c-size16-body-releasefix-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Verify `
  -WindowsHostContentionGate ExternalFail `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-013912-hle-451c-size16-body-releasefix-field-windows`

Verification:

- Visual gate passed: `FIELD_LIKE_PRESENT`; first field-like screenshot was
  `screenshot-0117s.png` at `117s`.
- All `10/10` screenshots were field-like, with `0` invalid screenshots after
  first field.
- Manual check of `screenshots\screenshot-0150s.png` shows correct Path to
  Tenuto field gameplay, not the previous black-overlay failure.
- Strict fatal scan found no real crash/access/Vulkan/assertion/STOP hit after
  excluding known `cellSpurs*ExceptionEventHandler` and hint-setting lines.
- Host contention stayed clean/external-clean across all `6` snapshots.

Counters:

- SPU HLE descriptor-batch records: `798`.
- `size16_body_groups=63,855`, `size16_body_desc=127,710`,
  `size16_body_bytes=346.22 MB`, covering `100%` of size-16 candidates.
- Body split: `tag0_size16=32,217` groups / `64,434` descriptors /
  `175.12 MB`; `tag1_size16=31,638` groups / `63,276` descriptors /
  `171.10 MB`.
- Preserve-order groups: `104,947`; preserve-order descriptors: `210,991`;
  preserve-order bytes: `550.82 MB`.
- Window title samples averaged `34.36 FPS` with min `29.50` and max `39.83`.
  This is context only, not speed proof.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The release-exit repair appears to fix the first black-overlay cause for the
  opt-in size-16 body on the no-movement field route.
- This is a field-only correctness pass. The body still needs menu/Options and
  first-battle visual/fatal proof, then matched A/B timing, before any win,
  promotion, or 200% gate claim.
- This remains CPU/SPU HLE/codegen work. It moves work into a narrower CPU-side
  HLE body, but it is not GPU migration credit because the capture still shows
  `0 B` RSX-local and `0 B` indirect RSX overlap.

Classification:

- `spu-hle-size16-body-field-pass`, `windows-field-correctness`,
  `body-opt-in`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  200% gate candidate.

Next:

- Run Windows-only menu/Options and first-battle proofs with
  `-EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Verify`.
  Only after those are visually and fatal-clean should the body enter matched
  A/B timing or CPU-load comparison.

## 2026-05-25 0x451c Size-16 Body Options Route Miss

Question:

- Does the release-exit repaired size-16 body also survive the title
  menu/Options checkpoint?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene menu `
  -Label hle-451c-size16-body-releasefix-options `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Verify `
  -WindowsHostContentionGate ExternalFail `
  -MaxSeconds 135 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 70 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-015311-hle-451c-size16-body-releasefix-options-windows`

Verification:

- Host contention stayed clean/external-clean across `5` snapshots.
- Strict fatal scan found no real crash/access/Vulkan/assertion/STOP hit after
  excluding known `cellSpurs*ExceptionEventHandler` and hint-setting lines.
- Manual screenshots show correct rendering, but the route missed the title
  Options target and landed in the intro/cutscene instead:
  - `screenshots\screenshot-0077s.png`: intro field scene, not title menu;
  - `screenshots\screenshot-0096s.png`: intro subtitle scene;
  - `screenshots\screenshot-0104s.png`: tree cutscene with subtitle;
  - later screenshots remain cutscene-style, not Options.
- Window-title samples averaged `34.22 FPS` with min `28.68` and max `42.83`.
  This is context only, not a speed or menu proof.

Counters:

- SPU HLE descriptor-batch records: `608`.
- Size-16 body executed: `41,891` groups, `83,782` descriptors, `227.53 MB`,
  covering `100%` of size-16 candidates in this route.
- Body split: `tag0_size16=21,155` groups / `42,310` descriptors /
  `115.31 MB`; `tag1_size16=20,736` groups / `41,472` descriptors /
  `112.23 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- This is not a menu/Options proof. The repaired body survived a non-field intro
  route without black overlay or fatal markers, but the current menu macro is
  not reliable enough under this body-on/logged boot timing.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so this body-on Options route miss does
  not send the sprint back to unrelated loader-control movement. The next action
  stays route repair/state gating for menu/Options proof.
- The next Windows-only step should repair or harden the title Options route,
  for example by waiting for the real title menu before pressing Down/Options,
  before counting the body as menu-clean.
- Still no GPU migration credit: this remains CPU/SPU HLE/codegen work with
  `0 B` RSX-local and `0 B` indirect RSX overlap.

Classification:

- `not-comparable-menu-route-miss`, `body-opt-in`, `windows-visual-clean-context`,
  not `menu-options-proof`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Repair the Windows `menu` route or add a route-state visual gate so the
  title menu/Options checkpoint is proven explicitly before first-battle proof
  or A/B timing.

## 2026-05-25 0x451c Size-16 Body Title Options Route Repair

Question:

- Can the body-on menu route be repaired enough to prove the title
  menu/Options checkpoint instead of drifting straight into the intro/cutscene?

Harness change:

- Updated `tools/eternal_sonata_speed_sprint.ps1` `-Scene menu` to use the
  older PadApi-safe direct title-menu navigation shape:
  `wait; shot; down; shot; down; shot; cross; shot`.
- Removed the initial `Cross` at 65s because the prior body-on run used it while
  timing was drifting and skipped into the attract/intro route instead of
  stabilizing the title menu.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene menu `
  -Label hle-451c-size16-body-releasefix-options-nocross `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Verify `
  -WindowsHostContentionGate ExternalFail `
  -MaxSeconds 125 `
  -ScreenshotEverySeconds 8 `
  -ScreenshotStartSeconds 60 `
  -ScreenshotMaxCount 9
```

Run:

- `debug-captures/windows-lab/20260525-020435-hle-451c-size16-body-releasefix-options-nocross-windows`

Verification:

- Host contention stayed clean/external-clean across `5` snapshots.
- Strict fatal scan found no real crash/access/Vulkan/assertion/STOP hit after
  excluding known `cellSpurs*ExceptionEventHandler` and hint-setting lines.
- Manual screenshots:
  - `screenshots\screenshot-0068s.png`: correct Eternal Sonata title menu;
  - `screenshots\screenshot-0069s.png`: title menu with `LOAD` highlighted;
  - `screenshots\screenshot-0095s.png`, `screenshot-0102s.png`, and
    `screenshot-0108s.png`: title menu with `OPTIONS` visible/selected;
  - `screenshot-0116s.png` and `screenshot-0124s.png`: later attract/intro
    sequence, so this is not a clean full Options-page hold.
- Window-title samples averaged `73.06 FPS` with min `15.14` and max `107.55`.
  This is title-menu/route context only, not speed proof.

Counters:

- SPU HLE descriptor-batch records: `481`.
- Size-16 body executed: `29,880` groups, `59,760` descriptors, `164.69 MB`,
  covering `100%` of size-16 candidates in this route.
- Body split: `tag0_size16=15,114` groups / `30,228` descriptors /
  `83.52 MB`; `tag1_size16=14,766` groups / `29,532` descriptors /
  `81.17 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The route repair is useful: the opt-in size-16 body can reach and render the
  title menu with `OPTIONS` selected after the release-exit fix.
- Do not count this as a full Options-page proof or any speed proof. The macro
  still waits too long and lets the attract/intro sequence take over after the
  title-menu checkpoint.
- Next menu work should either stop the capture at the selected-Options
  checkpoint or press/open Options immediately after the second `down`, then
  verify the full Options page. First-battle proof remains outstanding.
- Still no GPU migration credit: this remains CPU/SPU HLE/codegen work with
  `0 B` RSX-local and `0 B` indirect RSX overlap.

Classification:

- `menu-title-options-selected`, `route-repair`, `body-opt-in`,
  `windows-visual-clean-context`, not `full-options-page-proof`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Tighten the menu macro to open or stop on Options before attract takeover, or
  run the first-battle proof with the body opt-in if title-menu Options
  selection is accepted as the current menu checkpoint.

## 2026-05-25 0x451c Size-16 Body Full Options Fast-Open Proof

Question:

- Can the repaired body-on route open and hold the real title Options page
  before attract/intro takeover?

Harness change:

- Updated `tools/eternal_sonata_speed_sprint.ps1` `-Scene menu` to open
  Options immediately after the second title-menu down pulse:
  `wait:65000;shot:100;down:220;wait:800;shot:100;down:220;wait:800;shot:100;cross:240;wait:8000;shot:100;wait:6000;shot:100`.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so clean full Options-page body runs
  classify as `valid-options-triage` instead of misleading
  wrong-window/field-loader failures. The refiner now points to first-battle
  proof as the next step.
- Parser check passed for `tools/eternal_sonata_speed_sprint.ps1`.
- Parser check passed for `tools/ps3_harness_refiner.ps1`.
- `git diff --check -- tools/eternal_sonata_speed_sprint.ps1` passed with only
  the existing LF-to-CRLF warning.

Command:

```powershell
$macro = 'wait:65000;shot:100;down:220;wait:800;shot:100;down:220;wait:800;shot:100;cross:240;wait:8000;shot:100;wait:6000;shot:100'
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene menu `
  -Label hle-451c-size16-body-releasefix-options-fastopen `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Verify `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro $macro `
  -MaxSeconds 105 `
  -ScreenshotEverySeconds 8 `
  -ScreenshotStartSeconds 60 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-022003-hle-451c-size16-body-releasefix-options-fastopen-windows`

Verification:

- Host contention stayed clean/external-clean across `5` snapshots.
- Strict fatal scan found no real crash/access/Vulkan/assertion hit after
  excluding normal boot/config noise and known hint/exception-handler lines.
- Manual screenshots:
  - `screenshots\screenshot-0068s.png`: correct title menu at `NEW GAME`;
  - `screenshots\screenshot-0071s.png`: title menu with `OPTIONS` selected;
  - `screenshots\screenshot-0080s.png` and `screenshot-0086s.png`: full
    title Options page, stable and visually clean.
- Window-title samples: `13` samples, average `47.99 FPS`, min `37.37`, max
  `61.54`. This is route context only, not speed proof.

Counters:

- GPU probe records: `756`; SPU HLE verifier records: `756`; SPU HLE 0x451c
  descriptor-batch records: `561`.
- Total observed DMA bytes: `711.87 MB`; offload fit mix:
  `spu-kernel-hle=328`, `too-small=428`.
- Size-16 body executed: `22,723` groups, `45,446` descriptors, `125.04 MB`,
  covering `100%` of size-16 candidates in this route.
- Body split: `tag0_size16=11,538` groups / `23,076` descriptors /
  `64.01 MB`; `tag1_size16=11,185` groups / `22,370` descriptors /
  `61.03 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- This closes the missing full title Options-page visual proof for the opt-in
  `0x451c` size-16 body after the release-exit fix.
- The body still needs first-battle proof before any speed A/B, promotion, or
  200% gate claim.
- Still no GPU migration credit: this remains CPU/SPU HLE/codegen work with
  `0 B` RSX-local and `0 B` indirect RSX overlap.

Classification:

- `full-options-page-proof`, `body-opt-in`, `windows-visual-clean-context`,
  `route-repair`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  200% gate candidate.

Next:

- Run the Windows-only first-battle proof with
  `-EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Verify`
  and `-WindowsGameScreen 1`. If field, full Options, and first battle are all
  clean, move to matched A/B timing before any speed claim.

## 2026-05-25 0x451c Size-16 Body First-Battle Black Overlay

Question:

- Does the release-exit repaired, Options-clean size-16 body survive the first
  battle visual checkpoint?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-size16-body-releasefix-battle `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Verify `
  -WindowsHostContentionGate ExternalFail `
  -MaxSeconds 330 `
  -ScreenshotEverySeconds 20 `
  -ScreenshotStartSeconds 220 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-023256-hle-451c-size16-body-releasefix-battle-windows`

Verification:

- The Windows lab stopped RPCS3 at the configured `330s`; the outer Codex shell
  timeout interrupted before the normal GPU summary post-pass completed, so raw
  log checks were used for counters.
- No RPCS3/RPCSX process remained active after the run.
- Host contention stayed clean/external-clean across `5` snapshots.
- Strict fatal scan found no real crash/access/Vulkan/assertion hit.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; all captured screenshots were
  black/perf-overlay-sized (`~32-33 KB`).
- Manual screenshot checks of `screenshots\screenshot-0244s.png`,
  `screenshot-0305s.png`, and `screenshot-0320s.png` show a black frame with
  only the performance overlay, not active first-battle visuals.
- Window-title samples: `12` samples, average `49.56 FPS`, min `43.33`, max
  `59.50`. This is invalid route context, not speed proof.

Raw counters from `RPCS3.log`:

- SPU HLE 0x451c descriptor-batch records: `2,055`.
- Preserve-order groups: `125,380`; descriptors: `248,330`; bytes:
  `740.15 MB`.
- Size-16 body executed: `83,484` groups, `166,968` descriptors,
  `460.41 MB`.
- Body split: `tag0_size16=42,420` groups / `84,840` descriptors /
  `235.51 MB`; `tag1_size16=41,064` groups / `82,128` descriptors /
  `224.90 MB`.
- SPU HLE verifier records: `2,775`; hits: `16,679`; bytes: `164.23 MB`.
- MFC dynamic probe records: `2,775`; bytes: `625.74 MB`; PC mix:
  `0x25cc=22,245` hits, `0x451c=304,020` hits.

Reading:

- The body path is field-clean and full-Options-clean, but it is not
  first-battle-clean. Treat the body as opt-in/off by default and do not run
  speed A/B or promotion from it.
- Counters from this run are runtime smoke only because the visuals are black.
  They must not drive GPU/HLE fast-mode promotion.
- The refiner was updated so this failure is classified as
  `hle-size16-body-battle-black-overlay`, not as a generic size-16 candidate or
  loader-control failure. Its next action is a body-off first-battle reproof on
  the same route before another body-on battle attempt.
- Still no GPU migration credit: this remains CPU/SPU HLE/codegen work, and the
  visual failure blocks correctness before any speed or 200% claim.

Classification:

- `failed-black-overlay-visual`, `first-battle-proof-failed`, `body-opt-in-off`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

Next:

- Run the same Windows-only first-battle route with
  `-EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off` to
  separate route/control from the size-16 body semantics, then inspect or narrow
  the body before any body-on battle rerun.

## 2026-05-25 0x451c Size-16 Body-Off Battle Reproof Window-Lost

Question:

- Was the body-on first-battle black overlay caused by the size-16 body itself,
  or by the current Windows battle route/window control?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-size16-body-off-battle-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -WindowsHostContentionGate ExternalFail `
  -MaxSeconds 330 `
  -ScreenshotEverySeconds 20 `
  -ScreenshotStartSeconds 220 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-025556-hle-451c-size16-body-off-battle-reproof-windows`

Verification:

- Host contention stayed clean/external-clean across `3` snapshots.
- Refiner fatal scan found no crash/access/Vulkan/assertion/STOP hit.
- Manual screenshot `screenshots\screenshot-0131s.png` shows a clean field
  frame around `31.96 FPS`, not battle.
- The required later screenshots were not captured: the lab reported
  `game window was not found` at `183s`, `244s`, and `304s`.
- This is not a clean body-off first-battle proof. It only proves the route can
  reach field with the size-16 body off before losing the game window.

Counters:

- GPU probe records: `1014`; SPU HLE verifier records: `1014`; SPU HLE 0x451c
  descriptor-batch records: `630`.
- Total observed DMA bytes: `1,317.51 MB`; offload fit mix:
  `spu-kernel-hle=629`, `too-small=385`.
- Preserve-order 0x451c batch candidates observed with body off:
  `60,859` groups, `121,731` descriptors, `348,418,496` bytes.
- Size-16 candidates observed with body off: `38,439` groups, `76,878`
  descriptors, `219,276,880` bytes. Size-16 body execution stayed `0` by
  design.
- SPU HLE shadow summary showed 0x25cc remained redundant on this route
  (`dst_unchanged=364`, `output_mismatch=0`), while 0x451c was real-copy work
  (`dst_changed=2213`, `output_mismatch=164`).
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Harness change:

- Updated `tools/ps3_harness_refiner.ps1` to classify runs with later
  `game window was not found` screenshot skips as
  `failed-window-lost-after-field` before accepting them as valid field triage.
- Updated `tools/windows_rpcs3_lab.ps1` so future screenshot skips distinguish
  between an exited RPCS3 process and a live process with an empty
  `MainWindowHandle`. The main loop now also logs the exact early process-exit
  second when RPCS3 exits before `-MaxSeconds`.
- Updated the repo-local `ps3-continual-harness-refiner` skill with the same
  route/window-loss rule and the new process-exit distinction.
- Parser checks passed for `tools/windows_rpcs3_lab.ps1` and
  `tools/ps3_harness_refiner.ps1`.

Reading:

- The body-off reproof does not clear the body path for battle. It changes the
  blocker from "body-on black overlay only" to "battle route/window control is
  not giving valid battle evidence either."
- Do not rerun body-on battle or run speed A/B from this evidence. First repair
  the Windows battle route/window-lost gate or add a shorter state-gated battle
  capture that proves the transition and active first-battle visuals.
- Still no GPU migration credit: this remains SPU HLE/codegen investigation
  with `0 B` RSX-local and `0 B` indirect RSX overlap.

Classification:

- `failed-window-lost-after-field`, `battle-proof-incomplete`,
  `body-opt-in-off`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  200% gate candidate.

Next:

- Keep `-EternalSonataSpuHleSize16Body Off` while repairing the Windows battle
  route/window gate. The next useful step is a route-only or shorter
  state-gated battle capture that keeps RPCS3 visible through active first
  battle before inspecting size-16 body semantics again.

## 2026-05-25 Body-Off Battle Window-Loss Diagnostic

Question:

- Does the body-off battle route lose the window because the process exits, or
  because the window handle goes missing while RPCS3 is still running?

Command:

```powershell
$macro = 'wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;ls_left:2600;wait:1000;combo:ls_left+ls_down:2200;wait:45000;shot:post-move-check'
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-size16-body-off-battle-windowloss-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro $macro `
  -MaxSeconds 195 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-031502-hle-451c-size16-body-off-battle-windowloss-diagnostic-windows`

Verification:

- No duplicate RPCS3/RPCSX/build process was active before the run.
- The route stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across `3` snapshots.
- `screenshots\screenshot-0131s-field-check.png` is a clean Path to Tenuto
  field frame around `32.56 FPS`, not first battle.
- The later labeled screenshot did not happen: the lab logged
  `Screenshot skipped at 183s: game window was not found; process has exited
  with code exited.` and `Process exited at 183s before max 195s.`
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted log scan found suspicious guest/RSX-side lines shortly before exit:
  repeated `unknown draw command (3f7c9752)`, an RSX cached-object parameter
  mismatch at `0xC801DF80`, `Unexpected instruction 'invalid'`,
  `Unknown/illegal instruction: 0x5f`, `Unknown/illegal instruction: 0x62`,
  and `ROP reads from r0 without writing to it.`

Counters:

- GPU probe records: `1001`; SPU HLE verifier records: `1001`; SPU HLE
  shadow records: `1000`; SPU HLE 0x451c descriptor-batch records: `618`.
- Total observed DMA bytes: `1,371.85 MB`; offload fit mix:
  `spu-kernel-hle=636`, `too-small=365`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`:
  `775.67 MB`; `CellSpursKernelGroup` / top PC `0x25cc`: `596.18 MB`.
- Dynamic MFC: `170,213` hits, `317.73 MB`, `168.503 ms`;
  `0x451c=158,336` hits / `135.985 ms`, `0x25cc=11,877` hits /
  `32.518 ms`.
- MFC list transfer: `64,677` calls, `57.253 ms`, all at `0x451c`.
- Preserve-order 0x451c batch candidates observed with body off:
  `64,677` groups, `129,378` descriptors, `368,448,080` bytes.
- Size-16 candidates observed with body off: `40,124` groups, `80,248`
  descriptors, `228,686,080` bytes. Size-16 body execution stayed `0` by
  design.
- SPU HLE shadow summary: `0x25cc` stayed redundant
  (`dst_unchanged=370`, `output_mismatch=0`), while `0x451c` was real-copy work
  (`dst_changed=2411`, `output_mismatch=147`).
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Harness change:

- Updated `tools/ps3_harness_refiner.ps1` to count window-loss lines where
  RPCS3 has actually exited, then recommend a left-only battle route isolation
  command instead of a generic window-gate repair. Parser check passed, and the
  latest refiner report now calls the blocker `battle-route process exit`.

Reading:

- The earlier body-off battle reproof's window loss is now sharpened: this
  route exits RPCS3 after a clean field checkpoint, so it is not merely an empty
  `MainWindowHandle`.
- The shortest failing suffix currently includes `ls_left:2600` plus
  `combo:ls_left+ls_down:2200`. Do not rerun the full battle proof or body-on
  battle until route control isolates which movement/input branch triggers the
  process exit or guest exit.
- Still no GPU migration credit: this is SPU HLE/codegen target sizing with
  `0 B` direct RSX-local and `0 B` indirect RSX overlap.

Classification:

- `failed-process-exit-after-field`, `failed-window-lost-after-field`,
  `battle-route-process-exit`, `body-opt-in-off`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep `-EternalSonataSpuHleSize16Body Off` and run one shorter Windows-only
  route isolation step: field checkpoint, `ls_left` only, screenshot, no
  diagonal combo. If that survives, test the diagonal branch separately. If it
  exits again, inspect the nearby guest/RSX `unknown draw command` path before
  returning to size-16 body semantics.

## 2026-05-25 Body-Off Battle Left-Only Exit Diagnostic

Question:

- Is the post-field process exit caused by the diagonal movement branch, or is
  a left-only movement already enough to trigger it?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-size16-body-off-battle-leftonly-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;ls_left:2600;wait:45000;shot:left-only-check" `
  -MaxSeconds 185 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-033011-hle-451c-size16-body-off-battle-leftonly-diagnostic-windows`

Verification:

- The route stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across `3` snapshots.
- `screenshots\screenshot-0131s-field-check.png` is a clean Path to Tenuto
  field frame. Title-bar sample was `37.12 FPS`; overlay instant FPS was about
  `31.00`.
- After only `ls_left:2600`, the follow-up screenshot did not happen: the lab
  logged `Screenshot skipped at 179s: game window was not found; process has
  exited with code exited.` and `Process exited at 179s before max 185s.`
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted log scan again found the guest `unknown draw command` path right
  after the field/left movement window, now with `unknown draw command
  (3f5fbf16)` repeated from PPU PC `0x003f2a64`. Early boot still shows RSX
  invalid-instruction/ROP warnings, but no fatal/access/Vulkan/assertion hit.

Counters:

- GPU probe records: `992`; SPU HLE verifier records: `992`; SPU HLE shadow
  records: `991`; SPU HLE 0x451c descriptor-batch records: `602`.
- Total observed DMA bytes: `1,313.71 MB`; offload fit mix:
  `spu-kernel-hle=622`, `too-small=370`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`: `723.38 MB`;
  `CellSpursKernelGroup` / top PC `0x25cc`: `590.33 MB`.
- Preserve-order 0x451c batch candidates observed with body off:
  `60,300` groups, `120,420` descriptors, `341,948,320` bytes.
- Size-16 candidates observed with body off: `37,244` groups, `74,488`
  descriptors, `213,071,184` bytes. Size-16 body execution stayed `0` by
  design.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Harness change:

- Updated `tools/ps3_harness_refiner.ps1` so a latest `leftonly-diagnostic`
  process exit does not recommend the same left-only run again. It now
  recommends a no-post-field-movement diagnostic to separate route/timer exit
  from movement-triggered guest exit.
- Parser check passed, and the latest refiner report points at
  `hle-451c-size16-body-off-battle-nopostmove-diagnostic`.

Reading:

- The diagonal branch is not required. A left-only movement after the clean
  field checkpoint is enough to trigger the same process-exit class.
- Body semantics remain blocked: this was body-off, and it still failed before
  any first-battle proof.
- Still no GPU migration credit: this is route/control and SPU HLE target
  sizing with `0 B` direct RSX-local and `0 B` indirect RSX overlap.

Classification:

- `failed-left-only-process-exit-after-field`,
  `failed-window-lost-after-field`, `battle-route-process-exit`,
  `body-opt-in-off`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  200% gate candidate.

Next:

- Keep `-EternalSonataSpuHleSize16Body Off` and run the no-post-field-movement
  diagnostic from the refiner. If no movement still exits, the battle route is
  landing in a timer/guest-exit state before battle. If no movement survives,
  shrink the left pulse before testing diagonal movement or returning to
  size-16 body semantics.

## 2026-05-25 Body-Off Battle No-Post-Field-Movement Diagnostic

Question:

- Does the body-off battle route exit by itself after the field checkpoint, or
  does the post-field movement pulse trigger the process-exit class?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-size16-body-off-battle-nopostmove-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;wait:45000;shot:no-postfield-move-check" `
  -MaxSeconds 185 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-034157-hle-451c-size16-body-off-battle-nopostmove-diagnostic-windows`

Verification:

- No duplicate RPCS3/RPCSX/build process was active before the run.
- The route stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- `screenshots\screenshot-0131s-field-check.png` is a clean Path to Tenuto
  field frame. Title sample: `34.15 FPS`.
- `screenshots\screenshot-0177s-no-postfield-move-check.png` is still a clean
  Path to Tenuto field frame after waiting with no post-field movement. Title
  sample: `30.83 FPS`; host samples around the same window read `29.34` and
  `34.87 FPS`.
- RPCS3 did not disappear before the second screenshot. The harness stopped it
  only after the planned `185s` wall-time cap.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Refiner result: newest clean descriptor-batch Verify route restored the HLE
  baseline; do not rerun movement. Move to bounded preserve-order inline-GET
  batch copier/verifier design while broad SPU-to-Vulkan remains parked.

Counters:

- GPU probe records: `1437`; SPU HLE verifier records: `1437`; SPU HLE shadow
  records: `1436`; SPU HLE `0x451c` descriptor-batch records: `811`.
- Total observed DMA bytes: `2,139.60 MB`; offload fit mix:
  `spu-kernel-hle=982`, `too-small=455`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`:
  `1,156.17 MB`; `CellSpursKernelGroup` / top PC `0x25cc`: `983.42 MB`.
- Dynamic MFC: `258,192` hits, `506.92 MB`, `284.910 ms`;
  `0x451c=238,859` hits / `233.106 ms`, `0x25cc=19,333` hits /
  `51.804 ms`.
- MFC list transfer: `96,953` calls, `116.314 ms`, all at `0x451c`.
- Preserve-order `0x451c` batch candidates observed with body off:
  `96,953` groups, `195,055` descriptors, `539,020,080` bytes.
- Size-16 candidates observed with body off: `58,155` groups, `116,310`
  descriptors, `331,513,952` bytes. Size-16 body execution stayed `0` by
  design.
- SPU HLE shadow summary: `0x25cc` stayed redundant
  (`dst_unchanged=603`, `output_mismatch=0`), while `0x451c` was real-copy work
  (`dst_changed=3344`, `output_mismatch=192`).
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The no-post-field route survives. The earlier process-exit class is not a
  simple timer or waiting state after the field checkpoint; it is tied to the
  post-field movement branch or route control after movement starts.
- This restores a clean HLE descriptor-batch baseline, but it is not first
  battle proof and it is not a body correctness proof.
- The hottest measurable CPU-side target is still the `0x451c` preserve-order
  dynamic list/inline-GET family, not direct GPU compute. Broad SPU-to-Vulkan
  remains parked because the run again found `0 B` direct RSX-local and `0 B`
  indirect RSX overlap.

Classification:

- `valid-field-triage`, `hle-descriptor-baseline-clean`, `body-opt-in-off`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

Next:

- Keep `-EternalSonataSpuHleSize16Body Off` and do not rerun movement next.
  Inspect `do_list_transfer()` / `process_mfc_cmd()` around the `0x451c`
  dynamic `0x46` list path and implement a verify-gated preserve-order
  inline-GET batch copier/verifier with a rollback switch before enabling any
  fast path.

## 2026-05-25 0x451c Preserve-Body Field Smoke

Question:

- Can a rollback-gated preserve-order inline GET body execute the partial
  `0x451c` dynamic list batches without breaking the clean no-post-field route?

Implementation:

- Added `RPCS3_ES_SPU_HLE_451C_PRESERVE_BODY`, exposed as
  `-EternalSonataSpuHle451cPreserveBody Verify`.
- The path is title-gated to `BLUS30161`, requires
  `-EternalSonataSpuHleVerify Verify`, and only consumes partial fetch groups
  where all descriptors are non-stalled GETs from non-RAW-SPU memory.
- `-EternalSonataSpuHleSize16Body` stays a separate opt-in and remained `Off`
  for this run.
- Parser support now emits `eternal-sonata-spu-hle-451c-preserve-body-profile.csv`.

Build:

```powershell
cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6
```

Result:

- Build passed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-nopostmove-field-smoke `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Verify `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;wait:45000;shot:no-postfield-move-check" `
  -MaxSeconds 185 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-040906-hle-451c-preserve-body-nopostmove-field-smoke-windows`

Verification:

- The route stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- `screenshots\screenshot-0131s-field-check.png` is a clean Path to Tenuto
  field frame. Title sample: `29.61 FPS`.
- `screenshots\screenshot-0177s-no-postfield-move-check.png` is still a clean
  Path to Tenuto field frame after waiting with no post-field movement. Title
  sample: `29.99 FPS`.
- RPCS3 was stopped only by the planned `185s` wall-time cap.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found no `F`, access violation, SIGSEGV/SIGBUS,
  assertion, `VK_ERROR`, verification-failed, or unknown-draw-command hit.
- The outer Codex command timed out after the harness stopped RPCS3, so the
  summarizer was rerun manually and completed.

Counters:

- GPU probe records: `1450`; SPU HLE verifier records: `1450`; SPU HLE shadow
  records: `1449`; SPU HLE `0x451c` descriptor-batch records: `772`.
- Preserve-body records: `749`.
- Preserve-body executed: `75,220` groups, `167,870` descriptors,
  `468.67 MB`.
- Total observed DMA bytes: `2,159.18 MB`; offload fit mix:
  `spu-kernel-hle=1023`, `too-small=427`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`:
  `1,122.06 MB`; `CellSpursKernelGroup` / top PC `0x25cc`: `1,037.12 MB`.
- Dynamic MFC: `253,035` hits, `513.71 MB`, `222.594 ms`;
  `0x451c=232,582` hits / `171.202 ms`, `0x25cc=20,453` hits /
  `51.392 ms`.
- MFC list transfer: `94,831` calls, all at `0x451c`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- This is a real CPU-side partial-list body smoke, not just a counter: the
  newly gated path copied `468.67 MB` while preserving clean field visuals.
- It is not a GPU offload. It still executes CPU-side SPU/MFC copy work, and
  the run again found no RSX-local or RSX-overlap lane.
- The field route is clean, but this does not repair the first-battle movement
  branch and does not prove menu/Options, first-battle, speed, or 200%.
- Updated `tools/ps3_harness_refiner.ps1` so a newest preserve-body field-clean
  run recommends title Options proof next instead of falling back to movement.

Classification:

- `valid-field-triage`, `hle-451c-preserve-body-field-clean`,
  `cpu-side-copy-body-smoke`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body opt-in and run the refiner's title Options proof next:
  `-EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off
  -EternalSonataSpuHle451cPreserveBody Verify`.
- Only after Options and first-battle visuals are clean should this move to
  matched timing A/B.

## 2026-05-25 - `0x451c` Preserve-Body Options Proof

Purpose:

- Follow the refiner after the clean field smoke: keep the opt-in
  `0x451c` preserve-order partial inline-GET body gate enabled, prove the
  title Options menu visually, and avoid making speed/GPU migration claims
  before field, menu, and first-battle are all clean.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene menu `
  -Label hle-451c-preserve-body-options-proof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Verify `
  -WindowsHostContentionGate ExternalFail `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 90 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-042628-hle-451c-preserve-body-options-proof-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `8` snapshots.
- `screenshots\screenshot-0068s.png` is the title menu with `NEW GAME`,
  `LOAD`, and `OPTIONS` visible. Title sample: `44.13 FPS`.
- `screenshots\screenshot-0071s.png` highlights `OPTIONS`. Title sample:
  `52.96 FPS`.
- `screenshots\screenshot-0080s.png` opens the full Options page with Battle
  Camera, Attack Button, Vibration, Volume, Subtitles, Voice, and Language
  visible. Title sample: `48.94 FPS`.
- `screenshots\screenshot-0160s.png` is still the full Options page near the
  end of the run. Title sample: `40.79 FPS`.
- RPCS3 was stopped only by the planned `190s` wall-time cap.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found no `F`, access violation, SIGSEGV/SIGBUS,
  assertion, `VK_ERROR`, verification-failed, or unknown-draw-command hit.

Counters:

- GPU probe records: `1462`; SPU HLE verifier records: `1462`; SPU HLE shadow
  records: `1461`; SPU HLE `0x451c` descriptor-batch records: `1032`.
- Preserve-body records: `999`.
- Preserve-body executed: `52,106` groups, `113,480` descriptors,
  `356.61 MB`.
- Total observed DMA bytes: `1,402.39 MB`; offload fit mix:
  `too-small=774`, `spu-kernel-hle=688`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`:
  `794.64 MB`; `CellSpursKernelGroup` / top PC `0x25cc`: `607.75 MB`.
- Dynamic MFC: `166,386` hits, `328.26 MB`, `184.675 ms`;
  `0x451c=153,709` hits / `153.792 ms`, `0x25cc=12,677` hits /
  `30.883 ms`.
- MFC list transfer: `63,897` calls, all at `0x451c`, `68.397 ms`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The preserve-body gate now has clean title Options proof, not just field
  proof. It executed `356.61 MB` of CPU-side list body copy work while keeping
  the Options page stable through the planned cap.
- This is still not a GPU offload and not a speed claim. The scoreboard remains
  `0` newly promoted CPU/SPU -> GPU bytes, `0` direct RSX-local scout bytes,
  and `0` indirect RSX-overlap bytes.
- The next correctness gap is first-battle proof with the same opt-in gate.
  Matched timing A/B and any 200% gate discussion stay blocked until field,
  title Options, and first-battle visuals are all clean.
- Updated `tools/ps3_harness_refiner.ps1` so preserve-body title Options
  proofs are classified as `valid-options-triage` instead of
  `failed-wrong-window-or-other-visual`. The refiner now recommends the
  preserve-body first-battle proof next.

Classification:

- `valid-options-triage`, `hle-451c-preserve-body-options-clean`,
  `cpu-side-copy-body-options-proof`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body opt-in and run first-battle visual/fatal proof with
  `-EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off
  -EternalSonataSpuHle451cPreserveBody Verify`.
- Only after the first-battle proof is clean should this move to matched timing
  A/B against the same route.

## 2026-05-25 - `0x451c` Preserve-Body First-Battle Proof

Purpose:

- Take the preserve-body gate from field plus title Options proof into the
  first-battle route, still opt-in and still Windows-only. This was a
  correctness proof attempt, not a speed A/B.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-first-battle-proof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Verify `
  -WindowsHostContentionGate ExternalFail `
  -MaxSeconds 330 `
  -ScreenshotEverySeconds 20 `
  -ScreenshotStartSeconds 220 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-044006-hle-451c-preserve-body-first-battle-proof-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- `screenshots\screenshot-0131s.png` is a clean Path to Tenuto field frame.
  Title sample: `30.74 FPS`.
- `screenshots\screenshot-0183s.png` reached the first-battle tutorial scene
  with Polka, HP UI, and tutorial text visible. Title sample: `29.96 FPS`.
- `screenshots\screenshot-0244s.png` through `screenshots\screenshot-0320s.png`
  stayed on the same battle tutorial frame, but RPCS3 overlaid
  `The PS3 application has likely crashed, you can close it`.
- `rpcs3.stdout.txt` was empty. `rpcs3.stderr.txt` contained:
  `VM: Access violation reading location 0x40 (unmapped memory)`.
- `RPCS3.log` confirms the fatal at `0:02:16.623492`:
  `PPU[0x100000c] Thread () [0x002aedd0] VM: Access violation reading location 0x40`.
- RPCS3 was stopped by the planned `330s` cap after the emulator had already
  frozen.

Counters:

- GPU probe records: `978`; SPU HLE verifier records: `978`; SPU HLE shadow
  records: `977`; SPU HLE `0x451c` descriptor-batch records: `590`.
- Preserve-body records: `569`.
- Preserve-body executed: `47,689` groups, `105,872` descriptors,
  `303.94 MB`.
- Total observed DMA bytes: `1,306.89 MB`; offload fit mix:
  `spu-kernel-hle=634`, `too-small=344`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`:
  `715.47 MB`; `CellSpursKernelGroup` / top PC `0x25cc`: `591.42 MB`.
- Dynamic MFC: `158,685` hits, `308.48 MB`, `159.114 ms`;
  `0x451c=146,840` hits / `130.383 ms`, `0x25cc=11,845` hits /
  `28.731 ms`.
- MFC list transfer: `60,011` calls, all at `0x451c`, `60.272 ms`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The route did reach first battle, but the fatal log invalidates this as a
  preserve-body correctness pass. Do not count it as battle proof, speed,
  GPU migration credit, or a 200% gate candidate.
- The failure signature is guest/PPU-visible (`PPU[0x100000c]` access
  violation at `0x40`) after battle entry, so the next question is whether the
  route itself now fails or whether preserve-body corrupts battle state.
- Updated `tools/ps3_harness_refiner.ps1` so this specific preserve-body
  first-battle fatal recommends a same-route battle reproof with
  `-EternalSonataSpuHle451cPreserveBody Off` instead of falling back to generic
  loader-control movement.

Classification:

- `failed-fatal-log`, `hle-451c-preserve-body-battle-fatal`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body opt-in/off by default and re-prove the exact first-battle
  route with preserve-body disabled:
  `-EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off
  -EternalSonataSpuHle451cPreserveBody Off`.
- If the body-off reproof is clean, narrow preserve-body semantics before any
  body-on battle retry. If the body-off reproof also fails, treat this as a
  route/gameplay proof problem instead of a preserve-body semantics problem.

## 2026-05-25 - `0x451c` Preserve-Body-Off First-Battle Reproof

Purpose:

- Re-prove the exact first-battle route with preserve-body disabled after the
  opt-in preserve-body run reached battle but froze with the `0x40` access
  violation. This was a route/control proof, not speed A/B.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-first-battle-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -MaxSeconds 330 `
  -ScreenshotEverySeconds 20 `
  -ScreenshotStartSeconds 220 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-045749-hle-451c-preserve-body-off-first-battle-reproof-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `3` snapshots.
- `screenshots\screenshot-0131s.png` is a clean Path to Tenuto field frame.
  Title sample: `35.47 FPS`; overlay shows field gameplay around `29.94 FPS`.
- Later requested screenshots at `183s`, `244s`, and `304s` were skipped
  because the game window was not found and RPCS3 had exited.
- RPCS3 exited before the `330s` cap, with no stdout or stderr output.
- Targeted scan found no `F`, access violation, SIGSEGV/SIGBUS,
  assertion, `VK_ERROR`, verification-failed, or likely-crashed overlay hit.
  It did find guest `sys_tty` `unknown draw command` lines near `0:02:13`,
  right before the window/process loss.

Counters:

- GPU probe records: `994`; SPU HLE verifier records: `994`; SPU HLE shadow
  records: `993`; SPU HLE `0x451c` descriptor-batch records: `625`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes: `1,272.98 MB`; offload fit mix:
  `spu-kernel-hle=594`, `too-small=400`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`:
  `713.87 MB`; `CellSpursKernelGroup` / top PC `0x25cc`: `559.12 MB`.
- Dynamic MFC: `156,918` hits, `299.73 MB`, `129.888 ms`;
  `0x451c=145,713` hits / `102.678 ms`, `0x25cc=11,205` hits /
  `27.21 ms`.
- MFC list transfer: `59,657` calls, all at `0x451c`, `41.965 ms`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- This did not clear the preserve-body semantics question. The body-off route
  only proved the field checkpoint, then lost the RPCS3 process/window before
  battle screenshots.
- Because body-off did not reach first battle cleanly, do not call the previous
  body-on battle fatal a preserve-body corruption proof yet. It is still
  plausible that the battle route/window control is the failing variable.
- `tools/ps3_harness_refiner.ps1` now recognizes this exact
  preserve-body-off battle window/process-loss case and recommends a
  no-post-field-movement diagnostic instead of falling back to generic
  reservation-loop movement.
- The scoreboard remains `0` newly promoted CPU/SPU -> GPU bytes, `0` direct
  RSX-local scout bytes, and `0` indirect RSX-overlap bytes.

Classification:

- `failed-window-lost-after-field`, `hle-451c-preserve-body-off-battle-route-lost`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Run the refiner-suggested no-post-field-movement diagnostic with
  preserve-body Off:
  `-Label hle-451c-preserve-body-off-battle-nopostmove-diagnostic`.
- If RPCS3 exits even without post-field movement, repair/state-gate the battle
  route before preserve-body semantics work. If it stays alive, isolate the
  left/diagonal movement branch before any body-on battle retry.

## 2026-05-25 - Preserve-Body-Off Battle No-Postfield Diagnostic

Purpose:

- Isolate whether the preserve-body-off battle control was losing the RPCS3
  process because of post-field movement or because the battle/load route
  itself was unstable. This kept preserve-body Off and removed all movement
  after the intended field checkpoint.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-nopostmove-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;wait:45000;shot:no-postfield-move-check" `
  -MaxSeconds 185 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-051225-hle-451c-preserve-body-off-battle-nopostmove-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- RPCS3 stayed alive until the planned `185s` wall-time cap, then the harness
  stopped it. This is different from the previous body-off reproof that exited
  before the later battle screenshots.
- `screenshots\screenshot-0131s-field-check.png` and
  `screenshots\screenshot-0177s-no-postfield-move-check.png` are not field or
  first-battle frames. Manual image check shows both are the Load screen with
  `Load complete`, `Save File 04`, Polka level 1, Tenuto South Section, and
  `Save file has been damaged`.
- Title samples: `49.79 FPS` at `131s`, `37.58 FPS` at `177s`, plus host
  samples `43.29 FPS` and `51.84 FPS`.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found no real `F`, access violation, SIGSEGV/SIGBUS,
  assertion, `VK_ERROR`, unknown-draw-command, or likely-crashed hit.

Counters:

- GPU probe records: `1284`; SPU HLE verifier records: `1284`; SPU HLE shadow
  records: `1283`; SPU HLE `0x451c` descriptor-batch records: `868`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes: `1,263.77 MB`; offload fit mix:
  `too-small=650`, `spu-kernel-hle=634`.
- Group totals: `TCX_CellSpursKernelGroup` / top PC `0x451c`:
  `708.11 MB`; `CellSpursKernelGroup` / top PC `0x25cc`: `555.66 MB`.
- Dynamic MFC: `148,616` hits, `294.62 MB`, `213.286 ms`;
  `0x451c=136,995` hits / `185.336 ms`, `0x25cc=11,621` hits /
  `27.95 ms`.
- MFC list transfer: `56,867` calls, all at `0x451c`, `80.406 ms`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- This did not prove the body-off battle route. It proved the no-postfield
  diagnostic stayed alive, but the route was parked on the Load menu instead
  of entering the field or battle.
- Do not use these clean counters for HLE/GPU promotion; visuals are invalid
  for field/battle proof.
- The next useful work is route/harness repair: add a battle load/menu state
  gate or adjust the load macro so a diagnostic must prove accepted field
  before post-field movement or preserve-body semantics are tested again.
- Updated `tools/ps3_harness_refiner.ps1` so this exact preserve-body battle
  wrong-route case blocks generic movement and recommends repairing/state-gating
  the Windows battle route before any body-on/body-off semantics work.
- The scoreboard remains `0` newly promoted CPU/SPU -> GPU bytes, `0` direct
  RSX-local scout bytes, and `0` indirect RSX-overlap bytes.

Classification:

- `failed-wrong-window-or-other-visual`, `hle-451c-preserve-body-battle-route-miss`,
  not `valid-field-triage`, not `valid-battle-triage`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Repair or state-gate the Windows battle load route. The next preserve-body
  battle proof should not proceed past the load segment unless it captures a
  real accepted field frame first.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Route Diagnostic

Purpose:

- Repair the preserve-body-off battle load route after the previous
  no-postfield diagnostic parked on damaged `Save File 04`. This normalized the
  load menu back to the top save slot before selecting the save, then required
  accepted field screenshots before any movement or preserve-body semantics work.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;wait:45000;shot:no-postfield-move-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-052534-hle-451c-preserve-body-off-battle-topslot-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- The harness stopped RPCS3 at the planned `205s` cap, and no lingering
  `rpcs3`/`rpcsx` process remained afterward.
- Manual screenshots are both clean Path to Tenuto field frames:
  `screenshots\screenshot-0115s-accepted-field-check.png` and
  `screenshots\screenshot-0161s-no-postfield-move-check.png`.
- Manual visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  at `115s`, no invalid screenshot after first field.
- Window-title samples: `33.16 FPS` at `115s`, `42.67 FPS` at `161s`, plus
  host samples `36.33 FPS` and `34.40 FPS`.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; no access violation,
  SIGSEGV/SIGBUS, assertion, `VK_ERROR`, unknown draw command, verification
  failure, or likely-crashed hit.

Counters:

- GPU probe records: `1616`; SPU HLE verifier records: `1616`; SPU HLE shadow
  records: `1615`; SPU HLE `0x451c` descriptor-batch records: `807`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes from direct probe parsing: `2,634.01 MB`; group
  totals: `CellSpursKernelGroup=1,294.63 MB`,
  `TCX_CellSpursKernelGroup=1,339.38 MB`.
- Max-DMA PC record counts: `0x451c=828`, `0x25cc=788`.
- Dynamic MFC: `303,673` hits, `624.49 MB`, `306.491 ms`;
  `0x451c=278,388` hits / `239.429 ms`, `0x25cc=25,285` hits /
  `67.062 ms`.
- MFC list transfer: `113,518` calls, all at `0x451c`, `91.483 ms`.
- RSX-local/nonzero probe records remain `0`.

Reading:

- The top-slot normalization repaired the immediate load-menu miss. This is a
  route-control result only.
- This does not prove first battle, speed, preserve-body semantics, or GPU
  migration. It only gives a clean accepted-field checkpoint for the next
  branch-isolation run.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so preserve-body-off top-slot field
  diagnostics are not mistaken for opt-in preserve-body proof. The refiner now
  recommends a top-slot-normalized left-only diagnostic next.

Classification:

- `valid-field-triage`, `battle-load-route-repaired-topslot`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and isolate the left-only movement branch using the
  same top-slot-normalized load macro:
  `hle-451c-preserve-body-off-battle-topslot-leftonly-diagnostic`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left-Only Diagnostic

Purpose:

- Test whether the repaired top-slot load route survives the first movement
  branch. Preserve-body stayed Off; this was branch isolation, not semantics or
  speed proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-leftonly-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:2600;wait:45000;shot:left-only-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-054202-hle-451c-preserve-body-off-battle-topslot-leftonly-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `3` snapshots.
- Manual screenshot `screenshots\screenshot-0115s-accepted-field-check.png`
  is a clean Path to Tenuto field frame. Window-title sample: `36.18 FPS`.
- After `ls_left:2600`, the follow-up screenshot was skipped at `164s`
  because the game window was not found and the process had exited. RPCS3
  exited before the `205s` cap.
- No lingering `rpcs3`/`rpcsx` process remained afterward.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted scan found `unknown draw command` guest `sys_tty` lines around
  `0:01:57`, plus `Stub PPU Traps: 0`; it found no access violation,
  SIGSEGV/SIGBUS, assertion, `VK_ERROR`, verification failure, or
  likely-crashed hit.

Counters:

- GPU probe records: `826`; SPU HLE verifier records: `826`; SPU HLE shadow
  records: `825`; SPU HLE `0x451c` descriptor-batch records: `438`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes: `1,114.34 MB`; offload fit mix:
  `spu-kernel-hle=549`, `too-small=277`.
- Group totals: `TCX_CellSpursKernelGroup=521.64 MB`,
  `CellSpursKernelGroup=592.70 MB`.
- Hot PCs: `0x451c=521.64 MB`, `0x25cc=592.70 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The repaired top-slot load still reaches accepted field, but the full
  left-only movement branch exits RPCS3 before a follow-up screenshot. This is
  now a movement-branch/route-control blocker, not the earlier load-menu
  parking problem.
- Do not fall back to the old non-top-slot no-post diagnostic; top-slot
  no-post already stayed alive. The next route step should shrink or repair the
  left-only branch before diagonal movement, preserve-body-on battle, timing, or
  GPU migration claims.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so this exact top-slot left-only exit
  recommends a smaller `ls_left:800` diagnostic instead of the stale
  non-top-slot no-post rerun.

Classification:

- `failed-window-lost-after-field`,
  `hle-451c-preserve-body-off-battle-topslot-leftonly-exit`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and run the refiner-suggested smaller top-slot
  left-only branch diagnostic:
  `hle-451c-preserve-body-off-battle-topslot-left800-diagnostic`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left800 Diagnostic

Purpose:

- Binary-search the route-control failure after full `ls_left:2600` exited
  RPCS3. Preserve-body stayed Off; this was movement-boundary triage, not
  speed, first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left800-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:800;wait:45000;shot:left800-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-055145-hle-451c-preserve-body-off-battle-topslot-left800-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- Manual screenshots
  `screenshots\screenshot-0116s-accepted-field-check.png` and
  `screenshots\screenshot-0162s-left800-check.png` are clean Path to Tenuto
  field frames; the latter confirms the `left800` movement branch survived.
- Visual gate result: `FIELD_LIKE_PRESENT`; first field-like screenshot at
  `116s`, no invalid screenshot after first field, and field PNG size above
  the `1,000,000` byte floor.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no guest
  `unknown draw command`, access violation, SIGSEGV/SIGBUS, assertion,
  `VK_ERROR`, verification failure, or likely-crashed hit.
- Window-title samples: `29.63`, `26.87`, `31.82`, and `33.96 FPS`. These are
  route-control samples only and are not comparable speed results.

Counters:

- The GPU probe summarizer timed out after `180s`, so counters were directly
  parsed from `RPCS3.log` with `rg`.
- GPU probe records: `1,597`; SPU HLE verifier records: `1,597`; SPU HLE
  shadow records: `1,596`; SPU HLE `0x451c` descriptor-batch records: `770`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes: `2,676.9 MB`.
- Hot-PC records: `0x451c=798`, `0x25cc=799`.
- Group totals: `CellSpursKernelGroup=1,303.51 MB`,
  `TCX_CellSpursKernelGroup=1,373.38 MB`.
- Dynamic verifier hits: `309,521` / `635.75 MB` / `293.688 ms`;
  `0x451c=283,948` hits / `230.743 ms`, `0x25cc=25,573` hits /
  `62.945 ms`.
- MFC list transfer: `115,582` calls, all at `0x451c`, `104.984 ms`.
- RSX-local/nonzero probe records remain `0`.

Reading:

- `ls_left:800` survives cleanly, unlike the previous `ls_left:2600` route
  which exited RPCS3 after accepted field. This narrows the current failure to
  movement distance/duration after field, not the load macro, preserve-body
  semantics, or a generic screen-targeting problem.
- This still does not prove first battle, speed, or GPU migration. It also
  gives no RSX-local/offload credit because RSX-local probe records remain
  `0`.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so this `left800` clean boundary
  recommends a `left1600` binary-search diagnostic instead of looping the old
  full left-only route or jumping to diagonal/preserve-body-on work.

Classification:

- `valid-field-triage`, `battle-route-left800-survived`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and run the refiner-suggested binary-search branch:
  `hle-451c-preserve-body-off-battle-topslot-left1600-diagnostic`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left1600 Diagnostic

Purpose:

- Binary-search the post-field movement branch between the clean `left800`
  lower boundary and the failing full `left2600` branch. Preserve-body stayed
  Off; this was route/fatal isolation, not speed, first-battle, or GPU
  migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left1600-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1600;wait:45000;shot:left1600-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-060831-hle-451c-preserve-body-off-battle-topslot-left1600-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- `screenshots\screenshot-0116s-accepted-field-check.png` is the expected Path
  to Tenuto accepted-field checkpoint at `116s`.
- `screenshots\screenshot-0163s-left1600-check.png` is large enough for byte
  triage but visually invalid on manual inspection: it shows a corrupted
  green/yellow noisy field instead of a clean field or battle transition.
- Visual gate result was only `FIELD_LIKE_PRESENT` / `passed-for-triage` with
  `0` byte-class invalid screenshots after first field. Manual review overrides
  that byte triage for correctness.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- `rpcs3.stdout.txt` was empty.
- `rpcs3.stderr.txt` contained a fatal RSX shader/decompiler error:
  `Unimplemented FP CAL instruction`.
- Targeted log scan also found guest `unknown draw command` lines around
  `0:01:58` and `Stub PPU Traps: 0`; it found no access violation,
  SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, or likely-crashed hit.
- Window-title samples: `24.48`, then `27.35` FPS at the corrupted follow-up
  and host samples. These are invalid for speed comparison because the follow-up
  visual and log evidence failed.

Counters:

- GPU probe records: `867`; SPU HLE verifier records: `867`; SPU HLE shadow
  records: `866`; SPU HLE `0x451c` descriptor-batch records: `499`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes: `1,150.31 MB`.
- Offload fit mix: `spu-kernel-hle=546`, `too-small=321`.
- Group totals: `TCX_CellSpursKernelGroup=605.78 MB`,
  `CellSpursKernelGroup=544.53 MB`.
- Hot PCs: `0x451c=528` records / `605.78 MB`,
  `0x25cc=339` records / `544.53 MB`.
- SPU HLE verifier: `6,972` hits, `79.73 MB` candidate bytes.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- `left1600` is above the current safe route boundary. Unlike `left800`, it
  produced fatal RSX/shader evidence and visibly corrupt follow-up visuals even
  though the process stayed alive until the harness cap.
- This is not first-battle proof, not a speed result, and not GPU migration
  credit. The counters remain useful only as failed-run context.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so `left1600` fatal/corruption does not
  fall back to a generic no-movement route or loop `left1600`. The next refiner
  step is to re-prove `left800`; if that lower boundary re-passes, try
  `left1200` as the smaller midpoint.

Classification:

- `failed-fatal-log`, `battle-route-left1600-corrupt-fatal`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and re-prove the clean lower boundary:
  `hle-451c-preserve-body-off-battle-topslot-left800-diagnostic`. If it passes
  again after the `left1600` failure, try
  `hle-451c-preserve-body-off-battle-topslot-left1200-diagnostic`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left800 Reproof

Purpose:

- Re-prove the lower `left800` movement boundary after `left1600` produced
  fatal RSX/shader evidence and corrupt follow-up visuals. Preserve-body stayed
  Off; this was boundary reproof, not speed, first-battle, or GPU migration
  proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left800-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:800;wait:45000;shot:left800-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-061947-hle-451c-preserve-body-off-battle-topslot-left800-reproof-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- Manual screenshots
  `screenshots\screenshot-0115s-accepted-field-check.png` and
  `screenshots\screenshot-0162s-left800-check.png` are clean Path to Tenuto
  field frames; the follow-up shows the `left800` movement boundary survived.
- Visual gate result: `FIELD_LIKE_PRESENT`; first field-like screenshot at
  `115s`, `0` invalid screenshots after first field, and field PNG size above
  the `1,000,000` byte floor.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, guest `unknown draw command`, access
  violation, SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, or likely-crashed
  hit.
- Window-title samples: `25.26`, `27.46`, `27.17`, and `38.47 FPS`. These are
  route-control samples only and are not comparable speed results.

Counters:

- GPU probe records: `1,578`; SPU HLE verifier records: `1,578`; SPU HLE
  shadow records: `1,577`; SPU HLE `0x451c` descriptor-batch records: `760`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes: `2,560.53 MB`.
- Offload fit mix: `spu-kernel-hle=1228`, `too-small=350`.
- Group totals: `CellSpursKernelGroup=1,294.21 MB`,
  `TCX_CellSpursKernelGroup=1,266.33 MB`.
- Hot PCs: `0x25cc=793` records / `1,294.21 MB`,
  `0x451c=785` records / `1,266.33 MB`.
- SPU HLE verifier: `15,055` hits, `186.45 MB` candidate bytes.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- `left800` is now re-proven as the lower clean movement boundary after the
  `left1600` fatal/corrupt run. The current route search bracket is therefore:
  `left800` clean, `left1600` fatal/corrupt, `left2600` exited RPCS3.
- This remains route-control evidence only. It does not prove first battle,
  speed, or GPU migration, and repeated zero RSX-local records keep broad
  SPU-to-Vulkan compute parked.
- The refiner now recommends `left1200` as the next midpoint before diagonal
  movement or any preserve-body-on battle work.

Classification:

- `valid-field-triage`, `battle-route-left800-reproved`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and run the refiner-suggested midpoint:
  `hle-451c-preserve-body-off-battle-topslot-left1200-diagnostic`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left1200 Diagnostic

Purpose:

- Test the midpoint between the re-proven clean `left800` boundary and the
  fatal/corrupt `left1600` boundary. Preserve-body stayed Off; this was
  route-boundary isolation, not speed, first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left1200-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1200;wait:45000;shot:left1200-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-063102-hle-451c-preserve-body-off-battle-topslot-left1200-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- Manual screenshots
  `screenshots\screenshot-0115s-accepted-field-check.png` and
  `screenshots\screenshot-0162s-left1200-check.png` are clean Path to Tenuto
  field frames; the follow-up shows the `left1200` movement boundary survived.
- Visual gate result: `FIELD_LIKE_PRESENT`; first field-like screenshot at
  `115s`, `0` invalid screenshots after first field, and both screenshots above
  the `1,000,000` byte field-like floor.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found no `Unimplemented FP CAL instruction`, guest
  `unknown draw command`, access violation, SIGSEGV/SIGBUS, `VK_ERROR`,
  verification failure, likely-crashed hit, or fatal RSX/shader evidence.
- Window-title samples: `31.27`, `23.25`, `33.39`, and `31.79 FPS`. These are
  route-control samples only and are not comparable speed results.
- `tools\summarize_eternal_sonata_gpu_probe.ps1` timed out on the large
  `RPCS3.log`, so counters below were parsed directly from the same log.

Counters:

- GPU probe records: `1,588`; SPU HLE verifier records: `1,588`; SPU HLE
  shadow records: `1,587`; SPU HLE `0x451c` descriptor-batch records: `772`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`; size-16 body bytes also stayed
  `0`.
- Total observed DMA bytes: `2,618.94 MB`.
- Offload fit mix: `spu-kernel-hle=1234`, `too-small=354`.
- Group totals: `TCX_CellSpursKernelGroup=1,333.42 MB`,
  `CellSpursKernelGroup=1,285.52 MB`.
- Hot PCs: `0x451c=801` records / `1,333.42 MB`,
  `0x25cc=787` records / `1,285.52 MB`.
- SPU HLE verifier: `14,967` hits, `185.50 MB` candidate bytes.
- SPU HLE `0x451c` size-16 candidate bytes: `369.11 MB`.
- RSX-local traffic records remain `0`.

Reading:

- `left1200` is now the clean lower movement boundary after `left1600`
  produced fatal RSX/shader evidence and corrupt visuals. The current bracket
  is `left1200` clean, `left1600` fatal/corrupt, `left2600` exited RPCS3.
- This remains route-control evidence only. It does not prove first battle,
  speed, or GPU migration, and repeated zero RSX-local records keep broad
  SPU-to-Vulkan compute parked.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so a clean `left1200` after fatal
  `left1600` recommends `left1400` instead of falling back to the full
  left-only route.

Classification:

- `valid-field-triage`, `battle-route-left1200-survived`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and run the refiner-suggested midpoint:
  `hle-451c-preserve-body-off-battle-topslot-left1400-diagnostic`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left1400 Diagnostic

Purpose:

- Test the midpoint between clean `left1200` and fatal/corrupt `left1600`.
  Preserve-body stayed Off; this was movement-boundary isolation, not speed,
  first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left1400-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1400;wait:45000;shot:left1400-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-064948-hle-451c-preserve-body-off-battle-topslot-left1400-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `3` snapshots.
- Manual screenshot `screenshots\screenshot-0116s-accepted-field-check.png`
  is a clean Path to Tenuto field frame at the accepted-field checkpoint.
- The planned `left1400` follow-up screenshot was skipped at `163s` because
  the game window was not found and RPCS3 had already exited.
- Visual gate result: `FIELD_LIKE_PRESENT`; first field-like screenshot at
  `116s`, only `1` screenshot total, and no valid post-move screenshot.
- No lingering `rpcs3`/`rpcsx` process remained after the run.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found guest `unknown draw command (3f5fbf16)` entries
  around `0:01:57.993591` and `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, access violation, SIGSEGV/SIGBUS,
  `VK_ERROR`, verification failure, likely-crashed hit, fatal, or assertion.
- Window-title sample at the accepted-field checkpoint was `30.55 FPS`. This
  is route-control context only and is not a comparable speed result.

Counters:

- GPU probe records: `863`; SPU HLE verifier records: `863`; SPU HLE shadow
  records: `862`; SPU HLE `0x451c` descriptor-batch records: `473`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- Total observed DMA bytes: `1,148.58 MB`.
- Offload fit mix: `spu-kernel-hle=562`, `too-small=301`.
- Group totals: `TCX_CellSpursKernelGroup=558.44 MB`,
  `CellSpursKernelGroup=590.14 MB`.
- Hot PCs: `0x451c=495` records / `558.44 MB`,
  `0x25cc=368` records / `590.14 MB`.
- SPU HLE verifier: `7,153` hits, `86.46 MB` candidate bytes.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- `left1400` is above the current clean boundary: it reached accepted field,
  then RPCS3 exited before the post-move screenshot.
- The movement bracket is now `left1200` clean, `left1400` process-exit,
  `left1600` fatal/corrupt, and `left2600` process-exit.
- This does not prove first battle, speed, or GPU migration. Repeated zero
  RSX-local records still keep broad SPU-to-Vulkan compute parked.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so a `left1400` exit after clean
  `left1200` recommends the `left1300` midpoint instead of generic no-post or
  full left-only route work.

Classification:

- `failed-window-lost-after-field`, `battle-route-left1400-exited-after-field`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and run the refiner-suggested midpoint:
  `hle-451c-preserve-body-off-battle-topslot-left1300-diagnostic`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left1300 Diagnostic

Purpose:

- Test the midpoint below the `left1400` process-exit boundary after clean
  `left1200`. Preserve-body stayed Off; this was route-boundary isolation,
  not speed, first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left1300-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1300;wait:45000;shot:left1300-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-070254-hle-451c-preserve-body-off-battle-topslot-left1300-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- Manual screenshots
  `screenshots\screenshot-0115s-accepted-field-check.png` and
  `screenshots\screenshot-0162s-left1300-check.png` are both the Eternal
  Sonata `Now Loading...` screen, not Path to Tenuto field frames.
- Visual gate result: `NO_FIELD_LIKE_SCREENSHOT`; class counts show
  `loading-like-small-png=2`, with no accepted field screenshot.
- Window-title samples reported `119.92` to `120.14 FPS`, but those are loading
  screen samples and are invalid for speed comparison.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, guest `unknown draw command`, access
  violation, SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, likely-crashed
  hit, fatal, or assertion.
- `tools\summarize_eternal_sonata_gpu_probe.ps1` timed out on the large log, so
  counters below were parsed directly from `RPCS3.log`.

Counters:

- GPU candidate probe records: `1,712`; total observed DMA bytes:
  `2,323.13 MB`.
- SPU HLE verifier records: `1,712`; hits: `20,927`; candidate bytes:
  `307.85 MB`.
- SPU HLE shadow records: `1,711`; SPU HLE `0x451c` descriptor-batch records:
  `373`.
- Preserve-body descriptor bytes observed: `147.44 MB`; size-16 candidate
  bytes: `93.27 MB`; size-16 body bytes: `0 B`, as expected with the body Off.
- Offload fit mix: `spu-kernel-hle=1,442` records / `2,191.70 MB`,
  `too-small=270` records / `131.43 MB`.
- Group totals: `CellSpursKernelGroup=1,312` records / `2,007.84 MB`,
  `TCX_CellSpursKernelGroup=400` records / `315.29 MB`.
- Hot PCs: `0x25cc=1,312` records / `2,007.84 MB`,
  `0x451c=400` records / `315.29 MB`.
- RSX-local traffic records remain `0`; RSX-local bytes remain `0`.

Reading:

- `left1300` did not establish a movement boundary because it never reached
  accepted field. Treat it as a loading/route miss, not as clean, process-exit,
  or fatal gameplay evidence.
- The previous valid bracket remains `left1200` clean and `left1400`
  process-exit after accepted field, with `left1600` fatal/corrupt and
  `left2600` process-exit farther out.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so a latest `left1300` loading-only
  run recommends a `left1200` reproof with the same top-slot macro instead of
  generic field movement.

Classification:

- `failed-loading-visual`, `battle-route-left1300-loading-only`,
  not `valid-field-triage`, not `valid-battle-triage`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and re-prove the last clean lower boundary:
  `hle-451c-preserve-body-off-battle-topslot-left1200-reproof-after-left1300-loading`.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left1200 Reproof After Left1300 Loading

Purpose:

- Re-prove the last clean lower boundary after `left1300` produced loading-only
  screenshots. Preserve-body stayed Off; this was route-boundary repair/control,
  not speed, first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left1200-reproof-after-left1300-loading `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1200;wait:45000;shot:left1200-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-071953-hle-451c-preserve-body-off-battle-topslot-left1200-reproof-after-left1300-loading-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- Visual gate result: `FIELD_LIKE_PRESENT`; first field-like screenshot
  `screenshot-0116s-accepted-field-check.png` at `116s` (`2.50 MB`).
  Follow-up `screenshot-0162s-left1200-check.png` was also field-like
  (`2.65 MB`).
- Manual screenshot review shows clean Path to Tenuto field frames at both the
  accepted-field checkpoint and the left1200 follow-up.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, guest `unknown draw command`, access
  violation, SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, likely-crashed
  hit, fatal, or assertion.
- Window-title samples around the screenshots reported `31.03`, `33.31`,
  `29.23`, and `34.41 FPS`; these are route-control samples only and are not
  comparable speed results.

Counters:

- GPU candidate probe records: `1,621`; total observed DMA bytes:
  `2,798.18 MB`.
- SPU HLE verifier records: `1,621`; hits: `15,024`; candidate bytes:
  `172.83 MB`.
- SPU HLE shadow records: `1,620`; SPU HLE `0x451c` list-seed records: `338`;
  list-family records: `863`; descriptor-batch records: `863`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- MFC dynamic records: `1,621`; MFC list-transfer records: `863`; MFC wait
  records: `1,733`; MFC wait exact-PC records: `91,985`.
- Offload fit mix: `spu-kernel-hle=1,237` records / `2,614.88 MB`,
  `too-small=384` records / `183.30 MB`.
- Group totals: `TCX_CellSpursKernelGroup=887` records / `1,601.00 MB`,
  `CellSpursKernelGroup=734` records / `1,197.18 MB`.
- Hot PCs: `0x451c=887` records / `1,601.00 MB`,
  `0x25cc=734` records / `1,197.18 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- `left1200` is re-proven as the clean lower movement boundary after the
  `left1300` loading-only miss.
- `left1300` remains a route/load miss, not a boundary. `left1400` remains
  process-exit after accepted field; `left1600` fatal/corrupt; `left2600`
  process-exit.
- No first-battle, speed, or GPU migration evidence. Repeated zero RSX-local
  records still keep broad SPU-to-Vulkan compute parked.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so a latest `left1200` reproof after
  recent `left1300` loading does not loop back to `left1400` or `left1300`.

Classification:

- `valid-field-triage`, `battle-route-left1200-reproved-after-left1300-loading`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Repair or state-gate the top-slot accepted-field route before another
  midpoint. Keep preserve-body Off until route control is trustworthy again.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Route State Gate After Left1200 Reproof

Purpose:

- Confirm the accepted-field load route is stable again before adding another
  movement midpoint. Preserve-body stayed Off; this was route/state-gate
  tooling, not speed, first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-route-state-gate-after-left1200-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;wait:15000;shot:accepted-field-stability-1;wait:15000;shot:accepted-field-stability-2;wait:30000;shot:accepted-field-stability-3" `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-073543-hle-451c-preserve-body-off-battle-topslot-route-state-gate-after-left1200-reproof-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- RPCS3 stayed alive until the planned `190s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- The initial Codex shell wrapper timed out after the lab run completed, before
  auto post-processing finished; manual visual and GPU summaries were generated
  afterward from the completed run directory.
- Visual gate result: `FIELD_LIKE_PRESENT`; first field-like screenshot
  `screenshot-0115s-accepted-field-check.png` at `115s` (`2.50 MB`), field by
  `160s` passed, invalid-after-first-field count `0`, and all `4` screenshots
  were `field-like-large-png`.
- Manual review of `screenshot-0115s-accepted-field-check.png` and
  `screenshot-0177s-accepted-field-stability-3.png` shows clean Path to Tenuto
  field frames with no loading, black overlay, or visible corruption.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, guest `unknown draw command`, access
  violation, SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, likely-crashed
  hit, fatal, or assertion.
- Window-title samples around the screenshots reported `34.97`, `29.52`,
  `29.87`, `33.49`, `39.15`, and `31.92 FPS`; these are route-control
  samples only and are not comparable speed results.

Counters:

- GPU candidate probe records: `1,460`; total observed DMA bytes:
  `2,348.66 MB`.
- SPU HLE verifier records: `1,460`; hits: `13,350`; candidate bytes:
  `158.11 MB`.
- SPU HLE shadow records: `1,459`; SPU HLE `0x451c` list-seed records: `300`;
  list-family records: `766`; descriptor-batch records: `766`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- MFC dynamic records: `1,460`; MFC list-transfer records: `766`; MFC wait
  records: `1,607`; MFC wait exact-PC records: `83,422`.
- Offload fit mix: `spu-kernel-hle=1,064` records / `2,165.13 MB`,
  `too-small=396` records / `183.54 MB`.
- Group totals: `TCX_CellSpursKernelGroup=790` records / `1,251.83 MB`,
  `CellSpursKernelGroup=670` records / `1,096.83 MB`.
- Hot PCs: `0x451c=790` records / `1,251.83 MB`,
  `0x25cc=670` records / `1,096.83 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The top-slot accepted-field route is stable again when no post-field
  movement is added. That narrows the earlier `left1300` loading-only result to
  a route/state miss, not a new speed or GPU signal.
- This still does not prove first battle, speed, or GPU migration. Repeated zero
  RSX-local records still keep broad SPU-to-Vulkan compute parked.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so this route-state gate recommends a
  smaller state-gated `left1250` diagnostic next instead of falling back to full
  left-only, `left1300`, or `left1400`.

Classification:

- `valid-field-triage`, `battle-route-state-gate-clean-after-left1200-reproof`,
  not `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Keep preserve-body Off and try the refiner-suggested
  `hle-451c-preserve-body-off-battle-topslot-left1250-state-gated-diagnostic`
  before any `left1300` or `left1400` rerun.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Left1250 State-Gated Diagnostic

Purpose:

- Test a smaller midpoint after `left1200` reproof and a clean no-movement
  route-state gate. Preserve-body stayed Off; this was route-boundary
  isolation, not speed, first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-left1250-state-gated-diagnostic `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;wait:10000;shot:accepted-field-pre-left1250;ls_left:1250;wait:45000;shot:left1250-check" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-075219-hle-451c-preserve-body-off-battle-topslot-left1250-state-gated-diagnostic-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- Visual gate result: `NO_FIELD_LIKE_SCREENSHOT`; all `3` screenshots were
  `black-overlay-small-png`, including the accepted-field and pre-left1250
  checkpoints before any left1250 boundary evidence.
- Manual review of `screenshot-0115s-accepted-field-check.png` and
  `screenshot-0172s-left1250-check.png` shows black/perf-overlay output, not
  Path to Tenuto field.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, guest `unknown draw command`, access
  violation, SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, likely-crashed
  hit, fatal, or assertion.
- Window-title samples reported `54.44`, `51.58`, `55.26`, `45.87`, and
  `52.40 FPS`; these are invalid black-overlay samples and are not speed
  evidence.

Counters:

- GPU candidate probe records: `1,656`; total observed DMA bytes:
  `1,604.59 MB`.
- SPU HLE verifier records: `1,656`; hits: `10,195`; candidate bytes:
  `99.20 MB`.
- SPU HLE shadow records: `1,655`; SPU HLE `0x451c` list-seed records: `650`;
  list-family records: `1,210`; descriptor-batch records: `1,210`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- MFC dynamic records: `1,656`; MFC list-transfer records: `1,210`; MFC wait
  records: `1,741`; MFC wait exact-PC records: `84,524`.
- Offload fit mix: `too-small=881` records / `495.01 MB`,
  `spu-kernel-hle=775` records / `1,109.58 MB`.
- Group totals: `TCX_CellSpursKernelGroup=1,241` records / `960.46 MB`,
  `CellSpursKernelGroup=415` records / `644.13 MB`.
- Hot PCs: `0x451c=1,241` records / `960.46 MB`,
  `0x25cc=415` records / `644.13 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- This is not a left1250 movement boundary. The route black-overlayed before
  the pre-movement accepted-field checkpoint, so the result is a route/control
  miss, not evidence that left1250 itself is too far.
- `left1200` remains the latest clean movement boundary. `left1300` remains
  loading-only, `left1400` process-exit after accepted field, and `left1600`
  fatal/corrupt.
- No first-battle, speed, or GPU migration evidence. Repeated zero RSX-local
  records still keep broad SPU-to-Vulkan compute parked.
- Updated `tools/ps3_harness_refiner.ps1` and the repo-local
  `ps3-continual-harness-refiner` skill so a black-overlayed state-gated
  `left1250` recommends accepted-field route-state reconfirm/repair before any
  further midpoint.

Classification:

- `failed-black-overlay-visual`,
  `battle-route-left1250-state-gated-black-before-field`, not
  `valid-field-triage`, not `valid-battle-triage`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Reconfirm or repair the no-movement top-slot accepted-field route-state gate
  before any further movement midpoint.

## 2026-05-25 - Preserve-Body-Off Battle Top-Slot Route-State Reconfirm After Left1250 Black

Purpose:

- Re-run the no-movement top-slot accepted-field route-state gate after the
  state-gated `left1250` diagnostic black-overlayed before its accepted-field
  checkpoints. Preserve-body stayed Off; this was route/control repair
  evidence, not speed, first-battle, or GPU migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label hle-451c-preserve-body-off-battle-topslot-route-state-gate-after-left1200-reproof `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataSpuHleVerify Verify `
  -EternalSonataSpuHleSize16Body Off `
  -EternalSonataSpuHle451cPreserveBody Off `
  -WindowsHostContentionGate ExternalFail `
  -InputMacro "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;wait:15000;shot:accepted-field-stability-1;wait:15000;shot:accepted-field-stability-2;wait:30000;shot:accepted-field-stability-3" `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 0 `
  -ScreenshotStartSeconds 0 `
  -ScreenshotMaxCount 0
```

Run:

- `debug-captures/windows-lab/20260525-080652-hle-451c-preserve-body-off-battle-topslot-route-state-gate-after-left1200-reproof-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `5` snapshots.
- RPCS3 stayed alive until the planned `190s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- Visual gate result: `NO_FIELD_LIKE_SCREENSHOT`; all `4` screenshots were
  `black-overlay-small-png`, including the accepted-field and stability
  checkpoints (`35,429` to `35,878` bytes).
- Manual review of `screenshot-0115s-accepted-field-check.png` and
  `screenshot-0177s-accepted-field-stability-3.png` shows the RPCS3 likely
  crashed overlay on a black screen, not Path to Tenuto field.
- Fatal scan found `VM: Access violation reading location 0x4 (unmapped
  memory)` at PPU PC `0x0007dccc` in both `rpcs3.stderr.txt` and `RPCS3.log`.
  `RPCS3.log` also reported `Stub PPU Traps: 0`.
- Window-title samples around the screenshots reported `29.14`, `30.36`,
  `30.19`, `29.52`, `29.26`, and `30.22 FPS`; these are invalid crash-overlay
  samples and are not speed evidence.

Counters:

- GPU candidate probe records: `325`; total observed DMA bytes: `309.45 MB`.
- SPU HLE verifier records: `325`; hits: `1,941`; candidate bytes: `18.75 MB`.
- SPU HLE shadow records: `324`; SPU HLE `0x451c` list-seed records: `136`;
  list-family records: `241`; descriptor-batch records: `241`.
- Preserve-body records: `0`, as expected with
  `-EternalSonataSpuHle451cPreserveBody Off`.
- MFC dynamic records: `325`; MFC list-transfer records: `241`; MFC wait
  records: `338`; MFC wait exact-PC records: `16,363`.
- Offload fit mix: `too-small=187` records / `109.41 MB`,
  `spu-kernel-hle=138` records / `200.04 MB`.
- Group totals: `TCX_CellSpursKernelGroup=246` records / `187.99 MB`,
  `CellSpursKernelGroup=79` records / `121.46 MB`.
- Hot PCs: `0x451c=246` records / `187.99 MB`,
  `0x25cc=79` records / `121.46 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The accepted-field route-state reconfirm did not re-prove the route after the
  `left1250` black-overlay miss. This failure happened before any further
  movement and carried a real PPU access violation, so it is route/crash
  evidence, not a left1250 boundary and not HLE speed evidence.
- The newest clean movement boundary remains `left1200`, but route/control is
  now unstable enough that further midpoint movement should pause until a
  no-movement loader/control or route-state proof is clean again.
- No first-battle, speed, or GPU migration evidence. Repeated zero RSX-local
  records still keep broad SPU-to-Vulkan compute parked.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` now classifies the latest
  run as `failed-fatal-log` and recommends a no-movement loader/control
  `CleanAfterField` repair before adding movement.

Classification:

- `failed-fatal-log`, `failed-black-overlay-visual`,
  `battle-route-state-gate-fatal-before-field-after-left1250-black`, not
  `valid-field-triage`, not `valid-battle-triage`, not `windows-micro-win`,
  not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Do not rerun the same route-state reconfirm or any `left1250+` midpoint yet.
  Run a no-movement loader/control or repaired accepted-field route proof with
  `CleanAfterField` first, then only resume movement after field visuals and
  fatal logs are clean.

## 2026-05-25 - CPU4 Loader-Control CleanAfterField Reproof

Purpose:

- Repair the route/control base after two black-overlay pre-field runs and one
  fatal route-state reconfirm. This was a no-movement loader/control proof with
  reservation-loop verify counters, not a speed A/B, first-battle proof, or GPU
  migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -MaxSeconds 190 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 120 `
  -ScreenshotMaxCount 8
```

Run:

- `debug-captures/windows-lab/20260525-081533-cpu4-loader-control-visualgate-windows-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `6` snapshots.
- RPCS3 stayed alive until the planned `190s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- Visual gate result: `FIELD_LIKE_PRESENT`; first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.50 MB`), field by `160s` passed, and
  invalid-after-first-field count was `0`.
- Manual review of `screenshot-0117s.png` and `screenshot-0190s.png` shows
  clean Path to Tenuto field frames with the save-point effect visible. No
  black overlay, loading screen, or obvious corruption was visible.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, guest `unknown draw command`, access
  violation, SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, likely-crashed
  hit, fatal, or assertion.
- Window-title samples during the field route ranged from `24.56` to `42.10`
  FPS. These are route-control samples under reservation-loop `Verify`, not
  matched speed evidence.

Counters:

- GPU candidate probe records: `1,445`; total observed DMA bytes:
  `2,236.47 MB`.
- MFC dynamic records: `1,445`; MFC list-transfer records: `759`; MFC wait
  records: `1,596`; MFC wait exact-PC records: `82,424`.
- Reservation-loop command records: `1,595`; command exact-PC records:
  `43,265`; verify records: `5,522`; RDCH join records: `3`; lane-join
  records: `3`; raw-lane records: `8`.
- Offload fit mix: `spu-kernel-hle=1,046` records / `2,032.80 MB`,
  `too-small=399` records / `203.66 MB`.
- Group totals: `TCX_CellSpursKernelGroup=791` records / `1,172.50 MB`,
  `CellSpursKernelGroup=654` records / `1,063.97 MB`.
- Hot PCs: `0x451c=791` records / `1,172.50 MB`,
  `0x25cc=654` records / `1,063.97 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- The no-movement loader/control route is clean again after the fatal
  route-state reconfirm. This resolves the immediate black-overlay control
  blocker for one small state-aware movement test, but it does not repair or
  validate the older top-slot battle-state macro.
- Reservation-loop verify produced clean field visuals and counters, but still
  showed zero RSX-local or indirect RSX overlap, so broad SPU-to-Vulkan compute
  remains parked.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` now recommends using
  this loader-control route as the base for one small `left200`
  `CleanAfterField` movement step while keeping lane-2 HLE/GPU dry-runs
  blocked.

Classification:

- `valid-field-triage`, `loader-control-route-repaired`, not
  `valid-battle-triage`, not `windows-micro-win`, not `gpu-migration-credit`,
  not a 200% gate candidate.

Next:

- Use the refiner-suggested
  `cpu4-loader-control-left200-visualgate-windows` command as the next
  Windows-only route-control step before returning to larger midpoint movement
  or HLE/GPU dry-runs.

## 2026-05-25 - CPU4 Loader-Control Left200 VisualGate Attempt

Purpose:

- Add one small state-aware `left200` movement step after the clean no-movement
  loader/control reproof. This was still route-control validation under
  reservation-loop `Verify`, not a speed A/B, first-battle proof, or GPU
  migration proof.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label cpu4-loader-control-left200-visualgate-windows `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsCpuAffinityMask 0x0F `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -EternalSonataReservationLoop Verify `
  -WindowsVisualGate CleanAfterField `
  -WindowsVisualGateFieldSeconds 160 `
  -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" `
  -MaxSeconds 205 `
  -ScreenshotEverySeconds 10 `
  -ScreenshotStartSeconds 110 `
  -ScreenshotMaxCount 10
```

Run:

- `debug-captures/windows-lab/20260525-082840-cpu4-loader-control-left200-visualgate-windows-windows`

Verification:

- The run stayed on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Host contention stayed clean/external-clean across all `6` snapshots.
- RPCS3 stayed alive until the planned `205s` cap and the harness stopped it.
  No lingering `rpcs3`/`rpcsx` process remained afterward.
- The sprint wrapper exited nonzero because `CleanAfterField` failed.
- Visual gate result: `NO_FIELD_LIKE_SCREENSHOT`; first screenshot
  `screenshot-0117s.png` was `wrong-window-or-other-small-png` (`895,769`
  bytes), and the remaining `13` screenshots were byte-classed
  `black-overlay-small-png` at `37,848` bytes.
- Manual review shows this was not Path to Tenuto field: `screenshot-0117s.png`
  is a blue/starry story or cutscene-like camera, and `screenshot-0135s.png`
  onward is the same mostly starry sky view. The route missed field before the
  `left200` pulse, so this is not a left200 movement boundary.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were empty.
- Targeted fatal scan found only `Stub PPU Traps: 0`; it found no
  `Unimplemented FP CAL instruction`, guest `unknown draw command`, access
  violation, SIGSEGV/SIGBUS, `VK_ERROR`, verification failure, likely-crashed
  hit, fatal, or assertion.
- Window-title samples reported `44.84` FPS at the first nonfield screenshot
  and `27.00` FPS after the route settled into the starry view. These are
  invalid route-mismatch samples and are not speed evidence.

Counters:

- GPU candidate probe records: `1,683`; total observed DMA bytes:
  `2,646.01 MB`.
- MFC dynamic records: `1,683`; MFC list-transfer records: `565`; MFC wait
  records: `1,741`; MFC wait exact-PC records: `98,992`.
- Reservation-loop command records: `1,741`; command exact-PC records:
  `48,731`; verify records: `6,390`; RDCH join records: `3`; lane-join
  records: `3`; raw-lane records: `8`.
- Offload fit mix: `spu-kernel-hle=1,394` records / `2,495.99 MB`,
  `too-small=289` records / `150.01 MB`.
- Group totals: `CellSpursKernelGroup=1,102` records / `1,807.21 MB`,
  `TCX_CellSpursKernelGroup=581` records / `838.80 MB`.
- Hot PCs: `0x25cc=1,102` records / `1,807.21 MB`,
  `0x451c=581` records / `838.80 MB`.
- RSX-local traffic records remain `0`; indirect RSX overlap remains `0`.

Reading:

- This run invalidated the specific `loader-control-left200` route shape, but
  it did not test field movement. The route was already in a nonfield
  story/cutscene view at the pre-movement screenshot.
- The byte-size visual gate calls most later frames black-overlay-small, but
  manual review shows a starry nonfield view. Treat this as
  `failed-cutscene-or-nonfield-visual` / route mismatch, not black-overlay
  speed evidence.
- No first-battle, speed, or GPU migration evidence. Repeated zero RSX-local
  records still keep broad SPU-to-Vulkan compute parked.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` now blocks automatic
  `loader-control-left200` reruns after the clean no-movement boundary and
  recommends route-control repair, smaller/changed movement, or focused SPU
  kernel HLE/codegen/verifier analysis.

Classification:

- `failed-cutscene-or-nonfield-visual`, `loader-control-left200-route-miss`,
  not `valid-field-triage`, not `valid-battle-triage`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Do not auto-rerun `loader-control-left200`. Add/use route-state visual
  detection for the starry/cutscene miss, shrink/change the route pulse only
  after the pre-movement field is proven, or switch to focused SPU kernel
  HLE/codegen/verifier analysis that does not depend on this movement route.

## 2026-05-25 - Visual Gate Small Blue Nonfield Classifier

Purpose:

- Fix the harness/refiner blind spot found in the `loader-control-left200`
  miss: the starry blue story/cutscene frames compressed into the old
  black-overlay byte window, so the refiner counted them as black-overlay
  instead of cutscene/nonfield route failure.
- This was a Windows-only harness improvement. No Android, ADB, Thor, speed
  A/B, first-battle, or GPU migration run was performed.

Changed:

- `tools/check_eternal_sonata_windows_visual_gate.ps1` now samples color for
  all screenshots, not only field-sized screenshots, and classifies
  blue-dominant low-green frames as `cutscene-or-nonfield-small-png` when
  they fall below the field byte threshold.
- `tools/ps3_harness_refiner.ps1` now mirrors that small blue nonfield class,
  treats it as `failed-cutscene-or-nonfield-visual`, preserves Options/menu
  proof handling for expected small menu screenshots, and avoids auto-emitting
  another loader-control movement command when the latest failed movement is
  already a cutscene/nonfield route miss after a clean lower boundary.
- `.agents/skills/ps3-continual-harness-refiner/SKILL.md` now records the
  small blue/starry nonfield rule.

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was attached.
- PowerShell parser checks passed for both updated scripts:
  `check_eternal_sonata_windows_visual_gate.ps1` and
  `ps3_harness_refiner.ps1`.
- Re-running the visual gate on
  `debug-captures/windows-lab/20260525-082840-cpu4-loader-control-left200-visualgate-windows-windows`
  still fails correctly with `NO_FIELD_LIKE_SCREENSHOT`, no first field-like
  screenshot, and expected gate failures for no field by `160s`.
- The same left200 run now reports class counts
  `cutscene-or-nonfield-small-png=14` and `black-overlay-small-png=0`. The
  first large-ish story frame is now `cutscene-or-nonfield-small-png`
  (`895,769` bytes, Avg RGB `24.8/41/85.6`, ratios
  `G/B/R/D=0.058/0.667/0.03/0.546`), and the repeated starry frames are
  `cutscene-or-nonfield-small-png` (`37,848` bytes, Avg RGB
  `19.4/28.1/88.6`, ratios `0/0.9/0.007/0.884`).
- A known true black-overlay screenshot copied from
  `20260525-080652-hle-451c-preserve-body-off-battle-topslot-route-state-gate-after-left1200-reproof-windows`
  still classifies as `black-overlay-small-png` (`35,878` bytes, Avg RGB
  `19.7/19.7/19.5`, ratios `0/0/0.007/0.884`).
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` now shows the latest
  left200 run with primary small class `cutscene-or-nonfield-small-png` and
  decision `failed-cutscene-or-nonfield-visual`. Its recommended command is a
  comment, not a rerun: no automatic loader-control movement rerun; repair
  route-state detection, shrink/change the pulse after pre-movement field
  proof, or switch to SPU kernel HLE/codegen/verifier analysis.

Classification:

- `harness-improvement`, `visual-gate-classifier-repair`,
  `refiner-route-loop-guard`, not `valid-field-triage`, not
  `valid-battle-triage`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Use the improved visual/refiner classification before any next route run.
  Do not auto-rerun `loader-control-left200`; either repair route-state
  detection/shrink the movement after pre-movement field proof, or switch to a
  focused SPU kernel HLE/codegen/verifier analysis step.

## 2026-05-25 - SPU HLE Candidate Atlas Refresh

Purpose:

- Follow the refiner's non-route option after the `loader-control-left200`
  cutscene/nonfield miss: refresh the valid-field SPU HLE/codegen candidate
  ranking and the existing `0x451c` contract before doing any more movement
  reruns.
- This was Windows-only analysis from existing captures. No Android, ADB,
  Thor, speed A/B, first-battle, or GPU migration run was performed.

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 12 -Top 12
.\tools\summarize_eternal_sonata_451c_contract.ps1 -MaxRuns 20 -Top 12
```

Artifacts:

- `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.md`
- `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.csv`
- `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.md`
- `debug-captures/windows-lab/_eternal-sonata-451c-contract-latest.csv`

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was attached.
- Refiner status still blocks automatic `loader-control-left200` reruns after
  the latest nonfield/cutscene route miss and points to route-state repair,
  changed/smaller pulse after pre-movement field proof, or focused SPU
  HLE/codegen/verifier analysis.
- Latest clean loader/control field proof
  `20260525-081533-cpu4-loader-control-visualgate-windows-windows` still has
  visual status `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `10` field-like-large screenshots, `0`
  invalid screenshots after first field, and `passed-for-triage`.
- Targeted fatal scan of that latest clean field proof found no access
  violation, unhandled exception, SIGSEGV/SIGBUS, likely crash, unknown STOP,
  assertion, device lost, or verification-failure lines.
- Candidate atlas used `6` valid field runs and excluded `0` field-like runs
  for fatal logs.
- `0x451c` contract scout used `9` valid fatal-clean field runs and skipped
  `0` fatal-clean field runs.

Counter Reading:

- Top stable SPU HLE/codegen bucket is now `PC 0x25cc`,
  `CellSpursKernelGroup` / `CellSpursKernel0`, image
  `0x958dfe208b686622`: `5.65 GB` over `3,552` records across `6` valid
  field runs, `847.33 MB` GET, `4.82 GB` PUT, `0 B` list GET, `0 B` RSX,
  max job `4.58 MB`, `133` pattern signatures, and `1` max-DMA EA value.
- `0x451c` remains a strong codegen/list-control target but not a copy-elision
  or GPU target yet: dynamic MFC `0x451c` hits `1,341,997`, bytes observed
  `1.17 GB`; list-transfer calls `547,135`, descriptor bytes `8.49 MB`;
  top runtime-cost lane `small-list-control` was `764.932 ms`,
  `900,196` hits, `803.13 MB`, `548` descriptors.
- Current `0x451c` top-two predicate coverage remains too narrow:
  `45,680` hits (`5.07%`) and `63.718 ms` (`8.33%`) of the broad dynamic
  `0x46` list-control lane.
- Existing `0x451c` shadow verifier blocks copy-elision: `14,024` hits,
  `3.42 MB` shadowed, `768` output mismatches, `14,024` destination changes,
  `0` skip hits. Future `0x451c` paths must preserve DMA ordering/data
  movement or reduce descriptor/codegen overhead.
- No candidate in the valid field set has RSX-local bytes. Broad
  SPU-to-Vulkan compute remains parked; this is SPU HLE/codegen/verifier work,
  not GPU migration credit.

Classification:

- `analysis`, `spu-hle-codegen-target-refresh`, not `valid-battle-triage`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate
  candidate.

Next:

- Prefer a verify-only `0x25cc` recognizer/contract next: gate on
  `BLUS30161`, SPU image `0x958dfe208b686622`, `CellSpursKernelGroup`,
  `CellSpursKernel0`, and PC `0x25cc`; record MFC descriptors plus touched
  GET/PUT ranges, run the stock path, compare candidate result, and keep fast
  mode off until field/menu/first-battle visuals survive.
- Keep `0x451c` fast/copy-elision parked until the descriptor family
  recognizer is broader or a codegen specialization can reduce list/control
  overhead without changing DMA order.

## 2026-05-25 - 0x25cc Exact-Skip Coverage Gap

Purpose:

- Convert the existing `0x25cc` title-CSV Verify/Skip evidence into a
  repeatable coverage artifact, so the clean exact guarded skip is not
  accidentally re-promoted as a speed or GPU-offload win.
- This was Windows-only analysis from existing captures. No Android, ADB,
  Thor, emulator rerun, speed A/B, first-battle rerun, or GPU migration run
  was performed.

Changed:

- Added `tools/summarize_eternal_sonata_25cc_coverage.ps1`.

Commands:

```powershell
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_25cc_coverage.ps1), [ref]$tokens, [ref]$errors) | Out-Null
.\tools\summarize_eternal_sonata_25cc_coverage.ps1
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

Artifacts:

- `debug-captures/windows-lab/_eternal-sonata-25cc-coverage-latest.md`
- `debug-captures/windows-lab/_eternal-sonata-25cc-coverage-latest.csv`

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was
  attached.
- PowerShell parser check passed for the new summarizer.
- The summarizer read the existing title-CSV pair
  `20260524-125346-hle-shadow-verify-titlecsv-uncap240-field-windows-windows`
  and
  `20260524-125942-hle-shadow-skip-titlecsv-uncap240-field-windows-windows`,
  plus the latest
  `debug-captures/windows-lab/_eternal-sonata-spu-hle-candidates-latest.csv`
  atlas.
- Refiner still blocks automatic `loader-control-left200` reruns after the
  latest nonfield/cutscene route miss and recommends route repair or focused
  SPU HLE/codegen/verifier analysis.

Counter Reading:

- Latest atlas `0x25cc` bucket:
  `PC 0x25cc`, image `0x958dfe208b686622`,
  `CellSpursKernelGroup` / `CellSpursKernel0`, `3,552` records across `6`
  valid field runs, `5.65 GB`, and `0 B` RSX-local.
- Title-CSV Verify run: hot `0x25cc` total `501.28 MB` over `312` records,
  top EA `0x9e4000`; exact verifier shape
  `pc=0x25cc`, `cmd=0x40`, tag `31`, size `16384`,
  `lsa=0x3b000`, `eal=0xa1c000` covered `72.89 MB` / `4,665` hits
  (`14.54%` of hot `0x25cc`). Shadow bytes were `4.86 MB`, with
  `0` mismatches and `0` destination changes.
- Title-CSV Skip run: hot `0x25cc` total `573.70 MB` over `356` records,
  top EA `0x9e4000`; exact verifier shape covered `83.20 MB` / `5,325`
  hits (`14.50%` of hot `0x25cc`). Actual guarded skip removed only
  `5.55 MB`, with `0` mismatches, `0` destination changes, and `0` skip
  misses.
- The exact skip's `5.55 MB` is only `0.97%` of that run's total hot
  `0x25cc` bytes, `6.67%` of exact verifier-shape bytes, and about `0.10%`
  of the refreshed `5.65 GB` atlas bucket.
- Title-CSV speed evidence remains unfavorable to Skip: Verify averaged
  `116.57 FPS`, while Skip averaged `111.33 FPS` in the generated artifact.

Reading:

- The exact `0xa1c000` guarded skip is still a correctness-clean CPU/SPU HLE
  proof, but it is too narrow to explain or produce a useful speed gain.
- The main hot `0x25cc` traffic points at top EA `0x9e4000`, not the exact
  `lsa=0x3b000` / `eal=0xa1c000` redundant-copy shape.
- Do not rerun the exact `0xa1c000` skip expecting the 200% gate. Future
  `0x25cc` work should broaden verify-only coverage around the dynamic MFC /
  `0x9e4000` pattern families or codegen dispatch overhead.

Classification:

- `analysis`, `spu-hle-25cc-coverage-gap`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Either design a broader verify-only `0x25cc` recognizer around the
  `0x9e4000` pattern family, or stay with the current `0x451c`
  preserve-order/codegen lane. Keep broad SPU-to-Vulkan compute parked until
  a capture shows RSX-consumed data.

## 2026-05-25 - 0x25cc `0x9e4000` Pattern-Family Atlas

Purpose:

- Follow the exact-skip coverage gap with a broader `0x25cc` family analysis:
  identify the repeated hot `0x9e4000` EA/pattern family that the narrow
  `eal=0xa1c000` redundant-copy skip did not cover.
- This was Windows-only analysis from existing valid field captures. No
  Android, ADB, Thor, emulator rerun, speed A/B, first-battle rerun, fast
  mode, or GPU migration run was performed.

Changed:

- Added `tools/summarize_eternal_sonata_25cc_pattern_family.ps1`.

Commands:

```powershell
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_25cc_pattern_family.ps1), [ref]$tokens, [ref]$errors) | Out-Null
.\tools\summarize_eternal_sonata_25cc_pattern_family.ps1
```

Artifacts:

- `debug-captures/windows-lab/_eternal-sonata-25cc-pattern-family-latest.md`
- `debug-captures/windows-lab/_eternal-sonata-25cc-pattern-family-latest.csv`

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was
  attached.
- Read `AGENTS.md`, the repo-local PS3 skills, and this latest ledger before
  acting.
- PowerShell parser check passed for the new summarizer.
- The summarizer scanned the newest `12` Windows capture directories with
  GPU-probe CSVs, used `6` fatal-clean `FIELD_LIKE_PRESENT` field captures,
  and excluded `0` field-like runs for fatal logs.
- Scope was title `BLUS30161`, SPU image `0x958dfe208b686622`,
  `CellSpursKernelGroup` / `CellSpursKernel0`, PC `0x25cc`.

Counter Reading:

- Selected `0x25cc` traffic totaled `5.65 GB` across `2` EA buckets, with
  `0 B` RSX-local bytes.
- Top EA bucket: `0x9e4000`, `5.65 GB` over `3,552` records across `6`
  valid field runs, `133` pattern signatures, `847.33 MB` GET,
  `4.82 GB` PUT, `27,373.314 ms` summed duration, and max job `4.58 MB`.
- The only other EA bucket was `0x4f0b80`: `2.95 MB` over `6` records,
  also seen across `6` runs, not a speed target.
- Top repeated `0x9e4000` clusters all had max DMA size `16,384`, fit
  `spu-kernel-hle`, risk `tiny-dispatch-trap`, and `0 B` RSX-local.
  The largest stable clusters were:
  - pattern `0x4318b5fc803b855f`: `6` runs, `170` records,
    `259.78 MB`, `4.49%` of selected `0x25cc`, `1,627.173 ms`;
  - pattern `0xf7bf30bddad5855f`: `6` runs, `166` records,
    `253.66 MB`, `4.38%`, `1,890.973 ms`;
  - pattern `0x30540805202a855f`: `6` runs, `144` records,
    `220.05 MB`, `3.80%`, `1,248.654 ms`;
  - pattern `0x209c1716c9de855f`: `6` runs, `140` records,
    `213.93 MB`, `3.70%`, `1,541.564 ms`.
- Many large single-run clusters exist, but the stable multi-run family is
  enough for a verify-only `0x9e4000` recognizer design.

Reading:

- The broader `0x25cc` target is the repeated `0x9e4000` EA family, not the
  exact `lsa=0x3b000` / `eal=0xa1c000` redundant-copy skip.
- This still is not GPU migration: the family has `0 B` RSX-local bytes and
  no SPU-DMA/RSX-resource overlap evidence. Broad SPU-to-Vulkan compute stays
  parked.
- Next useful code work is verify-only logging under the existing
  `BLUS30161` / image / group / SPU / PC gate, narrowed to the `0x9e4000`
  family. Record command descriptors, source/destination hashes, touched
  GET/PUT ranges, and destination-change behavior before considering any
  HLE/codegen specialization.

Classification:

- `analysis`, `spu-hle-25cc-pattern-family`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate.

Next:

- Build a verify-only `0x25cc` `0x9e4000` runtime-family recognizer in the
  Windows `rpcs3-upstream` lab, or continue the current `0x451c`
  preserve-order/list-control codegen lane. Keep fast mode and Vulkan compute
  off until field/menu/first-battle correctness and counters justify it.

## 2026-05-25 - 0x25cc `0x9e4000` Runtime-Family Verifier Hook

Purpose:

- Convert the `0x25cc` `0x9e4000` pattern-family atlas into a verify-only
  Windows RPCS3 runtime counter hook, so the next clean field run can measure
  actual dynamic MFC coverage before any HLE/codegen body is attempted.
- This was Windows-only code and parser work. No Android, ADB, Thor,
  gameplay rerun, fast mode, skip mode, speed A/B, first-battle run, or GPU
  migration run was performed.

Changed:

- In `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`:
  - `rpcs3/Emu/Cell/SPUThread.h` adds `spu_hle_25cc_family_*` counters.
  - `rpcs3/Emu/Cell/SPUThread.cpp` adds a verify-only
    `BLUS30161` / image `0x958dfe208b686622` / PC `0x25cc` runtime-family
    recognizer for non-list 16 KB MFC GET/PUT traffic below RSX local memory,
    with buckets for EA `0x9e4000`, EA `0x4f0b80`, exact EA `0xa1c000`, and
    other matching EAs.
  - `rpcs3/Emu/Cell/lv2/sys_spu.cpp` logs
    `Eternal Sonata SPU HLE 25cc family verifier:` rows.
- In this Android/workflow repo:
  - `tools/summarize_eternal_sonata_gpu_probe.ps1` now parses and exports
    `eternal-sonata-spu-hle-25cc-family-profile.csv`, plus a Markdown summary
    section.

Commands:

```powershell
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_gpu_probe.ps1), [ref]$tokens, [ref]$errors) | Out-Null
# synthetic log parser smoke for the new 25cc-family row
cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was
  attached.
- Read `AGENTS.md`, the repo-local PS3 skills, and the latest ledger before
  acting.
- PowerShell parser check passed for
  `tools/summarize_eternal_sonata_gpu_probe.ps1`.
- Synthetic parser smoke parsed one
  `Eternal Sonata SPU HLE 25cc family verifier:` log row and confirmed
  `hits=12`, `ea9e4000_hits=10`, and `put_hits=9` in the emitted CSV and
  Markdown summary.
- `git diff --check` passed for the touched Windows RPCS3 files and the
  summarizer, with only existing LF/CRLF warnings.
- MSVC Release build passed:
  `build-msvc\bin\rpcs3.exe`.
- `ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` still blocks automatic
  `loader-control-left200` reruns and recommends focused SPU
  HLE/codegen/verifier work or route-state repair.

Counter Reading:

- No gameplay screenshots or real 25cc-family counters were generated in this
  step because the work was a compile/parser-verified hook, not a field run.
- The hook is intentionally counter-only under existing `Verify` mode. It
  does not skip DMA, does not change MFC ordering, does not offload SPU work
  to Vulkan, and does not run in default stock mode unless the existing
  Eternal Sonata HLE verifier is enabled.

Classification:

- `verify-only-hle-codegen-prep`, `spu-hle-25cc-runtime-family`, not
  `windows-micro-win`, not `gpu-migration-credit`, and not a 200% gate
  candidate.

Next:

- Run a clean Windows field proof with
  `-EternalSonataSpuHleVerify Verify -WindowsGameScreen 1`, then parse the
  new `eternal-sonata-spu-hle-25cc-family-profile.csv` alongside dynamic MFC,
  GPU-candidate, and visual/fatal gates. Keep fast mode and broad
  SPU-to-Vulkan compute off unless field/menu/first-battle proof and counters
  justify a narrowed HLE/codegen body.

## 2026-05-25 - 0x25cc Runtime-Family Field Measurement

Purpose:

- Field-measure the new verify-only `0x25cc` runtime-family hook on Windows
  with RPCS3 gameplay kept on screen 1, so the broader `0x25cc` HLE/codegen
  target has real dynamic MFC counters instead of only offline atlas data.
- This was Windows-only. No Android, ADB, Thor, fast mode, skip mode, speed
  A/B, menu/Options proof, first-battle proof, or GPU migration run was
  performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-25cc-family-verify-nomove -WindowsInputBackend PadApi -EternalSonataSpuHleVerify Verify -WindowsGameScreen 1 -MaxSeconds 200 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 15 -ScreenshotMaxCount 14 -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -WindowsHostContentionGate ExternalFail
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows`
- Visual gate:
  `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-windows-visual-gate-summary.md`
- GPU/HLE summary:
  `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-gpu-probe-summary.md`
- New family CSV:
  `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-spu-hle-25cc-family-profile.csv`

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was
  attached.
- Read `AGENTS.md` and this latest ledger before acting.
- The run used `build-msvc\bin\rpcs3.exe`, `--no-gui --game-screen 1`, and
  moved the game window to `\\.\DISPLAY2`.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0118s.png` at `118s`, `15` field-like screenshots, and `0`
  invalid screenshots after first field-like.
- Manual screenshot check of `screenshot-0150s.png` showed correct Path to
  Tenuto moving-field gameplay with normal characters, terrain, foliage, and
  overlay.
- Host contention stayed clean across `6` snapshots under
  `ExternalFail`.
- Focused fatal scan found no real access violation, device-lost, assertion,
  likely-crashed, or crash signatures. Earlier broad `Exception` matches were
  only benign `cellSpurs*ExceptionEventHandler` export names.
- Parser fix: `tools/summarize_eternal_sonata_gpu_probe.ps1` was corrected
  so the 25cc-family reading prints literal `` `0x9e4000` `` instead of a
  PowerShell backtick-NUL escape; parser check and `git diff --check` passed.

Counter Reading:

- New `0x25cc` family verifier:
  `798` rows, `23,928` hits, `23,928` success, `0` fail,
  `373.88 MB`, `60.637 ms`, max `72 us`.
- Direction split: `11,958` GET hits and `11,970` PUT hits.
- EA buckets at runtime command level:
  `1,595` EA `0x9e4000` hits, `1` EA `0x4f0b80` hit,
  `1,595` exact `0xa1c000` hits, and `20,737` other matching EA hits.
- Dynamic MFC fallback:
  `157,801` hits, `528.23 MB`, `106.650 ms`;
  PC `0x25cc` accounted for `25,525` dynamic hits / `61.282 ms`.
  The family hook therefore covers most `0x25cc` dynamic-command hits, but
  its command-level EAL distribution is broader than the offline atlas' top
  max-DMA EA bucket.
- GPU candidate summary still reports `0` direct RSX-local records,
  `0 B` RSX GET, `0 B` RSX PUT, and `0` indirect RSX overlap records.
- Window-title FPS was capped field proof, average `29.998 FPS`
  (`29.96` to `30.07`), so it is not a speed comparison.

Reading:

- The hook is valid and field-clean as target-sizing instrumentation.
- The runtime family is large enough to keep as an HLE/codegen candidate:
  it covers most observed `0x25cc` dynamic MFC hits in this field route.
- The command-level EAL buckets show that exact `0x9e4000` command matching
  alone would be too narrow; any next HLE/codegen body needs a broader
  descriptor or pattern-family gate, plus source/destination/hash semantics,
  before fast mode.
- This still is not GPU migration. The run repeated the `0 B` RSX-local /
  `0` overlap result, so broad SPU-to-Vulkan compute remains parked.

Classification:

- `valid-field-triage`, `spu-hle-25cc-runtime-family-sizing`,
  not `windows-micro-win`, not `gpu-migration-credit`, not a speed result,
  and not a 200% gate candidate.

Next:

- Keep the hook verify-only. Add a narrower analysis/pass that groups the
  `0x25cc` family by command-level EAL range or pattern/hash semantics, then
  require menu/Options and first-battle proof before any fast HLE/codegen
  body or speed A/B.

## 2026-05-25 - 0x25cc Runtime-Family Pattern Analysis Tool

Purpose:

- Add a narrow Windows-only post-run analysis pass for the clean
  `0x25cc` runtime-family field proof, so the next HLE/codegen verifier can
  target repeated pattern/descriptor semantics instead of exact command-level
  EA buckets.
- This was harness and analysis work only. No Android, ADB, Thor, gameplay
  rerun, fast mode, skip mode, speed A/B, menu/Options proof, first-battle
  proof, or GPU migration run was performed.

Changed:

- Added
  `tools/summarize_eternal_sonata_25cc_runtime_family.ps1`.
- The tool reads a Windows run's
  `eternal-sonata-spu-hle-25cc-family-profile.csv` and
  `eternal-sonata-gpu-probe-records.csv`, then writes:
  - `eternal-sonata-25cc-runtime-family-summary.md`
  - `eternal-sonata-25cc-runtime-family-patterns.csv`
  - `eternal-sonata-25cc-runtime-family-buckets.csv`

Commands:

```powershell
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_25cc_runtime_family.ps1), [ref]$tokens, [ref]$errors) | Out-Null
.\tools\summarize_eternal_sonata_25cc_runtime_family.ps1 -RunDir "debug-captures\windows-lab\20260525-093540-hle-25cc-family-verify-nomove-windows" -Top 15
git diff --check -- tools\summarize_eternal_sonata_25cc_runtime_family.ps1
```

Artifacts:

- `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-25cc-runtime-family-summary.md`
- `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-25cc-runtime-family-patterns.csv`
- `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-25cc-runtime-family-buckets.csv`

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was
  attached.
- Read `AGENTS.md`, the repo-local PS3 skills including
  `ps3-rsx-experiment-gate`, and the latest ledger before acting.
- PowerShell parser check passed for the new script.
- The script ran successfully on the clean field run
  `20260525-093540-hle-25cc-family-verify-nomove-windows`.
- `git diff --check` passed for the new script.

Counter Reading:

- Runtime hook buckets remained:
  `798` rows, `23,928` hits, `23,928` success, `0` fail,
  `373.88 MB`, `60.637 ms`, `2.534 us/hit`, max `72 us`.
- Command-level bucket split:
  `1,595` `ea9e4000` hits (`6.666%`, estimated `24.92 MB`),
  `1` `ea4f0b80` hit (`0.004%`),
  `1,595` `exact_a1c000` hits (`6.666%`), and
  `20,737` `other_matching_ea` hits (`86.664%`, estimated `324.02 MB`).
- The max-DMA pattern grouping found `798` `0x25cc` GPU-probe rows,
  `1.25 GB` total bytes, `0 B` direct RSX-local bytes, and
  `16` repeated `0x9e4000` HLE pattern-body candidate groups covering
  `775` records / `1.22 GB`.
- Top candidate groups were all `0x9e4000` with `0 B` RSX bytes:
  `0x1868eeff9c00f62b` (`62` records / `104.35 MB`),
  `0x7672495eee5c4b13` (`62` / `101.10 MB`),
  `0x6f472e2eac55f62b` (`60` / `100.98 MB`), and
  `0x30540805202a855f` (`65` / `99.33 MB`).

Reading:

- Exact command-level EA `0x9e4000` remains too narrow at only `6.666%`
  of runtime-family hits.
- The useful next gate is pattern-level or descriptor-level semantics over
  repeated `0x25cc` max-DMA pattern groups, especially `0x9e4000` groups
  with repeated 16 KB jobs.
- This remains CPU/SPU HLE/codegen sizing. Direct RSX-local traffic is
  still `0 B`, so there is no GPU migration credit and no reason to revive
  broad SPU-to-Vulkan compute yet.

Classification:

- `analysis-tooling`, `spu-hle-25cc-pattern-gate`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and
  not a 200% gate candidate.

Next:

- Keep the runtime-family hook verify-only. Add a verify-shadow or C++
  descriptor/hash semantics scout for the repeated `0x25cc` pattern groups
  before any fast HLE/codegen body. Menu/Options and first-battle proof are
  still required before speed A/B or any 200% claim.

## 2026-05-25 - 0x25cc Hash-Semantics Scout

Purpose:

- Extend the `0x25cc` runtime-family analysis so future verifier work does
  not over-trust placeholder hash fields when designing an HLE/codegen body.
- This was Windows-only harness analysis. No Android, ADB, Thor, gameplay
  rerun, fast mode, speed A/B, menu/Options proof, first-battle proof, or GPU
  migration run was performed.

Changed:

- `tools/summarize_eternal_sonata_25cc_runtime_family.ps1` now writes a
  hash-semantics CSV and summary section:
  `eternal-sonata-25cc-runtime-family-hash-semantics.csv`.
- The scout groups `0x25cc` GPU-probe rows by max-DMA EA, GET/PUT payload
  hash, sampled payload byte counts, LS start/end hashes, and block hashes.

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_25cc_runtime_family.ps1), [ref]$tokens, [ref]$errors) | Out-Null
.\tools\summarize_eternal_sonata_25cc_runtime_family.ps1 -RunDir "debug-captures\windows-lab\20260525-093540-hle-25cc-family-verify-nomove-windows" -Top 15
git diff --check -- tools\summarize_eternal_sonata_25cc_runtime_family.ps1
```

Artifacts:

- `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-25cc-runtime-family-summary.md`
- `debug-captures/windows-lab/20260525-093540-hle-25cc-family-verify-nomove-windows/eternal-sonata-25cc-runtime-family-hash-semantics.csv`

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `MSBuild`, `ninja`,
  `cl`, or `link` process was active, and no app terminal session was
  attached.
- Read `AGENTS.md`, the repo-local PS3 skills, and the latest ledger before
  acting.
- `ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite` still blocks automatic
  `loader-control-left200` and recommends SPU kernel HLE/codegen/verifier
  analysis because recent runs repeat `0 B` RSX-local and invalid movement
  branches.
- Parser check passed for the updated script.
- The script ran successfully on clean field run
  `20260525-093540-hle-25cc-family-verify-nomove-windows`.
- `git diff --check` passed for the updated script.

Counter Reading:

- The hash scout produced only `2` hash groups:
  - `0x9e4000`: `797` records, `32` pattern signatures, `1.25 GB`,
    GET hash `0x14650fb0739d0383`, PUT hash `0x14650fb0739d0383`,
    sampled GET/PUT payload bytes `0 B/0 B`, LS start/end `0x0/0x0`,
    block/max-DMA block `0x0/0x0`, reading
    `hash-instrumentation-gap`.
  - `0x4f0b80`: `1` record, `299.7 KB`, same payload hash pair and all
    sampled/LS/block hash fields zero, reading `hash-instrumentation-gap`.
- Rows with sampled payload bytes: `0`.
- Rows with nonzero LS/block hashes: `0`.
- Direct RSX-local traffic remains `0 B`.

Reading:

- The current GPU-probe hash fields are not sufficient source/destination
  semantics for a fast `0x25cc` body. The repeated `0x9e4000` pattern groups
  are real HLE/codegen candidates, but the next code step must add a
  verify-shadow runtime scout that hashes source, destination-before, and
  destination-after for those groups before changing behavior.
- This result prevents a bad shortcut: do not treat the uniform
  `0x14650fb0739d0383` GET/PUT pair as proof that the job is replay-safe or
  skip-safe.
- Still no GPU migration credit: `0 B` RSX-local and no SPU-DMA/RSX-resource
  overlap.

Classification:

- `analysis-tooling`, `spu-hle-25cc-hash-semantics-gap`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and
  not a 200% gate candidate.

Next:

- Add a verify-only C++ shadow scout in the Windows `rpcs3-upstream` lab for
  the repeated `0x25cc` pattern groups. It should log source,
  destination-before, and destination-after hashes under the existing
  BLUS30161/image/PC gate, then fall back to stock MFC behavior.

## 2026-05-25 - 0x25cc Verify-Shadow Hook

Purpose:

- Add the verify-only source/destination semantics scout required by the
  `0x25cc` runtime-family hash-semantics result before attempting any fast HLE
  body or GPU offload claim.
- This was Windows-only lab/tooling work. No Android, ADB, Thor, gameplay
  rerun, fast mode, speed A/B, menu/Options proof, first-battle proof, or GPU
  migration run was performed.

Changed:

- Windows `rpcs3-upstream`:
  - `rpcs3/Emu/Cell/SPUThread.h` now carries `0x25cc` shadow counters for
    hits, bytes, GET/PUT direction, EA buckets, repeat hashes, changed vs.
    unchanged destinations, and source/destination-before/destination-after
    hashes.
  - `rpcs3/Emu/Cell/SPUThread.cpp` now treats the `0x25cc` runtime family as a
    shadow candidate only when `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` or
    `25cc-shadow`, then records the extra source/destination hash sample while
    falling back to stock MFC behavior.
  - `rpcs3/Emu/Cell/lv2/sys_spu.cpp` now emits an
    `Eternal Sonata SPU HLE 25cc shadow verifier` log row.
- Workflow repo:
  - `tools/windows_rpcs3_lab.ps1` and
    `tools/eternal_sonata_speed_sprint.ps1` accept
    `-EternalSonataSpuHleVerify Verify25ccShadow`.
  - `tools/summarize_eternal_sonata_gpu_probe.ps1` parses/export the new
    `eternal-sonata-spu-hle-25cc-shadow-profile.csv` row family.

Commands:

```powershell
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\windows_rpcs3_lab.ps1), [ref]$tokens, [ref]$errors) | Out-Null
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\eternal_sonata_speed_sprint.ps1), [ref]$tokens, [ref]$errors) | Out-Null
$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\tools\summarize_eternal_sonata_gpu_probe.ps1), [ref]$tokens, [ref]$errors) | Out-Null
.\tools\summarize_eternal_sonata_gpu_probe.ps1 -RunDir "debug-captures\windows-lab\synthetic-25cc-shadow-parser-smoke" -Top 5
git diff --check -- tools\windows_rpcs3_lab.ps1 tools\eternal_sonata_speed_sprint.ps1 tools\summarize_eternal_sonata_gpu_probe.ps1 debug-experiments\20260518-cpu-spu-gpu-translation-research.md
cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6
git diff --check -- rpcs3\Emu\Cell\SPUThread.h rpcs3\Emu\Cell\SPUThread.cpp rpcs3\Emu\Cell\lv2\sys_spu.cpp
```

Artifacts:

- `debug-captures/windows-lab/synthetic-25cc-shadow-parser-smoke/eternal-sonata-spu-hle-25cc-shadow-profile.csv`

Verification:

- At heartbeat start, no `rpcs3`, `rpcsx`, `cmake`, `ninja`, `cl`, or `link`
  process was active. The visible `MSBuild.exe` processes were node-reuse
  workers left by the completed build, not an active gameplay/profiling run.
- Read `AGENTS.md`, the repo-local PS3 skills, and the latest ledger before
  acting.
- Parser checks passed for all touched PowerShell wrappers/tools.
- Synthetic parser smoke parsed the new log family and exported the expected
  values: `hits=4`, `ea9e4000_hits=3`, `last_src_hash=0x1111`, and
  `last_dst_post_hash=0x1111`.
- The Windows MSVC Release `rpcs3` target built successfully. The only noted
  build warning was the existing standard-library conflict warning
  `LNK4098`.
- `git diff --check` passed for the touched scripts and C++ files, with only
  line-ending normalization warnings in the touched Windows/PowerShell files.

Reading:

- This adds the missing runtime source/destination evidence channel for the
  repeated `0x25cc` groups. It does not change emulation behavior because the
  new mode shadows and logs before falling back to stock MFC behavior.
- This is HLE/codegen prep, not a speed win. It provides the next counter
  needed to determine whether repeated `0x25cc` jobs are replay-safe,
  output-stable, or suitable for a narrow fast body.
- Still no GPU migration credit: no gameplay rerun was performed and the prior
  valid field evidence remained `0 B` RSX-local traffic.

Classification:

- `verify-only-hle-codegen-prep`, `spu-hle-25cc-shadow-semantics`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Run a clean Windows field proof with
  `-EternalSonataSpuHleVerify Verify25ccShadow -WindowsGameScreen 1`, keeping
  fast/offload disabled. Parse the resulting
  `eternal-sonata-spu-hle-25cc-shadow-profile.csv` before any fast-body design.
  Menu/Options and first-battle proof are still required before speed A/B or
  any 200% claim.

## 2026-05-25 - Verify25ccShadow Field Proof

Purpose:

- Run the first real Windows field proof for the new `0x25cc` source /
  destination shadow scout, keeping emulation behavior stock and fast/offload
  paths disabled.
- This was Windows-only. No Android, ADB, Thor, menu/Options proof,
  first-battle proof, speed A/B, fast HLE body, or GPU offload was run.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-25cc-shadow-verify-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 190 -MaxSeconds 240 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 30 -ScreenshotMaxCount 12 -WindowsHostContentionGate Warn
```

Artifacts:

- `debug-captures/windows-lab/20260525-102628-hle-25cc-shadow-verify-field-windows`
- `debug-captures/windows-lab/20260525-102628-hle-25cc-shadow-verify-field-windows/eternal-sonata-windows-visual-gate-summary.md`
- `debug-captures/windows-lab/20260525-102628-hle-25cc-shadow-verify-field-windows/eternal-sonata-gpu-probe-summary.md`
- `debug-captures/windows-lab/20260525-102628-hle-25cc-shadow-verify-field-windows/eternal-sonata-spu-hle-25cc-shadow-profile.csv`
- `debug-captures/windows-lab/20260525-102628-hle-25cc-shadow-verify-field-windows/screenshots/screenshot-0117s.png`
- `debug-captures/windows-lab/20260525-102628-hle-25cc-shadow-verify-field-windows/screenshots/screenshot-0195s.png`

Verification:

- Pre-run guard found no active `rpcs3`, `rpcsx`, `cmake`, `ninja`, `cl`, or
  `link` process. Existing `MSBuild.exe` processes were idle node-reuse
  workers from the prior completed build.
- The run kept RPCS3 on `\\.\DISPLAY2` with `--game-screen 1` and PadApi input.
- Host contention stayed clean for all `8` snapshots; external contention was
  clean.
- Visual triage passed: `14` field-like screenshots, first field-like at
  `screenshot-0117s.png` (`117s`, `2.50 MB`), `0` invalid screenshots after
  first field-like, and field-like proof before the `190s` deadline.
- Manual screenshot inspection of `screenshot-0117s.png` and
  `screenshot-0195s.png` showed the expected Path to Tenuto field with no
  black overlay, loading screen, menu route miss, or obvious texture breakage.
- RPCS3 stdout/stderr were empty. Fatal scan found no real crash/access/assert
  hit; the only matched log text was the benign configuration line
  `Show fatal error hints: false`.
- The lab stopped RPCS3 at the planned `240s` wall-time limit after the field
  evidence was collected.

Counter Reading:

- GPU probe summary:
  - Total records: `1831`.
  - Total observed DMA: `2,265.95 MB`.
  - Offload fit mix: `spu-kernel-hle=1227`, `too-small=604`.
  - RSX-local traffic records: `0`.
  - Indirect RSX resource overlap records: `0`.
- `0x25cc` family verifier:
  - Rows: `892`.
  - Hits: `26763`, success/fail `26763/0`.
  - GET/PUT: `13368/13395`.
  - Bytes: `418.17 MB`.
  - Runtime timing: `1025.839 ms` total.
  - EA buckets: `ea9e4000=1784`, `ea4f0b80=1`,
    `exact_a1c000=1784`, `other=23194`.
- `0x25cc` shadow verifier:
  - Rows: `892`.
  - Hits: `13368`, all GET-side shadow copies.
  - Bytes: `208.88 MB`.
  - EA buckets: `ea9e4000=891`, `ea4f0b80=1`,
    `exact_a1c000=891`, `other=11585`.
  - Destination changed/unchanged: `894 / 12474`.
  - Output match/mismatch: `13368 / 0`.
  - Unique last source hashes: `892`.
  - Unique last destination-post hashes: `892`.

Reading:

- The `Verify25ccShadow` hook survived the field route and produced useful
  source/destination evidence with zero output mismatches. This validates the
  shadow scout as a real measurement channel for `0x25cc` semantics.
- The data says many repeated `0x25cc` GET copies are already output-stable in
  the field route, but it does not prove replay safety or a fast body yet. We
  still need menu/Options and first-battle shadow proof before using this as a
  correctness basis.
- The run provides no GPU migration credit: direct RSX-local traffic and
  indirect RSX overlap both remained `0`, so broad SPU-to-Vulkan compute stays
  parked.
- The run provides no speed credit: it was capped at PS3-native behavior,
  verify/logging was enabled, and there was no matched baseline/mutant A/B.

Classification:

- `valid-field-triage`, `spu-hle-25cc-shadow-semantics`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Run the same stock-behavior `Verify25ccShadow` path through title
  menu/Options proof on screen 1. If Options is clean, run first-battle proof.
  Only after field/menu/battle all have clean shadow evidence should a narrow
  `0x25cc` HLE/codegen body be designed or timed.

## 2026-05-25 - Verify25ccShadow Menu/Options Attempt

Purpose:

- Try to extend the stock-behavior `Verify25ccShadow` scout from clean field
  proof into the title menu/Options route, still with fast/offload paths
  disabled.
- This was Windows-only. No Android, ADB, Thor, first-battle proof, speed A/B,
  fast HLE body, or GPU offload was run.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label hle-25cc-shadow-verify-options -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -MaxSeconds 120 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 30 -ScreenshotMaxCount 18 -WindowsHostContentionGate Warn
```

Artifacts:

- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows`
- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows/windows-rpcs3-lab.txt`
- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows/eternal-sonata-gpu-probe-summary.md`
- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows/eternal-sonata-spu-hle-25cc-family-profile.csv`
- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows/eternal-sonata-spu-hle-25cc-shadow-profile.csv`
- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows/screenshots/screenshot-0091s.png`
- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows/screenshots/screenshot-0105s.png`
- `debug-captures/windows-lab/20260525-104117-hle-25cc-shadow-verify-options-windows/screenshots/screenshot-0115s.png`

Verification:

- Pre-run guard found no active `rpcs3`, `rpcsx`, `cmake`, `MSBuild`,
  `ninja`, `cl`, or `link` process.
- The run kept RPCS3 on `\\.\DISPLAY2` with `--game-screen 1` and PadApi input.
- Input macro:
  `wait:65000;shot:100;down:220;wait:800;shot:100;down:220;wait:800;shot:100;cross:240;wait:8000;shot:100;wait:6000;shot:100`.
- Host contention was mostly clean, but the final `sample-0120s` was
  `moderate` because host CPU reached `50%`. External contention stayed clean.
- RPCS3 stdout/stderr were empty. Fatal scan found no real crash/access/assert
  hit; the only matched log text was the benign configuration line
  `Show fatal error hints: false`.
- The lab stopped RPCS3 at the planned `120s` wall-time limit.

Visual Reading:

- `screenshot-0091s.png`, `screenshot-0105s.png`, and `screenshot-0110s.png`
  still showed the title menu with `OPTIONS` visible/selected at about `60 FPS`.
- `screenshot-0115s.png` showed a dark Options/loading-style background with
  the `Eternal Sonata` logo and no obvious corruption, but no stable Options
  controls/text before the run stopped.
- This is therefore only a partial Options-route attempt. It does not satisfy
  the full menu/Options proof gate yet.

Counter Reading:

- GPU probe summary:
  - Total records: `797`.
  - Total observed DMA: `1,109.03 MB`.
  - Offload fit mix: `spu-kernel-hle=585`, `too-small=212`.
  - RSX-local traffic records: `0`.
  - Indirect RSX resource overlap records: `0`.
- `0x25cc` family verifier:
  - Rows: `518`.
  - Hits: `15543`, success/fail `15543/0`.
  - GET/PUT: `7758/7785`.
  - Bytes: `242.86 MB`.
  - Runtime timing: `800.133 ms` total.
  - EA buckets: `ea9e4000=1036`, `ea4f0b80=1`,
    `exact_a1c000=1036`, `other=13470`.
- `0x25cc` shadow verifier:
  - Rows: `518`.
  - Hits: `7758`, all GET-side shadow copies.
  - Bytes: `121.22 MB`.
  - EA buckets: `ea9e4000=517`, `ea4f0b80=1`,
    `exact_a1c000=517`, `other=6723`.
  - Destination changed/unchanged: `520 / 7238`.
  - Output match/mismatch: `7758 / 0`.
  - Unique last source hashes: `518`.
  - Unique last destination-post hashes: `518`.

Reading:

- The `Verify25ccShadow` hook again produced clean source/destination evidence
  with zero output mismatches while the title menu route was active.
- The late transition at `115s` means the Options route is not yet stable enough
  to use as menu/Options proof for a future fast body or 200% gate.
- The run provides no GPU migration credit: direct RSX-local traffic and
  indirect RSX overlap both remained `0`.
- The run provides no speed credit: it was verify/logging stock behavior, had a
  moderate final host sample, and no matched baseline/mutant A/B.

Classification:

- `partial-options-route`, `spu-hle-25cc-shadow-semantics`, not
  `valid-options-proof`, not `windows-micro-win`, not `gpu-migration-credit`,
  not a speed result, and not a 200% gate candidate.

Next:

- Repair the title Options input macro or extend the post-cross wait so it
  captures stable Options controls/text on screen 1. Only after clean field,
  stable Options, and first-battle shadow evidence should a narrow `0x25cc`
  HLE/codegen fast body be designed or timed.

## 2026-05-25 - Verify25ccShadow Options Route Repair

Purpose:

- Re-run the `Verify25ccShadow` title Options proof with the previously proven
  title-route macro, after the default `Scene menu` macro only reached a late
  transition/loading-style frame.
- This was Windows-only. No Android, ADB, Thor, first-battle proof, speed A/B,
  fast HLE body, or GPU offload was run.

Command:

```powershell
$macro = 'wait:65000;cross:180;wait:9000;shot:100;down:220;wait:1000;shot:100;down:220;wait:16000;shot:100;cross:180;wait:8000;shot:100;wait:6000;shot:100'
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label hle-25cc-shadow-verify-options-route-repair -InputMacro $macro -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -MaxSeconds 130 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 75 -ScreenshotMaxCount 14 -WindowsHostContentionGate Fail
```

Artifacts:

- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows`
- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/windows-rpcs3-lab.txt`
- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/window-title-samples.csv`
- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/eternal-sonata-gpu-probe-records.csv`
- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/eternal-sonata-spu-hle-25cc-family-profile.csv`
- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/eternal-sonata-spu-hle-25cc-shadow-profile.csv`
- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/screenshots/screenshot-0105s.png`
- `debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/screenshots/screenshot-0130s.png`

Verification:

- Pre-run guard found no active `rpcs3`, `rpcsx`, `cmake`, `MSBuild`,
  `ninja`, `cl`, or `link` process.
- The run kept RPCS3 on `\\.\DISPLAY2` with `--game-screen 1` and PadApi input.
- Host contention stayed clean across all `5` snapshots with
  `-WindowsHostContentionGate Fail`; external contention was clean.
- Window-title samples on the Options page stayed at about `60 FPS`
  (`59.92` to `60.10` around the stable proof window). This is capped
  verify-mode behavior, not a speed claim.
- RPCS3 stdout/stderr were empty. Fatal scan found no real crash/access/assert
  hit; the only matched log text was the benign configuration line
  `Show fatal error hints: false`.
- The lab stopped RPCS3 at the planned `130s` wall-time limit. The outer
  Codex shell timeout interrupted post-run summarizer completion, so counters
  below were aggregated directly from the emitted CSVs.

Visual Reading:

- `screenshot-0105s.png` showed the full title Options page with Battle
  Camera, Attack Button, Vibration, Volume, Subtitles, Voice, and Language
  controls visible.
- `screenshot-0130s.png` showed the same stable full title Options page, still
  clean at the run end.
- No black overlay, loading-only screen, wrong-window capture, or obvious menu
  texture/lighting corruption was seen in the inspected Options screenshots.

Counter Reading:

- GPU probe CSV:
  - Records: `868`.
  - Total observed DMA: `1,043.56 MB`.
  - Offload fit mix: `spu-kernel-hle=619`, `too-small=249`.
  - RSX-local traffic records: `0`; RSX GET/PUT bytes were both `0`.
- `0x25cc` family verifier:
  - Rows: `561`.
  - Hits: `16818`, success/fail `16818/0`.
  - GET/PUT: `8403/8415`.
  - Bytes: `262.78 MB`.
  - Runtime timing: `643.270 ms` total.
  - EA buckets: `ea9e4000=1121`, `ea4f0b80=1`,
    `exact_a1c000=1121`, `other=14575`.
- `0x25cc` shadow verifier:
  - Rows: `561`.
  - Hits: `8403`, all GET-side shadow copies.
  - Bytes: `131.30 MB`.
  - EA buckets: `ea9e4000=560`, `ea4f0b80=1`,
    `exact_a1c000=560`, `other=7282`.
  - Destination changed/unchanged: `563 / 7840`.
  - Output match/mismatch: `8403 / 0`.
  - Unique last source hashes: `561`.
  - Unique last destination-post hashes: `561`.

Reading:

- The repaired title-route macro restores clean, stable full Options proof for
  `Verify25ccShadow`.
- The shadow scout again produced useful source/destination evidence with zero
  output mismatches on the title Options page.
- The run provides no GPU migration credit: direct RSX-local traffic remained
  `0`.
- The run provides no speed credit: it was capped stock behavior with
  verify/logging enabled and no matched baseline/mutant A/B.

Classification:

- `valid-options-triage`, `spu-hle-25cc-shadow-semantics`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Run the same stock-behavior `Verify25ccShadow` path through first-battle
  proof on screen 1. Field and stable Options now have clean shadow evidence;
  first-battle shadow proof is still required before any narrow `0x25cc`
  HLE/codegen body or A/B timing.

## 2026-05-25 - Verify25ccShadow First-Battle Proof

Purpose:

- Complete the stock-behavior `Verify25ccShadow` correctness sweep by running
  the same verifier through the first-battle route after clean field and stable
  title Options proof.
- This was Windows-only. No Android, ADB, Thor, speed A/B, fast HLE body, or
  GPU offload was run.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-shadow-verify-battle -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -MaxSeconds 330 -ScreenshotEverySeconds 30 -ScreenshotStartSeconds 220 -ScreenshotMaxCount 8 -WindowsHostContentionGate Fail
```

Artifacts:

- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/windows-rpcs3-lab.txt`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/window-title-samples.csv`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/eternal-sonata-gpu-probe-summary.md`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/eternal-sonata-spu-hle-25cc-family-profile.csv`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/eternal-sonata-spu-hle-25cc-shadow-profile.csv`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/screenshots/screenshot-0244s.png`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/screenshots/screenshot-0310s.png`

Verification:

- Pre-run guard found no active `rpcs3`, `rpcsx`, `cmake`, `MSBuild`,
  `ninja`, `cl`, or `link` process.
- The run kept RPCS3 on `\\.\DISPLAY2` with `--game-screen 1` and PadApi input.
- Host contention stayed clean across all `5` snapshots with
  `-WindowsHostContentionGate Fail`; external contention was clean.
- `window-title-samples.csv` showed the first-battle route capped around
  `30 FPS` from `screenshot-0244s.png` through `screenshot-0310s.png`.
  This is capped verify-mode behavior, not a speed claim.
- RPCS3 stdout/stderr were empty. Fatal scan found no real crash/access/assert
  hit; the only matched log text was the benign configuration line
  `Show fatal error hints: false`.
- The lab stopped RPCS3 at the planned `330s` wall-time limit.

Visual Reading:

- `screenshot-0244s.png` showed active first-battle UI with Polka, HP/turn UI,
  command ring, and battle field visible.
- `screenshot-0310s.png` showed the same active first-battle state still clean
  near the end of the route.
- No black overlay, loading-only screen, wrong-window capture, crash dialog, or
  obvious battle texture/lighting corruption was seen in the inspected battle
  screenshots.

Counter Reading:

- GPU probe summary:
  - Total records: `2598`.
  - Total observed DMA: `3,696.18 MB`.
  - Offload fit mix: `spu-kernel-hle=2104`, `too-small=494`.
  - RSX-local traffic records: `0`.
  - Indirect RSX resource overlap records: `0`.
- `0x25cc` family verifier:
  - Rows: `1564`.
  - Hits: `46923`, success/fail `46923/0`.
  - GET/PUT: `23448/23475`.
  - Bytes: `733.17 MB`.
  - EA buckets: `ea9e4000=3128`, `ea4f0b80=1`,
    `exact_a1c000=3128`, `other=40666`.
- `0x25cc` shadow verifier:
  - Rows: `1564`.
  - Hits: `23448`, all GET-side shadow copies.
  - Bytes: `366.38 MB`.
  - EA buckets: `ea9e4000=1563`, `ea4f0b80=1`,
    `exact_a1c000=1563`, `other=20321`.
  - Destination changed/unchanged: `1566 / 21882`.
  - Output match/mismatch: `23448 / 0`.
  - Unique last source hashes: `1564`.
  - Unique last destination-post hashes: `1564`.
- The broader legacy `SPU HLE Shadow Verifier` section also saw `0x451c`
  shape mismatches (`1200`), so this run should be used as `0x25cc` shadow
  proof only, not as new proof for the older 0x451c/exact-copy skip contract.

Reading:

- `Verify25ccShadow` now has clean source/destination shadow evidence with
  zero `0x25cc` mismatches across field, stable title Options, and first
  battle.
- This completes the verify-only correctness sweep needed before designing a
  narrow `0x25cc` HLE/codegen fast body.
- The run provides no GPU migration credit: direct RSX-local traffic and
  indirect RSX overlap both remained `0`.
- The run provides no speed credit: it was capped stock behavior with
  verify/logging enabled and no matched baseline/mutant A/B.

Classification:

- `valid-first-battle-triage`, `spu-hle-25cc-shadow-semantics`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Design the first narrow `0x25cc` HLE/codegen fast-body experiment behind an
  opt-in switch, using only the field/Options/battle-proven title/image/PC/
  tag/size/EA/LSA family. Keep broad SPU-to-Vulkan compute parked until a trace
  shows RSX-consumed data.

## 2026-05-25 - 0x25cc Runtime-Family Harness Refresh

Purpose:

- Convert the completed `Verify25ccShadow` field/Options/battle sweep into a
  safer fast-body preflight artifact before editing the emulator fast path.
- This was Windows-only analysis/harness work. No Android, ADB, Thor, new RPCS3
  gameplay run, GPU offload, or speed A/B was run.

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
.\tools\summarize_eternal_sonata_25cc_runtime_family.ps1 -RunDir .\debug-captures\windows-lab\20260525-110806-hle-25cc-shadow-verify-battle-windows
.\tools\summarize_eternal_sonata_25cc_pattern_family.ps1 -MaxRuns 12 -Top 12
```

Artifacts:

- `tools/summarize_eternal_sonata_25cc_runtime_family.ps1`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/eternal-sonata-25cc-runtime-family-summary.md`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/eternal-sonata-25cc-runtime-family-patterns.csv`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/eternal-sonata-25cc-runtime-family-buckets.csv`
- `debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows/eternal-sonata-25cc-runtime-family-hash-semantics.csv`
- `debug-captures/windows-lab/_eternal-sonata-25cc-pattern-family-latest.md`
- `debug-captures/windows-lab/_eternal-sonata-25cc-pattern-family-latest.csv`

Verification:

- Pre-work guard found no active `rpcs3`, `rpcsx`, `cmake`, `MSBuild`,
  `ninja`, `cl`, or `link` process.
- Re-opened existing proof screenshots for the three required visuals:
  - `20260525-102628-hle-25cc-shadow-verify-field-windows/screenshots/screenshot-0117s.png`
    shows the correct Path to Tenuto field.
  - `20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/screenshots/screenshot-0130s.png`
    shows the full title Options page.
  - `20260525-110806-hle-25cc-shadow-verify-battle-windows/screenshots/screenshot-0310s.png`
    shows active first-battle UI.
- The runtime-family summarizer now reads
  `eternal-sonata-spu-hle-25cc-shadow-profile.csv` when present and includes a
  `0x25cc Shadow Semantics` section instead of still saying a generic shadow
  scout is missing.
- The refreshed first-battle runtime summary reports `1564` shadow rows,
  `23448` hits, `366.38 MB`, GET=`23448`, PUT=`0`,
  destination changed/unchanged `1566/21882`, and output match/mismatch
  `23448/0`.
- The refreshed pattern-family summary across recent valid field-like runs
  reports selected `0x25cc` traffic of `5.94 GB`, top EA bucket `0x9e4000`,
  `95` patterns, `17,777.037 ms`, and `0 B` RSX-local bytes.

Reading:

- The analysis artifact now matches the newest evidence: 0x25cc shadow
  semantics exist and are clean for the inspected first-battle proof, so the
  next useful step is a narrow opt-in fast-body/codegen design rather than yet
  another generic source/destination scout.
- The broad target remains the repeated `0x9e4000` family and pattern-level
  descriptor/body behavior, not the earlier exact `eal=0xa1c000` redundant-copy
  skip.
- Direct RSX-local traffic is still `0 B`, so this is CPU/SPU HLE/codegen
  sizing, not GPU migration credit.

Classification:

- `harness-improvement`, `spu-hle-25cc-fastbody-preflight`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Design the opt-in `0x25cc` body experiment around the repeated `0x9e4000`
  descriptor/pattern family with the existing title/image/PC/tag/size gates,
  and keep it off by default until field, Options, first-battle, and matched
  A/B proof exist.

## 2026-05-25 - 0x25cc Body Gate Synthesis

Purpose:

- Synthesize the latest field, stable title Options, and first-battle
  `Verify25ccShadow` counters into a go/no-go check for the next opt-in
  `0x25cc` body scaffold.
- This was Windows-only analysis. No Android, ADB, Thor, new RPCS3 gameplay
  run, GPU offload, fast body, or speed A/B was run.

Command:

```powershell
$runs = @(
  @{scene='field'; dir='debug-captures/windows-lab/20260525-102628-hle-25cc-shadow-verify-field-windows'},
  @{scene='options'; dir='debug-captures/windows-lab/20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows'},
  @{scene='battle'; dir='debug-captures/windows-lab/20260525-110806-hle-25cc-shadow-verify-battle-windows'}
)
# Import each run's eternal-sonata-spu-hle-25cc-*.csv and gpu-probe records,
# then aggregate family fail, shadow mismatch, destination-change, and RSX bytes.
```

Verification:

- Pre-work guard found no active `rpcs3`, `rpcsx`, `cmake`, `MSBuild`,
  `ninja`, `cl`, or `link` process.
- Re-opened the existing proof screenshots:
  - field: `20260525-102628-hle-25cc-shadow-verify-field-windows/screenshots/screenshot-0117s.png`
  - Options: `20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows/screenshots/screenshot-0130s.png`
  - first battle: `20260525-110806-hle-25cc-shadow-verify-battle-windows/screenshots/screenshot-0310s.png`
- All three visuals were still the correct scene targets with no obvious black
  overlay, wrong-window capture, or visible texture/lighting corruption.

Counter Reading:

- Field:
  - Family rows/hits/fail: `892 / 26763 / 0`.
  - Shadow rows/hits/mismatch: `892 / 13368 / 0`.
  - Destination changed/unchanged: `894 / 12474`.
  - RSX-local bytes from `0x25cc` GPU-probe rows: `0`.
- Stable title Options:
  - Family rows/hits/fail: `561 / 16818 / 0`.
  - Shadow rows/hits/mismatch: `561 / 8403 / 0`.
  - Destination changed/unchanged: `563 / 7840`.
  - RSX-local bytes from `0x25cc` GPU-probe rows: `0`.
- First battle:
  - Family rows/hits/fail: `1564 / 46923 / 0`.
  - Shadow rows/hits/mismatch: `1564 / 23448 / 0`.
  - Destination changed/unchanged: `1566 / 21882`.
  - RSX-local bytes from `0x25cc` GPU-probe rows: `0`.
- Aggregate gate line:
  - `body_scaffold_ready=True`
  - `copy_required=True`
  - `gpu_migration_ready=False`
  - total shadow destination-changed hits: `3023`
  - total `0x25cc` RSX-local bytes: `0`
- Top repeated pattern-family clusters remain `0x9e4000`, `max_dma_size=16384`,
  `spu-kernel-hle`, `tiny-dispatch-trap`, with the largest current cluster
  `0xf7bf30bddad5855f` covering `291.87 MB` across `5` valid runs.

Reading:

- The next code step may scaffold an opt-in `0x25cc` body experiment because
  field, Options, and first-battle all have zero family failures and zero
  shadow mismatches.
- It must not be a broad skip: `3023` verified shadow hits changed the
  destination, so the body still has to preserve the copy/update semantics.
- It must not be treated as GPU migration: the same aggregate gate found `0`
  RSX-local bytes for the `0x25cc` rows.

Classification:

- `analysis`, `spu-hle-25cc-body-scaffold-ready`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a speed result, and not a 200% gate candidate.

Next:

- Add a default-off `0x25cc` body scaffold with an explicit env/harness switch
  and verification counters, preserving copy semantics first. Only after a
  body-on run passes field, Options, and first-battle visuals should matched
  uncapped A/B timing begin.

## 2026-05-25 - Reusable 0x25cc Body Gate Summarizer

Purpose:

- Turn the ad hoc `0x25cc` body go/no-go aggregation into a reusable harness
  check that future agents can run before enabling any body-on path.
- This was Windows-only process/tooling work. No Android, ADB, Thor, new RPCS3
  gameplay run, GPU offload, fast body, or speed A/B was run.

Command:

```powershell
.\tools\summarize_eternal_sonata_25cc_body_gate.ps1
```

Artifacts:

- `tools/summarize_eternal_sonata_25cc_body_gate.ps1`
- `debug-captures/windows-lab/_eternal-sonata-25cc-body-gate-latest.md`
- `debug-captures/windows-lab/_eternal-sonata-25cc-body-gate-latest.csv`

Verification:

- Pre-work guard found no active `rpcs3`, `rpcsx`, `cmake`, `MSBuild`,
  `ninja`, `cl`, or `link` process.
- The new summarizer imports the three latest required proof runs:
  - field: `20260525-102628-hle-25cc-shadow-verify-field-windows`
  - Options: `20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows`
  - first battle: `20260525-110806-hle-25cc-shadow-verify-battle-windows`
- It writes both Markdown and CSV outputs under
  `debug-captures/windows-lab/`.

Counter Reading:

- Output gate line:
  - Body scaffold ready: `True`
  - Copy/update semantics required: `True`
  - GPU migration ready: `False`
- Scene rows:
  - field: family hits/fail `26763/0`, shadow hits/mismatch `13368/0`,
    destination changed/unchanged `894/12474`, `0x25cc` GPU bytes `1.41 GB`,
    RSX bytes `0 B`.
  - Options: family hits/fail `16818/0`, shadow hits/mismatch `8403/0`,
    destination changed/unchanged `563/7840`, `0x25cc` GPU bytes `870.86 MB`,
    RSX bytes `0 B`.
  - battle: family hits/fail `46923/0`, shadow hits/mismatch `23448/0`,
    destination changed/unchanged `1566/21882`, `0x25cc` GPU bytes `2.40 GB`,
    RSX bytes `0 B`.
- Aggregate:
  - Total shadow hits: `45219`.
  - Total shadow bytes: `706.55 MB`.
  - Total shadow mismatches: `0`.
  - Total destination-changed hits: `3023`.
  - Total `0x25cc` RSX-local bytes: `0 B`.

Reading:

- The body gate is now repeatable instead of hand-computed: field, title
  Options, and first battle all support a default-off `0x25cc` body scaffold.
- The result still forbids a broad skip because verified destination bytes do
  change.
- The result still provides no GPU migration credit because selected `0x25cc`
  RSX-local bytes remain `0 B`.

Classification:

- `harness-improvement`, `spu-hle-25cc-body-scaffold-ready`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Use the new body-gate summarizer as the preflight check while adding the
  default-off `0x25cc` body scaffold and parser support for body-on counters.

## 2026-05-25 - Default-Off 0x25cc GET Body Scaffold

Purpose:

- Add the next guarded Windows-only `0x25cc` CPU/SPU HLE body scaffold after
  the field, Options, and first-battle shadow gate proved zero mismatches.
- Keep it default-off and counter-first. This does not claim a speed win, GPU
  migration, or gameplay correctness for body-on mode.

Changed:

- `rpcs3-upstream/rpcs3/Emu/Cell/SPUThread.cpp`
  - Added `RPCS3_ES_SPU_HLE_25CC_BODY` as a default-off gate.
  - Added an opt-in `0x25cc` GET copy-body path for the verified title/image/PC
    runtime family. It performs the required copy, records counters, and still
    leaves PUT/update directions on the stock path.
- `rpcs3-upstream/rpcs3/Emu/Cell/SPUThread.h`
  - Added `spu_hle_25cc_body_*` counters.
- `rpcs3-upstream/rpcs3/Emu/Cell/lv2/sys_spu.cpp`
  - Added `Eternal Sonata SPU HLE 25cc body verifier:` log output.
- `tools/windows_rpcs3_lab.ps1`
  - Added `-EternalSonataSpuHle25ccBody Verify`, mapped to
    `RPCS3_ES_SPU_HLE_25CC_BODY=verify`.
- `tools/eternal_sonata_speed_sprint.ps1`
  - Passed the new body switch through the Windows scene wrapper.
- `tools/summarize_eternal_sonata_gpu_probe.ps1`
  - Parses `25cc body` rows, writes
    `eternal-sonata-spu-hle-25cc-body-profile.csv`, and adds a summary section.

Verification:

```powershell
cmake --build "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc" --config Release --target rpcs3 --parallel 6
.\tools\windows_rpcs3_lab.ps1 -Action Smoke -Label hle-25cc-body-param-smoke -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify
```

- Native Windows RPCS3 build passed and produced
  `rpcs3-upstream/build-msvc/bin/rpcs3.exe`.
- Parameter smoke run:
  `debug-captures/windows-lab/20260525-115715-hle-25cc-body-param-smoke`.
- Smoke run verified the new lab parameter and SPU image dump setup:
  `Eternal Sonata SPU HLE 0x25cc body: Verify`.
- Smoke summary parsed cleanly and reported `SPU HLE 0x25cc body records: 0`,
  as expected because no game scene was booted.
- `git diff --check` on the touched PowerShell and native files reported only
  line-ending warnings.

Reading:

- The scaffold is now buildable and measurable, but it is only a CPU-side GET
  copy-body replacement for part of the `0x25cc` runtime family.
- It is not a broad skip. PUT/update directions are explicitly left on the
  stock path because the shadow gate showed destination changes.
- It is not GPU migration credit because the proven `0x25cc` rows still have
  `0 B` RSX-local bytes and no RSX-consumed batch evidence.

Classification:

- `harness-improvement`, `spu-hle-25cc-body-scaffold-build-pass`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Run a Windows field `Verify25ccShadow + 25ccBody Verify` capture with
  `-WindowsGameScreen 1` and visual/fatal/counter checks. If field is clean,
  repeat title Options and first battle before any uncapped A/B timing.

## 2026-05-25 - 0x25cc GET Body Field Proof

Purpose:

- Run the first real Windows field capture with the default-off `0x25cc` GET
  body scaffold enabled in verify mode.
- This was Windows-only. No Android, ADB, Thor, GPU offload, menu/battle proof,
  or speed A/B was run.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-25cc-body-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate Fail -MaxSeconds 170 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-120819-hle-25cc-body-field-windows`.
- Summary:
  `debug-captures/windows-lab/20260525-120819-hle-25cc-body-field-windows/eternal-sonata-gpu-probe-summary.md`.
- Body CSV:
  `debug-captures/windows-lab/20260525-120819-hle-25cc-body-field-windows/eternal-sonata-spu-hle-25cc-body-profile.csv`.
- Visual gate:
  `debug-captures/windows-lab/20260525-120819-hle-25cc-body-field-windows/eternal-sonata-windows-visual-gate-summary.md`.

Verification:

- Active-work guard showed no active RPCS3/RPCSX/cmake/cl/link/ninja work;
  only idle MSBuild node-reuse processes with `0` CPU delta were present.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention gate passed: `Fail` gate, worst host grade `clean`, worst
  external grade `clean`, `5` snapshots.
- Visual triage passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `0` invalid screenshots after first field.
- Manual screenshot review of `screenshot-0117s.png`, `screenshot-0150s.png`,
  and `screenshot-0165s.png` showed the correct Path to Tenuto field with no
  obvious black overlay, wrong-window capture, or visible texture/lighting
  corruption.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- The outer Codex shell command timed out after post-run output, so the GPU
  probe summarizer and visual gate were run manually against the completed
  run directory.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `683`;
  - GET body hits: `10233`;
  - GET body bytes: `167657472` (`159.89 MB`);
  - PUT rejects left on stock path: `10260`;
  - timing: total `1.571 ms`, average `0.154 us/hit`, max `8 us`.
- `0x25cc` family verifier:
  - rows: `683`;
  - hits: `20493`;
  - fail: `0`;
  - bytes: `335757312` (`320.20 MB`).
- `0x25cc` shadow verifier:
  - rows: `683`;
  - hits: `10233`;
  - bytes: `167657472` (`159.89 MB`);
  - output mismatch: `0`;
  - destination changed/unchanged: `685 / 9548`.
- Selected `0x25cc` GPU probe rows still had `0` RSX-local GET/PUT bytes.
- Window title samples stayed near the capped field rate, about `30.00 FPS`;
  this run is correctness/counter proof only, not speed evidence.

Reading:

- The opt-in `0x25cc` GET body path survived field route, screenshots, fatal
  scan, host gate, and counters in verify mode.
- The body path is preserving copy/update semantics for GET work only; PUT
  directions were observed and rejected back to stock as intended.
- This is still CPU/SPU HLE/codegen work, not GPU migration: the selected
  `0x25cc` RSX-local bytes remain `0 B`.

Classification:

- `spu-hle-25cc-body-field-pass`, `field-correctness-proof`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Run the same `Verify25ccShadow + 25ccBody Verify` mode through title
  Options, then first battle. Only after field, Options, and first battle are
  visually/fatal/counter-clean should any uncapped A/B timing begin.

## 2026-05-25 - 0x25cc GET Body Options Route Miss

Purpose:

- Try the second correctness gate for the default-off `0x25cc` GET body
  scaffold: title menu/Options with `Verify25ccShadow + 25ccBody Verify`.
- This was Windows-only. No Android, ADB, Thor, GPU offload, first-battle
  body proof, or speed A/B was run.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label hle-25cc-body-options -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate Fail -MaxSeconds 120 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 60 -ScreenshotMaxCount 8
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-122302-hle-25cc-body-options-windows`.
- Summary:
  `debug-captures/windows-lab/20260525-122302-hle-25cc-body-options-windows/eternal-sonata-gpu-probe-summary.md`.
- Body CSV:
  `debug-captures/windows-lab/20260525-122302-hle-25cc-body-options-windows/eternal-sonata-spu-hle-25cc-body-profile.csv`.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before launch.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention gate passed: `Fail` gate, worst host grade `clean`, worst
  external grade `clean`, `6` snapshots.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- Manual screenshot review showed the route did not open the full title
  Options page:
  - `screenshot-0080s.png` and `screenshot-0090s.png` were still the title
    menu with `NEW GAME / LOAD / OPTIONS` visible.
  - `screenshot-0120s.png` had fallen into intro/cutscene playback.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `508`;
  - GET body hits: `7608`;
  - GET body bytes: `124649472` (`118.88 MB`);
  - PUT rejects left on stock path: `7635`;
  - timing: total `1.112 ms`, average `0.146 us/hit`, max `5 us`.
- `0x25cc` family verifier:
  - rows: `508`;
  - hits: `15243`;
  - fail: `0`;
  - bytes: `249741312` (`238.17 MB`).
- `0x25cc` shadow verifier:
  - rows: `508`;
  - hits: `7608`;
  - bytes: `124649472` (`118.88 MB`);
  - output mismatch: `0`;
  - destination changed/unchanged: `510 / 7098`.
- Selected `0x25cc` GPU probe rows still had `0` RSX-local GET/PUT bytes.
- Window title samples showed about `60 FPS` while on the title menu and about
  `30 FPS` once intro playback began; these are not Options proof and not speed
  evidence.

Reading:

- The counters remained clean, but the visual target was missed. This is not a
  valid title Options body proof.
- Do not use these counters to promote the `0x25cc` body path, because the run
  did not reach the required Options page.
- The result still provides no GPU migration credit because the selected
  `0x25cc` RSX-local bytes remain `0 B`.

Classification:

- `failed-menu-route-miss`, `not-comparable-options-proof`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Repair or state-gate the Windows title Options route for body-on verification
  before first-battle proof or any uncapped A/B timing. The body field proof
  remains valid, but Options remains unproven for body mode.

## 2026-05-25 - 0x25cc GET Body Options Route Repair Pass

Purpose:

- Re-run the default-off `0x25cc` GET body scaffold through the title Options
  gate using the known-good route-repair timing shape.
- This was Windows-only. No Android, ADB, Thor, GPU offload, first-battle
  body proof, or speed A/B was run.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label hle-25cc-body-options-route-repair -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate Fail -MaxSeconds 130 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 75 -ScreenshotMaxCount 14 -InputMacro "wait:65000;cross:180;wait:9000;shot:100;down:220;wait:1000;shot:100;down:220;wait:16000;shot:100;cross:180;wait:8000;shot:100;wait:6000;shot:100"
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-123316-hle-25cc-body-options-route-repair-windows`.
- Summary:
  `debug-captures/windows-lab/20260525-123316-hle-25cc-body-options-route-repair-windows/eternal-sonata-gpu-probe-summary.md`.
- Body CSV:
  `debug-captures/windows-lab/20260525-123316-hle-25cc-body-options-route-repair-windows/eternal-sonata-spu-hle-25cc-body-profile.csv`.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before launch.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention gate passed: `Fail` gate, worst host grade `clean`, worst
  external grade `clean`, `5` snapshots.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- Manual screenshot review confirmed the full title Options page stayed clean:
  - `screenshot-0104s.png`: full Options page immediately after opening.
  - `screenshot-0115s.png`: full Options page still stable.
  - `screenshot-0130s.png`: full Options page still stable at run end.
- No black overlay, wrong-window capture, or obvious menu corruption was visible.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `570`;
  - GET body hits: `8538`;
  - GET body bytes: `139886592` (`133.41 MB`);
  - PUT rejects left on stock path: `8565`;
  - timing: total `1.096 ms`, average about `0.128 us/hit`, max `11 us`.
- `0x25cc` family verifier:
  - rows: `570`;
  - hits: `17103`;
  - fail: `0`;
  - bytes: `280215552` (`267.23 MB`).
- `0x25cc` shadow verifier:
  - rows: `570`;
  - hits: `8538`;
  - bytes: `139886592` (`133.41 MB`);
  - output mismatch: `0`;
  - destination changed/unchanged: `572 / 7966`.
- Selected `0x25cc` GPU probe rows still had `0` RSX-local GET/PUT bytes.
- Window title samples stayed about `60 FPS` on the title Options page; this is
  route/correctness evidence only, not speed evidence.

Reading:

- The `0x25cc` body scaffold now has field and title Options
  visual/fatal/counter proof in verify mode.
- The repaired title Options timing works because it first settles/skips to the
  title menu with `cross`, then moves to Options, waits for selection to settle,
  and opens the full Options page.
- This still is CPU/SPU HLE/codegen work, not GPU migration: selected `0x25cc`
  RSX-local bytes remain `0 B`.

Classification:

- `spu-hle-25cc-body-options-pass`, `valid-options-proof`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Run `Verify25ccShadow + 25ccBody Verify` through first battle. If first battle
  is clean, update the default Windows menu macro to the repaired route shape
  before uncapped A/B timing.

## 2026-05-25 - 0x25cc GET Body First-Battle Proof

Purpose:

- Run the default-off `0x25cc` GET body scaffold through the first-battle gate
  with `Verify25ccShadow + 25ccBody Verify`.
- This was Windows-only. No Android, ADB, Thor, GPU offload, or uncapped speed
  A/B was run.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate Fail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 220 -ScreenshotMaxCount 8
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-124500-hle-25cc-body-battle-windows`.
- Summary:
  `debug-captures/windows-lab/20260525-124500-hle-25cc-body-battle-windows/eternal-sonata-gpu-probe-summary.md`.
- Body CSV:
  `debug-captures/windows-lab/20260525-124500-hle-25cc-body-battle-windows/eternal-sonata-spu-hle-25cc-body-profile.csv`.
- Screenshots:
  `screenshot-0244s.png`, `screenshot-0305s.png`, and `screenshot-0320s.png`
  show the active first battle.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before launch.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention gate passed: `Fail` gate, worst host grade `clean`, worst
  external grade `clean`, `5` snapshots.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- Manual screenshot review confirmed a clean active first-battle scene:
  - `screenshot-0244s.png`: Polka battle HUD, HP `900/900`, command ring, and
    field background visible.
  - `screenshot-0305s.png`: same first-battle view still stable.
  - `screenshot-0320s.png`: same first-battle view still stable near run end.
- No black overlay, wrong-window capture, obvious battle HUD corruption, or
  visible texture/lighting break was observed.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `1600`;
  - GET body hits: `23988`;
  - GET body bytes: `393019392` (`374.81 MB`);
  - PUT rejects left on stock path: `24075`;
  - timing: total `3.996 ms`, average `0.167 us/hit`, max `12 us`.
- `0x25cc` family verifier:
  - rows: `1600`;
  - hits: `48063`;
  - fail: `0`;
  - bytes: `787464192` (`750.98 MB`).
- `0x25cc` shadow verifier:
  - rows: `1600`;
  - hits: `23988`;
  - bytes: `393019392` (`374.81 MB`);
  - output mismatch: `0`;
  - destination changed/unchanged: `1602 / 22386`.
- Selected `0x25cc` GPU probe rows still had `0` RSX-local GET/PUT bytes.
- Window title samples stayed near the capped battle rate, about `30.00 FPS`;
  this run is correctness/counter proof only, not speed evidence.

Reading:

- The opt-in `0x25cc` GET body path now has field, title Options, and
  first-battle visual/fatal/counter proof in verify mode.
- The body path continues to preserve GET copy semantics while rejecting PUT
  directions back to stock.
- This remains CPU/SPU HLE/codegen work, not GPU migration: selected `0x25cc`
  RSX-local bytes remain `0 B`.

Classification:

- `spu-hle-25cc-body-battle-pass`, `first-battle-correctness-proof`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Update the default Windows menu macro to the repaired Options route shape,
  then run matched uncapped stock/body A/B timing only after confirming both
  sides hit the same field, Options, and first-battle checkpoints.

## 2026-05-25 - Default Windows Options Route Repair

Purpose:

- Promote the proven title Options timing into the default Windows `menu`
  route in `tools/eternal_sonata_speed_sprint.ps1`.
- This was a Windows-only harness improvement. No Android, ADB, Thor, new
  gameplay run, GPU offload, or speed A/B was run.

Changed:

- `tools/eternal_sonata_speed_sprint.ps1` now uses the repaired Options macro:
  `wait:65000;cross:180;wait:9000;shot:100;down:220;wait:1000;shot:100;down:220;wait:16000;shot:100;cross:180;wait:8000;shot:100;wait:6000;shot:100`.
- The default route now first settles/skips to the title menu with `cross`,
  then moves to Options, waits for selection stability, and opens the full
  Options page.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before the edit.
- PowerShell parser validation passed for
  `tools/eternal_sonata_speed_sprint.ps1`: `parse-ok`.
- The macro is backed by the existing clean Options proof run
  `debug-captures/windows-lab/20260525-123316-hle-25cc-body-options-route-repair-windows`:
  screenshots `screenshot-0104s.png`, `screenshot-0115s.png`, and
  `screenshot-0130s.png` showed the full title Options page stable and clean.
- That proof run had host grade `clean`, no real fatal/access/Vulkan/assertion
  hit, `0x25cc` body `8538` GET hits, `139886592` GET bytes (`133.41 MB`),
  `0` shadow mismatches, and `0 B` selected `0x25cc` RSX-local traffic.

Reading:

- This removes the known bad default route that could remain on the title menu
  or fall into intro playback before proving Options.
- This is process/route tooling only. It does not move work to GPU, does not
  improve FPS by itself, and does not change the `0x25cc` body gate.

Classification:

- `process-harness`, `route-tooling`, `default-options-route-repaired`, not
  `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and not
  a 200% gate candidate.

Next:

- Use the repaired default `-Scene menu` route for future matched stock/body
  correctness and uncapped A/B timing, with `-WindowsGameScreen 1` and host
  contention gating.

## 2026-05-25 - 0x25cc GET Body Uncapped Field A/B Attempt

Purpose:

- Start matched uncapped field timing for the `0x25cc` GET body path after the
  field, title Options, and first-battle correctness proofs.
- This was Windows-only. No Android, ADB, Thor, GPU offload, menu/battle A/B,
  or promotion run was performed.

Stock Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-25cc-stock-field-uncap-ab -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsHostContentionGate ExternalFail -MaxSeconds 175 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 5 -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

Body Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-25cc-body-field-uncap-ab -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 175 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 5 -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

Artifacts:

- Stock run:
  `debug-captures/windows-lab/20260525-130753-hle-25cc-stock-field-uncap-ab-windows`.
- Body run:
  `debug-captures/windows-lab/20260525-131116-hle-25cc-body-field-uncap-ab-windows`.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before the pair.
- Both runs used `-WindowsGameScreen 1`, PadApi, `240/240`, and
  `ExternalFail` host gating.
- Stock visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, with no real fatal/access/Vulkan/assertion
  hit beyond the benign `Show fatal error hints: false` config line.
- Stock window-title samples across `8` samples: min `89.98 FPS`, max
  `105.42 FPS`, average `96.07 FPS`; host total grade was `moderate` as
  expected for uncapped RPCS3 load, but external grade stayed `clean`.
- Body visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; all six screenshots were
  small blue/cutscene/crash-like frames (`39882` to `40890` bytes).
- Manual screenshot review of `screenshot-0118s.png` showed the RPCS3 overlay
  message `The PS3 application has likely crashed, you can close it.`
- Body fatal scan found a real crash:
  `VM: Access violation reading location 0x14 (unmapped memory)` in
  `PPU[0x1000000] Thread (main_thread) [0x002c067c]`, followed by
  `Emulation has been frozen`.
- Body window-title samples stayed around `30 FPS` only because the game had
  frozen/crashed; they are not valid field timing.

Counter Reading:

- Body run before crash:
  - `0x25cc` body rows: `318`;
  - body hits: `4758`;
  - body bytes: `74.34 MB`;
  - PUT rejects: `4785`;
  - body timing: `7.190 ms`;
  - selected `0x25cc` RSX-local GET/PUT bytes: `0 / 0`.
- The body run used `-EternalSonataSpuHleVerify Verify`, not
  `Verify25ccShadow`; the earlier clean correctness proofs used
  `Verify25ccShadow + 25ccBody Verify`.

Reading:

- The pure stock uncapped field baseline is valid and useful for later A/B.
- The body half of this A/B is invalid because the guest crashed before a valid
  field screenshot. Do not compare the stock `96.07 FPS` average against the
  body run's frozen `30 FPS` samples.
- This suggests the `0x25cc` body path is not yet ready for plain-`Verify`
  uncapped timing. The next narrow isolation is either:
  - re-run uncapped body with the previously proven `Verify25ccShadow` mode; or
  - run capped field with plain `Verify + 25ccBody Verify` to separate mode
    semantics from uncapped timing.
- Selected `0x25cc` RSX-local traffic remains `0 B`, so broad GPU offload stays
  parked.

Classification:

- Stock half: `valid-uncapped-stock-field-baseline`.
- Body half: `failed-body-plain-verify-uncap-crash`,
  `not-comparable-speed-proof`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a speed result, and not a 200% gate candidate.

Next:

- Do not use this failed body run for speed claims. Isolate the crash by
  reusing the proven `Verify25ccShadow + 25ccBody Verify` correctness mode
  under uncapped field, or by testing plain `Verify + 25ccBody Verify` under
  capped field before another A/B.

## 2026-05-25 - 0x25cc GET Body Plain-Verify Capped Field Isolation

Purpose:

- Isolate whether the uncapped body crash was caused by plain
  `-EternalSonataSpuHleVerify Verify` mode itself, or by the uncapped/timing
  conditions of the failed A/B run.
- This was Windows-only. No Android, ADB, Thor, GPU offload, menu/battle proof,
  or speed promotion run was performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-25cc-body-field-plainverify-capped-isolate -WindowsInputBackend PadApi -WindowsGameScreen 1 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate Fail -MaxSeconds 170 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4 -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-133018-hle-25cc-body-field-plainverify-capped-isolate-windows`.
- Visual gate:
  `debug-captures/windows-lab/20260525-133018-hle-25cc-body-field-plainverify-capped-isolate-windows/eternal-sonata-windows-visual-gate-summary.md`.
- Summary:
  `debug-captures/windows-lab/20260525-133018-hle-25cc-body-field-plainverify-capped-isolate-windows/eternal-sonata-gpu-probe-summary.md`.
- Body CSV:
  `debug-captures/windows-lab/20260525-133018-hle-25cc-body-field-plainverify-capped-isolate-windows/eternal-sonata-spu-hle-25cc-body-profile.csv`.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before launch.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention gate passed: `Fail` gate, worst host grade `clean`, worst
  external grade `clean`, `5` snapshots.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `0` invalid screenshots after first field,
  and required field-like at or before `160s` passed.
- Manual screenshots `screenshot-0117s.png` and `screenshot-0165s.png` showed a
  clean Path to Tenuto field with the player visible, no black overlay, no
  crash overlay, and no obvious lighting/texture corruption.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- No lingering `rpcs3`, `rpcsx`, build, or linker process was present after the
  run.
- Window-title samples across `8` samples stayed capped: min `29.95 FPS`, max
  `30.01 FPS`, average `29.99 FPS`.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `645`;
  - GET body hits: `9663`;
  - GET body bytes: `158318592` (`150.98 MB`);
  - PUT rejects left on stock path: `9690`;
  - timing: total `9.114 ms`, max `14 us`.
- `0x25cc` family verifier:
  - rows: `645`;
  - hits: `19353`;
  - fail: `0`;
  - bytes: `302.39 MB`;
  - timing: total `50.355 ms`, max `68 us`.
- Plain HLE shadow verifier:
  - rows: `1281`;
  - hits: `4487`;
  - bytes: `11.00 MB`;
  - output match/mismatch: `3899 / 588`;
  - destination changed/unchanged: `3843 / 644`.
- Selected `0x25cc` RSX-local traffic remained `0 B`; the GPU probe summary had
  `0` RSX-local traffic records.

Reading:

- Plain `Verify + 25ccBody Verify` does not crash under capped field timing, so
  the failed uncapped body A/B is not explained by plain Verify mode alone.
- The plain-shadow mismatches mean this run is crash isolation and visual/fatal
  survival evidence, not a promoted correctness proof for plain Verify body
  timing. The cleaner correctness mode remains the earlier
  `Verify25ccShadow + 25ccBody Verify` field, Options, and first-battle proof
  with `0` 25cc-shadow mismatches.
- The body path remains CPU/SPU HLE/codegen work, not GPU migration: selected
  `0x25cc` RSX-local bytes are still `0 B`.

Classification:

- `spu-hle-25cc-body-plainverify-capped-field-survives`,
  `crash-isolation`, not `windows-micro-win`, not `gpu-migration-credit`, not a
  speed result, and not a 200% gate candidate.

Next:

- Do not use this capped field run for speed claims. For the next uncapped A/B,
  either use the previously proven `Verify25ccShadow + 25ccBody Verify` mode or
  first inspect why plain `Verify + 25ccBody Verify` produced `588` general
  shadow mismatches despite clean visual/fatal capped field survival.

## 2026-05-25 - 0x25cc GET Body Shadow-Verify Uncapped Field Isolation

Purpose:

- Re-run the body half of the uncapped field A/B with the previously proven
  `Verify25ccShadow + 25ccBody Verify` correctness mode, after plain `Verify`
  crashed under uncapped timing but survived capped timing.
- This was Windows-only. No Android, ADB, Thor, GPU offload, menu/battle A/B,
  or 200% promotion run was performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-25cc-body-field-shadowverify-uncap-isolate -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 175 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 5 -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-135133-hle-25cc-body-field-shadowverify-uncap-isolate-windows`.
- Visual gate:
  `debug-captures/windows-lab/20260525-135133-hle-25cc-body-field-shadowverify-uncap-isolate-windows/eternal-sonata-windows-visual-gate-summary.md`.
- Summary:
  `debug-captures/windows-lab/20260525-135133-hle-25cc-body-field-shadowverify-uncap-isolate-windows/eternal-sonata-gpu-probe-summary.md`.
- Window title samples:
  `debug-captures/windows-lab/20260525-135133-hle-25cc-body-field-shadowverify-uncap-isolate-windows/window-title-samples.csv`.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before launch.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention used `ExternalFail`: total host grade was `moderate` as
  expected for uncapped RPCS3 load, while external host grade stayed `clean`
  across `5` snapshots.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `0` invalid screenshots after first field,
  and required field-like at or before `160s` passed.
- Manual screenshots `screenshot-0117s.png` and `screenshot-0165s.png` showed a
  clean Path to Tenuto field with the player visible, no black overlay, no
  crash overlay, and no obvious lighting/texture corruption.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- No lingering `rpcs3`, `rpcsx`, build, or linker process was present after the
  run.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `478`;
  - GET body hits: `7158`;
  - GET body bytes: `111.84 MB`;
  - PUT rejects left on stock path: `7185`;
  - timing: total `1.114 ms`, max `2 us`.
- `0x25cc` family verifier:
  - rows: `478`;
  - hits: `14343`;
  - fail: `0`;
  - bytes: `224.11 MB`;
  - timing: total `703.967 ms`, max `569 us`.
- `0x25cc` shadow verifier:
  - rows: `478`;
  - hits: `7158`;
  - bytes: `111.84 MB`;
  - output match/mismatch: `7158 / 0`;
  - destination changed/unchanged: `480 / 6678`.
- Selected `0x25cc` RSX-local traffic remained `0 B`; the GPU probe summary had
  `0` RSX-local traffic records.
- Window-title samples across `8` samples: min `102.54 FPS`, max `108.83 FPS`,
  average `105.31 FPS`.
- Same-day uncapped stock field baseline
  `debug-captures/windows-lab/20260525-130753-hle-25cc-stock-field-uncap-ab-windows`
  sampled min `89.98 FPS`, max `105.42 FPS`, average `96.07 FPS`.
  The body run was `+9.24 FPS` / `+9.62%` over that stock field average under
  the same route shape, display target, `240/240` config, PadApi input, and
  `ExternalFail` external-host gate.

Reading:

- The uncapped crash appears specific to the earlier plain-`Verify` body run or
  its interaction with general shadow instrumentation, not to uncapped field
  timing plus the `0x25cc` body copy itself.
- This is the first clean uncapped field timing signal for the `0x25cc` GET
  body scaffold and is worth repeating, but it is only field evidence. It does
  not prove title Options, first battle, or a stable combined speed gate.
- The body path remains CPU/SPU HLE/codegen work, not GPU migration: selected
  `0x25cc` RSX-local bytes are still `0 B`.

Classification:

- `spu-hle-25cc-body-shadowverify-uncap-field-pass`,
  `field-only-windows-micro-win-signal`, not full `windows-micro-win`, not
  `gpu-migration-credit`, not a 200% gate candidate, and not a promotion result.

Next:

- Repeat a matched uncapped field pair or run title Options and first-battle
  uncapped body/stock checks with the repaired menu route before banking this
  as a real Windows micro-win. Do not port or claim 200%; broad SPU-to-Vulkan
  compute remains parked while `0x25cc` RSX-local traffic is `0 B`.

## 2026-05-25 - 0x25cc GET Body Shadow-Verify Uncapped Options Proof

Purpose:

- Check the repaired title Options route under uncapped `240/240` timing with
  the same `Verify25ccShadow + 25ccBody Verify` body mode that produced the
  clean uncapped field signal.
- This was Windows-only. No Android, ADB, Thor, GPU offload, stock Options A/B,
  first-battle A/B, or 200% promotion run was performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label hle-25cc-body-options-shadowverify-uncap -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 135 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 85 -ScreenshotMaxCount 12
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-140314-hle-25cc-body-options-shadowverify-uncap-windows`.
- Summary:
  `debug-captures/windows-lab/20260525-140314-hle-25cc-body-options-shadowverify-uncap-windows/eternal-sonata-gpu-probe-summary.md`.
- Window title samples:
  `debug-captures/windows-lab/20260525-140314-hle-25cc-body-options-shadowverify-uncap-windows/window-title-samples.csv`.
- Body CSV:
  `debug-captures/windows-lab/20260525-140314-hle-25cc-body-options-shadowverify-uncap-windows/eternal-sonata-spu-hle-25cc-body-profile.csv`.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before launch.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention used `ExternalFail`; total and external host grades both
  stayed `clean` across `5` snapshots.
- Manual screenshots `screenshot-0104s.png` and `screenshot-0130s.png` showed
  the full title Options page stable and clean at uncapped speed.
- No black overlay, wrong-window capture, visible menu corruption, or obvious
  texture/lighting defect was observed in the checked Options screenshots.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- No lingering `rpcs3`, `rpcsx`, build, or linker process was present after the
  run.
- Window-title samples across `18` samples: min `239.26 FPS`, max `240.85 FPS`,
  average `240.14 FPS`. This is title-menu route/correctness evidence, not a
  moving-gameplay speed claim.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `428`;
  - GET body hits: `6408`;
  - GET body bytes: `100.12 MB`;
  - PUT rejects left on stock path: `6435`;
  - timing: total `1.169 ms`, max `13 us`.
- `0x25cc` family verifier:
  - rows: `428`;
  - hits: `12843`;
  - fail: `0`;
  - bytes: `200.67 MB`;
  - timing: total `614.682 ms`, max `363 us`.
- `0x25cc` shadow verifier:
  - rows: `428`;
  - hits: `6408`;
  - bytes: `100.12 MB`;
  - output match/mismatch: `6408 / 0`;
  - destination changed/unchanged: `430 / 5978`.
- Total observed DMA bytes: `1,485.99 MB`.
- Selected `0x25cc` RSX-local traffic remained `0 B`; the GPU probe summary had
  `0` RSX-local traffic records.

Reading:

- The body path now has clean uncapped `Verify25ccShadow + 25ccBody Verify`
  evidence for field and title Options.
- This strengthens the field-only micro-win signal, but it is not a banked
  Windows micro-win by itself because no matched stock Options A/B was run and
  first-battle uncapped proof is still missing.
- This remains CPU/SPU HLE/codegen work, not GPU migration: selected `0x25cc`
  RSX-local bytes are still `0 B`.

Classification:

- `spu-hle-25cc-body-shadowverify-uncap-options-pass`,
  `valid-options-proof`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a speed result, and not a 200% gate candidate.

Next:

- Run first-battle uncapped proof for `Verify25ccShadow + 25ccBody Verify`, or
  repeat a matched uncapped field stock/body pair, before banking the `0x25cc`
  body path as a real Windows micro-win. Do not port or claim 200%.

## 2026-05-25 - 0x25cc GET Body Shadow-Verify Uncapped Battle Route Miss

Purpose:

- Classify the pending uncapped first-battle attempt for
  `Verify25ccShadow + 25ccBody Verify` before starting duplicate Windows work.
- This was Windows-only. No Android, ADB, Thor, GPU offload, stock battle A/B,
  or 200% promotion run was performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle-shadowverify-uncap -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 180 -ScreenshotMaxCount 10 -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

Artifacts:

- Run directory:
  `debug-captures/windows-lab/20260525-141304-hle-25cc-body-battle-shadowverify-uncap-windows`.
- Visual gate:
  `debug-captures/windows-lab/20260525-141304-hle-25cc-body-battle-shadowverify-uncap-windows/eternal-sonata-windows-visual-gate-summary.md`.
- Summary:
  `debug-captures/windows-lab/20260525-141304-hle-25cc-body-battle-shadowverify-uncap-windows/eternal-sonata-gpu-probe-summary.md`.
- Window title samples:
  `debug-captures/windows-lab/20260525-141304-hle-25cc-body-battle-shadowverify-uncap-windows/window-title-samples.csv`.

Verification:

- Active-work guard found no active RPCS3/RPCSX/cmake/cl/link/MSBuild/ninja
  work before review.
- The route stayed on `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention used `ExternalFail`; total and external host grades stayed
  `clean` across `5` snapshots.
- Visual gate failed as expected for this command shape:
  `NO_FIELD_LIKE_SCREENSHOT`, `12` wrong-window/other-small PNGs, and required
  field-like-at-160s failed. The gate was a field gate, not a battle/menu OCR
  gate.
- Manual screenshot checks of `screenshot-0131s.png`, `screenshot-0244s.png`,
  and `screenshot-0311s-01.png` show the full title Options page, not active
  first battle. No obvious Options-page texture, lighting, or menu corruption
  was visible.
- Fatal scan found no real crash/access/Vulkan/assertion hit; the only fatal
  string match was the benign config line `Show fatal error hints: false`.
- Window-title samples across `14` samples: min `239.73 FPS`, max
  `240.34 FPS`, average `240.07 FPS`. This is title Options/menu behavior, not
  moving-gameplay or first-battle speed evidence.

Counter Reading:

- `0x25cc` body verifier:
  - rows: `635`;
  - GET body hits: `9513`;
  - GET body bytes: `155860992` (`148.64 MB`);
  - PUT rejects left on stock path: `9585`;
  - timing: total `1.457 ms`, max `4 us`.
- `0x25cc` shadow verifier:
  - rows: `635`;
  - hits: `9513`;
  - bytes: `148.64 MB`;
  - output match/mismatch: `9513 / 0`;
  - destination changed/unchanged: `637 / 8876`.
- Total observed DMA bytes: `1,518.39 MB`.
- Selected `0x25cc` RSX-local traffic remained `0 B`; the GPU probe summary had
  `0` RSX-local traffic records and `0` indirect overlap records.

Reading:

- The run is useful as an additional clean uncapped title Options/body counter
  proof, but it is a route miss for the requested first-battle proof.
- It must not be counted as first-battle visual proof, a moving-gameplay speed
  result, a `windows-micro-win`, `gpu-migration-credit`, or a 200% gate
  candidate.
- Repeated `0 B` selected `0x25cc` RSX-local bytes keep broad SPU-to-Vulkan
  compute parked. This lane remains CPU/SPU HLE/codegen work.

Classification:

- `route-miss-options-not-battle`, `valid-options-duplicate`,
  `not-comparable-speed-proof`, not `windows-micro-win`, not
  `gpu-migration-credit`, not a speed result, and not a 200% gate candidate.

Next:

- Do not rerun this same battle command unchanged. Repair the first-battle macro
  or add a battle-aware route/visual gate, then rerun
  `Verify25ccShadow + 25ccBody Verify` first-battle proof on screen 1 before any
  stock/body battle A/B or micro-win claim.

## 2026-05-25 - 25cc Battle Route-Miss Harness Refiner Guard

Purpose:

- Prevent the continual harness from treating the latest `0x25cc` body
  battle-to-Options route miss as a generic wrong-window failure or from
  recommending another duplicate Windows movement/field run.
- This was Windows-only process tooling. No Android, ADB, Thor, RPCS3 gameplay
  launch, GPU offload, speed A/B, or 200% promotion run was performed.

Changed:

- `tools/ps3_harness_refiner.ps1` now:
  - classifies labeled `0x25cc` body title Options captures with repeated small
    clean menu screenshots as `valid-options-triage`;
  - classifies a battle-labeled `0x25cc` body run that produces those repeated
    clean title Options screenshots as `route-miss-options-not-battle`;
  - emits a blocker anti-pattern and a no-rerun comment telling the next pass to
    repair the first-battle macro or add a battle-aware visual gate before
    rerunning `Verify25ccShadow + 25ccBody Verify`.
- `.agents/skills/ps3-continual-harness-refiner/SKILL.md` documents the same
  reusable route-miss rule and output class.

Verification:

```powershell
$errors = $null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw tools\ps3_harness_refiner.ps1), [ref]$errors) | Out-Null; if ($errors -and $errors.Count -gt 0) { $errors | Format-List; exit 1 } else { 'PSParser OK' }
git diff --check -- tools/ps3_harness_refiner.ps1 .agents/skills/ps3-continual-harness-refiner/SKILL.md
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

Result:

- Parser check: `PSParser OK`.
- `git diff --check`: clean.
- Refiner dry run now reports:
  - latest run
    `20260525-141304-hle-25cc-body-battle-shadowverify-uncap-windows` as
    `route-miss-options-not-battle`;
  - `20260525-140314-hle-25cc-body-options-shadowverify-uncap-windows` and
    `20260525-123316-hle-25cc-body-options-route-repair-windows` as
    `valid-options-triage`;
  - next action:
    `Latest 0x25cc body battle attempt opened the title Options page instead of first battle. Do not rerun that battle command unchanged; repair the first-battle macro or add a battle-aware route/visual gate before battle proof or stock/body A/B.`
  - suggested command:
    `# No automatic 0x25cc body battle rerun: latest battle attempt opened title Options instead of first battle. Repair the first-battle macro or add a battle-aware visual gate before rerunning Verify25ccShadow + 25ccBody Verify.`

Classification:

- `harness-improvement`, `route-tooling`, not a speed result, not
  `windows-micro-win`, not `gpu-migration-credit`, and not a 200% gate
  candidate.

Next:

- Repair the first-battle macro or add a battle-aware route/visual gate before
  another `Verify25ccShadow + 25ccBody Verify` battle proof. Do not rerun the
  same battle command unchanged.

## 2026-05-25 - BattleRoute Visual Gate Harness Guard

Purpose:

- Add a reusable Windows visual gate for repaired first-battle routes so a new
  `0x25cc` body battle proof can reject title Options/menu landings before any
  stock/body A/B or micro-win claim.
- This was Windows-only harness work. No Android, ADB, Thor, RPCS3 gameplay
  launch, GPU offload, speed A/B, or 200% promotion run was performed.

Changed:

- `tools/check_eternal_sonata_windows_visual_gate.ps1` now supports:
  - `-RequireFieldAtOrAfterSeconds`;
  - `-RequireMinFieldLikeCount`.
- `tools/eternal_sonata_speed_sprint.ps1` now accepts
  `-WindowsVisualGate BattleRoute`, which requires:
  - a field-like screenshot at or before `-WindowsVisualGateFieldSeconds`;
  - a field-like screenshot at or after `220s`;
  - at least two field-like screenshots;
  - no invalid screenshot after the first field-like screenshot;
  - a minimum large-scene PNG threshold of at least `1,500,000` bytes.
- `tools/ps3_harness_refiner.ps1` now tells the next `0x25cc` body battle rerun
  to use `-WindowsVisualGate BattleRoute` after the route is repaired.
- `.agents/skills/ps3-continual-harness-refiner/SKILL.md` documents that
  `0x25cc` route-miss recovery should use the `BattleRoute` gate.

Verification:

```powershell
$files = @('tools\check_eternal_sonata_windows_visual_gate.ps1','tools\eternal_sonata_speed_sprint.ps1','tools\ps3_harness_refiner.ps1'); foreach ($f in $files) { $errors = $null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $f), [ref]$errors) | Out-Null; if ($errors -and $errors.Count -gt 0) { Write-Host "PARSER_FAIL $f"; $errors | Format-List; exit 1 } }; 'PSParser OK'
git diff --check -- tools/check_eternal_sonata_windows_visual_gate.ps1 tools/eternal_sonata_speed_sprint.ps1 tools/ps3_harness_refiner.ps1 .agents/skills/ps3-continual-harness-refiner/SKILL.md
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir debug-captures\windows-lab\20260525-124500-hle-25cc-body-battle-windows -MinFieldPngBytes 1500000 -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireFieldAtOrAfterSeconds 220 -RequireMinFieldLikeCount 2 -RequireNoInvalidAfterFirstField -NoWriteSummary
try { .\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir debug-captures\windows-lab\20260525-141304-hle-25cc-body-battle-shadowverify-uncap-windows -MinFieldPngBytes 1500000 -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireFieldAtOrAfterSeconds 220 -RequireMinFieldLikeCount 2 -RequireNoInvalidAfterFirstField -NoWriteSummary; 'UNEXPECTED_PASS'; exit 1 } catch { 'EXPECTED_FAIL'; $_.Exception.Message }
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

Result:

- Parser check: `PSParser OK`.
- `git diff --check`: no whitespace errors; PowerShell warned that
  `tools/eternal_sonata_speed_sprint.ps1` line endings may normalize later.
- Known clean first-battle visual proof
  `20260525-124500-hle-25cc-body-battle-windows` passed the new stricter gate:
  `FIELD_LIKE_PRESENT`, first field-like `screenshot-0131s.png` at `131s`
  (`2.50 MB`), with later large screenshots after `220s`.
- Known battle-to-Options route miss
  `20260525-141304-hle-25cc-body-battle-shadowverify-uncap-windows` failed the
  new gate as expected:
  - no field-like screenshot;
  - no field-like screenshot at or before `160s`;
  - no field-like screenshot at or after `220s`;
  - `0` field-like screenshots found, required at least `2`.
- Refiner dry run still classifies the latest battle attempt as
  `route-miss-options-not-battle`, and its suggested command now says:
  `Repair the first-battle macro, then rerun Verify25ccShadow + 25ccBody Verify with -WindowsVisualGate BattleRoute.`

Classification:

- `harness-improvement`, `battle-route-tooling`, not a speed result, not
  `windows-micro-win`, not `gpu-migration-credit`, and not a 200% gate
  candidate.

Next:

- Repair the first-battle input macro, then rerun the `0x25cc` body battle proof
  on screen 1 with `-WindowsVisualGate BattleRoute`. Do not use the battle proof
  for speed or micro-win banking unless the gate passes and manual first-battle
  visuals are clean.

## 2026-05-25 - Top-Slot Battle Route Repair Command

Purpose:

- Turn the `0x25cc` battle-to-Options route miss into an executable next
  Windows command instead of a vague "repair macro" comment.
- This was Windows-only harness work. No Android, ADB, Thor, RPCS3 gameplay
  launch, GPU offload, speed A/B, or 200% promotion run was performed.

Changed:

- `tools/eternal_sonata_speed_sprint.ps1` now accepts
  `-WindowsBattleLoadRoute Legacy|TopSlot`.
- Default behavior remains `Legacy` to avoid changing existing battle-route
  callers silently.
- `TopSlot` reuses the repaired title/load-menu path that normalizes to Save
  File 01 before opening the field, then applies the existing first-battle
  movement tail.
- `tools/ps3_harness_refiner.ps1` now suggests this concrete repaired route
  after the latest `0x25cc` body battle-to-Options miss:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Verification:

```powershell
$files = @('tools\eternal_sonata_speed_sprint.ps1','tools\ps3_harness_refiner.ps1'); foreach ($f in $files) { $errors = $null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $f), [ref]$errors) | Out-Null; if ($errors -and $errors.Count -gt 0) { Write-Host "PARSER_FAIL $f"; $errors | Format-List; exit 1 } }; 'PSParser OK'
git diff --check -- tools/eternal_sonata_speed_sprint.ps1 tools/ps3_harness_refiner.ps1 .agents/skills/ps3-continual-harness-refiner/SKILL.md
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
```

Result:

- Parser check: `PSParser OK`.
- `git diff --check`: no whitespace errors; PowerShell warned that
  `tools/eternal_sonata_speed_sprint.ps1` line endings may normalize later.
- Refiner dry run now emits the concrete `TopSlot + BattleRoute` command above
  for the latest `route-miss-options-not-battle` run.

Classification:

- `harness-improvement`, `battle-route-tooling`, not a speed result, not
  `windows-micro-win`, not `gpu-migration-credit`, and not a 200% gate
  candidate.

Next:

- Run the suggested `TopSlot + BattleRoute` 0x25cc body battle proof on screen 1.
  If it passes the route gate and manual first-battle visuals, then use it as
  the battle leg before any stock/body battle A/B or micro-win banking.

## 2026-05-25 - 0x25cc Body TopSlot BattleRoute Proof

Purpose:

- Validate the repaired `TopSlot` first-battle route for the `0x25cc` body
  verifier after the earlier battle-to-Options miss.
- This was Windows-only gameplay proof work on screen 1. No Android, ADB, Thor,
  GPU offload, stock/body A/B, or 200% promotion run was performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Run:

- `debug-captures\windows-lab\20260525-170853-hle-25cc-body-battle-topslot-battleroute-windows`

Visual verification:

- Visual gate summary: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- First field-like screenshot: `screenshot-0155s.png` at `155s`
  (`2.50 MB`), satisfying the required field-like frame at or before `160s`.
- Later field-like requirement passed at or after `220s`; total field-like
  screenshots found: `6`.
- Invalid screenshots after first field-like: `0`.
- Manual screenshot checks:
  - `screenshot-0155s.png`: clean Path to Tenuto field gameplay.
  - `screenshot-0206s.png`: clean first-battle tutorial prompt
    (`View the tutorial? Yes/No`).
  - `screenshot-0268s.png`: clean active first-battle UI with Polka HP
    `900/900` and command UI.
  - `screenshot-0332s.png`: clean late first-battle UI.

Logs and host gate:

- `ExternalFail` host-contention gate passed. External load was clean; total
  load was moderate from RPCS3 itself.
- `stdout.txt` and `stderr.txt` were empty.
- Fatal scan found no real fatal/access/Vulkan/assert/crash/likely-crashed/STOP
  evidence; the matches were benign sys errors and Vulkan initialization text.
- No `rpcs3`, `rpcsx`, or build processes remained active after the run.

Counters:

- Window-title FPS samples: `8`; average `116.44 FPS`, minimum `112.63 FPS`,
  maximum `119.90 FPS`.
- SPU HLE `0x25cc` shadow: `14658` hits, `229.03 MB`, output mismatch `0`.
- SPU HLE `0x25cc` body: `14658` hits, `229.03 MB`, timing total
  `3.140 ms`, average `0.214 us/hit`, max `189 us`.
- SPU HLE `0x25cc` family: `29343` hits, `458.48 MB`, success/fail
  `29343 / 0`.
- GPU Port Scoreboard: promoted CPU/SPU to GPU replacements `0`, direct
  RSX-local scout traffic `0`, indirect SPU-DMA/RSX-resource overlap `0`.
- MFC wait exact-PC peak reads: `174309`; top exact PCs remained wait-heavy,
  so reservation-loop attribution still needs repair before a fast/HLE/GPU
  replacement design.

Classification:

- `valid-first-battle-proof`, `battle-route-tooling`,
  `spu-hle-codegen-proof`.
- Not `windows-micro-win`, not `gpu-migration-credit`, not a matched speed A/B,
  and not a 200% gate candidate.

Reading:

- The repaired `TopSlot + BattleRoute` path is now usable for the first-battle
  leg of the `0x25cc` proof chain.
- This proof strengthens the ARM64/NEON/SPU-HLE/codegen lane from the research
  intake, because it shows the `0x25cc` body can run through field and first
  battle visuals with zero shadow mismatches.
- It does not justify broad SPU-to-GPU compute yet. The same run reported zero
  promoted CPU/SPU-to-GPU bytes, zero direct RSX-local scout traffic, and zero
  indirect overlap, so the near-term target remains trace-mined native
  CPU/NEON fast paths plus reservation-loop attribution.

Next:

- Use this `TopSlot + BattleRoute` command shape for future `0x25cc` battle
  legs.
- The next speed step is a matched clean stock/body battle A/B, or a combined
  field/menu/battle route, before banking any full-route micro-win.
- Do not promote GPU compute work unless a future trace shows RSX-consumed data
  or a stable RSX-local candidate.

## 2026-05-25 - 0x25cc Stock TopSlot BattleRoute A/B Attempt Rejected

Purpose:

- Run the missing stock side for a matched `0x25cc` body-vs-stock battle A/B
  using the repaired `TopSlot + BattleRoute` command shape.
- This was Windows-only on screen 1. No Android, ADB, Thor, GPU offload, or
  200% promotion run was performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-stock-battle-topslot-battleroute-ab -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Run:

- `debug-captures\windows-lab\20260525-173039-hle-25cc-stock-battle-topslot-battleroute-ab-windows`

Verification:

- Visual gate summary reported `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- First field-like screenshot: `screenshot-0154s.png` at `154s`
  (`1.75 MB`); field-like at/after `220s` also passed; total field-like
  screenshots: `6`; invalid after first field-like: `0`.
- Manual screenshot inspection rejects the route as a battle baseline:
  - `screenshot-0154s.png`, `screenshot-0206s.png`,
    `screenshot-0268s.png`, and `screenshot-0332s.png` all show the same
    paused Path to Tenuto field state with the large `Pause` overlay.
  - No tutorial prompt, first-battle UI, enemy/party HUD, or battle scene was
    reached.
- Host contention gate `ExternalFail` passed: external load was clean, total
  load was moderate from RPCS3 itself near the end of the run.
- `stdout.txt` and `stderr.txt` were empty.
- Fatal scan found no real fatal/access/Vulkan/assertion/crash evidence; hits
  were benign `stop`/module-stop/import text and the config line
  `Show fatal error hints: false`.
- No `rpcs3`, `rpcsx`, or build processes remained active after the run.

Counters:

- Stock window-title FPS samples: `8`; average `119.94 FPS`, minimum
  `119.28 FPS`, maximum `120.79 FPS`.
- If compared mechanically to the prior body battle proof
  (`116.44 FPS` average), body would look `-3.49 FPS` / `-2.91%`.
- That comparison is invalid because the stock route stayed in paused field
  while the body route reached field, first-battle tutorial prompt, and active
  first-battle UI.

Classification:

- `not-comparable-route-miss-paused-field`, `battle-route-tooling-gap`.
- Not `speed-win`, not `windows-micro-win`, not `gpu-migration-credit`, and
  not a 200% gate candidate.

Reading:

- The current `BattleRoute` byte-size gate is necessary but not sufficient for
  A/B timing: a paused field can satisfy the field-like count/byte rules.
- The stock route likely hit the `start`/`cross` timing in a different game
  state than the body run, leaving the game paused and preventing movement into
  the first battle.
- Do not use this stock run as the stock battle baseline.

Next:

- Repair or state-gate the stock TopSlot battle macro so the stock route shows
  manual first-battle visuals before rerunning the A/B.
- Future battle A/B acceptance must include manual first-battle screenshot
  checks, not only `BattleRoute` triage.

## 2026-05-25 - BattleRoute Late Battle-Like Gate Refinement

Purpose:

- Close the false positive found by the rejected stock A/B attempt, where a
  paused Path to Tenuto field satisfied byte-size `BattleRoute` triage and
  produced misleading `~120 FPS` stock samples.
- This was Windows-only harness/tooling work. No Android, ADB, Thor, emulator
  gameplay rerun, GPU offload, speed A/B, or 200% promotion run was performed.

Changed:

- `tools/check_eternal_sonata_windows_visual_gate.ps1` now accepts:
  - `-RequireBattleLikeAtOrAfterSeconds`;
  - `-MinBattleLikeRedRatio` (default `0.25`);
  - `-MaxBattleLikeGreenRatio` (default `0.34`).
- The helper derives battle-like rows from existing sampled color stats on
  field-like large PNGs. A late screenshot must satisfy
  `RedRatio >= 0.25` and `GreenRatio <= 0.34`.
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsVisualGate BattleRoute` now
  requires a battle-like frame at or after `200s`, in addition to the earlier
  field-like deadline/count/no-invalid checks.
- `.agents/skills/ps3-continual-harness-refiner/SKILL.md` now records the
  paused-field false positive as `not-comparable-route-miss-paused-field`.
- `tools/ps3_harness_refiner.ps1` now treats an explicit visual summary
  `Gate result: failed` as `failed-visual-gate` even when field-like byte-size
  screenshots exist.
- `AGENTS.md` records the standing BattleRoute rule and reminds future A/B
  passes that manual first-battle screenshots remain required.

Verification:

```powershell
$files = @('tools\check_eternal_sonata_windows_visual_gate.ps1','tools\eternal_sonata_speed_sprint.ps1','tools\ps3_harness_refiner.ps1'); foreach ($f in $files) { $errors = $null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $f), [ref]$errors) | Out-Null; if ($errors -and $errors.Count -gt 0) { Write-Host "PARSER_FAIL $f"; $errors | Format-List; exit 1 } }; 'PSParser OK'
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir debug-captures\windows-lab\20260525-170853-hle-25cc-body-battle-topslot-battleroute-windows -MinFieldPngBytes 1500000 -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireFieldAtOrAfterSeconds 220 -RequireMinFieldLikeCount 2 -RequireBattleLikeAtOrAfterSeconds 200 -RequireNoInvalidAfterFirstField
try { .\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir debug-captures\windows-lab\20260525-173039-hle-25cc-stock-battle-topslot-battleroute-ab-windows -MinFieldPngBytes 1500000 -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireFieldAtOrAfterSeconds 220 -RequireMinFieldLikeCount 2 -RequireBattleLikeAtOrAfterSeconds 200 -RequireNoInvalidAfterFirstField; 'UNEXPECTED_PASS'; exit 1 } catch { 'EXPECTED_FAIL'; $_.Exception.Message }
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8 -NoWrite
git diff --check -- AGENTS.md .agents/skills/ps3-continual-harness-refiner/SKILL.md tools/check_eternal_sonata_windows_visual_gate.ps1 tools/eternal_sonata_speed_sprint.ps1 tools/ps3_harness_refiner.ps1
```

Result:

- Parser check: `PSParser OK`.
- Known good body battle proof still passes:
  - run `20260525-170853-hle-25cc-body-battle-topslot-battleroute-windows`;
  - first field-like `screenshot-0155s.png` at `155s`;
  - first battle-like `screenshot-0206s.png` at `206s`;
  - red/green ratios `0.356 / 0.222`.
- Known bad stock paused-field A/B attempt now fails:
  - run `20260525-173039-hle-25cc-stock-battle-topslot-battleroute-ab-windows`;
  - field-like checks still pass, but no battle-like screenshot exists after
    `200s`;
  - paused-field red/green ratios stay around `0.109 / 0.375-0.380`.
- Refiner dry run now classifies that same latest stock run as
  `failed-visual-gate`, not `valid-field-triage`.
- `git diff --check` reported no whitespace errors; only existing LF-to-CRLF
  warnings for `AGENTS.md` and `tools/eternal_sonata_speed_sprint.ps1`.
- No `rpcs3`, `rpcsx`, or build processes remained active.

Classification:

- `harness-improvement`, `battle-route-tooling`,
  `false-positive-visual-gate-repair`.
- Not a speed result, not `windows-micro-win`, not `gpu-migration-credit`, and
  not a 200% gate candidate.

Next:

- Rerun stock TopSlot battle A/B only after the stricter `BattleRoute` gate is
  active, and still manually verify first-battle visuals.
- If stock still parks on the paused field, repair the stock macro timing or
  add an explicit unpause/state-gate before using stock FPS as a baseline.

## 2026-05-25 - 0x25cc Stock No-Pause TopSlot BattleRoute Baseline

Purpose:

- Repair the rejected stock battle baseline by removing the post-load
  `start`/`cross` pair that left the prior stock run paused in the Path to
  Tenuto field.
- This was Windows-only on screen 1. No Android, ADB, Thor, GPU offload, or
  200% promotion run was performed.

Command:

```powershell
$macro = 'wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:1000;ls_left:2600;wait:1000;combo:ls_left+ls_down:2200;wait:45000;shot:100;dpad_down:120;wait:500;cross:180;wait:60000;shot:100;wait:60000;shot:100'
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-stock-battle-topslot-nopause-battleroute-ab -WindowsInputBackend PadApi -WindowsGameScreen 1 -InputMacro $macro -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsHostContentionGate ExternalFail -MaxSeconds 315 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Run:

- `debug-captures\windows-lab\20260525-180238-hle-25cc-stock-battle-topslot-nopause-battleroute-ab-windows`

Visual verification:

- Visual gate summary: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- First field-like screenshot: `screenshot-0117s.png` at `117s`
  (`2.49 MB`), satisfying the required field-like frame at or before `160s`.
- Later field-like requirement passed at or after `220s`; total field-like
  screenshots found: `14`; invalid screenshots after first field-like: `0`.
- Late battle-like requirement passed: first battle-like screenshot
  `screenshot-0232s.png` at `232s`, red/green ratios `0.403 / 0.269`.
- Manual screenshot checks:
  - `screenshot-0117s.png`: clean unpaused Path to Tenuto field gameplay.
  - `screenshot-0170s.png`: clean first-battle tutorial prompt
    (`View the tutorial? Yes/No`) with Polka HP `900/900`.
  - `screenshot-0232s.png`: clean active first-battle UI with Polka HP
    `900/900`, command UI, and visible `Next` marker.
  - `screenshot-0304s-01.png`: clean late active first-battle UI.

Logs and host gate:

- `ExternalFail` host-contention gate passed. External load was clean; total
  load was moderate from RPCS3 itself.
- `stdout.txt` and `stderr.txt` were empty.
- Fatal scan found no real fatal/access/Vulkan/assert/crash/likely-crashed/STOP
  evidence; matches were benign stop/module/config text.
- No `rpcs3`, `rpcsx`, or build processes remained active after the run.

Counters:

- Stock no-pause window-title FPS samples: `16`; average `118.15 FPS`,
  minimum `90.93 FPS`, maximum `120.11 FPS`.
- Prior `0x25cc` body battle proof
  (`20260525-170853-hle-25cc-body-battle-topslot-battleroute-windows`) had
  `8` samples, average `116.44 FPS`, minimum `112.63 FPS`, maximum
  `119.90 FPS`.
- Mechanical cross-run delta: body `-1.70 FPS` / `-1.44%` versus this stock
  no-pause baseline.
- This delta is not a bankable speed result because the stock no-pause run and
  the prior body proof used different macro timing and sampled different route
  windows. The stock run also includes an early field transition sample at
  `90.93 FPS`.

Classification:

- `valid-stock-first-battle-baseline`, `battle-route-tooling`,
  `not-speed-win`.
- Not `windows-micro-win`, not `gpu-migration-credit`, not a matched speed A/B,
  and not a 200% gate candidate.

Reading:

- The no-pause stock route fixes the paused-field false positive and reaches
  field, first-battle tutorial prompt, and active first-battle UI under the
  stricter `BattleRoute` gate.
- The prior `0x25cc` body battle proof remains a correctness/codegen proof, but
  this stock baseline does not show a speed win. If anything, the mechanical
  cross-run comparison is slightly slower for body, so no speed credit should be
  banked from the battle leg yet.
- This result also remains non-GPU work: it moved no CPU/SPU work to GPU and
  does not change the parked broad-SPU-to-compute conclusion.

Next:

- Rerun the `0x25cc` body battle proof with the same no-pause macro and the
  stricter `BattleRoute` gate before claiming a matched body-vs-stock battle
  speed result.
- If that no-pause body route passes field, tutorial, and active battle
  screenshots, then promote the no-pause macro into the default `TopSlot`
  battle route.

## 2026-05-25 - 0x25cc Body No-Pause TopSlot BattleRoute Matched A/B

Purpose:

- Rerun the `0x25cc` body first-battle proof with the same no-pause TopSlot
  macro used by the repaired stock baseline.
- This was Windows-only on screen 1. No Android, ADB, Thor, GPU offload, or
  200% promotion run was performed.

Command:

```powershell
$macro = 'wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:1000;ls_left:2600;wait:1000;combo:ls_left+ls_down:2200;wait:45000;shot:100;dpad_down:120;wait:500;cross:180;wait:60000;shot:100;wait:60000;shot:100'
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle-topslot-nopause-battleroute-ab -WindowsInputBackend PadApi -WindowsGameScreen 1 -InputMacro $macro -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 315 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Run:

- `debug-captures\windows-lab\20260525-181425-hle-25cc-body-battle-topslot-nopause-battleroute-ab-windows`

Visual verification:

- The shell timeout cut off wrapper post-processing after the run completed, so
  the visual gate was regenerated manually with the same `BattleRoute` rules.
- Visual gate summary: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- First field-like screenshot: `screenshot-0117s.png` at `117s`
  (`2.50 MB`), satisfying the required field-like frame at or before `160s`.
- Later field-like requirement passed at or after `220s`; total field-like
  screenshots found: `14`; invalid screenshots after first field-like: `0`.
- Late battle-like requirement passed: first battle-like screenshot
  `screenshot-0231s.png` at `231s`, red/green ratios `0.400 / 0.269`.
- Manual screenshot checks:
  - `screenshot-0117s.png`: clean unpaused Path to Tenuto field gameplay.
  - `screenshot-0170s.png`: clean first-battle tutorial prompt
    (`View the tutorial? Yes/No`) with Polka HP `900/900`.
  - `screenshot-0231s.png`: clean active first-battle UI with Polka HP
    `900/900`, command UI, and visible `Next` marker.
  - `screenshot-0303s.png`: clean late active first-battle UI.

Logs and host gate:

- `ExternalFail` host-contention gate passed with clean total and external load
  across `5` snapshots.
- `stdout.txt` and `stderr.txt` were empty.
- Serious fatal scan found `0` access violation, SIGSEGV/SIGBUS, assertion,
  Vulkan validation, likely-crashed, unhandled exception, or crash hits. Broad
  text hits were benign config/import/module-stop/stream-stop rows.
- No `rpcs3`, `rpcsx`, or build processes remained active after the run.

Counters:

- Body no-pause window-title FPS samples: `16`; average `117.81 FPS`, minimum
  `113.13 FPS`, maximum `120.10 FPS`.
- Matched stock no-pause baseline
  (`20260525-180238-hle-25cc-stock-battle-topslot-nopause-battleroute-ab-windows`)
  had `16` samples, average `118.15 FPS`, minimum `90.93 FPS`, maximum
  `120.11 FPS`.
- Overall matched delta: body `-0.33 FPS` / `-0.28%` versus stock.
- Battle-only samples at or after first active battle frame (`>=231s`): body
  `14` samples, average `117.89 FPS`; stock `14` samples, average
  `119.95 FPS`; delta `-2.06 FPS` / `-1.71%`.
- Stable late-battle samples (`>=292s`): body `13` samples, average
  `117.96 FPS`; stock `13` samples, average `119.98 FPS`; delta
  `-2.02 FPS` / `-1.68%`.
- Narrow log parser for the `0x25cc` body/shadow rows:
  - body verifier: `770` records, `11538` GET hits, `189038592` bytes,
    `1705 us` total, `10 us` max;
  - shadow verifier: `770` records, `11538` hits, `189038592` bytes,
    output match/mismatch `11538 / 0`, destination changed/unchanged
    `772 / 10766`;
  - family verifier: `770` records, hits/success/fail `23148 / 23148 / 0`,
    `379256832` bytes, `1064081 us` total, `577 us` max.
- The normal GPU-probe summarizer timed out on the `91 MB` log, but all RSX/GPU
  migration flags were off for this run and no CPU/SPU-to-GPU replacement was
  being tested.

Tooling change:

- `tools/eternal_sonata_speed_sprint.ps1` now makes
  `-WindowsBattleLoadRoute TopSlot` use the normalized no-pause loader by
  default instead of adding the post-load `start`/`cross` pause pair.
- Parser check passed: `PSParser OK`.
- `AGENTS.md` now records the TopSlot no-pause default as a standing
  BattleRoute rule.

Classification:

- `valid-matched-no-pause-first-battle-ab`, `valid-first-battle-proof`,
  `spu-hle-codegen-proof`, `not-speed-win`.
- Not `windows-micro-win`, not `gpu-migration-credit`, and not a 200% gate
  candidate.

Reading:

- The no-pause TopSlot route is now proven on both stock and `0x25cc` body for
  field, tutorial prompt, and active first-battle visuals.
- The `0x25cc` body remains correctness-clean (`0` shadow mismatches), but the
  matched no-pause A/B does not show a speed gain. The body path is slightly
  slower overall and clearly slower in the stable battle-only window.
- Do not bank the `0x25cc` body as a micro-win. Treat it as a codegen/HLE proof
  scaffold whose overhead still needs work before it can help the 200% gate.

Next:

- Use the default `TopSlot` route for future battle proofs; it now points at the
  no-pause macro.
- Before another speed A/B for this body, inspect the body/family timing and
  remove verifier/body overhead or narrow the replacement further. Broad
  SPU-to-Vulkan compute remains parked because this route still provides no
  RSX-consumed GPU batch evidence.

## 2026-05-25 - 0x25cc Battle A/B Narrow Summarizer

Purpose:

- The full GPU-probe summarizer timed out on the `91 MB` matched body log, so
  the `0x25cc` battle A/B needed a narrow parser that preserves the useful
  proof numbers without blocking future heartbeats.

Changed:

- Added `tools/summarize_eternal_sonata_25cc_battle_ab.ps1`.
- The tool reads the proven no-pause stock/body BattleRoute pair:
  - stock:
    `20260525-180238-hle-25cc-stock-battle-topslot-nopause-battleroute-ab-windows`;
  - body:
    `20260525-181425-hle-25cc-body-battle-topslot-nopause-battleroute-ab-windows`.
- It writes:
  - `debug-captures/windows-lab/_eternal-sonata-25cc-battle-ab-latest.md`;
  - `debug-captures/windows-lab/_eternal-sonata-25cc-battle-ab-latest.csv`.

Verification:

- Parser check passed: `PSParser OK`.
- Tool run completed in the local Windows repo; no RPCS3/RPCSX/build process was
  active or left running.
- Visual/log gates from the generated summary:
  - stock visual gate: `FIELD_LIKE_PRESENT` / `passed-for-triage`, first field
    `screenshot-0117s.png` at `117s`, first battle-like
    `screenshot-0232s.png` at `232s`, serious fatal hits `0`;
  - body visual gate: `FIELD_LIKE_PRESENT` / `passed-for-triage`, first field
    `screenshot-0117s.png` at `117s`, first battle-like
    `screenshot-0231s.png` at `231s`, serious fatal hits `0`.
- FPS windows:
  - all samples: stock `118.15 FPS`, body `117.81 FPS`, delta `-0.33 FPS` /
    `-0.28%`;
  - battle window (`>=231s`): stock `119.95 FPS`, body `117.89 FPS`, delta
    `-2.06 FPS` / `-1.71%`;
  - stable late-battle window (`>=292s`): stock `119.98 FPS`, body
    `117.96 FPS`, delta `-2.02 FPS` / `-1.68%`.
- `0x25cc` body counters:
  - body verifier: `770` records, `11538` hits, `180.28 MB`, `1705 us` total,
    `0.148 us/hit`, `10 us` max;
  - shadow verifier: `770` records, `11538` hits, `0` mismatches, destination
    changed/unchanged `772 / 10766`;
  - family verifier: `23148` hits, success/fail `23148 / 0`, `361.69 MB`,
    `1064081 us` total, `45.969 us/hit`, `577 us` max.

Classification:

- `not-speed-win`.
- Not `windows-micro-win`, not `gpu-migration-credit`, and not a 200% gate
  candidate.

Reading:

- The matched body run is correctness-clean and still valuable as a codegen/HLE
  scaffold, but the first-battle A/B says it is slower in the windows that
  matter.
- The narrow summarizer is now the cheapest way to answer "how much speed did
  0x25cc body get?" without rerunning the long GPU-probe parser.
- Next speed work should remove verifier/family overhead or narrow the body
  path before spending another full BattleRoute A/B. Broad SPU-to-GPU compute
  remains parked until there is an RSX-consumed batch with proven latency and
  visual correctness.

## 2026-05-25 - Harness Refiner 0x25cc Battle A/B Stop Rule

Purpose:

- The continual harness refiner was still suggesting a generic loader-control
  field movement command after the matched `0x25cc` no-pause BattleRoute A/B
  was already complete. That would repeat an older route-control lane instead
  of acting on the newest performance evidence.

Changed:

- Updated `tools/ps3_harness_refiner.ps1` to detect the newest
  `0x25cc` no-pause top-slot BattleRoute A/B completion.
- Updated `.agents/skills/ps3-continual-harness-refiner/SKILL.md` with the
  reusable rule: when the no-pause `0x25cc` A/B is complete and classified
  `not-speed-win`, do not fall back to generic loader-control movement or rerun
  the same A/B.

Verification:

- Parser check passed: `PSParser OK`.
- `tools/ps3_harness_refiner.ps1 -MaxRuns 8` now writes
  `debug-captures/windows-lab/_ps3-harness-refiner-latest.md` and `.json`
  with this next action:
  - do not add generic route movement;
  - do not rerun the same `0x25cc` A/B;
  - inspect body/family verifier timing, remove measurement overhead, or narrow
    the `0x25cc` body before another matched stock/body comparison.
- The report adds anti-pattern `hle-25cc-nopause-battle-ab-complete` and keeps
  `zero-rsx-local-repeated` active, so broad SPU-to-Vulkan compute remains
  parked.
- No RPCS3/RPCSX/build process was active or left running.

Classification:

- `harness-tooling`, `analysis`.
- Not `windows-micro-win`, not `gpu-migration-credit`, not a speed result, and
  not a 200% gate candidate.

Next:

- Follow the refiner's corrected direction: inspect or reduce the `0x25cc`
  body/family verifier overhead before any new A/B. The current matched A/B
  remains `not-speed-win`.

## 2026-05-25 - 0x25cc BodyFast Overhead Removal And BattleRoute CPU Candidate

Purpose:

- Convert the correctness-clean but slower `0x25cc` body verifier into a
  lower-overhead opt-in path by removing the shadow/family/timing verifier
  costs from the hot path.
- Keep this Windows-only and evidence-locked. No Android, ADB, Thor, GPU
  offload, or 200% promotion run was performed.

Changed:

- `rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp` now supports
  `RPCS3_ES_SPU_HLE_25CC_BODY=fast` / `lean` / `noverify`.
- Fast mode uses the title/image/PC/DMA-family gate and performs the scoped
  GET body path without `get_system_time`, shadow finish/hash/memcmp, or
  family verifier accounting.
- `verify` mode preserves the older shadow/family verifier behavior.
- `rpcs3-upstream\rpcs3\Emu\Cell\lv2\sys_spu.cpp` initializes the Eternal
  Sonata SPU-image signature path when the fast body mode is enabled, even
  without full `RPCS3_ES_SPU_HLE_VERIFY`.
- `tools\windows_rpcs3_lab.ps1` and
  `tools\eternal_sonata_speed_sprint.ps1` now accept
  `-EternalSonataSpuHle25ccBody Fast`.

Verification:

- Parser checks passed for:
  - `tools\windows_rpcs3_lab.ps1`;
  - `tools\eternal_sonata_speed_sprint.ps1`;
  - `tools\summarize_eternal_sonata_25cc_battle_ab.ps1`;
  - `tools\ps3_harness_refiner.ps1`.
- Windows RPCS3 Release rebuild passed:
  `cmake --build build-msvc --config Release --target rpcs3 --parallel 6`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-battle-topslot-nopause-battleroute-ab -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Run:

- `debug-captures\windows-lab\20260525-193449-hle-25cc-bodyfast-battle-topslot-nopause-battleroute-ab-windows`

Visual/log proof:

- Manual visual gate rerun passed `BattleRoute` triage:
  `FIELD_LIKE_PRESENT` / `passed-for-triage`.
- First accepted field: `screenshot-0118s.png` at `118s`, `2.50 MB`,
  clean Path to Tenuto field.
- First battle-like: `screenshot-0231s.png` at `231s`, clean active
  first-battle UI with Polka, command ring, and no obvious corruption.
- Later battle spot check `screenshot-0292s.png` stayed clean.
- Serious fatal scan: `0` real access violation, SIGSEGV/SIGBUS, assertion,
  Vulkan validation, likely-crashed, unhandled exception, or crash hits.
- The run-level `ExternalFail` gate failed only at `postrun` because the Codex
  process spiked after RPCS3 stopped (`codex#2708=16.8%`). In-run external
  samples were clean.

Matched A/B output:

- Summary:
  `debug-captures\windows-lab\_eternal-sonata-25cc-bodyfast-battle-ab-latest.md`
- Visual/log status:
  - stock field `117s`, battle-like `232s`, serious fatal hits `0`;
  - bodyfast field `118s`, battle-like `231s`, serious fatal hits `0`.
- FPS windows versus stock:
  - all samples: stock `118.15 FPS`, bodyfast `119.29 FPS`,
    delta `+1.15 FPS` / `+0.97%`;
  - active battle `>=231s`: stock `119.95 FPS`, bodyfast `120.00 FPS`,
    delta `+0.05 FPS` / `+0.04%`;
  - stable battle `>=292s`: stock `119.98 FPS`, bodyfast `119.99 FPS`,
    delta `+0.02 FPS` / `+0.01%`.
- CPU-load samples:
  - in-run host samples: stock `2`, bodyfast `3`;
  - RPCS3 process CPU average: stock `42.60%`, bodyfast `35.60%`,
    delta `-7.00 pp` / `-16.43%`;
  - total host CPU average: stock `59.75%`, bodyfast `42.20%`,
    delta `-17.55 pp` / `-29.37%`;
  - GPU engine util sum average stayed similar: stock `31.05%`, bodyfast
    `31.67%`.
- Bodyfast counters:
  - body records/hits/bytes: `3037` / `45543` / `711.61 MB`;
  - body timing `0 us`, shadow `0`, family `0`, as intended for fast mode.

GPU/offload reading:

- GPU-probe summary reported `0 B` total observed DMA, `0` direct RSX-local
  traffic records, and `0` indirect RSX overlap for this fast run.
- This is still CPU/SPU HLE/codegen work. It is not GPU migration, not a
  compute-shader offload result, and not a GPU-only speedup.

Classification:

- `valid-matched-no-pause-first-battle-ab`.
- FPS: capped and effectively flat versus stock in active battle
  (`+0.04%`) and stable battle (`+0.01%`), so do not call this a banked FPS
  speed win.
- CPU-load: directional `windows-micro-candidate` only, because the bodyfast
  run had postrun host-gate noise even though the in-run samples were clean.
- Not `gpu-migration-credit`, not `windows-micro-win` yet, and not a 200% gate
  candidate.

Reading:

- The concrete gain found so far is not 10% FPS. It is about `16%` lower
  measured RPCS3 process CPU load while first-battle FPS remains capped around
  `120`.
- Compared with the older body verifier run, bodyfast recovered the verifier
  regression (`117.89 FPS` old body vs `120.00 FPS` bodyfast at `>=231s`),
  but compared with stock it is only a capped-FPS tie.
- Broad SPU-to-Vulkan compute remains parked. This result strengthens the
  CPU/SIMD/HLE/codegen lane, not the GPU-offload lane.

Next:

- Repeat one clean bodyfast BattleRoute or run a fresh stock/bodyfast pair so
  the CPU-load reduction is not discounted by postrun host-gate noise.
- If the repeat remains capped, pivot to a larger `0x451c`/descriptor/list
  HLE or codegen body where removed work can become visible beyond the 120 FPS
  ceiling.

## 2026-05-25 - BodyFast Summarizer And Refiner Update

Purpose:

- Make the harness smarter after the bodyfast result so it does not keep asking
  to remove verifier overhead that has already been removed.

Changed:

- `tools\summarize_eternal_sonata_25cc_battle_ab.ps1` now reports in-run host
  sample CPU separately from FPS and preserves any run-level host gate note.
- `tools\ps3_harness_refiner.ps1` now detects the bodyfast CPU-load candidate
  summary and suggests confirming the CPU-load reduction before pivoting to a
  larger `0x451c`/codegen body.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` now carries the same
  rule.

Verification:

- Parser checks passed.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` now reports:
  `Latest 0x25cc bodyfast BattleRoute has clean field/battle visuals and
  capped FPS, with directional CPU-load reduction but postrun host-gate noise`.
- Suggested next command is a bodyfast BattleRoute repeat with
  `-EternalSonataSpuHle25ccBody Fast`, `TopSlot`, and `BattleRoute` visual
  gate.

Classification:

- `harness-tooling`, `analysis`.
- Not speed evidence by itself, not GPU migration, and not a 200% gate result.

## 2026-05-25 - BodyFast Repeat Confirms CPU-Pressure Stack Component

Purpose:

- Answer whether the `0x25cc` bodyfast gain is stackable after the previous run
  was discounted by postrun Codex host noise.
- Keep this Windows-only on screen 1. No Android, ADB, Thor, GPU offload, or
  200% promotion run was performed.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-battle-topslot-nopause-battleroute-repeat -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Run:

- `debug-captures\windows-lab\20260525-195528-hle-25cc-bodyfast-battle-topslot-nopause-battleroute-repeat-windows`

Visual/log proof:

- Visual gate passed `BattleRoute` triage:
  `FIELD_LIKE_PRESENT` / `passed-for-triage`.
- Manual field spot check: `screenshot-0117s.png`, clean Path to Tenuto field
  at about `117.66 FPS`.
- Manual first-battle spot checks: `screenshot-0230s.png` and
  `screenshot-0320s.png`, clean active battle UI with Polka HP, command ring,
  and no obvious corruption.
- Serious fatal hits: `0`.
- Host gate: clean in-run external samples and no postrun host-gate failure.

Matched A/B output:

- Summary:
  `debug-captures\windows-lab\_eternal-sonata-25cc-bodyfast-repeat-battle-ab-latest.md`
- FPS windows versus stock:
  - all samples: stock `118.15 FPS`, bodyfast repeat `119.83 FPS`,
    delta `+1.68 FPS` / `+1.42%`;
  - active battle `>=231s`: stock `119.95 FPS`, bodyfast repeat `119.94 FPS`,
    delta `+0.00 FPS` / `+0.00%`;
  - stable battle `>=292s`: stock `119.98 FPS`, bodyfast repeat `119.94 FPS`,
    delta `-0.04 FPS` / `-0.03%`.
- CPU-load samples:
  - in-run host samples: stock `2`, bodyfast repeat `3`;
  - RPCS3 process CPU average: stock `42.60%`, bodyfast repeat `37.10%`,
    delta `-5.50 pp` / `-12.91%`;
  - total host CPU average: stock `59.75%`, bodyfast repeat `45.50%`,
    delta `-14.25 pp` / `-23.85%`;
  - worst in-run external grade: `clean` / `clean`.
- Bodyfast counters:
  - body records/hits/bytes: `3046` / `45678` / `713.72 MB`;
  - body timing `0 us`, shadow `0`, family `0`, as intended for fast mode.

GPU/offload reading:

- GPU-probe summary still reported `0 B` observed DMA, `0` direct RSX-local
  records, and `0` indirect RSX overlap.
- This result does not move SPU/PPU/CPU work onto the GPU. It is CPU/SPU
  HLE/codegen pressure relief only.

Classification:

- `windows-cpu-load-micro-win-candidate` / stack component.
- Bank as a stackable CPU-pressure component because the clean repeat preserved
  field and first-battle visuals, stayed fatal-clean, and reproduced at least a
  `5 pp` RPCS3 process CPU drop with clean external host samples.
- Do not call it a banked FPS win: active/stable battle FPS is flat around the
  cap.
- Do not call it `gpu-migration-credit`: migrated GPU bytes remain `0 B`.
- Not a 200% gate candidate.

Harness/report changes:

- `tools\summarize_eternal_sonata_25cc_battle_ab.ps1` now classifies clean
  bodyfast CPU reductions separately from FPS wins, using
  `windows-cpu-load-micro-win-candidate` when host samples are clean and RPCS3
  process CPU drops by at least `5 pp`.
- `tools\ps3_harness_refiner.ps1` now prefers the repeat bodyfast A/B summary,
  treats clean bodyfast as a resolved stack component, and suggests combining
  it with the existing RSX geometry/locality credit stack instead of rerunning
  bodyfast alone.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same standing rule.

Next:

- Stack bodyfast with an already verified Windows credit path, starting with the
  RSX geometry/locality stack (`DepthReadOnly + FastSampled + KeepReadOnly +
  GpuSwap + VertexSuperset Fast + VertexPersistent Fast + IndexPersistent
  Fast`) on the same TopSlot BattleRoute, then verify field and active
  first-battle visuals plus host counters.
- If the combined stack regresses visuals, bisect the RSX side. If it stays
  clean but FPS remains capped, pivot to larger `0x451c`/descriptor/list HLE or
  codegen bodies where removed CPU work can become visible beyond the `120 FPS`
  cap.
