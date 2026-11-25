local stub = require("stub")

-- The Questie bridge (QuestieBridge.lua): the one place that reads Questie's
-- own code.

local function questie(modules, extra)
    stub.loadedAddOns.Questie = true
    local api = { isReady = true }
    _G.Questie = { API = api, db = { profile = { trackerEnabled = true } } }
    _G.QuestieLoader = {
        ImportModule = function(_, name)
            local m = modules[name]
            if type(m) == "function" then return m() end
            return m or { private = {} }
        end,
    }
    for k, v in pairs(extra or {}) do api[k] = v end
    return api
end

local function load(before)
    stub.Load({ quests = true, before = function()
        _G.Questie, _G.QuestieLoader = nil, nil
        stub.loadedAddOns.Questie = nil
        if before then before() end
    end })
    return stub.quests.Bridge
end

T.test("bridge: no Questie answers nil", function()
    local B = load()
    T.eq(B.Loaded(), false)
    T.eq(B.PlateKind("Creature-0-1-2-3-9-0"), nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bridge: Questie's icon hover reaches us and its white flash stays off", function()
    local waypoints = { SetHighlighted = function() end }
    local B = load(function() questie({ QuestieWaypoints = waypoints }) end)
    local seen = {}
    B.WatchHover(function(id) seen[#seen + 1] = id or "left" end)
    local data = { Id = 140 }
    waypoints.SetHighlighted(data, true)
    T.truthy(data.touchedPins, "Questie's tint step is skipped (MapIconTooltip: tint = not touchedPins)")
    waypoints.SetHighlighted(data, false)
    T.deq(seen, { 140, "left" })
    -- Stopped: Questie's own again, and a second watch doesn't hook twice.
    B.WatchHover(nil)
    local other = { Id = 141 }
    waypoints.SetHighlighted(other, true)
    T.isnil(other.touchedPins, "its flash is back")
    B.WatchHover(function(id) seen[#seen + 1] = id or "left" end)
    waypoints.SetHighlighted({ Id = 142 }, true)
    T.deq(seen, { 140, "left", 142 })
    -- A callback that breaks stays ours.
    B.WatchHover(function() error("boom") end)
    waypoints.SetHighlighted({ Id = 143 }, true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bridge: one quest's icons grow, the others fade, on both maps, all come back", function()
    local function icon(name, extra)
        local f = CreateFrame("Frame", name, UIParent)
        for k, v in pairs(extra or {}) do f[k] = v end
        return f
    end
    local mine, other, party, mini
    local B = load(function()
        questie({ QuestieMap = { questIdFrames = {
            [1] = { DuiMine = "DuiMine", DuiMini = "DuiMini" },
            [2] = { DuiOther = "DuiOther", DuiParty = "DuiParty", DuiGone = "DuiGone" },
        } } })
    end)
    DaylightUI.DB.General().motion = false
    mine, other = icon("DuiMine"), icon("DuiOther")
    party = icon("DuiParty", { data = { ObjectiveData = { IsPartyObjective = true } } })
    party:SetAlpha(0.5)
    mini = icon("DuiMini", { miniMapIcon = true })
    mini:SetSize(10, 12)
    B.FocusIcons(1, 0.2, 1.35)
    T.eq(mine:GetScale(), 1.35, "the quest's icon grows")
    T.eq(mine:GetAlpha(), 1)
    T.eq(other:GetAlpha(), 0.2, "another quest's fades")
    T.eq(other:GetScale(), 1)
    T.eq(party:GetAlpha(), 0.1, "a party member's stays dimmer")
    -- HereBeDragons places a minimap icon by an offset from the minimap's middle,
    -- and a frame's scale scales its offset too: it grows by size, or it would run.
    T.eq(mini:GetScale(), 1, "a minimap icon never scales")
    T.eq(mini:GetWidth(), 13.5, "it grows by size")
    T.eq(mini:GetHeight(), 12 * 1.35)
    -- Straight to the other quest, then back to rest.
    B.FocusIcons(2, 0.2, 1.35)
    T.eq(mine:GetScale(), 1)
    T.eq(mine:GetAlpha(), 0.2)
    T.eq(other:GetAlpha(), 1)
    T.eq(other:GetScale(), 1.35)
    B.FocusIcons(nil)
    T.eq(mine:GetAlpha(), 1)
    T.eq(other:GetScale(), 1)
    T.eq(party:GetAlpha(), 0.5, "the party dim comes back")
    T.eq(mini:GetWidth(), 10, "the minimap's comes back to its size")
    T.eq(mini:GetHeight(), 12)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's video: with the mouse still over packed icons in a fight, Questie's
-- hover went on and off a few times a second. A grown icon took the mouse from
-- the bare map (where Questie hovers a patrol path) or from the icon it was over,
-- that hover ended, everything shrank back, and the hover began again.
T.test("bridge: a grown icon keeps the mouse area it had at rest", function()
    local B = load(function()
        questie({ QuestieMap = { questIdFrames = { [1] = { DuiHitMap = "DuiHitMap", DuiHitMini = "DuiHitMini" } } } })
    end)
    DaylightUI.DB.General().motion = false
    local map = CreateFrame("Frame", "DuiHitMap", UIParent)
    map:SetSize(16, 16)
    local mini = CreateFrame("Frame", "DuiHitMini", UIParent)
    mini.miniMapIcon = true
    mini:SetSize(10, 10)
    -- How wide the mouse area is on screen, in the parent's units.
    local function reach(f)
        local hit = f.__hitRect or { 0, 0, 0, 0 }
        local s = f:GetScale()
        return (f:GetWidth() - hit[1] - hit[2]) * s, (f:GetHeight() - hit[3] - hit[4]) * s
    end
    B.FocusIcons(1, 0.2, 1.35)
    T.eq(map:GetScale(), 1.35, "it still grows")
    local w, h = reach(map)
    T.near(w, 16, 1e-6, "the map icon's mouse area stays its resting width")
    T.near(h, 16, 1e-6)
    w, h = reach(mini)
    T.eq(mini:GetWidth(), 13.5, "the minimap icon still grows")
    T.near(w, 10, 1e-6, "the minimap icon's mouse area stays its resting width")
    T.near(h, 10, 1e-6)
    B.FocusIcons(nil)
    T.deq(map.__hitRect or { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, "the whole icon takes the mouse again")
    T.deq(mini.__hitRect or { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bridge: an icon Questie gave to something else keeps what Questie set", function()
    local mini
    local B = load(function()
        questie({ QuestieMap = { questIdFrames = { [1] = { DuiRecycled = "DuiRecycled" } } } })
    end)
    DaylightUI.DB.General().motion = false
    mini = CreateFrame("Frame", "DuiRecycled", UIParent)
    mini.miniMapIcon, mini.data = true, { Id = 1 }
    mini:SetSize(10, 10)
    B.FocusIcons(1, 0.2, 1.35)
    T.eq(mini:GetWidth(), 13.5)
    -- Questie's draw: new data, its own size, for another quest.
    mini.data = { Id = 2 }
    mini:SetSize(20, 20)
    B.FocusIcons(nil)
    T.eq(mini:GetWidth(), 20, "not the old icon's size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bridge: no Questie, no icons, no error", function()
    local B = load()
    B.FocusIcons(1, 0.2, 1.35)
    B.FocusIcons(nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bridge: a Questie with no such function is left alone", function()
    local B = load(function() questie({}) end)
    B.WatchHover(function() end)
    T.eq(B.hooked, nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bridge: a broken Questie answers nil", function()
    local B = load(function()
        questie({}, { GetQuestObjectiveIconForUnit = function() error("boom") end })
    end)
    T.eq(B.Loaded(), true)
    T.eq(B.PlateKind("Creature-0-1-2-3-9-0"), nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bridge: plate kind from the icon path", function()
    local icon
    local calls = 0
    local B = load(function()
        questie({}, { GetQuestObjectiveIconForUnit = function() calls = calls + 1; return icon end })
    end)
    local G = "Creature-0-1-2-3-9-0"
    icon = "Interface\\Addons\\Questie\\Icons\\slay.blp"; T.eq(B.PlateKind(G), "kill")
    icon = "Interface\\Addons\\Questie\\Icons\\loot.blp"; T.eq(B.PlateKind(G), "loot")
    icon = "Interface\\Addons\\Questie\\Icons\\object.blp"; T.eq(B.PlateKind(G), "use")
    icon = "Interface\\Addons\\Questie\\Icons\\interact.blp"; T.eq(B.PlateKind(G), "use")
    icon = "Interface\\Addons\\Questie\\Icons\\event.blp"; T.eq(B.PlateKind(G), "explore")
    icon = "Interface\\Addons\\Questie\\Icons\\mystery.blp"; T.eq(B.PlateKind(G), nil)
    icon = nil; T.eq(B.PlateKind(G), nil)
    local before = calls
    T.eq(B.PlateKind(stub.Secret(G)), nil)
    T.eq(calls, before, "a secret GUID never reaches Questie")
end)

T.test("aside: Questie's settings ready late still get its NPC tooltip quests out of the way", function()
    load(function()
        stub.loadedAddOns.Questie = true
        _G.Questie = {}     -- loaded, its AceDB profile not made yet
    end)
    local profile = { showQuestsInNpcTooltip = true }
    Questie.db = { profile = profile }      -- made a while after our login
    stub.Advance(DaylightUI.QuestieAside.RETRY)
    stub.RunTimers()
    T.eq(profile.showQuestsInNpcTooltip, false, "ours draws: Questie's steps aside")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("aside: without Questie nothing keeps asking", function()
    load()
    stub.RunTimers()
    local asked = 0
    local run = DaylightUI.QuestieAside.Run
    DaylightUI.QuestieAside.Run = function() asked = asked + 1; return run() end
    stub.RunTimers()
    DaylightUI.QuestieAside.Run = run
    T.eq(asked, 0)
end)

T.test("aside: untracked quests leave Questie's maps while ours tracks, not with the whole-log filter", function()
    local log = {}
    local modules = {
        ThreadLib = { ThreadInstant = function(fn) fn() end },
        ActiveQuests = { Iterate = function() return pairs({ [5] = { quest = { Id = 5 } } }) end },
        QuestieQuest = {
            PopulateObjectiveNotes = function(_, q) log[#log + 1] = "draw" .. q.Id end,
            ShowQuestIcons = function() log[#log + 1] = "show" end,
            HideQuestIcons = function() log[#log + 1] = "hide" end,
        },
    }
    load(function() questie(modules) end)
    local p = Questie.db.profile
    DaylightUI.questsOwnTracker = true   -- the fake game has no tracker of its own to switch off
    DaylightUI.Fire("QuestMapsChanged")
    T.eq(p.hideUntrackedQuestsMapIcons, true, "Questie hides untracked quests' icons")
    T.eq(table.concat(log, " "), "draw5 show hide", "and redraws the ones already drawn")
    DaylightUI:Set("Quests", "filter", "log")
    T.eq(p.hideUntrackedQuestsMapIcons, false, "the whole log is listed, nothing watched: all show")
    DaylightUI:Set("Quests", "filter", "zone")
    T.eq(p.hideUntrackedQuestsMapIcons, true)
    DaylightUI.questsOwnTracker = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's ask: Questie's "Hide icons of untracked quests" came back on after
-- every reload. Daylight UI turns it on once, then the player's own change stays.
T.test("aside: untracked quests' icons are hidden once; turned off in Questie, they stay off over a reload", function()
    local profile
    local function start(sv)
        load(function()
            questie({})
            if profile then Questie.db.profile = profile end   -- Questie's own saved profile
            if sv then DaylightUIDB = sv end
            -- The game's tracker, which Quests switches off as its file loads.
            ObjectiveTrackerManager = {}
        end)
        profile = Questie.db.profile
        DaylightUI.Fire("QuestMapsChanged")
    end
    start()
    T.eq(profile.hideUntrackedQuestsMapIcons, true, "turned on the first time")
    -- The player turns it off in Questie's options, then reloads.
    profile.hideUntrackedQuestsMapIcons = false
    DaylightUI.Fire("QuestMapsChanged")
    T.eq(profile.hideUntrackedQuestsMapIcons, false, "a settings change leaves it off")
    start(DaylightUIDB)
    T.eq(profile.hideUntrackedQuestsMapIcons, false, "a reload leaves it off")
    -- A player from before this: it was forced on (noted in questieOff), then turned off.
    profile.hideUntrackedQuestsMapIcons = false
    start({ questieOff = { hideUntrackedQuestsMapIcons = true } })
    T.eq(profile.hideUntrackedQuestsMapIcons, false, "an earlier player's Questie setting stays as it is")
    -- The whole-log filter hands it back; taking charge again turns it on once more.
    DaylightUI:Set("Quests", "filter", "log")
    T.eq(profile.hideUntrackedQuestsMapIcons, false)
    DaylightUI:Set("Quests", "filter", "zone")
    T.eq(profile.hideUntrackedQuestsMapIcons, true, "set once again after being handed back")
    DaylightUI.questsOwnTracker = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("aside: a newly tracked quest's icons draw in a few frames, not Questie's slow queue", function()
    local drawn = 0
    local map = { ProcessQueue = function() drawn = drawn + 1 end }
    load(function() questie({ QuestieMap = map }) end)
    local p = Questie.db.profile
    p.trackerEnabled, p.hideUntrackedQuestsMapIcons = false, true
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 5, false)
    T.isnil(DaylightUI.QuestieAside.hurryFrame, "untracking draws nothing new")
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 5, true)
    local f = DaylightUI.QuestieAside.hurryFrame
    stub.RunOnUpdate(f, 0.016)
    T.eq(drawn, DaylightUI.QuestieAside.HURRY_PER_FRAME, "the queue worked every frame")
    stub.Advance(DaylightUI.QuestieAside.HURRY_FOR + 0.1)
    stub.RunOnUpdate(f, 0.016)
    T.isnil(f.__scripts.OnUpdate, "and it stops again: nothing runs while idle")
    -- Questie's own settings: its tracker on draws every quest anyway.
    p.trackerEnabled = true
    drawn = 0
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 6, true)
    stub.RunOnUpdate(f, 0.016)
    T.eq(drawn, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
