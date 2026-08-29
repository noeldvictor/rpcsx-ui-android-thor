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
    's_load_wait_dumps.load() < 18',
    '"Thor LOAD SOURCE:',
    'data_vtable + 0x3c',
    'data_vtable + 0x50',
    'vm::check_addr(data, 0, 0xd0)',
    '"Thor LOAD RANGE:',
    'data + 0x98',
    'data + 0xc0',
    'data + 0xc4',
    'data + 0xc8',
    'const u32 range_table =',
    'vm::check_addr(range_table, 0, 0x20)',
    '"Thor LOAD IO:',
    'data + 0x88',
    'range_table + 0x1c',
    'vm::check_addr(0x019d5410u, 0, 4)',
    'io_manager + 4',
    'io_manager + 8',
    'vm::check_addr(io_workers, 0, 4)',
    'vm::check_addr(io_worker_vtable, 0, 0x50)',
    'io_worker_vtable + 0x0c',
    'io_worker_vtable + 0x10',
    'io_worker_vtable + 0x40',
    'io_worker_vtable + 0x48',
    'io_worker_vtable + 0x4c',
    '"Thor LOAD IO VT:',
    '"Thor LOAD IO BACKEND:',
    'vm::check_addr(io_worker, 0, 0x78)',
    '"Thor LOAD IO STATE:',
    'io_worker + 0x4c',
    'io_worker + 0x50',
    'io_worker + 0x58',
    'io_worker + 0x5c',
    'io_worker + 0x64',
    'io_worker + 0x6c',
    'io_worker + 0x70',
    'vm::check_addr(io_active, 0, 0x50)',
    '"Thor LOAD IO ACTIVE 00:',
    '"Thor LOAD IO ACTIVE 20:',
    '"Thor LOAD IO ACTIVE 40:',
    'const u32 completion_entries =',
    'const u32 completion_item =',
    'const u32 completion_state =',
    'vm::check_addr(completion_state, 0, 4)',
    '"Thor LOAD IO COMPLETION:',
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
