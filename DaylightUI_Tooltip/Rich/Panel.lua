-- The rich tooltip's panel: Daylight UI's own card drawn over the game's
-- tooltip. It's a child of the tooltip, so the tooltip's alpha (its fade in,
-- the game's fade out, a mute), scale, spot and showing carry it. The game's
-- own lines stay under it at alpha 0 (never hidden or emptied: other addons
-- read and add to them), and the tooltip is padded to the card's size, so
-- compare tooltips and frames other addons pin to it still line up.
--
-- A card is a list of pieces laid out top to bottom: Begin, then Header, Row,
-- Text, Rule, Gap, Section, Bar, Tiles, Tags, Hints, then Finish. Every region
-- is pooled per panel and reused on the next fill.
--
-- When a line is secret (a fight, the client's restrictions) nothing about its
-- size can be read, so the card can't be measured or the tooltip padded to it.
-- The panel then shows only its frame (Chrome): shell, top light and corner
-- cut around the game's own lines, sized by the game.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret

local Panel = {}
ns.RichPanel = Panel

Panel.PAD_X, Panel.PAD_TOP, Panel.PAD_BOTTOM = 16, 14, 14
Panel.ROW_GAP = 5      -- between rows
Panel.RULE_GAP = 10    -- above and below a rule
Panel.CUT = 12         -- the card's bottom-right corner
Panel.ICON_CUT = 8
Panel.LIGHT_H = 2      -- the colored line along the top
Panel.BORDER = 4       -- outline, warm band, inner line (screen pixels)
Panel.MIN_W = 160
-- Each kind's card is as wide as its board; anything else is as wide as it
-- needs, up to "other".
Panel.WIDTH = { unit = 300, mob = 260, node = 210, item = 290, compare = 290, spell = 270, cooldown = 200, other = 280 }
Panel.FIXED = { unit = true, mob = true, node = true, item = true, compare = true, spell = true, cooldown = true }
Panel.TAG_GAP, Panel.TILE_GAP = 6, 4
Panel.HINT_H = 20      -- a hint line, 12 px text at 1.7 line height
Panel.RULE_ALPHA = 0.25
Panel.SHADE = 0.45     -- a bar colored from a curve: its dark end, as black over the fill
Panel.BUFF, Panel.BUFF_GAP = 22, 4
Panel.WASH_ALPHA = 0.22
Panel.WASH_DOWN = 0.16 -- an item's wash, top to bottom
Panel.SWEEP_W = 70     -- the quality light's sweep
-- Lines measured with no font metrics (the tests) are this tall per size.
Panel.LINE_EXTRA = 3

local panels = setmetatable({}, { __mode = "k" }) -- tooltip -> panel

local function W() return DUI.Widgets end
local function font() return ns.MEDIA and ns.MEDIA.font end

-- The card is laid out in the boards' own numbers (title 18, rows 13, 300
-- wide) and drawn at Panel.CARD, so its rows sit near a tooltip's usual text
-- size (12) and its title near a tooltip's heading: at 1 it read far bigger
-- than every other tooltip. The tooltip text size setting (12 by default)
-- scales the whole card with it.
Panel.CARD = 0.85
function Panel.Scale()
    local cfg = ns.Tooltip.Config()
    return Panel.CARD * (cfg and tonumber(cfg.textSize) or 12) / 12
end

local function size(s) return s end

local function lineHeight(fs, s)
    local h = fs:GetStringHeight()
    if type(h) == "number" and not isSecret(h) and h > 0 then return h end
    return s + Panel.LINE_EXTRA
end

local function widthOf(fs)
    local w = fs:GetStringWidth()
    if type(w) ~= "number" or isSecret(w) then return 0 end
    return w
end

local function paint(fs, c)
    c = c or Style.INK.TEXT
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- ---------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------

function Panel.Get(tip) return panels[tip] end

function Panel.For(tip)
    local p = panels[tip]
    if p then return p end
    p = CreateFrame("Frame", nil, tip)
    p:SetAllPoints(tip)
    p:EnableMouse(false)
    p:Hide()
    p.tip = tip
    p.shell = Style.Shell(p, { borderPx = Panel.BORDER, cornerPx = 0, noBevel = true, bgAlpha = ns.Tooltip.BackAlpha("rich") })
    Style.CutShell(p, Panel.CUT)
    -- The top light: two pieces, so a quality light can fade out along its
    -- right part (one gradient has only two ends).
    p.light = { p:CreateTexture(nil, "ARTWORK", nil, 2), p:CreateTexture(nil, "ARTWORK", nil, 2) }
    for _, t in ipairs(p.light) do t:SetTexture("Interface\\Buttons\\WHITE8X8") end
    -- The header's wash: two pieces too (strong to faint, then faint to none).
    p.wash = { p:CreateTexture(nil, "BACKGROUND", nil, 1), p:CreateTexture(nil, "BACKGROUND", nil, 1) }
    for _, t in ipairs(p.wash) do
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:Hide()
    end
    p.pool = { text = {}, tex = {}, bar = {}, timer = {}, tag = {}, tile = {}, icon = {}, buff = {} }
    p.used = { text = 0, tex = 0, bar = 0, timer = 0, tag = 0, tile = 0, icon = 0, buff = 0 }
    -- The quality light's sweep: a short bright band along the top light, soft
    -- at both ends, run once as the card shows.
    p.track = CreateFrame("Frame", nil, p)
    p.track:EnableMouse(false)
    p.sweep = CreateFrame("Frame", nil, p)
    p.sweep:EnableMouse(false)
    p.sweep:Hide()
    p.sweep.halves = { p.sweep:CreateTexture(nil, "OVERLAY"), p.sweep:CreateTexture(nil, "OVERLAY") }
    for i, t in ipairs(p.sweep.halves) do
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetBlendMode("ADD")
        t:SetPoint(i == 1 and "TOPLEFT" or "TOPRIGHT", p.sweep, i == 1 and "TOPLEFT" or "TOPRIGHT")
        t:SetPoint(i == 1 and "BOTTOMRIGHT" or "BOTTOMLEFT", p.sweep, "BOTTOM")
    end
    -- Every piece lives in here, so the card's words can fade in while its
    -- frame stays put.
    p.body = CreateFrame("Frame", nil, p)
    p.body:SetAllPoints(p)
    p.body:EnableMouse(false)
    p.items, p.count = {}, 0
    panels[tip] = p
    Panel.Level(p)
    return p
end

-- Below the tooltip's own text (shown in Chrome), above nothing of the game's.
function Panel.Level(p)
    local tip = p.tip
    local level = tip:GetFrameLevel()
    if level < 2 then
        tip:SetFrameLevel(2)
        level = 2
    end
    p:SetFrameLevel(level - 1)
    p.body:SetFrameLevel(level)
    p.shell:SetFrameLevel(level - 2)
    if p.shell.over then p.shell.over:SetFrameLevel(level - 1) end
end

function Panel.Repaint(p)
    p.shell.opts.bgAlpha = ns.Tooltip.BackAlpha("rich")
    Style.LayoutShell(p.shell)
end

-- ---------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------

local makers = {
    text = function(p)
        local fs = Style.Text(p, Style.SIZE.body, "LEFT", font())
        fs:SetWordWrap(false)
        return fs
    end,
    tex = function(p)
        local t = p:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        return t
    end,
    icon = function(p)
        local f = CreateFrame("Frame", nil, p)
        f:EnableMouse(false)
        -- A tile behind art that doesn't fill the square (a round class icon).
        f.tile = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.tile:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.tile:SetAllPoints(f)
        f.art = f:CreateTexture(nil, "ARTWORK", nil, 1)
        -- The quality outline: a square a pixel bigger than the art, under it,
        -- so only its ring shows.
        f.edge = f:CreateTexture(nil, "ARTWORK", nil, -1)
        f.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.glow = f:CreateTexture(nil, "BACKGROUND")
        f.glow:SetTexture(DUI.MEDIA .. "glow.png")
        f.glow:SetBlendMode("ADD")
        Style.CutCorner(f, Panel.ICON_CUT, f.art, f.tile)
        return f
    end,
    -- A buff: the icon inside a black edge and a thin warm ring.
    buff = function(p)
        local f = CreateFrame("Frame", nil, p)
        f:EnableMouse(false)
        f.ring = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.edge = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        local band, b = Style.BAND, Style.BORDER
        f.ring:SetColorTexture(band[1], band[2], band[3], 1)
        f.edge:SetColorTexture(b[1], b[2], b[3], 1)
        f.edge:SetAllPoints(f)
        f.art = f:CreateTexture(nil, "ARTWORK")
        return f
    end,
    bar = function(p) return Panel.MakeBar(p) end,
    -- A bar the client drains by itself (a cooldown): kept apart, as nothing
    -- takes a running timer off a bar again.
    timer = function(p) return Panel.MakeBar(p) end,
    tag = function(p) return W().Tag(p, font()) end,
    tile = function(p) return W().Tile(p, font()) end,
}

-- A thin bar in the card's look: black under it, a dark outline, the fill a
-- gradient with an angled end. Also the fight pill's.
function Panel.MakeBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.back = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.back:SetColorTexture(0, 0, 0, 0.6)
    bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    local b = Style.BORDER
    bar.edge:SetColorTexture(b[1], b[2], b[3], 1)
    -- Over a fill colored from the health curve (a secret color, so no dark
    -- end can be worked out from it): black fading out, left to right.
    bar.shade = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.shade:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.shade:SetVertexColor(1, 1, 1, 1)
    if bar.shade.SetGradient and CreateColor then
        bar.shade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, Panel.SHADE), CreateColor(0, 0, 0, 0))
    end
    Style.FollowFill(bar, bar.shade)
    bar:SetMinMaxValues(0, 1)
    return bar
