// Quads index expansion: scalar (the core's loop) against NEON, on the Thor.
//
// The core expands each quad to two triangles, 6 indices per quad, in
// write_index_array_for_non_indexed_non_native_primitive_to_buffer (BufferUtils.cpp).
// Clang vectorizes the line-loop and triangle-fan cases there by itself, but the
// quads case compiles to six scalar stores per quad. This checks that a NEON
// version writes the same indices, and what it costs per call at each size.
//
// Build: tools/bench/build_thor_quad_index_bench.sh   Run: on the device, CPU number as arg.
#include <arm_neon.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

using u32 = uint32_t;
using u64 = uint64_t;

static inline u64 ticks()
{
	u64 v;
	__asm__ __volatile__("isb; mrs %0, cntvct_el0" : "=r"(v)::"memory");
	return v;
}

// The core's loop, as it is now.
__attribute__((noinline)) void quads_scalar(u32* dst, unsigned count)
{
	for (unsigned i = 0; i < count / 4; i++)
	{
		dst[6 * i] = 4 * i;
		dst[6 * i + 1] = 4 * i + 1;
		dst[6 * i + 2] = 4 * i + 2;
		dst[6 * i + 3] = 4 * i + 2;
		dst[6 * i + 4] = 4 * i + 3;
		dst[6 * i + 5] = 4 * i;
	}
}

// Two quads are 12 indices: {0,1,2,2, 3,0,4,5, 6,6,7,4} + 4i, three vectors.
__attribute__((noinline)) void quads_neon(u32* dst, unsigned count)
{
	const unsigned quads = count / 4;
	static const u32 p[12] = {0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4};
	uint32x4_t a = vld1q_u32(p), b = vld1q_u32(p + 4), c = vld1q_u32(p + 8);
	const uint32x4_t step = vdupq_n_u32(8);
	unsigned i = 0;

	for (; i + 2 <= quads; i += 2)
	{
		const uint32x4x3_t abc = {{a, b, c}};
		vst1q_u32_x3(dst + 6 * i, abc);
		a = vaddq_u32(a, step);
		b = vaddq_u32(b, step);
		c = vaddq_u32(c, step);
	}

	if (i < quads)
	{
		dst[6 * i] = 4 * i;
		dst[6 * i + 1] = 4 * i + 1;
		dst[6 * i + 2] = 4 * i + 2;
		dst[6 * i + 3] = 4 * i + 2;
		dst[6 * i + 4] = 4 * i + 3;
		dst[6 * i + 5] = 4 * i;
	}
}

int main(int argc, char** argv)
{
	if (argc > 1)
	{
		cpu_set_t set;
		CPU_ZERO(&set);
		CPU_SET(atoi(argv[1]), &set);
		sched_setaffinity(0, sizeof(set), &set);
	}

	const unsigned max_vertices = 4 * 65536;
	u32* x = static_cast<u32*>(aligned_alloc(64, (max_vertices / 4 * 6 + 16) * sizeof(u32)));
	u32* y = static_cast<u32*>(aligned_alloc(64, (max_vertices / 4 * 6 + 16) * sizeof(u32)));

	// Same output for every count up to 8192 vertices, including counts that are not
	// a multiple of 4, and nothing written past the end.
	unsigned mismatches = 0;
	for (unsigned n = 0; n <= 8192; n++)
	{
		memset(x, 0xAB, (n / 4 * 6 + 16) * sizeof(u32));
		memset(y, 0xAB, (n / 4 * 6 + 16) * sizeof(u32));
		quads_scalar(x, n);
		quads_neon(y, n);
		mismatches += memcmp(x, y, (n / 4 * 6 + 16) * sizeof(u32)) != 0;
	}
	printf("cpu %s: mismatches %u of 8193 counts\n", argc > 1 ? argv[1] : "any", mismatches);

	// ns per call; cntvct_el0 runs at 19.2 MHz on this device.
	const unsigned sizes[] = {4, 8, 16, 64, 256, 1024, 4096, 65536, 262144};
	for (unsigned n : sizes)
	{
		const unsigned reps = n <= 64 ? 2000000 : n <= 4096 ? 200000 : 2000;
		double best[2] = {1e30, 1e30};

		for (int round = 0; round < 5; round++)
		{
			for (int k = 0; k < 2; k++)
			{
				const u64 t0 = ticks();
				for (unsigned r = 0; r < reps; r++)
				{
					(k ? quads_neon : quads_scalar)(k ? y : x, n);
					__asm__ __volatile__("" ::: "memory");
				}
				const double ns = (ticks() - t0) / 19.2 * 1000.0 / reps;
				best[k] = ns < best[k] ? ns : best[k];
			}
		}

		printf("%7u vertices: scalar %10.1f ns, neon %10.1f ns, %.2fx\n", n, best[0], best[1], best[0] / best[1]);
	}

	return 0;
}
