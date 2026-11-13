local stub = require("stub")
local QW = require("questworld")

-- Loads the core and the quest tracker into a fake quest world.
local function load(spec, opts)
    opts = opts or {}
    opts.quests = true
    local world = QW.world(spec or { quests = {} })
    local before = opts.before
    opts.before = function() world(); if before then before() end end
    local DUI = stub.Load(opts)
    return DUI, stub.quests
end

T.test("quests: the module registers", function()
    load()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(DaylightUI:GetModule("Quests"), "registered")
end)

T.test("quests: starving empties exactly the three setup functions", function()
    local _, ns = load()
    T.eq(ns.Blizzard.Starve(), true)
    local m = ObjectiveTrackerManager
    for _, name in ipairs({ "AddContainer", "AssignModulesOrder", "SetModuleContainer" }) do
        T.truthy(m[name] ~= QW.originals[name], name .. " emptied")
    end
    T.eq(m.UpdateAll, QW.originals.UpdateAll, "UpdateAll stays the game's own")
    T.eq(DaylightUI.questsOwnTracker, true)
end)

T.test("quests: the leftover frame goes see-through and deaf, never hidden", function()
    local _, ns = load()
    ns.Blizzard.Starve()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    local f = ObjectiveTrackerFrame
    T.eq(f:GetAlpha(), 0)
    T.eq(f:IsShown(), true, "never hidden")
    T.eq(f:IsMouseEnabled(), false)
    T.eq(f.Header:IsMouseEnabled(), false)
    T.eq(f.Header.MinimizeButton:IsMouseEnabled(), false)
    T.eq(QuestTimerFrame:IsMouseEnabled(), false)
end)

-- In game (a new character, controller mode on) something put the frame
-- back to alpha 1 and its full-height black background showed.
T.test("quests: the leftover frame's own background stays see-through if the frame comes back", function()
    local _, ns = load()
    ns.Blizzard.Starve()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    ObjectiveTrackerFrame:SetAlpha(1)
    T.eq(ObjectiveTrackerFrame.NineSlice:GetAlpha(), 0, "the background never shows")
end)

T.test("quests: with Kaliel's Tracker loaded ours stays off", function()
    local _, ns = load({ quests = {}, loaded = { "!KalielsTracker" } })
    T.eq(ns.Blizzard.Starve(), false)
    T.eq(ObjectiveTrackerManager.AddContainer, QW.originals.AddContainer, "the game's tracker left alone")
    T.truthy(stub.ChatContains("Kaliel's Tracker"), "said why")
end)

local function snap(spec)
    local _, ns = load(spec)
    return ns.Data.Snapshot(), ns
end

T.test("quests data: objective text loses its count, either way round", function()
    local _, ns = load()
    local D = ns.Data
    T.deq({ D.SplitObjective("5/8 Murloc Fin") }, { "Murloc Fin", true })
    T.deq({ D.SplitObjective("Murloc Fin: 5/8") }, { "Murloc Fin", true })
    T.deq({ D.SplitObjective("Speak to Gryan Stoutmantle") }, { "Speak to Gryan Stoutmantle", false })
end)

