-- The detail card beside a Social list (Friends, Recent allies): the picked person's
-- icon and name, what's known about them, and the buttons that apply to them right
-- now. Picking a row widens the window to make room on the right; picking it again (or
-- losing it from the list) closes the card and the window goes back. A button that
-- doesn't apply isn't dimmed, it isn't there: no Invite for someone already in the
-- group, no Add friend for a friend.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local Win = DUI.Win
local Style = DUI.Style

local Detail = {}
Detail.__index = Detail
ns.Detail = Detail

Detail.W = 264          -- the card's width (wide enough for a name with its level and a long value to wrap kindly)
Detail.GAP = 12         -- between the list and the card
Detail.SPAN = Detail.W + Detail.GAP   -- how much room the window makes for it
Detail.EDGE = 16        -- from the page's right edge, like the list's
Detail.TOP = 10         -- from the page's top, level with the search box
Detail.REST = 12        -- from the page's bottom
Detail.PAD = 12         -- inside the card
Detail.ICON = 44
-- The lines are laid out by the height their text really has (it grows with the text scale);
-- these are what they come to at the default size, and what a text that can't be measured gets.
Detail.ROW = 46         -- a titled line: its title, the rule under it, its value
Detail.PLAIN = 22       -- a line with no title
Detail.LETTER_X = 1       -- the badge's letter, nudged to the right: the font sets its glyphs a little left of the box's middle
Detail.LETTER_Y = 0
Detail.LINE_H = 14      -- one line of a value
Detail.MAX_LINES = 4     -- of a value, unless its line asks for more (spec.rows[i].lines)
Detail.ROWS = 10        -- most lines of information
Detail.BUTTON = 28      -- a button's height (Parts.Footer's)
Detail.BUTTON_GAP = 6
Detail.BUTTONS = 4      -- most buttons
Detail.GAP_AFTER = 10   -- under the lines with no title, before the titled ones
Detail.NAME = 15        -- the name's line, and the one under it
Detail.UNDER = 14
Detail.RULE_GAP = 3     -- a title's rule sits this far under its text
Detail.VALUE_GAP = 7    -- and its value this far under the rule
Detail.AFTER = 8        -- under each line
Detail.FILL = { 1, 1, 1, 0.035 }
Detail.PERSON = 26      -- a person's line (spec.rows[i].people): a role badge, the name, the level
Detail.PEOPLE = 10      -- most of them
Detail.BADGE = 16
Detail.PERSON_RULE = { 1, 1, 1, 0.05 }

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end

-- A text's height as drawn (it follows the text scale), or what it comes to at the default.
local function tall(fs, fallback)
    local h = fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then return fallback end
    return h
end