end

-- spec: unit with health = true (its health, colored by the health curve) or
-- power = true (its power); else value and max. pair { lo, hi } paints the
-- fill. Values may be secret: they only go into the bar. duration: a duration
-- object the client drains the bar by, with no Lua running each frame.
function Panel.PaintBar(bar, spec)
    local unit = spec.unit
    if spec.duration then
        local E = Enum
        bar:SetTimerDuration(spec.duration, E.StatusBarInterpolation.Immediate, E.StatusBarTimerDirection.RemainingTime)
    elseif unit and spec.health then
        bar:SetMinMaxValues(0, UnitHealthMax(unit))
        bar:SetValue(UnitHealth(unit))
    elseif unit and spec.power then
        bar:SetMinMaxValues(0, UnitPowerMax(unit))
        bar:SetValue(UnitPower(unit))
    else
        bar:SetMinMaxValues(0, spec.max or 1)
        bar:SetValue(spec.value or 0)
    end
    local fill = bar:GetStatusBarTexture()
    if unit and spec.health and not spec.pair and DUI.Health.GradientCurve() then
        fill:SetVertexColor(1, 1, 1, 1)
        DUI.Health.ApplyGradient(bar, unit)
        bar.shade:Show()
    elseif unit and spec.health and not spec.pair then
        -- No color curve in this client: the full-health green.
        local lo, hi = DUI.Gradients.PairFrom(Style.INK.GOOD)
        DUI.Gradients.PaintPair(fill, lo, hi)
        bar.shade:Hide()
    else
        local pair = spec.pair
        if pair then DUI.Gradients.PaintPair(fill, pair[1], pair[2]) end
        bar.shade:Hide()
    end
