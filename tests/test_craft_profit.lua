local stub = require("stub")
local PW = require("craftworld")
local AHW = require("ahworld")

-- Profit in the profession window: material and sale prices from the Auction
-- House addon (DaylightUI.AuctionPrices), vendor prices learned at a merchant.

local NOW = 1700000000
local SILK, BOLT, THREAD, HOOD = 4306, 4305, 2321, 7048
local LINEN, LINEN_BOLT = 2589, 2996

local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end

-- The profession window with the Auction House addon on (ah = false: off).
local function load(opts)
    opts = opts or {}
    local before = function()
        stub.SetTime(NOW)
        PW.world(opts.craft or {})()
    end
    if opts.ah == false then
        stub.Load({ before = before })
        return stub.craft, nil
    end
    local _, A = AHW.Load(nil, { before = before })
    return stub.craft, A
end

local function price(A, itemID, copper)
    A.Store.Record("US-PvE", tostring(itemID), copper, 20, NOW)
end

-- A merchant opening, selling the items given as { itemID, price, stack }.
local function merchant(rows)
    _G.GetMerchantNumItems = function() return #rows end
    _G.GetMerchantItemLink = function(i) return "|cffffffff|Hitem:" .. rows[i][1] .. "::::::::|h[x]|h|r" end
    _G.C_MerchantFrame = _G.C_MerchantFrame or {}
    _G.C_MerchantFrame.GetItemInfo = function(i)
        local r = rows[i]
        return r and { name = "x", price = r[2], stackCount = r[3] or 1, hasExtendedCost = r[4] == true }
    end
    stub.FireEvent("MERCHANT_SHOW")
end

local function open(ns)
    PW.Open(197)
    frame(20)
    return ns.Window.frame.pages.recipes
end

local function recipe(ns, id) return ns.List.data.byID[id] end

local function profitPiece(page)
    for _, b in ipairs(page.recipe.stack.used) do
        if b:IsShown() and b.rows and b.recipeID then return b end
    end
    return nil
end

