# AES: the hardware is there and the emulator never asks for it

Every AES operation this emulator performs on Thor runs in software, on a chip with
AES instructions.

## The finding

`Crypto/aesni.cpp` opens with:

```cpp
#if defined(__SSE2__) || defined(_M_X64)
```

The whole file. On AArch64 that is false, so nothing in it is compiled. And every
dispatch point in `Crypto/aes.cpp` carries the same guard:

| line | guarded call | ARM64 result |
| --- | --- | --- |
| 462 | `aesni_setkey_enc` | software key schedule |
| 567 | `aesni_inverse_key` | software inverse key |
| 666 | `aesni_crypt_ecb` | **software block encrypt/decrypt** |

What runs instead is the classic four-table PolarSSL implementation — `FT0`–`FT3`,
`RT0`–`RT3`, sixteen table lookups and a pile of XORs per round, ten to fourteen
rounds per block.

The device reports `aes pmull sha1 sha2 sha3 sha512` in `/proc/cpuinfo`. None of it
is reachable from this code path.

## Why it is worth caring about

AES is not incidental here. It is on the boot path:

- SELF/SPRX decryption — **every module**, and Eternal Sonata's cache build walks
  1187 of them, plus firmware PRX
- PKG install, EDAT/SDAT, save data

Two costs, not one. The obvious one is throughput: ARMv8 does a round in `AESE` +
`AESMC`, against sixteen dependent loads and XORs. The less obvious one is that the
software path streams 8 KB of lookup tables through L1 on a machine where the SPU and
PPU working sets are already fighting for it — and this fork has spent a lot of effort
on cache behaviour elsewhere.

**No number is claimed here.** The magnitude is an instruction-count argument, not a
measurement, and this project's own history says that is exactly when a confident
figure turns out wrong. What is certain is that the hardware path is not merely
slower to reach — it is absent from the binary.

## What implementing it requires

The AOT baseline does **not** include the crypto extension. Verified by asking the
compiler rather than reading the spec — `-march=armv8.4-a` expands to:

```
+complxnum +crc +dotprod +fp-armv8 +jsconv +lse +neon +outline-atomics
+pauth +ras +rcpc +rdm +v8.1a +v8.2a +v8.3a +v8.4a +v8a
```

No `+aes`, no `+sha2`, no `+sha3`, no `+i8mm`, no `+fullfp16`, no `+bf16` — all of
which this chip has. So an ARM64 AES path needs the feature turned on for those
functions specifically, which is the pattern the fork already uses elsewhere:
`__attribute__((target("+crypto")))` on the implementation, a runtime
`getauxval(AT_HWCAP) & HWCAP_AES` gate, and a software fallback that stays reachable —
the same shape as the `sha3`/`dotprod`/`i8mm` gating in `JITLLVM.cpp`.

The intrinsics are `vaeseq_u8` / `vaesmcq_u8` for encrypt and `vaesdq_u8` /
`vaesimcq_u8` for decrypt. Note that ARM's round structure is *not* a drop-in for
x86's: `AESE` performs AddRoundKey-then-SubBytes-then-ShiftRows, so the key schedule
and the round loop are shaped differently from `_mm_aesenc_si128`. Porting the x86
file by renaming intrinsics produces wrong output, which makes this a case for the
equivalence-test treatment `tools/rdata_equiv.c` already established: NIST vectors
plus a randomized differential run against the software path, mismatch count zero.

## The primitive now exists and is validated on device

`tools/aes_arm64_equiv.c` implements ARMv8 AES-128/192/256 block encrypt and
decrypt and proves it on the Thor:

```
FIPS-197 known-answer tests:
  AES-128 ok
  AES-192 ok
  AES-256 ok
randomized round-trip:
  600000 round-trips over 3 key sizes
failures=0
RESULT: ARMv8 AES matches FIPS-197 and inverts cleanly
```

Verified to be real hardware AES, not a fallback: `llvm-objdump` shows `aese`
followed immediately by `aesmc`, and `aesd` followed by `aesimc`.

