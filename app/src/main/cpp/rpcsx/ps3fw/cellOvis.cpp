#include "stdafx.h"
#include <atomic>
#include "Emu/Cell/PPUModule.h"
#include "cellos/sys_spu.h"

LOG_CHANNEL(cellOvis);

// Return Codes
enum CellOvisError : u32
{
	CELL_OVIS_ERROR_INVAL = 0x80410402,
	CELL_OVIS_ERROR_ABORT = 0x8041040C,
	CELL_OVIS_ERROR_ALIGN = 0x80410410,
};

template <>
void fmt_class_string<CellOvisError>::format(std::string& out, u64 arg)
{
	format_enum(out, arg, [](auto error)
		{
			switch (error)
			{
				STR_CASE(CELL_OVIS_ERROR_INVAL);
				STR_CASE(CELL_OVIS_ERROR_ABORT);
				STR_CASE(CELL_OVIS_ERROR_ALIGN);
			}

			return unknown;
		});
}

// DOES THE ELF THE TITLE HANDS US ACTUALLY HAVE OVERLAYS?
//
// This returns 0 - "no overlay table needed" - for every ELF, and
// cellOvisFixSpuSegments below does nothing at all. That is only harmless if
// the images really have no overlay segments.
//
// It matters because the HLE SPURS path calls this 22 times and the LLE path
// never calls it once, measured on the same title in the same scene. If these
// images DO carry overlays, then under HLE the task loader is loading
// incomplete SPU code, which is consistent with tasks that run and drain their
// queue while nothing is ever drawn.
//
// So count the segments before deciding. An SPU ELF is ELFCLASS32/ELFDATA2MSB;
// overlays show up as multiple PT_LOAD segments sharing a virtual address.
static void thor_report_spu_elf_overlays(vm::cptr<char> elf)
{
	static std::atomic<u32> s_n{0};

	const u32 n = s_n++;

	if (n >= 4 || !elf)
	{
		return;   // the first few answer the question; this is not a hot path worth spamming
	}

	const u32 base = elf.addr();
	const u8 magic0 = vm::_ref<u8>(base + 0);

	if (magic0 != 0x7f)
	{
		cellOvis.error("Thor OVIS #%u: not an ELF at 0x%x (first byte 0x%02x)", n, base, magic0);
		return;
	}

	const u16 e_type = vm::_ref<be_t<u16>>(base + 0x10);
	const u16 e_machine = vm::_ref<be_t<u16>>(base + 0x12);
	const u32 e_phoff = vm::_ref<be_t<u32>>(base + 0x1C);
	const u16 e_phentsize = vm::_ref<be_t<u16>>(base + 0x2A);
	const u16 e_phnum = vm::_ref<be_t<u16>>(base + 0x2C);

	cellOvis.error("Thor OVIS #%u: elf@0x%x type=%u machine=%u phnum=%u phentsize=%u",
		n, base, e_type, e_machine, e_phnum, e_phentsize);

	// PT_LOAD segments, and whether any two share a vaddr (the overlay tell).
	u32 loads = 0;
	u32 dupes = 0;
	u32 vaddrs[32]{};

	for (u32 i = 0; i < e_phnum && i < 32; i++)
	{
		const u32 ph = base + e_phoff + i * e_phentsize;
		const u32 p_type = vm::_ref<be_t<u32>>(ph + 0x00);
		const u32 p_vaddr = vm::_ref<be_t<u32>>(ph + 0x08);
		const u32 p_filesz = vm::_ref<be_t<u32>>(ph + 0x10);

		if (p_type != 1)   // PT_LOAD
		{
			continue;
		}

		for (u32 k = 0; k < loads; k++)
		{
			if (vaddrs[k] == p_vaddr) { dupes++; break; }
		}

		vaddrs[loads] = p_vaddr;
		loads++;

		cellOvis.error("Thor OVIS #%u:   PT_LOAD[%u] vaddr=0x%05x filesz=0x%x", n, i, p_vaddr, p_filesz);
	}

	cellOvis.error("Thor OVIS #%u: PT_LOAD=%u shared-vaddr=%u -> %s",
		n, loads, dupes,
		dupes ? "HAS OVERLAYS, returning 0 is WRONG" : "no overlays, returning 0 is correct");
}

error_code cellOvisGetOverlayTableSize(vm::cptr<char> elf)
{
	cellOvis.todo("cellOvisGetOverlayTableSize(elf=%s)", elf);
	thor_report_spu_elf_overlays(elf);
	return CELL_OK;
}

error_code cellOvisInitializeOverlayTable(vm::ptr<void> ea_ovly_table, vm::cptr<char> elf)
{
	cellOvis.todo("cellOvisInitializeOverlayTable(ea_ovly_table=*0x%x, elf=%s)", ea_ovly_table, elf);
	return CELL_OK;
}

void cellOvisFixSpuSegments(vm::ptr<sys_spu_image> image)
{
	cellOvis.todo("cellOvisFixSpuSegments(image=*0x%x)", image);
}

void cellOvisInvalidateOverlappedSegments(vm::ptr<sys_spu_segment> segs, vm::ptr<int> nsegs)
{
	cellOvis.todo("cellOvisInvalidateOverlappedSegments(segs=*0x%x, nsegs=*0x%x)", segs, nsegs);
}

DECLARE(ppu_module_manager::cellOvis)("cellOvis", []()
	{
		REG_FUNC(cellOvis, cellOvisGetOverlayTableSize);
		REG_FUNC(cellOvis, cellOvisInitializeOverlayTable);
		REG_FUNC(cellOvis, cellOvisFixSpuSegments);
		REG_FUNC(cellOvis, cellOvisInvalidateOverlappedSegments);
	});
