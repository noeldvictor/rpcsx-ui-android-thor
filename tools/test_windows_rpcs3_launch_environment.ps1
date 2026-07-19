$ErrorActionPreference = "Stop"

$labPath = Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1"
if (-not (Test-Path -LiteralPath $labPath -PathType Leaf)) {
    throw "Missing Windows RPCS3 lab launcher: $labPath"
}

$source = Get-Content -LiteralPath $labPath -Raw

foreach ($fragment in @(
    '[Environment]::GetEnvironmentVariables("Process")',
    '$_.Name -ceq "PATH"',
    '[Environment]::SetEnvironmentVariable($pathVariable.Name, $null, "Process")',
    '[Environment]::SetEnvironmentVariable("Path", "$qtBin;$vcpkgBin;$inheritedPath", "Process")',
    '$processStartInfo.UseShellExecute = $false',
    '$processStartInfo.RedirectStandardOutput = $true',
    '$processStartInfo.RedirectStandardError = $true',
    '$stdoutReadTask = $process.StandardOutput.ReadToEndAsync()',
    '$stderrReadTask = $process.StandardError.ReadToEndAsync()'
)) {
    if (-not $source.Contains($fragment)) {
        throw "Windows RPCS3 launcher is missing its canonical environment or output-capture contract: $fragment"
    }
}

if ($source.Contains('$env:PATH = "$qtBin;$vcpkgBin;$env:PATH"')) {
    throw "Windows RPCS3 launcher must not use the PowerShell environment drive while case-variant Path entries exist."
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $labPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    throw ("PowerShell parse failure in {0}: {1}" -f $labPath, $errors[0].Message)
}

Write-Output "Windows RPCS3 launch environment contract passed: Path is canonicalized and redirected process output remains captured."
