-- The fight pill: in a fight (and under the client's restrictions) a unit's
-- tooltip is one small line by the cursor: the name (a player's in their
-- class color, a creature's with "· on you" when it's on you), their health,
-- and a thin bar. The game's tooltip stays up but out of sight (muted), so
-- Shift brings the full card back at once. Fixed in size: nothing in it is
-- measured, so secret names and health are fine.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local Pill = {}
ns.RichPill = Pill

Pill.W, Pill.CUT, Pill.BAR_H = 200, 8, 4
Pill.PAD_X, Pill.PAD_TOP, Pill.PAD_BOTTOM, Pill.BAR_GAP = 12, 7, 9, 5
Pill.CURSOR_X, Pill.CURSOR_Y = 22, -20 -- its top-left from the cursor's tip, clear of the arrow
Pill.FADE = 0.35 -- out, once the creature it shows is no longer under the mouse

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

-- pill = "combat" (in a fight and under restrictions), "always" or "never";
-- Shift shows the full card any time.
function Pill.Wanted(tip, unit)
    local Tip = ns.Tooltip
    local cfg = Tip.Config()
    local mode = cfg and cfg.pill or "combat"
    if mode == "never" or type(unit) ~= "string" or IsShiftKeyDown() then return false end
    -- Hidden in combat by its own switch: that wins.
    if Tip.HideNow(tip) then return false end
    if mode == "always" then return true end
    return InCombatLockdown() or DUI.Restricted()
end

local function lineHeight() return Style.SIZE.body + ns.RichPanel.LINE_EXTRA end

function Pill.Frame()
    local f = Pill.frame
    if f then return f end
    f = CreateFrame("Frame", "DaylightUITooltipPill", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:Hide()
    f.shell = Style.Shell(f, { borderPx = ns.RichPanel.BORDER, cornerPx = 0, noBevel = true,
        bgAlpha = ns.Tooltip.BackAlpha("rich") })
    Style.CutShell(f, Pill.CUT)
    f.light = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.light:SetTexture("Interface\\Buttons\\WHITE8X8")
    local font = ns.MEDIA and ns.MEDIA.font
    f.name = Style.Text(f, Style.SIZE.body, "LEFT", font)
    f.name:SetWordWrap(false)
    f.on = Style.Text(f, Style.SIZE.body, "LEFT", font)
    f.on:SetWordWrap(false)
    Style.InkText(f.on, "LABEL")
    f.pct = Style.Text(f, Style.SIZE.body, "RIGHT", font)
    f.pct:SetWordWrap(false)
    Style.InkText(f.pct, "VALUE")
    f.bar = ns.RichPanel.MakeBar(f)
    Style.AngleFill(f.bar, "right", 3)
    Pill.frame = f
    Pill.Layout()
    return f
end

function Pill.Layout()
    local f = Pill.frame
    if not f then return end
    local cfg = ns.Tooltip.Config()
    f:SetScale((tonumber(cfg and cfg.scale) or 1) * DUI.Movers.Scale() * ns.RichPanel.Scale())
    local h = Pill.PAD_TOP + lineHeight() + Pill.BAR_GAP + Pill.BAR_H + Pill.PAD_BOTTOM
    f:SetSize(Pill.W, h)
    local one = DUI.Pixel.Px(f, 1)
    f.light:ClearAllPoints()
    f.light:SetPoint("TOPLEFT", f, "TOPLEFT", one, -one)
    f.light:SetPoint("TOPRIGHT", f, "TOPRIGHT", -one, -one)
    f.light:SetHeight(ns.RichPanel.LIGHT_H)
    f.pct:ClearAllPoints()
    f.pct:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Pill.PAD_X, -Pill.PAD_TOP)
    f.name:ClearAllPoints()
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", Pill.PAD_X, -Pill.PAD_TOP)
    f.on:ClearAllPoints()
    f.on:SetPoint("LEFT", f.name, "RIGHT", 4, 0)
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", Pill.PAD_X, -(Pill.PAD_TOP + lineHeight() + Pill.BAR_GAP))
    f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Pill.PAD_X, -(Pill.PAD_TOP + lineHeight() + Pill.BAR_GAP))
    f.bar:SetHeight(Pill.BAR_H)
    f.bar.edge:ClearAllPoints()
    f.bar.edge:SetPoint("TOPLEFT", f.bar, "TOPLEFT", -one, one)
    f.bar.edge:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", one, -one)
    f.shell.opts.bgAlpha = ns.Tooltip.BackAlpha("rich")
    Style.LayoutShell(f.shell)
