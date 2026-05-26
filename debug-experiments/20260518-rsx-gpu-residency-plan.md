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
- Academic binary-translation-to-GPU direction:
  <https://www.usenix.org/conference/atc23/presentation/ginzburg>
- Academic system-level DBT codegen direction:
  <https://arxiv.org/abs/2402.09688>
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
- Vectorized binary-translation work is relevant as a design signal, not a
  drop-in SPU plan. It works when many independent instances can be batched and
  run to completion with limited synchronization. Eternal Sonata's hot SPU
  `0x25cc` / `0x451c` path still looks like DMA command/wait machinery, so any
  GPU offload must first find a coarse repeated payload or an RSX-consumed
  resource, then add verify-only comparison.
- Recent system-level DBT work argues that reducing coordination overhead,
  eliminating redundant coordination points, and improving generated-code
  quality can produce emulator wins without moving work to a different
  processor. That keeps SPU HLE/codegen/reduced-loop work on equal footing with
  RSX tiler-locality work.

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

## Windows Lab Slice - 2026-05-18 Blit Source Geometry and Fused Resolve

Status: `fused-blit-source-rejected`.

Added durable wrapper and summarizer support for the Windows-only scout gate:

- `tools/windows_rpcs3_lab.ps1 -RsxBlitSourceResolve Off|Verify|Fast`
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxBlitSourceResolve Off|Verify|Fast`
- Process env: `RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=off|verify|fast`
- Summary output:
  `eternal-sonata-rsx-blit-source-profile.csv` plus a `Blit Source Profile`
  table in `eternal-sonata-rsx-auditor-summary.md`

Geometry profile capture:

- Run dir:
  `debug-captures/windows-lab/20260518-141204-rsx-blit-source-geometry-profile-windows/`
- Gate:
  `RPCS3_ES_RSX_TEXTURE_BARRIER=off`
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=profile`
- Host grade: clean during the useful field samples.
- Window routing: RPCS3 moved to `\\.\DISPLAY2`.
- Visual result: correct-looking first playable field screenshot.
- Auditor totals across `7260` frames:
  - queue submits: `7380`, about `60.99` per 60 frames;
  - hard sync flushes: `98`, about `0.81` per 60 frames;
  - render-pass barrier breaks: `5225`, about `43.18` per 60 frames;
  - image break source `rt_res`: `3483`;
  - texture barriers depth: `1742`;
  - color resolves: `3484`, about `28.79` per 60 frames;
  - DMA transfer fences: `15`, about `24.20 MB`.
- Resolve profile:
  - reason: `blit-source`;
  - format: `0x0000002c`;
  - size: `1280x720`;
  - samples/grid: `2`, `2x1`;
  - pitch: `10240`;
  - base: `0xc0b20000`.
- Blit source profile highlights:
  - stable `0xc3840000 -> 0xc3a11080`, `640x360`, count `7134`;
  - stable `0xc1a30000 -> 0xc2ecc100`, `768x768`, count `3484`;
  - source-render-target chunks from `0xc0b20000`, `0xc0b21000`,
    `0xc0b22000`, covering `0..2560 x 720`, each count `1742`.

Reading: the hot consumer is real and stable enough to scout. It is a good
Windows research target because it is already RSX/GPU-adjacent and batched by a
large render-target-to-texture transfer, not a tiny SPURS control event.

Fast fused prototype capture:

- Run dir:
  `debug-captures/windows-lab/20260518-143950-rsx-blit-source-fused-fast-windows/`
- Gate:
  `RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=fast`
- Host grade: high near the end, so timing is not comparable.
- Visual result: failed. Screenshots at `132s`, `147s`, and `156s` showed a
  black field with only the overlay visible.
- Counter result:
  - render-pass barrier breaks dropped to `0`;
  - resolve calls/skips dropped to `0`;
  - compute pipeline creates: `1`;
  - DMA transfer fences: `8`, about `9.21 MB`.

Follow-up diagnostics:

- `20260518-144937-rsx-blit-source-fused-solid-probe-windows`: forced solid
  magenta shader output, still black field.
- `20260518-145729-rsx-blit-source-fused-storage-dst-windows`: added storage
  usage for the blit destination texture, still black field.
- `20260518-150422-rsx-blit-source-fused-trace-windows`: trace confirmed the
  fused helper dispatched on the expected `0xc0b20000` source chunks and
  `0/0/1024/720`, `1024/0/2048/720`, `2048/0/2560/720` rectangles, still black.
- `20260518-151129-rsx-blit-source-fused-untyped-dst-windows`: changed the
  destination image declaration to match the untyped resolve style, still black.
- `20260518-151717-rsx-blit-source-fused-untyped-solid-windows`: untyped
  destination plus forced solid magenta, still black.

Decision:

- Keep the blit-source profile tooling and the wrapper gate because they found a
  legitimate RSX-local candidate.
- Reject the current direct compute resolve-to-blit-destination path. It gives
  beautiful counters and a black field, which is not a speed win.
- Do not port `RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=fast` to Thor.
- The next valid RSX path is verify-only parity first: run the normal
  resolve/blit and the candidate fused path on the same source, compare GPU-side
  or copied hashes/bytes outside the critical path, then investigate why the
  compute writes are not feeding the visible texture chain. If that stalls,
  return to the measured SPU/HLE/codegen path around `0x25cc` / `0x451c`.

## Windows Lab Slice - 2026-05-18 Blit Source Scratch Verify

Status: `scratch-verify-gpu-dispatches`.

Added a safer verify mode for the Windows-only blit-source resolve gate:

- `tools/windows_rpcs3_lab.ps1 -RsxBlitSourceResolve Verify`
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxBlitSourceResolve Verify`
- Process env: `RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=verify`
- Summary counters:
  `blit_resolve(fast/verify/reject)` and
  `blit_reject(region/typeless/format/rt/dispatch)`.

Failed live-destination verify attempt:

- Run dir:
  `debug-captures/windows-lab/20260518-172519-rsx-blit-source-verify-storage-windows/`
- Visual result: failed. The field was black with overlay only.
- Crash signal:
  `VKDraw.cpp:68 validate_image_layout_for_read_access`.
- Reading: making the real blit destination storage-capable mutates the live
  texture-cache chain too early. Do not use this as a Thor route.

Scratch verify capture:

- Run dir:
  `debug-captures/windows-lab/20260518-173457-rsx-blit-source-verify-scratch-windows/`
- Gate:
  `RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=verify`
- Resolve probe:
  `RPCS3_ES_RSX_RESOLVE=profile`
- Window routing: RPCS3 moved to `\\.\DISPLAY2`.
- Host grade: clean.
- Visual result: correct-looking first playable field screenshot.
- Auditor totals across `7230` frames:
  - queue submits: `7355`, about `61.04` per 60 frames;
  - hard sync flushes: `103`, about `0.85` per 60 frames;
  - render-pass barrier breaks: `5185`, about `43.03` per 60 frames;
  - color resolve calls/skips: `6916` / `3458`;
  - scratch verify dispatches: `3458`, about `28.70` per 60 frames;
  - rejects: `26277`, all `render_target` rejects from non-candidate surfaces;
  - compute pipeline creates: `3`.
- Resolve profile:
  - `transfer-read` count `3458`, duplicate tags `3458`;
  - `blit-source` skip count `3458`;
  - target: `1280x720`, `fmt=0x2c`, `samples=2`, `grid=2x1`,
    `pitch=10240`, `base=0xc0b20000`.

Reading: this is the first clean proof that the candidate RSX resolve/blit
compute work can be dispatched on the GPU while the normal path preserves the
visible frame. It is not a speed win because verify adds scratch work. The next
RSX step is not Thor porting; it is finding the ownership/state gap that makes
the live destination path black. Keep `fast` off until the candidate can feed
the visible texture chain and pass field, menu, and first battle.

## Windows Lab Slice - 2026-05-18 Depth Feedback Barrier Profile

Status: `rsx-depth-feedback-not-a-speed-win`.

Added a Windows-only depth-feedback gate and better texture-barrier profiling:

- `tools/windows_rpcs3_lab.ps1 -RsxDepthFeedback Off|KeepReadOnly`
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxDepthFeedback Off|KeepReadOnly`
- Process env: `RPCS3_ES_RSX_DEPTH_FEEDBACK=keep-readonly`
- Summary output now includes `depth_feedback(...)` counters and a `bound`
  texture-barrier flag.

Matched high-vblank baseline:

- Run dir:
  `debug-captures/windows-lab/20260518-202807-rsx-texture-profile-uncap-vblank240-fieldmove-windows-windows/`
- Host grade: moderate because one CPU sample crossed the clean threshold.
- Visual result: correct-looking field and first-battle screenshots.
- Auditor totals across `15600` frames:
  - queue submits: `15924`, about `61.25` per 60 frames;
  - hard sync flushes: `100`, about `0.38` per 60 frames;
  - render-pass barrier breaks: `9550`, about `36.73` per 60 frames;
  - break source `g/b/i/t`: `0/0/1607/7943`;
  - texture barriers depth: `7943`;
  - resolve calls color/depth: `1608/0`.
- Texture barrier profile found one dominant surface:
  `base=0xc1260000`, `fmt=0x81`, `1280x720`, `samples=2`, `grid=2x1`,
  `pitch=10240`, `cur/opt=3/1000339000`, flags
  `depth,read-only,fbo-loop,renderpass-open`.

Destructive depth-skip reference:

- Run dir:
  `debug-captures/windows-lab/20260518-201024-rsx-texture-depth-skip-uncap-vblank240-fieldmove-windows-windows/`
- Visual result: survived this high-vblank route, but earlier same-camera depth
  skip evidence showed black-backed foliage/flower billboard artifacts.
- Counter result: render-pass barrier breaks fell from about `36.4` to `5.8`
  per 60 frames, proving the locality target is real.
- Decision: do not port or promote; the counter win is not correctness-safe and
  did not show a 200% Windows moving-gameplay speedup.

Safe feedback-layout probes:

- Preserve-only run:
  `debug-captures/windows-lab/20260518-205734-rsx-depth-feedback-preserve-uncap-vblank240-fieldmove-windows-windows/`
  stayed visually correct, but render-pass breaks remained `9554`
  (`36.75` per 60) and depth texture barriers remained `7945`.
- Proactive prepare/prime run:
  `debug-captures/windows-lab/20260518-210556-rsx-depth-feedback-prime-uncap-vblank240-fieldmove-windows-windows/`
  stayed visually correct, but the full-route counters only moved to `9487`
  render-pass breaks (`36.49` per 60) and `7908` depth texture barriers.
- Bound-profile short route:
  `debug-captures/windows-lab/20260518-211409-rsx-depth-feedback-bound-profile-fieldbattle-windows-windows/`
  confirmed the hot `0xc1260000` barrier is on the bound read-only depth
  surface, not an unrelated stale depth texture. Its profile still split mostly
  into `cur/opt=3/1000339000` barriers, plus a smaller current-optimal bucket.

Reading:

- RSX depth-feedback locality is a real GPU-residency target, but the safe
  layout-preservation path does not remove the actual hot barrier.
- The only version that collapses the counter today is the destructive depth
  texture-barrier skip, which is visually suspect and still not a measured speed
  win on Windows.
- Under the current user gate, this remains Windows-only lab work. There is no
  stable 200% moving-gameplay proof, so do not port this RSX path to Android or
  Thor.
- Next valid choices are either a deeper render-pass scheduling rewrite that
  makes the bound depth feedback legal without the explicit texture barrier, or
  a pivot back to the measured SPU/MFC/codegen target around `0x25cc` / `0x451c`,
  which old Windows and Thor captures both show as the actual gameplay hot path.

## Windows Lab Slice - 2026-05-18 GPU Candidate Fieldbattle Overlap Scout

Status: `no-spu-to-rsx-producer-found`.

Extended `tools/summarize_eternal_sonata_gpu_probe.ps1` so the GPU probe
summary now correlates sampled SPU max-DMA and MFC-shape EA ranges with RSX
resource profile rows from the same log:

- RSX blit-source profile `src`/`dst` ranges.
- RSX resolve profile base ranges.
- RSX texture-barrier profile base ranges.
- Output field: `Indirect RSX resource overlap records`.
- Optional CSV when overlap exists:
  `eternal-sonata-rsx-resource-overlap.csv`.

Field-to-first-battle Windows scout:

- Run dir:
  `debug-captures/windows-lab/20260518-212026-gpu-candidate-probe-fieldbattle-windows-windows/`
- Route:
  field movement into the active first-battle tutorial prompt on `\\.\DISPLAY2`.
- Visual result:
  correct-looking field and first-battle tutorial screenshots.
- GPU probe result:
  - `670` SPU candidate records;
  - about `898.25 MB` observed DMA;
  - top image `0x958dfe208b686622`;
  - hot PCs `0x451c` and `0x25cc`;
  - direct RSX-local traffic records: `0`;
  - offload mix: `spu-kernel-hle=435`, `too-small=235`.
- RSX resource profile result:
  - `3,093` raw RSX resource rows;
  - `84` aggregated RSX resource ranges;
  - indirect SPU-DMA/MFC-to-RSX overlap records: `0`.
- RSX pressure during the same route:
  - `12,060` auditor frames;
  - queue submits `12,384`, about `61.61` per 60 frames;
  - render-pass barrier breaks `5,953`, about `29.62` per 60 frames;
  - hot resolve is still `blit-source` on `base=0xc0b20000`;
  - hot depth texture barrier is still the bound read-only depth surface
    `base=0xc1260000`.

Academic/paper reading matched this result:

- GPU emulation wins such as CuLE work because many independent emulator
  instances are batched on the GPU.
- Binary-translation-to-GPU work is relevant when hot loops can be extracted and
  run with little coordination, not when each small SPU DMA command needs an
  immediate CPU-visible result.
- WebAssembly/GPU accelerator work similarly depends on keeping data resident
  and amortizing scheduling/copy costs.

Decision:

- Do not build a generic Vulkan compute path for the `0x25cc` / `0x451c` SPU
  jobs from this evidence. They remain SPU-kernel/HLE/codegen/MFC-ordering
  targets until a future capture finds GPU-consumed output.
- The best actual "RSX on GPU" route is still the RSX-local blit-source
  fused-resolve/live-texture-chain problem, because it already has stable
  GPU-resident resources and field/menu/battle correctness footholds.
- Under the current user gate, this remains Windows-only. There is still no
  stable 200% moving-gameplay proof, so do not port to Android or Thor.

## Windows Lab Slice - 2026-05-18 DepthReadOnly RSX Gate

Status: `best-rsx-locality-foothold-not-speed-proof`.

Added a narrower Windows-only texture-barrier mode:

- `tools/windows_rpcs3_lab.ps1 -RsxTextureBarrier DepthReadOnly`
- `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxTextureBarrier DepthReadOnly`
- Process env: `RPCS3_ES_RSX_TEXTURE_BARRIER=depth-readonly`

Unlike broad `Depth`, this gate only skips the BLUS30161 read-only depth
feedback-loop surface observed in profiling: depth, framebuffer-readonly, FBO
loops supported, render pass open, currently bound, `fmt=0x81`, `1280x720`,
`samples=2`, `grid=2x1`, `pitch=10240`. It is still Windows lab work, but it is
no longer "skip every depth texture barrier in the title."

Matched field-to-first-battle result:

- Run dir:
  `debug-captures/windows-lab/20260518-222010-rsx-texturebarrier-depthreadonly-fast-uncap-vblank240-fieldbattle-windows-windows/`
- Route:
  field movement into the active first-battle tutorial prompt on
  `\\.\DISPLAY2`.
- Visual result:
  correct-looking first-battle tutorial screenshots; no obvious black field,
  missing texture, or prompt corruption in `0053s` / `0058s`.
- Host grade: clean.
- Auditor totals across `12,120` frames:
  - queue submits: `12,445`, about `61.61` per 60 frames;
  - hard sync flushes: `101`, about `0.50` per 60 frames;
  - render-pass barrier breaks: `1,594`, about `7.89` per 60 frames;
  - break source `g/b/i/t`: `0/0/1594/0`;
  - texture barriers color/depth: `0/0`;
  - texture skips/post elides: `4364/798`;
  - hot texture profile: `4364` forced skips on `base=0xc1260000`.

Comparison against the same high-vblank fieldbattle family:

| Mode | Visual | Host | Render-pass Breaks / 60 | Texture Depth Barriers | Notes |
| --- | --- | --- | ---: | ---: | --- |
| Off | first battle correct | clean | `29.79` | `4379` | baseline from `20260518-214549` |
| Blit Fast | first battle correct | clean | `29.16` | `4296` | tiny counter move; no FPS proof |
| FastKeepSrc | first battle correct | clean | `29.73` | `4369` | not better than Fast |
| Fast + KeepReadOnly | first battle correct | clean | `29.73` | `4404` | lots of keep attempts, no hot barrier removal |
| Fast + DepthReadOnly | first battle correct | clean | `7.89` | `0` | narrow gate hits the measured depth loop |

Menu/status:

- Broad `Depth` run
  `20260518-220745-rsx-texturebarrier-skipdepth-fast-uncap-vblank240-menu-windows-windows`
  reached a correct-looking Options page, with render-pass breaks about `5.22`
  per 60 frames.
- Narrow `DepthReadOnly` menu attempts reached field/pause/cutscene-skip visuals
  without obvious corruption, but the input route did not reliably reach the
  full Options page. Do not count this as full menu validation yet.

Decision:

- This is the best current RSX-on-GPU/residency lane because it removes a large
  render-pass break class while staying title/surface-gated and fieldbattle
  correct on Windows.
- It is still not a 200% moving-gameplay performance proof. FPS in the
  fieldbattle route remains around the same `120 FPS` Windows ceiling, and menu
  routing needs a cleaner full-options checkpoint.
- Do not port to Android/Thor yet. Next Windows work should either improve the
  menu route and get a repeatable full Options screenshot for `DepthReadOnly`,
  or attack the remaining `render_target_resolve` image breaks / SPU
  `0x25cc`/`0x451c` codegen lane.

## Windows Lab Slice - 2026-05-18 Resolve Barrier Split

Status: `remaining-rsx-breaks-classified`.

Added Windows auditor detail for the resolve path:

- `resolve_barrier(rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable)`
- `resolve_break(rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable)`

The summarizer keeps old captures readable by defaulting missing fields to zero.

Build proof:

- `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`
  passed after the new instrumentation.

Clean DepthReadOnly + Fast fieldbattle run:

- Run dir:
  `debug-captures/windows-lab/20260518-232448-rsx-resolve-barrier-profile-depthreadonly-fast-fieldbattle-windows-windows/`
- Route:
  field movement into the first-battle tutorial prompt on `\\.\DISPLAY2`.
- Visual result:
  correct-looking first-battle tutorial screenshots in `0053s` / `0058s`.
- Host grade:
  one moderate CPU sample, otherwise clean; use as counter evidence, not FPS proof.
- Auditor totals across `12,060` frames:
  - render-pass barrier breaks: `1,598`, about `7.95` per 60 frames;
  - image break source `rt_res`: `1,598`;
  - color resolve calls/skips: `4,800` / `4,800`;
  - resolve barriers: `0/0/0/0/4800/4800/4800`;
  - resolve breaks: `0/0/0/0/1598/0/0`.

Reading: all remaining counted `render_target_resolve` image breaks in this
lane come from the fused blit-source source transition to `GENERAL`; none come
from the old normal RT resolve path, restore, or destination-readable tail.

Clean DepthReadOnly + FastKeepSrc fieldbattle run:

- Run dir:
  `debug-captures/windows-lab/20260518-232743-rsx-resolve-barrier-profile-depthreadonly-fastkeepsrc-fieldbattle-windows-windows/`
- Visual result:
  correct-looking first-battle tutorial screenshot in `0058s`.
- Host grade:
  clean.
- Auditor totals across `12,060` frames:
  - render-pass barrier breaks: `1,600`, about `7.96` per 60 frames;
  - color resolve calls/skips: `4,806` / `4,806`;
  - resolve barriers: `0/0/0/0/1602/0/4806`;
  - resolve breaks: `0/0/0/0/1600/0/0`.

Reading: keeping the source in `GENERAL` removes most non-breaking source
restore transitions, but it does not reduce the actual render-pass break count.
It is therefore not a meaningful Windows speed lane by itself.

Force Hardware MSAA Resolve re-check:

- Run dir:
  `debug-captures/windows-lab/20260518-233341-rsx-forcehwmsaa-depthreadonly-fast-fieldbattle-windows-windows/`
- Route:
  route drifted to story/cutscene instead of first-battle gameplay.
- Host grade:
  high because GPU engine utilization sum hit about `90%`.
- Visual:
  screenshots were not a comparable fieldbattle proof.
- Auditor totals across `9,300` frames:
  - render-pass barrier breaks: `5,720`, about `36.90` per 60 frames;
  - color/depth resolve calls: `17,169` / `4,704`;
  - depth texture barriers returned: `4,704`;
  - fused resolve fast count: `17,169`.

Reading: this global config makes the GPU busier but makes the RSX locality
problem worse in this route family. Do not chase global hardware MSAA resolve
as the speed path.

Research/context check:

- Vulkan `vkCmdDispatch` is normally an outside-render-pass command; the
  exception is the newer per-tile execution model. See
  <https://docs.vulkan.org/refpages/latest/refpages/source/vkCmdDispatch.html>.
- Vulkan subpass resolve attachments require a multisampled color attachment
  and a same-format single-sample resolve attachment. See
  <https://docs.vulkan.org/refpages/latest/refpages/source/VkSubpassDescription.html>.
- Qualcomm's `VK_QCOM_tile_shading` proposal is relevant to the Android/Adreno
  version of this problem because it is explicitly about running compute/draw
  work while tile attachments are still in tile memory. See
  <https://docs.vulkan.org/features/latest/features/proposals/VK_QCOM_tile_shading.html>.
- GPU binary translation/emulation research still points at batching/residency:
  VectorVisor runs many copies of the same application concurrently on the GPU,
  and CuLE gets speed by batching many Atari instances and rendering frames
  directly on the GPU. See
  <https://www.usenix.org/conference/atc23/presentation/ginzburg> and
  <https://arxiv.org/abs/1907.08467>.

Decision:

- The remaining RSX-local path is not "more tiny compute blits." The compute
  fused blit is useful for correctness/profiling, but it must leave the current
  render pass unless a renderpass-local/tile-local mechanism is used.
- The next RSX-only Windows research path is a feasibility spike for
  renderpass-local MSAA resolve/blit, such as subpass resolve/input-attachment
  structure or, later on Thor only after Windows proof gates, Adreno tile
  shading. This is a larger renderer-architecture change and not a quick
  switch.
- In parallel, the SPU `0x25cc` / `0x451c` codegen/HLE lane remains the
  stronger near-term CPU-load target because Windows and Thor captures both
  show it as a hot CPU/SPU path with no RSX-local output overlap.

## Windows Lab Slice - 2026-05-19 PadApi Options Route

Status: `padapi-control-proof-and-menu-validation`.

Implemented a Windows-only PadApi bridge for the lab build. The lab wrapper now
sets `RPCS3_ES_PAD_API_FILE`, writes PS3 button/stick state into a per-run
state file, and the RPCS3 keyboard pad layer overlays that state before pad
output. This keeps title/menu routing independent of Windows focus and
`keybd_event` delivery while preserving the normal keyboard path when the env
var is unset.

Proof runs, both on `\\.\DISPLAY2`:

- `debug-captures/windows-lab/20260519-154942-rsx-padapi-title-options-proof-windows-windows/`
  proved delivery but not the route: `cross` advanced the intro/cutscene to the
  title screen, while the two `down` presses happened too early.
- `debug-captures/windows-lab/20260519-155213-rsx-padapi-title-options-after-skip-windows-windows/`
  proved the route: `0079s` shows title on `New Game`, `0080s` / `0082s` show
  selection moved to `Options`, and `0091s` shows the full Options page.
- `debug-captures/windows-lab/20260519-160309-rsx-padapi-title-options-postbuild-windows-windows/`
  repeated the same proof after rebuilding the hardened PadApi bridge:
  `0079s` title, `0081s` Options selected, and `0091s` full Options page.

The successful run used:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label rsx-padapi-title-options-after-skip-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve Fast -WindowsRsxAuditor 60 -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsGameScreen 1 -MaxSeconds 95 -InputMacro "wait:65000;shot:100;cross:180;wait:6000;shot:100;down:250;wait:1000;shot:100;down:250;wait:1000;shot:100;cross:180;wait:8000;shot:100;wait:6000;shot:100"
```

Auditor summary for the post-build Options run:

- Host grade: moderate due one postlaunch CPU sample, otherwise clean; use this
  as control-path proof and counter evidence, not FPS proof.
- Auditor frames: `19,620`.
- Queue submits: `19,785`, about `60.50` per 60 frames.
- Hard sync flushes: `102`, about `0.31` per 60 frames.
- Render-pass barrier breaks: `3,873`, about `11.84` per 60 frames.
- Fused GPU resolve/blit dispatches: `11,631`, about `35.57` per 60 frames.
- RSX-local credit events: `11,631`, about `35.57` per 60 frames.
- Remaining render-pass break debt: `3,873`, about `11.84` per 60 frames.

Decision:

- PadApi is now the default Windows control path for title/menu routing after
  one keyboard focus attempt.
- The previous `DepthReadOnly + Fast` menu-routing blocker is closed on
  Windows: the route reaches a clean full Options screen with before/after
  screenshots.
- This is still only RSX-local residency credit, not promoted CPU/SPU/PPU job
  bytes and not a 200% moving-gameplay proof. Keep all Thor/Android work gated
  off until Windows has stable, correctness-checked moving-gameplay wins.

## Windows Lab Slice - 2026-05-19 Depth Feedback Credit

Status: `more-rsx-gpu-residency-credit`.

With the PadApi title/menu route fixed, reran the RSX-local stack with
`DepthReadOnly + Fast + KeepReadOnly`:

- `-WindowsRsxTextureBarrier DepthReadOnly`
- `-WindowsRsxBlitSourceResolve Fast`
- `-WindowsRsxDepthFeedback KeepReadOnly`
- `-WindowsInputBackend PadApi`
- `-WindowsGameScreen 1`

Options route:

- Run dir:
  `debug-captures/windows-lab/20260519-161410-rsx-padapi-options-depthreadonly-fast-keepfeedback-windows-windows/`
- Visual:
  clean full Options screen at `screenshot-0091s.png`.
- Host grade:
  moderate because postlaunch CPU crossed the clean threshold; use for
  correctness/counters, not FPS.
- Auditor frames:
  `19,500`.
- Render-pass barrier breaks:
  `3,813`, about `11.73` per 60 frames.
- Depth feedback prep keep/layout/write:
  `66,616/0/57,795`.
- Depth feedback end keep/layout/write/restore:
  `3,658/0/1/0`.
- Fused GPU resolve/blit dispatches:
  `11,451`, about `35.23` per 60 frames.
- RSX-local credit events:
  `81,725`, about `251.46` per 60 frames.

Field route:

- Run dir:
  `debug-captures/windows-lab/20260519-162400-rsx-field-depthreadonly-fast-keepfeedback-windows-windows/`
- Visual:
  clean field screenshots at `screenshot-0136s.png` and `screenshot-0151s.png`;
  no obvious missing textures, black field, or menu overlay corruption.
- Host grade:
  moderate because one CPU/GPU sample crossed the clean threshold; use for
  correctness/counters, not FPS.
- Auditor frames:
  `25,560`.
- Render-pass barrier breaks:
  `13,205`, about `31.00` per 60 frames.
- Depth feedback prep keep/layout/write:
  `118,785/0/94,354`.
- Depth feedback end keep/layout/write/restore:
  `12,168/0/1/0`.
- Fused GPU resolve/blit dispatches:
  `39,636`, about `93.04` per 60 frames.
- RSX-local credit events:
  `170,589`, about `400.44` per 60 frames.

Battle route attempt:

- Run dir:
  `debug-captures/windows-lab/20260519-161721-rsx-battle-depthreadonly-fast-keepfeedback-windows-windows/`
- Result:
  route did not reach battle; screenshots stayed in the field. The outer shell
  timeout interrupted final log copy, so do not use it for auditor metrics.
- Reading:
  the field visuals still looked clean, but this is a route failure, not a
  battle proof.
- Follow-up route-2 attempt:
  `debug-captures/windows-lab/20260519-163212-rsx-battle-depthreadonly-fast-keepfeedback-route2-windows-windows/`
  failed early in the lab script after launch and left RPCS3 running; the
  leftover process was stopped. The unvalidated route tweak was reverted. Do
  not use this folder for correctness or auditor metrics.

Decision:

- `KeepReadOnly` is now a valid additional RSX-local residency credit when
  paired with `DepthReadOnly + Fast`: it converts depth-feedback end restores
  into read-only layout keeps and greatly increases measured GPU-local credit in
  both field and Options routes.
- This still does not move SPU/PPU bytes to GPU and does not prove a Windows
  FPS win; the field route remains around the same visible `120 FPS` cap.
- The remaining RSX-local debt is still `blit_src_to_general` breaking the
  render pass. Next Windows RSX work should focus on renderpass-local/tile-local
  resolve/blit feasibility, or on making the first-battle route deterministic
  with PadApi so this combined gate can be checked against battle visuals.
- Do not port this to Android/Thor under the current user gate.

## Windows Lab Slice - 2026-05-19 Battle Route Proof

Status: `battle-visual-pass-gpu-residency-credit`.

While validating the combined `DepthReadOnly + Fast + KeepReadOnly` stack, the
Windows PadApi battle route exposed a control bug: `Set-LabPadApiState` used a
fixed `.tmp` path and `Move-Item -Force`, which can fail during combo state
replacement with `Cannot create a file when that file already exists.` The
writer now uses a unique temp path with replace/copy retry, so PadApi combos no
longer abort the macro and leave RPCS3 running.

Proven battle route:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -Label rsx-battle-padapi-left-downleft-keepfeedback-retry `
  -WindowsInputBackend PadApi `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve Fast `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxAuditor 60 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -WindowsGameScreen 1 `
  -MaxSeconds 330
```

Run dir:

- `debug-captures/windows-lab/20260519-170902-rsx-battle-padapi-left-downleft-keepfeedback-retry-windows/`

Visuals:

- `screenshot-0135s.png`: correct field before movement.
- `screenshot-0187s.png`: first-battle tutorial prompt.
- `screenshot-0248s.png` and `screenshot-0309s.png`: active first-battle UI
  with correct-looking character, arena, HUD, and command ring. No obvious
  black field, missing textures, or menu/HUD corruption.

Host:

- Clean host contention summary across 4 snapshots.

Auditor summary:

- Auditor frames: `44,280`.
- Queue submits: `44,664`, about `60.52` per 60 frames.
- Hard sync flushes: `103`, about `0.14` per 60 frames.
- Render-pass barrier breaks: `8,960`, about `12.14` per 60 frames.
- Resolve break detail is still entirely `blit_src`: `8,960`.
- Depth feedback prep keep/layout/write: `277,807/0/197,284`.
- Depth feedback end keep/layout/write/restore: `30,883/0/1/0`.
- Fused GPU resolve/blit dispatches: `26,907`, about `36.46` per 60 frames.
- RSX-local credit events: `335,597`, about `454.74` per 60 frames.

Decision:

- The combined RSX-local stack now has field, Options/menu, and first-battle
  visual proof on Windows.
- This promotes the stack from `gpu-migration-credit-candidate` to a durable
  Windows `gpu-migration-credit` for RSX residency/locality.
- It is still not a speed win: the route remains around the Windows `120 FPS`
  cap and does not prove a 200% moving-gameplay improvement.
- The next RSX-only target remains the `blit_src_to_general` render-pass break
  debt. Any further GPU work should reduce that debt or move actual CPU/SPU
  bytes, with verify mode first.
- Do not port this to Android/Thor under the current user gate.

## Windows Lab Slice - 2026-05-19 Present Upload GPU Swap

Status: `gpu-migration-credit-small-present-upload`.

Implemented an opt-in Windows lab path that moves Eternal Sonata's fallback
present-upload byte swap from the CPU row loop into the existing Vulkan
upload/GPU shuffle path. The new switch is:

```powershell
-WindowsRsxPresentUpload GpuSwap
```

`tools/windows_rpcs3_lab.ps1` maps this to
`RPCS3_ES_RSX_PRESENT_UPLOAD=gpu-swap`; default `Off` keeps stock behavior. The
upstream lab patch gates the fast path to `BLUS30161`, the opt-in env mode, a
valid pitch/size, and `VK_FORMAT_B8G8R8A8_UNORM`. The auditor now logs
`present_upload(cpu/gpu)` and `present_upload_bytes(cpu/gpu)`, and
`tools/summarize_eternal_sonata_rsx_auditor.ps1` reports the split plus a GPU
migration credit row.

Menu/Options proof:

- Run dir:
  `debug-captures/windows-lab/20260519-190002-rsx-present-gpuswap-field-windows-windows/`
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label rsx-present-gpuswap-field-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve Fast -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsGameScreen 1 -MaxSeconds 150 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 30 -ScreenshotMaxCount 8
```

- Visual:
  clean title Options page. This is menu proof, despite the `field` scene label.
- Auditor:
  `present_upload(cpu/gpu)=0/1`,
  `present_upload_bytes(cpu/gpu)=0/3686400`, about `3.52 MB` GPU.

Field proof:

- Run dir:
  `debug-captures/windows-lab/20260519-190656-rsx-present-gpuswap-field-ps3native-windows-windows/`
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label rsx-present-gpuswap-field-ps3native-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve Fast -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsGameScreen 1 -MaxSeconds 170 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4
```

- Visual:
  clean Path to Tenuto field at `screenshot-0147s.png`.
- Host:
  clean host contention.
- Auditor:
  `7,680` auditor frames, `4,322` render-pass barrier breaks
  (`33.77` per 60), `12,972` fused GPU resolve/blit dispatches,
  `29,558` read-only depth feedback keeps, and present upload split
  `cpu=0/0.00 MB`, `gpu=1/3.52 MB`.

Battle proof:

- Run dir:
  `debug-captures/windows-lab/20260519-191046-rsx-present-gpuswap-battle-windows-windows/`
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label rsx-present-gpuswap-battle-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve Fast -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsGameScreen 1 -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 10
```

- Visual:
  clean active first-battle UI at `screenshot-0309s.png`, with correct-looking
  character, arena, HUD, and command ring.
- Host:
  clean host contention.
- Auditor:
  `12,540` auditor frames, `2,182` render-pass barrier breaks
  (`10.44` per 60), `6,552` fused GPU resolve/blit dispatches, `69,806`
  read-only depth feedback keeps, and present upload split `cpu=0/0.00 MB`,
  `gpu=1/3.52 MB`.

Decision:

- This is real CPU-to-GPU migration credit: one fallback present upload per
  proven route now uses Vulkan upload/GPU shuffle instead of CPU byte-swap row
  conversion.
- It is intentionally small: about `3.52 MB` per boot/route. It does not reduce
  the remaining `blit_src_to_general` render-pass break debt, does not move SPU
  or PPU job bytes, and is not a measurable speed win.
- Keep it opt-in and Windows-only. Do not port to Android/Thor before the
  standing 200% Windows moving-gameplay gate is met.
- Next RSX-only target remains renderpass-local/tile-local resolve/blit
  architecture for `blit_src_to_general`. If looking for bigger CPU load
  movement, return to SPU reservation/reduced-loop/codegen evidence rather than
  one-dispatch-per-DMA Vulkan compute.

## Windows Lab Slice - 2026-05-19 Sampled MSAA Blit-Source Resolve

Status: `gpu-migration-credit-sampled-msaa-variant`.

Implemented a new blit-source resolve mode:

```powershell
-WindowsRsxBlitSourceResolve VerifySampled
-WindowsRsxBlitSourceResolve FastSampled
```

The wrapper maps these to
`RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=verify-sampled|fast-sampled`. The old `Fast`
path reads the MSAA source as a storage image in `GENERAL`. The sampled path
reads the same MSAA source through `sampler2DMS` in
`SHADER_READ_ONLY_OPTIMAL`, then writes the resolved/blitted result through the
existing storage destination. The goal is a cleaner GPU-read shape that is
closer to mobile/tile-friendly rendering research, not a claim that the
render-pass break is solved.

Scratch verify field:

- Run dir:
  `debug-captures/windows-lab/20260519-195434-rsx-blitsource-sampled-verify-field-windows-windows/`
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label rsx-blitsource-sampled-verify-field-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve VerifySampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsGameScreen 1 -MaxSeconds 165 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4
```

- Visual:
  clean Path to Tenuto field at `screenshot-0147s.png`.
- Auditor:
  `3,976` verify dispatches, `3,974` render-pass barrier breaks, and one
  `3.52 MB` GPU present-upload swap. No shader compile, validation, or fatal
  RSX errors were found.

Fast field:

- Run dir:
  `debug-captures/windows-lab/20260519-195808-rsx-blitsource-sampled-fast-field-windows-windows/`
- Visual:
  clean Path to Tenuto field at `screenshot-0147s.png`.
- Auditor:
  `12,324` fast dispatches, `4,106` render-pass barrier breaks, and one
  `3.52 MB` GPU present-upload swap. Host grade clean.

Fast Options/menu:

- Run dir:
  `debug-captures/windows-lab/20260519-200154-rsx-blitsource-sampled-fast-menu-windows-windows/`
- Visual:
  clean full Options page at `screenshot-0138s.png`.
- Auditor:
  `7,815` fast dispatches, `2,603` render-pass barrier breaks, and one
  `3.52 MB` GPU present-upload swap. Host grade clean.

Fast first battle:

- Run dir:
  `debug-captures/windows-lab/20260519-200516-rsx-blitsource-sampled-fast-battle-windows-windows/`
- Visual:
  clean active first-battle UI at `screenshot-0309s.png`, with correct-looking
  arena, character, HUD, command ring, and overlays.
- Auditor:
  `6,570` fast dispatches, `2,187` render-pass barrier breaks, `69,764`
  read-only depth feedback keeps, and one `3.52 MB` GPU present-upload swap.
  Host grade clean.

Decision:

- `FastSampled` is a real Windows RSX `gpu-migration-credit` variant after
  field, Options/menu, and first-battle visual proof.
- It is not a speed win. FPS remained at the native/capped route expectations,
  and the main `blit_src` source-layout render-pass break debt remains.
- Keep it opt-in and Windows-only under the 200% gate. Do not port to
  Android/Thor yet.
- Next RSX work must be more architectural: renderpass-local/tile-local
  resolve/blit, or a proof that the source can stay readable without leaving
  the render pass. Otherwise, switch back to SPU reservation/reduced-loop/codegen
  for larger CPU-load movement.

Counter split follow-up:

- Run dir:
  `debug-captures/windows-lab/20260519-202952-rsx-blitsource-sampled-counter-field-windows-windows/`
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label rsx-blitsource-sampled-counter-field-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsGameScreen 1 -MaxSeconds 165 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4
```

- Visual:
  clean Path to Tenuto field at `screenshot-0147s.png`.
- Auditor:
  `7,560` frames, `7,689` queue submits, `107` hard sync flushes, `4,092`
  render-pass barrier breaks, and one `3.52 MB` GPU present-upload swap.
- New path split:
  `blit_resolve_path(storage_fast/sampled_fast/storage_verify/sampled_verify)=0/12282/0/0`.
  This proves the `FastSampled` run used sampled-MSAA GPU reads and did not just
  reuse the storage-image fast path.
- Validation:
  Release build passed. Summarizer parser and old-log fallback passed. No new
  Vulkan validation, shader compile, or fatal RSX errors were found; the log
  still contains the known Eternal Sonata PRX/ESRCH/savedata messages.
- Decision:
  keep `FastSampled` as measured Windows `gpu-migration-credit`. It is not a
  speed win and not a Thor promotion gate.

Failed keep-source probe:

- Hypothesis:
  leaving the sampled MSAA source in `SHADER_READ_ONLY_OPTIMAL` after a fused
  dispatch might let later chunks reuse the same readable source and avoid
  redundant non-breaking source transitions/restores.
- Temporary mode:
  `FastSampledKeepSrc`, mapped to
  `RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=fast-sampled-keep-src`.
- Run dir:
  `debug-captures/windows-lab/20260519-210056-rsx-blitsource-sampled-keepsrc-field-windows-windows/`
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label rsx-blitsource-sampled-keepsrc-field-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampledKeepSrc -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsGameScreen 1 -MaxSeconds 165 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4
```

- Result:
  failed. The field rendered black, the route froze, and `RPCS3.log`/stderr
  reported `Unsupported image layout 0x5` from the RSX thread.
- Counters:
  `5,460` auditor frames, `5,578` queue submits, `104` hard sync flushes,
  `0` render-pass breaks, `0` fused fast/verify dispatches, and `7,197`
  blit-source rejects. The zero-break result is not useful because the
  candidate did not produce visible frames or reach the fused path.
- Decision:
  `failed`. The temporary switch was removed and the safe tree rebuilt. Do not
  re-add sampled keep-source without first changing the render-target rebind or
  render-pass key path so a shader-read source can legally become an attachment
  again before drawing.

## Windows Lab Slice - 2026-05-19 Battle Kernel/GPU Scout

Status: `parked-no-new-spu-gpu-lane`.

Purpose:

- Re-check first battle with both SPU/kernel capsule scouting and the current
  clean RSX residency stack, in case combat exposes RSX-consumed SPU work that
  field/menu did not.
- Keep the run Windows-only and on the second screen under the 200% Thor gate.

Run:

- Run dir:
  `debug-captures/windows-lab/20260519-211905-kernel-capsule-gpu-scout-battle-windows-windows/`
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap`.
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label kernel-capsule-gpu-scout-battle-windows -EternalSonataKernelCapsule Profile -EternalSonataGpuProbe Profile -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsGameScreen 1 -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 10
```

Visual/log result:

- Reached active first-battle UI with clean-looking arena, character, HUD, and
  command ring at `screenshots/screenshot-0244s.png` and
  `screenshots/screenshot-0311s-01.png`.
- Host contention stayed clean.
- Log scan found no real fatal, validation, shader compile, access-violation, or
  `Unsupported image layout` hit. The only `fatal` match was a config line.

GPU probe:

- Records: `2586`.
- Observed DMA: `3,641.99 MB`.
- Largest single job: `3.42 MB` in `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`.
- Direct RSX-local traffic: `0`.
- Indirect RSX resource overlap: `0`.
- Offload fit mix: `spu-kernel-hle=2057`, `too-small=529`.
- Hot PCs: `0x25cc` (`2,369.14 MB`) and `0x451c` (`1,272.85 MB`).

Kernel capsule classifier:

- Capsule rows: `3141`.
- Capsule records observed: `7,711,909`.
- Capsule DMA bytes: `3,641.99 MB`.
- RSX-local bytes inside capsules: `0 B`.
- GPU-batch candidates: `0`.
- Class: all `reservation-risk`, with wait/atomic reads present.

RSX auditor:

- Auditor frames: `12540`.
- Queue submits: `12781`, about `61.15` per 60 frames.
- Hard sync flushes: `106`, about `0.51` per 60 frames.
- Render-pass barrier breaks: `2186`, about `10.46` per 60 frames.
- Blit-source fused resolve: `6564` fast dispatches, all sampled path:
  `blit_resolve_path(storage_fast/sampled_fast/storage_verify/sampled_verify)=0/6564/0/0`.
- Present upload: `cpu=0`, `gpu=1`, `3.52 MB`.
- GPU migration credit class: `gpu-migration-credit-candidate`.

Decision:

- The current RSX stack remains visually valid in first battle and continues to
  move small RSX-local/present-upload work onto the GPU.
- This run did not find a new SPU-to-GPU offload lane. The battle hot work is
  still large SPU/DMA kernel traffic with reservation/atomic risk and no
  RSX-local or indirect RSX overlap.
- Do not build a Vulkan compute mirror for these `0x25cc` / `0x451c` capsules
  yet. The smarter next GPU work is true renderpass-local/tile-local RSX
  architecture; the smarter CPU-load work is SPU kernel HLE/codegen/reduced-loop
  specialization with shadow verification.

## Windows Lab Slice - 2026-05-19 Blit-Source Coalescing Scout

Status: `source-resolve-cache-candidate`.

Purpose:

- Profile the remaining `blit_src` render-pass/locality debt after the
  `FastSampled` proof, without changing visible output.
- Find out whether the repeated fused GPU resolves are stable enough for a
  source-resolve cache/coalescer instead of another unsafe layout shortcut.

Run:

- Run dir:
  `debug-captures/windows-lab/20260519-214153-rsx-blitsource-profile-fastsampled-field-windows-windows/`
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Resolve Profile`.
- Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label rsx-blitsource-profile-fastsampled-field-windows -WindowsInputBackend PadApi -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxResolve Profile -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxAuditor 60 -WindowsGameScreen 1 -MaxSeconds 170 -ScreenshotEverySeconds 15 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 4
```

Visual/log result:

- Clean field visual at `screenshots/screenshot-0147s.png`.
- Host contention stayed clean.
- Log scan found no real fatal, validation, shader compile, access-violation, or
  `Unsupported image layout` hit. The only `fatal` match was a config line.

RSX summary:

- Auditor frames: `7680`.
- Render-pass barrier breaks: `4318`, all from `blit_src_to_general`.
- Sampled blit-source fused dispatches: `12960`.
- Present upload split: `cpu=0`, `gpu=1`, `3.52 MB`.
- Resolve profile: one hot blit-source target, `1280x720`, format `0x2c`, 2x
  MSAA grid `2x1`, pitch `10240`, base `0xc0b20000`.
- Blit source profile: `25` keys, top key `0xd15bac2e1cb3e31b` accounts for
  `7952` calls.

New summarizer support:

- `tools/summarize_eternal_sonata_rsx_auditor.ps1` now emits
  `Resolve Coalescing Scout` when resolve profile rows are present.
- Current run:
  - profiled blit-source resolve calls: `12960`;
  - duplicate source-tag calls: `8640`;
  - unique source-tag floor: `4320`;
  - duplicate share: `66.67%`.

Decision:

- This is the first genuinely interesting next RSX architecture target after
  the keep-source failure. The source content repeats far more often than the
  destination writes do.
- Candidate design: a verify-first source-resolve cache that resolves the
  repeated MSAA source once per content tag into a GPU-resident single-sample
  image, then fans out exact destination blits/copies from that image.
- Do not skip destination writes. The duplicate-tag count is an upper bound for
  source-resolve/coalescing work, not a correctness proof and not a measured FPS
  win.

## Windows Lab Slice - 2026-05-19 Cached Source Resolve And Host DMA Fence

Status: `fast-cached-source-triad-pass`.

Purpose:

- Try the source-resolve cache idea in verify mode first, then reject or keep it
  based on counters instead of vibes.
- Add the existing host-read DMA fence mode to the current RSX stack and push it
  through field, menu, and first-battle visuals on Windows only.

Cached source resolve probe:

- Run dir:
  `debug-captures/windows-lab/20260519-221519-rsx-blitsource-verifycachedsampled-field-v2-windows-windows/`
- Stack:
  `DepthReadOnly + VerifyCachedSampled + KeepReadOnly + GpuSwap + Resolve Profile`.
- Visual:
  clean Path to Tenuto field at `screenshots/screenshot-0147s.png`.
- Error scan:
  no real fatal, validation, shader compile, access-violation, or unsupported
  layout hit. The only `fatal` matches were config lines.
- Auditor:
  `4376` verify sampled dispatches, `4374` render-pass breaks,
  `blit_cache(hit/miss/fill/fanout/reject)=0/4376/4376/4376/0`, and
  `duplicate_tags=0`.

Reading:

- The layout fix made the cached verify path visually correct, but verify mode
  fell back into the normal visible path, so it filled once per candidate and
  never hit. This was a verify-mode artifact, not a final cache verdict.

Fast cached source resolve proof:

- Field run:
  `debug-captures/windows-lab/20260519-223810-rsx-blitsource-fastcachedsampled-field-windows-windows/`
- Menu/pause run:
  `debug-captures/windows-lab/20260519-224209-rsx-blitsource-fastcachedsampled-menu-windows-windows/`
- Battle run:
  `debug-captures/windows-lab/20260519-224632-rsx-blitsource-fastcachedsampled-battle-windows-windows/`
- Stack:
  `DepthReadOnly + FastCachedSampled + KeepReadOnly + GpuSwap + Host DMA fence + Resolve Profile`.
- Visuals:
  clean field at field `screenshot-0147s.png`, clean pause/menu overlay at menu
  `screenshot-0138s.png`, and clean active first-battle UI at battle
  `screenshot-0244s.png` / `screenshot-0309s.png`.
- Error scans:
  no real fatal, validation, shader compile, access-violation, or unsupported
  layout hits. The only `fatal` matches were config lines.

Fast cached counter summary:

| Scene | Host | Cache Hit/Miss/Fill/Fanout/Reject | Fused Sampled Dispatches | Render-Pass Breaks / 60 | DMA Fence Split |
| --- | --- | --- | ---: | ---: | --- |
| Field | clean | `8644/4322/4322/12966/0` | `12966` | `33.75` | `all=0 / host=15` |
| Menu/pause | clean | `11104/5552/5552/16656/0` | `16656` | `40.22` | `all=0 / host=15` |
| Battle | moderate | `4372/2186/2186/6558/0` | `6558` | `10.45` | `all=0 / host=75` |

Reading:

- `FastCachedSampled` hit the expected repeated-source pattern: about one full
  source resolve fill per unique source tag, followed by two cached fanouts, with
  no rejected cache operations in field, menu, or battle.
- This is a real Windows RSX `gpu-migration-credit` candidate because it keeps
  the repeated resolved source GPU-resident and fans out destination writes from
  that image.
- It is still not a 200% speed proof. It does not remove the remaining
  `blit_src_to_general` render-pass break because the first fill still has to
  leave the render pass and resolve the MSAA source.

Host-read DMA fence proof:

- Field run:
  `debug-captures/windows-lab/20260519-222018-rsx-hostdma-fastsampled-field-windows-windows/`
- Battle run:
  `debug-captures/windows-lab/20260519-222407-rsx-hostdma-fastsampled-battle-windows-windows/`
- Menu/pause run:
  `debug-captures/windows-lab/20260519-223044-rsx-hostdma-fastsampled-menu-windows-windows/`
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA fence + Resolve Profile`.
- Visuals:
  clean field at field `screenshot-0147s.png`, clean active first-battle UI at
  battle `screenshot-0244s.png` and `screenshot-0304s.png`, clean pause/menu
  overlay at menu `screenshot-0138s.png`.
- Error scans:
  no real fatal, validation, shader compile, access-violation, or unsupported
  layout hits. The only `fatal` matches were config lines.

Counter summary:

| Scene | Host | Fused Sampled Dispatches | Render-Pass Breaks / 60 | DMA Fence Split | DMA MB Split | RSX Credit / 60 |
| --- | --- | ---: | ---: | --- | --- | ---: |
| Field | clean | `12984` | `33.80` | `all=0 / host=15` | `0.00 / 24.20` | `349.49` |
| Battle | clean | `6564` | `10.46` | `all=0 / host=74` | `0.00 / 54.97` | `398.51` |
| Menu/pause | moderate | `16536` | `39.93` | `all=0 / host=15` | `0.00 / 24.20` | `397.36` |

Decision:

- `-WindowsRsxDmaFence Host` is now a Windows triad-pass micro-credit when
  combined with `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap`.
- This narrows `VKTextureCache` DMA synchronization from broad `ALL_COMMANDS`
  to host-read waits in the proven scenes. It is a residency/sync win, not a
  200% performance proof.
- Keep this Windows-only and opt-in under the standing gate. Do not port or
  enable it on Android/Thor until a stable 200% Windows moving-gameplay proof
  exists.
- Next work should target the remaining `blit_src_to_general` render-pass break
  debt and compare `FastSampled` versus `FastCachedSampled` in matched uncapped
  Windows movement. Do not port either cached-source or host-DMA work to Thor
  until the 200% gate is actually met.

## Windows Lab Slice - 2026-05-20 Cached Transfer Source And Route Repair

Status: `gpu-migration-credit-route-blocked`.

Purpose:

- Keep pushing repeated RSX source-resolve work toward GPU residency without
  pretending this is a 200% speed win.
- Repair the Windows route after discovering that older field/menu runs were
  selecting title Options instead of actually loading the field.

Implementation:

- Added `FastCachedTransferSampled`, which keeps the cached single-sample
  source image in `TRANSFER_SRC_OPTIMAL` and fans out destination copies from
  that GPU-resident transfer source.
- Extended the RSX auditor and summarizer with
  `blit_cache_transfer_src(fill/fanout)`.
- Added branch-labeled Windows screenshots to `tools/windows_rpcs3_lab.ps1`
  (`shot:label`).
- Corrected the Windows Eternal Sonata load pulse to use `down:20` on the title
  menu; `down:120` or `ls_down:120` could skip straight to title Options.

Build/tool checks:

- `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`
  passed in `rpcs3-upstream`.
- PowerShell parser checks passed for the touched Windows tools.

Route evidence:

- `debug-captures/windows-lab/20260520-000826-route-debug-load-ack-windows-windows/`
  proved the fixed save-load sequence reaches a clean Path to Tenuto field image
  after acknowledging `Load complete`.
- `debug-captures/windows-lab/20260520-002600-route-debug-skip-to-field-windows-windows/`,
  `20260520-002925-route-debug-active-field-windows-windows/`,
  `20260520-003320-route-debug-resume-circle-windows-windows/`, and
  `20260520-003703-route-debug-resume-cross-windows-windows/` proved the next
  route blocker: skipping the loaded cutscene leaves a plain `Pause` overlay,
  and current PadApi `start`, `circle`, and `cross` resume attempts did not
  dismiss it.

True-field cached-transfer proof:

- Variant:
  `debug-captures/windows-lab/20260520-001217-rsx-blitsource-fastcachedtransfer-field-true-windows-windows/`
- Control:
  `debug-captures/windows-lab/20260520-001700-rsx-blitsource-fastsampled-field-true-control-windows-windows/`
- Stack:
  `DepthReadOnly + KeepReadOnly + GpuSwap + Host DMA fence + Resolve Profile`,
  with `FastCachedTransferSampled` versus `FastSampled`.
- Visuals:
  both runs reached clean true field/cutscene visuals. Do not count these as
  active moving gameplay, because the post-load cutscene/pause route is not yet
  solved.
- Error scan:
  no real fatal, validation, access-violation, VK error, or unsupported-layout
  hit; the only `fatal` match was the config line.

Counter comparison:

| Mode | Auditor Frames | Fused Sampled Dispatches | Cache Hit/Miss/Fill/Fanout/Reject | Transfer-Src Fill/Fanout | Render-Pass Breaks / 60 | Screenshot FPS Point |
| --- | ---: | ---: | --- | --- | ---: | ---: |
| `FastSampled` | `24000` | `52299` | `0/0/0/0/0` | `0/0` | `43.57` | about `112` |
| `FastCachedTransferSampled` | `24480` | `52677` | `35118/17559/17559/52677/0` | `17559/52677` | `43.03` | about `101` |

Reading:

- `FastCachedTransferSampled` is a real GPU-residency/migration-credit path: it
  resolves each unique source tag into a GPU-local cache image, keeps that image
  as a transfer source, and fans out every destination copy from GPU memory.
- It is not a speed win in this true-field A/B. It reduces repeated source
  resolve work and layout churn, but it does not remove the first
  `blit_src_to_general` render-pass break per unique source tag.
- The next RSX architecture target is still the source fill break itself:
  deferred/cache fill after renderpass close, renderpass-local resolve/blit
  design, or another verify-first approach that preserves attachment reuse.
- Do not port this to Thor and do not include it in the 200% gate until active
  moving field, menu/Options, and first battle are clean and materially faster.

### Constrained CPU A/B - 2026-05-20

Question:

- Would this kind of RSX GPU-residency path help more on a smaller CPU than on
  the beefy Windows host?

Tooling added:

- `tools/windows_rpcs3_lab.ps1` now accepts `-CpuAffinityMask`.
- `tools/eternal_sonata_speed_sprint.ps1` now accepts
  `-WindowsCpuAffinityMask` and forwards it to the Windows lab runner.
- `0x0F` pins RPCS3 to the first four logical CPUs and logs the applied mask.

Matched clean-field attempt:

- Control:
  `debug-captures/windows-lab/20260520-111750-cpu4-fastsampled-field-robust2-windows-windows/`
- Variant:
  `debug-captures/windows-lab/20260520-112229-cpu4-fastcachedtransfer-field-robust2-windows-windows/`
- Shared macro:
  `wait:45000;down:20;wait:800;cross:120;wait:15000;shot:load-list;cross:120;wait:5000;shot:confirm;up:40;wait:1000;shot:yes;cross:120;wait:30000;shot:after-confirm-wait;combo:ls_right+ls_down:2500;wait:1000;cross:120;wait:30000;shot:field-final;wait:20000;shot:field-late`

Field-late screenshot/host readings:

| Mode | Window Title FPS | Overlay FPS | Overlay CPU | RPCS3 CPU | Host GPU Engine Sum |
| --- | ---: | ---: | --- | ---: | ---: |
| `FastSampled` | `29.94` | `42.66` | PPU `1.2%`, SPU `21.8%`, RSX `0.9%`, Total `23.9%` | `26.2` | `20.1` |
| `FastCachedTransferSampled` | `31.55` | `29.86` | PPU `1.2%`, SPU `22.7%`, RSX `0.9%`, Total `24.8%` | `26.1` | `26.7` |

Reading:

- The smaller-CPU theory is plausible in general: a path that genuinely removes
  CPU bookkeeping, memcpy, endian swap, sync, or layout churn can matter more on
  a CPU-limited handheld-class host.
- This specific cached-transfer path did not prove that. It made the GPU busier
  and kept visuals clean, but measured RPCS3 CPU stayed essentially flat and
  the final overlay FPS was worse than `FastSampled`.
- Classify the constrained run as `gpu-migration-credit`, not
  `windows-micro-win`.
- Next GPU work should target CPU-visible work that can actually disappear:
  renderpass-local/tile-local source fill, upload conversion, persistent GPU
  scratch/caches, or batched RSX-consumed transforms. Do not spend more time
  optimizing cached-transfer fanout unless a scout shows it removes CPU load or
  render-pass breaks.

## Windows Lab Slice - 2026-05-20 Source Layout And Vertex/Index Scout

Status: `gpu-migration-credit-scout`.

Source-layout result:

- `FastSampled` robust field:
  `debug-captures/windows-lab/20260520-122644-rsx-auditor-fastsampled-field-robust2-windows/`.
- `FastKeepSrc` robust field:
  `debug-captures/windows-lab/20260520-123058-rsx-auditor-fastkeepsrc-field-robust2-windows/`.
- Both runs reached clean field screenshots.
- `FastKeepSrc` removed the non-breaking source restore churn, but actual
  source-read render-pass breaks stayed flat: `FastSampled` logged about
  `4002` `blit_src` breaks (`29.64` per 60), while `FastKeepSrc` logged about
  `4096` (`30.12` per 60).

Decision:

- Park `FastKeepSrc` as correctness-clean but not a speed lane. The next RSX
  architecture target remains the first source fill/read break, not source
  restore cleanup.

Tooling added:

- `rpcs3-upstream` RSX auditor now logs vertex/index upload pressure:
  `vertex_upload(draws/cache_hit/cache_miss/persistent_mb/volatile_mb)` and
  `index_upload(draws/emulated/restart/mb)`.
- `tools/summarize_eternal_sonata_rsx_auditor.ps1` parses those mixed
  integer/decimal tuples, exports them in CSV, adds totals, and classifies
  heavy intervals as `vertex-index-upload`.
- `tools/windows_rpcs3_lab.ps1` now raises the RPCS3 window foreground/topmost
  before screenshots. Earlier run
  `20260520-124609-rsx-auditor-vertex-index-field-windows` captured the wrong
  browser window, so it is profiler-only and not visual proof.

Corrected field proof:

- Run:
  `debug-captures/windows-lab/20260520-125838-rsx-auditor-vertex-index-field-corrected-windows/`.
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA fence +
  RSX auditor 60`, with PadApi route and `-WindowsGameScreen 1`.
- Visual:
  clean Path to Tenuto field at `screenshots/screenshot-0157s-field-late.png`.
- Host:
  clean, RPCS3 CPU `20.8%`, host GPU engine sum `31.0%` at sample `0157s`.
- Error scan:
  no fatal, validation, access-violation, `VK_ERROR`, unsupported-layout, or
  shader-compile failure. The matches are expected game/sysutil lines and the
  config `Show fatal error hints` entry.

Corrected counter summary over `8100` auditor frames:

| Bucket | Total | Per 60 Frames | Reading |
| --- | ---: | ---: | --- |
| Actual persistent vertex upload | `6,132.92 MB` | `45.43 MB` | CPU-written cache-miss vertex data consumed by GPU. |
| Volatile vertex upload | `513.49 MB` | `3.80 MB` | Per-draw volatile vertex data. |
| Index upload | `1,071.74 MB` | `7.94 MB` | GPU-consumed index-buffer generation/upload. |
| Vertex draws hit/miss | `375,609 / 543,375` | `2,782 / 4,025` | Persistent cache helps, but miss traffic remains large. |
| Emulated index draws | `23,013` | `170.47` | Primitive-emulation slice worth profiling separately. |
| Render-pass breaks | `4,022` | `29.79` | Still mostly `blit_src_to_general`, unaffected by vertex/index scout. |
| Present upload GPU swap | `1 / 3.52 MB` | `0.01 / 0.03 MB` | Small compared with geometry upload traffic. |

