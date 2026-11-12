# Contributing

How to set up, run the tests, and the technical rules in more detail. What a change has to meet,
pull request etiquette, and whether your idea fits better as a plugin are in the
[README](README.md#contributing).

## Setup

DaylightUI is built for WoW: Forever only (Interface 16001). It's classic content on the modern
client, so the modern addon rules apply: secret values, Edit Mode, `C_*` APIs. Code written for
old Classic clients usually won't work.

1. Fork and clone the repo somewhere **outside** the game folder (Battle.net can't update the game
   while an editor has files open inside it).
2. Link it into the game. On Windows:

   ```
   powershell -ExecutionPolicy Bypass -File tools\link_dev.ps1
   ```

   This makes junctions in `Interface\AddOns` for the core and every module. Pass
   `-Game "D:\path\to\_forever_"` if the game isn't in the default place.
3. `/reload` in game picks up every change, new files included.

## Tests

The tests run the addon against a fake copy of the game, no WoW needed. You need
[LuaJIT](https://luajit.org) and Python 3.

```
py tools/fetch_blizzard.py          # once: downloads the game's UI code the tests use
py tools/affected.py --files <the files you changed>   # the tests for what you touched
luajit tests/run.lua --par          # everything, before you open the PR (~2 min)
```

If you fix an error from the game, add a test that fails with that error first, then fix it.
`tests/stub.lua` is the fake game; if it doesn't behave like the real client in some case, teach it
the real rule.

## The rules that matter most

These are what reviews usually come back on.

**Secret values.** In combat and in restricted content (boss fights, keystones, PvP matches), many
API returns are "secret". You can pass them to things like `FontString:SetText` or
`StatusBar:SetValue`, but you can't compare them, do math on them, test them in an `if`, or use them
as table keys. Some (`UnitHealth`, `UnitInRange`, absorbs) are secret all the time. Check before
using a game function:

```
luajit tools/api.lua UnitHealth
```

It tells you the arguments, whether the return can be secret, and where DaylightUI already calls it.

**Combat lockdown.** Protected frames can't be moved, shown or resized in combat. Use
`DUI.AfterCombat(fn, key)`. Aura buttons made by the client get locked under restrictions too:
`DUI.AfterRestrictions(fn, key)`.

**Don't hook the game's frames.** No `hooksecurefunc(frame, "Method")` on the game's objects: in
this client it breaks the game's own protected calls. React to events instead.
`tests/test_guards.lua` catches most of these.

**One look.** Everything visible goes through the shared pieces so the whole UI feels like one thing:
- Controls (buttons, tabs, switches, sliders, inputs, menus, scroll bars) come from
  `Options/Widgets.lua`. Don't build your own, and don't use the game's templates.
- Frames get `Style.Shell`. Bars are gradients (`Style.Bar`, `W.Bar`).
- Text sizes come from `Style.SIZE`, text colors from `Style.INK` or `Style.Accent()` (read when
  painting, never cached). No typed-in colors, no plain gray text.
- Things move: anything that appears, disappears or changes size eases with `Motion` at one of the
  three speeds (`Motion.FAST/NORMAL/SLOW`). Information you need in a fight never waits for an
  animation.

`tests/test_hygiene.lua` checks most of this, and will tell you what it found.

**Text.** Every string a player sees goes through the locale table: `L["Ready"]`, whole sentences
with `%s` for the parts that change. Use `DUI.UnitName(unit, element)` for names, not `UnitName`.

**Settings.** `DUI:Get(scope, "path")` and `DUI:Set(...)`. Never read settings when a file loads;
they don't exist until login.

**Performance.** Nothing should run every frame while idle. `tests/test_lag.lua` counts it.

## Where things are

- The core (`DaylightUI/`) holds the shared pieces: `Style.lua`, `Motion.lua`, `Options/`,
  the window kit in `Windows/`, and the newer windows (`Book/`, `Character/`, `Npc/`, ...).
- Each `DaylightUI_<Name>` folder is its own addon and can be switched off on its own.
- `API.md` is the public API for plugin authors.

## Bug reports

Open an issue with what you were doing, what you expected, and the error text if there was one
(BugSack / BugGrabber is the easiest way to get it). Which modules you have on helps too.
