-- The fake game's Auction House, for Game/AH.lua and what builds on it (the
-- full scan, targeted searches). Never shipped: it lives in tests/ only.
-- Modeled on the game's API docs (tests/blizzard/api/AuctionHouseDocumentation.lua,
-- ItemDocumentation.lua) and DaylightUI's tests/mailworld.lua world pattern.
--
--   local AHW = require("ahworld")
--   local DUI, A = AHW.Load({ auctions = {...}, commodities = {...} }, { login = ... })
--   AHW.Open(); C_AuctionHouse.ReplicateItems(); AHW.Step() ...
--
-- AHW.Load(spec, opts) loads Daylight UI with the Auction House module
-- (stub.Load's opts plus auctionhouse = true) and returns the core and the
-- module's namespace; the world is installed first in `before`, so a test's own
-- `before` can still replace any function here. spec:
--   auctions = { { itemID, count, buyout, minBid?, bid?, link?, owner?, name?,
--                  quality?, level?, suffix?, cached? }, ... }
--       buyout is the whole stack's (0 = bid only), like GetReplicateItemInfo.
--       cached = false: the item isn't known yet (hasAllInfo false, no link,
--       GetItemKeyInfo nil) until AHW.Cache(itemID).
--       Browse queries also read: classID, subClassID, inventoryType (itemClassFilters),
--       usable (false: not UsableOnly), timeLeft (a band, 0-3, default 2).
--       C_Item.GetItemInfo reads: name, quality, itemLevel (else level), icon,
--       vendorSell, bindType (nothing while the item isn't cached).
--   commodities = { [itemID] = true }   searched as commodities, the rest as items
--   throttled = true                    IsThrottledMessageSystemReady() false until AHW.Throttle(false)
--   neverCache = { [itemID] = true }    C_Item.RequestLoadItemDataByID never answers
--   dropAsks = { [itemID] = n }         the first n RequestLoadItemDataByID of it are let fall, unanswered
--                                       (guess: Auctionator asks every 0.4 s for items still loading)
--   missing = { [itemID] = true }       C_Item.DoesItemExistByID false (a deleted item)
--   staleRows = { [itemID] = true }     its replicate rows keep hasAllInfo false and no link after the
--                                       item loads (guess: the list is a snapshot taken at the ask)
--   page = 50                           search rows per page
--   moreEvents = { "added", "updated" } what a RequestMore*SearchResults answer fires, in
--                                       order: *_SEARCH_RESULTS_ADDED, *_UPDATED (guess: unknown
--                                       which the client sends; the probe will tell)
--   quoteBump = 0                       copper added to every commodity quote (the price moved)
--   silentPurchase = false              a buy sends no COMMODITY_PURCHASED (seen in play: won, list not counted down)
--   quoteFails = true                   every commodity quote answers COMMODITY_PRICE_UNAVAILABLE
--   quoteSeconds = 300                  how long a commodity quote lasts (GetQuoteDurationRemaining)
--   soldOut = { [auctionID] = true }    a PlaceBid on it answers AUCTION_HOUSE_SHOW_ERROR
--   step = 0.25                         seconds each server answer takes
--   itemDelay = 0.25                    seconds each item data load takes (loads run side by side)
--   itemSpacing = nil                   seconds: a cold cache, loads arrive one at a time at least
--                                       this far apart (a trickle; guess at how a cold client feels)
--   favorites = { itemID, ... }         the player's favorites: HasFavorites() true, and the
--                                       game's own frame searches them as it shows (below)
--   responseFirst = true                an answer fires RESPONSE_RECEIVED and SYSTEM_READY
--                                       BEFORE its own events (the other order of the guess below)
--   readyEarly = true                   the throttle is ready again BEFORE an answer's own events
--                                       (RESPONSE_RECEIVED still after them; a third reading of the guess)
--   bags = { [bag] = { [slot] = { itemID, stackCount, name?, isBound?, link?, quality?, locked?, noValue? } } }
--                                       the player's bags: installs C_Container and ItemLocation
--                                       (posting takes from them, BAG_UPDATE_DELAYED after)
--   items = { [itemID] = { name, quality?, level?, classID?, subClassID?, vendorSell?, bindType? } }
--                                       items the game knows that no auction holds (C_Item.GetItemInfo)
--   postWarning = { [itemID] = true }   PostCommodity / PostItem answer needsConfirmation (the game's
--                                       "are you sure" price warning): nothing is posted until
--                                       ConfirmPostCommodity / ConfirmPostItem with the same values
--   postFails = { [itemID] = true }     a post of it answers AUCTION_HOUSE_SHOW_ERROR (a number: that error)
--   postRefused = { [itemID] = true }   PostCommodity / PostItem fire AUCTION_HOUSE_POST_ERROR inside the
--                                       call and return true, like a warning (the game's popup is OK only)
--   cancelFails = number                every CancelAuction answers AUCTION_HOUSE_SHOW_ERROR(number)
--   cancelCost = 0                      GetCancelCost, copper
--   saleCancels = false                 a sold-out auction also fires AUCTION_CANCELED(id) while the AH is open
--   cancelEvent = nil                   what a cancel's AUCTION_CANCELED carries: nil the auction's ID (the
--                                       docs), a number that number, false no event at all (a GUESS at Forever,
--                                       where nothing came back for a player; the game's own
--                                       window ignores the payload and refreshes)
--   auctions' `account = true`          one of the account's (search rows say containsAccountItem)
--   auctions' `timeLeftSeconds`         a commodity row's time left (nil: the game doesn't say)
--   auctions' `mine = true`             the player's own (search rows say containsOwnerItem, owners
--                                       "player"; QueryOwnedAuctions lists them); `sold = true` with it:
--                                       sold, still listed (status Sold) like the game's
--   emptyOnce = { [itemID] = true }     the first search for it answers with no rows and HasFull*
--                                       false, like the glitch Auctionator works around (its
--                                       SearchScan.lua: "sometimes no results are returned when there
--                                       are actually some"); the next search answers normally
--   replicateCooldown = nil             seconds: a ReplicateItems within this long of the last one
--                                       the server answered is ignored, no REPLICATE_ITEM_LIST_UPDATE
--                                       (guess: the client documents no cooldown; the throttle
--                                       events still flow, logged "Ignored")
--   replicateLate = nil                 seconds after REPLICATE_ITEM_LIST_UPDATE until the whole list shows;
--                                       until then GetNumReplicateItems says replicateEarly (default 0)
--   replicateBlank = nil                seconds after the event during which GetReplicateItemInfo answers
--                                       nothing (guess for both: TSM waits and re-reads, the docs don't say)
--
-- What the client does, and what is a guess (not seen in game yet):
--   * Everything the server answers is asynchronous: ReplicateItems,
--     SendSearchQuery, SendSellSearchQuery and RequestMore*SearchResults queue
--     their answer; AHW.Step() delivers the next one. Item data loads the same way.
--   * CloseAuctionHouse (the docs' function) closes it like AHW.Close(), logged.
--   * The AH functions work only while it is open: a send while closed does
--     nothing (logged "Refused"). Closing drops the answers still on the way.
--   * The throttle (guess, from how the client's events read): a send goes out
--     only while IsThrottledMessageSystemReady(); it fires
--     AUCTION_HOUSE_THROTTLED_MESSAGE_SENT and the system is busy until its
--     answer; then RESPONSE_RECEIVED and SYSTEM_READY. A send while not ready
--     is dropped: AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED, logged "Dropped",
--     never answered (the client may queue some instead: MESSAGE_QUEUED; the
--     fake is the stricter of the two).
--   * SendSearchQuery / SendSellSearchQuery: "restricted to 100 calls per
--     minute" (the docs). The 101st within 60 s is dropped the same way (guess
--     at what the server does).
--   * Order of one answer (guess): the answer's own events, then
--     RESPONSE_RECEIVED, then SYSTEM_READY (spec.responseFirst: the other way round).
--   * The game's AuctionHouseFrame searches on its own as it shows: OnShow calls
--     QueryAll(AllFavorites) when C_AuctionHouse.HasFavorites() (Blizzard_AuctionHouseFrame.lua
--     forever, lines 396-398), which sends C_AuctionHouse.SearchForFavorites(sorts) (line 772);
--     its answer is the one browse list (AUCTION_HOUSE_BROWSE_RESULTS_UPDATED, the browse
--     results frame's event: Blizzard_AuctionHouseBrowseResultsFrame.lua lines 10, 74). The
--     fake sends it in AHW.Open between the interaction manager's show (where the game shows
--     the frame) and AUCTION_HOUSE_SHOW (that order is a guess). The frame is under the window
--     kit's veil, still shown, so this runs on every open.
--   * A search answers COMMODITY_SEARCH_RESULTS_UPDATED(itemID) or
--     ITEM_SEARCH_RESULTS_UPDATED(itemKey copy); a RequestMore answer fires
--     *_ADDED then *_UPDATED by default (guess; spec.moreEvents picks). Commodity rows merge auctions of one
--     unit price, cheapest first; item rows are one per auction, cheapest
--     buyout first, bid-only last. Rows are taken when the answer arrives;
--     `page` of them at a time, HasFull* false until RequestMore brought the rest.
--   * An item search with suffix 0 returns every suffix of the item; with a
--     suffix, only that one (guess). Results are kept per itemID.
--   * Forever's suffixed gear (an auction with `words`, "of Defense"): the AH's
--     number (itemSuffix 14303, one per suffix name) is NOT in the link, whose
--     suffix field is empty, whose bonus ID (`a.bonus`, else the AH number less
--     1580) names the suffix and whose [text] holds the whole name; SendSearchQuery
--     finds it only by its exact key (level and suffix), a cleared key finds
--     nothing; SendSellSearchQuery with a cleared key finds every suffix (the
--     game's sell frame, ConvertItemSellItemKey). Numbers and links seen in play.
--     Sent with the level or suffix still set, it answers only
--     AUCTION_HOUSE_NEW_RESULTS_RECEIVED (every search fires that first): no
--     results event, so a search waiting for one times out (seen in play).
--     MakeItemKey(itemID) fills in the item's level (known `level`, else an auction's).
--   * GetItemKeyInfo on an item not cached answers nil and does NOT start a
--     load (the client probably does; asking with RequestLoadItemDataByID
--     works either way). AHW.Cache(itemID) fires ITEM_DATA_LOAD_RESULT,
--     GET_ITEM_INFO_RECEIVED (both itemID, true) and ITEM_KEY_ITEM_INFO_RECEIVED(itemID).
--   * No name, texture or link for an item not cached yet (guess: the client
--     may already know the link; our code falls back to the itemID either way).
--   * SendBrowseQuery(query) (counted as a search, like the docs' two): one row per item
--     key (itemID, level, suffix) among the auctions that match the query: searchString
--     (case-insensitive substring of the name), the ExactMatch filter finds nothing
--     and neither does a query with filters but no quality among them (GUESS at which
--     of the two it was: `filters = { ExactMatch }` came back empty in play, and the
--     game's own UI never sends ExactMatch and always sends the qualities),
--     minLevel/maxLevel (the auction's level, default 1), the quality filters (any of
--     the ones given), itemClassFilters (any of them; subClassID and inventoryType
--     only when given), the UsableOnly filter (usable ~= false). Rows come cheapest
--     first (the sorts are logged and ignored, like the search). minPrice (GUESS: the
--     real meaning for gear): a commodity's cheapest unit, gear's cheapest buyout (a
--     bid-only one's minBid); totalQuantity: the stacks' counts summed. `page` rows
--     arrive per answer; HasFullBrowseResults false until RequestMoreBrowseResults
--     brought the rest, which answers *_ADDED (the added rows) and/or *_UPDATED per
--     spec.moreEvents (a guess, as for the search). There is no GetNumBrowseResults
--     in the game API (the docs have none): GetBrowseResults() is a fresh copy of the
--     shown rows. RequestMoreBrowseResults returns nothing (the docs name no result).
--     A new query replaces the list.
--   * Search result rows are fresh tables on each Get*SearchResultInfo call.
--   * SendSearchQuery's sorts are logged (AHW.Log) but don't change the order:
--     the answer is cheapest first. Enum.AuctionHouseSortOrder is the
--     docs' (Price = 0 ...). spec.dearFirst answers gear dearest first: in game
--     a sell search for bags came back with the 40g ones ahead of the 25s ones,
--     sorts and all, so the order an item search arrives in can't be trusted.
--
--   * Purchases (from the game's Blizzard_AuctionHouseUI source and the API docs).
--     StartCommoditiesPurchase(itemID, quantity[, unitPrice]) (the game's own dialog
--     passes the third; the docs list two), ConfirmCommoditiesPurchase(itemID, quantity)
--     and PlaceBid(auctionID, amount) are hardware-only: outside a click or key they are
--     refused with ADDON_ACTION_BLOCKED (stub.HardwareOnly) and nothing is sent. The
--     docs mark Start and PlaceBid HasRestrictions; Confirm is a GUESS (hardware-only
--     too). All three are throttled messages. Start answers
--     COMMODITY_PRICE_UPDATED(unitPrice, totalPrice) with the cheapest `quantity` units'
--     total (+ spec.quoteBump); the unit price is total / quantity floored (the game's
--     source: its buy frame passes totalPrice / totalQuantity), or
--     COMMODITY_PRICE_UNAVAILABLE when the shelf
--     holds fewer or spec.quoteFails. Confirm needs a matching started quote; it
--     takes the units again and fails (COMMODITY_PURCHASE_FAILED) when they are gone or
--     now cost more than the quote, else removes them (a stack partly: its count and
--     buyout shrink) and fires COMMODITY_PURCHASE_SUCCEEDED then COMMODITY_PURCHASED.
--     A quote lasts spec.quoteSeconds (300): GetQuoteDurationRemaining counts it down (0
--     without one) and a Confirm after it ends answers COMMODITY_PURCHASE_FAILED.
--     CancelCommoditiesPurchase drops the quote. PlaceBid with at least the buyout
--     buys the auction (it goes; AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)); a lower
--     bid at least the minBid stands (auction.bid; BID_ADDED(auctionID): GUESS, the
--     game's bid popup listens for no event); a gone auction, a lower bid or
--     spec.soldOut answers AUCTION_HOUSE_SHOW_ERROR(1).
--
--   * Selling (the game's Blizzard_AuctionHouseUI, forever branch: CommoditiesSellFrame.lua
--     108-126, ItemSellFrame.lua 480-498, AuctionsFrame.lua, AuctionHouseFrame.lua 77-129; the docs).
--     GetItemCommodityStatus(loc): 0 unknown (not cached), 2 commodity (spec.commodities), 1 item.
--     PostCommodity(loc, duration 1-3, qty, unitPrice) and PostItem(loc, duration, qty, bid, buyout)
--     are hardware-only and throttled; they return needsConfirmation (spec.postWarning: true, and
--     nothing is sent until ConfirmPost* with the same values). A commodity post is one auction of
--     qty at unitPrice; an item post of qty makes qty auctions of 1 at `buyout` each (the game's
--     multisell: AUCTION_MULTISELL_START(qty) first and AUCTION_MULTISELL_UPDATE(n, qty) after each
--     when qty > 1; one message for all of them: a GUESS). Each new auction fires
--     AUCTION_HOUSE_AUCTION_CREATED(auctionID). The items leave the bag slot when the answer comes
--     (BAG_UPDATE_DELAYED). A bad slot, too few in it, a price under 1c or spec.postFails answer
--     AUCTION_HOUSE_SHOW_ERROR(1) (AUCTION_MULTISELL_FAILURE too for a multisell). A gear or
--     recipe post (classID 2, 4, 9) whose buyout or bid isn't whole silver answers
--     AUCTION_HOUSE_SHOW_ERROR(DatabaseError), "Internal auction error" (Forever, in the game's
--     own window too: seen in game); any other single item (a Silver Rod: a player posted one
--     at 4s 50c in the game's window) and a commodity take copper. Deposits:
--     vendorSell (or 1) x qty x duration, at least 1 (a GUESS at the formula: only its existence matters).
--     QueryOwnedAuctions(sorts) answers OWNED_AUCTIONS_UPDATED; GetOwnedAuctionInfo(i) is the docs'
--     OwnedAuctionInfo (status 0 active, 1 sold). CancelAuction(id) (hardware-only, throttled) on an
--     active auction of the player's that the owned list has loaded removes it, mails the items back
--     (AHW.Mailed(); the modern AH returns them by mail) and fires AUCTION_CANCELED(id); anything else
--     answers AUCTION_HOUSE_SHOW_ERROR. AHW.Sell(auctionID, buyer, count?) sells one of the player's
--     (count: part of a commodity auction, one letter for that part, the rest still up).
--
-- Gold and mail (a goldworld and tests/mailworld.lua, loaded beside this world): while goldworld is loaded the AH moves the player's money the way the
-- client does, the event first and the gold AHW.STEP later (PLAYER_MONEY): a commodity confirm and a
-- buyout take the price (a buyout also fires ITEM_PURCHASED(itemID): a GUESS, mailworld's), a lower
-- bid takes the bid, a post takes its deposit after AUCTION_HOUSE_AUCTION_CREATED, a cancel takes
-- spec.cancelCost. While mailworld is loaded a cancel, a sale (AHW.Sell(id, buyer)) and an expiry
-- (AHW.Expire(id)) each leave a letter in its world (MW.Deliver puts it in the inbox): "Auction
-- canceled/successful/expired: <name>" (the client's AUCTION_*_MAIL_SUBJECT, with " (n)" for a stack),
-- the sale with a seller invoice (bid = buyout, the cut 5%, the deposit the post paid) and its gold
-- bid - cut + deposit (a GUESS, mailworld's).
--
-- Time: one clock (GetTime, stub.Advance). Everything pending carries the
-- time it is due: a server answer `step` (0.25 s) after its send, an item
-- load `itemDelay` (0.25 s) after its request, each on its own (forty item
-- loads arrive together, not one after another, and never hold up a search
-- answer), and timers. The world owns C_Timer.After, NewTimer and NewTicker
-- while it is installed (stub.Reset puts the stub's back); delays are kept,
-- 0 = the next frame. stub.RunTimers() / stub.RunTickers() don't run them.
--   AHW.Frame()      one frame: the timers due now, not those added during it.
--                    The clock does NOT move per frame (frames take no time here).
--   AHW.Step()       runs everything on the clock up to and including the next
--                    answer, in time order (a timeout due before a slow answer
--                    fires first), then one frame. False when nothing is coming.
--   AHW.Advance(s)   moves the clock s seconds, running timers and answers as
--                    their times come, then frames until none is due.
--   AHW.Settle()     frames and Steps until no timer is due and no answer is coming
--                    (timers further in the future than the last answer stay).
--   A ticker with interval 0 runs every frame, so Settle never goes quiet:
--   it errors after SETTLE_MAX rounds.
local stub = require("stub")

-- The stub's C_Item before any world swapped it: each load starts from it.
local BASE_C_ITEM = _G.C_Item

local AHW = {}

AHW.STEP = 0.25        -- seconds a server answer takes
AHW.ITEM_DELAY = 0.25  -- seconds an item data load takes
AHW.PAGE = 50          -- search rows per page
AHW.SEARCH_LIMIT = 100 -- the docs' calls per minute for SendSearchQuery / SendSellSearchQuery
AHW.AUCTIONEER = 21    -- Enum.PlayerInteractionType.Auctioneer
local EPS = 1e-6
local SETTLE_MAX = 20000

local function S() return AHW.state end
local function fire(...) stub.FireEvent(...) end

-- A deep copy: the world hands out and keeps its own tables, never the test's.
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

-- ---------------------------------------------------------------------
-- What our code called
-- ---------------------------------------------------------------------

local function record(name, ...) table.insert(S().calls, { name = name, args = { ... } }) end

-- How many times `name` was called (or "Refused" / "Dropped" happened).
function AHW.Calls(name)
    local n = 0
    for _, c in ipairs(S().calls) do if c.name == name then n = n + 1 end end
    return n
end

-- The arguments of each call to `name`, in order.
function AHW.Log(name)
    local out = {}
    for _, c in ipairs(S().calls) do if c.name == name then out[#out + 1] = c.args end end
    return out
end

-- ---------------------------------------------------------------------
-- Timers and the server's answers
-- ---------------------------------------------------------------------

local function nextSeq()
    local st = S()
    st.seq = st.seq + 1
    return st.seq
end

local function after(delay, fn)
    table.insert(S().timers, { at = GetTime() + math.max(0, tonumber(delay) or 0), fn = fn, seq = nextSeq() })
end

-- C_Timer.NewTimer / NewTicker on the same clock: handles with Cancel().
local function handle()
    local h = { canceled = false }
    function h:Cancel() self.canceled = true end
    function h:IsCanceled() return self.canceled end
    return h
end
local function newTimer(delay, fn)
    local h = handle()
    after(delay, function() if not h.canceled then fn(h) end end)
    return h
end
local function newTicker(interval, fn, iterations)
    local h, n = handle(), 0
    local function tick()
        if h.canceled then return end
        n = n + 1
        fn(h)
        if h.canceled or (iterations and n >= iterations) then return end
        after(interval, tick)
    end
    after(interval, tick)
    return h
end

local function anyDue()
    local now = GetTime() + EPS
    for _, t in ipairs(S().timers) do if t.at <= now then return true end end
    return false
end

-- One frame: the timers due now, oldest first; ones added meanwhile wait.
function AHW.Frame()
    local st = S()
    local limit, now = st.seq, GetTime() + EPS
    local due, keep = {}, {}
    for _, t in ipairs(st.timers) do
        if t.seq <= limit and t.at <= now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    st.timers = keep
    table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    for _, t in ipairs(due) do t.fn() end
    st.frames = st.frames + 1
    return #due
end

local function framesUntilQuiet()
    for _ = 1, SETTLE_MAX do
        if not anyDue() then return end
        AHW.Frame()
    end
    error("ahworld: timers never settled", 3)
end

-- Something the server or the item cache answers `delay` seconds from now,
-- each on its own time; ah = true ones are dropped when the AH closes.
local function later(delay, fn, ah)
    table.insert(S().queue, { at = GetTime() + delay, fn = fn, ah = ah, seq = nextSeq() })
end

-- Goldworld and mailworld, when this load has them (their state is nil otherwise).
local function goldw()
    local g = package.loaded.goldworld
    return g and g.state and g or nil
end
local function mailw()
    local m = package.loaded.mailworld
    return m and m.state and m or nil
end
-- Money that moves a step after what caused it (nothing without goldworld).
local function pay(delta)
    local g = goldw()
    if g and delta ~= 0 then g.Change(delta) end
end
-- Goldworld's own money events ride this clock.
-- The Auction House's errors (AuctionHouseEnumsDocumentation.lua) and the game's words for them.
AHW.DATABASE_ERROR = 10
function AHW.GameWords()
    _G.Enum.AuctionHouseError = { NotEnoughMoney = 0, ItemNotFound = 4, IsBusy = 7, Unavailable = 8,
        DatabaseError = AHW.DATABASE_ERROR }
    _G.ERR_NOT_ENOUGH_MONEY = "You don't have enough money."
    _G.ERR_AUCTION_HOUSE_BUSY = "The Auction House is busy."
    _G.ERR_AUCTION_DATABASE_ERROR = "Internal auction error"
    _G.AUCTION_POSTING_ERROR_TEXT = "Your auction could not be posted."
end

function AHW.Later(delay, fn) later(delay, fn, false) end

-- The earliest entry of a timer or answer list: index, entry.
local function earliest(list)
    local bi, best
    for i, e in ipairs(list) do
        if not best or e.at < best.at or (e.at == best.at and e.seq < best.seq) then bi, best = i, e end
    end
    return bi, best
end

local function moveTo(t)
    local now = GetTime()
    if t > now then stub.Advance(t - now) end
end

-- Runs the next thing on the clock due by `target`: the earliest timer
-- (as a frame) or answer, timers first on a tie. "timer", "answer" or nil.
local function runNext(target)
    local _, t = earliest(S().timers)
    local qi, q = earliest(S().queue)
    if t and t.at <= target + EPS and (not q or t.at <= q.at + EPS) then
        moveTo(t.at)
        AHW.Frame()
        return "timer"
    end
    if q and q.at <= target + EPS then
        moveTo(q.at)
        table.remove(S().queue, qi)
        q.fn()
        return "answer"
    end
    return nil
end

function AHW.Step()
    for _ = 1, SETTLE_MAX do
        if #S().queue == 0 then return false end
        if runNext(math.huge) == "answer" then
            AHW.Frame()
            return true
        end
    end
    error("ahworld: a step never reached its answer", 2)
end

function AHW.Settle()
    for _ = 1, SETTLE_MAX do
        if anyDue() then AHW.Frame()
        elseif not AHW.Step() then return end
    end
    error("ahworld: never settled", 2)
end

function AHW.Advance(seconds)
    local target = GetTime() + seconds
    for _ = 1, SETTLE_MAX do
        if not runNext(target) then break end
    end
    moveTo(target)
    framesUntilQuiet()
end

-- Server answers still on the way.
function AHW.Waiting() return #S().queue end

-- ---------------------------------------------------------------------
-- The window and the throttle
-- ---------------------------------------------------------------------

local function ready() return not S().throttled and not S().busy end

-- The server's extra browse info for an item arrives (a recipe's skill).
function AHW.SendExtra(itemID)
    for _, a in ipairs(S().auctions) do
        if a.itemID == itemID then a.skillLate = nil end
    end
    fire("EXTRA_BROWSE_INFO_RECEIVED", itemID)
end

function AHW.Open()
    if S().open then return end
    S().open = true
    fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", AHW.AUCTIONEER)
    -- the game's AuctionHouseFrame:OnShow (lines 396-398): its favorites, searched
    if C_AuctionHouse.HasFavorites() then C_AuctionHouse.SearchForFavorites({}) end
    fire("AUCTION_HOUSE_SHOW")
end

function AHW.Close()
    if not S().open then return end
    S().open = false
    local keep = {}
    for _, q in ipairs(S().queue) do if not q.ah then keep[#keep + 1] = q end end
    S().queue = keep
    S().busy = false
    S().purchase = nil
    fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", AHW.AUCTIONEER)
    fire("AUCTION_HOUSE_CLOSED")
end

function AHW.IsOpen() return S().open == true end

-- on: the game holds every throttled message; off: ready again
-- (AUCTION_HOUSE_THROTTLED_SYSTEM_READY when nothing else is out).
function AHW.Throttle(on)
    S().throttled = on == true
    if not on and ready() then fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end
end

local function isSearch(name)
    return name == "SendSearchQuery" or name == "SendSellSearchQuery" or name == "SendBrowseQuery"
end

local function overLimit(name)
    if not isSearch(name) then return false end
    local now, recent = GetTime(), {}
    for _, t in ipairs(S().searches) do if now - t < 60 - EPS then recent[#recent + 1] = t end end
    S().searches = recent
    return #recent >= AHW.SEARCH_LIMIT
end

-- A throttled message to the server; `answer` runs when it comes back.
local function send(name, answer)
    if not S().open then record("Refused", name); return false end
    if not ready() or overLimit(name) then
        record("Dropped", name)
        fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
        return false
    end
    if isSearch(name) then table.insert(S().searches, GetTime()) end
    S().busy = true
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    later(S().step, function()
        if S().responseFirst then
            S().busy = false
            fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
            if ready() then fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end
            return answer()
        end
        if S().readyEarly then   -- a send from inside the answer's events is the next message out
            S().busy = false
            answer()
            fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
            return
        end
        answer()
        S().busy = false
        fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
        if ready() then fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end
    end, true)
    return true
end

-- ---------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------

local function nameOf(id)
    for _, a in ipairs(S().auctions) do if a.itemID == id and a.name then return a.name end end
    local known = S().known[id]
    if known and known.name then return known.name end
    return "Item " .. tostring(id)
end

local function cached(id) return id ~= nil and not S().uncached[id] end

-- The item's level as MakeItemKey fills it in: the client puts the item's own
-- level in a key made from the itemID alone (seen in play: MakeItemKey(2901),
-- a Mining Pick, gave itemLevel 4). 0 when the spec doesn't say.
local function levelOf(id)
    local known = S().known[id]
    if known and known.level then return known.level end
    for _, a in ipairs(S().auctions) do if a.itemID == id and a.level then return a.level end end
    return 0
end

local function linkOf(a)
    if not cached(a.itemID) then return nil end
    if a.link then return a.link end
    if a.words then
        -- A real Forever link: the 13th field counts the bonus IDs after it, and
        -- the bonus is the suffix, a number apart from the AH's (seen in play:
        -- "of the Bandit" is bonus 12751, AH 14330).
        local bonus = a.bonus or (a.suffix - 1580)
        return "|cnIQ2:|Hitem:" .. a.itemID .. "::::::::19:1491:::1:" .. bonus .. "::::::|h[" .. nameOf(a.itemID) .. " " .. a.words .. "]|h|r"
    end
    local suffix = a.suffix and tostring(a.suffix) or ""
    return "|cffffffff|Hitem:" .. a.itemID .. "::::::" .. suffix .. ":::60::::::::|h[" .. nameOf(a.itemID) .. "]|h|r"
end

-- The suffix a link carries (its 7th field after "item:"), 0 for none.
local function suffixOf(a)
    if a.suffix then return a.suffix end
    local link = a.link
    if not link then return 0 end
    local body = link:match("item:([^|]*)")
    if not body then return 0 end
    local i = 0
    for field in (body .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i == 7 then return tonumber(field) or 0 end
    end
    return 0
end

-- The client learns about an item: its data events, in this order (guess).
function AHW.Cache(itemID)
    S().uncached[itemID] = nil
    S().loading[itemID] = nil
    fire("ITEM_DATA_LOAD_RESULT", itemID, true)
    fire("GET_ITEM_INFO_RECEIVED", itemID, true)
    fire("ITEM_KEY_ITEM_INFO_RECEIVED", itemID)
end

-- The live list of auctions: a test may add or remove some between requests.
function AHW.Auctions() return S().auctions end

-- ---------------------------------------------------------------------
-- Search results
-- ---------------------------------------------------------------------

local function checkKey(fn, key)
    if type(key) ~= "table" or type(key.itemID) ~= "number" then
        error(fn .. ": bad argument #1 (an item key table from C_AuctionHouse.MakeItemKey)", 3)
    end
end

local function copyKey(k)
    return { itemID = k.itemID, itemLevel = k.itemLevel or 0, itemSuffix = k.itemSuffix or 0, battlePetSpeciesID = k.battlePetSpeciesID or 0 }
end

local function commodityRows(id)
    local byPrice, rows = {}, {}
    for _, a in ipairs(S().auctions) do
        if a.itemID == id and (a.count or 0) > 0 and (a.buyout or 0) > 0 and not a.sold then
            local unit = math.floor(a.buyout / a.count)
            local row = byPrice[unit]
            if not row then
                row = { itemID = id, quantity = 0, unitPrice = unit, auctionID = a.auctionID, owners = {},
                    totalNumberOfOwners = 0, timeLeftSeconds = a.timeLeftSeconds, numOwnerItems = 0, containsOwnerItem = false,
                    containsAccountItem = false }
                byPrice[unit] = row
                rows[#rows + 1] = row
            end
            row.quantity = row.quantity + a.count
            table.insert(row.owners, a.mine and "player" or (a.owner or "Seller"))
            row.totalNumberOfOwners = #row.owners
            if a.account then row.containsAccountItem = true end
            if a.mine then
                row.numOwnerItems = row.numOwnerItems + a.count
                row.containsOwnerItem = true
            end
        end
    end
    table.sort(rows, function(x, y) return x.unitPrice < y.unitPrice end)
    return rows
end

local function itemRows(key, exact)
    local rows = {}
    for _, a in ipairs(S().auctions) do
        if a.itemID == key.itemID and (a.count or 0) > 0 and (key.itemSuffix == 0 or suffixOf(a) == key.itemSuffix)
            and not a.sold and not (exact and a.words and key.itemSuffix == 0) then
            -- the price of ONE: a row of an item that isn't a commodity is `quantity`
            -- like auctions of one (the game's sell frame reads it as "per item";
            -- TSM's SubRow and Auctionator read it so; a Linen Bag row of 694 at 3s, in play)
            local buyout = (a.buyout or 0) > 0 and math.floor(a.buyout / a.count) or nil
            rows[#rows + 1] = {
                itemKey = { itemID = a.itemID, itemLevel = a.level or 0, itemSuffix = suffixOf(a), battlePetSpeciesID = 0 },
                owners = { a.mine and "player" or (a.owner or "Seller") }, totalNumberOfOwners = 1, timeLeft = a.timeLeft or 2,
                auctionID = a.auctionID, quantity = a.count, itemLink = linkOf(a), containsOwnerItem = a.mine == true,
                containsAccountItem = a.account == true, containsSocketedItem = false, bidder = nil,
                minBid = a.minBid or (buyout == nil and 1 or nil), bidAmount = a.bid, buyoutAmount = buyout,
                timeLeftSeconds = nil,
            }
        end
    end
    table.sort(rows, function(x, y)
        if (x.buyoutAmount ~= nil) ~= (y.buyoutAmount ~= nil) then return x.buyoutAmount ~= nil end
        if x.buyoutAmount and x.buyoutAmount ~= y.buyoutAmount then
            if S().dearFirst then return x.buyoutAmount > y.buyoutAmount end
            return x.buyoutAmount < y.buyoutAmount
        end
        return x.auctionID < y.auctionID
    end)
    return rows
end

local function shownRows(r) return math.min(r.shown, #r.rows) end

-- Whether the item stacks: an auction's `stack` (GetItemInfo's itemStackCount) over 1.
local function stacks(id)
    for _, a in ipairs(S().auctions) do
        if a.itemID == id and (a.stack or 1) > 1 then return true end
    end
    return false
end

local function search(name, key)
    local id = key.itemID
    local q = copyKey(key)
    return send(name, function()
        -- Every search's answer starts with AUCTION_HOUSE_NEW_RESULTS_RECEIVED (in play,
        -- in play: before the results' own events, in the same frame). A sell search
        -- names the key the server used: level and suffix cleared. Sent with them NOT
        -- cleared (the docs: "ItemKey should have its iLVL and suffix cleared before
        -- calling"), that is all that comes: no ITEM_SEARCH_RESULTS_* (seen six times in
        -- play: a Mining Pick sent at itemLevel 4), so nothing can be read.
        local sell = name == "SendSellSearchQuery"
        local answered = copyKey(q)
        if sell then answered.itemLevel, answered.itemSuffix = 0, 0 end
        fire("AUCTION_HOUSE_NEW_RESULTS_RECEIVED", answered)
        if sell and (q.itemLevel ~= 0 or q.itemSuffix ~= 0) then return end
        -- A sell search for something that stacks (ammo, thrown weapons) never brings
        -- results either (seen in play): the game's sell frame sends one only for gear.
        if sell and stacks(id) then return end
        local glitch = S().emptyOnce and S().emptyOnce[id]
        if glitch then S().emptyOnce[id] = nil end
        local exact = name == "SendSearchQuery"
        if S().commodities[id] then
            S().commodity[id] = { rows = glitch and {} or commodityRows(id), shown = S().page, glitch = glitch }
            fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
        else
            S().items[id] = { rows = glitch and {} or itemRows(q, exact), shown = S().page, glitch = glitch,
                key = copyKey(q), exact = exact }
            fire("ITEM_SEARCH_RESULTS_UPDATED", copyKey(q), nil)
        end
    end)
end

-- ---------------------------------------------------------------------
-- Browse results
-- ---------------------------------------------------------------------

local FILTER = {
    UncollectedOnly = 1, UsableOnly = 2, CurrentExpansionOnly = 3, UpgradesOnly = 4, ExactMatch = 5,
    PoorQuality = 6, CommonQuality = 7, UncommonQuality = 8, RareQuality = 9, EpicQuality = 10,
    LegendaryQuality = 11, ArtifactQuality = 12, LegendaryCraftedItemOnly = 13,
}
AHW.FILTER = FILTER
local QUALITY_FILTER = { [6] = 0, [7] = 1, [8] = 2, [9] = 3, [10] = 4, [11] = 5, [12] = 6 }   -- filter -> item quality

local function matchesClass(a, f)
    return a.classID == f.classID
        and (f.subClassID == nil or a.subClassID == f.subClassID)
        and (f.inventoryType == nil or a.inventoryType == f.inventoryType)
end

local function matchesQuery(a, q)
    local name = nameOf(a.itemID):lower()
    local text = (q.searchString or ""):lower()
    local set, qualities, anyQuality = {}, {}, false
    for _, f in ipairs(q.filters or {}) do
        set[f] = true
        if QUALITY_FILTER[f] then qualities[QUALITY_FILTER[f]] = true; anyQuality = true end
    end
    if set[FILTER.ExactMatch] or (q.filters and #q.filters > 0 and not anyQuality) then return false end
    if text ~= "" and not name:find(text, 1, true) then return false end
    local level = a.level or 1
    if q.minLevel and level < q.minLevel then return false end
    if q.maxLevel and level > q.maxLevel then return false end
    if anyQuality and not qualities[a.quality or 1] then return false end
    if set[FILTER.UsableOnly] and a.usable == false then return false end
    if q.itemClassFilters and #q.itemClassFilters > 0 then
        local any = false
        for _, f in ipairs(q.itemClassFilters) do
            if matchesClass(a, f) then any = true; break end
        end
        if not any then return false end
    end
    return true
end

-- One row per item key among the matching auctions, cheapest first.
local function browseRows(q)
    local byKey, rows = {}, {}
    for _, a in ipairs(S().auctions) do
        local commodity = S().commodities[a.itemID] == true
        local buyout = (a.buyout or 0) > 0 and a.buyout or nil
        local price
        if (a.count or 0) > 0 and not a.sold and matchesQuery(a, q) then
            if commodity then
                price = buyout and math.floor(buyout / a.count) or nil
            else
                price = buyout or a.minBid or 1
            end
        end
        if price then
            local level, suffix = commodity and 0 or (a.level or 0), commodity and 0 or suffixOf(a)
            local id = a.itemID .. ":" .. level .. ":" .. suffix
            local row = byKey[id]
            if not row then
                row = {
                    itemKey = { itemID = a.itemID, itemLevel = level, itemSuffix = suffix, battlePetSpeciesID = 0 },
                    totalQuantity = 0, minPrice = price, containsOwnerItem = false,
                }
                byKey[id] = row
                rows[#rows + 1] = row
            end
            row.totalQuantity = row.totalQuantity + a.count
            if price < row.minPrice then row.minPrice = price end
        end
    end
    table.sort(rows, function(x, y)
        if x.minPrice ~= y.minPrice then return x.minPrice < y.minPrice end
        if x.itemKey.itemID ~= y.itemKey.itemID then return x.itemKey.itemID < y.itemKey.itemID end
        return x.itemKey.itemSuffix < y.itemKey.itemSuffix
    end)
    return rows
end

local function checkBrowseQuery(q)
    if type(q) ~= "table" or type(q.searchString) ~= "string" or type(q.sorts) ~= "table" then
        error("SendBrowseQuery: bad argument #1 (an AuctionHouseBrowseQuery with searchString and sorts)", 3)
    end
    for _, f in ipairs(q.itemClassFilters or {}) do
        if type(f) ~= "table" or type(f.classID) ~= "number" then
            error("SendBrowseQuery: bad itemClassFilters (each needs a classID)", 3)
        end
    end
end

-- ---------------------------------------------------------------------
-- Purchases
-- ---------------------------------------------------------------------

-- The cheapest `qty` units of a commodity, a stack at a time: total, the
-- dearest unit taken, the plan { auction, units, unit }; nil when the shelf
-- holds fewer.
local function takeUnits(id, qty)
    local list = {}
    for _, a in ipairs(S().auctions) do
        if a.itemID == id and (a.count or 0) > 0 and (a.buyout or 0) > 0 and not a.sold then list[#list + 1] = a end
    end
    table.sort(list, function(x, y)
        local ux, uy = math.floor(x.buyout / x.count), math.floor(y.buyout / y.count)
        if ux ~= uy then return ux < uy end
        return x.auctionID < y.auctionID
    end)
    local need, total, worst, plan = qty, 0, 0, {}
    for _, a in ipairs(list) do
        if need <= 0 then break end
        local unit = math.floor(a.buyout / a.count)
        local n = math.min(need, a.count)
        total, worst, need = total + unit * n, unit, need - n
        plan[#plan + 1] = { auction = a, units = n, unit = unit }
    end
    if need > 0 then return nil end
    return total, worst, plan
end

local function removeAuction(a)
    for i, x in ipairs(S().auctions) do
        if x == a then table.remove(S().auctions, i); return end
    end
end

local function buyUnits(plan)
    for _, p in ipairs(plan) do
        local a = p.auction
        a.count = a.count - p.units
        if a.count <= 0 then removeAuction(a) else a.buyout = a.buyout - p.unit * p.units end
    end
end

local function auctionByID(id)
    for _, a in ipairs(S().auctions) do if a.auctionID == id then return a end end
end

-- ---------------------------------------------------------------------
-- The client's functions
-- ---------------------------------------------------------------------

local function install()
    -- The house's rows cost no time to read: a frame's slice (ns.Game.SLICE_MS)
    -- ends on the row count alone, the same however busy the computer is. A
    -- test of slow rows moves this clock itself.
    _G.debugprofilestop = function() return 0 end
    -- The client's mail subjects for the house's letters (GlobalStrings).
    _G.AUCTION_EXPIRED_MAIL_SUBJECT = _G.AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"
    _G.AUCTION_SOLD_MAIL_SUBJECT = _G.AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s"
    _G.AUCTION_REMOVED_MAIL_SUBJECT = _G.AUCTION_REMOVED_MAIL_SUBJECT or "Auction canceled: %s"
    local AH = {}
    _G.C_AuctionHouse = AH
    -- Each function is logged by its name.
    local function def(name, fn)
        AH[name] = function(...)
            record(name, ...)
            return fn(...)
        end
    end

    -- Forever's answer (a single item still takes whole silver only: postAnswer).
    def("SupportsCopperValues", function() return true end)

    -- The docs' CloseAuctionHouse: closes the window like the player does.
    def("CloseAuctionHouse", function() AHW.Close() end)

    def("IsThrottledMessageSystemReady", function() return ready() end)

    def("ReplicateItems", function()
        local st = S()
        local ignored = st.replicateCooldown ~= nil and st.lastReplicate ~= nil
            and GetTime() - st.lastReplicate < st.replicateCooldown - EPS
        local sent = send("ReplicateItems", function()
            if ignored then record("Ignored", "ReplicateItems"); return end
            local snap = {}
            for i, a in ipairs(S().auctions) do snap[i] = a end
            S().replicate = snap
            S().replicateAt = GetTime()
            fire("REPLICATE_ITEM_LIST_UPDATE")
        end)
        if sent and not ignored then st.lastReplicate = GetTime() end
    end)
    def("GetNumReplicateItems", function()
        local st = S()
        if st.replicateLate and st.replicateAt and GetTime() < st.replicateAt + st.replicateLate - EPS then
            return math.min(st.replicateEarly or 0, #st.replicate)
        end
        return #st.replicate
    end)
    -- name, texture, count, qualityID, usable, level, levelType, minBid,
    -- minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName,
    -- owner, ownerFullName, saleStatus, itemID, hasAllInfo (0-based index)
    def("GetReplicateItemInfo", function(index)
        local st = S()
        local a = type(index) == "number" and st.replicate[index + 1]
        if not a then return end
        if st.replicateBlank and GetTime() < st.replicateAt + st.replicateBlank - EPS then return end
        local known = cached(a.itemID) and not st.staleRows[a.itemID]
        local owner = a.owner or "Seller"
        return known and nameOf(a.itemID) or nil, known and 134400 or nil, a.count or 0, a.quality or 1, true,
            a.level or 1, "", a.minBid or ((a.buyout or 0) > 0 and a.buyout or 1), 0, a.buyout or 0, a.bid or 0,
            nil, nil, owner, owner .. "-Forever", 0, a.itemID, known
    end)
    def("GetReplicateItemLink", function(index)
        local a = type(index) == "number" and S().replicate[index + 1]
        if a and S().staleRows[a.itemID] then return nil end
        return a and linkOf(a) or nil
    end)
    def("GetReplicateItemTimeLeft", function(index)
        local a = type(index) == "number" and S().replicate[index + 1]
        return a and (a.timeLeft or 2) or nil
    end)

    def("MakeItemKey", function(itemID, itemLevel, itemSuffix, battlePetSpeciesID)
        if type(itemID) ~= "number" then error("MakeItemKey: bad argument #1 (itemID, a number)", 3) end
        return { itemID = itemID, itemLevel = itemLevel or levelOf(itemID), itemSuffix = itemSuffix or 0,
            battlePetSpeciesID = battlePetSpeciesID or 0 }
    end)
    -- A recipe's skill (the game's Skill column) or a piece of gear's level.
    -- Like the server, nothing until it has sent it (an auction's skillLate:
    -- AHW.SendExtra(itemID) sends it and fires EXTRA_BROWSE_INFO_RECEIVED).
    def("GetExtraBrowseInfo", function(key)
        checkKey("GetExtraBrowseInfo", key)
        for _, a in ipairs(S().auctions) do
            if a.itemID == key.itemID and a.skill and not a.skillLate then return a.skill end
        end
        return nil
    end)
    def("GetItemKeyInfo", function(key)
        checkKey("GetItemKeyInfo", key)
        local id = key.itemID
        if S().missing[id] or not cached(id) then return nil end
        local quality, equipment, name = 1, false, nameOf(id)
        for _, a in ipairs(S().auctions) do
            if a.itemID == id then
                if a.quality then quality = a.quality end
                -- ammo (classID 6) goes in the ammo slot, so the game may call it equipment (a guess)
                if a.suffix or a.classID == 2 or a.classID == 4 or a.classID == 6 then equipment = true end
                if a.words and key.itemSuffix == a.suffix and not S().plainKeyNames then name = name .. " " .. a.words end
            end
        end
        return { itemID = id, battlePetSpeciesID = 0, itemName = name, quality = quality, iconFileID = 134400,
            isPet = false, isCommodity = S().commodities[id] == true, isEquipment = equipment }
    end)

    -- A real link of one auction of that exact key (the game's own AH shows it on
    -- a browse row's hover, Blizzard_AuctionHouseSharedTemplates.lua, forever:
    -- GetItemKeySampleLink first, SetItemKey only without one). Nil when nothing
    -- of that key is up or the item isn't cached (GUESS), or with noSampleLinks.
    def("GetItemKeySampleLink", function(key)
        checkKey("GetItemKeySampleLink", key)
        if S().noSampleLinks then return nil end
        for _, a in ipairs(S().auctions) do
            if a.itemID == key.itemID and (a.suffix or 0) == (key.itemSuffix or 0) then return linkOf(a) end
        end
        return nil
    end)

    -- SendSearchQuery(itemKey, sorts, separateOwnerItems[, minLevel, maxLevel])
    local function checkQuery(fn, key, sorts, separate)
        checkKey(fn, key)
        if type(sorts) ~= "table" then error(fn .. ": bad argument #2 (sorts, a table)", 3) end
        if type(separate) ~= "boolean" then error(fn .. ": bad argument #3 (separateOwnerItems, a boolean)", 3) end
    end
    def("SendSearchQuery", function(key, sorts, separate)
        checkQuery("SendSearchQuery", key, sorts, separate)
        search("SendSearchQuery", key)
    end)
    def("SendSellSearchQuery", function(key, sorts, separate)
        checkQuery("SendSellSearchQuery", key, sorts, separate)
        search("SendSellSearchQuery", key)
    end)

    -- Browse results: one list (the latest query), shown `page` rows at a time.
    def("SendBrowseQuery", function(query)
        checkBrowseQuery(query)
        local q = copy(query)
        send("SendBrowseQuery", function()
            S().browse = { rows = browseRows(q), shown = S().page }
            fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        end)
    end)
    -- The player's favorites (spec.favorites), searched into the one browse list.
    def("HasFavorites", function() return #S().favorites > 0 end)
    def("FavoritesAreAvailable", function() return true end)
    def("IsFavoriteItem", function(key)
        checkKey("IsFavoriteItem", key)
        for _, id in ipairs(S().favorites) do if id == key.itemID then return true end end
        return false
    end)
    def("SetFavoriteItem", function(key, on)
        checkKey("SetFavoriteItem", key)
        local list = S().favorites
        for i = #list, 1, -1 do if list[i] == key.itemID then table.remove(list, i) end end
        if on then list[#list + 1] = key.itemID end
        fire("AUCTION_HOUSE_FAVORITES_UPDATED")
    end)
    def("SearchForFavorites", function(sorts)
        if type(sorts) ~= "table" then error("SearchForFavorites: bad argument #1 (sorts)", 2) end
        send("SearchForFavorites", function()
            local want = {}
            for _, id in ipairs(S().favorites) do want[id] = true end
            local rows = {}
            for _, r in ipairs(browseRows({ searchString = "" })) do
                if want[r.itemKey.itemID] then rows[#rows + 1] = r end
            end
            S().browse = { rows = rows, shown = S().page }
            fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        end)
    end)
    def("GetBrowseResults", function()
        local b = S().browse
        local out = {}
        for i = 1, b and shownRows(b) or 0 do out[i] = copy(b.rows[i]) end
        return out
    end)
    def("HasFullBrowseResults", function()
        local b = S().browse
        return b ~= nil and b.shown >= #b.rows
    end)
    def("RequestMoreBrowseResults", function()
        local b = S().browse
        if not b or b.shown >= #b.rows then return end
        send("RequestMoreBrowseResults", function()
            if S().browse ~= b then return end   -- a new query replaced the list meanwhile
            local from = shownRows(b)
            b.shown = b.shown + S().page
            for _, e in ipairs(S().moreEvents) do
                if e == "added" then
                    local added = {}
                    for i = from + 1, shownRows(b) do added[#added + 1] = copy(b.rows[i]) end
                    fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", added)
                else
                    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
                end
            end
        end)
    end)

    -- Commodity results (1-based).
    def("GetNumCommoditySearchResults", function(id)
        local r = S().commodity[id]
        return r and shownRows(r) or 0
    end)
    def("GetCommoditySearchResultInfo", function(id, index)
        local r = S().commodity[id]
        if not r or type(index) ~= "number" or index < 1 or index > shownRows(r) then return nil end
        return copy(r.rows[index])
    end)
    def("HasFullCommoditySearchResults", function(id)
        local r = S().commodity[id]
        return r ~= nil and not r.glitch and r.shown >= #r.rows
    end)
    def("RequestMoreCommoditySearchResults", function(id)
        local r = S().commodity[id]
        if not r or r.shown >= #r.rows then return true end
        send("RequestMoreCommoditySearchResults", function()
            r.shown = r.shown + S().page
            for _, e in ipairs(S().moreEvents) do
                fire(e == "added" and "COMMODITY_SEARCH_RESULTS_ADDED" or "COMMODITY_SEARCH_RESULTS_UPDATED", id)
            end
        end)
        return false
    end)

    -- Item results (1-based), kept per itemID.
    local function itemResults(fn, key)
        checkKey(fn, key)
        return S().items[key.itemID]
    end
    def("GetNumItemSearchResults", function(key)
        local r = itemResults("GetNumItemSearchResults", key)
        return r and shownRows(r) or 0
    end)
    def("GetItemSearchResultInfo", function(key, index)
        local r = itemResults("GetItemSearchResultInfo", key)
        if not r or type(index) ~= "number" or index < 1 or index > shownRows(r) then return nil end
        return copy(r.rows[index])
    end)
    def("HasFullItemSearchResults", function(key)
        local r = itemResults("HasFullItemSearchResults", key)
        return r ~= nil and not r.glitch and r.shown >= #r.rows
    end)

    -- The game's own window refreshes held results this way after a purchase
    -- (Blizzard_AuctionHouseFrame.lua forever, RefreshSearchResults): the item's
    -- results are asked again from the first page and answer *_UPDATED. Not a
    -- SendSearchQuery, so not counted toward the 100 a minute (a GUESS: the docs
    -- limit those two by name).
    def("HasSearchResults", function(key)
        checkKey("HasSearchResults", key)
        local id = key.itemID
        return (S().commodities[id] and S().commodity[id] or S().items[id]) ~= nil
    end)
    def("RefreshCommoditySearchResults", function(id)
        if type(id) ~= "number" then error("RefreshCommoditySearchResults: bad argument #1 (a number)", 2) end
        send("RefreshCommoditySearchResults", function()
            S().commodity[id] = { rows = commodityRows(id), shown = S().page }
            fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
        end)
    end)
    def("RefreshItemSearchResults", function(key)
        local r = itemResults("RefreshItemSearchResults", key)
        local q = r and r.key or copyKey(key)
        local exact = r == nil or r.exact
        send("RefreshItemSearchResults", function()
            S().items[key.itemID] = { rows = itemRows(q, exact), shown = S().page, key = q, exact = exact }
            fire("ITEM_SEARCH_RESULTS_UPDATED", copyKey(key), nil)
        end)
    end)
    def("RequestMoreItemSearchResults", function(key)
        local r = itemResults("RequestMoreItemSearchResults", key)
        if not r or r.shown >= #r.rows then return true end
        local q = copyKey(key)
        send("RequestMoreItemSearchResults", function()
            r.shown = r.shown + S().page
            for _, e in ipairs(S().moreEvents) do
                if e == "added" then
                    fire("ITEM_SEARCH_RESULTS_ADDED", copyKey(q))
                else
                    fire("ITEM_SEARCH_RESULTS_UPDATED", copyKey(q), nil)
                end
            end
        end)
        return false
    end)

    -- Purchases: hardware-only (a click or key), throttled messages.
    local function checkNumbers(fn, ...)
        for i = 1, select("#", ...) do
            if type(select(i, ...)) ~= "number" then error(fn .. ": bad argument #" .. i .. " (a number)", 3) end
        end
    end
    def("StartCommoditiesPurchase", function(id, qty, unit)
        checkNumbers("StartCommoditiesPurchase", id, qty)
        if not stub.HardwareOnly("StartCommoditiesPurchase") then return end
        send("StartCommoditiesPurchase", function()
            local total = takeUnits(id, qty)
            if not total or S().quoteFails then
                S().purchase = nil
                fire("COMMODITY_PRICE_UNAVAILABLE")
                return
            end
            local bump = S().quoteBump
            total = total + bump
            S().purchase = { itemID = id, qty = qty, total = total, expires = GetTime() + S().quoteSeconds }
            fire("COMMODITY_PRICE_UPDATED", math.floor(total / qty), total)
        end)
    end)
    def("ConfirmCommoditiesPurchase", function(id, qty)
        checkNumbers("ConfirmCommoditiesPurchase", id, qty)
        if not stub.HardwareOnly("ConfirmCommoditiesPurchase") then return end
        local p = S().purchase
        if not p or p.itemID ~= id or p.qty ~= qty then
            record("Refused", "ConfirmCommoditiesPurchase")   -- no matching start
            return
        end
        send("ConfirmCommoditiesPurchase", function()
            S().purchase = nil
            local total, _, plan = takeUnits(id, qty)
            if not total or total + S().quoteBump > p.total or GetTime() >= p.expires then
                fire("COMMODITY_PURCHASE_FAILED")
                return
            end
            buyUnits(plan)
            fire("COMMODITY_PURCHASE_SUCCEEDED")
            if not S().silentPurchase then fire("COMMODITY_PURCHASED", id, qty) end
            pay(-(total + S().quoteBump))
        end)
    end)
    def("CancelCommoditiesPurchase", function() S().purchase = nil end)
    def("GetQuoteDurationRemaining", function()
        local p = S().purchase
        return p and math.max(0, p.expires - GetTime()) or 0
    end)
    def("PlaceBid", function(auctionID, amount)
        checkNumbers("PlaceBid", auctionID, amount)
        if not stub.HardwareOnly("PlaceBid") then return end
        send("PlaceBid", function()
            local a = auctionByID(auctionID)
            -- one of the row at its one's price, as its rows say (GUESS at the server:
            -- TSM takes one a buy; the row of the rest stays up)
            local count = a and math.max(a.count or 1, 1) or 1
            local buyout = a and math.floor((a.buyout or 0) / count) or 0
            local minBid = a and (a.minBid or (buyout > 0 and buyout or 1)) or 0
            if not a or S().soldOut[auctionID] or amount < minBid then
                local code = S().soldOut[auctionID]
                fire("AUCTION_HOUSE_SHOW_ERROR", type(code) == "number" and code or 1)
            elseif buyout > 0 and amount >= buyout then
                if count > 1 then a.count, a.buyout = count - 1, a.buyout - buyout
                else removeAuction(a) end
                fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
                fire("ITEM_PURCHASED", a.itemID)
                pay(-(buyout - (a.myBid or 0)))
            else
                pay(-(amount - (a.myBid or 0)))
                a.bid, a.myBid = amount, amount
                fire("BID_ADDED", auctionID)
            end
        end)
    end)

    -- Selling: the bag slot behind an ItemLocation, posts, the owned list, cancels.
    local function slotOf(loc)
        if type(loc) ~= "table" or type(loc.GetBagAndSlot) ~= "function" then return nil end
        local bag, slot = loc:GetBagAndSlot()
        local b = S().bags and S().bags[bag]
        return b and b[slot], bag, slot
    end
    local function checkLoc(fn, loc)
        if type(loc) ~= "table" or type(loc.GetBagAndSlot) ~= "function" then
            error(fn .. ": bad argument #1 (an ItemLocation)", 3)
        end
    end
    local function checkDuration(fn, d)
        if d ~= 1 and d ~= 2 and d ~= 3 then error(fn .. ": bad duration (1, 2 or 3)", 3) end
    end
    def("GetItemCommodityStatus", function(loc)
        checkLoc("GetItemCommodityStatus", loc)
        local it = slotOf(loc)
        if not it or not cached(it.itemID) then return 0 end
        return S().commodities[it.itemID] and 2 or 1
    end)
    def("IsSellItemValid", function(loc)
        checkLoc("IsSellItemValid", loc)
        local it = slotOf(loc)
        return it ~= nil and not it.isBound
    end)
    -- Every unbound stack of the item counts (the game's sell frame posts across stacks).
    local function available(id)
        local n = 0
        for _, b in pairs(S().bags or {}) do
            for _, it in pairs(b) do if it.itemID == id and not it.isBound then n = n + it.stackCount end end
        end
        return n
    end
    def("GetAvailablePostCount", function(loc)
        local it = slotOf(loc)
        return it and available(it.itemID) or 0
    end)
    local function deposit(id, dur, qty)
        local known = S().known[id]
        local sell = known and known.vendorSell
        for _, a in ipairs(S().auctions) do if a.itemID == id and a.vendorSell then sell = a.vendorSell end end
        return math.max(1, (sell or 1) * qty * dur)
    end
    def("CalculateCommodityDeposit", function(id, dur, qty) return deposit(id, dur, qty) end)
    def("CalculateItemDeposit", function(loc, dur, qty)
        local it = slotOf(loc)
        return it and deposit(it.itemID, dur, qty) or nil
    end)
    local function newAuction(it, count, buyout, dur)
        local st = S()
        st.nextAuction = st.nextAuction + 1
        local a = { auctionID = st.nextAuction, itemID = it.itemID, name = it.name, count = count, buyout = buyout,
            mine = true, duration = dur, timeLeftSeconds = ({ 7200, 28800, 86400 })[dur], deposit = deposit(it.itemID, dur, count) }
        table.insert(st.auctions, a)
        return a
    end
    -- From the given slot first, then the item's other stacks.
    local function takeFromBag(it, bag, slot, qty)
        local function take(b, s, x)
            local n = math.min(qty, x.stackCount)
            x.stackCount, qty = x.stackCount - n, qty - n
            if x.stackCount <= 0 then S().bags[b][s] = nil end
        end
        take(bag, slot, it)
        for b, list in pairs(S().bags) do
            for s, x in pairs(list) do
                if qty > 0 and x.itemID == it.itemID and not x.isBound then take(b, s, x) end
            end
        end
        fire("BAG_UPDATE_DELAYED")
    end
    -- One post's answer: nil when it can't go (then the error event fires).
    local function postAnswer(kind, loc, dur, qty, price, bid)
        local it, bag, slot = slotOf(loc)
        local classID = it and C_Item and C_Item.GetItemInfo and select(12, C_Item.GetItemInfo(it.itemID))
        local whole = classID == 2 or classID == 4 or classID == 9
        if kind == "item" and whole and (price % 100 ~= 0 or (bid and bid % 100 ~= 0)) then
            if qty > 1 then fire("AUCTION_MULTISELL_FAILURE") end
            fire("AUCTION_HOUSE_SHOW_ERROR", AHW.DATABASE_ERROR)
            return
        end
        if not it or it.isBound or available(it.itemID) < qty or qty < 1 or price < 1 or S().postFails[it.itemID] then
            if kind == "item" and qty > 1 then fire("AUCTION_MULTISELL_FAILURE") end
            local code = it and S().postFails[it.itemID]
            fire("AUCTION_HOUSE_SHOW_ERROR", type(code) == "number" and code or 1)
            return
        end
        local id, name = it.itemID, it.name
        takeFromBag(it, bag, slot, qty)
        local owned = { itemID = id, name = name }
        if kind == "commodity" then
            local a = newAuction(owned, qty, price * qty, dur)
            fire("AUCTION_HOUSE_AUCTION_CREATED", a.auctionID)
            pay(-a.deposit)
            return
        end
        if qty > 1 then fire("AUCTION_MULTISELL_START", qty) end
        for n = 1, qty do
            local a = newAuction(owned, 1, price, dur)
            fire("AUCTION_HOUSE_AUCTION_CREATED", a.auctionID)
            pay(-a.deposit)
            if qty > 1 then fire("AUCTION_MULTISELL_UPDATE", n, qty) end
        end
    end
    local function post(kind, fn, loc, dur, qty, price, confirming, bid)
        checkLoc(fn, loc)
        checkDuration(fn, dur)
        checkNumbers(fn, qty, price)
        if not stub.HardwareOnly(fn) then return false end
        local it = slotOf(loc)
        if it and S().postRefused[it.itemID] then
            fire("AUCTION_HOUSE_POST_ERROR")
            return true
        end
        if not confirming and it and S().postWarning[it.itemID] then
            S().pendingPost = { kind = kind, loc = loc, dur = dur, qty = qty, price = price }
            fire("AUCTION_HOUSE_POST_WARNING")
            return true
        end
        if confirming then
            local p = S().pendingPost
            S().pendingPost = nil
            if not p or p.kind ~= kind or p.dur ~= dur or p.qty ~= qty or p.price ~= price then
                record("Refused", fn)
                return
            end
        end
        send(fn, function() postAnswer(kind, loc, dur, qty, price, bid) end)
        return false
    end
    def("PostCommodity", function(loc, dur, qty, unit) return post("commodity", "PostCommodity", loc, dur, qty, unit) end)
    def("PostItem", function(loc, dur, qty, bid, buyout)
        if bid ~= nil and not (type(bid) == "number" and bid >= 1 and bid < buyout) then
            error("PostItem: a bid is a number under the buyout", 2)
        end
        return post("item", "PostItem", loc, dur, qty, buyout, nil, bid)
    end)
    def("ConfirmPostCommodity", function(loc, dur, qty, unit) return post("commodity", "ConfirmPostCommodity", loc, dur, qty, unit, true) end)
    def("ConfirmPostItem", function(loc, dur, qty, bid, buyout) return post("item", "ConfirmPostItem", loc, dur, qty, buyout, true, bid) end)

    def("QueryOwnedAuctions", function(sorts)
        if type(sorts) ~= "table" then error("QueryOwnedAuctions: bad argument #1 (sorts, a table)", 2) end
        send("QueryOwnedAuctions", function()
            local list = {}
            for _, a in ipairs(S().auctions) do if a.mine then list[#list + 1] = a end end
            S().owned = list
            S().ownedLoaded = {}
            for _, a in ipairs(list) do S().ownedLoaded[a.auctionID] = true end
            fire("OWNED_AUCTIONS_UPDATED")
        end)
    end)
    -- The auctions the player bid on (PlaceBid below the buyout): QueryBids answers
    -- BIDS_UPDATED, GetBidInfo(i) is the docs' BidInfo. An auction's outbid = true
    -- makes someone else the highest bidder.
    def("QueryBids", function(sorts, auctionIDs)
        if type(sorts) ~= "table" or type(auctionIDs) ~= "table" then
            error("QueryBids: bad arguments (sorts, auctionIDs: tables)", 3)
        end
        send("QueryBids", function()
            local list = {}
            for _, a in ipairs(S().auctions) do if a.myBid then list[#list + 1] = a end end
            S().bids = list
            fire("BIDS_UPDATED")
        end)
    end)
    def("GetNumBids", function() return #(S().bids or {}) end)
    def("GetBidInfo", function(index)
        local a = type(index) == "number" and S().bids and S().bids[index]
        if not a then return nil end
        local count = math.max(a.count or 1, 1)
        return {
            auctionID = a.auctionID, itemKey = { itemID = a.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
            itemLink = linkOf(a), timeLeft = a.timeLeft or 3, minBid = a.nextBid or (a.bid or 0) + 100,
            bidAmount = a.bid, buyoutAmount = (a.buyout or 0) > 0 and math.floor(a.buyout / count) or nil,
            bidder = a.outbid and "Player-1-OTHER" or UnitGUID("player"),
        }
    end)
    def("GetNumOwnedAuctions", function() return #S().owned end)
    def("HasFullOwnedAuctionResults", function() return true end)
    def("GetOwnedAuctionInfo", function(index)
        local a = type(index) == "number" and S().owned[index]
        if not a then return nil end
        return {
            auctionID = a.auctionID, itemKey = { itemID = a.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
            itemLink = linkOf(a), status = a.sold and 1 or 0, quantity = a.count,
            timeLeftSeconds = (not a.sold) and (a.timeLeftSeconds or 86400) or nil, timeLeft = a.timeLeft or 3,
            -- the price of one (Auctionator's Cancelling.lua 242-244 multiplies it by the quantity),
            -- but a SOLD one's is the whole sale (seen by players: 9 Swiftthistle sold for
            -- 70s 11c showed as 70s 11c each, 6g 30s 99c in all)
            bidAmount = a.bid, buyoutAmount = (a.buyout or 0) > 0 and (a.sold and a.buyout or math.floor(a.buyout / a.count)) or nil,
            bidder = a.bid and "Someone" or nil,
        }
    end)
    def("CanCancelAuction", function(id) local a = auctionByID(id); return a ~= nil and a.mine == true and not a.sold end)
    def("GetCancelCost", function() return S().cancelCost end)
    def("CancelAuction", function(id)
        checkNumbers("CancelAuction", id)
        if not stub.HardwareOnly("CancelAuction") then return end
        send("CancelAuction", function()
            local a = auctionByID(id)
            if S().cancelFails then
                fire("AUCTION_HOUSE_SHOW_ERROR", S().cancelFails)
                return
            end
            if not a or not a.mine or a.sold or not S().ownedLoaded[id] then
                fire("AUCTION_HOUSE_SHOW_ERROR", 1)
                return
            end
            removeAuction(a)
            table.insert(S().mailed, { itemID = a.itemID, count = a.count })
            if S().cancelEvent == nil then fire("AUCTION_CANCELED", id)
            elseif S().cancelEvent then fire("AUCTION_CANCELED", S().cancelEvent) end
            pay(-S().cancelCost)
            AHW.Letter(_G.AUCTION_REMOVED_MAIL_SUBJECT, a)
        end)
    end)

    -- C_Item: a copy of whatever the game had, plus the item-data calls.
    local item = {}
    for k, v in pairs(_G.C_Item or {}) do item[k] = v end
    _G.C_Item = item
    local function idOf(v) return type(v) == "number" and v or tonumber(tostring(v):match("item:(%d+)") or v) end
    item.DoesItemExistByID = function(v)
        record("DoesItemExistByID", v)
        local id = idOf(v)
        return id ~= nil and id > 0 and not S().missing[id]
    end
    -- What the client knows of an item without the server (TSM calls these its
    -- "preloaded" fields): answered for any item on an auction, cached or not.
    -- classID: the auction's, else 4 (armor) for a suffixed one, else 0.
    item.GetItemInfoInstant = function(v)
        local id = idOf(v)
        if not id or S().missing[id] then return nil end
        local function from(a)
            local class = a.classID or (a.suffix and 4) or 0
            return id, "", "", "", a.icon or ("tex:" .. id), class, a.subClassID or 0
        end
        for _, a in ipairs(S().auctions) do
            if a.itemID == id then return from(a) end
        end
        local k = S().known[id]
        if k then return from(k) end
        return nil
    end
    item.IsItemDataCachedByID = function(v)
        record("IsItemDataCachedByID", v)
        local id = idOf(v)
        return id ~= nil and not S().missing[id] and cached(id)
    end
    -- The docs' returns (ItemDocumentation.lua) for an item on one of the
    -- auctions, from its spec (name, link, quality 1, itemLevel or level 1,
    -- icon "tex:<id>", vendorSell 0, classID, subClassID, bindType 0); nothing
    -- for one not cached yet, missing, or on no auction.
    item.GetItemInfo = function(v)
        local id = idOf(v)
        if not id or S().missing[id] or not cached(id) then return nil end
        for _, a in ipairs(S().auctions) do
            if a.itemID == id then
                return nameOf(id), linkOf(a), a.quality or 1, a.itemLevel or a.level or 1, a.level or 1, "", "",
                    a.stack or 1, "", a.icon or ("tex:" .. id), a.vendorSell or 0, a.classID or 0, a.subClassID or 0,
                    a.bindType or 0, 0, nil, false, ""
            end
        end
        local k = S().known[id]
        if k then
            return k.name, "|cffffffff|Hitem:" .. id .. "::::::::60::::::::|h[" .. k.name .. "]|h|r", k.quality or 1,
                k.level or 1, k.level or 1, "", "", k.stack or 20, "", k.icon or ("tex:" .. id), k.vendorSell or 0,
                k.classID or 0, k.subClassID or 0, k.bindType or 0, 0, nil, false, ""
        end
        return nil
    end
    -- Loads a step later: ITEM_DATA_LOAD_RESULT(id, false) for a missing item,
    -- the events at once (next step) for a known one, nothing for neverCache.
    item.RequestLoadItemDataByID = function(v)
        record("RequestLoadItemDataByID", v)
        local id = idOf(v)
        if not id then return end
        if S().missing[id] then
            later(S().itemDelay, function() fire("ITEM_DATA_LOAD_RESULT", id, false) end)
        elseif not cached(id) then
            if S().neverCache[id] or S().loading[id] then return end
            -- an ask the client lets fall (dropAsks): only asking again loads it
            local drop = S().dropAsks[id]
            if drop and drop > 0 then
                S().dropAsks[id] = drop - 1
                return
            end
            S().loading[id] = true
            -- a cold cache (itemSpacing): one load after another, not side by side
            local st, at = S(), GetTime() + S().itemDelay
            if st.itemSpacing and st.lastLoad then at = math.max(at, st.lastLoad + st.itemSpacing) end
            st.lastLoad = at
            later(at - GetTime(), function() if not cached(id) then AHW.Cache(id) end end)
        else
            later(S().itemDelay, function() fire("ITEM_DATA_LOAD_RESULT", id, true) end)
        end
    end
    -- Whether this character can use an item: false when an auction of it
    -- says usable = false (the UsableOnly filter's rule), else true.
    _G.C_PlayerInfo = _G.C_PlayerInfo or {}
    C_PlayerInfo.CanUseItem = function(v)
        local id = idOf(v)
        for _, a in ipairs(S().auctions) do
            if a.itemID == id and a.usable == false then return false end
        end
        return true
    end

    _G.Enum = _G.Enum or {}
    Enum.PlayerInteractionType = Enum.PlayerInteractionType or { Merchant = 5, MailInfo = 17, Auctioneer = AHW.AUCTIONEER }
    Enum.AuctionHouseFilter = { None = 0 }
    for k, v in pairs(FILTER) do Enum.AuctionHouseFilter[k] = v end
    Enum.AuctionHouseTimeLeftBand = { Short = 0, Medium = 1, Long = 2, VeryLong = 3 }
    Enum.AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 }
    C_Timer.After, C_Timer.NewTimer, C_Timer.NewTicker = after, newTimer, newTicker
end

-- The player's bags (spec.bags): C_Container reads them, ItemLocation points into them.
local function installBags()
    _G.NUM_BAG_SLOTS = 4
    _G.Enum = _G.Enum or {}
    Enum.BagIndex = { Keyring = -1, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 }   -- the docs' (part)
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return S().bags[bag] and 16 or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local it = S().bags[bag] and S().bags[bag][slot]
            if not it then return nil end
            local link = it.link or ("|cffffffff|Hitem:" .. it.itemID .. "::::::::60::::::::|h[" .. nameOf(it.itemID) .. "]|h|r")
            return { itemID = it.itemID, stackCount = it.stackCount, hyperlink = link, isBound = it.isBound == true,
                iconFileID = 134400, quality = it.quality or 1, isLocked = it.locked == true, hasNoValue = it.noValue == true }
        end,
    }
    local Loc = {}
    Loc.__index = Loc
    function Loc:GetBagAndSlot() return self.bag, self.slot end
    function Loc:IsValid() return S().bags[self.bag] ~= nil and S().bags[self.bag][self.slot] ~= nil end
    function Loc:IsBagAndSlot() return true end
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return setmetatable({ bag = bag, slot = slot }, Loc) end }
end

-- The player's bags as the world holds them (a test may change them).
function AHW.Bags() return S().bags end

-- What cancels mailed back: { { itemID, count }... }.
function AHW.Mailed() return S().mailed end

local function stackName(a)
    return (a.name or nameOf(a.itemID)) .. ((a.count or 1) > 1 and (" (" .. a.count .. ")") or "")
end

-- A letter from the house in mailworld's inbox queue (when it is loaded): the
-- item back by default, or `extra` (gold and an invoice) instead.
function AHW.Letter(format, a, extra)
    local MW = mailw()
    if not MW then return end
    local letter = { sender = "Alliance Auction House", subject = format:format(stackName(a)) }
    if extra then
        for k, v in pairs(extra) do letter[k] = v end
    else
        letter.items = { { name = a.name or nameOf(a.itemID), itemID = a.itemID, count = a.count, quality = a.quality or 1 } }
    end
    MW.Arrive(letter)
end

-- Someone bought one of the player's auctions: it stays listed as Sold, and
-- (with mailworld) the seller's letter waits: the buyout less the 5% cut, the
-- deposit back, and the invoice. `count` (a commodity's, fewer than it holds)
-- sells only part of it: the modern AH mails one letter per buy, for that
-- count, and the rest stays up (its buyout and deposit what is left). GUESS:
-- the deposit comes back in proportion (floor), the last part takes the rest.
function AHW.Sell(auctionID, buyer, count)
    local a = auctionByID(auctionID)
    if not a or a.sold then return end
    local all = a.count or 1
    count = (type(count) == "number" and count > 0 and count < all) and count or all
    local bid, deposit = a.buyout or 0, a.deposit or 0
    if count < all then
        bid = math.floor((a.buyout or 0) * count / all)
        deposit = math.floor((a.deposit or 0) * count / all)
        a.count, a.buyout, a.deposit = all - count, (a.buyout or 0) - bid, (a.deposit or 0) - deposit
    else
        a.sold = true
        -- The real client, seen in game: 17 commodities were booked canceled, nobody
        -- canceled them, and their sale letter came. Its signal for a sold-out auction.
        if S().saleCancels and S().open then fire("AUCTION_CANCELED", auctionID) end
    end
    local cut = math.floor(bid * 0.05)
    local part = { name = a.name, itemID = a.itemID, count = count }
    AHW.Letter(_G.AUCTION_SOLD_MAIL_SUBJECT, part, { money = bid - cut + deposit,
        invoice = { type = "seller", item = a.name or nameOf(a.itemID), player = buyer or "Ysella Brightwind", bid = bid,
            buyout = bid, deposit = deposit, cut = cut, count = count } })
end

-- One of the player's auctions ran out: it leaves the house, the deposit is
-- lost and the item comes back by letter.
function AHW.Expire(auctionID)
    local a = auctionByID(auctionID)
    if not a then return end
    AHW.Letter(_G.AUCTION_EXPIRED_MAIL_SUBJECT, a)   -- while the house still knows its name
    removeAuction(a)
    table.insert(S().mailed, { itemID = a.itemID, count = a.count })
end

-- ---------------------------------------------------------------------
-- The world
-- ---------------------------------------------------------------------

function AHW.world(spec)
    spec = spec or {}
    return function()
        AHW.GameWords()
        AHW.state = {
            calls = {}, queue = {}, timers = {}, seq = 0, frames = 0,
            open = false, busy = false, throttled = spec.throttled == true, dearFirst = spec.dearFirst == true,
            step = spec.step or AHW.STEP, itemDelay = spec.itemDelay or AHW.ITEM_DELAY, page = spec.page or AHW.PAGE,
            itemSpacing = spec.itemSpacing, replicateCooldown = spec.replicateCooldown,
            replicateLate = spec.replicateLate, replicateEarly = spec.replicateEarly, replicateBlank = spec.replicateBlank,
            moreEvents = copy(spec.moreEvents or { "added", "updated" }),
            auctions = {}, commodities = copy(spec.commodities or {}), neverCache = copy(spec.neverCache or {}),
            dropAsks = copy(spec.dropAsks or {}), missing = copy(spec.missing or {}), staleRows = copy(spec.staleRows or {}), uncached = {}, loading = {},
            replicate = {}, commodity = {}, items = {}, searches = {}, browse = nil, bids = {},
            quoteBump = spec.quoteBump or 0, quoteFails = spec.quoteFails == true,
            quoteSeconds = spec.quoteSeconds or 300,
            soldOut = copy(spec.soldOut or {}), purchase = nil,
            favorites = copy(spec.favorites or {}), responseFirst = spec.responseFirst == true,
            readyEarly = spec.readyEarly == true, emptyOnce = copy(spec.emptyOnce or {}),
            known = copy(spec.items or {}), bags = copy(spec.bags), postWarning = copy(spec.postWarning or {}),
            postFails = copy(spec.postFails or {}), postRefused = copy(spec.postRefused or {}), cancelFails = spec.cancelFails, cancelCost = spec.cancelCost or 0, saleCancels = spec.saleCancels, cancelEvent = spec.cancelEvent,
            owned = {}, ownedLoaded = {}, mailed = {}, nextAuction = 5000, pendingPost = nil,
        }
        if AHW.state.bags then installBags() end
        local nextID = 1000
        for i, a in ipairs(spec.auctions or {}) do
            local own = copy(a)
            nextID = nextID + 1
            own.auctionID = own.auctionID or nextID
            AHW.state.auctions[i] = own
            if own.cached == false and own.itemID then AHW.state.uncached[own.itemID] = true end
        end
        install()
    end
end

-- Has the game say which ruleset this is, as Forever's client does: the key
-- reads "US-<kind>".
local RULES = { PvPRuleset = 1, RPRuleset = 2, HardcoreRuleset = 3 }
function AHW.Ruleset(kind)
    _G.GetCurrentRegion = function() return 1 end
    _G.RegionalUniqueNamesEnabled = function() return true end
    _G.Enum.GameRule = RULES
    local on = {
        PvP = { [1] = true }, RP = { [2] = true }, RPvP = { [1] = true, [2] = true }, Hardcore = { [3] = true },
    }
    _G.C_GameRules = { IsGameRuleActive = function(rule) return (on[kind] or {})[rule] == true end }
end

-- Loads Daylight UI with the Auction House module on this world (spec), as
-- stub.Load does with opts. Returns the core and the module's namespace.
function AHW.Load(spec, opts)
    opts = opts or {}
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.auctionhouse = true
    o.before = function()
        _G.C_Item, _G.C_AuctionHouse, _G.GetServerTime = BASE_C_ITEM, nil, nil
        _G.C_Container, _G.ItemLocation, _G.NUM_BAG_SLOTS = nil, nil, nil
        _G.C_GameRules, _G.RegionalUniqueNamesEnabled = nil, nil
        if _G.Enum then _G.Enum.GameRule = nil end
        -- The game says the ruleset (PvE unless opts.ruleset names another, none with false).
        if opts.ruleset ~= false then
            AHW.Ruleset(opts.ruleset or "PvE")
        else
            _G.RegionalUniqueNamesEnabled = function() return true end
        end
        _G.DaylightUIAuctionDB = opts.prices
        for _, name in ipairs({ "ahworld", "mailworld", "goldworld" }) do
            local world = package.loaded[name]
            if world then world.state = nil end
        end
        if spec then AHW.world(spec)() end
        if opts.before then opts.before() end
    end
    local DUI = stub.Load(o)
    return DUI, stub.auctionhouse
end

-- The same with one table of options, the world under `ah` (the shape the
-- Auction House tests were first written in). Returns the module's namespace.
function AHW.Mog(opts)
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    local spec = o.ah
    o.ah = nil
    local _, A = AHW.Load(spec, o)
    -- the game layer's tests count requests and time them: the read of your
    -- auctions as the AH opens (the window's convenience) stays out of them
    A.Post.OPEN_READ = nil
    return A
end

return AHW
