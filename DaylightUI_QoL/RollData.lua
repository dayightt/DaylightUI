-- Who picked what on each loot roll, read from the game's loot history: its
-- drops, which drop each roll popup is for, and a drop's Tally (the players
-- who picked Need, Greed or Pass, and those who haven't picked yet). No frames:
-- RollTally.lua draws it. Reading the history, pairing drops with popups and
-- the Tally's sections are adapted from BetterGroupLoot (MIT, see
-- RollTally-LICENSE.txt).
--
--   Row    { name, class, choice, roll, winner, isSelf }. choice: need,
--          offspec, greed, pass or undecided. roll is nil until there is one.
--          A row with any field the game keeps secret is dropped as it's read.
--   Drop   { key = "encounterID:listID", listID, link, itemID, inProgress, rows }
--   Popup  { frame, rollID, link, itemID }: a roll popup on screen.
--   Tally  section -> { rows (in order, at most MAX_ROWS), total, more }, for
--          the sections need, greed, pass and undecided.

local _, ns = ...
local secret = DaylightUI.IsSecret

local RollData = {
    MAX_ROWS = 15,   -- players a section lists before "+N more"
    SECTIONS = { "need", "greed", "pass", "undecided" },
    -- The section each choice counts in: Off-spec Need on the Need button.
    SECTION_OF_CHOICE = { need = "need", offspec = "need", greed = "greed", pass = "pass", undecided = "undecided" },
    -- The section each popup button counts and lists. The game shows
    -- Transmog in Greed's place.
    SECTION_OF_BUTTON = { need = "need", greed = "greed", transmog = "greed", pass = "pass" },
}
ns.RollData = RollData

-- The history's roll state as the choice it counts as. The values are the
-- game's (Enum.EncounterLootDropRollState); a Transmog roll counts as Greed.
local STATE = Enum and Enum.EncounterLootDropRollState
    or { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }
local CHOICE_OF_STATE = {
    [STATE.NeedMainSpec] = "need",
    [STATE.NeedOffSpec] = "offspec",
    [STATE.Transmog] = "greed",
    [STATE.Greed] = "greed",
    [STATE.Pass] = "pass",
    [STATE.NoRoll] = "undecided",
}

local function anySecret(...)
    for i = 1, select("#", ...) do
        if secret((select(i, ...))) then return true end
    end
    return false
end

function RollData.ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function readRow(info)
    local name, class, state, roll, winner, isSelf =
        info.playerName, info.playerClass, info.state, info.roll, info.isWinner, info.isSelf
    if anySecret(name, class, state, roll, winner, isSelf) then return nil end
    local choice = CHOICE_OF_STATE[state]
    if type(name) ~= "string" or not choice then return nil end
    return { name = name, class = class, choice = choice, roll = type(roll) == "number" and roll or nil,
        winner = winner == true, isSelf = isSelf == true }
end

