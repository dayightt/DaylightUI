local AHW = require("ahworld")
local stub = require("stub")

-- Buying (Game/Buy.lua) on the fake auction house: a commodity in two clicks
-- (quote, then confirm), gear and bids in one, the safety net, and what the
-- fake does with a purchase (tests/ahworld.lua header).

local HERB, SWORD, BOW = 2449, 2207, 2208
local RKEY = "US-PvE"
local G, S = 10000, 100   -- a gold and a silver, in copper

local function load(spec)
    spec = spec or {}
    spec.auctions = spec.auctions or {
        { itemID = HERB, count = 30, buyout = 30 * 1 * G },
        { itemID = HERB, count = 30, buyout = 30 * 1.1 * G },
        { itemID = HERB, count = 30, buyout = 30 * 1.2 * G },
        { itemID = SWORD, count = 1, buyout = 5000, owner = "Brann" },
        { itemID = BOW, count = 1, buyout = 0, minBid = 300, owner = "Brann" },
    }
    spec.commodities = spec.commodities or { [HERB] = true }
    local M = AHW.Mog({
        ah = spec,
        before = function()
        end,
    })
    return M
end

-- Records what the addon says about a purchase.
local function watcher()
    local w = { quotes = {}, done = {} }
    w.onQuote = function(unit, total) w.quotes[#w.quotes + 1] = { unit, total } end
    w.onDone = function(ok, why) w.done[#w.done + 1] = { ok, why } end
    return w
end

-- The total of the latest quote the addon told about: what the player is looking at.
local function seen(w)
    local q = w.quotes[#w.quotes]
    return q and q[2]
end

local function click(fn)
    local a, b
    stub.Key(function() a, b = fn() end)
    return a, b
end

local function auctionOf(itemID)
    for _, a in ipairs(AHW.Auctions()) do if a.itemID == itemID then return a end end
end

local function countOf(itemID)
    local n = 0
    for _, a in ipairs(AHW.Auctions()) do if a.itemID == itemID then n = n + a.count end end
    return n
end

local function blockedOn(name)
    for _, e in ipairs(stub.errors) do if e:find(name, 1, true) then return true end end
    return false
end

T.test("commodity_two_clicks", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local ok = click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    T.truthy(ok)
    T.eq(M.Buy.Pending(), "quote")
    T.eq(AHW.Calls("StartCommoditiesPurchase"), 1)
    AHW.Settle()
    T.deq(w.quotes, { { 10500, 63 * G } }, "the 60 cheapest units cost 63g, 10500 each on average")
    T.eq(M.Buy.Pending(), "quote", "the quote waits for the second click")
    T.deq(w.done, {})
    T.falsy(M.AH.Busy(), "nothing in flight while the player looks at the price")
    T.eq(countOf(HERB), 90, "nothing bought yet")
    ok = click(function() return M.Buy.Confirm(seen(w)) end)
    T.truthy(ok)
    T.eq(M.Buy.Pending(), "confirm")
    AHW.Settle()
    T.deq(w.done, { { true } })
    T.isnil(M.Buy.Pending())
    T.eq(countOf(HERB), 30, "the 60 cheapest are gone")
    T.eq(auctionOf(HERB).buyout, 30 * 1.2 * G, "the dearest stack is left")
    T.deq(AHW.Log("ConfirmCommoditiesPurchase"), { { HERB, 60 } })
end)

T.test("commodity_partial_stack", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 40, 11000, w.onQuote, w.onDone) end)
    AHW.Settle()
    T.deq(w.quotes, { { 10250, 30 * G + 10 * 11000 } })
    click(function() return M.Buy.Confirm(seen(w)) end)
    AHW.Settle()
    T.deq(w.done, { { true } })
    T.eq(countOf(HERB), 50)
end)

T.test("start_outside_a_click_is_blocked", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local ok = M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone)   -- no stub.Key: not a click
    T.truthy(ok, "the addon sent it; the client refused it")
    T.truthy(blockedOn("ADDON_ACTION_BLOCKED"), "the client recorded ADDON_ACTION_BLOCKED")
    T.eq(AHW.Waiting(), 0, "nothing went out, so no answer is coming")
    AHW.Advance(M.AH.TIMEOUT + 1)
    T.deq(w.done, { { false, "timeout" } }, "the quote never came: that is all the addon can know")
    T.deq(w.quotes, {})
    T.isnil(M.Buy.Pending())
    T.eq(AHW.Calls("StartCommoditiesPurchase"), 1, "never retried")
    AHW.Advance(60)
    T.eq(AHW.Calls("StartCommoditiesPurchase"), 1, "still never retried")
end)

