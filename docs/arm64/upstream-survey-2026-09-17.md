# Upstream survey, 2026-09-17: ARMSX3 tenth pass and RPCS3 master

Part of the notes indexed from [`AGENTS.md`](../../AGENTS.md). The ledger for
the survey series is [`../fork-watch.md`](../fork-watch.md). The previous pass
is [`upstream-survey-2026-09-07.md`](upstream-survey-2026-09-07.md).

This pass has two parts. The first part is a read of the two upstream trees in
the comparison checkout, `rpcs3-upstream`, after a fetch. The second part is
the news item of the week: RPCS3 reports a 20 to 25 percent frame-rate gain on
NVIDIA GPUs from one change, and the question is whether the Thor gets the
same. Both parts are host work. Neither touched the Thor.

## Fetch state

| ref | head | date | note |
| --- | --- | --- | --- |
| `origin/master` (RPCS3/rpcs3) | `8db660b18` | 2026-09-17 | 64 commits since `54014a7de` (2026-09-07) |
| `armsx3/master` (ARMSX2/ARMSX3) | `23e119c0c` | 2026-09-15 | 135 commits since `6925a398e`; 46 of them came in through their merge of RPCS3 master (`6eda23dd2`); releases 0.9.8, 0.9.8.1 to 0.9.8.4, 0.9.9 |

The ninth pass stopped at ARMSX3 `6925a398e` and RPCS3 `54014a7de`.

## The NVIDIA item: RPCS3 pull request 19500

The news articles of 2026-09-17 (VideoCardz, Notebookcheck, OC3D, ixbt) all
report one RPCS3 post on X: a workaround for an NVIDIA driver bottleneck gives
+20 percent in Red Dead Redemption on a 13900K with an RTX 3080 and +25 percent
on a 9800X3D with an RTX 5090. The articles do not name the change. The change
is pull request 19500 by Yahfz with kd-11, merged 2026-09-16 as `a65980547`,
"rsx: Reuse discarded render targets during surface splitting". The pull
request body says: "This works around some NVIDIA driver bottlenecks, doesn't
seem to affect AMD. Got a 25-30% performance boost in my RDR benchmark scene."
Testers on the pull request report gains in GTA IV, the three Saints Row titles
(GTX 1060) and Gran Turismo 5 (60 to 67 FPS on an RTX 5070, and 107 to 147 FPS
in a light scene with much lower VRAM use).

### What the change does

A surface split happens when a game writes a smaller or offset surface into
memory that a live render target already covers. The surface store cuts the old
target into the regions the new surface does not cover, and clones a render
target for each region (`split_surface_region` in `surface_store.h`). Before
the change, a clone with no compatible sink created a new image, and the old
target went to the discard list. The change looks in the discard list first for
a surface with the same scaled size, sample count, format class, format, usage
and create flags, and with no references and no pending old contents. When it
finds one it takes it out of the list, resets its state and hands it to
`clone_surface` as the sink. `clone_surface` then skips the image creation and
does the same setup as for a new image.

So the change removes image creations and, later, image destructions. On NVIDIA
the create path is the slow part. The pull request does not say which call
inside the driver is slow.

### What it means for the Thor

Three facts from this tree's own measurements decide the prediction.

1. The work removed is on the RSX thread. On the Transformers combat scene the
   RSX thread is not the binding stage (`AGENTS.md`, sprint gate, 2026-09-08).
   The frame is the PPU render thread, the GCMX SPU jobs and the GPU.
2. The create path on the Thor is Turnip on Adreno 740, not the NVIDIA driver.
   A `vkCreateImage` in Turnip is a layout computation in user space. The
   memory comes from this fork's own device-local heap in the surface cache
   pool, so an image creation rarely reaches the kernel.
3. Nobody has counted how many clones a frame makes in either tracked title. A
   scene that makes none cannot move.

So the expected frame-rate change on the Transformers scene is zero. A change
in RSX thread time, in cores, or in memory churn is possible and is worth a
count. That is what the port measures first.

### The port, and how to read it

The change is in and on by default, at the owner's decision of 2026-09-17,
before any device measurement. The switch is the Video setting "Reuse Discarded
Render Targets", in the app under Advanced settings, Video. The node is dynamic,
so a change applies at once, while a game runs. A property overrides the
setting for A/B runs driven by adb: `0` forces off, `1` forces on, unset
follows the setting:

    debug.rpcsx.thor.rsx_surface_reuse = 0

The property is read once on first use; the setting is read on each call
(`thor_surface_reuse.h`). Two counters on the perf_monitor Frames line say
whether the path fires:

    surf_clone=<clones with no sink>  surf_reuse=<clones served from the discard list>

