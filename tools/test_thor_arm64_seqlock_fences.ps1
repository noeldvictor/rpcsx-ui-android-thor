$ErrorActionPreference = "Stop"

# Contract for the reservation seqlock read side on AArch64.
#
# GETLLAR and the MFC DMA read both follow the same shape:
#
#   t0 = vm::reservation_acquire(addr)     load-acquire
#   ... copy guest data ...                plain loads
#   if (t0 != vm::reservation_acquire(addr)) retry
#
# The copy is only valid if it is observed strictly between the two reservation
# reads. The first read is a load-acquire, so the copy cannot be hoisted above
# it. But load-acquire is one-way: it orders later accesses after itself and
# does nothing to stop earlier accesses being observed after it. Without a
# LoadLoad barrier the copy can be satisfied after the validating read, so a
# writer that bumped the counter in between goes undetected, which is the exact
# case the check exists for.
#
# x86 never exhibits this, because TSO does not reorder loads with loads. That
# is why the barrier was absent: the read side was correct as written on the
# architecture it was written for. atomic_fence_acquire is a compiler barrier
# only on x86, so restoring it costs nothing there.
#
# The DMA path matters as much as GETLLAR despite looking safer: it re-compares
# the data, but only for the 128-byte case. Every smaller size relies on the
# timestamp check alone.

$repoRoot = Split-Path -Parent $PSScriptRoot
$spu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp") -Raw

# Strip comments: they describe the hazard and name the fence, and must not be
# what satisfies the check.
$code = ($spu -split "`n" | Where-Object { $_.Trim() -notmatch '^\s*//' }) -join "`n"

# Each validating re-read must have an acquire fence between the copy and itself.
$sites = @(
    @{
        name  = "GETLLAR"
        check = 'if \(u64 time0 = vm::reservation_acquire\(addr\); \(ntime & test_mask\) != \(time0 & test_mask\)\)'
    },
    @{
        name  = "MFC DMA read"
        check = 'if \(time0 != vm::reservation_acquire\(eal\) \|\|'
    }
)

foreach ($site in $sites) {
    $m = [regex]::Match($code, $site.check)
    if (-not $m.Success) {
        throw "Could not find the $($site.name) reservation re-check; the seqlock shape changed and this contract needs revisiting."
    }

    # Look back a short way for the fence. Keep the window tight so an unrelated
    # fence far above cannot satisfy it.
    $start = [Math]::Max(0, $m.Index - 400)
    $window = $code.Substring($start, $m.Index - $start)

    if ($window -notmatch 'atomic_fence_acquire\(\)') {
        throw "$($site.name) re-reads the reservation without an acquire fence after the data copy. On AArch64 the copy may be observed after the check, defeating it."
    }
}

# The fences must not have been downgraded to a bare compiler barrier, which
# would restore the x86-only behaviour while looking correct.
foreach ($bad in @('std::atomic_signal_fence', 'asm volatile\("" ::: "memory"\)')) {
    if ($code -match "$bad[^;]*;\s*(?=[^;]*reservation_acquire)") {
        throw "A reservation re-check is guarded by a compiler-only barrier, which orders nothing on AArch64."
    }
}

Write-Output "Thor ARM64 seqlock contract passed: GETLLAR and the MFC DMA read both fence the data copy against the validating reservation re-read."
