-- Replicate: every auction on the Auction House at once (the game's
-- ReplicateItems list), turned into one plain row per price key:
--   { key = "7429:-15", base = "7429", unit = lowest copper each, qty = how many }
--
--   ns.Replicate.Start(function(rows, reason, skipped, total) end, onSent)
--     rows nil: reason "closed", "timeout", "error", "empty" (the list
--     stayed empty, or had nothing to price); skipped: how many items
--     were left out because the game never loaded them (0 when none);
--     total: how many auctions the list had.
--     onSent(): runs when ReplicateItems went out (the game's cooldown
--     starts there, whatever happens next).
--   ns.Replicate.Progress() -> read, total, waiting, peak, unique   (nil when none: the scan band)
--
-- Only on request (ns.Scan.Full: the player asked). The list is asked through
-- ns.AH.Request, then read SLICE rows a frame so a big AH stays smooth.
-- Rows the game can't price are skipped: bid only (buyout 0), count 0, no
-- item or an item that no longer exists. A row whose item the game doesn't
-- know yet (hasAllInfo false: no link, so no suffix) waits for the item's
-- data and is read again. On a cold cache (a first scan) thousands of items
-- load one after another, so the wait ends only after ITEM_WAIT seconds in
-- which no item arrived at all (each arrival restarts that clock), and at
-- most ITEM_WAIT_MAX seconds after the first item was asked for; the items
-- still missing then are skipped and counted. An item the game says can't
-- load is skipped at once (not counted: scanning again wouldn't help). The
-- AH closing part way throws everything away: half a scan prices nothing.

local _, ns = ...

local Replicate = {}
ns.Replicate = Replicate

Replicate.TIMEOUT = 90   -- seconds for the list: a big AH takes a while to answer
Replicate.SETTLE = 2       -- seconds the list must hold still before the scan is done (guess)
Replicate.EMPTY_WAIT = 15  -- seconds an empty list gets to fill before it counts as empty (guess)
local LOOK = 0.25        -- seconds between looks while the list settles
local MIN_LOOK = 0.05    -- seconds at least between looks at the item wait's end
local EPS = 1e-6
local ITEM_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }

local frame = CreateFrame("Frame")   -- item data events, only while a list is being read
local job                            -- the scan in progress, nil when none

function Replicate.Running()
    return job ~= nil
end

-- Rows read so far and the list's size (0, 0 until the list arrives), items
-- the game is still loading and the most it ever was, and how many different
-- items the rows held; nil when no list is being read.
function Replicate.Progress()
    if not job then return nil end
    return job.nextIndex, job.total, job.numWaiting, job.peakWaiting, job.unique
end

-- Ends `j`: nothing of it keeps listening, and its timers do nothing.
local function finish(j, rows, reason, skipped, total)
    if j.done then return end
    j.done, j.reason = true, reason
    if job == j then
        job = nil
        for _, event in ipairs(ITEM_EVENTS) do frame:UnregisterEvent(event) end
    end
    if j.timer then
        j.timer:Cancel()
        j.timer = nil
    end
    if j.onDone then ns.SafeCall(j.onDone, rows, reason, skipped, total) end
end

local armTimer, schedule

-- When the wait for items ends: ITEM_WAIT after the last arrival (or after
-- the wait began), and never later than ITEM_WAIT_MAX after the first ask.
local function waitEnds(j)
    return math.min(j.lastProgress + ns.Game.ITEM_WAIT, j.firstAsk + ns.Game.ITEM_WAIT_MAX)
end

-- An item the game never loaded in time: its rows are skipped, counted once.
local function skip(j, itemID)
    if j.gaveUp[itemID] then return end
    j.gaveUp[itemID] = true
    j.skipped = j.skipped + 1
end