`surf_clone` counts with the gate off too. The rule for the device: read
`surf_clone` and `surf_reuse` per frame from the first run on this build. If
`surf_clone` is near zero in the scene, the port has no reach there, and the
default costs nothing. If it is large, run the standard A/B on one binary,
gate on (the default) then off, three windows each, and read FPS, cores and
the two counters. The `thor-measurement-validity` rules apply.

Files: `rpcs3/Emu/RSX/Common/surface_store.h` (finder and the gated branch),
`rpcs3/Emu/RSX/VK/VKRenderTargets.h` and `rpcs3/Emu/RSX/GL/GLRenderTargets.h`
(`is_reusable_surface`, `prepare_for_reuse`, and the `initialize` restructure of
`clone_surface`), `rpcs3/Emu/RSX/thor_rsx_counters.h`,
`rpcs3/Emu/RSX/thor_surface_reuse.h`, and the config node
`reuse_discarded_render_targets` in `rpcs3/Emu/system_config.h`. This fork's
`clone_surface` has no
resolution scaling config argument, so the finder calls the four-argument
`apply_resolution_scale`. The GL half is ported so the shared template compiles.

## Ported in this pass

Each port carries the origin hash in its commit message. None is measured.

### 1. Surface reuse, RPCS3 `a65980547`

Described above. On by default, gated, counted.

### 2. TBL for the ARM64 byteswap, RPCS3 `ec4b1ae65`

