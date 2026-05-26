param(
    [string]$RunDir = "",
    [string]$LogPath = "",
    [int]$Top = 25,
    [string]$OutPath = "",
    [string]$CsvPath = "",
    [string]$MfcShapeCsvPath = "",
    [string]$MfcLadderCsvPath = "",
    [string]$SpuHleVerifyCsvPath = "",
    [string]$SpuHleShadowCsvPath = "",
    [string]$SpuHle25ccFamilyCsvPath = "",
    [string]$SpuHle25ccShadowCsvPath = "",
    [string]$SpuHle25ccBodyCsvPath = "",
    [string]$SpuHle451cListSeedCsvPath = "",
    [string]$SpuHle451cListFamilyCsvPath = "",
    [string]$SpuHle451cDescBatchCsvPath = "",
    [string]$SpuHle451cPreserveBodyCsvPath = "",
    [string]$MfcDynamicCsvPath = "",
    [string]$MfcListCsvPath = "",
    [string]$MfcWaitCsvPath = "",
    [string]$MfcWaitPcCsvPath = "",
    [string]$ReservationLoopCmdCsvPath = "",
    [string]$ReservationLoopCmdPcCsvPath = "",
    [string]$ReservationLoopVerifyCsvPath = "",
    [string]$ReservationLoopRdchJoinCsvPath = "",
    [string]$ReservationLoopLaneJoinCsvPath = "",
    [string]$ReservationLoopRawLaneCsvPath = "",
    [string]$Putllc16CsvPath = "",
    [string]$Putllc16RuntimeCsvPath = "",
    [string]$Putllc16PairVerifyCsvPath = "",
    [string]$KernelCapsuleCsvPath = "",
    [string]$RsxOverlapCsvPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-ProbePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Resolve-ProbeLogPath {
    param([string]$RunDir)

    $root = Resolve-ProbePath $RunDir
    $candidates = @(
        "RPCS3.log",
        "RPCSX.log",
        "logcat-full.txt",
        "logcat-live.txt",
        "thor-rsx-auditor-logcat.txt",
        "rpcsx-live-tail.txt"
    )

    foreach ($candidate in $candidates) {
        $path = Join-Path $root $candidate
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    $fallback = Get-ChildItem -LiteralPath $root -Recurse -File -Include $candidates -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if ($fallback) {
        return $fallback.FullName
    }

    return Join-Path $root "RPCS3.log"
}

function Convert-ProbeNumber {
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

function Format-ProbeHex {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "0x0"
    }

    $text = $Value.Trim()
    if ($text -match '^0x') {
        return $text.ToLowerInvariant()
    }

    return ("0x{0:x}" -f (Convert-ProbeNumber $text))
}

function Format-ProbeHexNumber {
    param([UInt64]$Value)
    return ("0x{0:x}" -f $Value)
}

function Format-ProbeHexToken {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $text = $Value.Trim()
    if ($text -match '^0x') {
        return $text.ToLowerInvariant()
    }

    if ($text -match '^[0-9a-fA-F]+$') {
        return "0x$($text.ToLowerInvariant())"
    }

    return $text.ToLowerInvariant()
}

function Format-ProbeBytes {
    param([UInt64]$Value)

    if ($Value -ge 1048576) {
        return ("{0:N2} MB" -f ([double]$Value / 1048576.0))
    }
    if ($Value -ge 1024) {
        return ("{0:N1} KB" -f ([double]$Value / 1024.0))
    }
    return "$Value B"
}

function Format-ProbePercent {
    param(
        [UInt64]$Numerator,
        [UInt64]$Denominator
    )

    if ($Denominator -eq 0) {
        return "0.000%"
    }

    return ("{0:n3}%" -f (([double]$Numerator / [double]$Denominator) * 100.0))
}

function Get-ProbeSignedDelta {
    param(
        [UInt64]$Value,
        [UInt64]$Reference
    )

    return ([Int64]$Value - [Int64]$Reference)
}

function Find-ProbeWaitPcPeak {
    param(
        [hashtable]$WaitPcPeakByPc,
        [AllowNull()][string]$TargetPc,
        [UInt64]$WindowBytes = 0
    )

    if ([string]::IsNullOrWhiteSpace($TargetPc) -or $WaitPcPeakByPc.Count -eq 0) {
        return $null
    }

    $target = Convert-ProbeNumber $TargetPc
    $best = $null
    $bestDiff = [UInt64]::MaxValue

    foreach ($pc in $WaitPcPeakByPc.Keys) {
        $pcValue = Convert-ProbeNumber $pc
        $diff = if ($pcValue -gt $target) { $pcValue - $target } else { $target - $pcValue }
        if ($diff -le $WindowBytes -and ($diff -lt $bestDiff -or ($diff -eq $bestDiff -and $WaitPcPeakByPc[$pc].reads -gt $best.reads))) {
            $best = $WaitPcPeakByPc[$pc]
            $bestDiff = $diff
        }
    }

    return $best
}

function Get-ProbeObjectNumber {
    param(
        [AllowNull()][object]$Record,
        [string]$Property
    )

    if ($null -eq $Record) {
        return [UInt64]0
    }

    $prop = $Record.PSObject.Properties[$Property]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return [UInt64]0
    }

    return Convert-ProbeNumber ([string]$prop.Value)
}

function Find-ReservationLoopPeakPcRecord {
    param(
        $Records,
        [string[]]$Pcs,
        [string]$Metric
    )

    $normalized = @($Pcs | ForEach-Object { Format-ProbeHexToken $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($normalized.Count -eq 0) {
        return [pscustomobject]@{ pc = ""; value = [UInt64]0; group_name = ""; spu_name = ""; record = $null }
    }

    $best = $null
    $bestValue = [UInt64]0

    foreach ($record in @($Records | ForEach-Object { $_ })) {
        $pc = Format-ProbeHexToken $record.pc
        if ($normalized -notcontains $pc) {
            continue
        }

        $value = Get-ProbeObjectNumber -Record $record -Property $Metric
        if ($null -eq $best -or $value -gt $bestValue) {
            $best = $record
            $bestValue = $value
        }
    }

    if ($null -eq $best) {
        return [pscustomobject]@{ pc = ""; value = [UInt64]0; group_name = ""; spu_name = ""; record = $null }
    }

    return [pscustomobject]@{
        pc         = $best.pc
        value      = $bestValue
        group_name = $best.group_name
        spu_name   = $best.spu_name
        record     = $best
    }
}

function Get-ReservationLoopLaneJoinRows {
    param(
        $CmdPcRecords,
        $WaitPcRecords,
        $VerifyRecords,
        $RawLaneRows
    )

    $knownLanes = @(
        [pscustomobject]@{ lane = 1; getllar_focus_cmd_pc = "0xa70"; getllar_raw_cmd_pc = "0xaec"; getllar_focus_read_pc = "0xa74"; getllar_raw_read_pc = "0xaf0"; putllc_focus_cmd_pc = "0xad4"; putllc_raw_cmd_pc = "0xb40"; putllc_focus_read_pc = "0xad8"; putllc_raw_read_pc = "0xb44"; retry_pc = "0xb48"; next_branch_pc = "0xb78" },
        [pscustomobject]@{ lane = 2; getllar_focus_cmd_pc = "0xb64"; getllar_raw_cmd_pc = "0xbe0"; getllar_focus_read_pc = "0xb68"; getllar_raw_read_pc = "0xbe4"; putllc_focus_cmd_pc = "0xc24"; putllc_raw_cmd_pc = "0xc24"; putllc_focus_read_pc = "0xc28"; putllc_raw_read_pc = "0xc28"; retry_pc = "0xc2c"; next_branch_pc = "0xcac" },
        [pscustomobject]@{ lane = 3; getllar_focus_cmd_pc = "0xc6c"; getllar_raw_cmd_pc = "0xc6c"; getllar_focus_read_pc = "0xc70"; getllar_raw_read_pc = "0xc70"; putllc_focus_cmd_pc = "0xca4"; putllc_raw_cmd_pc = "0xca4"; putllc_focus_read_pc = "0xca8"; putllc_raw_read_pc = "0xca8"; retry_pc = "0xcac"; next_branch_pc = "0xcc0" }
    )

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($lane in $knownLanes) {
        $getCmd = Find-ReservationLoopPeakPcRecord -Records $CmdPcRecords -Pcs @($lane.getllar_focus_cmd_pc, $lane.getllar_raw_cmd_pc) -Metric "getllar_cmds"
        $putCmd = Find-ReservationLoopPeakPcRecord -Records $CmdPcRecords -Pcs @($lane.putllc_focus_cmd_pc, $lane.putllc_raw_cmd_pc) -Metric "putllc_cmds"
        $getRead = Find-ReservationLoopPeakPcRecord -Records $WaitPcRecords -Pcs @($lane.getllar_focus_read_pc, $lane.getllar_raw_read_pc) -Metric "atomic_reads"
        $putRead = Find-ReservationLoopPeakPcRecord -Records $WaitPcRecords -Pcs @($lane.putllc_focus_read_pc, $lane.putllc_raw_read_pc) -Metric "atomic_reads"

        $rawRow = @(
            $RawLaneRows |
                Where-Object {
                    (Format-ProbeHexToken $_.raw_getllar_cmd_pc) -eq (Format-ProbeHexToken $lane.getllar_raw_cmd_pc) -and
                    (Format-ProbeHexToken $_.raw_putllc_cmd_pc) -eq (Format-ProbeHexToken $lane.putllc_raw_cmd_pc)
                } |
                Sort-Object @{Expression = { Get-ProbeObjectNumber -Record $_ -Property "putllc_cmd_hits" }; Descending = $true} |
                Select-Object -First 1
        )

        $verifyRows = @($VerifyRecords | Where-Object { (Get-ProbeObjectNumber -Record $_ -Property "lane") -eq [UInt64]$lane.lane })
        $verifyPeak = $null
        if ($verifyRows.Count -gt 0) {
            $verifyPeak = $verifyRows |
                Sort-Object @{Expression = { Get-ProbeObjectNumber -Record $_ -Property "attempts" }; Descending = $true}, @{Expression = { Get-ProbeObjectNumber -Record $_ -Property "completed" }; Descending = $true} |
                Select-Object -First 1
        }

        $exactSeen = $getCmd.value -gt 0 -or $putCmd.value -gt 0 -or $getRead.value -gt 0 -or $putRead.value -gt 0
        $verifySeen = $verifyRows.Count -gt 0
        $classification = if ($verifySeen) {
            "live-verify-seen"
        } elseif ($exactSeen) {
            "exact-pc-seen-live-verify-missing"
        } else {
            "raw-or-empty"
        }

        $exactGroup = if (-not [string]::IsNullOrWhiteSpace($putCmd.group_name)) { $putCmd.group_name } elseif (-not [string]::IsNullOrWhiteSpace($getCmd.group_name)) { $getCmd.group_name } elseif (-not [string]::IsNullOrWhiteSpace($putRead.group_name)) { $putRead.group_name } else { $getRead.group_name }
        $exactSpu = if (-not [string]::IsNullOrWhiteSpace($putCmd.spu_name)) { $putCmd.spu_name } elseif (-not [string]::IsNullOrWhiteSpace($getCmd.spu_name)) { $getCmd.spu_name } elseif (-not [string]::IsNullOrWhiteSpace($putRead.spu_name)) { $putRead.spu_name } else { $getRead.spu_name }
        $rawFirst = if ($rawRow.Count -gt 0) { $rawRow[0] } else { $null }

        $rows.Add([pscustomobject]@{
            lane                  = $lane.lane
            getllar_focus_cmd_pc  = $lane.getllar_focus_cmd_pc
            getllar_raw_cmd_pc    = $lane.getllar_raw_cmd_pc
            getllar_cmd_peak_pc   = $getCmd.pc
            getllar_cmd_hits      = $getCmd.value
            getllar_focus_read_pc = $lane.getllar_focus_read_pc
            getllar_raw_read_pc   = $lane.getllar_raw_read_pc
            getllar_read_peak_pc  = $getRead.pc
            getllar_read_hits     = $getRead.value
            putllc_focus_cmd_pc   = $lane.putllc_focus_cmd_pc
            putllc_raw_cmd_pc     = $lane.putllc_raw_cmd_pc
            putllc_cmd_peak_pc    = $putCmd.pc
            putllc_cmd_hits       = $putCmd.value
            putllc_focus_read_pc  = $lane.putllc_focus_read_pc
            putllc_raw_read_pc    = $lane.putllc_raw_read_pc
            putllc_read_peak_pc   = $putRead.pc
            putllc_read_hits      = $putRead.value
            retry_pc              = $lane.retry_pc
            next_branch_pc        = $lane.next_branch_pc
            raw_lane_cmd_hits     = if ($null -ne $rawFirst) { Get-ProbeObjectNumber -Record $rawFirst -Property "putllc_cmd_hits" } else { [UInt64]0 }
            raw_lane_read_hits    = if ($null -ne $rawFirst) { Get-ProbeObjectNumber -Record $rawFirst -Property "putllc_read_hits" } else { [UInt64]0 }
            verify_row_count      = $verifyRows.Count
            verify_attempts       = Get-ProbeObjectNumber -Record $verifyPeak -Property "attempts"
            verify_completed      = Get-ProbeObjectNumber -Record $verifyPeak -Property "completed"
            verify_success        = Get-ProbeObjectNumber -Record $verifyPeak -Property "success"
            verify_failure        = Get-ProbeObjectNumber -Record $verifyPeak -Property "failure"
            verify_unexpected     = Get-ProbeObjectNumber -Record $verifyPeak -Property "unexpected"
            verify_retry_branches = Get-ProbeObjectNumber -Record $verifyPeak -Property "retry_branches"
            verify_retry_taken    = Get-ProbeObjectNumber -Record $verifyPeak -Property "retry_taken"
            verify_retry_fallthrough = Get-ProbeObjectNumber -Record $verifyPeak -Property "retry_fallthrough"
            verify_next_branches  = Get-ProbeObjectNumber -Record $verifyPeak -Property "next_branches"
            verify_next_taken     = Get-ProbeObjectNumber -Record $verifyPeak -Property "next_taken"
            verify_next_fallthrough = Get-ProbeObjectNumber -Record $verifyPeak -Property "next_fallthrough"
            exact_group_name      = $exactGroup
            exact_spu_name        = $exactSpu
            raw_group_name        = if ($null -ne $rawFirst) { $rawFirst.group_name } else { "" }
            raw_spu_name          = if ($null -ne $rawFirst) { $rawFirst.spu_name } else { "" }
            classification        = $classification
            cause                 = "0x0"
            status                = "0x0"
        }) | Out-Null
    }

    return @($rows | Sort-Object -Property putllc_cmd_hits,getllar_cmd_hits,putllc_read_hits,getllar_read_hits -Descending)
}

function Get-ReservationLoopVerifyPeakRows {
    param($Records)

    $recordItems = @($Records | ForEach-Object { $_ })

    if ($recordItems.Count -eq 0) {
        return @()
    }

    $laneItems = @($recordItems | Where-Object { $_.scope -eq "lane" })
    $sourceItems = if ($laneItems.Count -gt 0) { $laneItems } else { $recordItems }

    return @(
        $sourceItems |
            Group-Object -Property group_name,spu_name,lane |
            ForEach-Object {
                $_.Group | Sort-Object -Property attempts,completed -Descending | Select-Object -First 1
            } |
            Sort-Object -Property attempts,completed -Descending
    )
}

function Get-ReservationLoopRdchJoinRows {
    param(
        $VerifyPeakRows,
        $WaitPcRecords
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $verifyItems = @($VerifyPeakRows | ForEach-Object { $_ })
    $waitItems = @($WaitPcRecords | ForEach-Object { $_ })

    if ($verifyItems.Count -eq 0 -or $waitItems.Count -eq 0) {
        return @()
    }

    foreach ($record in $verifyItems) {
        $matchingWaitRows = @(
            $waitItems |
                Where-Object {
                    $_.title -eq $record.title -and
                    $_.group_name -eq $record.group_name -and
                    $_.spu_name -eq $record.spu_name -and
                    $_.entry -eq $record.entry -and
                    $_.image_sig -eq $record.image_sig
                }
        )

        if ($matchingWaitRows.Count -eq 0) {
            continue
        }

        $getllarRead = @(
            $matchingWaitRows |
                Where-Object { $_.pc -eq "0xa74" } |
                Sort-Object -Property atomic_reads,reads -Descending |
                Select-Object -First 1
        )
        $putllcRead = @(
            $matchingWaitRows |
                Where-Object { $_.pc -eq "0xad8" } |
                Sort-Object -Property atomic_reads,reads -Descending |
                Select-Object -First 1
        )

        $getllarReadPc = "0x0"
        $getllarExactReads = [UInt64]0
        if ($getllarRead.Count -gt 0) {
            $getllarReadPc = $getllarRead[0].pc
            $getllarExactReads = [UInt64]$getllarRead[0].atomic_reads
        }

        $putllcReadPc = "0x0"
        $putllcExactReads = [UInt64]0
        if ($putllcRead.Count -gt 0) {
            $putllcReadPc = $putllcRead[0].pc
            $putllcExactReads = [UInt64]$putllcRead[0].atomic_reads
        }

        if ($getllarExactReads -eq 0 -and $putllcExactReads -eq 0) {
            continue
        }

        $exactReads = [UInt64]($getllarExactReads + $putllcExactReads)
        $rows.Add([pscustomobject]@{
            mode                         = $record.mode
            reservation_mode             = $record.reservation_mode
            title                        = $record.title
            group                        = $record.group
            group_name                   = $record.group_name
            spu                          = $record.spu
            spu_index                    = $record.spu_index
            spu_name                     = $record.spu_name
            entry                        = $record.entry
            image_sig                    = $record.image_sig
            getllar_cmd_pc               = "0xa70"
            getllar_read_pc              = $getllarReadPc
            getllar_attempts             = $record.attempts
            getllar_updates              = $record.getllar_updates
            getllar_exact_reads          = $getllarExactReads
            getllar_read_minus_attempts  = Get-ProbeSignedDelta $getllarExactReads $record.attempts
            getllar_read_coverage        = Format-ProbePercent $getllarExactReads $record.attempts
            putllc_cmd_pc                = "0xad4"
            putllc_read_pc               = $putllcReadPc
            putllc_completed             = $record.completed
            putllc_updates               = $record.putllc_updates
            putllc_exact_reads           = $putllcExactReads
            putllc_read_minus_completed  = Get-ProbeSignedDelta $putllcExactReads $record.completed
            putllc_read_coverage         = Format-ProbePercent $putllcExactReads $record.completed
            update_linked                = $record.update_linked
            update_unlinked              = $record.update_unlinked
            in_hook_atomic_reads         = $record.atomic_reads
            exact_atomic_reads           = $exactReads
            exact_minus_in_hook_reads    = Get-ProbeSignedDelta $exactReads $record.atomic_reads
            unexpected                   = $record.unexpected
            dirty_multi                  = $record.dirty_multi
            lane                         = $record.lane
            last_cmd_pc                  = $record.last_cmd_pc
            last_atomic_pc               = $record.last_atomic_pc
            last_read_pc                 = $record.last_read_pc
            last_raw_cmd_pc              = $record.last_raw_cmd_pc
            last_raw_atomic_pc           = $record.last_raw_atomic_pc
            last_raw_read_pc             = $record.last_raw_read_pc
            last_retry_pc                = $record.last_retry_pc
            last_next_branch_pc          = $record.last_next_branch_pc
            cause                        = $record.cause
            status                       = $record.status
        }) | Out-Null
    }

    return @($rows | Sort-Object -Property exact_atomic_reads -Descending)
}

function Read-SpuDisasmHeader {
    param([string[]]$Lines)

    $header = @{}
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            break
        }

        if ($line -match '^([^=]+)=(.*)$') {
            $header[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    return $header
}

function Read-SpuDisasmInstructions {
    param([string[]]$Lines)

    $instructions = New-Object System.Collections.Generic.List[object]
    foreach ($line in $Lines) {
        if ($line -match '^\s*([0-9a-fA-F]{8}):\s+(?:[0-9a-fA-F]{2}\s+){4}(.*)$') {
            $pc = [Convert]::ToUInt64($Matches[1], 16)
            $instructions.Add([pscustomobject]@{
                pc      = $pc
                pc_hex  = Format-ProbeHexNumber $pc
                text    = $Matches[2].Trim()
            }) | Out-Null
        }
    }

    return @($instructions | Sort-Object -Property pc)
}

function Find-SpuDisasmInstruction {
    param(
        $Instructions,
        [UInt64]$AfterPc,
        [UInt64]$MaxDelta,
        [string]$Pattern
    )

    foreach ($instruction in @($Instructions | Where-Object { $_.pc -gt $AfterPc -and ($_.pc - $AfterPc) -le $MaxDelta } | Sort-Object -Property pc)) {
        if ($instruction.text -match $Pattern) {
            return $instruction
        }
    }

    return $null
}

function Get-ProbePcCounterPeak {
    param(
        $Records,
        [string]$Pc,
        [string]$Property,
        [string]$Title,
        [string]$Entry,
        [string]$ImageSig
    )

    $best = [UInt64]0
    foreach ($record in @($Records | ForEach-Object { $_ })) {
        if ($record.pc -ne $Pc) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($Title) -and $record.title -ne $Title) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($Entry) -and $record.entry -ne $Entry) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($ImageSig) -and $record.image_sig -ne $ImageSig) {
            continue
        }

        $value = [UInt64]0
        if ($null -ne $record.$Property) {
            $value = Convert-ProbeNumber $record.$Property
        }
        if ($value -gt $best) {
            $best = $value
        }
    }

    return $best
}

function Get-ReservationLoopRawLaneRows {
    param(
        [string]$RunDir,
        $CmdPcRecords,
        $WaitPcRecords
    )

    $spuImagesDir = Join-Path $RunDir "spu-images"
    if (-not (Test-Path -LiteralPath $spuImagesDir -PathType Container)) {
        return @()
    }

    $candidateRows = New-Object System.Collections.Generic.List[object]
    $instructionsByContext = @{}
    $cmdGetllarPeakByPc = @{}
    $cmdPutllcPeakByPc = @{}
    $waitAtomicPeakByPc = @{}

    foreach ($record in @($CmdPcRecords | ForEach-Object { $_ })) {
        $key = @($record.title, $record.entry, $record.image_sig, $record.pc) -join "|"
        $getllarValue = Convert-ProbeNumber $record.getllar_cmds
        $putllcValue = Convert-ProbeNumber $record.putllc_cmds
        if (-not $cmdGetllarPeakByPc.ContainsKey($key) -or $getllarValue -gt $cmdGetllarPeakByPc[$key]) {
            $cmdGetllarPeakByPc[$key] = $getllarValue
        }
        if (-not $cmdPutllcPeakByPc.ContainsKey($key) -or $putllcValue -gt $cmdPutllcPeakByPc[$key]) {
            $cmdPutllcPeakByPc[$key] = $putllcValue
        }
    }

    foreach ($record in @($WaitPcRecords | ForEach-Object { $_ })) {
        $key = @($record.title, $record.entry, $record.image_sig, $record.pc) -join "|"
        $atomicValue = Convert-ProbeNumber $record.atomic_reads
        if (-not $waitAtomicPeakByPc.ContainsKey($key) -or $atomicValue -gt $waitAtomicPeakByPc[$key]) {
            $waitAtomicPeakByPc[$key] = $atomicValue
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $spuImagesDir -Filter "*.disasm.txt" -File -ErrorAction SilentlyContinue)) {
        $content = @(Get-Content -LiteralPath $file.FullName)
        if ($content.Count -eq 0) {
            continue
        }

        $header = Read-SpuDisasmHeader -Lines $content
        $instructions = @(Read-SpuDisasmInstructions -Lines $content)
        if ($instructions.Count -eq 0) {
            continue
        }

        $title = if ($header.ContainsKey("title")) { $header["title"] } else { "" }
        $entry = if ($header.ContainsKey("entry")) { Format-ProbeHexToken $header["entry"] } else { "" }
        $imageSig = if ($header.ContainsKey("image_sig")) { Format-ProbeHexToken $header["image_sig"] } else { "" }
        $groupName = if ($header.ContainsKey("group")) { $header["group"] } else { "" }
        $spuName = if ($header.ContainsKey("spu")) { $header["spu"] } else { "" }
        $focusPc = if ($header.ContainsKey("focus_pc")) { Format-ProbeHexToken $header["focus_pc"] } else { "" }
        $contextKey = @($title, $entry, $imageSig, $groupName, $spuName) -join "|"
        if (-not $instructionsByContext.ContainsKey($contextKey)) {
            $instructionsByContext[$contextKey] = New-Object System.Collections.Generic.List[object]
        }
        foreach ($instruction in $instructions) {
            $instructionsByContext[$contextKey].Add($instruction) | Out-Null
        }

        foreach ($getllarCmd in @($instructions | Where-Object { $_.text -match 'wrch\s+MFC_Cmd' -and $_.text -match '#GETLLAR' })) {
            $getllarRead = Find-SpuDisasmInstruction -Instructions $instructions -AfterPc $getllarCmd.pc -MaxDelta 0x40 -Pattern 'rdch\s+\S+,MFC_RdAtomicStat'
            if ($null -eq $getllarRead) {
                continue
            }

            $putllcCmd = Find-SpuDisasmInstruction -Instructions $instructions -AfterPc $getllarRead.pc -MaxDelta 0x200 -Pattern 'wrch\s+MFC_Cmd,\S+\s+#PUTLLC'
            if ($null -eq $putllcCmd) {
                continue
            }

            $putllcRead = Find-SpuDisasmInstruction -Instructions $instructions -AfterPc $putllcCmd.pc -MaxDelta 0x40 -Pattern 'rdch\s+\S+,MFC_RdAtomicStat'
            if ($null -eq $putllcRead) {
                continue
            }

            $retryBranch = Find-SpuDisasmInstruction -Instructions $instructions -AfterPc $putllcRead.pc -MaxDelta 0x40 -Pattern '\bbrnz\b|\bbrz\b'
            $postGuard = $null
            if ($null -ne $retryBranch) {
                $postGuard = Find-SpuDisasmInstruction -Instructions $instructions -AfterPc $retryBranch.pc -MaxDelta 0xa0 -Pattern '\bbrz\b|\bbrnz\b|\bbr\b'
            }

            $candidateRows.Add([pscustomobject]@{
                key                 = @($title, $entry, $imageSig, $groupName, $spuName, $getllarCmd.pc_hex, $putllcCmd.pc_hex) -join "|"
                title               = $title
                entry               = $entry
                image_sig           = $imageSig
                group_name          = $groupName
                spu_name            = $spuName
                source_focus_pc     = $focusPc
                source_file         = $file.Name
                raw_getllar_cmd_pc  = $getllarCmd.pc_hex
                raw_getllar_read_pc = $getllarRead.pc_hex
                raw_putllc_cmd_pc   = $putllcCmd.pc_hex
                raw_putllc_read_pc  = $putllcRead.pc_hex
                raw_retry_branch_pc = if ($null -ne $retryBranch) { $retryBranch.pc_hex } else { "0x0" }
                raw_retry_branch    = if ($null -ne $retryBranch) { $retryBranch.text } else { "" }
                raw_next_branch_pc  = if ($null -ne $postGuard) { $postGuard.pc_hex } else { "0x0" }
                raw_next_branch     = if ($null -ne $postGuard) { $postGuard.text } else { "" }
            }) | Out-Null
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($candidateRows | Group-Object -Property key)) {
        $first = $group.Group[0]
        $focusPcs = @($group.Group | Select-Object -ExpandProperty source_focus_pc -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object { Convert-ProbeNumber $_ })
        $sourceFiles = @($group.Group | Select-Object -ExpandProperty source_file -Unique | Sort-Object)
        $contextKey = @($first.title, $first.entry, $first.image_sig, $first.group_name, $first.spu_name) -join "|"
        $retryBranchPc = $first.raw_retry_branch_pc
        $retryBranch = $first.raw_retry_branch
        $nextBranchPc = $first.raw_next_branch_pc
        $nextBranch = $first.raw_next_branch

        if ($instructionsByContext.ContainsKey($contextKey)) {
            $contextInstructions = @(
                $instructionsByContext[$contextKey] |
                    Group-Object -Property pc_hex |
                    ForEach-Object { $_.Group[0] } |
                    Sort-Object -Property pc
            )

            if ($retryBranchPc -eq "0x0") {
                $putllcReadPcValue = Convert-ProbeNumber $first.raw_putllc_read_pc
                $fallbackRetry = Find-SpuDisasmInstruction -Instructions $contextInstructions -AfterPc $putllcReadPcValue -MaxDelta 0x40 -Pattern '\bbrnz\b|\bbrz\b'
                if ($null -ne $fallbackRetry) {
                    $retryBranchPc = $fallbackRetry.pc_hex
                    $retryBranch = $fallbackRetry.text
                }
            }

            if ($nextBranchPc -eq "0x0" -and $retryBranchPc -ne "0x0") {
                $retryBranchPcValue = Convert-ProbeNumber $retryBranchPc
                $fallbackPostGuard = Find-SpuDisasmInstruction -Instructions $contextInstructions -AfterPc $retryBranchPcValue -MaxDelta 0xa0 -Pattern '\bbrz\b|\bbrnz\b|\bbr\b'
                if ($null -ne $fallbackPostGuard) {
                    $nextBranchPc = $fallbackPostGuard.pc_hex
                    $nextBranch = $fallbackPostGuard.text
                }
            }
        }

        $getllarCmdKey = @($first.title, $first.entry, $first.image_sig, $first.raw_getllar_cmd_pc) -join "|"
        $putllcCmdKey = @($first.title, $first.entry, $first.image_sig, $first.raw_putllc_cmd_pc) -join "|"
        $getllarReadKey = @($first.title, $first.entry, $first.image_sig, $first.raw_getllar_read_pc) -join "|"
        $putllcReadKey = @($first.title, $first.entry, $first.image_sig, $first.raw_putllc_read_pc) -join "|"
        $getllarCmdHits = if ($cmdGetllarPeakByPc.ContainsKey($getllarCmdKey)) { [UInt64]$cmdGetllarPeakByPc[$getllarCmdKey] } else { [UInt64]0 }
        $putllcCmdHits = if ($cmdPutllcPeakByPc.ContainsKey($putllcCmdKey)) { [UInt64]$cmdPutllcPeakByPc[$putllcCmdKey] } else { [UInt64]0 }
        $getllarReadHits = if ($waitAtomicPeakByPc.ContainsKey($getllarReadKey)) { [UInt64]$waitAtomicPeakByPc[$getllarReadKey] } else { [UInt64]0 }
        $putllcReadHits = if ($waitAtomicPeakByPc.ContainsKey($putllcReadKey)) { [UInt64]$waitAtomicPeakByPc[$putllcReadKey] } else { [UInt64]0 }

        $rows.Add([pscustomobject]@{
            title                = $first.title
            entry                = $first.entry
            image_sig            = $first.image_sig
            group_name           = $first.group_name
            spu_name             = $first.spu_name
            raw_getllar_cmd_pc   = $first.raw_getllar_cmd_pc
            raw_getllar_read_pc  = $first.raw_getllar_read_pc
            raw_putllc_cmd_pc    = $first.raw_putllc_cmd_pc
            raw_putllc_read_pc   = $first.raw_putllc_read_pc
            raw_retry_branch_pc  = $retryBranchPc
            raw_retry_branch     = $retryBranch
            raw_next_branch_pc   = $nextBranchPc
            raw_next_branch      = $nextBranch
            getllar_cmd_hits     = $getllarCmdHits
            putllc_cmd_hits      = $putllcCmdHits
            getllar_read_hits    = $getllarReadHits
            putllc_read_hits     = $putllcReadHits
            source_focus_pcs     = $focusPcs -join ";"
            source_file_count    = $sourceFiles.Count
            source_files         = $sourceFiles -join ";"
            classification       = "raw-spu-reservation-lane"
            cause                = "0x0"
            status               = "0x0"
        }) | Out-Null
    }

    return @($rows | Sort-Object -Property putllc_cmd_hits,getllar_cmd_hits,putllc_read_hits,getllar_read_hits -Descending)
}

function Get-Putllc16BreakCauseReason {
    param([UInt64]$Cause)

    switch ($Cause) {
        16 { return "LQD/STQD LS state mismatch after PC-relative access" }
        23 { return "LQX/STQX store after prior invalid LS access" }
        35 { return "LQR/STQR store after prior invalid LS access" }
        37 { return "LQA/STQA store after prior invalid LS access" }
        default { return "" }
    }
}

function Get-ProbeFields {
    param([string]$Line)

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_()\/]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    return $fields
}

function Get-ProbeHeightFromExtent {
    param(
        [AllowNull()][string]$Extent,
        [UInt64]$Fallback = 1
    )

    if (-not [string]::IsNullOrWhiteSpace($Extent) -and $Extent -match '^\d+x(?<h>\d+)$') {
        return [UInt64]$Matches['h']
    }

    return [UInt64]([Math]::Max(1, [double]$Fallback))
}

function New-ProbeRsxResourceRecord {
    param(
        [string]$Kind,
        [string]$Role,
        [UInt64]$Base,
        [UInt64]$Pitch,
        [UInt64]$Height,
        [UInt64]$Count,
        [string]$Format,
        [string]$Key,
        [string]$Description
    )

    if ($Base -eq 0 -or $Pitch -eq 0 -or $Height -eq 0) {
        return $null
    }

    $bytes = $Pitch * $Height
    if ($bytes -eq 0) {
        return $null
    }

    return [pscustomobject]@{
        kind        = $Kind
        role        = $Role
        base        = Format-ProbeHexNumber $Base
        end         = Format-ProbeHexNumber ($Base + $bytes)
        base_value  = $Base
        end_value   = $Base + $bytes
        bytes       = $bytes
        pitch       = $Pitch
        height      = $Height
        count       = $Count
        format      = $Format
        key         = $Key
        description = $Description
    }
}

function Get-ProbeOffloadFit {
    param([object]$Record)

    if ($Record.output_mismatches -gt 0) {
        return "reject-mismatch"
    }

    $rsxBytes = [UInt64]($Record.rsx_get_bytes + $Record.rsx_put_bytes)
    if ($rsxBytes -gt 0 -and $Record.total_bytes -ge 1048576) {
        return "gpu-resident-strong"
    }

    if ($rsxBytes -gt 0) {
        return "gpu-resident-check"
    }

    if ($Record.repeat_hits -gt 0 -and $Record.put_payload_bytes -gt 0) {
        return "cpu-hle-or-replay"
    }

    if ($Record.total_bytes -ge 1048576) {
        return "spu-kernel-hle"
    }

    if ($Record.max_dma_size -ge 65536) {
        return "batch-first"
    }

    return "too-small"
}

function Get-ProbeDispatchRisk {
    param([object]$Record)

    if ($Record.max_dma_size -eq 0) {
        return "unknown"
    }

    if ($Record.cmd_count -gt 128 -and $Record.max_dma_size -lt 65536) {
        return "tiny-dispatch-trap"
    }

    if ($Record.cmd_count -gt 32 -and $Record.max_dma_size -lt 262144) {
        return "needs-batching"
    }

    if ($Record.total_bytes -ge 1048576 -or $Record.max_dma_size -ge 262144) {
        return "batchable"
    }

    return "low"
}

function Get-ProbeReading {
    param([object]$Record)

    switch ($Record.offload_fit) {
        "reject-mismatch" { return "Verification saw mismatched outputs; do not fast-path this signature." }
        "gpu-resident-strong" { return "Nonzero RSX-local traffic plus large DMA makes this a real Vulkan/RSX superpath candidate." }
        "gpu-resident-check" { return "RSX-local traffic exists, but size/repeat evidence must survive field, battle, and menu." }
        "cpu-hle-or-replay" { return "Repeat-clean payloads point at a verified CPU/HLE or replay cache before Vulkan compute." }
        "spu-kernel-hle" { return "Large SPU traffic with zero RSX-local bytes points first at SPU kernel HLE, NEON/dotprod, reduced-loop, or scheduler/copy work." }
        "batch-first" { return "Potentially useful only if batched; one dispatch per DMA command would be too expensive." }
        default { return "Too small or insufficiently stable for a GPU offload experiment." }
    }
}

function Get-KernelCapsuleReading {
    param([string]$Class)

    switch ($Class) {
        "gpu-batch-candidate" { return "Best next GPU-shadow target: bulk DMA and low sync risk, but still needs CPU output hashing before fast mode." }
        "cpu-simd-first" { return "Large SPU-side work with weak RSX evidence; try CPU SIMD/codegen/HLE before a Vulkan dispatch path." }
        "rsx-consumed" { return "Touches RSX-local memory; correlate with RSX resource overlap before promoting to an RSX/Vulkan-local superpath." }
        "reservation-risk" { return "Atomic/reservation signals are present; correctness risk is high, so keep this in observe/verify mode." }
        "tiny-dispatch-trap" { return "Many small commands would lose to GPU launch overhead unless a larger batch capsule is found." }
        "sync-only" { return "Mostly tag/atomic waiting; scheduler/reduced-loop work beats GPU compute here." }
        default { return "Too small or ambiguous; keep logging and look for a larger stable capsule." }
    }
}

function Format-MfcShapeFlags {
    param([UInt64]$Flags)

    $names = New-Object System.Collections.Generic.List[string]
    $map = @(
        @{ bit = 0; name = "list" },
        @{ bit = 1; name = "get" },
        @{ bit = 2; name = "put" },
        @{ bit = 3; name = "atomic" },
        @{ bit = 4; name = "barrier" },
        @{ bit = 5; name = "fence" },
        @{ bit = 6; name = "rsx-local" }
    )

    foreach ($entry in $map) {
        if (($Flags -band ([UInt64]1 -shl $entry.bit)) -ne 0) {
            $names.Add($entry.name) | Out-Null
        }
    }

    if ($names.Count -eq 0) {
        return "none"
    }

    return ($names -join ",")
}

function Read-ProbeRecord {
    param([string]$Line)

    $probeKind = ""
    if ($Line -match 'Eternal Sonata GPU candidate probe:') {
        $probeKind = "windows-gpu"
    } elseif ($Line -match 'Eternal Sonata DMA candidate probe:') {
        $probeKind = "thor-dma"
    } else {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    if (-not $fields.ContainsKey('total_bytes')) {
        return $null
    }

    $record = [pscustomobject]@{
        probe_kind      = $probeKind
        mode            = $fields['mode']
        title           = $fields['title']
        ppu             = Format-ProbeHex $fields['ppu']
        ppu_name        = $fields['ppu_name']
        group           = Format-ProbeHex $fields['group']
        group_name      = $fields['group_name']
        spu             = Format-ProbeHex $fields['spu']
        spu_index       = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name        = $fields['spu_name']
        entry           = Format-ProbeHex $fields['entry']
        image_sig       = Format-ProbeHex $fields['image_sig']
        pattern_sig     = Format-ProbeHex $fields['pattern_sig']
        duration_us     = Convert-ProbeNumber $fields['duration_us']
        total_bytes     = Convert-ProbeNumber $fields['total_bytes']
        get_bytes       = Convert-ProbeNumber $fields['get_bytes']
        put_bytes       = Convert-ProbeNumber $fields['put_bytes']
        list_get_bytes  = Convert-ProbeNumber $fields['list_get_bytes']
        list_put_bytes  = Convert-ProbeNumber $fields['list_put_bytes']
        rsx_get_bytes   = Convert-ProbeNumber $fields['rsx_get_bytes']
        rsx_put_bytes   = Convert-ProbeNumber $fields['rsx_put_bytes']
        cmd_count       = Convert-ProbeNumber $fields['cmd_count']
        list_cmd_count  = Convert-ProbeNumber $fields['list_cmd_count']
        dma_mode        = $fields['dma_mode']
        get_payload_hash = Format-ProbeHex $fields['get_payload_hash']
        put_payload_hash = Format-ProbeHex $fields['put_payload_hash']
        get_payload_bytes = Convert-ProbeNumber $fields['get_payload_bytes']
        put_payload_bytes = Convert-ProbeNumber $fields['put_payload_bytes']
        sampled_get_payload_bytes = Convert-ProbeNumber $fields['sampled_get_payload_bytes']
        sampled_put_payload_bytes = Convert-ProbeNumber $fields['sampled_put_payload_bytes']
        ls_start_hash   = Format-ProbeHex $fields['ls_start_hash']
        ls_end_hash     = Format-ProbeHex $fields['ls_end_hash']
        repeat_hits     = Convert-ProbeNumber $fields['repeat_hits']
        output_mismatches = Convert-ProbeNumber $fields['output_mismatches']
        max_dma_size    = [UInt64](Convert-ProbeNumber $fields['max_dma_size'])
        max_dma_pc      = Format-ProbeHex $fields['max_dma_pc']
        max_dma_ea      = Format-ProbeHex $fields['max_dma_ea']
        block_hash      = Format-ProbeHex $fields['block_hash']
        max_dma_block_hash = Format-ProbeHex $fields['max_dma_block_hash']
        cause           = Format-ProbeHex $fields['cause']
        status          = Format-ProbeHex $fields['status']
    }

    $record | Add-Member -NotePropertyName offload_fit -NotePropertyValue (Get-ProbeOffloadFit $record)
    $record | Add-Member -NotePropertyName dispatch_risk -NotePropertyValue (Get-ProbeDispatchRisk $record)
    $record | Add-Member -NotePropertyName reading -NotePropertyValue (Get-ProbeReading $record)
    return $record
}

function Read-KernelCapsuleRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata kernel capsule probe:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('records')) {
        return $null
    }

    return [pscustomobject]@{
        mode                 = $fields['mode']
        capsule_mode         = $fields['capsule_mode']
        title                = $fields['title']
        ppu                  = Format-ProbeHex $fields['ppu']
        ppu_name             = $fields['ppu_name']
        group                = Format-ProbeHex $fields['group']
        group_name           = $fields['group_name']
        spu                  = Format-ProbeHex $fields['spu']
        spu_index            = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name             = $fields['spu_name']
        entry                = Format-ProbeHex $fields['entry']
        image_sig            = Format-ProbeHex $fields['image_sig']
        pattern_sig          = Format-ProbeHex $fields['pattern_sig']
        duration_us          = Convert-ProbeNumber $fields['duration_us']
        class                = $fields['class']
        records              = Convert-ProbeNumber $fields['records']
        total_bytes          = Convert-ProbeNumber $fields['total_bytes']
        get_bytes            = Convert-ProbeNumber $fields['get_bytes']
        put_bytes            = Convert-ProbeNumber $fields['put_bytes']
        list_bytes           = Convert-ProbeNumber $fields['list_bytes']
        rsx_bytes            = Convert-ProbeNumber $fields['rsx_bytes']
        cmd_count            = Convert-ProbeNumber $fields['cmd_count']
        list_cmd_count       = Convert-ProbeNumber $fields['list_cmd_count']
        dynamic_hits         = Convert-ProbeNumber $fields['dynamic_hits']
        dynamic_bytes        = Convert-ProbeNumber $fields['dynamic_bytes']
        list_calls           = Convert-ProbeNumber $fields['list_calls']
        list_desc_bytes      = Convert-ProbeNumber $fields['list_desc_bytes']
        wait_reads           = Convert-ProbeNumber $fields['wait_reads']
        tagstat_reads        = Convert-ProbeNumber $fields['tagstat_reads']
        atomic_reads         = Convert-ProbeNumber $fields['atomic_reads']
        putllc16_hits        = Convert-ProbeNumber $fields['putllc16_hits']
        max_dma_size         = Convert-ProbeNumber $fields['max_dma_size']
        max_dma_pc           = Format-ProbeHex $fields['max_dma_pc']
        max_dma_ea           = Format-ProbeHex $fields['max_dma_ea']
        last_pc              = Format-ProbeHex $fields['last_pc']
        last_cmd             = Format-ProbeHex $fields['last_cmd']
        reservation_risk     = Convert-ProbeNumber $fields['reservation_risk']
        tiny_dispatch_trap   = Convert-ProbeNumber $fields['tiny_dispatch_trap']
        rsx_consumed         = Convert-ProbeNumber $fields['rsx_consumed']
        gpu_batch_candidate  = Convert-ProbeNumber $fields['gpu_batch_candidate']
        cpu_simd_first       = Convert-ProbeNumber $fields['cpu_simd_first']
        sync_only            = Convert-ProbeNumber $fields['sync_only']
        cause                = Format-ProbeHex $fields['cause']
        status               = Format-ProbeHex $fields['status']
    }
}

function Read-MfcShapeRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC shape probe:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    if (-not $fields.ContainsKey('count')) {
        return $null
    }

    return [pscustomobject]@{
        mode       = $fields['mode']
        title      = $fields['title']
        group      = Format-ProbeHex $fields['group']
        group_name = $fields['group_name']
        spu        = Format-ProbeHex $fields['spu']
        spu_index  = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name   = $fields['spu_name']
        entry      = Format-ProbeHex $fields['entry']
        image_sig  = Format-ProbeHex $fields['image_sig']
        pc         = Format-ProbeHex $fields['pc']
        block_hash = Format-ProbeHex $fields['block_hash']
        cmd        = Format-ProbeHex $fields['cmd']
        tag        = Convert-ProbeNumber $fields['tag']
        size       = Convert-ProbeNumber $fields['size']
        lsa        = Format-ProbeHex $fields['lsa']
        flags      = Convert-ProbeNumber $fields['flags']
        count      = Convert-ProbeNumber $fields['count']
        bytes      = Convert-ProbeNumber $fields['bytes']
        eal_first  = Format-ProbeHex $fields['eal_first']
        eal_last   = Format-ProbeHex $fields['eal_last']
        eal_min    = Format-ProbeHex $fields['eal_min']
        eal_max    = Format-ProbeHex $fields['eal_max']
        overflow   = Convert-ProbeNumber $fields['overflow']
        cause      = Format-ProbeHex $fields['cause']
        status     = Format-ProbeHex $fields['status']
    }
}

