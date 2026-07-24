#pragma once

class ppu_thread;

#if defined(__ANDROID__) && !defined(RPCSX_THOR_SPURS_PROBE)
static FORCE_INLINE constexpr bool thor_spurs_probe_enabled() noexcept {
  return false;
}

#define THOR_SPURS_PROBE_LOG_PPU_WAIT(...) ((void)0)

#else
bool thor_spurs_probe_enabled() noexcept;

void thor_spurs_probe_log_ppu_wait(const char* op, ppu_thread& ppu,
                                   u32 object_id, u64 timeout, u64 detail0,
                                   u64 detail1, s32 result);
#define THOR_SPURS_PROBE_LOG_PPU_WAIT(...) \
  thor_spurs_probe_log_ppu_wait(__VA_ARGS__)

#endif
