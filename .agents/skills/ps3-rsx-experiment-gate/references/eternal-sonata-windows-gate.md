# Eternal Sonata Windows RSX/GPU Gate

Use this reference when the task is to get more RPCS3/RPCSX work onto GPU while the project is still Windows-only.

## Current Standing Rule

- Platform: Windows lab only.
- Game: Eternal Sonata `BLUS30161`.
- Required display target: second screen, `-WindowsGameScreen 1`.
- Required promotion bar: stable 200% or better moving-gameplay performance improvement with correct field, menu/Options, and first-battle visuals.
- Android/Thor work: parked until the promotion bar is met or the user explicitly reopens Android work.

## Current RSX-Local Stack

Use this stack as the current known-good RSX-local residency foothold:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -WindowsInputBackend PadApi `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve FastSampled `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxPresentUpload GpuSwap `
  -WindowsRsxDmaFence Host `
  -WindowsRsxAuditor 60 `
  -WindowsGameScreen 1
```

Known proof as of 2026-05-19:

- Options route `debug-captures/windows-lab/20260519-161410-rsx-padapi-options-depthreadonly-fast-keepfeedback-windows-windows/` reached a clean full Options page and logged about `251` RSX-local credit events per 60 frames.
- Field route `debug-captures/windows-lab/20260519-162400-rsx-field-depthreadonly-fast-keepfeedback-windows-windows/` kept field visuals clean and logged about `400` RSX-local credit events per 60 frames.
- Battle route `debug-captures/windows-lab/20260519-170902-rsx-battle-padapi-left-downleft-keepfeedback-retry-windows/` reached the tutorial prompt at `screenshot-0187s.png` and active first-battle UI at `screenshot-0248s.png` / `screenshot-0309s.png`, with clean-looking battle visuals and about `455` RSX-local credit events per 60 frames.
- New host-DMA triad route with `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host`:
  field `debug-captures/windows-lab/20260519-222018-rsx-hostdma-fastsampled-field-windows-windows/`,
  first battle `debug-captures/windows-lab/20260519-222407-rsx-hostdma-fastsampled-battle-windows-windows/`,
  and menu/pause `debug-captures/windows-lab/20260519-223044-rsx-hostdma-fastsampled-menu-windows-windows/`
  all rendered cleanly. The DMA fence split moved to `all=0 / host=15` in field,
  `all=0 / host=74` in battle, and `all=0 / host=15` in menu. Treat this as
  Windows `gpu-migration-credit`/sync narrowing, not a speed proof.

## Optional Sampled Blit-Source Resolve

Use `-WindowsRsxBlitSourceResolve VerifySampled` for scratch-only proof, then
`-WindowsRsxBlitSourceResolve FastSampled` only after the shader compiles and
the route is visually checked. The wrapper maps these to
`RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE=verify-sampled|fast-sampled`.

The sampled variant keeps the same fused resolve/blit role as `Fast`, but reads
the MSAA source through `sampler2DMS` in `SHADER_READ_ONLY_OPTIMAL` instead of a
storage image in `GENERAL`. This is a cleaner GPU-read shape for later
mobile/tile-local research, but it does not solve the render-pass break by
itself.

Proof as of 2026-05-19 with `DepthReadOnly + FastSampled + KeepReadOnly +
GpuSwap`:

- Scratch verify field
  `debug-captures/windows-lab/20260519-195434-rsx-blitsource-sampled-verify-field-windows-windows/`
  reached clean Path to Tenuto field visuals and logged `3,976` verify
  dispatches.
- Fast field
  `debug-captures/windows-lab/20260519-195808-rsx-blitsource-sampled-fast-field-windows-windows/`
  reached clean field visuals and logged `12,324` fast dispatches.
- Fast Options/menu
  `debug-captures/windows-lab/20260519-200154-rsx-blitsource-sampled-fast-menu-windows-windows/`
  reached a clean full Options page and logged `7,815` fast dispatches.
- Fast first battle
  `debug-captures/windows-lab/20260519-200516-rsx-blitsource-sampled-fast-battle-windows-windows/`
  reached clean active first-battle UI and logged `6,570` fast dispatches.
