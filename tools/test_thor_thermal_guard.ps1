param(
    [string]$CaptureRoot = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "thor_debug_common.ps1")

function Assert-ThorEqual {
    param(
        [string]$Name,
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name failed: expected '$Expected', got '$Actual'."
    }
}

function New-ThorTestSnapshot {
    param(
        [AllowNull()][object]$Battery,
        [AllowNull()][object]$Skin,
        [AllowNull()][object]$Silicon,
        [int]$SkinSensorCount,
        [int]$SiliconSensorCount,
        [int]$GuardSensorCount
    )

    return [pscustomobject]@{
        battery_temperature_c = $Battery
        skin_temperature_c = $Skin
        silicon_temperature_c = $Silicon
        skin_sensor_count = $SkinSensorCount
        silicon_sensor_count = $SiliconSensorCount
        guard_sensor_count = $GuardSensorCount
    }
}

$thermalZoneLines = @(
    "zone=thermal_zone0 type=cpu-silver-usr temp=61250",
    "zone=thermal_zone1 type=gpu-usr temp=73500",
    "zone=thermal_zone2 type=skin-therm-usr temp=41800",
    "zone=thermal_zone3 type=battery temp=31000",
    "zone=thermal_zone4 type=invalid-negative temp=-273000",
    "garbage"
)
$hardwareLines = @(
    "CPU temperatures: [55.0, 58.5]",
    "GPU temperatures: [62.0, NaN]",
    "Battery temperatures: [29.0]",
    "Skin temperatures: [37.25]",
    "CPU throttling temperatures: [95.0]"
)

