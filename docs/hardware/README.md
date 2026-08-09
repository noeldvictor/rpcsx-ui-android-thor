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

## Qualcomm Snapdragon platform documents

`qualcomm_snapdragon_opencl_optimization_guide.pdf` — *Snapdragon Mobile Platform
OpenCL General Programming and Optimization*, 80-NB295-11 Rev. C, 116 pages.
Fetched from `docs.qualcomm.com/bundle/publicresource/`.

It is an **OpenCL** guide and this emulator uses Vulkan, so the API half does not
transfer. The hardware half does, because it describes the part rather than the
API:

* Adreno cache line is **64 bytes** on most generations (p17-18) — worth holding
  next to the 128-byte PS3 reservation line, which is two of them.
* The GPU and CPU share physical memory. Zero-copy is not an optimization on this
  part, it is the absence of a mistake: any path that stages through a separate
  allocation is paying for a copy the hardware never needed (7.4, p57-58).
* Coalescing, L1/L2 behaviour and burst sizes are properties of the memory system
  and apply to Vulkan traffic just as much as to OpenCL kernels.

**The SoC-level manual is not public.** The Snapdragon 8 Gen 2 / SM8550 *Hardware
Register Description* is distributed to Qualcomm partners and HDK purchasers
through Lantronix's technical portal; the data sheet (80-33265-1) surfaces only on
Scribd behind a paywall. Neither is fetchable, and guessing at
`docs.qualcomm.com` URLs is actively misleading — one guessed path returned
**HTTP 200 with an HTML error page**, which `file` catches and a size check
catches, but a bare `curl -o` does not. Verify every download with `file` and a
`pypdf` page count before believing it.

# Snapdragon 8 Gen 2 coverage: what is here, block by block

The device reports `ro.soc.model=QCS8550`, `ro.board.platform=kalama` — the
Snapdragon 8 Gen 2. There is no single "chipset manual" for it in public
circulation, so the question worth answering is not *"do we have the manual"* but
*"is every block of this chip documented here"*. Measured cluster layout from the
device, matching the power probe's three groups:

| block | this device | document here |
| --- | --- | --- |
| Prime core | 1× Cortex-X3 @ 3187 MHz (`cpu7`) | `arm_cortex_x3_software_optimization_guide.pdf` |
| Performance | 2× Cortex-A715 + 2× A710 @ 2803 MHz (`cpu3`–`cpu6`) | `arm_cortex_a715_…pdf`, `arm_cortex_a710_…pdf` |
| Efficiency | 3× Cortex-A510 @ 2016 MHz (`cpu0`–`cpu2`) | `arm_cortex_a510_software_optimization_guide.pdf` |
| Instruction set | Armv9-A | `arm_architecture_reference_manual_DDI0487M_c.pdf` (17,145 pp) |
| GPU | Adreno 740 | `qualcomm_adreno_game_developer_guide.pdf` (200 pp) |
| GPU compute / memory system | Adreno 740, UMA | `qualcomm_snapdragon_opencl_optimization_guide.pdf` (116 pp) |

Every execution block the emulator touches is covered. The CPU guides are not
generic Arm material — the X3, A715, A710 and A510 *are* this chip's cores.

**What is genuinely missing, and why.** The SM8550 *Hardware Register
Description* (the LM80-P0436 class of document) and the SM8550 data sheet
(80-33265-1) are not public. Qualcomm ships the register description to
partners; Lantronix, who sell the 8 Gen 2 HDK, state that schematics and manuals
reach only purchasers through their technical portal. The data sheet appears
only on Scribd behind a paywall. Both were searched for from several directions.

**What was found, inspected and deliberately not vendored.** Qualcomm publishes
Product Briefs under `docs.qualcomm.com/bundle/publicresource/87-*`, including
one for the 8 Gen 2. It was downloaded and read: two pages of marketing copy with
no technical content. Adding it would make this directory look more complete
without making it more useful. The `87-*` numbers are briefs; the `80-*` numbers
are the technical guides, which is why both Qualcomm documents here are `80-*`.

**The register description would not help much anyway.** It documents SoC
peripheral registers — clocks, interconnect, camera, modem — for people writing
kernel drivers. This project writes a userspace emulator on top of Android's
drivers and Mesa's Turnip. The questions it actually has are instruction timing
(the Arm core guides), instruction semantics (the Arm ARM), and GPU behaviour
(the Adreno guides). That is the material that has produced findings.

## The Arm Architecture Reference Manual

Issue **M.c**, **17,145 pages**, 120 MB, committed as three ~40 MB parts:

    arm_architecture_reference_manual_DDI0487M_c.pdf.part00
    arm_architecture_reference_manual_DDI0487M_c.pdf.part01
    arm_architecture_reference_manual_DDI0487M_c.pdf.part02

Rebuild it with `sh docs/hardware/assemble_arm_arm.sh`, which concatenates the
parts and checks the SHA-256. The assembled PDF is gitignored.

Split rather than stored whole because 120 MB is over GitHub's hard 100 MB
per-blob limit, and **Git LFS is not available on this repo** — GitHub refuses
LFS uploads to a public fork, since the objects would bill to the upstream
owner:

    batch response: @noeldvictor can not upload new objects to public fork

Each part is also under the 50 MB warning threshold.

This is the manual referenced in the video that set this project's direction
("PS3 emulation is fast on ARM now"), where the RPCS3 team describe scouring
*"every page of an ARM Architecture manual with over 17,000 pages"*. The page
count identifies it exactly: **M.c has 17,145 pages**, the widely mirrored H.a
has 11,530.

An earlier revision of this README argued against vendoring it, on the grounds
that it specifies semantics and encodings and contains no timing data. That
reasoning is still correct and still worth heeding — **it remains the wrong
reference for any question about speed**, and `CLAUDE.md` records an error
already made by reasoning from it without checking the part (the ESR syndrome
fields). It is here because it was asked for and because it is the source the
upstream ARM64 work was done from, not because that caveat has been withdrawn.

### Getting the current issue

Do not guess CDN paths; every pattern tried returned 404, and one guessed
Qualcomm path returned **HTTP 200 with an HTML error page**. Arm publishes a
JSON index that names the current issue and its download URL:

```
curl -sS "https://documentation-service.arm.com/documentation/ddi0487/latest?lang=en&baseUrl=/documentation"
```

`_links.resources[0]` carries `name` (e.g. `DDI0487M_c_a-profile_architecture_reference_manual.pdf`)
and `href` (a `documentation-service.arm.com/static/<id>?token=` URL that fetches
with plain `curl`). This is simpler than the Playwright network-sniffing recipe
below and should be tried first — Playwright is still how you *find* the endpoint
when a portal changes, which is how this one was found.

Always verify a download with `file` and a `pypdf` page count. A status code is
not evidence.

## What is deliberately not here

Nothing, currently. The Arm Architecture Reference Manual used to be listed here
and is now vendored above under LFS.
