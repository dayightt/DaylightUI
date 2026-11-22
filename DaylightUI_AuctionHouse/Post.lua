-- Post: selling at the Auction House, and the player's own auctions. A post
-- and a cancel each take one click (the game allows them only inside one):
-- they go through ns.AH.Act, never the queue. Reading your auctions is an
-- ordinary request.
--
--   ns.Post.HOURS = { 2, 8, 24 }        Forever's durations; the game's duration is the index
--   ns.Post.Index(hours) -> 1 | 2 | 3   (24 for anything else)
--   ns.Post.Step(kind, key) -> 100 | 1  the smallest price step the AH takes: a single piece of
--       gear or a recipe ("item", classID Weapon, Armor, Recipe) only whole silver (Forever
--       answers "Internal auction error" to a recipe at 49s 99c, in the game's own window too:
--       seen in game), and so does everything when the game says it takes no copper
--       (SupportsCopperValues false). Any other single item takes copper (a Silver Rod posts at
--       4s 50c in the game's window, seen in game), and so does a commodity (ore at
--       3s 73c). No key, or a class the game hasn't loaded: whole silver (never refused).
--   ns.Post.Round(copper, kind, down, key) -> copper   onto that step: up, like the game's own
--       box (AuctionHouseUtil.SanitizeAuctionHousePrice), or down (an undercut); nil stays nil
--   ns.Post.Kind(key) -> "commodity" | "item" | nil   nil: not in the bags, or the game
--       doesn't know the item yet (GetItemCommodityStatus Unknown)
--   ns.Post.Sellable(key) -> true when a stack of it is in the bags and the game takes it
--       (IsSellItemValid: a damaged item or one with used charges isn't taken)
--   ns.Post.Most(key) -> how many of it can go up: the bags' count, capped by what the game
--       says it would post (GetAvailablePostCount leaves out a damaged or used copy)
--   ns.Post.Deposit(key, qty, hours) -> copper | nil
--   ns.Post.Send(key, qty, unit, hours, onDone(ok, reason), bid) -> ok, reason
--       bid: gear's starting bid each, under `unit` (nil, or a commodity: buyout only)
--       a commodity: PostCommodity(loc, duration, qty, unit), one auction of qty;
--       an item: PostItem(loc, duration, qty, nil, unit), qty auctions of one
--       (the game's multisell). Done on AUCTION_HOUSE_AUCTION_CREATED (a commodity,
--       or one item) or AUCTION_MULTISELL_UPDATE(n, n); "failed" on
--       AUCTION_HOUSE_SHOW_ERROR, AUCTION_MULTISELL_FAILURE or AUCTION_HOUSE_POST_ERROR,
--       onDone's third value the game's own words when it gave any.
--       Refused at once (false, reason, onDone not called): "closed", "busy", "late"
--       (ns.AH.Act), "failed" (the game's error inside the call; third value its words),
--       "throttled", "nobags" (none of it in the bags to sell), "unknown" (the game
--       doesn't know yet whether it is a commodity), "price" (under a copper),
--       "count" (more than the bags hold), "silver" (a price or bid off Post.Step: the game
--       would answer "Internal auction error"; callers round first with Post.Round), and "confirm": the game warned about
--       the price (needsConfirmation) and posted nothing; Post.Confirm() in the
--       player's next click posts the same values (onDone then hears the end).
--   ns.Post.Confirm() -> ok, reason      "nothing" when no warning waits; "moved" when its
--       bag slot holds something else now (the warning is dropped: the game would post
--       whatever sits there)
--   ns.Post.Warned() -> { key, qty, unit, hours } | nil   the post waiting for that click
--   ns.Post.Forget()                     drops a waiting warning (the player moved on)
--   ns.Post.Owned(onDone(list | nil, reason)) -> ok, reason   QueryOwnedAuctions: one row per
--       auction { auctionID, key, itemID, link, qty, unit (buyout each, nil: bid only; the
--       game's buyoutAmount is already per unit), buyout (unit x qty), bid (0 none), sold,
--       left (seconds, nil when sold or unknown) },
--       sold ones included (the game keeps them listed). Also kept: ns.Post.Mine().
--   ns.Post.Mine() -> the last list read (empty before)
--   ns.Post.ReadAt() -> GetTime() of the last read this visit, nil before one
--       The list is read once just after the Auction House opens, so My auctions shows at
--       once, and again by itself when one of them sells (an AUCTION_CANCELED that isn't a
--       cancel of Daylight UI's) or gets a bid (AUCTION_HOUSE_NEW_BID_RECEIVED), as the
--       game's own window does. The bids are read again then too, once they have been.
--   ns.Post.KeyOf(auctionID) -> the price key of one of your auctions (the ledger's), nil unknown
--   ns.Post.CountOf(auctionID) -> how many units a new auction holds (the ledger's): Daylight UI's own
--       post's (a commodity: its qty; an item: 1 each), else the owned list's, else 1
--   ns.Post.Up(key) -> how many of the item are up (active, not sold) in that list
--   ns.Post.MineLow(key) -> your cheapest of it up in the owned list, nil when none
--   ns.Post.Cancel(auctionID, onDone(ok, reason)) -> ok, reason   CancelAuction, done on
--       AUCTION_CANCELED (any: only one cancel is out, and Forever's may not carry the ID; a
--       player's stalled after one), "failed" on AUCTION_HOUSE_SHOW_ERROR; no answer:
--       the owned list is read again, done when it's gone from it, else "timeout"; refused at
--       once with "closed", "busy", "throttled" or "notmine" (not in the owned list).
--       The items come back by mail (the modern AH mails a cancel back).
--   ns.Post.CancelCost(auctionID) -> copper (0 when the game doesn't say, keeps it secret or errors)
--
-- From the game's own sell and auctions frames (wow-ui-source forever:
-- CommoditiesSellFrame.lua 108-126, ItemSellFrame.lua 480-510, AuctionsFrame.lua,
-- AuctionHouseFrame.lua 77-129). A click the client blocks gives no result:
-- it ends "timeout" and is never retried.

local _, ns = ...

local Post = {}
ns.Post = Post

Post.HOURS = { 2, 8, 24 }
Post.TIMEOUT = 10        -- seconds for a post's answer, plus one per extra auction of an item's multisell
Post.OPEN_READ = 0.1     -- seconds after the Auction House opens that your list is read (nil: not then)

local warned    -- { key, qty, unit, hours, kind, loc, onDone }: the game asked "are you sure"
local mine = {}
local readAt          -- GetTime() of the owned list's last read this visit
local cancelling = false   -- a cancel of Daylight UI's is out: its AUCTION_CANCELED is its own
local bidsRead = false
local sent      -- { key, n, at, wait }: the last post Daylight UI sent (its new auctions' item, units each)

function Post.Index(hours)
    for i, h in ipairs(Post.HOURS) do if h == hours then return i end end
    return #Post.HOURS
end

local function api() return C_AuctionHouse end

local WHOLE = { [2] = true, [4] = true, [9] = true }   -- Enum.ItemClass Weapon, Armor, Recipe
local function wholeOnly(key)
    local id = key and ns.Items.ID(key)
    local classID = id and select(3, ns.Items.Gear(id))
    if type(classID) ~= "number" then return true end
    return WHOLE[classID] == true
end

function Post.Step(kind, key)
    if kind == "item" and wholeOnly(key) then return 100 end
    local a = api()
    if a and a.SupportsCopperValues and a.SupportsCopperValues() == false then return 100 end
    return 1
end

function Post.Round(copper, kind, down, key)
    if type(copper) ~= "number" then return copper end
    local step = Post.Step(kind, key)
    if down then return math.floor(copper / step) * step end
    return math.ceil(copper / step) * step
end

-- The biggest stack of it the game would take: loc, bag, slot. The `false`
-- keeps the game from printing an error for Daylight UI's asking.
local function location(key)
    if not (ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
    local a = api()
    for _, s in ipairs(ns.Bags.Stacks(key)) do
        local loc = ItemLocation:CreateFromBagAndSlot(s.bag, s.slot)
        if not (a and a.IsSellItemValid) or a.IsSellItemValid(loc, false) ~= false then
            return loc, s.bag, s.slot
        end
    end
    return nil
end

function Post.Sellable(key) return location(key) ~= nil end

function Post.Most(key)
    local n = ns.Bags.Free(key)
    local a = api()
    local loc = n > 0 and a and a.GetAvailablePostCount and location(key)
    if loc then
        local can = a.GetAvailablePostCount(loc)
        if type(can) == "number" and can < n then n = math.max(0, can) end
    end
    return n
end

function Post.Kind(key)
    local loc = location(key)
    local a = api()
    if not loc or not (a and a.GetItemCommodityStatus) then return nil end
    local status = a.GetItemCommodityStatus(loc)
    local E = Enum and Enum.ItemCommodityStatus
    local commodity, item = E and E.Commodity or 2, E and E.Item or 1
    if status == commodity then return "commodity" end
    if status == item then return "item" end
    return nil
end

function Post.Deposit(key, qty, hours)
    local a = api()
    if not a or type(qty) ~= "number" or qty < 1 then return nil end
    local d = Post.Index(hours)
    local kind = Post.Kind(key)
    local v
    if kind == "commodity" and a.CalculateCommodityDeposit then
        v = a.CalculateCommodityDeposit(ns.Items.ID(key), d, qty)
    elseif kind == "item" and a.CalculateItemDeposit then
        local loc = location(key)
        v = loc and a.CalculateItemDeposit(loc, d, qty)
    end
    return type(v) == "number" and v or nil
end

-- What one of your commodity auctions paid to go up, lost on a cancel. Only
-- known for a 24 h post: more than 8 h left can't be a shorter one. Gear needs
-- the item in the bags to price, so it gives nil, as does anything unknown.
Post.LONG_LEFT = 8 * 3600
function Post.PaidDeposit(itemID, qty, left)
    local a = api()
    if not (a and a.CalculateCommodityDeposit) or type(itemID) ~= "number" or type(qty) ~= "number" then return nil end
    if type(left) ~= "number" or left <= Post.LONG_LEFT then return nil end
    local v = a.CalculateCommodityDeposit(itemID, Post.Index(24), qty)
    return type(v) == "number" and v > 0 and v or nil
end

-- The events that end a post of `qty` of `kind`.
local function postEvents(kind, qty)
    local events = {
        AUCTION_HOUSE_SHOW_ERROR = function(code) return false, "failed", (ns.AH.ErrorText(code)) end,
        -- nothing went out: the game's popup with OK only, no second click
        AUCTION_HOUSE_POST_ERROR = function() return false, "failed", ns.AH.Words(_G.AUCTION_POSTING_ERROR_TEXT) end,
    }
    if kind == "item" and qty > 1 then
        events.AUCTION_MULTISELL_UPDATE = function(made, total)
            if type(made) == "number" and type(total) == "number" and made >= total then return true end
        end
        events.AUCTION_MULTISELL_FAILURE = function() return false, "failed" end
    else
        events.AUCTION_HOUSE_AUCTION_CREATED = function() return true end
    end
    return events
end

local function call(p, confirming)
    local a = api()
    local d = Post.Index(p.hours)
    if p.kind == "commodity" then
        local fn = confirming and a.ConfirmPostCommodity or a.PostCommodity
        return fn(p.loc, d, p.qty, p.unit)
    end
    local fn = confirming and a.ConfirmPostItem or a.PostItem
    return fn(p.loc, d, p.qty, p.bid, p.unit)
end

local function act(p, confirming)
    local asked, sending, early = false, true, nil   -- early: the game's error inside the call
    local ok, why = ns.AH.Act({
        name = confirming and "post confirm" or "post",
        timeout = Post.TIMEOUT + (p.kind == "item" and math.max(0, p.qty - 1) or 0),
        events = postEvents(p.kind, p.qty),
        send = function()
            if call(p, confirming) == true and not confirming then
                asked = not early
                return "answered"   -- nothing went out: the game wants a second click
            end
            if early then return end
            sent = { key = p.key, n = p.kind == "commodity" and p.qty or 1, at = GetTime(), wait = Post.TIMEOUT + p.qty }
        end,
        onDone = function(ok, reason, detail)
            if asked then return end
            if sending and not ok then
                early = { reason, detail }
                return
            end
            if p.onDone then ns.SafeCall(p.onDone, ok, reason, detail) end
        end,
    })
    sending = false
    if not ok then return false, why end
    if early then return false, early[1], early[2] end
    if asked then
        warned = p
        return false, "confirm"
    end
    return true
end

function Post.Send(key, qty, unit, hours, onDone, bid)
    if type(key) ~= "string" or type(qty) ~= "number" or type(unit) ~= "number" then
        error("ns.Post.Send needs a price key, a quantity and a unit price", 2)
    end
    warned = nil
    if not ns.AH.IsOpen() then return false, "closed" end
    unit = math.floor(unit)
    if unit < 1 then return false, "price" end
    local loc, bag, slot = location(key)
    if not loc then return false, "nobags" end
    if qty < 1 or qty > Post.Most(key) then return false, "count" end
    local kind = Post.Kind(key)
    if not kind then return false, "unknown" end
    bid = type(bid) == "number" and math.floor(bid) or nil
    if bid and (bid < 1 or bid >= unit) then bid = nil end
    local step = Post.Step(kind, key)
    if unit % step ~= 0 or (bid and bid % step ~= 0) then return false, "silver" end
    return act({ key = key, qty = qty, unit = unit, hours = hours, kind = kind, loc = loc, bag = bag, slot = slot,
        onDone = onDone, bid = bid }, false)
end

function Post.Confirm()
    local p = warned
    if not p then return false, "nothing" end
    warned = nil
    if ns.Bags.KeyAt(p.bag, p.slot) ~= p.key then return false, "moved" end
    local ok, why, detail = act(p, true)
    if not ok and why ~= "closed" and why ~= "failed" then warned = p end   -- busy or throttled: the next click can try again
    return ok, why, detail
end

function Post.Warned()
    local p = warned
    if p then return { key = p.key, qty = p.qty, unit = p.unit, hours = p.hours } end
end

function Post.Forget() warned = nil end

-- ---------------------------------------------------------------------
-- Your auctions
-- ---------------------------------------------------------------------

local function readOwned()
    local a = api()
    local list = {}
    local n = tonumber(a.GetNumOwnedAuctions and a.GetNumOwnedAuctions()) or 0
    local SOLD = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
    for i = 1, n do
        local r = a.GetOwnedAuctionInfo(i)
        if type(r) == "table" and type(r.auctionID) == "number" then
            local id = type(r.itemKey) == "table" and r.itemKey.itemID or nil
            local key = ns.Items.RowKey(r.itemKey, r.itemLink)
            local qty = tonumber(r.quantity) or 1
            -- An owned auction's buyoutAmount is the price of ONE (Auctionator's Cancelling.lua
            -- 242-244 multiplies it by the quantity for its total on sale), but a SOLD one's is
            -- the whole sale (seen in game: 9 sold for 70s 11c read 6g 30s 99c).
            local sold = r.status == SOLD
            local unit = tonumber(r.buyoutAmount)
            if unit and unit <= 0 then unit = nil end
            local total = unit and (sold and unit or unit * qty) or nil
            if unit and sold then unit = unit / qty end
            list[#list + 1] = {
                auctionID = r.auctionID, key = key, itemID = id or ns.Items.ID(key), link = r.itemLink, qty = qty,
                buyout = total, unit = unit,
                bid = tonumber(r.bidAmount) or 0, sold = sold,
                left = not sold and tonumber(r.timeLeftSeconds) or nil,
            }
        end
    end
    return list
end

-- A read already asked for answers everyone who asks meanwhile: one request.
local ownedWait, bidsWait

function Post.Owned(onDone)
    local a = api()
    if not (a and a.QueryOwnedAuctions) then
        if onDone then ns.SafeCall(onDone, nil, "error") end
        return false, "error"
    end
    if ownedWait then
        ownedWait[#ownedWait + 1] = onDone
        return true
    end
    local waiting = { onDone }
    ownedWait = waiting
    local ok = ns.AH.Request({
        name = "owned auctions",
        events = { OWNED_AUCTIONS_UPDATED = function() return true end },
        send = function() a.QueryOwnedAuctions({}) end,
        onDone = function(done, reason)
            if ownedWait == waiting then ownedWait = nil end
            if done then
                mine = readOwned()
                readAt = GetTime()
                ns.Fire("OwnedChanged")
            end
            for i = 1, table.maxn(waiting) do
                local fn = waiting[i]
                if fn then ns.SafeCall(fn, done and mine or nil, not done and reason or nil) end
            end
        end,
    })
    if not ok then return false, "closed" end
    return true
end

function Post.Mine() return mine end
function Post.ReadAt() return readAt end
-- The auctions you bid on (the game's Bids list). high: you're the highest
-- bidder; minBid is the least the next bid can be.
local bids = {}
local function readBids()
    local a = api()
    local list = {}
    local me = UnitGUID and UnitGUID("player")
    if issecretvalue and issecretvalue(me) then me = nil end
    local n = tonumber(a.GetNumBids and a.GetNumBids()) or 0
    for i = 1, n do
        local r = a.GetBidInfo(i)
        if type(r) == "table" and type(r.auctionID) == "number" then
            local id = type(r.itemKey) == "table" and r.itemKey.itemID or nil
            local key = ns.Items.RowKey(r.itemKey, r.itemLink)
            local buyout = tonumber(r.buyoutAmount)
            if buyout and buyout <= 0 then buyout = nil end
            list[#list + 1] = {
                auctionID = r.auctionID, key = key, itemID = id or ns.Items.ID(key), link = r.itemLink, qty = 1,
                bid = tonumber(r.bidAmount) or 0, minBid = tonumber(r.minBid) or 0, buyout = buyout, unit = buyout,
                band = r.timeLeft, high = me ~= nil and r.bidder == me,
            }
        end
    end
    return list
end

function Post.Bids(onDone)
    local a = api()
    if not (a and a.QueryBids) then
        if onDone then ns.SafeCall(onDone, nil, "error") end
        return false, "error"
    end
    if bidsWait then
        bidsWait[#bidsWait + 1] = onDone
        return true
    end
    local waiting = { onDone }
    bidsWait = waiting
    local ok = ns.AH.Request({
        name = "bids",
        events = { BIDS_UPDATED = function() return true end },
        send = function() a.QueryBids({}, {}) end,
        onDone = function(done, reason)
            if bidsWait == waiting then bidsWait = nil end
            if done then
                bids = readBids()
                bidsRead = true
                ns.Fire("OwnedChanged")
            end
            for i = 1, table.maxn(waiting) do
                local fn = waiting[i]
                if fn then ns.SafeCall(fn, done and bids or nil, not done and reason or nil) end
            end
        end,
    })
    if not ok then return false, "closed" end
    return true
end

function Post.MyBids() return bids end


-- The price key of one of your auctions by its ID, for the ledger: the
-- owned list read last, else what the client says of it (GetAuctionInfoByID,
-- a GUESS that it knows a new auction), else the item Daylight UI's own post was
-- sending a moment ago (a new auction isn't in the owned list yet). Nil when
-- none says.
function Post.KeyOf(auctionID)
    if type(auctionID) ~= "number" then return nil end
    for _, r in ipairs(mine) do
        if r.auctionID == auctionID and r.key then return r.key end
    end
    local a = api()
    if a and a.GetAuctionInfoByID then
        local info = a.GetAuctionInfoByID(auctionID)
        if type(info) == "table" then
            local key = ns.Items.RowKey(info.itemKey, info.itemLink)
            if key then return key end
        end
    end
    if sent and GetTime() - sent.at <= sent.wait then return sent.key end
    return nil
end

-- How many units one of your auctions holds, for the ledger (a commodity
-- auction sells in parts): the post Daylight UI sent a moment ago, else the owned
-- list read last, else 1.
function Post.CountOf(auctionID)
    if type(auctionID) ~= "number" then return 1 end
    if sent and GetTime() - sent.at <= sent.wait and sent.key == Post.KeyOf(auctionID) then return sent.n or 1 end
    for _, r in ipairs(mine) do
        if r.auctionID == auctionID and type(r.qty) == "number" and r.qty > 0 then return r.qty end
    end
    return 1
end

function Post.Up(key)
    local n = 0
    for _, r in ipairs(mine) do
        if r.key == key and not r.sold then n = n + r.qty end
    end
    return n
end

function Post.MineLow(key)
    local low
    for _, r in ipairs(mine) do
        if r.key == key and not r.sold and type(r.unit) == "number" and (not low or r.unit < low) then low = r.unit end
    end
    return low
end

function Post.CancelCost(auctionID)
    local a = api()
    if not (a and a.GetCancelCost) then return 0 end
    local v = a.GetCancelCost(auctionID)
    if (issecretvalue and issecretvalue(v)) or type(v) ~= "number" then return 0 end
    return v
end

local function listed(auctionID)
    for _, r in ipairs(mine) do if r.auctionID == auctionID and not r.sold then return true end end
    return false
end

function Post.Cancel(auctionID, onDone)
    if not listed(auctionID) then return false, "notmine" end
    local function finish(ok, reason, detail)
        if ok then
            for i, r in ipairs(mine) do
                if r.auctionID == auctionID then table.remove(mine, i); break end
            end
            ns.Fire("OwnedChanged")
        end
        if onDone then ns.SafeCall(onDone, ok, reason, detail) end
    end
    cancelling = true
    local ok, why = ns.AH.Act({
        name = "cancel",
        send = function() api().CancelAuction(auctionID) end,
        events = {
            -- Only one cancel is ever out, so a cancel answer is ours: Forever's may
            -- not carry this auction's ID (the game's own window never reads it).
            -- One naming another of your auctions is that one selling, not ours.
            AUCTION_CANCELED = function(id)
                if type(id) == "number" and not (issecretvalue and issecretvalue(id)) and id ~= 0 and id ~= auctionID then
                    for _, r in ipairs(mine) do if r.auctionID == id then return end end
                end
                return true
            end,
            AUCTION_HOUSE_SHOW_ERROR = function(code) return false, "failed", (ns.AH.ErrorText(code)) end,
        },
        onDone = function(ok, reason, detail)
            cancelling = false
            if reason ~= "timeout" then return finish(ok, reason, detail) end
            -- No answer: the owned list says whether it went.
            local asking, why = Post.Owned(function(list)
                if list and not listed(auctionID) then return finish(true) end
                if onDone then ns.SafeCall(onDone, false, "timeout") end
            end)
            if not asking and why == "closed" and onDone then ns.SafeCall(onDone, false, "timeout") end
        end,
    })
    if not ok then cancelling = false end
    return ok, why
end

-- One read of the list (and the bids, once read) after something changed it,
-- however many events say so.
local rereading = false
local function reread()
    if rereading or not ns.AH.IsOpen() then return end
    rereading = true
    C_Timer.After(0.1, function()
        rereading = false
        if not ns.AH.IsOpen() then return end
        Post.Owned()
        if bidsRead then Post.Bids() end
    end)
end

-- What changes your auctions while the Auction House is open: a sale (the game
-- says AUCTION_CANCELED for one of yours that sold) or a bid.
local watch = CreateFrame("Frame")
watch:SetScript("OnEvent", function(_, event, id)
    if event == "AUCTION_CANCELED" then
        if cancelling then return end   -- a cancel of Daylight UI's: it reads the list itself
        if issecretvalue and issecretvalue(id) then return reread() end
        if type(id) == "number" and id ~= 0 then
            local ours = false
            for _, r in ipairs(mine) do if r.auctionID == id then ours = true; break end end
            if not ours then return end
        end
    end
    reread()
end)

ns.On("AHOpened", function()
    if ns.mogul then return end
    watch:RegisterEvent("AUCTION_CANCELED")
    watch:RegisterEvent("AUCTION_HOUSE_NEW_BID_RECEIVED")
    -- read now, so My auctions and Sell's "yours" know it when they show
    if not Post.OPEN_READ then return end
    C_Timer.After(Post.OPEN_READ, function()
        if ns.AH.IsOpen() and not readAt then Post.Owned() end
    end)
end)

ns.On("AHClosed", function()
    warned = nil
    readAt, cancelling, bidsRead, ownedWait, bidsWait = nil, false, false, nil, nil
    watch:UnregisterAllEvents()
end)
