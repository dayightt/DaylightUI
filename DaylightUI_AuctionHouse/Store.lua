-- Store: what has been seen on the Auction House, per ruleset.
-- Saved per ruleset key (ns.Ruleset.Key(), through ns.DB.RulesetData):
--   { items = { [key] = { l = lows, m = min, t = t, q = q } },
--     full = time of the last full scan, asked = when one was last asked
--     of the game, offered = true, n = how many items it knows (Count:
--     plain keys only),
--     last = the newest sighting's time (LastAt) }
-- l = the daily lows (Market.AddLow), m = the lowest unit buyout when the
-- item was last seen, t = when, q = how many were for sale. With no
-- ruleset key nothing is stored. Reads never make entries.
-- Store fires nothing: ns.Scan tells the rest once per batch.

local _, ns = ...

local Store = {}
ns.Store = Store

local DB, Market = ns.DB, ns.Market
Store.STALE_DAYS = 60   -- an item not seen for this many days is dropped
-- The player's pick from the options, STALE_DAYS until the settings are read.
function Store.KeepDays()
    local v = ns.Setting and ns.Setting("keepDays")
    return type(v) == "number" and v >= 1 and v or Store.STALE_DAYS
end
local function staleAfter() return Store.KeepDays() * 86400 end
Store.TRIM_SLICE = 2000          -- items the login trim looks at a frame (a compare each)

local added = 0   -- new keys recorded so far: a walk across frames starts again after one

-- The ruleset's table for reading, nil when it has none (a read makes no
-- entry). Read-only, the session copy: it may hold this session's writes.
local function peek(rkey)
    if rkey == nil then return nil end
    if DB.readOnly then return DB.RulesetData(rkey) end
    local prices = DB.Prices()
    local rulesets = prices and prices.rulesets
    local data = type(rulesets) == "table" and rulesets[rkey]
    return type(data) == "table" and data or nil
end

-- A plain key ("2589"), not a suffixed one ("7429:-15"): every suffixed
-- sighting is also recorded under its plain key, so items are counted by these.
local function plain(key)
    return type(key) ~= "string" or not key:find(":", 1, true)
end

local function itemOf(rkey, key)
    local data = peek(rkey)
    local items = data and data.items
    local item = type(items) == "table" and key ~= nil and items[key]
    return type(item) == "table" and item or nil
end

-- Notes that `qty` of `key` were for sale at `at`, the cheapest at `unit`
-- (copper per unit). Adds to the item's daily lows; what was last seen is
-- replaced unless this sighting is older than the one stored. False when
-- nothing was stored (no ruleset, or a record that makes no sense).
function Store.Record(rkey, key, unit, qty, at)
    if rkey == nil or key == nil then return false end
    if type(unit) ~= "number" or unit < 1 or type(at) ~= "number" then return false end
    unit = math.floor(unit)
    local data = DB.RulesetData(rkey)
    if type(data.items) ~= "table" then data.items = {} end
    local item = data.items[key]
    if type(item) ~= "table" then
        local n = Store.Count(rkey)   -- before the new key goes in: an old uncounted table is counted as it was
        item = {}
        data.items[key] = item
        added = added + 1
        data.n = plain(key) and n + 1 or n
    end
    if type(data.last) ~= "number" or at > data.last then data.last = at end
    if type(item.l) ~= "table" then item.l = {} end
    Market.AddLow(item.l, Market.Day(at), unit)
    if item.t == nil or at >= item.t then
        item.m, item.t, item.q = unit, at, qty or 0
    end
    return true
end

-- { min, t, q } of the last sighting, nil when never seen.
function Store.Seen(rkey, key)
    local item = itemOf(rkey, key)
    if not item or item.t == nil then return nil end
    return { min = item.m, t = item.t, q = item.q }
end

-- When the item was last seen, nil when never. Like Min it makes no table
-- (Seen does): the tooltip reads it on every fill.
function Store.SeenAt(rkey, key)
    local item = itemOf(rkey, key)
    if not item then return nil end
    return item.t
end

-- How many were for sale at that sighting, nil when never seen. Makes no table
-- (Seen does): a price source reads it once per item of a recipe list.
function Store.Qty(rkey, key)
    local item = itemOf(rkey, key)
    if not item or item.t == nil then return nil end
    return item.q
end

-- The lowest unit buyout of the last sighting, nil when never seen. Makes no
-- table (Seen does): price sources read it for every formula and tooltip.
function Store.Min(rkey, key)
    local item = itemOf(rkey, key)
    if not item or item.t == nil then return nil end
    return item.m
end

-- The ruleset's saved items table, key -> item, for walking (autocomplete);
-- read it, don't change it. Nil when the ruleset has none.
function Store.Items(rkey)
    local data = peek(rkey)
    local items = data and data.items
    return type(items) == "table" and items or nil
end

