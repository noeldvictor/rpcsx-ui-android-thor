#pragma once

// How long a PPU lv2 wait spins before it sleeps.
//
// Every blocking lv2 primitive -- cond, event, event_flag, lwcond, lwmutex,
// rwlock, semaphore -- opens its wait with the same loop:
//
//     for (usz i = 0; cpu_flag::signal - ppu.state && i < 50; i++)
//         rx::busy_wait(500);
//
// `rx::busy_wait` spins until the generic timer advances by its argument, and
// CNTFRQ_EL0 on this chip is 19.2 MHz. So 500 ticks is 26 us, and fifty of them
// is 1.3 ms of spinning before the code even looks at `timeout`. `rx::pause()`
// is `YIELD`, which retires as a nop on an SMP core, so that time is spent
// issuing instructions at full rate rather than idling the pipeline.
//
// A symbolized profile of Folklore holding 60.01 fps put 73.9% of all CPU
// cycles in exactly two of these loops -- see docs/arm64/lv2-ppu-spin.md.
//
// The sleep this spin sits in front of is already correct: the same functions
// fall through to `ppu.state.wait(state)` or `lv2_obj::wait_timeout`, both real
// futex waits woken by the signalling store. Nothing here needs WFE. The only
// question is how much spinning is worth doing first, and that is a latency
// trade the device has to answer, so it is a property rather than an edit.
//
//   debug.rpcsx.thor.lv2_spin = <iterations>   (default 50, unchanged)
//
// 0 disables the spin entirely and sleeps immediately. Read the value once per
// wait, never inside the loop: a function-local static costs a guard-variable
// acquire load on every call, and putting one in a hot spin is a mistake this
// fork has already made once (see the pause() comment in rx/asm.hpp).

#include <cstddef>

#if defined(ANDROID)
#include <cstdlib>
#include <sys/system_properties.h>
#endif

namespace thor {
inline std::size_t ppu_spin_iters() {
  static const std::size_t iters = []() -> std::size_t {
#if defined(ANDROID)
    char value[PROP_VALUE_MAX]{};
    const int length = __system_property_get("debug.rpcsx.thor.lv2_spin", value);
    const char *v = length > 0 ? value : std::getenv("RPCSX_THOR_LV2_SPIN");
#else
    const char *v = std::getenv("RPCSX_THOR_LV2_SPIN");
#endif
    if (!v || v[0] < '0' || v[0] > '9') {
      return 50;
    }

    std::size_t parsed = 0;
    for (const char *p = v; *p >= '0' && *p <= '9'; p++) {
      parsed = parsed * 10 + static_cast<std::size_t>(*p - '0');
      if (parsed > 100000) {
        return 50;
      }
    }

    return parsed;
  }();

  return iters;
}
} // namespace thor
