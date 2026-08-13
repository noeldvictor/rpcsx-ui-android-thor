#pragma once

// Park an SPU that branches to itself, instead of spinning on `state`.
//
// A gameplay profile of Eternal Sonata, 119,662 samples, puts about **20% of all
// CPU** in two instructions:
//
//     ldr w8, [x19, #0x14]
//     cbz w8, .-4
//
// That is `check_state()` at the top of a chunk, in a chunk that branches to
// itself. `SPULLVMRecompiler.cpp` emits the load and the compare for each
// iteration, and `BR` has no case for `target == m_pos`, so the back edge closes
// a loop with nothing in it. See docs/arm64/jit-emitted-code.md.
//
// Nothing inside such a loop can end it. The loop body is empty, so the only exit
// is `cpu_thread::state`, which something outside the thread writes. The thread
// therefore runs at full issue rate, on a core, until that write happens. A
// `sched_yield` would not help either: it re-queues the thread, keeps it
// runnable, and holds the cluster at a high operating point.
//
//   debug.rpcsx.thor.spu_selfloop_park = <microseconds>   (default 0, which is off)
//
// The value is the timeout for one park. `0` keeps the spin, which is the
// behaviour of every build before this one. **The default is off and the change
// is unmeasured on this device.**
//
// ## The timeout is not optional
//
// Not every writer of `state` notifies it. A park with no timeout would sleep
// until a notify that may never come, so the wait always carries one. The
// timeout bounds the added latency: the thread wakes, re-reads `state` through
// the same `check_state` it always ran, and parks again if there is still
// nothing to do.
//
// ## Parking makes a hang look like idleness
//
// A branch to itself is also what a guest deadlock looks like. Before this
// change a deadlocked SPU burned a core, which is ugly and visible. After it, the
// same deadlock is a quiet sleeping thread. So the park has to leave a record.
//
// **The record is written on entry, not on completion.** CLAUDE.md states the
// problem exactly: "Every counter in this fork is incremented on completion, so
// none of them can see a hang." Three instruments were armed against the Eternal
// Sonata deadlock and all three logged nothing, which looks the same as code that
// never ran. `entries` and `last_pc` are written **before** the wait, so a
// watchdog reading `entries - exits > 0` sees a park that is happening now, and
// `last_pc` says where. That is the record-on-entry slot the same file asks for.

#include <cstdlib>

#include "util/atomic.hpp"
#include "util/types.hpp"

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace thor {

struct spu_selfloop_park_t {
  // Written before the wait, so a live park is visible while it happens.
  atomic_t<u64> entries{0};
  atomic_t<u32> last_pc{0};

  // Written after the wait. entries - exits is the number of threads parked now.
  atomic_t<u64> exits{0};
};

inline spu_selfloop_park_t g_spu_selfloop_park{};

// The timeout for one park, in microseconds. 0 turns the park off.
inline u64 spu_selfloop_park_us() {
  static const u64 value = []() -> u64 {
#if defined(__ANDROID__)
    char buf[PROP_VALUE_MAX]{};
    const int length =
        __system_property_get("debug.rpcsx.thor.spu_selfloop_park", buf);

    const char *v = length > 0 ? buf : std::getenv("RPCSX_THOR_SPU_SELFLOOP_PARK");
#else
    const char *v = std::getenv("RPCSX_THOR_SPU_SELFLOOP_PARK");
#endif
    if (!v) {
      return 0;
    }

    char *end = nullptr;
    const unsigned long parsed = std::strtoul(v, &end, 10);

    // A malformed value keeps the spin. Do not guess a timeout.
    if (end == v || (end && *end) || parsed > 1000000ul) {
      return 0;
    }

    return static_cast<u64>(parsed);
  }();

  return value;
}

inline bool spu_selfloop_park_enabled() { return spu_selfloop_park_us() != 0; }

} // namespace thor