end

local function take(p, kind)
    local n = p.used[kind] + 1
    p.used[kind] = n
    local list = p.pool[kind]
    local r = list[n]
    if not r then
        r = makers[kind](p.body or p)
        list[n] = r
    end
    r:ClearAllPoints()
    r:Show()
    return r
end

local function text(p, s, c, wrap)
    local fs = take(p, "text")
    Style.SetTextSize(fs, size(s))
    fs.size = size(s)
    fs:SetWidth(0)
    fs:SetWordWrap(wrap and true or false)
    fs:SetJustifyH("LEFT")
    paint(fs, c)
    return fs
end

local function add(p, item)
    p.count = p.count + 1
    p.items[p.count] = item
    return item
end

-- ---------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------

-- kind: "unit", "item", "spell" or "other" (its widest card). light: the top
-- light's pair { lo, hi } ({ r, g, b } each), fade = its right part fades out.
function Panel.Begin(p, kind, light, fade)
    for k in pairs(p.used) do
        local list = p.pool[k]
        for i = 1, p.used[k] do list[i]:Hide() end
        p.used[k] = 0
    end
    for i = 1, p.count do p.items[i] = nil end
    p.count = 0
    p.kind = kind or "other"
    p.lightPair, p.lightFade = light, fade
    p.washColor, p.washDown = nil, nil
    p.padX, p.padTop, p.rowGap, p.ruleGap = nil, nil, nil, nil
    p.chrome = false
end

