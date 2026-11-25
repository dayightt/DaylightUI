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
Flares.ARRIVE_FROM = 0.9       -- size it grows from as it fades in
Flares.TEST_SECONDS = 10

local function num(v, d) if type(v) == "number" then return v end return d end
local function get(path) return DUI:Get("Procs", path) end

function Flares.Art(design, core)
    return DUI.MEDIA .. "flare-" .. design .. (core and "-core" or "") .. ".png"
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

-- One painted piece: its frame (placed, and what the loops move), the light
-- and the core over it. Both textures sit on the piece's bottom edge, so the
-- time drain can shorten them from the top.
function Flares.NewPart(f)
    local pf = CreateFrame("Frame", nil, f)
    local part = { frame = pf, tex = layer(pf, 0), core = layer(pf, 1) }
    for _, t in ipairs({ part.tex, part.core }) do
        t:SetPoint("BOTTOMLEFT", pf, "BOTTOMLEFT")
        t:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT")
    end
    local g = pf:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.7)
    a:SetDuration(1.3)
    a:SetSmoothing("IN_OUT")
    part.breathe = g
    g = pf:CreateAnimationGroup()
    g:SetLooping("BOUNCE")
    local s = g:CreateAnimation("Scale")
    s:SetScaleFrom(1, 1)
    s:SetScaleTo(1.08, 1.08)
    s:SetDuration(0.5)
    s:SetSmoothing("IN_OUT")
    part.pulse, part.pulseScale = g, s
    g = pf:CreateAnimationGroup()
    s = g:CreateAnimation("Scale")
    s:SetScaleFrom(1.5, 1.5)
    s:SetScaleTo(1, 1)
    s:SetDuration(0.16)
    s:SetSmoothing("OUT")
    part.impact, part.impactScale = g, s
    return part
end

local function acquire()
    local f = table.remove(pool)
    if f then return f end
    f = CreateFrame("Frame", nil, Flares.holder)
    f:SetAllPoints(Flares.holder)
    f:EnableMouse(false)
    f.parts = { Flares.NewPart(f), Flares.NewPart(f) }
    f.fade, f.flashKey, f.drainKey = {}, {}, {}
    return f
end

local function stopLoops(f)
    for _, part in ipairs(f.parts) do
        part.breathe:Stop()
        part.pulse:Stop()
        part.impact:Stop()
    end
    Motion.Tween(f.flashKey, 0, 0, 0)
    Motion.Tween(f.drainKey, 0, 0, 0)
end

