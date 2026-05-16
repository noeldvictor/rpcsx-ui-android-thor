#pragma once

#include "rx/asm.hpp"
#include "util/types.hpp"

#include <array>
#include <atomic>
#include <cstdlib>

#ifdef ANDROID
#include <android/log.h>
#include <sys/system_properties.h>
#endif

namespace thor_wait
{
	enum class site : u32
	{
		spu_pc_acquire,
		spu_dma_reservation,
		spu_accurate_store,
		spu_putunc_abandon,
		spu_putunc_lock,
		spu_getllar,
		spu_getllar_retry,
		spu_eventstat,
		spu_event_lock,
		spu_channel_pop,
		spu_channel_push,
		spu_channel4_pop,
		rsx_fifo_cache_fill,
		vm_range_lock,
		vm_passive_lock,
		vm_writer_lock,
		vm_reservation_lock,
		vm_reservation_shared,
		cpu_register_slot,
		cpu_suspend_wait,
		semaphore_spin,
		mutex_shared,
		mutex_exclusive,
		mutex_upgrade,
		mutex_unlock,
		count
	};

	struct site_stats
	{
		std::atomic<u64> calls{0};
		std::atomic<u64> cycles{0};
	};

	inline std::array<site_stats, static_cast<usz>(site::count)> g_stats{};
	inline std::atomic<u64> g_total_calls{0};

	inline u32 parse_interval(const char* value) noexcept
	{
		if (!value || value[0] == '\0' || value[0] == '0' || value[0] == 'o' || value[0] == 'O' ||
			value[0] == 'f' || value[0] == 'F' || value[0] == 'd' || value[0] == 'D')
		{
			return 0;
		}

		if (value[0] >= '1' && value[0] <= '9')
		{
			const auto parsed = std::strtoul(value, nullptr, 10);
			return parsed >= 1000 ? static_cast<u32>(parsed) : 1'000'000u;
		}

		if (value[0] == 'v' || value[0] == 'V')
		{
			return 100'000u;
		}

		return 1'000'000u;
	}

	inline u32 interval() noexcept
	{
		static const u32 value = []() noexcept
		{
#ifdef ANDROID
			char prop[PROP_VALUE_MAX]{};
			const int length = __system_property_get("debug.rpcsx.thor.wait_profiler", prop);
			if (length > 0)
			{
				return parse_interval(prop);
			}
#endif

			return parse_interval(std::getenv("RPCSX_THOR_WAIT_PROFILER"));
		}();

		return value;
	}

	inline u64 calls(site id) noexcept
	{
		return g_stats[static_cast<usz>(id)].calls.load(std::memory_order_relaxed);
	}

	inline u64 cycles(site id) noexcept
	{
		return g_stats[static_cast<usz>(id)].cycles.load(std::memory_order_relaxed);
	}

