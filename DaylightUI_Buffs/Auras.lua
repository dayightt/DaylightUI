-- Auras: reads the player's auras and weapon enchants into plain entry
-- tables. Every value that comes back from the client passes through the
-- secret guard, so a restricted field is simply absent.

local _, BL = ...

local Auras = {}
BL.Auras = Auras

Auras.MAX = 64

local WEAPON_SLOT_TO_INVENTORY = { [0] = 16, [1] = 17, [2] = 18 }

local function plainNumber(v)
    v = BL.Plain(v)
    if type(v) == "number" then return v end
    return nil
end

-- Returns the entry list and a flag that is true when the client refused
-- a read (in combat, secret auras make the index API error instead of
-- returning data); the caller decides what to show in that case.
function Auras.Collect(filter)
    local entries = {}
    local restricted = false
    for index = 1, Auras.MAX do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
        if not ok then
            restricted = true
            break
        end
        if type(data) == "nil" then break end
        data = BL.PlainTable(data)
        if data then
            local expiration = plainNumber(data.expirationTime)
            -- A secret expiration can't be sorted or printed, but the
            -- Cooldown widget accepts it as-is; keep the raw values for that.
            local secretExpiration, secretDuration
            if expiration == nil and type(data.expirationTime) ~= "nil" then
                secretExpiration, secretDuration = data.expirationTime, data.duration
            end
            entries[#entries + 1] = {
                secretExpiration = secretExpiration,
                secretDuration = secretDuration,
                kind = "aura",
                filter = filter,
                index = index,
                auraInstanceID = plainNumber(data.auraInstanceID),
                name = BL.Plain(data.name),
                icon = BL.Plain(data.icon),
                spellId = plainNumber(data.spellId),
                applications = plainNumber(data.applications) or 0,
                duration = plainNumber(data.duration),
                expirationTime = expiration,
                sourceUnit = BL.Plain(data.sourceUnit),
                dispelName = BL.Plain(data.dispelName),
                timed = expiration ~= nil and expiration > 0,
            }
        end
    end
    return entries, restricted
end

-- The enchant's own name is only available from the item tooltip: the
-- first green line, minus any "(30 min)" suffix.
local function enchantName(invSlot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, info = pcall(C_TooltipInfo.GetInventoryItem, "player", invSlot)
    info = ok and BL.PlainTable(info) or nil
    local lines = info and BL.PlainTable(info.lines)
    if not lines then return nil end
    for i = 2, #lines do
        local line = BL.PlainTable(lines[i])
        local color = line and BL.PlainTable(line.leftColor)
        local text = line and BL.Plain(line.leftText)
        if color and type(text) == "string" then
            local r, g, b = BL.Plain(color.r), BL.Plain(color.g), BL.Plain(color.b)
            if type(g) == "number" and g > 0.9 and (r or 0) < 0.2 and (b or 0) < 0.2 then
                text = string.gsub(text, "%s*%(.-%)%s*$", "")
                if text ~= "" then return text end
            end
        end
    end
    return nil
end

-- Returns the entry list and a flag that is true when the client refused the
-- read. skipNames skips the tooltip lookup for the enchant's name (the bar's
-- timer tick doesn't need it). into: an existing list to fill, reusing its entry
-- tables (the tick asks five times a second while an enchant is up). skipDrawn:
-- leave out each enchant the buff bar's container draws itself, and only count
-- them (the third return).
local function trim(list, n)
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- Does the container's weapon slot draw this enchant? It draws the slot's one
-- temporary enchant (C_PaperDollInfo.GetTemporaryEnchantmentInfo, timed ones
-- only: hidePermanent), so ask that, by enchant id. The type from
-- GetWeaponEnchantInfo doesn't tell: Forever's rogue poisons report a different
-- type and were drawn twice. Without the read, assume Temporary.
local CONTAINER_KIND = 2 -- Enum.ItemEnchantType.Temporary
local function containerDraws(invSlot, enchant, kind)
    local get = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
    if type(get) ~= "function" then return kind == CONTAINER_KIND end
    local ok, info = pcall(get, invSlot)
    info = ok and BL.PlainTable(info) or nil
    if type(info) ~= "table" or not BL.Plain(info.hasExpirationTime) then return false end
    local id, drawn = plainNumber(enchant.enchantID), plainNumber(info.enchantID)
    if id and drawn then return id == drawn end
    return kind == CONTAINER_KIND
end

function Auras.CollectWeapons(skipNames, into, skipDrawn)
    local entries = into or {}
    local n, skipped = 0, 0
    if not (C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot) then return trim(entries, 0), false, 0 end
    local now = BL.Clock()
    -- Called five times a second, so the slots are sorted only once.
    local slots = Auras.weaponSlots
    if not slots then
        slots = {}
        for _, slotID in pairs(Enum.WeaponSlot) do slots[#slots + 1] = slotID end
        table.sort(slots)
        Auras.weaponSlots = slots
    end
    for _, slotID in ipairs(slots) do
        local invSlot = WEAPON_SLOT_TO_INVENTORY[slotID]
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, slotID)
        if not ok then return trim(entries, 0), true, 0 end
        list = BL.PlainTable(list)
        if invSlot and list then
            for _, enchant in ipairs(list) do
                enchant = BL.PlainTable(enchant)
                local kind = enchant and plainNumber(enchant.enchantType) or 0
                if enchant and BL.Plain(enchant.hasEnchant) and skipDrawn and containerDraws(invSlot, enchant, kind) then
                    skipped = skipped + 1
                elseif enchant and BL.Plain(enchant.hasEnchant) then
                    local ms = plainNumber(enchant.timeLeft) or 0
                    n = n + 1
                    local e = entries[n]
                    if type(e) ~= "table" then e = {}; entries[n] = e end
                    e.kind = "weapon"
                    e.slot = invSlot
                    e.weaponSlot = slotID
                    e.enchantType = kind
                    e.name = (not skipNames and enchantName(invSlot)) or "Weapon Enchant"
                    e.icon = BL.Plain(enchant.enchantIconID) or GetInventoryItemTexture("player", invSlot)
                    e.applications = plainNumber(enchant.charges) or 0
                    e.expirationTime = now + ms / 1000
                    e.timed = true
                end
            end
        end
    end
    return trim(entries, n), false, skipped
end

