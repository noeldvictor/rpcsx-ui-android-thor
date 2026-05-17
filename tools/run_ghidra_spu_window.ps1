param(
    [Parameter(Mandatory = $true)]
    [string[]] $DisasmPath,

    [string[]] $Addresses = @(),

    [string] $GhidraHome = "C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\ghidra_12.0.4_PUBLIC",

    [string] $OutDir = "",

    [string] $WindowBytes = "0x50",

    [int] $ImageSize = 262144
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-HexOrDecimalToInt {
    param([Parameter(Mandatory = $true)][string] $Value)

    $trimmed = $Value.Trim()
    if ($trimmed.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToInt32($trimmed.Substring(2), 16)
    }

    return [Convert]::ToInt32($trimmed, 10)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$headless = Join-Path $GhidraHome "support\analyzeHeadless.bat"
$spuSla = Join-Path $GhidraHome "Ghidra\Processors\SPU\data\languages\spu.sla"
$ghidraScript = Join-Path $repoRoot "tools\ghidra_scripts\DisassembleSpuWindows.java"

if (!(Test-Path -LiteralPath $headless)) {
    throw "Ghidra headless runner not found: $headless"
}

if (!(Test-Path -LiteralPath $spuSla)) {
    throw "GhidraSPU language is not installed: $spuSla"
}

if (!(Test-Path -LiteralPath $ghidraScript)) {
    throw "SPU window Ghidra script not found: $ghidraScript"
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path $repoRoot "debug-captures\ghidra-spu-window-$stamp"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$image = New-Object byte[] $ImageSize
$focusAddresses = New-Object System.Collections.Generic.List[string]
$parsedInstructionCount = 0
$sourceFiles = New-Object System.Collections.Generic.List[string]

foreach ($path in $DisasmPath) {
    $resolvedPath = (Resolve-Path -LiteralPath $path).Path
    $sourceFiles.Add($resolvedPath) | Out-Null

    foreach ($line in Get-Content -LiteralPath $resolvedPath) {
        if ($line -match '^focus_pc=(0x[0-9a-fA-F]+)$' -and $Addresses.Count -eq 0) {
            $focusAddresses.Add($Matches[1]) | Out-Null
            continue
        }

        if ($line -notmatch '^\s*([0-9a-fA-F]{8}):\s+([0-9a-fA-F]{2})\s+([0-9a-fA-F]{2})\s+([0-9a-fA-F]{2})\s+([0-9a-fA-F]{2})\s+') {
            continue
        }

        $address = [Convert]::ToInt32($Matches[1], 16)
        if ($address + 4 -gt $image.Length) {
            throw "Instruction at 0x$($Matches[1]) exceeds image size $ImageSize in $resolvedPath"
        }

        for ($i = 0; $i -lt 4; $i++) {
            $image[$address + $i] = [Convert]::ToByte($Matches[$i + 2], 16)
        }

        $parsedInstructionCount++
    }
}

if ($Addresses.Count -gt 0) {
    $focusAddresses.Clear()
    foreach ($address in $Addresses) {
        $focusAddress = Convert-HexOrDecimalToInt $address
        $focusAddresses.Add(("0x{0:x}" -f $focusAddress)) | Out-Null
    }
}

if ($focusAddresses.Count -eq 0) {
    throw "No focus addresses supplied or found in focus_pc headers."
}

$windowBytesInt = Convert-HexOrDecimalToInt $WindowBytes
$imagePath = Join-Path $OutDir "spu-hot-window-image.bin"
$ghidraOut = Join-Path $OutDir "spu-hot-window-ghidra.txt"
$headlessLog = Join-Path $OutDir "ghidra-headless.log"
$summaryPath = Join-Path $OutDir "summary.json"

[System.IO.File]::WriteAllBytes($imagePath, $image)

$summary = [ordered]@{
    source_files = @($sourceFiles)
    image_path = $imagePath
    ghidra_output = $ghidraOut
    parsed_instruction_count = $parsedInstructionCount
    addresses = @($focusAddresses)
    window_bytes = ("0x{0:x}" -f $windowBytesInt)
    ghidra_home = $GhidraHome
    processor = "SPU:BE:128:default"
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$ghidraArgs = @(
    $OutDir,
    "spu_window",
    "-import", $imagePath,
    "-processor", "SPU:BE:128:default",
    "-cspec", "default",
    "-loader-baseAddr", "0x0",
    "-noanalysis",
    "-postScript", "DisassembleSpuWindows.java", $ghidraOut, ("0x{0:x}" -f $windowBytesInt)
)
$ghidraArgs += @($focusAddresses)
$ghidraArgs += @(
    "-scriptPath", (Join-Path $repoRoot "tools\ghidra_scripts"),
    "-deleteProject"
)

& $headless @ghidraArgs 2>&1 | Tee-Object -FilePath $headlessLog | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Ghidra headless failed with exit code $LASTEXITCODE"
}

Write-Host "Wrote $ghidraOut"
