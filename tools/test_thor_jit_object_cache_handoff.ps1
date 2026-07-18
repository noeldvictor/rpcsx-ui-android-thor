$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$jitHeader = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JIT.h") -Raw
$jitSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp") -Raw
$ppuSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp") -Raw

$contracts = @(
    @{
        Name = "JIT interface"
        Source = $jitHeader
        Required = @(
            'struct jit_memory_buffer_deleter final',
            'using jit_object_buffer = std::unique_ptr<llvm::MemoryBuffer, jit_memory_buffer_deleter>;',
            'bool add(const std::string& path, jit_object_buffer cache = {});',
            'static jit_object_buffer check(const std::string& path);'
        )
    },
    @{
        Name = "JIT implementation"
        Source = $jitSource
        Required = @(
            'void jit_memory_buffer_deleter::operator()(llvm::MemoryBuffer* buffer) const noexcept',
            'bool jit_compiler::add(const std::string& path, jit_object_buffer cache)',
            'owned_cache.reset(cache.release());',
            'owned_cache = ObjectCache::load(path);',
            'jit_object_buffer jit_compiler::check(const std::string& path)',
            'return jit_object_buffer{cache.release()};'
        )
    },
    @{
        Name = "PPU warm-cache handoff"
        Source = $ppuSource
        Required = @(
            'struct ppu_link_work',
            'jit_object_buffer validated_cache;',
            'bool retain_validated_cache = true;',
            'u32 retained_validated_count = 0;',
            'if (auto validated_cache = jit_compiler::check(cache_path + obj_name))',
            'link_workload.back().validated_cache = std::move(validated_cache);',
            'retained_validated_count++;',
            'retain_validated_cache = false;',
            'retained_validated_count = 0;',
            'link.validated_cache.reset();',
            'std::move(link.validated_cache)',
            'LLVM: Reusing %u validated warm-cache object buffers.'
        )
    }
)

foreach ($contract in $contracts) {
    foreach ($fragment in $contract.Required) {
        if (-not $contract.Source.Contains($fragment)) {
            throw "Missing $($contract.Name) contract fragment: $fragment"
        }
    }
}

if ($ppuSource.Contains('if (jit_compiler::check(cache_path + obj_name))')) {
    throw "PPU warm-cache discovery still discards the validated object buffer."
}

$missIndex = $ppuSource.IndexOf('retain_validated_cache = false;')
$compileIndex = $ppuSource.IndexOf('// Fill workload list for compilation', $missIndex)
if ($missIndex -lt 0 -or $compileIndex -le $missIndex) {
    throw "Partial-cache retention is no longer disabled before compilation."
}

$linkIndex = $ppuSource.IndexOf('for (auto& link : link_workload)')
$moveIndex = $ppuSource.IndexOf('std::move(link.validated_cache)', $linkIndex)
if ($linkIndex -lt 0 -or $moveIndex -le $linkIndex) {
    throw "Validated PPU objects are no longer moved into the linking JIT."
}

Write-Output "Thor JIT object-cache handoff contract passed: all-hit warm sets reuse validated buffers, while any miss releases retained buffers before compilation."
