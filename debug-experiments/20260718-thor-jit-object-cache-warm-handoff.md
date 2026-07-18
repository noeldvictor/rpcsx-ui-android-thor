# 2026-07-18 Thor JIT Object-Cache Warm Handoff

## Result

- Confirmed that fully warm PPU cache objects were read, inflated, and parsed
  in `jit_compiler::check`, discarded, then read, inflated, and parsed again
  in `jit_compiler::add`.
- Implemented a validated parsed-object handoff from cache discovery into
  linking, including the object's owning decompressed buffer.
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

- `jit_compiler::check` now returns an opaque owning `jit_object_cache` only
  after LLVM successfully parses the object. Its private implementation keeps
  LLVM's parsed `ObjectFile` and the decompressed backing `MemoryBuffer`
  together as an `OwningBinary`.
- Fully warm PPU module sets retain those validated parsed objects and move
  them directly into the linking JIT, avoiding the second disk read, gzip
  inflation, and object parse.
- The empty-handoff path in `jit_compiler::add` keeps the original load and
  parse behavior for cold/partial fallback.
- The first miss disables handoff for the entire module set and releases every
  retained buffer before any compilation worker starts. Partial/cold sets
  therefore keep the old memory lifetime and reload path.
- The raw uncompressed-cache fallback and compressed-cache format are
  unchanged.
- One low-volume notice reports
  `LLVM: Reusing N validated warm-cache objects.` so a later guarded
  run can prove activation without verbose compiler logging.

The existing zero-copy vector owner remains underneath this handoff. Together,
the warm path removes the redundant post-inflate memcpy and the second
read/inflate/parse pass. Every fully warm object is materialized and parsed
once. This does not reduce RSX or SPU preload work and is not yet a thermal or
FPS result.

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
- `git diff --check`: pass before ledger update; final check repeated after the
  record update.

Exact host-only ARM64 ThorTest artifact:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,574,522` bytes.
- APK SHA-256:
  `39EE3277C6CE1657129B199A6BF9BF21ADB307CFF8ECAF80C84CB4123EDD0D81`
- Merged ARM64 core size: `1,305,643,544` bytes.
- Merged ARM64 core SHA-256:
  `5099BD531D49CF614F83598C8762F095F2A7375E1797D025EF56EEE37E2E908D`
- Packaged stripped core size: `62,849,256` bytes.
- Packaged stripped core SHA-256:
  `C8B55B9CB7DD81D3BEB83F819F6A49FDD252753B32ECF6F12166D8E0F7D934AC`

This supersedes the earlier uninstalled buffer-only host artifact
`5750F2C10F47C40E68456D7AC758994DDB94B34F1C69F180E9DE6D0343ED10C6`.

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