function Read-MfcLadderRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC ladder probe:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    if (-not $fields.ContainsKey('eligible')) {
        return $null
    }

    return [pscustomobject]@{
        mode        = $fields['mode']
        ladder_mode = $fields['ladder_mode']
        title       = $fields['title']
        group       = Format-ProbeHex $fields['group']
        group_name  = $fields['group_name']
        spu         = Format-ProbeHex $fields['spu']
        spu_index   = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name    = $fields['spu_name']
        entry       = Format-ProbeHex $fields['entry']
        image_sig   = Format-ProbeHex $fields['image_sig']
        pc          = Format-ProbeHex $fields['pc']
        last_lsa    = Format-ProbeHex $fields['last_lsa']
        eligible    = Convert-ProbeNumber $fields['eligible']
        verify_hits = Convert-ProbeNumber $fields['verify_hits']
        fast_hits   = Convert-ProbeNumber $fields['fast_hits']
        blocked     = Convert-ProbeNumber $fields['blocked']
        mismatches  = Convert-ProbeNumber $fields['mismatches']
        bytes       = Convert-ProbeNumber $fields['bytes']
        check_us    = Convert-ProbeNumber $fields['check_us']
        transfer_us = Convert-ProbeNumber $fields['transfer_us']
        total_us    = Convert-ProbeNumber $fields['total_us']
        max_check_us = Convert-ProbeNumber $fields['max_check_us']
        max_transfer_us = Convert-ProbeNumber $fields['max_transfer_us']
        max_total_us = Convert-ProbeNumber $fields['max_total_us']
        eal_first   = Format-ProbeHex $fields['eal_first']
        eal_last    = Format-ProbeHex $fields['eal_last']
        eal_min     = Format-ProbeHex $fields['eal_min']
        eal_max     = Format-ProbeHex $fields['eal_max']
        cause       = Format-ProbeHex $fields['cause']
        status      = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHleVerifyRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode             = $fields['mode']
        hle_mode         = $fields['hle_mode']
        title            = $fields['title']
        ppu              = Format-ProbeHex $fields['ppu']
        ppu_name         = $fields['ppu_name']
        group            = Format-ProbeHex $fields['group']
        group_name       = $fields['group_name']
        spu              = Format-ProbeHex $fields['spu']
        spu_index        = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name         = $fields['spu_name']
        entry            = Format-ProbeHex $fields['entry']
        image_sig        = Format-ProbeHex $fields['image_sig']
        hits             = Convert-ProbeNumber $fields['hits']
        runtime_hits     = Convert-ProbeNumber $fields['runtime_hits']
        llvm_hits        = Convert-ProbeNumber $fields['llvm_hits']
        get_hits         = Convert-ProbeNumber $fields['get_hits']
        put_hits         = Convert-ProbeNumber $fields['put_hits']
        pc25_hits        = Convert-ProbeNumber $fields['pc25_hits']
        pc451c_hits      = Convert-ProbeNumber $fields['pc451c_hits']
        other_pc_hits    = Convert-ProbeNumber $fields['other_pc_hits']
        bytes            = Convert-ProbeNumber $fields['bytes']
        runtime_bytes    = Convert-ProbeNumber $fields['runtime_bytes']
        llvm_bytes       = Convert-ProbeNumber $fields['llvm_bytes']
        last_path        = Convert-ProbeNumber $fields['last_path']
        last_pc          = Format-ProbeHex $fields['last_pc']
        last_cmd         = Format-ProbeHex $fields['last_cmd']
        last_tag         = Convert-ProbeNumber $fields['last_tag']
        last_size        = Convert-ProbeNumber $fields['last_size']
        last_lsa         = Format-ProbeHex $fields['last_lsa']
        last_eal         = Format-ProbeHex $fields['last_eal']
        cause            = Format-ProbeHex $fields['cause']
        status           = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHleShadowRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE shadow verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode               = $fields['mode']
        hle_mode           = $fields['hle_mode']
        title              = $fields['title']
        ppu                = Format-ProbeHex $fields['ppu']
        ppu_name           = $fields['ppu_name']
        group              = Format-ProbeHex $fields['group']
        group_name         = $fields['group_name']
        spu                = Format-ProbeHex $fields['spu']
        spu_index          = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name           = $fields['spu_name']
        entry              = Format-ProbeHex $fields['entry']
        image_sig          = Format-ProbeHex $fields['image_sig']
        hits               = Convert-ProbeNumber $fields['hits']
        bytes              = Convert-ProbeNumber $fields['bytes']
        src_repeats        = Convert-ProbeNumber $fields['src_repeats']
        dst_pre_repeats    = Convert-ProbeNumber $fields['dst_pre_repeats']
        dst_post_repeats   = Convert-ProbeNumber $fields['dst_post_repeats']
        dst_changed        = Convert-ProbeNumber $fields['dst_changed']
        dst_unchanged      = Convert-ProbeNumber $fields['dst_unchanged']
        output_match       = Convert-ProbeNumber $fields['output_match']
        output_mismatch    = Convert-ProbeNumber $fields['output_mismatch']
        skip_hits          = if ($fields.ContainsKey('skip_hits')) { Convert-ProbeNumber $fields['skip_hits'] } else { 0 }
        skip_bytes         = if ($fields.ContainsKey('skip_bytes')) { Convert-ProbeNumber $fields['skip_bytes'] } else { 0 }
        skip_misses        = if ($fields.ContainsKey('skip_misses')) { Convert-ProbeNumber $fields['skip_misses'] } else { 0 }
        skip_miss_bytes    = if ($fields.ContainsKey('skip_miss_bytes')) { Convert-ProbeNumber $fields['skip_miss_bytes'] } else { 0 }
        last_pc            = Format-ProbeHex $fields['last_pc']
        last_cmd           = Format-ProbeHex $fields['last_cmd']
        last_tag           = Convert-ProbeNumber $fields['last_tag']
        last_size          = Convert-ProbeNumber $fields['last_size']
        last_lsa           = Format-ProbeHex $fields['last_lsa']
        last_eal           = Format-ProbeHex $fields['last_eal']
        last_src_hash      = Format-ProbeHex $fields['last_src_hash']
        last_dst_pre_hash  = Format-ProbeHex $fields['last_dst_pre_hash']
        last_dst_post_hash = Format-ProbeHex $fields['last_dst_post_hash']
        cause              = Format-ProbeHex $fields['cause']
        status             = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHle451cListSeedRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE 451c list seed verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode          = $fields['mode']
        hle_mode      = $fields['hle_mode']
        title         = $fields['title']
        ppu           = Format-ProbeHex $fields['ppu']
        ppu_name      = $fields['ppu_name']
        group         = Format-ProbeHex $fields['group']
        group_name    = $fields['group_name']
        spu           = Format-ProbeHex $fields['spu']
        spu_index     = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name      = $fields['spu_name']
        entry         = Format-ProbeHex $fields['entry']
        image_sig     = Format-ProbeHex $fields['image_sig']
        hits          = Convert-ProbeNumber $fields['hits']
        success       = Convert-ProbeNumber $fields['success']
        fail          = Convert-ProbeNumber $fields['fail']
        seed1_hits    = Convert-ProbeNumber $fields['seed1_hits']
        seed2_hits    = Convert-ProbeNumber $fields['seed2_hits']
        desc_bytes    = Convert-ProbeNumber $fields['desc_bytes']
        total_us      = Convert-ProbeNumber $fields['total_us']
        max_total_us  = Convert-ProbeNumber $fields['max_total_us']
        last_seed     = Convert-ProbeNumber $fields['last_seed']
        last_pc       = Format-ProbeHex $fields['last_pc']
        last_cmd      = Format-ProbeHex $fields['last_cmd']
        last_tag      = Convert-ProbeNumber $fields['last_tag']
        last_size     = Convert-ProbeNumber $fields['last_size']
        last_lsa      = Format-ProbeHex $fields['last_lsa']
        last_eal      = Format-ProbeHex $fields['last_eal']
        cause         = Format-ProbeHex $fields['cause']
        status        = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHle25ccFamilyRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE 25cc family verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode                 = $fields['mode']
        hle_mode             = $fields['hle_mode']
        title                = $fields['title']
        ppu                  = Format-ProbeHex $fields['ppu']
        ppu_name             = $fields['ppu_name']
        group                = Format-ProbeHex $fields['group']
        group_name           = $fields['group_name']
        spu                  = Format-ProbeHex $fields['spu']
        spu_index            = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name             = $fields['spu_name']
        entry                = Format-ProbeHex $fields['entry']
        image_sig            = Format-ProbeHex $fields['image_sig']
        hits                 = Convert-ProbeNumber $fields['hits']
        success              = Convert-ProbeNumber $fields['success']
        fail                 = Convert-ProbeNumber $fields['fail']
        get_hits             = Convert-ProbeNumber $fields['get_hits']
        put_hits             = Convert-ProbeNumber $fields['put_hits']
        bytes                = Convert-ProbeNumber $fields['bytes']
        total_us             = Convert-ProbeNumber $fields['total_us']
        max_total_us         = Convert-ProbeNumber $fields['max_total_us']
        ea9e4000_hits        = Convert-ProbeNumber $fields['ea9e4000_hits']
        ea4f0b80_hits        = Convert-ProbeNumber $fields['ea4f0b80_hits']
        exact_a1c000_hits    = Convert-ProbeNumber $fields['exact_a1c000_hits']
        other_ea_hits        = Convert-ProbeNumber $fields['other_ea_hits']
        last_family          = Convert-ProbeNumber $fields['last_family']
        last_pc              = Format-ProbeHex $fields['last_pc']
        last_cmd             = Format-ProbeHex $fields['last_cmd']
        last_tag             = Convert-ProbeNumber $fields['last_tag']
        last_size            = Convert-ProbeNumber $fields['last_size']
        last_lsa             = Format-ProbeHex $fields['last_lsa']
        last_eal             = Format-ProbeHex $fields['last_eal']
        cause                = Format-ProbeHex $fields['cause']
        status               = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHle25ccShadowRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE 25cc shadow verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode                 = $fields['mode']
        hle_mode             = $fields['hle_mode']
        title                = $fields['title']
        ppu                  = Format-ProbeHex $fields['ppu']
        ppu_name             = $fields['ppu_name']
        group                = Format-ProbeHex $fields['group']
        group_name           = $fields['group_name']
        spu                  = Format-ProbeHex $fields['spu']
        spu_index            = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name             = $fields['spu_name']
        entry                = Format-ProbeHex $fields['entry']
        image_sig            = Format-ProbeHex $fields['image_sig']
        hits                 = Convert-ProbeNumber $fields['hits']
        get_hits             = Convert-ProbeNumber $fields['get_hits']
        put_hits             = Convert-ProbeNumber $fields['put_hits']
        bytes                = Convert-ProbeNumber $fields['bytes']
        ea9e4000_hits        = Convert-ProbeNumber $fields['ea9e4000_hits']
        ea4f0b80_hits        = Convert-ProbeNumber $fields['ea4f0b80_hits']
        exact_a1c000_hits    = Convert-ProbeNumber $fields['exact_a1c000_hits']
        other_ea_hits        = Convert-ProbeNumber $fields['other_ea_hits']
        src_repeats          = Convert-ProbeNumber $fields['src_repeats']
        dst_pre_repeats      = Convert-ProbeNumber $fields['dst_pre_repeats']
        dst_post_repeats     = Convert-ProbeNumber $fields['dst_post_repeats']
        dst_changed          = Convert-ProbeNumber $fields['dst_changed']
        dst_unchanged        = Convert-ProbeNumber $fields['dst_unchanged']
        output_match         = Convert-ProbeNumber $fields['output_match']
        output_mismatch      = Convert-ProbeNumber $fields['output_mismatch']
        last_family          = Convert-ProbeNumber $fields['last_family']
        last_pc              = Format-ProbeHex $fields['last_pc']
        last_cmd             = Format-ProbeHex $fields['last_cmd']
        last_tag             = Convert-ProbeNumber $fields['last_tag']
        last_size            = Convert-ProbeNumber $fields['last_size']
        last_lsa             = Format-ProbeHex $fields['last_lsa']
        last_eal             = Format-ProbeHex $fields['last_eal']
        last_src_hash        = Format-ProbeHex $fields['last_src_hash']
        last_dst_pre_hash    = Format-ProbeHex $fields['last_dst_pre_hash']
        last_dst_post_hash   = Format-ProbeHex $fields['last_dst_post_hash']
        cause                = Format-ProbeHex $fields['cause']
        status               = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHle25ccBodyRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE 25cc body verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode                 = $fields['mode']
        hle_mode             = $fields['hle_mode']
        title                = $fields['title']
        ppu                  = Format-ProbeHex $fields['ppu']
        ppu_name             = $fields['ppu_name']
        group                = Format-ProbeHex $fields['group']
        group_name           = $fields['group_name']
        spu                  = Format-ProbeHex $fields['spu']
        spu_index            = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name             = $fields['spu_name']
        entry                = Format-ProbeHex $fields['entry']
        image_sig            = Format-ProbeHex $fields['image_sig']
        hits                 = Convert-ProbeNumber $fields['hits']
        get_hits             = Convert-ProbeNumber $fields['get_hits']
        put_rejects          = Convert-ProbeNumber $fields['put_rejects']
        bytes                = Convert-ProbeNumber $fields['bytes']
        total_us             = Convert-ProbeNumber $fields['total_us']
        max_total_us         = Convert-ProbeNumber $fields['max_total_us']
        ea9e4000_hits        = Convert-ProbeNumber $fields['ea9e4000_hits']
        ea4f0b80_hits        = Convert-ProbeNumber $fields['ea4f0b80_hits']
        exact_a1c000_hits    = Convert-ProbeNumber $fields['exact_a1c000_hits']
        other_ea_hits        = Convert-ProbeNumber $fields['other_ea_hits']
        last_family          = Convert-ProbeNumber $fields['last_family']
        last_pc              = Format-ProbeHex $fields['last_pc']
        last_cmd             = Format-ProbeHex $fields['last_cmd']
        last_tag             = Convert-ProbeNumber $fields['last_tag']
        last_size            = Convert-ProbeNumber $fields['last_size']
        last_lsa             = Format-ProbeHex $fields['last_lsa']
        last_eal             = Format-ProbeHex $fields['last_eal']
        cause                = Format-ProbeHex $fields['cause']
        status               = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHle451cListFamilyRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE 451c list family verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode               = $fields['mode']
        hle_mode           = $fields['hle_mode']
        title              = $fields['title']
        ppu                = Format-ProbeHex $fields['ppu']
        ppu_name           = $fields['ppu_name']
        group              = Format-ProbeHex $fields['group']
        group_name         = $fields['group_name']
        spu                = Format-ProbeHex $fields['spu']
        spu_index          = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name           = $fields['spu_name']
        entry              = Format-ProbeHex $fields['entry']
        image_sig          = Format-ProbeHex $fields['image_sig']
        hits               = Convert-ProbeNumber $fields['hits']
        success            = Convert-ProbeNumber $fields['success']
        fail               = Convert-ProbeNumber $fields['fail']
        tag1_size8_hits    = Convert-ProbeNumber $fields['tag1_size8_hits']
        tag0_size8_hits    = Convert-ProbeNumber $fields['tag0_size8_hits']
        tag0_size16_hits   = Convert-ProbeNumber $fields['tag0_size16_hits']
        tag1_size16_hits   = Convert-ProbeNumber $fields['tag1_size16_hits']
        tag1_size24_hits   = Convert-ProbeNumber $fields['tag1_size24_hits']
        tag0_size24_hits   = Convert-ProbeNumber $fields['tag0_size24_hits']
        desc_bytes         = Convert-ProbeNumber $fields['desc_bytes']
        total_us           = Convert-ProbeNumber $fields['total_us']
        max_total_us       = Convert-ProbeNumber $fields['max_total_us']
        last_family        = Convert-ProbeNumber $fields['last_family']
        last_pc            = Format-ProbeHex $fields['last_pc']
        last_cmd           = Format-ProbeHex $fields['last_cmd']
        last_tag           = Convert-ProbeNumber $fields['last_tag']
        last_size          = Convert-ProbeNumber $fields['last_size']
        last_lsa           = Format-ProbeHex $fields['last_lsa']
        last_eal           = Format-ProbeHex $fields['last_eal']
        cause              = Format-ProbeHex $fields['cause']
        status             = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHle451cDescBatchRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE 451c descriptor batch verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('calls')) {
        return $null
    }

    return [pscustomobject]@{
        mode            = $fields['mode']
        hle_mode        = $fields['hle_mode']
        title           = $fields['title']
        ppu             = Format-ProbeHex $fields['ppu']
        ppu_name        = $fields['ppu_name']
        group           = Format-ProbeHex $fields['group']
        group_name      = $fields['group_name']
        spu             = Format-ProbeHex $fields['spu']
        spu_index       = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name        = $fields['spu_name']
        entry           = Format-ProbeHex $fields['entry']
        image_sig       = Format-ProbeHex $fields['image_sig']
        calls           = Convert-ProbeNumber $fields['calls']
        desc_bytes      = Convert-ProbeNumber $fields['desc_bytes']
        fetch_groups    = Convert-ProbeNumber $fields['fetch_groups']
        fast_groups     = Convert-ProbeNumber $fields['fast_groups']
        fast_desc       = Convert-ProbeNumber $fields['fast_desc']
        slow_desc       = Convert-ProbeNumber $fields['slow_desc']
        nonzero_desc    = Convert-ProbeNumber $fields['nonzero_desc']
        zero_desc       = Convert-ProbeNumber $fields['zero_desc']
        stall_desc      = Convert-ProbeNumber $fields['stall_desc']
        inline_get_desc = Convert-ProbeNumber $fields['inline_get_desc']
        inline_put_desc = Convert-ProbeNumber $fields['inline_put_desc']
        dma_desc        = Convert-ProbeNumber $fields['dma_desc']
        shadow_groups   = Convert-ProbeNumber $fields['shadow_groups']
        shadow_single_groups = Convert-ProbeNumber $fields['shadow_single_groups']
        shadow_multi_groups = Convert-ProbeNumber $fields['shadow_multi_groups']
        shadow_full_groups = Convert-ProbeNumber $fields['shadow_full_groups']
        shadow_partial_groups = Convert-ProbeNumber $fields['shadow_partial_groups']
        shadow_desc     = Convert-ProbeNumber $fields['shadow_desc']
        shadow_bytes    = Convert-ProbeNumber $fields['shadow_bytes']
        shadow_uniform_size_groups = Convert-ProbeNumber $fields['shadow_uniform_size_groups']
        shadow_mixed_size_groups = Convert-ProbeNumber $fields['shadow_mixed_size_groups']
        shadow_zero_rejects = Convert-ProbeNumber $fields['shadow_zero_rejects']
        shadow_stall_rejects = Convert-ProbeNumber $fields['shadow_stall_rejects']
        shadow_raw_rejects = Convert-ProbeNumber $fields['shadow_raw_rejects']
        shadow_max_desc = Convert-ProbeNumber $fields['shadow_max_desc']
        shadow_max_bytes = Convert-ProbeNumber $fields['shadow_max_bytes']
        shadow_last_desc = Convert-ProbeNumber $fields['shadow_last_desc']
        shadow_last_bytes = Convert-ProbeNumber $fields['shadow_last_bytes']
        shadow_last_first_ea = Format-ProbeHex $fields['shadow_last_first_ea']
        shadow_last_last_ea = Format-ProbeHex $fields['shadow_last_last_ea']
        preserve_groups = Convert-ProbeNumber $fields['preserve_groups']
        preserve_single_groups = Convert-ProbeNumber $fields['preserve_single_groups']
        preserve_multi_groups = Convert-ProbeNumber $fields['preserve_multi_groups']
        preserve_full_groups = Convert-ProbeNumber $fields['preserve_full_groups']
        preserve_partial_groups = Convert-ProbeNumber $fields['preserve_partial_groups']
        preserve_desc = Convert-ProbeNumber $fields['preserve_desc']
        preserve_bytes = Convert-ProbeNumber $fields['preserve_bytes']
        preserve_zero_stops = Convert-ProbeNumber $fields['preserve_zero_stops']
        preserve_stall_stops = Convert-ProbeNumber $fields['preserve_stall_stops']
        preserve_raw_stops = Convert-ProbeNumber $fields['preserve_raw_stops']
        preserve_max_desc = Convert-ProbeNumber $fields['preserve_max_desc']
        preserve_max_bytes = Convert-ProbeNumber $fields['preserve_max_bytes']
        preserve_last_desc = Convert-ProbeNumber $fields['preserve_last_desc']
        preserve_last_bytes = Convert-ProbeNumber $fields['preserve_last_bytes']
        preserve_last_first_ea = Format-ProbeHex $fields['preserve_last_first_ea']
        preserve_last_last_ea = Format-ProbeHex $fields['preserve_last_last_ea']
        preserve_family1_groups = if ($fields.ContainsKey('preserve_family1_groups')) { Convert-ProbeNumber $fields['preserve_family1_groups'] } else { 0 }
        preserve_family1_desc = if ($fields.ContainsKey('preserve_family1_desc')) { Convert-ProbeNumber $fields['preserve_family1_desc'] } else { 0 }
        preserve_family1_bytes = if ($fields.ContainsKey('preserve_family1_bytes')) { Convert-ProbeNumber $fields['preserve_family1_bytes'] } else { 0 }
        preserve_family2_groups = if ($fields.ContainsKey('preserve_family2_groups')) { Convert-ProbeNumber $fields['preserve_family2_groups'] } else { 0 }
        preserve_family2_desc = if ($fields.ContainsKey('preserve_family2_desc')) { Convert-ProbeNumber $fields['preserve_family2_desc'] } else { 0 }
        preserve_family2_bytes = if ($fields.ContainsKey('preserve_family2_bytes')) { Convert-ProbeNumber $fields['preserve_family2_bytes'] } else { 0 }
        preserve_family3_groups = if ($fields.ContainsKey('preserve_family3_groups')) { Convert-ProbeNumber $fields['preserve_family3_groups'] } else { 0 }
        preserve_family3_desc = if ($fields.ContainsKey('preserve_family3_desc')) { Convert-ProbeNumber $fields['preserve_family3_desc'] } else { 0 }
        preserve_family3_bytes = if ($fields.ContainsKey('preserve_family3_bytes')) { Convert-ProbeNumber $fields['preserve_family3_bytes'] } else { 0 }
        preserve_family4_groups = if ($fields.ContainsKey('preserve_family4_groups')) { Convert-ProbeNumber $fields['preserve_family4_groups'] } else { 0 }
        preserve_family4_desc = if ($fields.ContainsKey('preserve_family4_desc')) { Convert-ProbeNumber $fields['preserve_family4_desc'] } else { 0 }
        preserve_family4_bytes = if ($fields.ContainsKey('preserve_family4_bytes')) { Convert-ProbeNumber $fields['preserve_family4_bytes'] } else { 0 }
        preserve_family5_groups = if ($fields.ContainsKey('preserve_family5_groups')) { Convert-ProbeNumber $fields['preserve_family5_groups'] } else { 0 }
        preserve_family5_desc = if ($fields.ContainsKey('preserve_family5_desc')) { Convert-ProbeNumber $fields['preserve_family5_desc'] } else { 0 }
        preserve_family5_bytes = if ($fields.ContainsKey('preserve_family5_bytes')) { Convert-ProbeNumber $fields['preserve_family5_bytes'] } else { 0 }
        preserve_family6_groups = if ($fields.ContainsKey('preserve_family6_groups')) { Convert-ProbeNumber $fields['preserve_family6_groups'] } else { 0 }
        preserve_family6_desc = if ($fields.ContainsKey('preserve_family6_desc')) { Convert-ProbeNumber $fields['preserve_family6_desc'] } else { 0 }
        preserve_family6_bytes = if ($fields.ContainsKey('preserve_family6_bytes')) { Convert-ProbeNumber $fields['preserve_family6_bytes'] } else { 0 }
        size16_candidate_groups = if ($fields.ContainsKey('size16_candidate_groups')) { Convert-ProbeNumber $fields['size16_candidate_groups'] } else { 0 }
        size16_candidate_desc = if ($fields.ContainsKey('size16_candidate_desc')) { Convert-ProbeNumber $fields['size16_candidate_desc'] } else { 0 }
        size16_candidate_bytes = if ($fields.ContainsKey('size16_candidate_bytes')) { Convert-ProbeNumber $fields['size16_candidate_bytes'] } else { 0 }
        size16_candidate_family3_groups = if ($fields.ContainsKey('size16_candidate_family3_groups')) { Convert-ProbeNumber $fields['size16_candidate_family3_groups'] } else { 0 }
        size16_candidate_family3_desc = if ($fields.ContainsKey('size16_candidate_family3_desc')) { Convert-ProbeNumber $fields['size16_candidate_family3_desc'] } else { 0 }
        size16_candidate_family3_bytes = if ($fields.ContainsKey('size16_candidate_family3_bytes')) { Convert-ProbeNumber $fields['size16_candidate_family3_bytes'] } else { 0 }
        size16_candidate_family4_groups = if ($fields.ContainsKey('size16_candidate_family4_groups')) { Convert-ProbeNumber $fields['size16_candidate_family4_groups'] } else { 0 }
        size16_candidate_family4_desc = if ($fields.ContainsKey('size16_candidate_family4_desc')) { Convert-ProbeNumber $fields['size16_candidate_family4_desc'] } else { 0 }
        size16_candidate_family4_bytes = if ($fields.ContainsKey('size16_candidate_family4_bytes')) { Convert-ProbeNumber $fields['size16_candidate_family4_bytes'] } else { 0 }
        size16_body_groups = if ($fields.ContainsKey('size16_body_groups')) { Convert-ProbeNumber $fields['size16_body_groups'] } else { 0 }
        size16_body_desc = if ($fields.ContainsKey('size16_body_desc')) { Convert-ProbeNumber $fields['size16_body_desc'] } else { 0 }
        size16_body_bytes = if ($fields.ContainsKey('size16_body_bytes')) { Convert-ProbeNumber $fields['size16_body_bytes'] } else { 0 }
        size16_body_family3_groups = if ($fields.ContainsKey('size16_body_family3_groups')) { Convert-ProbeNumber $fields['size16_body_family3_groups'] } else { 0 }
        size16_body_family3_desc = if ($fields.ContainsKey('size16_body_family3_desc')) { Convert-ProbeNumber $fields['size16_body_family3_desc'] } else { 0 }
        size16_body_family3_bytes = if ($fields.ContainsKey('size16_body_family3_bytes')) { Convert-ProbeNumber $fields['size16_body_family3_bytes'] } else { 0 }
        size16_body_family4_groups = if ($fields.ContainsKey('size16_body_family4_groups')) { Convert-ProbeNumber $fields['size16_body_family4_groups'] } else { 0 }
        size16_body_family4_desc = if ($fields.ContainsKey('size16_body_family4_desc')) { Convert-ProbeNumber $fields['size16_body_family4_desc'] } else { 0 }
        size16_body_family4_bytes = if ($fields.ContainsKey('size16_body_family4_bytes')) { Convert-ProbeNumber $fields['size16_body_family4_bytes'] } else { 0 }
        size16_reject_groups = if ($fields.ContainsKey('size16_reject_groups')) { Convert-ProbeNumber $fields['size16_reject_groups'] } else { 0 }
        size16_reject_single_groups = if ($fields.ContainsKey('size16_reject_single_groups')) { Convert-ProbeNumber $fields['size16_reject_single_groups'] } else { 0 }
        size16_reject_partial_groups = if ($fields.ContainsKey('size16_reject_partial_groups')) { Convert-ProbeNumber $fields['size16_reject_partial_groups'] } else { 0 }
        size16_reject_stop_groups = if ($fields.ContainsKey('size16_reject_stop_groups')) { Convert-ProbeNumber $fields['size16_reject_stop_groups'] } else { 0 }
        size16_last_family = if ($fields.ContainsKey('size16_last_family')) { Convert-ProbeNumber $fields['size16_last_family'] } else { 0 }
        size16_last_desc = if ($fields.ContainsKey('size16_last_desc')) { Convert-ProbeNumber $fields['size16_last_desc'] } else { 0 }
        size16_last_bytes = if ($fields.ContainsKey('size16_last_bytes')) { Convert-ProbeNumber $fields['size16_last_bytes'] } else { 0 }
        size16_last_first_ea = if ($fields.ContainsKey('size16_last_first_ea')) { Format-ProbeHex $fields['size16_last_first_ea'] } else { "0x0" }
        size16_last_last_ea = if ($fields.ContainsKey('size16_last_last_ea')) { Format-ProbeHex $fields['size16_last_last_ea'] } else { "0x0" }
        family1_calls   = Convert-ProbeNumber $fields['family1_calls']
        family2_calls   = Convert-ProbeNumber $fields['family2_calls']
        family3_calls   = Convert-ProbeNumber $fields['family3_calls']
        family4_calls   = Convert-ProbeNumber $fields['family4_calls']
        family5_calls   = Convert-ProbeNumber $fields['family5_calls']
        family6_calls   = Convert-ProbeNumber $fields['family6_calls']
        last_family     = Convert-ProbeNumber $fields['last_family']
        last_pc         = Format-ProbeHex $fields['last_pc']
        last_cmd        = Format-ProbeHex $fields['last_cmd']
        last_tag        = Convert-ProbeNumber $fields['last_tag']
        last_size       = Convert-ProbeNumber $fields['last_size']
        last_lsa        = Format-ProbeHex $fields['last_lsa']
        last_eal        = Format-ProbeHex $fields['last_eal']
        last_desc_ts    = Convert-ProbeNumber $fields['last_desc_ts']
        last_desc_ea    = Format-ProbeHex $fields['last_desc_ea']
        cause           = Format-ProbeHex $fields['cause']
        status          = Format-ProbeHex $fields['status']
    }
}

