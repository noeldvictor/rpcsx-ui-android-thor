param(
    [switch]$Install,
    [switch]$VerifyOnly,
    [string]$ToolchainRoot = "C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains",
    [string]$AgiVersion = "3.3.3"
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ReportRoot = Join-Path $RepoRoot "debug-captures\tooling"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $ReportRoot "$Stamp-$PID-speed-sprint-tools.md"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

function Write-ToolReport {
    param([string]$Text = "")
    $Text | Tee-Object -FilePath $ReportPath -Append | ForEach-Object { Write-Host $_ }
}

function Find-FirstExistingPath {
    param([string[]]$Paths)
    foreach ($path in $Paths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }
    return ""
}

function Find-CommandPath {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    return ""
}

function Find-RenderDoc {
    $fromPath = Find-CommandPath "renderdoccmd.exe"
    if ($fromPath) {
        return $fromPath
    }

    return Find-FirstExistingPath @(
        "C:\Program Files\RenderDoc\renderdoccmd.exe",
        "C:\Program Files\RenderDoc\qrenderdoc.exe",
        "C:\Program Files (x86)\RenderDoc\renderdoccmd.exe",
        "C:\Program Files (x86)\RenderDoc\qrenderdoc.exe"
    )
}

function Find-Agi {
    $fromPath = Find-CommandPath "agi.exe"
    if ($fromPath) {
        return $fromPath
    }

    $direct = Find-FirstExistingPath @(
        (Join-Path $ToolchainRoot "agi-$AgiVersion\agi.exe"),
        (Join-Path $ToolchainRoot "agi-$AgiVersion\bin\agi.exe"),
        "C:\Program Files\Android GPU Inspector\agi.exe",
        "C:\Program Files (x86)\Android GPU Inspector\agi.exe"
    )
    if ($direct) {
        return $direct
    }

    $root = Join-Path $ToolchainRoot "agi-$AgiVersion"
    if (Test-Path -LiteralPath $root) {
        $match = Get-ChildItem -LiteralPath $root -Recurse -File -Filter "agi.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return ""
}

function Find-SnapdragonProfiler {
    return Find-FirstExistingPath @(
        "C:\Program Files (x86)\Qualcomm\Snapdragon Profiler\SnapdragonProfiler.exe",
        "C:\Program Files\Qualcomm\Snapdragon Profiler\SnapdragonProfiler.exe",
        "C:\Program Files\Qualcomm\Shared\QualcommProfiler\SnapdragonProfiler.exe"
    )
}

function Install-RenderDocIfNeeded {
    if (Find-RenderDoc) {
        return
    }

    $winget = Find-CommandPath "winget.exe"
    if (-not $winget) {
        Write-ToolReport "- RenderDoc install skipped: winget.exe not found."
        return
    }

    Write-ToolReport "- Installing RenderDoc via winget package `BaldurKarlsson.RenderDoc`."
    & $winget install --id BaldurKarlsson.RenderDoc -e --silent --accept-package-agreements --accept-source-agreements
    Write-ToolReport "- RenderDoc winget exit: $LASTEXITCODE"
}

function Install-AgiIfNeeded {
    if (Find-Agi) {
        return
    }

    New-Item -ItemType Directory -Force -Path $ToolchainRoot | Out-Null
    $agiRoot = Join-Path $ToolchainRoot "agi-$AgiVersion"
    $downloadRoot = Join-Path $ToolchainRoot "_downloads"
    $zipPath = Join-Path $downloadRoot "agi-$AgiVersion-windows.zip"
    $url = "https://github.com/google/agi/releases/download/v$AgiVersion/agi-$AgiVersion-windows.zip"

    New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
    Write-ToolReport "- Downloading AGI $AgiVersion from $url"
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    if (Test-Path -LiteralPath $agiRoot) {
        Remove-Item -LiteralPath $agiRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $agiRoot | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $agiRoot -Force

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
    Write-ToolReport "- AGI zip SHA256: $hash"
}

function Write-ToolStatus {
    $renderDoc = Find-RenderDoc
    $agi = Find-Agi
    $snapdragon = Find-SnapdragonProfiler
    $adb = Find-CommandPath "adb.exe"
    if (-not $adb -and $env:ANDROID_HOME) {
        $adb = Find-FirstExistingPath @((Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"))
    }
    if (-not $adb) {
        $adb = Find-FirstExistingPath @("C:\Users\leanerdesigner\AppData\Local\Android\Sdk\platform-tools\adb.exe")
    }

    Write-ToolReport "## Tool Status"
    Write-ToolReport ""
    Write-ToolReport "| Tool | Status | Path / note |"
    Write-ToolReport "| --- | --- | --- |"
    Write-ToolReport "| RenderDoc | $(if ($renderDoc) { 'ready' } else { 'missing' }) | $renderDoc |"
    Write-ToolReport "| Android GPU Inspector | $(if ($agi) { 'ready' } else { 'missing' }) | $agi |"
    Write-ToolReport "| Snapdragon Profiler | $(if ($snapdragon) { 'ready' } else { 'blocked-or-missing' }) | $(if ($snapdragon) { $snapdragon } else { 'Qualcomm login/download may be required; fall back to AGI + Perfetto + dumpsys.' }) |"
    Write-ToolReport "| ADB | $(if ($adb) { 'ready' } else { 'missing' }) | $adb |"
    Write-ToolReport ""
    Write-ToolReport "Report: $ReportPath"
}

Write-ToolReport "# Eternal Sonata Speed Sprint Tooling"
Write-ToolReport ""
Write-ToolReport "- Created: $(Get-Date -Format o)"
Write-ToolReport "- Toolchain root: $ToolchainRoot"
Write-ToolReport "- Mode: $(if ($Install) { 'install' } elseif ($VerifyOnly) { 'verify-only' } else { 'verify-only' })"
Write-ToolReport ""

if ($Install -and -not $VerifyOnly) {
    Install-RenderDocIfNeeded
    Install-AgiIfNeeded
} elseif (-not $Install) {
    Write-ToolReport "- Install switch not set; verifying only."
}

Write-ToolStatus
