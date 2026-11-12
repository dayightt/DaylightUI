-- A frame's power bar placed outside the frame, in two ways.
-- The player's free bar (player.powerAt = "free"): a separate bar on its own
-- mover, with its own width and angled end. Its height is the frame's
-- powerHeight plus the border. It's not secure and not anchored to the player
-- frame, so it shows, moves and fades like any other addon frame.
-- Ribbon's line (Ribbon style, UF.StyleOf): a thin bar hung under the frame at
-- the same width, with a gap, its angled end continuing the frame's edge. It's
-- a child of the frame, so it fades and hides with it.
-- While either is in use, the frame's power fields (f.power, f.powerText,
-- f.altMana, f.cost, f.costHolder) point at that bar's pieces, so every update
-- and sample finds the live one.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local PB = {}
ns.PowerBar = PB

PB.KEY = "unitframes.playerPower"
PB.FIELDS = { "power", "powerText", "altMana", "cost", "costHolder" }

-- The frame's own pieces to point back at, saved once before any swap.
local function keepInside(f)
    if f.insidePower then return end
    local inside = {}
    for _, k in ipairs(PB.FIELDS) do inside[k] = f[k] end
    f.insidePower = inside
end

-- The power pieces on holder h, clipped to its angle, using the frame's own
-- texture and font slots.
local function makeSet(h, f)
    local media = ns.UF.MediaOf(f.spec)
    local set = { power = Style.Bar(h, nil, media.bars.power) }
    Style.Clip(h, set.power:GetStatusBarTexture(), "inner")
    Style.Clip(h, Style.BarBack(set.power), "inner")
    local overlay = CreateFrame("Frame", nil, h)
    overlay:SetAllPoints(h)
    overlay:SetFrameLevel(set.power:GetFrameLevel() + 3)
    set.powerText = Style.Text(overlay, 10, f.spec.slant == "left" and "LEFT" or "RIGHT", media.fonts.power)
    set.powerText:Hide()
    if f.altMana then
        set.altMana = Style.Bar(h, nil, media.bars.power)
        set.altMana:SetFrameLevel(set.power:GetFrameLevel() + 1)
        Style.Clip(h, set.altMana:GetStatusBarTexture(), "inner")
        Style.Clip(h, Style.BarBack(set.altMana), "inner")
        set.altMana:SetReverseFill(f.spec.slant == "left")
        set.altMana:Hide()
    end
    if f.cost then set.costHolder, set.cost = ns.UF.CostBar(h, set.power, h) end
    return set
end

function PB.Create(f)
    keepInside(f)
    local h = CreateFrame("Frame", "DaylightUIPowerBar_player", UIParent)
    Style.Shell(h)
    Style.Slant(h, nil, 0)
    h.set = makeSet(h, f)
    f.freePower = h
    h:Hide()
    return h
end

-- Ribbon's line (UF.Build, frames with spec.ribbon and a power bar).
function PB.CreateLine(f)
    keepInside(f)
    local h = CreateFrame("Frame", nil, f)
    h:EnableMouse(false)
    Style.Shell(h, { borderPx = ns.UF.TAB_BORDER })
    Style.Slant(h, nil, 0)
    h.set = makeSet(h, f)
    f.line = h
    h:Hide()
    return h
end

-- Where the frame's power bar is: "free" (the player's standalone bar), "line"
-- (Ribbon) or "inside". Points f's power fields at that bar's pieces and hides
-- the others. A frame without the requested holder (an options sample has no
-- free bar) only reads the choice.
function PB.Pick(f, cfg)
    local where = "inside"
    if f.spec.unit == "player" and cfg.powerAt == "free" then
        where = "free"
    elseif f.ribbon then
        where = "line"
    end
    local holders = { free = f.freePower, line = f.line }
    local h = holders[where]
    if where ~= "inside" and not h then return where end
    for key, other in pairs(holders) do
        if other and key ~= where then other:Hide() end
    end
    if not f.insidePower then return where end
    local set = h and h.set or f.insidePower
    for _, k in ipairs(PB.FIELDS) do f[k] = set[k] end
    if h then
        for _, k in ipairs(PB.FIELDS) do
            local piece = f.insidePower[k]
            if piece then piece:Hide() end
        end
        f.separator:Hide()
    end
    if f.freePower then DUI.Movers.Suspend(PB.KEY, where ~= "free" or not ns.UF.ShowsPower(cfg)) end
    return where
