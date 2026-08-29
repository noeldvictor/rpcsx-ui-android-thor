#include "stdafx.h"
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
#include "perf_monitor.hpp"

#include "Emu/System.h"
#include "Emu/system_config.h"
#include "Emu/IdManager.h"
#include "Emu/RSX/RSXThread.h"
#include "Emu/Memory/vm.h"
#include "Emu/Cell/PPUThread.h"
#include "Emu/Cell/timers.hpp"
#include "Emu/Cell/thor_spu_selfloop_park.h"
#include "Emu/Cell/thor_spu_ls_dump.h"
#include "Emu/Cell/thor_spu_pc_census.h"
#include "Emu/Cell/thor_spu_trap_stop.h"
#include "Emu/RSX/thor_rsx_fifo_park.h"
#include "Emu/thor_thermal_guard.h"
#include "Emu/thor_device_stats.h"
#include "util/cpu_stats.hpp"
#include "util/sysinfo.hpp"
#include "util/Thread.h"

LOG_CHANNEL(perf_log, "PERF");

void perf_monitor::operator()()
{
	constexpr u64 update_interval_us = 500000;      // Update every half second
	constexpr u64 log_interval_us_max = 10000000;   // Log at least every 10 seconds
	constexpr u64 log_interval_us_min = 500000;     // Log up to every half second when RAM is climbing
	constexpr u64 log_mem_increase = 50 * 1024 * 1024;
	u64 elapsed_us = 0;

	utils::cpu_stats stats;
	stats.init_cpu_query();

	u32 logged_pause = 0;
	u64 last_pause_time = umax;
	u64 max_memory_usage = 0;

	std::vector<double> per_core_usage;
	std::string msg;

	// Guest frame accounting, so an A/B can read frames out of this log.
	u64 last_flip_index = 0;
	u64 last_flip_time = umax;

	u64 thermal_tick = 0;
	bool thermal_engaged_logged = false;

	for (u64 sleep_until = get_system_time();;)
	{
		thread_ctrl::wait_until(&sleep_until, update_interval_us);
		elapsed_us += update_interval_us;

		// This is a monitor-thread probe. The SPU execution path stays unchanged.
		thor::spu_pc_census_tick();

		// Sample temperature for the gameplay thermal guard.
		//
		// Here because this thread already wakes on a timer and nothing on the
		// render path can afford to read sysfs. Every fourth tick, so about 2 s:
		// silicon temperature does not move faster than that, and the guard has
		// hysteresis to absorb what it does miss.
		if (++thermal_tick % 4 == 0)
		{
			thor::thermal_guard::sample();

			// Write one SPU local store, if somebody asked for one. It returns
			// at once when the property is unset, which is the default, and it
			// writes at most one file for each run. It lives here so that no SPU
			// path pays for it.
			thor::spu_ls_dump_tick();

			// Stop the emulator if the guest halted its own SPU.
			thor::spu_trap_stop_tick();

			// Emergency thermal stop. The frame cap bounds the renderer; this stops
			// the emulator. Same reason the trap stop lives here: pausing takes
			// locks, so it must not happen on a sampling or signal path.
			if (thor::thermal_guard::check_thermal_abort())
			{
				perf_log.error("THERMAL ABORT at %u C, sustained for %u samples. Pausing "
					"emulation to protect the device. A frame cap does not stop this: the "
					"heat is SPU work, not presentation. Raise or clear "
					"debug.rpcsx.thor.thermal_abort_c to continue.",
					thor::thermal_guard::hottest_celsius(), thor::thermal_guard::g_abort_dwell);

				Emu.Pause();
			}

			// Log the EDGES only. A line every 2 s would bury the log, and the
			// interesting facts are when it engaged, how hot it was, and when it
			// let go again.
			if (const bool now_engaged = thor::thermal_guard::engaged(); now_engaged != thermal_engaged_logged)
			{
				thermal_engaged_logged = now_engaged;

				if (now_engaged)
				{
					perf_log.warning("Thermal guard ENGAGED at %u C, limiting to %u FPS",
						thor::thermal_guard::hottest_celsius(), thor::thermal_guard::g_hot_fps);
				}
				else
				{
					perf_log.notice("Thermal guard released at %u C",
						thor::thermal_guard::hottest_celsius());
				}
			}
		}

		double total_usage = 0.0;

		stats.get_per_core_usage(per_core_usage, total_usage);

		const u64 current_mem_use = utils::get_memory_usage().second;
		const u64 mem_use_increase = current_mem_use >= max_memory_usage ? current_mem_use - max_memory_usage : 0;
		const u64 log_interval = mem_use_increase >= log_mem_increase ? log_interval_us_min : log_interval_us_max;

		if (elapsed_us >= log_interval || thread_ctrl::state() == thread_state::aborting)
		{
			max_memory_usage = std::max<u64>(current_mem_use, max_memory_usage);
			elapsed_us = 0;

			const bool is_paused = Emu.IsPaused();
			const u64 pause_time = Emu.GetPauseTime();

			if (!is_paused || last_pause_time != pause_time)
			{
				// Resumed or not paused since last check
				logged_pause = 0;
				last_pause_time = pause_time;
			}

			if (is_paused)
			{
				if (logged_pause >= 2)
				{
					// Let's not spam the log when emulation is paused
					// But still emit the message two times so even paused state can be debugged and inspected
					continue;
				}

				logged_pause++;
			}

			msg.clear();
			fmt::append(msg, "CPU Usage: Total: %.1f%%", total_usage);

			if (!per_core_usage.empty())
			{
				fmt::append(msg, ", Cores:");
			}

			for (usz i = 0; i < per_core_usage.size(); i++)
			{
				fmt::append(msg, "%s %.1f%%", i > 0 ? "," : "", per_core_usage[i]);
			}

			if (max_memory_usage)
			{
				fmt::append(msg, ", RAM Usage: %lluMB (Peak: %lluMB)",
					current_mem_use / (1024 * 1024), max_memory_usage / (1024 * 1024));
			}

			// Frames rendered since the previous report.
			//
			// The guest's own flip counter, NOT the host compositor. `dumpsys
			// SurfaceFlinger --latency` is not usable for this: it reported a frozen
			// layer for a session whose own overlay read 25.74 FPS, because the scene
			// was a dialogue box and the presented image barely changed. Its buffer is
			// also a fixed 126 entries, so a stale read is indistinguishable from a
			// real measurement. int_flip_index does not care whether the picture
			// changed.
			//
			// The window is measured rather than assumed, because the log interval
			// drops from 10 s to 0.5 s whenever RAM is climbing.
			if (const auto rsx_thr = g_fxo->try_get<rsx::thread>())
			{
				const u64 flips = rsx_thr->int_flip_index;
				const u64 now = get_system_time();

				if (last_flip_time != umax && now > last_flip_time)
				{
					const u64 window_us = now - last_flip_time;
					const u64 frames = flips >= last_flip_index ? flips - last_flip_index : 0;

					fmt::append(msg, ", Frames: %llu in %.2fs (%.2f FPS)", frames,
						window_us / 1000000.0, frames * 1000000.0 / window_us);

					// Publish for the control API, so a tool can read speed, heat and
					// power without grepping the log. Frames go with the CPU number on
					// purpose: CPU alone cannot tell a thread that stopped spinning
					// from an emulator that stopped working.
					thor::device_stats::publish(frames * 1000000.0 / window_us,
						total_usage / 100.0 * utils::get_thread_count(), flips,
						current_mem_use / (1024 * 1024));
				}

			// WHERE IS main_thread SPINNING?
			//
			// Under HLE SPURS the title never finishes loading: all non-SPURS calls
			// stop at t=17.17s and main_thread emits its last line at t=12.01s. It is
			// NOT deadlocked - per-thread CPU shows PPU[0x1000000] burning ~16% of a
			// core - so it is busy-waiting inside guest code and simply making no
			// calls this log can see.
			//
			// A spinning thread has a PC, and the PC names the loop. Sample it here,
			// on a timer that keeps running while everything else is stuck, and
			// disassemble the address against the PPU ELF (PowerPC:BE:64).
			//
			//   debug.rpcsx.thor.ppu_pc_census = 1
#ifdef __ANDROID__
			{
				static const bool s_pc_census = []() noexcept
				{
					char v[PROP_VALUE_MAX]{};
					if (__system_property_get("debug.rpcsx.thor.ppu_pc_census", v) > 0 && v[0] && v[0] != '0')
					{
						return true;
					}

					std::memset(v, 0, sizeof(v));
					return __system_property_get("debug.rpcsx.thor.ppu_call_trace", v) > 0 && v[0] && v[0] != '0';
				}();

				if (s_pc_census)
				{
					idm::select<named_thread<ppu_thread>>([](u32 id, ppu_thread& ppu)
						{
							const u32 pc = +ppu.cia;

							// THE FENCE main_thread WAITS ON.
							//
							// 0x00fdcf60 disassembles to a two-counter spin:
							//
							//     lwz  r29,-0x638c(r31)
							//     lwz  r0,-0x6390(r31)
							//     cmpw cr7,r29,r0
							//     bne  cr7,-0x18        ; loop while they differ
							//     (with li r3,30 / li r11,0x8d / sc = sys_timer_usleep(30))
							//
							// main_thread sits here in the WORKING LLE run too, so the loop
							// itself is normal - what matters is whether the two counters
							// converge. Under HLE they do not, and printing them says WHICH
							// side is stuck: a frozen producer or a target that keeps moving.
							if (pc == 0x00fdcf60u)
							{
								const u32 base = static_cast<u32>(ppu.gpr[31]);

								if (vm::check_addr(base - 0x6390, 0, 8))
								{
									// WHAT ARE THESE TWO VALUES?
									//
									// They never converge and they are not small counters -
									// 0x304f8348 and 0x304f93e8, 0x10A0 apart. Guest main
									// memory ends at 0x10000000, video is 0xC0000000 and
									// stack 0xD0000000, so if these are pointers they live in
									// a dynamically created user/RSX-context block. Report
									// whether they are mapped at all, and what they point at.
									const u32 done = +vm::_ref<be_t<u32>>(base - 0x638c);
									const u32 targ = +vm::_ref<be_t<u32>>(base - 0x6390);
									const bool d_ok = vm::check_addr(done, 0, 16);
									const bool t_ok = vm::check_addr(targ, 0, 16);

									perf_log.error("Thor FENCE: base=0x%08x done=0x%08x(%s) target=0x%08x(%s) delta=0x%x %s",
										base, done, d_ok ? "mapped" : "UNMAPPED",
										targ, t_ok ? "mapped" : "UNMAPPED",
										targ - done, ppu.get_name());

									if (d_ok)
									{
										perf_log.error("Thor FENCE   at done: %08x %08x %08x %08x",
											+vm::_ref<be_t<u32>>(done), +vm::_ref<be_t<u32>>(done + 4),
											+vm::_ref<be_t<u32>>(done + 8), +vm::_ref<be_t<u32>>(done + 12));
									}
								}
							}

							// Ghidra identifies 0x005a3298 as a staged title loader. The
							// sleep at 0x009e4ba4 returns to 0x005a3350 once per loop.
							// Record a bounded set of object snapshots through the post-Start
							// transition. The first three samples occur before Transformers
							// enters the loading screen. They cannot identify the stopped request.
							static std::atomic<u32> s_load_wait_dumps{0};
							if (id == 0x1000000u && pc == 0x009e4ba4u &&
								static_cast<u32>(ppu.lr) == 0x005a3350u && s_load_wait_dumps.load() < 18)
							{
								const u32 object = static_cast<u32>(ppu.gpr[29]);

								if (vm::check_addr(object, 0, 0x5b0))
								{
									const u32 sample = s_load_wait_dumps.fetch_add(1);
									const u32 vtable = +vm::_ref<be_t<u32>>(object);
									const bool vtable_ok = vm::check_addr(vtable + 0x170, 0, 8);
									const u32 data = +vm::_ref<be_t<u32>>(object + 0x580);
									const bool data_ok = vm::check_addr(data, 0, 0xd0);
									const u32 data_vtable = data_ok ? +vm::_ref<be_t<u32>>(data) : 0;
									const bool data_vtable_ok = data_ok && vm::check_addr(data_vtable + 0x50, 0, 4);
									const u32 size_opd = data_vtable_ok ? +vm::_ref<be_t<u32>>(data_vtable + 0x3c) : 0;
									const u32 read_opd = data_vtable_ok ? +vm::_ref<be_t<u32>>(data_vtable + 0x50) : 0;
									const u32 size_code = vm::check_addr(size_opd, 0, 8) ? +vm::_ref<be_t<u32>>(size_opd) : 0;
									const u32 read_code = vm::check_addr(read_opd, 0, 8) ? +vm::_ref<be_t<u32>>(read_opd) : 0;

									perf_log.error("Thor LOAD WAIT: sample=%u object=0x%08x vtable=0x%08x poll=0x%08x loader=0x%08x flags=0x%08x control=0x%08x data=0x%08x handle=0x%08x",
										sample + 1, object, vtable,
										vtable_ok ? +vm::_ref<be_t<u32>>(vtable + 0x170) : 0,
										vtable_ok ? +vm::_ref<be_t<u32>>(vtable + 0x174) : 0,
										+vm::_ref<be_t<u32>>(object + 0x598),
										+vm::_ref<be_t<u32>>(object + 0x170),
										data,
										+vm::_ref<be_t<u32>>(object + 0x28));
									perf_log.error("Thor LOAD COUNTS: sample=%u a=%u/%u b=%u/%u c=%u/%u links=%u/%u ticks=%u entries=0x%08x",
										sample + 1, +vm::_ref<be_t<u32>>(object + 0x584), +vm::_ref<be_t<u32>>(object + 0x4c),
										+vm::_ref<be_t<u32>>(object + 0x588), +vm::_ref<be_t<u32>>(object + 0x5c),
										+vm::_ref<be_t<u32>>(object + 0x58c), +vm::_ref<be_t<u32>>(object + 0x54),
										+vm::_ref<be_t<u32>>(object + 0x594), +vm::_ref<be_t<u32>>(object + 0xbc),
										+vm::_ref<be_t<u32>>(object + 0x59c), +vm::_ref<be_t<u32>>(object + 0xb8));
									perf_log.error("Thor LOAD SOURCE: sample=%u data=0x%08x vtable=0x%08x size_opd=0x%08x size_code=0x%08x read_opd=0x%08x read_code=0x%08x",
										sample + 1, data, data_vtable, size_opd, size_code, read_opd, read_code);

									if (data_ok)
									{
										const u32 range_table = +vm::_ref<be_t<u32>>(data + 0xc8);
										const bool range_table_ok = vm::check_addr(range_table, 0, 0x20);
										const u32 io_manager = vm::check_addr(0x019d5410u, 0, 4)
											? +vm::_ref<be_t<u32>>(0x019d5410u) : 0;
										const bool io_manager_ok = vm::check_addr(io_manager, 0, 0x0c);
										const u32 io_workers = io_manager_ok ? +vm::_ref<be_t<u32>>(io_manager + 4) : 0;
										const u32 io_worker_count = io_manager_ok ? +vm::_ref<be_t<u32>>(io_manager + 8) : 0;
										const u32 io_worker = io_worker_count && vm::check_addr(io_workers, 0, 4)
											? +vm::_ref<be_t<u32>>(io_workers) : 0;
										const bool io_worker_ok = vm::check_addr(io_worker, 0, 0x78);
										const u32 io_worker_vtable = io_worker_ok
											? +vm::_ref<be_t<u32>>(io_worker) : 0;
										const bool io_worker_vtable_ok = io_worker_vtable && vm::check_addr(io_worker_vtable, 0, 0x50);
										const u32 direct_opd = io_worker_vtable_ok ? +vm::_ref<be_t<u32>>(io_worker_vtable + 0x0c) : 0;
										const u32 table_opd = io_worker_vtable_ok ? +vm::_ref<be_t<u32>>(io_worker_vtable + 0x10) : 0;
										const u32 backend_read_opd = io_worker_vtable_ok ? +vm::_ref<be_t<u32>>(io_worker_vtable + 0x40) : 0;
										const u32 backend_release_opd = io_worker_vtable_ok ? +vm::_ref<be_t<u32>>(io_worker_vtable + 0x48) : 0;
										const u32 backend_validate_opd = io_worker_vtable_ok ? +vm::_ref<be_t<u32>>(io_worker_vtable + 0x4c) : 0;

										perf_log.error("Thor LOAD RANGE: sample=%u limit=%u size=%u request=%u+%u cache0=%u..%u buffer0=0x%08x pending0=%u cache1=%u..%u buffer1=0x%08x pending1=%u table=0x%08x io=%u",
											sample + 1,
											+vm::_ref<be_t<u32>>(data + 0x94), +vm::_ref<be_t<u32>>(data + 0x98),
											+vm::_ref<be_t<u32>>(data + 0xa0), +vm::_ref<be_t<u32>>(data + 0xa4),
											+vm::_ref<be_t<u32>>(data + 0xa8), +vm::_ref<be_t<u32>>(data + 0xb0),
											+vm::_ref<be_t<u32>>(data + 0xb8), +vm::_ref<be_t<u32>>(data + 0xc0),
											+vm::_ref<be_t<u32>>(data + 0xac), +vm::_ref<be_t<u32>>(data + 0xb4),
											+vm::_ref<be_t<u32>>(data + 0xbc), +vm::_ref<be_t<u32>>(data + 0xc4),
											range_table, +vm::_ref<be_t<u32>>(data + 0xcc));
										perf_log.error("Thor LOAD IO: sample=%u source=%08x %08x %08x table=%s %08x %08x %08x %08x %08x %08x %08x %08x",
											sample + 1,
											+vm::_ref<be_t<u32>>(data + 0x88), +vm::_ref<be_t<u32>>(data + 0x8c),
											+vm::_ref<be_t<u32>>(data + 0x90), range_table_ok ? "mapped" : "unmapped",
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x00) : 0,
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x04) : 0,
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x08) : 0,
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x0c) : 0,
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x10) : 0,
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x14) : 0,
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x18) : 0,
											range_table_ok ? +vm::_ref<be_t<u32>>(range_table + 0x1c) : 0);
										perf_log.error("Thor LOAD IO VT: sample=%u manager=0x%08x workers=0x%08x/%u worker0=0x%08x vtable=0x%08x direct_opd=0x%08x direct_code=0x%08x table_opd=0x%08x table_code=0x%08x",
											sample + 1, io_manager, io_workers, io_worker_count, io_worker, io_worker_vtable, direct_opd,
											vm::check_addr(direct_opd, 0, 8) ? +vm::_ref<be_t<u32>>(direct_opd) : 0,
											table_opd, vm::check_addr(table_opd, 0, 8) ? +vm::_ref<be_t<u32>>(table_opd) : 0);
										perf_log.error("Thor LOAD IO BACKEND: sample=%u read_opd=0x%08x read_code=0x%08x release_opd=0x%08x release_code=0x%08x validate_opd=0x%08x validate_code=0x%08x",
											sample + 1,
											backend_read_opd, vm::check_addr(backend_read_opd, 0, 8) ? +vm::_ref<be_t<u32>>(backend_read_opd) : 0,
											backend_release_opd, vm::check_addr(backend_release_opd, 0, 8) ? +vm::_ref<be_t<u32>>(backend_release_opd) : 0,
											backend_validate_opd, vm::check_addr(backend_validate_opd, 0, 8) ? +vm::_ref<be_t<u32>>(backend_validate_opd) : 0);

										// Ghidra shows that both read methods add a 0x50-byte entry to
										// the queue at worker +0x4c. The worker moves it to the active
										// list at +0x58 before it starts the backend read. Record both
										// list counts and the first active entry. This separates a
										// queued request from a backend request that does not finish.
										if (io_worker_ok)
										{
											const u32 io_queue = +vm::_ref<be_t<u32>>(io_worker + 0x4c);
											const u32 io_queue_count = +vm::_ref<be_t<u32>>(io_worker + 0x50);
											const u32 io_active = +vm::_ref<be_t<u32>>(io_worker + 0x58);
											const u32 io_active_count = +vm::_ref<be_t<u32>>(io_worker + 0x5c);

											perf_log.error("Thor LOAD IO STATE: sample=%u queue=0x%08x/%u/%u active=0x%08x/%u/%u wake=0x%08x refs=%u run=%u sequence=%llu",
												sample + 1, io_queue, io_queue_count, +vm::_ref<be_t<u32>>(io_worker + 0x54),
												io_active, io_active_count, +vm::_ref<be_t<u32>>(io_worker + 0x60),
												+vm::_ref<be_t<u32>>(io_worker + 0x64), +vm::_ref<be_t<u32>>(io_worker + 0x68),
												+vm::_ref<be_t<u32>>(io_worker + 0x6c),
												static_cast<unsigned long long>(+vm::_ref<be_t<u64>>(io_worker + 0x70)));

											if (io_active_count && vm::check_addr(io_active, 0, 0x50))
											{
												perf_log.error("Thor LOAD IO ACTIVE 00: sample=%u %08x %08x %08x %08x %08x %08x %08x %08x",
													sample + 1,
													+vm::_ref<be_t<u32>>(io_active + 0x00), +vm::_ref<be_t<u32>>(io_active + 0x04),
													+vm::_ref<be_t<u32>>(io_active + 0x08), +vm::_ref<be_t<u32>>(io_active + 0x0c),
													+vm::_ref<be_t<u32>>(io_active + 0x10), +vm::_ref<be_t<u32>>(io_active + 0x14),
													+vm::_ref<be_t<u32>>(io_active + 0x18), +vm::_ref<be_t<u32>>(io_active + 0x1c));
												perf_log.error("Thor LOAD IO ACTIVE 20: sample=%u %08x %08x %08x %08x %08x %08x %08x %08x",
													sample + 1,
													+vm::_ref<be_t<u32>>(io_active + 0x20), +vm::_ref<be_t<u32>>(io_active + 0x24),
													+vm::_ref<be_t<u32>>(io_active + 0x28), +vm::_ref<be_t<u32>>(io_active + 0x2c),
													+vm::_ref<be_t<u32>>(io_active + 0x30), +vm::_ref<be_t<u32>>(io_active + 0x34),
													+vm::_ref<be_t<u32>>(io_active + 0x38), +vm::_ref<be_t<u32>>(io_active + 0x3c));
												perf_log.error("Thor LOAD IO ACTIVE 40: sample=%u %08x %08x %08x %08x",
													sample + 1,
													+vm::_ref<be_t<u32>>(io_active + 0x40), +vm::_ref<be_t<u32>>(io_active + 0x44),
													+vm::_ref<be_t<u32>>(io_active + 0x48), +vm::_ref<be_t<u32>>(io_active + 0x4c));

												// The completion poll at 0x013bcce0 walks the pointer list
												// at active entry +0x40. Each item points to a status word
												// and storage. The request completes when the status is zero.
												const u32 completion_entries = +vm::_ref<be_t<u32>>(io_active + 0x40);
												const u32 completion_count = +vm::_ref<be_t<u32>>(io_active + 0x44);
												const u32 completion_capacity = +vm::_ref<be_t<u32>>(io_active + 0x48);
												const u32 completion_item = completion_count && vm::check_addr(completion_entries, 0, 4)
													? +vm::_ref<be_t<u32>>(completion_entries) : 0;
												const bool completion_item_ok = completion_item && vm::check_addr(completion_item, 0, 8);
												const u32 completion_state = completion_item_ok ? +vm::_ref<be_t<u32>>(completion_item) : 0;
												const u32 completion_storage = completion_item_ok ? +vm::_ref<be_t<u32>>(completion_item + 4) : 0;
												const bool completion_state_ok = completion_state && vm::check_addr(completion_state, 0, 4);

												perf_log.error("Thor LOAD IO COMPLETION: sample=%u entries=0x%08x/%u/%u item0=0x%08x state0=%s:0x%08x value=0x%08x storage=0x%08x",
													sample + 1, completion_entries, completion_count, completion_capacity,
													completion_item, completion_state_ok ? "mapped" : "unmapped", completion_state,
													completion_state_ok ? +vm::_ref<be_t<u32>>(completion_state) : 0, completion_storage);
											}
										}
										perf_log.error("Thor LOAD DATA 00: sample=%u %08x %08x %08x %08x %08x %08x %08x %08x",
											sample + 1,
											+vm::_ref<be_t<u32>>(data + 0x00), +vm::_ref<be_t<u32>>(data + 0x04),
											+vm::_ref<be_t<u32>>(data + 0x08), +vm::_ref<be_t<u32>>(data + 0x0c),
											+vm::_ref<be_t<u32>>(data + 0x10), +vm::_ref<be_t<u32>>(data + 0x14),
											+vm::_ref<be_t<u32>>(data + 0x18), +vm::_ref<be_t<u32>>(data + 0x1c));
										perf_log.error("Thor LOAD DATA 20: sample=%u %08x %08x %08x %08x %08x %08x %08x %08x",
											sample + 1,
											+vm::_ref<be_t<u32>>(data + 0x20), +vm::_ref<be_t<u32>>(data + 0x24),
											+vm::_ref<be_t<u32>>(data + 0x28), +vm::_ref<be_t<u32>>(data + 0x2c),
											+vm::_ref<be_t<u32>>(data + 0x30), +vm::_ref<be_t<u32>>(data + 0x34),
											+vm::_ref<be_t<u32>>(data + 0x38), +vm::_ref<be_t<u32>>(data + 0x3c));
										perf_log.error("Thor LOAD DATA 40: sample=%u %08x %08x %08x %08x %08x %08x %08x %08x",
											sample + 1,
											+vm::_ref<be_t<u32>>(data + 0x40), +vm::_ref<be_t<u32>>(data + 0x44),
											+vm::_ref<be_t<u32>>(data + 0x48), +vm::_ref<be_t<u32>>(data + 0x4c),
											+vm::_ref<be_t<u32>>(data + 0x50), +vm::_ref<be_t<u32>>(data + 0x54),
											+vm::_ref<be_t<u32>>(data + 0x58), +vm::_ref<be_t<u32>>(data + 0x5c));
									}
								}
							}

							// A syscall PC can identify only a shared wrapper. Keep its caller,
							// stack pointer and first argument in the same low-rate sample.
							perf_log.error("Thor PPU PC: id=0x%x %s cia=0x%08x lr=0x%08x sp=0x%08x r3=0x%llx state=0x%x",
								id, ppu.get_name(), pc, static_cast<u32>(ppu.lr), static_cast<u32>(ppu.gpr[1]),
								ppu.gpr[3], static_cast<u32>(ppu.state.load()));

							// Capture one bounded main-thread stack. The census runs only when
							// the manual Android property is on, and the performance thread
							// samples at most once per log interval.
							static std::atomic<bool> s_main_stack_dumped{false};
							if (id == 0x1000000u && pc && !s_main_stack_dumped.load())
							{
								const auto call_stack = ppu.dump_callstack_list();
								if (!call_stack.empty() && !s_main_stack_dumped.exchange(true))
								{
									const usz count = std::min<usz>(call_stack.size(), 12);
									perf_log.error("Thor PPU STACK BEGIN: cia=0x%08x lr=0x%08x sp=0x%08x count=%u total=%u",
										pc, static_cast<u32>(ppu.lr), static_cast<u32>(ppu.gpr[1]),
										static_cast<u32>(count), static_cast<u32>(call_stack.size()));
									for (usz frame = 0; frame < count; frame++)
									{
										perf_log.error("Thor PPU STACK: frame=%u from=0x%08x sp=0x%08x",
											static_cast<u32>(frame), call_stack[frame].first, call_stack[frame].second);
									}
									perf_log.error("Thor PPU STACK END");
								}
							}

							// AND THE CODE AT THAT PC.
							//
							// Dump the words around each sampled address once. The code can
							// then be disassembled offline as PowerPC:BE:64.
							static std::atomic<u32> s_dumped[8]{};
							static std::atomic<u32> s_ndumped{0};

							bool seen = false;

							for (u32 i = 0, have = s_ndumped.load(); i < have && i < 8; i++)
							{
								if (s_dumped[i].load() == pc) { seen = true; break; }
							}

							if (!seen && s_ndumped.load() < 8 && pc > 0x20000 && vm::check_addr(pc - 0x20, 0, 0x40))
							{
								s_dumped[s_ndumped.load()].store(pc);
								s_ndumped++;

								std::string words;

								for (u32 off = 0; off < 0x40; off += 4)
								{
									fmt::append(words, "%08x ", +vm::_ref<be_t<u32>>(pc - 0x20 + off));
								}

								perf_log.error("Thor PPU CODE @0x%08x (from 0x%08x): %s",
									pc, pc - 0x20, words);
							}
						});
				}
			}