- Counter split follow-up
  `debug-captures/windows-lab/20260519-202952-rsx-blitsource-sampled-counter-field-windows-windows/`
  reached clean field visuals and logged
  `blit_resolve_path(storage_fast/sampled_fast/storage_verify/sampled_verify)=0/12282/0/0`,
  proving the optional path used sampled-MSAA reads rather than hiding inside
  the aggregate fast counter.

Decision: `FastSampled` is a valid Windows `gpu-migration-credit` variant, not
a default speed stack and not a Thor port candidate. It still leaves the
source-layout render-pass break debt, so the next big RSX idea remains true
renderpass-local/tile-local resolve/blit architecture.

Rejected follow-up: a temporary `FastSampledKeepSrc` probe attempted to keep
the sampled source in `SHADER_READ_ONLY_OPTIMAL` between fused chunks. Run
`debug-captures/windows-lab/20260519-210056-rsx-blitsource-sampled-keepsrc-field-windows-windows/`
went black, logged zero fused dispatches, and froze with
`Unsupported image layout 0x5`. The switch was removed; do not use sampled
keep-source as a shortcut for the renderpass-local architecture.

## Latest Kernel/GPU Scout

Battle scout
`debug-captures/windows-lab/20260519-211905-kernel-capsule-gpu-scout-battle-windows-windows/`
used `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap` plus
`-EternalSonataKernelCapsule Profile -EternalSonataGpuProbe Profile` and reached
clean active first-battle visuals. It logged `2586` GPU/DMA candidate rows,
`3,641.99 MB` observed DMA, `0 B` direct RSX-local traffic, `0` indirect RSX
overlap records, and offload fit `spu-kernel-hle=2057` / `too-small=529`.
Kernel capsule classification was all `reservation-risk` (`3141` rows), with
`0` gpu-batch candidates and hot PCs `0x25cc` / `0x451c`.

Decision: this is not a GPU compute promotion lane. Keep moving RSX-local work
through renderpass-local/tile-local architecture and GPU-resident uploads, and
treat the hot SPU jobs as HLE/codegen/reduced-loop candidates until a future
trace proves batched RSX-consumed data.

## Current RSX Architecture Candidate

Field scout
`debug-captures/windows-lab/20260519-214153-rsx-blitsource-profile-fastsampled-field-windows-windows/`
used `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Resolve Profile`
and reached clean field visuals. The RSX summarizer's `Resolve Coalescing Scout`
reported `12960` profiled blit-source resolve calls, `8640` duplicate source-tag
calls, a `4320` unique source-tag floor, and `25` blit-source profile keys. The
hot source is the same `1280x720`, 2x MSAA, `0xc0b20000` color target seen in
earlier resolve work.

Decision: the next RSX GPU experiment should be a verify-first source-resolve
cache/coalescer, not another source-layout keep shortcut. Resolve the repeated
MSAA source once per content tag into a GPU-resident single-sample image, then
fan out destination blits/copies. Never drop destination writes just because the
source tag repeats.

First cached-source attempt:
`debug-captures/windows-lab/20260519-221519-rsx-blitsource-verifycachedsampled-field-v2-windows-windows/`
used `VerifyCachedSampled` and reached clean field visuals after a layout fix,
but the cache counters were `hit/miss/fill/fanout/reject=0/4376/4376/4376/0`.

Fast cached-source triad:
`FastCachedSampled` plus `DepthReadOnly + KeepReadOnly + GpuSwap + Host` reached
clean field, menu/pause, and first-battle visuals in
`20260519-223810-rsx-blitsource-fastcachedsampled-field-windows-windows`,
`20260519-224209-rsx-blitsource-fastcachedsampled-menu-windows-windows`, and
`20260519-224632-rsx-blitsource-fastcachedsampled-battle-windows-windows`.
Cache counters matched the repeated-source scout:

- field: `hit/miss/fill/fanout/reject=8644/4322/4322/12966/0`;
- menu/pause: `11104/5552/5552/16656/0`;
- battle: `4372/2186/2186/6558/0`.

Decision: `FastCachedSampled` is now a Windows RSX `gpu-migration-credit`
candidate. It is not a 200% speed proof and still leaves the first
`blit_src_to_general` break per source tag, so compare it against `FastSampled`
in matched uncapped Windows movement before treating it as a micro-win.

## Optional Present-Upload GPU Swap

