# Eternal Sonata RSX GPU Residency Plan

- Status: `tooling-ready`
- Game: Eternal Sonata `BLUS30161`
- Device target: AYN Thor Max first
- Created: 2026-05-18

## Working Definition

`RSX on GPU` should not mean moving the RSX command processor to a compute
shader. In this emulator, RSX command decoding, state tracking, sync, and queue
submission should stay CPU-side.

The useful target is RSX GPU residency:

- fewer CPU/GPU drain points;
- fewer render-pass breaks on Adreno;
- narrower barriers and fences;
- less host-visible transfer ping-pong;
- more texture/vertex/render-target data staying in Vulkan resources;
- pipeline warmup separated from steady-state FPS analysis.

## New Tool

Added:

```powershell
.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir RUN_DIR
```

The script reads `Thor RSX Auditor:` log lines from a run folder or explicit
log file and writes:

- `eternal-sonata-rsx-auditor-summary.md`
- `eternal-sonata-rsx-auditor-records.csv`

It parses both old and newer auditor formats, including:

- queue submits, waits, signals, flush requests, and hard syncs;
- render-pass begin/end and barrier breaks;
- global/buffer/image/texture/all-command barriers;
- barrier-tracked MB;
- texture barrier color/depth/skips when present;
- DMA transfer fences to `ALL_COMMANDS` or `HOST`;
- pipeline graphics/compute/slow creation counts and total creation time;
- detile and simple-upload bytes.

## Old Capture Re-Read

Input:

```powershell
.\tools\summarize_eternal_sonata_rsx_auditor.ps1 `
  -RunDir debug-captures\android-speed-sprint\20260516-101045-eternal-sonata-field-stock-qualcomm-scene `
  -Top 8
```

Output:

- `debug-captures/android-speed-sprint/20260516-101045-eternal-sonata-field-stock-qualcomm-scene/eternal-sonata-rsx-auditor-summary.md`
- `debug-captures/android-speed-sprint/20260516-101045-eternal-sonata-field-stock-qualcomm-scene/eternal-sonata-rsx-auditor-records.csv`

Totals across 106 auditor intervals / 6360 frames:

- Queue submits: `11717`, about `110.54` per 60 frames.
- Hard sync flushes: `695`, about `6.56` per 60 frames.
- Render-pass barrier breaks: `2576`, about `24.30` per 60 frames.
- Barrier-tracked buffer range: about `51583.86 MB`.
- DMA transfer fences: `4652` to `ALL_COMMANDS`, `0` to `HOST`, about
  `7086.80 MB`.
- Pipeline creates: `157` graphics, `1` compute, `158` slow, about
  `89257.93 ms` total creation time.
- Detile jobs: `0`.
- Simple upload: `1`, about `3.51 MB`.

Pressure mix:

| Class | Records | Frames | Reading |
| --- | ---: | ---: | --- |
| `dma-fence-bandwidth` | 55 | 3300 | The main old-capture RSX signal is transfer fences and bytes. |
| `low` | 34 | 2040 | Many intervals are quiet after warmup/transition. |
| `cpu-gpu-drain` | 11 | 660 | Hard syncs are present but not the largest byte path. |
| `pipeline-stutter` | 3 | 180 | Pipeline creation is ugly early warmup, separate from steady field. |
| `buffer-barrier-bandwidth` | 3 | 180 | Large buffer ranges are touched by barriers. |

Important caveat: this was the old `rsx-auditor` dev core field capture at about
`15.11 FPS`, before the RelWithDebInfo build-type correction and before current
u4 reduced-loop low-overhead baselines. Use it to choose the next measurement,
not as the current FPS truth.

## Current Read

The best RSX/GPU hypothesis is:

1. The steady field path is paying too much for `VKTextureCache` DMA transfer
   fencing and broad buffer barrier ranges.
2. Render-pass breaks still matter on Adreno, especially texture/image barriers,
   but the old capture's newer break-source split was not yet available.
3. Pipeline creation is a separate warmup/stutter lane.
4. Detile/simple upload was not the field bottleneck in this capture.

This points at GPU-residency and synchronization-narrowing work before any new
compute shader.

## Next Measurement

Re-run on the current optimized baseline:

```powershell
.\tools\set_thor_logging.ps1 -Mode RsxAuditor
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action AndroidScene `
  -Scene field `
  -Driver stock-qualcomm `
  -Core relwithdebinfo-u4-rsx-auditor `
  -AndroidLogMode RsxAuditor
.\tools\set_thor_logging.ps1 -Mode Quiet
.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir RUN_DIR
```

If field still shows high `dma_transfer_all` / `dma_mb`, test only the existing
host-read fence mode as a narrow A/B:

```powershell
.\tools\set_thor_logging.ps1 -Mode RsxDmaHostFence
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action AndroidScene `
  -Scene field `
  -Driver stock-qualcomm `
  -Core relwithdebinfo-u4-rsx-host-fence `
  -AndroidLogMode RsxDmaHostFence
.\tools\set_thor_logging.ps1 -Mode Quiet
```

