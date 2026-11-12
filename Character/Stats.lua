-- Reads stats into plain rows per group. No frames.
--
-- In combat almost every stat is secret. Secrets can't be compared or added,
-- but the engine can still format them, so a row is a format string plus its
-- values. Rows that need a sum (attack power is base + buffs) keep their last
-- plain value while secret and are drawn dimmed (`stale`). Secret and stale
-- rows get no buff coloring and no explanation.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local Stats = {}
ns.Stats = Stats

Stats.GROUPS = { "attributes", "attack", "ranged", "spell", "defense", "resistances" }
Stats.LABEL = { attributes = L["Attributes"], attack = L["Attack"], ranged = L["Ranged"], spell = L["Spell"],
    defense = L["Defense"], resistances = L["Resistances"] }

-- The group that opens beside Attributes, by role if known, else by class.
Stats.ROLE_OPEN = { TANK = "defense", HEALER = "spell" }
Stats.CLASS_OPEN = { WARRIOR = "attack", ROGUE = "attack", PALADIN = "attack", HUNTER = "ranged", MAGE = "spell",
    WARLOCK = "spell", PRIEST = "spell", DRUID = "spell", SHAMAN = "spell" }
Stats.NO_MANA = { WARRIOR = true, ROGUE = true }

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- Calls a game function that may be missing or error. Returns nothing on failure.
local function call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return unpack(res, 2, table.maxn(res))
end

-- Only called with plain numbers (Stats.Row checks first).
local function buffOf(plus, minus)
    if type(minus) == "number" and minus < 0 then return "down" end
    if type(plus) == "number" and plus > 0 then return "up" end
end
-- Armor and resistances return no bonus values on this client, only base and
-- current. Higher than base means buffed, lower means debuffed.
local function overBase(now, base)
    if type(now) ~= "number" or type(base) ~= "number" then return nil end
    if now < base then return "down" end
    if now > base then return "up" end
end
local function sum(...)
    local t = 0
    for i = 1, select("#", ...) do t = t + (select(i, ...) or 0) end
    return t
end
local function biggest(...)
    local m = 0
    for i = 1, select("#", ...) do m = math.max(m, select(i, ...) or 0) end
    return m
