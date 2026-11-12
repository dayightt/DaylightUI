local stub = require("stub")
local QW = require("questworld")

-- An NPC's quests in its tooltip (GiverTips.lua), from Questie's own list, and the
-- game's own quest lines on a mob or an item, in Daylight UI's text colors.

local GIVER = "Creature-0-1-2-3-9-0"     -- NPC 9

-- QuestieDB as its API says: rows by id.
local DB = {
    [100] = { name = "Wolves", finishedBy = { { 9 } }, questLevel = 11 },
    [200] = { name = "Bears", questLevel = 10 },
    [210] = { name = "Again and again", questLevel = 12, specialFlags = 1 },
    [211] = { name = "Into the dungeon", questLevel = 13 },
}

-- Questie, with its loader handing out its tooltip registry: the quests NPC 9
-- starts that it says you can take (200, 210, 211), a target line (an objective
-- entry, not a start) and another NPC's quest.
local function questie()
    stub.loadedAddOns.Questie = true
    _G.Questie = { db = { profile = {} } }
    local byKey = {
        m_9 = {
            ["200 Sten 9"] = { questId = 200, name = "Sten", starterId = 9, type = "NPC" },
            ["210 Sten 9"] = { questId = 210, name = "Sten", starterId = 9, type = "NPC" },
            ["211 Sten 9"] = { questId = 211, name = "Sten", starterId = 9, type = "NPC" },
            ["100 1"] = { questId = 100, objective = { Index = 1 } },
        },
        m_7 = { ["300 Ada 7"] = { questId = 300, name = "Ada", starterId = 7, type = "NPC" } },
    }
    _G.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestieTooltips" then return { lookupByKey = byKey } end
        return { private = {} }
    end }
    -- QuestieDB as Spots.Ready() finds it, with finishedBy a fresh copy per read like its own.
    _G.LibQuestieDB, _G.NpcDB = {}, { Get = function() return nil end }
    _G.QuestDB = { Get = function(id, key)
        local e = DB[id]
        local v = e and e[key]
        if key == "finishedBy" then stub.finishedByReads = (stub.finishedByReads or 0) + 1 end
        if key == "finishedBy" and type(v) == "table" then return { { unpack(v[1] or {}) } } end
        return v
    end }
end

local post
local function load(spec)
    spec = spec or {}
    local world = QW.world(spec.world or { quests = {} })
    stub.Load({ quests = true, before = function()
        world()
        post = {}
        Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }
        _G.TooltipDataProcessor = {
            AllTypes = "ALL",
            AddTooltipPostCall = function(kind, fn) post[kind] = post[kind] or {}; table.insert(post[kind], fn) end,
        }
        _G.Questie, _G.QuestieLoader, _G.QuestDB, _G.LibQuestieDB, _G.NpcDB = nil, nil, nil, nil, nil
        stub.loadedAddOns.Questie = nil
        if spec.questie then questie() end
    end })
    stub.units = stub.units or {}
    stub.units.player = stub.units.player or { name = "Me", class = "MAGE" }
    stub.units.player.level = 12
    for k, v in pairs(spec.settings or {}) do DaylightUI:Set("Quests", k, v) end
    return stub.quests
end

-- Points at a unit: the game fills its tooltip, then runs the post-calls.
local function hover(guid)
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:Show()
    for _, fn in ipairs(post[Enum.TooltipDataType.Unit] or {}) do fn(GameTooltip, { guid = guid }) end
    return GameTooltip.lines
end

local function find(lines, word)
    for i, l in ipairs(lines) do if l:find(word, 1, true) then return i, l end end
end

T.test("NPC tooltip: Questie's quests you can take, with their level and kind", function()
    load({ questie = true })
    local lines = hover(GIVER)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(lines[1], " ", "a gap before the quests")
    local i, bears = find(lines, "Bears")
    T.truthy(i, "Bears listed: " .. table.concat(lines, " / "))
    T.truthy(bears:find("|A:QuestNormal:", 1, true), "the game's ! in front")
    T.truthy(bears:find("| 10", 1, true), "its level on the right: " .. bears)
    local c = DaylightUI.Npc.Data.QuestColor(200, 10, false)
    T.eq(GameTooltip.colors[i].lc[1], c[1], "the name in the quest log's difficulty color")
    T.falsy(find(lines, "Wolves"), "a target line of Questie's isn't a quest to take")
    local _, again = find(lines, "Again and again")
    T.truthy(again and again:find("Repeatable", 1, true), "a repeatable quest says so")
    T.truthy(find(lines, "Bears") < find(lines, "Again and again"), "lowest level first")
end)

T.test("NPC tooltip: a dungeon quest says so, in the game's word", function()
    load({ questie = true })
    C_QuestLog.GetQuestTagInfo = function(id) if id == 211 then return { tagID = 81 } end end
    local _, line = find(hover(GIVER), "Into the dungeon")
    T.truthy(line and line:find(CALENDAR_TYPE_DUNGEON or "Dungeon", 1, true), tostring(line))
end)

T.test("NPC tooltip: a quest ready to hand in to them comes first, marked Ready", function()
    local ready = QW.quest(100, "Wolves", { complete = true, objs = { { text = "Wolf slain", have = 5, need = 5, done = true } } })
    load({ questie = true, world = { quests = { ready } } })
    local lines = hover(GIVER)
    T.truthy(lines[2]:find("Wolves", 1, true), "first: " .. tostring(lines[2]))
    T.truthy(lines[2]:find("QuestTurnin", 1, true), "the game's ?")
    T.truthy(lines[2]:find(DaylightUI.L["Ready"], 1, true))
    T.eq(GameTooltip.colors[2].rc[1], DaylightUI.Style.INK.GOOD[1], "Ready in the done color")
end)

