# Thor Android Thread Identity Race Fix

Date: 2026-07-18

Status: host-verified, uninstalled, device-unmeasured

Classification: current-upstream Android stability and low-overhead candidate

## Goal

Remove a native thread-handle publication race and make thread identifiers
stable and inexpensive after first use. This is generic runtime infrastructure:
it does not add workers, increase polling, alter emulation semantics, or enable
a title-specific path. The Thor was deliberately not contacted.

## Current-Upstream Finding

Fresh official RPCS3 origin/master at
a7d90852dd02efcceb539968667201dbc9799cb0 contains:

- 4e49c5319dda50d56b7ef32bdbc31a61059b6652,
  Avoid using pthread_self() partially;
- 5d62ee4b4270558fe75b5bcf8383bcb89d1b393e,
  Fix possible multi-platform race-condition (depending on kernel).

The Android fork still passed m_thread.raw() to pthread_create(), allowing the
pthread implementation to write through storage owned by an atomic object.
The new thread also unconditionally released pthread_self() into that object
during initialization. Which write happened first depended on scheduling.

The fork's thread_ctrl::get_tid() also queried the platform on every call and
returned a pthread handle as Android's diagnostic thread ID. Current upstream
resolves the kernel TID once per native thread and caches it in thread-local
storage.

## Android Adaptation

Thread.cpp now lets pthread_create() write into a local pthread_t and publishes
its bit representation through compare_and_swap_test(). The new thread uses
the same compare/exchange protocol, so either side can safely win without an
unsynchronized raw write.

This fork deliberately gives Android and Apple native threads an 8 MiB stack.
That local behavior is preserved: only the destination passed to
pthread_create() changed. Apple's upstream wait-before-initialize rule is also
retained.

Android get_tid() now evaluates pthread_gettid_np(pthread_self()) once per
thread through static thread_local storage. The atomic wait handle records the
same kernel-TID representation, matching current upstream.

tools/test_thor_android_thread_identity.ps1 requires:

- the Android 8 MiB stack attribute;
- local pthread_t destinations for attributed and default creation;
- atomic parent/child handle publication;
- the Apple initialization wait;
- cached Android kernel TIDs;
- matching atomic-wait ownership IDs;
- absence of pthread_create writes through m_thread.raw() and unconditional
  m_thread.release(pthread_self()).

Rollback is the single source/test/documentation commit. There is no property,
cache schema, persistent state, or game profile to migrate.

## Host Verification

No ADB query, install, launch, temperature read, or other Thor action ran.

- Focused Android thread identity contract: pass.
- All 31 tools/test_thor_*.ps1 contracts: pass.
- Optimized ARM64 native compile/link: BUILD SUCCESSFUL in 64 seconds.
- ARM64-only optimized ThorTest APK: BUILD SUCCESSFUL in 14 seconds.
- Exact APK/ABI/merged-core contract: pass.
- Packaged ARM64 core exactly matches the stripped ARM64 core.
- Export surface: 34 defined dynamic symbols, 590 explicit relocations,
  392 jump slots, and 44,285 encoded relocation bytes.
- The kernel-TID/TLS path adds three explicit relocations and one jump slot
  relative to the preceding SELB candidate; all counts remain well below the
  enforced limits.
- git diff --check: pass before documentation finalization.

Exact host-only artifacts:

- APK:
  app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk
- APK size: 73,697,234 bytes
- APK SHA-256:
  05DDE070BF459FDD1D66633054E0D18DE8CDFD2945B7721A31F76AC98E817E60
- merged ARM64 core size: 1,306,298,120 bytes
- merged ARM64 core SHA-256:
  C30FB8E72ACF7EB1002403E78E147AE440BAA38EA39A93738B0AB0000A14EC9F
- stripped/packaged core size: 63,137,016 bytes
- stripped/packaged core SHA-256:
  178B010A1D169ED2357F39D5B12F6221E6AD4BBE02DB41B35A58717881D81EF7

## Claim Boundary

This removes undefined/racy handle publication and avoids repeated platform-ID
resolution after each thread's first get_tid() call. It does not prove that
the observed flicker was thread-related, and it is not a measured gameplay,
FPS, frame-time, temperature, or power improvement. No Thor speed, thermal,
flicker, field, menu, battle, or stability credit is allowed without a later
independently cool matched device proof.
