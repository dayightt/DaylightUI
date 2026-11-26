-- The soft styles: Slosh (water), Molten (soft lava) and Cinders (soft
-- embers). The fill stays a plain, readable bar: its color, its edge and its
-- value are untouched. The life sits in soft light inside it, at its surface
-- and at its end. Every layer is anchored to the fill and cut by its masks,
-- so nothing reaches past where a bar ends. At rest the client runs every
-- motion (animation groups); a hit or a heal is a short tween. Nothing reads
-- the bar's value.

local _, DUI = ...
local Style, BarFx, L = DUI.Style, DUI.BarFx, DUI.L
local M = DUI.MEDIA

BarFx.GLOW = M .. "barfx-glow.png"       -- a glow rising toward the end
BarFx.DEPTH = M .. "barfx-depth.png"     -- sheen on top, shade below
BarFx.BAND = M .. "barfx-band.png"       -- the band a heal runs along the fill
BarFx.SURFACE = M .. "barfx-surface.png" -- Slosh's waterline
BarFx.BLOOM = M .. "barfx-bloom.png"     -- a round light on the end, fading straight from its middle
BarFx.HOT = { 1, 0.93, 0.70 }            -- the second color is mixed toward this to light with
BarFx.HOT_MIX = 0.6
BarFx.SHADE_MAX = 0.34                   -- the darkest any layer makes the fill
BarFx.BLOOM_SPAN = 3                     -- the bloom on the end, in bar heights
BarFx.CINDERS_GLOW = 5                   -- how far back the end's glow reaches, in bar heights
BarFx.MOLTEN_GLOW = 4
-- The motes' sheet: 272 frames, 8 a row, over 9 s (about 30 a second; 128
-- frames over 18 s stepped too slowly and looked choppy in game).
BarFx.CINDERS_LOOP, BarFx.CINDERS_FRAMES, BarFx.CINDERS_COLS = 9, 272, 8
BarFx.MOTES_REST = 0.5                   -- the motes' sheet peaks at twice what shows at rest
BarFx.SURFACE_LOOP = 8
BarFx.SURFACE_FRAMES = 256
-- The pattern tiles' widths: the client repeats a tile at its file's width
-- (seen in game), so each is drawn as wide as one repeat (tools/make_barfx.py).
BarFx.TILE_WIDE, BarFx.TILE_THIN = 256, 128

local WHITE, BLACK = { 1, 1, 1 }, { 0, 0, 0 }
local Mix, Pin, Lean = BarFx.Mix, BarFx.Pin, BarFx.Lean

local function hotOf(hi) return Mix(hi, BarFx.HOT, BarFx.HOT_MIX) end

-- ---- What every soft style is made of ----

