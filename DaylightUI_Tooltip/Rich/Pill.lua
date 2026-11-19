-- The fight pill: in a fight (and under the client's restrictions) a unit's
-- tooltip is one small line where the tooltip would be: the name (a player's in their
-- class color, a creature's with "· on you" when it's on you), their health,
-- and a thin bar. The game's tooltip stays up but out of sight (muted), so
-- Shift brings the full card back at once. Fixed in size: nothing in it is
-- measured, so secret names and health are fine.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret

local Pill = {}
ns.RichPill = Pill

Pill.W, Pill.CUT, Pill.BAR_H = 200, 8, 4
Pill.PAD_X, Pill.PAD_TOP, Pill.PAD_BOTTOM, Pill.BAR_GAP = 12, 7, 9, 5
Pill.CURSOR_X, Pill.CURSOR_Y = 22, -20 -- its top-left from the cursor's tip, clear of the arrow

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

-- The key that shows the full card while held (pillKey), or none.
Pill.KEYS = { shift = "IsShiftKeyDown", ctrl = "IsControlKeyDown", alt = "IsAltKeyDown" }
function Pill.KeyHeld(cfg)
    local fn = _G[Pill.KEYS[cfg and cfg.pillKey or "shift"] or ""]
    return type(fn) == "function" and fn() == true
end

-- pill = "combat" (in a fight and under restrictions), "always" or "never";
-- holding pillKey shows the full card any time.
function Pill.Wanted(tip, unit)
    local Tip = ns.Tooltip
    local cfg = Tip.Config()
    local mode = cfg and cfg.pill or "combat"
    if mode == "never" or type(unit) ~= "string" or Pill.KeyHeld(cfg) then return false end
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
    -- Measures how wide the health can get ("100%"): the health itself is
    -- secret and can't be measured.
    f.room = Style.Text(f, Style.SIZE.body, "RIGHT", font)
    f.room:SetText("100%")
    f.room:SetAlpha(0)
    f.pct = Style.Text(f, Style.SIZE.body, "RIGHT", font)
    f.pct:SetWordWrap(false)
    Style.InkText(f.pct, "VALUE")
    f.bar = ns.RichPanel.MakeBar(f)
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
    f.room:ClearAllPoints()
    f.room:SetPoint("TOPRIGHT", f.pct, "TOPRIGHT", 0, 0)
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", Pill.PAD_X, -(Pill.PAD_TOP + lineHeight() + Pill.BAR_GAP))
    f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Pill.PAD_X, -(Pill.PAD_TOP + lineHeight() + Pill.BAR_GAP))
    ns.RichPanel.ShapeBar(f.bar, Pill.BAR_H)
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
-- health; a creature: its name in its reaction's color (hostile red, neutral
-- yellow, friendly green), the bar in that pair. The name is cut short with "..." before it can
-- reach the health.
Pill.NAME_GAP = 8
function Pill.Fill(unit)
    local f = Pill.Frame()
    local Tip = ns.Tooltip
    local player = plain(UnitIsPlayer(unit)) == true
    local name = DUI.UnitName(unit, "tooltip")
    f.name:SetText(name)
    local room = f.room:GetStringWidth()
    if isSecret(room) or type(room) ~= "number" then room = 30 end
    local most = Pill.W - 2 * Pill.PAD_X - room - Pill.NAME_GAP
    if isSecret(name) then
        f.name:SetWidth(most)
    else
        local w = f.name:GetStringWidth()
        f.name:SetWidth((type(w) == "number" and not isSecret(w) and w > most) and most or 0)
    end
    local r, g, b = Tip.UnitColor(unit)
    if r then
        f.name:SetTextColor(r, g, b)
    elseif player and DUI.Gradients and type(DUI.Gradients.HiddenClassID(unit)) ~= "nil" then
        -- A class the game hides (battlegrounds): its color as the client gives it.
        f.name:SetTextColor(DUI.Gradients.HiddenClassColor(unit))
    else
        Style.InkText(f.name, "TITLE")
    end
    local pair = ns.RichPlayers.ClassPair(unit)
    paintLight(f.light, pair)
    f.barPair = (not player) and pair or nil
    ns.RichPanel.PaintBar(f.bar, { unit = unit, health = true, pair = f.barPair })
    DUI.Health.Write(f.pct, "percent", unit, true)
end

-- Where the tooltip would be, by the Tooltip position setting: at the cursor,
-- at Daylight UI's tooltip spot growing from its corner, or where the tooltip's
-- owner put it.
function Pill.Place(tip)
    local f = Pill.frame
    if not f then return end
    local where, corner = ns.Tooltip.PillSpot(tip or GameTooltip)
    if where ~= "cursor" then
        local rel = where == "handle" and ns.Tooltip.anchor or (tip or GameTooltip)
        local point = where == "handle" and corner or "TOPLEFT"
        if f.at and f.at[1] == rel and f.at[2] == point then return end
        f.at = { rel, point }
        f:ClearAllPoints()
        f:SetPoint(point, rel, point, 0, 0)
        return
    end
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    if type(x) ~= "number" or type(s) ~= "number" or s <= 0 then return end
    x, y = x / s + Pill.CURSOR_X, y / s + Pill.CURSOR_Y
    local at = f.at
    if at and type(at[1]) == "number" and math.abs(at[1] - x) < 0.01 and math.abs(at[2] - y) < 0.01 then return end
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
    Pill.Place(tip)
    ns.Tooltip.Mute(tip, "pill")
end

-- Each frame while it shows: kept in place (the cursor moves), health kept live, and it
-- fades out once the creature under the mouse is gone.
function Pill.Step(tip, unit)
    local f = Pill.frame
    if not (f and f:IsShown()) then return end
    Pill.Place(tip)
    local now = GetTime()
    if now >= (f.next or 0) and not f.leaving then
        f.next = now + ns.Rich.BAR_EVERY
        ns.RichPanel.PaintBar(f.bar, { unit = unit, health = true, pair = f.barPair })
        DUI.Health.Write(f.pct, "percent", unit, true)
    end
    if not f.leaving and plain(UnitExists(unit)) == false then Pill.Leave() end
end

-- The mouse left it (Tip.OnWorldCursor, or its unit is gone). As world
-- tooltips do by the "Fade out world tooltips" switch: gone at once, or a
-- short fade.
function Pill.Leave()
    local f = Pill.frame
    if not (f and f:IsShown()) or f.leaving then return end
    f.leaving = true
    local M, cfg = DUI.Motion, ns.Tooltip.Config()
    if cfg and cfg.fadeOut and M and M.On() then M.AlphaTo(f, 0, M.SLOW, true) else f:Hide() end
end

function Pill.Hide()
    local f = Pill.frame
    if f then
        f.leaving, f.at = nil, nil
        f:Hide()
    end
end