local function tex(parent, layer, color)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(WHITE)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- opts: side(open) (the window makes or gives back the room), fit(p) (the page's widgets
-- move over by p of the card's room, p from 0 to 1, as the list's edge eases), refill()
-- (lay the list out again at its new width, once it has got there).
function Detail.New(page, opts)
    local d = setmetatable({ page = page, opts = opts, open = false, rows = {}, buttons = {} }, Detail)
    d.w = Detail.W
    local f = CreateFrame("Frame", nil, page)
    f:SetWidth(d.w)
    f:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Detail.EDGE, -Detail.TOP)
    f:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Detail.EDGE, Detail.REST)
    f:SetAlpha(0)
    f:Hide()
    d.frame = f
    f.fill = tex(f, "BACKGROUND", Detail.FILL)
    f.fill:SetAllPoints(f)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(Detail.ICON, Detail.ICON)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -Detail.PAD)
    -- No class to show (a Battle.net friend, someone offline): their initial in a round
    -- badge in the accent.
    f.avatar = f:CreateTexture(nil, "ARTWORK")
    f.avatar:SetTexture(DUI.MEDIA .. "shape-circle.png")
    f.avatar:SetSize(Detail.ICON, Detail.ICON)
    f.avatar:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -Detail.PAD)
    f.letter = Style.Text(f, Style.SIZE.title, "CENTER")
    -- A box as big as the badge, set outright (a box sized by its anchors can come out
    -- narrow and clip the letter to a sliver).
    f.letter:SetSize(Detail.ICON, Detail.ICON)
    f.letter:SetPoint("CENTER", f.avatar, "CENTER", Detail.LETTER_X, Detail.LETTER_Y)
    f.letter:SetWordWrap(false)
    f.letter:SetJustifyH("CENTER")
    f.letter:SetJustifyV("MIDDLE")
    f.title = Style.Text(f, Style.SIZE.body, "LEFT")
    f.title:SetWordWrap(false)
    f.sub = Style.Text(f, Style.SIZE.small, "LEFT")
    f.sub:SetWordWrap(false)
    Style.InkText(f.sub, "LABEL")
    f.rule = tex(f, "ARTWORK", { 1, 1, 1, 0.06 })
    f.rule:SetHeight(1)
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -(Detail.PAD * 2 + Detail.ICON))
    f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Detail.PAD, -(Detail.PAD * 2 + Detail.ICON))
    for i = 1, Detail.ROWS do
        local r = {}
        r.label = Style.Text(f, Style.SIZE.small, "LEFT")
        r.label:SetWordWrap(false)
        r.rule = tex(f, "ARTWORK", { 1, 1, 1, 0.1 })
        r.rule:SetHeight(1)
        r.value = Style.Text(f, Style.SIZE.small, "LEFT")
        r.value:SetWordWrap(true)   -- a long text goes on to the next line, up to MAX_LINES
        if r.value.SetMaxLines then r.value:SetMaxLines(Detail.MAX_LINES) end
        d.rows[i] = r
    end
    for i = 1, Detail.BUTTONS do
        local b = W().Button(f, "", Detail.BUTTON)
        b:SetScript("OnClick", function(self)
            if self.spec and not self.spec.off and self.spec.onClick then self.spec.onClick(self) end
        end)
        b:Hide()
        d.buttons[i] = b
    end
    -- People lines: a role's badge, a name and a level, each on its own line and all level
    -- with each other (a line of text with a badge drawn in it sits crooked).
    d.people = {}
    for i = 1, Detail.PEOPLE do
        local m = CreateFrame("Frame", nil, f)
        m:SetHeight(Detail.PERSON)
        m.badge = W().Role(m, Detail.BADGE)
        m.badge:SetPoint("LEFT", m, "LEFT", 0, 0)
        m.level = Style.Text(m, Style.SIZE.small, "RIGHT")
        m.level:SetPoint("RIGHT", m, "RIGHT", 0, 0)
        Style.InkText(m.level, "LABEL")
        m.name = Style.Text(m, Style.SIZE.small, "LEFT")
        m.name:SetWordWrap(false)
        m.name:SetPoint("LEFT", m.badge, "RIGHT", 8, 0)
        m.name:SetPoint("RIGHT", m.level, "LEFT", -8, 0)
        m.line = tex(m, "ARTWORK", Detail.PERSON_RULE)
        m.line:SetHeight(1)
        m.line:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", 0, 0)
        m.line:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
        m:Hide()
        d.people[i] = m
    end
    -- The controller's X presses the main button (Pad.FindParts finds it through this).
    f.padFooter = { frame = f, buttons = d.buttons }
    return d
end

