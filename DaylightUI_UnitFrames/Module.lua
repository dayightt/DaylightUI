-- Registers the unit frames with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("UnitFrames", {
    -- Every file that defines a part. If one is missing after an update, the
    -- module turns itself off with a single line in chat.
    ns = ns,
    parts = { "UF", "HealSpells", "AuraLists", "Auras", "Spots", "AuraGroups", "Indicators", "Texts", "Looks", "Combo", "Happiness", "DruidBars", "Blizzard", "Group", "Raid", "PartyPets", "PartyTargets", "PartyCasts", "Party", "Arena", "Leader", "Pull", "Test", "Sample",
               "PageSample", "Sweep", "CastBar", "PowerBar", "Personal", "Arrive", "Moments", "Swing", "GroupParts", "GroupPrivate",
               "ClickCast", "ClickBinder", "ClickCastPage", "AuraListsPage" },
    label = "Unit Frames",
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod) ns.Build(mod) end,
    -- A list edit only changes what the aura rows match, no layout.
    OnSettingChanged = function(mod, path)
        if ns.AuraLists.IsListPath(path) then ns.AuraLists.Changed() else ns.Refresh(mod, path) end
    end,
    OnStyleChanged = function(mod) ns.Refresh(mod) end,
    -- Sample frames shown inside other windows, like the setup guide (Sample.lua).
    Samples = function(_, parent) return ns.Sample.Pair(parent) end,
})
