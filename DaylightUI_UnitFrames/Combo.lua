-- Combo points for rogues and druids. On this client they belong to the
-- target, so the pips sit under or over the target frame and GetComboPoints is
-- read directly (the power value can still hold the old target's count right
-- after a swap). Each pip is a tiny bar spanning (i - 1, i), so it fills once
-- the count reaches it and still works with a secret count. The last pip can be
-- red. It only fills at max points, so the row reads as full at a glance
-- without comparing the count.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Combo = {}
ns.Combo = Combo

Combo.MAX = 5
Combo.GAP = 3
Combo.BORDER_PX = 2
Combo.COLOR = DUI.Gradients.COMBO_COLOR
Combo.FULL_COLOR = DUI.Gradients.COMBO_FULL

-- Only one power event. The game's own combo bar listens to UNIT_POWER_FREQUENT
-- only (ClassPowerBar.lua). UNIT_POWER_UPDATE is a slower copy of it.
local EVENTS = { "UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER" }

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

function Combo.Create(target)
    local _, class = UnitClass("player")
    if class ~= "ROGUE" and class ~= "DRUID" then return nil end
    local c = CreateFrame("Frame", nil, target)
    c.class, c.target, c.pips = class, target, {}
    for i = 1, Combo.MAX do
        local pip = CreateFrame("Frame", nil, c)
        Style.Shell(pip, { borderPx = Combo.BORDER_PX, noBevel = true })
        pip.bar = Style.Bar(pip, nil, ns.UF.MEDIA.combo.bar)
        pip.bar:SetMinMaxValues(i - 1, i)
        pip.bar:SetValue(0)
        Style.Slant(pip, nil, 0)
        Style.Clip(pip, pip.bar:GetStatusBarTexture(), "inner")
        Style.Clip(pip, Style.BarBack(pip.bar), "inner")
        -- One more bar on top spanning the last point. It only fills at max
        -- points, so the whole row can switch to the full color without reading
        -- the possibly secret count. Shown by Gradients.PaintCombo.
        pip.full = Style.Bar(pip, nil, ns.UF.MEDIA.combo.bar)
        pip.full:SetMinMaxValues(Combo.MAX - 1, Combo.MAX)
        pip.full:SetValue(0)
        pip.full:SetAllPoints(pip.bar)
        pip.full:SetFrameLevel(pip.bar:GetFrameLevel() + 1)
        Style.BarBack(pip.full):SetAlpha(0)
        Style.Clip(pip, pip.full:GetStatusBarTexture(), "inner")
        pip.full:Hide()
        c.pips[i] = pip
    end
    DUI.Gradients.ComboSweep(c)    -- the light at max points
    for _, e in ipairs(EVENTS) do pcall(c.RegisterUnitEvent, c, e, "player") end
    -- Points carried onto a new target keep their count without a power event.
    pcall(c.RegisterEvent, c, "COMBO_TARGET_CHANGED")
    -- Energy ticks and finisher spends fire the same event, so only redraw
    -- the row when the count actually changed (Gradients.ComboSame).
    c:SetScript("OnEvent", function(self, event, _, powerType)
        if event == "UNIT_POWER_FREQUENT" and DUI.Gradients.ComboSame(self, powerType) then return end
        Combo.Update(self)
    end)
    return c
end

-- Pip height: the setting, or automatic (a little over half the width).
function Combo.Height(cfg)
    local h = cfg.height or 0
    if h > 0 then return h end
    return math.floor(cfg.size * 0.55 + 0.5)
end

-- How far the row reaches above the target's debuff anchor (top of the name
-- tab or the frame) when it sits above. The debuffs start past it.
function Combo.Lift(cfg)
    return math.max(0, 4 + Combo.Height(cfg) + (cfg.y or 0))
end

-- Pip width: the setting, or the frame's width divided up when stretched.
local function pipWidth(cfg, f, gap)
    if not cfg.stretch then return cfg.size end
    local span = f:GetWidth() - (f.cut or 0) - 16
    return math.max(4, math.floor((span - (Combo.MAX - 1) * gap) / Combo.MAX))
end

