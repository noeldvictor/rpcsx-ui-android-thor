# Windows RPCS3 Lab Launch Environment Repair

Date: 2026-07-19

## Failure

PowerShell 5.1 inherited two case variants of the Windows path variable:
`Path` and `PATH`. `Start-Process` attempted to construct a case-insensitive
environment dictionary and failed before RPCS3 started:

`Item has already been added. Key in dictionary: 'PATH' Key being added: 'Path'`

After that was isolated, a restricted diagnostic launch displayed RPCS3's
`Not enough memory for RPCS3 process` dialog. Host memory and commit headroom
were ample. The failure came from the restricted Windows job rejecting
RPCS3's 2 to 3 GiB working-set request, not from physical-memory exhaustion.
The bounded profiler therefore must run outside that restricted job.

## Repair

The launcher now:

- reads the raw process environment;
- prefers the exact uppercase `PATH` value when present, preserving the host's
  restricted-binary entries;
- removes all case variants and writes one canonical `Path`;
- launches through `System.Diagnostics.ProcessStartInfo` with shell execution
  disabled;
- keeps the real process handle; and
- drains stdout and stderr asynchronously before writing the capture files.

All experiment variables continue to be restored immediately after process
creation.

## Verification

- `tools/test_windows_rpcs3_launch_environment.ps1`: pass;
- PowerShell AST parsing: pass;
- bounded 15-second smoke capture:
  `20260719-034159-canonical-path-redirect-final-smoke`;
- RPCS3 remained alive for the entire 15-second bound and was then stopped by
  the harness;
- stdout and stderr capture completed without the duplicate-path exception;
- no Thor interaction occurred.

This repair restores trustworthy Windows profiling. It is tooling work and
does not itself earn emulator speed or temperature credit.
