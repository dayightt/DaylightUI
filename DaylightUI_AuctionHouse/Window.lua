-- The Auction House window: Buy, Sell and My auctions in Daylight UI's look,
-- shown in place of the game's AuctionHouseFrame.
--
-- The game's frame is held aside by the window kit (Win.Follow, aside):
-- it stays shown, see-through and tiny, never clipped, so every way the
-- game opens and closes the AH still runs only the game's own code. It must
-- stay shown: its OnHide calls C_AuctionHouse.CloseAuctionHouse(), so the
-- kit's hidden parent would close the AH as it was parked. The frame comes
-- from Blizzard_AuctionHouseUI, which the game loads the first time the AH
-- opens; the follower parks it as it loads, before its first show.
--
-- Parking happens only out of combat. As a fight starts a hidden frame is
-- handed back, so an AH opened in a fight is the game's own, parked again
-- once it closes after the fight. A window already open as a fight starts
-- stays.
--
-- Win.Swap gives the player the game's own window from the header's swap icon
-- (the setting "enabled"), and a link on the game's window brings this one
-- back. With DaylightMogul loaded none of this is built: Mogul owns the AH.

local _, ns = ...
local DUI = DaylightUI
local L = ns.L
local Win = DUI.Win
local Style = DUI.Style
local W = DUI.Widgets
local Parts = Win.Parts
local Motion = DUI.Motion

local Main = {}
ns.Window = Main

Main.NAME = "DaylightUIAuctionHouse"
Main.W, Main.H = 960, 642
Main.ICON = "Interface\\Icons\\INV_Misc_Coin_02"
Main.KIND = "ah"
Main.TABS = {
    { id = "buy", text = L["Buy"] },
    { id = "sell", text = L["Sell"] },
    { id = "auctions", text = L["My auctions"] },
}
Main.MONEY_X = -6           -- lines up with the X's icon, not its wider click box
Main.MONEY_Y = 1            -- up from the X's bottom onto the sub line's row
Main.AGE_TICK = 60          -- seconds between repaints of the sub line's age while open
Main.SEP = "  \194\183  "   -- "  ·  " between the sub line's parts
Main.LINK_BUSY = 0.35       -- the Full scan link while a scan runs
Main.OFFER_H = 64
Main.OFFER_EDGE = 16
Main.OFFER_PAD = 14

Main.opened = false   -- the AH opened the window, so the AH closing closes it

function ns.Setting(key)
    local mod = ns.module
    return mod and mod.db and mod.db[key]
end

local function pop(text) return Parts.Hex({ Style.Pop() }) .. text .. "|r" end

-- The game's frame, nil until the game loads it.
function Main.Game()
    local f = _G.AuctionHouseFrame
    return type(f) == "table" and f or nil
end

function Main.IsOpen()
    return Main.frame ~= nil and Win.IsOpen(Main.frame)
end

local function parked()
    return Main.follow ~= nil and Win.Followers.Parked(Main.follow, Main.KIND)
end

-- The AH is open and the game's frame is out of sight under this window.
function Main.Docked()
    return ns.AH.IsOpen() and parked()
end

-- ---------------------------------------------------------------------
-- Header: how fresh the prices are, how many are known, the Full scan link
-- ---------------------------------------------------------------------

-- The newest of the last full scan and the last sighting, nil when never.
function Main.PricesAt(rkey)
    local full, last = ns.Store.FullScanAt(rkey), ns.Store.LastAt(rkey)
    if type(full) ~= "number" then return last end
    if type(last) ~= "number" or full > last then return full end
    return last
end

-- "prices from 2 h ago  ·  3,412 items known  ·  " (the numbers in the accent).
-- The Full scan link follows the words.
function Main.SubText()
    local rkey = ns.Ruleset.Key()
    local at = rkey and Main.PricesAt(rkey)
    if not at then return L["no prices yet"] end
    local age = ns.Ago(math.max(0, ns.Game.Now() - at))
    local n = Main.known or ns.Store.Count(rkey)
    return string.format(L["prices from %s ago"], pop(age)) .. Main.SEP
        .. string.format(n == 1 and L["%s item known"] or L["%s items known"], pop(ns.Thousands(n)))