-- spec: icon (file or id) or portrait (a unit: its face), iconSize, iconCoords ({ l, r, t, b }, else the
-- square crop), iconTile ({ lo, hi }: a gradient tile behind it), iconInset
-- (the art this far inside the tile), iconEdge ({ r, g, b }: an outline and glow),
-- iconGap (between the icon and the words, 12), title, titleColor, titleSize,
-- right, rightColor, tags = { { text, color } }, sub (a line under the title),
-- wash ({ r, g, b }: the banner's light).
function Panel.Header(p, spec)
    local item = add(p, { kind = "header", spec = spec })
    if spec.icon or spec.portrait then
        local ic = take(p, "icon")
        if spec.portrait then
            -- Square, no round mask: the card cuts its corner itself.
            ic.art:SetTexture(nil)
            DUI.SafeCall(SetPortraitTexture, ic.art, spec.portrait, true)
        else
            ic.art:SetTexture(spec.icon)
        end
        local c = spec.iconCoords
        if c then ic.art:SetTexCoord(c[1], c[2], c[3], c[4]) else Style.CropIcon(ic.art) end
        local inset = spec.iconInset or 0
        ic.art:ClearAllPoints()
        ic.art:SetPoint("TOPLEFT", ic, "TOPLEFT", inset, -inset)
        ic.art:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", -inset, inset)
        local tile = spec.iconTile
        ic.tile:SetShown(tile ~= nil)
        if tile then
            ic.tile:SetVertexColor(1, 1, 1, 1)
            Style.Gradient(ic.tile, "VERTICAL", tile[1][1], tile[1][2], tile[1][3], 1, tile[2][1], tile[2][2], tile[2][3], 1)
        end
        local e = spec.iconEdge
        ic.edge:SetShown(e ~= nil)
        ic.glow:SetShown(e ~= nil)
        if e then
            ic.edge:SetVertexColor(e[1], e[2], e[3], 1)
            ic.glow:SetVertexColor(e[1], e[2], e[3], 0.45)
        end
        item.icon = ic
    end
    item.title = text(p, spec.titleSize or Style.SIZE.title, spec.titleColor or Style.INK.TITLE)
    item.title:SetText(spec.title or "")
    if spec.right then
        item.right = text(p, Style.SIZE.body, spec.rightColor or Style.INK.VALUE)
        item.right:SetText(spec.right)
    end
    if spec.sub then
        item.sub = text(p, Style.SIZE.small, Style.INK.LABEL)
        item.sub:SetText(spec.sub)
    end
    if spec.tags then
        item.tags = {}
        for i, t in ipairs(spec.tags) do
            local tag = take(p, "tag")
            tag.Set(t[1], t[2])
            item.tags[i] = tag
        end
    end
    p.washColor = spec.wash
end

-- A label on the left, its value on the right. s: their text size (body).
function Panel.Row(p, label, value, valueColor, labelColor, s)
    local item = add(p, { kind = "row" })
    item.label = text(p, s or Style.SIZE.body, labelColor or Style.INK.LABEL)
    item.label:SetText(label or "")
    if value and value ~= "" then
        item.value = text(p, s or Style.SIZE.body, valueColor or Style.INK.VALUE)
        item.value:SetText(value)
        item.value:SetJustifyH("RIGHT")
    end
end

-- A sentence, wrapped to the card.
function Panel.Text(p, sentence, color, s)
    local item = add(p, { kind = "text" })
    item.fs = text(p, s or Style.SIZE.body, color or Style.INK.TEXT, true)
    item.fs:SetText(sentence or "")
end

-- One line that never wraps, cut with "..." at the card's edge, and an
-- optional smaller tail right after it (a stat's "from Equip").
function Panel.Line(p, words, color, s, tail, tailColor, tailSize)
    local item = add(p, { kind = "line" })
    item.fs = text(p, s or Style.SIZE.body, color or Style.INK.TEXT)
    item.fs:SetText(words or "")
    if tail then
        item.tail = text(p, tailSize or Style.SIZE.small, tailColor or Style.INK.LABEL)
        item.tail:SetText(tail)
    end
end

function Panel.Rule(p)
    local item = add(p, { kind = "rule" })
    local t = take(p, "tex")
    local c = Style.INK.LABEL
    t:SetVertexColor(1, 1, 1, 1)
    if t.SetGradient and CreateColor then
        Style.Gradient(t, "HORIZONTAL", c[1], c[2], c[3], Panel.RULE_ALPHA, c[1], c[2], c[3], 0)
    end
    item.tex = t
end

function Panel.Gap(p, h) add(p, { kind = "gap", h = h or 6 }) end

-- A small upper-case heading in the accent (a quest, a set).
function Panel.Section(p, title, color)
    local item = add(p, { kind = "section" })
    local c = color
    if not c then
        local r, g, b = Style.Accent()
        c = { r, g, b }
    end
    item.fs = text(p, Style.SIZE.tiny, c)
    item.fs:SetText(Style.Upper(title or ""))
end

-- spec: as Panel.PaintBar, plus h (7 or 4), caption (above, left) and pct
-- (above, right: text, or fn(fs) that writes it, secret or not).
function Panel.Bar(p, spec)
    local item = add(p, { kind = "bar", h = spec.h or 4, spec = spec })
    local bar = take(p, spec.duration and "timer" or "bar")
    Panel.PaintBar(bar, spec)
    item.bar = bar
    if spec.caption then
        item.caption = text(p, Style.SIZE.tiny, Style.INK.LABEL)
        item.caption:SetText(Style.Upper(spec.caption))
    end
    if spec.pct then
        local r, g, b = Style.Accent()
        item.pct = text(p, Style.SIZE.tiny, { r, g, b })
        if type(spec.pct) == "function" then spec.pct(item.pct) else item.pct:SetText(spec.pct) end
        item.pct:SetJustifyH("RIGHT")
    end
end

-- The card's unit bars and their numbers again (health while it shows).
function Panel.UpdateBars(p)
    for i = 1, p.count do
        local item = p.items[i]
        if item.kind == "bar" and item.spec.unit then
            Panel.PaintBar(item.bar, item.spec)
            if item.pct and type(item.spec.pct) == "function" then item.spec.pct(item.pct) end
        end
    end
end

-- icons: a list of icon files or ids (n of them), in rows of as many as fit
-- (a player's buffs).
function Panel.Icons(p, icons, n)
    local item = add(p, { kind = "icons", list = {} })
    for i = 1, n or #icons do
        local f = take(p, "buff")
        f.art:SetTexture(icons[i])
        Style.CropIcon(f.art)
        item.list[i] = f
    end
end

-- tiles: { { value, caption, color }, ... } side by side, equal widths.
function Panel.Tiles(p, tiles)
    local item = add(p, { kind = "tiles", list = {} })
    for i, t in ipairs(tiles) do
        local tile = take(p, "tile")
        tile.Set(t[1], t[2], t[3])
        item.list[i] = tile
    end
end

-- tags: { { text, color }, ... } in a row that wraps (compare's change chips).
function Panel.Tags(p, tags)
    local item = add(p, { kind = "tags", list = {} })
    for i, t in ipairs(tags) do
        local tag = take(p, "tag")
        tag.Set(t[1], t[2])
        item.list[i] = tag
    end
end

-- hints: { { key, what, color? }, ... }: the key in the accent (or its own
-- color: a spell's school), what it does TEXT.
function Panel.Hints(p, hints)
    local item = add(p, { kind = "hints", list = {} })
    local Hex = DUI.Win.Parts.Hex
    local r, g, b = Style.Accent()
    local accent = Hex({ r, g, b })
    for i, h in ipairs(hints) do
        local fs = text(p, Style.SIZE.small, Style.INK.TEXT)
        fs:SetText((h[3] and Hex(h[3]) or accent) .. h[1] .. "|r " .. h[2])
        item.list[i] = fs
    end
end

-- ---------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------

local function tagsWidth(list)
    local w = 0
    for i, tag in ipairs(list) do w = w + tag:GetWidth() + (i > 1 and Panel.TAG_GAP or 0) end
    return w
end

local function natural(item)
    local k = item.kind
    if k == "header" then
        local w = widthOf(item.title) + (item.right and (12 + widthOf(item.right)) or 0)
        if item.sub then w = math.max(w, widthOf(item.sub)) end
        if item.tags then w = math.max(w, tagsWidth(item.tags)) end
        local icon = item.icon and ((item.spec.iconSize or 36) + (item.spec.iconGap or 12)) or 0
        return icon + w
    elseif k == "row" then
        return widthOf(item.label) + (item.value and (16 + widthOf(item.value)) or 0)
    elseif k == "text" or k == "section" then
        return widthOf(item.fs)
    elseif k == "line" then
        return widthOf(item.fs) + (item.tail and (4 + widthOf(item.tail)) or 0)
    elseif k == "hints" then
        local w = 0
        for _, fs in ipairs(item.list) do w = math.max(w, widthOf(fs)) end
        return w
    elseif k == "tiles" then
        local w = 0
        for _, t in ipairs(item.list) do w = math.max(w, widthOf(t.value), widthOf(t.caption)) end
        return #item.list * (w + 2 * W().TILE_PAD) + (#item.list - 1) * Panel.TILE_GAP
    elseif k == "icons" then
        local n = math.min(#item.list, 10)
        return n * (Panel.BUFF + Panel.BUFF_GAP) - Panel.BUFF_GAP
    elseif k == "tags" then
        return tagsWidth(item.list)
    end
    return 0
end

-- Each piece placed from the panel's top-left at y (going down) and across
-- the inside width; returns its height.
-- A card's own spacing (Begin clears them): padX, padTop, rowGap, ruleGap.
local function padX(p) return p.padX or Panel.PAD_X end

local place = {}

function place.header(p, item, y, inner)
    local x = padX(p)
    local spec, h = item.spec, 0
    if item.icon then
        local s = spec.iconSize or 36
        local ic = item.icon
        ic:SetSize(s, s)
        ic:SetPoint("TOPLEFT", p, "TOPLEFT", x, -y)
        local one = DUI.Pixel.Px(ic, 1)
        ic.edge:ClearAllPoints()
        ic.edge:SetPoint("TOPLEFT", ic, "TOPLEFT", -one, one)
        ic.edge:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", one, -one)
        ic.glow:ClearAllPoints()
        ic.glow:SetPoint("TOPLEFT", ic, "TOPLEFT", -12, 12)
        ic.glow:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 12, -12)
        Style.CutCorner(ic, Panel.ICON_CUT, ic.edge)
        x = x + s + (spec.iconGap or 12)
        h = s
    end
    local th = lineHeight(item.title, item.title.size)
    local col = th
    if item.sub then col = col + 2 + lineHeight(item.sub, item.sub.size) end
    local tagGap = spec.tagGap or 5
    if item.tags and #item.tags > 0 then col = col + tagGap + W().TAG_H end
    -- The words sit in the middle of the icon's height when shorter.
    local top = y + math.max(0, (h - col) / 2)
    item.title:SetPoint("TOPLEFT", p, "TOPLEFT", x, -top)
    -- Never past the card's edge (or the level beside it): cut short with "...".
    local room = inner + padX(p) - x - (item.right and (12 + widthOf(item.right)) or 0)
    if widthOf(item.title) > room + 1 then item.title:SetWidth(room) end
    if item.right then
        -- On the title's baseline, at the right edge (a mob's level).
        item.right:SetPoint("TOPRIGHT", p, "TOPRIGHT", -padX(p), -(top + th - lineHeight(item.right, item.right.size)))
    end
    local ty = top + th
    if item.sub then
        item.sub:SetPoint("TOPLEFT", p, "TOPLEFT", x, -(ty + 2))
        ty = ty + 2 + lineHeight(item.sub, item.sub.size)
    end
    if item.tags and #item.tags > 0 then
        local tx = x
        for _, tag in ipairs(item.tags) do
            tag:SetPoint("TOPLEFT", p, "TOPLEFT", tx, -(ty + tagGap))
            tx = tx + tag:GetWidth() + Panel.TAG_GAP
        end
        ty = ty + tagGap + W().TAG_H
    end
    item.h = math.max(h, ty - y)
    return item.h
end

function place.row(p, item, y)
    item.label:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -y)
    local h = lineHeight(item.label, item.label.size)
    if item.value then
        item.value:SetPoint("TOPRIGHT", p, "TOPRIGHT", -padX(p), -y)
        item.value:SetPoint("LEFT", item.label, "RIGHT", 16, 0)
        h = math.max(h, lineHeight(item.value, item.value.size))
    end
    return h
end

function place.text(p, item, y, inner)
    local fs = item.fs
    fs:SetWidth(inner)
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -y)
    local h = fs:GetStringHeight()
    if type(h) == "number" and not isSecret(h) and h > 0 then return h end
    -- No metrics (the tests): as many lines as the width needs.
    local lines = math.max(1, math.ceil(widthOf(fs) / math.max(1, inner)))
    return lines * (fs.size + Panel.LINE_EXTRA)
end

function place.section(p, item, y)
    item.fs:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -y)
    return lineHeight(item.fs, item.fs.size)
end

function place.line(p, item, y, inner)
    local fs, tail = item.fs, item.tail
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -y)
    local room = inner - (tail and (4 + widthOf(tail)) or 0)
    if widthOf(fs) > room + 1 then fs:SetWidth(math.max(1, room)) end
    local h = lineHeight(fs, fs.size)
    if tail then
        -- On the line's baseline.
        tail:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 4, 0)
        h = math.max(h, lineHeight(tail, tail.size))
    end
    return h
