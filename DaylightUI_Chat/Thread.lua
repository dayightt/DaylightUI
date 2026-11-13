-- Draws one whisper conversation. The card beside the chat (Convo.lua) and the
-- hub's right side (Hub.lua) each make their own.
-- * Header: class-colored name, a sub line (your note, else level and class),
--   and Pin, Invite, Note and Clear links.
-- * Lines, newest at the bottom. Each run from one person starts with a tan
--   "Name - time" line. Every line has a 2 px rail on its side (their class color
--   on the left, your accent on the right) with a soft wash fading from it.
--   New lines slide up into place.
-- * The input box (Enter sends).

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel
local L = DUI.L

local Thread = {}
ns.Thread = Thread

Thread.PAD = 10
Thread.HEAD = 56 -- header height
Thread.PORTRAIT = 34 -- header portrait size
Thread.NARROW = 240 -- below this width, links and Send go under the box (Thread.Fit)
Thread.RAIL = 2
Thread.WASH = 0.14 -- wash strength next to the rail
Thread.GAP = 4 -- gap between lines
Thread.RUN_GAP = 10 -- gap before a new person's run
Thread.RUN_TIME = 300 -- seconds; a line this much later starts a new run

local function W() return DUI.Widgets end
local function M() return DUI.Motion end

-- Display name for the header and runs; a Battle.net friend's account name.
function Thread.Name(c)
    if c.bn then
        local info = C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(c.bn)
        local n = type(info) == "table" and info.accountName
        if type(n) ~= "nil" then return n end
        return L["Battle.net friend"]
    end
    if type(Ambiguate) == "function" then return Ambiguate(c.name, "short") end
    return c.name
end

-- A whisperer's realm, or nil on yours (the game omits it then).
local function realmOf(c)
    if c.guid and type(GetPlayerInfoByGUID) == "function" then
        local realm = select(7, GetPlayerInfoByGUID(c.guid))
        if type(realm) == "string" and not issecretvalue(realm) and realm ~= "" then return realm end
    end
    return string.match(c.name or "", "%-(.+)$")
end

-- Only offer Invite for someone you could group with (same ruleset).
function Thread.CanInvite(c)
    local Data = DUI.Social.Data
    if c.bn then return Data.CanInviteFriend(Data.Friend(c.bn)) end
    return Data.SameRuleset(realmOf(c))
end

function Thread.Invite(c)
    if not Thread.CanInvite(c) then return end
    if c.bn then DUI.Social.Data.InviteFriend(DUI.Social.Data.Friend(c.bn))
    elseif C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(c.name) end
end

-- Ignore, like the game's player menu. Never for Battle.net friends, since the
-- ignore list holds character names. The conversation closes and gets nothing
-- more from them.
function Thread.CanIgnore(c) return c and not c.bn and type(c.name) == "string" end

function Thread.Ignore(c)
    if not Thread.CanIgnore(c) then return end
    DUI.Social.Data.Ignore(c.name)
    if ns.Convo.Showing(c.key) then ns.Convo.Close() end
    ns.Talk.Close(c)
end

local function theirColor(c)
    if c.class then
        local r, g, b = Style.ClassColor(c.class)
        if r then return r, g, b end
    end
    local info = ChatTypeInfo and ChatTypeInfo[c.bn and "BN_WHISPER" or "WHISPER"]
    if type(info) == "table" and type(info.r) == "number" then return info.r, info.g, info.b end
    return Style.Accent()
end

