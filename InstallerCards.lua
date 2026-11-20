-- Setup guide building blocks: picture cards (one choice among several, or an
-- action), a picker that lays out a row of them, the opening's showpiece
-- cards, the pictures on the question pages, and the small drawings inside
-- plugins' cards (a screen with frames, a health bar, a bag, a font sample, a color). Everything is drawn in code from the options
-- window's shapes and colors, so it follows the accent and needs no images.

local _, DUI = ...
local Style, W = DUI.Style, DUI.Widgets
local SIZE = DUI.Style.SIZE -- the text size scale
local C = W.COLORS
local L = DUI.L

local Cards = {}
DUI.InstallerCards = Cards

Cards.GAP = 10        -- between cards
Cards.LIFT = 2 -- how far a card rises on hover

-- A rounded panel with an outline that lifts on hover. When selected it gets
-- an accent outline and a tick in the corner. A tag is a small pill in that
-- corner instead ("Recommended for you", "In use"). Content goes on
-- card.inner, which is the part that lifts.
function Cards.Card(parent)
    local c = CreateFrame("Button", nil, parent)
    local inner = CreateFrame("Frame", nil, c)
    c.inner = inner
    local function place(dy)
        inner:ClearAllPoints()
        inner:SetPoint("TOPLEFT", c, "TOPLEFT", 0, dy)
        inner:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, dy)
    end
    place(0)
    inner.bg = W.Round(inner, "BACKGROUND")
    inner.bg:SetAllPoints(inner)
    W.Tint(inner.bg, C.card)
    inner.edge = W.Round(inner, "BORDER", 0, true)
    inner.edge:SetAllPoints(inner)
    c.tick = W.Icon(inner, "ui-check.png", 14, C.text, "OVERLAY")
    c.tick:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -10, -10)
    c.tick:Hide()
    c.tag = CreateFrame("Frame", nil, inner)
    c.tag:SetHeight(18)
    c.tag:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -8, -8)
    c.tag.bg = W.Round(c.tag, "ARTWORK")
    c.tag.bg:SetAllPoints(c.tag)
    W.Tint(c.tag.bg, C.control)
    c.tag.text = W.Font(c.tag, W.BODY, SIZE.tiny, C.text, "CENTER")
    c.tag.text:SetPoint("CENTER", c.tag, "CENTER", 0, 0)
    c.tag:Hide()

    local function paint()
        if c.selected then
            W.TintAccent(inner.edge)
            W.TintAccent(c.tick)
        else
            W.Tint(inner.edge, c.hover and C.dim or C.track)
        end
        c.tick:SetShown(c.selected == true and not c.tag:IsShown())
    end
    function c.SetSelected(on)
        c.selected = on and true or false
        paint()
    end
    function c.SetTag(text)
        if type(text) == "string" and text ~= "" then
            c.tag.text:SetText(text)
            local w = c.tag.text:GetStringWidth()
            c.tag:SetWidth((type(w) == "number" and w > 0 and w or 60) + 16)
            c.tag:Show()
        else
            c.tag:Hide()
        end
        paint()
    end
    c:SetScript("OnEnter", function()
        c.hover = true
        place(Cards.LIFT)
        paint()
        if c.tooltip then W.Tooltip(c, c.tooltip[1], c.tooltip[2]) end
    end)
    c:SetScript("OnLeave", function()
        c.hover = false
        place(0)
        paint()
        W.HideTooltip()
    end)
    -- The accent may have changed while hidden.
    c:HookScript("OnShow", paint)
    paint()
    return c
end

-- Wrapping text on a card.
function Cards.Text(card, text, size, color)
    local fs = W.Font(card.inner, W.BODY, size or SIZE.small, color or C.dim)
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    fs:SetText(text or "")
    return fs
end

-- A showpiece's tag: W.Tag at the tiny size, slanted a little more, its
-- words as written (not capitals) and a fill that turns to the Daylight
-- gradient when lit. t.Say(text) returns whether there are words to show.
function Cards.ShowTag(parent)
    local tag = W.Tag(parent)
    tag.fill = tag:CreateTexture(nil, "BORDER", nil, 1)
    tag.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    tag.fill:SetAllPoints(tag)
    Style.Clip(tag, tag.fill, "inner")
    Style.Slant(tag, "both", Cards.SHOW_TAG_SLANT, nil, "left")
    Style.SetTextSize(tag.text, SIZE.tiny)
    function tag.Lit(on)
        if on then W.TintDaylight(tag.fill, 0.55) else W.Tint(tag.fill, C.track) end
    end
    function tag.Say(text)
        if type(text) ~= "string" or text == "" then return false end
        tag.Set(text, Style.INK.TEXT)
        tag.text:SetText(text)
        tag.FitWidth()
        return true
    end
    tag.Lit(false)
    return tag
end

