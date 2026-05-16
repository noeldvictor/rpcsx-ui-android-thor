param(
    [ValidateSet("Profile", "BuildInstall", "Start", "Summarize", "Capture", "Stop", "Auto")]
    [string]$Action = "Auto",
    [string]$Label = "thor-ooda",
    [string]$Profile = "default",
    [string]$Package = "net.rpcsx.easy",
    [string]$Mode = "",
    [string]$Symptom = "",
    [int]$LogcatLines = 0,
    [int]$SummaryTailLines = 0,
    [int]$StreamPollSeconds = 0,
    [string]$PostMode = "",
    [int]$GhidraWaitSeconds = -1,
    [switch]$NoBuildInstall,
    [switch]$NoLaunch,
    [switch]$NoGhidra,
    [switch]$NoIssueCommit,
    [switch]$KeepLogging
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$RepoRoot = Get-ThorRepoRoot
$Adb = Resolve-ThorAdb
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeLabel = New-ThorSafeLabel $Label
$profilePath = Join-Path $RepoRoot (Join-Path "debug-profiles" "$Profile.json")

function Read-OodaProfile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Missing OODA profile: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-OodaProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return $Default
    }

    return $prop.Value
}

function Get-OodaIntProperty {
    param(
        [object]$Object,
        [string]$Name,
        [int]$Default
    )

    $value = Get-OodaProperty $Object $Name $null
    if ($null -eq $value) {
        return $Default
    }

    try {
        return [int]$value
    } catch {
        return $Default
    }
}

function Get-OodaGitText {
    param([string[]]$GitArgs)

    try {
        return ((& git -C $RepoRoot @GitArgs 2>$null) -join "`n").Trim()
    } catch {
        return ""
    }
}

function Get-OodaAdbText {
    param([string[]]$AdbArgs)

    try {
        return ((& $Adb @AdbArgs 2>$null) -join "`n").Trim()
    } catch {
        return ""
    }
}

function New-OodaIssue {
    param(
        [object]$ProfileObject,
        [string]$EffectiveMode,
        [System.Collections.IDictionary]$EffectiveSettings
    )

    $issueId = "$stamp-$safeLabel"
    $issueDir = Join-Path $RepoRoot (Join-Path "debug-issues" $issueId)
    New-Item -ItemType Directory -Force -Path $issueDir | Out-Null

    return [ordered]@{
        id = $issueId
        created = (Get-Date -Format o)
        action = $Action
        label = $safeLabel
        symptom = $Symptom
        package = $Package
        profile = (Get-OodaProperty $ProfileObject "name" $Profile)
        profilePath = $profilePath
        mode = $EffectiveMode
        status = "started"
        failure = ""
        settings = $EffectiveSettings
        repo = [ordered]@{
            head = (Get-OodaGitText @("rev-parse", "--short", "HEAD"))
            branch = (Get-OodaGitText @("branch", "--show-current"))
            status = (Get-OodaGitText @("status", "--short"))
        }
        apk = [ordered]@{}
        device = [ordered]@{}
        captures = @()
        summaries = @()
        quickRead = @()
        ghidra = @()
        nextAction = ""
        issueDir = $issueDir
    }
}

