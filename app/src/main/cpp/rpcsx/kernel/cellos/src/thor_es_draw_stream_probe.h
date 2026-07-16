#pragma once

#include <string_view>

class ppu_thread;

void thor_es_draw_stream_probe_tty(const ppu_thread &ppu,
                                   std::string_view message);
