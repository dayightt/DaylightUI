-- Scrolling combat text: message kinds, streams, presets and setting defaults.
-- Lines.lua draws, Feed.lua listens to the game, Page.lua is the options page.
--
-- The game's own frame stays hidden and everything is drawn here. Every value
-- from C_CombatText.GetCurrentEventInfo is secret, even out of combat, so it can
-- be shown but never summed, compared or measured. That's why nothing merges
-- hits, filters small ones or scales by amount.

local _, DUI = ...
local Style = DUI.Style
local INK = Style.INK

local CT = {}
DUI.CombatText = CT

CT.GAME_SWITCH = "enableFloatingCombatText"   -- the game's CVar for floating combat text

-- The three streams. side = which way it leans away from the character.
CT.STREAM_ORDER = { "hits", "heals", "notes" }
CT.STREAMS = {
    hits = { label = "Left stream", word = "left", place = { "CENTER", nil, "CENTER", -190, 30 }, side = -1 },
    heals = { label = "Right stream", word = "right", place = { "CENTER", nil, "CENTER", 190, 30 }, side = 1 },
    notes = { label = "Top stream", word = "top", place = { "CENTER", nil, "CENTER", 0, 210 }, side = 0 },
}

CT.MOTIONS = { slant = "Slant", rise = "Rise", fall = "Fall", arc = "Arc", fountain = "Fountain", stack = "Stack" }
CT.MOTION_ORDER = { "slant", "rise", "fall", "arc", "fountain", "stack" }

CT.CRITS = { flare = "Flare", slam = "Slam", pop = "Pop", plain = "Plain" }
CT.CRIT_ORDER = { "flare", "slam", "pop", "plain" }
CT.CRIT_POP = { flare = 1.45, slam = 1.9, pop = 1.3 }   -- crit scale on landing, before it settles

CT.OUTLINES = { [""] = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }
CT.OUTLINE_ORDER = { "", "OUTLINE", "THICKOUTLINE" }

CT.ALIGNS = { RIGHT = "Right", CENTER = "Center", LEFT = "Left" }
CT.ALIGN_ORDER = { "LEFT", "CENTER", "RIGHT" }

CT.NUMBERS = { full = "Full (1,234)", short = "Short (1.2K)" }
CT.NUMBER_ORDER = { "full", "short" }

-- Message kinds, each with its own switch and color.
CT.KIND_ORDER = { "hit", "spell", "avoid", "reduce", "heal", "hot", "shield", "power", "powerTick",
    "buff", "debuff", "proc", "low", "combat", "rep", "honor", "other" }
CT.KINDS = {
    hit = { label = "Melee and ranged hits", desc = "Hits you take from weapons.", stream = "hits", ink = "DAMAGE", on = true },
    spell = { label = "Spell hits", desc = "Hits you take from spells.", stream = "hits", ink = "DAMAGE", on = true },
    avoid = { label = "Dodge, parry and miss", desc = "Attacks that didn't land on you.", stream = "hits", ink = "TEXT", on = true },
    reduce = { label = "Blocks, absorbs and resists", desc = "How much a block, absorb or resist saved you.", stream = "hits", ink = "LABEL", on = true },
    heal = { label = "Heals", desc = "Heals you receive.", stream = "heals", ink = "GOOD", on = true },
    hot = { label = "Heals over time", desc = "The ticks of a heal over time on you.", stream = "heals", ink = "GOOD", on = true },
    shield = { label = "Absorb shields gained", desc = "A shield landing on you.", stream = "heals", ink = "TEXT", on = true },
    power = { label = "Rage, mana and energy gains", desc = "Power you get back from a spell or an attack.", stream = "heals", ink = "TEXT", power = true, on = false },
    powerTick = { label = "Power gains over time", desc = "Power that ticks back from a buff or a drink.", stream = "heals", ink = "TEXT", power = true, on = false },
    buff = { label = "Buffs gained and lost", desc = "The name of a buff as it lands on you or leaves.", stream = "notes", ink = "GOOD", on = false },
    debuff = { label = "Debuffs gained and lost", desc = "The name of a debuff as it lands on you or leaves.", stream = "notes", ink = "BAD", on = false },
    proc = { label = "Procs you can use", desc = "A spell that just lit up, like Overpower or Execute.", stream = "notes", ink = "MONEY", on = true },
    low = { label = "Low health and mana warning", desc = "A warning that stays up while your health or mana is low.", stream = "notes", ink = "BAD", on = true, fixed = true },
    combat = { label = "Entering and leaving combat", desc = "A word when a fight starts and ends.", stream = "notes", ink = "LABEL", on = false },
    rep = { label = "Reputation gains", desc = "Reputation you earn with a faction.", stream = "notes", ink = "LABEL", on = false },
    honor = { label = "Honor gains", desc = "Honor you earn in PvP.", stream = "notes", ink = "LABEL", on = false },
    other = { label = "Casts, interrupts and more", desc = "The game's other short messages: an interrupt, a dispel, an extra attack.", stream = "notes", ink = "TEXT", on = true },
}

