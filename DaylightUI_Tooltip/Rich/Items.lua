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
Items.AFTER_HEADER = 10
Items.TAG_GAP = 6       -- between the title and its tags
Items.ROW_GAP = 5       -- one rhythm for every row
Items.RULE_GAP = 8      -- each side of a rule
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

-- Cloth, leather, mail and plate each in a color of their own, so the armor
-- type reads at a glance: keyed by the item's armor subclass, not its word,
-- so it works in every language.
Items.ARMOR_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
Items.ARMOR_COLORS = {
    [1] = { 0.82, 0.68, 1.00 }, -- cloth, violet
    [2] = { 0.96, 0.68, 0.42 }, -- leather, amber
    [3] = { 0.46, 0.86, 0.78 }, -- mail, teal
    [4] = { 1.00, 0.85, 0.50 }, -- plate, gold
}

-- An armor tag's outline: its color, half toward the plain outline so the
-- word stays the brightest part.
function Items.ArmorEdge(c)
    local e = Style.BAND_LIT
    return { (c[1] + e[1]) / 2, (c[2] + e[2]) / 2, (c[3] + e[3]) / 2 }
end

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
        local _, kind, sub, equip, icon, class, subClass = C_Item.GetItemInfoInstant(link)
        kind, sub, equip, icon = plain(kind), plain(sub), plain(equip), plain(icon)
        if type(kind) == "string" and kind ~= "" then info.kind = kind end
        if type(sub) == "string" and sub ~= "" then info.sub = sub end
        -- A cloak counts as cloth but every class wears one: no color there.
        if plain(class) == Items.ARMOR_CLASS and equip ~= "INVTYPE_CLOAK" then
            info.armor = Items.ARMOR_COLORS[plain(subClass)]
        end
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

-- Every number on the card the way the game writes it, number first at the
-- left edge ("1,287 Armor", "+8 Stamina"): one column the eye runs down. The
-- number in the accent, or a stat's in its color, so it stands out from the
-- word in the sentence color. One from an Equip line says so after it, small.
local function popHex() return hex({ Style.Pop() }) end
local function numText(num, word, color) return (color and hex(color) or popHex()) .. num .. "|r " .. word end
local function numLine(p, num, word, color, equip)
    ns.RichPanel.Line(p, numText(num, word, color), Style.INK.TEXT, nil, equip and L["Equip"] or nil, Style.INK.GOOD)
end

-- Two base numbers that belong together share a line, as the game shows a
-- weapon's damage and speed: "46 - 86 Damage" on the left, "2.20 Speed" at
-- the right edge. A shield's armor and block go the same way.
local function pairLine(p, a, b)
    if not b then return numLine(p, a[1], a[2]) end
    ns.RichPanel.Row(p, numText(a[1], a[2]), numText(b[1], b[2]), Style.INK.TEXT, Style.INK.TEXT)
end

-- The game's binding lines and Unique: facts about the item itself, shown
-- as tags under its name (where the game puts them too).
local function isBadge(line, t)
    if line.type == (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemBinding or 20) then return true end
    for _, word in ipairs({ ITEM_SOULBOUND or "Soulbound", ITEM_BIND_ON_PICKUP or "Binds when picked up",
        ITEM_BIND_ON_EQUIP or "Binds when equipped", ITEM_BIND_ON_USE or "Binds when used", ITEM_BIND_QUEST or "Quest Item",
        ITEM_UNIQUE or "Unique", ITEM_UNIQUE_EQUIPPABLE or "Unique-Equipped", ITEM_ACCOUNTBOUND, ITEM_BNETACCOUNTBOUND }) do
        if type(word) == "string" and t == word then return true end
    end
    return false
end

-- A row from a line like "Speed 2.60": the words as its label, the number its value.
local function wordsAndNumber(t)
    local words, num = t:match("^(.-)%s*([%d][%d%.,]*)$")
    if words and words ~= "" then return words, num end
end

