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
Spells.SECTION_GAP = 4    -- a recipe's reagents heading, then its rows
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

-- ---------------------------------------------------------------------
-- A profession's recipe: "Reagents:" and "Tools:" lines
-- ---------------------------------------------------------------------

-- The word before the colon in one of the game's strings ("Reagents: |n"
-- gives "Reagents"), in the player's language, or the English fallback.
local function wordOf(global, fallback)
    local g = _G[global]
    if type(g) == "string" then
        local w = g:match("^%s*(.-)%s*:") or g:match("^%s*(.-)%s*\239\188\154")
        if w and w ~= "" then return w end
    end
    return fallback
end

function Spells.RecipeWords()
    return wordOf("SPELL_REAGENTS", L["Reagents"]), wordOf("SPELL_TOTEMS", L["Tools"])
end

-- What follows "Word:" at the start of a line (the colon may be a full-width
-- one), or nil when the line doesn't start with it. Line breaks and spaces
-- right after the colon are dropped, so "Reagents:|nSoul Dust (6)" and a
-- "Reagents:" line alone (its list on the next line) both read.
function Spells.After(t, w)
    if type(t) ~= "string" or t:sub(1, #w) ~= w then return nil end
    local rest = t:sub(#w + 1):gsub("^%s+", "")
    local cut = rest:match("^:(.*)") or rest:match("^\239\188\154(.*)")
    if not cut then return nil end
    cut = cut:gsub("^[%s]+", ""):gsub("^|n", ""):gsub("^[%s]+", "")
    return cut
end

-- "Soul Dust (6), |cffff2020Pyrite|r (4)" as { { name, need, short } }: short
-- when the game painted that part red (not enough in the bags).
function Spells.ReagentList(raw)
    local out = {}
    for part in (raw .. ","):gmatch("(.-),") do
        local words = bare(part)
        if words ~= "" then
            local name, need = words:match("^(.-)%s*%((%d+)%)$")
            local c = part:match("|c%x%x(%x%x%x%x%x%x)")
            local red = c ~= nil and DUI.Tips.GameColor(tonumber(c:sub(1, 2), 16) / 255,
                tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255) == "red"
            out[#out + 1] = { name = name or words, need = tonumber(need) or 1, short = red }
        end
    end
    return out
end

-- Takes the reagent and tool lines out of a spell's own lines into r.reagents
-- and r.tools, and marks which lines they were (r.taken). A "Reagents:" line
-- on its own has its list on the next line.
function Spells.ReadRecipe(r, lines, own)
    local reagentWord, toolWord = Spells.RecipeWords()
    r.taken = {}
    local i = 2
    while i <= own do
        local line = lines[i]
        local raw = line and line.left
        local t = type(raw) == "string" and raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
        local list = t and Spells.After(t, reagentWord)
        if list then
            r.taken[i] = true
            local at, len = raw:find(":", 1, true), 1
            if not at then at, len = raw:find("\239\188\154", 1, true), 3 end
            local rawList = at and raw:sub(at + len) or raw
            if list == "" and lines[i + 1] and i + 1 <= own and type(lines[i + 1].left) == "string" then
                i = i + 1
                r.taken[i] = true
                rawList = lines[i].left
            end
            rawList = rawList:gsub("^%s*|n", "")
            r.reagents = Spells.ReagentList(rawList)
        else
            local tools = t and Spells.After(t, toolWord)
            if tools then
                r.taken[i] = true
                local c = line.hasLC and line.lc or nil
                local red = c and DUI.Tips.GameColor(c[1], c[2], c[3]) == "red"
                r.tools = r.tools or {}
                for name in (tools .. ","):gmatch("%s*(.-)%s*,") do
                    if name ~= "" then r.tools[#r.tools + 1] = { name = name, short = red } end
                end
            end
        end
        i = i + 1
    end
end

-- Sorts the spell's own lines (2 to own) into what the card shows. Lines past
-- own are other addons' (and the Spell ID line).
function Spells.Read(n, lines, own)
    local Tips, P = DUI.Tips, Spells.Patterns()
    local first = lines[1]
    local r = { title = first and first.left or "", desc = {}, facts = {} }
    if first and first.right then r.rank = bare(first.right) end
    Spells.ReadRecipe(r, lines, own)
    for i = 2, n do
        local line = lines[i]
        if i > own or r.taken[i] then
            -- Another addon's (or the Spell ID line): Rich/Foreign.lua's.
            -- A recipe's reagents and tools have their own part.
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

local function escape(w) return (w:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- The school a description names first, as { key, word, color }, or nil.
-- Whole words first, so "fires a volley ... Arcane damage" is Arcane. Languages
-- that join the school onto the damage word ("Feuerschaden") fall back to
-- finding it inside a word; English never needs that.
function Spells.School(text)
    if type(text) ~= "string" then return nil end
    local low = text:lower()
    local function first(whole)
        local best, at
        for _, s in ipairs(Spells.SCHOOLS) do
            local w = _G[s.global]
            if type(w) ~= "string" or w == "" then w = s.key end
            local lw = w:lower()
            local from
            if whole then from = low:find("%f[%w]" .. escape(lw) .. "%f[%W]")
            else from = low:find(lw, 1, true) end
            if from and (not at or from < at) then best, at = { key = s.key, word = w }, from end
        end
        return best
    end
    local best = first(true)
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    if not best and not tostring(locale):find("^en") then best = first(false) end
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

-- "Enchanting: Enchant Weapon - Recovery" as the profession's name, its color
-- and the recipe's own name, when the part before the colon is one of the
-- game's recipe kinds (its own words, every language). Else nil.
function Spells.Profession(title)
    if type(title) ~= "string" then return nil end
    local prof, rest = title:match("^(.-):%s*(.+)$")
    if not prof or prof == "" then return nil end
    local Items = ns.RichItems
    local get = C_Item and C_Item.GetItemSubClassInfo
    if type(get) ~= "function" then return nil end
    for sub in pairs(Items.RECIPE_COLORS) do
        local name = plain(get(Items.RECIPE_CLASS, sub))
        if name == prof then return prof, Items.RECIPE_COLORS[sub], rest end
    end
end

-- An item's icon (else the question mark), its color by quality and its id,
-- by id or, for a name, only when the client already knows it.
local UNKNOWN_ICON = 134400
local function itemLook(item)
    local I, Tip = C_Item, ns.Tooltip
    if not (I and item) then return UNKNOWN_ICON, Style.INK.VALUE end
    local id, icon
    if type(I.GetItemInfoInstant) == "function" then
        local a, _, _, _, e = I.GetItemInfoInstant(item)
        id, icon = plain(a), plain(e)
    end
    local q = type(I.GetItemQualityByID) == "function" and plain(I.GetItemQualityByID(item)) or nil
    local r, g, b = Tip.QualityColor(q)
    return icon or UNKNOWN_ICON, r and { r, g, b } or Style.INK.VALUE, id
end

-- The reagents with their items: the recipe's own list from the client
-- (C_TradeSkillUI) when it names as many as the line, so each has its icon
-- even when the item isn't loaded yet; else the line's names.
function Spells.Reagents(id, list)
    local TS = C_TradeSkillUI
    local s = id and TS and type(TS.GetRecipeSchematic) == "function" and TS.GetRecipeSchematic(id, false) or nil
    local slots = type(s) == "table" and type(s.reagentSlotSchematics) == "table" and s.reagentSlotSchematics or nil
    local ids = {}
    for _, slot in ipairs(slots or {}) do
        local first = type(slot.reagents) == "table" and slot.reagents[1]
        local itemID = type(first) == "table" and plain(first.itemID)
        if type(itemID) == "number" and slot.required ~= false and slot.hiddenInCraftingForm ~= true then
            ids[#ids + 1] = itemID
        end
    end
    local out = {}
    for i, m in ipairs(list) do
        local key = #ids == #list and ids[i] or m.name
        local icon, color, itemID = itemLook(key)
        out[i] = { name = m.name, need = m.need, short = m.short, icon = icon, color = color,
            itemID = type(key) == "number" and key or itemID }
    end
    return out
end

local function iconText(icon)
    return "|T" .. icon .. ":0:0:0:0:64:64:5:59:5:59|t "
end

-- How many the recipe needs, popped; with fewer in the bags (but some), what
-- you have first in red: "2 / 6". Red too when the game said so.
function Spells.Need(m)
    local INK = Style.INK
    local have
    if m.itemID and C_Item and type(C_Item.GetItemCount) == "function" then
        have = plain(C_Item.GetItemCount(m.itemID))
    end
    if m.short and not (type(have) == "number" and have > 0) then return tostring(m.need), INK.BAD end
    if type(have) == "number" and have > 0 and have < m.need then
        return hex(INK.BAD) .. have .. "|r" .. hex(INK.LABEL) .. " / |r" .. m.need, { Style.Pop() }
    end
    return tostring(m.need), { Style.Pop() }
end

-- The recipe's part: its reagents under their heading, one row each (icon,
-- name in its quality color, the count), then the tools it needs.
function Spells.RecipeRows(p, r, id)
    local Panel, INK, SIZE = ns.RichPanel, Style.INK, Style.SIZE
    local word = Spells.RecipeWords()
    if r.reagents then
        Panel.Section(p, word)
        Panel.Gap(p, Spells.SECTION_GAP)
    end
    for _, m in ipairs(Spells.Reagents(id, r.reagents or {})) do
        local need, c = Spells.Need(m)
        Panel.Row(p, iconText(m.icon) .. m.name, need, c, m.color)
    end
    for _, t in ipairs(r.tools or {}) do
        local icon, color = itemLook(t.name)
        Panel.Row(p, iconText(icon) .. t.name, L["Tool"], t.short and INK.BAD or INK.LABEL,
            t.short and INK.BAD or color, nil, SIZE.small)
    end
end

-- The spell card (board "The strip").
function Spells.Card(p, tip, r, lines, school, id, light, cd)
    local Panel, INK, SIZE, Tips = ns.RichPanel, Style.INK, Style.SIZE, DUI.Tips
    Panel.Begin(p, "spell", light)
    p.padTop = Spells.PAD_TOP
    local tags = {}
    local Tag = ns.RichItems.Tag
    local recipe = r.reagents or r.tools
    local title = r.title
    -- A recipe's profession is a tag, the title its own name.
    local prof, profColor, rest
    if recipe then prof, profColor, rest = Spells.Profession(r.title) end
    if prof then
        tags[#tags + 1] = Tag(prof, profColor)
        title = rest
    end
    if school and Panel.Wants("tags.spell.school") then tags[#tags + 1] = Tag(school.word, school.color or INK.TEXT) end
    if r.rank and r.rank ~= "" and Panel.Wants("tags.spell.rank") then tags[#tags + 1] = Tag(r.rank, { Style.Pop() }) end
    Panel.Header(p, { icon = iconOf(tip, id), iconSize = Spells.ICON, iconGap = Spells.ICON_GAP,
        title = title, tags = #tags > 0 and tags or nil, tagGap = Spells.TAG_GAP })
    local tiles = {}
    if r.cast then tiles[#tiles + 1] = { r.cast, L["Cast"] } end
    if r.cost then tiles[#tiles + 1] = { r.cost, L["Cost"], { Style.PowerColor(r.power) } } end
    if r.cooldown then
        tiles[#tiles + 1] = { r.cooldown, L["Cooldown"] }
    elseif r.range then
        tiles[#tiles + 1] = { r.range, L["Range"] }
    end
    -- Its pieces, in the player's order (Rich/Layout.lua).
    local numbers = school and school.color or nil
    local pieces = {
        tiles = { has = #tiles > 0, draw = function() Panel.Tiles(p, tiles) end },
        cooldown = { has = cd ~= nil, draw = function() Spells.CooldownRows(p, cd) end },
        desc = { has = #r.desc > 0, draw = function()
            for _, t in ipairs(r.desc) do Panel.Text(p, Tips.Numbers(t, numbers), INK.TEXT) end
        end },
        reagents = { has = recipe and true or false, draw = function() Spells.RecipeRows(p, r, id) end },
        facts = { has = #r.facts > 0, draw = function()
            for _, f in ipairs(r.facts) do Panel.Text(p, f[1], f[2], SIZE.small) end
        end },
        addons = ns.RichForeign.Part(p, "spell"),
    }
    ns.RichLayout.Run(p, "spell", pieces)
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
