#include "stdafx.h"
#ifdef ANDROID
#include <sys/system_properties.h>
#endif
#include <atomic>
#include <cstdio>
#include "Loader/ELF.h"

#include "Emu/Memory/vm_reservation.h"
#include "Emu/Cell/SPUThread.h"
#include "Emu/Cell/SPURecompiler.h"
#include "cellSpurs.h"

#include "rx/asm.hpp"
#include "util/v128.hpp"
#include "util/simd.hpp"

LOG_CHANNEL(cellSpurs);

// Temporarily
#ifndef _MSC_VER
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#endif

//----------------------------------------------------------------------------
// Function prototypes
//----------------------------------------------------------------------------

//
// SPURS utility functions
//
static void cellSpursModulePutTrace(CellSpursTracePacket* packet, u32 dmaTagId);
static u32 cellSpursModulePollStatus(spu_thread& spu, u32* status);
static void cellSpursModuleExit(spu_thread& spu);

static bool spursDma(spu_thread& spu, u32 cmd, u64 ea, u32 lsa, u32 size, u32 tag);
static u32 spursDmaGetCompletionStatus(spu_thread& spu, u32 tagMask);
static u32 spursDmaWaitForCompletion(spu_thread& spu, u32 tagMask, bool waitForAll = true);
static void spursHalt(spu_thread& spu);

//
// SPURS kernel functions
//
static bool spursKernel1SelectWorkload(spu_thread& spu);
static bool spursKernel2SelectWorkload(spu_thread& spu);
static void spursKernelDispatchWorkload(spu_thread& spu, u64 widAndPollStatus);
static bool spursKernelWorkloadExit(spu_thread& spu);
bool spursKernelEntry(spu_thread& spu);

//
// SPURS system workload functions
//
static bool spursSysServiceEntry(spu_thread& spu);
// TODO: Exit
static void spursSysServiceIdleHandler(spu_thread& spu, SpursKernelContext* ctxt);
static void spursSysServiceMain(spu_thread& spu, u32 pollStatus);
static void spursSysServiceProcessRequests(spu_thread& spu, SpursKernelContext* ctxt);
static void spursSysServiceActivateWorkload(spu_thread& spu, SpursKernelContext* ctxt);
// TODO: Deactivate workload
static void spursSysServiceUpdateShutdownCompletionEvents(spu_thread& spu, SpursKernelContext* ctxt, u32 wklShutdownBitSet);
static void spursSysServiceTraceSaveCount(spu_thread& spu, SpursKernelContext* ctxt);
static void spursSysServiceTraceUpdate(spu_thread& spu, SpursKernelContext* ctxt, u32 arg2, u32 arg3, u32 forceNotify);
// TODO: Deactivate trace
// TODO: System workload entry
static void spursSysServiceCleanupAfterSystemWorkload(spu_thread& spu, SpursKernelContext* ctxt);

//
// SPURS taskset policy module functions
//
static bool spursTasksetEntry(spu_thread& spu);
static bool spursTasksetSyscallEntry(spu_thread& spu);
static void spursTasksetResumeTask(spu_thread& spu);
static void spursTasksetStartTask(spu_thread& spu, CellSpursTaskArgument& taskArgs);
static s32 spursTasksetProcessRequest(spu_thread& spu, s32 request, u32* taskId, u32* isWaiting);
static void spursTasksetProcessPollStatus(spu_thread& spu, u32 pollStatus);
static bool spursTasksetPollStatus(spu_thread& spu);
static void spursTasksetExit(spu_thread& spu);
static void spursTasksetOnTaskExit(spu_thread& spu, u64 addr, u32 taskId, s32 exitCode, u64 args);
static s32 spursTasketSaveTaskContext(spu_thread& spu);
static void spursTasksetDispatch(spu_thread& spu);
static s32 spursTasksetProcessSyscall(spu_thread& spu, u32 syscallNum, u32 args);
static void spursTasksetInit(spu_thread& spu, u32 pollStatus);
static s32 spursTasksetLoadElf(spu_thread& spu, u32* entryPoint, u32* lowestLoadAddr, u64 elfAddr, bool skipWriteableSegments);

//
// SPURS jobchain policy module functions
//
bool spursJobChainEntry(spu_thread& spu);
void spursJobchainPopUrgentCommand(spu_thread& spu);

//----------------------------------------------------------------------------
// SPURS utility functions
//----------------------------------------------------------------------------

// Output trace information
void cellSpursModulePutTrace(CellSpursTracePacket* packet, u32 dmaTagId)
{
	// TODO: Implement this
}

// Check for execution right requests
u32 cellSpursModulePollStatus(spu_thread& spu, u32* status)
{
	auto ctxt = spu._ptr<SpursKernelContext>(0x100);

	spu.gpr[3]._u32[3] = 1;
	if (ctxt->spurs->flags1 & SF1_32_WORKLOADS)
	{
		spursKernel2SelectWorkload(spu);
	}
	else
	{
		spursKernel1SelectWorkload(spu);
	}

	auto result = spu.gpr[3]._u64[1];
	if (status)
	{
		*status = static_cast<u32>(result);
	}

	u32 wklId = result >> 32;
	return wklId == ctxt->wklCurrentId ? 0 : 1;
}

// Exit current workload
void cellSpursModuleExit(spu_thread& spu)
{
	auto ctxt = spu._ptr<SpursKernelContext>(0x100);
	spu.pc = ctxt->exitToKernelAddr;

	// TODO: use g_escape for actual long jump
	// throw SpursModuleExit();
}

// Execute a DMA operation
bool spursDma(spu_thread& spu, const spu_mfc_cmd& args)
{
	spu.ch_mfc_cmd = args;

	if (!spu.process_mfc_cmd())
	{
		spu_runtime::g_escape(&spu);
	}

	if (args.cmd == MFC_GETLLAR_CMD || args.cmd == MFC_PUTLLC_CMD || args.cmd == MFC_PUTLLUC_CMD)
	{
		return static_cast<u32>(spu.get_ch_value(MFC_RdAtomicStat)) != MFC_PUTLLC_FAILURE;
	}

	return true;
}

// Execute a DMA operation
bool spursDma(spu_thread& spu, u32 cmd, u64 ea, u32 lsa, u32 size, u32 tag)
{
	return spursDma(spu, {MFC(cmd), static_cast<u8>(tag & 0x1f), static_cast<u16>(size & 0x7fff), lsa, static_cast<u32>(ea), static_cast<u32>(ea >> 32)});
}

// Get the status of DMA operations
u32 spursDmaGetCompletionStatus(spu_thread& spu, u32 tagMask)
{
	spu.set_ch_value(MFC_WrTagMask, tagMask);
	spu.set_ch_value(MFC_WrTagUpdate, MFC_TAG_UPDATE_IMMEDIATE);
	return static_cast<u32>(spu.get_ch_value(MFC_RdTagStat));
}

// Wait for DMA operations to complete
u32 spursDmaWaitForCompletion(spu_thread& spu, u32 tagMask, bool waitForAll)
{
	spu.set_ch_value(MFC_WrTagMask, tagMask);
	spu.set_ch_value(MFC_WrTagUpdate, waitForAll ? MFC_TAG_UPDATE_ALL : MFC_TAG_UPDATE_ANY);
	return static_cast<u32>(spu.get_ch_value(MFC_RdTagStat));
}

// Halt the SPU
void spursHalt(spu_thread& spu)
{
	spu.halt();
}

void sys_spu_thread_exit(spu_thread& spu, s32 status)
{
	// Cancel any pending status update requests
	spu.set_ch_value(MFC_WrTagUpdate, 0);
	while (spu.get_ch_count(MFC_RdTagStat) != 1)
		;
	spu.get_ch_value(MFC_RdTagStat);

	// Wait for all pending DMA operations to complete
	spu.set_ch_value(MFC_WrTagMask, 0xFFFFFFFF);
	spu.set_ch_value(MFC_WrTagUpdate, MFC_TAG_UPDATE_ALL);
	spu.get_ch_value(MFC_RdTagStat);

	spu.set_ch_value(SPU_WrOutMbox, status);
	spu.stop_and_signal(0x102);
}

void sys_spu_thread_group_exit(spu_thread& spu, s32 status)
{
	// Cancel any pending status update requests
	spu.set_ch_value(MFC_WrTagUpdate, 0);
	while (spu.get_ch_count(MFC_RdTagStat) != 1)
		;
	spu.get_ch_value(MFC_RdTagStat);

	// Wait for all pending DMA operations to complete
	spu.set_ch_value(MFC_WrTagMask, 0xFFFFFFFF);
	spu.set_ch_value(MFC_WrTagUpdate, MFC_TAG_UPDATE_ALL);
	spu.get_ch_value(MFC_RdTagStat);

	spu.set_ch_value(SPU_WrOutMbox, status);
	spu.stop_and_signal(0x101);
}

s32 sys_spu_thread_send_event(spu_thread& spu, u8 spup, u32 data0, u32 data1)
{
	if (spup > 0x3F)
	{
		return CELL_EINVAL;
	}

	if (spu.get_ch_count(SPU_RdInMbox))
	{
		return CELL_EBUSY;
	}

	spu.set_ch_value(SPU_WrOutMbox, data1);
	spu.set_ch_value(SPU_WrOutIntrMbox, (spup << 24) | (data0 & 0x00FFFFFF));
	return static_cast<u32>(spu.get_ch_value(SPU_RdInMbox));
}

s32 sys_spu_thread_switch_system_module(spu_thread& spu, u32 status)
{
	if (spu.get_ch_count(SPU_RdInMbox))
	{
		return CELL_EBUSY;
	}

	u32 result;

	// Cancel any pending status update requests
	spu.set_ch_value(MFC_WrTagUpdate, 0);
	while (spu.get_ch_count(MFC_RdTagStat) != 1)
		;
	spu.get_ch_value(MFC_RdTagStat);

	// Wait for all pending DMA operations to complete
	spu.set_ch_value(MFC_WrTagMask, 0xFFFFFFFF);
	spu.set_ch_value(MFC_WrTagUpdate, MFC_TAG_UPDATE_ALL);
	spu.get_ch_value(MFC_RdTagStat);

	do
	{
		spu.set_ch_value(SPU_WrOutMbox, status);
		spu.stop_and_signal(0x120);
		result = static_cast<u32>(spu.get_ch_value(SPU_RdInMbox));
	} while (result == CELL_EBUSY);

	return result;
}

//----------------------------------------------------------------------------
// SPURS kernel functions
//----------------------------------------------------------------------------

// Select a workload to run
// THOR HLE SPURS DIAGNOSIS, one shot per SPU.
//
// The branch is stuck with every SPU selecting wid=32 (the system service) once
// and never again. cellSpursModulePollStatus only reports "leave" when the
// selected workload DIFFERS from the current one, and selection can only pick a
// workload whose ctxt->wklRunnable1 bit is set - which is set only from
// spurs->wklState1[i] == SPURS_WKL_STATE_RUNNABLE.
//
// So exactly two things need to be known, and neither is guessable:
//   1. does spursSysServiceActivateWorkload run at all on each SPU?
//   2. when it does, what does it actually READ out of wklState1?
//
// ONE SHOT PER SPU. Per-iteration logging on this path has boot-looped this
// branch twice: six SPUs run these functions continuously.
static std::atomic<u32> g_thor_hle_req_logged{0};
static std::atomic<u32> g_thor_hle_act_logged{0};

// Keep the research counters and log formatting out of normal Android builds.
// Diagnostic APKs still require the explicit runtime property before launch.
#if defined(ANDROID) && !defined(RPCSX_THOR_SPURS_PROBE)
static FORCE_INLINE constexpr bool thor_hle_spurs_diagnostics() noexcept
{
	return false;
}
#else
static bool thor_hle_spurs_diagnostics() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char value[PROP_VALUE_MAX]{};
		return __system_property_get("debug.rpcsx.thor.spurs_probe", value) > 0 &&
			value[0] && value[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}
#endif

// Record the narrow Transformers edge-Zlib scheduling boundary without the
// high-volume general SPURS probe. This is a bounded diagnostic only.
//
//   debug.rpcsx.thor.edge_task_census = 1
static bool thor_edge_task_census() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char value[PROP_VALUE_MAX]{};
		return __system_property_get("debug.rpcsx.thor.edge_task_census", value) > 0 &&
			value[0] && value[0] != '0';
	}();
	return s_on;
#else
	return false;
#endif
}

// Gate for the wklSignal clear fix. **DEFAULT OFF - the fix REGRESSES HLE.**
//
//   debug.rpcsx.thor.spurs_signal_fix = 0  original unguarded shift (default)
//   debug.rpcsx.thor.spurs_signal_fix = 1  guard the sentinel
//
// MEASURED 2026-08-25, one binary, four interleaved arms, 150 s settle:
//
//   fix=1  armed=0  emu stalls at 0:00:04   (2 of 2)
//   fix=0  armed=6  emu reaches 0:00:17     (2 of 2)
//
// The undefined shift is REAL: `0x8000 >> 32` is UB and AArch64 evaluates it as
// `>> 0`, so the line clears workload 0's signal, and the PPU can be seen writing
// the signal and reading 0x0 back one line later. But the SPURS state machine
// DEPENDS on that accidental clear. With the signal left standing,
// cellSpursModulePollStatus reports "selected workload differs from current" on
// every call, the SPU exits to the kernel and re-selects forever, and emulation
// livelocks before SPURS even arms.
//
// So the clear is load-bearing and the correct repair is NOT to delete it. What
// is needed is a consume-on-dispatch that clears the signal for the workload the
// SPU actually runs, without relying on a shift that only works by accident.
// Until that exists, the original behaviour ships.
//
// The fix is correct on its own terms - `0x8000 >> 32` is undefined and AArch64
// evaluates it as `>> 0`, clearing workload 0 - but correctness of the shift does
// not prove it is the cause of a later crash, and attributing by reasoning is how
// this session has already been wrong twice. One property, two arms, same binary.
// EVERY one-shot probe on this path fires at FIRST entry, which is BEFORE the
// PPU has created and activated the workload. That is why select#1 has always
// printed runnable=0 prio=0 maxCont=0: it was reading pre-activation state, not
// a stuck gate. To see the gate that actually deadlocks, fire on the Nth call
// instead of the first.
//
//   debug.rpcsx.thor.sel_probe_nth = N   (default 200, 0 disables)
static u32 thor_sel_probe_nth() noexcept
{
#ifdef ANDROID
	static const u32 s_n = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.sel_probe_nth", v) <= 0 || !v[0])
		{
			return 200u;
		}
		return static_cast<u32>(std::atoi(v));
	}();
	return s_n;
#else
	return 0u;
#endif
}

static bool thor_hle_nth(std::atomic<u32>& counter, u32 spuNum) noexcept
{
	const u32 n = thor_sel_probe_nth();
	if (!n || spuNum >= 8)
	{
		return false;
	}
	// one counter per SPU packed into the caller's atomic is not enough, so the
	// caller passes a per-SPU counter array element
	return counter.fetch_add(1) == n;
}

// REFRESH THE TASKSET SNAPSHOT BEFORE READING IT.
//
// SpursTasksetContext begins with `tempAreaTaskset[0x80]` at LS 0x2700 - a
// 128-byte scratch meant to hold a DMA'd copy of the taskset head. CellSpursTaskset
// keeps `spurs` at 0x60 and `args` at 0x68, both inside those 128 bytes, which is
// why the code reads `spu._ptr<CellSpursTaskset>(0x2700)`.
//
// NOTHING EVER FILLS IT. spursTasksetEntry memsets the whole context, scratch
// included, and the only other write is
// `memcpy(spu._ptr<void>(0x2700), spu._ptr<void>(0x100), 128)` at the end of
// spursTasksetProcessRequest - which copies the KERNEL's CellSpurs head from LS
// 0x100, the wrong structure, and runs before spursTasksetStartTask reads it.
//
// MEASURED: the task halts on `HEQI` at pc=0x04a00 with r55 = 0, and the trap
// decoder reports `arg r4 = 00000000 00000000 00000000 00000000` - the SPURS
// address and taskset args that spursTasksetStartTask is supposed to hand it.
// The guest refused a zero it should never have seen.
//
// This is the same defect the idle handler already documents ("REFRESH THE
// SNAPSHOT BEFORE READING IT") and the same repair: copy the live structure in
// before reading, keeping every read local. Exactly 128 bytes, so it lands in
// tempAreaTaskset and cannot touch the context fields that start at 0x2780.
//
//   debug.rpcsx.thor.taskset_snapshot_fix = 0 disables
static bool thor_taskset_snapshot_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.taskset_snapshot_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static void thor_refresh_taskset_snapshot(spu_thread& spu, SpursTasksetContext* ctxt) noexcept
{
	if (!thor_taskset_snapshot_fix() || !ctxt->taskset)
	{
		return;
	}

	std::memcpy(spu._ptr<void>(0x2700), ctxt->taskset.get_ptr(), 128);
}

// PROCESS TASKSET REQUESTS WITH THE FIRMWARE RESERVATION CONTRACT.
//
// The taskset policy module at LS 0xE40 reads the 128-byte taskset head with
// GETLLAR for every request, updates it in local store, and retries PUTLLC
// until it succeeds.
// The old HLE path reads and writes the six bitmaps without one transaction.
// A PPU signal can therefore race an SPU wait and leave the task state or the
// ready count inconsistent.
//
// The route switch lets one APK test both behaviors.
//
//   debug.rpcsx.thor.taskset_select_atomic = 1  use the reservation contract
static bool thor_taskset_select_atomic() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		return __system_property_get("debug.rpcsx.thor.taskset_select_atomic", v) > 0 &&
			v[0] && v[0] != '0';
	}();
	return s_on;
#else
	return false;
#endif
}

static v128 thor_load_task_bitmap(const be_t<u32> (&words)[4]) noexcept
{
	be_t<v128> bitmap;
	std::memcpy(&bitmap, words, sizeof(bitmap));
	return bitmap;
}

static void thor_store_task_bitmap(be_t<u32> (&words)[4], v128 bitmap) noexcept
{
	const be_t<v128> stored = bitmap;
	std::memcpy(words, &stored, sizeof(stored));
}

static bool thor_release_idle_taskset() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.release_idle_taskset", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_contention_atomic_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.contention_atomic_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_pending_contention_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.pending_contention_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

// WHO ACTUALLY HOLDS A CONTENTION SLOT.
//
// The hang always reads the same: wkl2 maxCont=1 cont=1 rawCont=0x01, and
// every SPU that PRINTS reports curId=32 locC=0. That is consistent with two
// very different worlds - a real holder that is busy inside a task and so
// never reaches the selector to print, or a leaked slot with no holder at all
// - and the printed lines cannot tell them apart, because an SPU inside a task
// is exactly the SPU that does not appear.
//
// Record the holder as the counter is moved, so the question has an answer.
// Bit n means SPU n believes it holds that workload.
static std::atomic<u32> g_thor_wkl_holders[CELL_SPURS_MAX_WORKLOAD]{};

static void thor_hold_wkl(u32 wid, u32 spu_num) noexcept
{
	if (wid < CELL_SPURS_MAX_WORKLOAD && spu_num < 32)
	{
		g_thor_wkl_holders[wid] |= (1u << spu_num);
	}
}

static void thor_release_wkl(u32 wid, u32 spu_num) noexcept
{
	if (wid < CELL_SPURS_MAX_WORKLOAD && spu_num < 32)
	{
		g_thor_wkl_holders[wid] &= ~(1u << spu_num);
	}
}

// WAIT FOR DMA BEFORE DISPATCHING A TASKSET SYSCALL.
//
// Read out of the real taskset policy module, captured under LLE and
// disassembled (_research/spurs/real_taskset_pm.bin, handler at 0x1c58):
//
//     00001c78: brz  r2,0x00001c84        ; version flag decides
//     00001c7c: andi r5,r3,0xf            ; syscallNum & 0xF
//     00001c84: il   r4,-0x1
//     00001c88: il   r3,0x2
//     00001c8c: wrch r4,ch22              ; MFC_WrTagMask  = -1
//     00001c90: wrch r3,ch23              ; MFC_WrTagUpdate = 2
//     00001c94: rdch r2,ch24              ; MFC_RdTagStat - WAIT FOR ALL DMA
//     00001c98: shli r10,r5,0x2           ; then dispatch through the table
//
// The firmware drains every outstanding transfer before it will look at a
// syscall. Our copy has the same shape - the `(syscallNum & 0x10) == 0` guard
// is the same version test - but the call inside it was left commented out,
// so the syscall is serviced while the task's DMA may still be in flight.
// Anything the task wrote by DMA and expects the policy module to see is then
// read too early.
//
//   debug.rpcsx.thor.syscall_dma_wait = 0 restores the previous behaviour
static bool thor_yield_poll_always() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.yield_poll_always", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_exit_destroy_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.exit_destroy_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_syscall_dma_wait() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.syscall_dma_wait", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_contention_orphan_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.contention_orphan_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_task_ls_clear_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.task_ls_clear_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

// A YIELD WITH NOTHING ELSE TO RUN MUST BE CHEAP.
//
// The yield case runs `pollStatus || REQUEST_POLL || thor_yield_redispatch_fix()`,
// and the last term is a fallback that is ALWAYS TRUE. So every yield takes the
// expensive arm: spursTasketSaveTaskContext, a YIELD_TASK request, and a full
// re-dispatch - even when no other workload and no other task want the SPU.
//
// The task's ls_pattern is the "entire LS is saved" sentinel
// (0x03FFFFFFFFFFFFFF/0xFFFFFFFFFFFFFFFF), so each of those costs a save and a
// restore of essentially all 256 KB of local store. Measured 17,408 yields in
// four minutes against 338 useful queue operations - roughly 4 GB of memcpy to
// accomplish nothing, and it is the best available explanation for HLE running
// at ~1% of LLE (4,900 draws vs 631,921; <200k SPU DMAs vs 21.6M).
//
// On hardware cellSpursYield returns immediately when nothing else is runnable
// and the task simply continues. This does the same: if neither poll found work,
// return without saving anything and let the task keep the SPU.
//
// Short-circuit order is preserved exactly - spursTasksetPollStatus is always
// evaluated for its side effect, and REQUEST_POLL only when it returns false,
// which is what `a || b` did before.
//
//   debug.rpcsx.thor.yield_fast_path = 1
static bool thor_yield_fast_path() noexcept
{
#ifdef __ANDROID__
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		return __system_property_get("debug.rpcsx.thor.yield_fast_path", v) > 0 && v[0] && v[0] != '0';
	}();
	return s_on;
#else
	return false;
#endif
}

static bool thor_spurs_sel_cond_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.spurs_sel_cond_fix", v) <= 0 || !v[0])
		{
			return false;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return false;
#endif
}

// COMMIT THE UPDATED TASKSET STATE, NOT THE VALUES IT WAS READ WITH.
//
// Every arm of the switch in spursTasksetProcessRequest mutates `signalled0`
// and `ready0` - those ARE the new values - while the writeback below stored
// `signalled` and `ready`, the words as they were read. So every state
// transition the request made was computed and then thrown away.
//
// This is a transcription bug, not a design choice. Upstream RPCS3 has the
// whole writeback COMMENTED OUT (Emu/Cell/Modules/cellSpursSpu.cpp), so its
// variable names were never exercised by a running system; uncommenting the
// block brought the stale names with it.
//
// WHAT IT COSTS: a signal can never be consumed. `_cellSpursSendSignal` only
// raises the workload signal when `~signalled & waiting & mask` is 1, so once
// `signalled` latches it stays latched, the workload stops being signalled,
// and the task that would clear it can only clear it BY RUNNING. Measured
// state at the stall is exactly that fixed point:
//
//     waiting=80000000  signalled=80000000   (set, never consumed)
//     gate: wkl0 signal=0, wkl1 signal=0
//
// and the consumer drains ~40 entries before freezing while the producer
// jams on a full ring. The black-screen HLE run is this deadlock: no SPURS
// task completes, so no geometry reaches RSX (6.6% GPU) while the frame
// counter keeps presenting empty frames at the 30 cap.
//
// DESTROY_TASK leaks the same way - it clears the task from `ready0` and
// `signalled0`, so without this the taskset keeps a destroyed task marked
// ready forever.
//
// The taskset invariant still holds after the change: `ready & pending_ready`
// is 0 because pending_ready is stored as 0 and ready0 absorbs it, and
// `enabled` stays a subset of running|ready|pready|signalled|waiting in both
// the park path (waiting gets the bit) and the select path (running does).
//
//   debug.rpcsx.thor.taskset_writeback_fix = 0  restore the discarding writeback
static bool thor_taskset_writeback_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.taskset_writeback_fix", v) <= 0 || !v[0])
		{
			return true;   // ON by default: the discarding writeback is a defect
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

// LET A YIELD ACTUALLY RETURN TO THE KERNEL.
//
// spursTasksetProcessSyscall only re-dispatches at the bottom of the function,
// and only when `incident` is set:
//
//     if (incident) { pollStatus ? spursTasksetExit(spu) : spursTasksetDispatch(spu); }
//
// The YIELD arm sets `incident` only inside its
// `if (pollStatus || REQUEST_POLL)` branch, and for a ONE-TASK taskset both
// halves are permanently 0:
//
//   - REQUEST_POLL computes `readyButNotRunning = gv_andn(running, ready0)`.
//     The only enabled task is the one doing the polling, so the set is empty.
//   - spursTasksetPollStatus returns 1 only if the workload selector picks a
//     DIFFERENT workload, which it does not here.
//
// So every yield is a no-op, no dispatch follows, the guest resumes and yields
// again. MEASURED: 3,200+ yields against `dispatches: 1` and `select: 1`, with
// six SPUs pinned at pc=0x00a70. The SPU is CAPTURED inside the taskset and the
// kernel can never re-select the workload, which is the stall.
//
// Upstream guards the yield to avoid a pointless context save/restore when
// nothing else can run. That is an OPTIMISATION, not a correctness rule: with
// the guard lifted, SELECT_TASK simply re-selects the same task and resumes it
// - and if the task has genuinely parked, SELECT_TASK returns MAX_TASK and the
// taskset EXITS, handing the SPU back so a push can re-select the workload.
// That is the normal SPURS lifecycle the capture was preventing.
//
// Costs a context save/restore per yield, so it is measured, not assumed.
//
// THROTTLE IT. Re-dispatching on EVERY yield is correct but ruinously
// expensive: spursTasketSaveTaskContext copies 0x380 bytes plus up to 122 2KB
// local store blocks, and the restore copies the same back, so each yield
// moves about 244KB twice. The task was measured yielding 273,152 times in one
// run - on the order of 130 GB of memcpy - which is enough to starve the task
// of forward progress all by itself and to look like a spin.
//
// Handing the SPU back does not have to happen on every yield; it has to
// happen OFTEN ENOUGH that the kernel can re-select a workload and that a
// parked task can be noticed. One in N is enough for that and costs 1/N of the
// copying.
//
//   debug.rpcsx.thor.yield_redispatch_fix = 0   never (upstream behaviour)
//   debug.rpcsx.thor.yield_redispatch_fix = 1   every yield
//   debug.rpcsx.thor.yield_redispatch_fix = N   every Nth yield (N power of 2)
static u32 thor_yield_redispatch_every() noexcept
{
#ifdef ANDROID
	static const u32 s_n = []() noexcept -> u32
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.yield_redispatch_fix", v) <= 0 || !v[0])
		{
			return 0;
		}

		const long parsed = std::strtol(v, nullptr, 10);
		return parsed > 0 ? static_cast<u32>(parsed) : 0;
	}();
	return s_n;
#else
	return 0;
#endif
}

