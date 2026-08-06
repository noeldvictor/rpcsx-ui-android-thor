// Measures the two sequences the SPU translator can emit for the same value,
// on the core this runs on. Sequences are written as inline asm so the compiler
// cannot fold either side away or turn one into the other.
//
//   SHUFB selector : (c & ~0x60) ^ 0x0f
//     before  ->  and + eor          (two vector ops)
//     after   ->  bcax               (one vector op)
//
//   EQV            : ~(a ^ b)
//     before  ->  eor + mvn          (two vector ops)
//     after   ->  bcax with ~0       (one vector op)
//
// Two shapes are reported per pair, because they answer different questions:
//   latency    - one serial dependency chain, what a tight SPU block feels
//   throughput - four independent chains, what wide code feels

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <sched.h>
#include <stdlib.h>

#define STR2(x) #x
#define STR(x) STR2(x)
#define INNER 64
#define OUTER 200000

static double now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

#define BENCH(name, body)                                    \
	static double name(void)                                 \
	{                                                        \
		double best = 1e30;                                  \
		for (int rep = 0; rep < 5; rep++) {                  \
			double t0 = now_ns();                            \
			for (unsigned long o = 0; o < OUTER; o++) {      \
				body                                         \
			}                                                \
			double dt = now_ns() - t0;                       \
			double per = dt / ((double)OUTER * INNER);       \
			if (per < best) best = per;                      \
		}                                                    \
		return best;                                         \
	}

// ---- SHUFB selector, latency (serial chain) ----
BENCH(sel_before_lat,
	__asm__ volatile(
		"movi v0.16b, #0x33            \n"
		"movi v1.16b, #0x9f            \n"
		"movi v2.16b, #0x0f            \n"
		".rept " STR(INNER) "          \n"
		"and  v0.16b, v0.16b, v1.16b   \n"
		"eor  v0.16b, v0.16b, v2.16b   \n"
		".endr                         \n"
		::: "v0", "v1", "v2");)

BENCH(sel_after_lat,
	__asm__ volatile(
		"movi v0.16b, #0x33            \n"
		"movi v1.16b, #0x60            \n"
		"movi v2.16b, #0x0f            \n"
		".rept " STR(INNER) "          \n"
		"bcax v0.16b, v2.16b, v0.16b, v1.16b \n"
		".endr                         \n"
		::: "v0", "v1", "v2");)

// ---- SHUFB selector, throughput (four independent chains) ----
BENCH(sel_before_tp,
	__asm__ volatile(
		"movi v0.16b, #0x33            \n"
		"movi v3.16b, #0x35            \n"
		"movi v4.16b, #0x37            \n"
		"movi v5.16b, #0x39            \n"
		"movi v1.16b, #0x9f            \n"
		"movi v2.16b, #0x0f            \n"
		".rept " STR(INNER) "          \n"
		"and  v0.16b, v0.16b, v1.16b   \n"
		"and  v3.16b, v3.16b, v1.16b   \n"
		"and  v4.16b, v4.16b, v1.16b   \n"
		"and  v5.16b, v5.16b, v1.16b   \n"
		"eor  v0.16b, v0.16b, v2.16b   \n"
		"eor  v3.16b, v3.16b, v2.16b   \n"
		"eor  v4.16b, v4.16b, v2.16b   \n"
		"eor  v5.16b, v5.16b, v2.16b   \n"
		".endr                         \n"
		::: "v0", "v1", "v2", "v3", "v4", "v5");)

BENCH(sel_after_tp,
	__asm__ volatile(
		"movi v0.16b, #0x33            \n"
		"movi v3.16b, #0x35            \n"
		"movi v4.16b, #0x37            \n"
		"movi v5.16b, #0x39            \n"
		"movi v1.16b, #0x60            \n"
		"movi v2.16b, #0x0f            \n"
		".rept " STR(INNER) "          \n"
		"bcax v0.16b, v2.16b, v0.16b, v1.16b \n"
		"bcax v3.16b, v2.16b, v3.16b, v1.16b \n"
		"bcax v4.16b, v2.16b, v4.16b, v1.16b \n"
		"bcax v5.16b, v2.16b, v5.16b, v1.16b \n"
		".endr                         \n"
		::: "v0", "v1", "v2", "v3", "v4", "v5");)

// ---- EQV, latency ----
BENCH(eqv_before_lat,
	__asm__ volatile(
		"movi v0.16b, #0x33            \n"
		"movi v1.16b, #0x5a            \n"
		".rept " STR(INNER) "          \n"
		"eor  v0.16b, v0.16b, v1.16b   \n"
		"mvn  v0.16b, v0.16b           \n"
		".endr                         \n"
		::: "v0", "v1");)

BENCH(eqv_after_lat,
	__asm__ volatile(
		"movi v0.16b, #0x33            \n"
		"movi v1.16b, #0x5a            \n"
		"movi v2.16b, #0xff            \n"
		".rept " STR(INNER) "          \n"
		"bcax v0.16b, v0.16b, v2.16b, v1.16b \n"
		".endr                         \n"
		::: "v0", "v1", "v2");)

static void report(const char* what, double before, double after)
{
	printf("%-26s before=%7.3f ns  after=%7.3f ns  speedup=%5.2fx  saved=%5.1f%%\n",
		what, before, after, before / after, 100.0 * (before - after) / before);
}

int main(int argc, char** argv)
{
	int cpu = (argc > 1) ? atoi(argv[1]) : 7;
	cpu_set_t set;
	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	if (sched_setaffinity(0, sizeof(set), &set) != 0) {
		printf("warning: could not pin to cpu%d\n", cpu);
	}

	printf("pinned to cpu%d, %d ops per inner block, %d outer, best of 5\n", cpu, INNER, OUTER);
	report("SHUFB selector latency", sel_before_lat(), sel_after_lat());
	report("SHUFB selector throughput", sel_before_tp() / 4.0, sel_after_tp() / 4.0);
	report("EQV latency", eqv_before_lat(), eqv_after_lat());
	return 0;
}
