# Vulkan descriptor-pool autoscaling

Date: 2026-07-17

## Goal

Reduce Vulkan descriptor-pool startup allocation and growth pressure on AYN Thor without changing descriptor contents, draw ordering, or synchronization.

## Upstream basis

- Adapted RPCS3 `8e370c2` (automatic descriptor-pool sizing).
- Adapted RPCS3 `bf85a3f` (debounced pool growth).
- Did not take `3b1abec`; its bulk aligned allocator depends on the newer `rsx::data_heap` / `ring_buffer_helper` architecture that this tree does not have.

## Local adaptation

This renderer uses one older global draw descriptor pool rather than the newer per-pipeline arrangement. The global renderer and shader interpreter now start at 256 sets and grow on demand up to the existing device-derived ceiling (normally 32,768, or 8,192 on devices with lower descriptor-indexing limits). Compute and overlay pools retain their fixed 1,024-set behavior.

Each newly created subpool stores its actual set capacity. Allocation, cache fill, and rollover decisions use that recorded capacity. A failed Vulkan pool creation rolls the autoscaling state back before retrying.

The modeled new-pool sequence at a 32,768 ceiling is:

```text
256, 256, 512, 512, 1024, 1024, 2048, 2048,
4096, 4096, 8192, 8192, 16384, 16384, 32768, 32768
```

The initial reservation is therefore 128 times smaller than the former 32,768-set pool. Repeating each size once before doubling avoids runaway growth after a single overflow.

## Host proof

- ARM64 Android RelWithDebInfo build: passed (`BUILD SUCCESSFUL in 1m 31s`).
- Artifact: `app/build/intermediates/cxx/RelWithDebInfo/724a6w64/obj/arm64-v8a/librpcsx-android.so`
- Size: `1,351,033,144` bytes.
- SHA-256: `85B82314153CC3F20016A3AC1C7096F0F67BF9753881FD3C070653AF1A7676C7`.
- Modified UTC: `2026-07-17T05:20:35.0134261Z`.
- `git diff --check`: passed.
- Call-site and `maxSets`/`max_sets()` audit: passed.

## Device status

No ADB, install, launch, or device benchmark was performed in this round, so the hot Thor was not disturbed. This is build-proven and structurally lower-pressure, but it is not yet a measured FPS, frame-pacing, flicker, or thermal win. The next proof must be a thermally bounded field, first-battle, and in-game-menu run on a cool Thor.
