# Hardware reference documents

Arm's per-core Software Optimization Guides for the cores in the AYN Thor's
Snapdragon 8 Gen 2 (`kalama`). These are Arm's **Non-Confidential** publications,
redistributed here so the numbers this project relies on cannot silently change
or disappear behind a documentation portal.

| file | core | pages | covers |
| --- | --- | --- | --- |
| `arm_cortex_x3_software_optimization_guide.pdf` | Cortex-X3 (1x prime) | 66 | instruction latency, throughput, pipe assignment |
| `arm_cortex_a715_software_optimization_guide.pdf` | Cortex-A715 (2x mid) | 73 | same, for the newer mid pair |
| `arm_cortex_a710_software_optimization_guide.pdf` | Cortex-A710 (2x mid) | 92 | same, for the older mid pair |

Thor's full topology is 1x X3 + 2x A715 + 2x A710 + 3x A510, and the first three
are now all covered. Only the A510 guide is missing, and those little cores are
kept off hot emulator code by design — though note the AES measurement in
[`../arm64/aes.md`](../arm64/aes.md), where the same instructions ran **8.8x
slower** on an A510 than on the X3, because each A510 pair shares one vector unit.
When something does land there, it lands hard.

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