// ONE-SHOT EXECUTION PROBES INSIDE A REAL POLICY MODULE.
//
// `RunHleFunction` replaces the block at a registered pc and its caller does
// `continue`, which re-evaluates pc. So a probe that LOGS, UNREGISTERS ITSELF
// and returns true lets the genuine instruction execute on the very next
// iteration - a one-shot "execution reached here" marker that costs nothing
// afterwards and does not perturb the module.
//
// This is the only tracing available: the SPU runs through the recompiler, so
// there is no per-instruction hook, and the module is guest code we must not
// modify.
//
//   debug.rpcsx.thor.jobchain_trace = 1
static bool thor_jobchain_trace() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		return __system_property_get("debug.rpcsx.thor.jobchain_trace", v) > 0 && v[0] && v[0] != '0';
	}();
	return s_on;
#else
	return false;
#endif
}

static bool thor_jc_trace_probe(spu_thread& spu)
{
	static std::atomic<u32> s_seq{0};

	cellSpurs.error("Thor JCTRACE %u: reached 0x%05x (spu=%u r3=0x%08x r4=0x%08x r5=0x%08x)",
		s_seq++, +spu.pc, +spu.lv2_id,
		+spu.gpr[3]._u32[3], +spu.gpr[4]._u32[3], +spu.gpr[5]._u32[3]);

	// Drop the hook so the real instruction runs on the next dispatch.
	spu.UnregisterHleFunction(spu.pc);
	return true;
}

static void thor_install_jobchain_trace(spu_thread& spu)
{
	if (!thor_jobchain_trace())
	{
		return;
	}

	// Decision points and subroutine entries along the path a non-system
	// workload takes, from the module disassembly.
	// ONLY FUNCTION ENTRIES WORK. `RunHleFunction` is consulted at block-entry
	// pcs and the SPU runs whole recompiled blocks, so a probe planted in the
	// middle of a block never fires. A first attempt probed mid-block addresses
	// (0x2204, 0x222c, 0x2af0 ...) and produced NOTHING even on a boot where the
	// module demonstrably ran and hit the switch stop twice.
	//
	// These are all `brsl` targets taken from the module's own call graph, which
	// is what makes them block entries. 0x21a8 matters most: the entry path is
	// `0xa4c -> brsl 0x21a8`, and everything the module executes - including the
	// switch request at 0x2af4 - happens inside that call's subtree.
	static constexpr u32 sites[] = {
		0x21a8, 0x28d0,          // the entry subtree, and the trace writer it calls
		0x2850, 0x2868,          // the kernel-service callers
		0x1230, 0x1470, 0x1600,  // other subroutines reachable from the entry
		0x1988, 0x1b00, 0x1c00, 0x1d88, 0x2160, 0x2630, 0x2a98,
		0x0cc8,                  // the remaining brsl target from the call map
	};

	for (const u32 a : sites)
	{
		spu.RegisterHleFunction(a, thor_jc_trace_probe);
	}
}

extern u32 thor_spurs_kernel_code(u32 want_entry, u32& out_size) noexcept;

// FILL THE KERNEL CODE REGION OF LOCAL STORE.
//
// MEASURED, comparing local store from an LLE boot where the job chain module
// works against an HLE boot where it does not, with the SAME module byte-
// identical at 0xA00 in both (8704/8704):
//
//     non-zero bytes   LLE 9543   HLE 8081
//     0x2C0 .. 0x880   LLE ~1472 bytes   HLE ZERO, every 64-byte block
//
// That range is the tail of the SPURS kernel image (PT_LOAD vaddr 0x100,
// size 0x780 -> 0x100..0x880). In LLE the kernel's own CODE is resident there.
// Under HLE the kernel is intercepted by RegisterHleFunction and the image is
// never loaded, so the region is empty.
//
// The module `bisl`s addresses it reads out of the kernel context - 0x808
// (exitToKernelAddr) and 0x290 (selectWorkloadAddr) - and those are hooked, so
// they work. Any OTHER call into kernel code lands on zeros and returns without
// doing anything, which is exactly the observed behaviour: runs, faults
// nowhere, consumes nothing.
//
// Copy only 0x2C0..0x880. The first 0x1C0 bytes of the image overlap
// SpursKernelContext at 0x100, which the HLE kernel maintains itself and must
// not be clobbered.
static void thor_fill_kernel_code(spu_thread& spu, bool isKernel2)
{
	constexpr u32 code_lo = 0x2C0;   // first byte past SpursKernelContext
	constexpr u32 img_lo = 0x100;    // the image loads at LS 0x100

	u32 size = 0;
	const u32 mem = thor_spurs_kernel_code(isKernel2 ? 0x848u : 0x818u, size);

	if (!mem || size <= (code_lo - img_lo))
	{
		return;
	}

	const u32 off = code_lo - img_lo;
	const u32 len = size - off;

	std::memcpy(spu._ptr<void>(code_lo), vm::base(mem + off), len);

	static std::atomic<u32> s_n{0};

	if (const u32 n = s_n++; n < 8)
	{
		cellSpurs.error("Thor KERNEL CODE: filled LS 0x%x..0x%x from the real kernel%d (%u bytes)",
			code_lo, code_lo + len, isKernel2 ? 2 : 1, len);
	}
}

static bool thor_entry_pollstatus_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.entry_pollstatus_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_yield_redispatch_fix() noexcept
{
	const u32 every = thor_yield_redispatch_every();

	if (!every)
	{
		return false;
	}

	if (every == 1)
	{
		return true;
	}

	// Per-SPU counter: two SPUs in the same taskset must not share a phase and
	// accidentally both skip, or both pay, on the same yields.
	static thread_local u32 s_count = 0;
	return (s_count++ % every) == 0;
}

