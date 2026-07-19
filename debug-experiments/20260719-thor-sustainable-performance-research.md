# Thor Sustainable PS3 Performance Research Audit

Date: 2026-07-19

## Question

Which current upstream, Android, Qualcomm, and systems-research ideas can make
PS3 emulation on AYN Thor faster at a lower sustained temperature without
trading away correctness?

This is a host-only research and prioritization note. No Thor interaction
occurred.

## High-confidence near-term lanes

### 1. Remove unnecessary wakeups at the measured guest boundary

The local matched Windows result remains the strongest direct lead: the
one-millisecond Eternal Sonata frame-poll wait cut title polling calls by about
79.9% and reduced matched battle host CPU mean by about 14.2%. Two milliseconds
was worse and was rejected. This is more directly applicable than a broad
power cap because it removes work rather than merely slowing it.

The 2026 GPU energy study also reports workload-dependent efficiency regimes
and finds frequency reduction generally more effective than blunt power caps
in its tested datacenter GPUs. It is not an Adreno result, but it reinforces
measuring a scene-specific operating point instead of assuming maximum clocks
are most efficient:
<https://arxiv.org/abs/2607.00819>.

### 2. Use Android's sustainable-performance controls around real work

Current Android game guidance recommends the Thermal API, Game Mode/State, and
Performance Hint sessions. Android 15 can express a preference for power
efficiency on a hint session:

- <https://developer.android.com/games/optimize/adpf>
- <https://developer.android.com/games/optimize/adpf/thermal>

The fork already has a default-off, API-gated RSX Performance Hint candidate
including optional power-efficiency preference. Do not duplicate it or promote
it without matched Thor evidence. Thermal headroom should be sampled no more
than once per ten seconds and may adapt only optional compiler/preload worker
budgets, never guest semantics, emulation fidelity, or correctness-critical
timing.

### 3. Reduce peak startup concurrency

Existing Thor evidence shows an early startup spike while PPU, SPU, and RSX
cache work overlaps. The default-off cache-phase pacing candidate serializes
some of that optional work. It may reduce peak power but can increase time to
title, so its future acceptance gate is temperature slope plus time-to-title,
not temperature alone.

Qualcomm's current game developer guide highlights Adreno tiling, UBWC, thread
scheduling/affinity, and NEON as optimization areas:
<https://docs.qualcomm.com/bundle/publicresource/topics/80-78185-2/landing.html?product=1601111740035277>.
For this emulator, scheduling and affinity deserve measurement before format or
render-path churn because the clean battle trace accounts for only about 2.1
milliseconds of RSX stages in a 33.3 millisecond frame.

## Research that informs longer-term work

Partial cross-compilation research selectively offloads eligible functions
from a DBT environment to native host code and reports up to 13x on its
LLVM/QEMU workloads. That headline is not transferable to RPCS3. Its useful
lesson is narrower: native offload pays only when the boundary is infrequent
and state-marshalling cost is controlled:
<https://arxiv.org/abs/2512.00487>.

The clean Eternal Sonata profiles reject the current PPU and SPU blocks for
that approach: nearly every leading guest PPU block has one sample per entry,
and the leading battle SPU body crosses roughly 238 times per second.

Learned DBT translation-rule work reports 1.36x on SPEC CINT2006 and 1.15x on
its real applications, with gains partly from fewer and cheaper CPU-state
coordination points:
<https://arxiv.org/abs/2402.09688>.
For RPCS3, the actionable analogue is to profile state synchronization and
dispatcher boundaries, then optimize a repeated coordination pattern only
after identifying it. Training a translation-rule system is a long-term
research project, not the next Thor patch.

## Rejected immediate moves

- Do not add an RSX upload, draw, or present superpath from the current trace;
  measured RSX stages are far below the frame budget.
- Do not add a native PPU/SPU body with a high-frequency transition boundary.
- Do not raise sustained clocks or disable thermal protection.
- Do not count upstream correctness imports as speedups.
- Do not use temperature alone as a success metric; require field and battle
  correctness, frame pacing, and matched workload duration.

## Ranked next device proofs, only when independently cool

1. Reconfirm the one-millisecond frame-poll candidate against off using exact
   matched title, field, and first-battle gates.
2. Compare cache-phase pacing off/on in separate cool rounds, recording thermal
   slope and time-to-title.
3. Compare the existing ADPF RSX hint off/on only after the first two are
   resolved.
4. Collect scheduling/affinity evidence before writing another core hot path.

Every proof retains the strict multi-sensor guard and early stop. A neutral or
hotter result is parked rather than stacked into the default configuration.
