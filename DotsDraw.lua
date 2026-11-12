-- Draws the damage your DoTs still have left to do on a health bar (data from
-- Dots.lua). Nothing here compares health; the client's StatusBars do it.
--
-- The veil is a bar the client fills from the unit's max health (secret on
-- every mob) and the damage left. It hangs off the health fill's moving edge
-- and covers the part of the fill the DoTs will still take. It sits in a
-- clipping frame the size of the health bar, so a lethal amount stops at the
-- bar's start.
--
-- The skull uses Does It Die's trick: a 10000 px bar filled with the damage
-- left out of current health (secret), inside a window as wide as the skull.
-- The skull rides the end of that fill, so it only enters the window once
-- the damage reaches the health. It pops in instead of fading because there's
-- no way to know when it becomes visible.

local _, DUI = ...
local Dots = DUI.Dots
local Style = DUI.Style

local WHITE = "Interface\\Buttons\\WHITE8x8"
Dots.TINT = { 0, 0, 0, 0.45 } -- the veil, a soft darker shade
Dots.SKULL_COLOR = { 0.92, 0.36, 0.3 } -- warm red, so it never looks like the raid marker's white skull
Dots.SKULL_BAR = 10000
-- The dark line where the damage stops. Kept soft so it reads as the end of
-- the shade rather than a mark on the bar; a hard near-black line looked like
-- a glitch.
local EDGE_ALPHA = 0.55
local EDGE_PX = 2

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- The veil color: the unit frames' Colors page pick, else the default.
function Dots.Tint()
    local c = DUI:Get("UnitFrames", "colors.dotTint")
    return type(c) == "table" and c or Dots.TINT
end

function Dots.TintVeil(veil, c)
    c = type(c) == "table" and c or Dots.TINT
    veil.bar:SetStatusBarColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or Dots.TINT[4])
end

-- A hidden veil over bar. veil.bar is the client's bar, veil.edge the line.
function Dots.NewVeil(bar, level)
    local veil = CreateFrame("Frame", nil, bar)
    veil:SetAllPoints(bar)
    veil:SetClipsChildren(true)
    veil:SetFrameLevel(bar:GetFrameLevel() + (level or 1))
    local v = CreateFrame("StatusBar", nil, veil)
    v:SetStatusBarTexture(WHITE)
    v:SetMinMaxValues(0, 1)
    v:SetValue(0)
    veil.bar = v
    veil.edge = v:CreateTexture(nil, "OVERLAY")
    veil.edge:SetColorTexture(0, 0, 0, EDGE_ALPHA)
    Dots.TintVeil(veil, Dots.TINT)
    veil:Hide()
    return veil
end

-- Hangs the veil off bar's moving edge (growLeft = fill grows leftward), as
-- wide as the bar and growing back into the fill. It shares the fill's angled
-- edge mask so it ends exactly where the fill does. Its other end, where the
-- damage stops, is cut at the same angle (the dark line leans with it) so the
-- band keeps parallel sides.
function Dots.LayoutVeil(veil, bar, growLeft)
    local v = veil.bar
    local lead = growLeft and "LEFT" or "RIGHT"
    local back = growLeft and "RIGHT" or "LEFT"
    local fill = bar:GetStatusBarTexture()
    v:ClearAllPoints()
    v:SetPoint("TOP" .. lead, fill, "TOP" .. lead, 0, 0)
    v:SetPoint("BOTTOM" .. lead, fill, "BOTTOM" .. lead, 0, 0)
    v:SetWidth(math.max(bar:GetWidth(), 1))
    v:SetReverseFill(not growLeft)
    local tex = v:GetStatusBarTexture()
    local side, cut = Style.GetFillAngle(bar)
    local m = side and Style.GetFillMask(bar) or nil
    if veil.mask ~= m then
        if veil.mask then tex:RemoveMaskTexture(veil.mask) end
        if m then tex:AddMaskTexture(m) end
        veil.mask = m
    end
    local e = veil.edge
    e:ClearAllPoints()
    e:SetPoint("TOP", tex, "TOP" .. back, 0, 0)
    e:SetPoint("BOTTOM", tex, "BOTTOM" .. back, 0, 0)
    e:SetWidth(DUI.Pixel.Px(bar, EDGE_PX))
    Style.AngleTrail(v, side, cut)
    -- Vertex 1 is upper left, 3 upper right. Shift the line's top out along the
    -- cut the way the trail mask runs (a quarter of its width at the top).
    if e.SetVertexOffset then
        local lean = side == "right" and cut or side == "left" and -cut or 0
        pcall(e.SetVertexOffset, e, 1, lean, 0)
        pcall(e.SetVertexOffset, e, 3, lean, 0)
    end
end

-- A hidden skull window on parent. The caller positions it.
function Dots.NewSkull(parent, size)
    local skull = CreateFrame("Frame", nil, parent)
    skull:SetClipsChildren(true)
    local b = CreateFrame("StatusBar", nil, skull)
    b:SetPoint("RIGHT", skull, "RIGHT", 0, 0)
    b:SetStatusBarTexture(WHITE)
    b:SetStatusBarColor(0, 0, 0, 0)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(DUI.MEDIA .. "kill-skull.png")
    local c = Dots.SKULL_COLOR
    icon:SetVertexColor(c[1], c[2], c[3], 1)
    icon:SetPoint("RIGHT", b:GetStatusBarTexture(), "RIGHT", 0, 0)
    skull.bar, skull.icon = b, icon
    Dots.SizeSkull(skull, size)
    skull:Hide()
    return skull
end

function Dots.SizeSkull(skull, size)
    skull:SetSize(size, size)
    skull.bar:SetSize(Dots.SKULL_BAR, size)
    skull.icon:SetSize(size, size)
end

local function dead(unit)
    local ok, d = pcall(UnitIsDead, unit)
    return ok and not isSecret(d) and d == true
end

-- Draws unit's DoTs on a veil and a skull (either may be nil). Health and max
-- health go to the bars unchanged since they may be secret. Returns whether
-- anything shows.
function Dots.Paint(unit, veil, skull)
    local left = unit and not dead(unit) and Dots.Left(unit)
    if not left then
        if veil then veil:Hide() end
        if skull then skull:Hide() end
        return false
    end
    if veil then
        veil.bar:SetMinMaxValues(0, UnitHealthMax(unit))
        veil.bar:SetValue(left)
        veil:Show()
    end
    if skull then
        skull.bar:SetMinMaxValues(0, UnitHealth(unit))
        skull.bar:SetValue(left)
        skull:Show()
    end
    return true
end

-- A sample for test mode and option previews, from plain numbers. lethal fills the skull.
function Dots.PaintSample(veil, skull, max, left, lethal)
    if veil then
        veil.bar:SetMinMaxValues(0, max)
        veil.bar:SetValue(left)
        veil:Show()
    end
    if skull then
        skull.bar:SetMinMaxValues(0, 1)
        skull.bar:SetValue(lethal and 1 or 0)
        skull:SetShown(lethal == true)
    end
end
