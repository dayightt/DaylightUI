-- Social window, Friends page: a search box, then Battle.net friends under Favorites,
-- Online and Offline (collapsed), and ignored players (collapsed). Each row has a
-- status dot, the friend's name in white and their character in class color, with
-- level and zone, another game, or last-online time underneath. Hover shows a card
-- tooltip, click picks a friend and opens the detail card beside the list (who, where,
-- Invite and Whisper), right-click opens a menu (same as the group finder). A friend
-- coming online gets a shine. A square button beside the search adds a friend.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Friends = {}
ns.Friends = Friends

Friends.EDGE = 16
Friends.CHIPS_Y = 44
Friends.TOP = 76
-- The chips over the list: everyone, friends in this game, everyone online.
Friends.FILTERS = { "all", "game", "online" }
DUI.WithLanguage(function()
    Friends.FILTER_WORD = { all = ALL or L["All"], game = L["Same game"], online = L["Online"] }
end)
Friends.filter = "all"
-- A friend's faction as the game's own banner icon, cropped like our other icons.
Friends.FACTION_ICON = { Alliance = "Interface\\Icons\\INV_BannerPVP_02", Horde = "Interface\\Icons\\INV_BannerPVP_01" }
Friends.FACTION_SIZE = 14
Friends.ROW = 42
Friends.IGNORED = 28
Friends.folds = { offline = true, ignored = true }   -- collapsed sections (this session)

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end
local function Rows() return DUI.Lfg.Rows end
local function Data() return ns.Data end

-- Collapsible section header with its count (same as the profession window: Stack:Section
-- look, click to collapse, "+" while collapsed)

local function makeHead(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")
    b.text = Style.Text(b, Win.Parts.HEAD, "LEFT")
    b.text:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 4)
    b.count = Style.Text(b, Win.Parts.HEAD, "LEFT")
    b.count:SetPoint("LEFT", b.text, "RIGHT", 8, 0)
    Style.InkText(b.count, "LABEL")
    b.state = Style.Text(b, Style.SIZE.body, "RIGHT")
    b.state:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 3)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetTexture(WHITE)
    b.line:SetVertexColor(1, 1, 1, 0.06)
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.isSection = true
    local function lit(on)
        Style.InkText(b.text, "pop", on and 1 or 0.85)
        Style.InkText(b.state, "pop", on and 1 or 0.85)
    end
    b.Lit = lit
    b:SetScript("OnEnter", function() lit(true) end)
    b:SetScript("OnLeave", function() lit(false) end)
    b:SetScript("OnClick", function(self) if self.onFold then self.onFold() end end)
    return b
end

