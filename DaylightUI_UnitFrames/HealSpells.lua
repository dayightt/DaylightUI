-- Your class's heals over time, shields and helpful spells cast on others.
-- Used by the party/raid buff row's "Heals and shields" filter
-- (Auras.KINDS.tilebuff "heals") and by the heal indicators (Indicators.lua),
-- where a family's color is its square's color. The client's aura container
-- matches them by spell id, every rank included, so no aura is ever read.
--
-- Ids are copied from DaylightUI_ActionBars/CdmSpells.lua (talentsforever.com
-- data, CC BY 4.0, see CdmSpells-LICENSE.txt there). Copied rather than read
-- because that module can be disabled. One family per spell, rank 1 first.
--
-- Family fields:
--   filter       its own aura filter. Indicators only, never the buff row.
--                Weakened Soul is a debuff on a friend, and the client refuses
--                spell id filters for those (includeSpellIDs then shows nothing,
--                see AuraContainerUtil.CanApplyIdentityCandidateFilters). So it
--                is matched as a debuff of yours lasting at most maxDuration s.
--                Recently Bandaged is also yours, at 60 s.
--   others       a second group on the same square for the same debuff from
--                anyone else: a short player debuff your class can apply
--                (canApplyAura). Not confirmed in game for Weakened Soul; if
--                the flag isn't set the group stays empty. !PLAYER keeps out the
--                first group's aura, and the 15 s cap plus !CROWD_CONTROL keep
--                an enemy priest's Shadow Word: Pain and fear out.
--   long         a buff kept up for minutes (Oath of Light, 5 min). Its square
--                counts down the last LONG_WARN seconds so you know to recast.
--   buff         a group-wide class buff (Fortitude, Mark of the Wild, the
--                Blessings; one family holds both single and group versions).
--                Shown from any caster (HELPFUL) and counts down its last minute.

local _, ns = ...

local HealSpells = {}
ns.HealSpells = HealSpells

HealSpells.CLASSES = {
    PRIEST = {
        { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315, color = { 0.45, 0.85, 0.45 } },   -- Renew
        { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, color = { 1, 0.84, 0.35 } }, -- Power Word: Shield
        { 401859, 1240826, 1240827, color = { 0.95, 0.5, 0.75 } },               -- Prayer of Mending
        { 6346, color = { 0.95, 0.6, 0.3 } },                                -- Fear Ward
        { 10060, color = { 0.6, 0.75, 1 } },                                -- Power Infusion
        { 552, color = { 0.78, 0.62, 0.38 } },                             -- Abolish Disease
        { 6788, color = { 0.85, 0.32, 0.3 }, filter = "HARMFUL|PLAYER", maxDuration = 30,  -- Weakened Soul
          others = { filter = "HARMFUL|!PLAYER|!CROWD_CONTROL",
                     candidates = { canApplyAura = true, isFromPlayerOrPlayerPet = true, maxDuration = 15 } } },
        { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564, color = { 0.92, 0.9, 0.8 }, buff = true }, -- Power Word: Fortitude
        { 14752, 14818, 14819, 27841, color = { 0.55, 0.8, 1 }, buff = true },  -- Divine Spirit
        { 976, 10957, 10958, 27683, color = { 0.62, 0.45, 0.85 }, buff = true }, -- Shadow Protection
    },
    DRUID = {
        { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, color = { 0.75, 0.45, 0.95 } }, -- Rejuvenation
        { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858, color = { 0.45, 0.85, 0.45 } }, -- Regrowth
        { 408120, 1238214, 1238215, color = { 0.35, 0.85, 0.8 } },                -- Wild Growth
        { 29166, color = { 0.4, 0.6, 1 } },                                   -- Innervate
        { 2893, color = { 0.5, 0.8, 0.35 } },                                -- Abolish Poison
        { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850, color = { 0.95, 0.55, 0.85 }, buff = true }, -- Mark of the Wild
        { 467, 782, 1075, 8914, 9756, 9910, color = { 0.65, 0.75, 0.35 }, buff = true }, -- Thorns
    },
    SHAMAN = {
        { 408521, 1239242, 1239243, color = { 0.35, 0.65, 1 } },                 -- Riptide
    },
    PALADIN = {
        { 1022, 5599, 10278, color = { 0.95, 0.85, 0.45 } },                -- Blessing of Protection
        { 6940, 20729, color = { 0.95, 0.45, 0.35 } },                       -- Blessing of Sacrifice
        { 1310911, 1311590, 1311595, color = { 1, 0.95, 0.6 } },                -- Light's Vigil
        { 1328548, color = { 1, 0.75, 0.3 }, long = true },                      -- Oath of Light (Holy talent, one ally, 5 min)
        { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916, color = { 1, 0.6, 0.35 }, buff = true }, -- Blessing of Might
        { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918, color = { 0.45, 0.75, 1 }, buff = true }, -- Blessing of Wisdom
        { 20217, 25898, color = { 0.85, 0.6, 1 }, buff = true },              -- Blessing of Kings
        { 1038, 25895, color = { 0.6, 0.85, 0.95 }, buff = true },            -- Blessing of Salvation
        { 19977, 19978, 19979, 25890, color = { 1, 0.9, 0.55 }, buff = true }, -- Blessing of Light
    },
    MAGE = {
        { 1459, 1460, 1461, 10156, 10157, 23028, color = { 0.45, 0.7, 1 }, buff = true }, -- Arcane Intellect
        { 1008, 8455, 10169, 10170, color = { 0.7, 0.55, 1 }, buff = true },   -- Amplify Magic
        { 604, 8450, 8451, 10173, 10174, color = { 0.5, 0.55, 0.8 }, buff = true }, -- Dampen Magic
    },
}

