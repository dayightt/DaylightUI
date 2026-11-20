-- The two tooltip looks side by side, for a player choosing between them (the
-- setup guide and the 2.0 welcome). Both show the same made-up item: Rich as
-- the real card, drawn by the card's own code, and Simple as the game's
-- tooltip lines in the Daylight UI shell. Same shape as the unit frames'
-- portrait looks sample: Looks(parent) gives a box with HEIGHT and
-- Refresh(width).

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local L = DUI.L

local Sample = {}
ns.RichSample = Sample

Sample.CARD_H = 200   -- the room each card gets; a taller one shrinks to fit
Sample.GAP = 6        -- between a card and its name
Sample.PAD = 10       -- inside the Simple card
Sample.SIMPLE_W = 230

Sample.LOOKS = {
    { key = "rich", name = "Rich", line = "Daylight UI's own card, laid out in rows." },
    { key = "simple", name = "Simple", line = "The game's tooltip in the Daylight UI look." },
}

-- The made-up item both cards show.
Sample.ITEM = {
    name = "Robe of the Evening Star", quality = 4, level = 60,
    icon = "Interface\\Icons\\INV_Chest_Cloth_04",
    armor = 89, stats = { { 22, "Intellect" }, { 14, "Stamina" }, { 12, "Spirit" } },
    equip = { 23, "Spell Power" }, money = 24150,
}

local function qualityColor()
    local r, g, b = ns.Tooltip.QualityColor(Sample.ITEM.quality)
    if not r then
        local c = Style.INK.VALUE
        r, g, b = c[1], c[2], c[3]
    end
    return { r, g, b }
end

local function hex(c) return DUI.Win.Parts.Hex(c) end

-- "+22 Intellect" with the number in the stat's color, as both looks paint it.
local function statText(n, word)
    local c = ns.Tooltip.StatColor(word) or { Style.Pop() }
    return hex(c) .. "+" .. n .. "|r " .. L[word]
end

-- The Simple look: the game's lines, in the order the game writes them.
local function buildSimple(parent)
    local Tip = ns.Tooltip
    local f = CreateFrame("Frame", nil, parent)
    f.shell = Style.Shell(f, { borderPx = Tip.BORDER, flat = true, noBevel = true, bgAlpha = Tip.BackAlpha("simple") })
    f.lines = {}
    local item = Sample.ITEM
    local function add(size, text, color, right)
        local fs = Style.Text(f, size, "LEFT")
        fs:SetText(text)
        Style.InkText(fs, color or "VALUE")
        local line = { fs = fs }
        if right then
            line.right = Style.Text(f, size, "RIGHT")
            line.right:SetText(right)
            Style.InkText(line.right, "VALUE")
        end
        f.lines[#f.lines + 1] = line
        return fs
    end
    f.title = add(Style.SIZE.head, L[item.name])
    add(Style.SIZE.body, ITEM_BIND_ON_PICKUP or L["Binds when picked up"])
    add(Style.SIZE.body, INVTYPE_ROBE or L["Chest"], nil, L["Cloth"])
    add(Style.SIZE.body, string.format(ARMOR_TEMPLATE or L["%s Armor"], item.armor))
    for _, s in ipairs(item.stats) do add(Style.SIZE.body, statText(s[1], s[2])) end
    add(Style.SIZE.body, string.format(L["Equip: %s"], "+" .. item.equip[1] .. " " .. L[item.equip[2]]), "GOOD")
    add(Style.SIZE.body, (SELL_PRICE or L["Sell Price"]) .. ": " .. DUI.Widgets.Money(item.money))
    function f.Layout()
        local c = qualityColor()
        f.title:SetTextColor(c[1], c[2], c[3], 1)
        local y = Sample.PAD
        for _, line in ipairs(f.lines) do
            line.fs:ClearAllPoints()
            line.fs:SetPoint("TOPLEFT", f, "TOPLEFT", Sample.PAD, -y)
            if line.right then
                line.right:ClearAllPoints()
                line.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Sample.PAD, -y)
            end
            local h = line.fs:GetStringHeight()
            y = y + ((type(h) == "number" and h > 0) and h or 13) + 2
        end
        f:SetSize(Sample.SIMPLE_W, y + Sample.PAD - 2)
        Style.LayoutShell(f.shell)
    end
    return f