T.test("quests data: groups by zone, the zone you're in first", function()
    local s = snap({ zone = "Elwynn Forest", quests = {
        QW.quest(1, "Westfall Stew"),
        QW.quest(2, "A Fishy Peril", { zone = "Elwynn Forest" }),
        QW.quest(3, "Red Leather Bandanas"),
    } })
    T.eq(#s.groups, 2)
    T.eq(s.groups[1].name, "Elwynn Forest", "current zone first")
    T.eq(s.groups[2].name, "Westfall")
    T.eq(#s.groups[2].quests, 2)
    T.eq(s.groups[2].quests[1].zone, "Westfall")
    T.eq(s.logCount, 3)
    T.eq(s.logMax, 25)
end)

T.test("quests data: a quest the log walk missed asks for its header", function()
    local _, ns = load({ quests = { QW.quest(1, "Westfall Stew") } })
    local getInfo = C_QuestLog.GetInfo
    -- The walk sees the header but not the quest (as if folded under it).
    C_QuestLog.GetNumQuestLogEntries = function() return 1, 1 end
    C_QuestLog.GetHeaderIndexForQuest = function() return 1 end
    C_QuestLog.GetLogIndexForQuestID = function() return 2 end
    C_QuestLog.GetInfo = getInfo
    local s = ns.Data.Snapshot()
    T.eq(s.groups[1].name, "Westfall", "still under its zone, not Other")
end)

T.test("quests data: unwatched quests stay out", function()
    local s = snap({ quests = { QW.quest(1, "A"), QW.quest(2, "B", { watched = false }) } })
    T.eq(#s.groups[1].quests, 1)
end)

T.test("quests data: objectives counted, plain and as a bar", function()
    local s = snap({ quests = { QW.quest(1, "Stew", { pct = 45, objs = {
        { text = "3/6 Goretusk Snout", have = 3, need = 6 },
        { text = "Speak to Salma" , need = 0 },
        { text = "Clear the farm: 45%", type = "progressbar" },
    } }) } })
    local o = s.groups[1].quests[1].objs
    T.eq(o[1].kind, "count"); T.eq(o[1].text, "Goretusk Snout"); T.eq(o[1].have, 3); T.eq(o[1].need, 6)
    T.eq(o[2].kind, "text"); T.eq(o[2].text, "Speak to Salma")
    T.eq(o[3].kind, "bar"); T.eq(o[3].pct, 45); T.eq(o[3].text, "Clear the farm")
end)

T.test("quests data: ready, auto-complete, failed, and the hand-in line", function()
    local s = snap({ quests = {
        QW.quest(1, "A", { complete = true, turnIn = "Return to Salma Saldean" }),
        QW.quest(2, "B", { complete = true }),
        QW.quest(3, "C", { complete = true, auto = true }),
        QW.quest(4, "D", { failed = true }),
    } })
    local q = s.groups[1].quests
    T.eq(q[1].state, "ready"); T.eq(q[1].turnIn, "Return to Salma Saldean")
    T.eq(q[2].turnIn, "Ready to turn in", "no text from the game: our fallback")
    T.eq(q[3].auto, true); T.eq(q[3].turnIn, "Click to complete")
    T.eq(q[4].state, "failed")
end)

T.test("quests data: titles take the quest log's colors, gray to red", function()
    local s = snap({ quests = {
        QW.quest(1, "A", { difficulty = 0 }), QW.quest(2, "B", { difficulty = 1 }),
        QW.quest(3, "C", { difficulty = 2 }), QW.quest(4, "D", { difficulty = 3 }),
        QW.quest(5, "E", { difficulty = 4 }),
    } })
    local q = s.groups[1].quests
    for i, name in ipairs({ "trivial", "standard", "difficult", "verydifficult", "impossible" }) do
        local c = QW.COLORS[name]
        T.deq(q[i].diff, { c.r, c.g, c.b }, name)
    end
end)

-- Seen in game: at level 5 a level 10 quest came back yellow from
-- the server, where the level math says red.
T.test("quests data: a quest well above you goes orange, then red, whatever the server says", function()
    local s = snap({ playerLevel = 5, quests = {
        QW.quest(1, "Near", { level = 6, difficulty = 2 }),
        QW.quest(2, "Tough", { level = 8, difficulty = 2 }),
        QW.quest(3, "Far", { level = 10, difficulty = 2 }),
        QW.quest(4, "Old", { level = 1, difficulty = 1 }),
    } })
    local q = s.groups[1].quests
    for i, name in ipairs({ "difficult", "verydifficult", "impossible", "standard" }) do
        local c = QW.COLORS[name]
        T.deq(q[i].diff, { c.r, c.g, c.b }, name)
    end
end)

T.test("quests data: without the server's verdict the level math colors a title", function()
    local _, ns = load({ quests = { QW.quest(1, "A", { difficulty = 1 }) } }, {
        before = function() _G.C_PlayerInfo = nil end })
    local c = QW.COLORS.difficult
    T.deq(ns.Data.Snapshot().groups[1].quests[1].diff, { c.r, c.g, c.b })
end)

T.test("quests data: items and timers ride on their quest", function()
    local s = snap({ quests = {
        QW.quest(1, "A", { item = { link = "|Hitem:5862:|h[Seaforium]|h", icon = 1234, charges = 3 } }),
        QW.quest(2, "B", { timer = 252 }),
    } })
    local q = s.groups[1].quests
    T.eq(q[1].item.icon, 1234); T.eq(q[1].item.charges, 3)
    T.isnil(q[2].item)
    T.eq(q[2].timer, 252)
end)

T.test("quests data: tracked achievements with their unfinished criteria", function()
    local s = snap({ achievements = { { id = 9, title = "Explore Westfall", criteria = {
        { text = "Moonbrook", done = true }, { text = "Jangolode Mine" }, { text = "Murlocs", have = 2, need = 10 },
    } } } })
    local a = s.achievements[1]
    T.eq(a.title, "Explore Westfall")
    T.eq(#a.objs, 2, "done criteria left out")
    T.eq(a.objs[2].kind, "count"); T.eq(a.objs[2].need, 10)
end)

T.test("quests data: a client without the quest APIs gives an empty picture", function()
    local _, ns = load()
    _G.C_QuestLog, _G.C_ContentTracking, _G.GetQuestLogCompletionText = nil, nil, nil
    local s
    T.noerror(function() s = ns.Data.Snapshot() end)
    T.eq(#s.groups, 0)
    T.eq(#s.achievements, 0)
end)

local function lay(spec, o)
    local _, ns = load(spec)
    local opts = { width = 226, sizes = { header = 12, title = 12, objective = 11, zone = 10 },
                   zoneNames = true, compact = false, hideDone = false, filter = "all", folds = {}, caps = false }
    for k, v in pairs(o or {}) do opts[k] = v end
    local one = function(_, size) return size + 3 end
    return ns.Layout.Build(ns.Data.Snapshot(), opts, o and o.measure or one), ns
end

local STEW = QW.quest(1, "Westfall Stew", { objs = {
    { text = "4/5 Stringy Vulture Meat", have = 4, need = 5 },
    { text = "3/6 Goretusk Snout", have = 3, need = 6 },
} })

T.test("quests layout: header, zone, quest at the anatomy board's sizes", function()
    local b = lay({ quests = { STEW } })
    T.eq(b[1].key, "section:quests"); T.eq(b[1].y, 0); T.eq(b[1].h, 26)       -- 15 + 3 + 2 + 6
    T.eq(b[1].count, "1/25")
    T.eq(b[2].key, "zone:Westfall"); T.eq(b[2].y, 26); T.eq(b[2].h, 18)        -- 2 + 13 + 3
    local q = b[3]
    T.eq(q.key, "quest:1"); T.eq(q.y, 44)
    T.eq(q.lines[1].kind, "title"); T.eq(q.lines[1].h, 15)
    T.eq(q.lines[2].key, "obj:1"); T.eq(q.lines[2].y, 16); T.eq(q.lines[2].h, 14)
    T.eq(q.lines[3].y, 31)
    T.eq(q.h, 45 + 7)
end)

T.test("quests layout: a ready quest folds into its hand-in line", function()
    local b = lay({ quests = { QW.quest(1, "A", { complete = true, turnIn = "Return to Salma", objs = STEW.objs }) } })
    local lines = b[3].lines
    T.eq(#lines, 2)
    T.eq(lines[2].kind, "turnin"); T.eq(lines[2].text, "Return to Salma")
end)

T.test("quests layout: a bar line under its objective, a timer line, a failed line", function()
    local b = lay({ quests = {
        QW.quest(1, "A", { pct = 45, timer = 90, objs = { { text = "Clear the farm: 45%", type = "progressbar" } } }),
        QW.quest(2, "B", { failed = true, timer = 0 }),
    } })
    local a = b[3].lines
    T.eq(a[2].kind, "obj"); T.eq(a[3].kind, "bar"); T.eq(a[3].pct, 45); T.eq(a[3].y, a[2].y + a[2].h + 3)
    T.eq(a[4].kind, "timer")
    local f = b[4].lines
    T.eq(f[2].kind, "failed"); T.eq(#f, 2, "no timer once failed")
end)

T.test("quests layout: long text wraps and pushes what's below down", function()
    local wrap = function(text, size, width) return math.ceil(#text * 6 / width) * (size + 3) end
    local long = QW.quest(1, string.rep("Long title ", 12), { objs = { { text = "1/2 Thing", have = 1, need = 2 } } })
    local b = lay({ quests = { long, QW.quest(2, "Short") } }, { measure = wrap })
    local title = b[3].lines[1]
    T.truthy(title.h > 15, "the title wrapped")
    T.eq(b[3].lines[2].y, title.h + 1, "the objective sits under the wrapped title")
    T.eq(b[4].y, b[3].y + b[3].h, "the next quest sits under it")
end)

T.test("quests layout: options change what's there", function()
    T.eq(#lay({ quests = { STEW } }, { zoneNames = false }), 2, "no zone row")
    local folded = lay({ quests = { STEW } }, { folds = { quests = true } })
    T.eq(#folded, 1); T.eq(folded[1].folded, true)
    local two = { STEW, QW.quest(2, "B", { zone = "Elwynn Forest" }) }
    local zf = lay({ quests = two }, { folds = { ["zone:Westfall"] = true } })
    T.eq(#zf, 4, "header, Westfall (folded), Elwynn, quest 2")
    T.eq(zf[2].folded, true); T.eq(zf[2].count, 1, "a folded zone counts its quests")
    T.eq(zf[4].key, "quest:2")
    T.eq(#lay({ quests = two }, { zoneNames = false, folds = { ["zone:Westfall"] = true } }), 3,
         "no zone names: nothing left to unfold it, so nothing is hidden")
    local done = QW.quest(1, "A", { objs = { { text = "1/1 X", have = 1, need = 1, done = true }, { text = "0/2 Y", have = 0, need = 2 } } })
    T.eq(#lay({ quests = { done } }, { hideDone = true })[3].lines, 2, "the done one hidden")
    local compact = lay({ quests = { STEW } }, { compact = true })
    T.eq(compact[3].h, 45 + 4)
    local zone = lay({ zone = "Elwynn Forest", quests = { STEW, QW.quest(2, "B", { zone = "Elwynn Forest" }) } }, { filter = "zone" })
    T.eq(#zone, 3, "header, Elwynn, one quest")
    T.eq(zone[3].key, "quest:2")
    T.eq(lay({ quests = { STEW } }, { caps = true })[3].lines[1].text, "WESTFALL STEW")
end)

T.test("quests layout: quest levels in front of titles, when switched on", function()
    T.eq(lay({ quests = { STEW } })[3].lines[1].text, "Westfall Stew", "off by default")
    T.eq(lay({ quests = { STEW } }, { levels = true })[3].lines[1].text, "[15] Westfall Stew")
    T.eq(lay({ quests = { STEW } }, { levels = true, caps = true })[3].lines[1].text, "[15] WESTFALL STEW")
    local none = QW.quest(2, "No level", { level = 0 })
    T.eq(lay({ quests = { none } }, { levels = true })[3].lines[1].text, "No level", "no level, no tag")
    local _, ns = load({ quests = { STEW } })
    T.eq(ns.DEFAULTS.questLevels, false)
end)

T.test("quests layout: achievements get their own section", function()
    local b = lay({ quests = { STEW }, achievements = { { id = 9, title = "Explore", criteria = { { text = "Mine" } } } } })
    local last = b[#b]
    T.eq(last.key, "ach:9")
    T.eq(b[#b - 1].key, "section:achievements")
    T.eq(b[#b - 1].y, b[3].y + b[3].h + 6, "a gap above the second section")
end)

T.test("quests layout: the diff by key", function()
    local _, ns = load()
    local L = ns.Layout
    local d = L.Diff({ { key = "a", y = 0 }, { key = "b", y = 10 } }, { { key = "b", y = 0 }, { key = "c", y = 10 } })
    T.deq(d.enter, { c = true }); T.deq(d.leave, { a = true }); T.deq(d.moved, { b = true })
end)

T.test("quests layout: would item buttons have to move", function()
    local _, ns = load()
    local L = ns.Layout
    local old = { { key = "quest:1", y = 0 }, { key = "quest:2", y = 50, item = true } }
    T.eq(L.WouldMoveItems(old, { { key = "quest:1", y = 0 }, { key = "quest:2", y = 50, item = true } }), false)
    T.eq(L.WouldMoveItems(old, { { key = "quest:1", y = 0, h = 20 }, { key = "quest:2", y = 30, item = true } }), true, "moved")
    T.eq(L.WouldMoveItems(old, { { key = "quest:1", y = 0 } }), true, "gone")
    T.eq(L.WouldMoveItems(old, { { key = "quest:2", y = 50, item = true }, { key = "quest:3", y = 90 } }), false, "below: fine")
end)

-- setup(db), optional: change settings after loading, before painting.
local function painted(spec, o, setup)
    local blocks, ns = lay(spec, o)
    local mod = DaylightUI:GetModule("Quests")
    if setup then setup(mod.db) end
    local look = ns.Look.Get(mod.db)
    look.width = 226
    local parent = CreateFrame("Frame", nil, UIParent)
    local frames = {}
    for _, b in ipairs(blocks) do
        local f = ns.Rows.Get(b.kind, parent)
        ns.Rows.Paint(f, b, look, {})
        frames[b.key] = f
    end
    return frames, ns, look, blocks
end

T.test("quests: a mark at the title's end says how many of your party are on it", function()
    local SHARED = QW.quest(2, "The Defias Brotherhood", { onParty = { "party1", "party3" } })
    local spec = { partySize = 3, quests = { STEW, SHARED } }
    local got = {}
    for _, q in ipairs(snap(spec).groups[1].quests) do got[q.id] = q.party end
    T.deq(got, { 0, 2 }, "the game's count, party1 on")
    T.eq(snap({ partySize = 1, quests = { SHARED } }).groups[1].quests[1].party, 1, "party3 has left: no such member")
    local b = lay(spec, { party = true })
    T.isnil(b[3].lines[1].party, "nobody else on it: nothing")
    T.eq(b[4].lines[1].party, 2)
    T.eq(b[4].lines[1].text, "The Defias Brotherhood", "drawn, not written into the title: [2] reads as a level")
    T.isnil(lay(spec, { party = false })[4].lines[1].party, "switched off")
    -- the title wraps short of the mark
    local widths = {}
    lay({ partySize = 3, quests = { SHARED } }, { party = true, measure = function(_, size, w) widths[#widths + 1] = w; return size + 3 end })
    T.eq(widths[3], 226 - 18 - 24, "header, zone, then the title")
    local frames, ns, look = painted(spec, { party = true })
    T.eq(ns.DEFAULTS.questParty, true, "on by default")
    T.eq(frames["quest:1"].lines.title.party:IsShown(), false)
    local mark = frames["quest:2"].lines.title.party
    T.eq(mark:IsShown(), true)
    T.eq(mark.count:GetText(), "2")
    T.eq(mark:IsMouseEnabled() == true, false, "the row under it keeps its hover and clicks")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests: the mark follows the party, in one look for a burst", function()
    local SHARED = QW.quest(2, "The Defias Brotherhood")
    local _, ns = load({ partySize = 2, quests = { SHARED } })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    local function mark() return ns.Tracker.frames["quest:2"].lines.title.party end
    T.eq(mark():IsShown(), false)
    QW.state.quests[1].onParty = { "party2" }
    stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "party2")
    stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "party1")
    stub.RunTimers()
    T.eq(mark():IsShown(), true, "someone took it")
    T.eq(mark().count:GetText(), "1")
    QW.state.quests[1].onParty = nil
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(mark():IsShown(), false, "gone with them, after its fade")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Spoken (the quest voice-over addon), faked the way Spoken_Quests 3.8.4 hands
-- itself to a tracker: QuestOverlayUI:ShowsTrackerButton, :BindPlayButton
-- (which sets the button's OnClick, and its OnEnter/OnLeave when the button
-- carries setPlayState), .FollowQueue (calls button:SetState).
local function spoken(voiced)
    local s = { voiced = voiced, played = {}, state = {}, callbacks = {} }
    _G.Spoken = { RegisterCallback = function(_, event, fn) s.callbacks[event] = fn end }
    local Q = {}
    function Q:ShowsTrackerButton(id) return s.voiced[id] == true end
    function Q:BindPlayButton(b, id, title)
        s.bound = (s.bound or 0) + 1
        b:SetScript("OnClick", function() s.played[#s.played + 1] = { id = id, title = title } end)
        if b.setPlayState then
            b.questID = id
            b:SetScript("OnEnter", function() s.spokenTip = true end)
            b:SetScript("OnLeave", function() end)
        end
    end
    function Q.FollowQueue(b) b:SetState(s.state[b.questID] or "play") end
    _G.VoiceOver = { QuestOverlayUI = Q }
    return s
end
local function noSpoken() _G.Spoken, _G.VoiceOver = nil, nil end

T.test("quests: a Play button on a quest Spoken voices, its room kept", function()
    local VOICED = QW.quest(2, "The Defias Brotherhood")
    local spec = { quests = { STEW, VOICED } }
    noSpoken()
    T.isnil(snap(spec).groups[1].quests[2].voice, "no Spoken: no button")
    local s = spoken({ [2] = true })
    local got = {}
    for _, q in ipairs(snap(spec).groups[1].quests) do got[q.id] = q.voice or false end
    T.deq(got, { false, true })
    local widths = {}
    lay({ quests = { VOICED } }, { measure = function(_, size, w) widths[#widths + 1] = w; return size + 3 end })
    T.eq(widths[3], 226 - 18 - 18, "the title wraps short of the button")
    local frames = painted(spec, {})
    T.eq(frames["quest:1"].lines.title.voice:IsShown(), false)
    local v = frames["quest:2"].lines.title.voice
    T.eq(v:IsShown(), true)
    T.eq(v.icon:GetTexture(), DaylightUI.MEDIA .. "ui-play.png")
    v:Click()
    T.deq(s.played, { { id = 2, title = "The Defias Brotherhood" } }, "Spoken plays the quest's line")
    T.eq(v:GetScript("OnEnter"), v.enter, "our tooltip, not Spoken's, back on after the bind")
    s.state[2] = "stop"
    v.setPlayState(v)
    T.eq(v.icon:GetTexture(), DaylightUI.MEDIA .. "ui-stop.png", "playing: Stop")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    noSpoken()
end)

T.test("quests: the Play buttons look again when Spoken's packs load", function()
    local VOICED = QW.quest(2, "The Defias Brotherhood")
    local s
    local _, ns = load({ quests = { VOICED } }, { before = function() s = spoken({}) end })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    local function button() return ns.Tracker.frames["quest:2"].lines.title.voice end
    T.eq(button():IsShown(), false, "no pack has it yet")
    s.voiced[2] = true
    s.callbacks.VOICE_PACKS_LOADED()
    stub.RunTimers()
    T.eq(button():IsShown(), true, "the packs came: a button")
    local binds = s.bound
    stub.FireEvent("QUEST_LOG_UPDATE")
    stub.RunTimers()
    T.eq(s.bound, binds, "bound once, not on every look")
    s.voiced[2] = nil
    s.callbacks.PART_SWITCHED("quests")
    stub.RunTimers()
    T.eq(button():IsShown(), false, "Spoken's quest part off: gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    noSpoken()
end)

T.test("quests: elite, dungeon, raid and PvP quests get a tag after their title", function()
    local ELITE_Q = QW.quest(2, "The Defias Brotherhood", { elite = true })
    local quests = { STEW, ELITE_Q, QW.quest(3, "Red Silk Bandanas", { tagID = 81 }),
                     QW.quest(4, "The Hand of Rag", { tagID = 62 }), QW.quest(5, "Warsong Mark", { tagID = 41 }),
                     QW.quest(6, "Tagged elite", { tagID = 1 }), QW.quest(7, "Other tag", { tagID = 102 }) }
    local got = {}
    for _, q in ipairs(snap({ quests = quests }).groups[1].quests) do got[q.id] = q.tag or "none" end
    T.deq(got, { "none", "elite", "dungeon", "raid", "pvp", "elite", "none" })
    local b = lay({ quests = { STEW, ELITE_Q } }, { tags = true })
    T.isnil(b[3].lines[1].tag)
    T.eq(b[4].lines[1].tag, "elite")
    T.eq(b[4].lines[1].text, "The Defias Brotherhood", "the tag is drawn, not written into the title")
    T.isnil(lay({ quests = { ELITE_Q } }, { tags = false })[3].lines[1].tag, "switched off")
    -- the title wraps short of the tag's room
    local widths = {}
    lay({ quests = { ELITE_Q } }, { tags = true, measure = function(_, size, w) widths[#widths + 1] = w; return size + 3 end })
    T.eq(widths[3], 226 - 18 - 50, "header, zone, then the title")
    local frames, ns, look = painted({ quests = quests }, { tags = true })
    T.eq(ns.DEFAULTS.questTags, true, "on by default")
    local tag = frames["quest:2"].lines.title.tag
    T.eq(tag:IsShown(), true)
    T.eq(tag.text:GetText(), string.upper(ELITE or "Elite"))
    T.rgb(tag.text.__textColor, look.c.elite)
    local sl = DaylightUI.Style.GetSlant(tag)
    T.eq(sl and sl.side, "both", "a slanted box, not a pill")
    T.eq(sl.under, "left", "leaning like the loot feed's rows")
    local dng = frames["quest:3"].lines.title.tag
    T.eq(dng.text:GetText(), string.upper(CALENDAR_TYPE_DUNGEON or "Dungeon"))
    T.rgb(dng.text.__textColor, look.c.dungeon)
    T.eq(frames["quest:1"].lines.title.tag:IsShown(), false)
    T.eq(frames["quest:7"].lines.title.tag:IsShown(), false, "a tag we don't show")
end)

T.test("quests rows: a quest's title, icon and objectives", function()
    local f = painted({ quests = { STEW } })["quest:1"]
    T.eq(f.lines.title.label:GetText(), "Westfall Stew")
    T.eq(f.ring:IsShown(), true); T.eq(f.ready:IsShown(), false)
    local o = f.lines["obj:2"]
    T.eq(o.label:GetText(), "Goretusk Snout")
    T.eq(o.count:GetText(), "3/6")
    T.eq(o.tick:IsShown(), false)
end)

T.test("quests rows: a ready quest is gold with the '?' and its hand-in line", function()
    local frames, ns, look = painted({ quests = { QW.quest(1, "A", { complete = true, turnIn = "Return to Salma" }) } })
    local f = frames["quest:1"]
    T.eq(f.ready:IsShown(), true); T.eq(f.ring:IsShown(), false)
    T.rgb(f.lines.title.label.__textColor, look.c.ready)
    T.eq(f.lines.turnin.label:GetText(), "Return to Salma")
end)

T.test("quests rows: a done objective dims and shows the tick", function()
    local q = QW.quest(1, "A", { objs = { { text = "1/1 X", have = 1, need = 1, done = true } } })
    local frames, _, look = painted({ quests = { q } })
    local o = frames["quest:1"].lines["obj:1"]
    T.eq(o.tick:IsShown(), true); T.eq(o.count:IsShown(), false)
    T.rgb(o.label.__textColor, look.c.done)
end)

T.test("quests rows: one title color when asked", function()
    local frames, _, look = painted({ quests = { STEW } }, nil, function(db) db.colors.titleMode = "one" end)
    T.rgb(frames["quest:1"].lines.title.label.__textColor, look.c.title)
end)

T.test("quests rows: the header in capitals with its count, the zone name too", function()
    local frames = painted({ quests = { STEW } })
    local h = frames["section:quests"]
    T.eq(h.label:GetText(), "QUESTS"); T.eq(h.count:GetText(), "1/25")
    T.eq(frames["zone:Westfall"].label:GetText(), "WESTFALL")
end)

T.test("quests rows: headers, their line and zone names in the class color", function()
    local frames = painted({ quests = { STEW } }, nil, function(db)
        stub.SetUnits({ player = { name = "Me", class = "MAGE" } })
        db.colors.headerMode, db.colors.headerLineMode, db.colors.zoneMode = "class", "class", "class"
    end)
    local want = { DaylightUI.Style.ClassColor("MAGE") }
    local h = frames["section:quests"]
    T.rgb(h.label.__textColor, want)
    T.eq(h.label:GetText(), "QUESTS")
    T.rgb(h.rule.__vertex, want)
    T.rgb(frames["zone:Westfall"].label.__textColor, want)
end)

T.test("quests rows: headers, their line and zone names in the class gradient", function()
    local frames = painted({ quests = { STEW } }, nil, function(db)
        stub.SetUnits({ player = { name = "Me", class = "MAGE" } })
        db.colors.headerMode, db.colors.headerLineMode, db.colors.zoneMode = "gradient", "gradient", "gradient"
    end)
    local G = DaylightUI.Gradients
    local h = frames["section:quests"]
    T.eq(h.label:GetText(), G.Text("MAGE", "QUESTS"))
    T.rgb(h.label.__textColor, { 1, 1, 1 })
    T.eq(h.rule.__gradient[1], "HORIZONTAL")
    T.eq(frames["zone:Westfall"].label:GetText(), G.Text("MAGE", "WESTFALL"))
end)

T.test("quests rows: no class known, the gradient falls back to the class color", function()
    local frames, ns, look = painted({ quests = { STEW } }, nil, function(db)
        stub.SetUnits({})
        db.colors.headerMode = "gradient"
    end)
    T.eq(ns.Look.Mode(look, "header"), "class")
    T.eq(frames["section:quests"].label:GetText(), "QUESTS")
end)

T.test("quests rows: under the mouse the title lifts toward white, no box behind", function()
    local frames, ns = painted({ quests = { STEW } })
    local f = frames["quest:1"]
    T.isnil(f.hover, "no row box")
    local title = f.lines.title
    local base = { unpack(title.label.__textColor) }
    DaylightUI:Set("general", "motion", false); ns.Rows.Hover(f, true)
    local r, g, b = unpack(title.label.__textColor)
    local k = ns.Rows.LIFT
    T.near(r, base[1] + (1 - base[1]) * k); T.near(g, base[2] + (1 - base[2]) * k); T.near(b, base[3] + (1 - base[3]) * k)
    T.falsy(ns.Rows.Glow():IsShown(), "the icon stays dark")
    ns.Rows.Hover(f, false)
    T.rgb(title.label.__textColor, base)
end)

T.test("quests rows: over the icon only the icon lights, in the priority color", function()
    local frames, ns = painted({ quests = { STEW } })
    local f = frames["quest:1"]
    local base = { unpack(f.lines.title.label.__textColor) }
    DaylightUI:Set("general", "motion", false); ns.Rows.Hover(f, "icon")
    local glow = ns.Rows.Glow()
    T.truthy(glow:IsShown())
    T.eq(glow.__vertex[4], ns.Rows.GLOW_ALPHA, "its strength is in its color")
    T.eq(glow.__blend, "ADD")
    T.rgb(glow.__vertex, { DaylightUI.Style.Accent() }, "the accent by default")
    T.rgb(f.lines.title.label.__textColor, base, "the title stays as it is")
    ns.Rows.Hover(f, false)
    T.falsy(glow:IsShown())
end)

T.test("quests rows: the header line and the priority icon wear the accent by default", function()
    local frames = painted({ quests = { STEW }, focus = 1 }, nil, function()
        DaylightUI:Set("general", "accent", "custom")
        DaylightUI:Set("general", "accentColor", { 0.1, 0.9, 0.3 })
    end)
    T.rgb(frames["section:quests"].rule.__vertex, { 0.1, 0.9, 0.3 })
    T.rgb(frames["quest:1"].ring.__vertex, { 0.1, 0.9, 0.3 })
end)

T.test("quests rows: section headers and zones can wear the accent", function()
    local frames = painted({ quests = { STEW } }, nil, function(db)
        DaylightUI:Set("general", "accent", "custom")
        DaylightUI:Set("general", "accentColor", { 0.1, 0.9, 0.3 })
        db.colors.headerMode, db.colors.zoneMode = "accent", "accent"
    end)
    T.rgb(frames["section:quests"].label.__textColor, { 0.1, 0.9, 0.3 })
    T.eq(frames["section:quests"].label:GetText(), "QUESTS")
    T.rgb(frames["zone:Westfall"].label.__textColor, { 0.1, 0.9, 0.3 })
end)

T.test("quests rows: the priority color follows its setting", function()
    local frames, ns = painted({ quests = { STEW }, focus = 1 }, nil, function(db)
        db.colors.focusMode = "custom"; db.colors.focus = { 0.2, 0.4, 0.6 }
    end)
    T.rgb(frames["quest:1"].ring.__vertex, { 0.2, 0.4, 0.6 })
    DaylightUI:Set("general", "motion", false); ns.Rows.Hover(frames["quest:1"], "icon")
    T.rgb(ns.Rows.Glow().__vertex, { 0.2, 0.4, 0.6 })
end)

T.test("quests rows: a freed frame comes back clean for another quest", function()
    local frames, ns, look, blocks = painted({ quests = { STEW } })
    local f = frames["quest:1"]
    ns.Rows.Free(f)
    local g = ns.Rows.Get("quest", UIParent)
    T.eq(g, f, "pooled")
    T.isnil(g.key); T.isnil(next(g.lines), "no lines left over")
end)

T.test("quests rows: painting in place adds and removes no lines", function()
    local frames, ns, look, blocks = painted({ quests = { STEW } })
    local f = frames["quest:1"]
    local ready = { key = "quest:1", kind = "quest", y = 0, h = 30, quest = { id = 1, title = "Westfall Stew", state = "ready", diff = { 1, 1, 1 }, objs = {} },
                    lines = { { key = "title", kind = "title", y = 0, h = 15, text = "Westfall Stew" }, { key = "turnin", kind = "turnin", y = 16, h = 14, text = "Go" } } }
    ns.Rows.Paint(f, ready, look, { inPlace = true })
    T.isnil(f.lines.turnin, "no new line in place")
    T.truthy(f.lines["obj:1"], "old lines kept")
end)

T.test("quests rows: timer text", function()
    local _, ns = load()
    T.eq(ns.Rows.TimerText(252), "4:12 left")
    T.eq(ns.Rows.TimerText(48), "0:48 left")
end)

local function animator()
    local _, ns = load()
    local A = ns.Animate
    local placed = {}
    A.place = function(f, y, dx, a) placed[f] = { y = y, dx = dx, a = a } end
    local function run(secs) for _ = 1, math.floor(secs * 60 + 0.5) do stub.RunOnUpdate(A.driver, 1 / 60) end end
    return A, placed, run
end

T.test("quests motion: a jump places at once; a glide eases there", function()
    local A, placed, run = animator()
    local f = CreateFrame("Frame")
    A.Jump(f, 10)
    T.eq(placed[f].y, 10); T.eq(placed[f].a, 1)
    A.Glide(f, 50)
    run(0.15)
    T.truthy(placed[f].y > 10 and placed[f].y < 50, "partway")
    run(0.3)
    T.eq(placed[f].y, 50); T.eq(A.Moving(), false)
end)

T.test("quests motion: a new goal partway turns round from where it is", function()
    local A, placed, run = animator()
    local f = CreateFrame("Frame")
    A.Jump(f, 0)
    A.Glide(f, 100)
    run(0.15)
    local mid = placed[f].y
    A.Glide(f, 0)
    run(1 / 60)
    T.truthy(math.abs(placed[f].y - mid) < 5, "no jump back to the start")
end)

T.test("quests motion: enter slides in and fades up; leave slides out and tells when done", function()
    local A, placed, run = animator()
    local f = CreateFrame("Frame")
    A.Enter(f, 30)
    T.eq(placed[f].dx, 16); T.eq(placed[f].a, 0); T.eq(placed[f].y, 30)
    run(0.3)
    T.eq(placed[f].dx, 0); T.eq(placed[f].a, 1)
    local gone = false
    A.Leave(f, function() gone = true end)
    run(0.3)
    T.eq(placed[f].dx, 12); T.eq(placed[f].a, 0); T.eq(gone, true)
end)

T.test("quests motion: a far leave slides further and slower", function()
    local A, placed, run = animator()
    local f = CreateFrame("Frame")
    A.Jump(f, 0)
    local gone = false
    A.Leave(f, function() gone = true end, true)
    run(0.3)
    T.eq(gone, false, "still going after NORMAL")
    run(0.15)
    T.eq(placed[f].dx, 40); T.eq(placed[f].a, 0); T.eq(gone, true)
end)

T.test("quests motion: with motion off everything jumps", function()
    local A, placed = animator()
    DaylightUI.DB.General().motion = false
    local f = CreateFrame("Frame")
    A.Jump(f, 0)
    A.Glide(f, 40)
    T.eq(placed[f].y, 40)
    local gone = false
    A.Leave(f, function() gone = true end)
    T.eq(gone, true)
end)

T.test("quests motion: the tick hook runs while things move", function()
    local A, _, run = animator()
    local ticks = 0
    A.onTick = function() ticks = ticks + 1 end
    local f = CreateFrame("Frame")
    A.Jump(f, 0); A.Glide(f, 10)
    run(0.1)
    T.truthy(ticks > 0)
end)

-- The tracker built and at rest: renders run, the animator played out.
local function tracker(spec, opts)
    local DUI, ns = load(spec, opts)
    stub.RunTimers()
    local function settle() stub.RunTimers(); for _ = 1, 60 do stub.RunOnUpdate(ns.Animate.driver, 1 / 60) end end
    return ns.Tracker, ns, settle
end

T.test("quests rows: the zone name color changes at once from the options", function()
    local Tr = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "colors.zone", { 0.1, 0.9, 0.3 })
    stub.RunTimers()
    T.rgb(Tr.frames["zone:Westfall"].label.__textColor, { 0.1, 0.9, 0.3 })
end)

T.test("quests tracker: login builds every block with no entrance", function()
    local Tr, ns = tracker({ quests = { STEW, QW.quest(2, "Red Leather Bandanas") } })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(ns.Blizzard.starved, true, "the game's tracker is off")
    T.truthy(Tr.frames["quest:1"]); T.truthy(Tr.frames["quest:2"]); T.truthy(Tr.frames["section:quests"])
    for _, f in pairs(Tr.frames) do
        T.isnil(next(ns.Animate.State(f).ch), "nothing animating at login")
    end
end)

T.test("quests tracker: the login reveal slides the lines in one after another; a fight first: they land", function()
    local Tr, ns, settle = tracker({ quests = { STEW, QW.quest(2, "Red Leather Bandanas") } })
    local A = ns.Animate
    local f1, f2 = Tr.frames["quest:1"], Tr.frames["quest:2"]
    local y1 = A.State(f1).y
    DaylightUI.Fire("LoginReveal")
    T.eq(A.State(f1).a, 0, "clear until its turn")
    T.eq(A.State(f1).dx, A.ENTER_DX, "nudged right, like a new quest")
    stub.RunTimers()
    T.truthy(A.State(f1).ch.dx and A.State(f2).ch.dx, "each slides in")
    settle()
    T.eq(A.State(f1).a, 1); T.eq(A.State(f1).dx, 0)
    T.eq(A.State(f1).y, y1, "where it rests")

    Tr, ns = tracker({ quests = { STEW } })
    A = ns.Animate
    f1 = Tr.frames["quest:1"]
    DaylightUI.Fire("LoginReveal")
    stub.EnterCombat()
    stub.RunTimers()
    T.eq(A.State(f1).a, 1, "a fight: shown at once")
    T.eq(A.State(f1).dx, 0)
    T.isnil(next(A.State(f1).ch), "nothing moving")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests tracker: a turned-in quest leaves the others' frames and text untouched", function()
    local Tr, ns, settle = tracker({ quests = { STEW, QW.quest(2, "Red Leather Bandanas"), QW.quest(3, "Patrolling Westfall") } })
    local f2, f3 = Tr.frames["quest:2"], Tr.frames["quest:3"]
    local text3 = f3.lines.title.label:GetText()
    QW.state.quests[1].watched = false
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 1, false)
    stub.RunTimers()
    T.eq(Tr.frames["quest:2"], f2, "same frame")
    T.eq(Tr.frames["quest:3"], f3, "same frame")
    T.eq(f3.lines.title.label:GetText(), text3)
    local ch = ns.Animate.State(f3).ch
    T.truthy(ch.y, "it glides up")
    T.isnil(ch.a, "no fade on a row that only moves"); T.isnil(ch.dx)
    settle()
    T.isnil(Tr.frames["quest:1"], "gone")
end)

T.test("quests tracker: a measured height of nothing falls back to one line", function()
    local Tr = tracker({ quests = { STEW } })
    T.eq(Tr.Measure("anything", 12, 200), 0, "the stub can't measure")
    T.eq(Tr.shown[3].lines[1].h, 15)
end)

T.test("quests tracker: folding a section frees its quests and is remembered per character", function()
    local Tr, ns, settle = tracker({ quests = { STEW } })
    Tr.ToggleFold("quests")
    settle()
    T.isnil(Tr.frames["quest:1"])
    T.eq(DaylightUI.DB.Character().questFolds.quests, true)
    T.eq(Tr.shown[1].folded, true, "the header knows (its chevron turns: Task 7)")
end)

T.test("quests tracker: This zone only, and the width follows the minimap", function()
    local Tr, ns, settle = tracker({ zone = "Elwynn Forest", quests = { STEW, QW.quest(2, "A Fishy Peril", { zone = "Elwynn Forest" }) } },
        { infopanel = true, before = QW.panelWorld })
    DaylightUI:Set("Quests", "filter", "zone")
    settle()
    T.isnil(Tr.frames["quest:1"]); T.truthy(Tr.frames["quest:2"])
    DaylightUI:Set("InfoPanel", "map.size", 260)
    T.eq(Tr.Width(), 260)
    T.eq(Tr.view:GetWidth(), 260, "the list follows the slider at once, no quest event needed")
    DaylightUI:Set("Quests", "matchMap", false)
    T.eq(Tr.Width(), 226)
end)

-- The classic log files a starting area's quests under its own name (Northshire
-- Valley), while the game's zone text says Elwynn Forest. The subzone text names
-- it only in the open valley; in the Abbey it says Northshire Abbey.
local NORTHSHIRE = QW.quest(3, "Wolves Across the Border", { zone = "Northshire Valley" })
local function elwynnMaps(where)
    _G.GetSubZoneText = function() return where.sub end
    Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
    local maps = { [1429] = { mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
                   [1436] = { mapID = 1436, name = "Westfall", mapType = 3, parentMapID = 1415 },
                   [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 } }
    C_Map.GetBestMapForUnit = function() return 1429 end
    C_Map.GetMapInfo = function(id) return maps[id] end
    C_Map.GetMapChildrenInfo = function(id)
        if id == 1415 then return { maps[1429], maps[1436] } end
    end
    -- Both quests have a spot on Elwynn's map, the Westfall one its hand-in.
    C_QuestLog.GetQuestsOnMap = function(id)
        if id == 1429 and where.spots then return { { questID = 3, x = 0.5, y = 0.4 }, { questID = 1, x = 0.4, y = 0.8 } } end
        return {}
    end
end
local function unElwynn() _G.GetSubZoneText = nil end

T.test("quests tracker: This zone counts the subzone the log names", function()
    local where = { sub = "Goldshire" }
    local Tr, ns, settle = tracker({ zone = "Elwynn Forest", quests = { STEW, NORTHSHIRE } },
        { before = function() elwynnMaps(where) end })
    DaylightUI:Set("Quests", "filter", "zone")
    settle()
    T.isnil(Tr.frames["quest:3"], "Goldshire isn't Northshire")
    where.sub = "Northshire Valley"
    stub.FireEvent("ZONE_CHANGED")
    settle()
    T.truthy(Tr.frames["quest:3"], "a new subzone in the same zone looks again")
    T.isnil(Tr.frames["quest:1"])
    unElwynn()
end)

T.test("quests tracker: This zone counts a part of the zone whose quests are on its map", function()
    local where = { sub = "Northshire Abbey", spots = true }
    local Tr, ns, settle = tracker({ zone = "Elwynn Forest", quests = { STEW, NORTHSHIRE } },
        { before = function() elwynnMaps(where) end })
    DaylightUI:Set("Quests", "filter", "zone")
    settle()
    T.truthy(Tr.frames["quest:3"], "Northshire Valley is in Elwynn: its quests are on Elwynn's map")
    T.isnil(Tr.frames["quest:1"], "Westfall is a zone of its own, though its hand-in is on this map")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    unElwynn()
end)

T.test("quests data: every header that counts as here comes first", function()
    local where = { sub = "Northshire Abbey", spots = true }
    local _, ns = load({ zone = "Elwynn Forest", quests = { STEW, QW.quest(2, "B", { zone = "Elwynn Forest" }), NORTHSHIRE } },
        { before = function() elwynnMaps(where) end })
    local d = ns.Data.Snapshot()
    T.truthy(d.here["Northshire Valley"]); T.truthy(d.here["Elwynn Forest"]); T.isnil(d.here.Westfall)
    T.eq(d.zone, "Elwynn Forest", "the zone itself stays the main one")
    T.eq(d.groups[3].name, "Westfall", "the zone and its part ahead of Westfall")
    unElwynn()
end)

T.test("quests tracker: the box only when asked", function()
    local Tr, ns, settle = tracker({ quests = { STEW } })
    T.eq(Tr.box:IsShown(), false)
    DaylightUI:Set("Quests", "box", true)
    settle()
    T.eq(Tr.box:IsShown(), true)
end)

T.test("quests tracker: hangs from the info panel's anchor, else under the screen's corner", function()
    local Tr = tracker({ quests = {} }, { infopanel = true, before = QW.panelWorld })
    T.eq(Tr.Default()[2], "DaylightUITrackerAnchor")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    Tr = tracker({ quests = {} })
    T.deq(Tr.Default(), Tr.FALLBACK)
end)

T.test("quests tracker: a spot the game's tracker was moved to carries over", function()
    load({ quests = {} }, { login = false })
    DaylightUI.DB.Positions()["infopanel.tracker"] = { 100, 50 }
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    T.deq(DaylightUI.DB.Positions()["quests.tracker"], { 111, 50, follows = true }, "same top-right corner: (248 - 226) / 2 further right")
end)

T.test("quests tracker: Reset puts it under the panel, not where the game's tracker once was", function()
    load({ quests = {} }, { login = false, infopanel = true, before = QW.panelWorld })
    DaylightUI.DB.Positions()["infopanel.tracker"] = { -300, 100 }
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    local P, IT = stub.infopanel.Panel, stub.infopanel.Tracker
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 700 end
    IT.Apply(DaylightUI:Get("InfoPanel", "tracker"))
    stub.RunTimers()
    local _, _, _, x, y = IT.anchor:GetPoint(1)
    T.eq(x, 1900 - IT.EDGE, "the anchor (our tracker's home) under the panel")
    T.eq(y, 700 - P.GAP)
end)

T.test("quests tracker: a spot carried over from under the panel follows the data texts' strip", function()
    load({ quests = {} }, { login = false, infopanel = true, before = QW.panelWorld })
    local P, IT = stub.infopanel.Panel, stub.infopanel.Tracker
    local bottom = 700
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return bottom end
    -- Where the game's tracker sat under the panel (saved by the info panel
    -- once it got there), carried over: its top-right at the panel's corner.
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    DaylightUI.DB.Positions()["infopanel.tracker"] = { 1900 - IT.HANDLE[1] / 2 - W / 2, 700 - P.GAP - IT.HANDLE[2] / 2 - H / 2 }
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    T.truthy(DaylightUI.DB.Positions()["quests.tracker"], "carried over")
    -- The strip comes on: the panel grows down by its height.
    bottom = 700 - stub.infopanel.DataTexts.Room({ data = { enabled = true, textSize = 11 } })
    DaylightUI:Set("InfoPanel", "data.enabled", true)
    stub.RunTimers()
    T.isnil(DaylightUI.DB.Positions()["quests.tracker"], "the spot was the panel's, not the player's: dropped")
    local point, rel = DaylightUIQuestTracker:GetPoint(1)
    T.eq(point, "TOPRIGHT"); T.eq(rel, DaylightUITrackerAnchor, "hangs from the anchor again, so it follows from now on")
    -- A spot moved anywhere else stays.
    DaylightUI.DB.Positions()["quests.tracker"] = { -300, 100 }
    DaylightUI:Set("InfoPanel", "data.enabled", false)
    stub.RunTimers()
    T.deq(DaylightUI.DB.Positions()["quests.tracker"], { -300, 100 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player report: moved a little lower under the panel (the magnet keeps
-- its right edge on the panel's), it went back under the panel at the next
-- login. Only a spot carried over from the game's tracker follows the strip.
T.test("quests tracker: a spot moved by hand just under the panel stays after a reload", function()
    load({ quests = {} }, { login = false, infopanel = true, before = QW.panelWorld })
    local P = stub.infopanel.Panel
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 700 end
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    local h = DaylightUIQuestTracker
    local Movers = DaylightUI.Movers
    -- Dragged one grid step lower, right edge still on the panel's.
    h.__center = { 1900 - h:GetWidth() / 2, 700 - P.GAP - Movers.GRID - h:GetHeight() / 2 }
    Movers.Save("quests.tracker", true)
    h.__center = nil
    local spot = DaylightUI.DB.Copy(DaylightUI.DB.Positions()["quests.tracker"])
    T.truthy(spot, "saved")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.deq(DaylightUI.DB.Positions()["quests.tracker"], spot, "kept")
    DaylightUI:Set("InfoPanel", "data.enabled", true)
    stub.RunTimers()
    T.deq(DaylightUI.DB.Positions()["quests.tracker"], spot, "the strip coming on doesn't take it either")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

local function spyMotion()
    local M, seen = DaylightUI.Motion, {}
    for _, name in ipairs({ "Bump", "Pop", "Flash" }) do
        local orig = M[name]
        M[name] = function(region, ...) table.insert(seen, { name, region }); return orig(region, ...) end
    end
    return seen
end
local function count(seen, name, region)
    local n = 0
    for _, s in ipairs(seen) do if s[1] == name and (region == nil or s[2] == region) then n = n + 1 end end
    return n
end

T.test("quests tracker: a level up recolors a title that turned green", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { difficulty = 2 }) } })
    local function title(name)
        local c = QW.COLORS[name]
        T.rgb(Tr.frames["quest:1"].lines.title.label.__textColor, { DaylightUI.Style.Soften(c.r, c.g, c.b) }, name)
    end
    title("difficult")
    QW.state.quests[1].difficulty = 1
    stub.FireEvent("PLAYER_LEVEL_UP"); stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    title("standard")
end)

-- QUEST_LOG_UPDATE comes many a second in a fight, and each look reads the
-- whole log; anything that isn't a bare update still runs next frame.
T.test("quests tracker: a bare quest update waits longer in a fight, and progress still counts", function()
    local Tr, ns = tracker({ quests = { STEW, QW.quest(2, "B", { objs = { { text = "1/5 Y", have = 1, need = 5 } } }) } })
    stub.RunTimers()
    local waits, after = {}, C_Timer.After
    C_Timer.After = function(s, fn) waits[#waits + 1] = s; return after(s, fn) end
    stub.FireEvent("QUEST_LOG_UPDATE")
    T.eq(waits[#waits], Tr.LOG_WAIT, "out of a fight")
    stub.RunTimers()
    stub.combat = true
    stub.FireEvent("QUEST_LOG_UPDATE")
    T.eq(waits[#waits], Tr.LOG_WAIT_FIGHT, "in one")
    C_Timer.After = after
    local recent = Tr.Recent()
    QW.state.quests[2].objs[1] = { text = "2/5 Y", have = 2, need = 5 }
    stub.RunTimers()
    T.truthy(recent[2], "the count going up is seen once the wait is over")
    local first = recent[2]
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(recent[2], first, "no second count for the same progress")
    QW.state.quests[2].objs[1] = { text = "3/5 Y", have = 3, need = 5 }
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.truthy(recent[2] > first, "and the next one counts too")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests tracker: a quest event that changes nothing shown paints nothing; a new subzone isn't a change", function()
    local Tr, ns = tracker({ quests = { STEW, QW.quest(2, "B", { objs = { { text = "1/5 Y", have = 1, need = 5 } } }) } })
    local paints, orig = 0, ns.Rows.Paint
    ns.Rows.Paint = function(...) paints = paints + 1; return orig(...) end
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(paints, 0, "the same list: nothing repainted")
    local snaps, snap = 0, ns.Data.Snapshot
    ns.Data.Snapshot = function(...) snaps = snaps + 1; return snap(...) end
    stub.FireEvent("ZONE_CHANGED"); stub.RunTimers()
    T.eq(snaps, 0, "same zone, another part of it: not even a look at the log")
    QW.state.quests[2].objs[1] = { text = "2/5 Y", have = 2, need = 5 }
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.truthy(paints > 0, "a count going up does paint")
    paints = 0
    Tr.Apply()
    T.truthy(paints > 0, "a setting always lays it out")
    ns.Rows.Paint, ns.Data.Snapshot = orig, snap
end)

T.test("quests effects: a count going up bumps that number only", function()
    local Tr, ns, settle = tracker({ quests = { STEW, QW.quest(2, "B", { objs = { { text = "1/5 Y", have = 1, need = 5 } } }) } })
    local seen = spyMotion()
    QW.state.quests[1].objs[2] = { text = "4/6 Goretusk Snout", have = 4, need = 6 }
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    local count2 = Tr.frames["quest:1"].lines["obj:2"].count
    T.eq(count(seen, "Bump", count2), 1)
    T.eq(#seen, 1, "nothing else moved")
end)

T.test("quests effects: an objective done gets the sheen and the tick", function()
    local Tr, ns = tracker({ quests = { STEW } })
    local seen = spyMotion()
    QW.state.quests[1].objs[1] = { text = "5/5 Stringy Vulture Meat", have = 5, need = 5, done = true }
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    local l = Tr.frames["quest:1"].lines["obj:1"]
    T.eq(l.sheen.anim:IsPlaying(), true)
    T.eq(count(seen, "Pop", l.tick), 1)
end)

-- How often our quest chime played (Media/sounds/shh-quest3.ogg).
local function chimes()
    local n = 0
    for _, file in ipairs(QW.Calls("soundFile")) do
        if file == DaylightUI.Sound.FILES.quest then n = n + 1 end
    end
    return n
end

T.test("quests effects: a quest turning ready pops its '?' and plays our chime once", function()
    local Tr, ns = tracker({ quests = { STEW } })
    local seen = spyMotion()
    QW.state.quests[1].complete = true
    QW.state.quests[1].turnIn = "Return to Salma"
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(count(seen, "Pop", Tr.frames["quest:1"].ready), 1)
    T.eq(chimes(), 1)
    T.eq(#QW.Calls("sound"), 0, "not the game's hand-in sound")
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(chimes(), 1, "not again")
end)

-- The gold sheen on a quest's title: playing, in the ready color.
local function goldSheen(Tr, f)
    local s = f.lines.title.sheen
    T.truthy(s, "the title has a sheen")
    T.eq(s.anim:IsPlaying(), true, "it runs")
    local c = Tr.Look().c.ready
    local to = s.left.__gradient[3]
    T.rgb({ to.r, to.g, to.b }, { c[1], c[2], c[3] }, "gold")
end

T.test("quests effects: a quest turning ready runs a gold sheen across its title", function()
    local Tr = tracker({ quests = { STEW } })
    QW.state.quests[1].complete = true
    QW.state.quests[1].turnIn = "Return to Salma"
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    goldSheen(Tr, Tr.frames["quest:1"])
end)

T.test("quests effects: no gold sheen on a quest already ready at login", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { complete = true, turnIn = "Return" }) } })
    T.eq(Tr.frames["quest:1"].ready:IsShown(), true)
    T.eq(Tr.frames["quest:1"].lines.title.sheen.anim:IsPlaying(), false)
end)

T.test("quests effects: the gold sheen plays inside a combat hold", function()
    local Tr = tracker({ quests = { STEW, QW.quest(2, "B", { item = { link = "|cffffffff|Hitem:5862::::::::|h[Seaforium]|h|r", icon = 1, charges = 1 } }) } })
    stub.secure = true
    stub.EnterCombat()
    QW.state.quests[1].complete = true      -- quest 1 folds: quest 2 would move up
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(Tr.held, true)
    goldSheen(Tr, Tr.frames["quest:1"])
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests effects: a turn-in leaves with the long slow slide; an untrack keeps the short one", function()
    local Tr, ns, settle = tracker({ quests = { STEW, QW.quest(2, "B"), QW.quest(3, "C") } })
    local M = DaylightUI.Motion
    local f1, f2 = Tr.frames["quest:1"], Tr.frames["quest:2"]
    table.remove(QW.state.quests, 1)
    stub.FireEvent("QUEST_TURNED_IN", 1, 0, 0)
    stub.FireEvent("QUEST_REMOVED", 1)
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 1, false)
    stub.RunTimers()
    T.eq(ns.Animate.LEAVE_FAR_DX, 40)
    local dx = ns.Animate.State(f1).ch.dx
    T.eq(dx.to, ns.Animate.LEAVE_FAR_DX); T.eq(dx.dur, M.SLOW)
    settle()
    T.isnil(Tr.frames["quest:1"], "gone")
    QW.state.quests[1].watched = false
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 2, false); stub.RunTimers()
    dx = ns.Animate.State(f2).ch.dx
    T.eq(dx.to, ns.Animate.LEAVE_DX); T.eq(dx.dur, M.NORMAL)
end)

T.test("quests effects: the chime can be turned off", function()
    local Tr = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "sound", false)
    QW.state.quests[1].complete = true
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(chimes(), 0)
end)

T.test("quests effects: Soft UI sounds off silences the chime too", function()
    local Tr = tracker({ quests = { STEW } })
    DaylightUI:Set("general", "sounds", false)
    QW.state.quests[1].complete = true
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(chimes(), 0)
end)

-- The switch lives on General > Sound and writes the tracker's own setting.
local function chimeItem()
    for _, page in DaylightUI.Options.Pages() do
        for _, g in ipairs(page.groups or {}) do
            for _, item in ipairs(g.items or {}) do
                if item.label == "Quest ready chime" then return item, page, g end
            end
        end
    end
end

T.test("quests options: the chime's switch sits on General > Sound and writes Quests.sound", function()
    tracker({ quests = { STEW } })
    local item, page, g = chimeItem()
    T.truthy(item, "found")
    T.eq(g.label, "Sound")
    T.eq(item.get(), true, "on by default")
    item.set(false)
    T.eq(DaylightUI:Get("Quests", "sound"), false)
    T.eq(item.get(), false)
    T.eq(item.hidden(), false, "shown while the tracker is on")
    T.eq(item.disabled(function(k) if k == "sounds" then return false end end), true, "dims with Soft UI sounds off")
end)

T.test("quests effects: accepting slides one quest in; the rest only glide", function()
    local Tr, ns = tracker({ quests = { STEW } })
    table.insert(QW.state.quests, 1, QW.quest(7, "Goretusk Liver Pie"))
    stub.FireEvent("QUEST_ACCEPTED", 7); stub.RunTimers()
    local new, old = ns.Animate.State(Tr.frames["quest:7"]), ns.Animate.State(Tr.frames["quest:1"])
    T.truthy(new.ch.dx and new.ch.a, "slides and fades in")
    T.truthy(old.ch.y, "the other glides down")
    T.isnil(old.ch.a)
end)

T.test("quests effects: turn-in mid-glide turns round without a jump", function()
    local Tr, ns, settle = tracker({ quests = { STEW, QW.quest(2, "B"), QW.quest(3, "C") } })
    table.insert(QW.state.quests, 1, QW.quest(7, "New"))
    stub.FireEvent("QUEST_ACCEPTED", 7); stub.RunTimers()
    for _ = 1, 6 do stub.RunOnUpdate(ns.Animate.driver, 1 / 60) end
    local f3 = Tr.frames["quest:3"]
    local mid = ns.Animate.State(f3).y
    QW.state.quests[2].watched = false
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 1, false); stub.RunTimers()
    stub.RunOnUpdate(ns.Animate.driver, 1 / 60)
    T.truthy(math.abs(ns.Animate.State(f3).y - mid) < 6, "turns round from where it was")
    T.eq(Tr.frames["quest:3"], f3)
end)

T.test("quests effects: nothing plays at login or after a loading screen", function()
    local seen
    local Tr = tracker({ quests = { STEW } }, { before = function() end })
    seen = spyMotion()
    stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers()
    T.eq(#seen, 0)
end)

-- Most recent progress first: the quests' order on screen, by id.
local function order(Tr)
    local out = {}
    for _, b in ipairs(Tr.shown) do if b.kind == "quest" then out[#out + 1] = b.quest.id end end
    return out
end
local function kills(have) return { { text = have .. "/14 Murloc", have = have, need = 14 } } end
local THREE = { quests = {
    QW.quest(1, "A", { objs = kills(1) }), QW.quest(2, "B", { objs = kills(1) }),
    QW.quest(3, "C", { zone = "Elwynn Forest", objs = kills(1) }) } }

T.test("quests order: progress moves a quest to the top of its zone, and its zone to the top", function()
    local Tr, ns = tracker(THREE)
    T.deq(order(Tr), { 1, 2, 3 })
    QW.state.quests[2].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 2, 1, 3 })
    T.truthy(ns.Animate.State(Tr.frames["quest:1"]).ch.y, "the others glide")
    QW.state.quests[3].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 3, 2, 1 }, "Elwynn rises over the zone you're in")
    QW.state.quests[1].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 1, 2, 3 }, "newest first")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests order: a bar filling, an objective done and a quest turning ready count", function()
    local Tr = tracker({ quests = {
        QW.quest(1, "A", { objs = kills(1) }),
        QW.quest(2, "B", { pct = 10, objs = { { text = "Explore: 10%", type = "progressbar" } } }),
        QW.quest(3, "C", { objs = { { text = "Speak to Gryan" } } }) } })
    QW.state.quests[2].pct = 40
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 2, 1, 3 }, "bar")
    QW.state.quests[3].objs[1].done = true
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 3, 2, 1 }, "done")
    QW.state.quests[1].complete = true
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 1, 3, 2 }, "ready")
end)

T.test("quests order: a count going down or a new quest moves nothing", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { objs = kills(1) }), QW.quest(2, "B", { objs = kills(3) }) } })
    QW.state.quests[2].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 1, 2 }, "down")
    table.insert(QW.state.quests, QW.quest(7, "New", { objs = kills(5) }))
    stub.FireEvent("QUEST_ACCEPTED", 7); stub.RunTimers()
    T.deq(order(Tr), { 1, 2, 7 }, "a new quest isn't progress")
end)

T.test("quests order: switched off, the game's order stays", function()
    local Tr = tracker(THREE)
    DaylightUI:Set("Quests", "sort", "zone")
    stub.RunTimers()
    QW.state.quests[2].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 1, 2, 3 })
    DaylightUI:Set("Quests", "sort", "recent")
    stub.RunTimers()
    T.deq(order(Tr), { 2, 1, 3 }, "on again: what moved meanwhile goes first")
end)

T.test("quests saved data: the old map marks' and quest givers' lists are cleared at login", function()
    tracker({ quests = { STEW } })
    local saved = DaylightUIDB
    saved.characters["Other-Realm"] = { questGiversSeen = { [1] = true }, questMarksHidden = { [2] = true }, install = "installed" }
    local key = DaylightUI.DB.CharKey()
    saved.characters[key].questPinsHidden = { [3] = true }
    tracker({ quests = { STEW } }, { before = function() _G.DaylightUIDB = saved end })
    local other = DaylightUIDB.characters["Other-Realm"]
    T.isnil(other.questGiversSeen); T.isnil(other.questMarksHidden)
    T.eq(other.install, "installed", "the rest stays")
    T.isnil(DaylightUIDB.characters[key].questPinsHidden)
end)

T.test("quests order: in a fight the zones stay; after it the newest goes first", function()
    local Tr = tracker(THREE)
    QW.state.quests[3].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 3, 1, 2 })
    stub.EnterCombat()
    QW.state.quests[1].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 3, 1, 2 }, "nothing re-sorts in a fight")
    stub.LeaveCombat(); stub.RunTimers()
    T.deq(order(Tr), { 1, 2, 3 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests order: kept per character through a reload; a quest that leaves is forgotten", function()
    local Tr = tracker(THREE)
    QW.state.quests[2].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    local saved = DaylightUIDB
    local spec = { quests = { QW.quest(1, "A", { objs = kills(1) }), QW.quest(2, "B", { objs = kills(2) }),
                              QW.quest(3, "C", { zone = "Elwynn Forest", objs = kills(1) }) } }
    Tr = tracker(spec, { before = function() _G.DaylightUIDB = saved end })
    T.deq(order(Tr), { 2, 1, 3 }, "after the reload")
    table.remove(QW.state.quests, 2)
    stub.FireEvent("QUEST_REMOVED", 2); stub.RunTimers()
    T.isnil(DaylightUI.DB.Character().questRecent[2])
end)

T.test("quests order: in combat a move that would shift an item quest waits for the fight's end", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { objs = kills(1), item = { link = "|cffffffff|Hitem:5862::::::::|h[Seaforium]|h|r", icon = 1, charges = 1 } }),
                                    QW.quest(2, "B", { objs = kills(1) }) } })
    stub.secure = true
    stub.EnterCombat()
    QW.state.quests[2].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 1, 2 }, "nothing moves under the item button (nothing re-sorts in a fight)")
    stub.LeaveCombat(); stub.RunTimers()
    T.deq(order(Tr), { 2, 1 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

local ITEM = { link = "|cffffffff|Hitem:5862::::::::|h[Seaforium]|h|r", icon = 1234, charges = 2 }

T.test("quests items: one secure button per quest with an item", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }), QW.quest(2, "B") } })
    local b = ns.Items.buttons[1]
    T.truthy(b, "made")
    T.eq(b:IsProtected(), true)
    T.eq(b:GetAttribute("type"), "item")
    T.eq(b:GetAttribute("item"), "item:5862")
    T.isnil(ns.Items.buttons[2])
