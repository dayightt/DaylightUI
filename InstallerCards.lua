-- Setup guide building blocks: picture cards (one choice among several, or an
-- action), a picker that lays out a row of them, module tiles, clash cards,
-- and the small drawings inside cards (a screen with frames, a health bar, a
-- bag, a font sample, a color). Everything is drawn in code from the options
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
Cards.TILE_H = 84     -- a module tile's height
Cards.CLASH_H = 70    -- a clash card's height

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

-- A module tile: its name with an on/off switch (the options' own toggle,
-- reading get() and writing set(on)) and a one-line pitch below. Dimmed with
-- no switch when not installed.
function Cards.Tile(parent, mod, width, get, set, installed)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(width, Cards.TILE_H)
    t.bg = W.Round(t, "BACKGROUND")
    t.bg:SetAllPoints(t)
    W.Tint(t.bg, C.card)
    if installed then
        local item = { type = "toggle", label = mod.label, desc = mod.pitch, get = get, set = set }
        t.row = W.CompactRow(t, {}, item, width - 24)
        t.row:SetPoint("TOPLEFT", t, "TOPLEFT", 12, -10)
    else
        t.name = W.Font(t, W.BODY, SIZE.body, C.faint)
        t.name:SetPoint("TOPLEFT", t, "TOPLEFT", 12, -16)
        t.name:SetText(string.format(L["%s (not installed)"], L[mod.label]))
    end
    t.pitch = W.Font(t, W.BODY, SIZE.small, installed and C.dim or C.faint)
    t.pitch:SetWordWrap(true)
    t.pitch:SetJustifyV("TOP")
    t.pitch:SetPoint("TOPLEFT", t, "TOPLEFT", 12, -40)
    t.pitch:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -12, 8)
    t.pitch:SetText(L[mod.pitch])
    function t.Refresh()
        if t.row then t.row.Refresh() end
    end
    t.Refresh()
    return t
end

-- Another addon doing one of our modules' jobs, with the two ways out: ours
-- (listed first) or theirs. get() -> "ours" | "theirs"; set(v).
function Cards.Clash(parent, clash, width, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, Cards.CLASH_H)
    f.bg = W.Round(f, "BACKGROUND")
    f.bg:SetAllPoints(f)
    W.Tint(f.bg, C.card)
    f.edge = W.Round(f, "BORDER", 0, true)
    f.edge:SetAllPoints(f)
    W.Tint(f.edge, C.warn, 0.6)
    f.text = W.Font(f, W.BODY, SIZE.body, C.text)
    f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
    f.text:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.text:SetText(string.format(L["%s is also on. Both change your %s."], clash.label, L[clash.what]))
    f.ours = W.Button(f, L["Use DaylightUI's"], 26)
    f.ours:SetWidth(150)
    f.ours:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    f.theirs = W.Button(f, string.format(L["Keep %s"], clash.label), 26)
    f.theirs.FitWidth(150)
    f.theirs:SetPoint("LEFT", f.ours, "RIGHT", 8, 0)
    function f.Refresh()
        local v = get()
        f.ours.SetActive(v ~= "theirs")
        f.theirs.SetActive(v == "theirs")
    end
    f.ours:SetScript("OnClick", function() set("ours"); f.Refresh() end)
    f.theirs:SetScript("OnClick", function() set("theirs"); f.Refresh() end)
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
    Style.Follow(a.back, Style.BACKGROUND, 1, true)
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
local function paintBand(band, mode)
    band:SetTexture(DUI.MEDIA .. "portrait-band.png")
    if mode == "accent" then
        if not Style.AccentPair() then band:SetTexture(DUI.MEDIA .. "portrait-band-lit.png") end
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
    local inner = R * 0.772
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
    paintBand(band, ringOf())
    band:SetSize(2 * R / 0.6, 2 * R / 0.6)
    band:SetPoint("CENTER", r, "CENTER", 0, 0)
    art.ring, art.band = r, band
    bar:SetPoint("LEFT", a, "LEFT", math.ceil(reach) + 2, 0)
    bar:SetPoint("RIGHT", a, "RIGHT", -2, 0)
    card.portraitArt = art
    card.redraw = function()
        fill:SetTexture(Style.BarFile())
        if art.band then paintBand(art.band, ringOf()) end
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

-- Frame style (Unit frames, look.style): Daylight's frame with its name tab and
-- the number inside, or Ribbon's slim bar with name and number on a row above
-- and the power line below. A small sketch in the real frames' proportions
-- (Ribbon's bar 24 to its line 5), kept clear of the tick in the top right.
Cards.STYLE_TICK = 22 -- room kept for the tick
function Cards.Draw.frameStyle(card, key, w, h)
    local a = CreateFrame("Frame", nil, card.inner)
    a:SetSize(math.max(1, w - Cards.STYLE_TICK), h)
    a:SetPoint("TOPLEFT", card.inner, "TOPLEFT", 10, -10)
    local k = tonumber(DUI:Get("UnitFrames", "look.slant")) or 0.21
    local name = DUI.UnitName("player", "player") or L["Name"]
    local fills = {}
    if key == "ribbon" then
        local fillH = math.max(6, math.floor(h * 0.24 + 0.5))
        local P, gap = math.max(2, math.floor(fillH * 5 / 24 + 0.5)), 2
        local n = W.Font(a, W.BODY, SIZE.small, C.text)
        n:SetPoint("TOPLEFT", a, "TOPLEFT", 4, 0)
        n:SetText(name)
        local v = W.Font(a, W.BODY, SIZE.body, C.value)
        v:SetText("87")
        local bar = styleBar(a, fillH)
        bar:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -math.floor(h * 0.3 + 0.5))
        bar:SetPoint("RIGHT", a, "RIGHT", 0, 0)
        local H = bar:GetHeight()
        local cut = math.floor(H * k + 0.5)
        Style.Slant(bar, "right", cut)
        -- The number at the row's inner end, clear of the bar's angle.
        v:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -cut, 2)
        local line = styleBar(a, P, true)
        line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -gap)
        line:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -gap)
        local total = H + gap + line:GetHeight()
        Style.Slant(line, "right", cut * total / H, { frame = bar, height = total })
        local r, g, b = Style.PowerColor("MANA")
        line.fill:SetVertexColor(r, g, b, 1)
        fills = { bar.fill, line.fill }
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
    local def = Style.FONTS[key]
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
    Style.Follow(a.edge, b, 1, true)
    a.back = a:CreateTexture(nil, "BORDER")
    a.back:SetPoint("TOPLEFT", a, "TOPLEFT", 1, -1)
    a.back:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -1, 1)
    Style.Follow(a.back, Style.BACKGROUND, 1, true)
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
    Style.Follow(back, Style.BACKGROUND, 1, true)
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
