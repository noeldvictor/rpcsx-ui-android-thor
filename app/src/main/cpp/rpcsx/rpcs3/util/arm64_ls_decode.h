#pragma once

// AArch64 load/store decoder for fault-handler use.
//
// Why this exists. `handle_access_violation` emulates RawSPU MMIO by decoding
// the faulting instruction, performing the register access itself, and stepping
// over it. On x86 that costs `decode_x64_reg_op`, a ~250-line parser for
// prefixes, ModRM and SIB, and the whole body is `#if defined(ARCH_X64)`.
//
// The hope was that AArch64 would need no decoder at all, because ESR carries a
// syndrome describing the access. That hope is dead: measured on this device,
// `ISV` reads 0 for every stage-1 translation fault, so `SAS`, `SRT`, `SSE` and
// `SF` are all zero and mean nothing. Only the exception class and `WnR` are
// usable, which is exactly what `decode_fault_reason` already consumes. See the
// fault-handler section of docs/arm64/ledger.md.
//
// So a decoder is required after all. It is far smaller than the x86 one -
// fixed 32-bit encodings, no prefixes, no ModRM, no SIB - and that is the whole
// of it below.
//
// **This is deliberately not wired into the signal handler.** Integration needs
// a RawSPU title to exercise it, and a mistake inside a fault handler turns a
// recoverable fault into a crash loop. What is safe to do now is the part that
// can be verified without a device: the decode itself, checked at compile time
// against encodings produced by the assembler rather than written from memory.

#include "util/types.hpp"

namespace rx::arm64
{
	enum class ls_op : u8
	{
		none,  // not a general-register load/store we handle
		load,
		store,
	};

	struct ls_info
	{
		ls_op op = ls_op::none;
		u8 reg = 0;            // Rt, 0-30; 31 is the zero register
		u8 size = 0;           // access width in bytes: 1, 2, 4 or 8
		bool sign_extend = false;
		bool dest_is_64 = false; // destination register width for loads

		constexpr bool valid() const noexcept { return op != ls_op::none; }
	};

	// Decode one instruction. Returns `op == none` for anything that is not a
	// general-register load or store, which includes the SIMD/FP forms (V=1),
	// PRFM, the atomic and exclusive families, and everything unallocated.
	//
	// Covers the three addressing modes a compiler emits for a plain pointer
	// dereference, which is what guest MMIO accesses compile to:
	//   - unsigned immediate offset   (LDR/STR  Xt, [Xn, #imm])
	//   - unscaled immediate          (LDUR/STUR Xt, [Xn, #simm])
	//   - register offset             (LDR/STR  Xt, [Xn, Xm])
	// Pre- and post-indexed forms are decoded too, but note the caller would
	// have to apply the base-register writeback itself; they are flagged the
	// same as any other load or store here.
	constexpr ls_info decode_load_store(u32 insn) noexcept
	{
		ls_info out{};

		// Common to every form handled here: bits 29:27 == 0b111 and V == 0.
		// V == 1 selects the SIMD/FP register file, which MMIO emulation would
		// have to handle separately and which no guest MMIO access produces.
		if (((insn >> 27) & 0x7) != 0x7 || ((insn >> 26) & 0x1) != 0)
		{
			return out;
		}

		const u32 size = (insn >> 30) & 0x3; // 00=byte 01=half 10=word 11=dword
		const u32 kind = (insn >> 24) & 0x3; // 01 = unsigned immediate form
		const u32 opc = (insn >> 22) & 0x3;

		if (kind == 0x1)
		{
			// Unsigned immediate offset. No further discrimination needed.
		}
		else if (kind == 0x0)
		{
			// Unscaled / register-offset / pre- and post-indexed all share this
			// major encoding and are separated by bit 21 and bits 11:10.
			const u32 op21 = (insn >> 21) & 0x1;
			const u32 op11 = (insn >> 10) & 0x3;

			if (op21 == 1)
			{
				// Register offset requires 11:10 == 0b10; other values here are
				// the atomic and exclusive families, which must not be treated
				// as plain accesses.
				if (op11 != 0x2)
				{
					return out;
				}
			}
			else
			{
				// 00 unscaled, 01 post-indexed, 11 pre-indexed. 10 is unallocated
				// in this corner.
				if (op11 == 0x2)
				{
					return out;
				}
			}
		}
		else
		{
			return out;
		}

		// opc selects direction and extension, and its meaning depends on size.
		//   00 store
		//   01 load, zero-extend
		//   10 load, sign-extend to 64  (size 11 is PRFM, not a load)
		//   11 load, sign-extend to 32  (only meaningful for size 00 and 01)
		switch (opc)
		{
		case 0x0:
			out.op = ls_op::store;
			out.dest_is_64 = (size == 0x3);
			break;
		case 0x1:
			out.op = ls_op::load;
			out.dest_is_64 = (size == 0x3);
			break;
		case 0x2:
			if (size == 0x3)
			{
				return out; // PRFM: a hint, not an access to emulate
			}
			out.op = ls_op::load;
			out.sign_extend = true;
			out.dest_is_64 = true;
			break;
		case 0x3:
			if (size >= 0x2)
			{
				return out; // unallocated
			}
			out.op = ls_op::load;
			out.sign_extend = true;
			out.dest_is_64 = false;
			break;
		default:
			return out;
		}

		out.reg = static_cast<u8>(insn & 0x1f);
		out.size = static_cast<u8>(1u << size);
		return out;
	}

