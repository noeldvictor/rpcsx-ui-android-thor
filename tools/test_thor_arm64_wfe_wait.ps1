$ErrorActionPreference = "Stop"

# Contract for the opt-in AArch64 WFE wait in the SPU GETLLAR spin.
#
# x86 does not spin here. MONITORX arms a cache line and MWAITX parks the core
# in a low-power C-state until that line is written or a timer expires; TPAUSE
# does the timed half. Both sit inside #if defined(ARCH_X64), so ARM fell
# through to busy_wait(), which spins on yield. A spinning core on a passively
# cooled handheld is heat, and heat is this device's binding constraint.
#
# AArch64 has had the same primitive since Armv8.0: LDXR arms the exclusive
# monitor on the line, WFE parks the core, and a write to that line clears the
# monitor and wakes it.
#
# This is off by default and must stay that way until someone can measure it.
# The entire case for it is power and thermal behaviour; its effect on frame
# time could be zero or negative, since parking a core adds wake latency to the
# reservation handoff. This fork does not benchmark, so there is nothing to
# check such a claim against.
#
# What this test protects is the ordering, which is what makes it safe rather
# than a hang.

$repoRoot = Split-Path -Parent $PSScriptRoot
$spu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp") -Raw
$cmake = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$gradle = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw

# Strip comments; they describe the hazard and name the instructions.
$code = ($spu -split "`n" | Where-Object { $_.Trim() -notmatch '^\s*//' }) -join "`n"

# 1. It must be opt-in, and default off, in both build systems.
# Not [^)]* here: the option's own description contains parentheses.
if ($cmake -notmatch 'option\(RPCSX_THOR_ARM64_WFE_WAIT\b.*\sOFF\)') {
    throw "RPCSX_THOR_ARM64_WFE_WAIT is no longer a CMake option defaulting to OFF."
}
if ($gradle -notmatch 'RPCSX_THOR_ARM64_WFE_WAIT=\$\{if \(rpcsxThorArm64WfeWait\) "ON" else "OFF"\}') {
    throw "Gradle no longer forwards the WFE gate to CMake."
}
if ($gradle -notmatch '(?s)val rpcsxThorArm64WfeWait =.*?null, "", "0", "false", "off", "OFF" -> false') {
    throw "The Gradle WFE property no longer defaults to false when unset."
}

# 2. The helper must exist and be gated on both the architecture and the flag.
$helper = [regex]::Match($code, '(?s)#if defined\(ARCH_ARM64\) && defined\(RPCSX_THOR_ARM64_WFE_WAIT\)(?<body>.*?)#endif')
if (-not $helper.Success) {
    throw "The AArch64 WFE helper is missing or no longer gated on ARCH_ARM64 plus the opt-in flag."
}
$body = $helper.Groups['body'].Value

foreach ($insn in @('ldxr', 'wfe', 'clrex')) {
    if ($body -notmatch $insn) {
        throw "The WFE helper no longer emits $insn."
    }
}

# 3. Ordering is the whole safety argument: arm, then re-check, then park.
#    Checking before arming loses the wakeup if the writer lands in between,
#    and the thread then sleeps until something unrelated pokes it.
$iLdxr  = $body.IndexOf('ldxr')
$iCheck = $body.IndexOf('needs_wait')
$iWfe   = $body.IndexOf('wfe')

if ($iLdxr -lt 0 -or $iCheck -lt 0 -or $iWfe -lt 0) {
    throw "Could not locate the arm/check/park sequence in the WFE helper."
}
if (-not ($iLdxr -lt $iCheck -and $iCheck -lt $iWfe)) {
    throw "The WFE helper no longer arms the monitor, then re-checks, then parks. Any other order can lose a wakeup and sleep until an unrelated event."
}

# 4. CLREX must come after the park, not before it, or the reservation is
#    dropped while it is still needed.
$iClrex = $body.IndexOf('clrex')
if ($iClrex -lt $iWfe) {
    throw "The WFE helper drops the exclusive monitor before parking, which defeats the wake."
}

# 4b. Parking must be gated on an established long wait.
#
#     MWAITX bounds its sleep with a timer; AArch64 cannot, because FEAT_WFxT
#     is absent here (ID_AA64ISAR2_EL1 reads 0 on device). WFE's only fallback
#     wake is the generic timer event stream, measured at ~95us. The monitor
#     granule is one 64-byte line while a reservation is 128 bytes, so a writer
#     touching only the second line may not clear the monitor and the waiter
#     eats the full ~95us. Parking unconditionally would put that penalty on
#     short waits, where it dominates.
if ($code -notmatch 'getllar_spin_count >= \d+') {
    throw "The WFE path no longer waits for an established long spin before parking. Without WFxT there is no timeout, and the fallback wake is ~95us."
}

# 5. The default path must remain the plain busy wait, reachable when the flag
#    is off. If this disappears, turning the option off stops being safe.
if ($code -notmatch 'thor_wait::profiled_busy_wait\(thor_wait::site::spu_getllar, 300\)') {
    throw "The default GETLLAR busy-wait path is gone; the opt-in flag is no longer optional."
}

# 6. The x86 path must be untouched. This change is meant to add an ARM branch,
#    not to alter what Intel and AMD hardware does.
foreach ($x86 in @('__tpause', '__mwaitx', 'utils::has_um_wait\(\)')) {
    if ($code -notmatch $x86) {
        throw "The x86 power-optimized wait lost $x86; this change was supposed to leave it alone."
    }
}

Write-Output "Thor ARM64 WFE wait contract passed: opt-in and default-off in both build systems, helper arms then re-checks then parks then clears, default busy-wait intact, x86 path untouched."
