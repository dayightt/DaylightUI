-- Vendor page of the NPC window: item tiles two per row, a search, Shop and Buy back
-- tabs, a strip with the last item sold, and Sell junk, Repair and Goodbye at the
-- bottom. The player's money sits in the header and rolls to its new value.
--
-- MerchantFrame is parked under the kit's veil (Npc.VEIL) so it is really shown and its
-- OnShow (opens bags, resets the filter), OnHide (CloseMerchant, closes bags) and other
-- addons' hooks still run (Mainline/MerchantFrame.lua). Buying only ever goes through
-- the game's functions: BuyMerchantItem, PickupMerchantItem, BuybackItem,
-- C_MerchantFrame.SellAllJunkItems, RepairAllItems.

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc
local L = DUI.L
local Style = DUI.Style

local Shop = {}
ns.Shop = Shop

Shop.W = 520                        -- window width while the shop is open
Shop.HIGH = 1500000                 -- the game's MERCHANT_HIGH_PRICE_COST; pricier items need a second click
Shop.CONFIRM = DUI.Widgets.CONFIRM
Shop.BAD = Style.INK.BAD          -- unaffordable or unusable (text)
Shop.PRICE = Style.INK.MONEY       -- affordable price
Shop.BAD_ICON = { 0.95, 0.15, 0.12 } -- unusable, tinted over the icon (a softer tint disappears on the art; the game uses 0.9, 0, 0)
Shop.ROLL = 0.45                    -- s for the money to roll to its new value
Shop.DOWN = Style.INK.TEXT         -- money going down
Shop.UP = Style.INK.GOOD           -- money going up
Shop.GHOST = 0.7                    -- s for the "-25c" floating off a bought tile
Shop.BAGS = 4                       -- junk is read from bags 0-4

local Win = DUI.Win
local Parts = Win.Parts

Shop.LAST_PAD = 4                   -- last-sold strip: padding inside the shell
Shop.LAST_H = Parts.LINE + 2 * Shop.LAST_PAD
Shop.LAST_LIFT = 4                  -- gap above the footer rule
Shop.LAST_GAP = 6                   -- gap between the shelf and the strip

local function fn(f) return type(f) == "function" end
local function call(f, ...) if fn(f) then return f(...) end end
local function now() return fn(GetTime) and GetTime() or 0 end

local S = { tab = "shop", filter = "", confirm = nil }
Shop.state = S

-- Reading the shop

-- Item quality from its link. Uncached items still carry it in the color tag (|cnIQ<n>:).
local function qualityOf(link)
    if type(link) ~= "string" then return nil end
    local tag = tonumber(link:match("|cnIQ(%d+):"))
    if not C_Item then return tag end
    if fn(C_Item.GetItemQualityByID) then
        local ok, q = pcall(C_Item.GetItemQualityByID, link)
        if ok and type(q) == "number" then return q end
    end
    if fn(C_Item.GetItemInfo) then
        local ok, _, _, q = pcall(C_Item.GetItemInfo, link)
        if ok and type(q) == "number" then return q end
    end
    return tag
end
Shop.QualityOf = qualityOf

function Shop.Items()
    local out = {}
    for i = 1, call(GetMerchantNumItems) or 0 do
        local info = C_MerchantFrame and fn(C_MerchantFrame.GetItemInfo) and C_MerchantFrame.GetItemInfo(i)
        if type(info) == "table" and info.name then
            local link = call(GetMerchantItemLink, i)
            out[#out + 1] = { index = i, name = info.name, texture = info.texture, price = info.price or 0,
                stack = info.stackCount or 1, available = info.numAvailable or -1, usable = info.isUsable ~= false,
                extended = info.hasExtendedCost == true, link = link, quality = qualityOf(link) }
        end
    end
    return out
end

function Shop.Buyback()
    local out = {}
    for i = 1, call(GetNumBuybackItems) or 0 do
        local name, texture, price, count = call(GetBuybackItemInfo, i)
        if name then
            local link = call(GetBuybackItemLink, i)
            out[#out + 1] = { index = i, name = name, texture = texture, price = price or 0, stack = count or 1,
                usable = true, link = link, quality = qualityOf(link), buyback = true }
        end
    end
    return out
end

