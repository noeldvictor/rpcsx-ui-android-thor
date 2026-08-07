$ErrorActionPreference = "Stop"

# Contract: per-core junction sensors must not be guarded at the package limit.
#
# thermal_zone types on this SoC mix two quantities. Subsystem sensors
# (cpuss-*, gpuss-*, aoss-*, ddr) track roughly what a package sensor tracks.
# Per-core junction sensors (cpu-<cluster>-<core>) run far hotter by design and
# swing much harder with load: cpu-1-9 measured 90.7 C during a compile and
# 55.0 C idle minutes later, while cpuss-0 sat at 49.4 C.
#
# The classifier used to call both "silicon" and report the maximum, so a 72 C
# silicon limit was applied to a junction maximum. Junction passes 72 C under
# any sustained work on this part and is unremarkable until roughly 95-105 C, so
# that pairing was a load detector rather than a thermal bound.
#
# It fired: the cache-worker A/B recorded "71.1 C at the first runtime sample,
# guard stopped it 0.7 s in" for the arm on the big cores, and 53.8 C for the arm
# pinned to the A510s. It was measuring which arm ran on faster cores. The A510
# pinning was then adopted to satisfy that reading.
#
# This device also exposes no skin-domain zone at all, so there is no package
# sensor to fall back on and the separation is the only thing keeping the silicon
# limit meaningful.

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "thor_debug_common.ps1")

# 1. Classification must split the two families.
$junctionNames = @('cpu-0-0', 'cpu-1-9', 'cpu-1-10', 'CPU-1-3')
foreach ($name in $junctionNames) {
    $domain = Get-ThorTemperatureDomain -Name $name
    if ($domain -ne "junction") {
        throw "Per-core sensor '$name' classified as '$domain'; it must be 'junction' or it gets guarded at the package limit."
    }
}

# Only the names the classifier actually claims. aoss-*, nspss-* and video fall
# through to "other" and always did; that is pre-existing behaviour this change
# did not touch, so it is not asserted here. Writing down the assumption instead
# of checking it is how this test failed twice.
$siliconNames = @('cpuss-0', 'cpuss-3', 'gpuss-4', 'ddr')
foreach ($name in $siliconNames) {
    $domain = Get-ThorTemperatureDomain -Name $name
    if ($domain -ne "silicon") {
        throw "Subsystem sensor '$name' classified as '$domain'; it must remain 'silicon' or the silicon limit loses the sensors it suits."
    }
}

# Battery and skin classification must be unaffected.
if ((Get-ThorTemperatureDomain -Name 'battery') -ne "battery") { throw "Battery classification changed." }
if ((Get-ThorTemperatureDomain -Name 'skin-therm') -ne "skin") { throw "Skin classification changed." }

# 2. A junction reading below its own limit but above the silicon limit must not
#    trip the guard. This is the exact case that produced the false stop.
$lines = @(
    "zone=thermal_zone31 type=cpuss-0 temp=64600",
    "zone=thermal_zone43 type=cpu-1-8 temp=88000"
)
$snapshot = Get-ThorThermalGuardSnapshot -BatteryLines @("  temperature: 300") -ThermalZoneLines $lines -HardwareLines @()

if ($snapshot.silicon_temperature_c -ne 64.6) {
    throw "silicon_temperature_c is $($snapshot.silicon_temperature_c); it must come from the subsystem sensor, not the junction one."
}
if ($snapshot.junction_temperature_c -ne 88.0) {
    throw "junction_temperature_c is $($snapshot.junction_temperature_c); the per-core sensor is not being reported separately."
}

$violation = Get-ThorThermalGuardViolation -Snapshot $snapshot `
    -MaxBatteryTemperatureC 45 -MaxSkinTemperatureC 48 -MaxSiliconTemperatureC 72
if ($null -ne $violation) {
    throw "Guard reported '$($violation.code)' for junction 88 C / silicon 64.6 C. Junction below 95 C is ordinary load, not a violation."
}

# 3. A genuine junction runaway must still stop. Removing the false trips must
#    not leave junction unbounded, which is what it effectively was before, since
#    the silicon check always fired first.
$hotLines = @(
    "zone=thermal_zone31 type=cpuss-0 temp=64600",
    "zone=thermal_zone43 type=cpu-1-8 temp=97000"
)
$hotSnapshot = Get-ThorThermalGuardSnapshot -BatteryLines @("  temperature: 300") -ThermalZoneLines $hotLines -HardwareLines @()
$hotViolation = Get-ThorThermalGuardViolation -Snapshot $hotSnapshot `
    -MaxBatteryTemperatureC 45 -MaxSkinTemperatureC 48 -MaxSiliconTemperatureC 72
if ($null -eq $hotViolation -or $hotViolation.code -ne "junction-temperature") {
    throw "Junction at 97 C did not trip the guard. Separating the domains must not leave junction unbounded."
}

# 4. The silicon limit must still bite on the sensors it does suit.
$hotSiliconLines = @("zone=thermal_zone31 type=cpuss-0 temp=75000")
$hotSiliconSnapshot = Get-ThorThermalGuardSnapshot -BatteryLines @("  temperature: 300") -ThermalZoneLines $hotSiliconLines -HardwareLines @()
$hotSiliconViolation = Get-ThorThermalGuardViolation -Snapshot $hotSiliconSnapshot `
    -MaxBatteryTemperatureC 45 -MaxSkinTemperatureC 48 -MaxSiliconTemperatureC 72
if ($null -eq $hotSiliconViolation -or $hotSiliconViolation.code -ne "silicon-temperature") {
    throw "Subsystem sensor at 75 C did not trip the silicon limit; the guard has been loosened rather than corrected."
}

Write-Output "Thor thermal domain contract passed: junction split from silicon, junction 88 C is not a violation, junction 97 C is, and the 72 C silicon limit still bites on subsystem sensors."
