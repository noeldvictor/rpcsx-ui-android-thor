$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "tools/install_thor_apk_no_launch.ps1"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredFragments = @(
    '[ValidatePattern(''^[0-9A-Fa-f]{64}$'')]',
    '[string]$CoolGateCaptureDir',
    'Cool gate is stale',
    'stage=pre-run-',
    'Cool gate must contain exactly one ordered pre-run sample',
    '$coolGateMaximumC -ge 70.0',
    'Host APK hash mismatch',
    '@("install", "-r", $resolvedApk)',
    'am force-stop $Package',
    'pidof $Package',
    'sha256sum ''$remoteApk''',
    'Installed APK hash mismatch',
    'Write-ThorLaunchPowerState',
    'Write-PostInstallThermalSnapshot',
    'Emulator launch: no'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "No-launch installer contract is missing: $fragment"
    }
}

$sourceWithoutSafeGateMetadata = $source.Replace('"- BootGame: False"', '')
if ([regex]::IsMatch($sourceWithoutSafeGateMetadata, '(?i)\bam\s+start\b|\bmonkey\b|\bBootGame\b')) {
    throw "The no-launch installer contains an activity-launch path."
}

$forceStopCount = [regex]::Matches($source, [regex]::Escape('am force-stop $Package')).Count
$pidCheckCount = [regex]::Matches($source, [regex]::Escape('pidof $Package')).Count
if ($forceStopCount -lt 2 -or $pidCheckCount -lt 2) {
    throw "The installer must force-stop and verify PID absence before and after installation."
}

Write-Output "Thor no-launch APK installer contract passed: one fresh sample below 70 C, host/device hashes, and a stopped PID are required, with no activity start path."
