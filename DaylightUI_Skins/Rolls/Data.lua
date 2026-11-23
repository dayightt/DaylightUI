-- Every open loot roll and what the group has done on it. Three sources feed it:
-- the game's roll events (the item, your own pick, your Need number), the Loot
-- History (everyone's pick, roll and the winner) and the chat lines (the same,
-- for whatever the history lacks). The winner always comes from the game; the
-- order players are listed in is only for showing.

local _, ns = ...
local DUI = DaylightUI

local RollData = {
    GRACE = 5, -- seconds past a roll's time with no result before it ends as "No result seen."
    RANK = { need = 4, transmog = 3, greed = 2, disenchant = 2, pass = 0, choosing = -1 },
    ID = { pass = 0, need = 1, greed = 2, disenchant = 3, transmog = 4 }, -- RollOnLoot's numbers
    -- Enum.EncounterLootDropRollState: NeedMainSpec, NeedOffSpec, Transmog, Greed, NoRoll, Pass.
    STATE = { [0] = "need", [1] = "need", [2] = "transmog", [3] = "greed", [4] = "choosing", [5] = "pass" },
    drops = {},
    -- Rolls that ended or were put away this session, so a zone change doesn't
    -- bring them back: game roll ids, and "encounter:key" for the Loot History.
    ended = {},
}
ns.RollData = RollData

local function fire(rollID, what) DUI.Fire("RollChanged", rollID, what) end

-- The Loot History's fields may come back secret under the client's restrictions.
local function plain(v, kind)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == kind then return v end
end

-- Rolls only happen in a group; out of one, nothing more comes for any roll.
local function grouped()
    return type(IsInGroup) ~= "function" or IsInGroup() == true
end

local function historyKey(encounterID, key) return encounterID .. ":" .. key end

local function itemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end
local function itemName(link) return type(link) == "string" and link:match("%[(.-)%]") or nil end

-- Same item: by link, or by name when one side only has "[Name]".
local function sameItem(drop, link)
    if type(link) ~= "string" then return false end
    if drop.link == link then return true end
    local a, b = itemID(drop.link), itemID(link)
    if a and b then return a == b and itemName(drop.link) == itemName(link) end
    return itemName(link) ~= nil and itemName(link) == (drop.name or itemName(drop.link))
end
RollData.SameItem = sameItem

-- Oldest first, so the first of two copies pairs with the first lines.
local function oldest(test)
    local best
    for _, d in pairs(RollData.drops) do
        if test(d) and (not best or d.start < best.start or (d.start == best.start and d.rollID < best.rollID)) then
            best = d
        end
    end
    return best
end

local function nextSeq(drop)
    drop.seq = (drop.seq or 0) + 1
    return drop.seq
end

local function ownName()
    local name = UnitName and UnitName("player")
    return plain(name, "string") or "?"
end

