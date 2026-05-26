---
name: codex-goal-loop
description: Keep long-running Codex Desktop work goal-locked with explicit done gates, checkpoint/resume discipline, and "continue until blocked or complete" behavior. Use when the user asks Codex to keep going, not stop until a target is reached, mimic Ralph-loop/Claude-hook persistence, continue a PS3 speed sprint across many turns, avoid premature finals, create durable resume notes, or decide whether to use a heartbeat/automation for later continuation.
---

# Codex Goal Loop

## Core Rule

Treat the user's goal as a gate, not a vibe. Keep working until the gate is met, a hard blocker requires user input, or the host environment forces a pause.

Do not claim this skill can override Codex Desktop, tool timeouts, context limits, user interruptions, safety limits, or permissions. It is a persistence protocol, not a hidden infinite loop.

## Start A Goal Loop

1. State the current goal in one sentence.
2. Define the done gate as observable evidence: command output, tests, screenshots, FPS delta, ledger entry, commit, or another concrete artifact.
3. Define the current checkpoint: the next smallest useful proof that advances the gate.
4. Read project memory before acting: `AGENTS.md`, relevant `.agents/skills/*`, and the narrowest experiment ledger.
5. Make or update a short plan when the task is more than a single command.

For this repo's PS3 sprint, the default hard gate remains: Windows-only until a stable 200% or better moving-gameplay improvement is proven with correct Eternal Sonata field, menu/Options, and first-battle visuals.

## Continue Discipline

Before sending a final answer, ask:

- Is the done gate actually met?
- Is there one more safe, non-duplicative command, code edit, run, screenshot check, parser check, or ledger update I can do now?
- Did I record enough state that a resumed Codex can continue without rediscovering context?

If the gate is not met and another useful step is available, keep working. Do not end with "next I would..." when the next step is executable now.

If the gate is not met but a hard blocker exists, final with:

- current state;
- exact blocker;
- last valid artifact or run directory;
- next command or edit to run after unblock;
- whether the result is `speed-win`, `gpu-migration-credit`, `not-comparable`, `failed`, `parked`, or another local project class.

## Checkpoint Protocol

Create durable breadcrumbs whenever a run changes future decisions:

- append concise facts to the narrowest ledger under `debug-experiments/`;
- update `AGENTS.md` only for standing rules, current best stack, hard gates, or repeated gotchas;
- include exact commands, run directories, screenshots, host grade, visual status, counters, and decision class;
- mark invalid evidence as `not-comparable` or `failed`, not as progress.

For long sessions, leave a resume block with:

```text
Goal:
Current best evidence:
Open blocker:
Next exact step:
Do not do:
```

## Heartbeat And Resume

Use Codex app heartbeat/automation only when the user explicitly asks to keep this thread waking up later, monitor, remind, or continue after a delay. Prefer a heartbeat attached to the current thread over a detached cron job.

Automation prompts should be self-contained and task-focused. Do not pretend a heartbeat can bypass safety, permissions, or the need for fresh evidence.

## Ralph/Hook Translation

Claude-style stop hooks can feed a continuation prompt back into an agent when it tries to stop. Codex Desktop skill files cannot install such a host-level hook. Translate the idea as:

- a clear done gate;
- a "one more useful action" final-answer check;
- durable resume notes before unavoidable pauses;
- optional heartbeat follow-up when requested;
- no infinite busy loops, no repeated waiting, and no fake completion.

Read `references/claude-hooks-notes.md` when comparing this skill to Claude Code hooks or Ralph-loop behavior.
