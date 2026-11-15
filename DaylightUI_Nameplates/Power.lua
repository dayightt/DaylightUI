-- Power bar on a plate: mana, rage or energy as a thin bar just under the health
-- bar, continuing its angled end (like the cast bar). The cast bar and combo
-- points drop below it. Off by default. powerShow picks who gets one: players and
-- mana users, everything with power, or your target only.
-- Power values are secret in combat and under the client's restrictions, so they
-- go straight into the bar (SetMinMaxValues/SetValue accept secrets) and are
-- never read or compared. Power events are only registered while the bar shows.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Power = {}
ns.Power = Power

Power.HEIGHT = 5 -- default bar height
Power.GAP = 2 -- default gap under the health bar
Power.EVENTS = { UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true }
Power.MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
Power.SHOW = { players = "Players and mana users", all = "Everyone with power", target = "Your target only" }
Power.SHOW_ORDER = { "players", "all", "target" }

local plain = ns.Plate.Plain   -- a call's plain first return, or nil (Plate.lua loads first)

-- Never thicker than half the health bar, so a thin bar keeps some visible fill.
local function borderPx(h)
    return function(px) return ns.Plate.BORDER(px, h) end
end

function Power.Create(p)
    local f = CreateFrame("Frame", nil, p)
    -- Slim and plain, continuing the health bar's angle along its top (Body.lua's
    -- shell look, no masks), like the cast bar.
    f.body = ns.Body.New(f, { borderPx = borderPx(Power.HEIGHT), flat = true, joined = true, clear = ns.Plate.Clear })
    f.bar = Style.Bar(f, nil, ns.Plate.MEDIA.bars.power)
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(0)
    f:Hide()
    p.power = f
end

-- Bar settings for a plate (friendly plates have their own switch, the rest is
-- shared), each with a default since older profiles may lack them. Never taller
-- than the plate's health bar (4 px on a friendly one).
local function opts(c)
    return {
        height = math.min(c.powerHeight or Power.HEIGHT, c.height or Power.HEIGHT),
        gap = c.powerGap or Power.GAP,
    }
end

-- Space the bar takes under the health bar while enabled in settings. The layout
-- reserves it whether shown or not, so nothing jumps.
function Power.Room(c)
    if not (c and c.power) then return 0 end
    local o = opts(c)
    return o.height + o.gap
end

-- Space it takes right now (the cast bar and combo row drop by this).
function Power.Drop(p)
    if not (p and p.powerOn) then return 0 end
    return Power.Room(ns.Plate.Cfg(p))
end

-- Whether a plate's unit gets the bar: enabled, the plate has a bar (not
-- name-only or a minion badge), and it matches the setting. UnitIsPlayer and the
-- power type are never secret; an unknown type counts as mana.
function Power.Wanted(p)
    local c = ns.Plate.Cfg(p)
    if not (c and c.power) then return false end
    if ns.Plate.NameOnly(p, c) or p.minion or p.minionBar then return false end
    local show = c.powerShow or "players"
    if p.isSample then
        return p.samplePower ~= nil and (show ~= "target" or p.sampleTarget == true)
    end
    local u = p.unit
    if not u then return false end
    if show == "target" then return p.isTarget == true end
    -- No power at all (a readable max of 0): nothing to draw.
    if plain(UnitPowerMax, u) == 0 then return false end
    if show == "all" then return true end
    if plain(UnitIsPlayer, u) == true then return true end
    local kind = plain(UnitPowerType, u)
    return kind == nil or kind == Power.MANA
end

-- Placed under the health bar (cut continues its angled end).
function Power.Layout(p, cut)
    local f, hp = p.power, p.hp
    local c = ns.Plate.Cfg(p)
    local o = opts(c)
    local w, h, hh = hp:GetWidth(), o.height, hp:GetHeight()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, -(hh + o.gap))
    f:SetSize(w, h)
    f:SetFrameLevel(hp:GetFrameLevel() + 3)
    if f.bodyH ~= h then
        f.bodyH = h
        f.body.opts.borderPx = borderPx(h)
    end
    -- Continue the health bar's edge at this bar's top and bottom, like Cast.Layout.
    local total = hh + o.gap + h
    local line = (cut or 0) > 0 and cut * total / hh or 0
    local ref = f.body.opts.ref or {}
    f.body.opts.ref = ref
    ref.frame, ref.height = hp, total
    ns.Body.Layout(f.body, line > 0 and line * (hh + o.gap) / total or 0, line)
    ns.Body.FitBar(f.body, f.bar)
    ns.Plate.BackAlpha(f.bar)
    f.laidGen = ns.Plate.gen
