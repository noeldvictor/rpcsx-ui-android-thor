$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredFragments = @(
    'class vector_memory_buffer final : public llvm::MemoryBuffer',
    'std::vector<u8> m_data;',
    'm_data.push_back(0);',
    'init(begin, begin + m_data.size() - 1, true);',
    'return MemoryBuffer_Malloc;',
    'auto out = unzip(cached_data);',
    'return std::make_unique<vector_memory_buffer>(std::move(out));'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "Missing JIT object-cache buffer contract fragment: $fragment"
    }
}

$compressedStart = $source.IndexOf('if (fs::file cached{path + ".gz", fs::read})')
$rawStart = $source.IndexOf('if (fs::file cached{path, fs::read})', $compressedStart)
if ($compressedStart -lt 0 -or $rawStart -le $compressedStart) {
    throw "Could not isolate the compressed JIT object-cache load path."
}

$compressedPath = $source.Substring($compressedStart, $rawStart - $compressedStart)
foreach ($forbidden in @(
    'WritableMemoryBuffer::getNewUninitMemBuffer(out.size())',
    'std::memcpy(buf->getBufferStart(), out.data(), out.size())'
)) {
    if ($compressedPath.Contains($forbidden)) {
        throw "Compressed JIT object-cache path regained a redundant allocation/copy: $forbidden"
    }
}

$rawEnd = $source.IndexOf('return buf;', $rawStart)
$rawPath = $source.Substring($rawStart, $rawEnd - $rawStart + 'return buf;'.Length)
if (-not $rawPath.Contains('WritableMemoryBuffer::getNewUninitMemBuffer(cached.size())') -or
    -not $rawPath.Contains('cached.read(buf->getBufferStart(), buf->getBufferSize())')) {
    throw "Raw JIT object-cache fallback no longer reads into an LLVM-owned writable buffer."
}

Write-Output "Thor JIT object-cache buffer contract passed: decompressed bytes are moved into an owning LLVM buffer with no second allocation or full memcpy; raw-cache fallback remains intact."