$snapshot = Get-ThorThermalGuardSnapshot `
    -BatteryLines @("temperature: 250") `
    -ThermalZoneLines $thermalZoneLines `
    -HardwareLines $hardwareLines

Assert-ThorEqual "battery maximum" $snapshot.battery_temperature_c 31.0
Assert-ThorEqual "skin maximum" $snapshot.skin_temperature_c 41.8
Assert-ThorEqual "silicon maximum" $snapshot.silicon_temperature_c 73.5
Assert-ThorEqual "thermal-zone count" $snapshot.thermal_zone_count 4
Assert-ThorEqual "hardware sensor count" $snapshot.hardware_sensor_count 5
Assert-ThorEqual "skin sensor count" $snapshot.skin_sensor_count 2
Assert-ThorEqual "silicon sensor count" $snapshot.silicon_sensor_count 5
Assert-ThorEqual "guard sensor count" $snapshot.guard_sensor_count 7
Assert-ThorEqual "battery format" (Format-ThorTemperatureC $snapshot.battery_temperature_c) "31.0"
Assert-ThorEqual "unknown format" (Format-ThorTemperatureC $null) "unknown"

$limits = @{
    MaxBatteryTemperatureC = 39
    MaxSkinTemperatureC = 45
    MaxSiliconTemperatureC = 80
}

$coolViolation = Get-ThorThermalGuardViolation -Snapshot $snapshot @limits
Assert-ThorEqual "cool snapshot" $coolViolation $null

$unknownBattery = New-ThorTestSnapshot -Battery $null -Skin 35 -Silicon 65 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2
Assert-ThorEqual "unknown battery" (Get-ThorThermalGuardViolation -Snapshot $unknownBattery @limits).code "unknown-battery-temperature"

$unknownSilicon = New-ThorTestSnapshot -Battery 25 -Skin 30 -Silicon $null -SkinSensorCount 1 -SiliconSensorCount 0 -GuardSensorCount 1
Assert-ThorEqual "skin-only telemetry fails closed" (Get-ThorThermalGuardViolation -Snapshot $unknownSilicon @limits).code "unknown-silicon-temperature"

$hotBattery = New-ThorTestSnapshot -Battery 39 -Skin 35 -Silicon 65 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2
Assert-ThorEqual "battery ceiling" (Get-ThorThermalGuardViolation -Snapshot $hotBattery @limits).code "battery-temperature"

$hotSkin = New-ThorTestSnapshot -Battery 30 -Skin 45 -Silicon 65 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2
Assert-ThorEqual "skin ceiling" (Get-ThorThermalGuardViolation -Snapshot $hotSkin @limits).code "skin-temperature"

$hotSilicon = New-ThorTestSnapshot -Battery 30 -Skin 35 -Silicon 80 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2
Assert-ThorEqual "silicon ceiling" (Get-ThorThermalGuardViolation -Snapshot $hotSilicon @limits).code "silicon-temperature"

$preflightLimits = @{
    MaxBatteryTemperatureC = 34
    MaxSkinTemperatureC = 40
    MaxSiliconTemperatureC = 75
}
$coolPreflight = New-ThorTestSnapshot -Battery 33 -Skin 39 -Silicon 74.9 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2
Assert-ThorEqual "preflight headroom cool" (Get-ThorThermalGuardViolation -Snapshot $coolPreflight @preflightLimits) $null

$hotPreflight = New-ThorTestSnapshot -Battery 33 -Skin 39 -Silicon 75 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2
Assert-ThorEqual "preflight headroom ceiling" (Get-ThorThermalGuardViolation -Snapshot $hotPreflight @preflightLimits).code "silicon-temperature"
Assert-ThorEqual "launch ceiling wins" (Get-ThorPreflightSiliconLimitC -RuntimeLimitC 75 -HeadroomC 5 -MaxLaunchSiliconTemperatureC 40) 40
Assert-ThorEqual "runtime headroom wins" (Get-ThorPreflightSiliconLimitC -RuntimeLimitC 35 -HeadroomC 5 -MaxLaunchSiliconTemperatureC 40) 30
$stablePreflight = @(
    (New-ThorTestSnapshot -Battery 25 -Skin 30 -Silicon 34.0 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2),
    (New-ThorTestSnapshot -Battery 25 -Skin 30 -Silicon 35.9 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2)
)
Assert-ThorEqual "stable preflight trend" (Get-ThorThermalPreflightTrendViolation -Snapshots $stablePreflight -MaxRiseC 2.0) $null
$risingPreflight = @(
    (New-ThorTestSnapshot -Battery 25 -Skin 30 -Silicon 34.0 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2),
    (New-ThorTestSnapshot -Battery 25 -Skin 30 -Silicon 36.1 -SkinSensorCount 1 -SiliconSensorCount 1 -GuardSensorCount 2)
)
Assert-ThorEqual "rising preflight trend" (Get-ThorThermalPreflightTrendViolation -Snapshots $risingPreflight -MaxRiseC 2.0).code "preflight-silicon-rise"

$zoneCommand = Get-ThorThermalZoneShellCommand
if ($zoneCommand -notmatch "thermal_zone\*" -or $zoneCommand -notmatch "zone=%s type=%s temp=%s") {
    throw "Thermal-zone shell command is missing its bounded parse contract."
}

if (-not [string]::IsNullOrWhiteSpace($CaptureRoot)) {
    $resolvedCaptureRoot = (Resolve-Path -LiteralPath $CaptureRoot).Path
    $realSnapshot = Get-ThorThermalGuardSnapshot `
        -BatteryLines @(Get-Content -LiteralPath (Join-Path $resolvedCaptureRoot "guard-pre-capture-battery.txt")) `
        -HardwareLines @(Get-Content -LiteralPath (Join-Path $resolvedCaptureRoot "guard-pre-capture-hardware-temperatures.txt")) `
        -ThermalZoneLines @(Get-Content -LiteralPath (Join-Path $resolvedCaptureRoot "guard-pre-capture-thermal-zones.txt"))

    Assert-ThorEqual "captured battery maximum" $realSnapshot.battery_temperature_c 26.0
    Assert-ThorEqual "captured skin maximum" $realSnapshot.skin_temperature_c 30.0
    Assert-ThorEqual "captured silicon maximum" $realSnapshot.silicon_temperature_c 87.1
    Assert-ThorEqual "captured thermal-zone count" $realSnapshot.thermal_zone_count 65
    Assert-ThorEqual "captured silicon sensor count" $realSnapshot.silicon_sensor_count 29
    Assert-ThorEqual "captured thermal violation" (Get-ThorThermalGuardViolation -Snapshot $realSnapshot @limits).code "silicon-temperature"
    Write-Output "Validated captured Thor 87.1 C silicon trip."
}
$inputMacroSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "thor_input_macro.ps1") -Raw
$debugCommonSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "thor_debug_common.ps1") -Raw
if ($debugCommonSource -notmatch 'function\s+Write-ThorStandardSnapshot[\s\S]*?Copy-ThorAdbFile[\s\S]*?\$\{namePrefix\}RPCSX\.log') {
    throw "Standard Thor snapshots do not preserve the full guest RPCSX log."
}
if ($inputMacroSource -match '&\s+\$Adb\s+shell\s+\$thermalZoneCommand') {
    throw "The input route still invokes the quoted thermal-zone command through PowerShell native argument flattening."
}
if ($inputMacroSource -notmatch 'Invoke-ThorAdbLines.+\$thermalZoneCommand') {
    throw "The input route does not use the lossless native argument capture path for thermal zones."
}
if ($inputMacroSource -notmatch '\[int\]\$ThermalPreflightSamples\s*=\s*3') {
    throw "The input route does not default to three thermal preflight samples."
}
if ($inputMacroSource -notmatch '\[int\]\$ThermalPreflightIntervalSeconds\s*=\s*2') {
    throw "The input route does not default to a two-second thermal preflight interval."
}
if ($inputMacroSource -notmatch '\[double\]\$ThermalPreflightHeadroomC\s*=\s*5\.0') {
    throw "The input route does not reserve five degrees of launch headroom."
}
if ($inputMacroSource -notmatch '\[double\]\$MaxLaunchSiliconTemperatureC\s*=\s*40\.0' -or
    $inputMacroSource -notmatch '\[double\]\$ThermalPreflightMaxRiseC\s*=\s*2\.0') {
    throw "The input route does not enforce the cool-silicon launch ceiling and stable preflight trend."
}
if ($inputMacroSource -notmatch '\[int\]\$ThermalPollIntervalSeconds\s*=\s*2') {
    throw "The input route does not default to two-second runtime thermal polling."
}
if ($inputMacroSource -notmatch '\[ValidateRange\(0,\s*16\)\]\s*\[int\]\$RsxCacheWorkers\s*=\s*0') {
    throw "The input route does not expose a bounded, opt-in RSX cache worker override."
}
$rsxWorkerResetCount = [regex]::Matches(
    $inputMacroSource,
    [regex]::Escape('setprop debug.rpcsx.thor.rsx_cache_workers 0')
).Count
if ($rsxWorkerResetCount -ne 3) {
    throw "The input route must reset the RSX cache worker override before launch and after success or failure; found $rsxWorkerResetCount resets."
}
if ($inputMacroSource -notmatch 'setprop debug\.rpcsx\.thor\.rsx_cache_workers \$RsxCacheWorkers') {
    throw "The input route does not set the requested RSX cache worker override before launch."
}
if ($inputMacroSource -notmatch '\[ValidateRange\(0,\s*4096\)\]\s*\[int\]\$RsxCachePreloadLimit\s*=\s*0') {
    throw "The input route does not expose a bounded, opt-in RSX cached-pipeline preload limit."
}
$rsxPreloadLimitResetCount = [regex]::Matches(
    $inputMacroSource,
    [regex]::Escape('setprop debug.rpcsx.thor.rsx_cache_preload_limit 0')
).Count
if ($rsxPreloadLimitResetCount -ne 3) {
    throw "The input route must reset the RSX cached-pipeline preload limit before launch and after success or failure; found $rsxPreloadLimitResetCount resets."
}
if ($inputMacroSource -notmatch 'setprop debug\.rpcsx\.thor\.rsx_cache_preload_limit \$RsxCachePreloadLimit') {
    throw "The input route does not set the requested RSX cached-pipeline preload limit before launch."
}
if ($inputMacroSource -notmatch '\[ValidateRange\(0,\s*4096\)\]\s*\[int\]\$SpuCachePreloadLimit\s*=\s*0') {
    throw "The input route does not expose a bounded, opt-in SPU cached-program preload limit."
}
$spuPreloadLimitResetCount = [regex]::Matches(
    $inputMacroSource,
    [regex]::Escape('setprop debug.rpcsx.thor.spu_cache_preload_limit 0')
).Count
if ($spuPreloadLimitResetCount -ne 3) {
    throw "The input route must reset the SPU cached-program preload limit before launch and after success or failure; found $spuPreloadLimitResetCount resets."
}
if ($inputMacroSource -notmatch 'setprop debug\.rpcsx\.thor\.spu_cache_preload_limit \$SpuCachePreloadLimit') {
    throw "The input route does not set the requested SPU cached-program preload limit before launch."
}
if ($inputMacroSource -notmatch '\[ValidateSet\("on",\s*"off"\)\]\s*\[string\]\$VkPipelineCache\s*=\s*"on"') {
    throw "The input route does not expose a default-on Vulkan pipeline cache rollback."
}
$vkPipelineCacheResetCount = [regex]::Matches(
    $inputMacroSource,
    [regex]::Escape('setprop debug.rpcsx.thor.vk_pipeline_cache on')
).Count
if ($vkPipelineCacheResetCount -ne 3) {
    throw "The input route must reset the Vulkan pipeline cache route before launch and after success or failure; found $vkPipelineCacheResetCount resets."
}
if ($inputMacroSource -notmatch 'setprop debug\.rpcsx\.thor\.vk_pipeline_cache \$VkPipelineCache') {
    throw "The input route does not set the requested Vulkan pipeline cache route before launch."
}
if ($inputMacroSource -notmatch '\$slice\s*=\s*\[Math\]::Min\(\$remaining,\s*\$ThermalPollIntervalSeconds\s*\*\s*1000\)') {
    throw "Long input-route waits do not use the bounded thermal polling interval."
}
if ($inputMacroSource -notmatch 'function\s+Assert-ThorThermalPreflight[\s\S]*?Get-ThorPreflightSiliconLimitC[\s\S]*?-MaxLaunchSiliconTemperatureC\s+\$MaxLaunchSiliconTemperatureC[\s\S]*?for\s*\(\$sample\s*=\s*1;[\s\S]*?Assert-ThorThermalBudget[\s\S]*?-PassThru[\s\S]*?Get-ThorThermalPreflightTrendViolation[\s\S]*?-MaxRiseC\s+\$ThermalPreflightMaxRiseC') {
    throw "The input route thermal preflight does not require the cool-silicon ceiling, repeated samples, and stable trend."
}
$preflightCallIndex = $inputMacroSource.LastIndexOf('Assert-ThorThermalPreflight "pre-run"')
$quiesceIndex = $inputMacroSource.IndexOf('if ($ForceStop -or $BootGame)')
$bootLaunchIndex = if ($preflightCallIndex -ge 0) { $inputMacroSource.IndexOf('if ($BootGame) {', $preflightCallIndex) } else { -1 }
if ($quiesceIndex -lt 0 -or $preflightCallIndex -le $quiesceIndex -or $bootLaunchIndex -le $preflightCallIndex) {
    throw "The repeated thermal preflight must run after quiescing RPCSX and before launch."
}

$speedSprintSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "eternal_sonata_speed_sprint.ps1") -Raw
if ($speedSprintSource -notmatch '\[int\]\$AndroidThermalPreflightSamples\s*=\s*3' -or
    $speedSprintSource -notmatch '\[int\]\$AndroidThermalPreflightIntervalSeconds\s*=\s*2' -or
    $speedSprintSource -notmatch '\[double\]\$AndroidThermalPreflightHeadroomC\s*=\s*5\.0' -or
    $speedSprintSource -notmatch '\[double\]\$AndroidMaxLaunchSiliconTemperatureC\s*=\s*40\.0' -or
    $speedSprintSource -notmatch '\[double\]\$AndroidThermalPreflightMaxRiseC\s*=\s*2\.0') {
    throw "The Android speed-sprint wrapper does not expose the cool-soak defaults."
}
if ($speedSprintSource -notmatch 'ThermalPreflightSamples\s*=\s*\$AndroidThermalPreflightSamples' -or
    $speedSprintSource -notmatch 'ThermalPreflightIntervalSeconds\s*=\s*\$AndroidThermalPreflightIntervalSeconds' -or
    $speedSprintSource -notmatch 'ThermalPreflightHeadroomC\s*=\s*\$AndroidThermalPreflightHeadroomC' -or
    $speedSprintSource -notmatch 'MaxLaunchSiliconTemperatureC\s*=\s*\$AndroidMaxLaunchSiliconTemperatureC' -or
    $speedSprintSource -notmatch 'ThermalPreflightMaxRiseC\s*=\s*\$AndroidThermalPreflightMaxRiseC' -or
    $speedSprintSource -notmatch 'ThermalPollIntervalSeconds\s*=\s*\$AndroidThermalPollSeconds') {
    throw "The Android speed-sprint wrapper does not forward the cool-soak contract."
}
if ($speedSprintSource -notmatch '\[ValidateRange\(1,\s*5\)\]\s*\[int\]\$AndroidThermalPollSeconds') {
    throw "The Android speed-sprint wrapper allows an unsafe runtime thermal polling interval."
}
if ($speedSprintSource -notmatch '\[int\]\$AndroidThermalPollSeconds\s*=\s*2') {
    throw "The Android speed-sprint wrapper does not default to two-second runtime thermal polling."
}
if ($speedSprintSource -notmatch '\[ValidateRange\(0,\s*16\)\]\s*\[int\]\$AndroidRsxCacheWorkers\s*=\s*0' -or
    $speedSprintSource -notmatch 'RsxCacheWorkers\s*=\s*\$AndroidRsxCacheWorkers') {
    throw "The Android speed-sprint wrapper does not expose and forward the bounded RSX cache worker override."
}
if ($speedSprintSource -notmatch '\[ValidateRange\(0,\s*4096\)\]\s*\[int\]\$AndroidRsxCachePreloadLimit\s*=\s*0' -or
    $speedSprintSource -notmatch 'RsxCachePreloadLimit\s*=\s*\$AndroidRsxCachePreloadLimit') {
    throw "The Android speed-sprint wrapper does not expose and forward the bounded RSX cached-pipeline preload limit."
}
if ($speedSprintSource -notmatch '\[ValidateRange\(0,\s*4096\)\]\s*\[int\]\$AndroidSpuCachePreloadLimit\s*=\s*0' -or
    $speedSprintSource -notmatch 'SpuCachePreloadLimit\s*=\s*\$AndroidSpuCachePreloadLimit') {
    throw "The Android speed-sprint wrapper does not expose and forward the bounded SPU cached-program preload limit."
}
if ($speedSprintSource -notmatch '\[ValidateSet\("on",\s*"off"\)\]\s*\[string\]\$AndroidVkPipelineCache\s*=\s*"on"' -or
    $speedSprintSource -notmatch 'VkPipelineCache\s*=\s*\$AndroidVkPipelineCache') {
    throw "The Android speed-sprint wrapper does not expose and forward the default-on Vulkan pipeline cache route."
}
if ($zoneCommand -match '\$\(\s*cat') {
    throw "Thermal-zone polling still spawns per-zone cat processes instead of using shell built-ins."
}
$joinedZoneCommand = Join-ThorNativeArguments @("shell", $zoneCommand)
if ($joinedZoneCommand -notmatch '^shell "' -or $joinedZoneCommand -notmatch '\\"zone=%s') {
    throw "Thermal-zone native argument quoting does not preserve the remote printf contract."
}
Write-Output "Thor multi-sensor thermal guard tests passed."
