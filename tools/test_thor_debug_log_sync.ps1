$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$paths = @{
    Core = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
    Logs = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/logs.cpp"
    Wrapper = Join-Path $repoRoot "app/src/main/cpp/native-lib.cpp"
    KotlinApi = Join-Path $repoRoot "app/src/main/java/net/rpcsx/RPCSX.kt"
    Receiver = Join-Path $repoRoot "app/src/debug/java/net/rpcsx/ThorDebugLogReceiver.kt"
    Manifest = Join-Path $repoRoot "app/src/debug/AndroidManifest.xml"
    Macro = Join-Path $repoRoot "tools/thor_input_macro.ps1"
}

$source = @{}
foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Thor debug log-sync surface is missing: $($entry.Value)"
    }
    $source[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

$contracts = @(
    @{ Key = 'Core'; Text = 'extern "C" u64 _rpcsx_syncLogs()' },
    @{ Key = 'Core'; Text = 'rpcsx_android.always()("Thor debug log sync checkpoint: %u.", checkpoint);' },
    @{ Key = 'Core'; Text = 'logs::listener::sync_all();' },
    @{ Key = 'Core'; Text = 'return checkpoint;' },
    @{ Key = 'Logs'; Text = 'if (!(bufv % s_log_size) && flush(bufv))' },
    @{ Key = 'Wrapper'; Text = 'uint64_t (*syncLogs)();' },
    @{ Key = 'Wrapper'; Text = 'dlsym(handle, "_rpcsx_syncLogs")' },
    @{ Key = 'Wrapper'; Text = 'Java_net_rpcsx_RPCSX_syncLogs' },
    @{ Key = 'KotlinApi'; Text = 'external fun syncLogs(): Long' },
    @{ Key = 'Receiver'; Text = 'RPCSX.instance.syncLogs()' },
    @{ Key = 'Receiver'; Text = 'Activity.RESULT_OK' },
    @{ Key = 'Receiver'; Text = 'const val RESULT_CHECKPOINT_PREFIX = "checkpoint:"' },
    @{ Key = 'Receiver'; Text = 'const val ACTION = "net.rpcsx.THOR_DEBUG_SYNC_LOG"' },
    @{ Key = 'Manifest'; Text = 'android:name="net.rpcsx.ThorDebugLogReceiver"' },
    @{ Key = 'Manifest'; Text = '<action android:name="net.rpcsx.THOR_DEBUG_SYNC_LOG" />' },
    @{ Key = 'Macro'; Text = 'function Sync-ThorGuestLogEvidence' },
    @{ Key = 'Macro'; Text = 'am broadcast --receiver-foreground -a net.rpcsx.THOR_DEBUG_SYNC_LOG' },
    @{ Key = 'Macro'; Text = '$syncEvidence = Sync-ThorGuestLogEvidence $Label' },
    @{ Key = 'Macro'; Text = 'Thor debug log sync checkpoint: $($syncEvidence.Sequence).' }
)
foreach ($contract in $contracts) {
    if (-not $source[$contract.Key].Contains($contract.Text)) {
        throw "Thor debug log-sync contract is missing from $($contract.Key): $($contract.Text)"
    }
}

$assertStart = $source.Macro.IndexOf('function Assert-ThorGuestHealthy')
$syncCall = $source.Macro.IndexOf('Sync-ThorGuestLogEvidence $Label', $assertStart)
$pullCall = $source.Macro.IndexOf('$evidence = Save-ThorGuestLogEvidence $Label', $assertStart)
$checkpointCall = $source.Macro.IndexOf('$checkpoint = "Thor debug log sync checkpoint:', $pullCall)
$fatalScan = $source.Macro.IndexOf('$fatalMatches = @(', $checkpointCall)
if ($assertStart -lt 0 -or $syncCall -le $assertStart -or $pullCall -le $syncCall -or
    $checkpointCall -le $pullCall -or $fatalScan -le $checkpointCall) {
    throw "Thor guest-health evidence must synchronize the native log before reading it."
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $paths.Macro,
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -ne 0) {
    throw "Thor input macro parse failed: $($errors[0].Message)"
}

Write-Output "Thor debug log-sync contract passed: debug broadcast, unique native checkpoint, caller-side drain, and post-pull durability proof are connected."
