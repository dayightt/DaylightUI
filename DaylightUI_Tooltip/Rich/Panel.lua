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
Panel.MIN_W = 160
Panel.TEXT_ROOM = 1.05 -- the game draws a line a little wider than it measures
Panel.SHRINK_MIN = 0.7  -- a title's longest word may shrink the letters this far to fit
Panel.GROW = 1.3       -- a fixed card widens this much at most, for a long tag or tile
-- Each kind's card is as wide as its board; anything else is as wide as it
-- needs, up to "other".
Panel.WIDTH = { unit = 300, mob = 260, node = 210, item = 290, compare = 290, spell = 270, other = 280 }
Panel.FIXED = { unit = true, mob = true, node = true, item = true, compare = true, spell = true }
Panel.TAG_GAP, Panel.TILE_GAP = 6, 4
Panel.TAG_ROW_GAP = 4  -- between two rows of a header's tags
Panel.RULE_ALPHA = 0.25
Panel.SHADE = 0.45     -- a bar colored from a curve: its dark end, as black over the fill
Panel.BUFF, Panel.BUFF_GAP = 22, 4
Panel.WASH_ALPHA = 0.22
Panel.WASH_DOWN = 0.16 -- an item's wash, top to bottom
Panel.SWEEP_W = 70     -- the quality light's sweep
-- Lines measured with no font metrics (the tests) are this tall per size.
Panel.LINE_EXTRA = 3
Panel.LINE_SPACING = 3 -- between the lines of a wrapped sentence

local panels = setmetatable({}, { __mode = "k" }) -- tooltip -> panel

-- Whether a card switch is on (a missing one is: every one defaults on).
function Panel.Wants(key)
    local c = ns.Tooltip.Config()
    return not (type(c) == "table" and DUI.DB.GetPath(c, key) == false)
end

-- Compact rows (the "Row spacing" setting): every card's rows and rules
-- closer together.
Panel.COMPACT_ROW_GAP, Panel.COMPACT_RULE_GAP = 3, 6
function Panel.Compact()
    local c = ns.Tooltip.Config()
    return type(c) == "table" and c.cardRows == "compact"
end

-- The cards' width setting (times each kind's own width).
function Panel.WidthScale()
    local c = ns.Tooltip.Config()
    local k = type(c) == "table" and tonumber(c.cardWidth) or 1
    return math.max(0.8, math.min(1.3, k or 1))
end

-- The cut corner, unless switched off.
function Panel.Cut(p)
    local cut = Panel.Wants("cardCut") and Panel.CUT or 0
    if Style.GetCut(p) ~= cut then Style.CutShell(p, cut) end
end

local function W() return DUI.Widgets end
local function font() return ns.MEDIA and ns.MEDIA.font end

-- The card is laid out in the boards' own numbers (title 18, rows 13, 300
-- wide) and drawn at Panel.CARD, so its rows sit near a tooltip's usual text
-- size (12) and its title near a tooltip's heading: at 1 it read far bigger
-- than every other tooltip. The tooltip text size setting (12 by default)
-- scales the whole card with it, and the card reads Panel.LIFT steps above
-- that size, as its rows sit looser than a plain tooltip's.
Panel.CARD = 0.85
Panel.LIFT = 1
function Panel.Scale()
    local cfg = ns.Tooltip.Config()
    return Panel.CARD * ((cfg and tonumber(cfg.textSize) or 12) + Panel.LIFT) / 12
end

-- Which part of the tooltip a card size is, for that part's size and font
-- settings: "title" (a card's title and headings), "small" (sub lines, small
-- facts, captions), or nil for the text.
function Panel.Part(s)
    if s >= Style.SIZE.head then return "title" end
    if s <= Style.SIZE.small then return "small" end
end

