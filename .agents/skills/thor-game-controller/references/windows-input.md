# Windows Lab Input Reference

## Launch Rule

Use `tools/windows_rpcs3_lab.ps1` for Windows input work. It writes the agent keyboard pad profile, suppresses the main GUI for NoGui runs, moves the game window to the secondary monitor when asked, and records run metadata.

Basic proof:

```powershell
.\tools\windows_rpcs3_lab.ps1 -Mode NoGui -Visible -InputMacro "move2;focus;wait:3000;cross:150;wait:800;shot" -ScreenshotEverySeconds 0
```

## Macro Syntax

Tokens are separated by semicolons or commas:

- `wait:MS`
- `focus`
- `move2` or `secondary`
- `shot` or `screenshot`
- PS3 labels: `cross`, `circle`, `square`, `triangle`, `start`, `select`, `ps`
- D-pad: `up`, `down`, `left`, `right`
- Left stick keyboard aliases: `ls_up`, `ls_down`, `ls_left`, `ls_right`
- Right stick keyboard aliases: `rs_up`, `rs_down`, `rs_left`, `rs_right`
- Shoulders: `l1`, `r1`, `l2`, `r2`, `l3`, `r3`

Use explicit press durations for branch points:

```powershell
-InputMacro "move2;focus;wait:5000;start:180;wait:1000;cross:180;wait:3000;shot"
```

## Failure Handling

If input does not land:

- Confirm the run has a game window handle in `run.md`.
- Use `-Visible` and include `focus` before the first key.
- Use `move2` so the game window is not hidden behind Codex or another emulator.
- Check host contention. If Vita3K or another emulator is active, label the run `contended-host`.
- If the GUI or a fatal dialog appears, stop and relaunch through the lab script; do not keep clicking around manually for a benchmark route.

## Agent Keyboard Map

Windows lab writes a deterministic Player 1 keyboard profile:

- Cross `X`, Circle `C`, Square `Z`, Triangle `V`
- Start `Enter`, Select `Space`, PS `Backspace`
- D-pad arrows
- Left stick `W/A/S/D`
- Right stick `Home/Delete/End/PageDown`
- L1/R1 `Q/E`, L2/R2 `R/T`, L3/R3 `F/G`
