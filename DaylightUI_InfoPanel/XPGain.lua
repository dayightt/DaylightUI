-- XP bar gain effects: the fill eases, the gained piece flashes, a "+1,234"
-- rises off the bar (consecutive kills add up), and a level up sweeps a band
-- across before it empties. With the XP orbs (XPOrbs.lua) a gain flies in
-- first: the fill steps as each orb lands and the last one sweeps a light over
-- the gained piece. Reputation at the cap gets the same minus the level up and
-- the orbs. A secret value skips the effects and is set directly.

local _, ns = ...
local DUI = DaylightUI
local secret = DUI.IsSecret
local Style = DUI.Style

local XPGain = {}
ns.XPGain = XPGain

XPGain.FLASH = { 1, 1, 1, 0.6 }
XPGain.RISE = 10        -- px the "+N" climbs
XPGain.RISE_TIME = 1.2  -- seconds it lasts
XPGain.BAND = 0.25      -- the sweep's width, as a share of the bar

local function enabled()
    local db = ns.module and ns.module.db
    return not (db and db.xpGain == false) and DUI.Motion ~= nil and DUI.Motion.On()
end


local function plain(bar, value)
    if secret(value) then bar:SetValue(value) else Style.SetBarValue(bar, value) end
end

-- The white flash over the gained piece.
local function flashPiece(XP, from, to, max)
    local up = XP.vertical
    local w = (up and XP.bar:GetHeight() or XP.bar:GetWidth()) or 0
    if w <= 0 or max <= 0 then return end
    local t = XPGain.flash
    if not t then
        t = XP.bar:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(unpack(XPGain.FLASH))
        t:Hide()
        XPGain.flash = t
    end
    t:ClearAllPoints()
    if up then
        t:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", 0, w * from / max)
        t:SetPoint("BOTTOMRIGHT", XP.bar, "BOTTOMRIGHT", 0, w * from / max)
        t:SetHeight(math.max(1, w * (to - from) / max))
    else
        t:SetPoint("TOPLEFT", XP.bar, "TOPLEFT", w * from / max, 0)
        t:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", w * from / max, 0)
        t:SetWidth(math.max(1, w * (to - from) / max))
    end
    DUI.Motion.Flash(t, DUI.Motion.SLOW)
end

-- The rising number's color: the bar's color (rested purple while rested XP
-- remains), lightened so the small text reads against the world.
XPGain.LIFT = 0.45
function XPGain.TextColor(XP)
    local d = XP.Read and XP.Read()
    local c = (d and (d.rested or 0) > 0 and XP.RESTED) or (d and d.color) or XP.COLOR
    local w, k = Style.INK.VALUE, XPGain.LIFT
    return c[1] + (w[1] - c[1]) * k, c[2] + (w[2] - c[2]) * k, c[3] + (w[3] - c[3]) * k
end

