-- Live preview strip at the top of a frame's options page (Player, Target,
-- Party...). The module draws the sample (e.g. DaylightUI_UnitFrames/PageSample.lua)
-- and it redraws with the page, so changes show right away. Each part has a
-- hotspot: hover outlines it, click jumps to its settings via onJump.
--
-- In Design mode, parts with part.move can be dragged. Their anchor spots show
-- as dots, and part.move.drop decides where a drop lands; the result goes to
-- onMove({ {key, value} }). Clicking selects a part, then arrow keys nudge it
-- 1 px (Shift for Strip.NUDGE_BIG).
--
-- Samples can offer views (sample.Views / sample.SetView), such as a nameplate
-- in execute range. Each one gets a toggle chip at the top right; with
-- sample.viewsExclusive one is always on and picking another switches to it.
-- sample.hint replaces the line under it, for a sample with nothing to click.
--
-- A list move (part.move.list) is for pieces in a column, such as the rows of a
-- tooltip card: they go up or down, not anywhere. While one is dragged it rides
-- under the cursor in a lifted box, a line in the accent shows the slot it would
-- land in (part.move.slots()), and letting go calls part.move.place(id); the
-- arrow keys call part.move.step(dir). Strip.NewTray is a box such a sample can
-- show its switched-off pieces in.

local _, DUI = ...
local W = DUI.Widgets
local SIZE = DUI.Style.SIZE
local C = W.COLORS
local L = DUI.L

local Strip = {}
DUI.SampleStrip = Strip

Strip.MAX_HEIGHT = 220   -- sample height cap, shrinks to fit
Strip.MIN_HEIGHT = 120   -- floor, however short the window
Strip.SHARE = 0.3        -- fraction of the window's height
Strip.DESIGN_MAX = 320   -- Design mode gets a bigger stage
Strip.DESIGN_SHARE = 0.45

-- Sample height for a window this tall.
function Strip.Room(windowHeight, design)
    local h = math.floor((tonumber(windowHeight) or 0) * (design and Strip.DESIGN_SHARE or Strip.SHARE))
    return math.max(Strip.MIN_HEIGHT, math.min(design and Strip.DESIGN_MAX or Strip.MAX_HEIGHT, h))
end
Strip.PAD = 10           -- padding around the sample
Strip.HINT_HEIGHT = 16   -- help line under the sample
Strip.LAYER = 50         -- hotspot frame level offset, above every part
-- Its words, once the picked language is on (Locales.lua).
DUI.WithLanguage(function()
    Strip.HINT = L["Click any part to jump to its settings."]
    Strip.DESIGN_HINT = L["Drag a piece to move it. Click it for its settings; the arrow keys then nudge it."]
    Strip.TIP = L["Click to jump to its settings."]
    Strip.DESIGN_EMPTY = L["Click a piece of the preview to see its settings here."]
    Strip.ALL = L["Every setting for this piece"]
    Strip.ADD = L["+ Add piece"]
    Strip.DESIGN_TIP = L["Drag to move it, or click for its settings."]
    Strip.NEW_SECTION = L["New section"]
    Strip.HIDDEN = L["Hidden"]
end)
Strip.DRAG_START = 4     -- px of movement before a press becomes a drag
Strip.DOT = 5            -- spot dot size; the nearest one is DOT_NEAR
Strip.DOT_NEAR = 8
Strip.DOT_ALPHA = 0.3
Strip.DOT_NEAR_ALPHA = 0.8
Strip.NUDGE_BIG = 5      -- px per arrow key with Shift held
Strip.ZOOM_WIDTH = 190   -- zoom slider including label and number
Strip.GRIP = 8           -- resize grip size; edge grips are GRIP x GRIP_LONG
Strip.GRIP_LONG = 14
-- A list move.
Strip.LINE = 2           -- the insert line's thickness
Strip.REACH = 40         -- px either side of the list a drop still counts
Strip.LIFT_FILL = 0.12   -- the lifted piece's accent wash
Strip.HOVER_ALPHA = 0.45 -- a list piece's dashed outline under the mouse
Strip.DASH, Strip.DASH_GAP = 4, 3
Strip.DOTS_W, Strip.DOTS_H = 6, 12  -- a list piece's grip: two columns of four dots
-- The tray of hidden pieces.
Strip.TRAY_MIN = 44
Strip.TRAY_PAD = 10
Strip.TRAY_GAP = 6
Strip.TRAY_ITEM_X, Strip.TRAY_ITEM_Y = 10, 3
Strip.TRAY_HEAD = 18     -- its heading's row

