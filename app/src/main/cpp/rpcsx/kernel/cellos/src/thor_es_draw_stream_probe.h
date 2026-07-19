#pragma once

#include <string_view>

class ppu_thread;

#if defined(__ANDROID__) && !defined(RPCSX_THOR_DRAW_STREAM_PROBE)
static FORCE_INLINE constexpr void
thor_es_draw_stream_probe_tty(const ppu_thread &, std::string_view) noexcept {}
#else
void thor_es_draw_stream_probe_tty(const ppu_thread &ppu,
                                   std::string_view message);
#endif
