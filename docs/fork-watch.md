# Fork And Pull Request Watch

This file is the ledger for the periodic survey of RPCS3 forks and RPCS3 pull
requests. The goal is narrow. Find Android work and ARM64 work that another
tree did first. Take it, or write down why we do not take it.

Every fork below is GPL-2.0, the same licence as this tree. A port is legal.
Keep the origin commit hash in the port commit message.

## Cadence

Run the survey at the start of a sprint round, and not more than one time a
week. The survey is host work only. It does not touch Thor.

## Rules

1. Verify a claim against the source. Do not trust a commit title.
2. Diff the added lines against the vendored core before you call a fix new.
   The vendored core is at `app/src/main/cpp/rpcsx/`.
3. Check the path first. The vendored core uses the old RPCS3 layout
   `rpcs3/util/JIT*`. Current upstream uses `Utilities/JIT*`. A file that
   looks absent is often only moved.
4. Check whether this fork already solved the same problem at the call site.
   Two fixes for one problem can cancel each other. See the same rule in
   `AGENTS.md`, section `ARM64 Upstream Perf Uplift`.
5. Record a survey that finds nothing. An empty result is a result.
6. A port is a normal code change. It needs the same proof as any other
   change. Do not classify a port as a speed win without a measurement.

## How to run the survey

Use the GitHub REST API from the host shell. No token is necessary for these
calls.

```bash
# what a fork added on top of upstream
curl -sS "https://api.github.com/repos/RPCS3/rpcs3/compare/master...<owner>:<repo>:master"
# the files of one commit
curl -sS "https://api.github.com/repos/<owner>/<repo>/commits/<sha>"
# open upstream pull requests, newest first
curl -sS "https://api.github.com/repos/RPCS3/rpcs3/pulls?state=open&sort=updated&direction=desc&per_page=50"
```

Read the JSON as UTF-8. The Windows default code page fails on Cyrillic author
names.

## The watch list

| Tree | What it is | Why we watch it |
| --- | --- | --- |
| `https://github.com/sashkinbro/EmuCoreC` | RPCS3 fork. Android PS3 emulator with a Compose UI. Active since 2026-08-15. | It fixes Adreno and Android faults in the RPCS3 core. Same file layout as the vendored core. |
| `https://github.com/maxjivi05/PS3Native` | RPCS3 fork. Android port that tracks upstream master. | It keeps the Android work additive in `android/`. Good source of build glue. |
| `https://github.com/aenu1/aps3e` | Android PS3 emulator from RPCS3. | The older comparison tree. See `docs/arm64/armsx3-comparison.md`. |
| `https://github.com/RPCS3/rpcs3/pulls` | Upstream pull requests. | ARM64 and mobile GPU work arrives here before master. |
| `https://github.com/sashkinbro/EmuCoreV`, `EmuCoreX` | Vita3K and PCSX2 forks by the same author. | Not PS3. Watch only for Adreno driver loading and touch overlay ideas. |

## Survey log

### 2026-08-20 — EmuCoreC, first survey

State at the survey: `54` commits ahead of `RPCS3/rpcs3` master, `5` behind.
About `17000` changed lines sit in the Kotlin app. The core changes are small
and specific. The APK releases run from `v0.0.2` to `v0.0.5`.

Take these, in this order:

1. `d2b993c5` "android/cpu: port PPU/SPU compile-time hardening for ARM64".
   It changes `Utilities/JITLLVM.cpp` (+123), `AArch64Common.cpp` (+43/-34),
   `PPUThread.cpp` (+155), `SPUCommonRecompiler.cpp` (+133) and
   `SPULLVMRecompiler.cpp` (+107). Our equivalent files are `rpcs3/util/JITLLVM.cpp`
   and the same `Emu/Cell` paths. Read it against
   `docs/arm64/ppu-compile-oom.md` first.
2. `77dc85d0` "fix: stabilize protected RSX CPU transfers on Android". It
   changes `Emu/RSX/Host/MM.cpp` (+99/-16), `RSXOffload.cpp`, `nv0039.cpp`,
   `nv3089.cpp` and `texture_cache.h`. Our `MM.cpp` is `110` lines, so the
   vendored core is far behind here. This is page protection work, and the
   Thor page size makes it relevant.
3. `47220b15` "Vulkan pipeline caching, mobile GPU vendor detection, LLVM
   stability, and memory budget optimizations". The memory budget part and the
   vendor detection part are the interesting parts for Thor.
4. `77c30684` and `e67d18b7` stabilize Vulkan texture uploads and audio
   startup through `RSXOffload`. Small. Read them together with item 2.

Hold this one, do not port it yet:

* `32ed4c9e` "Fix Vulkan pipeline compilation on Adreno". Current upstream
  makes `VK_EXT_shader_uniform_buffer_unsized_array` a hard requirement. The
  Adreno driver does not give it. EmuCoreC makes the extension optional and
  emits a concrete array bound through a new `vk::ubo_array_dim()`. It also
  adds a subpass self-dependency in `VKRenderPass.cpp` for the feedback case.
  The vendored core contains no `unsized_array` symbol, so the fault does not
  exist here today. The fault arrives at the next core rebase. Keep this
  pointer with the rebase plan.

Do not take these:

* `f83474fa` and `b56e30ff` add an OpenGL ES renderer, including a new
  `OpenGLESCompat.h` of `703` lines. Thor has an Adreno 740 with a complete
  Vulkan path. A second renderer adds surface area and gives no speed.
* The Kotlin app under `app/src/main/java/com/sbro/emucorec/`. It is a
  different application with a different package name.

Open point: nobody measured any of the four items above on Thor. The order
above is a reading order, not a speed claim.

### 2026-08-20 — EmuCoreC, what we took

