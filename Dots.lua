-- Your DoTs for every module that shows them (target frame, nameplates): how
-- much damage the ones you've put on a mob will still deal.
--
-- The client gives addons neither the combat log (closed) nor a mob's auras
-- (secret), so this learns your DoTs the way the Does It Die addon does:
--   * your own casts stay readable (UNIT_SPELLCAST_SENT/SUCCEEDED for the
--     player are never secret), and a spell's description gives its damage,
--     school and duration;
--   * UNIT_COMBAT reports every hit on a unit token (target, focus, plates).
--     On Forever the amount is secret even though the docs don't say so,
--     while action, flag and school stay plain. A hit is matched to one of
--     your DoTs by school and rhythm alone (onBeat), and the damage left is
--     the description's share times a learned factor. Where amounts are
--     plain, hits (onWound) also match on size and learn the real ticks;
--   * after a fight the game's damage meter reads plain, and each DoT's total
--     there over the ticks counted here teaches its real size (spell power
--     and attack power included, which descriptions leave out).
--   Sizes are kept as a factor of the description's share: a spell keeps one
--   id at every level, so a size seen at level 10 says nothing about level 47.
-- Everything here is a plain number. Health is never read: DotsDraw.lua hands
-- these numbers to the client's bars next to the unit's secret health, and
-- the bars do the comparing.

local _, DUI = ...

local Dots = {}
DUI.Dots = Dots

