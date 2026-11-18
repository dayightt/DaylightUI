local stub = require("stub")
local QW = require("questworld")

-- DaylightUI.API 1.3: the quest tracker's quests are frames plugins paint ("questrow":
-- unit = the quest's id; title, objectives, bar, icon), painted after every layout
-- of the list.

local function load(spec)
    local world = QW.world(spec)
    stub.Load({ quests = true, before = function() world() end })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    return DaylightUI.API, stub.quests
end

local STEW = QW.quest(1, "Westfall Stew", { objs = {
    { text = "4/5 Stringy Vulture Meat", have = 4, need = 5 },
} })
local DEFIAS = QW.quest(2, "The Defias Brotherhood")

T.test("api quests: each tracked quest is a frame with its pieces by name", function()
    local API, ns = load({ quests = { STEW, DEFIAS } })
    local row = API.GetQuestRow(1)
    T.truthy(row, "found by its quest")
    T.eq(row, ns.Tracker.frames["quest:1"])
    local p = API.Parts(row)
    T.eq(p.title, row.lines.title.label)
    T.truthy(type(p.objectives) == "table" and #p.objectives >= 1, "its objectives")
    T.eq(p.icon, row.ring, "the shown state's icon")
    T.isnil(API.GetQuestRow(99))
end)

T.test("api quests: painted after each layout, with the quest's id", function()
    local API = load({ quests = { STEW } })
    local got = {}
    API.For("Neon").Paint("questrow", function(f, parts, info) got[#got + 1] = info end)
    T.truthy(#got >= 1, "the one already there")
    local n = #got
    QW.state.quests[1].objs[1].have = 5
    QW.state.quests[1].objs[1].text = "5/5 Stringy Vulture Meat"
    stub.FireEvent("QUEST_LOG_UPDATE")
    stub.RunTimers()
    T.truthy(#got > n, "painted again after the update")
    T.eq(got[#got].questID, 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api quests: a quest leaving the tracker lets its row go", function()
    local API = load({ quests = { STEW, DEFIAS } })
    local removed = {}
    API.On("FrameRemoved", function(kind, f, unit) if kind == "questrow" then removed[#removed + 1] = unit end end)
    table.remove(QW.state.quests, 2)
    stub.FireEvent("QUEST_REMOVED", 2)
    stub.FireEvent("QUEST_LOG_UPDATE")
    stub.RunTimers()
    T.eq(removed[1], 2)
    T.isnil(API.GetQuestRow(2))
end)

-- 1.11: rows of a plugin's own in the quest right-click menus.
local function catchMenu()
    local W, got = DaylightUI.Widgets, {}
    W.OpenMenu = function(owner, keys, text, current, onPick) got.keys, got.text, got.pick = keys, text, onPick end
    return got
end

T.test("api quests: a plugin's row in the tracker's menu, before Stop tracking", function()
    local API, ns = load({ quests = { STEW, DEFIAS } })
    local me = API.For("Mapzeroth")
    local clicked, asked
    T.eq(me.AddQuestMenu("route", { label = function(q) asked = q; return "Route to this quest" end,
        show = function(q) return q.questID == 1 end, onClick = function(q) clicked = q end }), true)
    local got = catchMenu()
    ns.Clicks.Menu(ns.Tracker.frames["quest:1"].block.quest, ns.Tracker.frames["quest:1"])
    local keys = got.keys
    local at
    for i, k in ipairs(keys) do if k == "plugin:Mapzeroth:route" then at = i end end
    T.truthy(at, "the row is there")
    T.eq(got.text[keys[at]], "Route to this quest")
    T.eq(keys[at + 1], "untrack", "Stop tracking and Abandon stay at the bottom")
    T.eq(asked.title, "Westfall Stew")
    got.pick(keys[at])
    T.eq(clicked.questID, 1)
    ns.Clicks.Menu(ns.Tracker.frames["quest:2"].block.quest, ns.Tracker.frames["quest:2"])
    for _, k in ipairs(got.keys) do T.truthy(k ~= "plugin:Mapzeroth:route", "show said no for this quest") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api quests: a broken plugin row is left out, a bad spec refused, and it can be taken away", function()
    local API, ns = load({ quests = { STEW } })
    local me = API.For("Broken")
    T.eq(me.AddQuestMenu("x", { label = "No click" }), false, "needs onClick")
    me.AddQuestMenu("boom", { label = function() error("boom") end, onClick = function() end })
    me.AddQuestMenu("ok", { label = "Fine", onClick = function() end })
    local got = catchMenu()
    local f = ns.Tracker.frames["quest:1"]
    ns.Clicks.Menu(f.block.quest, f)
    local seen = {}
    for _, k in ipairs(got.keys) do seen[k] = true end
    T.isnil(seen["plugin:Broken:boom"], "an erroring label is left out")
    T.truthy(seen["plugin:Broken:ok"])
    T.truthy(seen.abandon or seen.untrack, "the menu's own rows are still there")
    T.eq(me.RemoveQuestMenu("ok"), true)
    ns.Clicks.Menu(f.block.quest, f)
    for _, k in ipairs(got.keys) do T.truthy(k ~= "plugin:Broken:ok", "gone") end
end)

T.test("api quests: the journal's quest menu has the plugin's row too", function()
    local API, ns = load({ quests = { STEW } })
    local clicked
    API.For("Mapzeroth").AddQuestMenu("route", { label = "Route to this quest", onClick = function(q) clicked = q.questID end })
    local got = catchMenu()
    ns.Journal.Menu(ns.Tracker.frames["quest:1"].block.quest, UIParent)
    local at
    for i, k in ipairs(got.keys) do if k == "plugin:Mapzeroth:route" then at = i end end
    T.truthy(at, "in the journal's menu")
    got.pick(got.keys[at])
    T.eq(clicked, 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
