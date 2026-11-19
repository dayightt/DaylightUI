local AHW = require("ahworld")
local stub = require("stub")

-- Posting and cancelling (Game/Post.lua) on the fake auction house: a
-- commodity is one post of the amount, gear one auction per item (the game's
-- multisell), each in one click; the game's price warning wants a second
-- click; your own auctions (sold ones too); a cancel needs them read first
-- and mails the items back. tests/ahworld.lua's header says what the fake does.

local LINEN, SWORD, BOUND, NEW = 2589, 2207, 6948, 4306
local RKEY = "US-PvE"

local function load(spec)
    spec = spec or {}
    spec.commodities = spec.commodities or { [LINEN] = true, [NEW] = true }
    spec.auctions = spec.auctions or {
        { itemID = LINEN, name = "Linen Cloth", count = 200, buyout = 200 * 10 },
        { itemID = SWORD, name = "Ridge Cleaver", count = 1, buyout = 20000, classID = 2 },
    }
    spec.items = spec.items or {
        [BOUND] = { name = "Hearthstone" },
        [NEW] = { name = "Silk Cloth", vendorSell = 37 },
    }
    spec.bags = spec.bags or {
        [0] = {
            { itemID = LINEN, stackCount = 20, name = "Linen Cloth" },
            { itemID = LINEN, stackCount = 5, name = "Linen Cloth" },
            { itemID = SWORD, stackCount = 1, name = "Ridge Cleaver" },
            { itemID = SWORD, stackCount = 1, name = "Ridge Cleaver" },
            { itemID = BOUND, stackCount = 1, isBound = true },
        },
    }
    local M = AHW.Mog({
        ah = spec,
        before = function()
        end,
    })
    return M
end

local function click(fn)
    local a, b
    stub.Key(function() a, b = fn() end)
    return a, b
end

