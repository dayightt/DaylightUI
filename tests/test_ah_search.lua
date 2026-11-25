local AHW = require("ahworld")
local stub = require("stub")

-- Targeted searches (Game/Search.lua) on the fake auction house: one item
-- priced from its search results, commodity or not, every page read, bad
-- rows skipped, the item's key info waited for (never forever), nothing kept
-- when the AH closes, nothing stored without a ruleset (rows still returned).

local LINEN, WOOL, BLADE = 2589, 2592, 15210
local RKEY = "US-PvE"

-- A fresh addon in the realm "Forever" (US). ruleset = false: not known.
-- spec: the ahworld spec (auctions, commodities, page, neverCache, missing).
local function load(spec, opts)
    opts = opts or {}
    local M = AHW.Mog({
        ah = spec, ruleset = opts.ruleset,
        before = function()
        end,
    })
    return M
end

local function watchChanges(M)
    local seen = {}
    M.On("PricesChanged", function(rkey) seen[#seen + 1] = rkey end)
    return seen
end

-- Starts a search; the returned table fills in when it ends:
-- { calls = n, rows = rows|nil, reason = reason }.
local function search(M, itemID)
    local got = { calls = 0 }
    got.started, got.why = M.Search.Item(itemID, function(rows, reason)
        got.calls = got.calls + 1
        got.rows, got.reason = rows, reason
    end)
    return got
end

-- The returned rows by key.
local function byKey(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do out[r.key] = r end
    return out
end

local function items()
    local data = DaylightUIAuctionDB.rulesets and DaylightUIAuctionDB.rulesets[RKEY]
    return data and data.items
end

-- Nothing of the search keeps running: no timer due or waiting, no answer coming.
local function quiet(M)
    T.eq(M.Search.Pending(), 0, "no search left")
    AHW.Advance(M.Game.ITEM_WAIT * 2)
    T.eq(AHW.Frame(), 0, "no timer left")
    T.eq(AHW.Waiting(), 0, "no answer coming")
end

-- ---------------------------------------------------------------------
-- Pricing
-- ---------------------------------------------------------------------

T.test("commodity_search_prices_it", function()
    local M = load({
        commodities = { [LINEN] = true },
        auctions = {
            { itemID = LINEN, count = 20, buyout = 2000 },   -- 100 each
            { itemID = LINEN, count = 5, buyout = 400 },     -- 80 each: the low
            { itemID = LINEN, count = 3, buyout = 240 },     -- 80 each too
        },
    })
    local changes = watchChanges(M)
    AHW.Open()
    local got = search(M, LINEN)
    T.eq(got.started, true)
    AHW.Settle()
    local now = M.Game.Now()
    T.eq(got.calls, 1)
    T.isnil(got.reason)
    T.deq(got.rows, { { key = "2589", base = "2589", unit = 80, qty = 28 } }, "one row per key: lowest unit, summed qty")
    T.deq(M.Store.Seen(RKEY, "2589"), { min = 80, t = now, q = 28 })
    T.deq(M.Store.Lows(RKEY, "2589"), { M.Market.Day(now), 80 })
    T.deq(changes, { RKEY }, "one PricesChanged")
    local sent = AHW.Log("SendSearchQuery")
    T.eq(#sent, 1)
    T.eq(sent[1][1].itemID, LINEN)
    T.deq(sent[1][2], { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, "cheapest first, asked for")
    T.eq(sent[1][3], false)
    T.eq(AHW.Calls("GetCommoditySearchResultInfo"), 2, "two price rows, each read once")
    T.eq(AHW.Calls("GetItemSearchResultInfo"), 0)
    T.isnil(M.Store.FullScanAt(RKEY), "a search is not a full scan")
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("item_search_prices_each_suffix", function()
    local M = load({ auctions = {
        { itemID = BLADE, count = 1, buyout = 5000, suffix = -15 },
        { itemID = BLADE, count = 1, buyout = 4000, suffix = -15 },
        { itemID = BLADE, count = 1, buyout = 3000, suffix = -16 },
        { itemID = WOOL, count = 1, buyout = 10 },   -- another item: not in the results
    } })
    local changes = watchChanges(M)
    AHW.Open()
    local got = search(M, BLADE)
    AHW.Settle()
    local now = M.Game.Now()
    T.isnil(got.reason)
    local rows = byKey(got.rows)
    T.eq(#got.rows, 2, "one row per suffix")
    T.deq(rows["15210:-15"], { key = "15210:-15", base = "15210", unit = 4000, qty = 2 })
    T.deq(rows["15210:-16"], { key = "15210:-16", base = "15210", unit = 3000, qty = 1 })
    T.deq(M.Store.Seen(RKEY, "15210:-15"), { min = 4000, t = now, q = 2 })
    T.deq(M.Store.Seen(RKEY, "15210:-16"), { min = 3000, t = now, q = 1 })
    T.deq(M.Store.Seen(RKEY, "15210"), { min = 3000, t = now, q = 3 }, "the base: cheapest of every suffix, all counted")
    T.eq(T.count(items()), 3, "nothing else stored")
    T.deq(changes, { RKEY })
    T.eq(AHW.Log("SendSellSearchQuery")[1][1].itemSuffix, 0, "gear: the sell search with no suffix, every suffix comes back")
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- Ammo stacks to 200 and the game may call it equipment (it goes in the ammo slot),
-- but a sell search for something that stacks never brings results: it was a dead
-- search every time, so arrows could neither be bought nor priced.
T.test("ammo_search_asks_like_any_stack", function()
    local ARROW = 2515
    local M = load({ auctions = {
        { itemID = ARROW, count = 200, buyout = 600, classID = 6, stack = 200 },
        { itemID = ARROW, count = 200, buyout = 400, classID = 6, stack = 200 },
    } })
    AHW.Open()
    local got = search(M, ARROW)
    AHW.Settle()
    T.isnil(got.reason)
    T.eq(got.calls, 1, "answered")
    T.deq(byKey(got.rows)["2515"], { key = "2515", base = "2515", unit = 2, qty = 400 })
    T.eq(AHW.Calls("SendSellSearchQuery"), 0, "never a sell search for a stack")
    T.eq(AHW.Calls("SendSearchQuery"), 1)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- Seen in play: MakeItemKey(2901) gave a Mining Pick's key at itemLevel 4,
-- the sell search went out with it, and only AUCTION_HOUSE_NEW_RESULTS_RECEIVED
-- came back: every gear check sat out its 10 s timeout, and the picked item
-- waited behind it. The game's sell frame clears level and suffix first
-- (AuctionHouseUtil.ConvertItemSellItemKey), as the docs ask.
T.test("gear_search_clears_the_level_and_is_answered_at_once", function()
    local PICK = 2901
    local M = load({ auctions = {
        { itemID = PICK, count = 1, buyout = 900, level = 4, classID = 2 },
    } })
    AHW.Open()
    local got = search(M, PICK)
    AHW.Settle()
    T.isnil(got.reason, "answered, not timed out")
    T.eq(#got.rows, 1)
    T.eq(got.rows[1].unit, 900)
    local sent = AHW.Log("SendSellSearchQuery")[1][1]
    T.eq(sent.itemLevel, 0, "the level cleared, as the game's sell frame does")
    T.eq(sent.itemSuffix, 0)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- Linen Bags in play: a row of 694 at 3s each came out "0 copper" and a row of
-- 2 at 4s each as 2s, the item's market with it.
T.test("an_item_row's_buyout_is_the_price_of_one", function()
    local M = load({ auctions = {
        { itemID = BLADE, count = 694, buyout = 694 * 300, timeLeft = 0 },
        { itemID = BLADE, count = 2, buyout = 800 },
    } })
    AHW.Open()
    local got
    M.Search.Item(BLADE, function(rows, _, auctions) got = { rows = rows, auctions = auctions } end)
    AHW.Settle()
    T.deq(got.rows, { { key = "15210", base = "15210", unit = 300, qty = 696 } })
    T.eq(M.Store.Seen(RKEY, "15210").min, 300)
    T.eq(got.auctions[1].unit, 300); T.eq(got.auctions[1].buyout, 300); T.eq(got.auctions[1].qty, 694)
    T.eq(got.auctions[2].unit, 400); T.eq(got.auctions[2].buyout, 400); T.eq(got.auctions[2].qty, 2)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("bid_only_results_skipped", function()
    local M = load({ auctions = {
        { itemID = BLADE, count = 1, buyout = 0, minBid = 50 },   -- bid only
        { itemID = BLADE, count = 1, buyout = 700 },
        { itemID = WOOL, count = 2, buyout = 0, minBid = 10 },    -- only bids on this one
    } })
    local changes = watchChanges(M)
    AHW.Open()
    local got = search(M, BLADE)
    AHW.Settle()
    T.deq(got.rows, { { key = "15210", base = "15210", unit = 700, qty = 1 } }, "the bid-only auction neither priced nor counted")
    T.deq(M.Store.Seen(RKEY, "15210"), { min = 700, t = M.Game.Now(), q = 1 })

    local wool = search(M, WOOL)
    AHW.Settle()
    T.deq(wool.rows, {}, "nothing to price")
    T.isnil(wool.reason)
    T.isnil(M.Store.Seen(RKEY, "2592"))
    T.eq(#changes, 1, "no PricesChanged when nothing was priced")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("sub_copper_rows_skipped", function()
    local M = load({
        commodities = { [LINEN] = true },
        auctions = {
            { itemID = LINEN, count = 200, buyout = 150 },   -- under a copper each: unitPrice 0
            { itemID = LINEN, count = 20, buyout = 2000 },
            { itemID = BLADE, count = 2, buyout = 1, suffix = -15 },
            { itemID = BLADE, count = 1, buyout = 3000, suffix = -15 },
        },
    })
    AHW.Open()
    local linen = search(M, LINEN)
    local blade = search(M, BLADE)
    AHW.Settle()
    T.deq(linen.rows, { { key = "2589", base = "2589", unit = 100, qty = 20 } })
    local seen = M.Store.Seen(RKEY, "2589")
    T.deq({ seen.min, seen.q }, { 100, 20 }, "priced from the normal stack")
    T.deq(blade.rows, { { key = "15210:-15", base = "15210", unit = 3000, qty = 1 } })
    seen = M.Store.Seen(RKEY, "15210")
    T.deq({ seen.min, seen.q }, { 3000, 1 }, "the base too")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- ---------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------

T.test("paging_until_full", function()
    local auctions = {}
    for i = 1, 3 do auctions[#auctions + 1] = { itemID = LINEN, count = 1, buyout = 100 * i } end   -- 3 price rows
    for i = 1, 3 do auctions[#auctions + 1] = { itemID = BLADE, count = 1, buyout = 1000 * i } end
    local M = load({ commodities = { [LINEN] = true }, page = 2, auctions = auctions })
    local changes = watchChanges(M)
    AHW.Open()
    local linen = search(M, LINEN)
    AHW.Step()   -- the first page
    T.eq(linen.calls, 0, "not done on the first page")
    T.eq(AHW.Calls("GetCommoditySearchResultInfo"), 2, "the first page is read as it comes")
    AHW.Settle()
    T.eq(AHW.Calls("RequestMoreCommoditySearchResults"), 1)
    T.eq(AHW.Calls("SendSearchQuery"), 1, "one search, then the next page")
    T.deq(linen.rows, { { key = "2589", base = "2589", unit = 100, qty = 3 } }, "both pages counted")

    local blade = search(M, BLADE)
    AHW.Settle()
    T.eq(AHW.Calls("RequestMoreItemSearchResults"), 1)
    T.deq(blade.rows, { { key = "15210", base = "15210", unit = 1000, qty = 3 } })
    T.deq(M.Store.Seen(RKEY, "15210"), { min = 1000, t = M.Game.Now(), q = 3 })
    T.eq(#changes, 2)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- Wraps M.AH.Request: each request's onDone results, in order of asking.
local function watchRequests(M)
    local seen = {}
    local real = M.AH.Request
    M.AH.Request = function(spec)
        local entry = { name = spec.name, done = {} }
        seen[#seen + 1] = entry
        local onDone = spec.onDone
        spec.onDone = function(ok, reason, ...)
            entry.done[#entry.done + 1] = ok and "ok" or tostring(reason)
            if onDone then return onDone(ok, reason, ...) end
        end
        return real(spec)
    end
    return seen
end

-- Which events follow RequestMore* is unknown (the docs list *_ADDED and
-- *_UPDATED): a page is done on either, whichever the client sends.
T.test("pages_on_either_results_event", function()
    for _, events in ipairs({ { "added" }, { "updated" }, { "added", "updated" } }) do
        local what = table.concat(events, "+")
        local auctions = {}
        for i = 1, 3 do auctions[#auctions + 1] = { itemID = LINEN, count = 1, buyout = 100 * i } end
        for i = 1, 3 do auctions[#auctions + 1] = { itemID = BLADE, count = 1, buyout = 1000 * i } end
        local M = load({ commodities = { [LINEN] = true }, page = 1, moreEvents = events, auctions = auctions })
        local requests = watchRequests(M)
        AHW.Open()
        local t0 = GetTime()
        local linen = search(M, LINEN)
        AHW.Settle()
        local blade = search(M, BLADE)
        AHW.Settle()
        T.truthy(GetTime() - t0 < M.AH.TIMEOUT, what .. ": no page waited for a timeout")
        T.deq(linen.rows, { { key = "2589", base = "2589", unit = 100, qty = 3 } }, what .. ": every commodity page")
        T.deq(blade.rows, { { key = "15210", base = "15210", unit = 1000, qty = 3 } }, what .. ": every item page")
        T.eq(#requests, 6, what .. ": a search and two more pages, twice")
        for i, r in ipairs(requests) do T.deq(r.done, { "ok" }, what .. ": request " .. i .. " done exactly once") end
        T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    end
end)

T.test("a_late_results_event_doesnt_end_the_next_page", function()
    local auctions = {}
    for i = 1, 3 do auctions[#auctions + 1] = { itemID = LINEN, count = 1, buyout = 100 * i } end
    local M = load({ commodities = { [LINEN] = true }, page = 1, auctions = auctions })
    local requests = watchRequests(M)
    AHW.Open()
    local got = search(M, LINEN)
    AHW.Step()   -- page one; page two asked
    T.eq(#requests, 2)
    T.deq(requests[2].done, {})
    stub.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", LINEN)   -- page one's, late
    stub.FireEvent("COMMODITY_SEARCH_RESULTS_ADDED", LINEN)
    T.deq(requests[2].done, {}, "no new rows yet: still waiting for page two")
    AHW.Settle()
    T.deq(got.rows, { { key = "2589", base = "2589", unit = 100, qty = 3 } })
    for i, r in ipairs(requests) do T.deq(r.done, { "ok" }, "request " .. i) end
end)

T.test("a_list_full_already_ends_paging_at_once", function()
    local auctions = {}
    for i = 1, 3 do auctions[#auctions + 1] = { itemID = BLADE, count = 1, buyout = 1000 * i } end
    local M = load({ page = 1, auctions = auctions })
    AHW.Open()
    -- the client disagreeing with itself: not full, yet nothing more to ask
    C_AuctionHouse.HasFullItemSearchResults = function() return false end
    C_AuctionHouse.RequestMoreItemSearchResults = function() return true end
    local t0 = GetTime()
    local got = search(M, BLADE)
    AHW.Settle()
    T.eq(got.calls, 1)
    T.truthy(GetTime() - t0 < 1, "done promptly, not after a timeout")
    T.isnil(got.reason)
    T.deq(got.rows, { { key = "15210", base = "15210", unit = 1000, qty = 1 } }, "the rows read so far")
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("paging_is_capped", function()
    local auctions = {}
    for i = 1, 30 do auctions[i] = { itemID = BLADE, count = 1, buyout = 100 + i } end
    local M = load({ page = 1, auctions = auctions })
    AHW.Open()
    local got = search(M, BLADE)
    AHW.Settle()
    T.eq(AHW.Calls("SendSearchQuery") + AHW.Calls("RequestMoreItemSearchResults"), M.Search.MAX_PAGES,
        "no more than MAX_PAGES pages, whatever HasFull says")
    T.deq(got.rows, { { key = "15210", base = "15210", unit = 101, qty = M.Search.MAX_PAGES } },
        "the pages read are priced (the cheapest come first)")
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- A frame stops after SLICE_MS of slow rows, not only after SLICE of them.
T.test("slow_rows_end_the_frame_early", function()
    local auctions = {}
    for i = 1, 600 do auctions[i] = { itemID = BLADE, count = 1, buyout = 1000 + i } end
    local M = load({ page = 600, auctions = auctions })
    local was = _G.debugprofilestop
    _G.debugprofilestop = function() return AHW.Calls("GetItemSearchResultInfo") * 1.0 end   -- 1 ms a row
    AHW.Open()
    local got = search(M, BLADE)
    AHW.Step()
    local first = AHW.Calls("GetItemSearchResultInfo")
    T.truthy(first >= 1 and first <= M.Game.SLICE_MS + 1, "about SLICE_MS rows the first frame, got " .. first)
    _G.debugprofilestop = was
    AHW.Settle()
    T.eq(got.calls, 1, "every row still read")
    T.deq(got.rows, { { key = "15210", base = "15210", unit = 1001, qty = 600 } })
end)

T.test("reads_rows_in_slices", function()
    local auctions = {}
    for i = 1, 600 do auctions[i] = { itemID = BLADE, count = 1, buyout = 1000 + i } end
    local M = load({ page = 600, auctions = auctions })
    AHW.Open()
    local got = search(M, BLADE)
    AHW.Step()   -- the answer, then a frame
    local reads = { AHW.Calls("GetItemSearchResultInfo") }
    for k = 2, 3 do
        T.eq(got.calls, 0, "not done before frame " .. k)
        AHW.Frame()
        reads[k] = AHW.Calls("GetItemSearchResultInfo")
    end
    T.deq(reads, { 250, 500, 600 }, "at most SLICE rows a frame")
    T.eq(got.calls, 1)
    T.deq(got.rows, { { key = "15210", base = "15210", unit = 1001, qty = 600 } })
    T.eq(AHW.Frame(), 0, "nothing scheduled after the end")
end)

-- ---------------------------------------------------------------------
-- Item key info the client doesn't have yet
-- ---------------------------------------------------------------------

T.test("waits_for_item_key_info", function()
    local M = load({
        auctions = { { itemID = BLADE, count = 1, buyout = 4000, suffix = -15, cached = false } },
        neverCache = { [BLADE] = true },   -- known only when the test says so
    })
    AHW.Open()
    local got = search(M, BLADE)
    T.eq(got.started, true)
    AHW.Settle()
    T.eq(AHW.Calls("SendSellSearchQuery"), 0, "no search for a key the client doesn't know (it would ignore it)")
    T.eq(AHW.Calls("RequestLoadItemDataByID"), 1, "the item's data asked for")
    T.eq(got.calls, 0)
    AHW.Advance(M.Game.ITEM_WAIT - 1)
    AHW.Cache(BLADE)   -- ITEM_KEY_ITEM_INFO_RECEIVED
    AHW.Settle()
    T.eq(AHW.Calls("SendSellSearchQuery"), 1, "sent once the key info came")
    T.isnil(got.reason)
    T.deq(got.rows, { { key = "15210:-15", base = "15210", unit = 4000, qty = 1 } })
    T.deq(M.Store.Seen(RKEY, "15210:-15"), { min = 4000, t = M.Game.Now(), q = 1 })
    quiet(M)
    T.eq(got.calls, 1, "the give-up timer is gone")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("gives_up_uncached", function()
    local M = load({
        auctions = {
            { itemID = BLADE, count = 1, buyout = 4000, cached = false },
            { itemID = LINEN, count = 1, buyout = 100, cached = false },
        },
        neverCache = { [BLADE] = true, [LINEN] = true },
        missing = { [WOOL] = true },
    })
    local changes = watchChanges(M)
    AHW.Open()
    local got = search(M, BLADE)
    AHW.Settle()
    AHW.Advance(M.Game.ITEM_WAIT - 1)
    T.eq(got.calls, 0, "waits the whole ITEM_WAIT")
    AHW.Advance(1)
    T.eq(got.calls, 1, "then gives up")
    T.isnil(got.rows)
    T.eq(got.reason, "uncached")
    T.eq(AHW.Calls("SendSearchQuery"), 0)
    AHW.Cache(BLADE)   -- too late: nothing listens any more
    AHW.Settle()
    T.eq(got.calls, 1)
    T.eq(AHW.Calls("SendSearchQuery"), 0)
    T.eq(#changes, 0)
    quiet(M)

    -- an item the game says has no data gives up at once
    local gone = search(M, WOOL)
    AHW.Settle()
    T.eq(gone.reason, "uncached", "no ITEM_WAIT for an item that doesn't exist")
    T.eq(AHW.Calls("SendSearchQuery"), 0)
    quiet(M)

    -- so does GET_ITEM_INFO_RECEIVED saying no
    local nope = search(M, LINEN)
    T.eq(nope.calls, 0)
    stub.FireEvent("GET_ITEM_INFO_RECEIVED", LINEN, false)
    T.eq(nope.reason, "uncached")
    T.eq(AHW.Calls("SendSearchQuery"), 0)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- ---------------------------------------------------------------------
-- The AH closing, the ruleset
-- ---------------------------------------------------------------------

T.test("closed_mid_search", function()
    local M = load({
        page = 1,
        auctions = {
            { itemID = BLADE, count = 1, buyout = 3000 },
            { itemID = BLADE, count = 1, buyout = 4000 },
            { itemID = WOOL, count = 1, buyout = 50, cached = false },
        },
        neverCache = { [WOOL] = true },
    })
    local changes = watchChanges(M)
    AHW.Open()

    -- the answer on its way
    local got = search(M, BLADE)
    AHW.Close()
    T.eq(got.calls, 1)
    T.isnil(got.rows)
    T.eq(got.reason, "closed")
    quiet(M)

    -- between pages
    AHW.Open()
    got = search(M, BLADE)
    AHW.Step()   -- page one
    T.eq(AHW.Calls("RequestMoreItemSearchResults"), 1)
    AHW.Close()
    T.eq(got.reason, "closed")
    T.isnil(got.rows)
    quiet(M)

    -- waiting for the item's key info
    AHW.Open()
    local wool = search(M, WOOL)
    AHW.Settle()
    AHW.Close()
    T.eq(wool.calls, 1)
    T.eq(wool.reason, "closed")
    AHW.Cache(WOOL)
    AHW.Settle()
    T.eq(wool.calls, 1, "the closed search stays closed")
    quiet(M)

    -- asked while closed
    local shut = search(M, BLADE)
    T.eq(shut.started, false)
    T.eq(shut.why, "closed")
    T.eq(shut.reason, "closed")

    T.isnil(items(), "nothing kept")
    T.eq(#changes, 0)

    -- the next search works
    AHW.Open()
    got = search(M, BLADE)
    AHW.Settle()
    T.deq(got.rows, { { key = "15210", base = "15210", unit = 3000, qty = 2 } })
    T.eq(#changes, 1)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("no_ruleset_stores_nothing", function()
    local M = load({ commodities = { [LINEN] = true }, auctions = { { itemID = LINEN, count = 20, buyout = 2000 } } },
        { ruleset = false })
    local changes = watchChanges(M)
    AHW.Open()
    local got = search(M, LINEN)
    AHW.Settle()
    T.deq(got.rows, { { key = "2589", base = "2589", unit = 100, qty = 20 } }, "the caller still gets the rows")
    T.eq(got.reason, "noruleset", "and why nothing was kept")
    T.eq(T.count(DaylightUIAuctionDB.rulesets or {}), 0, "no rulesets entry")
    T.eq(#changes, 0)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("ruleset_changed_mid_search", function()
    local M = load({ commodities = { [LINEN] = true }, auctions = { { itemID = LINEN, count = 20, buyout = 2000 } } })
    local changes = watchChanges(M)
    AHW.Open()
    local got = search(M, LINEN)
    AHW.Ruleset("PvP"); stub.FireEvent("GAME_RULES_CHANGED")   -- before the answer
    AHW.Settle()
    T.deq(got.rows, { { key = "2589", base = "2589", unit = 100, qty = 20 } })
    T.eq(got.reason, "ruleset")
    T.isnil(items(), "nothing under the old ruleset")
    T.isnil(DaylightUIAuctionDB.rulesets and DaylightUIAuctionDB.rulesets["US-PvP"]
        and DaylightUIAuctionDB.rulesets["US-PvP"].items, "nor under the new one")
    T.eq(#changes, 0)
    got = search(M, LINEN)
    AHW.Settle()
    T.isnil(got.reason, "the next search stores")
    T.deq(M.Store.Seen("US-PvP", "2589"), { min = 100, t = M.Game.Now(), q = 20 })
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("same_item_twice_is_one_search", function()
    local M = load({ commodities = { [LINEN] = true }, auctions = { { itemID = LINEN, count = 20, buyout = 2000 } } })
    AHW.Open()
    local a, b = search(M, LINEN), search(M, LINEN)
    AHW.Settle()
    T.eq(AHW.Calls("SendSearchQuery"), 1, "one search answers both")
    T.deq(a.rows, b.rows)
    T.truthy(a.rows ~= b.rows and a.rows[1] ~= b.rows[1], "each caller gets its own copy")
    T.eq(a.calls + b.calls, 2)
    T.errors(function() M.Search.Item("2589", function() end) end, "an itemID is a number")
end)

T.test("no_answer_times_out", function()
    local M = load({ commodities = { [LINEN] = true }, auctions = { { itemID = LINEN, count = 20, buyout = 2000 } } })
    AHW.Open()
    local real = C_AuctionHouse.SendSearchQuery
    C_AuctionHouse.SendSearchQuery = function() end   -- the answer never comes
    local got = search(M, LINEN)
    AHW.Advance(M.AH.TIMEOUT)
    T.eq(got.calls, 0, "a first page that never answers is asked once more")
    AHW.Advance(M.AH.LATE + M.AH.TIMEOUT)
    T.eq(got.reason, "timeout", "then it gives up")
    T.isnil(got.rows)
    T.isnil(items())
    quiet(M)
    C_AuctionHouse.SendSearchQuery = real
    got = search(M, LINEN)
    AHW.Settle()
    T.isnil(got.reason, "the next search works")
    T.eq(#got.rows, 1)
end)

-- ---------------------------------------------------------------------
-- One search at a time; cheapest first
-- ---------------------------------------------------------------------

-- Where in the world's call log the first call `name` whose first argument
-- is (or names) itemID is, and the last.
local function callsOf(name, itemID)
    local first, last
    for i, c in ipairs(AHW.state.calls) do
        local a = c.args[1]
        if c.name == name and (a == itemID or (type(a) == "table" and a.itemID == itemID)) then
            first = first or i
            last = i
        end
    end
    return first, last
end

T.test("two_items_are_searched_one_after_another", function()
    -- whether the client keeps results per item or only the latest search's
    -- is a probe question: the second search waits until the first's last
    -- row was read, so either way neither reads the other's results
    local M = load({ commodities = { [LINEN] = true }, page = 2, auctions = {
        { itemID = LINEN, count = 20, buyout = 2000 },
        { itemID = LINEN, count = 5, buyout = 400 },
        { itemID = LINEN, count = 3, buyout = 330 },
        { itemID = WOOL, count = 1, buyout = 700 },
        { itemID = WOOL, count = 2, buyout = 1000 },
    } })
    local changes = watchChanges(M)
    AHW.Open()
    local a, b = search(M, LINEN), search(M, WOOL)
    T.eq(a.started, true)
    T.eq(b.started, true)
    T.eq(AHW.Calls("SendSearchQuery"), 1, "the second waits its turn")
    AHW.Settle()
    local _, lastLinenRow = callsOf("GetCommoditySearchResultInfo", LINEN)
    local woolQuery = callsOf("SendSearchQuery", WOOL)
    T.truthy(lastLinenRow and woolQuery and woolQuery > lastLinenRow,
        "the second item's query goes out after the first's rows were read")
    T.eq(AHW.Calls("SendSearchQuery"), 2)
    T.isnil(a.reason)
    T.isnil(b.reason)
    local linen, wool = M.Store.Seen(RKEY, "2589"), M.Store.Seen(RKEY, "2592")
    T.deq({ linen.min, linen.q, wool.min, wool.q }, { 80, 28, 500, 3 }, "both priced")
    T.deq(changes, { RKEY, RKEY })
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("a_search_that_ends_early_lets_the_next_go", function()
    -- the first item's AH request fails: the one waiting behind it still runs
    local M = load({ commodities = { [LINEN] = true }, auctions = {
        { itemID = LINEN, count = 20, buyout = 2000 },
        { itemID = WOOL, count = 1, buyout = 700 },
    } })
    AHW.Open()
    local real = C_AuctionHouse.SendSearchQuery
    C_AuctionHouse.SendSearchQuery = function(key, ...)
        if key.itemID == LINEN then return end   -- never answered
        return real(key, ...)
    end
    local a, b = search(M, LINEN), search(M, WOOL)
    AHW.Advance(2 * M.AH.TIMEOUT + M.AH.LATE + 1)
    AHW.Settle()
    T.eq(a.reason, "timeout")
    T.isnil(b.reason)
    T.eq(#b.rows, 1)
    C_AuctionHouse.SendSearchQuery = real
    quiet(M)
end)

T.test("searches_ask_cheapest_first", function()
    -- the page cap (MAX_PAGES) keeps the cheapest pages only if the server
    -- sorts by price: asked for explicitly, never left to its default
    local M = load({ auctions = { { itemID = WOOL, count = 1, buyout = 700 } } })
    AHW.Open()
    search(M, WOOL)
    AHW.Settle()
    T.deq(AHW.Log("SendSearchQuery")[1][2], { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } })
    T.eq(Enum.AuctionHouseSortOrder.Price, 0, "the docs' value")
end)

T.test("no_sort_enum_asks_with_no_sorts", function()
    local M = AHW.Mog({
        ah = { auctions = { { itemID = WOOL, count = 1, buyout = 700 } } },
        before = function()
            Enum.AuctionHouseSortOrder = nil
        end,
    })
    AHW.Open()
    local got = search(M, WOOL)
    AHW.Settle()
    T.deq(AHW.Log("SendSearchQuery")[1][2], {})
    T.isnil(got.reason)
end)

T.test("an_item_waiting_for_its_key_info_doesnt_hold_the_line", function()
    -- only the asking and reading go one at a time: waiting for the game to
    -- learn an item runs beside them
    local M = load({ commodities = { [LINEN] = true }, neverCache = { [WOOL] = true }, auctions = {
        { itemID = WOOL, count = 1, buyout = 700, cached = false },
        { itemID = LINEN, count = 20, buyout = 2000 },
    } })
    AHW.Open()
    local a, b = search(M, WOOL), search(M, LINEN)
    AHW.Settle()
    T.eq(b.calls, 1, "the cached item is priced at once")
    T.isnil(b.reason)
    T.eq(a.calls, 0, "the other still waits")
    AHW.Advance(M.Game.ITEM_WAIT)
    T.eq(a.reason, "uncached")
    quiet(M)
end)

-- ---------------------------------------------------------------------
-- The raw auctions
-- ---------------------------------------------------------------------

T.test("search_hands_out_auctions", function()
    local M = load({
        commodities = { [LINEN] = true },
        auctions = {
            { itemID = LINEN, count = 20, buyout = 2000 },   -- 100 each
            { itemID = LINEN, count = 5, buyout = 400 },     -- 80 each
            { itemID = LINEN, count = 3, buyout = 240, mine = true },   -- 80 each too: one price, one row; the player's
            { itemID = BLADE, count = 1, buyout = 3000, minBid = 1500, owner = "Brann", timeLeft = 3 },
            { itemID = BLADE, count = 2, buyout = 10000, minBid = 2000, bid = 2600, owner = "Mira", timeLeft = 1 },
            { itemID = BLADE, count = 1, buyout = 0, minBid = 700, owner = "Tove", timeLeft = 0 },   -- bid only
            { itemID = BLADE, count = 1, buyout = 9000, mine = true },   -- the player's own
        },
    })
    AHW.Open()
    local linen, blade
    M.Search.Item(LINEN, function(rows, reason, auctions) linen = { rows = rows, reason = reason, auctions = auctions } end)
    AHW.Settle()
    local brief = {}
    for i, a in ipairs(linen.auctions) do brief[i] = { unit = a.unit, qty = a.qty, own = a.own } end
    T.deq(brief, { { unit = 80, qty = 8, own = 3 }, { unit = 100, qty = 20, own = 0 } },
        "commodity: one per price, with how many are the player's")

    M.Search.Item(BLADE, function(rows, reason, auctions) blade = { rows = rows, reason = reason, auctions = auctions } end)
    AHW.Settle()
    T.isnil(blade.reason)
    T.eq(#blade.auctions, 4, "one per auction, bid-only included")
    local a, b, c = blade.auctions[1], blade.auctions[2], blade.auctions[4]
    T.eq(blade.auctions[3].own, 1, "the player's own auction says so")
    T.eq(a.own, 0)
    T.truthy(a.auctionID, "the auction id")
    T.eq(a.buyout, 3000)
    T.eq(a.unit, 3000)
    T.eq(a.minBid, 1500)
    T.eq(a.bid, 0)
    T.eq(a.qty, 1)
    T.eq(a.key, "15210")
    T.eq(a.timeLeft, 3)
    T.eq(a.owner, "Brann")
    T.eq(b.buyout, 5000)
    T.eq(b.unit, 5000, "the price of one")
    T.eq(b.qty, 2)
    T.eq(b.bid, 2600)
    T.eq(b.owner, "Mira")
    T.eq(c.buyout, 0, "bid only: never bought")
    T.eq(c.minBid, 700)
    T.eq(c.timeLeft, 0)
    T.eq(c.owner, "Tove")
    T.deq(blade.rows, { { key = "15210", base = "15210", unit = 3000, qty = 4 } }, "rows still skip the bid-only one")
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("search_auctions_are_each_callers_own", function()
    local M = load({ auctions = { { itemID = BLADE, count = 1, buyout = 3000 } } })
    AHW.Open()
    local first, second
    M.Search.Item(BLADE, function(_, _, auctions) first = auctions end)
    M.Search.Item(BLADE, function(_, _, auctions) second = auctions end)
    AHW.Settle()
    T.truthy(first and second)
    T.truthy(first ~= second, "copies")
    first[1].buyout = 1
    T.eq(second[1].buyout, 3000)
    quiet(M)
end)

T.test("search_failure_has_no_auctions", function()
    local M = load({ auctions = { { itemID = BLADE, count = 1, buyout = 3000 } } })
    local rows, reason, auctions = "x", nil, "x"
    M.Search.Item(BLADE, function(r, why, a) rows, reason, auctions = r, why, a end)
    T.isnil(rows)
    T.eq(reason, "closed")
    T.isnil(auctions)
end)


T.test("commodity_steps_keep_sellers_and_time_left", function()
    local M = load({
        auctions = {
            { itemID = LINEN, count = 20, buyout = 2000, owner = "Brann", timeLeftSeconds = 20 * 60 },
            { itemID = LINEN, count = 20, buyout = 2000, owner = "Thrall", timeLeftSeconds = 20 * 60 },
            { itemID = LINEN, count = 10, buyout = 2000, owner = "Jaina", timeLeftSeconds = 5 * 3600 },
            { itemID = LINEN, count = 10, buyout = 3000, owner = "Jaina", timeLeftSeconds = 20 * 3600 },
            { itemID = LINEN, count = 10, buyout = 4000, owner = "Jaina" },
        },
        commodities = { [LINEN] = true },
    })
    AHW.Open()
    local got
    M.Search.Item(LINEN, function(_, _, auctions) got = auctions end)
    AHW.Settle()
    local E = Enum.AuctionHouseTimeLeftBand
    T.eq(got[1].owner, "Brann")
    T.deq(got[1].owners, { "Brann", "Thrall" })
    T.eq(got[1].timeLeft, E.Short)
    T.eq(got[2].timeLeft, E.Long, "Jaina's at 2s")
    T.eq(got[3].timeLeft, E.VeryLong)
    T.isnil(got[4].timeLeft, "the game didn't say")
end)

T.test("an_alt_sharing_a_price_with_strangers_doesnt_make_it_all_yours", function()
    local M = load({
        auctions = {
            { itemID = LINEN, count = 1, buyout = 100, account = true, owner = "Alt" },
            { itemID = LINEN, count = 499, buyout = 49900, owner = "Stranger" },
        },
        commodities = { [LINEN] = true },
    })
    AHW.Open()
    local got
    M.Search.Item(LINEN, function(_, _, auctions) got = auctions end)
    AHW.Settle()
    T.eq(got[1].qty, 500)
    T.eq(got[1].acct, 0, "strangers sell at that price too: it's a price to undercut")
end)

T.test("account_items_are_marked_apart_from_your_own", function()
    local M = load({
        auctions = {
            { itemID = LINEN, count = 20, buyout = 2000, account = true },
            { itemID = LINEN, count = 10, buyout = 1000, mine = true, account = true },
            { itemID = LINEN, count = 10, buyout = 3000 },
            { itemID = BLADE, count = 1, buyout = 900, account = true },
            { itemID = BLADE, count = 1, buyout = 1000, mine = true, account = true },
            { itemID = BLADE, count = 1, buyout = 1100 },
        },
        commodities = { [LINEN] = true },
    })
    AHW.Open()
    local herb, gear
    M.Search.Item(LINEN, function(_, _, auctions) herb = auctions end)
    M.Search.Item(BLADE, function(_, _, auctions) gear = auctions end)
    AHW.Settle()
    T.eq(herb[1].own, 10); T.eq(herb[1].acct, 20, "the units that aren't this character's")
    T.eq(herb[2].acct, 0)
    T.eq(gear[1].own, 0); T.eq(gear[1].acct, 1, "an alt's")
    T.eq(gear[2].own, 1); T.eq(gear[2].acct, 0, "this character's stays own")
    T.eq(gear[3].acct, 0)
end)

T.test("a_later_page_timing_out_keeps_the_pages_read", function()
    local auctions = {}
    for i = 1, 70 do auctions[i] = { itemID = LINEN, count = 1, buyout = 100 + i } end
    local M = load({ auctions = auctions, commodities = { [LINEN] = true }, page = 50, moreEvents = {} })
    AHW.Open()
    local rows, reason, got
    M.Search.Item(LINEN, function(r, why, a) rows, reason, got = r, why, a end)
    AHW.Advance(M.AH.TIMEOUT + 2)
    AHW.Settle()
    T.truthy(rows, "the first page's answer stands")
    T.truthy(#got >= 50)
    T.isnil(reason)
end)

T.test("an_item_slot_comes_from_the_game", function()
    local M = load({})
    C_Item.GetItemInventoryTypeByID = function(id) return id == BLADE and 13 or nil end
    T.eq(M.Search.Slot(BLADE), 13)
    T.isnil(M.Search.Slot(LINEN))
end)

-- ---------------------------------------------------------------------
-- A price check reads the first page; a list sees each page come in
-- ---------------------------------------------------------------------

T.test("one_page_is_enough_for_a_price", function()
    local auctions = {}
    for i = 1, 5 do auctions[#auctions + 1] = { itemID = LINEN, count = 1, buyout = 100 * i } end
    local M = load({ commodities = { [LINEN] = true }, page = 2, auctions = auctions })
    AHW.Open()
    local got = {}
    M.Search.Item(LINEN, function(rows, reason, a) got.rows, got.reason, got.auctions = rows, reason, a end, { pages = 1 })
    AHW.Settle()
    T.eq(AHW.Calls("RequestMoreCommoditySearchResults"), 0, "no second page asked")
    T.eq(got.rows[1].unit, 100, "the cheapest is on the first page")
    T.eq(#got.auctions, 2)
    T.truthy(got.auctions.capped, "it says more were up")
    quiet(M)
end)

T.test("pages_show_as_they_come", function()
    local auctions = {}
    for i = 1, 5 do auctions[#auctions + 1] = { itemID = LINEN, count = 1, buyout = 100 * i } end
    local M = load({ commodities = { [LINEN] = true }, page = 2, auctions = auctions })
    AHW.Open()
    local seen, done = {}, nil
    M.Search.Item(LINEN, function(_, _, a) done = a end,
        { onPage = function(_, a) seen[#seen + 1] = #a end })
    AHW.Settle()
    T.deq(seen, { 2, 4 }, "each page but the last, everything so far")
    T.eq(#done, 5)
    T.falsy(done.capped)
    quiet(M)
end)

T.test("a_search_nobody_wants_stops", function()
    local M = load({ commodities = { [LINEN] = true }, auctions = {
        { itemID = LINEN, count = 20, buyout = 2000 }, { itemID = WOOL, count = 1, buyout = 700 },
    } })
    AHW.Open()
    local a, b = {}, {}
    local function fa(rows) a.rows = rows end
    M.Search.Item(LINEN, fa)
    M.Search.Item(WOOL, function(rows) b.rows = rows end, { priority = true })
    M.Search.Cancel(LINEN, fa)
    AHW.Settle()
    T.isnil(a.rows, "the canceled caller hears nothing")
    T.eq(#b.rows, 1, "the next search ran")
    T.eq(M.Search.Pending(), 0)
    quiet(M)
end)

T.test("an_empty_first_answer_is_asked_again", function()
    local M = load({ commodities = { [LINEN] = true }, emptyOnce = { [LINEN] = true },
        auctions = { { itemID = LINEN, count = 20, buyout = 2000 } } })
    AHW.Open()
    local got = search(M, LINEN)
    AHW.Settle()
    T.eq(AHW.Calls("SendSearchQuery"), 2, "asked once more")
    T.eq(#got.rows, 1, "and found it")
    quiet(M)
end)

T.test("a_refresh_asks_the_held_results_again", function()
    local M = load({ commodities = { [LINEN] = true }, auctions = { { itemID = LINEN, count = 20, buyout = 2000 } } })
    AHW.Open()
    search(M, LINEN)
    AHW.Settle()
    local got = {}
    M.Search.Item(LINEN, function(rows) got.rows = rows end, { refresh = true })
    AHW.Settle()
    T.eq(AHW.Calls("SendSearchQuery"), 1, "no second search")
    T.eq(AHW.Calls("RefreshCommoditySearchResults"), 1)
    T.eq(#got.rows, 1)
    local rows, auctions, age = M.Search.Last(LINEN)
    T.eq(#rows, 1, "the last answer is kept for this visit")
    T.eq(#auctions, 1)
    T.truthy(age >= 0)
    AHW.Close()
    T.isnil((M.Search.Last(LINEN)), "and forgotten when the AH closes")
    quiet(M)
end)
