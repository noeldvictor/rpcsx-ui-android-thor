// Equivalence test for the two reservation-path rewrites that were reverted
// after Eternal Sonata faulted in combat.
//
// Both changes looked correct, passed their contract tests, and were verified in
// the shipped disassembly. None of that is evidence they compute the right
// answer, and a contract test that checks the *source has the intended shape*
// cannot catch a wrong result. This runs the implementations against each other.
//
// The bar is the one this fork already applied to VSUMSWS: edge cases enumerated
// exhaustively where the space is small, plus millions of randomised cases, and
// a mismatch count that must be zero.
//
// Build and run:
//   $NDK/toolchains/llvm/prebuilt/*/bin/clang \
//       --target=aarch64-linux-android29 -O2 -march=armv8.4-a -static \
//       -o rdata_equiv tools/rdata_equiv.c
//   adb push rdata_equiv /data/local/tmp/ && adb shell /data/local/tmp/rdata_equiv
//
// A nonzero exit means one of the rewrites is wrong and the crash has a cause.
// Zero means they agree over the tested space, which does not prove them correct
// but does move the suspicion elsewhere.

#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

typedef struct { _Alignas(64) u8 b[128]; } rdata_t;

// ---------------------------------------------------------------- mov_rdata --

// What ARM64 ran before the rewrite, and runs again now.
static void mov_old(rdata_t *dst, const rdata_t *src) { memcpy(dst, src, 128); }

// The reverted rewrite: four interleaved 16-byte chunk pairs.
typedef u8 chunk_t __attribute__((vector_size(16)));
static void mov_new(rdata_t *dst, const rdata_t *src) {
  const chunk_t *s = (const chunk_t *)src;
  chunk_t *d = (chunk_t *)dst;
  const chunk_t a0 = s[0], a1 = s[1];
  d[0] = a0; d[1] = a1;
  const chunk_t b0 = s[2], b1 = s[3];
  d[2] = b0; d[3] = b1;
  const chunk_t c0 = s[4], c1 = s[5];
  d[4] = c0; d[5] = c1;
  const chunk_t e0 = s[6], e1 = s[7];
  d[6] = e0; d[7] = e1;
}

// ---------------------------------------------------------------- cmp_rdata --

// The serial accumulator that ARM64 ran before the rewrite, and runs again now.
static inline int16x8_t accum(int16x8_t acc, const u8 *l0, const u8 *r0,
                              const u8 *l1, const u8 *r1) {
  int16x8_t eq0 = vreinterpretq_s16_u16(
      vceqq_u16(vld1q_u16((const u16 *)l0), vld1q_u16((const u16 *)r0)));
  int16x8_t eq1 = vreinterpretq_s16_u16(
      vceqq_u16(vld1q_u16((const u16 *)l1), vld1q_u16((const u16 *)r1)));
  return vmlaq_s16(acc, eq0, eq1);
}
static int cmp_old(const rdata_t *L, const rdata_t *R) {
  const u8 *l = L->b, *r = R->b;
  int16x8_t h = vdupq_n_s16(0);
  h = accum(h, l + 0,  r + 0,  l + 16,  r + 16);
  h = accum(h, l + 32, r + 32, l + 48,  r + 48);
  h = accum(h, l + 64, r + 64, l + 80,  r + 80);
  h = accum(h, l + 96, r + 96, l + 112, r + 112);
  return vaddvq_s16(h) == 32;
}

// The reverted rewrite: XOR every pair, OR the results, test for all-zero.
static int cmp_new(const rdata_t *L, const rdata_t *R) {
  const uint8x16_t *l = (const uint8x16_t *)L, *r = (const uint8x16_t *)R;
  uint8x16_t a = vorrq_u8(veorq_u8(l[0], r[0]), veorq_u8(l[1], r[1]));
  uint8x16_t b = vorrq_u8(veorq_u8(l[2], r[2]), veorq_u8(l[3], r[3]));
  uint8x16_t c = vorrq_u8(veorq_u8(l[4], r[4]), veorq_u8(l[5], r[5]));
  uint8x16_t d = vorrq_u8(veorq_u8(l[6], r[6]), veorq_u8(l[7], r[7]));
  uint8x16_t ab = vorrq_u8(a, b), cd = vorrq_u8(c, d);
  return vmaxvq_u32(vreinterpretq_u32_u8(vorrq_u8(ab, cd))) == 0;
}