The survey above named four commits to read. We read all of them, and two more.
The port is host-verified only: every file compiles for `arm64-v8a` and the
full native build links. Nothing ran on Thor, and nothing is measured.

Taken:

1. The ARM64 PPU gateway scratchpad, `8192` to `262144` bytes. EmuCoreC found
   the fault in `d2b993c5` and used 64 KB. We use the same number as our SPU
   gateway. See the note above `PPU_GW_SCRATCH_SIZE`.
2. The Android preflight for RSX-protected guest pages, from `e67d18b7`,
   `77c30684` and `77dc85d0`. `rsx::prepare_guest_read()` and
   `rsx::prepare_guest_write()` resolve protected pages from normal thread
   context, so a fault cannot recurse on the Android signal stack. A mirror in
   `Emu/RSX/Host/MM.cpp` answers "is this page open?" with one atomic load, so
   the hot paths pay almost nothing. ZCULL and two texture-cache paths now use
   the new `rsx::mm_protect_immediate()` to keep the mirror true.
3. The LLVM out-of-memory handler, from `d2b993c5`. LLVM dispatches it apart
   from the fatal handler, and without it an LLVM-reported allocation failure
   dies with an empty log.
4. The PPU compile survival and throttle, from `47220b15`. `ppu_initialize2()`
   now returns a result, uses `try_add` on ARM64, and reports a failed module
   instead of ending the process with it. Under memory pressure a module also
   waits for the other workers, because the worker count from `limit()` is
   fixed at startup. This aims at `docs/arm64/ppu-compile-oom.md`.
5. `fs::error::readonly` now maps to `CELL_EROFS` in `sys_fs_unlink`,
   `sys_fs_truncate` and `sys_fs_utime`.

Not taken, and why:

* The Cubeb switch to OpenSL ES (`e67d18b7`). `android/CMakeLists.txt` sets
  `USE_OPENSL off`, so that backend is not compiled here and the switch would
  fail at `cubeb_init`.
* The block which disables GPU byteswap and hardware deswizzle on Android
  (`77c30684`). It is a behaviour change, not a stability fix, and it would
  undo the Adreno compute work in `d76de5b5c`.
* The OpenGL ES renderer (`f83474fa`, `b56e30ff`). Thor has a complete Vulkan
  path on an Adreno 740.
* Every log-level demotion in `77dc85d0` and `47220b15`. Our log policy is our
  own, and those channels carry evidence for the current sprint.
* The `g_ppu_avoid_strict_fma` retry in `47220b15`. It changes PPU float
  results on the second attempt, and nothing shows that the first attempt fails
  for a reason that weaker FMA would fix.
* The little-core CPU name guard, the FCTIW/FCTID saturation fix, the JIT
  instruction-cache maintenance, the `vm.cpp` log-once, and the vectorised
  index upload with a restart index. This tree already has all five, and its
  versions carry more explanation. See `docs/arm64/codegen.md`,
  `Emu/RSX/Common/BufferUtils.cpp`, and `rpcs3/util/JITLLVM.cpp`.
* The `m_poisoned` engine leak in `d2b993c5`. It guards `~MCJIT` against a
  deadlock. Our `m_engine` and `m_context` already hold no-operation deleters,
  so nothing here destroys the engine and there is nothing to guard.

Follow-up work this survey found. None of it is started:

1. ~~**`VK_EXT_extended_dynamic_state`**~~ Done on 2026-08-21. See the entry
   below.
2. **`VKGSRender::on_vram_exhausted()` while uninterruptible** (`47220b15`).
   Our version asserts and ends the process. EmuCoreC releases what it can
   without a hard sync. The port needs `vk::is_last_ditch_eviction()`, which
   this tree does not have.
3. **The index upload without a restart index.** `untouched_impl` still uses
   the branching `min_max()` helper, which does not vectorise. Our own
   `primitive_restart_impl` shows the branch-free shape that does. EmuCoreC did
   not fix this one either.

### 2026-08-21 — EmuCoreC, extended dynamic state

Follow-up 1 above is done. `VK_EXT_extended_dynamic_state` now moves the
topology, the cull mode, the front face and the three depth states out of the
pipeline object and into the command buffer.

What the port covers, beyond the EmuCoreC commit:

* EmuCoreC's device hunk REPLACES the `VK_EXT_multi_draw` feature query with the
  new one, so their tree stopped asking for multi-draw. Read that hunk before
  you take anything else from `47220b15`. This tree adds the new query beside
  the old one.
* The six entry points come from `vkGetDeviceProcAddr`, and the code asks for
  the `EXT` name first and the Vulkan 1.3 core name second. A loader can export
  one and not the other. If any one of the six is missing, the feature goes off,
  because the pipeline objects and the draw path must agree about who owns
  these states.
* Three places produce pipeline properties, not one: the draw path, the shader
  interpreter preload, and the disk shader cache. All three normalise now. The
  cache matters most: a key built from raw properties never matches a key built
  from normalised ones, and every preloaded pipeline would miss.
* The draw path normalises the freshly decoded properties BEFORE it compares
  them with the current ones. EmuCoreC compares first and normalises after, so
  with the feature live the comparison never succeeds and the pipeline lookup
  runs for every draw with a dirty pipeline configuration.
* `debug.rpcsx.thor.vk_dynamic_state_off = 1` turns the feature off for an A/B
  run on the device. A driver which emulates these states instead of setting
  registers can be slower, and nobody measured this on Thor.

A device log line reports the state: "Extended dynamic state is live." Flipping
the property leaves the old shader cache entries unused, not wrong: the draw
path asks for a different key, misses, and compiles again.

Not measured. The claim is only that the pipeline count falls, and even that is
unverified on hardware.
