[CmdletBinding()]
param(
    [string]$Ndk = "$env:LOCALAPPDATA\Android\Sdk\ndk\29.0.13113456",
    [string]$Abi = "aarch64-linux-android24",
    [string]$Cpu = "cortex-a715",
    [string]$Arch = "armv8.4-a",
    [switch]$Asm
)

$ErrorActionPreference = "Stop"

# Build the bespoke benchmark for the Thor.
#
# Static, so it needs nothing on the device and runs from /data/local/tmp with no
# APK, no emulator boot and no thermal gate for a short run. The target matches
# what the AOT build uses: -march=armv8.4-a -mtune=cortex-a715.

$clang = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\clang++.exe"
if (-not (Test-Path $clang)) { throw "no clang++ at $clang; pass -Ndk" }

$src = Join-Path $PSScriptRoot "thor_bench.cpp"
if (-not (Test-Path $src)) { throw "no source at $src" }

$out = Join-Path $PSScriptRoot "thor_bench"

$flags = @(
    "--target=$Abi", "-O2", "-march=$Arch", "-mtune=$Cpu",
    "-static", "-fno-exceptions", "-fno-rtti", "-Wall", "-Wextra"
)

if ($Asm) {
    & $clang @flags -S -o "$out.s" $src
    if ($LASTEXITCODE -ne 0) { throw "assembly build failed" }
    Write-Output "wrote $out.s"

    # Prove the non-temporal kernel is actually in the binary being timed. A
    # benchmark of a loop that quietly compiled to something else measures the
    # something else.
    $ldnp = (Select-String -Path "$out.s" -Pattern '\bldnp\b' -AllMatches).Matches.Count
    $stnp = (Select-String -Path "$out.s" -Pattern '\bstnp\b' -AllMatches).Matches.Count
    Write-Output "non-temporal instructions in the assembly: ldnp=$ldnp stnp=$stnp"
    if ($ldnp -lt 2 -or $stnp -lt 2) {
        throw "the LDNP/STNP kernel is not in the output, so the memcpy mode would measure the wrong thing"
    }
    return
}

& $clang @flags -o $out $src
if ($LASTEXITCODE -ne 0) { throw "build failed" }

$size = (Get-Item $out).Length
Write-Output "built $out ($size bytes, static $Abi, -march=$Arch -mtune=$Cpu)"
