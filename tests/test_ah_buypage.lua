local AHW = require("ahworld")
local stub = require("stub")

-- The Buy tab (DaylightUI_AuctionHouse/BuyPage.lua) on the fake auction
-- house, in the window as the game opens it: a search fills one row per item
-- cheapest first, a category browses, a picked commodity opens its price steps
-- and buys in the game's two clicks, gear in one, a price far over usual asks
-- once more, favorites and recent searches are saved, suggestions come from
-- the items seen, and the first-visit card moves the panes down.

local RKEY = "US-PvE"
local RUNECLOTH, BOLT, HELM, SWORD = 14047, 14048, 20001, 2207
local PATTERN_HIGH, PATTERN_LOW = 14468, 4292
local DAY = 86400

-- The game's AuctionHouseFrame as the game drives it (test_ah_window's).
local function gameAH()
    local world = CreateFrame("Frame")
    world:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    world:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    world:SetScript("OnEvent", function(_, event, kind)
        if kind ~= AHW.AUCTIONEER then return end
        local f = rawget(_G, "AuctionHouseFrame")
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            if not f then
                f = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
                f.CloseButton = CreateFrame("Button", nil, f)
                f:Hide()
                f:SetScript("OnHide", function() C_AuctionHouse.CloseAuctionHouse() end)
                stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI")
            end
            f:Show()
        elseif f then
            f:Hide()
        end
    end)
end

-- The game's categories in the shape of Blizzard_AuctionData.lua: a parent's
-- filters hold its children's (AddFilter passes each up).
local function fakeCategories()
    local function f(c, s, i) return { classID = c, subClassID = s, inventoryType = i } end
    _G.TOKEN_FILTER_LABEL = "WoW Token"
    _G.AuctionCategories = {
        { name = "Weapons", filters = { f(2, 7) }, subCategories = { { name = "Swords", filters = { f(2, 7) } } } },
        { name = "Armor", filters = { f(4, 4, 1) }, subCategories = {
            { name = "Plate", filters = { f(4, 4, 1) } } } },
        { name = "Trade Goods", filters = { f(7, 5) }, subCategories = {
            { name = "Cloth", filters = { f(7, 5) } } } },
        { name = "Recipes", filters = { f(9) }, subCategories = {
            { name = "Tailoring", filters = { f(9, 2) } } } },
        { name = "WoW Token", filters = {} },
    }
end

-- The mockup's Runecloth (60 at 1g 05s, 200 at 1g 18s, 340 at 1g 40s), a
-- bolt, a helm at 311% of usual, two swords.
local function auctions()
    return {
        { itemID = RUNECLOTH, name = "Runecloth", count = 60, buyout = 60 * 10500, level = 50, classID = 7, subClassID = 5 },
        { itemID = RUNECLOTH, name = "Runecloth", count = 200, buyout = 200 * 11800, level = 50, classID = 7, subClassID = 5 },
        { itemID = RUNECLOTH, name = "Runecloth", count = 340, buyout = 340 * 14000, level = 50, classID = 7, subClassID = 5 },
        { itemID = BOLT, name = "Bolt of Runecloth", count = 80, buyout = 80 * 65000, level = 55, classID = 7, subClassID = 5 },
        { itemID = HELM, name = "Lionheart Helm", count = 1, buyout = 420000, quality = 4, level = 60, itemLevel = 65,
          classID = 4, subClassID = 4, inventoryType = 1, owner = "Brann" },
        { itemID = SWORD, name = "Short Sword", count = 1, buyout = 9000, quality = 2, level = 10,
          classID = 2, subClassID = 7, owner = "Brann" },
        { itemID = SWORD, name = "Short Sword", count = 1, buyout = 12000, quality = 2, level = 10,
          classID = 2, subClassID = 7, owner = "Mira" },
    }
end

local function seed(A, key, unit, days)
    local now = A.Game.Now()
    for d = 1, days do A.Store.Record(RKEY, key, unit, 1, now - d * DAY) end
end

-- One frame of the world: timers, then the follower's look.
local function frame(n)
    for _ = 1, n or 1 do
        AHW.Frame()
        DaylightUI.Win.Followers.Tick()
    end
end

-- The tween driver run for `s` seconds (glides, fades).
local function tween(A, s)
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, s or 1) end
end

