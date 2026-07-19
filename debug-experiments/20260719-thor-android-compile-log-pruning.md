# Thor Android routine compile-log pruning

Date: 2026-07-19
Status: host-verified `stackable-cpu-pressure`; device-unmeasured

## Problem

The Android logger is now plain, bounded, and event-driven, but routine compile
successes still pay formatting, queue-copy, wake, and file-write costs during
startup. A review of all 24 saved `RPCSX*.log` captures found three remaining
current-source candidates that do not describe failures or changing state.

| Message family | Rows | Captured bytes |
| --- | ---: | ---: |
| Cached PPU module loaded | 1,004 | 129,804 |
| RSX program compiled successfully | 612 | 38,556 |
| ARM64 dot-product feature enabled | 289 | 29,403 |
| ARM64 I8MM feature enabled | 289 | 27,380 |
| **Total** | **2,194** | **225,143** |

## Change

- Android reports the process-stable ARM64 SPU mode, dot-product state, and
  I8MM state once per process instead of twice per translator initialization.
- Android reports successful cached PPU module loads only when PPU Debug is
  enabled. Module-load failures remain unconditional.
- Android compiles out the generic successful-RSX-pipeline row. Its trace-level
  program-ID breadcrumb, every compile failure, and the pipeline notification
  remain intact.
- Desktop diagnostics and success logging are unchanged.

On the same 24-capture mix, this leaves at most one combined ARM feature row per
run: an expected 2,170 of 2,194 message calls removed (98.906%), covering
219.866 KiB of historical records. This is a source/capture projection, not a
new on-device measurement.

## Host verification

- All 54 Thor contract tests pass, including the new
  `tools/test_thor_android_compile_logging.ps1` contract.
- Android ARM64 RelWithDebInfo builds successfully in 129.9 seconds.
- Relevant PPU loader, RSX cache preload, export-surface, and frame-poll tests
  pass; `git diff --check` is clean.
- The shared library retains 34 defined dynamic symbols, 590 explicit
  relocations, 392 `JUMP_SLOT` relocations, 44,293 encoded relocation bytes,
  and all 13 active `thor_es_frame_poll` symbols.
- `cpu_translator::initialize` shrinks from 2,540 to 2,416 bytes; its one-time
  summary helper is 120 bytes, for a selected CPU text total of 2,536 bytes
  (`-4`). `ppu_initialize` grows 32 bytes for the Android debug gate.
- The full debug-bearing core grows from 1,304,706,248 to 1,304,708,688 bytes
  (`+2,440`) due to the guard/debug support. This is a runtime logging-pressure
  reduction, not a binary-size win.
- The old two ARM feature strings and generic RSX success string are absent
  from the Android binary. The PPU success string remains for PPU Debug, and
  the combined ARM feature summary remains.

No APK was installed and no ADB, launch, screenshot, temperature query, or
device workload was performed. No FPS, temperature, flicker, gameplay, or
runtime credit is claimed until a cool-device validation is explicitly allowed.

## Decision

Keep the change. It removes redundant Android startup work while preserving
failures, opt-in debug detail, trace identity, and desktop behavior.
