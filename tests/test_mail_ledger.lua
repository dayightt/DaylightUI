local stub = require("stub")
local MW = require("mailworld")

-- The mailbox gold ledger: gold in and out through mail and the auction house.
-- It reads only the client's events, so a buy or post made by any addon counts.

local function load(spec)
    stub.Load({ before = MW.world(spec) })
    return stub.mail.Ledger
end

local function kinds(Ledger, range) return Ledger.Range(range or "session").kinds end

local function sale(id, cut) MW.Sold(id, { cut = cut }) end

T.test("ledger: a commodity bought with any addon is a buy of its quote, named from the won notice", function()
    local Ledger = load({ money = 324 })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Sunscale Feather", itemID = 5115, count = 20, unit = 1 })
    MW.Settle()
    T.eq(kinds(Ledger).buys, -20)
    local r = Ledger.Recent()[1]
    T.eq(r.kind, "buys"); T.eq(r.item, "Sunscale Feather"); T.eq(r.count, 20)
    local it = Ledger.Range("session").items[1]
    T.eq(it.name, "Sunscale Feather"); T.eq(it.bought, 20); T.eq(it.boughtN, 20)
end)

T.test("ledger: the purchase's events in either order, and two buys back to back", function()
    local Ledger = load({ money = 10000 })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Linen Cloth", itemID = 2589, count = 1, unit = 16, completedFirst = true })
    MW.BuyCommodity({ name = "Wool Cloth", itemID = 2592, count = 10, unit = 30 })
    MW.Settle()
    T.eq(kinds(Ledger).buys, -316)
    T.eq(#Ledger.Recent(), 2)
end)

T.test("ledger: gear bought outright books the gold that left", function()
    local Ledger = load({ money = 100000 })
    MW.OpenAH()
    MW.BuyItem({ name = "Feral Blade", itemID = 1726, price = 42000 })
    MW.Settle()
    T.eq(kinds(Ledger).buys, -42000)
end)

T.test("ledger: a post's deposit counts; gold spent elsewhere doesn't", function()
    local Ledger = load({ money = 10000 })
    MW.OpenAH()
    MW.Post({ name = "Heavy Leather", itemID = 4234, count = 20, deposit = 100, price = 51000 })
    MW.Settle()
    T.eq(kinds(Ledger).deposits, -100)
    MW.state.money = 9000     -- a vendor or repair, not tracked by the ledger
    stub.FireEvent("PLAYER_MONEY")
    stub.Advance(5)
    MW.state.money = 9500     -- loot
    stub.FireEvent("PLAYER_MONEY")
    T.eq(Ledger.Range("session").net, -100)
end)

T.test("ledger: a sale letter's gold taken (by any addon) is the price, the cut and the deposit back", function()
    local Ledger = load({ money = 10000 })
    MW.OpenAH()
    local id = MW.Post({ name = "Heavy Leather", itemID = 4234, count = 20, deposit = 100, price = 51000 })
    MW.Settle()
    MW.CloseAH()
    sale(id, 2550)
    MW.Open()
    MW.Deliver()
    T.eq(Ledger.Range("session").net, -100, "nothing counted until the gold is taken")
    TakeInboxMoney(1)
    MW.Settle()
    local k = kinds(Ledger)
    T.eq(k.sales, 51000); T.eq(k.cuts, -2550); T.eq(k.deposits, 0, "the deposit came back")
    T.eq(Ledger.Range("session").net, 51000 - 2550)
    local it = Ledger.Range("session").items[1]
    T.eq(it.name, "Heavy Leather"); T.eq(it.sold, 51000 - 2550, "what you keep: less the cut"); T.eq(it.soldN, 20)
end)

T.test("ledger: gold from a player's letter; Collect all style loot of several letters", function()
    local Ledger = load({ money = 0, letters = {
        { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 },
        { sender = "Mira Dawnsong", subject = "Thanks", money = 700 } } })
    MW.Open()
    AutoLootMailItem(1)
    MW.Settle()
    -- Emptied with no text: the first letter is gone and the second moves up.
    AutoLootMailItem(1)
    MW.Settle()
    T.eq(kinds(Ledger).players, 15700)
    T.eq(Ledger.Recent()[2].who, "Brannoc Ironhide")
end)

T.test("ledger: a send is postage and the gold you put in it", function()
    local Ledger = load({ money = 10000 })
    MW.Open()
    MW.Cursor({ name = "Linen Cloth", itemID = 2589, count = 20 })
    ClickSendMailItemButton(1)
    SetSendMailMoney(500)
    SendMail("Shooty McGoovy", "Cloth", "")
    MW.Settle()
    local k = kinds(Ledger)
    T.eq(k.postage, -30); T.eq(k.sent, -500)
    T.eq(Ledger.Recent()[1].who, "Shooty McGoovy")
end)

T.test("ledger: cash on delivery paid", function()
    local Ledger = load({ money = 100000, letters = { { sender = "Ysella Brightwind", subject = "Runecloth", cod = 60000,
        items = { { name = "Runecloth", itemID = 14047, count = 20 } } } } })
    MW.Open()
    TakeInboxItem(1, 1)
    MW.Settle()
    T.eq(kinds(Ledger).cod, -60000)
end)

T.test("ledger: a won letter checks a buy seen live; a won bid seen only by letter counts once", function()
    local Ledger = load({ money = 100000 })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Linen Cloth", itemID = 2589, count = 20, unit = 10 })
    MW.Settle()
    MW.CloseAH()
    -- An auction won while away. The gold left at bid time, only the letter tells.
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction won: Feral Blade",
        items = { { name = "Feral Blade", itemID = 1726, count = 1 } },
        invoice = { type = "buyer", item = "Feral Blade", bid = 30000, buyout = 0, deposit = 0, cut = 0, count = 1 } })
    MW.Open()
    MW.Deliver()
    MW.Leave()
    MW.Open()   -- seen again on the next visit
    T.eq(kinds(Ledger).buys, -(200 + 30000))
    T.eq(#Ledger.Recent(), 2)
end)