#endif

				last_flip_index = flips;
				last_flip_time = now;
			}

			// The SPU self-loop park writes entries/last_pc BEFORE the wait and exits
			// after it, so `parked_now` is the number of SPU threads parked at this
			// instant and `last_pc` says where. Nothing in the tree read those three
			// words until now, which made a null A/B unreadable: a lever with no reach
			// and a lever with no effect both produce "no change".
			//
			// Printed only when the park is on, because the call is only emitted into
			// the JIT when the timeout is non-zero. entries=0 with the park ON is
			// therefore a real result - it says this scene never branches to self.
			//
			// perf_log.notice() is used because this thread's output is already in
			// RPCSX.log. rsx_log.always() does NOT reach the Android sink; that cost a
			// build and a boot on 2026-08-17.
			if (thor::spu_selfloop_park_enabled())
			{
				const u64 entries = thor::g_spu_selfloop_park.entries.load();
				const u64 exits = thor::g_spu_selfloop_park.exits.load();

				fmt::append(msg, ", SPU self-loop park: entries=%llu exits=%llu parked_now=%llu last_pc=0x%05x",
					entries, exits, entries - exits, thor::g_spu_selfloop_park.last_pc.load());
			}

			// Reported only when the RSX park is on. parks=0 with it enabled is a
			// real result: it says the ring never stayed empty long enough.
			// Printed when EITHER the park or the pause ladder is on. The ladder also
			// increments idle_polls, and gating this on enabled() alone made the
			// ladder's reach invisible: with it on and the park off, nothing printed,
			// so "the ring is never empty" and "the lever is not running" looked the
			// same. That is the exact failure this file's counters exist to prevent.
			if (thor::rsx_fifo::enabled() || thor::rsx_fifo::pause_ladder())
			{
				fmt::append(msg, ", RSX FIFO park: idle_polls=%llu parks=%llu slept_ms=%llu",
					thor::rsx_fifo::g_idle_polls.load(), thor::rsx_fifo::g_parks.load(),
					thor::rsx_fifo::g_park_us_total.load() / 1000);
			}

			// The stcx stale-128 probe. Printed unconditionally while the question is
			// open, because a zero here is the RESULT - it says this tree does not have
			// ARMSX3's ldarx defect - and a zero must be distinguishable from a probe
			// that never ran, which is why the other-failure control prints beside it.
			{
				extern atomic_t<u64> g_ppu_stcx_stale_128;
				extern atomic_t<u64> g_ppu_stcx_other_fail;

				fmt::append(msg, ", stcx: stale128=%llu other_fail=%llu",
					g_ppu_stcx_stale_128.load(), g_ppu_stcx_other_fail.load());
			}

			perf_log.notice("%s", msg);

			if (thread_ctrl::state() == thread_state::aborting)
			{
				break;
			}
		}
	}
}

perf_monitor::~perf_monitor()
{
}
