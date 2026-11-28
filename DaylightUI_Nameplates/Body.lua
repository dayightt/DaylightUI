-- A plate's border in the Daylight UI look, drawn cheaply: the same outline, warm
-- band, inner line, rounded corners, angled end and soft shadow as Style.Shell,
-- but without masks. A shell cuts its angled end and rounded corners out of whole
-- pieces with masks; a plate carried 69 of them, and masked textures are slow to
-- draw with 20-40 plates up. Here each ring of the border is a filled shape laid
-- over the one below (outline, band, inner line, then the bar, each opaque so only
-- its ring shows). The angled end is one texture leaned with SetVertexOffset and
-- the rounded corners are quarter discs. Only the bar fill keeps a mask, for its
-- angled moving edge (Style.AngleFill), and one more when its left end is angled.

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

-- Moves a texture's corners along x so its sides follow an angle. Vertex 1 is
-- the upper left, 2 the lower left, 3 the upper right, 4 the lower right; nil
-- or 0 puts a corner back. Only a change goes to the client.
local shapeOf = setmetatable({}, { __mode = "k" })
local function vertex(tex, i, dx)
    dx = dx or 0
    local s = shapeOf[tex]
    if not s then
        s = { 0, 0, 0, 0 }
        shapeOf[tex] = s
    end
    if s[i] == dx then return end
    s[i] = dx
    DUI.SafeCall(tex.SetVertexOffset, tex, i, dx, 0)
end

function Body.Shape(tex, ul, ll, ur, lr)
    if not tex.SetVertexOffset then return end
    vertex(tex, 1, ul); vertex(tex, 2, ll); vertex(tex, 3, ur); vertex(tex, 4, lr)
end

-- Leans a texture's lower right corner by dx along x so its right side follows
-- an angle; 0 resets it.
function Body.Lean(tex, dx)
    if tex.SetVertexOffset then vertex(tex, 4, dx) end
end

-- How far in from its own edge of the frame an end's line is, y down from the
-- top and d in from the edge (square to the line). side: "r" or "l" of the
-- layout's geometry.
local function inAt(g, side, y, d)
    local e = g[side]
    return e.top + e.lean * y / g.H + d * e.slope
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
-- at a square end, and an angled end along the frame's line moved d in
-- (perpendicular to the line).
local function placeLayer(b, L, d)
    local s, g = b.holder, b.geo
    local r = math.max(0, g.R - d)
    local rl = g.l.angled and 0 or r
    local rr = g.r.angled and 0 or r
    for _, key in ipairs(CORNERS) do
        local c, cr = L[key], key:find("LEFT") and rl or rr
        c:ClearAllPoints()
        c:SetSize(cr, cr)
        c:SetPoint(key, s, key, key:find("LEFT") and d or -d, key:find("TOP") and -d or d)
        c:SetShown(cr > 0)
    end
    L.left:ClearAllPoints()
    L.left:SetPoint("TOPLEFT", s, "TOPLEFT", d, -(d + rl))
    L.left:SetPoint("BOTTOMRIGHT", s, "BOTTOMLEFT", d + rl, d + rl)
    L.left:SetShown(rl > 0 and g.H - 2 * (d + rl) > 0)
    L.right:ClearAllPoints()
    L.right:SetPoint("TOPRIGHT", s, "TOPRIGHT", -d, -(d + rr))
    L.right:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", -(d + rr), d + rr)
    L.right:SetShown(rr > 0 and g.H - 2 * (d + rr) > 0)
    -- The middle reaches each end: along the line at an angled end (its lower
    -- corner moved along it), else to where the corner curve starts.
    local lTop = g.l.angled and inAt(g, "l", d, d) or d + rl
    local rTop = g.r.angled and inAt(g, "r", d, d) or d + rr
    L.mid:ClearAllPoints()
    L.mid:SetPoint("TOPLEFT", s, "TOPLEFT", lTop, -d)
    L.mid:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -rTop, d)
    local ll = g.l.angled and (inAt(g, "l", g.H - d, d) - lTop) or 0
    local lr = g.r.angled and (rTop - inAt(g, "r", g.H - d, d)) or 0
    Body.Shape(L.mid, 0, ll, 0, lr)
    L.mid:Show()
end

-- One side strip of the shadow. At an angled end it leans with the cut, placed by
-- where the line crosses the strip's bottom and sheared out to where it crosses
-- its top.
local function placeSideShadow(b, side, S, E)
    local s, g, sh, o = b.holder, b.geo, b.shadow, b.opts
    local T, e = g.T, g[side]
    local top = (o.joined == true or e.angled) and -T or -E
    local bottom = e.angled and T or E
    local inX, lean = 0, 0
    if e.angled then
        local yb, yt = g.H - bottom, -top
        inX = e.top + e.lean * yb / g.H
        lean = e.lean * (yb - yt) / g.H
    end
    if side == "r" then
        local t = sh.RIGHT
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", s, "TOPRIGHT", -inX, top)
        t:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", S - inX, bottom)
        Body.Shape(t, lean, 0, lean, 0)
    else
        local t = sh.LEFT
        t:ClearAllPoints()
        t:SetPoint("TOPRIGHT", s, "TOPLEFT", inX, top)
        t:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", inX - S, bottom)
        Body.Shape(t, -lean, 0, -lean, 0)
    end