T.test("ledger: a buy's won letter read hours later still only checks it (no second buy)", function()
    local Ledger = load({ money = 100000 })
    MW.OpenAH()
    MW.BuyCommodity({ name = "Linen Cloth", itemID = 2589, count = 20, unit = 10 })
    MW.Settle()
    MW.CloseAH()
    stub.Advance(3 * 3600)
    MW.Open()
    MW.Deliver()
    T.eq(kinds(Ledger).buys, -200, "booked once")
    T.eq(#Ledger.Recent(), 1)
end)

-- The client counts a letter's days left on its own clock, so two reads a moment
-- apart can land a second either side of an hour. The same won letter must still
-- be booked once.
T.test("ledger: a won letter whose days left read across an hour is still booked once", function()
    local Ledger = load({ money = 100000 })
    stub.SetTime(1700002800)   -- an exact hour; 30 days are whole hours too
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction won: Feral Blade", days = 30 - 0.4 / 86400,
        items = { { name = "Feral Blade", itemID = 1726, count = 1 } },
        invoice = { type = "buyer", item = "Feral Blade", bid = 30000, buyout = 0, deposit = 0, cut = 0, count = 1 } })
    MW.Open()
    MW.Deliver()
    MW.Leave()
    MW.Inbox()[1].days = 30 + 0.4 / 86400
    MW.Open()
    T.eq(kinds(Ledger).buys, -30000, "booked once")
    T.eq(#Ledger.Recent(), 1)
end)

