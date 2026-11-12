-- The fake game's mailbox and auction house, for the mailbox window and its gold
-- ledger. Copied from the game's source (Blizzard_MailFrame, the API docs) and
-- what was seen in game:
--   * The mailbox is a player interaction (Enum.PlayerInteractionType.MailInfo
--     17). PLAYER_INTERACTION_MANAGER_FRAME_SHOW(17) and MAIL_SHOW run the game's
--     MailFrame_Show (ShowUIPanel(MailFrame), then CloseMail if it didn't show).
--     Walking away (FRAME_HIDE, MAIL_CLOSED) runs MailFrame_Hide, and MailFrame's
--     OnHide calls CloseMail(). The client keeps the mailbox open until CloseMail,
--     and while it's open clicking a mailbox does nothing. MW.Open refuses then,
--     which is what a hidden MailFrame that never ran its OnHide would cause.
--   * One mail command at a time (C_Mail.IsCommandPending); a second is refused.
--     Each answers a server step later (MW.Step) with MAIL_INBOX_UPDATE and
--     MAIL_SUCCESS (CLOSE_INBOX_ITEM when a letter empties). The gold arrives a
--     step after that, since PLAYER_MONEY comes after the event that caused it
--     (~0.2-0.3 s in game).
--   * AutoLootMailItem / TakeInboxItem with full bags: MAIL_FAILED + UI_ERROR_MESSAGE
--     "Inventory is full.". An item from a cash-on-delivery letter pays the COD.
--   * SendMail needs a first and last name. One word answers UI_ERROR_MESSAGE
--     457 "Please enter a full character name.". A send fires MAIL_SEND_SUCCESS,
--     MAIL_SUCCESS, then PLAYER_MONEY minus postage (30 a letter, 30 an item)
--     and the gold attached.
--   * The auction house is played by the test, since any addon's call looks the
--     same from outside (only the client's events): MW.BuyCommodity, MW.BuyItem,
--     MW.Post, MW.Cancel, MW.Sold, MW.Expired. Their letters arrive with
--     MW.Deliver. Buyer invoice: bid = the total paid. Not yet seen in game, so
--     guesses: a gear buy's events, the sold notice's text, and a sale letter's
--     gold = bid - cut + deposit.
--
-- MW.world(spec) is stub.Load's "before". Server answers wait in a queue:
-- MW.Step() runs the next one (advancing the clock by its delay), MW.Settle()
-- runs them all. MW.Calls(kind) reads what the addon called.
local stub = require("stub")

local MW = {}

MW.MAIL_INFO = 17      -- Enum.PlayerInteractionType.MailInfo
MW.AUCTIONEER = 21     -- Enum.PlayerInteractionType.Auctioneer
MW.STEP = 0.25         -- seconds between a server answer and the next
MW.POSTAGE = 30
MW.NOTICE = { BidPlaced = 0, AuctionRemoved = 1, AuctionWon = 2, AuctionOutbid = 3, AuctionSold = 4, AuctionExpired = 5 }

local function S() return MW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end
function MW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.args end end
    return out
end

local function fire(...) stub.FireEvent(...) end

-- The server's answers, in order. Each waits `delay` seconds.
local function later(delay, fn) table.insert(S().queue, { delay = delay or MW.STEP, fn = fn }) end
function MW.Step()
    local q = table.remove(S().queue, 1)
    if not q then return false end
    stub.Advance(q.delay)
    q.fn()
    stub.RunTimers()
    return true
end
function MW.Settle() for _ = 1, 200 do if not MW.Step() then return end end end
function MW.Waiting() return #S().queue end

local function setMoney(m)
    S().money = m
    fire("PLAYER_MONEY")
end
local function payLater(delta) later(MW.STEP, function() setMoney(S().money + delta) end) end

-- ---------------------------------------------------------------------
-- Letters
-- ---------------------------------------------------------------------

-- A letter: { sender, subject, body, money, cod, days, read, returned,
-- canReply, items = { { name, itemID, count, quality } }, invoice = { type,
-- item, player, bid, buyout, deposit, cut, count } }.
function MW.Letter(t)
    t.money, t.cod, t.days = t.money or 0, t.cod or 0, t.days or 30
    t.items = t.items or {}
    t.body = t.body or ""
    if t.canReply == nil then t.canReply = t.invoice == nil end
    return t
end

-- Letters the server holds for you. MW.Deliver puts them in the inbox.
function MW.Arrive(t) table.insert(S().incoming, MW.Letter(t)) end
function MW.Deliver()
    for _, l in ipairs(S().incoming) do table.insert(S().inbox, 1, l) end
    local had = #S().incoming > 0
    S().incoming = {}
    if had then
        fire("UPDATE_PENDING_MAIL")
        if S().open then fire("MAIL_INBOX_UPDATE") end
    end
end

function MW.Inbox() return S().inbox end
local function L(i)
    local l = S().inbox[i]
    if type(i) ~= "number" or not l then error("bad inbox index " .. tostring(i), 3) end
    return l
end
local function itemCount(l) return #l.items > 0 and #l.items or nil end

-- One command at a time, answered a step later.
local function command(name, fn)
    if S().pending then record("Refused", name); return false end
    if not S().open then record("Refused", name); return false end
    S().pending = true
    later(MW.STEP, function()
        S().pending = false
        fn()
    end)
    return true
end

-- An emptied letter closes. One with no text (an auction house letter) is deleted
-- too, and the letters under it move up one. The game's Open All starts from the
-- top again when the count changes (OpenAllMailMixin).
local function emptied(i, l)
    if l.money == 0 and #l.items == 0 then
        fire("CLOSE_INBOX_ITEM", i)
        if l.body == "" and S().inbox[i] == l then
            table.remove(S().inbox, i)
            fire("MAIL_INBOX_UPDATE")
        end
    end
end

local function takeItem(i, l, a)
    local it = l.items[a]
    if not it then return true end
    if S().bagFree <= 0 then
        fire("MAIL_FAILED", 5165)
        fire("UI_ERROR_MESSAGE", 3, "Inventory is full.")
        return false
    end
    S().bagFree = S().bagFree - 1
    table.remove(l.items, a)
    table.insert(S().bags, it)
    if l.cod > 0 then
        local cod = l.cod
        l.cod = 0
        payLater(-cod)
    end
    return true
end

-- ---------------------------------------------------------------------
-- The game's frames
-- ---------------------------------------------------------------------

local function frames()
    if _G.MailFrame then return _G.MailFrame end
    local f = CreateFrame("Frame", "MailFrame", UIParent)
    f:Hide()
    f.InboxFrame = CreateFrame("Frame", "InboxFrame", f)
    f.SendMailFrame = CreateFrame("Frame", "SendMailFrame", f)
    f.SendMailFrame:Hide()
    CreateFrame("EditBox", "SendMailNameEditBox", f.SendMailFrame)
    CreateFrame("EditBox", "SendMailSubjectEditBox", f.SendMailFrame)
    local open = CreateFrame("Frame", "OpenMailFrame", UIParent)
    open:Hide()
    -- The game's MailMixin:OnHide.
    f:SetScript("OnHide", function()
        CloseMail()
        HideUIPanel(open)
        SetSendMailShowing(false)
    end)
    return f
end

-- The game's MailFrame_Show / MailFrame_Hide.
local function mailFrameShow()
    local f = frames()
    ShowUIPanel(f)
    if not f:IsShown() then CloseMail(); return end
    f.InboxFrame:Show()
    f.SendMailFrame:Hide()
end
local function mailFrameHide() HideUIPanel(frames()) end

-- The player right-clicks a mailbox. Refused while the client still has one open
-- (CloseMail never came).
function MW.Open()
    if S().open then record("Refused", "Open"); return false end
    S().open = true
    fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", MW.MAIL_INFO)
    fire("MAIL_SHOW")
    mailFrameShow()
    fire("MAIL_INBOX_UPDATE")
    stub.RunTimers()
    return true
end

-- The player walks away (or the client closes the interaction).
function MW.Leave()
    if not S().open then return end
    S().open = false
    fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", MW.MAIL_INFO)
    fire("MAIL_CLOSED")
    mailFrameHide()
    stub.RunTimers()
end

function MW.IsOpen() return S().open == true end

-- ---------------------------------------------------------------------
-- The auction house, played by the test (only the client's events)
-- ---------------------------------------------------------------------

local nextAuction = 62842353

-- A commodity (cloth, herbs...) bought with any addon. As in game: the quote
-- (COMMODITY_PRICE_UPDATED unit, total), then the won notice and SUCCEEDED,
-- PURCHASE_COMPLETED 0 and AUCTION_CANCELED 0 (in either order, `completedFirst`),
-- then the gold a step later. The "Auction won" letter (buyer invoice: bid = total)
-- waits for MW.Deliver.
function MW.BuyCommodity(t)
    local total = t.unit * t.count
    fire("COMMODITY_PRICE_UPDATED", t.unit, total)
    local function won()
        fire("AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION", t.name, t.count)
        fire("COMMODITY_PURCHASE_SUCCEEDED")
    end
    local function completed()
        fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 0)
        fire("AUCTION_CANCELED", 0)
        fire("UPDATE_PENDING_MAIL")
    end
    later(MW.STEP, function()
        if t.completedFirst then completed(); won() else won(); completed() end
    end)
    payLater(-total)
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction won: " .. t.name .. (t.count > 1 and (" (" .. t.count .. ")") or ""),
        items = { { name = t.name, itemID = t.itemID, count = t.count, quality = 1 } },
        invoice = { type = "buyer", item = t.name, player = t.seller, bid = total, buyout = 1, deposit = 0, cut = 0, count = t.count } })
