// Bespoke acceleration benchmarks for the AYN Thor, run outside the emulator.
//
// CLAUDE.md states the rule this file exists for: the in-app loop costs about
// forty minutes for one arm, and the out-of-app loop costs seconds. Use this to
// find out whether an idea is worth having. Use the emulator to confirm it on the
// real workload.
//
// And the limit, which is in CLAUDE.md too: this program says what something
// costs in isolation. It cannot say whether the code is hot or what it competes
// with. Nine of nine manual predictions in the ledger were refuted on exactly
// that gap, and the BCAX benchmark is the specific warning -- its chain forwarded
// inside one region where the real code crosses two.
//
// Build with tools/bench/build_thor_bench.ps1, run with run_thor_bench.ps1.
//
//   thor_bench topology     the core map, read rather than assumed
//   thor_bench hierarchy    load-to-use latency and streaming bandwidth by size
//   thor_bench memcpy       memcpy against the LDNP/STNP loop, with and without a thrasher
//   thor_bench wait         what a wait costs: spin, yield, WFE, futex
//   thor_bench evict        what a 16 KB copy costs the *neighbour*, memcpy against LDNP/STNP

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

#include <linux/futex.h>
#include <pthread.h>
#include <sched.h>
#include <sys/syscall.h>
#include <unistd.h>

using u8 = uint8_t;
using u32 = uint32_t;
using u64 = uint64_t;

// ---------------------------------------------------------------- timing

static inline u64 tsc()
{
	u64 v;
	__asm__ __volatile__("mrs %0, cntvct_el0" : "=r"(v)::"memory");
	return v;
}

static inline u64 tsc_hz()
{
	u64 v;
	__asm__ __volatile__("mrs %0, cntfrq_el0" : "=r"(v));
	return v;
}

// The generic timer is 19.2 MHz on this chip, so one tick is about 52 ns. Report
// the frequency that was read rather than that constant, because a benchmark
// that assumes its own clock is the first thing to be wrong.
static double ticks_to_ns(u64 ticks, u64 hz)
{
	return (double(ticks) * 1e9) / double(hz);
}

// ---------------------------------------------------------------- affinity

// Wake the cores that core_ctl has paused, so a pin to them can succeed.
//
// Measured 2026-08-13: on an idle device, sched_setaffinity to CPU5 or CPU7
// fails with EINVAL, while CPU3 and CPU6 succeed. Both cores read online=1,
// every cpuset including top-app lists 0-7, and the process's own
// Cpus_allowed_list reads 0-7. Under load the same pins succeed.
//
// That is Qualcomm core_ctl pausing a core: it stays online but leaves the
// scheduler's active mask, and an affinity request naming only paused CPUs is
// rejected. **A light benchmark cannot measure the prime core**, because it is
// not heavy enough to bring it back, and the failure looks like a permission
// problem rather than an idle one.
struct core_waker
{
	std::atomic<bool> stop{false};
	std::vector<pthread_t> threads;

	static void* spin(void* arg)
	{
		auto* self = static_cast<core_waker*>(arg);
		volatile u64 x = 0;
		while (!self->stop.load(std::memory_order_relaxed))
		{
			for (int i = 0; i < 100000; i++)
			{
				x += i;
			}
		}
		(void)x;
		return nullptr;
	}

	void start(int n)
	{
		threads.resize(size_t(n));
		for (int i = 0; i < n; i++)
		{
			pthread_create(&threads[size_t(i)], nullptr, &core_waker::spin, this);
		}
	}

	void join()
	{
		stop.store(true);
		for (pthread_t t : threads)
		{
			pthread_join(t, nullptr);
		}
		threads.clear();
	}
};

static bool pin_to_raw(int cpu);

// Try the pin; if the core is paused, load the machine and try again.
static bool pin_to(int cpu)
{
	if (pin_to_raw(cpu))
	{
		return true;
	}

	core_waker waker;
	waker.start(int(sysconf(_SC_NPROCESSORS_CONF)));

	bool ok = false;
	for (int attempt = 0; attempt < 50 && !ok; attempt++)
	{
		struct timespec ts{0, 100 * 1000 * 1000};
		nanosleep(&ts, nullptr);
		ok = pin_to_raw(cpu);
	}

	waker.join();

	// Confirm the pin survived the load going away.
	return ok && pin_to_raw(cpu);
}

static bool pin_to_raw(int cpu)
{
	cpu_set_t set;
	CPU_ZERO(&set);
	CPU_SET(cpu, &set);

	if (sched_setaffinity(0, sizeof(set), &set) != 0)
	{
		return false;
	}

	// Confirm the move actually happened. This project has recorded an affinity
	// table that was inert while every thread still reported 0-7.
	cpu_set_t got;
	CPU_ZERO(&got);
	if (sched_getaffinity(0, sizeof(got), &got) != 0)
	{
		return false;
	}

	return CPU_ISSET(cpu, &got) && CPU_COUNT(&got) == 1;
}

