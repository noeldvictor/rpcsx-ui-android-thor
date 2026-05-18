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

## Windows Lab Slice - 2026-05-18 Resolve Profile

Status: `resolve-profile-single-target`.

Added non-destructive resolve profiling to the Windows lab patch:

- `tools/windows_rpcs3_lab.ps1 -RsxResolve Profile`
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxResolve Profile`
- Process env: `RPCS3_ES_RSX_RESOLVE=profile`
- Summary output:
  `eternal-sonata-rsx-resolve-profile.csv` plus a `Resolve Profile` table in
  `eternal-sonata-rsx-auditor-summary.md`

Clean field capture:

- Run dir:
  `debug-captures/windows-lab/20260518-095926-rsx-resolve-profile-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=profile`
- Host grade: `clean` across seven snapshots.
- Visual result: correct-looking first playable field screenshot with FPS
  overlay around `30 FPS`.
- Auditor totals across `8940` frames:
  - queue submits: `9073`, about `60.89` per 60 frames;
  - hard sync flushes: `111`, about `0.74` per 60 frames;
  - render-pass barrier breaks: `6873`, about `46.13` per 60 frames;
  - image source `rt_res`: `27496`;
  - image break source `rt_res`: `6873`;
  - resolve calls/skips color/depth: calls `6874/0`, skips `0/0`;
  - texture skips/post elides: `3437/3437`.
- Resolve profile:
  - count: `6874`, about `46.13` per 60 frames;
  - depth: `0`;
  - format: `0x0000002c`;
  - size: `1280x720`;
  - samples/grid: `2`, `2x1`;
  - pitch: `10240`;
  - base: `0xc0b20000`;
  - key: `0x5d84ad5c95803672`.

Duplicate-tag confirmation capture:

- Run dir:
  `debug-captures/windows-lab/20260518-100949-rsx-resolve-profile-dup-tags-windows/`
- Host grade: `clean` across five snapshots.
- Visual result: correct-looking first playable field screenshot.
- Auditor totals across `7680` frames:
  - queue submits: `7806`, about `60.98` per 60 frames;
  - hard sync flushes: `104`, about `0.81` per 60 frames;
  - render-pass barrier breaks: `4341`, about `33.91` per 60 frames;
  - image source `rt_res`: `17368`;
  - image break source `rt_res`: `4341`;
  - resolve calls/skips color/depth: calls `4342/0`, skips `0/0`.
- Resolve profile:
  - same single target signature as the first profile run;
  - count: `4342`, about `33.92` per 60 frames;
  - duplicate last-use tags: `0`.

Reading: Eternal Sonata field is not bouncing through many unrelated resolve
targets. It is repeatedly resolving one `1280x720` 2x1 MSAA color render target,
and the resolves are not simple duplicates of an unchanged last-use tag. The
hot output is consumed, so `SkipColor` was a useful proof but not a feature.

Next RSX-on-GPU route:

1. Profile the resolve reason/callsite so we know whether the target is being
   resolved for texture sampling, transfer/readback, present/blit, or another
   consumer.
2. Try a correct hardware/local resolve path only after that reason is known.
   The global `Force Hardware MSAA Resolve` setting is a candidate A/B, but use
   a reversible wrapper-controlled config override and screenshots because it
   changes correctness-sensitive FBO sampling behavior.
3. Do not port the local Windows resolve-skip code to Thor. Port only a narrow,
   correct locality change after field, first battle, and menu survive.

## Research Pass - 2026-05-18

Status: `tiler-resolve-direction-confirmed`.

Primary-source reading:

- Khronos Vulkan tile-based rendering best practices:
  <https://github.khronos.org/Vulkan-Site/guide/latest/tile_based_rendering_best_practices.html>
- Khronos Vulkan subpasses performance sample:
  <https://github.khronos.org/Vulkan-Site/samples/latest/samples/performance/subpasses/README.html>
- Khronos `VK_EXT_multisampled_render_to_single_sampled` proposal:
  <https://github.khronos.org/Vulkan-Site/features/latest/features/proposals/VK_EXT_multisampled_render_to_single_sampled.html>
- Khronos `VK_EXT_custom_resolve` / `VK_QCOM_render_pass_shader_resolve` material:
  <https://github.khronos.org/Vulkan-Site/features/latest/features/proposals/VK_EXT_custom_resolve.html>
  and
  <https://docs.vulkan.org/refpages/latest/refpages/source/VK_QCOM_render_pass_shader_resolve.html>
- Qualcomm Adreno tile-based rendering note:
  <https://www.qualcomm.com/news/onq/2021/07/evolution-high-performance-foveated-rendering-adreno>
- Academic tile-redundancy paper:
  <https://arxiv.org/abs/1807.09449>
- Academic DBT hybrid-execution direction:
  <https://arxiv.org/abs/2512.00487>
- Academic GPU emulator batching reference:
  <https://arxiv.org/abs/1907.08467>

Reading:

- Mobile tilers want the MSAA resolve to happen while data is still tile-local
  or attachment-local. Khronos guidance explicitly points at resolve
  attachments in the same subpass plus discarding the multisampled attachment as
  the efficient tiler shape.
- Subpass/input-attachment designs matter because they can avoid writing an
  intermediate render target to external memory and reading it back in a later
  pass. This matches the Windows evidence: the hot work is not DMA bandwidth,
  it is repeated render-target resolve barriers.
- Qualcomm's Adreno material frames tile memory the same way: build the frame
  locally, write only the needed final contents to system memory, and avoid
  unnecessary read/rewrite traffic.
- The newer Vulkan resolve extensions are useful design signals but not a blind
  patch target. `VK_EXT_custom_resolve` and QCOM shader resolve help when custom
  filtering is needed; fixed-function or in-pass resolves should stay preferred
  for simple average/sample resolves if they can match PS3 semantics.
- CPU-to-GPU emulator offload papers point toward selective, batched,
  verification-friendly execution. That supports the existing SPU-superpath rule:
  avoid broad "SPU on GPU"; target stable bulk jobs only.

Decision: keep RSX work on a correct resolve-locality lane. Do not build a
generic compute resolve until a capture proves the consumer cannot be handled by
an in-pass/hardware/local path.

## Windows Lab Slice - 2026-05-18 Resolve Reason

Status: `transfer-read-consumer-identified`.

Extended the local Windows lab patch so resolve profile rows include a reason
bucket:

- `unknown`
- `spill`
- `transfer-read`
- `memory-copy`

The Android repo summarizer remains backward-compatible with old profile rows
and now shows a `Reason` column in the `Resolve Profile` table.

Clean field capture:

- Run dir:
  `debug-captures/windows-lab/20260518-103121-rsx-resolve-reason-profile-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=profile`
- Host grade: `clean` across five snapshots.
- Visual result: correct-looking first playable field screenshot:
  `screenshots/screenshot-0131s.png`.
- Build proof:
  `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed before the run, with only the usual `LNK4098` warning.
