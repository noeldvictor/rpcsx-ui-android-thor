$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$kernelSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_spu.cpp") -Raw
$spuSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp") -Raw
$spuHeader = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.h") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorEsSpuExperiments")',
    'System.getenv("RPCSX_THOR_ES_SPU_EXPERIMENTS_BUILD")',
    '"-DRPCSX_THOR_ES_SPU_EXPERIMENTS=${if (rpcsxThorEsSpuExperiments) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing Eternal Sonata SPU-experiment Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_ES_SPU_EXPERIMENTS "Build Eternal Sonata DMA and GETLLAR experiments on Android" OFF)',
    'add_compile_definitions(RPCSX_THOR_ES_SPU_EXPERIMENTS=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing Eternal Sonata SPU-experiment CMake gate: $fragment"
    }
}

$kernelGate = '#if !defined\(__ANDROID__\) \|\| defined\(RPCSX_THOR_ES_SPU_EXPERIMENTS\)'
if ([regex]::Matches($kernelSource, $kernelGate).Count -ne 4) {
    throw "The kernel DMA experiment must have one body gate and three guarded start/join regions."
}

if ($kernelSource -notmatch ($kernelGate + '\s+enum class thor_es_dma_superpath_mode[\s\S]*?Eternal Sonata DMA candidate probe:[\s\S]*?#endif\s+\s*template <>')) {
    throw "Kernel DMA mode, state, hashing, and reporting are not wholly excluded from normal Android builds."
}

$kernelCallPatterns = @(
    ($kernelGate + '\s+if \(Emu\.GetTitleID\(\) == "BLUS30161"\)[\s\S]*?reset_thor_es_dma_probe[\s\S]*?#endif'),
    ($kernelGate + '\s+if \(thor_es_dma_verify_enabled\(\)\)[\s\S]*?hash_thor_es_dma_bytes[\s\S]*?#endif'),
    ($kernelGate + '\s+if \(thor_es_dma_probe_enabled\(\)\)[\s\S]*?log_thor_es_dma_probe[\s\S]*?#endif')
)

foreach ($pattern in $kernelCallPatterns) {
    if ($kernelSource -notmatch $pattern) {
        throw "A kernel DMA experiment hook is outside the Android build gate: $pattern"
    }
}

$spuGate = '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_ES_SPU_EXPERIMENTS\)'
if ([regex]::Matches($spuSource, $spuGate).Count -ne 1) {
    throw "SPUThread must use one shared build gate for the coupled DMA and GETLLAR experiments."
}

if ($spuSource -notmatch ($spuGate + '\s+enum class thor_es_dma_superpath_mode[\s\S]*?debug\.rpcsx\.thor\.es_dma_superpath[\s\S]*?enum class thor_es_getllar_mode[\s\S]*?debug\.rpcsx\.thor\.es_getllar[\s\S]*?static u32 thor_es_getllar_retry_cycles\(\)[\s\S]*?#else')) {
    throw "SPU DMA/GETLLAR parsing, profiling, and speed experiments are not wholly excluded from normal Android builds."
}

$requiredNoOpPatterns = @(
    'static FORCE_INLINE constexpr void record_thor_es_dma\([\s\S]*?\) noexcept\s+\{\s*\}',
    'static FORCE_INLINE constexpr void record_thor_es_dma_payload\([\s\S]*?\) noexcept\s+\{\s*\}',
    'static FORCE_INLINE constexpr bool thor_es_dma_list_active\([\s\S]*?return false;\s*\}',
    'struct thor_es_dma_list_scope\s+\{\s*explicit constexpr thor_es_dma_list_scope\(spu_thread&\) noexcept \{\}\s*\};',
    'static FORCE_INLINE constexpr void record_thor_es_getllar\([\s\S]*?\) noexcept\s+\{\s*\}',
    'static FORCE_INLINE constexpr u32 thor_es_getllar_retry_spin_limit\(\) noexcept\s+\{\s*return 24;\s*\}',
    'static FORCE_INLINE constexpr bool thor_es_getllar_skip_rsx_lock\([\s\S]*?return false;\s*\}',
    'static FORCE_INLINE constexpr u32 thor_es_getllar_retry_cycles\(\) noexcept\s+\{\s*return 300;\s*\}'
)

foreach ($pattern in $requiredNoOpPatterns) {
    if ($spuSource -notmatch $pattern) {
        throw "Normal Android did not retain the exact compile-time baseline SPU behavior: $pattern"
    }
}

$expectedHookCounts = @{
    'record_thor_es_dma\(' = 6
    'record_thor_es_dma_payload\(' = 6
    'record_thor_es_getllar\(' = 3
    'thor_es_getllar_retry_spin_limit\(' = 3
    'thor_es_getllar_skip_rsx_lock\(' = 3
    'thor_es_getllar_retry_cycles\(' = 3
}

foreach ($entry in $expectedHookCounts.GetEnumerator()) {
    $actual = [regex]::Matches($spuSource, $entry.Key).Count
    if ($actual -ne $entry.Value) {
        throw "Expected $($entry.Value) restorable SPU hooks matching $($entry.Key), found $actual."
    }
}

$requiredRuntimeFragments = @(
    'RPCSX_THOR_ES_DMA_SUPERPATH',
    'RPCS3_ES_DMA_SUPERPATH',
    'RPCS3_ES_GPU_PROBE',
    'RPCSX_THOR_ES_GETLLAR',
    'Thor GETLLAR probe sample:',
    'Thor GETLLAR probe top',
    'Eternal Sonata DMA candidate probe:'
)

foreach ($fragment in $requiredRuntimeFragments) {
    if (-not ($spuSource.Contains($fragment) -or $kernelSource.Contains($fragment))) {
        throw "Explicit diagnostic build lost SPU experiment behavior: $fragment"
    }
}

if ($spuHeader -notmatch 'struct es_gpu_probe_state_t[\s\S]*?es_gpu_probe_state_t es_gpu_probe\{\};[\s\S]*?rpcs3::hypervisor_context_t hv_ctx') {
    throw "The SPU thread layout changed; keep probe storage in place so persisted JIT object offsets remain valid."
}

if ($gradleSource -match 'rpcsxThorEsSpuExperiments[^\r\n]*\?:\s*true') {
    throw "The Android Eternal Sonata SPU experiments must remain disabled by default."
}

Write-Output "Thor Eternal Sonata SPU-experiment build gate passed: normal Android retains baseline DMA/GETLLAR semantics without probe work, while diagnostics and thread layout remain restorable."