// DO NOT CLOBBER A SIGNAL THE PPU SET WHILE WE WERE THINKING.
//
// spursTasksetProcessRequest reads the six taskset bitmaps, computes, and
// writes them back - and the `vm::reservation_op` wrapper that should make
// that atomic is COMMENTED OUT (in upstream too). Meanwhile the PPU updates
// `signalled` inside a real reservation_op in _cellSpursSendSignal. So:
//
//     SPU reads signalled = 0
//     PPU atomically sets signalled |= mask      <- a push
//     SPU writes back a value derived from 0     <- the signal is ERASED
//
// The consumer then waits for a signal that was already delivered and thrown
// away, and `head` freezes wherever it happened to be. MEASURED freeze points
// across otherwise identical runs: 42, 89, 257, 511. A fixed arithmetic bug
// does not move; a race does.
//
// `signalled` is the ONLY field with two writers - _cellSpursSendSignal reads
// the others but assigns only `op.signalled[...]` - so the fix is narrow.
// Instead of storing the whole word, CONSUME exactly the bits this pass
// decided to consume (`signalled & ~signalled0`) inside a reservation on the
// same 128-byte line the PPU reserves, leaving any concurrently-set bit alone.
//
// The clear is done on the raw 16 bytes as a v128 rather than per big-endian
// word, because a bitwise AND-NOT of two views of the same memory layout is
// endian-agnostic and a per-word version would need a byte swap to be correct.
//
//   debug.rpcsx.thor.signal_atomic_fix = 0  restore the clobbering store
static bool thor_signal_atomic_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.signal_atomic_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_taskset_syscall_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.taskset_syscall_fix", v) <= 0 || !v[0])
		{
			return true;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

static bool thor_spurs_signal_fix() noexcept
{
#ifdef ANDROID
	static const bool s_on = []() noexcept
	{
		char v[PROP_VALUE_MAX]{};
		if (__system_property_get("debug.rpcsx.thor.spurs_signal_fix", v) <= 0 || !v[0])
		{
			// DEFAULT OFF. The guard is correct about the undefined shift and
			// WRONG about the consequence - measured below.
			return false;
		}
		return v[0] != '0';
	}();
	return s_on;
#else
	return true;
#endif
}

// Clear only the selected signal bit with an atomic update.
//
// The PPU sets workload signals with atomic_op. A direct `raw() &= mask` in a
// selector can read an old word, race with that PPU update, and then store the
// old word. That operation can erase a signal for a different workload.
//
// Keep the measured default behavior for the system service. The old AArch64
// shift cleared workload 0 when the selected ID was 32. The signal-fix arm
// changes that operation to a no-op, but both arms still issue atomic writes so
// that guest reservation waiters receive the same notification.
static void spursAtomicClearSelectedSignal(CellSpurs* spurs, u32 selectedId, bool guardSystemService) noexcept
{
	u16 signal1Mask = 0;
	u16 signal2Mask = 0;

	if (selectedId < CELL_SPURS_MAX_WORKLOAD)
	{
		signal1Mask = 0x8000u >> selectedId;
	}
	else if (selectedId < CELL_SPURS_MAX_WORKLOAD2)
	{
		signal2Mask = 0x8000u >> (selectedId - CELL_SPURS_MAX_WORKLOAD);
	}
	else if (!guardSystemService)
	{
		// Preserve the measured AArch64 result of the old `0x8000 >> 32`.
		signal1Mask = 0x8000u;
	}

	spurs->wklSignal1.atomic_op([&](be_t<u16>& signal)
	{
		signal &= ~signal1Mask;
	});
	spurs->wklSignal2.atomic_op([&](be_t<u16>& signal)
	{
		signal &= ~signal2Mask;
	});
}

// Return true when the selected workload enters a host HLE callback at 0xA00.
// A real policy module starts in the SPU runtime and has no host callback
// boundary. The selector consumes its signal. The dispatch path must not clear
// a newer signal that arrives after selection.
static bool spursWorkloadUsesHleEntry(CellSpurs* spurs, u32 selectedId, bool isKernel2) noexcept
{
	u32 policyAddress = 0;

	if (selectedId < CELL_SPURS_MAX_WORKLOAD)
	{
		policyAddress = spurs->wklInfo1[selectedId].addr.addr();
	}
	else if (isKernel2 && selectedId < CELL_SPURS_MAX_WORKLOAD2)
	{
		policyAddress = spurs->wklInfo2[selectedId - CELL_SPURS_MAX_WORKLOAD].addr.addr();
	}
	else
	{
		return false;
	}

	return policyAddress == SPURS_IMG_ADDR_TASKSET_PM ||
		policyAddress == SPURS_IMG_ADDR_JOBCHAIN_PM;
}
// The first CellSpurs cache line contains every dynamic kernel-1 scheduling
// input. Real SPURS updates this line through a 128-byte reservation. Keep the
// HLE claim on the same reservation granule as PPU workload signals.
struct alignas(128) spurs_kernel1_claim_op
{
	u8 readyCount[0x10];       // 0x00
	u8 idleSpuCount[0x10];     // 0x10
	u8 currentContention[0x10]; // 0x20
	u8 pendingContention[0x10]; // 0x30
	u8 minContention[0x10];     // 0x40
	u8 maxContention[0x10];     // 0x50
	u8 workloadFlagPrefix[0x0c]; // 0x60
	be_t<u32> workloadFlag;      // 0x6c
	be_t<u16> signal1;           // 0x70
	u8 sysSrvMessage;            // 0x72
	u8 spuIdling;                // 0x73
	u8 flags1;                   // 0x74
	u8 sysSrvTraceControl;       // 0x75
	u8 nSpus;                    // 0x76
	u8 workloadFlagReceiver;     // 0x77
	be_t<u16> signal2;           // 0x78
	u8 tail[6];                  // 0x7a
};

CHECK_SIZE_ALIGN(spurs_kernel1_claim_op, 128, 128);

// Revalidate demand, claim one contention slot, and consume the demand token
// in one reservation transaction. A signal-only wake can therefore dispatch
// one SPU, not every SPU that read the bit before a separate clear.
static bool spursAtomicTryClaimWorkload(spu_thread& spu, SpursKernelContext* ctxt, u32 selectedId) noexcept
{
	if (selectedId >= CELL_SPURS_MAX_WORKLOAD)
	{
		return false;
	}

	return vm::reservation_op<true>(spu,
		vm::unsafe_ptr_cast<spurs_kernel1_claim_op>(ctxt->spurs),
		[&](spurs_kernel1_claim_op& op)
		{
			const u8 current = op.currentContention[selectedId];
			const u8 maximum = op.maxContention[selectedId];
			const u8 ready = std::min<u8>(op.readyCount[selectedId], CELL_SPURS_MAX_SPU);
			const u8 idle = std::min<u8>(op.idleSpuCount[selectedId], CELL_SPURS_MAX_SPU);
			const u16 signalMask = 0x8000u >> selectedId;
			const bool hasSignal = (op.signal1 & signalMask) != 0;
			const bool hasFlag = op.workloadFlag == 0 && op.workloadFlagReceiver == selectedId;
			const bool hasReadyDemand = ready != 0 && ready + idle > current;

			if (current >= maximum || (!hasSignal && !hasFlag && !hasReadyDemand))
			{
				return false;
			}

			op.currentContention[selectedId] = current + 1;

			if (hasSignal)
			{
				op.signal1 &= ~signalMask;
			}

			if (hasFlag)
			{
				op.workloadFlag = -1;
			}

			return true;
		});
}

static bool thor_hle_once(std::atomic<u32>& bits, u32 spuNum) noexcept
{
	const u32 bit = 1u << (spuNum & 31);
	return (bits.fetch_or(bit) & bit) == 0;
}

bool spursKernel1SelectWorkload(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursKernelContext>(0x100);

	// WHEN does this first run? Four repairs to the clear below have hung the boot
	// at ~4 s of emulated time, but 'armed' is logged at SPU THREAD CREATION and
	// the group is not created until ~17 s - so either this selector runs far
	// earlier than assumed, or the hang has nothing to do with it. One shot per
	// SPU, at entry, before any of the changed code.
	{
		static std::atomic<u32> s_entry_logged{0};

		if (thor_hle_once(s_entry_logged, spu.index))
		{
			cellSpurs.error("Thor SELECTOR first entry: spu=%u pc=0x%05x", spu.index, spu.pc);
		}
	}

	// The first and only argument to this function is a boolean that is set to false if the function
	// is called by the SPURS kernel and set to true if called by cellSpursModulePollStatus.
	// If the first argument is true then the shared data is not updated with the result.
	const auto isPoll = spu.gpr[3]._u32[3];

	u32 wklSelectedId;
	u32 pollStatus;
	bool contentionClaimed = false;

	// vm::reservation_op(vm::cast(ctxt->spurs.addr()), 128, [&]()
	{
		// lock the first 0x80 bytes of spurs
		auto spurs = ctxt->spurs.get_ptr();

		// Calculate the contention (number of SPUs used) for each workload
		u8 contention[CELL_SPURS_MAX_WORKLOAD];
		u8 pendingContention[CELL_SPURS_MAX_WORKLOAD];
		for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
		{
			// CLAMP: this is u8 arithmetic and it UNDERFLOWS.
			//
			// Measured at the 50-frame stall:
			//
			//   select#1 wkl0: runnable=1 prio=1 maxCont=8 cont=254 signal=0
			//
			// 254 is 0 - 2 wrapped in a u8, not a leak upward: the shared
			// wklCurrentContention read 0 while this SPU's local contribution was
			// 2. Six SPUs committing a selection concurrently makes that race
			// reachable, and once it happens `maxContention > contention` is false
			// forever (8 > 254 never holds), so the workload can never be selected
			// again and rendering stops dead.
			//
			// Saturate at 0 instead of wrapping. A contention of 0 is the correct
			// reading when the shared counter says nobody is running this workload.
			{
				const u8 cur = spurs->wklCurrentContention[i];
				const u8 loc = ctxt->wklLocContention[i];

				contention[i] = cur >= loc ? cur - loc : 0;
			}

			// If this is a poll request then the number of SPUs pending to context switch is also added to the contention presumably
			// to prevent unnecessary jumps to the kernel
			if (isPoll)
			{
				{
					// Same u8 underflow hazard as wklCurrentContention above.
					const u8 pcur = spurs->wklPendingContention[i];
					const u8 ploc = ctxt->wklLocPendingContention[i];

					pendingContention[i] = pcur >= ploc ? pcur - ploc : 0;
				}
				if (i != ctxt->wklCurrentId)
				{
					contention[i] += pendingContention[i];
				}
			}
		}

		wklSelectedId = CELL_SPURS_SYS_SERVICE_WORKLOAD_ID;
		pollStatus = 0;

		// The system service has the highest priority. Select the system service if
		// the system service message bit for this SPU is set.
		if (spurs->sysSrvMessage & (1 << ctxt->spuNum))
		{
			ctxt->spuIdling = 0;
			if (!isPoll || ctxt->wklCurrentId == CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				// Clear the message bit
				spurs->sysSrvMessage.raw() &= ~(1 << ctxt->spuNum);
			}
		}
		else
		{
			// THOR: the four terms of the selection gate, once per SPU.
			//
			// state1 already reads [02 02 ...] and spurs matches the PPU's
			// address, so RUNNABLE is NOT the problem. The gate is
			//   runnable && priority[i] != 0 && wklMaxContention[i] > contention[i]
			//   && (wklFlag || wklSignal || (readyCount && requestCount > contention[i]))
			// and the title does call cellSpursSendWorkloadSignal, so print every
			// term for the two workloads that exist and let it name the failure.
			// FIRE BECAUSE A SIGNAL IS PENDING, not on a call count.
			//
			// Fixed-count probes keep landing before the PPU writes the signal:
			// the 200th call read 12.169976 while cellSpursSendWorkloadSignal ran
			// at 12.175456. Trigger on the condition itself so the log shows what
			// the selector sees WHILE a real workload is signalled - which is the
			// only moment that can explain the deadlock.
			// PERIODIC, NOT ONE-SHOT. The first dispatch works; what fails is
			// RE-selection after the task waits. A one-shot probe cannot show that,
			// so sample the gate terms every 4096 selector calls.
			static std::atomic<u32> s_sel_calls2{0};

			if (thor_hle_spurs_diagnostics())
			{
				const u32 sn = s_sel_calls2++;

				if ((sn & 0xFFF) == 0)
				{
					// COVER wid 2. The queue's taskset is workload 2 - the PPU logs
					// `signal wid=2: inside=0x2000 readback=0x2000` - so printing only
					// wkl0 and wkl1 was reading workloads that have nothing to do with
					// the stall.
					for (u32 k = 0; k < 4; k++)
					{
						cellSpurs.error("Thor HLE SPU%u select#1 wkl%u: runnable=%u prio=%u maxCont=%u cont=%u ready=%u idle=%u signal=%u flag=%u flagRecv=%u | K2=%u rawCont=0x%02x rawMax=0x%02x curId=%u locC=%u isPoll=%u holders=0x%02x",
							+ctxt->spuNum, k,
							(ctxt->wklRunnable1 & (0x8000 >> k)) ? 1u : 0u,
							+ctxt->priority[k],
							+spurs->wklMaxContention[k],
							+contention[k],
							+spurs->wklReadyCount1[k],
							+spurs->wklIdleSpuCountOrReadyCount2[k],
							(spurs->wklSignal1.load() & (0x8000u >> k)) ? 1u : 0u,
							+spurs->wklFlag.flag.load(),
							// IS THIS TITLE 32-WORKLOAD? kernel2 packs wklCurrentContention as two
							// 4-bit counters per byte (low = wkl i, high = wkl i+16); kernel1 reads
							// the byte as a plain count. If K2=1 while THIS probe (kernel1) is the
							// one running, a packed 0xFC reads as 252 and no workload can ever be
							// selected. Print the raw bytes beside the decoded value so the two
							// readings can be told apart.

							+spurs->wklFlagReceiver,
							(spurs->flags1 & SF1_32_WORKLOADS) ? 1u : 0u,
							+spurs->wklCurrentContention[k],
							+spurs->wklMaxContention[k],
							// LEAKED OR LEGITIMATELY HELD? cont=1 with maxCont=1 looks identical
							// either way. curId says which workload THIS SPU thinks it is on, and
							// locC says whether it believes it holds contention for wkl k. If no
							// SPU reports curId=2 while wkl2 shows cont=1, the count is leaked.
							+ctxt->wklCurrentId,
							+ctxt->wklLocContention[k],
							isPoll ? 1u : 0u,
							g_thor_wkl_holders[k & 0x0F].load());
					}
				}
			}

			// Caclulate the scheduling weight for each workload
			u16 maxWeight = 0;
			for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
			{
				u16 runnable = ctxt->wklRunnable1 & (0x8000 >> i);
				u16 wklSignal = spurs->wklSignal1.load() & (0x8000 >> i);
				u8 wklFlag = spurs->wklFlag.flag.load() == 0u ? spurs->wklFlagReceiver == i ? 1 : 0 : 0;
				u8 readyCount = spurs->wklReadyCount1[i] > CELL_SPURS_MAX_SPU ? CELL_SPURS_MAX_SPU : spurs->wklReadyCount1[i].load();
				u8 idleSpuCount = spurs->wklIdleSpuCountOrReadyCount2[i] > CELL_SPURS_MAX_SPU ? CELL_SPURS_MAX_SPU : spurs->wklIdleSpuCountOrReadyCount2[i].load();
				u8 requestCount = readyCount + idleSpuCount;

				// For a workload to be considered for scheduling:
				// 1. Its priority must not be 0
				// 2. The number of SPUs used by it must be less than the max contention for that workload
				// 3. The workload should be in runnable state
				// 4. The number of SPUs allocated to it must be less than the number of SPUs requested (i.e. readyCount)
				//    OR the workload must be signalled
				//    OR the workload flag is 0 and the workload is configured as the wokload flag receiver
				if (runnable && ctxt->priority[i] != 0 && spurs->wklMaxContention[i] > contention[i])
				{
					if (wklFlag || wklSignal || (readyCount != 0 && requestCount > contention[i]))
					{
						// The scheduling weight of the workload is formed from the following parameters in decreasing order of priority:
						// 1. Wokload signal set or workload flag or ready count > contention
						// 2. Priority of the workload on the SPU
						// 3. Is the workload the last selected workload
						// 4. Minimum contention of the workload
						// 5. Number of SPUs that are being used by the workload (lesser the number, more the weight)
						// 6. Is the workload executable same as the currently loaded executable
						// 7. The workload id (lesser the number, more the weight)
						u16 weight = (wklFlag || wklSignal || (readyCount > contention[i])) ? 0x8000 : 0;
						weight |= (ctxt->priority[i] & 0x7F) << 8; // TODO: was shifted << 16
						weight |= i == ctxt->wklCurrentId ? 0x80 : 0x00;
						weight |= (contention[i] > 0 && spurs->wklMinContention[i] > contention[i]) ? 0x40 : 0x00;
						weight |= ((CELL_SPURS_MAX_SPU - contention[i]) & 0x0F) << 2;
						weight |= ctxt->wklUniqueId[i] == ctxt->wklCurrentId ? 0x02 : 0x00;
						weight |= 0x01;

						// In case of a tie the lower numbered workload is chosen
						if (weight > maxWeight)
						{
							wklSelectedId = i;
							maxWeight = weight;
							pollStatus = readyCount > contention[i] ? CELL_SPURS_MODULE_POLL_STATUS_READYCOUNT : 0;
							pollStatus |= wklSignal ? CELL_SPURS_MODULE_POLL_STATUS_SIGNAL : 0;
							pollStatus |= wklFlag ? CELL_SPURS_MODULE_POLL_STATUS_FLAG : 0;
						}
					}
				}
			}

			// Enforce max contention in the same atomic operation that claims the
			// slot. A failed claimant stays in the system service and leaves the
			// workload signal available for a later selector pass.
			if (!isPoll && thor_contention_atomic_fix() &&
				wklSelectedId < CELL_SPURS_MAX_WORKLOAD &&
				!ctxt->wklLocContention[wklSelectedId])
			{
				contentionClaimed = spursAtomicTryClaimWorkload(spu, ctxt, wklSelectedId);

				if (!contentionClaimed)
				{
					wklSelectedId = CELL_SPURS_SYS_SERVICE_WORKLOAD_ID;
					pollStatus = 0;
				}
			}

			// Not sure what this does. Possibly mark the SPU as idle/in use.
			ctxt->spuIdling = wklSelectedId == CELL_SPURS_SYS_SERVICE_WORKLOAD_ID ? 1 : 0;

			// GHIDRA: THE SECOND TERM IS THE WRONG COMPARISON.
			//
			// The real kernel's selector at LS 0x290 computes this branch as:
			//
			//     00000290: ceqi r30,r3,0x0      ; r30 = (arg0 == 0)
			//     00000294: lqr  r10,-0x31       ; PC-rel: 0x294 - 0xc4 = LS 0x1d0
			//     000002c4: rotqbyi r20,r10,0xc  ; bytes 12..15 of 0x1d0 = 0x1dc
			//     000002d8: ceqi r7,r20,0x20     ; r7  = (wklCurrentId == 32)
			//     000002a0: sfi  r29,r30,0x0     ; r29 = -(arg0 == 0)
			//     000002e0: sfi  r5,r7,0x0       ; r5  = -(wklCurrentId == 32)
			//     000002e8: or   r3,r29,r5       ; r3  = !isPoll || currentId == 32
			//
			// LS 0x1dc is SpursKernelContext::wklCurrentId, so hardware asks
			// "am I currently running the SYSTEM SERVICE", NOT "did the
			// selection change". The port asks the latter, and that is the
			// livelock: parked in the system service, currentId is 32, a real
			// workload 0 is selected, `0 != 32` sends it down the
			// context-switch-required path at the `else if` below, which
			// exits to the kernel and re-selects forever. Hardware instead
			// COMMITS here - sets wklCurrentId and dispatches.
			//
			// Only meaningful with spurs_signal_fix=1; alone, the signal is
			// still eaten by `0x8000 >> 32` before a workload can be selected.
			//
			//   debug.rpcsx.thor.spurs_sel_cond_fix = 1
			const bool commitSelection = thor_spurs_sel_cond_fix()
				? (!isPoll || ctxt->wklCurrentId == CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
				: (!isPoll || wklSelectedId == ctxt->wklCurrentId);

			// A POLL MUST NOT CONSUME A SIGNAL.
			//
			// With the selector condition fixed, an SPU parked in the system
			// service now selects a real workload - measured, the first time this
			// branch ever did:
			//
			//   Thor SPU5 SELECTED REAL WORKLOAD wid=0 (isPoll=1)
			//   select#1 wkl0: runnable=1 prio=1 maxCont=8 cont=0 signal=1
			//
			// But that came from cellSpursModulePollStatus, which only asks
			// "should I yield?". Clearing the signal there consumes it without
			// dispatching, so when the KERNEL selects for real (isPoll=0) the
			// signal is gone, it picks 32, and the system service is dispatched
			// again - the same deadlock, one step later.
			//
			// The original commit condition (`!isPoll || selected == current`)
			// could not hit this: during a poll it only fired when nothing
			// changed. Widening the commit means narrowing the clear to match.
			const bool consumeSignal = !thor_spurs_sel_cond_fix() || !isPoll;

			// The first edge-Zlib signal completes one loader batch. The next
			// signal is consumed but no further queue atomic appears. Record each
			// selector that sees or chooses workload 0 so the next capture can
			// distinguish a lost workload signal from a failed task selection.
			if (thor_edge_task_census() &&
				(wklSelectedId == 0 || (spurs->wklSignal1.load() & 0x8000u)))
			{
				static std::atomic<u32> s_edge_wkl_selects{0};
				const u32 n = s_edge_wkl_selects++;

				if (n < 32)
				{
					cellSpurs.error("Thor EDGE WKL SELECT #%u: selected=%u current=%u isPoll=%u pollStatus=0x%x "
						"commit=%u consume=%u signal1=%04x gate{runnable=%u prio=%u max=%u cont=%u ready=%u idle=%u} "
						"contention{shared=%u pending=%u local=%u localPending=%u} spu=%u",
						n, wklSelectedId, +ctxt->wklCurrentId, +isPoll, pollStatus,
						commitSelection ? 1u : 0u, consumeSignal ? 1u : 0u, +spurs->wklSignal1.load(),
						(ctxt->wklRunnable1 & 0x8000u) ? 1u : 0u, +ctxt->priority[0],
						+spurs->wklMaxContention[0], +contention[0], +spurs->wklReadyCount1[0],
						+spurs->wklIdleSpuCountOrReadyCount2[0], +spurs->wklCurrentContention[0],
						+spurs->wklPendingContention[0], +ctxt->wklLocContention[0],
						+ctxt->wklLocPendingContention[0], +ctxt->spuNum);
				}
			}

			if (commitSelection)
			{
				// Clear workload signal for the selected workload.
				//
				// **THE SHIFT IS UNDEFINED FOR THE SYSTEM SERVICE, AND ON AArch64
				// IT SILENTLY ERASES WORKLOAD 0's SIGNAL.**
				//
				// wklSelectedId is CELL_SPURS_SYS_SERVICE_WORKLOAD_ID (32) whenever
				// no real workload is selectable, and the guard above is
				// `!isPoll || wklSelectedId == ctxt->wklCurrentId`, TRUE on every
				// poll once an SPU sits in the system service. AArch64 takes a
				// 32-bit shift count MODULO 32, so `0x8000 >> 32` evaluates to
				// `0x8000 >> 0` = 0x8000 and the line becomes
				// `wklSignal1 &= ~0x8000` - clearing workload 0.
				//
				// Measured: cellSpursSendWorkloadSignal(wid=0) reached its write
				// path with state=2, and reading wklSignal1 back ONE LINE LATER
				// gave 0x0. Six SPUs spinning here erase the bit faster than the
				// PPU returns. A vm::light_op write and a direct atomic_op both
				// looked "lost" for this reason; the writes were never the problem.
				//
				// The system service has no signal bit, so it must not clear one.
				// CONTROL EXPERIMENT, 2026-08-25. Both arms run IDENTICAL code.
				//
				// fix=1 hung the game at ~1 s of emulated time, before SPURS even
				// armed - which a change to signal semantics inside the selector
				// should not be able to do. The other suspect is the gate itself:
				// thor_spurs_signal_fix() is a function-local static whose
				// initializer calls __system_property_get, and six SPU threads
				// reach it concurrently on a hot path. If THAT is the hang, then
				// calling it at all is the bug and the signal analysis is
				// untouched.
				//
				// So: read the flag, ignore it, and always run the original. If
				// fix=1 still hangs, the mechanism is guilty and the property must
				// be read once at load time instead of lazily on an SPU thread.
				// KEEP THE WRITE, FIX THE MASK.
				//
				// Three things are now measured, and together they pin the repair:
				//
				//  1. `0x8000 >> wklSelectedId` with wklSelectedId == 32 is UB, and
				//     AArch64 evaluates it as `>> 0`, so this clears workload 0's
				//     signal - the one gate term that can start a taskset.
				//  2. Deleting the statement HANGS the game at ~1 s, before SPURS
				//     arms (armed=0 twice, against armed=6 twice).
				//  3. That hang is NOT my property gate: a control where both arms
				//     ran byte-identical code booted fine (armed=6).
				//
				// So the statement is load-bearing for a reason that has nothing to
				// do with which bit it clears: it is a WRITE to guest memory, and in
				// SPURS a write to this line is also a reservation notification. Drop
				// the store and a waiter never wakes.
				//
				// Therefore keep writing, but with a mask that changes nothing when
				// the system service is selected. Same store, same notification, no
				// corrupted signal.
				if (!consumeSignal)
				{
					// Poll: report the selection, consume nothing.
				}
				else if (contentionClaimed)
				{
					// The reservation claim already consumed the selected signal.
					// Do not clear a newer signal that arrived after the claim.
				}
				else
				{
					spursAtomicClearSelectedSignal(spurs, wklSelectedId, thor_spurs_signal_fix());
				}

				// If the selected workload is the wklFlag workload then pull the wklFlag to all 1s
				if (!contentionClaimed && wklSelectedId == spurs->wklFlagReceiver)
				{
					spurs->wklFlag.flag = -1;
				}
			}
		}

		if (!isPoll)
		{
			// Called by kernel
			// Increment the contention for the selected workload
			if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				contention[wklSelectedId]++;
			}

			for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
			{
				// CLAMP THE WRITE-BACK TOO.
				//
				// Clamping only the subtraction did not help: the probe still read
				// cont=253 over half a million times, so 253 is the value actually
				// STORED in the shared counter - genuine upward growth, not an
				// underflow in this SPU's read.
				//
				// Contention counts SPUs currently running a workload, so it can
				// never exceed the number of SPUs in the instance. Saturating there
				// keeps `maxContention > contention` meaningful no matter how the
				// bookkeeping drifts, and 253 permanently closing the gate is what
				// stops rendering at ~50 frames.
				{
					const u8 cap = static_cast<u8>(std::min<u32>(+spurs->nSpus ? +spurs->nSpus : 6u, 8u));

					if (contention[i] > cap)
					{
						static std::atomic<u32> s_clamped{0};

						if (const u32 cn = s_clamped++; (cn & 0xFFF) == 0)
						{
							cellSpurs.error("Thor CONTENTION CLAMP #%u: wkl%u had %u, cap %u, selected=%u locC=%u",
								cn, i, +contention[i], +cap, wklSelectedId, +ctxt->wklLocContention[i]);
						}

						contention[i] = cap;
					}
				}

				if (!thor_contention_atomic_fix())
				{
					spurs->wklCurrentContention[i] = contention[i];
				}

				// SATURATE. This was a raw u8 subtraction and it UNDERFLOWS.
				//
				// Measured at the hang, with the shared current-contention CLEAN:
				//
				//   select#1 wkl0: maxCont=8 cont=253 ... K2=0 rawCont=0x00
				//
				// rawCont is the shared wklCurrentContention and it is 0, so the 253
				// came from pendingContention, which the poll path adds in. 253 is 0-3
				// wrapped in a u8.
				//
				// wklCurrentContention already had a clamp (see CONTENTION CLAMP above);
				// wklPendingContention never did. The read side saturates too, but that
				// only stops a SECOND underflow - once the SHARED byte is 253 it is
				// passed straight through, `maxContention > contention` is false forever
				// (8 > 253 never holds), and the workload can never be selected again.
				//
				// That is the hang: every workload unselectable, six SPUs spinning in the
				// selector, no task ever dispatched, and draw_calls = 0.
				// Atomic per entry: this SPU subtracts only what IT owes. The plain
				// read-modify-write below is shared by six SPUs and loses updates,
				// which leaves the same permanent +1 the poll branch used to leak.
				if (thor_pending_contention_fix())
				{
					if (const u8 ploc = ctxt->wklLocPendingContention[i])
					{
						vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklPendingContention) + i)
							.atomic_op([ploc](u8& v) { v = v >= ploc ? v - ploc : 0; });
					}
				}
				else
				{
					const u8 pcur = spurs->wklPendingContention[i];
					const u8 ploc = ctxt->wklLocPendingContention[i];

					spurs->wklPendingContention[i] = pcur >= ploc ? pcur - ploc : 0;
				}
				ctxt->wklLocPendingContention[i] = 0;

				if (!thor_contention_atomic_fix())
				{
					ctxt->wklLocContention[i] = 0;
				}
			}

			// ATOMIC PER-ENTRY TRANSFER INSTEAD OF A BULK WRITE-BACK.
			//
			// `wklCurrentContention` is a plain `u8[16]` shared by all six SPUs,
			// and the loop above has every SPU recompute the WHOLE array from its
			// own stale read and write all sixteen bytes back. That loses updates
			// by construction, and the counter was measured running away to 253.
			// With `maxContention = 1` on the queue's workload, one bad update
			// closes its gate permanently - which is why the workload is dispatched
			// 45 times in one run and 0 times in the next off the same build.
			//
			// Transfer only what THIS SPU changed, atomically: release the slot it
			// held, take the slot it selected. Nothing else is touched, so no SPU
			// can clobber another's accounting.
			if (thor_contention_atomic_fix())
			{
				// RELEASE EVERY SLOT THIS SPU HOLDS, NOT JUST wklCurrentId.
				//
				// Releasing only `prev = wklCurrentId` orphans a slot whenever
				// wklCurrentId changes by any OTHER route - a taskset exit, a kernel
				// re-entry - because `wklLocContention[X]` is then still set for a
				// workload that `prev` no longer names, and nothing ever subtracts
				// its +1. Measured at a hang, with the pending leak already fixed:
				//
				//   wkl2: maxCont=1 cont=1 rawCont=0x01 curId=32 locC=0  (all six SPUs)
				//
				// The shared CURRENT contention is 1 and no SPU holds it, so the
				// maxContention=1 gate is shut for good - the same deadlock as the
				// pending leak, one counter over.
				//
				// This form is idempotent: the SPU's held set always equals its own
				// local records, so no route out of a workload can orphan a slot.
				//
				//   debug.rpcsx.thor.contention_orphan_fix = 0 restores prev-only
				if (thor_contention_orphan_fix())
				{
					for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
					{
						if (i != wklSelectedId && ctxt->wklLocContention[i])
						{
							vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklCurrentContention) + i)
								.atomic_op([](u8& v) { if (v) v--; });
							ctxt->wklLocContention[i] = 0;
							thor_release_wkl(i, ctxt->spuNum);
						}
					}

					if (wklSelectedId < CELL_SPURS_MAX_WORKLOAD && !ctxt->wklLocContention[wklSelectedId])
					{
						if (!contentionClaimed)
						{
							vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklCurrentContention) + wklSelectedId)
								.atomic_op([](u8& v) { if (v < 8) v++; });
						}
						ctxt->wklLocContention[wklSelectedId] = 1;
						thor_hold_wkl(wklSelectedId, ctxt->spuNum);
					}
				}
				else
				{
				const u32 prev = ctxt->wklCurrentId;

				if (prev != wklSelectedId)
				{
					if (prev < CELL_SPURS_MAX_WORKLOAD && ctxt->wklLocContention[prev])
					{
						vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklCurrentContention) + prev)
							.atomic_op([](u8& v) { if (v) v--; });
						ctxt->wklLocContention[prev] = 0;
					}

					if (wklSelectedId < CELL_SPURS_MAX_WORKLOAD)
					{
						vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklCurrentContention) + wklSelectedId)
							.atomic_op([](u8& v) { if (v < 8) v++; });
						ctxt->wklLocContention[wklSelectedId] = 1;
					}
				}
				}
			}
			else if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				ctxt->wklLocContention[wklSelectedId] = 1;
			}

			ctxt->wklCurrentId = wklSelectedId;
		}
		else if (wklSelectedId != ctxt->wklCurrentId)
		{
			// PENDING CONTENTION LEAKED HERE, AND THAT IS THE HANG.
			//
			// The bulk write-back below stores this SPU's stale snapshot over the
			// WHOLE shared array and then clears ALL of this SPU's local records:
			//
			//     spurs->wklPendingContention[i] = pendingContention[i];
			//     ctxt->wklLocPendingContention[i] = 0;
			//
			// `wklLocPendingContention[X]` is the ONLY record that this SPU owes a
			// decrement on workload X. If this SPU polled X earlier and now polls a
			// different workload Y, X's +1 is written straight back into the shared
			// counter while its local record is zeroed - so no SPU will ever subtract
			// it. That is a permanent +1 per leaked workload.
			//
			// Measured at the hang, six SPUs spinning and zero frames:
			//
			//   select#1 wkl2: maxCont=1 cont=1 ready=1 signal=1 rawCont=0x00 locC=0 curId=32
			//
			// rawCont (shared CURRENT contention) is 0 and locC is 0, so the 1 is
			// pure leaked PENDING contention. With maxContention = 1 the selector
			// gate `maxContention > contention` is `1 > 1` - false forever - so the
			// workload can never be selected again, every SPU falls back to the
			// system service workload (curId=32), and no task is ever dispatched.
			//
			// Release every pending slot this SPU actually holds, atomically and
			// per entry, then take the one it just selected. Nothing another SPU
			// owns is touched, so no update is lost.
			//
			//   debug.rpcsx.thor.pending_contention_fix = 0 restores the old path
			if (thor_pending_contention_fix())
			{
				for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
				{
					if (ctxt->wklLocPendingContention[i])
					{
						vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklPendingContention) + i)
							.atomic_op([](u8& v) { if (v) v--; });
						ctxt->wklLocPendingContention[i] = 0;
					}
				}

				if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID && wklSelectedId < CELL_SPURS_MAX_WORKLOAD)
				{
					vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklPendingContention) + wklSelectedId)
						.atomic_op([](u8& v) { if (v < 8) v++; });
					ctxt->wklLocPendingContention[wklSelectedId] = 1;
				}
			}
			else
			{
			// Not called by kernel but a context switch is required
			// Increment the pending contention for the selected workload
			if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				pendingContention[wklSelectedId]++;
			}

			for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
			{
				spurs->wklPendingContention[i] = pendingContention[i];
				ctxt->wklLocPendingContention[i] = 0;
			}

			if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				ctxt->wklLocPendingContention[wklSelectedId] = 1;
			}
			}
		}
		else
		{
			// Not called by kernel and no context switch is required
			for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
			{
				// SATURATE. This was a raw u8 subtraction and it UNDERFLOWS.
				//
				// Measured at the hang, with the shared current-contention CLEAN:
				//
				//   select#1 wkl0: maxCont=8 cont=253 ... K2=0 rawCont=0x00
				//
				// rawCont is the shared wklCurrentContention and it is 0, so the 253
				// came from pendingContention, which the poll path adds in. 253 is 0-3
				// wrapped in a u8.
				//
				// wklCurrentContention already had a clamp (see CONTENTION CLAMP above);
				// wklPendingContention never did. The read side saturates too, but that
				// only stops a SECOND underflow - once the SHARED byte is 253 it is
				// passed straight through, `maxContention > contention` is false forever
				// (8 > 253 never holds), and the workload can never be selected again.
				//
				// That is the hang: every workload unselectable, six SPUs spinning in the
				// selector, no task ever dispatched, and draw_calls = 0.
				// Atomic per entry: this SPU subtracts only what IT owes. The plain
				// read-modify-write below is shared by six SPUs and loses updates,
				// which leaves the same permanent +1 the poll branch used to leak.
				if (thor_pending_contention_fix())
				{
					if (const u8 ploc = ctxt->wklLocPendingContention[i])
					{
						vm::_ref<atomic_t<u8>>(ctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklPendingContention) + i)
							.atomic_op([ploc](u8& v) { v = v >= ploc ? v - ploc : 0; });
					}
				}
				else
				{
					const u8 pcur = spurs->wklPendingContention[i];
					const u8 ploc = ctxt->wklLocPendingContention[i];

					spurs->wklPendingContention[i] = pcur >= ploc ? pcur - ploc : 0;
				}
				ctxt->wklLocPendingContention[i] = 0;
			}
		}

		std::memcpy(ctxt, spurs, 128);
	} //);

	// If a real workload was ever selected, say so once per SPU. This is the
	// event the whole HLE effort is waiting for.
	// WHICH WORKLOADS ACTUALLY RUN, AND HOW OFTEN.
	//
	// The title queues ~2 MB of GCM command buffer that nothing drains. The
	// producer works; the consumer does not. The consumer is one of these
	// workloads, so count SELECTIONS per workload id - event-based, because
	// state sampling here is driven by DMA traffic that stops at the failure.
	// A workload with zero selections is never running at all.
	if (thor_hle_spurs_diagnostics())
	{
		static std::array<std::atomic<u32>, 32> s_sel_hist{};
		static std::atomic<u32> s_sel_total{0};

		if (wklSelectedId < 32)
		{
			s_sel_hist[wklSelectedId]++;
		}

		if ((s_sel_total++ % 20000) == 0)
		{
			char hist[256]{};
			int off = 0;

			for (u32 i = 0; i < 16; i++)
			{
				if (const u32 c = s_sel_hist[i].load())
				{
					off += std::snprintf(hist + off, sizeof(hist) - off, " w%u=%u", i, c);
				}
			}

			cellSpurs.error("Thor SELHIST (sys=%u):%s", s_sel_hist[32 & 31].load(), hist);
		}
	}

	if (thor_hle_spurs_diagnostics() && wklSelectedId < CELL_SPURS_MAX_WORKLOAD2)
	{
		static std::array<std::atomic<u32>, 8> s_real_sel{};

		if (ctxt->spuNum < 8 && thor_hle_once(s_real_sel[ctxt->spuNum], 0))
		{
			cellSpurs.error("Thor SPU%u SELECTED REAL WORKLOAD wid=%u (isPoll=%u)",
				+ctxt->spuNum, wklSelectedId, +isPoll);
		}
	}

	u64 result = u64{wklSelectedId} << 32;
	result |= pollStatus;
	spu.gpr[3]._u64[1] = result;
	return true;
}