function Save-OodaIssue {
    param([System.Collections.IDictionary]$Issue)

    $issueDir = $Issue["issueDir"]
    $jsonPath = Join-Path $issueDir "issue.json"
    $mdPath = Join-Path $issueDir "issue.md"

    $jsonIssue = [ordered]@{}
    foreach ($key in $Issue.Keys) {
        if ($key -ne "issueDir") {
            $jsonIssue[$key] = $Issue[$key]
        }
    }

    $jsonIssue | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $captureLines = @()
    foreach ($capture in @($Issue["captures"])) {
        $captureLines += "- $capture"
    }
    if ($captureLines.Count -eq 0) {
        $captureLines = @("- none yet")
    }

    $summaryLines = @()
    foreach ($summary in @($Issue["summaries"])) {
        $summaryLines += "- $summary"
    }
    if ($summaryLines.Count -eq 0) {
        $summaryLines = @("- none yet")
    }

    $quickReadLines = @()
    foreach ($line in @($Issue["quickRead"])) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            $quickReadLines += "- $line"
        }
    }
    if ($quickReadLines.Count -eq 0) {
        $quickReadLines = @("- no triage summary yet")
    }

    $ghidraLines = @()
    foreach ($g in @($Issue["ghidra"])) {
        $ghidraLines += "- $g"
    }
    if ($ghidraLines.Count -eq 0) {
        $ghidraLines = @("- none yet")
    }

    @(
        "# Thor OODA Issue $($Issue["id"])",
        "",
        "- Created: $($Issue["created"])",
        "- Action: $($Issue["action"])",
        "- Label: $($Issue["label"])",
        "- Profile: $($Issue["profile"])",
        "- Mode: $($Issue["mode"])",
        "- Status: $($Issue["status"])",
        "- Package: $($Issue["package"])",
        "- Repo: $($Issue["repo"]["head"]) on $($Issue["repo"]["branch"])",
        "- Symptom: $($Issue["symptom"])",
        "- Logcat Lines: $($Issue["settings"]["logcatLines"])",
        "- Stream Poll Seconds: $($Issue["settings"]["streamPollSeconds"])",
        "- Post Mode: $($Issue["settings"]["postMode"])",
        "",
        "## Captures",
        $captureLines,
        "",
        "## Summaries",
        $summaryLines,
        "",
        "## Quick Read",
        $quickReadLines,
        "",
        "## Ghidra",
        $ghidraLines,
        "",
        "## Next Action",
        "",
        $Issue["nextAction"],
        "",
        "## Notes",
        "",
        '- Raw captures stay in ignored `debug-captures/`.',
        "- Commit this issue folder after each OODA run."
    ) | Set-Content -LiteralPath $mdPath -Encoding UTF8
}

function Commit-OodaIssue {
    param([System.Collections.IDictionary]$Issue)

    if ($NoIssueCommit) {
        return
    }

    $issueDir = [string]$Issue["issueDir"]
    $preStaged = Get-OodaGitText @("diff", "--cached", "--name-only")
    if (-not [string]::IsNullOrWhiteSpace($preStaged)) {
        Write-Warning "Skipping issue auto-commit because files are already staged."
        return
    }

    & git -C $RepoRoot add -- $issueDir | Out-Null
    & git -C $RepoRoot commit -m "Record Thor OODA issue $($Issue["id"])" | Out-Host
    if ($LASTEXITCODE -eq 0) {
        & git -C $RepoRoot push origin master | Out-Host
    }
}

function Add-OodaListValue {
    param(
        [System.Collections.IDictionary]$Issue,
        [string]$Key,
        [object]$Value
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [array]) {
        foreach ($item in $Value) {
            Add-OodaListValue $Issue $Key $item
        }
        return
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return
    }

    if (@($Issue[$Key]) -notcontains $text) {
        $Issue[$Key] = @($Issue[$Key]) + $text
    }
}

function Get-OodaTailText {
    param(
        [string]$Path,
        [int]$Lines = 80
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    return @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue)
}

function Test-OodaAnyPattern {
    param(
        [string[]]$Lines,
        [string[]]$Patterns
    )

    $text = ($Lines -join "`n")
    foreach ($pattern in $Patterns) {
        if ($text -match $pattern) {
            return $true
        }
    }

    return $false
}

