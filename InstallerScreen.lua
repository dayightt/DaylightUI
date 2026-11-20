-- A small picture of the whole screen with Daylight UI on it: the setup
-- guide's cards, several of its questions and its Finish page draw one. It
-- shows a layout (where your frame, the party and the bars sit), how many
-- action bars there are, what fades out of a fight and where the cast bar
-- sits, and eases from one of those to the next.
--
-- Every spot is a share of the picture's width (1 unit = 1% of it), so one
-- table draws it at any size. The sky, ground and minimap colors are the
-- picture's own art; the pieces standing for Daylight UI's frames take the
-- shell's colors, the accent at paint time and the hostile reaction red.

local _, DUI = ...
local Style, W = DUI.Style, DUI.Widgets
local C = W.COLORS

local Screen = {}
DUI.InstallerScreen = Screen

Screen.RATIO = 0.5625
Screen.FADE = { calm = 0.2, calmSide = 0.1, float = 0.04, immersiveSoft = 0.5 }
Screen.SIDE = 0.45      -- the side bar sits back a little even in a fight
Screen.YOU_FILL, Screen.FOE_FILL, Screen.XP_FILL = 0.82, 0.64, 0.42
Screen.LEAN = 22        -- degrees the frames' bars lean
Screen.GRID = 6.25      -- the blueprint's grid, in units

-- The picture's own art colors.
local ART = {
    sky = { { 0.106, 0.165, 0.290 }, { 0.227, 0.208, 0.376 }, { 0.478, 0.290, 0.416 }, { 0.788, 0.471, 0.369 } },
    skyAt = { 0, 0.30, 0.47, 0.54 },
    ground = { 0.110, 0.106, 0.086 }, groundLow = { 0.082, 0.078, 0.059 },
    groundAt = 0.545,
    chat = { 0.078, 0.078, 0.090, 0.82 },
    slot = { 0.169, 0.169, 0.192 },
    map = { 0.24, 0.35, 0.25 }, mapDark = { 0.12, 0.19, 0.14 },
    buff = { 0.353, 0.290, 0.478 },
    face = { 0.42, 0.29, 0.16 }, foeFace = { 0.48, 0.18, 0.16 },
    quest = { 1, 0.82, 0, 0.8 },
    classicRing = { 0.54, 0.42, 0.26 },
    plate = { 0.043, 0.043, 0.051 },
}

-- Ten class color pairs for the party and the raid tiles, in the mock-up's order.
local CLASSES = { "MAGE", "PALADIN", "HUNTER", "ROGUE", "WARLOCK", "SHAMAN", "DRUID", "WARRIOR", "PRIEST", "PRIEST" }

