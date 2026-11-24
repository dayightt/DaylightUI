local AHW = require("ahworld")
local stub = require("stub")

-- The Sell tab (DaylightUI_AuctionHouse/SellPage.lua) on the fake Auction
-- House with real bags: the bag items under the game's item classes, each
-- searched once a visit; a pick fills the cheapest price, or under it by the
-- undercut setting (copper for a commodity, whole silver for gear); Post (the
-- button or the key)
-- sends it in the click and picks the next; refusals and the game's price
-- warning say what to do.

local LINEN, WOOL, POTION, SWORD, PATTERN, COPPER = 2589, 2592, 118, 2207, 2598, 2840
local RKEY = "US-PvE"
local G = 10000

local CLASSES = { [0] = "Consumable", [2] = "Weapon", [7] = "Trade Goods", [9] = "Recipe" }

-- The game's AuctionHouseFrame, loaded and shown by the interaction manager
-- as the game does (tests/test_ah_window.lua has the long story).
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

local function spec(extra)
    local s = {
        commodities = { [LINEN] = true, [WOOL] = true, [POTION] = true, [COPPER] = true },
        auctions = {
            { itemID = LINEN, name = "Linen Cloth", count = 200, buyout = 200 * 10, classID = 7 },
            { itemID = WOOL, name = "Wool Cloth", count = 45, buyout = 45 * 32, classID = 7 },
            { itemID = POTION, name = "Minor Healing Potion", count = 10, buyout = 10 * 12, classID = 0 },
            { itemID = SWORD, name = "Ridge Cleaver", count = 1, buyout = 2 * G + 500, classID = 2, quality = 2 },
        },
        items = {
            [PATTERN] = { name = "Pattern: Red Linen Robe", classID = 9 },
            [COPPER] = { name = "Copper Bar", classID = 7 },
        },
        bags = {
            [0] = {
                { itemID = LINEN, stackCount = 20, name = "Linen Cloth" },
                { itemID = WOOL, stackCount = 14, name = "Wool Cloth" },
                { itemID = POTION, stackCount = 6, name = "Minor Healing Potion" },
                { itemID = SWORD, stackCount = 1, name = "Ridge Cleaver" },
                { itemID = PATTERN, stackCount = 1 },
            },
        },
    }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

-- usual: key -> copper, five days of lows (the usual price).
-- Most of these tests post a copper under the cheapest, so the price they
-- check differs from the cheapest. Pass asShipped = true for the real default.
local function load(extra, usual, asShipped)
    local DUI, A = AHW.Load(spec(extra), {
        before = function()
            _G.AuctionHouseFrame = nil
            gameAH()
            C_Item.GetItemClassInfo = function(id) return CLASSES[id] end
        end,
    })
    A.Replicate.SETTLE, A.Replicate.EMPTY_WAIT = 0, 0
    if not asShipped then DaylightUI:Set("AuctionHouse", "undercut", 1) end
    local now = A.Game.Now()
    usual = usual or { [LINEN] = 10, [WOOL] = 34, [POTION] = 13, [SWORD] = 2 * G }
    for id, c in pairs(usual) do
        for d = 0, 4 do A.Store.Record(RKEY, tostring(id), c, 1, now - d * 86400) end
    end
    for _, id in ipairs({ LINEN, WOOL, POTION, SWORD, PATTERN, COPPER }) do AHW.Cache(id) end
    return A, DUI
end

local function frame(n)
    for _ = 1, n or 1 do
        AHW.Frame()
        DaylightUI.Win.Followers.Tick()
    end
end

-- At the Auction House, on Sell, every price checked.
local function open(A)
    AHW.Open()
    frame(3)
    T.truthy(A.Window.IsOpen(), "the window opens at the AH")
    A.Window.ShowTab("sell")
    AHW.Advance(30)   -- the background checks: one a second, quiet after the player's clicks
    return A.Window.frame.pages.sell
end

local function plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T[^|]-coin%-(%a)%a*%.png[^|]*|t", "%1"):gsub("|T.-|t", ""))
end
local function said(page) return plain(page.right.said:GetText()) end
local function why(page) return plain(page.right.why.text:GetText()) end

