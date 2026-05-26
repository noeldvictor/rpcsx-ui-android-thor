# Claude Hooks Notes

Use this reference only when the user asks to compare Codex persistence with Claude Code hooks, Ralph-loop behavior, or stop-hook automation.

## What Claude Code Hooks Provide

Anthropic's Claude Code hooks are shell commands attached to lifecycle events such as `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, and `SubagentStop`.

The important idea for persistence is the `Stop` event: a hook can inspect or block completion and provide feedback that the agent sees. Ralph-style loops use that idea to tell the agent to continue when a broad goal is not done.

## What Codex Skills Can Provide

Repo-local Codex skills provide instructions and reusable scripts/resources. They do not install host lifecycle hooks and cannot force Codex Desktop to ignore stop conditions, context limits, safety policy, tool failures, user interruptions, or final-answer boundaries.

The useful portable pattern is:

1. define an observable done gate;
2. run the next concrete step instead of ending early;
3. write durable checkpoints before unavoidable pauses;
4. use a thread heartbeat only when the user asks for delayed continuation.

## Anti-Patterns

- Do not create an infinite "continue" loop with no progress check.
- Do not rerun the same command repeatedly without new evidence.
- Do not let a persistence skill override visual correctness, benchmark gates, safety rules, or user instructions.
- Do not call an incomplete state "done" because the current chat turn is getting long.