Do not compare against any capture where `debug.rpcsx.thor.rsx_dma_fence` was
accidentally left on; use captured props to prove the mode.

## Implementation Ladder

1. `measurement`: current RelWithDebInfo + reduced-loop u4 + `RsxAuditor`.
2. `existing-gate-ab`: `RsxDmaHostFence` versus clean off on matched field.
3. `callsite-labels`: if still hot, split DMA transfer/fence counters by
   texture cache source and command-buffer flush path.
4. `barrier-scope`: narrow the `VKTextureCache.cpp` post-transfer fence only if
   field, first battle, and menu verify clean.
5. `tile-locality`: if newer logs show texture/image `rp_break` dominance,
   continue depth/texture barrier experiments, but keep WCB correctness on.
6. `gpu-resident-prep`: only after the above, consider persistent texture/vertex
   prep buffers or GPU-side conversion.

## Guardrails

- Keep RSX command decoding and synchronization semantics CPU-side.
- Do not mix pipeline warmup with steady-field FPS.
- Do not count WCB-off as a correctness win without visual A/B proof.
- Do not promote `RsxDmaHostFence` unless field, first battle, and menu survive.
- Reset to `Quiet` after RSX logging or fence tests.
- Treat Turnip/A7xx as a separate driver lane because the last Android Turnip
  field result was worse than stock Qualcomm.

## Decision

Continue RSX/GPU work through residency and synchronization:

1. summarize current optimized RSX auditor capture;
2. if DMA fences still dominate, A/B host-read fence mode;
3. if render-pass breaks dominate, target texture/image barrier locality;
4. only build GPU compute for RSX-adjacent data after a capture proves real
   texture/vertex/render-prep bandwidth that can stay on GPU.

## Windows Lab Slice - 2026-05-17

Status: `windows-depth-texture-barrier-proved`.

Windows-first is the right route for RSX/GPU experiments because it gives fast
route/counter iteration before touching Thor. The Windows lab checkout
`rpcs3-upstream` now has a local RSX auditor and title-gated depth texture
barrier skip for Eternal Sonata behind environment variables:

- `RPCS3_ES_RSX_AUDITOR=60|frame|N`
- `RPCS3_ES_RSX_DMA_FENCE=host`
- `RPCS3_ES_RSX_TEXTURE_BARRIER=depth|color|all`

The Android repo wrappers now expose these as:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -WindowsRsxAuditor On
```

and:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -WindowsRsxAuditor On `
  -WindowsRsxTextureBarrier Depth
```

Build proof:

- `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed after the auditor patch.
- The rebuilt binary was `rpcs3-upstream\build-msvc\bin\rpcs3.exe`.

Baseline Windows field capture:

- Run dir:
  `debug-captures/windows-lab/20260517-223527-rsx-auditor-windows/`
- Screenshot:
  `screenshots/screenshot-0147s.png`
- Visual result: reached the first playable field, correct-looking field
  screenshot, overlay about `30 FPS`.
- Host grade: `high` by the end because the host CPU saturated; useful for RSX
  classification, not clean timing.
- Summary:
  `eternal-sonata-rsx-auditor-summary.md`
- Auditor totals across `7080` frames:
  - queue submits: `7219`, about `61.18` per 60 frames;
  - hard sync flushes: `117`, about `0.99` per 60 frames;
  - render-pass barrier breaks: `4754`, about `40.29` per 60 frames;
  - break source `g/b/i/t`: `0/0/3169/1585`;
  - barriers `g/b/i/t/all`: `0/165/12830/1585/0`;
  - texture barriers color/depth: `0/1585`;
  - DMA transfer fences: `15`, about `24.19 MB` total;
  - detile: `0`, simple upload: `1`.

Reading: unlike the old Thor auditor run, Windows field is not a DMA-fence
bandwidth story. It is mostly image/texture barrier render-pass locality, with
depth texture barriers as the first obvious target.

Depth texture-barrier skip Windows capture:

- Run dir:
  `debug-captures/windows-lab/20260517-224402-rsx-depth-skip-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Screenshot:
  `screenshots/screenshot-0146s.png`
- Visual result: reached field, correct-looking screenshot, overlay about
  `30 FPS`.
- Host grade: `high` because Vita3K was active, so do not use this as timing.
- Summary:
  `eternal-sonata-rsx-auditor-summary.md`
- Auditor totals across `5640` frames:
  - render-pass barrier breaks: `2358`, about `25.09` per 60 frames;
  - break source `g/b/i/t`: `0/0/2358/0`;
  - barriers `g/b/i/t/all`: `0/178/10165/0/0`;
  - texture barriers color/depth: `0/0`;
  - texture skips/post elides: `1257/667`;
  - DMA transfer fences: `22`, about `33.54 MB`;
  - pipeline create time dropped to about `84.72 ms`, likely cache/warmup state
    and not a claim about the barrier gate.

Reading: depth texture-barrier skip mechanically removed the texture-side
render-pass breaks and the field screenshot survived. The remaining pressure is
image barriers. The next Windows RSX step is callsite labeling for image
barriers, especially render-target and texture-cache layout transitions, before
attempting a broader skip.

Port decision:

- The depth texture-barrier skip already exists on Thor. Windows says the idea
  is mechanically valid, but it only removes the texture half of the locality
  pressure.
- Next port-worthy work is not compute. It is image-barrier callsite labels and
  a narrow render-target resolve locality experiment, then Thor field, first
  battle, and menu validation.

## Windows Lab Slice - 2026-05-17 Late

Status: `windows-render-target-resolve-identified`.

Follow-up instrumentation added image-barrier callsite buckets to the Windows
`rpcs3-upstream` RSX auditor. The first broad pass split image barriers into
`unknown/render-target/texture-cache/draw/present/texture/upscaler`; the second
pass split render-target into `rt_res`, `rt_unres`, `rt_post`, and `rt_other`.

Broad image-label capture:

- Run dir:
  `debug-captures/windows-lab/20260517-230406-rsx-image-labels-depth-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Visual result: reached first playable field; screenshots looked correct with
  FPS overlay around `30 FPS`.