static std::string read_sysfs(const std::string& path)
{
	FILE* f = std::fopen(path.c_str(), "r");
	if (!f)
	{
		return {};
	}

	char buf[256]{};
	if (!std::fgets(buf, sizeof(buf), f))
	{
		std::fclose(f);
		return {};
	}

	std::fclose(f);
	std::string s(buf);
	while (!s.empty() && (s.back() == '\n' || s.back() == ' '))
	{
		s.pop_back();
	}
	return s;
}

static int cpu_count()
{
	return int(sysconf(_SC_NPROCESSORS_CONF));
}

// ---------------------------------------------------------------- copies

// The same kernel as thor_copy_nontemporal in SPUThread.cpp. Kept identical on
// purpose: a benchmark of a different loop measures a different loop.
static void copy_nontemporal(void* dst, const void* src, size_t size)
{
	auto d = static_cast<u8*>(dst);
	auto s = static_cast<const u8*>(src);

	if (size_t blocks = size & ~size_t{63})
	{
		__asm__ __volatile__(
			"1:\n\t"
			"ldnp q0, q1, [%[s]]\n\t"
			"ldnp q2, q3, [%[s], #32]\n\t"
			"stnp q0, q1, [%[d]]\n\t"
			"stnp q2, q3, [%[d], #32]\n\t"
			"add %[s], %[s], #64\n\t"
			"add %[d], %[d], #64\n\t"
			"subs %[n], %[n], #64\n\t"
			"b.ne 1b\n\t"
			: [s] "+r"(s), [d] "+r"(d), [n] "+r"(blocks)
			:
			: "v0", "v1", "v2", "v3", "memory", "cc");
	}

	if (const size_t tail = size & 63)
	{
		std::memcpy(d, s, tail);
	}
}

// ---------------------------------------------------------------- modes

static int mode_topology()
{
	const u64 hz = tsc_hz();
	std::printf("timer_hz=%llu tick_ns=%.3f\n", (unsigned long long)hz, 1e9 / double(hz));

	for (int cpu = 0; cpu < cpu_count(); cpu++)
	{
		const std::string midr = read_sysfs("/sys/devices/system/cpu/cpu" + std::to_string(cpu) + "/regs/identification/midr_el1");
		const std::string cap = read_sysfs("/sys/devices/system/cpu/cpu" + std::to_string(cpu) + "/cpu_capacity");
		const std::string mhz = read_sysfs("/sys/devices/system/cpu/cpu" + std::to_string(cpu) + "/cpufreq/scaling_cur_freq");

		const bool pinned = pin_to(cpu);
		u64 ctr = 0;
		if (pinned)
		{
			__asm__ __volatile__("mrs %0, ctr_el0" : "=r"(ctr));
		}

		// Part number sits in MIDR bits 15:4.
		const char* name = "?";
		if (midr.size() > 2)
		{
			const u64 v = std::strtoull(midr.c_str(), nullptr, 0);
			switch ((v >> 4) & 0xfff)
			{
			case 0xd4e: name = "Cortex-X3"; break;
			case 0xd4d: name = "Cortex-A715"; break;
			case 0xd47: name = "Cortex-A710"; break;
			case 0xd46: name = "Cortex-A510"; break;
			default: name = "unknown"; break;
			}
		}

		std::printf("cpu=%d core=%s midr=%s capacity=%s cur_khz=%s pinned=%d ctr_el0=0x%llx\n",
			cpu, name, midr.c_str(), cap.c_str(), mhz.c_str(), pinned ? 1 : 0, (unsigned long long)ctr);
	}

	return 0;
}