-- Game message type -> kind. crit = shown as a crit. Anything missing here
-- uses the game's own COMBAT_TEXT_<type> string and counts as "other".
CT.MESSAGES = {
    DAMAGE = "hit", DAMAGE_CRIT = "hit", DAMAGE_SHIELD = "spell", SPLIT_DAMAGE = "hit",
    SPELL_DAMAGE = "spell", SPELL_DAMAGE_CRIT = "spell",
    MISS = "avoid", DODGE = "avoid", PARRY = "avoid", EVADE = "avoid", IMMUNE = "avoid", DEFLECT = "avoid", REFLECT = "avoid",
    SPELL_MISS = "avoid", SPELL_DODGE = "avoid", SPELL_PARRY = "avoid", SPELL_EVADE = "avoid", SPELL_IMMUNE = "avoid",
    SPELL_DEFLECT = "avoid", SPELL_REFLECT = "avoid", SPELL_MISFIRE = "avoid",
    BLOCK = "reduce", ABSORB = "reduce", RESIST = "reduce", SPELL_BLOCK = "reduce", SPELL_ABSORB = "reduce", SPELL_RESIST = "reduce",
    HEAL = "heal", HEAL_CRIT = "heal", HEAL_ABSORB = "heal", HEAL_CRIT_ABSORB = "heal",
    PERIODIC_HEAL = "hot", PERIODIC_HEAL_CRIT = "hot", PERIODIC_HEAL_ABSORB = "hot",
    ABSORB_ADDED = "shield",
    ENERGIZE = "power", PERIODIC_ENERGIZE = "powerTick",
    SPELL_AURA_START = "buff", SPELL_AURA_END = "buff",
    SPELL_AURA_START_HARMFUL = "debuff", SPELL_AURA_END_HARMFUL = "debuff",
    SPELL_ACTIVE = "proc",
    ENTERING_COMBAT = "combat", LEAVING_COMBAT = "combat",
    FACTION = "rep", HONOR_GAINED = "honor",
}

CT.CRIT_TYPES = { DAMAGE_CRIT = true, SPELL_DAMAGE_CRIT = true, HEAL_CRIT = true, HEAL_CRIT_ABSORB = true,
    PERIODIC_HEAL_CRIT = true, SPELL_ACTIVE = true }

-- School colors by UNIT_COMBAT schoolMask bit, softened to fit the palette.
-- The lowest bit wins on multi-school spells.
CT.SCHOOL_ORDER = { 2, 4, 8, 16, 32, 64 }
CT.SCHOOLS = {
    [2] = { 1, 0.9, 0.55 },     -- holy
    [4] = { 1, 0.56, 0.3 },     -- fire
    [8] = { 0.6, 0.88, 0.45 },  -- nature
    [16] = { 0.55, 0.82, 1 },   -- frost
    [32] = { 0.72, 0.56, 0.95 },-- shadow
    [64] = { 0.95, 0.6, 0.9 },  -- arcane
}