end

-- Gear bought outright. A guess: PURCHASE_COMPLETED(id) and ITEM_PURCHASED(itemID).
function MW.BuyItem(t)
    local id = nextAuction
    nextAuction = nextAuction + 1
    later(MW.STEP, function()
        fire("AUCTION_HOUSE_PURCHASE_COMPLETED", id)
        fire("ITEM_PURCHASED", t.itemID)
    end)
    payLater(-t.price)
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction won: " .. t.name,
        items = { { name = t.name, itemID = t.itemID, count = 1, quality = t.quality or 2 } },
        invoice = { type = "buyer", item = t.name, player = t.seller, bid = t.price, buyout = t.price, deposit = 0, cut = 0, count = 1 } })
end

-- An auction posted: AUCTION_HOUSE_AUCTION_CREATED(id), with the deposit a step later.
function MW.Post(t)
    local id = nextAuction
    nextAuction = nextAuction + 1
    S().auctions[id] = { name = t.name, itemID = t.itemID, count = t.count or 1, deposit = t.deposit or 0, price = t.price }
    later(MW.STEP, function() fire("AUCTION_HOUSE_AUCTION_CREATED", id) end)
    payLater(-(t.deposit or 0))
    return id
end

-- Canceled: the notice (AuctionRemoved) and AUCTION_CANCELED(id) at once. The item
-- comes back by letter with no invoice, and the house keeps the deposit.
function MW.Cancel(id)
    local a = S().auctions[id]
    S().auctions[id] = nil
    fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", MW.NOTICE.AuctionRemoved, "", id)
    fire("AUCTION_CANCELED", id)
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction canceled: " .. a.name .. (a.count > 1 and (" (" .. a.count .. ")") or ""),
        items = { { name = a.name, itemID = a.itemID, count = a.count, quality = 1 } } })