local function lineOf(page, name)
    for _, b in ipairs(page.left.stack.used) do
        if b.lineSpec and b:IsShown() and plain(b.lineSpec.text) == name then return b end
    end
    error("no line " .. name)
end

local function sections(page)
    local out = {}
    for _, b in ipairs(page.left.stack.used) do
        if b.isSection and b:IsShown() then out[#out + 1] = b end
    end
    return out
end

-- Types into a box as the player would.
local function typeIn(box, text)
    box:SetFocus()
    box:SetText(text)
    box:GetScript("OnTextChanged")(box, true)
end

-- How far down the card a text's top sits, and its height (the fake game has no
-- layout, so this reads the anchors: every line hangs from the card's top).
local function span(fs, box)
    local point, rel, relPoint, _, y = fs:GetPoint(1)
    T.eq(rel, box)
    local _, h = fs:GetFont()
    local top = -y - ((point:find("^BOTTOM") and h) or 0)
    T.truthy(relPoint:find("^TOP"), relPoint)
    return top, top + h
end

T.test("sell: what a sale brings sits under its label, so a sale worth gold never covers it", function()
    local A = load()
    local page = open(A)
    lineOf(page, "Linen Cloth"):Click()
    AHW.Settle()
    typeIn(page.right.form.price, "4g 99s 99c")
    AHW.Settle()
    local box = page.right.box
    T.eq(plain(box.get:GetText()), "94g 99s 81c")
    local _, labelEnd = span(box.get.label, box)
    local top, bottom = span(box.get, box)
    T.truthy(top >= labelEnd, "the amount shares a line with \"You get when it sells\": " .. top .. " < " .. labelEnd)
    local postTop = -select(5, box.post:GetPoint(1))
    T.truthy(bottom <= postTop, "the amount runs into Post")
    T.truthy(postTop + 30 <= -select(5, box.key:GetPoint(1)), "Post runs into the key line")
    T.truthy(-select(5, box.key:GetPoint(1)) + DaylightUI.Style.SIZE.small <= A.SellPage.BOX_H, "the key line leaves the card")
end)

local function quiet()
    AHW.Settle()
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end

T.test("sell: bag items under the game's classes, each searched and priced", function()
    local A = load()
    local page = open(A)
    T.eq(AHW.Calls("SendSearchQuery") + AHW.Calls("SendSellSearchQuery"), 5, "every sellable item searched once")
    local heads = {}
    for _, s in ipairs(sections(page)) do heads[#heads + 1] = s.text:GetText() end
    T.deq(heads, { "WEAPON", "CONSUMABLE", "TRADE GOODS", "RECIPE" }, "the Auction House's category order")
    local linen = lineOf(page, "Linen Cloth")
    T.eq(plain(linen.lineSpec.sub), "20 \195\151 9c")
    T.eq(plain(linen.lineSpec.value), "1s 80c", "what the whole stack brings")
    T.eq(plain(lineOf(page, "Wool Cloth").lineSpec.value), "4s 34c")
    local order = A.SellPage.Order("c:7")
    T.eq(order[1].name, "Wool Cloth", "the most valuable first")
    T.eq(order[2].name, "Linen Cloth")
    T.truthy(plain(lineOf(page, "Pattern: Red Linen Robe").lineSpec.sub):find("no price yet: you set it", 1, true))
    T.eq(plain(sections(page)[3].value:GetText()), "6s 14c", "the heading's total")
    T.eq(plain(sections(page)[4].value:GetText()), "no price yet")
    quiet()
end)

T.test("sell: before its search a row shows the saved price and Post waits", function()
    local A = load()
    AHW.Open()
    frame(3)
    A.Window.ShowTab("sell")
    local page = A.Window.frame.pages.sell
    local linen = lineOf(page, "Linen Cloth")
    T.truthy(plain(linen.lineSpec.sub):find("ago", 1, true), plain(linen.lineSpec.sub))
    A.SellPage.Pick("2589", true)
    T.truthy(page.right.box.post.off, "Post waits for the search")
    stub.Key(function() A.SellPage.Post() end)
    T.eq(AHW.Calls("PostCommodity"), 0, "nothing posts on a saved price")
    T.eq(said(page), "Still checking its price. Click again in a moment.")
    AHW.Settle()
    T.eq(page.right.form.price:GetText(), "9c", "the search is back")
    quiet()
end)

T.test("sell: by default a pick fills the cheapest price itself, and says why", function()
    local A = load(nil, nil, true)
    local page = open(A)
    lineOf(page, "Linen Cloth"):Click()
    AHW.Settle()
    local right = page.right
    T.eq(right.form.price:GetText(), "10c", "no undercut: the same as the cheapest")
    T.eq(plain(right.form.hint:GetText()), "the same as the cheapest")
    T.eq(why(page), "10c each: the same as the cheapest one up right now (10c, 200 of them, checked just now).")
    quiet()
end)

T.test("sell: with an undercut set, a pick fills the price under the cheapest", function()
    local A = load()
    local page = open(A)
    lineOf(page, "Linen Cloth"):Click()
    AHW.Settle()
    local right = page.right
    T.eq(right.title:GetText(), "Linen Cloth")
    T.eq(plain(right.meta:GetText()), "20 in your bags  \194\183  usual 10c")
    T.eq(right.form.qty:GetText(), "20")
    T.eq(right.form.price:GetText(), "9c")
    T.eq(plain(right.form.hint:GetText()), "1c under the cheapest")
    T.eq(why(page), "9c each: 1c under the cheapest one up right now (10c, 200 of them, checked just now).")
    T.eq(right.box.post.text:GetText(), "Post 20")
    T.eq(plain(right.box.get:GetText()), "1s 71c", "after the 5% cut")
    T.truthy(plain(right.box.deposit:GetText()) ~= "\226\128\148", "the game's deposit")
    T.eq(#right.ah.rows, 1, "what's up now: one price")
    T.eq(right.ah.rows[1].unit, 10)
    T.eq(#right.days.days, 14, "two weeks of lows")
    T.eq(right.days.days[14].net, 10, "today's low on the right")
    T.eq(plain(right.dayCap:GetText()), "Usual 10c is the middle of these")
    quiet()
end)

T.test("sell: gear goes a whole silver under", function()
    local A = load()
    local page = open(A)
    A.SellPage.Pick("2207", true)
    AHW.Settle()
    local right = page.right
    T.eq(right.form.price:GetText(), "2g 4s", "1c under 2g 5s lands on 2g 4s")
    T.eq(plain(right.form.hint:GetText()), "1s under the cheapest")
    right.box.post:Click()
    T.eq(AHW.Log("PostItem")[1][5], 2 * G + 400)
    AHW.Settle()
    T.truthy(said(page):find("Posted 1 Ridge Cleaver at 2g 4s each.", 1, true), said(page))
    quiet()
end)

T.test("sell: Post sends it in the click and picks the next", function()
    local A = load()
    local page = open(A)
    lineOf(page, "Wool Cloth"):Click()
    AHW.Settle()
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostCommodity"), 1)
    local args = AHW.Log("PostCommodity")[1]
    T.eq(args[2], 3, "24 h by default")
    T.eq(args[3], 14)
    T.eq(args[4], 31)
    T.eq(page.right.box.post.text:GetText(), "Posting...")
    AHW.Settle()
    T.eq(said(page), "Posted 14 Wool Cloth at 31c each. Next up: Linen Cloth.")
    T.eq(A.SellPage.picked, "2589", "the next one is picked")
    T.isnil(A.SellPage.Row("2592"), "none of it left in the bags")
    quiet()
end)

T.test("sell: the key posts like the button, and the box names it", function()
    local A = load()
    local page = open(A)
    stub.bindings.DAYLIGHTUI_AH_ACT = { "F" }
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    T.eq(plain(page.right.box.key:GetText()), "or press F")
    stub.Key(DaylightUI.AuctionHouseKey)
    T.eq(AHW.Calls("PostCommodity"), 1, "a key press is the player's")
    AHW.Settle()
    T.truthy(said(page):find("Posted 20 Linen Cloth", 1, true), said(page))
    stub.bindings.DAYLIGHTUI_AH_ACT = nil
    A.SellPage.Paint()
    T.eq(plain(page.right.box.key:GetText()), "", "no key bound: no line")
    quiet()
end)

T.test("sell: Skip picks the next without posting, and remembers the time picked", function()
    local A = load()
    local page = open(A)
    lineOf(page, "Wool Cloth"):Click()
    AHW.Settle()
    page.right.box.skip:Click()
    T.eq(A.SellPage.picked, "2589")
    T.eq(AHW.Calls("PostCommodity"), 0)
    page.right.form.chips[8]:Click()
    T.eq(A.SellPage.Hours(), 8)
    page.right.box.post:Click()
    T.eq(AHW.Log("PostCommodity")[1][2], 2, "8 h is the game's second duration")
    AHW.Settle()
    T.truthy(page.right.form.chips[8].on, "8 h still picked")
    T.eq(A.SellPage.Hours(), 8, "kept for the next post")
    quiet()
end)

T.test("sell: Sell all walks its heading and stops after the last", function()
    local A = load()
    local page = open(A)
    local trade = sections(page)[3]
    trade.action:Click()
    T.eq(A.SellPage.picked, "2592", "the heading's first")
    AHW.Settle()
    page.right.box.post:Click()
    AHW.Settle()
    T.eq(A.SellPage.picked, "2589")
    page.right.box.post:Click()
    AHW.Settle()
    T.truthy(said(page):find("That was the last of Trade Goods.", 1, true), said(page))
    T.isnil(A.SellPage.selling)
    quiet()
end)

T.test("sell: refusals say why in plain words", function()
    local A = load({ postFails = { [LINEN] = AHW.DATABASE_ERROR } })
    local page = open(A)
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    stub.Key(function() A.SellPage.Post() end)
    AHW.Settle()
    T.eq(said(page), "The game said no to that post: Internal auction error.")
    -- a refusal the page has no words for still reads plainly
    local real = A.Post.Send
    A.Post.Send = function() return false, "weird" end
    page.right.box.post:Click()
    A.Post.Send = real
    T.eq(said(page), "Something went wrong posting it.")
    -- the stack left the bags before the event said so
    AHW.Bags()[0][1] = nil
    page.right.box.post:Click()
    T.eq(said(page), "None of it is left in your bags to sell.")
    quiet()
end)

T.test("sell: the game's price warning asks for one more click", function()
    local A = load({ postWarning = { [LINEN] = true } })
    local page = open(A)
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    local post = page.right.box.post
    post:Click()
    AHW.Settle()
    T.eq(post.text:GetText(), "The game asks: click again")
    T.truthy(said(page):find("look again at this price", 1, true), said(page))
    T.eq(AHW.Calls("ConfirmPostCommodity"), 0)
    post:Click()
    T.eq(AHW.Calls("ConfirmPostCommodity"), 1)
    AHW.Settle()
    T.truthy(said(page):find("Posted 20 Linen Cloth", 1, true), said(page))
    quiet()
end)

T.test("sell: a typed price is used; gear's goes up to whole silver first", function()
    local A = load()
    local page = open(A)
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    typeIn(page.right.form.price, "12c")
    T.eq(plain(page.right.form.hint:GetText()), "your own price")
    T.eq(why(page), "12c each: your own price.")
    page.right.box.post:Click()
    T.eq(AHW.Log("PostCommodity")[1][4], 12)
    AHW.Settle()
    A.SellPage.Pick("2207", true)
    AHW.Settle()
    typeIn(page.right.form.price, "1g 99s 99c")
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostItem"), 0, "not posted at a price it didn't show")
    T.truthy(said(page):find("whole silver only for this item: 2g each", 1, true), said(page))
    T.eq(page.right.form.price:GetText(), "2g")
    page.right.box.post:Click()
    T.eq(AHW.Log("PostItem")[1][5], 2 * G)
    AHW.Settle()
    -- a price that doesn't read
    typeIn(page.right.form.price, "lots")
    A.SellPage.Pick("2592", true)   -- a new pick forgets it
    T.eq(page.right.form.price:GetText(), "31c")
    quiet()
end)

T.test("sell: a price that doesn't read is refused", function()
    local A = load()
    local page = open(A)
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    typeIn(page.right.form.price, "5c 2g")
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostCommodity"), 0)
    T.eq(said(page), "Type a price like 1g 20s 5c.")
    quiet()
end)

T.test("sell: your own cheapest isn't undercut, and shows as yours", function()
    local A = load({ auctions = {
        { itemID = LINEN, name = "Linen Cloth", count = 30, buyout = 30 * 8, classID = 7, mine = true },
        { itemID = LINEN, name = "Linen Cloth", count = 200, buyout = 200 * 10, classID = 7 },
    } })
    local page = open(A)
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    T.eq(page.right.form.price:GetText(), "8c")
    T.eq(plain(page.right.form.hint:GetText()), "the cheapest is yours: same price")
    local rows = page.right.ah.rows
    T.eq(#rows, 2)
    T.eq(rows[1].own, 30, "the tag says yours")
    T.eq(rows[2].own, 0)
    quiet()
end)

T.test("sell: no one else selling posts at the usual price; neither asks for one", function()
    local A = load({ bags = { [0] = {
        { itemID = COPPER, stackCount = 5, name = "Copper Bar" },
        { itemID = PATTERN, stackCount = 1 },
    } } }, { [COPPER] = 18 })
    local page = open(A)
    local copper = lineOf(page, "Copper Bar")
    T.eq(plain(copper.lineSpec.sub), "5 \195\151 18c  \194\183  no one else selling")
    A.SellPage.Pick("2840", true)
    AHW.Settle()
    T.eq(page.right.form.price:GetText(), "18c")
    T.eq(plain(page.right.form.hint:GetText()), "no one else selling: usual price")
    A.SellPage.Pick("2598", true)
    AHW.Settle()
    T.eq(page.right.form.price:GetText(), "")
    T.eq(plain(page.right.form.hint:GetText()), "no price yet: you set it")
    T.truthy(page.right.box.post.off, "no price: Post waits for one")
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostItem") + AHW.Calls("PostCommodity"), 0)
    quiet()
end)

T.test("sell: far under the usual price still posts, in the warning color", function()
    local A = load(nil, { [LINEN] = 40 })
    local page = open(A)
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    T.eq(page.right.form.price:GetText(), "9c")
    T.eq(plain(page.right.form.hint:GetText()), "under half the usual price")
    local r, g, b = page.right.form.hint:GetTextColor()
    local warn = DaylightUI.Style.INK.WARN
    T.deq({ r, g, b }, { warn[1], warn[2], warn[3] })
    T.truthy(why(page):find("That's under half the usual price (40c).", 1, true), why(page))
    quiet()
end)

T.test("sell: a bag change keeps the pick", function()
    local A = load()
    local page = open(A)
    A.SellPage.Pick("2592", true)
    AHW.Settle()
    AHW.Bags()[0][1].stackCount = 10
    stub.FireEvent("BAG_UPDATE_DELAYED")
    AHW.Frame()
    T.eq(A.SellPage.picked, "2592")
    T.eq(plain(lineOf(page, "Linen Cloth").lineSpec.sub), "10 \195\151 9c")
    quiet()
end)

T.test("sell: money in the price box reads and writes", function()
    local A = load()
    local P = A.SellPage
    T.eq(P.ReadMoney("1g 20s 5c"), 12005)
    T.eq(P.ReadMoney("2g4s"), 20400)
    T.eq(P.ReadMoney("9c"), 9)
    T.isnil(P.ReadMoney("12"), "a bare number has no coin")
    T.isnil(P.ReadMoney("5c 2g"), "out of order")
    T.eq(P.PlainMoney(20400), "2g 4s")
    T.eq(P.PlainMoney(0), "0c")
end)

-- A Chinese client's coins are 金 银 铜, typed through the input method: a
-- number after a coin is the next coin down, and a bare number is in the coin
-- the box suggested, so a price never needs a coin word at its end.
T.test("sell: a price reads without typing a coin word, in any language", function()
    local A = load()
    local P = A.SellPage
    local saved = { GOLD_AMOUNT_SYMBOL, SILVER_AMOUNT_SYMBOL, COPPER_AMOUNT_SYMBOL }
    GOLD_AMOUNT_SYMBOL, SILVER_AMOUNT_SYMBOL, COPPER_AMOUNT_SYMBOL = "\233\135\145", "\233\147\182", "\233\147\156"
    local read = {}
    for i, text in ipairs({ "27\233\147\182", "1\233\135\14520", "27\233\147\1825" }) do read[i] = P.ReadMoney(text) end
    -- put the English coins back before any check can stop the test
    GOLD_AMOUNT_SYMBOL, SILVER_AMOUNT_SYMBOL, COPPER_AMOUNT_SYMBOL = saved[1], saved[2], saved[3]
    T.eq(read[1], 2700, "27 silver in the client's own coin word")
    T.eq(read[2], 12000, "1 gold 20: the 20 is silver")
    T.eq(read[3], 2705, "27 silver 5: the 5 is copper")
    T.eq(P.ReadMoney("1g 20"), 12000, "the same with the letters every client takes")
    T.isnil(P.ReadMoney("5c3"), "nothing comes after copper")
    T.eq(P.ReadMoney("26", 100), 2600, "a bare number in the coin the box suggested")
    T.isnil(P.ReadMoney("26"), "and with no suggestion it isn't a price")
    -- In the window: the sword suggests 2g 4s, the player types a plain 3.
    local page = open(A)
    P.Pick("2207", true)
    AHW.Settle()
    typeIn(page.right.form.price, "3")
    T.falsy(said(page) ~= nil and said(page):find("Type a price", 1, true), "read, not refused")
    page.right.box.post:Click()
    T.eq(AHW.Log("PostItem")[1][5], 3 * G, "posted at 3 gold: the gear's suggested price is in gold")
    AHW.Settle()
    quiet()
end)

T.test("sell: gear takes a starting bid, stackable goods don't", function()
    local A = load()
    local page = open(A)
    local form = page.right.form
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    for _ = 1, 12 do
        local d = DaylightUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 0.1) end
    end
    T.falsy(form.bid:IsShown(), "no bids on stackable goods")
    T.eq(plain(form.bidHint:GetText()), "Stackable goods sell at their price only")
    A.SellPage.Pick("2207", true)
    AHW.Settle()
    T.truthy(form.bid:IsShown())
    T.eq(plain(form.bidHint:GetText()), "optional: buyout only")
    typeIn(form.bid, "3g")
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostItem"), 0, "a bid over the price isn't sent")
    T.eq(said(page), "The starting bid has to be under the price.")
    typeIn(form.bid, "1g 50s 50c")
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostItem"), 0, "shown on the silver step first")
    T.eq(form.bid:GetText(), "1g 51s")
    page.right.box.post:Click()
    local args = AHW.Log("PostItem")[1]
    T.eq(args[4], 15100, "the starting bid")
    T.eq(args[5], 2 * G + 400, "the price")
    AHW.Settle()
    quiet()
end)

T.test("sell: a click on a listing takes its price", function()
    local A = load()
    local page = open(A)
    A.SellPage.Pick("2592", true)
    AHW.Settle()
    local t = page.right.ah
    t.view:SetSize(300, 200)   -- the fake game doesn't lay frames out from their anchors
    t:Layout()
    T.eq(#t.rows, 1)
    t:Row(1):Click()
    T.eq(page.right.form.price:GetText(), "32c", "the listing's own price")
    page.right.box.post:Click()
    T.eq(AHW.Log("PostCommodity")[1][4], 32)
    AHW.Settle()
    quiet()
end)

T.test("sell: a right click on a bag item puts it on Sell", function()
    local A = load()
    open(A)
    A.Window.ShowTab("buy")
    T.truthy(DaylightUI.AuctionHouseSell(0, 4), "the sword")
    T.eq(A.Window.frame.tab, "sell")
    T.eq(A.SellPage.picked, "2207")
    T.falsy(DaylightUI.AuctionHouseSell(0, 9), "an empty slot")
    AHW.Close()
    frame(3)
    T.falsy(DaylightUI.AuctionHouseSell(0, 1), "nothing once the Auction House is closed")
    quiet()
end)

T.test("sell: the bag click setting picks which click puts an item on Sell", function()
    local A = load()
    open(A)
    local function from(click)
        A.Window.ShowTab("buy")
        return DaylightUI.AuctionHouseSell(0, 4, click)
    end
    T.truthy(from("right"), "right-click by default")
    T.truthy(from("alt"), "Alt-click by default too")
    T.eq(A.Window.frame.tab, "sell")
    DaylightUI:Set("AuctionHouse", "bagClick", "alt")
    T.falsy(from("right"), "Alt-click only: a right click is left to the game")
    T.eq(A.Window.frame.tab, "buy", "and stays on Buy")
    T.truthy(from("alt"))
    DaylightUI:Set("AuctionHouse", "bagClick", "right")
    T.falsy(from("alt"), "right-click only")
    T.truthy(from("right"))
    quiet()
end)

T.test("sell: undercut by a percent, when set", function()
    local A = load()
    local page = open(A)
    DaylightUI:Set("AuctionHouse", "undercutPct", 0.1)
    A.SellPage.Pick("2592", true)   -- Wool Cloth, the cheapest at 32c
    AHW.Settle()
    T.eq(page.right.form.price:GetText(), "29c", "10% under 32c, a copper rounded down")
    quiet()
end)

T.test("sell: the amount posted comes back next time, and a chat line says it", function()
    local A = load()
    local page = open(A)
    DaylightUI:Set("AuctionHouse", "chatPosts", true)
    A.SellPage.Pick("2589", true)   -- 20 Linen Cloth
    AHW.Settle()
    typeIn(page.right.form.qty, "5")
    page.right.box.post:Click()
    AHW.Settle()
    local said = false
    for _, m in ipairs(stub.chat) do if plain(m):find("Posted 5", 1, true) then said = true end end
    T.truthy(said, "a chat line: " .. table.concat(stub.chat, " | "))
    A.SellPage.Pick("2589", true)
    AHW.Settle()
    T.eq(page.right.form.qty:GetText(), "5", "5 again, not all 15 left")
    quiet()
end)

T.test("sell: a right-click pins an item on top or hides it at the bottom", function()
    local A = load()
    local page = open(A)
    local P = A.SellPage
    local function names()
        local out = {}
        for _, b in ipairs(page.left.stack.used) do
            if b:IsShown() and b.isSection then out[#out + 1] = "#" .. plain(b.spec and b.spec.text or "") end
            if b:IsShown() and b.lineSpec then out[#out + 1] = plain(b.lineSpec.text) end
        end
        return out
    end
    lineOf(page, "Minor Healing Potion"):Click("RightButton")
    DaylightUI.Widgets.MenuRow(1):Click()   -- Pin to the top
    T.eq(P.Order()[1].key, "118", "pinned first")
    lineOf(page, "Linen Cloth"):Click("RightButton")
    DaylightUI.Widgets.MenuRow(2):Click()   -- Hide from the list
    local order = {}
    for _, r in ipairs(P.Order()) do order[#order + 1] = r.key end
    T.falsy(table.concat(order, ","):find("2589", 1, true), "hidden: not in the order Post walks")
    T.truthy(P.IsHidden("2589"))
    T.truthy(lineOf(page, "Linen Cloth"), "still in the list, at the bottom, to bring back")
    for _ = 1, 12 do   -- the menu fades shut before the next right-click opens it again
        local d = DaylightUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 0.1) end
    end
    lineOf(page, "Linen Cloth"):Click("RightButton")
    DaylightUI.Widgets.MenuRow(2):Click()   -- Show in the list again
    T.falsy(P.IsHidden("2589"))
    quiet()
end)

T.test("sell: a price check reads only the first page", function()
    local auctions = {}
    for i = 1, 6 do auctions[#auctions + 1] = { itemID = LINEN, name = "Linen Cloth", count = 10, buyout = 10 * (10 + i), classID = 7 } end
    local A = load({ page = 2, auctions = auctions })
    open(A)
    T.eq(AHW.Calls("RequestMoreCommoditySearchResults"), 0, "the cheapest is on the first page")
    T.eq(A.SellPage.Row("2589").d.unit, 10, "a copper under the cheapest")
    quiet()
end)

T.test("sell: one silly-low listing asks before it drags a post down", function()
    local A = load({ auctions = {
        { itemID = LINEN, name = "Linen Cloth", count = 1, buyout = 1, classID = 7 },
        { itemID = LINEN, name = "Linen Cloth", count = 200, buyout = 200 * 10, classID = 7 },
        { itemID = WOOL, name = "Wool Cloth", count = 45, buyout = 45 * 32, classID = 7 },
    } })
    local page = open(A)
    lineOf(page, "Linen Cloth"):Click()
    AHW.Settle()
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostCommodity"), 0, "asked first")
    T.truthy(said(page):find("far under what most others ask", 1, true), said(page))
    T.eq(page.right.box.post.text:GetText(), "Post anyway")
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostCommodity"), 1, "the second click posts it")
    quiet()
end)

T.test("sell: under what a vendor pays asks first", function()
    local A = load({ auctions = {
        { itemID = LINEN, name = "Linen Cloth", count = 200, buyout = 200 * 10, classID = 7 },
        { itemID = POTION, name = "Minor Healing Potion", count = 10, buyout = 10 * 12, classID = 0, vendorSell = 50 },
    } })
    local page = open(A)
    lineOf(page, "Minor Healing Potion"):Click()
    AHW.Settle()
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostCommodity"), 0)
    T.truthy(said(page):find("A vendor pays more", 1, true), said(page))
    page.right.box.post:Click()
    T.eq(AHW.Calls("PostCommodity"), 1)
    quiet()
end)

T.test("sell: Post rests while the Auction House answers something else", function()
    local A = load()
    local page = open(A)
    lineOf(page, "Wool Cloth"):Click()
    AHW.Settle()
    T.falsy(page.right.box.post.off)
    A.Post.Owned(function() end)
    T.truthy(page.right.box.post.off, "a click now would be refused")
    AHW.Settle()
    T.falsy(page.right.box.post.off, "free again")
    quiet()
end)

-- On a controller the boxes are stepped with the D-pad, never typed: A picks
-- one up, left and right change it, and X posts.
T.test("sell: on a controller the D-pad steps the amount and price, and X posts", function()
    local A, DUI = load()
    local page = open(A)
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    A.SellPage.Pick("2592", true)
    AHW.Settle()
    local form = page.right.form
    local function press(box, dir)
        box.OnSmartNavSelect()
        box.OnSmartNavClick()   -- A picks it up
        T.truthy(stub.overrides.PADDRIGHT, "left and right taken while it's up")
        local b = _G[stub.overrides[dir > 0 and "PADDRIGHT" or "PADDLEFT"].click]
        b:GetScript("OnClick")(b, "LeftButton", true)
        b:GetScript("OnClick")(b, "LeftButton", false)
        box.OnSmartNavClick()   -- A puts it down
        T.eq(stub.overrides.PADDRIGHT, nil, "put down")
        box.OnSmartNavDeselect()
    end
    press(form.qty, -1)
    T.eq(form.qty:GetText(), "13", "one fewer")
    press(form.price, 1)
    T.eq(form.price:GetText(), "32c", "a copper price steps by a copper")
    -- a gold price lands on round amounts
    T.eq(A.SellPage.StepMoney(12 * G + 3400, 1), 13 * G)
    T.eq(A.SellPage.StepMoney(12 * G + 3400, -1), 12 * G)
    T.eq(A.SellPage.StepMoney(155, -1, 1), 150)
    T.eq(A.SellPage.StepMoney(1, -1, 1), 1, "never under the lowest")
    local x
    for _, e in ipairs(DUI.Pad.Entries(A.Window.frame)) do
        if e.key == "X" and (not e.when or e.when()) then x = e; break end
    end
    T.truthy(x, "X acts on Sell")
    T.eq(x.label(), page.right.box.post.text:GetText())
    stub.Key(x.run)   -- the controller's button press is the player's
    local args = AHW.Log("PostCommodity")[1]
    T.truthy(args, "X posted")
    T.eq(args[3], 13)
    _G.GamepadMode, _G.InputUtil = nil, nil
    quiet()
end)

T.test("sell: hovering the picked item's name shows its tooltip", function()
    local A = load()
    local page = open(A)
    lineOf(page, "Linen Cloth"):Click()
    AHW.Settle()
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner = o end
    function tip:IsOwned(o) return self.__owner == o end
    local head = page.right.head
    head:GetScript("OnEnter")(head)
    T.truthy(tip:IsShown(), "the item's tooltip")
    T.truthy(tip:IsOwned(head))
    head:GetScript("OnLeave")(head)
    T.falsy(tip:IsShown(), "gone when the mouse leaves")
    quiet()
end)