local function release(f)
    stopLoops(f)
    f.arriving = nil
    f:Hide()
    f.key = nil
    pool[#pool + 1] = f
end

-- Placing -----------------------------------------------------------------

-- Where each piece goes and how big. k = the arrival's growth (0.9 to 1).
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
        part.h = h
    end
    if sp.mirrored then
        local edge = (sp.edge + sp.step * f.lane) * scale + x
        local yy = sp.y * scale + y
        local a, b = "RIGHT", "LEFT"
        if sp.anchor == "bottom" then a, b = "BOTTOMRIGHT", "BOTTOMLEFT" end
        left.frame:SetPoint(a, holder, "CENTER", -edge, yy)
        right.frame:SetPoint(b, holder, "CENTER", edge, yy)
        left.origin, right.origin = a, b
        right.frame:Show()
    else
        local yy = (sp.y + (sp.step or 0) * f.lane) * scale + y
        local a = sp.anchor == "bottom" and "BOTTOM" or "CENTER"
        left.frame:SetPoint(a, holder, "CENTER", x, yy)
        left.origin = a
        right.frame:Hide()
    end
    for i, part in ipairs(f.parts) do
        part.pulseScale:SetOrigin(part.origin or "CENTER", 0, 0)
        part.impactScale:SetOrigin(part.origin or "CENTER", 0, 0)
        Flares.Cut(f, part, i)
    end
end

-- The light's visible share from the bottom (1 = whole), and the right piece
-- mirrored.
function Flares.Cut(f, part, i)
    local frac = f.frac or 1
    local l, r = 0, 1
    if i == 2 then l, r = 1, 0 end
    local h = (part.h or 0) * frac
    for _, t in ipairs({ part.tex, part.core }) do
        t:SetTexCoord(l, r, 1 - frac, 1)
        t:SetHeight(math.max(h, 0.01))
    end
end

-- Painting ----------------------------------------------------------------

-- The light tinted bottom to top with the proc's two colors, the core white.
local function lighter(c)
    local k = Flares.CORE_LIFT
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

function Flares.Paint(f)
    local lo, hi = ns.Alerts.Colors(f.key)
    local a = f.dim or 1
    local coreA = Flares.CORE_ALPHA * (f.boost or 1) * a
    if coreA > 1 then coreA = 1 end
    local file, coreFile = Flares.Art(f.design), Flares.Art(f.design, true)
    local clo, chi = lighter(lo), lighter(hi)
    for _, part in ipairs(f.parts) do
        part.tex:SetTexture(file)
        part.core:SetTexture(coreFile)
        part.tex:SetVertexColor(1, 1, 1, 1)
        Style.Gradient(part.tex, "VERTICAL", lo[1], lo[2], lo[3], a, hi[1], hi[2], hi[3], a)
        -- The core is the same pair, a little lighter: a white core over the
        -- whole shape washed every color out to near white.
        part.core:SetVertexColor(1, 1, 1, 1)
        Style.Gradient(part.core, "VERTICAL", clo[1], clo[2], clo[3], coreA, chi[1], chi[2], chi[3], coreA)
    end
end

-- The flare's own opacity: every alert's times this one's.
function Flares.Opacity(key)
    return num(get("alpha"), 1) * num(ns.Alerts.Get(key, "alpha"), 1)
end

-- Motion ------------------------------------------------------------------

local function startLoop(f)
    stopLoops(f)
    if not Motion.On() then return end
    local anim = f.anim
    local shown = ns.Data.SPOTS[f.spot].mirrored and 2 or 1
    if anim == "flash" then
        f.boost = 1 / Flares.CORE_ALPHA
        Motion.Tween(f.flashKey, f.boost, 1, Motion.SLOW, function(v)
            f.boost = v
            Flares.Paint(f)
        end)
    end
    for i = 1, shown do
        local part = f.parts[i]
        if anim == "breathe" or anim == "flash" then
            part.breathe:Play()
        elseif anim == "pulse" then
            part.pulse:Play()
        elseif anim == "impact" then
            part.impact:Play()
        end
    end
end

local function arrive(f)
    local target = Flares.Opacity(f.key)
    f.target = target
    f:Show()
    if not Motion.On() then
        f:SetAlpha(target)
        Flares.Layout(f, 1)
        return
    end
    f.arriving = true
    Motion.Tween(f.fade, 0, 1, Motion.FAST, function(p)
        f:SetAlpha(p * f.target)
        Flares.Layout(f, Flares.ARRIVE_FROM + (1 - Flares.ARRIVE_FROM) * p)
    end, function() f.arriving = nil end)
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

local function cutAll(f)
    for i, part in ipairs(f.parts) do Flares.Cut(f, part, i) end
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
    f.dim, f.boost, f.frac, f.drainA, f.stackDim = stackDim, 1, 1, 1, stackDim
    f.test = info.test
    f.endsAt = info.left and GetTime() + info.left or nil
    Flares.live[key] = f
    Flares.Paint(f)
    Flares.Layout(f, Motion.On() and Flares.ARRIVE_FROM or 1)
    arrive(f)
    startLoop(f)
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
    Motion.Tween(f.fade, f:GetAlpha(), 0, Motion.NORMAL, function(a) f:SetAlpha(a) end, function() release(f) end)
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
        if (not f.info.design and ns.Alerts.Get(f.key, "design") ~= f.design) or ns.Alerts.Get(f.key, "anim") ~= f.anim then
            Flares.Restart(f.key)
        else
            f.target = Flares.Opacity(f.key)
            if not f.arriving then f:SetAlpha(f.target) end
            Flares.Paint(f)
            Flares.Layout(f, 1)
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
