#pragma once

// Whether one thread claims the LLVM compilation of an SPU item.
//
// `spu_runtime::add_empty()` gives back an existing item when the caller
// registers an identical program, and it does not say that it did not insert.
// The entry-point check in `spu_llvm_recompiler::compile()` then passes, because
// the entry point is also the same. So each thread that reaches the same uncached
// program compiles it again, with its own LLVM instance. The threads race the
// publication of `compiled` and the rebuild of the ubertrampoline.
//
// ARMSX3 found this and fixed it: their commit `1847433eb`. They measured up to
// five concurrent compilations of one item, about 790 collisions for each boot,
// and about two thirds of all cold compilation work as duplicates. Cold-boot SPU
// compilation fell from about 12,900 blocks to 3,900.
//
//   debug.rpcsx.thor.spu_compile_claim = 0   (default 1)
//
// **The default is 1, which is the fixed behaviour.** The gate exists to make the
// two arms measurable from one APK. The installed APK before this change is three
// days older and carries other work, so a before-and-after across two builds
// cannot attribute anything to this change alone. That confound is the reason for
// the gate, and this fork has recorded the same class of error more than once.
//
// Set the property to 0 to get the old behaviour, where every thread compiles the
// same item. Read the count from `SPU Runtime: Built N functions.` in RPCSX.log
// for each arm, on a cold cache. A warm boot compiles cached programs before SPU
// execution starts, one presentation for each program, so a warm boot cannot see
// this and both arms will agree.
//
// The property is read once into a static. This is not a hot path: it runs once
// for each compile, not once for each instruction, so a function-local static is
// safe here. `thor_spu_branch_extract.h` explains why the branch lowering could
// not use one.

#include <cstdlib>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace thor {
inline bool spu_compile_claim() {
  static const bool enabled = []() -> bool {
#if defined(__ANDROID__)
    char value[PROP_VALUE_MAX]{};
    const int length =
        __system_property_get("debug.rpcsx.thor.spu_compile_claim", value);

    const char *v =
        length > 0 ? value : std::getenv("RPCSX_THOR_SPU_COMPILE_CLAIM");
#else
    const char *v = std::getenv("RPCSX_THOR_SPU_COMPILE_CLAIM");
#endif
    if (!v) {
      return true;
    }

    // Only an explicit off turns it off. An unset or malformed value keeps the
    // fixed behaviour, so a typo cannot quietly ship the race.
    return !(v[0] == '0' || v[0] == 'n' || v[0] == 'N' || v[0] == 'f' ||
             v[0] == 'F');
  }();

  return enabled;
}
} // namespace thor
