-- Addon-made pieces for the Cooldown Manager layout: every class spell with a cooldown
-- or duration, plus group buffs others cast on you (from CdmSpells). They are keyed
-- "s<rank 1 id>", while the game's own pieces use numeric cooldown ids. CdmOwn and
-- CdmAuras ask this file for the spell, ranks, look and track of these pieces.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret

local Custom = {}
ns.CdmCustom = Custom

local index        -- [key] = { ids, cd, aura, group }, class spells then GROUP
local totemRanks   -- [any rank id] = { slot, key, noBuff } for TOTEMS and TOTEM_SLOTS (build)
local slotRanks    -- [any rank id] = { slot, cools } for every totem on the three lists (build)
local order        -- keys in list order
local learned = {} -- [key] = highest known rank, or false
local entries = {} -- [key] = cached Custom.Entry table
local auraKeys     -- [spell id] = family key, for families with an aura (built lazily)
local added = {}   -- [key] = family of a spell or item added by ID
local classSpells  -- [spell id] = true for every rank on any class list (built lazily)

local function plain(v)
    return not isSecret(v) and v or nil
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

-- Paladin "blessing" piece, same idea as the seal: any of the paladin's long
-- Blessings on you, whoever cast it, so Buff missing can glow when none is. The
-- short ones (Protection, Freedom, Sacrifice) don't count. By rank 1 id, from the
-- generated list.
Custom.BLESSINGS = { 19740, 19742, 20217, 1038, 19977, 25782, 25894, 25898, 25895, 25890 }
-- It wears Blessing of Might's icon, asked of the client when drawn. Until the
-- client knows the spell, the file that icon comes from.
Custom.BLESSING_SPELL = 19740
Custom.BLESSING_ICON = "Interface/Icons/Spell_Holy_FistOfJustice"

-- Your class's buffs that another player can also put on you (another warrior's
-- Battle Shout, a second hunter's Trueshot Aura), by rank 1 id. Every family on
-- the GROUP list counts too. The game's own icon only finds a buff you cast.
Custom.SHARED = { [6673] = true, [1299346] = true }

-- Debuffs a target carries only one copy of, whoever cast it, so another player's
-- counts as yours (Sunder Armor, the curses). A DoT each caster keeps their own of
-- (Rend, Corruption) isn't here: only your copy counts. By rank 1 id.
Custom.UNIQUE = {
    [7386] = true,    -- Sunder Armor
    [1160] = true,    -- Demoralizing Shout
    [6343] = true,    -- Thunder Clap
    [99] = true,      -- Demoralizing Roar
    [770] = true,     -- Faerie Fire
    [1130] = true,    -- Hunter's Mark
    [8647] = true,    -- Expose Armor
    [704] = true,     -- Curse of Recklessness
    [1714] = true,    -- Curse of Tongues
    [702] = true,     -- Curse of Weakness
    [440892] = true,  -- Curse of the Elements
    [18223] = true,   -- Curse of Exhaustion
}

-- Hunter and warlock "pet" piece: up while your pet is out and alive, so Buff
-- missing can glow when it isn't. Not an aura, so CdmAuras draws it itself. The
-- spells only say whether you have a pet at all; the last one you know is its look
-- (Call Pet, Summon Imp).
Custom.PETS = {
    HUNTER = { 1515, 883 },                 -- Tame Beast, Call Pet
    WARLOCK = { 691, 712, 697, 688 },       -- Felhunter, Succubus, Voidwalker, Imp
}

-- Shaman element pieces: one per totem slot, showing whichever totem stands there,
-- then a cooldown totem's cooldown once it's gone (Custom.SlotNow).
Custom.TOTEM_ELEMENTS = {
    fire = { slot = 1, name = "Fire totem", icon = "Interface/Icons/Spell_Fire_Elemental_Totem" },
    earth = { slot = 2, name = "Earth totem", icon = "Interface/Icons/Spell_Nature_EarthElemental_Totem" },
    water = { slot = 3, name = "Water totem", icon = "Interface/Icons/Spell_Frost_SummonWaterElemental_2" },
    air = { slot = 4, name = "Air totem", icon = "Interface/Icons/INV_Elemental_Primal_Air" },
}
Custom.ELEMENT_ORDER = { "fire", "earth", "water", "air" }

