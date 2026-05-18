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

The interesting idea is real, but the order matters:

1. mine reduced-loop and ARM64 codegen harder;
2. prove and specialize dynamic MFC command shapes at `0x25cc` / `0x451c`;
3. lift any stable bulk body into a tiny recognized-kernel IR;
4. only then test CPU+GPU split with verify-only Vulkan mirrors.

That gives us a path toward CPU/SPU translation to CPU+GPU without repeating the
crash-prone synchronization experiments.
