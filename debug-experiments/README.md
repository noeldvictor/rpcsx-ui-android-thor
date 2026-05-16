# Debug Experiments

This folder is the durable ledger for performance and compatibility experiments.

Raw logs, screenshots, tombstones, pulled configs, cache dumps, and Ghidra projects stay in ignored `debug-captures/` or local-only scratch folders. Local repro writeups can live in `debug-issues/`. This folder answers the higher-level question: what did we try, why, on which platform, and what happened?

## Rules

- Every serious speed experiment gets a stable ID such as `20260515-eternal-sonata-first-playable-baseline`.
- Record the hypothesis before changing code.
- Mark the platform scope: `shared-core`, `windows-lab`, `android-thor`, or `experimental-gated`.
- Keep risky behavior behind a debug property, config gate, or easy rollback until Android Thor proof exists.
- Separate Windows reasoning from Android proof. Windows can validate structure and correctness, but Thor decides Snapdragon/Adreno speed.
- Do not delete failed experiments. Failed attempts prevent repeat work.

## Status Values

- `proposed`: idea is written down, not measured.
- `measuring`: capture or analysis in progress.
- `windows-pass`: Windows lab supports the idea.
- `android-pass`: Thor proof supports the idea.
- `failed`: disproven, crashed, regressed, or too risky.
- `parked`: plausible, but blocked or lower priority.

## First Canary

Eternal Sonata `BLUS30161` on AYN Thor is the first performance canary. The current goal is to reach the first playable area repeatably, capture a clean baseline, then attack the slow path with SPU/PPU/RSX evidence instead of guessing.