end)

T.test("quests items: in combat a change that would move an item quest waits", function()
    local Tr, ns, settle = tracker({ quests = { STEW, QW.quest(2, "B", { item = ITEM }) } })
    stub.secure = true
    local y2 = Tr.shown[4].y
    stub.EnterCombat()
    QW.state.quests[1].complete = true      -- quest 1 folds: quest 2 would move up
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(Tr.held, true)
    T.eq(Tr.shown[4].y, y2, "the layout on screen is the old one")
    T.eq(Tr.frames["quest:1"].ready:IsShown(), true, "the '?' shows at once anyway")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(Tr.held, false)
    T.truthy(Tr.shown[4].y < y2, "after the fight it moves")
end)

T.test("quests items: in combat a change below the last item quest plays at once", function()
    -- (its own id: STEW is quest 1 too)
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }), QW.quest(2, "Westfall Stew", { objs = STEW.objs }) } })
    DaylightUI:Set("Quests", "sort", "zone")   -- else turning ready takes quest 2 to the top
    stub.RunTimers()
    stub.EnterCombat()
    QW.state.quests[2].complete = true
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(Tr.held, false)
end)

-- growUp: the list stands on its bottom, so a change below the item quest
-- that makes the list shorter still moves the item quest's row.
T.test("quests items: growing up, in combat a change below the item quest that changes the height waits", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }), QW.quest(2, "Westfall Stew", { objs = STEW.objs }) } })
    DaylightUI:Set("Quests", "sort", "zone")
    DaylightUI:Set("Quests", "growUp", true)
    stub.RunTimers()
    local h = Tr.contentHeight
    stub.EnterCombat()
    QW.state.quests[2].complete = true      -- quest 2 folds into its ready line: the list gets shorter
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(Tr.held, true, "held: the row under the item button would slide")
    T.eq(Tr.contentHeight, h, "the height on screen is the old one")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(Tr.held, false)
    T.truthy(Tr.contentHeight < h, "after the fight it plays")
