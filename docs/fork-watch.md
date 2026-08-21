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