-- The card is already scaled by the text size, so a title or small text only
-- grows by how far its own size sits from where it would be at that text
-- size (the defaults' gap kept).
local function size(s, part)
    part = part or Panel.Part(s)
    if not part then return s end
    local cfg, D = ns.Tooltip.Config(), ns.DEFAULTS
    local key = part .. "Size"
    local text = cfg and tonumber(cfg.textSize) or D.textSize
    local want = cfg and tonumber(cfg[key]) or D[key]
    return s * want / math.max(1, text + D[key] - D.textSize)
end

local function slotOf(s)
    local part = Panel.Part(s)
    return part and ns.MEDIA.fonts[part] or font()
end

-- A one-line text's height comes from its size alone, measured once per
-- layout on a hidden ruler in the same font. Read from each row's own text it
-- came out a few pixels different line to line, so a list of stats sat at
-- uneven gaps.
Panel.RULER = "Ag"
local measuring -- the panel being laid out, while Finish runs
local function lineHeight(s, slot)
    local p = measuring
    if p then
        slot = slot or font()
        local cache = p.heights[slot]
        if not cache then
            cache = {}
            p.heights[slot] = cache
        end
        if cache[s] then return cache[s] end
        local r = p.ruler
        if not r then
            r = Style.Text(p.body or p, s, "LEFT", font())
            r:SetWordWrap(false)
            r:Hide()
            p.ruler = r
            r.slot = font()
        end
        if r.slot ~= slot then
            r.slot = slot
            Style.SetTextSlot(r, slot)
        end
        Style.SetTextSize(r, s)
        r:SetText(Panel.RULER)
        local h = r:GetStringHeight()
        if type(h) ~= "number" or isSecret(h) or h <= 0 then h = s + Panel.LINE_EXTRA end
        cache[s] = h
        return h
    end
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

-- Plugins painting the card (API Paint kind "tooltip"): its pieces by name,
-- and whether one claimed a piece (then Daylight UI leaves its color alone).
function Panel.Owned(part)
    local R = DUI.APIReport
    return R ~= nil and R.Owned ~= nil and R.Owned("tooltip", part)
end

function Panel.Parts(p)
    local parts = p.parts or {}
    p.parts = parts
    parts.panel, parts.light, parts.banner = p, p.light, p.wash
    parts.icon, parts.title, parts.bar, parts.dps = nil, nil, nil, nil
    for i = 1, p.count do
        local item = p.items[i]
        if item.kind == "header" and not parts.title then
            parts.title = item.title
            parts.icon = item.icon and item.icon.art or nil
        elseif item.kind == "bar" and not parts.bar then
            parts.bar = item.bar
        elseif item.big and not parts.dps then
            parts.dps = item.fs
        end
    end
    return parts
end

if DUI.APIReport and DUI.APIReport.Parts then
    DUI.APIReport.Parts("tooltip", Panel.Parts)
    -- A claim began or ended: the card is laid out again before the next draw.
    DUI.APIReport.Repainter("tooltip", function(p) ns.Rich.Refresh(p.tip) end)
end

function Panel.For(tip)
    local p = panels[tip]
    if p then return p end
    p = CreateFrame("Frame", nil, tip)
    p:SetAllPoints(tip)
    p:EnableMouse(false)
    p:Hide()
    p.tip = tip
    -- The tooltip's own X (a clicked link) follows the card as it comes and goes.
    p:HookScript("OnShow", function() ns.Tooltip.PlaceClose(tip, true) end)
    p:HookScript("OnHide", function() ns.Tooltip.PlaceClose(tip, false) end)
    p.shell = Style.Shell(p, { look = ns.Tooltip.LOOK, cornerPx = 0, noBevel = true, bgAlpha = ns.Tooltip.BackAlpha("rich") })
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
    if DUI.APIReport then DUI.APIReport.Made("tooltip", p) end
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
    if spec.card and Panel.Owned("bar") then return end
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

-- A pooled text that once showed a secret (a unit's name or health in a
-- fight) keeps reading as one after it gets plain text: its text and width
-- come back secret, and inline icons like coins don't draw (seen in game).
-- SetToDefaults clears that, and takes the font and shadow with it.
local function unsecret(fs)
    if type(fs.HasAnySecretAspect) ~= "function" or fs:HasAnySecretAspect() ~= true then return end
    fs:SetToDefaults()
    fs:SetShadowOffset(Style.TEXT_SHADOW[1], Style.TEXT_SHADOW[2])
    fs:SetDrawLayer("OVERLAY")
    fs:Show()
    fs.slot = nil
end

local function text(p, s, c, wrap, part)
    local fs = take(p, "text")
    unsecret(fs)
    local slot = part and font() or slotOf(s)
    if fs.slot ~= slot then
        fs.slot = slot
        Style.SetTextSlot(fs, slot)
    end
    local z = size(s, part)
    Style.SetTextSize(fs, z)
    fs.size = z
    fs:SetWidth(0)
    fs:SetWordWrap(wrap and true or false)
    fs:SetMaxLines(0)
    -- A wrapped sentence's lines ran into each other without it.
    fs:SetSpacing(wrap and Panel.LINE_SPACING or 0)
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
    p.tagSpots = {}
    p.padX, p.padTop, p.rowGap, p.ruleGap = nil, nil, nil, nil
    p.chrome = false
end

-- spec: icon (file or id) or portrait (a unit: its face), iconSize, iconCoords ({ l, r, t, b }, else the
-- square crop), iconTile ({ lo, hi }: a gradient tile behind it), iconInset
-- (the art this far inside the tile), iconEdge ({ r, g, b }: an outline and glow),
-- iconGap (between the icon and the words, 12), title, titleColor, titleSize,
-- right, rightColor, rightSize (body), tags = { { text, color, edge? } }, sub (a line under the title),
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
        item.right = text(p, spec.rightSize or Style.SIZE.body, spec.rightColor or Style.INK.VALUE)
        item.right:SetText(spec.right)
    end
    if spec.sub then
        item.sub = text(p, Style.SIZE.small, Style.INK.LABEL)
        item.sub:SetText(spec.sub)
    end
    -- A Daylight UI plugin's tags (lines.Tag) after the card's own.
    local extra = p.extraTags
    if spec.tags or extra then
        item.tags = {}
        for _, list in ipairs({ spec.tags or false, extra or false }) do
            for _, t in ipairs(list or {}) do
                local tag = take(p, "tag")
                tag.Set(t[1], t[2], t[3])
                item.tags[#item.tags + 1] = tag
            end
        end
    end
    p.washColor = spec.wash
end

-- A label on the left, its value on the right. s: their text size (body);
-- valueSize lets the value stand out bigger than its label (a sell price).
-- wrap: a label too long for its room wraps onto more lines instead of being cut
-- (not a secret one, which can't be measured).
function Panel.Row(p, label, value, valueColor, labelColor, s, valueSize, wrap)
    wrap = wrap and type(label) == "string" and not isSecret(label)
    local item = add(p, { kind = "row", wrap = wrap or nil, words = label })
    item.label = text(p, s or Style.SIZE.body, labelColor or Style.INK.LABEL, wrap)
    item.label:SetText(label or "")
    if value and value ~= "" then
        item.value = text(p, valueSize or s or Style.SIZE.body, valueColor or Style.INK.VALUE)
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
    -- Secret words can't be measured: they get the whole room, cut there.
    local item = add(p, { kind = "line", secret = isSecret(words) })
    item.fs = text(p, s or Style.SIZE.body, color or Style.INK.TEXT)
    item.fs:SetText(words or "")
    if tail then
        item.tail = text(p, tailSize or Style.SIZE.small, tailColor or Style.INK.LABEL)
        item.tail:SetText(tail)
    end
end

-- A weapon's damage per second, the one number a glance at a weapon wants:
-- a line of its own, bigger than the rows, sized by its own setting (dps).
Panel.DPS = 16
function Panel.Big(p, words)
    local item = add(p, { kind = "line", big = true, secret = isSecret(words) })
    item.fs = text(p, Panel.DPS, Style.INK.TEXT, false, "dps")
    item.fs:SetText(words or "")
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
    spec.card = true -- a card's bar (the pill's are its own), for a plugin's claim
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
-- Not once the unit is gone (the mouse left it): its token then answers no
-- health, and the bar would empty to black while the card fades out.
function Panel.UpdateBars(p)
    for i = 1, p.count do
        local item = p.items[i]
        if item.kind == "bar" and item.spec.unit and not isSecret(UnitExists(item.spec.unit))
            and UnitExists(item.spec.unit) == true then
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
        tag.Set(t[1], t[2], t[3])
        item.list[i] = tag
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

-- What a tile's words need across.
local function tileWidth(t)
    if t.Need then
        local w = t.Need()
        if w > 2 * W().TILE_PAD then return w end
    end
    return math.max(widthOf(t.value), widthOf(t.caption)) + 2 * W().TILE_PAD
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
        return widthOf(item.label) + (item.value and (Panel.ROW_GAP_X + widthOf(item.value)) or 0)
    elseif k == "text" or k == "section" then
        return widthOf(item.fs)
    elseif k == "line" then
        return widthOf(item.fs) + (item.tail and (4 + widthOf(item.tail)) or 0)
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

-- What a fixed-width card makes room for beyond its board's width: its tiles
-- side by side, and another addon's row that keeps its two sides on one line
-- that way (its `need`, set by Foreign's row). Nothing else (a title and a
-- sentence wrap).
local function needed(item)
    local k, w = item.kind, 0
    if k == "row" and item.need then return item.need end
    if k == "tiles" then
        w = (#item.list - 1) * Panel.TILE_GAP
        for _, t in ipairs(item.list) do w = w + tileWidth(t) end
    end
    return w
end

-- Each piece placed from the panel's top-left at y (going down) and across
-- the inside width; returns its height.
-- A card's own spacing (Begin clears them): padX, padTop, rowGap, ruleGap.
local function padX(p) return p.padX or Panel.PAD_X end

local place = {}

-- A tag on whole screen pixels, height too: its outline is one pixel thick and
-- drawn through a mask, so off the pixel grid its top or bottom line is lost.
-- The grid is the screen's, not the card's: the card sits wherever the game
-- put the tooltip, so each tag's offset is worked out from where the card is
-- (alignTags, once laid out and again a frame later, when the game has put it).
local function alignTag(p, spot)
    local snap = DUI.Pixel.Snap
    local tag, x, y = spot[1], spot[2], spot[3]
    local l, t = p:GetLeft(), p:GetTop()
    if type(l) == "number" and type(t) == "number" and not isSecret(l) and not isSecret(t) then
        x = snap(p, l + x) - l
        y = t - snap(p, t - y)
    else
        x, y = snap(p, x), snap(p, y)
    end
    tag:ClearAllPoints()
    tag:SetPoint("TOPLEFT", p, "TOPLEFT", x, -y)
end

local function alignTags(p)
    for _, spot in ipairs(p.tagSpots) do alignTag(p, spot) end
    p.tagsAt = { p:GetLeft(), p:GetTop() }
end

-- The card moves with its tooltip (with the cursor, a padding that grows it
-- from its bottom corner, a mirrored side), and each move can leave the tags
-- between screen pixels, their outline's top or bottom line gone (seen in
-- game at UI scale 0.71). From the tooltip's update: the tags are put back on
-- the grid whenever the card has moved since they last were.
function Panel.KeepTags(p)
    local spots, at = p.tagSpots, p.tagsAt
    if not (spots and spots[1]) then return end
    local l, t = p:GetLeft(), p:GetTop()
    if isSecret(l) or isSecret(t) or type(l) ~= "number" or type(t) ~= "number" then return end
    if at and at[1] == l and at[2] == t then return end
    alignTags(p)
end

local function snapTag(p, tag, x, y)
    tag:SetHeight(math.max(DUI.Pixel.Px(tag, 1), DUI.Pixel.Snap(tag, tag:GetHeight())))
    local spot = { tag, x, y }
    p.tagSpots[#p.tagSpots + 1] = spot
    alignTag(p, spot)
end

-- The widest single word of a text, measured on the fs itself (its text put
-- back after).
local function longestWord(fs, text)
    if type(text) ~= "string" then return 0 end
    local best = 0
    for word in text:gmatch("%S+") do
        fs:SetText(word)
        best = math.max(best, widthOf(fs))
    end
    fs:SetText(text)
    return best
end

-- How many lines a text takes wrapped at room, word by word as the client
-- wraps it, measured on the fs itself (its text put back after). At least 2:
-- it's only asked once the text is already too wide for one.
Panel.TITLE_LINES = 3
local function wrappedLines(fs, text, room)
    if type(text) ~= "string" then return 2 end
    local lines, row = 1, ""
    for word in text:gmatch("%S+") do
        local try = row == "" and word or (row .. " " .. word)
        fs:SetText(try)
        if row ~= "" and widthOf(fs) > room then
            lines, row = lines + 1, word
        else
            row = try
        end
    end
    fs:SetText(text)
    return math.max(2, lines)
end

function place.header(p, item, y, inner)
    local x = padX(p)
    local spec, h = item.spec, 0
    if item.icon then
        local s = spec.iconSize or 36
        local ic = item.icon
        ic:SetSize(s, s)
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
    local one = lineHeight(item.title.size, item.title.slot)
    local th = one
    -- Never past the card's edge (or the level beside it). A long name wraps
    -- onto a second line rather than losing its end ("of Healing" is the point).
    local room = inner + padX(p) - x - (item.right and (12 + widthOf(item.right)) or 0)
    -- A clicked item's popup has the game's X in its top right corner.
    local close = p.tip and p.tip.CloseButton
    if type(close) == "table" and close:IsShown() then room = room - 18 end
    if isSecret(item.spec.title) then
        -- A secret name can't be measured: it gets the whole room, cut there.
        item.title:SetWidth(room)
    elseif widthOf(item.title) > room + 1 then
        -- A word wider than the row can't wrap: the letters shrink to fit it
        -- (down to SHRINK_MIN) instead of ending in "...".
        local word = longestWord(item.title, item.spec.title)
        if word > room then
            local z = item.title.size * math.max(Panel.SHRINK_MIN, room / word)
            Style.SetTextSize(item.title, z)
            item.title.size = z
            one = lineHeight(z, item.title.slot)
            th = one
        end
    end
    if not isSecret(item.spec.title) and widthOf(item.title) > room + 1 then
        -- As many lines as its words need (a book page's long name on a narrow
        -- card took three), so it never ends in "...".
        local lines = math.min(Panel.TITLE_LINES, wrappedLines(item.title, item.spec.title, room))
        item.title:SetWidth(room)
        item.title:SetWordWrap(true)
        item.title:SetMaxLines(lines)
        item.title:SetSpacing(Panel.LINE_SPACING)
        th = lines * one + (lines - 1) * Panel.LINE_SPACING
    end
    -- Everything under the title has the room right of the icon, the whole way.
    local wide = inner + padX(p) - x
    local col = th
    local subH = 0
    if item.sub then
        -- A long sub line ("Companion of ..." in German) wraps onto a second
        -- line rather than running to the card's edge.
        local sh = lineHeight(item.sub.size, item.sub.slot)
        subH = sh
        if isSecret(item.spec.sub) then
            item.sub:SetWidth(wide)
        elseif widthOf(item.sub) > wide + 1 then
            item.sub:SetWidth(wide)
            item.sub:SetWordWrap(true)
            item.sub:SetMaxLines(2)
            item.sub:SetSpacing(Panel.LINE_SPACING)
            subH = 2 * sh + Panel.LINE_SPACING
        end
        col = col + 2 + subH
    end
    local tagGap = spec.tagGap or 5
    local rows = {}
    -- Tags sit beside the icon, under the words, while each fits on one row
    -- there. A tag that would wrap (a long "Consumable - Food & Drink" in
    -- Spanish) moves them all under the icon instead, across the card's whole
    -- width, so no tag is two lines tall next to a short icon.
    local under = false
    local tagRoom = wide
    if item.tags and #item.tags > 0 then
        for _, tag in ipairs(item.tags) do
            if tag:GetWidth() > wide then under = true end
        end
        if under then tagRoom = inner end
        -- As many rows as the tags need; a tag longer than a whole row wraps
        -- its own words (W.Tag's FitTo) and its row grows.
        local tx = 0
        rows[1] = W().TAG_H
        for _, tag in ipairs(item.tags) do
            local tagH = tag.FitTo and tag.FitTo(tagRoom) or W().TAG_H
            local w = tag:GetWidth()
            if tx > 0 and tx + w > tagRoom then
                rows[#rows + 1], tx = W().TAG_H, 0
            end
            tag.row, tag.at = #rows, tx
            rows[#rows] = math.max(rows[#rows], tagH)
            tx = tx + w + Panel.TAG_GAP
        end
    end
    local rowsH = 0
    for i, rh in ipairs(rows) do rowsH = rowsH + rh + (i > 1 and Panel.TAG_ROW_GAP or 0) end
    local beside = #rows > 0 and not under
    if beside then col = col + tagGap + rowsH end
    -- Shorter than the icon, the words sit in the middle of its height; taller
    -- (a wrapped name), the icon sits in the middle of theirs.
    local block = math.max(h, col)
    local top = y + (block - col) / 2
    if item.icon then
        -- With tags beside it the icon keeps the top; without, it sits in the
        -- middle of a taller (wrapped) name.
        local drop = beside and 0 or (block - h) / 2
        item.icon:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -(y + drop))
    end
    item.title:SetPoint("TOPLEFT", p, "TOPLEFT", x, -top)
    if item.right then
        -- On the title's baseline, at the right edge (a mob's level).
        item.right:SetPoint("TOPRIGHT", p, "TOPRIGHT", -padX(p), -(top + one - lineHeight(item.right.size, item.right.slot)))
    end
    local ty = top + th
    if item.sub then
        item.sub:SetPoint("TOPLEFT", p, "TOPLEFT", x, -(ty + 2))
        ty = ty + 2 + subH
    end
    if #rows > 0 then
        local rowY = {}
        local tagX = x
        local at = ty + tagGap
        if under then
            tagX = padX(p)
            at = y + block + tagGap
        end
        for i, rh in ipairs(rows) do
            rowY[i] = at
            at = at + rh + Panel.TAG_ROW_GAP
        end
        for _, tag in ipairs(item.tags) do
            snapTag(p, tag, tagX + tag.at, rowY[tag.row])
        end
        ty = at - Panel.TAG_ROW_GAP
    end
    item.h = math.max(block, ty - y)
    return item.h
end

-- The value keeps its own width at the right edge; only a label too long for
-- what's left is cut. Squeezed between the label and the edge, a value was
-- cut with "..." whenever the card was exactly as wide as its widest row.
Panel.ROW_GAP_X = 16
function place.row(p, item, y, inner)
    local h = lineHeight(item.label.size, item.label.slot)
    local drop = 0
    if item.value then
        item.value:SetPoint("TOPRIGHT", p, "TOPRIGHT", -padX(p), -y)
        local room = inner - widthOf(item.value) - Panel.ROW_GAP_X
        if widthOf(item.label) > room + 1 then
            item.label:SetWidth(math.max(1, room))
            -- A secret label can't be measured or split into words: it stays cut.
            if item.wrap and type(item.words) == "string" and not isSecret(item.words) then
                local sh = item.label:GetStringHeight()
                if type(sh) == "number" and not isSecret(sh) and sh > h then
                    h = sh
                else
                    local lines = wrappedLines(item.label, item.words, room)
                    h = lines * h + (lines - 1) * Panel.LINE_SPACING
                end
            end
        end
        -- A bigger value: the label sits on the same baseline, not up at its top.
        local vh = lineHeight(item.value.size, item.value.slot)
        if vh > h then drop, h = vh - h, vh end
    end
    item.label:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -(y + drop))
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
    return lines * (fs.size + Panel.LINE_EXTRA) + (lines - 1) * Panel.LINE_SPACING
end

function place.section(p, item, y, inner)
    local fs = item.fs
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -y)
    local one = lineHeight(fs.size, fs.slot)
    -- A quest's name and its tags can be longer than the card: they wrap onto a
    -- second line (the game's measure is a little short, hence the margin).
    if widthOf(fs) * Panel.TEXT_ROOM > inner then
        fs:SetWidth(inner)
        fs:SetWordWrap(true)
        fs:SetMaxLines(2)
        fs:SetSpacing(Panel.LINE_SPACING)
        return 2 * one + Panel.LINE_SPACING
    end
    return one
end

function place.line(p, item, y, inner)
    local fs, tail = item.fs, item.tail
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p), -y)
    local room = inner - (tail and (4 + widthOf(tail)) or 0)
    if item.secret or widthOf(fs) > room + 1 then fs:SetWidth(math.max(1, room)) end
    local h = lineHeight(fs.size, fs.slot)
    if tail then
        -- On the line's baseline.
        tail:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 4, 0)
        h = math.max(h, lineHeight(tail.size, tail.slot))
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
    -- Equal widths; when one's words need more, each takes what its words
    -- need and the rest is shared out, so none is cut.
    local nat, total, tight = {}, (n - 1) * Panel.TILE_GAP, false
    for i, t in ipairs(item.list) do
        nat[i] = tileWidth(t)
        total = total + nat[i]
        if nat[i] > w + 0.5 then tight = true end
    end
    local x = 0
    for i, t in ipairs(item.list) do
        local tw = w
        if tight then tw = nat[i] + math.max(0, inner - total) / n end
        if tight and total > inner then tw = nat[i] * inner / total end
        t:SetSize(tw, W().TILE_H)
        t:SetPoint("TOPLEFT", p, "TOPLEFT", padX(p) + x, -y)
        x = x + tw + Panel.TILE_GAP
        Style.LayoutShell(Style.GetShell(t))
    end
    return W().TILE_H
