param(
    [string]$KernelRunDir = "",
    [string]$PairRunDir = "",
    [string]$CommandRunDir = "",
    [int]$Top = 12,
    [string]$OutPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-ReservationPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Convert-ReservationNumber {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [UInt64]0
    }

    $text = $Value.Trim()
    if ($text -match '^0x([0-9a-fA-F]+)$') {
        return [Convert]::ToUInt64($Matches[1], 16)
    }

    return [Convert]::ToUInt64($text, 10)
}

function Format-ReservationHexNumber {
    param([UInt64]$Value)
    return ("0x{0:x}" -f $Value)
}

function Format-ReservationHex {
    param([AllowNull()][string]$Value)
    return (Format-ReservationHexNumber (Convert-ReservationNumber $Value))
}

function Get-ReservationPairKey {
    param(
        [AllowNull()][string]$Pc,
        [AllowNull()][string]$Group,
        [AllowNull()][string]$Spu
    )

    return "$(Format-ReservationHex $Pc)|$Group|$Spu"
}

function Convert-ReservationDelta {
    param([UInt64]$Left, [UInt64]$Right)
    return ([Int64]$Left - [Int64]$Right)
}

function Sum-ReservationField {
    param([object[]]$Rows, [string]$Field)

    [UInt64]$sum = 0
    foreach ($row in $Rows) {
        if ($row.PSObject.Properties.Name -contains $Field) {
            $sum += Convert-ReservationNumber $row.$Field
        }
    }

    return $sum
}

function Get-ReservationField {
    param([AllowNull()][object]$Row, [string]$Field)

    if ($null -eq $Row -or !($Row.PSObject.Properties.Name -contains $Field)) {
        return [UInt64]0
    }

    return Convert-ReservationNumber $Row.$Field
}

function Max-ReservationField {
    param([object[]]$Rows, [string]$Field)

    [UInt64]$max = 0
    foreach ($row in $Rows) {
        if ($row.PSObject.Properties.Name -contains $Field) {
            $value = Convert-ReservationNumber $row.$Field
            if ($value -gt $max) {
                $max = $value
            }
        }
    }

    return $max
}

function Format-ReservationMb {
    param([UInt64]$Bytes)
    return ([double]$Bytes / 1MB).ToString("F2", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Import-ReservationCsv {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    return @(Import-Csv -LiteralPath $Path)
}

function Add-ReservationTable {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string[]]$Header,
        [object[]]$Rows,
        [scriptblock]$Render
    )

    $Lines.Add(($Header -join " | "))
    $Lines.Add((($Header | ForEach-Object { "---" }) -join " | "))

    foreach ($row in $Rows) {
        $Lines.Add((& $Render $row) -join " | ")
    }
}

if ([string]::IsNullOrWhiteSpace($KernelRunDir) -and [string]::IsNullOrWhiteSpace($PairRunDir) -and [string]::IsNullOrWhiteSpace($CommandRunDir)) {
    throw "Provide -KernelRunDir, -PairRunDir, -CommandRunDir, or a combination."
}

$kernelRoot = if ([string]::IsNullOrWhiteSpace($KernelRunDir)) { "" } else { Resolve-ReservationPath $KernelRunDir }
$pairRoot = if ([string]::IsNullOrWhiteSpace($PairRunDir)) { "" } else { Resolve-ReservationPath $PairRunDir }
$commandRoot = if ([string]::IsNullOrWhiteSpace($CommandRunDir)) { "" } else { Resolve-ReservationPath $CommandRunDir }

$kernelCsv = if ($kernelRoot) { Join-Path $kernelRoot "eternal-sonata-kernel-capsule-profile.csv" } else { "" }
$waitPcCsv = if ($kernelRoot) { Join-Path $kernelRoot "eternal-sonata-mfc-wait-pc-profile.csv" } else { "" }
$pairCsv = if ($pairRoot) { Join-Path $pairRoot "eternal-sonata-putllc16-pair-verify-profile.csv" } else { "" }
$commandCsv = if ($commandRoot) { Join-Path $commandRoot "eternal-sonata-reservation-loop-cmd-profile.csv" } else { "" }
$commandPcCsv = if ($commandRoot) { Join-Path $commandRoot "eternal-sonata-reservation-loop-cmd-pc-profile.csv" } else { "" }
$commandWaitPcCsv = if ($commandRoot) { Join-Path $commandRoot "eternal-sonata-mfc-wait-pc-profile.csv" } else { "" }