end)

-- Scrolled to the bottom of a long list: a shorter list pulls the scroll
-- back, moving every row (the item quest's too).
T.test("quests items: in combat a shorter list that pulls the scroll back waits", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }), QW.quest(2, "Westfall Stew", { objs = STEW.objs }) } })
    DaylightUI:Set("Quests", "sort", "zone")
    stub.RunTimers()
    DaylightUI:Set("Quests", "maxHeight", math.floor(Tr.contentHeight - 30))
    stub.RunTimers()
    ns.Scroll.To(1000)
    T.truthy(ns.Scroll.offset > 0, "scrolled down")
    stub.EnterCombat()
    QW.state.quests[2].complete = true
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(Tr.held, true, "held: the scroll would move")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(Tr.held, false)
end)

T.test("quests items: an item used up in combat goes see-through, then away after", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }) } })
    stub.secure = true
    stub.EnterCombat()
    QW.state.quests[1].item = nil
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(ns.Items.buttons[1]:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(ns.Items.buttons[1]:IsShown(), false)
end)

T.test("quests items: a secret cooldown is never handed to SetCooldown", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }) } })
    local btn = ns.Items.buttons[1]
    local handed = 0
    btn.cooldown.SetCooldown = function(_, a, b)
        if issecretvalue(a) or issecretvalue(b) then handed = handed + 1 end
    end
    local old = _G.GetQuestLogSpecialItemCooldown
    _G.GetQuestLogSpecialItemCooldown = function() return stub.Secret(100), stub.Secret(30), 1 end
    ns.Items.Refresh()
    _G.GetQuestLogSpecialItemCooldown = old
    T.eq(handed, 0, "the client refuses secrets there from addon code")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests items: out of range tints the icon", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM, itemRange = 0 }) } })
    ns.Items.Refresh()
    T.rgb(ns.Items.buttons[1].icon.__vertex, ns.Items.OUT_OF_RANGE)
