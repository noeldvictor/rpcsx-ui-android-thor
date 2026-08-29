#pragma once

// Sample the guest PC of a loaded edgeZlib SPU task from the monitor thread.
//
// The task can complete its LFQueue reservation operations and then run guest
// code without another observable syscall or MFC atomic operation. This probe
// identifies that code without adding work to the SPU execution path.
//
// The property is off by default. A run records at most 64 timer samples. The
// edgeZlib code signature limits each sample to the matching local-store image.
//
//   debug.rpcsx.thor.spu_pc_census = 1

#include "Emu/Cell/SPUThread.h"
#include "Emu/IdManager.h"
#include "cellos/sys_spu.h"
#include "util/types.hpp"

#include <array>
#include <cstdlib>
#include <cstring>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

namespace thor
{
	inline bool spu_pc_census_enabled()
	{
#ifdef ANDROID
		char value[PROP_VALUE_MAX]{};

		if (__system_property_get("debug.rpcsx.thor.spu_pc_census", value) > 0)
		{
			return value[0] && value[0] != '0';
		}
#endif

		if (const char* value = std::getenv("RPCSX_THOR_SPU_PC_CENSUS"))
		{
			return value[0] && value[0] != '0';
		}

		return false;
	}

	inline void spu_pc_census_tick()
	{
		if (!spu_pc_census_enabled())
		{
			return;
		}

		static constexpr u32 max_samples = 64;
		static u32 s_sample = 0;

		if (s_sample >= max_samples)
		{
			return;
		}

		// Do not use the quota before edgeZlib is in local store. The title loads
		// the task after about 46 seconds, but the monitor ticks every 0.5 second.
		// The old counter used all 64 samples before the task could match.
		const u32 sample = s_sample + 1;
		bool matched = false;

		// These are the first four instructions at edgeZlib LS address 0x3000.
		static constexpr std::array<u8, 16> edge_signature = {
			0x42, 0x47, 0x24, 0x02, 0x43, 0x7e, 0xc0, 0x82,
			0x43, 0x3e, 0x0f, 0x02, 0x42, 0x01, 0x6d, 0x82,
		};

		idm::select<named_thread<spu_thread>>([&](u32 id, named_thread<spu_thread>& spu)
			{
				if (std::memcmp(spu._ptr<u8>(0x3000), edge_signature.data(), edge_signature.size()) != 0)
				{
					return;
				}

				matched = true;

				const auto tname = spu.spu_tname.load();
				const char* name = tname ? tname->c_str() : "";
				const u32 state = spu.state.load().toUnderlying();
				const u32 group_state = spu.group ? static_cast<u32>(spu.group->run_state.load()) : umax;
				const u32 spurs_running = spu.group ? spu.group->spurs_running.load() : 0;

				spu_log.error("Thor EDGE PC sample=%u id=0x%08x spu=%u pc=0x%05x base=0x%05x "
					"lr=0x%05x sp=0x%05x r3=0x%08x r4=0x%08x r5=0x%08x "
					"mfc=0x%02x ea=0x%08x out=%u intr=%u in=%u state=0x%08x "
					"group=%u spursrun=%u blocks=%llu recover=%llu failures=%llu "
					"hash=0x%016llx interp=%u thread='%s'",
					sample, id, spu.index, spu.pc, spu.base_pc, spu.gpr[0]._u32[3],
					spu.gpr[1]._u32[3], spu.gpr[3]._u32[3], spu.gpr[4]._u32[3],
					spu.gpr[5]._u32[3], +spu.ch_mfc_cmd.cmd, +spu.ch_mfc_cmd.eal,
					spu.ch_out_mbox.get_count(), spu.ch_out_intr_mbox.get_count(),
					spu.ch_in_mbox.get_count(), state, group_state, spurs_running,
					spu.block_counter, spu.block_recover, spu.block_failure, spu.block_hash,
					spu.interp_fallback ? 1 : 0, name);
			});

		if (matched)
		{
			s_sample++;
		}
	}
} // namespace thor
