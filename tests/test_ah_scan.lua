local AHW = require("ahworld")
local stub = require("stub")

-- The full scan (Game/Replicate.lua, Prices/Scan.lua) on the fake auction
-- house: only on request, every row priced once per key, bad rows ignored,
-- uncached items waited for (never forever), sliced per frame, nothing kept
-- when the AH closes, its progress for the window's card.

local LINEN, WOOL, SILK, BLADE = 2589, 2592, 4306, 15210
local RKEY = "US-PvE"

-- A fresh addon in the realm "Forever" (US). ruleset = false: not known.
-- The sentences the scan ended with (ScanEnded), for this load.
local ended = {}

local function load(auctions, opts)
    opts = opts or {}
    local M = AHW.Mog({
        ruleset = opts.ruleset,
        ah = { auctions = auctions or {}, neverCache = opts.neverCache, missing = opts.missing,
               itemSpacing = opts.itemSpacing, dropAsks = opts.dropAsks, staleRows = opts.staleRows, replicateCooldown = opts.replicateCooldown,
               replicateLate = opts.replicateLate, replicateEarly = opts.replicateEarly,
               replicateBlank = opts.replicateBlank },
        before = function()
        end,
    })
    ended = {}
    M.On("ScanEnded", function(_, text) ended[#ended + 1] = text end)
    -- the list holds still here; only the tests about a late list wait for it
    if not opts.settles then M.Replicate.SETTLE, M.Replicate.EMPTY_WAIT = 0, 0 end
    return M
end

-- How many of them contain `text`.
local function said(text)
    local n = 0
    for _, m in ipairs(ended) do
        if string.find(m, text, 1, true) then n = n + 1 end
    end
    return n
end

-- Counts PricesChanged, with the keys it carried.
local function watchChanges(M)
    local seen = {}
    M.On("PricesChanged", function(rkey) seen[#seen + 1] = rkey end)
    return seen
end

-- n rows over `distinct` items (10001 ...), each 1 for 100c.
local function many(n, distinct)
    local out = {}
    for i = 1, n do out[i] = { itemID = 10000 + ((i - 1) % distinct) + 1, count = 1, buyout = 100 } end
    return out
end

local function items(M)
    local data = DaylightUIAuctionDB.rulesets and DaylightUIAuctionDB.rulesets[RKEY]
    return data and data.items
end

-- ---------------------------------------------------------------------
-- Pricing
-- ---------------------------------------------------------------------

T.test("full_scan_prices_everything", function()
    local M = load({
        { itemID = LINEN, count = 20, buyout = 2000 },   -- 100 each
        { itemID = LINEN, count = 5, buyout = 400 },     -- 80 each: the low
        { itemID = WOOL, count = 10, buyout = 3001 },    -- 300.1 -> 300
        { itemID = SILK, count = 1, buyout = 999 },
    })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(AHW.Calls("ReplicateItems"), 0, "opening never scans on its own")
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    local now = M.Game.Now()
    T.deq(M.Store.Seen(RKEY, "2589"), { min = 80, t = now, q = 25 }, "lowest unit, summed qty")
    T.deq(M.Store.Seen(RKEY, "2592"), { min = 300, t = now, q = 10 }, "copper floored")
    T.deq(M.Store.Seen(RKEY, "4306"), { min = 999, t = now, q = 1 })
    T.eq(M.Store.Market(RKEY, "2589", now), 80)
    T.deq(M.Store.Lows(RKEY, "2589"), { M.Market.Day(now), 80 }, "one daily low")
    T.eq(M.Store.FullScanAt(RKEY), now)
    T.deq(changes, { RKEY }, "one PricesChanged")
    T.eq(said("Full scan done: 3 items priced."), 1)
    T.eq(AHW.Calls("ReplicateItems"), 1)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- A crate's bundle lines name their items, and the game finds a name only
-- for an item it loaded this session: the scan keeps each name it read.
T.test("full_scan_keeps_item_names", function()
    local M = load({ { itemID = LINEN, count = 20, buyout = 2000 } })
    AHW.Open()
    M.Scan.Full()
    AHW.Settle()
    local name = C_AuctionHouse.GetReplicateItemInfo(0)
    T.truthy(type(name) == "string" and name ~= "", "the fake scan has a name")
    T.eq(M.Items.Names()[name:lower()], LINEN)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("bad_rows_are_ignored", function()
    local M = load({
        { itemID = LINEN, count = 5, buyout = 0, minBid = 50 },   -- bid only
        { itemID = WOOL, count = 0, buyout = 500 },               -- count 0
        { itemID = nil, count = 1, buyout = 100 },                -- no item
        { itemID = SILK, count = 1, buyout = 100 },               -- a deleted item
        { itemID = BLADE, count = 1, buyout = 700 },              -- the one good row
    }, { missing = { [SILK] = true } })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.isnil(M.Store.Seen(RKEY, "2589"), "bid only")
    T.isnil(M.Store.Seen(RKEY, "2592"), "count 0")
    T.isnil(M.Store.Seen(RKEY, "4306"), "non-existent item")
    T.deq(M.Store.Seen(RKEY, "15210"), { min = 700, t = M.Game.Now(), q = 1 })
    T.eq(T.count(items(M)), 1, "nothing else stored")
    T.eq(#changes, 1)
    T.eq(said("Full scan done: 1 item priced."), 1)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("suffix_rows_record_both_keys", function()
    local M = load({
        { itemID = BLADE, count = 1, buyout = 5000, suffix = -15 },
        { itemID = BLADE, count = 1, buyout = 4000, suffix = -15 },
        { itemID = BLADE, count = 1, buyout = 3000, suffix = -16 },
    })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    local now = M.Game.Now()
    T.deq(M.Store.Seen(RKEY, "15210:-15"), { min = 4000, t = now, q = 2 })
    T.deq(M.Store.Seen(RKEY, "15210:-16"), { min = 3000, t = now, q = 1 })
    T.deq(M.Store.Seen(RKEY, "15210"), { min = 3000, t = now, q = 3 }, "the base: cheapest of every suffix, all of them counted")
    T.eq(T.count(items(M)), 3)
    T.eq(said("Full scan done: 1 item priced."), 1, "one item, however many suffixes")
end)

-- ---------------------------------------------------------------------
-- Items the game doesn't know yet
-- ---------------------------------------------------------------------

T.test("uncached_gear_is_waited_for", function()
    -- cloth can't carry a suffix: priced by its itemID at once, no load asked;
    -- the blade can, so its link is waited for
    local M = load({
        { itemID = WOOL, count = 10, buyout = 3000, cached = false },
        { itemID = WOOL, count = 2, buyout = 500, cached = false },
        { itemID = BLADE, count = 1, buyout = 4000, suffix = -15, cached = false },
        { itemID = LINEN, count = 20, buyout = 2000 },
    })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    local now = M.Game.Now()
    T.eq(AHW.Calls("RequestLoadItemDataByID"), 1, "only the gear is loaded")
    T.deq(M.Store.Seen(RKEY, "2592"), { min = 250, t = now, q = 12 }, "the cloth priced without its data")
    T.deq(M.Store.Seen(RKEY, "15210:-15"), { min = 4000, t = now, q = 1 }, "the link after the load carries the suffix")
    T.deq(M.Store.Seen(RKEY, "15210"), { min = 4000, t = now, q = 1 })
    T.deq(M.Store.Seen(RKEY, "2589"), { min = 100, t = now, q = 20 })
    T.eq(#changes, 1)
    -- nothing left listening: a later load or a long wait changes nothing
    AHW.Cache(WOOL)
    AHW.Advance(M.Game.ITEM_WAIT * 2)
    T.eq(#changes, 1, "no second PricesChanged")
    T.eq(said("Full scan done"), 1)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("uncached_items_give_up", function()
    local M = load({
        { itemID = WOOL, count = 10, buyout = 3000, cached = false, classID = 4 },
        { itemID = LINEN, count = 20, buyout = 2000 },
    }, { neverCache = { [WOOL] = true } })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(#changes, 0, "still waiting for the item")
    T.eq(select(2, M.Scan.Full()), "A full scan is already running.")
    AHW.Advance(M.Game.ITEM_WAIT - 1)
    T.eq(#changes, 0, "waits the whole ITEM_WAIT")
    AHW.Advance(1)
    T.eq(#changes, 1, "then gives up and finishes")
    T.isnil(M.Store.Seen(RKEY, "2592"), "the unknown item is skipped")
    T.deq(M.Store.Seen(RKEY, "2589"), { min = 100, t = M.Game.Now(), q = 20 },
        "the rest priced, stamped when the scan finished")
    T.eq(said("Full scan done: 1 item priced, 1 skipped (the game hadn't loaded it; scan again later)."), 1,
        "the skipped item is counted")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- n uncached pieces of gear (20001 ...), one row each at 100c.
local function cold(n, first)
    local out = {}
    for i = 1, n do out[i] = { itemID = (first or 20000) + i, count = 1, buyout = 100, cached = false, classID = 4 } end
    return out
end

T.test("a_cold_cache_is_waited_for_while_items_keep_coming", function()
    -- a first scan: 1000 items the game doesn't know, loading one per 0.05 s
    -- (50 s in all): none is given up while loads keep arriving
    local M = load(cold(1000), { itemSpacing = 0.05 })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(AHW.Calls("RequestLoadItemDataByID"), 1000)
    T.eq(T.count(items(M)), 1000, "every item priced")
    T.eq(#changes, 1)
    T.eq(said("Full scan done: 1,000 items priced."), 1, "nothing skipped")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("a_stalled_cache_gives_up_after_ten_quiet_seconds", function()
    -- four items load 6 s apart (each gap under ITEM_WAIT), the fifth never:
    -- the wait ends ITEM_WAIT after the last load, not ITEM_WAIT after the first ask
    local auctions = cold(4)
    auctions[5] = { itemID = WOOL, count = 1, buyout = 100, cached = false, classID = 4 }
    local M = load(auctions, { itemSpacing = 6, neverCache = { [WOOL] = true } })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Step()   -- the list, and the rows read: five loads asked
    local t0 = GetTime()
    T.eq(AHW.Calls("RequestLoadItemDataByID"), 5)
    -- the loads arrive at +0.25, 6.25, 12.25 and 18.25 s; then silence
    AHW.Advance(t0 + 18.25 + M.Game.ITEM_WAIT - 0.1 - GetTime())
    T.eq(#changes, 0, "still waiting: the last load was under ITEM_WAIT ago")
    T.eq(T.count(items(M) or {}), 0, "nothing saved yet")
    AHW.Advance(0.2)
    T.eq(#changes, 1, "ITEM_WAIT of silence: gives up")
    T.eq(T.count(items(M)), 4, "the four that came are priced")
    T.isnil(M.Store.Seen(RKEY, "2592"))
    T.eq(said("Full scan done: 4 items priced, 1 skipped (the game hadn't loaded it; scan again later)."), 1)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("a_long_cold_cache_is_waited_out", function()
    -- forty pieces of gear load 5 s apart (200 s in all): loads keep coming,
    -- so none is given up, however long it takes
    local M = load(cold(40), { itemSpacing = 5 })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Step()
    AHW.Advance(150)
    T.eq(#changes, 0, "still loading at 150 s")
    AHW.Advance(60)
    T.eq(#changes, 1)
    T.eq(T.count(items(M)), 40, "every item priced")
    T.eq(said("Full scan done: 40 items priced."), 1, "nothing skipped")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("a_cold_cache_of_goods_is_priced_without_loading", function()
    -- a first scan on a big AH: 7,000 trade goods, potions and recipes the
    -- game hasn't loaded and never will in time; none can carry a suffix,
    -- so the row's itemID prices it and nothing is asked or skipped
    local auctions = {}
    local never = {}
    for i = 1, 7000 do
        auctions[i] = { itemID = 50000 + i, count = 5, buyout = 500, cached = false, classID = (i % 3 == 0) and 9 or 7 }
        never[50000 + i] = true
    end
    local M = load(auctions, { neverCache = never })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(AHW.Calls("RequestLoadItemDataByID"), 0, "nothing to load")
    T.eq(T.count(items(M)), 7000)
    T.deq(M.Store.Seen(RKEY, "50001"), { min = 100, t = M.Game.Now(), q = 5 })
    T.eq(said("Full scan done: 7,000 items priced."), 1, "nothing skipped")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("an_item_whose_load_was_let_fall_is_asked_again", function()
    -- the client drops the first two asks for one piece of gear (Auctionator
    -- asks again for anything still loading): it is asked again when
    -- nothing has come for a while, and priced
    local M = load({
        { itemID = BLADE, count = 1, buyout = 4000, cached = false, classID = 2 },
        { itemID = LINEN, count = 20, buyout = 2000 },
    }, { dropAsks = { [BLADE] = 2 } })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    AHW.Advance(M.Game.ITEM_WAIT + 1)
    AHW.Settle()
    T.truthy(AHW.Calls("RequestLoadItemDataByID") >= 3, "asked again")
    T.eq(said("Full scan done: 2 items priced."), 1, "nothing skipped")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- A full scan that never ended: an item arrived, its row still read as not
-- known, so it was waited for again, asked for again two seconds later, and
-- each answer started the quiet clock over.
T.test("a_row_still_unknown_after_its_item_arrived_is_priced_by_its_id", function()
    local M = load({
        { itemID = BLADE, count = 1, buyout = 4000, cached = false, classID = 2 },
        { itemID = LINEN, count = 20, buyout = 2000 },
    }, { staleRows = { [BLADE] = true } })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    for _ = 1, 10 do
        AHW.Settle()
        AHW.Advance(M.Game.ITEM_WAIT)
    end
    AHW.Settle()
    T.eq(said("Full scan done: 2 items priced."), 1, "the scan ends with the blade priced")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("the_done_line_has_a_sentence_for_every_count", function()
    -- whole sentences, never glued: one and many, priced and skipped
    local cases = {
        { 1, 0, "Full scan done: 1 item priced." },
        { 3, 0, "Full scan done: 3 items priced." },
        { 1, 1, "Full scan done: 1 item priced, 1 skipped (the game hadn't loaded it; scan again later)." },
        { 1, 2, "Full scan done: 1 item priced, 2 skipped (the game hadn't loaded them; scan again later)." },
        { 3, 1, "Full scan done: 3 items priced, 1 skipped (the game hadn't loaded it; scan again later)." },
    }
    for _, c in ipairs(cases) do
        local auctions = {}
        for i = 1, c[1] do auctions[#auctions + 1] = { itemID = 30000 + i, count = 1, buyout = 100 } end
        local never = {}
        for i = 1, c[2] do
            auctions[#auctions + 1] = { itemID = 40000 + i, count = 1, buyout = 100, cached = false, classID = 4 }
            never[40000 + i] = true
        end
        local M = load(auctions, { neverCache = never })
        AHW.Open()
        T.eq(M.Scan.Full(), true)
        AHW.Settle()
        AHW.Advance(M.Game.ITEM_WAIT + 1)
        T.eq(said(c[3]), 1, c[3])
    end
end)

T.test("rows_of_an_item_that_cant_load_are_skipped", function()
    -- one WOOL row in the first slice, another after the game says no data is coming
    local auctions = { { itemID = WOOL, count = 10, buyout = 3000, cached = false, classID = 4 } }
    for _, a in ipairs(many(300, 300)) do auctions[#auctions + 1] = a end
    auctions[#auctions + 1] = { itemID = WOOL, count = 5, buyout = 1000, cached = false, classID = 4 }
    local M = load(auctions, { neverCache = { [WOOL] = true } })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Step()   -- the list and the first slice: the first WOOL row waits
    T.eq(AHW.Calls("RequestLoadItemDataByID"), 1)
    stub.FireEvent("ITEM_DATA_LOAD_RESULT", WOOL, false)
    AHW.Settle()
    T.isnil(M.Store.Seen(RKEY, "2592"), "neither row priced")
    T.eq(AHW.Calls("RequestLoadItemDataByID"), 1, "not asked again")
    T.eq(#changes, 1, "the scan still finishes, without waiting ITEM_WAIT")
    T.eq(said("Full scan done: 300 items priced."), 1)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("sub_copper_rows_are_skipped", function()
    local M = load({
        { itemID = LINEN, count = 200, buyout = 150 },   -- under a copper each
        { itemID = LINEN, count = 20, buyout = 2000 },
        { itemID = BLADE, count = 2, buyout = 1, suffix = -15 },
        { itemID = BLADE, count = 1, buyout = 3000, suffix = -15 },
    })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    local now = M.Game.Now()
    T.deq(M.Store.Seen(RKEY, "2589"), { min = 100, t = now, q = 20 }, "priced from the normal stack")
    T.deq(M.Store.Seen(RKEY, "15210:-15"), { min = 3000, t = now, q = 1 })
    T.deq(M.Store.Seen(RKEY, "15210"), { min = 3000, t = now, q = 1 }, "the base too")
    T.eq(said("Full scan done: 2 items priced."), 1)
end)

-- ---------------------------------------------------------------------
-- Smooth: slices per frame
-- ---------------------------------------------------------------------

T.test("slices_per_frame", function()
    local M = load(many(600, 300))
    AHW.Open()
    local got, why
    T.eq(M.Replicate.Start(function(rows, reason) got, why = rows, reason end), true)
    AHW.Step()   -- the list arrives, and the first frame
    local reads = { AHW.Calls("GetReplicateItemInfo") }
    for k = 2, 3 do
        T.isnil(got, "not done before frame " .. k)
        AHW.Frame()
        reads[k] = AHW.Calls("GetReplicateItemInfo")
    end
    T.deq(reads, { 250, 500, 600 }, "at most SLICE rows a frame")
    T.truthy(got, "done in 3 frames")
    T.isnil(why)
    T.eq(#got, 300, "one row per key")
    for _, row in ipairs(got) do
        T.eq(row.unit, 100)
        T.eq(row.qty, 2)
        T.eq(row.key, row.base)
    end
    T.eq(AHW.Frame(), 0, "nothing scheduled after the end")
end)

-- Rows that are slow to read (an item the game has to load, a huge house):
-- a frame stops after SLICE_MS of them, not only after SLICE rows. Reading
-- 250 a frame whatever they cost made frames of 50 to 100 ms in game.
T.test("a_slow_row_ends_the_frame_early", function()
    local M = load(many(600, 300))
    local was = _G.debugprofilestop
    _G.debugprofilestop = function() return AHW.Calls("GetReplicateItemInfo") * 1.0 end   -- 1 ms a row
    AHW.Open()
    local got
    T.eq(M.Replicate.Start(function(rows) got = rows end), true)
    AHW.Step()   -- the list arrives, and the first frame
    local first = AHW.Calls("GetReplicateItemInfo")
    T.truthy(first >= 1 and first <= M.Game.SLICE_MS + 1, "about SLICE_MS rows the first frame, got " .. first)
    AHW.Frame()
    T.truthy(AHW.Calls("GetReplicateItemInfo") - first <= M.Game.SLICE_MS + 1, "and the next")
    _G.debugprofilestop = was
    AHW.Settle()
    T.truthy(got, "every row still read")
    T.eq(#got, 300)
end)

T.test("saving_is_sliced_too", function()
    local M = load(many(600, 600))
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Step()
    AHW.Frame()
    AHW.Frame()   -- the last rows read: 600 keys to save
    local before = T.count(items(M) or {})
    T.truthy(before <= M.Game.SLICE, "at most SLICE keys saved in the frame that read the last rows")
    AHW.Settle()
    T.eq(T.count(items(M)), 600)
    T.eq(#changes, 1)
    T.eq(said("Full scan done: 600 items priced."), 1)
end)

-- ---------------------------------------------------------------------
-- The AH closing, the game not answering
-- ---------------------------------------------------------------------

T.test("closing_mid_scan_keeps_nothing", function()
    local M = load(many(600, 300))
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Step()                  -- the list, and the first 250 rows
    T.eq(AHW.Calls("GetReplicateItemInfo"), 250)
    AHW.Close()
    AHW.Settle()
    T.eq(AHW.Calls("GetReplicateItemInfo"), 250, "no row read after the close")
    T.isnil(items(M), "nothing kept")
    T.isnil(M.Store.FullScanAt(RKEY))
    T.eq(#changes, 0)
    T.eq(said("Full scan stopped: the Auction House was closed. Nothing was kept."), 1)

    -- the request went out, so the game's cooldown runs from it (Ruling 9)
    AHW.Open()
    local ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "Full scan again in 15 min.", "refused with minutes after a close mid-read")
    T.eq(AHW.Calls("ReplicateItems"), 1)
    AHW.Advance(M.Scan.FULL_COOLDOWN)

    -- closed while the list is on its way
    T.eq(M.Scan.Full(), true, "the next scan works once the cooldown is over")
    AHW.Close()
    AHW.Settle()
    T.isnil(items(M))
    T.eq(said("Full scan stopped: the Auction House was closed. Nothing was kept."), 2)
    AHW.Advance(M.Scan.FULL_COOLDOWN)

    -- and the one after that finishes
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(T.count(items(M)), 300)
    T.eq(#changes, 1)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- The game's "the list is ready" may come before the list is: "done" must
-- mean the whole list was read, never just that the first look was short.
T.test("a_list_that_comes_after_its_event_is_waited_for", function()
    local M = load(many(600, 600), { replicateLate = 1, settles = true })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Advance(0.5)
    T.eq(said("Full scan done"), 0, "an empty first look isn't the end")
    T.truthy(M.Scan.Running())
    AHW.Advance(10)
    AHW.Settle()
    T.eq(said("Full scan done: 600 items priced."), 1)
    T.eq(T.count(items(M)), 600)
end)

T.test("a_list_that_keeps_growing_is_read_to_its_end", function()
    local M = load(many(600, 600), { replicateLate = 1.5, replicateEarly = 50, settles = true })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Advance(10)
    AHW.Settle()
    T.eq(said("Full scan done: 600 items priced."), 1)
    T.eq(said("Full scan done: 50"), 0, "not only the first rows")
end)

T.test("rows_that_read_blank_at_first_are_read_again", function()
    local M = load(many(600, 600), { replicateBlank = 0.5, settles = true })
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Advance(10)
    AHW.Settle()
    T.eq(said("Full scan done: 600 items priced."), 1)
end)

T.test("an_empty_list_is_not_a_finished_scan", function()
    local M = load({}, { settles = true })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Advance(5)
    T.truthy(M.Scan.Running(), "the list may still come")
    T.eq(said("Full scan"), 0)
    AHW.Advance(20)
    AHW.Settle()
    T.eq(said("Full scan done"), 0)
    T.eq(said("Full scan stopped: the Auction House sent back no auctions. The game allows one full scan every 15 minutes."), 1)
    T.isnil(M.Store.FullScanAt(RKEY), "no scan on record: the first-visit card stays")
    T.eq(#changes, 0)
    T.falsy(M.Scan.Running())
    T.eq(#stub.errors, 0)
end)

T.test("replicate_with_no_answer_times_out", function()
    local M = load(many(10, 10))
    local changes = watchChanges(M)
    AHW.Open()
    local real = C_AuctionHouse.ReplicateItems
    C_AuctionHouse.ReplicateItems = function() end   -- the answer never comes
    T.eq(M.Scan.Full(), true)
    AHW.Advance(89)
    T.eq(said("Full scan stopped"), 0, "a big AH may take a while: 90 s")
    AHW.Advance(1)
    T.eq(said("Full scan stopped: the Auction House didn't answer. The game allows one full scan every 15 minutes."), 1)
    T.isnil(items(M))
    T.falsy(M.Scan.Running(), "not stuck running")
    C_AuctionHouse.ReplicateItems = real
    T.eq(select(2, M.Scan.Full()), "Full scan again in 14 min.", "the cooldown ran from the request, 90 s ago")
    AHW.Advance(M.Scan.FULL_COOLDOWN - 90)
    T.eq(M.Scan.Full(), true, "then the next scan works")
    AHW.Settle()
    T.eq(T.count(items(M)), 10)
    T.eq(#changes, 1)
end)

T.test("a_failing_read_doesnt_jam_the_next_scan", function()
    local M = load(many(10, 10))
    AHW.Open()
    local real = C_AuctionHouse.GetReplicateItemInfo
    C_AuctionHouse.GetReplicateItemInfo = function() error("boom") end
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(said("Full scan stopped: something went wrong. Try again in a moment."), 1)
    T.truthy(#stub.errors >= 1, "the error is reported")
    T.isnil(items(M))
    T.falsy(M.Replicate.Running())
    C_AuctionHouse.GetReplicateItemInfo = real
    T.eq(select(2, M.Scan.Full()), "Full scan again in 15 min.", "the list was asked for: the cooldown runs")
    AHW.Advance(M.Scan.FULL_COOLDOWN)
    T.eq(M.Scan.Full(), true, "the next scan runs")
    AHW.Settle()
    T.eq(T.count(items(M)), 10)
end)

T.test("a_send_that_fails_says_so_once", function()
    local M = load(many(10, 10))
    AHW.Open()
    local real = C_AuctionHouse.ReplicateItems
    C_AuctionHouse.ReplicateItems = function() error("refused") end
    local ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "Full scan stopped: something went wrong. Try again in a moment.")
    T.eq(said("Full scan stopped"), 0, "refused at once: the caller has the sentence, nothing else says it")
    T.falsy(M.Scan.Running())
    T.isnil(M.Store.AskedAt(RKEY), "nothing went out: no cooldown")
    C_AuctionHouse.ReplicateItems = real
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(T.count(items(M)), 10)
end)

T.test("a_scan_the_game_would_ignore_is_refused_up_front", function()
    -- the fake server ignores a second ReplicateItems inside its cooldown (a
    -- guess at the client's rule): such a request would only time out
    local M = load(many(600, 300), { replicateCooldown = 900 })
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Step()   -- the list, and the first rows
    AHW.Close()  -- closed mid-read: nothing kept, but the request was answered
    AHW.Settle()
    local asked = M.Store.AskedAt(RKEY)
    T.truthy(type(asked) == "number" and M.Game.Now() - asked < 1, "the ask is stamped when it was sent")
    T.isnil(M.Store.FullScanAt(RKEY), "no full scan finished")
    AHW.Open()
    local ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "Full scan again in 15 min.")
    T.eq(AHW.Calls("ReplicateItems"), 1, "nothing asked: refused up front")

    -- what the refusal saves the player from: the same request, sent anyway
    local got, reason = "pending", nil
    T.eq(M.Replicate.Start(function(rows, r) got, reason = rows, r end), true)
    AHW.Advance(M.Replicate.TIMEOUT + 1)
    T.isnil(got, "no list came")
    T.eq(reason, "timeout", "it would have timed out")
    T.eq(AHW.Calls("Ignored"), 1, "the fake ignored it")

    -- after the window, a scan works again
    AHW.Advance(M.Scan.FULL_COOLDOWN)
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(T.count(items(M)), 300)
    T.eq(#changes, 1)
end)

T.test("a_failing_save_doesnt_jam_the_next_scan", function()
    -- an error in the save's very first lines still ends the scan
    local M = load(many(10, 10))
    AHW.Open()
    local real = M.Rows.Records
    M.Rows.Records = function() error("boom") end
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    M.Rows.Records = real
    T.truthy(#stub.errors >= 1, "the error is reported")
    T.eq(said("Full scan stopped: something went wrong. Try again in a moment."), 1)
    T.falsy(M.Scan.Running(), "not left running")
    local ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "Full scan again in 15 min.", "refused for the cooldown, not as already running")
    AHW.Advance(M.Scan.FULL_COOLDOWN)
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(T.count(items(M)), 10)
end)

T.test("ruleset_changed_mid_scan", function()
    local M = load(many(10, 10))
    local changes = watchChanges(M)
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Ruleset("PvP"); stub.FireEvent("GAME_RULES_CHANGED")   -- before the list arrives
    AHW.Settle()
    T.eq(said("Full scan stopped: the ruleset changed."), 1)
    T.isnil(items(M), "nothing under the old ruleset")
    T.isnil(DaylightUIAuctionDB.rulesets["US-PvP"] and DaylightUIAuctionDB.rulesets["US-PvP"].items,
        "nor under the new one")
    T.isnil(M.Store.FullScanAt(RKEY))
    T.eq(#changes, 0)
    T.falsy(M.Scan.Running())
    T.eq(M.Scan.Full(), true, "a scan for the new ruleset may start")
    AHW.Settle()
    T.eq(T.count(DaylightUIAuctionDB.rulesets["US-PvP"].items), 10)
end)

-- ---------------------------------------------------------------------
-- Refusals
-- ---------------------------------------------------------------------

T.test("refusals", function()
    local M = load({ { itemID = LINEN, count = 20, buyout = 2000 } })
    -- closed
    local ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "Open the Auction House first.")
    T.eq(AHW.Calls("ReplicateItems"), 0)

    -- already running
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "A full scan is already running.")
    AHW.Settle()
    T.eq(AHW.Calls("ReplicateItems"), 1)

    -- cooldown, in whole minutes rounded up
    ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "Full scan again in 15 min.")
    AHW.Advance(5 * 60 + 1)
    T.eq(select(2, M.Scan.Full()), "Full scan again in 10 min.")
    AHW.Advance(M.Scan.FULL_COOLDOWN - (5 * 60 + 1) - 30)
    T.eq(select(2, M.Scan.Full()), "Full scan again in 1 min.")
    AHW.Advance(30)
    T.eq(M.Scan.Full(), true, "the cooldown is over")
    AHW.Settle()
    T.eq(AHW.Calls("ReplicateItems"), 2)
end)

T.test("no_ruleset_stores_nothing", function()
    local M = load({ { itemID = LINEN, count = 20, buyout = 2000 } }, { ruleset = false })
    AHW.Open()
    local ok, why = M.Scan.Full()
    T.eq(ok, false)
    T.eq(why, "The game hasn't said which Auction House this is yet. Try again in a moment.")
    AHW.Settle()
    T.eq(AHW.Calls("ReplicateItems"), 0)
    T.eq(T.count(DaylightUIAuctionDB.rulesets or {}), 0, "no rulesets entry")
end)

-- ---------------------------------------------------------------------
-- No chat hint (the window's first-visit card replaced it), and progress
-- ---------------------------------------------------------------------

T.test("opening_the_ah_says_nothing_in_chat", function()
    local M = load({ { itemID = LINEN, count = 20, buyout = 2000 } })
    AHW.Open()
    T.eq(said("scan"), 0, "the first-visit card in the window offers the scan")
    T.eq(M.Store.Offered(RKEY), false, "only the card's Not now marks it offered")
    T.eq(AHW.Calls("ReplicateItems"), 0, "opening never scans")
    M = load({}, { ruleset = false })
    AHW.Open()
    T.eq(said("Set your ruleset first"), 0, "the window's header says how")
end)

T.test("progress_follows_the_running_scan", function()
    local M = load(many(600, 600))
    local ends = {}
    M.On("ScanEnded", function(ok, text, total) ends[#ends + 1] = { ok, text, total } end)
    T.isnil(M.Scan.Progress(), "no scan")
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    local done, total = M.Scan.Progress()
    T.eq(done, 0, "asked, the list not here yet")
    T.eq(total, 0)
    AHW.Step()   -- the list arrives, and the first frame reads SLICE rows
    done, total = M.Scan.Progress()
    T.eq(total, 600)
    T.eq(done, 250)
    AHW.Frame()
    T.eq((M.Scan.Progress()), 500)
    AHW.Frame()   -- the last rows read: saving
    done, total = M.Scan.Progress()
    T.eq(done, 600, "read: full while the keys are saved")
    T.eq(total, 600)
    AHW.Settle()
    T.isnil(M.Scan.Progress(), "done")
    T.deq(ends, { { true, "Full scan done: 600 items priced.", 600 } }, "ScanEnded carries the done line and the rows")
end)

T.test("scan_ended_on_a_stop", function()
    local M = load(many(600, 600))
    local ends = {}
    M.On("ScanEnded", function(ok, text) ends[#ends + 1] = { ok, text } end)
    AHW.Open()
    M.Scan.Full()
    AHW.Step()
    AHW.Close()
    AHW.Settle()
    T.deq(ends, { { false, "Full scan stopped: the Auction House was closed. Nothing was kept." } })
    T.isnil(M.Scan.Progress())
end)

-- The game's message line never says it's ready again (seen as a scan stuck
-- on "Asking" for minutes): the scan gives up with a sentence instead of
-- waiting forever, and a new one can start.
T.test("scan_gives_up_when_the_game_never_takes_the_ask", function()
    local M = load(many(10, 10))
    AHW.Open()
    AHW.Throttle(true)
    T.eq(M.Scan.Full(), true)
    AHW.Advance(M.Replicate.TIMEOUT + 1)
    T.eq(said("Full scan stopped: the Auction House didn't answer."), 1, "stopped with a sentence")
    T.isnil(M.Scan.Progress(), "not running any more")
    T.eq(M.Replicate.Running(), false)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- ---------------------------------------------------------------------
-- Forever's random suffixes ("Phalanx Girdle of the Defender")
-- ---------------------------------------------------------------------

-- The girdle in a player's report: one "of the Monkey" at 16s 95c and three
-- "of the Defender" from 50s 90c. A Forever link names its suffix only by a
-- bonus ID, the AH by its own number; a full scan sees links only.
local GIRDLE = 7418
local function girdles()
    return {
        { itemID = GIRDLE, count = 1, buyout = 1695, suffix = 14455, words = "of the Monkey" },
        { itemID = GIRDLE, count = 1, buyout = 5090, suffix = 14333, words = "of the Defender" },
        { itemID = GIRDLE, count = 1, buyout = 5090, suffix = 14333, words = "of the Defender" },
        { itemID = GIRDLE, count = 1, buyout = 5095, suffix = 14333, words = "of the Defender" },
    }
end
local function girdleLoad()
    local M = AHW.Mog({ ah = { auctions = girdles(), items = { [GIRDLE] = { name = "Phalanx Girdle", classID = 4 } } } })
    M.Replicate.SETTLE, M.Replicate.EMPTY_WAIT = 0, 0
    return M
end
-- The Defender girdle in the bags, as the game links it (bonus 12753).
local DEFENDER = "|cnIQ2:|Hitem:7418::::::::27:1491:::1:12753::::::|h[Phalanx Girdle of the Defender]|h|r"

T.test("a suffix never paired gets no price, not the cheapest of every suffix", function()
    local M = girdleLoad()
    -- the words alone are known (a name to show), but never pick a price
    M.DB.Suffixes()[14333] = "of the Defender"
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(M.Store.Min(RKEY, "7418"), 1695, "the plain girdle: cheapest of every suffix")
    T.isnil(M.Store.Min(RKEY, "7418:14333"), "no Defender price from the scan before the pairing")
    local key, _, unplaced = M.Items.Key(DEFENDER)
    T.eq(key, "7418")
    T.eq(unplaced, true)
    T.isnil(M.Tooltip.Lines(DEFENDER, false, 1), "no line rather than the Monkey's 16s 95c")
end)

T.test("a Sell search pairs the suffix, then the scan and the tooltip price the Defender", function()
    local M = girdleLoad()
    AHW.Open()
    local done
    M.Search.Item(GIRDLE, function() done = true end)
    AHW.Settle()
    T.truthy(done)
    T.eq(M.DB.Table("suffixBonus")["12753"], 14333, "paired from the auction's own row")
    T.eq(M.DB.Table("suffixBonus")["12875"], 14455)
    AHW.Advance(M.Scan.FULL_COOLDOWN + 1)
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(M.Store.Min(RKEY, "7418:14333"), 5090)
    T.eq(M.Store.Min(RKEY, "7418:14455"), 1695)
    T.eq(M.Items.Key(DEFENDER), "7418:14333")
    local rows = M.Tooltip.Lines(DEFENDER, false, 1)
    T.eq(rows and rows[1][2], DaylightUI.Widgets.Money(5090), "the Defender's own 50s 90c")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's tooltip for an item key, as a link with the suffix's bonus in it.
-- Bonuses are mostly the AH number less 1580 but not always: 14300 and 14298
-- trade places (12718 and 12720).
local function keyTips(answer)
    local had = _G.C_TooltipInfo
    local asked = 0
    _G.C_TooltipInfo = { GetItemKey = function(itemID, level, suffix)
        asked = asked + 1
        local bonus = answer and answer(suffix)
        if bonus == nil then
            bonus = (suffix == 14300 and 12718) or (suffix == 14298 and 12720) or suffix - 1580
        end
        if bonus == false then return nil end
        return { hyperlink = "|cnIQ2:|Hitem:" .. itemID .. "::::::::27:1491:::1:" .. bonus .. "::::::|h[Phalanx Girdle]|h|r" }
    end }
    return function() _G.C_TooltipInfo = had end, function() return asked end
end

-- A suffixed green dropped and hovered in the loot window: the first time a
-- link's suffix isn't paired, every suffix is paired through the game's item
-- key tooltips, so the full scan files each one under its own price.
T.test("an unpaired suffix pairs every suffix, so a looted green gets its own price", function()
    local M = girdleLoad()
    local undo, asked = keyTips()
    local key = M.Items.Key(DEFENDER)
    T.eq(key, "7418:14333", "the loot window's link is placed at once")
    T.eq(M.DB.Table("suffixBonus")["12753"], 14333)
    T.eq(M.DB.Table("suffixBonus")["12718"], 14300, "taken from the game, never computed")
    T.eq(M.DB.Table("suffixBonus")["12875"], 14455)
    local n = asked()
    M.Items.Key("|cnIQ2:|Hitem:7418::::::::27:1491:::1:99999::::::|h[Phalanx Girdle of Nothing]|h|r")
    T.eq(asked(), n, "asked once a session, not on every unknown bonus")
    AHW.Open()
    T.eq(M.Scan.Full(), true)
    AHW.Settle()
    T.eq(M.Store.Min(RKEY, "7418:14333"), 5090, "the Defender's own price")
    T.eq(M.Store.Min(RKEY, "7418:14455"), 1695)
    local rows = M.Tooltip.Lines(DEFENDER, false, 1)
    T.eq(rows and rows[1][2], DaylightUI.Widgets.Money(5090), "the looted Defender shows 50s 90c")
    undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("item key tooltips that disagree with a known pair teach nothing", function()
    local M = girdleLoad()
    M.DB.Table("suffixBonus")["12875"] = 14455
    local undo = keyTips(function(suffix) if suffix == 14455 then return 11111 end end)
    local _, _, unplaced = M.Items.Key(DEFENDER)
    T.eq(unplaced, true, "no price rather than a pair the game contradicted")
    T.isnil(M.DB.Table("suffixBonus")["12753"])
    T.isnil(M.DB.Table("suffixBonus")["11111"])
    undo()
end)

T.test("item key tooltips that answer nothing leave the suffix unplaced", function()
    local M = girdleLoad()
    local undo = keyTips(function() return false end)
    local _, _, unplaced = M.Items.Key(DEFENDER)
    T.eq(unplaced, true)
    T.isnil(next(M.DB.Table("suffixBonus")))
    undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a girdle whose name the game hasn't loaded gets no price", function()
    local M = girdleLoad()
    M.Store.Record(RKEY, "7418", 1695, 1, M.Game.Now())
    local name = M.Items.Name
    M.Items.Name = function() return nil end
    T.isnil(M.Tooltip.Lines(DEFENDER, false, 1), "can't tell its suffix: no plain price")
    M.Items.Name = name
end)

T.test("a key's sample link and the AH's name for a key pair nothing", function()
    local M = girdleLoad()
    AHW.Open()
    -- the game hands back a Monkey girdle as the Defender key's sample
    local monkey = "|cnIQ2:|Hitem:7418::::::::27:1491:::1:12875::::::|h[Phalanx Girdle of the Monkey]|h|r"
    local sampleOf = C_AuctionHouse.GetItemKeySampleLink
    C_AuctionHouse.GetItemKeySampleLink = function() return monkey end
    local tip = CreateFrame("GameTooltip", nil, UIParent)
    tip.SetHyperlink = function() end
    tip.SetItemKey = function() end
    M.Items.SetTip(tip, "7418:14333", GIRDLE)
    C_AuctionHouse.GetItemKeySampleLink = sampleOf
    M.Items.LearnKey({ itemID = GIRDLE, itemLevel = 32, itemSuffix = 14333, battlePetSpeciesID = 0 })
    T.isnil(next(M.DB.Table("suffixBonus")), "nothing paired from a sample or a name")
    T.isnil(M.Items.RealLinkOf("7418:14333"), "the sample isn't kept as the key's link")
end)

T.test("an item in the bags pairs its suffix through the game's item key", function()
    local M = girdleLoad()
    local fromItem = C_AuctionHouse.GetItemKeyFromItem
    local hadLocation = ItemLocation
    C_AuctionHouse.GetItemKeyFromItem = function() return { itemID = GIRDLE, itemLevel = 32, itemSuffix = 14333, battlePetSpeciesID = 0 } end
    ItemLocation = ItemLocation or { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    T.eq(M.Items.BagKey(0, 1, DEFENDER, GIRDLE), "7418:14333")
    T.eq(M.DB.Table("suffixBonus")["12753"], 14333)
    C_AuctionHouse.GetItemKeyFromItem = fromItem
    ItemLocation = hadLocation
    T.eq(M.Items.Key(DEFENDER), "7418:14333", "known from then on, without the bag")
end)