-- The pieces: left, top, width, height in units. top may be a function of
-- the state (the healer's frames sit higher). group: what fades out of a
-- fight ("a": your frame and the bars, "b": buffs, XP and the tracker).
Screen.PIECES = {
    { key = "chat", l = 2, t = 41.25, w = 23, h = 12 },
    { key = "party", l = 2, t = 12, w = 11, h = 4 * 2.4 + 3 * 1 },
    { key = "tiles", l = 37.2, t = 41, w = 25.6, h = 2 * 2.7 + 0.3 },
    { key = "you", l = 26, t = 36, healer = 33, w = 18, h = 5, group = "a" },
    { key = "target", l = 56, t = 36, healer = 33, w = 18, h = 5, fight = true },
    { key = "plateA", l = 40, t = 21, w = 9, h = 1.3, fight = true },
    { key = "plateB", l = 53, t = 17, w = 9, h = 1.3, fight = true },
    { key = "cast", w = 13, h = 1.5, fight = true },
    { key = "row1", l = (100 - 35.05) / 2, t = 56.25 - 2.4 - 2.6, w = 35.05, h = 2.6, group = "a" },
    { key = "row2", l = (100 - 35.05) / 2, t = 56.25 - 2.4 - 2.6 - 0.35 - 2.6, w = 35.05, h = 2.6, group = "a" },
    { key = "side", l = 100 - 1.4 - 2.3, t = 21, w = 2.3, h = 10 * 2.65, group = "a" },
    { key = "map", l = 100 - 2 - 13, t = 2.5, w = 13, h = 13 },
    { key = "xp", l = 100 - 2 - 13, t = 17, w = 13, h = 1, group = "b" },
    { key = "buffs", l = 100 - 17.5 - 13.1, t = 2.5, w = 13.1, h = 2.3, group = "b" },
    { key = "tracker", l = 100 - 5.6 - 11, t = 21, w = 11, h = 4 * 1.9, group = "b" },
}
Screen.CAST = { below = { 30, 42.6 }, middle = { 43.5, 37.6 }, healerUp = 3 }

local function px(f) return DUI.Pixel.Px(f, 1) end

local function plain(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    return t
end

local function paint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end

-- What each texture becomes in the blueprint: "edge" takes the piece's
-- outline color, "body" the stage's color (so the edge reads as an outline),
-- "detail" hides. The piece being built collects them.
local marking
local function mark(t, kind)
    if marking then marking[#marking + 1] = { tex = t, kind = kind } end
    return t
end

-- A box with a dark outline round it: the outline is a texture under the
-- fill, grown out by `edge` units (at least a pixel, so it shows small).
local function outlined(f, u, edge, layer)
    local e = math.max(px(f), edge * u)
    local o = plain(f, layer or "BORDER")
    o:SetPoint("TOPLEFT", f, "TOPLEFT", -e, e)
    o:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", e, -e)
    paint(o, Style.BORDER)
    return mark(o, "edge")
end

-- A leaning bar: an outline, the band inside it and the fill, each its own
-- frame cut to a parallelogram (Style.Slant with both ends the same way).
-- dir 1 leans like "/", -1 like "\".
local function leaning(parent, w, h, band, edge, dir)
    local cut = h * math.tan(math.rad(Screen.LEAN))
    local under = dir < 0 and "right" or "left"
    local function layer(inset, level)
        local f = CreateFrame("Frame", nil, parent)
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
        f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
        f:SetFrameLevel(parent:GetFrameLevel() + level)
        f.tex = plain(f, "ARTWORK")
        f.tex:SetAllPoints(f)
        Style.Clip(f, f.tex, "outer")
        Style.Slant(f, "both", cut, nil, under)
        return f
    end
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(w, h)
    b:SetFrameLevel(parent:GetFrameLevel() + 1)
    b.outline = layer(-(band + edge), 0)
    paint(b.outline.tex, Style.BORDER)
    mark(b.outline.tex, "edge")
    b.band = layer(-band, 1)
    paint(b.band.tex, Style.BAND)
    mark(b.band.tex, "body")
    b.back = layer(0, 2)
    paint(b.back.tex, ART.plate)
    mark(b.back.tex, "body")
    -- The fill: as wide as its share, cut the same way.
    b.fill = CreateFrame("Frame", nil, b)
    b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.fill:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.fill:SetFrameLevel(b:GetFrameLevel() + 3)
    b.fill.tex = mark(plain(b.fill, "ARTWORK"), "detail")
    b.fill.tex:SetAllPoints(b.fill)
    Style.Clip(b.fill, b.fill.tex, "outer")
    Style.Slant(b.fill, "both", cut, nil, under)
    function b.SetShare(share) b.fill:SetWidth(math.max(px(b), w * share)) end
    return b
end

-- A round portrait: a dark outline disc, the band ring, the face.
local function portrait(parent, size, u)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p:SetFrameLevel(parent:GetFrameLevel() + 8)
    local function disc(grow, layer)
        local t = p:CreateTexture(nil, layer)
        t:SetTexture(DUI.MEDIA .. "crest-disc.png")
        t:SetPoint("TOPLEFT", p, "TOPLEFT", -grow, grow)
        t:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", grow, -grow)
        return t
    end
    p.outline = mark(disc(math.max(px(p), 0.15 * u), "BACKGROUND"), "edge")
    paint(p.outline, Style.BORDER)
    p.ring = mark(disc(0, "BORDER"), "body")
    p.face = mark(disc(-0.55 * u, "ARTWORK"), "detail")
    return p
end

-- A row of small square slots.
local function slots(parent, n, size, gap, across, color, u)
    local list = {}
    for i = 1, n do
        local s = CreateFrame("Frame", nil, parent)
        s:SetSize(size, size)
        if across then
            s:SetPoint("TOPLEFT", parent, "TOPLEFT", (i - 1) * (size + gap), 0)
        else
            s:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((i - 1) * (size + gap) + gap))
        end
        s.edge = outlined(s, u, 0.15)
        s.fill = plain(s, "ARTWORK")
        s.fill:SetAllPoints(s)
        paint(s.fill, color)
        mark(s.fill, "body")
        s.lit = mark(plain(s, "ARTWORK", 1), "detail")
        s.lit:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
        s.lit:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
        s.lit:SetHeight(math.max(px(s), 0.15 * u))
        paint(s.lit, Style.BAND_LIT)
        list[i] = s
    end
    return list
end

local function lines(parent, u, spec)
    local out = {}
    for i, l in ipairs(spec) do
        local t = mark(plain(parent, "ARTWORK"), l.kind or "detail")
        t:SetHeight(0.8 * u)
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", l.x * u, -l.y * u)
        t:SetWidth(l.w)
        out[i] = t
    end
    return out
end

-- Builders, one per piece, filling the piece's frame f (w x h in pixels).
local build = {}

function build.chat(f, u, w, h)
    f.edge = outlined(f, u, 0.15, "BACKGROUND")
    f.bg = mark(plain(f, "BORDER", 1), "body")
    f.bg:SetAllPoints(f)
    paint(f.bg, ART.chat)
    f.lines = lines(f, u, { { x = 1.5, y = 1.5, w = w * 0.70 }, { x = 1.5, y = 3.8, w = w * 0.48 },
        { x = 1.5, y = 6.1, w = w * 0.60 } })
end

local function pairBar(f, u, w, h, pairOf)
    local b = CreateFrame("Frame", nil, f)
    b:SetSize(w, h)
    b.edge = outlined(b, u, 0.2)
    b.fill = mark(plain(b, "ARTWORK"), "body")
    b.fill:SetAllPoints(b)
    b.token = pairOf
    return b
end

function build.party(f, u)
    f.bars = {}
    for i = 1, 4 do
        local b = pairBar(f, u, 11 * u, 2.4 * u, CLASSES[i])
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * 3.4 * u)
        f.bars[i] = b
    end
end

function build.tiles(f, u)
    f.bars = {}
    for i = 1, 10 do
        local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
        local b = pairBar(f, u, 4.88 * u, 2.7 * u, CLASSES[i])
        b:SetPoint("TOPLEFT", f, "TOPLEFT", col * 5.18 * u, -row * 3 * u)
        f.bars[i] = b
    end
end

local function unitFrame(f, u, mirror)
    f.bar = leaning(f, 12.6 * u, 2.4 * u, 0.45 * u, math.max(px(f), 0.15 * u), mirror and -1 or 1)
    f.portrait = portrait(f, 5 * u, u)
    if mirror then
        f.portrait:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1 * u, -1.1 * u)
        paint(f.portrait.face, ART.foeFace)
    else
        f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 4.4 * u, -1.1 * u)
        paint(f.portrait.face, ART.face)
    end
