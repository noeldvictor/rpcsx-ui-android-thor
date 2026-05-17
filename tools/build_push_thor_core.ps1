param(
    [string]$Package = "net.rpcsx.easy",
    [string]$Label = "dev-core",
    [string]$CoreName = "librpcsx-android.so",
    [string]$GradleTask = ":app:buildCMakeRelWithDebInfo[arm64-v8a]",
    [string]$StagingDir = "",
    [string]$Profile = "default",
    [switch]$NoBuild,
    [switch]$NoFallbackBuild,
    [switch]$AllowDebugFallback,
    [switch]$NoLaunch,
    [switch]$NoStream,
    [switch]$ResetToBundled
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}
. "$PSScriptRoot\thor_debug_common.ps1"

$RepoRoot = Get-ThorRepoRoot
$Adb = Resolve-ThorAdb
$safeLabel = New-ThorSafeLabel $Label
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outRoot = Join-Path $RepoRoot "debug-captures"
$logDir = Join-Path $outRoot "$stamp-$safeLabel-dev-core-push"
$logPath = Join-Path $logDir "build-push.txt"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if ([string]::IsNullOrWhiteSpace($StagingDir)) {
    $StagingDir = "/storage/emulated/0/Android/data/$Package/files/dev-core-staging"
}

$internalRelativeDir = "files/dev-core"
$internalCorePath = "/data/data/$Package/$internalRelativeDir/$CoreName"

function Write-DevCoreLog {
    param([string]$Text)

    $Text | Tee-Object -FilePath $logPath -Append | ForEach-Object { Write-Host $_ }
}

