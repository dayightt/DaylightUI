# Daylight UI for addon authors

Daylight UI has a public API, `DaylightUI.API`, for addons that want to look like Daylight UI or
build on its frames: add healer features to the raid tiles, put a marker on nameplates, dress your
own window in the same shells, fonts and colors, or put your settings on Daylight UI's own options
pages.

Build on what's on this page: it keeps working from update to update. You (or your AI) may read
any of Daylight UI's files to see how it works and which function to hook, but never copy its code,
art or text into your addon: write your own.

Having an AI write the code? Read the next section first. The rest of the page is the full list
of calls.

## Using an AI to write it

AI tools often write WoW code for the wrong version of the game (old Classic rules) or make up
calls that don't exist. Paste this at the start of your chat so it writes code that works:

```
I'm writing a World of Warcraft addon for WoW: Forever (Interface 16001). It runs on the modern
client (Midnight 12.x rules): secret values in combat and under addon restrictions, C_* namespaces.
It builds on the Daylight UI addon, through DaylightUI.API. Rules:
- Use the calls in Daylight UI's API.md (I'll paste it) first. Don't invent DaylightUI calls.
- You may read any of Daylight UI's files (the DaylightUI folder and every DaylightUI_ module
  folder) to understand how it works and find the function to Paint over or hook. Never copy its
  code, art or text into my addon: write the code yourself, in your own words.
- Make windows and controls with API.Skin, API.Text, API.Button, API.Close, API.Switch, API.Input,
  API.Bar and API.Menu, not the game's templates or hand-made textures.
- Text colors from API.Colors() (VALUE, TEXT, LABEL, OFF, GOOD, WARN, BAD) or API.Accent(); text
  sizes "tiny", "small", "body", "head", "title". No typed-in colors.
- To restyle Daylight UI's frames use me.Paint(kind, fn, { owns = {...} }) and the parts it hands
  over; to add things, draw on API.Attach(frame). Never move, resize, show or hide Daylight UI's
  frames.
- Health, threat and other combat values can be secret: never compare them, do math on them or use
  them in an if. Check with issecretvalue(x).
- Never use hooksecurefunc on Daylight UI's frames or the game's frames' methods. To change one of
  Daylight UI's own functions use me.Hook / me.Wrap.
```