local function addPlayer(drop, key, first, full)
    local p = { key = key, first = first, name = full }
    drop.players[key] = p
    drop.order[#drop.order + 1] = key
    return p
end

local function forget(drop, key)
    drop.players[key] = nil
    for i, k in ipairs(drop.order) do
        if k == key then table.remove(drop.order, i) break end
    end
end

-- A player on a drop, kept under their first name: chat can name them shorter
-- than the history does. A second player with the same first name gets their
-- full name as the key.
local function playerOf(drop, name, self)
    if self and drop.me then
        local p = drop.players[drop.me]
        if name then
            local first, full = ns.RollChat.Names(name)
            if drop.me ~= first then
                -- First seen as "you", now named by the history. An entry made
                -- from your name before (a twin's "has one") folds into yours.
                local other = drop.players[first]
                if other and other ~= p then
                    p.hasOne = p.hasOne or other.hasOne
                    forget(drop, first)
                end
                drop.players[drop.me] = nil
                for i, k in ipairs(drop.order) do if k == drop.me then drop.order[i] = first end end
                p.key, p.first = first, first
                drop.players[first], drop.me = p, first
            end
            if #full > #(p.name or "") then p.name = full end
        end
        return p
    end
    if self then name = name or ownName() end
    if type(name) ~= "string" then return nil end
    local first, full = ns.RollChat.Names(name)
    local p, key = drop.players[full], first
    if not p then
        local q = drop.players[first]
        if q and full:find(" ", 1, true) and q.name and q.name:find(" ", 1, true) and q.name ~= full then
            key = full
        else
            p = q
        end
    end
    if not p then
        p = addPlayer(drop, key, first, full)
    elseif #full > #(p.name or "") then
        p.name = full
    end
    if self then p.self = true; drop.me = p.key end
    return p
end

local mend

-- A pick. Your own, once the game says so, is what you picked, whatever was pressed.
-- record: it came from a chat line or the Loot History, which may name the wrong
-- copy of an item until mend has checked it.
local function setPick(drop, p, pick, offSpec, record)
    if not pick or pick == "choosing" then return false end
    local changed = not (p.pick == pick and (not offSpec or p.offSpec))
    p.pick = pick
    if offSpec then p.offSpec = true end
    p.seq = p.seq or nextSeq(drop)
    if p.self then
        if record then drop.said = pick else drop.took = pick end
        if drop.mine ~= pick then drop.mine = pick; changed = true end
        drop.pending = nil
        if pick ~= "pass" then drop.timedOut = nil end
    end
    return changed
end

local function finish(drop, now)
    if drop.done then return end
    drop.done = true
    drop.doneAt = now or GetTime()
end

local function twinsHaveOne(drop, p)
    for _, twin in ipairs(RollData.Twins(drop)) do
        local q = playerOf(twin, p.name or p.first, p.self)
        if q then q.hasOne = true end
    end
end

local function setWinner(drop, p, now)
    if drop.winner == p.key then return false end
    drop.winner = p.key
    p.won = true
    finish(drop, now)
    twinsHaveOne(drop, p)
    return true
end

-- The game started a roll: the item from its roll API.
function RollData.Start(rollID, rollTime, now)
    if RollData.drops[rollID] then return RollData.drops[rollID] end
    local icon, name, count, quality, bop, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed,
        reasonDisenchant, _, canTransmog = GetLootRollItemInfo(rollID)
    -- No name: the game drops such a roll too (GroupLootFrame_OnShow).
    if type(name) ~= "string" then return nil end
    local link = GetLootRollItemLink(rollID)
    local ms = rollTime or (C_Loot and C_Loot.GetLootRollDuration and C_Loot.GetLootRollDuration(rollID)) or 60000
    local drop = {
        rollID = rollID, link = link, itemID = itemID(link), name = name, icon = icon, quality = quality,
        bop = bop == true, count = count,
        can = { need = canNeed == true, greed = canGreed == true, disenchant = canDisenchant == true, transmog = canTransmog == true },
        reasons = { need = reasonNeed, greed = reasonGreed, disenchant = reasonDisenchant },
        start = now or GetTime(), duration = ms / 1000, players = {}, order = {},
    }
    RollData.drops[rollID] = drop
    fire(rollID, "start")
    RollData.Scan(drop)
    return drop
end

-- The drop a chat line is about.
-- A chat line's id is the drop's Loot History key, so a copy already paired with
-- the history is paired with its chat lines too.
local function byID(id)
    return oldest(function(x) return x.historyID == id or x.lootListKey == id end)
end
local function unpaired(link)
    return oldest(function(x) return not x.historyID and not x.lootListKey and sameItem(x, link) end)
end

local function chatDrop(line)
    if line.historyID then
        local d = byID(line.historyID)
        -- The started line was missed: pair the oldest copy without an id.
        d = d or unpaired(line.link)
        if d then d.historyID = line.historyID end
        return d
    end
    -- Lines without an id: the oldest open copy where this player still has
    -- nothing of that kind.
    return oldest(function(x)
        if x.done or not sameItem(x, line.link) then return false end
        local p = line.who and (x.players[line.who] or x.players[(ns.RollChat.Names(line.who))])
        if line.kind == "roll" then return not (p and p.roll) end
        return not (p and p.pick)
    end)
end

function RollData.Chat(line, now)
    if type(line) ~= "table" then return end
    if line.kind == "started" then
        local d = line.historyID and (byID(line.historyID) or unpaired(line.link))
        if d then d.historyID = line.historyID end
        return
    end
    local drop = chatDrop(line)
    if not drop then return end
    local id = drop.rollID
    if line.kind == "allpassed" then
        if not drop.allPassed then
            drop.allPassed = true
            finish(drop, now)
            fire(id, "done")
        end
        return
    end
    local p = playerOf(drop, line.who, line.self)
    if not p then return end
    if line.kind == "pick" then
        if setPick(drop, p, line.pick, line.offSpec, true) then fire(id, "pick") end
    elseif line.kind == "roll" then
        setPick(drop, p, line.pick, line.offSpec, true)
        if line.roll and p.roll ~= line.roll then
            p.roll = line.roll
            fire(id, "roll")
        end
    elseif line.kind == "won" then
        setPick(drop, p, line.pick, line.offSpec, true)
        if line.roll then p.roll = line.roll end
        if setWinner(drop, p, now) then fire(id, "won") end
    end
    mend(drop)
end

-- Looks for this drop in the Loot History (it may have been recorded first).
function RollData.Scan(drop)
    if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos) then return end
    local infos = C_LootHistory.GetAllEncounterInfos()
    if type(infos) ~= "table" then return end
    for _, enc in ipairs(infos) do
        local encounterID = plain(enc.encounterID, "number")
        local drops = encounterID and C_LootHistory.GetSortedDropsForEncounter(encounterID)
        if type(drops) == "table" then
            for _, info in ipairs(drops) do
                local key = plain(info.lootListKey, "number")
                if key and type(info.winner) == "nil" and plain(info.allPassed, "boolean") ~= true then
                    RollData.History(encounterID, key)
                    if drop.lootListKey then return end
                end
            end
        end
    end
end

local function byAge(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.rollID < b.rollID
end

-- A Loot History record no copy of ours is paired with yet: with one unpaired
-- copy of that item, that one. With several (two of the same item), the
-- history's records for it in key order go to the copies in age order, so it
-- doesn't matter which record speaks first.
local function pairCopy(encounterID, key, link)
    local copies = {}
    for _, d in pairs(RollData.drops) do
        if not d.lootListKey and (not d.historyID or d.historyID == key) and not d.done and sameItem(d, link) then
            copies[#copies + 1] = d
        end
    end
    if #copies <= 1 then return copies[1] end
    table.sort(copies, byAge)
    local taken = {}
    for _, d in pairs(RollData.drops) do
        if d.encounterID == encounterID and d.lootListKey then taken[d.lootListKey] = true end
    end
    local keys = {}
    local list = C_LootHistory.GetSortedDropsForEncounter and C_LootHistory.GetSortedDropsForEncounter(encounterID)
    for _, info in ipairs(type(list) == "table" and list or {}) do
        local k = plain(info.lootListKey, "number")
        if k and not taken[k] and sameItem(copies[1], plain(info.itemHyperlink, "string")) then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for i, k in ipairs(keys) do
        if k == key then return copies[i] or copies[#copies] end
    end
    return copies[1]
end

-- A drop's Loot History record changed.
function RollData.History(encounterID, key, now)
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
    local info = C_LootHistory.GetSortedInfoForDrop(encounterID, key)
    if type(info) ~= "table" then return end
    local link = plain(info.itemHyperlink, "string")
    local drop = oldest(function(x) return x.encounterID == encounterID and x.lootListKey == key end)
        or oldest(function(x) return x.historyID == key and not x.lootListKey end)
        or pairCopy(encounterID, key, link)
    if not drop then return end
    -- The first record seats the whole group and makes the total known: the
    -- card's ticks and count change even though nobody has picked yet.
    local paired, seated = drop.lootListKey == nil, #drop.order
    drop.encounterID, drop.lootListKey = encounterID, key
    local id, what = drop.rollID, nil
    local rolls = type(info.rollInfos) == "table" and info.rollInfos or {}
    for _, r in ipairs(rolls) do
        local name = plain(r.playerName, "string")
        local p = name and playerOf(drop, name, plain(r.isSelf, "boolean") == true)
        if p then
            p.class = plain(r.playerClass, "string") or p.class
            local state = plain(r.state, "number")
            if setPick(drop, p, RollData.STATE[state], state == 1, true) then what = what or "pick" end
            local roll = plain(r.roll, "number")
            if roll and p.roll ~= roll then p.roll = roll; what = "roll" end
            if plain(r.isWinner, "boolean") == true and setWinner(drop, p, now) then what = "won" end
        end
    end
    if plain(info.isTied, "boolean") == true and not drop.tied then drop.tied = true; what = what or "roll" end
    if plain(info.allPassed, "boolean") == true and not drop.allPassed then
        drop.allPassed = true
        finish(drop, now)
        what = "done"
    end
    if not what and (paired or #drop.order ~= seated) then what = "seat" end
    if what then fire(id, what) end
    mend(drop)
end

-- A roll button of Daylight UI's pressed, before RollOnLoot. The pick is yours
-- once the game takes it: at once, or after its "this item will bind" box.
function RollData.Press(rollID, kind)
    local drop = RollData.drops[rollID]
    if not drop or drop.mine then return end
    drop.pending = kind
    fire(rollID, "pick")
end

-- Your own pick, known for sure.
function RollData.Mine(rollID, kind)
    local drop = RollData.drops[rollID]
    if not drop then return end
    drop.mine, drop.took = kind, kind
    local p = playerOf(drop, nil, true)
    if p then setPick(drop, p, kind) end
    fire(rollID, "pick")
    mend(drop)
end

-- The game hid its popup: it took what you pressed, or your time ran out (a
-- pass). Your own chat line or history state, when it comes, has the last word.
function RollData.Cancel(rollID)
    local drop = RollData.drops[rollID]
    if not drop or drop.mine then return end
    local p = playerOf(drop, nil, true)
    if drop.pending then
        setPick(drop, p, drop.pending)
    else
        setPick(drop, p, "pass")
        drop.timedOut = true
    end
    fire(rollID, "pick")
    mend(drop)
end

-- Your Need number, shown by the game before any chat line.
function RollData.NeedRoll(rollID, roll)
    local drop = RollData.drops[rollID]
    if not drop or type(roll) ~= "number" then return end
    drop.myRoll = roll
    local p = playerOf(drop, nil, true)
    if p then p.roll = p.roll or roll end
    fire(rollID, "roll")
end

function RollData.AllCancel(now)
    for id, drop in pairs(RollData.drops) do
        if not drop.done then
            finish(drop, now)
            fire(id, "done")
        end
    end
end

-- You left the group: no pick or winner will come for any roll, so each one
-- ends now instead of waiting out its timer.
function RollData.LeftGroup(now)
    if grouped() then return end
    for id, drop in pairs(RollData.drops) do
        if not drop.done then
            drop.leftGroup = true
            finish(drop, now)
            fire(id, "done")
        end
    end
end

-- After a reload: every roll the game still has open, with the time it has left.
-- Out of a group none is yours any more, even if the game still lists it.
function RollData.Rebuild(now)
    now = now or GetTime()
    if not grouped() then return end
    local ids = GetActiveLootRollIDs and GetActiveLootRollIDs()
    if type(ids) ~= "table" then return end
    for _, rollID in ipairs(ids) do
        if not RollData.drops[rollID] and not RollData.ended[rollID] then
            local ms = C_Loot and C_Loot.GetLootRollDuration and C_Loot.GetLootRollDuration(rollID)
            local drop = RollData.Start(rollID, ms, now)
            local left = GetLootRollTimeLeft and GetLootRollTimeLeft(rollID)
            if drop and type(left) == "number" then drop.start = now - (drop.duration - left / 1000) end
        end
    end
    RollData.RebuildPicked(now)
end

-- After a reload the game lists only rolls you haven't picked. The ones you
-- have, still being rolled by the others, come back from the Loot History, to
-- watch: no buttons.
function RollData.RebuildPicked(now)
    if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos and C_LootHistory.GetSortedDropsForEncounter) then return end
    -- The history times its drops in milliseconds on its own clock, not GetTime's.
    local clock = C_LootHistory.GetLootHistoryTime and plain(C_LootHistory.GetLootHistoryTime(), "number")
    local infos = C_LootHistory.GetAllEncounterInfos()
    for _, enc in ipairs(type(infos) == "table" and infos or {}) do
        local encounterID = plain(enc.encounterID, "number")
        local list = encounterID and C_LootHistory.GetSortedDropsForEncounter(encounterID)
        for _, info in ipairs(type(list) == "table" and list or {}) do
            local key = plain(info.lootListKey, "number")
            local state = plain(info.playerRollState, "number")
            local started, length = plain(info.startTime, "number"), plain(info.duration, "number")
            local left = clock and started and length and (length - (clock - started)) / 1000
            local held = key and oldest(function(x) return x.encounterID == encounterID and x.lootListKey == key end)
            local id = key and -(encounterID * 100000 + key)
            if key and not held and not RollData.drops[id] and not RollData.ended[historyKey(encounterID, key)]
                and type(info.winner) == "nil"
                and plain(info.allPassed, "boolean") ~= true and state and state ~= 4
                and left and left > 0 then
                local link = plain(info.itemHyperlink, "string")
                local item = itemID(link)
                local icon, quality
                local instant = C_Item and C_Item.GetItemInfoInstant
                if item and type(instant) == "function" then icon = select(5, instant(item)) end
                local qualityOf = C_Item and C_Item.GetItemQualityByID
                if item and type(qualityOf) == "function" then quality = qualityOf(item) end
                local drop = {
                    rollID = id, link = link, itemID = item, name = itemName(link) or "?", icon = icon or 134400,
                    quality = type(quality) == "number" and quality or nil, count = 1, watch = true,
                    can = {}, reasons = {}, players = {}, order = {},
                    start = now - (length / 1000 - left), duration = length / 1000,
                    mine = RollData.STATE[state], encounterID = encounterID, lootListKey = key,
                }
                RollData.drops[id] = drop
                fire(id, "start")
                RollData.History(encounterID, key, now)
            end
        end
    end
end

-- A roll whose time is long over with no result ends on its own.
function RollData.Expire(now)
    now = now or GetTime()
    for id, drop in pairs(RollData.drops) do
        if not drop.done and now > drop.start + drop.duration + RollData.GRACE then
            drop.expired = true
            finish(drop, now)
            fire(id, "done")
        end
    end
end

-- Forgets a finished roll once its card has left.
function RollData.Remove(rollID)
    local drop = RollData.drops[rollID]
    if drop then
        if type(rollID) == "number" and rollID > 0 then RollData.ended[rollID] = true end
        if drop.encounterID and drop.lootListKey then
            RollData.ended[historyKey(drop.encounterID, drop.lootListKey)] = true
        end
        RollData.drops[rollID] = nil
        fire(rollID, "gone")
    end
end

-- The players to list. "best": Need above Greed above Pass, then the highest
-- roll, then the name, so the winner leads. "picked": the order they chose in.
function RollData.Sorted(drop, how)
    local list = {}
    for _, key in ipairs(drop.order) do list[#list + 1] = drop.players[key] end
    local RANK = RollData.RANK
    if how == "picked" then
        table.sort(list, function(a, b)
            local sa, sb = a.seq or math.huge, b.seq or math.huge
            if sa ~= sb then return sa < sb end
            return (a.name or "") < (b.name or "")
        end)
    else
        table.sort(list, function(a, b)
            if a.won ~= b.won then return a.won == true end
            local ra, rb = RANK[a.pick or "choosing"] or 0, RANK[b.pick or "choosing"] or 0
            if ra ~= rb then return ra > rb end
            local na, nb = a.roll or -1, b.roll or -1
            if na ~= nb then return na > nb end
            return (a.name or "") < (b.name or "")
        end)
    end
    return list
end

local function sameKind(a, b)
    if a.itemID and b.itemID then return a.itemID == b.itemID end
    return a.name == b.name
end

-- Every held copy of this item, oldest first, this one included.
local function copies(drop)
    local list = {}
    for _, d in pairs(RollData.drops) do
        if sameKind(d, drop) then list[#list + 1] = d end
    end
    table.sort(list, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return a.rollID < b.rollID
    end)
    return list
end

-- The other copies of the same item.
function RollData.Twins(drop)
    local list = {}
    for _, d in ipairs(copies(drop)) do
        if d ~= drop then list[#list + 1] = d end
    end
    return list
end

-- What a drop knows from its chat lines and Loot History record, as opposed to
-- what the game's roll events told it about its own roll id.
local RECORD = { "encounterID", "lootListKey", "historyID", "players", "order", "me", "seq", "said",
    "winner", "done", "doneAt", "tied", "allPassed" }

local function swap(x, y)
    for _, k in ipairs(RECORD) do x[k], y[k] = y[k], x[k] end
    for _, d in ipairs({ x, y }) do
        -- The record has the last word on your pick, the game's events next.
        d.mine = d.said or d.took
        local p = d.me and d.players[d.me]
        if p then p.pick = d.mine end
    end
end

-- Nothing ties a game roll id to its Loot History key or chat id, so two copies
-- of one item are paired by the order things arrive, which is a guess. The
-- game's own events say which copy you picked: a record saying you picked a
-- copy you never pressed, while a copy you did press has no such word, means
-- the two were paired the wrong way round. Left alone, a win on one copy ended
-- the other before you could roll on it.
mend = function(drop)
    if drop.watch then return end
    local list = copies(drop)
    if #list < 2 then return end
    local function pressed(d) return d.pending ~= nil or d.took ~= nil end
    for _, x in ipairs(list) do
        if x.said and not pressed(x) and not x.watch then
            for _, y in ipairs(list) do
                if y ~= x and pressed(y) and not y.said and not y.watch then
                    swap(x, y)
                    fire(x.rollID, "pick"); fire(y.rollID, "pick")
                    return
                end
            end
        end
    end
end

function RollData.TwinIndex(drop)
    local list = copies(drop)
    for i, d in ipairs(list) do
        if d == drop then return i, #list end
    end
    return 1, 1
end

local wired = false
function RollData.Wire()
    if wired then return end
    wired = true
    local function num(v) return plain(v, "number") end
    DUI.RegisterEvent("START_LOOT_ROLL", function(_, rollID, rollTime)
        rollID = num(rollID)
        if rollID then RollData.Start(rollID, num(rollTime), GetTime()) end
    end)
    DUI.RegisterEvent("CANCEL_LOOT_ROLL", function(_, rollID)
        rollID = num(rollID)
        if rollID then RollData.Cancel(rollID) end
    end)
    DUI.RegisterEvent("CANCEL_ALL_LOOT_ROLLS", function() RollData.AllCancel(GetTime()) end)
    DUI.RegisterEvent("GROUP_LEFT", function() RollData.LeftGroup(GetTime()) end)
    DUI.RegisterEvent("MAIN_SPEC_NEED_ROLL", function(_, rollID, roll)
        rollID = num(rollID)
        if rollID then RollData.NeedRoll(rollID, num(roll)) end
    end)
    DUI.RegisterEvent("LOOT_HISTORY_UPDATE_DROP", function(_, encounterID, key)
        encounterID, key = num(encounterID), num(key)
        if encounterID and key then RollData.History(encounterID, key, GetTime()) end
    end)
    DUI.RegisterEvent("CHAT_MSG_LOOT", function(_, text)
        local line = ns.RollChat.Parse(text)
        if line then RollData.Chat(line, GetTime()) end
    end)
end