// Select a workload to run
bool spursKernel2SelectWorkload(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursKernelContext>(0x100);

	// The kernel1 probe never fired, which I read as "the selector never runs".
	// That conclusion was only valid for kernel1 - this title may take the
	// 32-workload path instead, and the gate has call sites in BOTH selectors.
	{
		static std::atomic<u32> s_entry2_logged{0};

		if (thor_hle_once(s_entry2_logged, spu.index))
		{
			cellSpurs.error("Thor SELECTOR2 first entry: spu=%u pc=0x%05x", spu.index, spu.pc);
		}
	}

	// The first and only argument to this function is a boolean that is set to false if the function
	// is called by the SPURS kernel and set to true if called by cellSpursModulePollStatus.
	// If the first argument is true then the shared data is not updated with the result.
	const auto isPoll = spu.gpr[3]._u32[3];

	u32 wklSelectedId;
	u32 pollStatus;

	// vm::reservation_op(vm::cast(ctxt->spurs.addr()), 128, [&]()
	{
		// lock the first 0x80 bytes of spurs
		auto spurs = ctxt->spurs.get_ptr();

		// Calculate the contention (number of SPUs used) for each workload
		u8 contention[CELL_SPURS_MAX_WORKLOAD2];
		u8 pendingContention[CELL_SPURS_MAX_WORKLOAD2];
		for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD2; i++)
		{
			{
				// Same u8 underflow the kernel1 selector had.
				const u8 kcur = spurs->wklCurrentContention[i & 0x0F];
				const u8 kloc = ctxt->wklLocContention[i & 0x0F];

				contention[i] = kcur >= kloc ? kcur - kloc : 0;
			}
			contention[i] = i + 0u < CELL_SPURS_MAX_WORKLOAD ? contention[i] & 0x0F : contention[i] >> 4;

			// If this is a poll request then the number of SPUs pending to context switch is also added to the contention presumably
			// to prevent unnecessary jumps to the kernel
			if (isPoll)
			{
				pendingContention[i] = spurs->wklPendingContention[i & 0x0F] - ctxt->wklLocPendingContention[i & 0x0F];
				pendingContention[i] = i + 0u < CELL_SPURS_MAX_WORKLOAD ? pendingContention[i] & 0x0F : pendingContention[i] >> 4;
				if (i != ctxt->wklCurrentId)
				{
					contention[i] += pendingContention[i];
				}
			}
		}

		wklSelectedId = CELL_SPURS_SYS_SERVICE_WORKLOAD_ID;
		pollStatus = 0;

		// The system service has the highest priority. Select the system service if
		// the system service message bit for this SPU is set.
		if (spurs->sysSrvMessage & (1 << ctxt->spuNum))
		{
			// Not sure what this does. Possibly Mark the SPU as in use.
			ctxt->spuIdling = 0;
			if (!isPoll || ctxt->wklCurrentId == CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				// Clear the message bit
				spurs->sysSrvMessage.raw() &= ~(1 << ctxt->spuNum);
			}
		}
		else
		{
			// Caclulate the scheduling weight for each workload
			u8 maxWeight = 0;
			for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD2; i++)
			{
				u32 j = i & 0x0f;
				u16 runnable = i < CELL_SPURS_MAX_WORKLOAD ? ctxt->wklRunnable1 & (0x8000 >> j) : ctxt->wklRunnable2 & (0x8000 >> j);
				u8 priority = i < CELL_SPURS_MAX_WORKLOAD ? ctxt->priority[j] & 0x0F : ctxt->priority[j] >> 4;
				u8 maxContention = i < CELL_SPURS_MAX_WORKLOAD ? spurs->wklMaxContention[j] & 0x0F : spurs->wklMaxContention[j] >> 4;
				u16 wklSignal = i < CELL_SPURS_MAX_WORKLOAD ? spurs->wklSignal1.load() & (0x8000 >> j) : spurs->wklSignal2.load() & (0x8000 >> j);
				u8 wklFlag = spurs->wklFlag.flag.load() == 0u ? spurs->wklFlagReceiver == i ? 1 : 0 : 0;
				u8 readyCount = i < CELL_SPURS_MAX_WORKLOAD ? spurs->wklReadyCount1[j] : spurs->wklIdleSpuCountOrReadyCount2[j];

				// For a workload to be considered for scheduling:
				// 1. Its priority must be greater than 0
				// 2. The number of SPUs used by it must be less than the max contention for that workload
				// 3. The workload should be in runnable state
				// 4. The number of SPUs allocated to it must be less than the number of SPUs requested (i.e. readyCount)
				//    OR the workload must be signalled
				//    OR the workload flag is 0 and the workload is configured as the wokload receiver
				if (runnable && priority > 0 && maxContention > contention[i])
				{
					if (wklFlag || wklSignal || readyCount > contention[i])
					{
						// The scheduling weight of the workload is equal to the priority of the workload for the SPU.
						// The current workload is given a sligtly higher weight presumably to reduce the number of context switches.
						// In case of a tie the lower numbered workload is chosen.
						u8 weight = priority << 4;
						if (ctxt->wklCurrentId == i)
						{
							weight |= 0x04;
						}

						if (weight > maxWeight)
						{
							wklSelectedId = i;
							maxWeight = weight;
							pollStatus = readyCount > contention[i] ? CELL_SPURS_MODULE_POLL_STATUS_READYCOUNT : 0;
							pollStatus |= wklSignal ? CELL_SPURS_MODULE_POLL_STATUS_SIGNAL : 0;
							pollStatus |= wklFlag ? CELL_SPURS_MODULE_POLL_STATUS_FLAG : 0;
						}
					}
				}
			}

			// Not sure what this does. Possibly mark the SPU as idle/in use.
			ctxt->spuIdling = wklSelectedId == CELL_SPURS_SYS_SERVICE_WORKLOAD_ID ? 1 : 0;

			// Same Ghidra-derived condition as kernel1 (see the long note there).
			// Hardware branches on "am I running the SYSTEM SERVICE", not on
			// "did the selection change". This title takes the kernel1 path -
			// its SPUs report [0x00818] = CELL_SPURS_KERNEL1_ENTRY_ADDR - so this
			// copy is for 32-workload titles, kept in step so the two selectors
			// cannot drift.
			const bool commitSelection2 = thor_spurs_sel_cond_fix()
				? (!isPoll || ctxt->wklCurrentId == CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
				: (!isPoll || wklSelectedId == ctxt->wklCurrentId);
			const bool consumeSignal2 = !thor_spurs_sel_cond_fix() || !isPoll;

			if (commitSelection2)
			{
				// Same undefined shift as the kernel1 selector: 0x8000 >> 32 wraps
				// to 0x8000 on AArch64 and clears workload 0. See the comment there.
				// CONTROL EXPERIMENT, 2026-08-25. Both arms run IDENTICAL code.
				//
				// fix=1 hung the game at ~1 s of emulated time, before SPURS even
				// armed - which a change to signal semantics inside the selector
				// should not be able to do. The other suspect is the gate itself:
				// thor_spurs_signal_fix() is a function-local static whose
				// initializer calls __system_property_get, and six SPU threads
				// reach it concurrently on a hot path. If THAT is the hang, then
				// calling it at all is the bug and the signal analysis is
				// untouched.
				//
				// So: read the flag, ignore it, and always run the original. If
				// fix=1 still hangs, the mechanism is guilty and the property must
				// be read once at load time instead of lazily on an SPU thread.
				// KEEP THE WRITE, FIX THE MASK.
				//
				// Three things are now measured, and together they pin the repair:
				//
				//  1. `0x8000 >> wklSelectedId` with wklSelectedId == 32 is UB, and
				//     AArch64 evaluates it as `>> 0`, so this clears workload 0's
				//     signal - the one gate term that can start a taskset.
				//  2. Deleting the statement HANGS the game at ~1 s, before SPURS
				//     arms (armed=0 twice, against armed=6 twice).
				//  3. That hang is NOT my property gate: a control where both arms
				//     ran byte-identical code booted fine (armed=6).
				//
				// So the statement is load-bearing for a reason that has nothing to
				// do with which bit it clears: it is a WRITE to guest memory, and in
				// SPURS a write to this line is also a reservation notification. Drop
				// the store and a waiter never wakes.
				//
				// Therefore keep writing, but with a mask that changes nothing when
				// the system service is selected. Same store, same notification, no
				// corrupted signal.
				if (!consumeSignal2)
				{
					// Poll: report the selection, consume nothing.
				}
				else
				{
					spursAtomicClearSelectedSignal(spurs, wklSelectedId, thor_spurs_signal_fix());
				}

				// If the selected workload is the wklFlag workload then pull the wklFlag to all 1s
				if (wklSelectedId == spurs->wklFlagReceiver)
				{
					spurs->wklFlag.flag = -1;
				}
			}
		}

		if (!isPoll)
		{
			// Called by kernel
			// Increment the contention for the selected workload
			if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				contention[wklSelectedId]++;
			}

			for (u32 i = 0; i < (CELL_SPURS_MAX_WORKLOAD2 >> 1); i++)
			{
				spurs->wklCurrentContention[i] = contention[i] | (contention[i + 0x10] << 4);
				// SATURATE. This was a raw u8 subtraction and it UNDERFLOWS.
				//
				// Measured at the hang, with the shared current-contention CLEAN:
				//
				//   select#1 wkl0: maxCont=8 cont=253 ... K2=0 rawCont=0x00
				//
				// rawCont is the shared wklCurrentContention and it is 0, so the 253
				// came from pendingContention, which the poll path adds in. 253 is 0-3
				// wrapped in a u8.
				//
				// wklCurrentContention already had a clamp (see CONTENTION CLAMP above);
				// wklPendingContention never did. The read side saturates too, but that
				// only stops a SECOND underflow - once the SHARED byte is 253 it is
				// passed straight through, `maxContention > contention` is false forever
				// (8 > 253 never holds), and the workload can never be selected again.
				//
				// That is the hang: every workload unselectable, six SPUs spinning in the
				// selector, no task ever dispatched, and draw_calls = 0.
				{
					const u8 pcur = spurs->wklPendingContention[i];
					const u8 ploc = ctxt->wklLocPendingContention[i];

					spurs->wklPendingContention[i] = pcur >= ploc ? pcur - ploc : 0;
				}
				ctxt->wklLocContention[i] = 0;
				ctxt->wklLocPendingContention[i] = 0;
			}

			ctxt->wklLocContention[wklSelectedId & 0x0F] = wklSelectedId < CELL_SPURS_MAX_WORKLOAD ? 0x01 : wklSelectedId < CELL_SPURS_MAX_WORKLOAD2 ? 0x10 :
			                                                                                                                                           0;
			ctxt->wklCurrentId = wklSelectedId;
		}
		else if (wklSelectedId != ctxt->wklCurrentId)
		{
			// Not called by kernel but a context switch is required
			// Increment the pending contention for the selected workload
			if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
			{
				pendingContention[wklSelectedId]++;
			}

			for (u32 i = 0; i < (CELL_SPURS_MAX_WORKLOAD2 >> 1); i++)
			{
				spurs->wklPendingContention[i] = pendingContention[i] | (pendingContention[i + 0x10] << 4);
				ctxt->wklLocPendingContention[i] = 0;
			}

			ctxt->wklLocPendingContention[wklSelectedId & 0x0F] = wklSelectedId < CELL_SPURS_MAX_WORKLOAD ? 0x01 : wklSelectedId < CELL_SPURS_MAX_WORKLOAD2 ? 0x10 :
			                                                                                                                                                  0;
		}
		else
		{
			// Not called by kernel and no context switch is required
			for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
			{
				// SATURATE. This was a raw u8 subtraction and it UNDERFLOWS.
				//
				// Measured at the hang, with the shared current-contention CLEAN:
				//
				//   select#1 wkl0: maxCont=8 cont=253 ... K2=0 rawCont=0x00
				//
				// rawCont is the shared wklCurrentContention and it is 0, so the 253
				// came from pendingContention, which the poll path adds in. 253 is 0-3
				// wrapped in a u8.
				//
				// wklCurrentContention already had a clamp (see CONTENTION CLAMP above);
				// wklPendingContention never did. The read side saturates too, but that
				// only stops a SECOND underflow - once the SHARED byte is 253 it is
				// passed straight through, `maxContention > contention` is false forever
				// (8 > 253 never holds), and the workload can never be selected again.
				//
				// That is the hang: every workload unselectable, six SPUs spinning in the
				// selector, no task ever dispatched, and draw_calls = 0.
				{
					const u8 pcur = spurs->wklPendingContention[i];
					const u8 ploc = ctxt->wklLocPendingContention[i];

					spurs->wklPendingContention[i] = pcur >= ploc ? pcur - ploc : 0;
				}
				ctxt->wklLocPendingContention[i] = 0;
			}
		}

		std::memcpy(ctxt, spurs, 128);
	} //);

	u64 result = u64{wklSelectedId} << 32;
	result |= pollStatus;
	spu.gpr[3]._u64[1] = result;
	return true;
}

// SPURS kernel dispatch workload
void spursKernelDispatchWorkload(spu_thread& spu, u64 widAndPollStatus)
{
	const auto ctxt = spu._ptr<SpursKernelContext>(0x100);
	const bool isKernel2 = ctxt->spurs->flags1 & SF1_32_WORKLOADS ? true : false;

	auto pollStatus = static_cast<u32>(widAndPollStatus);
	auto wid = static_cast<u32>(widAndPollStatus >> 32);

	// DMA in the workload info for the selected workload
	auto wklInfoOffset = wid < CELL_SPURS_MAX_WORKLOAD               ? &ctxt->spurs->wklInfo1[wid] :
	                     wid < CELL_SPURS_MAX_WORKLOAD2 && isKernel2 ? &ctxt->spurs->wklInfo2[wid & 0xf] :
	                                                                   &ctxt->spurs->wklInfoSysSrv;

	const auto wklInfo = spu._ptr<CellSpurs::WorkloadInfo>(0x3FFE0);
	std::memcpy(wklInfo, wklInfoOffset, 0x20);

	// ONE-SHOT per SPU. Does the selector pick the taskset now that the workload
	// state is real?
	//
	// SPURS_IMG_ADDR_SYS_SRV_WORKLOAD = 0x100, SPURS_IMG_ADDR_TASKSET_PM = 0x200.
	// Before the snapshot fixes every SPU dispatched 0x100 once and stopped. Logs
	// the FIRST TWO dispatches per SPU only - per-dispatch logging on this path
	// boot-looped the branch (36cb52ca1), the one-shot breadcrumb pattern did not.
	{
		static std::array<std::atomic<u32>, 8> s_seen{};

		if (spu.index < 8 && s_seen[spu.index].fetch_add(1) < 2)
		{
			cellSpurs.error("Thor SPU%u dispatch#%u: wid=%u addr=0x%x size=0x%x",
				spu.index, s_seen[spu.index].load(), wid, wklInfo->addr.addr(), +wklInfo->size);
		}
	}

	// WHICH WORKLOAD IS ACTUALLY BEING DISPATCHED, AND WITH WHAT ARGUMENT?
	//
	// 183 of 183 sampled taskset dispatches carried taskset 0x101b4e80 and ZERO
	// carried the queue's taskset 0x10364100, so either the kernel only ever
	// selects that workload, or the argument handed to the taskset PM is wrong.
	// wklInfo->arg is what becomes ctxt->taskset in spursTasksetEntry.
	{
		static std::atomic<u32> s_dw{0};

		if (const u32 dn = s_dw++; (dn & 0x3F) == 0)
		{
			cellSpurs.error("Thor DISPATCH_WKL #%u: spu=%u wid=%u addr=0x%x arg=0x%llx",
				dn, spu.index, wid, wklInfo->addr.addr(), +wklInfo->arg);
		}
	}

	// CONSUME THE SIGNAL HERE, AT DISPATCH, NOT AT SELECTION.
	//
	// The original clears it inside the selector via `0x8000 >> wklSelectedId`.
	// With wklSelectedId == 32 (the system service) that shift is UNDEFINED and
	// AArch64 evaluates it as `>> 0`, so it clears bit 15 - workload 0 - every
	// time an SPU polls while parked in the system service. The workload's signal
	// is therefore eaten BEFORE the workload is ever dispatched, which is the
	// deadlock this branch has shown for weeks: six SPUs dispatch wid=32 once and
	// never move.
	//
	// Simply not clearing is worse, and it was measured: the selector then reports
	// "selected differs from current" on every call, the SPU exits to the kernel
	// and re-selects forever, and the GAME hangs at about 1 s of emulated time
	// (fix=1 armed=0 twice, against fix=0 armed=6 twice).
	//
	// So the clear is load-bearing but it is in the wrong place. A signal means
	// "this workload has work"; it should be consumed when that workload is
	// actually dispatched to an SPU. Doing it here breaks the livelock - the SPU
	// takes the workload and the signal goes away - while letting the taskset run,
	// which consuming-at-selection never did.
	//
	// Real workloads only. The system service has no signal bit, which is exactly
	// what the undefined shift forgot. The selector already consumes an HLE
	// workload signal. Do not clear a newer signal that the PPU can publish
	// between selection and dispatch. Real policy modules keep the legacy
	// dispatch-time clear.
	const bool signalConsumedBySelector = thor_spurs_signal_fix() &&
		spursWorkloadUsesHleEntry(ctxt->spurs.get_ptr(), wid, isKernel2);

	if (!signalConsumedBySelector && wid < CELL_SPURS_MAX_WORKLOAD)
	{
		ctxt->spurs->wklSignal1.atomic_op([&](be_t<u16>& sig)
			{
				sig &= ~(0x8000 >> wid);
			});
	}
	else if (!signalConsumedBySelector && wid < CELL_SPURS_MAX_WORKLOAD2)
	{
		ctxt->spurs->wklSignal2.atomic_op([&](be_t<u16>& sig)
			{
				sig &= ~(0x8000 >> (wid - CELL_SPURS_MAX_WORKLOAD));
			});
	}

	// Load the workload to LS
	if (ctxt->wklCurrentAddr != wklInfo->addr)
	{
		// EVERY WORKLOAD IMAGE LOAD, so the dispatch flow can be graphed.
		//
		// LS 0xA00 under HLE was measured EMPTY (830/8704 bytes matching the real
		// job chain module, first 16 bytes zero) while under LLE it matches 100%.
		// That capture had wklCurrentAddr = 0x100 (the SYS_SRV sentinel), so it
		// only proves that SPU was on another workload at the time - not that the
		// job chain copy fails. Log the load itself and stop inferring.
		{
			static std::atomic<u32> s_ld{0};
			const u32 n = s_ld++;

			if (n < 64 || (n & 0x3FF) == 0)
			{
				const u32 a = wklInfo->addr.addr();
				const char* kind =
					a == SPURS_IMG_ADDR_SYS_SRV_WORKLOAD ? "SYS_SRV" :
					a == SPURS_IMG_ADDR_TASKSET_PM       ? "TASKSET" :
					a == SPURS_IMG_ADDR_JOBCHAIN_PM      ? "JOBCHAIN-SENTINEL" :
					a == 0                               ? "NULL-IMAGE" : "REAL-IMAGE";

				// ARG MATTERS: the kernel passes wklInfo->arg to the module in r4, and
				// for a job chain that must be the CellSpursJobChain address. The
				// module was measured exiting with r4 = 0.
				cellSpurs.error("Thor WKLOAD #%u: wid=%u addr=0x%x size=0x%x arg=0x%llx kind=%s spu=%u",
					n, wid, a, +wklInfo->size, +wklInfo->arg, kind, +ctxt->spuNum);

				// AND THE JOB CHAIN ITSELF.
				//
				// The module has the right code, the right kernel contract and the
				// right job chain pointer, and still decides there is nothing to do.
				// What is left is the CONTENT of the structure it DMAs in. Decode the
				// fields it actually branches on rather than dumping raw bytes.
				if (a != SPURS_IMG_ADDR_SYS_SRV_WORKLOAD && a != SPURS_IMG_ADDR_TASKSET_PM && a != 0)
				{
					const u32 jc = static_cast<u32>(+wklInfo->arg);

					if (jc && vm::check_addr(jc, 0, 0x80))
					{
						const auto rd32 = [&](u32 o) { return +vm::_ref<be_t<u32>>(jc + o); };
						const auto rd16 = [&](u32 o) { return +vm::_ref<be_t<u16>>(jc + o); };
						const auto rd8  = [&](u32 o) { return vm::_ref<u8>(jc + o); };

						cellSpurs.error("Thor JOBCHAIN STATE jc=0x%x: pc=0x%08x_%08x "
							"lr0=0x%08x_%08x isHalted=%u autoReadyCount=%u initSpuCount=%u "
							"tag1=%u tag2=%u val2C=0x%02x jmVer=%u "
							"maxGrabbedJob=%u sizeJobDescriptor=%u workloadId=%u spurs=0x%08x_%08x "
							"urgent0=0x%08x_%08x",
							jc, rd32(0x00), rd32(0x04), rd32(0x08), rd32(0x0C),
							rd8(0x23), rd8(0x24), rd8(0x28), rd8(0x2A), rd8(0x2B), rd8(0x2C), rd8(0x2D),
							rd16(0x70), rd16(0x72), rd32(0x74), rd32(0x78), rd32(0x7C),
							rd32(0x30), rd32(0x34));

						// AND THE JOB DESCRIPTOR LIST ITSELF.
						//
						// `pc` is identical at every dispatch - measured across four
						// selections on four different SPUs - so the module runs and
						// consumes nothing. Either the descriptors are empty, or the
						// module rejects them. Print the first two entries; a jmVer=3
						// descriptor is sizeJobDescriptor bytes (0x80 here).
						const u32 pc32 = rd32(0x04);

						if (pc32 && vm::check_addr(pc32, 0, 0x40))
						{
							const auto d = [&](u32 o) { return +vm::_ref<be_t<u32>>(pc32 + o); };

							cellSpurs.error("Thor JOBDESC @0x%x: %08x %08x %08x %08x | %08x %08x %08x %08x",
								pc32, d(0x00), d(0x04), d(0x08), d(0x0C), d(0x10), d(0x14), d(0x18), d(0x1C));
							cellSpurs.error("Thor JOBDESC +0x20:  %08x %08x %08x %08x | %08x %08x %08x %08x",
								d(0x20), d(0x24), d(0x28), d(0x2C), d(0x30), d(0x34), d(0x38), d(0x3C));
						}
						else
						{
							cellSpurs.error("Thor JOBDESC: pc 0x%x is not readable guest memory", pc32);
						}
					}
					else
					{
						cellSpurs.error("Thor JOBCHAIN STATE: arg 0x%x is not readable guest memory", jc);
					}
				}
			}
		}

		switch (wklInfo->addr.addr())
		{
		case SPURS_IMG_ADDR_SYS_SRV_WORKLOAD:
			spu.RegisterHleFunction(0xA00, spursSysServiceEntry);
			break;
		case SPURS_IMG_ADDR_TASKSET_PM:
			spu.RegisterHleFunction(0xA00, spursTasksetEntry);
			break;
		case SPURS_IMG_ADDR_JOBCHAIN_PM:
			spu.RegisterHleFunction(0xA00, spursJobChainEntry);
			break;
		default:
			// DROP ANY HLE STUB SHADOWING 0xA00 BEFORE LOADING A REAL MODULE.
			//
			// The two cases above install an HLE function AT 0xA00, and a
			// registration made for one workload is still live when a DIFFERENT
			// workload is loaded here. So the real policy module was copied into
			// local store and then never executed: the SPU reached 0xA00, found the
			// previous workload's HLE stub registered there, and ran that instead.
			//
			// MEASURED, and this is what gives it away. The kernel enters a module
			// with r0 = exitToKernelAddr, sp = 0x3FFB0, r3 = 0x100, r5 = pollStatus
			// (see "Run workload" below). The job chain module was observed leaving
			// with:
			//
			//     lr=0x00808  sp=0x3ffb0  r3=0x00000100  r5=0x00000002
			//
			// EVERY register still at its entry value - including sp, which the
			// module's own second instruction (`ila sp,0x3ffd0` at 0xa20) would have
			// changed. It did not execute one instruction of its own prologue.
			//
			// Upstream never hits this because it registers no SPU-side HLE entries
			// at all (both RegisterHleFunction calls are commented out there) and
			// always runs real images through this branch. Enabling the HLE entries
			// made unregistering mandatory, and the calls to do it were left
			// commented out in spursTasksetInit and spursKernelEntry.
			spu.UnregisterHleFunction(0xA00);
			std::memcpy(spu._ptr<void>(0xA00), wklInfo->addr.get_ptr(), wklInfo->size);
			thor_install_jobchain_trace(spu);

			// DUMP LOCAL STORE ONCE, WITH THE JOB CHAIN MODULE RESIDENT.
			//
			// An LLE capture already exists in which this same module is resident at
			// 0xA00 and WORKING (_research/spurs/ls_lle_CellSpursKernel1.bin - the
			// module matched 8704/8704 bytes there). Capturing the HLE equivalent at
			// the same point makes the two directly comparable, and the differences
			// outside the module image are the data the working one has and ours
			// does not.
			//
			// One shot, and only for the job chain - the taskset and system service
			// pass through here constantly.
			{
				static std::atomic<bool> s_dumped{false};

				if (bool expected = false; s_dumped.compare_exchange_strong(expected, true))
				{
					if (FILE* f = std::fopen("/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/thor_ls_jobchain.bin", "wb"))
					{
						std::fwrite(spu._ptr<void>(0), 1, 0x40000, f);
						std::fclose(f);
						cellSpurs.error("Thor LS DUMP: job chain resident, 256KB written (spu=%u)", +ctxt->spuNum);
					}
				}
			}
			break;
		}

		ctxt->wklCurrentAddr = wklInfo->addr;
		ctxt->wklCurrentUniqueId = wklInfo->uniqueId;
	}

	if (!isKernel2)
	{
		ctxt->moduleId[0] = 0;
		ctxt->moduleId[1] = 0;
	}

	// Run workload
	spu.gpr[0]._u32[3] = ctxt->exitToKernelAddr;
	spu.gpr[1]._u32[3] = 0x3FFB0;
	spu.gpr[3]._u32[3] = 0x100;
	spu.gpr[4]._u64[1] = wklInfo->arg;
	// DO NOT HAND A CONSUMED SIGNAL TO THE POLICY MODULE.
	//
	// The selection loop above ALREADY consumed the workload's signal - it does
	// `wklSignal1 &= ~(0x8000 >> wid)` on the way to picking this workload - so
	// reporting SIGNAL in the entry poll status describes a condition that no
	// longer exists.
	//
	// The real job chain policy module treats it as fatal. Straight from its
	// disassembly, at its entry:
	//
	//     0221c  lqd  r3,0x20(sp)   ; the word holding the pollStatus argument
	//     02220  andi r11,r3,0x2    ; CELL_SPURS_MODULE_POLL_STATUS_SIGNAL
	//     02224  brz  r11,0x222c    ; clear -> carry on
	//     02228  stopd              ; SET -> assert
	//
	// MEASURED once the module was actually allowed to run (see the
	// UnregisterHleFunction fix): it reaches 0x2228 and the SPU dies with
	// "Unknown STOP code: 0x3fff". Entry state was r5 = 0x00000002, exactly this
	// bit. cellSpursRunJobChain signals the workload, so EVERY job chain start
	// hit this.
	//
	//   debug.rpcsx.thor.entry_pollstatus_fix = 0  pass the raw poll status
	spu.gpr[5]._u32[3] = thor_entry_pollstatus_fix()
		? (pollStatus & ~u32{CELL_SPURS_MODULE_POLL_STATUS_SIGNAL})
		: pollStatus;
	spu.pc = 0xA00;
}

// SPURS kernel workload exit
bool spursKernelWorkloadExit(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursKernelContext>(0x100);

	// WHERE INSIDE THE JOB CHAIN MODULE DOES IT GIVE UP?
	//
	// The staged real module is loaded to LS 0xA00, entered, and returns here
	// immediately having done no work - twice in a whole run, with no fault and
	// no halt. A module that branches to exitToKernelAddr leaves its return
	// address in the link register (r0 on SPU), so THAT address is the exact
	// instruction inside the module that decided to bail. It maps straight onto
	// the disassembly of _research/spurs/jobchain_pm.spu.bin loaded at 0xA00.
	//
	// Only for the job chain: the taskset and system service exit through here
	// constantly and would bury it.
	{
		const u32 img = ctxt->wklCurrentAddr.addr();

		if (img != SPURS_IMG_ADDR_SYS_SRV_WORKLOAD && img != SPURS_IMG_ADDR_TASKSET_PM && img != 0)
		{
			static std::atomic<u32> s_x{0};

			if (const u32 n = s_x++; n < 16)
			{
				cellSpurs.error("Thor JCEXIT #%u: module image 0x%x wid=%u exits from lr=0x%05x "
					"sp=0x%05x r3=0x%08x r4=0x%08x r5=0x%08x spu=%u",
					n, img, +ctxt->wklCurrentId, +spu.gpr[0]._u32[3], +spu.gpr[1]._u32[3],
					+spu.gpr[3]._u32[3], +spu.gpr[4]._u32[3], +spu.gpr[5]._u32[3], +ctxt->spuNum);
			}
		}
	}
	const bool isKernel2 = ctxt->spurs->flags1 & SF1_32_WORKLOADS ? true : false;

	// Select next workload to run
	spu.gpr[3].clear();
	if (isKernel2)
	{
		spursKernel2SelectWorkload(spu);
	}
	else
	{
		spursKernel1SelectWorkload(spu);
	}

	spursKernelDispatchWorkload(spu, spu.gpr[3]._u64[1]);
	return false;
}

