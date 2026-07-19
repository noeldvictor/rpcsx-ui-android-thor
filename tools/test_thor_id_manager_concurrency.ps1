$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$sources = [ordered]@{
    Android = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/IdManager.h"
    Windows = Join-Path $workspaceRoot "rpcs3-upstream/rpcs3/Emu/IdManager.h"
}

function Get-ContractSegment {
    param(
        [string]$Source,
        [string]$StartMarker,
        [string]$EndMarker
    )

    $start = $Source.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Missing IdManager contract marker: $StartMarker"
    }

    $end = $Source.IndexOf(
        $EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) {
        throw "Missing IdManager contract marker: $EndMarker"
    }

    return $Source.Substring($start, $end - $start)
}

function Assert-FragmentsInOrder {
    param(
        [string]$Name,
        [string]$Source,
        [string[]]$Fragments
    )

    $cursor = 0
    foreach ($fragment in $Fragments) {
        $index = $Source.IndexOf(
            $fragment, $cursor, [StringComparison]::Ordinal)
        if ($index -lt 0) {
            throw "$Name is missing or misorders: $fragment"
        }
        $cursor = $index + $fragment.Length
    }
}

$contracts = @(
    @{
        Name = "remove"
        Start = "// Remove the ID"
        End = "// Remove the ID if matches"
        Return = "return false;"
    },
    @{
        Name = "remove_verify"
        Start = "// Remove the ID if matches"
        End = "// Remove the ID and return the object"
        Return = "return false;"
    },
    @{
        Name = "withdraw"
        Start = "// Remove the ID and return the object"
        End = "// Remove the ID after accessing the object"
        Return = "return ptr;"
    }
)

foreach ($entry in $sources.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Missing $($entry.Key) IdManager source: $($entry.Value)"
    }

    $source = Get-Content -LiteralPath $entry.Value -Raw
    foreach ($contract in $contracts) {
        $segment = Get-ContractSegment -Source $source -StartMarker $contract.Start -EndMarker $contract.End
        Assert-FragmentsInOrder -Name "$($entry.Key) $($contract.Name)" -Source $segment -Fragments @(
            "const u32 index = get_index<Get>(id);",
            "if (index >= id_manager::id_traits<Get>::count)",
            $contract.Return,
            "lock(id_manager::g_mutex)",
            "find_index<T, Get>(index, id)"
        )

        if ($segment.Contains("find_id<T, Get>(id)")) {
            throw "$($entry.Key) $($contract.Name) still recomputes the ID index under the global lock."
        }
    }
}

Write-Output "Thor IdManager concurrency contract passed: removal paths validate and resolve indices before taking the global object lock."
