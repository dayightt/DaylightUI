local AHW = require("ahworld")
local stub = require("stub")

local DAY = 86400

-- A fresh addon in the fake realm "Forever", US region.
local function load(opts)
    opts = opts or {}
    return AHW.Mog({
        login = opts.login, ruleset = opts.ruleset,
        db = opts.db, prices = opts.prices,
        before = function()
            if opts.now then stub.SetTime(opts.now) end
        end,
    })
end

-- Ruleset known: "US-PvE".
local function known()
    local M = load()
    return M
end

T.test("nothing_stored_without_a_ruleset", function()
    local M = load({ ruleset = false })
    T.isnil(M.Ruleset.Key())
    T.eq(M.Store.Record(nil, "2589", 100, 5, 1700000000), false)
    T.isnil(M.Store.Seen(nil, "2589"))
    T.isnil(M.Store.Lows(nil, "2589"))
    T.isnil(M.Store.Market(nil, "2589", 1700000000))
    T.eq(M.Store.MarkFullScan(nil, 5), false)
    T.eq(M.Store.MarkOffered(nil), false)
    T.isnil(M.Store.FullScanAt(nil))
    T.eq(M.Store.Offered(nil), false)
    M.Store.Trim(nil, 1700000000)
    T.eq(T.count(DaylightUIAuctionDB and DaylightUIAuctionDB.rulesets or {}), 0)
end)

T.test("record_and_read_back", function()
    local M = known()
    local at = 1700000000
    T.eq(M.Store.Record("US-PvE", "2589", 120, 20, at), true)
    T.deq(M.Store.Seen("US-PvE", "2589"), { min = 120, t = at, q = 20 })
    T.eq(M.Store.Qty("US-PvE", "2589"), 20, "the count, read without making a table")
    T.isnil(M.Store.Qty("US-PvE", "2590"), "never seen: nil")
    T.deq(M.Store.Lows("US-PvE", "2589"), { M.Market.Day(at), 120 })
    T.eq(M.Store.Market("US-PvE", "2589", at), 120)
    -- the saved shape
    T.deq(DaylightUIAuctionDB.rulesets["US-PvE"].items["2589"],
        { l = { M.Market.Day(at), 120 }, m = 120, t = at, q = 20 })
    -- a second record the same day: lows keep the lower, seen is the newest
    M.Store.Record("US-PvE", "2589", 150, 3, at + 60)
    T.deq(M.Store.Seen("US-PvE", "2589"), { min = 150, t = at + 60, q = 3 })
    T.deq(M.Store.Lows("US-PvE", "2589"), { M.Market.Day(at), 120 })
    -- an unknown item and another ruleset read as nothing
    T.isnil(M.Store.Seen("US-PvE", "999"))
    T.isnil(M.Store.Lows("US-PvE", "999"))
    T.isnil(M.Store.Market("US-PvE", "999", at))
    T.isnil(M.Store.Seen("EU-PvP", "2589"))
end)

T.test("bridge_offer_gives_price_seen_at_and_how_many_were_for_sale", function()
    local M = known()
    local at = 1700000000
    T.eq(M.Store.Record("US-PvE", "2589", 120, 20, at), true)
    local price, seenAt, qty = M.Bridge.Offer(2589)
    T.eq(price, 120, "the price a price source adds to the recipe")
    T.eq(seenAt, at, "and when it was seen, so the other addon can age it")
    T.eq(qty, 20, "and how many were for sale, for its supply math")
    T.isnil(M.Bridge.Offer(12345), "never seen: nil, not a made-up price")
end)

T.test("bridge_scanned_at_is_the_last_sighting_of_anything", function()
    local M = known()
    T.isnil(M.Bridge.ScannedAt(), "before the first scan")
    local at = 1700000000
    M.Store.Record("US-PvE", "2589", 120, 20, at)
    M.Store.Record("US-PvE", "2590", 300, 4, at + 600)
    T.eq(M.Bridge.ScannedAt(), at + 600, "the newest sighting wins")
end)

