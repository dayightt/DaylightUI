-- Shared animation helpers. Three speeds, ease-out, and one switch
-- (general.motion): when it's off every helper jumps straight to its end
-- state. Only our own regions are animated.

local _, DUI = ...

local Motion = {}
DUI.Motion = Motion

Motion.FAST, Motion.NORMAL, Motion.SLOW = 0.12, 0.2, 0.4
Motion.CLOSE = 0.3 -- fading out only
Motion.GHOST_EDGE = 0.1 -- a ghost's border is heavier than its background, so it fades first

function Motion.On()
    local g = DUI.DB and DUI.DB.General and DUI.DB.General()
    return not (g and g.motion == false)
end

-- Each region keeps its own animation groups, created once and reused.
local function group(region, key)
    region.__duiMotion = region.__duiMotion or {}
    local g = region.__duiMotion[key]
    if g then g:Stop() else
        g = region:CreateAnimationGroup()
        region.__duiMotion[key] = g
    end
    return g
end

local function alphaAnim(g, from, to, dur, delay)
    g:SetToFinalAlpha(true)
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(dur)
    if delay then a:SetStartDelay(delay) end
    a:SetSmoothing("OUT")
end

-- An alpha fade that holds its end value. One group per region, reused (a new
-- one per call piled up on lines that fade often). A fade still playing stops.
function Motion.Fade(region, from, to, dur, delay)
    if not Motion.On() then region:SetAlpha(to); return end
    local g = group(region, "fade")
    local a = g.__alpha
    if not a then
        g:SetToFinalAlpha(true)
        a = g:CreateAnimation("Alpha")
        a:SetSmoothing("OUT")
        g.__alpha = a
    end
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(dur or Motion.NORMAL)
    a:SetStartDelay(delay or 0)
    region:SetAlpha(to)
    g:Play()
    return g
end

-- Scale from `from` up to 1 while fading in.
function Motion.Pop(region, from, dur)
    region:SetAlpha(1)
    if not Motion.On() then return end
    dur = dur or Motion.NORMAL
    local g = region.__duiPop
    if g then g:Stop() else
        g = region:CreateAnimationGroup()
        local s = g:CreateAnimation("Scale")
        s:SetScaleFrom(from or 0.6, from or 0.6)
        s:SetScaleTo(1, 1)
        s:SetDuration(dur)
        s:SetSmoothing("OUT")
        alphaAnim(g, 0, 1, dur)
        region.__duiPop = g
    end
    g:Play()
end

-- Scale from `from` back to 1 without touching alpha: a nudge on something
-- already shown.
function Motion.Bump(region, from, dur)
    if not Motion.On() then return end
    local g = region.__duiBump
    if g then g:Stop() else
        g = region:CreateAnimationGroup()
        local s = g:CreateAnimation("Scale")
        s:SetScaleFrom(from or 1.15, from or 1.15)
        s:SetScaleTo(1, 1)
        s:SetDuration(dur or Motion.FAST)
        s:SetSmoothing("OUT")
        region.__duiBump = g
    end
    g:Play()
end

-- Full alpha fading to nothing.
function Motion.Flash(texture, dur)
    if not Motion.On() then texture:Hide(); return end
    local g = texture.__duiFlash
    if g then g:Stop() else
        g = texture:CreateAnimationGroup()
        alphaAnim(g, 1, 0, dur or Motion.NORMAL)
        g:SetScript("OnFinished", function() texture:Hide() end)
        texture.__duiFlash = g
    end
    texture:SetAlpha(1)
    texture:Show()
    g:Play()
end

-- Fade in plus a lift of `rise` px (visual only, the frame never moves). Only
-- lift small windows: the client re-places every child on each frame of the
-- lift, so a window full of buttons (bags with 100+ slots) dropped about 10
-- fps. The bags only fade.
function Motion.Appear(frame, rise)
    frame:SetAlpha(1)
    if not Motion.On() then return end
    local fade = group(frame, "appearFade")
    if not fade.__built then
        alphaAnim(fade, 0, 1, Motion.NORMAL)
        fade.__built = true
    end
    fade:Play()
    if rise and rise ~= 0 then
        local lift = group(frame, "appearLift")
        if not lift.__built then
            local t = lift:CreateAnimation("Translation")
            t:SetOffset(0, -rise)
            t:SetDuration(Motion.NORMAL)
            t:SetSmoothing("OUT")
            lift.__built = true
        end
        lift:Play(true) -- reversed: from `rise` px low up to rest
    end
end

