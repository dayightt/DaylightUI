-- Reads equipped gear into plain tables (name, quality, item level, durability,
-- ammo, the line under each name). No frames here, so it's easy to test.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local Gear = {}
ns.Gear = Gear

-- Slot layout: eight per side, weapons in a row underneath. Ammo is a small
-- slot beside the ranged icon, as in the game's window.
Gear.LEFT = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist" }
Gear.RIGHT = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" }
Gear.BOTTOM = { "MainHand", "SecondaryHand", "Ranged" }

-- Only classes that use ammo get the ammo slot, matching PaperDollFrame_OnShow.
-- unit defaults to "player". The inspect window passes its own.
function Gear.UsesAmmo(unit)
    return type(UnitUsesAmmo) == "function" and UnitUsesAmmo(unit or "player") == true
end

Gear.LABEL = { Head = L["Head"], Neck = L["Neck"], Shoulder = L["Shoulders"], Back = L["Back"], Chest = L["Chest"], Shirt = L["Shirt"],
    Tabard = L["Tabard"], Wrist = L["Wrists"], Hands = L["Hands"], Waist = L["Waist"], Legs = L["Legs"], Feet = L["Feet"],
    Finger0 = L["Ring"], Finger1 = L["Ring"], Trinket0 = L["Trinket"], Trinket1 = L["Trinket"], MainHand = L["Main hand"],
    SecondaryHand = L["Off hand"], Ranged = L["Ranged"], Ammo = L["Ammo"] }

-- Shirt and tabard say what they are instead of an item level.
Gear.NO_LEVEL = { Shirt = true, Tabard = true }

Gear.AMMO_WORD = { Arrow = "arrows", Bullet = "bullets" }
Gear.GREY = DUI.Style.INK.OFF   -- a quality the game has no color for

local ids = {}
-- Slot id and empty-slot texture for a key like "Head".
function Gear.SlotId(key)
    if ids[key] == nil then
        local ok, id, empty = pcall(GetInventorySlotInfo, key .. "Slot")
        ids[key] = (ok and type(id) == "number") and { id, empty } or false
    end
    local e = ids[key]
    if e then return e[1], e[2] end
end

local function levelOf(link)
    local get = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if not (link and get) then return nil end
    local ok, level = pcall(get, link)
    return ok and type(level) == "number" and level or nil
end

local function subTypeOf(link)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not (link and get) then return nil end
    local ok, _, _, _, _, _, _, subType = pcall(get, link)
    return ok and subType or nil
end

-- The permanent enchant's text ("+7 Agility"), read from the item tooltip's
-- ItemEnchantmentPermanent line. Links without an enchant id skip the tooltip,
-- and results are cached per link so each enchant is read once.
Gear.ENCHANT_LINE = 15
local enchants = {}

-- The line is localized ENCHANTED_TOOLTIP_LINE ("Enchanted: %s"). Keep only the %s part.
local function bareEnchant(text)
    local fmt = ENCHANTED_TOOLTIP_LINE
    if type(fmt) ~= "string" then return text end
    local pattern = "^" .. fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        :gsub("%%%%%d?%%?%$?s", "(.+)", 1) .. "$"
    return text:match(pattern) or text
end

function Gear.Enchant(link, slotId, unit)
    local eid = link and string.match(link, "item:%-?%d+:(%d+)")
    if not eid or eid == "0" then return nil end
    if enchants[link] then return enchants[link] end
    local get = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
    if not get then return nil end
    local ok, data = pcall(get, unit or "player", slotId)
    if not (ok and type(data) == "table" and type(data.lines) == "table") then return nil end
    local kind = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent or Gear.ENCHANT_LINE
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if line.type == kind and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            text = bareEnchant(text)
            enchants[link] = text
            return text
        end
    end
end