end

-- Lays out the free bar, after the frame's own layout has set f.flipped and
-- f.growLeft. The caller is protected, this runs inside UF.Layout.
function PB.Layout(f, cfg, text)
    local UF, h = ns.UF, f.freePower
    if not h then return end
    local show = cfg.enabled ~= false and UF.ShowsPower(cfg)
    h:SetScale(DUI.Movers.Scale(PB.KEY))
    local T = Pixel.Px(h, Style.BorderPx(h))
    local H = Pixel.Snap(h, cfg.powerHeight) + 2 * T
    h:SetSize(2 * Pixel.Snap(h, (tonumber(cfg.powerWidth) or 187) / 2), H)
    local side = cfg.powerSlant ~= false and f.spec.slant or nil
    local cut = side and Pixel.Snap(h, H * UF.SLANT) or 0
    Style.Slant(h, side, cut)
    -- Read by a cast bar hung under it (CB.Layout, playerCastbar.from "power"):
    -- the frame's spec (which side is angled), this bar's cut, and its mover.
    h.spec, h.cut, h.moverKey = f.spec, side and cut or 0, PB.KEY
    local p = h.set.power
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", h, "TOPLEFT", T, -T)
    p:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    p:Show()
    Style.AngleFill(p, not f.flipped and side or nil, cut * (H - 2 * T) / H)
    UF.LayoutPowerExtras(f, cfg, text, side, cut, H, true)
    h:SetShown(show)
    if show and not f.test and type(f.unitToken) == "string" and UnitExists(f.unitToken) then
        UF.UpdatePower(f, true)
    end
end

-- Lays out Ribbon's line under f: the gap, then a bar as wide as the frame.
-- Its angle continues the frame's edge using one mask measured from the
-- frame's top corner down through the line (like a hung cast bar), so the two
-- can't drift apart. side/cut are the frame's. Sets f.foot, the space the line
-- takes under the frame (0 while off). The caller is protected.
function PB.LayoutLine(f, cfg, text, side, cut, show)
    local h = f.line
    f.foot = 0
    if not h then return end
    if not show then
        h:Hide()
        return
    end
    local T = Pixel.Px(h, Style.BorderPx(h))
    local H = Pixel.Snap(f, tonumber(cfg.powerHeight) or 4) + 2 * T
    local gap = Pixel.Snap(f, tonumber(cfg.ribbonGap) or ns.UF.RIBBON_GAP)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -gap)
    h:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -gap)
    h:SetHeight(H)
    h:SetFrameLevel(f:GetFrameLevel() + 1)
    local fH = f:GetHeight()
    local total = fH + gap + H
    local lineCut = side and fH > 0 and cut * total / fH or 0
    local ref = h.slantRef or {}
    h.slantRef, ref.frame, ref.height = ref, f, total
    Style.Slant(h, lineCut > 0 and side or nil, lineCut, ref)
    local p = h.set.power
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", h, "TOPLEFT", T, -T)
    p:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    p:SetReverseFill(f.growLeft == true)
    local fillSide = (lineCut > 0 and not f.flipped) and side or nil
    Style.AngleFill(p, fillSide, lineCut * (H - 2 * T) / total)
    -- Its texts stay clear of the angle at the line, nearly the whole cut this
    -- far down.
    ns.UF.LayoutPowerExtras(f, cfg, text, lineCut > 0 and side or nil, lineCut, total, true, lineCut + 4)
    h:Show()
    f.foot = gap + H
end

-- The five second rule sweep

-- Spirit regen stops when a mana-costing spell finishes and resumes five
-- seconds later. A light crosses the mana bar over that time, on the player
-- frame and the personal display (player.regenSweep, one look for both). A new
-- cast restarts it. Mana is secret in combat, so nothing here reads it; the
-- signals are your own cast event and the spell's cost. The client animates
-- each bar (SetTimerDuration), so no Lua runs per frame. All bars share one
-- timer, so a bar that reappears mid-sweep (a form ends) joins where it's at.
-- When off there are no events and no frames.

