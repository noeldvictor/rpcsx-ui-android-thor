$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$syncPath = Join-Path $repoRoot "app\src\main\cpp\rpcsx\ps3fw\cellSync.cpp"
$spursPath = Join-Path $repoRoot "app\src\main\cpp\rpcsx\ps3fw\cellSpurs.cpp"
$sync = Get-Content -LiteralPath $syncPath -Raw
$spurs = Get-Content -LiteralPath $spursPath -Raw

$requiredSyncFragments = @(
    'const s32 reserved = +push.m_h8;',
    'push.m_h8 = static_cast<u16>(next);',
    'const u16 completed = static_cast<u16>(+push.m_h6 | (1u << (15 - distance)));',
    'push.m_h5 = static_cast<u16>(published);',
    'token = queue->m_hs1[slot];',
    'pop.m_h3 = static_cast<u16>((pack & 0x83ff) | (next << 10));',
    'thor_spurs_notify_lfq(ppu, queue->m_eaSignal.addr(), token)'
)

foreach ($fragment in $requiredSyncFragments) {
    if (-not $sync.Contains($fragment)) {
        throw "The firmware LFQueue contract is missing from cellSync.cpp: $fragment"
    }
}

$requiredSpursFragments = @(
    's32 thor_spurs_notify_lfq(ppu_thread& ppu, u32 ea_signal, u32 token)',
    'vm::ptr<CellSpurs>::make(ea_signal & ~0xfu)',
    '(token >> 8) & 0xffffff',
    'return _cellSpursSendSignal(ppu, taskset, task_id);'
)

foreach ($fragment in $requiredSpursFragments) {
    if (-not $spurs.Contains($fragment)) {
        throw "The firmware SPURS notifier contract is missing from cellSpurs.cpp: $fragment"
    }
}

if ($sync.Contains('thor_spurs_wake_lfq_waiter(ppu, ea)')) {
    throw "The ANY2ANY completion path still uses the old direct waiter scan."
}

function Complete-Reservation {
    param(
        [int]$Published,
        [int]$Mask,
        [int]$Pointer,
        [int]$Depth
    )

    $distance = $Pointer - $Published
    if ($distance -lt 0) {
        $distance += $Depth * 2
    }
    if ($distance -ge 16) {
        throw "The test reservation is outside the completion window."
    }

    $completed = $Mask -bor (1 -shl (15 - $distance))
    $advance = 0
    while ($advance -lt 16 -and ($completed -band (0x8000 -shr $advance)) -ne 0) {
        $advance++
    }

    $newPublished = $Published + $advance
    if ($newPublished -ge $Depth * 2) {
        $newPublished -= $Depth * 2
    }

    return @($newPublished, (($completed -shl $advance) -band 0xffff), $advance)
}

$inOrder = Complete-Reservation -Published 0 -Mask 0 -Pointer 0 -Depth 16
if ($inOrder[0] -ne 1 -or $inOrder[1] -ne 0 -or $inOrder[2] -ne 1) {
    throw "An in-order completion did not publish one entry."
}

$outOfOrder = Complete-Reservation -Published 0 -Mask 0 -Pointer 1 -Depth 16
if ($outOfOrder[0] -ne 0 -or $outOfOrder[1] -ne 0x4000 -or $outOfOrder[2] -ne 0) {
    throw "An out-of-order completion became visible too early."
}

$joined = Complete-Reservation -Published $outOfOrder[0] -Mask $outOfOrder[1] -Pointer 0 -Depth 16
if ($joined[0] -ne 2 -or $joined[1] -ne 0 -or $joined[2] -ne 2) {
    throw "A contiguous completion pair did not publish together."
}

$wrapped = Complete-Reservation -Published 31 -Mask 0 -Pointer 31 -Depth 16
if ($wrapped[0] -ne 0 -or $wrapped[1] -ne 0 -or $wrapped[2] -ne 1) {
    throw "The published counter did not wrap at two times the depth."
}

$pack = 0x0001
$head = ($pack -shr 10) -band 0x1f
$tail = $pack -band 0x1f
$next = if ($head -eq 0x1d) { 0 } else { $head + 1 }
$consumed = ($pack -band 0x83ff) -bor ($next -shl 10)
if ((($consumed -shr 10) -band 0x1f) -ne $tail) {
    throw "The pending pop token did not retire."
}

Write-Output "Thor ANY2ANY LFQueue firmware contract passed."