end

function build.you(f, u) unitFrame(f, u, false); f.bar.SetShare(Screen.YOU_FILL) end
function build.target(f, u) unitFrame(f, u, true); f.bar.SetShare(Screen.FOE_FILL) end

local function plate(f, u, w, h)
    f.edge = outlined(f, u, 0.2, "BACKGROUND")
    f.bg = mark(plain(f, "BORDER", 1), "body")
    f.bg:SetAllPoints(f)
    paint(f.bg, ART.plate)
    f.fill = mark(plain(f, "ARTWORK"), "detail")
    f.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.fill:SetWidth(w * Screen.FOE_FILL)
end
build.plateA, build.plateB = plate, plate

function build.cast(f, u, w, h)
    -- A soft light round the bar, then the bar itself.
    f.light = f:CreateTexture(nil, "BACKGROUND")
    f.light:SetTexture(DUI.MEDIA .. "crest-disc.png")
    f.light:SetPoint("TOPLEFT", f, "TOPLEFT", -1 * u, 1 * u)
    f.light:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1 * u, -1 * u)
    f.light:SetVertexColor(1, 1, 1, 0.1)
    mark(f.light, "detail")
    f.bar = leaning(f, w, h, 0.3 * u, 0.15 * u, 1)
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.bar.SetShare(1)
end

function build.row1(f, u) f.slots = slots(f, 12, 2.6 * u, 0.35 * u, true, ART.slot, u) end
build.row2 = build.row1
function build.side(f, u) f.slots = slots(f, 10, 2.3 * u, 0.35 * u, false, ART.slot, u) end

function build.map(f, u)
    f.edge = outlined(f, u, 0.6, "BACKGROUND")
    f.band = mark(plain(f, "BORDER", 1), "detail")
    f.band:SetPoint("TOPLEFT", f, "TOPLEFT", -0.45 * u, 0.45 * u)
    f.band:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0.45 * u, -0.45 * u)
    paint(f.band, Style.BAND)
    f.bg = mark(plain(f, "ARTWORK"), "body")
    f.bg:SetAllPoints(f)
