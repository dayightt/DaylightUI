local AHW = require("ahworld")
local stub = require("stub")

-- The My auctions tab (DaylightUI_AuctionHouse/AuctionsPage.lua) on the fake
-- AH: your auctions read when the tab shows, sold ones too, each item still up
-- searched once for the cheapest other seller, undercut ones first, the
-- filters, the picked row's why, and one click (or the key) per cancel, on
-- the picked row only.

local LINEN, SILK, FELCLOTH, BOLT, ICECAP, SWORD = 2589, 4306, 14256, 2996, 13467, 2207

local AUCTIONS = {
    -- undercut by 5c
    { itemID = LINEN, name = "Linen Cloth", count = 60, buyout = 60 * 105, mine = true },
    { itemID = LINEN, name = "Linen Cloth", count = 40, buyout = 40 * 100 },
    -- undercut by 10c
    { itemID = SILK, name = "Silk Cloth", count = 20, buyout = 20 * 50, mine = true },
    { itemID = SILK, name = "Silk Cloth", count = 200, buyout = 200 * 40 },
    -- you're the lowest
    { itemID = FELCLOTH, name = "Felcloth", count = 8, buyout = 8 * 324, mine = true },
    { itemID = FELCLOTH, name = "Felcloth", count = 30, buyout = 30 * 350 },
    -- no one else
    { itemID = BOLT, name = "Bolt of Linen Cloth", count = 20, buyout = 20 * 650, mine = true },
    -- sold
    { itemID = ICECAP, name = "Icecap", count = 10, buyout = 10 * 300, mine = true, sold = true },
    -- a bid on it, and someone under it
    { itemID = SWORD, name = "Ridge Cleaver", count = 1, buyout = 9000, mine = true, bid = 5000, classID = 2 },
    { itemID = SWORD, name = "Ridge Cleaver", count = 1, buyout = 7000, classID = 2 },
}

-- The game's AuctionHouseFrame, loaded and shown the way the game does it
-- (test_ah_window.lua has the long version).
local function gameAH()
    local world = CreateFrame("Frame")
    world:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    world:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    world:SetScript("OnEvent", function(_, event, kind)
        if kind ~= AHW.AUCTIONEER then return end
        local f = rawget(_G, "AuctionHouseFrame")
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            if not f then
                f = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
                f.CloseButton = CreateFrame("Button", nil, f)
                f:Hide()
                f:SetScript("OnHide", function() C_AuctionHouse.CloseAuctionHouse() end)
                stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI")
            end
            f:Show()
        elseif f then
            f:Hide()
        end
    end)
end

-- Tweens run on the shared driver's OnUpdate: run it until they're done.
local function ease()
    for _ = 1, 12 do
        local d = DaylightUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 0.1) end
    end
end

local function settle()
    for _ = 1, 3 do
        AHW.Settle()
        ease()
    end
end

