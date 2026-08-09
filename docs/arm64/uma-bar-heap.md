# The BAR heap is the whole machine, and it is parked

A finding that came out of reading Qualcomm's *Snapdragon Mobile Platform OpenCL
General Programming and Optimization* guide (`docs/hardware/`) against this
emulator's Vulkan memory setup. It is recorded as a measured observation and a
proposal, not as a change — nothing here has been implemented or benchmarked.

## What the hardware is

Snapdragon is a unified memory architecture. CPU and GPU address the same
physical DRAM. The Qualcomm guide spends section 7.4 on the consequence: on this
part a staging copy is not a cost of doing business, it is a copy the hardware
never required. Their OpenCL advice is `CL_MEM_ALLOC_HOST_PTR` and the ION /
dmabuf / AHardwareBuffer extensions; the Vulkan equivalent is simply that
host-visible and device-local are the *same* memory types.

## What the emulator assumes

`Emu/RSX/VK/vkutils/device.cpp:1183` classifies memory into three groups, and the
third is the interesting one:

```cpp
auto bar_memory_types = find_memory_type_with_property(
    (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT |
     VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT), 0);
...
// BAR heap, currently parked for future use, I have some plans for it (kd-11)
```

That comment is correct for the hardware it was written against. On a discrete PC
GPU, memory that is simultaneously host-visible and device-local is the PCIe BAR
aperture — historically a 256 MB window, scarce enough that it is reasonable to
set it aside for a specific future purpose rather than spend it on general
uploads.

## What this device actually reports

From a Folklore boot on the Thor:

```
RSX: Detected 11441 MB of BAR memory
```

**11.4 GB.** That is not an aperture, it is the machine. Every heap on an
integrated part qualifies as host-visible and device-local, so the category the
code treats as a scarce exotic resource is, here, all of memory.

## Why this is worth pursuing

The upload path currently writes to a host-coherent staging heap and copies into
device-local memory. On UMA both heaps are the same DRAM, so that copy moves
bytes from one part of physical memory to another for no architectural reason.
Texture and vertex uploads are the volume traffic in an RSX frame.

## Measured: the precondition holds

`VkPhysicalDeviceMemoryProperties` on the Thor, dumped at `device.cpp:1186`:

| type | flags | heap size |
| --- | --- | --- |
| 0 | DEVICE_LOCAL, HOST_VISIBLE, HOST_COHERENT | 11441 MB |
| **1** | **DEVICE_LOCAL, HOST_VISIBLE, HOST_COHERENT, HOST_CACHED** | 11441 MB |
| 2 | DEVICE_LOCAL, HOST_VISIBLE, HOST_CACHED | 11441 MB |
| 3 | DEVICE_LOCAL, LAZILY_ALLOCATED | 11441 MB |

**One heap, and every type is device-local.** There is no separate VRAM to stage
into — types 0-2 are the same 11.4 GB of DRAM described three ways.

Type 1 answers the question this file was written to ask. It is device-local,
host-visible, coherent *and* cached, which was the stated precondition for a
direct-write upload path being worth prototyping. The staging copy currently
performed on the way to device-local memory has no destination that differs from
its source.

Type 3 is worth noting separately for the tiler work in
[`adreno-tiler.md`](adreno-tiler.md): `DEVICE_LOCAL | LAZILY_ALLOCATED` with no
host visibility is Adreno's on-chip tile memory. Transient attachments — depth
and MSAA targets that are never sampled outside the pass — can be backed by it
and never touch DRAM, which pairs directly with the `LOAD_OP_CLEAR` /
`STORE_OP_DONT_CARE` work that file describes.

## What has *not* been established

The precondition is proven; the payoff is not.

* **Whether a direct write is actually faster.** Host-visible does not mean fast
  to write. Type 1 being `HOST_CACHED` removes the usual objection — an uncached
  or write-combined mapping would have sunk this — but cached-and-device-local
  still has to beat cached staging plus a driver-side copy in practice, and that
  is an A/B, not a deduction.
* **Whether the RSX upload path is bandwidth-bound at all.** If uploads are a
  small share of frame time, removing a copy from them buys nothing measurable.
* **What the copy currently costs.** Unmeasured. Establish it before changing it.

## The next step

The dump is done and type 1 qualifies, so the remaining work is the part that
decides the value rather than the feasibility:

1. Measure upload volume per frame first. `adreno-tiler.md` records a prediction
   of heavy traffic that measurement cut to ~1 pass per frame; do not repeat that
   mistake by optimizing a path before knowing its size.
2. Prototype the upload heap on type 1 and A/B it against the current staging
   path on a title that renders — Folklore now does.

## Measured, and it settles the question: not worth doing

```
Thor RSX Staging: frames=60 heap_allocs=660 alloc_mb=0.50 per_frame_mb=0.00
```

**0.5 MB across 60 frames — about 8.5 KB per frame**, over 660 allocations.

That is the entire volume a direct-write upload path would stop copying. The
feasibility argument was sound: one heap, every type device-local, type 1
host-visible *and* cached, so the staging copy's destination is genuinely its own
source. None of that matters at 8 KB a frame.

**Closing this.** The precondition is proven and the payoff is negligible, which
is the same shape as the AES work: a real inefficiency, correctly identified,
worth nothing once measured. Do not reopen it without a workload that shows a
materially larger figure here first.

Caveat worth stating: measured on Folklore's title and prologue screens, which
are light. A dense 3D scene will upload more. The number to beat is in this file
— re-measure before arguing from the architecture again.