end

-- The soft shadow around the frame, like a shell's: corner pieces centered on the
-- curve, fading edges. At an angled end the side strip leans with the cut and the
-- corners move in to where the cut puts them.
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
        local e = key:find("RIGHT") and g.r or g.l
        local own = round and not e.angled
        local Ek = own and E or T
        local cut = e.angled and (key:find("TOP") and e.top or e.bottom) or 0
        c:SetTexture(own and ART.ShadowRound(E, S) or ART.SHADOW, "CLAMP", "CLAMP")
        c:SetTexCoord(unpack(ART.CORNER_COORDS[key]))
        c:ClearAllPoints()
        c:SetSize(Ek + S, Ek + S)
        local an = ART.SHADOW_ANCHOR[key]
        c:SetPoint(an[1], s, key, an[2] * (Ek + cut), an[3] * Ek)
        c:SetVertexColor(0, 0, 0, a)
        c:SetShown(not (joined and (key == "TOPLEFT" or key == "TOPRIGHT")))
    end
    local l, r = g.l, g.r
    sh.TOP:ClearAllPoints()
    sh.TOP:SetPoint("BOTTOMLEFT", s, "TOPLEFT", l.angled and (l.top + T) or E, 0)
    sh.TOP:SetPoint("TOPRIGHT", s, "TOPRIGHT", -(r.angled and (r.top + T) or E), S)
    sh.TOP:SetShown(not joined)
    sh.BOTTOM:ClearAllPoints()
    sh.BOTTOM:SetPoint("TOPLEFT", s, "BOTTOMLEFT", l.angled and (l.bottom + T) or E, 0)
    sh.BOTTOM:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -(r.angled and (r.bottom + T) or E), -S)
    placeSideShadow(b, "l", S, E)
    placeSideShadow(b, "r", S, E)
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
local function shellLayout(b, px, clear)
    local frame, o, g = b.frame, b.opts, b.geo
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
    local l, r = g.l, g.r
    local side = (l.angled and r.angled and "both") or (r.angled and "right") or (l.angled and "left") or nil
    if not side then
        Style.Slant(frame, nil, 0)
    elseif o.joined and o.ref then
        -- A bar hung under another carries its line on (ref.cut over ref.height, an
        -- end under a flipped one starting at that frame's bottom: ref.drop).
        Style.Slant(frame, side, o.ref.cut or math.max(r.bottom, l.bottom), o.ref)
    else
        -- An end leans under when its bottom corner sticks out.
        local lu, ru = l.angled and l.lean < 0, r.angled and r.lean < 0
        local under = (lu and ru and "both") or (ru and "right") or (lu and "left") or nil
        Style.Slant(frame, side, math.max(math.abs(r.lean), math.abs(l.lean)), nil, under)
    end
    b.shell:SetShown(not b.off)
end

-- Lays the border around its frame. cutTop, cutBottom: how far in from the frame's
-- right edge its right end is at the top and bottom; leftTop, leftBottom the same
-- for the left end from the left edge (0, 0 = a square end, rounded).
local layouts = 0
function Body.TakeLayoutCount()
    local n = layouts
    layouts = 0
    return n
end

local function endGeo(e, top, bottom, H)
    e.top, e.bottom = top, bottom
    e.lean = bottom - top
    e.angled = top ~= 0 or bottom ~= 0
    e.slope = math.sqrt(H * H + e.lean * e.lean) / H
    return e
end

function Body.Layout(b, cutTop, cutBottom, leftTop, leftBottom)
    layouts = layouts + 1
    local frame, s, o = b.frame, b.holder, b.opts
    local gen = general()
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
    local g = b.geo or { l = {}, r = {} }
    b.geo = g
    g.W, g.H, g.T, g.R, g.one = W, H, T, R, one
    local r = endGeo(g.r, cutTop or 0, cutBottom or 0, H)
    local l = endGeo(g.l, leftTop or 0, leftBottom or 0, H)
    -- The right end's numbers by their older names (the cast bar's kick pieces).
    g.cutTop, g.cutBottom, g.lean, g.angled, g.slope = r.top, r.bottom, r.lean, r.angled, r.slope
    g.heavy = gen.heavyBorder ~= false and not o.flat and px >= Style.HEAVY_MIN_PX
    b.T, b.radius, b.heavy = T, R, g.heavy
    -- See-through (Missing health opacity below the default): the rings are stacked
    -- filled shapes, so the plate uses the shell, its background as solid as the
    -- empty part.
    local clear = type(o.clear) == "function" and o.clear() or nil
    b.shellMode = not o.noBorder and ((gen.borderAlpha or 1) < 1 or clear ~= nil)
    b.bg:SetAlpha(clear or 1)
    if b.shellMode then
        shellLayout(b, px, clear)
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
    -- The band's lit top line, from the end of each corner curve to a pixel short
    -- of an angled end's cut (where the band's own line meets its lower edge).
    local lit = b.lit
    local litOn = g.heavy and T > 0 and not o.noBorder and not o.joined
    if litOn then
        local function stop(e) return e.angled and (e.top + one * e.slope + e.lean * 2 * one / H) or R end
        lit:ClearAllPoints()
        lit:SetPoint("TOPLEFT", s, "TOPLEFT", stop(l), -one)
        lit:SetPoint("TOPRIGHT", s, "TOPRIGHT", -stop(r), -one)
        lit:SetHeight(one)
    end
    lit:SetShown(litOn)
    -- Contents background: square (the corner caps round it off), leaned along an
    -- angled end like the rings.
    local bg = b.bg
    local bl = l.angled and inAt(g, "l", T, T) or T
    local br = r.angled and inAt(g, "r", T, T) or T
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", s, "TOPLEFT", bl, -T)
    bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -br, T)
    Body.Shape(bg, 0, l.angled and (inAt(g, "l", H - T, T) - bl) or 0,
        0, r.angled and (br - inAt(g, "r", H - T, T)) or 0)
    bg:SetShown(H - 2 * T > 0)
    -- Corner caps where the curve is rounder than the border is thick.
    local F = math.max(0, R - T)
    for key, sign in pairs(ART.FILLET_SIGN) do
        local f = b.fillet[key]
        f:ClearAllPoints()
        f:SetSize(F, F)
        f:SetPoint(key, s, key, sign[1] * T, sign[2] * T)
        local sharp = (key:find("RIGHT") and r or l).angled
        f:SetShown(F > 0 and T > 0 and not o.noBorder and not sharp)
    end
    placeShadow(b)
    Body.Paint(b)