end

function place.tags(p, item, y, inner)
    local x, row = 0, 0
    for _, tag in ipairs(item.list) do
        if tag:GetWidth() > inner then tag.FitWidth(inner) end
        local w = tag:GetWidth()
        if x > 0 and x + w > inner then
            x, row = 0, row + 1
        end
        snapTag(p, tag, padX(p) + x, y + row * (W().TAG_H + 4))
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

local SPACED = { rule = false, gap = false }

-- Lays the card out. Returns its width and height.
function Panel.Finish(p)
    p:SetScale(Panel.Scale())
    local widest = 0
    for i = 1, p.count do widest = math.max(widest, natural(p.items[i])) end
    local most = (Panel.WIDTH[p.kind] or Panel.WIDTH.other) * Panel.WidthScale()
    if Panel.Compact() then p.rowGap, p.ruleGap = Panel.COMPACT_ROW_GAP, Panel.COMPACT_RULE_GAP end
    -- Rounded up: a card a fraction short of its widest text cut it with "...".
    local w = math.ceil(math.min(most, math.max(Panel.MIN_W, widest + 2 * padX(p))))
    if Panel.FIXED[p.kind] then
        local need = 0
        for i = 1, p.count do need = math.max(need, needed(p.items[i])) end
        w = math.ceil(math.min(most * Panel.GROW, math.max(most, need + 2 * padX(p))))
    end
    local inner = w - 2 * padX(p)
    local y, last = p.padTop or Panel.PAD_TOP, nil
    local rowGap = p.rowGap or Panel.ROW_GAP
    -- Measured again each layout: the font or the size settings may have changed.
    p.heights = {}
    measuring = p
    for i = 1, p.count do
        local item = p.items[i]
        -- Rows sit ROW_GAP apart; a rule or a gap brings its own room.
        if last and SPACED[item.kind] ~= false and SPACED[last] ~= false then y = y + rowGap end
        item.y = y
        -- Its height, for the Design sample's hotspots (Rich/Design.lua).
        item.tall = place[item.kind](p, item, y, inner)
        y = y + item.tall
        last = item.kind
    end
    measuring = nil
    local h = math.floor(y + Panel.PAD_BOTTOM + 0.5)
    p.wantW, p.wantH = w, h
    Panel.Pin(p)
    Panel.Cut(p)
    alignTags(p)
    -- Where the game puts the tooltip may come a frame later.
    C_Timer.After(0, function() if p:IsShown() then alignTags(p) end end)
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
    -- A plugin painting the light (API Paint "tooltip", owns "light") colors it.
    if Panel.Owned("light") then return end
    if not pair or not Panel.Wants("cardLight") then
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
    if not (c and header and header.kind == "header") or not Panel.Wants("cardWash") then
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
    if InCombatLockdown() or not (p.lightPair and type(c) == "table" and M.On() and Panel.Wants("cardLight")) then return end
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