end

function Main.Header()
    local f = Main.frame
    if not f then return end
    -- fading out with the AH: it keeps the words it had
    if f:IsShown() and not Win.IsOpen(f) then return end
    local scan = ns.Ruleset.Key() ~= nil
    Win.SetTitle(f, AUCTION_HOUSE or L["Auction House"], nil, Main.SubText() .. (scan and Main.SEP or ""))
    Style.InkText(f.sub, "LABEL")
    local link = Main.scanLink
    if not link then return end
    if scan then
        local w = f.sub:GetStringWidth()
        link:ClearAllPoints()
        link:SetPoint("LEFT", f.sub, "LEFT", math.ceil(type(w) == "number" and w or 0), 0)
        Motion.AlphaTo(link, ns.Scan.Running() and Main.LINK_BUSY or 1, f:IsVisible() and Motion.FAST or 0)
    else
        Motion.AlphaTo(link, 0, f:IsVisible() and Motion.FAST or 0, true)
    end
end


-- Your gold on the header's second line, under the X.
-- A change counts to the new amount.
local moneyKey = {}
function Main.PaintMoney(instant)
    local f = Main.frame
    if not (f and f.money) then return end
    local now = GetMoney and GetMoney() or 0
    if issecretvalue and issecretvalue(now) then return end
    local was = f.moneyShown
    f.moneyShown = now
    local function show(v) f.money:SetText(W.Money(math.floor(v + 0.5))) end
    if instant or not was or was == now or not f:IsVisible() then
        Motion.Tween(moneyKey, now, now, 0, show)
    else
        Motion.Tween(moneyKey, was, now, Motion.NORMAL, show)
    end
end

-- The sub line's items-known number counts up after a scan.
function Main.CountKnown(from, to)
    if from == to then return end
    Motion.Tween(Main, from, to, Motion.SLOW, function(v)
        Main.known = math.floor(v + 0.5)
        Main.Header()
    end, function()
        Main.known = nil
        Main.Header()
    end)
end

-- ---------------------------------------------------------------------
-- The first-visit card: at the top of Buy, at the Auction House, while the
-- ruleset has no full scan and the player hasn't said Not now.
-- ---------------------------------------------------------------------

function Main.Offer()
    local page = Main.frame and Main.frame.pages.buy
    return page and page.offer or nil
end

local function offerText()
    local strong = Parts.Hex(Style.INK.VALUE) .. L["No prices yet."] .. "|r"
    return string.format(L["%s A full scan reads the whole Auction House in about a minute, so every item gets a usual price and a tooltip line. The game allows one every %d minutes."],
        strong, math.floor(ns.Scan.FULL_COOLDOWN / 60))
end

local function offerable()
    local rkey = ns.Ruleset.Key()
    return rkey ~= nil and ns.Store.FullScanAt(rkey) == nil and not ns.Store.Offered(rkey)
end

function Main.OfferWanted()
    return ns.AH.IsOpen() and offerable() and not ns.Scan.Running()
end

-- Shows or hides the card, eased; instant: before the window opens.
function Main.PaintOffer(instant)
    local card = Main.Offer()
    if not card then return end
    card.text:SetText(offerText())
    Style.InkText(card.text, "TEXT")
    local want = Main.OfferWanted()
    if want ~= card.want then
        card.want = want
        -- unseen: at once, so it's right when the window comes up
        local dur = (instant or not Main.IsOpen()) and 0 or Motion.FAST
        Motion.AlphaTo(card, want and 1 or 0, dur, true)
    end
    ns.Fire("OfferChanged", want)
end

function Main.NotNow()
    if ns.Scan.Running() then return end
    ns.Store.MarkOffered(ns.Ruleset.Key())
    Main.PaintOffer()
