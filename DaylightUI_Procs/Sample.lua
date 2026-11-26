-- The live preview at the top of the Proc Alerts page: the picked proc's flare
-- as it would light up around your character, redrawn with every change.
-- The flare is built the same way as the real one (Flares.lua), on its own
-- frame, so it never takes a lane or plays a sound.

local _, ns = ...
local DUI = DaylightUI

local Sample = {}
ns.Sample = Sample

Sample.STAGE = 640   -- the holder's size: the real flare's places, scaled to fit

function Sample.New(parent)
    local s = { hint = DUI.L["The picked alert, as it lights up around your character."] }
    local f = CreateFrame("Frame", nil, parent)
    s.frame = f
    local stage = CreateFrame("Frame", nil, f)
    stage:SetSize(Sample.STAGE, Sample.STAGE)
    stage:SetPoint("CENTER", f, "CENTER", 0, 0)
    local flare = { rel = stage, lane = 0, frac = 1, dim = 1 }
    flare.parts = { ns.Flares.NewPart(stage), ns.Flares.NewPart(stage) }
    flare.burst = ns.Flares.NewBurst(stage)
    s.flare = flare
    -- The client stops its loops while the options window is closed.
    stage:SetScript("OnShow", function()
        if flare.key then ns.Flares.PlayLoops(flare, flare.anim) end
    end)

    function s.Refresh(width, maxHeight)
        local key = ns.Options.Selected()
        local p = ns.Data.BY[key]
        if not p then return 0 end
        local design = ns.Alerts.Get(key, "design")
        local d = ns.Data.DESIGNS[design]
        flare.key, flare.design, flare.spot = key, design, d and d.spot or "side"
        flare.anim = ns.Alerts.Get(key, "anim")
        ns.Flares.Layout(flare, 1)
        ns.Flares.Paint(flare)
        stage:SetAlpha(ns.Flares.Opacity(key))
        -- Its loops, kept running across redraws so a slider drag doesn't stutter.
        ns.Flares.PlayLoops(flare, flare.anim)
        local h = math.min(maxHeight or 220, 220)
        local k = h / Sample.STAGE
        stage:SetScale(k)
        f:SetSize(width or 300, h)
        return h
    end

    function s.Parts() return {} end

    return s
end

-- The welcome's On and Off pair (InstallerLooks.lua): your portrait in the
-- middle of each, and in the On one a proc of your class lit around it as it
-- would be in play. Same shape as the other look previews: frames, names and
-- lines per key, HEIGHT, Refresh(width).
Sample.LOOK_H = 220       -- the drawing's height
Sample.LOOK_GAP = 14      -- between the drawing and its name
Sample.PORTRAIT = 150     -- your portrait, in the flare's own units (the holder is 640)
Sample.LOOKS = {
    { key = "on", name = DUI.L["On"], line = DUI.L["A flare around you when a proc is ready."] },
    { key = "off", name = DUI.L["Off"], line = DUI.L["No flares, as before."] },
}

-- The proc to show: your class's first one that's on and lights both your
-- sides, since that reads best at this size; else your first one.
function Sample.Pick()
    local first
    for _, p in ipairs(ns.Data.Mine()) do
        if ns.Alerts.Get(p.key, "enabled") ~= false then
            local d = ns.Data.DESIGNS[ns.Alerts.Get(p.key, "design")]
            if d and d.spot == "side" then return p.key end
            first = first or p.key
        end
    end
    return first or (ns.Data.PROCS[1] and ns.Data.PROCS[1].key)
end

function Sample.Looks(parent)
    local Style = DUI.Style
    local box = CreateFrame("Frame", nil, parent)
    box.frames, box.names, box.lines, box.stages = {}, {}, {}, {}
    for _, look in ipairs(Sample.LOOKS) do
        local f = CreateFrame("Frame", nil, box)
        local stage = CreateFrame("Frame", nil, f)
        stage:SetSize(Sample.STAGE, Sample.STAGE)
        stage:SetPoint("CENTER", f, "CENTER", 0, 0)
        stage.portrait = stage:CreateTexture(nil, "BACKGROUND")
        stage.portrait:SetSize(Sample.PORTRAIT, Sample.PORTRAIT)
        stage.portrait:SetPoint("CENTER", stage, "CENTER", 0, 0)
        if look.key == "on" then
            stage.flare = { rel = stage, lane = 0, frac = 1, dim = 1 }
            stage.flare.parts = { ns.Flares.NewPart(stage), ns.Flares.NewPart(stage) }
            local flare = stage.flare
            stage:SetScript("OnShow", function()
                if flare.key then ns.Flares.PlayLoops(flare, flare.anim) end
            end)
        end
        box.stages[look.key] = stage
        box.frames[look.key] = f
        box.names[look.key] = Style.Text(box, Style.SIZE.body, "CENTER")
        box.names[look.key]:SetText(look.name)
        box.lines[look.key] = Style.Text(box, Style.SIZE.small, "CENTER")
        box.lines[look.key]:SetText(look.line)
    end
    box.HEIGHT = Sample.LOOK_H + Sample.LOOK_GAP + Style.SIZE.body + 4 + Style.SIZE.small + 2

    function box.Refresh(width)
        width = (type(width) == "number" and width > 0) and width or 460
        box:SetSize(width, box.HEIGHT)
        local half = width / 2
        local key = Sample.Pick()
        for i, look in ipairs(Sample.LOOKS) do
            local f, stage, mid = box.frames[look.key], box.stages[look.key], (i - 0.5) * half
            local fw = half - 32
            f:SetSize(fw, Sample.LOOK_H)
            f:ClearAllPoints()
            f:SetPoint("TOP", box, "TOPLEFT", mid, 0)
            -- The whole holder fits the drawing, so every design's spot shows.
            stage:SetScale(math.min(fw, Sample.LOOK_H * 1.5) / Sample.STAGE)
            DUI.SafeCall(SetPortraitTexture, stage.portrait, "player")
            local flare = stage.flare
            if flare and key then
                local design = ns.Alerts.Get(key, "design")
                local d = ns.Data.DESIGNS[design]
                flare.key, flare.design, flare.spot = key, design, d and d.spot or "side"
                flare.anim = ns.Alerts.Get(key, "anim")
                ns.Flares.Layout(flare, 1)
                ns.Flares.Paint(flare)
                ns.Flares.PlayLoops(flare, flare.anim)
            end
            local name, line = box.names[look.key], box.lines[look.key]
            Style.InkText(name, "VALUE")
            Style.InkText(line, "LABEL")
            name:ClearAllPoints()
            name:SetPoint("TOP", box, "TOPLEFT", mid, -(Sample.LOOK_H + Sample.LOOK_GAP))
            name:SetWidth(half - 8)
            line:ClearAllPoints()
            line:SetPoint("TOP", name, "BOTTOM", 0, -4)
            line:SetWidth(half - 8)
        end
    end
    return box
end
