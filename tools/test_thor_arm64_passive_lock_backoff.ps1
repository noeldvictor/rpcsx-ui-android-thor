$ErrorActionPreference = "Stop"

# Contract: vm::passive_lock must keep its graduated backoff.
#
# passive_lock waits for g_range_lock_bits[1] to clear, which happens when every
# writer_lock releases. It used a flat busy_wait(200), and 200 ticks of this
# device's 19.2 MHz generic timer is 10.42 us.
#
# Measured on device with the wait profiler, that was roughly ten times longer
# than needed. Instrumenting loop entries separately from backoffs showed the
# mean contended wait resolving in 1.24 iterations: of 61,980 entries in a 1.45 s
# window, 41.2% backed off at all and consumed 31,636 iterations between them. So
# the first backoff was almost always overshooting a lock that had already been
# released, and the site was the second-largest spin source in the emulator at
# 17.5% of all spin.
#
# With i==0 shortened to 20 ticks and i<4 to 50, re-measured:
#
#   spin per contended wait   247.5 -> 37.0 ticks   (-85.1%)
#   cores spinning here       0.227 -> 0.072        (-68.3%)
#
# Two things this test defends, and the second is the reason it exists.
#
#  1. The escalation must stay. Reverting to a flat small constant is NOT the
#     same change. Dividing every busy-wait in the emulator by a fixed factor is
#     what produced a lock convoy and about 1 FPS before, recorded on busy_wait
#     in rx/asm.hpp. The long tail still needs a long wait; only the first
#     iterations may be short.
#  2. The final tier must stay at 200. If someone "simplifies" the ladder to its
#     smallest value, the convoy case returns with no visible symptom until a
#     title contends heavily.

$repoRoot = Split-Path -Parent $PSScriptRoot
$vm = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Memory/vm.cpp"

if (-not (Test-Path $vm)) { throw "vm.cpp not found at $vm" }
$source = Get-Content $vm -Raw

# Bound the search to passive_lock's body so a neighbouring wait loop cannot
# satisfy this. That mistake has been made in this suite before.
$start = $source.IndexOf("void passive_lock(cpu_thread& cpu)")
if ($start -lt 0) { throw "passive_lock definition not found; this test needs updating." }
$tail = $source.Substring($start)
$end = $tail.IndexOf("`n	}")
if ($end -lt 0) { throw "Could not find the end of passive_lock." }
$body = $tail.Substring(0, $end)

# 1. The flat form must be gone.
if ($body -match 'profiled_busy_wait\(thor_wait::site::vm_passive_lock, 200\)') {
    throw "passive_lock is back to a flat busy_wait(200). That is 10.42 us against a mean contended wait of 1.24 iterations, so the first backoff overshoots an already-released lock almost every time."
}

# 2. The graduated ladder must be present, with a short first tier.
if ($body -notmatch 'i == 0 \? 20') {
    throw "passive_lock's first backoff tier is not 20 ticks. The measured win came from shortening the first wait from 10.42 us to about 1 us."
}
if ($body -notmatch 'i < 4 \? 50') {
    throw "passive_lock's middle backoff tier is missing. The ladder is 20 / 50 / 200 by iteration."
}

# 3. The final tier must remain 200. This is the anti-convoy guard.
if ($body -notmatch ':\s*200\)') {
    throw "passive_lock's final backoff tier is no longer 200 ticks. A wait that genuinely lasts must still reach the long backoff; collapsing the ladder to its smallest value is how the lock convoy returns."
}

# 4. The yield fallback past 100 iterations must survive.
if ($body -notmatch 'i < 100' -or $body -notmatch 'std::this_thread::yield\(\)') {
    throw "passive_lock lost its yield fallback after 100 iterations."
}

# 5. The instrumentation that justified the change must stay, so the next person
#    can re-derive it rather than trusting this comment.
foreach ($site in @('vm_passive_lock_enter', 'vm_passive_lock_taken')) {
    if ($body -notmatch [regex]::Escape($site)) {
        throw "passive_lock no longer records $site. Entries and contended-waits must be counted separately, or the 1.24-iterations figure that motivated the ladder cannot be reproduced."
    }
}

Write-Output "Thor passive_lock backoff contract passed: graduated 20/50/200 ladder intact, final tier still 200, yield fallback and entry/taken instrumentation preserved."
