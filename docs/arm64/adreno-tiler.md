# The GPU is a tiler and the backend does not know it

The CPU-side review found one real thing (AES) and a lot of code that was already
correct. The GPU side is not in the same condition.

This is the GPU equivalent of [`x86-isms-sweep.md`](x86-isms-sweep.md): not "which
instruction", but **which assumptions came from immediate-mode desktop GPUs and do
not hold on a tiler**. The reference is
[`../hardware/qualcomm_adreno_game_developer_guide.pdf`](../hardware/qualcomm_adreno_game_developer_guide.pdf).

## The two costs a tiler has and a desktop GPU does not

Adreno renders into on-chip **GMEM**, one tile at a time. Two operations move data
between GMEM and system memory, and they are the whole ballgame:

- **unresolve** — `LOAD_OP_LOAD` reads the attachment back into GMEM before the
  tile is rendered
- **resolve** — `STORE_OP_STORE` writes the tile back out afterwards

On an immediate-mode desktop GPU both are close to free: the attachment lives in
VRAM and stays there, so "load" means "leave it alone". On a tiler each one is a
full-surface memory transaction, per attachment, per pass.

## What the backend actually asks for

`VKRenderPass.cpp:276-295`, unconditionally, with no parameter and no variation:

```cpp
color_attachment_description.loadOp  = VK_ATTACHMENT_LOAD_OP_LOAD;
color_attachment_description.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
...
depth_attachment_description.loadOp        = VK_ATTACHMENT_LOAD_OP_LOAD;
depth_attachment_description.storeOp       = VK_ATTACHMENT_STORE_OP_STORE;
depth_attachment_description.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_LOAD;
depth_attachment_description.stencilStoreOp= VK_ATTACHMENT_STORE_OP_STORE;
```

Every attachment op used anywhere in the Vulkan backend:

```
   3  VK_ATTACHMENT_LOAD_OP_LOAD          3  VK_ATTACHMENT_STORE_OP_STORE
   1  VK_ATTACHMENT_LOAD_OP_DONT_CARE     1  VK_ATTACHMENT_STORE_OP_DONT_CARE
   0  VK_ATTACHMENT_LOAD_OP_CLEAR
```

So **every render pass unresolves and resolves both colour and depth**, always.

## The clear path makes it worse, not better

`LOAD_OP_CLEAR` is used **zero times**. Clears go through
`vkCmdClearAttachments` inside the pass — `VKGSRender.cpp:1634`.

On a tiler that inverts the intended cost. `LOAD_OP_CLEAR` is the cheapest thing
the hardware can do: the tile is marked cleared in GMEM and **no memory traffic
happens at all**. Clearing with `vkCmdClearAttachments` after a `LOAD_OP_LOAD`
means the driver reads the entire surface from system memory into GMEM and the
very next command throws all of it away.

That is a full-surface read, per attachment, per cleared pass, whose result is
provably unused. It is the single most-cited mobile GPU mistake, and it is here
by construction rather than by accident — the code is correct and idiomatic for
the desktop GPUs RPCS3 targets.

## What this does not license

**This is not a blanket "switch everything to DONT_CARE" change**, and that is
why it is written up rather than patched.

RPCS3 uses `LOAD_OP_LOAD` for a real reason: RSX render targets persist across
draws and passes, the guest renders incrementally into them, and the backend
splits work into many passes over the same surface. Blindly discarding contents
would corrupt any target that is accumulated rather than fully rewritten.

The safe subset, in rough order of confidence:

1. **A pass whose first operation is a full-region clear can use
   `LOAD_OP_CLEAR`.** The information is already present at
   `VKGSRender.cpp:1634` — the clear descriptors and the region are right there.
   This is mechanical and cannot lose data, because the load is provably dead.
2. **Depth/stencil with `STORE_OP_DONT_CARE`** when the guest does not read depth
   back after the pass. Needs the ZCULL/readback state to say so; the profile
   already carries `Accurate ZCULL stats: false` and `Relaxed ZCULL Sync: false`.
3. Merging consecutive passes over the same attachment set, which removes a
   resolve/unresolve pair each time.

## Why it might matter here specifically

Unmeasured, and stated as a hypothesis rather than a result — but the shape fits
two things already recorded.

Eternal Sonata's profile sets `Write Color Buffers: true`, which forces colour
targets back to guest memory. On a tiler that is a resolve on top of the resolve
the pass already does. And
[`rsx-boot-hang.md`](rsx-boot-hang.md) records RSX wedging immediately after three
texture cache misses **on render-target addresses** — the exact operation that
forces a mid-pass resolve.

Neither was examined as a bandwidth question. Both were treated as correctness or
scheduling questions, because nothing in this repo had the tiler's cost model
written down until now.

## The second cost: the render pass is closed constantly

`LOAD_OP_LOAD`/`STORE_OP_STORE` would be tolerable if a frame were a few long
passes. It is not. `is_renderpass_open` — which in practice means "close the pass
so I can do this" — appears across the backend:

```
  VKTexture.cpp        6      vkutils/barriers.cpp   4
  VKGSRender.cpp       3      VKTextureCache.cpp     2
  VKCompute.cpp        1      VKQueryPool.cpp        1
  VKDraw.cpp           1      image_helpers.cpp      1
```

Every texture upload, blit, compute dispatch, occlusion query and image barrier
can end the current pass. On a desktop GPU that is close to free. On a tiler each
one is **a full resolve of colour and depth out to system memory**, and because
the next draw re-opens with `LOAD_OP_LOAD`, **a full unresolve back in**.