local function rowTexts(b)
    local out = {}
    for _, row in ipairs(b.rows) do
        if row:IsShown() then out[#out + 1] = row.label:GetText() end
    end
    return table.concat(out, ", ")
end

T.test("craft profit: materials, sale, cut and profit per craft", function()
    local ns, A = load()
    price(A, SILK, 50)
    price(A, BOLT, 300)
    open(ns)
    local p = ns.Profit.Of(recipe(ns, 102))
    T.eq(p.cost, 200)
    T.eq(p.value, 300)
    T.eq(p.cut, 15)
    T.eq(p.profit, 85)
    T.eq(p.pct, 43)
    T.eq(p.why, nil)
end)

T.test("craft profit: a price seen today wins over the usual one", function()
    local ns, A = load()
    price(A, SILK, 50)
    -- The bolt sold for 600 most of the last week, and 300 today.
    for d = 1, 6 do A.Store.Record("US-PvE", tostring(BOLT), 600, 20, NOW - d * 86400) end
    price(A, BOLT, 300)
    open(ns)
    local p = ns.Profit.Of(recipe(ns, 102))
    T.eq(p.value, 300)
end)

T.test("craft profit: an old sighting falls back to the usual price", function()
    local ns, A = load()
    price(A, SILK, 50)
    for d = 2, 7 do A.Store.Record("US-PvE", tostring(BOLT), 600, 20, NOW - d * 86400) end
    A.Store.Record("US-PvE", tostring(BOLT), 300, 20, NOW - 86400)
    open(ns)
    local p = ns.Profit.Of(recipe(ns, 102))
    T.eq(p.value, 600)
end)

T.test("craft profit: a vendor price is learned at a merchant and used", function()
    local ns, A = load()
    price(A, BOLT, 300)
    price(A, HOOD, 1000)
    price(A, SILK, 50)
    merchant({ { THREAD, 500, 5 }, { 9999, 100, 1, true } })
    T.eq(A.Vendor.Price(THREAD), 100)
    T.eq(A.Vendor.Price(9999), nil, "bought with something else: skipped")
    open(ns)
    local p = ns.Profit.Of(recipe(ns, 101))
    T.eq(p.mats[2].src, "vendor")
    -- Making a bolt (200) is cheaper than buying one (300).
    T.eq(p.mats[1].src, "craft")
    T.eq(p.mats[1].each, 200)
    T.eq(p.cost, 2 * 200 + 2 * 100)
    T.eq(p.profit, 1000 - 50 - 600)
    T.truthy(p.why:find("making it costs", 1, true), p.why)
end)

T.test("craft profit: a missing price says which, and shows no profit", function()
    local ns, A = load()
    price(A, BOLT, 300)
    open(ns)
    local p = ns.Profit.Of(recipe(ns, 101))
    T.eq(p.cost, nil)
    T.eq(p.profit, nil)
    T.eq(p.value, nil)
    T.truthy(p.why:find("Fine Thread", 1, true), p.why)
    T.truthy(p.why:find("Azure Silk Hood", 1, true), p.why)
end)

T.test("craft profit: a recipe making more than one prices the whole craft", function()
    local spec = { profs = PW.Sample() }
    spec.profs[1].recipes[2].yield = { 1, 3 }
    local ns, A = load({ craft = spec })
    price(A, SILK, 50)
    price(A, BOLT, 300)
    open(ns)
    local p = ns.Profit.Of(recipe(ns, 102))
    T.eq(p.yield, 2)
    -- One craft's materials against both items it makes, never one item's share.
    T.eq(p.cost, 200)
    T.eq(p.each, 300)
    T.eq(p.value, 600)
    T.eq(p.cut, 30)
    T.eq(p.profit, 600 - 30 - 200)
    T.truthy(p.why:find("whole craft", 1, true), p.why)
end)

T.test("craft profit: the recipe side shows a Profit section", function()
    local ns, A = load()
    price(A, SILK, 50)
    price(A, BOLT, 300)
    local page = open(ns)
    ns.Window.Pick(102)
    frame(5)
    local b = profitPiece(page)
    T.truthy(b, "profit piece")
    T.eq(rowTexts(b), "Materials, Sells for, Auction House cut, Profit")
    local last = b.rows[4]
    local INK = DaylightUI.Style.INK
    local r, g = last.value:GetTextColor()
    T.deq({ r, g }, { INK.GOOD[1], INK.GOOD[2] }, "a gain is green")
    T.truthy(last.value:GetText():find("^%+"), last.value:GetText())
end)

T.test("craft profit: no prices anywhere, no section and no chip", function()
    local ns = load({ ah = false })
    local page = open(ns)
    ns.Window.Pick(102)
    frame(5)
    T.eq(DaylightUI.AuctionPrices, nil)
    T.eq(ns.Profit.Of(recipe(ns, 102)), nil)
    T.eq(profitPiece(page), nil)
    T.eq(page.list.profit:IsShown(), false)
end)

T.test("craft profit: switched off in the options, nothing shows", function()
    local ns, A = load({ craft = { profit = false } })
    price(A, SILK, 50)
    price(A, BOLT, 300)
    DaylightUI:Set("Professions", "profit", false)
    local page = open(ns)
    ns.Window.Pick(102)
    frame(5)
    T.eq(ns.Profit.Of(recipe(ns, 102)), nil)
    T.eq(profitPiece(page), nil)
    T.eq(page.list.profit:IsShown(), false)
end)

T.test("craft profit: every row shows its profit beside the materials", function()
    local ns, A = load()
    price(A, SILK, 50)
    price(A, BOLT, 300)        -- silk bolt: 85 profit
    price(A, LINEN, 10)
    price(A, LINEN_BOLT, 500)  -- linen bolt: 455 profit
    open(ns)
    local line = ns.List.lines[104]
    T.truthy(line.profit and line.profit:IsShown(), "profit shown")
    T.truthy(line.profit:GetText():find("^%+"), line.profit:GetText())
    T.eq(line.sub:GetText(), recipe(ns, 104).sub, "materials stay")
end)

T.test("craft profit: a row with no price shows no profit", function()
    local ns = load()
    open(ns)
    local line = ns.List.lines[104]
    T.truthy(not (line.profit and line.profit:IsShown()), "nothing to show")
end)

T.test("craft profit: the Profit chip puts the best first", function()
    local ns, A = load()
    price(A, SILK, 50)
    price(A, BOLT, 300)        -- silk bolt: 85 profit
    price(A, LINEN, 10)
    price(A, LINEN_BOLT, 500)  -- linen bolt: 455 profit
    local page = open(ns)
    local function order()
        local ids = {}
        for _, id in ipairs(ns.List.order) do if id == 102 or id == 104 then ids[#ids + 1] = id end end
        return ids
    end
    T.deq(order(), { 102, 104 }, "the game's order")
    page.list.profit:Click()
    frame(5)
    T.deq(order(), { 104, 102 })
    T.eq(ns.List.lines[104].sub:GetText(), recipe(ns, 104).sub, "materials stay")
    page.list.profit:Click()
    frame(5)
    T.deq(order(), { 102, 104 })
    T.eq(ns.List.lines[104].sub:GetText(), recipe(ns, 104).sub)
end)

T.test("craft profit: new prices repaint the open window", function()
    local ns, A = load()
    price(A, SILK, 50)
    local page = open(ns)
    ns.Window.Pick(102)
    frame(5)
    T.eq(rowTexts(profitPiece(page)), "Materials")
    price(A, BOLT, 300)
    A.Fire("PricesChanged", "US-PvE")
    frame(3)
    T.eq(rowTexts(profitPiece(page)), "Materials, Sells for, Auction House cut, Profit")
end)
