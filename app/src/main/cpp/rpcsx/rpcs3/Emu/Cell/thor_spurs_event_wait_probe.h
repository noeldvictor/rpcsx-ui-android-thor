#pragma once

// Keep the latest Transformers EDGE event wait visible to the monitor thread.
//
// The PPU path can block after it arms the event flag. A first-N log cannot
// prove whether a later wait is still armed because boot jobs use the quota.
// This state uses only relaxed atomic stores while the diagnostic property is
// on. The performance monitor reads it with the existing late-loader sample.

#include "util/types.hpp"

#include <atomic>

namespace thor
{
	enum class spurs_event_wait_phase : u32
	{
		idle,
		armed,
		woke,
		returned,
		error,
	};

	struct spurs_event_wait_snapshot
	{
		u32 total = 0;
		u32 active = 0;
		u32 sequence = 0;
		u32 ppu_id = 0;
		u32 requested = 0;
		u32 received = 0;
		u32 mode = 0;
		u32 slot = 0xffffffffu;
		u32 phase = 0;
		u64 arm_time_us = 0;
		u64 wake_time_us = 0;
		u32 event_dispatch_total = 0;
		u32 event_dispatch_at_arm = 0;
		u32 event_dispatch_port = 0xffffffffu;
		u32 event_dispatch_result = 0;
		u32 event_dispatch_queue = 0;
		u64 event_dispatch_time_us = 0;
	};

	struct spurs_event_wait_probe_state
	{
		std::atomic<u32> total{0};
		std::atomic<u32> active{0};
		std::atomic<u32> sequence{0};
		std::atomic<u32> ppu_id{0};
		std::atomic<u32> requested{0};
		std::atomic<u32> received{0};
		std::atomic<u32> mode{0};
		std::atomic<u32> slot{0xffffffffu};
		std::atomic<u32> phase{static_cast<u32>(spurs_event_wait_phase::idle)};
		std::atomic<u64> arm_time_us{0};
		std::atomic<u64> wake_time_us{0};
		std::atomic<u32> event_dispatch_total{0};
		std::atomic<u32> event_dispatch_at_arm{0};
		std::atomic<u32> event_dispatch_port{0xffffffffu};
		std::atomic<u32> event_dispatch_result{0};
		std::atomic<u32> event_dispatch_queue{0};
		std::atomic<u64> event_dispatch_time_us{0};
	};

	inline spurs_event_wait_probe_state g_spurs_event_wait_probe;

	struct fmod_event_wait_snapshot
	{
		u32 total = 0;
		u32 active = 0;
		u32 sequence = 0;
		u32 ppu_id = 0;
		u32 event_flag = 0;
		u32 taskset = 0;
		u32 event_queue = 0;
		u32 event_port = 0xffffffffu;
		u32 requested = 0;
		u32 received = 0;
		u32 mode = 0;
		u32 slot = 0xffffffffu;
		u32 phase = 0;
		u64 arm_time_us = 0;
		u64 wake_time_us = 0;
		u32 event_dispatch_total = 0;
		u32 event_dispatch_at_arm = 0;
		u32 event_dispatch_port = 0xffffffffu;
		u32 event_dispatch_result = 0;
		u32 event_dispatch_queue = 0;
		u64 event_dispatch_time_us = 0;
	};

	struct fmod_event_wait_probe_state
	{
		std::atomic<u32> total{0};
		std::atomic<u32> active{0};
		std::atomic<u32> sequence{0};
		std::atomic<u32> ppu_id{0};
		std::atomic<u32> event_flag{0};
		std::atomic<u32> taskset{0};
		std::atomic<u32> event_queue{0};
		std::atomic<u32> event_port{0xffffffffu};
		std::atomic<u32> requested{0};
		std::atomic<u32> received{0};
		std::atomic<u32> mode{0};
		std::atomic<u32> slot{0xffffffffu};
		std::atomic<u32> phase{static_cast<u32>(spurs_event_wait_phase::idle)};
		std::atomic<u64> arm_time_us{0};
		std::atomic<u64> wake_time_us{0};
		std::atomic<u32> event_dispatch_total{0};
		std::atomic<u32> event_dispatch_at_arm{0};
		std::atomic<u32> event_dispatch_port{0xffffffffu};
		std::atomic<u32> event_dispatch_result{0};
		std::atomic<u32> event_dispatch_queue{0};
		std::atomic<u64> event_dispatch_time_us{0};
	};

	inline fmod_event_wait_probe_state g_fmod_event_wait_probe;

