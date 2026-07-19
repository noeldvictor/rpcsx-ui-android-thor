$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$graphicsFrame = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/java/net/rpcsx/GraphicsFrame.kt") -Raw
$displayPolicy = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/java/net/rpcsx/performance/ThorDisplayPacing.kt") -Raw
$gameSettings = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt") -Raw
$inputMacroPath = Join-Path $repoRoot "tools/thor_input_macro.ps1"
$inputMacro = Get-Content -LiteralPath $inputMacroPath -Raw
$profilePath = Join-Path $repoRoot "tools/push_eternal_sonata_thor_profile.ps1"
$profile = Get-Content -LiteralPath $profilePath -Raw

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )

    if (-not $Text.Contains($Needle)) {
        throw $Message
    }
}

Assert-Contains $displayPolicy 'ETERNAL_SONATA_TITLE_ID = "BLUS30161"' "Display pacing is not title-gated."
Assert-Contains $displayPolicy 'ETERNAL_SONATA_FRAME_RATE = 30f' "Display pacing no longer targets Eternal Sonata's 30 FPS cap."
Assert-Contains $graphicsFrame 'Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS' "Display pacing may perform a disruptive refresh-rate switch."
Assert-Contains $graphicsFrame 'Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE' "Pre-Android-16 display pacing compatibility is missing."
Assert-Contains $gameSettings 'Force FIFO present mode: true' "The managed Eternal Sonata profile no longer selects FIFO presentation."
Assert-Contains $inputMacro '[string]$ThorDisplayPacing = "on"' "The one-APK display-pacing A/B switch is missing."
Assert-Contains $inputMacro '--ez thorDisplayPacing $thorDisplayPacingValue' "The display-pacing switch is not forwarded to the debug boot intent."
Assert-Contains $profile '[string]$ForceFifoPresent = "Off"' "The FIFO A/B profile switch is missing."
Assert-Contains $profile 'Force FIFO present mode: $forceFifoPresentValue' "The FIFO A/B switch is not written to the profile."

foreach ($scriptPath in @($inputMacroPath, $profilePath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -ne 0) {
        throw "PowerShell parse failed for $scriptPath`: $($errors -join '; ')"
    }
}

Write-Host "Thor display-pacing contracts passed."
