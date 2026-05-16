#pragma once

#include "../VulkanAPI.h"

#include "util/logs.hpp"
#include "util/types.hpp"

#include <atomic>
#include <cstdlib>
#include <cstring>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

namespace vk::thor::rsx_auditor
{
	namespace detail
	{
		inline std::atomic<u32> g_cached_enabled{0}; // 0 unknown, 1 disabled, 2 enabled
		inline std::atomic<u32> g_report_interval{60};
		inline std::atomic<u64> g_property_poll_counter{0};
		inline std::atomic<u64> g_frame_counter{0};
		inline std::atomic<u64> g_last_report_frame{0};

		inline std::atomic<u64> g_queue_submits{0};
		inline std::atomic<u64> g_queue_submit_flush_requests{0};
		inline std::atomic<u64> g_queue_submit_async_requests{0};
		inline std::atomic<u64> g_queue_wait_semaphores{0};
		inline std::atomic<u64> g_queue_signal_semaphores{0};
		inline std::atomic<u64> g_hard_sync_flushes{0};

		inline std::atomic<u64> g_renderpass_begins{0};
		inline std::atomic<u64> g_renderpass_ends{0};
		inline std::atomic<u64> g_renderpass_barrier_breaks{0};
		inline std::atomic<u64> g_renderpass_breaks_global{0};
		inline std::atomic<u64> g_renderpass_breaks_buffer{0};
		inline std::atomic<u64> g_renderpass_breaks_image{0};
		inline std::atomic<u64> g_renderpass_breaks_texture{0};

		inline std::atomic<u64> g_global_barriers{0};
		inline std::atomic<u64> g_buffer_barriers{0};
		inline std::atomic<u64> g_image_barriers{0};
		inline std::atomic<u64> g_texture_barriers{0};
		inline std::atomic<u64> g_texture_barriers_color{0};
		inline std::atomic<u64> g_texture_barriers_depth{0};
		inline std::atomic<u64> g_texture_barrier_skips{0};
		inline std::atomic<u64> g_texture_barrier_skip_depth_readonly{0};
		inline std::atomic<u64> g_texture_barrier_skip_forced{0};
		inline std::atomic<u64> g_texture_post_barrier_elides{0};
		inline std::atomic<u64> g_texture_post_barrier_persists{0};
		inline std::atomic<u64> g_all_commands_barriers{0};
		inline std::atomic<u64> g_barrier_bytes{0};

		inline std::atomic<u64> g_dma_transfer_to_all_barriers{0};
		inline std::atomic<u64> g_dma_transfer_to_all_bytes{0};
		inline std::atomic<u64> g_dma_transfer_to_host_barriers{0};
		inline std::atomic<u64> g_dma_transfer_to_host_bytes{0};
		inline std::atomic<u64> g_query_wait_copies{0};
		inline std::atomic<u64> g_query_wait_copy_slots{0};

		inline std::atomic<u64> g_pipeline_graphics_creates{0};
		inline std::atomic<u64> g_pipeline_compute_creates{0};
		inline std::atomic<u64> g_pipeline_slow_creates{0};
		inline std::atomic<u64> g_pipeline_create_us{0};

		inline std::atomic<u64> g_detile_jobs{0};
		inline std::atomic<u64> g_detile_input_bytes{0};
		inline std::atomic<u64> g_detile_output_bytes{0};
		inline std::atomic<u64> g_simple_uploads{0};
		inline std::atomic<u64> g_simple_upload_bytes{0};

		inline bool looks_disabled(const char* value, int length)
		{
			if (length <= 0)
			{
				return true;
			}

			switch (value[0])
			{
			case '0':
			case 'n':
			case 'N':
			case 'f':
			case 'F':
				return true;
			case 'o':
			case 'O':
				return length >= 2 && (value[1] == 'f' || value[1] == 'F');
			default:
				return false;
			}
		}

		inline u32 parse_interval(const char* value, int length)
		{
			if (length >= 5 && std::strncmp(value, "frame", 5) == 0)
			{
				return 1;
			}

			char* end = nullptr;
			const unsigned long parsed = std::strtoul(value, &end, 10);
			if (end != value && parsed > 1)
			{
				return static_cast<u32>(parsed > 3600 ? 3600 : parsed);
			}

			return 60;
		}

