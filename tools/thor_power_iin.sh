#!/usr/bin/env bash
# System power from the PMIC input-current ADC.
#
# WHY THIS WORKS WHERE EVERYTHING ELSE FAILED
# -------------------------------------------
# On this device the battery fuel gauge reports nothing usable: current_now is 0,
# and charge_counter, voltage_now and power_now do not move within a measurement
# window, on AC or off it. A cpufreq-residency proxy was written next and FAILED
# validation - a 2.4x change in CPU moved it 0.2%.
#
# The charger input path does report. With the battery full-ish and not charging
# (ichg_fb == 0), the current drawn at the charger input IS the system's draw:
#
#   /sys/class/power_supply/usb/voltage_now   input volts
#   /sys/class/power_supply/usb/current_now   input amps
#
# USE usb/current_now, NOT the iin_fb ADC. The ADC is bidirectional and noisy - it
# swings between -2140 and +2118 mW-equivalent within one 40 s window and averages
# NEGATIVE under load, which is meaningless here. usb/current_now is steady and
# tracks: 178 mA idle against 253-291 mA with a title rendering.
#
# This also corrects an earlier note in CLAUDE.md that usb/current_now "is the
# negotiated limit and sits frozen". It is not frozen on this device.
#
# Sanity: idle measured 8.939 V x 178 mA = 1.59 W, against the 1.60 W idle this
# repo recorded independently from the second screen. That agreement is why this is
# trusted where the other two were not.
#
# THE CONDITION THAT MAKES IT VALID: the battery must not be charging. Check
# ichg_fb, and be suspicious if the level is climbing - input power then includes
# whatever is going into the cell, which is not the emulator's draw.
set -u
DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
SECONDS_TO_RUN="${1:-30}"
LABEL="${2:-sample}"
export MSYS_NO_PATHCONV=1
adb_sh() { adb -s "$DEVICE" shell "$@"; }

ICHG=$(adb_sh "cat /sys/bus/iio/devices/iio:device0/in_current_pm8550b_ichg_fb_input" | tr -d '\r')
[ "${ICHG:-0}" -gt 20000 ] 2>/dev/null && echo "WARNING: battery is charging at ${ICHG} uA - input power includes the cell" >&2

adb_sh "
n=0; sum=0; min=999999999; max=0
end=\$(( \$(date +%s) + $SECONDS_TO_RUN ))
while [ \$(date +%s) -lt \$end ]; do
  v=\$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null)
  i=\$(cat /sys/class/power_supply/usb/current_now 2>/dev/null)
  [ -n \"\$v\" ] && [ -n \"\$i\" ] && {
    # Divide BOTH terms before multiplying. (v/1000)*i overflows 32-bit signed
    # arithmetic in the device shell - 8918 * 278000 is 2.48e9 - which produced
    # negative milliwatts and a mean of -1334 mW for a device drawing 2.4 W.
    mw=\$(( (v / 1000) * (i / 1000) / 1000 ))
    sum=\$((sum+mw)); n=\$((n+1))
    [ \$mw -lt \$min ] && min=\$mw
    [ \$mw -gt \$max ] && max=\$mw
  }
  sleep 1
done
[ \$n -gt 0 ] && echo \"$LABEL  mean=\$((sum/n)) mW  min=\${min} mW  max=\${max} mW  n=\$n\"
" | tr -d '\r'