- Auditor totals across `7680` frames:
  - queue submits: `7806`, about `60.98` per 60 frames;
  - hard sync flushes: `104`, about `0.81` per 60 frames;
  - render-pass barrier breaks: `4329`, about `33.82` per 60 frames;
  - image source `rt_res`: `17320`;
  - image break source `rt_res`: `4329`;
  - resolve calls/skips color/depth: calls `4330/0`, skips `0/0`.
- Resolve profile:
  - count: `4330`, about `33.83` per 60 frames;
  - reason: `transfer-read`;
  - duplicate tags: `0`;
  - depth: `0`;
  - format: `0x0000002c`;
  - size: `1280x720`;
  - samples/grid: `2`, `2x1`;
  - pitch: `10240`;
  - base: `0xc0b20000`;
  - key: `0x26a0ad677c35c962`.

Reading: the hot Eternal Sonata field resolve is requested by
`render_target::memory_barrier` when a transfer-style read asks for the resolved
surface. It is not a spill path and not the old-content memory-copy path. That
means the next Windows A/B should target the transfer-read consumer:

1. Identify whether the transfer-read is texture sampling, CPU readback, blit,
   or another transfer consumer at `get_surface(surface_access::transfer_read)`.
2. If it is texture sampling, test the existing `Force Hardware MSAA Resolve`
   config as a reversible A/B because upstream has a path that forces strict FBO
   sampling for multisampled attachments.