// Pointer chase: each line points at the next, in a shuffled order, so the
// prefetcher cannot help and the number is load-to-use latency.
static int mode_hierarchy(int cpu)
{
	const u64 hz = tsc_hz();
	if (!pin_to(cpu))
	{
		std::printf("error=cannot_pin cpu=%d\n", cpu);
		return 1;
	}

	const size_t sizes[] = {16u << 10, 32u << 10, 64u << 10, 128u << 10, 256u << 10,
		512u << 10, 1u << 20, 2u << 20, 4u << 20, 8u << 20, 16u << 20};

	std::printf("mode=hierarchy cpu=%d timer_hz=%llu\n", cpu, (unsigned long long)hz);

	for (size_t bytes : sizes)
	{
		const size_t lines = bytes / 64;
		std::vector<size_t> order(lines);
		for (size_t i = 0; i < lines; i++)
		{
			order[i] = i;
		}

		// Deterministic shuffle: no Math.random equivalent, and a fixed order
		// keeps two runs comparable.
		u64 s = 0x9e3779b97f4a7c15ull;
		for (size_t i = lines - 1; i > 0; i--)
		{
			s ^= s << 13;
			s ^= s >> 7;
			s ^= s << 17;
			std::swap(order[i], order[s % (i + 1)]);
		}

		std::vector<u8> buf(bytes + 64);
		auto base = reinterpret_cast<u8*>((reinterpret_cast<uintptr_t>(buf.data()) + 63) & ~uintptr_t{63});

		for (size_t i = 0; i < lines; i++)
		{
			*reinterpret_cast<void**>(base + order[i] * 64) = base + order[(i + 1) % lines] * 64;
		}

		void* p = base;
		const size_t steps = lines * 8 < 200000 ? 200000 : lines * 8;

		// Warm, then measure.
		for (size_t i = 0; i < lines; i++)
		{
			p = *reinterpret_cast<void**>(p);
		}

		const u64 t0 = tsc();
		for (size_t i = 0; i < steps; i++)
		{
			p = *reinterpret_cast<void**>(p);
		}
		const u64 t1 = tsc();

		// Keep the chase alive so the loop cannot be removed.
		__asm__ __volatile__("" ::"r"(p) : "memory");

		const double ns = ticks_to_ns(t1 - t0, hz) / double(steps);
		std::printf("hierarchy cpu=%d bytes=%zu latency_ns=%.2f\n", cpu, bytes, ns);
	}

	return 0;
}

struct thrasher
{
	std::atomic<bool> stop{false};
	std::atomic<u64> loops{0};
	pthread_t th{};
	int cpu = 0;
	size_t bytes = 8u << 20;

	static void* run(void* arg)
	{
		auto* self = static_cast<thrasher*>(arg);
		pin_to(self->cpu);

		std::vector<u8> buf(self->bytes, 1);
		volatile u64 acc = 0;

		while (!self->stop.load(std::memory_order_relaxed))
		{
			for (size_t i = 0; i < self->bytes; i += 64)
			{
				acc += buf[i];
			}
			self->loops.fetch_add(1, std::memory_order_relaxed);
		}

		(void)acc;
		return nullptr;
	}

	void start() { pthread_create(&th, nullptr, &thrasher::run, this); }
	void join()
	{
		stop.store(true);
		pthread_join(th, nullptr);
	}
};

static int mode_memcpy(int cpu, int thrash_cpu)
{
	const u64 hz = tsc_hz();
	if (!pin_to(cpu))
	{
		std::printf("error=cannot_pin cpu=%d\n", cpu);
		return 1;
	}

	std::printf("mode=memcpy cpu=%d thrash_cpu=%d timer_hz=%llu\n", cpu, thrash_cpu, (unsigned long long)hz);

	// 16 KB is the size the comment at SPUThread.cpp names for Eternal Sonata's
	// hot SPU jobs. The others bracket it.
	const size_t sizes[] = {1u << 10, 4u << 10, 16u << 10, 64u << 10, 256u << 10};

	for (int with_thrash = 0; with_thrash < (thrash_cpu >= 0 ? 2 : 1); with_thrash++)
	{
		thrasher t;
		t.cpu = thrash_cpu;
		if (with_thrash)
		{
			t.start();
			// Let it get going before anything is timed.
			struct timespec ts{0, 200 * 1000 * 1000};
			nanosleep(&ts, nullptr);
		}

		for (size_t bytes : sizes)
		{
			std::vector<u8> src(bytes), dst(bytes);
			std::memset(src.data(), 0xA5, bytes);

			const size_t iters = (64u << 20) / bytes;

			// memcpy
			std::memcpy(dst.data(), src.data(), bytes);
			u64 t0 = tsc();
			for (size_t i = 0; i < iters; i++)
			{
				std::memcpy(dst.data(), src.data(), bytes);
			}
			u64 t1 = tsc();
			const double memcpy_ns = ticks_to_ns(t1 - t0, hz) / double(iters);

			// LDNP/STNP
			copy_nontemporal(dst.data(), src.data(), bytes);
			t0 = tsc();
			for (size_t i = 0; i < iters; i++)
			{
				copy_nontemporal(dst.data(), src.data(), bytes);
			}
			t1 = tsc();
			const double nt_ns = ticks_to_ns(t1 - t0, hz) / double(iters);

			if (std::memcmp(dst.data(), src.data(), bytes) != 0)
			{
				std::printf("error=copy_mismatch bytes=%zu\n", bytes);
				if (with_thrash) t.join();
				return 1;
			}

			std::printf("memcpy cpu=%d thrash=%d bytes=%zu memcpy_ns=%.1f nt_ns=%.1f ratio=%.3f memcpy_GBs=%.2f nt_GBs=%.2f\n",
				cpu, with_thrash, bytes, memcpy_ns, nt_ns, nt_ns > 0 ? memcpy_ns / nt_ns : 0.0,
				double(bytes) / memcpy_ns, double(bytes) / nt_ns);
		}

		if (with_thrash)
		{
			const u64 loops = t.loops.load();
			t.join();
			std::printf("thrasher cpu=%d passes=%llu\n", thrash_cpu, (unsigned long long)loops);
		}
	}

	return 0;
}

