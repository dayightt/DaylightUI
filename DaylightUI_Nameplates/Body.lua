-- A plate's border in the Daylight UI look, drawn cheaply: the same outline, warm
-- band, inner line, rounded corners, angled end and soft shadow as Style.Shell,
-- but without masks. A shell cuts its angled end and rounded corners out of whole
-- pieces with masks; a plate carried 69 of them, and masked textures are slow to
-- draw with 20-40 plates up. Here each ring of the border is a filled shape laid
-- over the one below (outline, band, inner line, then the bar, each opaque so only
-- its ring shows). The angled end is one texture leaned with SetVertexOffset and
-- the rounded corners are quarter discs. Only the bar fill keeps a mask, for its
-- angled moving edge (Style.AngleFill).

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Body = {}
ns.Body = Body

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ART = Style.SHELL_ART
local LAYERS = { "outline", "band", "line" }        -- bottom to top
local CORNERS = { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT" }
local LEFT_KEYS = { "TOPLEFT", "BOTTOMLEFT", "left" }
local RIGHT_KEYS = { "TOPRIGHT", "BOTTOMRIGHT", "right" }
local EDGES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local function general() return DUI.DB.General() end

local function texture(parent, layer, sublevel, file, key)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(file, "CLAMP", "CLAMP")
    if key then t:SetTexCoord(unpack(ART.CORNER_COORDS[key])) end
    return t
end

-- Leans a texture's lower right corner by dx along x so its right side follows
-- an angle; 0 resets it.
local leanOf = setmetatable({}, { __mode = "k" })
function Body.Lean(tex, dx)
    dx = dx or 0
    if leanOf[tex] == dx or not tex.SetVertexOffset then return end
    leanOf[tex] = dx
    pcall(tex.SetVertexOffset, tex, 4, dx, 0)
end

-- frame: what the border goes around (its size is set before each Layout).
-- opts: borderPx (screen pixels, or a function of the general setting), flat (no
-- warm band), joined (continues another frame's angle along its top, with no
-- shadow or lit line there), ref ({ frame, height }: for a joined frame, the frame
-- whose top right the angle starts at and the height it runs over), noBorder
-- (shadow only).
function Body.New(frame, opts)
    local b = { frame = frame, opts = opts or {} }
    local s = CreateFrame("Frame", nil, frame)
    s:SetAllPoints(frame)
    s:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    b.holder = s
    b.shadow = {}
    for _, key in ipairs(CORNERS) do b.shadow[key] = texture(s, "BACKGROUND", -8, ART.SHADOW, key) end
    for _, key in ipairs(EDGES) do b.shadow[key] = texture(s, "BACKGROUND", -8, WHITE) end
    b.layers = {}
    for i, name in ipairs(LAYERS) do
        local L = { mid = texture(s, "BORDER", i - 1, WHITE), left = texture(s, "BORDER", i - 1, WHITE),
                    right = texture(s, "BORDER", i - 1, WHITE) }
        for _, key in ipairs(CORNERS) do L[key] = texture(s, "BORDER", i - 1, ART.CORNER, key) end
        b.layers[name] = L
    end
    b.lit = texture(s, "BORDER", 3, WHITE)
    -- The contents' own dark background over the rings. Opaque, in the color the
    -- shell's translucent one shows over the dark line; otherwise a threat-colored
    -- inner line would tint a bar's empty part.
    b.bg = texture(s, "BORDER", 4, WHITE)
    -- Corner caps over the contents, so the bar's corners follow the curve.
    local over = CreateFrame("Frame", nil, s)
    over:SetAllPoints(frame)
    over:SetFrameLevel(frame:GetFrameLevel() + 10)
    b.over = over
    b.fillet = {}
    for _, key in ipairs(CORNERS) do b.fillet[key] = texture(over, "OVERLAY", 7, ART.FILLET, key) end
    return b
end

local function hideLayer(L)
    L.mid:Hide(); L.left:Hide(); L.right:Hide()
    for _, key in ipairs(CORNERS) do L[key]:Hide() end
end

-- One ring's filled shape, d in from the frame's edge: rounded corners of radius r
-- (always on the left, on the right only for a square end), and the angled end
-- along the frame's line moved d in (perpendicular to the line).
local function placeLayer(b, L, d)
    local s, g = b.holder, b.geo
    local r = math.max(0, g.R - d)
    local rr = g.angled and 0 or r
    local x0 = d + r
    for _, key in ipairs({ "TOPLEFT", "BOTTOMLEFT" }) do
        local c = L[key]
        c:ClearAllPoints()
        c:SetSize(r, r)
        c:SetPoint(key, s, key, d, key == "TOPLEFT" and -d or d)
        c:SetShown(r > 0)
    end
    L.left:ClearAllPoints()
    L.left:SetPoint("TOPLEFT", s, "TOPLEFT", d, -(d + r))
    L.left:SetPoint("BOTTOMRIGHT", s, "BOTTOMLEFT", d + r, d + r)
    L.left:SetShown(r > 0 and g.H - 2 * (d + r) > 0)
    L.mid:ClearAllPoints()
    L.mid:SetPoint("TOPLEFT", s, "TOPLEFT", x0, -d)
    if g.angled then
        local xTop = g.W - g.cutTop - g.lean * d / g.H - d * g.slope
        local xBot = g.W - g.cutTop - g.lean * (g.H - d) / g.H - d * g.slope
        L.mid:SetPoint("BOTTOMRIGHT", s, "BOTTOMLEFT", xTop, d)
        Body.Lean(L.mid, xBot - xTop)
        L.right:Hide()
        L.TOPRIGHT:Hide()
        L.BOTTOMRIGHT:Hide()
    else
        L.mid:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -(d + rr), d)
        Body.Lean(L.mid, 0)
        for _, key in ipairs({ "TOPRIGHT", "BOTTOMRIGHT" }) do
            local c = L[key]
            c:ClearAllPoints()
            c:SetSize(rr, rr)
            c:SetPoint(key, s, key, -d, key == "TOPRIGHT" and -d or d)
            c:SetShown(rr > 0)
        end
        L.right:ClearAllPoints()
        L.right:SetPoint("TOPRIGHT", s, "TOPRIGHT", -d, -(d + rr))
        L.right:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", -(d + rr), d + rr)
        L.right:SetShown(rr > 0 and g.H - 2 * (d + rr) > 0)
    end
    L.mid:Show()
