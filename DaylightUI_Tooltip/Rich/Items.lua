-- The rich card for an item: its icon in a quality outline and glow, the name
-- in its quality color with item level and slot tags, the base rows (armor,
-- damage), its stats one to a line, effects as sentences, its set, anything
-- else the game says, then durability and sell price at the foot and the keys
-- that do something for it. A compare tooltip gets a small card instead: what
-- you have on, and chips for what changes if you swap.
--
-- Everything is read from the tooltip's own lines (the game's words, in the
-- player's language), so another addon's lines after them land in the card
-- too, after a rule.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local Items = {}
ns.RichItems = Items

Items.ICON = 44
Items.PAD_TOP = 16
Items.AFTER_HEADER = 12
Items.TAG_GAP = 6       -- between the title and its tags
Items.ROW_GAP = 3
Items.RULE_GAP = 13     -- a rule's 10 px each side plus the rows' own 3
Items.EPIC = 4          -- the quality light sweeps from here up
Items.AFTER_TAG = 8     -- a compare card's Equipped tag, then the header
Items.MIN_QUALITY = 2   -- uncommon and up: the name, light and outline in its color
Items.GROUP_GAP = 8     -- between two groups that share a part (no rule)

-- A loss shows a real minus sign; these fonts have none, so they keep "-".
Items.MINUS = "\226\136\146"
Items.NO_MINUS = { "MPLUSRounded", "PressStart2P", "RussoOne", "SquadaOne" }

-- English stat names short enough for a chip (the game's delta lines are
-- whole words). Other languages keep the game's.
Items.SHORT = {
    Strength = "Str", Stamina = "Sta", Agility = "Agi", Intellect = "Int", Spirit = "Spi",
    ["Critical Strike"] = "Crit", ["Attack Power"] = "AP", ["Spell Power"] = "SP",
}

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

local function hex(c) return DUI.Win.Parts.Hex(c) end

-- A quality color's light end, as the top light starts and the name shows.
function Items.Lift(c)
    return { math.min(1, c[1] * 1.15 + 0.1), math.min(1, c[2] * 1.15 + 0.1), math.min(1, c[3] * 1.15 + 0.1) }
end

-- What the card needs from the item itself: quality and its colors, item
-- level, slot and kind words, icon. Empty for no link.
function Items.Info(link)
    local Tip = ns.Tooltip
    local info = {}
    if type(link) ~= "string" then return info end
    info.quality = Tip.Quality(link)
    if info.quality and info.quality >= Items.MIN_QUALITY then
        local r, g, b = Tip.QualityColor(info.quality)
        if r then
            info.color = { r, g, b }
            info.light = Items.Lift(info.color)
        end
    end
    info.level = Tip.ItemLevel(link)
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local _, kind, sub, equip, icon = C_Item.GetItemInfoInstant(link)
        kind, sub, equip, icon = plain(kind), plain(sub), plain(equip), plain(icon)
        if type(kind) == "string" and kind ~= "" then info.kind = kind end
        if type(sub) == "string" and sub ~= "" then info.sub = sub end
        if type(equip) == "string" and equip ~= "" and not DUI.NO_LEVEL[equip] then
            info.equip = equip
            local slot = _G[equip]
            if type(slot) == "string" and slot ~= "" then info.slot = slot end
        end
        info.icon = icon
    end
    return info
end

-- ---------------------------------------------------------------------
-- Reading the game's lines
-- ---------------------------------------------------------------------