$kernelRows = Import-ReservationCsv $kernelCsv
$waitPcRows = Import-ReservationCsv $waitPcCsv
$pairRows = Import-ReservationCsv $pairCsv
$commandRows = Import-ReservationCsv $commandCsv
$commandPcRows = Import-ReservationCsv $commandPcCsv
$commandWaitPcRows = Import-ReservationCsv $commandWaitPcCsv

if ($kernelRoot -and $kernelRows.Count -eq 0) {
    Write-Warning "No kernel capsule CSV found at $kernelCsv"
}

if ($kernelRoot -and $waitPcRows.Count -eq 0) {
    Write-Warning "No MFC wait exact-PC CSV found at $waitPcCsv"
}

if ($pairRoot -and $pairRows.Count -eq 0) {
    Write-Warning "No PUTLLC16 pair verifier CSV found at $pairCsv"
}

if ($commandRoot -and $commandRows.Count -eq 0) {
    Write-Warning "No reservation-loop command CSV found at $commandCsv"
}

if ($commandRoot -and $commandPcRows.Count -eq 0) {
    Write-Warning "No reservation-loop command exact-PC CSV found at $commandPcCsv"
}

if ($commandRoot -and $commandWaitPcRows.Count -eq 0) {
    Write-Warning "No command-run MFC wait exact-PC CSV found at $commandWaitPcCsv"
}

$kernelByPc = @()
if ($kernelRows.Count) {
    $kernelByPc = $kernelRows |
        Group-Object max_dma_pc |
        ForEach-Object {
            $rows = @($_.Group)
            [pscustomobject]@{
                pc = if ([string]::IsNullOrWhiteSpace($_.Name)) { "0x0" } else { $_.Name }
                rows = $rows.Count
                total_bytes = Sum-ReservationField $rows "total_bytes"
                wait_reads = Sum-ReservationField $rows "wait_reads"
                atomic_reads = Sum-ReservationField $rows "atomic_reads"
                tagstat_reads = Sum-ReservationField $rows "tagstat_reads"
                rsx_bytes = Sum-ReservationField $rows "rsx_bytes"
                gpu_batch = Sum-ReservationField $rows "gpu_batch_candidate"
            }
        } |
        Sort-Object -Property total_bytes -Descending |
        Select-Object -First $Top
}

$waitPeaks = @()
if ($waitPcRows.Count) {
    $waitPeaks = $waitPcRows |
        Group-Object pc |
        ForEach-Object {
            $rows = @($_.Group)
            $maxRow = $rows |
                Sort-Object { Convert-ReservationNumber $_.reads } -Descending |
                Select-Object -First 1

            [pscustomobject]@{
                pc = if ([string]::IsNullOrWhiteSpace($_.Name)) { "0x0" } else { $_.Name }
                peak_reads = Max-ReservationField $rows "reads"
                peak_atomic = Max-ReservationField $rows "atomic_reads"
                peak_tagstat = Max-ReservationField $rows "tagstat_reads"
                group = $maxRow.group_name
                spu = $maxRow.spu_name
                last_pc = $maxRow.last_pc
                last_ch = $maxRow.last_ch
            }
        } |
        Sort-Object -Property peak_reads -Descending |
        Select-Object -First $Top
}

$pairByPc = @()
if ($pairRows.Count) {
    $pairByPc = $pairRows |
        Group-Object last_pc, group_name |
        ForEach-Object {
            $rows = @($_.Group)
            $maxRow = $rows |
                Sort-Object { Convert-ReservationNumber $_.hits } -Descending |
                Select-Object -First 1

            [pscustomobject]@{
                key = $_.Name
                peak_hits = Max-ReservationField $rows "hits"
                peak_extra_dirty = Max-ReservationField $rows "extra_dirty"
                peak_success = Max-ReservationField $rows "post_success"
                peak_failure = Max-ReservationField $rows "post_failure"
                peak_lr_event = Max-ReservationField $rows "post_lr_event_set"
                sample_eal = $maxRow.last_eal
            }
        } |
        Sort-Object -Property peak_hits -Descending |
        Select-Object -First $Top
}