-- opts.offer: leave the first-visit card wanted (no full scan, not offered).
local function load(opts)
    opts = opts or {}
    local _, A = AHW.Load({ auctions = opts.auctions or auctions(), commodities = { [RUNECLOTH] = true, [BOLT] = true } }, {
        before = function()
            _G.AuctionHouseFrame = nil
            gameAH()
            fakeCategories()
        end,
    })
    A.Replicate.SETTLE, A.Replicate.EMPTY_WAIT = 0, 0
    seed(A, tostring(RUNECLOTH), 16200, 10)   -- usual 1g 62s
    seed(A, tostring(HELM), 135000, 6)
    seed(A, tostring(SWORD), 10000, 6)
    if not opts.offer then A.Store.MarkOffered(RKEY) end
    AHW.Open()
    frame()
    local page = A.Window.frame.pages.buy
    -- The fake game doesn't lay frames out from their anchors: the sizes the
    -- client gives the right pane and the table's view (960 x 563 page).
    page.right:SetSize(709, 563)
    page.table.view:SetSize(677, 563 - A.BuyPage.TABLE_TOP - DaylightUI.Widgets.COLUMN_H - 2 - A.BuyPage.FOOT)
    page.table:Layout()
    return A, page
end

local function plain(text)
    return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
local function textOf(fs) return plain(stub.Text(fs) or "") end

local function enter(box, text)
    box:SetText(text)
    box:GetScript("OnEnterPressed")(box)
end

local function quiet()
    AHW.Advance(5)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end

local function kinds(t)
    local out = {}
    for i, r in ipairs(t.rows) do out[i] = r.kind end
    return table.concat(out, ",")
end

-- The left pane's row or line whose words are `text`.
local function leftRow(A, text)
    for _, b in ipairs(A.BuyPage.Left.pane.stack.used) do
        local words = b.spec and b.spec.text or (b.lineSpec and b.lineSpec.text)
        if b:IsShown() and words and plain(words) == text then return b end
    end
    error("no left row " .. text)
end

local function menuRow(key)
    for i = 1, 20 do
        local r = DaylightUI.Widgets.MenuRow(i)
        if r and r:IsShown() and r.key == key then return r end
    end
    error("no menu row " .. tostring(key))
end

