param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuCommonPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$spuThreadPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"
$spuLlvmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"

$spuCommon = Get-Content -LiteralPath $spuCommonPath -Raw
$spuThread = Get-Content -LiteralPath $spuThreadPath -Raw
$spuLlvm = Get-Content -LiteralPath $spuLlvmPath -Raw

function Assert-Contains {
    param([string]$Source, [string]$Needle, [string]$Message)
    if (-not $Source.Contains($Needle)) {
        throw $Message
    }
}

Assert-Contains $spuCommon 'const bool build_llvm_interpreter = g_cfg.core.spu_decoder == spu_decoder_type::dynamic' "Dynamic mode no longer retains its required generated interpreter."
Assert-Contains $spuCommon '#if !defined(ARCH_ARM64)' "The LLVM-interpreter skip is not restricted to ARM64."
Assert-Contains $spuCommon '|| g_cfg.core.spu_decoder == spu_decoder_type::llvm' "Non-ARM64 LLVM no longer builds the interpreter required by spu_fast."
Assert-Contains $spuCommon 'if (build_llvm_interpreter)' "The architecture decision does not guard interpreter compilation."
Assert-Contains $spuCommon 'Skipped unused all-opcode LLVM interpreter on ARM64.' "The ARM64 startup decision is not observable in logs."

$decision = $spuCommon.IndexOf('const bool build_llvm_interpreter =')
$compile = $spuCommon.IndexOf('spu_recompiler_base::make_llvm_recompiler(11, use_native_object_cache)', $decision)
$workers = $spuCommon.IndexOf('u32 worker_count = 0;', $compile)
if ($decision -lt 0 -or $compile -le $decision -or $workers -le $compile) {
    throw "Interpreter skipping is not isolated from normal cached-program compilation."
}

if (([regex]::Matches($spuThread, [regex]::Escape('#elif defined(ARCH_ARM64)'))).Count -lt 2) {
    throw "Both normal and restored ARM64 SPU-thread constructors must be architecture-gated."
}
if (([regex]::Matches($spuThread, [regex]::Escape('jit = spu_recompiler_base::make_llvm_recompiler();'))).Count -ne 2) {
    throw "Both normal and restored ARM64 LLVM SPU threads must own the regular recompiler."
}
if (([regex]::Matches($spuThread, [regex]::Escape('spu_runtime::g_interpreter(*this, _ptr<u8>(0), nullptr);'))).Count -ne 1) {
    throw "Generated-interpreter execution has gained an unexpected runtime caller."
}
if ($spuThread -notmatch 'if\s*\(jit\)\s*\{') {
    throw "SPU runtime no longer separates JIT-owned execution from interpreter execution."
}

Assert-Contains $spuLlvm 'call(name, &exec_fall<F>, m_thread, m_ir->getInt32(op.opcode));' "Regular LLVM instruction fallback no longer calls the C++ handler directly."
Assert-Contains $spuCommon 'struct spu_fast : public spu_recompiler_base' "The x86 fast tier consuming the generated instruction table is missing."
Assert-Contains $spuCommon '#ifndef ARCH_X64' "spu_fast is no longer explicitly x86-only."
if (([regex]::Matches($spuCommon, [regex]::Escape('spu_runtime::g_interpreter_table['))).Count -ne 1) {
    throw "The generated interpreter table has gained an unexpected non-spu_fast consumer."
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
    throw "PowerShell AST parse failed for ${PSCommandPath}: $($errors -join '; ')"
}

Write-Host "Thor ARM64 unused SPU interpreter skip contract: PASS"
