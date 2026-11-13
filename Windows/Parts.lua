-- Window content: a scrolling column of blocks (text, section headers,
-- clickable rows, item tiles, a money line) and a footer of buttons. Blocks
-- are pooled and reused across refreshes. Each has a single anchor so Feel
-- can lift them in one after another (stack.pieces, in reading order).
--
--   local s = Parts.Stack(page, { bottom = 52 })
--   s:Begin(); s:Text(...); s:Section(...); s:Row({...}); s:Items({...}); s:Money(c, xp); s:End()
--   local foot = Parts.Footer(page); foot:Set({ { text, primary, tone, onClick, off } ... })

local _, DUI = ...
local L = DUI.L
local Style = DUI.Style

local Win = DUI.Win
local Parts = {}
Win.Parts = Parts

Parts.EDGE = 16
Parts.TEXT, Parts.SMALL, Parts.HEAD = Style.SIZE.body, Style.SIZE.small, Style.SIZE.small
Parts.ROW = 28
Parts.ICON = 18
Parts.ITEM = 44             -- item tile height
Parts.ITEM_ICON = 34
Parts.ITEM_MARK = 16        -- small mark at a tile's right end (the NPC window's coin)
Parts.GAP = 6
Parts.WHEEL = 40            -- px per wheel notch
Parts.SAY = Style.INK.TEXT       -- NPC speech
Parts.DIM = Style.INK.LABEL       -- labels and sub lines
Parts.FAINT = Style.INK.OFF       -- unavailable
-- Accent-colored texts (section heads, row keys), repainted when the accent
-- changes.
local popped = setmetatable({}, { __mode = "k" })
local whys = setmetatable({}, { __mode = "k" })   -- why cards, for their accent edge
local function paintWhyEdge(c)
    if c.warn then
        local w = Style.INK.WARN
        c.edge:SetVertexColor(w[1], w[2], w[3], 1)
    else
        Style.PaintAccent(c.edge, 1)
    end
end
local function repaintPops()
    for c in pairs(whys) do paintWhyEdge(c) end
    for b in pairs(popped) do
        if b.isSection then Style.InkText(b.text, "pop") elseif b.Lit then b.Lit(b:IsMouseOver() == true) end
    end
end
if DUI.On then DUI.On("StyleChanged", repaintPops) end
Parts.HI = { 1, 1, 1, 0.06 }       -- hovered row
Parts.PICKED = { 1, 1, 1, 0.08 }

-- Shift-click links the item, Ctrl-click previews it, via the game's
-- HandleModifiedItemClick. Returns true if the game handled the click.
-- link may be the item link or a function returning it.
function Parts.ItemClick(link)
    if type(HandleModifiedItemClick) ~= "function" then return false end
    if type(link) == "function" then link = link() end
    return link ~= nil and HandleModifiedItemClick(link) == true
end

-- Row hover highlight, eased in and out at FAST. instant skips the ease
-- (used on refill). SetAlpha on a texture replaces its vertex alpha, so ease
-- up to the original 0.06, not 1, or the row lights up solid white.
function Parts.Light(t, on, instant)
    local M = DUI.Motion
    on = on == true
    if not t.lightTop then t.lightTop = select(4, t:GetVertexColor()) or 1 end
    local top = t.lightTop
    if instant or not (M and M.On()) then
        if M then M.Tween(t, 0, 0, 0) end   -- cancel a running tween
        t:SetAlpha(top)
        t:SetShown(on)
        return
    end
    local from = t:IsShown() and t:GetAlpha() or 0
    t:Show()
    M.Tween(t, from, on and top or 0, M.FAST, function(a) t:SetAlpha(a) end,
        function() if not on then t:Hide(); t:SetAlpha(top) end end)
end
Parts.WHITE = "Interface\\Buttons\\WHITE8X8"

local function tex(parent, layer, color)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(Parts.WHITE)
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
    return t
end

-- A faint 1 px divider line. The caller anchors it.
Parts.RULE = { 1, 1, 1, 0.06 }
function Parts.Rule(parent, vertical)
    local t = tex(parent, "ARTWORK", Parts.RULE)
    if vertical then t:SetWidth(1) else t:SetHeight(1) end
    return t
end

-- Color table to a "|cffrrggbb" escape.
function Parts.Hex(c)
    local function h(v) return math.max(0, math.min(255, math.floor((v or 1) * 255 + 0.5))) end
    return string.format("|cff%02x%02x%02x", h(c[1]), h(c[2]), h(c[3]))
end

local function sound(name) if DUI.Sound then DUI.Sound.Play(name) end end

-- ---------------------------------------------------------------------
-- Stack
-- ---------------------------------------------------------------------

local Stack = {}
Stack.__index = Stack

-- inset: top, bottom, side (side margin defaults to Parts.EDGE).
function Parts.Stack(page, inset)
    inset = inset or {}
    local s = setmetatable({ pools = {}, used = {}, pieces = {}, page = page }, Stack)
    local sf = CreateFrame("ScrollFrame", nil, page)
    local side = inset.side or Parts.EDGE
    s.side = side
    sf:SetPoint("TOPLEFT", page, "TOPLEFT", side, -(inset.top or 12))
    sf:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -side, inset.bottom or 12)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    -- Scrolling moves rows out from under their cast buttons, so hide them.
    -- s.at is the last position, so a wheel at the end does nothing.
    s.at = 0
    s.bar = DUI.Widgets.Scroll(sf, { step = Parts.WHEEL, onScroll = function(v)
        if v ~= s.at then s.at = v; Win.CastersOff(sf) end
    end })
    s.scroll, s.child = sf, child
    return s
end

-- The width the window is resizing toward. Fills run before the resize
-- finishes, and using the current width laid pages out too narrow.
function Stack:Width()
    local w = self.scroll:GetWidth()
    if type(w) ~= "number" or w <= 0 then
        local pw = self.page:GetWidth()
        if (type(pw) ~= "number" or pw <= 0) and self.page.win then pw = self.page.win:GetWidth() end
        w = (pw or 0) - 2 * (self.side or Parts.EDGE)
    end
    w = w + Win.GoalGrowth(self.page)
    if w <= 0 then w = 368 end
    return w
end

