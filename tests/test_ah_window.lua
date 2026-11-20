local AHW = require("ahworld")
local stub = require("stub")

-- The Auction House window: the game's AuctionHouseFrame parked under the
-- window kit's veil with this window in its place, the game's own one click
-- away (Win.Swap), the game's own in a fight, the header's sub line, the
-- first-visit card and the scan band.

local RKEY = "US-PvE"
local LINEN = 2589

-- The game's AuctionHouseFrame as the game drives it (wow-ui-source, forever):
-- Blizzard_AuctionHouseUI_Bootstrap.lua registers it with the player
-- interaction manager, so PLAYER_INTERACTION_MANAGER_FRAME_SHOW (Auctioneer)
-- loads the addon on demand the first time (ADDON_LOADED inside the load,
-- before the show) and ShowUIPanel's it; _HIDE HideUIPanel's it. Its OnHide
-- calls C_AuctionHouse.CloseAuctionHouse(): hiding the frame closes the AH.
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

local function load(opts)
    opts = opts or {}
    local DUI, A = AHW.Load({ auctions = opts.auctions or {} }, {
        ruleset = opts.ruleset, prices = opts.prices,
        before = function()
            _G.AuctionHouseFrame = nil
            _G.DaylightMogul = opts.mogul and {} or nil
            gameAH()
        end,
    })
    _G.DaylightMogul = nil
    A.Replicate.SETTLE, A.Replicate.EMPTY_WAIT = 0, 0
    return A, DUI
end

-- One frame of the world: timers, then the follower's look.
local function frame(A, n)
    for _ = 1, n or 1 do
        AHW.Frame()
        DaylightUI.Win.Followers.Tick()
    end
end
local function settle(A)
    frame(A, 3)
    if A.Window.frame then stub.FinishFade(A.Window.frame) end
end

