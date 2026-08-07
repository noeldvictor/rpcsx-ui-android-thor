$ErrorActionPreference = "Stop"

# Contract: the Eternal Sonata semaphore fast cache is a publish-then-flag
# protocol and must keep release/acquire ordering.
#
# The cache maps a semaphore id to an lv2_sema*, so a lookup can skip the id
# manager. Three operations touch it, and all three were originally relaxed:
#
#   publish     sema.store(p); sem_id.store(id);
#   read        if (sem_id.load() != id) return nullptr; return sema.load();
#   invalidate  if (sem_id.CAS(id, 0)) sema.store(nullptr);
#
# All relaxed is correct on x86 and a data race on AArch64. TSO reorders neither
# store-store nor load-load, so a reader that observed the new id was guaranteed
# to observe the pointer stored before it. AArch64 promises neither: the id can
# become visible before the pointer, and the pointer load can be satisfied before
# the id load that is supposed to authorise it. Either way the caller
# dereferences a stale or null lv2_sema*.
#
# This is the same class as the reservation seqlock fences, found the same way -
# by grepping for the *shape* (publish-then-flag) rather than for an ARM path,
# because there is no ARM path to read. It sat in kernel/cellos/, which the
# ledger's "architecture-neutral" sweep never scanned: it searched Emu/Cell/lv2
# and Emu/Cell/Modules, neither of which exists in this fork.
#
# The superpath defaults to disabled, so this is latent rather than live. It is
# still fixed and pinned, because a race reachable by setting one system property
# is not meaningfully safer than one reachable by default, and the failure mode -
# a use-after-free of a destroyed semaphore - is not one to leave armed.

$repoRoot = Split-Path -Parent $PSScriptRoot
$sema = Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_semaphore.cpp"

if (-not (Test-Path $sema)) { throw "sys_semaphore.cpp not found at $sema" }
$source = Get-Content $sema -Raw

# 1. Publish: the id store carries the release.
if ($source -notmatch 'entry\.sema\.store\(sema, std::memory_order_relaxed\);\s*\r?\n\s*entry\.sem_id\.store\(sem_id, std::memory_order_release\);') {
    throw "The fast-cache publish is not a release. The id store must be memory_order_release so any reader observing the id also observes the pointer stored before it; relaxed lets AArch64 make the id visible first."
}

# 2. Read: the id load carries the acquire.
if ($source -notmatch 'entry\.sem_id\.load\(std::memory_order_acquire\) != sem_id') {
    throw "The fast-cache read is not an acquire. The id load must be memory_order_acquire, or the pointer load can be satisfied before the check that authorises it."
}

# 3. The pointer load stays relaxed underneath the acquire, which is the point of
#    the pattern - one ordered access, not two.
if ($source -notmatch 'return entry\.sema\.load\(std::memory_order_relaxed\);') {
    throw "The fast-cache pointer load is no longer relaxed. The acquire on the id is what orders it; promoting this one as well is redundant cost and suggests the pattern has been misunderstood."
}

# 4. Invalidate: acq_rel on the CAS.
if ($source -notmatch 'fast_entry\.sem_id\.compare_exchange_strong\(expected, 0,\s*\r?\n?\s*std::memory_order_acq_rel\)') {
    throw "The fast-cache invalidate CAS is not acq_rel. It must not allow the pointer clear to float above the id clear."
}

# 5. Nothing in the protocol may quietly revert to fully relaxed. Catch the exact
#    original spelling of the publish, which is the likely form of a regression.
if ($source -match 'entry\.sem_id\.store\(sem_id, std::memory_order_relaxed\)') {
    throw "The fast-cache id store is relaxed again. That is the original bug: publish-then-flag with no release."
}
if ($source -match 'entry\.sem_id\.load\(std::memory_order_relaxed\)') {
    throw "The fast-cache id load is relaxed again. That is the read half of the original bug."
}

# 6. The counters beside it must stay relaxed. They are statistics, they
#    participate in no protocol, and ordering them would be pure cost. This is
#    asserted so that a future sweep does not "fix" the whole file uniformly.
if ($source -notmatch 'fast_hits\.fetch_add\(\s*1, std::memory_order_relaxed\)') {
    throw "The fast_hits statistics counter is no longer relaxed. Statistics counters participate in no protocol and must not be promoted; only the id flag carries ordering."
}

Write-Output "Thor semaphore fast-cache ordering contract passed: publish releases, read acquires, invalidate is acq_rel, the pointer load and the statistics counters stay relaxed."
