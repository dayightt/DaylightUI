-- The bar styles beyond Flow and Tide. Each is a few textures laid exactly over
-- the bar's fill, wearing the fill's own masks (its moving angled end, and the
-- bar's still ends through Style.ClipLike), so nothing shows outside it. What
-- moves is a flipbook sheet the game steps through (tools/make_barfx.py), so
-- no Lua runs while a bar sits there; a reaction to a hit or heal is one short
-- fade of a light. Nothing reads the bar's value.

local _, DUI = ...
local Style, BarFx, L = DUI.Style, DUI.BarFx, DUI.L
local M = DUI.MEDIA

BarFx.SHEET_FRAMES = 64   -- frames in each style sheet
local WHITE = BarFx.WHITE

local function sheet(name) return M .. "barfx-" .. name .. ".png" end

-- A texture over the fill, in the style's light layer.
local function layer(p, s, file, blend, sub)
    local t = s.bar:CreateTexture(nil, "ARTWORK", nil, sub or BarFx.FX_SUB)
    t:SetTexture(file, "CLAMP", "CLAMP")
    t:SetBlendMode(blend or "ADD")
    Style.FollowFill(s.bar, t)
    p.layers[#p.layers + 1] = t
    return t
end

-- A light at the fill's moving end, inside the fill; its width is set in layout.
local function edge(p, s, file)
    local t = layer(p, s, file)
    local fill = s.bar:GetStatusBarTexture()
    local side = (s.bar.GetReverseFill and s.bar:GetReverseFill()) and "LEFT" or "RIGHT"
    t:ClearAllPoints()
    t:SetPoint("TOP" .. side, fill, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, fill, "BOTTOM" .. side, 0, 0)
    if side == "LEFT" then t:SetTexCoord(1, 0, 0, 1) end
    t.side = side
    p.edges[#p.edges + 1] = t
    return t
end

local function book(p, t, seconds, frames)
    local a = p.anim:CreateAnimation("FlipBook")
    a:SetTarget(t)
    a:SetDuration(seconds)
    frames = frames or BarFx.SHEET_FRAMES
    a:SetFlipBookRows(frames)
    a:SetFlipBookColumns(1)
    a:SetFlipBookFrames(frames)
    a:SetFlipBookFrameWidth(0)
    a:SetFlipBookFrameHeight(0)
    return a
end

local function new(s)
    local p = { layers = {}, edges = {}, edgeW = {} }
    p.anim = s.bar:CreateAnimationGroup()
    p.anim:SetLooping("REPEAT")
    return p
end

local function lighten(c, k)
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

-- The two colors to light with; a fill whose colors can't be known (secret)
-- lights in the accent.
local function pair(lo, hi)
    if lo then return lo, hi end
    local a, b = Style.AccentPair()
    if a then return a, b end
    local r, g, bl = Style.Accent()
    return { r, g, bl }, { r, g, bl }
end

local function tint(t, c, alpha) t:SetVertexColor(c[1], c[2], c[3], alpha) end

-- The parts every style shares.
local function show(s, p, on)
    p.on = on
    for _, t in ipairs(p.layers) do t:SetShown(on) end
    if on then
        p.anim:Play()
        if p.anim.SetAnimationSpeedMultiplier then
            p.anim:SetAnimationSpeedMultiplier(math.max(0.05, s.speed or 1))
        end
    else
        p.anim:Stop()
    end
end

local function layout(s, p, w, h)
    for i, t in ipairs(p.edges) do t:SetWidth(math.max(2, h * (p.edgeW[i] or 1.4))) end
    if p.tail then p.tail:SetWidth(math.max(4, w * 0.35)) end
end

local function clip(s, p)
    local fill = s.bar:GetStatusBarTexture()
    for _, t in ipairs(p.layers) do Style.SameMasks(t, fill) end
end

-- A hit or a heal: the flare light brightens and fades. A short Lua fade, only then.
local function flare(s, p, dir, size)
    local t = p.flare
    if not t then return end
    local Motion = DUI.Motion
    t:SetAlpha(math.min(1, 0.55 * size))
    t:Show()
    if Motion and Motion.AlphaTo then Motion.AlphaTo(t, 0, Motion.SLOW) else t:SetAlpha(0) end
end

local function withFlare(p, s)
    p.flare = edge(p, s, M .. "glow.png")
    p.edgeW[#p.edges] = 2.2
    p.flare:SetAlpha(0)
end

local function restart(s, p, key)
    -- The game stops a frame's animations while it's hidden: start again on show.
    s.bar:HookScript("OnShow", function()
        if p.on and s.style == key and not p.anim:IsPlaying() then show(s, p, true) end
    end)
end

local function def(key, d)
    d.show = d.show or show
    d.layout = d.layout or layout
    local build = d.build
    d.build = function(s)
        local p = new(s)
        build(s, p)
        restart(s, p, key)
        return p
    end
    local paint = d.paint
    d.paint = function(s, p, lo, hi, alpha)
        clip(s, p)
        lo, hi = pair(lo, hi)
        return paint(s, p, lo, hi, alpha)
    end
    return d
end

-- A lit head riding the fill's end with a soft tail behind it; it flares on
-- a hit or heal.
BarFx.Add("comet", L["Comet"], def("comet", {
    build = function(s, p)
        p.tail = edge(p, s, WHITE)
        p.head = edge(p, s, sheet("breathe"))
        p.edgeW[#p.edges] = 1.6
        book(p, p.head, 1.6)
        withFlare(p, s)
    end,
    paint = function(s, p, lo, hi, alpha)
        local c = lighten(hi, 0.6)
        local back = p.tail.side == "LEFT"
        local clear, lit = CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], 0.5 * alpha)
        p.tail:SetVertexColor(1, 1, 1, 1)
        p.tail:SetGradient("HORIZONTAL", back and lit or clear, back and clear or lit)
        tint(p.head, lighten(hi, 0.75), alpha)
        tint(p.flare, lighten(hi, 0.8), 1)
    end,
    kick = flare,
}))

-- Warm sparks rising off the fill and a glowing end; it flares on a hit or heal.
BarFx.EMBER = { 1, 0.62, 0.28 }
BarFx.Add("embers", L["Embers"], def("embers", {
    build = function(s, p)
        p.sparks = layer(p, s, sheet("embers"))
        book(p, p.sparks, 2.6)
        p.coal = edge(p, s, sheet("breathe"))
        p.edgeW[#p.edges] = 1.4
        book(p, p.coal, 2.2)
        withFlare(p, s)
    end,
    paint = function(s, p, lo, hi, alpha)
        local warm = { (hi[1] + BarFx.EMBER[1]) / 2, (hi[2] + BarFx.EMBER[2]) / 2, (hi[3] + BarFx.EMBER[3]) / 2 }
        tint(p.sparks, lighten(warm, 0.3), alpha)
        tint(p.coal, warm, 0.85 * alpha)
        tint(p.flare, lighten(warm, 0.4), 1)
    end,
    kick = flare,
}))

-- By power type: the style that suits each power.
BarFx.AUTO.RAGE = "embers"

-- Styles there once, now gone: a frame still set to one shows Flow.
for _, key in ipairs({ "silk", "prism", "aurora", "stars", "liquid", "heart", "storm" }) do BarFx.RETIRED[key] = "flow" end
