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
        [int]$GuardSensorCount
    )

    return [pscustomobject]@{
        battery_temperature_c = $Battery
        skin_temperature_c = $Skin
        silicon_temperature_c = $Silicon
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

$unknownBattery = New-ThorTestSnapshot -Battery $null -Skin 35 -Silicon 65 -GuardSensorCount 2
Assert-ThorEqual "unknown battery" (Get-ThorThermalGuardViolation -Snapshot $unknownBattery @limits).code "unknown-battery-temperature"

$unknownWorkload = New-ThorTestSnapshot -Battery 25 -Skin $null -Silicon $null -GuardSensorCount 0
Assert-ThorEqual "unknown workload telemetry" (Get-ThorThermalGuardViolation -Snapshot $unknownWorkload @limits).code "unknown-workload-temperature"

$hotBattery = New-ThorTestSnapshot -Battery 39 -Skin 35 -Silicon 65 -GuardSensorCount 2
Assert-ThorEqual "battery ceiling" (Get-ThorThermalGuardViolation -Snapshot $hotBattery @limits).code "battery-temperature"

$hotSkin = New-ThorTestSnapshot -Battery 30 -Skin 45 -Silicon 65 -GuardSensorCount 2
Assert-ThorEqual "skin ceiling" (Get-ThorThermalGuardViolation -Snapshot $hotSkin @limits).code "skin-temperature"

$hotSilicon = New-ThorTestSnapshot -Battery 30 -Skin 35 -Silicon 80 -GuardSensorCount 2
Assert-ThorEqual "silicon ceiling" (Get-ThorThermalGuardViolation -Snapshot $hotSilicon @limits).code "silicon-temperature"

$zoneCommand = Get-ThorThermalZoneShellCommand
if ($zoneCommand -notmatch "thermal_zone\*" -or $zoneCommand -notmatch "zone=%s type=%s temp=%s") {
    throw "Thermal-zone shell command is missing its bounded parse contract."
}

Write-Output "Thor multi-sensor thermal guard tests passed."
