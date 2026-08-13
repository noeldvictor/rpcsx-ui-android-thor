#pragma once

// Replace the SHUFB fallback TBX2 with a TBL2 and an OR.
//
// `shufb` is the most common operation in this title's compiled SPU corpus:
// **5,794** of them, against 2,203 `fm` and 399 `fi`, counted out of the
// on-device cache rather than guessed.
//
// Measured on the device 2026-08-13, `ns_per_op`, four independent chains:
//
//   | form      | A715 (cpu3) | A710 (cpu6) |
//   | tbl2_tp   | 0.178       | 0.183       |
//   | tbx2_tp   | 0.377       | 0.388       |
//
// **TBX2 costs 2.1x the throughput of TBL2 on the two clusters the SPU threads
// run on.** See docs/arm64/bench-results.md.
//
// The path that pays it is the one which is not `perm_only`, where the selector
// may hold the constant-generating bytes. It emits:
//
//     x = tbl(zero_lut, c >> 4)        // the 0x00 / 0xff / 0x80 constants
//     r = tbx2(x, a, b, idx)           // out-of-range lanes keep x
//
// `zero_lut` is twelve zero bytes then `ff, ff, 80, 80`, so **x is zero exactly
// where the selector is in range**, and TBL2 writes zero exactly where the index
// is out of range. The two facts are complementary, so the fallback can be an OR:
//
//     r = tbl2(a, b, idx) | x
//
// ## The equivalence is exhaustive, not argued
//
// A selector byte has 256 values, so the whole input space was checked for both
// index forms this file affects: `c & 0x9f` at the byteswapped site, and
// `(c & 0x9f) ^ 0x0f` at the other, which is what `BCAX(0x0f, c, 0x60)` computes
// (that identity was checked over the same 256 values). **Zero mismatches**, and
// both invariants hold:
//
//   A. index in range   =>  x == 0
//   B. x is nonzero     =>  index out of range
//
// ## What is proved and what is not
//
// Proved: the two forms compute the same result for every selector byte.
// **Not measured: that the replacement is faster.** It trades one TBX2 for one
// TBL2 plus an ORR. TBX2 costs 0.199 ns more than TBL2 here, and whether an ORR
// costs less than that is the open question. `thor_bench shufb` times both full
// sequences as `seq_tbx2_current` and `seq_tbl2_orr_candidate`.
//
//   debug.rpcsx.thor.shufb_tbl2_or = 1   (default 0)
//
// **The default is 0, so nothing changes by default.** Turn it on only with the
// bench numbers in hand. The emitted IR differs, so the SPU object cache key
// changes with it and stale objects invalidate by construction.

#include <cstdlib>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace thor {
inline bool shufb_tbl2_or() {
  static const bool enabled = []() -> bool {
#if defined(__ANDROID__)
    char value[PROP_VALUE_MAX]{};
    const int length =
        __system_property_get("debug.rpcsx.thor.shufb_tbl2_or", value);

    const char *v = length > 0 ? value : std::getenv("RPCSX_THOR_SHUFB_TBL2_OR");
#else
    const char *v = std::getenv("RPCSX_THOR_SHUFB_TBL2_OR");
#endif
    if (!v) {
      return false;
    }

    return v[0] == '1' || v[0] == 'y' || v[0] == 'Y' || v[0] == 't' ||
           v[0] == 'T';
  }();

  return enabled;
}
} // namespace thor
