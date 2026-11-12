-- Send page: To (first AND last name, the client refuses a single word), with recent
-- names, the player's own characters and the client's suggestions as chips that filter
-- while typing (Tab takes the first). Then subject, a multi-line letter, item tiles (up
-- to the game's 12; the empty one after them takes the next item dropped or clicked
-- with one on the cursor, and clicking an item removes it), gold, cash on delivery,
-- postage, and Send / Clear.
--
-- Everything goes through the game's send functions (ClickSendMailItemButton,
-- SetSendMailMoney / SetSendMailCOD, SendMail), and the client holds the items and
-- price. The game's Send tab calls SetSendMailShowing(true) while shown so right-clicking
-- a bag item attaches it; this page does the same.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Send = {}
ns.Send = Send

Send.EDGE = 16
Send.LABEL_W = 64
Send.ROW = 34             -- form row height
Send.LETTER_H = 76        -- letter box: four lines of text
Send.SLOTS = 12           -- the game's ATTACHMENTS_MAX_SEND
Send.RECENT = 8           -- recent names kept per character
Send.FOOT = 52
Send.EMPTY = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"   -- the game's empty bag slot

local S = { cod = false, said = nil }
Send.state = S

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end
local function W() return DUI.Widgets end
local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Names: recent ones and the player's own characters

-- This character's name as mail needs it (first and last), saved so alts can send to it.
function Send.SaveOwnName()
    if type(UnitFullName) ~= "function" then return end
    local first, last = UnitFullName("player")
    if type(first) ~= "string" or (issecretvalue and issecretvalue(first)) then return end
    local full = (type(last) == "string" and last ~= "") and (first .. " " .. last) or first
    DUI.DB.Character().mailName = full
end

function Send.Recent()
    local c = DUI.DB.Character()
    c.mailRecent = type(c.mailRecent) == "table" and c.mailRecent or {}
    return c.mailRecent
end

function Send.Remember(name)
    name = trim(name)
    if name == "" then return end
    local list = Send.Recent()
    for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
    table.insert(list, 1, name)
    while #list > Send.RECENT do table.remove(list) end
end