- Host grade: `high`; Vita3K appeared mid-run, so no timing claim.
- Auditor totals across `7020` frames:
  - render-pass barrier breaks: `3115`, about `26.62` per 60 frames;
  - image barrier sources `unk/rt/tc/draw/pres/tex/up`:
    `0/12464/7/0/171/0/0`;
  - image break sources `unk/rt/tc/draw/pres/tex/up`:
    `0/3115/0/0/0/0/0`.

Reading: after depth texture-barrier skip, all remaining image render-pass
breaks came from `VKRenderTargets`, not texture cache, draw, present, texture
conversion, or upscaling.

Refined render-target-label capture:

- Run dir:
  `debug-captures/windows-lab/20260517-231417-rsx-rt-labels-depth-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Visual result: reached first playable field; screenshots looked correct with
  FPS overlay around `30 FPS`.
- Host grade: `high`; no Vita3K process was active, but a separate Vita3K build
  was compiling through MSBuild/`cl.exe`, so no timing claim.
- Auditor totals across `7020` frames:
  - render-pass barrier breaks: `3381`, about `28.90` per 60 frames;
  - image barrier sources
    `unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up`:
    `0/13528/0/0/0/7/0/185/0/0`;
  - image break sources
    `unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up`:
    `0/3381/0/0/0/0/0/0/0/0`.

Reading: the remaining tile-locality loss is specifically
`render_target::resolve`, and the shape is very regular: four render-target
resolve image barriers per resolve burst, with the first one ending the open
render pass. The next RSX experiment should target render-target resolve
scheduling/caching/locality, not texture-cache DMA fences and not generic GPU
compute. A blunt `preserve_renderpass` flip is risky because this path enters
compute resolve work; use a narrow, title-gated experiment with field/menu/battle
visual validation.

## Windows Lab Slice - 2026-05-18 Morning

Status: `resolve-skip-rejected`.

Added an unsafe, title-gated Windows probe for `render_target::resolve`:

- `tools/windows_rpcs3_lab.ps1 -RsxResolve SkipColor|SkipDepth|SkipAll`
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxResolve SkipColor|SkipDepth|SkipAll`
- Process env: `RPCS3_ES_RSX_RESOLVE=color|depth|all`
- Auditor tuple:
  `resolve(color/depth/skip_color/skip_depth)=...`

Useful capture:

- Run dir:
  `debug-captures/windows-lab/20260518-093227-rsx-resolve-skip-color-rerun-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=color`
- Host grade: `clean` across prelaunch, postlaunch, field samples, and postrun.
- Screenshots:
  `screenshots/screenshot-0131s.png`,
  `screenshots/screenshot-0153s.png`
- Visual result: failed. The field was almost entirely black with only a small
  bright player/effect blob and the FPS overlay visible. Baseline comparison
  remains
  `debug-captures/windows-lab/20260517-231417-rsx-rt-labels-depth-windows/screenshots/screenshot-0134s.png`.
- Auditor totals across `8940` frames:
  - queue submits: `9075`, about `60.91` per 60 frames;
  - hard sync flushes: `113`, about `0.76` per 60 frames;
  - render-pass barrier breaks: `0`;
  - image barrier sources
    `unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up`:
    `0/0/0/0/0/7/0/151/0/0`;
  - image break sources
    `unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up`:
    `0/0/0/0/0/0/0/0/0/0`;
  - resolve calls/skips color/depth: calls `6876/0`, skips `6876/0`;
  - texture skips/post elides: `3438/3438`;
  - DMA transfer fences: `15`, about `24.20 MB`.

Reading: the destructive probe proves the hot `render_target::resolve` output is
consumed by the field render. Removing the resolves mechanically eliminates the
render-pass-break counter, but it is not visually correct and must not be ported
to Thor. The next plausible RSX-on-GPU path is a correct resolve locality change:
profile resolve identity/geometry, then try batching/debouncing only provably
duplicate resolves or moving the resolve into a hardware/local renderpass-safe
path. Do not spend Thor time on blanket `SkipColor`.
