-- Combo points on your target's plate for rogues and cat-form druids: a row of
-- small pips under its health bar (or above it, below the name), in the unit
-- frames' combo colors. On this client combo points belong to the target, so
-- there's one row that moves to whichever plate is your target; that plate's cast
-- bar drops below it, or its name rises above it.
-- Each pip is a tiny bar spanning (i - 1, i), so it fills once the count reaches
-- it and a secret count still draws.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Combo = {}
ns.Combo = Combo

Combo.MAX = 5
Combo.gen = 0 -- bumped on a style change so the pips get re-laid out
Combo.GAP = 3 -- gap between the health bar and the row (also the default pip spacing)
Combo.HEIGHT = 5 -- default pip height
Combo.BORDER_PX = 2 -- default outline
Combo.COLOR = DUI.Gradients.COMBO_COLOR -- the unit frames' combo gold
Combo.FULL_COLOR = DUI.Gradients.COMBO_FULL -- last pip fill when the unit frames set it red

-- Pip colors from the unit frames' combo settings (their defaults if the unit
-- frames are off), painted the same way.
function Combo.Paint(row)
    DUI.Gradients.PaintCombo(row.pips, DUI:Get("UnitFrames", "combo"))
end

local plain = ns.Plate.Plain   -- a call's plain first return, or nil (Plate.lua loads first)

-- Whether you play a class with combo points.
function Combo.Mine()
    local _, class = UnitClass("player")
    return class == "ROGUE" or class == "DRUID", class
end

-- A hidden row of pips on parent: the one on your target's plate (Combo.Create)
-- or the options preview's (Sample.lua).
function Combo.NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.pips = {}
    for i = 1, Combo.MAX do
        local pip = CreateFrame("Frame", nil, row)
        -- Shell look without masks (Body.lua).
        pip.body = ns.Body.New(pip, { borderPx = Combo.BORDER_PX })
        pip.bar = Style.Bar(pip, nil, ns.Plate.MEDIA.bars.combo)
        pip.bar:SetMinMaxValues(i - 1, i)
        pip.bar:SetValue(0)
        -- One more bar over the last point that fills only at max points, so the whole
        -- row can switch to the full color without reading the possibly secret count.
        -- Shown by Gradients.PaintCombo.
        pip.full = Style.Bar(pip, nil, ns.Plate.MEDIA.bars.combo)
        pip.full:SetMinMaxValues(Combo.MAX - 1, Combo.MAX)
        pip.full:SetValue(0)
        pip.full:SetAllPoints(pip.bar)
        pip.full:SetFrameLevel(pip.bar:GetFrameLevel() + 1)
        Style.BarBack(pip.full):SetAlpha(0)
        pip.full:Hide()
        row.pips[i] = pip
    end
    DUI.Gradients.ComboSweep(row) -- highlight at max points
    row:Hide()
    return row
end

-- The row for a combo class, or nil for everyone else.
function Combo.Create()
    local mine, class = Combo.Mine()
    if not mine then return nil end
    local row = Combo.NewRow(UIParent)
    row.class = class
    -- The game's own combo bar only listens to UNIT_POWER_FREQUENT for the
    -- "COMBO_POINTS" token (Blizzard_UnitFrame ClassPowerBar.lua,
    -- RogueComboPointBar.xml); UNIT_POWER_UPDATE is a slower copy. A finisher's spend
    -- arrives on the energy event, so every event reads the count but only a change
    -- moves the pips (Gradients.ComboSame); energy ticks leave the row alone.
    for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER" }) do
        pcall(row.RegisterUnitEvent, row, e, "player")
    end
    -- Points carried to a new target keep their count without a power event.
    pcall(row.RegisterEvent, row, "COMBO_TARGET_CHANGED")
    row:SetScript("OnEvent", function(self, event, _, powerType)
        if event == "UNIT_POWER_FREQUENT" and DUI.Gradients.ComboSame(self, powerType) then return end
        Combo.Place(true)
    end)
    -- Unit frames' combo colors changed: repaint.
    DUI.On("SettingChanged", function(scope, path)
        if scope == "UnitFrames" and type(path) == "string" and path:find("^combo") then
            Combo.Paint(row)
        end
    end)
    row:Hide()
    Combo.row = row
    Combo.Paint(row)
    return row
end

-- Settings, each with a default since older profiles may lack them.
local function opts()
    local c = ns.cfg or {}
    return {
        above = c.comboPosition == "above",
        height = c.comboHeight or Combo.HEIGHT,
        width = c.comboWidth or 1,
        gap = c.comboGap or Combo.GAP,
        border = c.comboBorder or Combo.BORDER_PX,
        slant = c.comboSlant == true,
    }
end

-- Should the row show: enabled, a combo class in the right form, and an
-- attackable target.
local function wanted()
    local row = Combo.row
    if not (row and ns.cfg and ns.cfg.comboPoints) then return false end
    if row.class == "DRUID" then
        local _, token = UnitPowerType("player")
        if not (issecretvalue and issecretvalue(token)) and token ~= "ENERGY" then return false end
    end
    return plain(UnitCanAttack, "player", "target") == true
