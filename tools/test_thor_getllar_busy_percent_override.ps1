$ErrorActionPreference = "Stop"

# Contract: the GETLLAR busy-waiting percentage override must be inert by default.
#
# `SPU GETLLAR Busy Waiting Percentage` decides whether a GETLLAR wait spins or
# sleeps, and at its upstream default of 100 the answer is always "spin". That
# one value gates the site measured at 93% of all emulator spin, and no Thor
# profile overrides it - while the analogous reservation knob is explicitly set
# to 0 for this device. Sweeping it is the outstanding measurement.
#
# The override exists because config.yml is not writable from a shell under
# scoped storage, so reading the value only from config would cost a full
# rebuild per arm. It is a diagnostic, and the property it reads must never
# change shipped behaviour:
#
#   - an absent property returns the configured value unchanged;
#   - a malformed one does too, rather than defaulting to something;
#   - values above 100 are rejected, since the comparison it feeds is against a
#     modulo-100 quantity and a larger number would silently mean "always spin"
#     while looking like a deliberate setting.
#
# It is also read once and cached. The call site is inside the GETLLAR retry
# path, and a property read per iteration would perturb the measurement it
# exists to enable - the same mistake as the FPS harness whose per-sample adb
# spawns tripped the thermal guard.

$repoRoot = Split-Path -Parent $PSScriptRoot
$spu = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

if (-not (Test-Path $spu)) { throw "SPUThread.cpp not found at $spu" }
$source = Get-Content $spu -Raw

$start = $source.IndexOf("static FORCE_INLINE u32 get_thor_getllar_busy_percent")
if ($start -lt 0) {
    throw "get_thor_getllar_busy_percent is missing. The GETLLAR busy-waiting percentage can then only be swept by rebuilding once per arm."
}
$tail = $source.Substring($start)
$end = $tail.IndexOf("`n}")
if ($end -lt 0) { throw "Could not find the end of get_thor_getllar_busy_percent." }
$body = $tail.Substring(0, $end)

# 1. Absent property must fall through to the configured value.
if ($body -notmatch 'if \(__system_property_get\("debug\.rpcsx\.thor\.getllar_busy_percent", value\) <= 0\)\s*\r?\n\s*\{\s*\r?\n\s*return -1;') {
    throw "An absent property does not fall through to the configured value. The override must be inert unless explicitly set."
}

# 2. Malformed input must fall through too, not silently become a number.
if ($body -notmatch 'end == value \|\| \*end') {
    throw "Malformed property text is not rejected. A partial parse would apply a value the operator never asked for."
}

# 3. Out-of-range must be rejected. The comparison this feeds is against a
#    modulo-100 quantity, so anything above 100 means 'always spin' while
#    reading like a deliberate choice.
if ($body -notmatch 'parsed > 100') {
    throw "Values above 100 are not rejected. They would mean 'always spin' while looking like a deliberate setting."
}

# 4. The configured value must be what is returned when nothing overrides.
if ($body -notmatch 'return configured;') {
    throw "The function does not return the configured value as its fallback."
}

# 5. Read once, not per call. This is inside the GETLLAR retry path.
if ($body -notmatch 'static const int overridden') {
    throw "The property is not read once and cached. A read per iteration sits inside the GETLLAR retry path and would perturb the measurement this exists to enable."
}

# 6. It must be ANDROID-gated, so host builds are untouched.
if ($body -notmatch '#ifdef ANDROID') {
    throw "The override is not ANDROID-gated."
}

# 7. It must actually be wired to the call site, or it is decorative.
if ($source -notmatch 'get_thor_getllar_busy_percent\(get_spu_wait_policy_for_runtime\(g_cfg\.core\.spu_getllar_busy_waiting_percentage\)\)') {
    throw "The override is not wired into evaluate_spin_optimization's percentage argument, so setting the property would do nothing."
}

# 8. No Thor profile may quietly pin the percentage. The sweep is unmeasured;
#    changing the default before measuring is the thing this test guards.
foreach ($f in @(
    "app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt",
    "app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt"
)) {
    $p = Join-Path $repoRoot $f
    if ((Test-Path $p) -and ((Get-Content $p -Raw) -match 'SPU GETLLAR Busy Waiting Percentage')) {
        throw "$f now sets 'SPU GETLLAR Busy Waiting Percentage'. That default is unmeasured; sweep it with the debug property first."
    }
}

Write-Output "Thor GETLLAR busy-percent override contract passed: inert without the property, rejects malformed and out-of-range values, read once, ANDROID-gated, wired to the call site, and no profile pins the percentage."