So the two findings multiply. The first says every pass pays maximum entry and
exit cost; the second says passes are broken constantly.

`vkutils/barriers.cpp:19` is the clearest case, and notably someone already knew:

```cpp
const bool breaks_renderpass = !preserve_renderpass && vk::is_renderpass_open(cmd);
vk::thor::rsx_auditor::record_image_barrier(src_stage, dst_stage, breaks_renderpass);

if (breaks_renderpass)
{
    vk::end_renderpass(cmd);
}
```

There is a `preserve_renderpass` opt-out, so the cost was understood at least
locally — the question nobody has asked is how often the opt-out is *not* taken.

## Measured: zero breaks on the workload available

The section above is a hypothesis and the measurement does not support it. Recorded
in place rather than deleted, because the reasoning was sound and the conclusion
was still wrong.

Auditor enabled, Odin Sphere booted, two consecutive 60-frame windows:

```
frames=60 rp_begin=60 rp_end=60 rp_break=0 rp_break(g/b/i/t)=0/0/0/0
          barriers(g/b/i/t/all)=0/0/0/0/0 barrier_mb=0.00
frames=60 rp_begin=62 rp_end=62 rp_break=0 ...
```

**Zero render-pass breaks. Zero image barriers. Roughly one render pass per
frame.** The eight `is_renderpass_open` call sites are real, and on this workload
none of them fire.

The honest reading, with its limits stated: this is a black loading screen at
13 FPS with an almost empty scene, so it is a *floor*, not a representative
figure. A gameplay scene with texture streaming, occlusion queries and
render-to-texture would exercise exactly the paths that are quiet here. What the
measurement does establish is that "passes are broken constantly" was an
assumption read off a call-site count, and call-site counts do not measure
frequency.

The first finding survives it and shrinks: at ~1 pass per frame, unconditional
`LOAD_OP_LOAD`/`STORE_OP_STORE` costs one unresolve and one resolve of colour plus
depth **per frame**, not per pass-break. That is still pure waste on a clear —
but it is one surface pair a frame, and at 1080p that is on the order of 16 MB a
frame rather than the hundreds the break hypothesis implied.

**Do not act on this document until it has been re-run on a scene that draws
something.** The whole point of the auditor is that it makes that cheap.

## The instrument already exists

That second line is the important one. **This fork already has an auditor that
counts render-pass-breaking barriers**, `vk::thor::rsx_auditor`, in
`VK/vkutils/thor_rsx_auditor.h`. It is compiled out by default behind the
`RPCSX_THOR_RSX_AUDITOR` CMake option, wired to a Gradle property in
`app/build.gradle.kts`.

So the measurement for everything above does not need to be built. It needs to be
switched on:

```
./gradlew assembleThortest -PrpcsxThorRsxAuditor=1
```

That gives breaks-per-frame directly. Multiply by the attachment footprint —
colour plus depth at the render target's resolution — and the bandwidth cost of
the current design falls out arithmetically, the same way the AES question was
settled by measuring 13.6 MB of firmware rather than timing a boot.

Do that **before** touching `LOAD_OP_CLEAR`. If breaks-per-frame turns out to be
small, the whole thing is another 35-millisecond finding and should be recorded as
one.

## Feasibility of the `LOAD_OP_CLEAR` change, checked

The worry was the render-pass cache: passes are keyed by a packed `u64`, and a
load-op variant that aliased an existing entry would silently hand back a pass with
the wrong ops. Checked rather than assumed — `renderpass_key_blob` in
`VKRenderPass.cpp:66`:

```cpp
u64 color_format          : 8;
u64 depth_format          : 8;
u64 sample_count          : 6;
u64 layout_blob           : 15;
u64 input_attachments_mask: 5;
```

**42 bits of 64 used, 22 spare.** A `load_op_clear : 1` field costs nothing and
cannot collide. The cache was not the obstacle.

So the work splits cleanly, and only one part is hard:

| step | difficulty |
| --- | --- |
| 1. add `load_op_clear : 1` to the key blob | trivial, 22 spare bits |
| 2. plumb the flag through `get_renderpass_key` / `begin_render_pass` | mechanical |
| 3. emit `VK_ATTACHMENT_LOAD_OP_CLEAR` in `create_renderpass` when set | mechanical, one branch at `VKRenderPass.cpp:276` |
| 4. **decide at the call site that a clear is coming** | the actual work |

Step 4 is the whole problem. Today the clear happens *inside* an already-open pass
via `vkCmdClearAttachments` (`VKGSRender.cpp:1634`), and `LOAD_OP_CLEAR` has to be
chosen *before* `vkCmdBeginRenderPass`. Converting one into the other means knowing,
at pass-begin time, that the first operation will be a full-region clear of every
attachment — which is a restructuring of when the backend decides to open a pass,
not a flag.

Steps 1-3 without step 4 are dead code, so they are deliberately not committed.
**The design is settled; the remaining work is a call-site restructuring and wants a
session with room to verify rendering, not just compilation.**

## How to measure it before changing anything

The trap this project keeps hitting is a correct measurement of the wrong
population, so: the number that matters is **bytes moved between GMEM and system
memory per frame**, not frame time. Adreno exposes that through its performance
counters, and a change that removes an unresolve should show up there directly
and immediately, independent of whatever else the frame is doing.

Frame time on a title that is CPU-bound behind an SPU reservation loop would show
nothing either way, and would be the wrong instrument entirely.
