-- Search: one item's current prices from a targeted Auction House search.
--
--   ns.Search.Item(itemID, function(rows, reason, auctions) end, opts) -> true | false, reason
--   opts (all optional):
--     pages     how many pages it may read (default MAX_PAGES). A price check needs only the
--               first: results come cheapest first, so the cheapest price is always on it
--     onPage    function(rows, auctions) after each page but the last, with everything read so
--               far, so a list can show the first page while the rest comes in
--     priority  the player is waiting on it: goes ahead of background checks
--     refresh   the client already holds this item's results (after a purchase): asks them
--               again the way the game's own window does (Refresh*SearchResults), which isn't a
--               SendSearchQuery and doesn't count toward the 100 a minute
--   ns.Search.Cancel(itemID, onDone)   that caller no longer wants the answer; a search nobody
--                                      waits for stops, and the line goes to the next
--   ns.Search.Last(itemID) -> rows, auctions, age   copies of the last answer this visit, nil
--                                      when none (Sell and My auctions share their checks)
--
-- rows: one row per price key (ns.Rows: { key, base, unit, qty }), each
-- suffix of a random-suffix item its own row. They are recorded under the
-- ruleset the search started in (ns.Store.Record, each suffixed key and its
-- plain itemID key, stamped ns.Game.Now()) and "PricesChanged" (payload: the
-- ruleset key) fires once when something was priced. reason with rows: nil
-- when stored, "noruleset" (no ruleset known: nothing stored; the AH's
-- first-visit line already asked for one) or "ruleset" (it changed during the
-- search: nothing stored, like the full scan). rows nil: "closed" (the AH
-- closed, or was closed when asked: onDone runs before Item returns false),
-- "uncached" (the client never learned the item's key: ITEM_WAIT seconds, or
-- at once when it says no data is coming), "timeout", "error".
--
-- auctions.capped is true when more results were up than were read (the page cap, or a later
-- page that never answered).
-- auctions (nil with no rows): the raw results in the order the client gave
-- them (cheapest first), one per row read, for buying and posting: a
-- commodity's { unit, qty, own (how many of them are this character's:
-- numOwnerItems), acct, owner, owners (every seller of that price), timeLeft (the
-- band of timeLeftSeconds, nil when the game doesn't say) } per price; gear's { auctionID, unit = buyout each (0: bid
-- only), buyout (what one costs, one click buys one: the same as unit, 0: bid only:
-- it can be bid on, never bought), minBid, bid (the standing bid, 0 none), qty (how
-- many like auctions the row holds), key, timeLeft
-- (Enum.AuctionHouseTimeLeftBand), owner (the first of owners), own (qty when
-- it is the player's: containsOwnerItem, else 0), acct }. acct = how many are your
-- other characters' (containsAccountItem), never counted in own: an alt's auction can
-- still be bought, but posting doesn't undercut it. A commodity price says only that
-- some are the account's, so acct is all of its units that aren't own (a GUESS: the
-- game gives no split). auctions.commodity: true for a commodity's (the game's
-- isCommodity), false for gear's. Each caller gets its own copy.
--
-- How (tests/blizzard/api/AuctionHouseDocumentation.lua): the item key is
-- MakeItemKey(itemID) (the client fills in the item's level; a sell search
-- clears it and the suffix, see below). The client ignores a search for a
-- key whose info it doesn't have yet, so GetItemKeyInfo is waited for first
-- (ITEM_KEY_ITEM_INFO_RECEIVED; item data asked with
-- C_Item.RequestLoadItemDataByID). Its isCommodity picks the results, its
-- isEquipment the query: gear that doesn't stack goes through SendSellSearchQuery, the one the docs
-- give a cleared key to (every level and suffix comes back; the game's sell
-- frame does it: ConvertItemSellItemKey); SendSearchQuery with a cleared key
-- finds no suffixed gear (seen in play). The rest: SendSearchQuery(itemKey,
-- sorts, false). Sorted by price, cheapest
-- first (Enum.AuctionHouseSortOrder.Price; no sorts when the enum is
-- missing), so the page cap keeps the cheapest pages, then
-- COMMODITY_SEARCH_RESULTS_UPDATED(itemID) or ITEM_SEARCH_RESULTS_UPDATED
-- (itemKey, matched by its itemID). Every page is its own ns.AH.Request. Only
-- the search counts toward the 100 a minute (search = true): the docs limit
-- SendSearchQuery alone, so the extra pages (RequestMore*, search = false)
-- don't. Which event follows RequestMore* is unknown (the docs list *_ADDED
-- and *_UPDATED; a probe question): a page is done on either, once the rows
-- grew or the list is full. Pages are asked until HasFull*, at most MAX_PAGES
-- (a HasFull that never says yes can't loop), or until RequestMore* says the
-- list is full already (nothing sent: the runner's "answered", no wait); the
-- pages read are priced then. Each page's new rows are read as it arrives, SLICE a
-- frame. A first answer with no rows that doesn't say it's whole is asked once more (the
-- server sometimes answers empty when there are auctions), and so is a first page that
-- never answers. Item rows: unit = buyoutAmount (the price of one), bid-only rows skipped,
-- the key from the row's itemKey when it has a suffix, else itemLink; commodity
-- rows: unitPrice. Rows under a copper each
-- are skipped (ns.Rows.Add). A second search for an item being searched waits
-- for the same answer (each caller gets its own copy of the rows).
--
-- One search at a time: whether the client keeps results per item or only
-- the latest search's is unknown (a probe question), so a search's query
-- goes out only after the one before it finished, its last row read. Waiting
-- for an item's key info runs beside that (it reads no results).

local _, ns = ...

local Search = {}
ns.Search = Search

Search.MAX_PAGES = 20   -- pages per search, the first included: 1000 rows at the client's 50 a page

local ITEM_EVENTS = { "ITEM_KEY_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }

local frame = CreateFrame("Frame")   -- item events, only while a search waits for its key info
local jobs = {}                      -- itemID -> the search in progress
local numJobs = 0
local waiting = {}                   -- itemID -> the search waiting for its key info
local numWaiting = 0
local active                         -- the search asking and reading now, nil when none
local line = {}                      -- searches with their key info, waiting their turn (oldest first)
local last = {}                      -- itemID -> { rows, auctions, at }: the last answer this visit

-- The item's equip slot (Enum.InventoryType), nil when it has none or the game
-- hasn't loaded it. The Add panes' category box (Query.ItemPasses).
function Search.Slot(itemID)
    if not (C_Item and C_Item.GetItemInventoryTypeByID) then return nil end
    return C_Item.GetItemInventoryTypeByID(itemID)
end

-- Whether the item stacks (ammo, thrown weapons). The game can call ammo
-- equipment because it goes in the ammo slot, but a sell search for anything
-- that stacks never brings results, so those are searched like any other stack.
function Search.Stacks(itemID)
    if not (C_Item and C_Item.GetItemInfo) then return false end
    local most = select(8, C_Item.GetItemInfo(itemID))
    return type(most) == "number" and most > 1
end

-- Searches in progress.
function Search.Pending()
    return numJobs
end

local function stopWaiting(j)
    if j.timer then
        j.timer:Cancel()
        j.timer = nil
    end
    if waiting[j.itemID] ~= j then return end
    waiting[j.itemID] = nil
    numWaiting = numWaiting - 1
    if numWaiting == 0 then
        for _, event in ipairs(ITEM_EVENTS) do frame:UnregisterEvent(event) end
    end
end

-- Ends `j`: nothing of it keeps listening, its timers do nothing, and every
-- caller waiting on it hears once, each with its own copy of the rows.
local function copyRows(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = { key = r.key, base = r.base, unit = r.unit, qty = r.qty } end
    return out
end

local function copyAuctions(auctions)
    local out = {}
    for i, a in ipairs(auctions) do
        local c = {}
        for k, v in pairs(a) do c[k] = v end
        out[i] = c
    end
    out.commodity = auctions.commodity
    return out
end

local ask

-- The next search in line asks, unless one is asking or reading already.
local function nextInLine()
    while not active and line[1] do
        local j = table.remove(line, 1)
        if not j.done then
            active = j
            ask(j, false)
        end
    end
end

local function finish(j, rows, reason)
    if j.done then return end
    j.done, j.reason = true, reason
    if jobs[j.itemID] == j then
        jobs[j.itemID] = nil
        numJobs = numJobs - 1
    end
    stopWaiting(j)
    local wasActive = active == j
    if wasActive then active = nil end
    if rows then last[j.itemID] = { rows = copyRows(rows), auctions = copyAuctions(j.auctions), at = GetTime() } end
    for i, c in ipairs(j.callbacks) do
        local own = rows and i > 1
        ns.SafeCall(c.done, own and copyRows(rows) or rows, reason,
            rows and (own and copyAuctions(j.auctions) or j.auctions) or nil)
    end
    -- the next one's query goes out only now: this one's rows are all read
    if wasActive then nextInLine() end
end

-- Everything read so far, to each caller that wants to see pages come in.
local function tellPage(j)
    for _, c in ipairs(j.callbacks) do
        if c.page then ns.SafeCall(c.page, copyRows(j.rows.list), copyAuctions(j.auctions)) end
    end
end

-- Runs fn(j, ...); an error is reported and ends the search instead of
-- leaving it waiting forever.
local function guarded(fn, j, ...)
    if not ns.SafeCall(fn, j, ...) then finish(j, nil, "error") end
end

-- ---------------------------------------------------------------------
-- Reading the results
-- ---------------------------------------------------------------------

local function hasFull(j)
    if j.commodity then return C_AuctionHouse.HasFullCommoditySearchResults(j.itemID) == true end
    return C_AuctionHouse.HasFullItemSearchResults(j.itemKey) == true
end

local function numResults(j)
    if j.commodity then return tonumber(C_AuctionHouse.GetNumCommoditySearchResults(j.itemID)) or 0 end
    return tonumber(C_AuctionHouse.GetNumItemSearchResults(j.itemKey)) or 0
end

-- Seconds left as the game's time-left band (the docs' bands: Search/Query.lua's
-- left/ words), nil when the game doesn't say.
local function bandOf(seconds)
    if type(seconds) ~= "number" then return nil end
    local e = Enum and Enum.AuctionHouseTimeLeftBand or {}
    if seconds < 1800 then return e.Short or 0 end
    if seconds < 7200 then return e.Medium or 1 end
    if seconds < 43200 then return e.Long or 2 end
    return e.VeryLong or 3
end

-- One result row (1-based) into the search's rows and auctions.
local function readRow(j, index)
    if j.commodity then
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(j.itemID, index)
        if type(r) ~= "table" then return end
        if ns.Rows.Add(j.rows, j.key, j.key, r.unitPrice, r.quantity) then
            local own = math.min(tonumber(r.numOwnerItems) or 0, r.quantity)
            local owners = type(r.owners) == "table" and r.owners or nil
            -- the flag says "some of it": it's your alt's only when no one else is in the step
            local others = (tonumber(r.totalNumberOfOwners) or 1) - (own > 0 and 1 or 0)
            j.auctions[#j.auctions + 1] = { unit = math.floor(r.unitPrice), qty = r.quantity, own = own,
                acct = r.containsAccountItem == true and others <= 1 and r.quantity - own or 0,
                owner = owners and owners[1] or nil, owners = owners, timeLeft = bandOf(r.timeLeftSeconds) }
        end
        return
    end
    local r = C_AuctionHouse.GetItemSearchResultInfo(j.itemKey, index)
    if type(r) ~= "table" then return end
    local buyout, qty = r.buyoutAmount, r.quantity
    if type(qty) ~= "number" or qty <= 0 then return end
    local key, base = ns.Items.Key(r.itemLink)
    if not key or ns.Items.ID(key) ~= j.itemID then key, base = j.key, j.key end
    -- the row's own key holds the AH's suffix number; Forever's link doesn't
    local rowKey, rowBase = ns.Items.KeyOf(r.itemKey)
    if rowKey and rowKey ~= rowBase and rowBase == j.key then
        ns.Items.LearnKey(r.itemKey, r.itemLink)
        key, base = rowKey, rowBase
    end
    local bought = type(buyout) == "number" and buyout > 0
    -- bid-only rows are priced by nothing, but can be bid on: auctions keep them
    -- buyoutAmount is the price of ONE, never divided by quantity (areas/game.md)
    if bought then ns.Rows.Add(j.rows, key, base, buyout, qty) end
    local owner = type(r.owners) == "table" and r.owners[1] or nil
    j.auctions[#j.auctions + 1] = {
        auctionID = r.auctionID, unit = bought and math.floor(buyout) or 0, buyout = bought and buyout or 0,
        minBid = tonumber(r.minBid) or 0, bid = tonumber(r.bidAmount) or 0, qty = qty, key = key,
        timeLeft = r.timeLeft, owner = owner, own = r.containsOwnerItem == true and qty or 0,
        acct = r.containsAccountItem == true and r.containsOwnerItem ~= true and qty or 0,
    }
end

-- Every row read: stored under the ruleset the search started in, if it
-- still is the current one.
local function complete(j)
    local rows, rkey = j.rows.list, j.rkey
    if rkey == nil then return finish(j, rows, "noruleset") end
    if ns.Ruleset.Key() ~= rkey then return finish(j, rows, "ruleset") end
    local at, priced = ns.Game.Now(), false
    for _, r in ipairs((ns.Rows.Records(rows))) do
        if ns.Store.Record(rkey, r.key, r.unit, r.qty, at) then priced = true end
    end
    if priced then ns.Fire("PricesChanged", rkey, j.key) end   -- the one item it priced
    finish(j, rows)
end

local schedule

local function slice(j)
    j.scheduled = false
    if j.done then return end
    if not ns.AH.IsOpen() then return finish(j, nil, "closed") end
    local upTo = math.min(j.nextRow + ns.Game.SLICE - 1, j.total)
    local stop, index = ns.Game.Deadline(), j.nextRow
    while index <= upTo do
        readRow(j, index)
        index = index + 1
        if ns.Game.Late(stop) then break end
    end
    j.nextRow = index
    if j.nextRow <= j.total then return schedule(j) end
    j.afterRead(j)
end

schedule = function(j)
    if j.scheduled or j.done then return end
    j.scheduled = true
    C_Timer.After(0, function() guarded(slice, j) end)
end

-- ---------------------------------------------------------------------
-- Asking: the search, then a page at a time
-- ---------------------------------------------------------------------

-- Cheapest first, asked for explicitly: MAX_PAGES then keeps the cheapest
-- pages whatever the server's own order is. No sorts when the game has no
-- such enum (the server's order then). A fresh table each call; the browse
-- query (ns.Query.Server) sends the same.
function Search.PriceSort()
    local order = Enum and Enum.AuctionHouseSortOrder
    if type(order) == "table" and order.Price ~= nil then
        return { { sortOrder = order.Price, reverseSort = false } }
    end
    return {}
end
local priceSort = Search.PriceSort

-- The pages so far are read: ask for the next, or price what is there.
local function pageRead(j)
    if not j.full and j.pages < j.maxPages and not hasFull(j) then
        tellPage(j)
        return ask(j, true)
    end
    if j.cut or not (j.full or hasFull(j)) then j.auctions.capped = true end
    complete(j)
end

local function answered(j, ok, reason)
    if j.done then return end
    if not ok and reason == "timeout" then
        if j.pages > 1 then
            -- a later page that never answers: the pages already in stand
            ok, j.full, j.cut = true, true, true
        elseif not j.retried then
            j.retried, j.pages = true, 0
            return ask(j, false)
        end
    end
    if not ok then return finish(j, nil, reason or "error") end
    if j.pages == 1 and numResults(j) == 0 and not hasFull(j) and not j.retried then
        -- an empty first answer that doesn't say it's whole: once more before "nobody sells it"
        j.retried, j.pages = true, 0
        return ask(j, false)
    end
    j.total = numResults(j)
    j.afterRead = pageRead
    schedule(j)
end

local function forItem(j, event)
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
        return function(itemID) return itemID == j.itemID end
    end
    return function(itemKey) return type(itemKey) == "table" and itemKey.itemID == j.itemID end
end

-- The search is done on its *_UPDATED. A page asked with RequestMore* is
-- done on *_ADDED or *_UPDATED (which one follows is unknown: a probe
-- question), but only once the rows grew past what they were when it was
-- sent, or the list is full: a late event from the page before can't end it.
local function resultEvents(j, more, before)
    local names = j.commodity and { "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED" }
        or { "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED" }
    local events = {}
    for i = 1, more and 2 or 1 do
        local mine = forItem(j, names[i])
        events[names[i]] = function(...)
            if not mine(...) then return nil end
            if not more then return true end
            return numResults(j) > before.count or hasFull(j)
        end
    end
    return events
end

ask = function(j, more)
    j.pages = j.pages + 1
    local before = { count = 0 }
    local api = C_AuctionHouse
    local refresh = not more and j.refresh and api.HasSearchResults ~= nil
        and api.HasSearchResults(j.itemKey) == true
    if not more then
        -- a new answer replaces the list: read it from the top
        j.nextRow, j.rows, j.auctions = 1, ns.Rows.New(), { commodity = j.commodity }
    end
    ns.AH.Request({
        name = more and "search: more results" or (refresh and "search: refresh" or "search"),
        -- the docs' 100 a minute names SendSearchQuery only: more pages and refreshes don't count
        search = not more and not refresh,
        priority = j.priority, tag = j.tag,
        events = resultEvents(j, more, before),
        send = function()
            if refresh then
                if j.commodity then api.RefreshCommoditySearchResults(j.itemID)
                else api.RefreshItemSearchResults(j.itemKey) end
                return
            end
            if not more then
                if j.equipment then
                    api.SendSellSearchQuery(j.itemKey, priceSort(), false)
                else
                    api.SendSearchQuery(j.itemKey, priceSort(), false)
                end
                return
            end
            before.count = numResults(j)
            local full
            if j.commodity then
                full = api.RequestMoreCommoditySearchResults(j.itemID)
            else
                full = api.RequestMoreItemSearchResults(j.itemKey)
            end
            -- true: the list is full already and nothing went out (HasFull
            -- said no just before: never seen). Read what is there, now.
            if full == true then
                j.full = true
                return "answered"
            end
        end,
        onDone = function(ok, reason) guarded(answered, j, ok, reason) end,
    })
end

-- ---------------------------------------------------------------------
-- The item's key info
-- ---------------------------------------------------------------------

-- Starts the search once the client knows the key; false while it doesn't.
local function tryStart(j)
    if j.queued then return true end   -- in line already: a late item event changes nothing
    local info = C_AuctionHouse.GetItemKeyInfo(j.itemKey)
    if type(info) ~= "table" then return false end
    stopWaiting(j)
    j.commodity = info.isCommodity == true
    j.auctions.commodity = j.commodity
    j.equipment = info.isEquipment == true and not j.commodity and not Search.Stacks(j.itemID)
    -- the sell search wants level and suffix cleared (the docs; the game's
    -- ConvertItemSellItemKey). MakeItemKey fills in the item's level, and sent
    -- so the client never fires a results event (in play: a 10 s timeout each)
    if j.equipment then j.itemKey.itemLevel, j.itemKey.itemSuffix = 0, 0 end
    j.queued = true
    if j.priority then table.insert(line, 1, j) else line[#line + 1] = j end
    nextInLine()
    return true
end

local function giveUp(j)
    if j.done or tryStart(j) then return end   -- one last look: an event may have been missed
    finish(j, nil, "uncached")
end

local function wait(j)
    waiting[j.itemID] = j
    numWaiting = numWaiting + 1
    if numWaiting == 1 then
        for _, event in ipairs(ITEM_EVENTS) do frame:RegisterEvent(event) end
    end
    j.timer = C_Timer.NewTimer(ns.Game.ITEM_WAIT, function()
        j.timer = nil
        guarded(giveUp, j)
    end)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(j.itemID) end
end

frame:SetScript("OnEvent", function(_, event, itemID, success)
    local j = waiting[itemID]
    if not j then return end
    if success == false and event ~= "ITEM_KEY_ITEM_INFO_RECEIVED" then
        return finish(j, nil, "uncached")   -- the game says no data is coming
    end
    guarded(tryStart, j)
end)

local function start(j)
    j.itemKey = C_AuctionHouse.MakeItemKey(j.itemID)
    if not tryStart(j) then wait(j) end
end

-- Searches the AH for one item (see the top of this file). Returns true
-- when started (or joined to a search for the same item already running);
-- false and the reason when it ended at once (onDone has run then).
local function caller(onDone, opts)
    return { done = onDone or function() end, page = opts and opts.onPage or nil }
end

function Search.Item(itemID, onDone, opts)
    if type(itemID) ~= "number" or itemID <= 0 or itemID ~= math.floor(itemID) then
        error("ns.Search.Item needs an itemID (a whole number)", 2)
    end
    opts = opts or {}
    local pages = math.max(1, math.min(Search.MAX_PAGES, tonumber(opts.pages) or Search.MAX_PAGES))
    local running = jobs[itemID]
    if running then
        running.callbacks[#running.callbacks + 1] = caller(onDone, opts)
        if pages > running.maxPages then running.maxPages = pages end
        if opts.priority and not running.priority then
            running.priority = true
            for i, queued in ipairs(line) do
                if queued == running then table.remove(line, i); table.insert(line, 1, running); break end
            end
        end
        return true
    end
    local j = {
        itemID = itemID, key = (ns.Items.Key(itemID)), callbacks = { caller(onDone, opts) },
        rows = ns.Rows.New(), auctions = {}, pages = 0, rkey = ns.Ruleset.Key(),
        maxPages = pages, priority = opts.priority == true, refresh = opts.refresh == true, tag = {},
    }
    if not ns.AH.IsOpen() then
        finish(j, nil, "closed")
        return false, "closed"
    end
    jobs[itemID] = j
    numJobs = numJobs + 1
    guarded(start, j)
    if j.done then return false, j.reason end   -- rows are read a frame later at the soonest
    return true
end

function Search.Cancel(itemID, onDone)
    local j = jobs[itemID]
    if not j or j.done then return end
    for i = #j.callbacks, 1, -1 do
        if j.callbacks[i].done == onDone then table.remove(j.callbacks, i) end
    end
    if #j.callbacks > 0 then return end
    -- nobody waits for it: let go of its request so the next search goes now
    ns.AH.Drop(j.tag)
    finish(j, nil, "dropped")
end

function Search.Last(itemID)
    local l = last[itemID]
    if not l then return nil end
    return copyRows(l.rows), copyAuctions(l.auctions), GetTime() - l.at
end

ns.On("AHClosed", function()
    -- clearing a field while walking the table is allowed
    for _, j in pairs(jobs) do finish(j, nil, "closed") end
    last = {}
end)
