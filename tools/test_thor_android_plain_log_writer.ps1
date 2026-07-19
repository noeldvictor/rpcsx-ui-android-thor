$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/logs.cpp"
$androidPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
$collectorPath = Join-Path $repoRoot "tools/collect_thor_debug.ps1"
$snapshotPath = Join-Path $repoRoot "tools/thor_debug_common.ps1"

$source = Get-Content -LiteralPath $sourcePath -Raw
$androidSource = Get-Content -LiteralPath $androidPath -Raw
$collector = Get-Content -LiteralPath $collectorPath -Raw
$snapshot = Get-Content -LiteralPath $snapshotPath -Raw

# Every gzip-only line must sit in a desktop-only preprocessor branch. Track
# nested directives so platform sub-branches inside those blocks remain valid.
$frames = [System.Collections.Generic.List[object]]::new()
$lines = $source -split "\r?\n"
$compressedPattern = 'm_fout2|m_zs|m_zout|z_stream|deflate(?:Init2|End)?\b|Z_(?:DEFLATED|DEFAULT_STRATEGY|STREAM_ERROR|NO_FLUSH|FINISH)|<zlib\.h>|%s\.gz'

for ($index = 0; $index -lt $lines.Count; $index++) {
    $line = $lines[$index]
    $trimmed = $line.Trim()

    if ($trimmed -match '^#\s*ifndef\s+ANDROID\s*$') {
        $frames.Add([pscustomobject]@{ Kind = 'ifndef-android'; DesktopOnly = $true })
        continue
    }

    if ($trimmed -match '^#\s*ifdef\s+ANDROID\s*$') {
        $frames.Add([pscustomobject]@{ Kind = 'ifdef-android'; DesktopOnly = $false })
        continue
    }

    if ($trimmed -match '^#\s*(?:if|ifdef|ifndef)\b') {
        $frames.Add([pscustomobject]@{ Kind = 'other'; DesktopOnly = $false })
        continue
    }

    if ($trimmed -match '^#\s*(?:else|elif)\b') {
        if ($frames.Count -eq 0) {
            throw "Unbalanced preprocessor branch at logs.cpp:$($index + 1)."
        }

        $frame = $frames[$frames.Count - 1]
        if ($frame.Kind -eq 'ifndef-android') {
            $frame.DesktopOnly = $false
        } elseif ($frame.Kind -eq 'ifdef-android' -and $trimmed -match '^#\s*else\b') {
            $frame.DesktopOnly = $true
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

    if ($line -match $compressedPattern) {
        $isDesktopOnly = $false
        foreach ($frame in $frames) {
            if ($frame.DesktopOnly) {
                $isDesktopOnly = $true
                break
            }
        }

        if (-not $isDesktopOnly) {
            throw "Android logging still compiles a gzip-only fragment at logs.cpp:$($index + 1): $trimmed"
        }
    }
}

if ($frames.Count -ne 0) {
    throw "Unbalanced preprocessor directives in logs.cpp."
}

$requiredPlainFragments = @(
    'm_fout.open(name, fs::rewrite)',
    'm_fout.write(m_fptr.get() + out_index, size)',
    'm_fout.sync();',
    'm_fout.close();',
    'const u64 size = std::min<u64>(end - read_pos, s_log_write_chunk_size);'
)

foreach ($fragment in $requiredPlainFragments) {
    if (-not $source.Contains($fragment)) {
        throw "Android plain log writer lost required behavior: $fragment"
    }
}

if ($source -notmatch '#ifdef ANDROID\s+if \(m_out >= m_max_size \|\| !m_fout\)\s+#else\s+if \(m_out >= m_max_size \|\| \(!m_fout && !m_fout2\)\)\s+#endif') {
    throw "Android logging inactivity no longer depends only on the plain output."
}

$requiredDesktopFragments = @(
    'm_fout2.open(name + ".gz", fs::rewrite + fs::unread)',
    'deflateInit2(&m_zs, 9, Z_DEFLATED, 16 + 15, 9, Z_DEFAULT_STRATEGY)',
    'deflate(&m_zs, Z_NO_FLUSH)',
    'deflate(&m_zs, Z_FINISH)',
    'deflateEnd(&m_zs)',
    'uchar m_zout[65536]{};',
    'm_zs.next_out = m_zout;'
)

foreach ($fragment in $requiredDesktopFragments) {
    if (-not $source.Contains($fragment)) {
        throw "Desktop compressed logging compatibility was removed: $fragment"
    }
}

if (-not $androidSource.Contains('logs::make_file_listener(fs::get_log_dir() + "RPCSX.log"')) {
    throw "Android no longer creates the plain RPCSX.log listener."
}

foreach ($plainTarget in @('RPCSX.log"; Local = "cache/RPCSX.log', 'RPCSX.old.log"; Local = "cache/RPCSX.old.log')) {
    if (-not $collector.Contains($plainTarget)) {
        throw "Thor collector lost a required plain log target: $plainTarget"
    }
}

if ($collector.Contains('RPCSX.log.gz')) {
    throw "Thor collector still expects the Android-only compressed duplicate."
}

if (-not $snapshot.Contains('$remoteRoot/cache/RPCSX.log')) {
    throw "Thor standard snapshots no longer preserve the plain runtime log."
}

foreach ($path in @($collectorPath, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -ne 0) {
        throw ("PowerShell contract parse failed for {0}: {1}" -f $path, $errors[0].Message)
    }
}

Write-Output "Thor Android log writer contract passed: plain diagnostics remain, live gzip work is desktop-only, and collectors no longer expect the duplicate."