$commandWaitByKey = @{}
if ($commandWaitPcRows.Count) {
    $commandWaitPcRows |
        Group-Object pc, group_name, spu_name |
        ForEach-Object {
            $rows = @($_.Group)
            $maxRow = $rows |
                Sort-Object { Convert-ReservationNumber $_.reads } -Descending |
                Select-Object -First 1

            $key = Get-ReservationPairKey $maxRow.pc $maxRow.group_name $maxRow.spu_name
            $commandWaitByKey[$key] = [pscustomobject]@{
                pc = Format-ReservationHex $maxRow.pc
                group = $maxRow.group_name
                spu = $maxRow.spu_name
                reads = Get-ReservationField $maxRow "reads"
                atomic_reads = Get-ReservationField $maxRow "atomic_reads"
                tagstat_reads = Get-ReservationField $maxRow "tagstat_reads"
                overflow_reads = Get-ReservationField $maxRow "overflow_reads"
                last_pc = $maxRow.last_pc
                last_ch = $maxRow.last_ch
            }
        }
}

$commandPcPeaks = @()
if ($commandPcRows.Count) {
    $commandPcPeaks = $commandPcRows |
        Group-Object pc, group_name, spu_name |
        ForEach-Object {
            $rows = @($_.Group)
            $maxRow = $rows |
                Sort-Object { Convert-ReservationNumber $_.cmd_hits } -Descending |
                Select-Object -First 1

            [pscustomobject]@{
                pc = Format-ReservationHex $maxRow.pc
                group = $maxRow.group_name
                spu = $maxRow.spu_name
                cmd_hits = Get-ReservationField $maxRow "cmd_hits"
                getllar_cmds = Get-ReservationField $maxRow "getllar_cmds"
                putllc_cmds = Get-ReservationField $maxRow "putllc_cmds"
                putlluc_cmds = Get-ReservationField $maxRow "putlluc_cmds"
                putqlluc_cmds = Get-ReservationField $maxRow "putqlluc_cmds"
                atomic_updates = Get-ReservationField $maxRow "atomic_updates"
                getllar_success = Get-ReservationField $maxRow "getllar_success"
                putllc_success = Get-ReservationField $maxRow "putllc_success"
                putllc_failure = Get-ReservationField $maxRow "putllc_failure"
                atomic_other = Get-ReservationField $maxRow "atomic_other"
                overflow = Get-ReservationField $maxRow "overflow"
            }
        } |
        Sort-Object -Property cmd_hits -Descending
}

$allCommandReadPairs = @()
if ($commandPcPeaks.Count) {
    $allCommandReadPairs = @(
        foreach ($cmd in $commandPcPeaks) {
            $waitPc = Format-ReservationHexNumber ((Convert-ReservationNumber $cmd.pc) + 4)
            $waitKey = Get-ReservationPairKey $waitPc $cmd.group $cmd.spu
            $wait = $commandWaitByKey[$waitKey]
            [UInt64]$waitReads = if ($null -ne $wait) { $wait.reads } else { 0 }
            [UInt64]$waitAtomicReads = if ($null -ne $wait) { $wait.atomic_reads } else { 0 }

            [pscustomobject]@{
                cmd_pc = $cmd.pc
                wait_pc = $waitPc
                group = $cmd.group
                spu = $cmd.spu
                cmd_hits = $cmd.cmd_hits
                getllar_cmds = $cmd.getllar_cmds
                putllc_cmds = $cmd.putllc_cmds
                atomic_updates = $cmd.atomic_updates
                getllar_success = $cmd.getllar_success
                putllc_success = $cmd.putllc_success
                putllc_failure = $cmd.putllc_failure
                atomic_other = $cmd.atomic_other
                wait_reads = $waitReads
                wait_atomic_reads = $waitAtomicReads
                cmd_read_delta = Convert-ReservationDelta $cmd.cmd_hits $waitReads
                atomic_read_delta = Convert-ReservationDelta $cmd.atomic_updates $waitAtomicReads
                overflow = $cmd.overflow
            }
        }
    ) |
        Sort-Object -Property cmd_hits -Descending
}

$commandReadPairs = @($allCommandReadPairs | Select-Object -First $Top)
$primaryGetllarPair = $allCommandReadPairs |
    Where-Object { $_.cmd_pc -eq "0xa70" -and $_.wait_pc -eq "0xa74" -and $_.getllar_cmds -gt 0 } |
    Select-Object -First 1
$primaryPutllcPair = $allCommandReadPairs |
    Where-Object { $_.cmd_pc -eq "0xad4" -and $_.wait_pc -eq "0xad8" -and $_.putllc_cmds -gt 0 } |
    Select-Object -First 1
