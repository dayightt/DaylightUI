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
    local _, A = AHW.Load({ auctions = opts.auctions or AUCTIONS, commodities = commodities }, {
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
    T.eq(AHW.Calls("QueryOwnedAuctions"), 0, "opening the AH reads nothing")
    A.Window.ShowTab("auctions")
    A.Window.ShowTab("buy")
    AHW.Advance(30)
    T.eq(AHW.Calls("QueryOwnedAuctions"), 1)
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