-- The heal indicators' default picks per class, by rank 1 id, square 1, 2, 3...
-- Light's Vigil isn't picked because its behavior on Forever is unverified.
HealSpells.PRESET = {
    PRIEST = { 139, 17, 401859, 6788 },
    DRUID = { 774, 8936, 408120 },
    SHAMAN = { 408521 },
    PALADIN = { 1022, 6940, 1328548 },
}

-- Seconds left from which a `long` family's square shows its time.
HealSpells.LONG_WARN = 60

local function classToken()
    local _, token = UnitClass("player")
    if type(token) ~= "string" or (issecretvalue and issecretvalue(token)) then return nil end
    return token
end

-- { [spellID] = true } for every rank of every spell of your class, or nil
-- when your class has none. "Heals and shields" then shows nothing.
function HealSpells.Ids()
    local list = HealSpells.CLASSES[classToken() or ""]
    if not list then return nil end
    local ids, any = {}, false
    for _, family in ipairs(list) do
        if not (family.filter or family.buff) then
            for _, id in ipairs(family) do ids[id] = true; any = true end
        end
    end
    return any and ids or nil
end

function HealSpells.Has()
    return HealSpells.Ids() ~= nil
end

-- The family (rank list, color) holding a spell id. Your class's first, then
-- any class's. Nil for a spell on no list.
function HealSpells.Family(id)
    if type(id) ~= "number" then return nil end
    local function find(list)
        for _, f in ipairs(list or {}) do for _, s in ipairs(f) do if s == id then return f end end end
    end
    local f = find(HealSpells.CLASSES[classToken() or ""])
    if f then return f end
    for _, list in pairs(HealSpells.CLASSES) do
        f = find(list)
        if f then return f end
    end
end

-- { [id] = true } for spell id and every rank of it.
function HealSpells.Ranks(id)
    local out, f = {}, HealSpells.Family(id)
    if f then for _, s in ipairs(f) do out[s] = true end
    elseif type(id) == "number" then out[id] = true end
    return out
end

-- The aura filter that finds a spell id: its family's own, else your own buffs.
function HealSpells.FilterOf(id)
    local f = HealSpells.Family(id)
    if f and f.buff then return "HELPFUL" end
    return f and f.filter or "HELPFUL|PLAYER"
end

-- Candidate filters that pick the spell out of what FilterOf finds: every rank,
-- or the family's duration cap where the client refuses spell ids.
function HealSpells.CandidatesOf(id)
    local f = HealSpells.Family(id)
    if f and f.maxDuration then return { maxDuration = f.maxDuration } end
    return { includeSpellIDs = HealSpells.Ranks(id) }
end

-- Whether spell id's square counts down its last LONG_WARN seconds.
function HealSpells.IsLong(id)
    local f = HealSpells.Family(id)
    return f and (f.long == true or f.buff == true) or false
end

-- The family's second group, { filter, candidates }, or nil.
function HealSpells.OthersOf(id)
    local f = HealSpells.Family(id)
    return f and f.others or nil
end

-- Indicator square i's spell (rank 1 id). "auto" means your class's pick for i,
-- otherwise the stored id. Nil when there's none.
function HealSpells.SpellFor(i, spell)
    if type(spell) == "number" then return spell end
    local n = tonumber(spell)
    if n then return n end
    local pick = HealSpells.PRESET[classToken() or ""]
    return pick and pick[i] or nil
end

-- A family's color as r, g, b. A warm tan for a spell on no list.
function HealSpells.ColorOf(id)
    local f = HealSpells.Family(id)
    local c = f and f.color or DaylightUI.Style.INK.LABEL
    return c[1], c[2], c[3]
end

-- Your class's families as { id = rank 1, name } in list order, for the
-- indicators' spell menu.
function HealSpells.Mine()
    local out = {}
    for _, f in ipairs(HealSpells.CLASSES[classToken() or ""] or {}) do
        local ok, name = pcall(C_Spell.GetSpellName, f[1])
        if not ok or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then name = tostring(f[1]) end
        out[#out + 1] = { id = f[1], name = name }
    end
    return out
end
