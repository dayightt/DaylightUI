-- Auras: reads the player's auras and weapon enchants into plain entry
-- tables. Every value that comes back from the client passes through the
-- secret guard, so a restricted field is simply absent.

local _, BL = ...
local DUI = DaylightUI

local Auras = {}
BL.Auras = Auras

Auras.MAX = 64

-- Debuffs that are only a timer on a bonus and never need a glance, left off
-- the debuff bar: Boosted Rest, the hour before a Camp Tent gives rested
-- experience again.
BL.QUIET_DEBUFFS = { [1229451] = true }

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
    local harmful = string.find(filter, "HARMFUL", 1, true) ~= nil
    for index = 1, Auras.MAX do
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
        if not ok then
            restricted = true
            break
        end
        if type(data) == "nil" then break end
        data = BL.PlainTable(data)
        -- The bar's container leaves these out, so the count and hover must too.
        if data and harmful and BL.QUIET_DEBUFFS[plainNumber(data.spellId) or 0] then data = nil end
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
                boss = BL.Plain(data.isBossAura) == true,
                timed = expiration ~= nil and expiration > 0,
            }
        end
    end
    return entries, restricted
end

-- Filters ------------------------------------------------------------------
--
-- Which buffs and debuffs the bars leave out: the aura lists shared with the
-- unit frames (made on Unit Frames > Aura Lists, so there are none while that
-- module is off), and on the debuff bar only the ones you can dispel, only a
-- boss's, or none that last too long. The client's container does the
-- filtering, so it holds in a fight. The checks below do the same out of
-- combat, for the hover and the counts.

Auras.NONE = "none"
Auras.DISPEL_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"

-- The spell ids of the list a bar picked for mode ("hide" or "only"), or nil.
local function listIds(scope, key, mode)
    local AL = DaylightUI.AuraLists
    local id = BL.GetSetting(key, scope)
    if not AL or type(id) ~= "string" or id == Auras.NONE or AL.ModeOf(id) ~= mode then return nil end
    return AL.Ids(id)
end
function Auras.HideIds(scope) return listIds(scope, "hideList", "hide") end
function Auras.OnlyIds() return listIds(nil, "onlyList", "only") end

local function union(a, b)
    if not b then return a end
    local out = {}
    for id in pairs(a) do out[id] = true end
    for id in pairs(b) do out[id] = true end
    return out
end

local function both(a, b)
    if not b then return a end
    local out = {}
    for id in pairs(a) do if b[id] then out[id] = true end end
    return out
end

-- A buff category's candidate filters: its own spells (Other: every spell no
-- category claims), without the hide list, cut to the show-only list.
function Auras.BuffFilters(id, sets)
    local hide, only = Auras.HideIds(), Auras.OnlyIds()
    if id == "other" then
        return { excludeSpellIDs = union(sets.categorised, hide), includeSpellIDs = only }
    end
    return { includeSpellIDs = both(sets.byCategory[id] or {}, only), excludeSpellIDs = hide }
end

function Auras.ShowsBuff(spellId)
    local hide, only = Auras.HideIds(), Auras.OnlyIds()
    if hide and spellId and hide[spellId] then return false end
    if only and not (spellId and only[spellId]) then return false end
    return true
end

-- The debuff bar's group: every debuff, or only the ones you can dispel.
function Auras.DebuffGroup()
    return BL.GetSetting("filter", "debuff") == "dispel" and "dispel" or "debuffs"
end

local function longest()
    local t = tonumber(BL.GetSetting("maxTime", "debuff")) or 0
    return t > 0 and t or nil
end

function Auras.DebuffFilters()
    return {
        excludeSpellIDs = union(BL.QUIET_DEBUFFS, Auras.HideIds("debuff")),
        isBossAura = BL.GetSetting("bossOnly", "debuff") == true or nil,
        maxDuration = longest(),
    }
end

-- The client matches a debuff on you by spell only when the game marks that
-- spell never secret (Sated and the like), so a hide list skips the rest.
local function matchable(id)
    local AL = DaylightUI.AuraLists
    return AL and AL.Everywhere(id)
end

-- Drops the debuffs the bar's filters leave out from entries, in place.
function Auras.KeepDebuffs(entries)
    local hide, boss, t = Auras.HideIds("debuff"), BL.GetSetting("bossOnly", "debuff") == true, longest()
    if not (hide or boss or t) then return entries end
    local n = 0
    for _, e in ipairs(entries) do
        local id = e.spellId
        local keep = not (hide and id and hide[id] and matchable(id))
            and not (boss and not e.boss)
            and not (t and (not e.duration or e.duration == 0 or e.duration > t))
        if keep then n = n + 1; entries[n] = e end
    end
    for i = #entries, n + 1, -1 do entries[i] = nil end
    return entries
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
    local Weapons = DUI.Weapons
    for _, slotID in ipairs(slots) do
        local invSlot = Weapons.INVENTORY[slotID]
        local list, refused = Weapons.Read(slotID, Auras.readInto)
        Auras.readInto = list
        if refused then return trim(entries, 0), true, 0 end
        for _, enchant in ipairs(invSlot and list or {}) do
            if skipDrawn and containerDraws(invSlot, enchant, enchant.kind) then
                skipped = skipped + 1
            else
                n = n + 1
                local e = entries[n]
                if type(e) ~= "table" then e = {}; entries[n] = e end
                e.kind = "weapon"
                e.slot = invSlot
                e.weaponSlot = slotID
                e.enchantType = enchant.kind
                e.name = (not skipNames and Weapons.Name(invSlot)) or "Weapon Enchant"
                e.icon = enchant.icon
                e.applications = enchant.charges
                e.expirationTime = now + enchant.msLeft / 1000
                e.timed = true
            end
        end
    end
    return trim(entries, n), false, skipped
end