	inline void spurs_event_wait_arm(u32 sequence, u32 ppu_id, u16 requested,
		u32 mode, u32 slot, u64 arm_time_us) noexcept
	{
		auto& state = g_spurs_event_wait_probe;
		state.total.store(sequence, std::memory_order_relaxed);
		state.sequence.store(sequence, std::memory_order_relaxed);
		state.ppu_id.store(ppu_id, std::memory_order_relaxed);
		state.requested.store(requested, std::memory_order_relaxed);
		state.received.store(0, std::memory_order_relaxed);
		state.mode.store(mode, std::memory_order_relaxed);
		state.slot.store(slot, std::memory_order_relaxed);
		state.arm_time_us.store(arm_time_us, std::memory_order_relaxed);
		state.wake_time_us.store(0, std::memory_order_relaxed);
		state.event_dispatch_at_arm.store(state.event_dispatch_total.load(std::memory_order_acquire),
			std::memory_order_relaxed);
		state.phase.store(static_cast<u32>(spurs_event_wait_phase::armed), std::memory_order_relaxed);
		state.active.store(1, std::memory_order_release);
	}

	inline u32 spurs_event_dispatch(u32 port, u32 result, u32 queue, u64 dispatch_time_us) noexcept
	{
		auto& state = g_spurs_event_wait_probe;
		state.event_dispatch_port.store(port, std::memory_order_relaxed);
		state.event_dispatch_result.store(result, std::memory_order_relaxed);
		state.event_dispatch_queue.store(queue, std::memory_order_relaxed);
		state.event_dispatch_time_us.store(dispatch_time_us, std::memory_order_release);
		return state.event_dispatch_total.fetch_add(1, std::memory_order_acq_rel) + 1;
	}

	inline void spurs_event_wait_wake(u32 slot, u16 received, u64 wake_time_us) noexcept
	{
		auto& state = g_spurs_event_wait_probe;
		state.slot.store(slot, std::memory_order_relaxed);
		state.received.store(received, std::memory_order_relaxed);
		state.wake_time_us.store(wake_time_us, std::memory_order_relaxed);
		state.phase.store(static_cast<u32>(spurs_event_wait_phase::woke), std::memory_order_release);
	}

	inline void spurs_event_wait_finish(u32 sequence, u16 received, bool failed) noexcept
	{
		auto& state = g_spurs_event_wait_probe;
		state.total.store(sequence, std::memory_order_relaxed);
		state.sequence.store(sequence, std::memory_order_relaxed);
		state.received.store(received, std::memory_order_relaxed);
		state.phase.store(static_cast<u32>(failed ? spurs_event_wait_phase::error
			: spurs_event_wait_phase::returned), std::memory_order_relaxed);
		state.active.store(0, std::memory_order_release);
	}

	inline spurs_event_wait_snapshot get_spurs_event_wait_snapshot() noexcept
	{
		const auto& state = g_spurs_event_wait_probe;
		spurs_event_wait_snapshot result;
		result.active = state.active.load(std::memory_order_acquire);
		result.total = state.total.load(std::memory_order_relaxed);
		result.sequence = state.sequence.load(std::memory_order_relaxed);
		result.ppu_id = state.ppu_id.load(std::memory_order_relaxed);
		result.requested = state.requested.load(std::memory_order_relaxed);
		result.received = state.received.load(std::memory_order_relaxed);
		result.mode = state.mode.load(std::memory_order_relaxed);
		result.slot = state.slot.load(std::memory_order_relaxed);
		result.phase = state.phase.load(std::memory_order_relaxed);
		result.arm_time_us = state.arm_time_us.load(std::memory_order_relaxed);
		result.wake_time_us = state.wake_time_us.load(std::memory_order_relaxed);
		result.event_dispatch_total = state.event_dispatch_total.load(std::memory_order_acquire);
		result.event_dispatch_at_arm = state.event_dispatch_at_arm.load(std::memory_order_relaxed);
		result.event_dispatch_port = state.event_dispatch_port.load(std::memory_order_relaxed);
		result.event_dispatch_result = state.event_dispatch_result.load(std::memory_order_relaxed);
		result.event_dispatch_queue = state.event_dispatch_queue.load(std::memory_order_relaxed);
		result.event_dispatch_time_us = state.event_dispatch_time_us.load(std::memory_order_acquire);
		return result;
	}