T.test("min_is_the_last_sightings_lowest", function()
    local M = known()
    local at = 1700000000
    T.isnil(M.Store.Min("US-PvE", "2589"), "never seen")
    T.isnil(M.Store.Min(nil, "2589"), "no ruleset")
    M.Store.Record("US-PvE", "2589", 120, 20, at)
    T.eq(M.Store.Min("US-PvE", "2589"), 120)
    M.Store.Record("US-PvE", "2589", 150, 3, at + 60)
    T.eq(M.Store.Min("US-PvE", "2589"), 150, "the newest sighting, not the day's low")
    M.Store.Record("US-PvE", "2589", 90, 7, at - 3 * DAY)
    T.eq(M.Store.Min("US-PvE", "2589"), 150, "an older sighting doesn't replace it")
    T.isnil(M.Store.Min("EU-PvP", "2589"))
    -- lows without a sighting (no `t`): nothing seen
    DaylightUIAuctionDB.rulesets["US-PvE"].items["7"] = { l = { M.Market.Day(at), 5 } }
    T.isnil(M.Store.Min("US-PvE", "7"))
    T.eq(T.count(DaylightUIAuctionDB.rulesets), 1, "reads make no entries")
end)

T.test("reads_make_no_entries", function()
    local M = known()
    T.isnil(M.Store.Seen("US-PvE", "2589"))
    T.isnil(M.Store.Market("US-PvE", "2589", 1700000000))
    T.eq(M.Store.Offered("US-PvE"), false)
    T.isnil(M.Store.FullScanAt("US-PvE"))
    M.Store.Trim("US-PvE", 1700000000)
    T.eq(T.count(DaylightUIAuctionDB and DaylightUIAuctionDB.rulesets or {}), 0)
end)

T.test("market_uses_the_daily_lows", function()
    local M = known()
    local t0 = 1700000000
    M.Store.Record("US-PvE", "2589", 500, 1, t0)
    M.Store.Record("US-PvE", "2589", 100, 1, t0 + DAY)
    M.Store.Record("US-PvE", "2589", 100, 1, t0 + 2 * DAY)
    -- weights: 0.5^(2/7) = 0.82034 for the 500, 0.90573 for the first 100, 1 for the second:
    -- total 2.72607, half 1.36303; sorted: 100 (0.90573), 100 (cumulative 1.90573) -> 100
    T.eq(M.Store.Market("US-PvE", "2589", t0 + 2 * DAY), 100)
end)

T.test("older_record_doesnt_replace_seen", function()
    local M = known()
    local t0 = 1700000000
    M.Store.Record("US-PvE", "2589", 120, 20, t0)
    M.Store.Record("US-PvE", "2589", 90, 7, t0 - 3 * DAY)   -- an older sighting arriving late
    T.deq(M.Store.Seen("US-PvE", "2589"), { min = 120, t = t0, q = 20 })
    -- but its low still counts, on its own day, in order
    T.deq(M.Store.Lows("US-PvE", "2589"), { M.Market.Day(t0 - 3 * DAY), 90, M.Market.Day(t0), 120 })
end)

T.test("bad_records_are_refused", function()
    local M = known()
    T.eq(M.Store.Record("US-PvE", nil, 100, 1, 1700000000), false)
    T.eq(M.Store.Record("US-PvE", "2589", nil, 1, 1700000000), false)
    T.eq(M.Store.Record("US-PvE", "2589", 0, 1, 1700000000), false)
    T.eq(M.Store.Record("US-PvE", "2589", 100, 1, nil), false)
    T.eq(T.count(DaylightUIAuctionDB and DaylightUIAuctionDB.rulesets or {}), 0)
end)

