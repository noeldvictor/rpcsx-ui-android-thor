$ErrorActionPreference = "Stop"

# Contract for the PPU LLVM optimization pipeline.
#
# The analysis managers, PassBuilder and FunctionPassManager were all inside
# #ifdef ARCH_X64, and both fpm.run() call sites were #ifdef ARCH_X64 // TODO.
# So on ARM64 every translated PPU function reached the backend with no
# IR-level optimization whatsoever, not even EarlyCSE. MCJIT's
# CodeGenOptLevel only tunes code generation; it does not do IR-level CSE, so
# nothing else was picking this up.
#
# Nothing in the pipeline is architecture specific, and the SPU side already
# runs its transforms on ARM, so the gate was an oversight rather than a design.

$repoRoot = Split-Path -Parent $PSScriptRoot
$ppu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp") -Raw

# The pipeline must be built unconditionally.
$setup = [regex]::Match($ppu, '(?s)FunctionAnalysisManager fam;.*?fpm\.addPass\(EarlyCSEPass\(\)\);')
if (-not $setup.Success) {
    throw "Could not isolate the PPU pass pipeline setup."
}
if ($setup.Value -match '#ifdef ARCH_X64|#if defined\(ARCH_X64\)') {
    throw "The PPU pass pipeline setup is gated to x86 again."
}

# Both run sites must be reachable on every architecture.
$runs = [regex]::Matches($ppu, 'fpm\.run\(\*func, fam\);')
if ($runs.Count -lt 2) {
    throw "Expected both PPU pass-manager run sites; found $($runs.Count)."
}

foreach ($run in $runs) {
    $before = $ppu.Substring(0, $run.Index)
    $lastGate = [regex]::Matches($before, '#ifdef ARCH_X64|#if defined\(ARCH_X64\)|#endif')
    if ($lastGate.Count -gt 0) {
        $last = $lastGate[$lastGate.Count - 1].Value
        if ($last -ne '#endif') {
            throw "A fpm.run() call is inside an ARCH_X64 gate again."
        }
    }
}

if ($ppu -match '#ifdef ARCH_X64 // TODO') {
    throw "The ARCH_X64 TODO gate around the PPU optimization passes is back."
}

Write-Output "Thor PPU pass-pipeline contract passed: analysis managers and EarlyCSE build unconditionally, both run sites reachable on ARM64."