	inline void log_summary(u64 total) noexcept
	{
#ifdef ANDROID
		__android_log_print(ANDROID_LOG_INFO, "RPCS3",
			"Thor wait profiler SPU total=%llu pc=%llu/%llu dma=%llu/%llu accurate=%llu/%llu "
			"putunc_abandon=%llu/%llu putunc_lock=%llu/%llu getllar=%llu/%llu getllar_retry=%llu/%llu "
			"eventstat=%llu/%llu event_lock=%llu/%llu ch_pop=%llu/%llu ch_push=%llu/%llu ch4_pop=%llu/%llu",
			static_cast<unsigned long long>(total),
			static_cast<unsigned long long>(calls(site::spu_pc_acquire)),
			static_cast<unsigned long long>(cycles(site::spu_pc_acquire)),
			static_cast<unsigned long long>(calls(site::spu_dma_reservation)),
			static_cast<unsigned long long>(cycles(site::spu_dma_reservation)),
			static_cast<unsigned long long>(calls(site::spu_accurate_store)),
			static_cast<unsigned long long>(cycles(site::spu_accurate_store)),
			static_cast<unsigned long long>(calls(site::spu_putunc_abandon)),
			static_cast<unsigned long long>(cycles(site::spu_putunc_abandon)),
			static_cast<unsigned long long>(calls(site::spu_putunc_lock)),
			static_cast<unsigned long long>(cycles(site::spu_putunc_lock)),
			static_cast<unsigned long long>(calls(site::spu_getllar)),
			static_cast<unsigned long long>(cycles(site::spu_getllar)),
			static_cast<unsigned long long>(calls(site::spu_getllar_retry)),
			static_cast<unsigned long long>(cycles(site::spu_getllar_retry)),
			static_cast<unsigned long long>(calls(site::spu_eventstat)),
			static_cast<unsigned long long>(cycles(site::spu_eventstat)),
			static_cast<unsigned long long>(calls(site::spu_event_lock)),
			static_cast<unsigned long long>(cycles(site::spu_event_lock)),
			static_cast<unsigned long long>(calls(site::spu_channel_pop)),
			static_cast<unsigned long long>(cycles(site::spu_channel_pop)),
			static_cast<unsigned long long>(calls(site::spu_channel_push)),
			static_cast<unsigned long long>(cycles(site::spu_channel_push)),
			static_cast<unsigned long long>(calls(site::spu_channel4_pop)),
			static_cast<unsigned long long>(cycles(site::spu_channel4_pop)));

		__android_log_print(ANDROID_LOG_INFO, "RPCS3",
			"Thor wait profiler core total=%llu rsx_fifo=%llu/%llu vm_range=%llu/%llu "
			"vm_passive=%llu/%llu vm_writer=%llu/%llu vm_res_lock=%llu/%llu vm_res_shared=%llu/%llu "
			"cpu_slot=%llu/%llu cpu_suspend=%llu/%llu sema=%llu/%llu mutex_s=%llu/%llu mutex_x=%llu/%llu "
			"mutex_up=%llu/%llu mutex_unlock=%llu/%llu",
			static_cast<unsigned long long>(total),
			static_cast<unsigned long long>(calls(site::rsx_fifo_cache_fill)),
			static_cast<unsigned long long>(cycles(site::rsx_fifo_cache_fill)),
			static_cast<unsigned long long>(calls(site::vm_range_lock)),
			static_cast<unsigned long long>(cycles(site::vm_range_lock)),
			static_cast<unsigned long long>(calls(site::vm_passive_lock)),
			static_cast<unsigned long long>(cycles(site::vm_passive_lock)),
			static_cast<unsigned long long>(calls(site::vm_writer_lock)),
			static_cast<unsigned long long>(cycles(site::vm_writer_lock)),
			static_cast<unsigned long long>(calls(site::vm_reservation_lock)),
			static_cast<unsigned long long>(cycles(site::vm_reservation_lock)),
			static_cast<unsigned long long>(calls(site::vm_reservation_shared)),
			static_cast<unsigned long long>(cycles(site::vm_reservation_shared)),
			static_cast<unsigned long long>(calls(site::cpu_register_slot)),
			static_cast<unsigned long long>(cycles(site::cpu_register_slot)),
			static_cast<unsigned long long>(calls(site::cpu_suspend_wait)),
			static_cast<unsigned long long>(cycles(site::cpu_suspend_wait)),
			static_cast<unsigned long long>(calls(site::semaphore_spin)),
			static_cast<unsigned long long>(cycles(site::semaphore_spin)),
			static_cast<unsigned long long>(calls(site::mutex_shared)),
			static_cast<unsigned long long>(cycles(site::mutex_shared)),
			static_cast<unsigned long long>(calls(site::mutex_exclusive)),
			static_cast<unsigned long long>(cycles(site::mutex_exclusive)),
			static_cast<unsigned long long>(calls(site::mutex_upgrade)),
			static_cast<unsigned long long>(cycles(site::mutex_upgrade)),
			static_cast<unsigned long long>(calls(site::mutex_unlock)),
			static_cast<unsigned long long>(cycles(site::mutex_unlock)));
#else
		(void)total;
#endif
	}

	inline void record(site id, usz cycles) noexcept
	{
		const u32 every = interval();
		if (!every)
		{
			return;
		}

		auto& stat = g_stats[static_cast<usz>(id)];
		stat.calls.fetch_add(1, std::memory_order_relaxed);
		stat.cycles.fetch_add(cycles, std::memory_order_relaxed);

		const u64 total = g_total_calls.fetch_add(1, std::memory_order_relaxed) + 1;
		if (total % every == 0)
		{
			log_summary(total);
		}
	}

	inline void profiled_busy_wait(site id, usz cycles = 3000) noexcept
	{
		record(id, cycles);
		rx::busy_wait(cycles);
	}
}