Use `-WindowsRsxPresentUpload GpuSwap` only when testing the opt-in fallback
present-upload path. The wrapper maps it to
`RPCS3_ES_RSX_PRESENT_UPLOAD=gpu-swap`; default `Off` keeps the CPU row
conversion path.

This moves the 32-bit fallback present-upload endian swap from a CPU row loop
to the existing Vulkan upload/GPU shuffle path for Eternal Sonata's matching
`B8G8R8A8` present upload. It is a small `gpu-migration-credit`, not a speed
claim.

Proof as of 2026-05-19:

- Menu/Options proof
  `debug-captures/windows-lab/20260519-190002-rsx-present-gpuswap-field-windows-windows/`
  reached a clean title Options page and logged
  `present_upload(cpu/gpu)=0/1`, `present_upload_bytes(cpu/gpu)=0/3686400`.
- Field proof
  `debug-captures/windows-lab/20260519-190656-rsx-present-gpuswap-field-ps3native-windows-windows/`
  reached clean Path to Tenuto field visuals and logged the same `0/1` split.
- Battle proof
  `debug-captures/windows-lab/20260519-191046-rsx-present-gpuswap-battle-windows-windows/`
  reached clean active first-battle UI and logged the same `0/1` split.

Decision: keep this Windows-only and opt-in. It moves about `3.52 MB` per
proven boot/route from CPU byte swap to GPU shuffle, but promoted SPU/PPU
replacement is still `0 B / 0%`, remaining render-pass break debt is still
`blit_src_to_general`, and the path is not a 200% gate candidate.

## Current Geometry Upload Scout

Corrected field run
`debug-captures/windows-lab/20260520-125838-rsx-auditor-vertex-index-field-corrected-windows/`
used `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA fence`
with RSX auditor interval `60`, PadApi route control, and
`-WindowsGameScreen 1`. It reached clean Path to Tenuto field visuals and had
no fatal, validation, access-violation, `VK_ERROR`, or unsupported-layout hit.

The RSX auditor now reports:

- `vertex_upload(draws/cache_hit/cache_miss/persistent_mb/volatile_mb)`;
- `index_upload(draws/emulated/restart/mb)`.

Corrected totals over `8100` field frames:

- actual persistent vertex uploads: `6,132.92 MB` (`45.43 MB` per 60 frames);
- volatile vertex uploads: `513.49 MB` (`3.80 MB` per 60 frames);
- index uploads: `1,071.74 MB` (`7.94 MB` per 60 frames);
- vertex cache hit/miss: `375,609 / 543,375`;
- emulated index draws: `23,013`;
- remaining render-pass breaks: `4,022`, still mostly `blit_src_to_general`.

Decision: geometry prep is the strongest newly measured CPU-to-GPU migration
target, but this is profiling only, not a speed win. Next experiments should
profile hot vertex/index signatures and build a verify-first GPU-resident
staging/cache or batched conversion path. Do not port to Thor/Android until the
standing 200% Windows moving-gameplay gate is met.

Shape-profile follow-up:

- Run:
  `debug-captures/windows-lab/20260520-133323-rsx-vertex-index-shape-profile-field-windows/`.
- Stack:
  `DepthReadOnly + FastSampled + KeepReadOnly + GpuSwap + Host DMA fence +
  Resolve Profile + RSX auditor 60`, PadApi route, `-WindowsGameScreen 1`.
- Visual:
  clean Path to Tenuto field at `screenshots/screenshot-0157s-field-late.png`.
- Profile overflow:
  `0` vertex overflow rows and `0` index overflow rows.
- Totals over `8160` frames:
  persistent vertex `6,163.64 MB` (`45.32 MB` per 60), volatile vertex
  `515.75 MB` (`3.79 MB` per 60), index upload `1,084.97 MB` (`7.98 MB` per
  60).
- Top vertex shape:
  `cmd/prim=2/6`, `attr=0x0109`, stride `20`, `regs=1`,
  `4,355,932` draws, `398.12 MB` volatile.
- Top persistent vertex target:
  `cmd/prim=3/6`, `attr=0x010d`, stride `24`, `500,324` draws,
  `2,743.06 MB` persistent, hit/miss `172,289/328,035`.
- Other persistent targets:
  `attr=0x010d`, stride `28`, `817.56 MB`; `attr=0x0083`, stride `32`,
  `1,390.12 MB`.
