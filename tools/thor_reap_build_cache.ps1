[CmdletBinding()]
param(
    [int]$Keep = 1,
    [switch]$Apply,
    [switch]$IncludeGradleCache
)

$ErrorActionPreference = "Stop"

# Reclaim the disk this project quietly eats.
#
# WHY THIS EXISTS
#
# app/.cxx/<buildType>/<hash>/ is keyed on the CMake argument list, so every
# distinct flag combination gets its own tree holding a full set of objects and
# an unstripped librpcsx-android.so. Nothing ever reaps them. One session that
# toggled -PrpcsxThorDebuggable, -PrpcsxThorWaitProfiler and
# -PrpcsxThorRsxAuditor left ~80 GB behind and filled a 930 GB disk.
#
# The failure does not look like a disk problem. Gradle reports:
#
#   Failed to stop service '...BuildFinishBuildService_...'
#   > There is not enough space on the disk
#
# with the cause in a sub-clause, under a Kotlin daemon heading. It reads like a
# toolchain fault, and the first instinct is to debug the build.
#
# DEFAULT IS A DRY RUN. Pass -Apply to actually delete. Everything it touches is
# regenerable build output; it never looks at sources, git, or APKs.

$repoRoot = Split-Path -Parent $PSScriptRoot
$cxxRoot = Join-Path $repoRoot "app/.cxx"

function Get-DirSize {
    param([string]$Path)
    try {
        return (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
    } catch { return 0 }
}

$drive = Get-PSDrive C
Write-Output ("C: {0:N1} GB free of {1:N1} GB" -f ($drive.Free / 1GB), (($drive.Free + $drive.Used) / 1GB))
Write-Output ""

if (-not (Test-Path $cxxRoot)) {
    Write-Output "No app/.cxx tree; nothing to reap."
    return
}

$reclaim = 0
foreach ($buildType in Get-ChildItem $cxxRoot -Directory -ErrorAction SilentlyContinue) {
    # Rank by the newest object file inside the tree, NOT by the tree directory's
    # own LastWriteTime. Those two disagree, and they disagreed in the dangerous
    # direction: measured here, 2v3i5c1h had the OLDEST directory stamp (08-08
    # 11:50) and the NEWEST objects (08-09 20:02) -- it was the active tree -- while
    # 6m3j1g1n had the newest directory stamp and objects six hours staler. Sorting
    # on the directory would have marked the tree in use STALE and deleted it,
    # costing a full native rebuild. A directory's mtime only changes when an entry
    # is added or removed from it; ninja overwrites existing .o files in place, so
    # a busy incremental tree can keep a very old directory stamp indefinitely.
    $trees = @(Get-ChildItem $buildType.FullName -Directory -ErrorAction SilentlyContinue |
        Where-Object { (Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue).Count -gt 0 } |
        ForEach-Object {
            $newest = (Get-ChildItem $_.FullName -Recurse -File -Filter *.o -ErrorAction SilentlyContinue |
                Measure-Object LastWriteTime -Maximum).Maximum
            if (-not $newest) { $newest = $_.LastWriteTime }
            $_ | Add-Member -NotePropertyName NewestObject -NotePropertyValue $newest -Force -PassThru
        } |
        Sort-Object NewestObject -Descending)

    if ($trees.Count -eq 0) { continue }

    Write-Output "$($buildType.Name)/"
    for ($i = 0; $i -lt $trees.Count; $i++) {
        $t = $trees[$i]
        $sz = Get-DirSize $t.FullName
        # Keep the N most recently written. The newest is whatever was built last,
        # which is what an incremental rebuild will want to reuse.
        $stale = $i -ge $Keep
        $mark = if ($stale) { "STALE" } else { "keep " }
        Write-Output ("  {0} {1,-14} {2,7:N1} GB  newest object {3}" -f $mark, $t.Name, ($sz / 1GB), $t.NewestObject.ToString('MM-dd HH:mm'))

        if ($stale) {
            $reclaim += $sz
            if ($Apply) {
                Remove-Item $t.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Write-Output ""
if ($IncludeGradleCache) {
    $gradleCache = Join-Path $env:USERPROFILE ".gradle/caches"
    if (Test-Path $gradleCache) {
        $sz = Get-DirSize $gradleCache
        Write-Output ("gradle caches: {0:N1} GB - NOT removed automatically." -f ($sz / 1GB))
        Write-Output "  Shared with every Gradle project on the machine, and re-downloading"
        Write-Output "  it is a network cost rather than a rebuild. Delete by hand if needed."
    }
}

Write-Output ("Reclaimable from app/.cxx: {0:N1} GB" -f ($reclaim / 1GB))
if ($Apply) {
    $after = (Get-PSDrive C).Free
    Write-Output ("C: {0:N1} GB free after" -f ($after / 1GB))
} else {
    Write-Output "Dry run. Re-run with -Apply to delete."
}

Write-Output ""
Write-Output "Note: app/build/ holds another copy of the merged native libs and the"
Write-Output "APK. './gradlew clean' clears it, and costs a re-link but not a full"
Write-Output "native recompile, because the objects live in app/.cxx."
