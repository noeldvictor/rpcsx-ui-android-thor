param(
    [string]$SourcePath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $PSScriptRoot "../app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
}

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$source = Get-Content -LiteralPath $resolvedSource -Raw

$startupBegin = $source.LastIndexOf("extern void ppu_initialize()")
$moduleSignature = "bool ppu_initialize(const ppu_module<lv2_obj>& info, bool check_only, u64 file_size, concurent_memory_limit& memory_limit)"
$moduleInitBegin = $source.LastIndexOf($moduleSignature)
if ($startupBegin -lt 0 -or $moduleInitBegin -le $startupBegin) {
    throw "Could not isolate the PPU startup initialization path."
}

$startup = $source.Substring($startupBegin, $moduleInitBegin - $startupBegin)
$compactStartup = $startup -replace '\s', ''
$precompileGate = 'if(!_main.segs.empty()&&g_cfg.core.llvm_precompilation){compile_main=ppu_initialize(_main,true);'
if (-not $compactStartup.Contains($precompileGate)) {
    throw "The check-only main-module cache pass is not gated by LLVM precompilation."
}

$checkOnlyCalls = [regex]::Matches($startup, 'ppu_initialize\(_main,\s*true\);').Count
if ($checkOnlyCalls -ne 1) {
    throw "Expected exactly one check-only main-module initialization call, found $checkOnlyCalls."
}

$moduleSplit = $source.IndexOf("// Limit how many modules are per JIt instance", $moduleInitBegin)
if ($moduleSplit -le $moduleInitBegin) {
    throw "Could not isolate the PPU module scan prelude."
}

$modulePrelude = $source.Substring($moduleInitBegin, $moduleSplit - $moduleInitBegin)
$satGate = $modulePrelude.IndexOf("if (g_cfg.core.ppu_set_sat_bit)")
$mfvscrDecode = $modulePrelude.IndexOf("g_ppu_itype.decode(*i_ptr) == ppu_itype::MFVSCR")
if ($satGate -lt 0 -or $mfvscrDecode -le $satGate) {
    throw "The MFVSCR instruction scan is not behind the accurate-SAT setting gate."
}

if ($modulePrelude.IndexOf("g_ppu_itype.decode(*i_ptr) == ppu_itype::MFVSCR", $mfvscrDecode + 1) -ge 0) {
    throw "Found an unexpected second MFVSCR instruction scan before module splitting."
}

Write-Output "PPU warm-cache startup contract tests passed."