-- The card laid over a whole frame (its tooltip, or the ghost carrying it).
-- It forgets its pin, so the next Panel.Pin holds it by its corner again:
-- left stretched over the tooltip, every refill that resized the tooltip
-- showed on the card as a flicker.
function Panel.Stretch(p, over)
    p:ClearAllPoints()
    p:SetAllPoints(over)
    p.pinned = nil
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
    p.wantW, p.wantH, p.padded = nil, nil, nil
    if p.pinned then Panel.Stretch(p, p.tip) end
    Panel.Cut(p)
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
    local r, b, l, t = tip:GetPadding()
    r, b, l, t = tonumber(r) or 0, tonumber(b) or 0, tonumber(l) or 0, tonumber(t) or 0
    if math.abs(dw) < 0.5 and math.abs(dh) < 0.5 then
        p.padded = { r, b }
        return true
    end
    -- Tried once already this fill and it didn't move: the client won't take
    -- that padding. Leave it rather than ask every frame.
    if p.fitTried and math.abs(p.fitTried[1] - w) < 0.5 and math.abs(p.fitTried[2] - h) < 0.5 then return true end
    tip:SetPadding(r + dw, b + dh, l, t)
    p.fitTried = { w, h }
    p.padded = { r + dw, b + dh }
    return true