T.test("trim_drops_stale_items", function()
    local M = known()
    local now = 1700000000
    M.Store.Record("US-PvE", "old", 100, 1, now - 61 * DAY)
    M.Store.Record("US-PvE", "edge", 100, 1, now - 60 * DAY)
    M.Store.Record("US-PvE", "new", 100, 1, now - 1 * DAY)
    M.Store.Trim("US-PvE", now)
    T.isnil(M.Store.Seen("US-PvE", "old"))
    T.truthy(M.Store.Seen("US-PvE", "edge"), "60 days is still kept")
    T.truthy(M.Store.Seen("US-PvE", "new"))
end)

T.test("trim_runs_at_login_for_every_ruleset", function()
    local now = 1700000000
    local M = load({ login = false, now = now, prices = { version = 1, rulesets = {
        ["US-PvE"] = { items = { stale = { l = { 1, 5 }, m = 5, t = now - 90 * DAY, q = 1 },
                                 fresh = { l = { 2, 6 }, m = 6, t = now - DAY, q = 1 } } },
        ["EU-PvP"] = { items = { stale = { l = { 1, 5 }, m = 5, t = now - 90 * DAY, q = 1 } } },
    } } })
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()   -- it walks from the next frame on
    local items = DaylightUIAuctionDB.rulesets["US-PvE"].items
    T.isnil(items.stale)
    T.truthy(items.fresh)
    T.isnil(DaylightUIAuctionDB.rulesets["EU-PvP"].items.stale, "other rulesets are trimmed too")
end)

T.test("trim_at_login_with_no_ruleset_known", function()
    -- the current ruleset unknown: every saved one is still trimmed
    local now = 1700000000
    load({ now = now, prices = { version = 1, rulesets = {
        ["US-PvE"] = { items = { stale = { l = { 1, 5 }, m = 5, t = now - 90 * DAY, q = 1 } } },
        ["EU-RP"] = { items = { stale = { l = { 1, 5 }, m = 5, t = now - 90 * DAY, q = 1 },
                                fresh = { l = { 2, 6 }, m = 6, t = now - DAY, q = 1 } } },
    } } })
    stub.RunTimers()
    T.isnil(DaylightUIAuctionDB.rulesets["US-PvE"].items.stale)
    T.isnil(DaylightUIAuctionDB.rulesets["EU-RP"].items.stale)
    T.truthy(DaylightUIAuctionDB.rulesets["EU-RP"].items.fresh)
end)

T.test("full_scan_and_offer_flags", function()
    local M = known()
    T.isnil(M.Store.FullScanAt("US-PvE"))
    T.eq(M.Store.Offered("US-PvE"), false)
    T.eq(M.Store.MarkFullScan("US-PvE", 1700000000), true)
    T.eq(M.Store.MarkOffered("US-PvE"), true)
    T.eq(M.Store.FullScanAt("US-PvE"), 1700000000)
    T.eq(M.Store.Offered("US-PvE"), true)
    T.isnil(M.Store.FullScanAt("EU-PvP"))
    T.eq(M.Store.Offered("EU-PvP"), false)
    T.eq(DaylightUIAuctionDB.rulesets["US-PvE"].full, 1700000000)
    T.eq(DaylightUIAuctionDB.rulesets["US-PvE"].offered, true)
end)

T.test("asked_flag", function()
    -- when a full scan was last asked of the game (its cooldown runs from the ask)
    local M = known()
    T.isnil(M.Store.AskedAt("US-PvE"))
    T.eq(M.Store.MarkAsked(nil, 1700000000), false, "no ruleset: nothing")
    T.isnil(M.Store.AskedAt(nil))
    T.eq(M.Store.MarkAsked("US-PvE", 1700000000), true)
    T.eq(M.Store.AskedAt("US-PvE"), 1700000000)
    T.isnil(M.Store.FullScanAt("US-PvE"), "asking is not a finished scan")
    T.isnil(M.Store.AskedAt("EU-PvP"))
    T.isnil(DaylightUIAuctionDB.rulesets["EU-PvP"], "reading makes no entry")
    T.eq(DaylightUIAuctionDB.rulesets["US-PvE"].asked, 1700000000)
end)

