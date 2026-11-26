-- List pieces shared by the group finder's three pages: a row (group, person or
-- activity, with text and a sub line on the left and role badges or a value on the
-- right; hover lights it, selection gets an accent wash like Parts.PickLine), the party
-- tooltip (DUI.Tips) and the right-click menu (W.OpenMenu at the cursor).

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Rows = {}
ns.Rows = Rows

Rows.GROUP = 46       -- group row
Rows.GROUP_NOTE = 62  -- group row with a note under the sub line
Rows.PERSON = 44      -- who list row
Rows.ACTIVITY = 34    -- activity row
Rows.SEP = { 1, 1, 1, 0.07 }   -- the thin line under a row that asks for one (spec.sep)
Rows.SEP_INSET = 8
Rows.BADGES = 5       -- max role badges per row (a dungeon's five)
Rows.MEMBERS = 10     -- members listed by name, as the game's own tooltip; bigger groups get counts
Rows.ACTION_W = 24                          -- a row's quick-action button (Invite on a friend), at its right end
Rows.ACTION_INSET = 8                   -- from the row's right edge
Rows.ACTION_ICON = "ui-data-social.png"
Rows.LINE_GAP = 3     -- space between a row's lines
Rows.DOT = 7          -- status dot

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end
local function sound(name) if DUI.Sound then DUI.Sound.Play(name) end end

local function tex(parent, layer, c, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
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

-- A group too big to name everyone: listed by name while it has at most Rows.MEMBERS,
-- with its open spots only when the whole group fits that list.
function Rows.ByName(r) return #r.members <= Rows.MEMBERS end
function Rows.Spots(r) return r.size <= Rows.MEMBERS end

-- How many of each class are in, in the game's class order: "3 Warrior  2 Mage", each
-- word in its class color, the number in the accent. "" when no class is known.
function Rows.Classes(r)
    local n, order = {}, {}
    for _, m in ipairs(r.members) do
        if type(m.class) == "string" then
            if not n[m.class] then order[#order + 1] = m.class end
            n[m.class] = (n[m.class] or 0) + 1
        end
    end
    local rank = {}
    if type(CLASS_SORT_ORDER) == "table" then for i, c in ipairs(CLASS_SORT_ORDER) do rank[c] = i end end
    table.sort(order, function(a, b)
        local ra, rb = rank[a] or 99, rank[b] or 99
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local pop, bits = Win.Parts.Hex({ Style.Pop() }), {}
    for _, c in ipairs(order) do bits[#bits + 1] = pop .. n[c] .. "|r " .. Rows.Named(Rows.ClassWord(c), c) end
    return table.concat(bits, "   ")
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
    b.sep = tex(b, "BORDER", Rows.SEP)
    b.sep:SetHeight(1)
    b.sep:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", Rows.SEP_INSET, 0)
    b.sep:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -Rows.SEP_INSET, 0)
    b.sep:Hide()
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
    -- A quick action at the row's right end (Invite on a friend), shown only when the
    -- row's spec has one: W.IconButton (tan, accent on hover, its name after a short
    -- rest). The row's own light follows the mouse onto it, so the row doesn't go dark
    -- under its own button.
    local act = W().IconButton(b, Rows.ACTION_ICON,
        function() return b.spec and b.spec.action and b.spec.action.tip end,
        function()
            local a = b.spec and b.spec.action
            if a and a.onClick then a.onClick(b) end
        end, Rows.ACTION_W)
    act:SetPoint("RIGHT", b, "RIGHT", -Rows.ACTION_INSET, 0)
    act:HookScript("OnEnter", function() Win.Parts.Light(b.hi, true) end)
    act:HookScript("OnLeave", function() Win.Parts.Light(b.hi, b:IsMouseOver() == true) end)
    act:Hide()
    b.action = act
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
-- valueColor, age, roles = { { role, open } }, dot (status dot color), picked, dim, sep (a line
-- under the row),
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
    local action = spec.action ~= nil
    b.action:SetShown(action)
    if action then room = room + Rows.ACTION_W + Rows.ACTION_INSET - 4 end
    local vw = b.value:GetStringWidth()
    if (spec.value or "") ~= "" and type(vw) == "number" then room = math.max(room, vw + 18) end
    local left = 8
    b.sep:SetShown(spec.sep == true)
    if spec.dot then
        b.dot:SetVertexColor(spec.dot[1], spec.dot[2], spec.dot[3], 1)
        left = 10 + Rows.DOT + 7
    end
    b.dot:SetShown(spec.dot ~= nil)
    b.name:ClearAllPoints()
    if b.sub:IsShown() then
        -- The lines as one block, centered on the row, so the wash has the same room
        -- above and below (the name was pinned for a block of fixed height, and a
        -- sub sat on the bottom edge).
        local function line(fs, size)
            local v = fs:GetStringHeight()
            return (type(v) == "number" and v > 0) and v or size + 2
        end
        local block = line(b.name, Style.SIZE.body) + Rows.LINE_GAP + line(b.sub, Style.SIZE.small)
        if spec.note then block = block + Rows.LINE_GAP + line(b.note, Style.SIZE.small) end
        b.name:SetPoint("TOPLEFT", b, "TOPLEFT", left, -math.floor((h - block) / 2 + 0.5))
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
-- A row spans the whole window, so its tooltip opens on whichever side of the window
-- has more room: on the right half of the screen, right of the row would run off it.
function Rows.TipSide(owner)
    local l, r = owner:GetLeft(), owner:GetRight()
    local edge = UIParent and UIParent:GetRight()
    if type(l) ~= "number" or type(r) ~= "number" or type(edge) ~= "number" then return "ANCHOR_RIGHT" end
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (edge - r * scale) < l * scale and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

function Rows.Tip(owner, r)
    if not (GameTooltip and r) then return end
    local T = DUI.Tips
    GameTooltip:SetOwner(owner, Rows.TipSide(owner))
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
    if not r.solo and not Rows.ByName(r) then
        local line, of = Rows.Counts(r)
        T.Line(line, of)
        local classes = Rows.Classes(r)
        if classes ~= "" then T.Text(classes) end
    else
        for _, m in ipairs(r.members) do
            T.Line(W().RoleText(m.role) .. " " .. Rows.Named(m.name, m.class),
                (type(m.level) == "number" and (m.level .. " ") or "") .. Rows.ClassWord(m.class))
        end
        if r.solo then
            local can = {}
            for _, item in ipairs(Rows.Badges(r)) do can[#can + 1] = W().RoleText(item.role) end
            if #can > 0 then T.Line(L["Can be"], table.concat(can, " ")) end
        elseif not Rows.Spots(r) then
            local line, of = Rows.Counts(r)
            T.Line(line, of)
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
