$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$spuSource = Get-Content -LiteralPath $spuPath -Raw
$match = [regex]::Match($spuSource, '(?s)void SELB\(spu_opcode_t op\).*?(?=\s+void SHUFB\(spu_opcode_t op\))')

if (-not $match.Success) {
    throw "Could not isolate the SPU SELB lowering."
}

$selb = $match.Value
$requiredFragments = @(
    'auto [select_match, sel_bool] = match_expr',
    'if (!select_match)',
    'auto quot = match_vr<f32[4]>(op.ra);',
    'auto quot_offset = match_vr<s32[4]>(op.rb);',
    'const auto [errcmp_match, div_err, fone] = match_expr',
    'const auto [divoffset_match] = match_expr',
    'const auto [div_match, nume, denom] = match_expr',
    'const auto [diverr_match] = match_expr',
    'std::bit_cast<uint32_t>(1.0f)',
    'set_vr(op.rt4, nume / denom);',
    '// Don''t ruin FSMB/FSM/FSMH instructions',
    'select(sel_bool, get_vr<VT>(op.rb), get_vr<VT>(op.ra))',
    'unsigned byte_granularity = 16;',
    'for (u8 cur_elt : mask._u8.data)',
    'switch (byte_granularity)',
    'match_vrs<f64[4]>(op.ra, op.rb)',
    'match_vrs<f32[4]>(op.ra, op.rb)',
    'select(bitcast<s8[16]>(c) != 0',
    'const auto m = conv_xfloat_mask(c.value);',
    'set_vr(op.rt4, (get_vr(op.rb) & c) | (get_vr(op.ra) & ~c));'
)

foreach ($fragment in $requiredFragments) {
    if (-not $selb.Contains($fragment)) {
        throw "Missing SPU SELB refactor or fallback fragment: $fragment"
    }
}

$legacyFragments = @(
    'if (auto [ok, x] = match_expr',
    'bool sel_32',
    'bool sel_16',
    'bool sel_8',
    '0x3f800000'
)

foreach ($fragment in $legacyFragments) {
    if ($selb.Contains($fragment)) {
        throw "Legacy SPU SELB matcher or repeated mask scan remains: $fragment"
    }
}

$maskScanCount = [regex]::Matches($selb, [regex]::Escape('for (u8 cur_elt : mask._u8.data)')).Count
if ($maskScanCount -ne 1) {
    throw "Expected exactly one SPU SELB constant-mask scan; found $maskScanCount."
}

Write-Output "Thor SPU SELB contract passed: comparison matching is flat, constant masks use one granularity scan, and all semantic fallbacks remain."
