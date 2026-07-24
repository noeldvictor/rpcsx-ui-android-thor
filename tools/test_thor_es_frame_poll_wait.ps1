$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$upstreamRoot = Join-Path $workspaceRoot "rpcs3-upstream"

$mainTimerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_timer.cpp"
$mainRsxHeaderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/RSXThread.h"
$mainRsxSourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/RSXThread.cpp"
$mainPpuHeaderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.h"
$mainRsxMethodsPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_methods.cpp"
$upstreamTimerPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/lv2/sys_timer.cpp"
$upstreamRsxHeaderPath = Join-Path $upstreamRoot "rpcs3/Emu/RSX/RSXThread.h"
$upstreamRsxSourcePath = Join-Path $upstreamRoot "rpcs3/Emu/RSX/RSXThread.cpp"
$upstreamRsxMethodsPath = Join-Path $upstreamRoot "rpcs3/Emu/RSX/rsx_methods.cpp"
$labPath = Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1"
$sprintPath = Join-Path $PSScriptRoot "eternal_sonata_speed_sprint.ps1"

$requiredPaths = @(
    $mainTimerPath,
    $mainRsxHeaderPath,
    $mainRsxSourcePath,
    $mainPpuHeaderPath,
    $mainRsxMethodsPath,
    $upstreamTimerPath,
    $upstreamRsxHeaderPath,
    $upstreamRsxSourcePath,
    $upstreamRsxMethodsPath,
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
$mainPpuHeader = Get-Content -LiteralPath $mainPpuHeaderPath -Raw
$mainRsxMethods = Get-Content -LiteralPath $mainRsxMethodsPath -Raw
$upstreamTimer = Get-Content -LiteralPath $upstreamTimerPath -Raw
$upstreamRsxHeader = Get-Content -LiteralPath $upstreamRsxHeaderPath -Raw
$upstreamRsxSource = Get-Content -LiteralPath $upstreamRsxSourcePath -Raw
$upstreamRsxMethods = Get-Content -LiteralPath $upstreamRsxMethodsPath -Raw
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
    'set_thor_es_vblank_waiter_registered(',
    'renderer->vblank_waiter_registered, true)',
    'thread_ctrl::wait_on(renderer->vblank_wait_token',
    'renderer->vblank_waiter_registered, false)',
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
    if ($timerContract -notmatch 'vblank_waiter_registered' -and
        -not $upstreamTimer.Contains($timerContract)) {
        throw "Windows frame-poll wait is missing a narrow gate or fallback: $timerContract"
    }
}

foreach ($registrationStoreContract in @(
    'set_thor_es_vblank_waiter_registered(atomic_t<bool> &registered',
    'auto &raw = const_cast<uchar &>(registered.raw())',
    '__atomic_store_n(&raw, static_cast<uchar>(value), __ATOMIC_RELAXED)',
    'registered.release(value)'
)) {
    if (-not $mainTimer.Contains($registrationStoreContract)) {
        throw "Android frame-poll registration store contract is missing: $registrationStoreContract"
    }
}

$registrationStoreCalls = [regex]::Matches(
    $mainTimer,
    'set_thor_es_vblank_waiter_registered\(\s*renderer->vblank_waiter_registered,\s*(?:true|false)\)')
if ($registrationStoreCalls.Count -ne 2) {
    throw "Android frame-poll wait must register and clear exactly once; found $($registrationStoreCalls.Count) stores."
}
if ($mainTimer.Contains('renderer->vblank_waiter_registered.release(')) {
    throw 'Android frame-poll wait reintroduced a release registration store.'
}

foreach ($tokenLoadContract in @(
    'u32 observe_thor_es_vblank_wait_token(',
    'const atomic_t<u32> &wait_token) noexcept',
    '  return wait_token.observe();',
    '  return wait_token;',
    'const u32 after_wait_token = renderer->vblank_wait_token'
)) {
    if (-not $mainTimer.Contains($tokenLoadContract)) {
        throw "Android frame-poll token-load contract is missing: $tokenLoadContract"
    }
}

if ($mainTimer -notmatch '(?s)u32 observe_thor_es_vblank_wait_token\(\s*const atomic_t<u32> &wait_token\) noexcept \{\s*#ifdef __ANDROID__.*?return wait_token[.]observe\(\);\s*#else\s*return wait_token;\s*#endif\s*\}') {
    throw 'Android frame-poll token helper must relax only Android pre-wait reads and retain desktop acquire loads.'
}

