$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$upstreamRoot = Join-Path $workspaceRoot "rpcs3-upstream"

$mainPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
$mainLocklessPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/lockless.h"
$upstreamPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/PPUThread.cpp"
$upstreamLocklessPath = Join-Path $upstreamRoot "Utilities/lockless.h"

foreach ($path in @($mainPath, $mainLocklessPath, $upstreamPath, $upstreamLocklessPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PPU command publication dependency: $path"
    }
}

$mainSource = Get-Content -LiteralPath $mainPath -Raw
$mainLockless = Get-Content -LiteralPath $mainLocklessPath -Raw
$upstreamSource = Get-Content -LiteralPath $upstreamPath -Raw
$upstreamLockless = Get-Content -LiteralPath $upstreamLocklessPath -Raw

foreach ($fragment in @(
    'reserve_ppu_command_slots(lf_fifo<atomic_t<cmd64>, 127>& queue, u32 count = 1) noexcept',
    'queue.push_begin_relaxed(count)',
    'queue.push_begin(count)',
    'complete_ppu_command_slots(lf_fifo<atomic_t<cmd64>, 127>& queue, u32 count) noexcept',
    'queue.pop_end_release(count)',
    'queue.pop_end(count)',
    'complete_ppu_command_slots(cmd_queue, count + 1)',
    'publish_ppu_command_head(atomic_t<cmd64>& slot, cmd64 command) noexcept',
    '#ifdef __ANDROID__',
    'slot.release(command)',
    'slot = command',
    'clear_ppu_command_ready(atomic_t<u32>& notify) noexcept',
    'notify.release(0)',
    'notify = 0',
    'cmd_queue[pos + i].raw() = list.begin()[i]',
    'cmd_queue[cmd_queue.peek()].exchange(cmd64{})'
)) {
    if (-not $mainSource.Contains($fragment)) {
        throw "Android PPU command publication contract is missing: $fragment"
    }
}

$reservationCalls = [regex]::Matches(
    $mainSource,
    'reserve_ppu_command_slots\(cmd_queue')
if ($reservationCalls.Count -ne 2) {
    throw "Android must relaxed-reserve exactly cmd_push and cmd_list queue ranges; found $($reservationCalls.Count)."
}
if ($mainSource.Contains('cmd_queue.push_begin(')) {
    throw 'Android PPU command publication bypasses the PPU-only relaxed reservation helper.'
}

foreach ($fragment in @(
    '#ifdef __ANDROID__',
    'u32 push_begin_relaxed(u32 count = 1)',
    '__atomic_fetch_add(&m_ctrl.raw(), u64{count}, __ATOMIC_RELAXED)',
    'u32 pop_end_release(u32 count = 1)',
    '__atomic_load_n(&m_ctrl.raw(), __ATOMIC_RELAXED)',
    '__atomic_compare_exchange_n(&m_ctrl.raw(), &ctrl, next, false, __ATOMIC_RELEASE, __ATOMIC_RELAXED)',
    'm_ctrl.fetch_add(count)',
    'm_ctrl.atomic_op([&](u64& ctrl)'
)) {
    if (-not $mainLockless.Contains($fragment)) {
        throw "Android PPU queue reservation contract is missing: $fragment"
    }
}
if ($upstreamLockless.Contains('push_begin_relaxed')) {
    throw 'Desktop upstream unexpectedly contains the Android-only relaxed FIFO reservation.'
}
if ($upstreamLockless.Contains('pop_end_release')) {
    throw 'Desktop upstream unexpectedly contains the Android-only release FIFO completion.'
}

$publishCalls = [regex]::Matches(
    $mainSource,
    'publish_ppu_command_head\(cmd_queue\[pos\],')
if ($publishCalls.Count -ne 2) {
    throw "Android must release-publish exactly cmd_push and cmd_list command heads; found $($publishCalls.Count)."
}

if ($mainSource.Contains('cmd_queue[pos] = cmd;') -or
    $mainSource.Contains('cmd_queue[pos] = *list.begin();')) {
    throw 'Android PPU command publication reintroduced a sequentially consistent head exchange.'
}

$pushPublish = [regex]::Match(
    $mainSource,
    '(?s)void ppu_thread::cmd_push\(cmd64 cmd\).*?reserve_ppu_command_slots\(cmd_queue\).*?publish_ppu_command_head\(cmd_queue\[pos\], cmd\);')
if (-not $pushPublish.Success) {
    throw 'cmd_push does not publish its reserved command head.'
}

$listPublish = [regex]::Match(
    $mainSource,
    '(?s)void ppu_thread::cmd_list\(std::initializer_list<cmd64> list\).*?reserve_ppu_command_slots\(cmd_queue, static_cast<u32>\(list\.size\(\)\)\).*?cmd_queue\[pos \+ i\]\.raw\(\) = list\.begin\(\)\[i\];.*?publish_ppu_command_head\(cmd_queue\[pos\], \*list\.begin\(\)\);')
if (-not $listPublish.Success) {
    throw 'cmd_list does not publish its command head after the relaxed tail.'
}

$completionCalls = [regex]::Matches(
    $mainSource,
    'complete_ppu_command_slots\(cmd_queue, count \+ 1\)')
if ($completionCalls.Count -ne 1) {
    throw "Android must release-complete exactly one PPU command queue range; found $($completionCalls.Count)."
}
if ($mainSource.Contains('cmd_queue.pop_end(count + 1);')) {
    throw 'Android PPU command completion bypasses the PPU-only release helper.'
}

$popCompletion = [regex]::Match(
    $mainSource,
    '(?s)void ppu_thread::cmd_pop\(u32 count\).*?cmd_queue\[pos \+ i\]\.raw\(\) = cmd64\{\};.*?complete_ppu_command_slots\(cmd_queue, count \+ 1\);')
if (-not $popCompletion.Success) {
    throw 'cmd_pop does not clear command tails before release-completing the queue range.'
}

$clearCalls = [regex]::Matches(
    $mainSource,
    'clear_ppu_command_ready\(cmd_notify\)')
if ($clearCalls.Count -ne 1) {
    throw "Android must clear exactly one PPU command-ready flag after waiting; found $($clearCalls.Count)."
}

$waitClear = [regex]::Match(
    $mainSource,
    '(?s)cmd64 ppu_thread::cmd_wait\(\).*?cmd_queue\[cmd_queue\.peek\(\)\]\.exchange\(cmd64\{\}\).*?thread_ctrl::wait_on\(cmd_notify, 0\);.*?clear_ppu_command_ready\(cmd_notify\);')
if (-not $waitClear.Success) {
    throw 'cmd_wait does not acquire the queue head before wait and one-way flag clear.'
}

if ($mainSource.Contains('cmd_notify = 0;')) {
    throw 'Android PPU command wait reintroduced a sequentially consistent notification clear.'
}

foreach ($fragment in @(
    'cmd_queue.push_begin();',
    'cmd_queue.push_begin(static_cast<u32>(list.size()));',
    'cmd_queue[pos] = cmd;',
    'cmd_queue[pos] = *list.begin();',
    'cmd_queue[cmd_queue.peek()].exchange(cmd64{})',
    'cmd_queue.pop_end(count + 1);',
    'cmd_notify = 0;'
)) {
    if (-not $upstreamSource.Contains($fragment)) {
        throw "Upstream PPU command publication baseline changed: $fragment"
    }
}

Write-Host "Thor Android PPU command reservation/publication/clear contract passed."