$hasPrimaryCommandFront = $null -ne $primaryGetllarPair -and $null -ne $primaryPutllcPair

$totalRsxBytes = Sum-ReservationField $kernelRows "rsx_bytes"
$totalGpuBatch = Sum-ReservationField $kernelRows "gpu_batch_candidate"
$totalKernelBytes = Sum-ReservationField $kernelRows "total_bytes"
$peakPairExtraDirty = Max-ReservationField $pairRows "extra_dirty"
$peakPairPostFailure = Max-ReservationField $pairRows "post_failure"
$peakPairHits = Max-ReservationField $pairRows "hits"
$peakCommandRow = if ($commandRows.Count) {
    $commandRows |
        Sort-Object { Convert-ReservationNumber $_.cmd_hits } -Descending |
        Select-Object -First 1
} else {
    $null
}
$peakCommandHits = Get-ReservationField $peakCommandRow "cmd_hits"
$peakCommandGetllar = Get-ReservationField $peakCommandRow "getllar_cmds"
$peakCommandPutllc = Get-ReservationField $peakCommandRow "putllc_cmds"
$peakCommandAtomic = Get-ReservationField $peakCommandRow "atomic_updates"
$peakCommandPutllcFailure = Get-ReservationField $peakCommandRow "putllc_failure"

$gpuDecision = if ($kernelRows.Count -and $totalRsxBytes -eq 0 -and $totalGpuBatch -eq 0) {
    "broad-spu-vulkan-parked"
} elseif ($kernelRows.Count) {
    "check-rsx-consumed-candidates"
} else {
    "kernel-capsule-data-missing"
}

$pairDecision = if ($pairRows.Count -and ($peakPairExtraDirty -gt 0 -or $peakPairPostFailure -gt 0)) {
    "pair-fast-unsafe"
} elseif ($pairRows.Count) {
    "pair-fast-needs-visual-proof"
} else {
    "pair-verifier-data-missing"
}

$commandDecision = if ($hasPrimaryCommandFront -and $primaryGetllarPair.cmd_read_delta -eq 0 -and $primaryPutllcPair.cmd_read_delta -eq 0) {
    "whole-loop-recognizer-preflight"
} elseif ($commandPcRows.Count) {
    "command-correlation-needs-more-proof"
} else {
    "command-correlation-data-missing"
}

$baseDecision = if ($gpuDecision -eq "broad-spu-vulkan-parked" -and $pairDecision -eq "pair-fast-unsafe") {
    "whole-loop-verify-first"
} else {
    "collect-missing-proof"
}

$nextDecision = if ($baseDecision -eq "whole-loop-verify-first" -and $commandDecision -eq "whole-loop-recognizer-preflight") {
    "whole-loop-recognizer-preflight"
} else {
    $baseDecision
}

