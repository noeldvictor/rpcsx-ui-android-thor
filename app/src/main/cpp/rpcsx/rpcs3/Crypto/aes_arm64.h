// ARMv8 AES block primitive for the PolarSSL AES path.
//
// Crypto/aesni.cpp is `#if defined(__SSE2__) || defined(_M_X64)`, so on AArch64
// every SELF, SPRX and PKG decryption ran the four-table software cipher on a
// chip that has AES instructions. Measured on a Snapdragon 8 Gen 2 against that
// exact software path: 18.9x faster decryption on the Cortex-X3, 21.8x on the
// A710/A715, 9.0x on an A510. Detail and method in docs/arm64/aes.md.
//
// WHY THIS TOUCHES NEITHER KEY SCHEDULE
//
// It consumes `ctx->rk` directly, for both directions, and that is a checked
// claim rather than a hopeful one. tools/aes_arm64_bench.cpp compares PolarSSL's
// schedules against independently derived ones over 60,000 random keys across
// all three key sizes:
//
//   forward schedule differs from PolarSSL enc ctx->rk: 0 / 60000
//   decrypt schedule differs from PolarSSL dec ctx->rk: 0 / 60000
//
// The decrypt case is the surprising one and the reason it was checked. x86
// does *not* reuse the software inverse schedule - `aes_setkey_dec` rebuilds it
// with `aesni_inverse_key` when AES-NI is present - which suggests the two are
// not interchangeable. On this code they are: PolarSSL's inverse schedule is
// already the equivalent-inverse-cipher form, the forward keys reversed with
// InvMixColumns applied to the middle ones, which is exactly what AESD wants.
//
// If that ever stops holding, the bench catches it as a nonzero count, and the
// symptom in the emulator would be every encrypted module decrypting to garbage.
//
// THE ROUND STRUCTURE IS NOT x86's
//
//   AESE(state, k) = ShiftRows(SubBytes(state XOR k))
//   AESMC(state)   = MixColumns(state)
//
// AESE folds AddRoundKey into the following SubBytes/ShiftRows, so the loop runs
// over keys 0..Nr-2 and the final AddRoundKey is a bare XOR with no MixColumns.
// Renaming _mm_aesenc_si128 to vaeseq_u8 produces a cipher that is not AES.

#pragma once

#if defined(__aarch64__)

#include <arm_neon.h>
#include <stdint.h>
#include <sys/auxv.h>

#ifndef HWCAP_AES
#define HWCAP_AES (1 << 3)
#endif

namespace rpcsx_aes_arm64
{
	// The shipped AOT baseline is armv8.4-a WITHOUT +crypto, so these need a
	// target attribute and a runtime gate; a global -march bump would fault on
	// any AArch64 device lacking the extension.
	inline bool supported() noexcept
	{
#ifdef RPCSX_AES_DISABLE_ARM64
		// Compile-time escape, for two reasons that both matter.
		//
		// It keeps tools/aes_arm64_bench.cpp honest: once aes_crypt_ecb routes
		// to hardware, a comparison against "the software path" would silently
		// become hardware-against-hardware and pass no matter what. The bench
		// builds aes.cpp with this defined so the baseline stays the real
		// four-table cipher.
		//
		// And it is a kill switch. This branch is on every SELF, SPRX and PKG
		// decryption, so if a title ever fails to load, rebuilding with this
		// defined answers "is it the AES change?" in one step rather than by
		// bisecting the cipher.
		return false;
#else
		static const bool value = (getauxval(AT_HWCAP) & HWCAP_AES) != 0;
		return value;
#endif
	}

	__attribute__((target("+crypto")))
	inline void encrypt_block(const uint8_t* rk, int rounds,
		const uint8_t* in, uint8_t* out) noexcept
	{
		uint8x16_t s = vld1q_u8(in);

		for (int r = 0; r < rounds - 1; r++)
		{
			s = vaesmcq_u8(vaeseq_u8(s, vld1q_u8(rk + r * 16)));
		}

		s = vaeseq_u8(s, vld1q_u8(rk + (rounds - 1) * 16));
		s = veorq_u8(s, vld1q_u8(rk + rounds * 16));

		vst1q_u8(out, s);
	}

	// `dk` is PolarSSL's decrypt-context schedule, used as-is. See above.
	__attribute__((target("+crypto")))
	inline void decrypt_block(const uint8_t* dk, int rounds,
		const uint8_t* in, uint8_t* out) noexcept
	{
		uint8x16_t s = vld1q_u8(in);

		for (int r = 0; r < rounds - 1; r++)
		{
			s = vaesimcq_u8(vaesdq_u8(s, vld1q_u8(dk + r * 16)));
		}

		s = vaesdq_u8(s, vld1q_u8(dk + (rounds - 1) * 16));
		s = veorq_u8(s, vld1q_u8(dk + rounds * 16));

		vst1q_u8(out, s);
	}
} // namespace rpcsx_aes_arm64

#endif // __aarch64__
