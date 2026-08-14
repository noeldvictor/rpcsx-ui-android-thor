#pragma once

// Which AArch64 spelling the eight SPU branch lowerings use.
//
// `BIZ`, `BINZ`, `BIHZ`, `BIHNZ`, `BRZ`, `BRNZ`, `BRHZ` and `BRHNZ` each carry a
// fast path under the comment `// Check sign bit instead (optimization)`. The
// fast path collapses all 16 bytes of the branch register to a 16-bit movemask.
// It then tests one bit of the mask. On x86 that is `PMOVMSKB` plus `TEST`, two
// instructions, and it is cheaper than a lane extract.
//
// AArch64 has no movemask, so LLVM builds one. The word form costs 8
// instructions: `adrp`, `ldr q`, `and`, `ext`, `zip1`, `addv`, `fmov`, `tbnz`.
// The halfword form costs 9. The same function already carries the direct
// spelling as its fallback: `extract(get_vr(op.rt), 3)` for a word, and
// `extract(get_vr<u16[8]>(op.rt), 6)` for a halfword. That spelling costs 2
// instructions: `umov` plus `cbz`. The saving is 6 instructions for a word and 7
// for a halfword, once the shared `adrp` is accounted.
//
// The two spellings compute the same predicate only because of the `sext` guard
// above each fast path. The guard forces every lane to all-zeros or all-ones.
// Over that population the equivalence is exhaustive: 0 mismatches over all 16
// guarded word patterns, and 0 over all 65,536 guarded byte patterns. Over
// arbitrary bytes the two predicates differ on about half of the inputs. So the
// guard is load-bearing. Do not move either spelling out of the guarded block.
//
//   debug.rpcsx.thor.spu_branch_extract = 0   (default 1)
//
// **MEASURED 2026-08-13, and the default is now 1.** Folklore, booted to its
// title screen, sampling a 60-second window 20 seconds after the first frame, and
// **accepting only windows of 3,500 frames** so both arms describe the same scene
// phase. That gate is not optional here: without it the same configuration gives
// 185 ticks over 1,750 frames and 1,720 over 3,500, because the title screen has
// an attract movie and a menu and a boot lands in whichever.
//
//   extract=0   1702, 1701, 1690 ticks      mean 1697.7
//   extract=1   1685, 1642, 1624, 1647      mean 1649.5
//
// **About 2.8% less CPU at an identical frame count**, with the two ranges not
// overlapping, across two batches run in opposite orders. Six accepted runs, all
// at exactly 3,500 frames.
//
// That is a small number and it is a real one. The mechanism matches: eight
// instructions become two at 1,402 sites, and this is one of the few changes
// tried on this device that **removes** work rather than trading spin for a
// syscall. The ones that traded, the SPU self-loop park and a GETLLAR busy-wait
// of 0, both measured worse.
//
// Set the property to 0 to get the movemask back. docs/arm64/bench-results.md
// holds the method, and docs/arm64/x86-tricks-arm64-answers.md the equivalence
// verification.
//
// Read the property once, and read it out of the compile loop. A function-local
// static costs a guard-variable acquire load on every call. This fork already
// made that mistake once with `get_thor_pause_mode` -- see the comment on
// `pause()` in rx/asm.hpp. `spu_llvm_recompiler` therefore copies the result
// into a member at construction, and the eight sites read the member.
//
// The guard below is `__aarch64__`, which the compiler predefines. It cannot go
// missing per CMake target, unlike `ANDROID`. The same file records what a
// missing `-DANDROID` cost `thor_host_mutex_spin_iters`.

#include <cstdlib>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace thor {
#if defined(__aarch64__)
inline bool spu_branch_extract() {
  static const bool enabled = []() -> bool {
#if defined(__ANDROID__)
    char value[PROP_VALUE_MAX]{};
    const int length =
        __system_property_get("debug.rpcsx.thor.spu_branch_extract", value);

    const char *v =
        length > 0 ? value : std::getenv("RPCSX_THOR_SPU_BRANCH_EXTRACT");
#else
    const char *v = std::getenv("RPCSX_THOR_SPU_BRANCH_EXTRACT");
#endif
    if (!v) {
      return true;
    }

    // Only an explicit off turns it off. An unset or malformed value keeps the
    // measured form, so a typo cannot quietly restore the movemask.
    return !(v[0] == '0' || v[0] == 'n' || v[0] == 'N' || v[0] == 'f' ||
             v[0] == 'F');
  }();

  return enabled;
}
#else
// The movemask is the correct x86 form, so the gate is off at compile time.
inline bool spu_branch_extract() { return false; }
#endif
} // namespace thor
