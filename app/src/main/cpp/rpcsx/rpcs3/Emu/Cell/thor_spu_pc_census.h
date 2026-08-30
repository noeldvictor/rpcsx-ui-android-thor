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
#include "Emu/Cell/timers.hpp"
#include "Emu/Cell/thor_spurs_event_wait_probe.h"
#include "Emu/IdManager.h"
#include "cellos/sys_spu.h"
#include "util/types.hpp"

#include <array>
#include <atomic>
#include <cstdlib>
#include <cstring>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

namespace thor
{
	struct transformers_physx_task_snapshot
	{
		u32 taskset = 0;
		u32 task_id = 0;
		u32 elf = 0;
		u64 arm_time_us = 0;
	};

	inline std::atomic<u32> s_transformers_physx_taskset{0};
	inline std::atomic<u32> s_transformers_physx_task_id{0};
	inline std::atomic<u32> s_transformers_physx_elf{0};
	inline std::atomic<u64> s_transformers_physx_arm_time_us{0};

	inline void arm_transformers_physx_spu_census(u32 taskset, u32 task_id, u32 elf) noexcept
	{
		s_transformers_physx_task_id.store(task_id, std::memory_order_relaxed);
		s_transformers_physx_elf.store(elf, std::memory_order_relaxed);
		s_transformers_physx_arm_time_us.store(get_system_time(), std::memory_order_relaxed);
		s_transformers_physx_taskset.store(taskset, std::memory_order_release);
	}

	inline transformers_physx_task_snapshot get_transformers_physx_task_snapshot() noexcept
	{
		transformers_physx_task_snapshot result{};
		result.taskset = s_transformers_physx_taskset.load(std::memory_order_acquire);
		result.task_id = s_transformers_physx_task_id.load(std::memory_order_relaxed);
		result.elf = s_transformers_physx_elf.load(std::memory_order_relaxed);
		result.arm_time_us = s_transformers_physx_arm_time_us.load(std::memory_order_relaxed);
		return result;
	}

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