// SPURS kernel entry point
bool spursKernelEntry(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursKernelContext>(0x100);
	memset(ctxt, 0, sizeof(SpursKernelContext));

	// Save arguments
	ctxt->spuNum = spu.gpr[3]._u32[3];
	ctxt->spurs.set(spu.gpr[4]._u64[1]);

	const bool isKernel2 = ctxt->spurs->flags1 & SF1_32_WORKLOADS ? true : false;

	// Initialise the SPURS context to its initial values
	ctxt->dmaTagId = CELL_SPURS_KERNEL_DMA_TAG_ID;
	ctxt->wklCurrentUniqueId = 0x20;
	ctxt->wklCurrentId = CELL_SPURS_SYS_SERVICE_WORKLOAD_ID;
	ctxt->exitToKernelAddr = isKernel2 ? CELL_SPURS_KERNEL2_EXIT_ADDR : CELL_SPURS_KERNEL1_EXIT_ADDR;
	ctxt->selectWorkloadAddr = isKernel2 ? CELL_SPURS_KERNEL2_SELECT_WORKLOAD_ADDR : CELL_SPURS_KERNEL1_SELECT_WORKLOAD_ADDR;
	if (!isKernel2)
	{
		ctxt->x1F0 = 0xF0020000;
		ctxt->x200 = 0x20000;
		ctxt->guid[0] = 0x423A3A02;
		ctxt->guid[1] = 0x43F43A82;
		ctxt->guid[2] = 0x43F26502;
		ctxt->guid[3] = 0x420EB382;
	}
	else
	{
		ctxt->guid[0] = 0x43A08402;
		ctxt->guid[1] = 0x43FB0A82;
		ctxt->guid[2] = 0x435E9302;
		ctxt->guid[3] = 0x43A3C982;
	}

	// Register SPURS kernel HLE functions
	// spu.UnregisterHleFunctions(0, 0x40000/*LS_BOTTOM*/);
	// The kernel is HLE, but its CODE must still be present for the guest policy
	// modules that call into it. See thor_fill_kernel_code.
	thor_fill_kernel_code(spu, isKernel2);

	spu.RegisterHleFunction(isKernel2 ? CELL_SPURS_KERNEL2_ENTRY_ADDR : CELL_SPURS_KERNEL1_ENTRY_ADDR, spursKernelEntry);
	spu.RegisterHleFunction(ctxt->exitToKernelAddr, spursKernelWorkloadExit);
	spu.RegisterHleFunction(ctxt->selectWorkloadAddr, isKernel2 ? spursKernel2SelectWorkload : spursKernel1SelectWorkload);

	// Start the system service
	spursKernelDispatchWorkload(spu, u64{CELL_SPURS_SYS_SERVICE_WORKLOAD_ID} << 32);
	return false;
}

//----------------------------------------------------------------------------
// SPURS system workload functions
//----------------------------------------------------------------------------

// Entry point of the system service
bool spursSysServiceEntry(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursKernelContext>(spu.gpr[3]._u32[3]);
	// auto arg = spu.gpr[4]._u64[1];
	auto pollStatus = spu.gpr[5]._u32[3];

	{
		if (ctxt->wklCurrentId == CELL_SPURS_SYS_SERVICE_WORKLOAD_ID)
		{
			spursSysServiceMain(spu, pollStatus);
		}
		else
		{
			// TODO: If we reach here it means the current workload was preempted to start the
			// system workload. Need to implement this.
		}

		cellSpursModuleExit(spu);
	}

	return false;
}

// Wait for an external event or exit the SPURS thread group if no workloads can be scheduled
void spursSysServiceIdleHandler(spu_thread& spu, SpursKernelContext* ctxt)
{
	bool shouldExit;

	while (true)
	{
		// REFRESH THE SNAPSHOT BEFORE READING IT.
		//
		// LS 0x100 is `SpursKernelContext::tempArea[0x80]` - a 128-byte scratch at
		// the head of the context, into which the head of CellSpurs is meant to be
		// DMA'd. That is why these readers use 0x100, and it is by design, not a
		// collision.
		//
		// The defect is that nothing refreshes it here. spursKernelEntry memsets
		// the whole context, tempArea included, and the ONLY other write is in
		// spursSysServiceCleanupAfterSystemWorkload - far too late and too rare to
		// serve this loop. So the idle handler reads zeros, every workload looks
		// like state 0 / priority 0 / readyCount 0, and all six SPUs park here:
		//
		//   Thor SPU0 idle-handler first entry: ... NO-WORKLOAD-HAS-ANY-STATE
		//
		// while the PPU had created the taskset and signalled wid=1.
		//
		// Redirecting the read to ctxt->spurs instead was tried twice and BOOT
		// LOOPED both times (f766f1880, and the read-only narrowing after it): the
		// code is written against a private snapshot, not against the live
		// structure the PPU mutates under it. Refreshing the snapshot is what the
		// hardware kernel does, and it keeps every read local.
		std::memcpy(spu._ptr<void>(0x100), ctxt->spurs.get_ptr(), 128);
		const auto spurs = spu._ptr<CellSpurs>(0x100);
		// vm::reservation_acquire(ctxt->spurs.addr());

		// Find the number of SPUs that are idling in this SPURS instance
		u32 nIdlingSpus = 0;
		for (u32 i = 0; i < 8; i++)
		{
			if (spurs->spuIdling & (1 << i))
			{
				nIdlingSpus++;
			}
		}

		const bool allSpusIdle = nIdlingSpus == spurs->nSpus;
		const bool exitIfNoWork = spurs->flags1 & SF1_EXIT_IF_NO_WORK ? true : false;
		shouldExit = allSpusIdle && exitIfNoWork;

		// Check if any workloads can be scheduled
		bool foundReadyWorkload = false;
		if (spurs->sysSrvMessage & (1 << ctxt->spuNum))
		{
			foundReadyWorkload = true;
		}
		else
		{
			if (spurs->flags1 & SF1_32_WORKLOADS)
			{
				for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD2; i++)
				{
					u32 j = i & 0x0F;
					u16 runnable = i < CELL_SPURS_MAX_WORKLOAD ? ctxt->wklRunnable1 & (0x8000 >> j) : ctxt->wklRunnable2 & (0x8000 >> j);
					u8 priority = i < CELL_SPURS_MAX_WORKLOAD ? ctxt->priority[j] & 0x0F : ctxt->priority[j] >> 4;
					u8 maxContention = i < CELL_SPURS_MAX_WORKLOAD ? spurs->wklMaxContention[j] & 0x0F : spurs->wklMaxContention[j] >> 4;
					u8 contention = i < CELL_SPURS_MAX_WORKLOAD ? spurs->wklCurrentContention[j] & 0x0F : spurs->wklCurrentContention[j] >> 4;
					u16 wklSignal = i < CELL_SPURS_MAX_WORKLOAD ? spurs->wklSignal1.load() & (0x8000 >> j) : spurs->wklSignal2.load() & (0x8000 >> j);
					u8 wklFlag = spurs->wklFlag.flag.load() == 0u ? spurs->wklFlagReceiver == i ? 1 : 0 : 0;
					u8 readyCount = i < CELL_SPURS_MAX_WORKLOAD ? spurs->wklReadyCount1[j] : spurs->wklIdleSpuCountOrReadyCount2[j];

					if (runnable && priority > 0 && maxContention > contention)
					{
						if (wklFlag || wklSignal || readyCount > contention)
						{
							foundReadyWorkload = true;
							break;
						}
					}
				}
			}
			else
			{
				for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
				{
					u16 runnable = ctxt->wklRunnable1 & (0x8000 >> i);
					u16 wklSignal = spurs->wklSignal1.load() & (0x8000 >> i);
					u8 wklFlag = spurs->wklFlag.flag.load() == 0u ? spurs->wklFlagReceiver == i ? 1 : 0 : 0;
					u8 readyCount = spurs->wklReadyCount1[i] > CELL_SPURS_MAX_SPU ? CELL_SPURS_MAX_SPU : spurs->wklReadyCount1[i].load();
					u8 idleSpuCount = spurs->wklIdleSpuCountOrReadyCount2[i] > CELL_SPURS_MAX_SPU ? CELL_SPURS_MAX_SPU : spurs->wklIdleSpuCountOrReadyCount2[i].load();
					u8 requestCount = readyCount + idleSpuCount;

					if (runnable && ctxt->priority[i] != 0 && spurs->wklMaxContention[i] > spurs->wklCurrentContention[i])
					{
						if (wklFlag || wklSignal || (readyCount != 0 && requestCount > spurs->wklCurrentContention[i]))
						{
							foundReadyWorkload = true;
							break;
						}
					}
				}
			}
		}

		const bool spuIdling = spurs->spuIdling & (1 << ctxt->spuNum) ? true : false;
		if (foundReadyWorkload && shouldExit == false)
		{
			spurs->spuIdling &= ~(1 << ctxt->spuNum);
		}
		else
		{
			spurs->spuIdling |= 1 << ctxt->spuNum;
		}

		// If all SPUs are idling and the exit_if_no_work flag is set then the SPU thread group must exit. Otherwise wait for external events.
		if (spuIdling && shouldExit == false && foundReadyWorkload == false)
		{
			// The system service blocks by making a reservation and waiting on the lock line reservation lost event.
			// Check debug pause and stop before the existing sleep. Do not add
			// thread-state loads to active SPURS scheduling.
			const auto threadState = spu.state.load();
			if ((is_stopped(threadState) || threadState & (cpu_flag::dbg_global_pause | cpu_flag::dbg_pause)) && spu.check_state())
			{
				return;
			}

			thread_ctrl::wait_for(1000);
			continue;
		}

		// if (vm::reservation_update(vm::cast(ctxt->spurs.addr()), spu._ptr<void>(0x100), 128) && (shouldExit || foundReadyWorkload))
		{
			break;
		}
	}

	if (shouldExit)
	{
		// TODO: exit spu thread group
	}
}

// Main function for the system service
void spursSysServiceMain(spu_thread& spu, u32 pollStatus)
{
	const auto ctxt = spu._ptr<SpursKernelContext>(0x100);

	if (!ctxt->spurs.aligned())
	{
		spu_log.error("spursSysServiceMain(): invalid spurs alignment");
		spursHalt(spu);
	}

	// Initialise the system service if this is the first time its being started on this SPU
	if (ctxt->sysSrvInitialised == 0)
	{
		ctxt->sysSrvInitialised = 1;

		// vm::reservation_acquire(ctxt->spurs.addr());

		// vm::reservation_op(ctxt->spurs.ptr(&CellSpurs::wklState1).addr(), [&]()
		{
			auto spurs = ctxt->spurs.get_ptr();

			// Halt if already initialised
			if (spurs->sysSrvOnSpu & (1 << ctxt->spuNum))
			{
				spu_log.error("spursSysServiceMain(): already initialized");
				spursHalt(spu);
			}

			spurs->sysSrvOnSpu |= 1 << ctxt->spuNum;

			std::memcpy(spu._ptr<void>(0x2D80), spurs->wklState1, 128);
		} //);

		ctxt->traceBuffer = 0;
		ctxt->traceMsgCount = -1;
		spursSysServiceTraceUpdate(spu, ctxt, 1, 1, 0);
		spursSysServiceCleanupAfterSystemWorkload(spu, ctxt);

		// Trace - SERVICE: INIT
		CellSpursTracePacket pkt{};
		pkt.header.tag = CELL_SPURS_TRACE_TAG_SERVICE;
		pkt.data.service.incident = CELL_SPURS_TRACE_SERVICE_INIT;
		cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);
	}

	// Trace - START: Module='SYS '
	CellSpursTracePacket pkt{};
	pkt.header.tag = CELL_SPURS_TRACE_TAG_START;
	std::memcpy(pkt.data.start._module, "SYS ", 4);
	pkt.data.start.level = 1; // Policy module
	pkt.data.start.ls = 0xA00 >> 2;
	cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

	u32 pauseCheckCounter = 0;

	while (true)
	{
		// Process requests for the system service
		spursSysServiceProcessRequests(spu, ctxt);

	poll:
		// Every system-service path crosses this label. The idle-handler path
		// returns here with goto and can bypass the top of the loop forever. A
		// check before ProcessRequests therefore did not stop that path: six SPUs
		// stayed at pc 0xa00 with dbg_global_pause set. Check here at the same
		// bounded rate. Keep 255 of every 256 scheduling passes free of
		// thread-state atomics because a check on every pass changes the Bink race.
		if ((++pauseCheckCounter & 0xff) == 0)
		{
			const auto threadState = spu.state.load();
			if ((is_stopped(threadState) || threadState & (cpu_flag::dbg_global_pause | cpu_flag::dbg_pause)) && spu.check_state())
			{
				return;
			}
		}

		if (cellSpursModulePollStatus(spu, nullptr))
		{
			// Trace - SERVICE: EXIT
			CellSpursTracePacket pkt{};
			pkt.header.tag = CELL_SPURS_TRACE_TAG_SERVICE;
			pkt.data.service.incident = CELL_SPURS_TRACE_SERVICE_EXIT;
			cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

			// Trace - STOP: GUID
			pkt = {};
			pkt.header.tag = CELL_SPURS_TRACE_TAG_STOP;
			pkt.data.stop = SPURS_GUID_SYS_WKL;
			cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

			// spursDmaWaitForCompletion(spu, 1 << ctxt->dmaTagId);
			break;
		}

		// If we reach here it means that either there are more system service messages to be processed
		// or there are no workloads that can be scheduled.

		// If the SPU is not idling then process the remaining system service messages
		if (ctxt->spuIdling == 0)
		{
			continue;
		}

		// If we reach here it means that the SPU is idling

		// Trace - SERVICE: WAIT
		CellSpursTracePacket pkt{};
		pkt.header.tag = CELL_SPURS_TRACE_TAG_SERVICE;
		pkt.data.service.incident = CELL_SPURS_TRACE_SERVICE_WAIT;
		cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

		spursSysServiceIdleHandler(spu, ctxt);

		goto poll;
	}
}

// Process any requests
void spursSysServiceProcessRequests(spu_thread& spu, SpursKernelContext* ctxt)
{
	bool updateTrace = false;
	bool updateWorkload = false;
	bool terminate = false;

	// vm::reservation_op(vm::cast(ctxt->spurs.addr() + OFFSET_32(CellSpurs, wklState1)), 128, [&]()
	{
		auto spurs = ctxt->spurs.get_ptr();

		if (thor_hle_once(g_thor_hle_req_logged, ctxt->spuNum))
		{
			cellSpurs.error("Thor HLE SPU%u processRequests#1: spurs=0x%x msgUpdateWkl=0x%x sysSrvMsg=0x%x wklMskB=0x%x",
				+ctxt->spuNum, ctxt->spurs.addr(),
				+spurs->sysSrvMsgUpdateWorkload, +spurs->sysSrvMessage, +spurs->wklMskB);
		}

		// Terminate request
		if (spurs->sysSrvMsgTerminate & (1 << ctxt->spuNum))
		{
			spurs->sysSrvOnSpu &= ~(1 << ctxt->spuNum);
			terminate = true;
		}

		// Update workload message
		if (spurs->sysSrvMsgUpdateWorkload & (1 << ctxt->spuNum))
		{
			spurs->sysSrvMsgUpdateWorkload &= ~(1 << ctxt->spuNum);
			updateWorkload = true;
		}

		// Update trace message
		if (spurs->sysSrvTrace.load().sysSrvMsgUpdateTrace & (1 << ctxt->spuNum))
		{
			updateTrace = true;
		}

		std::memcpy(spu._ptr<void>(0x2D80), spurs->wklState1, 128);
	} //);

	// Process update workload message
	if (updateWorkload)
	{
		spursSysServiceActivateWorkload(spu, ctxt);
	}

	// Process update trace message
	if (updateTrace)
	{
		spursSysServiceTraceUpdate(spu, ctxt, 1, 0, 0);
	}

	// Process terminate request
	if (terminate)
	{
		// TODO: Rest of the terminate processing
	}
}

// Activate a workload
void spursSysServiceActivateWorkload(spu_thread& spu, SpursKernelContext* ctxt)
{
	// Refresh the private first-line snapshot before this SPU reads it.
	//
	// LS 0x100 is SpursKernelContext::tempArea, a 128-byte scratch meant to hold
	// the head of CellSpurs. Nothing refreshed it, so every read below saw the
	// zeros spursKernelEntry memset there. This function computes
	// ctxt->wklRunnable1 from spurs->wklState1, and wklRunnable1 is EXACTLY what
	// the selector and the idle handler test - so a stale snapshot made every
	// workload permanently unrunnable, which is the whole failure.
	//
	// Redirecting the reads to ctxt->spurs instead was tried and boot-looped the
	// emulator twice; the code is written against a private copy. Refresh only
	// the private copy here. The state and status updates below use the live
	// CellSpurs pointer.
	std::memcpy(spu._ptr<void>(0x100), ctxt->spurs.get_ptr(), 128);
	const auto spurs = spu._ptr<CellSpurs>(0x100);
	std::memcpy(spu._ptr<void>(0x30000), ctxt->spurs->wklInfo1, 0x200);
	if (spurs->flags1 & SF1_32_WORKLOADS)
	{
		std::memcpy(spu._ptr<void>(0x30200), ctxt->spurs->wklInfo2, 0x200);
	}

	u32 wklShutdownBitSet = 0;
	ctxt->wklRunnable1 = 0;
	ctxt->wklRunnable2 = 0;
	for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
	{
		const auto wklInfo1 = spu._ptr<CellSpurs::WorkloadInfo>(0x30000);

		// Copy the priority of the workload for this SPU and its unique id to the LS
		ctxt->priority[i] = wklInfo1[i].priority[ctxt->spuNum] == 0 ? 0 : 0x10 - wklInfo1[i].priority[ctxt->spuNum];
		ctxt->wklUniqueId[i] = wklInfo1[i].uniqueId;

		if (spurs->flags1 & SF1_32_WORKLOADS)
		{
			const auto wklInfo2 = spu._ptr<CellSpurs::WorkloadInfo>(0x30200);

			// Copy the priority of the workload for this SPU to the LS
			if (wklInfo2[i].priority[ctxt->spuNum])
			{
				ctxt->priority[i] |= (0x10 - wklInfo2[i].priority[ctxt->spuNum]) << 4;
			}
		}
	}

	// vm::reservation_op(ctxt->spurs.ptr(&CellSpurs::wklState1).addr(), 128, [&]()
	{
		auto spurs = ctxt->spurs.get_ptr();

		// PERIODIC. wkl2 reads runnable=0 prio=0 in the selector, so either this
		// never re-runs after the second taskset is created, or main memory has no
		// priority for that workload on this SPU. Print the SOURCE value.
		static std::atomic<u32> s_act{0};

		if ((s_act++ & 0x3F) == 0)
		{
			const auto wi = spu._ptr<CellSpurs::WorkloadInfo>(0x30000);

			cellSpurs.error("Thor ACTIVATE spu=%u: prio[spu] wkl0=%u wkl1=%u wkl2=%u wkl3=%u | wklMskB=0x%x state1[2]=%u",
				+ctxt->spuNum,
				+wi[0].priority[ctxt->spuNum], +wi[1].priority[ctxt->spuNum],
				+wi[2].priority[ctxt->spuNum], +wi[3].priority[ctxt->spuNum],
				+spurs->wklMskB, +spurs->wklState1[2]);
		}

		if (thor_hle_once(g_thor_hle_act_logged, ctxt->spuNum))
		{
			// The 16 state bytes as the SPU sees them, from MAIN MEMORY. If the
			// PPU's spursAddWorkload really wrote RUNNABLE(2), it is visible here
			// or the two sides are not looking at the same CellSpurs.
			char st[64]{};
			for (u32 k = 0, o = 0; k < CELL_SPURS_MAX_WORKLOAD && o + 3 < sizeof(st); k++, o += 3)
			{
				const u32 v = +spurs->wklState1[k];
				st[o] = static_cast<char>('0' + (v / 10) % 10);
				st[o + 1] = static_cast<char>('0' + v % 10);
				st[o + 2] = ' ';
			}

			cellSpurs.error("Thor HLE SPU%u activateWorkload#1: spurs=0x%x wklMskB=0x%x state1=[%s]",
				+ctxt->spuNum, ctxt->spurs.addr(), +spurs->wklMskB, st);
		}

		for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
		{
			// Update workload status and runnable flag based on the workload state
			auto wklStatus = spurs->wklStatus1[i];
			if (spurs->wklState1[i] == SPURS_WKL_STATE_RUNNABLE)
			{
				spurs->wklStatus1[i] |= 1 << ctxt->spuNum;
				ctxt->wklRunnable1 |= 0x8000 >> i;
			}
			else
			{
				spurs->wklStatus1[i] &= ~(1 << ctxt->spuNum);
			}

			// If the workload is shutting down and if this is the last SPU from which it is being removed then
			// add it to the shutdown bit set
			if (spurs->wklState1[i] == SPURS_WKL_STATE_SHUTTING_DOWN)
			{
				if (((wklStatus & (1 << ctxt->spuNum)) != 0) && (spurs->wklStatus1[i] == 0))
				{
					spurs->wklState1[i] = SPURS_WKL_STATE_REMOVABLE;
					wklShutdownBitSet |= 0x80000000u >> i;
				}
			}

			if (spurs->flags1 & SF1_32_WORKLOADS)
			{
				// Update workload status and runnable flag based on the workload state
				wklStatus = spurs->wklStatus2[i];
				if (spurs->wklState2[i] == SPURS_WKL_STATE_RUNNABLE)
				{
					spurs->wklStatus2[i] |= 1 << ctxt->spuNum;
					ctxt->wklRunnable2 |= 0x8000 >> i;
				}
				else
				{
					spurs->wklStatus2[i] &= ~(1 << ctxt->spuNum);
				}

				// If the workload is shutting down and if this is the last SPU from which it is being removed then
				// add it to the shutdown bit set
				if (spurs->wklState2[i] == SPURS_WKL_STATE_SHUTTING_DOWN)
				{
					if (((wklStatus & (1 << ctxt->spuNum)) != 0) && (spurs->wklStatus2[i] == 0))
					{
						spurs->wklState2[i] = SPURS_WKL_STATE_REMOVABLE;
						wklShutdownBitSet |= 0x8000 >> i;
					}
				}
			}
		}

		std::memcpy(spu._ptr<void>(0x2D80), spurs->wklState1, 128);

		// Do not copy the private first line back to shared memory. This line does
		// not contain wklState or wklStatus. The updates above already use the
		// live CellSpurs pointer. A whole-line copy can instead overwrite a PPU
		// write to wklSignal1 at offset 0x70. Six SPUs can activate workloads at
		// the same time, which made the signal loss timing-dependent on Thor.
	} //);

	if (wklShutdownBitSet)
	{
		spursSysServiceUpdateShutdownCompletionEvents(spu, ctxt, wklShutdownBitSet);
	}
}

// Update shutdown completion events
void spursSysServiceUpdateShutdownCompletionEvents(spu_thread& spu, SpursKernelContext* ctxt, u32 wklShutdownBitSet)
{
	// Mark the workloads in wklShutdownBitSet as completed and also generate a bit set of the completed
	// workloads that have a shutdown completion hook registered
	u32 wklNotifyBitSet;
	[[maybe_unused]] u8 spuPort;
	// vm::reservation_op(ctxt->spurs.ptr(&CellSpurs::wklState1).addr(), 128, [&]()
	{
		auto spurs = ctxt->spurs.get_ptr();

		wklNotifyBitSet = 0;
		spuPort = spurs->spuPort;
		for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
		{
			if (wklShutdownBitSet & (0x80000000u >> i))
			{
				spurs->wklEvent1[i] |= 0x01;
				if (spurs->wklEvent1[i] & 0x02 || spurs->wklEvent1[i] & 0x10)
				{
					wklNotifyBitSet |= 0x80000000u >> i;
				}
			}

			if (wklShutdownBitSet & (0x8000 >> i))
			{
				spurs->wklEvent2[i] |= 0x01;
				if (spurs->wklEvent2[i] & 0x02 || spurs->wklEvent2[i] & 0x10)
				{
					wklNotifyBitSet |= 0x8000 >> i;
				}
			}
		}

		std::memcpy(spu._ptr<void>(0x2D80), spurs->wklState1, 128);
	} //);

	if (wklNotifyBitSet)
	{
		// TODO: sys_spu_thread_send_event(spuPort, 0, wklNotifyMask);
	}
}

// Update the trace count for this SPU
void spursSysServiceTraceSaveCount(spu_thread& spu, SpursKernelContext* ctxt)
{
	if (ctxt->traceBuffer)
	{
		auto traceInfo = vm::ptr<CellSpursTraceInfo>::make(vm::cast(ctxt->traceBuffer - (ctxt->spurs->traceStartIndex[ctxt->spuNum] << 4)));
		traceInfo->count[ctxt->spuNum] = ctxt->traceMsgCount;
	}
}

