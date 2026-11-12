-- Sample frames drawn inside another window. The setup guide shows your frame
-- and a target side by side so each choice can be seen without test mode.
-- Plain, non-secure frames, laid out from the current settings on each Refresh.

local _, ns = ...
local DUI = DaylightUI
local UF, Pixel = ns.UF, DUI.Pixel

local Sample = {}
ns.Sample = Sample

Sample.GAP = 56     -- gap between the two frames' rings
Sample.UNITS = { "player", "target" }
-- Your sample's power, by class (anyone else: mana).
Sample.POWER = { WARRIOR = "RAGE", ROGUE = "ENERGY" }

Sample.YOU = { health = 80, healthValue = 2480, power = 65 }

function Sample.You()
    local s = UF.You("player", Sample.YOU, "WARRIOR")
    s.powerToken = Sample.POWER[s.class] or "MANA"
    local level = UnitLevel("player")
    if type(level) ~= "number" or (issecretvalue and issecretvalue(level)) then level = 60 end
    s.level = level
    return s
end

-- A box holding the two sample frames (box.frames.player and .target).
-- box.Refresh() redraws them from the settings. Size the box first.
function Sample.Pair(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.frames = {}
    for _, spec in ipairs(ns.SPECS) do
        for _, unit in ipairs(Sample.UNITS) do
            if spec.unit == unit then
                local f = CreateFrame("Button", nil, box)
                UF.Build(f, spec)
                f:EnableMouse(false)   -- display only, no clicks or tooltip
                box.frames[unit] = f
            end
        end
    end
    function box.Refresh() Sample.Layout(box) end
    return box
end

-- Apply the current paint settings now. The host window may redraw before the
-- module's own refresh, which waits until combat ends.
function Sample.UseSettings(db)
    ns.SwapSizes(db)   -- a new style's own heights
    UF.ConfigureColors(db.colors)
    UF.SLANT = tonumber(db.look and db.look.slant) or 0.21
end

-- How far a frame's portrait ring reaches out past its outer end.
function Sample.Reach(f)
    local p = f.portrait
    if not (p and p:IsShown()) then return 0 end
    return f.ringReach or 0   -- set by UF.LayoutPortrait in either style
end

function Sample.Layout(box)
    local db = ns.module and ns.module.db
    if not db then return end
    Sample.UseSettings(db)
    local width, tab, foot = Sample.GAP, 0, 0
    for _, unit in ipairs(Sample.UNITS) do
        local f = box.frames[unit]
        local cfg, text = ns.ConfigFor(db, f.spec)
        f.iconStyle, f.classIcons = db.portraits.icons, db.portraits.classIcons
        f:SetScale(1)
        f:SetSize(2 * Pixel.Snap(f, cfg.width / 2), 2 * Pixel.Snap(f, cfg.height / 2))
        UF.Layout(f, cfg, text, true)
        f.test = unit == "player" and Sample.You() or ns.Test.SAMPLES.target
        UF.ShowSample(f)
        width = width + f:GetWidth() + Sample.Reach(f)
        if f.tab and f.tab:IsShown() then tab = math.max(tab, f.tabHeight or UF.TAB_HEIGHT) end
        foot = math.max(foot, f.foot or 0)   -- Ribbon's power line
    end
    -- Big frames shrink together to fit the box. The pair is centered, counting
    -- the name tabs and Ribbon's lines.
    local room = box:GetWidth() or 0
    local scale = (room > 0 and width > room) and room / width or 1
    local you, them = box.frames.player, box.frames.target
    you:SetScale(scale)
    them:SetScale(scale)
    -- Offsets are in the frames' own scaled units.
    local dx, dy = Sample.GAP / 2 / scale, (foot - tab) / 2 / scale
    you:ClearAllPoints()
    you:SetPoint("RIGHT", box, "CENTER", -dx, dy)
    them:ClearAllPoints()
    them:SetPoint("LEFT", box, "CENTER", dx, dy)
end