end

-- Sold (the notice is a guess). The seller letter carries bid - cut + deposit.
function MW.Sold(id, t)
    local a = S().auctions[id]
    S().auctions[id] = nil
    local bid = (t and t.bid) or a.price
    local cut = (t and t.cut) or math.floor(bid * 0.05)
    if S().ahOpen then fire("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", MW.NOTICE.AuctionSold, "A buyer has been found for your auction of " .. a.name .. ".", id) end
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction successful: " .. a.name .. (a.count > 1 and (" (" .. a.count .. ")") or ""),
        money = bid - cut + a.deposit,
        invoice = { type = "seller", item = a.name, player = (t and t.buyer) or "Ysella Brightwind", bid = bid, buyout = bid, deposit = a.deposit, cut = cut, count = a.count } })
end

-- Expired: the item comes back and the deposit is lost.
function MW.Expired(id)
    local a = S().auctions[id]
    S().auctions[id] = nil
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction expired: " .. a.name .. (a.count > 1 and (" (" .. a.count .. ")") or ""),
        items = { { name = a.name, itemID = a.itemID, count = a.count, quality = 1 } } })
end

function MW.OpenAH()
    S().ahOpen = true
    fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", MW.AUCTIONEER)
    fire("AUCTION_HOUSE_SHOW")
end
function MW.CloseAH()
    S().ahOpen = false
    fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", MW.AUCTIONEER)
    fire("AUCTION_HOUSE_CLOSED")
end

-- ---------------------------------------------------------------------
-- The client's functions
-- ---------------------------------------------------------------------

