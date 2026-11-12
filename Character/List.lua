-- Shared layout for the pages after Character: a list on the left with
-- foldable headers and pickable rows, and a detail pane on the right where
-- useful. Rows are pooled, and the list scrolls by whole rows.
-- Bars use a gradient pair when "Gradient bars" is on, else a plain fill.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local Style = DUI.Style

local List = {}
ns.List = List

List.EDGE = 16
List.TOP = 12
List.ROW = 24
List.BAR_ROW = 30                   -- row height when a bar sits under the name
List.BAR_H = 8
List.PANE_BAR = 12                  -- the detail pane's bar
List.HEAD_SIZE = Style.SIZE.head
List.LINE_ALPHA = 0.6               -- line under a header
List.PANE_W = 300
List.PANE_PAD = 14
List.INDENT = 12
List.ICON = 16
List.WHEEL = 3                      -- rows per wheel notch
-- When a group folds, rows glide to their new places. Newly opened rows drop
-- in from FOLD_DROP px above, one after another.
List.FOLD_DROP = 6
List.FOLD_STAGGER, List.FOLD_STAGGER_MAX = 0.02, 0.1
List.FOLD_WAIT = 1                  -- seconds to wait for the game's updated list
List.TEXT, List.SMALL, List.TITLE = Style.SIZE.body, Style.SIZE.small, Style.SIZE.head
List.DIM = Style.INK.VALUE         -- text on bars
List.HI = DUI.Win.Parts.HI         -- hovered or picked row, same as other lists
List.INSET = { 0, 0, 0, 0.22 }
List.WHITE = "Interface\\Buttons\\WHITE8X8"

-- Vertical space for a list or detail pane.
function List.Room()
    return ns.Window.H - ns.Window.HEADER - List.TOP - List.EDGE
end

function List.Visible(row)
    return math.floor(List.Room() / (row or List.ROW))
end

-- 17400 -> "17,400".
function List.Number(n)
    return DUI.Thousands(math.floor((n or 0) + 0.5))
end

-- The lighter end of a gradient pair, for text drawn in it.
function List.Light(key)
    local G = DUI.Gradients
    if not (G and key and G.Has(key)) then return nil end
    local a, b = G.PaintRGB(key)
    local function lum(c) return c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114 end
    return lum(a) >= lum(b) and a or b
end

-- Your own progress (skills, PvP, a currency's weekly cap) uses the accent.
function List.OwnBar()
    return "accent", { Style.Accent() }
end

function List.PaintBar(bar, key, rgb)
    local G, W = DUI.Gradients, DUI.Widgets
    if ns.Setting("gradient") == false then
        W.BarColor(bar, rgb[1], rgb[2], rgb[3])
    elseif key == "accent" then
        W.BarAccent(bar)
    elseif key and G.Has(key) then
        local lo, hi = G.Colors(key)
        W.BarPair(bar, lo, hi, G.Orientation())
    else
        W.BarFrom(bar, rgb[1], rgb[2], rgb[3])
    end
end

-- A W.Bar sized for list rows.
local function newBar(parent, h)
    return DUI.Widgets.Bar(parent, h or List.BAR_H)
end

local function rowFrame(L, i)
    if L.rows[i] then return L.rows[i] end
    local r = CreateFrame("Button", nil, L.frame)
    r:SetHeight(L.row)
    r.stripe = r:CreateTexture(nil, "BACKGROUND", nil, -1)
    r.stripe:SetAllPoints()
    r.stripe:Hide()
    r.hi = r:CreateTexture(nil, "BACKGROUND")
    r.hi:SetAllPoints()
    r.hi:SetColorTexture(List.HI[1], List.HI[2], List.HI[3], List.HI[4])
    r.hi:Hide()
    r.line = r:CreateTexture(nil, "ARTWORK")   -- under a header; white so ns.Colors.Line can tint it
    r.line:SetTexture(List.WHITE)
    r.line:SetHeight(1)
    r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 1)
    r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -2, 1)
    r.line:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(List.ICON, List.ICON)
    r.text = Style.Text(r, List.TEXT, "LEFT")
    r.text:SetWordWrap(false)
    r.head = Style.Text(r, List.HEAD_SIZE, "LEFT")   -- header text
    r.head:SetWordWrap(false)
    r.right = Style.Text(r, List.SMALL, "RIGHT")
    r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -5)
    r.bar = newBar(r)
    r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 3)
    r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -2, 3)
    r:SetScript("OnClick", function(self) List.Click(L, self.item) end)
    -- Only visible rows exist, so the D-pad reaching the last one scrolls the
    -- list (List.PadEdge).
    r.OnSmartNavSelect = function() List.PadEdge(L, i) end
    local Light = DUI.Win.Parts.Light   -- shared row hover
    r:SetScript("OnEnter", function(self) if self.item and self.item.kind ~= "head" then Light(self.hi, true) end end)
    r:SetScript("OnLeave", function(self) Light(self.hi, self.item ~= nil and self.item.key == L.selectedKey) end)
    L.rows[i] = r
    return r