end

-- The soft shadow around the frame, like a shell's: corner pieces centered on the
-- curve, fading edges. At an angled end the side strip leans with the cut and the
-- bottom corner moves in to where the cut ends.
local function placeShadow(b)
    local s, g, sh, o = b.holder, b.geo, b.shadow, b.opts
    local gen = general()
    local S = Pixel.Px(s, gen.shadowPx)
    local a = gen.shadowAlpha
    local T, R = g.T, g.R
    local round = R > T
    local E = round and R or T
    local joined = o.joined == true
    for _, key in ipairs(CORNERS) do
        local c = sh[key]
        local own = round and not (g.angled and (key == "TOPRIGHT" or key == "BOTTOMRIGHT"))
        local Ek = own and E or T
        c:SetTexture(own and ART.ShadowRound(E, S) or ART.SHADOW, "CLAMP", "CLAMP")
        c:SetTexCoord(unpack(ART.CORNER_COORDS[key]))
        c:ClearAllPoints()
        c:SetSize(Ek + S, Ek + S)
        local an = ART.SHADOW_ANCHOR[key]
        c:SetPoint(an[1], s, key, an[2] * Ek, an[3] * Ek)
        c:SetVertexColor(0, 0, 0, a)
        c:SetShown(not (joined and (key == "TOPLEFT" or key == "TOPRIGHT")))
    end
    local ER = g.angled and T or E
    sh.TOP:ClearAllPoints()
    sh.TOP:SetPoint("BOTTOMLEFT", s, "TOPLEFT", E, 0)
    sh.TOP:SetPoint("TOPRIGHT", s, "TOPRIGHT", -ER, S)
    sh.TOP:SetShown(not joined)
    sh.BOTTOM:ClearAllPoints()
    sh.BOTTOM:SetPoint("TOPLEFT", s, "BOTTOMLEFT", E, 0)
    sh.BOTTOM:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", g.angled and -(g.cutBottom + T) or -E, -S)
    sh.LEFT:ClearAllPoints()
    local top = joined and -T or -E
    sh.LEFT:SetPoint("TOPRIGHT", s, "TOPLEFT", 0, top)
    sh.LEFT:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", -S, E)
    -- Right side: square, or leaning with the cut from where the line crosses the
    -- strip's bottom to where it crosses its top.
    local rTop = (joined or g.angled) and -T or -E
    local rBottom = g.angled and T or E
    local inX, lean = 0, 0
    if g.angled then
        local yb, yt = g.H - rBottom, -rTop
        inX = g.cutTop + g.lean * yb / g.H
        lean = g.lean * (yb - yt) / g.H
        local c, an = sh.BOTTOMRIGHT, ART.SHADOW_ANCHOR.BOTTOMRIGHT
        c:ClearAllPoints()
        c:SetSize(T + S, T + S)
        c:SetPoint(an[1], s, "BOTTOMRIGHT", an[2] * (T + g.cutBottom), an[3] * T)
    end
    sh.RIGHT:ClearAllPoints()
    sh.RIGHT:SetPoint("TOPLEFT", s, "TOPRIGHT", -inX, rTop)
    sh.RIGHT:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", S - inX, rBottom)
    if sh.RIGHT.SetVertexOffset then
        -- Vertex 1 is upper left, 3 upper right: shear the top out along the cut.
        pcall(sh.RIGHT.SetVertexOffset, sh.RIGHT, 1, lean, 0)
        pcall(sh.RIGHT.SetVertexOffset, sh.RIGHT, 3, lean, 0)
    end
    local full, none = Style.ShadowColors(nil, a)
    -- VERTICAL: first color at the bottom; HORIZONTAL: first color at the left.
    sh.TOP:SetGradient("VERTICAL", full, none)
    sh.BOTTOM:SetGradient("VERTICAL", none, full)
    sh.LEFT:SetGradient("HORIZONTAL", none, full)
    sh.RIGHT:SetGradient("HORIZONTAL", full, none)