end

function build.xp(f, u, w)
    f.edge = outlined(f, u, 0.2, "BACKGROUND")
    f.bg = mark(plain(f, "BORDER", 1), "body")
    f.bg:SetAllPoints(f)
    paint(f.bg, ART.plate)
    f.fill = mark(plain(f, "ARTWORK"), "detail")
    f.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.fill:SetWidth(w * Screen.XP_FILL)
end

function build.buffs(f, u) f.slots = slots(f, 5, 2.3 * u, 0.4 * u, true, ART.buff, u) end

function build.tracker(f, u, w)
    local spec = {}
    for i = 1, 4 do spec[i] = { x = 0, y = (i - 1) * 1.9, w = i % 2 == 1 and w * 0.7 or w, kind = "edge" } end
    f.lines = lines(f, u, spec)
end

-- The blueprint's outline color for each piece: blue, the gradient's middle, or pink.
local PLAN = { chat = 1, party = 1, tiles = 1, you = 1, row1 = 2, row2 = 2, side = 2, plateA = 2, plateB = 2,
               target = 3, map = 3, xp = 3, buffs = 3, tracker = 3 }

local function planColor(key)
    local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
    local k = PLAN[key] or 1
    if k == 1 then return a elseif k == 3 then return z end
    return { (a[1] + z[1]) / 2, (a[2] + z[2]) / 2, (a[3] + z[3]) / 2 }
end

-- Colors that follow the accent and the gradients, painted on show.
local function paintAll(f)
    local P = f.pieces
    for _, key in ipairs({ "party", "tiles" }) do
        for _, b in ipairs(P[key].bars) do
            local lo, hi = DUI.Gradients.Colors(b.token)
            b.fill:SetVertexColor(1, 1, 1, 1)
            if lo and b.fill.SetGradient then b.fill:SetGradient("HORIZONTAL", lo, hi) end
        end
    end
    local r, g, b = Style.ReactionColor(2)
    if type(r) ~= "number" then r, g, b = 0.85, 0.33, 0.29 end
    for _, key in ipairs({ "plateA", "plateB" }) do P[key].fill:SetVertexColor(r, g, b, 1) end
    P.target.bar.fill.tex:SetVertexColor(r, g, b, 1)
    Style.PaintAccent(P.you.bar.fill.tex, 1)
    Style.PaintAccent(P.cast.bar.fill.tex, 1)
    Style.PaintAccent(P.xp.fill, 1)
    local map = P.map.bg
    map:SetVertexColor(1, 1, 1, 1)
    if map.SetGradient and CreateColor then
        local a, b = ART.mapDark, ART.map
        map:SetGradient("VERTICAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
    end
    local text = Style.INK.TEXT
    for _, t in ipairs(P.chat.lines) do t:SetVertexColor(text[1], text[2], text[3], 0.5) end
    for i, t in ipairs(P.tracker.lines) do
        if i % 2 == 1 then paint(t, ART.quest) else t:SetVertexColor(text[1], text[2], text[3], 0.55) end
    end
    local classic = f.state.portrait == "classic"
    for _, key in ipairs({ "you", "target" }) do
        local ring = P[key].portrait.ring
        if classic then
            local cr, cg, cb
            if key == "you" then
                local _, token = UnitClass("player")
                cr, cg, cb = Style.ClassColor(type(token) == "string" and token or "WARRIOR")
            end
            if type(cr) ~= "number" then cr, cg, cb = ART.classicRing[1], ART.classicRing[2], ART.classicRing[3] end
            ring:SetVertexColor(cr, cg, cb, 1)
        else
            paint(ring, Style.BAND)
        end
    end
end

-- The blueprint: the same pieces as outlines on a faint grid, no sky. Each
-- texture keeps its own color to go back to.
local function paintBlueprint(f, on)
    f.sky:SetShown(not on)
    f.plan:SetShown(on)
    if (f.blueprint == true) == on then return end
    f.blueprint = on
    for _, spec in ipairs(Screen.PIECES) do
        local c = planColor(spec.key)
        for _, m in ipairs(f.pieces[spec.key].marks) do
            local t = m.tex
            if on then
                m.r, m.g, m.b, m.a = t:GetVertexColor()
                if m.kind == "edge" then
                    t:SetVertexColor(c[1], c[2], c[3], 1)
                elseif m.kind == "body" then
                    paint(t, C.stage)
                else
                    t:Hide()
                end
            else
                if m.r then t:SetVertexColor(m.r, m.g, m.b, m.a or 1) end
                t:Show()
            end
        end
    end
    -- Your frame's bar stays filled, blue to pink.
    local t = f.pieces.you.bar.fill.tex
    t:Show()
    if on then
        local a, z = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
        t:SetVertexColor(1, 1, 1, 1)
        if t.SetGradient and CreateColor then
            t:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(z[1], z[2], z[3], 1))
        end
    end
