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

-- Seen in game: an item taken from the mail (or traded) as the bag closed with
-- the mailbox went to Recent, and Recent's heading (and a slot) stayed
-- see-through: only a piece's own fade-in ever brought it back up, so no later
-- layout did. Whatever cut that fade short, a piece a layout shows is whole
-- unless it's fading in right now, and an opening shows everything whole.
local function bigBag()
    stub.Load({ bags = true, before = function()
        setup()
        world.sizes[2], world.sizes[3] = 36, 36
        world.items[2], world.items[3] = {}, {}
        for i = 1, 70 do
            world.items[i <= 35 and 2 or 3][i <= 35 and i or i - 35] = { iconFileID = 200 + i, stackCount = 1, quality = 1,
                hyperlink = "|Hitem:" .. (200 + i) .. "|h", itemID = 200 + i, itemName = "Thing " .. i }
            world.class[200 + i] = i % 5
        end
    end })
    stub.RunTimers()
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    local ns = stub.bags
    OpenAllBags()
    stub.RunTimers()
    return ns, ns.window
end

local function drive(dt)
    stub.Advance(dt)
    local Motion, Feel = DaylightUI.Motion, DaylightUI.Win.Feel
    if Motion.Driver() then stub.RunOnUpdate(Motion.Driver(), dt) end
    if Feel.Driver() then stub.RunOnUpdate(Feel.Driver(), dt) end
end

local function recentHeading(f)
    for _, h in ipairs(f.headings or {}) do
        if h:IsShown() and h.key == "recent" then return h end
    end
end

local function everythingWhole(ns, f, why)
    for _, h in ipairs(f.headings or {}) do
        if h:IsShown() then T.near(h:GetAlpha(), 1, 0.01, why .. ": heading " .. tostring(h.key)) end
    end
    for _, s in ipairs(f.set.Slots()) do
        local b = s.button
        if b:IsShown() then T.near(ns.Items.Fader(b):GetAlpha(), 1, 0.01, why .. ": slot " .. s.bag .. ":" .. b:GetID()) end
    end
end

-- A fade cut short, as seen: the piece is see-through and its fade believes
-- it's still on its way in.
local function cutShort(ns, r)
    local fader = ns.Items.Fader(r)
    fader:SetAlpha(0)
    fader.__duiAlphaKey = fader.__duiAlphaKey or {}
    fader.__duiAlphaKey.goal = 1
end

