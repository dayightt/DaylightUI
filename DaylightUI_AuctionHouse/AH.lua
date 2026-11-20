-- AH: whether the Auction House is open, and the one road every request to
-- it takes. The game answers asynchronously and limits how fast we may ask
-- (its throttled message system, and 100 searches a minute), so requests
-- wait in line here: one in flight at a time, first in first out, sent only
-- while the AH is open and the game says it is ready.
--
--   ns.AH.Request({
--       name = "replicate",                 -- for reading the code and reports
--       send = function() C_AuctionHouse.ReplicateItems() end,
--       events = { REPLICATE_ITEM_LIST_UPDATE = function(...) return true end },
--       search = false,                     -- true: counts toward SEARCH_PER_MINUTE
--       timeout = 10,                       -- seconds from sending to the answer
--       wait = 90,                          -- optional: seconds it may wait in line before it's sent
--       onDone = function(ok, reason) end,
--   })
--
-- An event handler gets the event's payload and returns true when the
-- request is done (onDone(true)), or false and a reason to fail it
-- (onDone(false, reason)); anything else keeps waiting. A send that returns
-- "answered" sent nothing (the client already had it, e.g. RequestMore*
-- saying the results are full): the request is done at once, the next goes. Failures: "closed"
-- (the AH closed, or was closed when asked: onDone runs before Request
-- returns false), "timeout", "error" (send or a handler raised: the error
-- goes to the game's error handler like any other). Fires "AHOpened" /
-- "AHClosed" when the window opens and closes.
--
--   tag = "search" on a request lets ns.AH.Drop("search") end every queued one
--   with that tag (onDone(false, "dropped")) and let go of the one in flight:
--   it ends for its caller at once, its answer is ignored, and the next
--   request waits for that answer (or its timeout) because the client allows
--   one message out at a time.
--   Drop fires "AHDrop" (payload: the tag) once the queue is filtered and before any
--   caller hears "dropped", for callers that keep their own line of work behind the
--   runner (ns.Browse); a request made from a "dropped" callback is new and goes out.
--   ns.AH.Act{ name, send, events, timeout, onDone } -> ok, reason sends NOW,
--   inside the player's click (purchases and bids are hardware-only and can't
--   wait in line), or returns false and "closed", "busy", "late" (a message of ours
--   timed out and its answer may still come: AH.LATE) or "throttled"
--   without queueing (then onDone isn't called). True means it was sent: it
--   waits for its answer, or it already ended inside the send and onDone ran
--   (the send raised: onDone(false, "error"), since it may have reached the
--   server, e.g. a quote to let go; it returned "answered": onDone(true)).
--   ns.AH.Busy() = a request is out.
--   ns.AH.Close() asks the game to close the window when it is open.
--
-- Only answers to this addon's own messages count: the game's AuctionHouseFrame sends queries of its own (its OnShow
-- searches the player's favorites, Blizzard_AuctionHouseFrame.lua 396-398,
-- into the one browse list), and a request that timed out may still be
-- answered. Each message of ours is marked out on THROTTLED_MESSAGE_SENT and
-- answered on THROTTLED_MESSAGE_RESPONSE_RECEIVED. An answer that isn't the
-- request in flight's (the game's, or a late one) starts a "tail": for the
-- rest of that frame no event reaches a request and nothing new is sent, so
-- its own events (before or after its RESPONSE_RECEIVED: the order is a
-- guess) never complete ours. A request that timed out with its message out
-- holds the line (Act too: "busy") until that message's answer, or AH.LATE s.

local _, ns = ...

local AH = {}
ns.AH = AH

AH.SEARCH_PER_MINUTE = 100   -- SendSearchQuery / SendSellSearchQuery: the game's documented limit
AH.WINDOW = 61               -- seconds that limit counts over, sliding: the documented minute and
                             -- a second's margin (our clock and the server's needn't agree)
AH.TIMEOUT = 10              -- seconds a request waits for its answer unless it says otherwise
AH.RECHECK = 1               -- seconds between looks at a throttle that turned ready with no event
AH.LATE = 10                 -- seconds a timed-out message of ours may still be answered (holds the line)