T.test("confirm_outside_a_click_is_blocked", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    AHW.Settle()
    M.Buy.Confirm(seen(w))
    T.truthy(blockedOn("ConfirmCommoditiesPurchase"))
    AHW.Advance(M.AH.TIMEOUT + 1)
    T.deq(w.done, { { false, "timeout" } })
    T.eq(countOf(HERB), 90, "nothing bought")
    T.isnil(M.Buy.Pending())
end)

T.test("quote_higher", function()
    local M = load({ quoteBump = 5000 })
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    AHW.Settle()
    T.eq(#w.quotes, 1)
    T.eq(w.quotes[1][2], 63 * G + 5000, "the game's quote is higher than the shelf's")
    T.eq(w.quotes[1][1], math.floor((63 * G + 5000) / 60), "the unit is the average, total / qty floored")
    click(function() return M.Buy.Confirm(seen(w)) end)
    AHW.Settle()
    T.deq(w.done, { { true } }, "the player saw it and said yes")
end)

T.test("quote_unavailable", function()
    local M = load({ quoteFails = true })
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    AHW.Settle()
    T.deq(w.done, { { false, "unavailable" } })
    T.deq(w.quotes, {})
    T.isnil(M.Buy.Pending())
    local ok, why = click(function() return M.Buy.Confirm(seen(w)) end)
    T.falsy(ok); T.eq(why, "noquote")
    -- more than the shelf holds is unavailable too
    local M2 = load()
    AHW.Open()
    local w2 = watcher()
    click(function() return M2.Buy.Commodity(HERB, 500, 11000, w2.onQuote, w2.onDone) end)
    AHW.Settle()
    T.deq(w2.done, { { false, "unavailable" } })
end)

T.test("purchase_failed", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    AHW.Settle()
    table.remove(AHW.Auctions(), 1)   -- someone else bought the cheapest stack meanwhile
    click(function() return M.Buy.Confirm(seen(w)) end)
    AHW.Settle()
    T.deq(w.done, { { false, "failed" } })
    T.isnil(M.Buy.Pending())
    T.eq(countOf(HERB), 60, "nothing of ours was bought")
end)

T.test("close_mid_quote", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    AHW.Close()   -- the quote is still on its way
    T.deq(w.done, { { false, "closed" } })
    T.isnil(M.Buy.Pending())
    AHW.Open()
    w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    AHW.Settle()
    T.eq(M.Buy.Pending(), "quote")
    AHW.Close()   -- the player is looking at the price
    T.deq(w.done, { { false, "closed" } })
    T.isnil(M.Buy.Pending())
    local ok, why = click(function() return M.Buy.Confirm(seen(w)) end)
    T.falsy(ok); T.eq(why, "noquote")
end)

T.test("cancel_drops_the_quote", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    AHW.Settle()
    M.Buy.Cancel()
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1)
    T.isnil(M.Buy.Pending())
    T.deq(w.done, { { false, "canceled" } })
    local ok, why = click(function() return M.Buy.Confirm(seen(w)) end)
    T.falsy(ok); T.eq(why, "noquote")
    M.Buy.Cancel()   -- nothing to cancel: quiet
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1)
    -- a quote canceled before it arrives is not announced when it does
    w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 11000, w.onQuote, w.onDone) end)
    M.Buy.Cancel()
    AHW.Settle()
    T.deq(w.quotes, {})
    T.deq(w.done, { { false, "canceled" } })
end)

