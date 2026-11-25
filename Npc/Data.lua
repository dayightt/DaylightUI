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

-- Levels the NPC's list gave, by quest, for a quest page the game can't name a level for.
Data.levels = {}

-- A quest's level, or nil when the game doesn't know it.
function Data.QuestLevel(questID)
    if type(questID) ~= "number" or questID <= 0 then return nil end
    if C_QuestLog and fn(C_QuestLog.GetQuestDifficultyLevel) then
        local level = C_QuestLog.GetQuestDifficultyLevel(questID)
        if type(level) == "number" and level > 0 then return level end
    end
    return Data.levels[questID]
end

-- A quest's type as the game's own log tags it (Forever's
-- QuestUtilsOverrides.GetQuestTagText: "(Elite)", "(Dungeon)", "(Raid)", "(PvP)"):
-- elite | dungeon | raid | pvp, or nil. An elite quest without the tag still
-- counts (the log's "[22+]" comes from IsEliteQuest). The quest tracker reads
-- the same.
local QC = Constants and Constants.QuestConsts or {}
Data.TAGS = {
    [QC.QUEST_INFO_ELITE_ID or 1] = "elite",
    [QC.QUEST_INFO_DUNGEON_ID or 81] = "dungeon",
    [QC.QUEST_INFO_RAID_ID or 62] = "raid",
    [QC.QUEST_INFO_PVP_ID or 41] = "pvp",
}
Data.TAG_WORDS = {
    elite = function() return ELITE or DUI.L["Elite"] end,
    dungeon = function() return CALENDAR_TYPE_DUNGEON or DUI.L["Dungeon"] end,
    raid = function() return RAID or DUI.L["Raid"] end,
    pvp = function() return CALENDAR_TYPE_PVP or DUI.L["PvP"] end,
}

function Data.Tag(questID)
    if type(questID) ~= "number" or questID <= 0 or not C_QuestLog then return nil end
    local info = call(C_QuestLog.GetQuestTagInfo, questID)
    local id = type(info) == "table" and info.tagID or nil
    local kind = type(id) == "number" and Data.TAGS[id] or nil
    if not kind and call(C_QuestLog.IsEliteQuest, questID) == true then kind = "elite" end
    return kind
end

-- The tag for the NPC window: { text, color } in the tracker's colors, or nil
-- for a plain quest or with the tracker's quest tags switched off.
function Data.TagFor(questID)
    local kind = Data.Tag(questID)
    if not kind or DUI:Get("Quests", "questTags") == false then return nil end
    local c = DUI:Get("Quests", "colors." .. kind)
    if type(c) ~= "table" or type(c[1]) ~= "number" then c = { DUI.Style.Accent() } end
    return { text = Data.TAG_WORDS[kind](), color = c }
end

local function remember(q)
    if type(q.questID) == "number" and type(q.level) == "number" and q.level > 0 then Data.levels[q.questID] = q.level end
    return q
end

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
    if type(level) ~= "number" then level = Data.QuestLevel(questID) end
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

-- "(Quest)" and "(Play Movie)" before an option, both when both flags are set, as
-- the game's GossipOptionButtonMixin:Setup builds them. The older one-flag strings
-- are only a fallback for a client without the newer ones.
local function optionText(o)
    local name = o.name or ""
    local F = Enum and Enum.GossipOptionRecFlags
    if not (F and type(o.flags) == "number" and bit and bit.band) then return name end
    local quest = F.QuestLabelPrepend and bit.band(o.flags, F.QuestLabelPrepend) ~= 0
    local movie = F.PlayMovieLabelPrepend and bit.band(o.flags, F.PlayMovieLabelPrepend) ~= 0
    if type(GOSSIP_OPTION_PREPEND) == "string" and (quest or movie) then
        local pre = {}
        if quest and QUEST_PREPEND then pre[#pre + 1] = QUEST_PREPEND end
        if movie and PLAY_MOVIE_PREPEND then pre[#pre + 1] = PLAY_MOVIE_PREPEND end
        if #pre > 0 then return GOSSIP_OPTION_PREPEND:format(table.concat(pre, " "), name) end
    end
    if quest and GOSSIP_QUEST_OPTION_PREPEND then
        name = GOSSIP_QUEST_OPTION_PREPEND:format(name)
    elseif movie and GOSSIP_VIDEO_OPTION_PREPEND then
        name = GOSSIP_VIDEO_OPTION_PREPEND:format(name)
    end
    return name
end

function Data.Gossip()
    local G = C_GossipInfo or {}
    local t = { text = call(G.GetText) or "", quests = {}, options = {} }
    for _, q in ipairs(call(G.GetAvailableQuests) or {}) do
        t.quests[#t.quests + 1] = remember({ kind = "available", title = q.title, level = q.questLevel, trivial = q.isTrivial,
            questID = q.questID, legendary = q.isLegendary, frequency = q.frequency, repeatable = q.repeatable,
            important = q.isImportant, meta = q.isMeta, infoID = q.questInfoID })
    end
    for _, q in ipairs(call(G.GetActiveQuests) or {}) do
        t.quests[#t.quests + 1] = remember({ kind = "active", title = q.title, level = q.questLevel, trivial = q.isTrivial,
            questID = q.questID, complete = q.isComplete == true, legendary = q.isLegendary, frequency = q.frequency,
            repeatable = q.repeatable, important = q.isImportant, meta = q.isMeta, infoID = q.questInfoID })
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
        local trivial, frequency, repeatable, legendary, questID, important, meta, infoID = call(GetAvailableQuestInfo, i)
        t.quests[#t.quests + 1] = { kind = "available", index = i, title = call(GetAvailableTitle, i), trivial = trivial,
            questID = questID, level = Data.QuestLevel(questID), frequency = frequency, repeatable = repeatable, legendary = legendary,
            important = important, meta = meta, infoID = infoID }
    end
    for i = 1, call(GetNumActiveQuests) or 0 do
        local title, complete = call(GetActiveTitle, i)
        local questID = call(GetActiveQuestID, i)
        t.quests[#t.quests + 1] = { kind = "active", index = i, title = title, complete = complete == true,
            trivial = call(IsActiveQuestTrivial, i), questID = questID, level = Data.QuestLevel(questID) }
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
        -- Only a choice can be a currency here. The game reads every fixed reward as an
        -- item (its currencies come apart, Data.Currencies), so it never asks for those.
        local loot = kind == "choice" and call(GetQuestItemInfoLootType, kind, i) or 0
        local it
        if loot == nil or loot == 0 then
            local name, texture, count, quality, usable, itemID = call(GetQuestItemInfo, kind, i)
            if name then
                it = { kind = kind, index = i, name = name, texture = texture, count = count, quality = quality,
                    usable = usable, itemID = itemID, sell = sellPrice(itemID or call(GetQuestItemLink, kind, i)) }
            else
                it = { kind = kind, index = i, loading = true, texture = texture, count = count, itemID = itemID }
            end
        elseif C_QuestOffer and fn(C_QuestOffer.GetQuestRewardCurrencyInfo) then
            local ok, c = pcall(C_QuestOffer.GetQuestRewardCurrencyInfo, kind, i)
            if ok and type(c) == "table" then
                it = { kind = kind, index = i, currency = true, currencyID = c.currencyID, name = c.name, texture = c.texture,
                    count = c.totalRewardAmount or c.baseRewardAmount, quality = c.quality }
            end
        end
        out[#out + 1] = it or { kind = kind, index = i, loading = true }
    end
    return out
end

-- Currencies the quest always gives (not a choice). The game lists them apart from
-- its item rewards (QuestInfo.lua's C_QuestInfoSystem.GetQuestRewardCurrencies), and
-- its tooltip reads them by this order: SetQuestCurrency("reward", i).
function Data.Currencies(questID)
    if type(questID) ~= "number" or questID <= 0 or not (C_QuestInfoSystem and fn(C_QuestInfoSystem.GetQuestRewardCurrencies)) then return {} end
    local ok, list = pcall(C_QuestInfoSystem.GetQuestRewardCurrencies, questID)
    local out = {}
    if not ok or type(list) ~= "table" then return out end
    for i, c in ipairs(list) do
        if type(c) == "table" then
            local name, texture, count, quality = c.name, c.texture, c.totalRewardAmount or c.baseRewardAmount, c.quality
            -- Some currencies show as a container (a bag of them), as the game's window does.
            local util = CurrencyContainerUtil
            if c.currencyID and type(util) == "table" and fn(util.GetCurrencyContainerInfo) then
                local okC, n2, t2, a2, q2 = pcall(util.GetCurrencyContainerInfo, c.currencyID, count, name, texture, quality)
                if okC and n2 then name, texture, count, quality = n2, t2, a2, q2 end
            end
            out[#out + 1] = { kind = "reward", index = i, currency = true, currencyID = c.currencyID,
                name = name, texture = texture, count = count, quality = quality }
        end
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
    local fixed = (call(GetNumQuestRewards) or 0) + #Data.Currencies(d.questID)
    if (call(GetNumQuestChoices) or 0) ~= #d.choices or fixed ~= #d.rewards then return true end
    if (call(GetRewardMoney) or 0) ~= d.money or (call(GetRewardXP) or 0) ~= d.xp then return true end
    for _, list in ipairs({ d.choices, d.rewards }) do
        for _, it in ipairs(list) do
            if it.loading and call(GetQuestItemInfo, it.kind, it.index) then return true end
        end
    end
    return false
end

-- The icon the game's gossip and greeting give an offered quest
-- (QuestUtil.GetQuestIconOfferForQuestID: repeatable, legendary, recurring...), as
-- asset, isAtlas. Nil for a plain one, which keeps Daylight UI's gold "!".
Data.PLAIN_OFFER = "Interface/GossipFrame/AvailableQuestIcon"
function Data.OfferIcon(q)
    local U = QuestUtil
    if type(U) ~= "table" or not fn(U.GetQuestIconOfferForQuestID) or type(q.questID) ~= "number" then return nil end
    local ok, asset, isAtlas = DUI.SafeReturn(U.GetQuestIconOfferForQuestID, q.questID, q.legendary, q.frequency, q.repeatable,
        q.important, q.meta, q.infoID)
    if not ok or type(asset) ~= "string" or asset == Data.PLAIN_OFFER then return nil end
    return asset, isAtlas == true
end

-- Spell rewards, grouped the way QuestInfo.lua heads them ("You will learn",
-- "The following will be cast on you"...), in its order. Spells already in the
-- spellbook are left out, as the game does.
local SPELL_ORDER = { "Follower", "Companion", "Tradeskill", "Ability", "Aura", "Spell", "Unlock",
    "QuestlineUnlock", "QuestlineReward", "QuestlineUnlockPart", "PossibleReward" }
local SPELL_HEADER = { Follower = "REWARD_FOLLOWER", Companion = "REWARD_COMPANION", Tradeskill = "REWARD_TRADESKILL_SPELL",
    Ability = "REWARD_ABILITY", Aura = "REWARD_AURA", Spell = "REWARD_SPELL", Unlock = "REWARD_UNLOCK",
    QuestlineUnlock = "REWARD_QUESTLINE_UNLOCK", QuestlineReward = "REWARD_QUESTLINE_REWARD",
    QuestlineUnlockPart = "REWARD_QUESTLINE_UNLOCK_PART", PossibleReward = "REWARD_POSSIBLE_QUEST_REWARD" }

-- The game's GetRewardSpellBucketType, by the enum's names.
local function spellKind(info)
    local T = Enum and Enum.QuestCompleteSpellType or {}
    if type(info.type) == "number" and info.type ~= (T.LegacyBehavior or 0) then
        for name, v in pairs(T) do if v == info.type then return name end end
    end
    if info.isTradeskill or info.isTradeskillSpell then return "Tradeskill" end
    if info.isBoostSpell then return "Ability" end
    if info.garrFollowerID then return "Follower" end
    if info.isSpellLearned then return "Spell" end
    if info.genericUnlock then return "Unlock" end
    return "Aura"
end

local function known(spellID)
    if not (C_SpellBook and fn(C_SpellBook.IsSpellInSpellBook)) then return false end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local ok, yes = DUI.SafeReturn(C_SpellBook.IsSpellInSpellBook, spellID, bank, true)
    return ok and yes == true
end

-- { { header = text or nil, list = { { spell = true, spellID, name, texture } } } }
function Data.Spells(questID)
    local S = C_QuestInfoSystem
    if type(questID) ~= "number" or questID <= 0 or not (S and fn(S.GetQuestRewardSpells) and fn(S.GetQuestRewardSpellInfo)) then return {} end
    local ok, ids = DUI.SafeReturn(S.GetQuestRewardSpells, questID)
    if not ok or type(ids) ~= "table" then return {} end
    local buckets = {}
    for _, id in ipairs(ids) do
        local okI, info = false, nil
        if type(id) == "number" and id > 0 then okI, info = DUI.SafeReturn(S.GetQuestRewardSpellInfo, questID, id) end
        if okI and type(info) == "table" and info.texture and not known(id)
            and (not info.isBoostSpell or call(IsCharacterNewlyBoosted) == true) then
            local kind = spellKind(info)
            local b = buckets[kind]
            if not b then
                local word = _G[SPELL_HEADER[kind] or ""]
                b = { header = not info.hideSpellLearnText and (type(word) == "string" and word or DUI.L["You'll learn:"]) or nil, list = {} }
                buckets[kind] = b
            end
            b.list[#b.list + 1] = { spell = true, spellID = id, name = info.name, texture = info.texture }
        end
    end
    local out = {}
    for _, kind in ipairs(SPELL_ORDER) do if buckets[kind] then out[#out + 1] = buckets[kind] end end
    return out
end

-- Skill points and honor, the rewards QuestInfo.lua draws beside the items.
local HONOR_ICON = { Horde = "Interface\\Icons\\PVPCurrency-Honor-Horde", Alliance = "Interface\\Icons\\PVPCurrency-Honor-Alliance" }
local function extras()
    local out = {}
    local skill, icon, points = call(GetRewardSkillPoints)
    if type(points) == "number" and points > 0 then
        local name = skill and (type(BONUS_SKILLPOINTS) == "string" and BONUS_SKILLPOINTS:format(skill)
            or string.format(DUI.L["%s skill points"], skill)) or ""
        local tip = skill and type(BONUS_SKILLPOINTS_TOOLTIP) == "string" and BONUS_SKILLPOINTS_TOOLTIP:format(points, skill) or nil
        out[#out + 1] = { extra = "skill", name = name, texture = icon, count = points, tip = tip }
    end
    local honor = call(GetRewardHonor)
    if type(honor) == "number" and honor > 0 then
        local faction = fn(UnitFactionGroup) and UnitFactionGroup("player") or nil
        out[#out + 1] = { extra = "honor", name = HONOR or DUI.L["Honor"], texture = HONOR_ICON[faction] or HONOR_ICON.Alliance, count = honor }
    end
    return out
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
        t.group = call(GetSuggestedGroupSize) or 0
        local spellID, name, texture = call(GetCriteriaSpell)
        if type(spellID) == "number" and spellID > 0 then
            t.criteria = { spell = true, spellID = spellID, name = name, texture = texture }
        end
    elseif mode == "progress" then
        t.text = call(GetProgressText) or ""
        t.completable = call(IsQuestCompletable) == true
        t.required = {}
        -- As QuestFrameProgressItems_Update: the offer can hide its items, an item
        -- not loaded yet keeps its slot, and required currencies follow.
        local hide = C_QuestOffer and call(C_QuestOffer.GetHideRequiredItems) == true
        for i = 1, not hide and call(GetNumQuestItems) or 0 do
            if call(IsQuestItemHidden, i) ~= 1 then
                local name, texture, count, quality, _, itemID = call(GetQuestItemInfo, "required", i)
                t.required[#t.required + 1] = { kind = "required", index = i, name = name, texture = texture, count = count,
                    quality = quality, itemID = itemID, loading = name == nil or nil }
            end
        end
        for i = 1, call(GetNumQuestCurrencies) or 0 do
            local c = C_QuestOffer and call(C_QuestOffer.GetQuestRequiredCurrencyInfo, i)
            if type(c) == "table" then
                t.required[#t.required + 1] = { kind = "required", index = i, currency = true, currencyID = c.currencyID,
                    name = c.name, texture = c.texture, count = c.requiredAmount, quality = c.quality }
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
        for _, c in ipairs(Data.Currencies(t.questID)) do t.rewards[#t.rewards + 1] = c end
        t.money = call(GetRewardMoney) or 0
        t.xp = call(GetRewardXP) or 0
        t.spells = Data.Spells(t.questID)
        t.rewardTitle = call(GetRewardTitle)
        t.extras = extras()
    end
    t.level = Data.QuestLevel(t.questID)
    t.color = Data.QuestColor(t.questID, t.level)
    return t
end