local function watcher()
    local w = { done = {} }
    w.fn = function(ok, why) w.done[#w.done + 1] = { ok, why } end
    return w
end

local function mineOf(itemID)
    local out = {}
    for _, a in ipairs(AHW.Auctions()) do if a.itemID == itemID and a.mine then out[#out + 1] = a end end
    return out
end

local function quiet()
    AHW.Settle()
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end

T.test("post_a_commodity_is_one_auction_of_the_amount", function()
    local M = load()
    AHW.Open()
    T.eq(M.Post.Kind("2589"), "commodity")
    T.eq(M.Post.Kind("2207"), "item")
    local w = watcher()
    T.eq(click(function() return M.Post.Send("2589", 22, 9, 24, w.fn) end), true)
    T.deq(AHW.Log("PostCommodity")[1][2], 3, "24 h is the game's third duration")
    AHW.Settle()
    T.deq(w.done, { { true } })
    local up = mineOf(LINEN)
    T.eq(#up, 1)
    T.eq(up[1].count, 22)
    T.eq(up[1].buyout, 22 * 9)
    T.eq(M.Bags.Count("2589"), 3, "taken from both stacks")
    quiet()
end)

T.test("post_needs_the_players_click", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    M.Post.Send("2589", 5, 9, 24, w.fn)   -- no click
    AHW.Advance(15)
    T.eq(#mineOf(LINEN), 0, "nothing posted")
    T.truthy(stub.errors[1] and stub.errors[1]:find("ADDON_ACTION_BLOCKED", 1, true))
    T.deq(w.done, { { false, "timeout" } }, "the client gives no answer: it times out, never retried")
    stub.errors = {}
end)

T.test("post_gear_sends_a_starting_bid", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    T.eq(click(function() return M.Post.Send("2207", 1, 15000, 8, w.fn, 7000) end), true)
    local log = AHW.Log("PostItem")[1]
    T.eq(log[4], 7000, "the bid")
    T.eq(log[5], 15000)
    AHW.Settle()
    w = watcher()
    click(function() return M.Post.Send("2589", 5, 100, 8, w.fn, 50) end)
    T.eq(AHW.Calls("PostCommodity"), 1, "a commodity just has no bid")
    AHW.Settle()
end)

T.test("post_gear_makes_one_auction_each", function()
    local M = load()
    AHW.Open()
    local w = watcher()
    T.eq(click(function() return M.Post.Send("2207", 2, 15000, 8, w.fn) end), true)
    local log = AHW.Log("PostItem")[1]
    T.eq(log[2], 2, "8 h")
    T.eq(log[3], 2)
    T.isnil(log[4], "no bid")
    T.eq(log[5], 15000)
    AHW.Settle()
    T.deq(w.done, { { true } }, "done when the multisell says all")
    local up = mineOf(SWORD)
    T.eq(#up, 2)
    T.eq(up[1].buyout, 15000)
    T.eq(M.Bags.Count("2207"), 0)
    quiet()
end)

T.test("post_refusals_say_why", function()
    local M = load()
    T.deq({ M.Post.Send("2589", 1, 9, 24) }, { false, "closed" })
    AHW.Open()
    T.deq({ click(function() return M.Post.Send("2589", 26, 9, 24) end) }, { false, "count" }, "more than the bags hold")
    T.deq({ click(function() return M.Post.Send("2589", 1, 0.5, 24) end) }, { false, "price" })
    T.deq({ click(function() return M.Post.Send("6948", 1, 9, 24) end) }, { false, "nobags" }, "a bound item can't be sold")
    T.eq(M.Bags.Free("6948"), 0)
    T.eq(AHW.Calls("PostCommodity") + AHW.Calls("PostItem"), 0, "nothing sent")
    quiet()
end)

T.test("post_unknown_until_the_game_knows_the_item", function()
    local M = load({
        auctions = { { itemID = LINEN, name = "Linen Cloth", count = 1, buyout = 10, cached = false } },
        bags = { [0] = { { itemID = LINEN, stackCount = 5 } } },
    })
    AHW.Open()
    T.isnil(M.Post.Kind("2589"))
    T.deq({ click(function() return M.Post.Send("2589", 5, 9, 24) end) }, { false, "unknown" })
    AHW.Cache(LINEN)
    T.eq(M.Post.Kind("2589"), "commodity")
    quiet()
end)

T.test("the_games_price_warning_takes_a_second_click", function()
    local M = load({ postWarning = { [LINEN] = true } })
    AHW.Open()
    local w = watcher()
    T.deq({ click(function() return M.Post.Send("2589", 5, 1, 24, w.fn) end) }, { false, "confirm" })
    AHW.Settle()
    T.eq(#mineOf(LINEN), 0, "nothing posted yet")
    T.deq(w.done, {}, "the first click isn't an end")
    T.deq(M.Post.Warned(), { key = "2589", qty = 5, unit = 1, hours = 24 })
    T.eq(click(function() return M.Post.Confirm() end), true)
    T.eq(AHW.Calls("ConfirmPostCommodity"), 1)
    AHW.Settle()
    T.deq(w.done, { { true } })
    T.eq(#mineOf(LINEN), 1)
    T.isnil(M.Post.Warned())
    T.deq({ M.Post.Confirm() }, { false, "nothing" })
    quiet()
end)

T.test("a_failed_post_says_failed", function()
    local M = load({ postFails = { [SWORD] = true } })
    AHW.Open()
    local w = watcher()
    click(function() return M.Post.Send("2207", 2, 100, 24, w.fn) end)
    AHW.Settle()
    T.deq(w.done, { { false, "failed" } })
    T.eq(M.Bags.Count("2207"), 2, "still in the bags")
    quiet()
end)

T.test("a_failed_post_carries_the_games_own_words", function()
    local M = load({ postFails = { [SWORD] = AHW.DATABASE_ERROR } })
    AHW.Open()
    local got
    click(function() return M.Post.Send("2207", 1, 100, 24, function(...) got = { ... } end) end)
    AHW.Settle()
    T.deq(got, { false, "failed", "Internal auction error" })
    quiet()
end)

T.test("the_games_post_error_is_a_refusal_never_a_warning", function()
    local M = load({ postRefused = { [SWORD] = true } })
    AHW.Open()
    local w = watcher()
    local ok, why, text
    stub.Key(function() ok, why, text = M.Post.Send("2207", 1, 100, 24, w.fn) end)
    T.deq({ ok, why, text }, { false, "failed", "Your auction could not be posted" }, "the last period goes: it ends the addon's sentence")
    T.isnil(M.Post.Warned(), "no second click: the game's popup only has OK")
    T.deq(w.done, {}, "refused at once: onDone isn't called")
    T.falsy(M.AH.Busy(), "the line is free")
    quiet()
end)

T.test("a_click_while_a_lost_answer_may_still_come_says_late", function()
    local M = load({ step = 15 })
    AHW.Open()
    local w = watcher()
    click(function() return M.Post.Send("2207", 1, 100, 24, w.fn) end)
    AHW.Advance(11)   -- its timeout passed, its answer is due at +15
    T.deq(w.done, { { false, "timeout" } })
    T.deq({ click(function() return M.Post.Send("2589", 1, 9, 24, w.fn) end) }, { false, "late" })
    AHW.Settle()
    quiet()
end)

T.test("a_refused_cancel_keeps_the_games_words", function()
    local M = load({ cancelFails = AHW.DATABASE_ERROR })
    AHW.Open()
    click(function() return M.Post.Send("2207", 1, 100, 24) end)
    AHW.Settle()
    M.Post.Owned()
    AHW.Settle()
    local got
    click(function() return M.Post.Cancel(mineOf(SWORD)[1].auctionID, function(...) got = { ... } end) end)
    AHW.Settle()
    T.deq(got, { false, "failed", "Internal auction error" })
    quiet()
end)

T.test("deposit_from_the_game", function()
    local M = load()
    AHW.Open()
    T.eq(M.Post.Deposit("2589", 20, 24), 20 * 3, "the fake's: vendor price (1) x qty x duration")
    T.eq(M.Post.Deposit("2207", 1, 2), 1)
    T.isnil(M.Post.Deposit("6948", 1, 24), "nothing to sell")
    quiet()
end)

T.test("owned_auctions_list_sold_ones_too", function()
    local M = load({
        auctions = {
            { itemID = LINEN, name = "Linen Cloth", count = 20, buyout = 200, mine = true },
            { itemID = LINEN, name = "Linen Cloth", count = 10, buyout = 90 },
            { itemID = SWORD, name = "Ridge Cleaver", count = 1, buyout = 20000, mine = true, sold = true },
            { itemID = SWORD, name = "Ridge Cleaver", count = 1, buyout = 25000, mine = true, bid = 12000 },
            { itemID = LINEN, name = "Linen Cloth", count = 9, buyout = 9 * 30, mine = true, sold = true },
        },
    })
    AHW.Open()
    local got
    T.eq(M.Post.Owned(function(list, why) got = { list = list, why = why } end), true)
    T.eq(AHW.Calls("QueryOwnedAuctions"), 1)
    AHW.Settle()
    T.eq(#got.list, 4)
    local linen, sold, bid, soldStack = got.list[1], got.list[2], got.list[3], got.list[4]
    T.eq(linen.key, "2589")
    T.eq(linen.qty, 20)
    T.eq(linen.unit, 10)
    T.eq(linen.buyout, 200, "the game says the price of one; the whole auction is that x qty")
    T.eq(linen.sold, false)
    T.truthy(linen.left)
    T.eq(sold.sold, true)
    T.isnil(sold.left)
    T.eq(bid.bid, 12000)
    T.eq(soldStack.unit, 30, "a sold auction's price from the game is the whole sale: per unit is that / qty")
    T.eq(soldStack.buyout, 270, "never qty x the whole sale")
    T.eq(M.Post.Up("2589"), 20)
    T.eq(M.Post.Up("2207"), 1, "a sold one isn't up")
    T.eq(#M.Post.Mine(), 4)
    quiet()
end)

T.test("cancel_takes_a_click_and_mails_it_back", function()
    local M = load({ auctions = { { itemID = LINEN, name = "Linen Cloth", count = 20, buyout = 200, mine = true } } })
    AHW.Open()
    local id = AHW.Auctions()[1].auctionID
    T.deq({ M.Post.Cancel(id) }, { false, "notmine" }, "not read from the owned list yet")
    M.Post.Owned()
    AHW.Settle()
    local w = watcher()
    T.eq(click(function() return M.Post.Cancel(id, w.fn) end), true)
    AHW.Settle()
    T.deq(w.done, { { true } })
    T.eq(#AHW.Auctions(), 0)
    T.deq(AHW.Mailed(), { { itemID = LINEN, count = 20 } }, "back by mail, not to the bags")
    T.eq(#M.Post.Mine(), 0, "gone from the list")
    T.eq(M.Post.CancelCost(id), 0)
    quiet()
end)

-- Forever: a cancel went through but the addon heard no answer for that auction
-- (a player, 2026-11-11: "Cancel 1 of 9" stalled after one). Any cancel answer
-- while ours is out is ours; with none, the owned list says whether it's gone.
for _, case in ipairs({ { "another_id", 0 }, { "no_event", false } }) do
    T.test("a_cancel_answer_without_its_id_still_ends_it_" .. case[1], function()
        local M = load({ cancelEvent = case[2],
            auctions = { { itemID = LINEN, name = "Linen Cloth", count = 20, buyout = 200, mine = true } } })
        AHW.Open()
        local id = AHW.Auctions()[1].auctionID
        M.Post.Owned()
        AHW.Settle()
        local w = watcher()
        T.eq(click(function() return M.Post.Cancel(id, w.fn) end), true)
        AHW.Settle()
        AHW.Advance(30)
        AHW.Settle()
        T.deq(w.done, { { true } })
        T.eq(#M.Post.Mine(), 0, "gone from the list")
        quiet()
    end)
end

T.test("cancel_without_a_click_is_blocked", function()
    local M = load({ auctions = { { itemID = LINEN, name = "Linen Cloth", count = 20, buyout = 200, mine = true } } })
    AHW.Open()
    M.Post.Owned()
    AHW.Settle()
    local w = watcher()
    M.Post.Cancel(AHW.Auctions()[1].auctionID, w.fn)
    AHW.Advance(15)
    T.eq(#AHW.Auctions(), 1)
    T.deq(w.done, { { false, "timeout" } })
    stub.errors = {}
end)

T.test("a_warned_post_refuses_when_the_stack_moved", function()
    local M = load({ postWarning = { [LINEN] = true } })
    AHW.Open()
    click(function() return M.Post.Send("2589", 5, 1, 24) end)
    AHW.Settle()
    T.truthy(M.Post.Warned())
    -- the slot now holds something else
    local real = C_Container.GetContainerItemInfo
    C_Container.GetContainerItemInfo = function(bag, slot)
        if bag == 0 and slot == 1 then return real(0, 3) end
        return real(bag, slot)
    end
    T.deq({ click(function() return M.Post.Confirm() end) }, { false, "moved" })
    T.eq(AHW.Calls("ConfirmPostCommodity"), 0)
    T.isnil(M.Post.Warned(), "the warning is dropped")
    C_Container.GetContainerItemInfo = real
    quiet()
end)

T.test("an_owned_auction_with_no_link_keeps_its_suffix", function()
    local M = load({ auctions = { { itemID = SWORD, name = "Ridge Cleaver", count = 1, buyout = 500, mine = true } } })
    AHW.Open()
    local real = C_AuctionHouse.GetOwnedAuctionInfo
    C_AuctionHouse.GetOwnedAuctionInfo = function(i)
        local r = real(i)
        r.itemLink = nil
        r.itemKey = { itemID = SWORD, itemLevel = 0, itemSuffix = -15, battlePetSpeciesID = 0 }
        return r
    end
    M.Post.Owned()
    AHW.Settle()
    T.eq(M.Post.Mine()[1].key, "2207:-15")
    C_AuctionHouse.GetOwnedAuctionInfo = real
    quiet()
end)

T.test("mine_low_is_your_cheapest_up", function()
    local M = load({ auctions = {
        { itemID = LINEN, name = "Linen Cloth", count = 5, buyout = 5 * 30, mine = true },
        { itemID = LINEN, name = "Linen Cloth", count = 5, buyout = 5 * 20, mine = true, sold = true },
        { itemID = LINEN, name = "Linen Cloth", count = 5, buyout = 5 * 25, mine = true },
    } })
    AHW.Open()
    T.isnil(M.Post.MineLow("2589"))
    M.Post.Owned()
    AHW.Settle()
    T.eq(M.Post.MineLow("2589"), 25)
    quiet()
end)

T.test("a_stack_the_game_wont_sell_is_passed_over", function()
    local M = load()
    AHW.Open()
    local asked
    C_AuctionHouse.IsSellItemValid = function(loc, shout)
        asked = shout
        return not (loc.bag == 0 and loc.slot == 3)   -- the first sword is damaged
    end
    T.truthy(M.Post.Sellable("2207"))
    T.eq(asked, false, "never a chat error from the addon asking")
    click(function() return M.Post.Send("2207", 1, 100, 24) end)
    T.eq(AHW.Log("PostItem")[1][1].slot, 4)
    AHW.Settle()
    C_AuctionHouse.IsSellItemValid = function() return false end
    T.falsy(M.Post.Sellable("2589"))
    C_AuctionHouse.IsSellItemValid = nil
    quiet()
end)

-- Forever takes no copper on a single item ("Internal auction error", in the
-- game's own window too); a commodity takes it. A copper price for gear is
-- never sent.
T.test("a_single_item_takes_whole_silver_only", function()
    local M = load()
    AHW.Open()
    T.eq(M.Post.Step("item"), 100)
    T.eq(M.Post.Step("commodity"), 1)
    T.eq(M.Post.Round(4999, "item"), 5000, "up, like the game's own box")
    T.eq(M.Post.Round(4999, "item", true), 4900, "down: an undercut")
    T.eq(M.Post.Round(4999, "commodity", true), 4999)
    T.isnil(M.Post.Round(nil, "item"))
    T.deq({ click(function() return M.Post.Send("2207", 1, 4999, 24) end) }, { false, "silver" })
    T.deq({ click(function() return M.Post.Send("2207", 1, 5000, 24, nil, 2550) end) }, { false, "silver" }, "a bid too")
    T.eq(AHW.Calls("PostItem"), 0, "nothing sent")
    local w = watcher()
    T.eq(click(function() return M.Post.Send("2207", 1, 4900, 24, w.fn) end), true)
    AHW.Settle()
    T.deq(w.done, { { true } })
    quiet()
end)

-- Any other single item takes copper: a player posted a Silver Rod at 4s 50c in
-- the game's own window, where the addon rounded it up to 5s (2026-11-12).
T.test("a_single_item_that_isnt_gear_or_a_recipe_takes_copper", function()
    local ROD = 6338
    local M = load({
        items = { [ROD] = { name = "Silver Rod", classID = 7 } },
        bags = { [0] = { { itemID = ROD, stackCount = 1, name = "Silver Rod" } } },
    })
    AHW.Open()
    T.eq(M.Post.Kind("6338"), "item")
    T.eq(M.Post.Step("item", "6338"), 1)
    T.eq(M.Post.Round(450, "item", false, "6338"), 450)
    T.eq(M.Post.Round(4999, "item", true, "2207"), 4900, "a sword still whole silver")
    local w = watcher()
    T.eq(click(function() return M.Post.Send("6338", 1, 450, 8, w.fn) end), true)
    AHW.Settle()
    T.deq(w.done, { { true } })
    quiet()
end)