local function game() return rawget(_G, "AuctionHouseFrame") end
local function veil() return DaylightUI.Win.Followers.veil end
local function click(b) b:GetScript("OnClick")(b, "LeftButton") end
local function plain(fs) return (stub.Text(fs):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

T.test("ah window: opens in place of the game's, on Buy, the game's frame under the veil", function()
    local A = load()
    AHW.Open()
    frame(A)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(A.Window.IsOpen(), "Daylight UI's window opens at the AH")
    T.eq(A.Window.frame.tab, "buy")
    T.eq(stub.Text(A.Window.frame.title), "Auction House")
    local g = game()
    T.truthy(g:IsShown(), "the game's frame stays shown: its OnHide would close the AH")
    T.eq(g:GetParent(), veil(), "parked under the veil as it loaded")
    T.truthy(AHW.IsOpen())
    -- the next visit: ours again, on Buy
    A.Window.ShowTab("sell")
    AHW.Close()
    settle(A)
    T.falsy(A.Window.IsOpen(), "the AH closing closes it")
    AHW.Open()
    frame(A)
    T.truthy(A.Window.IsOpen())
    T.eq(A.Window.frame.tab, "buy")
end)

T.test("ah window: closing it closes the AH, Esc too", function()
    local A = load()
    AHW.Open()
    frame(A)
    A.Window.Close()
    settle(A)
    T.falsy(AHW.IsOpen(), "an AH under the veil would be open and out of sight")
    T.falsy(game():IsShown())
    AHW.Open()
    frame(A)
    T.eq(A.Window.OnKey("ESCAPE"), true)
    settle(A)
    T.falsy(AHW.IsOpen())
    T.eq(A.Window.OnKey("A"), false, "other keys go on to the game")
end)

T.test("ah window: the swap icon hands the AH to the game's window, its link brings ours back", function()
    local A = load()
    AHW.Open()
    frame(A)
    local icon = A.Window.frame.swap
    T.truthy(icon, "the header's swap icon")
    click(icon)
    settle(A)
    T.eq(DaylightUI:Get("AuctionHouse", "enabled"), false, "the pick is kept")
    T.falsy(A.Window.IsOpen(), "ours closes")
    T.truthy(AHW.IsOpen(), "the AH stays open in the game's window")
    T.eq(game():GetParent(), UIParent)
    T.truthy(game():IsShown())
    local link = A.swap.link
    T.truthy(link and link:IsShown(), "the game's window has a way back")
    -- the next visit stays the game's
    AHW.Close()
    frame(A, 3)
    AHW.Open()
    frame(A, 3)
    T.falsy(A.Window.IsOpen())
    T.eq(game():GetParent(), UIParent, "left the game's while it's the pick")
    click(link)
    settle(A)
    T.eq(DaylightUI:Get("AuctionHouse", "enabled"), true)
    T.truthy(A.Window.IsOpen(), "ours is back, the AH still open")
    T.eq(game():GetParent(), veil())
    T.truthy(AHW.IsOpen())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ah window: the game's own AH in a fight, ours again after it", function()
    local A = load()
    stub.EnterCombat()
    AHW.Open()
    frame(A, 3)
    T.eq(game():GetParent(), UIParent, "not parked in the lockdown")
    T.falsy(A.Window.IsOpen())
    AHW.Close()
    frame(A)
    stub.LeaveCombat()
    frame(A)
    T.eq(game():GetParent(), veil(), "parked after the fight")
    stub.EnterCombat()
    frame(A)
    T.eq(game():GetParent(), UIParent, "a hidden frame goes back as a fight starts")
    stub.LeaveCombat()
    frame(A, 2)
    AHW.Open()
    frame(A)
    T.truthy(A.Window.IsOpen())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ah window: with DaylightMogul loaded nothing is built or parked", function()
    local A = load({ mogul = true })
    T.eq(A.mogul, true)
    AHW.Open()
    frame(A, 3)
    T.isnil(A.Window.frame)
    T.eq(game():GetParent(), UIParent, "Mogul's to park")
    local page = DaylightUI.Options.Page and DaylightUI.Options.Page("AuctionHouse.window")
    if page then T.eq(page.hidden(), true, "no options page") end
end)

T.test("ah window: the sub line says how fresh the prices are, with the Full scan link", function()
    local A = load()
    AHW.Open()
    frame(A)
    local f = A.Window.frame
    T.truthy(plain(f.sub):find("no prices yet", 1, true), plain(f.sub))
    T.truthy(A.Window.scanLink:IsShown(), "Full scan is there")
    A.Store.Record(RKEY, tostring(LINEN), 10, 20, A.Game.Now() - 7200)
    A.Fire("PricesChanged", RKEY)
    T.truthy(plain(f.sub):find("prices from 2 h ago", 1, true), plain(f.sub))
    T.truthy(plain(f.sub):find("1 item known", 1, true), plain(f.sub))
end)

T.test("ah window: the first-visit card offers a scan until Not now", function()
    local A = load()
    AHW.Open()
    frame(A)
    local card = A.Window.Offer()
    T.truthy(card and card:IsShown(), "no full scan yet: the card")
    click(card.later)
    settle(A)
    T.eq(A.Store.Offered(RKEY), true, "noted")
    T.falsy(A.Window.OfferWanted(), "not wanted")
    T.falsy(card:IsShown(), "Not now fades it away")
    T.eq(A.Store.Offered(RKEY), true, "and it stays away")
    A.Window.Close()
    settle(A)
    AHW.Open()
    frame(A)
    T.falsy(card:IsShown())
end)

T.test("ah window: a full scan opens the band and the card steps aside", function()
    local A = load({ auctions = { { itemID = LINEN, count = 20, buyout = 200 } } })
    AHW.Open()
    frame(A)
    click(A.Window.Offer().scan)
    T.truthy(A.Scan.Running(), "Scan now starts a full scan")
    T.eq(A.ScanBand.State(), "scanning")
    T.truthy(A.ScanBand.frame:IsShown())
    T.falsy(A.Window.OfferWanted())
    AHW.Settle()
    frame(A, 3)
    T.falsy(A.Scan.Running(), "the scan finished")
    T.eq(A.ScanBand.State(), "done")
    T.truthy(A.Store.FullScanAt(RKEY))
    T.falsy(A.Window.OfferWanted(), "a full scan done: no card")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ah window: opens on the tab picked in the options, or the one left open", function()
    local A, DUI = load()
    DUI:Set("AuctionHouse", "openOn", "sell")
    AHW.Open()
    frame(A)
    T.eq(A.Window.frame.tab, "sell")
    A.Window.ShowTab("auctions")
    A.Window.Close()
    settle(A)
    DUI:Set("AuctionHouse", "openOn", "last")
    AHW.Open()
    frame(A)
    T.eq(A.Window.frame.tab, "auctions", "the tab left open last time")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ah options: own section, and its buttons clear lists and prices", function()
    local A, DUI = load({ prices = true })
    local Options = DUI.Options
    local s = Options.Section("AuctionHouse")
    T.truthy(s, "the Auction House has its own section")
    T.eq(#s.pages, 3)
    local function button(label)
        for _, p in ipairs(s.pages) do
            for _, g in ipairs(p.groups) do
                for _, item in ipairs(g.items) do if item.label == label then return item end end
            end
        end
    end
    A.BuyPage.SetFavorite(LINEN, true)
    button("Clear favorites").func()
    T.deq(A.BuyPage.Favorites(), {})
    A.Store.Record(RKEY, tostring(LINEN), 100, 5, A.Game.Now())
    T.truthy(A.Store.Min(RKEY, tostring(LINEN)))
    button("Forget every price").func()
    T.isnil(A.Store.Min(RKEY, tostring(LINEN)))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
