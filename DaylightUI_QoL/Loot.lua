-- Faster looting: when auto loot applies, grab every slot at once.

local _, ns = ...

local Loot = {}
ns.Loot = Loot
ns.features[#ns.features + 1] = Loot

local THROTTLE = 0.3
local mod, registered, lastLoot

local function autoLootApplies()
    if type(GetCVarBool) ~= "function" or type(IsModifiedClick) ~= "function" then return false end
    return (GetCVarBool("autoLootDefault") and true or false) ~= (IsModifiedClick("AUTOLOOTTOGGLE") and true or false)
end

function Loot.OnLootReady()
    if not (mod and mod.db and mod.db.fastLoot == true) then return end
    if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then return end
    if not autoLootApplies() then return end
    local now = type(GetTime) == "function" and GetTime() or 0
    if lastLoot and now - lastLoot < THROTTLE then return end
    lastLoot = now
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end

function Loot.Enable(m)
    mod = m
    if registered then return end
    registered = true
    DaylightUI.RegisterEvent("LOOT_READY", Loot.OnLootReady)
end

function Loot.Refresh(m) mod = m end
