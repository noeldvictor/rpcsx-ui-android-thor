$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$stqdStart = $source.IndexOf("`tvoid STQD(spu_opcode_t op)")
$haltStart = $source.IndexOf("`tvoid make_halt(value_t<bool> cond)")
if ($stqdStart -lt 0 -or $haltStart -le $stqdStart) {
    throw 'Unable to isolate the STQD/LQD source region.'
}
$source = $source.Substring($stqdStart, $haltStart - $stqdStart)

$matchAdd = 'match_expr(a, match<u32[4]>() + match<u32[4]>())'
$commutedPairs = 'std::initializer_list<std::pair<llvm_match_t<u32[4]>, llvm_match_t<u32[4]>>>{{x, y}, {y, x}}'
$constantProbe = 'get_const_vector(pair.first.value, m_pos)'
$canonicalAddend = 'const u64 addend = (data._u32[3] >= SPU_LS_SIZE) ? make_negative_LS_offset(data._u32[3]) : data._u32[3];'
$alignedGuard = 'if (const u32 remainder = data._u32[3] % 0x10; remainder == 0)'
$canonicalAddress = 'zext<u64>(extract(pair.second, 3) & 0x3fff0) + ((get_imm<u64>(op.si10) << 4) + splat<u64>(addend))'
$genericAddress = 'zext<u64>(extract(a, 3) & 0x3fff0) + (get_imm<u64>(op.si10) << 4)'

foreach ($contract in @(
        @{ Name = 'add-expression match'; Text = $matchAdd; Count = 2 },
        @{ Name = 'commuted operand scan'; Text = $commutedPairs; Count = 2 },
        @{ Name = 'constant operand probe'; Text = $constantProbe; Count = 2 },
        @{ Name = 'canonical constant addend'; Text = $canonicalAddend; Count = 2 },
        @{ Name = 'aligned-only guard'; Text = $alignedGuard; Count = 2 },
        @{ Name = 'canonical specialized address'; Text = $canonicalAddress; Count = 2 },
        @{ Name = 'generic masked fallback'; Text = $genericAddress; Count = 2 }
    )) {
    $count = ([regex]::Matches($source, [regex]::Escape($contract.Text))).Count
    if ($count -ne $contract.Count) {
        throw "Expected $($contract.Count) $($contract.Name) fragments in STQD/LQD; found $count."
    }
}

if ($source.Contains('get_const_vector(x.value, m_pos + 1)') -or
    $source.Contains('get_const_vector(y.value, m_pos + 2)') -or
    $source.Contains('splat<u64>(data._u32[3] & 0x3fff0)')) {
    throw 'The obsolete noncanonical STQD/LQD specialization is present.'
}

Write-Output 'Thor SPU LQD/STQD address contract passed: aligned constant operands use one canonical LS mirror and all other expressions retain the generic masked fallback.'