$relaxedTokenReads = [regex]::Matches(
    $mainTimer,
    'observe_thor_es_vblank_wait_token\(renderer->vblank_wait_token\)')
if ($relaxedTokenReads.Count -ne 2) {
    throw "Android frame-poll wait must use exactly two relaxed pre-wait token reads; found $($relaxedTokenReads.Count)."
}
if ($mainTimer -match 'const u32 after_wait_token\s*=\s*observe_thor_es_vblank_wait_token') {
    throw 'Android frame-poll wait relaxed the post-wait publication read.'
}

foreach ($upstreamTimerContract in @(
    'renderer->vblank_waiters.fetch_add(1)',
    'thread_ctrl::wait_on(renderer->vblank_wait_token',
    'renderer->vblank_waiters.fetch_sub(1)'
)) {
    if (-not $upstreamTimer.Contains($upstreamTimerContract)) {
        throw "Windows frame-poll wait is missing a narrow gate or fallback: $upstreamTimerContract"
    }
}

foreach ($mainContract in @(
    'constexpr u64 thor_es_frame_poll_wait_max_us = 1000',
    'constexpr u64 thor_es_frame_poll_handler_grace_us_default = 500',
    'constexpr u64 thor_es_frame_poll_log_probe_mask = 1023',
    'bool should_probe_thor_es_frame_poll_log() noexcept',
    'const u64 calls = g_thor_es_frame_poll_wait_state.calls',
    'calls == 1 ||',
    '(calls & thor_es_frame_poll_log_probe_mask) == 0',
    'debug.rpcsx.thor.es_frame_wait',
    'debug.rpcsx.thor.es_frame_wait_grace_us',
    'debug.rpcsx.thor.es_frame_wait_continuous_rearm',
    'RPCSX_THOR_ES_FRAME_POLL_WAIT',
    'RPCSX_THOR_ES_FRAME_POLL_HANDLER_GRACE_US',
    'RPCSX_THOR_ES_FRAME_POLL_CONTINUOUS_REARM',
    'RPCS3_ES_FRAME_POLL_WAIT',
    'RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US',
    'RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM',
    'is_thor_es_frame_poll_continuous_rearm_enabled()',
    'state.continuous_rearms++',
    'state.continuous_rearm_timeouts++',
    'state.continuous_rearm_progress++',
    'const u64 handler_grace_us =',
    'after_counter == counter ? get_thor_es_frame_poll_handler_grace_us() : 0',
    'waited_us < handler_grace_us',
    'return false;'
)) {
    if (-not $mainTimer.Contains($mainContract)) {
        throw "Android frame-poll wait is missing its opt-in or bounded-wait contract: $mainContract"
    }
}

$waitFunctionStart = $mainTimer.IndexOf('bool try_thor_es_frame_poll_wait')
$fallbackFunctionStart = $mainTimer.IndexOf(
    'void observe_thor_es_frame_poll_fallback',
    $waitFunctionStart)
if ($waitFunctionStart -lt 0 -or $fallbackFunctionStart -le $waitFunctionStart) {
    throw 'Could not isolate the Android frame-poll wait function.'
}

$waitFunction = $mainTimer.Substring(
    $waitFunctionStart,
    $fallbackFunctionStart - $waitFunctionStart)

if ($waitFunction -match 'waited_us\s*<\s*get_thor_es_frame_poll_handler_grace_us\(\)') {
    throw 'Android frame-poll grace loop reintroduced a static accessor call per wait iteration.'
}
$logCalls = [regex]::Matches(
    $waitFunction,
    '(?m)^\s*log_thor_es_frame_poll_wait\(')
$guardedLogCalls = [regex]::Matches(
    $waitFunction,
    '(?s)if \(should_probe_thor_es_frame_poll_log\(\)\) \{\s*log_thor_es_frame_poll_wait\([^;]+;\s*\}')
if ($logCalls.Count -ne 3 -or $guardedLogCalls.Count -ne $logCalls.Count) {
    throw 'Every Android frame-poll diagnostic logger call must be guarded by the cheap call-count probe.'
}