local function readDrop(encounterID, raw)
    local listID = raw.lootListID
    if listID == nil then listID = raw.lootListKey end
    local link, winner, allPassed, infos = raw.itemHyperlink, raw.winner, raw.allPassed, raw.rollInfos
    if anySecret(listID, link, winner, allPassed, infos) or type(listID) ~= "number" then return nil end
    local rows = {}
    for _, info in ipairs(infos or {}) do rows[#rows + 1] = readRow(info) end
    return { key = encounterID .. ":" .. listID, listID = listID, link = link, itemID = RollData.ItemID(link),
        inProgress = not winner and not allPassed, rows = rows }
end

-- Every drop in the loot history, in the order that numbers them: encounters
-- as the game lists them, each one's drops from the lowest list ID up.
function RollData.Drops()
    local history = C_LootHistory
    if type(history) ~= "table" then return {} end
    local drops = {}
    for _, encounter in ipairs(history.GetAllEncounterInfos() or {}) do
        local id = encounter.encounterID
        if type(id) == "number" and not secret(id) then
            local list = {}
            for _, raw in ipairs(history.GetSortedDropsForEncounter(id) or {}) do list[#list + 1] = readDrop(id, raw) end
            table.sort(list, function(a, b) return a.listID < b.listID end)
            for _, drop in ipairs(list) do drops[#drops + 1] = drop end
        end
    end
    return drops
end

-- How well a drop fits a popup: 2 the same link, 1 the same item, 0 neither.
local function match(popup, drop)
    if popup.link ~= nil and drop.link == popup.link then return 2 end
    if popup.itemID ~= nil and drop.itemID == popup.itemID then return 1 end
    return 0
end

-- Candidates { drop, number, match }: one still being rolled for first, then
-- the exact link, then the lower-numbered drop.
local function better(a, b)
    if a.drop.inProgress ~= b.drop.inProgress then return a.drop.inProgress end
    if a.match ~= b.match then return a.match > b.match end
    return a.number < b.number
end

local function best(popup, drops, claimed)
    local found
    for number, drop in ipairs(drops) do
        local m = claimed[drop.key] and 0 or match(popup, drop)
        if m > 0 then
            local c = { drop = drop, number = number, match = m }
            if not found or better(c, found) then found = c end
        end
    end
    return found and found.drop
end

local function openDropsFor(group, drops, claimed)
    local n = 0
    for _, drop in ipairs(drops) do
        if drop.inProgress and not claimed[drop.key] and match(group[1], drop) > 0 then n = n + 1 end
    end
    return n
end

-- popups: the Popups on screen. drops: RollData.Drops(). current: rollID ->
-- drop key from the last pairing. Returns rollID -> drop key for every popup
-- that has a drop:
--   a popup keeps its drop while that drop is still being rolled for;
--   otherwise it takes the best drop no other popup holds (see better);
--   popups showing the same item take their drops lowest roll ID first, and
--   only once there are as many drops still being rolled for as popups, so a
--   copy whose history arrives late can't swap them.
function RollData.Pair(popups, drops, current)
    local byKey = {}
    for _, drop in ipairs(drops) do byKey[drop.key] = drop end
    local result, claimed, open = {}, {}, {}
    for _, popup in ipairs(popups) do
        local key = current[popup.rollID]
        if key and byKey[key] and byKey[key].inProgress then
            result[popup.rollID], claimed[key] = key, true
        else
            open[#open + 1] = popup
        end
    end
    table.sort(open, function(a, b) return a.rollID < b.rollID end)
    local groups, order = {}, {}
    for _, popup in ipairs(open) do
        local item = popup.itemID or popup.link
        if item then
            if not groups[item] then
                groups[item] = {}
                order[#order + 1] = groups[item]
            end
            table.insert(groups[item], popup)
        end
    end
    for _, group in ipairs(order) do
        if #group == 1 or openDropsFor(group, drops, claimed) >= #group then
            for _, popup in ipairs(group) do
                local drop = best(popup, drops, claimed)
                if drop then result[popup.rollID], claimed[drop.key] = drop.key, true end
            end
        end
    end
    return result
end

-- Rows with a roll number first, highest first, then the rest by name.
local function before(a, b)
    if (a.roll ~= nil) ~= (b.roll ~= nil) then return a.roll ~= nil end
    if a.roll ~= nil and a.roll ~= b.roll then return a.roll > b.roll end
    return a.name < b.name
end

-- A drop's rows as its Tally.
function RollData.Tally(rows)
    local tally = {}
    for _, key in ipairs(RollData.SECTIONS) do tally[key] = { rows = {}, total = 0, more = 0 } end
    for _, row in ipairs(rows) do
        local list = tally[RollData.SECTION_OF_CHOICE[row.choice]].rows
        list[#list + 1] = row
    end
    for _, section in pairs(tally) do
        table.sort(section.rows, before)
        section.total = #section.rows
        for i = section.total, RollData.MAX_ROWS + 1, -1 do section.rows[i] = nil end
        section.more = section.total - #section.rows
    end
    return tally
end