end

-- How far in from the frame's right edge the contents' right end is at their top
-- (one border depth in, perpendicular to the angle).
function Body.InnerRight(b)
    local g = b.geo
    return inAt(g, "r", g.T, g.T)
end

-- How far an end's line leans over the contents' height ("r" or "l", right if
-- left out), and whether it leans under (its bottom corner out).
function Body.InnerCut(b, side)
    local g = b.geo
    local c = g[side or "r"].lean * (g.H - 2 * g.T) / g.H
    return math.abs(c), c < 0
end

-- A bar's left end cut at an angle: a mask on its fill (and on clips, textures
-- laid over the fill) through the core's Style.Slant on the bar itself. A square
-- left end (the usual) adds nothing.
local leftCut = setmetatable({}, { __mode = "k" })
function Body.ClipLeft(bar, cut, under, clips)
    if cut > 0 then
        Style.Clip(bar, bar:GetStatusBarTexture(), "outer", nil, "left")
        for _, tex in ipairs(clips or {}) do Style.Clip(bar, tex, "outer", nil, "left") end
        local was = leftCut[bar]
        if not (was and was.cut == cut and was.under == under) then
            leftCut[bar] = { cut = cut, under = under }
            Style.Slant(bar, "left", cut, nil, under and "left" or nil)
        end
    elseif leftCut[bar] then
        leftCut[bar] = nil
        Style.Slant(bar, nil, 0)
    end
end

-- Fits a bar inside the border, reaching each end's outer corner: the fill's
-- moving edge leans with the right end (one mask, which also cuts that end so a
-- full bar ends on the angle), an angled left end gets a mask of its own
-- (Body.ClipLeft, also on clips), and its background and any static full-width
-- overlays are leaned to match without masks. Returns each end's cut and whether
-- it leans under: right, then left.
function Body.FitBar(b, bar, overlays, clips)
    local g = b.geo
    local T = g.T
    local rCut, rUnder = Body.InnerCut(b, "r")
    local lCut, lUnder = Body.InnerCut(b, "l")
    -- A flipped end's outer corner is its bottom one, a cut further out.
    local rIn = Body.InnerRight(b) - (rUnder and rCut or 0)
    local lIn = inAt(g, "l", T, T) - (lUnder and lCut or 0)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", b.frame, "TOPLEFT", lIn, -T)
    bar:SetPoint("BOTTOMRIGHT", b.frame, "BOTTOMRIGHT", -rIn, T)
    Style.AngleFill(bar, rCut > 0 and "right" or nil, rCut, rUnder)
    Body.ClipLeft(bar, lCut, lUnder, clips)
    -- The corner each angled end pulls in: the lower one, or the upper one when flipped.
    local ul, ll = lUnder and lCut or 0, lUnder and 0 or lCut
    local ur, lr = rUnder and -rCut or 0, rUnder and 0 or -rCut
    local back = Style.BarBack(bar)
    if back then Body.Shape(back, ul, ll, ur, lr) end
    for _, tex in ipairs(overlays or {}) do Body.Shape(tex, ul, ll, ur, lr) end
    return rCut, rUnder, lCut, lUnder
end

function Body.SetShown(b, on)
    b.off = not on
    b.holder:SetShown(on and not b.shellMode)
    if b.shell then b.shell:SetShown(on and b.shellMode) end
end
