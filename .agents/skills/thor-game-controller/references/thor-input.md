# Thor Input Reference

## Modes

Prefer Direct mode on debug builds:

```powershell
.\tools\thor_input_macro.ps1 -InputMode Direct -Profile custom -Macro "shot:before;cross;wait:800;shot:after" -PostSnapshot
```

Direct mode sends `net.rpcsx.THOR_DEBUG_PAD` to `net.rpcsx.ThorDebugPadReceiver`, which calls `RPCSXActivity.thorDebugPad(...)` and the overlay pad bridge. It avoids Android focus/keyevent problems.

Fallback order:

- `Direct`: deterministic debug receiver path.
- `virtual:cross`: Android `input gamepad` key event.
- `raw:cross`: Odin `/dev/input/event9` injection, useful only when raw device mapping is known.

## Macro Syntax

Tokens are separated by semicolons:

- `wait:MS`
- `shot:NAME`
- `threads:NAME`
- `cross`, `circle`, `square`, `triangle`, `start`, `select`, `l1`, `r1`, `l2`, `r2`, d-pad names
- `combo:select+r1:800`
- `direct:cross`, `virtual:cross`, `raw:cross`
- `stick:left:up:1000`, `stick:left:up_left:1000`, `stick:rs:right:500`

Common Eternal Sonata route base:

```text
wait:90000;cross;wait:20000;start;wait:3000;cross;wait:1000;cross;wait:100000;shot:field;stick:left:left:1000;wait:1000;shot:field-move;threads:field-route
```

## Debug Checks

Use `adb devices` first if commands hang or screenshots fail.

Use this when Direct input might not be installed:

```powershell
adb shell cmd package resolve-activity net.rpcsx.THOR_DEBUG_PAD
```

If a button is ignored:

- Confirm the screenshot is actually the game, not launcher/GUI/fatal popup.
- Send one button with before/after screenshots.
- Try `start` and `cross` separately; menu/title states can ignore sticks.
- If Direct fails but Virtual works, check the debug receiver manifest/build variant.
- If Virtual works but the game ignores it, the emulator may not own focus or the pad handler may not be bound.

## Route Hygiene

Do not hide branch decisions inside long macros. Add `shot:` before and after each uncertain action. Name failed states honestly: `boundary-dialogue`, `title-reset`, `black-transition`, `ignored-input`, or `wrong-menu`.