		inline bool poll_enabled_property()
		{
			char value[128]{};
			int length = 0;

#ifdef ANDROID
			length = __system_property_get("debug.rpcsx.thor.rsx_auditor", value);
#else
			if (const char* env = std::getenv("RPCSX_THOR_RSX_AUDITOR"))
			{
				std::strncpy(value, env, sizeof(value) - 1);
				length = static_cast<int>(std::strlen(value));
			}
#endif

			const bool enabled = !looks_disabled(value, length);
			g_cached_enabled.store(enabled ? 2u : 1u, std::memory_order_relaxed);
			g_report_interval.store(enabled ? parse_interval(value, length) : 60u, std::memory_order_relaxed);
			return enabled;
		}

		enum class dma_fence_mode : u32
		{
			all_commands = 0,
			host_read = 1,
		};

		inline std::atomic<u32> g_cached_dma_fence_mode{0}; // 0 unknown, 1 all_commands, 2 host_read
		inline std::atomic<u64> g_dma_fence_property_poll_counter{0};

		inline dma_fence_mode parse_dma_fence_mode(const char* value, int length)
		{
			if (length >= 4 &&
				(value[0] == 'h' || value[0] == 'H') &&
				(value[1] == 'o' || value[1] == 'O') &&
				(value[2] == 's' || value[2] == 'S') &&
				(value[3] == 't' || value[3] == 'T'))
			{
				return dma_fence_mode::host_read;
			}

			return dma_fence_mode::all_commands;
		}

		inline dma_fence_mode poll_dma_fence_mode_property()
		{
			char value[128]{};
			int length = 0;

#ifdef ANDROID
			length = __system_property_get("debug.rpcsx.thor.rsx_dma_fence", value);
#else
			if (const char* env = std::getenv("RPCSX_THOR_RSX_DMA_FENCE"))
			{
				std::strncpy(value, env, sizeof(value) - 1);
				length = static_cast<int>(std::strlen(value));
			}
#endif

			const dma_fence_mode mode = parse_dma_fence_mode(value, length);
			g_cached_dma_fence_mode.store(mode == dma_fence_mode::host_read ? 2u : 1u, std::memory_order_relaxed);
			return mode;
		}

		inline dma_fence_mode get_dma_fence_mode()
		{
			const u64 poll = g_dma_fence_property_poll_counter.fetch_add(1, std::memory_order_relaxed);
			const u32 cached = g_cached_dma_fence_mode.load(std::memory_order_relaxed);

			if (cached == 0 || (poll & 0xfffu) == 0)
			{
				return poll_dma_fence_mode_property();
			}

			return cached == 2 ? dma_fence_mode::host_read : dma_fence_mode::all_commands;
		}

		enum class depth_feedback_mode : u32
		{
			disabled = 0,
			persist_readonly = 1,
		};

		inline std::atomic<u32> g_cached_depth_feedback_mode{0}; // 0 unknown, 1 disabled, 2 persist_readonly
		inline std::atomic<u64> g_depth_feedback_property_poll_counter{0};

		inline depth_feedback_mode parse_depth_feedback_mode(const char* value, int length)
		{
			if (looks_disabled(value, length))
			{
				return depth_feedback_mode::disabled;
			}

			return depth_feedback_mode::persist_readonly;
		}

		inline depth_feedback_mode poll_depth_feedback_mode_property()
		{
			char value[128]{};
			int length = 0;

#ifdef ANDROID
			length = __system_property_get("debug.rpcsx.thor.rsx_depth_feedback", value);
#else
			if (const char* env = std::getenv("RPCSX_THOR_RSX_DEPTH_FEEDBACK"))
			{
				std::strncpy(value, env, sizeof(value) - 1);
				length = static_cast<int>(std::strlen(value));
			}
#endif

			const depth_feedback_mode mode = parse_depth_feedback_mode(value, length);
			g_cached_depth_feedback_mode.store(mode == depth_feedback_mode::persist_readonly ? 2u : 1u, std::memory_order_relaxed);
			return mode;
		}

