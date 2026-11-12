-- Auto repair at vendors that can repair. Uses guild funds first when that
-- option is on and the guild allows it.
local ADDON, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Repair = {}
ns.Repair = Repair

local function fn(name) return type(_G[name]) == "function" and _G[name] or nil end

Repair.CHECK = 0.5     -- seconds to wait before checking whether the guild actually paid

local function cost()
    local c, can = GetRepairAllCost()
    if not can or type(c) ~= "number" then return 0 end
    return c
end

-- Repairs everything with the player's own gold, or reports being short.
local function ownMoney(c)
    if GetMoney() >= c then
        RepairAllItems()
        DUI.Print(string.format(L["Repaired for %s."], DUI.MoneyString(c)))
    else
        DUI.Print(string.format(L["Not enough money to repair (costs %s)."], DUI.MoneyString(c)))
    end
end

function Repair.OnVendor()
    if ns.Setting("autoRepair") ~= true then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not (fn("CanMerchantRepair") and fn("GetRepairAllCost") and fn("RepairAllItems")) then return end
    if not CanMerchantRepair() then return end
    local c = cost()
    if c <= 0 then return end

    local guild = false
    if ns.Setting("repairGuild") == true and fn("CanGuildBankRepair") and CanGuildBankRepair() then
        local allowed = fn("GetGuildBankWithdrawMoney") and GetGuildBankWithdrawMoney()
        guild = allowed == -1 or (type(allowed) == "number" and allowed >= c)
    end
    if not guild then return ownMoney(c) end
    -- The guild bank can be short even within the allowance and the game doesn't
    -- say so. Check again a moment later and fall back to own gold if nothing got
    -- repaired.
    RepairAllItems(true)
    C_Timer.After(Repair.CHECK, function()
        local left = cost()
        if left <= 0 then
            DUI.Print(string.format(L["Repaired for %s (guild)."], DUI.MoneyString(c)))
        elseif ns.Junk and ns.Junk.vendorOpen and CanMerchantRepair() then
            ownMoney(left)
        end
    end)
end

function Repair.Register()
    DUI.RegisterEvent("MERCHANT_SHOW", Repair.OnVendor)
end
