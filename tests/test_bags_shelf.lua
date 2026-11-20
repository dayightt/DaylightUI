local stub = require("stub")

-- The Shelf (the bags' categories view) holding still while the bag is open:
-- slots stay where they were laid out while items leave, so nothing slides under
-- the cursor at a vendor. These check that holding still never loses an item.

local world

local function setup()
    world = {
        sizes = { [0] = 16, [1] = 12, [2] = 0, [3] = 0, [4] = 0, [5] = 0 },
        items = { [0] = {}, [1] = {} },
        class = { [1] = 2, [8] = 0, [9] = 0 },
        maxStack = { [8] = 20, [9] = 20 },
    }
    world.items[0][1] = { iconFileID = 101, stackCount = 1, quality = 3, hyperlink = "|Hitem:1|h", itemID = 1 }
    world.items[0][8] = { iconFileID = 108, stackCount = 5, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    world.items[1][1] = { iconFileID = 108, stackCount = 7, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    world.items[1][2] = { iconFileID = 109, stackCount = 2, quality = 1, hyperlink = "|Hitem:9|h", itemID = 9, itemName = "Apple" }
    _G.Constants = _G.Constants or {}
    Constants.InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 }
    _G.KEYRING_CONTAINER = -2
    _G.GetKeyRingSize = function() return 0 end
    _G.C_ActionBar = _G.C_ActionBar or {}
    C_ActionBar.ShouldShowKeyring = function() return false end
    _G.GetCVarBool = function() return true end
    _G.C_Container = {
        GetContainerNumSlots = function(id) return world.sizes[id] or 0 end,
        GetContainerItemInfo = function(bag, slot) return world.items[bag] and world.items[bag][slot] end,
        GetContainerItemQuestInfo = function() return {} end,
        GetContainerNumFreeSlots = function(bag)
            local n = 0
            for s = 1, world.sizes[bag] or 0 do if not (world.items[bag] and world.items[bag][s]) then n = n + 1 end end
            return n, 0
        end,
        HasContainerItem = function(bag, slot) return world.items[bag] and world.items[bag][slot] ~= nil end,
        SetItemSearch = function() end,
        SortBags = function() end,
        ContainerIDToInventoryID = function(id) return 30 + id end,
        GetContainerItemEquipmentSetInfo = function() return false, "" end,
    }
    _G.C_Item = _G.C_Item or {}
    C_Item.GetItemQualityColor = function(q) return 0.1 * q, 0.5, 0.9 end
    C_Item.GetItemInfoInstant = function(id)
        local itemID = type(id) == "number" and id or tonumber(string.match(tostring(id), "item:(%d+)"))
        return itemID, "", "", "", 0, world.class[itemID], 0
    end
    C_Item.GetItemInfo = function(link)
        local itemID = tonumber(string.match(tostring(link), "item:(%d+)"))
        return "name", link, 1, 1, 1, "", "", world.maxStack[itemID] or 1, "", 1, 1, 0, 0, 1
    end
    _G.GetMoney = function() return 0 end
    _G.GetMoneyString = function(m) return "money:" .. m end
    _G.NUM_CONTAINER_FRAMES = 7
    CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent):Hide()
    for i = 1, 7 do CreateFrame("Frame", "ContainerFrame" .. i, UIParent) end
    local combined = ContainerFrameCombinedBags
    _G.IsAnyBagOpen = function() return combined:IsShown() end
    _G.OpenAllBags = function() combined:Show() end
    _G.CloseAllBags = function() combined:Hide() end
    _G.ToggleAllBags = function() combined:SetShown(not combined:IsShown()) end
    for _, n in ipairs({ "OpenBackpack", "CloseBackpack", "ToggleBackpack", "OpenBag", "CloseBag", "ToggleBag" }) do
        _G[n] = function() end
    end
    -- A stand-in for the game's bag button template: its update methods do nothing.
    local create = CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "ContainerFrameItemButtonTemplate" then
            f.icon = f:CreateTexture()
            f.Count = f:CreateFontString()
            f.IconBorder = f:CreateTexture()
            f.JunkIcon = f:CreateTexture()
            f.UpgradeIcon = f:CreateTexture()
            f.flash = f:CreateTexture()
            f.NewItemTexture = f:CreateTexture()
            f.IconQuestTexture = f:CreateTexture()
            f.Cooldown = CreateFrame("Cooldown", nil, f)
            local countdown = f.Cooldown:CreateFontString()
            f.Cooldown.GetCountdownFontString = function() return countdown end
            for _, m in ipairs({ "SetHasItem", "SetItemButtonTexture", "UpdateExtended", "UpdateQuestItem", "UpdateNewItem",
                                 "UpdateJunkItem", "UpdateItemContextMatching", "UpdateCooldown", "SetReadable",
                                 "CheckUpdateTooltip", "SetMatchesSearch" }) do
                f[m] = function() end
            end
            for _, k in ipairs({ "flashAnim", "newitemglowAnim" }) do
                f[k] = { Play = function() end, Stop = function() end, IsPlaying = function() return false end }
            end
        end
        return f
    end
    _G.SetItemButtonQuality = function() end
    _G.SetItemButtonCount = function(b, n) b.count = n end
    _G.SetItemButtonDesaturated = function() end
    _G.ClearItemButtonOverlay = function() end
end

local function shelf()
    stub.Load({ bags = true, before = setup })
    stub.RunTimers()
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    local ns = stub.bags
    OpenAllBags()
    stub.RunTimers()
    return ns, ns.window
end

local function bagChanged(bag)
    stub.FireEvent("BAG_UPDATE", bag)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
end

-- Every item in the bags has a slot on the Shelf that shows it, and its count
-- adds up to what's in the bags.
local function everyItemShows(ns, why)
    local want, shown = {}, {}
    for bag, slots in pairs(world.items) do
        for _, it in pairs(slots) do want[it.itemID] = (want[it.itemID] or 0) + it.stackCount end
    end
    for _, s in ipairs(ns.window.set.Slots()) do
        local b = s.button
        local it = world.items[s.bag] and world.items[s.bag][b:GetID()]
        if it and b:IsShown() then
            shown[it.itemID] = (shown[it.itemID] or 0) + (b.dluiCount or it.stackCount)
        end
    end
    for id, n in pairs(want) do T.eq(shown[id], n, why .. ": item " .. id) end
end

T.test("bags: Shelf open, a combined stack sold and bought back: both stacks still show", function()
    local ns, f = shelf()
    local B = ns.Bags
    local first, other = B.buttons[0][8], B.buttons[1][1]
    T.truthy(first:IsShown() and not other:IsShown(), "the two Bread stacks show as one")
    everyItemShows(ns, "laid out")
    -- Sold: the other stack takes its spot and the bag holds still.
    local sold = world.items[0][8]
    world.items[0][8] = nil
    bagChanged(0)
    T.truthy(other:IsShown() and not first:IsShown(), "the other stack took its spot")
    T.truthy(f.stale, "held still")
    -- Bought back, into the very slot it left.
    world.items[0][8] = sold
    bagChanged(0)
    everyItemShows(ns, "bought back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: Shelf open, items only leaving still hold every slot in place", function()
    local ns, f = shelf()
    local B = ns.Bags
    local weapon, apple = B.buttons[0][1], B.buttons[1][2]
    local _, _, _, ax, ay = apple:GetPoint(1)
    world.items[0][1] = nil
    bagChanged(0)
    T.truthy(weapon:IsShown(), "the sold slot keeps its place")
    local _, _, _, bx, by = apple:GetPoint(1)
    T.deq({ bx, by }, { ax, ay }, "nothing slid under the cursor")
    T.truthy(f.stale)
    everyItemShows(ns, "sold")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