end

function place.rule(p, item, y, inner)
    local t, one = item.tex, DUI.Pixel.Px(item.tex, 1)
    local gap = p.ruleGap or Panel.RULE_GAP
    t:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -(y + gap))
    t:SetSize(inner, one)
    return 2 * gap + one
end

function place.gap(_, item) return item.h end

function place.bar(p, item, y)
    local top = y
    if item.caption or item.pct then
        local s = (item.caption or item.pct).size
        if item.caption then item.caption:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -y) end
        if item.pct then item.pct:SetPoint("TOPRIGHT", p, "TOPRIGHT", -padX(p), -y) end
        top = y + s + Panel.LINE_EXTRA + 4
    end
    local bar = item.bar
    bar:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -top)
    bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -padX(p), -top)
    Panel.ShapeBar(bar, item.h)
    return top - y + item.h
end

-- A bar's height and its right end, cut at 45 degrees: the fill's moving end
-- and the track behind it at the same angle, so a full bar ends in one clean
-- slant instead of the fill's cut against a square black corner. The outline
-- sits inside the track, under the fill.
function Panel.ShapeBar(bar, h)
    bar:SetHeight(h)
    local one = DUI.Pixel.Px(bar, 1)
    bar.edge:ClearAllPoints()
    bar.edge:SetAllPoints(bar)
    bar.back:ClearAllPoints()
    bar.back:SetPoint("TOPLEFT", bar, "TOPLEFT", one, -one)
    bar.back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -one, one)
    Style.AngleFill(bar, "right", h)
    Style.CutCorner(bar, h, bar.back, bar.edge)
