$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/logs.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredFragments = @(
    "constexpr atomic_wait_timeout s_android_log_writer_liveness_timeout{1'000'000'000};",
    'atomic_t<u32> m_writer_waiting{0};',
    'void wake_writer()',
    'm_writer_waiting.load() && m_writer_waiting.exchange(0)',
    'm_writer_waiting.notify_one();',
    'm_writer_waiting = 1;',
    'if (m_buf != bufv || m_out == umax)',
    'm_writer_waiting.wait(1, s_android_log_writer_liveness_timeout);',
    'std::this_thread::sleep_for(10ms);'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "Android event-driven log writer lost required behavior: $fragment"
    }
}

$wake = [regex]::Match(
    $source,
    'void wake_writer\(\)\s*\{(?<body>[\s\S]*?)\r?\n\s*\}'
).Groups['body'].Value

if ([string]::IsNullOrWhiteSpace($wake) -or
    $wake -notmatch 'if \(m_writer_waiting\.load\(\) && m_writer_waiting\.exchange\(0\)\)\s*\{\s*m_writer_waiting\.notify_one\(\);') {
    throw "Writer wake must avoid notification unless the Android writer is armed."
}

if ($source -notmatch 'm_writer_waiting = 1;\s*if \(m_buf != bufv \|\| m_out == umax\)\s*\{\s*m_writer_waiting = 0;\s*continue;\s*\}\s*m_writer_waiting\.wait\(1, s_android_log_writer_liveness_timeout\);\s*m_writer_waiting = 0;') {
    throw "Writer wait no longer arms before rechecking work/shutdown, uses its one-second liveness bound, or clears after waking."
}

$commitIndex = $source.IndexOf('m_buf += (size * s_log_size) - size;')
$commitWakeIndex = $source.IndexOf('wake_writer();', $commitIndex)
$commitBreakIndex = $source.IndexOf('break;', $commitWakeIndex)
if ($commitIndex -lt 0 -or $commitWakeIndex -le $commitIndex -or
    $commitBreakIndex -le $commitWakeIndex) {
    throw "Log enqueue must notify only after the ring-buffer commit and before returning."
}

$shutdownIndex = $source.IndexOf('m_out = -1;')
$shutdownWakeIndex = $source.IndexOf('wake_writer();', $shutdownIndex)
$joinIndex = $source.IndexOf('m_writer.join();', $shutdownIndex)
if ($shutdownIndex -lt 0 -or $shutdownWakeIndex -le $shutdownIndex -or
    $joinIndex -le $shutdownWakeIndex) {
    throw "Logger shutdown must wake the idle writer before joining it."
}

$syncIndex = $source.IndexOf('void logs::file_writer::sync()')
$syncWakeIndex = $source.IndexOf('wake_writer();', $syncIndex)
$syncWaitIndex = $source.IndexOf('while ((m_out % s_log_size)', $syncIndex)
if ($syncIndex -lt 0 -or $syncWakeIndex -le $syncIndex -or
    $syncWaitIndex -le $syncWakeIndex) {
    throw "Explicit Android log synchronization must wake the event-driven writer before waiting."
}

# Prove event-only lines compile only for Android while the original timed poll
# remains in the desktop branch.
$frames = [System.Collections.Generic.List[object]]::new()
$lines = $source -split "\r?\n"
for ($index = 0; $index -lt $lines.Count; $index++) {
    $line = $lines[$index]
    $trimmed = $line.Trim()

    if ($trimmed -match '^#\s*ifdef\s+ANDROID\s*$') {
        $frames.Add([pscustomobject]@{
            Kind = 'ifdef-android'
            AndroidOnly = $true
            DesktopOnly = $false
        })
        continue
    }

    if ($trimmed -match '^#\s*ifndef\s+ANDROID\s*$') {
        $frames.Add([pscustomobject]@{
            Kind = 'ifndef-android'
            AndroidOnly = $false
            DesktopOnly = $true
        })
        continue
    }

    if ($trimmed -match '^#\s*(?:if|ifdef|ifndef)\b') {
        $frames.Add([pscustomobject]@{
            Kind = 'other'
            AndroidOnly = $false
            DesktopOnly = $false
        })
        continue
    }

    if ($trimmed -match '^#\s*(?:else|elif)\b') {
        if ($frames.Count -eq 0) {
            throw "Unbalanced preprocessor branch at logs.cpp:$($index + 1)."
        }

        $frame = $frames[$frames.Count - 1]
        if ($trimmed -match '^#\s*else\b') {
            if ($frame.Kind -eq 'ifdef-android') {
                $frame.AndroidOnly = $false
                $frame.DesktopOnly = $true
            } elseif ($frame.Kind -eq 'ifndef-android') {
                $frame.AndroidOnly = $true
                $frame.DesktopOnly = $false
            }
        } else {
            $frame.AndroidOnly = $false
            $frame.DesktopOnly = $false
        }
        continue
    }

    if ($trimmed -match '^#\s*endif\b') {
        if ($frames.Count -eq 0) {
            throw "Unbalanced preprocessor end at logs.cpp:$($index + 1)."
        }

        $frames.RemoveAt($frames.Count - 1)
        continue
    }

    $isAndroidOnly = $false
    $isDesktopOnly = $false
    foreach ($frame in $frames) {
        $isAndroidOnly = $isAndroidOnly -or $frame.AndroidOnly
        $isDesktopOnly = $isDesktopOnly -or $frame.DesktopOnly
    }

    if ($line -match 'm_writer_waiting|wake_writer\(|s_android_log_writer_liveness_timeout' -and -not $isAndroidOnly) {
        throw "Android event-wake state leaked into desktop at logs.cpp:$($index + 1): $trimmed"
    }

    if ($line.Contains('std::this_thread::sleep_for(10ms);') -and -not $isDesktopOnly) {
        throw "Android still compiles the fixed 10 ms idle poll at logs.cpp:$($index + 1)."
    }
}

if ($frames.Count -ne 0) {
    throw "Unbalanced preprocessor directives in logs.cpp."
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $PSCommandPath,
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -ne 0) {
    throw "PowerShell contract parse failed: $($errors[0].Message)"
}

Write-Output "Thor Android event-driven log writer contract passed: work commits wake immediately, explicit sync wakes before waiting, desktop keeps its original poll, and shutdown cannot strand the writer."