-- The player's other characters on this realm with a saved mail name.
function Send.Alts()
    local own = DUI.DB.CharKey()
    local realm = own and own:match("%-(.*)$")
    local out = {}
    local chars = DUI.DB.Root().characters
    for key, c in pairs(type(chars) == "table" and chars or {}) do
        if key ~= own and type(c) == "table" and type(c.mailName) == "string" and (realm == nil or key:match("%-(.*)$") == realm) then
            out[#out + 1] = c.mailName
        end
    end
    table.sort(out)
    return out
end

-- The form

local function copper(page)
    local function n(box) return tonumber(box:GetText()) or 0 end
    return n(page.gold) * 10000 + n(page.silver) * 100 + n(page.copper)
end

function Send.Items()
    local out = {}
    for slot = 1, Send.SLOTS do
        local name, itemID, tex, count, quality = call(GetSendMailItem, slot)
        if name then out[#out + 1] = { slot = slot, name = name, itemID = itemID, texture = tex, count = count, quality = quality } end
    end
    return out
end

-- Put the cursor's item into the first free slot (the drop button).
function Send.Attach()
    local kind = call(GetCursorInfo)
    if kind ~= "item" then return end
    local used = {}
    for _, it in ipairs(Send.Items()) do used[it.slot] = true end
    for slot = 1, Send.SLOTS do
        if not used[slot] then ClickSendMailItemButton(slot); return end
    end
end

function Send.Say(text, role)
    local page = Send.page
    if not page then return end
    page.said:SetText(text or "")
    Style.InkText(page.said, role or "LABEL")
    page.said:SetShown(text ~= nil)
end

-- Items, postage and footer, as the client holds them.
function Send.Render(page)
    page = page or Send.page
    if not page then return end
    local items = Send.Items()
    local s = page.stack
    s:Begin()
    local tiles = {}
    for _, it in ipairs(items) do
        local slot = it.slot
        tiles[#tiles + 1] = { name = it.name, texture = it.texture, count = it.count, quality = it.quality,
            sub = L["Click to take back"],
            tooltip = function(b)
                if not (GameTooltip and GameTooltip.SetSendMailItem) then return end
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                GameTooltip:SetSendMailItem(slot)
                GameTooltip:Show()
            end,
            onClick = function() ClickSendMailItemButton(slot, true) end }
    end
    -- After the items, an empty slot to drop the next one on (new each time, until all 12
    -- are used).
    local left = Send.SLOTS - #items
    if left > 0 then
        tiles[#tiles + 1] = { name = L["Drop an item here"], nameColor = Style.INK.LABEL, texture = Send.EMPTY,
            sub = left == 1 and L["1 slot left"] or string.format(L["%d slots left"], left), empty = true,
            onClick = Send.Attach, onReceive = Send.Attach }
    end
    s:Items(tiles)
    page.pieces = s:End()
    local price = tonumber(call(GetSendMailPrice)) or 0
    page.postage:SetText(string.format(L["Postage %s"], Win.Parts.Hex(Style.INK.MONEY) .. DUI.MoneyString(price) .. "|r"))
    Send.PaintFooter(page)
end

function Send.PaintFooter(page)
    page = page or Send.page
    if not (page and page.foot) then return end
    page.foot:Set({
        { text = SEND_LABEL or L["Send"], primary = true, off = S.sending == true, onClick = Send.Send },
        { text = L["Clear"], onClick = Send.Clear },
    })
end

function Send.PaintCod(page)
    page = page or Send.page
    if not page then return end
    page.cod.SetOn(S.cod)
    page.goldLabel:SetText(S.cod and L["COD"] or L["Gold"])
end

function Send.Clear()
    local page = Send.page
    if not page then return end
    for _, box in ipairs({ page.to, page.subject, page.body, page.gold, page.silver, page.copper }) do box:SetText("") end
    S.cod = false
    S.reply = nil
    for _, it in ipairs(Send.Items()) do ClickSendMailItemButton(it.slot, true) end
    call(SetSendMailMoney, 0)
    call(SetSendMailCOD, 0)
    Send.Say(nil)
    Send.PaintCod(page)
    Send.Chips(page)
    Send.Render(page)
end

-- Subject for a gold-only letter: the client refuses a letter without one, and there's
-- no item name to use.
function Send.GoldSubject(amount)
    if amount <= 0 then return "" end
    local get = C_CurrencyInfo and C_CurrencyInfo.GetCoinText
    return call(get, amount, ", ") or L["Gold"]
end

-- Send: needs a full name and the gold or COD set. An empty subject becomes the first
-- item's name (the game's own rule) or else the gold amount, then the client's SendMail.
function Send.Send()
    local page = Send.page
    if not page or S.sending then return end
    local to = trim(page.to:GetText())
    if not to:find("%S+%s+%S+") then
        return Send.Say(L["Write the full name: first and last."], "WARN")
    end
    local amount = copper(page)
    local items = Send.Items()
    if S.cod and (amount == 0 or #items == 0) then
        return Send.Say(L["Cash on delivery needs an item and a price."], "WARN")
    end
    if S.cod then
        call(SetSendMailMoney, 0)
        SetSendMailCOD(amount)
    else
        call(SetSendMailCOD, 0)
        if SetSendMailMoney(amount) == false then return Send.Say(L["You don't have that much gold."], "WARN") end
    end
    local subject = trim(page.subject:GetText())
    if subject == "" then subject = items[1] and items[1].name or Send.GoldSubject(amount) end
    if subject == "" then return Send.Say(L["Write a subject."], "WARN") end
    S.sending, S.to = true, to
    Send.PaintFooter(page)
    -- The letter being answered, at its current position (the inbox may have changed since).
    local reply = S.reply and ns.Inbox and ns.Inbox.Find(S.reply)
    SendMail(to, subject, page.body:GetText() or "", reply and reply.index or nil)
end

local function sent()
    if not S.sending then return end
    S.sending = false
    if DUI.Sound then DUI.Sound.Play("done") end
    Send.Remember(S.to)
    local page = Send.page
    if page then
        for _, box in ipairs({ page.subject, page.body, page.gold, page.silver, page.copper }) do box:SetText("") end
        S.cod, S.reply = false, nil
        Send.PaintCod(page)
        Send.Chips(page)
        Send.Render(page)
        Send.Say(string.format(L["Sent to %s."], S.to), "GOOD")
    end
end

-- A red error only fails the letter if it's a mail error (GetGameMessageInfo's name
-- starts with ERR_MAIL). Any other one meanwhile (out of range, not enough rage) leaves
-- the send waiting for MAIL_SEND_SUCCESS. The game's own Send button only re-enables
-- on MAIL_FAILED or MAIL_SUCCESS (Blizzard_MailFrame).
function Send.MailError(kind)
    if type(kind) ~= "number" or type(GetGameMessageInfo) ~= "function" then return false end
    local name = call(GetGameMessageInfo, kind)
    return type(name) == "string" and name:find("^ERR_MAIL") ~= nil
end

local function refused()
    if not S.sending then return end
    S.sending = false
    Send.PaintFooter()
end

-- Building the page

local function label(page, text, y)
    local fs = Style.Text(page, Style.SIZE.small, "LEFT")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", Send.EDGE, -y - 7)
    Style.InkText(fs, "LABEL")
    fs:SetText(text)
    return fs
end

local function box(page, y, opts)
    local e = W().Input(page, opts or {})
    e:SetPoint("TOPLEFT", page, "TOPLEFT", Send.EDGE + Send.LABEL_W, -y)
    e:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Send.EDGE, -y)
    return e