function Get-OodaMarkdownSection {
    param(
        [string]$Path,
        [string]$Section,
        [int]$MaxLines = 12
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    $lines = @(Get-Content -LiteralPath $Path)
    $result = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($line in $lines) {
        if ($line -match "^##\s+$([regex]::Escape($Section))\s*$") {
            $inside = $true
            continue
        }

        if ($inside -and $line -match "^##\s+") {
            break
        }

        if ($inside -and -not [string]::IsNullOrWhiteSpace($line)) {
            $result.Add(($line -replace '^\-\s+', '').Trim())
            if ($result.Count -ge $MaxLines) {
                break
            }
        }
    }

    return @($result)
}

function Get-OodaLatestStreamDir {
    $latestPath = Join-Path (Join-Path $RepoRoot "debug-captures") "latest-stream.txt"
    if (-not (Test-Path $latestPath)) {
        return ""
    }

    $streamDir = (Get-Content -LiteralPath $latestPath -Raw).Trim()
    if ($streamDir -and (Test-Path $streamDir)) {
        return (Resolve-Path -LiteralPath $streamDir).Path
    }

    return ""
}

function Invoke-OodaStreamSummary {
    param(
        [System.Collections.IDictionary]$Issue,
        [string]$StreamDir = ""
    )

    $summaryLog = Join-Path $Issue["issueDir"] "stream-summary.txt"
    if (-not [string]::IsNullOrWhiteSpace($StreamDir)) {
        & "$PSScriptRoot\summarize_thor_debug_stream.ps1" -Package $Package -TailLines $EffectiveSummaryTailLines -Session $StreamDir *> $summaryLog
    } else {
        & "$PSScriptRoot\summarize_thor_debug_stream.ps1" -Package $Package -TailLines $EffectiveSummaryTailLines -Latest *> $summaryLog
    }
    Get-Content -LiteralPath $summaryLog | Write-Host

    $resolvedStreamDir = $StreamDir
    if ([string]::IsNullOrWhiteSpace($resolvedStreamDir)) {
        $resolvedStreamDir = Get-OodaLatestStreamDir
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedStreamDir)) {
        Add-OodaListValue $Issue "captures" $resolvedStreamDir
        $summaryPath = Join-Path $resolvedStreamDir "summary-latest.md"
        if (Test-Path $summaryPath) {
            Add-OodaListValue $Issue "summaries" $summaryPath
            Add-OodaListValue $Issue "quickRead" (Get-OodaMarkdownSection $summaryPath "Quick Read" 12)
        }
    }

    Add-OodaListValue $Issue "summaries" $summaryLog
    return $resolvedStreamDir
}

function Invoke-OodaCaptureTriage {
    param(
        [System.Collections.IDictionary]$Issue,
        [string]$CaptureDir
    )

    if ([string]::IsNullOrWhiteSpace($CaptureDir) -or -not (Test-Path $CaptureDir)) {
        return
    }

    $rpcsxLines = @(Get-OodaTailText (Join-Path $CaptureDir "rpcsx-log-errors.txt") 160 | Where-Object { $_ -notmatch '^\s*#' })
    $logcatLines = @(Get-OodaTailText (Join-Path $CaptureDir "logcat-interesting.txt") 160 | Where-Object { $_ -notmatch '^\s*#' })
    $memLines = @(Get-OodaTailText (Join-Path $CaptureDir "meminfo.txt") 120 | Where-Object { $_ -notmatch '^\s*#' })
    $topLines = @(Get-OodaTailText (Join-Path $CaptureDir "top-threads.txt") 80 | Where-Object { $_ -notmatch '^\s*#' })
    $allLines = @($rpcsxLines + $logcatLines + $memLines + $topLines)

    $signals = New-Object System.Collections.Generic.List[string]
    if (Test-OodaAnyPattern $allLines @("FATAL EXCEPTION", "Fatal signal", "SIGSEGV", "SIGABRT", "tombstone", "Abort message")) {
        $signals.Add("Crash signature present. Inspect logcat/tombstone lines before tuning performance.")
    }
    if (Test-OodaAnyPattern $allLines @("lowmemorykiller", "lmkd", "critical pressure", "Out of memory", "OutOfMemory", "report_bad_alloc_error", "memory_commit", "Cannot allocate")) {
        $signals.Add("Memory pressure or allocation failure present. Treat compile/cache pressure as suspect.")
    }
    if (Test-OodaAnyPattern $allLines @("semaphore_acquire has timed out", "VK_ERROR", "Vulkan", "sys_rsx")) {
        $signals.Add("RSX/Vulkan sync or driver signal present. Check RSX log lines before blaming SPU.")
    }
    if (Test-OodaAnyPattern $allLines @("SPU: Building function", "PPU: LLVM", "Building function", "LLVM")) {
        $signals.Add("Compiler activity visible. Separate first-run compile stalls from steady-state FPS.")
    }
    if (Test-OodaAnyPattern $allLines @("Thor SPURS", "sys_spu_thread_group_start", "sys_spu_thread_group_join", "SpursHdlr", "CellSpurs")) {
        $signals.Add("SPURS/SPU group churn visible. Keep using SPURS/profile probes for this repro.")
    }
    if (Test-OodaAnyPattern $allLines @("Reduced Loop Candidate", "spu_reduced_loop")) {
        $signals.Add("SPU reduced-loop logging visible. Keep captures short and reset to Quiet after final pull.")
    }
    if ($signals.Count -eq 0) {
        $signals.Add("No obvious crash/OOM/RSX/SPURS signature in the quick triage. Check activity focus and whether RPCSX.log is advancing.")
    }

    Add-OodaListValue $Issue "quickRead" @($signals)

    $triagePath = Join-Path $Issue["issueDir"] "triage.md"
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("# Thor OODA Triage")
    $out.Add("")
    $out.Add("- Capture: $CaptureDir")
    $out.Add("- Created: $(Get-Date -Format o)")
    $out.Add("")
    $out.Add("## Quick Read")
    foreach ($signal in $signals) {
        $out.Add("- $signal")
    }
    $out.Add("")
    $out.Add("## Recent RPCSX Error Lines")
    if ($rpcsxLines.Count -gt 0) {
        foreach ($line in ($rpcsxLines | Select-Object -Last 80)) {
            $out.Add($line)
        }
    } else {
        $out.Add("(none)")
    }
    $out.Add("")
    $out.Add("## Recent Logcat Interesting Lines")
    if ($logcatLines.Count -gt 0) {
        foreach ($line in ($logcatLines | Select-Object -Last 80)) {
            $out.Add($line)
        }
    } else {
        $out.Add("(none)")
    }
    $out.Add("")
    $out.Add("## Hot Threads")
    if ($topLines.Count -gt 0) {
        foreach ($line in ($topLines | Select-Object -Last 50)) {
            $out.Add($line)
        }
    } else {
        $out.Add("(none)")
    }

    $out | Set-Content -LiteralPath $triagePath -Encoding UTF8
    Add-OodaListValue $Issue "summaries" $triagePath
}