$loopFrontPcs = @("0xa74", "0x0a74", "0xad8", "0x0ad8", "0xb44", "0x0b44")
$loopFrontWaitPeaks = @($waitPeaks | Where-Object {
    $pc = if ($_.pc) { $_.pc.ToString().ToLowerInvariant() } else { "" }
    $loopFrontPcs -contains $pc
})
$hasLoopFrontEvidence = $loopFrontWaitPeaks.Count -gt 0

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Eternal Sonata SPU Reservation Loop Summary")
$lines.Add("")
$lines.Add("- Generated: $(Get-Date -Format o)")
if ($kernelRoot) {
    $lines.Add("- Kernel run: $kernelRoot")
}
if ($pairRoot) {
    $lines.Add("- Pair verifier run: $pairRoot")
}
if ($commandRoot) {
    $lines.Add("- Command run: $commandRoot")
}
$lines.Add("- Kernel capsule rows: $($kernelRows.Count)")
$lines.Add("- MFC wait exact-PC rows: $($waitPcRows.Count)")
$lines.Add("- PUTLLC16 pair verifier rows: $($pairRows.Count)")
$lines.Add("- Reservation command rows: $($commandRows.Count)")
$lines.Add("- Reservation command exact-PC rows: $($commandPcRows.Count)")
$lines.Add("- Command-run MFC wait exact-PC rows: $($commandWaitPcRows.Count)")
$lines.Add("- Total kernel bytes: $(Format-ReservationMb $totalKernelBytes) MB")
$lines.Add("- Total RSX-local bytes: $(Format-ReservationMb $totalRsxBytes) MB")
$lines.Add("- Total GPU-batch candidate flags: $totalGpuBatch")
$lines.Add("- Peak pair hits / extra-dirty / post-failure: $peakPairHits / $peakPairExtraDirty / $peakPairPostFailure")
$lines.Add("- Peak command snapshot hits GETLLAR/PUTLLC/Atomic/PUTLLC-fail: $peakCommandHits / $peakCommandGetllar / $peakCommandPutllc / $peakCommandAtomic / $peakCommandPutllcFailure")
$lines.Add("- Command/read decision: $commandDecision")
$lines.Add("- Decision: $nextDecision")
$lines.Add("")
$lines.Add("## Kernel Capsule By Hot PC")
$lines.Add("")
if ($kernelByPc.Count) {
    Add-ReservationTable $lines @("PC", "Rows", "Total MB", "Wait Reads", "Atomic Reads", "TagStat Reads", "RSX Bytes", "GPU Batch") $kernelByPc {
        param($row)
        @(
            "``$($row.pc)``",
            "$($row.rows)",
            "$(Format-ReservationMb $row.total_bytes)",
            "$($row.wait_reads)",
            "$($row.atomic_reads)",
            "$($row.tagstat_reads)",
            "$($row.rsx_bytes)",
            "$($row.gpu_batch)"
        )
    }
} else {
    $lines.Add("No kernel capsule rows were available.")
}
$lines.Add("")
$lines.Add("## Exact Wait PC Peaks")
$lines.Add("")
if ($waitPeaks.Count) {
    Add-ReservationTable $lines @("PC", "Peak Reads", "Atomic", "TagStat", "Group", "SPU", "Last PC", "Last Ch") $waitPeaks {
        param($row)
        @(
            "``$($row.pc)``",
            "$($row.peak_reads)",
            "$($row.peak_atomic)",
            "$($row.peak_tagstat)",
            "``$($row.group)``",
            "``$($row.spu)``",
            "``$($row.last_pc)``",
            "$($row.last_ch)"
        )
    }
} else {
    $lines.Add("No exact wait-PC rows were available.")
}
$lines.Add("")
$lines.Add("## Reservation Command/Read Correlation")
$lines.Add("")
if ($commandReadPairs.Count) {
    Add-ReservationTable $lines @("Cmd PC", "Wait PC", "Cmd Hits", "GETLLAR", "PUTLLC", "Atomic Updates", "GET OK", "PUT OK", "PUT Fail", "Wait Reads", "Wait Atomic", "Cmd-Read Delta", "Atomic-Read Delta", "Group", "SPU") $commandReadPairs {
        param($row)
        @(
            "``$($row.cmd_pc)``",
            "``$($row.wait_pc)``",
            "$($row.cmd_hits)",
            "$($row.getllar_cmds)",
            "$($row.putllc_cmds)",
            "$($row.atomic_updates)",
            "$($row.getllar_success)",
            "$($row.putllc_success)",
            "$($row.putllc_failure)",
            "$($row.wait_reads)",
            "$($row.wait_atomic_reads)",
            "$($row.cmd_read_delta)",
            "$($row.atomic_read_delta)",
            "``$($row.group)``",
            "``$($row.spu)``"
        )
    }

    if ($hasPrimaryCommandFront) {
        $lines.Add("")
        $lines.Add('- Primary front: `0xa70 -> 0xa74` GETLLAR/AtomicStat and `0xad4 -> 0xad8` PUTLLC/AtomicStat.')
        $lines.Add("- Primary command/read deltas: GETLLAR $($primaryGetllarPair.cmd_read_delta), PUTLLC $($primaryPutllcPair.cmd_read_delta).")
    }
} else {
    $lines.Add("No command/read correlation rows were available.")
}
$lines.Add("")
$lines.Add("## PUTLLC16 Pair Verifier Peaks")
$lines.Add("")
if ($pairByPc.Count) {
    Add-ReservationTable $lines @("PC/Group", "Peak Hits", "Extra Dirty", "Post Success", "Post Failure", "LR Event", "Sample EAL") $pairByPc {
        param($row)
        @(
            "``$($row.key)``",
            "$($row.peak_hits)",
            "$($row.peak_extra_dirty)",
            "$($row.peak_success)",
            "$($row.peak_failure)",
            "$($row.peak_lr_event)",
            "``$($row.sample_eal)``"
        )
    }
} else {
    $lines.Add("No pair verifier rows were available.")
}
$lines.Add("")
$lines.Add("## Reading")
$lines.Add("")
if ($nextDecision -eq "whole-loop-verify-first" -or $nextDecision -eq "whole-loop-recognizer-preflight") {
    $lines.Add("- Broad SPU Vulkan compute stays parked because the kernel capsules still show zero RSX-local bytes and zero GPU-batch candidates.")
    $lines.Add("- The two-slot PUTLLC16 pair shortcut stays unsafe because the verifier still reports extra-dirty or post-failure evidence.")
    if ($commandDecision -eq "whole-loop-recognizer-preflight") {
        $lines.Add("- Command/read correlation now gives a coherent verifier target: GETLLAR and PUTLLC command PCs pair with the next AtomicStat read PCs with zero primary command/read delta.")
    }
    $lines.Add('- The next useful Windows-only experiment is a profile/verify hook for the whole `0xa74` / `0xad8` reservation retry loop, not another isolated pair fast path.')
} else {
    $lines.Add("- Missing or mixed evidence prevents a narrow next-step classification. Re-run kernel capsule and pair verifier captures before changing fast paths.")
}
$lines.Add('- Classification: `analysis`, `spu-reservation-loop-summary`, not `gpu-migration-credit`, not `windows-micro-win`, not a 200% gate candidate.')