local function install()
    _G.ShowUIPanel = function(f) record("ShowUIPanel", f:GetName()); f:Show() end
    _G.HideUIPanel = function(f) record("HideUIPanel", f:GetName()); f:Hide() end
    _G.GetMoney = function() return S().money end
    _G.CloseMail = function()
        record("CloseMail")
        S().open = false
    end
    _G.CheckInbox = function() record("CheckInbox") end
    _G.GetInboxNumItems = function() return #S().inbox, #S().inbox + (S().beyond or 0) end
    -- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft,
    -- itemCount, wasRead, wasReturned, textCreated, canReply, isGM
    _G.GetInboxHeaderInfo = function(i)
        local l = S().inbox[i]
        if not l then return nil end
        return 133465, nil, l.sender, l.subject, l.money, l.cod, l.days, itemCount(l), l.read == true,
            l.returned == true, l.read == true, l.canReply == true, false
    end
    _G.GetInboxText = function(i)
        local l = L(i)
        l.read = true
        return l.body, nil, nil, l.invoice ~= nil
    end
    -- name, itemID, texture, count, quality, canUse
    _G.GetInboxItem = function(i, a)
        local it = L(i).items[a]
        if not it then return nil end
        return it.name, it.itemID, 134400, it.count, it.quality or 1, true, false
    end
    _G.HasInboxItem = function(i, a) return L(i).items[a] ~= nil end
    _G.C_Container = _G.C_Container or {}
    C_Container.CalculateTotalNumberOfFreeBagSlots = function() return S().bagFree end
    _G.GetInboxItemLink = function(i, a)
        local it = L(i).items[a]
        return it and ("|cffffffff|Hitem:" .. it.itemID .. "|h[" .. it.name .. "]|h|r") or nil
    end
    -- invoiceType, itemName, playerName, bid, buyout, deposit, consignment,
    -- moneyDelay, etaHour, etaMin, count, commerceAuction
    _G.GetInboxInvoiceInfo = function(i)
        local v = L(i).invoice
        if not v then return nil end
        return v.type, v.item, v.player, v.bid, v.buyout, v.deposit, v.cut, 0, 0, 0, v.count, false
    end
    -- The client's rule lives in C. The game's own Lua (OpenMailDeleteMixin, and
    -- the expiry tooltip TIME_UNTIL_DELETED/RETURNED) shows a deletable letter may
    -- still hold items or gold (an auction house one asks first), and one that
    -- can't be deleted is returned. That means a player's letter still holding gold
    -- or items that hasn't been returned once (the server's return rule).
    _G.InboxItemCanDelete = function(i)
        local l = L(i)
        return l.returned == true or l.canReply ~= true or (l.money == 0 and l.cod == 0 and #l.items == 0)
    end
    _G.TakeInboxMoney = function(i)
        record("TakeInboxMoney", i)
        command("TakeInboxMoney", function()
            local l = L(i)
            local m = l.money
            l.money = 0
            fire("MAIL_INBOX_UPDATE")
            fire("MAIL_SUCCESS")
            emptied(i, l)
            if m > 0 then payLater(m) end
        end)
    end
    _G.TakeInboxItem = function(i, a)
        record("TakeInboxItem", i, a)
        command("TakeInboxItem", function()
            local l = L(i)
            if takeItem(i, l, a or 1) then
                fire("MAIL_INBOX_UPDATE")
                fire("MAIL_SUCCESS")
                emptied(i, l)
            end
        end)
    end
    -- Everything in the letter: its gold, then each item until the bags fill.
    _G.AutoLootMailItem = function(i)
        record("AutoLootMailItem", i)
        command("AutoLootMailItem", function()
            local l = L(i)
            local m = l.money
            l.money = 0
            while #l.items > 0 do
                if not takeItem(i, l, 1) then break end
            end
            fire("MAIL_INBOX_UPDATE")
            fire("MAIL_SUCCESS")
            emptied(i, l)
            if m > 0 then payLater(m) end
        end)
    end
    _G.DeleteInboxItem = function(i)
        record("DeleteInboxItem", i)
        command("DeleteInboxItem", function()
            table.remove(S().inbox, i)
            fire("MAIL_INBOX_UPDATE")
            fire("MAIL_SUCCESS")
        end)
    end
    _G.ReturnInboxItem = function(i)
        record("ReturnInboxItem", i)
        command("ReturnInboxItem", function()
            table.remove(S().inbox, i)
            fire("MAIL_INBOX_UPDATE")
            fire("MAIL_SUCCESS")
        end)
    end

    _G.C_CurrencyInfo = _G.C_CurrencyInfo or {}
    _G.C_CurrencyInfo.GetCoinText = function(amount, sep)
        local out = {}
        local g, s2, c = math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100
        if g > 0 then out[#out + 1] = g .. " Gold" end
        if s2 > 0 then out[#out + 1] = s2 .. " Silver" end
        if c > 0 or #out == 0 then out[#out + 1] = c .. " Copper" end
        return table.concat(out, sep)
    end
    _G.SetSendMailShowing = function(on) S().sendShowing = on == true end
    _G.GetCursorInfo = function() if S().cursor then return "item", S().cursor.itemID end end
    _G.SetSendMailMoney = function(c)
        if c > S().money then return false end
        S().send.money = c
        fire("SEND_MAIL_MONEY_CHANGED")
        return true
    end
    _G.SetSendMailCOD = function(c) S().send.cod = c; fire("SEND_MAIL_COD_CHANGED") end
    _G.GetSendMailItem = function(slot)
        local it = S().send.items[slot]
        if not it then return nil end
        return it.name, it.itemID, 134400, it.count, it.quality or 1
    end
    _G.ClickSendMailItemButton = function(slot, clear)
        record("ClickSendMailItemButton", slot, clear)
        if clear then S().send.items[slot] = nil
        elseif S().cursor then S().send.items[slot] = S().cursor; S().cursor = nil end
        fire("MAIL_SEND_INFO_UPDATE")
    end
    _G.GetSendMailPrice = function()
        local n = 0
        for _ in pairs(S().send.items) do n = n + 1 end
        return MW.POSTAGE * math.max(1, n)
    end
    _G.SendMail = function(to, subject, body)
        record("SendMail", to, subject, body)
        if type(to) ~= "string" or not to:find("%S+%s+%S+") then
            fire("UI_ERROR_MESSAGE", 457, "Please enter a full character name.")
            return
        end
        -- The game's Send button stays off without a subject (SendMailFrame_CanSend).
        if type(subject) ~= "string" or subject == "" then record("Refused", "SendMail"); return end
        if S().pending then record("Refused", "SendMail"); return end
        S().pending = true
        local cost = GetSendMailPrice() + (S().send.money or 0)
        local sent = { to = to, subject = subject, body = body, money = S().send.money or 0, cod = S().send.cod or 0, items = S().send.items }
        S().send = { items = {} }
        fire("MAIL_LOCK_SEND_ITEMS")
        later(MW.STEP, function()
            S().pending = false
            table.insert(S().sent, sent)
            fire("MAIL_SEND_SUCCESS")
            fire("MAIL_SUCCESS")
            fire("MAIL_UNLOCK_SEND_ITEMS")
        end)
        payLater(-cost)
    end

    _G.C_Mail = {
        IsCommandPending = function() return S().pending == true end,
        HasInboxMoney = function(i) return L(i).money > 0 end,
        CanCheckInbox = function() return true end,
        SetOpeningAll = function(on) S().openingAll = on == true end,
        GetCraftingOrderMailInfo = function() return nil end,
    }
    -- Item icons and names by ID, as the client's C_Item answers them (instantly,
    -- cached or not). By name, only an item the test says is cached.
    _G.C_Item = _G.C_Item or {}
    C_Item.GetItemIconByID = function(id) return "icon:" .. tostring(id) end
    C_Item.GetItemNameByID = C_Item.GetItemNameByID or function() return nil end
    C_Item.GetItemInfoInstant = function(name) return (S().cached or {})[name] end
    _G.Enum = _G.Enum or {}
    Enum.PlayerInteractionType = Enum.PlayerInteractionType or { Merchant = 5, MailInfo = MW.MAIL_INFO, Auctioneer = MW.AUCTIONEER }
    Enum.AuctionHouseNotification = MW.NOTICE
end

-- The player holds an item on the cursor (picked from the bags).
function MW.Cursor(item) S().cursor = item end
function MW.Sent() return S().sent end
function MW.Bags() return S().bags end

-- A copy of a test's letter, so the world changes its own (gold taken), never the test's.
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

function MW.world(spec)
    spec = spec or {}
    return function()
        MW.state = { calls = {}, queue = {}, inbox = {}, incoming = {}, sent = {}, bags = {}, auctions = {},
            money = spec.money or 1000000, bagFree = spec.bagFree or 16, send = { items = {} }, beyond = spec.beyond }
        _G.MailFrame, _G.InboxFrame, _G.SendMailFrame, _G.OpenMailFrame = nil, nil, nil, nil
        _G.SendMailNameEditBox, _G.SendMailSubjectEditBox = nil, nil
        install()
        for _, l in ipairs(spec.letters or {}) do table.insert(MW.state.inbox, MW.Letter(copy(l))) end
        frames()
        if spec.db then DaylightUIDB = spec.db end
    end
end

return MW