Decision:

- This is the best new GPU-use lead from the Windows lab: move CPU-side
  GPU-consumed geometry prep toward GPU residency, persistent staging, or
  batched conversion.
- It is not a speed win or 200% gate candidate. No fast path exists yet, only a
  measured target.
- Next experiment should be verify-first:
  1. Add a vertex/index profile table keyed by attribute layout, stride,
     primitive, persistent storage address, index type, and byte size.
  2. Identify repeated hot signatures and separate cache-miss persistent bytes
     from volatile per-draw bytes.
  3. Prototype a title-gated GPU-resident staging/cache or batched conversion
     path only for repeated GPU-consumed signatures.
  4. Compare CPU output and GPU candidate output before enabling fast mode.

Do not port this to Thor/Android until the standing Windows 200% moving-gameplay
gate is met with clean field, menu/Options, and first-battle visuals.

### Shape-Profile Follow-Up - 2026-05-20

Status: `gpu-migration-credit-scout`, not a speed win.

Tooling update:

- `rpcs3-upstream` RSX auditor now emits vertex/index upload shape profiles
  while `RPCS3_ES_RSX_RESOLVE=profile` is enabled. The key intentionally groups
  by command, primitive, layout/attribute shape, stride, register usage, and
  index type, not by every resource base, so the profile answers "which upload
  shape could be moved to GPU?" rather than "which one address was hottest?".
- `tools/summarize_eternal_sonata_rsx_auditor.ps1` exports
  `eternal-sonata-rsx-vertex-upload-profile.csv` and
  `eternal-sonata-rsx-index-upload-profile.csv` and prints `Vertex Upload
  Profile` / `Index Upload Profile` sections.

Proof run:

- Run:
  `debug-captures/windows-lab/20260520-133323-rsx-vertex-index-shape-profile-field-windows/`.
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA fence +
  Resolve Profile + RSX auditor 60`, PadApi route, `-WindowsGameScreen 1`.
- Visual:
  clean Path to Tenuto field at `screenshots/screenshot-0157s-field-late.png`.
- Host:
  clean, no competing emulator; sample `0157s` showed RPCS3 CPU `23.8%` and
  host GPU engine sum `28.2%`.
- Error scan:
  no fatal, validation, access-violation, `VK_ERROR`, unsupported-layout, or
  shader-compile failure. Matches were expected game/sysutil lines and the
  config `Show fatal error hints` entry.
- Profile overflow:
  zero vertex overflow rows and zero index overflow rows.

Corrected shape-profile totals over `8160` auditor frames:

| Bucket | Total | Per 60 Frames | Reading |
| --- | ---: | ---: | --- |
| Actual persistent vertex upload | `6,163.64 MB` | `45.32 MB` | CPU-written cache-miss vertex data consumed by GPU. |
| Volatile vertex upload | `515.75 MB` | `3.79 MB` | Per-draw volatile vertex data. |
| Index upload | `1,084.97 MB` | `7.98 MB` | GPU-consumed index-buffer generation/upload. |
| Vertex draws hit/miss | `378,524 / 546,150` | `2,783 / 4,016` | Persistent cache helps, but miss traffic remains large. |
| Emulated index draws | `23,433` | `172.30` | Tiny primitive-emulation slice; useful but not the main bandwidth. |
| Render-pass breaks | `4,042` | `29.72` | Still mostly `blit_src_to_general`; separate RSX-local lane. |

Top vertex upload shapes:

| Rank | Shape | Count | Bytes | Reading |
| ---: | --- | ---: | ---: | --- |
| 1 | `cmd/prim=2/6`, `attr=0x0109`, stride `20`, `regs=1` | `4,355,932` | `398.12 MB` volatile | Tiny repeated draw-array strips; likely CPU register/volatile expansion overhead. |
| 2 | `cmd/prim=2/6`, `attr=0x0109`, stride `24`, `regs=0` | `664,863` | `60.42 MB` volatile | Same volatile lane, different layout. |
| 3 | `cmd/prim=2/6`, `attr=0x0119`, stride `24`, `regs=1` | `512,285` | `54.44 MB` volatile | Same volatile lane with one more attribute bit. |
| 4 | `cmd/prim=3/6`, `attr=0x010d`, stride `24` | `500,324` | `2,743.06 MB` persistent | Best persistent vertex cache/staging/conversion target. |
| 6 | `cmd/prim=3/6`, `attr=0x010d`, stride `28` | `62,682` | `817.56 MB` persistent | Second strong persistent conversion target. |
| 7 | `cmd/prim=3/6`, `attr=0x0083`, stride `32` | `59,134` | `1,390.12 MB` persistent | Large miss bytes, worth verify-first profiling. |

Top index upload shapes:

| Rank | Shape | Count | Bytes | Reading |
| ---: | --- | ---: | ---: | --- |
| 1 | `cmd/prim=3/6`, u16 index type `1/2` | `912,542` | `1,084.82 MB` | Dominant normal indexed-strip upload path. |
| 2 | `cmd/prim=2/8`, u16 emulated quads/primitive path | `23,433` | rounded `0.00 MB` | Count-visible, bandwidth-tiny compared with normal index upload. |

Decision:

- The best next "use GPU more" candidate is no longer vague RSX-on-GPU talk:
  it is a verify-first vertex/index staging/conversion experiment for the
  dominant `cmd/prim=3/6` persistent vertex shapes and the single dominant u16
  index upload shape.
- The volatile draw-array shapes are huge by count but small by byte volume.
  They may reduce CPU bookkeeping only if batched or represented as
  GPU-generated scratch data without adding one dispatch per draw.
- Do not claim a speed win from this. It is a clean target list for the next
  Windows-only GPU migration experiment.

### Index GPU Byte-Swap Proof - 2026-05-20

Status: `gpu-migration-credit`, `parked-speed-path`.

Tooling update:

- Added a default-off diagnostic switch for native u16 index uploads:
  `RPCS3_ES_RSX_INDEX_UPLOAD=gpu-swap`, exposed as
  `tools/windows_rpcs3_lab.ps1 -RsxIndexUpload GpuSwap` and
  `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxIndexUpload GpuSwap`.
- The path is title-gated to `BLUS30161`, limited to native u16 indexed draws,
  pads the compute range before using `vk::cs_shuffle_16`, and records
  `index_gpu_convert(eligible/dispatch/reject/mb)` in the RSX auditor summary.

Proof runs:

- First run:
  `debug-captures/windows-lab/20260520-144334-rsx-index-gpu-swap-field-windows/`.
  It reached clean field visuals but logged `eligible=0`; the initial gate was
  too strict because primitive restart is enabled even when no restart
  emulation is needed.
- Corrected run:
  `debug-captures/windows-lab/20260520-145038-rsx-index-gpu-swap-field-r2-windows/`.
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + Present GpuSwap + Host DMA
  fence + Resolve Profile + RSX auditor 60 + Index GpuSwap`, PadApi route,
  `-WindowsGameScreen 1`.
- Visual:
  clean Path to Tenuto field at `screenshots/screenshot-0157s-field-late.png`.
- Error scan:
  no fatal, crash, exception, validation, `VK_ERROR`, assert, or inadequate
  compute buffer message; the only `fatal` text match was the normal
  `Show fatal error hints` config line.
- Host:
  clean; sample `0157s` showed RPCS3 CPU around `23.6%` and host GPU engine
  sum around `37.8%`.

Corrected run counters over `8100` auditor frames:

| Bucket | Total | Per 60 Frames | Reading |
| --- | ---: | ---: | --- |
| Index GPU convert dispatches | `893,565` | `6,619.00` | Almost every native u16 index draw got one compute dispatch. |
| Index GPU convert bytes | `1,046.37 MB` | `7.75 MB` | Real CPU endian-conversion work moved to GPU. |
| Index GPU convert rejects | `0` | `0.00` | The corrected gate matched its intended native u16 path. |
| Buffer barriers | `1,787,301` | `13,239.27` | Per-draw compute synchronization cost exploded. |
| Buffer render-pass breaks | `875,593` | `6,485.87` | The dispatch/barrier shape destroyed render-pass locality. |
| Total render-pass breaks | `879,561` | `6,515.27` | Far worse than the shape-profile control's about `30` per 60 frames. |
| Barrier-tracked buffer range | `3,808.24 MB` | `28.21 MB` | Synchronization traffic rose sharply. |

Decision:

- This proves that index endian conversion can be moved to GPU correctly for
  the dominant native u16 indexed-strip path.
- It also proves the naive architecture is wrong for speed: one compute
  dispatch and two barriers per tiny draw is a driver/render-pass locality
  disaster. Do not count this as a `windows-micro-win`, a `gate-candidate`, or
  any part of the 200% Thor promotion gate.
- Keep `GpuSwap` default-off and diagnostic. The next acceptable geometry
  offload must be cached or batched: convert repeated index/vertex signatures
  once per cache fill or per larger batch, then fan out normal draws without a
  compute dispatch immediately before each draw.

### Frame-Local Cached Index GPU Byte-Swap - 2026-05-20

Status: `gpu-migration-credit`, improved over raw `GpuSwap`, still not a speed
win.

Tooling update:

- Added `RPCS3_ES_RSX_INDEX_UPLOAD=gpu-swap-cached`, exposed as
  `tools/windows_rpcs3_lab.ps1 -RsxIndexUpload GpuSwapCached` and
  `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxIndexUpload
  GpuSwapCached`.
- `GpuSwap` keeps the raw per-draw diagnostic path. `GpuSwapCached` adds a
  frame-local cache for native u16 indexed draws, keyed by RSX source address,
  upload size, index count, primitive, and a CPU-side content hash.
- The RSX auditor now records
  `index_gpu_cache(hit/miss/hit_mb)=...`, and the summarizer reports cache hits
  beside `index_gpu_convert`.

Proof run:

- Run:
  `debug-captures/windows-lab/20260520-151947-rsx-index-gpu-swap-cached-field-windows/`.
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + Present GpuSwap + Host DMA
  fence + Resolve Profile + RSX auditor 60 + Index GpuSwapCached`, PadApi
  route, `-WindowsGameScreen 1`.
- Visual:
  clean Path to Tenuto field at `screenshots/screenshot-0157s-field-late.png`.
- Error scan:
  no fatal, crash, exception, validation, `VK_ERROR`, assert, or inadequate
  compute buffer message; the only `fatal` text match was the normal
  `Show fatal error hints` config line.
- Host:
  clean; sample `0157s` showed host CPU `22.1%` and host GPU engine sum
  `36.3%`.

Counter comparison over `8100` auditor frames:

| Bucket | Raw `GpuSwap` | Cached `GpuSwapCached` | Reading |
| --- | ---: | ---: | --- |
| Index GPU convert dispatches | `893,565` | `521,646` | Cache avoided `371,919` per-draw compute launches. |
| Index GPU convert bytes | `1,046.37 MB` | `609.92 MB` | Reused conversions represented the missing `435.91 MB`. |
| Index GPU cache hits | `0` | `368,091` | Same-frame repeat index sources are real. |
| Index GPU cache hit bytes | `0.00 MB` | `435.91 MB` | Real CPU conversion/upload work avoided after first fill. |
| Buffer barriers | `1,787,301` | `1,043,463` | About `42%` less buffer sync churn. |
| Buffer render-pass breaks | `875,593` | `505,761` | About `42%` less draw-stream locality damage. |
| Total render-pass breaks | `879,561` | `509,709` | Better than raw, still far above the non-index-swap controls. |
| Barrier-tracked range | `3,808.24 MB` | `2,443.96 MB` | About `36%` less barrier-touched buffer range. |

Decision:

- This is the first geometry experiment that both moves real CPU-side
  GPU-consumed index work to Vulkan compute and removes a large share of the
  raw path's dispatch/barrier cost.
- It is still not a `windows-micro-win` or a `gate-candidate`: the proof is
  capped near 30 FPS, field-only, and still has `521,646` compute dispatches
  and `509,709` render-pass breaks.
- Keep `GpuSwapCached` default-off, Windows-only, and diagnostic. The next
  valid speed proof should either run matched uncapped/constrained-CPU A/B
  against `Off`, `GpuSwap`, and `GpuSwapCached`, or push the architecture to a
  persistent/batched vertex/index cache that fills outside the immediate draw
  path.

### High-Cap Index Cache A/B - 2026-05-20

Status: `gpu-migration-credit`, `parked-speed-path`, not a `windows-micro-win`.

Matched high-cap field A/B, auditor off:

- Control:
  `debug-captures/windows-lab/20260520-152540-rsx-index-off-uncap240-field-windows/`.
- Mutant:
  `debug-captures/windows-lab/20260520-152853-rsx-index-gpuswapcached-uncap240-field-windows/`.
- Shared stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + Present GpuSwap + Host DMA
  fence`, no RSX auditor, `-WindowsFrameLimit 240 -WindowsVblankRate 240`,
  PadApi route, `-WindowsGameScreen 1`.
- Visual:
  both reached the same clean Path to Tenuto field late screenshot.
- Error scan:
  both had no fatal, crash, exception, validation, `VK_ERROR`, assert, or
  inadequate-buffer hit; the only `fatal` match was `Show fatal error hints`.

Late-field comparison:

| Run | Title FPS | Overlay FPS | Overlay Total CPU | Host RPCS3 CPU | Host GPU Sum | Reading |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `Off` | `119.96` | `119.71` | `38.8%` | `38.1%` | `85.9%` | Control held about 120 FPS. |
| `GpuSwapCached` | `112.89` | `109.26` | `30.5%` | `36.3%` | `92.6%` | CPU load dropped, but FPS also dropped and GPU pressure rose. |

Decision:

- The cached path really moves CPU-side index conversion/cache work toward GPU
  and lowers CPU utilization, but the extra GPU/barrier work loses about
  `6%`-`9%` FPS in this high-cap field route.
- Do not count this as a `windows-micro-win`. It is a useful CPU-to-GPU
  tradeoff probe and a correctness-clean migration credit, not a speed path.
- The next geometry architecture must reduce both CPU work and draw-stream GPU
  synchronization, likely by persistent/batched fills outside the immediate
  draw path rather than more per-draw compute.

Four-core constrained probe:

- Cached run
  `debug-captures/windows-lab/20260520-153619-cpu4-rsx-index-gpuswapcached-uncap240-field-windows/`
  reached clean field at about `33.3 FPS` with host RPCS3 CPU `25.8%` and GPU
  sum `34.1%`.
- Control runs
  `debug-captures/windows-lab/20260520-153306-cpu4-rsx-index-off-uncap240-field-windows/`
  and
  `debug-captures/windows-lab/20260520-154016-cpu4-rsx-index-off-uncap240-field-r2-windows/`
  did not reach the same field checkpoint by the final screenshots
  (`Load complete` / `Now Loading`), so the pair is route-mismatched.
- Treat the constrained-CPU result as `not-comparable`; it does not prove a
  smaller-machine win. If revisiting CPU4, first fix the route with a much
  longer post-load wait or a state-aware field detector.

### Vertex Superset Cache - 2026-05-20

Status: `gpu-migration-credit`, `single-run-cpu-load-win-candidate`, not a
`gate-candidate`.

Hypothesis:

- The existing Vulkan vertex cache is exact-range only and same-frame-lifetime
  because cached offsets live in the attribute ring. Some Eternal Sonata draws
  ask for persistent vertex ranges that are contained inside a larger range
  already uploaded earlier in the same frame.
- If we reuse the already uploaded GPU buffer slice, we can skip repeated CPU
  vertex prep/upload without adding a compute dispatch or buffer barrier.

Implementation:

- Added `RPCS3_ES_RSX_VERTEX_SUPERSET_CACHE=profile|fast`, surfaced through
  `tools/windows_rpcs3_lab.ps1 -RsxVertexSupersetCache Profile|Fast` and
  `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxVertexSupersetCache`.
- The path is scoped to `BLUS30161`, one interleaved persistent block,
  non-inlined draws, and current-frame cache lifetime. `Profile` only counts
  contained-range opportunities; `Fast` reuses the superset offset.
- The auditor and summarizer now report
  `vertex_superset_cache(hit/miss/hit_mb)`.

Proof runs:

- Profile/counter:
  `debug-captures/windows-lab/20260520-173248-rsx-vertex-superset-profile-field-windows/`.
- Fast/counter:
  `debug-captures/windows-lab/20260520-173648-rsx-vertex-superset-fast-field-windows/`.
- High-cap control:
  `debug-captures/windows-lab/20260520-174117-rsx-vertex-superset-off-uncap240-field-windows/`.
- High-cap Fast:
  `debug-captures/windows-lab/20260520-174435-rsx-vertex-superset-fast-uncap240-field-windows/`.
- Pause/menu overlay Fast:
  `debug-captures/windows-lab/20260520-175802-rsx-vertex-superset-fast-menu-windows/`.
- First-battle Fast:
  `debug-captures/windows-lab/20260520-180215-rsx-vertex-superset-fast-battle-windows/`.

Counter comparison over `8160` auditor frames:

| Run | Vertex Superset Hits | Hit MB | Persistent Vertex Upload MB | Vertex Cache Misses | Reading |
| --- | ---: | ---: | ---: | ---: | --- |
| `Profile` | `60,600` | `544.05` | `6,157.42` | `545,572` | Counted opportunity only; visible frame stayed on the old upload path. |
| `Fast` | `76,836` | `751.17` | `5,619.05` | `485,491` | Reused same-frame GPU-resident vertex slices, reducing persistent upload and miss count. |

High-cap late-field A/B, auditor off:

| Run | Title FPS | Overlay FPS | Overlay Total CPU | Host RPCS3 CPU | Host GPU Sum | Reading |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `Off` | `119.99` | `120.03` | `35.9%` | `42.7%` | `80.3%` | Control held about 120 FPS. |
| `Fast` | `119.80` | `119.39` | `37.3%` | `36.7%` | `68.8%` | Same FPS class, but lower final host RPCS3 CPU and GPU engine sum in this field sample. |

Visual/error result:

- Profile, Fast, high-cap Off, and high-cap Fast all reached the clean Path to
  Tenuto field late screenshot on `\\.\DISPLAY2`.
- Pause/menu overlay Fast reached a clean field `Pause` overlay at
  `screenshot-0112s.png` and logged `52,972` superset hits (`517.87 MB`) over
  `6,360` auditor frames. This does not count as full Options/menu proof.
- First-battle Fast reached a clean tutorial prompt at `screenshot-0157s.png`
  and active battle UI at `screenshot-0218s.png` / `screenshot-0279s.png`,
  with `212,754` superset hits (`3,569.62 MB`) over `13,200` auditor frames.
- Error scans found no crash, access violation, `VK_ERROR`, assertion,
  validation failure, or fatal runtime signal. The only matching `fatal` text
  was the static config line `Show fatal error hints`.

Decision:

- Keep the switch. This is the first geometry path in this lane that reduces
  repeated CPU vertex prep/upload without adding per-draw GPU compute.
- Count it as real RSX `gpu-migration-credit` and a provisional Windows
  CPU-load micro-win candidate, but do not count it as a speed win or 200%
  Thor gate. FPS stayed at the same about-120 plateau in the matched uncapped
  field A/B, and only a single host CPU-load sample improved.
- Before any Thor discussion, repeat matched Windows A/B and add full
  menu/Options proof. Next architecture target: persistent or batched
  vertex-range reuse beyond same-frame contained ranges, with content
  validation.

#### Scan-Depth Follow-Up - 2026-05-20

Status: `diagnostic-knob`, not a `windows-micro-win`.

Hypothesis:

- The first vertex superset cache only scans back through `64` prior
  same-frame GPU-resident ranges. A wider search might find more contained
  persistent vertex ranges and move more CPU vertex-prep/upload work to GPU
  residency.

Implementation:

- Added `RPCS3_ES_RSX_VERTEX_SUPERSET_SCAN=N` in local `rpcs3-upstream`.
- Exposed it as:
  - `tools/windows_rpcs3_lab.ps1 -RsxVertexSupersetScanLimit N`;
  - `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxVertexSupersetScanLimit N`.
- Default remains `64`; values above `1024` clamp to `1024`.

Runs:

- Profile scan 256:
  `debug-captures/windows-lab/20260520-203542-rsx-vertex-superset-profile-scan256-field-windows`.
- Fast scan 256 high-cap smoke:
  `debug-captures/windows-lab/20260520-203916-rsx-vertex-superset-fast-scan256-uncap240-field-windows`.

Findings:

- Profile scan 256 reached clean field and saw `55,230` hits / `495.84 MB`
  over `6,960` auditor frames, about `476` hits and `4.27 MB` per 60 frames.
- The prior 64-scan profile saw about `446` hits and `4.00 MB` per 60 frames,
  so the wider search exposes only a modest extra opportunity.
- Fast scan 256 reached clean field, but late field was about `118.94` title /
  `117.70` overlay FPS. That is a little lower than the prior scan-64 Fast
  high-cap run (`119.80` title / `119.39` overlay), and the host-contention
  label was `moderate` because the run itself loaded the desktop heavily.

Decision:

- Keep `RPCS3_ES_RSX_VERTEX_SUPERSET_SCAN` as a Windows lab diagnostic.
- Do not change the default `64` scan limit. Wider scan is not a speed win, and
  the extra search work probably eats the small additional reuse.

### Discarded Trust-Cache Probe - 2026-05-20

Status: `failed`, not retained.

Temporary implementation:

- Added a local-only `GpuSwapCachedTrust` diagnostic that skipped the per-hit
  content hash and trusted same-frame source address, upload size, index count,
  and primitive after the first GPU conversion.
- Built successfully, then removed the switch and rebuilt after the result
  proved worse and riskier than the hashed cache.

Proof runs:

- Capped/audited:
  `debug-captures/windows-lab/20260520-155514-rsx-index-gpu-swap-cached-trust-field-windows/`.
- High-cap:
  `debug-captures/windows-lab/20260520-155932-rsx-index-gpuswapcachedtrust-uncap240-field-windows/`.

Findings:

- Capped/audited visual proof was clean, with no fatal/crash/Vulkan/validation
  errors.
- Counter shape was basically the same as hashed `GpuSwapCached`:
  `369,483` frame-local hits, `521,381` compute dispatches, `509,447`
  render-pass breaks.
- High-cap field FPS was worse: about `95.9 FPS` overlay / `95.28` title bar,
  versus about `109.3` for hashed `GpuSwapCached` and about `119.7` for `Off`.

Decision:

- Do not keep or use this trust shortcut. It reduces correctness guarantees,
  does not improve dispatch/barrier pressure, and did not improve speed.
- The code and wrappers were restored to the retained modes: `Off`, `GpuSwap`,
  and `GpuSwapCached`.

### Volatile Vertex Cache - 2026-05-20

Status: `gpu-migration-credit`, `cpu-load-tradeoff`, `parked-speed-path`, not
a `windows-micro-win`.

Hypothesis:

- The existing vertex superset cache only helps persistent/interleaved vertex
  ranges. Eternal Sonata also emits many tiny volatile/transient vertex blobs.
- If those blobs repeat inside the same frame, we can reuse the already
  uploaded GPU buffer slice and avoid another CPU map/write without adding a
  compute dispatch.

Implementation:

- Added `RPCS3_ES_RSX_VERTEX_VOLATILE_CACHE=profile|fast`, surfaced through
  `tools/windows_rpcs3_lab.ps1 -RsxVertexVolatileCache Profile|Fast` and
  `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxVertexVolatileCache`.
- The path is scoped to `BLUS30161`, same-frame only, and hashes the actual
  transient source bytes before reuse.
- The auditor and summarizer now report
  `vertex_volatile_cache(hit/miss/hit_mb)`.

Proof runs:

- Profile/counter:
  `debug-captures/windows-lab/20260520-182520-rsx-vertex-volatile-profile-field-windows/`.
- Fast/counter:
  `debug-captures/windows-lab/20260520-182927-rsx-vertex-volatile-fast-field-windows/`.
- High-cap control:
  `debug-captures/windows-lab/20260520-183334-rsx-vertex-volatile-off-uncap240-field-windows/`.
- High-cap Fast:
  `debug-captures/windows-lab/20260520-183657-rsx-vertex-volatile-fast-uncap240-field-windows/`.

Counter comparison:

| Run | Frames | Volatile Cache Hits | Misses | Hit MB | Volatile Upload MB | Reading |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `Profile` | `7,380` | `240,239` | `5,747,418` | `21.08` | `551.96` | Counts repeated transient blobs while rendering through the old upload path. |
| `Fast` | `7,320` | `239,839` | `5,720,827` | `21.07` | `528.09` | Reuses same-frame volatile slices, reducing upload by about the hit-byte volume. |

High-cap late-field A/B, auditor off:

| Run | Title FPS | Overlay FPS | Overlay Total CPU | Host RPCS3 CPU | Host GPU Sum | Reading |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `Off` | `118.63` | `119.55` | `33.1%` | `69.4%` | `68.3%` | Control held near the 120 FPS field plateau. |
| `Fast` | `109.69` | `110.19` | `35.0%` | `37.5%` | `72.5%` | Later host CPU sample improved, but FPS dropped about `8%`. |

Visual/error result:

- Profile, Fast, high-cap Off, and high-cap Fast all reached clean Path to
  Tenuto field screenshots on `\\.\DISPLAY2`.
- Error scans found no crash, access violation, `VK_ERROR`, assertion,
  validation failure, or fatal runtime signal. The only matching `fatal` text
  was the static config line `Show fatal error hints`.

Decision:

- This is real CPU-to-GPU residency movement for many tiny volatile vertex
  writes, but it is small in bytes and not a throughput win.
- Keep the switch default-off and Windows-only as diagnostic
  `gpu-migration-credit` / CPU-load tradeoff.
- Do not count it toward the 200% Thor gate. The more promising geometry lane
  remains persistent/batched vertex-range reuse with larger byte volume, and
  the bigger Thor gap still points at SPU/PPU/JIT/sync work.

### CPU4 GPU Bundle Route Probe - 2026-05-20

Status: `not-comparable`, `route-sensitive`, not a `windows-micro-win`.

Question:

- On a deliberately constrained Windows host (`-WindowsCpuAffinityMask 0x0F`),
  does the current RSX/GPU migration bundle show a smaller-machine win once the
  beefy desktop's 120 FPS ceiling is removed?

Shared setup:

- Windows-only lab, PadApi input, `-WindowsGameScreen 1`,
  `-WindowsFrameLimit 240`, `-WindowsVblankRate 240`.
- Bundle under test:
  `DepthReadOnly + FastSampled + KeepReadOnly + Present GpuSwap + Host DMA fence + VertexSuperset Fast`.

Runs:

- Stock first pass:
  `debug-captures/windows-lab/20260520-194922-cpu4-stock-longfield-uncap240-windows`.
  Reached field late screenshots; field/title FPS was roughly `27`-`28`, with
  host RPCS3 CPU around `28%` and GPU sum around `25%`.
- Bundle first pass:
  `debug-captures/windows-lab/20260520-195352-cpu4-gpubundle-longfield-uncap240-windows`.
  Route mismatch; the macro landed on a damaged/missing save flow and stayed on
  load UI, so it cannot be compared.
- Bundle corrected top-slot pass:
  `debug-captures/windows-lab/20260520-195932-cpu4-gpubundle-longfield-topslot-uncap240-windows`.
  Reached field; late title FPS was about `27.05` then `29.81`, with host
  RPCS3 CPU around `27%`-`28%` and GPU sum around `24%`-`25%`.
- Stock corrected top-slot pass:
  `debug-captures/windows-lab/20260520-200523-cpu4-stock-longfield-topslot-uncap240-windows`.
  Did not reach the same moving-field checkpoint by the late screenshots
  (`Now Loading` / load UI), so it cannot be compared.

Decision:

- The CPU4 lab is useful because it makes the Windows box behave more like a
  CPU-limited handheld, but the current route is still too timing-sensitive for
  a speed claim.
- The bundle reaching field under CPU4 is encouraging for stability, not proof
  of improvement. Repeat only after the Windows route has stronger state-aware
  branch checks or longer labeled checkpoints.
- Later route debug:
  `debug-captures/windows-lab/20260520-202405-cpu4-stock-vertexsuperset-proof-stock-r2-windows`
  selected Save File 01 correctly but stayed on `Now Loading` through the late
  checkpoint under `0x0F` affinity, while
  `debug-captures/windows-lab/20260520-204428-cpu4-stock-save02-uncap240-field-windows`
  failed to select a valid second slot and remained on the confirm/save UI.
  Keep CPU4 parked until the route can detect the actual save row and load
  completion state.

### Persistent Vertex Cross-Frame Scout - 2026-05-20

Status: `architecture-scout`, `gpu-cache-candidate`, not a
`windows-micro-win`.

Question:

- The frame-local vertex superset cache proves same-frame GPU-resident reuse,
  but the existing weak vertex cache is purged every frame.
- Are the remaining cache-miss persistent vertex ranges actually stable across
  frames, or are they being rewritten by the game often enough that a long-lived
  GPU cache would be unsafe/noisy?

Implementation:

- Added `RPCS3_ES_RSX_VERTEX_PERSISTENT_CACHE=profile`, surfaced through
  `tools/windows_rpcs3_lab.ps1 -RsxVertexPersistentCache Profile` and
  `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxVertexPersistentCache`.
- The scout is title-gated to `BLUS30161`, exact-range only, and profile-only.
  It hashes the persistent/interleaved source bytes for current cache misses
  and reports `vertex_persistent_cache(hit/change/new/hit_mb)`.
- No fast path was added. The existing `m_vertex_cache->purge()` cannot simply
  be skipped, because its offsets point into the transient attribute ring and
  can be freed/overwritten after frame cleanup.

Run:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label rsx-vertex-persistent-profile `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve FastSampled `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxPresentUpload GpuSwap `
  -WindowsRsxVertexSupersetCache Fast `
  -WindowsRsxVertexPersistentCache Profile `
  -WindowsRsxAuditor 60 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 150
```

Capture:

- `debug-captures/windows-lab/20260520-220710-rsx-vertex-persistent-profile-windows/`.
- Late field screenshot `screenshots/screenshot-0140s.png` was visually clean.
- Host samples were `moderate` because GPU engine sum was high; this run is a
  profile/counter scout, not a clean FPS A/B.

Counter result:

| Counter | Total | Per 60 frames | Reading |
| --- | ---: | ---: | --- |
| Auditor frames | `23,340` | - | Long enough to include steady field. |
| Persistent vertex upload | `21,643.08 MB` | `55.64 MB` | Existing CPU-written persistent vertex miss traffic after same-frame superset fast. |
| Same-frame superset hits | `286,624 / 2,797.69 MB` | `736.82 / 7.19 MB` | Already proven frame-local reuse. |
| Cross-frame exact stable hits | `1,807,018 / 21,638.50 MB` | `4,645.29 / 55.63 MB` | Remaining exact persistent misses were almost entirely byte-identical to a prior frame. |
| Changed exact ranges | `0` | `0.00` | No observed rewritten exact ranges in this field route. |
| New exact ranges | `482` | `1.24` | Small unique working set, plausibly cacheable in a dedicated persistent heap. |