-- A showpiece card (the guide's opening): a picture on the stage color at the
-- top, a title and a line under it, a slanted tag top right and a tick top
-- left. Hovered it lifts; picked, its outline and a soft glow take the
-- Daylight gradient and it blooms once; the others dim. opts: titleSize,
-- lineSize, noLine (the line becomes the card's tooltip).
Cards.SHOW_DIM, Cards.SHOW_LIFT, Cards.SHOW_BLOOM = 0.78, 3, 5
Cards.SHOW_INSET = 11      -- the picture in from the card's sides and top
Cards.SHOW_TITLE_GAP, Cards.SHOW_LINE_GAP, Cards.SHOW_LINE_PAD = 9, 3, 12
Cards.SHOW_TAG_SLANT = 5
function Cards.Show(parent, width, height, pictureHeight, opts)
    opts = opts or {}
    local M = DUI.Motion
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(width, height)
    local inner = CreateFrame("Frame", nil, c)
    c.inner = inner
    local lift = 0
    local function place(dy)
        lift = dy
        inner:ClearAllPoints()
        inner:SetPoint("TOPLEFT", c, "TOPLEFT", 0, dy)
        inner:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, dy)
    end
    place(0)
    local function liftTo(dy, dur) M.Tween(inner, lift, dy, dur or M.FAST, place) end

    local one = DUI.Pixel.Px(c, 1)
    local function plainTex(layer, sub)
        local t = inner:CreateTexture(nil, layer, nil, sub)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        return t
    end
    inner.bg = plainTex("BACKGROUND")
    inner.bg:SetAllPoints(inner)
    W.Tint(inner.bg, C.card)
    local edges = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = plainTex("BORDER")
        if side == "top" or side == "bottom" then
            local p = side == "top" and "TOP" or "BOTTOM"
            t:SetPoint(p .. "LEFT", inner, p .. "LEFT", 0, 0)
            t:SetPoint(p .. "RIGHT", inner, p .. "RIGHT", 0, 0)
            t:SetHeight(one)
        else
            local p = side == "left" and "LEFT" or "RIGHT"
            t:SetPoint("TOP" .. p, inner, "TOP" .. p, 0, 0)
            t:SetPoint("BOTTOM" .. p, inner, "BOTTOM" .. p, 0, 0)
            t:SetWidth(one)
        end
        edges[side] = t
    end
    c.edges = edges

    local inset = one + Cards.SHOW_INSET
    c.picture = CreateFrame("Frame", nil, inner)
    c.picture:SetPoint("TOPLEFT", inner, "TOPLEFT", inset, -inset)
    c.picture:SetSize(width - 2 * inset, pictureHeight)
    c.picture.bg = c.picture:CreateTexture(nil, "BACKGROUND")
    c.picture.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    c.picture.bg:SetAllPoints(c.picture)
    W.Tint(c.picture.bg, C.stage)
    c.picture:SetClipsChildren(true)

    c.title = W.Font(inner, W.TITLE, opts.titleSize or SIZE.head, C.value, "CENTER")
    c.title:SetPoint("TOP", c.picture, "BOTTOM", 0, -Cards.SHOW_TITLE_GAP)
    c.line = W.Font(inner, W.BODY, opts.lineSize or SIZE.small, Style.INK.LABEL, "CENTER")
    c.line:SetWordWrap(true)
    c.line:SetMaxLines(2)
    c.line:SetJustifyV("TOP")
    -- Placed from the picture, not from the title: a text's own height is
    -- only known once the game has drawn it.
    local below = Cards.SHOW_TITLE_GAP + math.ceil((opts.titleSize or SIZE.head) * 1.2) + Cards.SHOW_LINE_GAP
    c.line:SetPoint("TOPLEFT", c.picture, "BOTTOMLEFT", Cards.SHOW_LINE_PAD - inset, -below)
    c.line:SetPoint("TOPRIGHT", c.picture, "BOTTOMRIGHT", inset - Cards.SHOW_LINE_PAD, -below)
    c.line:SetHeight(math.ceil((opts.lineSize or SIZE.small) * 2.6))
    c.line:SetShown(not opts.noLine)

    -- The tick and the tag sit over the picture and everything drawn in it.
    c.over = CreateFrame("Frame", nil, inner)
    c.over:SetAllPoints(inner)
    c.over:SetFrameLevel(inner:GetFrameLevel() + 60)
    c.tick = W.Icon(c.over, "ui-check.png", 12, C.text, "OVERLAY")
    c.tick:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -9)
    c.tick:Hide()

    local tag = Cards.ShowTag(c.over)
    tag:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -8, -8)
    tag:Hide()
    c.tagFrame = tag

    local function paintTag() tag.Lit(c.picked) end
    local function paintEdges()
        if c.picked then
            local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
            W.TintDaylight(edges.top)
            W.TintDaylight(edges.bottom)
            edges.left:SetVertexColor(a[1], a[2], a[3], 1)
            edges.right:SetVertexColor(z[1], z[2], z[3], 1)
        else
            W.Tint(edges.top, C.cardLit)
            for _, k in ipairs({ "bottom", "left", "right" }) do W.Tint(edges[k], C.cardEdge) end
        end
    end
    function c.Paint()
        paintEdges()
        paintTag()
        Style.PaintAccent(c.tick, 1)
    end

    function c.SetTag(text)
        tag:SetShown(tag.Say(text))
        paintTag()
    end

    function c.SetPicked(on, animate)
        on = on == true
        local was = c.picked == true
        c.picked = on
        paintEdges()
        paintTag()
        if on and animate and not was and M.On() then
            -- The tick pops: it grows into place, stepped by hand.
            c.tick:Show()
            M.Tween(c.tick, 0.5, 1, M.NORMAL, function(k) c.tick:SetSize(12 * k, 12 * k) end)
        else
            c.tick:SetShown(on)
        end
        W.GlowAround(c, on, { frame = inner, style = "breathe",
            lo = Style.GRADIENT_SHAPE[1], hi = Style.GRADIENT_SHAPE[2] })
        if on and animate and not was then
            -- The pick blooms once: the card lifts further and settles back.
            local rest = c:IsMouseOver() and Cards.SHOW_LIFT or 0
            M.Tween(inner, lift, Cards.SHOW_BLOOM, M.SLOW / 2, place, function()
                M.Tween(inner, Cards.SHOW_BLOOM, rest, M.SLOW / 2, place)
            end)
        end
    end

    -- Dimmed while another card is picked; a hovered one comes back to full.
    function c.SetDim(on, animate)
        c.dim = on == true
        c.restAlpha = c.dim and Cards.SHOW_DIM or 1
        local to = (c.dim and not c.hover) and Cards.SHOW_DIM or 1
        if animate then M.AlphaTo(c, to, M.NORMAL) else c:SetAlpha(to) end
    end

    c:SetScript("OnEnter", function()
        c.hover = true
        liftTo(Cards.SHOW_LIFT)
        if c.dim then M.AlphaTo(c, 1, M.FAST) end
        if c.tooltip then W.Tooltip(c, c.tooltip[1], c.tooltip[2]) end
    end)
    c:SetScript("OnLeave", function()
        c.hover = false
        liftTo(0)
        if c.dim then M.AlphaTo(c, Cards.SHOW_DIM, M.FAST) end
        W.HideTooltip()
    end)
    c:HookScript("OnShow", c.Paint)
    c.Paint()
    return c
end

-- One option as a row of cards, one per choice, with the current one
-- selected. opts:
--   keys      the choices, in order
--   width     width to fill; cols cards per row (default 3)
--   height    each card's height (default 64)
--   label(k)  a card's name; sub(k) an optional smaller line under it
--   get()     the current choice; set(k) picks one
--   draw(card, k, w, h)  optional, fills the card's top (w x h) with a picture
--   tag(k)    optional tag for a card, or nil
-- Returns a frame with .cards[k], .height and Refresh().
function Cards.Picker(parent, opts)
    local f = CreateFrame("Frame", nil, parent)
    f.cards = {}
    local cols = opts.cols or 3
    local h = opts.height or 64
    local rows = math.max(1, math.ceil(#opts.keys / cols))
    local w = (opts.width - (cols - 1) * Cards.GAP) / cols
    f.height = rows * h + (rows - 1) * Cards.GAP
    f:SetSize(opts.width, f.height)
    local bottom = opts.sub and 48 or 28 -- room under the picture for the name and its sub line
    for i, k in ipairs(opts.keys) do
        local c = Cards.Card(f)
        c.key = k
        c:SetSize(w, h)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c:SetPoint("TOPLEFT", f, "TOPLEFT", col * (w + Cards.GAP), -row * (h + Cards.GAP))
        c.label = W.Font(c.inner, W.BODY, SIZE.body, C.text)
        c.label:SetPoint("BOTTOMLEFT", c.inner, "BOTTOMLEFT", 10, opts.sub and 26 or 8)
        c.label:SetPoint("RIGHT", c.inner, "RIGHT", -10, 0)
        c.label:SetText(opts.label and opts.label(k) or tostring(k))
        if opts.sub then
            c.sub = Cards.Text(c, opts.sub(k), SIZE.small)
            c.sub:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -4)
            c.sub:SetPoint("BOTTOMRIGHT", c.inner, "BOTTOMRIGHT", -10, 4)
        end
        if opts.draw then opts.draw(c, k, w - 20, math.max(1, h - 10 - bottom)) end
        c:SetScript("OnClick", function()
            opts.set(k)
            f.Refresh()
        end)
        f.cards[k] = c
    end
    function f.Refresh()
        local v = opts.get()
        for _, k in ipairs(opts.keys) do
            local c = f.cards[k]
            c.SetSelected(k == v)
            c.SetTag(opts.tag and opts.tag(k) or nil)
            if c.redraw then c.redraw() end
        end
    end
    f.Refresh()
    return f
end

-- Drawings. Each fills a card's top (w x h, inside its 10 px inset). One that
-- shows a setting (the accent, the bar texture) sets card.redraw, which the
-- picker's Refresh calls so a new pick repaints it.

Cards.Draw = {}

local GREEN, RED, GOLD, STRIP = { 0.36, 0.64, 0.42 }, { 0.75, 0.35, 0.35 }, { 0.79, 0.64, 0.29 }, { 0.23, 0.23, 0.25 }
-- Faded parts (Immersive Preset fades your frame and the bars out of combat) and the quest tracker's lines.
local GREEN_DIM, STRIP_DIM, QUEST = { 0.2, 0.3, 0.23 }, { 0.17, 0.17, 0.18 }, { 0.62, 0.55, 0.4 }

-- Where frames sit in each layout, as boxes on a small screen: x, y (from the
-- top left), width, height as fractions of the screen, and a color.
Cards.LAYOUTS = {
    ["DPS/Tank"] = {
        { 0.22, 0.58, 0.18, 0.10, GREEN }, { 0.60, 0.58, 0.18, 0.10, RED },
        { 0.04, 0.18, 0.10, 0.07, GREEN }, { 0.04, 0.30, 0.10, 0.07, GREEN }, { 0.04, 0.42, 0.10, 0.07, GREEN },
        { 0.30, 0.84, 0.40, 0.08, STRIP },
    },
    -- DPS / Tank's positions with your frame and the bars faded, and the quest
    -- tracker in the top right corner.
    ["Immersive Preset"] = {
        { 0.22, 0.58, 0.18, 0.10, GREEN_DIM }, { 0.60, 0.58, 0.18, 0.10, RED },
        { 0.04, 0.18, 0.10, 0.07, GREEN }, { 0.04, 0.30, 0.10, 0.07, GREEN }, { 0.04, 0.42, 0.10, 0.07, GREEN },
        { 0.80, 0.14, 0.16, 0.03, QUEST }, { 0.80, 0.20, 0.12, 0.03, QUEST }, { 0.80, 0.26, 0.14, 0.03, QUEST },
        { 0.30, 0.84, 0.40, 0.08, STRIP_DIM },
    },
    Healer = {
        { 0.14, 0.50, 0.18, 0.10, GREEN }, { 0.68, 0.50, 0.18, 0.10, RED },
        { 0.36, 0.64, 0.05, 0.10, GREEN }, { 0.42, 0.64, 0.05, 0.10, GREEN }, { 0.48, 0.64, 0.05, 0.10, GREEN },
        { 0.54, 0.64, 0.05, 0.10, GOLD }, { 0.60, 0.64, 0.05, 0.10, GREEN },
        { 0.30, 0.84, 0.40, 0.08, STRIP },
    },
}

-- A small dark screen at the card's top with boxes on it.
local function screen(card, w, h, boxes)
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(w, h)
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    a.bg = W.Round(a, "BACKGROUND", 1)
    a.bg:SetAllPoints(a)
    W.Tint(a.bg, C.sidebar)
    for _, b in ipairs(boxes) do
        local t = a:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(b[5][1], b[5][2], b[5][3], 1)
        t:SetPoint("TOPLEFT", a, "TOPLEFT", b[1] * w, -b[2] * h)
        t:SetSize(math.max(1, b[3] * w), math.max(1, b[4] * h))
    end
    return a
end

function Cards.Draw.role(card, key, w, h)
    return screen(card, w, h, Cards.LAYOUTS[key] or Cards.LAYOUTS["DPS/Tank"])
end

-- The player's class color (softened like the frames), else a warm tan.
local function classColor()
    local _, token = UnitClass("player")
    if token then
        local r, g, b = Style.ClassColor(token)
        if type(r) == "number" then return { r, g, b } end
    end
    return { 0.78, 0.61, 0.43 }
end

-- A health bar three-quarters full, colored the way the mode does it.
function Cards.Draw.health(card, key, w, h)
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(w, math.max(1, math.min(14, h)))
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -12)
    a.back = a:CreateTexture(nil, "BACKGROUND")
    a.back:SetAllPoints(a)
    a.back:SetColorTexture(Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
    a.fill = a:CreateTexture(nil, "ARTWORK")
    a.fill:SetTexture(Style.BarFile())
    card.bar = a
    card.redraw = function() a.fill:SetTexture(Style.BarFile()) end
    a.fill:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    a.fill:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0)
    a.fill:SetWidth(math.max(1, w * 0.75))
    local c = classColor()
    local lo, hi
    if key == "classGradient" then
        lo, hi = { c[1] * 0.6, c[2] * 0.6, c[3] * 0.6 }, c
    elseif key == "gradient" then
        lo, hi = { 0.85, 0.75, 0.25 }, GREEN
    elseif key == "custom" then
        lo = GREEN
    elseif key == "dark" then
        lo = { 0.16, 0.16, 0.18 }
        a.missing = a:CreateTexture(nil, "ARTWORK")
        a.missing:SetColorTexture(RED[1], RED[2], RED[3], 1)
        a.missing:SetPoint("TOPLEFT", a.fill, "TOPRIGHT", 0, 0)
        a.missing:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
    else
        lo = c
    end
    if hi and a.fill.SetGradient and CreateColor then
        a.fill:SetVertexColor(1, 1, 1, 1)
        a.fill:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
    else
        a.fill:SetVertexColor(lo[1], lo[2], lo[3], 1)
    end
    return a