end

function place.tiles(p, item, y, inner)
    local n = #item.list
    local w = (inner - (n - 1) * Panel.TILE_GAP) / math.max(1, n)
    for i, t in ipairs(item.list) do
        t:SetSize(w, W().TILE_H)
        t:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p) + (i - 1) * (w + Panel.TILE_GAP), -y)
        Style.LayoutShell(Style.GetShell(t))
    end
    return W().TILE_H
end

function place.tags(p, item, y, inner)
    local x, row = 0, 0
    for _, tag in ipairs(item.list) do
        local w = tag:GetWidth()
        if x > 0 and x + w > inner then
            x, row = 0, row + 1
        end
        tag:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p) + x, -(y + row * (W().TAG_H + 4)))
        x = x + w + 4
    end
    return (row + 1) * W().TAG_H + row * 4
end

function place.icons(p, item, y, inner)
    local s, gap = Panel.BUFF, Panel.BUFF_GAP
    local per = math.max(1, math.floor((inner + gap) / (s + gap)))
    local one = DUI.Pixel.Px(p, 1)
    for i, f in ipairs(item.list) do
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        f:SetSize(s, s)
        f:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p) + col * (s + gap), -(y + row * (s + gap)))
        f.ring:ClearAllPoints()
        f.ring:SetPoint("TOPLEFT", f, "TOPLEFT", -one, one)
        f.ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", one, -one)
        f.art:ClearAllPoints()
        f.art:SetPoint("TOPLEFT", f, "TOPLEFT", one, -one)
        f.art:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -one, one)
    end
    local rows = math.ceil(#item.list / per)
    return rows * s + math.max(0, rows - 1) * gap
end

function place.hints(p, item, y)
    if #item.list == 0 then return 0 end
    for i, fs in ipairs(item.list) do
        fs:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -(y + (i - 1) * Panel.HINT_H))
    end
    return #item.list * Panel.HINT_H - (Panel.HINT_H - lineHeight(item.list[1], item.list[1].size))
end

local SPACED = { rule = false, gap = false }

