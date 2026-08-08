// Measure ARMv8 AES against the software AES this emulator actually ships.
//
// docs/arm64/aes.md records that Crypto/aesni.cpp is #if defined(__SSE2__), so
// every SELF, SPRX and PKG decryption on Thor runs the four-table PolarSSL
// path. tools/aes_arm64_equiv.c proved a hardware implementation correct. This
// answers the remaining question - what it is worth - and refuses to answer it
// against a strawman.
//
// THE BASELINE IS THE REAL FILE. Crypto/aes.cpp is compiled into this binary
// unmodified. Not a reimplementation, not a textbook byte-wise AES, which would
// be several times slower than the T-table code that actually ships and would
// inflate the ratio into exactly the sort of confident wrong number this
// project keeps having to retract.
//
// CORRECTNESS IS CHECKED BEFORE SPEED, against that same shipped code. Matching
// FIPS-197 proves the cipher is AES; matching aes_crypt_ecb byte for byte over
// random keys proves it is a drop-in for the thing it would replace. A timing
// harness that measures a wrong implementation is worse than no harness.
//
// CORE PINNING IS EXPLICIT. This machine is 1+4+3: a Cortex-X3 at 3187 MHz, two
// A715 and two A710 at 2803, and three A510 at 2016. An unpinned run reports
// whatever the scheduler felt like, and a previous experiment in this project
// was really just detecting which cluster an arm landed on. Both implementations
// are timed on the same core, and every core is reported separately.
//
// Build and run:
//   $NDK/.../clang++ --target=aarch64-linux-android29 -O2 \
//       -march=armv8.4-a+crypto -static -I <Crypto dir> \
//       -o aes_arm64_bench tools/aes_arm64_bench.cpp <Crypto>/aes.cpp
//   adb push aes_arm64_bench /data/local/tmp/ && adb shell /data/local/tmp/aes_arm64_bench

#define _GNU_SOURCE
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/auxv.h>
#include <time.h>

#include "aes.h"
#include "aes_arm64_neon.h"

#ifndef HWCAP_AES
#define HWCAP_AES (1 << 3)
#endif

static uint64_t now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t rng_state = 0x243f6a8885a308d3ull;
static uint64_t rnd(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 7;
    rng_state ^= rng_state << 17;
    return rng_state;
}

static int pin_to(int cpu)
{
    cpu_set_t set;
    CPU_ZERO(&set);
    CPU_SET(cpu, &set);
    return sched_setaffinity(0, sizeof(set), &set);
}

// ---------------------------------------------------------------- agreement --

static unsigned check_agreement(void)
{
    unsigned fails = 0;
    const int sizes[3] = {128, 192, 256};

    for (int s = 0; s < 3; s++)
    {
        for (int iter = 0; iter < 20000; iter++)
        {
            uint8_t key[32], in[16];
            for (int i = 0; i < 32; i += 8)
            {
                const uint64_t r = rnd();
                memcpy(key + i, &r, 8);
            }
            for (int i = 0; i < 16; i += 8)
            {
                const uint64_t r = rnd();
                memcpy(in + i, &r, 8);
            }

            uint8_t rk[15 * 16], dk[15 * 16];
            const int rounds = aes_arm64_expand_key(key, sizes[s], rk);
            aes_arm64_build_decrypt_key(rk, rounds, dk);

            uint8_t arm_enc[16], arm_dec[16], soft_enc[16], soft_dec[16];
            aes_arm64_encrypt_block(rk, rounds, in, arm_enc);
            aes_arm64_decrypt_block(dk, rounds, in, arm_dec);

            aes_context ectx, dctx;
            aes_setkey_enc(&ectx, key, (unsigned)sizes[s]);
            aes_setkey_dec(&dctx, key, (unsigned)sizes[s]);
            aes_crypt_ecb(&ectx, AES_ENCRYPT, in, soft_enc);
            aes_crypt_ecb(&dctx, AES_DECRYPT, in, soft_dec);

            if (memcmp(arm_enc, soft_enc, 16) != 0) fails++;
            if (memcmp(arm_dec, soft_dec, 16) != 0) fails++;
        }
    }

    return fails;
}

// ----------------------------------------------------------------- throughput --

#define BUF_BLOCKS 8192                       // 128 KB, comfortably L2-resident
#define REPEATS 24

// A checksum the compiler cannot discard, so neither loop can be optimized away.
static uint64_t sink = 0;

