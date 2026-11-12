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
