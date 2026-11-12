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
-- in execute range. Each one gets a toggle chip at the top right.

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
Strip.HINT = L["Click any part to jump to its settings."]
Strip.DESIGN_HINT = L["Drag a piece to move it. Click it for its settings; the arrow keys then nudge it."]
Strip.TIP = L["Click to jump to its settings."]
Strip.DESIGN_EMPTY = L["Click a piece of the preview to see its settings here."]
Strip.ALL = L["Every setting for this piece"]
Strip.ADD = L["+ Add piece"]
Strip.DESIGN_TIP = L["Drag to move it, or click for its settings."]
Strip.DRAG_START = 4     -- px of movement before a press becomes a drag
Strip.DOT = 5            -- spot dot size; the nearest one is DOT_NEAR
Strip.DOT_NEAR = 8
Strip.DOT_ALPHA = 0.3
Strip.DOT_NEAR_ALPHA = 0.8
Strip.NUDGE_BIG = 5      -- px per arrow key with Shift held
Strip.ZOOM_WIDTH = 190   -- zoom slider including label and number
Strip.GRIP = 8           -- resize grip size; edge grips are GRIP x GRIP_LONG
Strip.GRIP_LONG = 14

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

    local function lit(b)
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
                    sample.SetView(self.viewKey, not self.viewOn)
                    if strip.lastWidth then strip.Redraw(strip.lastWidth, strip.lastRoom) end
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
        setKeys(part and part.move ~= nil and (part.move.xKey or part.move.yKey) ~= nil)
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
            -- Grab offset from the piece's center, in its own units.
            local r = b.part.region
            local rs = r:GetEffectiveScale()
            local mx, my = r:GetCenter()
            press.gx = type(mx) == "number" and mx - press.x / rs or 0
            press.gy = type(my) == "number" and my - press.y / rs or 0
            press.mates = matesOf(b)
        end
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
        b:SetScript("OnEnter", function(self)
            lit(self)
            W.Tooltip(self, DUI.Options.Text(self.part.label), strip.design and self.part.move and Strip.DESIGN_TIP or Strip.TIP)
        end)
        b:SetScript("OnLeave", function(self)
            if press and press.b == self then return end
            if not (strip.design and selected == self.part.label) then
                DUI.Motion.AlphaTo(self.outline, 0, DUI.Motion.FAST, true)
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
        if b.outline:IsShown() then W.HideTooltip() end
        W.EaseAlpha(b.outline, 1)
        b.outline:Hide()
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
        press = nil
        strip:SetScript("OnUpdate", nil)
        hideDots()
        setKeys(false)
    end)

    function strip.SetPage(page)
        if sample then sample.frame:Hide() end
        strip.EndGrip(false)
        sample, press, selected = nil, nil, nil
        strip:SetScript("OnUpdate", nil)
        hideDots()
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
        strip.hint:SetText(on and Strip.DESIGN_HINT or Strip.HINT)
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

    return strip
end