local EPS = 1e-6
local isOpen = false
local queue = {}       -- requests waiting, oldest first
local current          -- the request in flight
local sentAt = {}      -- GetTime() of each search request sent within the last WINDOW
local waking = false   -- a timer will look again when the search window frees
local rechecking = false   -- a timer will look at the throttle again

local frame = CreateFrame("Frame")   -- the in-flight request's own events
local sending = false  -- inside a request's send (its THROTTLED_MESSAGE_SENT is ours)
local ownOut           -- a finished request whose message's answer (RESPONSE_RECEIVED) is still to come
local lateOut          -- GetTime() until which a timed-out message of ours may still be answered
local tail = false     -- this frame's answer wasn't ours: its events reach no request

function AH.IsOpen()
    return isOpen
end

local function ready()
    local api = C_AuctionHouse
    if not (api and api.IsThrottledMessageSystemReady) then return true end
    return api.IsThrottledMessageSystemReady() == true
end

-- A request let go while in flight still holds the line (`current`) until
-- its answer or timeout; this frees it.
local function release(req)
    if current ~= req then return end
    current = nil
    for event in pairs(req.events) do frame:UnregisterEvent(event) end
end

local function finish(req, ok, reason, detail)
    if req.finished then return end
    req.finished = true
    -- its message still out: its answer is late (a timeout), or just behind its events
    if req.out and reason ~= "closed" then
        req.out = false
        if reason == "timeout" then lateOut = GetTime() + AH.LATE else ownOut = req end
    end
    release(req)
    if req.onDone then ns.SafeCall(req.onDone, ok, reason, detail) end
end

-- Whether a search may go now; when not, a timer looks again once the
-- oldest search in the window is WINDOW seconds old.
local pump
local function searchAllowed()
    local now = GetTime()
    while sentAt[1] and now - sentAt[1] >= AH.WINDOW - EPS do table.remove(sentAt, 1) end
    if #sentAt < AH.SEARCH_PER_MINUTE then return true end
    if not waking then
        waking = true
        C_Timer.After(sentAt[1] + AH.WINDOW - now, function()
            waking = false
            pump()
        end)
    end
    return false
end

-- The throttle's events are how we hear it is ready again; should one never
-- come, a timer looks again every RECHECK seconds while work waits.
local function recheckSoon()
    if rechecking then return end
    rechecking = true
    C_Timer.After(AH.RECHECK, function()
        rechecking = false
        pump()
    end)
end

-- Puts a request in flight and sends it. True when it now waits for an
-- answer; false when it ended at once (send raised, or "answered"), its onDone run.
local function launch(req)
    current = req
    for event in pairs(req.events) do frame:RegisterEvent(event) end
    C_Timer.After(req.timeout, function()
        if current == req then
            if req.finished then
                release(req)
            else
                finish(req, false, "timeout")
            end
            pump()
        end
    end)
    local result
    sending = true
    local sent = ns.SafeCall(function() result = req.send() end)
    sending = false
    if not sent then
        finish(req, false, "error")
    elseif result == "answered" then
        finish(req, true)   -- nothing went out: no answer to wait for
    else
        return true
    end
    return false
end

-- Sends the next request when nothing is in flight, the AH is open and the
-- game is ready. A send that raises fails its request and the next one goes.
-- A late message of ours still out: nothing goes until its answer or AH.LATE.
local lateTimer = false
local function held()
    if tail then return true end
    if lateOut then
        local left = lateOut - GetTime()
        if left <= EPS then lateOut = nil; return false end
        if not lateTimer then
            lateTimer = true
            C_Timer.After(left, function() lateTimer = false; pump() end)
        end
        return true
    end
    return false
end

