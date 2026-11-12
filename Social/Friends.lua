-- Social window, Friends page: a search box, then Battle.net friends under Favorites,
-- Online and Offline (collapsed), and ignored players (collapsed). Each row has a
-- status dot, the friend's name in white and their character in class color, with
-- level and zone, another game, or last-online time underneath. Hover shows a card
-- tooltip, click selects for the footer's Invite and Whisper, right-click opens a menu
-- (same as the group finder). A friend coming online gets a shine.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Friends = {}
ns.Friends = Friends

Friends.EDGE = 16
Friends.TOP = 44
Friends.ROW = 38
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
    b.text:SetText(string.upper(label or ""))
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

function Friends.Tip(owner, f)
    if not (GameTooltip and f) then return end
    local T = DUI.Tips
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    T.Clear()
    T.Title(f.account)
    T.Sub(f.status == "off" and Friends.Sub(f) or ns.Window.STATUS_WORD[f.status])
    if f.char then
        local r, g, b = Style.ClassTextColor(f.class)
        T.Person(f.char, f.zone, { r, g, b })
        T.Text(((f.level and string.format(L["Level %s"], f.level) .. " ") or "") .. (f.race and (f.race .. " ") or "") .. Rows().ClassWord(f.class), Style.INK.LABEL)
    elseif f.game and f.status ~= "off" then
        T.Text(string.format(L["Playing %s"], f.game))
    end
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
    if Data().CanInviteFriend(f) then add("invite", INVITE or L["Invite"]) end
    add("note", L["Set note..."])
    add("favorite", f.favorite and L["Remove from favorites"] or L["Add to favorites"])
    add("remove", L["Remove friend..."])
    W().OpenMenu(owner, keys, values, nil, function(k)
        if k == "whisper" then Data().WhisperFriend(f)
        elseif k == "invite" then Data().InviteFriend(f)
        elseif k == "note" then
            W().Prompt(string.format(L["A note for %s:"], f.account), f.note or "", function(text) Data().SetNote(f, text) end)
        elseif k == "favorite" then Data().SetFavorite(f, not f.favorite)
        elseif k == "remove" and type(StaticPopup_Show) == "function" then
            -- The game's own confirmation; yes removes the friend (UnitPopupRemoveBnetFriendButtonMixin).
            local text = BATTLETAG_REMOVE_FRIEND_CONFIRMATION or L["Remove %s from your friends?"]
            StaticPopup_Show("CONFIRM_REMOVE_BN_FRIEND", string.format(text, f.account), nil, f.id)
        end
    end, nil, { atCursor = true })
end

-- The page

local function pick(id)
    Friends.picked = id
    for _, b in ipairs(Friends.rows or {}) do Rows().Pick(b, b.spec.friend.id == id) end
    Friends.PaintFooter()
end

local function picked()
    for _, f in ipairs(Friends.list or {}) do if f.id == Friends.picked then return f end end
end

function Friends.PaintFooter()
    local page = Friends.page
    if not page then return end
    local f = picked()
    page.foot:Set({
        { text = INVITE or L["Invite"], primary = true, off = not Data().CanInviteFriend(f), onClick = function() Data().InviteFriend(picked()) end },
        { text = WHISPER or L["Whisper"], off = not (f and f.status ~= "off"), onClick = function() Data().WhisperFriend(picked()) end },
        { text = L["Add friend"], onClick = function()
            W().Prompt(L["Add a friend: a BattleTag (Name#1234) or a character's name."], "", function(text) Data().AddFriend(text) end, { now = true })
        end },
    })
end

local function matches(f, q)
    if q == "" then return true end
    local hay = string.lower(table.concat({ f.account or "", f.tag or "", f.char or "", f.zone or "", f.ruleset or "", f.note or "" }, " "))
    return hay:find(q, 1, true) ~= nil
end

local function friendRow(s, f)
    local off = f.status == "off"
    local text = f.account
    if f.char then text = text .. "  " .. Rows().Named(f.char, f.class) end
    local b = Rows().Row(s, { kind = "friend", height = Friends.ROW, friend = f, text = text, id = "friend:" .. tostring(f.id),
        color = off and Style.INK.OFF or Style.INK.VALUE, sub = Friends.Sub(f), subColor = off and Style.INK.OFF or Style.INK.LABEL,
        dot = ns.Window.StatusColor(f.status), picked = f.id == Friends.picked,
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
function Friends.Render(keep, ease)
    local page = Friends.page
    if not (page and page:IsShown()) then return end
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
    Friends.PaintFooter()
end

function Friends.Build(page)
    Friends.page = page
    Friends.seen = {}
    page.search = W().Input(page, { search = true, hint = L["Search friends..."], maxLetters = 64,
        onChange = function() Friends.Render(nil, true) end })
    page.search:SetPoint("TOPLEFT", page, "TOPLEFT", Friends.EDGE, -10)
    page.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Friends.EDGE, -10)
    page.stack = Win.Parts.Stack(page, { top = Friends.TOP, bottom = 52 })
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page.foot = Win.Parts.Footer(page)
    for _, e in ipairs({ "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED",
        "IGNORELIST_UPDATE", "BN_CUSTOM_MESSAGE_CHANGED", "FRIENDLIST_UPDATE" }) do
        DUI.RegisterEvent(e, function() ns.Window.Refresh("friends") end)
    end
end

function Friends.Fill(page)
    Friends.Render()
end

function Friends.Pieces(page)
    local out = { page.search }
    for i, p in ipairs(page.pieces or {}) do
        if i > 12 then break end
        out[#out + 1] = p
    end
    return out
end
