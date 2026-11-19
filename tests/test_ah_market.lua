local AHW = require("ahworld")

-- Pure math: no game needed, but M.Market is loaded the way the client does.
local M = AHW.Mog({ login = false })
local Market = M.Market

local function lowsOf(pairsList)
    local lows = {}
    for _, p in ipairs(pairsList) do Market.AddLow(lows, p[1], p[2]) end
    return lows
end

T.test("one_low_is_the_market", function()
    T.eq(Market.Value({ 100, 500 }, 100), 500)
end)

T.test("constants_and_day", function()
    T.eq(Market.DAYS, 14)
    T.eq(Market.HALF, 7)
    T.eq(Market.Day(0), 0)
    T.eq(Market.Day(86399), 0)
    T.eq(Market.Day(86400), 1)
    T.eq(Market.Day(1700000000), 19675)
end)

T.test("same_day_keeps_the_lower", function()
    local lows = {}
    Market.AddLow(lows, 100, 500)
    Market.AddLow(lows, 100, 300)
    Market.AddLow(lows, 100, 400)
    T.deq(lows, { 100, 300 })
end)

T.test("a_new_day_is_added_newest_last", function()
    local lows = lowsOf({ { 100, 500 }, { 101, 400 } })
    T.deq(lows, { 100, 500, 101, 400 })
end)

T.test("an_older_day_goes_in_its_place", function()
    local lows = lowsOf({ { 100, 500 }, { 102, 400 }, { 101, 450 } })
    T.deq(lows, { 100, 500, 101, 450, 102, 400 })
end)

T.test("only_fourteen_days_kept", function()
    local lows = {}
    for d = 1, 20 do Market.AddLow(lows, d, d * 10) end
    T.eq(#lows, 28)
    T.eq(lows[1], 7)       -- oldest kept: day 7 (days 1..6 dropped)
    T.eq(lows[2], 70)
    T.eq(lows[27], 20)
    T.eq(lows[28], 200)
end)

T.test("a_day_older_than_all_fourteen_is_not_kept", function()
    local lows = {}
    for d = 11, 24 do Market.AddLow(lows, d, 100) end
    Market.AddLow(lows, 5, 1)
    T.eq(#lows, 28)
    T.eq(lows[1], 11)
end)

-- Weight of a low = 0.5 ^ (ageDays / 7). Market = the smallest low whose
-- cumulative weight (lows sorted ascending) reaches half the total weight.
--   today = 110. Day 110 (age 0): low 100, weight 1.
--   Days 103, 102, 101, 100 (ages 7, 8, 9, 10): low 1000, weights
--   0.5^1 = 0.5, 0.5^(8/7) = 0.45315, 0.5^(9/7) = 0.41017, 0.5^(10/7) = 0.37131.
--   Total = 1 + 0.5 + 0.45315 + 0.41017 + 0.37131 = 2.73463; half = 1.36732.
--   Sorted ascending: 100 (cumulative 1 < 1.36732), then 1000 (cumulative
--   1.5 >= 1.36732) -> market = 1000. The one fresh 100 does not outweigh
--   four old 1000s even with its full weight.
T.test("old_lows_weigh_less", function()
    local lows = lowsOf({ { 100, 1000 }, { 101, 1000 }, { 102, 1000 }, { 103, 1000 }, { 110, 100 } })
    T.eq(Market.Value(lows, 110), 1000)
end)

-- The same weights decide when they differ from a plain median.
--   today = 110. Days 108, 109, 110 (ages 2, 1, 0): low 1000, weights
--   0.5^(2/7) = 0.82034, 0.5^(1/7) = 0.90573, 1 -> 2.72607.
--   Days 96..99 (ages 14, 13, 12, 11): low 100, weights
--   0.5^2 = 0.25, 0.5^(13/7) = 0.27590, 0.5^(12/7) = 0.30484, 0.5^(11/7) = 0.33635 -> 1.16709.
--   Total = 3.89316; half = 1.94658. Sorted: 100 x4 (cumulative 1.16709 < 1.94658),
--   then 1000 -> market = 1000. A plain median of these seven lows is 100.
T.test("weights_beat_the_plain_median", function()
    local lows = lowsOf({ { 96, 100 }, { 97, 100 }, { 98, 100 }, { 99, 100 },
                          { 108, 1000 }, { 109, 1000 }, { 110, 1000 } })
    T.eq(Market.Value(lows, 110), 1000)
    -- the other way round: old lows high, fresh lows low -> the fresh ones win
    local flipped = lowsOf({ { 96, 1000 }, { 97, 1000 }, { 98, 1000 }, { 99, 1000 },
                             { 108, 100 }, { 109, 100 }, { 110, 100 } })
    T.eq(Market.Value(flipped, 110), 100)
end)

T.test("outlier_barely_moves_it", function()
    local lows = {}
    for d = 100, 112 do Market.AddLow(lows, d, 1000) end
    Market.AddLow(lows, 113, 10)
    T.eq(#lows, 28)
    T.eq(Market.Value(lows, 113), 1000)
end)

T.test("fewer_than_fourteen_days_use_what_there_is", function()
    local lows = lowsOf({ { 100, 300 }, { 101, 200 } })
    -- weights: day 100 (age 1) 0.90573, day 101 (age 0) 1; total 1.90573; half 0.95287
    -- sorted: 200 (cumulative 1 >= 0.95287) -> 200
    T.eq(Market.Value(lows, 101), 200)
end)

T.test("no_lows_no_value", function()
    T.isnil(Market.Value({}, 100))
    T.isnil(Market.Value(nil, 100))
end)

T.test("a_low_from_the_future_weighs_like_today", function()
    T.eq(Market.Value({ 105, 500 }, 100), 500)
end)

T.test("value_leaves_the_lows_alone", function()
    local lows = lowsOf({ { 100, 900 }, { 101, 100 }, { 102, 500 } })
    local before = { unpack(lows) }
    Market.Value(lows, 102)
    T.deq(lows, before)
end)

T.test("prior_leaves_today_out", function()
    local lows = lowsOf({ { 108, 1000 }, { 109, 1000 }, { 110, 100 } })
    T.eq(Market.Value(lows, 110), 1000, "with today: 2 old 1000s still win here")
    T.eq(Market.Value(lowsOf({ { 109, 1000 }, { 110, 100 } }), 110), 100, "one day and today: today wins")
    T.eq(Market.Value(lowsOf({ { 109, 1000 }, { 110, 100 } }), 110, true), 1000, "prior: yesterday alone")
    T.isnil(Market.Value({ 110, 100 }, 110, true), "only today: no prior market")
    T.eq(Market.Value({ 109, 500 }, 110, true), 500, "nothing today: the same as without prior")
    T.isnil(Market.Value({ 111, 100 }, 110, true), "a low from the future isn't before today")
end)