function Read-SpuHle451cPreserveBodyRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata SPU HLE 451c preserve-body verifier:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('groups')) {
        return $null
    }

    return [pscustomobject]@{
        mode          = $fields['mode']
        hle_mode      = $fields['hle_mode']
        title         = $fields['title']
        ppu           = Format-ProbeHex $fields['ppu']
        ppu_name      = $fields['ppu_name']
        group         = Format-ProbeHex $fields['group']
        group_name    = $fields['group_name']
        spu           = Format-ProbeHex $fields['spu']
        spu_index     = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name      = $fields['spu_name']
        entry         = Format-ProbeHex $fields['entry']
        image_sig     = Format-ProbeHex $fields['image_sig']
        groups        = Convert-ProbeNumber $fields['groups']
        desc          = Convert-ProbeNumber $fields['desc']
        bytes         = Convert-ProbeNumber $fields['bytes']
        last_family   = Convert-ProbeNumber $fields['last_family']
        last_desc     = Convert-ProbeNumber $fields['last_desc']
        last_bytes    = Convert-ProbeNumber $fields['last_bytes']
        last_first_ea = Format-ProbeHex $fields['last_first_ea']
        last_last_ea  = Format-ProbeHex $fields['last_last_ea']
        cause         = Format-ProbeHex $fields['cause']
        status        = Format-ProbeHex $fields['status']
    }
}

function Read-MfcDynamicRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC dynamic probe:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode        = $fields['mode']
        ladder_mode = $fields['ladder_mode']
        title       = $fields['title']
        group       = Format-ProbeHex $fields['group']
        group_name  = $fields['group_name']
        spu         = Format-ProbeHex $fields['spu']
        spu_index   = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name    = $fields['spu_name']
        entry       = Format-ProbeHex $fields['entry']
        image_sig   = Format-ProbeHex $fields['image_sig']
        hits        = Convert-ProbeNumber $fields['hits']
        success     = Convert-ProbeNumber $fields['success']
        fail        = Convert-ProbeNumber $fields['fail']
        bytes       = Convert-ProbeNumber $fields['bytes']
        total_us    = Convert-ProbeNumber $fields['total_us']
        max_total_us = Convert-ProbeNumber $fields['max_total_us']
        pc25_hits   = Convert-ProbeNumber $fields['pc25_hits']
        pc25_us     = Convert-ProbeNumber $fields['pc25_us']
        pc451c_hits = Convert-ProbeNumber $fields['pc451c_hits']
        pc451c_us   = Convert-ProbeNumber $fields['pc451c_us']
        pc0a70_hits = Convert-ProbeNumber $fields['pc0a70_hits']
        pc0a70_us   = Convert-ProbeNumber $fields['pc0a70_us']
        get_hits    = Convert-ProbeNumber $fields['get_hits']
        put_hits    = Convert-ProbeNumber $fields['put_hits']
        list_hits   = Convert-ProbeNumber $fields['list_hits']
        atomic_hits = Convert-ProbeNumber $fields['atomic_hits']
        other_hits  = Convert-ProbeNumber $fields['other_hits']
        last_pc     = Format-ProbeHex $fields['last_pc']
        last_cmd    = Format-ProbeHex $fields['last_cmd']
        last_lsa    = Format-ProbeHex $fields['last_lsa']
        last_eal    = Format-ProbeHex $fields['last_eal']
        last_size   = Convert-ProbeNumber $fields['last_size']
        last_tag    = Convert-ProbeNumber $fields['last_tag']
        cause       = Format-ProbeHex $fields['cause']
        status      = Format-ProbeHex $fields['status']
    }
}

function Read-MfcListRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC list transfer probe:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('calls')) {
        return $null
    }

    return [pscustomobject]@{
        mode          = $fields['mode']
        ladder_mode   = $fields['ladder_mode']
        title         = $fields['title']
        group         = Format-ProbeHex $fields['group']
        group_name    = $fields['group_name']
        spu           = Format-ProbeHex $fields['spu']
        spu_index     = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name      = $fields['spu_name']
        entry         = Format-ProbeHex $fields['entry']
        image_sig     = Format-ProbeHex $fields['image_sig']
        calls         = Convert-ProbeNumber $fields['calls']
        success       = Convert-ProbeNumber $fields['success']
        fail          = Convert-ProbeNumber $fields['fail']
        desc_bytes    = Convert-ProbeNumber $fields['desc_bytes']
        total_us      = Convert-ProbeNumber $fields['total_us']
        max_total_us  = Convert-ProbeNumber $fields['max_total_us']
        pc451c_hits   = Convert-ProbeNumber $fields['pc451c_hits']
        pc451c_us     = Convert-ProbeNumber $fields['pc451c_us']
        pc0a70_hits   = Convert-ProbeNumber $fields['pc0a70_hits']
        pc0a70_us     = Convert-ProbeNumber $fields['pc0a70_us']
        other_hits    = Convert-ProbeNumber $fields['other_hits']
        other_us      = Convert-ProbeNumber $fields['other_us']
        get_calls     = Convert-ProbeNumber $fields['get_calls']
        put_calls     = Convert-ProbeNumber $fields['put_calls']
        last_pc       = Format-ProbeHex $fields['last_pc']
        last_cmd      = Format-ProbeHex $fields['last_cmd']
        last_lsa      = Format-ProbeHex $fields['last_lsa']
        last_eal      = Format-ProbeHex $fields['last_eal']
        last_size     = Convert-ProbeNumber $fields['last_size']
        last_tag      = Convert-ProbeNumber $fields['last_tag']
        cause         = Format-ProbeHex $fields['cause']
        status        = Format-ProbeHex $fields['status']
    }
}

function Read-MfcWaitRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC wait probe:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('reads')) {
        return $null
    }

    return [pscustomobject]@{
        mode           = $fields['mode']
        ladder_mode    = $fields['ladder_mode']
        reservation_mode = $fields['reservation_mode']
        title          = $fields['title']
        group          = Format-ProbeHex $fields['group']
        group_name     = $fields['group_name']
        spu            = Format-ProbeHex $fields['spu']
        spu_index      = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name       = $fields['spu_name']
        entry          = Format-ProbeHex $fields['entry']
        image_sig      = Format-ProbeHex $fields['image_sig']
        reads          = Convert-ProbeNumber $fields['reads']
        fast_reads     = Convert-ProbeNumber $fields['fast_reads']
        blocking_reads = Convert-ProbeNumber $fields['blocking_reads']
        tagstat_reads  = Convert-ProbeNumber $fields['tagstat_reads']
        atomic_reads   = Convert-ProbeNumber $fields['atomic_reads']
        total_us       = Convert-ProbeNumber $fields['total_us']
        max_total_us   = Convert-ProbeNumber $fields['max_total_us']
        pc2598_hits    = Convert-ProbeNumber $fields['pc2598_hits']
        pc2598_us      = Convert-ProbeNumber $fields['pc2598_us']
        pc2600_hits    = Convert-ProbeNumber $fields['pc2600_hits']
        pc2600_us      = Convert-ProbeNumber $fields['pc2600_us']
        pc25_hits      = Convert-ProbeNumber $fields['pc25_hits']
        pc25_us        = Convert-ProbeNumber $fields['pc25_us']
        pc0b44_hits    = Convert-ProbeNumber $fields['pc0b44_hits']
        pc0b44_us      = Convert-ProbeNumber $fields['pc0b44_us']
        pc29e4_hits    = Convert-ProbeNumber $fields['pc29e4_hits']
        pc29e4_us      = Convert-ProbeNumber $fields['pc29e4_us']
        pc451c_hits    = Convert-ProbeNumber $fields['pc451c_hits']
        pc451c_us      = Convert-ProbeNumber $fields['pc451c_us']
        other_hits     = Convert-ProbeNumber $fields['other_hits']
        other_us       = Convert-ProbeNumber $fields['other_us']
        last_pc        = Format-ProbeHex $fields['last_pc']
        last_ch        = Convert-ProbeNumber $fields['last_ch']
        last_value     = Format-ProbeHex $fields['last_value']
        cause          = Format-ProbeHex $fields['cause']
        status         = Format-ProbeHex $fields['status']
    }
}

function Read-MfcWaitPcRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC wait pc probe:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('pc') -or -not $fields.ContainsKey('reads')) {
        return $null
    }

    return [pscustomobject]@{
        mode           = $fields['mode']
        ladder_mode    = $fields['ladder_mode']
        reservation_mode = $fields['reservation_mode']
        title          = $fields['title']
        group          = Format-ProbeHex $fields['group']
        group_name     = $fields['group_name']
        spu            = Format-ProbeHex $fields['spu']
        spu_index      = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name       = $fields['spu_name']
        entry          = Format-ProbeHex $fields['entry']
        image_sig      = Format-ProbeHex $fields['image_sig']
        pc             = Format-ProbeHex $fields['pc']
        reads          = Convert-ProbeNumber $fields['reads']
        tagstat_reads  = Convert-ProbeNumber $fields['tagstat_reads']
        atomic_reads   = Convert-ProbeNumber $fields['atomic_reads']
        overflow_reads = Convert-ProbeNumber $fields['overflow_reads']
        last_pc        = Format-ProbeHex $fields['last_pc']
        last_ch        = Convert-ProbeNumber $fields['last_ch']
        cause          = Format-ProbeHex $fields['cause']
        status         = Format-ProbeHex $fields['status']
    }
}

function Read-ReservationLoopCmdRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata reservation loop cmd probe:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('cmd_hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode             = $fields['mode']
        reservation_mode = $fields['reservation_mode']
        title            = $fields['title']
        group            = Format-ProbeHex $fields['group']
        group_name       = $fields['group_name']
        spu              = Format-ProbeHex $fields['spu']
        spu_index        = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name         = $fields['spu_name']
        entry            = Format-ProbeHex $fields['entry']
        image_sig        = Format-ProbeHex $fields['image_sig']
        cmd_hits         = Convert-ProbeNumber $fields['cmd_hits']
        getllar_cmds     = Convert-ProbeNumber $fields['getllar_cmds']
        putllc_cmds      = Convert-ProbeNumber $fields['putllc_cmds']
        putlluc_cmds     = Convert-ProbeNumber $fields['putlluc_cmds']
        putqlluc_cmds    = Convert-ProbeNumber $fields['putqlluc_cmds']
        atomic_updates   = Convert-ProbeNumber $fields['atomic_updates']
        getllar_success  = Convert-ProbeNumber $fields['getllar_success']
        putllc_success   = Convert-ProbeNumber $fields['putllc_success']
        putllc_failure   = Convert-ProbeNumber $fields['putllc_failure']
        putlluc_success  = Convert-ProbeNumber $fields['putlluc_success']
        atomic_other     = Convert-ProbeNumber $fields['atomic_other']
        pc_overflow      = Convert-ProbeNumber $fields['pc_overflow']
        last_pc          = Format-ProbeHex $fields['last_pc']
        last_cmd         = Format-ProbeHex $fields['last_cmd']
        last_lsa         = Format-ProbeHex $fields['last_lsa']
        last_eal         = Format-ProbeHex $fields['last_eal']
        last_size        = Convert-ProbeNumber $fields['last_size']
        last_tag         = Convert-ProbeNumber $fields['last_tag']
        last_atomic      = Format-ProbeHex $fields['last_atomic']
        last_raddr       = Format-ProbeHex $fields['last_raddr']
        last_rtime       = Format-ProbeHex $fields['last_rtime']
        last_events      = Format-ProbeHex $fields['last_events']
        cause            = Format-ProbeHex $fields['cause']
        status           = Format-ProbeHex $fields['status']
    }
}

function Read-ReservationLoopCmdPcRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata reservation loop cmd pc probe:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('pc') -or -not $fields.ContainsKey('cmd_hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode             = $fields['mode']
        reservation_mode = $fields['reservation_mode']
        title            = $fields['title']
        group            = Format-ProbeHex $fields['group']
        group_name       = $fields['group_name']
        spu              = Format-ProbeHex $fields['spu']
        spu_index        = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name         = $fields['spu_name']
        entry            = Format-ProbeHex $fields['entry']
        image_sig        = Format-ProbeHex $fields['image_sig']
        pc               = Format-ProbeHex $fields['pc']
        cmd_hits         = Convert-ProbeNumber $fields['cmd_hits']
        getllar_cmds     = Convert-ProbeNumber $fields['getllar_cmds']
        putllc_cmds      = Convert-ProbeNumber $fields['putllc_cmds']
        putlluc_cmds     = Convert-ProbeNumber $fields['putlluc_cmds']
        putqlluc_cmds    = Convert-ProbeNumber $fields['putqlluc_cmds']
        atomic_updates   = Convert-ProbeNumber $fields['atomic_updates']
        getllar_success  = Convert-ProbeNumber $fields['getllar_success']
        putllc_success   = Convert-ProbeNumber $fields['putllc_success']
        putllc_failure   = Convert-ProbeNumber $fields['putllc_failure']
        putlluc_success  = Convert-ProbeNumber $fields['putlluc_success']
        atomic_other     = Convert-ProbeNumber $fields['atomic_other']
        overflow         = Convert-ProbeNumber $fields['overflow']
        cause            = Format-ProbeHex $fields['cause']
        status           = Format-ProbeHex $fields['status']
    }
}

function Read-ReservationLoopVerifyRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata reservation loop verify (probe|lane):') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('attempts')) {
        return $null
    }

    $scope = if ($fields.ContainsKey('scope')) { $fields['scope'] } elseif ($Line -match 'verify lane:') { "lane" } else { "aggregate" }

    return [pscustomobject]@{
        scope              = $scope
        mode               = $fields['mode']
        reservation_mode   = $fields['reservation_mode']
        title              = $fields['title']
        group              = Format-ProbeHex $fields['group']
        group_name         = $fields['group_name']
        spu                = Format-ProbeHex $fields['spu']
        spu_index          = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name           = $fields['spu_name']
        entry              = Format-ProbeHex $fields['entry']
        image_sig          = Format-ProbeHex $fields['image_sig']
        attempts           = Convert-ProbeNumber $fields['attempts']
        getllar_cmds       = Convert-ProbeNumber $fields['getllar_cmds']
        getllar_success    = Convert-ProbeNumber $fields['getllar_success']
        putllc_cmds        = Convert-ProbeNumber $fields['putllc_cmds']
        getllar_updates    = Convert-ProbeNumber $fields['getllar_updates']
        putllc_updates     = Convert-ProbeNumber $fields['putllc_updates']
        update_linked      = Convert-ProbeNumber $fields['update_linked']
        update_unlinked    = Convert-ProbeNumber $fields['update_unlinked']
        atomic_reads       = Convert-ProbeNumber $fields['atomic_reads']
        read_getllar       = Convert-ProbeNumber $fields['read_getllar']
        read_putllc        = Convert-ProbeNumber $fields['read_putllc']
        read_success       = Convert-ProbeNumber $fields['read_success']
        read_failure       = Convert-ProbeNumber $fields['read_failure']
        read_unexpected    = Convert-ProbeNumber $fields['read_unexpected']
        read_fast          = Convert-ProbeNumber $fields['read_fast']
        read_blocking      = Convert-ProbeNumber $fields['read_blocking']
        completed          = Convert-ProbeNumber $fields['completed']
        success            = Convert-ProbeNumber $fields['success']
        failure            = Convert-ProbeNumber $fields['failure']
        unexpected         = Convert-ProbeNumber $fields['unexpected']
        raddr_match        = Convert-ProbeNumber $fields['raddr_match']
        rtime_match        = Convert-ProbeNumber $fields['rtime_match']
        main_line_readable = Convert-ProbeNumber $fields['main_line_readable']
        main_line_match    = Convert-ProbeNumber $fields['main_line_match']
        dirty_zero         = Convert-ProbeNumber $fields['dirty_zero']
        dirty_one_or_two   = Convert-ProbeNumber $fields['dirty_one_or_two']
        dirty_multi        = Convert-ProbeNumber $fields['dirty_multi']
        post_raddr_zero    = Convert-ProbeNumber $fields['post_raddr_zero']
        post_raddr_same    = Convert-ProbeNumber $fields['post_raddr_same']
        post_lr_event_set  = Convert-ProbeNumber $fields['post_lr_event_set']
        retry_branches     = Convert-ProbeNumber $fields['retry_branches']
        retry_taken        = Convert-ProbeNumber $fields['retry_taken']
        retry_fallthrough  = Convert-ProbeNumber $fields['retry_fallthrough']
        next_branches      = Convert-ProbeNumber $fields['next_branches']
        next_taken         = Convert-ProbeNumber $fields['next_taken']
        next_fallthrough   = Convert-ProbeNumber $fields['next_fallthrough']
        state              = Convert-ProbeNumber $fields['state']
        lane               = Convert-ProbeNumber $fields['lane']
        last_cmd_pc        = Format-ProbeHex $fields['last_cmd_pc']
        last_atomic_pc     = Format-ProbeHex $fields['last_atomic_pc']
        last_read_pc       = Format-ProbeHex $fields['last_read_pc']
        last_raw_cmd_pc    = Format-ProbeHex $fields['last_raw_cmd_pc']
        last_raw_atomic_pc = Format-ProbeHex $fields['last_raw_atomic_pc']
        last_raw_read_pc   = Format-ProbeHex $fields['last_raw_read_pc']
        last_retry_pc      = Format-ProbeHex $fields['last_retry_pc']
        last_next_branch_pc = Format-ProbeHex $fields['last_next_branch_pc']
        last_lsa           = Format-ProbeHex $fields['last_lsa']
        last_eal           = Format-ProbeHex $fields['last_eal']
        last_changed_mask  = Format-ProbeHex $fields['last_changed_mask']
        last_atomic        = Format-ProbeHex $fields['last_atomic']
        last_read_atomic   = Format-ProbeHex $fields['last_read_atomic']
        last_raddr         = Format-ProbeHex $fields['last_raddr']
        last_rtime         = Format-ProbeHex $fields['last_rtime']
        last_events        = Format-ProbeHex $fields['last_events']
        last_branch_pc     = Format-ProbeHex $fields['last_branch_pc']
        last_branch_target = Format-ProbeHex $fields['last_branch_target']
        last_branch_taken  = Convert-ProbeNumber $fields['last_branch_taken']
        cause              = Format-ProbeHex $fields['cause']
        status             = Format-ProbeHex $fields['status']
    }
}

function Read-Putllc16Record {
    param([string]$Line)

    if ($Line -notmatch 'SPU: .*?(GETLLAR pattern entry point|PUTLLC16 Pattern Detected!|PUTLLC16 Pair Pattern Candidate!|PUTLLC pattern breakage)') {
        return $null
    }

    $elapsed = ""
    $worker = ""
    if ($Line -match '\s(?<elapsed>\d+:\d+:\d+(?:\.\d+)?)\s+\{(?<worker>[^}]+)\}\s+SPU:') {
        $elapsed = $Matches['elapsed']
        $worker = $Matches['worker']
    }

    if ($Line -match '\[(?<entry>0x[0-9a-fA-F]+)\]\s+GETLLAR pattern entry point') {
        return [pscustomobject]@{
            kind           = "entry"
            elapsed        = $elapsed
            worker         = $worker
            entry_pc       = Format-ProbeHexToken $Matches['entry']
            function_sig   = ""
            function_pc    = ""
            pattern_hash   = ""
            mem_count      = [UInt64]0
            put_pc         = ""
            pc_rel         = [UInt64]0
            offset         = ""
            is_const       = [UInt64]0
            two_regs       = [UInt64]0
            reg            = [UInt64]0
            runtime        = [UInt64]0
            putllc0_count  = [UInt64]0
            putllc16_count = [UInt64]0
            all_count      = [UInt64]0
            break_pc       = ""
            mem            = [UInt64]0
            lsa_const      = [UInt64]0
            cause          = [UInt64]0
            cause_reason   = ""
            lsa_pc         = ""
        }
    }

    if ($Line -match 'PUTLLC16 Pair Pattern Candidate!\s+\(mem_count=(?<mem_count>\d+),\s+put_pc=(?<put_pc>0x[0-9a-fA-F]+),\s+offsets=(?<offset0>0x[0-9a-fA-F]+)/(?<offset1>0x[0-9a-fA-F]+),\s+write_mask=(?<write_mask>0x[0-9a-fA-F]+),\s+access_mask=(?<access_mask>0x[0-9a-fA-F]+),\s+no_notify=(?<no_notify>\d+),\s+(?<function_sig>0x[0-9a-fA-F]+-[^,\)]+),\s+pattern-hash=(?<pattern_hash>[^)\s]+)\)') {
        $functionSig = $Matches['function_sig']
        $memCount = $Matches['mem_count']
        $putPc = $Matches['put_pc']
        $offset0 = $Matches['offset0']
        $offset1 = $Matches['offset1']
        $writeMask = $Matches['write_mask']
        $accessMask = $Matches['access_mask']
        $noNotify = $Matches['no_notify']
        $patternHash = $Matches['pattern_hash']
        $functionPc = ""
        if ($functionSig -match '^(?<pc>0x[0-9a-fA-F]+)-') {
            $functionPc = Format-ProbeHexToken $Matches['pc']
        }

        return [pscustomobject]@{
            kind           = "pair-candidate"
            elapsed        = $elapsed
            worker         = $worker
            entry_pc       = ""
            function_sig   = $functionSig
            function_pc    = $functionPc
            pattern_hash   = $patternHash
            mem_count      = Convert-ProbeNumber $memCount
            put_pc         = Format-ProbeHexToken $putPc
            pc_rel         = [UInt64]0
            offset         = "$(Format-ProbeHexToken $offset0)/$(Format-ProbeHexToken $offset1)"
            pair_offset0   = Format-ProbeHexToken $offset0
            pair_offset1   = Format-ProbeHexToken $offset1
            write_mask     = Format-ProbeHexToken $writeMask
            access_mask    = Format-ProbeHexToken $accessMask
            no_notify      = Convert-ProbeNumber $noNotify
            is_const       = [UInt64]0
            two_regs       = [UInt64]0
            reg            = [UInt64]0
            runtime        = [UInt64]0
            putllc0_count  = [UInt64]0
            putllc16_count = [UInt64]0
            all_count      = [UInt64]0
            break_pc       = ""
            mem            = [UInt64]0
            lsa_const      = [UInt64]0
            cause          = [UInt64]0
            cause_reason   = ""
            lsa_pc         = ""
        }
    }

    if ($Line -match 'PUTLLC16 Pattern Detected!\s+\(mem_count=(?<mem_count>\d+),\s+put_pc=(?<put_pc>0x[0-9a-fA-F]+),\s+pc_rel=(?<pc_rel>\d+),\s+offset=(?<offset>0x[0-9a-fA-F]+),\s+const=(?<is_const>\d+),\s+two_regs=(?<two_regs>\d+),\s+reg=(?<reg>\d+),\s+runtime=(?<runtime>\d+),\s+(?<function_sig>0x[0-9a-fA-F]+-[^,\)]+),\s+pattern-hash=(?<pattern_hash>[^)\s]+)\)\s+\(putllc0=(?<putllc0>\d+),\s+putllc16\+0=(?<putllc16>\d+),\s+all=(?<all>\d+)\)') {
        $functionSig = $Matches['function_sig']
        $memCount = $Matches['mem_count']
        $putPc = $Matches['put_pc']
        $pcRel = $Matches['pc_rel']
        $offset = $Matches['offset']
        $isConst = $Matches['is_const']
        $twoRegs = $Matches['two_regs']
        $reg = $Matches['reg']
        $runtime = $Matches['runtime']
        $patternHash = $Matches['pattern_hash']
        $putllc0 = $Matches['putllc0']
        $putllc16 = $Matches['putllc16']
        $all = $Matches['all']
        $functionPc = ""
        if ($functionSig -match '^(?<pc>0x[0-9a-fA-F]+)-') {
            $functionPc = Format-ProbeHexToken $Matches['pc']
        }

        return [pscustomobject]@{
            kind           = "detected"
            elapsed        = $elapsed
            worker         = $worker
            entry_pc       = ""
            function_sig   = $functionSig
            function_pc    = $functionPc
            pattern_hash   = $patternHash
            mem_count      = Convert-ProbeNumber $memCount
            put_pc         = Format-ProbeHexToken $putPc
            pc_rel         = Convert-ProbeNumber $pcRel
            offset         = Format-ProbeHexToken $offset
            is_const       = Convert-ProbeNumber $isConst
            two_regs       = Convert-ProbeNumber $twoRegs
            reg            = Convert-ProbeNumber $reg
            runtime        = Convert-ProbeNumber $runtime
            putllc0_count  = Convert-ProbeNumber $putllc0
            putllc16_count = Convert-ProbeNumber $putllc16
            all_count      = Convert-ProbeNumber $all
            break_pc       = ""
            mem            = [UInt64]0
            lsa_const      = [UInt64]0
            cause          = [UInt64]0
            cause_reason   = ""
            lsa_pc         = ""
        }
    }

    if ($Line -match 'PUTLLC pattern breakage\s+\[(?<break_pc>[0-9a-fA-F]+)\s+mem=(?<mem>\d+)\s+lsa_const=(?<lsa_const>\d+)\s+cause=(?<cause>\d+)\]\s+\(lsa_pc=(?<lsa_pc>0x[0-9a-fA-F]+)\)') {
        $cause = Convert-ProbeNumber $Matches['cause']
        return [pscustomobject]@{
            kind           = "breakage"
            elapsed        = $elapsed
            worker         = $worker
            entry_pc       = ""
            function_sig   = ""
            function_pc    = ""
            pattern_hash   = ""
            mem_count      = [UInt64]0
            put_pc         = ""
            pc_rel         = [UInt64]0
            offset         = ""
            is_const       = [UInt64]0
            two_regs       = [UInt64]0
            reg            = [UInt64]0
            runtime        = [UInt64]0
            putllc0_count  = [UInt64]0
            putllc16_count = [UInt64]0
            all_count      = [UInt64]0
            break_pc       = Format-ProbeHexToken $Matches['break_pc']
            mem            = Convert-ProbeNumber $Matches['mem']
            lsa_const      = Convert-ProbeNumber $Matches['lsa_const']
            cause          = $cause
            cause_reason   = Get-Putllc16BreakCauseReason $cause
            lsa_pc         = Format-ProbeHexToken $Matches['lsa_pc']
        }
    }

    return $null
}