end
-- Like the game's sheet, show the best spell school (2 holy .. 7 arcane).
local function overSchools(name)
    return function()
        local out = {}
        for school = 2, 7 do
            local v = call(name, school)   -- secret in combat, so it's passed on untouched
            out[#out + 1] = type(v) == "nil" and 0 or v
        end
        return unpack(out, 1, 6)
    end
end
local function className() local _, c = UnitClass("player"); return c end
local function dual() return call("IsDualWielding") == true end
-- The game's own word for a unit's power (Mana, Rage, Energy, Focus).
local function powerName(unit)
    local _, token = call("UnitPowerType", unit)
    return type(token) == "string" and type(_G[token]) == "string" and _G[token] or L["Power"]
end
-- No ranged damage rows without a ranged weapon, as on the game's sheet.
local function noRanged() return call("IsRangedWeapon") == false end

-- Forever has a single hit stat for melee, ranged and spells. The API still has
-- four calls, so show the biggest like PaperDollFrame_SetHitChance does.
local function hitParts()
    return call("GetCombatRatingBonus", CR_HIT_MELEE or 6), call("GetHitModifier"), call("GetOffhandHitModifier"),
        call("GetCombatRatingBonus", CR_HIT_RANGED or 7), call("GetRangedHitModifier"),
        call("GetCombatRatingBonus", CR_HIT_SPELL or 8), call("GetSpellHitModifier")
end
local function bestHit(melee, main, off, ranged, rangedMod, spell, spellMod)
    melee = melee or 0
    return math.max(melee + (main or 0), melee + (off or 0), (ranged or 0) + (rangedMod or 0), (spell or 0) + (spellMod or 0))
end
local function hitRow()
    return { id = "hit", label = L["Chance to hit"], fmt = "%.2f%%", read = hitParts, compute = bestHit, game = "PaperDollFrame_SetHitChance" }
end
-- A pet's own hit is added to its owner's melee and spell hit. Show the bigger.
local function petHit()
    local melee, main, _, _, _, spell, spellMod = hitParts()
    return melee, main, spell, spellMod, call("GetPetHitChanceModifier"), call("GetPetSpellHitChanceModifier")
end
local function bestPetHit(melee, main, spell, spellMod, petMelee, petSpell)
    return math.max((melee or 0) + (main or 0) + (petMelee or 0), (spell or 0) + (spellMod or 0) + (petSpell or 0))
end

-- Row fields:
--   id, label, fmt   format string for the values
--   read()           returns the values
--   show             how many values fmt uses (default all)
--   compute(...)     one number when the values need a sum
--   buff(...)        "up" or "down"
--   skip()           true leaves the row out
--   game, gameArg    the game's sheet function for this stat, for its tooltip
Stats.ROWS = {
    attributes = {},
    attack = {
        { id = "dmg", label = L["Damage"], fmt = "%.0f - %.0f", read = function() return call("UnitDamage", "player") end, show = 2, game = "PaperDollFrame_SetMainhandDamage" },
        { id = "ohdmg", label = L["Off-hand damage"], fmt = "%.0f - %.0f", game = "PaperDollFrame_SetOffhandDamage", skip = function() return not dual() end,
          read = function() local _, _, lo, hi = call("UnitDamage", "player"); return lo, hi end },
        { id = "speed", label = L["Attack speed"], fmt = L["%.2f s"], read = function() return call("UnitAttackSpeed", "player") end, show = 1, game = "PaperDollFrame_SetAttackSpeed",
          skip = dual },
        { id = "speed", label = L["Attack speed"], fmt = L["%.2f / %.2f s"], read = function() return call("UnitAttackSpeed", "player") end, show = 2, game = "PaperDollFrame_SetAttackSpeed",
          skip = function() return not dual() end },
        { id = "ap", label = L["Attack power"], fmt = "%.0f", game = "PaperDollFrame_SetAttackPower", read = function() return call("UnitAttackPower", "player") end,
          compute = sum, buff = function(_, plus, minus) return buffOf(plus, minus) end },
        hitRow(),
        { id = "crit", label = L["Critical strike"], fmt = "%.2f%%", read = function() return call("GetCritChance") end, game = "PaperDollFrame_SetCritChance" },
        { id = "haste", label = L["Haste"], fmt = "%.2f%%", read = function() return call("GetMeleeHaste") end, game = "PaperDollFrame_SetHaste", hideAt = 0 },
        -- A percent on Forever. Dual wielding shows both hands, as the game does.
        { id = "expertise", label = L["Expertise"], fmt = "%.2f%%", read = function() return call("GetExpertise") end, show = 1, game = "PaperDollFrame_SetExpertise", gameArg = true,
          hideAt = 0, skip = dual },
        { id = "expertise", label = L["Expertise"], fmt = "%.2f%% / %.2f%%", read = function() return call("GetExpertise") end, show = 2, game = "PaperDollFrame_SetExpertise", gameArg = true,
          skip = function() return not dual() end },
        { id = "armorpen", label = L["Armor penetration"], fmt = "%.0f", read = function() return call("GetArmorPenetration") end, game = "PaperDollFrame_SetArmorPenetration", hideAt = 0 },
    },
    ranged = {
        { id = "rdmg", label = L["Damage"], fmt = "%.0f - %.0f", game = "PaperDollFrame_SetRangedDamage", skip = noRanged,
          read = function() local _, lo, hi = call("UnitRangedDamage", "player"); return lo, hi end },
        { id = "rspeed", label = L["Attack speed"], fmt = L["%.2f s"], read = function() return call("UnitRangedDamage", "player") end, show = 1, game = "PaperDollFrame_SetRangedDamage",
          skip = noRanged },
        { id = "rap", label = L["Attack power"], fmt = "%.0f", game = "PaperDollFrame_SetRangedAttackPower", read = function() return call("UnitRangedAttackPower", "player") end,
          compute = sum, buff = function(_, plus, minus) return buffOf(plus, minus) end },
        hitRow(),
        { id = "rcrit", label = L["Critical strike"], fmt = "%.2f%%", read = function() return call("GetRangedCritChance") end, game = "PaperDollFrame_SetCritChance" },
        -- Ranged haste is the weapon's plus the quiver's.
        { id = "rhaste", label = L["Haste"], fmt = "%.2f%%", read = function() return call("GetRangedHaste") end, compute = sum, game = "PaperDollFrame_SetHaste", hideAt = 0 },
        { id = "rarmorpen", label = L["Armor penetration"], fmt = "%.0f", read = function() return call("GetArmorPenetration") end, game = "PaperDollFrame_SetArmorPenetration", hideAt = 0 },
    },
    spell = {
        { id = "sp", label = L["Spell power"], fmt = "%.0f", read = overSchools("GetSpellBonusDamage"), compute = biggest, game = "PaperDollFrame_SetSpellPower" },
        { id = "heal", label = L["Healing"], fmt = "%.0f", read = function() return call("GetSpellBonusHealing") end, game = "PaperDollFrame_SetSpellHealing" },
        { id = "scrit", label = L["Critical strike"], fmt = "%.2f%%", read = overSchools("GetSpellCritChance"), compute = biggest, game = "PaperDollFrame_SetCritChance" },
        hitRow(),
        { id = "shaste", label = L["Haste"], fmt = "%.2f%%", read = function() return call("UnitSpellHaste", "player") end, game = "PaperDollFrame_SetHaste", hideAt = 0 },
        { id = "spen", label = L["Spell penetration"], fmt = "%.0f", read = function() return call("GetSpellPenetration") end, game = "PaperDollFrame_SetSpellPenetration", hideAt = 0 },
        -- The game shows the regen while casting, the one that counts in a fight.
        { id = "regen", label = L["Mana regen"], fmt = L["%.0f every 5 s"], game = "PaperDollFrame_SetManaRegen", read = function() return call("GetManaRegen") end,
          compute = function(_, casting) return math.floor((casting or 0) * 5) end, skip = function() return Stats.NO_MANA[className() or ""] == true end },
    },
    defense = {
        { id = "armor", label = L["Armor"], fmt = "%.0f", show = 1, game = "PaperDollFrame_SetArmor",
          read = function() local base, eff = call("UnitArmor", "player"); return eff, base end,   -- base, effective, real, bonus
          buff = overBase },
        { id = "defense", label = L["Defense"], fmt = "%.0f", game = "PaperDollFrame_SetDefense", read = function() return call("UnitDefenseSkill", "player") end, compute = sum },
        { id = "dodge", label = L["Dodge"], fmt = "%.2f%%", game = "PaperDollFrame_SetDodge", read = function() return call("GetDodgeChance") end, hideAt = 0 },
        { id = "parry", label = L["Parry"], fmt = "%.2f%%", game = "PaperDollFrame_SetParry", read = function() return call("GetParryChance") end, hideAt = 0 },
        { id = "block", label = L["Block"], fmt = "%.2f%%", game = "PaperDollFrame_SetBlock", read = function() return call("GetBlockChance") end, hideAt = 0,
          -- Same shield check as the game's sheet. IsEquippedItemType("Shields") returned false with a shield on.
          skip = function() return not (C_PaperDollInfo and C_PaperDollInfo.OffhandHasShield and C_PaperDollInfo.OffhandHasShield()) end },
    },
    resistances = {},
}

local ATTRIBUTES = { { "str", L["Strength"] }, { "agi", L["Agility"] }, { "sta", L["Stamina"] }, { "int", L["Intellect"] }, { "spi", L["Spirit"] } }
for i, a in ipairs(ATTRIBUTES) do
    Stats.ROWS.attributes[i] = { id = a[1], label = a[2], fmt = "%.0f", show = 1, game = "PaperDollFrame_SetStat", gameArg = i,
        read = function() local _, total, plus, minus = call("UnitStat", "player", i); return total, plus, minus end,
        buff = function(_, plus, minus) return buffOf(plus, minus) end }
end
local function pct(base, rate) return (base or 0) / (rate or 1) * 100 end

-- Movement speed goes last, as on the game's sheet (MovementSpeed_OnUpdate):
-- run, swim or flight speed depending on what you're doing, as a percent of
-- BASE_MOVEMENT_SPEED. Secret in combat, so the last plain value is kept.
local function moveSpeed(unit)
    return { id = unit == "pet" and "pet_speed" or "movespeed", label = L["Movement speed"], fmt = "%.0f%%", unit = unit,
        game = "PaperDollFrame_SetMovementSpeed",
        read = function()
            local _, run, fly, swim = call("GetUnitSpeed", unit)
            return run, fly, swim
        end,
        compute = function(run, fly, swim)
            -- Pets always use their run speed, as on the game's sheet.
            local v = run
            if unit ~= "pet" and call("IsSwimming", unit) then v = swim
            elseif unit ~= "pet" and call("IsFlying", unit) then v = fly end
            return pct(v, BASE_MOVEMENT_SPEED or 7)
        end }
end
-- Health and power sit with movement speed, as in the game's General group.
local function maxPower(unit)
    return { id = unit == "pet" and "pet_power" or "power", label = function() return powerName(unit) end, fmt = "%.0f", unit = unit,
        game = "PaperDollFrame_SetPower", read = function() return call("UnitPowerMax", unit) end }
end
local A = Stats.ROWS.attributes
A[#A + 1] = { id = "health", label = L["Health"], fmt = "%.0f", game = "PaperDollFrame_SetHealth", read = function() return call("UnitHealthMax", "player") end }
A[#A + 1] = maxPower("player")
A[#A + 1] = moveSpeed("player")

local RESIST = { { 2, "fire", L["Fire"] }, { 3, "nature", L["Nature"] }, { 4, "frost", L["Frost"] }, { 5, "shadow", L["Shadow"] }, { 6, "arcane", L["Arcane"] } }
for i, r in ipairs(RESIST) do
    Stats.ROWS.resistances[i] = { id = "res_" .. r[2], label = r[3], fmt = "%.0f", show = 1, game = "PaperDollFrame_SetResistance", gameArg = r[1],
        read = function()   -- base, real, effective, bonus
            local base, _, eff = call("UnitResistance", "player", r[1]); return eff, base
        end,
        buff = overBase }
end

-- Pet page rows, matching the game's pet stat group, each read for "pet".
Stats.PET_GROUPS = { "pet", "petResist" }
Stats.LABEL.pet, Stats.LABEL.petResist = L["General"], L["Resistances"]
Stats.PET_OPEN = { pet = true }   -- open until folded; resistances start folded
Stats.COLOR = { pet = "attack", petResist = "resistances" }   -- header color each pet group borrows
local function warlock() return className() == "WARLOCK" end
-- A demon gets a share of your Intellect back as mana every 5 s, an imp more
-- (the game's PaperDollFrame_SetWarlockPetManaRegen).
local IMP_FAMILY, IMP_REGEN, DEMON_REGEN = 23, 0.3, 0.1
local function petRegen(maxMana, intellect)
    if (maxMana or 0) <= 0 then return 0 end
    local _, family = call("UnitCreatureFamily", "pet")
    return math.floor((intellect or 0) * (family == IMP_FAMILY and IMP_REGEN or DEMON_REGEN))
end
local petPower = maxPower("pet")
petPower.skip = function() return not warlock() end   -- only a demon's mana, as on the game's sheet
Stats.ROWS.pet = {
    { id = "pet_health", label = L["Health"], fmt = "%.0f", unit = "pet", game = "PaperDollFrame_SetHealth",
      read = function() return call("UnitHealthMax", "pet") end },
    petPower,
    { id = "pet_regen", label = L["Mana regen"], fmt = L["%.0f every 5 s"], unit = "pet", game = "PaperDollFrame_SetManaRegen",
      read = function() local _, int = call("UnitStat", "player", 4); return call("UnitPowerMax", "pet", 0), int end,
      compute = petRegen, hideAt = 0, skip = function() return not warlock() end },
    { id = "pet_armor", label = L["Armor"], fmt = "%.0f", show = 1, unit = "pet", game = "PaperDollFrame_SetArmor",
      read = function() local base, eff = call("UnitArmor", "pet"); return eff, base end, buff = overBase },
    { id = "pet_dmg", label = L["Damage"], fmt = "%.0f - %.0f", show = 2, unit = "pet", game = "PaperDollFrame_SetDamage",
      read = function() return call("UnitDamage", "pet") end },
    { id = "pet_atkspeed", label = L["Attack speed"], fmt = L["%.2f s"], show = 1, unit = "pet", game = "PaperDollFrame_SetAttackSpeed",
      read = function() return call("UnitAttackSpeed", "pet") end },
    { id = "pet_ap", label = L["Attack power"], fmt = "%.0f", unit = "pet", game = "PaperDollFrame_SetAttackPower",
      read = function() return call("UnitAttackPower", "pet") end, compute = sum, buff = function(_, plus, minus) return buffOf(plus, minus) end },
    { id = "pet_sp", label = L["Spell power"], fmt = "%.0f", unit = "pet", game = "PaperDollFrame_SetSpellPower",
      read = function() return call("GetPetSpellBonusDamage") end, hideAt = 0 },
    { id = "pet_hit", label = L["Chance to hit"], fmt = "%.2f%%", unit = "pet", game = "PaperDollFrame_SetHitChance",
      read = petHit, compute = bestPetHit, hideAt = 0 },
    { id = "pet_crit", label = L["Critical strike"], fmt = "%.2f%%", unit = "pet", game = "PaperDollFrame_SetCritChance",
      read = function() return call("GetPetCritChance") end, compute = biggest, hideAt = 0,
      skip = function() return type(GetPetCritChance) ~= "function" end },
    { id = "pet_haste", label = L["Haste"], fmt = "%.2f%%", unit = "pet", game = "PaperDollFrame_SetHaste",
      read = function() return call("GetPetMeleeHaste"), call("UnitSpellHaste", "pet") end, compute = biggest, hideAt = 0 },
    -- A pet has its owner's expertise.
    { id = "pet_expertise", label = L["Expertise"], fmt = "%.2f%%", unit = "pet", game = "PaperDollFrame_SetExpertise",
      read = function() return call("GetExpertise") end, show = 1, hideAt = 0 },
    { id = "pet_dodge", label = L["Dodge"], fmt = "%.2f%%", unit = "pet", game = "PaperDollFrame_SetDodge",
      read = function() return call("GetPetDodgeChance") end, hideAt = 0,
      skip = function() return type(GetPetDodgeChance) ~= "function" end },
    moveSpeed("pet"),
}
Stats.ROWS.petResist = {}
for i, r in ipairs(RESIST) do
    Stats.ROWS.petResist[i] = { id = "pet_res_" .. r[2], label = r[3], fmt = "%.0f", show = 1, unit = "pet",
        game = "PaperDollFrame_SetResistance", gameArg = r[1],
        read = function() local base, _, eff = call("UnitResistance", "pet", r[1]); return eff, base end,
        buff = overBase }
end

local last = {}   -- row id -> its last plain sum

function Stats.Row(def)
    local raw = { def.read() }
    local n = table.maxn(raw)
    local secret = false
    for i = 1, n do if isSecret(raw[i]) then secret = true end end
    local label = def.label
    if type(label) == "function" then label = label() end
    local row = { id = def.id, label = label, fmt = def.fmt, secret = secret, game = def.game, gameArg = def.gameArg, unit = def.unit }
    if def.compute then
        if secret then
            row.stale = true
            if last[def.id] ~= nil then row.values = { last[def.id] } end
        else
            local v = def.compute(unpack(raw, 1, n))
            last[def.id] = v
            row.values = { v }
        end
    elseif type(raw[1]) ~= "nil" then
        row.values = {}
        for i = 1, (def.show or n) do row.values[i] = raw[i] end
    end
    if not secret and def.buff then row.buff = def.buff(unpack(raw, 1, n)) end
    return row
end

-- A row with hideAt is hidden while its value equals it (a pet with no spell
-- power), as on the game's sheet. Secrets can't be compared, so the last plain
-- answer holds until combat ends.
local gone = {}   -- row id -> left out at its last plain read
local function hidden(def, row)
    if def.hideAt == nil then return false end
    if not row.secret and not row.stale and row.values then gone[def.id] = row.values[1] == def.hideAt end
    return gone[def.id] == true
end

function Stats.Read(group)
    local out = {}
    for _, def in ipairs(Stats.ROWS[group] or {}) do
        if not (def.skip and def.skip()) then
            local row = Stats.Row(def)
            if not hidden(def, row) then out[#out + 1] = row end
        end
    end
    return out
end

-- The value as a string. Plain rows only.
function Stats.Text(row)
    if not row.values then return "--" end
    return string.format(row.fmt, unpack(row.values, 1, table.maxn(row.values)))
end

-- Writes the value with SetFormattedText, which accepts secrets, so nothing
-- here ever compares or adds them.
function Stats.Paint(fs, row)
    if not row.values then
        fs:SetText("--")
        return
    end
    fs:SetFormattedText(row.fmt, unpack(row.values, 1, table.maxn(row.values)))
end

-- Your role if the client knows it (same calls as Installer.lua), else nil.
function Stats.Role()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationRole) ~= "function" then return nil end
    local ok, spec = pcall(GetSpecialization)
    if not ok or isSecret(spec) or type(spec) ~= "number" then return nil end
    local ok2, role = pcall(GetSpecializationRole, spec)
    if not ok2 or isSecret(role) or type(role) ~= "string" then return nil end
    return role
end

function Stats.DefaultOpen(class, role)
    local second = Stats.ROLE_OPEN[role or ""] or Stats.CLASS_OPEN[class or ""] or "attack"
    return { attributes = true, [second] = true }
end

-- Open and folded groups are saved per character, so profile swaps keep them
-- and share strings never carry them. An older profile's entry for this
-- character is moved over once.
function Stats.Folds(cfg)
    local c = DUI.DB.Character()
    if type(c.statFolds) ~= "table" then
        c.statFolds = {}
        local old = type(cfg) == "table" and type(cfg.folded) == "table" and cfg.folded[Stats.Who()]
        if type(old) == "table" then
            for g, v in pairs(old) do c.statFolds[g] = v end
            cfg.folded[Stats.Who()] = nil
        end
    end
    return c.statFolds
end

-- Open or folded: the saved choice for this character, else the setting.
function Stats.IsOpen(cfg, folds, group, class, role)
    if type(folds) == "table" and type(folds[group]) == "boolean" then return folds[group] end
    if cfg.statsOpen == "all" or Stats.PET_OPEN[group] then return true end
    return Stats.DefaultOpen(class, role)[group] == true
end

function Stats.Who()
    return DUI.DB.CharKey() or "?-?"
end
