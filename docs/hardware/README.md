# Hardware reference documents

Vendor documentation for the AYN Thor's Snapdragon 8 Gen 2 (`kalama`) — Arm's
per-core Software Optimization Guides for the CPU, and Qualcomm's Adreno guide for
the GPU. All are public publications, redistributed here so the numbers this
project relies on cannot silently change or disappear behind a documentation
portal.

## The GPU one, and why it is a separate kind of document

| file | pages | covers |
| --- | --- | --- |
| `qualcomm_adreno_game_developer_guide.pdf` | 200 | Adreno architecture, GMEM, binning, LRZ, FlexRender, Vulkan practice |

The CPU guides answer "how many cycles". This one answers a question this project
has not really asked yet: **the Adreno is a tile-based renderer and the RSX was
not.**

RPCS3's Vulkan backend was written against immediate-mode desktop GPUs, where a
render target lives in VRAM and reading it back costs a transfer. On Adreno,
rendering happens into on-chip **GMEM** a tile at a time, and anything that forces
the tile to be resolved out — a mid-pass readback, a colour-buffer write, a
texture cache miss on a render target — costs a full resolve plus a reload, not a
transfer. The vocabulary to look for is in this document: GMEM, binning passes,
LRZ (early depth rejection), and FlexRender (Adreno switching between binned and
direct rendering).

That matters here specifically because Eternal Sonata's profile sets
`Write Color Buffers: true`, and [`../arm64/rsx-boot-hang.md`](../arm64/rsx-boot-hang.md)
records RSX wedging immediately after three texture cache misses on render-target
addresses. Neither has been examined through a tiler's cost model. **This is the
GPU-side equivalent of the x86-habits review** in
[`../arm64/x86-isms-sweep.md`](../arm64/x86-isms-sweep.md) — desktop-GPU
assumptions that need rethinking for a mobile tiler — and it is unstarted.

## The CPU guides

| file | core | pages | covers |
| --- | --- | --- | --- |
| `arm_cortex_x3_software_optimization_guide.pdf` | Cortex-X3 (1x prime) | 66 | instruction latency, throughput, pipe assignment |
| `arm_cortex_a715_software_optimization_guide.pdf` | Cortex-A715 (2x mid) | 73 | same, for the newer mid pair |
| `arm_cortex_a710_software_optimization_guide.pdf` | Cortex-A710 (2x mid) | 92 | same, for the older mid pair |

| `arm_cortex_a510_software_optimization_guide.pdf` | Cortex-A510 (3x little) | 71 | same, for the little cluster |

Thor's full topology is 1x X3 + 2x A715 + 2x A710 + 3x A510, and **all four are now
covered**.

The A510 guide earns its place despite those cores being kept off hot emulator
code, because it states the reason a measurement here came out the way it did.
The AES benchmark in [`../arm64/aes.md`](../arm64/aes.md) found identical
instructions running **8.8x slower** on an A510 than the X3, which was attributed
to a shared vector unit. The guide says so in as many words:

> Dual-core complexes share the L2 cache and VPU, while single-core complexes have
> a dedicated L2 cache and VPU.

So on Thor's three A510s, two of them are contending for one VPU. That is a
primary-source confirmation of an inference, which is the cheapest kind of
verification available and was not possible before this document was fetched.

**Getting the A715 guide took Playwright**, and the method is worth keeping. Arm's
documentation portal is a JavaScript application, so `curl` and any plain fetcher
receive an empty shell — an earlier pass concluded from that the guide "is not
published on the mirrors reachable from here", which was wrong. Driving a real
browser and watching network responses for
`documentation-service.arm.com/static/...` produced the URL immediately:

```
https://documentation-service.arm.com/static/6419bb9a8df5201251be08c3?token=
```

`developer.arm.com/documentation/<DOC-ID>/latest/` 302s to `support.arm.com`, and
`waitUntil: 'networkidle'` never fires on that portal — use `domcontentloaded`
plus a fixed settle. The same recipe should retrieve the A510 guide and Qualcomm's
Adreno material, neither of which has been tried.

**How to read a table.** Every instruction row gives execution latency, execution
throughput, and *utilized pipelines*. The pipeline symbol is the part that is
easy to miss and often decides the answer:

    V    FP/ASIMD 0/1/2/3   all four pipes
    V01  FP/ASIMD 0/1       two pipes
    V13  FP/ASIMD 1/3       two pipes
    V0   FP/ASIMD 0         one pipe

An instruction that saves an operation but lands on `V0` can still lose to a
two-instruction sequence that spreads across `V`. See the BCAX entry in
`CLAUDE.md`, which is exactly that case.

Extracting text: `pypdf` works, a naive stream scrape does not, because the body
uses font subsetting and only the cover page survives.

## What is deliberately not here

The **Arm Architecture Reference Manual for A-profile** (`aarch64.pdf`, roughly
14,000 pages, 65.9 MB) is a different kind of document and is not vendored:

    https://www.scs.stanford.edu/~zyedidia/docs/arm/aarch64.pdf

It specifies instruction *semantics* and *encodings*. It contains **no timing
data at all**, because timing is per-implementation and lives in the guides
above. It is the correct reference for the RawSPU MMIO instruction decoder in
`CLAUDE.md`'s ledger, which needs load/store encodings, and the wrong reference
for any question about speed.

`CLAUDE.md` records one error already made by reasoning from it without checking
the part: the ESR syndrome fields, which the architecture defines and this
silicon reports as zero for ordinary stage-1 faults. Fetch it for encodings when
that work starts, keep it out of git, and do not consult it about performance.