end

-- The header's Full scan and the card's Scan now: the band shows it, or why not.
function Main.FullScan()
    if ns.Scan.Running() then return end
    local ok, why = ns.Scan.Full()
    if not ok and ns.ScanBand then ns.ScanBand.Refuse(why) end
end

function Main.BuildOffer(page)
    local card = CreateFrame("Frame", nil, page)
    -- over the right pane only: the categories stay in reach beside it
    local left = ns.BuyPage and ns.BuyPage.LEFT_W and ns.BuyPage.LEFT_W + 1 or 0
    card:SetPoint("TOPLEFT", page, "TOPLEFT", left + Main.OFFER_EDGE, -12)
    card:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Main.OFFER_EDGE, -12)
    card:SetHeight(Main.OFFER_H)
    card:SetFrameLevel(page:GetFrameLevel() + 5)
    Style.Shell(card, {})
    card.later = W.Button(card, L["Not now"], 24)
    card.later.FitWidth(90)
    card.later:SetPoint("RIGHT", card, "RIGHT", -Main.OFFER_PAD, 0)
    card.later:SetScript("OnClick", function() Main.NotNow() end)
    card.scan = W.Button(card, L["Scan now"], 24)
    card.scan.FitWidth(90)
    Parts.Tone(card.scan, "main")
    card.scan:SetPoint("RIGHT", card.later, "LEFT", -8, 0)
    card.scan:SetScript("OnClick", function() Main.FullScan() end)
    card.text = Style.Text(card, Style.SIZE.body, "LEFT")
    card.text:SetWordWrap(true)
    card.text:SetPoint("TOPLEFT", card, "TOPLEFT", Main.OFFER_PAD, -12)
    card.text:SetPoint("RIGHT", card.scan, "LEFT", -12, 0)
    card:Hide()
    card.want = false
    page.offer = card
    return card
end

function Main.ScanChanged()
    Main.PaintOffer()
    Main.Header()
end

-- ---------------------------------------------------------------------
-- Tabs and pages
-- ---------------------------------------------------------------------

function Main.ShowTab(id)
    local f = Main.frame
    if not f then return end
    Main.tab = id
    ns.DB.Prices().lastTab = id
    Win.PickTab(f, id)
    Win.ShowPage(f, id)
    ns.Fire("TabShown", id)
end

-- Each tab's page file builds it (BuyPage.lua, SellPage.lua, AuctionsPage.lua);
-- the Buy page also carries the first-visit card.
local PAGE_FILES = { buy = "BuyPage", sell = "SellPage", auctions = "AuctionsPage" }
local function pageOf(id)
    local function P() return ns[PAGE_FILES[id]] end
    return {
        Build = function(page)
            if id == "buy" then Main.BuildOffer(page) end
            local p = P()
            if p and p.Build then p.Build(page) end
        end,
        Fill = function() local p = P(); if p and p.Fill then p.Fill() end end,
        w = Main.W, h = Main.H,
    }
end

-- The key binding: the shown tab's main action in the key press (a hardware
-- event, like a click): Buy's buy or confirm, Sell's Post, My auctions' Cancel.
function Main.Key()
    if not Main.IsOpen() then return end
    local id = Main.frame.tab
    local p = ns[PAGE_FILES[id] or ""]
    if p and p.Key then p.Key() end
end

-- While the window is open, Esc closes an open menu first, then the window.
function Main.OnKey(key)
    if key ~= "ESCAPE" then return false end
    if W.menuOwner then
        W.CloseMenu()
        return true
    end
    Main.Close()
    return true
end

-- ---------------------------------------------------------------------
-- Open, close, follow the game's frame
-- ---------------------------------------------------------------------

local function spot() return Main.spot and Main.spot.Get() end

local function place(f)
    local s = spot()
    if s then return Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
end

function Main.SaveSpot(x, y)
    if Main.spot then Main.spot.Save(x, y) end