end)

local function click(Tr, key, button)
    local f = Tr.frames[key]
    f:GetScript("OnClick")(f, button or "LeftButton")
end

T.test("quests clicks: a click opens the map to the quest and pings it", function()
    local Tr = tracker({ quests = { STEW } })
    click(Tr, "quest:1")
    T.deq(QW.Calls("map"), { 52 }); T.deq(QW.Calls("ping"), { 1 })
end)

T.test("quests clicks: not in combat; the game's error line says so", function()
    local Tr, ns = tracker({ quests = { STEW } })
    stub.EnterCombat()
    click(Tr, "quest:1")
    T.eq(#QW.Calls("map"), 0)
    T.deq(QW.Calls("error"), { ns.Clicks.MAP_IN_COMBAT })
end)

T.test("quests clicks: shift-click stops tracking; it slides out", function()
    local Tr, ns = tracker({ quests = { STEW, QW.quest(2, "B") } })
    QW.state.shift = true
    click(Tr, "quest:1")
    T.deq(QW.Calls("untrack"), { 1 })
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 1, false); stub.RunTimers()
    T.isnil(Tr.frames["quest:1"])
end)

T.test("quests clicks: an auto-complete quest completes on click", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { complete = true, auto = true }) } })
    click(Tr, "quest:1")
    T.deq(QW.Calls("complete"), { 1 })
end)

T.test("quests clicks: a click on the icon makes the quest the priority; again clears it", function()
    local Tr = tracker({ quests = { STEW, QW.quest(2, "B") } })
    local f = Tr.frames["quest:1"]
    f.IsMouseOver = function() return true end
    click(Tr, "quest:1")
    T.deq(QW.Calls("focus"), { 1 })
    T.eq(#QW.Calls("map"), 0, "the icon doesn't open the map")
    click(Tr, "quest:1")
    T.deq(QW.Calls("focus"), { 1, 0 })
end)

T.test("quests clicks: the mouse moving onto the icon lights it; off it the title lifts", function()
    local Tr, ns = tracker({ quests = { STEW } })
    DaylightUI:Set("general", "motion", false)
    local f = Tr.frames["quest:1"]
    local onIcon = true
    f.IsMouseOver = function() return onIcon end
    f:GetScript("OnEnter")(f)
    T.truthy(ns.Rows.Glow():IsShown())
    T.isnil(f.lift)
    onIcon = false
    stub.RunOnUpdate(f, 0.02)
    T.falsy(ns.Rows.Glow():IsShown())
    T.eq(f.lift, 1)
    f:GetScript("OnLeave")(f)
    T.isnil(f.lift); T.isnil(f:GetScript("OnUpdate"))
end)

T.test("quests tracker: the icon glow hangs off the tracker, outside the list that clips", function()
    local Tr, ns = tracker({ quests = { STEW } })
    DaylightUI:Set("general", "motion", false)
    ns.Rows.Hover(Tr.frames["quest:1"], "icon")
    local host = ns.Rows.Glow():GetParent()
    T.eq(host:GetParent(), DaylightUIQuestTracker)
    T.falsy(Tr.frames["quest:1"].glow, "no glow of its own, nothing always on")
end)

T.test("quests clicks: a click away from the icon still opens the map", function()
    local Tr = tracker({ quests = { STEW } })
    Tr.frames["quest:1"].IsMouseOver = function() return false end
    click(Tr, "quest:1")
    T.eq(#QW.Calls("focus"), 0)
    T.deq(QW.Calls("map"), { 52 })
end)

T.test("quests tracker: the priority quest's icon is painted in our gradient", function()
    local Tr, ns = tracker({ quests = { STEW, QW.quest(2, "B") }, focus = 1 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local ring1, ring2 = Tr.frames["quest:1"].ring, Tr.frames["quest:2"].ring
    T.truthy(ring1.__gradient or ring1.__vertex[1] ~= ns.Look.RING[1], "the priority quest stands out")
    T.isnil(ring2.__gradient)
    QW.state.focus = 2
    stub.FireEvent("SUPER_TRACKING_CHANGED"); stub.RunTimers()
    T.truthy(ring2.__gradient or ring2.__vertex[1] ~= ns.Look.RING[1], "the new priority follows")
    T.rgb(ring1.__vertex, ns.Look.RING)
end)

T.test("quests clicks: the menu, with Share only in a group", function()
    local Tr, ns = tracker({ quests = { STEW } })
    local q = Tr.shown[3].quest
    T.deq(ns.Clicks.MenuKeys(q), { "priority", "fold", "map", "details", "wowhead", "untrack", "abandon" })
    stub.SetGroup(true)
    T.deq(ns.Clicks.MenuKeys(q), { "priority", "fold", "map", "details", "share", "wowhead", "untrack", "abandon" })
    stub.EnterCombat()
    T.deq(ns.Clicks.MenuKeys(q), { "priority", "fold", "map", "details", "wowhead", "untrack", "abandon" }, "no Share in a fight")
    ns.Clicks.Do("share", q)
    T.deq(QW.Calls("shareBlocked"), {}, "a menu left open: never tried in a fight, the game blocks it")
    stub.LeaveCombat()
    ns.Clicks.Do("share", q); ns.Clicks.Do("abandon", q)
    T.deq(QW.Calls("share"), { q.logIndex })
    -- A yes/no box of its own, no map or journal needed; only the yes drops it.
    T.deq(QW.Calls("abandon"), {}, "nothing dropped yet")
    T.eq(stub.popup.which, "DAYLIGHTUI_ABANDON_QUEST")
    T.truthy(stub.popup.text:find(q.title, 1, true), "it names the quest")
    T.deq(QW.Calls("map"), {}, "no map opened")
    StaticPopupDialogs.DAYLIGHTUI_ABANDON_QUEST.OnAccept(nil, stub.popup.data)
    T.deq(QW.Calls("abandon"), { q.id })
    T.eq(#QW.Calls("error"), 1, "only the refused Share in the fight said no")
end)

T.test("quests clicks: Abandon's box works in a fight, names what it destroys, and a quest gone meanwhile is left", function()
    local Tr, ns = tracker({ quests = { STEW } })
    local q = Tr.shown[3].quest
    local itemsWas, nameWas = C_QuestLog.GetAbandonQuestItems, C_Item.GetItemNameByID
    C_QuestLog.GetAbandonQuestItems = function() return { 101 } end
    C_Item.GetItemNameByID = function() return "Okra" end
    local combat = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    ns.Clicks.Do("abandon", q)
    T.truthy(stub.popup and stub.popup.text:find("Okra", 1, true), "the item is named")
    T.deq(QW.Calls("error"), {}, "no refusal in a fight")
    _G.InCombatLockdown = combat
    local can = C_QuestLog.CanAbandonQuest
    C_QuestLog.CanAbandonQuest = function() return false end
    T.deq(ns.Clicks.MenuKeys(q), { "priority", "fold", "map", "details", "wowhead", "untrack" }, "no row when the game says no")
    StaticPopupDialogs.DAYLIGHTUI_ABANDON_QUEST.OnAccept(nil, stub.popup.data)
    T.deq(QW.Calls("abandon"), {}, "gone meanwhile: nothing happens")
    C_QuestLog.CanAbandonQuest = can
    C_QuestLog.GetAbandonQuestItems, C_Item.GetItemNameByID = itemsWas, nameWas
end)

-- The card's heights come from the tracker's ruler (Tracker.Measure, the
-- Quests font): its texts wear the same font, or a font of its own makes
-- lines overlap.
T.test("quests details: the card's text wears the tracker's font, the one it's measured in", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "Westfall Stew", { text = "Salma needs stew." }) } })
    DaylightUI:Set("Quests", "media.font", "bangers")
    stub.RunTimers()
    ns.Clicks.Do("details", Tr.shown[3].quest)
    stub.RunTimers()
    local Style = DaylightUI.Style
    for _, fs in ipairs(ns.Details.card.texts) do
        if fs:IsShown() then T.eq(fs:GetFont(), Style.FONTS.bangers.file, fs:GetText()) end
    end
end)

-- The game's chat link insert (ChatFrameUtil.InsertLink) returns true when a
-- chat box is open. Calling ChatFrame_OpenChat from addon code would taint
-- the edit box and break whisper replies in instances.
local function linkWorld(open)
    local inserted = {}
    _G.GetQuestLink = function(id) return "|Hquest:" .. id .. "|h[Q" .. id .. "]|h" end
    _G.ChatFrameUtil = { InsertLink = function(text)
        if not text then return false end
        if open then inserted[#inserted + 1] = text; return true end
        return false
    end }
    _G.ChatFrame_OpenChat = function(text) inserted.opened = text end
    return inserted
end

T.test("quests clicks: Link in chat puts the link in the open chat box, else says to open one", function()
    local Tr, ns = tracker({ quests = { STEW } })
    local q = Tr.shown[3].quest
    local got = linkWorld(true)
    ns.Clicks.Do("link", q)
    T.deq(got, { "|Hquest:1|h[Q1]|h" }, "from a menu row: no Shift needed")
    got = linkWorld(false)
    ns.Clicks.Do("link", q)
    T.isnil(got.opened, "never opens the chat box from our code")
    T.deq(QW.Calls("error"), { ns.Clicks.LINK_NO_CHAT })
    -- Chat open, a Shift-click on the row links it (the game's CHATLINK).
    got = linkWorld(true)
    _G.IsModifiedClick = function(k) return k == "CHATLINK" end
    click(Tr, "quest:1")
    T.deq(got, { "|Hquest:1|h[Q1]|h" })
    T.deq(QW.Calls("untrack"), {}, "linked, not untracked")
    _G.IsModifiedClick = function() return false end
    _G.ChatFrameUtil, _G.GetQuestLink, _G.ChatFrame_OpenChat = nil, nil, nil
end)

T.test("quests clicks: Quest details opens our own card, never the game's popup", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "Westfall Stew", { text = "Salma needs stew.", xp = 450, choices = 2,
        objs = { { text = "Okra: 2/3", have = 2, need = 3 } },
        rewards = { { name = "Stew Pot", icon = 1234, count = 2 } } }) } })
    local q = Tr.shown[3].quest
    ns.Clicks.Do("details", q)
    T.deq(QW.Calls("popup"), {}, "the game's quest popup taints the quest map")
    local D = ns.Details
    T.truthy(D.card:IsShown())
    local texts = {}
    for _, fs in ipairs(D.card.texts) do if fs:IsShown() then texts[#texts + 1] = fs:GetText() end end
    local all = table.concat(texts, "\n")
    T.truthy(all:find("Westfall Stew", 1, true), "the title")
    T.truthy(all:find("Salma needs stew.", 1, true), "the quest's own text")
    T.truthy(all:find("Okra 2/3", 1, true), "the objectives")
    T.truthy(all:find("450 XP", 1, true), "experience")
    T.truthy(all:find("Stew Pot x2", 1, true), "items it gives")
    T.truthy(all:find("choice of 2", 1, true), "a choice counted")
    T.truthy(D.card:GetHeight() > 60, "as tall as what it holds")
    local _, rel = D.card:GetPoint(1)
    T.eq(rel, Tr.view, "beside the list")
    -- Again on the same quest: closes. Works in combat too (our own frame).
    stub.EnterCombat()
    ns.Clicks.Do("details", q)
    T.falsy(DaylightUI.Motion.Shown(D.card), "closed")
    ns.Clicks.Do("details", q)
    T.truthy(DaylightUI.Motion.Shown(D.card), "opens in combat")
    stub.LeaveCombat()
    -- The quest leaves the log: its card goes.
    stub.FireEvent("QUEST_REMOVED", 1)
    T.falsy(DaylightUI.Motion.Shown(D.card))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests clicks: on a controller the details card's X makes it your priority and Y opens its options, as the game's quest log popup", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "Westfall Stew") } })
    local q = Tr.shown[3].quest
    ns.Clicks.Do("details", q)
    local card = ns.Details.card
    local function entry(key) for _, e in ipairs(card.padKeys) do if e.key == key then return e end end end
    local focused, was = nil, _G.C_SuperTrack
    _G.C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end,
                        SetSuperTrackedQuestID = function(id) focused = id end }
    entry("X").run()
    T.eq(focused, 1, "your priority")
    entry("Y").run()
    T.eq(DaylightUI.Widgets.menuOwner, card, "its options, under the card")
    DaylightUI.Widgets.CloseMenu()
    T.eq(card.padSelect(), false, "A does nothing on it")
    _G.C_SuperTrack = was
end)

T.test("quests clicks: right-click opens our drop-down", function()
    local Tr = tracker({ quests = { STEW } })
    click(Tr, "quest:1", "RightButton")
    T.eq(DaylightUI.Widgets.menuOwner, Tr.frames["quest:1"])
end)

T.test("quests clicks: a header click folds its section", function()
    local Tr, ns, settle = tracker({ quests = { STEW } })
    click(Tr, "section:quests")
    settle()
    T.isnil(Tr.frames["quest:1"])
end)

T.test("quests clicks: a zone name click folds its quests, again opens them", function()
    local Tr, ns, settle = tracker({ quests = { STEW } })
    click(Tr, "zone:Westfall")
    settle()
    T.isnil(Tr.frames["quest:1"])
    T.eq(DaylightUI.DB.Character().questFolds["zone:Westfall"], true)
    T.eq(Tr.frames["zone:Westfall"].chevron:IsShown(), true, "a folded zone shows its arrow")
    click(Tr, "zone:Westfall")
    settle()
    T.truthy(Tr.frames["quest:1"])
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests tracker: an open zone's arrow starts hidden, no blink at login", function()
    local Tr = tracker({ quests = { STEW } })
    local c = Tr.frames["zone:Westfall"].chevron
    T.eq(c:IsShown(), false, "hidden at once, not fading out from 1")
    T.eq(c:GetAlpha(), 0)
end)

T.test("quests tracker: a reused header shows its count, whatever its last use left", function()
    local Tr, ns = tracker({ quests = { STEW } })
    local h = Tr.frames["section:quests"]
    h.countGoal = 0
    h.count:SetAlpha(0)
    ns.Rows.Free(h)
    local again = ns.Rows.Get("header", UIParent)
    T.eq(again, h, "the same frame from the pool")
    T.isnil(again.countGoal)
    T.eq(again.count:GetAlpha(), 1, "its count shows")
end)

T.test("quests clicks: the tooltip lists objectives and the hint", function()
    local Tr, ns = tracker({ quests = { STEW } })
    local f = Tr.frames["quest:1"]
    f:GetScript("OnEnter")(f)
    local text = table.concat(GameTooltip.lines, "\n")
    T.truthy(text:find("Westfall Stew", 1, true))
    T.truthy(text:find("Goretusk Snout | 3/6", 1, true))
    for _, h in ipairs(ns.Clicks.HINTS) do
        local found
        for _, l in ipairs(GameTooltip.lines) do if l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == h then found = true end end
        T.truthy(found, "each click hint on its own line: " .. h)
    end
end)

T.test("quests clicks: rowTips off, a quest under the mouse shows no tooltip but still lights", function()
    local Tr = tracker({ quests = { STEW } })
    local f = Tr.frames["quest:1"]
    DaylightUI:Set("Quests", "rowTips", false)
    GameTooltip:Hide()
    f:GetScript("OnEnter")(f)
    T.eq(GameTooltip:IsShown(), false, "no tooltip")
    T.truthy(f:GetScript("OnUpdate"), "the row still follows the mouse")
    f:GetScript("OnLeave")(f)
    DaylightUI:Set("Quests", "rowTips", true)
    f:GetScript("OnEnter")(f)
    T.eq(GameTooltip:IsShown(), true, "on again: the tooltip")
    f:GetScript("OnLeave")(f)
end)