end

-- Lays the pips across a plate's health bar, under or over it, centered on the
-- bar's straight part when narrower.
local function layout(row, p)
    local o = opts()
    local hp = p.hp
    local w = hp:GetWidth()
    local cut = p.hpCut or 0
    -- The angled end takes the bar's bottom corner, so above the bar use the full width.
    local full = o.above and w or (w - cut)
    local span = math.max(Combo.MAX * 4, full * o.width)
    local pw = math.max(2, (span - (Combo.MAX - 1) * o.gap) / Combo.MAX)
    local x = (full - span) / 2
    row:ClearAllPoints()
    if o.above then
        row:SetPoint("BOTTOMLEFT", hp, "TOPLEFT", x, Combo.GAP)
    else
        -- Below the power bar if the plate has one.
        row:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", x, -(Combo.GAP + ns.Power.Drop(p)))
    end
    row:SetSize(span, o.height)
    -- The pips only depend on these. A target switch between same-size plates just
    -- moves the row and keeps its five shells, slants and masks (rebuilding them
    -- cost thousands of calls per switch).
    local scale = row:GetEffectiveScale()
    if row.pipW == pw and row.pipH == o.height and row.pipGap == o.gap and row.pipBorder == o.border
        and row.pipSlant == o.slant and row.pipScale == scale and row.pipGen == Combo.gen then
        return
    end
    row.pipW, row.pipH, row.pipGap, row.pipBorder, row.pipSlant, row.pipScale, row.pipGen =
        pw, o.height, o.gap, o.border, o.slant, scale, Combo.gen
    local pipCut = o.slant and Pixel.Snap(row, o.height * 0.5) or 0
    for i, pip in ipairs(row.pips) do
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (pw + o.gap), 0)
        pip:SetSize(pw, o.height)
        pip.body.opts.borderPx, pip.body.opts.noBorder = o.border, o.border == 0
        -- Angled like the bar's own end.
        ns.Body.Layout(pip.body, 0, pipCut)
        ns.Body.FitBar(pip.body, pip.bar)
        -- The whole-row overlay on the last pip gets the same fill shape.
        local fillCut = ns.Body.InnerCut(pip.body)
        Style.AngleFill(pip.full, fillCut > 0 and "right" or nil, fillCut)
    end
end
Combo.LayoutRow = layout

-- Whether a row is on plate p: your target's, or the preview's own (p.comboRow,
-- Sample.lua).
local function rowOn(p)
    if p.comboRow then return true end
    return Combo.row ~= nil and Combo.row.plate == p
end

-- Space the row takes under a plate's health bar (the cast bar drops by it).
function Combo.Drop(p)
    if not rowOn(p) then return 0 end
    local o = opts()
    return o.above and 0 or (o.height + Combo.GAP)
end

-- Space the row takes above a plate's health bar (the name rises by it).
function Combo.Lift(p)
    if not rowOn(p) then return 0 end
    local o = opts()
    return o.above and (o.height + Combo.GAP) or 0
end

-- The plate's unit went away, so the row goes too. The plate gets reused, and the
-- next unit's cast bar must not drop for a row it doesn't have.
function Combo.Leave(p)
    local row = Combo.row
    if not row or row.plate ~= p then return end
    row.plate = nil
    row:Hide()
end

-- Moves the row onto your target's plate (or away) and sets the count. countOnly
-- (power events, many per second): leave the pips alone unless the plate changed.
local found
local function findTarget(p)
    if p.isTarget and p.hp:IsShown() then found = p end
end

function Combo.Place(countOnly)
    local row = Combo.row
    if not row then return end
    local target
    if wanted() then
        -- A power tick (every frame while energy fills) on the same target: the row's
        -- plate hasn't changed, so skip walking every plate.
        local cur = row.plate
        if countOnly and cur and cur.isTarget and cur.unit and cur.hp:IsShown() then
            target = cur
        else
            found = nil
            ns.Manager.Each(findTarget)
            target, found = found, nil
        end
    end
    local old = row.plate
    if target ~= old then
        row.plate = target
        -- Cast bars under both plates, and the names above them, make room or close up.
        if old and old.unit then
            ns.Cast.Relayout(old)
            ns.Plate.PlaceSpots(old)
        end
        if target then
            ns.Cast.Relayout(target)
            ns.Plate.PlaceSpots(target)
        end
    end
    if not target then
        row:Hide()
        return
    end
    if target ~= old or not countOnly then
        row:SetParent(target)
        row:SetFrameLevel(target.hp:GetFrameLevel() + 2)
        Combo.Paint(row) -- follows the unit frames' combo colors
        layout(row, target)
    end
    -- No truth test on the count: it may be secret.
    local n = 0
    if GetComboPoints then n = GetComboPoints("player", "target") end
    -- A gained point flashes with five sweeps. Moving onto a plate (new target, or
    -- anything but a power tick) only records the count.
    DUI.Gradients.PopCombo(row, n, target ~= old or not countOnly)
    for _, pip in ipairs(row.pips) do
        pip.bar:SetValue(n)
        pip.full:SetValue(n)
    end
    row:Show()
end