function Invoke-OodaPostRunLogging {
    param(
        [System.Collections.IDictionary]$Issue,
        [string]$EffectiveMode
    )

    if ($KeepLogging -or $EffectiveMode -eq "Status" -or [string]::IsNullOrWhiteSpace($EffectivePostMode)) {
        return
    }

    $postLog = Join-Path $Issue["issueDir"] "post-logging.txt"
    & "$PSScriptRoot\set_thor_logging.ps1" -Mode $EffectivePostMode 2>&1 |
        Tee-Object -FilePath $postLog |
        ForEach-Object { Write-Host $_ }
    $Issue["settings"]["postModeApplied"] = $EffectivePostMode
}

function Invoke-OodaBuildInstall {
    param([System.Collections.IDictionary]$Issue)

    $logPath = Join-Path $Issue["issueDir"] "build-install.txt"
    Push-Location $RepoRoot
    try {
        ".\gradlew.bat :app:assembleDebug" | Tee-Object -FilePath $logPath
        & .\gradlew.bat :app:assembleDebug 2>&1 | Tee-Object -FilePath $logPath -Append
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle assembleDebug failed."
        }

        $apk = Join-Path $RepoRoot "app\build\outputs\apk\debug\rpcsx-thor-experiment-debug.apk"
        $hash = ""
        if (Test-Path $apk) {
            $hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
        }

        "adb install -r $apk" | Tee-Object -FilePath $logPath -Append
        & $Adb install -r $apk 2>&1 | Tee-Object -FilePath $logPath -Append
        if ($LASTEXITCODE -ne 0) {
            throw "adb install failed."
        }

        $Issue["apk"] = [ordered]@{
            path = $apk
            sha256 = $hash
            installed = (Get-Date -Format o)
        }
    } finally {
        Pop-Location
    }
}

function Set-OodaLogging {
    param(
        [string]$EffectiveMode,
        [object]$ProfileObject,
        [System.Collections.IDictionary]$Issue
    )

    $logPath = Join-Path $Issue["issueDir"] "logging.txt"
    & "$PSScriptRoot\set_thor_logging.ps1" -Mode $EffectiveMode 2>&1 |
        Tee-Object -FilePath $logPath |
        ForEach-Object { Write-Host $_ }

    if (-not $NoGhidra) {
        $ghidra = Get-OodaProperty $ProfileObject "ghidra" $null
        $module = Get-OodaProperty $ghidra "module" ""
        if (-not [string]::IsNullOrWhiteSpace($module)) {
            & $Adb shell setprop debug.rpcsx.thor.dump_prx $module | Out-Null
            "debug.rpcsx.thor.dump_prx=$module" | Out-File -LiteralPath $logPath -Append -Encoding UTF8
        }
    }
}