end

-- The Rich look: the card itself, filled the way an item's card is.
local function buildRich(parent)
    local Panel, Items = ns.RichPanel, ns.RichItems
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(1, 1)
    local p = Panel.For(holder)
    function holder.Layout()
        local item, c = Sample.ITEM, qualityColor()
        Panel.Begin(p, "item", { Items.Lift(c), c }, true)
        p.padTop, p.rowGap, p.ruleGap = Items.PAD_TOP, Items.ROW_GAP, Items.RULE_GAP
        p.washDown = true
        Panel.Header(p, { icon = item.icon, iconSize = Items.ICON, iconEdge = c, title = L[item.name], titleColor = c,
            tagGap = Items.TAG_GAP, wash = c, tags = {
                Items.Tag(string.format(L["ilvl %d"], item.level), c),
                Items.Tag(INVTYPE_ROBE or L["Chest"], Items.SLOT_ARMOR),
                Items.Tag(L["Cloth"], Items.ARMOR_COLORS[1]),
            } })
        Panel.Gap(p, Items.AFTER_HEADER)
        Panel.Line(p, hex({ Style.Pop() }) .. item.armor .. "|r " .. (ARMOR or L["Armor"]))
        for _, s in ipairs(item.stats) do Panel.Line(p, statText(s[1], s[2])) end
        Panel.Line(p, statText(item.equip[1], item.equip[2]), Style.INK.TEXT, nil, L["Equip"], Style.INK.GOOD)
        Panel.Rule(p)
        Panel.Row(p, SELL_PRICE or L["Sell price"], DUI.Widgets.Money(item.money), Style.INK.VALUE, Style.INK.LABEL,
            Style.SIZE.small, Style.SIZE.body)
        local w, h = Panel.Finish(p)
        local k = p:GetScale()
        holder:SetSize(w * k, h * k)
    end
    return holder
end

function Sample.Looks(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.cards, box.names, box.lines = {}, {}, {}
    for _, look in ipairs(Sample.LOOKS) do
        -- A frame per card, scaled as a whole to fit its half.
        local wrap = CreateFrame("Frame", nil, box)
        wrap:SetSize(1, 1)
        box.cards[look.key] = { wrap = wrap, card = look.key == "rich" and buildRich(wrap) or buildSimple(wrap) }
        local name = Style.Text(box, Style.SIZE.body, "CENTER")
        name:SetText(L[look.name])
        box.names[look.key] = name
        local line = Style.Text(box, Style.SIZE.small, "CENTER")
        line:SetText(L[look.line])
        box.lines[look.key] = line
    end
    box.HEIGHT = Sample.CARD_H + Sample.GAP + Style.SIZE.body + 4 + Style.SIZE.small + 2
    function box.Refresh(width) Sample.Layout(box, width) end
    return box
end

function Sample.Layout(box, width)
    width = (type(width) == "number" and width > 0) and width or 460
    box:SetSize(width, box.HEIGHT)
    local half = width / 2
    for i, look in ipairs(Sample.LOOKS) do
        local c = box.cards[look.key]
        c.card.Layout()
        local w, h = c.card:GetWidth(), c.card:GetHeight()
        local scale = math.min(1, (half - 16) / math.max(1, w), Sample.CARD_H / math.max(1, h))
        c.wrap:SetScale(scale)
        c.wrap:SetSize(w, h)
        local mid = (i - 0.5) * half
        c.wrap:ClearAllPoints()
        -- Cards hang from the top, centered in their half.
        c.wrap:SetPoint("TOP", box, "TOPLEFT", mid / scale, 0)
        c.card:ClearAllPoints()
        c.card:SetPoint("TOPLEFT", c.wrap, "TOPLEFT", 0, 0)
        local name, line = box.names[look.key], box.lines[look.key]
        Style.InkText(name, "VALUE")
        Style.InkText(line, "LABEL")
        name:ClearAllPoints()
        name:SetPoint("TOP", box, "TOPLEFT", mid, -(Sample.CARD_H + Sample.GAP))
        name:SetWidth(half - 8)
        line:ClearAllPoints()
        line:SetPoint("TOP", name, "BOTTOM", 0, -4)
        line:SetWidth(half - 8)
    end
end