Decision:

- This is the strongest RSX geometry cache signal so far. It points at a
  dedicated long-lived persistent vertex cache, not another scan-depth tweak.
- Do not count this as a speed win: profile hashing lowered the field to about
  `95 FPS`, and no rendering path used cached cross-frame data yet.
- Next Windows-only step: build a `Verify` mode that stores generated
  persistent vertex bytes in a dedicated GPU-visible/cache heap, compares
  later exact-range hits against the normal CPU-generated upload, records
  mismatches/evictions, and only then try `Fast`.
- The fast implementation must have a rollback switch, title gate, bounded
  memory, eviction on heap/grow/invalidation, and field/menu/battle proof before
  any 200% gate discussion.

### Persistent Vertex Verify And Fast Cache - 2026-05-21

Status: `gpu-migration-credit`, `cpu-load-micro-win-candidate`,
`windows-only`, not a `200-percent-gate`.

Question:

- Can the 2026-05-20 cross-frame scout become a real rendering path that keeps
  generated persistent vertex bytes in a long-lived GPU-visible cache heap
  instead of rewriting them into the per-frame attribute ring?

Implementation:

- Added `RPCS3_ES_RSX_VERTEX_PERSISTENT_CACHE=verify|fast`, surfaced through
  `tools/windows_rpcs3_lab.ps1 -RsxVertexPersistentCache Verify|Fast` and
  `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxVertexPersistentCache`.
- `Verify` stores generated persistent vertex bytes in a dedicated 64 MB cache
  heap and compares later exact hits while visible rendering still uses the
  normal upload path.
- `Fast` uses the cache heap directly as the persistent vertex texel-buffer
  source on guarded hits. Misses and rejected hits fall back to the normal CPU
  upload path and repair the cache. The hit guard is title-scoped to
  `BLUS30161`, exact layout/range keyed, and checks a cheap source fingerprint.
- The auditor/summarizer now report
  `vertex_persistent_verify(hit/store/mismatch/hit_mb/store_mb)` and
  `vertex_persistent_fast(hit/store/reject/hit_mb/store_mb)`.

Important correction:

- First fast attempt
  `debug-captures/windows-lab/20260521-003228-rsx-vertex-persistent-fast-windows/`
  was a parser-control run, not a fast-path run. The parser checked
  `looks_disabled()` before checking `fast`, so `fast` was treated like
  `false`. Do not use that run as persistent-cache fast evidence.

Verify proof:

- Run:
  `debug-captures/windows-lab/20260521-001734-rsx-vertex-persistent-verify-windows/`.
- Scene/stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + VertexSuperset Fast +
  Persistent Verify`.
- Late field screenshot `screenshots/screenshot-0140s.png` was visually clean.
- Error scan found no crash, access violation, `VK_ERROR`, validation failure,
  assertion, or fatal runtime signal.

Verify counters:

| Counter | Total | Per 60 frames | Reading |
| --- | ---: | ---: | --- |
| Auditor frames | `24,420` | - | Long field run. |
| Persistent verify hits | `2,103,928 / 25,088.37 MB` | `5,169.36 / 61.64 MB` | Generated bytes matched the cache copy while rendering through the old path. |
| Persistent verify stores | `482 / 4.53 MB` | `1.18 / 0.01 MB` | Small working set. |
| Persistent verify mismatches | `0` | `0.00` | Required proof before trying Fast. |

Fast proof runs:

- Field:
  `debug-captures/windows-lab/20260521-003928-rsx-vertex-persistent-fast-parserfix-windows/`.
- Pause/menu:
  `debug-captures/windows-lab/20260521-004322-rsx-vertex-persistent-fast-menu-windows/`.
- First battle:
  `debug-captures/windows-lab/20260521-004634-rsx-vertex-persistent-fast-battle-windows/`.

Fast counters:

| Scene | Frames | Fast Hits / MB | Stores / MB | Rejects | Persistent Upload | Visual |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Field | `24,780` | `4,207,085 / 46,485.49 MB` | `598 / 6.37 MB` | `0` | `6.37 MB` total, `0.02 MB/60` | clean late field, about `120 FPS` cap |
| Pause/menu | `22,200` | `3,030,588 / 33,617.00 MB` | `598 / 6.37 MB` | `0` | `6.37 MB` total | clean Pause overlay |
| First battle | `47,160` | `9,181,419 / 118,703.96 MB` | `814 / 8.69 MB` | `0` | `8.69 MB` total | clean active battle UI, about `120 FPS` cap |

What moved:

- In the field fast run, persistent upload fell from the verify/profile shape
  of roughly `61 MB/60 frames` to `0.02 MB/60 frames`.
- The same work moved into cache hits:
  `112.56 MB/60` from the persistent cache heap in field and
  `151.02 MB/60` in first battle.
- This is real RSX GPU-residency work: the vertex shader reads persistent
  bytes from the long-lived cache heap instead of forcing CPU generation and
  attribute-ring writes for almost every repeated range.

Decision:

- Promote this lane from `architecture-scout` to Windows RSX
  `gpu-migration-credit`.
- Do not call it a 200% speed proof. The Windows PC is still near the
  120 FPS cap, and no matched auditor-off/off-vs-fast A/B has proven a large
  moving-gameplay FPS gain.
- Keep the switch default-off, title-gated, and Windows-only.
- Next proof should be matched high-cap and CPU-constrained A/B against the same
  field/menu/battle checkpoints, then eviction/invalidation hardening. Do not
  port to Android/Thor until the standing 200% Windows gate is actually met.

### Persistent Vertex Matched A/B - 2026-05-21

Status: `gpu-migration-credit`, not a `windows-micro-win`, not a
`200-percent-gate`.

Purpose:

- Separate the persistent vertex cache's real GPU-residency/copy-removal proof
  from any FPS or host-load claim.

High-cap field A/B, auditor off:

| Run | Capture | Title FPS | Overlay FPS | Host RPCS3 CPU | Host GPU Sum | Grade | Reading |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| `Off` | `20260521-092709-rsx-persistent-ab-off-field-windows` | `119.77` | `119.83` | `43.2%` | `90.4%` | `high` | Clean field, capped. |
| `Fast` | `20260521-092959-rsx-persistent-ab-fast-field-windows` | `119.93` | `119.62` | `41.5%` | `74.3%` | `moderate` | Clean field, capped. |

CPU-constrained field A/B, auditor off, `-WindowsCpuAffinityMask 0x0F`:

| Run | Capture | Late Title FPS | Late Overlay FPS | Host RPCS3 CPU | Host GPU Sum | Grade | Reading |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| `Off` | `20260521-093410-cpu4-rsx-persistent-off-field-windows` | `35.42` | `31.76` | `25.5%` | `31.3%` | `clean` | Correct field, low-30s FPS. |
| `Fast` | `20260521-093715-cpu4-rsx-persistent-fast-field-windows` | `29.59` | `27.36` | `26.0%` | `18.2%` | `clean` | Correct field, lower late FPS. |

Visual/error result:

- All four A/B runs reached the same visible Path to Tenuto field on
  `\\.\DISPLAY2`.
- Error scans found no crash, access violation, `VK_ERROR`, validation failure,
  assertion, or fatal runtime signal.

Decision:

- The long-lived persistent vertex cache remains a strong correctness-stable
  RSX `gpu-migration-credit`: prior auditor proof shows it serves tens of GB of
  persistent vertex bytes from the cache heap with zero rejects in field/menu
  and first battle.
- The matched A/B does not prove a speed win. The high-cap pair is pinned to
  the Windows 120 FPS ceiling, and the CPU4 pair is mixed to worse for Fast.
- Remove the `cpu-load-micro-win-candidate` label from this lane for now. Keep
  it as default-off Windows-only evidence that stable geometry bytes can live
  GPU-resident.
- Next useful geometry experiment should target a different, larger remaining
  CPU-side job, especially persistent/batched index reuse or a verified
  SPU/RSX-prep candidate. More tuning on this exact vertex cache is unlikely to
  move the 200% gate by itself.

### Persistent Index Cross-Frame Scout - 2026-05-21

Status: `architecture-scout`, `index-cache-candidate`, not a speed win.

Question:

- The earlier `GpuSwap` / `GpuSwapCached` index lane proved native u16 endian
  conversion can move to Vulkan compute, but the per-draw dispatch/barrier cost
  made it slower.
- Are the same native u16 index sources stable across frames enough to support
  a persistent GPU index cache that avoids repeated CPU index generation/upload
  without one compute dispatch per draw?

Implementation:

- Added `RPCS3_ES_RSX_INDEX_PERSISTENT_CACHE=profile`, surfaced through:
  - `tools/windows_rpcs3_lab.ps1 -RsxIndexPersistentCache Profile`;
  - `tools/eternal_sonata_speed_sprint.ps1 -WindowsRsxIndexPersistentCache Profile`.
- The scout is title-gated to `BLUS30161`, profile-only, and limited to native
  u16 indexed draws that are not primitive-emulated, restart-emulated, or
  immediate draws.
- The auditor/summarizer now report
  `index_persistent_cache(hit/change/new/hit_mb)`.

Build:

- `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`
  passed after the scout was added. Only the known `LNK4098` warning appeared.
- PowerShell parser checks passed for:
  - `tools/windows_rpcs3_lab.ps1`;
  - `tools/eternal_sonata_speed_sprint.ps1`;
  - `tools/summarize_eternal_sonata_rsx_auditor.ps1`.

Run:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label rsx-index-persistent-profile-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve FastSampled `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxPresentUpload GpuSwap `
  -WindowsRsxVertexSupersetCache Fast `
  -WindowsRsxVertexPersistentCache Fast `
  -WindowsRsxIndexPersistentCache Profile `
  -WindowsRsxAuditor 60 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 150
```

Capture:

- `debug-captures/windows-lab/20260521-095638-rsx-index-persistent-profile-field-windows/`.
- Late field screenshot `screenshots/screenshot-0140s.png` was visually clean
  at about the 120 FPS cap.
- Host samples were `moderate` during gameplay (`rpcs3` CPU `40.1%`, GPU sum
  `68.1%` at `sample-0150s`).
- Error scan found no crash, access violation, `VK_ERROR`, validation failure,
  assertion, or fatal runtime signal.

Counter result:

| Counter | Total | Per 60 frames | Reading |
| --- | ---: | ---: | --- |
| Auditor frames | `25,020` | - | Long field run. |
| Index upload | `4,195,958 / 5,019.61 MB` | `10,061.45 / 12.04 MB` | Existing GPU-consumed index-buffer upload/generation lane. |
| Stable cross-frame index hits | `2,399,965 / 2,900.08 MB` | `5,755.31 / 6.95 MB` | Exact native u16 index sources were byte-identical to a prior frame. |
| Changed exact index ranges | `0` | `0.00` | No observed source rewrite for profiled exact keys in this field route. |
| New exact index ranges | `517` | `1.24` | Small working set, plausible cache size. |
| Persistent vertex fast hits in same run | `4,244,902 / 47,139.13 MB` | `10,179.62 / 113.04 MB` | Existing vertex cache still active and clean. |

Decision:

- This is a real index-cache signal, but smaller than the persistent vertex
  lane: about `6.95 MB/60` stable index bytes versus over `100 MB/60` served
  from persistent vertex fast in the same stack.
- Do not count it as a speed win or current GPU migration credit. Profile mode
  only proves a candidate.
- Next Windows-only step should be `Verify`: store Vulkan-ready generated index
  bytes in a bounded persistent index heap, render through the normal path, and
  compare later exact hits. Only after zero mismatches in field/menu/battle
  should a Fast mode bind a persistent index buffer directly.
- Avoid returning to raw per-draw compute byte-swap. It already moved work to
  GPU, but it added too much dispatch/barrier debt to be a good speed lane.

## Persistent Index Verify And Fast - 2026-05-21

Status: `gpu-migration-credit`, not a speed win, not a 200% gate candidate.

Implementation:

- Added `RPCS3_ES_RSX_INDEX_PERSISTENT_CACHE=verify|fast`.
- Android repo wrappers expose this as `-RsxIndexPersistentCache Verify|Fast`
  and `-WindowsRsxIndexPersistentCache Verify|Fast`.
- `Verify` stores generated Vulkan-ready native u16 index bytes into a bounded
  persistent `VK_BUFFER_USAGE_INDEX_BUFFER_BIT` heap, renders through the normal
  index upload path, and compares later exact hits.
- `Fast` binds that persistent index heap directly on title-gated exact hits and
  falls back to normal CPU index generation on misses/rejects.
- `Fast` remained opt-in and title-scoped to Eternal Sonata `BLUS30161`.

Verify command shape:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label rsx-index-persistent-verify-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve FastSampled `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxPresentUpload GpuSwap `
  -WindowsRsxVertexSupersetCache Fast `
  -WindowsRsxVertexPersistentCache Fast `
  -WindowsRsxIndexPersistentCache Verify `
  -WindowsRsxAuditor 60 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 150
```

Verify capture:

- `debug-captures/windows-lab/20260521-112515-rsx-index-persistent-verify-field-windows/`.
- Late field screenshot `screenshots/screenshot-0140s.png` was visually clean
  at about the 120 FPS cap.
- Error scan found no crash, access violation, `VK_ERROR`, validation failure,
  assertion, or fatal runtime signal.
- Host contention summary: `moderate`.

Verify counters:

| Counter | Total | Per 60 frames | Reading |
| --- | ---: | ---: | --- |
| Auditor frames | `24,540` | - | Long field run. |
| Index upload | `4,086,458 / 4,859.15 MB` | `9,991.34 / 11.88 MB` | Existing GPU-consumed native u16 index generation lane. |
| Persistent index verify | `2,340,334 / 2,830.33 MB` | `5,722.09 / 6.92 MB` | Generated bytes matched the dedicated persistent index heap while rendering stayed normal. |
| Persistent index verify stores | `517 / 0.48 MB` | `1.26 / 0.00 MB` | Small working set, matching the profile scout. |
| Persistent index mismatches | `0` | `0.00` | Clean enough to try a guarded Fast path. |

Fast command shape:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -Label rsx-index-persistent-fast2-field `
  -WindowsInputBackend PadApi `
  -WindowsGameScreen 1 `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve FastSampled `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxPresentUpload GpuSwap `
  -WindowsRsxVertexSupersetCache Fast `
  -WindowsRsxVertexPersistentCache Fast `
  -WindowsRsxIndexPersistentCache Fast `
  -WindowsRsxAuditor 60 `
  -WindowsFrameLimit 240 `
  -WindowsVblankRate 240 `
  -MaxSeconds 150
```

Fast captures:

- First attempt `20260521-114010-rsx-index-persistent-fast-field-windows` was
  visually clean, but logged `0` fast hits/stores/rejects. Cause: the new index
  parser checked `looks_disabled()` before the `fast` token, so `fast` was read
  as false/off. Fixed the parser to match the persistent vertex path.
- Fixed run:
  `debug-captures/windows-lab/20260521-114801-rsx-index-persistent-fast2-field-windows/`.
- Late field screenshot `screenshots/screenshot-0140s.png` was visually clean
  at about the 120 FPS cap.
- Error scan found no crash, access violation, `VK_ERROR`, validation failure,
  assertion, or fatal runtime signal.
- Host contention summary: `moderate`.

Fast counters:

| Counter | Total | Per 60 frames | Reading |
| --- | ---: | ---: | --- |
| Auditor frames | `24,660` | - | Long field run. |
| Persistent index fast hits | `4,060,099 / 4,972.35 MB` | `9,878.59 / 12.10 MB` | Indexed draws bound the persistent Vulkan index heap instead of regenerating/reuploading index bytes. |
| Persistent index fast stores | `517 / 0.48 MB` | `1.26 / 0.00 MB` | Working set stayed bounded. |
| Persistent index fast rejects | `0` | `0.00` | No fallback rejects in the clean field route. |
| Persistent vertex fast in same run | `4,209,232 / 46,716.81 MB` | `10,241.44 / 113.67 MB` | Existing vertex residency stayed active. |

Scene coverage follow-up:

- Pause-overlay attempt
  `debug-captures/windows-lab/20260521-115526-rsx-index-persistent-fast-menu-windows/`
  was visually clean and logged `5,701,412` persistent index fast hits
  (`6,906.03 MB`), but it only reached a loaded-field `Pause` overlay. Do not
  count this as full menu/Options proof.
- Full Options route
  `debug-captures/windows-lab/20260521-120847-rsx-index-persistent-fast-options-delayedcross-windows/`
  used the corrected title Options macro on `\\.\DISPLAY2`, reached a clean full
  Options page at `screenshots/screenshot-0095s.png` / `0101s.png`, had clean
  host grade and empty fatal/crash/Vulkan/validation scan, and logged
  `1,144,400` persistent index fast hits (`1,951.26 MB`), `705` stores, and `0`
  rejects over `20,880` auditor frames.
- First-battle route
  `debug-captures/windows-lab/20260521-121255-rsx-index-persistent-fast-battle-windows/`
  reached a clean tutorial prompt at `screenshot-0158s.png` and clean active
  battle UI at `screenshot-0220s.png` / `0320s.png`, had clean host grade and
  empty fatal/crash/Vulkan/validation scan, and logged `8,839,742` persistent
  index fast hits (`10,642.76 MB`), `703` stores, and `0` rejects over `46,620`
  auditor frames.
- Wrapper fix: `tools/eternal_sonata_speed_sprint.ps1 -Scene menu` now routes
  to the full title Options page by default. It should no longer count the
  loaded-field `Pause` overlay as the menu gate.

Decision:

- This is real RSX GPU-residency movement: native u16 index buffers are now
  served from a long-lived GPU index heap on repeated exact hits.
- It now has clean field, full Options, and first-battle visual coverage for
  `Fast`, with zero logged rejects or error-scan hits in the accepted scene
  runs.
- It is not a speed proof. The runs remain around the Windows 120 FPS cap and
  were auditor-on correctness/counter captures.
- Keep default off. Next proof should be matched auditor-off A/B, ideally with a
  CPU-constrained Windows host shape after the normal high-cap pair. Do not port
  to Thor until the project's Windows 200% moving-gameplay gate is met.

## Persistent Index Matched A/B - 2026-05-21

Status: `cpu-constrained-windows-speed-win-candidate`,
`gpu-migration-credit`, not a 200% gate candidate.

High-cap field A/B, auditor off:

- Control:
  `debug-captures/windows-lab/20260521-122523-rsx-index-ab-off-field-windows/`.
- Fast:
  `debug-captures/windows-lab/20260521-122832-rsx-index-ab-fast-field-windows/`.
- Both used `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap +
  VertexSuperset Fast + VertexPersistent Fast`, screen 1, PadApi, frame limit
  `240`, vblank `240`, and no RSX auditor.
- Both screenshots were clean at `screenshot-0140s.png`; fatal/crash/Vulkan/
  validation scans were empty.
- Both host grades were `moderate` and both stayed at the usual Windows field
  plateau: control title/overlay about `120.04 / 120.37 FPS`, Fast about
  `119.95 / 120.07 FPS`.
- Late host sample moved from RPCS3 CPU `40.1%`, GPU sum `84.7%` to RPCS3 CPU
  `42.6%`, GPU sum `80.9%`. This is not a high-cap speed win.

CPU4 field A/B, auditor off:

- Control:
  `debug-captures/windows-lab/20260521-123319-cpu4-rsx-index-ab-off-field-windows/`.
- Fast:
  `debug-captures/windows-lab/20260521-123630-cpu4-rsx-index-ab-fast-field-windows/`.
- Both used `-WindowsCpuAffinityMask 0x0F`, screen 1, PadApi, frame limit `240`,
  vblank `240`, and no RSX auditor.
- Both late screenshots were clean and error scans were empty.
- Host grade stayed `clean` for both.
- Final screenshot comparison:

| Run | Title FPS | Overlay FPS | Overlay 1% | Late RPCS3 CPU | Late GPU Sum | Reading |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Off | `27.55` | `24.24` | `23.0` | `26.4%` | `20.3%` | CPU-constrained control. |
| Fast | `34.11` | `29.93` | `26.0` | `26.0%` | `27.2%` | About `+23.8%` title FPS and `+23.5%` overlay FPS, with work shifted toward GPU. |

Decision:

- This is the first useful speed-shaped signal for the persistent index heap:
  under a constrained Windows CPU shape, binding the long-lived index heap beats
  regenerating/reuploading the same native u16 index bytes.
- Treat it as a `cpu-constrained-windows-speed-win-candidate`, not yet a durable
  general Windows speed win. It needs repeat A/B and a longer moving route to
  avoid one-sample luck.
- It still is nowhere near the required 200% Windows promotion gate and still
  must stay Windows-only.

## Persistent Geometry Route Fix And Moving Loop - 2026-05-21

Status: `gpu-migration-credit`, `parked-speed-path`, not a durable speed win,
not a 200% gate candidate.

Route repair:

- Restored/rechecked the Windows save route after repeated Load-screen captures.
- The save itself loaded; the old macro pressed the final `cross` too early,
  before `Load complete.` was ready to dismiss.
- `tools/eternal_sonata_speed_sprint.ps1` now waits `32000ms` after confirming
  `Yes`, then presses `cross:120` before the field settle wait.
- Default route proof:
  `debug-captures/windows-lab/20260521-154823-cpu4-route-fixed-default-field-off-windows-windows/`
  reached clean Path to Tenuto field on screen 1 with clean host grade and empty
  fatal/crash/Vulkan scan.

Route-fixed CPU4 idle A/B, auditor off:

- Control:
  `debug-captures/windows-lab/20260521-155147-cpu4-rsx-index-routefix-ab-off-field-windows-windows/`.
- Fast:
  `debug-captures/windows-lab/20260521-155456-cpu4-rsx-index-routefix-ab-fast-field-windows-windows/`.
- Both reached clean field on screen 1 with host grade `clean` and empty error
  scans.
- Final field frame favored Fast, about title/overlay `23.43 / 22.00 FPS` Off
  versus `38.42 / 33.96 FPS` Fast.
- Earlier tagged field frames were mixed, so this remains noisy and cannot be
  promoted by itself.

Moving-loop CPU4 A/B, auditor off:

- Control:
  `debug-captures/windows-lab/20260521-160014-cpu4-rsx-index-movingloop-off-field-windows-windows/`.
- Fast:
  `debug-captures/windows-lab/20260521-160340-cpu4-rsx-index-movingloop-fast-field-windows-windows/`.
- Both used the same small Path to Tenuto movement loop, screen 1, PadApi,
  `-WindowsCpuAffinityMask 0x0F`, `DepthReadOnly + FastSampled + KeepReadOnly +
  GpuSwap + VertexSuperset Fast + VertexPersistent Fast`.
- Both were visually clean and log-clean, but Fast was not better across tagged
  moving frames. This blocks a speed-win claim.

Warm-up filter follow-up:

- Added local Windows `rpcs3-upstream` warm-up gates for persistent index Fast
  and persistent vertex Fast: first-seen candidates are not inserted into the
  dedicated persistent cache heap until the same source/fingerprint is observed
  in a later frame.
- Rebuilt successfully:
  `cmake --build rpcs3-upstream\build-msvc --config Release --target rpcs3 --parallel 6`.
- Index-only warm-up Fast:
  `debug-captures/windows-lab/20260521-161910-cpu4-rsx-index-warmup-movingloop-fast-field-windows-windows/`.
- Index+vertex warm-up Fast:
  `debug-captures/windows-lab/20260521-163150-cpu4-rsx-ivwarmup-movingloop-fast-field-windows-windows/`.
- Both warm-up runs stayed visually/log clean, but neither beat the moving-loop
  Off control consistently.

Decision:

- The persistent geometry caches still count as real RSX `gpu-migration-credit`
  because they keep repeated vertex/index data GPU-resident and have prior
  verify/fast counter proof with field/menu/battle visuals.
- The moving-loop proof demotes the current speed claim: it is not a durable
  Windows speed win and not close to the 200% gate.
- Keep the warm-up filters because they are safer for dynamic scenes, but do not
  spend more time claiming this lane as the main speed answer.
- Next Windows-only GPU work should either find a larger batched RSX-local
  renderpass/tile-local win or return to the SPU/PPU job body with a verified
  coarse superpath. No Android/Thor port.

## Blit-Source Cache Render-Pass Locality Scout - 2026-05-21

Status: `gpu-migration-credit` for `FastCachedSampled`, `failed` /
`parked-speed-path` for transfer/defer variants, not a 200% gate candidate.

Why this lane:

- The earlier resolve coalescing scout found repeated 1280x720 2x MSAA
  blit-source resolves from the same source content tag.
- The hypothesis was that resolving the source once and fanning out destination
  writes could keep more RSX work GPU-resident.
- Mobile/tile-based Vulkan guidance points the same way: prefer preserving
  attachment/local data inside a render pass or subpass and avoid forcing tile
  memory out to external memory through broad barriers and separate passes.
  References checked while deciding the next target:
  [Khronos tile-based rendering best practices](https://github.khronos.org/Vulkan-Site/guide/latest/tile_based_rendering_best_practices.html)
  and the [Vulkan subpasses performance sample](https://docs.vulkan.org/samples/latest/samples/performance/subpasses/README.html).
- The relevant academic nudge is the same batching lesson from
  [VectorVisor, USENIX ATC 2023](https://www.usenix.org/conference/atc23/presentation/ginzburg):
  GPU binary translation pays when many copies of the same compute-bound body
  run concurrently. For this emulator, that argues against tiny one-dispatch
  SPU/RSX events and for coarse repeated jobs with verifier-first gates.

Added instrumentation:

- `rpcs3-upstream` RSX auditor now logs
  `blit_cache_rp(fill/src_layout/copy/hit_copy)` to separate cache-fill
  render-pass breaks from cache fanout-copy breaks.
- It also logs `blit_cache_defer(fill/src_layout)` for the new defer scout.
- Windows wrappers now accept `VerifyCachedDeferSampled` and
  `FastCachedDeferSampled`.
- `tools/summarize_eternal_sonata_rsx_auditor.ps1` parses the new counters and
  classifies them as `tile-locality-blit-cache`.

Controls and scouts:

- `FastSampled` control:
  `debug-captures/windows-lab/20260521-173058-rsx-fastsampled-route-check-field-windows/`.
  Clean field visual. It logged `7,770` sampled GPU resolve/blit dispatches,
  `2,588` `blit_src` render-pass breaks, and no cache activity.
- `FastCachedSampled`:
  `debug-captures/windows-lab/20260521-173413-rsx-fastcachedsampled-rp-scout-field-windows/`.
  Clean field visual. It logged
  `blit_cache(hit/miss/fill/fanout/reject)=6056/3028/3028/9084/0` and
  `blit_cache_rp(fill/src_layout/copy/hit_copy)=3026/3026/0/0`.
- `FastCachedTransferSampled`:
  `debug-captures/windows-lab/20260521-172407-rsx-blitcache-rp-scout-field-windows/`.
  This route rendered black and did not exercise the intended cache path
  (`fast=0`, cache counters zero, rejects were render-target rejects), so park
  it as failed for this route.
- `FastCachedDeferSampled`:
  `debug-captures/windows-lab/20260521-174659-rsx-fastcacheddefer-rp-scout-field-windows/`.
  The late screenshot was visually clean on `\\.\DISPLAY2`, host grade clean,
  and the error scan found no fatal/crash/Vulkan/validation issue. It logged
  `blit_cache(hit/miss/fill/fanout/reject)=2/3573/1/3/0`,
  `blit_cache_rp=3572/3572/0/0`, and
  `blit_cache_defer=3572/3572`. It moved only `3` resolves through the fast
  path and pushed the old cost back to normal resolve
  (`resolve_break_rt_src=3571`, `resolve_break_blit_src=0`,
  `rp_break=3571`, about `38.82` per 60 frames).

Decision:

- The useful proof is the negative split: cached fanout copies are not the
  hidden render-pass killer for non-transfer sampled cache. The first source
  fill/source-layout transition is.
- Late deferral does not find a practical same-source fill window in this route;
  it mostly gives up the cache and falls back to the normal resolve path.
- Keep `FastCachedSampled` as a correctness-clean `gpu-migration-credit`
  counter path only. Do not call it faster.
- Do not continue tuning transfer-src or defer-fill fanout for speed. The next
  real RSX-on-GPU attempt should be a render-pass-local source resolve, subpass
  / local-read shaped path, or a larger batched SPU/geometry job that moves
  coarse CPU work to GPU without one-dispatch-per-draw overhead.

## Combined RSX GPU-Credit Stack - 2026-05-21

Status: `gpu-migration-credit`, `parked-speed-path`, not a speed win, not a
200% gate candidate.

Combined audited field proof:

- Run:
  `debug-captures/windows-lab/20260521-175655-rsx-combined-gpu-credit-field-windows/`.
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA fence +
  VertexSuperset Fast + VertexPersistent Fast + IndexPersistent Fast`.
- Screen/input:
  `-WindowsGameScreen 1`, PadApi, CPU affinity `0x0F`, frame/vblank `240`.
- Screenshot `screenshots/screenshot-0138s.png` was visually clean in the Path
  to Tenuto field. Fatal/crash/Vulkan/validation scan found no actionable
  errors.

Auditor result:

| Counter | Total | Per 60 frames | Reading |
| --- | ---: | ---: | --- |
| RSX-local credit events | `1,358,389` | `13,721.10` | Strong GPU-residency accounting, not speed proof. |
| Persistent vertex fast | `669,194 / 7,273.88 MB` | `6,759.54 / 73.47 MB` | Repeated persistent vertex texel-buffer data came from the long-lived cache heap instead of rewriting generated bytes into the attribute ring. |
| Persistent index fast | `660,750 / 775.91 MB` | `6,674.24 / 7.84 MB` | Repeated native u16 index buffers came from the long-lived cache heap instead of regenerating/reuploading. |
| Sampled blit-source resolves | `8,820` | `89.09` | Fused GPU resolve/blit path used sampled MSAA reads. |
| GPU present upload | `1 / 3.52 MB` | `0.01 / 0.04 MB` | One fallback present upload used the GPU byte-swap path. |
| Host DMA fences | `15 / 24.20 MB` | `0.15 / 0.24 MB` | Fence scope stayed host-read narrowed. |
| Remaining render-pass breaks | `2,938` | `29.68` | Still dominated by blit-source source-layout render-pass breaks. |
| Remaining volatile vertex upload | `377.32 MB` | `3.81 MB` | Still rebuilt/pushed per draw. |
| Hard sync flushes | `302` | `3.05` | CPU/GPU drain still visible. |

No-auditor field isolation:

- Off control:
  `debug-captures/windows-lab/20260521-180043-cpu4-combined-ab-off-field-windows/`.
  Clean field, late title/overlay roughly `37.33 / 31.25 FPS`, RPCS3 CPU
  `26.2%`, GPU sum `22.0%`.
- Geometry-only:
  `debug-captures/windows-lab/20260521-181339-cpu4-geometry-only-fast-field-windows/`.
  Clean field, title/overlay roughly `35.53 / 31.50 FPS`, RPCS3 CPU `26.1%`,
  GPU sum `28.8%`. This is GPU-residency movement, not a speed win.
- Resolve/depth/present-only:
  `debug-captures/windows-lab/20260521-181653-cpu4-rsx-resolve-stack-fast-field-windows/`.
  Clean field, title/overlay roughly `31.80 / 35.85 FPS`, RPCS3 CPU `25.9%`,
  GPU sum `22.3%`. Mixed FPS counters, no clean speed claim.
- Full combined rerun:
  `debug-captures/windows-lab/20260521-182002-cpu4-combined-fast-rerun-field-windows/`.
  Clean field, title/overlay roughly `33.93 / 30.07 FPS` late, RPCS3 CPU
  `26.0%`, GPU sum `26.4%`. Compared with the Off control, this moves more
  RSX work onto GPU paths but does not improve CPU4 field FPS.

Rejected/not-comparable moving-loop attempts:

- `debug-captures/windows-lab/20260521-182603-cpu4-combined-fast-movingloop-rerun-windows/`
  stayed on `Now Loading...` through the tagged movement screenshots. Lower host
  load there is a loading-screen artifact.
- `debug-captures/windows-lab/20260521-183034-cpu4-combined-fast-movingloop-longsettle-windows/`
  left the loading screen but produced black tagged frames with the overlay
  alive. Error scan was clean, so classify it as route/render-state invalid, not
  a crash.
- Control route check:
  `debug-captures/windows-lab/20260521-200247-cpu4-off-movingloop-longsettle-routecheck-windows/`
  used the same long-settle moving macro, screen 1, PadApi, CPU affinity
  `0x0F`, frame/vblank `240`, and all RSX experiment gates off. It reached
  clean Path to Tenuto field gameplay at `screenshot-0126s-start.png`, clean
  movement at `screenshot-0135s-move1.png`, and clean late field at
  `screenshot-0157s-late.png`; fatal/crash/Vulkan/validation scan was empty.
  This proves the long-settle moving route itself is valid. Therefore the
  combined-stack black moving frames are a stack interaction/regression or
  render-state problem, not merely a broken macro.

Geometry-only moving-loop bisect:

- First pass:
  `debug-captures/windows-lab/20260521-203253-cpu4-geometry-only-movingloop-longsettle-windows/`.
  It used only `VertexSuperset Fast + VertexPersistent Fast + IndexPersistent
  Fast` on the same CPU4/screen-1/PadApi route, but all tagged screenshots
  remained on the Load screen after `Load complete`. Error scan was empty.
  Classify as input/load-confirm timing invalid, not visual proof.
- Reconfirm pass:
  `debug-captures/windows-lab/20260521-203858-cpu4-geometry-only-movingloop-longsettle-reconfirm-windows/`.
  Extra post-load confirms proved the geometry-only stack can transition into
  and render the field, but it also opened the save-point menu before movement.
  This is field/menu visual proof only, not moving-gameplay proof.
- Delayed-confirm pass:
  `debug-captures/windows-lab/20260521-204333-cpu4-geometry-only-movingloop-delayed-confirm-windows/`.
  One later post-load confirm reached clean Path to Tenuto gameplay and accepted
  movement: `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png` were visually
  clean. Fatal/crash/Vulkan/validation scan was empty. Host checks were clean;
  late samples were about CPU `28.3-28.8%` and GPU engine sum `25.5-26.9%`.
  Classification: geometry-only fast vertex/index cache stack is not the
  combined-stack black-frame culprit on this route. It remains
  `gpu-migration-credit`, not a speed win and not a 200% gate candidate.

Decision:

- The combined stack is real RSX GPU migration credit: it moves repeated
  vertex/index buffers, sampled blit resolves, one present upload, and host-DMA
  fence scope toward GPU-resident or GPU-local work.
- It is not a speed win. The no-auditor CPU4 field result is flat-to-lower, and
  the moving-gameplay combined-stack route is visually invalid while the same
  Off route is clean.
- Do not port to Thor/Android and do not claim progress toward the 200% gate.
- Geometry-only fast vertex/index caches are moving-route clean, so the next
  Windows-only bisect target is the `resolve/depth/present-only` side of the
  combined stack on the delayed-confirm moving route. Only after that side is
  clean should the sprint return to larger render-pass-local
  blit-source/source-layout work or a verified coarse SPU/PPU job/codegen
  superpath. More one-dispatch-per-draw RSX compute is unlikely to stack into
  the required gain.

Delayed-confirm moving-route update:

- Resolve/depth/present-only run:
  `debug-captures/windows-lab/20260521-210440-cpu4-resolve-depth-present-movingloop-delayed-confirm-windows/`.
  Stack was `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA
  fence`, with geometry caches off. It used the same delayed-confirm moving
  route, screen 1, PadApi, CPU affinity `0x0F`, and frame/vblank `240`.
  Screenshots `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png` were visually
  clean, and the fatal/crash/Vulkan/validation scan was empty. Host checks were
  clean; late samples were about CPU `27.9%` and GPU engine sum `24.1-26.4%`.
  Classification: this side is not the black-frame culprit by itself.