// Update trace control
void spursSysServiceTraceUpdate(spu_thread& spu, SpursKernelContext* ctxt, u32 arg2, u32 arg3, u32 forceNotify)
{
	bool notify;

	u8 sysSrvMsgUpdateTrace;
	// vm::reservation_op(ctxt->spurs.ptr(&CellSpurs::wklState1).addr(), 128, [&]()
	{
		auto spurs = ctxt->spurs.get_ptr();
		auto& trace = spurs->sysSrvTrace.raw();

		sysSrvMsgUpdateTrace = trace.sysSrvMsgUpdateTrace;
		trace.sysSrvMsgUpdateTrace &= ~(1 << ctxt->spuNum);
		trace.sysSrvTraceInitialised &= ~(1 << ctxt->spuNum);
		trace.sysSrvTraceInitialised |= arg2 << ctxt->spuNum;

		notify = false;
		if (((sysSrvMsgUpdateTrace & (1 << ctxt->spuNum)) != 0) && (spurs->sysSrvTrace.load().sysSrvMsgUpdateTrace == 0) && (spurs->sysSrvTrace.load().sysSrvNotifyUpdateTraceComplete != 0))
		{
			trace.sysSrvNotifyUpdateTraceComplete = 0;
			notify = true;
		}

		if (forceNotify && spurs->sysSrvTrace.load().sysSrvNotifyUpdateTraceComplete != 0)
		{
			trace.sysSrvNotifyUpdateTraceComplete = 0;
			notify = true;
		}

		std::memcpy(spu._ptr<void>(0x2D80), spurs->wklState1, 128);
	} //);

	// Get trace parameters from CellSpurs and store them in the LS
	if (((sysSrvMsgUpdateTrace & (1 << ctxt->spuNum)) != 0) || (arg3 != 0))
	{
		// vm::reservation_acquire(ctxt->spurs.ptr(&CellSpurs::traceBuffer).addr());
		auto spurs = spu._ptr<CellSpurs>(0x80 - OFFSET_OF(CellSpurs, traceBuffer));

		if (ctxt->traceMsgCount != 0xffu || spurs->traceBuffer.addr() == 0u)
		{
			spursSysServiceTraceSaveCount(spu, ctxt);
		}
		else
		{
			const auto traceBuffer = spu._ptr<CellSpursTraceInfo>(0x2C00);
			std::memcpy(traceBuffer, vm::base(vm::cast(spurs->traceBuffer.addr()) & -0x4), 0x80);
			ctxt->traceMsgCount = traceBuffer->count[ctxt->spuNum];
		}

		ctxt->traceBuffer = spurs->traceBuffer.addr() + (spurs->traceStartIndex[ctxt->spuNum] << 4);
		ctxt->traceMaxCount = spurs->traceStartIndex[1] - spurs->traceStartIndex[0];
		if (ctxt->traceBuffer == 0u)
		{
			ctxt->traceMsgCount = 0u;
		}
	}

	if (notify)
	{
		auto spurs = spu._ptr<CellSpurs>(0x2D80 - OFFSET_OF(CellSpurs, wklState1));
		sys_spu_thread_send_event(spu, spurs->spuPort, 2, 0);
	}
}

// Restore state after executing the system workload
void spursSysServiceCleanupAfterSystemWorkload(spu_thread& spu, SpursKernelContext* ctxt)
{
	u8 wklId;

	bool do_return = false;

	// vm::reservation_op(ctxt->spurs.ptr(&CellSpurs::wklState1).addr(), 128, [&]()
	{
		auto spurs = ctxt->spurs.get_ptr();

		if (spurs->sysSrvPreemptWklId[ctxt->spuNum] == 0xFF)
		{
			do_return = true;
			return;
		}

		wklId = spurs->sysSrvPreemptWklId[ctxt->spuNum];
		spurs->sysSrvPreemptWklId[ctxt->spuNum] = 0xFF;

		std::memcpy(spu._ptr<void>(0x2D80), spurs->wklState1, 128);
	} //);

	if (do_return)
		return;

	spursSysServiceActivateWorkload(spu, ctxt);

	// vm::reservation_op(vm::cast(ctxt->spurs.addr()), 128, [&]()
	{
		auto spurs = ctxt->spurs.get_ptr();

		// SATURATING DECREMENTS. These are raw `-=` on `u8` fields shared by six
		// SPUs, so decrementing a counter that already reads 0 wraps to 255 - and
		// `maxContention > contention` can never hold again for a workload whose
		// maxContention is 1, which is the queue's taskset. `cont=255` was measured
		// on wkl2 with exactly this signature after the bulk write-back was made
		// atomic, so this path is the remaining writer that can corrupt it.
		//
		// Saturating at 0 is also the only meaning that makes sense: a contention
		// or ready count cannot be negative.
		if (wklId >= CELL_SPURS_MAX_WORKLOAD)
		{
			u8& cont = spurs->wklCurrentContention[wklId & 0x0F];
			cont = cont >= 0x10 ? cont - 0x10 : 0;

			auto& rc = spurs->wklReadyCount1[wklId & 0x0F];
			rc.raw() = rc.raw() ? rc.raw() - 1 : 0;
		}
		else
		{
			u8& cont = spurs->wklCurrentContention[wklId & 0x0F];
			cont = cont ? cont - 1 : 0;

			auto& rc = spurs->wklIdleSpuCountOrReadyCount2[wklId & 0x0F];
			rc.raw() = rc.raw() ? rc.raw() - 1 : 0;
		}

		std::memcpy(spu._ptr<void>(0x100), spurs, 128);
	} //);

	// Set the current workload id to the id of the pre-empted workload since cellSpursModulePutTrace
	// uses the current worload id to determine the workload to which the trace belongs
	auto wklIdSaved = ctxt->wklCurrentId;
	ctxt->wklCurrentId = wklId;

	// Trace - STOP: GUID
	CellSpursTracePacket pkt{};
	pkt.header.tag = CELL_SPURS_TRACE_TAG_STOP;
	pkt.data.stop = SPURS_GUID_SYS_WKL;
	cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

	ctxt->wklCurrentId = wklIdSaved;
}

//----------------------------------------------------------------------------
// SPURS taskset policy module functions
//----------------------------------------------------------------------------

enum SpursTasksetRequest
{
	SPURS_TASKSET_REQUEST_POLL_SIGNAL = -1,
	SPURS_TASKSET_REQUEST_DESTROY_TASK = 0,
	SPURS_TASKSET_REQUEST_YIELD_TASK = 1,
	SPURS_TASKSET_REQUEST_WAIT_SIGNAL = 2,
	SPURS_TASKSET_REQUEST_POLL = 3,
	SPURS_TASKSET_REQUEST_WAIT_WKL_FLAG = 4,
	SPURS_TASKSET_REQUEST_SELECT_TASK = 5,
	SPURS_TASKSET_REQUEST_RECV_WKL_FLAG = 6,
};

// Taskset PM entry point
bool spursTasksetEntry(spu_thread& spu)
{
	auto kernelCtxt = spu._ptr<SpursKernelContext>(spu.gpr[3]._u32[3]);

	// HOW OFTEN IS THE TASKSET MODULE ENTERED, versus how often does it DISPATCH?
	//
	// Seven dispatches in four minutes is the one number nothing explains, while
	// SPU program counters sample at 0xa00 - inside this handler - constantly.
	// This entry runs memset + init + dispatch exactly once per call, so entries
	// and dispatches should match. If they do not, the gap is between them.
	{
		static std::atomic<u64> s_entries{0};

		if (const u64 n = ++s_entries; n <= 4 || (n % 4096) == 0)
		{
			cellSpurs.error("Thor TASKSET ENTRY #%llu (spu=%u)", n, +spu.lv2_id);
		}
	}

	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);
	auto arg = spu.gpr[4]._u64[1];
	auto pollStatus = spu.gpr[5]._u32[3];

	// Initialise memory and save args
	memset(ctxt, 0, sizeof(*ctxt));
	ctxt->taskset.set(arg);
	memcpy(ctxt->moduleId, "SPURSTASK MODULE", sizeof(ctxt->moduleId));
	ctxt->kernelMgmtAddr = spu.gpr[3]._u32[3];
	ctxt->syscallAddr = CELL_SPURS_TASKSET_PM_SYSCALL_ADDR;
	ctxt->spuNum = kernelCtxt->spuNum;
	ctxt->dmaTagId = kernelCtxt->dmaTagId;
	ctxt->taskId = 0xFFFFFFFF;

	// Register SPURS takset policy module HLE functions
	// spu.UnregisterHleFunctions(CELL_SPURS_TASKSET_PM_ENTRY_ADDR, 0x40000/*LS_BOTTOM*/);
	spu.RegisterHleFunction(CELL_SPURS_TASKSET_PM_ENTRY_ADDR, spursTasksetEntry);
	// REGISTER THE TASKSET SYSCALL ENTRY. Leaving this out is why the SPU faults
	// about 20 ms after the taskset first dispatches.
	//
	// `ctxt->syscallAddr` is CELL_SPURS_TASKSET_PM_SYSCALL_ADDR = 0xA70, an
	// address tasks BRANCH TO to make a syscall. With nothing registered there
	// the SPU executes whatever local store holds - zeros - and dies.
	//
	// GHIDRA CONFIRMS 0xA70 IS REAL CODE, not a stub. Disassembling the genuine
	// policy module out of LLE local store shows the context save begins at
	// exactly that address:
	//
	//     00000a70: stqa lr,0x2c80
	//     00000a74: stqa sp,0x2c90
	//     00000a7c: stqa r80,0x2ca0  ...  r92,0x2d60
	//
	// So a task syscall means "save my context and re-enter the policy module",
	// and spursTasksetSyscallEntry is the HLE stand-in for that. The entry above
	// is already registered by this very function, so the mechanism is present
	// and only this call was missing.
	// Gated so it can be A/B'd in ONE binary. The breakthrough run - armed=6 plus
	// the first wid=0 addr=0x200 dispatch - predates this registration, and a
	// later run armed 6 kernels but never dispatched the taskset. That is the only
	// delta, so it has to be isolated rather than assumed either way.
	//
	//   debug.rpcsx.thor.taskset_syscall_fix = 1  register the handler (default)
	//   debug.rpcsx.thor.taskset_syscall_fix = 0  leave 0xA70 unregistered
	if (thor_taskset_syscall_fix())
	{
		spu.RegisterHleFunction(ctxt->syscallAddr, spursTasksetSyscallEntry);
	}

	{
		// Initialise the taskset policy module
		spursTasksetInit(spu, pollStatus);

		// Dispatch
		spursTasksetDispatch(spu);
	}

	return false;
}

// Entry point into the Taskset PM for task syscalls
bool spursTasksetSyscallEntry(spu_thread& spu)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);

	{
		// Save task context
		ctxt->savedContextLr = spu.gpr[0];
		ctxt->savedContextSp = spu.gpr[1];
		for (auto i = 0; i < 48; i++)
		{
			ctxt->savedContextR80ToR127[i] = spu.gpr[80 + i];
		}

		// Handle the syscall
		//
		// THIS FUNCTION USED TO THROW. `fmt::throw_exception("Broken (TODO)")`
		// sat right here, which is why the registration of this entry at 0xA70 was
		// commented out upstream - and why registering it looked "neutral" in the
		// A/B: nothing ever reached a task, so nothing ever made a syscall. Now
		// that tasks actually run, every syscall lands here.
		//
		// The original intent is in the dead code below: resume the task unless
		// the syscall caused a context switch. `spu.m_is_branch` no longer exists
		// on spu_thread (the same removal that killed `custom_task`), but the test
		// it stood for is observable - a syscall that switches context MOVES pc,
		// e.g. cellSpursModuleExit sets pc to ctxt->exitToKernelAddr. So snapshot
		// pc, run the syscall, and resume only if pc is untouched.
		//
		//   debug.rpcsx.thor.taskset_syscall_fix = 0 restores the throw
		const u32 pc_before = spu.pc;

		spu.gpr[3]._u32[3] = spursTasksetProcessSyscall(spu, spu.gpr[3]._u32[3], spu.gpr[4]._u32[3]);

		if (!thor_taskset_syscall_fix())
		{
			fmt::throw_exception("Broken (TODO)");
		}

		// Resume the previously executing task if the syscall did not cause a context switch
		if (spu.pc == pc_before)
		{
			spursTasksetResumeTask(spu);
		}
	}

	return false;
}

// Resume a task
void spursTasksetResumeTask(spu_thread& spu)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);

	// Restore task context
	spu.gpr[0] = ctxt->savedContextLr;
	spu.gpr[1] = ctxt->savedContextSp;
	for (auto i = 0; i < 48; i++)
	{
		spu.gpr[80 + i] = ctxt->savedContextR80ToR127[i];
	}

	spu.pc = spu.gpr[0]._u32[3];
}

// Start a task
void spursTasksetStartTask(spu_thread& spu, CellSpursTaskArgument& taskArgs)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);
	thor_refresh_taskset_snapshot(spu, ctxt);
	auto taskset = spu._ptr<CellSpursTaskset>(0x2700);

	spu.gpr[2].clear();
	spu.gpr[3] = v128::from64r(taskArgs._u64[0], taskArgs._u64[1]);
	spu.gpr[4]._u64[1] = taskset->args;
	spu.gpr[4]._u64[0] = taskset->spurs.addr();

	// WHAT ARGUMENT DOES THE TASK ACTUALLY RECEIVE?
	//
	// The consumer task on taskset 0x10364100 polls a queue and gets 0x80410911
	// - CELL_SPURS_TASK_ERROR_NULL_POINTER, the code returned when the queue
	// argument is zero - on every iteration, then yields. Measured: yield=9216,
	// waitSig=1, poll=0, and no NOSYS. So the task is not stuck on an
	// unimplemented service, it is holding a null queue pointer.
	//
	// The task reads that pointer from its own global, which it fills at entry
	// from r3/r4. Print both here: if the argument is zero the defect is on the
	// PPU side that publishes it, not anywhere in the SPU dispatch path.
	{
		static std::atomic<u32> s_args{0};

		if (s_args++ < 8)
		{
			cellSpurs.error("Thor TASK ARGS: taskId=%u taskset=0x%x r3=%016llx.%016llx spurs=0x%x tsArgs=%016llx",
				+ctxt->taskId, ctxt->taskset.addr(),
				+taskArgs._u64[0], +taskArgs._u64[1],
				taskset->spurs.addr(), +taskset->args);
		}
	}
	for (auto i = 5; i < 128; i++)
	{
		spu.gpr[i].clear();
	}

	spu.pc = ctxt->savedContextLr.value()._u32[3];
}

// Process a request and update the state of the taskset
s32 spursTasksetProcessRequest(spu_thread& spu, s32 request, u32* taskId, u32* isWaiting)
{
	auto kernelCtxt = spu._ptr<SpursKernelContext>(0x100);
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);

	s32 rc = CELL_OK;
	s32 numNewlyReadyTasks = 0;

	if (thor_taskset_select_atomic())
	{
		spurs_taskset_signal_op committed{};
		u32 beforeRunning = 0;
		u32 beforeWaiting = 0;
		u32 beforeSignalled = 0;

		vm::reservation_op(spu, vm::unsafe_ptr_cast<spurs_taskset_signal_op>(+ctxt->taskset),
			[&](spurs_taskset_signal_op& op)
			{
				v128 waiting = thor_load_task_bitmap(op.waiting);
				v128 running = thor_load_task_bitmap(op.running);
				v128 ready = thor_load_task_bitmap(op.ready);
				v128 pready = thor_load_task_bitmap(op.pending_ready);
				v128 enabled = thor_load_task_bitmap(op.enabled);
				v128 signalled = thor_load_task_bitmap(op.signalled);

				beforeRunning = +op.running[0];
				beforeWaiting = +op.waiting[0];
				beforeSignalled = +op.signalled[0];

				if ((waiting & running) != v128{} || (ready & pready) != v128{} ||
					(gv_andn(enabled, running | ready | pready | signalled | waiting) != v128{}))
				{
					spu_log.error("Invalid taskset state in atomic taskset request");
					spursHalt(spu);
				}

				const v128 newlyReadyTasks = gv_andn(ready, signalled | pready);
				numNewlyReadyTasks = rx::popcnt128(newlyReadyTasks._u);

				v128 signalled0 = signalled & (ready | pready);
				v128 ready0 = signalled | ready | pready;
				v128 readyButNotRunning{};
				const u128 ctxtTaskIdMask = u128{1} << +(~ctxt->taskId & 127);

				switch (request)
				{
				case SPURS_TASKSET_REQUEST_POLL_SIGNAL:
					rc = signalled0._u & ctxtTaskIdMask ? 1 : 0;
					signalled0._u &= ~ctxtTaskIdMask;
					break;
				case SPURS_TASKSET_REQUEST_DESTROY_TASK:
					numNewlyReadyTasks--;
					running._u &= ~ctxtTaskIdMask;
					enabled._u &= ~ctxtTaskIdMask;
					signalled0._u &= ~ctxtTaskIdMask;
					ready0._u &= ~ctxtTaskIdMask;
					break;
				case SPURS_TASKSET_REQUEST_YIELD_TASK:
					running._u &= ~ctxtTaskIdMask;
					waiting._u |= ctxtTaskIdMask;
					break;
				case SPURS_TASKSET_REQUEST_WAIT_SIGNAL:
					if (!(signalled0._u & ctxtTaskIdMask))
					{
						numNewlyReadyTasks--;
						running._u &= ~ctxtTaskIdMask;
						waiting._u |= ctxtTaskIdMask;
						signalled0._u &= ~ctxtTaskIdMask;
						ready0._u &= ~ctxtTaskIdMask;
					}
					break;
				case SPURS_TASKSET_REQUEST_POLL:
					readyButNotRunning = gv_andn(running, ready0);
					if (op.wkl_flag_wait_task < CELL_SPURS_MAX_TASK)
					{
						readyButNotRunning._u &= ~(u128{1} << (~op.wkl_flag_wait_task & 127));
					}
					rc = readyButNotRunning._u ? 1 : 0;
					break;
				case SPURS_TASKSET_REQUEST_WAIT_WKL_FLAG:
					if (op.wkl_flag_wait_task == 0x81)
					{
						op.wkl_flag_wait_task = 0x80;
						rc = 0;
					}
					else if (op.wkl_flag_wait_task == 0x80)
					{
						op.wkl_flag_wait_task = static_cast<u8>(+ctxt->taskId);
						running._u &= ~ctxtTaskIdMask;
						waiting._u |= ctxtTaskIdMask;
						rc = 1;
						numNewlyReadyTasks--;
					}
					else
					{
						rc = CELL_SPURS_TASK_ERROR_BUSY;
					}
					break;
				case SPURS_TASKSET_REQUEST_SELECT_TASK:
				{
					readyButNotRunning = gv_andn(running, ready0);
					if (op.wkl_flag_wait_task < CELL_SPURS_MAX_TASK)
					{
						readyButNotRunning._u &= ~(u128{1} << (~op.wkl_flag_wait_task & 127));
					}

					u8 selectedTaskId;
					for (selectedTaskId = op.last_scheduled_task + 1; selectedTaskId < 128; selectedTaskId++)
					{
						if (readyButNotRunning._u & (u128{1} << (~selectedTaskId & 127)))
						{
							break;
						}
					}

					if (selectedTaskId == 128)
					{
						for (selectedTaskId = 0; selectedTaskId < op.last_scheduled_task + 1; selectedTaskId++)
						{
							if (readyButNotRunning._u & (u128{1} << (~selectedTaskId & 127)))
							{
								break;
							}
						}

						if (selectedTaskId == op.last_scheduled_task + 1)
						{
							selectedTaskId = CELL_SPURS_MAX_TASK;
						}
					}

					*taskId = selectedTaskId;
					if (selectedTaskId != CELL_SPURS_MAX_TASK)
					{
						const u128 selectedTaskIdMask = u128{1} << (~selectedTaskId & 127);
						*isWaiting = waiting._u & selectedTaskIdMask ? 1 : 0;
						op.last_scheduled_task = selectedTaskId;
						running._u |= selectedTaskIdMask;
						waiting._u &= ~selectedTaskIdMask;
					}
					else
					{
						*isWaiting = waiting._u & (u128{1} << 127) ? 1 : 0;
					}
					break;
				}
				case SPURS_TASKSET_REQUEST_RECV_WKL_FLAG:
					if (op.wkl_flag_wait_task < CELL_SPURS_MAX_TASK)
					{
						op.wkl_flag_wait_task = 0x80;
						rc = 1;
						numNewlyReadyTasks++;
					}
					else
					{
						op.wkl_flag_wait_task = 0x81;
						rc = 0;
					}
					break;
				default:
					spu_log.error("Unknown atomic taskset request");
					spursHalt(spu);
					break;
				}

				thor_store_task_bitmap(op.waiting, waiting);
				thor_store_task_bitmap(op.running, running);
				thor_store_task_bitmap(op.ready, ready0);
				thor_store_task_bitmap(op.pending_ready, v128{});
				thor_store_task_bitmap(op.enabled, enabled);
				thor_store_task_bitmap(op.signalled, signalled0);
				std::memcpy(&committed, &op, sizeof(committed));
				return true;
			});

		// Keep the local-store snapshot equal to the cache line that won PUTLLC.
		std::memcpy(spu._ptr<void>(0x2700), &committed, sizeof(committed));

		if (request == SPURS_TASKSET_REQUEST_SELECT_TASK)
		{
			static std::atomic<u32> s_atomic_selects{0};
			if (const u32 n = s_atomic_selects++; n < 32)
			{
				cellSpurs.error("Thor TASKSET SELECT ATOMIC #%u: taskset=0x%x taskId=%u isWaiting=%u "
					"before{run=%08x wait=%08x sig=%08x} after{run=%08x wait=%08x sig=%08x} spu=%u",
					n, ctxt->taskset.addr(), *taskId, *isWaiting,
					beforeRunning, beforeWaiting, beforeSignalled,
					+committed.running[0], +committed.waiting[0], +committed.signalled[0], +ctxt->spuNum);
			}

			// Keep this quota independent of the general startup census. Workload
			// 0 owns the edge-Zlib taskset in BLUS30357, and its second wake occurs
			// after the general 32-line quota is exhausted.
			if (thor_edge_task_census() && kernelCtxt->wklCurrentId == 0)
			{
				static std::atomic<u32> s_edge_task_selects{0};
				const u32 n = s_edge_task_selects++;

				if (n < 32)
				{
					cellSpurs.error("Thor EDGE TASK SELECT #%u: taskset=0x%x taskId=%u isWaiting=%u "
						"before{run=%08x wait=%08x sig=%08x} after{run=%08x wait=%08x sig=%08x} "
						"ready=%08x pready=%08x enabled=%08x readyCount=%u spu=%u",
						n, ctxt->taskset.addr(), *taskId, *isWaiting,
						beforeRunning, beforeWaiting, beforeSignalled,
						+committed.running[0], +committed.waiting[0], +committed.signalled[0],
						+committed.ready[0], +committed.pending_ready[0], +committed.enabled[0],
						+kernelCtxt->spurs->readyCount(kernelCtxt->wklCurrentId).load(), +ctxt->spuNum);
				}
			}
		}

		if (numNewlyReadyTasks)
		{
			auto spurs = kernelCtxt->spurs;
			vm::light_op(spurs->readyCount(kernelCtxt->wklCurrentId), [&](atomic_t<u8>& val)
				{
					val.fetch_op([&](u8& value)
						{
							const s32 next = value + numNewlyReadyTasks;
							value = static_cast<u8>(std::clamp<s32>(next, 0, 0xFF));
						});
				});
		}

		return rc;
	}

	// vm::reservation_op(vm::cast(ctxt->taskset.addr()), 128, [&]()
	{
		auto taskset = ctxt->taskset;
		v128 waiting = vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, waiting));
		v128 running = vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, running));
		v128 ready = vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, ready));
		v128 pready = vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, pending_ready));
		v128 enabled = vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, enabled));
		v128 signalled = vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, signalled));

		// Verify taskset state is valid
		if ((waiting & running) != v128{} || (ready & pready) != v128{} ||
			(gv_andn(enabled, running | ready | pready | signalled | waiting) != v128{}))
		{
			// THE TASKSET NOW DISPATCHES - `wid=0 addr=0x200` - and dies here.
			// Print the address it is reading and every bitmap the check uses, so
			// "invalid" can be told apart from "reading the wrong memory". The PPU
			// created this taskset at 0x10364100; if tasksetAddr is not that, the
			// argument plumbed through dispatch is wrong, not the state.
			{
				static std::atomic<u32> s_bad_state{0};

				if (thor_hle_once(s_bad_state, 0))
				{
					cellSpurs.error("Thor INVALID TASKSET STATE: tasksetAddr=0x%x wait=%016llx%016llx run=%016llx%016llx "
									"ready=%016llx%016llx pready=%016llx%016llx en=%016llx%016llx sig=%016llx%016llx",
						ctxt->taskset.addr(),
						waiting._u64[0], waiting._u64[1], running._u64[0], running._u64[1],
						ready._u64[0], ready._u64[1], pready._u64[0], pready._u64[1],
						enabled._u64[0], enabled._u64[1], signalled._u64[0], signalled._u64[1]);
				}
			}

			spu_log.error("Invalid taskset state");
			spursHalt(spu);
		}

		// Find the number of tasks that have become ready since the last iteration
		{
			v128 newlyReadyTasks = gv_andn(ready, signalled | pready);

			numNewlyReadyTasks = rx::popcnt128(newlyReadyTasks._u);
		}

		v128 readyButNotRunning;
		u8 selectedTaskId;
		v128 signalled0 = (signalled & (ready | pready));
		v128 ready0 = (signalled | ready | pready);

		u128 ctxtTaskIdMask = u128{1} << +(~ctxt->taskId & 127);

		switch (request)
		{
		case SPURS_TASKSET_REQUEST_POLL_SIGNAL:
		{
			rc = signalled0._u & ctxtTaskIdMask ? 1 : 0;
			signalled0._u &= ~ctxtTaskIdMask;
			break;
		}
		case SPURS_TASKSET_REQUEST_DESTROY_TASK:
		{
			numNewlyReadyTasks--;
			running._u &= ~ctxtTaskIdMask;
			enabled._u &= ~ctxtTaskIdMask;
			signalled0._u &= ~ctxtTaskIdMask;
			ready0._u &= ~ctxtTaskIdMask;
			break;
		}
		case SPURS_TASKSET_REQUEST_YIELD_TASK:
		{
			running._u &= ~ctxtTaskIdMask;
			waiting._u |= ctxtTaskIdMask;
			break;
		}
		case SPURS_TASKSET_REQUEST_WAIT_SIGNAL:
		{
			if (!(signalled0._u & ctxtTaskIdMask))
			{
				numNewlyReadyTasks--;
				running._u &= ~ctxtTaskIdMask;
				waiting._u |= ctxtTaskIdMask;
				signalled0._u &= ~ctxtTaskIdMask;
				ready0._u &= ~ctxtTaskIdMask;
			}
			break;
		}
		case SPURS_TASKSET_REQUEST_POLL:
		{
			readyButNotRunning = gv_andn(running, ready0);
			if (taskset->wkl_flag_wait_task < CELL_SPURS_MAX_TASK)
			{
				readyButNotRunning._u &= ~(u128{1} << (~taskset->wkl_flag_wait_task & 127));
			}

			rc = readyButNotRunning._u ? 1 : 0;
			break;
		}
		case SPURS_TASKSET_REQUEST_WAIT_WKL_FLAG:
		{
			if (taskset->wkl_flag_wait_task == 0x81)
			{
				// A workload flag is already pending so consume it
				taskset->wkl_flag_wait_task = 0x80;
				rc = 0;
			}
			else if (taskset->wkl_flag_wait_task == 0x80)
			{
				// No tasks are waiting for the workload flag. Mark this task as waiting for the workload flag.
				taskset->wkl_flag_wait_task = ctxt->taskId;
				running._u &= ~ctxtTaskIdMask;
				waiting._u |= ctxtTaskIdMask;
				rc = 1;
				numNewlyReadyTasks--;
			}
			else
			{
				// Another task is already waiting for the workload signal
				rc = CELL_SPURS_TASK_ERROR_BUSY;
			}
			break;
		}
		case SPURS_TASKSET_REQUEST_SELECT_TASK:
		{
			readyButNotRunning = gv_andn(running, ready0);

			// DOES SELECT_TASK ACTUALLY FIND THE TASK?
			//
			// The task reads waiting=80000000 signalled=80000000 from the PPU
			// side, and ready0 = signalled|ready|pready, so it SHOULD be
			// selectable. But head freezes and the task never runs, and
			// spursTasksetDispatch exits the taskset the moment SELECT_TASK
			// returns >= CELL_SPURS_MAX_TASK. The bit convention differs between
			// the two sides - PPU uses values[id/32] |= (1u<<31)>>(id%32), this
			// uses u128{1} << (~id & 127) - so print the raw words rather than
			// assume they agree.
			if (thor_hle_spurs_diagnostics())
			{
				static std::atomic<u32> s_sel{0};

				if (const u32 sn = s_sel++; (sn & 0x0F) == 0)
				{
					cellSpurs.error("Thor SELECT_TASK #%u: ready0=%016llx%016llx running=%016llx%016llx rbnr=%016llx%016llx last=%u",
						sn, ready0._u64[0], ready0._u64[1], running._u64[0], running._u64[1],
						readyButNotRunning._u64[0], readyButNotRunning._u64[1],
						+taskset->last_scheduled_task);
				}
			}
			if (taskset->wkl_flag_wait_task < CELL_SPURS_MAX_TASK)
			{
				readyButNotRunning._u &= ~(u128{1} << (~taskset->wkl_flag_wait_task & 127));
			}

			// Select a task from the readyButNotRunning set to run. Start from the task after the last scheduled task to ensure fairness.
			for (selectedTaskId = taskset->last_scheduled_task + 1; selectedTaskId < 128; selectedTaskId++)
			{
				if (readyButNotRunning._u & (u128{1} << (~selectedTaskId & 127)))
				{
					break;
				}
			}

			if (selectedTaskId == 128)
			{
				for (selectedTaskId = 0; selectedTaskId < taskset->last_scheduled_task + 1; selectedTaskId++)
				{
					if (readyButNotRunning._u & (u128{1} << (~selectedTaskId & 127)))
					{
						break;
					}
				}

				if (selectedTaskId == taskset->last_scheduled_task + 1)
				{
					selectedTaskId = CELL_SPURS_MAX_TASK;
				}
			}

			*taskId = selectedTaskId;

			if (selectedTaskId != CELL_SPURS_MAX_TASK)
			{
				const u128 selectedTaskIdMask = u128{1} << (~selectedTaskId & 127);

				*isWaiting = waiting._u & selectedTaskIdMask ? 1 : 0;
				taskset->last_scheduled_task = selectedTaskId;
				running._u |= selectedTaskIdMask;
				waiting._u &= ~selectedTaskIdMask;
			}
			else
			{
				*isWaiting = waiting._u & (u128{1} << 127) ? 1 : 0;
			}

			break;
		}
		case SPURS_TASKSET_REQUEST_RECV_WKL_FLAG:
		{
			if (taskset->wkl_flag_wait_task < CELL_SPURS_MAX_TASK)
			{
				// There is a task waiting for the workload flag
				taskset->wkl_flag_wait_task = 0x80;
				rc = 1;
				numNewlyReadyTasks++;
			}
			else
			{
				// No tasks are waiting for the workload flag
				taskset->wkl_flag_wait_task = 0x81;
				rc = 0;
			}
			break;
		}
		default:
			spu_log.error("Unknown taskset request");
			spursHalt(spu);
		}

		vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, waiting)) = waiting;
		vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, running)) = running;
		// See thor_taskset_writeback_fix: ready0/signalled0 are the UPDATED words.
		vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, ready)) =
			thor_taskset_writeback_fix() ? ready0 : ready;
		vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, pending_ready)) = v128{};
		vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, enabled)) = enabled;
		if (thor_taskset_writeback_fix() && thor_signal_atomic_fix())
		{
			// Consume only what this pass consumed; see thor_signal_atomic_fix.
			const v128 consumed = gv_andn(signalled0, signalled);   // signalled & ~signalled0

			if (consumed._u)
			{
				vm::reservation_op(spu, vm::unsafe_ptr_cast<spurs_taskset_signal_op>(+ctxt->taskset),
					[&](spurs_taskset_signal_op& op)
					{
						v128& mem = reinterpret_cast<v128&>(op.signalled[0]);
						mem = gv_andn(consumed, mem);   // mem & ~consumed
						return true;
					});
			}
		}
		else
		{
			vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, signalled)) =
				thor_taskset_writeback_fix() ? signalled0 : signalled;
		}

		std::memcpy(spu._ptr<void>(0x2700), spu._ptr<void>(0x100), 128); // Copy data
	} //);

	// Increment the ready count of the workload by the number of tasks that have become ready
	if (numNewlyReadyTasks)
	{
		auto spurs = kernelCtxt->spurs;

		vm::light_op(spurs->readyCount(kernelCtxt->wklCurrentId), [&](atomic_t<u8>& val)
			{
				val.fetch_op([&](u8& val)
					{
						const s32 _new = val + numNewlyReadyTasks;
						val = static_cast<u8>(std::clamp<s32>(_new, 0, 0xFF));
					});
			});
	}

	return rc;
}

