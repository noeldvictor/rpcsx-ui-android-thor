$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cpuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.cpp"
$ppuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
$rsxPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Program/ProgramStateCache.h"

$cpu = Get-Content -LiteralPath $cpuPath -Raw
$ppu = Get-Content -LiteralPath $ppuPath -Raw
$rsx = Get-Content -LiteralPath $rsxPath -Raw

$cpuAndroid = [regex]::Match(
    $cpu,
    '(?s)#ifdef __ANDROID__\s+(?<body>.*?)\s+#else\s+\tif \(m_use_dotprod\)'
).Groups['body'].Value

foreach ($fragment in @(
    'static const bool s_logged_spu_features = []()',
    'AArch64 SPU fast paths: mode=%s, dotprod=%s, i8mm=%s.',
    'utils::get_arm64_spu_feature_mode_name()',
    'utils::use_spu_dotprod()',
    'utils::use_spu_i8mm()'
)) {
    if (-not $cpuAndroid.Contains($fragment)) {
        throw "Android ARM64 feature reporting lost its once-per-process contract: $fragment"
    }
}

if ($cpuAndroid.Contains('AArch64 dot-product SPU fast paths enabled.') -or
    $cpuAndroid.Contains('AArch64 I8MM SPU fast paths enabled.')) {
    throw "Android restored per-translator ARM64 feature notices."
}

foreach ($desktopMessage in @(
    'AArch64 dot-product SPU fast paths enabled.',
    'AArch64 I8MM SPU fast paths enabled.',
    'AArch64 SPU feature isolation mode: %s (dotprod=%s, i8mm=%s).'
)) {
    if (-not $cpu.Contains($desktopMessage)) {
        throw "Desktop ARM64 diagnostics were removed: $desktopMessage"
    }
}

if ($ppu -notmatch '(?s)#ifdef __ANDROID__\s+if \(!is_compiled && g_cfg\.core\.ppu_debug\)\s+#else\s+if \(!is_compiled\)\s+#endif\s+\{\s+ppu_log\.success\("LLVM: Loaded module %s", obj_name\);') {
    throw "Cached PPU module success rows are not Android-debug-only."
}

if (-not $ppu.Contains('ppu_log.error("LLVM: Failed to load module %s", obj_name);')) {
    throw "Cached PPU module load failures are no longer retained."
}

if ($rsx -notmatch '(?s)#ifndef __ANDROID__\s+// Android already records the program IDs before compilation and retains every failure\.\s+rsx_log\.success\("Program compiled successfully"\);\s+#endif\s+notify_pipeline_compiled') {
    throw "Routine RSX pipeline success output is not compiled out on Android."
}

if ($rsx -notmatch '(?s)#ifdef __ANDROID__\s+// Cached startup can create hundreds of programs;.*?rsx_log\.trace\("Add program \(vp id = %d, fp id = %d\)"') {
    throw "Android lost its trace-level pipeline identity breadcrumb."
}

foreach ($path in @($PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -ne 0) {
        throw "PowerShell contract parse failed for ${path}: $($errors[0].Message)"
    }
}

Write-Output "Thor Android compile-log contract passed: cached PPU and RSX successes are quiet, failures remain, and ARM64 features report once."