		inline depth_feedback_mode get_depth_feedback_mode()
		{
			const u64 poll = g_depth_feedback_property_poll_counter.fetch_add(1, std::memory_order_relaxed);
			const u32 cached = g_cached_depth_feedback_mode.load(std::memory_order_relaxed);

			if (cached == 0 || (poll & 0xfffu) == 0)
			{
				return poll_depth_feedback_mode_property();
			}

			return cached == 2 ? depth_feedback_mode::persist_readonly : depth_feedback_mode::disabled;
		}

		enum class texture_barrier_mode : u32
		{
			normal = 0,
			skip_depth = 1,
			skip_color = 2,
			skip_all = 3,
		};

		inline std::atomic<u32> g_cached_texture_barrier_mode{0}; // 0 unknown, 1 normal, 2 depth, 3 color, 4 all
		inline std::atomic<u64> g_texture_barrier_property_poll_counter{0};

		inline texture_barrier_mode parse_texture_barrier_mode(const char* value, int length)
		{
			if (looks_disabled(value, length))
			{
				return texture_barrier_mode::normal;
			}

			if (length >= 5 &&
				(value[0] == 'd' || value[0] == 'D') &&
				(value[1] == 'e' || value[1] == 'E') &&
				(value[2] == 'p' || value[2] == 'P') &&
				(value[3] == 't' || value[3] == 'T') &&
				(value[4] == 'h' || value[4] == 'H'))
			{
				return texture_barrier_mode::skip_depth;
			}

			if (length >= 5 &&
				(value[0] == 'c' || value[0] == 'C') &&
				(value[1] == 'o' || value[1] == 'O') &&
				(value[2] == 'l' || value[2] == 'L') &&
				(value[3] == 'o' || value[3] == 'O') &&
				(value[4] == 'r' || value[4] == 'R'))
			{
				return texture_barrier_mode::skip_color;
			}

			return texture_barrier_mode::skip_all;
		}

		inline texture_barrier_mode poll_texture_barrier_mode_property()
		{
			char value[128]{};
			int length = 0;

#ifdef ANDROID
			length = __system_property_get("debug.rpcsx.thor.rsx_texture_barrier", value);
#else
			if (const char* env = std::getenv("RPCSX_THOR_RSX_TEXTURE_BARRIER"))
			{
				std::strncpy(value, env, sizeof(value) - 1);
				length = static_cast<int>(std::strlen(value));
			}
#endif

			const texture_barrier_mode mode = parse_texture_barrier_mode(value, length);
			g_cached_texture_barrier_mode.store(static_cast<u32>(mode) + 1u, std::memory_order_relaxed);
			return mode;
		}

		inline texture_barrier_mode get_texture_barrier_mode()
		{
			const u64 poll = g_texture_barrier_property_poll_counter.fetch_add(1, std::memory_order_relaxed);
			const u32 cached = g_cached_texture_barrier_mode.load(std::memory_order_relaxed);

			if (cached == 0 || (poll & 0xfffu) == 0)
			{
				return poll_texture_barrier_mode_property();
			}

			return static_cast<texture_barrier_mode>(cached - 1u);
		}

		inline bool enabled()
		{
			const u64 poll = g_property_poll_counter.fetch_add(1, std::memory_order_relaxed);
			const u32 cached = g_cached_enabled.load(std::memory_order_relaxed);

			if (cached == 0 || (poll & 0xfffu) == 0)
			{
				return poll_enabled_property();
			}

			return cached == 2;
		}

		inline void add_bytes(std::atomic<u64>& counter, VkDeviceSize bytes)
		{
			if (bytes != VK_WHOLE_SIZE)
			{
				counter.fetch_add(static_cast<u64>(bytes), std::memory_order_relaxed);
			}
		}

		inline u64 take(std::atomic<u64>& counter)
		{
			return counter.exchange(0, std::memory_order_relaxed);
		}

		inline void split_mib_x100(u64 bytes, u64& whole, u64& frac)
		{
			const u64 mib_x100 = (bytes * 100ull) / (1024ull * 1024ull);
			whole = mib_x100 / 100ull;
			frac = mib_x100 % 100ull;
		}
	}

