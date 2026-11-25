local AHW = require("ahworld")
local stub = require("stub")

-- Browse queries (Game/Browse.lua) on the fake auction house: one row per
-- item key from the game's SendBrowseQuery, every page read, the lows
-- recorded under the ruleset the query started in, a drop mid-paging
-- ending it with nothing stored, and the fake's own filtering.

local RUNECLOTH, LINEN, BLADE, CLOAK = 14047, 2589, 15210, 7429
local RKEY = "US-PvE"

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

-- Starts a browse; the returned table fills in when it ends.
local function browse(M, query, tag)
    local got = { calls = 0 }
    query = query or {}
    query.searchString = query.searchString or ""
    query.sorts = query.sorts or {}
    got.started, got.why = M.Browse.Query(query, function(rows, reason)
        got.calls = got.calls + 1
        got.rows, got.reason = rows, reason
    end, tag)
    return got
end

local function names(rows)
    local out = {}
    for i, r in ipairs(rows or {}) do out[i] = r.key end
    return out
end

local function quiet(M)
    AHW.Advance(M.Game.ITEM_WAIT * 2)
    T.eq(AHW.Frame(), 0, "no timer left")
    T.eq(AHW.Waiting(), 0, "no answer coming")
end

local function things(n, extra)
    local auctions = {}
    for i = 1, n do
        auctions[i] = { itemID = 20000 + i, name = "Thing " .. i, count = 1, buyout = 100 + i }
        for k, v in pairs(extra or {}) do auctions[i][k] = v end
    end
    return auctions
end

T.test("items_keyof_itemkey", function()
    local M = load({})
    local key, base = M.Items.KeyOf({ itemID = 7429, itemLevel = 0, itemSuffix = -15, battlePetSpeciesID = 0 })
    T.eq(key, "7429:-15")
    T.eq(base, "7429")
    key, base = M.Items.KeyOf({ itemID = 2589, itemLevel = 5, itemSuffix = 0 })
    T.eq(key, "2589")
    T.eq(base, "2589")
    T.isnil(M.Items.KeyOf({ itemSuffix = 3 }), "no itemID")
    T.isnil(M.Items.KeyOf("2589"), "not a table")
end)