end

-- A small sketch of a frame with its portrait ring over the outer end and your
-- class icon, mirroring UF.LayoutPortrait.
local RING_COLOR = { 0.34, 0.34, 0.36 }

-- The ring's band in a ring color for your class (like UF.PaintRing).
-- base: the band's art name, "portrait-band" or a thinner one.
local function paintBand(band, mode, base)
    base = DUI.MEDIA .. (base or "portrait-band")
    band:SetTexture(base .. ".png")
    if mode == "accent" then
        if not Style.AccentPair() then band:SetTexture(base .. "-lit.png") end
        Style.PaintAccent(band, 1, "VERTICAL")
    elseif mode == "daylight" then
        local a, b = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
        band:SetVertexColor(1, 1, 1, 1)
        band:SetGradient("VERTICAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
    elseif mode == "dark" then
        local b, l = Style.BAND, Style.BAND_LIT
        band:SetVertexColor(1, 1, 1, 1)
        band:SetGradient("VERTICAL", CreateColor(b[1], b[2], b[3], 1), CreateColor(l[1], l[2], l[3], 1))
    elseif mode == "class" then
        local _, token = UnitClass("player")
        local lo, hi = DUI.Gradients.Colors(type(token) == "string" and token or "WARRIOR")
        band:SetVertexColor(1, 1, 1, 1)
        band:SetGradient("VERTICAL", lo, hi)
    else
        band:SetVertexColor(RING_COLOR[1], RING_COLOR[2], RING_COLOR[3], 1)
    end
end

-- ringOf() returns the color to draw the ring in.
local function drawPortrait(card, ringOf, w, h)
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(w, h)
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    local _, token = UnitClass("player")
    local icon = DUI.MEDIA .. "class\\" .. string.lower(type(token) == "string" and token or "warrior") .. ".tga"
    local H = math.floor(math.min(h * 0.62, 34) + 0.5)
    local k = tonumber(DUI:Get("UnitFrames", "look.slant")) or 0.21
    local cut = math.floor(H * k + 0.5)
    local bar = CreateFrame("Frame", nil, a)
    bar:SetHeight(H)
    Style.Shell(bar, {})
    Style.Slant(bar, nil, 0)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(Style.BarFile())
    local c = classColor()
    fill:SetVertexColor(c[1], c[2], c[3], 1)
    Style.Clip(bar, fill, "inner")
    local T = DUI.Pixel.Px(bar, Style.BorderPx(bar))
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", T, -T)
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -T, T)
    local art = { bar = bar }
    local R = H * 1.33 / 2
    local off = R * 0.35
    local reach = R + off
    Style.Slant(bar, "right", cut)
    local r = CreateFrame("Frame", nil, a)
    r:SetFrameLevel(bar:GetFrameLevel() + 6)
    r:SetSize(2 * R, 2 * R)
    r:SetPoint("CENTER", bar, "LEFT", -off, 0)
    -- Set into the frame (the unit frames' default look): the bar's border runs
    -- on round the ring through the shell's own layers, the bar is cut back
    -- under it, and the ring inside is one step thinner.
    local socket = DUI:Get("UnitFrames", "player.portraitLook") ~= "classic"
    local Rk, ratio, bandArt = R, 0.772, "portrait-band"
    if socket then
        local one = DUI.Pixel.Px(bar, 1)
        Rk, ratio, bandArt = R - math.max(0, T - one), 0.85, "portrait-band-thin"
        local j = Style.ShellJoin(bar)
        j.side = "left"
        for _, piece in ipairs({ j.outline, j.band }) do
            piece:SetTexture(DUI.MEDIA .. "crest-disc.png")
            piece:ClearAllPoints()
            piece:SetPoint("CENTER", bar, "LEFT", -off, 0)
        end
        j.outline:SetSize(2 * R, 2 * R)
        j.band:SetSize(2 * (R - one), 2 * (R - one))
        j.outline:Show()
        j.band:SetShown(Style.IsHeavy(Style.GetShell(bar)))
        Style.PaintJoin(j, Style.GetShell(bar))
        -- The cut-back: the part of the ring's disc over the bar's inside.
        local gap = r:CreateTexture(nil, "BACKGROUND", nil, -1)
        gap:SetTexture(DUI.MEDIA .. "crest-disc.png")
        gap:SetVertexColor(Style.BORDER[1], Style.BORDER[2], Style.BORDER[3], 1)
        local x0, x1 = off + T, 2 * R
        local y = math.min(R, H / 2 - T)
        if x1 > x0 then
            gap:SetTexCoord(x0 / (2 * R), 1, (R - y) / (2 * R), (R + y) / (2 * R))
            gap:SetPoint("BOTTOMLEFT", r, "LEFT", x0, -y)
            gap:SetPoint("TOPRIGHT", r, "LEFT", x1, y)
        else
            gap:Hide()
        end
        card.portraitJoin = { outline = j.outline, band = j.band, gap = gap }
    end
    local inner = Rk * ratio
    local disc = r:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(DUI.MEDIA .. "crest-disc.png")
    disc:SetVertexColor(0.02, 0.02, 0.02, 1)
    disc:SetSize(2 * inner + 2, 2 * inner + 2)
    disc:SetPoint("CENTER", r, "CENTER", 0, 0)
    local t = r:CreateTexture(nil, "ARTWORK")
    t:SetTexture(icon)
    t:SetSize(2.3 * inner, 2.3 * inner)
    t:SetPoint("CENTER", r, "CENTER", 0, 0)
    local m = r:CreateMaskTexture()
    m:SetTexture(DUI.MEDIA .. "crest-disc.png", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetSize(2 * inner, 2 * inner)
    m:SetPoint("CENTER", r, "CENTER", 0, 0)
    t:AddMaskTexture(m)
    local band = r:CreateTexture(nil, "OVERLAY")
    paintBand(band, ringOf(), bandArt)
    band:SetSize(2 * Rk / 0.6, 2 * Rk / 0.6)
    band:SetPoint("CENTER", r, "CENTER", 0, 0)
    art.ring, art.band = r, band
    bar:SetPoint("LEFT", a, "LEFT", math.ceil(reach) + 2, 0)
    bar:SetPoint("RIGHT", a, "RIGHT", -2, 0)
    card.portraitArt = art
    card.redraw = function()
        fill:SetTexture(Style.BarFile())
        if art.band then paintBand(art.band, ringOf(), bandArt) end
    end
    return a
end

-- Ring color: one card per ring color.
function Cards.Draw.portraitRing(card, key, w, h)
    return drawPortrait(card, function() return key end, w, h)
end

-- Half a frame's border, as the unit frames' name tabs and Ribbon's power
-- line use (UF.TAB_BORDER).
local function halfBorder(px) return math.max(3, math.floor(px / 2 + 0.5)) end

-- A shelled bar in your class color (thin uses half the border), angled
-- later. fillH is the colored part's height. The border goes around it like
-- the frames' own bars (PB.LayoutLine), so a thick border never eats into it.
local function styleBar(parent, fillH, thin)
    local bar = CreateFrame("Frame", nil, parent)
    Style.Shell(bar, thin and { borderPx = halfBorder } or {})
    local T = DUI.Pixel.Px(bar, Style.BorderPx(bar))
    bar:SetHeight(fillH + 2 * T)
    Style.Slant(bar, nil, 0)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(Style.BarFile())
    local c = classColor()
    fill:SetVertexColor(c[1], c[2], c[3], 1)
    Style.Clip(bar, fill, "inner")
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", T, -T)
    fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -T, T)
    bar.fill = fill
    return bar
end

-- Frame style (Unit frames, look.style), drawn from the style's pieces (the
-- unit frames' STYLES): a frame with its name tab and the number inside, or a
-- slim bar with the name and number on a row above (row) and the power as a
-- line below (line), or a card (backdrop): your face filling the frame over
-- your class color, the name on it and thin strips along its foot. A small
-- sketch in the real frames' proportions (a bar 24 to its line 5), kept clear
-- of the tick in the top right.
Cards.STYLE_TICK = 22 -- room kept for the tick
local function frameStyleOf(key)
    local mod = DUI:GetModule("UnitFrames")
    local styles = mod and mod.ns and mod.ns.STYLES
    return type(styles) == "table" and styles[key] or {}
end
function Cards.Draw.frameStyle(card, key, w, h)
    local style = frameStyleOf(key)
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(math.max(1, w - Cards.STYLE_TICK), h)
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    local k = tonumber(DUI:Get("UnitFrames", "look.slant")) or 0.21
    local name = DUI.UnitName("player", "player") or L["Name"]
    local fills = {}
    if style.backdrop then
        local H = math.max(12, math.floor(h * 0.72 + 0.5))
        local body = styleBar(a, H)
        body:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -math.floor(h * 0.1 + 0.5))
        body:SetPoint("RIGHT", a, "RIGHT", 0, 0)
        local T = DUI.Pixel.Px(body, Style.BorderPx(body))
        local outerH = body:GetHeight()
        local cut = math.floor(outerH * k + 0.5)
        local bw = math.max(1, w - Cards.STYLE_TICK - 2 * T)
        local strip, P = math.max(3, math.floor(H * 0.14 + 0.5)), math.max(2, math.floor(H * 0.07 + 0.5))
        -- The bar's fill is the class color wash behind the picture.
        body.fill:SetAlpha(0.35)
        local art = H - strip - P - 1
        local face = body:CreateTexture(nil, "ARTWORK", nil, 1)
        face:SetPoint("TOPLEFT", body, "TOPLEFT", T, -T)
        face:SetSize(art, art)
        DUI.SafeCall(SetPortraitTexture, face, "player")
        Style.CropIcon(face)
        local hp = body:CreateTexture(nil, "ARTWORK", nil, 2)
        hp:SetTexture(Style.BarFile())
        local c = classColor()
        hp:SetVertexColor(c[1], c[2], c[3], 1)
        hp:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", T, T + P + 1)
        hp:SetSize(math.floor(bw * 0.72 + 0.5), strip)
        local mp = body:CreateTexture(nil, "ARTWORK", nil, 2)
        mp:SetTexture(Style.BarFile())
        local r, g, b = Style.PowerColor("MANA")
        mp:SetVertexColor(r, g, b, 1)
        mp:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", T, T)
        mp:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -T, T)
        mp:SetHeight(P)
        Style.Clip(body, hp, "inner")
        Style.Clip(body, mp, "inner")
        Style.Slant(body, "right", cut)
        local n = W.Font(body, W.BODY, SIZE.small, C.text)
        n:SetPoint("TOPLEFT", body, "TOPLEFT", T + art * 0.55, -T - 3)
        n:SetText(name)
        local v = W.Font(body, W.BODY, SIZE.head, C.value)
        v:SetPoint("BOTTOMRIGHT", hp, "TOPRIGHT", 0, 2)
        v:SetText("72")
        fills = { body.fill, hp, mp }
    elseif style.row or style.line then
        local fillH = math.max(6, math.floor(h * 0.24 + 0.5))
        local P, gap = math.max(2, math.floor(fillH * 5 / 24 + 0.5)), 2
        local bar = styleBar(a, fillH)
        bar:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -math.floor(h * 0.3 + 0.5))
        bar:SetPoint("RIGHT", a, "RIGHT", 0, 0)
        local H = bar:GetHeight()
        local cut = math.floor(H * k + 0.5)
        Style.Slant(bar, "right", cut)
        fills = { bar.fill }
        if style.row then
            local n = W.Font(a, W.BODY, SIZE.small, C.text)
            n:SetPoint("TOPLEFT", a, "TOPLEFT", 4, 0)
            n:SetText(name)
            -- The number at the row's inner end, clear of the bar's angle.
            local v = W.Font(a, W.BODY, SIZE.body, C.value)
            v:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -cut, 2)
            v:SetText("87")
        end
        if style.line then
            local line = styleBar(a, P, true)
            line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -gap)
            line:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -gap)
            local total = H + gap + line:GetHeight()
            Style.Slant(line, "right", cut * total / H, { frame = bar, height = total })
            local r, g, b = Style.PowerColor("MANA")
            line.fill:SetVertexColor(r, g, b, 1)
            fills[2] = line.fill
        end
    else
        local bar = styleBar(a, math.max(6, math.floor(h * 0.36 + 0.5)))
        bar:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, math.floor(h * 0.08 + 0.5))
        bar:SetPoint("RIGHT", a, "RIGHT", 0, 0)
        local H = bar:GetHeight()
        Style.Slant(bar, "right", math.floor(H * k + 0.5))
        local tab = CreateFrame("Frame", nil, a)
        tab:SetSize(math.floor(w * 0.42 + 0.5), math.floor(h * 0.3 + 0.5))
        tab:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 8, -1)
        Style.Shell(tab, { borderPx = halfBorder })
        local n = W.Font(tab, W.BODY, SIZE.small, C.text)
        n:SetPoint("CENTER", tab, "CENTER", 0, 0)
        n:SetText(name)
        local v = W.Font(bar, W.BODY, SIZE.head, C.value)
        v:SetPoint("RIGHT", bar, "RIGHT", -math.floor(H * k + 0.5) - 6, 0)
        v:SetText("87")
        fills = { bar.fill }
    end
    card.redraw = function()
        for _, t in ipairs(fills) do t:SetTexture(Style.BarFile()) end
    end
    return a