3. If it is a real transfer/copy consumer, instrument that callsite before
   attempting a different resolve scheduler.

## Windows Lab Slice - 2026-05-18 Force Hardware MSAA Resolve A/B

Status: `rejected-correctness`.

Added a reversible Windows wrapper override:

- `tools/windows_rpcs3_lab.ps1 -RsxForceHwMsaaResolve On|Off|Keep`
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxForceHwMsaaResolve On|Off|Keep`

The wrapper edits RPCS3's `Force Hardware MSAA Resolve` setting before launch,
records the old and new values in `windows-rpcs3-lab.txt`, and restores the old
value after the run. The tested run changed `false -> true`, then restored
`true -> false`; the config was checked afterward and is back to `false`.

Clean field capture:

- Run dir:
  `debug-captures/windows-lab/20260518-132528-rsx-force-hw-msaa-resolve-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=profile`
- Config override:
  `Force Hardware MSAA Resolve: true`
- Host grade: `clean` across five snapshots.
- Screenshot:
  `screenshots/screenshot-0131s.png`
- Visual result: failed. The field rendered, but flower/foliage sprites showed
  obvious black square backgrounds. Later screenshots showed repeated black
  square flower/foliage tiles. Do not port or recommend this setting for Eternal
  Sonata without a narrower fix.
- Auditor totals across `6300` frames:
  - queue submits: `6441`, about `61.34` per 60 frames;
  - hard sync flushes: `104`, about `0.99` per 60 frames;
  - render-pass barrier breaks: `3002`, about `28.59` per 60 frames;
  - image source `rt_res`: `12028`;
  - image break source `rt_res`: `3002`;
  - resolve calls/skips color/depth: calls `3007/1906`, skips `0/0`;
  - DMA transfer fences: `25`, about `33.58 MB`.
- Resolve profile:
  - color transfer-read: `3007`, about `28.64` per 60 frames,
    `1280x720`, `fmt=0x0000002c`, base `0xc0b20000`;
  - depth transfer-read: `1906`, about `18.15` per 60 frames,
    `1280x720`, `fmt=0x00000081`, base `0xc1260000`;
  - duplicate tags: `0`.

Comparison to the previous clean reason-profile run:

| Metric | Reason Profile Off | Force HW MSAA On | Reading |
| --- | ---: | ---: | --- |
| Frames | `7680` | `6300` | Different duration, compare normalized rates. |
| Render-pass breaks / 60 | `33.82` | `28.59` | Mechanically lower. |
| Color resolves / 60 | `33.83` | `28.64` | Lower, but not enough to matter if visuals break. |
| Depth resolves / 60 | `0.00` | `18.15` | New depth resolve pressure appears. |
| Visual correctness | pass | fail | Black square sprites reject the route. |

Reading: global `Force Hardware MSAA Resolve` moves some work in the desired
direction but changes FBO/MSAA sampling semantics enough to corrupt field
sprites. This is useful evidence, not a speed win.

Next Windows step: add consumer callsite labels around
`surface_access::transfer_read` so the hot target splits into texture-cache FBO
sampling, copy/dynamic texture processing, present, surface collapse, or another
consumer. Then test only the hot consumer with a narrow locality experiment.

## Windows Lab Slice - 2026-05-18 Transfer Consumer Profile

Status: `blit-source-consumer-identified`.

Extended the local Windows lab patch so transfer-read resolves can be labeled by
consumer callsite:

- `texture-gather-slices`
- `texture-fbo-copy`
- `texture-fbo-sample`
- `texture-fbo-wrap`
- `surface-collapse`
- `present`
- `texture-cache-lock`
- `blit-source`
- `old-content-copy-source`

The Android summarizer now maps those reason ids instead of reporting them as
`unknown`.

Build/parser proof:

- `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed, with only the usual `LNK4098` warning.
- `tools/summarize_eternal_sonata_rsx_auditor.ps1` passed PowerShell parser
  validation after the reason-map update.

