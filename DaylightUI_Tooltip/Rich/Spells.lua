-- The rich card for a spell: its icon, name, school and rank, a strip of tiles
-- for cast time, cost and range (or cooldown), the description with its numbers
-- colored, and a hint that Shift shows the math. Holding Shift lays the same
-- card out as the math: the base amount, what spell power adds, damage per
-- second and per point of mana. Hovering an action button whose spell is
-- cooling down shows when it's ready instead, over a bar the client drains.
--
-- Everything is read from the tooltip's own lines (the game's words, in the
-- player's language). In a fight every line is secret: then the card is only
-- its frame around the game's own lines (Rich.Build), and there's no math.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local Spells = {}
ns.RichSpells = Spells

Spells.ICON = 36
Spells.ICON_GAP = 10
Spells.TAG_GAP = 4        -- between the title and its tags
Spells.PAD_TOP = 16
Spells.AFTER_HEADER = 12  -- the header, then the strip
Spells.AFTER_STRIP = 12   -- the strip, then the description
Spells.BEFORE_HINT = 10
Spells.BEFORE_FOOT = 10   -- the math's tiles, then its foot
Spells.COOLDOWN_PAD = 14
Spells.READY_GAP = 8      -- the cooldown card's title, then "Ready in"
Spells.BAR_GAP = 6
Spells.CHARGES_GAP = 12
Spells.TICK = 0.1         -- how often "Ready in" counts down