// Measure the eviction, not the copy.
//
// bench-results.md records the gap this closes. The memcpy mode times the copy
// and found the non-temporal loop only 3.1% faster at 16 KB, but the theory
// behind the change was never about copy throughput: it was that a 16 KB DMA
// evicts the working set of the other SPU threads. The hierarchy run says that
// is plausible, because latency leaves the 1.43 ns L1 level at exactly 32 KB and
// a 16 KB transfer touches 32 KB across source and destination.
//
// So here the metric is the **victim's** rate, not the copier's. A victim thread
// walks a working set on one core while a copier hammers 16 KB transfers on
// another. Three arms: victim alone, victim beside memcpy, victim beside
// LDNP/STNP. If the non-temporal hint is worth anything to neighbours, the third
// arm loses less than the second.
//
// The victim's working set is a parameter because the answer depends on where it
// lives. A set inside its own L1 is private and should be untouched; a set in
// the shared last level is where copy traffic can reach it.
struct victim_t
{
	pthread_t th{};
	int cpu = 0;
	size_t bytes = 0;
	std::atomic<bool> go{false};
	std::atomic<bool> stop{false};
	std::atomic<u64> laps{0};

	static void* run(void* arg)
	{
		auto* self = static_cast<victim_t*>(arg);
		pin_to(self->cpu);

		const size_t lines = self->bytes / 64;
		std::vector<u8> buf(self->bytes + 64);
		auto base = reinterpret_cast<u8*>((reinterpret_cast<uintptr_t>(buf.data()) + 63) & ~uintptr_t{63});

		std::vector<size_t> order(lines);
		for (size_t i = 0; i < lines; i++)
		{
			order[i] = i;
		}
		u64 s = 0x9e3779b97f4a7c15ull;
		for (size_t i = lines - 1; i > 0; i--)
		{
			s ^= s << 13;
			s ^= s >> 7;
			s ^= s << 17;
			std::swap(order[i], order[s % (i + 1)]);
		}
		for (size_t i = 0; i < lines; i++)
		{
			*reinterpret_cast<void**>(base + order[i] * 64) = base + order[(i + 1) % lines] * 64;
		}

		while (!self->go.load(std::memory_order_acquire))
		{
		}

		void* p = base;
		while (!self->stop.load(std::memory_order_relaxed))
		{
			for (size_t i = 0; i < lines; i++)
			{
				p = *reinterpret_cast<void**>(p);
			}
			self->laps.fetch_add(1, std::memory_order_relaxed);
		}

		__asm__ __volatile__("" ::"r"(p) : "memory");
		return nullptr;
	}
};