- Full combined delayed-confirm run:
  `debug-captures/windows-lab/20260521-210934-cpu4-combined-fast-movingloop-delayed-confirm-windows/`.
  Stack was `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA
  fence + VertexSuperset Fast + VertexPersistent Fast + IndexPersistent Fast`.
  It reached clean field start and moving/late screenshots
  (`screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, `screenshot-0162s-late.png`) on screen 1, with
  empty fatal/crash/Vulkan/validation scan and clean host checks. Late samples
  were about CPU `28.4-29.5%` and GPU engine sum `20.1-22.3%`.
  Classification: the combined stack is moving-route visually clean when the
  delayed-confirm macro is used. The prior black/loading captures are now best
  classified as route-timing invalid / timing-sensitive failed attempts, not a
  reproduced stack correctness failure.

Updated decision:

- The combined stack now has clean no-auditor moving-field visual coverage on
  the delayed-confirm route, in addition to the earlier audited field
  GPU-migration counters.
- It is still not a speed win and nowhere near the 200% gate. The moving-loop
  FPS is broadly in the same low-30s CPU4 band as the clean Off/half-stack
  controls, and this pass was an integration/correctness bisect, not a matched
  A/B speed proof.
- Keep it Windows-only, default-off, and `gpu-migration-credit`. The next useful
  speed step is a matched delayed-confirm moving-loop A/B or a new coarse
  render-pass-local/SPU-codegen job; do not spend more time treating the old
  black frames as the current blocker.

Matched delayed-confirm moving-loop A/B:

- Off control:
  `debug-captures/windows-lab/20260521-214442-cpu4-delayed-confirm-ab-off-movingloop-windows/`.
  All RSX experiment gates were off. It used the delayed-confirm moving macro,
  screen 1, PadApi, CPU affinity `0x0F`, frame/vblank `240`, auditor off.
  Screenshots `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0150s-move2.png`, and `screenshot-0162s-late.png` were visually
  clean. Error scan was empty. Host grade was clean. Tagged title FPS was about
  `26.60`, `26.78`, `30.48`, `35.01`; tagged overlay FPS was about `27.89`,
  `24.63`, `30.29`, `36.66`. Late host samples were CPU `34.2%` / `29.3%` and
  GPU engine sum `18.5%` / `19.4%`.
- Combined stack:
  `debug-captures/windows-lab/20260521-214905-cpu4-delayed-confirm-ab-combined-movingloop-windows/`.
  Stack was `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA
  fence + VertexSuperset Fast + VertexPersistent Fast + IndexPersistent Fast`
  on the same delayed-confirm moving macro, screen 1, PadApi, CPU affinity
  `0x0F`, frame/vblank `240`, auditor off. Screenshots
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png` were visually
  clean. Error scan was empty. Host grade was clean. Tagged title FPS was about
  `27.91`, `34.66`, `32.84`, `32.33`; tagged overlay FPS was about `38.94`,
  `24.24`, `33.11`, `32.86`. Late host samples were CPU `28.8%` / `28.8%` and
  GPU engine sum `19.0%` / `24.6%`.
- Reading: across the four tagged screenshots, combined averaged about `31.94`
  title FPS versus `29.72` Off (`+7.5%`) and about `32.29` overlay FPS versus
  `29.87` Off (`+8.1%`). CPU samples also moved in the desired direction, with
  similar or lower CPU and higher late GPU use. However, the per-tag ordering is
  mixed (`late` favored Off), and this is a single A/B pair on one moving route.
  Classification: `windows-micro-win-candidate` plus `gpu-migration-credit`, not
  a durable speed win, not a 200% gate candidate. Next proof should repeat the
  delayed-confirm A/B or move to a larger architectural lane before spending
  more time stacking tiny RSX flags.

Reverse-order repeat:

- Combined first:
  `debug-captures/windows-lab/20260521-221517-cpu4-delayed-confirm-ab2-combined-movingloop-windows/`.
  Same combined stack, delayed-confirm moving macro, screen 1, PadApi, CPU
  affinity `0x0F`, frame/vblank `240`, auditor off. Screenshots
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png` were visually
  clean. Error scan was empty. Host grade was clean. Tagged title FPS was about
  `39.75`, `37.44`, `25.23`, `31.60`; tagged overlay FPS was about `35.53`,
  `47.53`, `31.87`, `28.19`. Late host samples were CPU `29.2%` / `29.8%`
  and GPU engine sum `25.8%` / `20.6%`.
- Off second:
  `debug-captures/windows-lab/20260521-221943-cpu4-delayed-confirm-ab2-off-movingloop-windows/`.
  Same route and settings with all RSX experiment gates off. Screenshots
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png` were visually
  clean. Error scan was empty. Host grade was clean. Tagged title FPS was about
  `35.91`, `28.72`, `31.84`, `33.48`; tagged overlay FPS was about `37.17`,
  `32.07`, `36.20`, `34.25`. Late host samples were CPU `29.5%` / `29.2%`
  and GPU engine sum `28.9%` / `21.3%`.
- Reading: the reverse-order repeat stayed positive but smaller, about `33.51`
  title FPS versus `32.49` Off (`+3.1%`) and `35.78` overlay FPS versus
  `34.92` Off (`+2.5%`). Across both A/B pairs, the combined stack averages
  about `+5%` by both title and overlay FPS. Per-tag ordering remains noisy, so
  this should be treated as a small repeated `windows-micro-win` and durable
  `gpu-migration-credit`, not a major speed win and not a 200% gate candidate.
  The next useful work should either find another compatible small win with a
  different bottleneck or target a larger render-pass-local/SPU-codegen lane.

FastCachedSampled add-on auditor check:

- Run:
  `debug-captures/windows-lab/20260521-224827-cpu4-combined-fastcachedsampled-movingloop-auditor-windows/`.
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-combined-fastcachedsampled-movingloop-auditor -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastCachedSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsRsxAuditor 60 -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- Visual/log status:
  reached Path to Tenuto field and accepted movement on screen 1. Tagged
  screenshots were `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`. The late/move
  frames still show the small leaf/particle black-square artifacts seen in this
  delayed-confirm route family, so this is a compatibility/counter check rather
  than a new field/menu/battle visual promotion. Fatal/crash/Vulkan/validation
  scan was empty; the only `fatal` match was the normal config line. Host checks
  were clean, with late samples around CPU `26.6-27.4%` and GPU engine sum
  `21.8-25.8%`.
- Auditor summary:
  `133` records / `7,980` auditor frames, `8,301` queue submits, `299` hard sync
  flushes, `6,616` render-pass barrier breaks, color resolve calls/skips
  `19,854/19,854`, host DMA fences `15` / `24.19 MB`, graphics/compute pipeline
  creates `310/2`, and `2,933,059` RSX-local credit events
  (`22,053.08` per 60 frames).
- Migrated/cache counters:
  persistent vertex fast `1,447,313` hits / `15,965.06 MB`, persistent index
  fast `1,427,833` hits / `1,696.93 MB`, sampled fused blit resolves `19,854`,
  GPU present upload `1` / `3.52 MB`, and blit-source cache
  `hit/miss/fill/fanout/reject=13236/6618/6618/19854/0`.
- Critical reading:
  `FastCachedSampled` adds real RSX-local cache fanout and therefore earns
  `gpu-migration-credit`, but it does not fix the hidden source-layout cost:
  `blit_cache_rp(fill/src_layout/copy/hit_copy)=6616/6616/0/0`. That means the
  repeated fanout copies are not the remaining render-pass killer; the first
  source fill/layout transition still is.
- Classification:
  `gpu-migration-credit`, `parked-speed-path`, not `windows-micro-win`, not a
  200% gate candidate. Do not spend the next Windows loop on a no-auditor
  FastSampled-vs-FastCachedSampled speed A/B unless the goal is compatibility
  only. The next RSX lane should be render-pass-local/source-local fill or
  subpass/local-read architecture; otherwise switch to SPU/codegen/HLE around
  the known hot kernel PCs.

Matched FastSampled auditor control:

- Run:
  `debug-captures/windows-lab/20260521-231500-cpu4-combined-fastsampled-movingloop-auditor-control-windows/`.
- Command shape:
  same delayed-confirm moving macro, screen 1, PadApi, CPU affinity `0x0F`,
  frame/vblank `240`, auditor `60`, and combined stack as above, but with
  `-WindowsRsxBlitSourceResolve FastSampled` instead of `FastCachedSampled`.
- Visual/log status:
  reached Path to Tenuto field and movement. Screenshots
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0150s-move2.png`, and `screenshot-0162s-late.png` were visually
  clean for this route. Title FPS tags were about `36.75`, `32.98`, `30.28`,
  and `35.66`; overlay FPS tags were about `38.29`, `27.19`, `30.20`, and
  `37.08`. Host grade was clean, with late samples around CPU `27.2-27.5%` and
  GPU engine sum `25.7-28.9%`. Error scan had no real crash/validation/Vulkan
  failures; matches were normal config/export/disassembly text.
- Auditor control summary:
  `134` records / `8,040` frames, `8,358` queue submits, `296` hard sync
  flushes, `6,672` render-pass barrier breaks, and all image breaks came from
  render-target resolve (`image_break_rt_res=6672`). It logged color
  resolve calls/skips `20,022/20,022`, sampled fused blit dispatches `20,022`,
  persistent vertex fast `1,451,672` hits / `16,352.52 MB`, persistent index
  fast `1,432,026` hits / `1,741.46 MB`, and one GPU present upload /
  `3.52 MB`.
- Direct counter comparison with the cached run:
  `FastCachedSampled` was `7,980` frames, `8,301` submits, `299` hard syncs,
  `6,616` render-pass breaks, `19,854` sampled fused blits, and
  `blit_cache(hit/miss/fill/fanout)=13236/6618/6618/19854`. Plain
  `FastSampled` was `8,040` frames, `8,358` submits, `296` hard syncs,
  `6,672` render-pass breaks, `20,022` sampled fused blits, and no cache path.
  Normalized, both sit at about `49.8` render-pass breaks and `149.4` fused
  blits per 60 frames.
- Classification:
  matched Windows `gpu-migration-credit` control and `parked-speed-path`.
  This confirms cached-source fanout adds extra GPU-resident bookkeeping but
  does not reduce the real source-layout/render-pass debt versus plain
  `FastSampled`. Do not run more cache-copy/fanout variants for speed. The next
  RSX-only experiment must change the architecture of the source read/fill
  itself, for example render-pass-local input attachment/local-read plumbing or
  a different source-preservation strategy; otherwise pivot to the SPU/codegen
  lane.

## 2026-05-22 RSX Source-Local Debt Auditor Tooling

Question:

- Can the Windows auditor make the remaining RSX source-read debt explicit so
  future loops do not keep rediscovering that cached-source fanout is not the
  speed lane?

Implementation:

- `tools/summarize_eternal_sonata_rsx_auditor.ps1` now emits a
  `Source-Local Debt` section and a top-level `Source-local debt class`.
- The section reports `resolve_break_blit_src`, source-read share of all
  render-pass breaks, breaks per fused resolve/blit, cached-source fanout per
  miss, cached fill/source-layout render-pass breaks, and deferred source-fill
  counters.
- Classification is deliberately narrow:
  `cache-fanout-active-source-layout-bound` when cached fanout is active but
  cache fills still hit the source-layout render-pass break, and
  `source-layout-renderpass-bound` for the plain fused path.

Verification:

- Regenerated the cached run summary:
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260521-224827-cpu4-combined-fastcachedsampled-movingloop-auditor-windows`.
- Regenerated the matched plain control:
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260521-231500-cpu4-combined-fastsampled-movingloop-auditor-control-windows`.
- Cached result:
  `cache-fanout-active-source-layout-bound`, `6616` source-read render-pass
  breaks, `49.74` per 60 frames, `100.00%` of all breaks, `33.32%` breaks per
  fused resolve/blit, and cached fanout per miss `3.00`. The cached
  fill/source-layout RP-break pair stayed `6616/6616`.
- Plain FastSampled control:
  `source-layout-renderpass-bound`, `6672` source-read render-pass breaks,
  `49.79` per 60 frames, `100.00%` of all breaks, and `33.32%` breaks per
  fused resolve/blit.

Reading:

- This is Windows-only analysis/tooling, not a new speed run.
- The result reinforces the previous decision: `FastCachedSampled` earns
  `gpu-migration-credit`, but more cache-fanout/copy variants are parked for
  speed because they do not reduce the source-layout break itself.
- Next RSX experiment should be render-pass-local/source-local source read/fill
  plumbing. If that cannot be made concrete, pivot back to SPU reduced-loop,
  codegen, or HLE work around the known hot reservation/kernel PCs.

Status: `analysis-tooling`, `gpu-migration-credit-accounting`,
`parked-speed-path`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Moving Source-Profile Scout

Question:

- On the delayed-confirm moving route, is the remaining source-layout debt
  shaped like many unrelated blits, or a smaller set of repeated GPU-consumed
  source reads that could justify render-pass-local/source-local work?

Run:

- `debug-captures/windows-lab/20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows/`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-combined-fastsampled-resolveprofile-movingloop -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsRsxResolve Profile -WindowsRsxAuditor 60 -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`.
- This was Windows-only. No Android, ADB, or Thor work was run.

Verification:

- RPCS3 was routed to screen 1 / `\\.\DISPLAY2`.
- Host contention stayed clean across prelaunch, postlaunch, two late samples,
  and postrun snapshots.
- Screenshots reached field start and movement:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- Fatal/crash/access-violation/Vulkan-validation scan had no runtime crash or
  validation failure. Matches were the static `Show fatal error hints: false`
  line and normal `cellSpurs*ExceptionEventHandler` export names.
- Visual caveat: the run reached moving field, but the late screenshot still
  shows the known bottom-left black flower-tile artifact seen in this route
  family. Treat this as source-profile/counter evidence, not a promotion-clean
  field visual.

Counter result:

- Auditor summary regenerated successfully.
- Records/frames: `137` records / `8,220` auditor frames.
- Source-local debt class: `source-layout-renderpass-bound`.
- RSX-local credit events: `3,006,517` total / `21,945.38` per 60 frames.
- Remaining render-pass break debt: `6,786` / `49.53` per 60 frames.
- Source-read render-pass breaks: `6,786` / `49.53` per 60 frames,
  `100.00%` of all render-pass breaks.
- Blit-source fused sampled resolves: `20,364` / `148.64` per 60 frames.
- Resolve coalescing scout:
  `blit_source_calls=20364`, `duplicate_tags=13576`,
  `unique_tag_floor=6788`, `duplicate_share=66.67%`.
- Blit-source profile keys: `25`, with the top key
  `0xd15bac2e1cb3e31b` accounting for `8,952` calls. The top shapes were all
  format `0x85` cached-destination source/destination blits, led by
  `640x360`, `768x768`, and split `1280x720` source regions.

Reading:

- The moving route again proves that the remaining breaks are not broad RSX
  chaos; they are the source-read/fill side of the fused blit-source path.
- The duplicate source-tag share is high, but the unique source floor
  (`6,788`) is essentially the render-pass break count (`6,786`). That matches
  the previous FastCachedSampled finding: cache fanout can reuse repeated
  source tags, but every unique source fill still causes the render-pass break.
- A speed-oriented RSX follow-up must remove or pre-stage the unique source-fill
  break itself, for example render-pass-local/source-local read plumbing,
  earlier pre-resolve before the dependent draw opens its pass, or a narrow
  input-attachment/local-read style path if the Vulkan constraints line up.
- Do not spend another loop on cached-source fanout/copy variants as a speed
  path. If source-local plumbing is too invasive for the next slice, pivot to
  SPU reduced-loop/codegen/HLE around the known hot reservation/kernel PCs.

Status: `gpu-migration-credit-accounting`, `rsx-source-profile-scout`,
`parked-speed-path`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Source-Shape Candidate Tooling

Question:

- Can the RSX auditor turn the resolve-profile rows into a concrete shortlist
  of source shapes for the next source-local/pre-stage experiment?

Implementation:

- `tools/summarize_eternal_sonata_rsx_auditor.ps1` now emits
  `Blit Source Source-Shape Profile` when resolve-profile rows are available.
- The table groups profile rows by source shape (`src`, requested size, source
  rect, pitch, bytes-per-pixel, format, context, and flags), then reports the
  number of destination shapes, key count, top destinations, and a narrow
  reading for whether the shape is a fanout candidate.
- The section explicitly labels the counts as profile aggregates. They are
  ranking guidance only because profile rows can be cumulative/slot aggregates.
  Continue using `Resolve Coalescing Scout` for exact call accounting.

Verification:

- Regenerated:
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- The regenerated summary contains the source-shape table and preserves the
  exact resolve accounting:
  `blit_source_calls=20364`, `duplicate_tags=13576`,
  `unique_tag_floor=6788`, `duplicate_share=66.67%`.
- Top ranked source shapes from this run:
  `0xc3840000` (`640x360`, one destination, profile count `8952`),
  `0xc1a30000` (`768x768`, one destination, profile count `6788`),
  `0xc0b20000` (`1024x720`, two destinations, profile count `6788`),
  `0xc0b22000` (`512x720`, two destinations, profile count `6788`), and
  `0xc0b21000` (`1024x720`, two destinations, profile count `6788`).

Reading:

- This is Windows-only analysis/tooling. No Android, ADB, or Thor work was run.
- The most promising RSX-only next slice is now concrete: target the repeated
  `cached-dest` source shapes for earlier pre-stage/local-read plumbing, then
  prove that unique source-fill render-pass breaks drop below the current
  `6786` per moving run (`49.53` per 60 frames).
- This is not a speed win and not a 200% gate candidate. It is a scout that
  keeps the next GPU-migration attempt pointed at source-fill debt instead of
  another cache-fanout variant.

Status: `analysis-tooling`, `rsx-source-shape-scout`, `parked-speed-path`,
not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Source-Local Architecture Scout

Question:

- Is the next RSX path a quick Vulkan local-read toggle, or does the core need
  actual render-pass/input-attachment plumbing around the blit-source path?

Static Windows-lab code scout:

- Searched the local RSX/Vulkan code only. No Android, ADB, Thor build, or
  device capture was run.
- Existing input-attachment support is real but narrow:
  `VKRenderPass.cpp` can encode `input_attachments_mask`, carry
  `input_attachment_ids`, and set `subpass.pInputAttachments`.
- Current core draw usage does not feed source IDs into that path:
  `VKGSRender.cpp` creates the normal render-pass key from `m_fbo_images`,
  while `VKDraw.cpp` refreshes from `m_current_renderpass_key`; only overlays
  appear to use actual input-attachment descriptors today.
- The current Eternal Sonata fused blit-source path is still compute/scratch:
  `VKTextureCache.h::try_fused_blit_source_resolve` dispatches
  `resolve_blit_image` / `resolve_blit_image_to_scratch`, and
  `VKTextureCache.cpp` only adds `VK_IMAGE_USAGE_STORAGE_BIT` to
  `blit_engine_dst` images when the fused resolve mode is active.
- `device.cpp` watches `VK_KHR_dynamic_rendering_local_read` and
  `VK_EXT_shader_tile_image`, but the local feature plumbing currently only
  stores/enables the existing `VK_EXT_attachment_feedback_loop_layout` path.
- Offline join of the latest resolve/source CSVs shows the exact hot source:
  resolve base `0xc0b20000`, pitch `10240`, height `720`. The three split
  source shapes inside that base are `0xc0b20000` (`1024x720`),
  `0xc0b21000` (`1024x720`), and `0xc0b22000` (`512x720`), each with profile
  count `6788` and two destinations. Their combined profile count is `20364`,
  matching the exact resolve-profile `blit_source_calls=20364`. This is the
  concrete source-local target, not the broader profile aggregate total
  (`48500`).

Reading:

- Source-local is still plausible because the measured source shapes are
  repeated GPU-consumed render-target reads, but it is not a one-line
  extension toggle in this tree.
- The immediate hot target is a single split `1280x720` MSAA render-target
  source at `0xc0b20000`/pitch `10240`, not a large cloud of unrelated
  resources. That makes a profile-gated pre-stage/local-read experiment worth
  attempting before abandoning RSX for the SPU/codegen lane.
- The next useful code slice should stay conservative:
  add a `Profile`-only source-local eligibility counter at the
  `try_fused_blit_source_resolve` call site, keyed by the already-ranked
  source shapes, then prove whether the hot `cached-dest` shapes are actually
  the current render-pass attachment or an already-closed source that must be
  pre-staged before the dependent draw.
- Do not jump straight to `VK_KHR_dynamic_rendering_local_read` or
  `VK_EXT_shader_tile_image` as a fast path until device feature support is
  plumbed into `optional_features_support`, enabled at device creation, and
  proven present in the Windows lab GPU.

Status: `architecture-scout`, `rsx-source-local-prep`, `parked-speed-path`,
not a `gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate
candidate.

## 2026-05-22 Resolve Source-Base Join Tooling

Question:

- Can the auditor prove which source-profile shapes belong to the exact
  blit-source resolve base, instead of relying on broader profile aggregates?

Implementation:

- `tools/summarize_eternal_sonata_rsx_auditor.ps1` now emits
  `Resolve Source-Base Join` when both resolve-profile and blit-source profile
  rows are present.
- The join groups exact `reason=blit-source` resolve rows by base/pitch/size,
  then includes only blit-source profile rows whose `src` address falls inside
  that resolve base span. This separates the concrete source-local target from
  unrelated cumulative source-profile rows.

Verification:

- Regenerated:
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- Parser check passed for the summarizer.
- No RPCS3 process was left running, and no Android, ADB, or Thor work was run.
- Existing source capture screenshots are present:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- The regenerated summary now reports one exact source-base join:
  `20364` resolve calls, `20364` source-profile calls inside base,
  `100.00%` match, `13576` duplicate tags, base `0xc0b20000`,
  `1280x720`, format `0x0000002c`, `2x` MSAA, pitch/grid `10240/2x1`.
- Split source shapes inside that base:
  `6788x +0x0 1024x720 0/0/1024/720`,
  `6788x +0x1000 1024x720 1024/0/2048/720`, and
  `6788x +0x2000 512x720 2048/0/2560/720`, each with two destinations.
- Error scan on the source capture still only matches the static
  `Show fatal error hints: false` line.

Reading:

- The next RSX local-read/pre-stage target is now exact: one split
  `1280x720` MSAA color source at `0xc0b20000`, not the unrelated
  `640x360` / `768x768` profile aggregate rows.
- The speed hypothesis is also exact: a useful source-local path must reduce
  the current `6786` source-read render-pass breaks per moving run
  (`49.53` per 60 frames) by handling this base before or inside the dependent
  render pass.
- This is Windows-only analysis/tooling, not a speed run. It does not change
  the 200% gate status.

Status: `analysis-tooling`, `rsx-source-base-join`, `parked-speed-path`,
not a `gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate
candidate.

## 2026-05-22 Source-Base Join CSV Export

Question:

- Can the exact source-local target be emitted as machine-readable data so the
  next profile-gated RSX code slice does not depend on copying Markdown rows?

Implementation:

- `tools/summarize_eternal_sonata_rsx_auditor.ps1` now accepts
  `-SourceBaseJoinCsvPath` and writes
  `eternal-sonata-rsx-source-base-join.csv` by default whenever resolve-profile
  and blit-source profile rows are both present.
- The CSV exports the exact join row with resolve calls, duplicate tags,
  source-profile count inside the base span, match share, base, size, format,
  sample/grid/pitch, source-shape count, and the joined source-shape list.

Verification:

- Parser check passed for the summarizer.
- Regenerated:
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- New CSV:
  `debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows\eternal-sonata-rsx-source-base-join.csv`.
- CSV row:
  `count=20364`, `dup=13576`, `matched=20364`, `match_share=100`,
  `base=0xc0b20000`, `span_mb=7.03125`, `1280x720`, `fmt=0x0000002c`,
  `samples=2`, `grid=2x1`, `pitch=10240`, `shapes=3`.
- Joined source shapes:
  `6788x +0x0 1024x720 0/0/1024/720`,
  `6788x +0x1000 1024x720 1024/0/2048/720`, and
  `6788x +0x2000 512x720 2048/0/2560/720`.
- Existing source capture screenshots are still present, and the error scan
  still only matches the static `Show fatal error hints: false` line.
- No Android, ADB, Thor work, or new gameplay run was performed.

Reading:

- This is analysis/tooling only, but it makes the next source-local experiment
  much less hand-wavy: the code can target the CSV's exact `0xc0b20000`
  source-base shape and measure whether `resolve_break_blit_src` drops.
- Still not a speed win, not `gpu-migration-credit`, and not a 200% gate
  candidate.

Status: `analysis-tooling`, `rsx-source-base-csv`, `parked-speed-path`,
not a `gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate
candidate.

## 2026-05-22 Source-Local Acceptance Target

Question:

- What exact counter target must a real RSX source-local/pre-stage experiment
  beat before it can count as useful?

Implementation:

- `tools/summarize_eternal_sonata_rsx_auditor.ps1` now adds acceptance-target
  fields to the source-base join CSV and table:
  `unique_floor`, `source_rp_breaks`, `source_rp_breaks_per60`, and
  `breaks_per_unique_percent`.
- The summary table now reports `Source RP Break Target` directly in the
  `Resolve Source-Base Join` section.

Verification:

- Parser check passed for the summarizer.
- Regenerated:
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- Updated CSV row:
  `count=20364`, `dup=13576`, `unique_floor=6788`, `matched=20364`,
  `source_rp_breaks=6786`, `source_rp_breaks_per60=49.5328467153285`,
  `breaks_per_unique_percent=99.9705362404243`, base `0xc0b20000`.
- Updated summary row:
  source RP break target `6786` (`49.53` per 60 frames, `99.97%` of the
  unique source floor).
- Existing source capture screenshots are present, error scan still only
  matches the static `Show fatal error hints: false` line, and no RPCS3 process
  was left running.
- No Android, ADB, Thor work, or new gameplay run was performed.

Reading:

- A source-local/pre-stage fast path is not meaningful unless it reduces
  `resolve_break_blit_src` below the current `6786` moving-run baseline. The
  strongest target is the exact `0xc0b20000` split `1280x720` MSAA source base.
- Because the break count is essentially the unique source floor, this remains
  a source-fill/layout architecture target, not a cache-fanout target.
- This is Windows-only analysis/tooling, not a speed win, not
  `gpu-migration-credit`, and not a 200% gate candidate.

Status: `analysis-tooling`, `rsx-source-local-acceptance-target`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 Source-Local Eligibility Counter Placement

Question:

- Where should the next profile-only counter live so it can tell whether the
  hot `0xc0b20000` blit-source resolve is a true source-local/pre-stage
  candidate?

Static Windows-lab code scout:

- Searched the local Common and Vulkan RSX code only. No Android, ADB, Thor
  build, or device capture was run.
- The exact fused path is the common texture-cache call at
  `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Common/texture_cache.h:3433`,
  where `traits::try_fused_blit_source_resolve(...)` receives the render-target
  source, destination image, source/destination areas, transfer flags, and null
  region state.
- The common callsite still has the RSX metadata needed to classify the hot
  source: `src_subres.surface->get_memory_range()`, `dst_base_address`,
  `cached_dest->get_section_base()`, `src.pitch`, `dst.pitch`, destination
  context, and source/destination GCM formats. `get_section_base()` resolves to
  `cpu_range.start` in
  `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Common/texture_cache_utils.h:1094`.
- `rsx::typeless_xfer` carries source/destination context, format, typeless,
  flip, and scaling flags, but not source/destination RSX base or pitch. That
  means format/context gates are already available in the Vulkan trait, while
  the exact source-base decision is not.
- `VKTextureCache.h:38` is the backend-specific fused resolve gate. It can see
  the Vulkan render-target/image objects and the typeless transfer flags, but it
  cannot reconstruct the exact source base `0xc0b20000` or destination section
  identity unless the common callsite passes that metadata through.
- `VKResolveHelper.cpp:273` is too low-level for the eligibility counter. It
  only sees Vulkan images and rectangles, then performs layout changes and the
  compute resolve. It is useful for dispatch success/failure, not for deciding
  whether the repeated Eternal Sonata source base is the right GPU-local target.

Reading:

- The next code slice should add a profile-only metadata path at the
  `try_fused_blit_source_resolve` boundary, either by extending that trait
  signature with source/destination RSX metadata or by adding a separate
  candidate-recording trait hook beside the call. A separate hook is likely the
  lower-risk shape because it can stay no-op in GL and logging-only in Vulkan.
- The first counter should be gated to BLUS30161 and the known source target:
  base `0xc0b20000`, pitch `10240`, format `0x0000002c`, 2x MSAA, split source
  shapes `0x0`, `0x1000`, and `0x2000`. It should report exact-base hits,
  cached-dest hits, destination base/context, matching format, matching area,
  and whether the Vulkan source is still a render target requiring resolve.
- This remains a source-layout/render-pass-debt experiment. A useful follow-up
  must reduce `resolve_break_blit_src` below the current moving-run baseline of
  `6786` (`49.53` per 60 frames). If it only increases blit cache hits without
  lowering that break count, it is not useful for the current GPU-offload lane.

Verification:

- Existing source-profile capture remains the evidence base:
  `debug-captures/windows-lab/20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- Regenerated the auditor summary for that capture with
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- Confirmed the source-base CSV row still reports `count=20364`,
  `dup=13576`, `unique_floor=6788`, `matched=20364`,
  `match_share=100`, base `0xc0b20000`, pitch `10240`,
  `source_rp_breaks=6786`, `source_rp_breaks_per60=49.5328467153285`,
  and `breaks_per_unique_percent=99.9705362404243`.
- Confirmed the existing screenshots are present:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- Error scan still only matched the static `Show fatal error hints: false`
  line plus normal `cellSpurs*ExceptionEventHandler` export names. No crash,
  access violation, validation failure, or Vulkan error was found by the scan.
- No `rpcs3` process was left running. `git diff --check` on this ledger only
  reported the usual LF-to-CRLF warning.
- This checkpoint is static analysis plus ledger only. It is not a new speed
  run, not `gpu-migration-credit`, not a `windows-micro-win`, and not a 200%
  gate candidate.

Status: `architecture-scout`, `rsx-source-local-counter-placement`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 Source-Local Eligibility Summary

Question:

- Does the existing Windows profile data already prove the hot source base is
  eligible for a future source-local/pre-stage fast path, or do we need another
  C++ counter first?

Implementation:

- Extended `tools/summarize_eternal_sonata_rsx_auditor.ps1` with a
  `Source-Local Eligibility` section and default CSV:
  `eternal-sonata-rsx-source-local-eligibility.csv`.
- The tool now uses the existing Windows-lab callsite profile rows from
  `Thor RSX Blit Source Profile` instead of requiring a new behavior patch.
  It joins the exact resolve source base, then checks cached-destination,
  clean flags, matching format, matching area, and non-render-target
  destination gates.
- The CSV aggregates each concrete source/destination pair so the next code
  slice can target exact shapes without copying Markdown rows.

Verification:

- Parser check passed for the summarizer.
- Regenerated:
  `.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- New CSV:
  `debug-captures\windows-lab\20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows\eternal-sonata-rsx-source-local-eligibility.csv`.
- Eligibility result for top base `0xc0b20000` / pitch `10240`:
  `20364 / 20364` source-profile rows are cached-dest, clean flags,
  format-match, area-match, non-render-target destination, and fully eligible.
- Concrete eligible pairs, all `3394` calls each, `src_fmt=dst_fmt=0x85`,
  `src_ctx=8`, `dst_ctx=4`, `flags=0x20`:
  `0xc0b20000 -> 0xc27c4080`, `0xc0b20000 -> 0xc3af2100`,
  `0xc0b21000 -> 0xc27c5080`, `0xc0b21000 -> 0xc3af3100`,
  `0xc0b22000 -> 0xc27c6080`, and `0xc0b22000 -> 0xc3af4100`.
- Existing screenshots are present:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- Error scan still only matched the static `Show fatal error hints: false`
  line plus normal `cellSpurs*ExceptionEventHandler` export names. No crash,
  access violation, validation failure, or Vulkan error was found by the scan.
- No `rpcs3` process was left running. `git diff --check` on the summarizer
  and ledger only reported the usual LF-to-CRLF warnings.
- No Android, ADB, Thor work, or new gameplay run was performed.

Reading:

- We do not need another profile counter before attempting the next
  source-local code slice in the Windows lab. The existing callsite profile
  already proves the hot source base is a clean cached-dest copy-like workload.
- This strengthens the GPU-offload lane: the next experiment should target
  these six exact pairs and must reduce `resolve_break_blit_src` below the
  current `6786` moving-run baseline. It still must keep field/menu/battle
  visuals correct before counting as anything promotable.
- This is Windows-only analysis/tooling. It is not a speed win, not
  `gpu-migration-credit`, and not a 200% gate candidate.

Status: `analysis-tooling`, `rsx-source-local-eligibility`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 Source-Local Code Path Scout

Question:

- Does the current Windows-lab Vulkan code already have a cached source path
  that can beat the `resolve_break_blit_src=6786` moving-route target, or is
  the next useful RSX experiment a different architecture?

Static Windows-lab code scout:

- Inspected only `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
  No Android, ADB, Thor build, device capture, or new gameplay run was
  performed.
- The common blit-source consumer still records the right metadata at
  `rpcs3/Emu/RSX/Common/texture_cache.h:3472`, tries the fused Vulkan path at
  `:3483`, and falls back to the normal transfer-read resolve at `:3488` when
  the fused path returns false.
- The Vulkan trait gate in
  `rpcs3/Emu/RSX/VK/VKTextureCache.h:84-93` chooses between plain
  `resolve_blit_image(...)`, cached-source `resolve_blit_image_cached_source(...)`,
  and scratch verify modes. This confirms the existing `FastCachedSampled`
  route is the same callsite as the source-base/eligibility CSVs, not a side
  path.
- The cached-source helper in
  `rpcs3/Emu/RSX/VK/VKResolveHelper.cpp:518` creates a device-local
  single-sample cache image and keys it by source render target, format, and
  full source size. On a miss, it resolves the full source into that cache
  image; on every consumer, it copies from the cache into the cached
  destination.
- The miss path still observes the render-pass/source-layout problem directly:
  `VKResolveHelper.cpp:619-624` records whether a cache fill starts with an
  open render pass and whether the source is not already in the sampled-read
  layout. The actual fill calls `resolve_blit_image(...)`, whose image barriers
  break an open render pass through
  `rpcs3/Emu/RSX/VK/vkutils/barriers.cpp:20-24`.
- The fanout copy path is also not renderpass-local in general:
  `VKResolveHelper.cpp:476-480` records and ends an open render pass before
  `vkCmdCopyImage`. In the current Eternal Sonata route the measured fanout
  copies were not the visible break source, but this code shape means copy
  tuning is still not the architectural fix.

Evidence tie-back:

- Latest moving FastSampled source-profile run:
  `debug-captures/windows-lab/20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- The exact source target remains one split MSAA color base:
  `0xc0b20000`, `1280x720`, format `0x0000002c`, 2x MSAA, pitch `10240`,
  source RP break target `6786`.
- The eligibility CSV proves all `20364 / 20364` source-profile rows for that
  base are clean cached-dest copy-like candidates, across six source/destination
  pairs.
- Earlier matched cached-source evidence already showed why this code shape is
  parked for speed: `FastCachedSampled` added real cache fanout but kept the
  source-layout debt (`blit_cache_rp fill/src_layout=6616/6616`), while plain
  `FastSampled` stayed essentially identical at about `49.8` source breaks per
  60 frames. `FastCachedDeferSampled` moved the same debt into normal
  render-target resolve instead of eliminating it.

Reading:

- The next RSX-only Windows experiment should not be another cached fanout,
  transfer-src, or defer variant. Those move more residency bookkeeping to the
  GPU, but they reach the source too late in the consumer path to remove the
  hot source-layout render-pass break.
- A useful source-local experiment must change where the source is made
  readable. The two viable RSX directions are:
  - producer-side/pre-renderpass snapshot: capture the known `0xc0b20000`
    source after the producing draw or resolve point, before the dependent
    blit-source consumer opens a new render pass;
  - true renderpass-local/local-read plumbing: consume the source as an
    attachment/local input without forcing the image layout barrier that
    currently calls `end_renderpass`.
- Acceptance remains strict: the same moving route must reduce
  `resolve_break_blit_src` below `6786`, keep field/menu/battle visuals clean,
  and show no crash/Vulkan/validation errors before this can be promoted beyond
  `parked-speed-path`.

Status: `architecture-scout`, `rsx-source-local-code-path`,
`parked-speed-path`, not a new `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Source-Local Producer Hook Scout

Question:

- If the consumer-side cached-source path is too late to remove the
  `resolve_break_blit_src` debt, where is the lowest-risk producer-side hook
  for a Windows-only profile counter or prefill experiment?

Static Windows-lab code scout:

- Inspected only `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
  No Android, ADB, Thor build, device capture, or new gameplay run was
  performed.
- Draw completion marks render targets dirty at
  `rpcs3/Emu/RSX/VK/VKDraw.cpp:1302` via
  `m_rtts.on_write(m_framebuffer_layout.color_write_enabled, ...)`.
- The common surface store stamps a shared write tag at
  `rpcs3/Emu/RSX/Common/surface_store.h:1269` and writes it into each active
  color target through `surface->on_write_fast(write_tag)` or
  `surface->on_write(write_tag, require_resolve, ...)` at `:1278-1282`.
- The descriptor code then sets `last_use_tag` and marks MSAA targets as
  needing resolve in `rpcs3/Emu/RSX/Common/surface_utils.h:615-667`. This is
  exactly the state the source-local experiment needs: base address, pitch,
  dimensions, format, sample layout, `last_use_tag`, and `msaa_flags`.
- Forcing a resolve at draw-end is still risky because it would occur in the
  active draw stream. The better first hook is
  `rpcs3/Emu/RSX/VK/VKDraw.cpp:140-142`, `VKGSRender::close_render_pass()`.
  That method is a `VKGSRender` member, so it can inspect
  `m_rtts.m_bound_render_targets` after a natural render-pass close and before
  later blit-source consumers ask for the same target.
- The consumer trigger remains
  `VKGSRender::scaled_image_from_memory(...)` in
  `rpcs3/Emu/RSX/VK/VKGSRender.cpp:2707`, which calls
  `m_texture_cache.blit(...)`. That path eventually reaches the exact
  blit-source profile rows already summarized for source base `0xc0b20000`.

Concrete next experiment:

- Add a Windows-lab, profile-only `SourceLocalPrefillProfile` counter before
  any behavior change.
- Candidate placement: immediately after `vk::end_renderpass(...)` in
  `VKGSRender::close_render_pass()`.
- Gate it to BLUS30161 and exact hot source metadata:
  base `0xc0b20000`, pitch `10240`, `1280x720`, color format matching the
  current Vulkan target, `2x` MSAA, and `msaa_flags & require_resolve`.
- The counter should report:
  - natural render-pass closes observed;
  - bound render targets examined;
  - exact hot-source matches;
  - hot-source matches with `require_resolve`;
  - hot-source matches whose `last_use_tag` differs from the last resolved or
    prefetched tag.
- Only if this profile shows frequent hot-source matches at natural pass close
  should the next behavior patch expose a helper that pre-fills the existing
  cached-source image there. A useful fast path must still prove that later
  `resolve_break_blit_src` falls below `6786` on the same moving route.

Reading:

- This is a better first step than an immediate source-cache fast path. It
  proves whether the producer-side timing exists before adding GPU work.
- If the counter does not see the hot source at natural pass close, the
  source-local RSX lane should pivot to true renderpass-local/local-read
  plumbing or back to SPU/codegen/HLE around the known hot PCs.
- This is Windows-only architecture analysis. It is not a new speed run, not
  `gpu-migration-credit`, not a `windows-micro-win`, and not a 200% gate
  candidate.

Verification:

- Existing evidence run remains
  `debug-captures/windows-lab/20260522-025410-cpu4-combined-fastsampled-resolveprofile-movingloop-windows`.
- The source-base CSV still identifies the acceptance target as
  `resolve_break_blit_src=6786` for `0xc0b20000`.
- Existing screenshots for that run remain the visual proof base:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.

Status: `architecture-scout`, `rsx-source-local-producer-hook`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 SourceLocalPrefillProfile Moving-Loop Result

Question:

- Does the first low-risk producer-side hook,
  `VKGSRender::close_render_pass()`, see the hot Eternal Sonata source target
  before the consumer-side blit-source path forces the remaining
  `resolve_break_blit_src` debt?

Implementation:

- Added Windows-lab-only profile instrumentation in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- New env gate:
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`
  (`RPCSX_THOR_RSX_SOURCE_PREFILL_PROFILE` compatibility alias).
- The hook is title-gated to `BLUS30161`, records only after
  `vk::end_renderpass(...)` inside `VKGSRender::close_render_pass()`, and does
  not change rendering behavior.
- New auditor tuple:
  `source_prefill(close/bound/hot/resolve/tagdirty)`.
- Updated `tools/summarize_eternal_sonata_rsx_auditor.ps1` to parse and report
  that tuple in the normal summary/CSV output.

Verification:

- Windows build passed:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- Parser/summarizer pass succeeded on the new run.
- `git diff --check` passed for the touched Windows-lab C++ files and the
  summarizer, with only the usual LF-to-CRLF warnings.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.

Run:

- `debug-captures/windows-lab/20260522-080237-cpu4-source-prefill-profile-movingloop-windows`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-source-prefill-profile-movingloop -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsRsxResolve Profile -WindowsRsxAuditor 60 -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`, with
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- The lab moved RPCS3 to `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention summary: clean, `5` snapshots.
- Screenshots are present and visually reached the delayed-confirm moving field:
  `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.

Counters:

- `source_prefill(close/bound/hot/resolve/tagdirty)=4/4/0/0/0`.
- `resolve_break_blit_src=6770` (`50.52` per 60 frames), still `100%` of
  render-pass breaks.
- Fused sampled-MSAA blit-source dispatches: `20316`.
- Resolve source-base join remained exact:
  `20316 / 20316` rows joined to base `0xc0b20000`, `1280x720`,
  `0x0000002c`, `2x` MSAA, pitch `10240`.
- Source-local eligibility remained exact:
  `20316 / 20316` rows fully eligible across the same six concrete
  source/destination pairs.
- Error scan found only known normal noise for this route/profile family:
  frame-limit enum warning, SPU channel-loop warning, module lookup/lwmutex/
  semaphore ESRCH lines, and savedata callback result lines. No fatal error,
  access violation, Vulkan validation failure, or `VK_ERROR` was found.
- No `rpcs3` process was left running.

Reading:

- This hook is not the source-local prefill point. It saw only `4` natural-close
  probes and `0` hot-source matches while the same run still hit `6770`
  source-layout render-pass breaks.
- Do not build a prefill fast path at `VKGSRender::close_render_pass()`.
- The source-local RSX lane remains real, but the next Windows-only RSX step
  should inspect the direct `vk::end_renderpass(...)` callsites and/or true
  renderpass-local/local-read plumbing. A candidate must reduce
  `resolve_break_blit_src < 6770` on this same moving route before it can be
  called a speed candidate.

Status: `architecture-scout`, `rsx-source-local-producer-hook-rejected`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 Source-Read Render-Pass Break Callsite Scout

Question:

- After `SourceLocalPrefillProfile` showed that
  `VKGSRender::close_render_pass()` is not the hot-source prefill point, which
  exact Windows-lab call path is still producing the `resolve_break_blit_src`
  debt?

Static Windows-lab code scout:

- Inspected only
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.
- The consumer trigger remains
  `rpcs3/Emu/RSX/VK/VKGSRender.cpp:2707`,
  `VKGSRender::scaled_image_from_memory(...)`, which calls
  `m_texture_cache.blit(...)` while the current command buffer can already have
  an open render pass.
- The fused blit-source path enters
  `rpcs3/Emu/RSX/VK/VKResolveHelper.cpp:313`,
  `resolve_blit_image(...)`.
- Its source-read layout transition at `VKResolveHelper.cpp:375-392` records
  `resolve_barrier_kind::blit_src_to_general` using
  `vk::is_renderpass_open(cmd)`, then calls `vk::insert_image_memory_barrier`
  with `preserve_renderpass=false` and source
  `image_barrier_source::render_target_resolve`.
- The actual interrupting close is the generic barrier helper:
  `rpcs3/Emu/RSX/VK/vkutils/barriers.cpp:18-24`.
  If `vk::is_renderpass_open(cmd)` is true and preservation is false, it
  records an image-barrier break and calls `vk::end_renderpass(cmd)`.
- The normal render-target read hook at
  `rpcs3/Emu/RSX/VK/VKRenderTargets.cpp:1132-1148` records/skips the normal
  resolve for the fused blit-source reason before this compute blit path. That
  is why the visible debt shows up later as a source-read layout barrier, not
  as a normal RT resolve.

Evidence tie-back:

- Latest profile run:
  `debug-captures/windows-lab/20260522-080237-cpu4-source-prefill-profile-movingloop-windows`.
- Summarizer verified the exact split:
  `resolve_break_blit_src=6770`, `blit_resolve_sampled_fast=20316`, and
  `source_prefill(close/bound/hot/resolve/tagdirty)=4/4/0/0/0`.
- The source-read breaks are still `100%` of render-pass breaks in that run.
- Source-base join remained exact:
  `20316 / 20316` rows for base `0xc0b20000`, `1280x720`,
  `0x0000002c`, `2x` MSAA, pitch `10240`.
- Source-local eligibility remained exact:
  `20316 / 20316` rows fully eligible across six concrete cached-destination
  source/destination pairs.
- Screenshots from the same run are present and show the delayed-confirm moving
  field route: `screenshot-0131s-start.png`, `screenshot-0140s-move1.png`,
  `screenshot-0149s-move2.png`, and `screenshot-0162s-late.png`.
- Error scan for fatal/Vulkan/validation/access-violation patterns was clean,
  and no `rpcs3` process was left running.

Reading:

- The `close_render_pass()` prefill hook was looking at the wrong class of
  close. The hot path is not a natural pass close; it is a consumer-side source
  layout barrier interrupting an already-open render pass.
- Do not add a fast path at `VKGSRender::close_render_pass()`.
- The next useful Windows-only RSX experiment should either:
  - move the source-readable/prefill work to a producer timing point before
    `scaled_image_from_memory(...)` opens the dependent render pass; or
  - prototype a true renderpass-local/local-read design that avoids the
    `insert_image_memory_barrier(... preserve_renderpass=false ...)` source
    transition for the known hot source.
- A promotable candidate must reduce `resolve_break_blit_src < 6770` on the
  same delayed-confirm moving route while keeping field/menu/first-battle
  visuals correct.

Status: `architecture-scout`, `rsx-source-read-break-callsite`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 Source Readiness Fast-Path Feasibility Scout

Question:

- Is there a cheap Windows-only way to keep the hot sampled-MSAA source already
  readable before `scaled_image_from_memory(...)` calls the fused blit-source
  path, or does the remaining debt require deeper renderpass-local/local-read
  work?

Static Windows-lab code scout:

- Inspected only
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.
- `rpcs3/Emu/RSX/VK/VKTextureCache.h:83-93` selects the sampled fused path
  through `resolve_blit_image(...)` when `FastSampled` is active.
- `rpcs3/Emu/RSX/VK/VKResolveHelper.cpp:381-399` sets the sampled source read
  layout to `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL` and inserts the source
  barrier whenever the render target is not already in that layout.
- `rpcs3/Emu/RSX/VK/VKResolveHelper.cpp:407-450` only keeps the source in a
  readable layout for the non-sampled `GENERAL` path. The sampled path restores
  the original attachment layout after each compute blit.
- The cached-source helper at
  `rpcs3/Emu/RSX/VK/VKResolveHelper.cpp:617-630` still fills the cache by
  calling the same `resolve_blit_image(...)` path, and the defer variant only
  returns to the normal path when the source-layout break would happen.
- `rpcs3/Emu/RSX/VK/VKRenderPass.cpp:81-93` rejects
  `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL` in renderpass-key layout encoding.
  This matches the earlier failed `FastSampledKeepSrc` result: leaving a color
  render target in shader-read layout is not legal in the current rebind path
  without deeper renderpass-key/attachment transition work.

Counter verification:

- Latest moving profile run:
  `debug-captures/windows-lab/20260522-080237-cpu4-source-prefill-profile-movingloop-windows`.
- Auditor CSV aggregate:
  `blit_resolve_sampled_fast=20316`,
  `resolve_barrier_blit_src=20316`,
  `resolve_barrier_blit_restore=20316`,
  `resolve_break_blit_src=6770`,
  `source_prefill(close/bound/hot/resolve/tagdirty)=4/4/0/0/0`.
- Therefore no sampled fused blit in this run found the hot source already in
  `SHADER_READ_ONLY_OPTIMAL`, and every sampled fused blit paid a source-read
  transition plus a restore transition.
- Source-base join remains exact for the same route:
  `20316 / 20316` rows on base `0xc0b20000`, `1280x720`,
  `fmt=0x0000002c`, `2x` MSAA, pitch `10240`.
- Source-local eligibility remains exact across the same six source/destination
  pairs:
  `0xc0b20000 -> 0xc27c4080`,
  `0xc0b20000 -> 0xc3af2100`,
  `0xc0b21000 -> 0xc27c5080`,
  `0xc0b21000 -> 0xc3af3100`,
  `0xc0b22000 -> 0xc27c6080`,
  `0xc0b22000 -> 0xc3af4100`.

Reading:

- Do not spend another loop on a cheap sampled keep-source toggle. The current
  helper deliberately restores the attachment layout, and the renderpass-key
  path cannot currently bind a color attachment left in shader-read layout.
- Cached/fanout/defer variants are also too late for this specific debt because
  cache misses still need the same source transition after the dependent render
  pass is already open.
- The next executable Windows-only RSX experiment should either profile a
  producer/pre-stage point before the dependent render pass begins, with direct
  hot-source counters, or prototype real renderpass-local/local-read plumbing
  that avoids `insert_image_memory_barrier(... preserve_renderpass=false ...)`
  for the known hot source.
- Acceptance target is unchanged: a candidate must reduce
  `resolve_break_blit_src < 6770` on the same delayed-confirm moving route,
  keep field/menu/first-battle visuals clean, and remain default-off until it
  proves correctness.

Status: `architecture-scout`, `rsx-source-readiness`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 SourceBlitStateProfile Route-Failed Probe

Question:

- Can a profile-only consumer hook show whether the hot fused blit-source render
  target is already readable at the moment `texture_cache::upload_scaled_image`
  chooses the render-target source?

Implementation:

- Added profile-only Windows-lab instrumentation in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- The existing env gate is reused:
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- New auditor tuple:
  `source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)`.
- The hook records render-target blit-source state before the fused
  blit-source path can run. For Vulkan it tracks whether the source is the
  exact Eternal Sonata hot target, whether a render pass is open, whether the
  current layout is shader-read, color-attachment, or general, and whether the
  source still requires resolve or has a dirty write tag.
- Updated `tools/summarize_eternal_sonata_rsx_auditor.ps1` to parse and report
  the new tuple.

Verification:

- Windows build passed:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- Parser/summarizer pass succeeded on an old run without the new tuple and on
  the new run with the tuple.
- `git diff --check` passed for the touched Windows-lab C++ files and
  summarizer, with only the usual LF-to-CRLF warnings.
- `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE` was removed after the run.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.
- No `rpcs3` process was left running.

Run:

- `debug-captures/windows-lab/20260522-093119-cpu4-source-blit-state-profile-movingloop-windows`
- Command shape:
  `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-source-blit-state-profile-movingloop -InputMacro <delayed-confirm moving macro> -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxDmaFence Host -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsRsxResolve Profile -WindowsRsxAuditor 60 -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotMaxCount 0`, with
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- The lab moved RPCS3 to `\\.\DISPLAY2` via `-WindowsGameScreen 1`.
- Host contention summary: clean, `5` snapshots.
- Visual check failed the route: `screenshot-0131s-start.png`,
  `screenshot-0140s-move1.png`, `screenshot-0149s-move2.png`, and
  `screenshot-0162s-late.png` all remained on the `Now Loading...` screen
  instead of reaching the Path to Tenuto field. This run is not comparable to
  the moving-field source-local baseline.

Counters:

- `source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)=75719/0/50844/0/75719/0/0/75719`.
- `source_prefill(close/bound/hot/resolve/tagdirty)=1/1/0/0/0`.
- `blit_resolve_sampled_fast=0`.
- `resolve_break_blit_src=0`.
- `rp_break=0`.
- Error scan found only known boot/load noise for this route family: SPURS job
  error constants in disassembly, module export lookup lines, module lookup
  failures, and savedata callback result lines. No fatal error, access
  violation, Vulkan validation failure, `VK_ERROR`, or unsupported image
  layout was found.

Reading:

- The instrumentation and parser are usable, but this route did not reach the
  hot field source. Do not use this run for source-local acceptance, speed, or
  GPU-migration credit.
- The failed route still proves the hook is counting consumer-side render-target
  blit sources and that the sampled-read layout is not naturally present in the
  loading path, but the hot-source question remains open.
- Next Windows-only step should rerun with a state-aware/longer load wait or
  move the direct counter into the already-filtered fused blit-source path so a
  route failure cannot drown the signal in non-hot loading blits.
- The acceptance target remains unchanged: reduce
  `resolve_break_blit_src < 6770` on the delayed-confirm moving field route
  with correct field/menu/first-battle visuals.

Status: `route-failed`, `not-comparable`, `rsx-source-blit-state-tooling`,
not a `gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate
candidate.

## 2026-05-22 SourceFusedStateProfile Route-Failed Runs

Question:

- Can a narrower profile-only hook inside the already-filtered fused
  blit-source candidate path answer whether the hot source is color-attachment
  only, already shader-readable, or still requiring a source-read transition?

Implementation:

- Added Windows-lab profile-only instrumentation in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Reused env gate:
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- New auditor tuple:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)`.
- The hook records only after the fused blit-source gate has a Vulkan render
  target requiring resolve, so it should avoid the broad loading-path noise
  from `source_blit_state(...)`.
- Updated `tools/summarize_eternal_sonata_rsx_auditor.ps1` to parse the tuple
  and add it to the summary/CSV output.

Verification:

- Windows build passed:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- Summarizer pass succeeded on the new captures.
- The profile env var was removed after both runs.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.
- No `rpcs3` process was left running.

Runs:

- `debug-captures/windows-lab/20260522-100135-cpu4-source-fused-state-profile-movingloop-windows`
  used the delayed moving macro with a longer post-load wait, PadApi,
  `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank `240`, and the
  current combined RSX stack. Host contention was clean with `6` snapshots.
  Screenshots `screenshot-0146s-start.png`, `screenshot-0155s-move1.png`,
  `screenshot-0164s-move2.png`, and `screenshot-0177s-late.png` were
  black-screen-alive with only the RPCS3 overlay visible, not the Path to
  Tenuto field.
- `debug-captures/windows-lab/20260522-100728-cpu4-source-fused-state-profile-fieldretry-windows`
  used the stock field macro, PadApi, `-WindowsGameScreen 1`, CPU affinity
  `0x0F`, frame/vblank `240`, and the same RSX stack. Host contention was
  clean with `5` snapshots. Screenshots `screenshot-0117s.png` and
  `screenshot-0133s.png` stayed in the Load menu with the `Load complete`
  prompt visible. This proves the stock field macro's final Cross was too
  early for this run.

Counters:

- Moving-loop route-failed run:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=0/0/0/0/0/0/0/0`,
  `source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)=4517/0/3390/0/4517/0/0/4517`,
  `source_prefill(close/bound/hot/resolve/tagdirty)=2/2/0/0/0`,
  `blit_resolve_sampled_fast=0`, `resolve_break_blit_src=0`,
  `rp_break=0`, and blit-source reject reasons
  `region/typeless/format/rt/dispatch=0/0/0/4517/0`.
- Stock-field retry:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=0/0/0/0/0/0/0/0`,
  `source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)=4305/0/3230/0/4305/0/0/4305`,
  `source_prefill(close/bound/hot/resolve/tagdirty)=4/4/0/0/0`,
  `blit_resolve_sampled_fast=0`, `resolve_break_blit_src=0`,
  `rp_break=0`, and blit-source reject reasons
  `region/typeless/format/rt/dispatch=0/0/0/4305/0`.