T.test("bags: mail landing as the bag closes: every piece shows whole on the next open", function()
    local newSlots = {}
    _G.C_NewItems = { IsNewItem = function(bag, slot) return newSlots[bag .. ":" .. slot] == true end }
    local ns, f = bigBag()
    drive(2)
    stub.FireEvent("MAIL_SHOW")
    stub.RunTimers()
    drive(2)
    world.items[1][5] = { iconFileID = 150, stackCount = 1, quality = 2, hyperlink = "|Hitem:50|h", itemID = 50, itemName = "Letter" }
    newSlots["1:5"] = true
    stub.FireEvent("BAG_UPDATE", 1)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    stub.FireEvent("MAIL_CLOSED")
    CloseAllBags()
    stub.RunTimers()
    T.truthy(f:IsShown() and f.__duiVanishing, "the bag is fading out")
    local h = recentHeading(f)
    T.truthy(h, "Recent came in")
    cutShort(ns, h)
    cutShort(ns, ns.Bags.buttons[1][5])
    stub.FinishFade(f)
    T.falsy(f:IsShown(), "closed")
    OpenAllBags()
    stub.RunTimers()
    everythingWhole(ns, f, "opened")
    _G.C_NewItems = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a piece left see-through shows whole after the next layout, one fading in carries on", function()
    local newSlots = {}
    _G.C_NewItems = { IsNewItem = function(bag, slot) return newSlots[bag .. ":" .. slot] == true end }
    local ns, f = bigBag()
    drive(2)
    world.items[1][5] = { iconFileID = 150, stackCount = 1, quality = 2, hyperlink = "|Hitem:50|h", itemID = 50, itemName = "Letter" }
    newSlots["1:5"] = true
    stub.FireEvent("BAG_UPDATE", 1)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    drive(2)
    local h = recentHeading(f)
    T.truthy(h, "Recent came in")
    cutShort(ns, h)
    -- Loot while open: an eased layout. The stuck heading comes back; the new
    -- item starts its own fade-in, which that layout leaves alone.
    world.items[1][6] = { iconFileID = 151, stackCount = 1, quality = 2, hyperlink = "|Hitem:51|h", itemID = 51, itemName = "Ring" }
    newSlots["1:6"] = true
    stub.FireEvent("BAG_UPDATE", 1)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.near(h:GetAlpha(), 1, 0.01, "the heading left see-through is whole")
    local ring = ns.Bags.buttons[1][6]
    T.truthy(ns.Items.Fader(ring):GetAlpha() < 1, "the new item is still fading in")
    drive(2)
    everythingWhole(ns, f, "settled")
    _G.C_NewItems = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: Clean Up left gaps in the backpack and its items unsorted. The
-- backpack was set to be skipped by clean up, and with the game's bag windows
-- parked nothing showed it or could change it: a right-click on the bag slots
-- strip did nothing.
T.test("bags: the Clean Up button's right-click lists the bags Clean Up skips, the backpack too", function()
    local ns = shelf()
    local flags, backpack = {}, false
    C_Container.GetBackpackAutosortDisabled = function() return backpack end
    C_Container.SetBackpackAutosortDisabled = function(on) backpack = on end
    C_Container.GetBagSlotFlag = function(bag, flag) return flags[bag .. ":" .. flag] == true end
    C_Container.SetBagSlotFlag = function(bag, flag, on) flags[bag .. ":" .. flag] = on end
    _G.Enum = _G.Enum or {}
    Enum.BagSlotFlags = Enum.BagSlotFlags or { DisableAutoSort = 1 }
    local menu
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(owner, keys, values, current, onPick, width, opts)
        menu = { owner = owner, keys = keys, values = values, pick = onPick, opts = opts }
    end
    local sort = ns.window.sort
    sort:GetScript("OnClick")(sort, "RightButton")
    DaylightUI.Widgets.OpenMenu = openMenu
    T.truthy(menu, "a menu opens")
    T.eq(menu.owner, sort)
    T.deq(menu.keys, { "head", "bag0", "bag1", "sellhead", "sell0", "sell1" },
        "a heading, the backpack, then each equipped bag; the same for Sell junk")
    T.truthy(menu.opts.titles.head and menu.opts.keepOpen, "a menu of switches under a heading")
    T.falsy(menu.opts.checked("bag0"))
    menu.pick("bag0")
    T.truthy(backpack, "the backpack is skipped now")
    T.truthy(menu.opts.checked("bag0"))
    T.truthy(ns.Keep.Skipped(0))
    menu.pick("bag1")
    T.truthy(flags["1:1"], "a bag uses the game's own flag")
    menu.pick("bag0")
    T.falsy(backpack, "and back")
    -- A strip bag's tooltip says so too (bag 1 is still skipped).
    local bag1 = ns.Slots.strip.slots[1]
    T.eq(bag1.bag, 1)
    local lines = {}
    local tip = GameTooltip
    _G.GameTooltip = { Hide = function() end, SetOwner = function() end, Show = function() end,
        SetInventoryItem = function() return false end, SetText = function(_, t) lines[#lines + 1] = t end,
        AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function(_, t) lines[#lines + 1] = t end,
        GetOwner = function() end, IsShown = function() return false end }
    bag1:GetScript("OnEnter")(bag1)
    bag1:GetScript("OnLeave")(bag1)
    _G.GameTooltip = tip
    local said = table.concat(lines, " / ")
    T.truthy(said:find("Clean Up skips this bag.", 1, true), said)
    T.truthy(said:find("Right-click", 1, true), "and where to change it")
    T.eq(ns.Keep.SkippedText(), "Skips Bag 1.")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