	inline bool enabled()
	{
		return detail::enabled();
	}

	inline bool use_host_read_dma_fence()
	{
		return detail::get_dma_fence_mode() == detail::dma_fence_mode::host_read;
	}

	inline bool persist_readonly_depth_feedback()
	{
		return detail::get_depth_feedback_mode() == detail::depth_feedback_mode::persist_readonly;
	}

	inline bool skip_texture_barrier(bool is_depth)
	{
		const auto mode = detail::get_texture_barrier_mode();
		return mode == detail::texture_barrier_mode::skip_all ||
			(is_depth && mode == detail::texture_barrier_mode::skip_depth) ||
			(!is_depth && mode == detail::texture_barrier_mode::skip_color);
	}

	inline void record_queue_submit(u32 wait_semaphores, u32 signal_semaphores)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_queue_submits.fetch_add(1, std::memory_order_relaxed);
		detail::g_queue_wait_semaphores.fetch_add(wait_semaphores, std::memory_order_relaxed);
		detail::g_queue_signal_semaphores.fetch_add(signal_semaphores, std::memory_order_relaxed);
	}

	inline void record_queue_submit_request(bool flush, bool async_request)
	{
		if (!enabled())
		{
			return;
		}

		if (flush)
		{
			detail::g_queue_submit_flush_requests.fetch_add(1, std::memory_order_relaxed);
		}

		if (async_request)
		{
			detail::g_queue_submit_async_requests.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_hard_sync_flush()
	{
		if (enabled())
		{
			detail::g_hard_sync_flushes.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_renderpass_begin()
	{
		if (enabled())
		{
			detail::g_renderpass_begins.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_renderpass_end()
	{
		if (enabled())
		{
			detail::g_renderpass_ends.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_global_barrier(VkPipelineStageFlags src_stage, VkPipelineStageFlags dst_stage, bool broke_renderpass)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_global_barriers.fetch_add(1, std::memory_order_relaxed);
		if ((src_stage | dst_stage) & VK_PIPELINE_STAGE_ALL_COMMANDS_BIT)
		{
			detail::g_all_commands_barriers.fetch_add(1, std::memory_order_relaxed);
		}

		if (broke_renderpass)
		{
			detail::g_renderpass_barrier_breaks.fetch_add(1, std::memory_order_relaxed);
			detail::g_renderpass_breaks_global.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_buffer_barrier(VkDeviceSize bytes, VkPipelineStageFlags src_stage, VkPipelineStageFlags dst_stage, bool broke_renderpass)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_buffer_barriers.fetch_add(1, std::memory_order_relaxed);
		detail::add_bytes(detail::g_barrier_bytes, bytes);
		if ((src_stage | dst_stage) & VK_PIPELINE_STAGE_ALL_COMMANDS_BIT)
		{
			detail::g_all_commands_barriers.fetch_add(1, std::memory_order_relaxed);
		}

		if (broke_renderpass)
		{
			detail::g_renderpass_barrier_breaks.fetch_add(1, std::memory_order_relaxed);
			detail::g_renderpass_breaks_buffer.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_image_barrier(VkPipelineStageFlags src_stage, VkPipelineStageFlags dst_stage, bool broke_renderpass)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_image_barriers.fetch_add(1, std::memory_order_relaxed);
		if ((src_stage | dst_stage) & VK_PIPELINE_STAGE_ALL_COMMANDS_BIT)
		{
			detail::g_all_commands_barriers.fetch_add(1, std::memory_order_relaxed);
		}

		if (broke_renderpass)
		{
			detail::g_renderpass_barrier_breaks.fetch_add(1, std::memory_order_relaxed);
			detail::g_renderpass_breaks_image.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_texture_barrier(bool broke_renderpass, VkImageAspectFlags aspect = 0)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_texture_barriers.fetch_add(1, std::memory_order_relaxed);
		if (aspect & VK_IMAGE_ASPECT_DEPTH_BIT)
		{
			detail::g_texture_barriers_depth.fetch_add(1, std::memory_order_relaxed);
		}
		else if (aspect & VK_IMAGE_ASPECT_COLOR_BIT)
		{
			detail::g_texture_barriers_color.fetch_add(1, std::memory_order_relaxed);
		}

		if (broke_renderpass)
		{
			detail::g_renderpass_barrier_breaks.fetch_add(1, std::memory_order_relaxed);
			detail::g_renderpass_breaks_texture.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_texture_barrier_skip(bool depth, bool forced = false)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_texture_barrier_skips.fetch_add(1, std::memory_order_relaxed);
		if (depth)
		{
			detail::g_texture_barrier_skip_depth_readonly.fetch_add(1, std::memory_order_relaxed);
		}
		if (forced)
		{
			detail::g_texture_barrier_skip_forced.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_texture_post_barrier_elide(bool persisted)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_texture_post_barrier_elides.fetch_add(1, std::memory_order_relaxed);
		if (persisted)
		{
			detail::g_texture_post_barrier_persists.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_dma_transfer_fence(VkDeviceSize bytes, bool host_read)
	{
		if (!enabled())
		{
			return;
		}

		if (host_read)
		{
			detail::g_dma_transfer_to_host_barriers.fetch_add(1, std::memory_order_relaxed);
			detail::add_bytes(detail::g_dma_transfer_to_host_bytes, bytes);
		}
		else
		{
			detail::g_dma_transfer_to_all_barriers.fetch_add(1, std::memory_order_relaxed);
			detail::add_bytes(detail::g_dma_transfer_to_all_bytes, bytes);
		}
	}

	inline void record_query_wait_copy(u32 slots)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_query_wait_copies.fetch_add(1, std::memory_order_relaxed);
		detail::g_query_wait_copy_slots.fetch_add(slots, std::memory_order_relaxed);
	}

	inline void record_pipeline_create(bool graphics, u64 elapsed_us)
	{
		if (!enabled())
		{
			return;
		}

		if (graphics)
		{
			detail::g_pipeline_graphics_creates.fetch_add(1, std::memory_order_relaxed);
		}
		else
		{
			detail::g_pipeline_compute_creates.fetch_add(1, std::memory_order_relaxed);
		}
		detail::g_pipeline_create_us.fetch_add(elapsed_us, std::memory_order_relaxed);
		if (elapsed_us >= 1000)
		{
			detail::g_pipeline_slow_creates.fetch_add(1, std::memory_order_relaxed);
		}
	}

	inline void record_detile_job(VkDeviceSize input_bytes, VkDeviceSize output_bytes)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_detile_jobs.fetch_add(1, std::memory_order_relaxed);
		detail::add_bytes(detail::g_detile_input_bytes, input_bytes);
		detail::add_bytes(detail::g_detile_output_bytes, output_bytes);
	}

	inline void record_simple_upload(VkDeviceSize bytes)
	{
		if (!enabled())
		{
			return;
		}

		detail::g_simple_uploads.fetch_add(1, std::memory_order_relaxed);
		detail::add_bytes(detail::g_simple_upload_bytes, bytes);
	}

	inline void on_frame_end()
	{
		if (!enabled())
		{
			return;
		}

		const u64 frame = detail::g_frame_counter.fetch_add(1, std::memory_order_relaxed) + 1;
		const u32 interval = detail::g_report_interval.load(std::memory_order_relaxed);
		if (interval == 0 || (frame % interval) != 0)
		{
			return;
		}

		const u64 previous_frame = detail::g_last_report_frame.exchange(frame, std::memory_order_relaxed);
		const u64 frames = previous_frame ? frame - previous_frame : frame;

		const u64 queue_submits = detail::take(detail::g_queue_submits);
		const u64 queue_flush_requests = detail::take(detail::g_queue_submit_flush_requests);
		const u64 queue_async_requests = detail::take(detail::g_queue_submit_async_requests);
		const u64 wait_semaphores = detail::take(detail::g_queue_wait_semaphores);
		const u64 signal_semaphores = detail::take(detail::g_queue_signal_semaphores);
		const u64 hard_sync_flushes = detail::take(detail::g_hard_sync_flushes);

		const u64 renderpass_begins = detail::take(detail::g_renderpass_begins);
		const u64 renderpass_ends = detail::take(detail::g_renderpass_ends);
		const u64 renderpass_breaks = detail::take(detail::g_renderpass_barrier_breaks);
		const u64 renderpass_breaks_global = detail::take(detail::g_renderpass_breaks_global);
		const u64 renderpass_breaks_buffer = detail::take(detail::g_renderpass_breaks_buffer);
		const u64 renderpass_breaks_image = detail::take(detail::g_renderpass_breaks_image);
		const u64 renderpass_breaks_texture = detail::take(detail::g_renderpass_breaks_texture);

		const u64 global_barriers = detail::take(detail::g_global_barriers);
		const u64 buffer_barriers = detail::take(detail::g_buffer_barriers);
		const u64 image_barriers = detail::take(detail::g_image_barriers);
		const u64 texture_barriers = detail::take(detail::g_texture_barriers);
		const u64 texture_barriers_color = detail::take(detail::g_texture_barriers_color);
		const u64 texture_barriers_depth = detail::take(detail::g_texture_barriers_depth);
		const u64 texture_barrier_skips = detail::take(detail::g_texture_barrier_skips);
		const u64 texture_barrier_skip_depth_readonly = detail::take(detail::g_texture_barrier_skip_depth_readonly);
		const u64 texture_barrier_skip_forced = detail::take(detail::g_texture_barrier_skip_forced);
		const u64 texture_post_barrier_elides = detail::take(detail::g_texture_post_barrier_elides);
		const u64 texture_post_barrier_persists = detail::take(detail::g_texture_post_barrier_persists);
		const u64 all_commands_barriers = detail::take(detail::g_all_commands_barriers);
		const u64 barrier_bytes = detail::take(detail::g_barrier_bytes);

		const u64 dma_transfer_to_all = detail::take(detail::g_dma_transfer_to_all_barriers);
		const u64 dma_transfer_to_all_bytes = detail::take(detail::g_dma_transfer_to_all_bytes);
		const u64 dma_transfer_to_host = detail::take(detail::g_dma_transfer_to_host_barriers);
		const u64 dma_transfer_to_host_bytes = detail::take(detail::g_dma_transfer_to_host_bytes);
		const u64 query_wait_copies = detail::take(detail::g_query_wait_copies);
		const u64 query_wait_slots = detail::take(detail::g_query_wait_copy_slots);

		const u64 pipeline_graphics = detail::take(detail::g_pipeline_graphics_creates);
		const u64 pipeline_compute = detail::take(detail::g_pipeline_compute_creates);
		const u64 pipeline_slow = detail::take(detail::g_pipeline_slow_creates);
		const u64 pipeline_us = detail::take(detail::g_pipeline_create_us);

		const u64 detile_jobs = detail::take(detail::g_detile_jobs);
		const u64 detile_input_bytes = detail::take(detail::g_detile_input_bytes);
		const u64 detile_output_bytes = detail::take(detail::g_detile_output_bytes);
		const u64 simple_uploads = detail::take(detail::g_simple_uploads);
		const u64 simple_upload_bytes = detail::take(detail::g_simple_upload_bytes);

		u64 barrier_mib = 0, barrier_mib_frac = 0;
		u64 dma_mib = 0, dma_mib_frac = 0;
		u64 dma_host_mib = 0, dma_host_mib_frac = 0;
		u64 detile_in_mib = 0, detile_in_mib_frac = 0;
		u64 detile_out_mib = 0, detile_out_mib_frac = 0;
		u64 upload_mib = 0, upload_mib_frac = 0;
		detail::split_mib_x100(barrier_bytes, barrier_mib, barrier_mib_frac);
		detail::split_mib_x100(dma_transfer_to_all_bytes, dma_mib, dma_mib_frac);
		detail::split_mib_x100(dma_transfer_to_host_bytes, dma_host_mib, dma_host_mib_frac);
		detail::split_mib_x100(detile_input_bytes, detile_in_mib, detile_in_mib_frac);
		detail::split_mib_x100(detile_output_bytes, detile_out_mib, detile_out_mib_frac);
		detail::split_mib_x100(simple_upload_bytes, upload_mib, upload_mib_frac);

		rsx_log.warning(
			"Thor RSX Auditor: frames=%llu submits=%llu waits=%llu signals=%llu flush_req=%llu async_req=%llu hard_sync=%llu "
			"rp_begin=%llu rp_end=%llu rp_break=%llu rp_break(g/b/i/t)=%llu/%llu/%llu/%llu barriers(g/b/i/t/all)=%llu/%llu/%llu/%llu/%llu barrier_mb=%llu.%02llu "
			"tex_color=%llu tex_depth=%llu tex_skip=%llu depth_skip=%llu forced_skip=%llu post_elide=%llu post_persist=%llu "
			"dma_transfer_all=%llu dma_mb=%llu.%02llu dma_transfer_host=%llu dma_host_mb=%llu.%02llu query_wait=%llu slots=%llu pipe(g/c/slow/us)=%llu/%llu/%llu/%llu "
			"detile=%llu in_mb=%llu.%02llu out_mb=%llu.%02llu simple_upload=%llu upload_mb=%llu.%02llu",
			static_cast<unsigned long long>(frames),
			static_cast<unsigned long long>(queue_submits),
			static_cast<unsigned long long>(wait_semaphores),
			static_cast<unsigned long long>(signal_semaphores),
			static_cast<unsigned long long>(queue_flush_requests),
			static_cast<unsigned long long>(queue_async_requests),
			static_cast<unsigned long long>(hard_sync_flushes),
			static_cast<unsigned long long>(renderpass_begins),
			static_cast<unsigned long long>(renderpass_ends),
			static_cast<unsigned long long>(renderpass_breaks),
			static_cast<unsigned long long>(renderpass_breaks_global),
			static_cast<unsigned long long>(renderpass_breaks_buffer),
			static_cast<unsigned long long>(renderpass_breaks_image),
			static_cast<unsigned long long>(renderpass_breaks_texture),
			static_cast<unsigned long long>(global_barriers),
			static_cast<unsigned long long>(buffer_barriers),
			static_cast<unsigned long long>(image_barriers),
			static_cast<unsigned long long>(texture_barriers),
			static_cast<unsigned long long>(all_commands_barriers),
			static_cast<unsigned long long>(barrier_mib),
			static_cast<unsigned long long>(barrier_mib_frac),
			static_cast<unsigned long long>(texture_barriers_color),
			static_cast<unsigned long long>(texture_barriers_depth),
			static_cast<unsigned long long>(texture_barrier_skips),
			static_cast<unsigned long long>(texture_barrier_skip_depth_readonly),
			static_cast<unsigned long long>(texture_barrier_skip_forced),
			static_cast<unsigned long long>(texture_post_barrier_elides),
			static_cast<unsigned long long>(texture_post_barrier_persists),
			static_cast<unsigned long long>(dma_transfer_to_all),
			static_cast<unsigned long long>(dma_mib),
			static_cast<unsigned long long>(dma_mib_frac),
			static_cast<unsigned long long>(dma_transfer_to_host),
			static_cast<unsigned long long>(dma_host_mib),
			static_cast<unsigned long long>(dma_host_mib_frac),
			static_cast<unsigned long long>(query_wait_copies),
			static_cast<unsigned long long>(query_wait_slots),
			static_cast<unsigned long long>(pipeline_graphics),
			static_cast<unsigned long long>(pipeline_compute),
			static_cast<unsigned long long>(pipeline_slow),
			static_cast<unsigned long long>(pipeline_us),
			static_cast<unsigned long long>(detile_jobs),
			static_cast<unsigned long long>(detile_in_mib),
			static_cast<unsigned long long>(detile_in_mib_frac),
			static_cast<unsigned long long>(detile_out_mib),
			static_cast<unsigned long long>(detile_out_mib_frac),
			static_cast<unsigned long long>(simple_uploads),
			static_cast<unsigned long long>(upload_mib),
			static_cast<unsigned long long>(upload_mib_frac));
	}
}