- Top index shape:
  `cmd/prim=3/6`, u16 index type `1/2`, `912,542` draws, `1,084.82 MB`.

Decision update: next Windows-only GPU migration experiment should verify a
GPU-resident vertex/index staging or conversion path for the dominant
`cmd/prim=3/6` persistent vertex layouts and the single dominant u16 index
upload shape. The volatile draw-array shapes are high-count but small-byte, so
only touch them if the design batches work rather than launching one GPU
dispatch per draw.

Index GPU byte-swap follow-up:

- Raw diagnostic run
  `debug-captures/windows-lab/20260520-145038-rsx-index-gpu-swap-field-r2-windows/`
  proved the dominant native u16 index endian conversion can move to Vulkan
  compute, but one dispatch per draw created `893,565` dispatches,
  `1,787,301` buffer barriers, and `879,561` total render-pass breaks.
- Cached diagnostic run
  `debug-captures/windows-lab/20260520-151947-rsx-index-gpu-swap-cached-field-windows/`
  with `-WindowsRsxIndexUpload GpuSwapCached` stayed visually clean and hit
  `368,091` frame-local index-cache reuses (`435.91 MB`), cutting dispatches to
  `521,646`, buffer barriers to `1,043,463`, and total render-pass breaks to
  `509,709`.
- Decision: `GpuSwapCached` is improved `gpu-migration-credit`, not a speed
  proof. Keep it default-off and Windows-only. The next geometry path must
  either prove a matched uncapped/CPU-constrained speed delta or move to a
  persistent/batched vertex/index cache that avoids immediate per-draw compute.
- Discarded follow-up: a temporary `GpuSwapCachedTrust` probe skipped per-hit
  content hashing. It stayed visually clean in
  `20260520-155514-rsx-index-gpu-swap-cached-trust-field-windows`, but high-cap
  field `20260520-155932-rsx-index-gpuswapcachedtrust-uncap240-field-windows`
  fell to about `95.9 FPS`, worse than hashed cache and control. The mode was
  removed; do not re-add it without a verifier.

## Good Candidate Signals

- A resource is already an RSX render target, texture, depth surface, blit source, resolve source, upload destination, or GPU-consumed buffer.
- The path removes CPU/GPU drains, render-pass breaks, broad layout transitions, host-visible ping-pong, or duplicate CPU prep.
- The work can be batched by frame, resource family, SPU image family, or render pass.
- Verification can compare output bytes, hashes, layouts, screenshots, or auditor counters before enabling fast mode.

## Bad Candidate Signals

- Zero direct RSX-local traffic and zero indirect RSX resource overlap in the probe summary.
- Tiny SPURS, semaphore, reservation, or PPU synchronization loops that need immediate CPU decisions.
- One Vulkan dispatch per tiny event, DMA, syscall, or branch.
- One Vulkan compute dispatch per tiny index/vertex draw. The 2026-05-20
  `-WindowsRsxIndexUpload GpuSwap` field proof moved about `1,046 MB` of u16
  index endian conversion to GPU, but it required `893,565` dispatches and
  ballooned buffer render-pass breaks to about `6,486` per 60 frames. Treat
  this as diagnostic `gpu-migration-credit`, not a speed path.
- Frame-local caching can reduce the raw per-draw trap but does not by itself
  prove speed. The 2026-05-20 `GpuSwapCached` proof avoided `368,091` repeated
  index conversions and cut render-pass breaks by about `42%`, yet still left
  `521,646` compute dispatches in the draw stream.
- Trusting same-frame index source addresses without content validation is not
  a free win. The temporary `GpuSwapCachedTrust` probe was slower and removed.
- Same-frame vertex superset reuse is a better geometry migration shape than
  per-draw compute because it reuses already uploaded GPU-consumed vertex bytes
  without launching a compute dispatch. Keep it title-scoped, same-frame only,
  and gated by `-WindowsRsxVertexSupersetCache Profile|Fast`.
- Same-frame volatile vertex reuse can move many tiny transient vertex writes
  away from the CPU upload path, but current byte volume is tiny. The
  2026-05-20 `-WindowsRsxVertexVolatileCache Fast` field proof avoided about
  `21 MB` of volatile writes and lowered late host RPCS3 CPU, but lost FPS in
  the high-cap A/B. Treat it as `gpu-migration-credit` / CPU-load tradeoff, not
  a speed path.