function CT.SchoolColor(mask)
    for _, bit_ in ipairs(CT.SCHOOL_ORDER) do
        if bit.band(mask, bit_) ~= 0 then return CT.SCHOOLS[bit_] end
    end
end

-- Defaults live here rather than in DB.lua because the colors copy Style.INK.
local function ink(name)
    local c = INK[name]
    return { c[1], c[2], c[3] }
end

local kinds = {}
for id, k in pairs(CT.KINDS) do
    kinds[id] = { on = k.on, stream = k.stream, color = ink(k.ink), power = k.power }
end

DUI.DB.GENERAL_DEFAULTS.sct = {
    enabled = true,
    outline = "OUTLINE",
    shadow = true,
    numbers = "full",
    signs = true,           -- - before damage, + before heals
    critMark = false,       -- ! after crits
    schoolColors = true,    -- color spell hits by school
    healerNames = false,
    crit = "flare",
    glow = 0.8,             -- brightness of the glow behind crits
    tick = false,           -- slanted mark beside each line; in game it read as a stray "/"
    underline = true,       -- underline under crits
    warnAt = 0.3,           -- health/mana fraction (0-1) that triggers the warning
    streams = {
        hits = { on = true, motion = "slant", size = 22, critSize = 32, align = "RIGHT", life = 1.5, dist = 130, lines = 9 },
        heals = { on = true, motion = "slant", size = 20, critSize = 30, align = "LEFT", life = 1.5, dist = 130, lines = 9 },
        notes = { on = true, motion = "stack", size = 20, critSize = 26, align = "CENTER", life = 2.4, dist = 0, lines = 5 },
    },
    kinds = kinds,
}

-- A preset is a full look. The one whose values all match is shown as picked.
CT.PRESET_ORDER = { "daylight", "calm", "punchy", "classic" }
CT.PRESETS = {
    daylight = { label = "Daylight", crit = "flare", glow = 0.8, tick = false, underline = true,
        hits = { motion = "slant", size = 22, critSize = 32, life = 1.5, dist = 130 },
        heals = { motion = "slant", size = 20, critSize = 30, life = 1.5, dist = 130 } },
    calm = { label = "Calm", crit = "pop", glow = 0.35, tick = false, underline = false,
        hits = { motion = "rise", size = 18, critSize = 24, life = 2, dist = 90 },
        heals = { motion = "rise", size = 17, critSize = 22, life = 2, dist = 90 } },
    punchy = { label = "Punchy", crit = "slam", glow = 1, tick = false, underline = true,
        hits = { motion = "fountain", size = 26, critSize = 44, life = 1.2, dist = 190 },
        heals = { motion = "fountain", size = 24, critSize = 40, life = 1.2, dist = 190 } },
    classic = { label = "Classic", crit = "pop", glow = 0, tick = false, underline = false,
        hits = { motion = "arc", size = 24, critSize = 36, life = 1.9, dist = 225 },
        heals = { motion = "arc", size = 24, critSize = 36, life = 1.9, dist = 225 } },
}

function CT.Get(path) return DUI:Get("general", "sct." .. path) end
function CT.Set(path, v) DUI:Set("general", "sct." .. path, v) end

local function near(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.001 end
    return a == b
end

function CT.Preset()
    for _, name in ipairs(CT.PRESET_ORDER) do
        local p, same = CT.PRESETS[name], true
        for _, key in ipairs({ "crit", "glow", "tick", "underline" }) do
            if not near(CT.Get(key), p[key]) then same = false end
        end
        for _, id in ipairs({ "hits", "heals" }) do
            for key, v in pairs(p[id]) do
                if not near(CT.Get("streams." .. id .. "." .. key), v) then same = false end
            end
        end
        if same then return name end
    end
    return "custom"
end

function CT.SetPreset(name)
    local p = CT.PRESETS[name]
    if not p then return end
    for _, key in ipairs({ "crit", "glow", "tick", "underline" }) do CT.Set(key, p[key]) end
    for _, id in ipairs({ "hits", "heals" }) do
        for key, v in pairs(p[id]) do CT.Set("streams." .. id .. "." .. key, v) end
    end
end
