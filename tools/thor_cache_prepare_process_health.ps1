function Test-ThorCachePrepareNativeProcessDeath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogText,
        [Parameter(Mandatory = $true)]
        [string]$Package
    )

    $escapedPackage = [regex]::Escape($Package)
    return $LogText -match "(?m)Fatal signal [0-9]+ .*\bpid [0-9]+ \($escapedPackage\)" -or
        $LogText -match "(?m)Process $escapedPackage \(pid [0-9]+\) has died"
}