local Style = DUI.Style
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- A 1 px dashed outline around a frame, drawn with short pieces laid along
-- its edges again whenever it changes size. d.Paint(color, alpha).
function Strip.Dashes(frame, layer)
    local d = { pieces = {}, frame = frame, count = 0 }
    local function piece(i)
        local t = d.pieces[i]
        if not t then
            t = frame:CreateTexture(nil, layer or "OVERLAY", nil, 6)
            t:SetTexture(WHITE)
            d.pieces[i] = t
        end
        t:Show()
        return t
    end
    -- w, h: its size when it isn't laid out yet (just anchored).
    function d.Layout(w, h)
        w, h = w or frame:GetWidth(), h or frame:GetHeight()
        if type(w) ~= "number" or type(h) ~= "number" then return end
        local one = DUI.Pixel.Px(frame, 1)
        local step = Strip.DASH + Strip.DASH_GAP
        local n = 0
        local function run(len, place)
            local at = 0
            while at < len do
                n = n + 1
                place(piece(n), at, math.min(Strip.DASH, len - at))
                at = at + step
            end
        end
        run(w, function(t, at, l)
            t:ClearAllPoints(); t:SetSize(l, one); t:SetPoint("TOPLEFT", frame, "TOPLEFT", at, 0)
        end)
        run(w, function(t, at, l)
            t:ClearAllPoints(); t:SetSize(l, one); t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", at, 0)
        end)
        run(h, function(t, at, l)
            t:ClearAllPoints(); t:SetSize(one, l); t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -at)
        end)
        run(h, function(t, at, l)
            t:ClearAllPoints(); t:SetSize(one, l); t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -at)
        end)
        for i = n + 1, #d.pieces do d.pieces[i]:Hide() end
        d.count = n
        if d.color then d.Paint(d.color, d.alpha) end
        if d.shown == false then d.SetShown(false) end
    end
    function d.Paint(c, alpha)
        d.color, d.alpha = c, alpha
        for i = 1, d.count do d.pieces[i]:SetVertexColor(c[1], c[2], c[3], alpha or 1) end
    end
    function d.SetShown(on)
        d.shown = on
        for i = 1, d.count do d.pieces[i]:SetShown(on) end
    end
    function d.Shown() return d.shown == true and d.count > 0 end
    return d
end

