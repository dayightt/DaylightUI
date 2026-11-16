-- Out of range: enemy plates you can't reach with your class's attacks fade
-- (rangeFade, to rangeAlpha). The fade itself is Plate.Dim's, so it eases and
-- stacks with "Fade other plates"; this file only keeps p.outOfRange current.

local _, ns = ...
local DUI = DaylightUI

local Range = {}
ns.Range = Range

local isSecret = DUI.IsSecret

-- Each class's attacks, by their first rank's id. The check asks by spell
-- name, so whichever rank you know answers. A plate is in range when any of
-- them reaches it, so a hunter's melee strikes cover the gap up close where
-- Auto Shot can't be fired. alt = only asked when nothing else is known.
-- Never an attack that goes off on your next swing (Heroic Strike, Raptor
-- Strike, Maul, Cleave): the game says those are in range at any distance.
Range.SPELLS = {
    WARRIOR = { { 772 }, { 1715 }, { 7386 } },        -- Rend, Hamstring, Sunder Armor
    ROGUE   = { { 1752 } },                           -- Sinister Strike
    PALADIN = { { 679 }, { 20271, alt = true } },     -- Holy Strike, else Judgement
    HUNTER  = { { 75 }, { 2974 }, { 1495 } },         -- Auto Shot, Wing Clip, Mongoose Bite
    MAGE    = { { 133 }, { 116 } },                   -- Fireball, Frostbolt
    WARLOCK = { { 686 }, { 172 } },                   -- Shadow Bolt, Corruption
    PRIEST  = { { 585 }, { 589 } },                   -- Smite, Shadow Word: Pain
    SHAMAN  = { { 403 }, { 8042 } },                  -- Lightning Bolt, Earth Shock
    DRUID   = { { 5176 }, { 8921 } },                 -- Wrath, Moonfire
}
-- A druid in cat or bear form fights in melee whatever spells they know
-- (GetShapeshiftFormID: 1 cat, 5 bear, 8 dire bear).
Range.FORMS = {
    [1] = { { 1082 } },  -- Claw
    [5] = { { 6795 }, { 5211 } },  -- Growl, Bash
    [8] = { { 6795 }, { 5211 } },
}
Range.EVERY = 0.2 -- seconds between checks while it's on

local spells       -- what to ask, by name (or id when the name can't be read)
local ticker

local function nameOf(id)
    local get = type(C_Spell) == "table" and C_Spell.GetSpellName
    if type(get) ~= "function" then return id end
    local ok, name = pcall(get, id)
    if ok and type(name) == "string" and not isSecret(name) and name ~= "" then return name end
    return id
end

local function names(groups)
    local list = {}
    for _, g in ipairs(groups) do list[#list + 1] = { nameOf(g[1]), alt = g.alt } end
    return list
end

local function form()
    if type(GetShapeshiftFormID) ~= "function" then return nil end
    local ok, id = pcall(GetShapeshiftFormID)
    if ok and not isSecret(id) then return id end
end

-- The list for your class right now. Names are read again after the
-- spellbook changes (Range.SpellsChanged).
local function current()
    local id = form()
    if id and Range.FORMS[id] then
        spells = spells or {}
        spells[id] = spells[id] or names(Range.FORMS[id])
        return spells[id]
    end
    if not spells then spells = {} end
    if spells.class == nil then
        local _, class = UnitClass("player")
        local groups = type(class) == "string" and not isSecret(class) and Range.SPELLS[class]
        spells.class = groups and names(groups) or false
    end
    return spells.class or nil
end

function Range.SpellsChanged() spells = nil end

local function ask(spell, unit)
    local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
    if not ok or isSecret(r) then return nil end
    return r
end

-- true: none of your attacks reach the unit. false: one does. nil: none of
-- them could tell (not learned yet, or not an enemy), so it doesn't fade.
function Range.Out(unit)
    if type(C_Spell) ~= "table" or type(C_Spell.IsSpellInRange) ~= "function" then return nil end
    local list = current()
    if not list then return nil end
    local said = false
    for _, s in ipairs(list) do
        if not s.alt then
            local r = ask(s[1], unit)
            if r == true then return false end
            if r == false then said = true end
        end
    end
    if said then return true end
    for _, s in ipairs(list) do
        if s.alt then
            local r = ask(s[1], unit)
            if r == true then return false end
            if r == false then said = true end
        end
    end
    return said or nil
end

-- Reads one plate's answer. Enemies only: friendly plates never fade.
function Range.Read(p)
    local out = nil
    if ns.cfg.rangeFade and not p.friendly and not p.isSample and type(p.unit) == "string" then
        out = Range.Out(p.unit)
    end
    p.outOfRange = out == true or nil
end

local function check(p)
    local was = p.outOfRange
    Range.Read(p)
    if p.outOfRange ~= was then ns.Plate.Dim(p) end
end

function Range.Tick() ns.Manager.Each(check) end

-- Starts or stops the checks with the setting (Manager.Start and Refresh).
function Range.Apply()
    local on = ns.cfg.rangeFade == true
    if on and not ticker then
        ticker = C_Timer.NewTicker(Range.EVERY, function() DUI.SafeCall(Range.Tick) end)
    elseif not on and ticker then
        ticker:Cancel()
        ticker = nil
        ns.Manager.Each(check)
    end
end
