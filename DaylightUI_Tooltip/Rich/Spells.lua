-- The rich card for a spell: its icon, name, school and rank, a strip of tiles
-- for cast time, cost and range (or cooldown), the description with its numbers
-- colored. Hovering an action button whose spell is cooling down adds when
-- it's ready under the strip, over a bar the client drains.
--
-- Everything is read from the tooltip's own lines (the game's words, in the
-- player's language). In a fight every line is secret: then the card is only
-- its frame around the game's own lines (Rich.Build).

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
Spells.BAR_GAP = 6
Spells.CHARGES_GAP = 12
Spells.TICK = 0.1         -- how often "Ready in" counts down

-- The schools a description can name (the game's own words for them).
Spells.SCHOOLS = {
    { key = "Holy", global = "STRING_SCHOOL_HOLY" },
    { key = "Fire", global = "STRING_SCHOOL_FIRE" },
    { key = "Nature", global = "STRING_SCHOOL_NATURE" },
    { key = "Frost", global = "STRING_SCHOOL_FROST" },
    { key = "Shadow", global = "STRING_SCHOOL_SHADOW" },
    { key = "Arcane", global = "STRING_SCHOOL_ARCANE" },
}

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

local function hex(c) return DUI.Win.Parts.Hex(c) end

-- A line's words alone: no color codes or inline icons, trimmed.
local function bare(t) return ns.RichItems.Words(t) end

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

-- The school a description names first, as { key, word, color }, or nil.
function Spells.School(text)
    if type(text) ~= "string" then return nil end
    local low = text:lower()
    local best, at
    for _, s in ipairs(Spells.SCHOOLS) do
        local w = _G[s.global]
        if type(w) ~= "string" or w == "" then w = s.key end
        local from = low:find(w:lower(), 1, true)
        if from and (not at or from < at) then best, at = { key = s.key, word = w }, from end
    end
    if best then best.color = ns.Tooltip.SCHOOL_COLORS[best.key] end
    return best
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

-- While the action button cools down: when it's ready again over a bar the
-- client drains, and its charges, under the strip. The card keeps everything
-- else it says, so a spell on cooldown can still be read.
function Spells.CooldownRows(p, cd)
    local Panel, INK = ns.RichPanel, Style.INK
    local lo, hi = DUI.Gradients.PairFrom(INK.WARN)
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
end

-- The spell card (board "The strip").
function Spells.Card(p, tip, r, lines, school, id, light, cd)
    local Panel, INK, SIZE, Tips = ns.RichPanel, Style.INK, Style.SIZE, DUI.Tips
    Panel.Begin(p, "spell", light)
    p.padTop = Spells.PAD_TOP
    local tags = {}
    local Tag = ns.RichItems.Tag
    if school then tags[#tags + 1] = Tag(school.word, school.color or INK.TEXT) end
    if r.rank and r.rank ~= "" then tags[#tags + 1] = Tag(r.rank, { Style.Pop() }) end
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
    if cd then
        Panel.Gap(p, Spells.AFTER_HEADER)
        Spells.CooldownRows(p, cd)
    end
    local numbers = school and school.color or nil
    for i, t in ipairs(r.desc) do
        if i == 1 then Panel.Gap(p, Spells.AFTER_STRIP) end
        Panel.Text(p, Tips.Numbers(t, numbers), INK.TEXT)
    end
    for _, f in ipairs(r.facts) do Panel.Text(p, f[1], f[2], SIZE.small) end
    ns.RichForeign.Place(p, "mixed")
    ns.RichForeign.Place(p, "own")
    Panel.Finish(p)
end

-- Builds a spell's card, with when it's ready while its action button cools
-- down. Returns what the tooltip's update needs to know ({ ends }).
function Spells.Build(p, tip, data, n, lines)
    local own = ns.Rich.Own(data, n)
    p.ready = nil
    local r = Spells.Read(n, lines, own)
    local school = Spells.School(table.concat(r.desc, " "))
    local id = spellId(data)
    local light = Spells.Light(school) or ns.Rich.Light(tip, data, "spell")
    local sp = {}
    local cd = tip == GameTooltip and Spells.Cooldown(tip) or nil
    if cd then sp.ends = cd.ends end
    Spells.Card(p, tip, r, lines, school, id, light, cd)
    return sp
end