-- Closing: fade out over CLOSE, then Hide. A window counts as closed from the
-- start of the fade (Motion.Shown), and showing it again mid-fade (via
-- Motion.Window's hooks) cancels the fade at full alpha.
function Motion.Vanish(frame)
    if not frame:IsShown() or frame.__duiVanishing then return end
    if DUI.Sound then DUI.Sound.Play("close") end
    if not Motion.On() then frame:Hide(); return end
    frame.__duiVanishing = true
    -- Escape is free again the moment the window starts to close.
    if frame.__duiEsc then frame.__duiEsc:Hide() end
    local m = frame.__duiMotion
    if m and m.appearFade then m.appearFade:Stop() end
    if m and m.appearLift then m.appearLift:Stop() end
    local g = group(frame, "vanish")
    if not g.__built then
        alphaAnim(g, 1, 0, Motion.CLOSE)
        g:SetScript("OnFinished", function()
            if not frame.__duiVanishing then return end
            frame.__duiVanishing = nil
            frame:Hide()
            frame:SetAlpha(1)
        end)
        g.__built = true
    end
    g:Play()
end

-- Shown and not on its way out. Toggles should ask this.
function Motion.Shown(frame)
    return frame:IsShown() and not frame.__duiVanishing
end

local function cancel(frame)
    if not frame.__duiVanishing then return end
    frame.__duiVanishing = nil
    local g = frame.__duiMotion and frame.__duiMotion.vanish
    if g then g:Stop() end
    frame:SetAlpha(1)
    if frame.__duiEsc then frame.__duiEsc:Show() end
end

-- Wires one of our windows once: it Appears on show (with a `rise` px lift,
-- or fade only), and Escape fades it out. Escape goes through a tiny hidden
-- stand-in frame in UISpecialFrames, shown while the window is. The game
-- hides the stand-in and its OnHide fades the window. With ownEscape the
-- window handles Escape itself (the setup guide), so there's no stand-in.
local escapes = 0
function Motion.Window(frame, rise, ownEscape)
    if frame.__duiWired then return end
    frame.__duiWired = true
    local esc
    if not ownEscape then
        escapes = escapes + 1
        local name = "DaylightUIEscape" .. escapes
        esc = CreateFrame("Frame", name, UIParent)
        esc:SetSize(1, 1)
        esc:EnableMouse(false)
        esc:Hide()
        -- Hidden along with its parent (Alt+Z hides the whole UI) isn't Escape.
        esc:SetScript("OnHide", function(self)
            if not self:IsShown() then Motion.Vanish(frame) end
        end)
        frame.__duiEsc = esc
        tinsert(UISpecialFrames, name)
        if frame:IsShown() then esc:Show() end
    end
    if DUI.Pad then DUI.Pad.Follow(frame, function() Motion.Vanish(frame) end) end
    frame:HookScript("OnShow", function(self)
        if esc then esc:Show() end
        if DUI.Sound then DUI.Sound.Play("open") end
        Motion.Appear(self, rise)
    end)
    frame:HookScript("OnHide", function(self)
        local g = self.__duiMotion and self.__duiMotion.vanish
        if self.__duiVanishing then
            self.__duiVanishing = nil
            if g then g:Stop() end
            self:SetAlpha(1)
        end
        if esc then esc:Hide() end
    end)
    -- Shown again while still fading out fires no OnShow, so hook Show.
    hooksecurefunc(frame, "Show", cancel)
    hooksecurefunc(frame, "SetShown", function(self, on) if on then cancel(self) end end)
end

-- The game's own windows: fade in only, out of combat, never touching their
-- Hide. Their alpha is stepped each frame from clear up to its previous value
-- (the way the game fades its own map as you move), never with an alpha
-- animation. An animation on a game window loses whatever the window does to
-- its own parts while it plays (the world map's picture, shown once loaded,
-- stayed hidden; the game menu's button art, hidden as buttons were created,
-- came back). If anything else sets the window's alpha meanwhile (the map
-- fading itself) it wins and the fade stops. Closed mid-fade, the alpha is
-- restored.
local fading = setmetatable({}, { __mode = "k" }) -- window -> its fade
-- Game windows that already have the OnHide hook (tracked here, not on the frame).
local fadeWired = setmetatable({}, { __mode = "k" })

-- GetAlpha can return a value slightly off what was set.
local ALPHA_SLACK = 0.02

local function endFade(frame)
    local s = fading[frame]
    if not s then return end
    fading[frame] = nil
    s.over = true
    if math.abs(frame:GetAlpha() - s.last) <= ALPHA_SLACK then frame:SetAlpha(s.target) end
end

-- No fade for a secret alpha.
function Motion.FadeIn(frame)
    if not Motion.On() or (InCombatLockdown and InCombatLockdown()) then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local old = fading[frame]
    local target = old and old.target or frame:GetAlpha()
    if issecretvalue and issecretvalue(target) then return end
    if old then old.over = true end
    if not fadeWired[frame] then
        fadeWired[frame] = true
        frame:HookScript("OnHide", endFade)
    end
    local s = { target = target, last = frame:GetAlpha() }
    fading[frame] = s
    Motion.Tween(s, 0, target, Motion.NORMAL, function(a)
        if s.over then return end
        if math.abs(frame:GetAlpha() - s.last) > ALPHA_SLACK then
            s.over = true -- someone else owns it now
            fading[frame] = nil
            return
        end
        -- Combat started mid-fade. Nothing of the game's fades in combat, so jump to
        -- its own alpha.
        if InCombatLockdown and InCombatLockdown() then
            endFade(frame)
            return
        end
        s.last = a
        frame:SetAlpha(a)
    end, function()
        if fading[frame] == s then fading[frame] = nil end
    end)
end

function Motion.FadingIn(frame)
    return fading[frame] ~= nil
end

