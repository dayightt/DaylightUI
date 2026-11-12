-- Short light effects on the unit frames for moments a player notices:
-- - combat starting: a light runs along the top edge of each frame and tile
--   in turn (your portrait ring already fills red)
-- - combat ending: the same, slower and warmer
-- - your target or focus dying: a soft ash-colored breath rises off the frame
--   and fades, and DEAD fades in instead of snapping
-- - a ready check: a tile that answers ready shines once in the good color,
--   and when everyone is ready one light ripples across all of them
-- Only our own lights, on a small frame over each body. Nothing protected
-- moves and nothing a fight needs waits for them. Motion off disables all of it.

local _, ns = ...
local DUI = DaylightUI
local Motion = DUI.Motion
local Style = DUI.Style
local Pixel = DUI.Pixel

local Moments = {}
ns.Moments = Moments

Moments.FILE = DUI.MEDIA .. "glow.png"
Moments.BAND = 0.4          -- the light's width, as a share of the frame's
Moments.STEP = 0.035        -- seconds between one frame's light and the next
Moments.STEPS_MAX = 0.5     -- the whole ripple always starts within this (a 40-player raid)
Moments.PULL = { dur = 0.5, alpha = 0.9 }               -- a fight starting
Moments.CALM = { dur = 0.9, alpha = 0.55 }              -- combat ending: slower, softer
Moments.READY = { dur = 0.6, alpha = 0.35 }             -- one tile answering ready
Moments.ALL_READY = { dur = 0.6, alpha = 0.5 }          -- everyone ready
Moments.BREATH = 0.9        -- seconds the last breath takes to rise and fade
Moments.BREATH_RISE = 10    -- px it rises
Moments.BREATH_ALPHA = 0.45

-- A small frame over the body holding a light, created on first use.
-- "edge" is a thin strip along the top, "body" covers the whole frame.
local function holder(f, kind)
    f.moments = f.moments or {}
    local h = f.moments[kind]
    if h then return h end
    h = CreateFrame("Frame", nil, f)
    h:SetFrameLevel(f:GetFrameLevel() + 8)
    if kind == "edge" then
        h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        h:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        h:SetHeight(1)
    else
        h:SetAllPoints(f)
    end
    local t = h:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Moments.FILE)
    t:SetBlendMode("ADD")
    t:Hide()
    h.light = t
    f.moments[kind] = h
    return h
end

-- One light across one frame. look: { dur, alpha }; color: { r, g, b }.
local function sweep(f, kind, look, color)
    local h = holder(f, kind)
    local w, H = f:GetWidth() or 0, f:GetHeight() or 0
    if w <= 0 then return end
    local t = h.light
    t:SetHeight(kind == "edge" and Pixel.Px(f, 3) or H * 1.2)
    Motion.Sweep(t, h, { width = w * Moments.BAND, dur = look.dur, alpha = look.alpha, color = color,
        inset = w * Moments.BAND * 0.25 })
end

-- Frames that can take a light now: ours, shown, and not samples.
local function live(f)
    return f and not f.test and f:IsVisible()
end

