-- The flares: painted light around the character, one per proc that's up.
-- A design's spot decides where it sits; two procs at the same spot take
-- lanes, the second one further out (or up), so they never cover each other.
-- Each flare is its own frame: it fades in and out with Motion, and loops its
-- animation with an animation group, so nothing runs Lua every frame while it
-- just sits there.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local Flares = { live = {} }
ns.Flares = Flares

local pool = {}
-- lanes[spot][lane] = the proc key holding it. The aura flares the game shows
-- reserve theirs too (Game.lua), since Daylight UI can't see when they appear.
local lanes = {}
Flares.lanes = lanes

Flares.CORE_ALPHA = 0.35       -- the hot core, of the flare's opacity
Flares.CORE_LIFT = 0.3         -- how far the core's colors lean toward white
Flares.ARRIVE_FROM = 0.9       -- a Still flare's size as it starts fading in
Flares.TEST_SECONDS = 10

-- The moving sheets, made from the paintings by tools/make_flare_sheets.py.
-- The client steps through them as FlipBooks, so no Lua runs while a flare
-- just sits there. live = the flicker (the core baked in), burn = the way
-- out, gleam = Flash's band, sparks = the strike's spray (a frame stands for
-- twice the piece), embers = a field rising over the piece.
Flares.LIVE = { frames = 32, cols = 8, loop = 2 }
Flares.EMBERS = { frames = 48, cols = 8, loop = 3, lift = 0.3 }
Flares.SPARKS = { frames = 16, cols = 4, time = 0.6, lift = 0.4, size = 2 }
Flares.BURN = { frames = 8, cols = 8 }
Flares.GLEAM = { frames = 8, cols = 8, time = 0.45, every = 1.6 }
-- The way in: revealed from the inner edge out to 1.2 times the width with a
-- white front 0.06 of it wide; sun and feet (no inner edge) grow from 0.7.
Flares.STRIKE = { reach = 1.2, front = 0.06, lift = 0.6, from = 0.7 }
-- Each animation's own motion on top of the flicker.
Flares.BREATHE = { to = 0.55, time = 1.6 }
Flares.BEAT = { every = 1.0, rise = 0.03, fall = 0.17, again = 0.7, fall2 = 0.2 }
Flares.WAVE = { every = 1.4, time = 0.75, to = 1.45, alpha = 0.5, sparksAt = 0.45, sparks = 0.45 }
Flares.WARM = { 1, 0.97, 0.9 }   -- the white sparks and embers lean toward

-- What each animation adds while the flare is up: the flicker's speed, the
-- embers' and the strike sparks' brightness, and its own groups on each piece.
-- One sheet serves every animation, so a calmer one is slower or dimmer, not
-- a different drawing. Still has no row: it shows the still painting.
Flares.KINDS = {
    strike  = { live = 1,   embers = 1,    sparks = 1,   groups = {} },
    breathe = { live = 0.5, embers = 0.35, sparks = 0.5, groups = { "breathe" } },
    pulse   = { live = 1,   embers = 0.5,  sparks = 0.7, groups = { "beat" } },
    impact  = { live = 1,   embers = 0.5,  sparks = 0.7, groups = { "wave" }, again = true },
    flash   = { live = 1,   embers = 0.5,  sparks = 0.7, groups = { "gleam" } },
}

local function num(v, d) if type(v) == "number" then return v end return d end
local function get(path) return DUI:Get("Procs", path) end

function Flares.Art(design, core)
    return DUI.MEDIA .. "flare-" .. design .. (core and "-core" or "") .. ".png"
end

-- A moving sheet's file. A played sheet ignores SetTexCoord, so the right
-- piece has its own mirrored file.
function Flares.Sheet(design, kind, right)
    return DUI.MEDIA .. "flare-" .. design .. "-" .. kind .. (right and "-r" or "") .. ".png"
end

-- Whether a flare draws the moving sheets, or the still painting (Still, or motion off).
function Flares.Moving(f)
    return Motion.On() and Flares.KINDS[f.anim] ~= nil
end

-- Lanes -------------------------------------------------------------------

function Flares.TakeLane(spot, key)
    local t = lanes[spot]
    if not t then t = {}; lanes[spot] = t end
    for i, k in pairs(t) do if k == key then return i end end
    local i = 0
    while t[i] ~= nil do i = i + 1 end
    t[i] = key
    return i
end

function Flares.FreeLane(spot, key)
    local t = lanes[spot]
    if not t then return end
    for i, k in pairs(t) do if k == key then t[i] = nil end end
end

-- Building ----------------------------------------------------------------

local function layer(parent, sub)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetBlendMode("ADD")
    -- Sizes animate below a pixel: no snapping to the grid.
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    return t
end

