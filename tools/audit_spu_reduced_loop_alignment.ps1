[CmdletBinding()]
param(
    [string]$UpstreamRepo = "",
    [switch]$FailOnIncomplete
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($UpstreamRepo)) {
    $UpstreamRepo = Join-Path (Split-Path $RepoRoot -Parent) "rpcs3-upstream"
}
$UpstreamRepo = (Resolve-Path $UpstreamRepo).Path

function Invoke-GitText {
    param(
        [string]$Repo,
        [string[]]$Arguments
    )

    $Output = & git -C $Repo @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git -C '$Repo' $($Arguments -join ' ') failed: $($Output -join [Environment]::NewLine)"
    }

    return ($Output -join [Environment]::NewLine).Trim()
}

$AndroidHead = Invoke-GitText -Repo $RepoRoot -Arguments @("rev-parse", "HEAD")
$UpstreamHead = Invoke-GitText -Repo $UpstreamRepo -Arguments @("rev-parse", "HEAD")

$RequiredCommits = @(
    [pscustomobject]@{ Commit = "a863e94"; Purpose = "integrated analyzer/dataflow detection" }
    [pscustomobject]@{ Commit = "2e4ee9c"; Purpose = "LLVM reduced-loop emitter" }
    [pscustomobject]@{ Commit = "37a07ae"; Purpose = "FM/FMA/FCGT reduced-loop optimization" }
    [pscustomobject]@{ Commit = "a03a78d"; Purpose = "runtime completability verification" }
    [pscustomobject]@{ Commit = "13de823"; Purpose = "register-origin and external-origin fix" }
    [pscustomobject]@{ Commit = "02eb549"; Purpose = "second-block register-update fix" }
)

$CommitRows = foreach ($Entry in $RequiredCommits) {
    & git -C $UpstreamRepo merge-base --is-ancestor $Entry.Commit HEAD 2>$null
    [pscustomobject]@{
        Commit = $Entry.Commit
        Purpose = $Entry.Purpose
        Present = $LASTEXITCODE -eq 0
    }
}

$TrackedPaths = @(
    "rpcs3/Emu/CPU/CPUTranslator.h"
    "rpcs3/Emu/Cell/SPUAnalyser.h"
    "rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
    "rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
    "rpcs3/Emu/Cell/SPUOpcodes.h"
    "rpcs3/Emu/Cell/SPURecompiler.h"
    "rpcs3/Emu/Cell/SPUThread.cpp"
)
$LogArguments = @("log", "--format=%h %s", "--reverse", "a863e94^..02eb549", "--") + $TrackedPaths
$PathCommitLines = (Invoke-GitText -Repo $UpstreamRepo -Arguments $LogArguments) -split "\r?\n"

$CommonPath = Join-Path $RepoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$LlvmPath = Join-Path $RepoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$HeaderPath = Join-Path $RepoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPURecompiler.h"
$SetLoggingPath = Join-Path $RepoRoot "tools/set_thor_logging.ps1"
$SprintPath = Join-Path $RepoRoot "tools/eternal_sonata_speed_sprint.ps1"

$CommonSource = Get-Content -Raw $CommonPath
$LlvmSource = Get-Content -Raw $LlvmPath
$HeaderSource = Get-Content -Raw $HeaderPath
$SetLoggingParam = (Get-Content $SetLoggingPath | Select-Object -First 8) -join [Environment]::NewLine
$SprintParam = (Get-Content $SprintPath | Select-Object -First 120) -join [Environment]::NewLine

$SafetyChecks = @(
    [pscustomobject]@{
        Check = "Android native emit clamp"
        Present = [regex]::IsMatch(
            $CommonSource,
            "spu_reduced_loop_emit_enabled\(\) noexcept\s*\{.*?#ifdef ANDROID.*?return false;.*?#else",
            [Text.RegularExpressions.RegexOptions]::Singleline
        )
    }
    [pscustomobject]@{
        Check = "set_thor_logging public emit profile retired"
        Present = $SetLoggingParam -notmatch "ReducedLoopEmit"
    }
    [pscustomobject]@{
        Check = "speed-sprint public emit profile retired"
        Present = $SprintParam -notmatch "ReducedLoopEmit"
    }
)

$ArchitectureChecks = @(
    [pscustomobject]@{
        Check = "integrated reduced_loop_all analyzer state"
        Present = $CommonSource -match "\breduced_loop_all\b"
    }
    [pscustomobject]@{
        Check = "register-origin propagation"
        Present = $CommonSource -match "\badd_register_origin\b"
    }
    [pscustomobject]@{
        Check = "reduced-loop origin_t model"
        Present = $HeaderSource -match "\bstruct\s+origin_t\b"
    }
    [pscustomobject]@{
        Check = "LLVM member-scoped reduced-loop state"
        Present = $LlvmSource -match "\bm_reduced_loop_info\b"
    }
)

$SafetyComplete = @($SafetyChecks | Where-Object { -not $_.Present }).Count -eq 0
$UpstreamComplete = @($CommitRows | Where-Object { -not $_.Present }).Count -eq 0
$ArchitectureComplete = @($ArchitectureChecks | Where-Object { -not $_.Present }).Count -eq 0

if (-not $SafetyComplete) {
    $Classification = "unsafe-workflow"
} elseif (-not $UpstreamComplete -or -not $ArchitectureComplete) {
    $Classification = "full-port-required"
} else {
    $Classification = "host-verification-required"
}

Write-Output "# SPU Reduced-Loop Alignment Audit"
Write-Output ""
Write-Output ('- Android head: `{0}`' -f $AndroidHead)
Write-Output ('- Upstream head: `{0}`' -f $UpstreamHead)
Write-Output ('- Classification: `{0}`' -f $Classification)
Write-Output ('- Path-touching commits in upstream range: `{0}`' -f $PathCommitLines.Count)
Write-Output ""
Write-Output "## Safety"
Write-Output ""
Write-Output "| Check | Status |"
Write-Output "| --- | --- |"
foreach ($Row in $SafetyChecks) {
    $Status = if ($Row.Present) { "pass" } else { "missing" }
    Write-Output "| $($Row.Check) | $Status |"
}
Write-Output ""
Write-Output "## Required upstream commits"
Write-Output ""
Write-Output "| Commit | Purpose | Status |"
Write-Output "| --- | --- | --- |"
foreach ($Row in $CommitRows) {
    $Status = if ($Row.Present) { "ancestor" } else { "missing" }
    Write-Output ('| `{0}` | {1} | {2} |' -f $Row.Commit, $Row.Purpose, $Status)
}
Write-Output ""
Write-Output "## Vendored architecture"
Write-Output ""
Write-Output "| Required marker | Status |"
Write-Output "| --- | --- |"
foreach ($Row in $ArchitectureChecks) {
    $Status = if ($Row.Present) { "present" } else { "missing" }
    Write-Output "| $($Row.Check) | $Status |"
}
Write-Output ""
Write-Output "## Path-touching upstream sequence"
Write-Output ""
foreach ($Line in $PathCommitLines) {
    Write-Output ('- `{0}`' -f $Line)
}
Write-Output ""
Write-Output "Emission remains retired even when this audit reaches host-verification-required."
Write-Output "Re-enable only after a complete port, host build/proof, and a separate thermally guarded Thor validation."

if ($FailOnIncomplete -and $Classification -ne "host-verification-required") {
    exit 1
}