function Start-OodaStream {
    param(
        [System.Collections.IDictionary]$Issue,
        [string]$EffectiveMode,
        [object]$ProfileObject
    )

    Set-OodaLogging $EffectiveMode $ProfileObject $Issue

    $args = @("-Label", $Issue["id"], "-Package", $Package, "-ClearLogcat", "-PollSeconds", "$EffectiveStreamPollSeconds")
    if (-not $NoLaunch) {
        $args += "-Launch"
    }

    $logPath = Join-Path $Issue["issueDir"] "start-stream.txt"
    & "$PSScriptRoot\start_thor_debug_stream.ps1" @args 2>&1 |
        Tee-Object -FilePath $logPath

    $latestPath = Join-Path (Join-Path $RepoRoot "debug-captures") "latest-stream.txt"
    if (Test-Path $latestPath) {
        $streamDir = (Get-Content -LiteralPath $latestPath -Raw).Trim()
        if ($streamDir) {
            $Issue["captures"] = @($Issue["captures"]) + $streamDir
            $Issue["nextAction"] = "Reproduce on Thor. While it is running, use `.\tools\thor_ooda.ps1 -Action Summarize -Label $($Issue["label"]) -Profile $Profile -NoIssueCommit` for quick reads; when the issue is visible, run `.\tools\thor_ooda.ps1 -Action Stop -Label $($Issue["label"]) -Profile $Profile`."
        }
    }
}

function Invoke-OodaCapture {
    param(
        [System.Collections.IDictionary]$Issue,
        [string]$EffectiveMode,
        [object]$ProfileObject
    )

    Set-OodaLogging $EffectiveMode $ProfileObject $Issue

    $captureLog = Join-Path $Issue["issueDir"] "capture.txt"
    & "$PSScriptRoot\collect_thor_debug.ps1" -Label $Issue["id"] -Package $Package -LogcatLines $EffectiveLogcatLines *> $captureLog
    Get-Content -LiteralPath $captureLog | Write-Host

    $captureRoot = Join-Path $RepoRoot "debug-captures"
    $captureDir = Get-ChildItem -LiteralPath $captureRoot -Directory -Filter "*-$($Issue["id"])" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName

    if ($captureDir) {
        $Issue["captures"] = @($Issue["captures"]) + $captureDir
        return $captureDir
    }

    return ""
}

function Stop-OodaStream {
    param([System.Collections.IDictionary]$Issue)

    & "$PSScriptRoot\stop_thor_debug_stream.ps1" -Latest -Package $Package 2>&1 |
        Tee-Object -FilePath (Join-Path $Issue["issueDir"] "stop-stream.txt") |
        ForEach-Object { Write-Host $_ }

    $latestPath = Join-Path (Join-Path $RepoRoot "debug-captures") "latest-stream.txt"
    if (Test-Path $latestPath) {
        $streamDir = (Get-Content -LiteralPath $latestPath -Raw).Trim()
        if ($streamDir) {
            $Issue["captures"] = @($Issue["captures"]) + $streamDir
            return $streamDir
        }
    }

    return ""
}

function Find-OodaGuestAddress {
    param([string[]]$Roots)

    $files = @()
    foreach ($root in $Roots) {
        if ($root -and (Test-Path $root)) {
            if ((Get-Item -LiteralPath $root) -is [System.IO.DirectoryInfo]) {
                $files += Get-ChildItem -LiteralPath $root -Recurse -File -Include "*.txt", "*.log", "*.md" -ErrorAction SilentlyContinue
            } else {
                $files += Get-Item -LiteralPath $root
            }
        }
    }

    foreach ($file in $files) {
        $matches = Select-String -LiteralPath $file.FullName -Pattern '\b([A-Za-z0-9_.-]+):(0x[0-9A-Fa-f]{6,16})\b' -AllMatches -ErrorAction SilentlyContinue
        foreach ($matchInfo in $matches) {
            foreach ($match in $matchInfo.Matches) {
                $module = $match.Groups[1].Value
                $addr = $match.Groups[2].Value
                if ($module -notmatch '^(http|https|file)$') {
                    return [pscustomobject]@{
                        module = $module
                        addresses = @($addr)
                        source = $file.FullName
                    }
                }
            }
        }
    }

    return $null
}