Depth-skip consumer run:

- Run dir:
  `debug-captures/windows-lab/20260518-134503-rsx-transfer-consumer-profile-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=depth`
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=profile`
- Host grade: `clean` across five snapshots.
- Window routing: RPCS3 moved to `\\.\DISPLAY2`.
- Visual result: reached field, but same-route screenshots showed black-backed
  flower/foliage billboards. Treat this as a correctness warning for the depth
  texture-barrier skip route, not as a speed win.
- Auditor totals across `6240` frames:
  - queue submits: `6379`, about `61.34` per 60 frames;
  - hard sync flushes: `103`, about `0.99` per 60 frames;
  - render-pass barrier breaks: `2966`, about `28.52` per 60 frames;
  - image source `rt_res`: `11868`;
  - image break source `rt_res`: `2966`;
  - texture barriers color/depth: `0/0`;
  - texture skips/post elides: `1867/675`;
  - resolve calls/skips color/depth: calls `2967/0`, skips `0/0`;
  - DMA transfer fences: `24`, about `33.57 MB`.
- Resolve profile:
  - count: `2967`, about `28.53` per 60 frames;
  - reason: `blit-source`;
  - duplicate tags: `0`;
  - depth: `0`;
  - format: `0x0000002c`;
  - size: `1280x720`;
  - samples/grid: `2`, `2x1`;
  - pitch: `10240`;
  - base: `0xc0b20000`.

Baseline consumer run:

- Run dir:
  `debug-captures/windows-lab/20260518-134854-rsx-transfer-consumer-baseline-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER` off
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=profile`
- Host grade: `moderate` only because the post-run snapshot caught Codex CPU
  work; prelaunch, postlaunch, and field samples were clean.
- Window routing: RPCS3 moved to `\\.\DISPLAY2`.
- Visual result: reached field; same-camera screenshots looked clean, without
  the black-backed flower/foliage billboards seen in the depth-skip run.
- Auditor totals across `7200` frames:
  - queue submits: `7325`, about `61.04` per 60 frames;
  - hard sync flushes: `103`, about `0.86` per 60 frames;
  - render-pass barrier breaks: `5102`, about `42.52` per 60 frames;
  - break source `g/b/i/t`: `0/0/3401/1701`;
  - image source `rt_res`: `13608`;
  - image break source `rt_res`: `3401`;
  - texture barriers color/depth: `0/1701`;
  - resolve calls/skips color/depth: calls `3402/0`, skips `0/0`;
  - DMA transfer fences: `15`, about `24.20 MB`.
- Resolve profile:
  - count: `3402`, about `28.35` per 60 frames;
  - reason: `blit-source`;
  - duplicate tags: `0`;
  - depth: `0`;
  - format: `0x0000002c`;
  - size: `1280x720`;
  - samples/grid: `2`, `2x1`;
  - pitch: `10240`;
  - base: `0xc0b20000`.

Reading:

- We found a real RSX-on-GPU target: the hot render-target resolve feeds the
  blit engine through `texture_cache::upload_scaled_image`, not present, CPU
  readback, texture-cache FBO sampling, or old-content copy.
- The work is already GPU-adjacent, but it likely spills tile/locality because
  the path resolves the MSAA render target, then uses the resolved image as the
  blit source. A plausible GPU-use experiment is not "skip resolve"; it is a
  fused MSAA-resolve-plus-blit path or renderpass-local resolve path for this
  specific title/shape.
- The depth texture-barrier skip route now has same-camera evidence of black
  billboard artifacts. Do not port or promote it without a narrower fix.

Next Windows step:

1. Add a small blit-source geometry profiler for the `src_is_render_target`
   branch in `texture_cache::upload_scaled_image`.
2. Confirm whether the hot blit is a fixed-size, fixed-format
   render-target-to-texture transfer.
3. If stable, prototype a title-gated fused resolve/blit path and validate
   field, first battle, and menu before any Thor port.