-- Waits for the item's data, the row read again when it comes; or skips the
-- row (the item was given up on, the game said no data is coming, or the
-- wait is past ITEM_WAIT_MAX).
local function wait(j, itemID, index)
    local entry = j.waiting[itemID]
    if entry then
        entry[#entry + 1] = index
        return
    end
    if j.failed[itemID] or j.gaveUp[itemID] then return end
    local now = GetTime()
    if j.firstAsk and now + EPS >= j.firstAsk + ns.Game.ITEM_WAIT_MAX then return skip(j, itemID) end
    j.firstAsk = j.firstAsk or now
    -- nothing was waiting: the quiet clock starts now
    if j.numWaiting == 0 then j.lastProgress = now end
    if not j.asked[itemID] then
        j.asked[itemID] = true
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    end
    j.waiting[itemID] = { index }
    j.numWaiting = j.numWaiting + 1
    j.peakWaiting = math.max(j.peakWaiting, j.numWaiting)
    armTimer(j)
end

-- One replicate row (0-based) into the job's rows.
local function read(j, index)
    local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAllInfo =
        C_AuctionHouse.GetReplicateItemInfo(index)
    if type(itemID) ~= "number" then
        j.blank[#j.blank + 1] = index   -- may only not be ready yet: settle reads it again
        return
    end
    if not j.seen[itemID] then
        j.seen[itemID] = true
        j.unique = j.unique + 1
    end
    if type(count) ~= "number" or count <= 0 or type(buyout) ~= "number" or buyout <= 0 then return end
    -- under a copper each can't be stored (copper integers): such a stack
    -- would otherwise be the "lowest" and leave the item unpriced
    local unit = math.floor(buyout / count)
    if unit < 1 then return end
    if C_Item and C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(itemID) then return end
    if not hasAllInfo then
        -- read again when the item's data comes; skipped when it can't wait
        -- (waited ITEM_WAIT already, or the game said no data is coming)
        wait(j, itemID, index)
        return
    end
    local key, base = ns.Items.Key(C_AuctionHouse.GetReplicateItemLink(index))
    if not key or ns.Items.ID(key) ~= itemID then key, base = ns.Items.Key(itemID) end
    if not key then return end
    ns.Rows.Add(j.rows, key, base, unit, count)
    -- Kept for a crate's bundle lines, which name their items.
    j.names = j.names or ns.Items.Names()
    ns.Items.LearnName(name, itemID, j.names)
end

local function listSize()
    return tonumber(C_AuctionHouse.GetNumReplicateItems()) or 0
end

-- Every row seen so far is read. The game's "list is ready" can come before
-- the list is (guess, from TSM waiting and re-reading; the docs don't say), so
-- "done" waits until the list stopped growing and blank rows stopped filling
-- in for SETTLE seconds (EMPTY_WAIT while it is still empty). Nothing priced
-- then is "empty", never a finished scan.
local function settle(j)
    local size = listSize()
    if size > j.total then
        j.total, j.stillAt = size, nil
        return schedule(j)
    end
    if j.numWaiting > 0 then return end   -- each arrival and the wait's timer come back here
    if #j.blank ~= j.blanks then j.blanks, j.stillAt = #j.blank, nil end
    local now = GetTime()
    j.stillAt = j.stillAt or now
    local quiet = j.total > 0 and Replicate.SETTLE or Replicate.EMPTY_WAIT
    if now + EPS >= j.stillAt + quiet then
        if #j.rows.list == 0 then return finish(j, nil, "empty") end
        return finish(j, j.rows.list, nil, j.skipped, j.total)
    end
    if j.looking then return end
    j.looking = true
    C_Timer.After(LOOK, function()
        j.looking = false
        if job ~= j then return end
        local blank = j.blank
        j.blank = {}
        for _, index in ipairs(blank) do
            j.readyTail = j.readyTail + 1
            j.ready[j.readyTail] = index
        end
        schedule(j)
    end)
end

-- One frame's work: rows whose item arrived first, then the next new rows,
-- SLICE in all; then the wait for the list to settle.
local function slice(j)
    j.scheduled = false
    if job ~= j then return end
    if not ns.AH.IsOpen() then return finish(j, nil, "closed") end
    local budget = ns.Game.SLICE
    while budget > 0 do
        if j.readyHead <= j.readyTail then
            local index = j.ready[j.readyHead]
            j.ready[j.readyHead] = nil
            j.readyHead = j.readyHead + 1
            read(j, index)
        elseif j.nextIndex < j.total then
            read(j, j.nextIndex)
            j.nextIndex = j.nextIndex + 1
        else
            break
        end
        budget = budget - 1
    end
    if j.readyHead > j.readyTail then
        j.ready, j.readyHead, j.readyTail = {}, 1, 0
    end
    if j.nextIndex < j.total or j.readyHead <= j.readyTail then return schedule(j) end
    settle(j)
end

schedule = function(j)
    if j.scheduled or job ~= j then return end
    j.scheduled = true
    -- a row that raises ends the scan (reported) instead of leaving it running forever
    C_Timer.After(0, function()
        if not ns.SafeCall(slice, j) then finish(j, nil, "error") end
    end)
end

-- One timer for the end of the wait. When it fires and an item arrived
-- meanwhile, it looks again later; at the end, every item still waited for
-- is given up on (its rows skipped, the item counted).
armTimer = function(j)
    if j.timer or j.numWaiting == 0 then return end
    j.timer = C_Timer.NewTimer(math.max(waitEnds(j) - GetTime(), MIN_LOOK), function()
        j.timer = nil
        if job ~= j then return end
        if GetTime() + EPS >= waitEnds(j) then
            for itemID in pairs(j.waiting) do
                j.waiting[itemID] = nil   -- clearing a field while walking the table is allowed
                skip(j, itemID)
            end
            j.numWaiting = 0
        end
        armTimer(j)
        schedule(j)
    end)
end

-- The game knows an item now (or says it can't): its rows are read again.
-- Either way the game answered: the quiet clock starts over.
local function itemArrived(j, itemID, success)
    local entry = j.waiting[itemID]
    if not entry then return end
    j.waiting[itemID] = nil
    j.numWaiting = j.numWaiting - 1
    j.lastProgress = GetTime()
    if success == false then
        j.failed[itemID] = true   -- no data is coming: later rows of it are skipped too
    else
        for _, index in ipairs(entry) do
            j.readyTail = j.readyTail + 1
            j.ready[j.readyTail] = index
        end
    end
    schedule(j)
end

-- An error here ends the scan (reported) rather than leaving it waiting.
frame:SetScript("OnEvent", function(_, _, itemID, success)
    local j = job
    if not j then return end
    if not ns.SafeCall(itemArrived, j, itemID, success) then finish(j, nil, "error") end
end)

local function begin(j)
    j.total = listSize()
    for _, event in ipairs(ITEM_EVENTS) do frame:RegisterEvent(event) end
    schedule(j)
end

-- Asks for the whole list and reads it; onDone(rows, nil, skipped) when
-- done, or onDone(nil, reason). onSent() when the request went out. Returns
-- true when started; false and "busy" when a list is already being read,
-- false and the reason when it failed at once (onDone has run then).
function Replicate.Start(onDone, onSent)
    if job then return false, "busy" end
    local j = {
        onDone = onDone, rows = ns.Rows.New(), total = 0, nextIndex = 0,
        ready = {}, readyHead = 1, readyTail = 0,
        waiting = {}, numWaiting = 0, peakWaiting = 0, asked = {}, failed = {}, gaveUp = {}, skipped = 0,
        blank = {}, blanks = 0, seen = {}, unique = 0,
    }
    job = j
    ns.AH.Request({
        name = "replicate",
        timeout = Replicate.TIMEOUT,
        wait = Replicate.TIMEOUT,
        send = function()
            C_AuctionHouse.ReplicateItems()
            -- it went out (a send that raised sent nothing): the cooldown starts
            if onSent then ns.SafeCall(onSent) end
        end,
        events = { REPLICATE_ITEM_LIST_UPDATE = function() return true end },
        onDone = function(ok, reason)
            if job ~= j then return end
            if ok then return begin(j) end
            finish(j, nil, reason or "error")
        end,
    })
    if j.done then return false, j.reason end
    return true
end

ns.On("AHClosed", function()
    if job then finish(job, nil, "closed") end
end)