-- Sub line: your note, else level and class.
local function subLine(c)
    local note = ns.Talk.Note(c)
    if note then return note end
    if c.bn then return L["Battle.net"] end
    local parts = {}
    if c.level then parts[#parts + 1] = string.format(L["Level %s"], c.level) end
    if c.class then
        parts[#parts + 1] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class]) or c.class
    end
    return table.concat(parts, " · ")
end

-- ---------------------------------------------------------------------
-- Lines
-- ---------------------------------------------------------------------

local function rowOf(t, i)
    local r = t.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, t.child)
    r.label = Style.Text(r, Style.SIZE.small, "LEFT")
    r.label:SetWordWrap(false)
    Style.InkText(r.label, "LABEL")
    r.text = Style.Text(r, Style.SIZE.body, "LEFT")
    r.text:SetWordWrap(true)
    Style.InkText(r.text, "TEXT")
    r.rail = r:CreateTexture(nil, "ARTWORK")
    r.rail:SetTexture("Interface\\Buttons\\WHITE8X8")
    r.wash = r:CreateTexture(nil, "BACKGROUND")
    r.wash:SetTexture("Interface\\Buttons\\WHITE8X8")
    t.rows[i] = r
    return r
end

local function paintRow(r, me, cr, cg, cb)
    r.rail:SetVertexColor(cr, cg, cb, 1)
    local a = Thread.WASH
    if me then
        r.wash:SetGradient("HORIZONTAL", CreateColor(cr, cg, cb, 0), CreateColor(cr, cg, cb, a))
    else
        r.wash:SetGradient("HORIZONTAL", CreateColor(cr, cg, cb, a), CreateColor(cr, cg, cb, 0))
    end
end

-- Bottom offset of the box; when narrow, the links and Send sit under it.
function Thread.BoxLift(t)
    if t.narrow then return Thread.PAD + DUI.Widgets.INPUT_H + 6 end
    return Thread.PAD
end

-- Lays out every line top-down and scrolls to the newest.
function Thread.Fill(t, slide)
    local c = t.c and ns.Talk.Get(t.c)
    if not c then
        for _, r in ipairs(t.rows) do r:Hide() end
        t.empty:Show()
        return
    end
    t.empty:SetShown(#c.msgs == 0)
    -- Size from the thread's own area; a freshly placed list can read 0 until the
    -- next layout.
    local areaW, areaH = t.size()
    local width = math.max(60, areaW - 2 * Thread.PAD - 6)
    local tr, tg, tb = theirColor(c)
    local ar, ag, ab = Style.Accent()
    local y, last = 0, nil
    for i, m in ipairs(c.msgs) do
        local r = rowOf(t, i)
        local run = not last or (last.me == true) ~= (m.me == true) or (m.t or 0) - (last.t or 0) > Thread.RUN_TIME
        y = y + (run and i > 1 and Thread.RUN_GAP or (i > 1 and Thread.GAP or 0))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", t.child, "TOPLEFT", Thread.PAD, -y)
        r:SetWidth(width)
        local h = 0
        if run then
            r.label:Show()
            r.label:SetWidth(width)
            r.label:ClearAllPoints()
            r.label:SetPoint("TOP" .. (m.me and "RIGHT" or "LEFT"), r, "TOP" .. (m.me and "RIGHT" or "LEFT"), 0, 0)
            r.label:SetJustifyH(m.me and "RIGHT" or "LEFT")
            local who = m.me and L["You"] or Thread.Name(c)
            r.label:SetText(string.format("%s · %s", who, date("%H:%M", m.t or time())))
            h = Style.SIZE.small + 4
        else
            r.label:Hide()
        end
        r.text:ClearAllPoints()
        r.text:SetWidth(width - 12)
        r.text:SetJustifyH(m.me and "RIGHT" or "LEFT")
        r.text:SetPoint("TOP" .. (m.me and "RIGHT" or "LEFT"), r, "TOP" .. (m.me and "RIGHT" or "LEFT"),
            m.me and -8 or 8, -h - 2)
        r.text:SetText(m.text)
        local th = r.text:GetStringHeight()
        if type(th) ~= "number" or th <= 0 then th = Style.SIZE.body end
        r.rail:ClearAllPoints()
        r.rail:SetPoint("TOP" .. (m.me and "RIGHT" or "LEFT"), r, "TOP" .. (m.me and "RIGHT" or "LEFT"), 0, -h)
        r.rail:SetSize(Pixel.Px(r, Thread.RAIL), th + 4)
        r.wash:ClearAllPoints()
        r.wash:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -h)
        r.wash:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -h)
        r.wash:SetHeight(th + 4)
        if m.me then paintRow(r, true, ar, ag, ab) else paintRow(r, false, tr, tg, tb) end
        h = h + th + 4
        r:SetHeight(h)
        r:Show()
        y = y + h
        last = m
    end
    for i = #c.msgs + 1, #t.rows do t.rows[i]:Hide() end
    t.child:SetSize(width + 2 * Thread.PAD, math.max(y + Thread.PAD, 1))
    local below = Thread.BoxLift(t) + DUI.Widgets.INPUT_H + 6
    local view = math.max(0, areaH - Thread.HEAD - 4 - below)
    local most = math.max(0, y + Thread.PAD - view)
    t.list:SetVerticalScroll(most)
    if t.bar then t.bar.Update() end
    -- New line rises into place.
    local newest = t.rows[#c.msgs]
    if slide and newest and M().On() then M().SlideIn(newest, 0, -8, M().NORMAL) end
end

-- ---------------------------------------------------------------------
-- The head
-- ---------------------------------------------------------------------

-- Class icon from the unit frames' icon set (DUI.ClassIcon, if that module is on),
-- else Daylight UI's own. Battle.net friends and unknown classes get the chat bubble.
function Thread.ClassIcon(token)
    if type(token) == "string" then
        if DUI.ClassIcon then
            local file, l, r, top, b = DUI.ClassIcon(token)
            if file then return file, l, r, top, b end
        end
        return DUI.MEDIA .. "class\\" .. string.lower(token) .. ".tga", 0, 1, 0, 1
    end
end

function Thread.Head(t)
    local c = t.c and ns.Talk.Get(t.c)
    t.name:SetText(c and Thread.Name(c) or "")
    if c then
        t.name:SetTextColor(Style.ClassTextColor(c.class))
        t.sub:SetText(subLine(c))
        if t.links.pin then t.links.pin.SetLabel(c.pinned and L["Unpin"] or L["Pin"]) end
        local file, l, r, top, b = Thread.ClassIcon(c.class)
        if file then
            t.portrait:SetTexture(file)
            t.portrait:SetTexCoord(l, r, top, b)
            t.portrait:SetVertexColor(1, 1, 1, 1)
        else
            t.portrait:SetTexture(DUI.MEDIA .. "ui-chat.png")
            t.portrait:SetTexCoord(0, 1, 0, 1)
            local lab = Style.INK.LABEL
            t.portrait:SetVertexColor(lab[1], lab[2], lab[3], 1)
        end
    else
        t.sub:SetText("")
    end
    t.portrait:SetShown(c ~= nil)
    t.rim:SetShown(c ~= nil)
    t.invite:SetShown(c ~= nil and Thread.CanInvite(c))
    if t.links.clear then t.links.clear:SetShown(c ~= nil) end
    if t.links.note then t.links.note:SetShown(c ~= nil and not c.bn) end
end

-- Forget a conversation. Its card tucks away first; the hub moves on by itself
-- (Hub.Changed).
function Thread.Forget(c)
    if ns.Convo.Showing(c.key) then ns.Convo.Close() end
    ns.Talk.Forget(c)
end

-- Header links a caller can request.
Thread.LINKS = {
    note = { words = function() return L["Note"] end, click = function(t)
        local c = t.c and ns.Talk.Get(t.c)
        if c then W().Prompt(L["A note about this player"], ns.Talk.Note(c) or "", function(text) ns.Talk.SetNote(c, text) end) end
    end },
    pin = { words = function() return L["Pin"] end, click = function(t)
        local c = t.c and ns.Talk.Get(t.c)
        if c then ns.Talk.Pin(c, not c.pinned) end
    end },
    -- Its only choice is the confirm: a card's row has no room for a link that grows
    -- into "Click again".
    clear = { words = function() return L["Clear"] end, click = function(t)
        local c = t.c and ns.Talk.Get(t.c)
        if not c then return end
        W().OpenMenu(t.links.clear, { "forget" }, { forget = L["Forget conversation"] }, nil,
            function() Thread.Forget(c) end, 170)
    end },
    all = { words = function() return L["All"] end, click = function(t)
        local key = t.c
        ns.Convo.Close()
        ns.Hub.Open(key)
    end },
    pop = { words = function() return L["Pop out"] end, click = function(t)
        local key = t.c
        ns.Hub.Close()
        if key then ns.Convo.Open(key) end
    end },
}

-- ---------------------------------------------------------------------
-- Making one
-- ---------------------------------------------------------------------

local function send(t, text)
    local c = t.c and ns.Talk.Get(t.c)
    if c and ns.Talk.Send(c, text) then return true end
    return false
end

-- opts: { onClose = fn (adds an X), links = { ... }, size = fn() -> w, h
-- (the area to fill, default the parent's) }
function Thread.New(parent, opts)
    opts = opts or {}
    local t = { rows = {} }
    t.size = opts.size or function() return parent:GetWidth() or 0, parent:GetHeight() or 0 end
    -- Header from the window kit: round portrait (class icon from the unit frames'
    -- Class icons set), name as title, level and class (or your note) below, links
    -- and X on the right.
    local E = Thread.PAD
    t.portrait = parent:CreateTexture(nil, "ARTWORK")
    t.portrait:SetSize(Thread.PORTRAIT, Thread.PORTRAIT)
    t.portrait:SetPoint("TOPLEFT", parent, "TOPLEFT", E, -E)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(DUI.Win.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(t.portrait)
    t.portrait:AddMaskTexture(mask)
    t.rim = parent:CreateTexture(nil, "OVERLAY")
    t.rim:SetTexture(DUI.MEDIA .. "portrait-rim.png")
    t.rim:SetPoint("TOPLEFT", t.portrait, "TOPLEFT", -3, 3)
    t.rim:SetPoint("BOTTOMRIGHT", t.portrait, "BOTTOMRIGHT", 3, -3)
    Style.Follow(t.rim, Style.BAND)
    t.name = Style.Text(parent, Style.SIZE.head, "LEFT")
    t.name:SetPoint("TOPLEFT", t.portrait, "TOPRIGHT", 10, -2)
    t.name:SetWordWrap(false)
    t.sub = Style.Text(parent, Style.SIZE.small, "LEFT")
    t.sub:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -3)
    t.sub:SetWordWrap(false)
    Style.InkText(t.sub, "LABEL")
    if opts.onClose then
        t.close = W().Close(parent, opts.onClose)
        t.close:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
    end
    t.row = {} -- links, right to left (placed by Thread.Fit)
    local function link(words, fn)
        local l = W().Link(parent, Style.SIZE.small)
        l.SetLabel(words)
        l:SetScript("OnClick", fn)
        t.row[#t.row + 1] = l
        return l
    end
    -- The links the caller asked for, right to left (opts.links: "all", "note", "pin",
    -- "pop"), then Invite.
    t.links = {}
    for i = #(opts.links or {}), 1, -1 do
        local id = opts.links[i]
        local def = Thread.LINKS[id]
        if def then t.links[id] = link(def.words(), function() def.click(t) end) end
    end
    t.invite = link(L["Invite"], function()
        local c = t.c and ns.Talk.Get(t.c)
        if c then Thread.Invite(c) end
    end)
    t.rule = DUI.Win.Parts.Rule(parent)
    t.rule:SetPoint("TOPLEFT", parent, "TOPLEFT", Thread.PAD, -Thread.HEAD)
    t.rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -Thread.PAD, -Thread.HEAD)
    -- Input box at the bottom, with Send, styled like the chat's own footer.
    t.send = W().Button(parent, L["Send"], DUI.Widgets.INPUT_H)
    t.send:SetWidth(64)
    t.send:SetScript("OnClick", function()
        if send(t, t.input:GetText()) then t.input:SetText("") end
    end)
    t.input = W().Input(parent, { hint = L["Reply..."], maxLetters = 255 })
    t.input:SetScript("OnEnterPressed", function(box)
        if send(t, box:GetText()) then box:SetText("") end
    end)
    t.input:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    local bottom = t.input
    -- The lines in between.
    t.list = CreateFrame("ScrollFrame", nil, parent)
    t.list:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -Thread.HEAD - 4)
    t.list:SetPoint("BOTTOM", bottom, "TOP", 0, 6)
    t.list:SetPoint("RIGHT", parent, "RIGHT")
    t.list:SetPoint("LEFT", parent, "LEFT")
    t.child = CreateFrame("Frame", nil, t.list)
    t.child:SetSize(1, 1)
    t.list:SetScrollChild(t.child)
    t.bar = W().Scroll(t.list, { x = -8, step = 40 })
    t.empty = Style.Text(parent, Style.SIZE.body, "CENTER")
    t.empty:SetPoint("CENTER", t.list, "CENTER")
    Style.InkText(t.empty, "LABEL")
    t.empty:SetText(L["No messages yet."])
    t.empty:Hide()
    t.parent = parent
    Thread.Fit(t)
    return t
end

-- Wide: links in the header, Send beside the box. Narrow (the conversation's
-- default): the name keeps the header and the box gets the full width, with the
-- links and Send in a row under it.
function Thread.Fit(t)
    local narrow = (t.size()) < Thread.NARROW
    if narrow == t.narrow then return end
    t.narrow = narrow
    local parent, E = t.parent, Thread.PAD
    local foot = DUI.Widgets.INPUT_H
    for _, f in ipairs({ t.name, t.sub, t.send, t.input }) do f:ClearAllPoints() end
    t.name:SetPoint("TOPLEFT", t.portrait, "TOPRIGHT", 10, -2)
    t.sub:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -3)
    t.send:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -E, E)
    for i, l in ipairs(t.row) do
        l:ClearAllPoints()
        if narrow then
            if i == 1 then l:SetPoint("LEFT", parent, "BOTTOMLEFT", E, E + foot / 2)
            else l:SetPoint("LEFT", t.row[i - 1], "RIGHT", 12, 0) end
        elseif i > 1 then l:SetPoint("RIGHT", t.row[i - 1], "LEFT", -12, 0)
        elseif t.close then l:SetPoint("RIGHT", t.close, "LEFT", -6, 0)
        else l:SetPoint("RIGHT", parent, "TOPRIGHT", -E, -E - 12) end
    end
    if narrow then
        t.input:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", E, Thread.BoxLift(t))
        t.input:SetPoint("RIGHT", parent, "RIGHT", -E, 0)
        local edge = t.close or parent
        t.name:SetPoint("RIGHT", edge, t.close and "LEFT" or "RIGHT", -6, 0)
        t.sub:SetPoint("RIGHT", edge, t.close and "LEFT" or "RIGHT", -6, 0)
    else
        t.input:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", E, Thread.BoxLift(t))
        t.input:SetPoint("RIGHT", t.send, "LEFT", -6, 0)
        t.name:SetPoint("RIGHT", t.invite, "LEFT", -10, 0)
        t.sub:SetPoint("RIGHT", t.invite, "LEFT", -10, 0)
    end
end

function Thread.Set(t, key)
    t.c = key
    Thread.Fit(t)
    Thread.Head(t)
    Thread.Fill(t)
end