pump = function()
    if held() then return end
    while not current and isOpen and queue[1] do
        if not ready() then return recheckSoon() end
        local req = queue[1]
        if req.search and not searchAllowed() then return end
        table.remove(queue, 1)
        if req.search then sentAt[#sentAt + 1] = GetTime() end
        if launch(req) then return end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local req = current
    local fn = req and req.events[event]
    if not fn then return end
    if req.finished then   -- let go: its answer ends the hold, nothing else
        -- as finish does: its RESPONSE_RECEIVED, just behind these events, is its own,
        -- never the next message's (that one could then time out without holding the line)
        if req.out then req.out = false; ownOut = req end
        release(req)
        return pump()
    end
    if tail then return end   -- the game's answer, or a late one: never ours
    local result, reason, detail
    local ran = ns.SafeCall(function(...) result, reason, detail = fn(...) end, ...)
    if current ~= req then return end
    if not ran then
        finish(req, false, "error")
    elseif result then
        finish(req, true)
    elseif result == false and reason ~= nil then
        finish(req, false, reason, detail)
    else
        return
    end
    pump()
end)

-- Queues a request (see the top of this file). Returns false when the AH is
-- closed: nothing is sent and onDone(false, "closed") has already run.
function AH.Request(spec)
    if type(spec) ~= "table" or type(spec.send) ~= "function" or type(spec.events) ~= "table" then
        error("ns.AH.Request needs { name =, send = function, events = { EVENT = function } }", 2)
    end
    local req = {
        name = spec.name, send = spec.send, events = spec.events, search = spec.search == true,
        timeout = tonumber(spec.timeout) or AH.TIMEOUT, onDone = spec.onDone, tag = spec.tag,
    }
    if not isOpen then
        finish(req, false, "closed")
        return false
    end
    queue[#queue + 1] = req
    -- A request that may only wait so long for its turn leaves the line then,
    -- unsent: the game's throttle can stay busy for minutes, and a full scan
    -- shouldn't sit on "asking" all that time.
    local wait = tonumber(spec.wait)
    if wait then
        C_Timer.After(wait, function()
            if req.finished or current == req then return end
            for i, queued in ipairs(queue) do
                if queued == req then
                    table.remove(queue, i)
                    return finish(req, false, "timeout")
                end
            end
        end)
    end
    pump()
    return true
end

-- Ends every request with this tag: queued ones at once, the one in flight
-- for its caller (the line stays held until its answer or timeout).
function AH.Drop(tag)
    if tag == nil then return end
    local kept, dropped = {}, {}
    for _, req in ipairs(queue) do
        if req.tag == tag then dropped[#dropped + 1] = req else kept[#kept + 1] = req end
    end
    queue = kept
    -- after the queue is filtered: work started from a dropped caller's callback is new, and stays
    ns.Fire("AHDrop", tag)   -- whoever keeps its own line (ns.Browse) ends it before anything asks again
    local inFlight = current and current.tag == tag and not current.finished and current
    if inFlight then
        inFlight.finished = true
        if inFlight.onDone then ns.SafeCall(inFlight.onDone, false, "dropped") end
    end
    for _, req in ipairs(dropped) do finish(req, false, "dropped") end
end

function AH.Busy()
    return current ~= nil
end

-- Sends now, in the caller's click, or says why not. Never queues.
function AH.Act(spec)
    if type(spec) ~= "table" or type(spec.send) ~= "function" or type(spec.events) ~= "table" then
        error("ns.AH.Act needs { name =, send = function, events = { EVENT = function } }", 2)
    end
    if not isOpen then return false, "closed" end
    if current then return false, "busy" end
    if held() then return false, lateOut and "late" or "busy" end
    if not ready() then return false, "throttled" end
    launch({   -- ended at once (raised, "answered"): onDone has run, still true
        name = spec.name, send = spec.send, events = spec.events, search = false,
        timeout = tonumber(spec.timeout) or AH.TIMEOUT, onDone = spec.onDone,
    })
    return true
end

-- The game's own words for an AUCTION_HOUSE_SHOW_ERROR code (AuctionHouseUtil.GetErrorText,
-- which lives in a window that may not be loaded), and whether the trouble is
-- the server's, not this auction's. Nil when the game doesn't say.
local ERRORS = {
    NotEnoughMoney = "ERR_NOT_ENOUGH_MONEY", HigherBid = "ERR_AUCTION_HIGHER_BID",
    BidIncrement = "ERR_AUCTION_BID_INCREMENT", BidOwn = "ERR_AUCTION_BID_OWN",
    ItemNotFound = "ERR_ITEM_NOT_FOUND", RestrictedAccountTrial = "ERR_RESTRICTED_ACCOUNT_TRIAL",
    HasRestriction = "ERR_HAS_RESTRICTION", IsBusy = "ERR_AUCTION_HOUSE_BUSY",
    Unavailable = "ERR_AUCTION_HOUSE_UNAVAILABLE", ItemHasQuote = "ERR_AUCTION_ITEM_HAS_QUOTE",
    DatabaseError = "ERR_AUCTION_DATABASE_ERROR", MinBid = "ERR_AUCTION_MIN_BID",
    NotEnoughItems = "ERR_AUCTION_ENOUGH_ITEMS", RepairItem = "ERR_AUCTION_REPAIR_ITEM",
    UsedCharges = "ERR_AUCTION_USED_CHARGES", QuestItem = "ERR_AUCTION_QUEST_ITEM",
    BoundItem = "ERR_AUCTION_BOUND_ITEM", ConjuredItem = "ERR_AUCTION_CONJURED_ITEM",
    LimitedDurationItem = "ERR_AUCTION_LIMITED_DURATION_ITEM", IsBag = "ERR_AUCTION_BAG",
    EquippedBag = "ERR_AUCTION_EQUIPPED_BAG", WrappedItem = "ERR_AUCTION_WRAPPED_ITEM",
    LootItem = "ERR_AUCTION_LOOT_ITEM", DoubleBid = "ERR_AUCTION_DOUBLE_BID",
    ItemBoundToAccountUntilEquip = "ERR_NOT_SAME_ACCOUNT",
}
local SERVER = { DatabaseError = true, IsBusy = true, Unavailable = true }

-- Game text for the end of a sentence: without its last period.
function AH.Words(text)
    if type(text) ~= "string" or text == "" then return nil end
    return (text:gsub("%.$", ""))
end

function AH.ErrorText(code)
    if issecretvalue and issecretvalue(code) then return nil end
    local all = Enum and Enum.AuctionHouseError
    for name, value in pairs(all or {}) do
        if value == code then return AH.Words(ERRORS[name] and _G[ERRORS[name]]), SERVER[name] == true end
    end
    return nil
end

function AH.Close()
    if not isOpen then return end
    local api = C_AuctionHouse
    if api and api.CloseAuctionHouse then api.CloseAuctionHouse() end
end

-- Answers from before (a close drops them: a guess, tests/ahworld.lua) count for nothing now.
local function forgetOut()
    ownOut, lateOut, tail = nil, nil, false
end

ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
    if isOpen then return pump() end
    isOpen = true
    forgetOut()
    ns.Fire("AHOpened")
    pump()
end)