-- Game windows can't be held open to fade out (their Hide is the game's), so
-- a ghost does it: an empty copy of the window's frame, in the same spot,
-- fading out over CLOSE. Nothing of the game's is touched, only read.
-- dress(ghost) styles a new ghost once (the skin's window look). Call from
-- the window's OnHide.
local ghosts = {}
function Motion.Ghost(frame, dress)
    if not Motion.On() then return end
    -- Still shown, so only the UI around it was hidden (Alt+Z), not closed.
    if frame:IsShown() or not UIParent:IsVisible() then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    -- Already faded out by the game itself (the loot window). A ghost would
    -- briefly bring it back at full alpha.
    if frame:GetAlpha() <= ALPHA_SLACK then return end
    -- Never visible at all (under a transparent parent, like the window kit's veil).
    if frame.GetEffectiveAlpha and frame:GetEffectiveAlpha() <= ALPHA_SLACK then return end
    local l, b, w, h = frame:GetRect()
    if not (l and b and w and h) or w <= 0 or h <= 0 then return end
    local g = ghosts[frame]
    if not g then
        g = CreateFrame("Frame", nil, UIParent)
        g:EnableMouse(false)
        g:Hide()
        -- dress returns the border, one of the ghost's frames, which fades over
        -- GHOST_EDGE (at the same alpha a heavy border lingers after the background).
        -- Fade a frame, never individual textures: a texture's own alpha fade lost
        -- its tint in game (a gradient border flashed white).
        local ok, edge = false, nil
        if dress then
            ok = DUI.SafeCall(function() edge = dress(g) end)
        end
        if ok and type(edge) == "table" and edge.CreateAnimationGroup then
            g.edge = edge
            alphaAnim(group(edge, "ghostEdge"), 1, 0, Motion.GHOST_EDGE)
        end
        local fade = g:CreateAnimationGroup()
        alphaAnim(fade, 1, 0, Motion.CLOSE)
        fade:SetScript("OnFinished", function() g:Hide() end)
        g.fade = fade
        ghosts[frame] = g
        -- Reopened mid-fade: the real window is back, so the ghost goes.
        frame:HookScript("OnShow", function() fade:Stop(); g:Hide() end)
    end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    g:SetFrameStrata(frame:GetFrameStrata())
    g:SetFrameLevel(frame:GetFrameLevel())
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    g:SetSize(w * s, h * s)
    g.fade:Stop()
    g:SetAlpha(1)
    if g.edge then
        local ef = g.edge.__duiMotion.ghostEdge
        ef:Stop()
        g.edge:SetAlpha(1)
        ef:Play()
    end
    g:Show()
    g.fade:Play()
end

-- Number tweens share one driver. A new tween on a key replaces the old one.
local tweens, driver = {}, nil

-- A step or done callback that errors is reported (DUI.SafeCall, so BugSack
-- sees it and repeats are only counted) and the tween goes on.
local function run(fn, ...)
    if fn then DUI.SafeCall(fn, ...) end
end

-- Iterate over a copy, since a step or done may start, replace or end tweens,
-- and modifying a table under pairs breaks it ("invalid key to 'next'").
local walkKeys, walkTweens = {}, {}

local function tick(self, dt)
    local n = 0
    for key, tw in pairs(tweens) do
        n = n + 1
        walkKeys[n], walkTweens[n] = key, tw
    end
    for i = 1, n do
        local key, tw = walkKeys[i], walkTweens[i]
        walkKeys[i], walkTweens[i] = nil, nil
        -- Ended or replaced by an earlier tween's callback, so skip it.
        if tweens[key] == tw then
            tw.t = tw.t + dt
            local p = tw.t / tw.dur
            if p >= 1 then
                tweens[key] = nil
                run(tw.step, tw.to)
                run(tw.done)
            else
                local e = 1 - (1 - p) ^ 3
                run(tw.step, tw.from + (tw.to - tw.from) * e)
            end
        end
    end
    if next(tweens) == nil then self:SetScript("OnUpdate", nil) end
end

function Motion.Tween(key, from, to, dur, step, done)
    dur = dur or Motion.NORMAL
    if not Motion.On() or dur <= 0 or from == to then
        tweens[key] = nil
        run(step, to)
        run(done)
        return
    end
    driver = driver or CreateFrame("Frame")
    tweens[key] = { from = from, to = to, dur = dur, t = 0, step = step, done = done }
    run(step, from)
    driver:SetScript("OnUpdate", tick)
end

-- The shared tween driver (nil until the first tween). Tests run it.
function Motion.Driver() return driver end

-- Eases one of our regions to an alpha from wherever it is, stepped by hand
-- (no animation group, so nothing else's alpha on it is lost). Going up from
-- hidden it shows at 0 first. With hide, it's hidden once it reaches 0.
-- Asked for the same goal while already heading there, it carries on, unless
-- dur is 0: a snap always lands at once (a recycled plate's cast bar). Motion
-- off or a secret alpha goes straight there.
function Motion.AlphaTo(region, to, dur, hide)
    local key = region.__duiAlphaKey
    if not key then key = {}; region.__duiAlphaKey = key end
    local shown = region:IsShown()
    if to > 0 and not shown then
        region:SetAlpha(0)
        region:Show()
    elseif to <= 0 and hide and not shown then
        Motion.Tween(key, 0, 0, 0)
        key.goal = nil
        return
    end
    local from = region:GetAlpha()
    if issecretvalue and issecretvalue(from) then from = to end
    local snap = type(dur) == "number" and dur <= 0
    if key.goal == to and from ~= to and not snap then return end
    key.goal = to
    Motion.Tween(key, from, to, dur or Motion.FAST, function(a) region:SetAlpha(a) end,
        function()
            key.goal = nil
            if hide and to <= 0 then region:Hide() end
        end)
end

-- Counts a number from what this text last showed up to `to`, writing each
-- step as fmt(n): whole numbers on the way, the exact value at the end. The
-- first number, nil, a secret, or motion off writes fmt(to) at once. Returns
-- true when it counts.
function Motion.CountTo(fs, to, fmt, dur)
    local key = fs.__duiCountKey
    if not key then key = {}; fs.__duiCountKey = key end
    local from = key.shown
    local plain = type(to) == "number" and not (issecretvalue and issecretvalue(to))
    key.shown = plain and to or nil
    if not plain or type(from) ~= "number" or from == to or not Motion.On() then
        Motion.Tween(key, 0, 0, 0)
        fs:SetText(fmt(to))
        return false
    end
    Motion.Tween(key, from, to, dur or Motion.NORMAL, function(v)
        fs:SetText(fmt(v == to and to or math.floor(v + 0.5)))
    end)
    return true
end

-- A light that runs once across `over` from left to right. `tex` is one of our
-- textures (an additive band). It fades in and out at the ends, so it needs
-- no mask. opts: width, dur (0.5), alpha (peak, 1), color {r,g,b}, inset (px
-- kept clear at both ends), key (tween key, default tex), done. Does nothing
-- with motion off.
function Motion.Sweep(tex, over, opts)
    opts = opts or {}
    if not Motion.On() then return end
    local inset, peak = opts.inset or 0, opts.alpha or 1
    tex:ClearAllPoints()
    if opts.width then tex:SetWidth(opts.width) end
    local c = opts.color
    if c then tex:SetVertexColor(c[1], c[2], c[3]) end
    tex:SetAlpha(0)
    tex:Show()
    Motion.Tween(opts.key or tex, 0, 1, opts.dur or 0.5, function(p)
        local w = over:GetWidth() or 0
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", over, "LEFT", inset + (opts.reverse and 1 - p or p) * (w - 2 * inset), 0)
        local a = p < 0.15 and p / 0.15 or (p > 0.75 and (1 - p) / 0.25 or 1)
        tex:SetAlpha(peak * a)
    end, function()
        tex:Hide()
        if opts.done then opts.done() end
    end)
end

-- Sliders: something tucked away (p 0) coming out (p 1) and back, eased in and
-- out, turning around from wherever it is if the goal changes partway.
-- apply(sl) places it where p says, done(sl) runs on arrival. Each slider has
-- its own driver frame, shown only while moving (a child of opts.parent, so
-- it stops when that's hidden).
local Slider = {}
Slider.__index = Slider

local function smooth(t) return t * t * (3 - 2 * t) end

-- opts: p (start position, default 1 = out), dur (seconds), parent, done.
function Motion.Slider(apply, opts)
    opts = opts or {}
    local p = opts.p or 1
    local sl = setmetatable({ p = p, goal = p, dur = opts.dur or Motion.NORMAL,
        apply = apply, done = opts.done }, Slider)
    sl.driver = CreateFrame("Frame", nil, opts.parent or UIParent)
    sl.driver:Hide()
    sl.driver:SetScript("OnUpdate", function(_, dt) sl:Tick(dt or 0) end)
    return sl
end

function Slider:Moving() return self.t ~= nil end

-- Jumps straight to p and stays (not an arrival, so no done).
function Slider:Jump(p)
    self.p, self.goal, self.t = p, p, nil
    self.driver:Hide()
    if self.apply then self.apply(self) end
end

-- Heads toward goal from wherever it is. If already there or heading there,
-- it carries on. Motion off goes straight there.
function Slider:To(goal)
    if goal == self.goal and (self.t or self.p == goal) then return end
    if not Motion.On() or self.dur <= 0 then
        self:Jump(goal)
        if self.done then self.done(self) end
        return
    end
    self.from, self.goal, self.t = self.p, goal, 0
    self.driver:Show()
    if self.apply then self.apply(self) end
end

function Slider:Tick(dt)
    if not self.t then self.driver:Hide(); return end
    self.t = math.min(1, self.t + dt / self.dur)
    self.p = self.from + (self.goal - self.from) * smooth(self.t)
    if self.t >= 1 then
        self.p, self.t = self.goal, nil
        self.driver:Hide()
    end
    if self.apply then self.apply(self) end
    if not self.t and self.done then self.done(self) end
end

-- Coming in from the side: fades in while gliding from dx, dy px away back to
-- rest (visual only, the frame never moves). Same per-frame cost as Appear's
-- lift, so keep it short. delay holds it invisible that long first (rows
-- arriving one after another).
function Motion.SlideIn(frame, dx, dy, dur, delay)
    if not Motion.On() then return end
    dur = dur or Motion.NORMAL
    local g = group(frame, "slideIn")
    if not g.__built then
        local hide = g:CreateAnimation("Alpha") -- invisible while it jumps away
        hide:SetFromAlpha(0)
        hide:SetToAlpha(0)
        hide:SetDuration(0)
        hide:SetOrder(1)
        g.jump = g:CreateAnimation("Translation")
        g.jump:SetDuration(0)
        g.jump:SetOrder(1)
        g.move = g:CreateAnimation("Translation")
        g.move:SetOrder(2)
        g.move:SetSmoothing("OUT")
        g.fade = g:CreateAnimation("Alpha")
        g.fade:SetFromAlpha(0)
        g.fade:SetToAlpha(1)
        g.fade:SetOrder(2)
        g.hide = hide
        g.__built = true
    end
    g.dx, g.dy, g.delay = dx, dy, delay or 0
    -- Only invisible while waiting. A 0 s alpha step at 0 can leave the frame
    -- invisible for good when the group plays again (seen in game on the
    -- donators page's first-place card, which has no delay, on the page's second
    -- open). Without a wait the fade below starts it from 0.
    local wait = g.delay > 0 and 0 or 1
    g.hide:SetFromAlpha(wait)
    g.hide:SetToAlpha(wait)
    g.hide:SetDuration(g.delay)
    g.jump:SetOffset(dx, dy)
    g.move:SetOffset(-dx, -dy)
    g.move:SetDuration(dur)
    g.fade:SetDuration(dur)
    g:Play()
end

-- Something already shown moving to a new spot: drawn dx, dy px away (where
-- it was), gliding back to rest, alpha untouched. Visual only.
function Motion.Glide(frame, dx, dy, dur)
    if not Motion.On() then return end
    local g = group(frame, "glide")
    if not g.__built then
        g.jump = g:CreateAnimation("Translation")
        g.jump:SetDuration(0)
        g.jump:SetOrder(1)
        g.move = g:CreateAnimation("Translation")
        g.move:SetOrder(2)
        g.move:SetSmoothing("OUT")
        g.__built = true
    end
    g.dx, g.dy = dx, dy
    g.jump:SetOffset(dx, dy)
    g.move:SetOffset(-dx, -dy)
    g.move:SetDuration(dur or Motion.NORMAL)
    g:Play()
end

-- Back at rest at once. Stops a SlideIn or Glide still playing.
function Motion.Settle(frame)
    local m = frame.__duiMotion
    if not m then return end
    if m.slideIn then m.slideIn:Stop() end
    if m.glide then m.glide:Stop() end
end

-- Kicks: an interrupted enemy cast (nameplates, unit frame cast bars) plays
-- one of these, picked by the player (`Motion.KICKS`):
--   blade     a bright line slices along the bar, then it splits into top and
--             bottom halves that fly apart
--   shatter   it breaks into shards that burst out and fall
--   snap      it cracks in the middle and both ends droop away
--   burn      a hot edge eats the fill back to its start, embers rising
--   rewind    the fill whips back to empty with a streak
--   shock     a burst of light from the hit, the bar jolts and fades
--   fizzle    the fill goes dark as sparks leak off it
-- The pieces are flat copies of the bar laid out in its shape
-- (`Motion.LayPiece`, the angled end leaned with SetVertexOffset, no masks).
-- Only sizes and offsets change, never scale. Built with the bar at login,
-- never during a fight.
Motion.KICKS = { "blade", "shatter", "snap", "burn", "rewind", "shock", "fizzle" }
Motion.KICK_NAMES = { blade = "Blade", shatter = "Shatter", snap = "Snap", burn = "Burn out",
    rewind = "Rewind", shock = "Shockwave", fizzle = "Fizzle" }
Motion.BLADE_CUT = 0.12 -- seconds the line takes to cross
Motion.BLADE_SPLIT = 7 -- px each half flies
Motion.BLADE_FOR = 0.85 -- total seconds (for every kick)
Motion.BLADE_EDGE = { 1, 0.96, 0.88 } -- someone else's interrupt light (yours uses the accent)
Motion.BLADE_BURST = { 1, 0.5, 0.4 } -- the glow as it breaks
Motion.KICK_SHARDS = 6      -- shatter's pieces
Motion.KICK_SPARKS = 14 -- embers and sparks
Motion.KICK_DARK = { 0.12, 0.11, 0.1 } -- fizzle's burnt-out fill
local WHITE8 = "Interface\\Buttons\\WHITE8x8"

-- k.pieces[i] is a frame with .edge (the border) and .fill. k.halves is the
-- first two (used by blade).
function Motion.NewBlade(parent)
    local k = CreateFrame("Frame", nil, parent)
    k:EnableMouse(false)
    k.pieces = {}
    for i = 1, Motion.KICK_SHARDS do
        local h = CreateFrame("Frame", nil, k)
        h.edge = h:CreateTexture(nil, "BORDER", nil, 0)
        h.edge:SetTexture(WHITE8)
        h.fill = h:CreateTexture(nil, "BORDER", nil, 1)
        h.fill:SetTexture(WHITE8)
        h:Hide()
        k.pieces[i] = h
    end
    k.halves = { k.pieces[1], k.pieces[2] }
    local function add(file, sub)
        local t = k:CreateTexture(nil, "OVERLAY", nil, sub)
        t:SetTexture(file)
        t:SetBlendMode("ADD")
        t:SetAlpha(0)
        return t
    end
    k.line = add(WHITE8, 6)
    k.tip = add(DUI.MEDIA .. "glow.png", 7)
    k.burst = add(DUI.MEDIA .. "glow.png", 5)
    k.flash = add(WHITE8, 4)
    k.sparks = {}
    for i = 1, Motion.KICK_SPARKS do k.sparks[i] = add(DUI.MEDIA .. "glow.png", 7) end
    k:Hide()
    return k
end

local function offsets(tex, lean, dl, dr)
    if not tex.SetVertexOffset then return end
    tex:SetVertexOffset(1, 0, dl)
    tex:SetVertexOffset(2, 0, dl)
    tex:SetVertexOffset(3, 0, dr)
    tex:SetVertexOffset(4, lean, dr)
end

-- Lays piece h over the bar's region x0..x1, y0..y1 (px from its top left) in
-- the bar's shape. shape: { right = fn(y, inset) giving the bar's right end x
-- at y down, T = border px, edge = rgb, fill = rgb }. whole gives a border all
-- around (a shard), otherwise only on the bar's own sides. noEdge / noFill
-- drop one of them.
function Motion.LayPiece(h, over, shape, x0, x1, y0, y1, whole, noEdge, noFill)
    local T = shape.T or 0
    local H = over:GetHeight()
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", over, "TOPLEFT", x0, -y0)
    h:SetSize(math.max(x1 - x0, 0.01), math.max(y1 - y0, 0.01))
    h.x0, h.y0 = x0, y0
    local function er(y) return math.min(x1, shape.right(y, 0)) - x0 end
    local e, b = h.edge, shape.edge
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    e:SetPoint("BOTTOMRIGHT", h, "TOPLEFT", er(y0), -(y1 - y0))
    e.lean = er(y1) - er(y0)
    offsets(e, e.lean, 0, 0)
    e:SetVertexColor(b[1], b[2], b[3], 1)
    e:SetShown(T > 0 and not noEdge)
    local l = (whole or x0 <= 0) and T or 0
    local t = (whole or y0 <= 0) and T or 0
    local bt = (whole or y1 >= H) and T or 0
    local function fr(y) return math.min(x1 - (whole and T or 0), shape.right(y, T)) - x0 end
    local f, c = h.fill, shape.fill
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", h, "TOPLEFT", l, -t)
    f:SetPoint("BOTTOMRIGHT", h, "TOPLEFT", math.max(fr(y0 + t), l + 0.01), -(y1 - y0 - bt))
    f.lean = fr(y1 - bt) - fr(y0 + t)
    offsets(f, f.lean, 0, 0)
    f:SetVertexColor(c[1], c[2], c[3], 1)
    f:SetShown(not noFill)
    h:SetAlpha(1)
end

-- Tilts a laid piece: left side moved dl px up, right side dr.
local function tilt(h, dl, dr)
    offsets(h.edge, h.edge.lean or 0, dl, dr)
    offsets(h.fill, h.fill.lean or 0, dl, dr)
end

local function out3(v) return 1 - (1 - v) ^ 3 end
local function clamp(v) return v < 0 and 0 or v > 1 and 1 or v end

-- Each kick has start(k, over, W, H, shape), called once, then step(k, over,
-- s, W, H) with s the seconds elapsed. `pieces` is how many of k.pieces it shows.
local KICK = {}

KICK.blade = {
    pieces = 2,
    start = function(k, over, W, H, shape)
        local half = H / 2
        for i = 1, 2 do Motion.LayPiece(k.pieces[i], over, shape, 0, W, (i - 1) * half, i * half) end
        k.line:ClearAllPoints()
        k.line:SetPoint("LEFT", over, "LEFT", -6, 0)
        k.line:SetHeight(DUI.Pixel.Px(over, 2))
        k.tip:SetSize(26, 8)
        return true -- the bar holds while the line runs across
    end,
    step = function(k, over, s, W, H)
        local CUT, FOR, SPLIT = Motion.BLADE_CUT, Motion.BLADE_FOR, Motion.BLADE_SPLIT
        -- The cut: the line runs along the bar's middle with a glow at its tip.
        local reach = out3(clamp(s / CUT)) * (W + 12)
        local la = s < CUT and 1 or clamp(1 - (s - CUT) / 0.2)
        k.line:SetWidth(math.max(reach, 0.01))
        k.line:SetAlpha(la)
        k.tip:ClearAllPoints()
        k.tip:SetPoint("CENTER", over, "LEFT", -6 + reach, 0)
        k.tip:SetAlpha(la)
        if s < CUT then return end
        -- The split: the bar gives way to its halves, flying apart and fading.
        if not k.broken then
            k.broken = true
            over:SetAlpha(0)
            for i = 1, 2 do k.pieces[i]:Show() end
        end
        local v = out3(clamp((s - CUT) / 0.4))
        local fade = clamp(1 - (s - 0.4) / (FOR - 0.4))
        for i = 1, 2 do
            local h = k.pieces[i]
            h:SetPoint("TOPLEFT", over, "TOPLEFT", 0, -h.y0 + (i == 1 and 1 or -1) * SPLIT * v)
            h:SetAlpha(fade)
        end
        k.burst:SetSize(W * 1.3 * (0.6 + v), 10 + 18 * v)
        k.burst:SetAlpha(0.5 * (1 - v))
    end,
}

KICK.shatter = {
    pieces = Motion.KICK_SHARDS,
    start = function(k, over, W, H, shape)
        local n = Motion.KICK_SHARDS
        for i = 1, n do Motion.LayPiece(k.pieces[i], over, shape, W * (i - 1) / n, W * i / n, 0, H, true) end
    end,
    step = function(k, over, s, W, H)
        local n = Motion.KICK_SHARDS
        local v = clamp(s / Motion.BLADE_FOR)
        local fly = out3(clamp(s / 0.5))
        local fade = clamp(1 - (s - 0.25) / (Motion.BLADE_FOR - 0.25))
        for i = 1, n do
            local h = k.pieces[i]
            local c = i - (n + 1) / 2 -- offset from the middle
            local dx = c * 7 * fly
            local dy = (10 + (i % 2) * 5) * fly - 70 * v * v -- up, then falling
            h:SetPoint("TOPLEFT", over, "TOPLEFT", h.x0 + dx, -h.y0 + dy)
            local tw = c * 2.2 * fly * (i % 2 == 0 and 1 or -1)
            tilt(h, tw, -tw)
            h:SetAlpha(fade)
        end
        k.flash:SetAlpha(0.85 * clamp(1 - s / 0.12))
        k.burst:SetSize(W * (0.5 + fly), 12 + 20 * fly)
        k.burst:SetAlpha(0.45 * (1 - fly))
    end,
}

KICK.snap = {
    pieces = 2,
    start = function(k, over, W, H, shape)
        local mid = W * 0.55
        Motion.LayPiece(k.pieces[1], over, shape, 0, mid, 0, H, true)
        Motion.LayPiece(k.pieces[2], over, shape, mid, W, 0, H, true)
        k.mid = mid
        k.burst:ClearAllPoints()
        k.burst:SetPoint("CENTER", over, "TOPLEFT", mid, -H / 2)
    end,
    step = function(k, over, s, W, H)
        local v = out3(clamp(s / 0.45))
        local fade = clamp(1 - (s - 0.4) / (Motion.BLADE_FOR - 0.4))
        local drop = H * 1.1 * v
        local a, b = k.pieces[1], k.pieces[2]
        a:SetPoint("TOPLEFT", over, "TOPLEFT", -3 * v, -2 * v * v)
        b:SetPoint("TOPLEFT", over, "TOPLEFT", k.mid + 3 * v, -2 * v * v)
        tilt(a, -drop, 0) -- the left end droops from the break
        tilt(b, 0, -drop) -- and so does the right
        a:SetAlpha(fade)
        b:SetAlpha(fade)
        k.burst:SetSize(18 + 30 * v, 14 + 20 * v)
        k.burst:SetAlpha(0.8 * (1 - v))
    end,
}

-- Burn and Rewind: the border and an empty track stay (piece 1) while the
-- fill (piece 2, no border) shrinks back to the start.
local function shrinkStart(k, over, W, H, shape)
    Motion.LayPiece(k.pieces[1], over, shape, 0, W, 0, H)
    local bg = DUI.Style.BACKGROUND
    k.pieces[1].fill:SetVertexColor(bg[1], bg[2], bg[3], 1)
    k.shape = shape
    Motion.LayPiece(k.pieces[2], over, shape, 0, W, 0, H, false, true)
end

local function shrinkTo(k, over, x, H)
    if x <= 1 then k.pieces[2]:Hide(); return end
    Motion.LayPiece(k.pieces[2], over, k.shape, 0, x, 0, H, false, true)
end

KICK.burn = {
    pieces = 2,
    start = function(k, over, W, H, shape)
        shrinkStart(k, over, W, H, shape)
        k.tip:SetSize(16, H * 1.8)
        k.burnt = {}
    end,
    step = function(k, over, s, W, H)
        local v = out3(clamp(s / 0.55))
        local x = W * (1 - v)
        shrinkTo(k, over, x, H)
        k.pieces[1]:SetAlpha(clamp(1 - (s - 0.55) / (Motion.BLADE_FOR - 0.55)))
        k.tip:ClearAllPoints()
        k.tip:SetPoint("CENTER", over, "LEFT", x, 0)
        k.tip:SetAlpha(v < 1 and 0.9 or 0)
        -- Embers: each lights up where the edge passed, then rises and fades.
        for i, e in ipairs(k.sparks) do
            local born = (i - 1) / #k.sparks * 0.5
            local t = (s - born) / 0.45
            if t < 0 or t > 1 then
                e:SetAlpha(0)
            else
                k.burnt[i] = k.burnt[i] or (W * (1 - out3(clamp(born / 0.55))) + ((i * 7) % 9 - 4))
                e:ClearAllPoints()
                e:SetPoint("CENTER", over, "BOTTOMLEFT", k.burnt[i], H * 0.5 + t * (14 + (i % 3) * 5))
                e:SetSize(5, 5)
                e:SetAlpha(1 - t)
            end
        end
    end,
}

KICK.rewind = {
    pieces = 2,
    start = function(k, over, W, H, shape)
        shrinkStart(k, over, W, H, shape)
        k.line:SetHeight(math.max(H - 4, 1))
        k.tip:SetSize(22, H * 1.6)
    end,
    step = function(k, over, s, W, H)
        local v = out3(clamp(s / 0.28))
        local x = W * (1 - v)
        shrinkTo(k, over, x, H)
        k.pieces[1]:SetAlpha(clamp(1 - (s - 0.35) / (Motion.BLADE_FOR - 0.35)))
        -- The streak where the fill was, fading behind it.
        k.line:ClearAllPoints()
        k.line:SetPoint("LEFT", over, "LEFT", x, 0)
        k.line:SetWidth(math.max(W - x, 0.01))
        k.line:SetAlpha(0.7 * clamp(1 - s / 0.45))
        k.tip:ClearAllPoints()
        k.tip:SetPoint("CENTER", over, "LEFT", x, 0)
        k.tip:SetAlpha(v < 1 and 0.8 or 0)
    end,
}

KICK.shock = {
    pieces = 1,
    start = function(k, over, W, H, shape)
        Motion.LayPiece(k.pieces[1], over, shape, 0, W, 0, H)
        k.tip:ClearAllPoints()
        k.tip:SetPoint("CENTER", over, "CENTER")
    end,
    step = function(k, over, s, W, H)
        local j = s < 0.2 and math.sin(s * 90) * 3 * (1 - s / 0.2) or 0
        k.pieces[1]:SetPoint("TOPLEFT", over, "TOPLEFT", j, 0)
        k.pieces[1]:SetAlpha(clamp(1 - (s - 0.25) / 0.45))
        local v = out3(clamp(s / 0.5))
        k.burst:SetSize(W * (0.4 + 1.4 * v), H * (1 + 4 * v))
        k.burst:SetAlpha(0.7 * (1 - v))
        k.tip:SetSize(30 + 40 * v, H * (1.5 + 2 * v))
        k.tip:SetAlpha(0.9 * clamp(1 - s / 0.3))
        k.flash:SetAlpha(0.8 * clamp(1 - s / 0.1))
    end,
}

KICK.fizzle = {
    pieces = 1,
    start = function(k, over, W, H, shape)
        Motion.LayPiece(k.pieces[1], over, shape, 0, W, 0, H)
        k.from = shape.fill
    end,
    step = function(k, over, s, W, H)
        local v = out3(clamp(s / 0.6))
        local a, d = k.from, Motion.KICK_DARK
        k.pieces[1].fill:SetVertexColor(a[1] + (d[1] - a[1]) * v, a[2] + (d[2] - a[2]) * v, a[3] + (d[3] - a[3]) * v, 1)
        k.pieces[1]:SetAlpha(clamp(1 - (s - 0.5) / (Motion.BLADE_FOR - 0.5)))
        for i, e in ipairs(k.sparks) do
            local born = (i % 7) * 0.05
            local t = (s - born) / 0.6
            if t < 0 or t > 1 then
                e:SetAlpha(0)
            else
                local x = ((i * 37) % 97) / 97 * W
                e:ClearAllPoints()
                e:SetPoint("CENTER", over, "BOTTOMLEFT", x + math.sin(t * 8 + i) * 3, H * 0.6 + t * (18 + (i % 5) * 4))
                e:SetSize(4, 4)
                e:SetAlpha(0.95 * (1 - t))
            end
        end
    end,
}

-- over: the bar it plays on (hidden while its pieces stand in, restored
-- after). style: one of Motion.KICKS (unknown = blade). r, g, b: the light's
-- color. shape: see Motion.LayPiece (nil means the bar isn't laid out, so no
-- kick). Does nothing with motion off (the bar's own hold covers it).
function Motion.Kick(k, over, style, r, g, b, shape)
    if not (k and shape) or not Motion.On() then return end
    local W, H = over:GetWidth(), over:GetHeight()
    if type(W) ~= "number" or type(H) ~= "number" or W <= 0 or H <= 0 then return end
    if not KICK[style] then style = "blade" end
    local kick = KICK[style]
    Motion.Unblade(k)
    k:SetFrameStrata(over:GetFrameStrata())
    k:SetFrameLevel(over:GetFrameLevel() + 6)
    k:SetAlpha(1)
    for _, h in ipairs(k.pieces) do h:Hide() end
    for _, t in ipairs({ k.line, k.tip, k.burst, k.flash }) do t:SetAlpha(0) end
    for _, e in ipairs(k.sparks) do
        e:SetAlpha(0)
        e:SetVertexColor(r, g, b)
    end
    k.line:SetVertexColor(r, g, b)
    k.tip:SetVertexColor(r, g, b)
    k.flash:SetVertexColor(r, g, b)
    k.flash:ClearAllPoints()
    k.flash:SetAllPoints(over)
    local c = Motion.BLADE_BURST
    k.burst:SetVertexColor(c[1], c[2], c[3])
    k.burst:ClearAllPoints()
    k.burst:SetPoint("CENTER", over, "CENTER")
    k.broken = nil
    k.over = over
    k.style = style
    k:Show()
    -- The pieces replace the bar at once, unless the kick holds it a moment (the
    -- blade's cut).
    if not kick.start(k, over, W, H, shape) then
        for i = 1, kick.pieces do k.pieces[i]:Show() end
        over:SetAlpha(0)
    end
    k.gen = (k.gen or 0) + 1
    local gen, FOR = k.gen, Motion.BLADE_FOR
    -- One tween; s is the seconds elapsed (recovered from Tween's ease-out).
    Motion.Tween(k, 0, 1, FOR, function(e)
        if k.gen ~= gen then return end
        kick.step(k, over, (1 - (1 - e) ^ (1 / 3)) * FOR, W, H)
    end, function()
        if k.gen ~= gen then return end
        k:Hide()
        over:SetAlpha(1)
    end)
end

-- A new cast, a new unit, or the plate going away: end the kick at once and
-- restore the bar.
function Motion.Unblade(k)
    if not (k and k:IsShown()) then return end
    k.gen = (k.gen or 0) + 1
    Motion.Tween(k, 0, 0, 0) -- ends its tween
    k:Hide()
    if k.over then k.over:SetAlpha(1) end
end

-- Who interrupted it: a name (maybe secret, only ever passed to SetText) and a
-- class token (maybe secret or nil) from the interrupter's GUID. A unit near
-- you (group, pet, target) is resolved by token, else via the game's player
-- info. element picks whose last-names setting applies (DUI.UnitName).
function Motion.KickerName(guid, element)
    if type(guid) == "nil" then return end
    local secret = issecretvalue and issecretvalue(guid)
    if not secret and UnitTokenFromGUID then
        local u = UnitTokenFromGUID(guid)
        if type(u) == "string" and not (issecretvalue and issecretvalue(u)) then
            return DUI.UnitName(u, element), select(2, UnitClass(u))
        end
    end
    if not GetPlayerInfoByGUID then return end
    local ok, _, token, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
    if not ok or type(name) == "nil" then return end
    if not (issecretvalue and issecretvalue(name)) and name == "" then return end
    return name, token
end

-- The "Kicked by" tag: a tan label and the kicker's name in class color next
-- to an interrupted cast bar. It fades in quickly, holds KICKED_BY_FOR, then
-- fades out. The caller positions it.
Motion.KICKED_BY_FOR = 2.2
function Motion.NewKickTag(parent, font)
    local t = CreateFrame("Frame", nil, parent)
    t:EnableMouse(false)
    t:SetSize(1, 1)
    local Style = DUI.Style
    t.label = Style.Text(t, Style.SIZE.small, "LEFT", font)
    t.label:SetPoint("LEFT", t, "LEFT", 0, 0)
    t.label:SetText(DUI.L["Kicked by"])
    t.name = Style.Text(t, Style.SIZE.small, "LEFT", font)
    t.name:SetPoint("LEFT", t.label, "RIGHT", 3, 0)
    t:Hide()
    return t
end

-- Shows the tag for guid's kicker (nothing if there's no name). size is text px.
function Motion.KickTag(t, guid, element, size)
    if not t then return end
    local name, token = Motion.KickerName(guid, element)
    if type(name) == "nil" then return end
    local Style = DUI.Style
    if size then
        Style.SetTextSize(t.label, size)
        Style.SetTextSize(t.name, size)
    end
    t:SetHeight(size or Style.SIZE.small)
    t.label:SetText(DUI.L["Kicked by"])
    Style.InkText(t.label, "LABEL")
    t.name:SetText(name)
    t.name:SetTextColor(Style.ClassTextColor(token))
    t.gen = (t.gen or 0) + 1
    local gen = t.gen
    local from = t:IsShown() and t:GetAlpha() or 0
    t:Show()
    Motion.Tween(t, from, 1, Motion.FAST, function(a) t:SetAlpha(a) end)
    C_Timer.After(Motion.KICKED_BY_FOR, function()
        if t.gen ~= gen then return end
        Motion.Tween(t, 1, 0, Motion.NORMAL, function(a) t:SetAlpha(a) end, function()
            if t.gen == gen then t:Hide() end
        end)
    end)
end

-- A new unit or the plate going away: the tag goes at once.
function Motion.KickTagOff(t)
    if not (t and t:IsShown()) then return end
    t.gen = (t.gen or 0) + 1
    Motion.Tween(t, 0, 0, 0)
    t:Hide()
end