Whatcookie, 2026-09-15, upstream pull request 19498. ARMSX3 cherry-picked it as
`86cb3402e` and shipped it in 0.9.9. LLVM lowers the byteswap `shufflevector`
to `rev64` plus `ext` and does not turn it into one `tbl`, even where the
byteswap runs many times in a loop (llvm/llvm-project#223597). The port emits
`llvm.aarch64.neon.tbl1.v16i8` with a constant index vector on ARM64. The
recompiler emits this byteswap constantly, so the gain is code size and one
instruction per site.

This fork's `byteswap()` was the plain `zshuffle`. The
`match_expr(a, byteswap(match<u8[16]>()))` patterns in ROTQBY, ROTQBYI, SHUFB
and the DMA paths keep matching, because the fork's `llvm_calli::match`
compares the call name and this fork's `tbl()` emits the same intrinsic name.

Verify on the device the way `docs/arm64/jit-emitted-code.md` describes: read
the SPU object cache and look for `tbl` where `rev64` and `ext` were.
Unconditional, ARM64 only.

### 3. Drop the unused per-module helpers, RPCS3 `e826098bc`

Whatcookie, 2026-09-15. Every SPU module gets a `spu_test_state` function and a
`__spu-null` dispatch function. After the function pass manager runs, the port
erases each one that nothing calls, so it is not compiled into the object. This
fork erases the function table at the same point upstream does, before this
check, so the order is the same. Unconditional. Gain: object size and compile
time per module, on every cold boot, since this fork's native SPU object cache
is off by default.

### 4. 8-bit add and subtract folds, and compare fast paths, RPCS3 `ca223f70b`

Walter, 2026-09-10. Three IR-level rewrites:

- `SELB` with a `0xff00` or `0x00ff` halfword mask over two 16-bit adds (or
  subtracts) of the same operands becomes one 8-bit add (or subtract). The SPU
  has no byte add, so games build one this way.
- `ABSDB` where one operand is a compare result becomes `a ^ b`.
- `SHUFB` whose control word comes from a compare selects between `0x80` and
  byte 0 of `ra`.

All three are target independent. NEON has byte add and subtract, so the fold
lowers to one `add.16b` or `sub.16b` here. Unconditional. Eternal Sonata is
the stability canary for it.

## Rejected in this pass, with the reason

| Change | Reason |
| --- | --- |
| RPCS3 `e13ee1579` CFLTS saturation on ARM64 | This tree already emits `fptosi.sat`, one `FCVTZS` (`docs/arm64/codegen.md`). Upstream's form is a select chain. Upstream credits ARMSX3 `424514fde` and `19d23eb69` for the same fix. |
| RPCS3 `41f0ecc17` x86-only ifdefs in SPU LLVM | No runtime effect here. `m_use_avx512` and `m_use_avx` come from `utils::has_avx512()` and `has_avx()`, which return false outside `ARCH_X64` (`util/sysinfo.cpp`). The ARMSX3 0.9.9 note says "code written for x86 is no longer generated on this platform"; that code was never generated here. Compile-time hygiene only. |
| RPCS3 `92721aedf` SHUFB GFNI path | x86 only. |
| RPCS3 `bcb2d2231` AVX-512 index upload | x86 only. |
| RPCS3 `06d28a5f1` alpha test with native float16 | This fork's `RSXROPEpilogue.glsl` is the older form with no `_alpha_quantize`. No code to fix. |
| RPCS3 `a90c841b3` flush predictor for blit targets | This fork's blit path has no `real_dst_address` or `blit_op_result::dst_range` form. Different code. |
| RPCS3 `da2153db2`, `2003f2404` sys_memory | This fork's kernel is RPCSX's `kernel/cellos/src/sys_memory.cpp`. It has no `sys_memory_address_table`. |
| RPCS3 `fb2f1326a` silence syscall 579 | Syscall 579 is `null_func` at `kernel/cellos/src/lv2.cpp:843`. Take it only when a log shows the syscall. |
| RPCS3 `4f11259e5` savestate version | Follows the sys_memory change. |
| ARMSX3 `5323f8c2e`, `9f7db99a4` MUTABLE_FORMAT on tilers | This fork's `get_attachment_create_flags` returns only the feedback-loop usage bit when the driver supports framebuffer loops, and never sets `VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT` on Turnip. Their finding, that Turnip drops UBWC on a mutable-format attachment with no format list, does not apply here. Their own measurement: no frame-rate change on any game. |
| ARMSX3 `813710a68` Soulcalibur V label sampling | No `rsx_profiler.cpp` here. |
| ARMSX3 `b66d8f1ae`, `d1fa5ecba` ISO reader | No `Loader/ISO.cpp` here. |
| ARMSX3 `86cb3402e` | The same change as RPCS3 `ec4b1ae65`. |
| ARMSX3 Kotlin UI: mods, packages and title updates, savestates, touch scale, Play build, trophy sound, render position, OSD size | About 80 commits under `android/armsx3-ui`. Different app. Not read. |

## Needs adaptation, not ported yet

- **ARMSX3 graphics-pipe conversions**: `a2e025365` (32/16 byteswap as a
  fragment pass), `669ad8ce2` (D24S8 readback interleave as a fragment pass),
  `85b7495b9` (32-bit byteswap as a fragment pass). About 500 lines across
  `VKResolveHelper`, `VKTexture`, `VKTextureCache` and `vkutils/scratch`.
  Their claim for Arkham City: compute dispatches per frame from more than
  10,000 to 1, and the Adreno 830 device-lost hangs in Arkham City and Watch
  Dogs gone. The cause they name is the graphics-to-compute engine switch, not
  the dispatch count. Their levers: `ARMSX3_GFX_SHUFFLE`, `ARMSX3_GFX_SHUFFLE32`.
  First step here, no port needed: read `rp_end(... compute ...)` on the Frames
  line for Transformers and Eternal Sonata. That counter already exists and
  counts the render passes a compute dispatch ended. Near zero per frame means
  the series has no reach on these titles.
- **RPCS3 `12b4d3d50` and `bcd8a09f4`, SDK below 2.00**: user memory pool size
  and a 256 MB PPU private area at the front for very old SDKs. Eternal Sonata
  logs `sdk version: 0x230001`. Transformers is a 2009 title. No tracked title
  is in the band. Take it when a title below 2.00 is in play; Folklore (2007)
  is one.
- **RPCS3 `0646d3670`, PS Move tracker threads on demand**: this fork's
  `init_workers()` makes four threads in the constructor. Where the tracker is
  constructed was not found in the vendored `Modules` directory. Check whether
  the object exists at boot before porting.

## ARMSX3 releases 0.9.8 to 0.9.9, what their notes say

- 0.9.8 (2026-09-12): the Adreno GPU crash fix (`cs_shuffle_32` on the graphics
  pipe, above), game updates from Sony's servers.
- 0.9.8.1 to 0.9.8.4 (2026-09-13 to 14): the ISO sector buffer crash, savestate
  delete-all, the Artemis cheat collection, Play build storage.
- 0.9.9 (2026-09-15): the TBL byteswap and the x86 ifdefs (above), shortcut and
  frontend launches, a recommended settings database at setup.

## Sources for the NVIDIA item

- RPCS3 pull request 19500: https://github.com/RPCS3/rpcs3/pull/19500
- RPCS3 on X, post 2100302575954268238, cited by every article.
- VideoCardz: https://videocardz.com/newz/rpcs3-gains-up-to-25-performance-on-nvidia-gpus-after-workaround-for-driver-bug
- Notebookcheck: https://www.notebookcheck.net/RPCS3-announces-exciting-news-for-Nvidia-GPUs-promises-much-faster-performance.1401635.0.html
- OC3D: https://overclock3d.net/news/software/rpcs3-delivers-up-to-25-nvidia-fps-boost-with-driver-bug-workaround/
- ixbt: https://ixbt.games/en/news/2026/09/17/proizvoditelnost-emuliatora-playstation-3-vyrosla-do-25-na-videokartax-nvidia-blagodaria-obxodu-problemy-s-draiverom.html