local function take(s, kind, make)
    local pool = s.pools[kind]
    if not pool then pool = { n = 0 }; s.pools[kind] = pool end
    pool.n = pool.n + 1
    local b = pool[pool.n]
    if not b then
        b = make(s.child)
        pool[pool.n] = b
    end
    b:Show()
    s.used[#s.used + 1] = b
    return b
end

function Stack:Begin()
    -- A why card that stays across the refill shouldn't fade in again
    -- (Stack:Why reads c.keep).
    local whyPool = self.pools.why
    if whyPool then for i = 1, #whyPool do whyPool[i].keep = whyPool[i].seen end end
    for _, pool in pairs(self.pools) do
        for i = 1, #pool do pool[i]:Hide() end
        pool.n = 0
    end
    self.used, self.pieces = {}, {}
    self.y = 0
    self.bar.Stop()
    self.scroll:SetVerticalScroll(0)
    self.at = 0
    Win.CastersOff(self.scroll)   -- rows get new contents on refill
end

-- Place a block under the previous one, `gap` px apart.
local function put(s, b, h, gap)
    s.y = s.y + (#s.pieces > 0 and (gap or Parts.GAP) or 0)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", s.child, "TOPLEFT", 0, -s.y)
    b:SetSize(s:Width(), h)
    b.col = nil   -- full width, for Stack:Stretch
    b.stackY = s.y   -- top offset in the list, for Stack:Reveal
    s.y = s.y + h
    s.pieces[#s.pieces + 1] = b
    return b
end

function Stack:Gap(px) self.y = self.y + (px or 8) end

-- A custom block, built by make(parent) and pooled by kind. key identifies
-- it across refills for Stack:Ease.
function Stack:Piece(kind, make, h, gap, key)
    local b = take(self, kind, make)
    b.stackKey = key
    return put(self, b, h, gap)
end

-- Save and restore the scroll position around a refill (Begin resets to the top).
function Stack:Scrolled() return self.scroll:GetVerticalScroll() or 0 end
function Stack:ScrollTo(v)
    local max = math.max(0, (self.height or 0) - (self.scroll:GetHeight() or 0))
    self.bar.Stop()
    local to = math.max(0, math.min(max, v or 0))
    if to ~= self:Scrolled() then Win.CastersOff(self.scroll) end
    self.scroll:SetVerticalScroll(to)
    self.at = to
    self.bar.Update()
end

-- Scroll just enough to bring b into view. No-op if it's already visible.
function Stack:Reveal(b)
    local top = b and b.stackY
    if type(top) ~= "number" then return end
    local at, view = self:Scrolled(), self.scroll:GetHeight() or 0
    local bottom = top + (b:GetHeight() or 0)
    local to
    if top < at then to = top
    elseif bottom > at + view then to = bottom - view end
    if to then self.bar.To(to, true) end
end

-- Resize every piece to the current width without refilling. Win.Grip calls
-- this every frame of a resize drag; the refill at the end rewraps text.
-- Pieces with their own Stretch(w) re-lay their contents too.
function Stack:Stretch()
    local w = self:Width()
    local half = math.floor((w - Parts.GAP) / 2)
    for _, b in ipairs(self.pieces) do
        if b.col then
            b:SetWidth(half)
            if b.col == 2 then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self.child, "TOPLEFT", half + Parts.GAP, -b.colY)
            end
        else
            b:SetWidth(w)
            if b.Stretch then b.Stretch(w) end
        end
    end
    self.child:SetWidth(w)
end

function Stack:End()
    self.height = self.y
    self.child:SetSize(self:Width(), math.max(1, self.y))
    self.bar.Update()
    DUI.Pad.Settle()
    return self.pieces
end

-- Animated refill, e.g. opening a tree node: call Spots() before Begin and
-- Ease(spots) after End. Pieces with a known key glide from their old spot,
-- new ones fade in. `from` limits easing to pieces from that index on, for
-- lists filled a slice per frame.
function Stack:Spots()
    local out = {}
    for _, b in ipairs(self.pieces) do
        if b.stackKey and b.stackY then out[b.stackKey] = b.stackY end
    end
    return out
end

function Stack:Ease(before, from)
    local M = DUI.Motion
    local on = before ~= nil and M ~= nil and M.On()
    local child = self.child
    local pieces = self.pieces
    for i = from or 1, #pieces do
        local b = pieces[i]
        local to = b.stackY
        -- Two-column item tiles have no stackY and don't move.
        if not b.col and type(to) == "number" then
            b.glideKey = b.glideKey or {}
            local was = on and b.stackKey and before[b.stackKey]
            local function at(y)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            end
            if on and b.stackKey and was == nil then
                M.Tween(b.glideKey, to, to, 0, at)
                M.Fade(b, 0, 1, M.NORMAL)
            elseif on and was and was ~= to then
                M.Tween(b.glideKey, was, to, M.NORMAL, at)
            elseif M then
                M.Tween(b.glideKey, to, to, 0, at)   -- cancel any earlier glide
            end
        end
    end
end

-- Wrapped text. opts: size, color, gap, spacing (line spacing, default 3).
local function makeText(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.text = Style.Text(b, Parts.TEXT, "LEFT")
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.text:SetWordWrap(true)
    b.text:SetSpacing(3)
    return b
end

function Stack:Text(text, opts)
    opts = opts or {}
    local b = take(self, "text", makeText)
    Style.SetTextSize(b.text, opts.size or Parts.TEXT)
    b.text:SetSpacing(opts.spacing or 3)
    local c = opts.color or Parts.SAY
    b.text:SetTextColor(c[1], c[2], c[3])
    b.text:SetWidth(self:Width())
    b.text:SetText(text or "")
    local h = b.text:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then h = (opts.size or Parts.TEXT) + 4 end
    b.stackKey = "text:" .. (text or "")
    return put(self, b, math.ceil(h), opts.gap)
end

-- A small spaced header with a faint line under it.
local function makeSection(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.text = Style.Text(b, Parts.HEAD, "LEFT")
    b.text:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 4)
    b.line = tex(b, "ARTWORK", { 1, 1, 1, 0.06 })
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.value = Style.Text(b, Style.SIZE.small, "RIGHT")
    b.value:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 4)
    b.value:SetWordWrap(false)
    b.action = DUI.Widgets.Link(b, Style.SIZE.small)
    b.action:SetPoint("BOTTOMRIGHT", b.value, "BOTTOMLEFT", -10, -4)
    b.action:SetScript("OnClick", function(self)
        local fn = b.opts and b.opts.action and b.opts.action.onClick
        if fn then fn(self) end
    end)
    b.isSection = true
    popped[b] = true
    return b
end

-- opts.value: right-aligned text such as a total (INK.LABEL unless it has
--   its own color codes).
-- opts.action: { text, onClick } shown as a link left of the value.
-- opts.lit: draw the label in INK.VALUE instead of the accent.
function Stack:Section(label, opts)
    opts = opts or {}
    local b = take(self, "section", makeSection)
    b.opts = opts
    b.text:SetText(string.upper(label or ""))
    if opts.lit then Style.InkText(b.text, "VALUE") else Style.InkText(b.text, "pop") end
    b.value:SetText(opts.value or "")
    Style.InkText(b.value, "LABEL")
    b.value:SetShown(opts.value ~= nil)
    if opts.action then
        b.action.SetLabel(opts.action.text)
        b.action:ClearAllPoints()
        if opts.value then b.action:SetPoint("BOTTOMRIGHT", b.value, "BOTTOMLEFT", -10, -4)
        else b.action:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0) end
    end
    b.action:SetShown(opts.action ~= nil)
    b.stackKey = "section:" .. (label or "")
    return put(self, b, 22, 12)
end

-- ---------------------------------------------------------------------
-- Rows: icon, one line of text and an optional key hint
-- ---------------------------------------------------------------------

local function makeRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hi = tex(b, "BACKGROUND", Parts.HI)
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(Parts.ICON, Parts.ICON)
    -- Tree node open/closed marker (spec.chevron).
    b.chevron = b:CreateTexture(nil, "ARTWORK")
    b.chevron:SetTexture(DUI.MEDIA .. "ui-chevron.png")
    b.chevron:SetSize(Parts.CHEVRON, Parts.CHEVRON)
    b.chevron:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.chevron:Hide()
    b.text = Style.Text(b, Parts.TEXT, "LEFT")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.text:SetWordWrap(false)
    b.key = Style.Text(b, Style.SIZE.tiny, "CENTER")
    b.key:SetPoint("CENTER", b, "LEFT", 6 + Parts.KEY / 2, 0)
    b.keyBox = tex(b, "BORDER", { 1, 1, 1, 0.08 })
    b.keyBox:SetPoint("TOPLEFT", b.key, "TOPLEFT", -4, 3)
    b.keyBox:SetPoint("BOTTOMRIGHT", b.key, "BOTTOMRIGHT", 4, -3)
    local function lit(on)
        Parts.Light(b.hi, on or b.picked == true)
        Style.InkText(b.key, "pop", on and 1 or 0.75)
    end
    b.Lit = lit
    popped[b] = true
    b:SetScript("OnEnter", function(self)
        lit(true)
        if self.spec and self.spec.onEnter then self.spec.onEnter(self) end
    end)
    b:SetScript("OnLeave", function(self)
        lit(false)
        if self.spec and self.spec.onLeave then self.spec.onLeave(self) end
    end)
    b:SetScript("OnMouseDown", function(self) self.text:SetPoint("LEFT", self.icon, "RIGHT", 10, -1) end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("LEFT", self.icon, "RIGHT", 10, 0) end)
    -- Right-click only calls spec.onRightClick, never onClick.
    b:SetScript("OnClick", function(self, button)
        local spec = self.spec
        if not spec then return end
        local fn = button == "RightButton" and spec.onRightClick or (button ~= "RightButton" and spec.onClick)
        if fn then
            sound("click")
            fn(self)
        end
    end)
    return b
end

-- The key hint comes before the icon. key = "" reserves the space without
-- a box, so rows past 9 line up with the numbered ones.
Parts.KEY = 16
Parts.INDENT = 12     -- px per tree level (spec.depth)
Parts.CHEVRON = 10

-- The chevron art points down (open); rotate it to point right when closed.
-- A row already showing animates the turn, a fresh one snaps.
local function paintChevron(b, state)
    local c = b.chevron
    if state ~= "open" and state ~= "closed" then
        c:Hide()
        b.chevronAt = nil
        return
    end
    local to = state == "open" and 0 or (math.pi / 2)
    local L = Style.INK.LABEL
    c:SetVertexColor(L[1], L[2], L[3])
    local M = DUI.Motion
    local from = c:IsShown() and b.chevronAt or nil
    c:Show()
    b.chevronKey = b.chevronKey or {}
    b.chevronAt = to
    if M and from and from ~= to then
        M.Tween(b.chevronKey, from, to, M.FAST, function(a) c:SetRotation(a) end)
    else
        if M then M.Tween(b.chevronKey, to, to, 0) end
        c:SetRotation(to)
    end
end

-- spec: text, color, icon (file or id), atlas, iconColor (tint for white art),
-- key ("1"), dim, onClick, onRightClick, onEnter, onLeave, depth (tree level),
-- chevron ("open" or "closed" for tree nodes), id (stable key for Stack:Ease).
function Stack:Row(spec)
    local b = take(self, "row", makeRow)
    b.spec = spec
    b.text:SetText(spec.text or "")
    local c = spec.color or Style.INK.TEXT
    b.text:SetTextColor(c[1], c[2], c[3])
    if spec.atlas and b.icon.SetAtlas then b.icon:SetAtlas(spec.atlas)
    else b.icon:SetTexture(spec.icon or nil) end
    local ic = spec.iconColor or { 1, 1, 1 }
    b.icon:SetVertexColor(ic[1], ic[2], ic[3])
    b.icon:SetShown(spec.icon ~= nil or spec.atlas ~= nil)
    local shown = spec.key ~= nil and spec.key ~= ""
    b.key:SetText(spec.key or "")
    b.key:SetShown(shown)
    b.keyBox:SetShown(shown)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", b, "LEFT", (spec.key ~= nil and 6 + Parts.KEY + 8 or 6) + (spec.depth or 0) * Parts.INDENT, 0)
    paintChevron(b, spec.chevron)
    b.text:SetPoint("RIGHT", b, "RIGHT", b.chevron:IsShown() and -(Parts.CHEVRON + 14) or -8, 0)
    b:SetAlpha(1)
    b.dim = spec.dim
    b.Lit(false)
    b.stackKey = spec.id
    return put(self, b, Parts.ROW, 2)
end

-- ---------------------------------------------------------------------
-- Lines: full-width row with icon, name, sub line and a value on the right
-- (a cost, a count). A dim line is not available yet: dimmed text, icon in
-- full color, not clickable.
-- ---------------------------------------------------------------------

Parts.LINE = 36
Parts.LINE_ICON = 28
Parts.LATER = Style.INK.OFF   -- name color of a dim line

local function makeLine(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hi = tex(b, "BACKGROUND", Parts.HI)
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.pick = tex(b, "BORDER", Parts.PICKED)
    b.pick:SetAllPoints(b)
    b.pick:Hide()
    b.edge = tex(b, "ARTWORK", { 0.23, 0.23, 0.26, 1 })
    b.edge:SetSize(Parts.LINE_ICON + 2, Parts.LINE_ICON + 2)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("TOPLEFT", b.edge, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
    Style.CropIcon(b.icon)
    b.value = Style.Text(b, Style.SIZE.body, "RIGHT")
    b.value:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetPoint("TOPLEFT", b.edge, "TOPRIGHT", 10, -2)
    b.name:SetPoint("RIGHT", b.value, "LEFT", -10, 0)
    b.name:SetWordWrap(false)
    b.sub = Style.Text(b, Parts.SMALL, "LEFT")
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.sub:SetPoint("RIGHT", b.value, "LEFT", -10, 0)
    b.sub:SetWordWrap(false)
    -- Key hint, same as a Row's.
    b.key = Style.Text(b, Style.SIZE.tiny, "CENTER")
    b.key:SetPoint("CENTER", b, "LEFT", 6 + Parts.KEY / 2, 0)
    b.keyBox = tex(b, "BORDER", { 1, 1, 1, 0.08 })
    b.keyBox:SetPoint("TOPLEFT", b.key, "TOPLEFT", -4, 3)
    b.keyBox:SetPoint("BOTTOMRIGHT", b.key, "BOTTOMRIGHT", 4, -3)
    b.Lit = function(on) Style.InkText(b.key, "pop", on and 1 or 0.75) end
    popped[b] = true
    -- For Parts.Shine.
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.shine:SetTexture(Parts.WHITE)
    b.shine:SetBlendMode("ADD")
    b.shine:SetHeight(Parts.LINE)
    b.shine:Hide()
    b:SetScript("OnEnter", function(self)
        if not (self.lineSpec and self.lineSpec.dim) then
            Parts.Light(self.hi, true)
            self.Lit(true)
        end
        if self.lineSpec and self.lineSpec.tooltip then self.lineSpec.tooltip(self) end
    end)
    b:SetScript("OnLeave", function(self)
        Parts.Light(self.hi, false)
        self.Lit(false)
        self.UpdateTooltip = nil
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        if self.lineSpec and self.lineSpec.leave then self.lineSpec.leave(self) end
    end)
    -- Right-click only calls spec.onRightClick, like a Row.
    b:SetScript("OnClick", function(self, button)
        local spec = self.lineSpec
        if not spec then return end
        if spec.link and button ~= "RightButton" and Parts.ItemClick(spec.link) then return end
        if spec.dim then return end
        local fn = button == "RightButton" and spec.onRightClick or (button ~= "RightButton" and spec.onClick)
        if fn then
            sound("click")
            fn(self)
        end
    end)
    return b
end

-- spec: icon (file or id), text, color, sub, subColor, value, valueColor, dim,
-- picked, key (as for a Row), onClick(b), onRightClick(b), tooltip(b), leave(b),
-- link() for item modifier clicks (Parts.ItemClick), id.
function Stack:Line(spec)
    local b = take(self, "line", makeLine)
    b.lineSpec = spec
    b.stackKey = spec.id   -- stable key for Stack:Ease
    b.icon:SetTexture(spec.icon or nil)
    local dim = spec.dim == true
    local keyed = spec.key ~= nil and spec.key ~= ""
    b.key:SetText(spec.key or "")
    b.key:SetShown(keyed)
    b.keyBox:SetShown(keyed)
    b.Lit(b:IsMouseOver() == true)
    b.edge:ClearAllPoints()
    b.edge:SetPoint("LEFT", b, "LEFT", spec.key ~= nil and 6 + Parts.KEY + 8 or 4, 0)
    local c = spec.color or (dim and Parts.LATER) or Style.INK.VALUE
    b.name:SetText(spec.text or "")
    b.name:SetTextColor(c[1], c[2], c[3])
    b.sub:SetText(spec.sub or "")
    local sc = spec.subColor or Style.INK.LABEL
    b.sub:SetTextColor(sc[1], sc[2], sc[3])
    b.value:SetText(spec.value or "")
    local vc = spec.valueColor or (dim and Parts.FAINT) or Style.INK.VALUE
    b.value:SetTextColor(vc[1], vc[2], vc[3])
    Parts.Light(b.hi, not dim and b:IsMouseOver() == true, true)
    Parts.PickLine(b, spec.picked == true)
    b.shine:Hide()
    b:SetAlpha(1)
    return put(self, b, Parts.LINE, 2)
end

-- Selected line, with the same accent wash as a selected tile.
function Parts.PickLine(b, on)
    if b.lineSpec then b.lineSpec.picked = on end
    b.pick:SetShown(on)
    if on then Style.PaintAccent(b.pick, 0.16) end
end

-- A warm light sweeps across the line once, e.g. after learning or buying.
Parts.SHINE = { 1, 0.9, 0.7 }
function Parts.Shine(b)
    if not (b and b.shine and DUI.Motion) then return end
    DUI.Motion.Sweep(b.shine, b, { width = 90, dur = 0.42, alpha = 0.32, color = Parts.SHINE, key = b.shine })
end

-- ---------------------------------------------------------------------
-- Item tiles: two per line, outlined in the item's quality color
-- ---------------------------------------------------------------------

-- Builds an item icon with a quality outline on b (b.edge, b.well, b.icon).
-- The caller anchors b.edge. size is the icon size; the outline adds 2 px.
function Parts.ItemIcon(b, size)
    b.iconSize = size
    b.edge = tex(b, "ARTWORK")
    b.edge:SetSize(size + 2, size + 2)
    -- Dark fill inside the outline. Makes it read as a 1 px ring, and an
    -- icon that hasn't loaded yet shows dark instead of a solid quality color.
    b.well = tex(b, "ARTWORK", { 0, 0, 0, 1 })
    b.well:SetDrawLayer("ARTWORK", 1)
    b.well:SetPoint("TOPLEFT", b.edge, "TOPLEFT", 1, -1)
    b.well:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints(b.well)
    Style.CropIcon(b.icon)
    return b
end

-- Makes the ring one real screen pixel, not one UI unit: below a UI scale of 1
-- a unit is less than a pixel, and a side of the ring would round away.
-- Item tiles call it on each fill, as the window's scale can change.
function Parts.FitItemIcon(b)
    local Pixel = DUI.Pixel
    local px = Pixel and Pixel.Px(b, 1) or 1
    local side = (Pixel and Pixel.Snap(b, b.iconSize) or b.iconSize) + 2 * px
    b.edge:SetSize(side, side)
    b.well:ClearAllPoints()
    b.well:SetPoint("TOPLEFT", b.edge, "TOPLEFT", px, -px)
    b.well:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -px, px)
end

-- Sets the icon and its quality outline. If the quality isn't known yet
-- (item not cached), uses a faint outline rather than guessing white.
-- Returns the quality color.
function Parts.SetItemIcon(b, texture, quality)
    b.icon:SetTexture(texture)
    local r, g, bl = Parts.QualityColor(quality)
    if type(quality) == "number" then b.edge:SetVertexColor(r, g, bl, 1)
    else b.edge:SetVertexColor(Parts.FAINT[1], Parts.FAINT[2], Parts.FAINT[3], 1) end
    return r, g, bl
end

function Parts.QualityColor(q)
    if type(q) ~= "number" then return 1, 1, 1 end
    if C_Item and type(C_Item.GetItemQualityColor) == "function" then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
        if ok and type(r) == "number" then return r, g, b end
    end
    local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function makeTile(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.bg = tex(b, "BACKGROUND", { 1, 1, 1, 0.03 })
    b.bg:SetAllPoints(b)
    b.pick = tex(b, "BORDER", Parts.PICKED)
    b.pick:SetAllPoints(b)
    b.pick:Hide()
    Parts.ItemIcon(b, Parts.ITEM_ICON)
    b.edge:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.count = Style.Text(b, Style.SIZE.tiny, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 2)
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetPoint("TOPLEFT", b.edge, "TOPRIGHT", 8, -3)
    b.name:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.name:SetWordWrap(false)
    b.sub = Style.Text(b, Parts.SMALL, "LEFT")
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.sub:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.sub:SetWordWrap(false)
    b.sub:SetTextColor(Parts.DIM[1], Parts.DIM[2], Parts.DIM[3])
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetSize(Parts.ITEM_MARK, Parts.ITEM_MARK)
    b.mark:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.mark:Hide()
    b:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(1, 1, 1, 0.07)
        if self.spec and self.spec.tooltip then self.spec.tooltip(self) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(1, 1, 1, 0.03)
        self.UpdateTooltip = nil
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        if self.spec and self.spec.leave then self.spec.leave(self) end
    end)
    b:SetScript("OnClick", function(self, button)
        local spec = self.spec
        if not spec then return end
        -- Modifier clicks (link, dressing room) take priority.
        if spec.link and Parts.ItemClick(spec.link) then return end
        if spec.onClick then sound("click"); spec.onClick(self, button) end
    end)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) if self.spec and self.spec.onDrag then self.spec.onDrag(self) end end)
    -- A fast second click arrives here instead of OnClick. Without an
    -- onDouble handler, treat it as a normal click (fast buying at a vendor).
    b:SetScript("OnDoubleClick", function(self, button)
        local spec = self.spec
        if spec and spec.onDouble then return spec.onDouble(self) end
        local click = self:GetScript("OnClick")
        if click then click(self, button) end
    end)
    -- Drop target, e.g. the mailbox's empty attachment slot.
    b:SetScript("OnReceiveDrag", function(self) if self.spec and self.spec.onReceive then self.spec.onReceive(self) end end)
    return b