-- Gray items in the bags and what they sell for. Cached until the bags change
-- (Shop.BagsChanged on BAG_UPDATE_DELAYED), since money and item-info events refill the
-- shelf often. Prices that haven't loaded aren't cached, so they get read again.
function Shop.Junk()
    local kept = Shop.junk
    if kept then return kept[1], kept[2] end
    local n, value, whole = 0, 0, true
    if not (C_Container and fn(C_Container.GetContainerNumSlots) and fn(C_Container.GetContainerItemInfo)) then return 0, 0 end
    for bag = 0, Shop.BAGS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.quality == 0 and not info.hasNoValue
                and not (DUI.ItemLocked and DUI.ItemLocked(info.itemID)) then
                n = n + 1
                local sell
                if C_Item and fn(C_Item.GetItemInfo) then
                    local ok
                    ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, info.hyperlink or info.itemID)
                    if not ok then sell = nil end
                end
                if type(sell) == "number" then value = value + sell * (info.stackCount or 1) else whole = false end
            end
        end
    end
    if whole then Shop.junk = { n, value } end
    return n, value
end

function Shop.BagsChanged() Shop.junk = nil end
DUI.On("ItemLockChanged", function()
    Shop.junk = nil
    if ns.Window.state.mode == "merchant" then Shop.Refresh() end
end)

function Shop.Repair()
    if not call(CanMerchantRepair) then return 0 end
    local cost, can = call(GetRepairAllCost)
    if can and type(cost) == "number" then return cost end
    return 0
end

local function money() return call(GetMoney) or 0 end

-- Actions

Shop.STACKS = 10       -- most stacks the amount box buys in one go
Shop.STACK_STEP = 0.2  -- s between those stacks' purchases

-- Room for that many more stacks: free bag slots, between one and Shop.STACKS.
local function stacksRoom()
    if not (C_Container and fn(C_Container.GetContainerNumFreeSlots)) then return Shop.STACKS end
    local free = 0
    for bag = 0, Shop.BAGS do
        local ok, n = pcall(C_Container.GetContainerNumFreeSlots, bag)
        if ok and type(n) == "number" then free = free + n end
    end
    return math.max(1, math.min(Shop.STACKS, free))
end

-- Max of an item one purchase can take, and how many the player can buy in all.
-- Same math as the game's MerchantItemButton_BuyMultipleStacks (money, plus bag counts
-- for items paid in items), but past one stack: the rest is bought a stack at a time.
function Shop.MaxOf(it)
    local per = math.max(1, it.stack)
    local max
    if ns.Window.state.sample then max = per > 1 and per * 4 or 1 else max = call(GetMerchantItemMaxStack, it.index) or 1 end
    local afford = max
    if it.price > 0 then afford = math.floor(Shop.MoneyNow() / (it.price / per)) end
    if it.extended and not ns.Window.state.sample and fn(GetMerchantItemCostItem) and C_Item and fn(C_Item.GetItemCount) then
        for i = 1, MAX_ITEM_COST or 3 do
            local _, value, link, currency = GetMerchantItemCostItem(it.index, i)
            if link and not currency and type(value) == "number" and value > 0 then
                afford = math.min(afford, math.floor(C_Item.GetItemCount(link, false, false, true) / (value / per)))
            end
        end
    end
    local most = max > per and max * stacksRoom() or max
    return max, math.min(most, afford)
end

-- Buys n of an item, at most one stack per purchase, the next a moment after the last.
-- Stops if the shop closes on the way.
function Shop.BuyLots(it, n)
    local max = Shop.MaxOf(it)
    local per = math.max(1, it.stack)
    local chunk = math.max(per, math.floor(max / per) * per)
    local index = it.index
    local function step(left)
        local take = math.min(left, chunk)
        BuyMerchantItem(index, take)
        if left > take then
            C_Timer.After(Shop.STACK_STEP, function()
                local m = _G.MerchantFrame
                if type(m) == "table" and m:IsShown() then step(left - take) end
            end)
        end
    end
    step(n)
end

local function ghost(tile, text)
    local f = ns.Window.frame
    local g = Shop.ghostText
    if not g then
        g = Style.Text(f, Style.SIZE.body, "RIGHT")
        g:SetDrawLayer("OVERLAY", 7)
        Shop.ghostText = g
    end
    g:SetText(text)
    g:SetTextColor(Shop.DOWN[1], Shop.DOWN[2], Shop.DOWN[3])
    g:ClearAllPoints()
    g:SetPoint("RIGHT", tile, "RIGHT", -8, 0)
    local M = DUI.Motion
    if not (M and M.On()) then g:SetAlpha(0); return end
    M.Tween(g, 0, 1, Shop.GHOST, function(p)
        g:SetAlpha(p < 0.2 and p / 0.2 or 1 - (p - 0.2) / 0.8)
        g:SetPoint("RIGHT", tile, "RIGHT", -8, 4 + 14 * p)
    end, function() g:SetAlpha(0) end)
