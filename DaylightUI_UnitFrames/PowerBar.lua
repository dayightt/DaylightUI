-- A frame's power bar placed outside the frame, in two ways.
-- The free bar (<unit>.powerAt = "free", player, target and focus): a separate
-- bar on its own mover, with its own width and angled end. Its height is the
-- frame's powerHeight plus the border. It's not secure and not anchored to the
-- frame, so it shows, moves and fades like any other addon frame; the target's
-- and focus's show and hide with their frame.
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
-- The frames whose power bar can stand on its own, and each one's mover.
PB.FREE = { player = PB.KEY, target = "unitframes.targetPower", focus = "unitframes.focusPower" }

function PB.KeyFor(unit) return PB.FREE[unit] end
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
    local unit = f.spec.unit
    local h = CreateFrame("Frame", "DaylightUIPowerBar_" .. unit, UIParent)
    ns.UF.LiftPiece(h, f)   -- before its pieces are made, so they start above the frame too
    Style.Shell(h)
    Style.Slant(h, nil, 0)
    h.set = makeSet(h, f)
    h.key = PB.FREE[unit]
    f.freePower = h
    h:Hide()
    if unit ~= "player" then
        -- The target and focus come and go: the bar goes with its frame.
        f:HookScript("OnShow", function() if h.want then h:Show() end end)
        f:HookScript("OnHide", function() h:Hide() end)
    end
    return h
end