# The saved 20260719 title proof reached this many exact frame-poll calls.
# One initial probe plus one probe per 1024 calls replaces a clock read on
# every call without delaying the required first activation row.
$representativeCallCount = 93787
$representativeProbeCount = 1 + [math]::Floor($representativeCallCount / 1024)
$representativeReduction = 1.0 - ($representativeProbeCount / $representativeCallCount)
if ($representativeProbeCount -ne 92 -or $representativeReduction -lt 0.999) {
    throw 'The Android frame-poll diagnostic clock throttle lost its representative >99.9% probe reduction.'
}

foreach ($upstreamContract in @(
    'RPCS3_ES_FRAME_POLL_WAIT',
    'RPCS3_ES_FRAME_POLL_WAIT_MAX_US',
    'RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US',
    'RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM',
    'is_es_frame_poll_continuous_rearm_enabled()',
    'state.continuous_rearms++',
    'state.continuous_rearm_timeouts++',
    'state.continuous_rearm_progress++',
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

foreach ($fragment in @(
    'atomic_t<u32> vblank_wait_token{0}',
    'atomic_t<bool> vblank_waiter_registered{false}'
)) {
    if (-not $mainRsxHeader.Contains($fragment)) {
        throw "Android RSX VBlank wait state is missing: $fragment"
    }
}

foreach ($fragment in @(
    'atomic_t<u32> vblank_wait_token{0}',
    'atomic_t<u32> vblank_waiters{0}'
)) {
    if (-not $upstreamRsxHeader.Contains($fragment)) {
        throw "Windows RSX VBlank wait state is missing: $fragment"
    }
}

foreach ($rsxSource in @($mainRsxSource, $upstreamRsxSource)) {
    foreach ($fragment in @(
        'ppu_cmd::ptr_call'
    )) {
        if (-not $rsxSource.Contains($fragment)) {
            throw "RSX VBlank notification is missing: $fragment"
        }
    }

    if ($rsxSource -match 'vblank_count\+\+;\s*vblank_wait_token\+\+;') {
        throw "The frame-poll wait must wake after the guest VBlank handler, not at the raw VBlank edge."
    }
}

$mainHandlerQueue = [regex]::Match(
    $mainRsxSource,
    '(?s)ppu_cmd::lle_call.*?ppu_cmd::ptr_call.*?publish_vblank_wait_completion\(renderer->vblank_wait_token\).*?notify_vblank_waiter\(renderer->vblank_wait_token\).*?ppu_cmd::sleep')
if (-not $mainHandlerQueue.Success) {
    throw "The Android guest VBlank completion marker is not ordered after the handler and before interrupt-thread sleep."
}

$upstreamHandlerQueue = [regex]::Match(
    $upstreamRsxSource,
    '(?s)ppu_cmd::lle_call.*?ppu_cmd::ptr_call.*?vblank_wait_token\+\+.*?vblank_wait_token\.notify_all\(\).*?ppu_cmd::sleep')
if (-not $upstreamHandlerQueue.Success) {
    throw "The Windows guest VBlank completion marker is not ordered after the handler and before interrupt-thread sleep."
}

foreach ($fragment in @(
    'is_vblank_waiter_registered(const atomic_t<bool>& registered) noexcept',
    'return registered.observe()',
    'if (is_vblank_waiter_registered(vblank_waiter_registered))',
    'publish_vblank_wait_completion(renderer->vblank_wait_token)',
    'publish_vblank_wait_completion(vblank_wait_token)',
    'notify_vblank_waiter(renderer->vblank_wait_token)',
    'notify_vblank_waiter(vblank_wait_token)'
)) {
    if (-not $mainRsxSource.Contains($fragment)) {
        throw "Android single-waiter VBlank notification is missing: $fragment"
    }
}

$registrationGateCalls = [regex]::Matches(
    $mainRsxSource,
    'if \(is_vblank_waiter_registered\(vblank_waiter_registered\)\)')
if ($registrationGateCalls.Count -ne 2) {
    throw "Android must retain exactly the queued-handler and fallback registration gates; found $($registrationGateCalls.Count)."
}
if ($mainRsxSource.Contains('if (renderer->vblank_waiter_registered)') -or
    $mainRsxSource.Contains('if (vblank_waiter_registered)')) {
    throw 'Android VBlank handling reintroduced an acquire registration load.'
}

$mainQueuedCompletion = [regex]::Match(
    $mainRsxSource,
    '(?s)ppu_cmd::ptr_call.*?publish_vblank_wait_completion\(renderer->vblank_wait_token\);\s*// This callback is queued only after observing a waiter\..*?notify_vblank_waiter\(renderer->vblank_wait_token\);')
if (-not $mainQueuedCompletion.Success) {
    throw 'Android queued VBlank completion must notify without a second registration load.'
}

foreach ($fragment in @(
    'publish_vblank_wait_completion(atomic_t<u32>& token) noexcept',
    'notify_vblank_waiter(atomic_t<u32>& token) noexcept',
    '#ifdef __ANDROID__',
    '__atomic_fetch_add(&token.raw(), u32{1}, __ATOMIC_RELEASE)',
    'token.notify_one()',
    'token.notify_all()',
    'token++'
)) {
    if (-not $mainRsxSource.Contains($fragment)) {
        throw "Android release-published VBlank completion is missing: $fragment"
    }
}

foreach ($fragment in @(
    'void notify_cmd_ready() noexcept',
    'cmd_notify.release(1)',
    'cmd_notify.store(1)',
    'cmd_notify.notify_one()'
)) {
    if (-not $mainPpuHeader.Contains($fragment)) {
        throw "Android release-published PPU command notification is missing: $fragment"
    }
}

$mainCommandPublish = [regex]::Match(
    $mainRsxSource,
    '(?s)void thread::post_vblank_event.*?intr_thread->cmd_list.*?intr_thread->notify_cmd_ready\(\).*?return;')
if (-not $mainCommandPublish.Success) {
    throw 'Android VBlank command publication is not ordered after queueing and before wake/return.'
}

$mainFlipCommandPublish = [regex]::Match(
    $mainRsxSource,
    '(?s)void thread::handle_emu_flip.*?intr_thread->cmd_list.*?intr_thread->notify_cmd_ready\(\)')
if (-not $mainFlipCommandPublish.Success) {
    throw 'Android flip command publication is not ordered after queueing and before wake.'
}

$mainCommandReadyCalls = [regex]::Matches(
    $mainRsxSource,
    'intr_thread->notify_cmd_ready\(\)')
if ($mainCommandReadyCalls.Count -ne 2) {
    throw "Android must wake exactly the VBlank and flip PPU command waiters in RSXThread; found $($mainCommandReadyCalls.Count)."
}
if ($mainRsxSource.Contains('intr_thread->cmd_notify.store(1)') -or
    $mainRsxSource.Contains('intr_thread->cmd_notify.notify_one()')) {
    throw 'Android RSX thread command publication bypasses the centralized wake contract.'
}

$methodFlipCommandPublish = [regex]::Match(
    $mainRsxMethods,
    '(?s)void flip_command.*?intr_thread->cmd_list.*?intr_thread->notify_cmd_ready\(\).*?RSX\(ctx\)->reset\(\)')
if (-not $methodFlipCommandPublish.Success) {
    throw 'Android GCM flip command publication is not ordered after queueing and before frame completion.'
}

$methodUserCommandPublish = [regex]::Match(
    $mainRsxMethods,
    '(?s)void user_command.*?intr_thread->cmd_list.*?intr_thread->notify_cmd_ready\(\)')
if (-not $methodUserCommandPublish.Success) {
    throw 'Android RSX user command publication is not ordered after queueing and before return.'
}

$methodCommandReadyCalls = [regex]::Matches(
    $mainRsxMethods,
    'intr_thread->notify_cmd_ready\(\)')
if ($methodCommandReadyCalls.Count -ne 2) {
    throw "Android must wake exactly the GCM flip and user command waiters in rsx_methods; found $($methodCommandReadyCalls.Count)."
}
if ($mainRsxMethods.Contains('intr_thread->cmd_notify.store(1)') -or
    $mainRsxMethods.Contains('intr_thread->cmd_notify.notify_one()')) {
    throw 'Android RSX method command publication bypasses the centralized wake contract.'
}
foreach ($fragment in @(
    'publish_vblank_edge(atomic_t<u64>& count) noexcept',
    '__atomic_fetch_add(&count.raw(), u64{1}, __ATOMIC_RELEASE)',
    'count++',
    'publish_vblank_edge(vblank_count)'
)) {
    if (-not $mainRsxSource.Contains($fragment)) {
        throw "Android release-published VBlank edge is missing: $fragment"
    }
}

if ($mainRsxSource -match '(?m)^\s*vblank_count\+\+;') {
    throw 'Android VBlank edge reintroduced a sequentially consistent increment.'
}
if ($mainRsxSource.Contains('renderer->vblank_wait_token.notify_all()') -or
    $mainRsxSource -match '(?m)^\s*vblank_wait_token\.notify_all\(\);') {
    throw 'Android single-waiter completion reintroduced a direct broadcast wake.'
}

if ($mainRsxSource.Contains('renderer->vblank_wait_token++') -or
    $mainRsxSource -match '(?m)^\s*vblank_wait_token\+\+;') {
    throw 'Android VBlank completion reintroduced a sequentially consistent token increment.'
}

if ($mainTimer.Contains('vblank_waiters.fetch_') -or
    $mainRsxHeader.Contains('atomic_t<u32> vblank_waiters')) {
    throw 'Android frame-poll wait reintroduced a read-modify-write waiter counter.'
}

foreach ($fragment in @(
    'vblank_count++',
    'renderer->vblank_wait_token++',
    'vblank_wait_token++',
    'vblank_wait_token.notify_all()',
    'intr_thread->cmd_notify.store(1)',
    'intr_thread->cmd_notify.notify_one()',
    'if (vblank_waiters)'
)) {
    if (-not $upstreamRsxSource.Contains($fragment)) {
        throw "Windows RSX VBlank waiter notification is missing: $fragment"
    }
}

$upstreamCommandStores = [regex]::Matches(
    $upstreamRsxSource,
    'intr_thread->cmd_notify\.store\(1\);')
if ($upstreamCommandStores.Count -ne 2) {
    throw "Windows RSX must retain both VBlank and flip command stores; found $($upstreamCommandStores.Count)."
}

$upstreamMethodStores = [regex]::Matches(
    $upstreamRsxMethods,
    'intr_thread->cmd_notify\.store\(1\);')
$upstreamMethodWakes = [regex]::Matches(
    $upstreamRsxMethods,
    'intr_thread->cmd_notify\.notify_one\(\);')
if ($upstreamMethodStores.Count -ne 2 -or $upstreamMethodWakes.Count -ne 2) {
    throw "Windows RSX methods must retain both flip/user store+wake pairs; found stores=$($upstreamMethodStores.Count), wakes=$($upstreamMethodWakes.Count)."
}
foreach ($fragment in @(
    '[string]$EternalSonataFramePollWait = "Off"',
    '[int]$EternalSonataFramePollHandlerGraceUs = 500',
    '[string]$EternalSonataFramePollContinuousRearm = "Off"',
    '"Wait" { "wait" }',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_WAIT", $esFramePollWaitEnv, "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US", "$EternalSonataFramePollHandlerGraceUs", "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM", $esFramePollContinuousRearmEnv, "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM", $previousEsFramePollContinuousRearm, "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_WAIT", $previousEsFramePollWait, "Process")'
)) {
    if (-not $labSource.Contains($fragment)) {
        throw "Windows lab is missing frame-poll wait plumbing: $fragment"
    }
}

foreach ($fragment in @(
    '[string]$EternalSonataFramePollWait = "Off"',
    '[int]$EternalSonataFramePollHandlerGraceUs = 500',
    '[string]$EternalSonataFramePollContinuousRearm = "Off"',
    'EternalSonataFramePollWait = $EternalSonataFramePollWait',
    'EternalSonataFramePollHandlerGraceUs = $EternalSonataFramePollHandlerGraceUs',
    'EternalSonataFramePollContinuousRearm = $EternalSonataFramePollContinuousRearm',
    'debug.rpcsx.thor.es_frame_wait',
    'debug.rpcsx.thor.es_frame_wait_grace_us',
    'debug.rpcsx.thor.es_frame_wait_continuous_rearm',
    'down:120;wait:250;down:120;wait:250;down:120;wait:800',
    'shot:title-options-selected',
    'shot:options-page',
    'shot:options-hold',
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

Write-Output "Thor Eternal Sonata frame-poll wait contract passed: opt-in gates, 1 ms bound, cached 0-500 us post-handler grace, Android relaxed pre-wait token reads with an acquire post-wait publication read, relaxed-store single-waiter registration with relaxed producer gates, and no redundant callback load, release-published VBlank edge, VBlank/flip commands, and completion generation, one-waiter notification, counter-progress rearm, Android 1/1024 diagnostic call/clock sampling, Android/Windows continuous rearm, and fallback plumbing are intact."
