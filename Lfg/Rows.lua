-- List pieces shared by the group finder's three pages: a row (group, person or
-- activity, with text and a sub line on the left and role badges or a value on the
-- right; hover lights it, selection gets an accent wash like Parts.PickLine), the group
-- opened in place (note, members, open spots, Whisper and Invite), the party tooltip
-- (DUI.Tips) and the right-click menu (W.OpenMenu at the cursor).

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Rows = {}
ns.Rows = Rows

Rows.GROUP = 40       -- group row
Rows.GROUP_NOTE = 56  -- group row with a note under the sub line
Rows.PERSON = 36      -- who list row
Rows.ACTIVITY = 28    -- activity row
Rows.BADGES = 5       -- max role badges per row (a dungeon's five)
Rows.MEMBER = 22      -- member row in an opened group
Rows.MEMBERS = 5      -- members listed by name; bigger groups get counts
Rows.BUTTON = 24
Rows.DOT = 7          -- status dot

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end
local function sound(name) if DUI.Sound then DUI.Sound.Play(name) end end

local function tex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(WHITE)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

-- "Gorrak Stonefist" in their class color, as an escape string.
function Rows.Named(name, class)
    if type(name) ~= "string" then return "" end
    local r, g, b = Style.ClassTextColor(class)
    return Win.Parts.Hex({ r, g, b }) .. name .. "|r"
end

-- Localized class name ("Warrior") from its token.
function Rows.ClassWord(token)
    if type(token) ~= "string" then return "" end
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (type(names) == "table" and names[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end

-- How long ago it was listed: "just now", "20 min", "2 h".
function Rows.Age(seconds)
    if type(seconds) ~= "number" then return "" end
    if seconds < 60 then return L["just now"] end
    if seconds < 3600 then return string.format(L["%d min"], math.floor(seconds / 60)) end
    return string.format(L["%d h"], math.floor(seconds / 3600))
end

-- Row

local function makeRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hi = tex(b, "BACKGROUND", Win.Parts.HI)
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.pick = tex(b, "BORDER", Win.Parts.PICKED)
    b.pick:SetAllPoints(b)
    b.pick:Hide()
    b.value = Style.Text(b, Style.SIZE.body, "RIGHT")
    b.value:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.age = Style.Text(b, Style.SIZE.tiny, "RIGHT")
    b.age:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 4)
    Style.InkText(b.age, "LABEL")
    b.badges = {}
    for i = 1, Rows.BADGES do
        local r = W().Role(b)
        r:Hide()
        b.badges[i] = r
    end
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetWordWrap(false)
    -- Status dot left of the name (online, away, busy, as in the social window).
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetTexture(DUI.MEDIA .. "shape-circle.png")
    b.dot:SetSize(Rows.DOT, Rows.DOT)
    b.dot:SetPoint("RIGHT", b.name, "LEFT", -7, 0)
    b.dot:Hide()
    -- A soft light sweeps across once (Parts.Shine, as for a friend logging in).
    b.shine = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.shine:SetTexture(Win.Parts.WHITE)
    b.shine:SetBlendMode("ADD")
    b.shine:Hide()
    b.sub = Style.Text(b, Style.SIZE.small, "LEFT")
    b.sub:SetWordWrap(false)
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.note = Style.Text(b, Style.SIZE.small, "LEFT")
    b.note:SetWordWrap(false)
    b.note:SetPoint("TOPLEFT", b.sub, "BOTTOMLEFT", 0, -3)
    Style.InkText(b.note, "TEXT")
    b:SetScript("OnEnter", function(self)
        Win.Parts.Light(self.hi, true)
        if self.spec and self.spec.onEnter then self.spec.onEnter(self) end
    end)
    b:SetScript("OnLeave", function(self)
        Win.Parts.Light(self.hi, false)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self, button)
        local spec = self.spec
        if not spec then return end
        if button == "RightButton" then
            if spec.onMenu then spec.onMenu(self) end
            return
        end
        if spec.onClick then
            sound("click")
            spec.onClick(self)
        end
    end)
    return b
end

-- Badges laid out right to left from the row's right edge (or left of the age).
local function badges(b, list, top)
    local right, n = -8, 0
    for i = Rows.BADGES, 1, -1 do
        local item = list and list[i]
        local badge = b.badges[i]
        if item then
            n = n + 1
            badge.Set(item.role, item.open)
            badge:ClearAllPoints()
            badge:SetPoint(top and "TOPRIGHT" or "RIGHT", b, top and "TOPRIGHT" or "RIGHT", right, top and -6 or 0)
            right = right - W().ROLE - 3
        else
            badge:Hide()
        end
    end
    return n
end

-- spec: { kind (pool), height, text, color, sub, subColor, note (third line), value,
-- valueColor, age, roles = { { role, open } }, dot (status dot color), picked, dim,
-- id (identity across refills, for Stack:Ease), onClick(b), onMenu(b), onEnter(b) }
function Rows.Row(stack, spec)
    local h = spec.height or Rows.GROUP
    local b = stack:Piece(spec.kind or "row", makeRow, h, 2, spec.id)
    b.spec = spec
    b.shine:SetHeight(h)
    local c = spec.color or Style.INK.VALUE
    b.name:SetText(spec.text or "")
    b.name:SetTextColor(c[1], c[2], c[3])
    b.sub:SetText(spec.sub or "")
    local sc = spec.subColor or Style.INK.LABEL
    b.sub:SetTextColor(sc[1], sc[2], sc[3])
    b.sub:SetShown((spec.sub or "") ~= "")
    b.note:SetText(spec.note or "")
    b.note:SetShown(spec.note ~= nil)
    b.value:SetText(spec.value or "")
    local vc = spec.valueColor or Style.INK.VALUE
    b.value:SetTextColor(vc[1], vc[2], vc[3])
    b.age:SetText(spec.age or "")
    local hasAge = (spec.age or "") ~= ""
    local n = badges(b, spec.roles, hasAge)
    -- Text stops short of whatever is on the right.
    local room = 10
    if n > 0 then room = room + n * (W().ROLE + 3) end
    local vw = b.value:GetStringWidth()
    if (spec.value or "") ~= "" and type(vw) == "number" then room = math.max(room, vw + 18) end
    local left = 8
    if spec.dot then
        b.dot:SetVertexColor(spec.dot[1], spec.dot[2], spec.dot[3], 1)
        left = 10 + Rows.DOT + 7
    end
    b.dot:SetShown(spec.dot ~= nil)
    b.name:ClearAllPoints()
    if b.sub:IsShown() then b.name:SetPoint("TOPLEFT", b, "TOPLEFT", left, -(h - (spec.note and 46 or 30)) / 2 - 2)
    else b.name:SetPoint("LEFT", b, "LEFT", left, 0) end
    b.name:SetPoint("RIGHT", b, "RIGHT", -room, 0)
    b.sub:SetPoint("RIGHT", b, "RIGHT", -room, 0)
    -- The note runs under the badges, up to the age.
    local aw = b.age:GetStringWidth()
    b.note:SetPoint("RIGHT", b, "RIGHT", -(hasAge and type(aw) == "number" and aw + 18 or 10), 0)
    b:SetAlpha(spec.dim and 0.5 or 1)
    Win.Parts.Light(b.hi, b:IsMouseOver() == true, true)
    Rows.Pick(b, spec.picked == true)
    return b
end

function Rows.Pick(b, on)
    if b.spec then b.spec.picked = on end
    b.pick:SetShown(on)
    if on then Style.PaintAccent(b.pick, 0.16) end
end

-- Group members: who's in, which roles are still needed

-- Row badges: a solo player's roles; a dungeon group's five slots (filled when taken,
-- rings when open); none for bigger groups (their counts show when opened and in the
-- tooltip).
function Rows.Badges(r)
    local out = {}
    if r.solo then
        local roles = r.roles or {}
        for _, role in ipairs(ns.Data.ROLES) do
            if roles[ns.Data.ROLE_KEY[role]] then out[#out + 1] = { role = role } end
        end
        return out
    end
    if r.size > 5 then return out end
    local have, open = ns.Data.Places(r)
    for _, role in ipairs(ns.Data.ROLES) do
        for _ = 1, have[role] do out[#out + 1] = { role = role } end
        for _ = 1, open[role] do out[#out + 1] = { role = role, open = true } end
    end
    while #out > Rows.BADGES do table.remove(out) end
    return out
end

-- "3 / 40" plus role counts, for groups too big to list by name.
function Rows.Counts(r)
    local have = ns.Data.Places(r)
    local bits = {}
    for _, role in ipairs(ns.Data.ROLES) do bits[#bits + 1] = W().RoleText(role, 12) .. " " .. have[role] end
    return table.concat(bits, "   "), string.format(L["%d / %d"], #r.members, r.size)
end

-- Party tooltip on mouseover.
function Rows.Tip(owner, r)
    if not (GameTooltip and r) then return end
    local T = DUI.Tips
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    T.Clear()
    T.Title(r.mine and L["Your listing"] or r.text)
    local who = Rows.Named(r.leader.name, r.leader.class)
    local bits = {}
    if who ~= "" then bits[#bits + 1] = who end
    if type(r.leader.level) == "number" then bits[#bits + 1] = string.format(L["level %d"], r.leader.level) end
    local age = Rows.Age(r.age)
    if age ~= "" then bits[#bits + 1] = age end
    T.Sub(table.concat(bits, " · "))
    if r.mine then T.Text(r.text) end
    if r.leader.zone then T.Line(L["Zone"], r.leader.zone, Style.INK.WARN) end
    if r.style then T.Line(L["Playstyle"], r.style, r.styleInk) end
    if r.note then T.Text(r.note) end
    if r.newcomers then T.Text(L["New players welcome"], Style.INK.GOOD) end
    if r.delisted then T.Text(L["No longer listed"], Style.INK.WARN) end
    T.Gap()
    if r.size > Rows.MEMBERS and not r.solo then
        local line, of = Rows.Counts(r)
        T.Line(line, of)
    else
        for _, m in ipairs(r.members) do
            T.Line(W().RoleText(m.role) .. " " .. Rows.Named(m.name, m.class),
                (type(m.level) == "number" and (m.level .. " ") or "") .. Rows.ClassWord(m.class))
        end
        if r.solo then
            local can = {}
            for _, item in ipairs(Rows.Badges(r)) do can[#can + 1] = W().RoleText(item.role) end
            if #can > 0 then T.Line(L["Can be"], table.concat(can, " ")) end
        else
            local _, open = ns.Data.Places(r)
            for _, role in ipairs(ns.Data.ROLES) do
                for _ = 1, open[role] do T.Line(Win.Parts.Hex(Style.INK.OFF) .. L["Open spot"] .. "|r " .. W().RoleText(role), "") end
            end
        end
    end
    T.Gap()
    T.Hint(L["Click: see the group"])
    T.Hint(L["Right-click: whisper or invite"])
    T.Flush(GameTooltip)
    GameTooltip:Show()
end

-- Whisper / Invite at the cursor (W.OpenMenu; Invite only when the game would allow it).
function Rows.Menu(owner, name, canInvite)
    if type(name) ~= "string" then return end
    local keys, values = { "whisper" }, { whisper = WHISPER or L["Whisper"] }
    if canInvite then
        keys[2] = "invite"
        values.invite = INVITE or L["Invite"]
    end
    W().OpenMenu(owner, keys, values, nil, function(k)
        if k == "whisper" then ns.Data.Whisper(name) elseif k == "invite" then ns.Data.Invite(name) end
    end, nil, { atCursor = true })
end

-- Group opened in place: note, members, buttons

local function memberLine(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetHeight(Rows.MEMBER)
    m.badge = W().Role(m, 14)
    m.badge:SetPoint("LEFT", m, "LEFT", 0, 0)
    m.name = Style.Text(m, Style.SIZE.body, "LEFT")
    m.name:SetPoint("LEFT", m.badge, "RIGHT", 8, 0)
    m.what = Style.Text(m, Style.SIZE.small, "RIGHT")
    m.what:SetPoint("RIGHT", m, "RIGHT", 0, 0)
    Style.InkText(m.what, "LABEL")
    return m
end

local function makeOpened(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetClipsChildren(true)
    d.inner = CreateFrame("Frame", nil, d)
    d.inner:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
    d.inner:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)
    d.bar = tex(d.inner, "ARTWORK")
    d.bar:SetWidth(2)
    d.noteBg = tex(d.inner, "BACKGROUND", { 1, 1, 1, 0.03 })
    d.note = Style.Text(d.inner, Style.SIZE.body, "LEFT")
    d.note:SetWordWrap(true)
    d.note:SetSpacing(3)
    Style.InkText(d.note, "TEXT")
    d.head = Style.Text(d.inner, Win.Parts.HEAD, "LEFT")
    d.lines = {}
    for i = 1, Rows.MEMBERS + 5 do d.lines[i] = memberLine(d.inner) end
    d.count = Style.Text(d.inner, Style.SIZE.body, "LEFT")
    d.countOf = Style.Text(d.inner, Style.SIZE.small, "RIGHT")
    Style.InkText(d.countOf, "LABEL")
    d.main = W().Button(d.inner, "", Rows.BUTTON)
    d.second = W().Button(d.inner, "", Rows.BUTTON)
    d.main:SetScript("OnClick", function(self) if self.act then self.act() end end)
    d.second:SetScript("OnClick", function(self) if self.act then self.act() end end)
    return d
end

local function setButton(b, text, act, off, main)
    b.text:SetText(text)
    b.act = act
    b.FitWidth(90)
    local c = main and Win.Parts.YES or W().BUTTON.text
    b.text:SetTextColor(c[1], c[2], c[3], 1)
    b.SetOff(off == true)
end

-- Fill the opened group for r and return its height. acts: { whisper, invite, edit,
-- unlist } functions.
local function fillOpened(d, r, width, acts)
    local y, x = 8, 10
    local innerW = width - 2 * x
    if r.note or r.mine then
        local text = r.note or ""
        if r.mine then text = r.text .. (r.note and ("\n" .. r.note) or "") end
        d.note:SetWidth(innerW - 12)
        d.note:SetText(text)
        local h = d.note:GetStringHeight()
        if type(h) ~= "number" or h <= 0 then h = 16 end
        h = math.ceil(h)
        d.noteBg:ClearAllPoints()
        d.noteBg:SetPoint("TOPLEFT", d.inner, "TOPLEFT", x, -y)
        d.noteBg:SetSize(innerW, h + 12)
        d.bar:ClearAllPoints()
        d.bar:SetPoint("TOPLEFT", d.noteBg, "TOPLEFT", 0, 0)
        d.bar:SetPoint("BOTTOMLEFT", d.noteBg, "BOTTOMLEFT", 0, 0)
        Style.PaintAccent(d.bar, 1)
        d.note:ClearAllPoints()
        d.note:SetPoint("TOPLEFT", d.noteBg, "TOPLEFT", 10, -6)
        d.note:Show(); d.noteBg:Show(); d.bar:Show()
        y = y + h + 12 + 10
    else
        d.note:Hide(); d.noteBg:Hide(); d.bar:Hide()
    end
    d.head:ClearAllPoints()
    d.head:SetPoint("TOPLEFT", d.inner, "TOPLEFT", x, -y)
    d.head:SetText(string.upper(r.solo and L["Looking for a group"] or L["In the group"]))
    Style.InkText(d.head, "pop")
    y = y + 18
    local used = 0
    local function line(role, name, what, open)
        used = used + 1
        local m = d.lines[used]
        if not m then return end
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", d.inner, "TOPLEFT", x, -y)
        m:SetWidth(innerW)
        m.badge.Set(role, open)
        m.name:SetText(name)
        Style.InkText(m.name, open and "OFF" or "VALUE")
        m.what:SetText(what or "")
        m:Show()
        y = y + Rows.MEMBER
    end
    local big = r.size > Rows.MEMBERS and not r.solo
    if big then
        local text, of = Rows.Counts(r)
        d.count:ClearAllPoints()
        d.count:SetPoint("TOPLEFT", d.inner, "TOPLEFT", x, -y - 4)
        d.count:SetText(text)
        Style.InkText(d.count, "VALUE")
        d.countOf:ClearAllPoints()
        d.countOf:SetPoint("TOPRIGHT", d.inner, "TOPRIGHT", -x, -y - 4)
        d.countOf:SetText(of)
        d.count:Show(); d.countOf:Show()
        y = y + Rows.MEMBER
    else
        d.count:Hide(); d.countOf:Hide()
        for _, m in ipairs(r.members) do
            local what = (type(m.level) == "number" and (m.level .. " ") or "") .. Rows.ClassWord(m.class)
            if m.zone then what = what .. "  ·  " .. m.zone end
            line(m.role, Rows.Named(m.name, m.class), what)
        end
        if not r.solo then
            local _, open = ns.Data.Places(r)
            for _, role in ipairs(ns.Data.ROLES) do
                for _ = 1, open[role] do line(role, L["Open spot"], "", true) end
            end
        end
    end
    for i = used + 1, #d.lines do d.lines[i]:Hide() end
    y = y + 8
    d.main:ClearAllPoints()
    d.main:SetPoint("TOPLEFT", d.inner, "TOPLEFT", x, -y)
    d.second:ClearAllPoints()
    d.second:SetPoint("LEFT", d.main, "RIGHT", 8, 0)
    if r.mine then
        setButton(d.main, L["Edit listing"], acts.edit, not ns.Data.CanEdit(), true)
        setButton(d.second, L["Unlist"], acts.unlist, not ns.Data.CanEdit())
    else
        local name = r.leader.name
        setButton(d.main, string.format(L["Whisper %s"], name or ""), function() acts.whisper(r) end, type(name) ~= "string", true)
        setButton(d.second, INVITE or L["Invite"], function() acts.invite(r) end, not ns.Data.CanInvite(r))
    end
    y = y + Rows.BUTTON + 12
    d.inner:SetHeight(y)
    return y
end

-- The opened group as a stack piece at full height; Browse glides it open.
function Rows.Opened(stack, r, acts)
    local width = stack:Width()
    local probe = stack.openedFrame
    if not probe then
        probe = makeOpened(stack.child)
        stack.openedFrame = probe
    end
    local h = fillOpened(probe, r, width, acts)
    local d = stack:Piece("opened", function() return probe end, h, 0)
    d.full = h
    return d
end