if ($nextDecision -eq "whole-loop-verify-first" -or $nextDecision -eq "whole-loop-recognizer-preflight") {
    $lines.Add("")
    $lines.Add("## Whole-Loop Hook Preflight")
    $lines.Add("")
    if ($hasLoopFrontEvidence) {
        $lines.Add('- Exact wait-PC evidence includes the reservation-loop front (`0xa74` / `0xad8` / `0xb44`), so the next code slice can be PC-gated instead of broad-channel-gated.')
    } else {
        $lines.Add("- Exact wait-PC evidence did not include the reservation-loop front in the top rows. Re-run with a higher `-Top` value before adding a PC-gated verifier.")
    }
    $lines.Add('- Candidate switch: `RPCS3_ES_RESERVATION_LOOP=profile|verify`, default off, gated to title `BLUS30161` and SPU image `0x958dfe208b686622`.')
    $lines.Add('- Primary LLVM hook: `SPULLVMRecompiler.cpp::get_rdch()` / `RDCH(MFC_RdAtomicStat)` in the `0xa74..0xb44` retry band. It already splits fast channel reads from blocking fallback, so it can count AtomicStat values without consuming extra channel state.')
    $lines.Add('- Primary interpreter hook: `SPUThread.cpp::get_ch_value(MFC_RdAtomicStat)` behind the same title/image/PC gate for non-JIT or blocking-read parity.')
    $lines.Add('- Secondary command hook: `WRCH(MFC_Cmd)` / `set_ch_value(MFC_Cmd)` around GETLLAR and PUTLLC PCs if RDCH-only counters cannot reconstruct loop entry, retry, and exit.')
    if ($commandDecision -eq "whole-loop-recognizer-preflight") {
        $lines.Add('- Command-paired verifier front: `0xa70` GETLLAR -> `0xa74` AtomicStat read, then `0xad4` PUTLLC -> `0xad8` AtomicStat read. Treat this as a recognizer input, not a fast path.')
    }
    $lines.Add('- First verifier counters: loop entries, retry reads, GETLLAR command hits, PUTLLC command hits, AtomicStat success/failure/other values, `raddr`/`rtime` match, dirty-slot mask, LR event state, and post-loop observable state.')
    $lines.Add("- Do not change PUTLLC semantics, reservation notification, or SPU-to-Vulkan execution in the first hook slice. The first pass is profile/verify only.")
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $base = if ($commandRoot) { $commandRoot } elseif ($pairRoot) { $pairRoot } else { $kernelRoot }
    $OutPath = Join-Path $base "eternal-sonata-spu-reservation-loop-summary.md"
}

$resolvedOut = Resolve-ReservationPath $OutPath
$outDir = Split-Path -Parent $resolvedOut
if (![string]::IsNullOrWhiteSpace($outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$lines | Set-Content -LiteralPath $resolvedOut -Encoding UTF8
$lines | ForEach-Object { Write-Output $_ }
