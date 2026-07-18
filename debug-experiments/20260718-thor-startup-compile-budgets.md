# 2026-07-18 Thor Startup Compile Budgets

- Target: AYN Thor / Thor Max, Eternal Sonata `BLUS30161`
- Classification: `host-only gated startup-thermal candidate`
- Device state: not queried, installed, launched, or otherwise contacted
- Result: optimized ARM64 build and all host contracts pass; runtime benefit is
  unmeasured

## Problem

Saved guarded Thor logs put the first rapid silicon rise inside overlapping
optional startup work:

- validated Vulkan cache creation near `0.895 s`;
- bounded RSX load/compile workers beginning near `1.040 s`;
- PPU object loading around `1.80-2.24 s`;
- bounded SPU preload beginning near `2.247 s`;
- two SPU LLVM workers compiling 64 programs through about `2.820 s`; and
- runtime PPU module loading continuing past that point.

Count limits alone do not bound cost: Vulkan pipeline compile time and SPU
program compile time vary substantially by entry. Sleeping between entries
would stretch the same work and could simply delay the thermal trip. This
candidate instead stops issuing optional eager compilation after a measured
host-time slice and leaves untouched work to the existing runtime miss paths.

## Implementation

Two new controls are default-off and active only for `BLUS30161`:

- `debug.rpcsx.thor.rsx_cache_compile_budget_ms=0..5000`
- `debug.rpcsx.thor.spu_cache_compile_budget_ms=0..5000`

Environment fallbacks are:

- `RPCSX_THOR_RSX_CACHE_COMPILE_BUDGET_MS`
- `RPCSX_THOR_SPU_CACHE_COMPILE_BUDGET_MS`

Zero means unbounded/current behavior. Invalid, negative, out-of-range, empty,
or non-Eternal-Sonata requests fail closed to zero.

RSX behavior:

- the default-off path retains the original one-atomic dynamic compile loop;
- with a budget, load/unpack still validates the selected cache entries;
- workers check the deadline before each new driver pipeline submission;
- already-running submissions finish normally;
- untouched entries have no pipeline inserted and use the configured normal
  runtime pipeline creation path; and
- an activation/summary row records attempted and on-demand counts.

SPU behavior:

- every disk-cache identity is registered oldest-first before a budgeted eager
  queue is installed, even when the count limit is otherwise zero/all;
- workers check the shared deadline before analysis/LLVM compilation;
- already-running compilation finishes normally;
- untouched cached identities retain normal LLVM runtime compilation without
  duplicate disk appends; and
- the success count reports only the cached programs actually built.

The budgets are checked between submissions; they are not unsafe cancellation
timers. With two workers, up to two already-running calls can finish after the
deadline.

The guarded route and Eternal Sonata wrapper expose:

- `RsxCacheCompileBudgetMs` / `AndroidRsxCacheCompileBudgetMs`
- `SpuCacheCompileBudgetMs` / `AndroidSpuCacheCompileBudgetMs`

Both default to zero, are captured as requested/effective state, and reset to
zero before launch and after success or failure. The no-launch installer now
records both controls.

## Host verification

No ADB or device action ran.

- `tools/test_thor_startup_compile_budget.ps1`: pass.
- All 25 `tools/test_thor_*.ps1` source contracts: pass.
- Existing RSX preload, SPU preload, Vulkan cache-hit-only, phase-pacing,
  thermal, visual-route, JIT-cache, ARM64-codegen, and logging contracts: pass.
- PowerShell AST parsing for the route, wrapper, and new contract: pass.
- `git diff --check`: pass.
- Optimized ARM64-only build:
  `:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a
  -PbuildBundledRpcsxCore=true`: `BUILD SUCCESSFUL` in `2m21s`.
- Exact ThorTest APK ABI and merged-core identity contract: pass.
- Exact core export surface: 34 defined dynamic symbols, 587 explicit
  relocations, 391 jump slots, 44,245 encoded relocation bytes.
- Packaged core contains both properties and activation/summary strings.

Exact host-only artifacts:

- APK size: `73,580,566` bytes
- APK SHA-256:
  `73C443508B1275AE0A719854BED53DEA3C06DA472E10555CC19C0D38C6F91660`
- merged ARM64 core size: `1,305,844,816` bytes
- merged ARM64 core SHA-256:
  `2B8898DBA8DD55A81803804BECD3BFC8FE8F922396713D9D793D847234704E1C`
- packaged stripped core size: `62,861,528` bytes
- packaged stripped core SHA-256:
  `4796C5A7DFADD1F12C1A947A3B9F10EA4FCBA6B25DF4D84BE4211D0295AF50D3`
- the APK entry exactly matches the stripped-core hash.

## Device proof boundary

This is not a speed, FPS, time-to-title, frame-pacing, flicker, gameplay,
stability, energy, or temperature result. The APK is uninstalled and
`device-unmeasured`.

Do not stack both new controls in the first proof. After a separately cool
install-only round and another independently cool runtime round, isolate the
dominant RSX lane first:

- RSX workers: auto/two
- RSX preload limit: 256
- RSX compile budget: 250 ms
- SPU preload limit: 64
- SPU compile budget: 0/unbounded control
- Vulkan pipeline cache: on
- Vulkan cache-hit-only preload, phase pacing, and ADPF RSX: off

Require the RSX activation/summary rows, exact APK/core identity, comparable
power-policy state, time-to-title or exact guard time, temperature slope, and
fatal/device-loss/unknown-draw scans. Reject it if it only delays the same guard
trip or produces worse title/runtime stutter. A later isolated SPU-budget proof
can use 100 ms only after the RSX result is classified.

Rollback is immediate: leave or set both properties to `0`.