- Immediate CPU readback on the critical path.
- Visual correctness depends on skipping a resolve/barrier without an equivalent replacement.

## Required Visual Gates

Field:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -WindowsInputBackend PadApi -WindowsGameScreen 1
```

Menu/Options:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -WindowsInputBackend PadApi -WindowsGameScreen 1
```

First battle:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -WindowsInputBackend PadApi -WindowsGameScreen 1 -MaxSeconds 330
```

If the battle route fails, fix the route before claiming a renderer result. A field-only proof cannot promote a speed path.

## Current Windows Route Caution

The old scene macro used `ls_down:120` / long D-pad pulses at the title screen
and could select title `OPTIONS` instead of `LOAD`. Use short PadApi pulses for
load-route work:

```powershell
wait:45000;down:20;wait:500;cross:80
```

Then select Save File 01, move the confirm prompt to `Yes`, acknowledge
`Load complete`, and capture branch points with labeled screenshots such as
`shot:load-list` or `shot:after-load-ack`.

For constrained-CPU Windows A/B tests, use `-WindowsCpuAffinityMask` from
`tools/eternal_sonata_speed_sprint.ps1`. Example: `0x0F` pins the lab run to
the first four logical CPUs and writes the applied mask into the run log. Treat
this as a host-shape probe only; it is not a substitute for the 200% moving
gameplay gate.

If a long route sends an extra `cross` after the field loads, move the character
off the save point first. The current robust field checkpoint shape is:

```powershell
wait:45000;down:20;wait:800;cross:120;wait:15000;shot:load-list;cross:120;wait:5000;shot:confirm;up:40;wait:1000;shot:yes;cross:120;wait:30000;shot:after-confirm-wait;combo:ls_right+ls_down:2500;wait:1000;cross:120;wait:30000;shot:field-final;wait:20000;shot:field-late
```

As of 2026-05-20, the corrected route reaches the Path to Tenuto field/cutscene,
but skipping that cutscene leaves a plain `Pause` overlay that current scripted
`start`, `circle`, and `cross` resume attempts did not dismiss. Do not claim
active moving-field, menu, or first-battle proof from paused/cutscene captures.

## Vertex Superset Cache Follow-Up - 2026-05-20

Status: `gpu-migration-credit`, `single-run-cpu-load-win-candidate`, not a
`gate-candidate`.

Implementation:

- Windows RPCS3 gained `RPCS3_ES_RSX_VERTEX_SUPERSET_CACHE=profile|fast`,
  surfaced as `-WindowsRsxVertexSupersetCache Profile|Fast`.
- The gate is `BLUS30161`-scoped and same-frame only. It records persistent
  vertex uploads in a frame-local address-ordered cache, then lets later
  contained persistent vertex ranges reuse the already uploaded GPU buffer
  slice. No per-draw compute shader or new buffer barrier is added.
- `Profile` counts contained-range opportunities while rendering through the
  existing CPU upload path. `Fast` changes rendering by reusing the superset
  offset.

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

Counter proof:

| Run | Vertex Superset Hits | Hit MB | Persistent Vertex Upload MB | Reading |
| --- | ---: | ---: | ---: | --- |
| `Profile` | `60,600` | `544.05` | `6,157.42` | Opportunity count only; visible frame still used the old upload path. |
| `Fast` | `76,836` | `751.17` | `5,619.05` | Reused GPU-resident vertex slices and reduced persistent upload by about `538 MB` versus Profile. |

High-cap late-field A/B, auditor off:

| Run | Title FPS | Overlay FPS | Overlay Total CPU | Host RPCS3 CPU | Host GPU Sum | Reading |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `Off` | `119.99` | `120.03` | `35.9%` | `42.7%` | `80.3%` | Control held about 120 FPS. |
| `Fast` | `119.80` | `119.39` | `37.3%` | `36.7%` | `68.8%` | Same FPS class, lower final host RPCS3 CPU and GPU engine sum in this one field sample. |

Extended visual proof:

| Run | Visual | Vertex Superset Hits | Hit MB | Reading |
| --- | --- | ---: | ---: | --- |
| `Pause/menu overlay Fast` | Clean Pause overlay over field at `screenshot-0112s.png`; not a full Options page. | `52,972` | `517.87` | Broadens UI-overlay coverage, but does not satisfy the full menu/Options gate. |
| `First-battle Fast` | Clean tutorial prompt at `screenshot-0157s.png` and active battle UI at `screenshot-0218s.png` / `screenshot-0279s.png`. | `212,754` | `3,569.62` | Confirms the Fast path survives first-battle rendering and UI. |

Decision:

- Promote this as real RSX geometry `gpu-migration-credit`: it avoids repeated
  CPU persistent-vertex prep/upload for same-frame contained ranges, and the
  field, Pause overlay, and first-battle screenshots were clean in the tested
  Fast runs.
- Do not call it a 200% speed improvement. The uncapped field route stayed
  near `120 FPS` in both control and Fast. The host CPU drop is promising for
  smaller/CPU-limited systems, but it needs repeat A/B and full menu/Options
  proof before being treated as a durable `windows-micro-win`.
- Next geometry step should generalize from contained same-frame vertex reuse
  toward a validated persistent vertex-range cache or batched fill path, still
  avoiding one compute dispatch per draw.

## Volatile Vertex Cache Follow-Up - 2026-05-20

Status: `gpu-migration-credit`, `cpu-load-tradeoff`, `parked-speed-path`, not
a `windows-micro-win` or `gate-candidate`.

Implementation:

- Windows RPCS3 gained `RPCS3_ES_RSX_VERTEX_VOLATILE_CACHE=profile|fast`,
  surfaced as `-WindowsRsxVertexVolatileCache Profile|Fast`.
- The gate is `BLUS30161`-scoped and same-frame only. It hashes the actual
  transient vertex source bytes, then lets repeated volatile blobs reuse the
  already uploaded GPU buffer slice. No compute dispatch is added.
- `Profile` counts hits while still uploading normally. `Fast` changes
  rendering by reusing the volatile slice.

Proof runs:

- Profile/counter:
  `debug-captures/windows-lab/20260520-182520-rsx-vertex-volatile-profile-field-windows/`.
- Fast/counter:
  `debug-captures/windows-lab/20260520-182927-rsx-vertex-volatile-fast-field-windows/`.
- High-cap control:
  `debug-captures/windows-lab/20260520-183334-rsx-vertex-volatile-off-uncap240-field-windows/`.
- High-cap Fast:
  `debug-captures/windows-lab/20260520-183657-rsx-vertex-volatile-fast-uncap240-field-windows/`.

Counter proof:

| Run | Volatile Cache Hits | Hit MB | Volatile Vertex Upload MB | Reading |
| --- | ---: | ---: | ---: | --- |
| `Profile` | `240,239` | `21.08` | `551.96` | Repeated tiny transient blobs exist, but byte volume is small. |
| `Fast` | `239,839` | `21.07` | `528.09` | Reused same-frame GPU-resident volatile slices and avoided about the hit-byte volume. |

High-cap late-field A/B, auditor off:

| Run | Title FPS | Overlay FPS | Overlay Total CPU | Host RPCS3 CPU | Host GPU Sum | Reading |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `Off` | `118.63` | `119.55` | `33.1%` | `69.4%` | `68.3%` | Control held near the 120 FPS field plateau. |
| `Fast` | `109.69` | `110.19` | `35.0%` | `37.5%` | `72.5%` | CPU load shifted down in the late host sample, but FPS dropped. |

Decision:

- Keep the switch as diagnostic `gpu-migration-credit`: it moves real repeated
  volatile vertex upload work out of the CPU write path and field visuals were
  clean.
- Do not count it as `windows-micro-win`. The high-cap field route lost about
  `8%` FPS even though the late host CPU sample improved.
- Do not port to Thor. This is too small to matter for the 200% gate unless a
  later constrained-CPU proof shows a net throughput win.

## Result Labels

- `gpu-migration-credit`: real GPU residency or migrated work, correctness-clean, speed not proven.
- `windows-micro-win`: matched Windows comparison shows a 1%-10% speed or CPU-load reduction.
- `gate-candidate`: combined matched Windows run approaches or exceeds the 200% promotion bar and has clean field/menu/battle visuals.
- `failed`: corruption, crash, validation mismatch, route failure, or no work moved.
- `parked`: plausible but blocked by missing evidence, tooling, route, or architecture.
