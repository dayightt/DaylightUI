-- What a recipe costs to make and what it sells for, from the prices the
-- Auction House addon remembers (DaylightUI.AuctionPrices). Without that addon
-- there are no prices, and the window shows no profit at all.
--
-- A material costs the cheapest of: its Auction House price, what a vendor
-- sells it for, and what making it yourself costs (when the open profession
-- has a recipe for it, a few crafts deep at most, never in a loop). What it
-- sells for is the made item's usual Auction House price, less the Auction
-- House's cut. Everything is per item made, so a craft that makes two halves
-- its cost. Enchants and soulbound items can't be sold: they show only the cost.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L

local Profit = {}
ns.Profit = Profit

Profit.DEPTH = 3   -- crafts deep a made material is followed

local floor = math.floor
local function round(v) return floor(v + 0.5) end

local function source() return DUI.AuctionPrices end

-- True while prices can be read at all.
function Profit.On()
    return source() ~= nil and ns.Setting("profit") ~= false
end

-- Kept until prices change, the day turns (usual prices age) or another
-- profession opens (a different set of recipes can make the materials).
local recipes, mats, makers, stampDay, stampProf = {}, {}, nil, nil, nil

function Profit.Drop()
    recipes, mats, makers = {}, {}, nil
end

local function fresh()
    local day = floor((time and time() or 0) / 86400)
    local data = ns.List and ns.List.data
    local prof = data and data.prof and data.prof.id
    if day ~= stampDay or prof ~= stampProf then
        Profit.Drop()
        stampDay, stampProf = day, prof
    end
end

-- The open profession's learned recipe for each item it makes.
local function makerOf(itemID)
    if not makers then
        makers = {}
        local data = ns.List and ns.List.data
        for id, r in pairs(data and data.byID or {}) do
            local out = not r.enchant and ns.Data.OutputItem(id)
            if out and not makers[out] then makers[out] = r end
        end
    end
    return makers[itemID]
end

local function nameOf(itemID, name)
    if name then return name end
    local got = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if type(got) == "string" and not DUI.IsSecret(got) and got ~= "" then return got end
    return string.format(L["Item %d"], itemID)
end

local matPrice   -- forward

-- What one item of recipe r costs from its materials, nil when one has no price.
local function madeCost(r, chain, depth)
    local sum = 0
    for _, m in ipairs(r.mats) do
        local each = matPrice(m.itemID, chain, depth)
        if not each then return nil end
        sum = sum + each * m.need
    end
    if #r.mats == 0 then return nil end
    return round(sum / ns.Data.Yield(r.id))
end

-- The cheapest price of one material, and where it comes from ("ah", "vendor",
-- "craft"). chain holds the items being priced by making them, so a recipe that
-- makes its own material is never followed into a loop. Only an answer worked
-- out with an empty chain is kept: inside one, a loop changes the answer.
matPrice = function(itemID, chain, depth)
    local top = next(chain) == nil
    local hit = top and mats[itemID]
    if hit then return hit[1], hit[2] end
    local P = source()
    local best, src = P.Item(itemID), "ah"
    if not best then src = nil end
    local vendor = P.Vendor(itemID)
    if vendor and (not best or vendor < best) then best, src = vendor, "vendor" end
    local maker = depth < Profit.DEPTH and not chain[itemID] and makerOf(itemID)
    if maker then
        chain[itemID] = true
        local made = madeCost(maker, chain, depth + 1)
        chain[itemID] = nil
        if made and (not best or made < best) then best, src = made, "craft" end
    end
    if top then mats[itemID] = { best, src } end
    return best, src
end

local function list(names)
    if #names <= 1 then return names[1] or "" end
    local last = table.remove(names)
    return string.format(L["%s and %s"], table.concat(names, ", "), last)
end

local function build(r)
    local P = source()
    local res = { yield = ns.Data.Yield(r.id), mats = {} }
    local sum, missing, crafted = 0, {}, {}
    for i, m in ipairs(r.mats) do
        local each, src = matPrice(m.itemID, {}, 0)
        local name = nameOf(m.itemID, m.name)
        res.mats[i] = { itemID = m.itemID, name = name, n = m.need, each = each, src = src }
        if each then sum = sum + each * m.need else missing[#missing + 1] = name end
        if src == "craft" then crafted[#crafted + 1] = name end
    end
    if #missing == 0 and #r.mats > 0 then res.cost = round(sum / res.yield) end

    local why = {}
    if #missing > 0 then
        why[#why + 1] = string.format(L["No price for %s yet: search the Auction House, or visit a vendor that sells it."], list(missing))
    end
    if #crafted > 0 then
        why[#why + 1] = string.format(L["Priced at what making it costs: %s."], list(crafted))
    end
    if res.yield ~= 1 then
        why[#why + 1] = string.format(L["Makes about %s a craft, so these are for one."], string.format("%g", res.yield))
    end

    local out = ns.Data.OutputItem(r.id)
    if r.enchant or not out then
        res.none = "enchant"
        why[#why + 1] = L["Enchants can't be sold: no profit."]
    elseif P.Soulbound(out) then
        res.none = "bound"
        why[#why + 1] = L["Soulbound: no profit."]
    else
        local value, seenAt = P.Item(out)
        res.out, res.seenAt = out, seenAt
        if not value then
            res.none = "nomarket"
            why[#why + 1] = string.format(L["No price for %s yet: search the Auction House."], nameOf(out, r.name))
        else
            res.value = value
            res.cut = round(value * P.CUT)
            if res.cost then
                res.profit = value - res.cut - res.cost
                if res.cost > 0 then res.pct = round(res.profit / res.cost * 100) end
            end
        end
    end
    res.why = #why > 0 and table.concat(why, " ") or nil
    res.known = res.cost ~= nil or res.value ~= nil
    return res
end

-- r: a recipe from List.data. Nil when there are no prices to read.
function Profit.Of(r)
    if not (r and Profit.On()) then return nil end
    fresh()
    local hit = recipes[r.id]
    if hit then return hit end
    hit = build(r)
    recipes[r.id] = hit
    return hit
end

-- The color a profit is painted in: a gain green, a loss soft red, even gold.
function Profit.Color(profit)
    local INK = DUI.Style.INK
    if profit > 0 then return INK.GOOD end
    if profit < 0 then return INK.DAMAGE end
    return INK.MONEY
end

-- "+75s" / "-12s 40c", digits uncolored (the caller paints the line).
function Profit.Money(profit)
    local text = DUI.Widgets.Money(math.abs(profit), { color = false })
    if profit > 0 then return "+" .. text end
    if profit < 0 then return "-" .. text end
    return text
end

-- Prices moved (a scan, a search, a merchant): drop what's kept and repaint once
-- the burst is over, only while the window shows.
local soon = false
DUI.On("AuctionPricesChanged", function()
    Profit.Drop()
    local shown = ns.List and ns.List.pane
    if soon or not (C_Timer and shown and shown:IsVisible()) then return end
    soon = true
    C_Timer.After(0, function()
        soon = false
        local pane = ns.List and ns.List.pane
        if not (pane and pane:IsVisible()) then return end
        ns.List.Render(pane, true)
        if ns.Window then ns.Window.Refreshed() end
    end)
end)