end

function Main.ResetSpot()
    if Main.spot then Main.spot.Reset() end
end

function Main.Apply()
    local f = Main.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end
    Win.Repaint(f)
    if Main.follow then Win.Followers.WriteWidth(Main.follow) end
    if Win.IsOpen(f) then
        Main.Header()
        Main.PaintOffer()
    end
end

-- The tab the window opens on: the player's pick, or the one left last time.
function Main.FirstTab()
    local pick = ns.Setting("openOn")
    if pick == "last" then pick = ns.DB.Prices().lastTab end
    for _, t in ipairs(Main.TABS) do if t.id == pick then return pick end end
    return "buy"
end

function Main.Open()
    local f = Main.frame
    if not f then return end
    Main.Header()
    if Win.IsOpen(f) then return end
    place(f)
    Main.ShowTab(Main.FirstTab())
    if ns.ScanBand then ns.ScanBand.Sync() end
    Main.PaintOffer(true)
    Win.Open(f)
    Main.Header()
    Win.KeysOn(f, true)
    if Main.ageTicker then Main.ageTicker:Cancel() end
    Main.ageTicker = C_Timer.NewTicker(Main.AGE_TICK, function() Main.Header() end)
    ns.Fire("WindowOpened")
end

-- Ours goes now. lending: the game's frame shows instead, so the AH stays open.
local function shut(lending)
    local f = Main.frame
    if not f then return end
    Main.opened = false
    Win.KeysOn(f, false)
    if Main.ageTicker then Main.ageTicker:Cancel() end
    Main.ageTicker = nil
    if not Win.IsOpen(f) then return end
    W.CloseMenu()
    Win.Shut(f)
    ns.Fire("WindowClosed")
    if not lending and Main.Docked() then ns.AH.Close() end
end

-- The X, Esc: ours goes, and the AH with it (its window is out of sight).
function Main.Close() shut(false) end

