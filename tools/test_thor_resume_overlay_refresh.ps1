$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/System.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$resumeStart = $source.IndexOf("void Emulator::Resume()")
$resumeEnd = $source.IndexOf("u64 get_sysutil_cb_manager_read_count();", $resumeStart)
if ($resumeStart -lt 0 -or $resumeEnd -le $resumeStart) {
    throw "The emulator resume function was not found."
}

$resume = $source.Substring($resumeStart, $resumeEnd - $resumeStart)
$clear = "m_pause_msgs_refs.clear();"
$refresh = "rsx::set_native_ui_flip();"
$clearIndex = $resume.IndexOf($clear)
$refreshIndex = $resume.IndexOf($refresh)

if ($clearIndex -lt 0) {
    throw "Resume does not clear the pause message references."
}

if ($refreshIndex -le $clearIndex) {
    throw "Resume does not request a native UI flip after it clears the pause message."
}

Write-Output "Thor resume overlay refresh contract passed."