-- How many items the ruleset knows (the header's "items known"): its plain
-- keys (a suffixed item's sightings are under its plain key too, so its
-- suffixes would count it twice). A counter kept by Record and Trim, never
-- a walk; data saved before the counter is counted once, here.
function Store.Count(rkey)
    local data = peek(rkey)
    if not data then return 0 end
    if type(data.n) == "number" then return data.n end
    local n = 0
    if type(data.items) == "table" then
        for key, item in pairs(data.items) do
            if type(item) == "table" and plain(key) then n = n + 1 end
        end
    end
    data.n = n
    return n
end

-- When anything of the ruleset was last seen (a full scan, a search, a
-- browse), nil when never.
function Store.LastAt(rkey)
    local data = peek(rkey)
    return data and type(data.last) == "number" and data.last or nil
end

-- The daily lows (Market's flat list; read it, don't change it), nil when
-- never seen.
function Store.Lows(rkey, key)
    local item = itemOf(rkey, key)
    return item and type(item.l) == "table" and item.l or nil
end

-- The market value in copper as of `now`, nil with no data.
function Store.Market(rkey, key, now)
    local lows = Store.Lows(rkey, key)
    if not lows then return nil end
    return Market.Value(lows, Market.Day(now))
end

-- The market from the days before today, nil with none: Search compares a
-- row against it (today's low is the row itself).
function Store.Prior(rkey, key, now)
    if not rkey then return nil end
    local lows = Store.Lows(rkey, key)
    if not lows then return nil end
    return Market.Value(lows, Market.Day(now), true)
end

-- Drops the items not seen for Store.KeepDays() days; returns how many.
function Store.Trim(rkey, now)
    local data = peek(rkey)
    local items = data and data.items
    if type(items) ~= "table" then return 0 end
    local oldest, dropped, kept = now - staleAfter(), 0, 0
    for key, item in pairs(items) do
        if type(item) ~= "table" or type(item.t) ~= "number" or item.t < oldest then
            items[key] = nil   -- clearing a field while walking the table is allowed
            dropped = dropped + 1
        elseif plain(key) then
            kept = kept + 1
        end
    end
    data.n = kept   -- the walk is here anyway: the counter is set from it
    return dropped
end

-- When the last full scan finished, nil when none.
function Store.FullScanAt(rkey)
    local data = peek(rkey)
    return data and data.full or nil
end

function Store.MarkFullScan(rkey, at)
    if rkey == nil then return false end
    DB.RulesetData(rkey).full = at
    return true
end

-- When a full scan was last asked of the game (ReplicateItems sent), nil
-- when never. The game's cooldown runs from the ask, not from a finished
-- scan: a scan closed or timed out part way still started it.
function Store.AskedAt(rkey)
    local data = peek(rkey)
    return data and data.asked or nil
end

function Store.MarkAsked(rkey, at)
    if rkey == nil then return false end
    DB.RulesetData(rkey).asked = at
    return true
end

-- Whether the first-visit offer (a full scan) was already made.
function Store.Offered(rkey)
    local data = peek(rkey)
    return data ~= nil and data.offered == true
end

function Store.MarkOffered(rkey)
    if rkey == nil then return false end
    DB.RulesetData(rkey).offered = true
    return true
end

-- Trims the rulesets in `list` as Trim does, TRIM_SLICE items a frame from
-- the next frame on (rule 10: tens of thousands of items in one frame would
-- hitch). A key recorded meanwhile starts that ruleset's walk again (a new
-- key may move the table's insides, and the count must include it); items
-- cleared while walking are fine. PricesChanged(rkey) once for each ruleset
-- that dropped something (the header's count).
local function trimSliced(list, now)
    local i, cursor, kept, dropped, mark = 1, nil, 0, 0, added
    local function step()
        local budget = Store.TRIM_SLICE
        while list[i] do
            local rkey = list[i]
            local data = peek(rkey)
            local items = data and data.items
            if type(items) ~= "table" then
                i, cursor, kept, dropped = i + 1, nil, 0, 0
            else
                if mark ~= added then cursor, kept, mark = nil, 0, added end   -- from the start again
                local oldest, key, item = now - staleAfter(), next(items, cursor)
                while key ~= nil and budget > 0 do
                    budget = budget - 1
                    if type(item) ~= "table" or type(item.t) ~= "number" or item.t < oldest then
                        items[key] = nil   -- clearing a field while walking the table is allowed
                        dropped = dropped + 1
                    elseif plain(key) then
                        kept = kept + 1
                    end
                    cursor = key
                    key, item = next(items, cursor)
                end
                if key ~= nil then return C_Timer.After(0, function() ns.SafeCall(step) end) end
                data.n = kept
                if dropped > 0 then ns.Fire("PricesChanged", rkey) end
                i, cursor, kept, dropped = i + 1, nil, 0, 0
            end
        end
    end
    C_Timer.After(0, function() ns.SafeCall(step) end)
end

-- Old items go at login, in every saved ruleset (an alt on another ruleset
-- would otherwise keep its stale items until someone plays there). A
-- read-only session trims only the current one: its session copy, the
-- one this session reads; the others aren't copied just to be trimmed.
ns.On("Login", function()
    local now, current = ns.Game.Now(), ns.Ruleset.Key()
    local prices = DB.Prices()
    local rulesets = type(prices) == "table" and prices.rulesets
    local list = {}
    if DB.readOnly or type(rulesets) ~= "table" then
        list[1] = current
    else
        for rkey in pairs(rulesets) do list[#list + 1] = rkey end
    end
    if list[1] then trimSliced(list, now) end
end)

-- Forgets a ruleset's prices (items, their count, the last sighting, the
-- last full scan), so the next scan fills them again. The scan offer and the
-- server's cooldown stay.
function Store.Clear(rkey)
    local data = peek(rkey)
    if not data then return true end
    data.items, data.n, data.last, data.full = nil, nil, nil, nil
    added = added + 1   -- a walk across frames (the login trim) starts again
    return true
end