-- The rising number: a small Daylight UI frame over the bar. A gain while it
-- still shows is added on and the climb starts again.
local function rise(XP, gain)
    local f = XPGain.riser
    if not f then
        f = CreateFrame("Frame", nil, XP.frame)
        f:SetSize(120, 14)
        f:Hide()
        f.text = Style.Text(f, 11, "CENTER", ns.MEDIA.fonts.xp)
        f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
        local g = f:CreateAnimationGroup()
        f.move = g:CreateAnimation("Translation")
        f.move:SetDuration(XPGain.RISE_TIME)
        f.move:SetSmoothing("OUT")
        local fade = g:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(XPGain.RISE_TIME)
        fade:SetSmoothing("IN")
        g:SetScript("OnFinished", function() f:Hide(); f.total = 0 end)
        f.group = g
        XPGain.riser = f
    end
    f:SetFrameLevel(XP.bar:GetFrameLevel() + 5)
    f.total = (f:IsShown() and f.total or 0) + gain
    f.text:SetText("+" .. BreakUpLargeNumbers(f.total))
    f.text:SetTextColor(XPGain.TextColor(XP))
    -- Up off the bar; down instead when the bar is in the top half of the
    -- screen, where "up" leaves the screen. An upright bar's rises beside its
    -- fill's end, on the side toward the screen's middle.
    f:ClearAllPoints()
    if XP.vertical then
        local x, wide = XP.frame:GetCenter(), UIParent:GetWidth()
        local right = not (x and wide and x > wide / 2)
        local _, max = XP.bar:GetMinMaxValues()
        local v, h = XP.bar:GetValue(), XP.bar:GetHeight() or 0
        local y = (not secret(v) and not secret(max) and type(max) == "number" and max > 0) and h * v / max or h
        f:SetPoint(right and "LEFT" or "RIGHT", XP.bar, right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and 4 or -4, y)
        f.move:SetOffset(0, XPGain.RISE)
    else
        local top, high = XP.frame:GetTop(), UIParent:GetHeight()
        local dir = (top and high and top > high / 2) and -1 or 1
        f:SetPoint(dir == 1 and "BOTTOM" or "TOP", XP.bar, dir == 1 and "TOP" or "BOTTOM", 0, dir * 2)
        f.move:SetOffset(0, dir * XPGain.RISE)
    end
    f.group:Stop()
    f:Show()
    f.group:Play()
end

-- The bright band that crosses the bar on a level up.
local function sweep(XP)
    local up = XP.vertical
    local w = (up and XP.bar:GetHeight() or XP.bar:GetWidth()) or 0
    if w <= 0 then return end
    local band = w * XPGain.BAND
    local t = XPGain.band
    if not t then
        t = XP.bar:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 0.85)
        t:Hide()
        local g = t:CreateAnimationGroup()
        t.move = g:CreateAnimation("Translation")
        t.move:SetDuration(DUI.Motion.SLOW)
        t.move:SetSmoothing("OUT")
        local fade = g:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(DUI.Motion.SLOW)
        g:SetScript("OnFinished", function() t:Hide() end)
        t.group = g
        XPGain.band = t
    end
    t:ClearAllPoints()
    if up then
        t:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", XP.bar, "BOTTOMRIGHT", 0, 0)
        t:SetHeight(band)
        t.move:SetOffset(0, w - band)
    else
        t:SetPoint("TOPLEFT", XP.bar, "TOPLEFT", 0, 0)
        t:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", 0, 0)
        t:SetWidth(band)
        t.move:SetOffset(w - band, 0)
    end
    t.group:Stop()
    t:SetAlpha(1)
    t:Show()
    t.group:Play()
end

-- The light over the gained piece as the last orb lands: a frame of Daylight
-- UI laid over just that piece, and the bar's own sweep across it.
local function sweepPiece(XP, from, to, max)
    local up = XP.vertical
    local w = (up and XP.bar:GetHeight() or XP.bar:GetWidth()) or 0
    if w <= 0 or max <= 0 or to <= from then return end
    local f = XPGain.piece
    if not f then
        f = CreateFrame("Frame", nil, XP.bar)
        f.light = f:CreateTexture(nil, "OVERLAY")
        f.light:SetTexture(DUI.MEDIA .. "glow.png")
        f.light:SetBlendMode("ADD")
        f.light:Hide()
        XPGain.piece = f
    end
    f:SetFrameLevel(XP.bar:GetFrameLevel() + 3)
    f:ClearAllPoints()
    local a, b = w * from / max, w * math.min(to, max) / max
    if up then
        f:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", 0, a)
        f:SetPoint("BOTTOMRIGHT", XP.bar, "BOTTOMRIGHT", 0, a)
        f:SetHeight(math.max(1, b - a))
    else
        f:SetPoint("TOPLEFT", XP.bar, "TOPLEFT", a, 0)
        f:SetPoint("BOTTOMLEFT", XP.bar, "BOTTOMLEFT", a, 0)
        f:SetWidth(math.max(1, b - a))
    end
    XP.Sweep(f.light, f, { width = XPGain.PIECE_LIGHT, dur = DUI.Motion.SLOW, alpha = 0.7, key = "xpGainPiece" }, up)
