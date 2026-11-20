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

-- What one sells for at the Auction House: its usual price, else the
-- cheapest one last seen; then when it was last seen. Nil when never seen.
function Bridge.Item(itemID)
    local rkey = ns.Ruleset.Key()
    local key = rkey and ns.Items.Key(itemID)
    if not key then return nil end
    local now = ns.Game.Now()
    local price = ns.Store.Market(rkey, key, now) or ns.Store.Min(rkey, key)
    if not price then return nil end
    return price, ns.Store.SeenAt(rkey, key)
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