end

-- A ring's color: plain, or the gradient border's sweep (the long middle runs
-- across, each end takes the sweep color on its side).
local function paintLayer(L, r, g, b, a, sweep)
    if sweep then
        local lo, hi = sweep.lo, sweep.hi
        L.mid:SetVertexColor(1, 1, 1, 1)
        L.mid:SetGradient("HORIZONTAL", sweep[1], sweep[2])
        for _, key in ipairs(LEFT_KEYS) do L[key]:SetVertexColor(lo[1], lo[2], lo[3], a) end
        for _, key in ipairs(RIGHT_KEYS) do L[key]:SetVertexColor(hi[1], hi[2], hi[3], a) end
        return
    end
    L.mid:SetVertexColor(r, g, b, a)
    L.left:SetVertexColor(r, g, b, a)
    L.right:SetVertexColor(r, g, b, a)
    for _, key in ipairs(CORNERS) do L[key]:SetVertexColor(r, g, b, a) end
end

-- The accent sweep as two color objects, rebuilt only when its strength or pair
-- changes.
local sweepCache
local function sweepPair(lo, hi, a)
    local c = sweepCache
    if not c or c.a ~= a or c.lo ~= lo or c.hi ~= hi then
        sweepCache = { CreateColor(lo[1], lo[2], lo[3], a), CreateColor(hi[1], hi[2], hi[3], a), lo = lo, hi = hi, a = a }
    end
    return sweepCache
end

-- Colors from the settings plus any highlight (Body.SetColors).
function Body.Paint(b)
    local g = b.geo
    if not g then return end
    local gen = general()
    local a = b.opts.noBorder and 0 or gen.borderAlpha
    local bc = b.borderColor or Style.BORDER
    local nc = b.bandColor or Style.BAND
    local lo, hi
    if gen.gradientBorder and CreateColor ~= nil then lo, hi = Style.AccentPair() end
    local sweepBorder = lo and not g.heavy and not b.borderColor and sweepPair(lo, hi, a)
    local sweepBand = lo and g.heavy and not b.bandColor and sweepPair(lo, hi, a)
    local L = b.layers
    paintLayer(L.outline, bc[1], bc[2], bc[3], a, sweepBorder)
    paintLayer(L.band, nc[1], nc[2], nc[3], a, sweepBand)
    paintLayer(L.line, bc[1], bc[2], bc[3], a, sweepBorder)
    local lc = Style.BAND_LIT
    b.lit:SetVertexColor(lc[1], lc[2], lc[3], a)
    local bgc, k, under = Style.BACKGROUND, Style.BACKGROUND_ALPHA, Style.BORDER
    b.bg:SetVertexColor(bgc[1] * k + under[1] * (1 - k), bgc[2] * k + under[2] * (1 - k),
        bgc[3] * k + under[3] * (1 - k), 1)
    for _, key in ipairs(CORNERS) do
        local f = b.fillet[key]
        if sweepBorder then
            local c = key:find("LEFT") and sweepBorder.lo or sweepBorder.hi
            f:SetVertexColor(c[1], c[2], c[3], a)
        else
            f:SetVertexColor(bc[1], bc[2], bc[3], a)
        end
    end
