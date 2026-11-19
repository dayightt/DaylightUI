-- Browse: the game's browse query, one row per item, priced from it.
--
--   ns.Browse.Query(query, function(rows, reason, capped) end, tag) -> true | false, reason
--     capped: how many rows were read when MAX_PAGES stopped it (more were up); nil when whole
--
-- query: the game's AuctionHouseBrowseQuery { searchString, sorts, minLevel,
-- maxLevel, filters (Enum.AuctionHouseFilter values), itemClassFilters
-- ({ classID, subClassID, inventoryType } each) }, built by the Search tab;
-- sorts is {} when missing. tag: what ns.AH.Drop(tag) ends it by (default
-- "search": the window drops stale work when the player asks for something
-- else). rows, in the client's order: { itemKey (the game's), itemID, key,
-- base (ns.Items.KeyOf), minPrice, qty (totalQuantity), owned
-- (containsOwnerItem) }. They are recorded under the ruleset the query
-- started in (ns.Store.Record of minPrice and qty per key, and each plain
-- itemID key, stamped ns.Game.Now()) and "PricesChanged" (payload: the ruleset
-- key) fires once when something was priced. reason with rows: nil when
-- stored, "noruleset" or "ruleset" as ns.Search.Item. rows nil: "closed" (the
-- AH closed, or was closed when asked: onDone runs before Query returns
-- false), "timeout", "error" (also the client's AUCTION_HOUSE_BROWSE_FAILURE),
-- "dropped" (ns.AH.Drop(tag): nothing stored).
--
-- How (tests/blizzard/api/AuctionHouseDocumentation.lua): SendBrowseQuery(query)
-- (counts toward the 100 a minute: search = true, a guess; the docs limit
-- SendSearchQuery alone), done on AUCTION_HOUSE_BROWSE_RESULTS_UPDATED. More
-- pages: RequestMoreBrowseResults() (not counted) until HasFullBrowseResults,
-- at most MAX_PAGES; a page is done on _ADDED or _UPDATED (which one follows
-- is unknown, as for ns.Search) once the rows grew or the list is full. The
-- game has no GetNumBrowseResults: GetBrowseResults() is the whole list (a
-- copy), asked once per result event for its length (none when the list is full) and once more at the end, when
-- the rows are read from that copy SLICE a frame (so a later query can't
-- change what is being read).
--
-- One query at a time, each with all its pages: the client keeps one browse
-- list, so a second query goes out only after the one before it has its list
-- in hand; ns.Browse.Pending() counts those running or waiting. They wait here,
-- not in ns.AH, so a drop (the "AHDrop" ns.AH.Drop fires) ends them too.

local _, ns = ...

local Browse = {}
ns.Browse = Browse

Browse.MAX_PAGES = 20   -- pages per query, the first included: 1000 rows at the client's 50 a page
Browse.TAG = "search"

local active           -- the query asking and reading now, nil when none
local line = {}        -- queries waiting their turn (oldest first)

function Browse.Pending()
    return (active and 1 or 0) + #line
end

local ask, nextInLine

-- Ends `j` once: its caller hears the result, then the next in line asks.
local function finish(j, rows, reason)
    if j.done then return end
    j.done, j.reason = true, reason
    local wasActive = active == j
    if wasActive then active = nil end
    ns.SafeCall(j.onDone, rows, reason, rows and j.capped or nil)
    if wasActive then nextInLine() end
end

local function guarded(fn, j, ...)
    if not ns.SafeCall(fn, j, ...) then finish(j, nil, "error") end
end

nextInLine = function()
    while not active and line[1] do
        local j = table.remove(line, 1)
        if not j.done then
            active = j
            guarded(ask, j, false)
        end
    end
end

-- ---------------------------------------------------------------------
-- Reading the results
-- ---------------------------------------------------------------------

local function browseResults()
    local list = C_AuctionHouse.GetBrowseResults()
    return type(list) == "table" and list or {}
end

local function hasFull()
    return C_AuctionHouse.HasFullBrowseResults() == true
end

local function readRow(j, r)
    if type(r) ~= "table" then return end
    local key, base = ns.Items.KeyOf(r.itemKey)
    local price, qty = r.minPrice, r.totalQuantity
    if not key or type(price) ~= "number" or type(qty) ~= "number" then return end
    if key ~= base then ns.Items.LearnKey(r.itemKey) end
    ns.Rows.Add(j.set, key, base, price, qty)
    j.rows[#j.rows + 1] = {
        itemKey = r.itemKey, itemID = r.itemKey.itemID, key = key, base = base,
        minPrice = price, qty = qty, owned = r.containsOwnerItem == true,
    }
end

-- Every row read: stored under the ruleset the query started in, if it
-- still is the current one.
local function complete(j)
    local rkey = j.rkey
    if rkey == nil then return finish(j, j.rows, "noruleset") end
    if ns.Ruleset.Key() ~= rkey then return finish(j, j.rows, "ruleset") end
    local at, priced = ns.Game.Now(), false
    for _, r in ipairs((ns.Rows.Records(j.set.list))) do
        if ns.Store.Record(rkey, r.key, r.unit, r.qty, at) then priced = true end
    end
    if priced then ns.Fire("PricesChanged", rkey) end
    finish(j, j.rows)
end

local schedule

local function slice(j)
    j.scheduled = false
    if j.done then return end
    if not ns.AH.IsOpen() then return finish(j, nil, "closed") end
    local last = math.min(j.nextRow + ns.Game.SLICE - 1, #j.list)
    for index = j.nextRow, last do readRow(j, j.list[index]) end
    j.nextRow = last + 1
    if j.nextRow <= #j.list then return schedule(j) end
    complete(j)
end

schedule = function(j)
    if j.scheduled or j.done then return end
    j.scheduled = true
    C_Timer.After(0, function() guarded(slice, j) end)
end

-- ---------------------------------------------------------------------
-- Asking: the query, then a page at a time
-- ---------------------------------------------------------------------

local function answered(j, ok, reason)
    if j.done then return end
    -- a later page that never answers: the pages already in stand
    if not ok and reason == "timeout" and j.pages > 1 then
        ok, j.full = true, true
    end
    if not ok then return finish(j, nil, reason or "error") end
    local full = j.full or hasFull()
    if not full and j.pages < Browse.MAX_PAGES then return ask(j, true) end
    j.list, j.nextRow = browseResults(), 1
    if not full then j.capped = #j.list end
    schedule(j)
end

local function failed()
    return false, "error"
end

ask = function(j, more)
    j.pages = j.pages + 1
    local events = { AUCTION_HOUSE_BROWSE_FAILURE = failed }
    if more then
        -- full: no count needed; else one copy of the list per event, against the count last seen
        local grew = function()
            if hasFull() then return true end
            local n = #browseResults()
            local was = j.count
            j.count = n
            return n > was
        end
        events.AUCTION_HOUSE_BROWSE_RESULTS_ADDED = grew
        events.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = grew
    else
        events.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function()
            j.count = #browseResults()
            return true
        end
    end
    ns.AH.Request({
        name = more and "browse: more results" or "browse",
        search = not more,
        tag = j.tag,
        events = events,
        send = function()
            if not more then
                C_AuctionHouse.SendBrowseQuery(j.query)
                return
            end
            -- the list is full already (HasFull said no just before: never
            -- seen): nothing goes out, read what is there
            if hasFull() then
                j.full = true
                return "answered"
            end
            C_AuctionHouse.RequestMoreBrowseResults()
        end,
        onDone = function(ok, reason) guarded(answered, j, ok, reason) end,
    })
end

-- Browses the AH (see the top of this file). Returns true when started;
-- false and the reason when it ended at once (onDone has run then).
function Browse.Query(query, onDone, tag)
    if type(query) ~= "table" or type(query.searchString) ~= "string" then
        error("ns.Browse.Query needs a browse query table with a searchString", 2)
    end
    local j = {
        query = {
            searchString = query.searchString, sorts = query.sorts or {}, minLevel = query.minLevel,
            maxLevel = query.maxLevel, filters = query.filters, itemClassFilters = query.itemClassFilters,
        },
        onDone = onDone or function() end, tag = tag or Browse.TAG, rkey = ns.Ruleset.Key(),
        set = ns.Rows.New(), rows = {}, pages = 0,
    }
    if not ns.AH.IsOpen() then
        finish(j, nil, "closed")
        return false, "closed"
    end
    line[#line + 1] = j
    nextInLine()
    if j.done then return false, j.reason end
    return true
end

-- Ends everything of the tag that waits or runs; the line is cleared before
-- the running one ends, so the next of the same tag can't start.
ns.On("AHDrop", function(tag)
    local kept, dropped = {}, {}
    for _, j in ipairs(line) do
        if j.tag == tag then dropped[#dropped + 1] = j else kept[#kept + 1] = j end
    end
    line = kept
    for _, j in ipairs(dropped) do finish(j, nil, "dropped") end
    if active and active.tag == tag then finish(active, nil, "dropped") end
end)

ns.On("AHClosed", function()
    local waiting = line
    line = {}
    if active then finish(active, nil, "closed") end
    for _, j in ipairs(waiting) do finish(j, nil, "closed") end
end)
