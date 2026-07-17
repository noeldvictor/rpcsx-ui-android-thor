# Vulkan flicker upstream slice ? 2026-07-17

## Scope

- Target: AYN Thor Max, Android ARM64, stock Qualcomm Vulkan first.
- Title route: Eternal Sonata `BLUS30161`.
- Android base: `bc2c152f8`.
- Goal: remove undefined queue-submit state and missing Vulkan memory visibility
  that can present as intermittent flicker, stale textures, or driver-dependent
  behavior.
- Thermal policy: host-only source audit and ARM64 build. No ADB query, install,
  launch, or gameplay route occurred.

## Upstream audit

Recent upstream RPCS3 Vulkan/RSX fixes were checked against the current vendored
renderer with forward and reverse `git apply --check` probes. The Android tree
predates several renderer refactors, so whole-commit failure was treated as a
dependency signal rather than permission to force a broad port.

### Already represented locally

- `ed7f1aa`: fragment constants already use `alloc<256>`, matching the UBO
  alignment fix.
- `59468f1`: the post-transfer DMA buffer barrier already covers subsequent
  transfer reads and writes.
- The existing Android renderer also contains numerous explicit transfer,
  compute, and image-layout barriers from earlier Thor work.

### Selected corrections

#### `5fc7450` ? initialized Vulkan queue submissions

The clean upstream patch was applied exactly:

- zero-initialize wait semaphore, signal semaphore, and wait-stage arrays;
- bounds-check semaphore writes with `at32`.

This removes undefined copied bytes from `queue_submit_t` packets and makes an
overflow fail at the indexed write.

#### `46bbbd2` ? shadow-heap fragment visibility

The local shadow-heap copy barrier exposed transfer writes only to the vertex
shader stage. The missing upstream semantic change was ported narrowly by
including `VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT` in the destination stage
mask.

This prevents fragment shaders from observing stale shadowed uniform/storage
data after a transfer copy.

#### `5311f00` ? detile scratch-buffer reuse barriers

The current detile path already had the correct post-transfer and post-compute
barriers. It lacked upstream's two pre-use barriers. The port adds:

- all-commands memory access to transfer-write visibility before loading tiled
  data into reused scratch storage;
- all-commands memory access to compute-write visibility before decoding into
  the reused linear scratch range.

These barriers target write-after-read/write hazards when the global scratch
buffer is recycled across texture operations.

### Parked dependency-bound fixes

The following candidates require newer render-target, surface-scaling, texture,
or data-heap architecture and were not forced into the older vendored core:

- `cb276f0` aggregate-image transfer barriers;
- `3574677` wide-texel deswizzle rework;
- `0052108` per-surface resolution-scale transfer correction;
- `09554c4` unaligned DXT fallback;
- `1b11430` aligned-memory infrastructure;
- `069821a` dynamic resolution-scale surface optimization.

## Validation

Command:

`gradlew.bat :app:buildCMakeRelWithDebInfo[arm64-v8a] --no-daemon --console=plain --offline`

Result:

- `BUILD SUCCESSFUL`.
- Artifact:
  `app/build/intermediates/cxx/RelWithDebInfo/724a6w64/obj/arm64-v8a/librpcsx-android.so`
- Size: `1,351,016,000` bytes.
- SHA-256:
  `0D8358DF72E45F3A136289511CB8FBD3DDCD521DBBDEAAD960A7796531390808`
- `git diff --check`: clean.

## Promotion state

Classification: `build-proven`, `device-unmeasured`.

No flicker reduction, FPS, frame-pacing, or thermal credit is claimed yet.
A later cool-device round must use the same field, first-battle, and menu route,
preferably with a short matching baseline and immediate stop on corruption,
fatal VM/SPU errors, or excessive temperature.