local VERSION = 3 -- bumping this drops learned tick sizes that older code got wrong
local DEFAULT_INTERVAL = 3
-- Seconds either side of an expected tick. On Forever the first tick lands
-- within about 0.1 s of one interval after the cast, later ones within about
-- 0.1 s of the first tick's rhythm. Tight windows keep melee swings out
-- (same Physical school as a bleed, similar size, about 1 s apart).
local TICK_WINDOW, TICK_WINDOW_ANCHORED = 0.45, 0.25
local MISSES_BEFORE_DROP = 3 -- a DoT that never ticks was resisted or immune
-- A projectile DoT starts when it lands. Serpent Sting's first tick came
-- 3.6-3.9 s after the cast instead of 3.
local PROJECTILE_TRAVEL = 1.5
-- Once a DoT's tick size is known, same-school hits further off belong to
-- something else (the Imp's Firebolt beside Immolate, white hits beside Rip).
local SIZE_TOLERANCE, FIRST_SIZE_TOLERANCE = 0.25, 0.3
-- A bleed's first tick before its size is known: a white hit on its rhythm
-- (often ten times a Rend tick) is refused past this many description shares.
local BLEED_CEILING = 4
local CRIT_MIN, CRIT_MAX = 1.3, 2.3
-- A cast's own outcome arrives almost at once: the first avoid or hit on the
-- mob right after it decides. It can also arrive just before the cast event.
local OUTCOME_WINDOW, OUTCOME_LOOKBACK = 0.4, 0.25
-- A finisher that lands spends its combo points, one that misses keeps them.
-- Points spent this close to the cast were the finisher's.
local SPENT_WINDOW = 0.5
local SENT_SECONDS = 10
local SAME_SLOT = 0.2 -- two hits in one tick slot: the one closer in size was the tick
local COMBO_CAP = 5
local TICK_EVERY = 0.1

-- Description patterns. English here, other languages in Dots.LOCALES below
-- (a key a language leaves out uses the English one).
Dots.PATTERNS = {
    finisher = "Finishing move",
    perPoint = "(%d+) points?%s*:%s*(%d+) damage over (%d+%.?%d*) sec",
    weapon = "[Cc]oats a weapon", -- poisons: a proc, never cast on the mob
    heal = "^Heals",
    over = "(%d+)%s*([%a ]-)%s*damage over (%d+%.?%d*) sec",
    every = "(%d+)%s*([%a ]-)%s*damage every (%d+%.?%d*) sec",
    drain = "(%d+) health.-every (%d+%.?%d*) sec",
    lasts = "[Ll]asts (%d+%.?%d*) sec",
    awards = "Awards (%d+) combo point",
    -- How the game groups big numbers and writes decimals here ("1,214").
    thousands = { "," },
}

-- The French client words its tooltips its own way: "inflige 40 points de
-- dégâts d'Ombre en 12 sec.", "perd 15 points de vie en 9 sec." (Rend).
Dots.LOCALES = {
    frFR = {
        finisher = "Coup de grâce",
        perPoint = "(%d+) points?%s*:%s*(%d+)[^%d]-dégâts en (%d+%.?%d*) sec",
        weapon = "[Ee]nduit une arme",
        heal = "^Rend ",
        over = "(%d+) points? ([^%d]-) en (%d+%.?%d*) sec",
        drain = "(%d+) points de vie.-toutes les (%d+%.?%d*) sec",
        lasts = "[Dd]ure (%d+%.?%d*) sec",
        awards = "gagnez (%d+) points? de combo",
        thousands = { "\194\160", "\226\128\175", " " }, decimal = ",",
    },
    -- Spanish puts the school after the damage: "causando 40 p. de daño de
    -- las Sombras durante 12 s.", "15 p. de salud ... cada 3 segundo durante 30 s."
    esES = {
        finisher = "[Rr]emate",
        perPoint = "(%d+) puntos?[^:%d]*:%s*(%d+)[^%d]-daño durante (%d+%.?%d*) s",
        weapon = "[Cc]ubre un arma",
        heal = "^Cura",
        over = "(%d+) p%. de daño([^%d]-) durante (%d+%.?%d*) s",
        drain = "(%d+) p%. de salud.-cada (%d+%.?%d*) s",
        lasts = "durante (%d+%.?%d*) s",
        awards = "[Oo]torga (%d+) p[^%s]* de combo",
        thousands = { "%." }, decimal = ",",
    },
    -- Brazilian Portuguese: "causando 40 de dano de Sombra ao longo de 12 s."
    ptBR = {
        finisher = "Golpe final",
        perPoint = "(%d+) pontos?[^:%d]*:%s*(%d+) de dano ao longo de (%d+%.?%d*) s",
        weapon = "[Cc]obre a arma",
        heal = "^Cura",
        over = "(%d+) de dano([^%d]-) ao longo de (%d+%.?%d*) s",
        drain = "(%d+) pontos de vida.-a cada (%d+%.?%d*) s",
        lasts = "[Dd]ura (%d+%.?%d*) s",
        awards = "[Cc]oncede (%d+) pontos? de combo",
        thousands = { "%." }, decimal = ",",
    },
    -- German, Korean and Chinese name the duration before the damage, so
    -- those patterns say the order of their captures (see Dots.Parse).
    -- "verursacht 12 Sek. lang 40 Punkt(e) Schattenschaden", Rake's "39
    -- Punkt(e) zusätzlichen Schaden im Verlauf von 9 Sek."
    deDE = {
        finisher = "Finishing%-Move",
        perPoint = "(%d+) Punkte?:%s*(%d+) Schaden[^%d]-(%d+%.?%d*) Sek",
        weapon = "[Üü]berzieht eine Waffe",
        heal = "^Heilt",
        over = {
            { "(%d+%.?%d*) Sek%.[^%d]-(%d+)([^%d]-[Ss]chaden)", order = "saw" },
            { "(%d+)([^%d]-[Ss]chaden) im Verlauf von (%d+%.?%d*) Sek" },
        },
        drain = { "alle (%d+%.?%d*) Sek%.%s*(%d+) Punkt%(e%) Gesundheit", order = "ea" },
        lasts = "Hält (%d+%.?%d*) Sek%. lang an",
        awards = "Gewährt (%d+) Combopunkt",
        thousands = { "%." }, decimal = ",",
    },
    -- "40 ед. урона от темной магии за 12 сек.", "12 дополнительного урона от
    -- тайной магии в течение 9 сек.", Curse of Agony's "в течение 24 сек. ...
    -- Общая величина урона - 84."
    ruRU = {
        finisher = "Завершающий прием",
        perPoint = "(%d+) прием[^:%d]*:%s*(%d+) ед%. урона за (%d+%.?%d*) сек",
        weapon = "Смазать оружие",
        heal = "^Излечение",
        over = {
            { "(%d+) ед%.([^%d]-) за (%d+%.?%d*) сек" },
            { "(%d+)([^%d]-урона[^%d]-) в течение (%d+%.?%d*) сек" },
            { "(%d+)( здоровья) за (%d+%.?%d*) сек" },
            { "в течение (%d+%.?%d*) сек%.[^%d]-урона %- (%d+)", order = "sa" },
        },
        drain = "(%d+) ед%. здоровья.-раз в (%d+%.?%d*) сек",
        lasts = "Время действия[^%d]*(%d+%.?%d*) сек",
        awards = "Длина серии приемов увеличивается на (%d+)",
        thousands = { "\194\160", "\226\128\175", " " }, decimal = ",",
    },
    -- "在12秒内造成累计40点伤害" (Corruption names no school here: the spell's
    -- own school comes from SCHOOL_BY_NAME). Rip and Rupture list their
    -- points two ways: "1点：12秒内42点伤害", "1点：40伤害，持续8秒".
    zhCN = {
        finisher = "终结技",
        perPoint = {
            { "(%d+)点：(%d+%.?%d*)秒内(%d+)点伤害", order = "psa" },
            { "(%d+)点：(%d+)伤害，持续(%d+%.?%d*)秒" },
        },
        weapon = "武器浸毒",
        heal = "^治疗",
        over = { "在(%d+%.?%d*)秒内[^%d]-(%d+)点([^%d]-)伤害", order = "saw" },
        drain = { "每(%d+%.?%d*)秒将目标的(%d+)点生命值", order = "ea" },
        lasts = "持续(%d+%.?%d*)秒",
        awards = "奖励(%d+)个连击点数",
    },
    -- "12초에 걸쳐 총 40의 암흑 피해를 입힙니다."
    koKR = {
        finisher = "마무리 일격",
        perPoint = { "(%d+)[^%d:]*:%s*(%d+%.?%d*)초에 걸쳐 (%d+)의 피해", order = "psa" },
        weapon = "독을 바릅니다",
        heal = "회복시킵니다",
        over = { "(%d+%.?%d*)초에 걸쳐[^%d]-(%d+)의([^%d]-)피해", order = "saw" },
        drain = { "매 (%d+%.?%d*)초마다 (%d+)의 생명력", order = "ea" },
        lasts = "(%d+%.?%d*)초 동안 지속",
        awards = "(%d+)의 연계 포인트가 주어집니다",
    },
}
-- The Latin American client words its tooltips like the Spanish one.
Dots.LOCALES.esMX = Dots.LOCALES.esES
local ENGLISH = Dots.PATTERNS
function Dots.UseLocale(locale)
    local own = Dots.LOCALES[locale]
    Dots.PATTERNS = own and setmetatable(own, { __index = ENGLISH }) or ENGLISH
end
Dots.UseLocale(type(GetLocale) == "function" and GetLocale() or "enUS")

Dots.SCHOOLS = {
    Physical = 1, Holy = 2, Fire = 4, Nature = 8, Frost = 16, Shadow = 32, Arcane = 64,
    Frostfire = 4 + 16,       -- combined schools report as the OR of their masks
    -- French
    ["Sacré"] = 2, Feu = 4, feu = 4, Givre = 16, givre = 16, Ombre = 32, ombre = 32, Arcanes = 64,
    -- Spanish
    Sagrado = 2, Fuego = 4, Naturaleza = 8, Escarcha = 16, Sombras = 32, Arcano = 64,
    -- Portuguese (Sagrado and Arcano as in Spanish)
    Fogo = 4, Natureza = 8, Gelo = 16, Sombra = 32,
    -- Russian: "от темной магии", "от огня", "от сил природы", "от магии льда"
    ["светлой"] = 2, ["огня"] = 4, ["природы"] = 8, ["льда"] = 16, ["темной"] = 32, ["тайной"] = 64,
}
local PHYSICAL = 1

-- Tick intervals other than 3 s that descriptions don't state.
local INTERVALS = {
    ["Insect Swarm"] = 2, ["Curse of Agony"] = 2, ["Bane of Agony"] = 2, ["Fireball"] = 2,
    ["Holy Fire"] = 2, ["Rip"] = 2, ["Rupture"] = 2,
}
-- Uneven ticks: each tick is the average times its factor (factors average
-- to 1). Agony is back-loaded on Forever: 3,3,3,3, then 6..., then 9.
local AGONY = { 0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5, 1.5, 1.5, 1.5 }
local SHAPES = { ["Curse of Agony"] = AGONY, ["Bane of Agony"] = AGONY }
-- Spells whose description names no school in some language (Siphon Life
-- in English, Corruption, Curse of Agony and Fireball's burn in Chinese).
local SCHOOL_BY_NAME = { ["Siphon Life"] = 32, ["Corruption"] = 32, ["Curse of Agony"] = 32, ["Fireball"] = 4 }
-- Read like DoTs but aren't one on the mob: areas, channels, traps and
-- delayed damage (Wyvern Sting starts after the sleep).
local SKIP = {
    ["Rain of Fire"] = true, ["Hellfire"] = true, ["Blizzard"] = true, ["Flamestrike"] = true,
    ["Consecration"] = true, ["Hurricane"] = true, ["Volley"] = true,
    ["Drain Life"] = true, ["Drain Soul"] = true, ["Drain Mana"] = true, ["Health Funnel"] = true,
    ["Mind Flay"] = true, ["Arcane Missiles"] = true, ["Starshards"] = true,
    ["Immolation Trap"] = true, ["Explosive Trap"] = true, ["Wyvern Sting"] = true,
}
local PROJECTILE = { ["Serpent Sting"] = true, ["Fireball"] = true, ["Pyroblast"] = true, ["Frostfire Bolt"] = true }

-- The lists above go by English name. Each has a spell id, so a client in
-- another language finds its own name for it (rank 1; every rank shares it).
local SPELL_IDS = {
    ["Insect Swarm"] = 5570, ["Curse of Agony"] = 980, ["Fireball"] = 133, ["Holy Fire"] = 14914,
    ["Rip"] = 1079, ["Rupture"] = 1943, ["Siphon Life"] = 18265, ["Rain of Fire"] = 5740,
    ["Hellfire"] = 1949, ["Blizzard"] = 10, ["Flamestrike"] = 2120, ["Consecration"] = 26573,
    ["Hurricane"] = 16914, ["Volley"] = 1510, ["Drain Life"] = 689, ["Drain Soul"] = 1120,
    ["Drain Mana"] = 5138, ["Health Funnel"] = 755, ["Mind Flay"] = 15407, ["Arcane Missiles"] = 5143,
    ["Starshards"] = 10797, ["Immolation Trap"] = 13795, ["Explosive Trap"] = 13813,
    ["Wyvern Sting"] = 19386, ["Serpent Sting"] = 1978, ["Pyroblast"] = 11366,
    ["Corruption"] = 172,
}

local AVOIDS = {
    MISS = true, DODGE = true, PARRY = true, EVADE = true, IMMUNE = true, DEFLECT = true, RESIST = true, REFLECT = true,
}
-- Spells can't be dodged or parried, so next to a spell DoT these were melee.
local MELEE_ONLY = { DODGE = true, PARRY = true, DEFLECT = true }

local isSecret = DUI.IsSecret
local function round(v) return math.floor(v + 0.5) end

-- This client's name for each listed spell -> its English name. Built on first
-- use and again (at most every few seconds) while a spell's name hasn't loaded.
local english, englishMissing, englishAt
local function englishName(name)
    local now = GetTime()
    if not english or (englishMissing and now - englishAt > 5) then
        english, englishMissing, englishAt = {}, false, now
        for en, id in pairs(SPELL_IDS) do
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok and type(n) == "string" and not isSecret(n) then english[n] = en else englishMissing = true end
        end
    end
    return english[name] or name
end

-- Reading a description

-- German joins the school to the word for damage (Schattenschaden), and
-- Chinese and Korean don't split words with spaces, so these are looked for
-- inside the words. The game's own names for the schools are tried too.
Dots.SCHOOL_PARTS = {
    Heilig = 2, Feuer = 4, Natur = 8, Frost = 16, Schatten = 32, Arkan = 64,
    ["神圣"] = 2, ["火焰"] = 4, ["自然"] = 8, ["冰霜"] = 16, ["暗影"] = 32, ["奥术"] = 64,
    ["신성"] = 2, ["화염"] = 4, ["자연"] = 8, ["냉기"] = 16, ["암흑"] = 32, ["비전"] = 64,
}
local GAME_SCHOOLS = {
    STRING_SCHOOL_HOLY = 2, STRING_SCHOOL_FIRE = 4, STRING_SCHOOL_NATURE = 8,
    STRING_SCHOOL_FROST = 16, STRING_SCHOOL_SHADOW = 32, STRING_SCHOOL_ARCANE = 64,
}
local function schoolParts()
    local parts = {}
    for global, mask in pairs(GAME_SCHOOLS) do
        local word = _G[global]
        if type(word) == "string" and word ~= "" then parts[word] = mask end
    end
    for part, mask in pairs(Dots.SCHOOL_PARTS) do parts[part] = parts[part] or mask end
    return parts
end

local function schoolOf(words)
    local school
    -- Words split on spaces and punctuation, so "d'Ombre" gives "Ombre" and an
    -- accented word stays whole. French tooltips use both apostrophes.
    words = string.gsub(words or "", "\226\128\153", "'")
    for word in string.gmatch(words, "[^%s%p%d]+") do
        if Dots.SCHOOLS[word] then school = Dots.SCHOOLS[word] end
    end
    if school then return school end
    -- The last school named inside a longer word, as above.
    local at = 0
    for part, mask in pairs(schoolParts()) do
        local from = string.find(words, part, 1, true)
        if from and from > at then school, at = mask, from end
    end
    return school or PHYSICAL
end

-- A pattern is a string whose captures come in the English order, or
-- { pattern, order = "saw" } for a language that puts them another way, or a
-- list of those. Each letter of order names a capture: a the damage, w the
-- words naming its school, s the seconds, p combo points, e seconds a tick.
local function shapes(spec)
    if type(spec) == "string" then return { { spec } } end
    if type(spec[1]) == "string" then return { spec } end
    return spec
end

-- Every match of every shape, by role, in the order they sit in the text.
local function scan(desc, spec, order)
    local found = {}
    for _, shape in ipairs(shapes(spec)) do
        local roles, from = shape.order or order, 1
        while true do
            local r = { string.find(desc, shape[1], from) }
            if not r[1] then break end
            local m = { at = r[1] }
            for i = 1, #roles do m[string.sub(roles, i, i)] = r[i + 2] end
            found[#found + 1] = m
            from = r[2] + 1
        end
    end
    table.sort(found, function(x, y) return x.at < y.at end)
    return found
end

-- Finishers list their DoT per combo point; points past the list use the top one.
local function parseFinisher(desc, points)
    local byPoints, top = {}, 0
    for _, m in ipairs(scan(desc, Dots.PATTERNS.perPoint, "pas")) do
        local p = tonumber(m.p)
        byPoints[p] = { total = tonumber(m.a), duration = tonumber(m.s) }
        if p > top then top = p end
    end
    if top == 0 then return nil end
    local e = byPoints[math.max(1, math.min(points, top))] or byPoints[top]
    return e.total, PHYSICAL, e.duration
end

-- French words a mana drain like a DoT ("616 points de mana en 8 sec", Viper
-- Sting), so words naming mana mean the health bar has nothing to show.
local function drainsMana(words)
    words = string.lower(words or "")
    local mana = type(MANA) == "string" and string.lower(MANA) or "mana"
    return string.find(words, "mana", 1, true) ~= nil or string.find(words, mana, 1, true) ~= nil
end

-- The game groups big numbers in descriptions ("1,214 Shadow damage", "1.214",
-- "1 214") and some languages write decimals with a comma ("7,5 Sek."). The
-- patterns want plain digits: on "1,214" they started after the comma and
-- read 214. A separator only counts between a digit and exactly three more.
local function plainNumbers(desc)
    local P = Dots.PATTERNS
    for _, sep in ipairs(P.thousands or {}) do
        local grouped = "(%d)" .. sep .. "(%d%d%d)%f[^%d]"
        for _ = 1, 2 do desc = string.gsub(desc, grouped, "%1%2") end -- twice for 1,234,567
    end
    if P.decimal then desc = string.gsub(desc, "(%d)" .. P.decimal .. "(%d)", "%1.%2") end
    return desc
end

-- Returns total, school, duration, interval (only when stated), or nil if not
-- a DoT. combo is the points a finisher was cast with (unknown = 1, erring low).
function Dots.Parse(desc, combo)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    desc = plainNumbers(desc)
    local P = Dots.PATTERNS
    if string.find(desc, P.finisher) then return parseFinisher(desc, combo or 1) end
    if string.find(desc, P.weapon) or string.find(desc, P.heal) then return nil end
    -- The last "... damage over N sec", so Immolate's periodic part, not its hit.
    local over = scan(desc, P.over, "aws")
    local last = over[#over]
    if last and drainsMana(last.w) then last = nil end
    if last then
        local total, duration = tonumber(last.a), tonumber(last.s)
        if total and duration and duration > 0 then return total, schoolOf(last.w), duration end
    end
    local found = scan(desc, P.every, "aws")[1]
    local amount, words, every = found and found.a, found and found.w, found and found.s
    if not amount then
        found = scan(desc, P.drain, "ae")[1]
        amount, every, words = found and found.a, found and found.e, ""
    end
    local lasts = string.match(desc, P.lasts)
    if amount and every and lasts then
        every, lasts = tonumber(every), tonumber(lasts)
        if every > 0 and lasts > 0 then
            return tonumber(amount) * round(lasts / every), schoolOf(words), lasts, every
        end
    end
    return nil
end

-- State

local byMob = {} -- mob key -> { [spell name] = dot }
local sent = {} -- cast GUID -> { key, at }, the mob a cast was aimed at
local counted = 0             -- combo points counted from builders
local comboAtSend             -- combo points read when a finisher was sent
local lastFinisher            -- { id, points, at }: the last finisher cast and the points it used
local pendingBuilder -- { key, points, at }: a builder whose outcome isn't known yet
-- { key, name, dot, previous, at, finisher, landedAt }: a DoT cast whose outcome isn't known yet.
-- landedAt: its upfront hit landed (Rake, Immolate), so only an IMMUNE can still take its DoT back.
local pendingCast
local lastOutcome             -- { key, avoided, action, school, at }
local comboMovedAt            -- when your combo points last changed
-- This fight's count for learning from the meter. keys: tickKey -> { id,
-- share, factors, direct, dots }; untracked: spell ids cast at nothing that
-- could be told apart (the meter still has their damage); readable: tickKeys
-- a plain tick taught this fight.
local tally = { keys = {}, untracked = {}, readable = {} }
local spentCheck              -- { cast, dot, replaced }: a finisher dropped for an avoid, until its points say
local ticker
local events = CreateFrame("Frame")
local hearing = false -- UNIT_COMBAT is registered only while a cast or DoT needs the hits

-- Whether any hit on a mob can matter now: a DoT running, a cast sent, or one
-- whose outcome is pending. Otherwise hits (hundreds a second on every token
-- in a raid) aren't listened to at all.
local function needHits()
    return next(byMob) ~= nil or next(sent) ~= nil or pendingBuilder ~= nil or pendingCast ~= nil
end

local function hear(on)
    if on == hearing then return end
    hearing = on
    if on then
        events:RegisterEvent("UNIT_COMBAT")
        events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player") -- combo points spent: a finisher landed
    else
        events:UnregisterEvent("UNIT_COMBAT")
        events:UnregisterEvent("UNIT_POWER_FREQUENT")
    end
end

-- The learned tick sizes, looked up on every hit. The table reference is
-- cached once the character's name is known, and refreshed when the saved
-- table is replaced (DB.Init after the game hands DaylightUIDB over).
local ticks, ticksIn
local function saved()
    local DB = DUI.DB
    if ticks and ticksIn == DB.sv and ticksIn == _G.DaylightUIDB then return ticks end
    local c = DB.Character()
    if type(c.dots) ~= "table" or c.dots.v ~= VERSION then c.dots = { v = VERSION, ticks = {} } end
    if type(c.dots.ticks) ~= "table" then c.dots.ticks = {} end
    -- Before the name is known DB.Character() is a scratch entry, so don't cache it.
    if DB.CharKey() then ticks, ticksIn = c.dots.ticks, DB.sv else ticks = nil end
    return c.dots.ticks
end

-- key: the one mob whose DoTs changed (a plate or frame on another mob has
-- nothing to redraw); nil means any number of them.
local function changed(key) DUI.Fire("DotsChanged", key) end

-- The nameplate token ("nameplate3") showing the mob behind unit, or nil. A
-- mob keeps its token from NAME_PLATE_UNIT_ADDED to NAME_PLATE_UNIT_REMOVED,
-- and the game's plate frame keeps the token it was given (SetUnit).
local function plateToken(unit)
    if string.find(unit, "^nameplate%d+$") then return unit end
    -- The client refuses chained tokens ("targettarget", "focustarget") here.
    if #unit > 6 and string.sub(unit, -6) == "target" then return nil end
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if type(get) ~= "function" then return nil end
    local plate = get(unit, false)
    local token = type(plate) == "table" and plate.unitToken
    if type(token) == "string" and not isSecret(token) and string.find(token, "^nameplate%d+$") then return token end
    return nil
end

-- The mob behind a unit token: its GUID. Where the client hides GUIDs (a
-- restricted map, a battleground) it's the mob's nameplate while it has one,
-- else "target" for the target alone, else nil (that token can't be told apart).
function Dots.KeyOf(unit)
    if type(unit) ~= "string" then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return nil end
    if isSecret(guid) then
        local token = plateToken(unit)
        if token then return "plate:" .. token end
        return unit == "target" and "target" or nil
    end
    if type(guid) == "string" then return guid end
    return nil
end

local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
    hear(false)
end

function Dots.Forget()
    byMob, sent = {}, {}
    counted, comboAtSend, lastFinisher = 0, nil, nil
    pendingBuilder, pendingCast, lastOutcome, spentCheck = nil, nil, nil, nil
    tally = { keys = {}, untracked = {}, readable = {} }
    stopTicker()
    changed()
end

-- One DoT's sums

-- The description's share of one tick.
local function share(dot) return dot.total / dot.totalTicks end

-- The learned size for this cast: the saved factor times today's share, since
-- the description grows with level and spell power. nil if none is saved.
local function learned(dot)
    local factor = dot.tickKey and saved()[dot.tickKey]
    if type(factor) == "number" then return share(dot) * factor end
end

-- Best known average tick: the ones seen (crits excluded), else the learned
-- size, else the description's share.
local function expected(dot)
    if dot.normalTicks > 0 then return dot.tickSum / dot.normalTicks end
    return learned(dot) or share(dot)
end

local function tickNumberAt(dot, when)
    return math.max(1, round((when - dot.appliedAt) / dot.interval))
end

-- The factor for a given tick number (1 for even DoTs), with the shape
-- stretched to the DoT's tick count.
local function shapeOf(dot, number)
    local shape = dot.shape
    if not shape then return 1 end
    local i = math.ceil(math.min(math.max(number, 1), dot.totalTicks) / dot.totalTicks * #shape)
    return shape[math.max(1, math.min(i, #shape))]
end

-- A doubtful DoT (an avoid right after its cast that may have been someone
-- else's) only counts once it has ticked.
local function waiting(dot) return dot.ticksSeen == 0 and dot.doubtful == true end

local function remaining(dot)
    if dot.nextTickAt > dot.expiresAt + dot.interval / 2 then return 0 end
    local left = round((dot.expiresAt - dot.nextTickAt) / dot.interval) + 1
    if not dot.shape then return left * expected(dot) end
    local avg, total = expected(dot), 0
    for number = math.max(1, dot.totalTicks - left + 1), dot.totalTicks do
        total = total + avg * shapeOf(dot, number)
    end
    return total
end

-- Does It Die's API while it does the counting (see Dots.Borrowable).
local borrowed
local function borrowedLeft(unit)
    local ok, total = DUI.SafeReturn(borrowed.GetRemainingDamage, unit)
    if not ok or type(total) ~= "number" or isSecret(total) or total <= 0 then return nil end
    return round(total)
end

-- What your DoTs on unit will still deal, as a plain whole number, or nil.
function Dots.Left(unit)
    if borrowed then return borrowedLeft(unit) end
    local dots = byMob[Dots.KeyOf(unit)]
    if not dots then return nil end
    local total = 0
    for _, dot in pairs(dots) do
        if not waiting(dot) then total = total + remaining(dot) end
    end
    total = round(total)
    if total <= 0 then return nil end
    return total
end

-- Learning from the damage meter

-- In a fight every hit's amount is secret, so ticks are found by school and
-- timing alone and teach no size. Once the fight is over the game's damage
-- meter reads plain: each DoT's total over the ticks counted here is its real
-- average tick, kept as a factor of the description's share. The meter counts
-- every mob, the tally only what was seen, so a spell is only learned when
-- the two can match.
local LEARN_MIN = 2                      -- at least two average ticks' worth this fight
local RATIO_MIN, RATIO_MAX = 0.5, 2.5    -- further off, something else got mixed in
local WEIGHT_CAP = 20                    -- older fights count as at most this many ticks, so gear catches up
local METER_TRIES, METER_WAIT = 20, 0.5  -- the meter can take a few seconds to read plain


-- The damage a spell deals up front besides its DoT (Immolate's hit), from
-- its description: 0 when nothing before the DoT's own clause names a number,
-- nil when something does but this language's wording can't be read for it.
function Dots.Upfront(desc)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    desc = plainNumbers(desc)
    local over = scan(desc, Dots.PATTERNS.over, "aws")
    local last = over[#over]
    if not last then return 0 end
    local head = string.sub(desc, 1, last.at - 1)
    if not string.find(head, "%d") then return 0 end
    if Dots.PATTERNS ~= ENGLISH then return nil end
    local lo, hi = string.match(head, "(%d+) to (%d+)")
    if lo then return (tonumber(lo) + tonumber(hi)) / 2 end
    return tonumber(string.match(head, "(%d+)[^%d]-damage") or "")
end

local function tallyCast(dot, direct)
    local t = tally.keys[dot.tickKey]
    if not t then
        t = { id = dot.spellID, share = share(dot), factors = 0, direct = 0, dots = {} }
        tally.keys[dot.tickKey] = t
    end
    t.dots[#t.dots + 1] = dot
    if direct == nil then t.unclear = true else t.direct = t.direct + direct end
    dot.tally = t
end

local function tallyTick(dot, factor)
    local t = dot.tally
    if t and tally.keys[dot.tickKey] == t then t.factors = t.factors + factor end
end

local function weights()
    saved()
    local c = DUI.DB.Character().dots
    if type(c.weights) ~= "table" then c.weights = {} end
    return c.weights
end

-- Whether this fight's count of a spell can be set against the meter's total.
local function matches(key, t, counted, totals, perSpell)
    if t.factors < LEARN_MIN or counted.readable[key] or t.unclear or #t.dots == 0 then return false end
    if counted.untracked[t.id] or perSpell[t.id] > 1 or type(totals[t.id]) ~= "number" then return false end
    -- A cast whose ticks went on out of sight (no plate, tabbed away) dealt damage the count missed.
    for _, dot in ipairs(t.dots) do
        if dot.blind then return false end
    end
    return true
end

-- The player's damage per spell in the fight that just ended, or nil and
-- "wait" while the meter still reads secret.
local function meterTotals()
    local M = C_DamageMeter
    local E, S = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
    if type(M) ~= "table" or type(M.GetCombatSessionSourceFromType) ~= "function" or not (E and S) then return nil end
    if type(M.IsDamageMeterAvailable) == "function" and M.IsDamageMeterAvailable() == false then return nil end
    local data = M.GetCombatSessionSourceFromType(S.Current, E.DamageDone, UnitGUID("player"))
    local function open(t)
        return not isSecret(t) and type(t) == "table" and (type(canaccesstable) ~= "function" or canaccesstable(t))
    end
    if not open(data) or not open(data.combatSpells) then return nil, "wait" end
    local totals = {}
    for _, sp in ipairs(data.combatSpells) do
        if open(sp) then
            local id, amount = sp.spellID, sp.totalAmount
            if isSecret(id) or isSecret(amount) then return nil, "wait" end
            if type(id) == "number" and type(amount) == "number" then totals[id] = (totals[id] or 0) + amount end
        end
    end
    return totals
end

local function learnFromMeter(counted, tries)
    if InCombatLockdown() then return end -- a new fight began: the meter's current fight is that one
    local ok, totals, why = DUI.SafeReturn(meterTotals)
    if not ok then return end
    if not totals then
        if why == "wait" and tries > 0 then
            C_Timer.After(METER_WAIT, function() learnFromMeter(counted, tries - 1) end)
        end
        return
    end
    local perSpell = {}
    for _, t in pairs(counted.keys) do perSpell[t.id] = (perSpell[t.id] or 0) + 1 end
    local store, weight, any = saved(), weights(), false
    for key, t in pairs(counted.keys) do
        if matches(key, t, counted, totals, perSpell) then
            local ratio = totals[t.id] / (t.direct + t.share * t.factors)
            if ratio >= RATIO_MIN and ratio <= RATIO_MAX then
                local old = type(store[key]) == "number" and store[key] or nil
                local w = old and math.min(type(weight[key]) == "number" and weight[key] or 0, WEIGHT_CAP) or 0
                store[key] = math.floor(((old or 0) * w + ratio * t.factors) / (w + t.factors) * 1000 + 0.5) / 1000
                weight[key] = w + t.factors
                any = true
            end
        end
    end
    if any then changed() end -- DoTs still running take the new size
end

local function onFightOver()
    local counted = tally
    tally = { keys = {}, untracked = {}, readable = {} }
    if next(counted.keys) == nil then return end
    C_Timer.After(METER_WAIT, function() learnFromMeter(counted, METER_TRIES) end)
end

-- Upkeep

-- Whether hits on the mob reach the player right now. UNIT_COMBAT only covers unit
-- tokens, so a mob you tabbed away from ticks unseen and keeps its DoTs.
local function observable(key)
    if Dots.KeyOf("target") == key or Dots.KeyOf("focus") == key then return true end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and Dots.KeyOf(unit) == key then return true end
    end
    return false
end

-- How late a tick may run before its slot passes. The last one gets half an
-- interval: when seen it ends the DoT right away, so waiting costs nothing,
-- while giving up too soon would drop damage it was still going to deal.
local function lastSlot(dot) return dot.nextTickAt > dot.expiresAt - dot.interval / 2 end
local function lateness(dot) return lastSlot(dot) and dot.interval / 2 or TICK_WINDOW end

local function upkeep()
    local now, dropped = GetTime(), false
    for key, dots in pairs(byMob) do
        local slipped = false -- a tick's slot passed unseen, so its share comes off now
        for name, dot in pairs(dots) do
            local late = (dot.ticksSeen == 0 and dot.travel) or 0
            while dot.nextTickAt < now - lateness(dot) - late and dot.nextTickAt <= dot.expiresAt do
                dot.nextTickAt = dot.nextTickAt + dot.interval
                slipped = true
                local seen = observable(key)
                if dot.ticksSeen == 0 and seen then dot.missed = dot.missed + 1 end
                if not seen then dot.blind = true end -- it may have ticked where no hit could reach us
            end
            if dot.nextTickAt > dot.expiresAt + dot.interval / 2
                or (dot.ticksSeen == 0 and dot.missed >= MISSES_BEFORE_DROP) then
                dots[name] = nil
                dropped = true
            end
        end
        if next(dots) == nil then byMob[key] = nil end
        if slipped then changed(key) end
    end
    -- Sends that never landed (an interrupt) and outcomes past their window.
    for guid, s in pairs(sent) do
        if now - s.at > SENT_SECONDS then sent[guid] = nil end
    end
    if pendingBuilder and now - pendingBuilder.at > OUTCOME_WINDOW then pendingBuilder = nil end
    if spentCheck and now - spentCheck.cast.at > SPENT_WINDOW then spentCheck = nil end
    if pendingCast and now - pendingCast.at > OUTCOME_WINDOW then pendingCast = nil end
    if not needHits() then stopTicker() end
    if dropped then changed() end
end

local function startTicker()
    hear(true)
    if not ticker then ticker = C_Timer.NewTicker(TICK_EVERY, upkeep) end
end

-- Casts

local function describe(id)
    local okName, name = pcall(C_Spell.GetSpellName, id)
    local okDesc, desc = pcall(C_Spell.GetSpellDescription, id)
    if not okName or isSecret(name) or type(name) ~= "string" then return nil end
    if not okDesc or isSecret(desc) or type(desc) ~= "string" then desc = "" end
    return englishName(name), desc
end

-- Whether a spell's cast can matter here, per spell id: a DoT, a finisher or
-- a builder. A heal, mount or direct hit has nothing to learn from later
-- hits, so its send doesn't turn on UNIT_COMBAT or the ticker. A description
-- that isn't loaded yet (empty) isn't cached and is checked again next cast.
local matters = {}
local function mattersFor(id)
    local known = matters[id]
    if known ~= nil then return known end
    local name, desc = describe(id)
    if not name or desc == "" then return false end
    local P = Dots.PATTERNS
    known = string.find(desc, P.awards) ~= nil
        or (not SKIP[name] and (string.find(desc, P.finisher) ~= nil or Dots.Parse(desc) ~= nil))
    matters[id] = known
    return known
end

local function readCombo()
    if type(GetComboPoints) ~= "function" then return nil end
    local ok, points = pcall(GetComboPoints, "player", "target")
    if ok and not isSecret(points) and type(points) == "number" and points > 0 then return points end
    return nil
end

-- The mob a cast was sent at: the unit the game names (mouseover and focus
-- macros), else the target.
local AIMS = { "target", "mouseover", "focus", "softenemy" }
local function aimedAt(name)
    if type(name) == "string" and not isSecret(name) and name ~= "" then
        for _, unit in ipairs(AIMS) do
            local ok, n = pcall(UnitName, unit)
            if ok and not isSecret(n) and n == name then return Dots.KeyOf(unit) end
        end
    end
    return Dots.KeyOf("target")
end

local function onSent(targetName, castGUID, id)
    if not mattersFor(id) then return end
    local now = GetTime()
    for guid, s in pairs(sent) do
        if now - s.at > SENT_SECONDS then sent[guid] = nil end
    end
    if type(castGUID) == "string" then
        sent[castGUID] = { key = aimedAt(targetName), at = now }
        startTicker() -- its outcome (a dodge, a resist, a first tick) comes after this, so listen for hits
    end
    local _, desc = describe(id)
    if desc and string.find(desc, Dots.PATTERNS.finisher) then comboAtSend = readCombo() end
end

-- A cast that failed or was interrupted never lands. Drop its send now
-- rather than after SENT_SECONDS of listening to every hit.
local function onStopped(castGUID)
    if type(castGUID) == "string" then sent[castGUID] = nil end
end

-- An avoid on the mob that arrived just before the cast event, or nil. With
-- immune, also an IMMUNE followed by a hit: the cast's upfront part landed
-- and its DoT didn't (a bleed on a mob immune to bleeds).
local function avoidJustBefore(key, immune)
    local o = lastOutcome
    if not o or o.key ~= key then return nil end
    local now = GetTime()
    if o.avoided and now - o.at <= OUTCOME_LOOKBACK then return o end
    if immune and o.immuneAt and now - o.immuneAt <= OUTCOME_LOOKBACK then return o.immune end
end

-- Whether the combo points were spent around a finisher's cast.
local function spent(cast)
    return comboMovedAt ~= nil and comboMovedAt >= cast.at - OUTCOME_LOOKBACK and comboMovedAt - cast.at <= SPENT_WINDOW
end

-- An avoided DoT cast isn't on the mob: drop it, or restore the one it
-- replaced. A spell DoT is only taken back by an avoid that could be its own;
-- one that might not be (another school) makes it wait for a tick. Returns
-- false when the avoid was someone else's (its own may still come).
local function takeBack(cast, action, school)
    local dot = cast.dot
    local dots = byMob[cast.key]
    if not dots or dots[cast.name] ~= dot then return true end
    -- A swing missing in the same instant looks just like the finisher
    -- missing. Its points tell: spent means it landed.
    if cast.finisher and spent(cast) then return false end
    local own = not isSecret(school) and school == dot.school
    if dot.school ~= PHYSICAL and not own then
        if MELEE_ONLY[action] then return false end
        if not cast.previous then
            dot.doubtful = true
            changed(cast.key)
            return true
        end
    end
    dots[cast.name] = cast.previous
    if cast.finisher then spentCheck = { cast = cast, dot = dot, replaced = cast.previous } end
    changed(cast.key)
    return true
end

-- Your combo points changed. Spent right after a finisher that an avoid took
-- back means that avoid was a swing's: the finisher goes back on.
local function onComboMoved()
    local now = GetTime()
    comboMovedAt = now
    local check = spentCheck
    if not check or not spent(check.cast) then return end
    spentCheck = nil
    local cast = check.cast
    local dots = byMob[cast.key]
    if (dots and dots[cast.name]) ~= check.replaced or now > check.dot.expiresAt then return end
    byMob[cast.key] = dots or {}
    byMob[cast.key][cast.name] = check.dot
    startTicker()
    changed(cast.key)
end

local function onCast(castGUID, id)
    local s = type(castGUID) == "string" and sent[castGUID]
    local key
    if s then
        sent[castGUID], key = nil, s.key
    else
        key = Dots.KeyOf("target")
    end
    local name, desc = describe(id)
    if not name then return end
    local awards = tonumber(string.match(desc, Dots.PATTERNS.awards) or "")
    if awards then
        if not avoidJustBefore(key) then
            counted = math.min(COMBO_CAP, counted + awards)
            pendingBuilder = { key = key, points = awards, at = GetTime() }
        end
    end
    if SKIP[name] then return end
    local finisher = string.find(desc, Dots.PATTERNS.finisher) ~= nil
    local points
    if finisher then
        points = comboAtSend or (counted > 0 and counted or nil)
        comboAtSend, counted, pendingBuilder = nil, 0, nil
        lastFinisher = { id = id, points = points, at = GetTime() }
    end
    local total, school, duration, stated = Dots.Parse(desc, points)
    if not total then return end
    if not key then
        tally.untracked[id] = true -- the meter still counts what it deals
        return
    end
    -- A finisher's tick size depends on its points, so it's learned per point
    -- count, and not at all when the count is unknown.
    local tickKey = id
    if finisher then tickKey = points and (id .. "x" .. points) or nil end

    local now = GetTime()
    local interval = stated or INTERVALS[name] or DEFAULT_INTERVAL
    byMob[key] = byMob[key] or {}
    local previous = byMob[key][name]
    local dot = {
        spellID = id, tickKey = tickKey,
        school = SCHOOL_BY_NAME[name] or school,
        total = total, duration = duration, interval = interval,
        totalTicks = math.max(1, round(duration / interval)),
        shape = SHAPES[name], travel = PROJECTILE[name] and PROJECTILE_TRAVEL or nil,
        appliedAt = now, expiresAt = now + duration, nextTickAt = now + interval,
        tickSum = 0, normalTicks = 0, ticksSeen = 0, missed = 0,
    }
    byMob[key][name] = dot
    if tickKey then
        tallyCast(dot, finisher and 0 or Dots.Upfront(desc)) -- a finisher's point list is no upfront hit
    else
        tally.untracked[id] = true -- a finisher with unknown points: no size of its own to learn
    end
    pendingCast = { key = key, name = name, dot = dot, previous = previous, at = now, finisher = finisher }
    startTicker()
    local avoided = avoidJustBefore(key, true)
    if avoided and takeBack(pendingCast, avoided.action, avoided.school) then
        pendingCast = nil
    end
    changed(key)
end

-- Hits and avoids

-- One reused table each for the last avoid and hit, since a raid boss takes
-- hundreds of hits and misses a second.
local avoidOutcome = { avoided = true }
local function onAvoided(key, action, school)
    local now = GetTime()
    local o = avoidOutcome
    o.key, o.action, o.school, o.at = key, action, school, now
    lastOutcome = o
    if pendingBuilder and pendingBuilder.key == key then
        if now - pendingBuilder.at <= OUTCOME_WINDOW then
            counted = math.max(0, counted - pendingBuilder.points)
        end
        pendingBuilder = nil
    end
    local c = pendingCast
    if c and c.key == key then
        if now - c.at > OUTCOME_WINDOW then
            pendingCast = nil
        elseif c.landedAt then
            -- Its upfront hit landed: other avoids are someone else's, but the DoT itself may be immune.
            if action == "IMMUNE" and takeBack(c, action, school) then pendingCast = nil end
        elseif takeBack(c, action, school) then
            pendingCast = nil
        end
    end
end

-- A hit on the mob means the casts on it landed (a later avoid is someone
-- else's). A spell DoT's cast only counts by a hit in its own school.
-- A hit keeps an IMMUNE just before it on the same mob: an upfront part
-- landing while the DoT itself was refused (avoidJustBefore).
local hitOutcome = { avoided = false }
local immuneOutcome = { avoided = true, action = "IMMUNE" }
local function onHit(key, school)
    local now, prior = GetTime(), lastOutcome
    if prior and prior.avoided and prior.key == key and prior.action == "IMMUNE" and now - prior.at <= OUTCOME_LOOKBACK then
        immuneOutcome.key, immuneOutcome.school, immuneOutcome.at = key, prior.school, prior.at
        hitOutcome.immune, hitOutcome.immuneAt = immuneOutcome, prior.at
    elseif prior ~= hitOutcome or hitOutcome.key ~= key then
        hitOutcome.immune, hitOutcome.immuneAt = nil, nil
    end
    hitOutcome.key, hitOutcome.at = key, now
    lastOutcome = hitOutcome
    if pendingBuilder and pendingBuilder.key == key then pendingBuilder = nil end
    local c = pendingCast
    if c and c.key == key and not c.landedAt and (c.dot.school == PHYSICAL or c.dot.school == school) then
        c.landedAt = now -- it landed; only an IMMUNE for its DoT can still come
    end
end

-- Seconds from now to the nearest expected tick, and its number. Counted
-- from the first tick once seen (so jitter doesn't add up), else from the cast.
local function distance(dot, now)
    local anchor = dot.firstTickAt or dot.appliedAt
    if not dot.firstTickAt and dot.travel then
        local late = now - (anchor + dot.interval)
        if late > 0 then anchor = anchor + math.min(late, dot.travel) end
    end
    local k = math.max(1, round((now - anchor) / dot.interval))
    return math.abs(now - (anchor + k * dot.interval)), k
end

local function plausible(dot, amount, crit, number)
    local known, tolerance
    if dot.normalTicks > 0 then
        known, tolerance = dot.tickSum / dot.normalTicks, SIZE_TOLERANCE
    else
        known, tolerance = learned(dot), FIRST_SIZE_TOLERANCE
    end
    if not known then
        if dot.school ~= PHYSICAL then return true end
        return amount <= share(dot) * shapeOf(dot, number) * BLEED_CEILING + 1
    end
    known = known * shapeOf(dot, number)
    if crit then return amount >= known * CRIT_MIN - 1 and amount <= known * CRIT_MAX + 1 end
    return math.abs(amount - known) <= math.max(1, known * tolerance)
end

-- Saved for the next cast only once two normal ticks agree, since a single
-- one may have been someone else's hit slipping through. What's kept is the
-- real tick next to the description's share, so it still fits after a level.
local function learn(dot)
    if dot.tickKey and dot.normalTicks > 1 then
        local factor = dot.tickSum / dot.normalTicks / share(dot)
        saved()[dot.tickKey] = math.floor(factor * 1000 + 0.5) / 1000
        tally.readable[dot.tickKey] = true -- the meter then holds ticks this count didn't see
    end
end

-- Moves a DoT's bookkeeping to the tick in slot `index` that landed now.
local function anchor(dot, index, now)
    dot.missed = 0
    if dot.firstTickAt then
        dot.lastTickIndex = index
    else
        dot.firstTickAt, dot.lastTickIndex = now, 0
        if dot.travel then dot.appliedAt = now - index * dot.interval end
    end
    dot.lastTickAt = now
    dot.nextTickAt = now + dot.interval
    -- Ticks land a little after their nominal time, so the end follows them.
    local number = tickNumberAt(dot, now)
    dot.expiresAt = now + (dot.totalTicks - number) * dot.interval
end

-- Two same-school hits in one slot (a Shadow Bolt landing with a Corruption
-- tick): if this one is closer to the expected size, it was the tick.
local function swapSameSlot(dot, amount, crit, now)
    if crit or dot.lastTickCrit or not dot.lastTickAt or now - dot.lastTickAt > SAME_SLOT then return false end
    local factor = dot.lastTickShape
    local reference
    if dot.normalTicks > 1 then
        reference = (dot.tickSum - dot.lastTickAmount / factor) / (dot.normalTicks - 1)
    else
        reference = share(dot)
    end
    reference = reference * factor
    if math.abs(amount - reference) >= math.abs(dot.lastTickAmount - reference) then return false end
    dot.tickSum = dot.tickSum + (amount - dot.lastTickAmount) / factor
    dot.lastTickAmount = amount
    learn(dot)
    return true
end

-- A wrong learned size rejects every real tick. Two consecutive hits on the
-- DoT's rhythm that agree with each other and were rejected only on size are
-- the real ticks, so learn from them.
local function relearn(dot, amount, crit, index, dist, now)
    local window = dot.firstTickAt and TICK_WINDOW_ANCHORED or TICK_WINDOW
    local fresh = not dot.firstTickAt or index > dot.lastTickIndex
    if crit or not fresh or dist > window then return false end
    local prev = dot.offBeat
    local factor = shapeOf(dot, tickNumberAt(dot, now))
    local average = amount / factor
    dot.offBeat = { index = index, amount = amount, average = average, at = now }
    if not prev or index ~= prev.index + 1
        or math.abs(average - prev.average) > math.max(1, prev.average * SIZE_TOLERANCE) then
        return false
    end
    dot.offBeat = nil
    dot.tickSum, dot.normalTicks = prev.average + average, 2
    dot.ticksSeen = dot.ticksSeen + 2
    dot.lastTickAmount, dot.lastTickShape, dot.lastTickCrit = amount, factor, false
    learn(dot)
    if not dot.firstTickAt then
        dot.firstTickAt, dot.lastTickIndex = prev.at, 0
        index = 1
    end
    anchor(dot, index, now)
    return true
end

-- One hit arrives once per token showing the mob (target, its plate, focus)
-- and must count once. Two DoTs of one school can also tick for the same
-- amount in the same instant: those come twice from the same token. So within
-- an instant each hit's signature remembers its token and the DoTs it fed: a
-- repeat from that token feeds another DoT, one from another token is a copy.
local instantAt
local instant = {} -- signature -> { unit, fed = { [dot] = true } }
local function hitRecord(signature, unit, now)
    if instantAt ~= now then
        for k in pairs(instant) do instant[k] = nil end
        instantAt = now
    end
    local h = instant[signature]
    if h then
        if h.unit ~= unit then return nil end
    else
        h = { unit = unit, fed = {} }
        instant[signature] = h
    end
    return h
end

local function onWound(key, unit, amount, school, crit)
    local dots = byMob[key]
    if not dots then return end
    local now = GetTime()
    local h = hitRecord(key .. ":" .. amount .. ":" .. school, unit, now)
    if not h then return end

    local best, bestDist, bestIndex
    for _, dot in pairs(dots) do
        if not h.fed[dot] and dot.school == school and plausible(dot, amount, crit, tickNumberAt(dot, now)) then
            local dist, index = distance(dot, now)
            local window = dot.firstTickAt and TICK_WINDOW_ANCHORED or TICK_WINDOW
            if lastSlot(dot) then window = dot.interval / 2 end
            local fresh = not dot.firstTickAt or index > dot.lastTickIndex
            if fresh and dist <= window and (not bestDist or dist < bestDist) then
                best, bestDist, bestIndex = dot, dist, index
            end
        end
    end
    if not best then
        for _, dot in pairs(dots) do
            if not h.fed[dot] and dot.school == school then
                local dist, index = distance(dot, now)
                if swapSameSlot(dot, amount, crit, now) or relearn(dot, amount, crit, index, dist, now) then
                    h.fed[dot] = true
                    changed(key)
                    return
                end
            end
        end
        return
    end
    h.fed[best] = true
    local factor = shapeOf(best, tickNumberAt(best, now))
    best.ticksSeen = best.ticksSeen + 1
    best.lastTickAmount, best.lastTickShape, best.lastTickCrit = amount, factor, crit
    best.offBeat = nil
    if not crit then
        best.tickSum = best.tickSum + amount / factor
        best.normalTicks = best.normalTicks + 1
        learn(best)
    end
    anchor(best, bestIndex, now)
    changed(key)
end

-- A hit whose amount is secret: only school and timing can say it's a tick.
-- The rhythm stays the cast's (each slot takes one hit), so a swing landing
-- near a tick in its place changes nothing. A flag means a swing, since
-- bleeds aren't blocked.
local function onBeat(key, unit, school, flag)
    local dots = byMob[key]
    if not dots then return end
    if school == PHYSICAL and not isSecret(flag) and flag ~= "" then return end
    local now = GetTime()
    local h = hitRecord(key .. ":?:" .. school, unit, now)
    if not h then return end
    local best, bestDist, bestIndex
    for _, dot in pairs(dots) do
        if not h.fed[dot] and dot.school == school then
            local dist, index = distance(dot, now)
            local fresh = not dot.lastTickIndex or index > dot.lastTickIndex
            if fresh and dist <= TICK_WINDOW and (not bestDist or dist < bestDist) then
                best, bestDist, bestIndex = dot, dist, index
            end
        end
    end
    if not best then return end
    h.fed[best] = true
    if best.travel then -- was in flight until now, so its ticks and end count from here
        best.appliedAt = now - bestIndex * best.interval
        best.expiresAt = best.appliedAt + best.duration
        best.travel = nil
    end
    best.ticksSeen = best.ticksSeen + 1
    best.missed = 0
    best.lastTickIndex, best.lastTickAt = bestIndex, now
    tallyTick(best, shapeOf(best, tickNumberAt(best, now)))
    best.nextTickAt = (best.firstTickAt or best.appliedAt) + (bestIndex + 1) * best.interval
    changed(key)
end

-- Your group's tokens never point at a mob with your DoTs.
local function groupToken(unit)
    return unit == "player" or unit == "pet" or string.find(unit, "^raid") ~= nil or string.find(unit, "^party") ~= nil
end

local function onCombat(unit, action, flag, amount, school)
    if not needHits() then return end
    if isSecret(unit) or type(unit) ~= "string" or groupToken(unit) then return end
    if isSecret(action) or type(action) ~= "string" then return end
    if not AVOIDS[action] and action ~= "WOUND" then return end
    local key = Dots.KeyOf(unit)
    if not key then return end
    if isSecret(school) or type(school) ~= "number" then school = nil end
    if AVOIDS[action] then return onAvoided(key, action, school) end
    onHit(key, school)
    if not school then return end
    if isSecret(amount) or type(amount) ~= "number" then return onBeat(key, unit, school, flag) end
    onWound(key, unit, amount, school, not isSecret(flag) and flag == "CRITICAL")
end

-- Who wants it

events:SetScript("OnEvent", function(_, event, unit, a, b, c, d)
    if event == "UNIT_COMBAT" then
        onCombat(unit, a, b, c, d)
    elseif event == "PLAYER_TARGET_CHANGED" then
        counted, pendingBuilder = 0, nil
        -- DoTs stored under "target" (a secret GUID and no plate) belong to
        -- the target you just left.
        if byMob.target then
            byMob.target = nil
            if pendingCast and pendingCast.key == "target" then pendingCast = nil end
            changed()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        onFightOver()
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) ~= "string" or isSecret(unit) then return end
        -- A plate leaves when its mob dies: its DoTs end with it.
        if event == "NAME_PLATE_UNIT_REMOVED" then
            local dead = UnitIsDead(unit)
            local key = not isSecret(dead) and dead == true and Dots.KeyOf(unit)
            if key and byMob[key] then
                byMob[key] = nil
                if pendingCast and pendingCast.key == key then pendingCast = nil end
                changed(key)
            end
        end
        -- A plate token goes to the next mob that gets a plate, so DoTs kept
        -- under it (GUIDs hidden) were the mob it showed before.
        local key = byMob["plate:" .. unit] and "plate:" .. unit
        if key then
            byMob[key] = nil
            if pendingCast and pendingCast.key == key then pendingCast = nil end
            changed()
        end
    elseif isSecret(unit) or unit ~= "player" then
        return
    elseif event == "UNIT_POWER_FREQUENT" then
        if not isSecret(a) and a == "COMBO_POINTS" then onComboMoved() end
        return
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- (unit, target name, cast GUID, spell id)
        if not isSecret(b) and not isSecret(c) and type(c) == "number" then onSent(a, b, c) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, cast GUID, spell id)
        if not isSecret(a) and not isSecret(b) and type(b) == "number" then onCast(a, b) end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- (unit, cast GUID, spell id)
        if not isSecret(a) then onStopped(a) end
    end
end)

-- The combo points a finisher was cast with, for a buff whose length depends on
-- them (Slice and Dice). Asked from the same cast event, so it answers whether
-- this file has heard the cast yet or not. nil = not known.
function Dots.Combo(id)
    local f = lastFinisher
    if f and f.id == id and GetTime() - f.at < 1 then return f.points end
    return readCombo() or comboAtSend or (counted > 0 and counted or nil)
end

-- The Does It Die addon, when installed, can do the counting instead: its
-- public API hands out the same number (damage left on the mob behind a unit
-- token) and calls back when it changes. Players who trust its numbers can
-- keep them on Daylight UI's own bars and skull.
local SHOWS = { unitframes = true, nameplates = true } -- only these read Dots.Left

function Dots.Borrowable()
    local api = _G.DoesItDie
    return type(api) == "table" and type(api.GetRemainingDamage) == "function"
        and type(api.RegisterCallback) == "function" and type(api.UnregisterCallback) == "function"
end

local function useBorrowed()
    return Dots.Borrowable() and DUI:Get("Nameplates", "dotsDoesItDie") ~= false
end

local function onBorrowed(_, unit)
    changed(Dots.KeyOf(unit)) -- a plate whose mob can't be told apart gets nil: every one redraws
end

local wanted = {}
local listening = false

-- Decides who counts: Does It Die while it's wanted and allowed, else this
-- file. The Cooldown Manager still needs this file's combo point count.
local function apply()
    local any = next(wanted) ~= nil
    local api = any and useBorrowed() and _G.DoesItDie or nil
    if api ~= borrowed then
        if borrowed then DUI.SafeCall(borrowed.UnregisterCallback, "DaylightUI") end
        borrowed = api
        if api then DUI.SafeCall(api.RegisterCallback, "DaylightUI", onBorrowed) end
        changed()
    end
    local own = false
    for who in pairs(wanted) do
        if not (api and SHOWS[who]) then own = true end
    end
    if own == listening then return end
    listening = own
    if own then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        events:UnregisterEvent("UNIT_SPELLCAST_SENT")
        events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        events:UnregisterEvent("UNIT_SPELLCAST_FAILED")
        events:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        events:UnregisterEvent("PLAYER_TARGET_CHANGED")
        events:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        events:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Dots.Forget()
    end
end

-- who ("unitframes", "nameplates", "cdm") starts or stops needing DoTs. The
-- tracker only listens while someone does.
function Dots.Want(who, on)
    wanted[who] = on and true or nil
    apply()
end

-- Does It Die may load after the modules ask, and the switch can flip any time.
DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "DoesItDie" then apply() end
end)
DUI.On("SettingChanged", function(scope, path)
    if scope == "Nameplates" and path == "dotsDoesItDie" then apply() end
end)