	// Compile-time checks against encodings produced by the assembler, not
	// written from memory. Generated with NDK clang for aarch64-linux-android29
	// and read back with llvm-objdump, so the expected values are ground truth
	// rather than a second transcription of the same assumption.
	namespace decode_selftest
	{
		constexpr bool is(u32 insn, ls_op op, u8 reg, u8 size, bool sx, bool d64) noexcept
		{
			const ls_info i = decode_load_store(insn);
			return i.op == op && i.reg == reg && i.size == size && i.sign_extend == sx && i.dest_is_64 == d64;
		}

		// Unsigned immediate offset.
		static_assert(is(0xb9400041, ls_op::load, 1, 4, false, false), "ldr w1, [x2]");
		static_assert(is(0xf9400083, ls_op::load, 3, 8, false, true), "ldr x3, [x4]");
		static_assert(is(0x394000c5, ls_op::load, 5, 1, false, false), "ldrb w5, [x6]");
		static_assert(is(0x79400107, ls_op::load, 7, 2, false, false), "ldrh w7, [x8]");
		static_assert(is(0x39800149, ls_op::load, 9, 1, true, true), "ldrsb x9, [x10]");
		static_assert(is(0x7980018b, ls_op::load, 11, 2, true, true), "ldrsh x11, [x12]");
		static_assert(is(0xb98001cd, ls_op::load, 13, 4, true, true), "ldrsw x13, [x14]");
		static_assert(is(0xb900020f, ls_op::store, 15, 4, false, false), "str w15, [x16]");
		static_assert(is(0xf9000251, ls_op::store, 17, 8, false, true), "str x17, [x18]");
		static_assert(is(0x39000293, ls_op::store, 19, 1, false, false), "strb w19, [x20]");
		static_assert(is(0x790002d5, ls_op::store, 21, 2, false, false), "strh w21, [x22]");

		// Unscaled immediate.
		static_assert(is(0xb85fc317, ls_op::load, 23, 4, false, false), "ldur w23, [x24, #-4]");
		static_assert(is(0xf81f8359, ls_op::store, 25, 8, false, true), "stur x25, [x26, #-8]");

		// Register offset.
		static_assert(is(0xb8606b9b, ls_op::load, 27, 4, false, false), "ldr w27, [x28, x0]");
		static_assert(is(0xf8216bdd, ls_op::store, 29, 8, false, true), "str x29, [x30, x1]");

		// Things that must NOT decode as a plain access.
		static_assert(!decode_load_store(0xd503201f).valid(), "nop is not a load/store");
		static_assert(!decode_load_store(0x8b010000).valid(), "add x0, x0, x1 is not a load/store");
	}
} // namespace rx::arm64