-- The classic rule for how much of your spell power a spell gets: its cast
-- time over 3.5 sec (never under the global cooldown's 1.5, never over 1),
-- a damage or heal over time its duration over 15 sec, a channel its length
-- over 3.5 sec, and half of that for a spell that hits an area.
Spells.GCD = 1.5
Spells.CAST_BASE = 3.5
Spells.OVER_TIME_BASE = 15
Spells.AREA = 0.5

-- Spells that don't follow the rule, by their first rank's id: every rank of
-- the same name takes the number. For a spell that hits and then burns on, the
-- number is for the hit.
Spells.OVERRIDES = {
    [116] = 0.814,    -- Frostbolt: its slow costs it a share
    [133] = 1.0,      -- Fireball: the small burn after it takes none
    [11366] = 1.0,    -- Pyroblast: the hit
    [348] = 0.2,      -- Immolate: the hit
    [8921] = 0.15,    -- Moonfire: the hit
    [15407] = 0.45,   -- Mind Flay: its slow costs it a share
}

-- The schools a description can name (the game's own words for them), each
-- with its index for GetSpellBonusDamage.
Spells.SCHOOLS = {
    { key = "Holy", global = "STRING_SCHOOL_HOLY", index = 2 },
    { key = "Fire", global = "STRING_SCHOOL_FIRE", index = 3 },
    { key = "Nature", global = "STRING_SCHOOL_NATURE", index = 4 },
    { key = "Frost", global = "STRING_SCHOOL_FROST", index = 5 },
    { key = "Shadow", global = "STRING_SCHOOL_SHADOW", index = 6 },
    { key = "Arcane", global = "STRING_SCHOOL_ARCANE", index = 7 },
}

-- The words a description uses for time and area. Only languages listed here
-- get the spell power and per second numbers: elsewhere the card can't tell a
-- hit from a burn and shows the base alone.
Spells.WORDS = {
    enUS = {
        over = { "over (%d+%.?%d*) sec" },
        lasting = { "for (%d+%.?%d*) sec" },
        every = { "every (%d+%.?%d*) sec", "each (%d+%.?%d*) sec" },
        everySecond = { "every second", "each second" },
        area = { "enemies", "nearby", "all targets", "party members", "raid members", "members of" },
    },
}

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

local function hex(c) return DUI.Win.Parts.Hex(c) end

-- A line's words alone: no color codes or inline icons, trimmed.
local function bare(t) return ns.RichItems.Words(t) end

local function words()
    local W = Spells.WORDS
    return W[DUI.LOCALE] or (DUI.LOCALE == "enGB" and W.enUS) or nil
end

-- ---------------------------------------------------------------------
-- Reading the game's lines
-- ---------------------------------------------------------------------

-- The game's own line formats as whole-line patterns, made once (English
-- when the client has none, as in the tests).
local pats
function Spells.Patterns()
    if pats then return pats end
    local function whole(fmt) return "^" .. DUI.GamePattern(fmt) .. "$" end
    local function word(w, fallback) return type(w) == "string" and w ~= "" and w or fallback end
    pats = {
        cast = whole(SPELL_CAST_TIME_SEC or "%s sec cast"),
        castMin = whole(SPELL_CAST_TIME_MIN or "%s min cast"),
        range = whole(SPELL_RANGE or "%s yd range"),
        cooldown = whole(SPELL_RECAST_TIME_SEC or "%s sec cooldown"),
        cooldownMin = whole(SPELL_RECAST_TIME_MIN or "%s min cooldown"),
        cooldownHours = whole(SPELL_RECAST_TIME_HOURS or "%s hrs cooldown"),
        remaining = whole(ITEM_COOLDOWN_TIME or "Cooldown remaining: %s"),
        instant = { word(SPELL_CAST_TIME_INSTANT, "Instant"), word(SPELL_CAST_TIME_INSTANT_NO_MANA, "Instant cast") },
        channeled = word(SPELL_CAST_CHANNELED, "Channeled"),
        nextMelee = word(SPELL_ON_NEXT_SWING, "Next melee"),
        passive = word(SPELL_PASSIVE, "Passive"),
        melee = word(MELEE_RANGE, "Melee Range"),
    }
    return pats
end

local function isIn(t, list)
    for _, w in ipairs(list) do if t == w then return true end end
    return false
end

-- What one side of a line is: "cast", "cost", "range", "cooldown" or nil, and
-- what goes in its tile.
function Spells.Side(t)
    local P, Tips = Spells.Patterns(), DUI.Tips
    if isIn(t, P.instant) or t == P.nextMelee or t == P.passive then return "cast", t, "instant" end
    if t == P.channeled then return "cast", t, "channeled" end
    local n = t:match(P.cast)
    if n then return "cast", string.format(L["%s sec"], n), "cast", tonumber(n) end
    n = t:match(P.castMin)
    if n then return "cast", string.format(L["%s min"], n), "cast", (tonumber(n) or 0) * 60 end
    n = t:match(P.cooldown)
    if n then return "cooldown", string.format(L["%s sec"], n) end
    n = t:match(P.cooldownMin)
    if n then return "cooldown", string.format(L["%s min"], n) end
    n = t:match(P.cooldownHours)
    if n then return "cooldown", string.format(L["%s hr"], n) end
    n = t:match(P.range)
    if n then return "range", string.format(L["%s yd"], n) end
    if t == P.melee then return "range", L["Melee"] end
    if #t <= DUI.Tips.SHORT_LINE and t:find("%d") then
        local power = Tips.PowerIn(t)
        if power then return "cost", t, power end
    end
end

local DESC_TYPE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SpellDescription or 34

-- Sorts the spell's own lines (2 to own) into what the card shows. Lines past
-- own are other addons' (and the Spell ID line).
function Spells.Read(n, lines, own)
    local Tips, P = DUI.Tips, Spells.Patterns()
    local first = lines[1]
    local r = { title = first and first.left or "", desc = {}, facts = {} }
    if first and first.right then r.rank = bare(first.right) end
    for i = 2, n do
        local line = lines[i]
        if i > own then
            -- Another addon's (or the Spell ID line): Rich/Foreign.lua's.
        else
            for _, side in ipairs({ "left", "right" }) do
                local t = line[side] and bare(line[side])
                local c
                if side == "left" and line.hasLC then c = line.lc end
                if side == "right" and line.hasRC then c = line.rc end
                local kind = c and Tips.GameColor(c[1], c[2], c[3]) or nil
                if t and t ~= "" then
                    local what, value, extra, secs = Spells.Side(t)
                    if kind == "yellow" or (side == "left" and line.type == DESC_TYPE) then
                        r.desc[#r.desc + 1] = t
                    elseif kind == "red" then
                        r.facts[#r.facts + 1] = { t, Style.INK.BAD }
                    elseif what == "cast" then
                        r.cast, r.castKind, r.castSecs = value, extra, secs
                    elseif what == "cost" then
                        r.cost, r.power = value, extra
                    elseif what and not r[what] then
                        r[what] = value
                    elseif t:find(P.remaining) then
                        r.facts[#r.facts + 1] = { t, Style.INK.WARN }
                    elseif kind == "white" and #t > Tips.SHORT_LINE then
                        -- An aura's sentence is white.
                        r.desc[#r.desc + 1] = t
                    elseif kind == "white" or kind == nil then
                        r.facts[#r.facts + 1] = { t, Style.INK.LABEL }
                    else
                        r.facts[#r.facts + 1] = { t, { c[1], c[2], c[3] } }
                    end
                end
            end
        end
    end
    return r
end

-- The school a description names first, as { key, word, index, color }, or nil.
function Spells.School(text)
    if type(text) ~= "string" then return nil end
    local low = text:lower()
    local best, at
    for _, s in ipairs(Spells.SCHOOLS) do
        local w = _G[s.global]
        if type(w) ~= "string" or w == "" then w = s.key end
        local from = low:find(w:lower(), 1, true)
        if from and (not at or from < at) then best, at = { key = s.key, word = w, index = s.index }, from end
    end
    if best then best.color = ns.Tooltip.SCHOOL_COLORS[best.key] end
    return best
end

-- ---------------------------------------------------------------------
-- The math
-- ---------------------------------------------------------------------

local function num(s) return tonumber((s:gsub(",", ""))) end

local function firstMatch(text, list)
    if not list then return nil end
    for _, p in ipairs(list) do
        local v = text:match(p)
        if v then return tonumber(v) end
    end
end

local function hasAny(text, list)
    if not list then return false end
    for _, w in ipairs(list) do if text:find(w, 1, true) then return true end end
    return false
end

-- The amounts a description names (each a number or a range followed by a
-- damage word, or after a heal word), in order: { lo, hi }. Returns them and
-- whether the first is a heal.
function Spells.Amounts(text)
    local Tips = DUI.Tips
    local W = Tips.WORDS[DUI.LOCALE] or Tips.WORDS.enUS
    local low = text:lower()
    local dmg = W.damage
    if type(_G.DAMAGE) == "string" then dmg = { _G.DAMAGE:lower(), unpack(W.damage) } end
    local heal
    local out = {}
    local from = 1
    while true do
        local s, e, a = low:find("(%d[%d,]*%.?%d*)", from)
        if not s then break end
        local lo, hi, stop = num(a), nil, e
        for _, link in ipairs(W.link) do
            local b = low:sub(e + 1):match("^%s*" .. link:gsub("%-", "%%-") .. "%s*(%d[%d,]*)")
            if b then
                hi = num(b)
                stop = e + #low:sub(e + 1):match("^%s*" .. link:gsub("%-", "%%-") .. "%s*%d[%d,]*")
                break
            end
        end
        -- "Heals the target of 45 damage over 15 sec" is a heal: the heal word
        -- before the first amount says so, whatever word follows it.
        local before = (low:sub(1, s - 1):match("[^%.;]*$") or "")
        local healing = hasAny(before, W.heal)
        local isAmount = healing or hasAny(low:sub(stop + 1):match("^[^%.;,]*") or "", dmg)
        if isAmount and lo then
            if heal == nil then heal = healing end
            out[#out + 1] = { lo = lo, hi = hi or lo }
        end
        from = stop + 1
    end
    return out, heal == true
end

-- How a spell does its work, read from its description and cast line:
-- amount (lo, hi), heal, shape ("direct", "over", "channel", "hybrid"),
-- secs (how long it takes), area. nil when there's no amount.
function Spells.Shape(r)
    local text = table.concat(r.desc, " ")
    if text == "" then return nil end
    local amounts, heal = Spells.Amounts(text)
    if #amounts == 0 then return nil end
    local W = words()
    local low = text:lower()
    local a = amounts[1]
    local shape = { lo = a.lo, hi = a.hi, heal = heal, known = W ~= nil }
    if not W then return shape end
    local over = firstMatch(low, W.over)
    local every = firstMatch(low, W.every) or (hasAny(low, W.everySecond) and 1 or nil)
    local lasting = firstMatch(low, W.lasting)
    shape.area = hasAny(low, W.area)
    if r.castKind == "channeled" then
        shape.kind = "channel"
        shape.secs = over or lasting
        if every and shape.secs then shape.ticks = math.floor(shape.secs / every + 0.5) end
    elseif #amounts > 1 and (over or every) then
        shape.kind = "hybrid"
    elseif over then
        shape.kind, shape.secs = "over", over
    elseif every and lasting then
        shape.kind, shape.secs = "over", lasting
        shape.ticks = math.floor(lasting / every + 0.5)
    else
        shape.kind = "direct"
        shape.secs = math.max(r.castSecs or 0, Spells.GCD)
    end
    return shape
end

-- The localized name each override's first rank has, made once.
local overrideNames
local function override(id)
    if Spells.OVERRIDES[id] then return Spells.OVERRIDES[id] end
    if not overrideNames then
        overrideNames = {}
        local get = C_Spell and C_Spell.GetSpellName
        if type(get) == "function" then
            for first, k in pairs(Spells.OVERRIDES) do
                local name = plain(get(first))
                if type(name) == "string" and name ~= "" then overrideNames[name] = k end
            end
        end
    end
    local get = C_Spell and C_Spell.GetSpellName
    local name = type(get) == "function" and plain(get(id)) or nil
    return type(name) == "string" and overrideNames[name] or nil
end

-- The share of spell power a spell gets, or nil when it isn't known.
function Spells.Coefficient(id, shape, castSecs)
    local o = type(id) == "number" and override(id) or nil
    if o then return o end
    if not shape.known or shape.kind == "hybrid" then return nil end
    local k
    if shape.kind == "channel" then
        if not shape.secs then return nil end
        k = shape.secs / Spells.CAST_BASE
    elseif shape.kind == "over" then
        k = shape.secs / Spells.OVER_TIME_BASE
    else
        k = math.min(math.max(castSecs or 0, Spells.GCD), Spells.CAST_BASE) / Spells.CAST_BASE
    end
    if shape.area then k = k * Spells.AREA end
    return k
end

-- The player's spell power for this spell (healing power for a heal), plain or nil.
function Spells.Power(shape, school)
    if shape.heal then
        return type(GetSpellBonusHealing) == "function" and plain(GetSpellBonusHealing()) or nil
    end
    if not (school and type(GetSpellBonusDamage) == "function") then return nil end
    return plain(GetSpellBonusDamage(school.index))
end

-- The cast time in seconds: the client's own number when it has one.
local function castSecs(id, r)
    if r.castKind ~= "cast" then return r.castKind == "instant" and 0 or nil end
    local info = type(id) == "number" and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    local ms = type(info) == "table" and plain(info.castTime) or nil
    if type(ms) == "number" and ms > 0 then return ms / 1000 end
    return r.castSecs
end

-- The spell's first cost (amount and power token), plain or nil.
local function costOf(id)
    local get = C_Spell and C_Spell.GetSpellPowerCost
    local costs = type(id) == "number" and type(get) == "function" and get(id) or nil
    local c = type(costs) == "table" and costs[1]
    if type(c) ~= "table" then return nil end
    local amount, token = plain(c.cost), plain(c.name)
    if type(amount) == "number" and amount > 0 then return amount, token end
end

local function short(v)
    if v >= 100 then return string.format("%d", math.floor(v + 0.5)) end
    return string.format("%.1f", v)
end

-- Everything the math view shows: base text, coefficient and bonus, per
-- second and per power, the kind word. nil when the description names no amount.
function Spells.Math(id, r, school)
    local shape = Spells.Shape(r)
    if not shape then return nil end
    local m = { shape = shape }
    m.base = shape.lo == shape.hi and short(shape.lo) or string.format(L["%s to %s"], short(shape.lo), short(shape.hi))
    local secs = castSecs(id, r)
    if shape.kind == "direct" then shape.secs = math.max(secs or 0, Spells.GCD) end
    m.coefficient = Spells.Coefficient(id, shape, secs)
    local power = m.coefficient and Spells.Power(shape, school)
    if type(power) == "number" then m.bonus = math.floor(power * m.coefficient + 0.5) end
    -- Per second and per mana only when the whole amount is known.
    if m.bonus and shape.kind ~= "hybrid" and shape.secs and shape.secs > 0 then
        local each = (shape.lo + shape.hi) / 2 * (shape.ticks or 1)
        local total = each + m.bonus
        m.perSec = short(total / shape.secs)
        local cost, token = costOf(id)
        if cost then
            m.perPower = short(total / cost)
            m.powerToken = token
        end
    end
    local kinds = {
        direct = (secs or 0) > 0 and L["Bolt"] or L["Instant"],
        over = L["Over time"], channel = L["Channel"], hybrid = L["Hit and over time"],
    }
    m.kind = shape.known and kinds[shape.kind] or nil
    if shape.heal and shape.kind == "direct" then m.kind = L["Heal"] end
    if m.kind and shape.area then m.kind = string.format(L["%s · %s"], L["Area"], m.kind) end
    return m
end

-- ---------------------------------------------------------------------
-- The cooldown on an action button
-- ---------------------------------------------------------------------

-- The action slot a tooltip's owner shows, or nil.
local function slotOf(tip)
    local owner = tip.GetOwner and tip:GetOwner()
    local slot = type(owner) == "table" and owner.action or nil
    if type(slot) ~= "number" or isSecret(slot) then return nil end
    local AB = C_ActionBar
    if not (AB and type(AB.HasAction) == "function" and plain(AB.HasAction(slot)) == true) then return nil end
    return slot
end

-- When the hovered action button's spell is ready again: { ends, duration,
-- charges, most }, or nil when it isn't cooling down (the global cooldown
-- alone doesn't count) or the client keeps it secret.
function Spells.Cooldown(tip)
    local slot = slotOf(tip)
    local AB = C_ActionBar
    if not (slot and type(AB.GetActionCooldown) == "function") then return nil end
    local cd = {}
    local ch = type(AB.GetActionCharges) == "function" and AB.GetActionCharges(slot) or nil
    if type(ch) == "table" then
        local now, most = plain(ch.currentCharges), plain(ch.maxCharges)
        if type(now) == "number" and type(most) == "number" and most > 1 then
            cd.charges, cd.most = now, most
            if now < most then
                local s, d = plain(ch.cooldownStartTime), plain(ch.cooldownDuration)
                if type(s) == "number" and type(d) == "number" and d > 0 then
                    cd.ends = s + d
                    cd.duration = type(AB.GetActionChargeDuration) == "function" and AB.GetActionChargeDuration(slot) or nil
                end
            end
        end
    end
    local info = AB.GetActionCooldown(slot)
    if type(info) == "table" then
        local active, gcd = plain(info.isActive), plain(info.isOnGCD)
        local s, d = plain(info.startTime), plain(info.duration)
        if active == true and gcd ~= true and type(s) == "number" and type(d) == "number" and d > 0 then
            -- Out of charges: the cooldown itself is the wait.
            cd.ends = s + d
            local get = AB.GetActionCooldownDuration
            cd.duration = type(get) == "function" and get(slot, true) or nil
        end
    end
    if not cd.ends or cd.ends <= GetTime() then return nil end
    return cd
end

-- "4.2 sec", "12 sec", "1:30", "2 hr".
function Spells.Time(secs)
    if secs < 10 then return string.format(L["%.1f sec"], secs) end
    if secs < 60 then return string.format(L["%d sec"], math.ceil(secs)) end
    if secs < 3600 then return string.format(L["%d:%02d"], math.floor(secs / 60), math.floor(secs % 60)) end
    return string.format(L["%d hr"], math.floor(secs / 3600 + 0.5))
end

-- Counts "Ready in" down (from the tooltip's update, every Spells.TICK).
-- Returns true when the wait is over: the card is built again.
function Spells.Tick(p, sp)
    local now = GetTime()
    if now < (sp.nextTick or 0) then return false end
    sp.nextTick = now + Spells.TICK
    local left = sp.ends - now
    if left <= 0 then return true end
    if p.ready then p.ready:SetText(Spells.Time(left)) end
    return false
end

-- ---------------------------------------------------------------------
-- The cards
-- ---------------------------------------------------------------------

-- Whether a data's lines are a spell's: a spell, an aura, or a macro casting
-- a spell (a macro using an item has the item's lines).
function Spells.Is(data)
    local E = Enum and Enum.TooltipDataType
    local t = type(data) == "table" and plain(data.type) or nil
    if not (E and t) then return false end
    if t == E.Spell or t == E.UnitAura then return true end
    return t == E.Macro and ns.Tooltip.HasSpellLines(type(data.lines) == "table" and data.lines or nil)
end

local function spellId(data)
    local E = Enum and Enum.TooltipDataType
    local t = type(data) == "table" and plain(data.type) or nil
    if not (E and t) or t == E.Macro then return nil end
    local id = plain(data.id)
    return type(id) == "number" and id or nil
end

local function iconOf(tip, id)
    if id and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local tex = plain(C_Spell.GetSpellTexture(id))
        if tex then return tex end
    end
    local slot = slotOf(tip)
    local get = slot and C_ActionBar.GetActionTexture
    if type(get) == "function" then return plain(get(slot)) end
end

-- The top light: the school's color to its dark end.
function Spells.Light(school)
    if not (school and school.color) then return nil end
    local lo, hi = DUI.Gradients.PairFrom(school.color)
    return { hi, lo }
end

-- Whether the math view is wanted: Shift held over a spell that has math.
function Spells.WantsMath(sp)
    return sp ~= nil and sp.canMath == true and IsShiftKeyDown() == true
end

local function spellPower(shape)
    return shape.heal and L["Healing power"] or L["Spell power"]
end

-- The math view (board "Shift held").
function Spells.MathCard(p, r, m, school, id, light)
    local Panel, INK, SIZE = ns.RichPanel, Style.INK, Style.SIZE
    Panel.Begin(p, "spell", light)
    p.padTop = Spells.PAD_TOP
    Panel.Line(p, r.title, INK.TITLE, SIZE.head, string.format(L["· %s"], L["the math"]), INK.LABEL, SIZE.small)
    Panel.Rule(p)
    Panel.Row(p, L["Base"], m.base, INK.VALUE, INK.LABEL, SIZE.small)
    if m.bonus then
        local share = string.format(L["(%d%%)"], math.floor(m.coefficient * 100 + 0.5))
        Panel.Row(p, spellPower(m.shape) .. " " .. hex(INK.OFF) .. share .. "|r", "+" .. m.bonus, INK.GOOD,
            INK.LABEL, SIZE.small)
    end
    local tiles = {}
    local color = m.shape.heal and INK.GOOD or (school and school.color) or nil
    if not color then
        local cr, cg, cb = Style.Accent()
        color = { cr, cg, cb }
    end
    if m.perSec then
        tiles[#tiles + 1] = { m.perSec, m.shape.heal and L["Healing / sec"] or L["Damage / sec"], color }
    end
    if m.perPower then
        local token = m.powerToken
        local word = token == "MANA" and L["Per mana"]
            or string.format(L["Per %s"], string.lower(type(_G[token or ""]) == "string" and _G[token] or tostring(token)))
        tiles[#tiles + 1] = { m.perPower, word, color }
    end
    if #tiles > 0 then
        Panel.Rule(p)
        Panel.Tiles(p, tiles)
    end
    local foot = {}
    if school then foot[#foot + 1] = school.word end
    if m.kind then foot[#foot + 1] = m.kind end
    if id or #foot > 0 then
        Panel.Gap(p, Spells.BEFORE_FOOT)
        Panel.Row(p, id and string.format("%s %d", ns.Tooltip.SPELL_ID, id) or "", table.concat(foot, L[" · "]),
            INK.OFF, INK.OFF, SIZE.small)
    end
    Panel.Finish(p)
end

-- The cooldown card (board "On cooldown").
function Spells.CooldownCard(p, r, cd)
    local Panel, INK, SIZE = ns.RichPanel, Style.INK, Style.SIZE
    local lo, hi = DUI.Gradients.PairFrom(INK.WARN)
    Panel.Begin(p, "cooldown", { hi, lo })
    p.padTop, p.padX = Spells.COOLDOWN_PAD, Spells.COOLDOWN_PAD
    Panel.Line(p, r.title, INK.TITLE, SIZE.head)
    Panel.Gap(p, Spells.READY_GAP)
    Panel.Row(p, L["Ready in"], Spells.Time(math.max(0, cd.ends - GetTime())), INK.WARN)
    p.ready = p.items[p.count].value
    if type(cd.duration) ~= "nil" then
        Panel.Gap(p, Spells.BAR_GAP)
        Panel.Bar(p, { duration = cd.duration, pair = { lo, hi }, h = 4 })
    end
    if cd.most then
        Panel.Gap(p, Spells.CHARGES_GAP)
        Panel.Row(p, L["Charges"], cd.charges .. " " .. hex(INK.LABEL) .. string.format(L["/ %d"], cd.most) .. "|r",
            INK.VALUE)
    end
    Panel.Finish(p)
end

-- The spell card (board "The strip").
function Spells.Card(p, tip, r, lines, school, id, light, hasMath)
    local Panel, INK, SIZE, Tips = ns.RichPanel, Style.INK, Style.SIZE, DUI.Tips
    Panel.Begin(p, "spell", light)
    p.padTop = Spells.PAD_TOP
    local tags = {}
    if school then tags[#tags + 1] = { school.word, school.color } end
    if r.rank and r.rank ~= "" then tags[#tags + 1] = { r.rank, INK.LABEL } end
    Panel.Header(p, { icon = iconOf(tip, id), iconSize = Spells.ICON, iconGap = Spells.ICON_GAP,
        title = r.title, tags = #tags > 0 and tags or nil, tagGap = Spells.TAG_GAP })
    local tiles = {}
    if r.cast then tiles[#tiles + 1] = { r.cast, L["Cast"] } end
    if r.cost then tiles[#tiles + 1] = { r.cost, L["Cost"], { Style.PowerColor(r.power) } } end
    if r.cooldown then
        tiles[#tiles + 1] = { r.cooldown, L["Cooldown"] }
    elseif r.range then
        tiles[#tiles + 1] = { r.range, L["Range"] }
    end
    if #tiles > 0 then
        Panel.Gap(p, Spells.AFTER_HEADER)
        Panel.Tiles(p, tiles)
    end
    local numbers = school and school.color or nil
    for i, t in ipairs(r.desc) do
        if i == 1 then Panel.Gap(p, Spells.AFTER_STRIP) end
        Panel.Text(p, Tips.Numbers(t, numbers), INK.TEXT)
    end
    for _, f in ipairs(r.facts) do Panel.Text(p, f[1], f[2], SIZE.small) end
    ns.RichForeign.Place(p, "mixed")
    ns.RichForeign.Place(p, "own")
    if hasMath then
        Panel.Gap(p, Spells.BEFORE_HINT)
        Panel.Hints(p, { { SHIFT_KEY_TEXT or L["Shift"], L["the math"], school and school.color or nil } })
    end
    Panel.Finish(p)
end

-- Builds a spell's card: the cooldown card while its action button cools
-- down, the math while Shift is held, else the card. Returns what the
-- tooltip's update needs to know ({ canMath, math, ends }).
function Spells.Build(p, tip, data, n, lines)
    local own = ns.Rich.Own(data, n)
    p.ready = nil
    local r = Spells.Read(n, lines, own)
    local school = Spells.School(table.concat(r.desc, " "))
    local id = spellId(data)
    local light = Spells.Light(school) or ns.Rich.Light(tip, data, "spell")
    local E = Enum and Enum.TooltipDataType
    local isSpell = E and type(data) == "table" and plain(data.type) == E.Spell
    local m = isSpell and tip == GameTooltip and Spells.Math(id, r, school) or nil
    local sp = { canMath = m ~= nil }
    local cd = tip == GameTooltip and Spells.Cooldown(tip) or nil
    if Spells.WantsMath(sp) then
        sp.math = true
        Spells.MathCard(p, r, m, school, id, light)
    elseif cd then
        sp.ends = cd.ends
        Spells.CooldownCard(p, r, cd)
    else
        Spells.Card(p, tip, r, lines, school, id, light, m ~= nil)
    end
    return sp
end
