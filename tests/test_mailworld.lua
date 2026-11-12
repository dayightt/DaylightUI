local stub = require("stub")
local MW = require("mailworld")

-- The fake mailbox and auction house behave like the game's, as checked in
-- game. The mailbox window and its ledger are tested against them.

-- The game's own mailbox, with the addon's window off (it parks MailFrame when on).
local function load(spec)
    spec = spec or {}
    spec.db = { profileData = { ["DPS/Tank"] = { modules = { Mailbox = { enabled = false } } } } }
    stub.Load({ before = MW.world(spec) })
end

-- Writes down the events, each with the gold at that moment.
local function ear(events)
    local heard = {}
    local f = CreateFrame("Frame")
    for _, e in ipairs(events) do f:RegisterEvent(e) end
    f:SetScript("OnEvent", function(_, e, ...) heard[#heard + 1] = { e = e, gold = GetMoney(), ... } end)
    return heard
end
local function names(heard)
    local out = {}
    for _, h in ipairs(heard) do out[#out + 1] = h.e end
    return table.concat(out, " ")
end

T.test("mailworld: a mailbox opens the game's MailFrame and walking away closes it with CloseMail", function()
    load()
    T.truthy(MW.Open())
    T.truthy(MailFrame:IsShown())
    MW.Leave()
    T.falsy(MailFrame:IsShown())
    T.eq(#MW.Calls("CloseMail") >= 1, true, "the game's OnHide calls CloseMail")
    T.truthy(MW.Open(), "and a mailbox clicks again")
end)

T.test("mailworld: until CloseMail comes, clicking a mailbox does nothing", function()
    load()
    MW.Open()
    T.falsy(MW.Open(), "the client still has one open")
    CloseMail()
    T.truthy(MW.Open())
end)

T.test("mailworld: one mail command at a time, and the gold comes after MAIL_SUCCESS", function()
    load({ money = 100, letters = { { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 } } })
    MW.Open()
    local heard = ear({ "MAIL_SUCCESS", "PLAYER_MONEY", "CLOSE_INBOX_ITEM" })
    TakeInboxMoney(1)
    T.truthy(C_Mail.IsCommandPending())
    DeleteInboxItem(1)
    T.eq(MW.Calls("Refused")[1][1], "DeleteInboxItem", "a second command while one is pending is refused")
    MW.Step()
    T.eq(names(heard), "MAIL_SUCCESS CLOSE_INBOX_ITEM")
    T.eq(GetMoney(), 100, "no gold yet")
    MW.Step()
    T.eq(heard[3].e, "PLAYER_MONEY"); T.eq(heard[3].gold, 15100)
end)

T.test("mailworld: full bags stop a loot with the game's error", function()
    load({ bagFree = 0, letters = { { sender = "Alliance Auction House", subject = "Auction canceled: Linen Cloth (20)",
        items = { { name = "Linen Cloth", itemID = 2589, count = 20 } } } } })
    MW.Open()
    local heard = ear({ "MAIL_FAILED", "UI_ERROR_MESSAGE" })
    AutoLootMailItem(1)
    MW.Settle()
    T.eq(names(heard), "MAIL_FAILED UI_ERROR_MESSAGE")
    T.eq(heard[2][2], "Inventory is full.")
    T.eq(select(8, GetInboxHeaderInfo(1)), 1, "the item stays in the letter")
end)

T.test("mailworld: an item from a cash-on-delivery letter pays the COD", function()
    load({ money = 100000, letters = { { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000,
        items = { { name = "Runecloth", itemID = 14047, count = 20 } } } } })
    MW.Open()
    TakeInboxItem(1, 1)
    MW.Settle()
    T.eq(GetMoney(), 40000)
    T.eq(MW.Bags()[1].name, "Runecloth")
end)

T.test("mailworld: SendMail wants a first and last name; a send pays postage after MAIL_SEND_SUCCESS", function()
    load({ money = 1000 })
    MW.Open()
    local heard = ear({ "UI_ERROR_MESSAGE", "MAIL_SEND_SUCCESS", "PLAYER_MONEY" })
    SendMail("beorn", "Hi", "")
    T.eq(heard[1][2], "Please enter a full character name.")
    SetSendMailMoney(500)
    SendMail("Shooty McGoovy", "Hi", "")
    MW.Settle()
    T.eq(names(heard), "UI_ERROR_MESSAGE MAIL_SEND_SUCCESS PLAYER_MONEY")
    T.eq(heard[2].gold, 1000, "the gold leaves after the send's event")
    T.eq(GetMoney(), 1000 - 30 - 500, "postage and the gold attached")
    T.eq(MW.Sent()[1].to, "Shooty McGoovy")
end)

T.test("mailworld: a commodity bought (any addon) answers with events, then the gold, then a won letter", function()
    load({ money = 324 })
    local heard = ear({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
        "AUCTION_CANCELED", "PLAYER_MONEY" })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Sunscale Feather", itemID = 5115, count = 20, unit = 1 })
    T.eq(heard[1][1], 1); T.eq(heard[1][2], 20, "the quote: unit and total")
    MW.Step()
    T.eq(names(heard), "COMMODITY_PRICE_UPDATED COMMODITY_PURCHASE_SUCCEEDED AUCTION_HOUSE_PURCHASE_COMPLETED AUCTION_CANCELED")
    T.eq(heard[3][1], 0, "PURCHASE_COMPLETED 0 for a commodity")
    T.eq(GetMoney(), 324, "gold not gone yet")
    MW.Step()
    T.eq(heard[5].e, "PLAYER_MONEY"); T.eq(GetMoney(), 304)
    MW.Open()
    MW.Deliver()
    local kind, item, _, bid, _, _, _, _, _, _, count = GetInboxInvoiceInfo(1)
    T.eq(kind, "buyer"); T.eq(item, "Sunscale Feather"); T.eq(bid, 20, "bid = the total paid"); T.eq(count, 20)
end)

T.test("mailworld: post, cancel, sell and expire: deposits, notices and letters", function()
    load({ money = 10000 })
    local heard = ear({ "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_CANCELED", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "PLAYER_MONEY" })
    MW.OpenAH()
    local a = MW.Post({ name = "Heavy Leather", itemID = 4234, count = 20, deposit = 100, price = 51000 })
    local b = MW.Post({ name = "Thick Hide", itemID = 8169, count = 4, deposit = 1400, price = 9000 })
    local c = MW.Post({ name = "Linen Cloth", itemID = 2589, count = 20, deposit = 60, price = 400 })
    MW.Settle()
    T.eq(names(heard), "AUCTION_HOUSE_AUCTION_CREATED PLAYER_MONEY AUCTION_HOUSE_AUCTION_CREATED PLAYER_MONEY AUCTION_HOUSE_AUCTION_CREATED PLAYER_MONEY",
        "each deposit after its post")
    T.eq(GetMoney(), 10000 - 1560)
    MW.Cancel(c)
    T.eq(heard[7][1], MW.NOTICE.AuctionRemoved); T.eq(heard[8].e, "AUCTION_CANCELED"); T.eq(heard[8][1], c)
    MW.Sold(a, { cut = 2550 })
    MW.Expired(b)
    MW.Open()
    MW.Deliver()
    local subjects = {}
    for i = 1, GetInboxNumItems() do subjects[i] = select(4, GetInboxHeaderInfo(i)) end
    T.eq(table.concat(subjects, " | "), "Auction expired: Thick Hide (4) | Auction successful: Heavy Leather (20) | Auction canceled: Linen Cloth (20)")
    local kind, _, _, bid, _, deposit, cut = GetInboxInvoiceInfo(2)
    T.eq(kind, "seller"); T.eq(bid, 51000); T.eq(deposit, 100); T.eq(cut, 2550)
    T.eq(select(5, GetInboxHeaderInfo(2)), 51000 - 2550 + 100, "the sale letter's gold")
    T.isnil(GetInboxInvoiceInfo(1), "an expired auction's letter has no invoice")
end)