// Process pollStatus received from the SPURS kernel
void spursTasksetProcessPollStatus(spu_thread& spu, u32 pollStatus)
{
	if (pollStatus & CELL_SPURS_MODULE_POLL_STATUS_FLAG)
	{
		spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_RECV_WKL_FLAG, nullptr, nullptr);
	}
}

// Check execution rights
bool spursTasksetPollStatus(spu_thread& spu)
{
	u32 pollStatus;

	if (cellSpursModulePollStatus(spu, &pollStatus))
	{
		return true;
	}

	spursTasksetProcessPollStatus(spu, pollStatus);
	return false;
}

// Exit the Taskset PM
void spursTasksetExit(spu_thread& spu)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);

	// Trace - STOP
	CellSpursTracePacket pkt{};
	pkt.header.tag = 0x54; // Its not clear what this tag means exactly but it seems similar to CELL_SPURS_TRACE_TAG_STOP
	pkt.data.stop = SPURS_GUID_TASKSET_PM;
	cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

	// Not sure why this check exists. Perhaps to check for memory corruption.
	if (memcmp(ctxt->moduleId, "SPURSTASK MODULE", 16) != 0)
	{
		spu_log.error("spursTasksetExit(): memory corruption");
		spursHalt(spu);
	}

	cellSpursModuleExit(spu);
}

// Invoked when a task exits
void spursTasksetOnTaskExit(spu_thread& spu, u64 addr, u32 taskId, s32 exitCode, u64 args)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);

	std::memcpy(spu._ptr<void>(0x10000), vm::base(addr & -0x80), (addr & 0x7F) << 11);

	spu.gpr[3]._u64[1] = ctxt->taskset.addr();
	spu.gpr[4]._u32[3] = taskId;
	spu.gpr[5]._u32[3] = exitCode;
	spu.gpr[6]._u64[1] = args;
	spu.fast_call(0x10000);
}

// Save the context of a task
s32 spursTasketSaveTaskContext(spu_thread& spu)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);
	auto taskInfo = spu._ptr<CellSpursTaskset::TaskInfo>(0x2780);

	// spursDmaWaitForCompletion(spu, 0xFFFFFFFF);

	if (taskInfo->context_save_storage_and_alloc_ls_blocks == 0u)
	{
		static std::atomic<u32> s_e0{0};

		if (const u32 n = s_e0++; n < 4 || (n & 0xFFF) == 0)
		{
			cellSpurs.error("Thor SAVECTX FAIL #%u: no context_save_storage (taskId=%u)", n, +ctxt->taskId);
		}

		return CELL_SPURS_TASK_ERROR_STAT;
	}

	u32 allocLsBlocks = static_cast<u32>(taskInfo->context_save_storage_and_alloc_ls_blocks & 0x7F);
	v128 ls_pattern = v128::from64r(taskInfo->ls_pattern._u64[0], taskInfo->ls_pattern._u64[1]);

	const u32 lsBlocks = rx::popcnt128(ls_pattern._u);

	if (lsBlocks > allocLsBlocks)
	{
		static std::atomic<u32> s_e1{0};

		if (const u32 n = s_e1++; n < 4 || (n & 0xFFF) == 0)
		{
			cellSpurs.error("Thor SAVECTX FAIL #%u: lsBlocks=%u > allocLsBlocks=%u (taskId=%u)",
				n, lsBlocks, allocLsBlocks, +ctxt->taskId);
		}

		return CELL_SPURS_TASK_ERROR_STAT;
	}

	// Make sure the stack is area is specified in the ls pattern
	for (auto i = (ctxt->savedContextSp.value()._u32[3]) >> 11; i < 128; i++)
	{
		if (!(ls_pattern._u & (u128{1} << (i ^ 127))))
		{
			static std::atomic<u32> s_e2{0};

			if (const u32 n = s_e2++; n < 4 || (n & 0xFFF) == 0)
			{
				cellSpurs.error("Thor SAVECTX FAIL #%u: stack block %u not in ls_pattern "
					"(sp=0x%05x taskId=%u source=%016llx%016llx vector=%016llx%016llx bit=%u alloc=%u)",
					n, i, ctxt->savedContextSp.value()._u32[3], +ctxt->taskId,
					+taskInfo->ls_pattern._u64[0], +taskInfo->ls_pattern._u64[1],
					ls_pattern._u64[1], ls_pattern._u64[0],
					static_cast<u32>(i ^ 127), allocLsBlocks);
			}

			return CELL_SPURS_TASK_ERROR_STAT;
		}
	}

	// Get the processor context
	v128 r;
	spu.fpscr.Read(r);
	ctxt->savedContextFpscr = r;
	ctxt->savedSpuWriteEventMask = static_cast<u32>(spu.get_ch_value(SPU_RdEventMask));
	ctxt->savedWriteTagGroupQueryMask = static_cast<u32>(spu.get_ch_value(MFC_RdTagMask));

	// Store the processor context
	const u32 contextSaveStorage = vm::cast(taskInfo->context_save_storage_and_alloc_ls_blocks & -0x80);
	std::memcpy(vm::base(contextSaveStorage), spu._ptr<void>(0x2C80), 0x380);

	// Save the selected LS blocks in a compact array after the 0x400-byte
	// register area. The firmware advances the destination by the size of each
	// selected run. The LS block number only selects the source address.
	//
	// Do not use (i - 6) for the destination offset. Sparse patterns would then
	// write beyond the context allocation. For example, one selected stack block
	// near the end of LS still has only one 0x800-byte save slot.
	u32 savedLsBlock = 0;
	for (auto i = 6; i < 128; i++)
	{
		if (ls_pattern._u & (u128{1} << (i ^ 127)))
		{
			// TODO: Combine DMA requests for consecutive blocks into a single request
			std::memcpy(vm::base(contextSaveStorage + 0x400 + (savedLsBlock << 11)), spu._ptr<void>(CELL_SPURS_TASK_TOP + ((i - 6) << 11)), 0x800);
			savedLsBlock++;
		}
	}

	// spursDmaWaitForCompletion(spu, 1 << ctxt->dmaTagId);
	// DOES THE SAVE EVER FAIL? Callers test `rc == CELL_OK` and silently do
	// nothing otherwise - a failing save turns a yield into a no-op and a
	// wait into a lost task, with no log line anywhere. Report the error
	// paths; CELL_OK is counted but not printed.
	return CELL_OK;
}

// Taskset dispatcher
void spursTasksetDispatch(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);
	thor_refresh_taskset_snapshot(spu, ctxt);
	const auto taskset = spu._ptr<CellSpursTaskset>(0x2700);

	u32 taskId;
	u32 isWaiting;
	spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_SELECT_TASK, &taskId, &isWaiting);

	// WHAT DOES DISPATCH DO WITH THE RESULT? If taskId >= 128 the taskset EXITS
	// immediately, which would explain a consumer that never resumes even though
	// SELECT_TASK can see it. Print both the id and the waiting flag.
	if (thor_hle_spurs_diagnostics())
	{
		static std::atomic<u32> s_disp{0};

		// EVERY-16th SAMPLING CANNOT ANSWER "WAS THIS TASK EVER STARTED?".
		//
		// isWaiting=0 is the START path - it loads the task ELF and enters it.
		// isWaiting=1 is RESUME, which restores a context save area. A task that
		// is only ever resumed has never had its code loaded, and would execute
		// whatever is left in local store.
		//
		// A sampled probe read 724 isWaiting=1 against 1 isWaiting=0 and that was
		// over-read as "never started" - the first dispatch for a taskset can
		// easily fall in the 15 of 16 that are not printed. So log EVERY start
		// unconditionally, and the first few dispatches per taskset, and count
		// starts per taskset. Then the question has an answer instead of an
		// inference.
		const u32 dn = s_disp++;

		if (isWaiting == 0)
		{
			static std::atomic<u32> s_starts{0};
			cellSpurs.error("Thor TASK START #%u (dispatch #%u): taskId=%u taskset=0x%x",
				s_starts++, dn, taskId, ctxt->taskset.addr());
		}
		else if (dn < 8 || (dn & 0x3F) == 0)
		{
			// PRINT THE TASKSET BITMAPS, NOT JUST THE ID.
			//
			// waitSig=1 for the whole run means the task on taskset 0x101b4e80
			// called WAIT_SIGNAL once and never came back. Whether it is still
			// parked, and whether anything ever set its signalled bit, is in these
			// words - and nothing else prints them for a taskset that takes no
			// queue pushes.
			{
				const auto rd = [&](u32 off) { return +vm::_ref<be_t<u32>>(ctxt->taskset.addr() + off); };

				cellSpurs.error("Thor TSSTATE #%u: taskset=0x%x taskId=%u isWaiting=%u | running=%08x ready=%08x pready=%08x waiting=%08x enabled=%08x signalled=%08x",
					dn, ctxt->taskset.addr(), taskId, isWaiting,
					rd(OFFSET_OF(CellSpursTaskset, running)),
					rd(OFFSET_OF(CellSpursTaskset, ready)),
					rd(OFFSET_OF(CellSpursTaskset, pending_ready)),
					rd(OFFSET_OF(CellSpursTaskset, waiting)),
					rd(OFFSET_OF(CellSpursTaskset, enabled)),
					rd(OFFSET_OF(CellSpursTaskset, signalled)));
			}

			cellSpurs.error("Thor DISPATCH #%u: selected taskId=%u isWaiting=%u (exit if >= %u) taskset=0x%x",
				dn, taskId, isWaiting, +CELL_SPURS_MAX_TASK, ctxt->taskset.addr());
		}
	}

	// RELEASE THE CONTENTION SLOT WHEN THERE IS NOTHING TO RUN.
	//
	// Measured: 182 of 183 sampled dispatches selected taskId=128 - no runnable
	// task - and the SPU then exits and immediately re-enters the same workload.
	// The selector only releases a slot when the SPU switches to a DIFFERENT
	// workload, so an SPU in that loop holds the slot indefinitely. With
	// maxContention = 1 on the queue's taskset, one SPU spinning there locks every
	// other SPU out, and the boot never drains - which is the 2-in-3 failure.
	//
	// Release only an idle slot. The running bitmap counts tasks that another SPU
	// still executes. The shared count must not become less than that count.
	// This distinction stops an idle SPU from opening a maxContention = 1 gate
	// while another SPU still executes the only task.
	//
	//   debug.rpcsx.thor.release_idle_taskset = 0 disables
	if (taskId >= CELL_SPURS_MAX_TASK && thor_release_idle_taskset())
	{
		const auto kctxt = spu._ptr<SpursKernelContext>(0x100);
		const u32 held = kctxt->wklCurrentId;

		if (held < CELL_SPURS_MAX_WORKLOAD && kctxt->wklLocContention[held])
		{
			const u8 readyCount = kctxt->spurs->readyCount(held).load();
			const v128 runningTasks = vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, running));
			const u8 runningTaskCount = static_cast<u8>(std::min<u32>(rx::popcnt128(runningTasks._u), CELL_SPURS_MAX_SPU));

			// A nonzero ready count with no selectable task caused the measured
			// workload 7 redispatch storm. Keep this exceptional probe bounded.
			if (readyCount)
			{
				static std::atomic<u32> s_idle_ready{0};
				const u32 n = s_idle_ready++;

				if (n < 16 || (n & 0xFFFF) == 0)
				{
					const auto rd = [&](u32 off)
					{
						return +vm::_ref<be_t<u32>>(ctxt->taskset.addr() + off);
					};

					cellSpurs.error("Thor TASKSET IDLE-READY #%u: taskset=0x%x wid=%u readyCount=%u runningTaskCount=%u "
						"contention{shared=%u pending=%u local=%u localPending=%u} "
						"state{run=%08x ready=%08x pready=%08x wait=%08x enabled=%08x sig=%08x} spu=%u",
						n, ctxt->taskset.addr(), held, readyCount, runningTaskCount,
						+kctxt->spurs->wklCurrentContention[held], +kctxt->spurs->wklPendingContention[held],
						+kctxt->wklLocContention[held], +kctxt->wklLocPendingContention[held],
						rd(OFFSET_OF(CellSpursTaskset, running)), rd(OFFSET_OF(CellSpursTaskset, ready)),
						rd(OFFSET_OF(CellSpursTaskset, pending_ready)), rd(OFFSET_OF(CellSpursTaskset, waiting)),
						rd(OFFSET_OF(CellSpursTaskset, enabled)), rd(OFFSET_OF(CellSpursTaskset, signalled)), +ctxt->spuNum);
				}
			}

			vm::_ref<atomic_t<u8>>(kctxt->spurs.addr() + OFFSET_OF(CellSpurs, wklCurrentContention) + held)
				.atomic_op([runningTaskCount](u8& current)
				{
					if (current > runningTaskCount)
					{
						current--;
					}
				});
			kctxt->wklLocContention[held] = 0;
			thor_release_wkl(held, kctxt->spuNum);
		}
	}

	if (taskId >= CELL_SPURS_MAX_TASK)
	{
		spursTasksetExit(spu);
		return;
	}

	ctxt->taskId = taskId;

	// DMA in the task info for the selected task
	const auto taskInfo = spu._ptr<CellSpursTaskset::TaskInfo>(0x2780);
	std::memcpy(taskInfo, &ctxt->taskset->task_info[taskId], sizeof(CellSpursTaskset::TaskInfo));
	auto elfAddr = taskInfo->elf.addr().value();
	taskInfo->elf.set(taskInfo->elf.addr() & 0xFFFFFFFFFFFFFFF8);

	// Trace - Task: Incident=dispatch
	CellSpursTracePacket pkt{};
	pkt.header.tag = CELL_SPURS_TRACE_TAG_TASK;
	pkt.data.task.incident = CELL_SPURS_TRACE_TASK_DISPATCH;
	pkt.data.task.taskId = taskId;
	cellSpursModulePutTrace(&pkt, CELL_SPURS_KERNEL_DMA_TAG_ID);

	if (isWaiting == 0)
	{
		// If we reach here it means that the task is being started and not being resumed
		// GHIDRA: THE REAL MODULE STOPS AT 0x3d000, NOT 0x40000.
		//
		// The genuine taskset policy module clears local store with an unrolled
		// store run entered by a computed branch, and its bounds are explicit:
		//
		//     000018b0: il   r38,0x3000     ; start - matches CELL_SPURS_TASK_TOP
		//     000018b8: ila  r39,0x3d000    ; END - not 0x40000
		//     000018c8: ai   r39,r39,-0x80
		//     000018cc: brsl r5,0x000018d0  ; compute entry into the unrolled run
		//     000018ec: bi   r5
		//
		// CELL_SPURS_TASK_BOTTOM is 0x40000 (LS_BOTTOM), so this memset zeroes an
		// extra 0x3000 bytes - 12 KB at the very top of local store - that the
		// hardware deliberately leaves alone, immediately before the task's ELF is
		// loaded and entered. The top of local store is where a stack lives; wiping
		// it out from under the kernel/policy module is consistent with the
		// observed failure, where the task runs and then executes a conditional
		// HALT on its own assertion.
		//
		// Only the START path is changed. The resume path below is gated on
		// taskset->enable_clear_ls and is left exactly as it shipped.
		//
		//   debug.rpcsx.thor.task_ls_clear_fix = 0 restores the 0x40000 bound
		std::memset(spu._ptr<void>(CELL_SPURS_TASK_TOP), 0,
			(thor_task_ls_clear_fix() ? 0x3d000u : u32{CELL_SPURS_TASK_BOTTOM}) - CELL_SPURS_TASK_TOP);
		ctxt->guidAddr = CELL_SPURS_TASK_TOP;

		u32 entryPoint;
		u32 lowestLoadAddr;
		if (spursTasksetLoadElf(spu, &entryPoint, &lowestLoadAddr, taskInfo->elf.addr(), false) != CELL_OK)
		{
			spu_log.error("spursTaskLoadElf() failed");
			spursHalt(spu);
		}

		// spursDmaWaitForCompletion(spu, 1 << ctxt->dmaTagId);

		ctxt->savedContextLr = v128::from32r(entryPoint);
		ctxt->guidAddr = lowestLoadAddr;
		ctxt->tasksetMgmtAddr = 0x2700;
		ctxt->x2FC0 = 0;
		ctxt->taskExitCode = isWaiting;
		ctxt->x2FD4 = elfAddr & 5; // TODO: Figure this out

		if ((elfAddr & 5) == 1)
		{
			std::memcpy(spu._ptr<void>(0x2FC0), &vm::_ptr<CellSpursTaskset2>(vm::cast(ctxt->taskset.addr()))->task_exit_code[taskId], 0x10);
		}

		// Trace - GUID
		pkt = {};
		pkt.header.tag = CELL_SPURS_TRACE_TAG_GUID;
		pkt.data.guid = 0; // TODO: Put GUID of taskId here
		cellSpursModulePutTrace(&pkt, 0x1F);

		if (elfAddr & 2)
		{
			// TODO: Figure this out
			spu_runtime::g_escape(&spu);
		}

		spursTasksetStartTask(spu, taskInfo->args);
	}
	else
	{
		if (taskset->enable_clear_ls)
		{
			std::memset(spu._ptr<void>(CELL_SPURS_TASK_TOP), 0, CELL_SPURS_TASK_BOTTOM - CELL_SPURS_TASK_TOP);
		}

		// If the entire LS is saved then there is no need to load the ELF as it will be be saved in the context save area as well
		v128 ls_pattern = v128::from64r(taskInfo->ls_pattern._u64[0], taskInfo->ls_pattern._u64[1]);
		if (ls_pattern != v128::from64r(0x03FFFFFFFFFFFFFFull, 0xFFFFFFFFFFFFFFFFull))
		{
			// Load the ELF
			u32 entryPoint;
			if (spursTasksetLoadElf(spu, &entryPoint, nullptr, taskInfo->elf.addr(), true) != CELL_OK)
			{
				spu_log.error("spursTasksetLoadElf() failed");
				spursHalt(spu);
			}
		}

		// Load saved context from main memory to LS
		const u32 contextSaveStorage = vm::cast(taskInfo->context_save_storage_and_alloc_ls_blocks & -0x80);

		// IS THE CONTEXT SAVE AREA EVEN VALID?
		//
		// The task is resumed hundreds of thousands of times and blocks again
		// immediately every time. If this address or ls_pattern is wrong the resume
		// restores garbage, the task hits its wait again at once, and the dispatch
		// loop spins exactly as measured. Check the address is mapped before
		// trusting anything else about the resume path.
		{
			static std::atomic<u64> s_res{0};

			if (const u64 n = ++s_res; n <= 4 || (n % 65536) == 0)
			{
				const bool ok = contextSaveStorage && vm::check_addr(contextSaveStorage, vm::page_readable, 0x380);

				cellSpurs.error("Thor RESUME #%llu: task=%u ctxSave=0x%08x mapped=%u raw=0x%llx "
					"lsPattern=%016llx%016llx elf=0x%x",
					n, taskId, contextSaveStorage, ok ? 1u : 0u,
					+taskInfo->context_save_storage_and_alloc_ls_blocks,
					ls_pattern._u64[0], ls_pattern._u64[1], taskInfo->elf.addr());
			}
		}
		std::memcpy(spu._ptr<void>(0x2C80), vm::base(contextSaveStorage), 0x380);
		u32 savedLsBlock = 0;
		for (auto i = 6; i < 128; i++)
		{
			if (ls_pattern._u & (u128{1} << (i ^ 127)))
			{
				// TODO: Combine DMA requests for consecutive blocks into a single request
				std::memcpy(spu._ptr<void>(CELL_SPURS_TASK_TOP + ((i - 6) << 11)), vm::base(contextSaveStorage + 0x400 + (savedLsBlock << 11)), 0x800);
				savedLsBlock++;
			}
		}

		// spursDmaWaitForCompletion(spu, 1 << ctxt->dmaTagId);

		// Restore saved registers
		spu.fpscr.Write(ctxt->savedContextFpscr.value());
		spu.set_ch_value(MFC_WrTagMask, ctxt->savedWriteTagGroupQueryMask);
		spu.set_ch_value(SPU_WrEventMask, ctxt->savedSpuWriteEventMask);

		// Trace - GUID
		pkt = {};
		pkt.header.tag = CELL_SPURS_TRACE_TAG_GUID;
		pkt.data.guid = 0; // TODO: Put GUID of taskId here
		cellSpursModulePutTrace(&pkt, 0x1F);

		if (elfAddr & 2)
		{
			// TODO: Figure this out
			spu_runtime::g_escape(&spu);
		}

		spu.gpr[3].clear();
		spursTasksetResumeTask(spu);
	}
}