**The first version of it was wrong, in the way that matters.** Encryption passed
all three known-answer vectors on the first attempt; decryption failed all three.
The bug was assuming the forward key schedule could simply be walked backwards.
It cannot: the equivalent inverse cipher moves `AddRoundKey` to the far side of
`InvMixColumns`, which is only legal because `InvMixColumns` is linear —

```
InvMixColumns(x XOR k) == InvMixColumns(x) XOR InvMixColumns(k)
```

— and that identity requires the *key* to be passed through `InvMixColumns` too.
So the decryption schedule is the forward one reversed with `AESIMC` applied to
the middle keys, first and last untouched. Which is precisely what PolarSSL's
`aes_setkey_dec` builds with its `RT` tables and what `aesni_inverse_key` builds
with `_mm_aesimc_si128` — the structure was in the x86 file all along.

That asymmetry is the argument for having built this as a standalone binary
first. A correct encrypt path with a broken decrypt path is the worst possible
outcome to discover by booting a game: decryption is the side that runs on every
SELF and SPRX, so the failure would have appeared as modules decrypting to
garbage, far from the cause.

## Measured, against the code it would replace

`tools/aes_arm64_bench.cpp` compiles `Crypto/aes.cpp` **unmodified** into the
harness, so the baseline is the four-table implementation that actually ships —
not a reimplementation and not a textbook byte-wise AES, either of which would
inflate the ratio.

Correctness is settled before any timing, and against that same code: 60,000
blocks over all three key sizes, encrypt and decrypt, **zero mismatches**. Matching
FIPS-197 proves it is AES; matching `aes_crypt_ecb` byte for byte proves it is a
drop-in for the function it would displace.

AES-128 ECB, both implementations pinned to the same core:

| core | op | software | ARMv8 AES | ratio |
| --- | --- | --- | --- | --- |
| Cortex-X3 | encrypt | 372.8 MB/s | 7277.7 MB/s | **19.5x** |
| | decrypt | 371.5 MB/s | 7006.7 MB/s | **18.9x** |
| A715/A710 | encrypt | 319.6 MB/s | 6976.0 MB/s | **21.8x** |
| | decrypt | 317.5 MB/s | 6924.0 MB/s | **21.8x** |
| Cortex-A510 | encrypt | 91.5 MB/s | 796.3 MB/s | **8.7x** |
| | decrypt | 88.1 MB/s | 796.3 MB/s | **9.0x** |

Decrypt is the column that matters: SELF and SPRX are decrypted and never
encrypted.

Pinning is not decoration. An earlier experiment in this project turned out to be
measuring which cluster an arm landed on rather than the change under test, so
both implementations are timed on the same core and every core is reported. The
A510 result is its own reminder — 796 MB/s against the X3's 7007, a factor of 8.8
on the *same* instructions, which is consistent with the A510 sharing one vector
unit between each core pair. Work scheduled onto the little cluster does not get
the same win.

Two honest limits on these figures. They are ECB block throughput over a
128 KB L2-resident buffer, so they are an upper bound on the primitive rather
than a prediction of boot time — the real path adds CBC chaining, file I/O and
per-module setup, and nothing here says what share of boot is AES. And the
software number is what this build produces; a different compiler or a
`POLARSSL_AES_ROM_TABLES` change would move it.

What the numbers do establish is that this is not a marginal call. A 19x gap on
the big cores is far outside anything that measurement noise, table warmth or
scheduling could account for.

## What it is worth at boot: not measurable on a warm boot

`tools/thor_aes_boot_ab.ps1` toggles the path at runtime via
`debug.rpcsx.thor.aes_arm64` — one build, two arms, alternating so thermal drift
lands on both — and times boot to `Cubeb: Stream started`:

```
  hardware AES : mean   2.00 s   min 1.99   max 2.01
  software AES : mean   1.98 s   min 1.97   max 1.99
  delta        :  -0.01 s (-0.6%)   worst within-arm spread: 0.03 s
```