-- A style's power line (UF.Build, frames with spec.styled and a power bar).
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
-- (a style's line under the frame) or "inside". Points f's power fields at that bar's pieces and hides
-- the others. A frame without the requested holder (an options sample has no
-- free bar) only reads the choice, so its preview is all health like the game's.
function PB.Pick(f, cfg)
    local where = "inside"
    if cfg.powerAt == "free" and (f.freePower or PB.FREE[f.spec.unit]) then
        where = "free"
    elseif f.powerLine then
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
    if f.freePower then
        f.freePower.want = where == "free" and ns.UF.ShowsPower(cfg)
        DUI.Movers.Suspend(f.freePower.key, not f.freePower.want)
    end
    return where
end

-- Lays out the free bar, after the frame's own layout has set f.flipped and
-- f.growLeft. The caller is protected, this runs inside UF.Layout.
function PB.Layout(f, cfg, text)
    local UF, h = ns.UF, f.freePower
    if not h then return end
    local show = cfg.enabled ~= false and UF.ShowsPower(cfg)
    h:SetScale(DUI.Movers.Scale(h.key))
    local T = Pixel.Px(h, Style.BorderPx(h))
    local H = Pixel.Snap(h, cfg.powerHeight) + 2 * T
    h:SetSize(2 * Pixel.Snap(h, (tonumber(cfg.powerWidth) or tonumber(cfg.width) or 187) / 2), H)
    -- Each end is set on its own: powerSlant angles the end on the frame's
    -- angled side (inner), powerSlantBoth the other one; powerSlantUnder and
    -- powerSlantUnderLeft flip the right and left ends (bottom corner out).
    local inner = f.spec.slant
    local outer = inner == "left" and "right" or "left"
    local innerOn = inner ~= nil and cfg.powerSlant ~= false
    local outerOn = inner ~= nil and cfg.powerSlantBoth == true
    local leftOn = (inner == "left" and innerOn) or (outer == "left" and outerOn)
    local rightOn = (inner == "right" and innerOn) or (outer == "right" and outerOn)
    local ends, under = Style.EndsOf(leftOn, cfg.powerSlantUnderLeft, rightOn, cfg.powerSlantUnder)
    local cut = ends and Pixel.Snap(h, H * UF.AngleOf(cfg.powerOwnAngle, cfg.powerLean)) or 0
    local side = innerOn and inner or nil
    -- The cost shade cuts both its own ends at the angle (UF.LayoutCost), so with both
    -- of the bar's ends angled it keeps only the clip at the end the fill starts
    -- from, where a big cost runs past the bar. A texture takes three masks, and
    -- this saves the fourth. Set before the slant lays out, since that adds the clips.
    local cost = h.set.cost
    if cost then
        Style.ClipSpan(cost:GetStatusBarTexture(), nil, nil, ends == "both" and (f.growLeft == true and "right" or "left") or false)
    end
    Style.Slant(h, ends, cut, nil, under)
    -- Read by a cast bar hung under it (CB.Layout, playerCastbar.from "power")
    -- and the swing bars: the frame's spec (which side is angled), this bar's
    -- inner cut, its ends and which flip (UF.HangEnds), and its mover.
    h.spec, h.cut, h.moverKey = f.spec, side and cut or 0, h.key
    h.ends, h.under, h.endCut = ends, under, cut
    local p = h.set.power
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", h, "TOPLEFT", T, -T)
    p:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    p:Show()
    -- The fill's moving edge takes the angle of the end it runs toward: the
    -- inner end, or the outer one when reversed.
    local toward = f.flipped and outer or inner
    local edge = (toward and UF.HasEnd(ends, toward)) and toward or nil
    Style.AngleFill(p, edge, cut * (H - 2 * T) / H, UF.EdgeUnder(under, edge))
    UF.LayoutPowerExtras(f, cfg, text, side, cut, H, true)
    h.want = show
    h:SetShown(show and (f.spec.unit == "player" or f:IsShown()))
    if show and not f.test and type(f.unitToken) == "string" and UnitExists(f.unitToken) then
        UF.UpdatePower(f, true)
    end
end

-- Lays out a style's power line under f: the gap, then a bar as wide as the frame.
-- Its angle continues the frame's edge using one mask measured from the
-- frame's top corner down through the line (like a hung cast bar), so the two
-- can't drift apart. side/cut are the frame's. Sets f.foot, the space the line
-- takes under the frame (0 while off). The caller is protected.
-- The line's height and the gap above it: what it takes under the frame.
function PB.LineSize(f, cfg)
    local h = f.line
    local T = Pixel.Px(h, Style.BorderPx(h))
    return Pixel.Snap(f, tonumber(cfg.powerHeight) or 4) + 2 * T,
        Pixel.Snap(f, tonumber(cfg.ribbonGap) or ns.UF.LINE_GAP), T
end

function PB.LayoutLine(f, cfg, text, side, cut, show)
    local h = f.line
    f.foot = 0
    if not h then return end
    if not show then
        h:Hide()
        return
    end
    local H, gap, T = PB.LineSize(f, cfg)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -gap)
    h:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -gap)
    h:SetHeight(H)
    h:SetFrameLevel(f:GetFrameLevel() + 1)
    local fH = f:GetHeight()
    local total = fH + gap + H
    local ref = h.slantRef or {}
    h.slantRef = ref
    -- It continues each of the frame's angled ends (a flipped one as a chevron).
    local ends, lineCut = ns.UF.HangEnds(f, total, ref, fH)
    Style.Slant(h, ends, lineCut, ref)
    -- How far in the inner end is at the line, for its texts.
    if not ns.UF.HasEnd(ends, side) then side = nil end
    local innerCut = side and lineCut * (total - (ref.drop[side] or 0)) / total or 0
    local p = h.set.power
    -- A portrait on the frame reaches down over the line's outer end too: the
    -- bar starts where the ring's outline crosses its bottom edge, as the
    -- frame's own bars do (UF.Layout's f.ringShape).
    local ring = f.ringShape
    local edge = ring and math.min(ns.UF.RingEdge(f, ring, -gap - T), ns.UF.RingEdge(f, ring, -gap - H + T))
    local more = ring and math.max(0, edge - T) or 0
    f.powerRing = more
    local l, r = T, T
    if ring and ring.outerRight then r = T + more else l = T + more end
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", h, "TOPLEFT", l, -T)
    p:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -r, T)
    ns.UF.BackToBorder(p, ring, more)
    p:SetReverseFill(f.growLeft == true)
    -- The fill's moving edge takes the angle of the end it runs toward.
    local toward = f.growLeft == true and "left" or "right"
    local fillSide = ns.UF.HasEnd(ends, toward) and toward or nil
    Style.AngleFill(p, fillSide, lineCut * (H - 2 * T) / total)
    -- Its texts stay clear of the angle at the line, nearly the whole cut this
    -- far down.
    ns.UF.LayoutPowerExtras(f, cfg, text, side, innerCut, total, true, innerCut + 4)
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
-- Keep ticking (player.regenTicks): after the rule, a light runs to each mana
-- regen tick. The tick's length is measured from the gaps between real mana
-- gains, never assumed: gaps outside this range (steady regen, a potion) are
-- not ticks, and without a measured tick nothing shows.
PB.TICK_MIN, PB.TICK_MAX = 1, 4
PB.TICK_GRACE = 0.3   -- how late a tick's gain may come before ticking stops
PB.TICK_ALPHA = 0.6   -- ticks are softer than the rule's own sweep

local WHITE = "Interface\\Buttons\\WHITE8x8"
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local regen = { sweeps = {}, gen = 0, onMana = true }
PB.regen = regen

local isSecret = DUI.IsSecret

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
-- from the bar's beginning so the old light doesn't jump there. Between rules
-- the ticks (regen.ticking) run the same light, softer, and fade out at full
-- mana: plain mana is checked before a tick starts, secret mana goes through
-- the full-mana curve so the light's alpha drops to 0 at full.
local function arm(s, restart)
    local look = regen.look
    local on = (regen.ends or regen.ticking) and look ~= "off" and regen.onMana and s.bar:IsVisible()
    if not on then
        if s.holder:IsShown() then DUI.Motion.AlphaTo(s.holder, 0, DUI.Motion.FAST, true) end
        return
    end
    if restart then s.holder:SetAlpha(0) end
    local dir = Enum.StatusBarTimerDirection
    s.timer:SetTimerDuration(regen.ends and regen.duration or regen.tickDuration, Enum.StatusBarInterpolation.Immediate,
        look == "line" and dir.RemainingTime or dir.ElapsedTime)
    if regen.ends then
        s.timer:SetAlpha(1)
    else
        s.timer:SetAlpha(ns.UF.FullManaAlpha("player", 0, PB.TICK_ALPHA))
    end
    DUI.Motion.AlphaTo(s.holder, 1, DUI.Motion.FAST)
