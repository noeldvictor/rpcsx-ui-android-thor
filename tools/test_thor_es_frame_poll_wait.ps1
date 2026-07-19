$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$upstreamRoot = Join-Path $workspaceRoot "rpcs3-upstream"

$mainTimerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_timer.cpp"
$mainRsxHeaderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/RSXThread.h"
$mainRsxSourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/RSXThread.cpp"
$upstreamTimerPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/lv2/sys_timer.cpp"
$upstreamRsxHeaderPath = Join-Path $upstreamRoot "rpcs3/Emu/RSX/RSXThread.h"
$upstreamRsxSourcePath = Join-Path $upstreamRoot "rpcs3/Emu/RSX/RSXThread.cpp"
$labPath = Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1"
$sprintPath = Join-Path $PSScriptRoot "eternal_sonata_speed_sprint.ps1"

$requiredPaths = @(
    $mainTimerPath,
    $mainRsxHeaderPath,
    $mainRsxSourcePath,
    $upstreamTimerPath,
    $upstreamRsxHeaderPath,
    $upstreamRsxSourcePath,
    $labPath,
    $sprintPath
)

foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Eternal Sonata frame-poll wait dependency: $path"
    }
}

$mainTimer = Get-Content -LiteralPath $mainTimerPath -Raw
$mainRsxHeader = Get-Content -LiteralPath $mainRsxHeaderPath -Raw
$mainRsxSource = Get-Content -LiteralPath $mainRsxSourcePath -Raw
$upstreamTimer = Get-Content -LiteralPath $upstreamTimerPath -Raw
$upstreamRsxHeader = Get-Content -LiteralPath $upstreamRsxHeaderPath -Raw
$upstreamRsxSource = Get-Content -LiteralPath $upstreamRsxSourcePath -Raw
$labSource = Get-Content -LiteralPath $labPath -Raw
$sprintSource = Get-Content -LiteralPath $sprintPath -Raw

foreach ($timerContract in @(
    'Emu.GetTitleID() != "BLUS30161"',
    'ppu.id != 0x01000000',
    'ppu.cia != 0x002a8300',
    'sleep_time != 100',
    'const u32 object_addr = static_cast<u32>(ppu.gpr[28])',
    'const u32 frame_config_addr = static_cast<u32>(ppu.gpr[31])',
    'frame_config_addr != object_addr + 4',
    'vm::check_addr(frame_config_addr + 0x260)',
    'const u8 divisor = vm::read8(frame_config_addr + 0x260)',
    'divisor != 30 && divisor != 60',
    'const u32 threshold = 60 / divisor',
    'counter >= threshold',
    'renderer->vblank_waiters.fetch_add(1)',
    'thread_ctrl::wait_on(renderer->vblank_wait_token',
    'renderer->vblank_waiters.fetch_sub(1)',
    'const u32 after_wait_token = renderer->vblank_wait_token',
    'state.handler_wakes++',
    'state.handler_grace_waits++',
    'state.counter_progress_after_grace++',
    'thread_ctrl::wait_for(100)',
    'if (after_counter != counter)',
    'state.completed_vblank = after_vblank',
    'state.fallback_rearms++'
)) {
    if (-not $mainTimer.Contains($timerContract)) {
        throw "Android frame-poll wait is missing a narrow gate or fallback: $timerContract"
    }
    if (-not $upstreamTimer.Contains($timerContract)) {
        throw "Windows frame-poll wait is missing a narrow gate or fallback: $timerContract"
    }
}

foreach ($mainContract in @(
    'constexpr u64 thor_es_frame_poll_wait_max_us = 1000',
    'constexpr u64 thor_es_frame_poll_handler_grace_us_default = 500',
    'debug.rpcsx.thor.es_frame_wait',
    'debug.rpcsx.thor.es_frame_wait_grace_us',
    'RPCSX_THOR_ES_FRAME_POLL_WAIT',
    'RPCSX_THOR_ES_FRAME_POLL_HANDLER_GRACE_US',
    'RPCS3_ES_FRAME_POLL_WAIT',
    'RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US',
    'return false;'
)) {
    if (-not $mainTimer.Contains($mainContract)) {
        throw "Android frame-poll wait is missing its opt-in or bounded-wait contract: $mainContract"
    }
}

