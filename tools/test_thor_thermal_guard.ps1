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
if ($inputMacroSource -match '&\s+\$Adb\s+shell\s+\$thermalZoneCommand') {
    throw "The input route still invokes the quoted thermal-zone command through PowerShell native argument flattening."
}
if ($inputMacroSource -notmatch 'Invoke-ThorAdbLines.+\$thermalZoneCommand') {
    throw "The input route does not use the lossless native argument capture path for thermal zones."
}
if ($zoneCommand -match '\$\(\s*cat') {
    throw "Thermal-zone polling still spawns per-zone cat processes instead of using shell built-ins."
}
$joinedZoneCommand = Join-ThorNativeArguments @("shell", $zoneCommand)
if ($joinedZoneCommand -notmatch '^shell "' -or $joinedZoneCommand -notmatch '\\"zone=%s') {
    throw "Thermal-zone native argument quoting does not preserve the remote printf contract."
}
Write-Output "Thor multi-sensor thermal guard tests passed."