local function texture(p, s, sub, blend)
    local t = s.bar:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetBlendMode(blend or "ADD")
    -- Laid over the fill and given its angled end, now and whenever it moves;
    -- a light pinned to the end is placed in layout instead.
    Style.FollowFill(s.bar, t)
    p.layers[#p.layers + 1] = t
    return t
end

-- A layer the fill's size, its image stretched over it.
local function over(p, s, sub, blend, file)
    local t = texture(p, s, sub, blend)
    t:SetTexture(file or BarFx.WHITE, "CLAMP", "CLAMP")
    return t
end

-- A light pinned to the fill's moving end: leaned with it and also cut to the
-- bar's rectangle, so it can't show past a nearly empty fill.
local function pinned(p, s, sub, file)
    local t = texture(p, s, sub)
    if file then t:SetTexture(file, "CLAMP", "CLAMP") end
    p.pinned[#p.pinned + 1] = t
    p.isPin[t] = true
    return t
end

-- A pattern repeated along the fill and drifting: the tile repeats at its own
-- width (never stretched with the value), and the client scrolls it one tile
-- a loop with a TextureCoordTranslation made from BarFxSoft.xml (this client
-- won't make one from Lua). Snapped to whole pixels, a slow drift jumps a
-- pixel every few frames, so it isn't. speed is px a second on a 30 px bar;
-- away drifts toward the bar's start.
local function pattern(p, s, sub, blend, name, speed, away)
    local t = texture(p, s, sub, blend)
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
    t:SetHorizTile(true)
    p.patterns[#p.patterns + 1] = {
        tex = t, name = name, speed = speed, away = away == true,
        right = t:CreateAnimationGroup(nil, "DaylightUIBarFxDriftRight"),
        left = t:CreateAnimationGroup(nil, "DaylightUIBarFxDriftLeft"),
    }
    return t
end

local function group(p, s)
    local g = s.bar:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    p.still[#p.still + 1] = g
    return g
end

local function flipbook(g, t, loop, frames, cols)
    local a = g:CreateAnimation("FlipBook")
    a:SetTarget(t)
    a:SetDuration(loop)
    a:SetFlipBookRows(frames / cols)
    a:SetFlipBookColumns(cols)
    a:SetFlipBookFrames(frames)
    a:SetFlipBookFrameWidth(0)
    a:SetFlipBookFrameHeight(0)
    return a
end

-- Every group the piece plays now: its own, and each pattern's scroll the
-- way the bar fills.
local function groupsOf(p)
    local list = {}
    for _, g in ipairs(p.still) do list[#list + 1] = g end
    for _, pat in ipairs(p.patterns) do list[#list + 1] = pat.group or pat.right end
    p.anim = list[1]
    return list
end

local function playing(s, p, on)
    local was = p.on
    p.on = on
    for _, t in ipairs(p.layers) do t:SetShown(on) end
    -- Coming on it starts over, and so it does when BarFx.Restart stopped it
    -- after a loading screen; already on (a repaint) it keeps going.
    local over = not was or (p.anim and not p.anim:IsPlaying())
    for _, g in ipairs(groupsOf(p)) do
        if on then
            if over then g:Stop() end
            g:Play()
            if g.SetAnimationSpeedMultiplier then g:SetAnimationSpeedMultiplier(math.max(0.05, s.speed or 1)) end
        else
            g:Stop()
        end
    end
end

-- A new piece, started over on show (the game stops a frame's animations
-- while it's hidden).
local function piece(s, name)
    local p = { layers = {}, pinned = {}, isPin = {}, patterns = {}, still = {}, boost = {}, active = {}, keys = {} }
    s.bar:HookScript("OnShow", function()
        if p.on and s.style == name then
            for _, g in ipairs(groupsOf(p)) do g:Stop() end
            playing(s, p, true)
        end
    end)
    return p
end

-- Where the end is: side, cut, under, thin, left.
local function endOf(bar, h)
    local left = bar.GetReverseFill ~= nil and bar:GetReverseFill() == true
    local _, cut, under = Style.GetFillAngle(bar)
    return left and "LEFT" or "RIGHT", cut or 0, under == true, h < BarFx.THIN, left
end

-- The tiles for the bar's height, and how long one tile's drift takes.
local function layPatterns(s, p, h, thin, left)
    local wide = thin and BarFx.TILE_THIN or BarFx.TILE_WIDE
    for _, pat in ipairs(p.patterns) do
        local file = M .. "barfx-" .. pat.name .. (thin and "-thin" or "") .. ".png"
        if pat.file ~= file then
            pat.file = file
            pat.tex:SetTexture(file, "REPEAT", "REPEAT")
            pat.tex:SetHorizTile(true)
        end
        local loop = wide / (pat.speed * h / 30)
        pat.right:GetAnimations():SetDuration(loop)
        pat.left:GetAnimations():SetDuration(loop)
        -- Toward the end is right on a bar filling right, left on one filling left.
        local want = (pat.away == left) and pat.right or pat.left
        if pat.group ~= want then
            local was = pat.group
            pat.group = want
            if p.on then
                if was then was:Stop() end
                want:Play()
                if want.SetAnimationSpeedMultiplier then want:SetAnimationSpeedMultiplier(math.max(0.05, s.speed or 1)) end
            end
        end
    end
end

-- The end Molten and Cinders share: a glow reaching back from it, a bloom on
-- it and a bright line along it. Sheen and shade lie over the whole fill.
local function softEnd(p, s, subs)
    p.depth = over(p, s, subs.depth, "BLEND", BarFx.DEPTH)
    p.glow = pinned(p, s, subs.glow, BarFx.GLOW)
    p.bloom = pinned(p, s, subs.bloom, BarFx.BLOOM)
    p.line = pinned(p, s, subs.line, BarFx.WHITE)
end

local function layEnd(s, p, h, side, cut, under, thin, left, glowSpan)
    local fill = s.bar:GetStatusBarTexture()
    if p.flipped ~= left then
        p.flipped = left
        p.glow:SetTexCoord(left and 1 or 0, left and 0 or 1, 0, 1)
        p.bloom:SetTexCoord(left and 1 or 0, left and 0 or 1, 0, 1)
    end
    local px = DUI.Pixel.Px(s.bar, 1)
    Pin(p.glow, fill, side, h * glowSpan)
    Pin(p.bloom, fill, side, h * (BarFx.BLOOM_SPAN + (p.boost.bloom or 0)))
    Pin(p.line, fill, side, thin and px or 2 * px)
    for _, t in ipairs(p.pinned) do Lean(t, side, cut, under) end
end

-- Paints every layer at its resting alpha plus what the reactions running
-- now add. rest[texture] = { color, alpha, boost key }.
local function light(p)
    local a = p.alpha or 1
    for key in pairs(p.boost) do p.boost[key] = 0 end
    for _, r in pairs(p.active) do
        for key, v in pairs(r.peaks) do p.boost[key] = (p.boost[key] or 0) + v * r.size * r.k end
    end
    for t, r in pairs(p.rest or {}) do
        local c = r[1]
        local v = math.min(1, (r[2] + (r[3] and p.boost[r[3]] or 0)) * a)
        -- Darkening never hides the fill.
        if c == BLACK then v = math.min(BarFx.SHADE_MAX, v) end
        t:SetVertexColor(c[1], c[2], c[3], v)
    end
    if p.h and p.bloom then p.bloom:SetWidth(p.h * (BarFx.BLOOM_SPAN + (p.boost.bloom or 0))) end
end

local function masks(s, p)
    local fill = s.bar:GetStatusBarTexture()
    for _, t in ipairs(p.layers) do Style.SameMasks(t, fill, p.isPin[t] == true) end
end

-- A hit or a heal: what it lights goes at once to its peak and fades back
-- over dur (SLOW unless said). One tween per kind of reaction, so a second
-- one restarts it from full and nothing is left lit. step(k) does anything
-- else that moves with it.
local function react(p, kind, peaks, size, dur, step)
    local Motion = DUI.Motion
    p.keys[kind] = p.keys[kind] or {}
    local r = { peaks = peaks, size = size, k = 1 }
    p.active[kind] = r
    Motion.Tween(p.keys[kind], 1, 0, dur or Motion.SLOW, function(k)
        r.k = k
        if step then step(k) end
        light(p)
    end, function()
        if p.active[kind] == r then p.active[kind] = nil end
    end)
end

-- The band a heal sends along the fill, start to end, fading as it goes. It
-- lies over the fill with the fill's own masks, placed by its coordinates
-- (the fill's width can't be read), about 100 px wide on a 30 px bar.
BarFx.BAND_WIDE = 100
local function band(s, p, k)
    local w, h = s.bar:GetWidth(), s.bar:GetHeight()
    if type(w) ~= "number" or w <= 0 then return end
    local half = BarFx.BAND_WIDE * h / 30 / 2 / w
    local at = p.flipped and k or 1 - k
    local l = -(at - half) / (2 * half)
    p.band:SetTexCoord(l, l + 1 / (2 * half), 0, 1)
end

-- ---- Slosh ----
-- Water: soft light drifting inside, a waterline near the top with the empty
-- bar's dark above it, a line down the end. A hit tips the surface (the end
-- down) and dims the water a moment; a heal tips it the other way and runs a
-- band of light along it. The surface is a flipbook (its two ripples run
-- opposite ways, which no single scroll can do), in pieces chained back from
-- the end so none reaches past it.
local SURFACE_ROWS = 40 / 64             -- a frame's height in bar heights: 18.75 px on a 30 px bar
local SURFACE_ROOM = 4 / 30              -- room above the bar's top for the surface to tip down
BarFx.SLOSH_TIP = 4                      -- px a hit tips the end down, on a 30 px bar
BarFx.SLOSH_HEAL_TIP = 3.4
BarFx.SLOSH_PIECES = 2

local function tilt(s, p, v)
    p.tip = v
    local w, h = s.bar:GetWidth(), s.bar:GetHeight()
    if type(w) ~= "number" or w <= 0 or not p.pieceW then return end
    local room = SURFACE_ROOM * h
    -- v is how far the end moves up (down when below 0); the far side moves
    -- the other way, the slope measured over the bar's width.
    local function at(e)
        local d = v * (1 - 2 * e / w)
        return math.max(-room, math.min(room, d))
    end
    for i, t in ipairs(p.surface) do
        local near, far = at((i - 1) * p.pieceW), at(i * p.pieceW)
        -- Corners: 1 top left, 2 bottom left, 3 top right, 4 bottom right.
        local l, r = far, near
        if p.flipped then l, r = near, far end
        t:SetVertexOffset(1, 0, l); t:SetVertexOffset(2, 0, l)
        t:SetVertexOffset(3, 0, r); t:SetVertexOffset(4, 0, r)
    end
end

BarFx.Add("slosh", function() return L["Slosh"] end, {
    build = function(s)
        local p = piece(s, "slosh")
        local sub = BarFx.FILL_SUB
        pattern(p, s, sub + 1, "ADD", "caustic", 9)
        pattern(p, s, sub + 1, "ADD", "caustic-b", 6, true)
        p.depth = over(p, s, sub + 2, "BLEND", BarFx.DEPTH)
        p.dim = over(p, s, sub + 3, "BLEND")
        p.band = over(p, s, sub + 4, "ADD", BarFx.BAND)
        p.surface = {}
        local g = group(p, s)
        for i = 1, BarFx.SLOSH_PIECES do
            p.surface[i] = pinned(p, s, sub + 5, BarFx.SURFACE)
            p.surface[i]:SetBlendMode("BLEND")
            flipbook(g, p.surface[i], BarFx.SURFACE_LOOP, BarFx.SURFACE_FRAMES, BarFx.SHEET_COLS)
        end
        p.line = pinned(p, s, sub + 6, BarFx.WHITE)
        return p
    end,
    layout = function(s, p, w, h)
        local bar, fill = s.bar, s.bar:GetStatusBarTexture()
        local side, cut, under, thin, left = endOf(bar, h)
        p.h, p.flipped = h, left
        layPatterns(s, p, h, thin, left)
        -- Two pieces, each one repeat (8 heights) or half the bar, whichever is
        -- longer, chained back from the end; past the bar's start they're cut.
        p.pieceW = math.max(8 * h, w / BarFx.SLOSH_PIECES)
        local back = left and 1 or -1
        for i, t in ipairs(p.surface) do
            t:ClearAllPoints()
            local x = back * (i - 1) * p.pieceW
            t:SetPoint("TOP" .. side, fill, "TOP" .. side, x, SURFACE_ROOM * h)
            t:SetSize(p.pieceW, SURFACE_ROWS * h)
        end
        local px = DUI.Pixel.Px(bar, 1)
        Pin(p.line, fill, side, thin and px or 2 * px)
        Lean(p.line, side, cut, under)
        tilt(s, p, p.tip or 0)
    end,
    show = playing,
    paint = function(s, p, lo, hi, alpha)
        -- A fill whose colors are secret keeps its plain look.
        if not hi then return false end
        masks(s, p)
        p.alpha = alpha
        p.dim:SetVertexColor(0, 0, 0, 0)
        p.rest = {
            [p.patterns[1].tex] = { WHITE, 0.50 },
            [p.patterns[2].tex] = { WHITE, 0.38 },
            [p.depth] = { WHITE, 1 },
            [p.dim] = { BLACK, 0, "dim" },
            [p.band] = { WHITE, 0, "band" },
            [p.line] = { WHITE, 0.85 },
        }
        for _, t in ipairs(p.surface) do p.rest[t] = { WHITE, 1 } end
        light(p)
    end,
    kick = function(s, p, dir, size)
        local Motion = DUI.Motion
        local h = s.bar:GetHeight() or 30
        p.keys.rock = p.keys.rock or {}
        if dir < 0 then
            react(p, "dim", { dim = 0.22 }, size)
            Motion.Rock(p.keys.rock, -BarFx.SLOSH_TIP * h / 30 * size, function(v) tilt(s, p, v) end)
        else
            react(p, "band", { band = 0.35 }, size, Motion.SLOW * 2, function(k) band(s, p, k) end)
            Motion.Rock(p.keys.rock, BarFx.SLOSH_HEAL_TIP * h / 30 * size, function(v) tilt(s, p, v) end)
        end
    end,
})

-- ---- Molten ----
-- Soft lava: dark crust drifting slowly with bright seams running through its
-- gaps, a second, fainter copy of the seams drifting faster so they slowly
-- change shape, and a warm end. A hit leaves it be (a flash on every hit was
-- too busy); a heal warms the seams and runs a band of heat along the fill.
local MOLTEN_HEAL = { seams = 0.30, bloom = 1.0 }

BarFx.Add("molten", function() return L["Molten"] end, {
    build = function(s)
        local p = piece(s, "molten")
        local sub = BarFx.FILL_SUB
        pattern(p, s, sub + 1, "BLEND", "crust", 3)
        pattern(p, s, sub + 2, "ADD", "seam", 3)
        pattern(p, s, sub + 2, "ADD", "seam-b", 5.5)
        softEnd(p, s, { depth = sub + 3, glow = sub + 4, bloom = sub + 5, line = sub + 6 })
        p.band = over(p, s, sub + 5, "ADD", BarFx.BAND)
        return p
    end,
    layout = function(s, p, w, h)
        local side, cut, under, thin, left = endOf(s.bar, h)
        p.h = h
        layPatterns(s, p, h, thin, left)
        layEnd(s, p, h, side, cut, under, thin, left, BarFx.MOLTEN_GLOW)
    end,
    show = playing,
    paint = function(s, p, lo, hi, alpha)
        if not hi then return false end
        masks(s, p)
        local hot = hotOf(hi)
        p.alpha = alpha
        p.rest = {
            [p.patterns[1].tex] = { WHITE, 1 },   -- the crust is black in the image
            [p.patterns[2].tex] = { hot, 0.50, "seams" },
            [p.patterns[3].tex] = { hot, 0.20, "seamsB" },
            [p.depth] = { WHITE, 1 },
            -- The end at half the mock-up's light: at full, a player bar's end washed out white.
            [p.glow] = { hot, 0.20, "glow" },
            [p.bloom] = { hot, 0.30 },
            [p.band] = { hot, 0, "band" },
            [p.line] = { Mix(hot, WHITE, 0.5), 0.95 },
        }
        light(p)
    end,
    kick = function(s, p, dir, size)
        if dir < 0 then return end
        react(p, "flare", MOLTEN_HEAL, size)
        react(p, "band", { band = 0.40 }, size, DUI.Motion.SLOW * 2, function(k) band(s, p, k) end)
    end,
})

-- ---- Cinders ----
-- Soft round lights with no hard core drift up and back off a warm end. The
-- sheet is white, its motes peaking at twice the strength they show at rest,
-- so a hit can lift them.
local CINDERS_HIT = { glow = 0.30, motes = 0.30 / 0.68, bloom = 1.6 }
local CINDERS_HEAL = { glow = 0.20, bloom = 1.0 }

BarFx.Add("cinders", function() return L["Cinders"] end, {
    build = function(s)
        local p = piece(s, "cinders")
        local sub = BarFx.FILL_SUB
        softEnd(p, s, { depth = sub + 1, glow = sub + 2, bloom = sub + 4, line = sub + 5 })
        p.motes = pinned(p, s, sub + 3)
        flipbook(group(p, s), p.motes, BarFx.CINDERS_LOOP, BarFx.CINDERS_FRAMES, BarFx.CINDERS_COLS)
        return p
    end,
    layout = function(s, p, w, h)
        local side, cut, under, thin, left = endOf(s.bar, h)
        p.h = h
        local art = (thin and "thin" or "tall") .. side
        if p.art ~= art then
            p.art = art
            -- CLAMP, or the game blends each edge with the far one.
            p.motes:SetTexture(BarFx.SheetFile("cinders", thin, left), "CLAMP", "CLAMP")
        end
        layEnd(s, p, h, side, cut, under, thin, left, BarFx.CINDERS_GLOW)
        Pin(p.motes, s.bar:GetStatusBarTexture(), side, h * (thin and BarFx.THIN_SPAN or BarFx.SHEET_SPAN))
    end,
    show = playing,
    paint = function(s, p, lo, hi, alpha)
        if not hi then return false end
        masks(s, p)
        local hot = hotOf(hi)
        p.alpha = alpha
        p.rest = {
            [p.depth] = { WHITE, 1 },
            -- The end at half the mock-up's light, like Molten's.
            [p.glow] = { hot, 0.21, "glow" },
            [p.motes] = { hot, BarFx.MOTES_REST, "motes" },
            [p.bloom] = { hot, 0.30 },
            [p.line] = { Mix(hot, WHITE, 0.5), 0.95 },
        }
        light(p)
    end,
    kick = function(s, p, dir, size)
        react(p, "flare", dir < 0 and CINDERS_HIT or CINDERS_HEAL, size)
    end,
})
