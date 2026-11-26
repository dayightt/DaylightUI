-- The Proc Alerts pages in the options window. The Alerts page opens on the
-- switch for every alert, then edits one proc at a time, picked under it; its
-- rows read and write that proc's own settings (Alerts.lua). General holds the
-- rest of what applies to every alert.

local _, ns = ...
local DUI = DaylightUI

local Options = {}
ns.Options = Options

local SINCE = "2.2.8"

-- The proc the Alerts page edits: the one picked, else the player's first.
function Options.Selected()
    local key = Options.selected
    if key and ns.Data.BY[key] then return key end
    local mine = ns.Data.Mine()
    return mine[1] and mine[1].key or "overpower"
end

local function sel() return Options.Selected() end
local function proc() return ns.Data.BY[sel()] end

local function refreshPanel()
    local P = DUI.OptionsPanel
    if P and P.IsShown and P.IsShown() then P.Refresh() end
end

-- A row bound to one field of the picked proc.
local function field(name, item)
    item.since = item.since or SINCE
    item.get = function() return ns.Alerts.Get(sel(), name) end
    item.set = function(v) ns.Alerts.Set(sel(), name, v) end
    item.default = function() return ns.Alerts.Default(sel(), name) end
    return item
end

-- The procs this character can set up: its class's, then the gear it has.
local function choices()
    local values, order, titles = {}, {}, {}
    local gear = false
    for _, p in ipairs(ns.Data.Mine()) do
        if ns.Data.Have(p) then
            if p.class == "GEAR" and not gear then
                gear = true
                values["head:gear"] = "Weapons and enchants"
                order[#order + 1] = "head:gear"
                titles["head:gear"] = true
            end
            values[p.key] = ns.Data.Name(p)
            order[#order + 1] = p.key
        end
    end
    return values, order, titles
end

local function list(tbl, ord)
    local values, order = {}, {}
    for _, k in ipairs(ord) do values[k] = tbl[k].name; order[#order + 1] = k end
    return values, order
end

local designValues, designOrder = list(ns.Data.DESIGNS, ns.Data.DESIGN_ORDER)
local animValues, animOrder = list(ns.Data.ANIMS, ns.Data.ANIM_ORDER)

-- Every alert off: the rows below the switch are dimmed.
local function allOff() return DUI:Get("Procs", "enabled") == false end
local function off() return allOff() or ns.Alerts.Get(sel(), "enabled") == false end

local EVERY = {
    { type = "toggle", key = "enabled", label = "Show proc alerts", since = SINCE,
      desc = "Turns every proc alert on or off at once. When off, no flare shows and Proc Alerts watches nothing." },
}

local ALERT = {
    { type = "dropdown", label = "Alert", since = SINCE, search = "proc alert flare clearcasting overpower", disabled = allOff,
      desc = "Which proc the settings below change. Your class's procs come first, then the ones from weapons and enchants.",
      choices = choices,
      get = sel,
      set = function(k)
          if ns.Data.BY[k] then Options.selected = k end
          refreshPanel()
          if DUI.testMode and DUI.TestPartShown("procs") then ns.Flares.EndTests(); ns.Flares.Test(sel(), false) end
      end },
    field("enabled", { type = "toggle", label = "Show this alert", disabled = allOff,
        desc = "Lights up this proc's flare around your character when it's ready. Show proc alerts turns every one off at once." }),
}

local LOOK = {
    field("design", { type = "dropdown", label = "Design", values = designValues, order = designOrder,
        desc = "The painted light this proc shows. Each design has its own spot around your character, so two procs at once never look alike.",
        disabled = off }),
    field("anim", { type = "dropdown", label = "Animation", values = animValues, order = animOrder,
        desc = "How the flare moves while it's up. Every one flickers like flame: Strike is the liveliest, Breathe dims slowly, Pulse beats, Impact sends out a wave, Flash gleams from base to tip. Still doesn't move.",
        disabled = off }),
    field("speed", { type = "slider", label = "Animation speed", since = "2.3.1", min = 0.5, max = 2, step = 0.1, unit = "x",
        desc = "How fast the animation moves. Lower is calmer, higher is livelier.",
        disabled = function() return off() or ns.Alerts.Get(sel(), "anim") == "still" or not DUI.Motion.On() end }),
    field("embers", { type = "toggle", label = "Embers", since = "2.4.1",
        desc = "Little embers rising from the flare while it's up.",
        disabled = function() return off() or ns.Alerts.Get(sel(), "anim") == "still" or not DUI.Motion.On() end }),
    field("colorMode", { type = "dropdown", label = "Colors", disabled = off,
        values = { accent = "Accent color", class = "Class gradient", custom = "Custom gradient" },
        order = { "accent", "class", "custom" },
        desc = "The flare's colors, bottom to top: your accent (General > Appearance), your class's gradient, or two colors you pick." }),
    field("colorTop", { type = "color", label = "Top color", disabled = off,
        desc = "The flare's color at its top when Colors is Custom gradient.",
        hidden = function() return ns.Alerts.Get(sel(), "colorMode") ~= "custom" end }),
    field("colorBottom", { type = "color", label = "Bottom color", disabled = off,
        desc = "The flare's color at its bottom when Colors is Custom gradient.",
        hidden = function() return ns.Alerts.Get(sel(), "colorMode") ~= "custom" end }),
    field("size", { type = "slider", label = "Size", min = 0.5, max = 2, step = 0.05, unit = "x", disabled = off,
        desc = "This flare's size. Size of all alerts (General) changes every one." }),
    field("alpha", { type = "slider", label = "Opacity", min = 0.2, max = 1, step = 0.05, unit = "%", disabled = off,
        desc = "How see-through this flare is." }),
    field("x", { type = "slider", label = "Move sideways", min = -300, max = 300, step = 2, unit = "px", disabled = off,
        desc = "Moves this flare left or right. A flare on both sides moves both halves outward, or inward below 0." }),
    field("y", { type = "slider", label = "Move up", min = -300, max = 300, step = 2, unit = "px", disabled = off,
        desc = "Moves this flare up, or down below 0." }),
}

local WHEN = {
    field("sound", { type = "dropdown", label = "Sound", fallback = "none", disabled = off,
        desc = "Plays once as the proc lands. Procs only the game can see play none, since Daylight UI never learns when they land.",
        choices = function() return DUI.Sound.AlertChoices() end,
        hover = function(k) DUI.Sound.AlertHover(k) end,
        onPick = function(k) DUI.Sound.AlertSample(k) end }),
    field("combatOnly", { type = "toggle", label = "Only in combat", disabled = off,
        desc = "Shows this flare only in a fight. Turn it off for procs that often come right after one, like Victory Rush." }),
    field("drain", { type = "toggle", label = "Drain as time runs out", disabled = off,
        desc = "The flare shortens from its tip as the proc's time runs out. When off, it stays whole until it's gone.",
        hidden = function() return proc() ~= nil and proc().noTimer == true end }),
    field("fromStacks", { type = "slider", label = "Show from", min = 1, max = 5, step = 1, disabled = off,
        desc = "The stack count this flare starts showing at. It stays dimmer until its last stack.",
        hidden = function() return not (proc() and proc().stacks) end }),
}
-- The stack slider can't pass this proc's most.
do
    local set = WHEN[4].set
    WHEN[4].set = function(v)
        local most = proc() and proc().stacks or 1
        set(math.max(1, math.min(most, v)))
    end
end

local ACTIONS = {
    { type = "button", label = "Show it now", text = "Show", since = SINCE,
      desc = "Shows this proc's flare for ten seconds, as it looks with these settings.",
      disabled = allOff,
      func = function() ns.Flares.Test(sel()); ns.Flares.PlaySound(sel()) end },
    { type = "button", label = "Copy this look to my other alerts", text = "Copy", confirm = true, since = SINCE, disabled = allOff,
      desc = "Gives your other alerts this one's animation, colors, size, opacity and sound. Each keeps its own design, so they still look different.",
      func = function() ns.Alerts.CopyToClass(sel()) end },
    { type = "button", label = "Reset this alert", text = "Reset", confirm = true, since = SINCE, disabled = allOff,
      desc = "Puts this proc's look and sound back to how Daylight UI starts it.",
      func = function() ns.Alerts.Reset(sel()) end },
}

ns.OPTIONS = { pages = {
    { id = "alerts", label = "Proc Alerts", preview = { "procs" },
      sample = function(parent) return ns.Sample.New(parent) end,
      desc = "A painted flare around your character when a proc is ready: each one with its own look and sound.",
      groups = {
          { label = "Every alert", items = EVERY },
          { label = "Alert", items = ALERT },
          { label = "Look", items = LOOK },
          { label = "When it shows", items = WHEN },
          { label = "Try it", items = ACTIONS },
      } },
    { id = "general", label = "General", desc = "What applies to every proc alert.",
      groups = {
          { label = "Every alert", items = {
              { type = "slider", key = "scale", label = "Size of all alerts", min = 0.5, max = 2, step = 0.05, unit = "x", since = SINCE,
                disabled = allOff, desc = "Grows or shrinks every flare and the space between them. Each alert's own Size adds to it." },
              { type = "slider", key = "alpha", label = "Opacity of all alerts", min = 0.2, max = 1, step = 0.05, unit = "%", since = SINCE,
                disabled = allOff, desc = "How see-through every flare is." },
              { type = "toggle", key = "soundOn", label = "Alert sounds", since = SINCE,
                disabled = allOff, desc = "Plays each alert's sound as its proc lands. When off, the flares stay silent." },
          } },
      } },
} }