-- Every shown frame in order: you, target, focus, pet, target of target,
-- then the group's tiles.
local ORDER = { "player", "target", "focus", "pet", "targettarget", "focustarget" }
local list = {}
local function frames()
    wipe(list)
    for _, u in ipairs(ORDER) do
        local f = ns.frames[u]
        if live(f) then list[#list + 1] = f end
    end
    for _, b in ns.Group.Buttons() do
        if live(b) then list[#list + 1] = b end
    end
    return list
end

-- A light on each frame in turn, the whole ripple starting within STEPS_MAX.
local function ripple(all, kind, look, color)
    local n = #all
    local gap = n > 1 and math.min(Moments.STEP, Moments.STEPS_MAX / (n - 1)) or 0
    for i, f in ipairs(all) do
        if i == 1 or gap <= 0 then
            sweep(f, kind, look, color)
        else
            C_Timer.After((i - 1) * gap, function()
                if live(f) then sweep(f, kind, look, color) end
            end)
        end
    end
end

-- Combat starting (on = true) or ending: the accent, or a warm gold on the
-- way out. Dying also ends combat, and gets no warm light.
function Moments.Fight(on)
    if not Motion.On() then return end
    if not on and ns.UF.UnitState("player") then return end
    local all = frames()
    if #all == 0 then return end
    local r, g, b
    if on then r, g, b = Style.Accent() else
        local c = Style.INK.MONEY
        r, g, b = c[1], c[2], c[3]
    end
    -- Copy, since the next call reuses the list while timers are still running.
    local copy = {}
    for i, f in ipairs(all) do copy[i] = f end
    ripple(copy, "edge", on and Moments.PULL or Moments.CALM, { r, g, b })
end

-- The login reveal (Fade.Reveal). Each shown frame and tile arrives as the
-- ripple reaches it. The target uses its own arrival without the fade, since
-- the reveal fades it in: fills grow from empty, the portrait pops with its
-- light, the name tab slides up. The fills sit empty from the start and only
-- grow once the frame is half visible (LOGIN_SEEN of the fade-in), otherwise
-- the client's quick glide would finish unseen. If combat starts first, the
-- real values show at once.
Moments.LOGIN_SEEN = 0.5
local function fills(f, v)
    local u = f.unitToken
    if type(u) ~= "string" or not UnitExists(u) then return end
    f.health:SetValue(v or UnitHealth(u))
    if f.power and f.power:IsShown() then f.power:SetValue(v or UnitPower(u)) end
end

function Moments.Login()
    if not Motion.On() then return end
    local Fade = DUI.Fade
    for _, f in ipairs(frames()) do
        if f.health then
            fills(f, 0)
            C_Timer.After((Fade.RippleDelay(f) or 0) + Fade.INTRO * Moments.LOGIN_SEEN, function()
                if live(f) and not InCombatLockdown() then ns.Arrive.Start(f, nil, true) else fills(f) end
            end)
        end
    end
end
DUI.On("LoginReveal", function() Moments.Login() end)

-- The target or focus just died (not a swap to a corpse). A soft breath rises
-- off the frame and fades, and the DEAD text fades in. Returns true when DEAD
-- fades in, otherwise the caller shows it. The text fade is a manual tween,
-- not an animation group: a playing group's alpha overrides every SetAlpha,
-- which brought back the next target's hidden full-health text.
function Moments.Breath(f)
    if not Motion.On() or not live(f) then return false end
    local h = holder(f, "body")
    local t = h.light
    local w, H = f:GetWidth() or 0, f:GetHeight() or 0
    if w <= 0 then return false end
    local c = Style.INK.LABEL
    t:SetSize(w * 0.9, H * 1.4)
    t:SetVertexColor(c[1], c[2], c[3])
    t:ClearAllPoints()
    t:SetPoint("CENTER", h, "CENTER", 0, 0)
    t:SetAlpha(0)
    t:Show()
    h.breathKey = h.breathKey or {}
    h.breathing = true
    Motion.Tween(h.breathKey, 0, 1, Moments.BREATH, function(p)
        t:ClearAllPoints()
        t:SetPoint("CENTER", h, "CENTER", 0, p * Moments.BREATH_RISE)
    -- In quickly, out slowly, like a breath leaving.
        local a = p < 0.2 and p / 0.2 or (1 - p) / 0.8
        t:SetAlpha(Moments.BREATH_ALPHA * a)
    end, function() h.breathing = nil; t:Hide() end)
    local fs = f.percentText
    if not (fs and fs:IsShown()) then return false end
    h.textKey = h.textKey or {}
    h.textFading = true
    Motion.Tween(h.textKey, 0, 1, Motion.SLOW, function(a) fs:SetAlpha(a) end,
        function() h.textFading = nil end)
    return true
end

-- DEAD is still fading in. A health event meanwhile leaves its alpha alone.
function Moments.Breathing(f)
    local h = f.moments and f.moments.body
    return h ~= nil and h.textFading == true
end

-- A new unit on the frame. Stop the last one's breath and DEAD fade at once so
-- the new unit's text follows its own settings.
function Moments.Still(f)
    local h = f.moments and f.moments.body
    if not h then return end
    if h.textFading then
        h.textFading = nil
        Motion.Tween(h.textKey, 0, 0, 0)
    end
    if h.breathing then
        h.breathing = nil
        Motion.Tween(h.breathKey, 0, 0, 0)
        h.light:Hide()
    end
end

-- One tile answering ready: a soft light across it in the good color.
function Moments.Ready(b)
    if not Motion.On() or not b or not b:IsVisible() then return end
    local c = Style.INK.GOOD
    sweep(b, "body", Moments.READY, { c[1], c[2], c[3] })
end

-- Everyone answered ready: one light in the accent ripples across every shown
-- tile. tiles is optional, the ones to light for a practice check.
function Moments.AllReady(tiles)
    if not Motion.On() then return end
    local all = {}
    for _, b in ipairs(tiles or {}) do
        if b:IsVisible() then all[#all + 1] = b end
    end
    if not tiles then
        for _, b in ns.Group.Buttons() do
            if live(b) then all[#all + 1] = b end
        end
    end
    if #all == 0 then return end
    local r, g, b = Style.Accent()
    ripple(all, "body", Moments.ALL_READY, { r, g, b })
end

-- Did every shown tile answer ready? A secret or missing answer counts as no.
function Moments.EveryoneReady()
    local any = false
    for _, b in ns.Group.Buttons() do
        if live(b) and type(b.unitToken) == "string" and UnitExists(b.unitToken) then
            local ok, s = pcall(GetReadyCheckStatus, b.unitToken)
            if not ok or (issecretvalue and issecretvalue(s)) or s ~= "ready" then return false end
            any = true
        end
    end
    return any
end