-- A grip: two columns of four dots, the sign that a piece can be dragged.
function Strip.Grip(parent, layer)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(Strip.DOTS_W, Strip.DOTS_H)
    g:EnableMouse(false)
    g.dots = {}
    for col = 0, 1 do
        for row = 0, 3 do
            local t = g:CreateTexture(nil, layer or "OVERLAY", nil, 7)
            t:SetTexture(WHITE)
            t:SetSize(2, 2)
            t:SetPoint("TOPLEFT", g, "TOPLEFT", col * 4, -row * 3.3)
            g.dots[#g.dots + 1] = t
        end
    end
    function g.Paint(c, alpha)
        for _, t in ipairs(g.dots) do t:SetVertexColor(c[1], c[2], c[3], alpha or 1) end
    end
    g.Paint(Style.INK.LABEL)
    return g
end

-- The tray a sample shows its switched-off pieces in: a heading, then a
-- dashed box holding one small box per piece, wrapping. tray.Set(labels,
-- width) lays them out and returns the boxes in order (each a hotspot's
-- region); tray:GetHeight() is the whole tray's.
function Strip.NewTray(parent)
    local tray = CreateFrame("Frame", nil, parent)
    tray.head = Style.Text(tray, Style.SIZE.small, "LEFT")
    tray.head:SetPoint("TOPLEFT", tray, "TOPLEFT", 0, 0)
    tray.box = CreateFrame("Frame", nil, tray)
    tray.box:SetPoint("TOPLEFT", tray, "TOPLEFT", 0, -Strip.TRAY_HEAD)
    tray.box:SetPoint("TOPRIGHT", tray, "TOPRIGHT", 0, -Strip.TRAY_HEAD)
    tray.dashes = Strip.Dashes(tray.box, "BORDER")
    tray.items = {}
    local function item(i)
        local b = tray.items[i]
        if b then return b end
        b = CreateFrame("Frame", nil, tray.box)
        -- A square 1 px outline, as the card's own lines are.
        b.edge = {}
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = b:CreateTexture(nil, "BORDER")
            t:SetTexture(WHITE)
            t:SetPoint(side[1], b, side[1], 0, 0)
            t:SetPoint(side[2], b, side[2], 0, 0)
            b.edge[#b.edge + 1] = t
        end
        b.grip = Strip.Grip(b)
        b.grip:SetPoint("LEFT", b, "LEFT", Strip.TRAY_ITEM_X - 4, 0)
        b.text = Style.Text(b, Style.SIZE.small, "LEFT")
        b.text:SetPoint("LEFT", b.grip, "RIGHT", 6, 0)
        tray.items[i] = b
        return b
    end
    function tray.Set(labels, width)
        tray:SetWidth(width)
        tray.head:SetText(Style.Upper(Strip.HIDDEN or "Hidden"))
        Style.InkText(tray.head, "pop")
        local inner = width - 2 * Strip.TRAY_PAD
        local x, y, rowH = 0, 0, 0
        local out = {}
        for i, label in ipairs(labels) do
            local b = item(i)
            b.text:SetText(label)
            Style.InkText(b.text, "OFF")
            local tw = b.text:GetStringWidth()
            tw = type(tw) == "number" and tw or 0
            local h = Style.SIZE.small + 4 + 2 * Strip.TRAY_ITEM_Y
            local w = math.min(inner, tw + Strip.DOTS_W + 6 + 2 * Strip.TRAY_ITEM_X)
            if x > 0 and x + w > inner then x, y = 0, y + rowH + Strip.TRAY_GAP end
            b:SetSize(w, h)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", tray.box, "TOPLEFT", Strip.TRAY_PAD + x, -(Strip.TRAY_PAD + y))
            local one = DUI.Pixel.Px(b, 1)
            for k, t in ipairs(b.edge) do
                if k <= 2 then t:SetHeight(one) else t:SetWidth(one) end
                W.Tint(t, Style.BAND_LIT)
            end
            b:Show()
            x, rowH = x + w + Strip.TRAY_GAP, math.max(rowH, h)
            out[i] = b
        end
        for i = #labels + 1, #tray.items do tray.items[i]:Hide() end
        local boxH = math.max(Strip.TRAY_MIN, (#labels > 0 and (y + rowH) or 0) + 2 * Strip.TRAY_PAD)
        tray.box:SetHeight(boxH)
        tray:SetHeight(Strip.TRAY_HEAD + boxH)
        tray.dashes.Layout(width, boxH)
        tray.dashes.Paint(Style.BAND_LIT, 1)
        tray.dashes.SetShown(true)
        return out
    end
    return tray
end

-- Over a FontString, cover just the letters, not the whole line it spans.
-- scale is the text's frame scale, since hotspots themselves aren't scaled.
local function cover(b, region, scale)
    b:ClearAllPoints()
    if region:GetObjectType() == "FontString" then
        local w, h = region:GetStringWidth(), region:GetStringHeight()
        w = type(w) == "number" and w or 0
        h = type(h) == "number" and h or 0
        b:SetSize((math.max(w, 12) + 6) * scale, (math.max(h, 10) + 4) * scale)
        local j = region:GetJustifyH()
        local point = (j == "LEFT" or j == "RIGHT") and j or "CENTER"
        b:SetPoint(point, region, point, 0, 0)
    else
        b:SetAllPoints(region)
    end
end

-- Cursor position in owner's px from its top left, y down. nil if the owner
-- isn't laid out yet.
local function cursorIn(owner)
    local cx, cy = GetCursorPosition()
    local s = owner:GetEffectiveScale()
    local left, top = owner:GetLeft(), owner:GetTop()
    if not (cx and cy and left and top and s and s > 0) then return nil end
    return cx / s - left, top - cy / s
end

-- Center of a set of regions (a row of icons counts as one piece), in the
-- same coordinates as cursorIn.
local function middleIn(owner, regions)
    local os = owner:GetEffectiveScale()
    local left, top = owner:GetLeft(), owner:GetTop()
    if not (left and top and os and os > 0) then return nil end
    local l, r, b, t
    for _, region in ipairs(regions) do
        local rl, rb, rw, rh = region:GetRect()
        if type(rl) == "number" and type(rw) == "number" then
            local k = region:GetEffectiveScale() / os
            rl, rb, rw, rh = rl * k, rb * k, rw * k, rh * k
            l, b = math.min(l or rl, rl), math.min(b or rb, rb)
            r, t = math.max(r or rl + rw, rl + rw), math.max(t or rb + rh, rb + rh)
        end
    end
    if not l then return nil end
    return (l + r) / 2 - left, top - (b + t) / 2
end

-- Creates the strip, hidden. strip.SetPage(page) shows the page's sample, or
-- hides the strip if the page has none. strip.Redraw(width) redraws it and
-- re-places the hotspots. Callbacks: onJump(keys) on a part click,
-- onMove(changes) after a Design mode drag, onAll(keys) for the
-- "Every setting for this piece" link.
function Strip.New(parent, onJump, onMove, onAll)
    local strip = CreateFrame("Frame", nil, parent)
    strip.bg = W.Round(strip, "BACKGROUND")
    strip.bg:SetAllPoints(strip)
    W.Tint(strip.bg, C.stage)
    strip.edge = W.Round(strip, "BORDER", 0, true)
    strip.edge:SetAllPoints(strip)
    W.Tint(strip.edge, C.cardEdge)
    strip.hint = W.Font(strip, W.BODY, SIZE.small, C.faint)
    strip.hint:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", Strip.PAD + 2, 6)
    strip.hint:SetText(Strip.HINT)
    -- Hotspot layer, kept above every part of the sample.
    strip.layer = CreateFrame("Frame", nil, strip)
    strip.layer:SetAllPoints(strip)
    -- Design mode link back to the selected piece's settings.
    strip.all = W.Link(strip)
    strip.all.SetLabel(Strip.ALL .. "  >")
    strip.all:SetHeight(Strip.HINT_HEIGHT)
    strip.all:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -Strip.PAD - 2, -6)
    strip.all:Hide()
    -- Zoom slider, for samples that support sample.SetZoom.
    local sample   -- current sample, set by SetPage
    strip.zoom = CreateFrame("Frame", nil, strip)
    strip.zoom:SetSize(Strip.ZOOM_WIDTH, Strip.HINT_HEIGHT + 6)
    strip.zoom:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -Strip.PAD, 2)
    strip.zoom:SetFrameLevel(strip:GetFrameLevel() + Strip.LAYER + 210)
    strip.zoom.label = W.Font(strip.zoom, W.BODY, SIZE.small, C.faint, "RIGHT")
    strip.zoom.label:SetPoint("LEFT", strip.zoom, "LEFT", 0, 0)
    strip.zoom.label:SetText(L["Zoom"])
    strip.zoom.item = { type = "slider", label = "Zoom", min = 1, max = 4, step = 0.5, unit = "x",
        get = function() return sample and sample.Zoom and sample.Zoom() or 1 end,
        set = function(v)
            if not (sample and sample.SetZoom) then return end
            sample.SetZoom(v)
            -- Relayout the whole page so content below follows the new height.
            if strip.onZoom then strip.onZoom()
            elseif strip.lastWidth then strip.Redraw(strip.lastWidth, strip.lastRoom) end
        end }
    W.slider(strip.zoom, nil, strip.zoom.item)
    strip.zoom.control:ClearAllPoints()
    strip.zoom.control:SetPoint("RIGHT", strip.zoom, "RIGHT", 0, 0)
    strip.zoom.control:SetWidth(Strip.ZOOM_WIDTH - 46)
    strip.zoom:Hide()
    -- Design mode "+ Add piece" chip. The new piece comes out selected
    -- (strip.onAdded).
    strip.add = W.Chip(strip, Strip.ADD)
    strip.add.FitWidth()
    strip.add:SetPoint("TOPLEFT", strip, "TOPLEFT", Strip.PAD, -6)
    strip.add:SetFrameLevel(strip:GetFrameLevel() + Strip.LAYER + 210)
    strip.add:Hide()
    strip.views = {}     -- view chips, reused
    -- A list move's insert line, and the box a dragged piece rides in.
    strip.insert = CreateFrame("Frame", nil, strip.layer)
    strip.insert:SetHeight(Strip.LINE)
    strip.insert.line = strip.insert:CreateTexture(nil, "OVERLAY", nil, 6)
    strip.insert.line:SetAllPoints(strip.insert)
    strip.insert.line:SetTexture(WHITE)
    strip.insert.back = strip.insert:CreateTexture(nil, "OVERLAY", nil, 5)
    strip.insert.back:SetTexture(WHITE)
    strip.insert.word = Style.Text(strip.insert, Style.SIZE.tiny, "RIGHT")
    strip.insert.word:SetPoint("RIGHT", strip.insert, "RIGHT", -6, 0)
    strip.insert.back:SetPoint("TOPLEFT", strip.insert.word, "TOPLEFT", -6, 1)
    strip.insert.back:SetPoint("BOTTOMRIGHT", strip.insert.word, "BOTTOMRIGHT", 6, -1)
    strip.insert:Hide()
    strip.lift = CreateFrame("Frame", nil, strip.layer)
    strip.lift.shell = Style.Shell(strip.lift, { noBevel = true, borderPx = 1, bgAlpha = 1 })
    strip.lift.wash = strip.lift:CreateTexture(nil, "ARTWORK", nil, 1)
    strip.lift.wash:SetTexture(WHITE)
    strip.lift.wash:SetAllPoints(strip.lift)
    strip.lift:Hide()
    strip:Hide()

    local samples = {}   -- page id -> sample
    local spots = {}     -- hotspot buttons, reused
    local dots = {}      -- dot textures, reused
    local press          -- { b, x, y, dragging } while a hotspot is held
    local selected       -- selected part's label (Design mode)

    local function hideDots()
        for _, d in ipairs(dots) do d:Hide() end
    end

    -- Shows a part's spot dots, with the one nearest the cursor enlarged.
    local function showDots(part, near)
        local m = part.move
        local r = m.owner:GetEffectiveScale() / strip.layer:GetEffectiveScale()
        for i, d in ipairs(m.dots) do
            local t = dots[i]
            if not t then
                t = W.Round(strip.layer, "OVERLAY", 7)
                dots[i] = t
            end
            local size = d.spot == near and Strip.DOT_NEAR or Strip.DOT
            t:SetSize(size, size)
            t:ClearAllPoints()
            t:SetPoint("CENTER", m.owner, "TOPLEFT", d.x * r, -d.y * r)
            W.TintDaylight(t, d.spot == near and Strip.DOT_NEAR_ALPHA or Strip.DOT_ALPHA)
            t:Show()
        end
        for i = #m.dots + 1, #dots do dots[i]:Hide() end
    end

    -- A list piece in Design mode shows a dashed outline and its grip; the
    -- picked one's dashes are in the accent.
    local function listed(b) return strip.design and b.part ~= nil and b.part.move ~= nil and b.part.move.list end
    local function lit(b)
        if listed(b) then
            b.dashes.Layout()
            local on = selected == b.part.label
            b.dashes.Paint(on and { Style.Accent() } or Style.INK.LABEL, on and 1 or Strip.HOVER_ALPHA)
            b.dashes.SetShown(true)
            b.grip:Show()
            return
        end
        W.TintDaylight(b.outline)
        DUI.Motion.AlphaTo(b.outline, 1, DUI.Motion.FAST)
    end

    -- Resize grips for the selected part (part.size): a corner grip for a
    -- single size (s), edge grips for width (w) and height (h). The value
    -- shows while dragging and is saved through onMove on release.
    local grips, gripPress = {}, nil
    local gripLabel = W.Font(strip.layer, W.BODY, SIZE.tiny, C.text)
    gripLabel:Hide()

    local function gripValue(p, cx, cy)
        local g = p.g
        local z, s = g.part.size, g.part.region:GetEffectiveScale()
        local d = g.kind == "h" and (p.y - cy) / s or (cx - p.x) / s
        local one = g.kind == "s"
        return z.resize(p.start, d, one and z.min or z.min[g.kind], one and z.max or z.max[g.kind],
            one and z.step or z.step[g.kind]), d
    end

    -- Settings written for grip value v, plus a linked setting
    -- (part.size.link) moved by the same amount, both clamped. Uses the
    -- values captured at press time because live redraws change the part.
    local function gripChanges(g, v, p)
        local z = g.part.size
        local out = { { z.keys[g.kind], v } }
        local l = z.link and z.link[g.kind]
        if l and type(p.linkStart) == "number" and type(p.start) == "number" then
            local want = p.linkStart + (v - p.start)
            local got = math.max(l.min or want, math.min(l.max or want, want))
            out[1][2] = p.start + (got - p.linkStart)
            out[2] = { l.key, got }
        end
        return out
    end

    -- Redraws the preview on every change (strip.onPreview writes silently).
    -- The real frames only update on release.
    local function onGripUpdate()
        local p = gripPress
        if not p then return end
        local cx, cy = GetCursorPosition()
        local v, d = gripValue(p, cx or 0, cy or 0)
        if not p.moved and math.abs(d) < 0.5 then return end
        local changed = v ~= (p.value or p.start)
        p.moved, p.value = true, v
        if changed and strip.onPreview and strip.lastWidth then
            for _, c in ipairs(gripChanges(p.g, v, p)) do strip.onPreview(c[1], c[2]) end
            strip.Redraw(strip.lastWidth, strip.lastRoom)
        end
        gripLabel:SetText(tostring(v))
        gripLabel:ClearAllPoints()
        gripLabel:SetPoint("BOTTOMLEFT", p.g, "TOPRIGHT", 2, 2)
        gripLabel:Show()
    end

    local function makeGrip(kind)
        local g = CreateFrame("Button", nil, strip.layer)
        g.kind = kind
        g:SetSize(kind == "w" and Strip.GRIP / 2 + 1 or (kind == "h" and Strip.GRIP_LONG or Strip.GRIP),
                  kind == "h" and Strip.GRIP / 2 + 1 or (kind == "w" and Strip.GRIP_LONG or Strip.GRIP))
        g.tex = W.Round(g, "OVERLAY", 7)
        g.tex:SetAllPoints(g)
        W.TintDaylight(g.tex)
        g:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local cx, cy = GetCursorPosition()
            local link = self.part.size.link and self.part.size.link[self.kind]
            gripPress = { g = self, x = cx or 0, y = cy or 0, start = self.part.size.now[self.kind],
                          linkStart = link and link.now }
            strip:SetScript("OnUpdate", onGripUpdate)
        end)
        g:SetScript("OnMouseUp", function(self) strip.EndGrip(true) end)
        g:Hide()
        return g
    end
    -- Ends a grip drag. save = false drops it unsaved, e.g. on a page switch.
    function strip.EndGrip(save)
        local p = gripPress
        gripPress = nil
        strip:SetScript("OnUpdate", nil)
        gripLabel:Hide()
        if save and p and p.moved and p.value ~= nil and p.value ~= p.start and onMove then
            onMove(gripChanges(p.g, p.value, p))
        end
    end
    grips = { s = makeGrip("s"), w = makeGrip("w"), h = makeGrip("h") }

    -- View chips run right to left from the top right corner, left of the
    -- "Every setting for this piece" link when it shows.
    local function placeViews()
        local list = sample and sample.Views and sample.Views() or {}
        local right, rightPoint, gap = strip, "TOPRIGHT", 0
        if strip.all:IsShown() then right, rightPoint, gap = strip.all.text, "TOPLEFT", -10 end
        for i, v in ipairs(list) do
            local c = strip.views[i]
            if not c then
                c = W.Chip(strip, "")
                c:SetFrameLevel(strip:GetFrameLevel() + Strip.LAYER + 210)
                c:SetScript("OnClick", function(self)
                    if not (sample and sample.SetView) then return end
                    -- With one always on, a click picks it (a second click keeps it).
                    sample.SetView(self.viewKey, sample.viewsExclusive == true or not self.viewOn)
                    -- A view can change the sample's height: relayout the page below it too.
                    if strip.onZoom then strip.onZoom()
                    elseif strip.lastWidth then strip.Redraw(strip.lastWidth, strip.lastRoom) end
                end)
                strip.views[i] = c
            end
            c.viewKey, c.viewOn = v.key, v.on == true
            c.text:SetText(v.label)
            c.FitWidth()
            c.SetOn(c.viewOn)
            c:ClearAllPoints()
            if right == strip then
                c:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -Strip.PAD, -6)
            else
                c:SetPoint("TOPRIGHT", right, rightPoint, gap, right == strip.all.text and 2 or 0)
            end
            right, rightPoint, gap = c, "TOPLEFT", -6
            c:Show()
        end
        for i = #list + 1, #strip.views do strip.views[i]:Hide() end
    end
    function strip.ViewChips() return strip.views end

    -- Arrow keys while a movable piece is selected. Uses the window kit's
    -- key handling, so other keys pass through and nothing is held in combat.
    local keysOn = false
    local function setKeys(on)
        on = on == true
        if on == keysOn then return end
        keysOn = on
        DUI.Win.KeysOn(strip, on)
    end

    local function nudge(key)
        local arrow = DUI.Movers.ARROWS[key]
        if not arrow or press or not strip.onRead or not onMove then return false end
        local part = strip.SelectedPart()
        local m = part and part.move
        if not m then return false end
        if m.list then
            -- Up and down: one slot at a time.
            if arrow[2] == 0 or not m.step then return false end
            local changes = m.step(-arrow[2])
            if changes and #changes > 0 then onMove(changes) end
            if strip.lastWidth then strip.Redraw(strip.lastWidth, strip.lastRoom) end
            return true
        end
        local step = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true and Strip.NUDGE_BIG or 1
        local changes = {}
        local function add(k, by)
            if k and by ~= 0 then changes[#changes + 1] = { k, (tonumber(strip.onRead(k)) or 0) + by * step } end
        end
        add(m.xKey, arrow[1])
        add(m.yKey, arrow[2])
        if #changes == 0 then return false end
        onMove(changes)
        if strip.lastWidth then strip.Redraw(strip.lastWidth, strip.lastRoom) end
        return true
    end
    DUI.Win.Keys(strip, nudge)

    local function placeGrips()
        local host
        if strip.design and selected then
            for _, b in ipairs(spots) do
                if b:IsShown() and b.part.label == selected and b.part.size then
                    host = b
                    break
                end
            end
        end
        strip.all:SetShown(strip.design == true and selected ~= nil)
        strip.add:SetShown(strip.design == true and sample ~= nil and sample.Adds ~= nil)
        local part = strip.design and strip.SelectedPart()
        setKeys(part and part.move ~= nil and ((part.move.xKey or part.move.yKey) ~= nil or part.move.step ~= nil))
        placeViews()
        local POINT = { s = "BOTTOMRIGHT", w = "RIGHT", h = "BOTTOM" }
        for kind, g in pairs(grips) do
            if host and host.part.size.keys[kind] then
                g.part = host.part
                g:ClearAllPoints()
                g:SetPoint("CENTER", host, POINT[kind], 0, 0)
                g:SetFrameLevel(strip.layer:GetFrameLevel() + 200)
                g:Show()
            else
                g:Hide()
            end
        end
    end

    -- Hotspots that move along with b: same piece on the same frame, like a
    -- row of debuff icons. Each keeps its offset from b so the row holds shape.
    local function matesOf(b)
        local out = {}
        local bx, by = b.part.region:GetCenter()
        for _, o in ipairs(spots) do
            if o:IsShown() and o.part.label == b.part.label and o.part.move
               and o.part.move.owner == b.part.move.owner then
                local ox, oy = o.part.region:GetCenter()
                local known = type(bx) == "number" and type(ox) == "number"
                out[#out + 1] = { b = o, dx = known and ox - bx or 0, dy = known and oy - by or 0 }
            end
        end
        return out
    end

    -- A press that moves past DRAG_START on a movable part in Design mode
    -- becomes a drag. The piece follows the cursor, held where it was grabbed.
    local function regionsOf(mates)
        local out = {}
        for _, m in ipairs(mates) do out[#out + 1] = (m.b or m).part.region end
        return out
    end

    -- Whether the cursor is over a region (a box slot: the tray).
    local function over(region)
        local cx, cy = GetCursorPosition()
        local s = region:GetEffectiveScale()
        local l, b, w, h = region:GetRect()
        if not (cx and type(l) == "number" and type(w) == "number" and s and s > 0) then return false end
        cx, cy = cx / s, cy / s
        return cx >= l and cx <= l + w and cy >= b and cy <= b + h
    end

    -- The slot a list piece would land in: a box under the cursor, else the
    -- nearest line by height while the cursor is over the list (or REACH
    -- either side of it). nil anywhere else.
    local function nearestSlot(m)
        local slots = m.slots()
        for _, sl in ipairs(slots) do
            if sl.region and sl.region:IsShown() and over(sl.region) then return sl end
        end
        local x, y = cursorIn(m.owner)
        local w, h = m.owner:GetWidth(), m.owner:GetHeight()
        if not x or type(w) ~= "number" or x < -Strip.REACH or x > w + Strip.REACH
            or y < -Strip.REACH or y > h + Strip.REACH then
            return nil
        end
        local best, dist
        for _, sl in ipairs(slots) do
            if not sl.region then
                local d = math.abs(y - sl.y)
                if not dist or d < dist then best, dist = sl, d end
            end
        end
        return best
    end
    strip.NearestSlot = nearestSlot

    -- The insert line on a slot, gliding there from the last one.
    local function showLine(m, sl)
        local line = strip.insert
        if not sl or sl.region then
            line:Hide()
            line.at = nil
            return
        end
        local r = m.owner:GetEffectiveScale() / strip.layer:GetEffectiveScale()
        local was = line:IsShown() and line.at
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", m.owner, "TOPLEFT", sl.x * r, -(sl.y * r - Strip.LINE / 2))
        line:SetWidth(sl.w * r)
        line:SetFrameLevel(strip.layer:GetFrameLevel() + 205)
        Style.PaintAccent(line.line, 1)
        line.word:SetShown(sl.new == true)
        line.back:SetShown(sl.new == true)
        if sl.new then
            line.word:SetText(Style.Upper(Strip.NEW_SECTION or "New section"))
            Style.InkText(line.word, "pop")
            W.Tint(line.back, Style.BACKGROUND)
        end
        line:Show()
        if was and was ~= sl.y then DUI.Motion.Glide(line, 0, (sl.y - was) * r, DUI.Motion.FAST) end
        line.at = sl.y
    end

    -- The dragged piece's box: the accent outline, a faint accent wash over
    -- the background, a shadow; the sample draws the piece inside it.
    local function lift(b, on)
        local L = strip.lift
        local m = b.part.move
        if not on then
            if L:IsShown() and m.lift then m.lift(nil) end
            L:Hide()
            return
        end
        local r = b.part.region
        local w, h = r:GetWidth(), r:GetHeight()
        local k = r:GetEffectiveScale() / strip.layer:GetEffectiveScale()
        L:SetSize((w or 1) * k, (h or 1) * k)
        L:SetFrameLevel(strip.layer:GetFrameLevel() + 190)
        local c = { Style.Accent() }
        Style.SetShellColors(L.shell, c)
        Style.LayoutShell(L.shell)
        W.Tint(L.wash, c, Strip.LIFT_FILL)
        L:Show()
        if m.lift then m.lift(L) end
    end

    local function listUpdate(b, cx, cy)
        local s = strip.layer:GetEffectiveScale()
        local L = strip.lift
        L:ClearAllPoints()
        L:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s + press.gx, cy / s + press.gy)
        showLine(b.part.move, nearestSlot(b.part.move))
    end

    local function onUpdate()
        if not press then return end
        local b = press.b
        local cx, cy = GetCursorPosition()
        if not press.dragging then
            local dx, dy = (cx or 0) - press.x, (cy or 0) - press.y
            local s = strip.layer:GetEffectiveScale()
            if (dx * dx + dy * dy) / (s * s) < Strip.DRAG_START * Strip.DRAG_START then return end
            if not (strip.design and b.part.move) then return end
            press.dragging = true
            W.HideTooltip()
            if b.part.move.list then
                -- Held where it was grabbed, in the strip's own units.
                local r = b.part.region
                local mx, my = r:GetCenter()
                local k = r:GetEffectiveScale() / strip.layer:GetEffectiveScale()
                local s = strip.layer:GetEffectiveScale()
                press.gx = type(mx) == "number" and mx * k - press.x / s or 0
                press.gy = type(my) == "number" and my * k - press.y / s or 0
                lift(b, true)
            end
            -- Grab offset from the piece's center, in its own units.
            local r = b.part.region
            local rs = r:GetEffectiveScale()
            local mx, my = r:GetCenter()
            press.gx = type(mx) == "number" and mx - press.x / rs or 0
            press.gy = type(my) == "number" and my - press.y / rs or 0
            if not b.part.move.list then press.mates = matesOf(b) end
        end
        if b.part.move.list then return listUpdate(b, cx or 0, cy or 0) end
        local rs = b.part.region:GetEffectiveScale()
        for _, m in ipairs(press.mates) do
            local r = m.b.part.region
            r:ClearAllPoints()
            r:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / rs + press.gx + m.dx, cy / rs + press.gy + m.dy)
            lit(m.b)
        end
        local x, y = middleIn(b.part.move.owner, regionsOf(press.mates))
        if not x then x, y = cursorIn(b.part.move.owner) end   -- not laid out yet, use the cursor
        if x then showDots(b.part, (b.part.move.drop(x, y))) end
    end

    -- A piece's regions as currently drawn, found by label and owner.
    local function drawn(label, owner)
        local out = {}
        for _, o in ipairs(spots) do
            if o:IsShown() and o.part.label == label and o.part.move and o.part.move.owner == owner then
                out[#out + 1] = o.part.region
            end
        end
        return out
    end

    local function release(b)
        local p = press
        press = nil
        strip:SetScript("OnUpdate", nil)
        hideDots()
        if not (p and p.dragging) then
            if p and strip.design then
                selected = b.part.label
                placeGrips()
            end
            return
        end
        b.dragged = true   -- so the OnClick that follows is ignored
        local m, label = b.part.move, b.part.label
        if m.list then
            -- Dropped on a slot: the sample says what that changes. Anywhere
            -- else nothing changes.
            local sl = nearestSlot(m)
            lift(b, false)
            strip.insert:Hide()
            strip.insert.at = nil
            selected = label
            local changes = sl and m.place(sl.id)
            if changes and #changes > 0 and onMove then onMove(changes) end
            if strip.Redraw and strip.lastWidth then strip.Redraw(strip.lastWidth, strip.lastRoom) end
            return
        end
        -- Snap to the dot nearest the piece's center. Each spot anchors the
        -- piece differently (a row's pinned end, a corner...), so after saving
        -- the piece is measured again and the nudge corrected. It ends up where
        -- it was dropped, or centered on the dot it snapped to.
        local x, y = middleIn(m.owner, regionsOf(p.mates))
        if not x then x, y = cursorIn(m.owner) end   -- not laid out yet, use the cursor
        local redraw = strip.Redraw and strip.lastWidth and function() strip.Redraw(strip.lastWidth, strip.lastRoom) end
        if x then
            local spot, nx, ny = m.drop(x, y)
            if spot and nx == 0 and ny == 0 then
                for _, d in ipairs(m.dots) do
                    if d.spot == spot then x, y = d.x, d.y break end
                end
            end
            local changes = {}   -- without a spotKey the piece only nudges
            if m.spotKey then changes[1] = { m.spotKey, spot } end
            if m.xKey then changes[#changes + 1] = { m.xKey, nx } end
            if m.yKey then changes[#changes + 1] = { m.yKey, ny } end
            selected = label
            if spot and onMove then
                onMove(changes)
                if redraw and (m.xKey or m.yKey) then
                    redraw()
                    local lx, ly = middleIn(m.owner, drawn(label, m.owner))
                    if lx then
                        local dx, dy = math.floor(x - lx + 0.5), math.floor(ly - y + 0.5)
                        local fix = {}
                        if m.xKey and dx ~= 0 then fix[#fix + 1] = { m.xKey, nx + dx } end
                        if m.yKey and dy ~= 0 then fix[#fix + 1] = { m.yKey, ny + dy } end
                        if #fix > 0 then onMove(fix) end
                    end
                end
            end
        end
        if redraw then redraw() end
    end

    local function hotspot(i)
        if spots[i] then return spots[i] end
        local b = CreateFrame("Button", nil, strip.layer)
        b.outline = W.Round(b, "OVERLAY", 7, true)
        b.outline:SetAllPoints(b)
        b.outline:Hide()
        b.dashes = Strip.Dashes(b)
        b.grip = Strip.Grip(b)
        b.grip:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.grip:Hide()
        b:SetScript("OnEnter", function(self)
            lit(self)
            W.Tooltip(self, DUI.Options.Text(self.part.label), strip.design and self.part.move and Strip.DESIGN_TIP or Strip.TIP)
        end)
        b:SetScript("OnLeave", function(self)
            if press and press.b == self then return end
            if not (strip.design and selected == self.part.label) then
                DUI.Motion.AlphaTo(self.outline, 0, DUI.Motion.FAST, true)
                self.dashes.SetShown(false)
                self.grip:Hide()
            end
            W.HideTooltip()
        end)
        b:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local cx, cy = GetCursorPosition()
            press = { b = self, x = cx or 0, y = cy or 0 }
            strip:SetScript("OnUpdate", onUpdate)
        end)
        b:SetScript("OnMouseUp", function(self) release(self) end)
        b:SetScript("OnClick", function(self)
            if self.dragged then
                self.dragged = nil
                return
            end
            if strip.design then
                selected = self.part.label
                placeGrips()
            end
            onJump(self.part.keys)
        end)
        spots[i] = b
        return b
    end

    -- Clears outline and tooltip, since a reused hotspot may now cover
    -- another part.
    local function unlit(b)
        if b.outline:IsShown() or b.grip:IsShown() then W.HideTooltip() end
        W.EaseAlpha(b.outline, 1)
        b.outline:Hide()
        b.dashes.SetShown(false)
        b.grip:Hide()
    end

    -- Later parts get higher frame levels.
    local function placeHotspots()
        local parts = sample.Parts()
        local base = strip.layer:GetFrameLevel()
        for i, part in ipairs(parts) do
            local b = hotspot(i)
            unlit(b)
            b.part = part
            b.dragged = nil
            b:SetFrameLevel(base + i)
            cover(b, part.region, part.scale or 1)
            if strip.design and selected == part.label then lit(b) end
            b:Show()
        end
        for i = #parts + 1, #spots do
            unlit(spots[i])
            spots[i]:Hide()
        end
        placeGrips()
    end

    -- Hidden mid-drag (Escape, window closed): a held grip saves as if
    -- released, a held piece is dropped, and OnUpdate stops.
    strip:SetScript("OnHide", function()
        if gripPress then strip.EndGrip(true) end
        if press and press.dragging and press.b.part.move.list then lift(press.b, false) end
        press = nil
        strip:SetScript("OnUpdate", nil)
        hideDots()
        setKeys(false)
        strip.insert:Hide()
        strip.insert.at = nil
    end)

    function strip.SetPage(page)
        if sample then sample.frame:Hide() end
        strip.EndGrip(false)
        if press and press.dragging and press.b.part.move.list then lift(press.b, false) end
        sample, press, selected = nil, nil, nil
        strip:SetScript("OnUpdate", nil)
        hideDots()
        strip.insert:Hide()
        strip.insert.at = nil
        setKeys(false)
        if not (page and page.sample) then
            strip:Hide()
            return
        end
        sample = samples[page.id]
        if not sample then
            sample = page.sample(strip)
            samples[page.id] = sample
        end
        sample.frame:Show()
        strip.hint:SetText(strip.design and (sample.designHint or Strip.DESIGN_HINT) or sample.hint or Strip.HINT)
        local zooms = sample.SetZoom ~= nil and sample.zoomRange ~= nil
        if zooms then
            local item, r = strip.zoom.item, sample.zoomRange
            item.min, item.max, item.step = r.min, r.max, r.step
            strip.zoom.control.slider:SetMinMaxValues(r.min, r.max)
            strip.zoom.control.Refresh()
        end
        strip.zoom:SetShown(zooms)
        strip:Show()
    end

    function strip.ZoomControl() return strip.zoom end

    function strip.SetDesign(on)
        on = on == true
        if strip.design == on then return end
        strip.design = on
        if not on then selected = nil end
        strip.hint:SetText(on and (sample and sample.designHint or Strip.DESIGN_HINT) or (sample and sample.hint) or Strip.HINT)
        placeGrips()
    end

    -- room is the max sample height (Strip.Room).
    function strip.Redraw(width, room)
        if not sample then return end
        strip.lastWidth, strip.lastRoom = width, room
        local h = sample.Refresh(width - 2 * Strip.PAD, room or Strip.MAX_HEIGHT)
        if type(h) ~= "number" or h <= 0 then
            strip:Hide()
            return
        end
        strip:Show()
        sample.frame:ClearAllPoints()
        sample.frame:SetPoint("TOPLEFT", strip, "TOPLEFT", Strip.PAD, -Strip.PAD)
        strip:SetHeight(h + 2 * Strip.PAD + Strip.HINT_HEIGHT)
        strip.layer:SetFrameLevel(strip:GetFrameLevel() + Strip.LAYER)
        placeHotspots()
        placeViews()
    end

    function strip.Hotspots()
        local out = {}
        for _, b in ipairs(spots) do
            if b:IsShown() then out[#out + 1] = b end
        end
        return out
    end

    -- True if any part moves or resizes, which earns the page a Design
    -- switch. The player frame has nothing to drag but its bars resize.
    function strip.Movable()
        for _, b in ipairs(strip.Hotspots()) do
            if b.part.move or b.part.size then return true end
        end
        return false
    end

    function strip.DotsShown()
        local n = 0
        for _, d in ipairs(dots) do if d:IsShown() then n = n + 1 end end
        return n
    end

    function strip.Selected() return selected end
    -- The selected part, or nil.
    function strip.SelectedPart()
        if not selected then return nil end
        for _, b in ipairs(spots) do
            if b:IsShown() and b.part.label == selected then return b.part end
        end
    end
    -- Selects a piece by label, same as clicking it.
    function strip.Pick(label)
        selected = label
        placeGrips()
    end
    strip.add:SetScript("OnClick", function(self)
        if not (sample and sample.Adds) then return end
        local keys, values = sample.Adds()
        W.OpenMenu(self, keys, values, nil, function(k)
            local label = sample.Add(k)
            if not label then return end
            strip.Pick(label)
            if strip.onAdded then strip.onAdded(label) end
        end)
    end)
    strip.all:SetScript("OnClick", function()
        local part = strip.SelectedPart()
        if part and onAll then onAll(part.keys) end
    end)
    function strip.AllLink() return strip.all end
    function strip.Grips() return grips end
    function strip.GripLabel() return gripLabel end
    function strip.Sample() return sample end
    function strip.InsertLine() return strip.insert end
    function strip.Lifted() return strip.lift end

    return strip
end
