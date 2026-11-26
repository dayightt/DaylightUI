-- Daybreak: a slim crescent riding the fill's moving end, like a sun just
-- breaking the horizon. At rest its rim breathes and a bright bead sits at its
-- apex; a hit pushes a shadow into the fill, a heal draws two rims in toward the
-- end. Both drawings are flipbook sheets the client steps through
-- (tools/make_daybreak.py), pinned to the end at a fixed size and cut by the
-- fill's own masks, so nothing reads the bar's value and no Lua runs while the
-- bar sits there. A reaction is one non-looping group: a new one replaces the
-- old one at once.

local _, DUI = ...
local Style, BarFx, L = DUI.Style, DUI.BarFx, DUI.L

BarFx.DAYBREAK_FRAMES = 64
BarFx.DAYBREAK_COLS = 4
BarFx.DAYBREAK_LOOP = 5        -- seconds for one breath of the rim
BarFx.DAYBREAK_REACT = 0.74    -- a hit or a heal, whatever the speed setting
BarFx.DAYBREAK_SPAN = 4        -- a sheet's width in bar heights
-- At this height or lower the art drops the sun's cuts for one wider rim. Its
-- own number, not BarFx.THIN: a 16-high plate and its target zoom stay simple.
BarFx.DAYBREAK_THIN = 18
-- The light is the bar's brighter color lifted toward warm white; the shade
-- stays black.
BarFx.DAYBREAK_LIFT = { 176 / 255, 171 / 255, 159 / 255 }
BarFx.DAYBREAK_MIX = 0.34

local M = DUI.MEDIA
local function sheet(phase, thin, left)
    return M .. "barfx-daybreak" .. phase .. (thin and "-thin" or "") .. (left and "-l" or "") .. ".png"
end

local function flipbook(group, tex, duration)
    local a = group:CreateAnimation("FlipBook")
    a:SetTarget(tex)
    a:SetDuration(duration)
    a:SetFlipBookRows(BarFx.DAYBREAK_FRAMES / BarFx.DAYBREAK_COLS)
    a:SetFlipBookColumns(BarFx.DAYBREAK_COLS)
    a:SetFlipBookFrames(BarFx.DAYBREAK_FRAMES)
    a:SetFlipBookFrameWidth(0)
    a:SetFlipBookFrameHeight(0)
    return a
end

-- Drops a reaction in flight. A flipbook that isn't playing draws its whole
-- sheet squashed into its spot, so the texture hides with it.
local function clearReaction(s, p)
    p.phase = nil
    p.shot:Stop()
    p.react:Hide()
end

local function show(s, p, on)
    local was = p.on
    p.on = on
    p.idle:SetShown(on)
    if on then
        -- Coming on, or the client stopped it (hidden, a loading screen): start
        -- over with nothing left of a reaction. A repaint keeps both going.
        if not was or not p.anim:IsPlaying() then
            clearReaction(s, p)
            p.anim:Stop()
            p.anim:Play()
        end
        p.anim:SetAnimationSpeedMultiplier(math.max(0.05, s.speed or 1))
    else
        p.anim:Stop()
        clearReaction(s, p)
    end
end

local function build(s)
    local bar = s.bar
    local p = {}
    p.idle = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FX_SUB - 1)
    p.react = bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FX_SUB)
    p.layers = { p.idle, p.react }
    for _, t in ipairs(p.layers) do
        t:SetBlendMode("BLEND")
        Style.FollowFill(bar, t)
    end
    p.react:Hide()
    p.anim = bar:CreateAnimationGroup()
    p.anim:SetLooping("REPEAT")
    flipbook(p.anim, p.idle, BarFx.DAYBREAK_LOOP)
    p.shot = bar:CreateAnimationGroup()
    p.shot:SetLooping("NONE")
    flipbook(p.shot, p.react, BarFx.DAYBREAK_REACT)
    p.shot:SetScript("OnFinished", function()
        -- A newer reaction started in its place keeps its texture.
        if not p.shot:IsPlaying() then
            p.phase = nil
            p.react:Hide()
        end
    end)
    -- The client stops a frame's animations while it's hidden: whatever was
    -- in flight belongs to that moment (and maybe another unit), so it goes.
    bar:HookScript("OnHide", function() if p.phase then clearReaction(s, p) end end)
    bar:HookScript("OnShow", function()
        if p.on and s.style == "daybreak" then
            p.anim:Stop()
            show(s, p, true)
        end
    end)
    return p
end

local function layout(s, p, w, h)
    local bar = s.bar
    local fill = bar:GetStatusBarTexture()
    local left = bar.GetReverseFill ~= nil and bar:GetReverseFill() == true
    local side = left and "LEFT" or "RIGHT"
    local _, cut, under = Style.GetFillAngle(bar)
    local thin = h <= BarFx.DAYBREAK_THIN
    local art = (thin and "thin" or "tall") .. side
    if p.art ~= art then
        -- The reaction in flight was drawn for the old shape or direction.
        if p.art and p.phase then clearReaction(s, p) end
        p.art, p.thin, p.left = art, thin, left
        -- CLAMP, or the client blends each edge with the far one.
        p.idle:SetTexture(sheet("", thin, left), "CLAMP", "CLAMP")
    end
    for _, t in ipairs(p.layers) do
        BarFx.Pin(t, fill, side, h * BarFx.DAYBREAK_SPAN)
        BarFx.Lean(t, side, cut or 0, under == true)
    end
end

-- The light's color: per channel, the brighter color lifted toward warm white.
local function lightOf(hi)
    local k, lift = BarFx.DAYBREAK_MIX, BarFx.DAYBREAK_LIFT
    return math.min(1, k * hi[1] + lift[1]), math.min(1, k * hi[2] + lift[2]), math.min(1, k * hi[3] + lift[3])
end
BarFx.DaybreakLight = lightOf

local function paint(s, p, lo, hi, alpha)
    -- The bar's own colors unknown (secret): the plain bar shows until they are.
    if not hi then return false end
    local fill = s.bar:GetStatusBarTexture()
    for _, t in ipairs(p.layers) do Style.SameMasks(t, fill, true) end
    local r, g, b = lightOf(hi)
    p.light = p.light or {}
    p.light[1], p.light[2], p.light[3] = r, g, b
    p.idle:SetVertexColor(r, g, b, alpha)
    -- A reaction keeps the strength it started with, in the new color.
    p.react:SetVertexColor(r, g, b, p.reactAlpha or alpha)
    if p.phase and not BarFx.Get(s, "react") then clearReaction(s, p) end
end

local function kick(s, p, dir, size)
    if not p.on or not p.art then return end
    p.shot:Stop()
    local phase = dir < 0 and "-hit" or "-heal"
    p.phase = phase
    p.react:SetTexture(sheet(phase, p.thin, p.left), "CLAMP", "CLAMP")
    local alpha = BarFx.Get(s, "strength") or 1
    p.reactAlpha = math.max(0, math.min(1, alpha * (size or 1)))
    local c = p.light or { 1, 1, 1 }
    p.react:SetVertexColor(c[1], c[2], c[3], p.reactAlpha)
    p.react:Show()
    p.shot:Play()
end

BarFx.Add("daybreak", function() return L["Daybreak"] end, {
    build = build, layout = layout, paint = paint, show = show, kick = kick,
    clearReaction = function(s, p) if p.phase then clearReaction(s, p) end end,
})