T.test("quests clicks: the tooltip's words are calm, a hint's click wears the accent; progress reads amber, done reads green", function()
    local done = QW.quest(2, "Done Deal", { objs = { { text = "6/6 Thing", have = 6, need = 6, done = true } } })
    local Tr, ns = tracker({ quests = { STEW, done } })
    DaylightUI:Set("general", "accent", "custom")
    DaylightUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    local function hover(key)
        local f = Tr.frames[key]
        f:GetScript("OnEnter")(f)
        local by = {}
        for i, l in ipairs(GameTooltip.lines) do by[(l:match("^(.-) | ") or l)] = GameTooltip.colors[i] end
        return by
    end
    local Tips = DaylightUI.Tips
    local by = hover("quest:1")
    local snout = by["Goretusk Snout"]
    T.rgb(snout.lc, Tips.TEXT, "the objective's words calm, so rows read apart")
    T.truthy(snout.rc[1] > snout.rc[3] and snout.rc[2] > snout.rc[3], "3/6 reads amber")
    T.truthy(snout.rc[1] > Tips.GOOD[1], "not green yet")
    local key, what = ns.Clicks.HINTS[2]:match("^(.-:)(%s.*)$")
    local hint
    for t, c in pairs(by) do if t:find(key, 1, true) and t:find(what, 1, true) then hint = { t, c } end end
    T.truthy(hint and hint[1]:find("|c", 1, true), "a hint's click is colored apart")
    T.rgb(hint[2].lc, Tips.TEXT, "what it does: a calm label")
    by = hover("quest:2")
    T.rgb(by["Thing"].rc, Tips.GOOD, "6/6 reads green")
end)

T.test("quests clicks: an achievement opens its window; shift-click stops tracking it", function()
    local Tr = tracker({ achievements = { { id = 9, title = "Explore", criteria = { { text = "Mine" } } } } })
    click(Tr, "ach:9")
    T.deq(QW.Calls("achievement"), { 9 })
    QW.state.shift = true
    click(Tr, "ach:9")
    T.deq(QW.Calls("stopAchievement"), { 9 })
end)

local function many(n)
    local list = {}
    for i = 1, n do list[i] = QW.quest(i, "Quest " .. i, { objs = { { text = "0/5 Thing", have = 0, need = 5 } } }) end
    return list
end

-- The wheel's glide, played to its end.
local function glide()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 30 do if d then stub.RunOnUpdate(d, 1 / 60) end end
end

-- Scrolled down, a list that gets shorter pulls the scroll back: rows the
-- top edge had faded out come back, and nothing jumps on the way.
T.test("quests scroll: rows scrolled away come back when untracking shortens the list", function()
    local Tr, ns, settle = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    ns.Scroll.To(1000)
    ns.Tracker.RefreshEdges()
    T.eq(Tr.frames["quest:1"]:GetAlpha(), 0, "above the view: faded out")
    T.eq(Tr.frames["section:quests"]:GetAlpha(), 1, "the header stays, pinned at the top")
    for i = 4, 20 do
        QW.state.quests[i].watched = false
        stub.FireEvent("QUEST_WATCH_LIST_CHANGED", i, false)
    end
    settle()
    T.eq(ns.Scroll.offset, 0)
    T.eq(Tr.frames["section:quests"]:GetAlpha(), 1, "the header is back")
    T.eq(Tr.frames["quest:1"]:GetAlpha(), 1, "and the first quest")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests scroll: untracking at the bottom of the list: the rows under it stay put on screen", function()
    local Tr, ns = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    ns.Scroll.To(1000)
    local last = Tr.frames["quest:20"]
    local A = ns.Animate
    local onScreen = A.State(last).y - ns.Scroll.offset
    QW.state.quests[19].watched = false
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED", 19, false); stub.RunTimers()
    for _ = 1, 40 do
        stub.RunOnUpdate(A.driver, 1 / 60)
        T.truthy(math.abs(A.State(last).y - ns.Scroll.offset - onScreen) < 0.5, "no jump")
    end
    T.eq(ns.Scroll.offset, Tr.contentHeight - 200, "at the new bottom")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quests scroll: past the height limit the view stops and the wheel scrolls", function()
    local Tr, ns = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    T.eq(Tr.view:GetHeight(), 200)
    ns.Scroll.Wheel(-1); glide()
    T.eq(ns.Scroll.offset, 40)
    ns.Scroll.Wheel(100); glide()
    T.eq(ns.Scroll.offset, 0, "not past the top")
end)

T.test("quests scroll: the wheel glides there, and quick notches add up", function()
    local Tr, ns = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    ns.Scroll.Wheel(-1)
    T.eq(ns.Scroll.offset, 0, "no jump: it starts where it was")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 60)
    local part = ns.Scroll.offset
    T.truthy(part > 0 and part < 40, "part way: " .. tostring(part))
    T.eq(Tr.view:GetVerticalScroll(), part, "the view with it")
    ns.Scroll.Wheel(-1)   -- a second notch mid-glide
    glide()
    T.eq(ns.Scroll.offset, 80, "both notches count")
end)

T.test("quests scroll: motion off, the wheel goes straight there", function()
    local _, ns = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    DaylightUI:Set("general", "motion", false)
    stub.RunTimers()
    ns.Scroll.Wheel(-1)
    T.eq(ns.Scroll.offset, 40)
end)

T.test("quests scroll: a glide re-anchors no row, only their edges soften", function()
    local Tr, ns = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    local moved = 0
    local header = Tr.frames["section:quests"]
    for _, f in pairs(Tr.frames) do
        if f ~= header then
            local clear = f.ClearAllPoints
            f.ClearAllPoints = function(self) moved = moved + 1; return clear(self) end
        end
    end
    local first = Tr.frames["quest:1"]
    T.eq(first:GetAlpha(), 1, "at the top, nothing above")
    ns.Scroll.Wheel(-2); glide()
    T.eq(moved, 0, "a scroll moves the view, never the rows in it (only the pinned header rides along)")
    T.truthy(first:GetAlpha() < 1, "the row sliding under the header softens")
    T.eq(header:GetAlpha(), 1, "the header stays")
    local _, _, _, _, y = header:GetPoint(1)
    T.near(-y, ns.Scroll.offset, 1e-6, "at the view's top")
    T.truthy(header:GetFrameLevel() > first:GetFrameLevel(), "over the rows")
end)

T.test("quests scroll: a glide stops where it is when a fight starts over item buttons", function()
    local quests = many(20)
    quests[1].item = ITEM
    local _, ns = tracker({ quests = quests })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    ns.Scroll.Wheel(-1)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 60)
    local at = ns.Scroll.offset
    stub.EnterCombat()
    glide()
    T.eq(ns.Scroll.offset, at, "nothing moves under the buttons")
    ns.Scroll.Wheel(-1); glide()
    T.eq(ns.Scroll.offset, at, "the wheel waits too")
    stub.LeaveCombat(); stub.RunTimers()
    ns.Scroll.Wheel(-1); glide()
    T.eq(ns.Scroll.offset, at + 40, "from where it stopped, one notch: none saved up")
end)

T.test("quests scroll: the bar is our one scroll bar (W.Scroll), and a drag scrolls", function()
    local Tr, ns = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    local bar = ns.Scroll.bar
    T.truthy(bar and bar.thumb and bar.track, "W.Scroll's thumb and track")
    T.eq(bar:GetWidth(), DaylightUI.Widgets.SCROLL.width)
    bar.To(80)
    T.eq(ns.Scroll.offset, 80, "the bar's drag moves the list")
    T.eq(Tr.view:GetVerticalScroll(), 80)
end)

T.test("quests scroll: rows soften towards an edge with more beyond it", function()
    local _, ns = load()
    local S = ns.Scroll
    T.eq(S.EdgeAlpha(0, 30, 0, 200, false, true), 1)
    T.eq(S.EdgeAlpha(188, 30, 0, 200, false, true), 0.5, "12 px from the bottom edge")
    T.eq(S.EdgeAlpha(188, 30, 0, 200, false, false), 1, "nothing below: no softening")
    T.eq(S.EdgeAlpha(0, 30, 18, 200, true, false), 0.5, "12 px left above the top edge")
end)

T.test("quests scroll: no wheel in combat while item buttons show", function()
    local quests = many(20)
    quests[1].item = ITEM
    local Tr, ns = tracker({ quests = quests })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    stub.EnterCombat()
    ns.Scroll.Wheel(-1); glide()
    T.eq(ns.Scroll.offset, 0)
end)

T.test("quests controls: they show while the mouse is over the list", function()
    local Tr, ns = tracker({ quests = { STEW } })
    T.eq(Tr.controls:IsShown(), false)
    function Tr.view:IsMouseOver() return true end
    Tr.Hovered()
    T.eq(Tr.controls:IsShown(), true)
end)

T.test("quests controls: stay on the pinned header while the list scrolls", function()
    local Tr, ns = tracker({ quests = many(20) })
    DaylightUI:Set("Quests", "maxHeight", 200)
    stub.RunTimers()
    function Tr.view:IsMouseOver() return true end
    Tr.Hovered()
    local function anchoredTo() return select(2, Tr.controls:GetPoint(1)) end
    T.eq(anchoredTo(), Tr.frames["section:quests"].chevron, "on the header's line at the top")
    ns.Scroll.Wheel(-2); glide()
    T.truthy(ns.Scroll.offset > 0)
    T.eq(anchoredTo(), Tr.frames["section:quests"].chevron, "still on the header, pinned at the top: never over the rows")
    ns.Scroll.Wheel(100); glide()
    T.eq(anchoredTo(), Tr.frames["section:quests"].chevron, "back on the header at the top")
end)

T.test("quests controls: This zone, and no Fold button (the headers fold)", function()
    local Tr = tracker({ quests = { STEW } })
    Tr.controls.zone:GetScript("OnClick")(Tr.controls.zone)
    T.eq(DaylightUI:GetModule("Quests").db.filter, "zone")
    T.isnil(Tr.controls.fold)
end)

T.test("quests controls: the lit button follows a click while they're on show", function()
    local Tr = tracker({ quests = { STEW } })
    function Tr.view:IsMouseOver() return true end
    Tr.Hovered()
    local c = Tr.controls
    T.truthy(c.all.active, "All lit at first")
    c.zone:GetScript("OnClick")(c.zone)
    T.truthy(c.zone.active, "This zone lit after its click")
    T.falsy(c.all.active, "All dark again")
    c.all:GetScript("OnClick")(c.all)
    T.truthy(c.all.active, "All lit after its click")
end)

T.test("quests timers: count down every second and turn red in the last minute", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "Escort", { timer = 61 }) } })
    local label = Tr.frames["quest:1"].lines.timer.label
    T.eq(label:GetText(), "1:01 left")
    stub.Advance(2)
    Tr.TickTimers()
    T.eq(label:GetText(), "0:59 left")
    T.rgb(label.__textColor, DaylightUI:GetModule("Quests").db.colors.timerUrgent)
end)

T.test("quests timers: a ready quest still shows its time, under the hand-in line", function()
    local Tr = tracker({ quests = { QW.quest(1, "Antidote", { timer = 300, complete = true }) } })
    local lines = Tr.frames["quest:1"].lines
    T.truthy(lines.turnin, "hand-in line")
    T.eq(lines.timer.label:GetText(), "5:00 left")
end)

T.test("quests timers: a failed quest's time is gone", function()
    local Tr = tracker({ quests = { QW.quest(1, "Antidote", { timer = 300, failed = true }) } })
    T.isnil(Tr.frames["quest:1"].lines.timer)
end)

T.test("quests data: a timed quest the timer list leaves out is read the game tracker's way", function()
    local s = snap({ quests = {
        QW.quest(1, "A", { allowed = { 600, 100 } }),
        QW.quest(2, "B", { allowed = { 600, 600 } }),
        QW.quest(3, "C"),
    } })
    local q = s.groups[1].quests
    T.eq(q[1].timer, 500)
    T.isnil(q[2].timer, "used up")
    T.isnil(q[3].timer, "not timed")
end)

T.test("quests options: both pages exist and every setting has a valid default", function()
    load({ quests = { STEW } })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(DaylightUI.Options.GetPage("Quests.tracker"))
    T.truthy(DaylightUI.Options.GetPage("Quests.colors"))
    T.eq(stub.ChatContains("Options ("), false, "no validation complaints")
end)

T.test("quests options: changing a size or color repaints at once", function()
    local Tr = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "sizes.title", 15)
    stub.RunTimers()
    T.eq(Tr.frames["quest:1"].lines.title.label.__font[2] >= 15, true)
    DaylightUI:Set("Quests", "colors.objective", { 0.1, 0.2, 0.3 })
    stub.RunTimers()
    T.rgb(Tr.frames["quest:1"].lines["obj:1"].label.__textColor, { 0.1, 0.2, 0.3 })
end)

T.test("quests options: Track new quests reads and writes the game's setting", function()
    local cvar = "1"
    load({ quests = {} }, { before = function()
        _G.GetCVarBool = function() return cvar == "1" end
        _G.SetCVar = function(_, v) cvar = v end
    end })
    local item
    for _, g in ipairs(DaylightUI.Options.GetPage("Quests.tracker").groups) do
        for _, it in ipairs(g.items) do if it.label == "Track new quests automatically" then item = it end end
    end
    T.eq(item.get(), true)
    item.set(false)
    T.eq(cvar, "0")
end)

T.test("quests setup guide: the module is offered and the clashes listed", function()
    load()
    local P = DaylightUI.InstallerPages or DaylightUI.Installer.Pages
    local found, clashes = false, 0
    for _, m in ipairs(P.MODULES) do if m.addon == "DaylightUI_Quests" then found = true end end
    for _, c in ipairs(P.CLASHES) do if c.module == "Quests" then clashes = clashes + 1 end end
    T.eq(found, true); T.eq(clashes, 2)
end)

-- Edge cases

T.test("quests fade: fades with the mouse elsewhere; the list and item buttons bring it back", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }) } })
    local F = DaylightUI.Fade
    DaylightUI:Set("Quests", "fade.mode", "always")
    DaylightUI:Set("Quests", "fade.alpha", 0.3)
    DaylightUI:Set("Quests", "fade.delay", 0)
    stub.Advance(10)           -- past the preview a fade setting's change shows
    -- The cursor is somewhere on the screen: a frame as big as the screen is under it.
    function ns.Items.holder:IsMouseOver() return true end
    ns.Items.holder:Show()     -- as in game
    local function settle() F.Step(); for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end end
    settle()
    T.eq(Tr.holder:GetAlpha(), 0.3, "faded")
    T.eq(ns.Items.holder:GetAlpha(), 0.3, "the item column with it")
    function Tr.view:IsMouseOver() return true end
    settle()
    T.eq(Tr.holder:GetAlpha(), 1, "the list under the mouse")
    function Tr.view:IsMouseOver() return false end
    stub.Advance(1); settle()
    T.eq(Tr.holder:GetAlpha(), 0.3)
    ns.Items.buttons[1].IsMouseOver = function() return true end
    settle()
    T.eq(Tr.holder:GetAlpha(), 1, "an item button under the mouse")
end)

T.test("quests controls: they sit above the rows, so a click reaches them", function()
    local Tr = tracker({ quests = { STEW } })
    -- In game a child is one level over its parent: rows are content + 1.
    T.truthy(Tr.controls:GetFrameLevel() > (Tr.content:GetFrameLevel() or 0) + 3, "over the rows and their lines")
end)

T.test("quests items: the buttons follow when the list moves without a re-lay", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }) } })
    local follows, orig = 0, ns.Items.Follow
    ns.Items.Follow = function(...) follows = follows + 1; return orig(...) end
    local left = 500
    function Tr.view:GetLeft() return left end
    function Tr.view:GetTop() return 700 end
    stub.RunTickers()
    T.eq(follows, 1, "first look")
    stub.RunTickers()
    T.eq(follows, 1, "not moved: nothing to do")
    left = 400      -- dragged in unlock mode, or the panel above changed size
    stub.RunTickers()
    T.eq(follows, 2)
    stub.EnterCombat(); left = 300
    stub.RunTickers()
    T.eq(follows, 2, "not in combat")
    stub.LeaveCombat()
    stub.RunTickers()
    T.eq(follows, 3, "after the fight")
end)

