# 20260820-armsx3-upstream-selective-port

- Status: `measuring`
- Title ID: BLUS30161
- Game: Eternal Sonata
- Platform scope: `android-thor`
- Owner: leanerdesigner
- Created: 2026-08-20
- Last updated: 2026-08-20

## Hypothesis

The Adreno conversion kernels run 32 lanes wide on a 64-wide wave, so half of
each wave is idle on every dispatch. A 64-wide group recovers that half. The
per-block SPU diagnostics and the lv2 container query write to device storage on
the hot path, and a lower log level removes that cost.

## What This Round Ported

Both upstreams were fetched on 2026-08-20:

- `RPCS3/rpcs3` master moved to `243d7db5b`, 10 new commits.
- `ARMSX2/ARMSX3` master moved to `82f21b16d`, 166 new commits. 49 are their
  own; 117 are upstream RPCS3 that they inherited.

Five changes were ported:

| Source | Change | File here |
| --- | --- | --- |
| ARMSX3 `a2f005955` | Qualcomm compute groups go 32 -> 64 | `rpcs3/Emu/RSX/VK/VKCompute.cpp` |
| ARMSX3 `cbee3cd44` | `RPCSX_THOR_CS_GROUP_SIZE` overrides the group size | `rpcs3/Emu/RSX/VK/VKCompute.cpp` |
| ARMSX3 `ab58fb087` | `sys_memory_container_get_size` logs at trace | `kernel/cellos/src/sys_memory.cpp` |
| ARMSX3 `d9a0481dc` | six SPU recompiler diagnostics log at trace | `rpcs3/Emu/Cell/SPU*Recompiler.cpp` |
| ARMSX3 `53e225cf9` | an authentified RPCN with no game stops spinning | `rpcs3/Emu/NP/rpcn_client.cpp` |

The vendor enum here is still the single `QUALCOMM`, not the `ADRENO`/`TURNIP`
split that ARMSX3 uses, so `a2f005955` was adapted, not applied.

## What This Round Rejected, And Why

- **`6161ecd7a` PPU ARM64 float-to-int saturation.** This tree is already ahead.
  Upstream only removes the x86 correction. This tree removes it and also gives
  NaN the PowerPC result of `0x80000000`, which `fcvtns` gets wrong. Porting it
  would be a regression.
- **`82164a54c` SELB XFloat normalization.** Already present at both call sites.
- **`5d2601599`, `c4eff6971` AVX-512 XFloat.** x86 only.
- **`ac897144b`, `07a24cf71` PPU compile OOM.** This tree has its own Scudo OOM
  handling and thermal-headroom probe. See `docs/arm64/ppu-compile-oom.md`. The
  two would collide.
- **`5d71742da` VK pipeline cache persistence.** It depends on their
  `vk_android_loader`, which this tree does not have. 224 lines. Deferred.
- **Framegen (17 commits).** They reverted the whole line themselves in
  `187654eae`.
- **Play-store build, RPCN UI, input, save data.** Their Android application.
  This tree has its own.
- **`65454fef8`, `5a34aeb06` Yakuza FIFO.** A different title.

## Three SPU Log Lines Were Deliberately Left Alone

ARMSX3 `d9a0481dc` demotes eleven diagnostics. Three of them feed the analyzers
here, and those analyzers fail closed:

- `PUTLLC16 Pattern Detected` and `GETLLAR pattern entry point` feed
  `tools/summarize_eternal_sonata_gpu_probe.ps1`.
- `MFC_Cmd` feeds three summarizers, including
  `tools/summarize_eternal_sonata_spu_reservation_loop.ps1`.

Demoting them would make those tools report nothing. Two more lines, `SPU block
is a loop` and `New SPU block compiled successfully`, were already at trace here.
Six were demoted: two `Precompiling` lines, both `Trampoline simplified` lines,
`Likely missed PUTLLC16`, and `MFC_EAH`.

The `Trampoline simplified` pair is the valuable one. It was at error level, and
ARMSX3 counted it about 1500 times in a 15 minute session.

## Gates And Rollback

- `RPCSX_THOR_CS_GROUP_SIZE` sets the compute group size at run time. It takes a
  power of two up to the device limit. Set it to `32` to get the old behaviour
  without a rebuild, which makes the A/B a single build.
- Every other change is a log level or a wait. Revert the commit to roll back.

## Measurement Plan

- Windows: not applicable. The group size change only reaches a Qualcomm device.
- Android Thor: one bounded, temperature-guarded round. Compare 64 against 32
  with `RPCSX_THOR_CS_GROUP_SIZE` on the same build.
- Metrics: frame rate on a fixed route, silicon temperature, log line count.
- Regression checks: the three summarizers above must still report.

## Results

### Windows

Not run.

### Android Thor

Installed, not run. The strict cool gate was bypassed on the user's explicit
instruction, because the device was in use and would not reach the below-35 C
ceiling. Silicon was 43.3 C at install.

- Exact APK `E0F652F5...E04B87`, 73,631,605 bytes, `thortest`, arm64-v8a only.
- Replaced installed `f29fa573...ad6044`.
- Installed hash equals the host hash. `HASH_MATCH=True`.
- `adb install -r`, so user data, caches and checkpoints survive.
- No activity started. PID absent after install, `mResumedActivity` empty.
- Silicon was 43.3 C before and 43.3 C after. The install cost no measurable heat.

This grants installed identity only. Classify it `installed-exact-no-launch` /
`route-tooling`. Grant no speed, FPS, gameplay, flicker, stability, or thermal
credit. The 32-against-64 group-size A/B still needs one bounded round on a free
device, and `RPCSX_THOR_CS_GROUP_SIZE` makes that a single-build comparison.

**Superseded the same day.** The upstream Android UI merge changed the app, so
the device now carries the post-merge build instead:

- Exact APK `C5DE64F6...BD6622`, 73,841,738 bytes, `thortest`, arm64-v8a only.
- It replaced `E0F652F5...E04B87`. The five core ports are identical in both.
- Installed hash equals the host hash. `HASH_MATCH=True`.
- No activity started. PID absent, `mResumedActivity` empty.
- Silicon was 48.2 C before and 47.8 C after. The gate stayed bypassed, on the
  same instruction, because the device was still in use.

The classification does not change. It is still `installed-exact-no-launch` and
still carries no measured credit.

## Evidence

- Captures: none. The install was direct, so it produced no gate capture.
- Logs: none. Nothing was launched.
- Related code: the five files in the table above.

## Decision

`measuring`

## Notes

No speed, FPS, thermal, or stability credit is claimed. The 64-wide group is
ARMSX3's reasoning plus their device measurement, not a measurement made here.
The RPCN fix is almost certainly unreachable on this device, because it needs an
authentified RPCN session and this device boots offline. It was taken for
correctness only.

A comparison against a moving fork has a shelf life of about three days. See
`docs/arm64/armsx3-comparison.md`.