T.test("seen_at_reads_the_time_without_a_table", function()
    local M = known()
    local at = 1700000000
    T.isnil(M.Store.SeenAt("US-PvE", "2589"), "never seen")
    T.isnil(M.Store.SeenAt(nil, "2589"), "no ruleset")
    M.Store.Record("US-PvE", "2589", 120, 20, at)
    T.eq(M.Store.SeenAt("US-PvE", "2589"), at, "when it was last seen")
    M.Store.Record("US-PvE", "2589", 150, 3, at + 60)
    T.eq(M.Store.SeenAt("US-PvE", "2589"), at + 60, "the newest sighting")
    T.isnil(M.Store.SeenAt("US-PvE", "999"))
    T.isnil(M.Store.SeenAt("EU-PvP", "2589"))
    -- reading makes no entries
    T.isnil(DaylightUIAuctionDB.rulesets["EU-PvP"])
end)

T.test("count_is_kept_on_record_and_trim", function()
    -- the header's "items known": a counter, never a walk of the items
    local M = known()
    local now = 1700000000
    T.eq(M.Store.Count("US-PvE"), 0, "nothing yet")
    T.eq(M.Store.Count(nil), 0, "no ruleset")
    M.Store.Record("US-PvE", "2589", 100, 1, now - 61 * DAY)
    M.Store.Record("US-PvE", "2592", 100, 1, now)
    M.Store.Record("US-PvE", "2592", 90, 1, now + 1)
    T.eq(M.Store.Count("US-PvE"), 2, "a key seen twice counts once")
    T.eq(DaylightUIAuctionDB.rulesets["US-PvE"].n, 2, "saved with the ruleset")
    -- the counter is what Count reads: a walk would still say 2
    DaylightUIAuctionDB.rulesets["US-PvE"].n = 7
    T.eq(M.Store.Count("US-PvE"), 7)
    M.Store.Trim("US-PvE", now)
    T.eq(M.Store.Count("US-PvE"), 1, "Trim walks anyway and sets the counter")
    T.eq(M.Store.Count("EU-PvP"), 0)
    T.isnil(DaylightUIAuctionDB.rulesets["EU-PvP"], "reading makes no entry")
end)

T.test("count_is_items_not_suffixes", function()
    -- a suffixed sighting is stored under its own key and its plain key: one item
    local M = known()
    local now = 1700000000
    M.Store.Record("US-PvE", "7429:-15", 500, 1, now)
    M.Store.Record("US-PvE", "7429", 500, 1, now)
    M.Store.Record("US-PvE", "7429:-16", 400, 1, now)
    M.Store.Record("US-PvE", "2589", 100, 1, now)
    T.eq(M.Store.Count("US-PvE"), 2, "7429 and 2589")
    M.Store.Record("US-PvE", "9999:-3", 100, 1, now - 61 * DAY)
    M.Store.Record("US-PvE", "9999", 100, 1, now - 61 * DAY)
    T.eq(M.Store.Count("US-PvE"), 3)
    M.Store.Trim("US-PvE", now)
    T.eq(M.Store.Count("US-PvE"), 2, "Trim counts plain keys too")
    DaylightUIAuctionDB.rulesets["US-PvE"].n = nil
    T.eq(M.Store.Count("US-PvE"), 2, "the one-time count of old data too")
end)

T.test("count_of_data_saved_before_the_counter", function()
    local now = 1700000000
    local M = load({ login = false, now = now, prices = { version = 1, rulesets = {
        ["US-PvE"] = { items = { a = { l = { 1, 5 }, m = 5, t = now, q = 1 }, b = { l = { 1, 6 }, m = 6, t = now, q = 1 } } },
    } } })
    T.eq(M.Store.Count("US-PvE"), 2, "counted once")
    M.Store.Record("US-PvE", "c", 10, 1, now)
    T.eq(M.Store.Count("US-PvE"), 3)
end)

