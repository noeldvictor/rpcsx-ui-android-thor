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
    'object + 0x598',
    's_load_wait_dumps.load() < 3',
    '"Thor LOAD SOURCE:',
    'data_vtable + 0x3c',
    'data_vtable + 0x50',
    'vm::check_addr(data, 0, 0xd0)',
    '"Thor LOAD RANGE:',
    'data + 0x98',
    'data + 0xc0',
    'data + 0xc4',
    'data + 0xc8',
    '"Thor LOAD DATA 00:',
    '"Thor LOAD DATA 20:',
    '"Thor LOAD DATA 40:'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "The Transformers HLE load-wait probe is missing: $fragment"
    }
}

Write-Output "Transformers HLE load-wait probe contract passed."