T.test("quests: /dui taint leaves out the three functions emptied on purpose", function()
    local _, ns = load()
    for _, name in ipairs(ns.Blizzard.EMPTIED) do stub.Mark(ObjectiveTrackerManager, name, "DaylightUI_Quests") end
    stub.Mark(ObjectiveTrackerManager, "UpdateAll", "DaylightUI_Quests")
    local out = DaylightUI.Taint.Scan()
    T.eq(#out, 1, table.concat(out, ", "))
    T.truthy(out[1]:find("UpdateAll", 1, true), "anything else of ours still shows")
end)

-- Redundant work: each of these ran every frame or every refresh for nothing.

T.test("quests data: the log is read once per snapshot, not again per quest", function()
    local _, ns = load({ quests = { STEW, QW.quest(2, "B"), QW.quest(3, "C", { zone = "Elwynn Forest" }) } })
    local QL, counts = C_QuestLog, { info = 0, index = 0, focus = 0 }
    local info, index, focus = QL.GetInfo, QL.GetLogIndexForQuestID, C_SuperTrack.GetSuperTrackedQuestID
    QL.GetInfo = function(...) counts.info = counts.info + 1; return info(...) end
    QL.GetLogIndexForQuestID = function(...) counts.index = counts.index + 1; return index(...) end
    C_SuperTrack.GetSuperTrackedQuestID = function(...) counts.focus = counts.focus + 1; return focus(...) end
    QW.state.focus = 3
    local s = ns.Data.Snapshot()
    T.eq(counts.info, 5, "each log entry once (2 headers, 3 quests)")
    T.eq(counts.index, 0, "every watched quest was found in that pass")
    T.eq(counts.focus, 1, "the priority quest asked once")
    T.eq(s.groups[1].quests[1].logIndex, 2)
    T.eq(s.groups[2].quests[1].logIndex, 5)
    T.eq(s.groups[2].quests[1].focus, true, "and still marked")
    T.eq(s.groups[1].quests[1].focus, false)
    QL.GetInfo, QL.GetLogIndexForQuestID, C_SuperTrack.GetSuperTrackedQuestID = info, index, focus
end)

T.test("quests motion: a moving list makes no garbage each frame", function()
    local A = animator()
    A.place = function() end
    local f = CreateFrame("Frame")
    A.Jump(f, 0)
    A.Leave(f, function() end)
    A.Glide(f, 1000)
    for _, c in pairs(A.State(f).ch) do c.dur = 1e9 end     -- keeps moving
    if jit then jit.off() end   -- the compiler's own allocations vary run to run (test_chat)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 2000 do A.Tick(1 / 60) end
    local made = collectgarbage("count") - before
    collectgarbage("restart")
    if jit then jit.on() end
    T.truthy(made < 8, "made " .. made .. " KB")
    local done = 0
    A.Leave(f, function() done = done + 1 end)
    for _, c in pairs(A.State(f).ch) do c.dur = 0.1 end
    for _ = 1, 10 do A.Tick(1 / 60) end
    T.eq(done, 1, "a finished slide still says so, once")
end)

T.test("quests items: following the list leaves a button that's already in place alone", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { item = ITEM }) } })
    local btn, f = ns.Items.buttons[1], Tr.frames["quest:1"]
    function Tr.view:GetLeft() return 600 end
    function Tr.view:GetRight() return 826 end
    function Tr.view:GetTop() return 800 end
    function Tr.view:GetBottom() return 100 end
    local top = 500
    function f:GetTop() return top end
    local moves, real = 0, btn.ClearAllPoints
    btn.ClearAllPoints = function(self) moves = moves + 1; return real(self) end
    ns.Items.Follow()
    T.eq(moves, 1, "put next to its quest")
    T.eq(select(4, btn:GetPoint(1)), 600 - ns.Items.GAP)
    for _ = 1, 30 do ns.Items.Follow() end      -- other rows gliding, every frame
    T.eq(moves, 1, "its quest didn't move: left alone")
    top = 480
    ns.Items.Follow()
    T.eq(moves, 2, "its quest moved: it follows")
    T.eq(select(5, btn:GetPoint(1)), 481)
    f:SetAlpha(0.5)                             -- the list's edge softening
    ns.Items.Follow()
    T.eq(moves, 3)
    T.eq(btn:GetAlpha(), 0.5)
    btn.ClearAllPoints = real
end)

T.test("quests items: cooldown and range are set only when they change; no tick without buttons", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A") } })
    local refreshes, orig = 0, ns.Items.Refresh
    ns.Items.Refresh = function(...) refreshes = refreshes + 1; return orig(...) end
    stub.RunTickers()
    T.eq(refreshes, 0, "no item quest: nothing to look at every 0.2 s")
    ns.Items.Refresh = orig
    QW.state.quests[1].item = ITEM
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    local btn = ns.Items.buttons[1]
    local sets, tints = 0, 0
    local setCd, tint = btn.cooldown.SetCooldown, btn.icon.SetVertexColor
    btn.cooldown.SetCooldown = function(...) sets = sets + 1; return setCd(...) end
    btn.icon.SetVertexColor = function(...) tints = tints + 1; return tint(...) end
    local cd = { 100, 30 }
    _G.GetQuestLogSpecialItemCooldown = function() return cd[1], cd[2], 1 end
    for _ = 1, 5 do stub.RunTickers() end
    T.eq(sets, 1, "the cooldown once")
    T.eq(tints, 0, "in range all along: the tint as it was")
    cd = { 200, 30 }
    QW.state.quests[1].itemRange = 0
    for _ = 1, 5 do stub.RunTickers() end
    T.eq(sets, 2, "a new cooldown: once more")
    T.eq(tints, 1)
    T.rgb(btn.icon.__vertex, ns.Items.OUT_OF_RANGE)
    QW.state.quests[1].item = nil
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.isnil(ns.Items.ticker, "the last button gone: the tick stops")
end)

T.test("quests tracker: a re-render measures only text it hasn't measured before", function()
    local Tr = tracker({ quests = { STEW, QW.quest(2, "Red Leather Bandanas") } })
    local Style = DaylightUI.Style
    local ruler, n, orig = nil, 0, Style.SetTextSize
    Style.SetTextSize = function(fs, size)
        if fs:GetParent() == UIParent then ruler = fs; n = n + 1 end
        return orig(fs, size)
    end
    Tr.Measure("find the ruler", 12, 100)
    ruler.GetStringHeight = function() return 15 end
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    n = 0
    for _ = 1, 3 do stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers() end
    T.eq(n, 0, "the same texts: nothing measured again")
    QW.state.quests[2].title = "Red Leather Bandanas, again"
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(n, 1, "only the new title")
    DaylightUI:Set("Quests", "sizes.title", 15)
    stub.RunTimers()
    T.truthy(n > 1, "a new size: measured again")
    Style.SetTextSize = orig
end)

T.test("quests: warm text defaults, a player's own color kept", function()
    local DUI, ns = load()
    local INK = DUI.Style.INK
    T.deq(ns.DEFAULTS.colors.zone, INK.LABEL)
    T.deq(ns.DEFAULTS.colors.objective, INK.TEXT)
    T.deq(ns.DEFAULTS.colors.count, INK.VALUE)
    T.deq(ns.DEFAULTS.colors.done, { 0.52, 0.76, 0.52 })
    DUI:Set("Quests", "colors.done", { 0.3, 0.3, 0.9 })
    T.deq(DUI:Get("Quests", "colors.done"), { 0.3, 0.3, 0.9 }, "a saved custom color stays")
end)

T.test("quests: the details card's heads pop, its level in the difficulty color", function()
    local DUI, ns = load({ quests = { STEW } })
    local q = { id = 1, title = "Stew", level = 12, zone = "Elwynn", diff = { 0.25, 0.75, 0.25 }, objs = { { text = "Meat", kind = "count", have = 2, need = 5, done = false } } }
    local lines = ns.Details.Lines(q)
    T.rgb(lines[#lines - 1].color, ns.Details.TEXT)
    local head
    for _, l in ipairs(lines) do if l.text == ns.Details.HEAD.objectives then head = l end end
    T.rgb(head.color, { DUI.Style.Accent() })
    T.truthy(lines[2].text:find("|cff", 1, true), "the level is colored")
end)

-- ---------------------------------------------------------------------
-- Questie loaded: one question, which tracker (Choice.lua), and the
-- `tracker` switch it writes
-- ---------------------------------------------------------------------

local function withQuestie(opts)
    opts = opts or {}
    local saved = opts.saved
    local profile = opts.profile or { trackerEnabled = true, enableMapIcons = true, enableMiniMapIcons = true }
    local _, ns = load({ quests = {} }, { skins = true, before = function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { API = { isReady = true }, db = { profile = profile } }
        _G.DaylightUIDB = saved or { characters = {} }
        if opts.guide ~= false then
            local key = "Tester-" .. tostring(GetRealmName and GetRealmName() or "")   -- the fake game's player
            _G.DaylightUIDB.characters = _G.DaylightUIDB.characters or {}
            local c = _G.DaylightUIDB.characters[key]
            if type(c) ~= "table" then c = {}; _G.DaylightUIDB.characters[key] = c end
            c.install = c.install or "installed"
        end
    end })
    stub.RunTimers()
    return ns, profile
end

local function choiceShown()
    local f = _G.DaylightUIQuestieChoice
    return f ~= nil and DaylightUI.Win.IsOpen(f)
end

T.test("choice: asked once with Questie", function()
    local ns = withQuestie()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(choiceShown(), "asked at login")
    ns.Choice.Pick("ours")
    T.eq(DaylightUI.DB.Root().questieAsked, true, "marked asked for the account")
    stub.Advance(1)
    T.falsy(choiceShown(), "closed")
    ns.Choice.Maybe()
    T.falsy(choiceShown(), "never asked again")
    T.eq(DaylightUI:Get("Quests", "tracker"), true, "ours kept")
    _G.Questie = nil
end)

T.test("choice: not before the setup guide is done", function()
    withQuestie({ guide = false })
    T.falsy(choiceShown())
    _G.Questie = nil
end)

T.test("choice: never in a fight", function()
    local ns = withQuestie()
    ns.Choice.Pick("ours")
    DaylightUI.DB.Root().questieAsked = nil
    stub.Advance(1)
    stub.EnterCombat()
    ns.Choice.Maybe()
    T.falsy(choiceShown(), "not in a fight")
    stub.LeaveCombat(); stub.RunTimers()
    T.truthy(choiceShown(), "asked once the fight ends")
    _G.Questie = nil
end)

T.test("choice: Questie's tracker", function()
    local ns, profile = withQuestie()
    T.eq(profile.trackerEnabled, false, "ours on: Questie's stepped aside")
    ns.Choice.Pick("questie")
    stub.RunTimers()
    for _ = 1, 30 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 30) end   -- it fades out, then goes
    T.eq(DaylightUI:Get("Quests", "tracker"), false)
    T.falsy(DaylightUIQuestTracker:IsShown(), "our tracker gone")
    T.eq(profile.trackerEnabled, true, "Questie's tracker back")
    T.eq(DaylightUI:Get("Quests", "journal"), true, "the journal stays")
    T.eq(ns.Tracker.Wanted(), false)
    _G.Questie = nil
end)

T.test("choice: a profile switch carries the pick", function()
    local ns, profile = withQuestie()
    ns.Choice.Pick("ours")
    local saved = _G.DaylightUIDB
    local key = DaylightUI.DB.CharKey()
    saved.profileData.Theirs = { modules = { Quests = { tracker = false } } }
    saved.characters[key].profile = "Theirs"
    withQuestie({ saved = saved, profile = profile })
    T.eq(DaylightUI.DB.ActiveName(), "Theirs")
    T.eq(profile.trackerEnabled, true, "that profile picked Questie's")
    T.falsy(_G.DaylightUIQuestTracker and DaylightUIQuestTracker:IsShown(), "ours not built")
    saved.characters[key].profile = "Default"
    withQuestie({ saved = saved, profile = profile })
    T.eq(profile.trackerEnabled, false, "back on ours: Questie's steps aside again")
    _G.Questie = nil
end)

-- Questie's tracker picked: ours is never built, yet the journal's quest
-- tooltip reads the tracker's look (error seen in game: Look.lua "index
-- local 'db' (a nil value)" from Journal.Tip).
T.test("choice: Questie's tracker, the journal's tooltip still works", function()
    local ns = withQuestie()
    local saved = _G.DaylightUIDB
    local key = DaylightUI.DB.CharKey()
    saved.profileData.Theirs = { modules = { Quests = { tracker = false } } }
    saved.characters[key].profile = "Theirs"
    ns = withQuestie({ saved = saved })
    T.falsy(_G.DaylightUIQuestTracker and DaylightUIQuestTracker:IsShown(), "ours not built")
    local q = { id = 9, title = "Lost Pages", level = 5, zone = "Elwynn Forest", objs = {} }
    local ok, err = pcall(ns.Clicks.QuestTip, q, ns.Clicks.JOURNAL_HINTS)
    T.truthy(ok, tostring(err))
    _G.Questie = nil
end)

T.test("choice: without Questie no switch", function()
    local _, ns = load({ quests = {} })
    stub.RunTimers()
    T.falsy(choiceShown(), "nothing asked")
    T.eq(ns.Tracker.Wanted(), true)
    local item
    for _, page in ipairs(ns.OPTIONS.pages) do
        for _, g in ipairs(page.groups or {}) do
            for _, it in ipairs(g.items or {}) do if it.key == "tracker" then item = it end end
        end
    end
    T.truthy(item, "the switch is in the options")
    T.truthy(item.hidden and item.hidden(), "hidden without Questie")
    -- Even set off (a profile from a PC with Questie), ours still draws.
    DaylightUI:Set("Quests", "tracker", false)
    T.eq(ns.Tracker.Wanted(), true, "no Questie: ours is the only tracker")
end)

-- ---------------------------------------------------------------------
-- The right-click menu (Clicks.MenuKeys / Do): Questie's menu in ours
-- ---------------------------------------------------------------------

local TWO = QW.quest(7, "Two Things", { objs = {
    { text = "Wolf slain: 1/5", have = 1, need = 5, type = "monster" },
    { text = "Bear pelt: 0/3", have = 0, need = 3, type = "item" } } })

local function menuQuest(spec)
    local Tr, ns = tracker(spec or { quests = { TWO } })
    local f = Tr.frames["quest:" .. (spec and spec.quests[1].id or 7)]
    return f.block.quest, ns
end

T.test("menu: the spec's order", function()
    local q, ns = menuQuest()
    _G.IsInGroup = function() return true end
    T.deq(ns.Clicks.MenuKeys(q), { "priority", "fold", "map", "details", "share", "wowhead", "untrack", "abandon" })
    _G.IsInGroup = nil
end)

T.test("menu: a ready quest offers its hand-in", function()
    local ready = QW.quest(8, "Done Deal", { complete = true, turnIn = "Ada", objs = { { text = "x", have = 1, need = 1, done = true } } })
    local q, ns = menuQuest({ quests = { ready } })
    ns.Spots.TurnIn = function() return { { map = 52, x = 0.3, y = 0.3 } } end
    local keys = table.concat(ns.Clicks.MenuKeys(q), " ")
    T.truthy(keys:find("turnin", 1, true), keys)
end)

T.test("menu: priority is super-track", function()
    local q, ns = menuQuest()
    ns.Clicks.Do("priority", q)
    T.eq(C_SuperTrack.GetSuperTrackedQuestID(), q.id)
    T.eq(ns.Clicks.MenuText(q).priority, DaylightUI.L["Stop being your priority"], "the label flips")
    ns.Clicks.Do("priority", q)
    T.eq(C_SuperTrack.GetSuperTrackedQuestID(), 0)
end)

T.test("menu: fold keeps the title and the timer", function()
    local timed = QW.quest(9, "In a Hurry", { timer = 300, objs = { { text = "Run: 0/1", have = 0, need = 1 } } })
    local Tr, ns, settle = tracker({ quests = { timed } })
    local q = Tr.frames["quest:9"].block.quest
    ns.Clicks.Do("fold", q)
    settle()
    local kinds = {}
    for _, l in ipairs(Tr.frames["quest:9"].block.lines) do kinds[#kinds + 1] = l.kind end
    T.eq(table.concat(kinds, " "), "title timer")
    T.eq(ns.Clicks.MenuText(q).fold, DaylightUI.L["Unfold"])
    ns.Clicks.Do("fold", q)
    settle()
    T.truthy(#Tr.frames["quest:9"].block.lines > 2, "unfolded")
end)

T.test("menu: wowhead", function()
    local q, ns = menuQuest()
    local got
    local W = DaylightUI.Widgets
    local was = W.Prompt
    W.Prompt = function(_, initial) got = initial end
    ns.Clicks.Do("wowhead", q)
    W.Prompt = was
    T.eq(got, "https://www.wowhead.com/forever/quest=7")
end)

-- ---------------------------------------------------------------------
-- Clicks you choose (clicks.click/shift/ctrl/alt), a zone's Shift-click,
-- the fold key
-- ---------------------------------------------------------------------

T.test("clicks: defaults keep today's", function()
    local Tr = tracker({ quests = { STEW } })
    click(Tr, "quest:1")
    T.deq(QW.Calls("map"), { 52 }, "a click shows it on the map")
    QW.state.shift = true
    click(Tr, "quest:1")
    QW.state.shift = false
    T.deq(QW.Calls("untrack"), { 1 }, "shift-click stops tracking")
end)

T.test("clicks: ctrl makes it the priority", function()
    local Tr = tracker({ quests = { STEW } })
    QW.state.ctrl = true
    click(Tr, "quest:1")
    QW.state.ctrl = false
    T.eq(C_SuperTrack.GetSuperTrackedQuestID(), 1)
    T.eq(#QW.Calls("map"), 0, "not the map")
end)

T.test("clicks: alt set to fold folds", function()
    local Tr, ns = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "clicks.alt", "fold")
    QW.state.alt = true
    click(Tr, "quest:1")
    QW.state.alt = false
    T.eq(ns.Tracker.Folds()["q1"], true)
end)

T.test("clicks: a plain click set to nothing does nothing", function()
    local Tr = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "clicks.click", "none")
    click(Tr, "quest:1")
    T.eq(#QW.Calls("map"), 0)
end)

T.test("clicks: hints follow the picks", function()
    local _, ns = tracker({ quests = { STEW } })
    local L = DaylightUI.L
    local all = table.concat(ns.Clicks.Hints(), " / ")
    T.truthy(all:find(L["Ctrl-click: %s"]:format(L["make it your priority"]), 1, true), all)
    DaylightUI:Set("Quests", "clicks.click", "details")
    DaylightUI:Set("Quests", "clicks.ctrl", "none")
    all = table.concat(ns.Clicks.Hints(), " / ")
    T.truthy(all:find(L["Click: %s"]:format(L["quest details"]), 1, true), all)
    T.falsy(all:find("Ctrl", 1, true), "a click set to nothing has no hint: " .. all)
end)

T.test("zone: shift-click folds every quest in it, again unfolds", function()
    local Tr, ns, settle = tracker({ quests = { STEW, QW.quest(2, "Red Leather Bandanas") } })
    QW.state.shift = true
    click(Tr, "zone:Westfall")
    QW.state.shift = false
    settle()
    local folds = ns.Tracker.Folds()
    T.eq(folds.q1, true); T.eq(folds.q2, true)
    T.isnil(folds["zone:Westfall"], "the zone itself stays open")
    QW.state.shift = true
    click(Tr, "zone:Westfall")
    QW.state.shift = false
    T.isnil(folds.q1); T.isnil(folds.q2)
end)

T.test("fold key: folds and opens the whole tracker", function()
    local _, ns = tracker({ quests = { STEW } })
    T.truthy(BINDING_NAME_DAYLIGHTUI_QUESTS_FOLD, "named in the key bindings")
    T.truthy(BINDING_HEADER_DAYLIGHTUI_QUESTS, "its own key bindings heading")
    DaylightUI.QuestsFoldAll()
    T.eq(ns.Tracker.Folds().quests, true)
    DaylightUI.QuestsFoldAll()
    T.isnil(ns.Tracker.Folds().quests)
end)

-- ---------------------------------------------------------------------
-- Tracker options (Questie's): every log quest, sorts, fold ready,
-- instances, objective colors, hover dim, grow up, the empty header
-- ---------------------------------------------------------------------

T.test("show all: every log quest without watches", function()
    local Tr, ns = tracker({ quests = { QW.quest(1, "A", { objs = kills(1) }),
        QW.quest(2, "B", { watched = false, objs = kills(1) }), QW.quest(3, "C", { watched = false, objs = kills(1) }) } })
    T.eq(#order(Tr), 1, "tracked only")
    DaylightUI:Set("Quests", "filter", "log")
    stub.RunTimers()
    T.deq(order(Tr), { 1, 2, 3 })
    T.eq(#QW.Calls("track"), 0, "no game watches added")
    for id = 1, 3 do T.eq(ns.Tracker.Shown(id), true, "shown " .. id) end
    DaylightUI:Set("Quests", "filter", "all")
    stub.RunTimers()
    T.eq(ns.Tracker.Shown(2), false)
end)

T.test("show all: a fight holds the order", function()
    local Tr = tracker(THREE)
    DaylightUI:Set("Quests", "filter", "log")
    stub.RunTimers()
    stub.EnterCombat()
    QW.state.quests[2].objs = kills(2)
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.deq(order(Tr), { 1, 2, 3 }, "nothing re-sorts in a fight")
    stub.LeaveCombat(); stub.RunTimers()
    T.deq(order(Tr), { 2, 1, 3 }, "after it")
end)

T.test("sort: by level", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { level = 20 }), QW.quest(2, "B", { level = 10 }), QW.quest(3, "C", { level = 15 }) } })
    DaylightUI:Set("Quests", "sort", "level")
    stub.RunTimers()
    T.deq(order(Tr), { 2, 3, 1 })
end)

T.test("sort: ready first", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { objs = kills(1) }), QW.quest(2, "B", { complete = true }) } })
    DaylightUI:Set("Quests", "sort", "ready")
    stub.RunTimers()
    T.deq(order(Tr), { 2, 1 })