-- Sorts the item's own lines (2 to own) into the card's groups. Each group
-- is a list of functions that add their pieces; the footer's two sides are
-- returned as they are.
local function sort(n, lines, own, info, groups)
    local P, Tip, Tips = Items.Patterns(), ns.Tooltip, DUI.Tips
    local foot = {}
    local inSet = false
    local sellWord = type(SELL_PRICE) == "string" and SELL_PRICE or "Sell Price"
    local sellType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice or 11
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
            if not mine then groups.taken[i] = true end
            if right then
                foot.money = right
            elseif at then
                foot.money = (left:sub(at + #sellWord):gsub("^%s*:%s*", ""))
            end
        elseif not mine then
            -- Another addon's: drawn by Rich/Foreign.lua.
        elseif isBadge(line, t) then
            info.badges[#info.badges + 1] = t
        elseif info.slot and t == info.slot then
            -- Shown in the slot tag.
            info.slotWord = right and Items.Words(right) or nil
        elseif t:find(P.level) then
            -- Shown in the item level tag.
        elseif t:find(P.durability) then
            foot.durability = t
        elseif t:find(P.armor) then
            local armor = { t:match(P.armor), ARMOR or L["Armor"] }
            groups.armor = armor
            groups.list[#groups.list + 1] = function(p) pairLine(p, armor, armor.block) end
        elseif t:find(P.block) then
            local block = { t:match(P.block), BLOCK or L["Block"] }
            if groups.armor and not groups.armor.block then
                -- Drawn on the armor's line.
                groups.armor.block = block
            else
                groups.list[#groups.list + 1] = function(p) numLine(p, block[1], block[2]) end
            end
        elseif t:find(P.damage) then
            local lo, hi = t:match(P.damage)
            local damage = { string.format(L["%s - %s"], lo, hi), DAMAGE or L["Damage"] }
            local words, num = wordsAndNumber(right and Items.Words(right) or "")
            local speed = words and { num, words } or nil
            groups.list[#groups.list + 1] = function(p) pairLine(p, damage, speed) end
        elseif t:find(P.dps) then
            -- Kept in the game's own brackets: they set it apart from the
            -- damage and speed lines above it.
            local v = t:match(P.dps)
            groups.list[#groups.list + 1] = function(p)
                ns.RichPanel.Line(p, string.format(DPS_TEMPLATE or "(%s damage per second)",
                    popHex() .. v .. "|r"), Style.INK.TEXT)
            end
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
                        local color = Tip.StatColor(name) or Style.INK.GOOD
                        groups.list[#groups.list + 1] = function(p) numLine(p, num, name, color, true) end
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
            groups.list[#groups.list + 1] = function(p) numLine(p, num, name, color) end
        elseif ns.Rich.IsFlavor(line) then
            groups.quote[#groups.quote + 1] = function(p) ns.Rich.Flavor(p, line) end
        else
            -- Requirements, classes, anything else the game says: small, tan,
            -- a requirement you don't meet in red.
            local color = isRed(c) and Style.INK.BAD or Style.INK.LABEL
            local words = right and (t .. "  " .. Items.Words(right)) or t
            groups.facts[#groups.facts + 1] = function(p) ns.RichPanel.Text(p, words, color, Style.SIZE.small) end
        end
    end
    return foot
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
    local own = ns.Rich.Own(data, n)
    local groups = { list = {}, effects = {}, set = {}, facts = {}, quote = {}, taken = {} }
    info.badges = {}
    local foot = sort(n, lines, own, info, groups)
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
    if info.slot and info.armor and (info.slotWord or info.sub) then
        -- The slot and its armor type apart, the armor type in its color.
        tags[#tags + 1] = { info.slot, Style.INK.LABEL }
        tags[#tags + 1] = { info.slotWord or info.sub, info.armor, Items.ArmorEdge(info.armor) }
    elseif what then
        tags[#tags + 1] = { what, Style.INK.LABEL }
    end
    for _, badge in ipairs(info.badges) do tags[#tags + 1] = { badge, Style.INK.LABEL } end
    Panel.Header(p, { icon = info.icon, iconSize = Items.ICON, iconEdge = info.color,
        title = first and first.left or "", titleColor = titleColor, tags = tags, tagGap = Items.TAG_GAP,
        wash = info.color })
    Panel.Gap(p, Items.AFTER_HEADER)
    -- The card's parts, a rule between each that has something: the list of
    -- numbers, then everything said in words (effects, set, other facts, the
    -- quote last), then the foot. Inside a part, groups sit a small gap apart.
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
    -- Other addons' lines (Rich/Foreign.lua): their own area is the foot,
    -- first (a price), then durability and sell price; mixed in, they go with
    -- what the card says in words. An item's card keeps to two or three rules.
    -- Lines the card drew itself (a sell price, a compare's changes) aren't
    -- theirs.
    local Foreign, taken = ns.RichForeign, groups.taken
    if compare then
        for i in pairs(compare.skip) do taken[i] = true end
    end
    local mixed, other = {}, {}
    if Foreign.Has(p, "mixed", taken) then mixed[1] = function() Foreign.Place(p, "mixed", taken) end end
    if Foreign.Has(p, "own", taken) then other[1] = function() Foreign.Place(p, "own", taken) end end
    if foot.durability or foot.money then
        -- A sell price alone (a quest reward has no durability) says what it is.
        local label = foot.durability or (type(SELL_PRICE) == "string" and SELL_PRICE or L["Sell price"])
        other[#other + 1] = function()
            Panel.Row(p, label, foot.money, Style.INK.VALUE, Style.INK.LABEL, Style.SIZE.small, Style.SIZE.head)
        end
    end
    part(groups.list)
    part(groups.effects, groups.set, groups.facts, groups.quote, mixed)
    part(other)
    -- A compare's chips: what changes if you swap, last.
    if compare and #compare.chips > 0 then
        if any then Panel.Rule(p) end
        any = true
        Panel.Tags(p, compare.chips)
    end
    -- Nothing under the header: no room kept for it.
    if not any and p.items[p.count].kind == "gap" then p.count = p.count - 1 end
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
    local own = ns.Rich.Own(data, n)
    local chips, skip = Items.Changes(lines, own + 1, n)
    return Items.Card(p, tip, data, n, lines, light, fade, { label = label, chips = chips, skip = skip })
end
