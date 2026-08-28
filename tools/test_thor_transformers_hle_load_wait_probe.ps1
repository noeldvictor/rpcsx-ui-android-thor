$ErrorActionPreference = "Stop"

$sourcePath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\perf_monitor.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredFragments = @(
    'pc == 0x009e4ba4u',
    'static_cast<u32>(ppu.lr) == 0x005a3350u',
    'const u32 object = static_cast<u32>(ppu.gpr[29]);',
    'vm::check_addr(object, 0, 0x5b0)',
    '"Thor LOAD WAIT:',
    '"Thor LOAD COUNTS:',
    'object + 0x584',
    'object + 0x588',
    'object + 0x58c',
    'object + 0x594',
    'object + 0x598'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "The Transformers HLE load-wait probe is missing: $fragment"
    }
}

Write-Output "Transformers HLE load-wait probe contract passed."