function Invoke-OodaGhidra {
    param(
        [System.Collections.IDictionary]$Issue,
        [object]$ProfileObject,
        [string[]]$SearchRoots
    )

    if ($NoGhidra) {
        return
    }

    $ghidra = Get-OodaProperty $ProfileObject "ghidra" $null
    $auto = [bool](Get-OodaProperty $ghidra "auto" $true)
    if (-not $auto) {
        return
    }

    $module = Get-OodaProperty $ghidra "module" ""
    $addresses = @()
    foreach ($addr in @(Get-OodaProperty $ghidra "addresses" @())) {
        if (-not [string]::IsNullOrWhiteSpace([string]$addr)) {
            $addresses += [string]$addr
        }
    }

    if ([string]::IsNullOrWhiteSpace($module) -or $addresses.Count -eq 0) {
        $detected = Find-OodaGuestAddress $SearchRoots
        if ($null -ne $detected) {
            $module = $detected.module
            $addresses = @($detected.addresses)
        }
    }

    if ([string]::IsNullOrWhiteSpace($module) -or $addresses.Count -eq 0) {
        return
    }

    $wait = $GhidraWaitSeconds
    if ($wait -lt 0) {
        $wait = [int](Get-OodaProperty $ghidra "waitSeconds" 0)
    }

    $logPath = Join-Path $Issue["issueDir"] "ghidra-auto.txt"
    try {
        $helper = Join-Path $PSScriptRoot "run_thor_ghidra_prx_probe.ps1"
        $helperArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $helper, "-Module", $module, "-WaitSeconds", "$wait")
        if ($addresses.Count -gt 0) {
            $helperArgs += "-Addresses"
            $helperArgs += $addresses
        }

        & powershell @helperArgs 2>&1 |
            Tee-Object -FilePath $logPath |
            ForEach-Object { Write-Host $_ }
        $helperExit = $LASTEXITCODE
        $ghidraDir = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "debug-captures") -Directory -Filter "ghidra-$module-*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($helperExit -eq 0 -and $ghidraDir) {
            $Issue["ghidra"] = @($Issue["ghidra"]) + $ghidraDir
        } elseif ($helperExit -ne 0) {
            $Issue["ghidra"] = @($Issue["ghidra"]) + "pending module=$module addresses=$($addresses -join ',') helperExit=$helperExit"
        } else {
            $Issue["ghidra"] = @($Issue["ghidra"]) + "attempted module=$module addresses=$($addresses -join ',')"
        }
    } catch {
        $_.Exception.Message | Tee-Object -FilePath $logPath -Append
        $Issue["ghidra"] = @($Issue["ghidra"]) + "failed module=$module addresses=$($addresses -join ',')"
    }
}

function Write-OodaDeviceMetadata {
    param([System.Collections.IDictionary]$Issue)

    $metaPath = Join-Path $Issue["issueDir"] "device-metadata.txt"
    Invoke-ThorAdbText $Adb $Issue["issueDir"] "device-props.txt" @("shell", "getprop | grep -E 'ro.product|ro.board|ro.hardware|debug.rpcsx|log.tag.RPCS|dalvik.vm|ro.build.fingerprint'") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $Issue["issueDir"] "app-prefs.txt" @("shell", "run-as $Package cat shared_prefs/app_prefs.xml") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $Issue["issueDir"] "package-path.txt" @("shell", "pm path $Package") -AllowFailure | Out-Null
    $Issue["device"] = [ordered]@{
        serial = (Get-OodaAdbText @("get-serialno"))
        model = (Get-OodaAdbText @("shell", "getprop ro.product.model"))
        product = (Get-OodaAdbText @("shell", "getprop ro.product.device"))
        board = (Get-OodaAdbText @("shell", "getprop ro.board.platform"))
        packagePath = (Get-OodaAdbText @("shell", "pm path $Package"))
        propsFile = (Join-Path $Issue["issueDir"] "device-props.txt")
        appPrefsFile = (Join-Path $Issue["issueDir"] "app-prefs.txt")
    }
    "metadata captured $(Get-Date -Format o)" | Set-Content -LiteralPath $metaPath -Encoding UTF8
}

$profileObject = Read-OodaProfile $profilePath
$effectiveMode = $Mode
if ([string]::IsNullOrWhiteSpace($effectiveMode)) {
    $effectiveMode = [string](Get-OodaProperty $profileObject "mode" "Normal")
}

