# Thor AArch64 notes moved into AGENTS.md

Read [`AGENTS.md`](AGENTS.md). It is the operating contract AND the hardware
knowledge, in one file, since 2026-08-23.

This file exists so a tool that looks for `CLAUDE.md` finds the way there.

Do not copy content into this file. Two copies of a map disagree.

## If you are here about speed, read these sections of AGENTS.md first

They exist because roughly 28 performance attempts failed before one worked, and
the failures share a single cause: they were chosen by reasoning about mechanisms
instead of by reading a measured cost distribution.

- **The Emulator Is COMPUTE-Bound, Not Wait-Bound. Stop Tuning Backoffs.**
  Every busy-wait together is 7.7% of busy CPU. That caps the entire class.
- **Where The Frame Time Actually Is: The Combat Symbol Profile.**
  55% of cycles are JIT-compiled guest code; 71.4% is six SPU threads.
- **SPU BLOCK SIZE = MEGA IS WORTH +16.5% IN COMBAT.** The one that worked, and
  why the census picked it when intuition did not.
- **An Arm Must PROVE It Engaged, Or Its Null Is Worthless.** The same setting
  produced a false null hours earlier because a config string was rejected for
  case and nothing checked.
- **The Combat Control Pair Disagrees With Itself By 17%.** The noise floor that
  makes small results unreadable.

Still no content here. This list is a signpost, not a second copy.
