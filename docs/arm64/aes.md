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
