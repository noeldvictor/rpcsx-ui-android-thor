param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainActivityPath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/MainActivity.kt"
$nativeLoaderPath = Join-Path $repoRoot "app/src/main/cpp/native-lib.cpp"
$source = Get-Content -LiteralPath $mainActivityPath -Raw
$nativeSource = Get-Content -LiteralPath $nativeLoaderPath -Raw

if ($source.Contains("RPCSX.instance.getLibraryVersion")) {
    throw "MainActivity still preloads a core through getLibraryVersion before opening it."
}

if (-not $source.Contains("val hasBundledCore = bundledCore.isFile && bundledCore.canRead()")) {
    throw "MainActivity does not use the cheap bundled-core file preflight."
}

if (-not $source.Contains("if (devCore != null)")) {
    throw "MainActivity no longer selects a readable Thor dev-core override."
}

if (-not $source.Contains("if (devCore == null && (BuildConfig.FORK_BUILD || rpcsxLibrary == null) && hasBundledCore)")) {
    throw "MainActivity no longer selects the bundled core when no dev override is active."
}

$openCalls = [regex]::Matches($source, [regex]::Escape("RPCSX.openLibrary(")).Count
if ($openCalls -ne 2) {
    throw "Expected one primary core open and one bundled fallback, found $openCalls calls."
}

$fallbackPattern = 'if \(!RPCSX\.openLibrary\(rpcsxLibrary\) && hasBundledCore && rpcsxLibrary != bundledCore\.path\) \{[\s\S]*?RPCSX\.openLibrary\(rpcsxLibrary\)'
if ($source -notmatch $fallbackPattern) {
    throw "MainActivity no longer falls back to the bundled core after an open failure."
}

$nativeOpen = $nativeSource.IndexOf("auto library = RPCSXLibrary::Open(libraryPath.c_str());")
$nativeVersionGate = $nativeSource.IndexOf("if (library->getVersion == nullptr)")
$nativeActivate = $nativeSource.IndexOf("rpcsxLib = std::move(*library);")

if ($nativeOpen -lt 0 -or $nativeVersionGate -lt 0 -or $nativeActivate -lt 0) {
    throw "Native core open, version validation, or activation is missing."
}

if (-not ($nativeOpen -lt $nativeVersionGate -and $nativeVersionGate -lt $nativeActivate)) {
    throw "The native core must be opened once, version-validated, then activated."
}

if ([regex]::Matches($nativeSource, [regex]::Escape("RPCSXLibrary::Open(libraryPath.c_str())")).Count -ne 1) {
    throw "The active native core path is opened more than once."
}

Write-Output "Thor single-open core startup contract passed."
