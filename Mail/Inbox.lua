-- Mailbox Inbox page: search and filter chips over the letter list (sender, subject,
-- gold or items, days left), the selected letter on the right (its text, auction mail
-- shown as a receipt, items to take one by one), Collect all under the list, and the
-- letter's Take, Reply, Return and Delete under it. Shift-click on a letter takes all
-- of it, as in the game's inbox.
--
-- Everything goes through the game's mail functions, one command at a time, since the
-- client refuses a second while one is pending (C_Mail.IsCommandPending). Collect all
-- takes every letter's gold and items, skips cash on delivery (only paid on a second
-- click of Take), and stops with a message when the bags are full.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Inbox = {}
ns.Inbox = Inbox

Inbox.LIST_W = 300
Inbox.EDGE = 12
Inbox.TOP = 76           -- height of search and chips over the list
Inbox.CHIPS_Y = 46
Inbox.FOOT = 52          -- footer height on the letter side
Inbox.STEP = 0.15        -- s between Collect all steps (the game's OPEN_ALL_MAIL_MIN_DELAY)
Inbox.SLOTS = 16         -- attachment slots per letter (the game's ATTACHMENTS_MAX)
Inbox.LOW_DAYS = 3       -- days left at or below this show in the warn color
Inbox.CONFIRM = DUI.Widgets.CONFIRM
Inbox.FILTERS = { "all", "ah", "players", "gold" }

Inbox.TIE = 2            -- s two letters' expiry can differ and still count as equal (closer position wins)

-- picked: the selected letter's identity (Inbox.Id), never its index. Letters shift up
-- as emptied ones go away and down as new ones arrive.
local S = { filter = "all", search = "", picked = nil, confirm = nil, collecting = false }
Inbox.state = S

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m end
end
local function now() return GetTime() end
local function money(c) return DUI.Widgets.Money(c) end
local function pending() return C_Mail and call(C_Mail.IsCommandPending) == true end

-- Letters

function Inbox.Letter(i)
    local pkg, stationery, sender, subject, gold, cod, days, items, read, returned, _, canReply, gm = call(GetInboxHeaderInfo, i)
    if sender == nil and subject == nil then return nil end
    local l = { index = i, sender = sender or "", subject = subject or "", money = tonumber(gold) or 0, cod = tonumber(cod) or 0,
        days = tonumber(days) or 0, items = tonumber(items) or 0, read = read == true, returned = returned == true,
        canReply = canReply == true, gm = gm == true, icon = pkg or stationery }
    local kind, item, player, bid, buyout, deposit, cut, _, _, _, count = call(GetInboxInvoiceInfo, i)
    if kind == "buyer" or kind == "seller" or kind == "seller_temp_invoice" then
        l.invoice = { type = kind, item = item, player = player, bid = tonumber(bid) or 0, buyout = tonumber(buyout) or 0,
            deposit = tonumber(deposit) or 0, cut = tonumber(cut) or 0, count = tonumber(count) or 1 }
    end
    if l.items > 0 then
        local name, _, tex = call(GetInboxItem, i, 1)
        l.firstItem, l.icon = name, tex or l.icon
    end
    l.ah = l.invoice ~= nil or not l.canReply
    -- Like the game's OpenMail_Delete: a letter the client won't delete gets returned.
    -- If the check is missing or errors, treat it as deletable, so Delete keeps its second
    -- click instead of silently returning.
    local okDel, can = true, true
    if type(InboxItemCanDelete) == "function" then okDel, can = pcall(InboxItemCanDelete, i) end
    l.canDelete = not okDel or can ~= false and can ~= nil
    l.key = ns.Ledger.LetterKey(l.sender, l.subject, l.invoice)
    l.ends = time() + l.days * 86400
    return l
end

-- A letter's identity: sender, subject, invoice (the ledger's letter key) and expiry.
-- The index only breaks ties between letters identical in all of those.
function Inbox.Id(l)
    return l and { key = l.key, ends = l.ends, index = l.index }
end

local function gapOf(l, id)
    if l.key ~= id.key then return nil end
    local gap = math.abs(l.ends - id.ends)
    return gap <= ns.Ledger.SAME and gap or nil
end

-- Where the letter named by `id` is now (in `letters`, read if not given).
function Inbox.Find(id, letters)
    if not id then return nil end
    local pick, best, far
    for _, l in ipairs(letters or Inbox.Letters()) do
        local gap = gapOf(l, id)
        if gap then
            local d = math.abs(l.index - id.index)
            if not pick or gap < best - Inbox.TIE or (math.abs(gap - best) <= Inbox.TIE and d < far) then pick, best, far = l, gap, d end
        end
    end
    if pick then id.index = pick.index end
    return pick
end

-- Stable row id per letter across renders (Stack:Ease). A letter matched again (like
-- Inbox.Find: key, then expiry, then index) keeps its id and glides to its new spot;
-- only new letters fade in.
local lastIds, madeIds = {}, 0
function Inbox.LineIds(letters)
    local was, taken, out = lastIds, {}, {}
    lastIds = {}
    for _, l in ipairs(letters) do
        local pick, best, far
        for j, id in ipairs(was) do
            local gap = not taken[j] and gapOf(l, id)
            if gap then
                local d = math.abs(l.index - id.index)
                if not pick or gap < best - Inbox.TIE or (math.abs(gap - best) <= Inbox.TIE and d < far) then pick, best, far = j, gap, d end
            end
        end
        local token
        if pick then
            taken[pick] = true
            token = was[pick].token
        else
            madeIds = madeIds + 1
            token = "letter:" .. madeIds
        end
        lastIds[#lastIds + 1] = { key = l.key, ends = l.ends, index = l.index, token = token }
        out[l] = token
    end
    return out
end

function Inbox.Letters()
    local n, total = call(GetInboxNumItems)
    n = tonumber(n) or 0
    local out = {}
    for i = 1, n do out[#out + 1] = Inbox.Letter(i) end
    return out, math.max(0, (tonumber(total) or n) - n)
end

local function wanted(l)
    local f = S.filter
    if f == "ah" and not l.ah then return false end
    if f == "players" and l.ah then return false end
    if f == "gold" and l.money <= 0 then return false end
    local q = S.search
    if q ~= "" then
        local hay = (l.subject .. " " .. l.sender .. " " .. (l.firstItem or "")):lower()
        if not hay:find(q, 1, true) then return false end
    end
    return true
end

-- The base game's Shift-click on a letter (MAILAUTOLOOTTOGGLE) takes all of it.
local function takeAllClick()
    if type(IsModifiedClick) == "function" then return call(IsModifiedClick, "MAILAUTOLOOTTOGGLE") == true end
    return type(IsShiftKeyDown) == "function" and call(IsShiftKeyDown) == true
end

local function daysText(d)
    if d < 1 then return L["Under a day"] end
    local n = math.floor(d)
    return n == 1 and L["1 day"] or string.format(L["%d days"], n)
end

-- The list

local function lineOf(l, picked, id)
    local value, vc
    if l.money > 0 then value, vc = money(l.money), Style.INK.MONEY
    elseif l.cod > 0 then value, vc = L["COD"], Style.INK.WARN
    elseif l.items > 0 then value, vc = l.items == 1 and L["1 item"] or string.format(L["%d items"], l.items), Style.INK.LABEL end
    local days = daysText(l.days)
    if l.days <= Inbox.LOW_DAYS then days = Win.Parts.Hex(Style.INK.WARN) .. days .. "|r" end
    return { icon = l.icon or ns.Window.ICON, text = l.subject ~= "" and l.subject or l.sender,
        color = l.read and Style.INK.LABEL or Style.INK.VALUE,
        sub = l.sender .. "  ·  " .. days, value = value, valueColor = vc, picked = picked == l,
        id = id,
        onClick = function()
            if takeAllClick() then Inbox.TakeAll(l) end
            Inbox.Pick(l.index)
            if DUI.Sound then DUI.Sound.Play("open") end   -- opening sound, like the game's
        end }
end

function Inbox.Render(pane)
    pane = pane or Inbox.list
    if not pane then return end
    local letters, more = Inbox.Letters()
    local picked = Inbox.Find(S.picked, letters)
    if not picked then S.picked = nil end
    Inbox.read = { letters = letters, picked = picked }   -- the footer paints from these
    local ids = Inbox.LineIds(letters)
    local s = pane.stack
    local at = s:Scrolled()
    -- When open, letters that stay glide to their new spot (one taken, a search or chip)
    -- and new ones fade in.
    local spots = pane:IsVisible() and s:Spots() or nil
    s:Begin()
    local shown = 0
    for _, l in ipairs(letters) do
        if wanted(l) then
            s:Line(lineOf(l, picked, ids[l]))
            shown = shown + 1
        end
    end
    if more > 0 then
        s:Text(string.format(L["%d more letters wait: take some to see them."], more), { color = Style.INK.LABEL, gap = 10 })
    end
    pane.pieces = s:End()
    s:ScrollTo(at)
    s:Ease(spots)
    local empty = shown == 0
    pane.note:SetText((#letters == 0) and L["No letters yet."] or L["No letters match."])
    pane.note:SetShown(empty and more == 0)
    Inbox.Show(nil, picked)
end

function Inbox.Search(text)
    S.search = (text or ""):lower()
    Inbox.Render()
end

function Inbox.Filter(id)
    S.filter = id
    for key, b in pairs(Inbox.list and Inbox.list.chips or {}) do b.SetOn(key == id) end
    Inbox.Render()
end

-- Shift-click: everything in the letter at once, like the base game's. A cash on
-- delivery letter only opens.
function Inbox.TakeAll(l)
    if not l or l.cod > 0 then return end
    Inbox.Do(function() AutoLootMailItem(l.index) end)
end

-- Selecting a letter reads it (GetInboxText marks it read, same as the game's window).
function Inbox.Pick(i)
    S.picked = Inbox.Id(Inbox.Letter(i))
    S.confirm = nil
    call(GetInboxText, i)
    Inbox.Render()
end

-- The letter

local function receipt(s, l)
    local v = l.invoice
    local function row(label, value) s:Text(Win.Parts.Hex(Style.INK.LABEL) .. label .. "|r   " .. value, { color = Style.INK.TEXT, gap = 4 }) end
    if v.type == "seller" or v.type == "seller_temp_invoice" then
        row(L["Sold for"], money(v.bid))
        if v.cut > 0 then row(L["Auction house cut"], Win.Parts.Hex(Style.INK.DAMAGE) .. "-" .. DUI.Widgets.Money(v.cut, { color = false }) .. "|r") end
        if v.deposit > 0 then row(L["Deposit back"], money(v.deposit)) end
        row(L["You keep"], money(v.bid - v.cut + v.deposit))
        if v.type == "seller_temp_invoice" then row(L["Gold on its way"], "") end
    else
        row(L["Bought for"], money(v.bid))
    end
end

local function itemTip(i, a)
    return function(b)
        if not (GameTooltip and GameTooltip.SetInboxItem) then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetInboxItem(i, a)
        GameTooltip:Show()
    end
end

-- The selected letter on the right (`l`, as Render found it).
function Inbox.Show(pane, l)
    pane = pane or Inbox.letter
    if not pane then return end
    local s = pane.stack
    s:Begin()
    pane.note:SetShown(l == nil)
    if l then
        local sub = string.format(L["From %s"], Win.Parts.Hex(Style.INK.VALUE) .. l.sender .. "|r") .. "  ·  " .. daysText(l.days)
        s:Line({ icon = l.icon or ns.Window.ICON, text = l.subject, color = Style.INK.TITLE, sub = sub })
        local body = call(GetInboxText, l.index)
        if type(body) == "string" and body ~= "" then s:Text(body, { color = Style.INK.TEXT, gap = 10 }) end
        if l.invoice then s:Gap(6); receipt(s, l) end
        if l.money > 0 and not l.invoice then s:Gap(6); s:Money(l.money) end
        if l.cod > 0 then
            s:Text(string.format(L["Cash on delivery: taking the items pays %s"], money(l.cod)), { color = Style.INK.WARN, gap = 10 })
        end
        if l.items > 0 then
            local items = {}
            for a = 1, 16 do
                local name, _, tex, count, quality = call(GetInboxItem, l.index, a)
                if name then
                    items[#items + 1] = { name = name, texture = tex, count = count, quality = quality, tooltip = itemTip(l.index, a),
                        onClick = l.cod == 0 and function()
                            local at = Inbox.Find(S.picked)   -- current position of the letter
                            if at then Inbox.Do(function() TakeInboxItem(at.index, a) end) end
                        end or nil }
                end
            end
            s:Gap(8)
            s:Items(items)
        end
    end
    pane.pieces = s:End()
    Inbox.PaintFooter()
end

-- Actions, one command at a time

function Inbox.Do(fn)
    if pending() or S.collecting then return false end
    fn()
    return true
end

-- Irreversible or costly actions need a second click on the same letter (matched by
-- identity, since letters may have moved).
local function asking(what, l)
    return l and S.confirm and S.confirm.what == what and gapOf(l, S.confirm.id) ~= nil
end
local function confirmed(what, l)
    if asking(what, l) and now() - S.confirm.at < Inbox.CONFIRM then
        S.confirm = nil
        return true
    end
    S.confirm = { what = what, id = Inbox.Id(l), at = now() }
    Inbox.PaintFooter()
    C_Timer.After(Inbox.CONFIRM, function() if S.confirm and now() - S.confirm.at >= Inbox.CONFIRM - 0.01 then S.confirm = nil; Inbox.PaintFooter() end end)
    return false
end

function Inbox.Take()
    local l = Inbox.Find(S.picked)
    if not l then return end
    if l.cod > 0 and not confirmed("take", l) then return end
    Inbox.Do(function() AutoLootMailItem(l.index) end)
end

function Inbox.Return()
    local l = Inbox.Find(S.picked)
    if not l then return end
    if Inbox.Do(function() ReturnInboxItem(l.index) end) then
        S.picked = nil
        if DUI.Sound then DUI.Sound.Play("close") end
    end
end

-- Like OpenMailDeleteMixin: a letter the client won't delete (another player's mail
-- still holding something) gets returned, and the button says so.
function Inbox.Delete()
    local l = Inbox.Find(S.picked)
    if not l then return end
    if not l.canDelete then return Inbox.Return() end
    if (l.money > 0 or l.items > 0) and not confirmed("delete", l) then return end
    if Inbox.Do(function() DeleteInboxItem(l.index) end) then
        S.picked = nil
        if DUI.Sound then DUI.Sound.Play("close") end
    end
end

-- The selected letter as last read (cheap, no game calls).
function Inbox.Picked()
    local read = Inbox.read
    return S.picked and read and read.picked or nil
end

-- The selected letter's options, matching the game's open-mail Options menu: Delete,
-- or Return when it can't be deleted; Return too when both are possible.
function Inbox.Options(owner)
    local l = Inbox.Picked()
    if not l then return end
    local keys, values = {}, {}
    if l.canDelete then keys[#keys + 1] = "delete"; values.delete = DELETE or L["Delete"] end
    if not l.canDelete or (l.canReply and not l.returned) then keys[#keys + 1] = "return"; values["return"] = MAIL_RETURN or L["Return"] end
    DUI.Widgets.OpenMenu(owner, keys, values, nil, function(k)
        if k == "delete" then Inbox.Delete() else Inbox.Return() end
    end)
end

function Inbox.Reply()
    local l = Inbox.Find(S.picked)
    if not (l and l.canReply) then return end
    ns.Window.replyTo = { name = l.sender, subject = l.subject, id = Inbox.Id(l) }
    ns.Window.ShowTab("send")
end

-- Collect all, same approach as the game's OpenAllMailMixin (Blizzard_MailFrame): one
-- piece at a time, gold first, then items from the last slot down, the next one
-- Inbox.STEP s later once no command is pending. Emptied letters without text get
-- deleted and the rest shift up, so a count change restarts from the top. GM and COD
-- letters are skipped, items the client refused are skipped by id, a letter whose gold
-- was refused (MAIL_FAILED with no item) is left alone, and full bags stop the run.
local function skipLetter(i)
    local _, _, _, _, _, cod, _, _, _, _, _, _, gm = call(GetInboxHeaderInfo, i)
    if gm == true or (tonumber(cod) or 0) > 0 then return true end
    if #S.left == 0 then return false end
    local l = Inbox.Letter(i)
    for _, id in ipairs(S.left) do
        if l and gapOf(l, id) then return true end
    end
    return false
end

local function skipSlot(i, a)
    local _, id, _, _, _, _, currency = call(GetInboxItem, i, a)
    if currency ~= true and id ~= nil and S.failed[id] then return true end
    if C_Mail and call(C_Mail.HasInboxMoney, i) == true then return false end
    return call(HasInboxItem, i, a) ~= true
end

-- Move S.at to the next letter and slot with something to take; false at the end.
local function advance()
    local at = S.at
    while at.letter <= (call(GetInboxNumItems) or 0) do
        if not skipLetter(at.letter) then
            while at.slot > 0 do
                if not skipSlot(at.letter, at.slot) then return true end
                at.slot = at.slot - 1
            end
        end
        at.letter, at.slot = at.letter + 1, Inbox.SLOTS
    end
    return false
end

local function freeSlots()
    return C_Container and tonumber(call(C_Container.CalculateTotalNumberOfFreeBagSlots))
end

function Inbox.Collect()
    if S.collecting or pending() then return end
    S.collecting, S.failed, S.left, S.full = true, {}, {}, false
    S.at = { letter = 1, slot = Inbox.SLOTS }
    S.count = call(GetInboxNumItems) or 0
    if C_Mail then call(C_Mail.SetOpeningAll, true) end
    Inbox.CollectNext()
end

function Inbox.CollectNext()
    if not S.collecting then return end
    if not (ns.Window.frame and DUI.Win.IsOpen(ns.Window.frame)) then return Inbox.StopCollecting() end
    if pending() then return C_Timer.After(Inbox.STEP, Inbox.CollectNext) end
    if not advance() then return Inbox.StopCollecting() end
    local i = S.at.letter
    local _, _, _, _, gold, _, _, items = call(GetInboxHeaderInfo, i)
    S.tried = nil
    if (tonumber(gold) or 0) > 0 then
        S.tried = Inbox.Id(Inbox.Letter(i))
        TakeInboxMoney(i)
    elseif (tonumber(items) or 0) > 0 and freeSlots() ~= 0 then
        TakeInboxItem(i, S.at.slot)
    else
        -- Bags full: items stay (noted under the letter), but gold from later letters is still
        -- taken.
        if (tonumber(items) or 0) > 0 then S.full = true end
        S.at.letter, S.at.slot = i + 1, Inbox.SLOTS
    end
    C_Timer.After(Inbox.STEP, Inbox.CollectNext)
    Inbox.PaintFooter()
end

function Inbox.StopCollecting()
    if not S.collecting then return end
    S.collecting, S.at, S.tried = false, nil, nil
    if C_Mail then call(C_Mail.SetOpeningAll, false) end
    Inbox.Render()
end

-- Client responses: letters removed (emptied ones without text) restart from the top;
-- a refused item is skipped from then on.
local function inboxChanged()
    if not S.collecting then return end
    local n = call(GetInboxNumItems) or 0
    if n ~= S.count then
        S.count = n
        S.at.letter, S.at.slot = 1, Inbox.SLOTS
    end
end
local function failed(itemID)
    if not S.collecting then return end
    if itemID ~= nil then S.failed[itemID] = true
    elseif S.tried then S.left[#S.left + 1] = S.tried end
    S.tried = nil
end

-- Footer

-- Painted from the letters Render last read (`Inbox.read`). It runs on every Collect
-- all step and click, while the inbox itself is only re-read on its update event.
function Inbox.PaintFooter(pane)
    pane = pane or Inbox.letter
    if not (pane and pane.foot) then return end
    local read = Inbox.read or {}
    local l = S.picked and read.picked
    local busy = S.collecting or pending()
    local function asked(what) return asking(what, l) end
    local take = L["Take"]
    if asked("take") then take = L["Click again to pay"] elseif l and l.cod > 0 then take = string.format(L["Pay %s"], DUI.MoneyString(l.cod)) end
    local anyGold = false
    for _, x in ipairs(read.letters or {}) do if (x.money > 0 or x.items > 0) and x.cod == 0 then anyGold = true end end
    local delete = DELETE or L["Delete"]
    if asked("delete") then delete = L["Click again"] elseif l and not l.canDelete then delete = MAIL_RETURN or L["Return"] end
    -- Collect all under the list (whole inbox), and the selected letter's four buttons
    -- sharing the width under the letter (five in one row overlapped).
    if Inbox.list and Inbox.list.foot then
        Inbox.list.foot:Set({
            { text = S.collecting and L["Collecting..."] or L["Collect all"], primary = true, off = busy or not anyGold, onClick = Inbox.Collect },
        })
    end
    pane.foot:Set({
        { text = take, primary = true, off = busy or not (l and (l.money > 0 or l.items > 0)), onClick = Inbox.Take },
        { text = REPLY_MESSAGE or L["Reply"], off = busy or not (l and l.canReply), onClick = Inbox.Reply },
        -- when the last button returns it, this one would say the same
        { text = L["Return"], off = busy or not (l and l.canReply and not l.returned and l.canDelete), onClick = Inbox.Return },
        { text = delete, tone = "no", off = busy or not l, onClick = Inbox.Delete },
    })
    pane.full:SetShown(S.full == true)
end

-- Page layout: list on the left, letter on the right

local function chip(pane, id, text, x)
    local b = DUI.Widgets.Chip(pane, text)
    b.FitWidth()
    b:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -Inbox.CHIPS_Y)
    b:SetScript("OnClick", function() Inbox.Filter(id) end)
    b.SetOn(S.filter == id)
    pane.chips[id] = b
    return x + b:GetWidth() + DUI.Widgets.CHIP_GAP
end

local function note(pane, text)
    local fs = Style.Text(pane, Style.SIZE.body, "CENTER")
    fs:SetPoint("CENTER", pane, "CENTER", 0, 0)
    Style.InkText(fs, "LABEL")
    fs:SetText(text or "")
    fs:Hide()
    return fs
end

function Inbox.Build(page)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    list:SetWidth(Inbox.LIST_W)
    Inbox.list = list
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(1, 1, 1, 0.06)
    rule:SetWidth(1)
    rule:SetPoint("TOPLEFT", list, "TOPRIGHT", 0, -12)
    rule:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 0, 12)
    local letter = CreateFrame("Frame", nil, page)
    letter:SetPoint("TOPLEFT", list, "TOPRIGHT", 1, 0)
    letter:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    Inbox.letter = letter

    local box = DUI.Widgets.Input(list, { search = true, hint = L["Search mail..."], onChange = function(t) Inbox.Search(t) end })
    box:SetPoint("TOPLEFT", list, "TOPLEFT", Inbox.EDGE, -10)
    box:SetPoint("TOPRIGHT", list, "TOPRIGHT", -Inbox.EDGE, -10)
    list.search = box
    list.chips = {}
    local x = Inbox.EDGE
    x = chip(list, "all", ALL or L["All"], x)
    x = chip(list, "ah", L["Auction house"], x)
    x = chip(list, "players", L["Players"], x)
    chip(list, "gold", L["Gold"], x)
    list.stack = Win.Parts.Stack(list, { top = Inbox.TOP, bottom = Inbox.FOOT })
    list.foot = Win.Parts.Footer(list, { edge = Inbox.EDGE, equal = true })
    list.foot.frame:ClearAllPoints()
    list.foot.frame:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", Inbox.EDGE, 12)
    list.note = note(list)

    letter.stack = Win.Parts.Stack(letter, { top = 12, bottom = Inbox.FOOT })
    letter.foot = Win.Parts.Footer(letter, { equal = true })
    list.foot.frame:SetWidth(Inbox.LIST_W - 2 * Inbox.EDGE)
    -- An equal-share footer reads its width, which a frame anchored on two sides may not
    -- know yet on first fill. Set it explicitly, and again when the window resizes.
    local function fitFoot(w)
        local foot = letter.foot.frame
        foot:ClearAllPoints()
        foot:SetPoint("BOTTOMLEFT", letter, "BOTTOMLEFT", Win.Parts.EDGE, 12)
        foot:SetWidth(math.max(1, w - 2 * Win.Parts.EDGE))
    end
    fitFoot(ns.Window.W - Inbox.LIST_W - 1)
    letter:SetScript("OnSizeChanged", function(_, w)
        if type(w) == "number" and w > 0 then fitFoot(w); Inbox.PaintFooter() end
    end)
    letter.note = note(letter, L["Pick a letter."])
    letter.full = Style.Text(letter, Style.SIZE.small, "LEFT")
    letter.full:SetPoint("BOTTOMLEFT", letter, "BOTTOMLEFT", Win.Parts.EDGE, Inbox.FOOT)
    Style.InkText(letter.full, "WARN")
    letter.full:SetText(L["Your bags are full."])
    letter.full:Hide()

    DUI.RegisterEvent("MAIL_INBOX_UPDATE", function() inboxChanged(); Inbox.Soon() end)
    DUI.RegisterEvent("MAIL_SUCCESS", function() if list:IsVisible() then Inbox.PaintFooter() end end)
    DUI.RegisterEvent("MAIL_FAILED", function(_, itemID) failed(itemID); if list:IsVisible() then Inbox.PaintFooter() end end)
    DUI.RegisterEvent("MAIL_OPEN_ALL_CANCELED", function() Inbox.StopCollecting() end)
    DUI.RegisterEvent("MAIL_CLOSED", function() Inbox.StopCollecting(); S.picked, Inbox.read = nil, nil end)
end

-- The inbox updates in bursts (several per letter during Collect all): redraw once,
-- next frame, only while shown.
function Inbox.Soon()
    local list = Inbox.list
    if not (list and list:IsVisible()) or Inbox.pending then return end
    Inbox.pending = true
    C_Timer.After(0, function()
        Inbox.pending = nil
        if list:IsVisible() then Inbox.Render() end
    end)
end

function Inbox.Fill()
    S.full = false
    Inbox.Render()
end

function Inbox.Pieces()
    local out = {}
    for _, p in ipairs(Inbox.list and Inbox.list.pieces or {}) do out[#out + 1] = p end
    for _, p in ipairs(Inbox.letter and Inbox.letter.pieces or {}) do out[#out + 1] = p end
    return out
end