-- The game's own line formats as whole-line patterns, made once (English
-- when the client has none, as in the tests).
local pats
function Items.Patterns()
    if pats then return pats end
    local function whole(fmt) return "^" .. DUI.GamePattern(fmt) .. "$" end
    pats = {
        armor = whole(ARMOR_TEMPLATE or "%s Armor"),
        block = whole(SHIELD_BLOCK_TEMPLATE or "%d Block"),
        damage = whole(DAMAGE_TEMPLATE or "%s - %s Damage"),
        dps = whole(DPS_TEMPLATE or "(%s damage per second)"),
        durability = whole(DURABILITY_TEMPLATE or "Durability %d / %d"),
        setName = whole(ITEM_SET_NAME or "%s (%d/%d)"),
        setOn = whole(ITEM_SET_BONUS or "Set: %s"),
        setOff = whole(ITEM_SET_BONUS_GRAY or "(%d) Set: %s"),
        level = whole(ITEM_LEVEL or "Item Level %d"),
    }
    return pats
end

-- A line's words alone: no color codes or inline icons, trimmed. A leading
-- minus stays (Rich.Bare drops a quest objective's dash).
function Items.Words(t)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return (t:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isGreen(c) return c and c[1] < 0.3 and c[2] > 0.85 and c[3] < 0.3 end
local function isRed(c) return c and DUI.Tips.GameColor(c[1], c[2], c[3]) == "red" end
local function lineColor(line) return line.hasLC and line.lc or nil end

-- "+24 Strength": its number and name, or nil.
function Items.Stat(t)
    local num, name = t:match("^([%+%-]%d[%d,%.]*%%?) (.+)$")
    return num, name
end

-- The effect triggers the game starts a green line with.
local function trigger(t)
    for _, word in ipairs({ ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:", ITEM_SPELL_TRIGGER_ONUSE or "Use:",
        ITEM_SPELL_TRIGGER_ONPROC or "Chance on hit:" }) do
        if type(word) == "string" and t:sub(1, #word) == word then return word, (t:sub(#word + 1):gsub("^%s+", "")) end
    end
end

-- A stat line in the card's look: the number in its stat's color, the name
-- in the sentence color, and a smaller tail after it when given ("from Equip").
local function statLine(p, num, name, color, tail)
    local Panel = ns.RichPanel
    Panel.Line(p, hex(color) .. num .. "|r " .. name, Style.INK.TEXT, nil,
        tail and string.format(L["· %s"], tail) or nil, Style.INK.LABEL)
end

-- A row from a line like "Speed 2.60": the words as its label, the number its value.
local function wordsAndNumber(t)
    local words, num = t:match("^(.-)%s*([%d][%d%.,]*)$")
    if words and words ~= "" then return words, num end
end

-- Sorts the item's own lines (2 to own) into the card's groups. Each group
-- is a list of functions that add their pieces; the footer's two sides are
-- returned as they are.
local function sort(n, lines, own, info, groups, skip)
    local P, Tip, Tips = Items.Patterns(), ns.Tooltip, DUI.Tips
    local foot = {}
    local inSet = false
    local sellWord = type(SELL_PRICE) == "string" and SELL_PRICE or "Sell Price"
    local sellType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice or 11
    local ownWord = L["from Equip"]
    for i = 2, n do
        local line = lines[i]
        local left, right = line.left, line.right
        local t = left and Items.Words(left) or nil
        local c = lineColor(line)
        local mine = i <= own
        if not t or t == "" then
            -- A blank line ends a set's piece list.
            inSet = false
        elseif line.type == sellType or t:sub(1, #sellWord) == sellWord then
            -- The sell price (the game's or a quest reward's, added after).
            -- Another addon may have rewritten it with the coins on the right
            -- ("Vendor price"), so they're taken from there when it has them.
            local at = left:find(sellWord, 1, true)
            if right then
                foot.money = right
            elseif at then
                foot.money = (left:sub(at + #sellWord):gsub("^%s*:%s*", ""))
            end
        elseif not mine then
            if not (skip and skip[i]) then groups.other[#groups.other + 1] = i end
        elseif info.slot and t == info.slot then
            -- Shown in the slot tag.
            info.slotWord = right and Items.Words(right) or nil
        elseif t:find(P.level) then
            -- Shown in the item level tag.
        elseif t:find(P.durability) then
            foot.durability = t
        elseif t:find(P.armor) then
            local v = t:match(P.armor)
            groups.base[#groups.base + 1] = function(p) ns.RichPanel.Row(p, ARMOR or L["Armor"], v) end
        elseif t:find(P.block) then
            local v = t:match(P.block)
            groups.base[#groups.base + 1] = function(p) ns.RichPanel.Row(p, BLOCK or L["Block"], v) end
        elseif t:find(P.damage) then
            local lo, hi = t:match(P.damage)
            groups.base[#groups.base + 1] = function(p)
                ns.RichPanel.Row(p, DAMAGE or L["Damage"], string.format(L["%s - %s"], lo, hi))
            end
            local words, num = wordsAndNumber(right and Items.Words(right) or "")
            if words then
                groups.base[#groups.base + 1] = function(p) ns.RichPanel.Row(p, words, num) end
            end
        elseif t:find(P.dps) then
            local v = t:match(P.dps)
            groups.base[#groups.base + 1] = function(p) ns.RichPanel.Row(p, L["Damage per second"], v) end
        elseif t:find(P.setName) then
            local name, have, total = t:match(P.setName)
            inSet = true
            groups.set[#groups.set + 1] = function(p)
                local r, g, b = Style.Accent()
                ns.RichPanel.Line(p, Style.Upper(name) .. " " .. hex({ r, g, b }) .. have .. "/" .. total .. "|r",
                    Style.INK.LABEL, Style.SIZE.small)
            end
        elseif t:find(P.setOff) then
            local count, text = t:match(P.setOff)
            inSet = false
            local words = Tip.ShortText(text) or text
            groups.set[#groups.set + 1] = function(p)
                ns.RichPanel.Text(p, string.format(L["(%s) %s"], count, words), Style.INK.OFF, Style.SIZE.small)
            end
        elseif t:find(P.setOn) then
            local text = t:match(P.setOn)
            inSet = false
            local words = Tip.ShortText(text) or text
            groups.set[#groups.set + 1] = function(p) ns.RichPanel.Text(p, words, Style.INK.GOOD, Style.SIZE.small) end
        elseif inSet then
            -- One of the set's pieces: the count says how many you have.
        elseif isGreen(c) or trigger(t) then
            local word, rest = trigger(t)
            local short = word == (ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:") and Tip.ShortText(rest) or nil
            if short then
                for part in (short .. "\n"):gmatch("(.-)\n") do
                    local num, name = Items.Stat(part)
                    if num then
                        groups.stats[#groups.stats + 1] = function(p) statLine(p, num, name, Style.INK.GOOD, ownWord) end
                    end
                end
            elseif word then
                groups.effects[#groups.effects + 1] = function(p)
                    ns.RichPanel.Text(p, hex(Style.INK.GOOD) .. word .. "|r " .. Tips.Numbers(rest), Style.INK.TEXT)
                end
            else
                groups.effects[#groups.effects + 1] = function(p) ns.RichPanel.Text(p, Tips.Numbers(t), Style.INK.GOOD) end
            end
        elseif Items.Stat(t) and not right and not isRed(c) then
            local num, name = Items.Stat(t)
            local color = Tip.StatColor(name) or (num:sub(1, 1) == "-" and Style.INK.DAMAGE) or Style.INK.VALUE
            groups.stats[#groups.stats + 1] = function(p) statLine(p, num, name, color) end
        else
            -- Binding, unique, requirements, classes, flavor text: small, tan,
            -- a requirement you don't meet in red.
            local color = isRed(c) and Style.INK.BAD or Style.INK.LABEL
            local words = right and (t .. "  " .. Items.Words(right)) or t
            groups.facts[#groups.facts + 1] = function(p) ns.RichPanel.Text(p, words, color, Style.SIZE.small) end
        end
    end
    return foot
end

-- The keys that do something for this item: Shift shows what you have on
-- (unless the game always does), Ctrl tries it on.
function Items.Hints(tip, link, info)
    local hints = {}
    if tip ~= GameTooltip or type(link) ~= "string" then return hints end
    local always = C_CVar and type(C_CVar.GetCVarBool) == "function" and plain(C_CVar.GetCVarBool("alwaysCompareItems"))
    if info.equip and always ~= true then
        hints[#hints + 1] = { SHIFT_KEY_TEXT or L["Shift"], L["compare all"] }
    end
    local dress = C_Item and C_Item.IsDressableItemByID
    if type(dress) == "function" and plain(dress(link)) == true then
        hints[#hints + 1] = { CTRL_KEY_TEXT or L["Ctrl"], L["try it on"] }
    end
    return hints
end

-- The item card. compare (a compare tooltip's): { label, chips, skip }: the
-- same card under its "Equipped" tag, the game's change lines as chips at the
-- bottom (skip: their line numbers), so the two read across line for line.
function Items.Card(p, tip, data, n, lines, light, fade, compare)
    local Panel, Tip = ns.RichPanel, ns.Tooltip
    local link = Tip.ItemLink(tip, data)
    local info = Items.Info(link)
    Panel.Begin(p, compare and "compare" or "item", light, fade)
    p.padTop, p.rowGap, p.ruleGap = Items.PAD_TOP, Items.ROW_GAP, Items.RULE_GAP
    p.washDown = true
    local first = lines[1]
    local own = type(data) == "table" and type(data.lines) == "table" and #data.lines or n
    local groups = { base = {}, stats = {}, effects = {}, set = {}, facts = {}, other = {} }
    local foot = sort(n, lines, math.min(own, n), info, groups, compare and compare.skip)
    if compare then
        Panel.Tags(p, { { compare.label, Style.INK.LABEL } })
        Panel.Gap(p, Items.AFTER_TAG)
    end
    -- The header.
    local titleColor = info.light
    if not titleColor and first and first.hasLC then
        local c = first.lc
        local kind = DUI.Tips.GameColor(c[1], c[2], c[3])
        if kind ~= "white" and kind ~= "yellow" then titleColor = { c[1], c[2], c[3] } end
    end
    local tags = {}
    if info.level then
        tags[#tags + 1] = { string.format(L["ilvl %d"], math.floor(info.level + 0.5)), info.light or Style.INK.LABEL }
    end
    local what
    if info.slot then
        local word = info.slotWord or info.sub
        what = word and word ~= info.slot and string.format(L["%s · %s"], info.slot, word) or info.slot
    elseif info.kind then
        what = info.sub and info.sub ~= info.kind and string.format(L["%s · %s"], info.kind, info.sub) or info.kind
    end
    if what then tags[#tags + 1] = { what, Style.INK.LABEL } end
    Panel.Header(p, { icon = info.icon, iconSize = Items.ICON, iconEdge = info.color,
        title = first and first.left or "", titleColor = titleColor, tags = tags, tagGap = Items.TAG_GAP,
        wash = info.color })
    Panel.Gap(p, Items.AFTER_HEADER)
    -- The card's parts, a rule between each that has something: the base
    -- rows, what it does, its set, and the foot. Inside a part, groups sit a
    -- small gap apart.
    local any = false
    local function part(...)
        local first = true
        for g = 1, select("#", ...) do
            local list = select(g, ...)
            if #list > 0 then
                if first and any then Panel.Rule(p) elseif not first then Panel.Gap(p, Items.GROUP_GAP) end
                first, any = false, true
                for _, add in ipairs(list) do add(p) end
            end
        end
    end
    -- What it does: its stats and effects, then the other facts (binding,
    -- requirements) in small tan lines.
    for _, add in ipairs(groups.effects) do groups.stats[#groups.stats + 1] = add end
    -- The foot: other addons' lines (a price), then durability and sell price.
    local other = {}
    for _, i in ipairs(groups.other) do other[#other + 1] = function() ns.Rich.Lines(p, i, lines, i) end end
    if foot.durability or foot.money then
        -- A sell price alone (a quest reward has no durability) says what it is.
        local label = foot.durability or (type(SELL_PRICE) == "string" and SELL_PRICE or L["Sell price"])
        other[#other + 1] = function()
            Panel.Row(p, label, foot.money, Style.INK.VALUE, Style.INK.LABEL, Style.SIZE.small)
        end
    end
    part(groups.base)
    part(groups.stats, groups.facts)
    part(groups.set)
    part(other)
    -- A compare's chips: what changes if you swap, last.
    if compare and #compare.chips > 0 then
        if any then Panel.Rule(p) end
        any = true
        Panel.Tags(p, compare.chips)
    end
    local hints = Items.Hints(tip, link, info)
    if #hints > 0 then
        if any then Panel.Gap(p, Items.GROUP_GAP) end
        Panel.Hints(p, hints)
    end
    -- Nothing under the header: no room kept for it.
    if not any and #hints == 0 and p.items[p.count].kind == "gap" then p.count = p.count - 1 end
    Panel.Finish(p)
    return info
end

-- ---------------------------------------------------------------------
-- The compare card
-- ---------------------------------------------------------------------

-- The minus for a loss in the tooltip's font.
function Items.Minus()
    local font = ns.MEDIA and ns.MEDIA.font
    local file = font and Style.FontFile(font)
    if type(file) == "string" then
        for _, name in ipairs(Items.NO_MINUS) do
            if file:find(name, 1, true) then return "-" end
        end
    end
    return Items.MINUS
end

-- One of the game's stat change lines ("+8 Strength", "-96 Armor") as a
-- chip: its text and color, or nil when it isn't one.
function Items.Chip(text)
    local t = Items.Words(text)
    local sign, num, name = t:match("^([%+%-])%s*(%d[%d,%.]*%%?)%s+(.+)$")
    if not sign then return nil end
    name = Items.SHORT[name] or name
    if sign == "-" then return Items.Minus() .. num .. " " .. name, Style.INK.DAMAGE end
    return "+" .. num .. " " .. name, Style.INK.GOOD
end

-- The game's "If you replace this item, the following stat changes will
-- occur:" line (or its both-hands form).
function Items.IsChangeHead(t)
    return t ~= nil and (t == ITEM_DELTA_DESCRIPTION or t == ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION)
end

-- A compare tooltip's change block: the game adds a blank line, its "If you
-- replace this item" line and one line per change after the item's own (and
-- after any other addon's). Returns the chips and the lines they took.
function Items.Changes(lines, from, n)
    local chips, skip, changes = {}, {}, false
    for i = from, n do
        local line = lines[i]
        local t = line.left and Items.Words(line.left) or nil
        if Items.IsChangeHead(t) then
            changes, skip[i] = true, true
        elseif changes and t and t ~= "" and not line.right then
            local text, color = Items.Chip(t)
            if text then
                chips[#chips + 1] = { text, color }
                skip[i] = true
            end
        end
    end
    return chips, skip
end

-- Builds a tooltip's item card; on a compare tooltip, the same card under
-- its "Equipped" tag with the changes at the bottom. Returns what it read of
-- the item.
function Items.Build(p, tip, data, n, lines, light, fade)
    local h = tip.CompareHeader
    if type(h) ~= "table" then return Items.Card(p, tip, data, n, lines, light, fade) end
    local label = type(h.Label) == "table" and plain(h.Label:GetText())
    if type(label) ~= "string" or label == "" then label = EQUIPPED or L["Equipped"] end
    local own = type(data) == "table" and type(data.lines) == "table" and math.min(#data.lines, n) or n
    local chips, skip = Items.Changes(lines, own + 1, n)
    return Items.Card(p, tip, data, n, lines, light, fade, { label = label, chips = chips, skip = skip })
end
