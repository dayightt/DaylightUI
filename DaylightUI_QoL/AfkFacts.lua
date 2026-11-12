-- Fun facts for the AFK screen, picked at random from what fits this character.
-- Each fact reads the game only when drawn, always out of combat. A fact whose
-- data is secret or missing is skipped.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Facts = {}
ns.AfkFacts = Facts

Facts.EVERY = 12                  -- seconds each fact stays
Facts.EPIC_MOUNT = 1000 * 10000   -- copper for an epic mount with its training (guess from classic prices; tune)
Facts.PROFESSIONS = {             -- skill line ids: primary and secondary professions
    [171] = true, [164] = true, [333] = true, [202] = true, [182] = true, [165] = true,
    [186] = true, [393] = true, [197] = true, [185] = true, [129] = true, [356] = true,
}

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function number(v) return type(v) == "number" and not secret(v) end
local function text(v) return type(v) == "string" and not secret(v) and v ~= "" end

local function num(n)
    local s = call(BreakUpLargeNumbers, math.floor(n))
    return type(s) == "string" and s or tostring(math.floor(n))
end

-- Tests swap this for a fixed answer.
function Facts.Random(n) return math.random(n) end

local function pick(list) return list[Facts.Random(#list)] end

local function atCap()
    local capped = call(IsPlayerAtEffectiveMaxLevel)
    if capped ~= nil then return capped == true end
    local max, level = call(GetMaxPlayerLevel), UnitLevel("player")
    return number(max) and number(level) and level >= max
end

local function level()
    local v = UnitLevel("player")
    return number(v) and v or nil
end

-- Gold when the module first woke this session (Enable), for "this session".
function Facts.Begin()
    local money = call(GetMoney)
    if Facts.startMoney == nil and number(money) then Facts.startMoney = money end
end

-- Each fact: a key and a reader giving (heading, line), or nil when it
-- doesn't fit right now. Order doesn't matter: the deck is shuffled.
Facts.LIST = {
    { key = "quests", read = function()
        local list = C_QuestLog and call(C_QuestLog.GetAllCompletedQuestIDs)
        if type(list) ~= "table" or secret(list) then return end
        local n = #list
        if n < 1 then return end
        return L["Quests"], string.format(pick({
            L["%s quests done. That's a lot of boar livers."],
            L["%s quests completed. Azeroth owes you one."],
            L["%s quests done, and every one of them was urgent."],
        }), num(n))
    end },
    { key = "honor", read = function()
        local kills = call(GetPVPLifetimeStats)
        if not number(kills) or kills < 1 then return end
        return L["Honor"], string.format(pick({
            L["%s honorable kills. The other faction remembers you."],
            L["%s honorable kills, and counting."],
        }), num(kills))
    end },
    { key = "profession", read = function()
        local S = C_SkillInfo
        local count = S and call(S.GetNumSkillLines)
        if not number(count) then return end
        local found = {}
        for i = 1, count do
            local s = call(S.GetSkillLineInfo, i)
            if type(s) == "table" and not s.isHeader and Facts.PROFESSIONS[s.skillID]
                and text(s.name) and number(s.rank) and number(s.maxRank) and s.rank > 0 then
                found[#found + 1] = s
            end
        end
        if #found == 0 then return end
        local s = pick(found)
        if s.rank >= 300 then
            return L["Professions"], string.format(L["%s at %d. A true master."], s.name, s.rank)
        elseif s.rank >= s.maxRank then
            return L["Professions"], string.format(L["%s %d / %d. Time to visit a trainer."], s.name, s.rank, s.maxRank)
        end
        return L["Professions"], string.format(L["%s %d / %d. %d more to go."], s.name, s.rank, s.maxRank, s.maxRank - s.rank)
    end },
    { key = "leveling", read = function()
        local lvl = level()
        if not lvl then return end
        if atCap() then
            return L["Leveling"], string.format(L["Level %d. Now it's all about the gear."], lvl)
        end
        local cur, max = call(UnitXP, "player"), call(UnitXPMax, "player")
        if not (number(cur) and number(max)) or max <= 0 then return end
        return L["Leveling"], string.format(pick({
            L["%s XP to level %d. You've got this."],
            L["%s XP until level %d."],
        }), num(max - cur), lvl + 1)
    end },
    { key = "resting", read = function()
        if atCap() or call(IsResting) ~= true then return end
        local rested, max = call(GetXPExhaustion), call(UnitXPMax, "player")
        if number(rested) and number(max) and max > 0 and rested >= max * 1.5 then
            return L["Resting"], L["Fully rested. Go spend it!"]
        end
        return L["Resting"], L["Resting at an inn. Free XP is piling up."]
    end },
    { key = "played", read = function()
        local p, Afk = ns.Afk.played, ns.Afk
        if not p then return end
        local now = GetTime() - p.at
        local total = p.total + now
        if number(p.level) and p.levelAt == level() and Facts.Random(2) == 1 then
            return L["Time played"], string.format(L["%s spent at level %d so far."], Afk.Played(p.level + now), p.levelAt)
        end
        local days = math.floor(total / 86400)
        if days >= 1 then
            return L["Time played"], string.format(L["%s played. That's %d whole days in Azeroth."], Afk.Played(total), days)
        end
        return L["Time played"], string.format(L["%s played. Just getting started."], Afk.Played(total))
    end },
    { key = "gold", read = function()
        local money = call(GetMoney)
        if not number(money) or money <= 0 then return end
        if atCap() and money < Facts.EPIC_MOUNT and Facts.Random(2) == 1 then
            return L["Gold"], string.format(L["Epic mount fund: %d%%. Keep saving!"], math.floor(money / Facts.EPIC_MOUNT * 100))
        end
        return L["Gold"], string.format(L["You carry %s."], DUI.MoneyString(money))
    end },
    { key = "account", read = function()
        local chars = DUI.DB.Root().characters
        if type(chars) ~= "table" then return end
        local total, n = 0, 0
        for _, c in pairs(chars) do
            if type(c) == "table" and number(c.money) then total, n = total + c.money, n + 1 end
        end
        if n < 2 or total <= 0 then return end
        return L["Gold"], string.format(L["%s across your %d characters."], DUI.MoneyString(total), n)
    end },
    { key = "earned", read = function()
        local money = call(GetMoney)
        if not (number(money) and number(Facts.startMoney)) or money <= Facts.startMoney then return end
        return L["This session"], string.format(L["+%s since you logged in. Nice."], DUI.MoneyString(money - Facts.startMoney))
    end },
    { key = "pet", read = function()
        if call(UnitExists, "pet") ~= true then return end
        local name = call(UnitName, "pet")
        if not text(name) then return end
        return L["Your pet"], string.format(pick({
            L["%s is waiting patiently."],
            L["%s wonders where you went."],
            L["%s is guarding your spot."],
        }), name)
    end },
    { key = "guild", read = function()
        if call(IsInGuild) ~= true then return end
        local _, online = call(GetNumGuildMembers)
        if not number(online) or online < 2 then return end
        return L["Guild"], string.format(pick({
            L["%d guildmates online, and you're away."],
            L["%d guildmates online. Say hi when you're back."],
        }), online - 1)
    end },
    { key = "away", read = function()
        local Afk = ns.Afk
        local gone = GetTime() - (Afk.since or GetTime())
        if gone < 600 then return end
        if gone >= 3600 then return L["Away"], L["Over an hour away. Still here, still waiting."] end
        if gone >= 1800 then return L["Away"], string.format(L["%s away. The innkeeper stopped asking."], Afk.Played(gone)) end
        return L["Away"], string.format(L["%s away. Your character is getting stiff."], Afk.Played(gone))
    end },
    { key = "night", read = function()
        local hour = tonumber(date("%H"))
        if not hour then return end
        if hour < 5 then
            return L["Late night"], string.format(L["It's %s. Just one more quest?"], ns.Afk.TimeOfDay())
        elseif hour < 8 then
            return L["Early start"], L["Up early. Even the murlocs are still asleep."]
        end
    end },
}

local byKey = {}
for _, f in ipairs(Facts.LIST) do byKey[f.key] = f end

function Facts.Read(key)
    local f = byKey[key]
    if not f then return end
    local ok, head, line = pcall(f.read)
    if ok and text(head) and text(line) then return head, line end
end

-- A fresh shuffled deck of every fact that fits now; the last one shown
-- never comes first, so nothing repeats back to back.
function Facts.Shuffle(last)
    local deck = {}
    for _, f in ipairs(Facts.LIST) do
        if Facts.Read(f.key) then deck[#deck + 1] = f.key end
    end
    for i = #deck, 2, -1 do
        local j = Facts.Random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    if #deck > 1 and deck[#deck] == last then deck[1], deck[#deck] = deck[#deck], deck[1] end
    return deck
end

-- The next fact to show: (key, heading, line), or nil when none fits.
function Facts.Next()
    for _ = 1, 2 do
        if not Facts.deck or #Facts.deck == 0 then Facts.deck = Facts.Shuffle(Facts.last) end
        while #Facts.deck > 0 do
            local key = table.remove(Facts.deck)
            local head, line = Facts.Read(key)
            if head then
                Facts.last = key
                return key, head, line
            end
        end
    end
end

-- A new deck each time the screen comes up.
function Facts.Reset() Facts.deck = nil end