end

local function armAll(restart)
    for _, s in pairs(regen.sweeps) do arm(s, restart) end
end

local function ticksOn()
    local db = ns.module and ns.module.db
    return db and db.player and db.player.regenTicks == true and regen.look ~= "off"
end

-- Plain mana, or nil while it reads secret.
local function plainMana()
    local cur, max = UnitPower("player", MANA), UnitPowerMax("player", MANA)
    if isSecret(cur) or isSecret(max) or type(cur) ~= "number" or type(max) ~= "number" then return end
    return cur, max
end

local startTick

-- The tick that began at `from`. Its end waits a moment for the next gain;
-- a gain restarts it from that gain. No gain with mana plain means full or no
-- regen, so ticking stops. Secret mana can't be read, so the ticks go on by
-- the measured beat and the curve hides them at full.
startTick = function(from)
    local tick = regen.tick
    if not (tick and ticksOn()) or regen.ends then regen.ticking = nil; return end
    local cur, max = plainMana()
    if cur and cur >= max then
        regen.ticking = nil
        armAll()
        return
    end
    regen.gen = regen.gen + 1
    local gen, restart = regen.gen, not regen.ticking
    regen.ticking = true
    regen.tickDuration = regen.tickDuration or C_DurationUtil.CreateDuration()
    regen.tickDuration:SetTimeFromStart(from, tick)
    armAll(restart)
    C_Timer.After(math.max(0, from + tick + PB.TICK_GRACE - GetTime()), function()
        if gen ~= regen.gen then return end
        if plainMana() then
            regen.ticking = nil
            armAll()
        else
            startTick(from + tick)
        end
    end)
end

-- The tick in progress now, by the beat of the last gain.
local function resumeTicks()
    local tick, last = regen.tick, regen.lastGain
    if not (tick and last) then return false end
    local now = GetTime()
    startTick(last + math.floor((now - last) / tick) * tick)
    return regen.ticking == true
end

function PB.RegenStart()
    regen.gen = regen.gen + 1
    local gen, now = regen.gen, GetTime()
    regen.ends = now + PB.REGEN_WINDOW
    regen.ticking = nil
    regen.duration = regen.duration or C_DurationUtil.CreateDuration()
    regen.duration:SetTimeFromStart(now, PB.REGEN_WINDOW)
    armAll(true)
    -- Hidden just as the light reaches the end, unless the ticks take over.
    C_Timer.After(PB.REGEN_WINDOW - DUI.Motion.FAST, function()
        if gen ~= regen.gen then return end
        regen.ends = nil
        if not (ticksOn() and resumeTicks()) then armAll() end
    end)
end

-- A mana change, out of the rule or in it. Only a plain rise counts as a gain;
-- the gap between two gains is the tick when it's in range.
function PB.ManaChanged()
    local cur, max = plainMana()
    if not cur then return end
    local last = regen.lastMana
    regen.lastMana = cur
    if cur >= max then
        if regen.ticking then regen.gen = regen.gen + 1; regen.ticking = nil; armAll() end
        return
    end
    if not (last and cur > last) then return end
    local now = GetTime()
    if regen.lastGain then
        local gap = now - regen.lastGain
        if gap >= PB.TICK_MIN and gap <= PB.TICK_MAX then regen.tick = gap end
    end
    regen.lastGain = now
    if not regen.ends and ticksOn() then startTick(now) end
end

-- Stops it at once, when turned off.
function PB.RegenStop()
    regen.gen, regen.ends, regen.ticking = regen.gen + 1, nil, nil
    for _, s in pairs(regen.sweeps) do DUI.Motion.AlphaTo(s.holder, 0, 0, true) end
end

local function readPower()
    local _, token = UnitPowerType("player")
    if not isSecret(token) then regen.onMana = token == "MANA" end
end

local function onEvent(_, event, _, arg2, spellID)
    if event == "UNIT_DISPLAYPOWER" then
        readPower()
        armAll()
    elseif event == "UNIT_POWER_FREQUENT" then
        if arg2 == "MANA" then PB.ManaChanged() end
    elseif PB.CostsMana(spellID) then
        PB.RegenStart()
    end
end

-- on = the sweep's events; ticks = the mana changes too, only with Keep ticking.
local function listen(on, ticks)
    ticks = on and ticks or false
    if on == (regen.listening or false) and ticks == (regen.listeningTicks or false) then return end
    regen.listening, regen.listeningTicks = on, ticks
    local ev = regen.events
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", onEvent)
        regen.events = ev
    end
    ev:UnregisterAllEvents()
    if on then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    end
    if ticks then
        ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        regen.lastMana = plainMana()   -- so the first rise already counts
    else
        regen.lastMana, regen.lastGain, regen.tick = nil, nil, nil
        if regen.ticking then regen.gen = regen.gen + 1; regen.ticking = nil; armAll() end
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
    listen(look ~= "off", ticksOn())
    if look == "off" then
        if was and was ~= "off" then PB.RegenStop() end
        return
    end
    readPower()
    if was and was ~= look then PB.RegenStart() else armAll() end
end