end

-- The client's suggestions for the typed text, requested the same way as the game's To
-- box (Blizzard_AutoComplete, AUTOCOMPLETE_LIST.MAIL): every character except
-- Battle.net friends, so own characters, friends, guild, group and people met.
Send.SUGGEST = 8
Send.BNET = 8             -- Enum.AutoCompleteEntryFlag.Bnet
function Send.Suggested(text)
    local out = {}
    local get = C_AutoComplete and C_AutoComplete.GetAutoCompleteResults
    if text == "" or type(get) ~= "function" then return out end
    local results = call(get, text, Send.SUGGEST, #text, true, 0xffffffff, Send.BNET)
    for _, r in ipairs(type(results) == "table" and results or {}) do
        local n = type(r) == "table" and r.name
        if type(n) == "string" and not (issecretvalue and issecretvalue(n)) then
            if type(Ambiguate) == "function" then n = call(Ambiguate, n, "mail") or n end
            out[#out + 1] = n
        end
    end
    return out
end

-- Does a name start with the typed text (first or last name)?
local function matches(name, typed)
    if typed == "" then return true end
    name = name:lower()
    if name:sub(1, #typed) == typed then return true end
    for word in name:gmatch("%s(%S+)") do
        if word:sub(1, #typed) == typed then return true end
    end
    return false
end

-- Names for the chips: recent first, then own characters, then the client's
-- suggestions. With text typed, only matches.
function Send.Names(text)
    text = trim(text)
    local typed = text:lower()
    local names, seen = {}, {}
    local function add(n)
        if not seen[n] and matches(n, typed) then names[#names + 1], seen[n] = n, true end
    end
    for _, n in ipairs(Send.Recent()) do add(n) end
    for _, n in ipairs(Send.Alts()) do add(n) end
    for _, n in ipairs(Send.Suggested(text)) do add(n) end
    return names
end

-- Name chips under To, filtered by the typed text: new ones fade in, ones that stay
-- glide to their new spot. Measured at the window's target width (Send is narrower
-- than the inbox it often opens from).
function Send.Chips(page)
    page = page or Send.page
    if not page then return end
    local Motion = DUI.Motion
    local was = {}
    for _, b in ipairs(page.chips) do
        if b:IsShown() then was[b.name] = b.x end
        b:Hide()
    end
    local x = Send.EDGE + Send.LABEL_W
    local room = (page.win and page.win:GetWidth() or 0) + Win.GoalGrowth(page) - Send.EDGE   -- the page spans the window
    if room <= x then room = ns.Window.SEND_W - Send.EDGE end
    page.first = nil
    for i, n in ipairs(Send.Names(page.to:GetText())) do
        local b = page.chips[i]
        if not b then
            b = W().Chip(page, n)
            b:SetScript("OnClick", function(self) Send.Pick(self.name) end)
            page.chips[i] = b
        end
        b.name = n
        b.text:SetText(n)
        b.FitWidth()
        if x + b:GetWidth() > room then b:Hide(); break end   -- a new chip starts shown
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -page.chipsY)
        b.x = x
        b:Show()
        if was[n] == nil then Motion.Fade(b, 0, 1, Motion.FAST)
        elseif was[n] ~= x then Motion.Glide(b, was[n] - x, 0, Motion.FAST) end
        page.first = page.first or n
        x = x + b:GetWidth() + W().CHIP_GAP
    end
end

-- A name chip (or Tab on the first) fills To.
function Send.Pick(name)
    local page = Send.page
    if not (page and name) then return end
    page.to:SetText(name)
    page.to:SetCursorPosition(#name)
    Send.Chips(page)
end

function Send.Build(page)
    Send.page = page
    local y = 14
    label(page, L["To"], y)
    page.chips = {}
    page.to = box(page, y, { hint = L["First and last name"],
        onChange = function(_, user) if user then Send.Chips(page) end end })
    -- Tab takes the first matching name, then moves on to the subject.
    page.to:SetScript("OnTabPressed", function(self)
        if page.first and trim(self:GetText()) ~= "" and page.first ~= trim(self:GetText()) then Send.Pick(page.first) end
        page.subject:SetFocus()
    end)
    y = y + Send.ROW
    page.chipsY = y
    y = y + W().CHIP_HEIGHT + 10
    label(page, L["Subject"], y)
    page.subject = box(page, y, { hint = L["Subject"], maxLetters = 64 })
    y = y + Send.ROW
    -- The letter: multi-line (Enter adds a line), in the shared text area. Its background
    -- extends 6 px past the area, so the area is inset 6 px to line up with the boxes
    -- above.
    label(page, L["Letter"], y)
    local letter = W().TextArea(page, { hint = L["Write a letter..."], maxLetters = 500, step = 32 })
    letter:SetPoint("TOPLEFT", page, "TOPLEFT", Send.EDGE + Send.LABEL_W + 6, -y - 6)
    letter:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Send.EDGE - 6, -y - 6)
    letter:SetHeight(Send.LETTER_H - 12)
    letter:SetScript("OnSizeChanged", function(_, w) if type(w) == "number" and w > 0 then letter.edit:SetWidth(w) end end)
    page.letter, page.body = letter, letter.edit
    page.subject:SetScript("OnTabPressed", function() page.body:SetFocus() end)
    y = y + Send.LETTER_H + (Send.ROW - W().INPUT_H) + 4
    page.goldLabel = label(page, L["Gold"], y)
    local x = Send.EDGE + Send.LABEL_W
    local function coin(key, w, glyph)
        local e = W().Input(page, { numeric = true, maxLetters = key == "gold" and 6 or 2, justify = "RIGHT" })
        e:SetSize(w, W().INPUT_H)
        e:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
        local g = Style.Text(page, Style.SIZE.small, "LEFT")
        g:SetPoint("LEFT", e, "RIGHT", 4, 0)
        g:SetText(glyph)
        x = x + w + 26
        page[key] = e
    end
    coin("gold", 64, DUI.MoneyString(10000):gsub("^1", ""))
    coin("silver", 40, DUI.MoneyString(100):gsub("^1", ""))
    coin("copper", 40, DUI.MoneyString(1):gsub("^1", ""))
    page.cod = W().Switch(page)
    page.cod:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Send.EDGE, -y - 5)
    page.cod:SetScript("OnClick", function() S.cod = not S.cod; Send.PaintCod(page) end)
    local codLabel = Style.Text(page, Style.SIZE.small, "RIGHT")
    codLabel:SetPoint("RIGHT", page.cod, "LEFT", -8, 0)
    Style.InkText(codLabel, "LABEL")
    codLabel:SetText(L["Cash on delivery"])
    y = y + Send.ROW + 6
    page.itemsLabel = label(page, L["Items"], y - 7)
    page.postage = Style.Text(page, Style.SIZE.small, "RIGHT")
    page.postage:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Send.EDGE, -y)
    Style.InkText(page.postage, "LABEL")
    y = y + 20
    page.stack = Win.Parts.Stack(page, { top = y, bottom = Send.FOOT + 18 })
    page.said = Style.Text(page, Style.SIZE.small, "LEFT")
    page.said:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", Send.EDGE, Send.FOOT)
    page.said:Hide()
    page.foot = Win.Parts.Footer(page)
    -- Tell the game the Send tab is showing (right-clicking bag items then attaches them).
    page:SetScript("OnShow", function() call(SetSendMailShowing, true) end)
    page:SetScript("OnHide", function() call(SetSendMailShowing, false) end)
    DUI.RegisterEvent("MAIL_SEND_INFO_UPDATE", function() if page:IsVisible() then Send.Render(page) end end)
    DUI.RegisterEvent("MAIL_SEND_SUCCESS", sent)
    DUI.RegisterEvent("MAIL_FAILED", refused)
    -- A send the client never answered ends with the mailbox, or Send would stay off until /reload.
    DUI.RegisterEvent("MAIL_CLOSED", refused)
    DUI.RegisterEvent("UI_ERROR_MESSAGE", function(_, kind, msg)
        if S.sending and Send.MailError(kind) then refused(); if type(msg) == "string" then Send.Say(msg, "WARN") end end
    end)
end

-- On show: a reply from the inbox fills To and the subject.
function Send.Fill(page)
    local r = ns.Window.replyTo
    if r then
        ns.Window.replyTo = nil
        page.to:SetText(r.name or "")
        local subj = r.subject or ""
        page.subject:SetText(subj ~= "" and string.format(L["Re: %s"], subj) or "")
        S.reply = r.id
    end
    Send.Say(nil)
    Send.Chips(page)
    Send.PaintCod(page)
    Send.Render(page)
end

function Send.Pieces()
    local page = Send.page
    return page and page.pieces or {}
end