end

-- Color: the power type's gradient pair (Gradients page), or a single color as a
-- gradient. token is the unit's power token (nil = mana).
function Power.Paint(p, token)
    local bar, c = p.power.bar, ns.Plate.Cfg(p)
    -- A plugin's fill (DaylightUI.API's Paint): white under its texture, the
    -- empty part in the power's own color unless the plugin holds that too.
    if ns.Plate.Owned("powerFill") then
        Style.SetBarGradient(bar, false)
        bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
        if not ns.Plate.Owned("powerBack") then ns.Plate.SetBackColor(bar, Style.PowerColor(token)) end
    elseif c.powerColor == "custom" and type(c.powerCustom) == "table" then
        local k = c.powerCustom
        Style.SetBarColor(bar, Style.Soften(k[1], k[2], k[3]))
        DUI.Gradients.PaintFrom(bar, { k[1], k[2], k[3] })
    else
        DUI.Gradients.Paint(bar, DUI.Gradients.PowerKey(token))
    end
    ns.Plate.Painted(p)
end

-- Range, color and value (on a new unit, max or power type).
function Power.Update(p, instant)
    if not p.powerOn or p.isSample then return end
    local u, bar = p.unit, p.power.bar
    Style.SetBarRange(bar, 0, UnitPowerMax(u))
    local _, token = UnitPowerType(u)
    Power.Paint(p, token)
    Style.SetBarValue(bar, UnitPower(u), instant)
end

-- Plain power change: only the value moves.
function Power.Value(p)
    if not p.powerOn then return end
    Style.SetBarValue(p.power.bar, UnitPower(p.unit))
end

-- Power events only while the bar shows; otherwise 40 plates' regen ticks add up.
-- Plate's listen() drops every event when p.powerEvents is nil.
local function listen(p, on)
    if on == (p.powerEvents == true) then return end
    for event in pairs(Power.EVENTS) do
        if on then
            pcall(p.RegisterUnitEvent, p, event, p.unit)
        else
            pcall(p.UnregisterEvent, p, event)
        end
    end
    p.powerEvents = on or nil
end

-- Shows or hides the bar for its unit. When that changes, whatever sits under the
-- health bar (cast bar, combo row, a name below) moves. instant: a freshly set up
-- plate, the fill snaps.
function Power.Refresh(p, instant)
    local on = Power.Wanted(p)
    local was = p.powerOn == true
    p.powerOn = on or nil
    local f = p.power
    if on and (not was or f.laidGen ~= ns.Plate.gen) then Power.Layout(p, p.hpCut) end
    if not p.isSample then listen(p, on and p.unit ~= nil) end
    if on ~= was then
        -- Fades in or out quickly; combat info never waits on it (the value is set now).
        -- A freshly set up plate snaps.
        local M = DUI.Motion
        M.AlphaTo(f, on and 1 or 0, instant and 0 or M.FAST, not on)
        ns.Cast.Relayout(p)
        local Combo = ns.Combo
        if Combo then
            if p.comboRow then Combo.LayoutRow(p.comboRow, p)
            elseif Combo.row and Combo.row.plate == p then Combo.LayoutRow(Combo.row, p) end
        end
        ns.Plate.PlaceSpots(p)
    end
    if on then Power.Update(p, instant or not was) end
    p.powerSet = true -- checked once per unit; target switches and power type changes check again
end

-- Options preview: the bar at a fraction of full, in the unit's power color.
function Power.ShowSample(p, u)
    p.samplePower = u.power -- nil for a unit with no power (the friendly NPC)
    Power.Refresh(p, true)
    if not p.powerOn then return end
    local bar = p.power.bar
    bar:SetMinMaxValues(0, 100)
    Style.SetBarValue(bar, u.power or 0, true)
    Power.Paint(p, u.powerToken)
    p.power:SetAlpha(1)
end

-- The plate's unit went away; the next unit starts with no bar.
function Power.Leave(p)
    listen(p, false)
    p.powerOn, p.powerSet = nil, nil
    DUI.Motion.AlphaTo(p.power, 0, 0, true) -- immediately, stopping any fade in progress
end