T.test("browse_rows_one_per_item", function()
    local M = load({
        commodities = { [RUNECLOTH] = true, [LINEN] = true },
        auctions = {
            { itemID = RUNECLOTH, name = "Runecloth", count = 20, buyout = 2000 },   -- 100 each
            { itemID = RUNECLOTH, name = "Runecloth", count = 5, buyout = 400 },     -- 80 each: the low
            { itemID = LINEN, name = "Linen Cloth", count = 10, buyout = 100 },
        },
    })
    AHW.Open()
    local got = browse(M, { searchString = "rune" })
    T.eq(got.started, true)
    AHW.Settle()
    T.eq(got.calls, 1)
    T.isnil(got.reason)
    T.eq(#got.rows, 1, "one row for the item")
    local r = got.rows[1]
    T.eq(r.itemID, RUNECLOTH)
    T.eq(r.key, "14047")
    T.eq(r.base, "14047")
    T.eq(r.minPrice, 80, "cheapest unit")
    T.eq(r.qty, 25, "summed")
    T.eq(r.owned, false)
    T.eq(r.itemKey.itemID, RUNECLOTH)
    T.eq(AHW.Calls("SendBrowseQuery"), 1)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("browse_records_lows", function()
    local M = load({
        commodities = { [RUNECLOTH] = true, [LINEN] = true },
        auctions = {
            { itemID = RUNECLOTH, name = "Runecloth", count = 5, buyout = 400 },
            { itemID = LINEN, name = "Linen Cloth", count = 10, buyout = 100 },
        },
    })
    local changes = watchChanges(M)
    AHW.Open()
    local got = browse(M)
    AHW.Settle()
    T.eq(#got.rows, 2)
    local now = M.Game.Now()
    T.eq(M.Store.Min(RKEY, "14047"), 80)
    T.eq(M.Store.Min(RKEY, "2589"), 10)
    T.deq(M.Store.Seen(RKEY, "14047"), { min = 80, t = now, q = 5 })
    T.deq(changes, { RKEY }, "one PricesChanged")
    quiet(M)
end)

T.test("browse_suffix_rows_and_plain_key", function()
    local M = load({
        auctions = {
            { itemID = CLOAK, name = "Cloak of the Monkey", count = 1, buyout = 900, suffix = -15 },
            { itemID = CLOAK, name = "Cloak of the Monkey", count = 1, buyout = 700, suffix = -16 },
        },
    })
    AHW.Open()
    local got = browse(M)
    AHW.Settle()
    T.deq(names(got.rows), { "7429:-16", "7429:-15" }, "one row per suffix, cheapest first")
    T.eq(got.rows[1].base, "7429")
    T.eq(M.Store.Min(RKEY, "7429:-15"), 900)
    T.eq(M.Store.Min(RKEY, "7429"), 700, "the plain key holds the cheapest of all")
    quiet(M)
end)

T.test("browse_pages_until_full", function()
    local M = load({ page = 50, auctions = things(120) })
    AHW.Open()
    local got = browse(M)
    AHW.Step()
    T.eq(got.calls, 0, "not done on the first page")
    AHW.Settle()
    T.eq(got.calls, 1)
    T.eq(#got.rows, 120)
    T.eq(AHW.Calls("SendBrowseQuery"), 1)
    T.eq(AHW.Calls("RequestMoreBrowseResults"), 2, "three pages")
    T.eq(#AHW.state.searches, 1, "one search counted")
    T.eq(M.Store.Min(RKEY, "20120"), 220)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("browse_pages_on_either_event", function()
    for _, events in ipairs({ { "added" }, { "updated" }, { "updated", "added" } }) do
        local M = load({ page = 3, moreEvents = events, auctions = things(7) })
        AHW.Open()
        local got = browse(M)
        AHW.Settle()
        T.eq(got.calls, 1, table.concat(events, ","))
        T.eq(#got.rows, 7, table.concat(events, ","))
        quiet(M)
    end
end)

T.test("browse_pages_are_capped", function()
    local M = load({ page = 1, auctions = things(60) })
    AHW.Open()
    local got = browse(M)
    AHW.Settle()
    T.eq(#got.rows, M.Browse.MAX_PAGES)
    T.eq(AHW.Calls("RequestMoreBrowseResults"), M.Browse.MAX_PAGES - 1)
    quiet(M)
end)

T.test("browse_reads_rows_in_slices", function()
    local M = load({ page = 50, auctions = things(30) })
    M.Game.SLICE = 10
    AHW.Open()
    local got = browse(M)
    AHW.Step()   -- the answer, and a frame: the first ten
    T.eq(got.calls, 0, "rows are read a frame at a time")
    AHW.Frame()
    T.eq(got.calls, 0)
    AHW.Frame()
    T.eq(got.calls, 1, "three slices of ten")
    T.eq(#got.rows, 30)
    quiet(M)
end)

-- A frame stops after SLICE_MS of slow rows, not only after SLICE of them.
T.test("browse_slow_rows_end_the_frame_early", function()
    local M = load({ page = 50, auctions = things(30) })
    local was, clock = _G.debugprofilestop, 0
    _G.debugprofilestop = function() clock = clock + 1; return clock end   -- every look at the clock: 1 ms later
    AHW.Open()
    local got = browse(M)
    AHW.Step()   -- the answer, and a frame
    T.eq(got.calls, 0, "30 rows of 1 ms don't fit one frame")
    _G.debugprofilestop = was
    AHW.Settle()
    T.eq(got.calls, 1)
    T.eq(#got.rows, 30)
    quiet(M)
end)

T.test("browse_filters_reach_server", function()
    local M = load({
        auctions = {
            { itemID = BLADE, name = "Dragon Blade", count = 1, buyout = 900, level = 40, quality = 3,
              classID = 2, subClassID = 7, inventoryType = 13 },
        },
    })
    AHW.Open()
    local query = {
        searchString = "dragon", minLevel = 30, maxLevel = 50,
        filters = { Enum.AuctionHouseFilter.UsableOnly, Enum.AuctionHouseFilter.RareQuality },
        itemClassFilters = { { classID = 2, subClassID = 7, inventoryType = 13 } },
    }
    local got = browse(M, query)
    AHW.Settle()
    local sent = AHW.Log("SendBrowseQuery")
    T.eq(#sent, 1)
    local q = sent[1][1]
    T.eq(q.searchString, "dragon")
    T.eq(q.minLevel, 30)
    T.eq(q.maxLevel, 50)
    T.deq(q.filters, { Enum.AuctionHouseFilter.UsableOnly, Enum.AuctionHouseFilter.RareQuality })
    T.deq(q.itemClassFilters, { { classID = 2, subClassID = 7, inventoryType = 13 } })
    T.eq(#got.rows, 1, "and it matches")
    quiet(M)
end)

-- The fake's own matching, pinned: later tests lean on it.
T.test("fake_browse_filters", function()
    local M = load({
        auctions = {
            { itemID = 1, name = "Iron Sword", count = 1, buyout = 100, level = 10, quality = 1, classID = 2, subClassID = 7, inventoryType = 13 },
            { itemID = 2, name = "Iron Sword of Doom", count = 1, buyout = 200, level = 20, quality = 3, classID = 2, subClassID = 7, inventoryType = 13 },
            { itemID = 3, name = "Plate Helm", count = 1, buyout = 300, level = 30, quality = 4, classID = 4, subClassID = 4, inventoryType = 1, usable = false },
            { itemID = 4, name = "Linen Cloth", count = 5, buyout = 50, level = 1, quality = 1, classID = 7, subClassID = 5, inventoryType = 0 },
        },
        commodities = { [4] = true },
    })
    AHW.Open()
    local function ids(query)
        local got = browse(M, query)
        AHW.Settle()
        local out = {}
        for i, r in ipairs(got.rows) do out[i] = r.itemID end
        table.sort(out)
        return out
    end
    T.deq(ids({}), { 1, 2, 3, 4 }, "no filter: everything")
    T.deq(ids({ searchString = "IRON" }), { 1, 2 }, "substring, any case")
    local E = Enum.AuctionHouseFilter
    local ALL = { E.PoorQuality, E.CommonQuality, E.UncommonQuality, E.RareQuality, E.EpicQuality, E.LegendaryQuality }
    T.deq(ids({ searchString = "iron sword", filters = { E.ExactMatch } }), {}, "the game's ExactMatch finds nothing")
    T.deq(ids({ minLevel = 15 }), { 2, 3 })
    T.deq(ids({ maxLevel = 15 }), { 1, 4 })
    T.deq(ids({ minLevel = 10, maxLevel = 20 }), { 1, 2 })
    T.deq(ids({ filters = { E.RareQuality } }), { 2 }, "a quality")
    T.deq(ids({ filters = { E.CommonQuality, E.EpicQuality } }), { 1, 3, 4 }, "qualities add up")
    T.deq(ids({ filters = { E.UsableOnly } }), {}, "filters with no quality find nothing")
    ALL[#ALL + 1] = E.UsableOnly
    T.deq(ids({ filters = ALL }), { 1, 2, 4 })
    T.deq(ids({ itemClassFilters = { { classID = 2 } } }), { 1, 2 }, "a class")
    T.deq(ids({ itemClassFilters = { { classID = 4, subClassID = 4, inventoryType = 1 } } }), { 3 })
    T.deq(ids({ itemClassFilters = { { classID = 2, subClassID = 8 } } }), {}, "the wrong subclass")
    T.deq(ids({ itemClassFilters = { { classID = 7 }, { classID = 4 } } }), { 3, 4 }, "classes add up")
    T.errors(function() C_AuctionHouse.SendBrowseQuery({}) end, "a query needs its searchString")
    quiet(M)
end)

T.test("browse_dropped", function()
    local M = load({ page = 50, auctions = things(120) })
    local changes = watchChanges(M)
    AHW.Open()
    local got = browse(M)
    AHW.Step()   -- the first page is in; the next one asked
    T.eq(got.calls, 0)
    M.AH.Drop("search")
    T.eq(got.calls, 1)
    T.isnil(got.rows)
    T.eq(got.reason, "dropped")
    AHW.Settle()
    T.eq(got.calls, 1, "heard once")
    T.isnil(M.Store.Min(RKEY, "20001"), "nothing recorded")
    T.eq(#changes, 0)
    quiet(M)

    -- a drop while it waits in line behind another
    local first = browse(M)
    local second = browse(M)
    M.AH.Drop("search")
    T.eq(first.reason, "dropped")
    T.eq(second.reason, "dropped")
    T.eq(second.calls, 1)
    AHW.Settle()
    T.eq(AHW.Calls("SendBrowseQuery"), 2, "the second never asked")
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("browse_tag_is_the_callers", function()
    local M = load({ auctions = { { itemID = LINEN, name = "Linen Cloth", count = 1, buyout = 100 } } })
    AHW.Open()
    local got = browse(M, nil, "pick")
    M.AH.Drop("search")
    T.eq(got.calls, 0, "another tag is not dropped")
    AHW.Settle()
    T.eq(#got.rows, 1)
    got = browse(M, nil, "pick")
    M.AH.Drop("pick")
    T.eq(got.reason, "dropped")
    AHW.Settle()
    quiet(M)
end)

T.test("browse_one_at_a_time", function()
    local auctions = things(6)
    for i, a in ipairs(auctions) do a.name = (i <= 3 and "Alpha " or "Beta ") .. i end
    local M = load({ page = 2, auctions = auctions })
    AHW.Open()
    local a = browse(M, { searchString = "alpha" })
    local b = browse(M, { searchString = "beta" })
    AHW.Settle()
    T.eq(a.calls, 1)
    T.eq(b.calls, 1)
    T.deq(names(a.rows), { "20001", "20002", "20003" }, "the first one's pages are all its own")
    T.deq(names(b.rows), { "20004", "20005", "20006" })
    local sent = AHW.Log("SendBrowseQuery")
    T.eq(#sent, 2)
    T.eq(sent[1][1].searchString, "alpha")
    T.eq(sent[2][1].searchString, "beta")
    quiet(M)
end)

T.test("browse_closed", function()
    local M = load({ page = 2, auctions = things(6) })
    local changes = watchChanges(M)

    local got = browse(M)
    T.eq(got.started, false)
    T.eq(got.why, "closed")
    T.eq(got.calls, 1)
    T.eq(got.reason, "closed")

    AHW.Open()
    got = browse(M)
    AHW.Step()
    AHW.Close()
    T.eq(got.reason, "closed")
    T.isnil(got.rows)

    AHW.Open()
    got = browse(M)
    local queued = browse(M)
    AHW.Close()
    T.eq(got.reason, "closed")
    T.eq(queued.reason, "closed")
    T.eq(queued.calls, 1)

    -- while its rows are read
    local m2 = load({ page = 50, auctions = things(6) })
    m2.Game.SLICE = 2
    AHW.Open()
    local reading = browse(m2)
    AHW.Step()
    AHW.Close()
    AHW.Settle()
    T.eq(reading.calls, 1)
    T.eq(reading.reason, "closed")
    T.isnil(reading.rows)
    T.eq(#changes, 0)
    quiet(m2)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("browse_no_ruleset_and_changed_ruleset", function()
    local spec = { auctions = { { itemID = LINEN, name = "Linen Cloth", count = 1, buyout = 100 } } }
    local M = load(spec, { ruleset = false })
    local changes = watchChanges(M)
    AHW.Open()
    local got = browse(M)
    AHW.Settle()
    T.eq(got.reason, "noruleset")
    T.eq(#got.rows, 1, "rows still returned")
    T.eq(#changes, 0)

    M = load(spec)
    changes = watchChanges(M)
    AHW.Open()
    got = browse(M)
    AHW.Ruleset("PvP"); stub.FireEvent("GAME_RULES_CHANGED")   -- before the answer
    AHW.Settle()
    T.eq(got.reason, "ruleset")
    T.eq(#got.rows, 1)
    T.eq(#changes, 0)
    T.isnil(M.Store.Min(RKEY, "2589"))
    quiet(M)
end)

T.test("browse_failure_and_timeout", function()
    local M = load({ auctions = { { itemID = LINEN, name = "Linen Cloth", count = 1, buyout = 100 } } })
    AHW.Open()
    local got = browse(M)
    stub.FireEvent("AUCTION_HOUSE_BROWSE_FAILURE")
    T.eq(got.calls, 1)
    T.isnil(got.rows)
    T.eq(got.reason, "error")
    AHW.Settle()
    quiet(M)

    M = load({ auctions = { { itemID = LINEN, name = "Linen Cloth", count = 1, buyout = 100 } } })
    AHW.Open()
    local real = C_AuctionHouse.SendBrowseQuery
    C_AuctionHouse.SendBrowseQuery = function() end   -- the answer never comes
    got = browse(M)
    AHW.Advance(M.AH.TIMEOUT + 1)
    T.isnil(got.reason, "a first page that never answers is asked once more")
    AHW.Advance(M.AH.LATE + M.AH.TIMEOUT)
    T.eq(got.reason, "timeout")
    T.isnil(got.rows)
    C_AuctionHouse.SendBrowseQuery = real
    AHW.Settle()
    quiet(M)
end)

T.test("browse_shows_each_page_as_it_comes", function()
    local M = load({ page = 3, auctions = things(7) })
    AHW.Open()
    local pages = {}
    local got = {}
    M.Browse.Query({ searchString = "" }, function(rows, reason) got.rows, got.reason = rows, reason end, nil,
        function(fresh) pages[#pages + 1] = #fresh end)
    AHW.Settle()
    T.deq(pages, { 3, 3 }, "the new rows of each page but the last")
    T.eq(#got.rows, 7)
    T.truthy(AHW.Calls("GetBrowseResults") <= 2, "added rows come with their event: " .. AHW.Calls("GetBrowseResults"))
    quiet(M)
end)

T.test("browse_counts_as_a_search", function()
    local M = load({ auctions = { { itemID = LINEN, name = "Linen Cloth", count = 1, buyout = 100 } } })
    AHW.Open()
    local done = 0
    for _ = 1, 101 do
        M.Browse.Query({ searchString = "", sorts = {} }, function() done = done + 1 end)
    end
    AHW.Advance(30)
    T.eq(AHW.Calls("SendBrowseQuery"), 100, "the 101st waits for the minute")
    T.eq(AHW.Calls("Dropped"), 0, "nothing sent into the limit")
    AHW.Advance(40)
    T.eq(done, 101)
    T.eq(AHW.Calls("Dropped"), 0)
end)

T.test("browse_started_from_a_dropped_callback_goes_out", function()
    local M = load({ page = 2, auctions = things(5) })
    AHW.Open()
    local second
    local first = { calls = 0 }
    M.Browse.Query({ searchString = "", sorts = {} }, function(rows, reason)
        first.calls, first.reason = first.calls + 1, reason
        second = browse(M)   -- the same tag, from inside the callback
    end)
    AHW.Step()
    M.AH.Drop("search")
    T.eq(first.reason, "dropped")
    T.truthy(second, "asked again")
    T.eq(second.started, true)
    T.eq(second.calls, 0, "not dropped by the drop that made it")
    AHW.Settle()
    T.eq(second.calls, 1)
    T.isnil(second.reason)
    T.eq(#second.rows, 5)
    T.eq(AHW.Calls("SendBrowseQuery"), 2)
    quiet(M)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("browse_counts_the_list_only_when_it_has_to", function()
    local M = load({ page = 3, auctions = things(9) })
    AHW.Open()
    local got = browse(M)
    AHW.Settle()
    T.eq(#got.rows, 9)
    -- the first answer, two more pages (added + updated each), then one read: never more
    T.truthy(AHW.Calls("GetBrowseResults") <= 1 + 2 * 2 + 1, "calls: " .. AHW.Calls("GetBrowseResults"))
    quiet(M)
end)

-- The game's own frame searches the player's favorites as it shows
-- (Blizzard_AuctionHouseFrame.lua OnShow, lines 396-398): the addon's first
-- browse right after opening shows only its own items, whichever order the
-- game's answer and its throttle events come in.
for _, first in ipairs({ false, true }) do
    T.test("first_browse_after_open_is_only_ours" .. (first and "_response_first" or ""), function()
        local M = load({
            commodities = { [RUNECLOTH] = true, [LINEN] = true },
            favorites = { LINEN },
            responseFirst = first,
            auctions = {
                { itemID = RUNECLOTH, name = "Runecloth", count = 5, buyout = 400 },
                { itemID = LINEN, name = "Linen Cloth", count = 10, buyout = 100 },
            },
        })
        AHW.Open()
        T.eq(AHW.Calls("SearchForFavorites"), 1, "the game's frame asked for its favorites")
        local got = browse(M, { searchString = "rune" })
        AHW.Settle()
        T.deq(names(got.rows), { "14047" }, "only the query's own items")
        T.eq(AHW.Calls("SendBrowseQuery"), 1)
        quiet(M)
        T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    end)
end

T.test("a_later_page_timing_out_keeps_the_pages_read", function()
    local auctions = {}
    for i = 1, 70 do auctions[i] = { itemID = 30000 + i, name = "Thing " .. i, count = 1, buyout = 100 + i } end
    local M = load({ auctions = auctions, page = 50, moreEvents = {} })
    AHW.Open()
    local rows, reason
    M.Browse.Query({ searchString = "Thing", sorts = {}, filters = {} }, function(r, why) rows, reason = r, why end)
    AHW.Advance(M.AH.TIMEOUT + 2)
    AHW.Settle()
    T.truthy(rows, "the first page's answer stands")
    T.truthy(#rows >= 50)
    T.isnil(reason)
end)

T.test("a_capped_browse_says_how_many_it_read", function()
    local M = load({ page = 1, auctions = things(60) })
    AHW.Open()
    local got = {}
    M.Browse.Query({ searchString = "", sorts = {} }, function(rows, reason, capped)
        got.rows, got.reason, got.capped = rows, reason, capped
    end)
    AHW.Settle()
    T.eq(#got.rows, M.Browse.MAX_PAGES)
    T.isnil(got.reason)
    T.eq(got.capped, M.Browse.MAX_PAGES, "more were up than it read")
    local all = {}
    M.Browse.Query({ searchString = "Thing 1", sorts = {} }, function(rows, reason, capped) all.rows, all.capped = rows, capped end)
    AHW.Settle()
    T.truthy(all.rows and #all.rows > 0 and #all.rows < M.Browse.MAX_PAGES)
    T.isnil(all.capped)
    quiet(M)
end)