static int mode_evict(int victim_cpu, int copier_cpu)
{
	const u64 hz = tsc_hz();
	std::printf("mode=evict victim_cpu=%d copier_cpu=%d timer_hz=%llu\n", victim_cpu, copier_cpu, (unsigned long long)hz);

	if (!pin_to(copier_cpu))
	{
		std::printf("error=cannot_pin cpu=%d\n", copier_cpu);
		return 1;
	}

	// 256 KB sits in L2; 4 MB is out at the shared level, where copy traffic can
	// reach it. Run both, because which one moves says where the damage lands.
	for (size_t victim_bytes : {size_t(256u << 10), size_t(4u << 20)})
	{
		double baseline = 0;

		for (int arm = 0; arm < 3; arm++)
		{
			victim_t v;
			v.cpu = victim_cpu;
			v.bytes = victim_bytes;
			pthread_create(&v.th, nullptr, &victim_t::run, &v);

			struct timespec settle{0, 300 * 1000 * 1000};
			nanosleep(&settle, nullptr);

			std::vector<u8> src(16u << 10), dst(16u << 10);
			std::memset(src.data(), 0x5a, src.size());

			v.laps.store(0, std::memory_order_relaxed);
			v.go.store(true, std::memory_order_release);

			const u64 t0 = tsc();
			const u64 window = hz;  // one second of generic timer ticks
			u64 copies = 0;

			while (tsc() - t0 < window)
			{
				for (int i = 0; i < 64; i++)
				{
					if (arm == 1)
					{
						std::memcpy(dst.data(), src.data(), src.size());
					}
					else if (arm == 2)
					{
						copy_nontemporal(dst.data(), src.data(), src.size());
					}
					copies++;
				}
			}

			const u64 elapsed = tsc() - t0;
			const u64 laps = v.laps.load(std::memory_order_relaxed);
			v.stop.store(true, std::memory_order_release);
			pthread_join(v.th, nullptr);

			const double lap_rate = double(laps) / (ticks_to_ns(elapsed, hz) / 1e9);
			if (arm == 0)
			{
				baseline = lap_rate;
			}

			const char* name = arm == 0 ? "victim_alone" : (arm == 1 ? "victim_with_memcpy" : "victim_with_nt");
			std::printf("evict victim_bytes=%zu arm=%s laps_per_s=%.1f retained=%.3f copies=%llu\n",
				victim_bytes, name, lap_rate, baseline > 0 ? lap_rate / baseline : 0.0,
				(unsigned long long)(arm == 0 ? 0 : copies));
		}
	}

	return 0;
}

// What a wait costs, and what it costs to be woken.
//
// This is the question behind the SPU self-loop park and the GETLLAR busy-wait
// percentage. A spin holds a core at full issue rate; a futex sleeps but costs a
// syscall and a wake; WFE parks the core but needs the monitor armed and cannot
// carry a timeout on this chip, which has no FEAT_WFxT.
static std::atomic<u32> g_word{0};

static int futex_wait(std::atomic<u32>* a, u32 expect, const struct timespec* to)
{
	return int(syscall(SYS_futex, a, FUTEX_WAIT_PRIVATE, expect, to, nullptr, 0));
}

static int futex_wake(std::atomic<u32>* a)
{
	return int(syscall(SYS_futex, a, FUTEX_WAKE_PRIVATE, 1, nullptr, nullptr, 0));
}

struct waker
{
	pthread_t th{};
	int cpu = 0;
	u64 delay_ns = 0;
	std::atomic<bool> go{false};
	std::atomic<u64> wake_tsc{0};

	static void* run(void* arg)
	{
		auto* self = static_cast<waker*>(arg);
		pin_to(self->cpu);

		while (!self->go.load(std::memory_order_acquire))
		{
		}

		struct timespec ts{time_t(self->delay_ns / 1000000000ull), long(self->delay_ns % 1000000000ull)};
		nanosleep(&ts, nullptr);

		self->wake_tsc.store(tsc(), std::memory_order_release);
		g_word.store(1, std::memory_order_release);
		futex_wake(&g_word);
		return nullptr;
	}
};

