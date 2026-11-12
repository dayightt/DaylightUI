-- Addon-made pieces for the Cooldown Manager layout: every class spell with a cooldown
-- or duration, plus group buffs others cast on you (from CdmSpells). They are keyed
-- "s<rank 1 id>", while the game's own pieces use numeric cooldown ids. CdmOwn and
-- CdmAuras ask this file for the spell, ranks, look and track of these pieces.

local _, ns = ...
local DUI = DaylightUI

local Custom = {}
ns.CdmCustom = Custom

local index        -- [key] = { ids, cd, aura, group }, class spells then GROUP
local order        -- keys in list order
local learned = {} -- [key] = highest known rank, or false
local entries = {} -- [key] = cached Custom.Entry table
local auraKeys     -- [spell id] = family key, for families with an aura (built lazily)
local added = {}   -- [key] = family of a spell or item added by ID
local classSpells  -- [spell id] = true for every rank on any class list (built lazily)

local function plain(v)
    return not (issecretvalue and issecretvalue(v)) and v or nil
end

-- Paladin "seal" piece: watches every rank of every seal and shows whichever is up.
-- The client draws that seal's icon and time. Listed by rank 1 id, Righteousness
-- last so its rank is the fallback look.
Custom.SEALS = { 20375, 1311649, 20164, 20165, 20166, 21082, 20154 }
-- A later expansion's seal icon that no Forever spell uses, so the empty slot
-- isn't mistaken for Righteousness.
Custom.SEAL_ICON = "Interface/Icons/Spell_Holy_SealOfVengeance"

-- Paladin "aura" piece, same idea as the seal. With Buff missing it glows when no
-- aura is up, which is easy to forget after a rez. The generated list skips auras
-- since they have no cooldown or duration, so they're listed here, rank 1 first.
Custom.AURAS = {
    { 465, 10290, 643, 10291, 1032, 10292, 10293 },     -- Devotion Aura
    { 7294, 10298, 10299, 10300, 10301 },               -- Retribution Aura
    { 19746 },                                          -- Concentration Aura
    { 19876, 19895, 19896 },                            -- Shadow Resistance Aura
    { 19888, 19897, 19898 },                            -- Frost Resistance Aura
    { 19891, 19899, 19900 },                            -- Fire Resistance Aura
    { 20218 },                                          -- Sanctity Aura
}
-- A later expansion's aura icon, so it isn't mistaken for one specific aura.
Custom.AURA_ICON = "Interface/Icons/Spell_Holy_AuraMastery"

-- Addon-made keys: "seal", "aura", "s<spell id>" (a list family or a spell added
-- by ID in the editor) and "i<item id>" (an item added by ID).
function Custom.Is(id)
    return type(id) == "string" and (id == "seal" or id == "aura" or id:match("^[si]%d+$") ~= nil)
end

-- The item of an "i<item id>" piece, else nil.
function Custom.ItemOf(id)
    local n = type(id) == "string" and id:match("^i(%d+)$")
    return n and tonumber(n) or nil
end

-- Ranks missing from the generated list, by the family's rank 1 id. Each is
-- inserted right after it. Seal of Righteousness Rank 1 is 21084 in game.
Custom.MORE_RANKS = { [20154] = { 21084 } }

-- Spells whose buff or debuff has its own spell id, by the family's rank 1 id.
-- Arcane Blast's stacking debuff is 400573 (up to 4 stacks, carries the damage
-- and mana cost increase; the casts themselves only deal damage).
Custom.AURA_IDS = { [400574] = { 400573 } }
-- Spells that put a debuff on yourself, by the family's rank 1 id. CdmAuras draws
-- them from your own casts, never from the target. Duration and stacks come from
-- the game's data and cover the case where the spell text isn't loaded yet.
Custom.SELF_DEBUFF = { [400574] = { lasts = 18, stacks = 4 } }

-- Duration and stacks for a SELF_DEBUFF piece, or nil.
function Custom.SelfDebuffFacts(key)
    local f = Custom.Is(key) and Custom.Family(key)
    local first = f and f.ids and f.ids[1]
    local t = first and Custom.SELF_DEBUFF[first]
    return type(t) == "table" and t or nil
end