-- Older saved data kept a won letter's end, to the hour, inside its key. It is
-- converted at login so that letter isn't booked again.
T.test("ledger: an old saved won letter is still seen after the update; ended ones go", function()
    local Ledger = load({ money = 100000 })
    stub.SetTime(1700002800)
    local d = Ledger.Data()
    local hour = math.floor((time() + 30 * 86400) / 3600)
    d.seen = { ["Alliance Auction House|Auction won: Feral Blade|" .. hour .. "|buyer|Feral Blade|30000|1"] = time() + 31 * 86400,
        ["Old|Gone|5|buyer|X|1|1"] = time() - 1 }
    Ledger.Trim(d)
    T.eq(#d.seen["Alliance Auction House|Auction won: Feral Blade|buyer|Feral Blade|30000|1"], 1)
    T.falsy(d.seen["Old|Gone|buyer|X|1|1"])
    MW.Arrive({ sender = "Alliance Auction House", subject = "Auction won: Feral Blade",
        items = { { name = "Feral Blade", itemID = 1726, count = 1 } },
        invoice = { type = "buyer", item = "Feral Blade", bid = 30000, buyout = 0, deposit = 0, cut = 0, count = 1 } })
    MW.Open()
    MW.Deliver()
    T.eq(kinds(Ledger).buys, 0, "seen before the update: not booked again")
end)

T.test("ledger: kept per character, by day; ranges add up", function()
    local Ledger = load({ money = 0, letters = { { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 } } })
    MW.Open()
    TakeInboxMoney(1)
    MW.Settle()
    local saved = DaylightUI.DB.Character().ledger
    T.eq(type(saved.days), "table")
    stub.Advance(3 * 86400)
    T.eq(Ledger.Range("week").net, 15000, "three days later, still in the week")
    stub.Advance(10 * 86400)
    T.eq(Ledger.Range("week").net, 0)
    T.eq(Ledger.Range("month").net, 15000)
    T.eq(Ledger.Range("all").net, 15000)
    T.eq(#Ledger.Range("week").days, 7, "one total per day")
end)

-- Two gold letters with the same key (from an alt, minutes apart). When the
-- newer, bigger one vanishes in one read (another addon's open-all), that one is
-- booked as gone, not its neighbor.
T.test("ledger: of two same letters, the one taken is the one booked (whatever their order)", function()
    local Ledger = load({ money = 0, letters = {
        { sender = "Brannoc Ironhide", subject = "Gold", money = 10000 },
        { sender = "Brannoc Ironhide", subject = "Gold", money = 5000, days = 30 - 300 / 86400 } } })
    MW.Open()
    MW.state.money = 10000   -- gold first, then the inbox, since the order isn't guaranteed
    stub.FireEvent("PLAYER_MONEY")
    table.remove(MW.Inbox(), 1)
    stub.FireEvent("MAIL_INBOX_UPDATE")
    T.eq(kinds(Ledger).players, 10000)
    T.eq(#Ledger.Recent(), 1)
end)

-- Once a won letter is taken it's gone. A second identical won auction (same item,
-- bid, count) arriving minutes later is a new buy, not the old one.
T.test("ledger: a second same won auction after the first was taken is booked too", function()
    local Ledger = load({ money = 100000 })
    local function won()
        MW.Arrive({ sender = "Alliance Auction House", subject = "Auction won: Feral Blade",
            items = { { name = "Feral Blade", itemID = 1726, count = 1 } },
            invoice = { type = "buyer", item = "Feral Blade", bid = 30000, buyout = 0, deposit = 0, cut = 0, count = 1 } })
    end
    won()
    MW.Open()
    MW.Deliver()
    T.eq(kinds(Ledger).buys, -30000)
    table.remove(MW.Inbox(), 1)   -- taken
    stub.FireEvent("MAIL_INBOX_UPDATE")
    stub.Advance(600)
    won()
    MW.Deliver()
    MW.Leave()
    MW.Open()   -- seen again on the next visit, still two
    T.eq(kinds(Ledger).buys, -60000, "two wins")
    T.eq(#Ledger.Recent(), 2)
end)

-- Past 50 letters the client shows only the first 50. New mail pushes the oldest
-- out of view until a letter goes. A won letter pushed out isn't taken, so it's
-- still the same buy when it comes back.
T.test("ledger: a won letter pushed out of view by new mail and back is still booked once", function()
    local letters = {}
    for i = 1, 49 do letters[i] = { sender = "Brannoc Ironhide", subject = "Hello " .. i } end
    letters[50] = { sender = "Alliance Auction House", subject = "Auction won: Feral Blade",
        items = { { name = "Feral Blade", itemID = 1726, count = 1 } },
        invoice = { type = "buyer", item = "Feral Blade", bid = 30000, buyout = 0, deposit = 0, cut = 0, count = 1 } }
    local Ledger = load({ money = 100000, letters = letters, beyond = 1 })
    MW.Open()
    T.eq(kinds(Ledger).buys, -30000)
    -- New mail on top: the won letter drops out of view.
    local pushed = table.remove(MW.Inbox(), 50)
    table.insert(MW.Inbox(), 1, MW.Letter({ sender = "Brannoc Ironhide", subject = "New" }))
    MW.state.beyond = 2
    stub.FireEvent("MAIL_INBOX_UPDATE")
    -- A letter goes: the won letter is back in view.
    table.remove(MW.Inbox(), 1)
    table.insert(MW.Inbox(), pushed)
    MW.state.beyond = 1
    stub.FireEvent("MAIL_INBOX_UPDATE")
    T.eq(kinds(Ledger).buys, -30000, "booked once")
    T.eq(#Ledger.Recent(), 1)
end)

-- An item the client hadn't loaded when first asked for by name. Once its info
-- arrives (GET_ITEM_INFO_RECEIVED) the next lookup finds it and the page repaints
-- for its icon.
T.test("ledger: an item name not cached at first is found once the client loads it", function()
    local Ledger = load({ money = 100 })
    T.eq(Ledger.ItemID("Heavy Leather"), nil)
    MW.state.cached = { ["Heavy Leather"] = 4234 }
    T.eq(Ledger.ItemID("Heavy Leather"), nil, "the miss is kept between asks")
    local painted = 0
    DaylightUI.On("MailLedger", function() painted = painted + 1 end)
    stub.FireEvent("GET_ITEM_INFO_RECEIVED", 4234, true)
    stub.RunTimers()
    T.eq(Ledger.ItemID("Heavy Leather"), 4234)
    T.truthy(painted > 0, "the page paints again")
end)
