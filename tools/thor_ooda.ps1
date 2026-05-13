param(
    [ValidateSet("Profile", "BuildInstall", "Start", "Capture", "Stop", "Auto")]
    [string]$Action = "Auto",
    [string]$Label = "thor-ooda",
    [string]$Profile = "default",
    [string]$Package = "net.rpcsx.easy",
    [string]$Mode = "",
    [string]$Symptom = "",
    [int]$LogcatLines = 30000,
    [int]$GhidraWaitSeconds = -1,
    [switch]$NoBuildInstall,
    [switch]$NoLaunch,
    [switch]$NoGhidra,
    [switch]$NoIssueCommit
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
        [string]$EffectiveMode
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
        repo = [ordered]@{
            head = (Get-OodaGitText @("rev-parse", "--short", "HEAD"))
            branch = (Get-OodaGitText @("branch", "--show-current"))
            status = (Get-OodaGitText @("status", "--short"))
        }
        apk = [ordered]@{}
        device = [ordered]@{}
        captures = @()
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
        "- Package: $($Issue["package"])",
        "- Repo: $($Issue["repo"]["head"]) on $($Issue["repo"]["branch"])",
        "- Symptom: $($Issue["symptom"])",
        "",
        "## Captures",
        $captureLines,
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
        Tee-Object -FilePath $logPath

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

    $args = @("-Label", $Issue["id"], "-Package", $Package, "-ClearLogcat")
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
            $Issue["nextAction"] = "Reproduce the issue on Thor, then run `.\tools\thor_ooda.ps1 -Action Stop -Label $($Issue["label"]) -Profile $Profile`."
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
    & "$PSScriptRoot\collect_thor_debug.ps1" -Label $Issue["id"] -Package $Package -LogcatLines $LogcatLines *> $captureLog
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
        Tee-Object -FilePath (Join-Path $Issue["issueDir"] "stop-stream.txt")

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
            Tee-Object -FilePath $logPath
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

if ($Action -eq "Profile") {
    $profileObject | ConvertTo-Json -Depth 8
    return
}

$issue = New-OodaIssue $profileObject $effectiveMode

try {
    if ($Action -eq "BuildInstall") {
        Invoke-OodaBuildInstall $issue
        $issue["nextAction"] = "Start a repro with `.\tools\thor_ooda.ps1 -Action Start -Label $safeLabel -Profile $Profile`."
    } elseif ($Action -eq "Start" -or $Action -eq "Auto") {
        if (-not $NoBuildInstall) {
            Invoke-OodaBuildInstall $issue
        }
        Start-OodaStream $issue $effectiveMode $profileObject
    } elseif ($Action -eq "Capture") {
        $captureDir = Invoke-OodaCapture $issue $effectiveMode $profileObject
        Invoke-OodaGhidra $issue $profileObject @($captureDir)
        $issue["nextAction"] = "Classify the issue from capture, patch narrowly, rebuild/install, and rerun the same profile."
    } elseif ($Action -eq "Stop") {
        $streamDir = Stop-OodaStream $issue
        Invoke-OodaGhidra $issue $profileObject @($streamDir)
        $issue["nextAction"] = "Inspect final stream/capture output, patch narrowly, rebuild/install, and rerun the same profile."
    }

    Write-OodaDeviceMetadata $issue
    Save-OodaIssue $issue
    Commit-OodaIssue $issue
    Write-Host "OODA issue written: $($issue["issueDir"])"
} catch {
    $issue["nextAction"] = "Run failed: $($_.Exception.Message)"
    Save-OodaIssue $issue
    Write-Host "OODA issue written with failure: $($issue["issueDir"])"
    throw
}