end

Shop.Ghost = ghost   -- the trainer's "-90s" too

local function short(c)
    if not DUI.MoneyString then return tostring(c) end
    return DUI.MoneyString(c)
end

-- Cost of an item paid in items or currency, as MerchantFrame_UpdateAltCurrency shows it:
-- each piece as count and icon, after the money if there is any.
function Shop.CostText(it)
    local parts = {}
    if it.price > 0 then parts[1] = short(it.price) end
    if it.extended and not ns.Window.state.sample and fn(GetMerchantItemCostItem) then
        for i = 1, MAX_ITEM_COST or 3 do
            local texture, value = GetMerchantItemCostItem(it.index, i)
            if texture and type(value) == "number" and value > 0 then
                parts[#parts + 1] = value .. " |T" .. texture .. ":0:0:0:0:64:64:5:59:5:59|t"
            end
        end
    end
    if #parts == 0 then return it.extended and L["Special cost"] or "" end
    return table.concat(parts, "  ")
end

-- How much the player holds of each thing the shelf costs, shown next to the money.
-- The game's shop only shows tokens at the bottom; this shows every cost, items too.
-- list: the shelf Shop.Items() already read, or nil to read it here.
function Shop.Wallet(list)
    if ns.Window.state.sample or not fn(GetMerchantItemCostItem) then return "" end
    local parts, seen = {}, {}
    for _, it in ipairs(list or Shop.Items()) do
        if it.extended then
            for i = 1, MAX_ITEM_COST or 3 do
                local texture, _, link, currency = GetMerchantItemCostItem(it.index, i)
                if texture and link and not seen[link] then
                    seen[link] = true
                    local have
                    if currency then
                        local info = C_CurrencyInfo and fn(C_CurrencyInfo.GetCurrencyInfoFromLink) and C_CurrencyInfo.GetCurrencyInfoFromLink(link)
                        have = type(info) == "table" and info.quantity
                    elseif C_Item and fn(C_Item.GetItemCount) then
                        have = C_Item.GetItemCount(link, false, false, true)
                    end
                    if type(have) == "number" then
                        parts[#parts + 1] = have .. " |T" .. texture .. ":0:0:0:0:64:64:5:59:5:59|t"
                    end
                end
            end
        end
    end
    return table.concat(parts, "  ")
end

function Shop.PaintWallet(list)
    local fs = ns.Window.frame and ns.Window.frame.wallet
    if not fs then return end
    fs:SetText(Shop.Wallet(list))
    Style.InkText(fs, "pop")
end

-- n: amount from the quantity box; nil = one lot (plain click).
function Shop.Buy(it, tile, n)
    Shop.AskClose()
    local cost = it.price * (n and n / math.max(1, it.stack) or 1)
    if ns.Window.state.sample then
        if cost > Shop.MoneyNow() then
            if tile and DUI.Motion then DUI.Motion.Bump(tile, 0.97) end
            return
        end
        Shop.sampleMoney = Shop.MoneyNow() - cost
        if it.buyback then Shop.sampleSold = nil end
        Shop.RollMoney()
        if tile then ghost(tile, "-" .. short(cost)) end
        return Shop.Refresh()
    end
    if it.buyback then
        BuybackItem(it.index)
        return
    end
    if cost > money() then
        if tile and DUI.Motion then DUI.Motion.Bump(tile, 0.97) end
        return
    end
    -- Expensive items or ones paid in something else need a second click. The game would
    -- ask with its own popup, but that reads its own frame. The Buy button in the
    -- quantity box counts as the second click, since it shows the cost.
    if not n and (it.extended or it.price >= Shop.HIGH) and not (S.confirm and S.confirm.index == it.index and now() - S.confirm.at < Shop.CONFIRM) then
        S.confirm = { index = it.index, at = now() }
        if tile then
            tile.sub:SetText(L["Click again to buy"])
            Style.InkText(tile.sub, "WARN")   -- same armed look as every "click again"
        end
        return
    end
    S.confirm = nil
    if n then Shop.BuyLots(it, n) else BuyMerchantItem(it.index) end
    if tile then
        local spec = tile.spec
        Parts.PaintPick(tile, true, true)   -- one soft glow
        C_Timer.After(0.35, function() if tile.spec == spec then Parts.PaintPick(tile, false) end end)
        if cost > 0 then ghost(tile, "-" .. short(cost)) end
    end
end

-- Quantity box: Shift-click opens it over the tile, where the game's own shop opens
-- its box. - and + (or the wheel) step one lot, the number can be typed, and Buy shows
-- the total. Enter buys, Escape closes.

Shop.ASK_H = 40
Shop.ASK_NUM = 46     -- width of the number

local function askButton(box, text)
    return DUI.Widgets.Button(box, text, 24)
end

local function askBox()
    if Shop.box then return Shop.box end
    local f = ns.Window.frame
    local box = CreateFrame("Frame", nil, f)
    box:SetFrameLevel(f:GetFrameLevel() + 40)
    box:SetHeight(Shop.ASK_H)
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    box:EnableMouseWheel(true)
    box:Hide()
    Style.Shell(box)
    DUI.Pad.Popup(box, function() Shop.AskClose() end)
    box.less = askButton(box, "-")
    box.less:SetWidth(24)
    box.less:SetPoint("LEFT", box, "LEFT", 8, 0)
    local num = DUI.Widgets.Input(box, { height = 24, size = Style.SIZE.body, justify = "CENTER", numeric = true, maxLetters = 5,
        onChange = function(text, user)
            if user and S.ask then Shop.AskSet(tonumber(text) or 0, true) end
        end })
    num:SetWidth(Shop.ASK_NUM)
    num:SetPoint("LEFT", box.less, "RIGHT", 4, 0)
    box.num = num
    box.more = askButton(box, "+")
    box.more:SetWidth(24)
    box.more:SetPoint("LEFT", num, "RIGHT", 4, 0)
    box.buy = askButton(box, "")
    box.buy:SetPoint("LEFT", box.more, "RIGHT", 10, 0)
    box.buy.text:SetTextColor(Parts.YES[1], Parts.YES[2], Parts.YES[3], 1)
    box.close = askButton(box, "×")
    box.close:SetWidth(24)
    box.close:SetPoint("LEFT", box.buy, "RIGHT", 4, 0)

    local function step(d)
        local a = S.ask
        if a then Shop.AskSet(a.n + d * a.step) end
    end
    box.less:SetScript("OnClick", function() step(-1) end)
    box.more:SetScript("OnClick", function() step(1) end)
    box:SetScript("OnMouseWheel", function(_, d) step(d > 0 and 1 or -1) end)
    num:SetScript("OnMouseWheel", function(_, d) step(d > 0 and 1 or -1) end)
    box.buy:SetScript("OnClick", function() Shop.AskBuy() end)
    box.close:SetScript("OnClick", function() Shop.AskClose() end)
    -- Typing updates the cost; the number is cleaned up (whole lots, capped at what the
    -- player can afford) when editing ends.
    num:SetScript("OnEnterPressed", function() Shop.AskBuy() end)
    num:SetScript("OnEscapePressed", function() Shop.AskClose() end)
    num:HookScript("OnEditFocusLost", function(self) if S.ask then self:SetText(tostring(S.ask.n)) end end)
    Shop.box = box
    return box
end

function Shop.AskOpen() return S.ask ~= nil end

function Shop.AskSet(v, typing)
    local a, box = S.ask, Shop.box
    if not (a and box) then return end
    a.n = math.max(a.step, math.min(a.max, math.floor(v / a.step) * a.step))
    if not typing then box.num:SetText(tostring(a.n)) end
    box.less:SetAlpha(a.n > a.step and 1 or 0.45)
    box.more:SetAlpha(a.n < a.max and 1 or 0.45)
    local cost = a.it.price * a.n / a.step
    box.buy.text:SetText(cost > 0 and string.format(L["Buy · %s"], short(cost)) or L["Buy"])
    box.buy.FitWidth(96)
    box:SetWidth(8 + 24 + 4 + Shop.ASK_NUM + 4 + 24 + 10 + box.buy:GetWidth() + 4 + 24 + 8)
end

-- Over the tile, or a plain buy for things sold one at a time.
function Shop.Ask(it, tile)
    local per = math.max(1, it.stack)
    local most, afford = Shop.MaxOf(it)
    if most <= per then return Shop.Buy(it, tile) end
    if afford < per then return Shop.Buy(it, tile) end   -- can't afford: bump the tile
    local box = askBox()
    if S.ask and S.ask.it.index == it.index and box:IsShown() then return Shop.AskClose() end
    S.confirm = nil
    S.ask = { it = it, tile = tile, step = per, max = math.floor(afford / per) * per, n = per }
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", tile, "TOPLEFT", 0, 4)
    Shop.AskSet(per)
    box:Show()
    if DUI.Motion then DUI.Motion.Appear(box, 4) end
    if DUI.Pad.On() then return end   -- controllers step with - and +, no typing
    box.num:SetFocus()
    box.num:HighlightText()
end

-- More than one stack can be bought at once (the game's multi-buy).
function Shop.CanStack(it)
    if not it or it.buyback then return false end
    return (Shop.MaxOf(it)) > math.max(1, it.stack)
end

function Shop.AskBuy()
    local a = S.ask
    if not a then return end
    Shop.AskSet(tonumber(Shop.box.num:GetText()) or a.n)
    Shop.Buy(a.it, a.tile, a.n)
end

function Shop.AskClose()
    S.ask = nil
    local box = Shop.box
    if not box then return end
    box.num:ClearFocus()
    box:Hide()
end

-- The shelf refilled under an open box (money, bags or stock changed): follow the
-- item's tile with the new affordable amount, or close.
local function askFollow(tiles)
    local a = S.ask
    if not a then return end
    for _, t in ipairs(tiles or {}) do
        if t.spec and t.spec.index == a.it.index then
            local _, afford = Shop.MaxOf(a.it)
            if afford < a.step then break end
            a.tile, a.max = t, math.floor(afford / a.step) * a.step
            Shop.box:ClearAllPoints()
            Shop.box:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 0, 4)
            Shop.AskSet(a.n, Shop.box.num:HasFocus())
            return
        end
    end
    Shop.AskClose()
end

function Shop.Click(it, tile)
    if not it.buyback and IsShiftKeyDown and IsShiftKeyDown() then return Shop.Ask(it, tile) end
    Shop.Buy(it, tile)
end

function Shop.SellJunk()
    if ns.Window.state.sample then
        Shop.sampleJunk = 0
        Shop.sampleSold = { Shop.SAMPLE_SOLD }
        Shop.sampleMoney = (Shop.sampleMoney or 0) + 67
        Shop.RollMoney()
        return Shop.Refresh()
    end
    -- The game's sale takes every gray item; a locked one is just skipped.
    if DUI.SellJunkAroundLocks and DUI.SellJunkAroundLocks() then return end
    if C_MerchantFrame and fn(C_MerchantFrame.SellAllJunkItems) then C_MerchantFrame.SellAllJunkItems() end
end

function Shop.RepairAll()
    if ns.Window.state.sample then
        Shop.sampleRepair = 0
        Shop.sampleMoney = math.max(0, (Shop.sampleMoney or 0) - 160)
        Shop.RollMoney()
        return Shop.Refresh()
    end
    if Shop.Repair() > 0 and Shop.Repair() <= money() then
        RepairAllItems()
        DUI.Sound.Kit("ITEM_REPAIR", "confirms")   -- the game's Repair button plays it (MerchantFrame.xml)
    end
end

-- Header money: rolls to its new value, warm going down, green going up, then white.

function Shop.MoneyNow() return ns.Window.state.sample and (Shop.sampleMoney or 0) or money() end

function Shop.RollMoney(instant)
    local f = ns.Window.frame
    local fs = f and f.money
    if not fs then return end
    local to = Shop.MoneyNow()
    local from = Shop.shown or to
    Shop.shown = to
    local M = DUI.Motion
    if instant or from == to or not (M and M.On()) then
        fs:SetText(DUI.MoneyString and DUI.MoneyString(to) or tostring(to))
        Style.InkText(fs, "MONEY")
        return
    end
    local c = to < from and Shop.DOWN or Shop.UP
    M.Tween(fs, 0, 1, Shop.ROLL, function(p)
        fs:SetText(DUI.MoneyString(math.floor(from + (to - from) * p + 0.5)))
        local k = p < 0.6 and 1 or (1 - (p - 0.6) / 0.4)
        local m = Style.INK.MONEY
        fs:SetTextColor(m[1] + (c[1] - m[1]) * k, m[2] + (c[2] - m[2]) * k, m[3] + (c[3] - m[3]) * k)
    end, function() Style.InkText(fs, "MONEY") end)
end

-- The page

-- The game's shop cursor, rebuilt because the veiled frame never gets the mouse (see
-- MerchantFrame_OnUpdate, MerchantItemButton_OnEnter): coin bag, red when unaffordable,
-- the buyback one on that tab, the magnifier with the dressing-room key held.
-- Set again on tooltip refresh so the key and money state stay current.
function Shop.Cursor(it)
    if ns.Window.state.sample then return end
    if IsModifiedClick and IsModifiedClick("DRESSUP") then
        call(ShowInspectCursor)
    elseif it.buyback then
        call(ShowBuybackSellCursor, it.index)
    elseif fn(SetCursor) then
        SetCursor(fn(CanAffordMerchantItem) and CanAffordMerchantItem(it.index) == false and "BUY_ERROR_CURSOR" or "BUY_CURSOR")
    end
end

local function tooltip(it)
    return function(b)
        Shop.Cursor(it)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        if ns.Window.state.sample then
            GameTooltip:SetText(it.name or "")
        elseif it.buyback then
            if GameTooltip.SetBuybackItem then GameTooltip:SetBuybackItem(it.index) end
        elseif GameTooltip.SetMerchantItem then
            GameTooltip:SetMerchantItem(it.index)
            if fn(GameTooltip_ShowCompareItem) then GameTooltip_ShowCompareItem(GameTooltip) end
        end
        GameTooltip:Show()
        b.UpdateTooltip = tooltip(it)
    end
end

local function tiles(list)
    local out, cash = {}, Shop.MoneyNow()
    local want = S.tab == "shop" and S.filter ~= "" and string.lower(S.filter) or nil   -- search only applies to the shelf
    for _, it in ipairs(list) do
        if not want or string.find(string.lower(it.name), want, 1, true) then
            local dear = it.price > cash or (it.extended and not it.buyback and fn(CanAffordMerchantItem)
                and not ns.Window.state.sample and CanAffordMerchantItem(it.index) == false)
            local sub = it.buyback and (it.price > 0 and short(it.price) or "") or Shop.CostText(it)
            out[#out + 1] = { index = it.index, name = it.name, texture = it.texture, count = it.stack, quality = it.quality,
                sub = sub, subColor = (dear or not it.usable) and Shop.BAD or (it.price > 0 and Shop.PRICE) or nil,
                tint = not it.usable and Shop.BAD_ICON or nil, nameColor = not it.usable and Shop.BAD or nil,
                tooltip = tooltip(it), leave = function() call(ResetCursor) end, link = it.link and function() return it.link end or nil,
                onClick = function(b) Shop.Click(it, b) end, shopItem = it,
                onDrag = not it.buyback and not ns.Window.state.sample and function() call(PickupMerchantItem, it.index) end or nil }
        end
    end
    return out
end

-- Items sold, oldest first: the game's list or the sample shop's.
function Shop.Sold()
    if ns.Window.state.sample then return Shop.sampleSold or {} end
    return Shop.Buyback()
end

-- Strip above the footer, Shop tab only: the newest sale, one click from buyback, like
-- the slot on the game's shop (GetBuybackItemInfo(GetNumBuybackItems())). Only shown
-- once something is sold; the shelf glides up for it and back down after.
local function lastStrip(page)
    local last = CreateFrame("Frame", nil, page)
    last:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", Parts.EDGE, ns.Window.FOOT + Shop.LAST_LIFT)
    last:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Parts.EDGE, ns.Window.FOOT + Shop.LAST_LIFT)
    last:SetHeight(Shop.LAST_H)
    Style.Shell(last)
    -- no bottom inset: a Line's sub text runs slightly past its row and this list clips there
    last.stack = Parts.Stack(last, { top = Shop.LAST_PAD, bottom = 0, side = Shop.LAST_PAD })
    last.glide = {}
    last:Hide()
    return last