The delta is smaller than the spread inside a single arm. **On a warm boot, AES is
not a measurable share of the time.** The 20x on the primitive is real and it is
not where these two seconds go.

That number needed checking before it could be believed, and the check is the
point. Two seconds looked far too fast against the ~25 s the same marker took
earlier, which is exactly the shape of a harness matching a stale log. It is not:
the log's mtime is current, its content is from the run, and SPU Workers and the
LLVM JIT are live in it. The earlier 25 s included PPU module compilation; with
caches fully warm the title reaches audio init in about two seconds.

**And the cold boot does not save it either.** That was the remaining defence —
a cold first boot walks firmware PRX and every SPRX, so surely *that* is where the
decryption volume is. It is, and the volume is small.

The firmware set is a static quantity, so it does not need a ten-minute boot to
measure:

```
/config/dev_flash/sys/external : 144 files, 13952 KB
```

**13.6 MB.** At the measured Cortex-X3 rates that is `13.6 / 371.5 = 36.6 ms`
of software AES against `13.6 / 7006.7 = 1.9 ms` of hardware AES — about **35
milliseconds saved** across the entire firmware set, against a cold boot that
takes minutes. Adding a generous 50 MB of game SPRX on top reaches roughly 130 ms.

So the question is closed, and the answer is no: **AES is not a meaningful share
of boot time, warm or cold.** A 19-22x speedup on a few tens of megabytes is tens
of milliseconds. The ratio was never the interesting number; the volume was, and
nobody had looked at it.

That is worth saying plainly because the 20x is exactly the kind of figure that
gets quoted. The change is still right — it is correct, it is free, it removes
8 KB of lookup tables from L1 on a machine that is short of it, and it is the
difference between using the hardware and not. It is simply not a boot-time
optimization, and this document would be misleading if it implied otherwise.

Where the volume *could* justify it, and where it remains unmeasured: **PKG
install**, which decrypts gigabytes rather than megabytes, and runtime EDAT/SDAT
access for games that stream encrypted data. Those are the cases worth timing
next, not boot.

## Three related things checked in the same pass, all negative

Recorded so they are not re-investigated.

**Acquire loads are already optimal.** The theory was that the JIT's `cortex-a78`
(Armv8.2) would miss FEAT_LRCPC and emit `LDAR` where `LDAPR` would do, on a chip
that has `lrcpc` and `ilrcpc` — and that this would matter because on x86 an acquire
load is a plain `MOV` and upstream therefore spends them freely. The compiler
disagrees: `-mcpu=cortex-a78` already emits `ldapr`, because LLVM's A78 model includes
RCpc regardless of the v8.2 baseline. Adding `+rcpc` changes nothing. Zero `ldar` in
the test either way.

**Non-temporal stores survive the x86 shim.** `utils::stream_vector` uses
`_mm_stream_si128`, which on ARM64 goes through `sse2neon.h` to
`__builtin_nontemporal_store` and really does emit `stnp`. The intent is not silently
dropped. It is *not* free, though: the non-temporal form costs an extra
`mov d1, v0.d[1]` and splits one 128-bit `str q0` into a 2x64-bit `stnp`, so whether
it wins on this core is an open microarchitectural question rather than an obvious
yes.

**`fullfp16` is moot.** The AOT baseline lacks it, but nothing in the emulator uses
`__fp16`, `float16x8_t`, or the fp16 convert intrinsics, so enabling it would change
no code.

## Correction to CLAUDE.md

CLAUDE.md stated the AOT build uses `-march=armv8.2-a`. It is **`armv8.4-a`** —
`app/build.gradle.kts:22` and `app/src/main/cpp/CMakeLists.txt:28` both default to it.
That changes the conclusion about what comes for free: `lse`, `rcpc`, `dotprod`,
`crc`, `complxnum` and `jsconv` are all implied, and the missing pieces are the
optional extensions listed above rather than everything past v8.2.
