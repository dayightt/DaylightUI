-- Market: the usual price of an item from its daily lows. Pure math, no game.
-- An item keeps one number a day, the lowest unit buyout seen that day, for
-- its newest DAYS (14) days, as a flat list { day1, low1, day2, low2, ... }
-- with the newest last. Its usual price is the age-weighted median of those
-- lows: a low's weight is 0.5 ^ (ageDays / HALF (7)), and the value is the
-- smallest low whose cumulative
-- weight (lows sorted ascending) reaches half the total weight. One bad day
-- (a deal, a trap) barely moves it; a price that changed for good takes over
-- within a week or two.

local _, ns = ...

local Market = {}
ns.Market = Market

Market.DAYS = 14   -- daily lows kept per item
Market.HALF = 7    -- days for a low's weight to halve

local SECONDS_PER_DAY = 86400
local floor = math.floor

-- The day number (days since the epoch) a time falls on.
function Market.Day(t)
    return floor(t / SECONDS_PER_DAY)
end

-- Notes `copper` as the low of `day` in `lows` (kept in day order, newest
-- last). The same day keeps the lower price; only the newest DAYS days stay.
-- Returns lows.
function Market.AddLow(lows, day, copper)
    local n = #lows
    -- Newest last, so a normal add finds its place at the end.
    local at = n - 1
    while at >= 1 and lows[at] > day do at = at - 2 end
    if at >= 1 and lows[at] == day then
        if copper < lows[at + 1] then lows[at + 1] = copper end
    else
        -- `at` is the day just before the new one's place (or -1: first).
        table.insert(lows, at + 2, day)
        table.insert(lows, at + 3, copper)
        local extra = #lows - Market.DAYS * 2
        -- The oldest days are first (fewer days than before: every extra one goes).
        for _ = 1, extra do table.remove(lows, 1) end
    end
    return lows
end

-- Scratch lists reused by every Value call (at most DAYS entries each), so a
-- tooltip's price read allocates nothing.
local prices, weights = {}, {}

-- The market value in copper of `lows` as of day `today`; nil with no lows.
-- prior: only the days before today (Search's comparison: today's low is
-- the row being judged, so it can't be part of what it's judged against).
function Market.Value(lows, today, prior)
    if not lows then return nil end
    local count, total = 0, 0
    local halfLife = Market.HALF
    local last = #lows - 1
    if prior then while last >= 1 and lows[last] >= today do last = last - 2 end end
    -- the newest `days` lows (more are kept after the setting went down, until the next one)
    local first = last - Market.DAYS * 2 + 2
    if first < 1 then first = 1 end
    for i = first, last, 2 do
        local age = today - lows[i]
        if age < 0 then age = 0 end   -- a clock that moved back: weigh it as today
        local w = 0.5 ^ (age / halfLife)
        local price = lows[i + 1]
        -- Insertion sort by price (14 entries at most).
        local j = count
        while j >= 1 and prices[j] > price do
            prices[j + 1], weights[j + 1] = prices[j], weights[j]
            j = j - 1
        end
        prices[j + 1], weights[j + 1] = price, w
        count = count + 1
        total = total + w
    end
    if count == 0 then return nil end
    -- A hair under half, so rounding in the sums never skips the exact half.
    local half = total / 2 - 1e-12
    local sum = 0
    for i = 1, count do
        sum = sum + weights[i]
        if sum >= half then return prices[i] end
    end
    return prices[count]
end