-- Lays the card out. Returns its width and height.
function Panel.Finish(p)
    p:SetScale(Panel.Scale())
    local widest = 0
    for i = 1, p.count do widest = math.max(widest, natural(p.items[i])) end
    local most = Panel.WIDTH[p.kind] or Panel.WIDTH.other
    -- Rounded up: a card a fraction short of its widest text cut it with "...".
    local w = math.ceil(math.min(most, math.max(Panel.MIN_W, widest + 2 * padX(p))))
    if Panel.FIXED[p.kind] then w = most end
    local inner = w - 2 * padX(p)
    local y, last = p.padTop or Panel.PAD_TOP, nil
    local rowGap = p.rowGap or Panel.ROW_GAP
    for i = 1, p.count do
        local item = p.items[i]
        -- Rows sit ROW_GAP apart; a rule or a gap brings its own room.
        if last and SPACED[item.kind] ~= false and SPACED[last] ~= false then y = y + rowGap end
        item.y = y
        y = y + place[item.kind](p, item, y, inner)
        last = item.kind
    end
    local h = math.floor(y + Panel.PAD_BOTTOM + 0.5)
    p.wantW, p.wantH = w, h
    Panel.Pin(p)
    Panel.PaintLight(p)
    Panel.PaintWash(p)
    p.shell:Show()
    p:Show()
    return w, h
end

-- The top light: the pair from left to right, inside the outline. With fade,
-- its right 60% runs from the light end down to 15% (an item's quality).
function Panel.PaintLight(p)
    local pair = p.lightPair
    local a, b = p.light[1], p.light[2]
    if not pair then
        a:Hide()
        b:Hide()
        return
    end
    local one = DUI.Pixel.Px(p, 1)
    local lo, hi = pair[1], pair[2]
    p.track:ClearAllPoints()
    p.track:SetPoint("TOPLEFT", p, "TOPLEFT", one, -one)
    p.track:SetPoint("TOPRIGHT", p, "TOPRIGHT", -one, -one)
    p.track:SetHeight(Panel.LIGHT_H)
    a:ClearAllPoints()
    b:ClearAllPoints()
    a:SetPoint("TOPLEFT", p, "TOPLEFT", one, -one)
    a:SetHeight(Panel.LIGHT_H)
    a:SetVertexColor(1, 1, 1, 1)
    if p.lightFade then
        a:SetPoint("RIGHT", p, "LEFT", one + (p.wantW or 200) * 0.4, 0)
        b:SetPoint("TOPLEFT", a, "TOPRIGHT", 0, 0)
        b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -one, -one)
        b:SetHeight(Panel.LIGHT_H)
        b:SetVertexColor(1, 1, 1, 1)
        Style.Gradient(b, "HORIZONTAL", hi[1], hi[2], hi[3], 1, hi[1], hi[2], hi[3], 0.15)
        b:Show()
    else
        a:SetPoint("TOPRIGHT", p, "TOPRIGHT", -one, -one)
        b:Hide()
    end
    Style.Gradient(a, "HORIZONTAL", lo[1], lo[2], lo[3], 1, hi[1], hi[2], hi[3], 1)
    a:Show()
end

-- The header's wash: its color strong at the left, faint at 60%, gone by the
-- right edge, over the header's height.
function Panel.PaintWash(p)
    local c, a, b = p.washColor, p.wash[1], p.wash[2]
    -- The header: first, or under a compare card's tag.
    local header = p.items[1]
    for i = 1, math.min(p.count, 3) do
        if p.items[i].kind == "header" then
            header = p.items[i]
            break
        end
    end
    if not (c and header and header.kind == "header") then
        a:Hide()
        b:Hide()
        return
    end
    local w = p.wantW or 200
    a:ClearAllPoints()
    b:ClearAllPoints()
    if p.washDown then
        -- An item's: its quality from the top, gone by 80% of the header's height.
        local h = ((header.y or p.padTop or Panel.PAD_TOP) + (header.h or 0)) * 0.8
        a:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
        a:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
        a:SetHeight(h)
        a:SetVertexColor(1, 1, 1, 1)
        Style.Gradient(a, "VERTICAL", c[1], c[2], c[3], 0, c[1], c[2], c[3], Panel.WASH_DOWN)
        a:Show()
        b:Hide()
        return
    end
    local h = (p.padTop or Panel.PAD_TOP) + (header.h or 0) + 12
    local s = Panel.WASH_ALPHA
    a:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    a:SetSize(w * 0.6, h)
    b:SetPoint("TOPLEFT", a, "TOPRIGHT", 0, 0)
    b:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    b:SetHeight(h)
    a:SetVertexColor(1, 1, 1, 1)
    b:SetVertexColor(1, 1, 1, 1)
    Style.Gradient(a, "HORIZONTAL", c[1], c[2], c[3], s, c[1], c[2], c[3], s * 0.27)
    Style.Gradient(b, "HORIZONTAL", c[1], c[2], c[3], s * 0.27, c[1], c[2], c[3], 0)
    a:Show()
    b:Show()
end

-- The top light's sweep: a brighter band of color runs along it once, left to
-- right, over SLOW. Nothing with Motion off or in a fight.
Panel.SWEEP_LIFT = 0.5
function Panel.Sweep(p, c)
    local M = DUI.Motion
    if InCombatLockdown() or not (p.lightPair and type(c) == "table" and M.On()) then return end
    local k = Panel.SWEEP_LIFT
    local r, g, b = c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k
    local left, right = p.sweep.halves[1], p.sweep.halves[2]
    left:SetVertexColor(1, 1, 1, 1)
    right:SetVertexColor(1, 1, 1, 1)
    Style.Gradient(left, "HORIZONTAL", r, g, b, 0, r, g, b, 1)
    Style.Gradient(right, "HORIZONTAL", r, g, b, 1, r, g, b, 0)
    p.sweep:SetHeight(Panel.LIGHT_H)
    M.Sweep(p.sweep, p.track, { width = Panel.SWEEP_W, dur = M.SLOW, inset = Panel.SWEEP_W / 2, key = p.sweep })
