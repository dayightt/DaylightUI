-- The prices this addon knows, handed to the rest of Daylight UI through
-- DaylightUI.AuctionPrices (the profession window works out profits with
-- them). Set at login unless DaylightMogul owns the Auction House; with this
-- addon switched off it's never set, and the profession window shows no
-- profit. "AuctionPricesChanged" tells the rest when prices move.

local _, ns = ...

local Bridge = {}
ns.Bridge = Bridge

-- The Auction House's share of a sale (the Sell tab's guess).
Bridge.CUT = ns.SellPage and ns.SellPage.CUT or 0.05

-- What one sells for at the Auction House, then when it was last seen; nil
-- when never seen. A price seen in the last few hours (a scan before going to
-- craft) is what the market is now, so it wins; an older one is only a guess,
-- so the usual price over the last days is used instead. Hours rather than
-- the calendar day: the day turns over in the middle of an evening's play.
Bridge.FRESH = 12 * 3600

function Bridge.Item(itemID)
    local rkey = ns.Ruleset.Key()
    local key = rkey and ns.Items.Key(itemID)
    if not key then return nil end
    local now = ns.Game.Now()
    local seen = ns.Store.SeenAt(rkey, key)
    local fresh = seen and now - seen < Bridge.FRESH
    local price = (fresh and ns.Store.Min(rkey, key))
        or ns.Store.Market(rkey, key, now) or ns.Store.Min(rkey, key)
    if not price then return nil end
    return price, ns.Store.SeenAt(rkey, key)
end

-- The same sighting, with how many were for sale: price, seen at, quantity.
-- Price sources outside Daylight UI read this one (a route planner needs the
-- stock as well as the price); nil when the item was never seen.
function Bridge.Offer(itemID)
    local price, at = Bridge.Item(itemID)
    if not price then return nil end
    local rkey = ns.Ruleset.Key()
    local key = rkey and ns.Items.Key(itemID)
    return price, at, key and ns.Store.Qty(rkey, key) or nil
end

-- When anything was last seen at the Auction House: a price source has to say
-- how old its numbers are. Nil before the first scan.
function Bridge.ScannedAt()
    local rkey = ns.Ruleset.Key()
    return rkey and ns.Store.LastAt(rkey) or nil
end

-- What a vendor sells one for, as last seen at a merchant.
function Bridge.Vendor(itemID) return ns.Vendor.Price(itemID) end

-- How long ago a time it gave was, in a few words ("2 h").
function Bridge.Ago(at) return ns.Ago(type(at) == "number" and ns.Game.Now() - at or nil) end

-- A bind-on-pickup item can never be sold.
function Bridge.Soulbound(itemID) return ns.Items.Soulbound(itemID) end

function Bridge.Publish()
    if ns.mogul then return end
    DaylightUI.AuctionPrices = Bridge
    DaylightUI.Fire("AuctionPricesChanged")
end

ns.On("PricesChanged", function() DaylightUI.Fire("AuctionPricesChanged") end)
