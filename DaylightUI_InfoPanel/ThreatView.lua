-- Contents of a threat window: a header with the mob and your own percent,
-- rows reused from the meters (Rows.lua), and the pull line.
--
-- Your percent is large and colored by DUI.Threat.Level, which uses the plain
-- threat status the game gives even against bosses. The tank's row gets a
-- shield mark. Against bosses the numbers are secret: drawn as-is, never
-- compared, and there's no pull line.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel = DUI.Style, DUI.Pixel

local View = {}
ns.ThreatView = View

View.HEAD = 18                -- the header's height
View.ICON = 12
View.LINE_PX = 2              -- the pull line, physical px
View.GLOW_PX = 10             -- its soft glow, fading in from the left
View.GLOW_ALPHA = 0.45
View.NOTCH = 7                -- the notch on its top
-- Rows: no rank, the icon square for the tank's mark.
View.ROW = { rank = false, icons = "mark", angled = true }

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

local LEVEL_INK = { safe = "GOOD", warn = "WARN", aggro = "BAD" }
View.LEVEL_INK = LEVEL_INK

-- A row's standing from its plain percent of the pull.
function View.LevelOf(scaled)
    if type(scaled) ~= "number" or isSecret(scaled) then return nil end
    if scaled >= 100 then return "aggro" end
    if scaled >= DUI.Threat.WARN_PCT then return "warn" end
    return "safe"
end

function View.New(win)
    local v = { win = win, rows = {} }
    local head = CreateFrame("Frame", nil, win)
    head:SetHeight(View.HEAD)
    v.head = head
    v.icon = head:CreateTexture(nil, "ARTWORK")
    v.icon:SetSize(View.ICON, View.ICON)
    v.icon:SetPoint("LEFT", head, "LEFT", 1, 0)
    v.icon:SetTexture(ns.Meter.ICON("threat"))
    v.mob = Style.Text(head, Style.SIZE.small, "LEFT", ns.MEDIA.fonts.meter)
    v.mob:SetPoint("LEFT", v.icon, "RIGHT", 5, 0)
    v.mob:SetWordWrap(false)
    v.yours = Style.Text(head, Style.SIZE.head, "RIGHT", ns.MEDIA.fonts.meter)
    v.yours:SetPoint("RIGHT", head, "RIGHT", -1, 0)
    v.mob:SetPoint("RIGHT", v.yours, "LEFT", -6, 0)
    v.empty = Style.Text(win, Style.SIZE.body, "CENTER", ns.MEDIA.fonts.meter)
    v.empty:SetText(L["No target"])
    v.empty:Hide()
    -- The pull line: its glow under it, its notch on top, all moved together.
    -- On a layer of its own above the rows (a frame's own textures draw under
    -- its children: the bars hid it).
    v.over = CreateFrame("Frame", nil, win)
    v.over:SetAllPoints(win)
    v.over:SetFrameLevel(win:GetFrameLevel() + 10)
    v.glow = v.over:CreateTexture(nil, "OVERLAY", nil, 5)
    v.line = v.over:CreateTexture(nil, "OVERLAY", nil, 7)
    v.notch = v.over:CreateTexture(nil, "OVERLAY", nil, 7)
    v.notch:SetRotation(math.pi / 4)
    v.glow:SetPoint("TOPRIGHT", v.line, "TOPLEFT", 0, 0)
    v.glow:SetPoint("BOTTOMRIGHT", v.line, "BOTTOMLEFT", 0, 0)
    v.notch:SetPoint("CENTER", v.line, "TOP", 0, 0)
    v.lineParts = { v.line, v.glow, v.notch }
    for _, t in ipairs(v.lineParts) do t:Hide() end
    -- The line's spot, set by a draw or its glide.
    function v.At(px)
        v.lineX = px
        v.line:ClearAllPoints()
        v.line:SetPoint("TOP", v.win, "TOPLEFT", px, -v.rowsTop)
    end
    View.Paint(v)
    return v
end

