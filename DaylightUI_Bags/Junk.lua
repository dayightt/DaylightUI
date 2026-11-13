-- Junk selling. Opening a vendor sells everything in the Junk group (gray items
-- plus anything the player moved there) and prints the total in chat. Uses the
-- game's own selling (using an item while a vendor is open), one item at a time
-- with a short gap so the vendor never refuses a burst. Stops if the vendor closes.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Junk = {}
ns.Junk = Junk

Junk.STEP = 0.15             -- seconds between sales

local function priceOf(info)
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, info.hyperlink or info.itemID)
        if ok and type(sell) == "number" then return sell end
    end
    return 0
end

-- Every junk slot that sells for something: { bag, slot, value }.
function Junk.Items()
    local out = {}
    for _, s in ipairs(ns.Bags.Slots()) do
        if s.section ~= "keyring" then
            local slot = s.button:GetID()
            local info = ns.Items.InfoAt(s.bag, slot)
            if info and not info.hasNoValue then
                local f = ns.Categories.Facts(s.bag, slot, info)
                f.recent = false        -- freshly looted junk is still junk
                if not f.locked and ns.Categories.Assign(f, s.section) == "junk" then
                    local price = priceOf(info)
                    if price > 0 then
                        out[#out + 1] = { bag = s.bag, slot = slot, value = price * (info.stackCount or 1),
                                          link = info.hyperlink }
                    end
                end
            end
        end
    end
    return out
end