-- The AH is open with the game's frame parked: this window, on Buy. Asked on
-- AHOpened and again when the follower sees the frame show (the game's order
-- of AUCTION_HOUSE_SHOW and the frame's show is its own).
-- Shift-clicking an item while the AH is open puts its name in the game's
-- search box (the game's ChatFrameUtil.InsertLink, which only asks whether
-- AuctionHouseFrame is visible, and held aside it is). This window sits in
-- its place, so it takes the name from there and searches it on Buy.
local watchedBox
function Main.WatchLinks()
    local g = Main.Game()
    local bar = g and g.SearchBar
    local box = type(bar) == "table" and bar.SearchBox
    if type(box) ~= "table" or box == watchedBox or type(box.HookScript) ~= "function" then return end
    watchedBox = box
    box:HookScript("OnTextChanged", function(b, typed)
        if typed or not (Main.IsOpen() and Main.Docked()) then return end
        local text = b:GetText()
        if type(text) ~= "string" or text == "" then return end
        -- Emptied again, so the same item Shift-clicked later is a change
        -- too. Whether the client runs this script for unchanged text isn't
        -- known, and nobody sees this box while it's parked.
        b:SetText("")
        if Main.frame.tab ~= "buy" then Main.ShowTab("buy") end
        ns.BuyPage.Submit(text, true)
    end)
end

function Main.Take()
    Main.WatchLinks()
    if not Main.Docked() then return end   -- in a fight, or the game's is picked
    if Main.IsOpen() then return end
    Main.opened = true
    Main.Open()
end

-- The AH closed or its frame hid: ours goes if the AH opened it.
function Main.Left()
    if not Main.opened then return end
    if Main.IsOpen() then shut(true) end
    Main.opened = false
end

-- Follower callback. away: another addon took the game's frame while it
-- shows; ours steps aside and the AH stays open for that addon.
function Main.Changed(_, shown, away)
    if shown then return Main.Take() end
    if away then
        if Main.IsOpen() then shut(true) end
        return
    end
    Main.Left()
end

-- Which window: Daylight UI's or the game's own (Win.Swap).
-- Picked the game's: an open AH is handed over as it is and ours closes.
function Main.GiveAway()
    local def = Main.follow
    if not def then return end
    if InCombatLockdown() then return DUI.AfterCombat(Main.GiveAway, "ah:giveaway") end
    local open = Main.IsOpen()
    if Win.Followers.Release(def, Main.KIND) and open then shut(true) end
end

-- Picked this one: an open game AH is held aside again and ours opens.
function Main.TakeBack()
    local def = Main.follow
    if not def or not ns.swap or not ns.swap.Ours() then return end
    if InCombatLockdown() then return DUI.AfterCombat(Main.TakeBack, "ah:takeback") end
    local g = Main.Game()
    if g and g:IsShown() and not parked() and Win.Followers.Reclaim(def, Main.KIND) then Main.Take() end
end

function Main.Pick(ours)
    if ours and not Main.frame then Main.Build(ns.module) end
    if not Main.follow then return end
    if ours then Main.TakeBack() else Main.GiveAway() end
end

-- The game's frame sits under this window, or will when the AH opens, so the
-- Skins leave it alone.
function Main.Covers()
    if not (Main.follow and ns.swap and ns.swap.Ours()) then return false end
    local g = Main.Game()
    return not (g and g:IsShown() and not parked())
end

-- The game's frame keeps listening while it's parked, so a price warning or
-- error on a post from this window also runs the game's own answer: it lays
-- its DialogOverlay (an invisible button over everything below the title) on
-- the hidden frame and asks with its own pop-up, whose OnHide takes it off.
-- When that pop-up is gone, or never came up, the overlay stays, and the
-- game's window handed back to the player can't be clicked. So it comes off
-- as the frame goes back, unless one of the game's dialogs is still up.
local AH_POPUPS = { "BUYOUT_AUCTION", "BID_AUCTION", "CANCEL_AUCTION", "AUCTION_HOUSE_POST_WARNING", "AUCTION_HOUSE_POST_ERROR" }

local function dialogUp(g)
    local buy = g.BuyDialog
    if type(buy) == "table" and buy:IsShown() then return true end
    local visible = _G.StaticPopup_Visible
    if type(visible) ~= "function" then return false end
    local list = type(_G.AUCTION_HOUSE_STATIC_POPUPS) == "table" and _G.AUCTION_HOUSE_STATIC_POPUPS or AH_POPUPS
    for _, which in ipairs(list) do
        if visible(which) then return true end
    end
    return false
end

function Main.ClearOverlay(g)
    local over = type(g) == "table" and g.DialogOverlay
    if type(over) ~= "table" or not over:IsShown() or dialogUp(g) then return end
    if type(g.SetDialogOverlayShown) == "function" then g:SetDialogOverlayShown(false) else over:Hide() end
end

-- Follower callback: the game's frame was parked (parked true) or handed back.
function Main.Parked(_, g, isParked)
    if not isParked then Main.ClearOverlay(g) end
end

-- A fight starts: a hidden game frame goes back for the fight.
function Main.FightStarts()
    if Main.follow then Win.Followers.Unpark(Main.follow, Main.KIND) end
end

-- Made at login, before the window, which is built only while it's the pick.
function Main.InitSwap()
    if ns.swap then return end
    DUI.ahCovers = Main.Covers   -- the Skins leave the game's frame alone while this is true
    ns.swap = Win.Swap({
        scope = "AuctionHouse",
        game = Main.Game,
        addon = "Blizzard_AuctionHouseUI",
        blocked = function() return ns.mogul == true end,
        apply = Main.Pick,
    })
end

function Main.Build(mod)
    ns.module = mod or ns.module
    if Main.frame then return Main.frame end
    local f = Win.New({ name = Main.NAME, escape = false, back = "AuctionHouse", w = Main.W, h = Main.H, portrait = true })
    Main.frame = f
    f.onClose = Main.Close
    Main.spot = Win.Spot(f, function() return ns.module and ns.module.db end, place)
    Win.SetIcon(f, Main.ICON)
    if ns.swap then ns.swap.Icon(f) end
    for _, t in ipairs(Main.TABS) do Win.AddPage(f, t.id, pageOf(t.id)) end
    for _, t in ipairs(Main.TABS) do Win.Build(f, t.id) end
    Win.Tabs(f, Main.TABS, function(id) Main.ShowTab(id) end)
    -- On a controller X posts on the Sell page, whose Post button sits in its
    -- own box rather than a footer; the other pages' footers answer X as usual.
    f.padKeys = {
        { key = "X", follow = true,
          label = function() local b = ns.SellPage.PostButton(); return b and b.text:GetText() end,
          when = function() return ns.SellPage.PostButton() ~= nil end,
          run = function() ns.SellPage.Key() end },
        DUI.Pad.FOOTER_KEY,
    }
    local link = W.Link(f, Style.SIZE.small)
    link.SetLabel(L["Full scan"])
    link:SetScript("OnClick", function() Main.FullScan() end)
    link:Hide()
    Main.scanLink = link
    f.money = Style.Text(f, Style.SIZE.small, "RIGHT")
    -- Your gold sits under the X, beside the sub line: the tabs fill the row above
    -- and each page's footer buttons fill the bottom edge.
    f.money:SetPoint("TOPRIGHT", f.close, "BOTTOMRIGHT", Main.MONEY_X, Main.MONEY_Y)
    f.money:SetWordWrap(false)
    Main.PaintMoney(true)
    if ns.ScanBand then ns.ScanBand.Build(f) end
    Win.Keys(f, Main.OnKey)
    Win.Drag(f, { save = Main.SaveSpot, reset = Main.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("AuctionHouse", "scale", v) end)
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Main.ResetSpot
    Main.follow = Win.Follow({ key = "auctionhouse", frames = { [Main.KIND] = Main.Game }, aside = { [Main.KIND] = true },
        changed = Main.Changed, onPark = Main.Parked,
        leave = function() return not (ns.swap and ns.swap.Ours()) end,
        width = function() return Main.W * Win.Scale(ns.Setting("scale")) end })
    Main.Apply()
    return f
end

-- The sub line and the card follow the ruleset, the prices and the AH.
local function repaint()
    Main.Header()
    Main.PaintOffer()
end
ns.On("RulesetChanged", repaint)
ns.On("PricesChanged", function() Main.Header() end)
ns.On("AHOpened", function()
    repaint()
    Main.PaintMoney(true)
    Main.Take()
end)
ns.RegisterEvent("PLAYER_MONEY", function() Main.PaintMoney() end)
ns.On("AHClosed", function() Main.Left() end)
ns.On("ScanStarted", function() Main.ScanChanged() end)
ns.On("ScanEnded", function() Main.ScanChanged() end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() Main.FightStarts() end)

-- A right click or Alt-click on a bag item while this window has the Auction
-- House: it goes on Sell, as the game's own window takes it. The bagClick
-- setting says which clicks count ("right", "alt" or "both"); nil is any.
-- True when it was taken.
function Main.SellFromBag(bag, slot, click)
    if not (Main.IsOpen() and Main.Covers()) then return false end
    local want = ns.Setting and ns.Setting("bagClick") or "both"
    if click and want ~= "both" and want ~= click then return false end
    local key = ns.Bags.KeyAt(bag, slot)
    if not key then return false end
    Main.ShowTab("sell")
    if not ns.SellPage.Row(key) then return false end
    ns.SellPage.Pick(key, true)
    return true
end
DUI.AuctionHouseSell = Main.SellFromBag

-- The key binding (Bindings.xml): Post or Cancel the next one.
_G.BINDING_NAME_DAYLIGHTUI_AH_ACT = L["Auction House: post or cancel the next one"]
DUI.AuctionHouseKey = Main.Key