end

-- An accent color as a rounded swatch.
function Cards.Draw.swatch(card, key, w, h)
    local s = W.Round(card.inner, "ARTWORK")
    local size = math.max(1, math.min(h, 26))
    s:SetSize(size * 1.6, size)
    s:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    local function paint()
        if key == "gradient" and s.SetGradient and CreateColor then
            local a, b = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
            s:SetVertexColor(1, 1, 1, 1)
            s:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
        elseif key == "classGradient" and s.SetGradient and CreateColor and Style.ClassAccentPair() then
            local a, b = Style.ClassAccentPair()
            s:SetVertexColor(1, 1, 1, 1)
            s:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
        elseif key == "customGradient" and s.SetGradient and CreateColor and Style.CustomAccentStops() then
            local stops = Style.CustomAccentStops()
            local a, b = stops[1], stops[#stops]
            s:SetVertexColor(1, 1, 1, 1)
            s:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
        elseif key == "class" or key == "classGradient" then
            local c = classColor()
            s:SetVertexColor(c[1], c[2], c[3], 1)
        elseif key == "custom" then
            local c = DUI:Get("general", "accentColor")
            if type(c) == "table" and type(c[1]) == "number" then s:SetVertexColor(c[1], c[2], c[3], 1) else W.Tint(s, C.dim) end
        else
            local a = Style.ACCENT
            s:SetVertexColor(a[1], a[2], a[3], 1)
        end
    end
    paint()
    card.redraw = paint
    card.swatch = s
    return s
end

-- A sample written in the font itself.
function Cards.Draw.font(card, key, w, h)
    local def = Style.FontEntry(key)
    local file = def and def.file or STANDARD_TEXT_FONT or W.BODY
    local fs = card.inner:CreateFontString(nil, "OVERLAY")
    fs:SetFont(file, 16, "")
    fs:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.7)
    fs:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    fs:SetText("Daylight 123")
    return fs