- Error scans found no fatal error, access violation, Vulkan validation
  failure, `VK_ERROR`, or unsupported image layout in either run.

Reading:

- The new `source_fused_state(...)` tooling builds and parses, but neither run
  reached the hot fused sampled-MSAA source. These runs are not usable for
  source-local acceptance, speed, GPU-migration credit, or 200% proof.
- The zero fused-state hits combined with `render_target` rejects means the
  observed RSX work was still load/menu traffic, not the known hot field
  source from the successful `20260522-080237` moving baseline.
- The immediate next Windows-only blocker is input-route reliability, not RSX
  architecture. The next retry should press Cross after `Load complete` is
  visibly present, for example by adding a load-menu screenshot and a delayed
  second Cross before the field/movement shots, or by making the Windows lab
  state-aware for the load-complete prompt.
- Acceptance target remains unchanged: a candidate must reduce
  `resolve_break_blit_src < 6770` on a correct delayed-confirm moving field
  route, then survive menu/Options and first-battle visuals before any Thor
  promotion discussion.

Status: `route-failed`, `not-comparable`, `rsx-source-fused-state-tooling`,
not a `gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate
candidate.

## 2026-05-22 SourceFusedStateProfile Field-Menu Confirmation

Question:

- Once the route actually reaches the field, does the narrow
  `source_fused_state(...)` counter prove the hot fused blit-source is still a
  color-attachment source that forces source-read render-pass breaks, or was
  the previous source-local debt just broad loading/menu noise?

Runs:

- `debug-captures/windows-lab/20260522-102400-cpu4-source-fused-state-doubleconfirm-movingloop-windows`
  used a double-confirm macro: screenshot the `Load complete` prompt, press
  Cross, wait `9000 ms`, press Cross again, then try the moving-loop shots.
  It used PadApi, `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank
  `240`, `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`, and the current
  combined RSX stack. Host contention was clean with `5` snapshots.
- Visual result: `screenshot-0104s-loadconfirm.png` proved the load prompt was
  visible. `screenshot-0148s-start.png`, `screenshot-0158s-move1.png`,
  `screenshot-0167s-move2.png`, and `screenshot-0179s-late.png` reached the
  Path to Tenuto field with correct-looking visuals, but the second Cross
  opened the save-point menu (`Save game` / `Don't save game`). This is not
  moving-gameplay proof and not a speed result.
- `debug-captures/windows-lab/20260522-103035-cpu4-source-fused-state-oneconfirm-movingloop-windows`
  tried the cleaner one-confirm variant: screenshot, wait `1000 ms`, press one
  Cross, then movement shots. Host contention was clean with `6` snapshots,
  but every screenshot was black-screen-alive with only the RPCS3 overlay. It
  did not reach the hot field source and is not comparable.

Counters from the field-menu run:

- `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=25734/25734/8576/0/25734/0/25734/0`.
- `source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)=60247/25734/37675/0/60247/0/25734/34513`.
- `blit_resolve_sampled_fast=25734`.
- `resolve_break_blit_src=8576`.
- `rp_break=8576`, with source-read breaks making up `100%` of render-pass
  breaks.
- Source-base join was exact: `25734 / 25734`, base `0xc0b20000`,
  `1280x720`, `fmt=0x0000002c`, `2x`, pitch `10240`, split as three
  `1024/1024/512 x 720` source shapes.
- Error scan found no fatal error, access violation, Vulkan validation
  failure, `VK_ERROR`, or unsupported image layout.

Counters from the one-confirm black-screen run:

- `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=0/0/0/0/0/0/0/0`.
- `source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)=4389/0/3294/0/4389/0/0/4389`.
- `blit_resolve_sampled_fast=0`, `resolve_break_blit_src=0`, `rp_break=0`,
  and blit-source reject reasons `region/typeless/format/rt/dispatch=0/0/0/4389/0`.

Reading:

- The narrow fused-state hook answered the architectural question on a real
  field visual: the hot source is not already readable. Every hot fused
  candidate is still in color-attachment layout, every hot fused candidate
  still requires resolve, and the render-pass-open subset accounts for the
  source-read break debt.
- This confirms the next RSX-only speed lane should be source pre-stage before
  the dependent render pass begins, or a deeper renderpass-local/local-read
  design. More cache fanout or a cheap sampled keep-source toggle is the wrong
  next bet.
- The input route still needs cleanup before another moving proof: the
  double-confirm reaches the field but opens the save menu, while the
  one-confirm variant can fall into black-screen-alive. The next route should
  either press `circle` after any save-point menu before movement, or avoid the
  save point by moving the route start/first input away from the save prompt.
- This is useful RSX architecture evidence, but not speed, not moving proof,
  and not a 200% gate candidate.

Status: `architecture-scout`, `route-partial`, `rsx-source-fused-state-confirmed`,
`parked-speed-path`, not a `gpu-migration-credit`, not a `windows-micro-win`,
not a 200% gate candidate.

## 2026-05-22 SourceFusedStateProfile Circle-Close Moving Field

Question:

- If the double-confirm route opens the save-point menu, can a `circle`
  dismiss reliably produce a real moving-field capture while keeping the same
  narrow fused-source counters active?

Run:

- `debug-captures/windows-lab/20260522-105422-cpu4-source-fused-state-circleclose-movingloop-windows`
  used PadApi, `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank
  `240`, `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`, and the current
  combined RSX stack.
- The macro confirmed load, opened the save-point menu, pressed `circle`,
  then ran stick movement loops and captured field screenshots.
- Host contention was clean across `7` snapshots. RPCS3 was moved to
  `\\.\DISPLAY2`; PS3 gameplay stayed on screen 1 from the lab's perspective.
- The profile env var was removed after the run. No `rpcs3` process was left
  running. No Android, ADB, Thor build, Thor deploy, or Thor capture was
  performed.

Visual verification:

- `screenshot-0104s-loadconfirm.png` captured the `Load complete` prompt.
- `screenshot-0115s-maybe-save-menu.png` captured the save-point menu.
- `screenshot-0117s-start.png` proves `circle` dismissed the menu and returned
  to the Path to Tenuto field.
- `screenshot-0127s-move1.png`, `screenshot-0136s-move2.png`, and
  `screenshot-0148s-late.png` show the field without menu obstruction after
  movement input. This is a valid moving-field architecture profile route, not
  a speed-proof route.

Counters:

- `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=25770/25770/8588/0/25770/0/25770/0`.
- `source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)=60049/25770/37517/0/60049/0/25770/34279`.
- `blit_resolve_sampled_fast=25770`.
- `resolve_break_blit_src=8588`.
- `rp_break=8588`, with source-read breaks making up `100%` of render-pass
  breaks.
- Source-base join stayed exact: `25770 / 25770`, base `0xc0b20000`,
  `1280x720`, `fmt=0x0000002c`, `2x`, pitch `10240`, split as three
  `1024/1024/512 x 720` source shapes.
- Fast-path migrated-work counters were active but this run is still not a
  new speed claim: vertex persistent fast `1848985/312/0`,
  index persistent fast `1823591/271/0`, present upload GPU byte-swap
  `1 / 3.52 MB`.
- Narrow error scan found no fatal error, access violation, Vulkan validation
  failure, `VK_ERROR`, device lost, or crash marker.

Reading:

- The route problem is now solved for this scout: `circle` cleanly closes the
  save-point menu and produces field movement screenshots.
- The architectural answer did not change. On a confirmed moving-field route,
  every hot fused candidate is still color-attachment layout, none are already
  shader-readable, and every one still requires resolve. About one third of
  fused sampled-MSAA source resolves are still forcing source-read render-pass
  breaks.
- The next Windows-only RSX experiment should prototype a source-local
  pre-stage/pre-resolve path for the exact `0xc0b20000` split source span, then
  compare `resolve_break_blit_src` and `rp_break` on the same circle-close
  moving route. A win must reduce the break counter before it can count as a
  real GPU-residency improvement.
- This capture is useful because it converts the previous field-menu evidence
  into a clean moving-field scout. It is not 200% proof because it lacks the
  speed-proof gate's baseline/treatment comparison, menu/Options proof, and
  first-battle proof.

Status: `architecture-scout`, `moving-field-profile`,
`rsx-source-fused-state-confirmed`, `source-local-next`, not a
`gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Source-Cache Prefill Prototype Miss

Question:

- Can the exact hot sampled-MSAA source be resolved into the existing
  GPU-resident blit-source cache at a natural `close_render_pass()` point, so a
  later `FastCachedSampled` source read hits cache instead of forcing
  `blit_src_to_general` while a dependent render pass is open?

Implementation:

- Added a Windows-only, opt-in prototype in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Gate: `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=prefill`.
- New function: `vk::prefill_resolve_blit_source_cache(...)` fills the same
  cached-source image used by `FastCachedSampled`, but only when called from
  the new source-prefill hook.
- New auditor tuple:
  `source_prefill_cache(attempt/hit/fill/reject)`.
- Updated `tools/summarize_eternal_sonata_rsx_auditor.ps1` to parse the new
  optional tuple while keeping old logs parseable.

Verification:

- Windows build passed:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- New-run summarizer pass succeeded.
- Backward parser check succeeded on
  `debug-captures/windows-lab/20260522-105422-cpu4-source-fused-state-circleclose-movingloop-windows`.
- Diff checks passed with only LF/CRLF warnings.
- The prefill env var was removed after the run.
- No `rpcs3` process was left running.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.

Run:

- `debug-captures/windows-lab/20260522-113937-cpu4-source-prefill-fastcached-circleclose-movingloop-windows`
  used PadApi, `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank
  `240`, `FastCachedSampled`, `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=prefill`,
  and the current combined RSX stack. Host contention was clean across `6`
  snapshots.
- Visual result: route failed. `screenshot-0104s-loadconfirm.png` was not the
  load-complete prompt; it was the opening story line, "So, once more, a new
  journey begins." Later screenshots stayed in star/story/field-cutscene
  visuals instead of Path to Tenuto moving gameplay, with obvious black square
  artifacts in the flower-field scene. This is not comparable to the
  circle-close moving field scout.
- Narrow error scan found no Vulkan validation failure, access violation,
  `VK_ERROR`, or device lost marker, but the log did contain SPU fatal
  `Unknown STOP code` lines around `0:03:05`. Treat the run as failed, not as
  a renderer proof.

Counters:

- New prefill hook stayed cold:
  `source_prefill(close/bound/hot/resolve/tagdirty)=5/5/0/0/0`.
- No cache prefill work happened:
  `source_prefill_cache(attempt/hit/fill/reject)=0/0/0/0`.
- Existing cached-source path did run:
  `blit_cache(hit/miss/fill/fanout/reject)=10068/5034/5034/15102/0`.
- Cached-source misses still broke the open render pass:
  `blit_cache_rp(fill/src_layout/copy/hit_copy)=5033/5033/0/0`.
- `resolve_break_blit_src=5033`, `rp_break=5033`.
- Narrow fused source state stayed color/read-debt shaped:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=15102/15102/5033/0/15102/0/15102/0`.

Reading:

- This prototype did not test the intended prefill idea because the natural
  `close_render_pass()` hook saw zero hot source targets, so it never attempted
  a prefill. The later consumer still saw the exact source-layout-bound debt.
- The failed route means the lower absolute break count is not a speed or
  architecture win. It is a different story/cutscene path.
- Do not spend more time tuning cached-source fanout from this evidence. The
  next Windows-only RSX step should either move the pre-stage hook closer to
  the writer that actually produces `0xc0b20000`, or instrument begin/end
  render-pass target identity to find the true producer moment before trying
  another fast path.
- This is useful negative evidence: the simple natural-close prefill hook is
  not the right source-local insertion point.

Status: `failed`, `route-failed`, `source-prefill-hook-miss`,
`not-comparable`, not a `gpu-migration-credit`, not a `windows-micro-win`, not
a 200% gate candidate.

## 2026-05-22 Source Producer Hook Static Analysis

Question:

- Why did the source-cache prefill hook stay cold, and where should the next
  Windows-only source-local experiment attach if the goal is to move more of
  the hot sampled-MSAA source work onto the GPU without replaying the failed
  `close_render_pass()` idea?

Evidence:

- Clean moving-field scout:
  `debug-captures/windows-lab/20260522-105422-cpu4-source-fused-state-circleclose-movingloop-windows`.
- The last 12 steady 60-frame intervals all had
  `source_prefill_close=0` and `source_prefill_hot=0`, while each interval
  still had `source_fused_state_hot=360`, `source_fused_state_rp=120`,
  `resolve_break_blit_src=120`, and `rp_break=120`.
- The exact hot source-base join remains fully eligible and exact:
  `25770 / 25770` samples, base `0xc0b20000`, `1280x720`,
  `fmt=0x0000002c`, `2x`, pitch `10240`, split as
  `1024/1024/512 x 720`.
- Static path check in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`:
  `texture_cache.h` records the sampled-MSAA source state and calls
  `traits::try_fused_blit_source_resolve(...)` on the consumer side;
  `VKRenderTargets.cpp` skips the normal resolve in
  `render_target::memory_barrier(...)` when the blit-source fused path is
  enabled; `surface_store.h` calls `surface->on_write_fast(...)` or
  `surface->on_write(...)` when bound render targets are actually written;
  `surface_utils.h` then sets `last_use_tag` and marks MSAA surfaces as
  `require_resolve`.

Reading:

- `VKGSRender::close_render_pass()` is not the producer point for the clean
  Path to Tenuto moving-field route. The failed prototype saw only story-route
  closes, and the clean route's steady intervals show zero natural prefill
  closes while the consumer still sees 120 source-read render-pass breaks per
  60 frames.
- The useful hook is likely one layer earlier or one layer later: either the
  actual render-target write path in `surface_store::on_write(...)` /
  `surface::on_write_fast(...)`, or the specific
  `memory_barrier(resolve_reason_blit_source)` boundary that currently defers
  work to the consumer-side fused resolve.
- This is not a GPU migration credit yet. It is a narrowing step that prevents
  rerunning a cold close hook and points the next source-local GPU-residency
  attempt at the hot writer/consumer boundary that actually owns the debt.

Next exact step:

- Add profile-only hot-source writer counters around the render-target write
  path, keyed on base/pitch/format/samples and recording fast/full write path,
  `last_use_tag`, and `cache_tag`. Only after that proves repeated hot writes
  should we try a producer-fill cache or renderpass-local source-stage path.

Status: `analysis`, `source-producer-hook-found`, `close-prefill-parked`,
not a `gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate
candidate.

## 2026-05-22 Source Writer Profile

Question:

- Does the exact hot sampled-MSAA source have a small, useful producer hook in
  the render-target writer path, or would producer-side prefill work happen too
  often to be a sane GPU-residency experiment?

Implementation:

- Added profile-only writer counters in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Hook: `surface_store::on_write(...)`, before the existing
  `on_write_fast(...)` / `on_write(...)` decision updates the surface tag.
- VK trait records the exact hot Eternal Sonata source shape
  (`0xc0b20000/0xc0b21000/0xc0b22000`, pitch `10240`, `1280x720`,
  BGRA8, `2x`, `2x1` sample grid); GL trait is a no-op.
- New optional auditor tuple:
  `source_writer(hit/hot/fast/full/hot_fast/hot_full/hot_resolve/hot_tagdirty/hot_gtcache/hot_lecache)`.
- Updated `tools/summarize_eternal_sonata_rsx_auditor.ps1` to parse and
  summarize the tuple while keeping old logs parseable.

Verification:

- Windows build passed:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- Backward parser check succeeded on
  `debug-captures/windows-lab/20260522-105422-cpu4-source-fused-state-circleclose-movingloop-windows`;
  old logs default the new `source_writer_*` columns to zero.
- Diff checks passed with only LF/CRLF warnings.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.
- The profile env var was removed after the run. No `rpcs3` process was left
  running.

Run:

- `debug-captures/windows-lab/20260522-120840-cpu4-source-writer-profile-circleclose-movingloop-windows`
  used the same circle-close moving-field macro, PadApi, `-WindowsGameScreen 1`,
  CPU affinity `0x0F`, frame/vblank `240`, `FastSampled`, `DepthReadOnly`,
  `KeepReadOnly`, `GpuSwap`, persistent vertex/index fast caches, resolve
  profile, and `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- Host contention stayed clean across `6` snapshots.
- Visuals were correct for this architecture scout:
  `screenshot-0104s-loadconfirm.png` shows the `Load complete` prompt,
  `screenshot-0115s-maybe-save-menu.png` shows the save-point menu,
  `screenshot-0117s-start.png` shows the field after `circle`, and
  `screenshot-0127s-move1.png` / `screenshot-0136s-move2.png` /
  `screenshot-0148s-late.png` show unobstructed Path to Tenuto field movement.
- Narrow error scan found no fatal error, access violation, Vulkan validation
  failure, `VK_ERROR`, device lost marker, or unsupported image layout.

Counters:

- New writer profile:
  `source_writer(hit/hot/fast/full/hot_fast/hot_full/hot_resolve/hot_tagdirty/hot_gtcache/hot_lecache)=7021565/6981244/6970025/51540/6970024/11220/6981243/6975633/6970024/11220`.
- Steady last-12 intervals were extremely hot at the writer boundary: each
  60-frame interval had about `149k-150k` hot writer hits, about `149k` hot
  fast writes, and `240` hot full writes.
- The consumer-side source debt remained the familiar shape:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=16830/16830/5608/0/16830/0/16830/0`.
- `resolve_break_blit_src=5608`, `rp_break=5608`, and the source-read breaks
  are still `100%` of render-pass breaks in this shortened run.
- Source-base join stayed exact: `16830 / 16830`, base `0xc0b20000`,
  `1280x720`, `fmt=0x0000002c`, `2x`, pitch `10240`, split as three
  `1024/1024/512 x 720` source shapes.

Reading:

- The writer hook is real but much too hot for a naive producer-side prefill.
  The exact source is touched millions of times and most hot writer events are
  already on the fast `last_use_tag > cache_tag` path. Adding a resolve/cache
  fill directly to every writer event would almost certainly make the route
  worse.
- The useful source-local design must coalesce by source content tag, frame,
  or consumer demand. The consumer-side debt is orders of magnitude smaller
  (`44-58` source-read breaks per 60 frames across recent clean scouts), so the
  next experiment should be a coalesced source-stage marker or a
  `memory_barrier(resolve_reason_blit_source)`-adjacent path, not work in every
  `surface_store::on_write(...)` call.
- This is useful GPU-residency architecture evidence because it prevents a
  bad "prefill at every producer write" experiment. It is not a speed win,
  not a new GPU migration credit, and not a 200% gate candidate.

Next exact step:

- Add a coalesced source-stage scout keyed by `last_use_tag` / hot-source base
  that counts unique producer tags and compares them to `resolve_break_blit_src`.
  Only if unique producer tags line up with the consumer debt should a
  producer-fill or renderpass-local source-stage fast path be attempted.

Status: `architecture-scout`, `moving-field-profile`,
`source-writer-profile-confirmed`, `producer-fill-naive-parked`, not a
`gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Source Writer Tag Coalescing Scout Attempt

Question:

- If the hot writer stream is too large to use directly, does it collapse to a
  small number of unique source write tags per interval, making a future
  producer-stage cache or source-stage marker plausible?

Implementation:

- Added a profile-only tag scout in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- `surface_store::on_write(...)` now passes the current `write_tag` into the
  RSX backend trait, GL keeps a no-op, and the VK trait forwards it to
  `vk::rsx_auditor::record_source_writer_state(...)`.
- The auditor records a fixed-slot hot-source tag filter and logs the optional
  tuple:
  `source_writer_tag(new/repeat/collision/zero)`.
- `tools/summarize_eternal_sonata_rsx_auditor.ps1` now parses and summarizes
  the optional tuple while keeping older logs parseable.

Verification:

- Diff checks passed with only LF/CRLF warnings.
- Backward parser check succeeded on
  `debug-captures/windows-lab/20260522-120840-cpu4-source-writer-profile-circleclose-movingloop-windows`;
  old records default the new tag columns to zero.
- Windows build passed:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- The profile env var was removed after each run. No `rpcs3` process was left
  running.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.

Runs:

- `debug-captures/windows-lab/20260522-123255-cpu4-source-writer-tag-profile-circleclose-movingloop-windows`
  used the same circle-close moving-field macro, PadApi,
  `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank `240`,
  `FastSampled`, `DepthReadOnly`, `KeepReadOnly`, `GpuSwap`, persistent
  vertex/index fast caches, resolve profile, and
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`. Host contention stayed clean
  across `6` snapshots.
- Retry
  `debug-captures/windows-lab/20260522-123834-cpu4-source-writer-tag-profile-circleclose-movingloop-retry-windows`
  used the same command shape and stayed host-clean across `5` snapshots.

Visual and log result:

- Both runs were visually invalid: screenshots such as
  `screenshot-0104s-loadconfirm.png`, `screenshot-0117s-start.png`,
  `screenshot-0126s-move1.png`, and retry `screenshot-0117s-start.png` showed
  black game output with only the RPCS3 overlay visible, not the load prompt,
  save-point menu, or Path to Tenuto field.
- Narrow error scans found no real fatal error, access violation, Vulkan
  validation failure, `VK_ERROR`, device lost marker, or unsupported image
  layout. The only `fatal` match was the normal `Show fatal error hints:
  false` config line.

Counters:

- First invalid run:
  `source_writer(hit/hot/fast/full/hot_fast/hot_full/hot_resolve/hot_tagdirty/hot_gtcache/hot_lecache)=23648/0/1/23647/0/0/0/0/0/0`,
  `source_writer_tag(new/repeat/collision/zero)=0/0/0/0`,
  `source_fused_state_hot=0`, `resolve_break_blit_src=0`, `rp_break=0`.
- Retry:
  `source_writer_hit=21739`, `source_writer_hot=0`,
  `source_writer_tag(new/repeat/collision/zero)=0/0/0/0`,
  `source_fused_state_hot=0`, `resolve_break_blit_src=0`, `rp_break=0`.

Reading:

- The tag scout tooling builds and the parser reads it, but the run evidence
  is not valid for coalescing because both attempts failed the visual route
  before touching the known hot source. Zero hot-source and zero tag counts in
  these captures mean "wrong/black route", not "source debt solved".
- Do not count this as `gpu-migration-credit`, `windows-micro-win`, or a 200%
  gate candidate. Do not use the auditor summary's generic
  `gpu-migration-credit-candidate` line from these black captures, because the
  speed-proof gate requires correct screenshots.

Next exact step:

- Isolate the black route on Windows before another tag interpretation:
  either run the same field macro with source-prefill profile disabled as a
  control, or temporarily gate off only the new writer-tag scout while keeping
  the prior clean source-writer profile stack. Resume coalescing only after
  load-confirm, save menu, field start, and movement screenshots are correct
  again.

Status: `failed`, `visual-black`, `route-invalid`, `tag-tooling-built`,
`not-comparable`, not a `gpu-migration-credit`, not a `windows-micro-win`, not
a 200% gate candidate.

## 2026-05-22 Source Writer Tag Control And Valid Rerun

Question:

- Were the first two writer-tag scout captures black because the tag tooling
  broke rendering, or because the route/config landed in a bad visual state?
  Once visuals recover, does the writer tag stream actually coalesce?

Control:

- `debug-captures/windows-lab/20260522-125319-cpu4-source-writer-tag-control-profileoff-movingloop-windows`
  used the same circle-close moving-field macro, PadApi,
  `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank `240`,
  `FastSampled`, `DepthReadOnly`, `KeepReadOnly`, `GpuSwap`, persistent
  vertex/index fast caches, resolve profile, and RSX auditor, but with
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE` disabled.
- Host contention stayed clean across `5` snapshots.
- Visuals recovered: `screenshot-0104s-loadconfirm.png` showed `Load
  complete`, `screenshot-0115s-maybe-save-menu.png` showed the save prompt
  over field, `screenshot-0117s-start.png` showed the field after Circle, and
  `screenshot-0127s-move1.png` / `screenshot-0148s-late.png` showed moving
  field output instead of black overlay-only frames.
- Error scan found no real fatal error, access violation, Vulkan validation
  failure, `VK_ERROR`, device lost marker, or unsupported image layout. The
  only `fatal` match was the normal `Show fatal error hints: false` config
  line.

Valid profile rerun:

- `debug-captures/windows-lab/20260522-125925-cpu4-source-writer-tag-profile-rerun-after-clean-control-windows`
  used the same command shape, with
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- Host contention stayed clean across `5` snapshots.
- Visuals were valid for this architecture scout: load prompt, save menu,
  field start, and moving field screenshots all rendered. No real fatal,
  crash, Vulkan validation, `VK_ERROR`, device lost, or unsupported layout
  marker was found.

Counters:

- Profile-off control kept source-writer profiling disabled as intended:
  `source_writer_hit=0`, `source_writer_tag(new/repeat/collision/zero)=0/0/0/0`,
  while the known source-local debt returned:
  `resolve_break_blit_src=4326`, `rp_break=4326`.
- Valid profile rerun:
  `source_writer(hit/hot/fast/full/hot_fast/hot_full/hot_resolve/hot_tagdirty/hot_gtcache/hot_lecache)=5461199/5427066/5418351/42848/5418350/8716/5427065/5422707/5418350/8716`.
- Valid profile writer tags:
  `source_writer_tag(new/repeat/collision/zero)=303104/0/5123962/0`.
- Steady last-8 intervals saturated the scout table: each 60-frame interval
  had `8192` new tags, `0` repeats, and about `141k` collisions.
- Consumer-side source-local debt stayed much smaller:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=13074/13074/4356/0/13074/0/13074/0`,
  `resolve_break_blit_src=4356`, `rp_break=4356`.
- Resolve/source-base coalescing still found the useful lower-level target:
  `blit_source_calls=13074`, duplicate tags `8716`, unique floor `4358`,
  duplicate share `66.67%`, exact source-base join at `0xc0b20000`.

Reading:

- The earlier black captures are superseded as route-invalid attempts, not as
  proof the tag tooling always breaks rendering. The clean control plus clean
  profile rerun show the tooling can run on the intended field route.
- Writer-stage `write_tag` coalescing is still a bad offload point. Even with
  a fixed 8192-slot scout, each steady interval fills the table and keeps
  colliding, with no repeats seen before saturation. That gives a lower bound
  of thousands of unique producer-write tags per 60 frames, versus only about
  `37.6` source-read render-pass breaks per 60 frames at the consumer.
- The next real RSX source-local GPU experiment should attach near consumer
  demand, `memory_barrier(resolve_reason_blit_source)`, or the existing
  resolve/source-base coalescer. Do not attach producer-fill/cache work to
  `surface_store::on_write(...)` or `write_tag` events.
- This is architecture evidence only. It is not a speed win, not a new GPU
  migration credit, and not a 200% gate candidate.

Next exact step:

- Stop pursuing producer-writer tag coalescing. Prototype a verify/profile
  consumer-side source-resolve cache keyed by the exact joined source base
  (`0xc0b20000`, `1280x720`, `fmt=0x2c`, `2x`, pitch `10240`, split
  `1024/1024/512 x720`) and the consumer-side source tag/fanout shape, or
  add a narrower scout at `memory_barrier(resolve_reason_blit_source)` that
  counts cacheable source-tag reuse before doing any visible fast path.

Status: `architecture-scout`, `moving-field-profile`, `writer-tag-too-hot`,
`producer-stage-coalescing-parked`, not a `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Consumer Source-Local Fanout Analysis

Question:

- Given the valid writer-tag rerun, is the next RSX-only source-local win a
  better source-cache fanout, or must it attack the first source-layout
  render-pass break itself?

Input evidence:

- Clean valid profile run:
  `debug-captures/windows-lab/20260522-125925-cpu4-source-writer-tag-profile-rerun-after-clean-control-windows`.
- Visual checkpoints from that run were valid: load prompt, save menu, field
  start, and moving field screenshots rendered. Host grade was clean. Narrow
  error scan found no real fatal error, access violation, Vulkan validation
  failure, `VK_ERROR`, device lost marker, or unsupported image layout; the
  only `fatal` match was the normal `Show fatal error hints: false` config
  line.
- Analysis files used:
  `eternal-sonata-rsx-auditor-summary.md`,
  `eternal-sonata-rsx-source-base-join.csv`, and
  `eternal-sonata-rsx-source-local-eligibility.csv`.

Consumer shape:

- Resolve/source-base coalescing:
  `blit_source_calls=13074`, duplicate tags `8716`, unique floor `4358`,
  duplicate share `66.67%`.
- Source-local debt:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=13074/13074/4356/0/13074/0/13074/0`.
- Remaining render-pass debt:
  `resolve_break_blit_src=4356`, `rp_break=4356`, source-read share `100%`.
- The source-local eligibility CSV grouped into three source chunks, each with
  two destinations:
  `0xc0b20000 +0x0 1024x720 -> 0xc27c4080,0xc3af2100`,
  `0xc0b21000 +0x1000 1024x720 -> 0xc27c5080,0xc3af3100`,
  `0xc0b22000 +0x2000 512x720 -> 0xc27c6080,0xc3af4100`.
- Total eligible rows: `13074`, unique source shapes: `3`, destination rows:
  `6`, and all rows pass cached-dest, clean-flags, format-match, area-match,
  and non-render-target-destination gates.

Reading:

- The source-cache fanout idea is real but mostly already bounded: in the best
  shape, `13074` destination resolve/blit calls collapse to about `4358`
  source fills and `8716` fanout copies.
- The remaining render-pass breaks (`4356`) almost exactly equal the unique
  source-tag floor (`4358`). That means the speed problem is the first
  source-layout break/fill for each unique source tag, not the repeated
  destination fanout. More cache fanout tuning alone should not be the next
  speed lane.
- Existing code confirms the same shape: `resolve_blit_image_cached_source`
  fills one full-size single-sample cache image on a miss, then copies to the
  requested destinations. It can save repeated destination resolves, but a
  miss still calls `resolve_blit_image(...)` while the source is in an open
  render-pass/color layout. `defer_fill_on_renderpass_src_break` only avoids
  that cache fill by falling back to the normal visible source path, so it
  moves the break rather than removing it.

Next exact step:

- Do not tune cached-source fanout again as the primary speed experiment.
  Prototype or scout one of these Windows-only source-break removals:
  renderpass-local/subpass-style source resolve for the exact
  `0xc0b20000` split source, a pre-stage fill before the render pass opens, or
  a precise `memory_barrier(resolve_reason_blit_source)`-adjacent verifier
  that proves the first source-layout break can be moved without black
  visuals. Keep it profile/verify first, title/resource gated, and screenshot
  gated.