local function lastQuery()
    local log = AHW.Log("SendBrowseQuery")
    return log[#log] and log[#log][1]
end

local function has(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

T.test("ah buy page: Lvl is the level to wear it, not the item level", function()
    local _, page = load()
    enter(page.box, "lionheart")
    AHW.Settle()
    T.eq(page.table.rows[1].itemID, HELM)
    T.eq(textOf(page.table:Row(1).cells.level), "60", "required level, item level is 65")
end)

-- The game's own window shows the skill a recipe needs in that column
-- (Recipes' detail column) and sorts by it.
T.test("ah buy page: recipes show the skill they need, sortable", function()
    local list = auctions()
    list[#list + 1] = { itemID = PATTERN_HIGH, name = "Pattern: Runecloth Bag", count = 1, buyout = 50000,
        level = 1, classID = 9, subClassID = 2, skill = 260 }
    list[#list + 1] = { itemID = PATTERN_LOW, name = "Pattern: Green Woolen Bag", count = 1, buyout = 90000,
        level = 1, classID = 9, subClassID = 2, skill = 95, skillLate = true }
    local A, page = load({ auctions = list })
    local t = page.table
    leftRow(A, "Recipes"):Click()
    AHW.Settle()
    T.eq(textOf(t.head.cells.level.text), "Skill", "the game's word for Recipes")
    T.eq(#t.rows, 2)
    T.eq(t.rows[1].itemID, PATTERN_HIGH, "cheapest first")
    T.eq(textOf(t:Row(1).cells.level), "260")
    T.eq(textOf(t:Row(2).cells.level), "", "the server hasn't sent it yet")
    AHW.SendExtra(PATTERN_LOW)
    frame()
    T.eq(textOf(t:Row(2).cells.level), "95", "filled when it arrives")
    t.head.cells.level:Click()
    frame()
    T.eq(t.rows[1].itemID, PATTERN_LOW, "lowest skill first")
    T.eq(t.rows[2].itemID, PATTERN_HIGH)
    enter(page.box, "lionheart")
    leftRow(A, "Recipes"):Click()   -- unpick: search everywhere
    AHW.Settle()
    T.eq(textOf(t.head.cells.level.text), "Lvl", "back to the level to use it")
    quiet()
end)

T.test("ah buy page: a search fills one row per item, cheapest first", function()
    local A, page = load()
    local Ink = DaylightUI.Style.INK
    T.truthy(page.note:IsShown(), "the empty words before any search")
    T.eq(textOf(page.note), "Pick a category on the left, or type a name.")
    enter(page.box, "runecloth")
    AHW.Settle()
    T.eq(AHW.Calls("SendBrowseQuery"), 1)
    T.eq(lastQuery().searchString, "runecloth")
    local t = page.table
    T.eq(#t.rows, 2)
    T.eq(t.rows[1].itemID, RUNECLOTH, "1g 05s first")
    T.eq(t.rows[2].itemID, BOLT)
    T.eq(t.head.sortId, "unit")
    T.falsy(t.head.descending)
    local b = t:Row(1)
    T.eq(textOf(b.name), "Runecloth")
    T.eq(textOf(b.cells.qty), "600")
    T.eq(textOf(b.cells.level), "50")
    T.eq(t.rows[1].usual, 16200, "usual from the days before today")
    T.eq(textOf(b.cells.pct), "65%")
    T.rgb({ b.cells.pct:GetTextColor() }, Ink.GOOD, "a deal")
    T.eq(textOf(t:Row(2).cells.usual), "6 50", "first seen today: today's cheapest is all it has")
    T.eq(textOf(t:Row(2).cells.pct), "100%")
    T.truthy(textOf(page.stat):find("2 items", 1, true), textOf(page.stat))
    tween(A)
    T.falsy(page.note:IsShown(), "no empty words over rows")
    -- a click on a column sorts by it, again flips it
    page.table.head.cells.unit:Click()
    T.eq(t.rows[1].itemID, BOLT, "dearest first")
    -- typing alone never searches
    page.box:SetText("linen")
    T.eq(AHW.Calls("SendBrowseQuery"), 1)
    -- nothing found
    enter(page.box, "linen")
    AHW.Settle()
    tween(A)
    T.eq(#t.rows, 0)
    T.eq(textOf(page.note), "No items match.")
    quiet()
end)

T.test("ah buy page: a category browses the game's own filters", function()
    local A, page = load()
    local Left = A.BuyPage.Left
    T.eq(Left.mode, "browse")
    for _, b in ipairs(Left.pane.stack.used) do
        T.falsy(b:IsShown() and b.spec and b.spec.text == "WoW Token", "the token has nothing to browse")
    end
    leftRow(A, "Trade Goods"):Click()
    T.truthy(Left.expanded["trade-goods"], "it opens")
    AHW.Settle()
    local q = lastQuery()
    T.eq(q.searchString, "")
    T.eq(q.itemClassFilters[1].classID, 7)
    T.eq(q.itemClassFilters[1].subClassID, 5)
    T.eq(#page.table.rows, 2, "the cloth, not the helm")
    leftRow(A, "Cloth"):Click()
    AHW.Settle()
    T.eq(A.BuyPage.state.query.path, "trade-goods/cloth")
    T.eq(textOf(page.where), "Trade Goods / Cloth")
    T.eq(page.box:GetText() or "", "", "a category isn't words in the box")
    -- the filter row goes with it: uncommon and better leaves the cloth out
    page.rarity:Click()
    menuRow("uncommon"):Click()
    AHW.Settle()
    q = lastQuery()
    T.falsy(has(q.filters, 6) or has(q.filters, 7), "no poor or common")
    T.truthy(has(q.filters, 8) and has(q.filters, 12), "uncommon up to artifact")
    T.eq(q.itemClassFilters[1].classID, 7, "still the category")
    T.eq(#page.table.rows, 0)
    page.usable:Click()
    AHW.Settle()
    T.truthy(has(lastQuery().filters, 2), "UsableOnly")
    enter(page.from, "50")
    AHW.Settle()
    T.eq(lastQuery().minLevel, 50)
    quiet()
end)

-- The game's own AH searches the typed words inside the picked category, and
-- a click on the picked category again unpicks it.
T.test("ah buy page: words typed with a category picked search inside it", function()
    local A, page = load()
    local BP = A.BuyPage
    leftRow(A, "Trade Goods"):Click()
    AHW.Settle()
    leftRow(A, "Cloth"):Click()
    AHW.Settle()
    enter(page.box, "lionheart")
    AHW.Settle()
    local q = lastQuery()
    T.eq(q.searchString, "lionheart")
    T.truthy(q.itemClassFilters and q.itemClassFilters[1].classID == 7, "still in Trade Goods / Cloth")
    T.eq(#page.table.rows, 0, "the helm isn't cloth")
    T.eq(BP.state.query.path, "trade-goods/cloth")
    T.eq(textOf(page.where), "Trade Goods / Cloth")
    -- the recent list keeps both
    T.eq(BP.Recent()[1].text, "lionheart")
    T.eq(BP.Recent()[1].path, "trade-goods/cloth")
    -- the box emptied: Enter browses the category again
    enter(page.box, "")
    AHW.Settle()
    T.eq(lastQuery().searchString, "")
    T.eq(#page.table.rows, 2)
    -- words again, still in Cloth
    enter(page.box, "bolt")
    AHW.Settle()
    T.eq(#page.table.rows, 1)
    -- a click on the picked one goes up to its parent, then to none
    leftRow(A, "Cloth"):Click()
    AHW.Settle()
    T.eq(BP.state.query.path, "trade-goods")
    T.eq(lastQuery().searchString, "bolt")
    leftRow(A, "Trade Goods"):Click()
    AHW.Advance(0.2)   -- its rows fade out first
    AHW.Settle()
    T.falsy(BP.state.query.path, "no category left")
    T.falsy(BP.Left.expanded["trade-goods"], "and it shuts")
    T.eq(textOf(page.where), "")
    T.eq(lastQuery().searchString, "bolt")
    T.falsy(lastQuery().itemClassFilters, "everywhere now")
    -- with nothing typed, unpicking the last category clears the results
    page.box:SetText("")
    leftRow(A, "Trade Goods"):Click()
    AHW.Settle()
    leftRow(A, "Trade Goods"):Click()
    AHW.Advance(0.2)
    AHW.Settle()
    T.falsy(BP.state.query, "nothing to search")
    T.eq(#page.table.rows, 0)
    -- a favorite or a shift-clicked link searches everywhere
    leftRow(A, "Trade Goods"):Click()
    AHW.Settle()
    BP.Submit("lionheart", true)
    AHW.Settle()
    T.falsy(BP.state.query.path)
    T.eq(#page.table.rows, 1)
    quiet()
end)

T.test("ah buy page: a commodity opens its steps, then the game's two clicks buy", function()
    local A, page = load()
    local BP = A.BuyPage
    enter(page.box, "runecloth")
    AHW.Settle()
    local t = page.table
    local row = t.rows[1]
    t:Row(1):Click()
    T.eq(BP.state.open, row)
    AHW.Settle()
    T.eq(kinds(t), "line,step,step,step,why,line")
    T.truthy(t.growing, "the steps and why glide open")
    tween(A, 1)
    T.isnil(t.growing)
    T.eq(textOf(t:Row(2).name), "60 at this price")
    T.eq(textOf(t:Row(2).cells.pct), "65%")
    local why = plain(t.rows[5].text)
    T.truthy(why:find("The cheapest 60 are", 1, true), why)
    T.truthy(why:find("65% of usual", 1, true), why)
    T.truthy(why:find("for the last 10 days", 1, true) or why:find("each of the 10 days", 1, true), why)
    T.truthy(why:find("so 260 would cost about", 1, true), why)
    local buy = page.foot.buttons[1]
    T.eq(textOf(buy.text), "Buy 1", "starts at one, as the game's window does")
    T.truthy(page.amount:IsShown(), "the amount box")
    T.eq(page.amount:GetText(), "1")
    -- a click on a step: up to and through it
    t:Row(3):Click()
    T.eq(textOf(buy.text), "Buy 260")
    BP.SetAmount(60)
    -- the first click asks the game for the price
    buy:Click()
    T.eq(AHW.Calls("StartCommoditiesPurchase"), 1, "asked inside the click")
    AHW.Settle()
    T.truthy(textOf(buy.text):find("Confirm 63", 1, true), textOf(buy.text))
    T.eq(AHW.Calls("ConfirmCommoditiesPurchase"), 0, "nothing bought on the first click")
    buy:Click()   -- a double-click: the total only just showed
    T.eq(AHW.Calls("ConfirmCommoditiesPurchase"), 0, "refused while the total is new")
    AHW.Advance(BP.CONFIRM_WAIT + 0.01)
    buy:Click()
    T.eq(AHW.Calls("ConfirmCommoditiesPurchase"), 1)
    AHW.Settle()
    tween(A, 1)
    T.eq(textOf(page.stat), "Bought 60 Runecloth.")
    T.rgb({ page.stat:GetTextColor() }, DaylightUI.Style.INK.GOOD)
    T.eq(row.qty, 540, "the row searched again")
    T.eq(row.unit, 11800, "the 60 at 1g 05s are gone")
    T.eq(textOf(buy.text), "Buy 1", "back to one after a purchase")
    -- picked again: shut
    t:Row(1):Click()
    tween(A, 1)
    T.eq(kinds(t), "line,line")
    T.isnil(BP.state.open)
    quiet()
end)

T.test("ah buy page: a moved quote is refused and shown again", function()
    local A, page = load()
    local BP = A.BuyPage
    enter(page.box, "runecloth")
    AHW.Settle()
    page.table:Row(1):Click()
    AHW.Settle()
    tween(A, 1)
    local buy = page.foot.buttons[1]
    BP.SetAmount(60)
    buy:Click()
    AHW.Settle()
    AHW.Advance(BP.CONFIRM_WAIT + 0.01)
    -- the price moves while the player looks
    stub.FireEvent("COMMODITY_PRICE_UPDATED", 10600, 636000)
    T.truthy(textOf(buy.text):find("Confirm 63", 1, true), textOf(buy.text))
    T.truthy(textOf(buy.text):find("the price went up", 1, true), textOf(buy.text))
    T.eq(AHW.Calls("ConfirmCommoditiesPurchase"), 0)
    -- Cancel drops the quote
    page.foot.buttons[2]:Click()
    T.eq(AHW.Calls("CancelCommoditiesPurchase"), 1)
    T.eq(textOf(buy.text), "Buy 60")
    quiet()
end)

T.test("ah buy page: gear buys in one click", function()
    local A, page = load()
    enter(page.box, "short sword")
    AHW.Settle()
    local t = page.table
    T.eq(#t.rows, 1)
    t:Row(1):Click()
    AHW.Settle()
    tween(A, 1)
    T.eq(kinds(t), "line,step,step,why", "two auctions to pick from")
    T.truthy(textOf(t:Row(2).name):find("Brann", 1, true), textOf(t:Row(2).name))
    local buy = page.foot.buttons[1]
    T.eq(textOf(buy.text), "Buy for 90")
    T.falsy(page.amount:IsShown(), "no amount for gear")
    -- the dearer one picked
    t:Row(3):Click()
    T.eq(textOf(buy.text), "Buy for 1 20")
    t:Row(2):Click()
    buy:Click()
    T.eq(AHW.Calls("PlaceBid"), 1, "one click buys")
    AHW.Settle()
    tween(A, 1)
    T.eq(textOf(page.stat), "Bought 1 Short Sword.")
    T.eq(#t.rows[1].steps, 1, "searched again: one left")
    quiet()
end)

T.test("ah buy page: far over usual asks once more", function()
    local A, page = load()
    local Ink = DaylightUI.Style.INK
    enter(page.box, "lionheart")
    AHW.Settle()
    local t = page.table
    T.eq(textOf(t:Row(1).cells.pct), "311%")
    T.rgb({ t:Row(1).cells.pct:GetTextColor() }, Ink.WARN)
    t:Row(1):Click()
    AHW.Settle()
    tween(A, 1)
    T.eq(kinds(t), "line,why", "one up: no step to pick")
    local why = plain(t.rows[2].text)
    T.truthy(why:find("One up, buyout 42", 1, true), why)
    T.truthy(why:find("311% of usual", 1, true), why)
    T.truthy(why:find("different roll", 1, true), why)
    local buy = page.foot.buttons[1]
    T.eq(textOf(buy.text), "Buy for 42")
    buy:Click()
    T.eq(textOf(buy.text), "311% of usual: click again")
    T.rgb({ buy.text:GetTextColor() }, Ink.WARN)
    T.eq(AHW.Calls("PlaceBid"), 0, "the first click only asks")
    buy:Click()   -- a double-click
    T.eq(AHW.Calls("PlaceBid"), 0, "a double-click buys nothing")
    AHW.Advance(DaylightUI.Widgets.CONFIRM_GAP + 0.01)
    buy:Click()
    T.eq(AHW.Calls("PlaceBid"), 1, "the second click buys")
    AHW.Settle()
    T.eq(textOf(page.stat), "Bought 1 Lionheart Helm.")
    quiet()
end)

T.test("ah buy page: favorites and recent searches are saved", function()
    local A, page = load()
    local BP, Left = A.BuyPage, A.BuyPage.Left
    enter(page.box, "runecloth")
    AHW.Settle()
    leftRow(A, "Trade Goods"):Click()
    AHW.Settle()
    enter(page.box, "Runecloth")
    AHW.Settle()
    local recent = DaylightUIAuctionDB.recent
    T.eq(#recent, 2, "the same search twice is one")
    T.eq(recent[1].text, "Runecloth", "newest first")
    T.eq(recent[1].path, "trade-goods", "the words in the category")
    T.eq(recent[2].text, "runecloth")
    T.falsy(recent[2].path)
    page.box:SetText("")
    Left.Show("recent")
    leftRow(A, "Runecloth in Trade Goods"):Click()
    AHW.Settle()
    T.eq(BP.state.query.path, "trade-goods", "a recent search goes back to its category")
    T.eq(page.box:GetText(), "Runecloth")
    leftRow(A, "runecloth"):Click()
    AHW.Settle()
    T.falsy(BP.state.query.path, "and one made everywhere searches everywhere")
    -- a result's right-click: on the favorites
    enter(page.box, "runecloth")
    AHW.Settle()
    page.table:Row(1):Click("RightButton")
    menuRow("fav"):Click()
    T.deq(DaylightUIAuctionDB.favorites, { RUNECLOTH })
    T.truthy(BP.IsFavorite(RUNECLOTH))
    Left.Show("favorites")
    local fav = leftRow(A, "Runecloth")
    -- a click searches it and opens its row
    enter(page.box, "lionheart")
    AHW.Settle()
    fav:Click()
    AHW.Settle()
    T.eq(page.box:GetText(), "Runecloth")
    T.eq(BP.state.open and BP.state.open.itemID, RUNECLOTH)
    -- a right-click takes it off
    fav:Click("RightButton")
    menuRow("off"):Click()
    T.deq(DaylightUIAuctionDB.favorites, {})
    quiet()
end)

T.test("ah buy page: suggestions come from the items seen", function()
    local A, page = load()
    local BP = A.BuyPage
    enter(page.box, "runecloth")
    AHW.Settle()
    T.isnil(BP.Suggest("r"), "one letter suggests nothing")
    BP.Suggest("rune")   -- starts the index, a slice a frame
    AHW.Settle()
    local list = BP.Suggest("rune")
    T.truthy(list and #list == 2, "Runecloth and Bolt of Runecloth")
    T.eq(list[1].insert, "Runecloth", "names starting with it first")
    T.eq(list[2].insert, "Bolt of Runecloth")
    T.truthy(list[2].label:find("|r", 1, true), "the typed part in the accent")
    T.isnil(BP.Suggest("runecloth"), "a whole name typed: Enter searches")
    -- Enter searches what's typed, even with names listed
    page.box:SetText("rune")
    page.complete:Refresh("rune")
    page.box:GetScript("OnEnterPressed")(page.box)
    AHW.Settle()
    T.eq(lastQuery().searchString, "rune")
    quiet()
end)

T.test("ah buy page: a row the game hasn't loaded gets its name when it comes", function()
    local FEL = 14256
    local list = auctions()
    list[#list + 1] = { itemID = FEL, name = "Felcloth", count = 42, buyout = 42 * 21000, cached = false,
        classID = 7, subClassID = 5 }
    local A, page = load({ auctions = list })
    enter(page.box, "cloth")
    AHW.Frame()
    AHW.Step()
    for _ = 1, 5 do AHW.Frame() end
    local t = page.table
    local fel
    for _, r in ipairs(t.rows) do if r.itemID == FEL then fel = r end end
    T.truthy(fel, "the row shows before its name")
    T.isnil(fel.name)
    AHW.Settle()
    T.eq(fel.name, "Felcloth", "named once the game loaded it")
    quiet()
end)

T.test("ah buy page: the first-visit card moves the right pane down, eased", function()
    local A, page = load({ offer = true })
    local BP = A.BuyPage
    T.truthy(A.Window.OfferWanted())
    T.eq(BP.shift, A.Window.OFFER_H + BP.ROOM_GAP, "under the card")
    local _, _, _, x, y = page.right:GetPoint(1)
    T.eq(x, BP.LEFT_W + 1, "beside the categories")
    local _, _, _, cx = A.Window.Offer():GetPoint(1)
    T.eq(cx, BP.LEFT_W + 1 + A.Window.OFFER_EDGE, "the card sits over the right pane only")
    _, _, _, _, y = page.left:GetPoint(1)
    T.eq(y, 0, "the categories stay put")
    _, _, _, _, y = page.right:GetPoint(1)
    T.eq(y, -(A.Window.OFFER_H + BP.ROOM_GAP))
    A.Window.Offer().later:Click()
    T.eq(BP.shift, 0)
    tween(A, 1)
    _, _, _, _, y = page.right:GetPoint(1)
    T.eq(y, 0, "back up once the card goes")
    quiet()
end)
