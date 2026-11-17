-- Spellbook data, read from C_SpellBook the same way the game's Camelot
-- spellbook does (Blizzard_SpellBookCategory.lua). One section per visible
-- skill line, then Pet if the pet has a spellbook. No spell lists of its own.
--
-- Lower ranks (IsSpellBookItemLowRank) are nested under the top rank with the
-- same name in the same section. The book also holds flyouts (warrior stances,
-- Portal, Summon Demon), but Classic has no pop-out spells: like the game's book
-- here, a flyout is skipped and its spells are listed one by one.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local L = DUI.L

local SD = {}
ns.SpellData = SD

-- Game enums, with their known values as fallback.
local function enum(kind, key, fallback)
    local e = Enum and Enum[kind]
    return (e and e[key]) or fallback
end
function SD.PLAYER() return enum("SpellBookSpellBank", "Player", 0) end
function SD.PET() return enum("SpellBookSpellBank", "Pet", 1) end
local function TYPE(key, n) return enum("SpellBookItemType", key, n) end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

-- The game returns "" for no rank; normalize to nil.
local function rankText(s)
    return (type(s) == "string" and s ~= "") and s or nil
end

local function entry(slot, bank, info)
    return { slot = slot, bank = bank, spellID = info.spellID, name = info.name or "",
        rank = rankText(info.subName),
        icon = info.iconID, passive = info.isPassive == true,
        future = info.itemType == TYPE("FutureSpell", 2), pet = bank == SD.PET(), lows = {},
        autocast = bank == SD.PET() and call(C_SpellBook.GetSpellBookItemAutoCast, slot, bank) == true or nil }
end

-- Sort key from the trailing number of the rank text ("Rank 2" in any
-- language), falling back to the book slot since the book lists ranks low to high.
function SD.RankOf(e)
    local n = e.rank and tonumber(string.match(e.rank, "(%d+)%D*$"))
    if n then return n * 1000 + (e.slot or 0) end
    return e.slot or 0
end

-- Read a range of book slots into section.spells. Lower ranks nest under
-- their top rank; one with no top rank in the section gets its own row.
local function readRange(section, bank, first, count, showLow, data)
    local tops, lows = {}, {}
    for slot = first, first + count - 1 do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
        if type(info) == "table" then
            if info.itemType ~= TYPE("Flyout", 4) then
                local e = entry(slot, bank, info)
                if call(C_SpellBook.IsSpellBookItemLowRank, slot, bank) then
                    e.low = true
                    lows[#lows + 1] = e
                else
                    tops[#tops + 1] = e
                end
            end
        end
    end
    -- IsSpellBookItemLowRank misses some (seen in game: Blessing of Might
    -- rank 1 next to rank 2 wasn't flagged). So when a name appears twice in
    -- a section, keep only the highest rank on top.
    local byName, kept = {}, {}
    for _, e in ipairs(tops) do
        local have = byName[e.name]
        if have then
            local top, low = have, e
            if SD.RankOf(e) >= SD.RankOf(have) then top, low = e, have end
            low.low = true
            lows[#lows + 1] = low
            byName[e.name] = top
            kept[top], kept[low] = true, nil
        else
            byName[e.name] = e
            kept[e] = true
        end
    end
    local still = {}
    for _, e in ipairs(tops) do if kept[e] then still[#still + 1] = e end end
    tops = still
    for _, e in ipairs(lows) do
        data.anyLow = true
        if showLow then
            local top = byName[e.name]
            if top then top.lows[#top.lows + 1] = e else tops[#tops + 1] = e end
        end
    end
    -- Sort lower ranks highest first, by rank rather than trusting the book's order.
    for _, e in ipairs(tops) do
        if #e.lows > 1 then
            local order = {}
            for i, l in ipairs(e.lows) do order[l] = i end
            table.sort(e.lows, function(a, b)
                local ra, rb = SD.RankOf(a), SD.RankOf(b)
                if ra ~= rb then return ra > rb end
                return order[a] > order[b]
            end)
        end
    end
    section.spells = tops
end

-- { sections = { { name, icon, pet?, spells = { { slot, bank, spellID,
-- name, rank, icon, passive, future, pet, low, lows } } } }, anyLow }
function SD.Read(showLow)
    local data = { sections = {}, anyLow = false }
    if type(C_SpellBook) ~= "table" or type(C_SpellBook.GetNumSpellBookSkillLines) ~= "function" then return data end
    local bank = SD.PLAYER()
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if type(line) == "table" and not line.shouldHide then
            local section = { name = line.name or "", icon = line.iconID }
            readRange(section, bank, (line.itemIndexOffset or 0) + 1, line.numSpellBookItems or 0, showLow, data)
            if #section.spells > 0 then data.sections[#data.sections + 1] = section end
        end
    end
    local numPet = call(C_SpellBook.HasPetSpells)
    if type(numPet) == "number" and numPet > 0 and call(PetHasSpellbook) then
        local section = { name = PET or L["Pet"], pet = true }
        readRange(section, SD.PET(), 1, numPet, showLow, data)
        if #section.spells > 0 then data.sections[#data.sections + 1] = section end
    end
    return data
end