function Read-Putllc16RuntimeRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata PUTLLC16 runtime probe:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode             = $fields['mode']
        ladder_mode      = $fields['ladder_mode']
        putllc16_res     = if ($fields.ContainsKey('putllc16_res')) { $fields['putllc16_res'] } else { "unknown" }
        title            = $fields['title']
        group            = Format-ProbeHex $fields['group']
        group_name       = $fields['group_name']
        spu              = Format-ProbeHex $fields['spu']
        spu_index        = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name         = $fields['spu_name']
        entry            = Format-ProbeHex $fields['entry']
        image_sig        = Format-ProbeHex $fields['image_sig']
        hits             = Convert-ProbeNumber $fields['hits']
        success          = Convert-ProbeNumber $fields['success']
        fail             = Convert-ProbeNumber $fields['fail']
        pc0ad4_hits      = Convert-ProbeNumber $fields['pc0ad4_hits']
        pc0ad4_success   = Convert-ProbeNumber $fields['pc0ad4_success']
        pc0c24_hits      = Convert-ProbeNumber $fields['pc0c24_hits']
        pc0c24_success   = Convert-ProbeNumber $fields['pc0c24_success']
        other_hits       = Convert-ProbeNumber $fields['other_hits']
        other_success    = Convert-ProbeNumber $fields['other_success']
        last_pc          = Format-ProbeHex $fields['last_pc']
        last_eal         = Format-ProbeHex $fields['last_eal']
        last_lsa         = Format-ProbeHex $fields['last_lsa']
        last_dest        = Format-ProbeHex $fields['last_dest']
        cause            = Format-ProbeHex $fields['cause']
        status           = Format-ProbeHex $fields['status']
    }
}

function Read-Putllc16PairVerifyRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata PUTLLC16 pair verify:') {
        return $null
    }

    $fields = Get-ProbeFields $Line
    if (-not $fields.ContainsKey('hits')) {
        return $null
    }

    return [pscustomobject]@{
        mode               = $fields['mode']
        pair_mode          = $fields['pair_mode']
        putllc16_res       = if ($fields.ContainsKey('putllc16_res')) { $fields['putllc16_res'] } else { "unknown" }
        title              = $fields['title']
        group              = Format-ProbeHex $fields['group']
        group_name         = $fields['group_name']
        spu                = Format-ProbeHex $fields['spu']
        spu_index          = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name           = $fields['spu_name']
        entry              = Format-ProbeHex $fields['entry']
        image_sig          = Format-ProbeHex $fields['image_sig']
        hits               = Convert-ProbeNumber $fields['hits']
        in_range           = Convert-ProbeNumber $fields['in_range']
        raddr_match        = Convert-ProbeNumber $fields['raddr_match']
        rtime_match        = Convert-ProbeNumber $fields['rtime_match']
        main_line_readable = Convert-ProbeNumber $fields['main_line_readable']
        main_line_match    = Convert-ProbeNumber $fields['main_line_match']
        changed            = Convert-ProbeNumber $fields['changed']
        no_extra_dirty     = Convert-ProbeNumber $fields['no_extra_dirty']
        extra_dirty        = Convert-ProbeNumber $fields['extra_dirty']
        decoded_mask_match = if ($fields.ContainsKey('decoded_mask_match')) { Convert-ProbeNumber $fields['decoded_mask_match'] } else { 0 }
        pattern_mask_match = if ($fields.ContainsKey('pattern_mask_match')) { Convert-ProbeNumber $fields['pattern_mask_match'] } else { 0 }
        post_hits          = if ($fields.ContainsKey('post_hits')) { Convert-ProbeNumber $fields['post_hits'] } else { 0 }
        post_atomic_ready  = if ($fields.ContainsKey('post_atomic_ready')) { Convert-ProbeNumber $fields['post_atomic_ready'] } else { 0 }
        post_success       = if ($fields.ContainsKey('post_success')) { Convert-ProbeNumber $fields['post_success'] } else { 0 }
        post_failure       = if ($fields.ContainsKey('post_failure')) { Convert-ProbeNumber $fields['post_failure'] } else { 0 }
        post_atomic_other  = if ($fields.ContainsKey('post_atomic_other')) { Convert-ProbeNumber $fields['post_atomic_other'] } else { 0 }
        post_raddr_zero    = if ($fields.ContainsKey('post_raddr_zero')) { Convert-ProbeNumber $fields['post_raddr_zero'] } else { 0 }
        post_raddr_same    = if ($fields.ContainsKey('post_raddr_same')) { Convert-ProbeNumber $fields['post_raddr_same'] } else { 0 }
        post_lr_event_set  = if ($fields.ContainsKey('post_lr_event_set')) { Convert-ProbeNumber $fields['post_lr_event_set'] } else { 0 }
        last_pc            = Format-ProbeHex $fields['last_pc']
        last_eal           = Format-ProbeHex $fields['last_eal']
        last_lsa           = Format-ProbeHex $fields['last_lsa']
        last_dest0         = Format-ProbeHex $fields['last_dest0']
        last_dest1         = Format-ProbeHex $fields['last_dest1']
        last_changed_mask  = Format-ProbeHex $fields['last_changed_mask']
        last_expected_mask = Format-ProbeHex $fields['last_expected_mask']
        last_decoded_mask  = if ($fields.ContainsKey('last_decoded_mask')) { Format-ProbeHex $fields['last_decoded_mask'] } else { Format-ProbeHex $fields['last_expected_mask'] }
        last_pattern_mask  = if ($fields.ContainsKey('last_pattern_mask')) { Format-ProbeHex $fields['last_pattern_mask'] } else { Format-ProbeHex $fields['last_expected_mask'] }
        last_post_atomic   = if ($fields.ContainsKey('last_post_atomic')) { Format-ProbeHex $fields['last_post_atomic'] } else { "" }
        last_post_raddr    = if ($fields.ContainsKey('last_post_raddr')) { Format-ProbeHex $fields['last_post_raddr'] } else { "" }
        last_post_events   = if ($fields.ContainsKey('last_post_events')) { Format-ProbeHex $fields['last_post_events'] } else { "" }
        last_notify        = Convert-ProbeNumber $fields['last_notify']
        cause              = Format-ProbeHex $fields['cause']
        status             = Format-ProbeHex $fields['status']
    }
}

function Read-RsxAuditorRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Auditor:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    return [pscustomobject]@{
        frames        = Convert-ProbeNumber $fields['frames']
        submits       = Convert-ProbeNumber $fields['submits']
        waits         = Convert-ProbeNumber $fields['waits']
        signals       = Convert-ProbeNumber $fields['signals']
        flush_req     = Convert-ProbeNumber $fields['flush_req']
        async_req     = Convert-ProbeNumber $fields['async_req']
        hard_sync     = Convert-ProbeNumber $fields['hard_sync']
        rp_break      = Convert-ProbeNumber $fields['rp_break']
        all_barriers  = Convert-ProbeNumber $fields['all']
        pipe          = $fields['pipe']
        detile        = Convert-ProbeNumber $fields['detile']
        simple_upload = Convert-ProbeNumber $fields['simple_upload']
    }
}

function Read-ProbeRsxResourceRecords {
    param([string]$Line)

    $records = New-Object System.Collections.Generic.List[object]

    if ($Line -match 'Thor RSX Blit Source Profile:') {
        $fields = Get-ProbeFields $Line
        $count = Convert-ProbeNumber $fields['count']
        $srcBase = Convert-ProbeNumber $fields['src']
        $dstBase = Convert-ProbeNumber $fields['dst']
        $srcPitch = Convert-ProbeNumber $fields['src_pitch']
        $dstPitch = Convert-ProbeNumber $fields['dst_pitch']
        $srcHeight = Get-ProbeHeightFromExtent $fields['src_req']
        $dstHeight = Get-ProbeHeightFromExtent $fields['dst_req']
        $key = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0" }
        $srcFmt = if ($fields.ContainsKey('src_fmt')) { $fields['src_fmt'] } else { "0x0" }
        $dstFmt = if ($fields.ContainsKey('dst_fmt')) { $fields['dst_fmt'] } else { "0x0" }
        $srcDesc = "src_req=$($fields['src_req']) src_rect=$($fields['src_rect'])"
        $dstDesc = "dst_req=$($fields['dst_req']) dst_rect=$($fields['dst_rect'])"

        $src = New-ProbeRsxResourceRecord -Kind "blit-source" -Role "src" -Base $srcBase -Pitch $srcPitch -Height $srcHeight -Count $count -Format $srcFmt -Key $key -Description $srcDesc
        if ($null -ne $src) { $records.Add($src) | Out-Null }
        $dst = New-ProbeRsxResourceRecord -Kind "blit-source" -Role "dst" -Base $dstBase -Pitch $dstPitch -Height $dstHeight -Count $count -Format $dstFmt -Key $key -Description $dstDesc
        if ($null -ne $dst) { $records.Add($dst) | Out-Null }
    } elseif ($Line -match 'Thor RSX Resolve Profile:') {
        $fields = Get-ProbeFields $Line
        $base = Convert-ProbeNumber $fields['base']
        $pitch = Convert-ProbeNumber $fields['pitch']
        $height = Convert-ProbeNumber $fields['h']
        $sampleRows = [UInt64]([Math]::Max(1, [double](Convert-ProbeNumber $fields['sy'])))
        $key = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0" }
        $fmt = if ($fields.ContainsKey('fmt')) { $fields['fmt'] } else { "0x0" }
        $count = Convert-ProbeNumber $fields['count']
        $desc = "size=$($fields['w'])x$($fields['h']) samples=$($fields['samples']) grid=$($fields['sx'])x$($fields['sy'])"
        $record = New-ProbeRsxResourceRecord -Kind "resolve" -Role "base" -Base $base -Pitch $pitch -Height ($height * $sampleRows) -Count $count -Format $fmt -Key $key -Description $desc
        if ($null -ne $record) { $records.Add($record) | Out-Null }
    } elseif ($Line -match 'Thor RSX Texture Barrier Profile:') {
        $fields = Get-ProbeFields $Line
        $base = Convert-ProbeNumber $fields['base']
        $pitch = Convert-ProbeNumber $fields['pitch']
        $height = Convert-ProbeNumber $fields['h']
        $sampleRows = [UInt64]([Math]::Max(1, [double](Convert-ProbeNumber $fields['sy'])))
        $key = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0" }
        $fmt = if ($fields.ContainsKey('fmt')) { $fields['fmt'] } else { "0x0" }
        $count = Convert-ProbeNumber $fields['count']
        $desc = "size=$($fields['w'])x$($fields['h']) samples=$($fields['samples']) grid=$($fields['sx'])x$($fields['sy']) flags=$($fields['flags'])"
        $record = New-ProbeRsxResourceRecord -Kind "texture-barrier" -Role "base" -Base $base -Pitch $pitch -Height ($height * $sampleRows) -Count $count -Format $fmt -Key $key -Description $desc
        if ($null -ne $record) { $records.Add($record) | Out-Null }
    }

    return $records
}

function New-ProbeDmaRange {
    param(
        [string]$SourceType,
        [object]$Record,
        [UInt64]$Start,
        [UInt64]$Bytes
    )

    if ($Start -eq 0 -or $Bytes -eq 0) {
        return $null
    }

    return [pscustomobject]@{
        source_type = $SourceType
        pc          = $Record.max_dma_pc
        group_name  = $Record.group_name
        spu_name    = $Record.spu_name
        image_sig   = $Record.image_sig
        pattern_sig = $Record.pattern_sig
        start       = Format-ProbeHexNumber $Start
        end         = Format-ProbeHexNumber ($Start + $Bytes)
        start_value = $Start
        end_value   = $Start + $Bytes
        bytes       = $Bytes
    }
}

function New-ProbeMfcShapeRange {
    param([object]$Record)

    $start = Convert-ProbeNumber $Record.eal_min
    $last = Convert-ProbeNumber $Record.eal_max
    $bytes = [UInt64]([Math]::Max(1, [double]$Record.size))
    if ($last -ge $start) {
        $bytes = ($last - $start) + $bytes
    }

    return [pscustomobject]@{
        source_type = "mfc-shape"
        pc          = $Record.pc
        group_name  = $Record.group_name
        spu_name    = $Record.spu_name
        image_sig   = $Record.image_sig
        pattern_sig = $Record.block_hash
        start       = Format-ProbeHexNumber $start
        end         = Format-ProbeHexNumber ($start + $bytes)
        start_value = $start
        end_value   = $start + $bytes
        bytes       = $bytes
    }
}

function Get-ProbeRangeOverlapBytes {
    param(
        [UInt64]$AStart,
        [UInt64]$AEnd,
        [UInt64]$BStart,
        [UInt64]$BEnd
    )

    if ($AStart -ge $BEnd -or $BStart -ge $AEnd) {
        return [UInt64]0
    }

    $start = [Math]::Max([double]$AStart, [double]$BStart)
    $end = [Math]::Min([double]$AEnd, [double]$BEnd)
    return [UInt64]([Math]::Max(0.0, $end - $start))
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        throw "Pass -RunDir or -LogPath."
    }

    $LogPath = Resolve-ProbeLogPath $RunDir
}

$LogPath = Resolve-ProbePath $LogPath
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "Probe log not found: $LogPath"
}

if ([string]::IsNullOrWhiteSpace($RunDir)) {
    $RunDir = Split-Path -Parent $LogPath
} else {
    $RunDir = Resolve-ProbePath $RunDir
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunDir "eternal-sonata-gpu-probe-summary.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunDir "eternal-sonata-gpu-probe-records.csv"
}
if ([string]::IsNullOrWhiteSpace($MfcShapeCsvPath)) {
    $MfcShapeCsvPath = Join-Path $RunDir "eternal-sonata-mfc-shape-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($MfcLadderCsvPath)) {
    $MfcLadderCsvPath = Join-Path $RunDir "eternal-sonata-mfc-ladder-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHleVerifyCsvPath)) {
    $SpuHleVerifyCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-verify-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHleShadowCsvPath)) {
    $SpuHleShadowCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-shadow-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHle25ccFamilyCsvPath)) {
    $SpuHle25ccFamilyCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-25cc-family-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHle25ccShadowCsvPath)) {
    $SpuHle25ccShadowCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-25cc-shadow-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHle25ccBodyCsvPath)) {
    $SpuHle25ccBodyCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-25cc-body-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHle451cListSeedCsvPath)) {
    $SpuHle451cListSeedCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-451c-list-seed-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHle451cListFamilyCsvPath)) {
    $SpuHle451cListFamilyCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-451c-list-family-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHle451cDescBatchCsvPath)) {
    $SpuHle451cDescBatchCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-451c-desc-batch-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SpuHle451cPreserveBodyCsvPath)) {
    $SpuHle451cPreserveBodyCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-451c-preserve-body-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($MfcDynamicCsvPath)) {
    $MfcDynamicCsvPath = Join-Path $RunDir "eternal-sonata-mfc-dynamic-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($MfcListCsvPath)) {
    $MfcListCsvPath = Join-Path $RunDir "eternal-sonata-mfc-list-transfer-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($MfcWaitCsvPath)) {
    $MfcWaitCsvPath = Join-Path $RunDir "eternal-sonata-mfc-wait-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($MfcWaitPcCsvPath)) {
    $MfcWaitPcCsvPath = Join-Path $RunDir "eternal-sonata-mfc-wait-pc-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($ReservationLoopCmdCsvPath)) {
    $ReservationLoopCmdCsvPath = Join-Path $RunDir "eternal-sonata-reservation-loop-cmd-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($ReservationLoopCmdPcCsvPath)) {
    $ReservationLoopCmdPcCsvPath = Join-Path $RunDir "eternal-sonata-reservation-loop-cmd-pc-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($ReservationLoopVerifyCsvPath)) {
    $ReservationLoopVerifyCsvPath = Join-Path $RunDir "eternal-sonata-reservation-loop-verify-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($ReservationLoopRdchJoinCsvPath)) {
    $ReservationLoopRdchJoinCsvPath = Join-Path $RunDir "eternal-sonata-reservation-loop-rdch-join-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($ReservationLoopLaneJoinCsvPath)) {
    $ReservationLoopLaneJoinCsvPath = Join-Path $RunDir "eternal-sonata-reservation-loop-lane-join-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($ReservationLoopRawLaneCsvPath)) {
    $ReservationLoopRawLaneCsvPath = Join-Path $RunDir "eternal-sonata-reservation-loop-raw-lane-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($Putllc16CsvPath)) {
    $Putllc16CsvPath = Join-Path $RunDir "eternal-sonata-putllc16-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($Putllc16RuntimeCsvPath)) {
    $Putllc16RuntimeCsvPath = Join-Path $RunDir "eternal-sonata-putllc16-runtime-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($Putllc16PairVerifyCsvPath)) {
    $Putllc16PairVerifyCsvPath = Join-Path $RunDir "eternal-sonata-putllc16-pair-verify-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($KernelCapsuleCsvPath)) {
    $KernelCapsuleCsvPath = Join-Path $RunDir "eternal-sonata-kernel-capsule-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($RsxOverlapCsvPath)) {
    $RsxOverlapCsvPath = Join-Path $RunDir "eternal-sonata-rsx-resource-overlap.csv"
}

$records = New-Object System.Collections.Generic.List[object]
$rsxAuditorRecords = New-Object System.Collections.Generic.List[object]
$rsxResourceRecords = New-Object System.Collections.Generic.List[object]
$mfcShapeRecords = New-Object System.Collections.Generic.List[object]
$mfcLadderRecords = New-Object System.Collections.Generic.List[object]
$spuHleVerifyRecords = New-Object System.Collections.Generic.List[object]
$spuHleShadowRecords = New-Object System.Collections.Generic.List[object]
$spuHle25ccFamilyRecords = New-Object System.Collections.Generic.List[object]
$spuHle25ccShadowRecords = New-Object System.Collections.Generic.List[object]
$spuHle25ccBodyRecords = New-Object System.Collections.Generic.List[object]
$spuHle451cListSeedRecords = New-Object System.Collections.Generic.List[object]
$spuHle451cListFamilyRecords = New-Object System.Collections.Generic.List[object]
$spuHle451cDescBatchRecords = New-Object System.Collections.Generic.List[object]
$spuHle451cPreserveBodyRecords = New-Object System.Collections.Generic.List[object]
$spuHleNonConstantWarnings = New-Object System.Collections.Generic.List[object]
$mfcDynamicRecords = New-Object System.Collections.Generic.List[object]
$mfcListRecords = New-Object System.Collections.Generic.List[object]
$mfcWaitRecords = New-Object System.Collections.Generic.List[object]
$mfcWaitPcRecords = New-Object System.Collections.Generic.List[object]
$reservationLoopCmdRecords = New-Object System.Collections.Generic.List[object]
$reservationLoopCmdPcRecords = New-Object System.Collections.Generic.List[object]
$reservationLoopVerifyRecords = New-Object System.Collections.Generic.List[object]
$putllc16Records = New-Object System.Collections.Generic.List[object]
$putllc16RuntimeRecords = New-Object System.Collections.Generic.List[object]
$putllc16PairVerifyRecords = New-Object System.Collections.Generic.List[object]
$kernelCapsuleRecords = New-Object System.Collections.Generic.List[object]
$mfcShapeGroups = @{}
$mfcShapeRawRecords = [UInt64]0
$logLineNumber = 0
foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
    $logLineNumber++

    if ($line -match 'SPU:\s+\[(?<pc>0x[0-9a-fA-F]+)\]\s+MFC_Cmd:\s+\$(?<reg>[0-9]+)\s+is\s+not\s+a\s+constant') {
        $spuHleNonConstantWarnings.Add([pscustomobject]@{
            pc          = Format-ProbeHex $Matches['pc']
            reg         = [int]$Matches['reg']
            line_number = $logLineNumber
        }) | Out-Null
    }

    $record = Read-ProbeRecord $line
    if ($null -ne $record) {
        $records.Add($record) | Out-Null
    }

    $kernelCapsuleRecord = Read-KernelCapsuleRecord $line
    if ($null -ne $kernelCapsuleRecord) {
        $kernelCapsuleRecords.Add($kernelCapsuleRecord) | Out-Null
    }

    $rsxRecord = Read-RsxAuditorRecord $line
    if ($null -ne $rsxRecord) {
        $rsxAuditorRecords.Add($rsxRecord) | Out-Null
    }

    foreach ($rsxResourceRecord in @(Read-ProbeRsxResourceRecords $line)) {
        if ($null -ne $rsxResourceRecord) {
            $rsxResourceRecords.Add($rsxResourceRecord) | Out-Null
        }
    }

    $mfcShapeRecord = Read-MfcShapeRecord $line
    if ($null -ne $mfcShapeRecord) {
        $mfcShapeRawRecords++
        $key = @(
            $mfcShapeRecord.mode,
            $mfcShapeRecord.title,
            $mfcShapeRecord.group_name,
            $mfcShapeRecord.spu_name,
            $mfcShapeRecord.entry,
            $mfcShapeRecord.image_sig,
            $mfcShapeRecord.pc,
            $mfcShapeRecord.block_hash,
            $mfcShapeRecord.cmd,
            $mfcShapeRecord.tag,
            $mfcShapeRecord.size,
            $mfcShapeRecord.lsa,
            $mfcShapeRecord.flags
        ) -join "|"

        $minValue = Convert-ProbeNumber $mfcShapeRecord.eal_min
        $maxValue = Convert-ProbeNumber $mfcShapeRecord.eal_max

        if (-not $mfcShapeGroups.ContainsKey($key)) {
            $mfcShapeGroups[$key] = [pscustomobject]@{
                mode       = $mfcShapeRecord.mode
                title      = $mfcShapeRecord.title
                group      = $mfcShapeRecord.group
                group_name = $mfcShapeRecord.group_name
                spu        = $mfcShapeRecord.spu
                spu_index  = $mfcShapeRecord.spu_index
                spu_name   = $mfcShapeRecord.spu_name
                entry      = $mfcShapeRecord.entry
                image_sig  = $mfcShapeRecord.image_sig
                pc         = $mfcShapeRecord.pc
                block_hash = $mfcShapeRecord.block_hash
                cmd        = $mfcShapeRecord.cmd
                tag        = $mfcShapeRecord.tag
                size       = $mfcShapeRecord.size
                lsa        = $mfcShapeRecord.lsa
                flags      = $mfcShapeRecord.flags
                count      = $mfcShapeRecord.count
                bytes      = $mfcShapeRecord.bytes
                eal_first  = $mfcShapeRecord.eal_first
                eal_last   = $mfcShapeRecord.eal_last
                eal_min    = $mfcShapeRecord.eal_min
                eal_max    = $mfcShapeRecord.eal_max
                overflow   = $mfcShapeRecord.overflow
                cause      = $mfcShapeRecord.cause
                status     = $mfcShapeRecord.status
                eal_min_value = $minValue
                eal_max_value = $maxValue
            }
        } else {
            $aggregate = $mfcShapeGroups[$key]
            $aggregate.count += $mfcShapeRecord.count
            $aggregate.bytes += $mfcShapeRecord.bytes
            $aggregate.eal_last = $mfcShapeRecord.eal_last
            if ($minValue -lt $aggregate.eal_min_value) {
                $aggregate.eal_min_value = $minValue
                $aggregate.eal_min = $mfcShapeRecord.eal_min
            }
            if ($maxValue -gt $aggregate.eal_max_value) {
                $aggregate.eal_max_value = $maxValue
                $aggregate.eal_max = $mfcShapeRecord.eal_max
            }
            if ($mfcShapeRecord.overflow -gt $aggregate.overflow) {
                $aggregate.overflow = $mfcShapeRecord.overflow
            }
        }
    }

    $mfcLadderRecord = Read-MfcLadderRecord $line
    if ($null -ne $mfcLadderRecord) {
        $mfcLadderRecords.Add($mfcLadderRecord) | Out-Null
    }

    $spuHleVerifyRecord = Read-SpuHleVerifyRecord $line
    if ($null -ne $spuHleVerifyRecord) {
        $spuHleVerifyRecords.Add($spuHleVerifyRecord) | Out-Null
    }

    $spuHleShadowRecord = Read-SpuHleShadowRecord $line
    if ($null -ne $spuHleShadowRecord) {
        $spuHleShadowRecords.Add($spuHleShadowRecord) | Out-Null
    }

    $spuHle25ccFamilyRecord = Read-SpuHle25ccFamilyRecord $line
    if ($null -ne $spuHle25ccFamilyRecord) {
        $spuHle25ccFamilyRecords.Add($spuHle25ccFamilyRecord) | Out-Null
    }

    $spuHle25ccShadowRecord = Read-SpuHle25ccShadowRecord $line
    if ($null -ne $spuHle25ccShadowRecord) {
        $spuHle25ccShadowRecords.Add($spuHle25ccShadowRecord) | Out-Null
    }

    $spuHle25ccBodyRecord = Read-SpuHle25ccBodyRecord $line
    if ($null -ne $spuHle25ccBodyRecord) {
        $spuHle25ccBodyRecords.Add($spuHle25ccBodyRecord) | Out-Null
    }

    $spuHle451cListSeedRecord = Read-SpuHle451cListSeedRecord $line
    if ($null -ne $spuHle451cListSeedRecord) {
        $spuHle451cListSeedRecords.Add($spuHle451cListSeedRecord) | Out-Null
    }

    $spuHle451cListFamilyRecord = Read-SpuHle451cListFamilyRecord $line
    if ($null -ne $spuHle451cListFamilyRecord) {
        $spuHle451cListFamilyRecords.Add($spuHle451cListFamilyRecord) | Out-Null
    }

    $spuHle451cDescBatchRecord = Read-SpuHle451cDescBatchRecord $line
    if ($null -ne $spuHle451cDescBatchRecord) {
        $spuHle451cDescBatchRecords.Add($spuHle451cDescBatchRecord) | Out-Null
    }

    $spuHle451cPreserveBodyRecord = Read-SpuHle451cPreserveBodyRecord $line
    if ($null -ne $spuHle451cPreserveBodyRecord) {
        $spuHle451cPreserveBodyRecords.Add($spuHle451cPreserveBodyRecord) | Out-Null
    }

    $mfcDynamicRecord = Read-MfcDynamicRecord $line
    if ($null -ne $mfcDynamicRecord) {
        $mfcDynamicRecords.Add($mfcDynamicRecord) | Out-Null
    }

    $mfcListRecord = Read-MfcListRecord $line
    if ($null -ne $mfcListRecord) {
        $mfcListRecords.Add($mfcListRecord) | Out-Null
    }

    $mfcWaitRecord = Read-MfcWaitRecord $line
    if ($null -ne $mfcWaitRecord) {
        $mfcWaitRecords.Add($mfcWaitRecord) | Out-Null
    }

    $mfcWaitPcRecord = Read-MfcWaitPcRecord $line
    if ($null -ne $mfcWaitPcRecord) {
        $mfcWaitPcRecords.Add($mfcWaitPcRecord) | Out-Null
    }

    $reservationLoopCmdRecord = Read-ReservationLoopCmdRecord $line
    if ($null -ne $reservationLoopCmdRecord) {
        $reservationLoopCmdRecords.Add($reservationLoopCmdRecord) | Out-Null
    }

    $reservationLoopCmdPcRecord = Read-ReservationLoopCmdPcRecord $line
    if ($null -ne $reservationLoopCmdPcRecord) {
        $reservationLoopCmdPcRecords.Add($reservationLoopCmdPcRecord) | Out-Null
    }

    $reservationLoopVerifyRecord = Read-ReservationLoopVerifyRecord $line
    if ($null -ne $reservationLoopVerifyRecord) {
        $reservationLoopVerifyRecords.Add($reservationLoopVerifyRecord) | Out-Null
    }

    $putllc16Record = Read-Putllc16Record $line
    if ($null -ne $putllc16Record) {
        $putllc16Records.Add($putllc16Record) | Out-Null
    }

    $putllc16RuntimeRecord = Read-Putllc16RuntimeRecord $line
    if ($null -ne $putllc16RuntimeRecord) {
        $putllc16RuntimeRecords.Add($putllc16RuntimeRecord) | Out-Null
    }

    $putllc16PairVerifyRecord = Read-Putllc16PairVerifyRecord $line
    if ($null -ne $putllc16PairVerifyRecord) {
        $putllc16PairVerifyRecords.Add($putllc16PairVerifyRecord) | Out-Null
    }
}

foreach ($shape in $mfcShapeGroups.Values) {
    $mfcShapeRecords.Add($shape) | Out-Null
}

$reservationLoopVerifyPeakRows = @(Get-ReservationLoopVerifyPeakRows -Records $reservationLoopVerifyRecords)
$reservationLoopRdchJoinRows = @(Get-ReservationLoopRdchJoinRows -VerifyPeakRows $reservationLoopVerifyPeakRows -WaitPcRecords $mfcWaitPcRecords)
$reservationLoopRawLaneRows = @(Get-ReservationLoopRawLaneRows -RunDir $RunDir -CmdPcRecords $reservationLoopCmdPcRecords -WaitPcRecords $mfcWaitPcRecords)
$reservationLoopLaneJoinRows = @(Get-ReservationLoopLaneJoinRows -CmdPcRecords $reservationLoopCmdPcRecords -WaitPcRecords $mfcWaitPcRecords -VerifyRecords $reservationLoopVerifyRecords -RawLaneRows $reservationLoopRawLaneRows)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata GPU Probe Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $(Get-Date -Format o)") | Out-Null
$lines.Add("- Log: $LogPath") | Out-Null
$lines.Add("- Records: $($records.Count)") | Out-Null
$lines.Add("- MFC shape records: $mfcShapeRawRecords raw, $($mfcShapeRecords.Count) aggregated") | Out-Null
$lines.Add("- MFC ladder records: $($mfcLadderRecords.Count)") | Out-Null
$lines.Add("- SPU HLE verifier records: $($spuHleVerifyRecords.Count)") | Out-Null
$lines.Add("- SPU HLE shadow records: $($spuHleShadowRecords.Count)") | Out-Null
$lines.Add("- SPU HLE 0x25cc family records: $($spuHle25ccFamilyRecords.Count)") | Out-Null
$lines.Add("- SPU HLE 0x25cc shadow records: $($spuHle25ccShadowRecords.Count)") | Out-Null
$lines.Add("- SPU HLE 0x25cc body records: $($spuHle25ccBodyRecords.Count)") | Out-Null
$lines.Add("- SPU HLE 0x451c list-seed records: $($spuHle451cListSeedRecords.Count)") | Out-Null
$lines.Add("- SPU HLE 0x451c list-family records: $($spuHle451cListFamilyRecords.Count)") | Out-Null
$lines.Add("- SPU HLE 0x451c descriptor-batch records: $($spuHle451cDescBatchRecords.Count)") | Out-Null
$lines.Add("- SPU HLE 0x451c preserve-body records: $($spuHle451cPreserveBodyRecords.Count)") | Out-Null
$lines.Add("- SPU HLE non-constant MFC warnings: $($spuHleNonConstantWarnings.Count)") | Out-Null
$lines.Add("- MFC dynamic records: $($mfcDynamicRecords.Count)") | Out-Null
$lines.Add("- MFC list transfer records: $($mfcListRecords.Count)") | Out-Null
$lines.Add("- MFC wait records: $($mfcWaitRecords.Count)") | Out-Null
$lines.Add("- MFC wait exact-PC records: $($mfcWaitPcRecords.Count)") | Out-Null
$lines.Add("- Reservation loop command records: $($reservationLoopCmdRecords.Count)") | Out-Null
$lines.Add("- Reservation loop command exact-PC records: $($reservationLoopCmdPcRecords.Count)") | Out-Null
$lines.Add("- Reservation loop verify records: $($reservationLoopVerifyRecords.Count)") | Out-Null
$lines.Add("- Reservation loop RDCH join records: $($reservationLoopRdchJoinRows.Count)") | Out-Null
$lines.Add("- Reservation loop lane-join records: $($reservationLoopLaneJoinRows.Count)") | Out-Null
$lines.Add("- Reservation loop raw-lane records: $($reservationLoopRawLaneRows.Count)") | Out-Null
$lines.Add("- PUTLLC16 analyzer records: $($putllc16Records.Count)") | Out-Null
$lines.Add("- PUTLLC16 runtime records: $($putllc16RuntimeRecords.Count)") | Out-Null
$lines.Add("- PUTLLC16 pair verify records: $($putllc16PairVerifyRecords.Count)") | Out-Null
$lines.Add("- Kernel capsule records: $($kernelCapsuleRecords.Count)") | Out-Null
$lines.Add("- RSX auditor records: $($rsxAuditorRecords.Count)") | Out-Null
$lines.Add("- Top rows: $Top") | Out-Null