local function load(opts)
    opts = opts or {}
    local commodities = { [LINEN] = true, [SILK] = true, [FELCLOTH] = true, [BOLT] = true, [ICECAP] = true }
    local spec = { auctions = opts.auctions or AUCTIONS, commodities = commodities }
    for k, v in pairs(opts.spec or {}) do spec[k] = v end
    local _, A = AHW.Load(spec, {
        before = function()
            _G.AuctionHouseFrame = nil
            _G.DaylightMogul = nil
            gameAH()
        end,
    })
    stub.bindings["DAYLIGHTUI_AH_ACT"] = opts.key and { opts.key } or nil
    -- Whether the client cancels an auction with a bid isn't known for Forever
    -- (the game's own window offers Cancel on it): these worlds refuse it
    -- unless opts.bidCancels, and the page asks CanCancelAuction either way.
    if not opts.bidCancels then
        local real = C_AuctionHouse.CanCancelAuction
        C_AuctionHouse.CanCancelAuction = function(id)
            for _, o in ipairs(A.Post.Mine() or {}) do
                if o.auctionID == id and (o.bid or 0) > 0 then return false end
            end
            return real(id)
        end
    end
    AHW.Open()
    AHW.Frame()
    DaylightUI.Win.Followers.Tick()
    T.truthy(A.Window.IsOpen(), "the window opens at the AH")
    A.Window.ShowTab("auctions")
    local page = A.Window.frame.pages.auctions
    page.table.view:SetSize(900, 400)
    page.table:Layout()
    AHW.Advance(30)   -- the owned list, then one search a second
    settle()
    return A, page
end

local function plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T[^|]-coin%-(%a)%a*%.png[^|]*|t", "%1"):gsub("|T.-|t", ""))
end

local function rowOf(A, itemID)
    for _, r in ipairs(A.AuctionsPage.Rows()) do if r.itemID == itemID then return r end end
end

local function shownIDs(page)
    local out = {}
    for _, d in ipairs(page.table.rows) do out[#out + 1] = d.kind == "why" and "why" or d.itemID end
    return out
end

local function pickedID(A)
    local r = A.AuctionsPage.picked
    for _, d in ipairs(A.AuctionsPage.Rows()) do if d.auctionID == r then return d.itemID end end
end

local function whyText(page)
    for _, d in ipairs(page.table.rows) do if d.kind == "why" then return plain(d.text) end end
end

-- The table's frame showing an item's row.
local function frameOf(page, itemID)
    for i, d in ipairs(page.table.rows) do
        if d.kind == "line" and d.itemID == itemID then return page.table.shown[i] end
    end
end

local function quiet()
    settle()
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end

T.test("ah auctions: your auctions with their status, undercut ones first", function()
    local A, page = load()
    T.eq(AHW.Calls("QueryOwnedAuctions"), 1)
    T.eq(AHW.Calls("SendSearchQuery") + AHW.Calls("SendSellSearchQuery"), 5, "each item still up searched once, not the sold one")
    T.eq(stub.Text(page.title), "5 auctions up")
    local meta = plain(stub.Text(page.meta))
    T.truthy(meta:find("1 sold", 1, true), meta)
    T.truthy(meta:find("waiting in your mailbox", 1, true), meta)
    T.truthy(meta:find("checked just now", 1, true), meta)
    T.deq(shownIDs(page), { LINEN, "why", SILK, FELCLOTH, SWORD, BOLT, ICECAP })
    T.eq(plain(rowOf(A, LINEN).text), "Undercut by 5c")
    T.eq(rowOf(A, LINEN).role, "WARN")
    T.eq(rowOf(A, LINEN).lowest, 100)
    T.eq(plain(rowOf(A, SILK).text), "Undercut by 10c")
    T.eq(rowOf(A, FELCLOTH).text, "You're the lowest")
    T.eq(rowOf(A, FELCLOTH).lowest, 350)
    T.eq(rowOf(A, BOLT).text, "No one else selling")
    T.isnil(rowOf(A, BOLT).lowest)
    T.eq(rowOf(A, SWORD).text, "Has a bid: can't cancel")
    T.eq(rowOf(A, ICECAP).text, "Sold: in your mailbox")
    T.eq(rowOf(A, ICECAP).role, "GOOD")
    -- what the row frames show
    local b = frameOf(page, LINEN)
    T.truthy(b, "the Linen row is drawn")
    T.eq(stub.Text(b.name), "Linen Cloth")
    T.eq(stub.Text(b.cells.qty), "60")
    T.eq(plain(stub.Text(b.cells.unit)), "1s 05c")
    T.eq(plain(stub.Text(b.cells.lowest)), "1s")
    T.eq(plain(stub.Text(frameOf(page, BOLT).cells.lowest)), "\226\128\148")
    quiet()
end)

T.test("ah auctions: the chips filter, their counts follow", function()
    local A, page = load()
    T.eq(plain(stub.Text(page.chips.all.text)), "All 6")
    T.eq(plain(stub.Text(page.chips.undercut.text)), "Undercut 2")
    T.eq(plain(stub.Text(page.chips.sold.text)), "Sold 1")
    page.chips.sold:Click()
    settle()
    T.deq(shownIDs(page), { ICECAP })
    T.isnil(A.AuctionsPage.picked, "nothing undercut to pick here")
    T.truthy(page.foot.buttons[1].spec.off, "nothing to cancel")
    page.chips.undercut:Click()
    settle()
    T.deq(shownIDs(page), { LINEN, "why", SILK }, "the first undercut one is picked, its why open")
    page.chips.all:Click()
    settle()
    T.eq(#page.table.rows, 7)
    quiet()
end)

T.test("ah auctions: the picked row's why says who undercut it and what a cancel costs", function()
    local A, page = load({ key = "F" })
    T.eq(pickedID(A), LINEN, "the first undercut one is picked for you")
    local why = whyText(page)
    T.truthy(why:find("Someone put up 40 at 1s (checked just now), 5c under yours.", 1, true), why)
    T.truthy(why:find("Cancel it and post again from Sell to be the cheapest.", 1, true), why)
    T.truthy(why:find("the deposit (", 1, true), "a commodity's deposit is known: " .. why)
    T.eq(stub.Text(page.foot.buttons[1].text), "Cancel Linen Cloth")
    T.falsy(page.foot.buttons[1].spec.off)
    T.eq(plain(stub.Text(page.hint)), "or press F")
    -- another row: its why opens under it instead
    frameOf(page, FELCLOTH):Click()
    settle()
    T.eq(pickedID(A), FELCLOTH)
    T.deq(shownIDs(page), { LINEN, SILK, FELCLOTH, "why", SWORD, BOLT, ICECAP })
    T.truthy(whyText(page):find("Yours is the cheapest", 1, true), whyText(page))
    T.eq(stub.Text(page.foot.buttons[1].text), "Cancel Felcloth")
    quiet()
end)

T.test("ah auctions: no key bound, no key hint", function()
    local _, page = load()
    T.eq(stub.Text(page.hint), "")
    quiet()
end)

T.test("ah auctions: Cancel cancels only the picked one, then the next undercut one is picked", function()
    local A, page = load()
    frameOf(page, SILK):Click()
    settle()
    T.eq(pickedID(A), SILK)
    page.foot.buttons[1]:Click()
    T.eq(AHW.Calls("CancelAuction"), 1)
    settle()
    T.deq(AHW.Mailed(), { { itemID = SILK, count = 20 } }, "the Silk it showed, never the Linen")
    T.truthy(plain(stub.Text(page.stat)):find("Canceled 20 Silk Cloth", 1, true), stub.Text(page.stat))
    T.isnil(rowOf(A, SILK), "its row left")
    T.eq(pickedID(A), LINEN, "the next undercut one is picked")
    T.deq(shownIDs(page), { LINEN, "why", FELCLOTH, SWORD, BOLT, ICECAP })
    T.eq(stub.Text(page.title), "4 auctions up")
    quiet()
end)

T.test("ah auctions: the key cancels the picked one like the button", function()
    local A, page = load({ key = "F" })
    stub.Key(DaylightUI.AuctionHouseKey)
    T.eq(AHW.Calls("CancelAuction"), 1)
    settle()
    T.deq(AHW.Mailed(), { { itemID = LINEN, count = 60 } })
    T.eq(pickedID(A), SILK)
    stub.Key(DaylightUI.AuctionHouseKey)
    settle()
    T.eq(AHW.Calls("CancelAuction"), 2, "one per press")
    T.isnil(A.AuctionsPage.picked, "nothing undercut left to pick")
    stub.Key(DaylightUI.AuctionHouseKey)
    T.eq(AHW.Calls("CancelAuction"), 2, "with nothing picked the key cancels nothing")
    T.truthy(page.foot.buttons[1].spec.off)
    quiet()
end)

T.test("ah auctions: an auction with a bid can't be canceled", function()
    local A, page = load({ key = "F" })
    frameOf(page, SWORD):Click()
    settle()
    T.eq(pickedID(A), SWORD)
    T.truthy(page.foot.buttons[1].spec.off, "the button is off")
    T.eq(stub.Text(page.hint), "It has a bid, so it can't be canceled.")
    T.truthy(whyText(page):find("can't be canceled", 1, true), whyText(page))
    page.foot.buttons[1]:Click()
    stub.Key(DaylightUI.AuctionHouseKey)
    A.AuctionsPage.Cancel()
    T.eq(AHW.Calls("CancelAuction"), 0)
    quiet()
end)

T.test("ah auctions: an auction with a bid cancels when the game allows it", function()
    local A, page = load({ bidCancels = true })
    T.truthy(rowOf(A, SWORD).text ~= "Has a bid: can't cancel", rowOf(A, SWORD).text)
    frameOf(page, SWORD):Click()
    settle()
    T.falsy(page.foot.buttons[1].spec.off, "the button is on")
    page.foot.buttons[1]:Click()
    settle()
    T.eq(AHW.Calls("CancelAuction"), 1)
    quiet()
end)

T.test("ah auctions: a sold one shows and can't be canceled", function()
    local A, page = load()
    frameOf(page, ICECAP):Click()
    settle()
    T.eq(pickedID(A), ICECAP)
    T.truthy(page.foot.buttons[1].spec.off)
    T.truthy(whyText(page):find("Sold for 30s", 1, true), whyText(page))
    T.eq(AHW.Calls("CancelAuction"), 0)
    quiet()
end)

T.test("ah auctions: a refused cancel says why in the game's words and keeps the row", function()
    local A, page = load()
    local real = A.Post.Cancel
    local answer
    A.Post.Cancel = function(_, onDone) answer = onDone; return true end
    page.foot.buttons[1]:Click()
    A.Post.Cancel = real
    T.eq(stub.Text(page.foot.buttons[1].text), "Canceling...")
    answer(false, "failed", "Internal auction error")
    T.eq(plain(stub.Text(page.stat)), "The game said no to that cancel: Internal auction error.")
    T.truthy(rowOf(A, LINEN))
    T.eq(stub.Text(page.foot.buttons[1].text), "Cancel Linen Cloth")
    quiet()
end)

T.test("ah auctions: Check again reads the list and the prices again, one search at a time", function()
    local _, page = load()
    local searches = AHW.Calls("SendSearchQuery") + AHW.Calls("SendSellSearchQuery")
    page.again:Click()
    T.eq(AHW.Calls("QueryOwnedAuctions"), 2)
    AHW.Advance(2)
    T.eq(AHW.Calls("SendSearchQuery") + AHW.Calls("SendSellSearchQuery"), searches, "waits while the player is clicking")
    AHW.Advance(30)
    settle()
    T.eq(AHW.Calls("SendSearchQuery") + AHW.Calls("SendSellSearchQuery"), searches + 5)
    quiet()
end)

T.test("ah auctions: nothing is asked until the tab shows, nor while it's hidden", function()
    local _, A = AHW.Load({ auctions = AUCTIONS, commodities = { [LINEN] = true } }, {
        before = function()
            _G.AuctionHouseFrame = nil
            gameAH()
        end,
    })
    AHW.Open()
    AHW.Frame()
    DaylightUI.Win.Followers.Tick()
    AHW.Advance(10)
    T.eq(AHW.Calls("QueryOwnedAuctions"), 1, "opening the AH reads your list once, so the tab shows at once")
    T.eq(AHW.Calls("SendSearchQuery") + AHW.Calls("SendSellSearchQuery"), 0, "and checks no prices")
    A.Window.ShowTab("auctions")
    A.Window.ShowTab("buy")
    AHW.Advance(30)
    T.eq(AHW.Calls("QueryOwnedAuctions"), 1, "the tab uses that read")
    T.eq(AHW.Calls("SendSearchQuery") + AHW.Calls("SendSellSearchQuery"), 0, "no price checks behind another tab")
    quiet()
end)

T.test("ah auctions: idle, nothing runs every frame", function()
    load()
    settle()
    local d = DaylightUI.Motion.Driver()
    T.falsy(d and d:GetScript("OnUpdate"), "no tween left running")
    quiet()
end)

T.test("ah auctions: the columns sort, the current bid has its own", function()
    local A, page = load()
    T.eq(plain(stub.Text(frameOf(page, SWORD).cells.bid)), "50s", "the bid on the sword")
    T.eq(plain(stub.Text(frameOf(page, LINEN).cells.bid)), "\226\128\148", "no bid")
    page.table.head.cells.qty:Click()
    settle()
    T.deq(shownIDs(page), { SWORD, FELCLOTH, ICECAP, SILK, BOLT, LINEN, "why" }, "fewest first")
    page.table.head.cells.qty:Click()
    settle()
    T.eq(page.table.rows[1].itemID, LINEN, "again: most first")
    page.table.head.cells.status:Click()
    settle()
    T.eq(page.table.rows[1].itemID, LINEN, "back to what needs doing")
    quiet()
end)

local AXE, MACE = 2025, 2489

-- Two auctions the player bid on: the highest bid on one, outbid on the other.
local function withBids()
    local list = {}
    for _, a in ipairs(AUCTIONS) do list[#list + 1] = a end
    list[#list + 1] = { itemID = AXE, name = "Bearded Axe", count = 1, buyout = 20000, bid = 3000, myBid = 3000,
        nextBid = 3300, classID = 2, timeLeft = 2 }
    list[#list + 1] = { itemID = MACE, name = "Two-Handed Mace", count = 1, buyout = 0, minBid = 1000, bid = 6000,
        myBid = 5000, outbid = true, nextBid = 6300, classID = 2, timeLeft = 1 }
    return list
end

T.test("ah auctions: Bids lists what you bid on, outbid first, and bids again", function()
    local A, page = load({ auctions = withBids() })
    T.eq(AHW.Calls("QueryBids"), 1, "read with your auctions")
    T.eq(plain(stub.Text(page.chips.all.text)), "All 6", "bids aren't your auctions")
    T.eq(plain(stub.Text(page.chips.bids.text)), "Bids 2")
    page.chips.bids:Click()
    settle()
    T.deq(shownIDs(page), { MACE, AXE })
    T.eq(rowOf(A, MACE).text, "Outbid")
    T.eq(rowOf(A, MACE).role, "WARN")
    T.eq(rowOf(A, AXE).text, "You're the highest bidder")
    T.eq(plain(stub.Text(frameOf(page, AXE).cells.left)), "<12 h")
    T.eq(plain(stub.Text(frameOf(page, AXE).cells.unit)), "2g", "the buyout")
    frameOf(page, MACE):Click()
    settle()
    local why = whyText(page)
    T.truthy(why:find("Bid at least 63s to win it back.", 1, true), why)
    T.eq(stub.Text(page.foot.buttons[1].text), "Bid")
    T.falsy(page.foot.buttons[2] and page.foot.buttons[2]:IsShown(), "no buyout to offer")
    T.truthy(page.bidBox:IsShown())
    T.eq(page.bidBox:GetText(), "63s", "the least next bid")
    page.bidBox:SetText("70s")
    page.foot.buttons[1]:Click()
    settle()
    local log = AHW.Log("PlaceBid")
    T.eq(log[#log][2], 7000, "the typed amount")
    T.truthy(plain(stub.Text(page.stat)):find("Bid 70s on Two-Handed Mace.", 1, true), stub.Text(page.stat))
    T.eq(AHW.Calls("QueryBids"), 2, "read again after the bid")
    quiet()
end)

T.test("ah auctions: a bid under the least is refused, and Buy out buys", function()
    local A, page = load({ auctions = withBids() })
    page.chips.bids:Click()
    settle()
    frameOf(page, AXE):Click()
    settle()
    page.bidBox:SetText("10s")
    page.foot.buttons[1]:Click()
    settle()
    T.eq(AHW.Calls("PlaceBid"), 0, "nothing sent")
    T.truthy(plain(stub.Text(page.stat)):find("Bid at least 33s.", 1, true), stub.Text(page.stat))
    T.eq(plain(stub.Text(page.foot.buttons[2].text)), "Buy out 2g")
    page.foot.buttons[2]:Click()
    settle()
    local log = AHW.Log("PlaceBid")
    T.eq(log[#log][2], 20000, "the buyout")
    quiet()
end)

T.test("ah auctions: a few cheaper ones can pass, and the search box finds one", function()
    local A, page = load()
    DaylightUI:Set("AuctionHouse", "undercutAhead", 50)
    A.AuctionsPage.Paint()
    settle()
    T.eq(rowOf(A, LINEN).text, "40 cheaper, left up", "40 Linen under yours, within 50")
    T.eq(rowOf(A, LINEN).role, "LABEL")
    T.eq(plain(rowOf(A, SILK).text), "Undercut by 10c", "200 Silk under yours is more than 50")
    page.search:SetText("silk")
    page.search:GetScript("OnTextChanged")(page.search, true)
    settle()
    T.deq(shownIDs(page), { SILK, "why" })
    T.eq(plain(stub.Text(page.chips.all.text)), "All 1")
    page.search:SetText("")
    page.search:GetScript("OnTextChanged")(page.search, true)
    settle()
    T.eq(plain(stub.Text(page.chips.all.text)), "All 6")
    quiet()
end)

T.test("ah auctions: a cancel that costs gold asks once, naming the cost", function()
    local A, page = load({ spec = { cancelCost = 2500 } })
    T.eq(pickedID(A), LINEN, "the undercut one is picked")
    page.foot.buttons[1]:Click()
    T.eq(AHW.Calls("CancelAuction"), 0, "asked first")
    T.truthy(plain(stub.Text(page.stat)):find("Canceling it costs", 1, true), plain(stub.Text(page.stat)))
    T.truthy(plain(stub.Text(page.foot.buttons[1].text)):find("Cancel for", 1, true))
    page.foot.buttons[1]:Click()
    T.eq(AHW.Calls("CancelAuction"), 1, "the second click cancels")
    quiet()
end)

T.test("ah auctions: a sale while you look reads the list again by itself", function()
    local A = load({ spec = { saleCancels = true } })
    local reads = AHW.Calls("QueryOwnedAuctions")
    local id
    for _, o in ipairs(A.Post.Mine()) do if o.itemID == SILK then id = o.auctionID end end
    AHW.Sell(id, "Brann")
    AHW.Advance(1)
    settle()
    T.eq(AHW.Calls("QueryOwnedAuctions"), reads + 1, "one read after the sale")
    T.truthy(rowOf(A, SILK).sold, "shown as sold")
    T.eq(AHW.Calls("RequestMoreCommoditySearchResults"), 0, "the checks read one page each")
    quiet()
end)

T.test("ah auctions: Cancel rests while the Auction House answers something else", function()
    local A, page = load()
    T.falsy(page.foot.buttons[1].spec and page.foot.buttons[1].spec.off)
    A.Post.Bids(function() end)
    T.truthy(page.foot.buttons[1].spec.off, "a click now would be refused")
    settle()
    T.falsy(page.foot.buttons[1].spec.off, "free again")
    quiet()
end)