foreach ($upstreamContract in @(
    'RPCS3_ES_FRAME_POLL_WAIT',
    'RPCS3_ES_FRAME_POLL_WAIT_MAX_US',
    'RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US',
    'std::clamp<u64>(parsed, 100, 1000)',
    'std::clamp<u64>(parsed, 0, 500)',
    'return 1000ull'
)) {
    if (-not $upstreamTimer.Contains($upstreamContract)) {
        throw "Windows frame-poll wait is missing its opt-in or bounded-wait contract: $upstreamContract"
    }
}

foreach ($source in @($mainTimer, $upstreamTimer)) {
    if ($source.Contains('futex_waitv')) {
        throw "The frame-poll path must use the portable 32-bit atomic wait, not futex_waitv."
    }
}

foreach ($rsxHeader in @($mainRsxHeader, $upstreamRsxHeader)) {
    foreach ($fragment in @(
        'atomic_t<u32> vblank_wait_token{0}',
        'atomic_t<u32> vblank_waiters{0}'
    )) {
        if (-not $rsxHeader.Contains($fragment)) {
            throw "RSX VBlank wait state is missing: $fragment"
        }
    }
}

foreach ($rsxSource in @($mainRsxSource, $upstreamRsxSource)) {
    foreach ($fragment in @(
        'ppu_cmd::ptr_call',
        'renderer->vblank_wait_token++',
        'vblank_wait_token++',
        'if (vblank_waiters)',
        'vblank_wait_token.notify_all()'
    )) {
        if (-not $rsxSource.Contains($fragment)) {
            throw "RSX VBlank notification is missing: $fragment"
        }
    }

    if ($rsxSource -match 'vblank_count\+\+;\s*vblank_wait_token\+\+;') {
        throw "The frame-poll wait must wake after the guest VBlank handler, not at the raw VBlank edge."
    }

    $handlerQueue = [regex]::Match(
        $rsxSource,
        '(?s)ppu_cmd::lle_call.*?ppu_cmd::ptr_call.*?vblank_wait_token\+\+.*?vblank_wait_token\.notify_all\(\).*?ppu_cmd::sleep')
    if (-not $handlerQueue.Success) {
        throw "The guest VBlank completion marker is not ordered after the handler and before interrupt-thread sleep."
    }
}

foreach ($fragment in @(
    '[string]$EternalSonataFramePollWait = "Off"',
    '[int]$EternalSonataFramePollHandlerGraceUs = 500',
    '"Wait" { "wait" }',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_WAIT", $esFramePollWaitEnv, "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US", "$EternalSonataFramePollHandlerGraceUs", "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_WAIT", $previousEsFramePollWait, "Process")'
)) {
    if (-not $labSource.Contains($fragment)) {
        throw "Windows lab is missing frame-poll wait plumbing: $fragment"
    }
}

foreach ($fragment in @(
    '[string]$EternalSonataFramePollWait = "Off"',
    '[int]$EternalSonataFramePollHandlerGraceUs = 500',
    'EternalSonataFramePollWait = $EternalSonataFramePollWait',
    'EternalSonataFramePollHandlerGraceUs = $EternalSonataFramePollHandlerGraceUs',
    'debug.rpcsx.thor.es_frame_wait',
    'debug.rpcsx.thor.es_frame_wait_grace_us',
    '$framePollWaitMode'
)) {
    if (-not $sprintSource.Contains($fragment)) {
        throw "Speed sprint is missing frame-poll wait plumbing: $fragment"
    }
}

foreach ($path in @($labPath, $sprintPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw ("PowerShell parse failure in {0}: {1}" -f $path, $errors[0].Message)
    }
}

Write-Output "Thor Eternal Sonata frame-poll wait contract passed: opt-in gates, 1 ms bound, 0-500 us post-handler grace, completion notification, counter-progress rearm, and fallback plumbing are intact."
