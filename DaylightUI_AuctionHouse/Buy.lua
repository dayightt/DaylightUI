-- Buy: buying at the Auction House. A commodity takes two clicks (the first
-- asks the game for a price quote, the second confirms what the player saw);
-- gear and bids take one. Every purchase goes through ns.AH.Act, inside the
-- player's click (the game allows them only then), one at a time.
--
--   ns.Buy.Commodity(itemID, qty, unit, onQuote(unit, total), onDone(ok, reason)) -> ok, reason
--       StartCommoditiesPurchase(itemID, qty, unit). `unit` in and out is the AVERAGE,
--       total / qty floored (the game's source: SetQuantitySelected passes
--       totalPrice / totalQuantity, and its dialog compares updatedUnitPrice with
--       currentTotalPrice / quantity). onQuote runs for the game's price
--       (COMMODITY_PRICE_UPDATED) and again when it moves while the player looks.
--       The quote waits (line free) for Confirm or Cancel, and goes stale after
--       C_AuctionHouse.GetQuoteDurationRemaining() reaches 0.
--   ns.Buy.Confirm(seenTotal) -> ok, reason   the quoted purchase (ConfirmCommoditiesPurchase);
--       seenTotal is the total the player was looking at: a different quote now
--       (it moved) is refused, nothing sent, false, "moved"; a stale one (the
--       quote duration ran out, when the game can say) ends it "expired" (nothing
--       sent, false, "expired", and onDone(false, "expired")).
--       onDone(true) on COMMODITY_PURCHASE_SUCCEEDED, (false, "failed") on _FAILED
--       and ns.Fire("CommodityBought", itemID, qty) with it, or when a confirm that ended
--       "timeout" or "closed" lands late (LATE seconds): the game took the gold anyway
--   ns.Buy.Cancel()                     drops the quote (CancelCommoditiesPurchase);
--       onDone(false, "canceled"). The AH closing does the same with "closed".
--       A quote or confirm that ends "timeout", "failed", "unavailable", "expired" or "error"
--       also cancels the game's held quote, as its dialog does on hide.
--   ns.Buy.Item(auctionID, buyout, onDone) -> ok, reason   PlaceBid(auctionID, buyout);
--       done on AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID), "failed" on AUCTION_HOUSE_SHOW_ERROR
--   ns.Buy.Bid(auctionID, amount, buyout, onDone) -> ok, reason   PlaceBid(auctionID, amount);
--       buyout is the auction's (0 = none): an amount at or over it would BUY the
--       auction, so it is refused (false, "buyout": use Buy.Item). Done on BID_ADDED
--       (a GUESS: the docs' event; the game's bid popup listens for nothing), or
--       AUCTION_HOUSE_PURCHASE_COMPLETED for that auction (a stale buyout), "failed" on
--       AUCTION_HOUSE_SHOW_ERROR.
--   ns.Buy.Pending() -> "quote" | "confirm" | "item" | "bid" | nil
--   ns.Buy.Quote() -> unit, total   the held quote the game gave (nil before it came,
--       or with none): what to show again after a Confirm refused "moved"
--   ns.Buy.Check(key, unit) -> warn, pct   the safety net: warn above Buy.Safety() % of the
--       market (or with no market or a unit that isn't a number, then pct is nil);
--       pct = the price as a percent of it.
--
-- Failures (ok false, reason): "closed", "busy" (a search, or another
-- purchase, is out, or a quote is held), "throttled" (from ns.AH.Act, nothing
-- sent), "noquote" (Confirm with no quote), "moved", "expired", "buyout",
-- "gold" (more than you have: nothing sent; a quote stays held for gold to come in).
-- onDone(ok, reason, detail): detail is the game's own words when it gave any
-- (AUCTION_HOUSE_SHOW_ERROR: AH.ErrorText). Reasons: "trouble" (a gear or bid purchase met the server's own error, not
-- another buyer), "unavailable" (the game won't hold the price), "failed"
-- (someone else bought first), "closed", "canceled", "expired", "timeout"
-- (nothing came back: a click the client blocked looks like this, it gives
-- Daylight UI no result), "error". A purchase that was sent is never retried.

local _, ns = ...

local Buy = {}
ns.Buy = Buy

Buy.SAFETY = 150   -- a price above this % of the usual one asks for a second look

-- The player's own limit from the options, Buy.SAFETY until the settings are read.
function Buy.Safety()
    local v = ns.Setting and ns.Setting("askAbove")
    return type(v) == "number" and v * 100 or Buy.SAFETY
end

Buy.LATE = 60   -- seconds a confirm that lost its answer can still land

local cur   -- the purchase under way: { kind, itemID, qty, unit, total, quoted, onQuote, onDone }
local lost  -- a confirm that lost its answer: { itemID, qty, at }

-- Enough gold for `copper`? True when the game doesn't say.
local function afford(copper)
    if type(copper) ~= "number" or not GetMoney then return true end
    local have = GetMoney()
    if issecretvalue and issecretvalue(have) then return true end
    return type(have) ~= "number" or have >= copper
end

-- The server's error for a purchase: another buyer's, or its own trouble, and the game's words.
local function shownError(code)
    local words, server = ns.AH.ErrorText(code)
    return false, server and "trouble" or "failed", words
end

-- Ends a purchase once: whoever gets there first (an answer, a timeout, the
-- AH closing, Cancel) tells the caller, the rest find it gone.
local CANCELS = { timeout = true, failed = true, unavailable = true, expired = true, error = true }

-- Tells the game to let go of a held quote (when the window is open).
local function dropQuote()
    local api = C_AuctionHouse
    if ns.AH.IsOpen() and api and api.CancelCommoditiesPurchase then api.CancelCommoditiesPurchase() end
end

local function finish(p, ok, reason, detail)
    if cur ~= p then return end
    cur = nil
    if p.itemID and CANCELS[reason] then dropQuote() end
    if p.onDone then ns.SafeCall(p.onDone, ok, reason, detail) end
end

function Buy.Pending()
    return cur and cur.kind or nil
end

function Buy.Quote()
    local p = cur
    if p and p.kind == "quote" and p.quoted then return p.unit, p.total end
end

function Buy.Check(key, unit)
    local rkey = ns.Ruleset.Key()
    local market = rkey and ns.Store.Market(rkey, key, ns.Game.Now())
    if type(unit) ~= "number" or type(market) ~= "number" or market <= 0 then return true, nil end
    local over = unit * 100 > market * Buy.Safety()
    if ns.Setting and ns.Setting("askHigh") == false then over = false end
    return over, math.floor(unit * 100 / market + 0.5)
end

function Buy.Commodity(itemID, qty, unit, onQuote, onDone)
    if cur then return false, "busy" end
    if type(itemID) ~= "number" or type(qty) ~= "number" or qty < 1 then
        error("ns.Buy.Commodity needs an itemID and a quantity", 2)
    end
    if type(unit) == "number" and not afford(unit * qty) then return false, "gold" end
    local p = { kind = "quote", itemID = itemID, qty = qty, unit = unit, onQuote = onQuote, onDone = onDone }
    cur = p
    local ok, why = ns.AH.Act({
        name = "buy quote",
        send = function() C_AuctionHouse.StartCommoditiesPurchase(itemID, qty, unit) end,
        events = {
            COMMODITY_PRICE_UPDATED = function(newUnit, total)
                if cur ~= p then return true end   -- canceled on its way: nobody to tell
                p.unit, p.total, p.quoted = newUnit, total, true
                if p.onQuote then ns.SafeCall(p.onQuote, newUnit, total) end
                return true   -- the line is free again; the quote waits on the player
            end,
            COMMODITY_PRICE_UNAVAILABLE = function() return false, "unavailable" end,
            AUCTION_HOUSE_SHOW_ERROR = shownError,
        },
        onDone = function(done, reason, detail)
            if not done then finish(p, false, reason, detail) end
        end,
    })
    if not ok then
        if cur == p then cur = nil end
        return false, why
    end
    return true
end

-- The price moved while the player looks (the game's dialog listens too), or
-- the game can no longer hold it.
-- (ns.RegisterEvent handlers get the event's name first.)
ns.RegisterEvent("COMMODITY_PRICE_UPDATED", function(_, unit, total)
    local p = cur
    if not (p and p.kind == "quote" and p.quoted) then return end
    if p.unit == unit and p.total == total then return end   -- the first quote, already told
    p.unit, p.total = unit, total
    if p.onQuote then ns.SafeCall(p.onQuote, unit, total) end
end)

ns.RegisterEvent("COMMODITY_PRICE_UNAVAILABLE", function()
    local p = cur
    if not (p and p.kind == "quote" and p.quoted) then return end
    finish(p, false, "unavailable")
end)

function Buy.Confirm(seenTotal)
    local p = cur
    if not p then return false, "noquote" end
    if p.kind ~= "quote" then return false, "busy" end
    if not p.quoted then return false, "busy" end   -- the quote is still on its way
    if p.total ~= seenTotal then return false, "moved" end
    if not afford(p.total) then return false, "gold" end
    local api = C_AuctionHouse
    if api and api.GetQuoteDurationRemaining then
        local left = api.GetQuoteDurationRemaining()
        if type(left) == "number" and left <= 0 then
            finish(p, false, "expired")
            return false, "expired"
        end
    end
    p.kind = "confirm"
    lost = nil   -- only the newest purchase can land
    local ok, why = ns.AH.Act({
        name = "buy confirm",
        send = function() C_AuctionHouse.ConfirmCommoditiesPurchase(p.itemID, p.qty) end,
        events = {
            COMMODITY_PURCHASE_SUCCEEDED = function() return true end,
            COMMODITY_PURCHASE_FAILED = function() return false, "failed" end,
            AUCTION_HOUSE_SHOW_ERROR = shownError,
        },
        onDone = function(done, reason, detail)
            -- what we bought, for Stock: the game's COMMODITY_PURCHASED didn't always come in play
            if done then ns.Fire("CommodityBought", p.itemID, p.qty) end
            if reason == "timeout" or reason == "closed" then
                lost = { itemID = p.itemID, qty = p.qty, at = GetTime() }
            end
            finish(p, done, reason, detail)
        end,
    })
    if not ok then
        if cur == p then p.kind = "quote" end
        return false, why
    end
    return true
end

-- A confirm that lost its answer and lands after all.
ns.RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
    local l = lost
    lost = nil
    if l and GetTime() - l.at <= Buy.LATE then ns.Fire("CommodityBought", l.itemID, l.qty) end
end)

function Buy.Cancel()
    local p = cur
    if not (p and p.kind == "quote") then return end
    dropQuote()
    finish(p, false, "canceled")
end

-- One click, one PlaceBid.
local function place(kind, auctionID, amount, onDone)
    if cur then return false, "busy" end
    if not afford(amount) then return false, "gold" end
    local p = { kind = kind, onDone = onDone }
    cur = p
    local events = {
        AUCTION_HOUSE_PURCHASE_COMPLETED = function(id)
            if id ~= auctionID then return end   -- another auction's
            return true   -- a buyout (or a bid that reached it) is a purchase
        end,
        AUCTION_HOUSE_SHOW_ERROR = shownError,
    }
    if kind == "bid" then events.BID_ADDED = function() return true end end
    local ok, why = ns.AH.Act({
        name = "buy " .. kind,
        send = function() C_AuctionHouse.PlaceBid(auctionID, amount) end,
        events = events,
        onDone = function(done, reason, detail) finish(p, done, reason, detail) end,
    })
    if not ok then
        if cur == p then cur = nil end
        return false, why
    end
    return true
end

function Buy.Item(auctionID, buyout, onDone)
    return place("item", auctionID, buyout, onDone)
end

function Buy.Bid(auctionID, amount, buyout, onDone)
    if type(buyout) == "number" and buyout > 0 and type(amount) == "number" and amount >= buyout then
        return false, "buyout"
    end
    return place("bid", auctionID, amount, onDone)
end

-- A quote the player was looking at ends with the window (a request still in
-- flight is failed "closed" by ns.AH itself, first).
ns.On("AHClosed", function()
    if cur then finish(cur, false, "closed") end
end)
