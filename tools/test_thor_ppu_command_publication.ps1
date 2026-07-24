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

foreach ($fragment in @(
    'cmd_queue[pos] = cmd;',
    'cmd_queue[pos] = *list.begin();',
    'cmd_queue[cmd_queue.peek()].exchange(cmd64{})'
)) {
    if (-not $upstreamSource.Contains($fragment)) {
        throw "Upstream PPU command publication baseline changed: $fragment"
    }
}

Write-Host "Thor Android PPU command publication contract passed."