-- Protected parent, so only call through DUI.AfterCombat.
function Combo.Layout(c, cfg)
    if not c then return end
    c.enabled = cfg.enabled
    local onPlayer = cfg.anchor == "player" and ns.frames and ns.frames.player
    local f = onPlayer or c.target
    local h = Combo.Height(cfg)
    local gap = cfg.gap or Combo.GAP
    local w = pipWidth(cfg, f, gap)
    local border = cfg.border or Combo.BORDER_PX
    local cut = Pixel.Snap(c, h * 0.5)
    local T = Pixel.Px(c, border)
    -- Under the frame (and Ribbon's power line) or above it, clear of the name
    -- tab or Ribbon's row. Horizontally it starts just past the angled inner
    -- end (the target's left, the player's right), is centered, or starts
    -- from the outer end clear of the portrait ring.
    local above = cfg.side == "above"
    local onRight = onPlayer or f.cutSide == "right"   -- which end is angled, the personal display's too
    local inner = onRight and "RIGHT" or "LEFT"
    local outer = onRight and "LEFT" or "RIGHT"
    local out = onRight and -1 or 1      -- inner end to outer end
    local y
    if above then
        local tab = f.tab
        y = 4 + ((tab and tab:IsShown()) and (tab:GetHeight() - Pixel.Px(f, 1)) or 0)
    else
        y = -4 - (f.foot or 0)
    end
    local x, side
    if cfg.stretch or cfg.align == nil or cfg.align == "inner" then
        side, x = inner, out * ((f.cut or 0) + 8)
    elseif cfg.align == "center" then
        side, x = "", 0
    else
        side, x = outer, -out * ((f.ringInset or 0) + 8)
    end
    local vert, rel = above and "BOTTOM" or "TOP", above and "TOP" or "BOTTOM"
    c:ClearAllPoints()
    c:SetPoint(vert .. side, f, rel .. side, x + (cfg.x or 0), y + (cfg.y or 0))
    c:SetSize(Combo.MAX * (w + gap) - gap, h)
    for i, pip in ipairs(c.pips) do
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", c, "TOPLEFT", (i - 1) * (w + gap), 0)
        pip:SetSize(w, h)
        Style.Shell(pip, { borderPx = border, noBevel = true, noBorder = border == 0 })
        pip.bar:ClearAllPoints()
        pip.bar:SetPoint("TOPLEFT", pip, "TOPLEFT", T, -T)
        pip.bar:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -T, T)
        -- Angled like the target's inner end, so the row reads as part of it.
        Style.Slant(pip, onRight and "right" or "left", cfg.slant == false and 0 or cut)
    end
    -- Colors: Color, the full color, and the Gradients page's pairs.
    DUI.Gradients.PaintCombo(c.pips, cfg)
    Combo.Update(c)
end

-- Push the count to every pip and the full-row overlay. Passed whole since it may be secret.
function Combo.SetCount(c, n)
    for _, pip in ipairs(c.pips) do
        pip.bar:SetValue(n)
        pip.full:SetValue(n)
    end
end

-- The target's cast bar under the frame only clears the pips while they show.
-- The personal display's row isn't under the target.
local function tellCastBar(c)
    if c == ns.combo and ns.targetCastbarFree then
        ns.CastBar.PipsUp(ns.targetCastbarFree, c:IsShown())
    end
end

-- Test mode: show n points regardless of class or form.
function Combo.ShowSample(c, n)
    c.test = true
    c:SetShown(c.enabled and true or false)
    tellCastBar(c)
    Combo.SetCount(c, n)
end

function Combo.HideSample(c)
    if not c.test then return end
    c.test = nil
    Combo.Update(c, true)
end

-- newTarget: the target changed or test mode ended. The count is only stored,
-- never animated, even if this look shows later.
function Combo.Update(c, newTarget)
    if not c then return end
    if newTarget then c.fresh = true end
    if c.test then return end
    -- Druids only have combo points in cat form.
    local show = c.enabled
    if show and c.class == "DRUID" then
        local _, token = UnitPowerType("player")
        show = isSecret(token) or token == "ENERGY"
    end
    c:SetShown(show and true or false)
    tellCastBar(c)
    if not show then return end
    -- Don't truth-test the count, it may be secret.
    local n = 0
    if GetComboPoints then n = GetComboPoints("player", "target") end
    DUI.Gradients.PopCombo(c, n, c.fresh)
    c.fresh = nil
    Combo.SetCount(c, n)
end