// ------------------------------------------------------------------ harness --

static u64 rng_state = 0x243f6a8885a308d3ull;
static u64 rnd(void) {
  rng_state ^= rng_state << 13;
  rng_state ^= rng_state >> 7;
  rng_state ^= rng_state << 17;
  return rng_state;
}
static void fill(rdata_t *d) {
  for (int i = 0; i < 16; i++) ((u64 *)d->b)[i] = rnd();
}

static u64 mov_fail = 0, cmp_fail = 0, cases = 0;

static void check_mov(const rdata_t *src) {
  rdata_t a, b;
  memset(&a, 0xA5, sizeof a);
  memset(&b, 0x5A, sizeof b);
  mov_old(&a, src);
  mov_new(&b, src);
  if (memcmp(&a, &b, 128) != 0) mov_fail++;
  // The copy must also equal the source exactly.
  if (memcmp(&b, src, 128) != 0) mov_fail++;
}

static void check_cmp(const rdata_t *L, const rdata_t *R) {
  int o = cmp_old(L, R) ? 1 : 0;
  int n = cmp_new(L, R) ? 1 : 0;
  int truth = (memcmp(L, R, 128) == 0) ? 1 : 0;
  // Both must agree with each other AND with memcmp. Checking against memcmp
  // matters: if the old form were also wrong, agreement alone would prove
  // nothing.
  if (o != n || n != truth) cmp_fail++;
  cases++;
}

int main(void) {
  rdata_t x, y;

  // 1. Exhaustive single-bit difference: every one of the 1024 bit positions.
  //    A copy or compare that drops any byte lane shows up here immediately.
  for (int bit = 0; bit < 1024; bit++) {
    fill(&x);
    y = x;
    y.b[bit >> 3] ^= (u8)(1u << (bit & 7));
    check_cmp(&x, &y);   // must be "different"
    check_cmp(&x, &x);   // must be "same"
    check_mov(&y);
  }

  // 2. Exhaustive single-byte difference at every offset, with a value that
  //    differs in the high bit, since a signed-lane bug would hide a low one.
  for (int off = 0; off < 128; off++) {
    fill(&x);
    y = x;
    y.b[off] ^= 0x80;
    check_cmp(&x, &y);
    check_mov(&y);
  }

  // 3. Patterns that break naive vector reductions: all-zero, all-ones, and
  //    lanes that sum to the accumulator's success value by accident.
  memset(&x, 0x00, sizeof x); memset(&y, 0x00, sizeof y); check_cmp(&x, &y);
  memset(&y, 0xFF, sizeof y); check_cmp(&x, &y);
  memset(&x, 0xFF, sizeof x); check_cmp(&x, &y);
  memset(&y, 0x01, sizeof y); check_cmp(&x, &y);

  // 4. Randomised: mostly-equal pairs, which is the case the reservation path
  //    actually sees, plus fully random pairs.
  const u64 N = 4000000;
  for (u64 i = 0; i < N; i++) {
    fill(&x);
    y = x;
    if ((i & 3) != 0) {
      // Perturb one random byte: the near-miss case a compare must not pass.
      u64 r = rnd();
      y.b[r % 128] ^= (u8)(1u + (r >> 8) % 255);
    }
    check_cmp(&x, &y);
    if ((i & 63) == 0) check_mov(&x);
  }

  printf("cases=%llu  cmp_mismatches=%llu  mov_mismatches=%llu\n",
         (unsigned long long)cases, (unsigned long long)cmp_fail,
         (unsigned long long)mov_fail);
  if (cmp_fail || mov_fail) {
    printf("RESULT: MISMATCH - a rewrite is wrong and the crash has a cause here\n");
    return 1;
  }
  printf("RESULT: agree over the tested space; suspicion moves elsewhere\n");
  return 0;
}