if ($records.Count -eq 0 -and $spuHleVerifyRecords.Count -eq 0 -and $spuHleShadowRecords.Count -eq 0 -and $spuHle25ccFamilyRecords.Count -eq 0 -and $spuHle25ccShadowRecords.Count -eq 0 -and $spuHle25ccBodyRecords.Count -eq 0 -and $spuHle451cListSeedRecords.Count -eq 0 -and $spuHle451cListFamilyRecords.Count -eq 0 -and $spuHle451cDescBatchRecords.Count -eq 0 -and $spuHle451cPreserveBodyRecords.Count -eq 0) {
    $lines.Add("") | Out-Null
    $lines.Add('No `Eternal Sonata GPU/DMA candidate probe` records were found.') | Out-Null

    if ($putllc16Records.Count -gt 0) {
        $putllc16Records |
            Select-Object kind,elapsed,worker,entry_pc,function_sig,function_pc,pattern_hash,mem_count,put_pc,pc_rel,offset,pair_offset0,pair_offset1,write_mask,access_mask,no_notify,is_const,two_regs,reg,runtime,putllc0_count,putllc16_count,all_count,break_pc,mem,lsa_const,cause,cause_reason,lsa_pc |
            Export-Csv -LiteralPath $Putllc16CsvPath -NoTypeInformation -Encoding UTF8
        $lines.Add("- PUTLLC16 analyzer CSV: $Putllc16CsvPath") | Out-Null

        $putllcEntries = @($putllc16Records | Where-Object { $_.kind -eq "entry" })
        $putllcDetected = @($putllc16Records | Where-Object { $_.kind -eq "detected" })
        $putllcPairs = @($putllc16Records | Where-Object { $_.kind -eq "pair-candidate" })
        $putllcBreakages = @($putllc16Records | Where-Object { $_.kind -eq "breakage" })

        $lines.Add("") | Out-Null
        $lines.Add("## PUTLLC16 Analyzer") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("- GETLLAR entry records: $($putllcEntries.Count)") | Out-Null
        $lines.Add("- PUTLLC16 detected records: $($putllcDetected.Count)") | Out-Null
        $lines.Add("- PUTLLC16 pair candidate records: $($putllcPairs.Count)") | Out-Null
        $lines.Add("- PUTLLC pattern breakage records: $($putllcBreakages.Count)") | Out-Null

        if ($putllcDetected.Count -gt 0) {
            $lines.Add("") | Out-Null
            $lines.Add("### Detected Patterns") | Out-Null
            $lines.Add("") | Out-Null
            $lines.Add("| Rank | Pattern Hash | Records | Function | Put PC | Mem Count | Runtime | Last PUTLLC16 Count |") | Out-Null
            $lines.Add("| ---: | --- | ---: | --- | --- | ---: | ---: | ---: |") | Out-Null

            $rank = 1
            foreach ($row in @(
                $putllcDetected |
                    Group-Object -Property pattern_hash,function_sig,put_pc |
                    ForEach-Object {
                        $groupRecords = @($_.Group)
                        $first = $groupRecords[0]
                        $peakCounter = $groupRecords | Sort-Object -Property putllc16_count -Descending | Select-Object -First 1
                        [pscustomobject]@{
                            pattern_hash   = $first.pattern_hash
                            records        = $_.Count
                            function_sig   = $first.function_sig
                            put_pc         = $first.put_pc
                            mem_count      = $first.mem_count
                            runtime        = $first.runtime
                            putllc16_count = $peakCounter.putllc16_count
                        }
                    } |
                    Sort-Object -Property records, putllc16_count -Descending |
                    Select-Object -First $Top
            )) {
                $lines.Add(('| {0} | `{1}` | {2} | `{3}` | `{4}` | {5} | {6} | {7} |' -f
                    $rank,
                    $row.pattern_hash,
                    $row.records,
                    $row.function_sig,
                    $row.put_pc,
                    $row.mem_count,
                    $row.runtime,
                    $row.putllc16_count)) | Out-Null
                $rank++
            }
        }

        if ($putllcPairs.Count -gt 0) {
            $lines.Add("") | Out-Null
            $lines.Add("### Pair Candidates") | Out-Null
            $lines.Add("") | Out-Null
            $lines.Add("| Rank | Pattern Hash | Records | Function | Put PC | Mem Count | Offsets | Write Mask | Access Mask | No Notify |") | Out-Null
            $lines.Add("| ---: | --- | ---: | --- | --- | ---: | --- | --- | --- | ---: |") | Out-Null

            $rank = 1
            foreach ($row in @(
                $putllcPairs |
                    Group-Object -Property pattern_hash,function_sig,put_pc |
                    ForEach-Object {
                        $first = $_.Group[0]
                        [pscustomobject]@{
                            pattern_hash = $first.pattern_hash
                            records      = $_.Count
                            function_sig = $first.function_sig
                            put_pc       = $first.put_pc
                            mem_count    = $first.mem_count
                            offsets      = $first.offset
                            write_mask   = $first.write_mask
                            access_mask  = $first.access_mask
                            no_notify    = $first.no_notify
                        }
                    } |
                    Sort-Object -Property records -Descending |
                    Select-Object -First $Top
            )) {
                $lines.Add(('| {0} | `{1}` | {2} | `{3}` | `{4}` | {5} | `{6}` | `{7}` | `{8}` | {9} |' -f
                    $rank,
                    $row.pattern_hash,
                    $row.records,
                    $row.function_sig,
                    $row.put_pc,
                    $row.mem_count,
                    $row.offsets,
                    $row.write_mask,
                    $row.access_mask,
                    $row.no_notify)) | Out-Null
                $rank++
            }
        }

        if ($putllcBreakages.Count -gt 0) {
            $lines.Add("") | Out-Null
            $lines.Add("### Breakage PCs") | Out-Null
            $lines.Add("") | Out-Null
            $lines.Add("| Rank | Cause | Reason | Records | Break PC | LSA PC | Mem | LSA Const | Worker |") | Out-Null
            $lines.Add("| ---: | ---: | --- | ---: | --- | --- | ---: | ---: | --- |") | Out-Null

            $rank = 1
            foreach ($row in @(
                $putllcBreakages |
                    Group-Object -Property cause,break_pc,lsa_pc |
                    ForEach-Object {
                        $groupRecords = @($_.Group)
                        $first = $groupRecords[0]
                        [pscustomobject]@{
                            cause        = $first.cause
                            cause_reason = $first.cause_reason
                            records      = $_.Count
                            break_pc     = $first.break_pc
                            lsa_pc       = $first.lsa_pc
                            mem          = $first.mem
                            lsa_const    = $first.lsa_const
                            worker       = $first.worker
                        }
                    } |
                    Sort-Object -Property records -Descending |
                    Select-Object -First $Top
            )) {
                $lines.Add(('| {0} | {1} | {2} | {3} | `{4}` | `{5}` | {6} | {7} | `{8}` |' -f
                    $rank,
                    $row.cause,
                    $row.cause_reason,
                    $row.records,
                    $row.break_pc,
                    $row.lsa_pc,
                    $row.mem,
                    $row.lsa_const,
                    $row.worker)) | Out-Null
                $rank++
            }
        }

        $lines.Add("") | Out-Null
        $lines.Add("PUTLLC16 reading: detected patterns are existing CPU-side reduced-loop/codegen opportunities; breakage PCs explain where the recognizer refused to replace a reservation loop. This is still a CPU/SPU specialization track unless a later capture proves a stable bulk body or RSX-consumed buffer behind the loop.") | Out-Null
    }

    if ($putllc16RuntimeRecords.Count -gt 0) {
        $putllc16RuntimeRecords |
            Select-Object mode,ladder_mode,putllc16_res,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,success,fail,pc0ad4_hits,pc0ad4_success,pc0c24_hits,pc0c24_success,other_hits,other_success,last_pc,last_eal,last_lsa,last_dest,cause,status |
            Export-Csv -LiteralPath $Putllc16RuntimeCsvPath -NoTypeInformation -Encoding UTF8
        $lines.Add("- PUTLLC16 runtime CSV: $Putllc16RuntimeCsvPath") | Out-Null
    }

    if ($putllc16PairVerifyRecords.Count -gt 0) {
        $putllc16PairVerifyRecords |
            Select-Object mode,pair_mode,putllc16_res,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,in_range,raddr_match,rtime_match,main_line_readable,main_line_match,changed,no_extra_dirty,extra_dirty,decoded_mask_match,pattern_mask_match,post_hits,post_atomic_ready,post_success,post_failure,post_atomic_other,post_raddr_zero,post_raddr_same,post_lr_event_set,last_pc,last_eal,last_lsa,last_dest0,last_dest1,last_changed_mask,last_expected_mask,last_decoded_mask,last_pattern_mask,last_post_atomic,last_post_raddr,last_post_events,last_notify,cause,status |
            Export-Csv -LiteralPath $Putllc16PairVerifyCsvPath -NoTypeInformation -Encoding UTF8
        $lines.Add("- PUTLLC16 pair verify CSV: $Putllc16PairVerifyCsvPath") | Out-Null
        $pairVerifyPeaks = @(
            $putllc16PairVerifyRecords |
                Group-Object -Property group_name,spu_name,last_pc |
                ForEach-Object {
                    $_.Group | Sort-Object -Property hits -Descending | Select-Object -First 1
                }
        )
        $pairHits = [UInt64](($pairVerifyPeaks | Measure-Object -Property hits -Sum).Sum)
        $pairExtraDirty = [UInt64](($pairVerifyPeaks | Measure-Object -Property extra_dirty -Sum).Sum)
        $pairDecoded = [UInt64](($pairVerifyPeaks | Measure-Object -Property decoded_mask_match -Sum).Sum)
        $pairPattern = [UInt64](($pairVerifyPeaks | Measure-Object -Property pattern_mask_match -Sum).Sum)
        $pairPostSuccess = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_success -Sum).Sum)
        $pairPostFailure = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_failure -Sum).Sum)
        $lines.Add("- PUTLLC16 pair verify peak hits: $pairHits; peak extra-dirty hits: $pairExtraDirty") | Out-Null
        $lines.Add("- PUTLLC16 pair verify decoded-mask / pattern-mask matches: $pairDecoded / $pairPattern") | Out-Null
        $lines.Add("- PUTLLC16 pair verify post stock success/failure: $pairPostSuccess / $pairPostFailure") | Out-Null
    }

    if ($reservationLoopVerifyRecords.Count -gt 0) {
        $reservationLoopVerifyRecords |
            Select-Object scope,mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,attempts,getllar_cmds,getllar_success,putllc_cmds,getllar_updates,putllc_updates,update_linked,update_unlinked,atomic_reads,read_getllar,read_putllc,read_success,read_failure,read_unexpected,read_fast,read_blocking,completed,success,failure,unexpected,raddr_match,rtime_match,main_line_readable,main_line_match,dirty_zero,dirty_one_or_two,dirty_multi,post_raddr_zero,post_raddr_same,post_lr_event_set,retry_branches,retry_taken,retry_fallthrough,next_branches,next_taken,next_fallthrough,state,lane,last_cmd_pc,last_atomic_pc,last_read_pc,last_raw_cmd_pc,last_raw_atomic_pc,last_raw_read_pc,last_retry_pc,last_next_branch_pc,last_lsa,last_eal,last_changed_mask,last_atomic,last_read_atomic,last_raddr,last_rtime,last_events,last_branch_pc,last_branch_target,last_branch_taken,cause,status |
            Export-Csv -LiteralPath $ReservationLoopVerifyCsvPath -NoTypeInformation -Encoding UTF8
        $lines.Add("- Reservation loop verify CSV: $ReservationLoopVerifyCsvPath") | Out-Null
    }

    if ($reservationLoopRdchJoinRows.Count -gt 0) {
        $reservationLoopRdchJoinRows |
            Select-Object mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,getllar_cmd_pc,getllar_read_pc,getllar_attempts,getllar_updates,getllar_exact_reads,getllar_read_minus_attempts,getllar_read_coverage,putllc_cmd_pc,putllc_read_pc,putllc_completed,putllc_updates,putllc_exact_reads,putllc_read_minus_completed,putllc_read_coverage,update_linked,update_unlinked,in_hook_atomic_reads,exact_atomic_reads,exact_minus_in_hook_reads,unexpected,dirty_multi,lane,last_cmd_pc,last_atomic_pc,last_read_pc,last_raw_cmd_pc,last_raw_atomic_pc,last_raw_read_pc,last_retry_pc,last_next_branch_pc,cause,status |
            Export-Csv -LiteralPath $ReservationLoopRdchJoinCsvPath -NoTypeInformation -Encoding UTF8
        $lines.Add("- Reservation loop RDCH join CSV: $ReservationLoopRdchJoinCsvPath") | Out-Null
    }

    if ($reservationLoopRawLaneRows.Count -gt 0) {
        $reservationLoopRawLaneRows |
            Select-Object title,entry,image_sig,group_name,spu_name,raw_getllar_cmd_pc,raw_getllar_read_pc,raw_putllc_cmd_pc,raw_putllc_read_pc,raw_retry_branch_pc,raw_retry_branch,raw_next_branch_pc,raw_next_branch,getllar_cmd_hits,putllc_cmd_hits,getllar_read_hits,putllc_read_hits,source_focus_pcs,source_file_count,source_files,classification,cause,status |
            Export-Csv -LiteralPath $ReservationLoopRawLaneCsvPath -NoTypeInformation -Encoding UTF8
        $lines.Add("- Reservation loop raw-lane CSV: $ReservationLoopRawLaneCsvPath") | Out-Null

        $lines.Add("") | Out-Null
        $lines.Add("## Reservation Loop Raw SPU Lanes") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("- Raw SPU reservation lanes found in disassembly sidecars: $($reservationLoopRawLaneRows.Count)") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | Raw GET/RD | Raw PUT/RD | Retry | Next Branch | Cmd Hits G/P | Read Hits G/P | Focus PCs | Group | SPU |") | Out-Null
        $lines.Add("| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

        $rank = 1
        foreach ($record in @($reservationLoopRawLaneRows | Select-Object -First $Top)) {
            $lines.Add(('| {0} | `{1}`/`{2}` | `{3}`/`{4}` | `{5}` `{6}` | `{7}` `{8}` | {9}/{10} | {11}/{12} | `{13}` | `{14}` | `{15}` |' -f
                $rank,
                $record.raw_getllar_cmd_pc,
                $record.raw_getllar_read_pc,
                $record.raw_putllc_cmd_pc,
                $record.raw_putllc_read_pc,
                $record.raw_retry_branch_pc,
                $record.raw_retry_branch,
                $record.raw_next_branch_pc,
                $record.raw_next_branch,
                $record.getllar_cmd_hits,
                $record.putllc_cmd_hits,
                $record.getllar_read_hits,
                $record.putllc_read_hits,
                $record.source_focus_pcs,
                $record.group_name,
                $record.spu_name)) | Out-Null
            $rank++
        }

        $lines.Add("") | Out-Null
        $lines.Add('Raw lane reading: this parses SPU disassembly windows and keeps raw instruction PCs separate from the exact-PC counter/focus PCs. Use this to choose whole-loop verifier lanes and retry/next-branch checks before any fast/HLE/GPU replacement; it is analysis only, not GPU migration credit or a speed claim.') | Out-Null
    }

    $lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Host "GPU probe summary: $OutPath"
    return
}

