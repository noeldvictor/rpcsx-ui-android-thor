#pragma once

#include "util/types.hpp"

#include <string_view>

#if defined(__ANDROID__) && defined(RPCSX_THOR_THERMAL_HEADROOM_PROBE)
#include <atomic>
#include <cmath>
#include <cstddef>
#include <dlfcn.h>
#include <sys/system_properties.h>
#endif

namespace rpcsx::thermal_headroom_probe
{
	struct sample
	{
		bool attempted = false;
		bool available = false;
		bool headroom_valid = false;
		float headroom = 0.0f;
		s32 status = -1;
	};

#if defined(__ANDROID__) && defined(RPCSX_THOR_THERMAL_HEADROOM_PROBE)
	namespace detail
	{
		struct thermal_manager;

		using acquire_manager_fn = thermal_manager* (*)();
		using release_manager_fn = void (*)(thermal_manager*);
		using get_status_fn = s32 (*)(thermal_manager*);
		using get_headroom_fn = float (*)(thermal_manager*, int);

		inline bool property_requested() noexcept
		{
			char value[PROP_VALUE_MAX]{};
			const int length = __system_property_get("debug.rpcsx.thor.thermal_headroom_probe", value);
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
			acquire_manager_fn acquire_manager = nullptr;
			release_manager_fn release_manager = nullptr;
			get_status_fn get_status = nullptr;
			get_headroom_fn get_headroom = nullptr;

			api() noexcept
			{
				library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
				if (!library)
				{
					return;
				}

				acquire_manager = reinterpret_cast<acquire_manager_fn>(dlsym(library, "AThermal_acquireManager"));
				release_manager = reinterpret_cast<release_manager_fn>(dlsym(library, "AThermal_releaseManager"));
				get_status = reinterpret_cast<get_status_fn>(dlsym(library, "AThermal_getCurrentThermalStatus"));
				get_headroom = reinterpret_cast<get_headroom_fn>(dlsym(library, "AThermal_getThermalHeadroom"));
			}

			bool available() const noexcept
			{
				return acquire_manager && release_manager && get_status && get_headroom;
			}
		};

		inline api& get_api() noexcept
		{
			// libandroid.so is process-lifetime. Keep the handle open so no probe can
			// race library teardown while a manager is being released.
			static api value;
			return value;
		}
	} // namespace detail

	inline bool requested() noexcept
	{
		// Read once. Default-off builds never contain this implementation, and an
		// enabled diagnostic process can emit at most one headroom sample.
		static const bool enabled = detail::property_requested();
		return enabled;
	}

	inline sample sample_before_ppu_compile(std::string_view title_id) noexcept
	{
		sample result{};
		if (title_id != "BLUS30161" || !requested())
		{
			return result;
		}

		static std::atomic_flag sampled = ATOMIC_FLAG_INIT;
		if (sampled.test_and_set(std::memory_order_relaxed))
		{
			return result;
		}

		result.attempted = true;
		auto& api = detail::get_api();
		if (!api.available())
		{
			return result;
		}

		auto* manager = api.acquire_manager();
		if (!manager)
		{
			return result;
		}

		result.available = true;
		result.status = api.get_status(manager);
		result.headroom = api.get_headroom(manager, 0);
		result.headroom_valid = std::isfinite(result.headroom) && result.headroom >= 0.0f;
		api.release_manager(manager);
		return result;
	}
#else
	inline constexpr bool requested() noexcept
	{
		return false;
	}

	inline constexpr sample sample_before_ppu_compile(std::string_view) noexcept
	{
		return {};
	}
#endif
} // namespace rpcsx::thermal_headroom_probe
