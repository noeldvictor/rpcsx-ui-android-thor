# Thermal sensors, the guard, and what the device actually reports

Two different quantities live in `/sys/class/thermal`, and comparing a limit
against the wrong one manufactured alarm twice here.

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md).

## The cold-start gate permits silicon below 70 C

The standalone `strict-cool-gate` uses one sample and an exclusive 70 C launch
limit. A fixed-silicon reading below 70 C can proceed immediately. It does not
wait for a lower target. A reading at or above 70 C cannot proceed. Battery,
skin, and CPU-junction readings do not decide this launch gate. The launch rule
uses only the fixed CPU-subsystem, GPU-subsystem, DDR, SoC, and crystal sensor
set.

The runtime guard is separate. It stops early at 70 C and keeps a 72 C hard
silicon limit. The CPU-junction hard limit remains 95 C.

## The guard measures junction maxima against a package-shaped limit

Following the sensor mistake below to its source found the same error in the
project's own tooling, and it explains a decision that was made on it.

`thor_debug_common.ps1` classifies any zone whose name matches
`cpu|gpu|soc|apss|cluster|silver|gold|prime|cpuss|ddr|memory|modem|pmic|xo` as
domain `silicon`, then reports `silicon_temperature_c` as the **maximum** of
that set. On this device that set includes `cpu-1-0` through `cpu-1-10`, which
are **per-core junction sensors**. Measured directly on the same zone:

    cpu-1-9  during unthrottled compile   90.7 C
    cpu-1-9  idle, minutes later          55.0 C

A ~35 C swing with load is the signature of a junction sensor. The subsystem
sensors beside it behave quite differently: `cpuss-0` reads 49.4 C idle, and the
`gpuss-*` group sits at 43-46 C.

This device also exposes **no `skin`-domain zone at all** — nothing matches
`skin|case|shell|quiet` — so the guard has no package sensor to fall back to and
rests entirely on that junction maximum, compared against
`MaxSiliconTemperatureC = 72.0`.

**A 72 C limit on a junction maximum is not a thermal bound, it is a load
detector.** Junction routinely passes 72 C on this SoC under any sustained work
and is unremarkable until roughly 95-105 C. That is why the original
cache-worker A/B recorded "71.1 C at the first runtime sample, guard stopped it
0.7 s in" for the ordinary scheduler: the arm that used the big cores tripped a
junction threshold almost immediately, and the arm pinned to the A510s did not,
because little cores have lower junction temperatures. The measurement was
faithfully recording which arm ran on faster cores.

So the A510 pinning was adopted to satisfy a limit that was measuring the wrong
quantity. Removing it, done for the independent reason that ten minutes at
51-58 C package was a bad trade, turns out to have removed a decision that rested
on an artifact.

**Fixed, without touching the safety bound.** The threshold was never the bug;
the classification was. `cpu-<cluster>-<core>` now resolves to a new `junction`
domain, leaving `silicon` to the subsystem sensors it was always meant to
describe. `MaxSiliconTemperatureC` stays at 72 C against those, and junction gets
its own `MaxJunctionTemperatureC = 95.0`, which still catches a genuine runaway
while no longer calling ordinary load an emergency.

Verified on the device at moderate load, and the numbers make the old failure
plain:

    silicon  : 64.6 C  from cpuss-2   (15 sensors, limit 72)  no violation
    junction : 71.9 C  from cpu-1-8   (14 sensors, limit 95)  no violation

Under the old classifier `silicon` was the maximum of both sets, so it would have
reported **71.9 C against a 72 C limit** — one tenth of a degree from stopping a
run, at a temperature that is entirely unremarkable. That is the mechanism behind
"stopped it 0.7 s in".

All four thermal contracts still pass.

## Read the right thermal sensor, and never mix two of them

`/sys/class/thermal/thermal_zone*/temp` on this device exposes both package-level
and **per-core junction** sensors. Taking the maximum across all of them is
wrong, and wrong in a way that manufactures alarm:

    cpu-1-9  = 90.7 C     per-core junction (Tj)
    cpu-1-10 = 83.9 C
    cpuss-0  = 68.7 C     CPU subsystem
    (AYN FanBase / on-device readout: 57-61 C, package)

Junction temperature always reads far above package. Roughly 90 C Tj under load
is ordinary for this SoC, which throttles nearer 95-105 C. The number the fan
curve uses, the number the device shows the user, and the number
`MaxSiliconTemperatureC = 72.0` bounds are all **package**, not junction.

This was found the hard way: an unthrottled compile was reported as "81.5 C,
above the 72 C gate" and nearly reversed a good change, when the device was
actually at 57 C and the reading came from a junction sensor. **A limit and a
measurement taken from different sensors cannot be compared**, and taking a
`max` over a heterogeneous sensor set silently does exactly that.

This is the same failure as the thermal wall recorded in the traps in
[`CLAUDE.md`](../../CLAUDE.md), in a
new costume. That one was sampling aliasing; this one is sensor mismatch. Both
produced a confident number that meant nothing. Use the project's own
`silicon_temperature_c` from `tools/thor_input_macro.ps1`, or the package sensor
the fan controller reads, and never a bare `sort -rn | head -1` over every zone.

With the correct sensor, the compile-throttle change reads:

| | time | package temp |
| --- | --- | --- |
| throttled (A510 x3, 2 LLVM threads) | ~10 min | 51-58 C |
| unthrottled (all cores, auto threads) | **~3 min** | **57-61 C** |

Roughly three times faster for about three degrees.
