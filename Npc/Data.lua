-- Reads what the NPC says and offers from the game into plain tables.
-- Mirrors the game's own reads in GossipFrameShared.lua, QuestFrame.lua and QuestInfo.lua.

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc

local Data = {}
ns.Data = Data

local function fn(f) return type(f) == "function" end
local function call(f, ...) if fn(f) then return f(...) end end

-- Quest colors

Data.YELLOW = { 1, 0.82, 0.25 }
Data.TRIVIAL = DUI.Style.INK.OFF

-- The game's level-based difficulty color, or nil.
local function levelColor(level)
    if type(level) ~= "number" or level <= 0 or not fn(GetQuestDifficultyColor) then return nil end
    local c = GetQuestDifficultyColor(level)
    if type(c) == "table" and c.r then return c end
end

local function plain(c) return c and { c.r, c.g, c.b } end

-- Is this quest orange or red for the player by level alone?
local function tooHigh(c)
    local all = QuestDifficultyColors
    return c and type(all) == "table" and (c == all.verydifficult or c == all.impossible)
end

-- The quest log's color comes from the server and can be greener than the level math,
-- but it never goes past yellow (a level 10 quest at level 5 still reads yellow).
-- So an orange or red from the level math wins, otherwise use the log's color.
function Data.QuestColor(questID, level, trivial)
    if trivial then return Data.TRIVIAL end
    if type(level) ~= "number" and type(questID) == "number" and C_QuestLog and fn(C_QuestLog.GetQuestDifficultyLevel) then
        local ok, l = pcall(C_QuestLog.GetQuestDifficultyLevel, questID)
        if ok then level = l end
    end
    local byLevel = levelColor(level)
    if tooHigh(byLevel) then return plain(byLevel) end
    if type(questID) == "number" and C_PlayerInfo and fn(C_PlayerInfo.GetContentDifficultyQuestForPlayer) and fn(GetDifficultyColor) then
        local ok, d = pcall(C_PlayerInfo.GetContentDifficultyQuestForPlayer, questID)
        local c = ok and d and GetDifficultyColor(d)
        if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    end
    return plain(byLevel) or Data.YELLOW
end

-- Gossip

local function optionText(o)
    local name = o.name or ""
    local F = Enum and Enum.GossipOptionRecFlags
    if F and type(o.flags) == "number" and bit and bit.band then
        if F.QuestLabelPrepend and bit.band(o.flags, F.QuestLabelPrepend) ~= 0 and GOSSIP_QUEST_OPTION_PREPEND then
            name = GOSSIP_QUEST_OPTION_PREPEND:format(name)
        elseif F.PlayMovieLabelPrepend and bit.band(o.flags, F.PlayMovieLabelPrepend) ~= 0 and GOSSIP_VIDEO_OPTION_PREPEND then
            name = GOSSIP_VIDEO_OPTION_PREPEND:format(name)
        end
    end
    return name
end

function Data.Gossip()
    local G = C_GossipInfo or {}
    local t = { text = call(G.GetText) or "", quests = {}, options = {} }
    for _, q in ipairs(call(G.GetAvailableQuests) or {}) do
        t.quests[#t.quests + 1] = { kind = "available", title = q.title, level = q.questLevel, trivial = q.isTrivial,
            questID = q.questID, legendary = q.isLegendary, frequency = q.frequency, repeatable = q.repeatable,
            important = q.isImportant, meta = q.isMeta, infoID = q.questInfoID }
    end
    for _, q in ipairs(call(G.GetActiveQuests) or {}) do
        t.quests[#t.quests + 1] = { kind = "active", title = q.title, level = q.questLevel, trivial = q.isTrivial,
            questID = q.questID, complete = q.isComplete == true, legendary = q.isLegendary, frequency = q.frequency,
            repeatable = q.repeatable, important = q.isImportant, meta = q.isMeta, infoID = q.questInfoID }
    end
    local opts = call(G.GetOptions) or {}
    table.sort(opts, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
    for _, o in ipairs(opts) do
        t.options[#t.options + 1] = { name = optionText(o), icon = o.overrideIconID or o.icon, orderIndex = o.orderIndex,
            spellID = o.spellID, status = o.status }
    end
    return t
end

-- Quest greeting (an NPC that only has quests)

function Data.Greeting()
    local t = { text = call(GetGreetingText) or "", quests = {} }
    for i = 1, call(GetNumAvailableQuests) or 0 do
        local trivial, frequency, repeatable, legendary, questID = call(GetAvailableQuestInfo, i)
        t.quests[#t.quests + 1] = { kind = "available", index = i, title = call(GetAvailableTitle, i), trivial = trivial,
            questID = questID, frequency = frequency, repeatable = repeatable, legendary = legendary }
    end
    for i = 1, call(GetNumActiveQuests) or 0 do
        local title, complete = call(GetActiveTitle, i)
        t.quests[#t.quests + 1] = { kind = "active", index = i, title = title, complete = complete == true,
            trivial = call(IsActiveQuestTrivial, i), questID = call(GetActiveQuestID, i) }
    end
    return t
end

-- Quest pages: offer (detail), progress and hand-in (reward)

-- Every reward slot gets an entry in the game's order. Slots that haven't loaded yet
-- stay as `loading` placeholders so the player can see the choice is there, and picks
-- go out by the game's own index. QUEST_ITEM_UPDATE fills them in later.
-- Vendor price of one item, or nil until the game has loaded it.
local function sellPrice(key)
    if not (key and C_Item and fn(C_Item.GetItemInfo)) then return nil end
    local ok, _, sell
    ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, key)
    if ok and type(sell) == "number" then return sell end