end

local function shelfBottom(page, on)
    local M, sf = DUI.Motion, page.stack.scroll
    local closed = ns.Window.FOOT
    local open = closed + Shop.LAST_LIFT + Shop.LAST_H + Shop.LAST_GAP
    M.Tween(page.last.glide, on and closed or open, on and open or closed, M.FAST, function(v)
        sf:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Parts.EDGE, v)
        page.stack.bar.Update()
    end)
end

function Shop.PaintLast(page)
    local last, sold = page.last, Shop.Sold()
    local it = S.tab == "shop" and sold[#sold] or nil
    local line
    if it then
        local buy = function(b) Shop.Buy(it, b) end
        last.stack:Begin()
        line = last.stack:Line({ icon = it.texture, text = it.name .. (it.stack > 1 and (" ×" .. it.stack) or ""),
            color = it.quality and { Parts.QualityColor(it.quality) } or nil, sub = L["Last sold"],
            value = it.price > 0 and short(it.price) or "", valueColor = it.price > Shop.MoneyNow() and Shop.BAD or Shop.PRICE,
            id = "last", link = it.link and function() return it.link end or nil,
            onClick = buy, onRightClick = buy,   -- any button buys back, like the game's
            tooltip = tooltip(it), leave = function() call(ResetCursor) end })
        last.stack:End()
        -- width passed in: the window may still be gliding wider or not laid out yet
        line:SetWidth(Shop.W - 2 * (Parts.EDGE + Shop.LAST_PAD))
    end
    local on = it ~= nil
    if on ~= (last.on or false) then
        last.on = on
        DUI.Motion.AlphaTo(last, on and 1 or 0, DUI.Motion.FAST, not on)
        shelfBottom(page, on)
    end
    -- A new sale lands with a soft glow; a buyback just shows the previous one.
    local who = it and (it.link or it.name)
    if line and last.n and (#sold > last.n or (#sold == last.n and who ~= last.who)) then Parts.Shine(line) end
    if who or #sold == 0 then last.n, last.who = #sold, who end
end

local TAB_H = 26

local function tabButton(page, id, label)
    local b = DUI.Widgets.Tab(page, label, { justify = "LEFT" })
    b.id = id
    b:SetHeight(TAB_H)
    b.FitWidth(4, 40)
    b:SetScript("OnClick", function(self)
        if S.tab == self.id then return end
        S.tab = self.id
        Shop.Show(true)
    end)
    return b
end

function Shop.Build(page)
    page.tabShop = tabButton(page, "shop", L["Shop"])
    page.tabShop:SetPoint("TOPLEFT", page, "TOPLEFT", Parts.EDGE, -8)
    page.tabBack = tabButton(page, "back", L["Buy back"])
    page.tabBack:SetPoint("LEFT", page.tabShop, "RIGHT", 18, 0)
    -- Search box; typing filters the shelf.
    local W = DUI.Widgets
    local box = W.Input(page, { search = true, hint = L["Search the shelf"],
        onChange = function(t)
            if t ~= S.filter then
                S.filter = t
                Shop.Refresh(true)
            end
        end })
    box:SetPoint("TOPLEFT", page, "TOPLEFT", Parts.EDGE, -8 - TAB_H - 8)
    box:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Parts.EDGE, -8 - TAB_H - 8)
    page.search = box
    page.stack = Parts.Stack(page, { top = 8 + TAB_H + 8 + W.INPUT_H + 6, bottom = ns.Window.FOOT })
    page.last = lastStrip(page)
    page.foot = Parts.Footer(page)
    page:HookScript("OnHide", function()
        Shop.AskClose()
        if DUI.APIReport then DUI.APIReport.ListClear("shoptile") end
    end)
end

function Shop.PaintTabs(page)
    for _, b in ipairs({ page.tabShop, page.tabBack }) do b.Pick(b.id == S.tab, true) end
    page.search:SetShown(S.tab == "shop")
end

function Shop.Fill(page)
    Shop.PaintTabs(page)
    local shelf = Shop.List()   -- read once for tiles and wallet
    Shop.PaintWallet(shelf)
    local s = page.stack
    s:Begin()
    local list = S.tab == "back" and Shop.Sold() or shelf
    if #list == 0 then
        s:Text(S.tab == "back" and L["Nothing sold yet. What you sell here can be bought back until you leave."]
            or L["Nothing here matches."], { color = Parts.DIM })
        Shop.AskClose()
    else
        local shown = s:Items(tiles(list))
        askFollow(shown)
        Shop.ReportTiles(shown)
    end
    if #list == 0 then Shop.ReportTiles({}) end
    page.pieces = s:End()
    table.insert(page.pieces, 1, page.tabShop)
    Shop.PaintLast(page)
    Shop.PaintFooter(page)
end

-- Visible tiles are passed to plugins (DaylightUI.API kind "shoptile", unit
-- "buy:<index>" or "buyback:<index>", API.ShopItem for details), then FrameStyled
-- fires for each on every fill (money, bags, stock, search).
local function itemID(link)
    if type(link) ~= "string" or not (C_Item and fn(C_Item.GetItemInfoInstant)) then return nil end
    local ok, id = pcall(C_Item.GetItemInfoInstant, link)
    return ok and type(id) == "number" and id or nil
end

function Shop.ReportTiles(shown)
    local R = DUI.APIReport
    if not R then return end
    local sample = ns.Window.state.sample and true or false
    for _, b in ipairs(shown) do
        local it = b.spec and b.spec.shopItem
        if it then
            local tab = it.buyback and "buyback" or "buy"
            R.Row("shoptile", b, tab .. ":" .. it.index,
                { tab = tab, index = it.index, id = itemID(it.link), link = it.link }, sample)
        end
    end
    R.ListDone("shoptile")
end

function Shop.List()
    if ns.Window.state.sample then return Shop.SAMPLE end
    -- Plugins' shop filters (DaylightUI.API) may leave items out.
    return DUI.APIReport.FilterShop(Shop.Items())
end

function Shop.PaintFooter(page)
    local sample = ns.Window.state.sample
    local junkN, junkV
    if sample then junkN, junkV = (Shop.sampleJunk or 0), (Shop.sampleJunk or 0) > 0 and 67 or 0 else junkN, junkV = Shop.Junk() end
    local repair = sample and (Shop.sampleRepair or 0) or Shop.Repair()
    local esc = ns.Setting("keys") ~= false and L["Esc"] or nil
    local list = { { text = junkN > 0 and string.format(L["Sell junk · %s"], short(junkV)) or L["Sell junk"],
        off = junkN == 0, onClick = Shop.SellJunk } }
    local canRepair = sample or call(CanMerchantRepair)
    if canRepair then
        list[#list + 1] = { text = repair > 0 and string.format(L["Repair · %s"], short(repair)) or L["Repair"],
            off = repair == 0 or repair > Shop.MoneyNow(), onClick = Shop.RepairAll }
    end
    list[#list + 1] = { text = L["Goodbye"], key = esc, onClick = ns.Window.Goodbye }
    page.foot:Set(list)
end

-- Refill in place (money, bags or stock changed, or hovered item info arrived): no
-- lift-in, scroll position kept. `top` = scroll to top (new search).
function Shop.Refresh(top)
    local f = ns.Window.frame
    local page = f and f.pages.shop
    if not (page and page:IsShown()) then return end
    local at = not top and page.stack:Scrolled() or 0
    Shop.Fill(page)
    page.stack:ScrollTo(at)
end

-- Tab switch: the shelf lifts in under the tabs, which stay put.
function Shop.Show(lift)
    local f = ns.Window.frame
    local page = f and f.pages.shop
    if not page then return end
    Shop.AskClose()
    Shop.Fill(page)
    if lift then Win.Feel.Stagger(page.pieces, 0) end
end

-- Each shop visit starts fresh. Bags and the game's filter are handled by its own
-- OnShow/OnHide, which still run on the veiled frame.
function Shop.Opened()
    S.tab, S.filter, S.confirm = "shop", "", nil
    Shop.junk = nil
    Shop.AskClose()
    local f = ns.Window.frame
    if f and f.pages.shop then f.pages.shop.search:SetText("") end
end

-- Sample shop (the sample talk's "Let me browse your goods")

local SAMPLE_ICON = 134400
Shop.SAMPLE = {
    { index = 1, name = L["Refreshing Spring Water"], texture = SAMPLE_ICON, price = 25, stack = 5, quality = 1, usable = true },
    { index = 2, name = L["Tough Jerky"], texture = SAMPLE_ICON, price = 25, stack = 5, quality = 1, usable = true },
    { index = 3, name = L["Freshly Baked Bread"], texture = SAMPLE_ICON, price = 125, stack = 5, quality = 1, usable = true },
    { index = 4, name = L["Simple Wood"], texture = SAMPLE_ICON, price = 38, stack = 1, quality = 1, usable = true },
    { index = 5, name = L["Flint and Tinder"], texture = SAMPLE_ICON, price = 135, stack = 1, quality = 1, usable = true },
    { index = 6, name = L["Coarse Thread"], texture = SAMPLE_ICON, price = 10, stack = 1, quality = 1, usable = true },
    { index = 7, name = L["Rough Arrow"], texture = SAMPLE_ICON, price = 10, stack = 200, quality = 1, usable = true },
    { index = 8, name = L["Small Brown Pouch"], texture = SAMPLE_ICON, price = 500, stack = 1, quality = 1, usable = true },
    { index = 9, name = L["Traveler's Backpack"], texture = SAMPLE_ICON, price = 25000, stack = 1, quality = 2, usable = true },
}

Shop.SAMPLE_SOLD = { index = 1, name = L["Coarse Thread"], texture = SAMPLE_ICON, price = 67, stack = 3, quality = 0, usable = true, buyback = true }

function Shop.StartSample()
    Shop.sampleMoney, Shop.sampleJunk, Shop.sampleRepair, Shop.sampleSold = 21435, 3, 160, nil
    Shop.shown = nil
end

-- What plugins get for a tile (DaylightUI.API Paint, kind "shoptile"): icon and name.
-- A refill restores the Daylight UI look.
if DUI.APIReport then
    DUI.APIReport.Parts("shoptile", function(b) return { icon = b.icon, name = b.name } end)
    DUI.APIReport.Repainter("shoptile", function() Shop.Refresh() end, true)
end