end

-- opts: onPick(item) for rows, onFold(item) for headers, row = row height
-- (List.BAR_ROW for lists with bars).
function List.Make(page, opts)
    opts = opts or {}
    local row = opts.row or List.ROW
    local L = { page = page, opts = opts, rows = {}, items = {}, offset = 0, row = row, visible = List.Visible(row),
                marks = {} }
    L.frame = CreateFrame("Frame", nil, page)
    L.frame:SetClipsChildren(true)   -- clip rows gliding in past the edges
    L.frame:EnableMouseWheel(true)
    L.frame:SetScript("OnMouseWheel", function(_, delta)
        List.Scroll(L, -delta * List.WHEEL)
        L.bar.Wake()
    end)
    -- Scroll bar in whole rows.
    L.bar = DUI.Widgets.Scroll(L.frame, {
        wheel = false,
        read = function() return L.offset, math.max(0, #L.items - L.visible), L.visible end,
        write = function(v)
            local n = math.floor(v + 0.5)
            if n ~= L.offset then List.Scroll(L, n - L.offset) end
        end,
    })
    return L
end

function List.Place(L, x, w)
    L.frame:ClearAllPoints()
    L.frame:SetPoint("TOPLEFT", L.page, "TOPLEFT", x, -List.TOP)
    L.frame:SetSize(w, L.visible * L.row)
end

-- Numbers each header (for its color) and each row under its header (for stripes).
function List.Marks(items)
    local marks, heads, n = {}, 0, 0
    for i, item in ipairs(items) do
        if item.kind == "head" then
            heads, n = heads + 1, 0
            marks[i] = heads
        else
            n = n + 1
            marks[i] = n
        end
    end
    return marks
end

function List.Set(L, items)
    local fold = List.TakeFold(L, items)
    L.items = items
    L.marks = List.Marks(items)
    local max = math.max(0, #items - L.visible)
    if L.offset > max then L.offset = max end
    List.Draw(L)
    if fold then List.Animate(L, fold, #items - fold.count) end
end

-- The D-pad landed on visible row i. On the last row with more below, scroll
-- one and step the D-pad back a row, so it stays on the same item and the next
-- press reaches the next one. Same going up from the first row.
function List.PadEdge(L, i)
    local dir
    if i >= L.visible and L.offset + L.visible < #L.items then dir = 1
    elseif i <= 1 and L.offset > 0 then dir = -1 end
    if not dir then return end
    List.Scroll(L, dir)
    if L.bar then L.bar.Wake() end
    DUI.Pad.Settle(L.rows[i - dir])
end

function List.Scroll(L, n)
    for _, r in ipairs(L.rows) do DUI.Motion.Settle(r) end
    L.offset = math.min(math.max(0, #L.items - L.visible), math.max(0, L.offset + n))
    List.Draw(L)
end

-- The pending fold from a header click, once the game's list has changed.
-- Nil until then, or if that header is gone.
function List.TakeFold(L, items)
    local fold = L.fold
    if not fold then return nil end
    if GetTime() - fold.time > List.FOLD_WAIT then L.fold = nil; return nil end
    if #items == fold.count then return nil end
    L.fold = nil
    local h = items[fold.at]
    if not (h and h.kind == "head" and h.text == fold.text) then return nil end
    return fold
end

-- delta rows were added (or removed, if negative) under the header at fold.at.
-- Each row glides from its old place to its new one, and new rows drop in top first.
function List.Animate(L, fold, delta)
    local Motion = DUI.Motion
    local n = 0
    for i = 1, L.visible do
        local r = L.rows[i]
        if r and r:IsShown() then
            Motion.Settle(r)
            local at = L.offset + i
            if at > fold.at and at <= fold.at + delta then
                Motion.SlideIn(r, 0, List.FOLD_DROP, nil, math.min(List.FOLD_STAGGER_MAX, n * List.FOLD_STAGGER))
                n = n + 1
            else
                local was = (at > fold.at and at - delta or at) - fold.offset
                if was ~= i then Motion.Glide(r, 0, -(was - i) * L.row) end
            end
        end
    end
end

function List.Click(L, item)
    if not item then return end
    if item.kind == "head" then
        if not L.opts.onFold then return end
        for i, it in ipairs(L.items) do
            if it == item then
                L.fold = { at = i, text = item.text, count = #L.items, offset = L.offset, time = GetTime() }
            end
        end
        L.opts.onFold(item)
        return
    end
    L.selectedKey = item.key
    if L.opts.onPick then L.opts.onPick(item) end
    List.Draw(L)
end

function List.Draw(L)
    for i = 1, L.visible do
        local item = L.items[L.offset + i]
        local r = rowFrame(L, i)
        r.item = item
        if not item then
            r:Hide()
        else
            r:Show()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", L.frame, "TOPLEFT", 0, -(i - 1) * L.row)
            r:SetPoint("TOPRIGHT", L.frame, "TOPRIGHT", 0, -(i - 1) * L.row)
            local head = item.kind == "head"
            local mark = L.marks[L.offset + i]
            local x = (item.indent or 0) * List.INDENT
            r.icon:SetShown(item.icon ~= nil)
            if item.icon then
                r.icon:ClearAllPoints()
                r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", x, -4)
                r.icon:SetTexture(item.icon)
                x = x + List.ICON + 6
            end
            r.text:SetShown(not head)
            r.head:SetShown(head)
            r.line:SetShown(head)
            if head then
                -- Header: bigger text in its palette color, with a line under it.
                r.head:ClearAllPoints()
                r.head:SetPoint("LEFT", r, "LEFT", x, 0)
                r.head:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
                ns.Colors.HeadText(r.head, mark, (item.folded and "+  " or "-  ") .. string.upper(item.text or ""))
                ns.Colors.Line(r.line, List.LINE_ALPHA)
                r.stripe:Hide()
            else
                r.text:ClearAllPoints()
                r.text:SetPoint("TOPLEFT", r, "TOPLEFT", x, -5)
                r.text:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
                r.text:SetText(item.text or "")
                local c = item.color
                if c then r.text:SetTextColor(c[1], c[2], c[3]) else Style.InkText(r.text, "TEXT") end
                ns.Colors.Stripe(r.stripe, mark)
            end
            r.right:SetText(item.right or "")
            local c = item.rightColor or { Style.Pop() }   -- right-hand numbers use the accent
            r.right:SetTextColor(c[1], c[2], c[3])
            local b = item.bar
            r.bar:SetShown(b ~= nil)
            if b then
                r.bar:SetMinMaxValues(0, (b.max or 0) > 0 and b.max or 1)
                -- Glide when it's the same item moving, snap when the row is reused for another.
                Style.SetBarValue(r.bar, (b.max or 0) > 0 and (b.value or 0) or 1, r.barKey ~= item.key)
                r.barKey = item.key
                List.PaintBar(r.bar, b.key, b.rgb)
            end
            DUI.Win.Parts.Light(r.hi, not head and item.key == L.selectedKey, true)
        end
    end
    if L.bar then L.bar.Update() end
end

-- Detail pane

-- A row with a W.Switch on the right. Clicking anywhere on the row flips it
-- right away. The game's answer may need a server round trip, so for
-- TOGGLE_HOLD seconds a refresh that still reads the old state keeps the click's.
List.TOGGLE_HOLD = 2
function List.Toggle(parent, label, onClick)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(List.PANE_W - 2 * List.PANE_PAD, 20)
    t.switch = DUI.Widgets.Switch(t)
    t.switch:SetPoint("RIGHT", t, "RIGHT", 0, 0)
    t.switch:EnableMouse(false)   -- the row handles the click
    t.text = Style.Text(t, List.TEXT, "LEFT")
    t.text:SetPoint("LEFT", t, "LEFT", 0, 0)
    t.text:SetPoint("RIGHT", t.switch, "LEFT", -8, 0)
    t.text:SetText(label)
    Style.InkText(t.text, "TEXT")
    t:SetScript("OnClick", function(self)
        if self.enabled == false then return end
        if DUI.Sound then DUI.Sound.Play("toggle") end
        onClick(self)   -- self.on is still the old state here
        self.want = { on = not self.on, at = GetTime(), who = self.who }
        self.on = not self.on
        self.switch.SetOn(self.on)
    end)
    return t
end

-- who is what the switch controls (a faction, a currency), so the hold ends
-- when the pane switches to something else.
function List.SetToggle(t, on, enabled, who)
    on = on == true
    local w = t.want
    if w and on ~= w.on and w.who == who and GetTime() - w.at < List.TOGGLE_HOLD then
        on = w.on
    else
        t.want = nil
    end
    t.on, t.enabled, t.who = on, enabled ~= false, who
    t.switch.SetOn(t.on)
    t:SetAlpha(t.enabled and 1 or 0.45)
end

function List.Pane(page)
    local P = CreateFrame("Frame", nil, page)
    P.bg = P:CreateTexture(nil, "BACKGROUND")
    P.bg:SetAllPoints()
    P.bg:SetColorTexture(List.INSET[1], List.INSET[2], List.INSET[3], List.INSET[4])
    local pad = List.PANE_PAD
    P.title = Style.Text(P, List.TITLE, "LEFT")
    P.title:SetPoint("TOPLEFT", P, "TOPLEFT", pad, -pad)
    Style.InkText(P.title, "VALUE")
    P.sub = Style.Text(P, List.TEXT, "LEFT")
    P.sub:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 0, -6)
    P.bar = newBar(P, List.PANE_BAR)
    P.bar:SetPoint("TOPLEFT", P.sub, "BOTTOMLEFT", 0, -10)
    P.bar:SetPoint("RIGHT", P, "RIGHT", -pad, 0)
    P.barText = Style.Text(P, List.SMALL, "LEFT")
    P.barText:SetPoint("TOPLEFT", P.bar, "BOTTOMLEFT", 0, -6)
    P.barText:SetTextColor(List.DIM[1], List.DIM[2], List.DIM[3])
    P.body = Style.Text(P, List.TEXT, "LEFT")
    P.body:SetPoint("TOPLEFT", P.barText, "BOTTOMLEFT", 0, -14)
    P.body:SetPoint("RIGHT", P, "RIGHT", -pad, 0)
    Style.InkText(P.body, "TEXT")
    P.toggles = {}
    P.button = DUI.Widgets.Button(P, "", 24)
    P.button:SetWidth(List.PANE_W - 2 * pad)
    P.button:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", pad, pad)
    P.button:Hide()
    return P
end

-- Switches stacked from the bottom of the pane (above its button).
function List.AddToggle(P, label, onClick)
    local t = List.Toggle(P, label, onClick)
    local n = #P.toggles
    t:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", List.PANE_PAD, List.PANE_PAD + 34 + n * 24)
    P.toggles[n + 1] = t
    return t
end

function List.PlacePane(P, x, w)
    P:ClearAllPoints()
    P:SetPoint("TOPLEFT", P:GetParent(), "TOPLEFT", x, -List.TOP)
    P:SetSize(w, List.Room())
end