T.test("last_at_is_the_newest_sighting", function()
    local M = known()
    local at = 1700000000
    T.isnil(M.Store.LastAt("US-PvE"))
    M.Store.Record("US-PvE", "2589", 120, 20, at)
    M.Store.Record("US-PvE", "2592", 120, 20, at - 500)
    T.eq(M.Store.LastAt("US-PvE"), at, "an older record doesn't move it back")
    M.Store.Record("US-PvE", "2592", 120, 20, at + 9)
    T.eq(M.Store.LastAt("US-PvE"), at + 9)
    T.isnil(M.Store.LastAt("EU-PvP"))
    T.isnil(M.Store.LastAt(nil))
end)

-- Rule 10: the login trim walks every item of every ruleset; tens of
-- thousands of them in one frame would hitch the login, so it walks
-- Store.TRIM_SLICE a frame. A key recorded meanwhile is counted, and
-- whatever it dropped is told once (PricesChanged) for the header's count.
T.test("the_login_trim_runs_in_slices", function()
    local AHW = require("ahworld")
    local now = 1700000000
    local items, other = {}, {}
    for i = 1, 5000 do items["s" .. i] = { l = { 1, 5 }, m = 5, t = now - 90 * DAY, q = 1 } end
    for i = 1, 300 do items[tostring(i)] = { l = { 2, 6 }, m = 6, t = now - DAY, q = 1 } end
    for i = 1, 1000 do other["s" .. i] = { l = { 1, 5 }, m = 5, t = now - 90 * DAY, q = 1 } end
    local fired = {}
    local M = AHW.Mog({ ah = {}, prices = { version = 1, rulesets = {
            ["US-PvE"] = { items = items, n = 5300 }, ["EU-PvP"] = { items = other } } },
        before = function()
            stub.SetTime(now)
            _G.GetServerTime = function() return now end
        end })
    M.On("PricesChanged", function(rkey) fired[#fired + 1] = rkey end)
    local left = 0
    for _ in pairs(DaylightUIAuctionDB.rulesets["US-PvE"].items) do left = left + 1 end
    for _ in pairs(DaylightUIAuctionDB.rulesets["EU-PvP"].items) do left = left + 1 end
    T.truthy(left > 6300 - 2 * M.Store.TRIM_SLICE, "no more than a slice the first frame")
    T.truthy(left > 300, "not all at once")
    M.Store.Record("US-PvE", "new", 10, 1, now)   -- a sighting while the trim walks
    for _ = 1, 20 do AHW.Frame() end
    T.isnil(next(DaylightUIAuctionDB.rulesets["EU-PvP"].items), "every ruleset trimmed")
    local kept = 0
    for _ in pairs(DaylightUIAuctionDB.rulesets["US-PvE"].items) do kept = kept + 1 end
    T.eq(kept, 301, "the fresh 300 and the new one")
    T.eq(M.Store.Count("US-PvE"), 301)
    table.sort(fired)
    T.deq(fired, { "EU-PvP", "US-PvE" }, "each ruleset that dropped items is told once")
end)

T.test("prior_is_the_market_before_today", function()
    local M = known()
    local t0 = 1700000000
    M.Store.Record("US-PvE", "2589", 1000, 1, t0)
    M.Store.Record("US-PvE", "2589", 100, 1, t0 + DAY)
    T.eq(M.Store.Market("US-PvE", "2589", t0 + DAY), 100, "today's low wins the market")
    T.eq(M.Store.Prior("US-PvE", "2589", t0 + DAY), 1000, "the day before alone")
    T.isnil(M.Store.Prior("US-PvE", "2589", t0), "first seen that day: none")
    T.isnil(M.Store.Prior("US-PvE", "404", t0 + DAY), "never seen")
    T.isnil(M.Store.Prior(nil, "2589", t0 + DAY))
end)