end

-- A border highlight (threat): outline and line in border, the band in band
-- ({ r, g, b } each). nil restores the normal colors.
function Body.SetColors(b, border, band)
    if b.borderColor == border and b.bandColor == band then return end
    b.borderColor, b.bandColor = border, band
    if b.shellMode and b.shell then
        Style.SetShellColors(b.shell, border, band)
    else
        Body.Paint(b)
    end
end

-- A see-through border (Appearance: Border opacity under 100%): stacked rings
-- would show through each other, so the frame uses a real shell instead
-- (Style.Shell, cut by masks), exactly as elsewhere. Built the first time it's
-- needed; at full opacity (the default) it stays hidden and costs nothing.
local function shellLayout(b, px, cutTop, cutBottom, clear)
    local frame, o = b.frame, b.opts
    local opts = b.shellOpts or {}
    b.shellOpts = opts
    opts.borderPx, opts.flat, opts.noBevel, opts.noBorder = px, o.flat, true, o.noBorder
    opts.bgAlpha = clear and math.min(Style.BACKGROUND_ALPHA, clear) or nil
    opts.borderColor, opts.bandColor = b.borderColor, b.bandColor
    local first = not b.shell
    b.shell = Style.Shell(frame, opts)
    -- Built after the frame's own bars (and maybe after the frame was raised), so put
    -- it under them where the rings sit.
    if first then b.shell:SetFrameLevel(b.holder:GetFrameLevel()) end
    if cutTop ~= 0 or cutBottom ~= 0 then
        Style.Slant(frame, "right", cutBottom, o.joined and o.ref or nil)
    else
        Style.Slant(frame, nil, 0)
    end
    b.shell:SetShown(not b.off)
end

-- Lays the border around its frame. cutTop, cutBottom: how far in from the frame's
-- right edge its right end is at the top and bottom (0, 0 = a square end, rounded
-- like the left).
local layouts = 0
function Body.TakeLayoutCount()
    local n = layouts
    layouts = 0
    return n
end

