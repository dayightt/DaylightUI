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

-- Every other tag reads its color from what it says, by the item's class
-- and subclass ids (every language): a recipe in its profession's color, a
-- weapon's type apart from an armor's, the slot by where it goes.
Items.WEAPON_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
Items.RECIPE_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Recipe or 9
Items.QUEST_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12
Items.WEAPON_COLOR = { 1.00, 0.62, 0.50 }
Items.CLASS_COLORS = {
    [0] = { 0.58, 0.90, 0.58 },  -- consumable, green
    [1] = { 0.86, 0.70, 0.52 },  -- container, leather brown
    [2] = Items.WEAPON_COLOR,
    [3] = { 0.98, 0.62, 0.86 },  -- gem, pink
    [4] = { 1.00, 0.72, 0.68 },  -- armor, rose
    [5] = { 0.78, 0.72, 1.00 },  -- reagent, lavender
    [6] = { 0.92, 0.80, 0.60 },  -- projectile, sand
    [7] = { 0.54, 0.80, 1.00 },  -- trade goods, sky
    [8] = { 0.56, 0.94, 0.86 },  -- enhancement, mint
    [9] = { 1.00, 0.84, 0.56 },  -- recipe, parchment
    [11] = { 0.86, 0.70, 0.52 }, -- quiver, as a container
    [12] = { 1.00, 0.82, 0.30 }, -- quest, the quest gold
    [13] = { 0.96, 0.80, 0.42 }, -- key, brass
    [15] = { 0.88, 0.80, 0.96 }, -- miscellaneous, lilac
    [16] = { 0.62, 0.74, 1.00 }, -- glyph, ink blue
    [17] = { 0.80, 0.92, 0.62 }, -- battle pet, leaf
    [19] = { 0.98, 0.78, 0.36 }, -- profession tool, brass
    [20] = { 0.96, 0.74, 0.56 }, -- housing, terracotta
}
-- A recipe's profession.
Items.RECIPE_COLORS = {
    [1] = { 0.96, 0.68, 0.42 },  -- leatherworking
    [2] = { 0.94, 0.64, 0.88 },  -- tailoring
    [3] = { 0.98, 0.78, 0.36 },  -- engineering
    [4] = { 1.00, 0.56, 0.40 },  -- blacksmithing
    [5] = { 1.00, 0.86, 0.52 },  -- cooking
    [6] = { 0.58, 0.92, 0.52 },  -- alchemy
    [7] = { 1.00, 0.58, 0.60 },  -- first aid
    [8] = { 0.76, 0.62, 1.00 },  -- enchanting
    [9] = { 0.50, 0.78, 1.00 },  -- fishing
    [10] = { 0.52, 0.92, 0.94 }, -- jewelcrafting
    [11] = { 0.62, 0.74, 1.00 }, -- inscription
}
-- Where it goes: weapons, jewelry, worn armor, anything else.
Items.SLOT_WEAPON = { 0.66, 0.80, 1.00 }
Items.SLOT_JEWELRY = { 0.98, 0.62, 0.86 }
Items.SLOT_ARMOR = { 1.00, 0.72, 0.68 }
Items.SLOT_OTHER = { 0.92, 0.84, 0.66 }
Items.SLOT_COLORS = {
    INVTYPE_WEAPON = Items.SLOT_WEAPON, INVTYPE_2HWEAPON = Items.SLOT_WEAPON,
    INVTYPE_WEAPONMAINHAND = Items.SLOT_WEAPON, INVTYPE_WEAPONOFFHAND = Items.SLOT_WEAPON,
    INVTYPE_RANGED = Items.SLOT_WEAPON, INVTYPE_RANGEDRIGHT = Items.SLOT_WEAPON,
    INVTYPE_THROWN = Items.SLOT_WEAPON, INVTYPE_SHIELD = Items.SLOT_WEAPON, INVTYPE_HOLDABLE = Items.SLOT_WEAPON,
    INVTYPE_NECK = Items.SLOT_JEWELRY, INVTYPE_FINGER = Items.SLOT_JEWELRY, INVTYPE_TRINKET = Items.SLOT_JEWELRY,
    INVTYPE_HEAD = Items.SLOT_ARMOR, INVTYPE_SHOULDER = Items.SLOT_ARMOR, INVTYPE_CHEST = Items.SLOT_ARMOR,
    INVTYPE_ROBE = Items.SLOT_ARMOR, INVTYPE_WAIST = Items.SLOT_ARMOR, INVTYPE_LEGS = Items.SLOT_ARMOR,
    INVTYPE_FEET = Items.SLOT_ARMOR, INVTYPE_WRIST = Items.SLOT_ARMOR, INVTYPE_HAND = Items.SLOT_ARMOR,
    INVTYPE_CLOAK = Items.SLOT_ARMOR,
}