PB.REGEN_WINDOW = 5
PB.REGEN_SPARK_W = 12     -- the spark's width
PB.REGEN_TRAIL = 56       -- the soft trail's length behind the light
PB.REGEN_TRAIL_HEAD = 12  -- and its soft edge ahead of it
PB.REGEN_TRAIL_ALPHA = 0.6
PB.REGEN_LINE_ALPHA = 0.7 -- the draining line's dim end
PB.REGEN_NO_MANA = { WARRIOR = true, ROGUE = true }

local WHITE = "Interface\\Buttons\\WHITE8x8"
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local regen = { sweeps = {}, gen = 0, onMana = true }
PB.regen = regen

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Whether your class has mana at all. The class can read as secret under the
-- client's restrictions, so the last plain value is kept.
function PB.HasMana()
    local _, class = UnitClass("player")
    if not isSecret(class) then regen.class = class end
    return not PB.REGEN_NO_MANA[regen.class or ""]
end

-- The look in use. Off for classes with no mana to regen.
function PB.RegenLook()
    local db = ns.module and ns.module.db
    local look = db and db.player and db.player.regenSweep or "off"
    return PB.HasMana() and look or "off"
end

-- A secret amount counts as a cost. Only a plain 0 is free.
function PB.CostsMana(spellID)
    if isSecret(spellID) then return false end
    local cost = ns.UF.SpellCost(spellID, MANA)
    if type(cost) == "nil" then return false end
    return isSecret(cost) or (type(cost) == "number" and cost > 0)
end

local function makeSweep(bar)
    local owner = bar:GetParent()
    local s = { bar = bar }
    s.holder = CreateFrame("Frame", nil, owner)
    s.holder:SetAllPoints(bar)
    s.holder:SetFrameLevel(bar:GetFrameLevel() + 2)
    s.holder:SetClipsChildren(true)
    s.holder:Hide()
    s.timer = CreateFrame("StatusBar", nil, s.holder)
    s.timer:SetStatusBarTexture(WHITE)
    s.timer:SetMinMaxValues(0, 1)
    s.fill = s.timer:GetStatusBarTexture()
    s.spark = s.timer:CreateTexture(nil, "OVERLAY")
    s.spark:SetTexture(DUI.MEDIA .. "glow.png")
    s.spark:SetBlendMode("ADD")
    s.trail = s.timer:CreateTexture(nil, "OVERLAY")
    s.trail:SetTexture(WHITE)
    s.head = s.timer:CreateTexture(nil, "OVERLAY")
    s.head:SetTexture(WHITE)
    local fill = bar:GetStatusBarTexture()
    for _, tex in ipairs({ s.fill, s.spark, s.trail, s.head }) do Style.ClipLike(tex, fill) end
    regen.sweeps[bar] = s
    return s
end

-- Lays a sweep out for the look, along the bar's own fill direction.
local function dress(s, look)
    local timer, c = s.timer, Style.INK.VALUE
    local lead = s.rev and "LEFT" or "RIGHT"
    timer:ClearAllPoints()
    timer:SetReverseFill(s.rev)
    if look == "line" then
        local H = s.bar:GetHeight()
        timer:SetPoint("BOTTOMLEFT", s.holder, "BOTTOMLEFT", 0, 0)
        timer:SetPoint("BOTTOMRIGHT", s.holder, "BOTTOMRIGHT", 0, 0)
        timer:SetHeight(Pixel.Px(s.bar, H >= 6 and 2 or 1))
        timer:SetStatusBarColor(c[1], c[2], c[3], 1)
        local dim, full = CreateColor(c[1], c[2], c[3], PB.REGEN_LINE_ALPHA), CreateColor(c[1], c[2], c[3], 1)
        s.fill:SetGradient("HORIZONTAL", s.rev and full or dim, s.rev and dim or full)
    else
        timer:SetAllPoints(s.holder)
        timer:SetStatusBarColor(c[1], c[2], c[3], 0)
    end
    s.spark:SetShown(look == "spark")
    s.trail:SetShown(look == "trail")
    s.head:SetShown(look == "trail")
    s.spark:ClearAllPoints()
    s.spark:SetPoint("TOP", s.fill, "TOP" .. lead, 0, 0)
    s.spark:SetPoint("BOTTOM", s.fill, "BOTTOM" .. lead, 0, 0)
    s.spark:SetWidth(PB.REGEN_SPARK_W)
    s.spark:SetVertexColor(c[1], c[2], c[3])
    s.trail:ClearAllPoints()
    s.trail:SetPoint("TOP" .. lead, s.fill, "TOP" .. lead, 0, 0)
    s.trail:SetPoint("BOTTOM" .. lead, s.fill, "BOTTOM" .. lead, 0, 0)
    s.trail:SetWidth(PB.REGEN_TRAIL)
    local none, lit = CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], PB.REGEN_TRAIL_ALPHA)
    s.trail:SetGradient("HORIZONTAL", s.rev and lit or none, s.rev and none or lit)
    local back = s.rev and "RIGHT" or "LEFT"
    s.head:ClearAllPoints()
    s.head:SetPoint("TOP" .. back, s.fill, "TOP" .. lead, 0, 0)
    s.head:SetPoint("BOTTOM" .. back, s.fill, "BOTTOM" .. lead, 0, 0)
    s.head:SetWidth(PB.REGEN_TRAIL_HEAD)
    s.head:SetGradient("HORIZONTAL", s.rev and none or lit, s.rev and lit or none)
