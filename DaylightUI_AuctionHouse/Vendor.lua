-- What vendors sell things for, learned from the merchant window as it shows
-- or changes. Crafting materials like thread, vials and flux come from
-- vendors and rarely reach the Auction House, so the profession window's
-- profit needs these. Copper per unit, account-wide (vendors charge every
-- character the same); items that cost anything but gold are skipped.

local _, ns = ...

local Vendor = {}
ns.Vendor = Vendor

local function itemIDOf(i)
    if type(GetMerchantItemLink) ~= "function" then return nil end
    local link = GetMerchantItemLink(i)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Reads every row of the open merchant. True when a price was new or changed.
function Vendor.Learn()
    if type(GetMerchantNumItems) ~= "function" then return false end
    if not (C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function") then return false end
    local known, changed = ns.DB.Vendor(), false
    for i = 1, GetMerchantNumItems() or 0 do
        local row = C_MerchantFrame.GetItemInfo(i)
        local price = type(row) == "table" and row.price
        if type(price) == "number" and price > 0 and row.hasExtendedCost ~= true then
            local id = itemIDOf(i)
            if id and id > 0 then
                local stack = type(row.stackCount) == "number" and row.stackCount >= 1 and row.stackCount or 1
                local each = math.floor(price / stack)
                if each >= 1 and known[id] ~= each then
                    known[id] = each
                    changed = true
                end
            end
        end
    end
    return changed
end

local function learn()
    if Vendor.Learn() then DaylightUI.Fire("AuctionPricesChanged") end
end

ns.RegisterEvent("MERCHANT_SHOW", learn)
ns.RegisterEvent("MERCHANT_UPDATE", learn)

-- The copper per unit a vendor sold this item for, as last seen; nil when
-- no merchant has shown it.
function Vendor.Price(itemID)
    local price = type(itemID) == "number" and ns.DB.Vendor()[itemID]
    return type(price) == "number" and price > 0 and price or nil
end