T.test("NPC tooltip: a quest you have that ends with them, not done yet, shows with its progress, after what you can take", function()
    local busy = QW.quest(100, "Wolves", { objs = { { text = "Wolf slain: 2/5", have = 2, need = 5 } } })
    load({ questie = true, world = { quests = { busy } } })
    local lines = hover(GIVER)
    local i, wolves = find(lines, "Wolves")
    T.truthy(i, "listed: " .. table.concat(lines, " / ") .. tostring(stub.errors[1]))
    T.truthy(wolves:find("quest-progress", 1, true), "the under-way icon, as in our NPC window")
    T.truthy(wolves:find("2/5", 1, true), "its progress: " .. wolves)
    T.truthy(find(lines, "Bears") < i, "after the quests you can take")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("NPC tooltip: who ends each quest is read once, not on every tooltip refresh", function()
    local busy = QW.quest(100, "Wolves", { objs = { { text = "Wolf slain: 2/5", have = 2, need = 5 } } })
    load({ questie = true, world = { quests = { busy } } })
    stub.finishedByReads = 0
    T.truthy(find(hover(GIVER), "Wolves"))
    local first = stub.finishedByReads
    T.truthy(find(hover(GIVER), "Wolves"))
    hover(GIVER)
    T.eq(stub.finishedByReads, first, "kept after the first look")
end)

T.test("NPC tooltip: nothing without Questie, for players, or when switched off", function()
    load()
    local n = #hover(GIVER)
    T.eq(n, 0, "no Questie: the game's tooltip as it is")
    load({ questie = true })
    T.eq(#hover("Player-1-0001"), 0, "a player")
    load({ questie = true, settings = { ["mapQuests.tooltip"] = false } })
    T.eq(#hover(GIVER), 0, "switched off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("NPC tooltip: past six quests, one line says how many more", function()
    load({ questie = true })
    local list = {}
    for i = 1, 9 do list[i] = { kind = "!", quest = 500 + i, name = "Quest " .. i, level = 10 } end
    stub.quests.GiverTips.Add(GameTooltip, list)
    local _, more = find(GameTooltip.lines, string.format(DaylightUI.L["And %d more"], 3))
    T.truthy(more, table.concat(GameTooltip.lines, " / "))
end)

T.test("NPC tooltip: Questie's own quest lines step aside while ours show, back when ours are off", function()
    load({ questie = true })
    local p = Questie.db.profile
    p.showQuestsInNpcTooltip = true
    DaylightUI.QuestieAside.Run()
    T.eq(p.showQuestsInNpcTooltip, false, "one list of quests, ours")
    DaylightUI:Set("Quests", "mapQuests.tooltip", false)
    DaylightUI.QuestieAside.Run()
    T.eq(p.showQuestsInNpcTooltip, true, "ours off: Questie's back")
end)

T.test("Mob tooltip: the game's quest lines get the log's color, soft white and a popped count", function()
    local q = QW.quest(700, "Kobold Camp Cleanup", { level = 12, objs = { { text = "Kobold Vermin slain", have = 4, need = 10 } } })
    load({ world = { quests = { q } } })
    Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
    local texts = { "Kobold Vermin", "Kobold Camp Cleanup", " - Kobold Vermin slain: 4/10", " - Wolf Pelt: 3/3" }
    for i, t in ipairs(texts) do
        local fs = GameTooltip:CreateFontString("GameTooltipTextLeft" .. i)
        _G["GameTooltipTextLeft" .. i] = fs
        fs:SetText(t)
        fs:SetTextColor(1, 1, 1)
    end
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    local data = { guid = "Creature-0-1-2-3-55-0", lines = {
        { type = 2 }, { type = 17 }, { type = 8, completed = false }, { type = 8, completed = true } } }
    for _, fn in ipairs(post[Enum.TooltipDataType.Unit] or {}) do fn(GameTooltip, data) end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local INK = DaylightUI.Style.INK
    local c = DaylightUI.Npc.Data.QuestColor(700, 12)
    T.eq(GameTooltipTextLeft2.__textColor[1], c[1], "the quest's name in the log's difficulty color")
    T.eq(GameTooltipTextLeft1:GetText(), "Kobold Vermin", "the mob's own line left alone")
    local obj = GameTooltipTextLeft3:GetText()
    T.eq(GameTooltipTextLeft3.__textColor[1], INK.TEXT[1], "the objective soft white")
    T.truthy(obj:find(DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Accent() }) .. "4/10|r", 1, true), "the count in the accent: " .. obj)
    T.truthy(GameTooltipTextLeft4:GetText():find(DaylightUI.Win.Parts.Hex(INK.GOOD) .. "3/3|r", 1, true), "a done count in good")
end)

T.test("NPC tooltip: its switch on the Tooltips page waits for Questie", function()
    local function row()
        stub.Load({ quests = true, tooltip = true, before = function()
            _G.Questie, _G.QuestieLoader, _G.QuestDB = nil, nil, nil
            stub.loadedAddOns.Questie = nil
        end })
        local page = DaylightUI.Options.GetPage("Tooltip.tooltip")
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items) do if it.key == "mapQuests.tooltip" then return it end end
        end
    end
    local it = row()
    T.truthy(it and it.disabled, "the row can dim")
    T.eq(it.disabled(), true, "dimmed without Questie: nothing would show")
    questie()
    T.eq(it.disabled(), false, "on with Questie")
end)
