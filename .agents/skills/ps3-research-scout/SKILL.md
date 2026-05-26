---
name: ps3-research-scout
description: Research PS3 emulation, CPU/SPU/PPU/RSX translation, GPU offload, Vulkan/Adreno, compiler, and academic performance ideas for this repo. Use when Codex should search academic or primary sources, synthesize lateral speed ideas, compare papers to Eternal Sonata/AYN Thor evidence, and update debug-experiments reports without using global research skills.
---

# PS3 Research Scout

## Scope

Use this repo-only skill for research and synthesis. It should produce decisions and experiment candidates, not broad implementation changes.

Compose it with:

- `ps3-debug-knowledge` to check what this repo already proved.
- `ps3-speed-proof-gate` to keep claims honest.
- `ps3-rsx-experiment-gate` for GPU/RSX feasibility.
- `thor-spu-codegen-hotpath` for SPU/codegen feasibility.
- `thor-experiment-ledger` to record durable conclusions.

## Source Rules

- Search the web when facts, APIs, tool capabilities, papers, or product specs may have changed.
- Prefer primary sources: papers, official docs, vendor docs, project blogs, specs, source repos.
- For academic claims, capture the mechanism, not just the title.
- Include source links in reports.
- Mark anything inferred from sources as inference.
- Do not cite hype as proof. Translate sources into testable repo hypotheses.

## Research Workflow

1. Search repo memory first:

```powershell
.\.agents\skills\ps3-debug-knowledge\scripts\ps3_debug_knowledge.ps1 -Action Status
```

2. State the concrete question:
   - Can this move CPU/SPU/PPU work to GPU?
   - Is CPU SIMD/HLE better than Vulkan here?
   - Does RSX-local residency remove barriers/readbacks?
   - Does the paper require batching, many instances, or relaxed synchronization?
3. Read sources selectively. Do not bulk-load unrelated papers.
4. Convert each useful idea into:
   - target subsystem;
   - title/signature gate;
   - required proof capture;
   - expected win mechanism;
   - correctness risks;
   - rollback switch;
   - next smallest experiment.
5. Record conclusions in the narrowest `debug-experiments/*.md` report and update `AGENTS.md` only for standing rules.

## Idea Filters

Good candidates:

- batched data-parallel SPU/RSX-adjacent work;
- RSX-consumed texture, resolve, blit, swizzle, decode, particle, skinning, or render-prep buffers;
- recognized-kernel IR that can lower to CPU SIMD first and GPU/SPIR-V when large enough;
- GPU shadow verification that does not block the critical path.

Bad candidates unless a trace proves otherwise:

- one GPU dispatch per tiny SPURS event, semaphore, MFC command, or PPU syscall;
- immediate CPU readback after compute;
- reservation/atomic loops without exact verifier history;
- broad "SPU emulator on GPU" rewrites.

## Output Shape

For reports, include:

- question and current repo evidence;
- sources used;
- source-derived mechanisms;
- project translation;
- ranked next experiments;
- rejected ideas and why;
- exact Windows-only command or capture needed when applicable.