-- Stops the line's glide where it is: it's going away, or being laid out
-- again (the next showing snaps into place).
local function stopLine(v)
    DUI.Motion.Tween(v.line, 0, 0, 0)
    v.lineX = nil
end

-- Colors read at paint time (a style change repaints).
function View.Paint(v)
    v.icon:SetVertexColor(Style.Accent())
    Style.InkText(v.mob, "TEXT")
    Style.InkText(v.empty, "LABEL")
    -- Your row's outline: lit again in the accent as it is now.
    for _, row in ipairs(v.rows) do row.mine = nil end
    v.lineColor = nil
end

-- Lays out the header and n rows, W wide. Returns the rows' top and the bar's
-- left edge and width, which the pull line is positioned against.
function View.Layout(v, cfg, inset, W, n, gap)
    local win, size = v.win, cfg.textSize
    v.head:ClearAllPoints()
    v.head:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -inset)
    v.head:SetPoint("TOPRIGHT", win, "TOPRIGHT", -inset, -inset)
    v.head:SetShown(cfg.header ~= "off")
    local headH = cfg.header ~= "off" and View.HEAD or 0
    Style.SetTextSize(v.mob, Style.SIZE.small)
    Style.SetTextSize(v.empty, size)
    local rowH = cfg.rowHeight
    local row
    for i = 1, math.max(n, #v.rows) do
        row = v.rows[i]
        if not row and i <= n then
            row = ns.Rows.New(win, size)
            v.rows[i] = row
        end
        if row then
            if i <= n then
                row:ClearAllPoints()
                local y = -(inset + headH + (i - 1) * (rowH + gap))
                row:SetPoint("TOPLEFT", win, "TOPLEFT", inset, y)
                row:SetPoint("TOPRIGHT", win, "TOPRIGHT", -inset, y)
                row:SetHeight(rowH)
                Style.SetTextSize(row.name, size)
                Style.SetTextSize(row.amount, size)
                ns.Rows.Track(row, cfg.trackAlpha)
                View.ROW.angled = cfg.angled ~= false
                ns.Rows.Layout(row, View.ROW)
                row.painted, row.mine, row.iconFile, row.levelInk, row.isTank = nil, nil, false, nil, nil
                row.icon:Hide()
                row.on = row:IsShown()
            else
                row:Hide()
                row.on = false
            end
        end
    end
    v.over:SetFrameLevel(win:GetFrameLevel() + 10)   -- above the rows, whatever level the window took
    local first = v.rows[1]
    local barX = first and first.barX or 0
    local T = first and Pixel.Px(first, ns.Rows.BORDER) or 0
    local px = Pixel.Px(win, View.LINE_PX)
    v.line:SetWidth(px)
    v.glow:SetWidth(View.GLOW_PX)
    v.notch:SetSize(View.NOTCH, View.NOTCH)
    stopLine(v)
    v.lineColor = nil
    return inset + headH, inset + barX, W - 2 * inset - barX - T, headH
end

-- A bar's colors: class (Meter.PaintBar), one color, or its standing.
local paintSrc = {}
local function paintBar(row, e, cfg)
    if cfg.barColor == "threat" then
        local level = View.LevelOf(e.scaled)
        if level then
            local ink = Style.INK[LEVEL_INK[level]]
            if row.levelInk == ink then return end
            row.levelInk = ink
            row.painted = nil
            if cfg.gradient == true and DUI.Gradients then
                DUI.Gradients.PaintFrom(row.bar, ink)
            else
                Style.SetBarColor(row.bar, ink[1], ink[2], ink[3])
            end
            return
        end
    end
    local key = ns.Meter.PaintKey(e.class)
    if key ~= nil and key == row.painted then return end
    row.painted, row.levelInk = key, nil
    paintSrc.classFilename = e.class
    ns.Meter.PaintBar(row.bar, paintSrc, nil, cfg)   -- "threat" with no plain level: the class's
end

-- Draws the list from TM.Collect: rows, your percent and the pull line.
-- `secret` means no reading the numbers and no line. `pull` and `top` are
-- plain. `mobUnit` is the unit to check your standing against. `snap` skips
-- the glide.
function View.Draw(v, cfg, data, secret, pull, top, mob, mobUnit, geo, snap)
    local count = data and #data or 0
    if type(mob) == "nil" then mob = "" end   -- (a secret name: never truth-tested)
    v.mob:SetText(mob)
    -- Yours: your row's percent, colored by your standing (plain even on a boss).
    local mine
    for i = 1, count do if data[i].me then mine = data[i] end end
    if mine then
        if secret then v.yours:SetFormattedText("%.0f%%", mine.scaled)
        else v.yours:SetFormattedText("%d%%", math.floor((mine.scaled or 0) + 0.5)) end
        local level = mobUnit and DUI.Threat.Level("player", mobUnit) or (not secret and View.LevelOf(mine.scaled))
        local ink = level and Style.INK[LEVEL_INK[level]] or Style.INK.VALUE
        v.yours:SetTextColor(ink[1], ink[2], ink[3])
    else
        v.yours:SetText("")
    end
    for i, row in ipairs(v.rows) do
        local e = i <= count and data[i] or nil
        local on = e ~= nil
        if row.on ~= on then
            row.on = on
            row:SetShown(on)
        end
        if e then
            paintBar(row, e, cfg)
            row.name:SetTextColor(ns.Meter.NameColor(e.class, cfg))
            ns.Rows.SetMine(row, e.me == true)
            -- The tank's mark (plain: against a boss the rows come by role instead).
            local tank = not isSecret(e.tank) and e.tank == true
            if tank ~= row.isTank then
                row.isTank = tank
                row.icon:SetTexture(ns.Meter.ICON("tank"))
                local c = Style.INK.LABEL
                row.icon:SetVertexColor(c[1], c[2], c[3])
                row.icon:SetShown(tank)
            end
            if e.me == true then Style.InkText(row.amount, "pop") else Style.InkText(row.amount, "VALUE") end
            row.name:SetText(e.name)
            if secret then
                row.bar:SetMinMaxValues(0, 100)
                row.bar:SetValue(e.scaled)
                row.amount:SetFormattedText("%.0f%%", e.scaled)
            else
                row.bar:SetMinMaxValues(0, top)
                Style.SetBarValue(row.bar, e.value, snap)
                row.amount:SetFormattedText("%d%%", math.floor(e.scaled + 0.5))
            end
        end
    end
    -- The pull line, over the rows: placed straight away the first time
    -- (or on a new target), gliding after.
    local showLine = cfg.pullLine ~= false and not secret and pull ~= nil and count > 0
    for _, t in ipairs(v.lineParts) do t:SetShown(showLine) end
    if not showLine then
        if v.lineX ~= nil then stopLine(v) end
        return
    end
    -- Its colors only when they change (a setting, a style change).
    local c = cfg.pullColor or ns.DEFAULTS.threat.pullColor
    if v.lineColor ~= c then
        v.lineColor = c
        v.line:SetColorTexture(c[1], c[2], c[3], 1)
        v.notch:SetColorTexture(c[1], c[2], c[3], 1)
        v.glow:SetColorTexture(1, 1, 1, 1)
        if CreateColor and v.glow.SetGradient then
            v.glow:SetGradient("HORIZONTAL", CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], View.GLOW_ALPHA))
        else
            v.glow:SetVertexColor(c[1], c[2], c[3], View.GLOW_ALPHA)
        end
    end
    local x = geo.barLeft + geo.barWidth * math.min(1, pull / top)
    v.line:SetHeight(math.max(1, count * (geo.rowH + geo.gap) - geo.gap))
    v.rowsTop = geo.rowsTop
    if snap or v.lineX == nil then
        stopLine(v)
        v.At(x)
    elseif math.abs(v.lineX - x) > 0.01 then
        DUI.Motion.Tween(v.line, v.lineX, x, DUI.Motion.FAST, v.At)
    end
end
