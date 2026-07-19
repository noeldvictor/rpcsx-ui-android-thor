#pragma once

#if defined(ANDROID) && !defined(RPCSX_THOR_ADPF_RSX_HINT)

namespace vk::thor::adpf_rsx_hint
{
	// The hint experiment is default-off. Make normal Android draws and
	// presents compile exactly as if it did not exist.
	inline constexpr bool requested() noexcept
	{
		return false;
	}

	inline constexpr void begin(bool) noexcept
	{
	}

	inline constexpr void finish(bool) noexcept
	{
	}
} // namespace vk::thor::adpf_rsx_hint

#elif defined(ANDROID)

#include "util/logs.hpp"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <dlfcn.h>
#include <sys/system_properties.h>
#include <unistd.h>

namespace vk::thor::adpf_rsx_hint
{
	inline constexpr std::int64_t target_work_duration_ns = 30'000'000;

	namespace detail
	{
		struct performance_hint_manager;
		struct performance_hint_session;

		using get_manager_fn = performance_hint_manager* (*)();
		using create_session_fn = performance_hint_session* (*)(performance_hint_manager*, const std::int32_t*, std::size_t, std::int64_t);
		using report_actual_fn = int (*)(performance_hint_session*, std::int64_t);
		using close_session_fn = void (*)(performance_hint_session*);
		using prefer_power_efficiency_fn = int (*)(performance_hint_session*, bool);

		inline bool property_requested() noexcept
		{
			char value[PROP_VALUE_MAX]{};
			const int length = __system_property_get("debug.rpcsx.thor.adpf_rsx", value);
			if (length <= 0)
			{
				return false;
			}

			return value[0] == '1' ||
			       (length == 2 && (value[0] == 'o' || value[0] == 'O') && (value[1] == 'n' || value[1] == 'N')) ||
			       (length == 3 && (value[0] == 'y' || value[0] == 'Y') && (value[1] == 'e' || value[1] == 'E') && (value[2] == 's' || value[2] == 'S')) ||
			       (length == 4 && (value[0] == 't' || value[0] == 'T') && (value[1] == 'r' || value[1] == 'R') &&
					   (value[2] == 'u' || value[2] == 'U') && (value[3] == 'e' || value[3] == 'E'));
		}

		struct api
		{
			void* library = nullptr;
			get_manager_fn get_manager = nullptr;
			create_session_fn create_session = nullptr;
			report_actual_fn report_actual = nullptr;
			close_session_fn close_session = nullptr;
			prefer_power_efficiency_fn prefer_power_efficiency = nullptr;

			api() noexcept
			{
				library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
				if (!library)
				{
					return;
				}

				get_manager = reinterpret_cast<get_manager_fn>(dlsym(library, "APerformanceHint_getManager"));
				create_session = reinterpret_cast<create_session_fn>(dlsym(library, "APerformanceHint_createSession"));
				report_actual = reinterpret_cast<report_actual_fn>(dlsym(library, "APerformanceHint_reportActualWorkDuration"));
				close_session = reinterpret_cast<close_session_fn>(dlsym(library, "APerformanceHint_closeSession"));
				prefer_power_efficiency = reinterpret_cast<prefer_power_efficiency_fn>(dlsym(library, "APerformanceHint_setPreferPowerEfficiency"));
			}

			bool available() const noexcept
			{
				return get_manager && create_session && report_actual && close_session;
			}
		};

		inline api& get_api() noexcept
		{
			// libandroid.so is process-lifetime. Intentionally keep this handle open so
			// thread-local session teardown cannot race static-library teardown.
			static api value;
			return value;
		}

		struct session_state
		{
			performance_hint_session* session = nullptr;
			std::chrono::steady_clock::time_point work_start{};
			bool work_active = false;
			bool failed = false;

			void close() noexcept
			{
				work_active = false;
				if (session)
				{
					get_api().close_session(session);
					session = nullptr;
				}
			}

			~session_state()
			{
				close();
			}
		};

		inline session_state& get_session_state() noexcept
		{
			static thread_local session_state state;
			return state;
		}
	} // namespace detail

	inline bool requested() noexcept
	{
		// Read once at process start-up. The normal/default-off path never loads
		// libandroid.so, takes timestamps, or enters the title check.
		static const bool enabled = detail::property_requested();
		return enabled;
	}

	inline void begin(bool title_eligible) noexcept
	{
		auto& state = detail::get_session_state();
		if (!title_eligible)
		{
			state.close();
			return;
		}

		if (state.failed || state.work_active)
		{
			return;
		}

		auto& api = detail::get_api();
		if (!state.session)
		{
			if (!api.available())
			{
				state.failed = true;
				rsx_log.warning("Thor ADPF RSX hint unavailable; continuing without performance hints.");
				return;
			}

			auto* manager = api.get_manager();
			const std::int32_t tid = static_cast<std::int32_t>(gettid());
			state.session = manager ? api.create_session(manager, &tid, 1, target_work_duration_ns) : nullptr;
			if (!state.session)
			{
				state.failed = true;
				rsx_log.warning("Thor ADPF RSX session creation failed; continuing without performance hints.");
				return;
			}

			const bool power_efficient = api.prefer_power_efficiency && api.prefer_power_efficiency(state.session, true) == 0;
			rsx_log.notice("Thor ADPF RSX hint enabled (target=%lld ns, power-efficient=%s).",
				static_cast<long long>(target_work_duration_ns), power_efficient ? "yes" : "platform-default");
		}

		state.work_start = std::chrono::steady_clock::now();
		state.work_active = true;
	}

	inline void finish(bool title_eligible) noexcept
	{
		auto& state = detail::get_session_state();
		if (!title_eligible)
		{
			state.close();
			return;
		}

		if (!state.work_active || state.failed || !state.session)
		{
			return;
		}

		const auto actual_duration_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
			std::chrono::steady_clock::now() - state.work_start)
		                                    .count();
		state.work_active = false;

		// This experiment may expose spare 30 FPS budget to Android, but must not
		// ask the scheduler to boost an already-over-budget frame.
		if (actual_duration_ns <= 0 || actual_duration_ns > target_work_duration_ns)
		{
			return;
		}

		if (detail::get_api().report_actual(state.session, actual_duration_ns) != 0)
		{
			state.close();
			state.failed = true;
			rsx_log.warning("Thor ADPF RSX reporting failed; disabling the hint session.");
		}
	}
} // namespace vk::thor::adpf_rsx_hint

#endif // defined(ANDROID)