local function withMore(f)
    local more = Custom.MORE_RANKS[f[1]]
    if not more then return f end
    local out = { f[1] }
    for _, s in ipairs(more) do out[#out + 1] = s end
    for i = 2, #f do out[#out + 1] = f[i] end
    for k, v in pairs(f) do if type(k) ~= "number" then out[k] = v end end
    return out
end

local function sealFamily(list)
    local byFirst = {}
    for _, f in ipairs(list) do
        if type(f) == "table" and type(f[1]) == "number" then byFirst[f[1]] = withMore(f) end
    end
    local ids = {}
    for _, first in ipairs(Custom.SEALS) do
        for _, s in ipairs(byFirst[first] or {}) do ids[#ids + 1] = s end
    end
    if #ids == 0 then return nil end
    return { ids = ids, aura = true, self = true, name = DUI.L["Seal"], icon = Custom.SEAL_ICON }
end

local function auraFamily()
    local ids = {}
    for _, f in ipairs(Custom.AURAS) do
        for _, s in ipairs(f) do ids[#ids + 1] = s end
    end
    return { ids = ids, aura = true, self = true, name = DUI.L["Aura"], icon = Custom.AURA_ICON }
end

local function build()
    if index then return end
    index, order = {}, {}
    local S = ns.CdmSpells or {}
    local function add(f, group)
        if type(f) ~= "table" or type(f[1]) ~= "number" then return end
        local k = "s" .. f[1]
        if index[k] then return end
        index[k] = { ids = withMore(f), cd = f.cd == true and not group, aura = group or f.aura == true, group = group or nil,
                     auras = Custom.AURA_IDS[f[1]], self = Custom.SELF_DEBUFF[f[1]] ~= nil or nil,
                     harm = Custom.SELF_DEBUFF[f[1]] ~= nil or nil }
        order[#order + 1] = k
    end
    local _, class = UnitClass("player")
    class = plain(class)
    if class == "PALADIN" then
        local seal = sealFamily(S.PALADIN or {})
        if seal then index.seal = seal; order[#order + 1] = "seal" end
        index.aura = auraFamily(); order[#order + 1] = "aura"
    end
    if type(class) == "string" then
        for _, f in ipairs(S[class] or {}) do add(f, false) end
    end
    for _, f in ipairs(S.GROUP or {}) do add(f, true) end
end

-- Rebuild everything when spells or talents change.
function Custom.Forget()
    index, order, auraKeys, classSpells = nil, nil, nil, nil
    for k in pairs(learned) do learned[k] = nil end
    for k in pairs(added) do added[k] = nil end
end
for _, e in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
    DUI.RegisterEvent(e, Custom.Forget)
end

-- An item's use spell, or nil if its data isn't loaded yet (a load is requested).
local function useSpell(item)
    if type(C_Item) ~= "table" or type(C_Item.GetItemSpell) ~= "function" then return nil end
    local ok, _, sid = pcall(C_Item.GetItemSpell, item)
    sid = ok and plain(sid) or nil
    if type(sid) ~= "number" and type(C_Item.RequestLoadItemDataByID) == "function" then
        pcall(C_Item.RequestLoadItemDataByID, item)
    end
    return type(sid) == "number" and sid or nil
end

-- True for any rank on any class list (not group buffs). If you don't know it,
-- it's another class's spell or a talent you don't have.
local function classSpell(sid)
    if not classSpells then
        classSpells = {}
        for name, list in pairs(ns.CdmSpells or {}) do
            if name ~= "GROUP" and type(list) == "table" then
                for _, f in ipairs(list) do
                    if type(f) == "table" then
                        for _, s in ipairs(f) do classSpells[s] = true end
                    end
                end
            end
        end
    end
    return classSpells[sid] == true
end

-- A piece added by ID: a spell (cooldown or buff), or an item with a use effect
-- (its cooldown, or its use spell's buff). Items with unloaded data aren't cached,
-- so they're retried. A spell on no class list is treated like a group buff
-- someone else puts on you (onYou), e.g. a totem's Mana Spring (5677).
local function addedFamily(id)
    local f = added[id]
    if f then return f end
    local item = Custom.ItemOf(id)
    if item then
        local sid = useSpell(item)
        if not sid then return nil end
        f = { ids = { sid }, cd = true, aura = true, item = item, user = true }
    else
        local sid = tonumber(id:match("^s(%d+)$"))
        if not sid then return nil end
        f = { ids = { sid }, cd = true, aura = true, user = true, onYou = not classSpell(sid) or nil }
    end
    added[id] = f
    return f
end

-- An added spell you don't know, cast on you by someone else: no cooldown of
-- yours, buff only. Still watched like any added spell, so Weakened Soul (also
-- on no list) works on your target too.
local function worn(id, f)
    return f.onYou == true and not Custom.Learned(id)
end
local function hasCd(id, f)
    return f.cd and not worn(id, f)
end

function Custom.Family(id)
    if not Custom.Is(id) then return nil end
    build()
    return index[id] or addedFamily(id)
end

-- Added by ID rather than from the generated list.
function Custom.IsAdded(id)
    local f = Custom.Family(id)
    return f ~= nil and f.user == true
end

-- The list's family this spell is a rank of (any rank, group buffs too), or nil.
function Custom.KeyOfSpell(sid)
    build()
    for k, f in pairs(index) do
        for _, s in ipairs(f.ids) do if s == sid then return k end end
    end
end

-- An item piece's cooldown in the same shape the spell calls return: whether it's
-- on a real cooldown (not the GCD), and a client duration object for the swipe and
-- bar, one per piece. Item cooldowns are never secret, even in combat.
Custom.ITEM_GCD = 1.5
local durations = {}
function Custom.ItemCooldown(id)
    local item = Custom.ItemOf(id)
    local get = type(C_Container) == "table" and C_Container.GetItemCooldown
    if not item or type(get) ~= "function" then return false, nil end
    local ok, start, dur, on = pcall(get, item)
    start, dur, on = ok and plain(start), ok and plain(dur), ok and plain(on)
    if type(start) ~= "number" or type(dur) ~= "number" or dur <= Custom.ITEM_GCD or on == 0 or on == false then
        return false, nil
    end
    local D = _G.C_DurationUtil
    if type(D) ~= "table" or type(D.CreateDuration) ~= "function" then return true, nil end
    local d = durations[id] or D.CreateDuration()
    durations[id] = d
    d:SetTimeFromStart(start, dur)
    return true, d
end

-- Item count, shown the way action buttons show it: only for consumables or
-- stacking items (potions, Healthstones, including 0), never a trinket's 1.
-- Returns nil when no count should show.
function Custom.ItemCount(id)
    local item = Custom.ItemOf(id)
    local I = type(C_Item) == "table" and C_Item
    if not item or not I or type(I.GetItemCount) ~= "function" then return nil end
    local used = false
    if type(I.IsConsumableItem) == "function" then
        local ok, yes = pcall(I.IsConsumableItem, item)
        used = ok and plain(yes) == true
    end
    if not used and type(I.GetItemMaxStackSizeByID) == "function" then
        local ok, most = pcall(I.GetItemMaxStackSizeByID, item)
        most = ok and plain(most)
        used = type(most) == "number" and most > 1
    end
    if not used then return nil end
    local ok, n = pcall(I.GetItemCount, item, false, true)
    n = ok and plain(n)
    return type(n) == "number" and n or 0
end

-- For item pieces: usable now, and whether only mana is missing. nil otherwise.
function Custom.ItemUsable(id)
    local item = Custom.ItemOf(id)
    local can = item and type(C_Item) == "table" and C_Item.IsUsableItem
    if type(can) ~= "function" then return nil end
    local ok, yes, noMana = pcall(can, item)
    if not ok or (issecretvalue and (issecretvalue(yes) or issecretvalue(noMana))) then return nil end
    return yes, noMana
end

-- Key of the class family with an aura that this spell id belongs to, or nil.
-- Some game cooldowns' auras are only known here (Bloodrage, see CdmOwn.QuietAura).
function Custom.KeyOfAuraSpell(sid)
    build()
    if not auraKeys then
        auraKeys = {}
        for k, f in pairs(index) do
            if f.aura and not f.group then
                for _, s in ipairs(f.ids) do auraKeys[s] = k end
            end
        end
    end
    return auraKeys[sid]
end

-- The highest rank you know, or nil.
function Custom.Learned(id)
    local f = Custom.Family(id)
    if not f then return nil end
    -- Items count as known even when not in your bags. CdmEffects grays the
    -- icon while it can't be used.
    if f.item then return f.ids[1] end
    local v = learned[id]
    if v == nil then
        v = false
        local known = type(C_SpellBook) == "table" and C_SpellBook.IsSpellKnown
        if type(known) == "function" then
            for i = #f.ids, 1, -1 do
                local ok, yes = pcall(known, f.ids[i])
                if ok and plain(yes) == true then v = f.ids[i]; break end
            end
        end
        learned[id] = v
    end
    return v or nil
end

-- Spell to time and show: highest known rank (ranks share a cooldown), else
-- rank 1 for group buffs and unlearned spells.
function Custom.SpellOf(id)
    local f = Custom.Family(id)
    return f and (Custom.Learned(id) or f.ids[1]) or nil
end

-- Every rank, for the aura filter: a lower rank someone else cast still shows.
function Custom.Ranks(id)
    local out, f = {}, Custom.Family(id)
    if f then
        for _, s in ipairs(f.ids) do out[s] = true end
        for _, s in ipairs(f.auras or {}) do out[s] = true end
    end
    return out
end

-- Another class's buff on you. The tray lists these behind their own switch.
function Custom.IsGroup(id)
    local f = Custom.Family(id)
    return f ~= nil and f.group == true
end

-- Group buffs, the seal and the aura are only watched on you.
function Custom.SelfOnly(id)
    local f = Custom.Family(id)
    return f ~= nil and (f.group == true or f.self == true)
end

-- The debuff lands on you (Arcane Blast), so your own debuffs are watched too.
function Custom.SelfDebuff(id)
    local f = Custom.Family(id)
    return f ~= nil and f.harm == true
end

-- Name and icon. The seal piece uses a generic name because which seal is up
-- can't be read in combat. The client draws the active seal's icon over ours.
function Custom.Look(id)
    local item = Custom.ItemOf(id)
    if item and type(C_Item) == "table" then
        local okN, name = false, nil
        if type(C_Item.GetItemNameByID) == "function" then okN, name = pcall(C_Item.GetItemNameByID, item) end
        local okT, tex = false, nil
        if type(C_Item.GetItemInfoInstant) == "function" then okT, tex = pcall(function() return select(5, C_Item.GetItemInfoInstant(item)) end) end
        name = okN and type(name) == "string" and plain(name) or nil
        return name, okT and type(tex) ~= "nil" and tex or nil
    end
    local sid = Custom.SpellOf(id)
    if not sid or type(C_Spell) ~= "table" then return nil, nil end
    local okN, name = pcall(C_Spell.GetSpellName, sid)
    local okT, tex = pcall(C_Spell.GetSpellTexture, sid)
    name = okN and type(name) == "string" and plain(name) or nil
    local f = Custom.Family(id)
    return f and f.name or name, f and f.icon or okT and type(tex) ~= "nil" and tex or nil
end

-- A spell of your class with both a cooldown and a buff (Bloodrage).
function Custom.CanTrack(id)
    local f = Custom.Family(id)
    return f ~= nil and hasCd(id, f) and f.aura or false
end

-- "cooldown" or "aura": the piece's saved choice (Data.SetTrack) if the spell
-- supports it, else its cooldown if it has one, else its buff.
function Custom.Track(id, set)
    local f = Custom.Family(id)
    if not f then return nil end
    set = set or (ns.CdmData and ns.CdmData.Current())
    local p = type(set) == "table" and type(set.pieces) == "table" and set.pieces[id] or nil
    local t = p and p.track
    -- Buff missing mode tracks the buff, shown only while it's up.
    if p and p.hideMissing == true and f.aura then return "aura" end
    if t == "aura" and f.aura then return "aura" end
    if t == "cooldown" and hasCd(id, f) then return "cooldown" end
    -- Spells added by ID: the cooldown if it has a real one, else the buff.
    if f.user and not f.item then
        if worn(id, f) then return "aura" end
        local Own = ns.CdmOwn
        return (Own == nil or Own.HasCooldown(f.ids[1])) and "cooldown" or "aura"
    end
    return f.cd and "cooldown" or "aura"
end

-- Same shape as CdmOwn.Known() entries. nil for class spells you don't know;
-- group buffs always count.
function Custom.Entry(id)
    local f = Custom.Family(id)
    if not f or not (f.group or f.item or f.onYou or Custom.Learned(id)) then return nil end
    local e = entries[id]
    if not e then
        e = { kind = "icon", custom = true }
        entries[id] = e
    end
    e.aura = Custom.Track(id) == "aura"
    return e
end

-- Extra spells for the editor tray: known class spells, then group buffs.
-- Each is { id, aura }.
function Custom.Tray()
    build()
    local out, group = {}, {}
    for _, k in ipairs(order) do
        local e = { id = k, aura = Custom.Track(k) == "aura" }
        if index[k].group then
            group[#group + 1] = e
        elseif Custom.Learned(k) then
            out[#out + 1] = e
        end
    end
    for _, e in ipairs(group) do out[#out + 1] = e end
    return out
end

-- Class spells you don't know, for the tray's Other talents section.
function Custom.Unlearned()
    build()
    local out = {}
    for _, k in ipairs(order) do
        if not index[k].group and not Custom.Learned(k) then
            out[#out + 1] = { id = k, aura = Custom.Track(k) == "aura", unlearned = true }
        end
    end
    return out
end