end

-- A strip of the bar texture in the accent.
function Cards.Draw.texture(card, key, w, h)
    local t = card.inner:CreateTexture(nil, "ARTWORK")
    local file = key ~= "daylight" and DUI.Media and DUI.Media.Fetch("statusbar", key) or Style.BAR.fill
    t:SetTexture(file)
    t:SetSize(w, math.max(1, math.min(14, h)))
    t:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -12)
    Style.PaintAccent(t)
    card.strip = t
    card.redraw = function() Style.PaintAccent(t) end
    return t
end

-- An enemy cast bar that gets interrupted (the core's Motion.Kick) when the
-- mouse enters the card, as if by your own kick.
local KICKED = { 0.85, 0.22, 0.2 } -- the nameplates' interrupted red (Cast.INTERRUPTED)
function Cards.Draw.kick(card, key, w, h)
    local bh = math.max(1, math.min(12, h))
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(w, bh)
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -14)
    local b = Style.BORDER
    a.edge = a:CreateTexture(nil, "BACKGROUND")
    a.edge:SetAllPoints(a)
    a.edge:SetColorTexture(b[1], b[2], b[3], 1)
    a.back = a:CreateTexture(nil, "BORDER")
    a.back:SetPoint("TOPLEFT", a, "TOPLEFT", 1, -1)
    a.back:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -1, 1)
    a.back:SetColorTexture(Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
    a.fill = a:CreateTexture(nil, "ARTWORK")
    a.fill:SetPoint("TOPLEFT", a, "TOPLEFT", 1, -1)
    a.fill:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 1, 1)
    a.fill:SetWidth(math.max(1, (w - 2) * 0.65))
    a.fill:SetTexture(Style.BarFile())
    local cast = Style.CAST.normal
    a.fill:SetVertexColor(cast[1], cast[2], cast[3], 1)
    local k = DUI.Motion.NewBlade(card.inner)
    local shape = { right = function(_, inset) return w - inset end, T = 1, edge = b, fill = KICKED }
    card:HookScript("OnEnter", function()
        local r, g, bl = Style.Accent()
        DUI.Motion.Kick(k, a, key, r, g, bl, shape)
    end)
    card.kick = k
    card.redraw = function() a.fill:SetTexture(Style.BarFile()) end
    return a
end

