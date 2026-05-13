# Thor OODA Debug Issues

This directory is for committed, durable debug issue summaries.

Use `tools/thor_ooda.ps1` as the default capture wrapper. It is game-agnostic by
default, with optional per-game overlays from `debug-profiles/*.json`.

Raw logs, streams, tombstones, pulled config files, and Ghidra projects stay in ignored
`debug-captures/` folders. Each OODA run should create a small tracked issue folder here
with:

- `issue.md`: human-readable diagnosis, links to capture folders, next action.
- `issue.json`: machine-readable profile, repo/device/APK metadata, capture paths.

Do not open GitHub issues for this experiment unless the user explicitly asks. Keep the
workflow local, fast, and commit the markdown/JSON trail to `master`.