end

local function paintLight(tex, pair)
    if not pair then
        local lo, hi = Style.AccentPair()
        if not lo then
            local r, g, b = Style.Accent()
            lo, hi = DUI.Gradients.PairFrom({ r, g, b })
        end
        pair = { lo, hi }
    end
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetGradient("HORIZONTAL", CreateColor(pair[2][1], pair[2][2], pair[2][3], 1),
        CreateColor(pair[1][1], pair[1][2], pair[1][3], 1))
end

-- Its words and bar for a unit. A player: class-colored name, the bar by
-- health; a creature: white name, "· on you" when it targets you, the bar in
-- its reaction's pair.
function Pill.Fill(unit)
    local f = Pill.Frame()
    local Tip = ns.Tooltip
    local player = plain(UnitIsPlayer(unit)) == true
    f.name:SetText(DUI.UnitName(unit, "tooltip"))
    local r, g, b
    if player then r, g, b = Tip.UnitColor(unit) end
    if r then
        f.name:SetTextColor(r, g, b)
    elseif player and DUI.Gradients and type(DUI.Gradients.HiddenClassID(unit)) ~= "nil" then
        -- A class the game hides (battlegrounds): its color as the client gives it.
        f.name:SetTextColor(DUI.Gradients.HiddenClassColor(unit))
    else
        Style.InkText(f.name, "TITLE")
    end
    local onYou = not player and plain(UnitIsUnit(unit .. "target", "player")) == true
    f.on:SetText(onYou and ("· " .. L["on you"]) or "")
    f.on:SetShown(onYou)
    local pair = ns.RichPlayers.ClassPair(unit)
    paintLight(f.light, pair)
    f.barPair = (not player) and pair or nil
    ns.RichPanel.PaintBar(f.bar, { unit = unit, health = true, pair = f.barPair })
    DUI.Health.Write(f.pct, "percent", unit, true)
end

function Pill.Place()
    local f = Pill.frame
    if not f then return end
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    if type(x) ~= "number" or type(s) ~= "number" or s <= 0 then return end
    x, y = x / s + Pill.CURSOR_X, y / s + Pill.CURSOR_Y
    if f.at and math.abs(f.at[1] - x) < 0.01 and math.abs(f.at[2] - y) < 0.01 then return end
    f.at = { x, y }
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

-- Shown at once (a fight never waits for a fade), the tooltip muted.
function Pill.Show(tip, unit)
    local f = Pill.Frame()
    Pill.Fill(unit)
    f.next = GetTime() + ns.Rich.BAR_EVERY
    f.leaving = nil
    -- Snapped back in, any fade out still running stopped.
    if DUI.Motion then DUI.Motion.AlphaTo(f, 1, 0) end
    f:SetAlpha(1)
    f:Show()
    Pill.Place()
    ns.Tooltip.Mute(tip, "pill")
end

-- Each frame while it shows: follows the cursor, health kept live, and it
-- fades out once the creature under the mouse is gone.
function Pill.Step(tip, unit)
    local f = Pill.frame
    if not (f and f:IsShown()) then return end
    Pill.Place()
    local now = GetTime()
    if now >= (f.next or 0) and not f.leaving then
        f.next = now + ns.Rich.BAR_EVERY
        ns.RichPanel.PaintBar(f.bar, { unit = unit, health = true, pair = f.barPair })
        DUI.Health.Write(f.pct, "percent", unit, true)
    end
    if unit == "mouseover" and not f.leaving and plain(UnitExists("mouseover")) == false then
        f.leaving = true
        if DUI.Motion and DUI.Motion.On() then DUI.Motion.AlphaTo(f, 0, Pill.FADE, true) else f:Hide() end
    end
end

function Pill.Hide()
    local f = Pill.frame
    if f then
        f.leaving, f.at = nil, nil
        f:Hide()
    end
end