function Invoke-DevCoreCommand {
    param(
        [string]$Title,
        [scriptblock]$Command
    )

    Write-DevCoreLog ""
    Write-DevCoreLog "## $Title"
    $oldErrorActionPreference = $ErrorActionPreference
    $oldNativeErrorActionPreference = $null
    $hasNativeErrorActionPreference = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($hasNativeErrorActionPreference) {
        $oldNativeErrorActionPreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = "Continue"
        if ($hasNativeErrorActionPreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        & $Command 2>&1 | Tee-Object -FilePath $logPath -Append | ForEach-Object { Write-Host $_ }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($hasNativeErrorActionPreference) {
            $PSNativeCommandUseErrorActionPreference = $oldNativeErrorActionPreference
        }
    }
}

function Assert-DevCoreCommand {
    param(
        [string]$Title,
        [scriptblock]$Command
    )

    $exitCode = Invoke-DevCoreCommand $Title $Command
    if ($exitCode -ne 0) {
        throw "$Title failed with exit code $exitCode."
    }
}

function Invoke-DevCoreRunAs {
    param([string]$Command)

    $appDataDir = "/data/data/$Package"
    $escapedCommand = "cd $appDataDir && $Command" -replace "'", "'\''"
    & $Adb shell "run-as $Package sh -c '$escapedCommand'"
}

function Find-DevCoreLibrary {
    $buildRoot = Join-Path $RepoRoot "app\build"
    if (-not (Test-Path $buildRoot)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $buildRoot -Recurse -File -Filter $CoreName -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '\\(cxx|intermediates)\\' -and
            $_.FullName -match '\\arm64-v8a\\'
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-DevCoreGitText {
    param([string[]]$GitArgs)

    try {
        return ((& git -C $RepoRoot @GitArgs 2>$null) -join "`n").Trim()
    } catch {
        return ""
    }
}

function Invoke-DevCoreBuild {
    Push-Location $RepoRoot
    try {
        $defaultJava = Join-Path $HOME ".codex\jdks\jdk-17"
        if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME) -and (Test-Path $defaultJava)) {
            $env:JAVA_HOME = $defaultJava
        }
        $defaultSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
        if ([string]::IsNullOrWhiteSpace($env:ANDROID_HOME) -and (Test-Path $defaultSdk)) {
            $env:ANDROID_HOME = $defaultSdk
        }

        $tasks = @($GradleTask)
        if (-not $NoFallbackBuild) {
            $tasks += ":app:externalNativeBuildRelWithDebInfo"
            if ($AllowDebugFallback) {
                $tasks += ":app:buildCMakeDebug[arm64-v8a]"
                $tasks += ":app:externalNativeBuildDebug"
                $tasks += ":app:assembleDebug"
            }
        }

        foreach ($task in $tasks) {
            if ([string]::IsNullOrWhiteSpace($task)) {
                continue
            }

            $exitCode = Invoke-DevCoreCommand "gradlew $task" {
                & .\gradlew.bat $task
            }
            if ($exitCode -eq 0) {
                return
            }

            Write-DevCoreLog "Gradle task failed with exit code $exitCode; trying next fallback if available."
        }

        throw "No Gradle native build task succeeded."
    } finally {
        Pop-Location
    }
}

if ($ResetToBundled) {
    Write-DevCoreLog "# Reset Thor dev core override"
    Assert-DevCoreCommand "remove active dev-core markers" {
        Invoke-DevCoreRunAs "rm -f $internalRelativeDir/active-core.path $internalRelativeDir/active-core.json $internalRelativeDir/$CoreName"
        & $Adb shell "rm -f '$StagingDir/active-core.path' '$StagingDir/active-core.json'"
    }
    if (-not $NoLaunch) {
        Assert-DevCoreCommand "relaunch app" {
            & $Adb shell am force-stop $Package
            & $Adb shell monkey -p $Package 1
        }
    }
    Write-Host "Thor dev core override reset. Log: $logPath"
    return
}

Write-DevCoreLog "# Thor dev core build/push"
Write-DevCoreLog "- Started: $(Get-Date -Format o)"
Write-DevCoreLog "- Package: $Package"
Write-DevCoreLog "- Staging dir: $StagingDir"
Write-DevCoreLog "- Internal core: $internalCorePath"
Write-DevCoreLog "- Gradle task: $GradleTask"
Write-DevCoreLog "- Repo: $(Get-DevCoreGitText @('rev-parse', '--short', 'HEAD'))"

if (-not $NoBuild) {
    Invoke-DevCoreBuild
}

$core = Find-DevCoreLibrary
if ($null -eq $core) {
    throw "Could not find $CoreName under app\build after native build."
}

$hash = (Get-FileHash -LiteralPath $core.FullName -Algorithm SHA256).Hash
$stagedCorePath = "$StagingDir/$CoreName"
$localManifest = Join-Path $logDir "active-core.json"
$localPathMarker = Join-Path $logDir "active-core.path"

$manifest = [ordered]@{
    core = $internalCorePath
    stagingCore = $stagedCorePath
    coreName = $CoreName
    sha256 = $hash
    pushed = (Get-Date -Format o)
    repo = [ordered]@{
        head = (Get-DevCoreGitText @("rev-parse", "--short", "HEAD"))
        branch = (Get-DevCoreGitText @("branch", "--show-current"))
        status = (Get-DevCoreGitText @("status", "--short"))
    }
    local = $core.FullName
}

$internalCorePath | Set-Content -LiteralPath $localPathMarker -Encoding ASCII
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $localManifest -Encoding UTF8

Write-DevCoreLog "- Local core: $($core.FullName)"
Write-DevCoreLog "- SHA256: $hash"
Write-DevCoreLog "- Staged core: $stagedCorePath"
Write-DevCoreLog "- Active internal core: $internalCorePath"

Assert-DevCoreCommand "push core and markers" {
    & $Adb shell "mkdir -p '$StagingDir'"
    & $Adb push $core.FullName $stagedCorePath
    & $Adb push $localPathMarker "$StagingDir/active-core.path"
    & $Adb push $localManifest "$StagingDir/active-core.json"
    Invoke-DevCoreRunAs "mkdir -p $internalRelativeDir && cp $stagedCorePath $internalRelativeDir/$CoreName && cp $StagingDir/active-core.path $internalRelativeDir/active-core.path && cp $StagingDir/active-core.json $internalRelativeDir/active-core.json && chmod 700 $internalRelativeDir $internalRelativeDir/$CoreName && chmod 600 $internalRelativeDir/active-core.path $internalRelativeDir/active-core.json"
}

Assert-DevCoreCommand "verify remote core" {
    & $Adb shell "ls -l '$stagedCorePath' '$StagingDir/active-core.path' '$StagingDir/active-core.json'"
    Invoke-DevCoreRunAs "ls -l $internalRelativeDir/$CoreName $internalRelativeDir/active-core.path $internalRelativeDir/active-core.json"
}

if (-not $NoLaunch) {
    Assert-DevCoreCommand "relaunch app" {
        & $Adb shell am force-stop $Package
        & $Adb shell monkey -p $Package 1
    }
}

if (-not $NoStream) {
    Assert-DevCoreCommand "start OODA stream without APK reinstall" {
        & "$PSScriptRoot\thor_ooda.ps1" -Action Start -NoBuildInstall -Profile $Profile -Label $safeLabel
    }
}

@(
    "# Thor Dev Core Push",
    "",
    "- Pushed: $(Get-Date -Format o)",
    "- Package: $Package",
    "- Local core: $($core.FullName)",
    "- Staged core: $stagedCorePath",
    "- Active internal core: $internalCorePath",
    "- SHA256: $hash",
    "- Log: $logPath",
    "",
    "Debug APKs read app-internal `files/dev-core/active-core.path` at startup and use that core before falling back to the bundled APK core.",
    "Reset with:",
    "",
    '```powershell',
    ".\tools\build_push_thor_core.ps1 -ResetToBundled",
    '```'
) | Set-Content -LiteralPath (Join-Path $logDir "README.md") -Encoding UTF8

Write-Host "Thor dev core pushed: $internalCorePath"
Write-Host "Log: $logPath"
