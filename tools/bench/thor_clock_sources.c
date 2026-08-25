// What does a timestamp actually COST on the AYN Thor?
//
// The SPURS backoff Ghidra found at 0x0f3d0 reads the decrementer 2400 times per
// iteration, and each read inlines an `mrs cntvct_el0`. That was measured at
// 38.49 ns. On a 3.2 GHz Cortex-X3 that is about 123 CYCLES for a system
// register read, where the architectural read should be 10-20. A number that
// large usually means the read is TRAPPED and paying a kernel round trip.
//
// If a cheaper source exists on this chip, every inlined decrementer read gets
// cheaper, and that is the single hottest instruction in the title.
//
// Measures, on the same core, with the same loop shape:
//   cntvct_el0    what the emulator uses today
//   cntvctss_el0  ARMv8.6 FEAT_ECV self-synchronised counter, if it traps we skip
//   cntpct_el0    physical counter
//   clock_gettime CLOCK_MONOTONIC through the vDSO
//   cntvct + isb  what the code costs if ordering is actually required
//
// Also prints CNTFRQ_EL0, because the whole "x86 constant means something else
// here" family of bugs in this tree comes from that frequency being 19.2 MHz.
#include <stdio.h>
#include <stdint.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>
#include <string.h>

static sigjmp_buf g_jmp;
static void on_ill(int sig) { (void)sig; siglongjmp(g_jmp, 1); }

static uint64_t now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

#define N 2000000

#define BENCH(name, expr)                                                     \
    do {                                                                      \
        if (sigsetjmp(g_jmp, 1) == 0) {                                       \
            volatile uint64_t sink = 0;                                       \
            /* warm */                                                        \
            for (int i = 0; i < 10000; i++) { uint64_t v; expr; sink += v; }  \
            const uint64_t t0 = now_ns();                                     \
            for (int i = 0; i < N; i++) { uint64_t v; expr; sink += v; }      \
            const uint64_t t1 = now_ns();                                     \
            printf("  %-22s %7.2f ns/read   (%6.1f cycles @3.2GHz)\n",        \
                   name, (double)(t1 - t0) / N,                               \
                   (double)(t1 - t0) / N * 3.2);                              \
        } else {                                                              \
            printf("  %-22s TRAPS (SIGILL) - unavailable on this chip\n", name); \
        }                                                                     \
    } while (0)

int main(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_ill;
    sigaction(SIGILL, &sa, NULL);

    uint64_t freq = 0;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(freq));
    printf("CNTFRQ_EL0 = %llu Hz  (one tick = %.2f ns)\n\n",
           (unsigned long long)freq, freq ? 1e9 / (double)freq : 0.0);

    printf("timestamp source cost, %d reads each:\n", N);

    BENCH("cntvct_el0",      __asm__ volatile("mrs %0, cntvct_el0"   : "=r"(v)));
    BENCH("cntvct_el0 + isb", __asm__ volatile("isb; mrs %0, cntvct_el0" : "=r"(v) :: "memory"));
    BENCH("cntpct_el0",      __asm__ volatile("mrs %0, cntpct_el0"   : "=r"(v)));
    // FEAT_ECV, ARMv8.6. Encoded by hand so this builds on any toolchain.
    BENCH("cntvctss_el0",    __asm__ volatile(".inst 0xd53be0a0" : "=r"(v)));
    BENCH("clock_gettime",   v = now_ns());

    return 0;
}
