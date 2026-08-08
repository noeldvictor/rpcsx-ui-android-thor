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

## How to measure it before changing anything

The trap this project keeps hitting is a correct measurement of the wrong
population, so: the number that matters is **bytes moved between GMEM and system
memory per frame**, not frame time. Adreno exposes that through its performance
counters, and a change that removes an unresolve should show up there directly
and immediately, independent of whatever else the frame is doing.

Frame time on a title that is CPU-bound behind an SPU reservation loop would show
nothing either way, and would be the wrong instrument entirely.