end

-- Adds one sweep to the running timer, or removes it. restart starts it over
-- from the bar's beginning so the old light doesn't jump there.
local function arm(s, restart)
    local look = regen.look
    local on = regen.ends and look ~= "off" and regen.onMana and s.bar:IsVisible()
    if not on then
        if s.holder:IsShown() then DUI.Motion.AlphaTo(s.holder, 0, DUI.Motion.FAST, true) end
        return
    end
    if restart then s.holder:SetAlpha(0) end
    local dir = Enum.StatusBarTimerDirection
    s.timer:SetTimerDuration(regen.duration, Enum.StatusBarInterpolation.Immediate,
        look == "line" and dir.RemainingTime or dir.ElapsedTime)
    DUI.Motion.AlphaTo(s.holder, 1, DUI.Motion.FAST)
end

local function armAll(restart)
    for _, s in pairs(regen.sweeps) do arm(s, restart) end
end

function PB.RegenStart()
    regen.gen = regen.gen + 1
    local gen, now = regen.gen, GetTime()
    regen.ends = now + PB.REGEN_WINDOW
    regen.duration = regen.duration or C_DurationUtil.CreateDuration()
    regen.duration:SetTimeFromStart(now, PB.REGEN_WINDOW)
    armAll(true)
    -- Hidden just as the light reaches the end.
    C_Timer.After(PB.REGEN_WINDOW - DUI.Motion.FAST, function()
        if gen ~= regen.gen then return end
        regen.ends = nil
        armAll()
    end)
end

-- Stops it at once, when turned off.
function PB.RegenStop()
    regen.gen, regen.ends = regen.gen + 1, nil
    for _, s in pairs(regen.sweeps) do DUI.Motion.AlphaTo(s.holder, 0, 0, true) end
end

local function readPower()
    local _, token = UnitPowerType("player")
    if not isSecret(token) then regen.onMana = token == "MANA" end
end

local function onEvent(_, event, _, _, spellID)
    if event == "UNIT_DISPLAYPOWER" then
        readPower()
        armAll()
    elseif PB.CostsMana(spellID) then
        PB.RegenStart()
    end
end

local function listen(on)
    if on == (regen.listening or false) then return end
    regen.listening = on
    local ev = regen.events
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", onEvent)
        regen.events = ev
    end
    if on then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    else
        ev:UnregisterAllEvents()
    end
end

-- The sweep for f.power, created the first time a look is on (UF.LayoutCost:
-- the player frame's bar wherever it sits, and the personal display's).
function PB.PlaceRegen(f)
    local look = PB.RegenLook()
    local s = regen.sweeps[f.power]
    if not s then
        if look == "off" then return end
        s = makeSweep(f.power)
    end
    s.rev = f.growLeft == true
    if look ~= "off" then dress(s, look) end
end

-- After the frames' layouts (ns.Refresh), a newly picked look plays one sweep
-- so you can see it.
function PB.RegenApply()
    local look, was = PB.RegenLook(), regen.look
    regen.look = look
    listen(look ~= "off")
    if look == "off" then
        if was and was ~= "off" then PB.RegenStop() end
        return
    end
    readPower()
    if was and was ~= look then PB.RegenStart() else armAll() end
end
