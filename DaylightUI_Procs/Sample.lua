-- The live preview at the top of the Proc Alerts page: the picked proc's flare
-- as it would light up around your character, redrawn with every change.
-- The flare is built the same way as the real one (Flares.lua), on its own
-- frame, so it never takes a lane or plays a sound.

local _, ns = ...
local DUI = DaylightUI

local Sample = {}
ns.Sample = Sample

Sample.STAGE = 640   -- the holder's size: the real flare's places, scaled to fit

local function loops(part, anim)
    if anim == "breathe" or anim == "flash" then return part.breathe end
    if anim == "pulse" then return part.pulse end
    if anim == "impact" then return part.impact end
end

function Sample.New(parent)
    local s = { hint = DUI.L["The picked alert, as it lights up around your character."] }
    local f = CreateFrame("Frame", nil, parent)
    s.frame = f
    local stage = CreateFrame("Frame", nil, f)
    stage:SetSize(Sample.STAGE, Sample.STAGE)
    stage:SetPoint("CENTER", f, "CENTER", 0, 0)
    local flare = { rel = stage, lane = 0, frac = 1, dim = 1, boost = 1 }
    flare.parts = { ns.Flares.NewPart(stage), ns.Flares.NewPart(stage) }
    s.flare = flare

    function s.Refresh(width, maxHeight)
        local key = ns.Options.Selected()
        local p = ns.Data.BY[key]
        if not p then return 0 end
        local design = ns.Alerts.Get(key, "design")
        local d = ns.Data.DESIGNS[design]
        flare.key, flare.design, flare.spot = key, design, d and d.spot or "side"
        ns.Flares.Layout(flare, 1)
        ns.Flares.Paint(flare)
        stage:SetAlpha(ns.Flares.Opacity(key))
        -- Its loop, kept running across redraws so a slider drag doesn't stutter.
        local anim = DUI.Motion.On() and ns.Alerts.Get(key, "anim") or "still"
        for _, part in ipairs(flare.parts) do
            local g = part.frame:IsShown() and loops(part, anim)
            for _, other in ipairs({ part.breathe, part.pulse, part.impact }) do
                if other ~= g then other:Stop() end
            end
            if g and not g:IsPlaying() then g:Play() end
        end
        local h = math.min(maxHeight or 220, 220)
        local k = h / Sample.STAGE
        stage:SetScale(k)
        f:SetSize(width or 300, h)
        return h
    end

    function s.Parts() return {} end

    return s
end
