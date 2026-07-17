# ARM64 SPU upstream slice audit ? 2026-07-17

## Scope

- Target: AYN Thor Max, Android ARM64, Eternal Sonata `BLUS30161`.
- Upstream reference: local `rpcs3-upstream` checkout through July 2026.
- Android base before this slice: `1f622a134`.
- Thermal policy: host-only audit and build. No ADB query, install, launch, or
  gameplay route was performed.
- Reduced-loop emission remains retired. This slice does not re-enable it.

## Compatibility classification

The audit rewrote upstream `rpcs3/` paths to the vendored
`app/src/main/cpp/rpcsx/rpcs3/` paths, then ran forward and reverse
`git apply --check` against the current Android tree.

| Classification | Upstream commits | Decision |
| --- | --- | --- |
| Forward-clean | `1ec3de9`, `3301674`, `2f2ac69` | Port `1ec3de9` and `2f2ac69`; skip `3301674` because it fixes big-endian host channel waits and Thor is little-endian ARM64. |
| Already exact | `03647fd`, `e3b1b55` | No action. |
| Outside the filtered source paths | `d25972e`, `5758ab1`, `6647c5a` | `d25972e` is already covered by the Android tree's stricter `use_spu_i8mm()` JIT feature gate. The other two are non-performance compatibility fixes outside this title's active path. |
| Diverged, partial, or dependency-bound | `1627757`, `4542020`, `45c6e93`, `7d0df30`, `320e8d6`, `53d76db`, `61a2604`, `7e436f9`, `dff29a7`, `a87d175`, `2d1be09`, `4a92d96`, `6349ea2`, `3164d44`, `e429f8c`, `18fe6ee`, `35f65c2`, `fa5b899`, `3f27cb8`, `09d602f`, `a7fc31f`, `700ca26` | Do not force whole-commit ports. Several overlap existing Android UDOT, shuffle, FCGT, checksum, and I8MM slices; the rest require newer shared analyzer/emitter structure. |
| Unavailable in the shallow reference | `f39d82f` | No claim; the referenced object was not locally available and the offline audit did not fetch it. |

SVE and SVE2 candidates were excluded from Thor promotion. They are not enabled
without an observed device feature report and a separate correctness proof.

## Selected upstream slices

### `1ec3de9` ? SPU analyzer no-regmod fix

The analyzer now exits the default register-modification path when
`spu_itype::zregmod` is set. This prevents an instruction that does not modify
a target register from poisoning `m_regmod`. It is a five-line,
source-compatible correctness fix and does not alter the Android gate surface.

### `2f2ac69` ? idiomatic ARM64 FSM lowering

ARM64 lowering for `FSM`, `FSMH`, `FSMB`, and `FSMBI` now uses vector
mask/compare forms that upstream reports compile to two NEON instructions,
instead of LLVM's scalar fallback. The non-ARM64 path is unchanged. The patch is
29 lines, architecture-gated, and applied without prerequisite refactors.

No Eternal Sonata opcode-frequency proof exists for these four instructions, so
this is a plausible general ARM64 codegen improvement, not a measured game FPS
claim.

## Validation

Command:

`gradlew.bat :app:buildCMakeRelWithDebInfo[arm64-v8a] --no-daemon --console=plain --offline`

Result:

- `BUILD SUCCESSFUL`.
- Built native artifact:
  `app/build/intermediates/cxx/RelWithDebInfo/724a6w64/obj/arm64-v8a/librpcsx-android.so`
- Size: `1,351,013,200` bytes.
- SHA-256:
  `D9077BB56FC92459A1663D9F4493B7150EB2CDB6091E85E26762E01EEE6DA654`
- `git diff --check`: clean.

## Promotion state

Classification: `build-proven`, `device-unmeasured`.

This slice receives no Thor FPS, frame-pacing, flicker, or stability credit yet.
A future cool-device round must use the established field, first-battle, and
menu route and stop immediately on a fatal VM/SPU fault or visible corruption.