	inline void fmod_event_wait_arm(u32 sequence, u32 ppu_id, u32 event_flag,
		u32 taskset, u32 event_queue, u32 event_port, u16 requested, u32 mode,
		u32 slot, u64 arm_time_us) noexcept
	{
		auto& state = g_fmod_event_wait_probe;
		state.total.store(sequence, std::memory_order_relaxed);
		state.sequence.store(sequence, std::memory_order_relaxed);
		state.ppu_id.store(ppu_id, std::memory_order_relaxed);
		state.event_flag.store(event_flag, std::memory_order_relaxed);
		state.taskset.store(taskset, std::memory_order_relaxed);
		state.event_queue.store(event_queue, std::memory_order_relaxed);
		state.event_port.store(event_port, std::memory_order_relaxed);
		state.requested.store(requested, std::memory_order_relaxed);
		state.received.store(0, std::memory_order_relaxed);
		state.mode.store(mode, std::memory_order_relaxed);
		state.slot.store(slot, std::memory_order_relaxed);
		state.arm_time_us.store(arm_time_us, std::memory_order_relaxed);
		state.wake_time_us.store(0, std::memory_order_relaxed);
		state.event_dispatch_at_arm.store(state.event_dispatch_total.load(std::memory_order_acquire),
			std::memory_order_relaxed);
		state.phase.store(static_cast<u32>(spurs_event_wait_phase::armed), std::memory_order_relaxed);
		state.active.store(1, std::memory_order_release);
	}

	inline u32 fmod_event_dispatch(u32 port, u32 result, u32 queue, u64 dispatch_time_us) noexcept
	{
		auto& state = g_fmod_event_wait_probe;
		state.event_dispatch_port.store(port, std::memory_order_relaxed);
		state.event_dispatch_result.store(result, std::memory_order_relaxed);
		state.event_dispatch_queue.store(queue, std::memory_order_relaxed);
		state.event_dispatch_time_us.store(dispatch_time_us, std::memory_order_release);
		return state.event_dispatch_total.fetch_add(1, std::memory_order_acq_rel) + 1;
	}

	inline void fmod_event_wait_wake(u32 slot, u16 received, u64 wake_time_us) noexcept
	{
		auto& state = g_fmod_event_wait_probe;
		state.slot.store(slot, std::memory_order_relaxed);
		state.received.store(received, std::memory_order_relaxed);
		state.wake_time_us.store(wake_time_us, std::memory_order_relaxed);
		state.phase.store(static_cast<u32>(spurs_event_wait_phase::woke), std::memory_order_release);
	}

	inline void fmod_event_wait_finish(u32 sequence, u16 received, bool failed) noexcept
	{
		auto& state = g_fmod_event_wait_probe;
		state.total.store(sequence, std::memory_order_relaxed);
		state.sequence.store(sequence, std::memory_order_relaxed);
		state.received.store(received, std::memory_order_relaxed);
		state.phase.store(static_cast<u32>(failed ? spurs_event_wait_phase::error
			: spurs_event_wait_phase::returned), std::memory_order_relaxed);
		state.active.store(0, std::memory_order_release);
	}

	inline fmod_event_wait_snapshot get_fmod_event_wait_snapshot() noexcept
	{
		const auto& state = g_fmod_event_wait_probe;
		fmod_event_wait_snapshot result;
		result.active = state.active.load(std::memory_order_acquire);
		result.total = state.total.load(std::memory_order_relaxed);
		result.sequence = state.sequence.load(std::memory_order_relaxed);
		result.ppu_id = state.ppu_id.load(std::memory_order_relaxed);
		result.event_flag = state.event_flag.load(std::memory_order_relaxed);
		result.taskset = state.taskset.load(std::memory_order_relaxed);
		result.event_queue = state.event_queue.load(std::memory_order_relaxed);
		result.event_port = state.event_port.load(std::memory_order_relaxed);
		result.requested = state.requested.load(std::memory_order_relaxed);
		result.received = state.received.load(std::memory_order_relaxed);
		result.mode = state.mode.load(std::memory_order_relaxed);
		result.slot = state.slot.load(std::memory_order_relaxed);
		result.phase = state.phase.load(std::memory_order_relaxed);
		result.arm_time_us = state.arm_time_us.load(std::memory_order_relaxed);
		result.wake_time_us = state.wake_time_us.load(std::memory_order_relaxed);
		result.event_dispatch_total = state.event_dispatch_total.load(std::memory_order_acquire);
		result.event_dispatch_at_arm = state.event_dispatch_at_arm.load(std::memory_order_relaxed);
		result.event_dispatch_port = state.event_dispatch_port.load(std::memory_order_relaxed);
		result.event_dispatch_result = state.event_dispatch_result.load(std::memory_order_relaxed);
		result.event_dispatch_queue = state.event_dispatch_queue.load(std::memory_order_relaxed);
		result.event_dispatch_time_us = state.event_dispatch_time_us.load(std::memory_order_acquire);
		return result;
	}
}
