-- Registers the unit frames with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("UnitFrames", {
    -- Every file that defines a part. If one is missing after an update, the
    -- module turns itself off with a single line in chat.
    ns = ns,
    parts = { "UF", "HealSpells", "AuraLists", "Auras", "Spots", "AuraGroups", "Indicators", "Texts", "Looks", "Combo", "Happiness", "DruidBars", "Blizzard", "Group", "Raid", "PartyPets", "PartyTargets", "PartyCasts", "Party", "Arena", "Leader", "Pull", "Test", "Sample",
               "PageSample", "Sweep", "Layers", "CastBar", "PowerBar", "Personal", "Arrive", "Moments", "Socket", "Swing", "GroupParts", "GroupPrivate",
               "ClickCast", "ClickBinder", "ClickCastPage", "AuraListsPage" },
    label = "Unit Frames",
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod) ns.Build(mod) end,
    -- A list edit only changes what the aura rows match, no layout.
    OnSettingChanged = function(mod, path)
        if ns.AuraLists.IsListPath(path) then ns.AuraLists.Changed() else ns.Refresh(mod, path) end
    end,
    -- Several settings changed together (DUI.Batch): the frames redraw once,
    -- as far as the widest of them reaches.
    OnSettingsChanged = function(mod, paths)
        local lists, last = false, nil
        for _, path in ipairs(paths) do
            if ns.AuraLists.IsListPath(path) then
                lists = true
            else
                if last then ns.Refresh(mod, last, true) end
                last = path
            end
        end
        if lists then ns.AuraLists.Changed() end
        if last then ns.Refresh(mod, last) end
    end,
    OnStyleChanged = function(mod)
        ns.Refresh(mod)
        -- Icons whose border wears the accent or class color: the client owns them,
        -- so the style repaint skips them.
        ns.Auras.RepaintBorders()
    end,
    -- Sample frames shown inside other windows, like the setup guide (Sample.lua).
    Samples = function(_, parent) return ns.Sample.Pair(parent) end,
})
