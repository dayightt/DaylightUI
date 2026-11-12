-- Quest locations from QuestieDB, when the player has it installed (a separate
-- addon, never bundled). Each spot is { map = uiMapID, x, y } with x, y in 0-1,
-- the way the map uses them.
--
-- QuestieDB exposes globals QuestDB, NpcDB, ObjectDB and ItemDB. Spawns are keyed
-- by AreaID in 0-100 ({ [areaID] = { {x, y}, ... } }) and converted to UiMapIDs
-- with its ZoneDB table. Every read returns a fresh copy, so anything read once is
-- cached here for the session.
--
-- A quest's objectives line up with the log's by type and order: the k-th
-- "monster" line in the log is the k-th creature objective, and so on.

local _, ns = ...

local Spots = {
    CONTRACT = 1,
    -- QuestieDB's objective groups (QuestDB.objectives): creature, object, item,
    -- reputation, kill credit, spell.
    GROUP = { monster = { 1, 5 }, object = { 2 }, item = { 3 } },
}
ns.Spots = Spots

local ready, areaToMap
local byEntity = {}   -- ["npc:123"] = spots
local byQuest = {}    -- [questID] = { done = { finished flags }, out = ByObjective's answer }

local function lib() return _G.LibQuestieDB end

-- QuestieDB is loaded and speaks the expected version of its API.
function Spots.Ready()
    if ready ~= nil then return ready end
    local L = lib()
    ready = false
    if type(L) ~= "table" or type(_G.QuestDB) ~= "table" or type(_G.NpcDB) ~= "table" then return false end
    if type(L.RequireContract) == "function" then
        local ok, yes = pcall(L.RequireContract, Spots.CONTRACT)
        if not ok or not yes then return false end
    end
    ready = true
    return true
end

-- AreaID -> UiMapID, from QuestieDB's ZoneDB (a Lua table stored as text).
local function mapOf(area)
    if areaToMap == nil then
        areaToMap = false
        local L = lib()
        local ok, zones = pcall(L.Support.Get, "ZoneDB")
        local src = ok and type(zones) == "table" and type(zones.private) == "table" and zones.private.areaIdToUiMapId
        if type(src) == "table" then
            areaToMap = src
        elseif type(src) == "string" then
            local fn = loadstring(src) or loadstring("return " .. src)
            local good, t = false, nil
            if fn then good, t = pcall(fn) end
            if good and type(t) == "table" then areaToMap = t end
        end
    end
    return areaToMap and areaToMap[area] or nil
end

local function get(db, id, key)
    db = _G[db]
    if type(db) ~= "table" or type(db.Get) ~= "function" or type(id) ~= "number" then return nil end
    local ok, v = pcall(db.Get, id, key)
    if ok then return v end
end

-- One field of a quest in QuestieDB (name, questLevel, specialFlags...). nil
-- without QuestieDB or when it speaks another API version. Tables come back as a
-- fresh copy each time, so cache anything read often.
function Spots.Quest(questID, key)
    if not Spots.Ready() then return nil end
    return get("QuestDB", questID, key)
end

-- { [areaID] = { {x, y}, ... } } -> spots, appended to `out`.
local function addSpawns(out, spawns)
    if type(spawns) ~= "table" then return end
    for area, list in pairs(spawns) do
        local map = mapOf(area)
        if map and type(list) == "table" then
            for _, p in ipairs(list) do
                -- -1, -1 means inside an instance, so no map spot.
                if type(p) == "table" and type(p[1]) == "number" and p[1] >= 0 and type(p[2]) == "number" and p[2] >= 0 then
                    out[#out + 1] = { map = map, x = p[1] / 100, y = p[2] / 100 }
                end
            end
        end
    end
end

local function entity(kind, id)
    local key = kind .. ":" .. tostring(id)
    local have = byEntity[key]
    if have then return have end
    local out = {}
    if kind == "npc" then
        addSpawns(out, get("NpcDB", id, "spawns"))
    elseif kind == "object" then
        addSpawns(out, get("ObjectDB", id, "spawns"))
    elseif kind == "item" then
        for _, npc in ipairs(get("ItemDB", id, "npcDrops") or {}) do
            for _, s in ipairs(entity("npc", npc)) do out[#out + 1] = s end
        end
        for _, obj in ipairs(get("ItemDB", id, "objectDrops") or {}) do
            for _, s in ipairs(entity("object", obj)) do out[#out + 1] = s end
        end
    end
    byEntity[key] = out
    return out
end

local function append(out, list)
    for _, s in ipairs(list) do out[#out + 1] = s end
end

-- Spots for one objective group entry: an id, or kill credit's list of ids.
local function entrySpots(group, entry)
    local out = {}
    if type(entry) ~= "table" then return out end
    if group == 5 then
        for _, npc in ipairs(type(entry[1]) == "table" and entry[1] or {}) do append(out, entity("npc", npc)) end
    elseif group == 1 then
        append(out, entity("npc", entry[1]))
    elseif group == 2 then
        append(out, entity("object", entry[1]))
    elseif group == 3 then
        append(out, entity("item", entry[1]))
    end
    return out
end

-- The quest's objectives from the log: { type, finished } in order.
local function logObjectives(questID)
    local QL = _G.C_QuestLog
    if type(QL) ~= "table" or type(QL.GetQuestObjectives) ~= "function" then return {} end
    local ok, list = pcall(QL.GetQuestObjectives, questID)
    return ok and type(list) == "table" and list or {}
end

-- Reuse the last answer while the same objectives are finished, since the
-- nameplates' quest symbol and the arrow ask over and over.
local function kept(questID, list)
    local k = byQuest[questID]
    if not k or #k.done ~= #list then return nil end
    for i, o in ipairs(list) do
        if k.done[i] ~= (type(o) == "table" and o.finished == true) then return nil end
    end
    return k.out
end

-- Where each unfinished objective is: { [log index] = spots }. Shared table,
-- read only.
function Spots.ByObjective(questID)
    if not Spots.Ready() then return {} end
    local list = logObjectives(questID)
    local was = kept(questID, list)
    if was then return was end
    local groups = get("QuestDB", questID, "objectives") or {}
    local seen = {}     -- [log type] = how many of that type so far
    local out, done, npcs = {}, {}, {}
    for i, o in ipairs(list) do
        done[i] = type(o) == "table" and o.finished == true
        local t = type(o) == "table" and o.type
        if type(t) == "string" then
            seen[t] = (seen[t] or 0) + 1
            if o.finished ~= true then
                local k, spots = seen[t], {}
                for _, g in ipairs(Spots.GROUP[t] or {}) do
                    local entry = type(groups[g]) == "table" and groups[g][k]
                    if entry then
                        append(spots, entrySpots(g, entry))
                        -- The creatures it names, for the nameplates' quest symbol: kind kill, or loot
                        -- for an item they drop.
                        if g == 1 and type(entry[1]) == "number" then npcs[i] = { entry[1], kind = "kill" }
                        elseif g == 5 and type(entry[1]) == "table" then
                            npcs[i] = { kind = "kill" }
                            for _, id in ipairs(entry[1]) do table.insert(npcs[i], id) end
                        elseif g == 3 and type(entry[1]) == "number" then
                            npcs[i] = { kind = "loot" }
                            for _, id in ipairs(get("ItemDB", entry[1], "npcDrops") or {}) do table.insert(npcs[i], id) end
                        end
                        break
                    end
                end
                if t == "event" then
                    local trig = get("QuestDB", questID, "triggerEnd")
                    if type(trig) == "table" then addSpawns(spots, trig[2]) end
                end
                if #spots > 0 then out[i] = spots end
            end
        end
    end
    byQuest[questID] = { done = done, out = out, npcs = npcs }
    return out
end

-- Creatures each unfinished objective names: { [log index] = { npcID, ... } }.
function Spots.ObjectiveNpcs(questID)
    Spots.ByObjective(questID)
    local k = byQuest[questID]
    return k and k.npcs or {}
end

-- Does a quest in the log still need this creature? Returns the kind of the first
-- unfinished objective naming it (kill, or loot when it drops a needed item) and
-- that quest's id; nil if none.
function Spots.NeedsNpc(npcID)
    if type(npcID) ~= "number" or not Spots.Ready() then return nil end
    local QL = C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return nil end
    local n = QL.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = QL.GetInfo(i)
        local id = type(info) == "table" and not info.isHeader and info.questID
        if type(id) == "number" and not (QL.IsComplete and QL.IsComplete(id)) then
            for _, list in pairs(Spots.ObjectiveNpcs(id)) do
                for _, who in ipairs(list) do
                    if who == npcID then return list.kind, id end
                end
            end
        end
    end
    return nil
end

-- Where the unfinished objectives are, as a list of spots. Cached while the
-- objectives stay the same, since the arrow asks every second for every tracked
-- quest (thousands of spots). Shared table, read only.
local objectivesOf = {}   -- [questID] = { by = ByObjective's answer, out = spots }
function Spots.Objectives(questID)
    local by = Spots.ByObjective(questID)
    local k = objectivesOf[questID]
    if k and k.by == by then return k.out end
    local out = {}
    for i = 1, table.maxn(by) do
        if by[i] then append(out, by[i]) end
    end
    objectivesOf[questID] = { by = by, out = out }
    return out
end

-- Who ends a quest: QuestieDB's finishedBy as { npcs = { id... }, objects =
-- { id... } }. Cached since it never changes, every read is a fresh copy, and an
-- NPC tooltip asks for each quest in the log.
local NONE = {}
local endsOf = {}
local function finishers(questID)
    local have = endsOf[questID]
    if have then return have end
    local ends = get("QuestDB", questID, "finishedBy")
    local out = { npcs = {}, objects = {} }
    if type(ends) == "table" then
        for _, id in ipairs(type(ends[1]) == "table" and ends[1] or NONE) do
            if type(id) == "number" then out.npcs[#out.npcs + 1] = id end
        end
        for _, id in ipairs(type(ends[2]) == "table" and ends[2] or NONE) do
            if type(id) == "number" then out.objects[#out.objects + 1] = id end
        end
    end
    endsOf[questID] = out
    return out
end

-- NPCs a quest is turned in to: { npcID, ... } (cached). Shared table, read only.
function Spots.Enders(questID)
    if not Spots.Ready() or type(questID) ~= "number" then return NONE end
    return finishers(questID).npcs
end

-- Where to turn it in: the NPCs and objects that end it (cached, they never
-- change). Shared table, read only.
local turnInOf = {}
function Spots.TurnIn(questID)
    if not Spots.Ready() or type(questID) ~= "number" then return {} end
    if turnInOf[questID] then return turnInOf[questID] end
    local out = {}
    local ends = finishers(questID)
    for _, npc in ipairs(ends.npcs) do append(out, entity("npc", npc)) end
    for _, obj in ipairs(ends.objects) do append(out, entity("object", obj)) end
    turnInOf[questID] = out
    return out
end
