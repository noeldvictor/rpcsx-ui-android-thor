# Windows Lab Input Reference

## Launch Rule

Use `tools/windows_rpcs3_lab.ps1` for Windows input work. It writes the agent keyboard pad profile, suppresses the main GUI for NoGui runs, moves the game window to the secondary monitor when asked, and records run metadata.

Basic proof:

```powershell
.\tools\windows_rpcs3_lab.ps1 -Mode NoGui -Visible -InputMacro "move2;focus;wait:3000;cross:150;wait:800;shot" -ScreenshotEverySeconds 0
```

Use `-InputBackend PadApi` when title/menu navigation matters. It sets `RPCS3_ES_PAD_API_FILE` for the lab build and writes PS3 button state directly into the keyboard pad layer, so it does not depend on Windows focus or `keybd_event` delivery.

PadApi title-to-Options proof:

```powershell
.\tools\windows_rpcs3_lab.ps1 -Mode NoGui -InputBackend PadApi -InputMacro "wait:65000;shot;cross:180;wait:6000;shot;down:250;wait:1000;shot;down:250;wait:1000;shot;cross:180;wait:8000;shot" -ScreenshotEverySeconds 0
```

## Macro Syntax

Tokens are separated by semicolons or commas:

- `wait:MS`
- `focus`
- `move2` or `secondary`
- `shot` or `screenshot`; use `shot:label` for branch-labeled screenshots
- PS3 labels: `cross`, `circle`, `square`, `triangle`, `start`, `select`, `ps`
- D-pad: `up`, `down`, `left`, `right`
- Left stick keyboard aliases: `ls_up`, `ls_down`, `ls_left`, `ls_right`
- Right stick keyboard aliases: `rs_up`, `rs_down`, `rs_left`, `rs_right`
- Shoulders: `l1`, `r1`, `l2`, `r2`, `l3`, `r3`
- PadApi analog values: `lx=0..255`, `ly=0..255`, `rx=0..255`, `ry=0..255`

Use explicit press durations for branch points:

```powershell
-InputMacro "move2;focus;wait:5000;start:180;wait:1000;cross:180;wait:3000;shot"
```

Use labeled screenshots while debugging routes:

```powershell
-InputMacro "wait:45000;shot:title;down:20;wait:500;shot:after-down;cross:80;wait:12000;shot:load-list"
```

For Eternal Sonata title loading, prefer short PadApi pulses. `down:120` or
`ls_down:120` can skip from `NEW GAME` to title `OPTIONS`; `down:20` has been
proven to land on `LOAD`.

For longer field-load perf routes, move off the save point before sending a late
acknowledge/retry `cross`; otherwise the macro can open the in-field `Save game`
prompt and pollute the perf checkpoint. A current Windows-only field checkpoint
shape is:

```powershell
wait:45000;down:20;wait:800;cross:120;wait:15000;shot:load-list;cross:120;wait:5000;shot:confirm;up:40;wait:1000;shot:yes;cross:120;wait:30000;shot:after-confirm-wait;combo:ls_right+ls_down:2500;wait:1000;cross:120;wait:30000;shot:field-final;wait:20000;shot:field-late
```

## Failure Handling

If input does not land:

- Confirm the run has a game window handle in `windows-rpcs3-lab.txt`.
- Use `-Visible` and include `focus` before the first key for keyboard backend only.
- Use `move2` so the game window is not hidden behind Codex or another emulator.
- If Cross/Start works but d-pad or sticks do not move selection, stop using keyboard for that route and rerun with `-InputBackend PadApi`.
- Check host contention. If Vita3K or another emulator is active, label the run `contended-host`.
- If the GUI or a fatal dialog appears, stop and relaunch through the lab script; do not keep clicking around manually for a benchmark route.
- If PadApi also opens the wrong state, the macro is wrong for that game state; do not keep lengthening it blindly.
- If a route reaches a cutscene `Pause` overlay after a skip, do not count it as
  active moving gameplay. Capture the state with `shot:label` and solve the
  resume control before running perf comparisons.

## Agent Keyboard Map

Windows lab writes a deterministic Player 1 keyboard profile:

- Cross `X`, Circle `C`, Square `Z`, Triangle `V`
- Start `Enter`, Select `Space`, PS `Backspace`
- D-pad arrows
- Left stick `W/A/S/D`
- Right stick `Home/Delete/End/PageDown`
- L1/R1 `Q/E`, L2/R2 `R/T`, L3/R3 `F/G`