-- Addon-made keys: "seal", "aura", "blessing", "pet", the elements, "s<spell id>" (a
-- list family or a spell added by ID in the editor) and "i<item id>" (an item added by ID).
Custom.NAMED = { seal = true, aura = true, blessing = true, pet = true,
                 fire = true, earth = true, water = true, air = true }
function Custom.Is(id)
    return type(id) == "string" and (Custom.NAMED[id] == true or id:match("^[si]%d+$") ~= nil)
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
-- and mana cost increase; the casts themselves only deal damage). A passive from
-- the list is offered only once its buff is named here, as the passive itself
-- never shows as a buff. A rogue's Poised buff is 1328826.
-- A hunter's trap is an object on the ground; the debuff on whatever walks into it
-- is another spell: Freezing Trap's freeze, Immolation and Explosive Trap's burn,
-- Frost Trap's slow.
Custom.AURA_IDS = {
    [400574] = { 400573 }, [1328825] = { 1328826 },
    [1499] = { 3355, 14308, 14309, 1294353 },
    [13795] = { 13797, 14298, 14299, 14300, 14301 },
    [13813] = { 13812, 14314, 14315 },
    [13809] = { 13810 },
}
-- Traps, by rank 1 id. Laying one down puts nothing up yet, so a cast never says
-- the debuff is up; only the client's button does, once a mob walks in.
Custom.TRAPS = { [1499] = true, [13795] = true, [13813] = true, [13809] = true }
-- Spells whose buff lands on your pet (the game's data targets the pet): Bestial
-- Wrath, Mend Pet, Intimidation, Eyes of the Beast, Health Funnel, and a pet's own
-- Dash and Dive. Watched on your pet as well as on you.
Custom.ON_PET = { [19574] = true, [136] = true, [19577] = true, [1002] = true, [755] = true,
                  [23099] = true, [23145] = true }
-- Spells that summon a helper for a while instead of putting up an aura, by rank 1
-- id: Summon Hawk's hawk stays 18 s, two at most (the game's data). Timed from your
-- own casts, the newest hawk's time shown with how many are out.
Custom.SUMMONS = { [1293241] = { lasts = 18, most = 2 } }
-- Totem slots: 1 fire, 2 earth, 3 water, 4 air. Totems with a cooldown (Grounding,
-- Earthbind, Stoneclaw, Mana Tide) are on neither list: their piece shows the
-- cooldown, since the totem can outlast it or end before it.
-- Totems that put no buff on you and have no cooldown, by rank 1 id, with their
-- slot. The spell list flags them as buffs. Their pieces show the totem's time
-- while it stands (Custom.TotemUp): Totem, or the game's icon with Cooldown.
Custom.TOTEMS = {
    [3599] = 1, [8190] = 1,             -- Searing, Magma
    [8143] = 2,                         -- Tremor
    [5394] = 3, [8166] = 3, [8170] = 3, -- Healing Stream, Poison Cleansing, Disease Cleansing
    [6495] = 4,                         -- Sentry
}
-- Totems that put a buff on you while you're in range, by rank 1 id, with their
-- slot. Their pieces show the totem's time with the buff over it (Totem and buff).
Custom.TOTEM_SLOTS = {
    [8227] = 1, [8181] = 1,                         -- Flametongue, Frost Resistance
    [8071] = 2, [8075] = 2,                         -- Stoneskin, Strength of Earth
    [8184] = 3, [5675] = 3,                         -- Fire Resistance, Mana Spring
    [8835] = 4, [10595] = 4, [8512] = 4, [15107] = 4, -- Grace of Air, Nature Resistance, Windfury, Windwall
}
-- Totems with a cooldown, by rank 1 id, with their slot. Only the element pieces
-- time them from the slot; their own pieces show the cooldown.
Custom.TOTEM_COOLDOWNS = {
    [2484] = 2, [5730] = 2,     -- Earthbind, Stoneclaw
    [16190] = 3,                -- Mana Tide
    [8177] = 4,                 -- Grounding
}
-- Spells that put a debuff on yourself, by the family's rank 1 id. CdmAuras draws
-- them from your own casts, never from the target. Duration and stacks come from
-- the game's data and cover the case where the spell text isn't loaded yet.
Custom.SELF_DEBUFF = {
    [400574] = { lasts = 18, stacks = 4 },
    -- Weakened Soul, added by its ID: put on you by your own Power Word: Shield (`from`).
    [6788] = { lasts = 15, stacks = 1, from = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 } },
}