end)

T.test("sort: nearest first, looked at again only out of a fight", function()
    local dist = { [1] = 900, [2] = 100, [3] = 400 }
    local Tr, ns = tracker({ quests = { QW.quest(1, "A"), QW.quest(2, "B"), QW.quest(3, "C") } }, { before = function() end })
    C_QuestLog.GetDistanceSqToQuest = function(id) return dist[id], true end
    DaylightUI:Set("Quests", "sort", "near")
    stub.RunTimers()
    T.deq(order(Tr), { 2, 3, 1 })
    dist[1] = 1
    stub.EnterCombat()
    ns.Tracker.NearTick()
    stub.RunTimers()
    T.deq(order(Tr), { 2, 3, 1 }, "not in a fight")
    stub.LeaveCombat(); stub.RunTimers()
    ns.Tracker.NearTick()
    stub.RunTimers()
    T.deq(order(Tr), { 1, 2, 3 })
end)

-- Walking changes every distance each look; only a new order lays out.
T.test("sort: nearest first lays out only when the order changes", function()
    local dist = { [1] = 900, [2] = 100, [3] = 400 }
    local Tr, ns = tracker({ quests = { QW.quest(1, "A"), QW.quest(2, "B"), QW.quest(3, "C") } }, { before = function() end })
    C_QuestLog.GetDistanceSqToQuest = function(id) return dist[id], true end
    DaylightUI:Set("Quests", "sort", "near")
    stub.RunTimers()
    local queued, queue = 0, ns.Tracker.Queue
    ns.Tracker.Queue = function(...) queued = queued + 1; return queue(...) end
    dist[1], dist[2], dist[3] = 800, 90, 380
    ns.Tracker.NearTick()
    T.eq(queued, 0, "same order: nothing to lay out")
    dist[3] = 50
    ns.Tracker.NearTick()
    T.eq(queued, 1, "a new order lays out")
    stub.RunTimers()
    T.deq(order(Tr), { 3, 2, 1 })
    ns.Tracker.Queue = queue
end)

T.test("sort: the old most-recent switch, off, becomes zone order", function()
    local p = { modules = { Quests = { recentFirst = false } } }
    stub.quests = nil
    tracker({ quests = { QW.quest(1, "A") } })
    stub.quests.UpgradeSort(p)
    T.eq(p.modules.Quests.sort, "zone")
    T.isnil(p.modules.Quests.recentFirst)
end)

T.test("fold ready: a ready quest shows its title alone", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { complete = true }), QW.quest(2, "B", { complete = true, timer = 60 }) } })
    DaylightUI:Set("Quests", "foldReady", true)
    stub.RunTimers()
    T.eq(#Tr.frames["quest:1"].block.lines, 1)
    T.truthy(#Tr.frames["quest:2"].block.lines > 1, "a timed quest never folds")
end)

-- A dungeon's quests and one from outside it, tracked; inside, the game's
-- zone is the dungeon's name.
local function dungeon(opts)
    local Tr, ns, settle = tracker({ zone = "The Deadmines", quests = {
        STEW, QW.quest(2, "Red Silk Bandanas", { zone = "The Deadmines" }) } }, opts)
    local inside, id = true, 36
    _G.IsInInstance = function() return inside, inside and "party" or "none" end
    _G.GetInstanceInfo = function() return "Dungeon", "party", 1, "Normal", 5, 0, false, id end
    local function load() stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers() end
    return Tr, ns, load, function(v) inside = v end, function(v) id = v end
end
local function undungeon() _G.IsInInstance, _G.GetInstanceInfo = nil, nil end

T.test("instances: by default the list goes to this zone, and back on leaving", function()
    local Tr, ns, load, setInside = dungeon()
    T.eq(DaylightUI:Get("Quests", "instances"), "zone")
    load()
    T.isnil(ns.Tracker.Folds().quests, "not folded")
    T.truthy(Tr.frames["quest:2"], "the dungeon's quest shows")
    T.isnil(Tr.frames["quest:1"], "a quest from outside doesn't")
    T.falsy(Tr.Shown(1), "nor does it count as in the tracker")
    T.truthy(Tr.Shown(2))
    T.eq(DaylightUI:Get("Quests", "filter"), "all", "the player's own filter isn't touched")
    T.truthy(Tr.controls.zone.active, "This zone lit: it says what the list shows")
    T.falsy(Tr.controls.all.active)
    setInside(false)
    load()
    T.truthy(Tr.frames["quest:1"], "every quest back outside")
    T.truthy(Tr.Shown(1))
    T.truthy(Tr.controls.all.active, "All lit again")
    undungeon()
end)

T.test("instances: this zone works with every quest in the log too", function()
    local Tr, ns, load, setInside = dungeon()
    DaylightUI:Set("Quests", "filter", "log")
    load()
    T.truthy(Tr.frames["quest:2"])
    T.isnil(Tr.frames["quest:1"])
    T.falsy(Tr.Shown(1))
    setInside(false)
    load()
    T.truthy(Tr.frames["quest:1"])
    T.eq(DaylightUI:Get("Quests", "filter"), "log", "still the player's")
    undungeon()
end)

T.test("instances: All inside shows everything until you leave, and keeps the player's filter", function()
    local Tr, ns, load, setInside, setId = dungeon()
    DaylightUI:Set("Quests", "filter", "log")
    load()
    Tr.controls.all:GetScript("OnClick")(Tr.controls.all); stub.RunTimers()
    T.truthy(Tr.frames["quest:1"], "All brings them back")
    T.truthy(Tr.controls.all.active)
    T.eq(DaylightUI:Get("Quests", "filter"), "log", "the click only lifted the dungeon's view")
    load()
    T.truthy(Tr.frames["quest:1"], "stays over a loading screen inside")
    setId(43)
    load()
    T.isnil(Tr.frames["quest:1"], "another dungeon goes to its zone again")
    undungeon()
end)

T.test("instances: the quest log names the dungeon differently from the zone text (The Stockade)", function()
    local Tr, ns, settle = tracker({ zone = "Stormwind Stockade", quests = {
        STEW, QW.quest(2, "Crime and Punishment", { zone = "The Stockade" }) } })
    _G.IsInInstance = function() return true, "party" end
    _G.GetInstanceInfo = function() return "The Stockade", "party", 1, "Normal", 5, 0, false, 34 end
    stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers()
    T.truthy(Tr.frames["quest:2"], "the dungeon's quests show under This zone")
    T.isnil(Tr.frames["quest:1"])
    undungeon()
end)

T.test("instances: a change of mode inside applies at once", function()
    local Tr, ns, load = dungeon()
    load()
    DaylightUI:Set("Quests", "instances", "fold"); stub.RunTimers()
    T.eq(ns.Tracker.Folds().quests, true, "this zone -> fold")
    T.falsy(Tr.controls.zone.active)
    DaylightUI:Set("Quests", "instances", "zone"); stub.RunTimers()
    T.isnil(ns.Tracker.Folds().quests, "fold -> this zone opens it")
    T.isnil(Tr.frames["quest:1"])
    DaylightUI:Set("Quests", "instances", "none"); stub.RunTimers()
    T.truthy(Tr.frames["quest:1"], "leave as it is: everything")
    undungeon()
end)

T.test("instances: fold on entering, back on leaving", function()
    local Tr, ns = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "instances", "fold")
    local inside = true
    _G.IsInInstance = function() return inside, inside and "party" or "none" end
    stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers()
    T.eq(ns.Tracker.Folds().quests, true, "folded inside")
    inside = false
    stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers()
    T.isnil(ns.Tracker.Folds().quests, "open again outside")
    DaylightUI:Set("Quests", "instances", "hide")
    inside = true
    stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers()
    for _ = 1, 30 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 30) end
    T.falsy(DaylightUIQuestTracker:IsShown(), "hidden inside")
    inside = false
    stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers()
    T.truthy(DaylightUIQuestTracker:IsShown(), "back outside")
    _G.IsInInstance = nil
end)

T.test("instances: a tracker opened inside stays open until you leave", function()
    local Tr, ns = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "instances", "fold")
    local inside, id = true, 36
    _G.IsInInstance = function() return inside, inside and "party" or "none" end
    _G.GetInstanceInfo = function() return "Dungeon", "party", 1, "Normal", 5, 0, false, id end
    local function load() stub.FireEvent("PLAYER_ENTERING_WORLD"); stub.RunTimers() end
    load()
    T.eq(ns.Tracker.Folds().quests, true, "folded on entering")
    DaylightUI.QuestsFoldAll()
    load()
    T.isnil(ns.Tracker.Folds().quests, "stays open over a loading screen inside")
    id = 43
    load()
    T.eq(ns.Tracker.Folds().quests, true, "another dungeon folds it again")
    DaylightUI.QuestsFoldAll()
    inside = false
    load()
    inside, id = true, 43
    load()
    T.eq(ns.Tracker.Folds().quests, true, "out and back in folds it again")
    DaylightUI.QuestsFoldAll()
    DaylightUI.QuestsFoldAll()
    inside = false
    load()
    T.eq(ns.Tracker.Folds().quests, true, "a fold the player made inside is left")
    DaylightUI.QuestsFoldAll()
    _G.IsInInstance, _G.GetInstanceInfo = nil, nil
end)

T.test("colors: count mode paints red to green", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { objs = { { text = "3/6 Murloc", have = 3, need = 6 } } }) } })
    DaylightUI:Set("Quests", "objColors", "count")
    stub.RunTimers()
    local f = Tr.frames["quest:1"]
    local l = f.lines["obj:1"]
    local c = DaylightUI.Tips.Progress(3, 6)
    T.rgb(l.label.__textColor, { c[1], c[2], c[3] })
end)

T.test("colors: done mode turns a done objective green", function()
    local Tr = tracker({ quests = { QW.quest(1, "A", { objs = { { text = "6/6 Murloc", have = 6, need = 6, done = true },
                                                                   { text = "1/6 Fin", have = 1, need = 6 } } }) } })
    DaylightUI:Set("Quests", "objColors", "done")
    stub.RunTimers()
    local G = DaylightUI.Style.INK.GOOD
    T.rgb(Tr.frames["quest:1"].lines["obj:1"].label.__textColor, { G[1], G[2], G[3] })
end)

T.test("hover dim eases others to 0.5", function()
    local Tr = tracker({ quests = { QW.quest(1, "A"), QW.quest(2, "B") } })
    local f1, f2 = Tr.frames["quest:1"], Tr.frames["quest:2"]
    f1:GetScript("OnEnter")(f1)
    for _ = 1, 30 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 30) end
    T.eq(f2.lines.title.label:GetAlpha(), 0.5)
    T.eq(f1.lines.title.label:GetAlpha(), 1, "the hovered one stays")
    f1:GetScript("OnLeave")(f1)
    for _ = 1, 30 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 30) end
    T.eq(f2.lines.title.label:GetAlpha(), 1)
end)

T.test("grow up anchors the list at the bottom", function()
    local Tr = tracker({ quests = { STEW } })
    DaylightUI:Set("Quests", "growUp", true)
    stub.RunTimers()
    T.eq((Tr.view:GetPoint(1)), "BOTTOMRIGHT")
    DaylightUI:Set("Quests", "growUp", false)
    stub.RunTimers()
    T.eq((Tr.view:GetPoint(1)), "TOPRIGHT")
end)

T.test("empty header: shows with no quests when on", function()
    local Tr = tracker({ quests = {} })
    T.isnil(Tr.frames["section:quests"])
    DaylightUI:Set("Quests", "emptyHeader", true)
    stub.RunTimers()
    T.truthy(Tr.frames["section:quests"])
end)

-- ---------------------------------------------------------------------
-- More edge cases
-- ---------------------------------------------------------------------

T.test("review: Questie's tracker picked live asks for a reload (Questie builds its tracker only at load)", function()
    local ns = withQuestie()
    local asked
    local was = DaylightUI.EditMode.AskReload
    DaylightUI.EditMode.AskReload = function(text) asked = text end
    ns.Choice.Pick("questie")
    stub.RunTimers()
    DaylightUI.EditMode.AskReload = was
    T.truthy(asked, "a reload asked for")
    _G.Questie = nil
end)

T.test("review: off then on again mid-fade leaves the tracker showing", function()
    local ns = withQuestie()
    ns.Choice.Pick("ours")
    DaylightUI:Set("Quests", "tracker", false)
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.05)   -- part way out
    DaylightUI:Set("Quests", "tracker", true)
    stub.RunTimers()
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1 / 30) end
    T.truthy(DaylightUIQuestTracker:IsShown())
    T.truthy(DaylightUIQuestTracker:GetAlpha() > 0.5, "visible again: " .. tostring(DaylightUIQuestTracker:GetAlpha()))
    T.falsy(ns.Tracker.going, "not on its way out any more")
    _G.Questie = nil
end)
