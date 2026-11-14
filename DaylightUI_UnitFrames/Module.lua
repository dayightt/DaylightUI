-- Registers the unit frames with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("UnitFrames", {
    -- Every file that defines a part. If one is missing after an update, the
    -- module turns itself off with a single line in chat.
    ns = ns,
    parts = { "UF", "HealSpells", "Auras", "Spots", "AuraGroups", "Indicators", "Texts", "Looks", "Combo", "Happiness", "DruidBars", "Blizzard", "Group", "Raid", "PartyPets", "PartyTargets", "PartyCasts", "Party", "Arena", "Leader", "Pull", "Test", "Sample",
               "PageSample", "Sweep", "CastBar", "PowerBar", "Personal", "Arrive", "Moments", "Swing", "GroupParts", "GroupPrivate",
               "ClickCast", "ClickBinder", "ClickCastPage" },
    label = "Unit Frames",
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod) ns.Build(mod) end,
    OnSettingChanged = function(mod, path) ns.Refresh(mod, path) end,
    OnStyleChanged = function(mod) ns.Refresh(mod) end,
    -- Sample frames shown inside other windows, like the setup guide (Sample.lua).
    Samples = function(_, parent) return ns.Sample.Pair(parent) end,
})
