// How expensive is one `mrs cntvct_el0` on this device?
//
// WHY THIS NUMBER MATTERS. The SPU profiler puts 96.84% of CellSpursKernel0 in
// one guest block: a 2400-iteration SPURS backoff whose body reads the
// decrementer. Each read compiles to an `mrs cntvct_el0`. If userspace access is
// enabled (CNTKCTL_EL1.EL0VCTEN) that is tens of cycles; if it TRAPS to EL1 it is
// microseconds, and 2400 of them per poll would be milliseconds - which would
// explain the whole frame budget by itself.
//
// Measured against itself is circular, so the loop is timed with
// clock_gettime(CLOCK_MONOTONIC) and cntvct is only the thing being counted.
#include <stdio.h>
#include <stdint.h>
#include <time.h>

static inline uint64_t rd(void) { uint64_t v; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(v)); return v; }
static inline uint64_t frq(void) { uint64_t v; __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v)); return v; }

static double ns_now(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e9 + ts.tv_nsec;
}

int main(void) {
    printf("cntfrq_el0 = %llu Hz\n", (unsigned long long)frq());

    volatile uint64_t sink = 0;
    const int N = 2000000;

    // warm
    for (int i = 0; i < 100000; i++) sink += rd();

    double t0 = ns_now();
    for (int i = 0; i < N; i++) sink += rd();
    double t1 = ns_now();
    double per = (t1 - t0) / N;
    printf("mrs cntvct_el0 : %.2f ns per read  (%d reads)\n", per, N);

    // an empty loop of the same shape, to subtract loop overhead
    double t2 = ns_now();
    for (int i = 0; i < N; i++) sink += i;
    double t3 = ns_now();
    printf("empty loop     : %.2f ns per iteration\n", (t3 - t2) / N);

    printf("\nSPURS backoff is 2400 reads per poll:\n");
    printf("  cost of one backoff = %.1f us\n", per * 2400 / 1000.0);
    printf("  at 18 fps that is %.1f%% of a 55ms frame per poll\n", (per * 2400 / 1e6) / 55.0 * 100.0);
    return (int)(sink & 1);
}