-- One slot. repairAt is the durability fraction that triggers "Repair soon".
-- Durability is only read for the player, since the game's call takes no unit.
function Gear.Read(key, repairAt, unit)
    unit = unit or "player"
    local id, empty = Gear.SlotId(key)
    local e = { key = key, id = id, label = Gear.LABEL[key] or key, emptyIcon = empty }
    -- No icon means empty, as in PaperDollItemSlotButton_Update. An empty ammo
    -- slot still returns an id and a count of 1, so the id alone isn't enough.
    local icon = id and GetInventoryItemTexture(unit, id)
    if not icon then
        e.empty = true
        return e
    end
    local link = GetInventoryItemLink(unit, id)
    -- The ammo slot gives an item id but no link. Get the link from the item
    -- info, which is nil until cached. The icon still shows and the name
    -- fills in on a later refresh.
    local itemID
    if not link and type(GetInventoryItemID) == "function" then
        itemID = GetInventoryItemID(unit, id)
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if itemID and get then
            local ok, _, itemLink, quality = pcall(get, itemID)
            if ok then link, e.quality = itemLink, quality end
        end
    end
    e.name = link and string.match(link, "%[(.-)%]")
    e.quality = GetInventoryItemQuality(unit, id) or e.quality
    e.icon = icon
    e.level = levelOf(link)
    e.enchant = Gear.Enchant(link, id, unit)
    local cur, max
    if unit == "player" then cur, max = GetInventoryItemDurability(id) end
    if type(cur) == "number" and type(max) == "number" and max > 0 then
        e.cur, e.max, e.pct = cur, max, cur / max
        if cur <= 0 then e.wear = "broken"
        elseif e.pct <= (repairAt or 0.25) then e.wear = "low" end
    end
    if key == "Ammo" then
        e.ammo = GetInventoryItemCount(unit, id) or 0
        e.ammoWord = Gear.AMMO_WORD[subTypeOf(link) or ""] or "ammo"
    end
    return e
end

-- Every slot we draw, by key.
function Gear.All(repairAt, unit)
    local out = {}
    for _, list in ipairs({ Gear.LEFT, Gear.RIGHT, Gear.BOTTOM }) do
        for _, key in ipairs(list) do out[key] = Gear.Read(key, repairAt, unit) end
    end
    out.Ammo = Gear.Read("Ammo", repairAt, unit)
    return out
end

-- Footer numbers: average item level (plain even in combat), total durability
-- (nil if nothing wears) and average quality for the item level's color.
-- Shirt, tabard and ammo are left out of the quality. For another unit the
-- item level comes from the inspect data.
Gear.NO_QUALITY = { Shirt = true, Tabard = true, Ammo = true }

function Gear.Summary(all, unit)
    local cur, max, qSum, qN = 0, 0, 0, 0
    for key, e in pairs(all) do
        if e.max then cur, max = cur + e.cur, max + e.max end
        if type(e.quality) == "number" and not Gear.NO_QUALITY[key] then qSum, qN = qSum + e.quality, qN + 1 end
    end
    local avg
    if unit and unit ~= "player" then
        local get = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
        local ok, v = pcall(get or error, unit)
        if ok and type(v) == "number" and v > 0 then avg = v end
    elseif type(GetAverageItemLevel) == "function" then
        local ok, overall, equipped = pcall(GetAverageItemLevel)
        if ok then avg = equipped or overall end
    end
    return { level = type(avg) == "number" and math.floor(avg) or nil, durability = max > 0 and cur / max or nil,
             quality = qN > 0 and math.floor(qSum / qN + 0.5) or nil }
end

-- Colors a number inside a label line as a value, then restores the line color.
function Gear.Value(v) return DUI.Win.Parts.Hex(DUI.Style.INK.VALUE) .. tostring(v) .. "|r" end

-- The line under a slot's name, and its color.
function Gear.Line(e)
    if e.empty then return L["Empty"], "dim" end
    if e.wear == "broken" then return L["Broken · no stats until repaired"], "red" end
    if e.wear == "low" then return string.format(L["Repair soon · %d%% left"], math.floor(e.pct * 100 + 0.5)), "amber" end
    if e.ammo then return string.format("%d %s", e.ammo, e.ammoWord), "dim" end
    if Gear.NO_LEVEL[e.key] then return e.label, "dim" end
    return e.level and string.format(L["Item level %s"], Gear.Value(e.level)) or "", "dim"
end

function Gear.QualityColor(q)
    local c = type(ITEM_QUALITY_COLORS) == "table" and q and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return Gear.GREY[1], Gear.GREY[2], Gear.GREY[3]
end