-- The animated glows (Motion.GLOW_STYLES): each card runs its style on a small
-- sample of what it lights, a main button or an enemy's nameplate. "none"
-- shows the sample alone. The lights run only while the page shows.
local function glowSample(card, key, w, h, shape)
    local s
    if shape == "button" then
        s = W.Button(card.inner, L["Accept"], math.min(22, h))
        s:SetWidth(math.min(w, 110))
        s:EnableMouse(false)
    else
        s = CreateFrame("Frame", nil, card.inner)
        s:SetSize(math.min(w, 120), math.max(1, math.min(10, h)))
        s.back = s:CreateTexture(nil, "BACKGROUND")
        s.back:SetAllPoints(s)
        s.back:SetColorTexture(Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
        s.fill = s:CreateTexture(nil, "ARTWORK")
        s.fill:SetPoint("TOPLEFT", s, "TOPLEFT")
        s.fill:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT")
        s.fill:SetWidth(math.max(1, s:GetWidth() * 0.62))
        s.fill:SetTexture(Style.BarFile())
        s.fill:SetVertexColor(RED[1], RED[2], RED[3], 1)
    end
    s:SetPoint("TOP", card.inner, "TOP", 0, -10 - math.max(0, (h - s:GetHeight()) / 2))
    local host = {}
    local function light()
        if DUI.Motion.GLOW_STYLES[key] then
            local px = DUI.Pixel.Px(s, 2)
            W.GlowAround(host, true, {
                style = key, frame = s, parent = s, layer = "OVERLAY", sub = 7,
                inset = shape == "plate" and -px or 0, thick = px,
                size = shape == "plate" and 10 or nil,
            })
        end
    end
    light()
    card.sample = s
    card.redraw = light
    return s
end
function Cards.Draw.glowButton(card, key, w, h) return glowSample(card, key, w, h, "button") end

-- Bar styles (BarFx): each card wears its style on a sample health bar.
function Cards.Draw.barFx(card, key, w, h)
    local s = DUI.BarFx.SampleBar(card.inner, "health", key)
    s:SetSize(math.min(w - 16, 150), math.max(8, math.min(14, h - 20)))
    s:SetPoint("TOP", card.inner, "TOP", 0, -10 - math.max(0, (h - s:GetHeight()) / 2))
    card.sample = s
    card.redraw = function() s.Paint() end
    return s
end
function Cards.Draw.glowPlate(card, key, w, h) return glowSample(card, key, w, h, "plate") end

-- Bars on a small screen: one or two rows at the bottom and side bars on the
-- right edge (the action bars step's presets).
Cards.BAR_LAYOUTS = {
    one = { { 0.30, 0.82, 0.40, 0.08, STRIP } },
    two = { { 0.30, 0.82, 0.40, 0.08, STRIP }, { 0.30, 0.70, 0.40, 0.08, STRIP } },
    sides = { { 0.30, 0.82, 0.40, 0.08, STRIP }, { 0.30, 0.70, 0.40, 0.08, STRIP },
              { 0.88, 0.25, 0.04, 0.45, STRIP_DIM }, { 0.93, 0.25, 0.04, 0.45, STRIP_DIM } },
}
function Cards.Draw.bars(card, key, w, h)
    return screen(card, w, h, Cards.BAR_LAYOUTS[key] or Cards.BAR_LAYOUTS.two)
end

-- Your cast bar under your frame, or between your frame and the target's with
-- the swing timers below it, each a little wider (the Frames step's presets).
Cards.CAST_LAYOUTS = {
    below = { { 0.08, 0.30, 0.34, 0.20, GREEN }, { 0.58, 0.30, 0.34, 0.20, RED },
              { 0.08, 0.50, 0.34, 0.10, GOLD } },
    middle = { { 0.04, 0.30, 0.30, 0.20, GREEN }, { 0.66, 0.30, 0.30, 0.20, RED },
               { 0.38, 0.30, 0.24, 0.12, GOLD },
               { 0.37, 0.43, 0.26, 0.07, STRIP }, { 0.36, 0.51, 0.28, 0.07, STRIP }, { 0.35, 0.59, 0.30, 0.07, STRIP } },
}
function Cards.Draw.castbar(card, key, w, h)
    return screen(card, w, h, Cards.CAST_LAYOUTS[key] or Cards.CAST_LAYOUTS.below)
end

-- A nameplate at each size: an enemy's red bar at the picked width and height.
Cards.PLATE_SIZES = { small = { 0.55, 7 }, medium = { 0.7, 9 }, large = { 0.88, 12 } }
function Cards.Draw.plates(card, key, w, h)
    local size = Cards.PLATE_SIZES[key] or Cards.PLATE_SIZES.medium
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(w, h)
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    local bw, bh = math.max(1, w * size[1]), math.min(h, size[2])
    local back = a:CreateTexture(nil, "BACKGROUND")
    back:SetColorTexture(Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
    back:SetSize(bw, bh)
    back:SetPoint("CENTER", a, "CENTER", 0, 0)
    local fill = a:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(Style.BarFile())
    fill:SetVertexColor(RED[1], RED[2], RED[3], 1)
    fill:SetPoint("TOPLEFT", back, "TOPLEFT", 0, 0)
    fill:SetSize(math.max(1, bw * 0.7), bh)
    card.redraw = function() fill:SetTexture(Style.BarFile()) end
    return a
end

-- Out of combat: everything shown, your frame and bars faded, or nearly
-- everything hidden (the calm step's presets).
Cards.CALM_LAYOUTS = {
    shown = Cards.LAYOUTS["DPS/Tank"],
    calm = Cards.LAYOUTS["Immersive Preset"],
    float = {
        { 0.22, 0.58, 0.18, 0.10, GREEN_DIM }, { 0.60, 0.58, 0.18, 0.10, RED },
        { 0.30, 0.84, 0.40, 0.08, STRIP_DIM },
    },
}
function Cards.Draw.calm(card, key, w, h)
    return screen(card, w, h, Cards.CALM_LAYOUTS[key] or Cards.CALM_LAYOUTS.shown)
end

-- A bag's slots, either in categories (groups with a gap between, each its
-- own shade) or bag by bag (one even grid).
function Cards.Draw.bagview(card, key, w, h)
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(w, h)
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    local size, gap = 7, 2
    local cols = math.max(1, math.floor((w + gap) / (size + gap)))
    local rows = math.max(1, math.floor((h + gap) / (size + gap)))
    local grouped = key == "categories"
    for r = 0, rows - 1 do
        for col = 0, cols - 1 do
            if not (grouped and col % 5 == 4) then
                local v = grouped and (math.floor(col / 5) % 2 == 0 and 0.34 or 0.24) or 0.28
                local t = a:CreateTexture(nil, "ARTWORK")
                t:SetColorTexture(v, v, v + 0.02, 1)
                t:SetSize(size, size)
                t:SetPoint("TOPLEFT", a, "TOPLEFT", col * (size + gap), -r * (size + gap))
            end
        end
    end
    return a
end


-- Pictures for the guide's questions (InstallerDuel). Each makes a frame of
-- the width asked for, drawn from the frames' own pieces and colors; the
-- sky, ground and the mob under a plate are the picture's own art.
Cards.Picture = {}
local Pic = Cards.Picture

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local SKY = {
    { 0.106, 0.165, 0.290 }, { 0.227, 0.208, 0.376 }, { 0.478, 0.290, 0.416 }, { 0.788, 0.471, 0.369 },
}
local SKY_AT = { 0, 0.36, 0.60, 0.72 }
local GROUND, GROUND_LOW, GROUND_AT = { 0.110, 0.106, 0.086 }, { 0.082, 0.078, 0.059 }, 0.725
local FIGURE = { 0.063, 0.059, 0.047 }
local ART_PLATE = { 0.043, 0.043, 0.051 }
local PANEL = { 0.078, 0.078, 0.090 }
local SLOT, SLOT_FULL, SLOT_FULL_LOW = { 0.133, 0.133, 0.153 }, { 0.29, 0.29, 0.345 }, { 0.169, 0.169, 0.2 }
local DEBUFFS = { { { 0.478, 0.29, 0.659 }, { 0.227, 0.141, 0.314 } }, { { 0.659, 0.376, 0.227 }, { 0.314, 0.188, 0.11 } },
                  { { 0.227, 0.541, 0.353 }, { 0.11, 0.251, 0.188 } } }
Pic.SKY_RATIO = 0.58

local function tex(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetTexture(WHITE8)
    return t
end
local function vertical(t, top, low)
    t:SetVertexColor(1, 1, 1, 1)
    if t.SetGradient and CreateColor then
        t:SetGradient("VERTICAL", CreateColor(low[1], low[2], low[3], 1), CreateColor(top[1], top[2], top[3], 1))
    else
        t:SetVertexColor(top[1], top[2], top[3], 1)
    end
end

-- The frame's edge round a panel: a dark line, the warm band, a dark line.
local function framed(f)
    for i, spec in ipairs({ { 5, Style.BORDER }, { 4, Style.BAND }, { 1, Style.BORDER } }) do
        local t = tex(f, "BACKGROUND", i - 8)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", -spec[1], spec[1])
        t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", spec[1], -spec[1])
        t:SetVertexColor(spec[2][1], spec[2][2], spec[2][3], 1)
    end
end

-- The small screen (InstallerScreen) in a state.
function Pic.screen(parent, state, width)
    local s = DUI.InstallerScreen.New(parent, width)
    s.Set(state, true)
    return s
end

-- The sky the plate, crowd and quest pictures stand on: dusk down to the
-- ground line, framed like a window of the game.
function Pic.Sky(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    local h = math.floor(width * Pic.SKY_RATIO + 0.5)
    f:SetSize(width, h)
    f:SetClipsChildren(true)
    framed(f)
    for i = 1, 4 do
        local t = tex(f, "BACKGROUND")
        local top, low = SKY_AT[i], SKY_AT[i + 1] or GROUND_AT
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top * h)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top * h)
        t:SetHeight(math.max(0.01, (low - top) * h))
        vertical(t, SKY[i], SKY[i + 1] or SKY[4])
    end
    local ground = tex(f, "BACKGROUND", 1)
    ground:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -GROUND_AT * h)
    ground:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    vertical(ground, GROUND, GROUND_LOW)
    return f
end

-- A shelled bar of the frames' own look, filled share of the way, leaning.
local function leanBar(parent, w, fillH, share, thin, lean)
    local bar = styleBar(parent, fillH, thin)
    bar:SetWidth(w)
    Style.Slant(bar, "both", math.floor(bar:GetHeight() * math.tan(math.rad(lean)) + 0.5), nil, "left")
    bar.fill:ClearAllPoints()
    local T = DUI.Pixel.Px(bar, Style.BorderPx(bar))
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", T, -T)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", T, T)
    bar.fill:SetWidth(math.max(1, (w - 2 * T) * share))
    return bar
end

-- An accent value's two colors (a single color gives the same twice).
local function accentPair(key)
    if key == "gradient" then return Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2] end
    if key == "classGradient" and Style.ClassAccentPair() then return Style.ClassAccentPair() end
    if key == "customGradient" and Style.CustomAccentStops() then
        local stops = Style.CustomAccentStops()
        return stops[1], stops[#stops]
    end
    if key == "class" or key == "classGradient" then local c = classColor(); return c, c end
    if key == "custom" then
        local c = DUI:Get("general", "accentColor")
        if type(c) == "table" and type(c[1]) == "number" then return c, c end
        return Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
    end
    return Style.ACCENT, Style.ACCENT
end
Cards.AccentPair = accentPair

local function paintPair(t, lo, hi, orientation)
    t:SetVertexColor(1, 1, 1, 1)
    if t.SetGradient and CreateColor then
        t:SetGradient(orientation or "HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
    else
        t:SetVertexColor(hi[1], hi[2], hi[3], 1)
    end
end

-- A round portrait with your class icon in the frames' warm ring.
local function portrait(parent, size)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(size, size)
    local _, token = UnitClass("player")
    local disc = r:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(DUI.MEDIA .. "crest-disc.png")
    disc:SetVertexColor(0.02, 0.02, 0.02, 1)
    disc:SetAllPoints(r)
    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(DUI.MEDIA .. "class\\" .. string.lower(type(token) == "string" and token or "warrior") .. ".tga")
    icon:SetSize(size * 0.95, size * 0.95)
    icon:SetPoint("CENTER", r, "CENTER", 0, 0)
    local m = r:CreateMaskTexture()
    m:SetTexture(DUI.MEDIA .. "crest-disc.png", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetSize(size * 0.8, size * 0.8)
    m:SetPoint("CENTER", r, "CENTER", 0, 0)
    icon:AddMaskTexture(m)
    local band = r:CreateTexture(nil, "OVERLAY")
    paintBand(band, "dark")
    band:SetSize(size / 0.6, size / 0.6)
    band:SetPoint("CENTER", r, "CENTER", 0, 0)
    r.band = band
    return r
end

-- The sample frame a color is shown on: a portrait, a health bar three
-- quarters full in that color with its number, a power bar and a name tag.
-- Drawn at 250 x 66 and scaled to the width asked for.
Pic.FRAME_W, Pic.FRAME_H = 250, 66
function Pic.accent(parent, key, width)
    local f = CreateFrame("Frame", nil, parent)
    local k = math.min(1, width / Pic.FRAME_W)
    f:SetSize(Pic.FRAME_W * k, Pic.FRAME_H * k)
    local inner = CreateFrame("Frame", nil, f)
    inner:SetSize(Pic.FRAME_W, Pic.FRAME_H)
    inner:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    inner:SetScale(k)
    local hp = leanBar(inner, 186, 24, 0.76, false, 24)
    hp:SetPoint("TOPLEFT", inner, "TOPLEFT", 52, -17)
    local lo, hi = accentPair(key)
    hp.fill:SetTexture(WHITE8)
    paintPair(hp.fill, lo, hi)
    hp.value = W.Font(hp, W.TITLE, SIZE.title, C.value, "RIGHT")
    hp.value:SetPoint("RIGHT", hp, "RIGHT", -16, 0)
    hp.value:SetText("2.5K")
    local power = leanBar(inner, 150, 7, 0.62, true, 24)
    power:SetPoint("TOPLEFT", inner, "TOPLEFT", 50, -48)
    local red = Style.REACTION.hostile
    power.fill:SetTexture(WHITE8)
    paintPair(power.fill, { red[1] * 0.65, red[2] * 0.65, red[3] * 0.65 }, red)
    local face = portrait(inner, 56)
    face:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -5)
    face:SetFrameLevel(hp:GetFrameLevel() + 6)
    local name = CreateFrame("Frame", nil, inner)
    name:SetFrameLevel(hp:GetFrameLevel() + 4)
    name:SetPoint("TOPLEFT", inner, "TOPLEFT", 92, 3)
    name:SetHeight(16)
    name.bg = tex(name, "BACKGROUND")
    name.bg:SetAllPoints(name)
    W.Tint(name.bg, C.window)
    name.text = W.Font(name, W.BODY, 11, C.value, "CENTER")
    name.text:SetPoint("CENTER", name, "CENTER", 0, 0)
    name.text:SetText(UnitName("player") or "Tester")
    local nw = name.text:GetStringWidth()
    name:SetWidth((type(nw) == "number" and nw > 0 and nw or 36) + 18)
    f.health, f.power, f.face = hp, power, face
    return f
end

-- A color's closed strip: an upright bar of it in a frame's edge, the
-- gradient running bottom to top.
function Pic.accentBar(parent, key)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(14, 150)
    framed(f)
    local t = tex(f, "ARTWORK")
    t:SetAllPoints(f)
    local lo, hi = accentPair(key)
    paintPair(t, lo, hi, "VERTICAL")
    return f
end

local function fontFile(key)
    local def = Style.FontEntry(key)
    return def and def.file or STANDARD_TEXT_FONT or W.BODY
end
Cards.FontFile = fontFile

-- A font, open: "Tester 2.5K" big, a line of stats under it.
function Pic.font(parent, key, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 36 * 1.2 + 2 + 14 * 1.2)
    local file = fontFile(key)
    f.big = f:CreateFontString(nil, "OVERLAY")
    f.big:SetFont(file, 36, "")
    f.big:SetPoint("TOP", f, "TOP", 0, 0)
    f.big:SetShadowOffset(1, -1)
    f.big:SetShadowColor(0, 0, 0, 0.7)
    W.TextColor(f.big, C.value)
    local r, g, b = Style.Accent()
    f.big:SetText(string.format("%s |cff%02x%02x%02x2.5K|r", UnitName("player") or "Tester",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
    f.small = f:CreateFontString(nil, "OVERLAY")
    f.small:SetFont(file, 14, "")
    f.small:SetPoint("TOP", f.big, "BOTTOM", 0, -2)
    W.TextColor(f.small, Style.INK.LABEL)
    f.small:SetText(L["Level 60 Warrior   128 - 193 Damage"])
    return f
end

-- A font, closed: "Aa" in it.
function Pic.fontMini(parent, key)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 34)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(fontFile(key), 27, "")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    W.TextColor(f.text, C.value)
    f.text:SetText(L["Aa"])
    return f
end

-- One enemy's nameplate over the sky, at the size and with the parts asked
-- for: opts = { size = "small" | "medium" | "large", percent, debuffs }.
-- Sizes are the Nameplates presets' own: width, height, scale.
Pic.PLATES = { small = { 150, 14, 0.85 }, medium = { 170, 16, 1 }, large = { 190, 20, 1.2 } }
function Pic.plate(parent, opts, width)
    opts = opts or {}
    local f = Pic.Sky(parent, width)
    local d = Pic.PLATES[opts.size or "medium"] or Pic.PLATES.medium
    local pw, ph = math.floor(d[1] * d[3] + 0.5), math.floor(d[2] * d[3] + 0.5)
    local p = CreateFrame("Frame", nil, f)
    p:SetWidth(pw)
    local debH = opts.debuffs ~= false and (18 + 5) or 0
    local nameH = math.floor(12 * d[3] + 0.5)
    local total = debH + nameH + 5 + ph + 10 + 44
    p:SetHeight(total)
    p:SetPoint("CENTER", f, "CENTER", 0, 0)
    p.debuffs = {}
    for i = 1, 3 do
        local b = CreateFrame("Frame", nil, p)
        b:SetSize(18, 18)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * 22, 0)
        local edge = tex(b, "BACKGROUND")
        edge:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
        edge:SetVertexColor(Style.BORDER[1], Style.BORDER[2], Style.BORDER[3], 1)
        local t = tex(b, "ARTWORK")
        t:SetAllPoints(b)
        vertical(t, DEBUFFS[i][1], DEBUFFS[i][2])
        b:SetShown(opts.debuffs ~= false)
        p.debuffs[i] = b
    end
    p.name = W.Font(p, W.BODY, nameH, C.value, "CENTER")
    p.name:SetPoint("TOP", p, "TOP", 0, -debH)
    p.name:SetText(L["Defias Pillager"])
    p.bar = CreateFrame("Frame", nil, p)
    p.bar:SetSize(pw, ph)
    p.bar:SetPoint("TOP", p, "TOP", 0, -(debH + nameH + 5))
    -- The edge round the bar (a dark line, the band, a dark line), all leaning.
    local cut = math.floor(ph * math.tan(math.rad(18)) + 0.5)
    for i, spec in ipairs({ { 4, Style.BORDER }, { 3, Style.BAND }, { 1, Style.BORDER }, { 0, ART_PLATE } }) do
        local t = tex(p.bar, "BACKGROUND", i - 8)
        t:SetPoint("TOPLEFT", p.bar, "TOPLEFT", -spec[1], spec[1])
        t:SetPoint("BOTTOMRIGHT", p.bar, "BOTTOMRIGHT", spec[1], -spec[1])
        t:SetVertexColor(spec[2][1], spec[2][2], spec[2][3], 1)
        Style.Clip(p.bar, t, "outer")
    end
    p.fill = tex(p.bar, "ARTWORK")
    p.fill:SetPoint("TOPLEFT", p.bar, "TOPLEFT", 0, 0)
    p.fill:SetPoint("BOTTOMLEFT", p.bar, "BOTTOMLEFT", 0, 0)
    p.fill:SetWidth(pw * 0.72)
    local red = Style.REACTION.hostile
    paintPair(p.fill, { red[1] * 0.65, red[2] * 0.65, red[3] * 0.65 }, red)
    Style.Clip(p.bar, p.fill, "outer")
    Style.Slant(p.bar, "both", cut, nil, "left")
    p.percent = W.Font(p.bar, W.BODY, math.floor(11 * d[3] + 0.5), C.value, "RIGHT")
    p.percent:SetPoint("RIGHT", p.bar, "RIGHT", -8, 0)
    p.percent:SetText("72%")
    p.percent:SetShown(opts.percent ~= false)
    -- The mob under its plate: a dark figure, round on top.
    p.mob = CreateFrame("Frame", nil, f)
    p.mob:SetSize(40, 44)
    p.mob:SetPoint("TOP", p.bar, "BOTTOM", 0, -10)
    local head = p.mob:CreateTexture(nil, "ARTWORK")
    head:SetTexture(DUI.MEDIA .. "crest-disc.png")
    head:SetSize(40, 40)
    head:SetPoint("TOP", p.mob, "TOP", 0, 0)
    local body = tex(p.mob, "ARTWORK")
    body:SetPoint("TOPLEFT", p.mob, "TOPLEFT", 0, -20)
    body:SetPoint("BOTTOMRIGHT", p.mob, "BOTTOMRIGHT", 0, 0)
    for _, t in ipairs({ head, body }) do t:SetVertexColor(FIGURE[1], FIGURE[2], FIGURE[3], 1) end
    f.plate = p
    return f
end

-- A bag, laid out three ways: grouped under headings, one grid, or a list.
Pic.BAG_W, Pic.SLOT_PX, Pic.SLOT_GAP = 196, 17, 3
local function slot(parent, filled)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(Pic.SLOT_PX, Pic.SLOT_PX)
    local edge = tex(s, "BACKGROUND")
    edge:SetPoint("TOPLEFT", s, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 1, -1)
    edge:SetVertexColor(Style.BORDER[1], Style.BORDER[2], Style.BORDER[3], 1)
    local t = tex(s, "ARTWORK")
    t:SetAllPoints(s)
    if filled then vertical(t, SLOT_FULL, SLOT_FULL_LOW) else t:SetVertexColor(SLOT[1], SLOT[2], SLOT[3], 1) end
    local lit = tex(s, "ARTWORK", 1)
    lit:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    lit:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
    lit:SetHeight(1)
    lit:SetVertexColor(Style.BAND_LIT[1], Style.BAND_LIT[2], Style.BAND_LIT[3], 1)
    return s
end
function Pic.bags(parent, key, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(Pic.BAG_W)
    framed(f)
    f.bg = tex(f, "BACKGROUND", 1)
    f.bg:SetAllPoints(f)
    f.bg:SetVertexColor(PANEL[1], PANEL[2], PANEL[3], 1)
    local x0, y = 10, 9
    local per = math.floor((Pic.BAG_W - 20 + Pic.SLOT_GAP) / (Pic.SLOT_PX + Pic.SLOT_GAP))
    local function grid(n, full)
        for i = 1, n do
            local col, row = (i - 1) % per, math.floor((i - 1) / per)
            local s = slot(f, i <= full)
            s:SetPoint("TOPLEFT", f, "TOPLEFT", x0 + col * (Pic.SLOT_PX + Pic.SLOT_GAP), -(y + row * (Pic.SLOT_PX + Pic.SLOT_GAP)))
        end
        y = y + math.ceil(n / per) * (Pic.SLOT_PX + Pic.SLOT_GAP) - Pic.SLOT_GAP
    end
    if key == "categories" then
        for i, g in ipairs({ { L["Weapons"], 4 }, { L["Consumables"], 7 }, { L["Trade goods"], 5 } }) do
            if i > 1 then y = y + 6 end
            local h = W.Font(f, W.BODY, SIZE.tiny, C.value)
            h:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -y)
            h:SetText(DUI.InstallerChrome.Spaced(g[1]))
            Style.InkText(h, "pop")
            y = y + SIZE.tiny + 5
            grid(g[2], g[2])
        end
    elseif key == "grid" then
        grid(27, 16)
    else
        for i, name in ipairs({ L["Blade of the Dawn"], L["Healing Potion"], L["Linen Cloth"], L["Copper Ore"], L["Hearthstone"] }) do
            if i > 1 then y = y + 8 end
            local s = slot(f, true)
            s:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -y)
            local t = W.Font(f, W.BODY, 11, Style.INK.TEXT)
            t:SetPoint("LEFT", s, "RIGHT", 8, 0)
            t:SetText(name)
            y = y + Pic.SLOT_PX
        end
    end
    f:SetHeight(y + 10)
    return f
end

-- The quest helper: the tracker box in the corner, and with the helper on
-- a trail of gold dots to a lit marker.
Pic.TRAIL = { { 18, 84 }, { 26, 76 }, { 35, 70 }, { 45, 66 }, { 55, 60 }, { 63, 52 } }
function Pic.quest(parent, key, width)
    local f = Pic.Sky(parent, width)
    local w, h = f:GetWidth(), f:GetHeight()
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    box:SetWidth(w * 0.42)
    box.bg = tex(box, "BACKGROUND")
    box.bg:SetAllPoints(box)
    box.bg:SetVertexColor(PANEL[1], PANEL[2], PANEL[3], 0.8)
    local y = 6
    local gold = Style.INK.MONEY
    for _, part in ipairs({ { L["Wanted: Hogger"], 1 }, { L["The Fargodeep Mine"], 2 } }) do
        local t = W.Font(box, W.BODY, 9, gold)
        t:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -y)
        t:SetText(part[1])
        y = y + 9 + 3
        for _ = 1, part[2] do
            local l = tex(box, "ARTWORK")
            l:SetSize((w * 0.42 - 16) * 0.8, 3)
            l:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -y)
            l:SetVertexColor(Style.INK.TEXT[1], Style.INK.TEXT[2], Style.INK.TEXT[3], 0.5)
            y = y + 3 + 6
        end
    end
    box:SetHeight(y)
    f.trail = {}
    if key == "yes" then
        for i, p in ipairs(Pic.TRAIL) do
            local d = f:CreateTexture(nil, "ARTWORK")
            d:SetTexture(DUI.MEDIA .. "crest-disc.png")
            d:SetSize(6, 6)
            d:SetPoint("TOPLEFT", f, "TOPLEFT", p[1] / 100 * w, -p[2] / 100 * h)
            d:SetVertexColor(gold[1], gold[2], gold[3], 1)
            f.trail[i] = d
        end
        local m = tex(f, "OVERLAY")
        m:SetSize(14, 14)
        m:SetPoint("TOPLEFT", f, "TOPLEFT", 0.70 * w, -0.34 * h)
        m:SetRotation(math.pi / 4)
        paintPair(m, Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2])
        f.marker = m
    end
    return f
end

-- Another addon, by name, on a plain panel (the "who draws it?" question).
function Pic.addon(parent, name, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, math.floor(width * Pic.SKY_RATIO + 0.5))
    framed(f)
    f.bg = tex(f, "BACKGROUND", 1)
    f.bg:SetAllPoints(f)
    f.bg:SetVertexColor(PANEL[1], PANEL[2], PANEL[3], 1)
    f.text = W.Font(f, W.TITLE, 28, C.value, "CENTER")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text:SetText(name or "")
    return f
end