// Process a syscall request
s32 spursTasksetProcessSyscall(spu_thread& spu, u32 syscallNum, u32 args)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);

	// SAME STALE-SNAPSHOT DEFECT as spursTasksetStartTask and
	// spursTasksetDispatch had. `spu._ptr<CellSpursTaskset>(0x2700)` reads
	// tempAreaTaskset, which nothing fills, so every taskset field here is
	// whatever was last left in that scratch.
	//
	// It matters on the EXIT path specifically: that case reads `taskset->x78`
	// to find the task-exit callback, and this is the COMPLETION path the title
	// is waiting on. Measured symptom: the FlipPump thread spins on
	// cellSpursWakeUp roughly every 265 us forever while six SPUs stay busy at
	// pc=0x00a00 - the renderer waiting for a task completion that never arrives.
	thor_refresh_taskset_snapshot(spu, ctxt);

	auto taskset = spu._ptr<CellSpursTaskset>(0x2700);

	// If the 0x10 bit is set in syscallNum then its the 2nd version of the
	// syscall (e.g. cellSpursYield2 instead of cellSpursYield) and so don't wait
	// for DMA completion
	if ((syscallNum & 0x10) == 0)
	{
		// See thor_syscall_dma_wait: the real module drains all DMA here
		// (wrch ch22/-1, wrch ch23/2, rdch ch24) before dispatching.
		if (thor_syscall_dma_wait())
		{
			spursDmaWaitForCompletion(spu, 0xFFFFFFFF);
		}
	}

	// WHICH SYSCALLS DOES THE TASK ACTUALLY ISSUE?
	//
	// The renderer stalls with FlipPump spinning on cellSpursWakeUp, which means a
	// completion never arrives. Before guessing at the completion path again,
	// measure what the task asks for. One line per distinct syscall number, at
	// warning level so it survives the default filter - trace does not, and that
	// already caused one misreading this session.
	if (thor_hle_spurs_diagnostics())
	{
		// COUNT, DO NOT ONE-SHOT.
		//
		// The one-shot version proved WHICH syscalls the task issues (#2
		// WAIT_SIGNAL then #1 YIELD) but not HOW OFTEN, and that is now the
		// question. A queue push only re-dispatches the workload when the task's
		// `waiting` bit is set, and only 2 workload signals fired all run. So:
		//
		//   many WAIT_SIGNALs against 2 signals -> the loss is PPU-side
		//   exactly 2 WAIT_SIGNALs              -> the task leaves its consume loop
		//
		// Printed every 64 calls so a hot path stays cheap.
		static std::array<std::atomic<u32>, 16> s_seen{};
		static std::atomic<u32> s_total{0};

		const u32 which = syscallNum & 0x0F;

		// WHERE IN THE TASK IS THE YIELD LOOP?
		//
		// The census settled that the task issues ONLY yield - 17,024 of them,
		// zero of anything else, zero NOSYS - while the ring sits full at
		// used=256 with head frozen. So the task is polling some address and not
		// seeing it change. To find what it polls, first find the loop: on SPU
		// the link register is r0, so at the syscall entry r0 holds the address
		// in the TASK that called yield.
		//
		// Distinct call sites, not a count - a poll loop has one or two, and
		// knowing them turns "somewhere in the task" into an address to
		// disassemble against the task ELF (SPU:BE:128 in Ghidra).
		{
			static std::atomic<u32> s_sites[8]{};
			static std::atomic<u32> s_nsites{0};

			const u32 lr = spu.gpr[0]._u32[3];

			// WHY IS THE POP FAILING?
			//
			// Disassembly of the task (task_yield_loop.disasm.txt) shows the loop at
			// 0xf3c0 is a backoff-retry, not a drain:
			//
			//   0f3b4: brsl lr,0x13c68   ; the pop
			//   0f3b8: lr   r80,r3       ; r80 = its RETURN CODE
			//   0f3bc: brz  r3,0xf238    ; 0 = success -> drain again
			//   0f3d0..0f3dc            ; 2400x rdch ch8, a timed backoff
			//   0f3e0: brsl lr,0x13b90   ; YIELD  (returns to 0xf3e4)
			//   0f3e8: ceq  r41,r80,r82  ; same code as last time?
			//   0f3f4: brnz r41,0xf3a0   ; yes -> retry
			//
			// So at THIS syscall r80 holds the code the pop just returned, and r82
			// the one it expects to keep seeing. Only 338 of ~17000 iterations touch
			// the queue, so most fail an early check inside 0x13c68 - 0x80410910
			// (arg2 not 16-byte aligned) or 0x80410902 (arg3 >= 32) - before its
			// GETLLAR. Print the code rather than guess which.
			if (lr == 0xf3e4 || lr == 0xf3a0)
			{
				static std::atomic<u32> s_rc{0};

				if (const u32 rn = s_rc++; rn < 8 || (rn & 0xFFF) == 0)
				{
					cellSpurs.error("Thor POPRC #%u: lr=0x%05x r80=0x%08x r82=0x%08x "
						"r3=0x%08x r4=0x%08x r5=0x%08x r86=0x%08x",
						rn, lr, spu.gpr[80]._u32[3], spu.gpr[82]._u32[3],
						spu.gpr[3]._u32[3], spu.gpr[4]._u32[3], spu.gpr[5]._u32[3],
						spu.gpr[86]._u32[3]);
				}
			}
			bool seen = false;
			const u32 have = s_nsites.load();

			for (u32 i = 0; i < have && i < 8; i++)
			{
				if (s_sites[i].load() == lr) { seen = true; break; }
			}

			if (!seen && have < 8)
			{
				s_sites[have].store(lr);
				s_nsites.store(have + 1);
				cellSpurs.error("Thor CALLSITE #%u: syscall 0x%x from task lr=0x%05x sp=0x%05x (taskId=%u taskset=0x%x)",
					have, syscallNum, lr, spu.gpr[1]._u32[3], +ctxt->taskId, ctxt->taskset.addr());

				// DUMP LOCAL STORE ONCE, so the loop at `lr` can be disassembled
				// (Ghidra, SPU:BE:128:default, load at 0x0). A call site alone says
				// WHERE the task waits; the code around it says WHAT it waits on,
				// and that is the whole remaining question.
				// ONE DUMP PER TASKSET, NAMED BY TASKSET.
				//
				// A single global one-shot fired on whichever SPU hit a syscall
				// first - taskset 0x101b4e80 on SPU5 - and local store is PER SPU,
				// so it captured the wrong task entirely: 0x0f390..0x0f400 came back
				// all zeroes while the other task's 0x08d54 held code. Key the dump
				// to the taskset so the queue's task is actually captured.
				static std::atomic<u32> s_dumped[4]{};
				static std::atomic<u32> s_ndumped{0};

				const u32 tsaddr = ctxt->taskset.addr();
				bool already = false;

				for (u32 i = 0, have = s_ndumped.load(); i < have && i < 4; i++)
				{
					if (s_dumped[i].load() == tsaddr) { already = true; break; }
				}

				if (!already && s_ndumped.load() < 4)
				{
					s_dumped[s_ndumped.load()].store(tsaddr);
					s_ndumped++;

					char path[256]{};
					std::snprintf(path, sizeof(path),
						"/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/thor_ls_%08x.bin", tsaddr);

					if (FILE* f = std::fopen(path, "wb"))
					{
						std::fwrite(spu._ptr<void>(0), 1, 0x40000, f);
						std::fclose(f);
						cellSpurs.error("Thor LS DUMP: taskset=0x%x lr=0x%05x spu=%u -> %s",
							tsaddr, lr, +ctxt->spuNum, path);
					}
					else
					{
						cellSpurs.error("Thor LS DUMP: could not open %s", path);
					}
				}
			}
		}

		if (which < 16)
		{
			s_seen[which]++;

			// DUMP LOCAL STORE AT THE STALL, not only at the first call.
			//
			// The first-call dump showed the consumer had read entry_size=16,
			// depth=256, buffer=0x1030e480 and direction=2 - our structure, at our
			// offsets - with head=0 tail=0. At t=10.4s tail really may have been 0,
			// so that snapshot cannot decide anything. The question is what its
			// GETLLAR returns once the producer reports the ring FULL.
			if (s_total.load() == 6000)
			{
				char path[256]{};
				std::snprintf(path, sizeof(path),
					"/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/thor_stall_%08x.bin",
					ctxt->taskset.addr());

				if (FILE* f = std::fopen(path, "wb"))
				{
					std::fwrite(spu._ptr<void>(0), 1, 0x40000, f);
					std::fclose(f);
					cellSpurs.error("Thor STALL DUMP: taskset=0x%x -> %s", ctxt->taskset.addr(), path);
				}
			}

			if (const u32 n = s_total++; (n & 0x3F) == 0)
			{
				// WHICH TASKSET is yielding? Two exist (0x101b4e80 and 0x10364100)
				// and each has a task 0, so taskId alone cannot tell them apart.
				// The queue is bound to 0x10364100 - if the spinner is the OTHER
				// taskset, the queue's consumer is simply never scheduled and the
				// yield loop is a red herring.
				// PRINT ALL SIXTEEN SLOTS, NOT THE FIVE WE IMPLEMENT.
				//
				// The switch below handles EXIT(0), YIELD(1), WAIT_SIGNAL(2),
				// POLL(3) and RECV_WKL_FLAG(4), and everything else falls into
				// `default: rc = CELL_SPURS_TASK_ERROR_NOSYS`. This census counted
				// all sixteen and PRINTED ONLY THOSE FIVE, so a task hammering an
				// unimplemented syscall and being told NOSYS forever would look,
				// in every reading taken so far, exactly like a task that only
				// yields. Do not infer "the task only yields" from a probe that
				// can only see yields.
				cellSpurs.error("Thor SYSCALL CENSUS n=%u: [0]exit=%u [1]yield=%u [2]waitSig=%u [3]poll=%u [4]recvFlag=%u | UNIMPLEMENTED 5..15: %u %u %u %u %u %u %u %u %u %u %u (taskId=%u taskset=0x%x spu=%u)",
					n, s_seen[0].load(), s_seen[1].load(), s_seen[2].load(),
					s_seen[3].load(), s_seen[4].load(),
					s_seen[5].load(), s_seen[6].load(), s_seen[7].load(),
					s_seen[8].load(), s_seen[9].load(), s_seen[10].load(),
					s_seen[11].load(), s_seen[12].load(), s_seen[13].load(),
					s_seen[14].load(), s_seen[15].load(), +ctxt->taskId,
					ctxt->taskset.addr(), +ctxt->spuNum);
			}
		}
	}

	s32 rc = 0;
	u32 incident = 0;
	switch (syscallNum & 0x0F)
	{
	case CELL_SPURS_TASK_SYSCALL_EXIT:
		// DESTROY IS UNCONDITIONAL. Read out of the real taskset policy module,
		// captured under LLE and disassembled (EXIT arm at 0x1cd8):
		//
		//     00001cd8: lqr  r12,0x4be   -> 0x1cd8 + 0x4be*4 = 0x2FD0, word 1 is x2FD4
		//     00001ce0: ceqi r6,r7,0x4   ; x2FD4 == 4, the same test we use
		//     00001ce4: brz  r6,0x1cfc   ; not 4 -> the destroy path
		//     00001cfc: il r3,0 / il r4,0 / fsmbi r5,0
		//     00001d08: brsl lr,0x00000e40   ; DESTROY - not guarded by anything
		//     00001d0c: lqr  r6,0x4ad   -> 0x1d0c + 0x4ad*4 = 0x2FC0, i.e. x2FC0
		//     00001d18: brz  r14,0x1e40 ; x2FC0 == 0 -> skip the callback, and END
		//     00001d2c: brsl lr,0x00001438   ; otherwise onTaskExit
		//
		// The firmware destroys the task whenever x2FD4 != 4, and only THEN asks
		// whether there is an exit callback. Our copy wrapped BOTH in a single
		// gate, so a task exiting with x2FD4 != 4 and x2FC0 == 0 was never
		// destroyed at all - it stays set in the taskset's running/enabled
		// bitmaps forever, and nothing can reuse its slot.
		//
		//   debug.rpcsx.thor.exit_destroy_fix = 0 restores the old gate
		if (ctxt->x2FD4 != 4u && thor_exit_destroy_fix())
		{
			spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_DESTROY_TASK, nullptr, nullptr);
		}

		if (ctxt->x2FD4 == 4u || (ctxt->x2FC0 & 0xffffffffu) != 0u)
		{ // TODO: Figure this out
			if (ctxt->x2FD4 != 4u && !thor_exit_destroy_fix())
			{
				spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_DESTROY_TASK, nullptr, nullptr);
			}

			const u64 addr = ctxt->x2FD4 == 4u ? +taskset->x78 : +ctxt->x2FC0;
			const u64 args = ctxt->x2FD4 == 4u ? 0 : +ctxt->x2FC8;
			spursTasksetOnTaskExit(spu, addr, ctxt->taskId, ctxt->taskExitCode, args);
		}

		incident = CELL_SPURS_TRACE_TASK_EXIT;
		break;
	case CELL_SPURS_TASK_SYSCALL_YIELD:
		// See thor_yield_redispatch_fix: without it a one-task taskset can never
		// set `incident`, so it never re-dispatches and captures the SPU.
		// ORDER MATTERS: spursTasksetPollStatus has a side effect
		// (spursTasksetProcessPollStatus on the false path), so it must still be
		// evaluated. The gate is a FALLBACK, never a short-circuit.
		{
			// Preserve the original short-circuit exactly: pollStatus always runs
			// (side effect on its false path), REQUEST_POLL only when it is false.
			// THE FIRMWARE CALLS BOTH, UNCONDITIONALLY, AND ORS THEM.
			//
			// Read out of the real taskset policy module, YIELD arm at 0x1d34:
			//
			//     00001d34: brsl lr,0x00001350   ; poll status      -> r80
			//     00001d44: il   r3,0x3
			//     00001d48: brsl lr,0x00000e40   ; ProcessRequest(POLL) -> r3
			//     00001d4c: andi r15,r80,0xff
			//     00001d50: or   r80,r15,r3      ; combine BOTH results
			//     00001d54: brz  r80,0x00001e9c  ; neither wants it -> fast return
			//
			// There is no branch between 0x1d34 and 0x1d48: the request is issued
			// every time, whatever the poll returned. Our copy short-circuited it
			// with a ternary, so whenever wklWantsSpu was true the request was
			// never made - and spursTasksetProcessRequest is NOT a pure query. It
			// ends by writing the taskset bitmaps back, so skipping it drops a
			// state write-back on a path this title takes 138,624 times per run.
			//
			//   debug.rpcsx.thor.yield_poll_always = 0 restores the short circuit
			const bool wklWantsSpu = spursTasksetPollStatus(spu);
			const bool pollRc = thor_yield_poll_always()
				? spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_POLL, nullptr, nullptr) != 0
				: (wklWantsSpu ? false
					: spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_POLL, nullptr, nullptr) != 0);
			const bool taskWantsSpu = pollRc;

			// See thor_yield_fast_path: nothing else can run, so keep the SPU and
			// skip the whole-local-store save/restore this would otherwise cost.
			if (!wklWantsSpu && !taskWantsSpu && thor_yield_fast_path())
			{
				break;
			}

			if (wklWantsSpu || taskWantsSpu || thor_yield_redispatch_fix())
			{
			// If we reach here then it means that either another task can be scheduled or another workload can be scheduled
			// Save the context of the current task
				rc = spursTasketSaveTaskContext(spu);
				if (rc == CELL_OK)
				{
					spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_YIELD_TASK, nullptr, nullptr);
					incident = CELL_SPURS_TRACE_TASK_YIELD;
				}
			}
		}
		break;
	case CELL_SPURS_TASK_SYSCALL_WAIT_SIGNAL:
		if (spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_POLL_SIGNAL, nullptr, nullptr) == 0)
		{
			rc = spursTasketSaveTaskContext(spu);
			if (rc == CELL_OK)
			{
				if (spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_WAIT_SIGNAL, nullptr, nullptr) == 0)
				{
					incident = CELL_SPURS_TRACE_TASK_WAIT;
				}
			}
		}
		break;
	case CELL_SPURS_TASK_SYSCALL_POLL:
		rc = spursTasksetPollStatus(spu) ? CELL_SPURS_TASK_POLL_FOUND_WORKLOAD : 0;
		rc |= spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_POLL, nullptr, nullptr) ? CELL_SPURS_TASK_POLL_FOUND_TASK : 0;
		break;
	case CELL_SPURS_TASK_SYSCALL_RECV_WKL_FLAG:
		if (args == 0)
		{ // TODO: Figure this out
			spu_log.error("args == 0");
			// spursHalt(spu);
		}

		if (spursTasksetPollStatus(spu) || spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_WAIT_WKL_FLAG, nullptr, nullptr) != 1)
		{
			rc = spursTasketSaveTaskContext(spu);
			if (rc == CELL_OK)
			{
				incident = CELL_SPURS_TRACE_TASK_WAIT;
			}
		}
		break;
	default:
		// LOUD. An unimplemented taskset syscall returns NOSYS and the guest
		// will simply ask again, which presents as an unexplained spin. This
		// arm has been silent for the whole effort.
		{
			static std::atomic<u32> s_nosys{0};

			if (const u32 nn = s_nosys++; nn < 4 || (nn & 0x3FF) == 0)
			{
				cellSpurs.error("Thor NOSYS #%u: taskset syscall 0x%x UNIMPLEMENTED (taskId=%u taskset=0x%x)",
					nn, syscallNum, +ctxt->taskId, ctxt->taskset.addr());
			}
		}
		rc = CELL_SPURS_TASK_ERROR_NOSYS;
		break;
	}

	if (incident)
	{
		// Trace - TASK
		CellSpursTracePacket pkt{};
		pkt.header.tag = CELL_SPURS_TRACE_TAG_TASK;
		pkt.data.task.incident = incident;
		pkt.data.task.taskId = ctxt->taskId;
		cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

		// Clear the GUID of the task
		std::memset(spu._ptr<void>(ctxt->guidAddr), 0, 0x10);

		if (spursTasksetPollStatus(spu))
		{
			spursTasksetExit(spu);
		}
		else
		{
			spursTasksetDispatch(spu);
		}
	}

	return rc;
}

// Initialise the Taskset PM
void spursTasksetInit(spu_thread& spu, u32 pollStatus)
{
	auto ctxt = spu._ptr<SpursTasksetContext>(0x2700);
	auto kernelCtxt = spu._ptr<SpursKernelContext>(0x100);

	kernelCtxt->moduleId[0] = 'T';
	kernelCtxt->moduleId[1] = 'K';

	// Trace - START: Module='TKST'
	CellSpursTracePacket pkt{};
	pkt.header.tag = 0x52; // Its not clear what this tag means exactly but it seems similar to CELL_SPURS_TRACE_TAG_START
	std::memcpy(pkt.data.start._module, "TKST", 4);
	pkt.data.start.level = 2;
	pkt.data.start.ls = 0xA00 >> 2;
	cellSpursModulePutTrace(&pkt, ctxt->dmaTagId);

	spursTasksetProcessPollStatus(spu, pollStatus);
}

// Load an ELF
s32 spursTasksetLoadElf(spu_thread& spu, u32* entryPoint, u32* lowestLoadAddr, u64 elfAddr, bool skipWriteableSegments)
{
	if (elfAddr == 0 || (elfAddr & 0x0F) != 0)
	{
		return CELL_SPURS_TASK_ERROR_INVAL;
	}

	const spu_exec_object obj(fs::file(vm::base(vm::cast(elfAddr)), u32(0 - elfAddr)));

	if (obj != elf_error::ok)
	{
		return CELL_SPURS_TASK_ERROR_NOEXEC;
	}

	u32 _lowestLoadAddr = CELL_SPURS_TASK_BOTTOM;
	for (const auto& prog : obj.progs)
	{
		if (prog.p_paddr >= CELL_SPURS_TASK_BOTTOM)
		{
			break;
		}

		if (prog.p_type == 1u /* PT_LOAD */)
		{
			if (skipWriteableSegments == false || (prog.p_flags & 2u /*PF_W*/) == 0u)
			{
				if (prog.p_vaddr < CELL_SPURS_TASK_TOP || prog.p_vaddr + prog.p_memsz > CELL_SPURS_TASK_BOTTOM)
				{
					return CELL_SPURS_TASK_ERROR_FAULT;
				}

				_lowestLoadAddr > prog.p_vaddr ? _lowestLoadAddr = prog.p_vaddr : _lowestLoadAddr;
			}
		}
	}

	for (const auto& prog : obj.progs)
	{
		if (prog.p_paddr >= CELL_SPURS_TASK_BOTTOM) // ???
		{
			break;
		}

		if (prog.p_type == 1u)
		{
			if (skipWriteableSegments == false || (prog.p_flags & 2u) == 0u)
			{
				std::memcpy(spu._ptr<void>(prog.p_vaddr), prog.bin.data(), prog.p_filesz);
			}
		}
	}

	*entryPoint = obj.header.e_entry;
	if (lowestLoadAddr)
		*lowestLoadAddr = _lowestLoadAddr;

	return CELL_OK;
}

//----------------------------------------------------------------------------
// SPURS taskset policy module functions
//----------------------------------------------------------------------------
// THE JOB CHAIN POLICY MODULE IS NOT IMPLEMENTED, AND NOW IT SAYS SO.
//
// This title renders through SPURS JOB CHAINS - it creates three of them at
// t=11.4s - not through the taskset. Everything the taskset path does is
// therefore invisible to the renderer, which is why a measurably healthy SPURS
// queue never produced a frame.
//
// Until this is implemented, the honest behaviour is to EXIT the workload back
// to the kernel rather than to return false. `return false` left the SPU
// running at pc=0xA00 over local store that this module never filled - the
// previous policy module's bytes, executed as if they were a job chain. That
// is how six SPUs stay at 90% while nothing is drawn.
//
// What a real implementation owes, from CellSpursJobChain_x00 and the SPU-side
// contract: fetch the job descriptor at `pc`, honour `sizeJobDescriptor` and
// `maxGrabbedJob`, DMA in the job binary (jobbin2) and its data, run it, walk
// `linkRegister` on return, service `urgentCmds` (the one piece that already
// exists here, spursJobchainPopUrgentCommand), and respect `isHalted` and the
// job guard. That is a policy module of comparable size to the taskset one.
bool spursJobChainEntry(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursJobChainContext>(0x4a00);

	static std::atomic<u32> s_n{0};

	if (const u32 n = s_n++; n < 4 || (n & 0xFFF) == 0)
	{
		cellSpurs.error("Thor JOBCHAIN #%u: policy module UNIMPLEMENTED - exiting workload "
			"(jobChain=0x%x arg=0x%llx). This title renders through job chains, so nothing "
			"will be drawn until this is written.",
			n, ctxt->jobChain.addr(), spu.gpr[4]._u64[1]);
	}

	// Hand the SPU back to the kernel instead of running whatever is at 0xA00.
	cellSpursModuleExit(spu);
	return true;
}

void spursJobchainPopUrgentCommand(spu_thread& spu)
{
	const auto ctxt = spu._ptr<SpursJobChainContext>(0x4a00);
	const auto jc = vm::unsafe_ptr_cast<CellSpursJobChain_x00>(+ctxt->jobChain);

	const bool alterQueue = ctxt->unkFlag0;
	vm::reservation_op(spu, jc, [&](CellSpursJobChain_x00& op)
		{
			const auto ls = reinterpret_cast<CellSpursJobChain_x00*>(ctxt->tempAreaJobChain);

			struct alignas(16)
			{
				v128 first, second;
			} data;
			std::memcpy(&data, &op.urgentCmds, sizeof(op.urgentCmds));

			if (!alterQueue)
			{
				// Read the queue, do not modify it
			}
			else
			{
				// Move FIFO queue contents one command up
				data.first._u64[0] = data.first._u64[1];
				data.first._u64[1] = data.second._u64[0];
				data.second._u64[0] = data.second._u64[1];
				data.second._u64[1] = 0;
			}

			// Writeback
			std::memcpy(&ls->urgentCmds, &data, sizeof(op.urgentCmds));

			std::memcpy(&ls->isHalted, &op.unk0[0], 1); // Maybe intended to set it to false
			ls->unk5 = 0;
			ls->sizeJobDescriptor = op.maxGrabbedJob;
			std::memcpy(&op, ls, 128);
		});
}