static int mode_wait(int cpu, int waker_cpu)
{
	const u64 hz = tsc_hz();
	if (!pin_to(cpu))
	{
		std::printf("error=cannot_pin cpu=%d\n", cpu);
		return 1;
	}

	std::printf("mode=wait cpu=%d waker_cpu=%d timer_hz=%llu\n", cpu, waker_cpu, (unsigned long long)hz);

	// 1. What one iteration of each wait shape costs when there is nothing to wait
	//    for. This is the per-iteration cost a spin loop pays.
	{
		const size_t iters = 200000;

		u64 t0 = tsc();
		for (size_t i = 0; i < iters; i++)
		{
			__asm__ __volatile__("yield" ::: "memory");
		}
		u64 t1 = tsc();
		std::printf("wait shape=yield ns=%.2f\n", ticks_to_ns(t1 - t0, hz) / double(iters));

		t0 = tsc();
		for (size_t i = 0; i < iters; i++)
		{
			__asm__ __volatile__("isb" ::: "memory");
		}
		t1 = tsc();
		std::printf("wait shape=isb ns=%.2f\n", ticks_to_ns(t1 - t0, hz) / double(iters));

		t0 = tsc();
		for (size_t i = 0; i < iters; i++)
		{
			__asm__ __volatile__("nop" ::: "memory");
		}
		t1 = tsc();
		std::printf("wait shape=nop ns=%.2f\n", ticks_to_ns(t1 - t0, hz) / double(iters));

		// A bare load of a shared word, which is what the SPU self-loop does.
		volatile u32 probe = 0;
		t0 = tsc();
		for (size_t i = 0; i < iters; i++)
		{
			(void)probe;
			__asm__ __volatile__("" ::: "memory");
		}
		t1 = tsc();
		std::printf("wait shape=load ns=%.2f\n", ticks_to_ns(t1 - t0, hz) / double(iters));
	}

	// 1b. WFE, which needs the exclusive monitor armed by an LDXR first.
	//
	// This is the park mechanism this project tried three times. The monitor is
	// per core and its granule is 64 bytes here, read from CTR_EL0, so it covers
	// half a 128-byte PS3 reservation. `FEAT_WFxT` is absent on this chip, so WFE
	// cannot carry a timeout, which is the reason the futex path exists at all.
	// Measure what one armed WFE costs when nothing wakes it: a WFE that returns
	// immediately is a nop with extra steps, and that is worth knowing before any
	// park is built on it.
	{
		const size_t iters = 200000;
		std::atomic<u32> monitor{0};

		u64 t0 = tsc();
		for (size_t i = 0; i < iters; i++)
		{
			u32 seen;
			__asm__ __volatile__(
				"ldxr %w[v], [%[p]]\n\t"
				"wfe\n\t"
				: [v] "=&r"(seen)
				: [p] "r"(&monitor)
				: "memory");
			(void)seen;
		}
		u64 t1 = tsc();
		std::printf("wait shape=wfe_armed ns=%.2f\n", ticks_to_ns(t1 - t0, hz) / double(iters));
	}

	// 2. Wake latency: how long after the writer stores does the waiter observe
	//    it. Run for a spin and for a futex, at several delays, because the park's
	//    whole risk is latency.
	for (u64 delay_us : {0ull, 50ull, 200ull, 1000ull})
	{
		for (int shape = 0; shape < 2; shape++)
		{
			const int rounds = 30;
			double total = 0;
			int counted = 0;

			for (int r = 0; r < rounds; r++)
			{
				g_word.store(0, std::memory_order_release);

				waker w;
				w.cpu = waker_cpu;
				w.delay_ns = delay_us * 1000ull;
				pthread_create(&w.th, nullptr, &waker::run, &w);

				w.go.store(true, std::memory_order_release);

				if (shape == 0)
				{
					while (g_word.load(std::memory_order_acquire) == 0)
					{
						__asm__ __volatile__("yield" ::: "memory");
					}
				}
				else
				{
					while (g_word.load(std::memory_order_acquire) == 0)
					{
						struct timespec to{0, 50 * 1000 * 1000};
						futex_wait(&g_word, 0, &to);
					}
				}

				const u64 observed = tsc();
				pthread_join(w.th, nullptr);

				const u64 sent = w.wake_tsc.load(std::memory_order_acquire);
				if (observed > sent)
				{
					total += ticks_to_ns(observed - sent, hz);
					counted++;
				}
			}

			std::printf("wake shape=%s delay_us=%llu latency_ns=%.0f rounds=%d\n",
				shape == 0 ? "spin" : "futex", (unsigned long long)delay_us,
				counted ? total / counted : 0.0, counted);
		}
	}

	return 0;
}

