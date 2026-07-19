$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$lv2Source = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/lv2.cpp") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorSyscallStats")',
    'System.getenv("RPCSX_THOR_SYSCALL_STATS_BUILD")',
    '"-DRPCSX_THOR_SYSCALL_STATS=${if (rpcsxThorSyscallStats) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing syscall-statistics Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_SYSCALL_STATS "Instrument Android PPU syscalls for Thor diagnostics" OFF)',
    'add_compile_definitions(RPCSX_THOR_SYSCALL_STATS=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing syscall-statistics CMake gate: $fragment"
    }
}

if ($lv2Source -notmatch '#if defined\(__ANDROID__\) && !defined\(RPCSX_THOR_SYSCALL_STATS\)\s+static FORCE_INLINE constexpr bool ppu_syscall_stats_enabled\(\) noexcept \{\s+return false;\s+\}\s+#else[\s\S]*?__system_property_get\("debug\.rpcsx\.thor\.syscall_stats", value\)[\s\S]*?#else\s+  return true;\s+#endif\s+\}\s+#endif') {
    throw "Normal Android builds do not compile the disabled syscall-statistics gate to false while preserving diagnostics and desktop behavior."
}

if ($lv2Source -notmatch '#if !defined\(__ANDROID__\) \|\| defined\(RPCSX_THOR_SYSCALL_STATS\)\s+class ppu_syscall_usage[\s\S]*?static FORCE_INLINE void record_ppu_syscall\(u64 code\)[\s\S]*?#else\s+static FORCE_INLINE constexpr void record_ppu_syscall\(u64\) noexcept \{\s+\}\s+#endif\s+\s*extern void ppu_execute_syscall[\s\S]*?record_ppu_syscall\(code\);') {
    throw "The syscall-statistics thread/accounting hook is not wholly excluded from normal Android builds."
}

if ($gradleSource -match 'rpcsxThorSyscallStats[^\r\n]*\?:\s*true') {
    throw "Android syscall statistics must remain disabled by default."
}

Write-Output "Thor syscall-statistics build gate passed: normal Android syscalls skip diagnostic timing/atomics while explicit diagnostic and desktop accounting remain."
