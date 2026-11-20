-- Sample frames drawn inside another window. The setup guide shows your frame
-- and a target side by side so each choice can be seen without test mode.
-- Plain, non-secure frames, laid out from the current settings on each Refresh.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local UF, Pixel = ns.UF, DUI.Pixel

local Sample = {}
ns.Sample = Sample

Sample.GAP = 56     -- gap between the two frames' rings
Sample.UNITS = { "player", "target" }
-- Your sample's power, by class (anyone else: mana).
Sample.POWER = { WARRIOR = "RAGE", ROGUE = "ENERGY" }

Sample.YOU = { health = 80, healthValue = 2480, power = 65, powerValue = 2080, pvp = true }

function Sample.You()
    local s = UF.You("player", Sample.YOU, "WARRIOR")
    s.powerToken = Sample.POWER[s.class] or "MANA"
    local level = UnitLevel("player")
    if type(level) ~= "number" or isSecret(level) then level = 60 end
    s.level = level
    s.faction = UnitFactionGroup("player")
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
        foot = math.max(foot, f.foot or 0)   -- a style's power line
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

-- Two player samples side by side, one per portrait look, each named under it
-- (the "New portrait mode" question and the welcome). Both are the standard
-- player frame from the defaults, so the two looks compare on their own and
-- not on the player's profile; nothing is written and the real frames keep
-- their settings.
Sample.LOOKS = {
    { key = "socket", name = "2.0", line = "The border runs around both." },
    { key = "classic", name = "Classic", line = "The ring lies over the frame." },
}
Sample.LOOK_FRAME = 64    -- the room each sample frame gets, ring and name tab included
Sample.LOOK_GAP = 6

function Sample.Looks(parent)
    local Style = DUI.Style
    local L = DUI.L
    local box = CreateFrame("Frame", nil, parent)
    box.frames, box.names, box.lines = {}, {}, {}
    local spec
    for _, s in ipairs(ns.SPECS) do
        if s.unit == "player" then spec = s end
    end
    for _, look in ipairs(Sample.LOOKS) do
        local f = CreateFrame("Button", nil, box)
        UF.Build(f, spec)
        f:EnableMouse(false)
        box.frames[look.key] = f
        local name = Style.Text(box, Style.SIZE.body, "CENTER")
        name:SetText(L[look.name])
        box.names[look.key] = name
        local line = Style.Text(box, Style.SIZE.small, "CENTER")
        line:SetText(L[look.line])
        box.lines[look.key] = line
    end
    box.HEIGHT = Sample.LOOK_FRAME + Sample.LOOK_GAP + Style.SIZE.body + 4 + Style.SIZE.small + 2
    function box.Refresh(width) Sample.LayoutLooks(box, width) end
    return box
end

function Sample.LayoutLooks(box, width)
    local D = ns.DEFAULTS
    if not (D and ns.module) then return end
    local Style = DUI.Style
    width = (type(width) == "number" and width > 0) and width or 340
    box:SetSize(width, box.HEIGHT)
    local half = width / 2
    for i, look in ipairs(Sample.LOOKS) do
        local f = box.frames[look.key]
        local base, text = ns.ConfigFor(D, f.spec)
        local cfg = {}
        for k, v in pairs(base) do cfg[k] = v end
        cfg.portraitLook = look.key
        cfg.portraitAt = "frame"
        cfg.style = "daylight"
        f.iconStyle, f.classIcons = D.portraits.icons, D.portraits.classIcons
        f:SetScale(1)
        f:SetSize(2 * Pixel.Snap(f, cfg.width / 2), 2 * Pixel.Snap(f, cfg.height / 2))
        UF.Layout(f, cfg, text, true)
        -- The two looks are about the portrait: no PvP badge on them.
        local you = Sample.You()
        you.pvp = false
        f.test = you
        UF.ShowSample(f)
        -- Nor incoming heals or shields: their bars at the health's end can
        -- leave a sliver even at nothing, which reads as part of the look.
        for _, bar in ipairs({ f.heals, f.absorbs, f.overshield }) do
            if bar then
                bar:Hide()
                if bar.wedge then bar.wedge:Hide() end
            end
        end
        -- Shrink to the room: the bar and the ring past its end across, the
        -- ring (or the name tab over the bar) up and down.
        local reach = Sample.Reach(f)
        local p = f.portrait
        local tall = math.max(f:GetHeight() + 2 * ((f.tab and f.tab:IsShown()) and (f.tabHeight or UF.TAB_HEIGHT) or 0),
            (p and p:IsShown()) and p:GetHeight() or 0)
        local scale = math.min(1, (half - 16) / (f:GetWidth() + reach), Sample.LOOK_FRAME / tall)
        f:SetScale(scale)
        local mid = (i - 0.5) * half
        f:ClearAllPoints()
        f:SetPoint("CENTER", box, "TOPLEFT", (mid + reach / 2 * scale) / scale, -(Sample.LOOK_FRAME / 2) / scale)
        local name, line = box.names[look.key], box.lines[look.key]
        Style.InkText(name, "VALUE")
        Style.InkText(line, "LABEL")
        name:ClearAllPoints()
        name:SetPoint("TOP", box, "TOPLEFT", mid, -(Sample.LOOK_FRAME + Sample.LOOK_GAP))
        name:SetWidth(half - 8)
        line:ClearAllPoints()
        line:SetPoint("TOP", name, "BOTTOM", 0, -4)
        line:SetWidth(half - 8)
    end
end