-- Duration and stacks for a SELF_DEBUFF piece, or nil.
function Custom.SelfDebuffFacts(key)
    local f = Custom.Is(key) and Custom.Family(key)
    local first = f and f.ids and f.ids[1]
    local t = first and Custom.SELF_DEBUFF[first]
    return type(t) == "table" and t or nil
end

-- How long a SUMMONS piece's helper stays and how many can be out, or nil.
function Custom.SummonFacts(key)
    local f = Custom.Is(key) and Custom.Family(key)
    local first = f and f.ids and f.ids[1]
    local t = first and Custom.SUMMONS[first]
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

-- Every rank of the list's families whose rank 1 id is in firsts, as one piece.
-- merged = each of those spells also has a piece of its own, which wins when a
-- spell id is looked up.
local function mergedFamily(list, firsts, name, icon)
    local byFirst = {}
    for _, f in ipairs(list) do
        if type(f) == "table" and type(f[1]) == "number" then byFirst[f[1]] = withMore(f) end
    end
    local ids = {}
    for _, first in ipairs(firsts) do
        for _, s in ipairs(byFirst[first] or {}) do ids[#ids + 1] = s end
    end
    if #ids == 0 then return nil end
    return { ids = ids, aura = true, self = true, merged = true, name = name, icon = icon }
end

local function sealFamily(list)
    return mergedFamily(list, Custom.SEALS, DUI.L["Seal"], Custom.SEAL_ICON)
end

local function auraFamily()
    local ids = {}
    for _, f in ipairs(Custom.AURAS) do
        for _, s in ipairs(f) do ids[#ids + 1] = s end
    end
    return { ids = ids, aura = true, self = true, name = DUI.L["Aura"], icon = Custom.AURA_ICON }
end

-- Every rank of every totem in the slot, from the class list.
local function elementFamily(list, key)
    local e = Custom.TOTEM_ELEMENTS[key]
    local ids = {}
    for _, f in ipairs(list) do
        local first = type(f) == "table" and f[1]
        if type(first) == "number" and (Custom.TOTEMS[first] or Custom.TOTEM_SLOTS[first]
            or Custom.TOTEM_COOLDOWNS[first]) == e.slot then
            for _, s in ipairs(f) do ids[#ids + 1] = s end
        end
    end
    if #ids == 0 then return nil end
    return { ids = ids, cd = true, aura = true, self = true, merged = true, element = e,
             name = DUI.L[e.name], icon = e.icon }
end

local function build()
    if index then return end
    index, order = {}, {}
    local S = ns.CdmSpells or {}
    local fromGroup = {}
    for _, f in ipairs(S.GROUP or {}) do
        if type(f) == "table" and type(f[1]) == "number" then fromGroup[f[1]] = true end
    end
    local function add(f, group)
        if type(f) ~= "table" or type(f[1]) ~= "number" then return end
        local k = "s" .. f[1]
        if index[k] or (f.passive and not Custom.AURA_IDS[f[1]]) then return end
        local shared = f.aura == true and (Custom.SHARED[f[1]] or fromGroup[f[1]]) or nil
        local aura = group or (f.aura == true and Custom.TOTEMS[f[1]] == nil)
        index[k] = { ids = withMore(f), cd = f.cd == true and not group, aura = aura, group = group or nil,
                     shared = shared, unique = f.aura == true and Custom.UNIQUE[f[1]] or nil,
                     auras = Custom.AURA_IDS[f[1]], self = Custom.SELF_DEBUFF[f[1]] ~= nil or nil,
                     harm = Custom.SELF_DEBUFF[f[1]] ~= nil or nil,
                     trap = Custom.TRAPS[f[1]], onPet = Custom.ON_PET[f[1]] }
        order[#order + 1] = k
    end
    local _, class = UnitClass("player")
    class = plain(class)
    if class == "PALADIN" then
        local seal = sealFamily(S.PALADIN or {})
        if seal then index.seal = seal; order[#order + 1] = "seal" end
        index.aura = auraFamily(); order[#order + 1] = "aura"
        local blessing = mergedFamily(S.PALADIN or {}, Custom.BLESSINGS, DUI.L["Blessing"], Custom.BLESSING_ICON)
        if blessing then
            blessing.iconSpell = Custom.BLESSING_SPELL
            index.blessing = blessing; order[#order + 1] = "blessing"
        end
    end
    if class == "SHAMAN" then
        for _, key in ipairs(Custom.ELEMENT_ORDER) do
            local f = elementFamily(S.SHAMAN or {}, key)
            if f then index[key] = f; order[#order + 1] = key end
        end
    end
    if type(class) == "string" and Custom.PETS[class] then
        index.pet = { ids = Custom.PETS[class], aura = true, self = true, pet = true, name = DUI.L["Pet"] }
        order[#order + 1] = "pet"
    end
    if type(class) == "string" then
        for _, f in ipairs(S[class] or {}) do add(f, false) end
    end
    for _, f in ipairs(S.GROUP or {}) do add(f, true) end
    -- Every rank of every totem, for a one-lookup Custom.Totem and Custom.SlotOf.
    totemRanks, slotRanks = {}, {}
    for k, f in pairs(index) do
        local first = not f.element and f.ids and f.ids[1]
        local slot = first and (Custom.TOTEMS[first] or Custom.TOTEM_SLOTS[first])
        if slot then
            local t = { slot = slot, key = k, noBuff = Custom.TOTEMS[first] ~= nil }
            for _, s in ipairs(f.ids) do totemRanks[s] = t end
        end
        local cools = first and Custom.TOTEM_COOLDOWNS[first]
        if slot or cools then
            local t = { slot = slot or cools, cools = cools ~= nil }
            for _, s in ipairs(f.ids) do slotRanks[s] = t end
        end
    end
end

-- Rebuild everything when spells or talents change.
function Custom.Forget()
    index, order, auraKeys, classSpells, totemRanks, slotRanks = nil, nil, nil, nil, nil, nil
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
        local harm = Custom.SELF_DEBUFF[sid] ~= nil or nil
        f = { ids = { sid }, cd = true, aura = true, user = true, onYou = not classSpell(sid) or nil,
              self = harm, harm = harm }
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
        if not (f.merged or f.pet) then
            for _, s in ipairs(f.ids) do if s == sid then return k end end
        end
    end
end

-- Any rank of a totem on TOTEMS or TOTEM_SLOTS: its slot and family key, or nil.
function Custom.Totem(sid)
    if type(sid) ~= "number" or isSecret(sid) then return nil end
    build()
    local t = totemRanks[sid]
    if t then return t.slot, t.key end
end

-- Any rank of any totem, cooldown totems too: its slot, and whether it has a cooldown.
function Custom.SlotOf(sid)
    if type(sid) ~= "number" or isSecret(sid) then return nil end
    build()
    local t = slotRanks[sid]
    if t then return t.slot, t.cools end
end

-- An element piece's TOTEM_ELEMENTS entry, else nil.
function Custom.Element(id)
    local f = type(id) == "string" and Custom.TOTEM_ELEMENTS[id] and Custom.Family(id)
    return f and f.element or nil
end

-- Whether a cast of any rank of this totem has taught its buff (CdmOwn.AuraOf).
-- Until then its buff's id isn't known, so nothing could show it.
function Custom.TotemBuffKnown(sid)
    local _, k = Custom.Totem(sid)
    local Own = ns.CdmOwn
    if not (k and Own and Own.AuraOf) then return false end
    for _, id in ipairs(index[k].ids) do
        if Own.AuraOf(id) then return true end
    end
    return false
end

-- Any rank of a totem that puts no buff on you (TOTEMS): its slot and family key.
function Custom.TotemNoBuff(sid)
    if type(sid) ~= "number" or isSecret(sid) then return nil end
    build()
    local t = totemRanks[sid]
    if t and t.noBuff then return t.slot, t.key end
end

-- Which totem stands in each slot: [slot] = family key. The slot's spell is
-- secret in a fight, but your own casts aren't, so a cast says which totem went in.
local standing = {}
local slotSpell = {}  -- [slot] = the rank standing there, false when not one of ours
local cooling = {}    -- [slot] = { sid, ends } for the last cooldown totem cast there
local castAt = {}   -- [slot] = when a totem was last cast into it
Custom.TOTEM_CAST_WINDOW = 1   -- seconds from the cast to its slot's update

-- The slot's spell: a totem of that slot, false for any other, nil when it can't
-- be read (secret in a fight). An unreadable slot keeps what the casts said.
local function readSlot(slot)
    if type(GetTotemInfo) ~= "function" then return nil end
    local okI, _, _, _, _, _, _, spell = pcall(GetTotemInfo, slot)
    spell = okI and plain(spell) or nil
    if type(spell) ~= "number" then return nil end
    return Custom.SlotOf(spell) == slot and spell or false
end

-- What a read slot holds: its timed totem's key, else false.
local function keyOf(spell)
    local _, key = Custom.Totem(spell or nil)
    return key or false
end

-- The totem's duration while this spell's totem stands, else nil. Whether the
-- slot returns a duration at all is never secret.
function Custom.TotemUp(sid)
    local slot, k = Custom.Totem(sid)
    if not slot or type(GetTotemDuration) ~= "function" then return nil end
    local ok, d = pcall(GetTotemDuration, slot)
    if not ok or type(d) == "nil" then return nil end
    if standing[slot] == nil then
        -- After a reload with a totem down: its spell, where it can be read.
        local spell = readSlot(slot)
        if spell ~= nil then standing[slot] = keyOf(spell) end
    end
    if standing[slot] == k then return d end
end

-- When a cooldown cast now ends, from the spell's base cooldown. nil when the
-- game won't say.
local function coolEnd(sid)
    local get = _G.GetSpellBaseCooldown
    if type(get) ~= "function" then return nil end
    local ok, ms = pcall(get, sid)
    if not ok or type(ms) ~= "number" or isSecret(ms) or ms <= 0 then return nil end
    return GetTime() + ms / 1000
end

-- What an element piece shows now: the standing rank, "totem" and the totem's
-- duration; else the last cooldown totem cast there, "cooldown"; else nil. A
-- cooldown past its base length is over. CdmEffects asks the game whether the
-- cooldown still runs.
function Custom.SlotNow(id)
    local e = Custom.Element(id)
    if not e or type(GetTotemDuration) ~= "function" then return nil end
    local slot = e.slot
    local ok, d = pcall(GetTotemDuration, slot)
    if ok and type(d) ~= "nil" then
        -- After a reload with a totem down: its spell, where it can be read.
        if slotSpell[slot] == nil then slotSpell[slot] = readSlot(slot) end
        if slotSpell[slot] then return slotSpell[slot], "totem", d end
    end
    local c = cooling[slot]
    if c and (c.ends == nil or GetTime() < c.ends) then return c.sid, "cooldown" end
end

local totems = CreateFrame("Frame")
totems:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
totems:RegisterEvent("PLAYER_TOTEM_UPDATE")
totems:SetScript("OnEvent", function(_, event, a, _, sid)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local slot, cools = Custom.SlotOf(sid)
        if not slot then return end
        -- A cooldown totem stands as none of the timed ones.
        local _, k = Custom.Totem(sid)
        standing[slot], slotSpell[slot], castAt[slot] = k or false, sid, GetTime()
        if cools then cooling[slot] = { sid = sid, ends = coolEnd(sid) } end
        return
    end
    local slot = plain(a)
    if type(slot) ~= "number" then return end
    local ok, d = pcall(GetTotemDuration, slot)
    if not ok or type(d) == "nil" then
        standing[slot], slotSpell[slot] = nil, nil
        return
    end
    -- An update with no cast of ours just before it: read its spell where it can
    -- be. A secret read keeps what the casts said.
    if GetTime() - (castAt[slot] or 0) > Custom.TOTEM_CAST_WINDOW then
        local spell = readSlot(slot)
        if spell ~= nil then standing[slot], slotSpell[slot] = keyOf(spell), spell end
    end
end)

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
    if not ok or isSecret(yes) or isSecret(noMana) then return nil end
    return yes, noMana
end

-- Key of the class family with an aura that this spell id belongs to, or nil.
-- Some game cooldowns' auras are only known here (Bloodrage, see CdmOwn.QuietAura).
function Custom.KeyOfAuraSpell(sid)
    build()
    if not auraKeys then
        auraKeys = {}
        for k, f in pairs(index) do
            if f.aura and not (f.group or f.merged or f.pet) then
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
-- An element piece's is the totem in its slot now (Custom.SlotNow), if any.
function Custom.SpellOf(id)
    local f = Custom.Family(id)
    if not f then return nil end
    local now = f.element and Custom.SlotNow(id)
    return now or Custom.Learned(id) or f.ids[1]
end

-- Every rank, for the aura filter: a lower rank someone else cast still shows.
-- The pet piece watches no aura.
function Custom.Ranks(id)
    local out, f = {}, Custom.Family(id)
    if f and not f.pet then
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

-- The pet piece: up while your pet is out (CdmAuras), not an aura.
function Custom.IsPet(id)
    local f = Custom.Family(id)
    return f ~= nil and f.pet == true
end

-- Group buffs, the seal, the aura and the blessing are only watched on you.
function Custom.SelfOnly(id)
    local f = Custom.Family(id)
    return f ~= nil and (f.group == true or f.self == true)
end

-- The debuff lands on you (Arcane Blast), so your own debuffs are watched too.
function Custom.SelfDebuff(id)
    local f = Custom.Family(id)
    return f ~= nil and f.harm == true
end

-- A trap: its debuff lands later, on whatever walks in.
function Custom.Trap(id)
    local f = Custom.Family(id)
    return f ~= nil and f.trap == true
end

-- Its buff can come from someone else too (Custom.SHARED).
function Custom.Shared(id)
    local f = Custom.Family(id)
    return f ~= nil and f.shared == true
end

-- Its debuff counts whoever cast it (Custom.UNIQUE).
function Custom.Unique(id)
    local f = Custom.Family(id)
    return f ~= nil and f.unique == true
end

-- Its buff lands on your pet (Bestial Wrath).
function Custom.OnPet(id)
    local f = Custom.Family(id)
    return f ~= nil and f.onPet == true
end

-- Name and icon. The seal piece uses a generic name because which seal is up
-- can't be read in combat. The client draws the active seal's icon over this one.
function Custom.Look(id)
    local e = Custom.Element(id)
    if e then return DUI.L[e.name], e.icon end
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
    if f and f.iconSpell then
        local okI, icon = pcall(C_Spell.GetSpellTexture, f.iconSpell)
        if okI and type(icon) ~= "nil" then return f.name or name, icon end
    end
    return f and f.name or name, f and f.icon or okT and type(tex) ~= "nil" and tex or nil
end

-- The card's What it shows can pick its cooldown, its buff or both. Not for
-- someone else's buff on you, the merged families (seal, aura, blessing, elements) or the pet,
-- which have no cooldown of yours to show.
function Custom.CanTrack(id)
    local f = Custom.Family(id)
    return f ~= nil and not (f.group or f.merged or f.pet) and not worn(id, f)
end

-- "cooldown", "aura" or "both": the piece's saved choice (Data.SetTrack) if the
-- spell can pick, else its cooldown if it has one, else its buff.
function Custom.Track(id, set)
    local f = Custom.Family(id)
    if not f then return nil end
    set = set or (ns.CdmData and ns.CdmData.Current())
    local p = type(set) == "table" and type(set.pieces) == "table" and set.pieces[id] or nil
    local t = p and p.track
    -- Buff missing mode tracks the buff, shown only while it's up.
    if p and p.hideMissing == true and f.aura then return "aura" end
    if (t == "aura" or t == "cooldown" or t == "both") and Custom.CanTrack(id) then return t end
    if t == "aura" and f.aura then return "aura" end
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