end

-- The tooltip was hidden and shown again in one frame (an owner's refill
-- starts with SetOwner, which hides it), and the game cleared its padding on
-- the way. The client takes a new padding only when it lays the frame out,
-- so the size read back is still the old one and measuring finds nothing to
-- fix: the cleared padding would win and draw the tooltip at its bare lines'
-- size for a frame, its compare tooltips jumping with its edge. The padding it
-- had goes back first; the fit then corrects it if the content changed.
function Panel.KeepSize(p)
    local kept = p and p.padded
    if not kept then return end
    local tip = p.tip
    local _, _, l, t = tip:GetPadding()
    tip:SetPadding(kept[1], kept[2], tonumber(l) or 0, tonumber(t) or 0)
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

-- Whether frame f draws anywhere over the tooltip. Frames are compared in
-- screen units, as an addon's frame may carry a scale of its own.
local function overTip(f, tip)
    local l, b, w, h = f:GetRect()
    local tl, tb, tw, th = tip:GetRect()
    if isSecret(l) or isSecret(b) or isSecret(w) or isSecret(h) or isSecret(tl) or isSecret(tb)
        or isSecret(tw) or isSecret(th) or type(l) ~= "number" or type(tl) ~= "number" then
        -- Unplaced or unreadable: it can't be shown to sit clear of the card.
        return true
    end
    local k, tk = f:GetEffectiveScale(), tip:GetEffectiveScale()
    l, b, w, h = l * k, b * k, w * k, h * k
    tl, tb, tw, th = tl * tk, tb * tk, tw * tk, th * tk
    return l < tl + tw and l + w > tl and b < tb + th and b + h > tb