$records | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
$lines.Add("- CSV: $CsvPath") | Out-Null
if ($mfcShapeRecords.Count -gt 0) {
    $mfcShapeRecords |
        Select-Object mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,pc,block_hash,cmd,tag,size,lsa,flags,count,bytes,eal_first,eal_last,eal_min,eal_max,overflow,cause,status |
        Export-Csv -LiteralPath $MfcShapeCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC shape CSV: $MfcShapeCsvPath") | Out-Null
}
if ($mfcLadderRecords.Count -gt 0) {
    $mfcLadderRecords |
        Select-Object mode,ladder_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,pc,last_lsa,eligible,verify_hits,fast_hits,blocked,mismatches,bytes,check_us,transfer_us,total_us,max_check_us,max_transfer_us,max_total_us,eal_first,eal_last,eal_min,eal_max,cause,status |
        Export-Csv -LiteralPath $MfcLadderCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC ladder CSV: $MfcLadderCsvPath") | Out-Null
}
if ($spuHleVerifyRecords.Count -gt 0) {
    $spuHleVerifyRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,runtime_hits,llvm_hits,get_hits,put_hits,pc25_hits,pc451c_hits,other_pc_hits,bytes,runtime_bytes,llvm_bytes,last_path,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,cause,status |
        Export-Csv -LiteralPath $SpuHleVerifyCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE verifier CSV: $SpuHleVerifyCsvPath") | Out-Null
}
if ($spuHleShadowRecords.Count -gt 0) {
    $spuHleShadowRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,bytes,src_repeats,dst_pre_repeats,dst_post_repeats,dst_changed,dst_unchanged,output_match,output_mismatch,skip_hits,skip_bytes,skip_misses,skip_miss_bytes,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,last_src_hash,last_dst_pre_hash,last_dst_post_hash,cause,status |
        Export-Csv -LiteralPath $SpuHleShadowCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE shadow CSV: $SpuHleShadowCsvPath") | Out-Null
}
if ($spuHle25ccFamilyRecords.Count -gt 0) {
    $spuHle25ccFamilyRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,success,fail,get_hits,put_hits,bytes,total_us,max_total_us,ea9e4000_hits,ea4f0b80_hits,exact_a1c000_hits,other_ea_hits,last_family,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,cause,status |
        Export-Csv -LiteralPath $SpuHle25ccFamilyCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE 0x25cc family CSV: $SpuHle25ccFamilyCsvPath") | Out-Null
}
if ($spuHle25ccShadowRecords.Count -gt 0) {
    $spuHle25ccShadowRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,get_hits,put_hits,bytes,ea9e4000_hits,ea4f0b80_hits,exact_a1c000_hits,other_ea_hits,src_repeats,dst_pre_repeats,dst_post_repeats,dst_changed,dst_unchanged,output_match,output_mismatch,last_family,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,last_src_hash,last_dst_pre_hash,last_dst_post_hash,cause,status |
        Export-Csv -LiteralPath $SpuHle25ccShadowCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE 0x25cc shadow CSV: $SpuHle25ccShadowCsvPath") | Out-Null
}
if ($spuHle25ccBodyRecords.Count -gt 0) {
    $spuHle25ccBodyRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,get_hits,put_rejects,bytes,total_us,max_total_us,ea9e4000_hits,ea4f0b80_hits,exact_a1c000_hits,other_ea_hits,last_family,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,cause,status |
        Export-Csv -LiteralPath $SpuHle25ccBodyCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE 0x25cc body CSV: $SpuHle25ccBodyCsvPath") | Out-Null
}
if ($spuHle25ccShadowRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE 0x25cc Shadow Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $shadow25Hits = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property hits -Sum).Sum)
    $shadow25Bytes = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property bytes -Sum).Sum)
    $shadow25GetHits = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property get_hits -Sum).Sum)
    $shadow25PutHits = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property put_hits -Sum).Sum)
    $shadow25Changed = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property dst_changed -Sum).Sum)
    $shadow25Unchanged = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property dst_unchanged -Sum).Sum)
    $shadow25Match = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property output_match -Sum).Sum)
    $shadow25Mismatch = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property output_mismatch -Sum).Sum)
    $shadow25Ea9 = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property ea9e4000_hits -Sum).Sum)
    $shadow25Other = [UInt64](($spuHle25ccShadowRecords | Measure-Object -Property other_ea_hits -Sum).Sum)
    $shadow25UniqueSrc = @($spuHle25ccShadowRecords | Select-Object -ExpandProperty last_src_hash -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    $shadow25UniqueDstPost = @($spuHle25ccShadowRecords | Select-Object -ExpandProperty last_dst_post_hash -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count

    $lines.Add("- Hits: $shadow25Hits") | Out-Null
    $lines.Add("- Direction hits: GET=$shadow25GetHits, PUT=$shadow25PutHits") | Out-Null
    $lines.Add("- EA hits: ea9e4000=$shadow25Ea9, other=$shadow25Other") | Out-Null
    $lines.Add("- Bytes: $(Format-ProbeBytes $shadow25Bytes)") | Out-Null
    $lines.Add("- Destination changed/unchanged: $shadow25Changed / $shadow25Unchanged") | Out-Null
    $lines.Add("- Output match/mismatch: $shadow25Match / $shadow25Mismatch") | Out-Null
    $lines.Add("- Unique last source hashes: $shadow25UniqueSrc; unique last destination-post hashes: $shadow25UniqueDstPost") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Hits | GET | PUT | EA 0x9e4000 | Other EA | Changed | Match | Last Family | Last PC | Last Cmd | Last LSA | Last EAL | Src Hash | Dst Pre Hash | Dst Post Hash | Group | SPU |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHle25ccShadowRecords | Sort-Object -Property hits, bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | `{9}` | `{10}` | `{11}` | `{12}` | `{13}` | `{14}` | `{15}` | `{16}` | `{17}` |' -f
            $rank,
            $record.hits,
            $record.get_hits,
            $record.put_hits,
            $record.ea9e4000_hits,
            $record.other_ea_hits,
            $record.dst_changed,
            $record.output_match,
            $record.last_family,
            $record.last_pc,
            $record.last_cmd,
            $record.last_lsa,
            $record.last_eal,
            $record.last_src_hash,
            $record.last_dst_pre_hash,
            $record.last_dst_post_hash,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("SPU HLE 0x25cc shadow reading: verify-only source/destination hashing for repeated runtime-family DMA. It does not skip or offload work; use it to decide whether any 0x25cc HLE/codegen body is semantically safe after field/menu/battle proof.") | Out-Null
}
if ($spuHle25ccBodyRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE 0x25cc Body Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $body25Hits = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property hits -Sum).Sum)
    $body25Bytes = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property bytes -Sum).Sum)
    $body25GetHits = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property get_hits -Sum).Sum)
    $body25PutRejects = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property put_rejects -Sum).Sum)
    $body25TotalUs = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property total_us -Sum).Sum)
    $body25MaxTotalUs = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $body25Ea9e4000Hits = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property ea9e4000_hits -Sum).Sum)
    $body25Ea4f0b80Hits = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property ea4f0b80_hits -Sum).Sum)
    $body25ExactA1c000Hits = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property exact_a1c000_hits -Sum).Sum)
    $body25OtherEaHits = [UInt64](($spuHle25ccBodyRecords | Measure-Object -Property other_ea_hits -Sum).Sum)
    $body25TimedHits = [UInt64]([Math]::Max(1, [double]$body25Hits))

    $lines.Add("- Hits: $body25Hits") | Out-Null
    $lines.Add("- Direction: GET body hits=$body25GetHits, PUT rejects=$body25PutRejects") | Out-Null
    $lines.Add("- EA hits: ea9e4000=$body25Ea9e4000Hits, ea4f0b80=$body25Ea4f0b80Hits, exact_a1c000=$body25ExactA1c000Hits, other=$body25OtherEaHits") | Out-Null
    $lines.Add("- Bytes: $(Format-ProbeBytes $body25Bytes)") | Out-Null
    $lines.Add(("- Timing: total={0:n3} ms, avg={1:n3} us/hit, max={2} us" -f ($body25TotalUs / 1000.0), ([double]$body25TotalUs / [double]$body25TimedHits), $body25MaxTotalUs)) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Hits | Total ms | Avg us | Max us | GET | PUT Rejects | EA 0x9e4000 | EA 0x4f0b80 | Exact 0xa1c000 | Other EA | Last Family | Last PC | Last Cmd | Last Tag | Last Size | Last LSA | Last EAL | Bytes | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHle25ccBodyRecords | Sort-Object -Property total_us, hits -Descending | Select-Object -First $Top)) {
        $avgUs = [double]$record.total_us / [double]([Math]::Max(1, [double]$record.hits))
        $lines.Add(('| {0} | {1} | {2:n3} | {3:n3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | `{12}` | `{13}` | {14} | {15} | `{16}` | `{17}` | {18} | `{19}` | `{20}` | `{21}` |' -f
            $rank,
            $record.hits,
            ($record.total_us / 1000.0),
            $avgUs,
            $record.max_total_us,
            $record.get_hits,
            $record.put_rejects,
            $record.ea9e4000_hits,
            $record.ea4f0b80_hits,
            $record.exact_a1c000_hits,
            $record.other_ea_hits,
            $record.last_family,
            $record.last_pc,
            $record.last_cmd,
            $record.last_tag,
            $record.last_size,
            $record.last_lsa,
            $record.last_eal,
            $record.bytes,
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add('SPU HLE 0x25cc body reading: this is an opt-in Windows verifier for a CPU-side GET copy-body scaffold under `RPCS3_ES_SPU_HLE_25CC_BODY`. It is not GPU migration, not a speed win, and still requires field, Options, first-battle visuals plus matched timing before any micro-win claim.') | Out-Null
}
if ($spuHle25ccFamilyRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE 0x25cc Family Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $family25Hits = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property hits -Sum).Sum)
    $family25Success = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property success -Sum).Sum)
    $family25Fail = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property fail -Sum).Sum)
    $family25GetHits = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property get_hits -Sum).Sum)
    $family25PutHits = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property put_hits -Sum).Sum)
    $family25Bytes = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property bytes -Sum).Sum)
    $family25TotalUs = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property total_us -Sum).Sum)
    $family25MaxTotalUs = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $family25Ea9e4000Hits = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property ea9e4000_hits -Sum).Sum)
    $family25Ea4f0b80Hits = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property ea4f0b80_hits -Sum).Sum)
    $family25ExactA1c000Hits = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property exact_a1c000_hits -Sum).Sum)
    $family25OtherEaHits = [UInt64](($spuHle25ccFamilyRecords | Measure-Object -Property other_ea_hits -Sum).Sum)
    $family25TimedHits = [UInt64]([Math]::Max(1, [double]$family25Hits))

    $lines.Add("- Hits: $family25Hits") | Out-Null
    $lines.Add("- Success / fail: $family25Success / $family25Fail") | Out-Null
    $lines.Add("- Direction hits: GET=$family25GetHits, PUT=$family25PutHits") | Out-Null
    $lines.Add("- EA hits: ea9e4000=$family25Ea9e4000Hits, ea4f0b80=$family25Ea4f0b80Hits, exact_a1c000=$family25ExactA1c000Hits, other=$family25OtherEaHits") | Out-Null
    $lines.Add("- Bytes: $(Format-ProbeBytes $family25Bytes)") | Out-Null
    $lines.Add(("- Timing: total={0:n3} ms, avg={1:n3} us/hit, max={2} us" -f ($family25TotalUs / 1000.0), ([double]$family25TotalUs / [double]$family25TimedHits), $family25MaxTotalUs)) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Hits | Total ms | Avg us | Max us | Success | Fail | GET | PUT | EA 0x9e4000 | EA 0x4f0b80 | Exact 0xa1c000 | Other EA | Last Family | Last PC | Last Cmd | Last Tag | Last Size | Last LSA | Last EAL | Bytes | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHle25ccFamilyRecords | Sort-Object -Property total_us, hits -Descending | Select-Object -First $Top)) {
        $avgUs = [double]$record.total_us / [double]([Math]::Max(1, [double]$record.hits))
        $lines.Add(('| {0} | {1} | {2:n3} | {3:n3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} | `{14}` | `{15}` | {16} | {17} | `{18}` | `{19}` | {20} | `{21}` | `{22}` | `{23}` |' -f
            $rank,
            $record.hits,
            ($record.total_us / 1000.0),
            $avgUs,
            $record.max_total_us,
            $record.success,
            $record.fail,
            $record.get_hits,
            $record.put_hits,
            $record.ea9e4000_hits,
            $record.ea4f0b80_hits,
            $record.exact_a1c000_hits,
            $record.other_ea_hits,
            $record.last_family,
            $record.last_pc,
            $record.last_cmd,
            $record.last_tag,
            $record.last_size,
            $record.last_lsa,
            $record.last_eal,
            (Format-ProbeBytes $record.bytes),
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add('SPU HLE 0x25cc family reading: this is a verify-only recognizer for the title/image/PC gated 16 KB runtime MFC family around EA `0x9e4000`. It keeps stock MFC behavior, does not skip or offload work, and exists to size whether the broader 0x25cc family is worth an HLE/codegen body after clean field/menu/battle proof.') | Out-Null
}

if ($spuHle451cListSeedRecords.Count -gt 0) {
    $spuHle451cListSeedRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,success,fail,seed1_hits,seed2_hits,desc_bytes,total_us,max_total_us,last_seed,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,cause,status |
        Export-Csv -LiteralPath $SpuHle451cListSeedCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE 0x451c list-seed CSV: $SpuHle451cListSeedCsvPath") | Out-Null
}
if ($spuHle451cListFamilyRecords.Count -gt 0) {
    $spuHle451cListFamilyRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,success,fail,tag1_size8_hits,tag0_size8_hits,tag0_size16_hits,tag1_size16_hits,tag1_size24_hits,tag0_size24_hits,desc_bytes,total_us,max_total_us,last_family,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,cause,status |
        Export-Csv -LiteralPath $SpuHle451cListFamilyCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE 0x451c list-family CSV: $SpuHle451cListFamilyCsvPath") | Out-Null
}
if ($spuHle451cDescBatchRecords.Count -gt 0) {
    $spuHle451cDescBatchRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,calls,desc_bytes,fetch_groups,fast_groups,fast_desc,slow_desc,nonzero_desc,zero_desc,stall_desc,inline_get_desc,inline_put_desc,dma_desc,shadow_groups,shadow_single_groups,shadow_multi_groups,shadow_full_groups,shadow_partial_groups,shadow_desc,shadow_bytes,shadow_uniform_size_groups,shadow_mixed_size_groups,shadow_zero_rejects,shadow_stall_rejects,shadow_raw_rejects,shadow_max_desc,shadow_max_bytes,shadow_last_desc,shadow_last_bytes,shadow_last_first_ea,shadow_last_last_ea,preserve_groups,preserve_single_groups,preserve_multi_groups,preserve_full_groups,preserve_partial_groups,preserve_desc,preserve_bytes,preserve_zero_stops,preserve_stall_stops,preserve_raw_stops,preserve_max_desc,preserve_max_bytes,preserve_last_desc,preserve_last_bytes,preserve_last_first_ea,preserve_last_last_ea,preserve_family1_groups,preserve_family1_desc,preserve_family1_bytes,preserve_family2_groups,preserve_family2_desc,preserve_family2_bytes,preserve_family3_groups,preserve_family3_desc,preserve_family3_bytes,preserve_family4_groups,preserve_family4_desc,preserve_family4_bytes,preserve_family5_groups,preserve_family5_desc,preserve_family5_bytes,preserve_family6_groups,preserve_family6_desc,preserve_family6_bytes,size16_candidate_groups,size16_candidate_desc,size16_candidate_bytes,size16_candidate_family3_groups,size16_candidate_family3_desc,size16_candidate_family3_bytes,size16_candidate_family4_groups,size16_candidate_family4_desc,size16_candidate_family4_bytes,size16_body_groups,size16_body_desc,size16_body_bytes,size16_body_family3_groups,size16_body_family3_desc,size16_body_family3_bytes,size16_body_family4_groups,size16_body_family4_desc,size16_body_family4_bytes,size16_reject_groups,size16_reject_single_groups,size16_reject_partial_groups,size16_reject_stop_groups,size16_last_family,size16_last_desc,size16_last_bytes,size16_last_first_ea,size16_last_last_ea,family1_calls,family2_calls,family3_calls,family4_calls,family5_calls,family6_calls,last_family,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,last_desc_ts,last_desc_ea,cause,status |
        Export-Csv -LiteralPath $SpuHle451cDescBatchCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE 0x451c descriptor-batch CSV: $SpuHle451cDescBatchCsvPath") | Out-Null
}
if ($spuHle451cPreserveBodyRecords.Count -gt 0) {
    $spuHle451cPreserveBodyRecords |
        Select-Object mode,hle_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,groups,desc,bytes,last_family,last_desc,last_bytes,last_first_ea,last_last_ea,cause,status |
        Export-Csv -LiteralPath $SpuHle451cPreserveBodyCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- SPU HLE 0x451c preserve-body CSV: $SpuHle451cPreserveBodyCsvPath") | Out-Null
}
if ($mfcDynamicRecords.Count -gt 0) {
    $mfcDynamicRecords |
        Select-Object mode,ladder_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,success,fail,bytes,total_us,max_total_us,pc25_hits,pc25_us,pc451c_hits,pc451c_us,pc0a70_hits,pc0a70_us,get_hits,put_hits,list_hits,atomic_hits,other_hits,last_pc,last_cmd,last_lsa,last_eal,last_size,last_tag,cause,status |
        Export-Csv -LiteralPath $MfcDynamicCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC dynamic CSV: $MfcDynamicCsvPath") | Out-Null
}
if ($mfcListRecords.Count -gt 0) {
    $mfcListRecords |
        Select-Object mode,ladder_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,calls,success,fail,desc_bytes,total_us,max_total_us,pc451c_hits,pc451c_us,pc0a70_hits,pc0a70_us,other_hits,other_us,get_calls,put_calls,last_pc,last_cmd,last_lsa,last_eal,last_size,last_tag,cause,status |
        Export-Csv -LiteralPath $MfcListCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC list transfer CSV: $MfcListCsvPath") | Out-Null
}
if ($mfcWaitRecords.Count -gt 0) {
    $mfcWaitRecords |
        Select-Object mode,ladder_mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,reads,fast_reads,blocking_reads,tagstat_reads,atomic_reads,total_us,max_total_us,pc2598_hits,pc2598_us,pc2600_hits,pc2600_us,pc25_hits,pc25_us,pc0b44_hits,pc0b44_us,pc29e4_hits,pc29e4_us,pc451c_hits,pc451c_us,other_hits,other_us,last_pc,last_ch,last_value,cause,status |
        Export-Csv -LiteralPath $MfcWaitCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC wait CSV: $MfcWaitCsvPath") | Out-Null
}
if ($mfcWaitPcRecords.Count -gt 0) {
    $mfcWaitPcRecords |
        Select-Object mode,ladder_mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,pc,reads,tagstat_reads,atomic_reads,overflow_reads,last_pc,last_ch,cause,status |
        Sort-Object -Property reads -Descending |
        Export-Csv -LiteralPath $MfcWaitPcCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC wait exact-PC CSV: $MfcWaitPcCsvPath") | Out-Null
}
if ($reservationLoopCmdRecords.Count -gt 0) {
    $reservationLoopCmdRecords |
        Select-Object mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,cmd_hits,getllar_cmds,putllc_cmds,putlluc_cmds,putqlluc_cmds,atomic_updates,getllar_success,putllc_success,putllc_failure,putlluc_success,atomic_other,pc_overflow,last_pc,last_cmd,last_lsa,last_eal,last_size,last_tag,last_atomic,last_raddr,last_rtime,last_events,cause,status |
        Export-Csv -LiteralPath $ReservationLoopCmdCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Reservation loop command CSV: $ReservationLoopCmdCsvPath") | Out-Null
}
if ($reservationLoopCmdPcRecords.Count -gt 0) {
    $reservationLoopCmdPcRecords |
        Select-Object mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,pc,cmd_hits,getllar_cmds,putllc_cmds,putlluc_cmds,putqlluc_cmds,atomic_updates,getllar_success,putllc_success,putllc_failure,putlluc_success,atomic_other,overflow,cause,status |
        Sort-Object -Property cmd_hits -Descending |
        Export-Csv -LiteralPath $ReservationLoopCmdPcCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Reservation loop command exact-PC CSV: $ReservationLoopCmdPcCsvPath") | Out-Null
}
if ($reservationLoopVerifyRecords.Count -gt 0) {
    $reservationLoopVerifyRecords |
        Select-Object scope,mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,attempts,getllar_cmds,getllar_success,putllc_cmds,getllar_updates,putllc_updates,update_linked,update_unlinked,atomic_reads,read_getllar,read_putllc,read_success,read_failure,read_unexpected,read_fast,read_blocking,completed,success,failure,unexpected,raddr_match,rtime_match,main_line_readable,main_line_match,dirty_zero,dirty_one_or_two,dirty_multi,post_raddr_zero,post_raddr_same,post_lr_event_set,retry_branches,retry_taken,retry_fallthrough,next_branches,next_taken,next_fallthrough,state,lane,last_cmd_pc,last_atomic_pc,last_read_pc,last_raw_cmd_pc,last_raw_atomic_pc,last_raw_read_pc,last_retry_pc,last_next_branch_pc,last_lsa,last_eal,last_changed_mask,last_atomic,last_read_atomic,last_raddr,last_rtime,last_events,last_branch_pc,last_branch_target,last_branch_taken,cause,status |
        Export-Csv -LiteralPath $ReservationLoopVerifyCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Reservation loop verify CSV: $ReservationLoopVerifyCsvPath") | Out-Null
}
if ($reservationLoopRdchJoinRows.Count -gt 0) {
    $reservationLoopRdchJoinRows |
        Select-Object mode,reservation_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,getllar_cmd_pc,getllar_read_pc,getllar_attempts,getllar_updates,getllar_exact_reads,getllar_read_minus_attempts,getllar_read_coverage,putllc_cmd_pc,putllc_read_pc,putllc_completed,putllc_updates,putllc_exact_reads,putllc_read_minus_completed,putllc_read_coverage,update_linked,update_unlinked,in_hook_atomic_reads,exact_atomic_reads,exact_minus_in_hook_reads,unexpected,dirty_multi,lane,last_cmd_pc,last_atomic_pc,last_read_pc,last_raw_cmd_pc,last_raw_atomic_pc,last_raw_read_pc,last_retry_pc,last_next_branch_pc,cause,status |
        Export-Csv -LiteralPath $ReservationLoopRdchJoinCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Reservation loop RDCH join CSV: $ReservationLoopRdchJoinCsvPath") | Out-Null
}
if ($reservationLoopLaneJoinRows.Count -gt 0) {
    $reservationLoopLaneJoinRows |
        Select-Object lane,getllar_focus_cmd_pc,getllar_raw_cmd_pc,getllar_cmd_peak_pc,getllar_cmd_hits,getllar_focus_read_pc,getllar_raw_read_pc,getllar_read_peak_pc,getllar_read_hits,putllc_focus_cmd_pc,putllc_raw_cmd_pc,putllc_cmd_peak_pc,putllc_cmd_hits,putllc_focus_read_pc,putllc_raw_read_pc,putllc_read_peak_pc,putllc_read_hits,retry_pc,next_branch_pc,raw_lane_cmd_hits,raw_lane_read_hits,verify_row_count,verify_attempts,verify_completed,verify_success,verify_failure,verify_unexpected,verify_retry_branches,verify_retry_taken,verify_retry_fallthrough,verify_next_branches,verify_next_taken,verify_next_fallthrough,exact_group_name,exact_spu_name,raw_group_name,raw_spu_name,classification,cause,status |
        Export-Csv -LiteralPath $ReservationLoopLaneJoinCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Reservation loop lane-join CSV: $ReservationLoopLaneJoinCsvPath") | Out-Null
}
if ($reservationLoopRawLaneRows.Count -gt 0) {
    $reservationLoopRawLaneRows |
        Select-Object title,entry,image_sig,group_name,spu_name,raw_getllar_cmd_pc,raw_getllar_read_pc,raw_putllc_cmd_pc,raw_putllc_read_pc,raw_retry_branch_pc,raw_retry_branch,raw_next_branch_pc,raw_next_branch,getllar_cmd_hits,putllc_cmd_hits,getllar_read_hits,putllc_read_hits,source_focus_pcs,source_file_count,source_files,classification,cause,status |
        Export-Csv -LiteralPath $ReservationLoopRawLaneCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Reservation loop raw-lane CSV: $ReservationLoopRawLaneCsvPath") | Out-Null
}
if ($putllc16Records.Count -gt 0) {
    $putllc16Records |
        Select-Object kind,elapsed,worker,entry_pc,function_sig,function_pc,pattern_hash,mem_count,put_pc,pc_rel,offset,pair_offset0,pair_offset1,write_mask,access_mask,no_notify,is_const,two_regs,reg,runtime,putllc0_count,putllc16_count,all_count,break_pc,mem,lsa_const,cause,cause_reason,lsa_pc |
        Export-Csv -LiteralPath $Putllc16CsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- PUTLLC16 analyzer CSV: $Putllc16CsvPath") | Out-Null
}
if ($putllc16RuntimeRecords.Count -gt 0) {
    $putllc16RuntimeRecords |
        Select-Object mode,ladder_mode,putllc16_res,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,success,fail,pc0ad4_hits,pc0ad4_success,pc0c24_hits,pc0c24_success,other_hits,other_success,last_pc,last_eal,last_lsa,last_dest,cause,status |
        Export-Csv -LiteralPath $Putllc16RuntimeCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- PUTLLC16 runtime CSV: $Putllc16RuntimeCsvPath") | Out-Null
}
if ($putllc16PairVerifyRecords.Count -gt 0) {
    $putllc16PairVerifyRecords |
        Select-Object mode,pair_mode,putllc16_res,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,hits,in_range,raddr_match,rtime_match,main_line_readable,main_line_match,changed,no_extra_dirty,extra_dirty,decoded_mask_match,pattern_mask_match,post_hits,post_atomic_ready,post_success,post_failure,post_atomic_other,post_raddr_zero,post_raddr_same,post_lr_event_set,last_pc,last_eal,last_lsa,last_dest0,last_dest1,last_changed_mask,last_expected_mask,last_decoded_mask,last_pattern_mask,last_post_atomic,last_post_raddr,last_post_events,last_notify,cause,status |
        Export-Csv -LiteralPath $Putllc16PairVerifyCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- PUTLLC16 pair verify CSV: $Putllc16PairVerifyCsvPath") | Out-Null
}
if ($kernelCapsuleRecords.Count -gt 0) {
    $kernelCapsuleRecords |
        Select-Object mode,capsule_mode,title,ppu,ppu_name,group,group_name,spu,spu_index,spu_name,entry,image_sig,pattern_sig,duration_us,class,records,total_bytes,get_bytes,put_bytes,list_bytes,rsx_bytes,cmd_count,list_cmd_count,dynamic_hits,dynamic_bytes,list_calls,list_desc_bytes,wait_reads,tagstat_reads,atomic_reads,putllc16_hits,max_dma_size,max_dma_pc,max_dma_ea,last_pc,last_cmd,reservation_risk,tiny_dispatch_trap,rsx_consumed,gpu_batch_candidate,cpu_simd_first,sync_only,cause,status |
        Export-Csv -LiteralPath $KernelCapsuleCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Kernel capsule CSV: $KernelCapsuleCsvPath") | Out-Null
}

$rsxResourceGroups = @(
    $rsxResourceRecords |
        Group-Object -Property kind, role, base, end, format, key |
        ForEach-Object {
            $first = $_.Group[0]
            [pscustomobject]@{
                kind        = $first.kind
                role        = $first.role
                base        = $first.base
                end         = $first.end
                base_value  = $first.base_value
                end_value   = $first.end_value
                bytes       = $first.bytes
                pitch       = $first.pitch
                height      = $first.height
                count       = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                format      = $first.format
                key         = $first.key
                description = $first.description
            }
        }
)

$dmaRanges = New-Object System.Collections.Generic.List[object]
foreach ($record in $records) {
    $range = New-ProbeDmaRange -SourceType "max-dma" -Record $record -Start (Convert-ProbeNumber $record.max_dma_ea) -Bytes $record.max_dma_size
    if ($null -ne $range) {
        $dmaRanges.Add($range) | Out-Null
    }
}

foreach ($shape in $mfcShapeRecords) {
    $range = New-ProbeMfcShapeRange $shape
    if ($null -ne $range) {
        $dmaRanges.Add($range) | Out-Null
    }
}

$rsxOverlapRecords = New-Object System.Collections.Generic.List[object]
foreach ($range in $dmaRanges) {
    foreach ($resource in $rsxResourceGroups) {
        $overlap = Get-ProbeRangeOverlapBytes $range.start_value $range.end_value $resource.base_value $resource.end_value
        if ($overlap -gt 0) {
            $rsxOverlapRecords.Add([pscustomobject]@{
                source_type          = $range.source_type
                pc                   = $range.pc
                group_name           = $range.group_name
                spu_name             = $range.spu_name
                image_sig            = $range.image_sig
                pattern_sig          = $range.pattern_sig
                dma_start            = $range.start
                dma_end              = $range.end
                dma_bytes            = $range.bytes
                resource_kind        = $resource.kind
                resource_role        = $resource.role
                resource_base        = $resource.base
                resource_end         = $resource.end
                resource_bytes       = $resource.bytes
                resource_count       = $resource.count
                resource_format      = $resource.format
                resource_key         = $resource.key
                overlap_bytes        = $overlap
                overlap_bytes_pretty = Format-ProbeBytes $overlap
                resource_description = $resource.description
            }) | Out-Null
        }
    }
}

if ($rsxOverlapRecords.Count -gt 0) {
    $rsxOverlapRecords |
        Sort-Object -Property overlap_bytes, resource_count -Descending |
        Export-Csv -LiteralPath $RsxOverlapCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- RSX resource overlap CSV: $RsxOverlapCsvPath") | Out-Null
}

$totalBytes = [UInt64](($records | Measure-Object -Property total_bytes -Sum).Sum)
$maxRecord = $records | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
$rsxRecords = @($records | Where-Object { $_.rsx_get_bytes -gt 0 -or $_.rsx_put_bytes -gt 0 })
$rsxLocalBytes = [UInt64](($rsxRecords | ForEach-Object { $_.rsx_get_bytes + $_.rsx_put_bytes } | Measure-Object -Sum).Sum)
$lines.Add("- Total observed DMA bytes: $(Format-ProbeBytes $totalBytes)") | Out-Null
$lines.Add(('- Largest single job: {0} in `{1}` / `{2}`' -f (Format-ProbeBytes $maxRecord.total_bytes), $maxRecord.group_name, $maxRecord.spu_name)) | Out-Null
$lines.Add("- RSX-local traffic records: $($rsxRecords.Count)") | Out-Null
$lines.Add("- RSX resource profile records: $($rsxResourceRecords.Count) raw, $($rsxResourceGroups.Count) aggregated") | Out-Null
$lines.Add("- Indirect RSX resource overlap records: $($rsxOverlapRecords.Count)") | Out-Null
$fitGroups = @($records | Group-Object -Property offload_fit | Sort-Object -Property Count -Descending)
$lines.Add("- Offload fit mix: $(@($fitGroups | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')") | Out-Null

$lines.Add("") | Out-Null
$lines.Add("## Top Candidates By DMA Bytes") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Fit | Dispatch | Group | SPU | Image | Pattern | Total | GET | PUT | List GET | List PUT | RSX GET | RSX PUT | Cmds | List Cmds | Max DMA | PC | Block | EA |") | Out-Null
$lines.Add("| ---: | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

$rank = 1
foreach ($record in @($records | Sort-Object -Property total_bytes -Descending | Select-Object -First $Top)) {
    $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | `{4}` | `{5}` | `{6}` | {7} | {8} | {9} | {10} | {11} | {12} | {13} | {14} | {15} | {16} | `{17}` | `{18}` | `{19}` |' -f $rank, $record.offload_fit, $record.dispatch_risk, $record.group_name, $record.spu_name, $record.image_sig, $record.pattern_sig, (Format-ProbeBytes $record.total_bytes), (Format-ProbeBytes $record.get_bytes), (Format-ProbeBytes $record.put_bytes), (Format-ProbeBytes $record.list_get_bytes), (Format-ProbeBytes $record.list_put_bytes), (Format-ProbeBytes $record.rsx_get_bytes), (Format-ProbeBytes $record.rsx_put_bytes), $record.cmd_count, $record.list_cmd_count, (Format-ProbeBytes $record.max_dma_size), $record.max_dma_pc, $record.max_dma_block_hash, $record.max_dma_ea)) | Out-Null
    $rank++
}

$lines.Add("") | Out-Null
$lines.Add("## Offload Fit Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Fit | Records | Sum Total | Reading |") | Out-Null
$lines.Add("| --- | ---: | ---: | --- |") | Out-Null

foreach ($fitGroup in $fitGroups) {
    $fitRecords = @($fitGroup.Group)
    $fitSum = [UInt64](($fitRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $sample = $fitRecords | Select-Object -First 1
    $lines.Add(('| `{0}` | {1} | {2} | {3} |' -f $fitGroup.Name, $fitGroup.Count, (Format-ProbeBytes $fitSum), $sample.reading)) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## GPU Port Scoreboard") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Bucket | Records | Bytes | Share Of Observed DMA | Status |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | --- |") | Out-Null
$lines.Add(('| New promoted CPU/SPU -> GPU replacement | 0 | {0} | {1} | none; no Windows field/menu/battle 200% proof yet |' -f (Format-ProbeBytes 0), (Format-ProbePercent 0 $totalBytes))) | Out-Null
$lines.Add(('| Direct RSX-local scout traffic | {0} | {1} | {2} | candidate evidence only, not a replacement path |' -f $rsxRecords.Count, (Format-ProbeBytes $rsxLocalBytes), (Format-ProbePercent $rsxLocalBytes $totalBytes))) | Out-Null
$lines.Add(('| Indirect SPU-DMA/RSX-resource overlap | {0} | {1} | {2} | promote only after verify-clean output and no critical readback |' -f $rsxOverlapRecords.Count, (Format-ProbeBytes ([UInt64](($rsxOverlapRecords | Measure-Object -Property overlap_bytes -Sum).Sum))), (Format-ProbePercent ([UInt64](($rsxOverlapRecords | Measure-Object -Property overlap_bytes -Sum).Sum)) $totalBytes))) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Scoreboard reading: the stock Vulkan renderer already runs PS3 RSX graphics on the GPU, so this table counts only new project work that moves CPU/SPU-side load or a verified RSX-local superpath. A row stays `candidate evidence` until it survives correctness and speed gates.") | Out-Null

if ($kernelCapsuleRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Kernel Capsule Classifier") | Out-Null
    $lines.Add("") | Out-Null

    $capsuleTotalRecords = [UInt64](($kernelCapsuleRecords | Measure-Object -Property records -Sum).Sum)
    $capsuleTotalBytes = [UInt64](($kernelCapsuleRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $capsuleRsxBytes = [UInt64](($kernelCapsuleRecords | Measure-Object -Property rsx_bytes -Sum).Sum)
    $capsuleWaitReads = [UInt64](($kernelCapsuleRecords | Measure-Object -Property wait_reads -Sum).Sum)
    $capsuleAtomicReads = [UInt64](($kernelCapsuleRecords | Measure-Object -Property atomic_reads -Sum).Sum)
    $capsuleGpuBatch = [UInt64](($kernelCapsuleRecords | Measure-Object -Property gpu_batch_candidate -Sum).Sum)
    $capsuleCpuSimd = [UInt64](($kernelCapsuleRecords | Measure-Object -Property cpu_simd_first -Sum).Sum)

    $lines.Add("- Capsule records observed: $capsuleTotalRecords") | Out-Null
    $lines.Add("- Capsule DMA bytes: $(Format-ProbeBytes $capsuleTotalBytes)") | Out-Null
    $lines.Add("- RSX-local bytes inside capsules: $(Format-ProbeBytes $capsuleRsxBytes)") | Out-Null
    $lines.Add("- Wait/atomic reads: $capsuleWaitReads / $capsuleAtomicReads") | Out-Null
    $lines.Add("- GPU-batch candidates / CPU-SIMD-first records: $capsuleGpuBatch / $capsuleCpuSimd") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Class | Rows | Capsule Records | Bytes | RSX Bytes | Wait Reads | Atomic Reads | Top PC | Reading |") | Out-Null
    $lines.Add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |") | Out-Null

    foreach ($classGroup in @($kernelCapsuleRecords | Group-Object -Property class | Sort-Object -Property Count -Descending)) {
        $classRecords = @($classGroup.Group)
        $classCapsules = [UInt64](($classRecords | Measure-Object -Property records -Sum).Sum)
        $classBytes = [UInt64](($classRecords | Measure-Object -Property total_bytes -Sum).Sum)
        $classRsx = [UInt64](($classRecords | Measure-Object -Property rsx_bytes -Sum).Sum)
        $classWait = [UInt64](($classRecords | Measure-Object -Property wait_reads -Sum).Sum)
        $classAtomic = [UInt64](($classRecords | Measure-Object -Property atomic_reads -Sum).Sum)
        $capsuleTopRecord = $classRecords | Sort-Object -Property total_bytes, records -Descending | Select-Object -First 1
        $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} | `{7}` | {8} |' -f
            $classGroup.Name,
            $classGroup.Count,
            $classCapsules,
            (Format-ProbeBytes $classBytes),
            (Format-ProbeBytes $classRsx),
            $classWait,
            $classAtomic,
            $capsuleTopRecord.max_dma_pc,
            (Get-KernelCapsuleReading $classGroup.Name))) | Out-Null
    }

    $lines.Add("") | Out-Null
    $lines.Add("Kernel capsule reading: this is migration scouting, not a speed win. Promote only a stable `gpu-batch-candidate` or RSX-consumed capsule into a CPU-vs-GPU shadow verifier; leave reservation, sync-only, and tiny-dispatch classes on CPU/HLE paths.") | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Group Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Group | Records | Max Total | Sum Total | Max List GET | Max List PUT | Max RSX GET | Max RSX PUT | Top SPU | Top Image | Top PC |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

foreach ($group in @($records | Group-Object -Property group_name | Sort-Object -Property Count -Descending)) {
    $groupRecords = @($group.Group)
    $topRecord = $groupRecords | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
    $sum = [UInt64](($groupRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $maxListGet = [UInt64](($groupRecords | Measure-Object -Property list_get_bytes -Maximum).Maximum)
    $maxListPut = [UInt64](($groupRecords | Measure-Object -Property list_put_bytes -Maximum).Maximum)
    $maxRsxGet = [UInt64](($groupRecords | Measure-Object -Property rsx_get_bytes -Maximum).Maximum)
    $maxRsxPut = [UInt64](($groupRecords | Measure-Object -Property rsx_put_bytes -Maximum).Maximum)
    $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} | {7} | `{8}` | `{9}` | `{10}` |' -f $group.Name, $group.Count, (Format-ProbeBytes $topRecord.total_bytes), (Format-ProbeBytes $sum), (Format-ProbeBytes $maxListGet), (Format-ProbeBytes $maxListPut), (Format-ProbeBytes $maxRsxGet), (Format-ProbeBytes $maxRsxPut), $topRecord.spu_name, $topRecord.image_sig, $topRecord.max_dma_pc)) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Hot PC Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| PC | Records | Sum Total | Max Total | Max DMA | Top Group | Top SPU | Top EA |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

foreach ($pcGroup in @($records | Group-Object -Property max_dma_pc | Sort-Object -Property Count -Descending | Select-Object -First $Top)) {
    $pcRecords = @($pcGroup.Group)
    $pcTop = $pcRecords | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
    $pcSum = [UInt64](($pcRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $pcMaxDma = [UInt64](($pcRecords | Measure-Object -Property max_dma_size -Maximum).Maximum)
    $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | `{5}` | `{6}` | `{7}` |' -f $pcGroup.Name, $pcGroup.Count, (Format-ProbeBytes $pcSum), (Format-ProbeBytes $pcTop.total_bytes), (Format-ProbeBytes $pcMaxDma), $pcTop.group_name, $pcTop.spu_name, $pcTop.max_dma_ea)) | Out-Null
}

if ($mfcShapeRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## MFC Shape Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | PC | Cmd | Flags | Count | Bytes | Size | Tag | LSA | EAL Range | First -> Last EAL | Group | SPU | Image | Block | Overflow |") | Out-Null
    $lines.Add("| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | ---: |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcShapeRecords | Sort-Object -Property count, bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | {4} | {5} | {6} | {7} | `{8}` | `{9}`-`{10}` | `{11}` -> `{12}` | `{13}` | `{14}` | `{15}` | `{16}` | {17} |' -f
            $rank,
            $record.pc,
            $record.cmd,
            (Format-MfcShapeFlags $record.flags),
            $record.count,
            (Format-ProbeBytes $record.bytes),
            $record.size,
            $record.tag,
            $record.lsa,
            $record.eal_min,
            $record.eal_max,
            $record.eal_first,
            $record.eal_last,
            $record.group_name,
            $record.spu_name,
            $record.image_sig,
            $record.block_hash,
            $record.overflow)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("MFC shape reading: high counts with a small command/size/tag/LSA set are a codegen/HLE candidate; many one-off rows or large overflow means the path is still too dynamic for a fast path.") | Out-Null
}

if ($mfcLadderRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## MFC 0x25cc Ladder Gate") | Out-Null
    $lines.Add("") | Out-Null

    $ladderEligible = [UInt64](($mfcLadderRecords | Measure-Object -Property eligible -Sum).Sum)
    $ladderVerify = [UInt64](($mfcLadderRecords | Measure-Object -Property verify_hits -Sum).Sum)
    $ladderFast = [UInt64](($mfcLadderRecords | Measure-Object -Property fast_hits -Sum).Sum)
    $ladderBlocked = [UInt64](($mfcLadderRecords | Measure-Object -Property blocked -Sum).Sum)
    $ladderMismatches = [UInt64](($mfcLadderRecords | Measure-Object -Property mismatches -Sum).Sum)
    $ladderBytes = [UInt64](($mfcLadderRecords | Measure-Object -Property bytes -Sum).Sum)
    $ladderCheckUs = [UInt64](($mfcLadderRecords | Measure-Object -Property check_us -Sum).Sum)
    $ladderTransferUs = [UInt64](($mfcLadderRecords | Measure-Object -Property transfer_us -Sum).Sum)
    $ladderTotalUs = [UInt64](($mfcLadderRecords | Measure-Object -Property total_us -Sum).Sum)
    $ladderMaxCheckUs = [UInt64](($mfcLadderRecords | Measure-Object -Property max_check_us -Maximum).Maximum)
    $ladderMaxTransferUs = [UInt64](($mfcLadderRecords | Measure-Object -Property max_transfer_us -Maximum).Maximum)
    $ladderMaxTotalUs = [UInt64](($mfcLadderRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $ladderTimedHits = [UInt64]([Math]::Max(1, [double]($ladderEligible)))
    $ladderAvgTotalUs = [double]$ladderTotalUs / [double]$ladderTimedHits
    $ladderAvgCheckUs = [double]$ladderCheckUs / [double]$ladderTimedHits
    $ladderAvgTransferUs = [double]$ladderTransferUs / [double]$ladderTimedHits

    $lines.Add("- Eligible hits: $ladderEligible") | Out-Null
    $lines.Add("- Verify hits: $ladderVerify") | Out-Null
    $lines.Add("- Fast hits: $ladderFast") | Out-Null
    $lines.Add("- Blocked by generic MFC ordering: $ladderBlocked") | Out-Null
    $lines.Add("- Ordering mismatches: $ladderMismatches") | Out-Null
    $lines.Add("- Ladder bytes: $(Format-ProbeBytes $ladderBytes)") | Out-Null
    $lines.Add(("- Timing: check={0:n3} ms, transfer={1:n3} ms, total={2:n3} ms" -f ($ladderCheckUs / 1000.0), ($ladderTransferUs / 1000.0), ($ladderTotalUs / 1000.0))) | Out-Null
    $lines.Add(("- Avg per eligible hit: check={0:n3} us, transfer={1:n3} us, total={2:n3} us" -f $ladderAvgCheckUs, $ladderAvgTransferUs, $ladderAvgTotalUs)) | Out-Null
    $lines.Add("- Max single hit: check=$ladderMaxCheckUs us, transfer=$ladderMaxTransferUs us, total=$ladderMaxTotalUs us") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Mode | PC | Eligible | Verify | Fast | Blocked | Mismatches | Bytes | Check ms | Transfer ms | Total ms | Max total us | Last LSA | EAL Range | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcLadderRecords | Sort-Object -Property eligible, bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | {3} | {4} | {5} | {6} | {7} | {8} | {9:n3} | {10:n3} | {11:n3} | {12} | `{13}` | `{14}`-`{15}` | `{16}` | `{17}` | `{18}` |' -f
            $rank,
            $record.ladder_mode,
            $record.pc,
            $record.eligible,
            $record.verify_hits,
            $record.fast_hits,
            $record.blocked,
            $record.mismatches,
            (Format-ProbeBytes $record.bytes),
            ($record.check_us / 1000.0),
            ($record.transfer_us / 1000.0),
            ($record.total_us / 1000.0),
            $record.max_total_us,
            $record.last_lsa,
            $record.eal_min,
            $record.eal_max,
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("MFC ladder reading: verify mode should show eligible hits with zero ordering mismatches before fast mode is trusted. If check/total timing dominates, dynamic-MFC codegen or HLE batching is the sharper CPU-offload target; if transfer timing dominates, this ladder is mostly memory copy and does not become a GPU win unless the consuming SPU work also moves.") | Out-Null
}

if ($spuHleVerifyRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $hleHits = [UInt64](($spuHleVerifyRecords | Measure-Object -Property hits -Sum).Sum)
    $hleRuntimeHits = [UInt64](($spuHleVerifyRecords | Measure-Object -Property runtime_hits -Sum).Sum)
    $hleLlvmHits = [UInt64](($spuHleVerifyRecords | Measure-Object -Property llvm_hits -Sum).Sum)
    $hleBytes = [UInt64](($spuHleVerifyRecords | Measure-Object -Property bytes -Sum).Sum)

    $lines.Add("- Hits: $hleHits") | Out-Null
    $lines.Add("- Runtime hits: $hleRuntimeHits") | Out-Null
    $lines.Add("- LLVM direct-copy hits: $hleLlvmHits") | Out-Null
    $lines.Add("- Candidate bytes: $(Format-ProbeBytes $hleBytes)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Mode | Hits | Runtime | LLVM | Bytes | PC25 | PC451c | Last Path | Last PC | Last Cmd | Last Tag | Last Size | Last LSA | Last EAL | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHleVerifyRecords | Sort-Object -Property hits, bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} | {8} | `{9}` | `{10}` | {11} | {12} | `{13}` | `{14}` | `{15}` | `{16}` | `{17}` |' -f
            $rank,
            $record.hle_mode,
            $record.hits,
            $record.runtime_hits,
            $record.llvm_hits,
            (Format-ProbeBytes $record.bytes),
            $record.pc25_hits,
            $record.pc451c_hits,
            $record.last_path,
            $record.last_pc,
            $record.last_cmd,
            $record.last_tag,
            $record.last_size,
            $record.last_lsa,
            $record.last_eal,
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $shapeSummaries = $spuHleVerifyRecords |
        Group-Object -Property last_path,last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,group_name,spu_name,image_sig |
        ForEach-Object {
            $first = $_.Group[0]
            [pscustomobject]@{
                records      = $_.Count
                hits         = [UInt64](($_.Group | Measure-Object -Property hits -Sum).Sum)
                runtime_hits = [UInt64](($_.Group | Measure-Object -Property runtime_hits -Sum).Sum)
                llvm_hits    = [UInt64](($_.Group | Measure-Object -Property llvm_hits -Sum).Sum)
                bytes        = [UInt64](($_.Group | Measure-Object -Property bytes -Sum).Sum)
                last_path    = $first.last_path
                last_pc      = $first.last_pc
                last_cmd     = $first.last_cmd
                last_tag     = $first.last_tag
                last_size    = $first.last_size
                last_lsa     = $first.last_lsa
                last_eal     = $first.last_eal
                group_name   = $first.group_name
                spu_name     = $first.spu_name
                image_sig    = $first.image_sig
            }
        } |
        Sort-Object -Property hits, bytes -Descending |
        Select-Object -First $Top

    if ($shapeSummaries.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("### SPU HLE Shape Summary") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | Records | Hits | Runtime | LLVM | Bytes | Path | PC | Cmd | Tag | Size | LSA | EAL | Group | SPU | Image |") | Out-Null
        $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | --- | --- | --- |") | Out-Null

        $rank = 1
        foreach ($shape in @($shapeSummaries)) {
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | `{7}` | `{8}` | {9} | {10} | `{11}` | `{12}` | `{13}` | `{14}` | `{15}` |' -f
                $rank,
                $shape.records,
                $shape.hits,
                $shape.runtime_hits,
                $shape.llvm_hits,
                (Format-ProbeBytes $shape.bytes),
                $shape.last_path,
                $shape.last_pc,
                $shape.last_cmd,
                $shape.last_tag,
                $shape.last_size,
                $shape.last_lsa,
                $shape.last_eal,
                $shape.group_name,
                $shape.spu_name,
                $shape.image_sig)) | Out-Null
            $rank++
        }
    }

    if ($spuHleNonConstantWarnings.Count -gt 0) {
        $warningSummaries = $spuHleNonConstantWarnings |
            Group-Object -Property pc,reg |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    pc         = $first.pc
                    reg        = $first.reg
                    count      = $_.Count
                    first_line = [int](($_.Group | Measure-Object -Property line_number -Minimum).Minimum)
                }
            } |
            Sort-Object -Property count -Descending |
            Select-Object -First $Top

        $lines.Add("") | Out-Null
        $lines.Add("### SPU HLE Compiler Fallback Hints") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | PC | Cmd Register | Warnings | First Log Line |") | Out-Null
        $lines.Add("| ---: | --- | ---: | ---: | ---: |") | Out-Null

        $rank = 1
        foreach ($warning in @($warningSummaries)) {
            $lines.Add(('| {0} | `{1}` | ${2} | {3} | {4} |' -f
                $rank,
                $warning.pc,
                $warning.reg,
                $warning.count,
                $warning.first_line)) | Out-Null
            $rank++
        }

        $hasPc25DynamicCmd = $null -ne ($warningSummaries | Where-Object { $_.pc -eq "0x25cc" } | Select-Object -First 1)
        if (($hleLlvmHits -eq 0) -and $hasPc25DynamicCmd) {
            $lines.Add("") | Out-Null
            $lines.Add('Compiler fallback reading: LLVM direct-copy stayed quiet because this route''s observed `0x25cc` MFC command is dynamic. Chase runtime/dynamic-command HLE or shadow verification before a direct-copy fast path.') | Out-Null
        }
    }

    $lines.Add("") | Out-Null
    $lines.Add("SPU HLE verifier reading: this is a verify-only visibility counter for the 0x25cc HLE/codegen target. It is not a speed win, not GPU migration credit, and has no fast path yet.") | Out-Null
}

if ($spuHleShadowRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE Shadow Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $shadowHits = [UInt64](($spuHleShadowRecords | Measure-Object -Property hits -Sum).Sum)
    $shadowBytes = [UInt64](($spuHleShadowRecords | Measure-Object -Property bytes -Sum).Sum)
    $shadowMatch = [UInt64](($spuHleShadowRecords | Measure-Object -Property output_match -Sum).Sum)
    $shadowMismatch = [UInt64](($spuHleShadowRecords | Measure-Object -Property output_mismatch -Sum).Sum)
    $shadowDstChanged = [UInt64](($spuHleShadowRecords | Measure-Object -Property dst_changed -Sum).Sum)
    $shadowDstUnchanged = [UInt64](($spuHleShadowRecords | Measure-Object -Property dst_unchanged -Sum).Sum)
    $shadowSrcRepeats = [UInt64](($spuHleShadowRecords | Measure-Object -Property src_repeats -Sum).Sum)
    $shadowSkipHits = [UInt64](($spuHleShadowRecords | Measure-Object -Property skip_hits -Sum).Sum)
    $shadowSkipBytes = [UInt64](($spuHleShadowRecords | Measure-Object -Property skip_bytes -Sum).Sum)
    $shadowSkipMisses = [UInt64](($spuHleShadowRecords | Measure-Object -Property skip_misses -Sum).Sum)
    $shadowSkipMissBytes = [UInt64](($spuHleShadowRecords | Measure-Object -Property skip_miss_bytes -Sum).Sum)
    $shadowUniqueSrc = @($spuHleShadowRecords | Select-Object -ExpandProperty last_src_hash -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count

    $lines.Add("- Hits: $shadowHits") | Out-Null
    $lines.Add("- Candidate bytes: $(Format-ProbeBytes $shadowBytes)") | Out-Null
    $lines.Add("- Output match/mismatch: $shadowMatch / $shadowMismatch") | Out-Null
    $lines.Add("- Destination changed/unchanged: $shadowDstChanged / $shadowDstUnchanged") | Out-Null
    $lines.Add("- Guarded skip hits/bytes: $shadowSkipHits / $(Format-ProbeBytes $shadowSkipBytes)") | Out-Null
    $lines.Add("- Guarded skip misses/bytes: $shadowSkipMisses / $(Format-ProbeBytes $shadowSkipMissBytes)") | Out-Null
    $lines.Add("- Source repeats: $shadowSrcRepeats") | Out-Null
    $lines.Add("- Unique source hashes: $shadowUniqueSrc") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Hits | Bytes | Match | Mismatch | Dst Changed | Dst Unchanged | Skip Hits | Skip Bytes | Skip Misses | Src Repeats | Last PC | Last Cmd | Last Tag | Last Size | Last LSA | Last EAL | Last Src Hash | Dst Pre Hash | Dst Post Hash | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHleShadowRecords | Sort-Object -Property hits, bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | `{11}` | `{12}` | {13} | {14} | `{15}` | `{16}` | `{17}` | `{18}` | `{19}` | `{20}` | `{21}` | `{22}` |' -f
            $rank,
            $record.hits,
            (Format-ProbeBytes $record.bytes),
            $record.output_match,
            $record.output_mismatch,
            $record.dst_changed,
            $record.dst_unchanged,
            $record.skip_hits,
            (Format-ProbeBytes $record.skip_bytes),
            $record.skip_misses,
            $record.src_repeats,
            $record.last_pc,
            $record.last_cmd,
            $record.last_tag,
            $record.last_size,
            $record.last_lsa,
            $record.last_eal,
            $record.last_src_hash,
            $record.last_dst_pre_hash,
            $record.last_dst_post_hash,
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $shadowShapeSummaries = @(
        $spuHleShadowRecords |
            Group-Object -Property last_pc,last_cmd,last_tag,last_size,last_lsa,last_eal,group_name,spu_name,image_sig |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    records       = $_.Count
                    hits          = [UInt64](($_.Group | Measure-Object -Property hits -Sum).Sum)
                    bytes         = [UInt64](($_.Group | Measure-Object -Property bytes -Sum).Sum)
                    output_match  = [UInt64](($_.Group | Measure-Object -Property output_match -Sum).Sum)
                    output_mismatch = [UInt64](($_.Group | Measure-Object -Property output_mismatch -Sum).Sum)
                    dst_changed   = [UInt64](($_.Group | Measure-Object -Property dst_changed -Sum).Sum)
                    dst_unchanged = [UInt64](($_.Group | Measure-Object -Property dst_unchanged -Sum).Sum)
                    skip_hits     = [UInt64](($_.Group | Measure-Object -Property skip_hits -Sum).Sum)
                    skip_bytes    = [UInt64](($_.Group | Measure-Object -Property skip_bytes -Sum).Sum)
                    skip_misses   = [UInt64](($_.Group | Measure-Object -Property skip_misses -Sum).Sum)
                    src_repeats   = [UInt64](($_.Group | Measure-Object -Property src_repeats -Sum).Sum)
                    unique_src    = @($_.Group | Select-Object -ExpandProperty last_src_hash -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
                    last_pc       = $first.last_pc
                    last_cmd      = $first.last_cmd
                    last_tag      = $first.last_tag
                    last_size     = $first.last_size
                    last_lsa      = $first.last_lsa
                    last_eal      = $first.last_eal
                    group_name    = $first.group_name
                    spu_name      = $first.spu_name
                    image_sig     = $first.image_sig
                }
            } |
            Sort-Object -Property hits, bytes -Descending |
            Select-Object -First $Top
    )

    if ($shadowShapeSummaries.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("### SPU HLE Shadow Shape Summary") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | Records | Hits | Bytes | Match | Mismatch | Dst Changed | Dst Unchanged | Skip Hits | Skip Bytes | Skip Misses | Src Repeats | Unique Src | PC | Cmd | Tag | Size | LSA | EAL | Group | SPU | Image |") | Out-Null
        $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | --- | --- | --- |") | Out-Null

        $rank = 1
        foreach ($shape in @($shadowShapeSummaries)) {
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | `{13}` | `{14}` | {15} | {16} | `{17}` | `{18}` | `{19}` | `{20}` | `{21}` |' -f
                $rank,
                $shape.records,
                $shape.hits,
                (Format-ProbeBytes $shape.bytes),
                $shape.output_match,
                $shape.output_mismatch,
                $shape.dst_changed,
                $shape.dst_unchanged,
                $shape.skip_hits,
                (Format-ProbeBytes $shape.skip_bytes),
                $shape.skip_misses,
                $shape.src_repeats,
                $shape.unique_src,
                $shape.last_pc,
                $shape.last_cmd,
                $shape.last_tag,
                $shape.last_size,
                $shape.last_lsa,
                $shape.last_eal,
                $shape.group_name,
                $shape.spu_name,
                $shape.image_sig)) | Out-Null
            $rank++
        }
    }

    $lines.Add("") | Out-Null
    $lines.Add('SPU HLE shadow reading: exact-copy contract. In `Verify` mode it is only a guarded skip hint; in `Skip` mode nonzero skip hits mean the copy returned early only after proving `dst_pre==src`. Treat this as a CPU/SPU HLE micro-candidate until matched A/B speed proof exists.') | Out-Null
}

if ($spuHle451cListSeedRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE 0x451c List-Seed Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $seedHits = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property hits -Sum).Sum)
    $seedSuccess = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property success -Sum).Sum)
    $seedFail = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property fail -Sum).Sum)
    $seed1Hits = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property seed1_hits -Sum).Sum)
    $seed2Hits = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property seed2_hits -Sum).Sum)
    $seedDescBytes = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property desc_bytes -Sum).Sum)
    $seedTotalUs = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property total_us -Sum).Sum)
    $seedMaxTotalUs = [UInt64](($spuHle451cListSeedRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $seedTimedHits = [UInt64]([Math]::Max(1, [double]$seedHits))

    $lines.Add("- Hits: $seedHits") | Out-Null
    $lines.Add("- Success / fail: $seedSuccess / $seedFail") | Out-Null
    $lines.Add("- Seed1 / seed2 hits: $seed1Hits / $seed2Hits") | Out-Null
    $lines.Add("- Descriptor bytes: $(Format-ProbeBytes $seedDescBytes)") | Out-Null
    $lines.Add(("- Timing: total={0:n3} ms, avg={1:n3} us/hit, max={2} us" -f ($seedTotalUs / 1000.0), ([double]$seedTotalUs / [double]$seedTimedHits), $seedMaxTotalUs)) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Hits | Total ms | Avg us | Max us | Success | Fail | Seed1 | Seed2 | Last Seed | Last PC | Last Cmd | Last Tag | Last Size | Last LSA | Last EAL | Desc Bytes | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHle451cListSeedRecords | Sort-Object -Property total_us, hits -Descending | Select-Object -First $Top)) {
        $avgUs = [double]$record.total_us / [double]([Math]::Max(1, [double]$record.hits))
        $lines.Add(('| {0} | {1} | {2:n3} | {3:n3} | {4} | {5} | {6} | {7} | {8} | {9} | `{10}` | `{11}` | {12} | {13} | `{14}` | `{15}` | {16} | `{17}` | `{18}` | `{19}` |' -f
            $rank,
            $record.hits,
            ($record.total_us / 1000.0),
            $avgUs,
            $record.max_total_us,
            $record.success,
            $record.fail,
            $record.seed1_hits,
            $record.seed2_hits,
            $record.last_seed,
            $record.last_pc,
            $record.last_cmd,
            $record.last_tag,
            $record.last_size,
            $record.last_lsa,
            $record.last_eal,
            (Format-ProbeBytes $record.desc_bytes),
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("SPU HLE 0x451c list-seed reading: this is a verify-only recognizer for the two hottest dynamic list-control seeds. It keeps stock DMA behavior, does not skip or offload work, and is only a compile-checked counter for the next 0x451c HLE/codegen body experiment.") | Out-Null
}

if ($spuHle451cListFamilyRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE 0x451c List-Family Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $familyHits = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property hits -Sum).Sum)
    $familySuccess = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property success -Sum).Sum)
    $familyFail = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property fail -Sum).Sum)
    $tag1Size8Hits = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property tag1_size8_hits -Sum).Sum)
    $tag0Size8Hits = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property tag0_size8_hits -Sum).Sum)
    $tag0Size16Hits = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property tag0_size16_hits -Sum).Sum)
    $tag1Size16Hits = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property tag1_size16_hits -Sum).Sum)
    $tag1Size24Hits = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property tag1_size24_hits -Sum).Sum)
    $tag0Size24Hits = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property tag0_size24_hits -Sum).Sum)
    $familyDescBytes = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property desc_bytes -Sum).Sum)
    $familyTotalUs = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property total_us -Sum).Sum)
    $familyMaxTotalUs = [UInt64](($spuHle451cListFamilyRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $familyTimedHits = [UInt64]([Math]::Max(1, [double]$familyHits))

    $lines.Add("- Hits: $familyHits") | Out-Null
    $lines.Add("- Success / fail: $familySuccess / $familyFail") | Out-Null
    $lines.Add("- Tag/size hits: tag1/size8=$tag1Size8Hits, tag0/size8=$tag0Size8Hits, tag0/size16=$tag0Size16Hits, tag1/size16=$tag1Size16Hits, tag1/size24=$tag1Size24Hits, tag0/size24=$tag0Size24Hits") | Out-Null
    $lines.Add("- Descriptor bytes: $(Format-ProbeBytes $familyDescBytes)") | Out-Null
    $lines.Add(("- Timing: total={0:n3} ms, avg={1:n3} us/hit, max={2} us" -f ($familyTotalUs / 1000.0), ([double]$familyTotalUs / [double]$familyTimedHits), $familyMaxTotalUs)) | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Hits | Total ms | Avg us | Max us | Success | Fail | Tag1 Size8 | Tag0 Size8 | Tag0 Size16 | Tag1 Size16 | Tag1 Size24 | Tag0 Size24 | Last Family | Last PC | Last Cmd | Last Tag | Last Size | Last LSA | Last EAL | Desc Bytes | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | --- | --- | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHle451cListFamilyRecords | Sort-Object -Property total_us, hits -Descending | Select-Object -First $Top)) {
        $avgUs = [double]$record.total_us / [double]([Math]::Max(1, [double]$record.hits))
        $lines.Add(('| {0} | {1} | {2:n3} | {3:n3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} | `{14}` | `{15}` | {16} | {17} | `{18}` | `{19}` | {20} | `{21}` | `{22}` | `{23}` |' -f
            $rank,
            $record.hits,
            ($record.total_us / 1000.0),
            $avgUs,
            $record.max_total_us,
            $record.success,
            $record.fail,
            $record.tag1_size8_hits,
            $record.tag0_size8_hits,
            $record.tag0_size16_hits,
            $record.tag1_size16_hits,
            $record.tag1_size24_hits,
            $record.tag0_size24_hits,
            $record.last_family,
            $record.last_pc,
            $record.last_cmd,
            $record.last_tag,
            $record.last_size,
            $record.last_lsa,
            $record.last_eal,
            (Format-ProbeBytes $record.desc_bytes),
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add('SPU HLE 0x451c list-family reading: this is a verify-only broad recognizer for the six measured dynamic `0x46` tag/size families. It keeps stock DMA behavior, does not skip or offload work, and exists to size the next preserve-order list-control/codegen batching experiment.') | Out-Null
}

if ($spuHle451cPreserveBodyRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## SPU HLE 0x451c Preserve-Body Verifier") | Out-Null
    $lines.Add("") | Out-Null

    $preserveBodyGroups = [UInt64](($spuHle451cPreserveBodyRecords | Measure-Object -Property groups -Sum).Sum)
    $preserveBodyDesc = [UInt64](($spuHle451cPreserveBodyRecords | Measure-Object -Property desc -Sum).Sum)
    $preserveBodyBytes = [UInt64](($spuHle451cPreserveBodyRecords | Measure-Object -Property bytes -Sum).Sum)

    $lines.Add("- Executed groups: $preserveBodyGroups") | Out-Null
    $lines.Add("- Executed descriptors: $preserveBodyDesc") | Out-Null
    $lines.Add("- Executed bytes: $(Format-ProbeBytes $preserveBodyBytes)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Mode | Groups | Desc | Bytes | Last Family | Last Desc | Last Bytes | Last First EA | Last Last EA | Group | SPU |") | Out-Null
    $lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($spuHle451cPreserveBodyRecords | Sort-Object -Property bytes, groups -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} | `{8}` | `{9}` | `{10}` | `{11}` |' -f
            $rank,
            $record.hle_mode,
            $record.groups,
            $record.desc,
            (Format-ProbeBytes $record.bytes),
            $record.last_family,
            $record.last_desc,
            $record.last_bytes,
            $record.last_first_ea,
            $record.last_last_ea,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("Preserve-body reading: this is an opt-in Windows verifier for partial preserve-order inline GET batches under `RPCS3_ES_SPU_HLE_451C_PRESERVE_BODY`. It executes CPU-side copies, not GPU compute, and it is not speed or migration credit until field/menu/battle visuals and matched timing prove it.") | Out-Null
}

if ($mfcDynamicRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Dynamic MFC Cmd Fallback") | Out-Null
    $lines.Add("") | Out-Null

    $dynamicHits = [UInt64](($mfcDynamicRecords | Measure-Object -Property hits -Sum).Sum)
    $dynamicSuccess = [UInt64](($mfcDynamicRecords | Measure-Object -Property success -Sum).Sum)
    $dynamicFail = [UInt64](($mfcDynamicRecords | Measure-Object -Property fail -Sum).Sum)
    $dynamicBytes = [UInt64](($mfcDynamicRecords | Measure-Object -Property bytes -Sum).Sum)
    $dynamicTotalUs = [UInt64](($mfcDynamicRecords | Measure-Object -Property total_us -Sum).Sum)
    $dynamicMaxTotalUs = [UInt64](($mfcDynamicRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $dynamicTimedHits = [UInt64]([Math]::Max(1, [double]$dynamicHits))
    $pc25Hits = [UInt64](($mfcDynamicRecords | Measure-Object -Property pc25_hits -Sum).Sum)
    $pc25Us = [UInt64](($mfcDynamicRecords | Measure-Object -Property pc25_us -Sum).Sum)
    $pc451cHits = [UInt64](($mfcDynamicRecords | Measure-Object -Property pc451c_hits -Sum).Sum)
    $pc451cUs = [UInt64](($mfcDynamicRecords | Measure-Object -Property pc451c_us -Sum).Sum)
    $pc0a70Hits = [UInt64](($mfcDynamicRecords | Measure-Object -Property pc0a70_hits -Sum).Sum)
    $pc0a70Us = [UInt64](($mfcDynamicRecords | Measure-Object -Property pc0a70_us -Sum).Sum)
    $getHits = [UInt64](($mfcDynamicRecords | Measure-Object -Property get_hits -Sum).Sum)
    $putHits = [UInt64](($mfcDynamicRecords | Measure-Object -Property put_hits -Sum).Sum)
    $listHits = [UInt64](($mfcDynamicRecords | Measure-Object -Property list_hits -Sum).Sum)
    $atomicHits = [UInt64](($mfcDynamicRecords | Measure-Object -Property atomic_hits -Sum).Sum)
    $otherHits = [UInt64](($mfcDynamicRecords | Measure-Object -Property other_hits -Sum).Sum)

    $lines.Add("- Dynamic MFC hits: $dynamicHits") | Out-Null
    $lines.Add("- Success / fail: $dynamicSuccess / $dynamicFail") | Out-Null
    $lines.Add("- Dynamic MFC bytes: $(Format-ProbeBytes $dynamicBytes)") | Out-Null
    $lines.Add(("- Timing: total={0:n3} ms, avg={1:n3} us/hit, max={2} us" -f ($dynamicTotalUs / 1000.0), ([double]$dynamicTotalUs / [double]$dynamicTimedHits), $dynamicMaxTotalUs)) | Out-Null
    $lines.Add("- PC mix: 0x25cc=$pc25Hits hits / $([Math]::Round($pc25Us / 1000.0, 3)) ms, 0x451c=$pc451cHits hits / $([Math]::Round($pc451cUs / 1000.0, 3)) ms, 0x0a70=$pc0a70Hits hits / $([Math]::Round($pc0a70Us / 1000.0, 3)) ms") | Out-Null
    $lines.Add("- Command mix: get=$getHits put=$putHits list=$listHits atomic=$atomicHits other=$otherHits") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Mode | Hits | Total ms | Avg us | Max us | 0x25cc | 0x451c | 0x0a70 | GET | PUT | LIST | Atomic | Last PC | Last Cmd | Bytes | Group | SPU |") | Out-Null
    $lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcDynamicRecords | Sort-Object -Property total_us, hits -Descending | Select-Object -First $Top)) {
        $avgUs = [double]$record.total_us / [double]([Math]::Max(1, [double]$record.hits))
        $lines.Add(('| {0} | `{1}` | {2} | {3:n3} | {4:n3} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | `{13}` | `{14}` | {15} | `{16}` | `{17}` |' -f
            $rank,
            $record.ladder_mode,
            $record.hits,
            ($record.total_us / 1000.0),
            $avgUs,
            $record.max_total_us,
            $record.pc25_hits,
            $record.pc451c_hits,
            $record.pc0a70_hits,
            $record.get_hits,
            $record.put_hits,
            $record.list_hits,
            $record.atomic_hits,
            $record.last_pc,
            $record.last_cmd,
            (Format-ProbeBytes $record.bytes),
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("Dynamic MFC reading: this times the LLVM non-constant `MFC_Cmd` fallback path that reaches `spu_write_channel`. If totals are small, specialize the SPU body instead; if one PC dominates, build a guarded codegen/HLE fast path for that PC before considering a GPU mirror.") | Out-Null
}

if ($mfcListRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## MFC List Transfer Timing") | Out-Null
    $lines.Add("") | Out-Null

    $listCalls = [UInt64](($mfcListRecords | Measure-Object -Property calls -Sum).Sum)
    $listSuccess = [UInt64](($mfcListRecords | Measure-Object -Property success -Sum).Sum)
    $listFail = [UInt64](($mfcListRecords | Measure-Object -Property fail -Sum).Sum)
    $listDescBytes = [UInt64](($mfcListRecords | Measure-Object -Property desc_bytes -Sum).Sum)
    $listTotalUs = [UInt64](($mfcListRecords | Measure-Object -Property total_us -Sum).Sum)
    $listMaxTotalUs = [UInt64](($mfcListRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $listTimedCalls = [UInt64]([Math]::Max(1, [double]$listCalls))
    $listGetCalls = [UInt64](($mfcListRecords | Measure-Object -Property get_calls -Sum).Sum)
    $listPutCalls = [UInt64](($mfcListRecords | Measure-Object -Property put_calls -Sum).Sum)
    $listPc451cHits = [UInt64](($mfcListRecords | Measure-Object -Property pc451c_hits -Sum).Sum)
    $listPc451cUs = [UInt64](($mfcListRecords | Measure-Object -Property pc451c_us -Sum).Sum)
    $listOtherHits = [UInt64](($mfcListRecords | Measure-Object -Property other_hits -Sum).Sum)
    $listOtherUs = [UInt64](($mfcListRecords | Measure-Object -Property other_us -Sum).Sum)

    $lines.Add("- List-transfer calls: $listCalls") | Out-Null
    $lines.Add("- Success / fail: $listSuccess / $listFail") | Out-Null
    $lines.Add("- Descriptor bytes: $(Format-ProbeBytes $listDescBytes)") | Out-Null
    $lines.Add(("- Timing: total={0:n3} ms, avg={1:n3} us/call, max={2} us" -f ($listTotalUs / 1000.0), ([double]$listTotalUs / [double]$listTimedCalls), $listMaxTotalUs)) | Out-Null
    $lines.Add("- PC mix: 0x451c=$listPc451cHits hits / $([Math]::Round($listPc451cUs / 1000.0, 3)) ms, other=$listOtherHits hits / $([Math]::Round($listOtherUs / 1000.0, 3)) ms") | Out-Null
    $lines.Add("- Direction mix: get=$listGetCalls put=$listPutCalls") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Mode | Calls | Total ms | Avg us | Max us | 0x451c | Other | GET | PUT | Last PC | Last Cmd | Desc Bytes | Group | SPU |") | Out-Null
    $lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcListRecords | Sort-Object -Property total_us, calls -Descending | Select-Object -First $Top)) {
        $avgUs = [double]$record.total_us / [double]([Math]::Max(1, [double]$record.calls))
        $lines.Add(('| {0} | `{1}` | {2} | {3:n3} | {4:n3} | {5} | {6} | {7} | {8} | {9} | `{10}` | `{11}` | {12} | `{13}` | `{14}` |' -f
            $rank,
            $record.ladder_mode,
            $record.calls,
            ($record.total_us / 1000.0),
            $avgUs,
            $record.max_total_us,
            $record.pc451c_hits,
            $record.other_hits,
            $record.get_calls,
            $record.put_calls,
            $record.last_pc,
            $record.last_cmd,
            (Format-ProbeBytes $record.desc_bytes),
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("MFC list-transfer reading: this isolates the actual `do_list_transfer` body for hot list DMAs. If this is still tiny, the offload target is not list issuing; look for the SPU consumer body or an RSX-local producer/consumer chain.") | Out-Null
}

if ($mfcWaitRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## MFC Tag/Atomic Wait Timing") | Out-Null
    $lines.Add("") | Out-Null

    $waitReads = [UInt64](($mfcWaitRecords | Measure-Object -Property reads -Sum).Sum)
    $waitFastReads = [UInt64](($mfcWaitRecords | Measure-Object -Property fast_reads -Sum).Sum)
    $waitBlockingReads = [UInt64](($mfcWaitRecords | Measure-Object -Property blocking_reads -Sum).Sum)
    $waitTagReads = [UInt64](($mfcWaitRecords | Measure-Object -Property tagstat_reads -Sum).Sum)
    $waitAtomicReads = [UInt64](($mfcWaitRecords | Measure-Object -Property atomic_reads -Sum).Sum)
    $waitTotalUs = [UInt64](($mfcWaitRecords | Measure-Object -Property total_us -Sum).Sum)
    $waitMaxTotalUs = [UInt64](($mfcWaitRecords | Measure-Object -Property max_total_us -Maximum).Maximum)
    $waitTimedReads = [UInt64]([Math]::Max(1, [double]$waitReads))
    $waitPc2598Hits = [UInt64](($mfcWaitRecords | Measure-Object -Property pc2598_hits -Sum).Sum)
    $waitPc2598Us = [UInt64](($mfcWaitRecords | Measure-Object -Property pc2598_us -Sum).Sum)
    $waitPc2600Hits = [UInt64](($mfcWaitRecords | Measure-Object -Property pc2600_hits -Sum).Sum)
    $waitPc2600Us = [UInt64](($mfcWaitRecords | Measure-Object -Property pc2600_us -Sum).Sum)
    $waitPc0b44Hits = [UInt64](($mfcWaitRecords | Measure-Object -Property pc0b44_hits -Sum).Sum)
    $waitPc0b44Us = [UInt64](($mfcWaitRecords | Measure-Object -Property pc0b44_us -Sum).Sum)
    $waitPc29e4Hits = [UInt64](($mfcWaitRecords | Measure-Object -Property pc29e4_hits -Sum).Sum)
    $waitPc29e4Us = [UInt64](($mfcWaitRecords | Measure-Object -Property pc29e4_us -Sum).Sum)
    $waitOtherHits = [UInt64](($mfcWaitRecords | Measure-Object -Property other_hits -Sum).Sum)
    $waitOtherUs = [UInt64](($mfcWaitRecords | Measure-Object -Property other_us -Sum).Sum)

    $lines.Add("- Wait reads: $waitReads") | Out-Null
    $lines.Add("- Fast / blocking reads: $waitFastReads / $waitBlockingReads") | Out-Null
    $lines.Add("- TagStat / AtomicStat reads: $waitTagReads / $waitAtomicReads") | Out-Null
    $lines.Add(("- Timing: total={0:n3} ms, avg={1:n3} us/read, max={2} us" -f ($waitTotalUs / 1000.0), ([double]$waitTotalUs / [double]$waitTimedReads), $waitMaxTotalUs)) | Out-Null
    $lines.Add("- PC mix: 0x2598=$waitPc2598Hits hits / $([Math]::Round($waitPc2598Us / 1000.0, 3)) ms, 0x2600=$waitPc2600Hits hits / $([Math]::Round($waitPc2600Us / 1000.0, 3)) ms, 0x0b44=$waitPc0b44Hits hits / $([Math]::Round($waitPc0b44Us / 1000.0, 3)) ms, 0x29e4=$waitPc29e4Hits hits / $([Math]::Round($waitPc29e4Us / 1000.0, 3)) ms, other=$waitOtherHits hits / $([Math]::Round($waitOtherUs / 1000.0, 3)) ms") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Mode | Reads | Total ms | Avg us | Max us | Fast | Blocking | TagStat | Atomic | 0x2598 | 0x2600 | 0x0b44 | 0x29e4 | Other | Last PC | Last Ch | Group | SPU |") | Out-Null
    $lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcWaitRecords | Sort-Object -Property total_us, reads -Descending | Select-Object -First $Top)) {
        $avgUs = [double]$record.total_us / [double]([Math]::Max(1, [double]$record.reads))
        $lines.Add(('| {0} | `{1}` | {2} | {3:n3} | {4:n3} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} | {14} | `{15}` | {16} | `{17}` | `{18}` |' -f
            $rank,
            $record.ladder_mode,
            $record.reads,
            ($record.total_us / 1000.0),
            $avgUs,
            $record.max_total_us,
            $record.fast_reads,
            $record.blocking_reads,
            $record.tagstat_reads,
            $record.atomic_reads,
            $record.pc2598_hits,
            $record.pc2600_hits,
            $record.pc0b44_hits,
            $record.pc29e4_hits,
            $record.other_hits,
            $record.last_pc,
            $record.last_ch,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("MFC wait reading: blocking TagStat or AtomicStat time means the win is scheduler/batching/HLE shape, not GPU compute by itself. Mostly fast reads mean the SPU loop after the wait is the next place to profile.") | Out-Null
}

if ($mfcWaitPcRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## MFC Wait Exact PC Histogram") | Out-Null
    $lines.Add("") | Out-Null

    $mfcWaitPcPeaks = @(
        $mfcWaitPcRecords |
            Group-Object -Property pc,group_name,spu_name |
            ForEach-Object {
                $_.Group | Sort-Object -Property reads -Descending | Select-Object -First 1
            } |
            Sort-Object -Property reads -Descending
    )

    $exactPcReads = [UInt64](($mfcWaitPcPeaks | Measure-Object -Property reads -Sum).Sum)
    $exactPcTagReads = [UInt64](($mfcWaitPcPeaks | Measure-Object -Property tagstat_reads -Sum).Sum)
    $exactPcAtomicReads = [UInt64](($mfcWaitPcPeaks | Measure-Object -Property atomic_reads -Sum).Sum)
    $exactPcOverflow = [UInt64](($mfcWaitPcRecords | Measure-Object -Property overflow_reads -Maximum).Maximum)

    $lines.Add("- Peak exact-PC reads: $exactPcReads") | Out-Null
    $lines.Add("- Peak TagStat / AtomicStat reads: $exactPcTagReads / $exactPcAtomicReads") | Out-Null
    $lines.Add("- Max overflow reads beyond the 64-slot exact-PC table: $exactPcOverflow") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | PC | Reads | TagStat | Atomic | Group | SPU | Last PC | Last Ch |") | Out-Null
    $lines.Add("| ---: | --- | ---: | ---: | ---: | --- | --- | --- | ---: |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcWaitPcPeaks | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | {2} | {3} | {4} | `{5}` | `{6}` | `{7}` | {8} |' -f
            $rank,
            $record.pc,
            $record.reads,
            $record.tagstat_reads,
            $record.atomic_reads,
            $record.group_name,
            $record.spu_name,
            $record.last_pc,
            $record.last_ch)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("Exact-PC reading: this table uses per-SPU peak counters instead of summing cumulative log snapshots. Use it to choose the next SPU body/codegen target.") | Out-Null
}

if ($reservationLoopCmdRecords.Count -gt 0 -or $reservationLoopCmdPcRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Reservation Loop Commands") | Out-Null
    $lines.Add("") | Out-Null

    $cmdPeakRows = @(
        $reservationLoopCmdRecords |
            Group-Object -Property group_name,spu_name |
            ForEach-Object {
                $_.Group | Sort-Object -Property cmd_hits -Descending | Select-Object -First 1
            } |
            Sort-Object -Property cmd_hits -Descending
    )
    $cmdPcPeakRows = @(
        $reservationLoopCmdPcRecords |
            Group-Object -Property pc,group_name,spu_name |
            ForEach-Object {
                $_.Group | Sort-Object -Property cmd_hits -Descending | Select-Object -First 1
            } |
            Sort-Object -Property cmd_hits -Descending
    )

    $cmdHits = [UInt64](($cmdPeakRows | Measure-Object -Property cmd_hits -Sum).Sum)
    $getllarCmds = [UInt64](($cmdPeakRows | Measure-Object -Property getllar_cmds -Sum).Sum)
    $putllcCmds = [UInt64](($cmdPeakRows | Measure-Object -Property putllc_cmds -Sum).Sum)
    $atomicUpdates = [UInt64](($cmdPeakRows | Measure-Object -Property atomic_updates -Sum).Sum)
    $getllarSuccess = [UInt64](($cmdPeakRows | Measure-Object -Property getllar_success -Sum).Sum)
    $putllcSuccess = [UInt64](($cmdPeakRows | Measure-Object -Property putllc_success -Sum).Sum)
    $putllcFailure = [UInt64](($cmdPeakRows | Measure-Object -Property putllc_failure -Sum).Sum)
    $cmdPcOverflow = [UInt64](($reservationLoopCmdRecords | Measure-Object -Property pc_overflow -Maximum).Maximum)

    $lines.Add("- Peak command hits: $cmdHits") | Out-Null
    $lines.Add("- GETLLAR / PUTLLC commands: $getllarCmds / $putllcCmds") | Out-Null
    $lines.Add("- Atomic updates: $atomicUpdates; GETLLAR success / PUTLLC success / PUTLLC failure: $getllarSuccess / $putllcSuccess / $putllcFailure") | Out-Null
    $lines.Add("- Max exact-PC overflow: $cmdPcOverflow") | Out-Null

    if ($cmdPeakRows.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | Cmd Hits | GETLLAR | PUTLLC | Atomic Updates | GETLLAR OK | PUTLLC OK | PUTLLC Fail | Last PC | Last Cmd | Last Atomic | Group | SPU |") | Out-Null
        $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- |") | Out-Null

        $rank = 1
        foreach ($record in @($cmdPeakRows | Select-Object -First $Top)) {
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | `{8}` | `{9}` | `{10}` | `{11}` | `{12}` |' -f
                $rank,
                $record.cmd_hits,
                $record.getllar_cmds,
                $record.putllc_cmds,
                $record.atomic_updates,
                $record.getllar_success,
                $record.putllc_success,
                $record.putllc_failure,
                $record.last_pc,
                $record.last_cmd,
                $record.last_atomic,
                $record.group_name,
                $record.spu_name)) | Out-Null
            $rank++
        }
    }

    if ($cmdPcPeakRows.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("### Reservation Command Exact PC") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | PC | Cmd Hits | GETLLAR | PUTLLC | Atomic Updates | GETLLAR OK | PUTLLC OK | PUTLLC Fail | Group | SPU |") | Out-Null
        $lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |") | Out-Null

        $rank = 1
        foreach ($record in @($cmdPcPeakRows | Select-Object -First $Top)) {
            $lines.Add(('| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} | {8} | `{9}` | `{10}` |' -f
                $rank,
                $record.pc,
                $record.cmd_hits,
                $record.getllar_cmds,
                $record.putllc_cmds,
                $record.atomic_updates,
                $record.getllar_success,
                $record.putllc_success,
                $record.putllc_failure,
                $record.group_name,
                $record.spu_name)) | Out-Null
            $rank++
        }
    }

    $lines.Add("") | Out-Null
    $lines.Add("Reservation command reading: this correlates the fast AtomicStat wait PCs with surrounding GETLLAR and PUTLLC commands. It is still a verifier/profiling path, not GPU migration credit or a speed claim.") | Out-Null
}

if ($reservationLoopVerifyRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Reservation Loop Verify") | Out-Null
    $lines.Add("") | Out-Null

    $verifyPeakRows = $reservationLoopVerifyPeakRows

    $verifyAttempts = [UInt64](($verifyPeakRows | Measure-Object -Property attempts -Sum).Sum)
    $verifyCompleted = [UInt64](($verifyPeakRows | Measure-Object -Property completed -Sum).Sum)
    $verifySuccess = [UInt64](($verifyPeakRows | Measure-Object -Property success -Sum).Sum)
    $verifyFailure = [UInt64](($verifyPeakRows | Measure-Object -Property failure -Sum).Sum)
    $verifyUnexpected = [UInt64](($verifyPeakRows | Measure-Object -Property unexpected -Sum).Sum)
    $verifyDirtyMulti = [UInt64](($verifyPeakRows | Measure-Object -Property dirty_multi -Sum).Sum)
    $verifyUpdateLinked = [UInt64](($verifyPeakRows | Measure-Object -Property update_linked -Sum).Sum)
    $verifyUpdateUnlinked = [UInt64](($verifyPeakRows | Measure-Object -Property update_unlinked -Sum).Sum)
    $verifyAtomicReads = [UInt64](($verifyPeakRows | Measure-Object -Property atomic_reads -Sum).Sum)
    $verifyReadGetllar = [UInt64](($verifyPeakRows | Measure-Object -Property read_getllar -Sum).Sum)
    $verifyReadPutllc = [UInt64](($verifyPeakRows | Measure-Object -Property read_putllc -Sum).Sum)
    $verifyReadUnexpected = [UInt64](($verifyPeakRows | Measure-Object -Property read_unexpected -Sum).Sum)

    $lines.Add("- Attempts / completed: $verifyAttempts / $verifyCompleted") | Out-Null
    $lines.Add("- Success / failure / unexpected: $verifySuccess / $verifyFailure / $verifyUnexpected") | Out-Null
    $lines.Add("- Linked / unlinked atomic updates: $verifyUpdateLinked / $verifyUpdateUnlinked") | Out-Null
    $lines.Add("- AtomicStat reads / GETLLAR / PUTLLC / unexpected reads: $verifyAtomicReads / $verifyReadGetllar / $verifyReadPutllc / $verifyReadUnexpected") | Out-Null
    $lines.Add("- Dirty multi-slot observations: $verifyDirtyMulti") | Out-Null

    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Lane | Attempts | Completed | Success | Failure | Unexpected | Update L/U | Reads G/P/Bad | RAddr | RTime | Main Match | Dirty 0/1-2/Multi | Post RAddr 0/Same | LR Event | Last PCs | Last Raw PCs | Retry/Next | Group | SPU |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | --- | --- | ---: | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($verifyPeakRows | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7}/{8} | {9}/{10}/{11} | {12} | {13} | {14} | {15}/{16}/{17} | {18}/{19} | {20} | `{21}->{22}->{23}` | `{24}->{25}->{26}` | `{27}->{28}` | `{29}` | `{30}` |' -f
            $rank,
            $record.lane,
            $record.attempts,
            $record.completed,
            $record.success,
            $record.failure,
            $record.unexpected,
            $record.update_linked,
            $record.update_unlinked,
            $record.read_getllar,
            $record.read_putllc,
            $record.read_unexpected,
            $record.raddr_match,
            $record.rtime_match,
            $record.main_line_match,
            $record.dirty_zero,
            $record.dirty_one_or_two,
            $record.dirty_multi,
            $record.post_raddr_zero,
            $record.post_raddr_same,
            $record.post_lr_event_set,
            $record.last_cmd_pc,
            $record.last_atomic_pc,
            $record.last_read_pc,
            $record.last_raw_cmd_pc,
            $record.last_raw_atomic_pc,
            $record.last_raw_read_pc,
            $record.last_retry_pc,
            $record.last_next_branch_pc,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add('Reservation verify reading: this groups verified reservation lanes into attempts and exit outcomes, and separates command issue, atomic-status update, guest RDCH reads, and raw SPU instruction PCs. It is a correctness verifier only; fast mode and GPU dispatch remain unavailable.') | Out-Null
}

if ($reservationLoopRdchJoinRows.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Reservation Loop RDCH Join") | Out-Null
    $lines.Add("") | Out-Null

    $joinedGetllarReads = [UInt64](($reservationLoopRdchJoinRows | Measure-Object -Property getllar_exact_reads -Sum).Sum)
    $joinedPutllcReads = [UInt64](($reservationLoopRdchJoinRows | Measure-Object -Property putllc_exact_reads -Sum).Sum)
    $joinedInHookReads = [UInt64](($reservationLoopRdchJoinRows | Measure-Object -Property in_hook_atomic_reads -Sum).Sum)
    $joinedExactReads = [UInt64](($reservationLoopRdchJoinRows | Measure-Object -Property exact_atomic_reads -Sum).Sum)
    $joinedUnexpected = [UInt64](($reservationLoopRdchJoinRows | Measure-Object -Property unexpected -Sum).Sum)

    $lines.Add("- Exact-PC AtomicStat reads GETLLAR / PUTLLC: $joinedGetllarReads / $joinedPutllcReads") | Out-Null
    $lines.Add("- In-hook AtomicStat reads / exact-PC AtomicStat reads: $joinedInHookReads / $joinedExactReads") | Out-Null
    $lines.Add("- Exact-PC reads minus in-hook reads: $(Get-ProbeSignedDelta $joinedExactReads $joinedInHookReads)") | Out-Null
    $lines.Add("- Joined unexpected verifier transitions: $joinedUnexpected") | Out-Null

    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Attempts | GETLLAR Reads | GETLLAR Cov | Completed | PUTLLC Reads | PUTLLC Cov | Update L/U | In-Hook Reads | Exact-InHook | Unexpected | Last PCs | Group | SPU |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($reservationLoopRdchJoinRows | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7}/{8} | {9} | {10} | {11} | `{12}->{13}->{14}` | `{15}` | `{16}` |' -f
            $rank,
            $record.getllar_attempts,
            $record.getllar_exact_reads,
            $record.getllar_read_coverage,
            $record.putllc_completed,
            $record.putllc_exact_reads,
            $record.putllc_read_coverage,
            $record.update_linked,
            $record.update_unlinked,
            $record.in_hook_atomic_reads,
            $record.exact_minus_in_hook_reads,
            $record.unexpected,
            $record.last_cmd_pc,
            $record.last_atomic_pc,
            $record.last_read_pc,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add('RDCH join reading: this is a post-process join between verify rows and the existing exact-PC AtomicStat histogram. It gives read-stage evidence without widening live MFC hooks; use it to target RDCH lowering or a verifier state-machine fix, not as a speed claim.') | Out-Null
}

if ($reservationLoopLaneJoinRows.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Reservation Loop Lane Join") | Out-Null
    $lines.Add("") | Out-Null

    $laneMissingVerify = @($reservationLoopLaneJoinRows | Where-Object { $_.classification -eq "exact-pc-seen-live-verify-missing" })
    $laneExactPutllc = [UInt64](($reservationLoopLaneJoinRows | Measure-Object -Property putllc_cmd_hits -Sum).Sum)
    $laneExactReads = [UInt64](($reservationLoopLaneJoinRows | Measure-Object -Property putllc_read_hits -Sum).Sum)

    $lines.Add("- Known lane exact-PC PUTLLC command/read peaks: $laneExactPutllc / $laneExactReads") | Out-Null
    $lines.Add("- Lanes with exact-PC evidence but no live verify lane rows: $($laneMissingVerify.Count)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Lane | GET Cmd/Read | PUT Cmd/Read | Raw PUT Cmd/Read | Verify Rows | Verify A/C | Verify S/F/U | Branch R/N | Retry/Next | Class | Exact Group | Raw Group |") | Out-Null
    $lines.Add("| ---: | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

    foreach ($record in @($reservationLoopLaneJoinRows | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}`:{2} / `{3}`:{4} | `{5}`:{6} / `{7}`:{8} | {9}/{10} | {11} | {12}/{13} | {14}/{15}/{16} | {17}/{18}/{19} / {20}/{21}/{22} | `{23}->{24}` | `{25}` | `{26}`/`{27}` | `{28}`/`{29}` |' -f
            $record.lane,
            $record.getllar_cmd_peak_pc,
            $record.getllar_cmd_hits,
            $record.getllar_read_peak_pc,
            $record.getllar_read_hits,
            $record.putllc_cmd_peak_pc,
            $record.putllc_cmd_hits,
            $record.putllc_read_peak_pc,
            $record.putllc_read_hits,
            $record.raw_lane_cmd_hits,
            $record.raw_lane_read_hits,
            $record.verify_row_count,
            $record.verify_attempts,
            $record.verify_completed,
            $record.verify_success,
            $record.verify_failure,
            $record.verify_unexpected,
            $record.verify_retry_branches,
            $record.verify_retry_taken,
            $record.verify_retry_fallthrough,
            $record.verify_next_branches,
            $record.verify_next_taken,
            $record.verify_next_fallthrough,
            $record.retry_pc,
            $record.next_branch_pc,
            $record.classification,
            $record.exact_group_name,
            $record.exact_spu_name,
            $record.raw_group_name,
            $record.raw_spu_name)) | Out-Null
    }

    $lines.Add("") | Out-Null
    $lines.Add('Lane join reading: this joins the known reservation-loop lane map against command exact-PCs, AtomicStat exact-PCs, raw disassembly lanes, and live verify rows. A lane can be hot in exact-PC counters while absent from live verify rows when the live verifier only preserves the last aggregate lane; fix that attribution before designing a fast/HLE/GPU replacement.') | Out-Null
}

if ($reservationLoopRawLaneRows.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Reservation Loop Raw SPU Lanes") | Out-Null
    $lines.Add("") | Out-Null

    $rawLaneCmdHits = [UInt64](($reservationLoopRawLaneRows | Measure-Object -Property putllc_cmd_hits -Sum).Sum)
    $rawLaneReadHits = [UInt64](($reservationLoopRawLaneRows | Measure-Object -Property putllc_read_hits -Sum).Sum)
    $lines.Add("- Raw SPU reservation lanes found in disassembly sidecars: $($reservationLoopRawLaneRows.Count)") | Out-Null
    $lines.Add("- Raw PUTLLC command/read counter peaks across lanes: $rawLaneCmdHits / $rawLaneReadHits") | Out-Null

    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Raw GET/RD | Raw PUT/RD | Retry | Next Branch | Cmd Hits G/P | Read Hits G/P | Focus PCs | Group | SPU |") | Out-Null
    $lines.Add("| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($reservationLoopRawLaneRows | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}`/`{2}` | `{3}`/`{4}` | `{5}` `{6}` | `{7}` `{8}` | {9}/{10} | {11}/{12} | `{13}` | `{14}` | `{15}` |' -f
            $rank,
            $record.raw_getllar_cmd_pc,
            $record.raw_getllar_read_pc,
            $record.raw_putllc_cmd_pc,
            $record.raw_putllc_read_pc,
            $record.raw_retry_branch_pc,
            $record.raw_retry_branch,
            $record.raw_next_branch_pc,
            $record.raw_next_branch,
            $record.getllar_cmd_hits,
            $record.putllc_cmd_hits,
            $record.getllar_read_hits,
            $record.putllc_read_hits,
            $record.source_focus_pcs,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add('Raw lane reading: this parses SPU disassembly windows and keeps raw instruction PCs separate from the exact-PC counter/focus PCs. Use this to choose whole-loop verifier lanes and retry/next-branch checks before any fast/HLE/GPU replacement; it is analysis only, not GPU migration credit or a speed claim.') | Out-Null
}

if ($putllc16Records.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## PUTLLC16 Analyzer") | Out-Null
    $lines.Add("") | Out-Null

    $putllcEntries = @($putllc16Records | Where-Object { $_.kind -eq "entry" })
    $putllcDetected = @($putllc16Records | Where-Object { $_.kind -eq "detected" })
    $putllcPairs = @($putllc16Records | Where-Object { $_.kind -eq "pair-candidate" })
    $putllcBreakages = @($putllc16Records | Where-Object { $_.kind -eq "breakage" })

    $waitPcPeakByPc = @{}
    foreach ($waitPcGroup in @($mfcWaitPcRecords | Group-Object -Property pc)) {
        $waitPcPeakByPc[$waitPcGroup.Name] = $waitPcGroup.Group | Sort-Object -Property reads -Descending | Select-Object -First 1
    }

    $lines.Add("- GETLLAR entry records: $($putllcEntries.Count)") | Out-Null
    $lines.Add("- PUTLLC16 detected records: $($putllcDetected.Count)") | Out-Null
    $lines.Add("- PUTLLC16 pair candidate records: $($putllcPairs.Count)") | Out-Null
    $lines.Add("- PUTLLC pattern breakage records: $($putllcBreakages.Count)") | Out-Null

    if ($putllcDetected.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("### Detected Patterns") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | Pattern Hash | Records | Function | Put PC | Mem Count | Runtime | Last PUTLLC16 Count | Nearby Wait PC | Nearby Wait Reads |") | Out-Null
        $lines.Add("| ---: | --- | ---: | --- | --- | ---: | ---: | ---: | --- | ---: |") | Out-Null

        $detectedRows = @(
            $putllcDetected |
                Group-Object -Property pattern_hash,function_sig,put_pc |
                ForEach-Object {
                    $groupRecords = @($_.Group)
                    $first = $groupRecords[0]
                    $peakCounter = $groupRecords | Sort-Object -Property putllc16_count -Descending | Select-Object -First 1
                    $nearWait = Find-ProbeWaitPcPeak -WaitPcPeakByPc $waitPcPeakByPc -TargetPc $first.put_pc -WindowBytes 16
                    [pscustomobject]@{
                        pattern_hash   = $first.pattern_hash
                        records        = $_.Count
                        function_sig   = $first.function_sig
                        put_pc         = $first.put_pc
                        mem_count      = $first.mem_count
                        runtime        = $first.runtime
                        putllc16_count = $peakCounter.putllc16_count
                        near_wait_pc   = if ($null -ne $nearWait) { $nearWait.pc } else { "" }
                        near_wait_reads = if ($null -ne $nearWait) { $nearWait.reads } else { [UInt64]0 }
                    }
                } |
                Sort-Object -Property near_wait_reads,records -Descending
        )

        $rank = 1
        foreach ($row in @($detectedRows | Select-Object -First $Top)) {
            $lines.Add(('| {0} | `{1}` | {2} | `{3}` | `{4}` | {5} | {6} | {7} | `{8}` | {9} |' -f
                $rank,
                $row.pattern_hash,
                $row.records,
                $row.function_sig,
                $row.put_pc,
                $row.mem_count,
                $row.runtime,
                $row.putllc16_count,
                $row.near_wait_pc,
                $row.near_wait_reads)) | Out-Null
            $rank++
        }
    }

    if ($putllcPairs.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("### Pair Candidates") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | Pattern Hash | Records | Function | Put PC | Mem Count | Offsets | Write Mask | Access Mask | No Notify |") | Out-Null
        $lines.Add("| ---: | --- | ---: | --- | --- | ---: | --- | --- | --- | ---: |") | Out-Null

        $pairRows = @(
            $putllcPairs |
                Group-Object -Property pattern_hash,function_sig,put_pc |
                ForEach-Object {
                    $first = $_.Group[0]
                    [pscustomobject]@{
                        pattern_hash = $first.pattern_hash
                        records      = $_.Count
                        function_sig = $first.function_sig
                        put_pc       = $first.put_pc
                        mem_count    = $first.mem_count
                        offsets      = $first.offset
                        write_mask   = $first.write_mask
                        access_mask  = $first.access_mask
                        no_notify    = $first.no_notify
                    }
                } |
                Sort-Object -Property records -Descending
        )

        $rank = 1
        foreach ($row in @($pairRows | Select-Object -First $Top)) {
            $lines.Add(('| {0} | `{1}` | {2} | `{3}` | `{4}` | {5} | `{6}` | `{7}` | `{8}` | {9} |' -f
                $rank,
                $row.pattern_hash,
                $row.records,
                $row.function_sig,
                $row.put_pc,
                $row.mem_count,
                $row.offsets,
                $row.write_mask,
                $row.access_mask,
                $row.no_notify)) | Out-Null
            $rank++
        }
    }

    if ($putllcBreakages.Count -gt 0) {
        $lines.Add("") | Out-Null
        $lines.Add("### Breakage PCs") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Rank | Cause | Reason | Records | Break PC | LSA PC | Mem | LSA Const | Exact Wait Reads | Exact Atomic Reads | Worker |") | Out-Null
        $lines.Add("| ---: | ---: | --- | ---: | --- | --- | ---: | ---: | ---: | ---: | --- |") | Out-Null

        $breakageRows = @(
            $putllcBreakages |
                Group-Object -Property cause,break_pc,lsa_pc |
                ForEach-Object {
                    $groupRecords = @($_.Group)
                    $first = $groupRecords[0]
                    $waitPeak = Find-ProbeWaitPcPeak -WaitPcPeakByPc $waitPcPeakByPc -TargetPc $first.lsa_pc -WindowBytes 0
                    [pscustomobject]@{
                        cause        = $first.cause
                        cause_reason = $first.cause_reason
                        records      = $_.Count
                        break_pc     = $first.break_pc
                        lsa_pc       = $first.lsa_pc
                        mem          = $first.mem
                        lsa_const    = $first.lsa_const
                        wait_reads   = if ($null -ne $waitPeak) { $waitPeak.reads } else { [UInt64]0 }
                        atomic_reads = if ($null -ne $waitPeak) { $waitPeak.atomic_reads } else { [UInt64]0 }
                        worker       = $first.worker
                    }
                } |
                Sort-Object -Property wait_reads,records -Descending
        )

        $rank = 1
        foreach ($row in @($breakageRows | Select-Object -First $Top)) {
            $lines.Add(('| {0} | {1} | {2} | {3} | `{4}` | `{5}` | {6} | {7} | {8} | {9} | `{10}` |' -f
                $rank,
                $row.cause,
                $row.cause_reason,
                $row.records,
                $row.break_pc,
                $row.lsa_pc,
                $row.mem,
                $row.lsa_const,
                $row.wait_reads,
                $row.atomic_reads,
                $row.worker)) | Out-Null
            $rank++
        }
    }

    $lines.Add("") | Out-Null
    $lines.Add("PUTLLC16 reading: detected patterns are existing CPU-side reduced-loop/codegen opportunities; breakage PCs explain where the recognizer refused to replace a reservation loop. This is still a CPU/SPU specialization track unless a later capture proves a stable bulk body or RSX-consumed buffer behind the loop.") | Out-Null
}

if ($putllc16RuntimeRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## PUTLLC16 Runtime") | Out-Null
    $lines.Add("") | Out-Null

    $putllc16RuntimePeaks = @(
        $putllc16RuntimeRecords |
            Group-Object -Property group_name,spu_name |
            ForEach-Object {
                $_.Group | Sort-Object -Property hits -Descending | Select-Object -First 1
            } |
            Sort-Object -Property hits -Descending
    )

    $runtimeHits = [UInt64](($putllc16RuntimePeaks | Measure-Object -Property hits -Sum).Sum)
    $runtimeSuccess = [UInt64](($putllc16RuntimePeaks | Measure-Object -Property success -Sum).Sum)
    $runtimeFail = [UInt64](($putllc16RuntimePeaks | Measure-Object -Property fail -Sum).Sum)
    $runtimeAd4Hits = [UInt64](($putllc16RuntimePeaks | Measure-Object -Property pc0ad4_hits -Sum).Sum)
    $runtimeAd4Success = [UInt64](($putllc16RuntimePeaks | Measure-Object -Property pc0ad4_success -Sum).Sum)
    $runtimeC24Hits = [UInt64](($putllc16RuntimePeaks | Measure-Object -Property pc0c24_hits -Sum).Sum)
    $runtimeC24Success = [UInt64](($putllc16RuntimePeaks | Measure-Object -Property pc0c24_success -Sum).Sum)
    $runtimeReservationModes = @(
        $putllc16RuntimePeaks |
            Group-Object -Property putllc16_res |
            Sort-Object -Property Count -Descending |
            ForEach-Object { "{0}={1}" -f $_.Name, $_.Count }
    )

    $lines.Add("- Peak runtime hits: $runtimeHits") | Out-Null
    $lines.Add("- Success / fail: $runtimeSuccess / $runtimeFail") | Out-Null
    $lines.Add("- 0xad4 hits/success: $runtimeAd4Hits / $runtimeAd4Success") | Out-Null
    $lines.Add("- 0xc24 hits/success: $runtimeC24Hits / $runtimeC24Success") | Out-Null
    $lines.Add("- Reservation mode rows: $($runtimeReservationModes -join ', ')") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Reservation | Hits | Success | Fail | 0xad4 Hits | 0xad4 Success | 0xc24 Hits | 0xc24 Success | Last PC | Last EAL | Last LSA | Last Dest | Group | SPU |") | Out-Null
    $lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($putllc16RuntimePeaks | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} | {8} | `{9}` | `{10}` | `{11}` | `{12}` | `{13}` | `{14}` |' -f
            $rank,
            $record.putllc16_res,
            $record.hits,
            $record.success,
            $record.fail,
            $record.pc0ad4_hits,
            $record.pc0ad4_success,
            $record.pc0c24_hits,
            $record.pc0c24_success,
            $record.last_pc,
            $record.last_eal,
            $record.last_lsa,
            $record.last_dest,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("PUTLLC16 runtime reading: this counts actual optimized reservation commits/fails from the JIT pattern. If hot detected patterns barely execute, chase the surrounding loop; if they execute but fail often, the verifier target is reservation state and local-store aliasing rather than GPU compute.") | Out-Null
}

if ($putllc16PairVerifyRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## PUTLLC16 Pair Verify") | Out-Null
    $lines.Add("") | Out-Null

    $pairVerifyPeaks = @(
        $putllc16PairVerifyRecords |
            Group-Object -Property group_name,spu_name,last_pc |
            ForEach-Object {
                $_.Group | Sort-Object -Property hits -Descending | Select-Object -First 1
            } |
            Sort-Object -Property hits -Descending
    )

    $pairHits = [UInt64](($pairVerifyPeaks | Measure-Object -Property hits -Sum).Sum)
    $pairInRange = [UInt64](($pairVerifyPeaks | Measure-Object -Property in_range -Sum).Sum)
    $pairRaddr = [UInt64](($pairVerifyPeaks | Measure-Object -Property raddr_match -Sum).Sum)
    $pairRtime = [UInt64](($pairVerifyPeaks | Measure-Object -Property rtime_match -Sum).Sum)
    $pairMain = [UInt64](($pairVerifyPeaks | Measure-Object -Property main_line_match -Sum).Sum)
    $pairNoExtra = [UInt64](($pairVerifyPeaks | Measure-Object -Property no_extra_dirty -Sum).Sum)
    $pairExtra = [UInt64](($pairVerifyPeaks | Measure-Object -Property extra_dirty -Sum).Sum)
    $pairDecoded = [UInt64](($pairVerifyPeaks | Measure-Object -Property decoded_mask_match -Sum).Sum)
    $pairPattern = [UInt64](($pairVerifyPeaks | Measure-Object -Property pattern_mask_match -Sum).Sum)
    $pairPostHits = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_hits -Sum).Sum)
    $pairPostReady = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_atomic_ready -Sum).Sum)
    $pairPostSuccess = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_success -Sum).Sum)
    $pairPostFailure = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_failure -Sum).Sum)
    $pairPostOther = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_atomic_other -Sum).Sum)
    $pairPostRaddrZero = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_raddr_zero -Sum).Sum)
    $pairPostRaddrSame = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_raddr_same -Sum).Sum)
    $pairPostLrEvent = [UInt64](($pairVerifyPeaks | Measure-Object -Property post_lr_event_set -Sum).Sum)

    $lines.Add("- Peak verify hits: $pairHits") | Out-Null
    $lines.Add("- In-range hits: $pairInRange") | Out-Null
    $lines.Add("- raddr/rtime/main-line matches: $pairRaddr / $pairRtime / $pairMain") | Out-Null
    $lines.Add("- No-extra-dirty / extra-dirty: $pairNoExtra / $pairExtra") | Out-Null
    $lines.Add("- Decoded-mask / pattern-mask matches: $pairDecoded / $pairPattern") | Out-Null
    $lines.Add("- Post stock hits/atomic-ready/success/failure/other: $pairPostHits / $pairPostReady / $pairPostSuccess / $pairPostFailure / $pairPostOther") | Out-Null
    $lines.Add("- Post raddr zero/same and LR-event-set: $pairPostRaddrZero / $pairPostRaddrSame / $pairPostLrEvent") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Hits | In Range | raddr | rtime | Main Line | No Extra Dirty | Extra Dirty | Decoded Match | Pattern Match | Post Success | Post Failure | Last PC | Changed Mask | Decoded Mask | Pattern Mask | Post Atomic | Post RAddr | Group | SPU |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($pairVerifyPeaks | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | `{12}` | `{13}` | `{14}` | `{15}` | `{16}` | `{17}` | `{18}` | `{19}` |' -f
            $rank,
            $record.hits,
            $record.in_range,
            $record.raddr_match,
            $record.rtime_match,
            $record.main_line_match,
            $record.no_extra_dirty,
            $record.extra_dirty,
            $record.decoded_mask_match,
            $record.pattern_mask_match,
            $record.post_success,
            $record.post_failure,
            $record.last_pc,
            $record.last_changed_mask,
            $record.last_decoded_mask,
            $record.last_pattern_mask,
            $record.last_post_atomic,
            $record.last_post_raddr,
            $record.group_name,
            $record.spu_name)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("PUTLLC16 pair verify reading: this is a shadow checker only. It routes actual gameplay through stock PUTLLC while measuring whether the two-slot shortcut would have preserved raddr/rtime, full reservation-line, and local-store dirty-slot assumptions.") | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Repeated Pattern Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Pattern | Records | Sum Total | Max Total | Group | SPU | PC | Max EA |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | --- | --- | --- | --- |") | Out-Null