-- Every timed animation remembers its times at 1x, so the Animation speed
-- setting can scale them (Flares.SetSpeed). The strike's sparks and the burn
-- aren't listed: they keep their time.
local function remember(holder, a, duration, delay, rate)
    holder.times[#holder.times + 1] = { a, duration, delay or 0, 0, rate }
end

local function anim(holder, g, kind, smoothing, duration, order)
    local a = g:CreateAnimation(kind)
    a:SetSmoothing(smoothing)
    a:SetDuration(duration)
    if order then a:SetOrder(order) end
    if holder then remember(holder, a, duration) end
    return a
end

local function fade(holder, g, from, to, duration, order)
    local a = anim(holder, g, "Alpha", "NONE", duration, order)
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    return a
end

local function hold(holder, a, seconds)
    a:SetEndDelay(seconds)
    for _, t in ipairs(holder.times) do
        if t[1] == a then t[4] = seconds end
    end
end

-- rate "live" = the flicker, which a calm animation also slows on its own.
local function flipbook(holder, g, tex, sheet, duration, order, rate)
    local a = g:CreateAnimation("FlipBook")
    a:SetTarget(tex)
    a:SetDuration(duration)
    if order then a:SetOrder(order) end
    a:SetFlipBookRows(sheet.frames / sheet.cols)
    a:SetFlipBookColumns(sheet.cols)
    a:SetFlipBookFrames(sheet.frames)
    a:SetFlipBookFrameWidth(0)
    a:SetFlipBookFrameHeight(0)
    if holder then remember(holder, a, duration, 0, rate) end
    return a
end

-- Plays a holder's (a piece's, or the sparks') timed loops faster (above 1)
-- or slower. Only between plays: a group's length is worked out as it starts.
function Flares.SetSpeed(holder, speed, liveRate)
    speed = num(speed, 1)
    if speed <= 0 then speed = 1 end
    liveRate = num(liveRate, 1)
    if holder.speed == speed and holder.liveRate == liveRate then return end
    holder.speed, holder.liveRate = speed, liveRate
    for _, t in ipairs(holder.times) do
        local k = t[5] == "live" and speed * liveRate or speed
        local a = t[1]
        a:SetDuration(t[2] / k)
        a:SetStartDelay(t[3] / k)
        a:SetEndDelay(t[4] / k)
    end
end

-- A copy of a light layer in a frame of its own, hidden between its loops.
-- Its frame's alpha is what animates: the texture's own alpha is carried in
-- its gradient.
local function copy(pf, sub)
    local cf = CreateFrame("Frame", nil, pf)
    cf:SetAllPoints(pf)
    cf:SetAlpha(0)
    local t = layer(cf, sub)
    t:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT")
    t:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT")
    return cf, t
end

local function clip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetClipsChildren(true)
    return c
end

-- One painted piece. Still: the light and the core on the piece's bottom
-- edge, shortened from the top by the time drain. Moving: the flicker sheet
-- at the piece's full size inside a clipping frame (liveFrame) that the strike
-- widens and the drain shortens, since a played sheet can't be cut by its
-- coordinates. A sheet that isn't playing draws its whole sheet squashed, so
-- every one-shot sheet sits in a frame whose own alpha is 0 and whose group
-- lifts it only while the FlipBook plays.
function Flares.NewPart(f)
    local pf = CreateFrame("Frame", nil, f)
    local part = { frame = pf, tex = layer(pf, 0), core = layer(pf, 1), times = {}, speed = 1, liveRate = 1 }
    for _, t in ipairs({ part.tex, part.core }) do
        t:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT")
        t:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT")
    end
    part.liveFrame = clip(pf)
    part.liveTex = layer(part.liveFrame, 0)
    part.burnTex = layer(part.liveFrame, 0)
    part.burnTex:Hide()
    part.gleamFrame = CreateFrame("Frame", nil, part.liveFrame)
    part.gleamFrame:SetAllPoints(part.liveFrame)
    part.gleamFrame:SetAlpha(0)
    part.gleamTex = layer(part.gleamFrame, 2)
    part.emberFrame = CreateFrame("Frame", nil, pf)
    part.emberFrame:SetAllPoints(pf)
    part.emberTex = layer(part.emberFrame, 3)
    part.emberTex:SetAllPoints(part.emberFrame)
    part.emberTex:Hide()
    -- The strike's white front: the painting lifted toward white, seen through
    -- a thin clip riding the reveal's edge.
    part.frontFrame = clip(pf)
    part.frontTex = layer(part.frontFrame, 4)
    part.frontTex:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT")
    part.frontTex:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT")
    part.frontFrame:Hide()
    -- The core at full strength: the strike's flash and Pulse's beat.
    part.flashFrame, part.flashTex = copy(pf, 5)
    -- Impact's ghost of the painting.
    part.echoFrame, part.echoTex = copy(pf, 2)

    local g = part.liveFrame:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    flipbook(part, g, part.liveTex, Flares.LIVE, Flares.LIVE.loop, nil, "live")
    part.live = g

    g = part.emberFrame:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    flipbook(part, g, part.emberTex, Flares.EMBERS, Flares.EMBERS.loop)
    part.embers = g

    -- The way out, once over Motion.SLOW whatever the speed.
    g = part.liveFrame:CreateAnimationGroup()
    g:SetLooping("NONE")
    flipbook(nil, g, part.burnTex, Flares.BURN, Motion.SLOW)
    g:SetScript("OnFinished", function(self)
        if not self:IsPlaying() then part.burnTex:Hide() end
    end)
    part.burn = g

    -- Breathe: the whole piece dims and comes back.
    local B = Flares.BREATHE
    g = pf:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local a = anim(part, g, "Alpha", "IN_OUT", B.time)
    a:SetFromAlpha(1)
    a:SetToAlpha(B.to)
    part.breathe = g

    -- Pulse: the core beats twice a second, the second softer.
    local P = Flares.BEAT
    g = part.flashFrame:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    fade(part, g, 0, 1, P.rise, 1)
    fade(part, g, 1, 0, P.fall, 2)
    fade(part, g, 0, P.again, P.rise, 3)
    a = fade(part, g, P.again, 0, P.fall2, 4)
    hold(part, a, P.every - P.rise * 2 - P.fall - P.fall2)
    part.beat = g

    -- Impact: a ghost of the painting swells out and fades. It lives in a
    -- frame of its own: nothing scales the piece itself.
    local W = Flares.WAVE
    g = part.echoFrame:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    local s = anim(part, g, "Scale", "OUT", W.time)
    s:SetScaleFrom(1, 1)
    s:SetScaleTo(W.to, W.to)
    hold(part, s, W.every - W.time)
    a = anim(part, g, "Alpha", "OUT", W.time)
    a:SetFromAlpha(W.alpha)
    a:SetToAlpha(0)
    hold(part, a, W.every - W.time)
    part.wave, part.waveScale = g, s

    -- Flash: a gleam runs from the base to the tip. Its frame is lit only
    -- while the sheet plays, then dark for the rest of the beat.
    local G = Flares.GLEAM
    g = part.gleamFrame:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    fade(part, g, 1, 1, G.time, 1)
    flipbook(part, g, part.gleamTex, G, G.time, 1)
    fade(part, g, 0, 0, G.every - G.time, 2)
    part.gleam = g
    return part
end

-- The sparks: two sheets (the right one mirrored) in one frame whose alpha is
-- 0, lit only while their FlipBooks play. group = the strike's, once, at its
-- own time; again = Impact's, partway through each wave.
function Flares.NewBurst(parent)
    local S, W = Flares.SPARKS, Flares.WAVE
    local b = { times = {}, speed = 1, liveRate = 1 }
    b.frame = CreateFrame("Frame", nil, parent)
    b.frame:SetAllPoints(parent)
    b.frame:SetAlpha(0)
    b.left, b.right = layer(b.frame, 6), layer(b.frame, 6)
    local g = b.frame:CreateAnimationGroup()
    g:SetLooping("NONE")
    fade(nil, g, 1, 1, S.time)
    flipbook(nil, g, b.left, S, S.time)
    flipbook(nil, g, b.right, S, S.time)
    b.group = g
    g = b.frame:CreateAnimationGroup()
    g:SetLooping("REPEAT")
    -- Dimmer than the strike's: the sheets carry the strike's brightness.
    local k = W.sparks / Flares.KINDS.impact.sparks
    fade(b, g, 0, 0, W.sparksAt, 1)
    fade(b, g, k, k, S.time, 2)
    flipbook(b, g, b.left, S, S.time, 2)
    flipbook(b, g, b.right, S, S.time, 2)
    fade(b, g, 0, 0, W.every - W.sparksAt - S.time, 3)
    b.again = g
    return b
end

-- Whether a proc's flare sheds embers (its own Embers switch).
function Flares.Embers(key)
    return ns.Alerts.Get(key, "embers") ~= false
end

-- Every loop a piece can play.
function Flares.AllLoops(part)
    return { part.live, part.embers, part.breathe, part.beat, part.wave, part.gleam }
end

-- The groups an animation plays on one piece: the flicker, the embers and its
-- own. none for Still.
function Flares.LoopsOf(part, anim)
    local kind = Flares.KINDS[anim]
    if not kind then return {} end
    local out = { part.live, part.embers }
    for _, name in ipairs(kind.groups) do out[#out + 1] = part[name] end
    return out
end

-- Plays a flare's loops on its shown pieces and stops every other. One already
-- playing keeps going, so a redraw (the options' preview) doesn't stutter.
-- During the strike only the flicker plays: the embers and the animation's own
-- motion start once the flare is out (f.reveal = 1).
function Flares.PlayLoops(f, anim)
    local kind = Motion.On() and Flares.KINDS[anim] or nil
    local speed = num(ns.Alerts.Get(f.key, "speed"), 1)
    local out = (f.reveal or 1) >= 1
    local embers = Flares.Embers(f.key)
    for _, part in ipairs(f.parts) do
        local rate = kind and kind.live or 1
        if part.speed ~= speed or part.liveRate ~= rate then
            for _, g in ipairs(Flares.AllLoops(part)) do g:Stop() end
            Flares.SetSpeed(part, speed, rate)
        end
        local want = {}
        if kind and part.frame:IsShown() then
            want[part.live] = true
            if out then
                want[part.embers] = embers or nil
                for _, name in ipairs(kind.groups) do want[part[name]] = true end
            end
        end
        part.liveTex:SetShown(want[part.live] == true)
        part.emberTex:SetShown(want[part.embers] == true)
        for _, g in ipairs(Flares.AllLoops(part)) do
            if not want[g] then g:Stop() end
        end
        for g in pairs(want) do
            if not g:IsPlaying() then g:Play() end
        end
    end
    local b = f.burst
    if b then
        if b.speed ~= speed then
            b.again:Stop()
            Flares.SetSpeed(b, speed)
        end
        if kind and kind.again and out then
            if not b.again:IsPlaying() then b.again:Play() end
        else
            b.again:Stop()
        end
    end
end

local function acquire()
    local f = table.remove(pool)
    if f then return f end
    f = CreateFrame("Frame", nil, Flares.holder)
    f:SetAllPoints(Flares.holder)
    f:EnableMouse(false)
    f.parts = { Flares.NewPart(f), Flares.NewPart(f) }
    f.burst = Flares.NewBurst(f)
    f.fade, f.drainKey = {}, {}
    f.reveal = 1
    -- The client stops a frame's animations while it's hidden (the UI hidden,
    -- a loading screen), and a sheet that isn't playing draws its whole sheet
    -- squashed: a flare that's up starts its loops again, one burning away
    -- goes straight back to the pool.
    f:SetScript("OnShow", function(self)
        if self.key and Flares.live[self.key] == self and self.moving then Flares.PlayLoops(self, self.anim) end
    end)
    f:SetScript("OnHide", function(self)
        if self.burning then
            Motion.Tween(self.fade, 0, 0, 0)
            Flares.Release(self)
        end
    end)
    return f
end

local function stopGroups(f)
    for _, part in ipairs(f.parts) do
        for _, g in ipairs(Flares.AllLoops(part)) do g:Stop() end
        part.burn:Stop()
    end
    if f.burst then
        f.burst.group:Stop()
        f.burst.again:Stop()
    end
end

local function stopLoops(f)
    stopGroups(f)
    Motion.Tween(f.drainKey, 0, 0, 0)
end

-- Back to the pool with nothing of the strike or the burn left on it.
local function release(f)
    stopLoops(f)
    f.arriving, f.burning, f.reveal = nil, nil, 1
    for _, part in ipairs(f.parts) do
        part.liveTex:Hide()
        part.burnTex:Hide()
        part.emberTex:Hide()
        part.frontFrame:Hide()
        part.flashFrame:SetAlpha(0)
        part.liveFrame:SetAlpha(1)
    end
    f:Hide()
    f.key = nil
    pool[#pool + 1] = f
end
Flares.Release = release

-- Placing -----------------------------------------------------------------

-- Where each piece goes and how big. k = the arrival's growth (a Still flare
-- from 0.9, a moving sun or feet flare from 0.7).
-- f.rel = the frame whose middle is the character (the holder, or a game-shown
-- flare's own button).
function Flares.Layout(f, k)
    local sp = ns.Data.SPOTS[f.spot]
    local key, holder = f.key, f.rel or Flares.holder
    local scale = num(get("scale"), 1)
    local size = num(ns.Alerts.Get(key, "size"), 1) * (k or 1)
    local x, y = num(ns.Alerts.Get(key, "x"), 0), num(ns.Alerts.Get(key, "y"), 0)
    local w, h = sp.w * scale * size, sp.h * scale * size
    if sp.grow then
        local g = sp.grow ^ f.lane
        w, h = w * g, h * g
    end
    local left, right = f.parts[1], f.parts[2]
    for _, part in ipairs(f.parts) do
        part.frame:ClearAllPoints()
        part.frame:SetSize(w, h)
        part.w, part.h = w, h
    end
    if sp.mirrored then
        local edge = (sp.edge + sp.step * f.lane) * scale + x
        local yy = sp.y * scale + y
        local a, b = "RIGHT", "LEFT"
        if sp.anchor == "bottom" then a, b = "BOTTOMRIGHT", "BOTTOMLEFT" end
        left.frame:SetPoint(a, holder, "CENTER", -edge, yy)
        right.frame:SetPoint(b, holder, "CENTER", edge, yy)
        left.origin, right.origin = a, b
        -- The moving light grows from the inner edge.
        left.corner, right.corner = "BOTTOMRIGHT", "BOTTOMLEFT"
        right.frame:Show()
    else
        local yy = (sp.y + (sp.step or 0) * f.lane) * scale + y
        local a = sp.anchor == "bottom" and "BOTTOM" or "CENTER"
        left.frame:SetPoint(a, holder, "CENTER", x, yy)
        -- The hidden right piece is still laid out below, so it needs spots too.
        left.origin, left.corner = a, "BOTTOM"
        right.origin, right.corner = a, "BOTTOM"
        right.frame:Hide()
    end
    for i, part in ipairs(f.parts) do
        part.waveScale:SetOrigin(part.origin or "CENTER", 0, 0)
        for _, t in ipairs({ part.liveTex, part.burnTex, part.gleamTex }) do
            t:ClearAllPoints()
            t:SetPoint(part.corner, part.liveFrame, part.corner)
            t:SetSize(w, h)
        end
        Flares.Cut(f, part, i)
    end
    Flares.PlaceBurst(f)
end

-- The sparks spray from the inner edge's middle (a comet's from its bottom
-- corner, where its light meets the edge), or both ways from a one-piece
-- design's middle. A spark sheet is twice the piece.
function Flares.PlaceBurst(f)
    local b = f.burst
    if not b then return end
    local sp = ns.Data.SPOTS[f.spot]
    local l, r = f.parts[1], f.parts[2]
    local k = Flares.SPARKS.size
    for _, t in ipairs({ b.left, b.right }) do
        t:ClearAllPoints()
        t:SetSize((l.w or 0) * k, (l.h or 0) * k)
    end
    if sp.mirrored then
        b.left:SetPoint("RIGHT", l.frame, l.origin)
        b.right:SetPoint("LEFT", r.frame, r.origin)
    else
        b.left:SetPoint("RIGHT", l.frame, "CENTER")
        b.right:SetPoint("LEFT", l.frame, "CENTER")
    end
end

-- The piece's visible share. Still: from the bottom by coordinates (1 =
-- whole), the right piece mirrored. Moving: the clip, as wide as the strike
-- has reached and as tall as the drain leaves.
function Flares.Cut(f, part, i)
    local frac = f.frac or 1
    local l, r = 0, 1
    if i == 2 then l, r = 1, 0 end
    local w, h = part.w or 0, part.h or 0
    for _, t in ipairs({ part.tex, part.core, part.echoTex, part.flashTex, part.frontTex }) do
        t:SetTexCoord(l, r, 1 - frac, 1)
        t:SetHeight(math.max(h * frac, 0.01))
    end
    local sp = ns.Data.SPOTS[f.spot]
    local St = Flares.STRIKE
    local reveal = f.reveal or 1
    local reach = reveal * St.reach
    local cw, ch = w, h * frac
    local edge = sp.mirrored or sp.anchor == "bottom"
    if sp.mirrored then
        cw = w * reach
    elseif sp.anchor == "bottom" then
        ch = h * math.min(reach, frac)
    end
    local lf = part.liveFrame
    lf:ClearAllPoints()
    lf:SetPoint(part.corner or "BOTTOM", part.frame, part.corner or "BOTTOM")
    lf:SetSize(math.max(cw, 0.01), math.max(ch, 0.01))
    local front = part.frontFrame
    if reveal < 1 and edge then
        front:ClearAllPoints()
        if sp.mirrored then
            local fw = w * St.front
            local off = math.max(cw - fw, 0)
            front:SetSize(fw, math.max(ch, 0.01))
            front:SetPoint(part.corner, part.frame, part.corner, i == 1 and -off or off, 0)
        else
            local fh = h * St.front
            front:SetSize(w, fh)
            front:SetPoint("BOTTOM", part.frame, "BOTTOM", 0, math.max(ch - fh, 0))
        end
        front:SetAlpha(1 - reveal)
        front:Show()
    else
        front:Hide()
    end
end

-- Painting ----------------------------------------------------------------

local function toward(c, to, k)
    return { c[1] + (to[1] - c[1]) * k, c[2] + (to[2] - c[2]) * k, c[3] + (to[3] - c[3]) * k }
end
local WHITE = { 1, 1, 1 }

-- A file is set only when it changes: the drain repaints every frame.
local function setFile(t, file)
    if t.duiFile == file then return end
    t.duiFile = file
    t:SetTexture(file, "CLAMP", "CLAMP")
end

-- The light tinted bottom to top with a pair.
local function tint(t, file, lo, hi, a)
    setFile(t, file)
    t:SetVertexColor(1, 1, 1, 1)
    Style.Gradient(t, "VERTICAL", lo[1], lo[2], lo[3], a, hi[1], hi[2], hi[3], a)
end

local function warm(t, file, c, k, a)
    setFile(t, file)
    local w = toward(c, Flares.WARM, k)
    t:SetVertexColor(w[1], w[2], w[3], a)
end

function Flares.Paint(f)
    local lo, hi = ns.Alerts.Colors(f.key)
    local a = f.dim or 1
    local file, coreFile = Flares.Art(f.design), Flares.Art(f.design, true)
    -- The core is the same pair, a little lighter: a white core over the
    -- whole shape washed every color out to near white.
    local clo, chi = toward(lo, WHITE, Flares.CORE_LIFT), toward(hi, WHITE, Flares.CORE_LIFT)
    local moving = Flares.Moving(f)
    local kind = Flares.KINDS[f.anim]
    for i, part in ipairs(f.parts) do
        local right = i == 2
        tint(part.tex, file, lo, hi, a)
        tint(part.core, coreFile, clo, chi, Flares.CORE_ALPHA * a)
        part.tex:SetShown(not moving)
        part.core:SetShown(not moving)
        tint(part.echoTex, file, lo, hi, a)
        tint(part.flashTex, coreFile, clo, chi, a)
        if moving then
            -- GUESS: Style.Gradient carries over to a texture a FlipBook plays.
            tint(part.liveTex, Flares.Sheet(f.design, "live", right), lo, hi, a)
            tint(part.burnTex, Flares.Sheet(f.design, "burn", right), lo, hi, a)
            local St = Flares.STRIKE
            tint(part.frontTex, file, toward(lo, WHITE, St.lift), toward(hi, WHITE, St.lift), a)
            if f.anim == "flash" then
                tint(part.gleamTex, Flares.Sheet(f.design, "gleam", right), clo, chi, a)
            else
                setFile(part.gleamTex, nil)
            end
            warm(part.emberTex, DUI.MEDIA .. "flare-embers.png", hi, Flares.EMBERS.lift, kind.embers * a)
        else
            for _, t in ipairs({ part.liveTex, part.burnTex, part.gleamTex, part.emberTex }) do
                setFile(t, nil)
                t:Hide()
            end
        end
    end
    local b = f.burst
    if b then
        if moving then
            local S = Flares.SPARKS
            warm(b.left, DUI.MEDIA .. "flare-sparks.png", hi, S.lift, kind.sparks * a)
            warm(b.right, DUI.MEDIA .. "flare-sparks-r.png", hi, S.lift, kind.sparks * a)
        else
            setFile(b.left, nil)
            setFile(b.right, nil)
        end
    end
end

-- The flare's own opacity: every alert's times this one's.
function Flares.Opacity(key)
    return num(get("alpha"), 1) * num(ns.Alerts.Get(key, "alpha"), 1)
end

-- Motion ------------------------------------------------------------------

local function startLoop(f)
    stopGroups(f)
    if not Motion.On() then return end
    Flares.PlayLoops(f, f.anim)
end

local function cutAll(f)
    for i, part in ipairs(f.parts) do Flares.Cut(f, part, i) end
end

-- A Still flare fades in, growing a little.
local function fadeIn(f)
    if not Motion.On() then
        f:SetAlpha(f.target)
        Flares.Layout(f, 1)
        return
    end
    f.arriving = true
    Motion.Tween(f.fade, 0, 1, Motion.FAST, function(p)
        f:SetAlpha(p * f.target)
        Flares.Layout(f, Flares.ARRIVE_FROM + (1 - Flares.ARRIVE_FROM) * p)
    end, function() f.arriving = nil end)
end

-- A moving flare strikes: full brightness at once, revealed from the inner
-- edge outward over Motion.NORMAL behind its white front, sparks flying, its
-- core flashing and settling over Motion.SLOW. One tween does it all: the
-- reveal works its own time back out of the tween's eased step.
local function strike(f)
    local sp = ns.Data.SPOTS[f.spot]
    local grows = not sp.mirrored and sp.anchor ~= "bottom"
    local St = Flares.STRIKE
    f.reveal, f.arriving = 0, true
    for _, part in ipairs(f.parts) do part.flashFrame:SetAlpha(1) end
    f.burst.group:Stop()
    f.burst.group:Play()
    local N, S = Motion.NORMAL, Motion.SLOW
    Motion.Tween(f.fade, 0, 1, S, function(v)
        if f.reveal < 1 then
            local p = math.min((1 - (1 - v) ^ (1 / 3)) * S / N, 1)
            f.reveal = 1 - (1 - p) ^ 3
            if grows then
                Flares.Layout(f, St.from + (1 - St.from) * f.reveal)
                for _, part in ipairs(f.parts) do part.liveFrame:SetAlpha(f.reveal) end
            else
                cutAll(f)
            end
            if f.reveal >= 1 then Flares.PlayLoops(f, f.anim) end
        end
        for _, part in ipairs(f.parts) do part.flashFrame:SetAlpha(1 - v) end
    end, function() f.arriving = nil end)
end

local function arrive(f)
    f.target = Flares.Opacity(f.key)
    f:Show()
    if f.moving then
        f:SetAlpha(f.target)
        strike(f)
    else
        fadeIn(f)
    end
end

-- Time drain and stacks -----------------------------------------------------

-- Spots that drain by fading, not shortening: a ring at the feet and a comet
-- would only lose their top.
local FADES = { feet = true, across = true }
Flares.DRAIN_FLOOR = 0.35

-- How bright a stacking proc is: dim until its last stack. nil = below Show from.
function Flares.StackDim(key, stacks)
    local p = ns.Data.BY[key]
    if not (p and p.stacks and type(stacks) == "number") then return 1 end
    if stacks < (ns.Alerts.Get(key, "fromStacks") or p.stacks) then return nil end
    return 0.45 + 0.55 * math.min(stacks, p.stacks) / p.stacks
end

local function shade(f)
    f.dim = (f.stackDim or 1) * (f.drainA or 1)
    Flares.Paint(f)
end

-- One tween over the time left, restarted when the proc renews. Its curve
-- eases out, so the step works the even time back out of it.
local function drain(f)
    local info = f.info
    local left, dur = info.left, info.dur
    f.frac, f.drainA, f.drainEnd = 1, 1, nil
    if not (left and dur and dur > 0) or ns.Alerts.Get(f.key, "drain") == false or not Motion.On() then
        Motion.Tween(f.drainKey, 0, 0, 0)
        cutAll(f)
        shade(f)
        return
    end
    left = math.max(0, math.min(left, dur))
    f.drainEnd = GetTime() + left
    local fades = FADES[f.spot]
    Motion.Tween(f.drainKey, 0, 1, math.max(left, 0.01), function(v)
        local t = 1 - (1 - v) ^ (1 / 3)
        local frac = (left - left * t) / dur
        if fades then
            f.drainA = Flares.DRAIN_FLOOR + (1 - Flares.DRAIN_FLOOR) * frac
            shade(f)
        else
            f.frac = frac
            cutAll(f)
        end
    end)
end

-- Showing and hiding --------------------------------------------------------

-- Other addons hear a real proc come, renew and go (ProcShown, ProcRenewed,
-- ProcHidden). Test flares and a look change that redraws one stay quiet.
local quiet = false
local function tell(event, f, stacks)
    if quiet or f.test then return end
    local R = DUI.APIReport
    if R and R.Event then R.Event(event, f.key, stacks) end
end

function Flares.Shown(key)
    return Flares.live[key] ~= nil
end

-- Shows a proc's flare, or updates it when it's already up. info: left and
-- dur (seconds) for the time drain, stacks. Returns the flare's frame.
function Flares.Show(key, info)
    if not Flares.holder or get("enabled") == false then return end
    info = info or {}
    local stackDim = Flares.StackDim(key, info.stacks)
    local f = Flares.live[key]
    if not stackDim then
        if f then Flares.Hide(key) end
        return
    end
    if f then
        local renewed = info.left and (not f.drainEnd or math.abs(GetTime() + info.left - f.drainEnd) > 0.25)
        local restacked = info.stacks ~= f.info.stacks
        f.info = info
        f.endsAt = info.left and GetTime() + info.left or nil
        if f.stackDim ~= stackDim then f.stackDim = stackDim; shade(f) end
        if renewed or (not info.left and f.drainEnd) then drain(f) end
        if renewed or restacked then tell("ProcRenewed", f, info.stacks) end
        return f
    end
    local design = info.design or ns.Alerts.Get(key, "design")
    local d = ns.Data.DESIGNS[design]
    if not d then return end
    f = acquire()
    f.key, f.design, f.spot, f.anim, f.info = key, design, d.spot, ns.Alerts.Get(key, "anim"), info
    f.lane = Flares.TakeLane(d.spot, key)
    f.dim, f.frac, f.drainA, f.stackDim = stackDim, 1, 1, stackDim
    f.test = info.test
    f.endsAt = info.left and GetTime() + info.left or nil
    Flares.live[key] = f
    f.moving = Flares.Moving(f)
    f.reveal = f.moving and 0 or 1
    Flares.Paint(f)
    Flares.Layout(f, (Motion.On() and not f.moving) and Flares.ARRIVE_FROM or 1)
    startLoop(f)
    arrive(f)
    drain(f)
    -- Once as it lands. A test flare stays quiet (test mode shows many at
    -- once); the Show button plays it itself.
    if not info.test then Flares.PlaySound(key) end
    tell("ProcShown", f, info.stacks)
    return f
end

function Flares.Hide(key, now)
    local f = Flares.live[key]
    if not f then return end
    Flares.live[key] = nil
    Flares.FreeLane(f.spot, key)
    stopLoops(f)
    tell("ProcHidden", f)
    if now or not Motion.On() then
        Motion.Tween(f.fade, 0, 0, 0)
        release(f)
        return
    end
    if not f.moving then
        Motion.Tween(f.fade, f:GetAlpha(), 0, Motion.NORMAL, function(a) f:SetAlpha(a) end, function() release(f) end)
        return
    end
    -- A moving flare burns away upward on its own sheet over Motion.SLOW,
    -- wherever the strike had got to; its embers keep rising.
    f.arriving, f.burning = nil, true
    for _, part in ipairs(f.parts) do
        part.frontFrame:Hide()
        part.flashFrame:SetAlpha(0)
        part.liveTex:Hide()
        if part.frame:IsShown() then
            part.burnTex:Show()
            part.burn:Play()
            if Flares.Embers(f.key) then
                part.emberTex:Show()
                part.embers:Play()
            end
        end
    end
    Motion.Tween(f.fade, 0, 1, Motion.SLOW, nil, function() release(f) end)
end

function Flares.HideAll(now)
    local keys = {}
    for key in pairs(Flares.live) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do Flares.Hide(key, now) end
end

-- A proc's look changed while it's up: show it again from the start, with
-- its new design, lane and animation.
function Flares.Restart(key)
    local f = Flares.live[key]
    if not f then return end
    local info, test = f.info, f.test
    quiet = true
    Flares.Hide(key, true)
    local _, g = DUI.SafeReturn(Flares.Show, key, info)
    quiet = false
    -- The engine's update may have replaced a test flare's info: it stays a test.
    if g then g.test = test end
end

-- Every flare painted and placed again (accent, size, a setting changed).
function Flares.Repaint()
    for _, f in pairs(Flares.live) do
        if (not f.info.design and ns.Alerts.Get(f.key, "design") ~= f.design) or ns.Alerts.Get(f.key, "anim") ~= f.anim
            or Flares.Moving(f) ~= f.moving then
            Flares.Restart(f.key)
        else
            f.target = Flares.Opacity(f.key)
            if not f.arriving then f:SetAlpha(f.target) end
            Flares.Paint(f)
            Flares.Layout(f, 1)
            -- A new speed restarts only the loop, so a slider drag doesn't
            -- fade the flare out and in again.
            if Motion.On() then Flares.PlayLoops(f, f.anim) end
        end
    end
end

-- The options' "Show it now" and test mode: a proc's flare for ten seconds
-- (seconds = false: until test mode ends). design shows another design on it
-- for a moment (the Design list's hover).
local testAsk = 0
-- A proc's own sound, unless it's None or alert sounds are off.
function Flares.PlaySound(key)
    if get("soundOn") == false then return end
    local sound = ns.Alerts.Get(key, "sound")
    if sound and sound ~= "none" then DUI.Sound.Alert(sound) end
end

function Flares.Test(key, seconds, design)
    if not key then return end
    testAsk = testAsk + 1
    local ask = testAsk
    Flares.Hide(key, true)
    local t = seconds
    if t == nil then t = Flares.TEST_SECONDS end
    if t == false then t = nil end
    Flares.Show(key, { left = t, dur = t, test = ask, design = design })
    if seconds ~= false then
        C_Timer.After(seconds or Flares.TEST_SECONDS, function()
            local f = Flares.live[key]
            if f and f.test == ask then Flares.Hide(key) end
        end)
    end
end

-- Hides the test flares (test mode ended), leaving real ones.
function Flares.EndTests()
    local keys = {}
    for key, f in pairs(Flares.live) do if f.test then keys[#keys + 1] = key end end
    for _, key in ipairs(keys) do Flares.Hide(key) end
end

-- The holder every flare hangs in: the size of the area round the
-- character, moved and sized from unlock mode.
function Flares.Build(mod)
    if Flares.holder then return Flares.holder end
    local h = CreateFrame("Frame", "DaylightUIProcs", UIParent)
    h:SetSize(640, 640)
    h:SetPoint("CENTER")
    h:SetFrameStrata("MEDIUM")
    h:EnableMouse(false)
    Flares.holder = h
    DUI.Movers.Register(h, "procs.anchor", L["Proc alerts"], { "CENTER", nil, "CENTER", 0, 0 }, {
        active = function() return get("enabled") ~= false end, minW = 320, minH = 320,
    })
    return h
end

-- Test mode: the proc the Alerts page edits, up until test mode ends.
local function syncTest()
    if not Flares.holder then return end
    if DUI.testMode and DUI.TestPartShown("procs") then
        local key = ns.Options and ns.Options.Selected()
        if key and not Flares.live[key] then Flares.Test(key, false) end
    else
        Flares.EndTests()
    end
end
DUI.On("TestModeChanged", syncTest)
DUI.On("TestPartChanged", function(key) if key == "procs" then syncTest() end end)
DUI.RegisterTestPart("procs", "Proc alerts", 87, function()
    return Flares.holder ~= nil and get("enabled") ~= false
end)