$captureProfile = Get-OodaProperty $profileObject "capture" $null
$streamProfile = Get-OodaProperty $profileObject "stream" $null
$effectiveLogcatLines = $LogcatLines
if ($effectiveLogcatLines -le 0) {
    $effectiveLogcatLines = Get-OodaIntProperty $captureProfile "logcatLines" 12000
}

$effectiveSummaryTailLines = $SummaryTailLines
if ($effectiveSummaryTailLines -le 0) {
    $effectiveSummaryTailLines = Get-OodaIntProperty $captureProfile "summaryTailLines" 80
}

$effectiveStreamPollSeconds = $StreamPollSeconds
if ($effectiveStreamPollSeconds -le 0) {
    $effectiveStreamPollSeconds = Get-OodaIntProperty $streamProfile "pollSeconds" 3
}

$effectivePostMode = $PostMode
if ([string]::IsNullOrWhiteSpace($effectivePostMode)) {
    $effectivePostMode = [string](Get-OodaProperty $captureProfile "postMode" "Quiet")
}
if ($effectivePostMode -match '^(none|off|keep)$') {
    $effectivePostMode = ""
}

$effectiveSettings = [ordered]@{
    logcatLines = $effectiveLogcatLines
    summaryTailLines = $effectiveSummaryTailLines
    streamPollSeconds = $effectiveStreamPollSeconds
    postMode = $effectivePostMode
    postModeApplied = ""
}

if ($Action -eq "Profile") {
    $profileObject | ConvertTo-Json -Depth 8
    return
}

$issue = New-OodaIssue $profileObject $effectiveMode $effectiveSettings

try {
    if ($Action -eq "BuildInstall") {
        Invoke-OodaBuildInstall $issue
        $issue["nextAction"] = "Start a repro with `.\tools\thor_ooda.ps1 -Action Start -Label $safeLabel -Profile $Profile`."
    } elseif ($Action -eq "Start" -or $Action -eq "Auto") {
        if (-not $NoBuildInstall) {
            Invoke-OodaBuildInstall $issue
        }
        Start-OodaStream $issue $effectiveMode $profileObject
    } elseif ($Action -eq "Summarize") {
        $streamDir = Invoke-OodaStreamSummary $issue
        Invoke-OodaGhidra $issue $profileObject @($streamDir)
        $issue["nextAction"] = "If the quick read is enough, patch narrowly; otherwise keep the stream running and summarize again, or stop it when the repro is fully visible."
    } elseif ($Action -eq "Capture") {
        $captureDir = Invoke-OodaCapture $issue $effectiveMode $profileObject
        Invoke-OodaCaptureTriage $issue $captureDir
        Invoke-OodaGhidra $issue $profileObject @($captureDir)
        Invoke-OodaPostRunLogging $issue $effectiveMode
        $issue["nextAction"] = "Classify the issue from capture, patch narrowly, rebuild/install, and rerun the same profile."
    } elseif ($Action -eq "Stop") {
        $streamDir = Stop-OodaStream $issue
        Invoke-OodaStreamSummary $issue $streamDir | Out-Null
        Invoke-OodaGhidra $issue $profileObject @($streamDir)
        Invoke-OodaPostRunLogging $issue $effectiveMode
        $issue["nextAction"] = "Inspect final stream/capture output, patch narrowly, rebuild/install, and rerun the same profile."
    }

    Write-OodaDeviceMetadata $issue
    $issue["status"] = "ok"
    Save-OodaIssue $issue
    Commit-OodaIssue $issue
    Write-Host "OODA issue written: $($issue["issueDir"])"
} catch {
    $issue["status"] = "failed"
    $issue["failure"] = $_.Exception.Message
    $issue["nextAction"] = "Run failed: $($_.Exception.Message)"
    try {
        Write-OodaDeviceMetadata $issue
    } catch {
        Add-OodaListValue $issue "quickRead" "Device metadata capture also failed: $($_.Exception.Message)"
    }
    Save-OodaIssue $issue
    try {
        Commit-OodaIssue $issue
    } catch {
        Write-Warning "Failed to auto-commit failed OODA issue: $($_.Exception.Message)"
    }
    Write-Host "OODA issue written with failure: $($issue["issueDir"])"
    throw
}