T.test("one_purchase_at_a_time", function()
    local M = load()
    local ok, why = click(function() return M.Buy.Commodity(HERB, 60, 11000) end)
    T.falsy(ok); T.eq(why, "closed")
    AHW.Open()
    click(function() return M.Buy.Commodity(HERB, 60, 11000) end)
    ok, why = click(function() return M.Buy.Commodity(HERB, 10, 11000) end)
    T.falsy(ok); T.eq(why, "busy")
    ok, why = click(function() return M.Buy.Item(auctionOf(SWORD).auctionID, 5000) end)
    T.falsy(ok); T.eq(why, "busy")
    T.eq(AHW.Calls("PlaceBid"), 0)
    ok = click(function() return M.Buy.Confirm(630000) end)
    T.falsy(ok, "no quote yet")
    AHW.Settle()
    T.eq(M.Buy.Pending(), "quote")
    -- the quote is in hand, the line is free: still one purchase at a time
    ok, why = click(function() return M.Buy.Item(auctionOf(SWORD).auctionID, 5000) end)
    T.falsy(ok); T.eq(why, "busy")
    ok, why = click(function() return M.Buy.Commodity(HERB, 10, 11000) end)
    T.falsy(ok); T.eq(why, "busy")
    T.eq(AHW.Calls("PlaceBid"), 0)
    T.eq(AHW.Calls("StartCommoditiesPurchase"), 1)
end)

T.test("confirm_refuses_a_quote_the_player_never_saw", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    AHW.Settle()
    local old = seen(w)
    -- the price moves while the player looks: the game sends a new quote
    AHW.state.quoteBump = 5000
    AHW.state.purchase.total = old + 5000
    stub.FireEvent("COMMODITY_PRICE_UPDATED", math.floor((old + 5000) / 60), old + 5000)
    T.eq(#w.quotes, 2, "the player is told again")
    T.deq(w.quotes[2], { math.floor((old + 5000) / 60), old + 5000 }, "the new unit and total, not the event's name")
    local ok, why = click(function() return M.Buy.Confirm(old) end)
    T.falsy(ok); T.eq(why, "moved")
    T.eq(AHW.Calls("ConfirmCommoditiesPurchase"), 0, "nothing sent")
    T.eq(M.Buy.Pending(), "quote", "the quote waits for a yes to the new price")
    ok = click(function() return M.Buy.Confirm(seen(w)) end)
    T.truthy(ok)
    AHW.Settle()
    T.deq(w.done, { { true } })
end)

T.test("stale_quote_is_refused_without_sending", function()
    local M = load({ quoteSeconds = 20 })
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    AHW.Settle()
    AHW.Advance(10)
    T.truthy(C_AuctionHouse.GetQuoteDurationRemaining() > 0)
    AHW.Advance(11)
    local ok, why = click(function() return M.Buy.Confirm(seen(w)) end)
    T.falsy(ok); T.eq(why, "expired")
    T.eq(AHW.Calls("ConfirmCommoditiesPurchase"), 0, "nothing sent")
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1, "the held quote is let go")
    T.deq(w.done, { { false, "expired" } })
    T.isnil(M.Buy.Pending())
    T.eq(countOf(HERB), 90)
end)

T.test("a_failed_or_lost_quote_is_canceled_in_the_game", function()
    -- unavailable
    local M = load({ quoteFails = true })
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    AHW.Settle()
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1)
    -- failed
    M = load()
    AHW.Open()
    w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    AHW.Settle()
    table.remove(AHW.Auctions(), 1)
    click(function() return M.Buy.Confirm(seen(w)) end)
    AHW.Settle()
    T.deq(w.done, { { false, "failed" } })
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1)
    -- timeout (a blocked click)
    M = load()
    AHW.Open()
    w = watcher()
    M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone)
    AHW.Advance(M.AH.TIMEOUT + 1)
    T.deq(w.done, { { false, "timeout" } })
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1)
    -- the window closing needs none: the game drops it itself
    M = load()
    AHW.Open()
    w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    AHW.Settle()
    AHW.Close()
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 0)
end)

T.test("item_one_click", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local id = auctionOf(SWORD).auctionID
    local ok = click(function() return M.Buy.Item(id, 5000, w.onDone) end)
    T.truthy(ok)
    T.eq(M.Buy.Pending(), "item")
    T.deq(AHW.Log("PlaceBid"), { { id, 5000 } }, "a buyout is a bid of the buyout")
    AHW.Settle()
    T.deq(w.done, { { true } })
    T.isnil(M.Buy.Pending())
    T.isnil(auctionOf(SWORD), "bought")
end)