-- folds: table of collapsed keys (nil: header doesn't collapse); render: the page's
-- paint, run after a toggle.
function Friends.Head(stack, key, label, count, folds, render)
    local b = stack:Piece("head", makeHead, 22, 12, "head:" .. tostring(key))
    b.text:SetText(DUI.Style.Upper(label or ""))
    b.count:SetText(count or "")
    local folded = folds and folds[key] == true
    b.state:SetText(folded and "+" or "")
    b.onFold = folds and function()
        folds[key] = not folds[key] or nil
        render(true)
    end or nil
    b:EnableMouse(folds ~= nil)
    b.Lit(b:IsMouseOver() == true)
    return folded
end

-- Card and menu

function Friends.Sub(f)
    if f.status == "off" then
        return f.lastOnline and string.format(L["Last online %s"], Data().Ago(f.lastOnline)) or L["Offline"]
    end
    if f.char then
        local bits = {}
        if f.level then bits[#bits + 1] = string.format(L["Level %s"], f.level) end
        if f.zone then bits[#bits + 1] = f.zone end
        if f.ruleset then bits[#bits + 1] = f.ruleset end
        return table.concat(bits, " · ")
    end
    return f.game and string.format(L["Playing %s"], f.game) or ""
end

-- What the button says: the game asks to be invited into a group a friend is already in
-- ("request"), and invites anyone else.
function Friends.InviteWord(f)
    return Data().InviteKind(f) == "REQUEST_INVITE" and L["Request invite"] or INVITE or L["Invite"]
end

-- "Level 46 Tauren Hunter" for one character.
function Friends.Who(c)
    return ((c.level and string.format(L["Level %s"], c.level) .. " ") or "") .. (c.race and (c.race .. " ") or "") .. Rows().ClassWord(c.class)
end

-- The card's lines for a friend's other game accounts: each character in its class
-- color with what it is, and where, or the other game they're in.
function Friends.Others(f)
    local lines = {}
    for _, o in ipairs(f.others or {}) do
        if o.char then
            lines[#lines + 1] = Rows().Named(o.char, o.class) .. "  " .. Friends.Who(o)
            if o.zone then lines[#lines + 1] = Win.Parts.Hex(Style.INK.LABEL) .. o.zone .. "|r" end
        elseif o.game then
            lines[#lines + 1] = string.format(L["Playing %s"], o.game)
        end
    end
    if #lines == 0 then return nil, 0 end
    return table.concat(lines, "\n"), #lines
end

function Friends.Tip(owner, f)
    if not (GameTooltip and f) then return end
    local T = DUI.Tips
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    T.Clear()
    T.Title(f.account)
    T.Sub(f.status == "off" and Friends.Sub(f) or ns.Window.STATUS_WORD[f.status])
    local function show(c)
        if c.char then
            local r, g, b = Style.ClassTextColor(c.class)
            T.Person(c.char, c.zone, { r, g, b })
            T.Text(Friends.Who(c), Style.INK.LABEL)
        elseif c.game and f.status ~= "off" then
            T.Text(string.format(L["Playing %s"], c.game))
        end
    end
    show(f)
    -- Their other game accounts online, under the one in focus, as the game's card has them.
    for _, o in ipairs(f.others or {}) do
        T.Gap()
        show(o)
    end
    if f.faction and ns.Setting("friendFactions") == true then T.Line(L["Faction"], f.faction == "Horde" and (FACTION_HORDE or L["Horde"]) or (FACTION_ALLIANCE or L["Alliance"])) end
    if f.ruleset then T.Line(L["Server"], f.ruleset) end
    if f.note then T.Line(L["Note"], f.note) end
    if f.broadcast then T.Text("\"" .. f.broadcast .. "\"") end
    T.Gap()
    T.Hint(L["Click: pick to whisper or invite"])
    T.Hint(L["Right-click: more"])
    T.Flush(GameTooltip)
    GameTooltip:Show()
end

function Friends.Menu(owner, f)
    local keys, values = {}, {}
    local function add(k, v) keys[#keys + 1] = k; values[k] = v end
    if f.status ~= "off" then add("whisper", WHISPER or L["Whisper"]) end
    if Data().CanInviteFriend(f) then add("invite", Friends.InviteWord(f)) end
    add("note", L["Set note..."])
    add("favorite", f.favorite and L["Remove from favorites"] or L["Add to favorites"])
    add("remove", L["Remove friend..."])
    W().OpenMenu(owner, keys, values, nil, function(k)
        if k == "whisper" then Data().WhisperFriend(f)
        elseif k == "invite" then Data().InviteFriend(f)
        elseif k == "note" then
            W().Prompt(string.format(L["A note for %s:"], f.account), f.note or "", function(text) Data().SetNote(f, text) end)
        elseif k == "favorite" then Data().SetFavorite(f, not f.favorite)
        elseif k == "remove" and type(BNRemoveFriend) == "function" then
            -- The game's own question and call (CONFIRM_REMOVE_BN_FRIEND).
            local text = BATTLETAG_REMOVE_FRIEND_CONFIRMATION or L["Remove %s from your friends?"]
            W().Ask({ key = "removeFriend", text = string.format(text, f.account), yes = ACCEPT or L["Accept"],
                no = CANCEL or L["Cancel"], onYes = function() BNRemoveFriend(f.id) end })
        end
    end, nil, { atCursor = true })
end

-- The page

local function pick(id)
    Friends.picked = id
    for _, b in ipairs(Friends.rows or {}) do Rows().Pick(b, b.spec.friend.id == id) end
    Friends.PaintDetail()
end

local function picked()
    for _, f in ipairs(Friends.list or {}) do if f.id == Friends.picked then return f end end
end

-- A friend's line: the account, then their character (with the faction's banner when
-- that's on). dim: gone or elsewhere, so the name goes quiet.
function Friends.Title(f)
    local dim = f.status == "off" or (ns.Setting("friendDim") == true and Friends.Away(f))
    local text = f.account
    if f.char then text = text .. "  " .. Friends.FactionIcon(f.faction) .. (dim and f.char or Rows().Named(f.char, f.class)) end
    return text, dim
end

-- What the card beside the list shows for the picked friend: who, what they play and
-- where, what they said, and only the buttons that apply (Invite when the game would let
-- it, Whisper while they're online). A friend is already a friend, so no Add friend here:
-- that one is the button beside the search box.
function Friends.Spec(f)
    local _, dim = Friends.Title(f)
    local ink = Style.INK
    local buttons = {}
    if Data().CanInviteFriend(f) then
        buttons[#buttons + 1] = { text = Friends.InviteWord(f), primary = true, onClick = function() Data().InviteFriend(picked()) end }
    end
    if f.status ~= "off" then
        buttons[#buttons + 1] = { text = WHISPER or L["Whisper"], onClick = function() Data().WhisperFriend(picked()) end }
    end
    local rows = {}
    local function add(label, value, color)
        if value and value ~= "" then rows[#rows + 1] = { label = label, value = value, color = color } end
    end
    add(nil, ns.Window.STATUS_WORD[f.status], ns.Window.StatusColor(f.status))
    if f.status == "off" then add(nil, f.lastOnline and string.format(L["Last online %s"], Data().Ago(f.lastOnline)) or nil, ink.LABEL) end
    -- What the game gives for a friend with no character (Battle.net, another game,
    -- offline): the game they're in, and their BattleTag under the name.
    if not f.char and f.game and f.status ~= "off" then add(nil, string.format(L["Playing %s"], f.game), ink.LABEL) end
    if f.char then
        add(LEVEL or L["Level"], f.level and tostring(f.level))
        add(L["Race"], f.race)
        add(L["Zone"], f.zone)
        local word = f.faction and (f.faction == "Horde" and (FACTION_HORDE or L["Horde"]) or (FACTION_ALLIANCE or L["Alliance"]))
        add(L["Faction"], word)
        add(L["Server"], f.ruleset)
    end
    local others, n = Friends.Others(f)
    if others then rows[#rows + 1] = { label = L["Also playing"], value = others, lines = n } end
    add(L["Note"], f.note)
    if f.broadcast then add(nil, "\"" .. f.broadcast .. "\"", ink.LABEL) end
    local icon
    if f.class and DUI.ClassIcon then icon = { DUI.ClassIcon(f.class) } end
    local r, g, b = 1, 1, 1
    if f.char and not dim and f.class then r, g, b = Style.ClassTextColor(f.class) end
    -- A Battle.net name can be a protected string, so the badge's letter comes from the
    -- BattleTag before the #, which is plain.
    local initial = f.char or (f.tag and f.tag:match("^[^#]+"))
    return { icon = icon, initial = initial, title = f.char or f.account, color = f.char and not dim and { r, g, b } or (dim and ink.OFF or ink.VALUE),
        sub = f.char and f.account or f.tag, rows = rows, buttons = buttons }
end

function Friends.PaintDetail()
    local page = Friends.page
    if not (page and page.detail) then return end
    local f = picked()
    return page.detail:Set(f and Friends.Spec(f) or nil)
end

-- The card open or closed: the search box and its Add friend button keep to the list's
-- side, and the list's right edge moves off the card.
function Friends.Fit(page, p)
    local room = ns.Detail.SPAN * p
    local right = Friends.EDGE + room
    page.add:ClearAllPoints()
    page.add:SetPoint("TOPRIGHT", page, "TOPRIGHT", -right, -10)
    page.stack.scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -page.stack.side - room, ns.Detail.REST)
end

-- Someone you can't play with right now: in another game, or on another ruleset.
function Friends.Away(f)
    return f.status ~= "off" and (not f.inGame or not Data().SameRuleset(f.realm))
end

function Friends.FactionIcon(faction)
    local file = faction and ns.Setting("friendFactions") == true and Friends.FACTION_ICON[faction]
    if not file then return "" end
    local n = Friends.FACTION_SIZE
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", file, n, n)
end

function Friends.Filter(id)
    Friends.filter = id
    for k, b in pairs(Friends.page.chips) do b.SetOn(k == id) end
    Friends.Render(nil, true)
end

local function matches(f, q)
    if Friends.filter == "online" and f.status == "off" then return false end
    if Friends.filter == "game" and not (f.inGame and Data().SameRuleset(f.realm)) then return false end
    if q == "" then return true end
    local hay = string.lower(table.concat({ f.account or "", f.tag or "", f.char or "", f.zone or "", f.ruleset or "", f.note or "" }, " "))
    return hay:find(q, 1, true) ~= nil
end

local function friendRow(s, f)
    local off = f.status == "off"
    local text, dim = Friends.Title(f)
    local b = Rows().Row(s, { kind = "friend", height = Friends.ROW, friend = f, text = text, id = "friend:" .. tostring(f.id),
        color = dim and Style.INK.OFF or Style.INK.VALUE, sub = Friends.Sub(f), subColor = dim and Style.INK.OFF or Style.INK.LABEL,
        dot = ns.Window.StatusColor(f.status), picked = f.id == Friends.picked,
        -- A quick Invite at the row's right end, when that friend can be invited now
        -- (the panel's Invite does the same for the picked row).
        action = Data().CanInviteFriend(f) and { tip = Friends.InviteWord(f), onClick = function() Data().InviteFriend(f) end } or nil,
        onClick = function() pick(Friends.picked ~= f.id and f.id or nil) end,
        onMenu = function(row) Friends.Menu(row, f) end,
        onEnter = function(row) Friends.Tip(row, f) end })
    Friends.rows[#Friends.rows + 1] = b
    -- Came online since the last paint: run a soft light across.
    local was = Friends.seen[f.id]
    if was == "off" and not off then Win.Parts.Shine(b) end
    return b
end

local function ignoredRow(s, name)
    return Rows().Row(s, { kind = "ignored", height = Friends.IGNORED, text = name, color = Style.INK.OFF, id = "ignored:" .. name,
        onMenu = function(row)
            W().OpenMenu(row, { "unignore" }, { unignore = L["Stop ignoring"] }, nil, function() Data().Unignore(name) end, nil, { atCursor = true })
        end,
        onEnter = function(row)
            if not GameTooltip then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            DUI.Tips.Clear()
            DUI.Tips.Title(name)
            DUI.Tips.Sub(L["Ignored"])
            DUI.Tips.Hint(L["Right-click: stop ignoring"])
            DUI.Tips.Flush(GameTooltip)
            GameTooltip:Show()
        end })
end

-- keep: a refill (a toggle, a friend's change) keeps the scroll position.
-- keep: refresh of the open list (events, a toggle); ease: the search changed.
-- Either way friends that stay glide to their new spot (one coming online moves up to
-- Online) and new ones fade in.
-- The chips show only when switched on; the list moves up into their room when not.
local function layChips(page)
    local on = ns.Setting("friendChips") == true
    if not on then Friends.filter = "all" end
    for id, b in pairs(page.chips) do
        b:SetShown(on)
        b.SetOn(Friends.filter == id)
    end
    page.stack.scroll:SetPoint("TOPLEFT", page, "TOPLEFT", page.stack.side, -(on and Friends.TOP or Friends.CHIPS_Y))
end

function Friends.Render(keep, ease)
    local page = Friends.page
    if not (page and page:IsShown()) then return end
    layChips(page)
    local s = page.stack
    local at = keep and s:Scrolled()
    local spots = (keep or ease) and s:Spots() or nil
    local q = string.lower(page.search:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local all = Data().Friends()
    Friends.list = all
    local fav, on, off = {}, {}, {}
    for _, f in ipairs(all) do
        if matches(f, q) then
            if f.favorite then fav[#fav + 1] = f elseif f.status ~= "off" then on[#on + 1] = f else off[#off + 1] = f end
        end
    end
    s:Begin()
    Friends.rows = {}
    local function count(list)
        local n = 0
        for _, f in ipairs(list) do if f.status ~= "off" then n = n + 1 end end
        return n
    end
    local render = Friends.Render
    if #fav > 0 then
        if not Friends.Head(s, "favorites", L["Favorites"], string.format(L["%d / %d"], count(fav), #fav), Friends.folds, render) then
            for _, f in ipairs(fav) do friendRow(s, f) end
        end
    end
    if #on > 0 or q == "" then
        if not Friends.Head(s, "online", L["Online"], tostring(#on), Friends.folds, render) then
            for _, f in ipairs(on) do friendRow(s, f) end
        end
    end
    if #off > 0 then
        if not Friends.Head(s, "offline", L["Offline"], tostring(#off), Friends.folds, render) then
            for _, f in ipairs(off) do friendRow(s, f) end
        end
    end
    local ignored = q == "" and Data().Ignores() or {}
    if #ignored > 0 then
        if not Friends.Head(s, "ignored", L["Ignored"], tostring(#ignored), Friends.folds, render) then
            for _, name in ipairs(ignored) do ignoredRow(s, name) end
        end
    end
    page.pieces = s:End()
    if at then s:ScrollTo(at) end
    s:Ease(spots)
    Friends.seen = {}
    for _, f in ipairs(all) do Friends.seen[f.id or 0] = f.status end
    local still = picked()
    if not still then Friends.picked = nil end
    local none = #fav + #on + #off == 0
    page.note:SetShown(none)
    page.note:SetText(q ~= "" and L["No friends match."] or L["No friends yet."])
    Friends.PaintDetail()
end

function Friends.Build(page)
    Friends.page = page
    Friends.seen = {}
    page.search = W().Input(page, { search = true, hint = L["Search friends..."], maxLetters = 64,
        onChange = function() Friends.Render(nil, true) end })
    -- Add friend: a square button beside the search (it adds someone new, so it isn't
    -- about the picked row).
    page.add = W().IconButton(page, "ui-plus.png", L["Add friend"], function()
        W().Prompt(L["Add a friend: a BattleTag (Name#1234) or a character's name."], "", function(text) Data().AddFriend(text) end, { now = true })
    end, W().INPUT_H)
    page.add:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Friends.EDGE, -10)
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", Friends.EDGE, -10)
    page.search:SetPoint("TOPRIGHT", page.add, "TOPLEFT", -6, 0)
    page.chips = {}
    local x = Friends.EDGE
    for _, id in ipairs(Friends.FILTERS) do
        local b = W().Chip(page, Friends.FILTER_WORD[id])
        b.FitWidth()
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -Friends.CHIPS_Y)
        b:SetScript("OnClick", function() Friends.Filter(id) end)
        b.SetOn(Friends.filter == id)
        page.chips[id] = b
        x = x + b:GetWidth() + W().CHIP_GAP
    end
    page.stack = Win.Parts.Stack(page, { top = Friends.TOP, bottom = ns.Detail.REST })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page.detail = ns.Detail.New(page, { refill = function() Friends.Render(true) end,
        side = function(open) ns.Window.SetSide("friends", open) end, fit = function(p) Friends.Fit(page, p) end })
    -- GROUP_ROSTER_UPDATE: a friend who joins the group has no Invite any more.
    for _, e in ipairs({ "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED",
        "IGNORELIST_UPDATE", "BN_CUSTOM_MESSAGE_CHANGED", "FRIENDLIST_UPDATE", "GROUP_ROSTER_UPDATE" }) do
        DUI.RegisterEvent(e, function() ns.Window.Refresh("friends") end)
    end
end

function Friends.Fill(page)
    Friends.Render()
end

function Friends.Pieces(page)
    local out = { page.search, page.add }
    if ns.Setting("friendChips") == true then
        for _, id in ipairs(Friends.FILTERS) do out[#out + 1] = page.chips[id] end
    end
    for i, p in ipairs(page.pieces or {}) do
        if i > 12 then break end
        out[#out + 1] = p
    end
    return out
end