static double time_soft(aes_context *ctx, int mode, uint8_t *buf, uint8_t *out)
{
    // Warm up: first pass touches tables and pages.
    for (int b = 0; b < BUF_BLOCKS; b++)
        aes_crypt_ecb(ctx, mode, buf + b * 16, out + b * 16);

    const uint64_t t0 = now_ns();
    for (int rep = 0; rep < REPEATS; rep++)
    {
        for (int b = 0; b < BUF_BLOCKS; b++)
            aes_crypt_ecb(ctx, mode, buf + b * 16, out + b * 16);
        sink += out[rep & 15];
    }
    return (double)(now_ns() - t0);
}

static double time_arm(const uint8_t *sched, int rounds, int encrypt,
                       uint8_t *buf, uint8_t *out)
{
    for (int b = 0; b < BUF_BLOCKS; b++)
    {
        if (encrypt) aes_arm64_encrypt_block(sched, rounds, buf + b * 16, out + b * 16);
        else         aes_arm64_decrypt_block(sched, rounds, buf + b * 16, out + b * 16);
    }

    const uint64_t t0 = now_ns();
    for (int rep = 0; rep < REPEATS; rep++)
    {
        for (int b = 0; b < BUF_BLOCKS; b++)
        {
            if (encrypt) aes_arm64_encrypt_block(sched, rounds, buf + b * 16, out + b * 16);
            else         aes_arm64_decrypt_block(sched, rounds, buf + b * 16, out + b * 16);
        }
        sink += out[rep & 15];
    }
    return (double)(now_ns() - t0);
}

static uint8_t g_buf[BUF_BLOCKS * 16];
static uint8_t g_out[BUF_BLOCKS * 16];

int main(void)
{
    if (!(getauxval(AT_HWCAP) & HWCAP_AES))
    {
        printf("RESULT: no HWCAP_AES; nothing measured\n");
        return 2;
    }

    printf("agreement with the shipped software AES (Crypto/aes.cpp):\n");
    const unsigned fails = check_agreement();
    printf("  60000 blocks over 3 key sizes, encrypt and decrypt: %u mismatches\n", fails);
    if (fails)
    {
        printf("RESULT: FAIL - implementations disagree, timings below would be meaningless\n");
        return 1;
    }

    for (int i = 0; i < BUF_BLOCKS * 16; i += 8)
    {
        const uint64_t r = rnd();
        memcpy(g_buf + i, &r, 8);
    }

    static const uint8_t key[16] = {
        0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
        0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f};

    uint8_t rk[15 * 16], dk[15 * 16];
    const int rounds = aes_arm64_expand_key(key, 128, rk);
    aes_arm64_build_decrypt_key(rk, rounds, dk);

    aes_context ectx, dctx;
    aes_setkey_enc(&ectx, key, 128);
    aes_setkey_dec(&dctx, key, 128);

    const double total_bytes = (double)BUF_BLOCKS * 16.0 * (double)REPEATS;

    // 0-2 are A510, 3-6 are A710/A715, 7 is the X3.
    const int cpus[] = {7, 3, 0};
    const char *names[] = {"Cortex-X3  ", "A715/A710  ", "Cortex-A510"};

    printf("\nAES-128 ECB throughput, same core for both implementations:\n");
    printf("  %-12s %-10s %12s %12s %8s\n", "core", "op", "software", "ARMv8 AES", "ratio");

    for (unsigned c = 0; c < sizeof(cpus) / sizeof(cpus[0]); c++)
    {
        if (pin_to(cpus[c]) != 0)
        {
            printf("  %-12s (could not pin, skipped)\n", names[c]);
            continue;
        }

        const double se = time_soft(&ectx, AES_ENCRYPT, g_buf, g_out);
        const double ae = time_arm(rk, rounds, 1, g_buf, g_out);
        const double sd = time_soft(&dctx, AES_DECRYPT, g_buf, g_out);
        const double ad = time_arm(dk, rounds, 0, g_buf, g_out);

        printf("  %-12s %-10s %9.1f MB/s %9.1f MB/s %7.2fx\n", names[c], "encrypt",
               total_bytes / se * 1000.0, total_bytes / ae * 1000.0, se / ae);
        printf("  %-12s %-10s %9.1f MB/s %9.1f MB/s %7.2fx\n", "", "decrypt",
               total_bytes / sd * 1000.0, total_bytes / ad * 1000.0, sd / ad);
    }

    printf("\n(checksum %llu - printed only so neither loop can be optimized away)\n",
           (unsigned long long)sink);
    printf("\nDecrypt is the number that matters for boot: SELF and SPRX are\n");
    printf("decrypted, never encrypted, and Eternal Sonata walks 1187 modules.\n");
    return 0;
}
