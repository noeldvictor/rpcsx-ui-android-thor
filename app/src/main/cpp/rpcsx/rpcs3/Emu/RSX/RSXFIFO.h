#pragma once

#include "util/types.hpp"
#include "util/endian.hpp"
#include "Emu/RSX/gcm_enums.h"

#include <span>

struct RsxDmaControl;

namespace rsx
{
	class thread;
	struct rsx_iomap_table;

	namespace FIFO
	{
		enum internal_commands : u32
		{
			FIFO_NOP = 0xBABEF1F4,
			FIFO_EMPTY = 0xDEADF1F0,
			FIFO_BUSY = 0xBABEF1F0,
			FIFO_ERROR = 0xDEADBEEF,
			FIFO_PACKET_BEGIN = 0xF1F0,
			FIFO_DISABLED_COMMAND = 0xF1F4,
			FIFO_DRAW_BARRIER = 0xF1F8,
		};

		enum flatten_op : u32
		{
			NOTHING = 0,
			EMIT_END = 1,
			EMIT_BARRIER = 2
		};

		enum class state : u8
		{
			running = 0,
			empty = 1,     // PUT == GET
			spinning = 2,  // Puller continuously jumps to self addr (synchronization technique)
			nop = 3,       // Puller is processing a NOP command
			lock_wait = 4, // Puller is processing a lock acquire
			paused = 5,    // Puller is paused externallly
		};

		enum class interrupt_hint : u8
		{
			conditional_render_eval = 1,
			zcull_sync = 2
		};

		struct register_pair
		{
			u32 reg;
			u32 value;

			void set(u32 reg, u32 val)
			{
				this->reg = reg;
				this->value = val;
			}
		};

		class flattening_helper
		{
			enum register_props : u8
			{
				none = 0,
				skip_on_match = 1,
				always_ignore = 2
			};

			enum optimization_hint : u8
			{
				unknown,
				load_low,
				load_unoptimizable,
				application_not_compatible
			};

			// Workaround for MSVC, C2248
			static constexpr u8 register_props_always_ignore = register_props::always_ignore;

			static constexpr std::array<u8, 0x10000 / 4> m_register_properties = []
			{
				constexpr std::array<std::pair<u32, u32>, 4> ignorable_ranges =
					{{                                      // General
						{NV4097_INVALIDATE_VERTEX_FILE, 3}, // PSLight clears VERTEX_FILE[0-2]
						{NV4097_INVALIDATE_VERTEX_CACHE_FILE, 1},
						{NV4097_INVALIDATE_L2, 1},
						{NV4097_INVALIDATE_ZCULL, 1}}};

				std::array<u8, 0x10000 / 4> register_properties{};

				for (const auto& method : ignorable_ranges)
				{
					for (u32 i = 0; i < method.second; ++i)
					{
						register_properties[method.first + i] |= register_props_always_ignore;
					}
				}

				return register_properties;
			}();

			u32 deferred_primitive = 0;
			u32 draw_count = 0;
			bool in_begin_end = false;

			bool enabled = false;
			u32 num_collapsed = 0;
			optimization_hint fifo_hint = unknown;

			void reset(bool _enabled);

		public:
			flattening_helper() = default;
			~flattening_helper() = default;

			u32 get_primitive() const
			{
				return deferred_primitive;
			}
			bool is_enabled() const
			{
				return enabled;
			}

			void force_disable();
			void evaluate_performance(u32 total_draw_count);
			inline flatten_op test(register_pair& command);
		};

		class FIFO_control
		{
		private:
			mutable rsx::thread* m_thread;
			RsxDmaControl* m_ctrl = nullptr;
			const rsx::rsx_iomap_table* m_iotable;
			u32 m_internal_get = 0;

			u32 m_memwatch_addr = 0;
			u32 m_memwatch_cmp = 0;

			u32 m_command_reg = 0;
			u32 m_command_inc = 0;
			u32 m_remaining_commands = 0;
			u32 m_args_ptr = 0;
			u32 m_cmd = ~0u;

			u32 m_cache_addr = 0;
			u32 m_cache_size = 0;

			// Thor (2026-09-08), ARMSX3 ccbcbce36: room for 32 lines. The refill's
			// fixed cost (read_put, the iotable lookup, the reservation lock, one
			// reservation_acquire per line) is paid per refill whatever it fetches;
			// Transformers combat runs 830 refills a frame for 106 KB of FIFO.
			// m_cache_line_limit picks 8 (upstream) or 32 lines at construction.
			//   debug.rpcsx.thor.rsx_fifo_4k = 1
			static constexpr u32 cache_line_count = 32;
			u32 m_cache_line_limit = 8;
			alignas(64) std::byte m_cache[cache_line_count][128];

			// ARMSX3 5636c9f3f and 8041edf5b: GET published on a bounded lag and only
			// when it moved. GET shares a 64-byte line with PUT, which the guest PPU
			// writes from another cluster, so each publish is a coherence miss taken
			// against the thread feeding the ring. Every path that can idle or block
			// publishes at once through sync_get_force().
			//   debug.rpcsx.thor.rsx_fifo_get_lag = 1
			bool m_thor_get_lag = false;
			mutable u32 m_get_sync_counter = 0;
			mutable u32 m_published_get = umax;

			// Snapshot of g_cfg.core.rsx_fifo_accuracy, refreshed once per packet.
			// The config read is a seq_cst atomic load, an ldar on ARM64 the compiler
			// cannot hoist, and it was consulted once per FIFO argument.
			bool m_accurate_fetch = false;

		public:
			FIFO_control(rsx::thread* pctrl);
			~FIFO_control() = default;

			u32 translate_address(u32 addr) const;

			// ARMSX3 1c2f13fa5: the hit path is inline, the refill is not. This is
			// called once per command word (about 300,000 a frame here) and refills
			// about 830 times, so nearly every call is a compare and a load.
			std::pair<bool, u32> fetch_u32_refill(u32 addr);

			inline std::pair<bool, u32> fetch_u32(u32 addr)
			{
				if (addr - m_cache_addr >= m_cache_size) [[unlikely]]
				{
					return fetch_u32_refill(addr);
				}

				return {true, read_from_ptr<be_t<u32>>(+m_cache[0], addr - m_cache_addr)};
			}
			void invalidate_cache()
			{
				m_cache_size = 0;
			}

			u32 get_pos() const
			{
				return m_internal_get;
			}
			u32 last_cmd() const
			{
				return m_cmd;
			}
			void sync_get() const;
			void sync_get_force() const;
			std::span<const u32> get_current_arg_ptr(u32 length_in_words) const;
			u32 get_remaining_args_count() const
			{
				return m_remaining_commands;
			}
			void restore_state(u32 cmd, u32 count);
			void inc_get(bool wait);

			void set_get(u32 get, u32 spin_cmd = 0);
			void abort();

			template <bool = true>
			u32 read_put() const;

			void read(register_pair& data);
			inline bool read_unsafe(register_pair& data);
			bool skip_methods(u32 count);
		};
	} // namespace FIFO
} // namespace rsx