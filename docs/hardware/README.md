# Hardware reference documents

Arm's per-core Software Optimization Guides for the cores in the AYN Thor's
Snapdragon 8 Gen 2 (`kalama`). These are Arm's **Non-Confidential** publications,
redistributed here so the numbers this project relies on cannot silently change
or disappear behind a documentation portal.

| file | core | pages | covers |
| --- | --- | --- | --- |
| `arm_cortex_x3_software_optimization_guide.pdf` | Cortex-X3 (1x prime) | 66 | instruction latency, throughput, pipe assignment |
| `arm_cortex_a710_software_optimization_guide.pdf` | Cortex-A710 (2x mid) | 92 | same, for the older mid cluster |

Thor's full topology is 1x X3 + 2x A715 + 2x A710 + 3x A510. The A715 and A510
guides are not published on the mirrors reachable from here; A715 is the A710's
successor and close enough for scheduling intuition, and the A510 little cores do
not run hot emulator code by design.

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
