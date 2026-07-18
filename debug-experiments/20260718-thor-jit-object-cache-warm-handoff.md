# 2026-07-18 Thor JIT Object-Cache Warm Handoff

## Result

- Confirmed that fully warm PPU cache objects were read, inflated, and parsed
  in `jit_compiler::check`, discarded, then read, inflated, and parsed again
  in `jit_compiler::add`.
- Implemented a validated decompressed-buffer handoff from cache discovery into
  linking.
- Corrupted-cache detection still parses every object before accepting it.
- Any cache miss releases all retained warm buffers before compilation, so
  cold/partial-cache peak-memory behavior is preserved.
- ARM64 native compilation, ARM64-only optimized ThorTest packaging, and all
  focused contracts pass.
- Classify this as `host-only-candidate` and `not-comparable`.
- No install, launch, or device query ran after the preceding thermal failure.

## Evidence and scope

The failed zero-copy proof still produced a full log:

`debug-captures/android-speed-sprint/20260718-123726-thor-input-jit-object-cache-zero-copy-bounded-title-proof/failure-RPCSX.log`

It loaded 47 cached PPU objects:

- 42 EBOOT objects;
- 5 runtime/PRX objects.

The source path performed two full cache materializations for every warm hit:

1. `PPUThread.cpp` called `jit_compiler::check(path)`;
2. `check` called `ObjectCache::load(path)`, which read and inflated the
   `.gz` file and parsed the resulting object;
3. the validated buffer was destroyed;
4. linking called `jit_compiler::add(path)`;
5. `add` called `ObjectCache::load(path)` again and repeated the read and
   inflation before parsing and handing the object to LLVM.

The comparison checkout at RPCS3 commit
`a18afa4037b25af1b285cdf109e1d6250b478234` retains the same
validate-then-reload flow in `PPUThread.cpp` and `Utilities/JITLLVM.cpp`.
This is a local successor, not an upstream cherry-pick.

## Host implementation

- `jit_compiler::check` now returns an opaque owning
  `jit_object_buffer` only after LLVM successfully parses the object.
- Fully warm PPU module sets retain those validated buffers and move them into
  the linking JIT, avoiding the second disk read and gzip inflation.
- `jit_compiler::add` still parses the handed-off bytes before LLVM engine
  ownership. This preserves the previous add/link failure behavior.
- The first miss disables handoff for the entire module set and releases every
  retained buffer before any compilation worker starts. Partial/cold sets
  therefore keep the old memory lifetime and reload path.
- The raw uncompressed-cache fallback and compressed-cache format are
  unchanged.
- One low-volume notice reports
  `LLVM: Reusing N validated warm-cache object buffers.` so a later guarded
  run can prove activation without verbose compiler logging.

The existing zero-copy vector owner remains underneath this handoff. Together,
the warm path removes both the redundant post-inflate memcpy and the second
read/inflate pass. This does not reduce RSX or SPU preload work and is not yet a
thermal or FPS result.

## Host verification

- `tools/test_thor_jit_object_cache_handoff.ps1`: pass.
- `tools/test_thor_jit_object_cache_buffer.ps1`: pass.
- ARM64 RelWithDebInfo native build: pass.
- ARM64-only optimized ThorTest assembly: pass.
- ThorTest APK ABI contract: pass.
- optimized test-hook contract: pass.
- core export/relocation contract: pass (34 dynamic exports, 583 explicit
  relocations, 391 `JUMP_SLOT` relocations, 44,219 encoded relocation bytes).
- strengthened thermal guard contract: pass (56 C probe, confirmed-near-limit
  stop, 68 C early stop, 72 C hard limit).
- `git diff --check`: pass before ledger update.

Exact host-only ARM64 ThorTest artifact:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,574,878` bytes.
- APK SHA-256:
  `5750F2C10F47C40E68456D7AC758994DDB94B34F1C69F180E9DE6D0343ED10C6`
- Merged ARM64 core size: `1,305,637,664` bytes.
- Merged ARM64 core SHA-256:
  `065C901B5666D76B664D2FA4BEB8FBA9A6D068980AE45326FF2795E3145347E8`
- Packaged stripped core size: `62,848,408` bytes.
- Packaged stripped core SHA-256:
  `10D94CD9DEC1222FD5C81E60C1539D759EDC15F4AD0A32D9B2741830A5C60671`

The artifact is uninstalled and `device-unmeasured`. The Thor remains stopped
on the prior exact zero-copy APK
`E69D671D2B6F74BAC6DEAF2A3A08D7DC98877B0F8654E7C89AC2A0BA68B6C509`.

## Next guarded step

Do not touch the Thor again after the `78.3 C` failure. A later independently
cool round may install this exact APK without launch. Only a different cool
round may spend one bounded proof using the repaired 56 C confirmed-probe
guard.

Promotion requires:

1. exact on-device APK identity;
2. activation summaries totaling the expected warm objects;
3. no partial-cache fallback or object-load failure;
4. lower PPU cached-object timing and safer temperature slope;
5. eventual title/menu, field, and first-battle correctness.

Reject it as a thermal solution if it only saves milliseconds and still reaches
the confirmed-probe stop before title.
