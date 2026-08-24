# GPU drivers on Thor: what a driver swap can and cannot buy

Part of the notes indexed from [`AGENTS.md`](../../AGENTS.md).

## Balemuni's Aurora, measured 2026-08-24: NULL on Transformers

Aurora is a Mesa 26.3.0-devel Turnip build that names Snapdragon 8 Gen 2 and
AYN Thor directly, so it was worth measuring. On the restored 3D combat scene it
changes nothing.

| driver | fps | cores | temp C |
| --- | --- | --- | --- |
| Turnip v26.3.0-R3-v1, baseline | 18.70, 18.80 | 5.220, 4.540 | 94, 94 |
| Balemuni Apex Ultimate | 18.70, 18.70, 18.71 | 4.680, 5.060, 4.560 | 89, 94, 94 |

**Why it cannot help here.** This scene runs at 18 to 19 FPS against its own 30
FPS cap with about 5 cores busy. It is CPU bound. A GPU driver cannot move a
workload that is not waiting on the GPU, and no Turnip build ever will. If a
driver is going to pay off on this device it has to be on a title that is
actually GPU bound, which this one is not.

The freeze counts were 1 in 3 for the baseline and 0 in 3 for Aurora. At three
runs those are the same number and it is not evidence of anything.

## How the comparison was run, and the two traps in it

    tools/thor_ab_gpu_drivers.sh

**A warm-up boot per driver is discarded.** Switching driver invalidates the
Vulkan pipeline cache - the log says "Ignoring Vulkan driver pipeline cache that
does not match the current GPU/driver" - so the first boot after a switch
recompiles shaders and is not comparable with anything.

**Check the MSAA line before comparing.** Both drivers here log "Your GPU driver
does not support some required MSAA features. MSAA will be disabled." Both, so
they render the same frame and the comparison is fair. Had only one logged it,
any speed difference would have been the missing MSAA rather than the driver,
and the A/B would have been worthless.

**Confirm the driver actually loaded.** A driver that fails to load falls back
silently and the run then measures the system driver twice. The proof is in
logcat:

    hook_impl: hook_android_dlopen_ext: loading custom driver: .../vulkan.freedreno.so

## Installing and switching

    tools/thor_install_gpu_driver.sh --aurora --select
    tools/thor_install_gpu_driver.sh --use "Turnip v26.3.0-R3-v1"
    tools/thor_install_gpu_driver.sh --list

The installer reads `meta.json` before touching the device and refuses a package
whose `libraryName` is absent from the zip. It verifies the library size on the
device after copying, because a copy that silently did nothing looks exactly
like a successful install until the driver fails to load hours later.

Three things that each cost a run:

- **The two Aurora assets are byte identical.** `Balemuni_Apex_Ultimate_SD8Gen2.zip`
  and `Balemuni_Apex_Universal_AllAdreno.zip` are both sha256
  `dbd1971dd93eecc789ea20913fac68876f0f112c697bce6e6b16025c1d49cd8f`. The
  device-specific name is packaging, not a separate build.
- **The drivers disagree about the library name.** Aurora ships
  `vulkan.freedreno.so`; the older Turnip ships `libvulkan_freedreno.so`. Pointing
  the app at the wrong name leaves it on the system driver. `--use` reads the
  name from that driver's own `meta.json` instead of assuming.
- **Do not select a driver with `set_thor_gpu_driver.ps1` in this environment.**
  PowerShell 5.1 turns adb's progress output on stderr into a NativeCommandError,
  and with `ErrorActionPreference = "Stop"` the script dies AFTER the push but
  BEFORE the `run-as` copy. It reports failure while leaving the old driver
  selected, which was verified. Selection is done in bash for that reason.