	inline void spu_edge_pc_census_tick()
	{
		if (!spu_pc_census_enabled())
		{
			return;
		}

		// The performance monitor starts before the SPU ID map. Do not call
		// idm::select until the map exists. An early select can read the fixed-
		// object poison pattern as an SPU pointer during guest startup.
		if (!g_fxo->try_get<id_manager::id_map<named_thread<spu_thread>>>())
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

	inline bool fmod_event_wait_census_enabled()
	{
#ifdef ANDROID
		char value[PROP_VALUE_MAX]{};

		if (__system_property_get("debug.rpcsx.thor.fmod_event_wait_trace", value) > 0)
		{
			return value[0] && value[0] != '0';
		}
#endif

		if (const char* value = std::getenv("RPCSX_THOR_FMOD_EVENT_WAIT_TRACE"))
		{
			return value[0] && value[0] != '0';
		}

		return false;
	}

	inline void spu_fmod_event_wait_census_tick()
	{
		if (!fmod_event_wait_census_enabled())
		{
			return;
		}

		if (!g_fxo->try_get<id_manager::id_map<named_thread<spu_thread>>>())
		{
			return;
		}

		static constexpr u32 max_samples = 16;
		static u32 s_sample = 0;

		if (s_sample >= max_samples)
		{
			return;
		}

		const auto wait = get_fmod_event_wait_snapshot();

		if (!wait.active || !wait.taskset)
		{
			return;
		}

		const u32 sample = s_sample + 1;
		u32 matches = 0;

		idm::select<named_thread<spu_thread>>([&](u32 id, named_thread<spu_thread>& spu)
			{
				const u32 taskset = static_cast<u32>(+spu._ref<u64>(0x27b8));

				if (taskset != wait.taskset)
				{
					return;
				}

				matches++;
				const auto tname = spu.spu_tname.load();
				const char* name = tname ? tname->c_str() : "";
				const u32 state = spu.state.load().toUnderlying();
				const u32 group_state = spu.group ? static_cast<u32>(spu.group->run_state.load()) : umax;
				const u32 spurs_running = spu.group ? spu.group->spurs_running.load() : 0;

				spu_log.error("Thor FMOD PC sample=%u id=0x%08x spu=%u taskset=0x%08x task=%u "
					"pc=0x%05x op=0x%08x base=0x%05x lr=0x%05x sp=0x%05x "
					"r3=0x%08x r4=0x%08x r5=0x%08x mfc=0x%02x ea=0x%08x "
					"out=%u intr=%u in=%u state=0x%08x group=%u spursrun=%u thread='%s'",
					sample, id, spu.index, taskset, +spu._ref<u32>(0x27d4),
					spu.pc, +spu._ref<u32>(spu.pc), spu.base_pc, spu.gpr[0]._u32[3],
					spu.gpr[1]._u32[3], spu.gpr[3]._u32[3], spu.gpr[4]._u32[3],
					spu.gpr[5]._u32[3], +spu.ch_mfc_cmd.cmd, +spu.ch_mfc_cmd.eal,
					spu.ch_out_mbox.get_count(), spu.ch_out_intr_mbox.get_count(),
					spu.ch_in_mbox.get_count(), state, group_state, spurs_running, name);
			});

		if (!matches)
		{
			return;
		}

		const u64 now = get_system_time();
		const u64 active_age_us = wait.arm_time_us && now >= wait.arm_time_us
			? now - wait.arm_time_us : 0;
		spu_log.error("Thor FMOD EFWAIT CENSUS: sample=%u sequence=%u ppu=0x%08x "
			"flag=0x%08x taskset=0x%08x matches=%u request=0x%04x mode=%u slot=%u "
			"active_age_us=%llu dispatch=%u/%u delta=%u queue=0x%08x port=%u",
			sample, wait.sequence, wait.ppu_id, wait.event_flag, wait.taskset, matches,
			wait.requested, wait.mode, wait.slot,
			static_cast<unsigned long long>(active_age_us), wait.event_dispatch_total,
			wait.event_dispatch_at_arm, wait.event_dispatch_total - wait.event_dispatch_at_arm,
			wait.event_queue, wait.event_port);
		s_sample++;
	}

	inline void spu_transformers_physx_pc_census_tick()
	{
		if (!spu_pc_census_enabled())
		{
			return;
		}

		if (!g_fxo->try_get<id_manager::id_map<named_thread<spu_thread>>>())
		{
			return;
		}

		const auto task = get_transformers_physx_task_snapshot();

		if (!task.taskset || task.elf != 0x018c1000u)
		{
			return;
		}

		static constexpr u32 max_samples = 16;
		static constexpr u32 max_wait_samples = 16;
		static u32 s_sample = 0;
		static u32 s_wait_sample = 0;

		if (s_sample >= max_samples)
		{
			return;
		}

		const u32 sample = s_sample + 1;
		u32 matches = 0;

		idm::select<named_thread<spu_thread>>([&](u32 id, named_thread<spu_thread>& spu)
			{
				const u32 taskset = static_cast<u32>(+spu._ref<u64>(0x27b8));
				const u32 task_id = +spu._ref<u32>(0x27d4);

				if (taskset != task.taskset || task_id != task.task_id)
				{
					return;
				}

				matches++;
				const auto tname = spu.spu_tname.load();
				const char* name = tname ? tname->c_str() : "";
				const u32 state = spu.state.load().toUnderlying();
				const u32 group_state = spu.group ? static_cast<u32>(spu.group->run_state.load()) : umax;
				const u32 spurs_running = spu.group ? spu.group->spurs_running.load() : 0;

				spu_log.error("Thor PHYSX PC sample=%u id=0x%08x spu=%u taskset=0x%08x task=%u "
					"pc=0x%05x op=0x%08x base=0x%05x lr=0x%05x sp=0x%05x "
					"r3=0x%08x r4=0x%08x r5=0x%08x mfc=0x%02x ea=0x%08x "
					"out=%u intr=%u in=%u state=0x%08x group=%u spursrun=%u "
					"blocks=%llu recover=%llu failures=%llu hash=0x%016llx interp=%u thread='%s'",
					sample, id, spu.index, taskset, task_id, spu.pc, +spu._ref<u32>(spu.pc),
					spu.base_pc, spu.gpr[0]._u32[3], spu.gpr[1]._u32[3], spu.gpr[3]._u32[3],
					spu.gpr[4]._u32[3], spu.gpr[5]._u32[3], +spu.ch_mfc_cmd.cmd,
					+spu.ch_mfc_cmd.eal, spu.ch_out_mbox.get_count(),
					spu.ch_out_intr_mbox.get_count(), spu.ch_in_mbox.get_count(), state,
					group_state, spurs_running, spu.block_counter, spu.block_recover,
					spu.block_failure, spu.block_hash, spu.interp_fallback ? 1 : 0, name);
			});

		if (matches)
		{
			s_sample++;
			return;
		}

		if (!s_sample && s_wait_sample < max_wait_samples)
		{
			const u64 now = get_system_time();
			const u64 active_age_us = task.arm_time_us && now >= task.arm_time_us
				? now - task.arm_time_us : 0;
			s_wait_sample++;
			spu_log.error("Thor PHYSX PC WAIT sample=%u taskset=0x%08x task=%u elf=0x%08x "
				"active_age_us=%llu matches=0", s_wait_sample, task.taskset, task.task_id,
				task.elf, static_cast<unsigned long long>(active_age_us));
		}
	}

	inline void spu_pc_census_tick()
	{
		spu_edge_pc_census_tick();
		spu_fmod_event_wait_census_tick();
		spu_transformers_physx_pc_census_tick();
	}
} // namespace thor