// What the SHUFB table lookups actually cost, per cluster.
//
// `shufb` is the most common operation in this title's compiled SPU corpus:
// 5,794 of them, against 2,203 `fm` and 399 `fi`. The lowering emits `TBX2`,
// which `codegen.md` keeps for correctness.
//
// The claim to test is in CLAUDE.md and it comes from the vendor guides, not from
// this device: `TBX` beats `TBL` on the Cortex-X3 at four pipes against two, and
// **that inverts on the A715 and A710**, where SPU threads actually run. Nine of
// nine manual predictions in the ledger were refuted by measurement, so measure.
//
// Throughput uses independent chains; latency feeds each result into the next
// index vector, so the dependency is real and the number is not throughput in
// disguise.
static int mode_shufb(int cpu)
{
	const u64 hz = tsc_hz();
	if (!pin_to(cpu))
	{
		std::printf("error=cannot_pin cpu=%d\n", cpu);
		return 1;
	}

	std::printf("mode=shufb cpu=%d timer_hz=%llu\n", cpu, (unsigned long long)hz);

	alignas(16) u8 tbl_a[16], tbl_b[16], idx[16];
	for (int i = 0; i < 16; i++)
	{
		tbl_a[i] = u8(i * 3 + 1);
		tbl_b[i] = u8(i * 7 + 2);
		idx[i] = u8((i * 5) & 15);
	}

	const size_t iters = 2000000;

#define BENCH_TP(NAME, INSN)                                                              \
	{                                                                                     \
		u64 t0 = tsc();                                                                   \
		__asm__ __volatile__(                                                             \
			"ld1 {v0.16b}, [%[a]]\n\t"                                                    \
			"ld1 {v1.16b}, [%[b]]\n\t"                                                    \
			"ld1 {v2.16b}, [%[i]]\n\t"                                                    \
			"mov v3.16b, v2.16b\n\t"                                                      \
			"mov v4.16b, v2.16b\n\t"                                                      \
			"mov v5.16b, v2.16b\n\t"                                                      \
			"mov x9, %[n]\n\t"                                                            \
			"1:\n\t" INSN                                                                 \
			"subs x9, x9, #1\n\t"                                                         \
			"b.ne 1b\n\t" ::[a] "r"(tbl_a),                                               \
			[b] "r"(tbl_b), [i] "r"(idx), [n] "r"(iters)                                  \
			: "v0", "v1", "v2", "v3", "v4", "v5", "x9", "cc", "memory");                  \
		u64 t1 = tsc();                                                                   \
		std::printf("shufb cpu=%d test=%s ns_per_op=%.3f\n", cpu, NAME,                   \
			ticks_to_ns(t1 - t0, hz) / double(iters * 4));                                 \
	}

	// Four independent ops per iteration, so this reports throughput.
	BENCH_TP("tbl1_tp",
		"tbl v6.16b, {v0.16b}, v2.16b\n\t"
		"tbl v7.16b, {v0.16b}, v3.16b\n\t"
		"tbl v16.16b, {v0.16b}, v4.16b\n\t"
		"tbl v17.16b, {v0.16b}, v5.16b\n\t")

	BENCH_TP("tbl2_tp",
		"tbl v6.16b, {v0.16b, v1.16b}, v2.16b\n\t"
		"tbl v7.16b, {v0.16b, v1.16b}, v3.16b\n\t"
		"tbl v16.16b, {v0.16b, v1.16b}, v4.16b\n\t"
		"tbl v17.16b, {v0.16b, v1.16b}, v5.16b\n\t")

	BENCH_TP("tbx1_tp",
		"tbx v6.16b, {v0.16b}, v2.16b\n\t"
		"tbx v7.16b, {v0.16b}, v3.16b\n\t"
		"tbx v16.16b, {v0.16b}, v4.16b\n\t"
		"tbx v17.16b, {v0.16b}, v5.16b\n\t")

	BENCH_TP("tbx2_tp",
		"tbx v6.16b, {v0.16b, v1.16b}, v2.16b\n\t"
		"tbx v7.16b, {v0.16b, v1.16b}, v3.16b\n\t"
		"tbx v16.16b, {v0.16b, v1.16b}, v4.16b\n\t"
		"tbx v17.16b, {v0.16b, v1.16b}, v5.16b\n\t")

#undef BENCH_TP

	// Latency: each result becomes the next index, so the chain is serial.
#define BENCH_LAT(NAME, INSN)                                                             \
	{                                                                                     \
		u64 t0 = tsc();                                                                   \
		__asm__ __volatile__(                                                             \
			"ld1 {v0.16b}, [%[a]]\n\t"                                                    \
			"ld1 {v1.16b}, [%[b]]\n\t"                                                    \
			"ld1 {v2.16b}, [%[i]]\n\t"                                                    \
			"movi v18.16b, #15\n\t"                                                       \
			"mov x9, %[n]\n\t"                                                            \
			"1:\n\t" INSN                                                                 \
			"and v2.16b, v2.16b, v18.16b\n\t"                                             \
			"subs x9, x9, #1\n\t"                                                         \
			"b.ne 1b\n\t" ::[a] "r"(tbl_a),                                               \
			[b] "r"(tbl_b), [i] "r"(idx), [n] "r"(iters)                                  \
			: "v0", "v1", "v2", "v18", "x9", "cc", "memory");                             \
		u64 t1 = tsc();                                                                   \
		std::printf("shufb cpu=%d test=%s ns_per_op=%.3f\n", cpu, NAME,                   \
			ticks_to_ns(t1 - t0, hz) / double(iters));                                     \
	}

	BENCH_LAT("tbl2_lat", "tbl v2.16b, {v0.16b, v1.16b}, v2.16b\n\t")
	BENCH_LAT("tbx2_lat", "tbx v2.16b, {v0.16b, v1.16b}, v2.16b\n\t")

#undef BENCH_LAT

	// The candidate rewrite for the SHUFB path that is not perm_only.
	//
	// SPULLVMRecompiler.cpp emits, for a selector that may contain the
	// constant-generating bytes:
	//
	//     x = tbl(zero_lut, c >> 4)        // 0x00 where the selector is in range
	//     r = tbx2(x, a, b, c & 0x9f)      // out-of-range lanes keep x
	//
	// `zero_lut` is twelve zero bytes then ff, ff, 80, 80, so **x is zero exactly
	// where the index is in range**, and TBL2 writes zero exactly where the index
	// is out of range. So the fallback can be an OR instead:
	//
	//     r = tbl2(a, b, c & 0x9f) | x
	//
	// TBX2 costs 2.1x TBL2 on this cluster. Whether trading it for TBL2 plus an
	// ORR actually wins depends on what the ORR costs, and that is measured here
	// rather than assumed. Four independent sequences per iteration.
	{
		const size_t seq_iters = 2000000;

#define BENCH_SEQ(NAME, BODY)                                                             \
	{                                                                                     \
		u64 t0 = tsc();                                                                   \
		__asm__ __volatile__(                                                             \
			"ld1 {v0.16b}, [%[a]]\n\t"                                                    \
			"ld1 {v1.16b}, [%[b]]\n\t"                                                    \
			"ld1 {v2.16b}, [%[i]]\n\t"                                                    \
			"movi v20.16b, #0\n\t"                                                        \
			"mov v3.16b, v2.16b\n\t"                                                      \
			"mov v4.16b, v2.16b\n\t"                                                      \
			"mov v5.16b, v2.16b\n\t"                                                      \
			"mov x9, %[n]\n\t"                                                            \
			"1:\n\t" BODY                                                                 \
			"subs x9, x9, #1\n\t"                                                         \
			"b.ne 1b\n\t" ::[a] "r"(tbl_a),                                               \
			[b] "r"(tbl_b), [i] "r"(idx), [n] "r"(seq_iters)                              \
			: "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16", "v17", "v18", "v19", \
			  "v20", "v21", "v22", "v23", "x9", "cc", "memory");                          \
		u64 t1 = tsc();                                                                   \
		std::printf("shufb cpu=%d test=%s ns_per_shufb=%.3f\n", cpu, NAME,                \
			ticks_to_ns(t1 - t0, hz) / double(seq_iters * 4));                             \
	}

		// What ships today: build the constants, then TBX2 merges them.
		BENCH_SEQ("seq_tbx2_current",
			"tbl v6.16b, {v20.16b}, v2.16b\n\t"
			"tbx v6.16b, {v0.16b, v1.16b}, v2.16b\n\t"
			"tbl v7.16b, {v20.16b}, v3.16b\n\t"
			"tbx v7.16b, {v0.16b, v1.16b}, v3.16b\n\t"
			"tbl v16.16b, {v20.16b}, v4.16b\n\t"
			"tbx v16.16b, {v0.16b, v1.16b}, v4.16b\n\t"
			"tbl v17.16b, {v20.16b}, v5.16b\n\t"
			"tbx v17.16b, {v0.16b, v1.16b}, v5.16b\n\t")

		// The candidate: TBL2 zeroes the out-of-range lanes, so OR the constants in.
		BENCH_SEQ("seq_tbl2_orr_candidate",
			"tbl v6.16b, {v20.16b}, v2.16b\n\t"
			"tbl v18.16b, {v0.16b, v1.16b}, v2.16b\n\t"
			"orr v6.16b, v6.16b, v18.16b\n\t"
			"tbl v7.16b, {v20.16b}, v3.16b\n\t"
			"tbl v19.16b, {v0.16b, v1.16b}, v3.16b\n\t"
			"orr v7.16b, v7.16b, v19.16b\n\t"
			"tbl v16.16b, {v20.16b}, v4.16b\n\t"
			"tbl v21.16b, {v0.16b, v1.16b}, v4.16b\n\t"
			"orr v16.16b, v16.16b, v21.16b\n\t"
			"tbl v17.16b, {v20.16b}, v5.16b\n\t"
			"tbl v22.16b, {v0.16b, v1.16b}, v5.16b\n\t"
			"orr v17.16b, v17.16b, v22.16b\n\t")

#undef BENCH_SEQ
	}

	return 0;
}

int main(int argc, char** argv)
{
	const std::string mode = argc > 1 ? argv[1] : "topology";
	const int cpu = argc > 2 ? std::atoi(argv[2]) : 7;
	const int other = argc > 3 ? std::atoi(argv[3]) : 5;

	std::printf("thor_bench mode=%s cpus=%d\n", mode.c_str(), cpu_count());

	if (mode == "topology") return mode_topology();
	if (mode == "hierarchy") return mode_hierarchy(cpu);
	if (mode == "memcpy") return mode_memcpy(cpu, other);
	if (mode == "wait") return mode_wait(cpu, other);
	if (mode == "shufb") return mode_shufb(cpu);
	if (mode == "evict") return mode_evict(cpu, other);

	std::printf("error=unknown_mode mode=%s\n", mode.c_str());
	return 2;
}
