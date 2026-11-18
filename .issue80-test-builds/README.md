# Issue 80: matched test builds

These files are review/test attachments for the pull request to DaylightUI.
They are not a release or a confirmed nameplate fix.

- **DaylightUI-issue80-capture-control.zip**: normal behavior plus local capture.
- **DaylightUI-issue80-no-layout-overrides.zip**: the same build with direct
  native panel-layout overrides removed.

Both use normal buffering and display version **1.9.3**. Only five runtime
files differ: Windows/Follow.lua, Book/Window.lua, Character/Follow.lua,
DaylightUI_Skins/Packs/NPC.lua, and DaylightUI_Skins/Packs/Spells.lua. Native
helper calls remain. Neighboring windows may overlap or use different spacing;
talents may close neighboring panels.

## Install and compare

1. Fully exit WoW and keep your normal addon package available to restore.
   Extract the control ZIP into `Interface/AddOns`, so its `DaylightUI` and
   eleven `DaylightUI_*` folders sit directly inside AddOns. Use one build at
   a time; keep the same settings and other addons.
2. Assign **DaylightUI → Capture missing nameplates** in Key Bindings. Repeat
   your failing sequence. If plates disappear, press the key before repair or
   reload. If they remain missing after combat, capture again then.
3. `/dui platereport` opens the newest saved report; `/dui platereport 2` opens
   the preceding one. Ctrl+C copies it. Label it **Control**. Capture during
   combat intentionally skips restricted frame reads; its copy window waits.
4. Fully exit WoW, install the experimental ZIP, and repeat the same sequence.
   Label that report **No layout overrides**. Record attempts/disappearances
   and spellbook errors separately. Repeat control if the experiment is quiet.

Keep the opening sequence the same within each comparison: opening before
combat versus during combat can use different spellbook handlers.

## Capture and privacy

The watcher is on by default. Three consecutive readable structural faults
on the same plate can save a report and prompt once per session. It cannot
detect missing pixels when WoW reports the frames as healthy; use the capture
key for that case. Zero plates alone does not trigger a warning.

The last three reports survive normal reload/logout. They contain bounded
counts, frame flags, relevant visibility switches, buffer readings, fixed event
labels, relative session times, addon version, and numeric client build. They
exclude names, GUIDs, locations, chat, hardware, addon inventories, and raw
errors. Nothing is uploaded automatically.

`/dui platewatch off` disables background watching, retaining manual capture.
`/dui platereport clear` clears saved reports. Both ZIPs include the same
capture, buffer-status, and optional render-probe diagnostics.

## Validation and source

The combined experimental source passed **5,634 tests across 159 files**.
Six designated slow sweeps were excluded. Tests check Lua behavior, not native
taint propagation or rendered pixels. Both ZIPs passed integrity checks; all
926 entries were compared and only the five listed files differed.

Base source: `64e7676d016cc0c7ed1fe5c6f627c2d248cb62e4`.
Diagnostic commit: `cef8022d112e803a2f80fd8969afbc2f0688c3a0`.
Layout experiment commit: `ea4f58bdcc0210ccd183d4f8eb7a294d5a47cc49`.
The test attachments are excluded from addon packaging by `.pkgmeta`.

SHA-256:

```text
2b0eac77c4eca0e41798c31a31f97af8866d302b58912e6c8399c4b3df48c428  DaylightUI-issue80-capture-control.zip
d7083b32f0db4046a3234ad59fe9936cb56ee3489df7870a1b6bd37a27d79435  DaylightUI-issue80-no-layout-overrides.zip
```