foreach ($patternGroup in @($records | Group-Object -Property pattern_sig | Sort-Object -Property Count -Descending | Select-Object -First $Top)) {
    $patternRecords = @($patternGroup.Group)
    $patternTop = $patternRecords | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
    $patternSum = [UInt64](($patternRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $lines.Add(('| `{0}` | {1} | {2} | {3} | `{4}` | `{5}` | `{6}` | `{7}` |' -f $patternGroup.Name, $patternGroup.Count, (Format-ProbeBytes $patternSum), (Format-ProbeBytes $patternTop.total_bytes), $patternTop.group_name, $patternTop.spu_name, $patternTop.max_dma_pc, $patternTop.max_dma_ea)) | Out-Null
}

$dmaRecords = @($records | Where-Object { $_.get_payload_bytes -gt 0 -or $_.put_payload_bytes -gt 0 -or $_.repeat_hits -gt 0 -or $_.output_mismatches -gt 0 })
if ($dmaRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## DMA Superpath Verification") | Out-Null
    $lines.Add("") | Out-Null

    $payloadGet = [UInt64](($dmaRecords | Measure-Object -Property get_payload_bytes -Sum).Sum)
    $payloadPut = [UInt64](($dmaRecords | Measure-Object -Property put_payload_bytes -Sum).Sum)
    $sampledGet = [UInt64](($dmaRecords | Measure-Object -Property sampled_get_payload_bytes -Sum).Sum)
    $sampledPut = [UInt64](($dmaRecords | Measure-Object -Property sampled_put_payload_bytes -Sum).Sum)
    $maxRepeat = [UInt64](($dmaRecords | Measure-Object -Property repeat_hits -Maximum).Maximum)
    $maxMismatch = [UInt64](($dmaRecords | Measure-Object -Property output_mismatches -Maximum).Maximum)

    $lines.Add("- Payload GET bytes: $(Format-ProbeBytes $payloadGet)") | Out-Null
    $lines.Add("- Payload PUT bytes: $(Format-ProbeBytes $payloadPut)") | Out-Null
    $lines.Add("- Sampled GET bytes: $(Format-ProbeBytes $sampledGet)") | Out-Null
    $lines.Add("- Sampled PUT bytes: $(Format-ProbeBytes $sampledPut)") | Out-Null
    $lines.Add("- Max repeat hits for a seen input/output key: $maxRepeat") | Out-Null
    $lines.Add("- Max output mismatches for a seen input key: $maxMismatch") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Image | Pattern | Input Hash | Output Hash | Repeats | Mismatches | GET Payload | PUT Payload | Sampled GET | Sampled PUT | Group | SPU | PC |") | Out-Null
    $lines.Add("| ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($dmaRecords | Sort-Object -Property repeat_hits, total_bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | `{4}` | {5} | {6} | {7} | {8} | {9} | {10} | `{11}` | `{12}` | `{13}` |' -f $rank, $record.image_sig, $record.pattern_sig, $record.get_payload_hash, $record.put_payload_hash, $record.repeat_hits, $record.output_mismatches, (Format-ProbeBytes $record.get_payload_bytes), (Format-ProbeBytes $record.put_payload_bytes), (Format-ProbeBytes $record.sampled_get_payload_bytes), (Format-ProbeBytes $record.sampled_put_payload_bytes), $record.group_name, $record.spu_name, $record.max_dma_pc)) | Out-Null
        $rank++
    }
}

if ($rsxRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## RSX-Local Candidates") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Group | SPU | Total | RSX GET | RSX PUT | Image | PC | EA |") | Out-Null
    $lines.Add("| ---: | --- | --- | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($rsxRecords | Sort-Object -Property rsx_get_bytes, rsx_put_bytes, total_bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | {3} | {4} | {5} | `{6}` | `{7}` | `{8}` |' -f $rank, $record.group_name, $record.spu_name, (Format-ProbeBytes $record.total_bytes), (Format-ProbeBytes $record.rsx_get_bytes), (Format-ProbeBytes $record.rsx_put_bytes), $record.image_sig, $record.max_dma_pc, $record.max_dma_ea)) | Out-Null
        $rank++
    }
}

if ($rsxResourceGroups.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Indirect RSX Resource Overlap") | Out-Null
    $lines.Add("") | Out-Null

    if ($rsxOverlapRecords.Count -eq 0) {
        $lines.Add("No sampled SPU max-DMA or MFC-shape EA range overlapped the profiled RSX resolve/blit/texture resources in this log.") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("Reading: this does not prove the game never feeds RSX from SPU work, but it means this capture did not expose a safe CPU-to-GPU producer-consumer target. Keep looking for nonzero overlap before building Vulkan compute for SPU jobs.") | Out-Null
    } else {
        $lines.Add("| Rank | Source | PC | DMA Range | Overlap | Resource | Role | Resource Range | Count | Format | Group | SPU |") | Out-Null
        $lines.Add("| ---: | --- | --- | --- | ---: | --- | --- | --- | ---: | --- | --- | --- |") | Out-Null

        $rank = 1
        foreach ($record in @($rsxOverlapRecords | Sort-Object -Property overlap_bytes, resource_count -Descending | Select-Object -First $Top)) {
            $lines.Add(('| {0} | `{1}` | `{2}` | `{3}`-`{4}` | {5} | `{6}` | `{7}` | `{8}`-`{9}` | {10} | `{11}` | `{12}` | `{13}` |' -f
                $rank,
                $record.source_type,
                $record.pc,
                $record.dma_start,
                $record.dma_end,
                $record.overlap_bytes_pretty,
                $record.resource_kind,
                $record.resource_role,
                $record.resource_base,
                $record.resource_end,
                $record.resource_count,
                $record.resource_format,
                $record.group_name,
                $record.spu_name)) | Out-Null
            $rank++
        }

        $lines.Add("") | Out-Null
        $lines.Add("Reading: overlap is only a scout signal. Promote it to a GPU superpath candidate only after output verification proves the SPU-produced bytes are consumed by RSX without a critical-path CPU readback.") | Out-Null
    }
}

if ($rsxAuditorRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## RSX Auditor Snapshot") | Out-Null
    $lines.Add("") | Out-Null

    $auditorFrames = [UInt64](($rsxAuditorRecords | Measure-Object -Property frames -Sum).Sum)
    $auditorSubmits = [UInt64](($rsxAuditorRecords | Measure-Object -Property submits -Sum).Sum)
    $auditorHardSync = [UInt64](($rsxAuditorRecords | Measure-Object -Property hard_sync -Sum).Sum)
    $auditorRenderPassBreaks = [UInt64](($rsxAuditorRecords | Measure-Object -Property rp_break -Sum).Sum)
    $auditorDetile = [UInt64](($rsxAuditorRecords | Measure-Object -Property detile -Sum).Sum)
    $auditorUploads = [UInt64](($rsxAuditorRecords | Measure-Object -Property simple_upload -Sum).Sum)

    $lines.Add("- Auditor frames: $auditorFrames") | Out-Null
    $lines.Add("- Queue submits: $auditorSubmits") | Out-Null
    $lines.Add("- Hard sync flushes: $auditorHardSync") | Out-Null
    $lines.Add("- Render-pass barrier breaks: $auditorRenderPassBreaks") | Out-Null
    $lines.Add("- Detile jobs: $auditorDetile") | Out-Null
    $lines.Add("- Simple uploads: $auditorUploads") | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add('- High `total/list` bytes with zero RSX traffic is still valuable, but it points first at SPU/kernel replacement, NEON, scheduler, or verified CPU superpaths.') | Out-Null
$lines.Add('- Nonzero `RSX GET/PUT` is the stronger Vulkan compute or GPU-resident superpath signal, especially if it repeats in field, battle, and menu.') | Out-Null
$lines.Add("- Do not claim FPS wins from this summary. Pair it with normalized host grade and visual proof.") | Out-Null

$lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "GPU probe summary: $OutPath"
Write-Host "GPU probe CSV: $CsvPath"