end

local function items(kind, n)
    local out = {}
    for i = 1, n or 0 do
        local loot = call(GetQuestItemInfoLootType, kind, i)
        local it
        if loot == nil or loot == 0 then
            local name, texture, count, quality, usable, itemID = call(GetQuestItemInfo, kind, i)
            if name then
                it = { kind = kind, index = i, name = name, texture = texture, count = count, quality = quality,
                    usable = usable, itemID = itemID, sell = sellPrice(itemID or call(GetQuestItemLink, kind, i)) }
            else
                it = { kind = kind, index = i, loading = true, texture = texture, count = count }
            end
        elseif C_QuestOffer and fn(C_QuestOffer.GetQuestRewardCurrencyInfo) then
            local ok, c = pcall(C_QuestOffer.GetQuestRewardCurrencyInfo, kind, i)
            if ok and type(c) == "table" then
                it = { kind = kind, index = i, currency = true, name = c.name, texture = c.texture,
                    count = c.totalRewardAmount or c.baseRewardAmount, quality = c.quality }
            end
        end
        out[#out + 1] = it or { kind = kind, index = i, loading = true }
    end
    return out
end

-- The quest log's choice count, or nil when it can't tell (not in the log, data not
-- loaded yet). GetNumQuestChoices can lag on a first visit; this one doesn't.
function Data.LogChoices(questID)
    if type(questID) ~= "number" or not (C_QuestLog and fn(C_QuestLog.GetLogIndexForQuestID)) then return nil end
    if not C_QuestLog.GetLogIndexForQuestID(questID) or call(HaveQuestData, questID) ~= true then return nil end
    local n = call(GetNumQuestLogChoices, questID, true)
    return type(n) == "number" and n or nil
end

-- A quest handed in without ever being accepted has no log entry. When it does, its
-- data may still be missing; Data.LoadQuest asks the server for it.
function Data.InLog(questID)
    return type(questID) == "number" and C_QuestLog and fn(C_QuestLog.GetLogIndexForQuestID)
        and C_QuestLog.GetLogIndexForQuestID(questID) ~= nil or false
end

function Data.LoadQuest(questID)
    if Data.InLog(questID) and call(HaveQuestData, questID) ~= true and fn(C_QuestLog.RequestLoadQuestByID) then
        C_QuestLog.RequestLoadQuestByID(questID)
    end
end

-- Has the game changed since this quest page was read? Counts, money, or a loading
-- reward tile that now has its item. No single event covers all of these.
function Data.QuestMoved(d)
    if (call(GetNumQuestChoices) or 0) ~= #d.choices or (call(GetNumQuestRewards) or 0) ~= #d.rewards then return true end
    if (call(GetRewardMoney) or 0) ~= d.money or (call(GetRewardXP) or 0) ~= d.xp then return true end
    for _, list in ipairs({ d.choices, d.rewards }) do
        for _, it in ipairs(list) do
            if it.loading and call(GetQuestItemInfo, it.kind, it.index) then return true end
        end
    end
    return false
end

-- Vendor value of the whole stack. Currencies have none.
function Data.SaleOf(it) return (it.sell or 0) * (it.count or 1) end

-- Sell price of the most valuable choice, for the coin on its tile. Returns nil when
-- there's nothing to compare (one choice, all equal, none sell), and nil, true while
-- a price is still loading so the coin doesn't jump from one item to another.
function Data.BestSale(list)
    if not list or #list < 2 then return nil end
    local best, low = 0, nil
    for _, it in ipairs(list) do
        if it.loading or (it.sell == nil and not it.currency) then return nil, true end
        local v = Data.SaleOf(it)
        if v > best then best = v end
        if not low or v < low then low = v end
    end
    if best > 0 and low < best then return best end
end

-- mode: "detail" | "progress" | "reward"
function Data.Quest(mode)
    local t = { mode = mode, title = call(GetTitleText) or "", questID = call(GetQuestID) }
    if mode == "detail" then
        t.text = call(GetQuestText) or ""
        t.objective = call(GetObjectiveText) or ""
        t.auto = call(QuestGetAutoAccept) == true
        t.pvp = call(QuestFlagsPVP) == true
    elseif mode == "progress" then
        t.text = call(GetProgressText) or ""
        t.completable = call(IsQuestCompletable) == true
        t.required = {}
        for i = 1, call(GetNumQuestItems) or 0 do
            if call(IsQuestItemHidden, i) ~= 1 then
                local name, texture, count, quality = call(GetQuestItemInfo, "required", i)
                if name then t.required[#t.required + 1] = { kind = "required", index = i, name = name, texture = texture, count = count, quality = quality } end
            end
        end
        t.cost = call(GetQuestMoneyToGet) or 0
    else
        t.text = call(GetRewardText) or ""
        t.cost = call(GetQuestMoneyToGet) or 0
    end
    if mode ~= "progress" then
        t.choices = items("choice", call(GetNumQuestChoices))
        t.rewards = items("reward", call(GetNumQuestRewards))
        t.money = call(GetRewardMoney) or 0
        t.xp = call(GetRewardXP) or 0
    end
    t.color = Data.QuestColor(t.questID)
    return t
end