end

-- The card at its own size from the first frame, pinned at the corner the
-- tooltip is anchored by (the one that stays put as it resizes): the tooltip
-- may take its padding a frame late, and a card stretched over it showed
-- itself rearranging.
function Panel.Pin(p)
    local tip, point = p.tip, "TOPLEFT"
    if tip:GetNumPoints() == 1 then
        local at = tip:GetPoint(1)
        if type(at) == "string" and not isSecret(at) then point = at end
    end
    if p.pinned ~= point then
        p:ClearAllPoints()
        p:SetPoint(point, tip, point, 0, 0)
        p.pinned = point
    end
    p:SetSize(p.wantW, p.wantH)
end

-- New content in a card that's already showing (another bag slot, another
-- enemy): its words fade in over FAST, the frame stays. Not in a fight: what
-- a fight needs shows at once.
function Panel.FadeBody(p)
    local M = DUI.Motion
    if InCombatLockdown() or not M.On() then
        M.AlphaTo(p.body, 1, 0)
        return
    end
    p.body:SetAlpha(0)
    M.AlphaTo(p.body, 1, M.FAST)
end

-- Only the frame (a secret line): no pieces, sized by the game.
function Panel.Chrome(p)
    Panel.Begin(p, p.kind, p.lightPair, p.lightFade)
    p.chrome = true
    p.wantW, p.wantH = nil, nil
    if p.pinned then
        p:ClearAllPoints()
        p:SetAllPoints(p.tip)
        p.pinned = nil
    end
    Panel.PaintLight(p)
    Panel.PaintWash(p)
    p:Show()
end

-- ---------------------------------------------------------------------
-- Fitting the game's tooltip to the card
-- ---------------------------------------------------------------------

-- Pads the game's tooltip so it's exactly the card's size: the padding needed
-- is read from how far off it is now, so it holds whatever the game's own
-- lines and edges measure. SetPadding resizes the tooltip at once. A padding
-- below zero shrinks a tooltip whose own lines are bigger than the card.
-- Returns false when the size can't be read (a secret line).
function Panel.Fit(p)
    local tip = p.tip
    if p.chrome or not p.wantW then return true end
    local w, h = tip:GetWidth(), tip:GetHeight()
    if isSecret(w) or isSecret(h) or type(w) ~= "number" or type(h) ~= "number" then return false end
    -- The card's size in the tooltip's own units.
    local k = p:GetScale() or 1
    local dw, dh = p.wantW * k - w, p.wantH * k - h
    if math.abs(dw) < 0.5 and math.abs(dh) < 0.5 then return true end
    -- Tried once already this fill and it didn't move: the client won't take
    -- that padding. Leave it rather than ask every frame.
    if p.fitTried and math.abs(p.fitTried[1] - w) < 0.5 and math.abs(p.fitTried[2] - h) < 0.5 then return true end
    local r, b, l, t = tip:GetPadding()
    r, b, l, t = tonumber(r) or 0, tonumber(b) or 0, tonumber(l) or 0, tonumber(t) or 0
    tip:SetPadding(r + dw, b + dh, l, t)
    p.fitTried = { w, h }
    return true
end

-- ---------------------------------------------------------------------
-- The game's own lines under the card
-- ---------------------------------------------------------------------

local function muteRegions(muted, ...)
    for i = 1, select("#", ...) do
        local r = select(i, ...)
        if type(r) == "table" and r.SetAlpha then
            muted[r] = true
            r:SetAlpha(0)
        end
    end
end

-- Every text and texture of the tooltip itself (its lines, their icons) and
-- its money frames go to alpha 0. Frames other addons hang on it stay.
function Panel.Mute(p)
    local tip = p.tip
    p.muted = p.muted or setmetatable({}, { __mode = "k" })
    muteRegions(p.muted, tip:GetRegions())
    local money = tip.shownMoneyFrames
    if type(money) == "table" then
        for _, f in pairs(money) do muteRegions(p.muted, f) end
    end
    -- A compare tooltip's "Equipped" tab: the card says it in its own tag.
    if type(tip.CompareHeader) == "table" then muteRegions(p.muted, tip.CompareHeader) end
end

function Panel.Unmute(p)
    if not (p and p.muted) then return end
    for r in pairs(p.muted) do
        p.muted[r] = nil
        r:SetAlpha(1)
    end
end

-- The card goes, the game's lines come back and the padding is given back.
function Panel.Release(p)
    if not p then return end
    Panel.Unmute(p)
    if p.fitTried then
        local tip = p.tip
        local _, _, l, t = tip:GetPadding()
        tip:SetPadding(0, 0, tonumber(l) or 0, tonumber(t) or 0)
    end
    p.wantW, p.wantH, p.fitTried = nil, nil, nil
    p:Hide()
end