function Body.Layout(b, cutTop, cutBottom)
    layouts = layouts + 1
    local frame, s, o = b.frame, b.holder, b.opts
    local gen = general()
    cutTop, cutBottom = cutTop or 0, cutBottom or 0
    local own = o.borderPx
    local px = type(own) == "function" and own(gen.borderPx) or own or gen.borderPx
    local T = Pixel.Px(s, px)
    local one = Pixel.Px(s, 1)
    local W, H = frame:GetWidth(), frame:GetHeight()
    if type(W) ~= "number" or W <= 0 then W = 1 end
    if type(H) ~= "number" or H <= 0 then H = 1 end
    -- Corner radius: its own size, never more than half the frame's smaller side, and
    -- capped at 3.4x the border like a shell's.
    local R = math.min(Pixel.Px(s, gen.cornerPx), math.min(W, H) / 2)
    if T > 0 then R = math.min(R, T * 3.4) end
    local lean = cutBottom - cutTop
    local g = b.geo or {}
    b.geo = g
    g.W, g.H, g.T, g.R, g.one = W, H, T, R, one
    g.cutTop, g.cutBottom, g.lean = cutTop, cutBottom, lean
    g.angled = cutTop ~= 0 or cutBottom ~= 0
    g.slope = math.sqrt(H * H + lean * lean) / H
    g.heavy = gen.heavyBorder ~= false and not o.flat and px >= Style.HEAVY_MIN_PX
    b.T, b.radius, b.heavy = T, R, g.heavy
    -- See-through (Missing health opacity below the default): the rings are stacked
    -- filled shapes, so the plate uses the shell, its background as solid as the
    -- empty part.
    local clear = type(o.clear) == "function" and o.clear() or nil
    b.shellMode = not o.noBorder and ((gen.borderAlpha or 1) < 1 or clear ~= nil)
    b.bg:SetAlpha(clear or 1)
    if b.shellMode then
        shellLayout(b, px, cutTop, cutBottom, clear)
        s:Hide()
        return
    end
    if b.shell then b.shell:Hide() end
    s:SetShown(not b.off)
    local L = b.layers
    if T > 0 and not o.noBorder then placeLayer(b, L.outline, 0) else hideLayer(L.outline) end
    if g.heavy and T > 0 and not o.noBorder then
        placeLayer(b, L.band, one)
        placeLayer(b, L.line, T - one)
    else
        hideLayer(L.band)
        hideLayer(L.line)
    end
    -- The band's lit top line, from the end of the corner curve to a pixel short of
    -- the cut (where the band's own line meets its lower edge).
    local lit = b.lit
    local litOn = g.heavy and T > 0 and not o.noBorder and not o.joined
    if litOn then
        lit:ClearAllPoints()
        lit:SetPoint("TOPLEFT", s, "TOPLEFT", R, -one)
        local right = R
        if g.angled then right = cutTop + one * g.slope + lean * 2 * one / H end
        lit:SetPoint("TOPRIGHT", s, "TOPRIGHT", -right, -one)
        lit:SetHeight(one)
    end
    lit:SetShown(litOn)
    -- Contents background: square (the corner caps round it off), leaned along the
    -- angle like the rings.
    local bg = b.bg
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", s, "TOPLEFT", T, -T)
    if g.angled then
        local xTop = W - cutTop - lean * T / H - T * g.slope
        local xBot = W - cutTop - lean * (H - T) / H - T * g.slope
        bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMLEFT", xTop, T)
        Body.Lean(bg, xBot - xTop)
    else
        bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -T, T)
        Body.Lean(bg, 0)
    end
    bg:SetShown(H - 2 * T > 0)
    -- Corner caps where the curve is rounder than the border is thick.
    local F = math.max(0, R - T)
    for key, sign in pairs(ART.FILLET_SIGN) do
        local f = b.fillet[key]
        f:ClearAllPoints()
        f:SetSize(F, F)
        f:SetPoint(key, s, key, sign[1] * T, sign[2] * T)
        local sharp = g.angled and (key == "TOPRIGHT" or key == "BOTTOMRIGHT")
        f:SetShown(F > 0 and T > 0 and not o.noBorder and not sharp)
    end
    placeShadow(b)
    Body.Paint(b)
end

-- How far in from the frame's right edge the contents' right end is at their top
-- (one border depth in, perpendicular to the angle), and how far the angle leans
-- over the contents' height.
function Body.InnerRight(b)
    local g = b.geo
    return g.cutTop + g.lean * g.T / g.H + g.T * g.slope
end

function Body.InnerCut(b)
    local g = b.geo
    return math.max(0, g.lean * (g.H - 2 * g.T) / g.H)
end

-- Fits a bar inside the border: its right end where the contents' angle starts at
-- the top, the fill's moving edge leaning with the cut (one mask, which also cuts
-- the end so a full bar ends on the angle), and its background and any static
-- full-width overlays leaned to match without masks.
function Body.FitBar(b, bar, overlays)
    local T = b.geo.T
    local cut = Body.InnerCut(b)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", b.frame, "TOPLEFT", T, -T)
    bar:SetPoint("BOTTOMRIGHT", b.frame, "BOTTOMRIGHT", -Body.InnerRight(b), T)
    Style.AngleFill(bar, cut > 0 and "right" or nil, cut)
    local back = Style.BarBack(bar)
    if back then Body.Lean(back, -cut) end
    for _, tex in ipairs(overlays or {}) do Body.Lean(tex, -cut) end
    return cut
end

function Body.SetShown(b, on)
    b.off = not on
    b.holder:SetShown(on and not b.shellMode)
    if b.shell then b.shell:SetShown(on and b.shellMode) end
end
