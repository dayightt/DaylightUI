-- Reads the game into a plain snapshot for the tracker: watched quests grouped by
-- zone (the quest log's headers), their objectives, items and timers, and tracked
-- achievements. No frames here. Every call is checked, so a missing API hides that
-- part instead of erroring.

local _, ns = ...

local Data = {}
ns.Data = Data

local L = DaylightUI.L
Data.READY = L["Ready to turn in"]   -- turn-in line when the game gives none
Data.AUTO = L["Click to complete"]
Data.OTHER = L["Other"]              -- quests the log lists under no header
Data.LOG_MAX = 25                 -- fallback when the game doesn't say

local function pick(ok, ...) if ok then return ... end end
-- Calls fn if it exists. Does nothing (no error) if it doesn't or if it fails.
local function call(fn, ...)
    if type(fn) == "function" then return pick(pcall(fn, ...)) end
end
local function api(t, name) return type(t) == "table" and t[name] or nil end

-- "5/8 Murloc Fin" or "Murloc Fin: 5/8" -> "Murloc Fin", true. Anything else
-- comes back unchanged, false.
function Data.SplitObjective(text)
    if type(text) ~= "string" then return "", false end
    local rest = text:match("^%s*%d+%s*/%s*%d+%s+(.+)$")
    if rest then return rest, true end
    rest = text:match("^(.-):?%s*%d+%s*/%s*%d+%s*$")
    if rest and rest ~= "" then return rest, true end
    return text, false
end

function Data.Objectives(questID)
    local list = call(api(C_QuestLog, "GetQuestObjectives"), questID)
    local out = {}
    if type(list) ~= "table" then return out end
    for i, o in ipairs(list) do
        if type(o) == "table" then
            local text = type(o.text) == "string" and o.text or ""
            local obj = { index = i, done = o.finished == true, type = o.type }
            if o.type == "progressbar" then
                local pct = call(GetQuestProgressBarPercent, questID)
                obj.kind = "bar"
                obj.pct = type(pct) == "number" and math.floor(pct + 0.5) or 0
                obj.text = (text:gsub(":?%s*%d+%%%s*$", ""))
            else
                local label, counted = Data.SplitObjective(text)
                obj.text = label
                if counted and type(o.numRequired) == "number" and o.numRequired > 0 then
                    obj.kind, obj.have, obj.need = "count", o.numFulfilled or 0, o.numRequired
                else
                    obj.kind = "text"
                end
            end
            if obj.text ~= "" or obj.kind == "bar" then out[#out + 1] = obj end
        end
    end
    return out
end

-- questID -> its quest log header, and each header's position in the log. Also
-- questID -> its log index and log info, read once here so Data.Quest doesn't
-- have to look them up again.
function Data.Headers()
    local of, rank, indexOf, infoOf = {}, {}, {}, {}
    local n = call(api(C_QuestLog, "GetNumQuestLogEntries"))
    local header
    for i = 1, (type(n) == "number" and n or 0) do
        local info = call(api(C_QuestLog, "GetInfo"), i)
        if type(info) == "table" then
            if info.isHeader then
                header = info.title
                if type(header) == "string" and not rank[header] then rank[header] = i end
            elseif type(info.questID) == "number" then
                of[info.questID] = header
                if not indexOf[info.questID] then indexOf[info.questID], infoOf[info.questID] = i, info end
            end
        end
    end
    return of, rank, indexOf, infoOf
end

-- A watched quest the log walk didn't place under a header (a collapsed header can
-- leave its quests out), so ask for its header directly.
function Data.HeaderFor(questID)
    local i = call(api(C_QuestLog, "GetHeaderIndexForQuest"), questID)
    local info = type(i) == "number" and call(api(C_QuestLog, "GetInfo"), i)
    return type(info) == "table" and type(info.title) == "string" and info.title or nil
end

function Data.Timers()
    local out = {}
    local list = call(api(C_QuestLog, "GetQuestTimers"))
    if type(list) ~= "table" then return out end
    for _, t in ipairs(list) do
        if type(t) == "table" and type(t.questID) == "number" and type(t.questTimer) == "number" then
            out[t.questID] = t.questTimer
        end
    end
    return out
end

-- Seconds left on a quest, or nil if it isn't timed. Uses the timer list, else
-- what the game's own tracker checks (total, elapsed, elapsed < total).
function Data.TimeLeft(questID, timers)
    if timers and timers[questID] then return timers[questID] end
    local total, elapsed = call(api(C_QuestLog, "GetTimeAllowed"), questID)
    if type(total) == "number" and type(elapsed) == "number" and elapsed < total then
        return total - elapsed
    end
end

-- A quest's type as the game's own log tags it (Forever's
-- QuestUtilsOverrides.GetQuestTagText: "(Elite)", "(Dungeon)", "(Raid)", "(PvP)"):
-- elite | dungeon | raid | pvp, or nil. An elite quest without the tag still counts
-- (the log's "[22+]" comes from IsEliteQuest).
local QC = Constants and Constants.QuestConsts or {}
Data.TAGS = {
    [QC.QUEST_INFO_ELITE_ID or 1] = "elite",
    [QC.QUEST_INFO_DUNGEON_ID or 81] = "dungeon",
    [QC.QUEST_INFO_RAID_ID or 62] = "raid",
    [QC.QUEST_INFO_PVP_ID or 41] = "pvp",
}
function Data.Tag(questID)
    local QL = C_QuestLog
    local info = call(api(QL, "GetQuestTagInfo"), questID)
    local id = type(info) == "table" and info.tagID or nil
    local kind = type(id) == "number" and Data.TAGS[id] or nil
    if not kind and call(api(QL, "IsEliteQuest"), questID) == true then kind = "elite" end
    return kind
end

-- How many party members are on this quest, the game's own count
-- (QuestUtils_GetNumPartyMembersOnQuest, the log's "[2]"). In a raid, only the
-- player's subgroup.
function Data.PartyOn(questID)
    local members = call(GetNumSubgroupMembers)
    local n = 0
    for i = 1, type(members) == "number" and members or 0 do
        if call(api(C_QuestLog, "IsUnitOnQuest"), "party" .. i, questID) == true then n = n + 1 end
    end
    return n
end

-- index, info: the quest's log index and log info if the caller already read them.
-- focus: the priority quest's id, same idea. Anything missing is looked up here.
function Data.Quest(questID, timers, zone, index, info, focus)
    local QL = C_QuestLog
    if type(index) ~= "number" or type(info) ~= "table" then
        index = call(api(QL, "GetLogIndexForQuestID"), questID)
        if type(index) ~= "number" then return nil end
        info = call(api(QL, "GetInfo"), index)
    end
    if type(info) ~= "table" then return nil end
    local title = type(info.title) == "string" and info.title or call(api(QL, "GetTitleForQuestID"), questID)
    local q = { id = questID, logIndex = index, level = info.level, zone = zone,
                title = type(title) == "string" and title or "?" }
    q.diff = DaylightUI.Npc.Data.QuestColor(questID, info.level)
    q.tag = Data.Tag(questID)
    q.party = Data.PartyOn(questID)
    -- Voiced by Spoken: a Play button on its title (Voice.lua).
    q.voice = ns.Voice ~= nil and ns.Voice.Has(questID) or nil
    if call(api(QL, "IsFailed"), questID) then
        q.state = "failed"
    elseif call(api(QL, "IsComplete"), questID) or call(api(QL, "ReadyForTurnIn"), questID) then
        q.state = "ready"
    else
        q.state = "active"
    end
    q.auto = q.state == "ready" and info.isAutoComplete == true
    if q.state == "ready" then
        local text = call(GetQuestLogCompletionText, index)
        q.turnIn = q.auto and Data.AUTO or ((type(text) == "string" and text ~= "") and text or Data.READY)
    end
    q.objs = Data.Objectives(questID)
    local link, icon, charges = call(GetQuestLogSpecialItemInfo, index)
    if type(link) == "string" then q.item = { link = link, icon = icon, charges = charges } end
    q.timer = Data.TimeLeft(questID, timers)
    if focus == nil then focus = call(api(C_SuperTrack, "GetSuperTrackedQuestID")) end
    q.focus = focus == questID
    return q
end

function Data.Achievements()
    local out = {}
    local kinds = type(Enum) == "table" and Enum.ContentTrackingType
    local ids = kinds and kinds.Achievement and call(api(C_ContentTracking, "GetTrackedIDs"), kinds.Achievement)
    if type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        local _, name, _, completed = call(GetAchievementInfo, id)
        if type(name) == "string" then
            local a = { id = id, title = name, done = completed == true, objs = {} }
            local n = call(GetAchievementNumCriteria, id)
            for i = 1, (type(n) == "number" and n or 0) do
                local text, _, got, have, need = call(GetAchievementCriteriaInfo, id, i)
                if type(text) == "string" and text ~= "" and not got then
                    local o = { index = i, text = text, done = false, kind = "text" }
                    if type(need) == "number" and need > 1 then o.kind, o.have, o.need = "count", have or 0, need end
                    a.objs[#a.objs + 1] = o
                end
            end
            out[#out + 1] = a
        end
    end
    return out
end

-- Quests to show: the watch list, or (filter "log") every quest in log order
-- without adding watches.
local function questIDs(filter, indexOf)
    local out = {}
    if filter == "log" then
        for id in pairs(indexOf) do out[#out + 1] = id end
        table.sort(out, function(a, b) return indexOf[a] < indexOf[b] end)
        return out
    end
    local n = call(api(C_QuestLog, "GetNumQuestWatches"))
    for i = 1, (type(n) == "number" and n or 0) do
        local id = call(api(C_QuestLog, "GetQuestIDForQuestWatchIndex"), i)
        if type(id) == "number" then out[#out + 1] = id end
    end
    return out
end

-- Where the player is, using the quest log's own name for it. Inside a dungeon the
-- zone text can differ from the log header (The Stockade, for one), so use the
-- instance or map name, whichever the log uses. has(name) says whether the log
-- has a header by that name.
function Data.Here(has)
    local real = call(GetRealZoneText)
    if type(real) ~= "string" or has(real) or not call(IsInInstance) then return real end
    local inst = call(GetInstanceInfo)
    if type(inst) == "string" and has(inst) then return inst end
    local M = C_Map
    local mapID = call(api(M, "GetBestMapForUnit"), "player")
    local info = mapID and call(api(M, "GetMapInfo"), mapID)
    if type(info) == "table" and type(info.name) == "string" and has(info.name) then return info.name end
    return real
end

function Data.Snapshot(filter)
    local QL = C_QuestLog
    local snap = { groups = {}, achievements = Data.Achievements() }
    local _, numQuests = call(api(QL, "GetNumQuestLogEntries"))
    snap.logCount = type(numQuests) == "number" and numQuests or 0
    local most = call(api(QL, "GetMaxNumQuestsCanAccept"))
    snap.logMax = type(most) == "number" and most or Data.LOG_MAX
    snap.realZone = call(GetRealZoneText)
    local headerOf, rank, indexOf, infoOf = Data.Headers()
    local timers = Data.Timers()
    local focus = call(api(C_SuperTrack, "GetSuperTrackedQuestID"))
    local byZone = {}
    for _, id in ipairs(questIDs(filter, indexOf)) do
        local zone = headerOf[id] or Data.HeaderFor(id) or Data.OTHER
        local q = zone and Data.Quest(id, timers, zone, indexOf[id], infoOf[id], focus)
        if q then
            local g = byZone[zone]
            if not g then
                g = { name = zone, quests = {} }
                byZone[zone] = g
                snap.groups[#snap.groups + 1] = g
            end
            g.quests[#g.quests + 1] = q
        end
    end
    snap.zone = Data.Here(function(name) return byZone[name] ~= nil end)
    table.sort(snap.groups, function(a, b)
        local ah, bh = a.name == snap.zone, b.name == snap.zone
        if ah ~= bh then return ah end
        return (rank[a.name] or math.huge) < (rank[b.name] or math.huge)
    end)
    return snap
end