-- Gray items the game's "sell all junk" would take, and whether a locked one is
-- among them (that sale can't be told to skip it).
function Junk.Grays()
    local out, kept = {}, false
    for _, s in ipairs(ns.Bags.Slots()) do
        if s.section ~= "keyring" then
            local slot = s.button:GetID()
            local info = ns.Items.InfoAt(s.bag, slot)
            if info and info.quality == 0 and not info.hasNoValue then
                if ns.Categories.IsLocked(info.itemID) then kept = true
                else
                    out[#out + 1] = { bag = s.bag, slot = slot, link = info.hyperlink,
                                      value = priceOf(info) * (info.stackCount or 1) }
                end
            end
        end
    end
    return out, kept
end

-- The gray stack in the bag worth least, as shown (a combined stack counts as
-- one): { button, value }, or nil when there's none. Locked items and items
-- with no price (still loading, or no value) are left out.
function Junk.Cheapest()
    local best
    for _, s in ipairs(ns.Bags.Slots()) do
        local btn = s.button
        if s.section ~= "keyring" and btn:IsShown() then
            local info = ns.Items.InfoAt(s.bag, btn:GetID())
            if info and info.quality == 0 and not info.hasNoValue and not ns.Categories.IsLocked(info.itemID) then
                local value = priceOf(info) * (btn.dluiCount or info.stackCount or 1)
                if value > 0 and (not best or value < best.value) then
                    best = { button = btn, value = value }
                end
            end
        end
    end
    return best
end

-- Moves the bag window's mark to the cheapest junk (setting markCheapJunk).
function Junk.MarkCheapest(f)
    local best = ns.Setting("markCheapJunk") ~= false and Junk.Cheapest() or nil
    local btn = best and best.button
    if f.cheapest and f.cheapest ~= btn then ns.Items.PaintCheap(f.cheapest, false) end
    f.cheapest, f.cheapValue = btn, best and best.value
    if btn then ns.Items.PaintCheap(btn, true) end
end

local selling = false

local money = DUI.MoneyString

-- Sells the list one at a time and prints the total at the end.
function Junk.Sell(list)
    if selling or #list == 0 then return end
    selling = true
    local i, count, total = 0, 0, 0
    local function step()
        if not Junk.vendorOpen then
            selling = false
            return
        end
        i = i + 1
        local item = list[i]
        if not item then
            selling = false
            if count > 0 then
                DUI.Print(count == 1 and string.format(L["Sold 1 junk item for %s."], money(total))
                    or string.format(L["Sold %d junk items for %s."], count, money(total)))
            end
            return
        end
        -- Is the same item still there (not moved or locked since)?
        local ok, info = pcall(C_Container.GetContainerItemInfo, item.bag, item.slot)
        if ok and info and not info.isLocked and info.hyperlink == item.link then
            pcall(C_Container.UseContainerItem, item.bag, item.slot)
            count = count + 1
            total = total + item.value
        end
        C_Timer.After(Junk.STEP, step)
    end
    step()
end

-- The window's Sell junk button: the same sale as the automatic one.
function Junk.SellNow()
    if not Junk.vendorOpen or (InCombatLockdown and InCombatLockdown()) then return end
    Junk.Sell(Junk.Items())
end

local function refreshButton()
    if ns.window and ns.Window then ns.Window.UpdateSell(ns.window) end
end

function Junk.OnVendor()
    Junk.vendorOpen = true
    if ns.Setting("sellJunk") ~= true then return end
    if InCombatLockdown and InCombatLockdown() then return end
    Junk.Sell(Junk.Items())
end

-- For the NPC window's Sell junk button. True when a locked gray item means
-- selling item by item here; false leaves it to the game's own sale.
function DUI.SellJunkAroundLocks()
    local list, kept = Junk.Grays()
    if kept then Junk.Sell(list) end
    return kept
end

-- The game vendor window's sell-all button is disabled while it would sell a
-- locked item. The rest was already sold here when the vendor opened.
function Junk.GameButton()
    local b = _G.MerchantSellAllJunkButton
    if type(b) == "table" and b.SetEnabled and select(2, Junk.Grays()) then b:SetEnabled(false) end
end

-- Items marked as junk say so in their tooltip with the game's junk coin:
-- "Junk, sold at the next vendor" while auto-sell is on, otherwise just "Junk".
-- Plain item IDs only; a secret one is skipped.
Junk.TIP_ICON = "|A:bags-junkcoin:14:14|a "

function Junk.TipText(itemID)
    if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return nil end
    if not ns.Categories.IsMarkedJunk(itemID) then return nil end
    return Junk.TIP_ICON .. (ns.Setting("sellJunk") == true and L["Junk, sold at the next vendor"] or L["Junk"])
end

-- "Cheapest junk: 3s" while the tooltip's owner is the marked slot.
function Junk.CheapText(owner)
    local f = ns.window
    if not (f and owner and owner == f.cheapest and type(f.cheapValue) == "number") then return nil end
    return string.format(L["Cheapest junk: %s"], DUI.Widgets.Money(f.cheapValue))
end

function Junk.OnTip(tip, data)
    if tip ~= GameTooltip or type(data) ~= "table" then return end
    local c = DUI.Style.INK.LABEL
    local cheap = Junk.CheapText(tip.GetOwner and tip:GetOwner())
    if cheap then tip:AddLine(cheap, c[1], c[2], c[3]) end
    local text = Junk.TipText(data.id)
    if not text then
        if cheap and tip.Show and tip:IsShown() then tip:Show() end
        return
    end
    tip:AddLine(text, c[1], c[2], c[3])
    -- Refit to the new line, but only if the tooltip is already showing (same as GiverTips.lua).
    if tip.Show and tip:IsShown() then tip:Show() end
end

local tipHooked = false

function Junk.Register()
    if type(MerchantFrame_UpdateMerchantInfo) == "function" then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", Junk.GameButton)
    end
    local TDP, types = TooltipDataProcessor, Enum and Enum.TooltipDataType
    if not tipHooked and type(TDP) == "table" and type(TDP.AddTooltipPostCall) == "function" and types and types.Item then
        tipHooked = true
        TDP.AddTooltipPostCall(types.Item, function(tip, data) DUI.SafeCall(Junk.OnTip, tip, data) end)
    end
    DUI.RegisterEvent("MERCHANT_SHOW", function() Junk.OnVendor(); refreshButton() end)
    DUI.RegisterEvent("MERCHANT_CLOSED", function() Junk.vendorOpen = false; refreshButton() end)
end