Then paste this whole page (API.md) and say what you want to make. When the AI gives you code, run
it in game, and if anything breaks, paste the full error back to it (see "When something goes
wrong" below).

## The promise

```lua
local API = DaylightUI.API
print(API.major, API.minor)   -- 1, 5
```

- `minor` goes up when something is added. Old calls keep working.
- `major` goes up only when something promised here changes or goes away.
- Register as a plugin with the version you use: `needs = { 1, 4 }` for Paint on nameplates and
  their cast bars (1.4), `{ 1, 3 }` for Paint, hooks, texts and settings (1.3), `{ 1, 2 }` for the vendor's tiles, the profession window and font rows (1.2),
  `{ 1, 1 }` for the rest. If the player's Daylight UI is too old, or a different major, your plugin
  stays off with one line in chat instead of an error.

Add `## OptionalDeps: DaylightUI` (or `Dependencies`) to your `.toc` so Daylight UI loads first.

## Quick start

```lua
local API = DaylightUI and DaylightUI.API
if not API or API.major ~= 1 then return end

local f = CreateFrame("Frame", "MyAddonWindow", UIParent)
f:SetSize(300, 200)
f:SetPoint("CENTER")
API.Skin(f, { window = true })            -- Daylight UI's window shell

local title = API.Text(f, "title")
title:SetPoint("TOPLEFT", 16, -14)
title:SetText("My Addon")

local close = API.Close(f, function() f:Hide() end)
close:SetPoint("TOPRIGHT", -10, -10)

local go = API.Button(f, "Go", 24)
go:SetSize(100, 24)
go:SetPoint("BOTTOM", 0, 16)
```

The player's font, accent color, text sizes and window opacity are read when you call these, so
your window matches whatever they've picked.

## Quick recipes

The jobs plugins do most, one short example each. The sections after this are the full list.

**Swap the cast bar's fill for your own texture** (it stays, cast after cast):

```lua
local me = DaylightUI.API.For("Neon")
me.Paint("castbar", function(bar, parts, cast)
    parts.fill:SetTexture("Interface\\AddOns\\Neon\\rainbow")
end, { owns = { "fill" } })
```

`owns` claims the fill: Daylight UI stops coloring and texturing it, so your texture shows as you
drew it. Without `owns` Daylight UI keeps its own look and your function paints on top after it.
The same function with `"platecast"` does the nameplates' cast bars (1.4).

**Recolor the nameplates' names** (1.4):

```lua
me.Paint("nameplate", function(plate, parts, unit)
    parts.name:SetTextColor(1, 0.85, 0.4)
end, { owns = { "name" } })
```

**Color action buttons your own way** (1.5), the job ElvUI plugins do on its bars:

```lua
me.Paint("actionbutton", function(button, parts, info)
    if not info or info.empty then return end
    if info.outOfRange then
        parts.icon:SetVertexColor(0.9, 0.2, 0.2)
    elseif info.noPower then
        parts.icon:SetVertexColor(0.3, 0.4, 1)
    else
        parts.icon:SetVertexColor(1, 1, 1)
    end
end, { owns = { "icon" } })
```

**Recolor every health bar** (unit frames, party and raid tiles):

```lua
for _, kind in ipairs({ "unit", "party", "raid" }) do
    me.Paint(kind, function(frame, parts, unit)
        parts.healthFill:SetVertexColor(0.2, 1, 0.8)
    end, { owns = { "healthFill" } })
end
```

**Add your own text to the unit frames** (players pick it in Extra text like Daylight UI's):

```lua
me.AddText("shards", { label = "Soul shards", on = { "power" },
    text = function(unit) return GetItemCount(6265) end })
```

**Mark something on a frame:**

```lua
me.Paint("bagslot", function(slot, parts, item)
    local mark = MyAddon:MarkFor(slot)                -- your own texture, made once on API.Attach(slot)
    mark:SetShown(item and item.itemID == 6265)
end)
```

**Put a setting on a Daylight UI page:** `me.AddOptionsGroup` (below), or keep it beside Daylight
UI's own settings with `me.AddDefaults("UnitFrames", { neonGlow = 0.5 })`.

## Look like Daylight UI

| Call | What it gives you |
|---|---|
| `API.Skin(frame, opts)` | The shell: shadow, rounded border, band, bevel, background. Call it again after resizing. `opts`: `window = true` (background follows the player's window opacity), `noBorder`, `noBackground`, `noBevel`, `bgAlpha`, `borderPx`. |
| `API.Text(parent, size, justify)` | A font string in the player's font, outline and shadow. `size`: `"tiny"` `"small"` `"body"` `"head"` `"title"` (10/12/13/15/18). |
| `API.Bar(parent)` | A status bar with the Daylight gradient fill. Set it like any `StatusBar`. |
| `API.Button(parent, text, height)` | A button. Hovering traces its edge in the accent; click sound built in. |
| `API.Close(parent, onClick, size)` | The close X. |
| `API.Switch(parent)` | An on/off switch. `sw.SetOn(true)`. |
| `API.Input(parent, opts)` | A text or search box. `opts`: `search`, `hint`, `numeric`, `onChange = function(text) end`. |
| `API.Menu(owner, keys, values, current, onPick, width, opts)` | A dropdown menu under `owner`. `keys` = the order, `values[key]` = the shown word, `onPick(key)`. `opts.atCursor = true` for a right-click menu. |
| `API.Accent()` | The player's accent color, `r, g, b`. Read it each time you paint; it can change. |
| `API.Colors()` | The text colors, each `{ r, g, b }`: `TITLE`, `VALUE`, `TEXT`, `LABEL`, `OFF`, `GOOD`, `WARN`, `BAD`, `DAMAGE`, `MONEY`. |
| `API.Font()` | The path of the player's font. |
| `API.FontFile(key)` | The path of the font a font row (below) saved: `"general"` or `nil` = the player's font. |
| `API.ClassColor(token)` | A class color, `r, g, b` (softened the way Daylight UI shows it). |
| `API.Fade(region, toAlpha, speed)` | Eases a region of yours to an alpha from where it is. `speed`: `"FAST"` `"NORMAL"` `"SLOW"` or seconds. A hidden region is only set to it, never shown. |
| `API.Speed` | `{ FAST = 0.12, NORMAL = 0.2, SLOW = 0.4 }`, the only three speeds Daylight UI uses. |

To fit in, color text the way Daylight UI does: values `VALUE` (white), sentences `TEXT` (soft
white), labels `LABEL` (tan), unavailable things `OFF`. Use color only on the one or two words a
glance needs: a number that matters in the accent, `GOOD`/`WARN`/`BAD` for done, low and out. Avoid
plain gray.

## Build on Daylight UI's frames

### Find a frame

| Call | Returns |
|---|---|
| `API.GetUnitFrame(unit)` | The frame showing that unit: a shown raid tile first, then party, then the single frames (player, target, focus...), then party pets. `nil` if none. |
| `API.GetNameplate(unit)` | The nameplate for `"nameplate3"` and so on. |
| `API.GetActionButton(bar, i)` | Button `i` of action bar `bar`: its number `1`-`8`, or its key `"main"`, `"bar2"`, `"left"`, `"right"`, `"bar5"`-`"bar8"`. |
| `API.GetActionBar(bar)` (1.5) | The frame holding a whole bar: the same numbers and keys, plus `"stance"`, `"pet"`, `"possess"` and `"totem"`. |
| `API.GetShopTile(tab, index)` | The vendor window's tile for an item: `tab` = `"buy"` or `"buyback"`, `index` = the game's index there. `nil` when it isn't on show. |
| `API.GetCraftRow(recipeID)` | The profession window's line for a recipe, while it's on show. |
| `API.GetQuestRow(questID)` | The quest tracker's row for a quest, while it's on show. |
| `for frame, unit in API.Frames(kind) do ... end` | Every frame of one kind. |

Kinds: `"unit"` (player, target, targettarget, pet, focus), `"party"`, `"raid"`, `"partypet"`,
`"nameplate"`, `"actionbutton"`, and since 1.2 the rows of Daylight UI's windows:

- `"shoptile"`: an item tile in the vendor window. Its `unit` is `"buy:<index>"` (the shop) or
  `"buyback:<index>"` (Buy back). `API.ShopItem(frame)` returns `tab, index, itemID, link`.
- `"craftrow"`: a recipe line in the profession window. Its `unit` is the recipe's id.

Since 1.3:

- `"castbar"`: a cast bar (yours, your target's, your focus's, each party member's). Its `unit` is
  the unit it shows.
- `"questrow"`: a quest in the quest tracker. Its `unit` is the quest's id.
- `"bagslot"`: an item slot in the bag, bank and alts windows. Its `unit` is `"bag:slot"`; a saved
  copy (an alt's bags) comes as a preview.

Since 1.4:

- `"platecast"`: a nameplate's cast bar. It comes and goes with its plate, and its `unit` is the
  plate's (`"nameplate3"`). Same pieces and `info` as `"castbar"`, so one function can paint both.

Since 1.5:

- `"actionbar"`: a bar's holder, the frame its buttons sit in. Its `unit` is the bar's key
  (`"main"`, `"bar2"`... `"stance"`, `"pet"`). It gets `FrameStyled` each time the bar is laid out
  again (size, rows, spacing). An `"actionbutton"`'s `unit` is `"<bar number>:<button>"`, `"1:5"`.

Tiles and lines are reused as the list changes (a search, another vendor), so they work like
nameplates: `FrameUnitChanged` when one shows another item, `FrameRemoved` when it's hidden or the
window closes. After every fill (money or bags changed, a search, a skill-up) each one on show gets
`FrameStyled`: that's your cue to repaint, since Daylight UI just painted it again. A tile that keeps
its index but holds another vendor's item gets `FrameUnitChanged` with the same `unit`: read
`API.ShopItem` again. These windows can be switched off (or replaced by DaylightMogul's); then there
are no tiles or lines at all.

### Hear when they change

```lua
local handle = API.On("FrameMade", function(kind, frame, unit, isPreview)
    if kind == "raid" then MyAddon:Decorate(frame) end
end, "MyAddon")
-- API.Off(handle) stops it.
```

| Event | Arguments | When |
|---|---|---|
| `FrameMade` | kind, frame, unit, isPreview | A frame is made. A listener added later is told about every frame already made, so you never miss one. |
| `FrameUnitChanged` | kind, frame, unit, isPreview | A frame shows a different unit (a raid tile after a roster change, a reused nameplate, a new target). |
| `FrameRemoved` | kind, frame, unit, isPreview | A frame lets its unit go. A reused frame gets this for the old unit before `FrameUnitChanged`. |
| `FrameStyled` | kind, frame, unit, isPreview | Daylight UI repainted the frame (settings changed). Redo your own look here. |
| `StyleChanged` | | The player changed the font, accent or another look setting. |
| `SettingChanged` | scope, path, value | Any Daylight UI setting changed. |
| `TestModeChanged` | | `/dui test` turned on or off. |
| `UnlockChanged` | | `/dui unlock` or lock. |
| `Login` | | Daylight UI finished loading for this character. |
| `CraftShown`, `CraftHidden`, ... | | The profession window's own: see "The profession window" below. |

`isPreview` is true for sample frames (test mode, the options window's live preview). Lookups never
return those, but events include them so your additions show in the preview too.

Pass your addon's name as the third argument: if your handler errors, chat names your addon once,
and Daylight UI and the other handlers keep running.

### Put your pieces on a frame

```lua
API.On("FrameMade", function(kind, frame)
    if kind ~= "raid" and kind ~= "party" then return end
    local holder = API.Attach(frame)
    local mark = holder:CreateTexture(nil, "OVERLAY")
    mark:SetSize(10, 10)
    mark:SetPoint("TOPRIGHT", -2, -2)
    mark:SetColorTexture(API.Accent())
end, "MyAddon")
```

`API.Attach(frame)` gives you a plain frame laid over Daylight UI's frame, above its art. It's the
same holder every time you ask. Draw on that, never on Daylight UI's own parts: those change
between versions. Only Daylight UI's frames (the ones the frame events and lookups hand you) get a
holder; any other frame gets `nil`.

To tint a tile's or a line's own pieces, ask for them by name: `API.GetPart(frame, part)`, `part` =
`"icon"` (a texture) or `"name"` (a font string), on `"shoptile"` and `"craftrow"` frames. Paint
them in `FrameStyled`; Daylight UI repaints them on every fill.

```lua
-- Mark demon grimoires you already know at the vendor.
API.On("FrameStyled", function(kind, tile)
    if kind ~= "shoptile" then return end
    local tab, index, itemID = API.ShopItem(tile)
    if tab == "buy" and itemID and MyAddon:Known(itemID) then
        API.GetPart(tile, "icon"):SetVertexColor(0.4, 0.4, 0.4)
        API.GetPart(tile, "name"):SetTextColor(unpack(API.Colors().OFF))
    end
end, "MyAddon")
```

### The profession window

| Call | What it does |
|---|---|
| `API.SelectCraftRecipe(recipeID)` | Picks a recipe, as a click on its line would: it lights, scrolls into view and shows on the right. `true` when it did; `false` when the window isn't open on your own profession or the recipe isn't learned. |
| `API.GetCraftProfession()` | The open profession: `skillLine, name`. `nil` while the window is shut. |
| `me.AttachCraftPane(width)` | A panel of yours docked to the window's right edge (below). |

Its events (`API.On`, like the frame events):

| Event | Arguments | When |
|---|---|---|
| `CraftShown` | | The profession window opened. |
| `CraftHidden` | | It closed. |
| `CraftProfessionChanged` | skillLine | It shows a profession (on opening too, after `CraftShown`). |
| `CraftRecipeSelected` | recipeID | A recipe is picked: a click, `API.SelectCraftRecipe`, or the first one when a profession opens. |
| `CraftStarted` | recipeID, count | Create or Create all started making `count`. |
| `CraftMade` | recipeID, done, count | One more made. |
| `CraftStopped` | recipeID, done, count | Making ended: all made, stopped, or a cast failed (`done` < `count`). |

These are Daylight UI's own profession window only. With it switched off, or DaylightMogul's in its
place, they never come; listen to the game's `TRADE_SKILL_SHOW` and `TRADE_SKILL_CLOSE` too if you
want both.

```lua
local me = API.For("MyAddon")
local pane = me.AttachCraftPane(220)      -- the same frame each time you ask
local title = API.Text(pane, "head")
title:SetPoint("TOPLEFT", 14, -14)
me.On("CraftRecipeSelected", function(recipeID)
    title:SetText(C_TradeSkillUI.GetRecipeInfo(recipeID).name)
end)
```

The pane sits on the window's right edge, the window's full height, in the window's own shell. It
moves, scales, opens and closes with the window, and the game's other windows make room for it. Two
plugins' panes sit side by side, in the order they asked. Asking again with another width resizes
yours. It never shows while Daylight UI's profession window isn't in use.

### Paint: your look on Daylight UI's frames

```lua
local handle = me.Paint(kind, function(frame, parts, info) ... end, { owns = { "fill" } })
API.Off(handle)   -- stop: the frames get Daylight UI's look back at once
```

Your function runs on every frame of that kind there now (a frame made later, as it's made), then
again right after each time Daylight UI paints one. That's the whole job: no events to listen to,
nothing to find. `parts` are the frame's pieces by name; `info` says what it shows (below), and can
be `nil` on the first call. Your errors name your addon; Daylight UI's own paint has already
happened, and your function is called again on the next one.

`owns` claims pieces: Daylight UI stops coloring and texturing them (sizes, places and shapes
stay its own). Two plugins claiming the same piece: the first keeps it, the second gets one line in
chat. When you stop, the piece passes to the next plugin that asked for it, or back to Daylight UI.

| Kind | Parts | When it's painted | `info` |
|---|---|---|---|
| `"castbar"` | `fill`, `bar`, `back`, `name`, `time`, `icon` | each cast or channel, an interrupt, a setting | `{ unit, spellID, channel, notInterruptible, interrupted }` |
| `"platecast"` (1.4) | the same as `"castbar"` | each cast or channel, an interrupt, a setting | the same as `"castbar"` |
| `"actionbutton"` (1.5) | `icon`, `border`, `band` (tables of textures), `hotkey`, `count`, `macro` (the macro's name), `cooldown`, `highlight`, `pushed`, `checked`, `flash` | a new action in the slot, a change in how it reads (usable, short of power, out of range, a real cooldown starting or ending, a proc, hover or press lighting the border), a setting; never on a cooldown tick | `API.ButtonInfo`'s table (below) |
| `"nameplate"` (1.4) | `health`, `healthFill`, `healthBack`, `healthText`, `power`, `powerFill`, `powerBack`, `name`, `guild` (the guild or title line), `level`, `dragon` (the elite mark), `marker` (the raid marker), `cast` (its cast bar's frame) | a new unit, a recolor (reaction, threat, tapped, a boss or rare color), the level, guild line or power type, a setting; never on each health tick | the unit |
| `"unit"`, `"party"`, `"raid"`, `"partypet"` | `health`, `healthFill`, `healthBack`, `power`, `powerFill`, `powerBack`, `name`, `level`, `texts` (a list), `portrait`, `classIcon`, `border`, `band` (lists of textures) | a new unit, a recolor (class, reaction, dead, offline), a layout or setting; never on each health tick | the unit |
| `"questrow"` | `title`, `objectives` (a list), `bar`, `icon` | each layout of the tracker | `{ questID }` |
| `"bagslot"` | `icon`, `count`, `border` (a list of textures) | each fill of the slot | `{ bag, slot, itemID, link, quality, count }` |
| `"shoptile"` | `icon`, `name` | each fill of the shelf | `{ tab, index, id, link }` |
| `"craftrow"` | `icon`, `name` | each fill of the list | `{ recipeID }` |

Action buttons: claims honored are `icon` (Daylight UI stops tinting, fading and graying it),
`border` (the border and band stop changing color: read `info.border` to light it yourself),
`hotkey`, `count` and `macro` (their text color). Only bars 1-8 are buttons of Daylight UI's; the
stance and pet buttons are the game's.

Pieces a unit frame doesn't have (a raid tile's portrait) are `nil`. Claims that are honored on
every repaint, the per-tick health color too: `healthFill`, `healthBack`, `powerFill`, `powerBack`,
`name` on unit frames, `fill` and `back` on cast bars (a nameplate's too), and on nameplates
`healthFill`, `healthBack`, `powerFill`, `powerBack`, `name`, `guild`, `level` and `dragon`. A
`back` claim counts together with its fill's. A nameplate's threat border, glow and pulse stay
Daylight UI's over a claimed fill (they're fight information). Other pieces are painted only at the moments
in the table, so your paint right after wins. A cast you can't interrupt still shows Daylight UI's
warning over a claimed fill (it's fight information), and `interrupted` says the bar is showing an
interrupt. In a fight, another unit's `notInterruptible` and `spellID` may be secrets: hand them to
setters that take them (a `...FromBoolean` setter, `SetText`), never compare or test them. A plugin that wants to follow health uses the game's events
like any addon. `API.Parts(frame)` gives any frame's parts; `API.GetPart(frame, name)` one.

### Action bars

| Call | What it does |
|---|---|
| `API.ButtonInfo(button)` (1.5) | What a button shows and how it reads now, the same table its paint gets: `bar` (1-8), `barKey`, `index`, `slot`, `type` and `id` (the game's `GetActionInfo`), `empty`, `usable`, `noPower`, `outOfRange`, `cooling` (a real cooldown, not the global one), `proc`, `checked` (being cast, queued or repeating), `border` (why its border is lit: `"proc"`, `"pressed"`, `"hover"`, `"form"`, `"active"`, or `nil`). `nil` for any other frame. |
| `API.BindKeys()` (1.5) | Opens the game's key binding mode on the bars, as the Action Bars page's Bind keys button does. `false` in a fight or with the bars switched off. |
| `API.Glow(frame, on, r, g, b)` (1.5) | The glow the Cooldown Manager uses (the game's proc ring, easing in and out) on any of Daylight UI's frames, in your color or the accent. It sits on the frame's `API.Attach` holder, so it never fights Daylight UI's own glows. `false` for another frame or with the bars off. |

```lua
-- Light a button while your addon's buff is missing.
local button = API.GetActionButton(1, 3)
API.Glow(button, MyAddon:BuffMissing(), 1, 0.8, 0.2)
```

Where ElvUI plugins hook `StyleButton` or LibActionButton's `OnButtonUpdate`, `OnButtonUsable` and
`OnButtonState`, use `Paint` on `"actionbutton"`: it runs at the same moments, with `info` saying
what changed. Bars are made when the game loads, so a plugin can't add bars of its own.

### Your own texts on the unit frames

```lua
me.AddText(key, { label = "Soul shards", on = { "power" }, events = { "UNIT_AURA" },
    text = function(unit, frame) return text, r, g, b end, sample = "3" })
```

Players pick it in a frame's Extra text, beside Daylight UI's own (saved as `"MyAddon:key"`).
`on` = which of the frame's own updates redraw it: `"health"`, `"power"`, `"identity"` (name,
class, level), `"flags"` (AFK, dead), `"roster"`. `events` = game events whose first argument is a
unit: the frames showing that unit redraw it. `text` may return a secret (it's passed to `SetText`
whole); the color is optional. `sample` shows on test mode and the options preview. A text whose
addon is gone shows nothing.

### Change one of Daylight UI's functions

When Paint isn't enough, hook the function itself. **Not promised:** Daylight UI's functions can be
renamed or changed in any update, and your hook then does nothing or breaks; that's on your addon.

```lua
local UF = DaylightUI:GetModule("UnitFrames").ns.UF
local h = me.Hook(UF, "Layout", function(frame, cfg) ... end)       -- after Daylight UI's
local w = me.Wrap(UF, "PaintName", function(original, frame, ...)  -- around it
    original(frame, ...)
end)
me.Unhook(h)
```

Only Daylight UI's own tables (the core `DaylightUI`, a module's `ns`, a table inside either);
a frame or the game's tables are refused with one line in chat. Several addons can hook the same
function. An error in your hook names your addon; a `Wrap` that errors falls back to Daylight UI's
function so the frame keeps working. Each module's parts: `DaylightUI:GetModule(name).ns`.

### Your settings beside Daylight UI's

`me.AddDefaults(module, { key = default, ... })` adds settings to one of Daylight UI's modules:
`API.GetSetting("UnitFrames", "neonGlow")`, saved in the player's profile with Daylight UI's. A key
Daylight UI already has is refused (`false`, one line in chat). While your addon is switched off its
saved values stay, so they come back with it.

### Read settings

- `API.GetSetting(scope, path)`: read only. `API.GetSetting("general", "accent")`,
  `API.GetSetting("UnitFrames", "raid.width")`. `nil` when that module is off.
- `API.IsModuleEnabled(name)`: `"UnitFrames"`, `"Nameplates"`, `"ActionBars"`, `"Buffs"`,
  `"Tooltip"`, `"InfoPanel"`, `"Quests"`, `"Chat"`, `"Bags"`, `"Skins"`, `"QoL"`.

## Join in: movers, fade, test mode, commands, skins

`API.For("MyAddon")` gives you calls tied to your addon's name. What they make is kept apart from
everyone else's, and errors carry your name.

```lua
local me = API.For("MyAddon")
```

| Call | What it does |
|---|---|
| `me.RegisterMover(frame, key, label, default)` | Your frame gets a handle in `/dui unlock`, with grid snap and magnets, and its spot is saved in the player's profile. `default = { "CENTER", UIParent, "CENTER", 0, 0 }`. `true` once registered, `false` when refused (a key used twice, a missing frame). |
| `me.RegisterFade({ key, frames = function() return { f } end, scope, path })` | Your frames follow Daylight UI's fade (out of a fight, mouseover, and so on). `scope`/`path` = where your fade choices sit in your settings, a table `{ mode = "never"|"ooc"|"combat"|"always", alpha, mouseover, delay }`; left out, the usual defaults. `true` once registered, `false` when refused. |
| `me.RegisterTestPart(key, label, available)` | A part that `/dui test` shows. Check it with `DaylightUI.TestPartShown("plugin.MyAddon." .. key)`. |
| `me.RegisterCommand(word, fn, help)` | `/dui <word>` runs `fn(rest)`. `false` when the word is taken. |
| `me.RegisterSkin(addon, fn)` | Dresses another addon's window when that addon loads (below). |
| `me.AddOptionsGroup(pageId, group, after)` | Your settings on one of Daylight UI's pages (below). |
| `me.On(event, fn)` | `API.On` with your name filled in. |

### Skin another addon's window

```lua
me.RegisterSkin("SomeAddon", function(Kit)
    if not SomeAddonFrame then return false end   -- not made yet: asked again later
    Kit.Window(SomeAddonFrame)                     -- strips its art, Daylight UI's window look
    Kit.Auto(SomeAddonFrame)                       -- dresses the buttons, boxes, tabs, scroll bars inside
end)
```

`fn` runs once `SomeAddon` has loaded; return `false` to be asked again as more addons load. Returns
`false` when the player has Daylight UI's Skins module turned off. An error in `fn` names your addon
once in chat and stops that skin.

What `Kit` offers for the game's own templates:

| Call | For |
|---|---|
| `Kit.Window(frame, opts)` | A whole window: art stripped, the window shell, title font, the close X. `opts.noBackground`, `opts.keep` (texture keys to leave). |
| `Kit.Auto(root, opts)` | Walks a window and dresses every control it finds (buttons, boxes, tabs, checkboxes, dropdowns, scroll bars, item buttons, bars). `opts`: `skip` (a set of frames to leave), `bars`, `rows = false`, `controlsOnly`, `shownOnly`, `depth`. A big window is walked a little each frame, and the walk waits out a fight. |
| `Kit.Panel(frame)` / `Kit.Inset(frame)` | A side panel / an inset, a shade darker. |
| `Kit.SidePane(pane, skip)` | A detail pane beside a list: art gone, title in the player's font, the rest by `Kit.Auto`. |
| `Kit.Strip(frame, keep)` | Hides a frame's textures. `keep`: a set of textures to leave. |
| `Kit.Font(fs, size, color)` | The player's font on a font string. |
| `Kit.Light(fs, color)` | Repaints dark text (written for the game's parchment) light. |

Controls of the game's templates, one at a time:

| Call | For |
|---|---|
| `Kit.Button(btn)` | A button: the hover trace in the accent. |
| `Kit.Close(btn)` | A close X. |
| `Kit.Tab(tab, isSelected)` / `Kit.SideTab(tab, isSelected)` | A tab along the bottom / a side tab with an icon. |
| `Kit.Check(cb)` | A checkbox, as a switch. |
| `Kit.EditBox(eb)` | A text box. |
| `Kit.Dropdown(dd)` | A dropdown. |
| `Kit.IconButton(btn, pad, file)` | A small icon button: art gone, the icon in the text color. |
| `Kit.PageButton(btn, dir)` | A Prev / Next button, `dir` = `"left"` or `"right"`. |
| `Kit.CollapseButton(btn)` | A + / - button on a list's heading. |
| `Kit.Item(btn)` | An item button: the icon cropped, the item's quality outline. |
| `Kit.Slot(slot)` | An equipment slot. |
| `Kit.StatusBar(bar, color)` / `Kit.ProgressBar(bar)` | A status bar / a bar drawn with textures, in the bar look. |

Lists and scroll bars:

| Call | For |
|---|---|
| `Kit.ScrollBar(bar)` | A scroll bar, old (named) or new (`Track`/`Thumb`): a thin pill, the arrows out of sight but still there. `Kit.Auto` finds them by itself. |
| `Kit.EachRow(box, fn, key)` | A `ScrollBox` list: `fn(row)` for every row now, and again after each update of the list (rows are reused, so this is how they stay dressed). `key`: a name of your own, so a second `fn` on the same list runs too. |
| `Kit.Row(row, keep, selected, shell)` | One list row: the row look. `selected` = `function(row) return isPicked end`, or the game's selection texture (shown = picked); `shell = false` for a plain line (a wash under the mouse) instead of a box. After the pick changes, `Kit.RepaintRow(row)` (or `Kit.RepaintRows()` for all). |
| `Kit.ListRow(row)` | A row of a list like the character window's reputation or skills: a heading with its +/-, or an entry with its bar. |
| `Kit.RowIcons(row)` | Every icon in a row, cropped. |

```lua
me.RegisterSkin("SomeAddon", function(Kit)
    if not SomeAddonFrame then return false end
    Kit.Window(SomeAddonFrame)
    Kit.EachRow(SomeAddonFrame.ScrollBox, function(row)
        Kit.Row(row, nil, function(r) return r.isSelected end, false)
    end)
    Kit.ScrollBar(SomeAddonFrame.ScrollBar)
end)
```

### Put your settings on a Daylight UI page

```lua
DaylightUI:RegisterPlugin("MyAddon", { needs = { 1, 1 } })
DaylightUI:RegisterModule("MyAddon", { plugin = "MyAddon", label = "My Addon",
    defaults = { showHots = true, size = 10 } })

me.AddOptionsGroup("UnitFrames.raid", {
    label = "HoT markers",
    items = {
        { type = "toggle", key = "showHots", label = "Show HoT markers", desc = "A dot for each of your HoTs.", default = true },
        { type = "slider", key = "size", label = "Size", min = 6, max = 20, step = 1, default = 10,
          disabled = function(get) return not get("showHots") end },
    },
})
```

The group shows on the page with "From My Addon" after its name. Rows with a `key` save in your
module's settings (`API.GetSetting("MyAddon", "showHots")`), in the player's profile. Row types:
`toggle`, `slider` (`min`, `max`, `step`), `dropdown` (`values = { key = "Shown word" }`), `color`
(`{ r, g, b }`), `button` (`func`), `text`. `disabled` and `hidden` take a function of `get`. A row
that isn't right is left out with one line in chat; it can't break the page.

Every row:

| Field | For |
|---|---|
| `type` | One of the types above. |
| `key` | Where its value is saved in your module's settings (`"size"`, or a path `"bar.size"`). Not on `button` and `text`. |
| `label` | Its name, a few words. |
| `desc` | One or two sentences under it: what it does, in play. |
| `default` | Its value before the player changes it. On `AddOptionsGroup` rows; on a module's own pages the module's `defaults` hold it. |
| `disabled`, `hidden` | `function(get) return ... end`: dimmed / gone while true. `get(key)` reads your settings. |
| `min`, `max`, `step`, `unit` | Sliders. `unit`: `"px"`, `"%"` or `"x"`. |
| `values` | Dropdowns: `{ key = "Shown word" }`. |
| `func` | Buttons: runs on a click. |
| `reload = true` | The change takes a `/reload`: the page says so. |

A font picker, each font shown in itself (the one Daylight UI's own pages use): `API.FontRow(key,
label, desc)` returns the row. Its value is a font's key, `"general"` = the player's font (use that
as its default); `API.FontFile(value)` turns it into a path for `SetFont`.

```lua
me.AddOptionsGroup("appearance", { label = "My Addon", items = {
    API.FontRow("font", "My Addon's font", "The font of My Addon's window."),
    { type = "button", label = "Reset my window", func = function() MyAddon:Reset() end },
} })
-- defaults = { font = "general" } in your module
myText:SetFont(API.FontFile(API.GetSetting("MyAddon", "font")), 13, "")
```

A module's own pages (`RegisterModule`'s `options`) take the same rows:

```lua
options = { pages = {
    { id = "main", label = "My Addon", desc = "One line under the page's title.",
      groups = {
          { label = "Window", items = { ...rows... } },
          { label = "Look", items = { ...rows... } },
      } },
} }
```

Each page is in your plugin's section of the options window; its id on the page list is
`"<Module>.<id>"` (`"MyAddon.main"`), which `AddOptionsGroup` takes too.

Page ids: `"appearance"` (General), and `"<Module>.<page>"` for a module's pages, such as
`"UnitFrames.party"`, `"UnitFrames.raid"`. `after` = the label of a group on that page to follow.
A page that isn't there yet (its module turned off) gets the group when it appears. The
`"plugins"`, `"profiles"` and `"gradients"` pages build their own groups and take none: asked for
one, you get `false` and one line in chat.

## Your data in a data text slot

Daylight UI's data texts (the strip under the minimap and the data bar along the bottom) take any
[LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1) object, the way most data bars do.
Make one and it shows up in every slot menu (Info Panel > Data texts), under its label, beside
Daylight UI's own texts. Nothing else to call, and no Daylight UI needed to make it: the same object
works in any other broker display.

```lua
local ldb = LibStub("LibDataBroker-1.1")
local obj = ldb:NewDataObject("MyAddon", {
    type = "data source",                    -- or "launcher": shows its label and takes clicks
    label = "Kills",                         -- the word before the text (dropped on a narrow strip)
    text = "0",                              -- what it shows; or value = 0, suffix = "kills"
    icon = "Interface\\Icons\\Ability_Rogue_Ambush",   -- shown when the player has icons on
    OnClick = function(slot, button) end,     -- "LeftButton" or "RightButton"
    OnTooltipShow = function(tooltip)         -- your lines, under your label in Daylight UI's tooltip
        tooltip:AddLine("Kills this session")
    end,
})
obj.text = "12"   -- every slot showing it redraws (changes are gathered a tenth of a second)
```

- Ship LibDataBroker-1.1 (and LibStub, CallbackHandler-1.0) in your addon: Daylight UI only reads it.
- Text can carry color codes; with none, the text takes the player's accent like Daylight UI's own.
- `OnEnter(slot)` / `OnLeave(slot)` instead of `OnTooltipShow` hand the hover to you (your own
  tooltip library). `iconCoords`, `iconR`/`iconG`/`iconB` are followed; your icon keeps its colors.
- An object made after login (an addon loaded on demand) joins the menus then. A slot the player set
  to it stays empty until it's made, then fills.
- `OnClick` runs from a plain button: no protected actions (casting, using items) from it.

## A plugin of your own

General > Plugins lists every plugin with its author and version, a switch to turn it off for that
character (it takes a reload), and one line on what it changes ("Paints cast bars. Adds 1 text.
Hooks 2 functions."). An addon that uses `API.For` without registering is listed under that name,
with a switch when the name is its addon's.

A bigger addon can register as a Daylight UI plugin: it gets its own section in the options window,
under a Plugins heading, with its icon and color, and its settings ride in Daylight UI's profiles.

```lua
DaylightUI:RegisterPlugin("MyAddon", {
    needs = { 1, 1 },
    icon = "Interface\\AddOns\\MyAddon\\icon.png",   -- white on clear, tinted with its color
    color = { 0.4, 0.8, 0.6 },                       -- or "66cc99"
    short = "Mine",                                  -- its name in the options rail, one word
    blurb = "One line for the rail's tooltip.",
})
DaylightUI:RegisterModule("MyAddonBars", { plugin = "MyAddon", label = "Bars", defaults = { ... },
    options = { pages = { ... } }, OnEnable = function(self) ... end })
```

Title, author, version and website come from your `.toc` (`Title`, `Author`, `Version`,
`X-Website`) when you leave them out. General > Plugins lists every plugin with its author.

## The game's rules still apply

Daylight UI runs on the modern client's addon rules, and so does your code:

- **Secret values.** In combat, and under the client's restrictions (boss fights, keystones, PvP
  matches, some maps), health, threat and many other values come back secret. Never compare them,
  do math on them, or use them in an `if`. Pass them whole to setters that take them
  (`FontString:SetText`, `StatusBar:SetValue`, `SetAlpha`...). Check with `issecretvalue(x)`.
- **Protected frames.** Raid, party and unit frames are secure: you can't move, show, hide or
  resize them in combat. `API.Attach`'s holder is a plain child, so drawing on it is fine; don't
  reparent, re-anchor or resize Daylight UI's frames.
- **Paint and events first, hooks last.** Paint, the events and the calls on this page keep working
  across updates; a hooked function (`me.Hook`) can change in any of them.

## When something goes wrong

- **Nothing happens at all.** Check the folder name, the `.toc` name and the file list in the
  `.toc` all match. Open the AddOns list on the character screen and check your addon is ticked and
  not marked "out of date" (the `## Interface: 16001` line).
- **A Lua error pops up.** Get [BugSack](https://www.curseforge.com/wow/addons/bugsack) so you can
  see and copy the whole error. Give it to your AI, or read the first line: it names the file and
  line number.
- **"attempt to compare a secret value"** (or do math on one): you used a combat value in an `if`
  or a sum. Pass it straight to `SetText` / `SetValue` instead, or check `issecretvalue(x)` first.
- **"blocked" or "action forbidden" in combat**: something moved, resized, showed or hid a secure
  frame during a fight. Draw on `API.Attach(frame)` and change only your own pieces.
- **"DaylightUI has no event called ..."** in chat: a typo in an event name. The list is under
  "Hear when they change".
- **Your thing is missing from a frame after a `/reload`**: you set it up before the frame was
  made. Use `me.On("FrameMade", ...)`, which also tells you about frames made before you asked.

## Help

Questions or a missing call you need: the [Discord](https://discord.gg/eeSYZDd6ar), or
[open an issue](https://github.com/dayightt/DaylightUI/issues). A call that would help other authors
too is likely to be added in a minor version.
