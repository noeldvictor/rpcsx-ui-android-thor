$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$upstreamRoot = Join-Path $workspaceRoot "rpcs3-upstream"

$mainPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
$upstreamPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/PPUThread.cpp"

foreach ($path in @($mainPath, $upstreamPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PPU command publication dependency: $path"
    }
}

$mainSource = Get-Content -LiteralPath $mainPath -Raw
$upstreamSource = Get-Content -LiteralPath $upstreamPath -Raw

foreach ($fragment in @(
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
    '(?s)void ppu_thread::cmd_push\(cmd64 cmd\).*?cmd_queue\.push_begin\(\).*?publish_ppu_command_head\(cmd_queue\[pos\], cmd\);')
if (-not $pushPublish.Success) {
    throw 'cmd_push does not publish its reserved command head.'
}

$listPublish = [regex]::Match(
    $mainSource,
    '(?s)void ppu_thread::cmd_list\(std::initializer_list<cmd64> list\).*?cmd_queue\.push_begin.*?cmd_queue\[pos \+ i\]\.raw\(\) = list\.begin\(\)\[i\];.*?publish_ppu_command_head\(cmd_queue\[pos\], \*list\.begin\(\)\);')
if (-not $listPublish.Success) {
    throw 'cmd_list does not publish its command head after the relaxed tail.'
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
    'cmd_queue[pos] = cmd;',
    'cmd_queue[pos] = *list.begin();',
    'cmd_queue[cmd_queue.peek()].exchange(cmd64{})',
    'cmd_notify = 0;'
)) {
    if (-not $upstreamSource.Contains($fragment)) {
        throw "Upstream PPU command publication baseline changed: $fragment"
    }
}

Write-Host "Thor Android PPU command publication/clear contract passed."
