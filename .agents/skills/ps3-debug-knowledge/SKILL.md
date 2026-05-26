---
name: ps3-debug-knowledge
description: Search and maintain repo-local PS3 RPCS3/RPCSX debug knowledge for Eternal Sonata performance work. Use when Codex needs to answer what was already tried, find capture paths, summarize GPU-port accounting, check RSX/SPU/PPU experiment status, avoid rediscovering failed routes, or append durable facts to AGENTS.md/debug-experiments before choosing the next Windows-only GPU migration step.
---

# PS3 Debug Knowledge

## Overview

Use this skill as the project memory before choosing a new optimization or answering "what next?" It searches `AGENTS.md`, experiment ledgers, and repo-local skills, then records durable facts in the narrowest appropriate note.

## Quick Search

Run the helper from the repo root:

```powershell
.\.agents\skills\ps3-debug-knowledge\scripts\ps3_debug_knowledge.ps1 -Query "GPU-port accounting"
```

Common searches:

- `-Query "200%"`
- `-Query "DepthReadOnly"`
- `-Query "RSX-local credit"`
- `-Query "0x25cc"`
- `-Query "battle route"`
- `-Query "do not port"`

Use status mode for the current high-signal project memory:

```powershell
.\.agents\skills\ps3-debug-knowledge\scripts\ps3_debug_knowledge.ps1 -Action Status
```

## Workflow

1. Search before changing code, rerunning an expensive route, or answering status.
2. Prefer evidence from current `AGENTS.md` and `debug-experiments/*.md` over memory.
3. Treat raw capture folders as supporting evidence; durable conclusions belong in Markdown notes.
4. If a search finds conflicting notes, prefer the newest dated entry and mention the older result as superseded.
5. Append durable facts only when they will change a future decision: current best stack, failed route, rollback switch, proof gap, or promotion status.
6. Keep Android/Thor actions out of the plan while the Windows 200% gate is active.

Read `references/query-patterns.md` for search terms that map to the current PS3 performance lanes.

## Recording Rules

Write the durable record in the narrowest location:

- `AGENTS.md`: standing rules, current best proof, promotion gates, and current default workflows.
- `debug-experiments/*.md`: experiment-specific results, failed hypotheses, commands, run dirs, screenshots, and next action.
- `.agents/skills/*`: reusable procedure, not one-off result spam.

Minimum durable fact:

- date;
- subsystem (`RSX`, `SPU`, `PPU`, `MFC`, `input`, `route`, `tooling`);
- exact command or changed gate;
- run directory or source file path;
- visual/FPS/counter result;
- decision label: `gpu-migration-credit`, `windows-micro-win`, `failed`, `parked`, or `gate-candidate`;
- next action.

Do not overwrite user notes or delete old failed entries. Add a new dated correction when the old conclusion is superseded.