-- spec: { icon = { file, l, r, t, b } or nil, initial (the badge's letter's source, when
-- the title can't be read), title, color, sub,
-- rows = { { label, value, color, lines (most lines of the value, default MAX_LINES),
-- spacing (pixels between the value's lines), people = { { role, open, name, level } } (in
-- place of the value: a line to each, the badge, the name and the level lined up) } }, buttons = { { text, primary, onClick } } }, or nil
-- to close. Returns true when the card opened or closed (the list is laid out again at
-- its new width next frame).
function Detail:Set(spec)
    local f = self.frame
    if not spec then
        if not self.open then return false end
        self.open = false
        self:Fade(false)
        self:Slide(false)
        if self.opts.side then self.opts.side(false) end
        return true
    end
    -- The icon: the class's, else a plain one.
    local icon = spec.icon
    f.icon:SetShown(icon ~= nil and icon[1] ~= nil)
    f.avatar:SetShown(not f.icon:IsShown())
    f.letter:SetShown(not f.icon:IsShown())
    if icon and icon[1] then
        f.icon:SetTexture(icon[1])
        f.icon:SetTexCoord(icon[2] or 0, icon[3] or 1, icon[4] or 0, icon[5] or 1)
        f.icon:SetVertexColor(1, 1, 1, 1)
    else
        Style.PaintAccent(f.avatar, 0.22)
        -- A Battle.net name can be a protected string ("|K...|k", only a FontString can
        -- draw it) whose first letter we can't read: the page passes the plain letters.
        local word = spec.initial or spec.title or "?"
        if word:find("|K", 1, true) then word = "?" end
        f.letter:SetText(string.upper(string.match(word, "^[%z\1-\127\194-\244][\128-\191]*") or "?"))
        Style.InkText(f.letter, "pop")
    end
    -- The name and what's under it, as one block centered on the icon (the header is as
    -- tall as the icon, or as the block if the text scale made that taller).
    local left = Detail.PAD * 2 + Detail.ICON
    local textW = self.w - left - Detail.PAD
    local sub = (spec.sub or "") ~= ""
    f.title:SetText(spec.title or "")
    f.title:SetWidth(textW)
    f.sub:SetText(spec.sub or "")
    f.sub:SetWidth(textW)
    local titleH = tall(f.title, Detail.NAME)
    local block = titleH + (sub and (tall(f.sub, Detail.UNDER - 2) + 2) or 0)
    local head = math.max(Detail.ICON, math.ceil(block))
    local top = Detail.PAD + math.floor((head - block) / 2)
    local iconTop = Detail.PAD + math.floor((head - Detail.ICON) / 2)
    for _, t in ipairs({ f.icon, f.avatar }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -iconTop)
    end
    local c = spec.color or Style.INK.VALUE
    f.title:SetTextColor(c[1], c[2], c[3])
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top)
    f.sub:SetShown(sub)
    f.sub:ClearAllPoints()
    f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", left, -(top + titleH + 2))
    f.rule:ClearAllPoints()
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -(Detail.PAD * 2 + head))
    f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Detail.PAD, -(Detail.PAD * 2 + head))
    -- Buttons from the bottom up; the information gets what room is left above them.
    local list = spec.buttons or {}
    local n = math.min(#list, Detail.BUTTONS)
    for i = 1, Detail.BUTTONS do
        local b = self.buttons[i]
        local s = list[i]
        if s and i <= n then
            b.spec = s
            b.text:SetText(s.text or "")
            b:SetWidth(self.w - Detail.PAD * 2)
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", Detail.PAD, Detail.PAD + (n - i) * (Detail.BUTTON + Detail.BUTTON_GAP))
            Win.Parts.Tone(b, s.primary == true and "main" or nil)
            b.SetOff(s.off)
            b:Show()
        else
            b.spec = nil
            b:Hide()
        end
    end
    local buttonsH = n > 0 and (n * Detail.BUTTON + (n - 1) * Detail.BUTTON_GAP + Detail.PAD) or 0
    local rowsTop = Detail.PAD * 2 + head + 10
    local height = self.page:GetHeight()
    -- The room the lines have, down to the buttons (all of it when the page isn't measured).
    local room = math.huge
    if type(height) == "number" and height > 0 then
        room = height - Detail.TOP - Detail.REST - rowsTop - buttonsH - Detail.PAD
    end
    local rows = spec.rows or {}
    for _, m in ipairs(self.people) do m:Hide() end
    local y = rowsTop
    local spent = 0
    local plainBefore = false
    for i = 1, Detail.ROWS do
        local r, s = self.rows[i], rows[i]
        local hasLabel = s and (s.label or "") ~= ""
        local h, air, lh, vh = 0, 0, Detail.LINE_H, Detail.LINE_H
        if s then
            -- The texts first, at their width: their heights are what the line takes.
            r.label:SetText(s.label or "")
            r.label:SetWidth(self.w - Detail.PAD * 2)
            r.value:SetWidth(self.w - Detail.PAD * 2)
            local cap = s.lines or Detail.MAX_LINES
            -- spacing: air between the value's lines (a list of people reads better apart).
            local gap = s.spacing or 0
            r.value:SetSpacing(gap)
            if r.value.SetMaxLines then r.value:SetMaxLines(cap) end
            r.value:SetText(s.people and "" or s.value or "")
            lh = tall(r.label, Detail.LINE_H)
            vh = math.min(math.max(tall(r.value, lh), lh), (lh + gap) * cap)
            if s.people then vh = math.min(#s.people, Detail.PEOPLE) * Detail.PERSON end
            -- A titled line: title, rule, value. An untitled one: the value alone.
            h = (hasLabel and (lh + Detail.RULE_GAP + Detail.VALUE_GAP) or 0) + vh + Detail.AFTER
            -- Some air between the untitled lines (the status) and the titled ones.
            air = (hasLabel and plainBefore) and Detail.GAP_AFTER or 0
        end
        if s and spent + h + air <= room then
            y = y + air
            spent = spent + h + air
            plainBefore = not hasLabel
            r.label:SetShown(hasLabel)
            r.rule:SetShown(hasLabel)
            r.label:ClearAllPoints()
            r.label:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -y)
            local valueY = y
            if hasLabel then
                Style.InkText(r.label, "pop")
                Style.PaintAccent(r.rule, 0.3)
                local ruleY = y + lh + Detail.RULE_GAP
                r.rule:ClearAllPoints()
                r.rule:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -ruleY)
                r.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Detail.PAD, -ruleY)
                valueY = ruleY + Detail.VALUE_GAP
            end
            local vc = s.color or Style.INK.VALUE
            r.value:SetTextColor(vc[1], vc[2], vc[3])
            r.value:ClearAllPoints()
            r.value:SetPoint("TOPLEFT", f, "TOPLEFT", Detail.PAD, -valueY)
            r.value:SetShown(s.people == nil)
            if s.people then self:Place(s.people, valueY) end
            y = y + h
        else
            r.label:Hide()
            r.rule:Hide()
            r.value:Hide()
        end
    end
    if self.open then return false end
    self.open = true
    f:Show()
    self:Fade(true)
    self:Slide(true)
    if self.opts.side then self.opts.side(true) end
    return true
