$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$sysinfoPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/sysinfo.cpp"
$spuSource = Get-Content -LiteralPath $spuPath -Raw
$sysinfoSource = Get-Content -LiteralPath $sysinfoPath -Raw

# Official RPCS3 61a2604824b01382bf57651b85f87b811306c2de lets
# ARM64 JIT code use the architectural cycle counter for SPU decrementers.
$arm64Guard = '#if defined(ARCH_X64) || defined(ARCH_ARM64)'
$guardCount = ([regex]::Matches($spuSource, [regex]::Escape($arm64Guard))).Count
if ($guardCount -ne 2) {
    throw "Expected exactly two ARM64 decrementer guards, found $guardCount."
}

$cycleCounter = 'llvm::Intrinsic::readcyclecounter'
$cycleCounterCount = ([regex]::Matches($spuSource, [regex]::Escape($cycleCounter))).Count
if ($cycleCounterCount -ne 2) {
    throw "Expected exactly two portable cycle-counter intrinsics, found $cycleCounterCount."
}

if ($spuSource.Contains('llvm::Intrinsic::x86_rdtsc')) {
    throw 'SPU decrementer lowering regressed to the x86-only rdtsc intrinsic.'
}

$enableGuard = 'if (utils::get_tsc_freq() && !(g_cfg.core.spu_loop_detection) && (g_cfg.core.clocks_scale == 100))'
$enableGuardCount = ([regex]::Matches($spuSource, [regex]::Escape($enableGuard))).Count
if ($enableGuardCount -ne 2) {
    throw "Expected both decrementer paths to retain the frequency/config guard; found $enableGuardCount."
}

foreach ($fallback in @(
    'res.value = call("spu_read_decrementer", &exec_read_dec, m_thread);',
    'm_ir->CreateStore(call("get_timebased_time", &get_timebased_time), spu_ptr<u64>(OFFSET_OF(spu_thread, ch_dec_start_timestamp)));'
)) {
    if (-not $spuSource.Contains($fallback)) {
        throw "SPU decrementer fallback was lost: $fallback"
    }
}

foreach ($fragment in @(
    'spu_ptr<u64>(OFFSET_OF(spu_thread, ch_dec_start_timestamp))',
    'spu_ptr<u32>(OFFSET_OF(spu_thread, ch_dec_value))',
    'spu_ptr<u8>(OFFSET_OF(spu_thread, is_dec_frozen))',
    'm_ir->getInt64(80000000)'
)) {
    if (-not $spuSource.Contains($fragment)) {
        throw "SPU decrementer timebase calculation fragment was lost: $fragment"
    }
}

if (-not $sysinfoSource.Contains('mrs %0, cntfrq_el0')) {
    throw 'ARM64 cycle-counter frequency source is missing from sysinfo.cpp.'
}

Write-Output 'Thor ARM64 SPU decrementer contract passed: RDCH/WRCH use readcyclecounter with guarded generic fallbacks.'