end

function Parts.PaintPick(b, on, pop)
    b.picked = on
    b.pick:SetShown(on)
    if on then Style.PaintAccent(b.pick, 0.16) end
    if on and pop and DUI.Motion then DUI.Motion.Pop(b.edge, 0.9); DUI.Motion.Pop(b.well, 0.9) end
end

-- Each item: name, texture, count, quality, sub, subColor, nameColor, tint,
-- mark (small texture at the right end), picked, tooltip(b), leave(b), link(),
-- onClick(b, button), onDouble, onDrag, onReceive.
function Stack:Items(items)
    local w = self:Width()
    local half = math.floor((w - Parts.GAP) / 2)
    local tiles = {}
    for i, it in ipairs(items) do
        local b = take(self, "tile", makeTile)
        b.spec = it
        Parts.FitItemIcon(b)
        local r, g, bl = Parts.SetItemIcon(b, it.texture, it.quality)
        b.name:SetText(it.name or "")
        local nc = it.nameColor   -- defaults to the quality color
        if nc then b.name:SetTextColor(nc[1], nc[2], nc[3]) else b.name:SetTextColor(r, g, bl) end
        b.sub:SetText(it.sub or "")
        local sc = it.subColor or Parts.DIM
        b.sub:SetTextColor(sc[1], sc[2], sc[3])
        local t = it.tint
        if t then b.icon:SetVertexColor(t[1], t[2], t[3]) else b.icon:SetVertexColor(1, 1, 1) end
        b.count:SetText((it.count or 0) > 1 and tostring(it.count) or "")
        Parts.PaintPick(b, it.picked == true)
        -- Text stops short of the mark. The mark fades in, but hides instantly
        -- when the tile is reused for an item without one.
        if it.mark then b.mark:SetTexture(it.mark) end
        local room = it.mark and -(Parts.ITEM_MARK + 14) or -6
        b.name:SetPoint("RIGHT", b, "RIGHT", room, 0)
        b.sub:SetPoint("RIGHT", b, "RIGHT", room, 0)
        DUI.Widgets.EaseShown(b.mark, it.mark ~= nil, not it.mark)
        if i % 2 == 1 then
            self.y = self.y + (#self.pieces > 0 and Parts.GAP or 0)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -self.y)
            b.col, b.colY = 1, self.y
            self.y = self.y + Parts.ITEM
            self.pieces[#self.pieces + 1] = b
        else
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.child, "TOPLEFT", half + Parts.GAP, -(self.y - Parts.ITEM))
            b.col, b.colY = 2, self.y - Parts.ITEM
            self.pieces[#self.pieces + 1] = b
        end
        b:SetSize(half, Parts.ITEM)
        tiles[i] = b
    end
    return tiles
end

-- A "why" card: a short explanation on a faint fill with a 2 px accent edge,
-- shown under the selected row. card:Set(text) wraps and sizes it, and it
-- fades in the first time it shows. opts.warn makes a solid warning card with
-- a WARN-colored edge, for laying over a page.
Parts.WHY_X, Parts.WHY_Y, Parts.WHY_EDGE = 10, 8, 2
function Parts.Why(parent, opts)
    local c = CreateFrame("Frame", nil, parent)
    c.warn = opts and opts.warn
    c.fill = tex(c, "BACKGROUND", c.warn and Style.BACKGROUND or { 1, 1, 1, 0.03 })
    c.fill:SetAllPoints(c)
    c.edge = tex(c, "ARTWORK")
    c.edge:SetWidth(Parts.WHY_EDGE)
    c.edge:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.edge:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    paintWhyEdge(c)
    c.text = Style.Text(c, Style.SIZE.small, "LEFT")
    c.text:SetWordWrap(true)
    c.text:SetSpacing(2)
    c.text:SetPoint("TOPLEFT", c, "TOPLEFT", Parts.WHY_X, -Parts.WHY_Y)
    Style.InkText(c.text, "TEXT")
    whys[c] = true
    c:SetScript("OnHide", function(self) self.seen = nil end)
    function c:Set(text)
        local w = self:GetWidth()
        if type(w) ~= "number" or w <= 0 then w = 300 end
        self.text:SetWidth(math.max(1, w - 2 * Parts.WHY_X))
        self.text:SetText(text or "")
        local h = self.text:GetStringHeight()
        if type(h) ~= "number" or h <= 0 then h = Style.SIZE.small + 4 end
        self:SetHeight(math.ceil(h) + 2 * Parts.WHY_Y)
        paintWhyEdge(self)
        if not self.seen then
            self.seen = true
            DUI.Motion.Fade(self, 0, 1, DUI.Motion.NORMAL)
        end
        return self
    end
    return c
end

function Stack:Why(text)
    local c = take(self, "why", Parts.Why)
    if c.keep then c.seen = true end
    c.keep = nil
    c:SetWidth(self:Width())
    c:Set(text)
    return put(self, c, c:GetHeight(), 4)
end

-- Money and experience rewards on one line.
function Stack:Money(copper, xp)
    local bits = {}
    if type(copper) == "number" and copper > 0 and DUI.MoneyString then
        bits[#bits + 1] = Parts.Hex(Style.INK.MONEY) .. DUI.MoneyString(copper) .. "|r"
    end
    if type(xp) == "number" and xp > 0 then
        bits[#bits + 1] = Parts.Hex(Style.INK.VALUE) .. string.format(L["%d experience"], xp) .. "|r"
    end
    if #bits == 0 then return nil end
    return self:Text(table.concat(bits, "     "), { size = Style.SIZE.body, color = Style.INK.VALUE })
end

-- ---------------------------------------------------------------------
-- Table: a virtualized list with sortable columns (W.ColumnHead). Only the
-- visible rows have frames, pooled per kind, so thousands of rows scroll
-- as cheaply as ten.
--
--   local t = Parts.Table(page, { head = cols, onSort, rowHeight = { line = Parts.LINE, step = 26 },
--       make = { line = fn(row) }, fill = { line = fn(row, data, cols) }, onClick(row, data, i),
--       onEnter(row, data), onLeave(row, data), top, bottom })
--   t:SetRows(list, keep)   -- each { kind, ... }; keep preserves the scroll position
--
-- Row frames are Buttons with the same hover and selection look as
-- Stack:Line. make builds a frame's contents once; fill paints them for each
-- row shown (cols = the head's { [id] = { x, w } }). Kind "why" is a
-- Parts.Why card sized to data.text.
-- t:Open(i, n) grows the n rows after i in from zero height while the rows
-- below slide down; t:Close(i, n, done) reverses it. Also t:Pick(i),
-- t:Scroll(px), t.bar, t.head, and t.shown[i] (the frame showing row i).
-- ---------------------------------------------------------------------

local Table = {}
Table.__index = Table
Parts.TableClass = Table

local function makeTableRow(t, kind)
    if kind == "why" then
        local c = Parts.Why(t.view)
        c:SetClipsChildren(true)
        return c
    end
    local b = CreateFrame("Button", nil, t.view)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetClipsChildren(true)
    b.hi = tex(b, "BACKGROUND", Parts.HI)
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.pick = tex(b, "BORDER", Parts.PICKED)
    b.pick:SetAllPoints(b)
    b.pick:Hide()
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 7)   -- Parts.Shine
    b.shine:SetTexture(Parts.WHITE)
    b.shine:SetBlendMode("ADD")
    b.shine:SetHeight(Parts.LINE)
    b.shine:Hide()
    b:SetScript("OnEnter", function(self)
        local d = self.data
        if not (d and d.dim) then Parts.Light(self.hi, true) end
        if d and t.opts.onEnter then t.opts.onEnter(self, d) end
    end)
    b:SetScript("OnLeave", function(self)
        Parts.Light(self.hi, false)
        if self.data and t.opts.onLeave then t.opts.onLeave(self, self.data) end
    end)
    b:SetScript("OnClick", function(self, button)
        local d = self.data
        if d and t.opts.link and button ~= "RightButton" and Parts.ItemClick(t.opts.link(d)) then return end
        if d and not d.dim and t.opts.onClick then
            sound("click")
            t.opts.onClick(self, d, self.index, button)
        end
    end)
    local make = t.opts.make and t.opts.make[kind]
    if make then make(b) end
    return b
end

function Parts.Table(page, opts)
    opts = opts or {}
    local t = setmetatable({ page = page, opts = opts, rows = {}, base = {}, tops = {}, grow = {},
                             pools = {}, shown = {}, at = 0, total = 0, growKey = {} }, Table)
    t.head = DUI.Widgets.ColumnHead(page, opts.head, function(id, desc)
        if opts.onSort then opts.onSort(id, desc) end
    end)
    t.head:SetPoint("TOPLEFT", page, "TOPLEFT", Parts.EDGE, -(opts.top or 12))
    t.head:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Parts.EDGE, -(opts.top or 12))
    local view = CreateFrame("Frame", nil, page)
    view:SetPoint("TOPLEFT", t.head, "BOTTOMLEFT", 0, -2)
    view:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Parts.EDGE, opts.bottom or 12)
    view:SetClipsChildren(true)
    t.view = view
    -- Hidden card used only to measure why-card heights at the row width.
    t.ruler = Parts.Why(view)
    t.ruler:Hide()
    t.ruler.seen = true
    t.bar = DUI.Widgets.Scroll(view, { step = Parts.WHEEL,
        read = function() return t:Range() end,
        write = function(v) t.at = v; t:Draw() end })
    view:SetScript("OnSizeChanged", function() t:Layout() end)
    return t
end

function Table:Width()
    local w = self.view:GetWidth()
    if type(w) ~= "number" or w <= 0 then
        local pw = self.page:GetWidth()
        w = (type(pw) == "number" and pw or 0) - 2 * Parts.EDGE
    end
    w = w + Win.GoalGrowth(self.page)
    if w <= 0 then w = 368 end
    return w
end

function Table:ViewHeight()
    local h = self.view:GetHeight()
    if type(h) ~= "number" or h <= 0 then
        local ph = self.page:GetHeight()
        h = (type(ph) == "number" and ph or 0) - (self.opts.top or 12) - (self.opts.bottom or 12) - DUI.Widgets.COLUMN_H - 2
    end
    return math.max(0, h)
end

-- Returns at, max, view for W.Scroll.
function Table:Range()
    local view = self:ViewHeight()
    return self.at, math.max(0, self.total - view), view
end

function Table:RowHeight(i)
    local b = self.base[i]
    if not b then return 0 end
    return b * (self.grow[i] or 1)
end

local function measure(t, i)
    local d = t.rows[i]
    local kind = d.kind or "line"
    if kind == "why" then
        t.ruler:SetWidth(t:Width())
        t.ruler:Set(d.text)
        return t.ruler:GetHeight()
    end
    local rh = t.opts.rowHeight
    return (rh and rh[kind]) or Parts.LINE
end

-- Recompute row tops from row `from` down.
local function relayout(t, from)
    from = math.max(1, from or 1)
    local y = from > 1 and (t.tops[from - 1] + t:RowHeight(from - 1)) or 0
    for i = from, #t.rows do
        t.tops[i] = y
        y = y + t:RowHeight(i)
    end
    for i = #t.rows + 1, #t.tops do t.tops[i] = nil end
    t.total = y
end

-- list: { { kind, ... } }. With keep, the scroll position and selection are
-- kept (the selection is found again by its data, since a re-sort moves it).
-- A running Open/Close is stopped and its done callback is NOT called.
function Table:SetRows(list, keep)
    local pickedData = keep and self.picked and self.rows[self.picked] or nil
    self.rows = list or {}
    self.picked = nil
    if pickedData then
        for i = 1, #self.rows do if self.rows[i] == pickedData then self.picked = i; break end end
    end
    if self.growing then self.growing = nil; DUI.Motion.Tween(self.growKey, 0, 0, 0) end
    self.base, self.grow = {}, {}
    self.gen = (self.gen or 0) + 1
    for i = 1, #self.rows do self.base[i] = measure(self, i) end
    relayout(self, 1)
    if not keep then self.bar.Stop(); self.at = 0 end
    self.cols = self.head:Layout(self:Width())
    self:Draw()
    self.bar.Update()
end

-- Called when the width changes. Re-measures columns and why cards.
function Table:Layout()
    if #self.rows == 0 then self.cols = self.head:Layout(self:Width()); return end
    for i = 1, #self.rows do
        if (self.rows[i].kind or "line") == "why" then self.base[i] = measure(self, i) end
    end
    relayout(self, 1)
    self.cols = self.head:Layout(self:Width())
    self.gen = (self.gen or 0) + 1
    self:Draw()
    self.bar.Update()
end

local function take(t, kind)
    local pool = t.pools[kind]
    if not pool then pool = { free = {}, n = 0 }; t.pools[kind] = pool end
    local b = table.remove(pool.free)
    if not b then
        b = makeTableRow(t, kind)
        b.kind = kind
        pool.n = pool.n + 1
    end
    return b
end

local function give(t, b)
    b:Hide()
    b.index, b.gen = nil, nil   -- keep b.data, Draw compares it for hover changes
    local pool = t.pools[b.kind]
    pool.free[#pool.free + 1] = b
end

-- Number of frames created for a kind. Used by tests.
function Table:Made(kind)
    local pool = self.pools[kind]
    return pool and pool.n or 0
end

-- First row whose bottom is below y. Binary search on the tops.
local function firstAt(t, y)
    local lo, hi = 1, #t.rows
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if t.tops[mid] <= y then lo = mid else hi = mid - 1 end
    end
    -- skip rows ending above y, but keep a zero-height row at y that is growing in
    while lo <= #t.rows do
        local h = t:RowHeight(lo)
        local bottom = t.tops[lo] + h
        if bottom < y or (bottom == y and h > 0) then lo = lo + 1 else break end
    end
    return lo
end

-- Assign and place frames for visible rows and release the rest.
function Table:Draw()
    local view, n = self:ViewHeight(), #self.rows
    local max = math.max(0, self.total - view)
    if self.at > max then self.at = max end
    if self.at < 0 then self.at = 0 end
    local at = self.at
    local want = self.want or {}   -- reused so scrolling makes no garbage
    self.want = want
    for i in pairs(want) do want[i] = nil end
    if n > 0 then
        local i = firstAt(self, at)
        while i <= n and self.tops[i] < at + view do
            want[i] = true
            i = i + 1
        end
    end
    for i, b in pairs(self.shown) do
        if not want[i] then give(self, b); self.shown[i] = nil end
    end
    local w = self:Width()
    for i in pairs(want) do
        local d = self.rows[i]
        local b = self.shown[i]
        if b and b.kind ~= (d.kind or "line") then give(self, b); self.shown[i] = nil; b = nil end
        if not b then
            b = take(self, d.kind or "line")
            self.shown[i] = b
        end
        local h = self:RowHeight(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.view, "TOPLEFT", 0, -(self.tops[i] - at))
        b:SetWidth(w)
        if b.gen ~= self.gen or b.index ~= i or b.data ~= d then
            -- The frame under a still mouse now shows a different row. The
            -- client fires no OnLeave/OnEnter for that, so fire them here to
            -- keep the tooltip in sync.
            local old = b.data
            local over = old ~= nil and old ~= d and b.kind ~= "why" and b:IsShown() and b:IsMouseOver() == true
            if over and self.opts.onLeave then self.opts.onLeave(b, old) end
            b.index, b.data, b.gen = i, d, self.gen
            if b.kind == "why" then
                b.seen = true   -- grows in via t:Open, so no fade on scroll
                b:Set(d.text)
            else
                Parts.Light(b.hi, not d.dim and b:IsMouseOver() == true, true)
                b.pick:SetShown(false)
                b.shine:Hide()
                Parts.PickLine(b, self.picked == i)
            end
            local fill = self.opts.fill and self.opts.fill[b.kind]
            if fill then fill(b, d, self.cols) end
            if over and self.opts.onEnter then self.opts.onEnter(b, d) end
        end
        b:SetHeight(math.max(0.01, h))
        b:SetAlpha(self.grow[i] or 1)
        b:Show()
    end
end

-- Jump to px from the top, no glide.
function Table:Scroll(px)
    self.bar.Stop()
    self.at = math.max(0, px or 0)
    self:Draw()
    self.bar.Update()
end

-- The frame showing row i, or nil if it's out of view.
function Table:Row(i) return self.shown[i] end

function Table:Pick(i)
    self.picked = i
    for j, b in pairs(self.shown) do
        if b.pick then Parts.PickLine(b, j == i) end
    end
end

-- Animate rows index+1 .. index+n from `from` to `to` height (0 closed,
-- 1 full), re-laying the rows below each step. A grow already running snaps
-- to its end first. Its done runs once the new grow has started, so if that
-- done calls SetRows, the new grow ends too.
local function growRows(t, index, n, from, to, done)
    local M = DUI.Motion
    local old = t.growing
    local first, last = index + 1, math.min(#t.rows, index + n)
    local from1 = first
    if old then
        t.growing = nil
        M.Tween(t.growKey, 0, 0, 0)
        for i = old.first, old.last do t.grow[i] = old.to < 1 and old.to or nil end
        from1 = math.min(first, old.first)
    end
    local g
    if last >= first then
        g = { first = first, last = last, to = to, done = done }
        t.growing = g
        for i = first, last do t.grow[i] = from end
    end
    relayout(t, from1)
    t:Draw()
    t.bar.Update()
    if old and old.done then old.done() end
    if not g then if done then done() end; return end
    if t.growing ~= g then return end   -- old done refilled the list
    M.Tween(t.growKey, from, to, M.NORMAL, function(p)
        if t.growing ~= g then return end
        for i = first, last do t.grow[i] = p end
        relayout(t, first)
        t:Draw()
        t.bar.Update()
    end, function()
        if t.growing ~= g then return end
        t.growing = nil
        if to >= 1 then for i = first, last do t.grow[i] = nil end end
        relayout(t, first)
        t:Draw()
        if done then done() end
    end)
end

function Table:Open(index, n) growRows(self, index or 0, n or 1, 0, 1) end
function Table:Close(index, n, done) growRows(self, index or 0, n or 1, 1, 0, done) end

-- ---------------------------------------------------------------------
-- Footer: buttons along the bottom, main action on the left like the game's
-- ---------------------------------------------------------------------

local Footer = {}
Footer.__index = Footer

-- opts.edge: side inset in px. opts.equal: buttons share the width evenly,
-- for narrow pages.
function Parts.Footer(page, opts)
    opts = opts or {}
    local foot = setmetatable({ buttons = {}, equal = opts.equal }, Footer)
    local edge = opts.edge or Parts.EDGE
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", edge, 12)
    f:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -edge, 12)
    f:SetHeight(28)
    f.line = tex(f, "ARTWORK", { 1, 1, 1, 0.06 })
    f.line:SetHeight(1)
    f.line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 10)
    f.line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 10)
    foot.frame = f
    f.padFooter = foot   -- the controller's X finds the main button through it (Pad.FindParts)
    return foot
end

-- Footer buttons are plain W.Buttons, not accent colored (class colors would
-- look gaudy). The main action gets a lifted band and green text, a refusal
-- (tone = "no") red text.
Parts.YES = Style.INK.GOOD
Parts.NO = Style.INK.BAD

-- Apply a footer tone to any W.Button: "main", "no" or nil for plain. The
-- band picks up the change on the button's next repaint (SetOff, hover).
function Parts.Tone(b, tone)
    b.main = tone == "main"
    local c = (tone == "main" and Parts.YES) or (tone == "no" and Parts.NO) or DUI.Widgets.BUTTON.text
    b.text:SetTextColor(c[1], c[2], c[3], 1)
end

local function button(foot, i)
    local b = foot.buttons[i]
    if b then return b end
    b = DUI.Widgets.Button(foot.frame, "", 28)
    b:SetScript("OnClick", function(self)
        if self.spec and not self.spec.off and self.spec.onClick then self.spec.onClick(self) end
    end)
    foot.buttons[i] = b
    return b
end

-- list: { { text, primary, tone, off, onClick, key, beside } }, left to right,
-- following the game's layout: the primary action in the left corner, the rest
-- packed to the right with the last (Goodbye, Decline) in the right corner.
-- beside places a button right after the previous one instead.
Footer.GAP = 8
Footer.EQUAL_GAP = 6
Footer.PAD = 20      -- text padding in a shared row
Footer.FIT = 110     -- minimum button width when sizing to text

-- Size each button to its text and split the leftover space evenly, so a long
-- label isn't cut while a short one has room to spare. When space is short,
-- every button gives up padding equally, then the room is split evenly.
function Footer.Share(foot, list, room)
    local n, need, sizes = #list, 0, {}
    for i = 1, n do
        local w = foot.buttons[i].text:GetStringWidth()
        if type(w) ~= "number" then w = 40 end
        sizes[i] = math.ceil(w) + Footer.PAD
        need = need + sizes[i]
    end
    local spare = room - need
    if spare >= 0 then
        local each = math.floor(spare / n)
        for i = 1, n do sizes[i] = sizes[i] + each end
    elseif spare > -Footer.PAD * n then
        local cut = math.ceil(-spare / n)
        for i = 1, n do sizes[i] = sizes[i] - cut end
    else
        local each = math.floor(room / n)
        for i = 1, n do sizes[i] = each end
    end
    return sizes
end
function Footer:Set(list)
    for i, b in ipairs(self.buttons) do if not list[i] then b:Hide() end end
    local right
    local gap = self.equal and Footer.EQUAL_GAP or Footer.GAP
    local width = self.frame:GetWidth()
    local fill = self.equal and type(width) == "number" and width > 0 and #list > 0
    for i = 1, #list do
        local spec = list[i]
        local b = button(self, i)
        local label = spec.text or ""
        if spec.key then label = label .. "  " .. Parts.Hex({ Style.Pop() }) .. spec.key .. "|r" end
        b.text:SetWidth(0)
        b.text:SetText(label)
    end
    -- Buttons fit their text (at least FIT). If that overflows the row, e.g.
    -- with a wide font, share the room instead of overlapping.
    if not fill and type(width) == "number" and width > 0 and #list > 0 then
        local need = gap * (#list - 1)
        for i = 1, #list do
            local w = self.buttons[i].text:GetStringWidth()
            need = need + math.max(Footer.FIT, (type(w) == "number" and w or 60) + 32)
        end
        fill = need > width
    end
    local sizes = fill and Footer.Share(self, list, width - gap * (#list - 1)) or nil
    for i = #list, 1, -1 do
        local spec = list[i]
        local b = button(self, i)
        b.spec = spec
        if sizes then
            b:SetWidth(sizes[i])
            b.text:SetWidth(sizes[i] - 8)
            b.text:SetWordWrap(false)
        else
            b.FitWidth(Footer.FIT)
        end
        Parts.Tone(b, (spec.primary == true and "main") or (spec.tone == "no" and "no") or nil)
        b.SetOff(spec.off)
        b:ClearAllPoints()
        if b.main then b:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
        elseif spec.beside and i > 1 then b:SetPoint("LEFT", self.buttons[i - 1], "RIGHT", gap, 0)
        elseif right then b:SetPoint("RIGHT", right, "LEFT", -gap, 0)
        else b:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0) end
        b:Show()
        if not b.main and not spec.beside then right = b end
    end
end

-- Press a footer button from the keyboard (Enter or Space), with a bump.
function Footer:Press(i)
    local b = self.buttons[i or 1]
    if b and b:IsShown() and b.spec and not b.spec.off and b.spec.onClick then
        if DUI.Motion then DUI.Motion.Bump(b, 0.96) end
        sound("click")
        b.spec.onClick(b)
        return true
    end
    return false
end
