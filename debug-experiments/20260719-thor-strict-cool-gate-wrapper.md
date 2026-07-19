# Thor Strict Cool-Gate Wrapper

- Date: 2026-07-19
- Classification: `route-tooling`
- Device action: none

## Problem

The exact `5C3911D0...682CC6` no-launch install succeeded, but its first host
attempt used an unsupported profile label and the successful follow-up had to
recover the capture directory manually because `thor_input_macro.ps1` printed
that path through the host stream. Neither error launched RPCSX, but both made
the install-only workflow easier to misuse or repeat.

## Change

- `thor_input_macro.ps1` now has an explicit empty `strict-cool-gate` profile.
  The profile itself rejects boot, missing force-stop, a custom macro, or any
  non-exact thermal limit before resolving ADB.
- `-PassThruCaptureDirectory` emits the successful capture directory through
  the PowerShell success stream while retaining the existing human-readable
  console message.
- `invoke_thor_strict_cool_gate.ps1` defaults to a host-only `Status` action.
  Explicit `-Action Run` supplies the exact three-sample, two-second,
  sub-35-C, maximum-1-C-rise, battery/skin/silicon, force-stop, and no-boot
  contract. It returns one validated absolute capture path.
- The wrapper contains no activity-start, monkey, or `-BootGame` path.

## Verification

- Both PowerShell files parse successfully.
- The host-only status action reports the exact contract without resolving or
  querying ADB.
- `tools/test_thor_strict_cool_gate.ps1` checks the no-launch surface, exact
  thermal values, pre-ADB unsafe-argument rejection, machine-readable output,
  and required capture evidence.
- All 59 `tools/test_thor_*.ps1` contracts pass.

## Decision

Keep the installed APK and Thor stopped. This change is safety/repeatability
tooling only and receives no speed, temperature, FPS, flicker, gameplay, or
stability credit. After a separate cooling interval, the next device action is
still one self-stopping `ThorCoolTitle` proof under the existing `35 C` launch
and `68/72 C` runtime gates.
