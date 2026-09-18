$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repo "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$required = @(
    '"state":"0x%x"',
    'static_cast<u32>(spu.state.load())'
)

foreach ($fragment in $required) {
    if (-not $source.Contains($fragment)) {
        throw "The Thor SPU diagnostic state field is missing: $fragment"
    }
}

Write-Host "Thor SPU diagnostic state contract passed."