T.test("item_sold_out", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local id = auctionOf(SWORD).auctionID
    AHW.state.soldOut[id] = true
    click(function() return M.Buy.Item(id, 5000, w.onDone) end)
    AHW.Settle()
    T.deq(w.done, { { false, "failed" } })
    T.isnil(M.Buy.Pending())
    T.truthy(auctionOf(SWORD))
end)

T.test("item_on_a_server_error_never_blames_a_buyer", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local id = auctionOf(SWORD).auctionID
    AHW.state.soldOut[id] = AHW.DATABASE_ERROR
    click(function() return M.Buy.Item(id, 5000, w.onDone) end)
    AHW.Settle()
    T.deq(w.done, { { false, "trouble" } })
    T.isnil(M.Buy.Pending())
end)

T.test("item_outside_a_click_is_blocked", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    M.Buy.Item(auctionOf(SWORD).auctionID, 5000, w.onDone)
    T.truthy(blockedOn("PlaceBid"))
    AHW.Advance(M.AH.TIMEOUT + 1)
    T.deq(w.done, { { false, "timeout" } })
    T.truthy(auctionOf(SWORD))
end)

T.test("item_close_mid_buy", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Item(auctionOf(SWORD).auctionID, 5000, w.onDone) end)
    AHW.Close()
    T.deq(w.done, { { false, "closed" } })
    T.isnil(M.Buy.Pending())
end)

T.test("bid_one_click", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local a = auctionOf(BOW)
    local ok = click(function() return M.Buy.Bid(a.auctionID, a.minBid, 0, w.onDone) end)
    T.truthy(ok)
    T.eq(M.Buy.Pending(), "bid")
    T.deq(AHW.Log("PlaceBid"), { { a.auctionID, 300 } })
    AHW.Settle()
    T.deq(w.done, { { true } })
    T.isnil(M.Buy.Pending())
    T.eq(auctionOf(BOW).bid, 300, "the bid stands, the auction stays")
end)

T.test("bid_at_the_buyout_is_refused", function()
    local M = load()
    AHW.Open()
    local id = auctionOf(SWORD).auctionID
    local ok, why = click(function() return M.Buy.Bid(id, 5000, 5000) end)
    T.falsy(ok); T.eq(why, "buyout")
    ok, why = click(function() return M.Buy.Bid(id, 6000, 5000) end)
    T.falsy(ok); T.eq(why, "buyout")
    T.eq(AHW.Calls("PlaceBid"), 0, "nothing sent")
    T.isnil(M.Buy.Pending())
end)

T.test("bid_that_turns_out_a_purchase_is_done", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local id = auctionOf(SWORD).auctionID
    -- the caller's buyout was stale (0): the game buys it anyway
    click(function() return M.Buy.Bid(id, 5000, 0, w.onDone) end)
    AHW.Settle()
    T.deq(w.done, { { true } })
    T.isnil(M.Buy.Pending())
    T.isnil(auctionOf(SWORD))
end)

T.test("bid_sold_out", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local a = auctionOf(BOW)
    AHW.state.soldOut[a.auctionID] = true
    click(function() return M.Buy.Bid(a.auctionID, a.minBid, 0, w.onDone) end)
    AHW.Settle()
    T.deq(w.done, { { false, "failed" } })
end)

T.test("check_follows_the_players_limit", function()
    local M = load()
    local set = { askHigh = true, askAbove = 2 }
    M.Setting = function(key) return set[key] end
    M.Store.Record(RKEY, "2449", 1 * G, 5, time())
    T.falsy((M.Buy.Check("2449", 1 * G + 90 * S)), "190% is under a 200% limit")
    T.truthy((M.Buy.Check("2449", 2 * G + 1 * S)))
    set.askHigh = false
    local warn, pct = M.Buy.Check("2449", 5 * G)
    T.falsy(warn, "asking switched off"); T.eq(pct, 500)
end)

