-- Registers the quest tracker with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("Quests", {
    label = "Quest Tracker",
    order = 122,
    ns = ns,
    parts = { "Blizzard", "Data", "Layout", "Look", "Rows", "Animate", "Items", "Clicks", "Details", "Journal", "Scroll", "Tracker", "Progress", "Nav", "Spots", "Route", "Arrow", "Bridge", "Voice", "Choice", "GiverTips" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        for _, c in ipairs(ns.Blizzard.CLASHES) do
            DaylightUI.WarnIfLoaded(c.addon, c.label, DaylightUI.L["quest tracker"])
        end
        if ns.Tracker then ns.Tracker.mod = mod end   -- read even when this tracker isn't built
        if ns.Blizzard.starved and ns.Tracker then ns.Tracker.Build(mod) end
        if ns.Journal then ns.Journal.Enable(mod) end
        if ns.Progress then ns.Progress.Enable(mod) end
        if ns.Nav then ns.Nav.Enable(mod) end
        if ns.Route then ns.Route.Enable(mod) end
        if ns.Arrow then ns.Arrow.Enable(mod) end
        if ns.GiverTips then ns.GiverTips.Enable(mod) end
        if ns.Choice then ns.Choice.Enable() end
        -- The nameplates' quest mark asks what a unit is wanted for: kill, loot, use or
        -- explore (Questie's answer when it's on, otherwise looked up in QuestieDB),
        -- shown in the accent. Gone when the module is off.
        DaylightUI.QuestKindForUnit = function(guid)
            if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
            local kind = ns.Bridge and ns.Bridge.PlateKind(guid)
            local npc = ns.GiverTips and ns.GiverTips.NpcID(guid)
            local need
            if npc then need = ns.Spots.NeedsNpc(npc) end
            kind = kind or need
            if not kind then return nil end
            local r, g, b = DaylightUI.Style.Accent()
            return kind, r, g, b
        end
        -- Questie's tracker and NPC tooltip lines step aside for these (DUI.QuestieAside
        -- in the core), which may have checked before this module was on.
        DaylightUI.Fire("QuestMapsChanged")
    end,
    OnSettingChanged = function(_, path)
        if string.sub(path, 1, 8) == "progress" then
            if ns.Progress then ns.Progress.Refresh() end
            return
        end
        if string.sub(path, 1, 9) == "mapQuests" then
            -- Questie's own NPC tooltip lines step aside for these (DUI.QuestieAside).
            DaylightUI.Fire("QuestMapsChanged")
            return
        end
        if string.sub(path, 1, 4) == "nav." or path == "nav" then
            if ns.Nav then ns.Nav.Refresh() end
            if ns.Route then ns.Route.Refresh() end
            if ns.Arrow then ns.Arrow.Refresh() end
            return
        end
        if path == "tracker" then
            if ns.Tracker then ns.Tracker.Follow() end
            -- Questie's tracker follows this choice (DUI.QuestieAside).
            DaylightUI.Fire("QuestMapsChanged")
            -- Questie only builds its tracker while loading (its own toggle reloads too),
            -- so switching to it needs a reload. Switching back doesn't.
            if DaylightUI:Get("Quests", "tracker") == false and ns.Bridge and ns.Bridge.Loaded() then
                DaylightUI.EditMode.AskReload(DaylightUI.L["Questie's tracker shows after a reload. Reload now?"])
            end
            return
        end
        if path == "journal" or path == "journalHoverIcons" then
            if ns.Journal then ns.Journal.Apply() end
            return
        end
        if string.sub(path, 1, 7) == "journal" then
            if ns.Journal then ns.Journal.OnStyleChanged() end
            return
        end
        if ns.Tracker and ns.Tracker.built then ns.Tracker.Apply(path) end
        -- The journal uses the tracker's colors and tags.
        if ns.Journal then ns.Journal.OnStyleChanged() end
    end,
    OnStyleChanged = function()
        if ns.Tracker and ns.Tracker.built then ns.Tracker.Apply() end
        if ns.Journal then ns.Journal.OnStyleChanged() end
        if ns.Nav then ns.Nav.OnStyleChanged() end
        if ns.Arrow then ns.Arrow.OnStyleChanged() end
        -- The card's headings use the accent, so an open card repaints.
        local card = ns.Details and ns.Details.card
        if card and card:IsShown() and card.quest then ns.Details.Show(card.quest) end
    end,
})