end
XPGain.PIECE_LIGHT = 44   -- the light's width over the gained piece

-- The last orb of a gain is home: the light over what it gave, and "+N".
function XPGain.Landed(from, to, max, gain)
    local XP = ns.XP
    if not (XP and XP.bar) then return end
    sweepPiece(XP, from, to, max)
    rise(XP, gain)
end

-- The level up: the bar full while a band crosses it, then the new level's XP.
local function levelSweep(XP, max)
    XPGain.sweepId = (XPGain.sweepId or 0) + 1
    local id = XPGain.sweepId
    XP.bar:SetValue(max)
    sweep(XP)
    C_Timer.After(DUI.Motion.SLOW, function()
        if id ~= XPGain.sweepId or not XP.bar then return end
        local now = XP.Read()
        if now and not now.rep then plain(XP.bar, ns.XPOrbs.Shown(now)) end
    end)
end

-- The level-up burst's last orb is home.
function XPGain.LevelSweep()
    local XP = ns.XP
    if not (XP and XP.bar) then return end
    local _, max = XP.bar:GetMinMaxValues()
    if secret(max) or type(max) ~= "number" then return end
    levelSweep(XP, max)
end

-- Called by XP.Update with the reading; true when it set the bar's value.
function XPGain.Show(d)
    local XP, Orbs = ns.XP, ns.XPOrbs
    if not enabled() then XPGain.last = nil; Orbs.Drop(); return false end
    if secret(d.value) or secret(d.max) then XPGain.last = nil; Orbs.Drop(); return false end
    local last = XPGain.last
    local level = UnitLevel and UnitLevel("player")
    -- Nothing moved (rested or quest XP changed, or the level up arrived ahead
    -- of its new numbers): keep the last reading, so a level up is judged once
    -- its numbers are in.
    if last and last.label == d.label and last.value == d.value and last.max == d.max then
        last.rested = d.rested
        Style.SetBarValue(XP.bar, Orbs.Shown(d))
        return true
    end
    XPGain.last = { label = d.label, value = d.value, max = d.max, level = level, rep = d.rep, rested = d.rested }
    local seen = XPGain.levelSeen
    if not last or last.label ~= d.label then
        Orbs.Drop()
        Style.SetBarValue(XP.bar, d.value, true)
        return true
    end
    local levelUp = not d.rep and not last.rep
        and ((level ~= nil and last.level ~= nil and level > last.level) or (seen and d.value < last.value))
    -- How much the rested pool fell with this gain, for the orbs' rested share.
    local drop = type(last.rested) == "number" and type(d.rested) == "number" and last.rested - d.rested or nil
    if levelUp then
        XPGain.levelSeen = nil
        if Orbs.Wanted(d) and type(last.max) == "number" and last.max > 0 then
            Orbs.Gain({ from = last.value, max = last.max, gain = (last.max - last.value) + d.value,
                        levelUp = true, restedDrop = drop })
            Style.SetBarValue(XP.bar, Orbs.Shown(d))
            return true
        end
        Orbs.Drop()
        levelSweep(XP, d.max)
        return true
    end
    if d.max == last.max and d.value > last.value and Orbs.Wanted(d) then
        Orbs.Gain({ from = last.value, to = d.value, max = d.max, gain = d.value - last.value, restedDrop = drop })
        Style.SetBarValue(XP.bar, Orbs.Shown(d))
        return true
    end
    Style.SetBarValue(XP.bar, Orbs.Shown(d))
    if d.max == last.max and d.value > last.value then
        flashPiece(XP, last.value, d.value, d.max)
        rise(XP, d.value - last.value)
    end
    return true
end