T.test("check_warns_over_safety", function()
    local M = load()
    T.eq(M.Buy.SAFETY, 150)
    M.Store.Record(RKEY, "2449", 1 * G, 5, time())
    local warn, pct = M.Buy.Check("2449", 1 * G + 51 * S)
    T.truthy(warn); T.eq(pct, 151)
    warn, pct = M.Buy.Check("2449", 1 * G + 50 * S)
    T.falsy(warn); T.eq(pct, 150)
    warn, pct = M.Buy.Check("2449", 1 * G)
    T.falsy(warn); T.eq(pct, 100)
    warn, pct = M.Buy.Check("999", 1 * G)
    T.truthy(warn, "no market: warn"); T.isnil(pct)
    T.noerror(function() warn, pct = M.Buy.Check("2449", nil) end)
    T.truthy(warn, "no price: warn"); T.isnil(pct)
    T.noerror(function() warn, pct = M.Buy.Check("2449", "1g") end)
    T.truthy(warn); T.isnil(pct)
end)

-- A quote that ends in "error" (a send or an answer handler raised) may still
-- be held by the server: it is let go there too.
T.test("a_quote_ending_in_error_is_canceled_in_the_game", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    local real = C_AuctionHouse.StartCommoditiesPurchase
    C_AuctionHouse.StartCommoditiesPurchase = function(...)
        real(...)   -- the quote went out
        error("something broke after the send")
    end
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    C_AuctionHouse.StartCommoditiesPurchase = real
    T.deq(w.done, { { false, "error" } })
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1, "the held quote is let go")
    stub.errors = {}   -- the raised error went to the error handler, as in game
    AHW.Settle()
end)

T.test("not_enough_gold_is_refused_before_anything_goes_out", function()
    local M = load()
    _G.GetMoney = function() return 100 end
    AHW.Open()
    local w = watcher()
    local ok, why = click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    T.falsy(ok); T.eq(why, "gold")
    T.eq(AHW.Calls("StartCommoditiesPurchase"), 0)
    T.isnil(M.Buy.Pending())
    local id = auctionOf(SWORD).auctionID
    ok, why = click(function() return M.Buy.Item(id, 5000, w.onDone) end)
    T.falsy(ok); T.eq(why, "gold")
    T.eq(AHW.Calls("PlaceBid"), 0)
    _G.GetMoney = nil
end)

T.test("a_quote_dearer_than_your_gold_waits_at_confirm", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    AHW.Settle()
    _G.GetMoney = function() return seen(w) - 1 end
    local ok, why = click(function() return M.Buy.Confirm(seen(w)) end)
    T.falsy(ok); T.eq(why, "gold")
    T.eq(AHW.Calls("ConfirmCommoditiesPurchase"), 0)
    T.eq(M.Buy.Pending(), "quote", "still held: gold can come in")
    _G.GetMoney = nil
    M.Buy.Cancel()
end)

T.test("the_games_own_words_come_with_a_refused_purchase", function()
    local M = load()
    AHW.Open()
    local words
    local id = auctionOf(SWORD).auctionID
    AHW.state.soldOut[id] = 0   -- NotEnoughMoney
    click(function() return M.Buy.Item(id, 5000, function(_, _, detail) words = detail end) end)
    AHW.Settle()
    T.truthy(words and words:find("money", 1, true), tostring(words))
end)

T.test("a_confirm_that_lost_its_answer_still_counts_when_it_lands", function()
    local M = load()
    AHW.Open()
    local bought = {}
    M.On("CommodityBought", function(id, qty) bought[#bought + 1] = { id, qty } end)
    local w = watcher()
    click(function() return M.Buy.Commodity(HERB, 60, 10500, w.onQuote, w.onDone) end)
    AHW.Settle()
    C_AuctionHouse.ConfirmCommoditiesPurchase = function() end   -- sent, and no answer in time
    click(function() return M.Buy.Confirm(seen(w)) end)
    AHW.Advance(M.AH.TIMEOUT + 1)
    T.deq(w.done, { { false, "timeout" } })
    T.eq(#bought, 0)
    stub.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
    T.deq(bought, { { HERB, 60 } }, "Stock hears, late")
    stub.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
    T.eq(#bought, 1, "once")
end)
