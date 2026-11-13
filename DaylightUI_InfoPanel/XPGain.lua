-- XP bar gain effects: the fill eases, the gained piece flashes, a "+1,234"
-- rises off the bar (consecutive kills add up), and a level up sweeps a band
-- across before it empties. Reputation at the cap gets the same minus the
-- level up. A secret value skips the effects and is set directly.

local _, ns = ...
local DUI = DaylightUI
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

local function secret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) == true
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

-- The rising number: a small frame of ours over the bar. A gain while it
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

-- Called by XP.Update with the reading; true when it set the bar's value.
function XPGain.Show(d)
    local XP = ns.XP
    if not enabled() then XPGain.last = nil; return false end
    if secret(d.value) or secret(d.max) then XPGain.last = nil; return false end
    local last = XPGain.last
    local level = UnitLevel and UnitLevel("player")
    XPGain.last = { label = d.label, value = d.value, max = d.max, level = level, rep = d.rep }
    local seen = XPGain.levelSeen
    if not last or last.label ~= d.label then
        Style.SetBarValue(XP.bar, d.value, true)
        return true
    end
    local levelUp = not d.rep and not last.rep
        and ((level ~= nil and last.level ~= nil and level > last.level) or (seen and d.value < last.value))
    if levelUp then
        XPGain.levelSeen = nil
        XPGain.sweepId = (XPGain.sweepId or 0) + 1
        local id = XPGain.sweepId
        XP.bar:SetValue(d.max)   -- full while the band crosses
        sweep(XP)
        C_Timer.After(DUI.Motion.SLOW, function()
            if id ~= XPGain.sweepId or not XP.bar then return end
            local now = XP.Read()
            if now and now.label == d.label then plain(XP.bar, now.value) end
        end)
        return true
    end
    Style.SetBarValue(XP.bar, d.value)
    if d.max == last.max and d.value > last.value then
        flashPiece(XP, last.value, d.value, d.max)
        rise(XP, d.value - last.value)
    end
    return true
end