end

-- The tooltip's own frames, and Daylight UI's on it, which the card handles
-- itself (the health bar, a clicked item's X) or which are already hidden.
local function ownChild(p, f)
    local tip = p.tip
    return f == p or f == ns.Tooltip.Shell(tip) or f == tip.NineSlice or f == tip.StatusBar
        or f == rawget(_G, "GameTooltipStatusBar") or f == tip.CloseButton or f == tip.ItemTooltip
        or f == tip.CompareHeader
end

-- Frames another addon lays over the tooltip (Forever Leveling BiS's upgrade
-- arrow, pinned to one of the game's lines) would draw on the card's rows, so
-- they go to alpha 0 too. One hanging beside the tooltip stays. Their own
-- alpha is kept for when the card goes.
local function muteChildren(p, ...)
    local muted = p.muted
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        if type(f) == "table" and f.SetAlpha and muted[f] == nil and not ownChild(p, f) and overTip(f, p.tip) then
            local a = f:GetAlpha()
            muted[f] = (type(a) == "number" and not isSecret(a)) and a or true
            f:SetAlpha(0)
        end
    end
end

-- Every text and texture of the tooltip itself (its lines, their icons), its
-- money frames and other addons' frames laid over it go to alpha 0.
function Panel.Mute(p)
    local tip = p.tip
    p.muted = p.muted or setmetatable({}, { __mode = "k" })
    muteRegions(p.muted, tip:GetRegions())
    p.regions = tip:GetNumRegions()
    muteChildren(p, tip:GetChildren())
    p.children = tip:GetNumChildren()
    -- The game keeps a count of them (SetTooltipMoney), each named
    -- <tooltip>MoneyFrame<n>.
    local money, name = tip.shownMoneyFrames, tip:GetName()
    if type(money) == "number" and not isSecret(money) and type(name) == "string" then
        for k = 1, money do muteRegions(p.muted, _G[name .. "MoneyFrame" .. k]) end
    end
    -- A compare tooltip's "Equipped" tab: the card says it in its own tag.
    if type(tip.CompareHeader) == "table" then muteRegions(p.muted, tip.CompareHeader) end
end

-- Another addon can make textures, texts and frames on the tooltip after the
-- card is built (Forever Leveling BiS draws boxes and an arrow on its lines).
-- Those would draw over the card, so new ones are hidden as they turn up.
function Panel.MuteNew(p)
    if not (p and p.muted) then return end
    local tip = p.tip
    if tip:GetNumRegions() ~= p.regions or tip:GetNumChildren() ~= p.children then Panel.Mute(p) end
end

function Panel.Unmute(p)
    if not (p and p.muted) then return end
    for r, was in pairs(p.muted) do
        p.muted[r] = nil
        r:SetAlpha(type(was) == "number" and was or 1)
    end
end

-- The card goes, the game's lines come back and the padding is given back.
function Panel.Release(p)
    if not p then return end
    Panel.Unmute(p)
    -- p.padded stays: a show in the same frame puts it back (Panel.KeepSize).
    if p.fitTried or p.padded then
        local tip = p.tip
        local _, _, l, t = tip:GetPadding()
        tip:SetPadding(0, 0, tonumber(l) or 0, tonumber(t) or 0)
    end
    p.wantW, p.wantH, p.fitTried = nil, nil, nil
    -- Lent to the tooltip's fading ghost: it hides the card as it hands it back.
    if not ns.TipGhost.Holds(p) then p:Hide() end
end
