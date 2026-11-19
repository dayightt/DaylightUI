local AHW = require("ahworld")
local stub = require("stub")

-- The Auction House request runner (Game/AH.lua) on the fake auction house
-- (tests/ahworld.lua), and a few tests that pin the fake itself: later tasks
-- (the full scan, targeted searches) lean on it behaving like the client.

local HERB = 2449          -- a commodity in these worlds
local SWORD = 2207         -- gear

local function world(spec)
    spec = spec or {}
    spec.auctions = spec.auctions or {
        { itemID = HERB, count = 20, buyout = 2000 },
        { itemID = SWORD, count = 1, buyout = 5000, owner = "Brann" },
    }
    spec.commodities = spec.commodities or { [HERB] = true }
    return AHW.Mog({ ah = spec })
end

-- A request that asks for a commodity search, done on its answer; what
-- happens is written into `log` (sent, then done/failed).
local function search(M, log, tag, opts)
    opts = opts or {}
    return M.AH.Request({
        name = "search " .. tostring(tag), search = true, timeout = opts.timeout,
        send = function()
            log[#log + 1] = "send " .. tostring(tag)
            C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(HERB), {}, false)
        end,
        events = { COMMODITY_SEARCH_RESULTS_UPDATED = function(itemID) return itemID == HERB end },
        onDone = function(ok, why) log[#log + 1] = (ok and "done " or ("failed " .. tostring(why) .. " ")) .. tostring(tag) end,
    })
end

local function replicate(M, log, tag, opts)
    opts = opts or {}
    return M.AH.Request({
        name = "replicate", timeout = opts.timeout,
        send = opts.send or function()
            log[#log + 1] = "send " .. tostring(tag)
            C_AuctionHouse.ReplicateItems()
        end,
        events = { REPLICATE_ITEM_LIST_UPDATE = function() return true end },
        onDone = function(ok, why) log[#log + 1] = (ok and "done " or ("failed " .. tostring(why) .. " ")) .. tostring(tag) end,
    })
end

-- ---------------------------------------------------------------------
-- The runner
-- ---------------------------------------------------------------------

T.test("open_state_follows_events", function()
    local M = world()
    local said = {}
    M.On("AHOpened", function() said[#said + 1] = "opened" end)
    M.On("AHClosed", function() said[#said + 1] = "closed" end)
    T.falsy(M.AH.IsOpen(), "closed at login")
    AHW.Open()
    T.truthy(M.AH.IsOpen(), "AUCTION_HOUSE_SHOW opens it")
    AHW.Close()
    T.falsy(M.AH.IsOpen(), "AUCTION_HOUSE_CLOSED closes it")
    AHW.Open()
    T.deq(said, { "opened", "closed", "opened" })
end)

T.test("one_request_at_a_time", function()
    local M = world()
    AHW.Open()
    local log = {}
    replicate(M, log, "A")
    search(M, log, "B")
    search(M, log, "C")
    T.eq(AHW.Calls("ReplicateItems"), 1, "the first is sent at once")
    T.eq(AHW.Calls("SendSearchQuery"), 0, "the second waits for the first")
    AHW.Step()   -- the replicate's answer
    T.eq(AHW.Calls("SendSearchQuery"), 1, "B goes once A is done")
    AHW.Settle()
    T.deq(log, { "send A", "done A", "send B", "done B", "send C", "done C" }, "first in, first out")
    T.eq(AHW.Calls("SendSearchQuery"), 2)
end)

T.test("waits_for_the_throttle", function()
    local M = world({ throttled = true })
    AHW.Open()
    local log = {}
    search(M, log, "A")
    T.eq(AHW.Calls("SendSearchQuery"), 0, "not sent while the game isn't ready")
    AHW.Throttle(false)   -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY
    T.eq(AHW.Calls("SendSearchQuery"), 1, "sent once it is")
    AHW.Settle()
    T.deq(log, { "send A", "done A" })
end)

T.test("rechecks_on_every_throttle_event", function()
    for _, event in ipairs({ "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
        "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
        "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_BROWSE_FAILURE" }) do
        local M = world({ throttled = true })
        AHW.Open()
        local log = {}
        search(M, log, "A")
        AHW.state.throttled = false   -- ready again, quietly
        T.eq(AHW.Calls("SendSearchQuery"), 0, event .. ": nothing until an event")
        stub.FireEvent(event)
        -- an answer while nothing of ours is out is someone else's: the next frame (AH.lua "tail")
        if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED" then
            T.eq(AHW.Calls("SendSearchQuery"), 0, "not in the frame of an answer that isn't ours")
            AHW.Frame()
        end
        T.eq(AHW.Calls("SendSearchQuery"), 1, event .. " re-checks the throttle")
    end
end)

T.test("search_rate_window", function()
    local M = world()
    AHW.Open()
    T.eq(M.AH.SEARCH_PER_MINUTE, 100, "the game's documented limit")
    T.eq(M.AH.WINDOW, 61, "the documented minute and a second's margin")
    local log = {}
    local function sent() return AHW.Calls("SendSearchQuery") end
    -- 50 searches in the first 12.5 s, then 30 s of nothing.
    for i = 1, 50 do search(M, log, i) end
    AHW.Settle()
    T.eq(sent(), 50)
    AHW.Advance(30)
    -- 110 more: 50 fit in the window, the 101st waits for the first to age out.
    for i = 51, 160 do search(M, log, i) end
    AHW.Settle()
    T.eq(sent(), 100, "100 in the window: the 101st waits")
    AHW.Advance(5.75)
    T.eq(sent(), 100, "60.75 s after the first: still waiting")
    AHW.Advance(0.25)
    T.eq(sent(), 101, "61 s after the first: it frees a place")
    -- Sliding, not a fresh minute: only the first 50 places free up now;
    -- the next 50 were used 30 s later and free up 30 s later.
    AHW.Settle()
    T.eq(sent(), 150, "the first minute's 50 places reused")
    AHW.Advance(29.75)
    T.eq(sent(), 150, "the second batch's places are still taken")
    AHW.Advance(0.25)
    T.eq(sent(), 151)
    AHW.Settle()
    T.eq(sent(), 160)
    T.eq(AHW.Calls("Dropped"), 0, "the fake server never had to drop one")
    local done = 0
    for _, line in ipairs(log) do if line:find("^done ") then done = done + 1 end end
    T.eq(done, 160)
end)

T.test("closing_fails_everything", function()
    local M = world()
    AHW.Open()
    local log = {}
    replicate(M, log, "A")
    search(M, log, "B")
    search(M, log, "C")
    AHW.Close()
    T.deq(log, { "send A", "failed closed A", "failed closed B", "failed closed C" }, "in flight and queued, in order, once each")
    AHW.Settle()
    T.eq(#log, 4, "no late answer finishes anything")
    -- The next visit starts clean.
    AHW.Open()
    search(M, log, "D")
    AHW.Settle()
    T.deq({ log[5], log[6] }, { "send D", "done D" })
end)

T.test("timeout_fails_the_request", function()
    local M = world()
    AHW.Open()
    local log = {}
    -- Sent, but the answer never comes (nothing is asked of the server).
    replicate(M, log, "A", { send = function() log[#log + 1] = "send A" end })
    search(M, log, "B")
    T.eq(M.AH.TIMEOUT, 10, "the default")
    AHW.Advance(9.75)
    T.deq(log, { "send A" }, "still waiting")
    AHW.Advance(0.25)
    T.deq(log, { "send A", "failed timeout A", "send B" }, "failed after 10 s; the next goes")
    AHW.Settle()
    T.eq(log[4], "done B")
    -- A request's own timeout.
    replicate(M, log, "C", { timeout = 2, send = function() log[#log + 1] = "send C" end })
    AHW.Advance(2)
    T.deq({ log[5], log[6] }, { "send C", "failed timeout C" })
end)

T.test("nothing_sent_while_closed", function()
    local M = world()
    local log = {}
    T.falsy(replicate(M, log, "A"), "refused")
    T.deq(log, { "failed closed A" }, "told at once")
    AHW.Open()
    AHW.Settle()
    AHW.Advance(60)
    T.eq(AHW.Calls("ReplicateItems"), 0, "never sent later either")
    T.eq(#log, 1)
end)

T.test("an_answer_handler_can_fail_the_request", function()
    local M = world()
    AHW.Open()
    local got
    M.AH.Request({
        name = "browse", send = function() C_AuctionHouse.ReplicateItems() end,
        events = { REPLICATE_ITEM_LIST_UPDATE = function() return false, "empty" end },
        onDone = function(ok, why) got = { ok, why } end,
    })
    AHW.Settle()
    T.deq(got, { false, "empty" })
end)

T.test("a_send_that_errors_fails_and_the_queue_moves_on", function()
    local M = world()
    AHW.Open()
    local log, got = {}, nil
    M.AH.Request({
        name = "bad", send = function() error("the game said no") end, events = {},
        onDone = function(ok, why) got = { ok, why } end,
    })
    search(M, log, "B")
    T.deq(got, { false, "error" })
    local reported = false
    for _, e in ipairs(stub.errors) do if e:find("the game said no", 1, true) then reported = true end end
    T.truthy(reported, "the error reaches the game's error handler, with where it happened")
    AHW.Settle()
    T.deq(log, { "send B", "done B" })
end)

T.test("a_send_that_answers_at_once_is_done_and_the_queue_moves_on", function()
    local M = world()
    AHW.Open()
    local log, got = {}, nil
    M.AH.Request({
        name = "nothing to ask", send = function() return "answered" end,
        events = { COMMODITY_SEARCH_RESULTS_UPDATED = function() return true end },
        onDone = function(ok, why) got = { ok, why } end,
    })
    T.deq(got, { true }, "done before Request returns: no event to wait for")
    search(M, log, "B")
    T.deq(log, { "send B" }, "the next request goes at once")
    AHW.Settle()
    T.deq(log, { "send B", "done B" })
    AHW.Advance(M.AH.TIMEOUT * 2)
    T.deq(got, { true }, "its timeout does nothing")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("loads_do_not_leak", function()
    local M = world()
    AHW.Open()
    local log = {}
    replicate(M, log, "A")
    local M2 = world()
    T.falsy(M2.AH.IsOpen(), "a new load starts closed")
    AHW.Settle()
    T.deq(log, { "send A" }, "the old world's answer is gone with it")
    local M3 = AHW.Mog({})
    T.isnil(_G.C_AuctionHouse, "a load without `ah` has no auction house")
    T.isnil(C_Item.DoesItemExistByID, "nor the world's item functions")
    T.falsy(M3.AH.IsOpen())
end)

-- ---------------------------------------------------------------------
-- M.Game.Now: the server's clock when the game has one
-- ---------------------------------------------------------------------

T.test("game_now_prefers_the_server_clock", function()
    local M = world()
    T.eq(M.Game.Now(), time(), "no GetServerTime: time()")
    M = AHW.Mog({ ah = {}, before = function() _G.GetServerTime = function() return 42 end end })
    T.eq(M.Game.Now(), 42)
    M = world()
    T.isnil(_G.GetServerTime, "each load starts without it")
end)

-- ---------------------------------------------------------------------
-- The fake itself
-- ---------------------------------------------------------------------

T.test("fake_replicate_answers_after_one_step", function()
    world({ auctions = {
        { itemID = HERB, count = 20, buyout = 2000, minBid = 1500, owner = "Ysella" },
        { itemID = SWORD, count = 1, buyout = 0, minBid = 900 },
    } })
    AHW.Open()
    local fired = 0
    local f = CreateFrame("Frame")
    f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    f:SetScript("OnEvent", function() fired = fired + 1 end)
    C_AuctionHouse.ReplicateItems()
    T.eq(fired, 0, "asynchronous")
    T.eq(C_AuctionHouse.GetNumReplicateItems(), 0)
    T.truthy(AHW.Step())
    T.eq(fired, 1)
    T.eq(C_AuctionHouse.GetNumReplicateItems(), 2)
    T.eq(select("#", C_AuctionHouse.GetReplicateItemInfo(0)), 18, "the 18 documented returns")
    local name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner, _, _, itemID, hasAll = C_AuctionHouse.GetReplicateItemInfo(0)
    T.eq(count, 20); T.eq(minBid, 1500); T.eq(buyout, 2000); T.eq(owner, "Ysella")
    T.eq(itemID, HERB); T.eq(hasAll, true); T.truthy(name)
    T.truthy(C_AuctionHouse.GetReplicateItemLink(0):find("item:" .. HERB, 1, true))
    local _, _, _, _, _, _, _, _, _, buyout2, _, _, _, _, _, _, itemID2 = C_AuctionHouse.GetReplicateItemInfo(1)
    T.eq(buyout2, 0, "bid only"); T.eq(itemID2, SWORD)
    T.eq(select("#", C_AuctionHouse.GetReplicateItemInfo(2)), 0, "0-based: index 2 is past the end")
    T.falsy(AHW.Step(), "nothing more to answer")
end)

T.test("fake_refuses_while_closed_or_throttled", function()
    world({ throttled = true })
    local dropped = 0
    local f = CreateFrame("Frame")
    f:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
    f:SetScript("OnEvent", function() dropped = dropped + 1 end)
    C_AuctionHouse.ReplicateItems()
    T.eq(AHW.Waiting(), 0, "closed: no answer coming")
    AHW.Open()
    C_AuctionHouse.ReplicateItems()
    T.eq(dropped, 1, "throttled: the client drops it")
    T.eq(AHW.Waiting(), 0)
    AHW.Throttle(false)
    C_AuctionHouse.ReplicateItems()
    T.falsy(C_AuctionHouse.IsThrottledMessageSystemReady(), "busy until the answer")
    C_AuctionHouse.ReplicateItems()
    T.eq(dropped, 2, "a second message while the first is out")
    AHW.Settle()
    T.truthy(C_AuctionHouse.IsThrottledMessageSystemReady(), "ready after the answer")
    T.errors(function() C_AuctionHouse.SendSearchQuery(HERB, {}, false) end, "an itemID is not an item key")
end)

T.test("fake_search_pages", function()
    local auctions = {}
    for i = 1, 120 do auctions[i] = { itemID = HERB, count = 1, buyout = 100 + i } end
    for i = 1, 3 do auctions[#auctions + 1] = { itemID = SWORD, count = 1, buyout = 9000 - i } end
    world({ auctions = auctions })
    AHW.Open()
    local key = C_AuctionHouse.MakeItemKey(HERB)
    T.deq(key, { itemID = HERB, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    C_AuctionHouse.SendSearchQuery(key, {}, false)
    T.eq(C_AuctionHouse.GetNumCommoditySearchResults(HERB), 0, "nothing before the answer")
    AHW.Step()
    T.eq(C_AuctionHouse.GetNumCommoditySearchResults(HERB), 50, "a page of 50")
    T.falsy(C_AuctionHouse.HasFullCommoditySearchResults(HERB))
    local first = C_AuctionHouse.GetCommoditySearchResultInfo(HERB, 1)
    T.eq(first.unitPrice, 101, "cheapest first"); T.eq(first.quantity, 1); T.eq(first.itemID, HERB)
    T.isnil(C_AuctionHouse.GetCommoditySearchResultInfo(HERB, 51), "not loaded yet")
    T.falsy(C_AuctionHouse.RequestMoreCommoditySearchResults(HERB))
    AHW.Step()
    T.eq(C_AuctionHouse.GetNumCommoditySearchResults(HERB), 100)
    C_AuctionHouse.RequestMoreCommoditySearchResults(HERB)
    AHW.Step()
    T.eq(C_AuctionHouse.GetNumCommoditySearchResults(HERB), 120)
    T.truthy(C_AuctionHouse.HasFullCommoditySearchResults(HERB))
    -- Gear: item results, its own events.
    local got
    local f = CreateFrame("Frame")
    f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    f:SetScript("OnEvent", function(_, _, k) got = k end)
    local skey = C_AuctionHouse.MakeItemKey(SWORD)
    C_AuctionHouse.SendSearchQuery(skey, {}, false)
    AHW.Settle()
    T.eq(got.itemID, SWORD, "the event carries an item key")
    T.eq(C_AuctionHouse.GetNumItemSearchResults(skey), 3)
    T.truthy(C_AuctionHouse.HasFullItemSearchResults(skey))
    local row = C_AuctionHouse.GetItemSearchResultInfo(skey, 1)
    T.eq(row.buyoutAmount, 8997); T.eq(row.quantity, 1); T.truthy(row.itemLink:find("item:" .. SWORD, 1, true))
    row.quantity, row.itemKey.itemID = 99, 0
    T.eq(C_AuctionHouse.GetItemSearchResultInfo(skey, 1).quantity, 1, "a fresh row each call")
    T.eq(C_AuctionHouse.GetItemSearchResultInfo(skey, 1).itemKey.itemID, SWORD)
    first.quantity = 99
    T.eq(C_AuctionHouse.GetCommoditySearchResultInfo(HERB, 1).quantity, 1)
    T.eq(AHW.Calls("SendSearchQuery"), 2)
end)

T.test("fake_uncached_items", function()
    world({ auctions = {
        { itemID = SWORD, count = 1, buyout = 5000, cached = false },
        { itemID = 7429, count = 1, buyout = 9000, cached = false },
    }, neverCache = { [7429] = true } })
    AHW.Open()
    local key = C_AuctionHouse.MakeItemKey(SWORD)
    T.isnil(C_AuctionHouse.GetItemKeyInfo(key), "not cached yet")
    C_AuctionHouse.ReplicateItems()
    AHW.Step()
    local hasAll = select(18, C_AuctionHouse.GetReplicateItemInfo(0))
    T.eq(hasAll, false)
    T.isnil(C_AuctionHouse.GetReplicateItemLink(0), "no link before the item is known")
    local heard = {}
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "ITEM_KEY_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }) do f:RegisterEvent(e) end
    f:SetScript("OnEvent", function(_, e, id) heard[#heard + 1] = e .. " " .. tostring(id) end)
    AHW.Cache(SWORD)
    T.truthy(#heard >= 2)
    T.eq(heard[1], "ITEM_DATA_LOAD_RESULT " .. SWORD)
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    T.eq(info.itemID, SWORD); T.eq(info.isCommodity, false)
    T.eq(select(18, C_AuctionHouse.GetReplicateItemInfo(0)), true)
    T.truthy(C_AuctionHouse.GetReplicateItemLink(0))
    -- Asking loads it a step later, unless the spec says it never loads.
    heard = {}
    C_Item.RequestLoadItemDataByID(7429)
    AHW.Settle()
    T.deq(heard, {}, "neverCache: no answer")
    T.isnil(C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(7429)))
    world({ auctions = { { itemID = SWORD, count = 1, buyout = 5000, cached = false } } })
    C_Item.RequestLoadItemDataByID(SWORD)
    T.isnil(C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(SWORD)), "not at once")
    AHW.Settle()
    T.truthy(C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(SWORD)), "a step later")
    T.truthy(C_Item.DoesItemExistByID(SWORD))
    world({ missing = { [99999] = true } })
    T.falsy(C_Item.DoesItemExistByID(99999))
end)

T.test("fake_counts_calls_and_frames", function()
    local M = world()
    AHW.Open()
    T.eq(AHW.Calls("ReplicateItems"), 0)
    C_AuctionHouse.ReplicateItems()
    T.eq(AHW.Calls("ReplicateItems"), 1)
    -- C_Timer.After keeps its delay in an ah world; 0 = the next frame.
    local ran = {}
    C_Timer.After(0, function() ran[#ran + 1] = "now" end)
    C_Timer.After(5, function() ran[#ran + 1] = "later" end)
    AHW.Frame()
    T.deq(ran, { "now" })
    AHW.Advance(5)
    T.deq(ran, { "now", "later" })
    T.truthy(M)
end)

-- ---------------------------------------------------------------------
-- The clock: answers and timers in time order (fix round 1)
-- ---------------------------------------------------------------------

T.test("slow_answer_times_out_and_its_late_answer_is_ignored", function()
    local M = world({ step = 15 })
    AHW.Open()
    local log = {}
    replicate(M, log, "A")                    -- the default 10 s
    replicate(M, log, "B", { timeout = 20 })
    AHW.Step()   -- the clock reaches A's answer at +15, passing A's timeout at +10 on the way
    T.deq(log, { "send A", "failed timeout A", "send B" },
        "A timed out first; its late answer (same event) did not complete B")
    AHW.Settle()
    T.deq(log, { "send A", "failed timeout A", "send B", "done B" }, "B finished on its own answer")
end)

T.test("item_loads_run_side_by_side", function()
    local auctions = {}
    for i = 1, 40 do auctions[i] = { itemID = 10000 + i, count = 1, buyout = 100, cached = false } end
    auctions[#auctions + 1] = { itemID = HERB, count = 20, buyout = 2000 }
    local M = world({ auctions = auctions })
    AHW.Open()
    local t0 = GetTime()
    local loaded, lastLoad = 0, nil
    local f = CreateFrame("Frame")
    f:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    f:SetScript("OnEvent", function() loaded = loaded + 1; lastLoad = GetTime() end)
    for i = 1, 40 do C_Item.RequestLoadItemDataByID(10000 + i) end
    local doneAt
    M.AH.Request({
        name = "search", search = true,
        send = function() C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(HERB), {}, false) end,
        events = { COMMODITY_SEARCH_RESULTS_UPDATED = function() return true end },
        onDone = function(ok) if ok then doneAt = GetTime() end end,
    })
    AHW.Settle()
    T.eq(loaded, 40)
    T.eq(lastLoad - t0, 0.25, "forty loads together, not one after another")
    T.eq(doneAt - t0, 0.25, "the search answer isn't held up behind them")
end)

T.test("a_timer_runs_before_a_later_answer", function()
    world()
    AHW.Open()
    local order = {}
    local f = CreateFrame("Frame")
    f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    f:SetScript("OnEvent", function() order[#order + 1] = "answer" end)
    C_AuctionHouse.ReplicateItems()   -- answers at +0.25
    C_Timer.After(0.1, function() order[#order + 1] = "timer" end)
    AHW.Step()
    T.deq(order, { "timer", "answer" })
    -- Advance delivers answers as their time comes, too.
    AHW.Settle()
    C_AuctionHouse.ReplicateItems()
    AHW.Advance(1)
    T.deq(order, { "timer", "answer", "answer" })
end)

T.test("a_stuck_throttle_is_rechecked", function()
    local M = world({ throttled = true })
    AHW.Open()
    local log = {}
    search(M, log, "A")
    AHW.state.throttled = false   -- ready, and no event says so
    AHW.Advance(0.75)
    T.eq(AHW.Calls("SendSearchQuery"), 0, "not yet")
    AHW.Advance(0.25)
    T.eq(AHW.Calls("SendSearchQuery"), 1, "a look every second finds it ready")
    AHW.Settle()
    T.deq(log, { "send A", "done A" })
    -- Nothing waiting: no timer keeps looking.
    AHW.Advance(5)
    T.falsy(AHW.Step())
end)

T.test("fake_timers_and_tickers_keep_their_delays", function()
    world()
    local ticks, fired = 0, 0
    local ticker = C_Timer.NewTicker(1, function() ticks = ticks + 1 end)
    local timer = C_Timer.NewTimer(2, function() fired = fired + 1 end)
    local cancelled = C_Timer.NewTimer(2, function() fired = fired + 100 end)
    cancelled:Cancel()
    AHW.Advance(3)
    T.eq(ticks, 3); T.eq(fired, 1)
    ticker:Cancel()
    AHW.Advance(3)
    T.eq(ticks, 3, "canceled")
    T.truthy(timer)
    T.eq(select("#", C_Timer.NewTicker(1, function() end, 2)), 1)
end)

T.test("prices_are_stamped_with_server_time", function()
    -- Ruling 3: the server's clock three days ahead of the computer's. A row
    -- recorded now (M.Game.Now) is today's low by the server's day.
    local M = AHW.Mog({ ah = {}, before = function()
        _G.GetServerTime = function() return time() + 3 * 86400 end
    end })
    local rkey = M.Ruleset.Key()
    T.truthy(rkey, "a ruleset")
    T.eq(M.Game.Now(), time() + 3 * 86400)
    M.Store.Record(rkey, "2589", 120, 5, M.Game.Now())
    local lows = M.Store.Lows(rkey, "2589")
    T.eq(lows[1], M.Market.Day(M.Game.Now()), "the low is filed under the server's day")
    T.eq(M.Store.Market(rkey, "2589", M.Game.Now()), 120, "and the usual price reads it")
    _G.GetServerTime = nil
    T.truthy(lows[1] ~= M.Market.Day(time()), "by the computer's day it isn't today's low")
    -- The Login trim drops what the server's clock says is 60 days old.
    local function login(serverAhead)
        local now = 1700000000
        local M2 = AHW.Mog({ ah = {}, login = false, prices = { version = 1, rulesets = {
            ["US-PvE"] = { items = { ["2589"] = { l = { 1, 5 }, m = 5, t = now - 59 * 86400, q = 1 } } },
        } }, before = function()
            if serverAhead then _G.GetServerTime = function() return time() + serverAhead end end
        end })
        stub.FireEvent("PLAYER_LOGIN")
        AHW.Frame()   -- the trim walks from the next frame on
        return M2.Store.Seen("US-PvE", "2589")
    end
    T.truthy(login(nil), "59 days old by the computer's clock: kept")
    T.isnil(login(2 * 86400), "61 days old by the server's: trimmed at login")
end)

-- ---------------------------------------------------------------------
-- Seams: drop by tag, act now, close
-- ---------------------------------------------------------------------

local function tagged(M, log, tag)
    return M.AH.Request({
        name = "tagged " .. tag, tag = "search",
        send = function()
            log[#log + 1] = "send " .. tag
            C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(HERB), {}, false)
        end,
        events = { COMMODITY_SEARCH_RESULTS_UPDATED = function() return true end },
        onDone = function(ok, why) log[#log + 1] = (ok and "done " or ("failed " .. tostring(why) .. " ")) .. tag end,
    })
end

T.test("drop_queued_by_tag", function()
    local M = world()
    local log = {}
    AHW.Open()
    tagged(M, log, "a"); tagged(M, log, "b"); tagged(M, log, "c")
    replicate(M, log, "plain")
    M.AH.Drop("search")
    T.deq(log, { "send a", "failed dropped a", "failed dropped b", "failed dropped c" })
    T.eq(AHW.Calls("Dropped"), 0, "nothing sent into a busy client")
    AHW.Settle()
    T.deq(log, { "send a", "failed dropped a", "failed dropped b", "failed dropped c", "send plain", "done plain" })
    T.eq(AHW.Calls("Dropped"), 0)
end)

T.test("drop_and_close", function()
    local M = world()
    local log = {}
    AHW.Open()
    tagged(M, log, "a"); tagged(M, log, "b")
    M.AH.Drop("search")
    AHW.Close()
    AHW.Settle()
    T.deq(log, { "send a", "failed dropped a", "failed dropped b" })
    T.falsy(M.AH.Busy(), "the held line is freed by closing")
    AHW.Open()
    replicate(M, log, "r")
    AHW.Settle()
    T.eq(log[#log], "done r")
end)

-- A new search typed while the last one loads: the dropped one's answer
-- (its events and its RESPONSE_RECEIVED, in either order, and whether or not
-- the client says ready before its events) never ends the new one, and the
-- new one finishes on its own answer.
for _, mode in ipairs({ "eventsFirst", "responseFirst", "readyEarly" }) do
    T.test("a_search_typed_while_one_loads_gets_its_own_answer_" .. mode, function()
        local M = world({ responseFirst = mode == "responseFirst", readyEarly = mode == "readyEarly" })
        AHW.Open()
        local log = {}
        tagged(M, log, "a")
        M.AH.Drop("search")
        tagged(M, log, "b")
        AHW.Settle()
        T.deq(log, { "send a", "failed dropped a", "send b", "done b" })
        T.eq(AHW.Calls("SendSearchQuery"), 2)
        T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    end)
end

-- The dropped search's RESPONSE_RECEIVED is its own, not the new search's:
-- when the new one then times out with its message out, it still holds the
-- line, so its late answer never completes the request after it.
T.test("a_dropped_answer_is_never_taken_for_the_next_message's", function()
    local M = world({ step = 15, readyEarly = true })
    AHW.Open()
    local log = {}
    tagged(M, log, "a")
    M.AH.Drop("search")
    tagged(M, log, "b")
    AHW.Advance(16)   -- a's answer at 15: b goes out on its events
    T.deq(log, { "send a", "failed dropped a", "send b" })
    search(M, log, "c", { timeout = 30 })
    AHW.Advance(10)   -- b times out at 25 with its message out
    T.deq(log, { "send a", "failed dropped a", "send b", "failed timeout b" }, "c waits for b's late answer")
    AHW.Settle()
    T.deq(log, { "send a", "failed dropped a", "send b", "failed timeout b", "send c", "done c" })
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("act_sends_now_or_refuses", function()
    local M = world()
    local log = {}
    local function act()
        return M.AH.Act({
            name = "buy",
            send = function() log[#log + 1] = "send"; C_AuctionHouse.ReplicateItems() end,
            events = { REPLICATE_ITEM_LIST_UPDATE = function() return true end },
            onDone = function(ok) log[#log + 1] = ok and "done" or "failed" end,
        })
    end
    local ok, why = act()
    T.falsy(ok); T.eq(why, "closed")
    AHW.Open()
    ok = act()
    T.truthy(ok); T.deq(log, { "send" }, "sent before Act returned")
    ok, why = act()
    T.falsy(ok); T.eq(why, "busy"); T.deq(log, { "send" })
    T.truthy(M.AH.Busy())
    AHW.Settle()
    T.deq(log, { "send", "done" })
    T.falsy(M.AH.Busy())
    AHW.Throttle(true)
    ok, why = act()
    T.falsy(ok); T.eq(why, "throttled"); T.deq(log, { "send", "done" })
    AHW.Throttle(false)
    tagged(M, {}, "s")   -- a search in flight is busy too
    ok, why = act()
    T.falsy(ok); T.eq(why, "busy")
    T.eq(AHW.Calls("Dropped"), 0)
end)

-- Act's contract: false and a reason means nothing was sent and onDone never
-- runs; true means it was sent, and a send that raised has already ended
-- with onDone(false, "error") (it may have reached the server: Buy lets a
-- quote go there), one that returned "answered" with onDone(true).
T.test("act_true_with_onDone_when_the_send_ends_at_once", function()
    local M = world()
    AHW.Open()
    local log = {}
    local ok = M.AH.Act({
        name = "buy", send = function() error("boom") end,
        events = { REPLICATE_ITEM_LIST_UPDATE = function() return true end },
        onDone = function(done, reason) log[#log + 1] = tostring(done) .. " " .. tostring(reason) end,
    })
    T.truthy(ok, "sent: its end is onDone's")
    T.deq(log, { "false error" }, "onDone said so, once")
    T.falsy(M.AH.Busy(), "the line is free")
    T.eq(#stub.errors, 1, "the error still reaches the error handler")
    stub.errors = {}
    ok = M.AH.Act({
        name = "nothing to send", send = function() return "answered" end,
        events = {}, onDone = function(done) log[#log + 1] = "answered " .. tostring(done) end,
    })
    T.truthy(ok, "answered at once is a success")
    T.deq(log, { "false error", "answered true" })
    AHW.Close()
    local why
    ok, why = M.AH.Act({ name = "x", send = function() log[#log + 1] = "sent" end, events = {},
        onDone = function() log[#log + 1] = "onDone" end })
    T.falsy(ok); T.eq(why, "closed")
    T.deq(log, { "false error", "answered true" }, "refused: nothing sent, no onDone")
end)

T.test("close_calls_game", function()
    local M = world()
    M.AH.Close()
    T.eq(AHW.Calls("CloseAuctionHouse"), 0, "closed already: nothing to close")
    AHW.Open()
    M.AH.Close()
    T.eq(AHW.Calls("CloseAuctionHouse"), 1)
    T.falsy(M.AH.IsOpen())
end)

-- The per-send guard: a request that timed out after its message went out
-- holds the line until that message's answer, and its late answer never
-- completes the next request, in either order of the answer's events.
T.test("a_late_answer_never_reaches_the_next_request", function()
    local M = world({ step = 15, responseFirst = true })
    AHW.Open()
    local log = {}
    replicate(M, log, "A")                    -- the default 10 s
    replicate(M, log, "B", { timeout = 20 })
    AHW.Step()   -- A's answer at +15, its throttle events first
    T.deq(log, { "send A", "failed timeout A", "send B" }, "B goes out after A's answer, not on it")
    AHW.Settle()
    T.deq(log, { "send A", "failed timeout A", "send B", "done B" }, "B finished on its own answer")
    T.eq(AHW.Calls("ReplicateItems"), 2)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)