Status: `analysis`, `source-local-fanout-bounded`,
`first-source-break-is-target`, not a `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Consumer Source-Fused Tag Verifier

Question:

- At the exact fused blit-source candidate boundary, do hot source content tags
  repeat enough to justify a consumer-side source-stage cache or pre-stage
  fill, and does the unique tag count line up with the remaining
  source-layout render-pass breaks?

Implementation:

- Added a profile-only `source_fused_tag(new/repeat/collision/zero)` tuple in
  local `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Hook: `vk::texture_cache_traits::try_fused_blit_source_resolve(...)`, after
  the exact hot Eternal Sonata source shape passes the fused candidate gates.
- The counter is active only with the existing
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile` scout mode; normal rendering
  behavior is unchanged.
- Updated `tools/summarize_eternal_sonata_rsx_auditor.ps1` to parse the tuple
  while keeping older captures parseable.

Verification:

- Parser compatibility check succeeded on old valid capture
  `debug-captures/windows-lab/20260522-125925-cpu4-source-writer-tag-profile-rerun-after-clean-control-windows`.
- Windows build passed:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- Diff checks passed with only LF/CRLF warnings.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.

Run:

- `debug-captures/windows-lab/20260522-134633-cpu4-source-fused-tag-profile-movingloop-windows`
  used the same delayed-confirm moving-field macro, PadApi,
  `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank `240`,
  `FastSampled`, `DepthReadOnly`, `KeepReadOnly`, `GpuSwap`, host DMA fence,
  persistent vertex/index fast caches, resolve profile, and
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- Host contention stayed clean across `5` snapshots. RPCS3 was moved to
  `\\.\DISPLAY2`.
- Visuals were valid for this architecture scout:
  `screenshot-0104s-loadconfirm.png` showed the `Load complete` prompt,
  `screenshot-0115s-maybe-save-menu.png` showed the save prompt over the
  field, and `screenshot-0126s-move1.png` / `screenshot-0148s-late.png`
  showed unobstructed Path to Tenuto movement.
- Narrow error scan found no real fatal error, access violation, Vulkan
  validation failure, `VK_ERROR`, device lost marker, unsupported image layout,
  or crash marker. The env var was removed after the run and no `rpcs3`
  process was left running.

Counters:

- `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=12894/12894/4296/0/12894/0/12894/0`.
- New tag verifier:
  `source_fused_tag(new/repeat/collision/zero)=4298/8596/0/0`.
- Remaining source-layout debt:
  `resolve_break_blit_src=4296`, `rp_break=4296`.
- Resolve coalescing scout:
  `blit_source_calls=12894`, `duplicate_tags=8596`, `unique_tag_floor=4298`,
  duplicate share `66.67%`.
- Source-base join stayed exact:
  `matched=12894/12894`, source breaks per unique percent `99.95%`, hot base
  `0xc0b20000`.

Reading:

- This directly confirms the earlier fanout analysis: source content tags
  repeat cleanly at the consumer boundary, with no scout collisions, and the
  unique fused-tag count almost exactly equals the render-pass source-break
  count.
- The useful work is not destination fanout and not producer writes. The target
  is the first source-tag fill/layout transition for the exact hot source.
- This is architecture evidence only. It is not a speed win, not a new
  `gpu-migration-credit`, and not a 200% gate candidate.

Next exact step:

- Prototype a Windows-only verify/profile renderpass-local or pre-stage source
  fill keyed by the exact hot source tag and source shape. The first acceptance
  signal is reduced `resolve_break_blit_src` against the same moving-field
  route with correct load, save prompt, moving field, menu/Options, and first
  battle visuals before any Thor port.

Status: `architecture-scout`, `moving-field-profile`,
`consumer-source-tags-coalesce`, `first-source-break-is-target`, not a
`gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Source-Read Rebind Static Gate

Question:

- After the clean fused-tag verifier proved the first source-tag fill/layout
  break is the target, can we safely retry a sampled keep-read/source-local
  path, or must the render-target rebind path be changed first?

Static Windows-lab code scout:

- Inspected only
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- No Android, ADB, Thor build, Thor deploy, device capture, or Windows gameplay
  capture was performed in this slice.
- `AGENTS.md` already records the failed `FastSampledKeepSrc` run
  `20260519-210056-rsx-blitsource-sampled-keepsrc-field-windows-windows`:
  black field, `fast=0`, and an RSX freeze at `Unsupported image layout 0x5`.
- `rpcs3/Emu/RSX/VK/VKRenderPass.cpp` encodes render-pass attachment layouts
  in `renderpass_key_blob::set_layout(...)`, but it only accepts
  `GENERAL`, `COLOR_ATTACHMENT_OPTIMAL`, `DEPTH_STENCIL_ATTACHMENT_OPTIMAL`,
  and `ATTACHMENT_FEEDBACK_LOOP_OPTIMAL_EXT`. A real color render target left
  in `SHADER_READ_ONLY_OPTIMAL` cannot currently be encoded as an attachment
  render-pass key.
- `rpcs3/Emu/RSX/VK/VKRenderTargets.h::prepare_surface_for_drawing(...)`
  explicitly transitions color render targets back to
  `COLOR_ATTACHMENT_OPTIMAL` before drawing, and then resets surface counters.
- `rpcs3/Emu/RSX/VK/VKResolveHelper.cpp::resolve_blit_image(...)` sets the
  sampled source read layout to `SHADER_READ_ONLY_OPTIMAL` only around the
  compute resolve/blit. For the sampled path it restores the source to the
  original attachment layout unless it was already readable at entry.
- `rpcs3/Emu/RSX/VK/VKDraw.cpp::invalidate_render_pass(...)` regenerates the
  render-pass key from the current `m_fbo_images` layouts after layout changes,
  so a keep-read experiment cannot just leave the real source in shader-read
  state and hope the next draw silently fixes it.

Reading:

- The old `FastSampledKeepSrc` failure is explained by the current rebind
  contract, not by a one-off route flake. The sampled source layout
  `0x5` is useful for the compute read, but illegal for the current attachment
  render-pass key path.
- A safe source-break experiment has two viable shapes:
  - fill a separate cache/scratch image from the hot source tag, then restore
    the real MSAA render target to attachment layout before any later rebind;
  - add an explicit verifier around render-target rebind/render-pass-key
    legalization before any path leaves the real target readable across draws.
- Do not re-add a plain sampled keep-read/source-local toggle. It would repeat
  the known layout failure and is not a new speed lane.

Next exact step:

- Build a profile/verify-only source-break verifier at the consumer boundary:
  for the exact hot source tag and shape, log whether a separate cache/scratch
  fill can be completed before the dependent render pass opens, while the real
  render target is restored to `COLOR_ATTACHMENT_OPTIMAL` before the next
  `prepare_surface_for_drawing(...)` / render-pass-key bind. Acceptance starts
  with lower `resolve_break_blit_src` on the same delayed-confirm moving-field
  route and correct field/menu/first-battle visuals.

Status: `analysis`, `source-read-rebind-gate`,
`keep-read-retry-blocked-by-layout-legalization`, not a
`gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Begin-Render-Pass Source Prefill Scout

Question:

- If the first source-tag fill/layout transition is the remaining hot RSX
  debt, can `VKGSRender::begin_render_pass()` see the exact hot source early
  enough to prefill a separate cached source before the dependent render pass
  starts?

Implementation:

- Added profile-only counters in local
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Hook:
  `rpcs3/Emu/RSX/VK/VKDraw.cpp::VKGSRender::begin_render_pass()`.
- New auditor tuple:
  `source_prefill_begin(call/rp/bound/hot/resolve/tagdirty)`.
- The hook counts calls, whether a render pass was already open, bound render
  targets, exact Eternal Sonata hot-source matches, matches requiring resolve,
  and matches whose write tag differed from the last resolve tag.
- Updated `tools/summarize_eternal_sonata_rsx_auditor.ps1` to parse the new
  optional tuple while keeping older captures parseable.
- After the failed fast scout below, the actual natural-close prefill call in
  `VKGSRender::close_render_pass()` was removed. Begin/natural-close prefill is
  now a profile-only scout until a better insertion point is found.

Verification:

- Parser compatibility check succeeded on the prior good moving run
  `debug-captures/windows-lab/20260522-134633-cpu4-source-fused-tag-profile-movingloop-windows`.
- Windows build passed before the scout:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`.
- Windows build passed again after removing the actual natural-close prefill
  call, so the kept state is buildable and profile-only.
- Diff checks passed with only LF/CRLF warnings.
- No Android, ADB, Thor build, Thor deploy, or Thor capture was performed.

Fast scout:

- `debug-captures/windows-lab/20260522-141642-cpu4-begin-prefill-fastcachedsampled-movingloop-windows`
  used the delayed-confirm moving macro, PadApi, `-WindowsGameScreen 1`, CPU
  affinity `0x0F`, frame/vblank `240`, `FastCachedSampled`, the current RSX
  stack, and `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=prefill`.
- Result: failed. Screenshots were black with overlay and the RPCS3 crash
  message. The log/stderr reported a PPU access violation reading `0x4` around
  `0:00:49.966840`, then emulation froze.
- No useful hot-source prefill occurred before the crash:
  `source_prefill_begin(call/rp/bound/hot/resolve/tagdirty)=87850/76164/87850/0/0/0`,
  `blit-source fused fast=0`, cache activity `0`.
- Classification: `failed`, `visual-black`, `ppu-access-violation`,
  `not-comparable`. It is not a speed win, not `gpu-migration-credit`, and not
  a 200% gate candidate.

Profile-only scout:

- `debug-captures/windows-lab/20260522-142049-cpu4-begin-prefill-profile-fastsampled-movingloop-windows`
  used the same macro and stack, but `FastSampled` plus
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- Narrow error scan found no fatal error, access violation, Vulkan validation
  failure, `VK_ERROR`, device-lost marker, unsupported image layout, or crash
  marker.
- Visual route was not comparable: `screenshot-0104s-loadconfirm.png` showed
  the story line "So, once more, a new journey begins.", and later screenshots
  stayed in star/cutscene visuals instead of Path to Tenuto moving gameplay.
- Useful counters:
  `source_prefill_begin(call/rp/bound/hot/resolve/tagdirty)=4713591/4638628/4713591/4134150/4134150/4131348`.
- The same run still showed the consumer source debt shape:
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=8406/8406/2801/0/8406/0/8406/0`,
  `source_fused_tag(new/repeat/collision/zero)=2802/5604/0/0`,
  `resolve_break_blit_src=2801`, `rp_break=2801`.

Reading:

- `begin_render_pass()` is not the precise speed insertion point. It is called
  millions of times in this route and is usually already observing an open
  render pass, so a naive prefill there would be noisy and late.
- The actual fast scout crashed before proving any useful hot-source work.
  Keep the hook profile-only and parked.
- The source-break target remains the first hot source-tag fill/layout
  transition, but the next implementation should be either true
  renderpass-local/local-read plumbing or a narrow
  `memory_barrier(resolve_reason_blit_source)`-adjacent verifier. Do not keep
  retrying `begin_render_pass()` or natural `close_render_pass()` prefill.

Status: `failed-fast-scout`, `route-mismatched-profile-scout`,
`begin-prefill-parked`, `source-break-target-unchanged`, not a
`gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Preserve-Renderpass Source Barrier Static Gate

Question:

- Can the remaining `resolve_break_blit_src` debt be attacked with a narrow
  verifier that simply sets `preserve_renderpass=true` on the fused
  blit-source source-layout barrier, or would that be illegal with the current
  compute resolve/blit path?

Static Windows-lab code scout:

- Inspected only
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- No Android, ADB, Thor build, Thor deploy, device capture, or Windows gameplay
  capture was performed in this slice.
- The clean reference capture remains
  `debug-captures/windows-lab/20260522-134633-cpu4-source-fused-tag-profile-movingloop-windows`.
  It stayed on `\\.\DISPLAY2`, host contention was clean across `5` snapshots,
  and screenshots included `screenshot-0104s-loadconfirm.png`,
  `screenshot-0115s-maybe-save-menu.png`, `screenshot-0117s-start.png`,
  `screenshot-0126s-move1.png`, `screenshot-0136s-move2.png`, and
  `screenshot-0148s-late.png`.
- That reference capture's counters remain the acceptance target:
  source-local debt class `source-layout-renderpass-bound`,
  `resolve_break_blit_src=4296`, source-read share `100.00%`,
  `blit_source_calls=12894`, `duplicate_tags=8596`,
  `unique_tag_floor=4298`, and
  `source_fused_tag(new/repeat/collision/zero)=4298/8596/0/0`.
- `rpcs3/Emu/RSX/VK/vkutils/barriers.cpp::insert_image_memory_barrier(...)`
  uses `preserve_renderpass` only to decide whether to call
  `vk::end_renderpass(cmd)` before `vkCmdPipelineBarrier(...)`. It does not
  transform the operation into renderpass-local graphics work.
- `rpcs3/Emu/RSX/VK/VKResolveHelper.cpp::resolve_blit_image(...)` records the
  `blit_src_to_general` source barrier and then runs
  `cs_resolve_blit_task::run(...)`.
- `cs_resolve_blit_task` inherits `compute_task`, and the Vulkan compute path
  dispatches through `vkCmdDispatch(...)`.
- The active render pass is begun through
  `vkCmdBeginRenderPass(..., VK_SUBPASS_CONTENTS_INLINE)`, so leaving it open
  and then trying to run the current compute resolve/blit is not the legal
  renderpass-local source-read design this lane needs.
- `VKRenderPass.cpp` already has render-pass key support for input attachment
  ids, but the current fused blit-source path does not use it. It is not wired
  to read the hot MSAA color source as a legal graphics subpass/input
  attachment replacement for the compute resolve/blit.

Reading:

- A one-line `preserve_renderpass=true` verifier would be a trap: it could
  reduce the counter by avoiding the explicit end-renderpass call, but it would
  leave the code trying to perform compute resolve/blit work while the graphics
  render pass is still open.
- The next valid source-break experiment must change architecture, not just the
  barrier flag:
  - pre-stage a separate scratch/cache source before the dependent render pass
    opens, while restoring the real render target to attachment layout; or
  - build a real graphics/renderpass-local path, likely input-attachment or
    subpass-feedback plumbing for the exact hot source shape, with verification
    before fast mode.
- Acceptance remains lower `resolve_break_blit_src` on the delayed-confirm
  moving-field route with clean load, field, menu/Options, and first-battle
  visuals. This static gate is not a speed result.

Status: `analysis`, `preserve-renderpass-flag-rejected`,
`source-break-target-unchanged`, not a `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Input-Attachment Source-Local Static Gate

Question:

- Since a compute dispatch cannot legally run inside the open graphics render
  pass, can the hot source-read lane be converted with a small
  input-attachment/render-pass-key patch, or is the fused path writing a
  texture-cache destination outside the current framebuffer?

Static Windows-lab code and CSV scout:

- Inspected only
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` and the
  existing Windows reference capture
  `debug-captures/windows-lab/20260522-134633-cpu4-source-fused-tag-profile-movingloop-windows`.
- No Android, ADB, Thor build, Thor deploy, device capture, Windows gameplay
  capture, or emulator rebuild was performed in this slice.
- Reference capture stayed on `\\.\DISPLAY2`, host contention was clean, and
  its source-local debt remains the target:
  `resolve_break_blit_src=4296`, `blit_source_calls=12894`,
  `duplicate_tags=8596`, `unique_tag_floor=4298`.
- `eternal-sonata-rsx-source-local-eligibility.csv` contains exactly six hot
  source-local rows totaling `12894` calls:
  - `0xc0b20000 -> 0xc27c4080` and `0xc0b20000 -> 0xc3af2100`;
  - `0xc0b21000 -> 0xc27c5080` and `0xc0b21000 -> 0xc3af3100`;
  - `0xc0b22000 -> 0xc27c6080` and `0xc0b22000 -> 0xc3af4100`.
- All six rows are `cached_dest=True`, `dst_render_target=False`,
  `clean_flags=True`, `format_match=True`, `area_match=True`, and
  `candidate=True`.
- Static path:
  `VKGSRender::scaled_image_from_memory(...)` calls `m_texture_cache.blit(...)`;
  the common texture-cache path then enters
  `traits::try_fused_blit_source_resolve(...)` and eventually
  `resolve_blit_image(...)`.
- `VKRenderPass.cpp` has a `get_renderpass_key(images, input_attachment_ids)`
  overload and stores an `input_attachments_mask`, but the normal draw path
  builds `m_current_renderpass_key` from `m_fbo_images` without input ids.
- The current hot destination images are texture-cache/cached destinations, not
  current framebuffer attachments, so adding input attachment ids to the
  current FBO key would not by itself provide the destination write or replace
  the texture-cache blit.

Reading:

- A small input-attachment/render-pass-key patch is not a valid next speed
  experiment. It would wire a capability the hot fused path does not currently
  consume, while the real operation still needs to create/update texture-cache
  destination images.
- There are still two plausible RSX source-break lanes:
  - pre-stage a separate scratch/cache fill before the dependent render pass
    opens, then let the existing texture-cache destination fanout read from
    that source without breaking the pass; or
  - build deeper shader/texture-cache plumbing that substitutes the current
    texture-cache blit with a legal graphics/renderpass-local read for the
    exact hot source shape.
- This static gate narrows the next executable implementation toward pre-pass
  scratch/cache fill or deeper shader plumbing. It is not a speed result and
  not a GPU migration credit.

Status: `analysis`, `input-attachment-small-patch-rejected`,
`source-break-target-unchanged`, not a `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 First-Use Source Tag Correlation

Question:

- Does the clean moving profile already contain a non-renderpass consumer use
  of each hot source tag before the breaking renderpass-open use, or is the
  first tag use itself the source-read render-pass break?

Existing-capture analysis:

- Used only
  `debug-captures/windows-lab/20260522-134633-cpu4-source-fused-tag-profile-movingloop-windows`.
- No Android, ADB, Thor build, Thor deploy, device capture, Windows gameplay
  capture, code edit, or emulator rebuild was performed in this slice.
- Aggregated `eternal-sonata-rsx-auditor-records.csv` rows where
  `source_fused_state_hot > 0`.
- Totals:
  `source_fused_state_hot=12894`,
  `source_fused_state_rp=4296`,
  `source_fused_tag_new=4298`,
  `source_fused_tag_repeat=8596`,
  `resolve_break_blit_src=4296`.
- Interval correlation:
  - first hot interval: `hot=294`, `rp=96`, `new=98`, `repeat=196`,
    `break=96`;
  - every later hot 60-frame interval: `hot=360`, `rp=120`, `new=120`,
    `repeat=240`, `break=120`.
- Grouping by deltas showed `35` steady intervals with
  `new - break = 0` and `rp - break = 0`; only the startup interval had
  `new - break = 2`.

Reading:

- In steady moving field, the first consumer use of each hot source tag is the
  renderpass-open source-read break. The two later repeated consumer uses are
  cache/fanout opportunities, but they happen after the first break has already
  been paid.
- This rejects a cheap plan that waits for an earlier non-RP consumer repeat to
  prefill the source cache. Existing consumer timing does not expose one.
- A pre-stage path must get its signal before this first consumer use, probably
  from a coalesced producer/source-tag publication point or from explicit
  scheduling before the dependent render pass opens.
- A renderpass-local path still needs deeper shader/texture-cache plumbing.
  Merely improving destination fanout or using input-attachment key bits will
  not remove the first-use break.

Status: `analysis`, `first-use-is-breaking-use`,
`consumer-repeat-prefill-rejected`, `source-break-target-unchanged`, not a
`gpu-migration-credit`, not a `windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Producer-Prestage Source Signal Static Gate

Question:

- If the first consumer use of each hot source tag is already the
  render-pass-breaking use, is there an existing producer-side or texture-cache
  hook that can safely pre-stage the hot MSAA source before that first consumer
  blit?

Static Windows-lab code scout:

- Inspected only
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` and the
  existing clean moving capture
  `debug-captures/windows-lab/20260522-134633-cpu4-source-fused-tag-profile-movingloop-windows`.
- No Android, ADB, Thor build, Thor deploy, device capture, Windows gameplay
  capture, code edit, or emulator rebuild was performed in this slice.
- Reference evidence remains valid: the run stayed on `\\.\DISPLAY2`, host
  contention was clean, field/load/menu/movement screenshots were present, and
  source debt was `resolve_break_blit_src=4296` with
  `source_fused_tag(new/repeat/collision/zero)=4298/8596/0/0`.
- `rpcs3/Emu/RSX/Common/surface_store.h::on_write(...)` runs per draw for
  bound render targets, gets `write_tag = rsx::get_shared_tag()`, records
  source-writer state, then calls `surface->on_write_fast(write_tag)` or
  `surface->on_write(...)`.
- `rpcs3/Emu/RSX/Common/surface_utils.h::on_write_fast(...)` only updates
  `last_use_tag` and marks MSAA surfaces as `require_resolve`.
- Earlier valid writer profile
  `20260522-125925-cpu4-source-writer-tag-profile-rerun-after-clean-control-windows`
  already showed this producer hook is much too hot: `5,427,066` hot writer
  hits, `303,104` new writer tags, `0` repeats, and `5,123,962` tag-table
  collisions, versus about `4,298` useful consumer source tags in the clean
  fused-tag run.
- `rpcs3/Emu/RSX/Common/texture_cache.h::lock_memory_region(...)` attaches the
  active framebuffer-storage cache section around FBO binding/use. It creates
  or reuses a locked section, marks it `framebuffer_storage`, sets dirty false,
  touches the cache tag, and optionally adds it to flush-always tracking. It
  does not resolve/fill completed MSAA content into the fused blit-source cache.
- `flush_if_cache_miss_likely(...)` can call `region.copy_texture(...)`, but
  that path is speculative CPU/Cell-memory synchronization for flush misses,
  not the exact hot GPU source-cache prefill we need.
- `prepare_rtts(...)` locks current draw surfaces and commits/locks orphaned
  surfaces, but the earlier `close_render_pass()` prefill scout saw zero hot
  natural-close targets, and the begin-render-pass scout was too hot/late.

Reading:

- There is no existing cheap producer-side hook that can become a fast prefill
  path by just adding the cached-source resolve call.
- The producer write hook is too hot, the texture-cache FBO lock is too early
  and metadata-oriented, and the consumer first use is already the breaking
  use.
- A valid pre-stage implementation needs a new verifier first: prove a
  coalesced moment where the exact hot source tag is final and the dependent
  consumer blit has not yet opened/broken a render pass. Candidate probes:
  source unbind/orphan transition, framebuffer layout switch for the hot base,
  or a queue that records final hot source tags and checks whether they can be
  safely resolved before the next draw pass begins.
- If that verifier cannot find such a moment, the RSX source-break lane should
  stop chasing prefill hooks and pivot to deeper shader/texture-cache plumbing
  or back to SPU/PPU codegen/HLE around the known hot blocks.

Status: `analysis`, `producer-prestage-cheap-hook-rejected`,
`needs-new-coalesced-prestage-verifier`, not a `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Framebuffer-Transition Source Prestage Verifier

Question:

- Does the framebuffer transition in `VKGSRender::prepare_rtts()` expose a
  coalesced moment where old hot Eternal Sonata MSAA source targets are retired,
  still unresolved/tag-dirty, and not yet inside the dependent render pass?

Implementation:

- Windows-only local `rpcs3-upstream` instrumentation added profile-only
  `source_transition(check/hot/retire/rp/resolve/tagdirty)` to
  `vkutils/rsx_auditor.h`.
- The probe runs only for `BLUS30161` when the RSX auditor is enabled and
  `RPCS3_ES_RSX_SOURCE_PREFILL_PROFILE=profile`.
- `VKGSRender::prepare_rtts()` now inspects previously bound color targets
  before `m_rtts.prepare_render_target(...)` and matches the exact hot source
  shape:
  `base=0xc0b20000/0xc0b21000/0xc0b22000`, `1280x720`,
  `pitch=10240`, `VK_FORMAT_B8G8R8A8_UNORM`, `samples=2`, `grid=2x1`.
- The Android/Thor device was not touched. No ADB, Thor build, Thor deploy, or
  Android capture was run.

Build and run:

- Build:
  `cmake --build .\build-msvc --config Release --target rpcs3 --parallel 6`
  in `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Build result: passed.
- Run:
  `debug-captures/windows-lab/20260522-151821-cpu4-source-transition-profile-movingloop-windows`.
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA fence +
  persistent vertex/index fast caches + Resolve Profile + RSX auditor 60`.
- Route:
  delayed-confirm moving-field macro, PadApi, `-WindowsGameScreen 1`, CPU
  affinity `0x0F`, frame/vblank `240`, `MaxSeconds 205`.
- Host:
  pre/post clean, one moderate CPU sample during the moving window, no competing
  emulator.

Visual/log verification:

- RPCS3 was moved to `\\.\DISPLAY2`.
- Screenshots:
  `screenshots/screenshot-0104s-loadconfirm.png`,
  `screenshots/screenshot-0115s-maybe-save-menu.png`,
  `screenshots/screenshot-0117s-start.png`,
  `screenshots/screenshot-0126s-move1.png`,
  `screenshots/screenshot-0136s-move2.png`,
  `screenshots/screenshot-0148s-late.png`.
- Visual read:
  load prompt, save prompt, field start, and late moving field looked correct.
- Error scan:
  no fatal, access violation, `VK_ERROR`, device-lost, validation, or
  unsupported-layout hit. The remaining `failed` lines were ordinary game/syscall
  save-data or LV2 noise already seen in prior clean routes.

Counters:

- Auditor frames:
  `7680`.
- Source-local debt stayed:
  `source-layout-renderpass-bound`.
- Remaining render-pass break debt:
  `resolve_break_blit_src=6052` (`47.28` per 60 frames).
- Fused sampled-MSAA GPU resolve/blit:
  `blit_resolve_path(storage_fast/sampled_fast/storage_verify/sampled_verify)=0/18162/0/0`.
- Source tag reuse:
  `source_fused_tag(new/repeat/collision/zero)=6054/12108/0/0`.
- New transition verifier:
  `source_transition(check/hot/retire/rp/resolve/tagdirty)=53913/12108/9081/12108/12108/12108`.
- Per-60 transition rates:
  `check=421.20`, `hot=94.59`, `retire=70.95`,
  `rp=94.59`, `resolve=94.59`, `tagdirty=94.59`.

Reading:

- The hook sees real hot retired targets, so the probe is hitting the right
  source family.
- It fails the important pre-stage condition: every hot transition is already
  render-pass-open (`rp == hot`), while all hot entries still require resolve
  and are tag-dirty.
- That means a fast path here would still have to end or disturb the active
  render pass before doing the current compute/sample resolve. It is not the
  clean before-pass window needed to remove `blit_src_to_general` debt.
- Do not promote this to a fast source-prefill implementation.
- The next RSX source-break lane should be real renderpass-local/local-read
  shader plumbing for the texture-cache destination path, or an even narrower
  scheduling verifier at the exact `resolve_reason_blit_source` boundary.
- If that also fails, pivot back to SPU/PPU codegen/HLE around hot PCs
  `0x25cc` / `0x451c` rather than adding more late RSX cache fanout work.

Status: `analysis`, `framebuffer-transition-prestage-rejected`,
`source-break-target-unchanged`, not a `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.

## 2026-05-22 Renderpass-Local Source-Read Static Gate

Question:

- After the cheap pre-stage hooks failed, can the hot fused blit-source path be
  made renderpass-local with a small render-pass-key/input-attachment change, or
  does it require a real graphics/subpass helper?

Static Windows-lab code scout:

- Inspected only local Windows source in
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Reused the latest valid moving-field evidence from
  `debug-captures/windows-lab/20260522-151821-cpu4-source-transition-profile-movingloop-windows`.
- No Android, ADB, Thor build, Thor deploy, device capture, Windows gameplay
  capture, emulator rebuild, or fast-path code change was performed in this
  slice.

Evidence:

- Latest moving profile remained visually/log clean and kept the target debt:
  `resolve_break_blit_src=6052`, `source_fused_tag(new/repeat)=6054/12108`,
  and source-local debt class `source-layout-renderpass-bound`.
- Latest source-local eligibility still says the hot rows are cached
  destinations, not render targets:
  `Fully eligible rows=18162`, `cached_dest=100%`,
  `dst_render_target=False`.
- `VKTextureCache.h::try_fused_blit_source_resolve(...)` dispatches into
  `vk::resolve_blit_image(...)` for the fast path.
- `VKResolveHelper.cpp::resolve_blit_image(...)` is compute-based:
  it uses `cs_resolve_blit_task`, binds the MSAA source as
  `sampler2DMS`/`image2DMS`, binds the destination as `writeonly image2D`, and
  then runs `compute_task::run(...)`, which records `vkCmdDispatch(...)`.
- The same function explicitly transitions the source from
  `COLOR_ATTACHMENT_OPTIMAL` to `SHADER_READ_ONLY_OPTIMAL` for sampled mode, or
  to `GENERAL` for storage-image mode. That transition is the measured
  `blit_src_to_general` render-pass break.
- `VKRenderPass.cpp` can encode input attachments in the render-pass key, but
  the current draw path builds `m_current_renderpass_key` from `m_fbo_images`
  without input ids, and the hot texture-cache destination image is not an FBO
  attachment.
- The latest run's RPCS3 log confirms the Windows RTX 3060 path exposes
  `VK_EXT_attachment_feedback_loop_layout`, and the render target creation path
  can add `VK_IMAGE_USAGE_ATTACHMENT_FEEDBACK_LOOP_BIT_EXT`. That is a capability
  signal, not an implementation: current source-fused counters still show
  `source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)=18162/18162/6052/0/18162/0/18162/0`.

Reading:

- A small render-pass-key or input-attachment-id tweak is not enough. It would
  not replace the compute dispatch and would not give the texture-cache
  destination image a legal in-pass write path.
- A legal renderpass-local replacement would need a new graphics/subpass helper,
  probably overlay/pass-like infrastructure, that:
  - runs as graphics while the dependent render pass is open;
  - reads the active hot MSAA attachment through feedback-loop or input-attachment
    semantics without changing it to shader-read/general layout;
  - writes the texture-cache `blit_engine_dst` destination without ending the
    active pass, likely via an attachment-compatible route or fragment storage
    image if the pipeline/renderpass constraints allow it;
  - verifies output against the existing compute `FastSampled` path before any
    fast visible path.
- This is now an architecture task, not a switch hunt. If we continue RSX here,
  the next implementation should be a verify-only graphics helper/scratch
  prototype, not another cache fanout, defer, keep-source, transition, or
  input-id toggle.
- Given cost/risk, it is also reasonable to pivot the next loop to SPU/PPU
  codegen/HLE around known hot PCs `0x25cc` / `0x451c`, where the scouts found
  real CPU-bound work but no RSX-local GPU batch lane.

Status: `analysis`, `renderpass-local-small-patch-rejected`,
`graphics-helper-required-or-pivot-spu`, not a `gpu-migration-credit`, not a
`windows-micro-win`, not a 200% gate candidate.