-- Binding and Unique tags: bound to you, binds as you pick it up, free to
-- trade until worn or used, shared across the account, one of a kind.
Items.BIND_YOURS = { 0.72, 0.74, 1.00 }
Items.BIND_PICKUP = { 1.00, 0.64, 0.58 }
Items.BIND_TRADE = { 0.58, 0.92, 0.62 }
Items.BIND_USE = { 0.98, 0.84, 0.50 }
Items.BIND_ACCOUNT = { 0.50, 0.86, 1.00 }
local badgeInk
function Items.BadgeColor(t)
    if not badgeInk then
        badgeInk = {}
        local function put(word, c) if type(word) == "string" and word ~= "" then badgeInk[word] = c end end
        put(ITEM_SOULBOUND or "Soulbound", Items.BIND_YOURS)
        put(ITEM_BIND_ON_PICKUP or "Binds when picked up", Items.BIND_PICKUP)
        put(ITEM_BIND_ON_EQUIP or "Binds when equipped", Items.BIND_TRADE)
        put(ITEM_BIND_ON_USE or "Binds when used", Items.BIND_USE)
        put(ITEM_BIND_QUEST or "Quest Item", Items.CLASS_COLORS[12])
        put(ITEM_ACCOUNTBOUND, Items.BIND_ACCOUNT)
        put(ITEM_BNETACCOUNTBOUND, Items.BIND_ACCOUNT)
        put(ITEM_BIND_TO_ACCOUNT, Items.BIND_ACCOUNT)
        put(ITEM_BIND_TO_BNETACCOUNT, Items.BIND_ACCOUNT)
    end
    if badgeInk[t] then return badgeInk[t] end
    -- "Unique", "Unique-Equipped", "Unique (5)": all one of a kind.
    local unique = ITEM_UNIQUE or "Unique"
    if t:sub(1, #unique) == unique then return Style.INK.MONEY end
    return Items.BIND_YOURS
end

function Items.HasBadge(info, word)
    for _, badge in ipairs(info.badges or {}) do
        if badge == word then return true end
    end
    return false
end

-- A colored tag's outline: its color, half toward the plain outline so the
-- word stays the brightest part.
function Items.TagEdge(c)
    local e = Style.BAND_LIT
    return { (c[1] + e[1]) / 2, (c[2] + e[2]) / 2, (c[3] + e[3]) / 2 }
end

-- A tag in its color, the outline tinted to match.
function Items.Tag(text, c)
    return { text, c, Items.TagEdge(c) }
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
        class, subClass = plain(class), plain(subClass)
        info.class = class
        if class == Items.ARMOR_CLASS and equip ~= "INVTYPE_CLOAK" then
            info.armor = Items.ARMOR_COLORS[subClass]
        end
        info.kindColor = Items.CLASS_COLORS[class] or Style.INK.VALUE
        if class == Items.RECIPE_CLASS then
            info.subColor = Items.RECIPE_COLORS[subClass]
        elseif class == Items.WEAPON_CLASS then
            info.subColor = Items.WEAPON_COLOR
        end
        info.slotColor = type(equip) == "string" and Items.SLOT_COLORS[equip] or Items.SLOT_OTHER
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
    -- The same durability line, also giving where its first number starts.
    pats.wear = pats.durability:gsub("%(%%d%+%)", "()(%%d+)", 1)
    return pats
end

-- The durability line with its current number colored by how worn the item
-- is (the same shades as the info panel's durability), so worn gear shows at
-- a glance. A line that doesn't read as two numbers stays as it is.
function Items.WearText(t)
    local at, cur, max = t:match(Items.Patterns().wear)
    local have, most = tonumber(cur), tonumber(max)
    if not (at and have and most and most > 0) then return t end
    local color = DUI.Tips.Wear(have / most * 100)
    return t:sub(1, at - 1) .. hex(color) .. cur .. "|r" .. t:sub(at + #cur)
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

-- "+24 Strength": its number, name and color (nil when unknown), or nil.
-- Read by the game's own stat formats, so it works in every language.
function Items.Stat(t)
    return ns.Tooltip.ReadStat(t)
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
-- word in the sentence color. A stat from an Equip line reads like any other.
local function popHex() return hex({ Style.Pop() }) end
local function numText(num, word, color) return (color and hex(color) or popHex()) .. num .. "|r " .. word end
local function numLine(p, num, word, color)
    ns.RichPanel.Line(p, numText(num, word, color), Style.INK.TEXT)
end

-- "31.5 damage per second" from the game's own words, its brackets off, the
-- number in the accent. A language that puts the number later keeps its order.
function Items.DpsWords(v)
    local words = (DPS_TEMPLATE or "(%s damage per second)"):gsub("^%s*%(", ""):gsub("%)%s*$", "")
    return function() return (words:gsub("%%s", function() return popHex() .. v .. "|r" end, 1)) end
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
local uniqueCounts
local function isBadge(line, t)
    if line.type == (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemBinding or 20) then return true end
    for _, word in ipairs({ ITEM_SOULBOUND or "Soulbound", ITEM_BIND_ON_PICKUP or "Binds when picked up",
        ITEM_BIND_ON_EQUIP or "Binds when equipped", ITEM_BIND_ON_USE or "Binds when used", ITEM_BIND_QUEST or "Quest Item",
        ITEM_UNIQUE or "Unique", ITEM_UNIQUE_EQUIPPABLE or "Unique-Equipped", ITEM_ACCOUNTBOUND, ITEM_BNETACCOUNTBOUND }) do
        if type(word) == "string" and t == word then return true end
    end
    -- "Unique (5)", "Unique-Equipped: Gems (3)": one of a kind with a count.
    if not uniqueCounts then
        uniqueCounts = {}
        for _, fmt in ipairs({ ITEM_UNIQUE_MULTIPLE or "Unique (%d)", ITEM_LIMIT_CATEGORY or "Unique: %s (%d)",
            ITEM_LIMIT_CATEGORY_MULTIPLE or "Unique-Equipped: %s (%d)" }) do
            if type(fmt) == "string" then uniqueCounts[#uniqueCounts + 1] = "^" .. DUI.GamePattern(fmt) .. "$" end
        end
    end
    for _, pattern in ipairs(uniqueCounts) do
        if t:find(pattern) then return true end
    end
    return false
end

-- A row from a line like "Speed 2.60": the words as its label, the number its value.
local function wordsAndNumber(t)
    local words, num = t:match("^(.-)%s*([%d][%d%.,]*)$")
    if words and words ~= "" then return words, num end
end

-- A recipe's tooltip holds the whole item it makes after its own lines: its
-- name, binding, slot, numbers, requirements and materials. Where that part
-- starts (a line of the item name type, or the recipe's name minus its
-- "Pattern: ") and ends (the next blank line), or nil.
local LT = Enum and Enum.TooltipDataLineType
Items.ITEM_NAME = LT and LT.ItemName or 22
Items.EQUIP_SLOT = LT and LT.EquipSlot or 21
function Items.Made(lines, own, title)
    local whole = type(title) == "string" and Items.Words(title) or nil
    for i = 2, own do
        local line = lines[i]
        local t = line.left and Items.Words(line.left) or nil
        if t and t ~= "" and not line.right and (line.type == Items.ITEM_NAME
            or (whole and #t + 2 < #whole and whole:sub(-(#t + 2)) == ": " .. t)) then
            local to = own
            for j = i + 1, own do
                local l = lines[j]
                local w = l.left and Items.Words(l.left) or ""
                if w == "" and not l.right then
                    to = j - 1
                    break
                end
            end
            return { from = i, to = to }
        end
    end
    return nil
end

-- Sorts the item's own lines (2 to own) into the card's groups. Each group
-- is a list of functions that add their pieces; the footer's two sides are
-- returned as they are.
local function sort(n, lines, own, info, groups, pieces)
    local P, Tip, Tips = Items.Patterns(), ns.Tooltip, DUI.Tips
    local foot = {}
    local inSet = false
    local made = Items.Made(lines, own, lines[1] and lines[1].left)
    groups.madeAt = made
    local madeGroups = { numbers = groups.made, stats = groups.made, effects = groups.made, set = groups.made,
        facts = groups.made, quote = groups.made, taken = groups.taken }
    local sellWord = type(SELL_PRICE) == "string" and SELL_PRICE or "Sell Price"
    local sellType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice or 11
    -- The simple look renames the game's line to "Vendor" before the card reads it.
    local vendorWord = L["Vendor"]
    for i = 2, n do
        local piece = pieces and pieces[i]
        local line = lines[i]
        -- The crafted item's lines go to its own part, in the game's order.
        local inMade = made ~= nil and i >= made.from and i <= made.to
        local g = inMade and madeGroups or groups
        local left, right = line.left, line.right
        local t = left and Items.Words(left) or nil
        local c = lineColor(line)
        local mine = i <= own
        if not t or t == "" then
            -- A blank line ends a set's piece list.
            inSet = false
        elseif piece and piece.sell then
            -- A quest reward's price, added by Daylight UI after the game's lines.
            g.taken[i] = true
            foot.money = piece.value
        elseif line.type == sellType then
            -- The game's own sell price line, known by its data line's type,
            -- never by its words: TSM's "Vendor Sell Price" and "Vendor Buy
            -- Price" rows start with the same word and belong to TSM.
            -- Another addon may have rewritten it with the coins on the right
            -- ("Vendor price"), so they're taken from there when it has them.
            local word = sellWord
            local at = left:find(word, 1, true)
            if not at then
                word = vendorWord
                at = left:find(word, 1, true)
            end
            if not mine then g.taken[i] = true end
            if right then
                foot.money = right
            elseif at then
                foot.money = (left:sub(at + #word):gsub("^%s*:%s*", ""))
            end
        elseif not mine then
            -- Another addon's: drawn by Rich/Foreign.lua.
        elseif inMade and i == made.from then
            -- The crafted item's name heads its part, in its quality color.
            local c2 = c and DUI.Tips.GameColor(c[1], c[2], c[3])
            local nameColor = (c and c2 ~= "white" and c2 ~= "yellow") and { c[1], c[2], c[3] } or Style.INK.TITLE
            g.numbers[#g.numbers + 1] = function(p) ns.RichPanel.Line(p, t, nameColor) end
        elseif inMade and isBadge(line, t) then
            -- What the crafted item binds as: with it, never among the recipe's own tags.
            local badge = Items.BadgeColor(t)
            g.facts[#g.facts + 1] = function(p) ns.RichPanel.Text(p, Style.Upper(t), badge, Style.SIZE.small) end
        elseif isBadge(line, t) then
            info.badges[#info.badges + 1] = t
        elseif inMade and (t:find(P.level) or line.type == Items.EQUIP_SLOT
            or (right and not t:find(P.damage) and not Items.Stat(t))) then
            -- Its slot and item level: words of the crafted item, not the recipe's tags.
            local words = right and (t .. "  " .. Items.Words(right)) or t
            g.facts[#g.facts + 1] = function(p) ns.RichPanel.Text(p, words, Style.INK.LABEL, Style.SIZE.small) end
        elseif info.slot and t == info.slot then
            -- Shown in the slot tag. The game paints the armor or weapon type
            -- red when your class can't use it, so the tag goes red too.
            info.slotWord = right and Items.Words(right) or nil
            info.cantUse = (line.hasRC and isRed(line.rc)) or isRed(c) or nil
        elseif t:find(P.level) then
            -- Shown in the item level tag.
        elseif t:find(P.durability) and inMade then
            g.facts[#g.facts + 1] = function(p) ns.RichPanel.Text(p, t, Style.INK.LABEL, Style.SIZE.small) end
        elseif t:find(P.durability) then
            foot.durability = Items.WearText(t)
        elseif t:find(P.armor) then
            local armor = { t:match(P.armor), ARMOR or L["Armor"] }
            g.armor = armor
            g.numbers[#g.numbers + 1] = function(p) pairLine(p, armor, armor.block) end
        elseif t:find(P.block) then
            local block = { t:match(P.block), BLOCK or L["Block"] }
            if g.armor and not g.armor.block then
                -- Drawn on the armor's line.
                g.armor.block = block
            else
                g.numbers[#g.numbers + 1] = function(p) numLine(p, block[1], block[2]) end
            end
        elseif t:find(P.damage) then
            local lo, hi = t:match(P.damage)
            local damage = { string.format(L["%s - %s"], lo, hi), DAMAGE or L["Damage"] }
            local words, num = wordsAndNumber(right and Items.Words(right) or "")
            local speed = words and { num, words } or nil
            g.numbers[#g.numbers + 1] = function(p) pairLine(p, damage, speed) end
            g.damageAt = #g.numbers
        elseif t:find(P.dps) then
            -- Big, over the damage and speed it comes from: the number that
            -- tells two weapons apart at a glance.
            local v = t:match(P.dps)
            local words = Items.DpsWords(v)
            table.insert(g.numbers, g.damageAt or #g.numbers + 1, function(p) ns.RichPanel.Big(p, words()) end)
            g.damageAt = nil
        elseif t:find(P.setName) then
            local name, have, total = t:match(P.setName)
            inSet = true
            g.set[#g.set + 1] = function(p)
                local r, g, b = Style.Accent()
                ns.RichPanel.Line(p, Style.Upper(name) .. " " .. hex({ r, g, b }) .. have .. "/" .. total .. "|r",
                    Style.INK.LABEL, Style.SIZE.small)
            end
        elseif t:find(P.setOff) then
            local count, text = t:match(P.setOff)
            inSet = false
            local words = Tip.ShortText(text) or text
            g.set[#g.set + 1] = function(p)
                ns.RichPanel.Text(p, string.format(L["(%s) %s"], count, words), Style.INK.OFF, Style.SIZE.small)
            end
        elseif t:find(P.setOn) then
            local text = t:match(P.setOn)
            inSet = false
            local words = Tip.ShortText(text) or text
            g.set[#g.set + 1] = function(p) ns.RichPanel.Text(p, words, Style.INK.GOOD, Style.SIZE.small) end
        elseif inSet then
            -- One of the set's pieces: the count says how many you have.
        elseif isGreen(c) or trigger(t) then
            local word, rest = trigger(t)
            local short = word == (ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:") and Tip.ShortText(rest) or nil
            local use, fed
            if word == (ITEM_SPELL_TRIGGER_ONUSE or "Use:") and Tip.ShortsOn() then use, fed = Tip.ShortUse(rest) end
            if short then
                for part in (short .. "\n"):gmatch("(.-)\n") do
                    local num, name, color = Items.Stat(part)
                    if num then
                        color = color or Style.INK.GOOD
                        g.stats[#g.stats + 1] = function(p) numLine(p, num, name, color) end
                    end
                end
            elseif use then
                -- Food, drink, potions: what it restores, then the well fed buff.
                local good = hex(Style.INK.GOOD)
                g.effects[#g.effects + 1] = function(p)
                    ns.RichPanel.Text(p, good .. word .. "|r " .. use, Style.INK.TEXT)
                end
                if fed then
                    g.effects[#g.effects + 1] = function(p)
                        ns.RichPanel.Text(p, good .. Tip.WELL_FED .. "|r " .. fed, Style.INK.TEXT)
                    end
                end
            elseif word then
                g.effects[#g.effects + 1] = function(p)
                    ns.RichPanel.Text(p, hex(Style.INK.GOOD) .. word .. "|r " .. Tips.Numbers(rest), Style.INK.TEXT)
                end
            else
                g.effects[#g.effects + 1] = function(p) ns.RichPanel.Text(p, Tips.Numbers(t), Style.INK.GOOD) end
            end
        elseif Items.Stat(t) and not right and not isRed(c) then
            local num, name, color = Items.Stat(t)
            color = color or (num:sub(1, 1) == "-" and Style.INK.DAMAGE) or Style.INK.VALUE
            g.stats[#g.stats + 1] = function(p) numLine(p, num, name, color) end
        elseif ns.Rich.IsFlavor(line) then
            g.quote[#g.quote + 1] = function(p) ns.Rich.Flavor(p, line) end
        else
            -- Requirements, classes, anything else the game says: small, tan,
            -- a requirement you don't meet in red.
            local color = isRed(c) and Style.INK.BAD or Style.INK.LABEL
            local words = right and (t .. "  " .. Items.Words(right)) or t
            g.facts[#g.facts + 1] = function(p) ns.RichPanel.Text(p, words, color, Style.SIZE.small) end
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
    local groups = { numbers = {}, stats = {}, effects = {}, set = {}, facts = {}, quote = {}, made = {}, taken = {} }
    info.badges = {}
    local foot = sort(n, lines, own, info, groups, p.foreign and p.foreign.pieces)
    -- A recipe: the card's tags are the recipe's own. The link may name the
    -- item it makes, so the recipe is read by the data's id then.
    if groups.madeAt and info.class ~= Items.RECIPE_CLASS then
        local id = type(data) == "table" and plain(data.id) or nil
        local recipe = type(id) == "number" and Items.Info("item:" .. id) or nil
        if recipe and recipe.class == Items.RECIPE_CLASS then
            recipe.badges = info.badges
            info = recipe
        end
    end
    if compare then
        Panel.Tags(p, { Items.Tag(compare.label, { Style.Accent() }) })
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
    local Wants = Panel.Wants
    if info.level and Wants("tags.item.level") then
        tags[#tags + 1] = Items.Tag(string.format(L["ilvl %d"], math.floor(info.level + 0.5)),
            info.light or Style.INK.VALUE)
    end
    if info.slot and not Wants("tags.item.slot") then
        -- Its slot and what it is (Plate, Sword) left off the card.
    elseif info.slot then
        -- The slot, then what it is (Plate, Sword) in a tag of its own color.
        tags[#tags + 1] = Items.Tag(info.slot, info.slotColor)
        local word = info.slotWord or info.sub
        if word and word ~= info.slot then
            tags[#tags + 1] = Items.Tag(word, info.cantUse and Style.INK.BAD
                or info.armor or info.subColor or info.kindColor)
        end
    elseif info.kind and not (info.class == Items.QUEST_CLASS and Items.HasBadge(info, ITEM_BIND_QUEST or "Quest Item")) then
        -- A quest item's "Quest Item" tag already says what it is.
        if info.sub and info.sub ~= info.kind and info.subColor then
            -- "Recipe" and "Blacksmithing" apart, the profession in its color.
            tags[#tags + 1] = Items.Tag(info.kind, info.kindColor)
            tags[#tags + 1] = Items.Tag(info.sub, info.subColor)
        else
            local what = info.sub and info.sub ~= info.kind and string.format(L["%s · %s"], info.kind, info.sub)
                or info.kind
            tags[#tags + 1] = Items.Tag(what, info.kindColor)
        end
    end
    if Wants("tags.item.bind") then
        for _, badge in ipairs(info.badges) do tags[#tags + 1] = Items.Tag(badge, Items.BadgeColor(badge)) end
    end
    -- How many fit in one bag slot, with the small facts (the stack size switch).
    local stack = (Tip.Config() or {}).stackSize == true and Tip.StackSize(link) or nil
    if stack then
        local words = L["Stacks to %s"]:format(hex({ Style.Pop() }) .. stack .. "|r")
        groups.facts[#groups.facts + 1] = function() Panel.Text(p, words, Style.INK.LABEL, Style.SIZE.small) end
    end
    Panel.Header(p, { icon = info.icon, iconSize = Items.ICON, iconEdge = info.color,
        title = first and first.left or "", titleColor = titleColor, tags = tags, tagGap = Items.TAG_GAP,
        wash = info.color })
    Panel.Gap(p, Items.AFTER_HEADER)
    -- The card's pieces in the player's order (Rich/Layout.lua). By default:
    -- the numbers, then everything said in words (effects, set, other
    -- facts, the quote last), the item a recipe makes, then the foot (other
    -- addons' lines first, then durability and sell price), a rule between
    -- each, so a card keeps to two or three rules. Lines the card drew itself
    -- (a sell price, a compare's changes) aren't other addons'.
    local Foreign, taken = ns.RichForeign, groups.taken
    if compare then
        for i in pairs(compare.skip) do taken[i] = true end
    end
    local pieces = {}
    for _, key in ipairs({ "numbers", "stats", "effects", "set", "facts", "quote", "made" }) do
        local list = groups[key]
        pieces[key] = { has = #list > 0, draw = function()
            for _, add in ipairs(list) do add(p) end
        end }
    end
    pieces.addons = Foreign.Part(p, "item", taken)
    -- A sell price alone (a quest reward has no durability) says what it is.
    pieces.foot = { has = (foot.durability or foot.money) ~= nil, draw = function()
        Panel.Row(p, foot.durability or L["Vendor"], foot.money, Style.INK.VALUE, Style.INK.LABEL, Style.SIZE.small, Style.SIZE.body)
    end }
    local any = ns.RichLayout.Run(p, "item", pieces)
    -- A compare's chips: what changes if you swap, last. They sit on the
    -- equipped item's card, so a heading says they're the trade, not its stats.
    if compare and #compare.chips > 0 then
        if any then Panel.Rule(p) end
        any = true
        Panel.Section(p, L["If you swap"])
        Panel.Tags(p, compare.chips)
    end
    -- Nothing under the header: no room kept for it.
    if not any then ns.RichLayout.DropGap(p) end
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
    -- With a weapon in each hand, which hand this one is in.
    local hand = ns.Tooltip.HandWord(ns.Tooltip.hands[tip])
    if hand then label = string.format(L["%s · %s"], label, hand) end
    local own = ns.Rich.Own(data, n)
    local chips, skip = Items.Changes(lines, own + 1, n)
    return Items.Card(p, tip, data, n, lines, light, fade, { label = label, chips = chips, skip = skip })
end