end

-- The sky: four bands of gradient down to the horizon, then the ground and
-- two low hills on it.
local function buildSky(f, w, h)
    local sky = CreateFrame("Frame", nil, f)
    sky:SetAllPoints(f)
    local at, c = ART.skyAt, ART.sky
    local stops = { at[1], at[2], at[3], at[4], ART.groundAt }
    local colors = { c[1], c[2], c[3], c[4], c[4] }
    for i = 1, 4 do
        local t = plain(sky, "BACKGROUND")
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -stops[i] * h)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -stops[i] * h)
        t:SetHeight(math.max(0.01, (stops[i + 1] - stops[i]) * h))
        local top, low = colors[i], colors[i + 1]
        t:SetVertexColor(1, 1, 1, 1)
        if t.SetGradient and CreateColor then
            t:SetGradient("VERTICAL", CreateColor(low[1], low[2], low[3], 1), CreateColor(top[1], top[2], top[3], 1))
        end
    end
    local ground = plain(sky, "BACKGROUND", 1)
    ground:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -ART.groundAt * h)
    ground:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    ground:SetVertexColor(1, 1, 1, 1)
    if ground.SetGradient and CreateColor then
        local a, b = ART.groundLow, ART.ground
        ground:SetGradient("VERTICAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
    end
    local u = w / 100
    for _, hill in ipairs({ { 74, 34, 9 }, { 16, 40, 7 } }) do
        local t = sky:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetTexture(DUI.MEDIA .. "crest-disc.png")
        t:SetSize(2 * hill[2] * u, 2 * hill[3] * u)
        t:SetPoint("CENTER", f, "TOPLEFT", hill[1] * u, -0.55 * h)
        paint(t, ART.ground)
    end
    return sky
end

local function buildPlan(f, w, h)
    local plan = CreateFrame("Frame", nil, f)
    plan:SetAllPoints(f)
    plan.bg = plain(plan, "BACKGROUND")
    plan.bg:SetAllPoints(f)
    paint(plan.bg, C.stage)
    local u, step = w / 100, Screen.GRID * w / 100
    local line = math.max(px(f), 0.12 * u)
    for x = step, w - 0.5, step do
        local t = plain(plan, "BACKGROUND", 1)
        t:SetSize(line, h)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
        t:SetVertexColor(1, 1, 1, 0.06)
    end
    for y = step, h - 0.5, step do
        local t = plain(plan, "BACKGROUND", 1)
        t:SetSize(w, line)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        t:SetVertexColor(1, 1, 1, 0.06)
    end
    plan:Hide()
    return plan
end

-- Where a piece's top sits in a state, in units.
local function topOf(spec, state)
    if spec.key == "cast" then
        local at = Screen.CAST[state.cast] or Screen.CAST.below
        return at[2] - (state.role == "Healer" and Screen.CAST.healerUp or 0), at[1]
    end
    if state.role == "Healer" and spec.healer then return spec.healer, spec.l end
    return spec.t, spec.l
end

-- How strongly each piece shows in a state.
local function alphaOf(spec, state)
    local key = spec.key
    if spec.fight then return state.fight and 1 or 0 end
    local F = Screen.FADE
    local base = key == "side" and Screen.SIDE or 1
    if state.fight or not spec.group then return base end
    if state.role == "Immersive Preset" then
        if spec.group == "a" then return F.calm end
        return F.immersiveSoft
    end
    if state.calm == "float" then return F.float end
    if state.calm == "calm" and spec.group == "a" then return key == "side" and F.calmSide or F.calm end
    return base
end

local function shownIn(key, state)
    if state.role == "blueprint" and key == "cast" then return false end
    if key == "party" then return state.role ~= "Healer" end
    if key == "tiles" then return state.role == "Healer" end
    if key == "row2" then return state.bars ~= "one" end
    if key == "side" then return state.bars == "sides" end
    return true
end

local function place(f, spec, top, left)
    local piece = f.pieces[spec.key]
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", f, "TOPLEFT", left * f.u, -top * f.u)
end

-- width: the picture's width; its height follows (0.5625 of it).
function Screen.New(parent, width)
    local f = CreateFrame("Frame", nil, parent)
    local w, h = width, width * Screen.RATIO
    f:SetSize(w, h)
    -- The hills run past the picture's sides.
    f:SetClipsChildren(true)
    f.u = w / 100
    f.state = { role = "DPS/Tank", bars = "two", calm = "shown", cast = "below", portrait = "socket", fight = true }
    f.sky = buildSky(f, w, h)
    f.plan = buildPlan(f, w, h)
    f.pieces = {}
    f.specs = {}
    for i, spec in ipairs(Screen.PIECES) do
        local p = CreateFrame("Frame", nil, f)
        p:SetSize(spec.w * f.u, spec.h * f.u)
        p:SetFrameLevel(f:GetFrameLevel() + 2 + i)
        p.marks = {}
        marking = p.marks
        build[spec.key](p, f.u, spec.w * f.u, spec.h * f.u)
        marking = nil
        f.pieces[spec.key] = p
        f.specs[spec.key] = spec
        local top, left = topOf(spec, f.state)
        place(f, spec, top, left)
        p.top = top
    end
    -- The plate pair and the side bar are named as the tests and pictures read them.
    f.pieces.plates = { a = f.pieces.plateA, b = f.pieces.plateB }
    f.vignette = CreateFrame("Frame", nil, f)
    f.vignette:SetAllPoints(f)
    f.vignette:SetFrameLevel(f:GetFrameLevel() + 40)
    f.vignette.tex = f.vignette:CreateTexture(nil, "OVERLAY")
    -- Dark toward the edges, clear in the middle.
    f.vignette.tex:SetTexture(DUI.MEDIA .. "portrait-vignette.png")
    f.vignette.tex:SetAllPoints(f)
    f.vignette.tex:SetVertexColor(0, 0, 0, 0.7)
    f.vignette:SetAlpha(0)
    f.pieces.vignette = f.vignette

    -- state: role, bars, calm, cast, portrait, fight; fields left out keep
    -- their last value. Pieces ease from one state to the next unless instant.
    function f.Set(state, instant)
        local s = f.state
        for k, v in pairs(state or {}) do s[k] = v end
        local M = DUI.Motion
        for _, spec in ipairs(Screen.PIECES) do
            local key = spec.key
            local piece = f.pieces[key]
            piece:SetShown(shownIn(key, s))
            local top, left = topOf(spec, s)
            if top ~= piece.top or key == "cast" then
                local from = piece.top or top
                piece.top = top
                if instant or key == "cast" then
                    M.Tween(piece, top, top, 0, function(y) place(f, spec, y, left) end)
                else
                    M.Tween(piece, from, top, DUI.Fade.IN, function(y) place(f, spec, y, left) end)
                end
            end
            -- The blueprint shows every piece but the cast bar, at full strength.
            local a = alphaOf(spec, s)
            if s.role == "blueprint" then a = 1 end
            local was = piece:GetAlpha()
            if instant or not piece:IsVisible() then
                local key = piece.__duiAlphaKey
                if key then M.Tween(key, a, a, 0); key.goal = nil end
                piece:SetAlpha(a)
            else
                M.AlphaTo(piece, a, a < was and DUI.Fade.OUT or DUI.Fade.IN)
            end
        end
        local vig = (s.role == "Immersive Preset") and 1 or 0
        if instant then f.vignette:SetAlpha(vig) else M.AlphaTo(f.vignette, vig, M.SLOW) end
        paintBlueprint(f, s.role == "blueprint")
        if s.role ~= "blueprint" then paintAll(f) end
    end
    -- The accent may have changed while it was hidden.
    f:SetScript("OnShow", function() f.Set(nil, true) end)
    f.Set(nil, true)
    return f
end

-- The state for the picks so far in the setup guide: the layout, the action
-- bars, what fades out of a fight, the cast bar's spot and the portraits, in
-- a fight. Questions not asked keep the picture's own.
function Screen.FromFlow()
    local I = DUI.Installer
    local state = { fight = true, role = I.RoleShape(I.Target() or "DPS/Tank") }
    for key, id in pairs({ bars = "bars", calm = "calm", cast = "cast", portrait = "portrait" }) do
        local q = I.QuestionById(id)
        local v = q and I.Answer(q)
        if v ~= nil then state[key] = v end
    end
    return state
end
