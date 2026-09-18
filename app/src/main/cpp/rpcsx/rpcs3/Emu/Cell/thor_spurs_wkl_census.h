#pragma once

// SPURS WORKLOAD CENSUS (2026-09-08).
//
// WHY. Round L put the six SPURS kernel threads on the three Cortex-A510 cores
// and Transformers combat fell from 19.8 to 6.4 FPS with the same draws per
// frame. SPU work is on the frame's chain, and the only SPU threads this title
// creates are CellSpursKernel0..5, so the work is a SPURS workload. The
// CellSpurs instance in guest memory names every workload the PPU added
// (nameClass and nameInstance strings, from cellSpursAddWorkloadWithAttribute)
// and holds its live state: ready count, contention, max contention, priority
// per SPU. This prints that table from the perf monitor, so the SPU profile's
// hot addresses and the render thread's wait can be matched to a named
// workload.
//
// LAYOUT. Raw offsets from ps3fw/include/rpcsx/fw/ps3/cellSpurs.h (CellSpurs,
// 0x2000 bytes, SPURS1 first sixteen workloads). This header does not include
// it, for the same reason SPUThread.cpp does not.
//
// COST. Nothing unless the property is set; one page of guest reads per report.
//
//   debug.rpcsx.thor.spurs_wkl_census = 1

#include "util/types.hpp"
#include "util/StrFmt.h"
#include "Emu/Memory/vm.h"
#include "Emu/IdManager.h"
#include "Emu/Cell/SPUThread.h"

#include <string>

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace thor::spurs_wkl_census
{
	inline bool enabled()
	{
		static const bool s_enabled = []() -> bool
		{
#ifdef __ANDROID__
			char value[PROP_VALUE_MAX]{};

			if (__system_property_get("debug.rpcsx.thor.spurs_wkl_census", value) > 0 && value[0])
			{
				return value[0] != '0';
			}
#endif
			return false;
		}();

		return s_enabled;
	}

	// The first kernel thread that knows its SPURS instance names it for all.
	inline u32 find_spurs_addr()
	{
		u32 found = 0;

		idm::select<named_thread<spu_thread>>([&](u32, spu_thread& spu)
		{
			if (!found && spu.spurs_addr != 0 && spu.spurs_addr != 0u - 0x80u && vm::check_addr(spu.spurs_addr, 0, 0x2000))
			{
				found = spu.spurs_addr;
			}
		});

		return found;
	}

	inline std::string read_guest_string(u32 ea, u32 max_len = 40)
	{
		std::string out;

		if (!ea || !vm::check_addr(ea, 0, 1))
		{
			return out;
		}

		const char* p = vm::_ptr<const char>(ea);

		for (u32 i = 0; i < max_len && vm::check_addr(ea + i, 0, 1); i++)
		{
			const char c = p[i];

			if (!c)
			{
				break;
			}

			out += (c >= 0x20 && c < 0x7f) ? c : '?';
		}

		return out;
	}

	// Appends one line per live workload to out. Returns false when there is no
	// instance to read.
	inline bool report(std::string& out)
	{
		const u32 sa = find_spurs_addr();

		if (!sa)
		{
			return false;
		}

		const u8* const base = vm::_ptr<const u8>(sa);

		const auto rd8 = [&](u32 off) -> u32 { return base[off]; };
		const auto rd16 = [&](u32 off) -> u32 { return (u32{base[off]} << 8) | base[off + 1]; };
		const auto rd32 = [&](u32 off) -> u32 { return (u32{base[off]} << 24) | (u32{base[off + 1]} << 16) | (u32{base[off + 2]} << 8) | base[off + 3]; };
		const auto rd64lo = [&](u32 off) -> u32 { return rd32(off + 4); }; // low half of a 64-bit BE pointer

		fmt::append(out, "Thor SPURS WKL: spurs=0x%08x nspus=%u enabled=0x%08x signal1=0x%04x flagReceiver=%u idling=%u",
			sa, rd8(0x76), rd32(0xB0), rd16(0x70), rd8(0x77), rd8(0x73));

		for (u32 wid = 0; wid < 16; wid++)
		{
			const u32 state = rd8(0x80 + wid);

			if (state == 0)
			{
				continue;
			}

			const u32 info = 0xB00 + wid * 32;
			const u32 name = 0xE00 + wid * 16;
			std::string prio;

			for (u32 s = 0; s < 8; s++)
			{
				fmt::append(prio, "%x", rd8(info + 0x18 + s));
			}

			fmt::append(out, "\n  wid=%2u state=%u ready=%u cont=%u/%u min=%u pending=%u prio=%s pm=0x%08x size=0x%x class='%s' inst='%s'",
				wid, state, rd8(0x00 + wid), rd8(0x20 + wid), rd8(0x50 + wid), rd8(0x40 + wid), rd8(0x30 + wid), prio,
				rd64lo(info + 0x00), rd32(info + 0x10),
				read_guest_string(rd64lo(name + 0)), read_guest_string(rd64lo(name + 8)));
		}

		return true;
	}
} // namespace thor::spurs_wkl_census
