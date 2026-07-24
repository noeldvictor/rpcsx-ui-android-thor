# Thor disabled SPURS-probe argument elision

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in hot PPU wait syscalls,
including Eternal Sonata `BLUS30161`. Thor was not contacted.

## Baseline

Normal Android builds compile the optional SPURS wait logger as an empty
`constexpr` function. C++ still evaluates arguments before making that
optimized-away call. Three hot syscall sites therefore retained an acquire
load whose value was discarded:

- `sys_timer_usleep`: `(+ppu.state).raw()`;
- `sys_semaphore_wait`: `+sem->val`; and
- `sys_semaphore_post`: `+sem->val`.

The predecessor merged core was
`7C40DA22E05904DF8197C89304B93E799D49A4FFC6B280205BEB9EAF37A817DD`,
1,304,324,368 bytes. Its linked ARM64 functions contained one `LDAR wzr`
each:

| Function | Predecessor size | Discarded acquire loads |
|---|---:|---:|
| `sys_timer_usleep` | `0x4ac` | 1 |
| `sys_semaphore_wait` | `0x6dc` | 1 |
| `sys_semaphore_post` | `0x74c` | 1 |
| `sys_event_queue_receive` | `0x794` | 0 |

## Change

The default-off Android header now defines
`THOR_SPURS_PROBE_LOG_PPU_WAIT(...)` as `((void)0)`. Because the preprocessor
discards the arguments, normal builds cannot evaluate diagnostic-only atomic
loads. Explicit `RPCSX_THOR_SPURS_PROBE` and desktop builds define the same
macro as a forwarding call to `thor_spurs_probe_log_ppu_wait`, preserving all
nine diagnostic hooks and their original arguments.

No syscall result, wait, notification, timeout, guest-visible ordering, or
diagnostic-on behavior changed. The event-queue hooks use the same macro even
though linked code already discarded all their arguments; this prevents future
diagnostic arguments from leaking into the normal hot path.

Official RPCS3 `master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` remains the upstream reference.
This is a local disabled-instrumentation code-generation fix.

## Exact ARM64 proof

The successor merged core is
`CA4D4B933D35DAEA4298FEDBFE5E7D08A46437E9A7ACE1691C23655BC236C42F`,
1,304,323,264 bytes: 1,104 bytes smaller than the predecessor. Exact linked
symbol and disassembly inspection gives:

| Function | Successor size | Change | Discarded acquire loads |
|---|---:|---:|---:|
| `sys_timer_usleep` | `0x49c` | -16 bytes | 0 |
| `sys_semaphore_wait` | `0x6cc` | -16 bytes | 0 |
| `sys_semaphore_post` | `0x73c` | -16 bytes | 0 |
| `sys_event_queue_receive` | `0x794` | unchanged | 0 |

Saved clean Windows route syscall counts conservatively imply:

| Route | `usleep` | sem wait | sem post | Removed acquire loads |
|---|---:|---:|---:|---:|
| Title | 79,952 | 35,152 | 35,149 | 150,253 |
| First battle | 245,726 | 119,823 | 119,820 | 485,369 |
| Options | 258,641 | 50,059 | 50,056 | 358,756 |
| Total | 584,319 | 205,034 | 205,025 | 994,378 |

The count excludes 75,549 event-receive calls because their predecessor
symbol had no discarded acquire load. It also does not claim FPS, power, or
temperature improvement.

## Verification

Passed:

- Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor linked ARM64 symbol and disassembly comparison;
- targeted diagnostic-on `clang++ -fsyntax-only
  -DRPCSX_THOR_SPURS_PROBE=1` checks for the timer call sites and probe
  implementation;
- source contract proving argument discard in normal Android, forwarding in
  diagnostic/desktop builds, and all nine restorable PPU hooks;
- ThorTest ARM64-only APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK:
  `896E0F8F0234ACB490B356968042B5C82239E022E7110B88C2DF4DF5163CDA87`,
  72,837,436 bytes.
- Merged ARM64 core:
  `CA4D4B933D35DAEA4298FEDBFE5E7D08A46437E9A7ACE1691C23655BC236C42F`,
  1,304,323,264 bytes.
- Packaged ARM64 core:
  `0F2EA7B8BAEC9C1FE23F4F40F8BDFFC2CF5F4F9962DF0D86F0160290CB2C54DE`,
  62,989,112 bytes.
- APK native entry matches the packaged-core hash and size exactly.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, stability, power, flicker, or temperature credit.
