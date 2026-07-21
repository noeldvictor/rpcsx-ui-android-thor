$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cellRoot = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell"
$interpreterSource = Get-Content -LiteralPath (Join-Path $cellRoot "PPUInterpreter.cpp") -Raw
$translatorSource = Get-Content -LiteralPath (Join-Path $cellRoot "PPUTranslator.cpp") -Raw
$translatorHeader = Get-Content -LiteralPath (Join-Path $cellRoot "PPUTranslator.h") -Raw
$threadSource = Get-Content -LiteralPath (Join-Path $cellRoot "PPUThread.cpp") -Raw
$labSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/windows_rpcs3_lab.ps1") -Raw
$managedProfilesSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt") -Raw
$mainActivitySource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/java/net/rpcsx/MainActivity.kt") -Raw
$inputMacroSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/thor_input_macro.ps1") -Raw
$pushProfileSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/push_eternal_sonata_thor_profile.ps1") -Raw

$requiredFragments = @(
    @($interpreterSource, 'g_cfg.core.ppu_llvm_nj_fixup && !g_cfg.core.set_daz_and_ftz'),
    @($translatorHeader, 'VecHandleResult(llvm::Value* val, bool flush_denormals_manually = false)'),
    @($translatorHeader, 'vec_handle_result(T&& expr, bool flush_denormals_manually = false)'),
    @($translatorSource, 'g_cfg.core.ppu_llvm_nj_fixup && (flush_denormals_manually || !g_cfg.core.set_daz_and_ftz)'),
    @($threadSource, 'uses_hardware_ftz'),
    @($threadSource, 'settings += ppu_settings::uses_hardware_ftz'),
    @($labSource, '[string]$PpuDazAndFtz = "Keep"'),
    @($labSource, 'Set DAZ and FTZ: $dazAndFtzValue'),
    @($labSource, '-PpuDazAndFtz $PpuDazAndFtz'),
    @($managedProfilesSource, '"BLUS30161" to """'),
    @($managedProfilesSource, 'Set DAZ and FTZ: true'),
    @($managedProfilesSource, 'fun applyRecommendedConfigForTitleId(context: Context, titleId: String): Status'),
    @($managedProfilesSource, 'val bundledTimestamp = readBundledDatabaseTimestamp(context)'),
    @($managedProfilesSource, 'synchronized(lock) { cachedDatabase = ready }'),
    @($managedProfilesSource, 'statusForConfigSnapshot('),
    @($mainActivitySource, 'GameSettingsDatabase.applyRecommendedConfigForTitleId(this, titleId)'),
    @($mainActivitySource, 'val managedProfileReady = settingsStatus?.let { it.enabled && it.applied } == true'),
    @($mainActivitySource, 'if (requireManagedProfile && !managedProfileReady)'),
    @($mainActivitySource, 'Thor debug boot rejected: request=$requestId'),
    @($mainActivitySource, 'Thor debug boot accepted: request=$requestId'),
    @($mainActivitySource, 'if (maybeStartThorDebugBoot(intent)) {'),
    @($inputMacroSource, '--es titleId $TitleId'),
    @($inputMacroSource, '--es thorDebugBootRequestId $debugBootRequestId'),
    @($inputMacroSource, 'Assert-ThorDebugBootAccepted -RequestId $debugBootRequestId'),
    @($inputMacroSource, '--ez thorRequireManagedProfile true')
)

foreach ($entry in $requiredFragments) {
    if (-not $entry[0].Contains($entry[1])) {
        throw "Missing PPU FTZ/NJ contract fragment: $($entry[1])"
    }
}

$debugBootComposeIndex = $mainActivitySource.IndexOf('if (maybeStartThorDebugBoot(intent)) {')
$setContentIndex = $mainActivitySource.IndexOf('setContent {', $debugBootComposeIndex)
$debugBootCallCount = ([regex]::Matches($mainActivitySource, 'maybeStartThorDebugBoot\(intent\)')).Count
if ($debugBootComposeIndex -lt 0 -or $setContentIndex -le $debugBootComposeIndex -or $debugBootCallCount -ne 2) {
    throw "Thor debug boot must bypass Compose on cold start and remain available from onNewIntent; order=$debugBootComposeIndex/$setContentIndex calls=$debugBootCallCount."
}

$manualFlushFragments = @(
    'llvm.exp2.v4f32", {b}}, true',
    'llvm.log2.v4f32", {b}}, true',
    'fmax(b, a))), true',
    'fmin(b, a))), true'
)

foreach ($fragment in $manualFlushFragments) {
    if (-not $translatorSource.Contains($fragment)) {
        throw "Missing always-manual vector denormal fixup: $fragment"
    }
}

$arm64ExtremaPatterns = @(
    'void PPUTranslator::VMAXFP\(ppu_opcode_t op\)[\s\S]*?#ifdef ARCH_ARM64\s+set_vr\(op\.vd, vec_handle_result\(fmax\(a, b\), true\)\);\s+#else[\s\S]*?#endif',
    'void PPUTranslator::VMINFP\(ppu_opcode_t op\)[\s\S]*?#ifdef ARCH_ARM64\s+set_vr\(op\.vd, vec_handle_result\(fmin\(a, b\), true\)\);\s+#else[\s\S]*?#endif'
)

foreach ($pattern in $arm64ExtremaPatterns) {
    if ($translatorSource -notmatch $pattern) {
        throw "Missing direct ARM64 PPU extrema lowering: $pattern"
    }
}

if ($threadSource -notmatch 'uses_hardware_ftz,[\s\S]*bitset_last = uses_hardware_ftz') {
    throw "PPU cache identity does not include the hardware-FTZ code-generation bit."
}

$pushProfileCount = ([regex]::Matches($pushProfileSource, '(?m)^  Set DAZ and FTZ: true\r?$')).Count
if ($pushProfileCount -ne 4) {
    throw "Expected all four Eternal Sonata profile templates to enable hardware FTZ; found $pushProfileCount."
}

Write-Output "Thor PPU FTZ/NJ contract passed: hardware FTZ is BLUS30161-only, debug boots reuse one validated managed-profile snapshot and fail closed unless it is applied, ARM64 extrema use direct hardware lowering, four sensitive ops retain manual flushing, and PPU cache identity is distinct."