-- Everything in flight or waiting fails: its answer won't come, and a scan
-- or search half done is no good to anyone.
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    local was = isOpen
    isOpen = false
    local inFlight, waiting = current, queue
    queue = {}
    if inFlight then
        finish(inFlight, false, "closed")
        release(inFlight)   -- one let go earlier still holds the line
    end
    for _, req in ipairs(waiting) do finish(req, false, "closed") end
    forgetOut()
    if was then ns.Fire("AHClosed") end
end)

-- The game's throttle: every change is a reason to look again (none carries
-- a payload; readiness is asked each time).
-- A message went out: the in-flight request's (inside its send, or the first
-- after it), else someone else's.
ns.RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", function()
    local req = current
    if req and not req.finished and (sending or not req.out) then req.out = true end
    pump()
end)

-- An answer came: the in-flight request's, the one just finished's, or not
-- ours (the game's own query, a late one): then a tail for this frame.
ns.RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", function()
    local req = current
    if req and not req.finished and req.out then
        req.out = false
    elseif ownOut then
        ownOut = nil
    else
        lateOut = nil
        if not tail then
            tail = true
            C_Timer.After(0, function() tail = false; pump() end)
        end
    end
    pump()
end)

for _, event in ipairs({ "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_BROWSE_FAILURE" }) do
    ns.RegisterEvent(event, function() pump() end)
end