end

-- The people lines of a row, from y down: { { role, open, name, level } }. An open spot is a
-- ring of the role and the name in the quiet color.
function Detail:Place(list, y)
    local n = math.min(#list, Detail.PEOPLE)
    for i = 1, n do
        local p, m = list[i], self.people[i]
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", self.frame, "TOPLEFT", Detail.PAD, -(y + (i - 1) * Detail.PERSON))
        m:SetWidth(self.w - Detail.PAD * 2)
        m.badge.Set(p.role, p.open)   -- (a function of the badge, not a method)
        m.name:SetText(p.name or "")
        local c = p.open and Style.INK.OFF or Style.INK.VALUE
        m.name:SetTextColor(c[1], c[2], c[3])
        m.level:SetText(p.level and tostring(p.level) or "")
        m.line:SetShown(i < n)
        m:Show()
    end
end

-- The card's fade in and out (the window's width eases on its own).
function Detail:Fade(on)
    local f = self.frame
    local M = DUI.Motion
    local function done() if not on then f:Hide() end end
    if M then M.Tween(f, f:GetAlpha(), on and 1 or 0, M.NORMAL, function(a) f:SetAlpha(a) end, done)
    else f:SetAlpha(on and 1 or 0); done() end
end

-- The list's right edge (and what keeps to it) eases to or from the card's room. The rows
-- are laid out again at the end, when the list has its final width.
function Detail:Slide(on)
    local M = DUI.Motion
    local to = on and 1 or 0
    local function step(p)
        self.slide = p
        if self.opts.fit then self.opts.fit(p) end
    end
    local function done()
        if self.opts.refill then C_Timer.After(0, self.opts.refill) end
    end
    if M then M.Tween(self, self.slide or 0, to, M.NORMAL, step, done)
    else step(to); done() end
end

function Detail:IsOpen() return self.open end
