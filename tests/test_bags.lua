local stub = require("stub")

-- A fake bag world: bag sizes and what's in them, the game's bag windows
-- and open/close functions, and a stand-in for the game's bag button
-- template that records what the game's update calls did.
local world

local function setup(opts)
    opts = opts or {}
    world = {
        sizes = { [0] = 16, [1] = 12, [2] = 0, [3] = 0, [4] = 0, [5] = 4 },
        items = { [0] = {}, [1] = {}, [5] = {} },
        open = false, closeAll = 0, searched = nil, sorted = 0, keyring = opts.keyring, keyringSize = opts.keyringSize,
    }
    world.items[0][1] = { iconFileID = 101, stackCount = 5, quality = 3, hyperlink = "|Hitem:1|h" }
    world.items[0][2] = { iconFileID = 102, stackCount = 1, quality = 0, hyperlink = "|Hitem:2|h" }
    world.items[5][1] = { iconFileID = 501, stackCount = 2, quality = 1, hyperlink = "|Hitem:5|h" }
    world.items[0][4] = { iconFileID = 104, stackCount = 1, quality = 2, hyperlink = "|Hitem:4|h", isBound = false }
    world.items[0][5] = { iconFileID = 105, stackCount = 1, quality = 2, hyperlink = "|Hitem:6|h", isBound = true }
    world.items[0][6] = { iconFileID = 106, stackCount = 1, quality = 2, hyperlink = "|Hitem:7|h" }
    -- Bind types by link: 2 on equip, 3 on use. Item 7 isn't loaded yet.
    world.bind = { ["|Hitem:4|h"] = 2, ["|Hitem:6|h"] = 2, ["|Hitem:1|h"] = 1 }
    world.sets = { ["0:4"] = true }
    _G.Constants = _G.Constants or {}
    Constants.InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 }
    _G.KEYRING_CONTAINER = -2
    world.sizes[-2] = 6
    -- The keyring holds more slots than a character has unlocked. The game only
    -- shows GetKeyRingSize() of them (ContainerFrame_GetContainerNumSlots) and
    -- puts its padlock on any button past that (UpdateExtended).
    _G.GetKeyRingSize = function() return world.keyringSize or world.sizes[-2] end
    _G.C_ActionBar = _G.C_ActionBar or {}
    C_ActionBar.ShouldShowKeyring = function() return world.keyring == true end
    _G.GetCVarBool = function() return true end
    _G.C_Container = {
        GetContainerNumSlots = function(id) return world.sizes[id] or 0 end,
        GetContainerItemInfo = function(bag, slot) return world.items[bag] and world.items[bag][slot] end,
        GetContainerItemQuestInfo = function() return {} end,
        GetContainerNumFreeSlots = function(bag)
            local n = 0
            for s = 1, world.sizes[bag] or 0 do if not (world.items[bag] and world.items[bag][s]) then n = n + 1 end end
            return n, (world.family or {})[bag] or 0
        end,
        HasContainerItem = function(bag, slot) return world.items[bag] and world.items[bag][slot] ~= nil end,
        SetItemSearch = function(t) world.searched = t end,
        SortBags = function() world.sorted = world.sorted + 1 end,
        ContainerIDToInventoryID = function(id) return 30 + id end,
        GetContainerItemEquipmentSetInfo = function(bag, slot) return world.sets[bag .. ":" .. slot] == true, "" end,
    }
    _G.C_Item = _G.C_Item or {}
    C_Item.GetItemInfo = function(link)
        local bt = world.bind[link]
        if bt == nil then return nil end
        return "name", link, 2, 10, 1, "Armor", "Cloth", 1, "", 1, 1, 4, 1, bt
    end
    _G.C_Item = _G.C_Item or {}
    C_Item.GetItemQualityColor = function(q) return 0.1 * q, 0.5, 0.9 end
    _G.GetMoney = function() return 9592 end
    _G.GetMoneyString = function(m) return "money:" .. m end
    -- Colorblind mode makes the money helper hand back the game's text, so the
    -- tests below can read the amount ("money:9592").
    _G.ENABLE_COLORBLIND_MODE = "1"
    -- The game's bag windows, and its open/close functions.
    _G.NUM_CONTAINER_FRAMES = 7
    CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent):Hide()
    for i = 1, 7 do CreateFrame("Frame", "ContainerFrame" .. i, UIParent) end
    -- The game counts a bag as open when its window is shown (IsBagOpen), and keeps
    -- who opened the bags in a file local, FRAME_THAT_OPENED_BAGS (ContainerFrame.lua).
    -- Written while addon code runs, that local stays tainted for good. The game
    -- reads it on every CloseAllBags(frame), and everything after that read fails
    -- (UseAction and the controller code, in taint logs).
    local combined = ContainerFrameCombinedBags
    _G.IsAnyBagOpen = function() return combined:IsShown() end
    _G.OpenAllBags = function(frame)
        if frame then world.opener = frame:GetName() end
        combined:Show()
    end
    _G.CloseAllBags = function() world.opener = nil; world.closeAll = world.closeAll + 1; combined:Hide() end
    _G.ToggleAllBags = function() combined:SetShown(not combined:IsShown()) end
    for _, n in ipairs({ "OpenBackpack", "CloseBackpack", "ToggleBackpack", "OpenBag", "CloseBag", "ToggleBag" }) do
        _G[n] = function() end
    end
    -- The template: the game's update methods, recorded.
    local create = CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "ContainerFrameItemButtonTemplate" then
            f.icon = f:CreateTexture()
            f.Count = f:CreateFontString()
            f.IconBorder = f:CreateTexture()
            f.JunkIcon = f:CreateTexture()
            f.UpgradeIcon = f:CreateTexture()
            f.calls = {}
            for _, m in ipairs({ "SetHasItem", "SetItemButtonTexture", "UpdateExtended", "UpdateQuestItem", "UpdateNewItem",
                                 "UpdateJunkItem", "UpdateItemContextMatching", "UpdateCooldown", "SetReadable",
                                 "CheckUpdateTooltip", "SetMatchesSearch" }) do
                f[m] = function(self, ...) self.calls[m] = { ... } end
            end
            -- The new-item shimmer: UpdateNewItem starts the sweep and the pulse, like the game's.
            f.flash = f:CreateTexture()
            f.NewItemTexture = f:CreateTexture()
            f.NewItemTexture:SetAlpha(0)
            -- Art the template sizes on its own (ContainerFrame.xml) for its 37 px
            -- slot. The button's size never reaches it.
            f.NewItemTexture:SetSize(44, 44)
            f.IconQuestTexture = f:CreateTexture()
            f.IconQuestTexture:SetSize(37, 38)
            f.Cooldown = CreateFrame("Cooldown", nil, f)
            local countdown = f.Cooldown:CreateFontString()
            f.Cooldown.GetCountdownFontString = function() return countdown end
            for _, k in ipairs({ "flashAnim", "newitemglowAnim" }) do
                local a = { playing = false }
                function a:Play() self.playing = true end
                function a:Stop() self.playing = false; f.NewItemTexture:SetAlpha(0) end
                function a:IsPlaying() return self.playing end
                f[k] = a
            end
            local rec = f.UpdateNewItem
            f.UpdateNewItem = function(self, ...)
                rec(self, ...)
                self.NewItemTexture:Show(); self.flash:Show()
                self.flashAnim:Play(); self.newitemglowAnim:Play()
            end
            -- No SplitStack here. The game sets it on every shift-click
            -- (OnModifiedClick in ContainerFrame.lua), see shiftSplit below.
        end
        return f
    end
    -- The game's split box (StackSplitFrame.lua). OK hides it, then calls the
    -- owner's SplitStack, which the shift-click had just set.
    _G.StackSplitFrame = _G.StackSplitFrame or CreateFrame("Frame", "StackSplitFrame", UIParent)
    _G.StackSplitOkayButton_OnClick = function()
        StackSplitFrame:Hide()
        if StackSplitFrame.owner then StackSplitFrame.owner.SplitStack(StackSplitFrame.owner, StackSplitFrame.split) end
    end
    -- The viewer's plain item buttons have no recorder.
    _G.SetItemButtonQuality = function(b, q) if b.calls then b.calls.quality = q end end
    _G.SetItemButtonCount = function(b, n) if b.calls then b.calls.count = n end; b.count = n end
    _G.SetItemButtonDesaturated = function(b, v) b.calls.locked = v end
    _G.ClearItemButtonOverlay = function() end
    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    function GameTooltip:SetOwner() end
    function GameTooltip:SetInventoryItem() return true end
end

-- The plain grid unless categories are asked for. Most of these tests are about
-- the grid, and the categories view has its own.
local function login(opts)
    stub.Load({ bags = true, before = function() setup(opts) end })
    stub.RunTimers()
    DaylightUI:Set("Bags", "view", opts and opts.view or "grid")
    stub.RunTimers()
    return stub.bags
end

-- The footer's free slots without their color codes.
local function freeText(f) return (f.free:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function open(ns)
    OpenAllBags()
    stub.RunTimers()
    return ns.window
end

T.test("bags: the window has a portrait header, its name and free slots in the sub line", function()
    local ns = login()
    local f = open(ns)
    T.truthy(f.portrait:IsShown(), "the portrait shows")
    T.eq(f.title:GetText(), "Bags")
    local free, total = f.set.Free(true)
    local sub = f.sub:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.truthy(string.find(sub, DaylightUI.UnitName("player", "player"), 1, true), "the player's name: " .. sub)
    T.truthy(string.find(sub, free .. " of " .. total .. " free", 1, true), "free of total: " .. sub)
end)

-- The fake game does no layout, so no text width is checked here: these read the
-- anchors. inset = how far a right edge sits in from the window's right edge.
local function anchorOf(obj, point)
    for i = 1, obj:GetNumPoints() do
        local p, rel, relPoint, x, y = obj:GetPoint(i)
        if p == point then return rel, relPoint, x, y end
    end
end

local function inset(obj, point)
    local rel, _, x = anchorOf(obj, point)
    return -x, rel
end

-- The header's text keeps clear of the X (and of the first header tab when there
-- are tabs), and the sub line sits under the title, right of the portrait.
local function headerFits(f, tabs)
    T.truthy(f.portrait:IsShown(), "the portrait shows")
    local first = tabs and tabs[1]
    for _, fs in ipairs({ f.title, f.sub }) do
        local rel, relPoint = anchorOf(fs, "RIGHT")
        if first then
            T.eq(rel, first, "stops at the first tab")
            T.eq(relPoint, "LEFT")
        else
            local closeIn = inset(f.close, "TOPRIGHT") + f.close:GetWidth()
            local textIn, textRel = inset(fs, "RIGHT")
            T.eq(textRel, f)
            T.truthy(textIn >= closeIn, "stops left of the X")
        end
    end
    local subRel, subPoint = anchorOf(f.sub, "TOPLEFT")
    T.eq(subRel, f.title, "the sub line hangs under the title")
    T.eq(subPoint, "BOTTOMLEFT")
    local _, _, titleX, titleY = anchorOf(f.title, "TOPLEFT")
    T.truthy(titleX >= DaylightUI.Win.EDGE + DaylightUI.Win.PORTRAIT, "the title starts right of the portrait")
    T.eq(titleY, DaylightUI.Win.TITLE_Y, "on the header's title row")
end

-- Header tabs ride the X's row: anchored to the X or the tab beside it, no
-- offset of their own, so they follow the taller header.
local function tabsOnTitleRow(f, tabs)
    local right = f.close
    for i = #tabs, 1, -1 do
        local rel, relPoint, x, y = anchorOf(tabs[i], "RIGHT")
        T.eq(rel, right, "tab " .. i .. " sits beside the one to its right")
        T.eq(relPoint, "LEFT"); T.eq(y, 0, "level with the X")
        right = tabs[i]
    end
end

T.test("bags: title and sub line stop left of the X at any width", function()
    local ns = login()
    local f = open(ns)
    DaylightUI:Set("Bags", "columns", 4)
    DaylightUI:Set("Bags", "iconSize", 26)
    stub.RunTimers()
    ns.Window.Relayout(f)
    headerFits(f, f.tabs)
    T.eq(ns.Window.TITLE, DaylightUI.Win.HEADER)
end)

T.test("viewer: portrait header, sub line stops at the tabs, tabs on the title row", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", money = 123, time = time() - 7200,
        bags = { { section = "bags", size = 4, items = {} } }, bank = { { section = "bank", size = 4, items = {} } }, bankTime = time() - 60 } }
    ns.Viewer.Open(alt, "bags")
    stub.RunTimers()
    local f = ns.Viewer.window
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    headerFits(f, f.viewTabs)
    tabsOnTitleRow(f, f.viewTabs)
    T.truthy(f.sub:GetText():find("Saved", 1, true), "when it was saved")
end)

T.test("viewer: same look, keeps its tabs and picker", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", money = 123456, time = time() - 7200,
        bags = { { section = "bags", size = 4, items = {} } }, bank = { { section = "bank", size = 4, items = {} } }, bankTime = time() - 60 } }
    ns.Viewer.Open(alt, "bags")
    stub.RunTimers()
    local f = ns.Viewer.window
    T.truthy(f.portrait:IsShown(), "portrait")
    T.truthy(#f.chips > 1, "chip row")
    T.truthy(f.freeBar:IsShown(), "free bar")
    T.eq(f.sellJunk, nil, "no Sell junk")
    T.eq(#f.viewTabs, 3, "Bags, Bank, Account")
    T.truthy(f.charsButton, "the character picker")
    T.eq(f.money:GetText(), DaylightUI.Widgets.Money(123456), "a saved character's gold in our coins")
    for _, view in ipairs({ "grid", "categories" }) do
        f.Set("view", view)
        stub.RunTimers()
        ns.Window.PickChip(f, f.chips[2].id)
        ns.Window.Relayout(f)
        ns.Window.PickChip(f, nil)
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a holder per bag carrying its bag, and exactly one button per real slot", function()
    local ns = login()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local B = ns.Bags
    T.eq(B.holders[0]:GetID(), 0, "the backpack's holder is bag 0: the game's buttons read their bag from it")
    T.eq(B.holders[5]:GetID(), 5, "and the profession bag's is 5")
    T.eq(#B.buttons[0], 16); T.eq(#B.buttons[1], 12); T.eq(#B.buttons[5], 4)
    T.eq(#B.buttons[2], 0, "no bag, no buttons")
    T.eq(B.buttons[0][3]:GetID(), 3, "a button's ID is its slot")
    T.eq(B.buttons[0][1]:GetParent(), B.holders[0])
    T.eq(#B.Slots(), 32, "every real slot, none past a bag's size")
end)

T.test("bags: laid out backpack first, the profession bag past a line, or merged", function()
    local ns = login()
    local f = open(ns)
    local B = ns.Bags
    local function pos(b) local _, _, _, x, y = b:GetPoint(1); return x, y end
    local x1, y1 = pos(B.buttons[0][1])
    T.eq(x1, 0); T.eq(y1, 0, "the backpack's first slot top left")
    local _, y28 = pos(B.buttons[1][12])        -- the 28th slot, row 3 at 10 columns
    local _, yp = pos(B.buttons[5][1])
    T.truthy(yp < y28, "the profession bag under the rest")
    T.truthy(f.lines and f.lines[1]:IsShown(), "past a line")
    DaylightUI:Set("Bags", "reagentMerged", true)
    stub.RunTimers()
    local xm, ym = pos(B.buttons[5][1])
    T.eq(ym, y28, "merged: straight on after the last slot, same row")
    T.truthy(xm > 0)
    T.falsy(f.lines[1]:IsShown(), "no line")
end)

T.test("bags: a slot's glow, quest border and cooldown numbers follow the slot size", function()
    local ns = login()
    DaylightUI:Set("Bags", "iconSize", 26)
    open(ns)
    ns.Relayout()
    local b = ns.Bags.buttons[0][1]
    T.eq(b:GetWidth(), 26, "the slot itself")
    T.near(b.IconQuestTexture:GetWidth(), 26, 0.01, "the quest border is the slot's width")
    T.near(b.IconQuestTexture:GetHeight(), 38 * 26 / 37, 0.01, "and keeps its shape")
    T.near(b.NewItemTexture:GetWidth(), 44 * 26 / 37, 0.01, "the glow shrinks with the slot")
    DaylightUI:Set("Bags", "iconSize", 37)
    ns.Relayout()
    T.near(b.IconQuestTexture:GetWidth(), 37, 0.01, "a new size follows")
    T.near(b.NewItemTexture:GetWidth(), 44, 0.01, "the game's own size at its own slot")
    local _, size = b.Cooldown:GetCountdownFontString():GetFont()
    T.eq(size, ns.Items.COOLDOWN_SIZE, "cooldown numbers in a size that fits any slot")
end)

T.test("bags: the search hint stops at its box", function()
    local ns = login()
    open(ns)
    local hint, right = ns.window.search.hint, nil
    for i = 1, hint:GetNumPoints() do
        local at, to = hint:GetPoint(i)
        if at == "RIGHT" then right = to end
    end
    T.eq(right, ns.window.search, "held to the box's right end, so a narrow bag cuts it short")
end)

T.test("bags: new items keep a still glow, no flash or pulse", function()
    local ns = login()
    open(ns)
    local rare = ns.Bags.buttons[0][1]
    T.eq(rare.calls.UpdateNewItem[1], 3, "the game's new-item update still runs")
    T.falsy(rare.flashAnim:IsPlaying(), "the sweep stopped")
    T.falsy(rare.newitemglowAnim:IsPlaying(), "the pulse stopped")
    T.falsy(rare.flash:IsShown(), "the flash texture hidden")
    T.truthy(rare.NewItemTexture:IsShown(), "the glow itself stays")
    T.eq(rare.NewItemTexture:GetAlpha(), 1, "still and fully lit (stopping the pulse had put it back to 0)")
    -- A button without the animations (another client build) fills without errors.
    local plain = ns.Bags.buttons[0][2]
    plain.flashAnim, plain.newitemglowAnim, plain.flash, plain.NewItemTexture = nil, nil, nil, nil
    ns.Items.Fill(plain)
end)

-- Loot shine: a new item of uncommon or better gets one glint across its icon
-- and a bright border that settles, once per bag:slot:item per session, and only
-- where it can be seen (looted with the bag open, or the first open after).
T.test("bags: a new green shines once, seen: looted open, or on the first open after", function()
    local ns = login()
    local newSlots = {}
    _G.C_NewItems = { IsNewItem = function(bag, slot) return newSlots[bag .. ":" .. slot] == true end }
    local f = open(ns)
    local Items, B = ns.Items, ns.Bags
    local function shining(b) return Items.Parts(b).glint:IsShown() end
    local function loot(slot, quality)
        world.items[0][slot] = { iconFileID = 200 + slot, stackCount = 1, quality = quality,
            hyperlink = "|Hitem:" .. (200 + slot) .. "|h", itemID = 200 + slot }
        newSlots["0:" .. slot] = true
        stub.FireEvent("BAG_UPDATE", 0)
        stub.FireEvent("BAG_UPDATE_DELAYED")
        stub.RunTimers()
        return B.buttons[0][slot]
    end
    local function finish() stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2) end
    T.falsy(shining(B.buttons[0][4]), "nothing new: no shine")

    local green = loot(7, 2)
    T.truthy(shining(green), "looted with the bag open: a glint runs across")
    local q = Items.QualityColor(2)
    T.truthy(Items.Parts(green).shell.opts.borderColor[1] > q[1] + 0.1, "the border flashes brighter")
    local grey = loot(8, 0)
    T.falsy(shining(grey), "a gray item doesn't")
    finish()
    T.falsy(shining(green), "the glint is gone after")
    T.near(Items.Parts(green).shell.opts.borderColor[1], q[1], nil, "the border settles back to its quality")
    stub.FireEvent("BAG_NEW_ITEMS_UPDATED"); stub.RunTimers()
    T.falsy(shining(green), "filled again: not a second time")

    -- Looted while closed (Prep fills it unseen), it shines on the next open.
    f:Hide(); stub.RunTimers()
    local closed = loot(9, 3)
    Items.Fill(closed)
    T.falsy(shining(closed), "never while the bag is closed")
    open(ns)
    T.truthy(f:IsShown())
    T.truthy(shining(closed), "the first open after looting, once the lift lands")
    finish()
    f:Hide(); stub.RunTimers()
    open(ns)
    T.falsy(shining(closed), "reopened: not again")

    -- Motion off: no shine, and the border keeps its color.
    DaylightUI:Set("general", "motion", false)
    local still = loot(10, 2)
    T.falsy(shining(still), "motion off: no glint")
    T.near(Items.Parts(still).shell.opts.borderColor[1], q[1], nil, "and no flash")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.C_NewItems = nil
end)

T.test("bags: a new item keeps a small dot until hovered", function()
    local ns = login()
    local newSlots = {}
    _G.C_NewItems = { IsNewItem = function(bag, slot) return newSlots[bag .. ":" .. slot] == true end }
    open(ns)
    local Items, B = ns.Items, ns.Bags
    local function loot(slot, quality)
        world.items[0][slot] = { iconFileID = 300 + slot, stackCount = 1, quality = quality,
            hyperlink = "|Hitem:" .. (300 + slot) .. "|h", itemID = 300 + slot }
        newSlots["0:" .. slot] = true
        stub.FireEvent("BAG_UPDATE", 0)
        stub.FireEvent("BAG_UPDATE_DELAYED")
        stub.RunTimers()
        return B.buttons[0][slot]
    end
    local green = loot(7, 2)
    T.truthy(Items.Parts(green).newDot:IsShown(), "a new green has a dot")
    T.falsy(Items.Parts(loot(8, 0)).newDot:IsShown(), "a gray one doesn't")
    green:GetScript("OnEnter")(green)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    stub.RunTimers()
    T.falsy(Items.Parts(green).newDot:IsShown(), "hovered: the dot is gone")
    Items.Fill(green)
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    T.falsy(Items.Parts(green).newDot:IsShown(), "and stays gone after a refill")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.C_NewItems = nil
end)

T.test("bags: slots filled the game's way, in our look", function()
    local ns = login()
    open(ns)
    local B, Items = ns.Bags, ns.Items
    local rare, poor, empty = B.buttons[0][1], B.buttons[0][2], B.buttons[0][3]
    T.eq(rare.calls.SetItemButtonTexture[1], 101, "the game's own update calls, with the item's info")
    T.eq(rare.calls.count, 5); T.eq(rare.calls.quality, 3)
    T.eq(rare.calls.SetMatchesSearch[1], true)
    T.near(Items.Parts(rare).shell.opts.borderColor[1], 0.3, nil, "the border in its quality's color")
    T.eq(Items.Parts(poor).shell.opts.borderColor, Items.POOR, "a poor item's dim gray")
    T.eq(poor.icon:GetAlpha(), Items.POOR_ALPHA, "and grayed")
    T.eq(Items.Parts(empty).shell.opts.borderColor, Items.EMPTY, "an empty slot: only a dim outline")
    T.eq(empty.icon:GetAlpha(), 0, "no empty-slot picture")
    T.eq(rare.IconBorder:GetAlpha(), 0, "the game's quality ring out of sight")
    -- The Hearthstone gets a light blue border, easy to spot.
    world.items[0][3] = { iconFileID = 134414, stackCount = 1, quality = 1, hyperlink = "|Hitem:6948|h", itemID = 6948 }
    Items.Fill(empty)
    T.eq(Items.Parts(empty).shell.opts.borderColor, Items.HEARTH, "the Hearthstone in light blue")
    world.items[0][3] = nil
    Items.Fill(empty)
    T.eq(Items.Parts(empty).shell.opts.borderColor, Items.EMPTY, "gone: an empty slot again")
    -- A herb bag: its empty slots and plain items in its color, better items in their quality's.
    world.family = { [0] = 32 }
    local herb = Items.BAG_COLORS[6].color
    Items.Fill(empty); Items.Fill(poor); Items.Fill(rare)
    T.eq(Items.Parts(empty).shell.opts.borderColor, herb, "empty: the herb bag's green")
    T.eq(Items.Parts(poor).shell.opts.borderColor, herb, "a plain item: the bag's color")
    T.near(Items.Parts(rare).shell.opts.borderColor[1], 0.3, nil, "a rare: still its quality's color")
    world.family = { [0] = 1024 }
    Items.Fill(empty)
    T.eq(Items.Parts(empty).shell.opts.borderColor, Items.BAG_COLORS[10].color, "a mining bag: dark brown")
    world.family = nil
    Items.Fill(empty)
    T.eq(Items.Parts(empty).shell.opts.borderColor, Items.EMPTY, "an ordinary bag again")
end)

-- From the mailbox: the bag update came before the item was there, so the slot
-- filled empty. The unlock that followed found it and lit the border, but there
-- was no icon until a hover refilled it.
T.test("bags: an item that turns up at its unlock gets its icon", function()
    local ns = login()
    open(ns)
    local slot = ns.Bags.buttons[0][3]
    T.isnil(slot.calls.SetItemButtonTexture[1], "empty to start")
    world.items[0][3] = { iconFileID = 2318, stackCount = 1, quality = 1, hyperlink = "|Hitem:2318|h", itemID = 2318 }
    stub.FireEvent("ITEM_LOCK_CHANGED", 0, 3)
    stub.RunTimers()
    T.eq(slot.calls.SetItemButtonTexture[1], 2318, "its icon, without a hover")
    T.eq(slot.icon:GetAlpha(), 1)
    -- And the other way: gone at the unlock, so the icon goes too.
    world.items[0][3] = nil
    stub.FireEvent("ITEM_LOCK_CHANGED", 0, 3)
    stub.RunTimers()
    T.isnil(slot.calls.SetItemButtonTexture[1], "empty again")
end)

-- The game held an item in the slot before it had the item's data, so the slot
-- read empty at its bag update, and no bag update came once the data arrived.
-- That left a blank slot whose hover showed the item.
T.test("bags: an item still loading at its bag update gets its icon once it loads", function()
    local ns = login()
    local loaded = {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return not (world.items[bag] and world.items[bag][slot]) end,
                 ContinueOnItemLoad = function(_, fn) loaded[bag .. ":" .. slot] = fn end }
    end }
    open(ns)
    local slot = ns.Bags.buttons[0][3]
    T.isnil(slot.calls.SetItemButtonTexture[1], "empty to start")
    local readInfo = C_Container.GetContainerItemInfo
    local ready = false
    C_Container.GetContainerItemInfo = function(bag, s)
        if bag == 0 and s == 3 and not ready then return nil end
        return readInfo(bag, s)
    end
    world.items[0][3] = { iconFileID = 2319, stackCount = 1, quality = 2, hyperlink = "|Hitem:2319|h", itemID = 2319 }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.isnil(slot.calls.SetItemButtonTexture[1], "no data yet: nothing to show")
    T.truthy(loaded["0:3"], "told when it loads")
    ready = true
    loaded["0:3"]()
    stub.RunTimers()
    T.eq(slot.calls.SetItemButtonTexture[1], 2319, "its icon, with no bag update")
    T.eq(slot.icon:GetAlpha(), 1)
    C_Container.GetContainerItemInfo = readInfo
    _G.Item = nil
end)

T.test("bags: an item the slot still gives no icon after its wait shows the item's own icon, and keeps it through a lock", function()
    local ns = login()
    local loaded = {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return not (world.items[bag] and world.items[bag][slot]) end,
                 ContinueOnItemLoad = function(_, fn) loaded[bag .. ":" .. slot] = fn end }
    end }
    local oldIcon = C_Item.GetItemIconByID
    C_Item.GetItemIconByID = function(id) if id == 7362 then return 134939 end end
    open(ns)
    local slot = ns.Bags.buttons[0][3]
    -- a pattern Forever changed: the slot reads it with no icon, before and after it loads
    world.items[0][3] = { stackCount = 1, quality = 2, hyperlink = "|Hitem:7362|h", itemID = 7362 }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    if loaded["0:3"] then loaded["0:3"](); stub.RunTimers() end
    T.eq(slot.calls.SetItemButtonTexture[1], 134939, "the item's own icon, not a blank tile")
    T.eq(slot.icon:GetAlpha(), 1, "shown")
    world.items[0][3].isLocked = true
    stub.FireEvent("ITEM_LOCK_CHANGED", 0, 3)
    stub.RunTimers()
    T.eq(slot.icon:GetAlpha(), 1, "picked up and put down: still shown")
    C_Item.GetItemIconByID = oldIcon
    _G.Item = nil
end)

T.test("bags: empty slots grouped into one free tile per section", function()
    local ns = login()
    local f = open(ns)
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    stub.RunTimers()
    local B, Items = ns.Bags, ns.Items
    T.truthy(B.buttons[0][1]:IsShown()); T.truthy(B.buttons[0][2]:IsShown())
    local tile = B.buttons[0][3]
    T.truthy(tile:IsShown(), "the first empty slot is the tile")
    T.eq(Items.Parts(tile).free:GetText(), 23, "with the number free in its section")
    T.falsy(B.buttons[0][7]:IsShown(), "the other empty slots hidden")
    T.truthy(B.buttons[5][2]:IsShown(), "the profession bag has its own tile")
    -- A herb bag in a normal bag slot: its empty slots get their own tile, in its color.
    world.family = { [1] = 32 }
    for s = 1, 12 do Items.Fill(B.buttons[1][s]) end
    ns.Refresh(ns.module)
    stub.RunTimers()
    T.eq(Items.Parts(tile).free:GetText(), 11, "the ordinary tile: only ordinary bags' slots")
    T.truthy(B.buttons[1][1]:IsShown(), "the herb bag's own tile")
    T.eq(Items.Parts(B.buttons[1][1]).free:GetText(), 12)
    T.eq(Items.Parts(B.buttons[1][1]).shell.opts.borderColor, Items.BAG_COLORS[6].color, "in herb green")
    T.falsy(B.buttons[1][2]:IsShown())
    world.family = nil
    DaylightUI:Set("Bags", "emptySlots", "all")
    stub.RunTimers()
    T.truthy(B.buttons[0][7]:IsShown(), "all again")
    T.falsy(Items.Parts(tile).free:IsShown())
end)

T.test("bags: opening and closing follow the game; closing ours closes the game's", function()
    local ns = login()
    local OC = ns.OpenClose
    T.eq(ContainerFrameCombinedBags:GetParent(), OC.hidden, "the game's windows out of sight")
    T.eq(ContainerFrame6:GetParent(), OC.hidden)
    local f = ns.window
    T.falsy(f:IsShown())
    OpenAllBags()
    stub.RunTimers()
    T.truthy(f:IsShown(), "the game opened its bags: ours shows")
    ToggleAllBags()
    stub.RunTimers()
    T.truthy(f:IsShown(), "fading out")
    stub.FinishFade(f)
    T.falsy(f:IsShown(), "and closes with them")
    OpenAllBags()
    stub.RunTimers()
    f.close:GetScript("OnClick")(f.close)
    stub.RunTimers()
    stub.FinishFade(f)
    T.falsy(IsAnyBagOpen(), "our X closes the game's bags")
    T.falsy(f:IsShown())
    -- Escape: the game hides the window's stand-in and the window fades out.
    OpenAllBags()
    stub.RunTimers()
    T.truthy(f.__duiEsc:IsShown())
    T.truthy(tContains(UISpecialFrames, f.__duiEsc:GetName()), "Escape closes it")
    f.__duiEsc:Hide()
    stub.FinishFade(f)
    T.falsy(f:IsShown())
    T.falsy(IsAnyBagOpen(), "and the game's bags with it")
end)

-- The game's help tips (the reagent bag tutorial, BagTutorialUtil.lua), cut to
-- what matters: a tip pointing at one of the game's item buttons, parked out of sight.
local function tutorial()
    local cbs, active = {}, {}
    _G.EventRegistry = {
        RegisterCallback = function(_, e, fn, owner)
            cbs[e] = cbs[e] or {}
            cbs[e][#cbs[e] + 1] = { fn, owner }
        end,
        UnregisterCallback = function() end,
        TriggerEvent = function(_, e, ...)
            for _, c in ipairs(cbs[e] or {}) do c[1](c[2], ...) end
        end,
    }
    _G.HelpTip = {
        framePool = { EnumerateActive = function() return next, active end },
        Show = function(_, parent, info, region)
            local tip = { info = info, relativeRegion = region or parent }
            tip.GetParent = function() return parent end
            active[tip] = true
        end,
        Hide = function(_, parent, text)
            for tip in pairs(active) do
                if tip:GetParent() == parent and tip.info.text == text then active[tip] = nil end
            end
        end,
    }
    local function shown()
        local out = {}
        for tip in pairs(active) do out[#out + 1] = tip end
        return out
    end
    return shown, active
end

T.test("bags: never says a bag opened or closed for the game; its tips land on our slot", function()
    local ns = login()
    local OC, f = ns.OpenClose, ns.window
    local shown, active = tutorial()
    local window = ContainerFrame1
    for _, w in ipairs(OC.GameWindows()) do w:Hide() end

    -- The game's own reagent bag button, parked with its window.
    local parked = CreateFrame("Button", nil, window)
    parked.GetBagID = function() return 0 end
    parked:SetID(2)

    -- Fired from addon code, these ran the game's listeners under addon taint:
    -- its controller code as DaylightUI_Bags in taint.log, then an error on its
    -- action buttons in the next fight.
    local said = 0
    EventRegistry:RegisterCallback("ContainerFrame.OpenBag", function() said = said + 1 end, "tutorial")
    EventRegistry:RegisterCallback("ContainerFrame.CloseBag", function() said = said + 1 end, "tutorial")

    local tip = { text = "Right-click it.", system = "TutorialReagentBag" }
    window:Show()     -- the game opens its window, out of sight
    OpenAllBags()
    stub.RunTimers()
    T.truthy(f:IsShown())
    window:Hide()
    CloseAllBags()
    stub.RunTimers()
    T.eq(said, 0, "the game's bag events are the game's to fire")

    -- With the bag open, the game points at its own hidden button.
    window:Show()
    OpenAllBags()
    stub.RunTimers()
    HelpTip:Show(UIParent, tip, parked)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(shown()[1].relativeRegion, ns.Bags.buttons[0][2], "pointing at our slot, not the game's hidden one")

    -- A slot not on show (merged into a stack) points at the bag itself.
    ns.Bags.buttons[0][2]:Hide()
    for t in pairs(active) do active[t] = nil end
    HelpTip:Show(UIParent, tip, parked)
    OC.MoveTips()
    T.eq(shown()[1].relativeRegion, f, "its slot hidden: the bag")
    _G.EventRegistry, _G.HelpTip = nil, nil
end)

T.test("bags: typing searches; the X clears it; sort is the game's sort", function()
    local ns = login()
    local f = open(ns)
    local B = ns.Bags
    local function type_(text)
        f.search:SetText(text)
        f.search:GetScript("OnTextChanged")(f.search, true)
    end
    type_("rare")
    T.eq(B.buttons[0][1].calls.SetMatchesSearch[1], true, "a rare item stands out")
    T.eq(B.buttons[0][2].calls.SetMatchesSearch[1], false, "the rest dim")
    T.eq(B.buttons[0][3].calls.SetMatchesSearch[1], true, "an empty slot never dims")
    T.truthy(f.search.clear:IsShown(), "an X to clear it, while there's a search")
    f.search.clear:GetScript("OnClick")(f.search.clear)
    f.search:GetScript("OnTextChanged")(f.search, true)
    T.eq(f.search:GetText(), "", "the X clears it")
    T.eq(B.buttons[0][2].calls.SetMatchesSearch[1], true, "everything back")
    T.falsy(f.search.clear:IsShown(), "gone again")
    f.sort:GetScript("OnClick")(f.sort)
    T.eq(world.sorted, 1)
    type_("potion")
    f:Hide()
    T.eq(f.search:GetText(), "", "a search clears when the bag closes")
end)

T.test("bags: a bigger bag gets more slots; never in combat", function()
    local ns = login()
    open(ns)
    local B = ns.Bags
    world.sizes[2] = 8
    stub.combat = true
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.eq(#B.buttons[2], 0, "no buttons made in combat")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.RunTimers()
    T.eq(#B.buttons[2], 8, "made after combat")
    world.sizes[2] = 4
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.falsy(B.buttons[2][5]:IsShown(), "a smaller bag hides its extra slots")
end)

T.test("bags: the keyring as its own section when the game shows one", function()
    local ns = login({ keyring = true })
    ns.module.db.showKeyring = true
    ns.Refresh(ns.module)
    open(ns)
    local B = ns.Bags
    T.eq(#B.buttons[-2], 6)
    T.eq(B.holders[-2]:GetID(), -2)
    local list = B.List()
    T.eq(list[#list].section, "keyring")
end)

T.test("bags: the keyring stays out of the bag until Show keyring is on", function()
    local ns = login({ keyring = true })
    ns.module.db.showKeyring = nil
    open(ns)
    local B = ns.Bags
    local function shown()
        local n = 0
        for _, b in ipairs(B.buttons[-2] or {}) do if b:IsShown() then n = n + 1 end end
        return n
    end
    T.eq(shown(), 0, "off by default")
    local list = B.List()
    T.truthy(list[#list].section ~= "keyring", "the keyring isn't listed")
    ns.module.db.showKeyring = true
    ns.Refresh(ns.module)
    T.eq(shown(), 6, "on: its slots show")
    ns.module.db.showKeyring = nil
    ns.Refresh(ns.module)
    T.eq(shown(), 0, "off again")
end)

T.test("bags: the keyring shows only its unlocked slots", function()
    local ns = login({ keyring = true, keyringSize = 4 })
    ns.module.db.showKeyring = true
    ns.Refresh(ns.module)
    open(ns)
    local B = ns.Bags
    T.eq(B.Size(-2), 4, "GetKeyRingSize, not the keyring's full size")
    local shown = 0
    for _, b in ipairs(B.buttons[-2] or {}) do if b:IsShown() then shown = shown + 1 end end
    T.eq(shown, 4, "no padlocked slots past the unlocked ones")
end)

T.test("bags: free slots and money in the footer", function()
    local ns = login()
    local f = open(ns)
    T.eq(freeText(f), "23 / 3", "the plain bags, then the profession bag's 3 free")
    T.eq(f.free:GetText(), "23 / " .. DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Pop() }) .. "3|r", "a profession bag without a color of its own: the accent")
    T.eq(f.money:GetText(), "money:9500 money:92", "our coins: silver and copper")
end)

T.test("bags: the footer bar fills with used slots and eases there", function()
    local ns = login()
    local f = open(ns)
    local free, total = f.set.Free(true)
    T.near(f.freeBar:GetValue(), (total - free) / total, 0.001, "used over total")
    T.eq(f.free:GetText():find("23", 1, true) ~= nil, true, "the text keeps its counts")
    world.items[0][3] = { iconFileID = 103, stackCount = 1, quality = 1, hyperlink = "|Hitem:3|h" }
    ns.Window.UpdateFooter(f)
    local free2, total2 = f.set.Free(true)
    T.eq(free2, free - 1, "one more slot used")
    stub.Advance(1); stub.RunTimers()
    T.near(f.freeBar:GetValue(), (total2 - free2) / total2, 0.001, "settles on the new share")
end)

T.test("bags: Sell junk sits above the money row, clear of the tracked currencies", function()
    local ns = login()
    DaylightUI:Set("Bags", "columns", 7)
    C_CurrencyInfo = { GetBackpackCurrencyInfo = function(i)
        if i <= 3 then return { iconFileID = 100 + i, quantity = 123456 * i } end
    end }
    local f = open(ns)
    stub.FireEvent("MERCHANT_SHOW")
    stub.Advance(1); stub.RunTimers()
    ns.Window.UpdateFooter(f)
    T.eq(#f.currencySlots >= 3 and f.currencySlots[3]:IsShown(), true, "currencies are drawn")
    local _, _, _, _, sy = f.sellJunk:GetPoint()
    local _, _, _, _, my = f.money:GetPoint()
    T.truthy(sy >= my + ns.Window.FOOTER_ROW, "above the row the money and currencies sit on")
    C_CurrencyInfo = nil
end)

T.test("bags: Sell junk shows at a vendor with junk and sells it", function()
    local ns = login()
    local f = open(ns)
    local sold = {}
    C_Container.UseContainerItem = function(bag, slot) sold[#sold + 1] = bag .. ":" .. slot end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:2|h" then return "name", link, 0, 1, 1, "", "", 20, "", 1, 25, 0, 0, 0 end
        return getInfo(link)
    end
    world.items[0][7] = { iconFileID = 107, stackCount = 1, quality = 0, hyperlink = "|Hitem:12|h", itemID = 12 }
    local old = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:12|h" then return "name", link, 0, 1, 1, "", "", 20, "", 1, 25, 0, 0, 0 end
        return old(link)
    end
    ns.Categories.ToggleLock(12)
    DaylightUI:Set("Bags", "sellJunk", false)
    T.eq(f.sellJunk:IsShown(), false, "hidden away from a vendor")
    stub.FireEvent("MERCHANT_SHOW")
    stub.Advance(1); stub.RunTimers()
    T.eq(f.sellJunk:IsShown(), true, "shown at a vendor with junk")
    T.truthy(f.sellJunk.text:GetText():find("25", 1, true), "its label holds the junk's value")
    f.sellJunk:GetScript("OnClick")(f.sellJunk)
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(table.concat(sold, ","), "0:2", "the gray slot only, not the locked one")
    stub.FireEvent("MERCHANT_CLOSED")
    stub.Advance(1); stub.RunTimers()
    T.eq(f.sellJunk:IsShown(), false, "hidden when the vendor closes")
end)

T.test("bags: the cheapest junk gets a warn dot that fades in, a tooltip line with its price, and a setting", function()
    local ns = login()
    local prices = { ["|Hitem:2|h"] = 25, ["|Hitem:12|h"] = 3, ["|Hitem:13|h"] = 1 }
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if prices[link] then return "name", link, 0, 1, 1, "", "", 20, "", 1, prices[link], 0, 0, 0 end
        return getInfo(link)
    end
    world.items[0][7] = { iconFileID = 107, stackCount = 4, quality = 0, hyperlink = "|Hitem:12|h", itemID = 12 }
    local f = open(ns)
    local function at(bag, slot)
        for _, s in ipairs(ns.Bags.Slots()) do
            if s.bag == bag and s.button:GetID() == slot then return s.button end
        end
    end
    local function dot(b) local p = ns.Items.Parts(b); return p.cheapDot ~= nil and p.cheapDot:IsShown() end
    T.eq(f.cheapest, at(0, 7), "4 x 3 copper is less than 25")
    T.truthy(dot(at(0, 7))); T.falsy(dot(at(0, 2)))
    local p = ns.Items.Parts(at(0, 7))
    T.rgb(p.cheapDot.__vertexColor or { p.cheapDot:GetVertexColor() }, DaylightUI.Style.INK.WARN, "in the warn color")
    -- A cheaper one arrives: the mark moves.
    world.items[1][3] = { iconFileID = 113, stackCount = 1, quality = 0, hyperlink = "|Hitem:13|h", itemID = 13 }
    stub.FireEvent("BAG_UPDATE", 1); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    stub.Advance(1); stub.RunTimers()
    T.eq(f.cheapest, at(1, 3), "the new, cheaper one")
    T.truthy(dot(at(1, 3))); T.falsy(dot(at(0, 7)), "the old mark fades away")
    -- Its tooltip says what it sells for.
    local added, addLine, getOwner = {}, GameTooltip.AddLine, GameTooltip.GetOwner
    GameTooltip.AddLine = function(_, text) added[#added + 1] = text end
    GameTooltip.GetOwner = function() return at(1, 3) end
    ns.Junk.OnTip(GameTooltip, { id = 13 })
    GameTooltip.GetOwner = function() return at(0, 7) end
    ns.Junk.OnTip(GameTooltip, { id = 12 })
    GameTooltip.AddLine, GameTooltip.GetOwner = addLine, getOwner
    T.eq(#added, 1, "only on the marked slot")
    T.eq(added[1], "Cheapest junk: " .. DaylightUI.Widgets.Money(1))
    -- A locked one is never the cheapest; with none left, no mark.
    ns.Categories.ToggleLock(13)
    stub.Advance(1); stub.RunTimers()
    T.eq(f.cheapest, at(0, 7), "locked: skipped")
    DaylightUI:Set("Bags", "markCheapJunk", false)
    stub.Advance(1); stub.RunTimers()
    T.isnil(f.cheapest, "off: no mark")
    T.falsy(dot(at(0, 7)))
    C_Item.GetItemInfo = getInfo
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a warlock over their Soul Shard limit gets a button that deletes the extra ones, only on a second click", function()
    local ns = login()
    stub.units.player = stub.units.player or {}
    stub.units.player.class = "WARLOCK"
    for i = 7, 11 do
        world.items[0][i] = { iconFileID = 600, stackCount = 1, quality = 1, hyperlink = "|Hitem:6265|h", itemID = 6265 }
    end
    world.items[1][1] = { iconFileID = 601, stackCount = 1, quality = 1, hyperlink = "|Hitem:6266|h", itemID = 6266 }
    local f = open(ns)
    local b = f.dropShards
    T.falsy(b:IsShown(), "no limit set: no button")
    DaylightUI:Set("Bags", "shardsKeep", 3)
    stub.Advance(1); stub.RunTimers()
    T.truthy(b:IsShown(), "5 shards, keep 3")
    T.eq(b.text:GetText(), "Delete 2 extra shards")
    -- In a raid its own limit counts.
    DaylightUI:Set("Bags", "shardsKeepRaid", 10)
    stub.inRaid = true
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.Advance(1); stub.RunTimers()
    T.falsy(b:IsShown(), "keep 10 in a raid")
    stub.inRaid = false
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.Advance(1); stub.RunTimers()
    T.truthy(b:IsShown())
    -- The game's cursor and delete, recorded.
    local deleted, picked = {}, {}
    C_Container.PickupContainerItem = function(bag, slot)
        local it = world.items[bag] and world.items[bag][slot]
        picked[#picked + 1] = bag .. ":" .. slot
        stub.cursor = it and { "item", it.itemID, bag, slot } or nil
    end
    _G.DeleteCursorItem = function()
        local c = stub.cursor
        if c then deleted[#deleted + 1] = c[3] .. ":" .. c[4]; world.items[c[3]][c[4]] = nil end
        stub.cursor = nil
    end
    _G.CursorHasItem = function() return stub.cursor ~= nil end
    b:GetScript("OnClick")(b)
    T.eq(#deleted, 0, "the first click only asks")
    T.eq(b.text:GetText(), "Click again")
    stub.Advance(1)
    b:GetScript("OnClick")(b)
    T.eq(table.concat(deleted, ","), "0:11,0:10", "two shards, from the last slot back, nothing else")
    T.truthy(stub.ChatContains("Deleted 2 Soul Shards."))
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.Advance(1); stub.RunTimers()
    T.falsy(b:IsShown(), "at the limit: gone")
    T.truthy(world.items[1][1], "the item that isn't a shard stays")
    -- Something else on the cursor after picking up: nothing deleted.
    world.items[0][12] = { iconFileID = 600, stackCount = 1, quality = 1, hyperlink = "|Hitem:6265|h", itemID = 6265 }
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.Advance(1); stub.RunTimers()
    C_Container.PickupContainerItem = function() stub.cursor = { "item", 1234 } end
    deleted = {}
    T.eq(ns.Junk.DeleteShards(), 0)
    T.eq(#deleted, 0, "the cursor didn't hold a shard: put back, nothing deleted")
    T.isnil(stub.cursor)
    -- Not a warlock: no button, and the rows are hidden.
    stub.units.player.class = "MAGE"
    T.eq(ns.Junk.ExtraShards(), 0)
    T.truthy(ns.Junk.IsWarlock() == false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a new accent repaints the profession bag's count at once", function()
    local ns = login()
    local f = open(ns)
    local was = f.free:GetText()
    DaylightUI:Set("general", "accentColor", { 0.9, 0.2, 0.1 })
    DaylightUI:Set("general", "accent", "custom")
    stub.RunTimers()
    stub.Advance(1)
    stub.RunTimers()
    local now = "23 / " .. DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Pop() }) .. "3|r"
    T.truthy(now ~= was, "the accent changed")
    T.eq(f.free:GetText(), now, "in the new accent")
end)

T.test("bags: a new accent while closed shows on the next open", function()
    local ns = login()
    local f = open(ns)
    CloseAllBags(); f:Hide(); stub.RunTimers()
    DaylightUI:Set("general", "accentColor", { 0.9, 0.2, 0.1 })
    DaylightUI:Set("general", "accent", "custom")
    stub.RunTimers()
    stub.Advance(1)
    stub.RunTimers()
    f = open(ns)
    T.eq(f.free:GetText(), "23 / " .. DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Pop() }) .. "3|r", "in the new accent")
end)

T.test("bags: the footer's money has our coins", function()
    local ns = login()
    _G.ENABLE_COLORBLIND_MODE = "0"
    local f = open(ns)
    local text = f.money:GetText()
    _G.ENABLE_COLORBLIND_MODE = "1"
    T.truthy(text:find("95", 1, true) and text:find("coin-silver.png", 1, true), "95 silver")
    T.truthy(text:find("coin-copper.png", 1, true), "92 copper")
end)

T.test("bags: hovering a bag in the strip lights every slot in it, empty ones too", function()
    local ns = login()
    open(ns)
    local B, Items, Slots = ns.Bags, ns.Items, ns.Slots
    local bag1 = Slots.strip.slots[1]
    T.eq(bag1.bag, 1)
    bag1:GetScript("OnEnter")(bag1)
    local empty = B.buttons[1][7]
    local r, g, b = DaylightUI.Style.Accent()
    T.eq(Items.Parts(empty).shell.opts.borderColor[1], r, "an empty slot of the bag outlined in the accent")
    T.eq(empty:GetAlpha(), 1)
    T.eq(B.buttons[0][1]:GetAlpha(), Slots.DIM, "another bag's slot dimmed")
    bag1:GetScript("OnLeave")(bag1)
    T.eq(Items.Parts(empty).shell.opts.borderColor, Items.EMPTY, "back to its own outline")
    T.eq(B.buttons[0][1]:GetAlpha(), 1)
end)

T.test("bags: the strip's key button shows and hides the keyring, and is there only when the game has one", function()
    local ns = login({ keyring = true })
    ns.module.db.showKeyring = nil
    ns.Refresh(ns.module)
    open(ns)
    local B, Slots = ns.Bags, ns.Slots
    local key = Slots.key
    T.truthy(key and key:IsShown(), "on the strip")
    T.eq(Slots.strip.slots[#Slots.strip.slots], key, "last, after the bags")
    T.truthy(key.icon:IsDesaturated(), "keyring hidden: the key dimmed")
    key:GetScript("OnClick")(key)
    T.eq(ns.module.db.showKeyring, true, "a click shows it")
    ns.Refresh(ns.module)
    T.eq(B.Size(-2) > 0 and #B.buttons[-2] > 0, true)
    T.falsy(key.icon:IsDesaturated(), "shown: the key lit")
    key:GetScript("OnClick")(key)
    T.falsy(ns.module.db.showKeyring, "again hides it")
    ns.module.db.showKeyring = nil

    local ns2 = login()
    open(ns2)
    T.falsy(ns2.Slots.key:IsShown(), "no keyring in the game: no key button")
end)

T.test("bags: BoE and BoU in the corner until bound; the set mark and junk coin with their settings; never the upgrade arrow", function()
    local ns = login()
    open(ns)
    local B, Items = ns.Bags, ns.Items
    local boe, bound, rare = B.buttons[0][4], B.buttons[0][5], B.buttons[0][1]
    T.eq(Items.Parts(boe).bind:GetText(), "BoE", "bind on equip, not yet bound")
    T.truthy(Items.Parts(boe).bind:IsShown())
    T.falsy(Items.Parts(bound).bind:IsShown(), "bound already: nothing")
    T.falsy(Items.Parts(rare).bind:IsShown(), "bind on pickup: nothing")
    T.falsy(Items.Parts(boe).set:IsShown(), "the set mark is off by default")
    T.eq(boe.JunkIcon:GetAlpha(), 0, "the junk coin off by default")
    T.eq(boe.UpgradeIcon:GetAlpha(), 0, "no upgrade arrow")
    DaylightUI:Set("Bags", "showSet", true)
    DaylightUI:Set("Bags", "showJunk", true)
    DaylightUI:Set("Bags", "showBind", false)
    stub.RunTimers()
    T.truthy(Items.Parts(boe).set:IsShown(), "in a set: marked")
    T.falsy(Items.Parts(rare).set:IsShown())
    T.eq(boe.JunkIcon:GetAlpha(), 1, "the junk coin when asked")
    T.falsy(Items.Parts(boe).bind:IsShown(), "bind type off")
end)

T.test("bags: an item you can't use wears the vendor's red, asked once per item and again after a level", function()
    local ns = login()
    -- The game's tooltip data for a slot. Item 4 needs a level you don't have (red, as RED_FONT_COLOR reads back).
    local RED, WHITE = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
    local level, asked = { ["0:4"] = RED }, 0
    local secret = false
    C_Item.GetItemInfoInstant = function() return 1, "Armor", "Cloth", "", 1, 4, 1 end
    C_Item.IsEquippableItem = function() return true end
    C_Item.GetItemSpell = function() return nil end
    _G.C_TooltipInfo = { GetBagItem = function(bag, slot)
        asked = asked + 1
        if secret then return { lines = stub.Secret({}) } end
        return { lines = { { leftText = "Item", leftColor = WHITE },
                           { leftText = "Requires Level 20", leftColor = level[bag .. ":" .. slot] or WHITE } } }
    end }
    _G.DURABILITY_TEMPLATE = "Durability %d / %d"
    local f = open(ns)
    local B, Items = ns.Bags, ns.Items
    local bad, fine = B.buttons[0][4], B.buttons[0][1]
    local function tint(btn) local r, g, b = btn.icon:GetVertexColor(); return string.format("%.2f %.2f %.2f", r, g, b) end
    local RED_ICON = string.format("%.2f %.2f %.2f", Items.UNUSABLE[1], Items.UNUSABLE[2], Items.UNUSABLE[3])
    T.eq(tint(bad), RED_ICON, "can't use: the vendor's red")
    T.eq(tint(fine), "1.00 1.00 1.00", "usable: as it is")
    T.eq(Items.UNUSABLE, DaylightUI.Npc.Shop.BAD_ICON, "the NPC window's own red")
    local before = asked
    ns.FillAll()
    stub.RunTimers()
    T.eq(asked, before, "asked once per item, not each fill")
    -- A level up asks again, and the slot follows.
    level["0:4"] = nil
    stub.FireEvent("PLAYER_LEVEL_UP")
    stub.RunTimers()
    T.eq(tint(bad), "1.00 1.00 1.00", "usable now")
    -- A red durability line (broken gear) isn't about using it.
    level["0:4"] = RED
    Items.ForgetUsable()
    local tip = C_TooltipInfo.GetBagItem
    C_TooltipInfo.GetBagItem = function(...) local t = tip(...); t.lines[2].leftText = "Durability 0 / 50"; return t end
    ns.FillAll(); stub.RunTimers()
    T.falsy(bad.dluiUnusable, "broken gear isn't unusable")
    C_TooltipInfo.GetBagItem = tip
    -- Under the client's restrictions the lines read secret, so nothing is known or cached.
    Items.ForgetUsable()
    secret = true
    ns.FillAll(); stub.RunTimers()
    T.falsy(bad.dluiUnusable, "secret: not tinted")
    secret = false
    ns.FillAll(); stub.RunTimers()
    T.truthy(bad.dluiUnusable, "asked again once it reads plain")
    -- A skill rising mid-fight under restrictions isn't known yet, so the red stays.
    secret = true
    stub.FireEvent("SKILL_LINES_CHANGED")
    stub.RunTimers()
    T.truthy(bad.dluiUnusable, "unknown for now: the red isn't taken off")
    T.eq(tint(bad), RED_ICON)
    secret = false
    DaylightUI:Set("Bags", "redUnusable", false)
    stub.RunTimers()
    T.eq(tint(bad), "1.00 1.00 1.00", "the setting off: as it is")
    T.truthy(f:IsShown())
    _G.C_TooltipInfo = nil
end)

T.test("bags: a recipe learned turns its other copies red; a level up fills once", function()
    local ns = login()
    -- Item 1 is a recipe. Whether it can be learned comes from the game's IsUsableItem.
    local learned = false
    C_Item.GetItemInfoInstant = function(link)
        if link == "|Hitem:1|h" then return 1, "Recipe", "Tailoring", "", 1, ns.Items.RECIPE, 2 end
        return 1, "Misc", "Junk", "", 1, 15, 0
    end
    C_Item.IsUsableItem = function(link) return not (link == "|Hitem:1|h" and learned) end
    open(ns)
    local recipe = ns.Bags.buttons[0][1]
    T.falsy(recipe.dluiUnusable, "not learned yet: as it is")
    learned = true
    stub.FireEvent("NEW_RECIPE_LEARNED")
    stub.RunTimers()
    T.truthy(recipe.dluiUnusable, "learned: this copy reads Already known, in red")
    -- A level up fills every slot once, not twice.
    local fills = 0
    local fill = ns.Items.Fill
    ns.Items.Fill = function(...) fills = fills + 1; return fill(...) end
    stub.FireEvent("PLAYER_LEVEL_UP")
    stub.RunTimers()
    ns.Items.Fill = fill
    T.eq(fills, #ns.Bags.Slots(), "one fill per slot")
    C_Item.IsUsableItem = nil
end)

T.test("bags: an item not loaded yet isn't judged usable or not until it loads", function()
    local ns = login()
    -- Before it loads, the game's tooltip is one red line ("Retrieving item information").
    local RED, WHITE = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
    C_Item.GetItemInfoInstant = function() return 1, "Armor", "Cloth", "", 1, 4, 1 end
    C_Item.IsEquippableItem = function() return true end
    C_Item.GetItemSpell = function() return nil end
    _G.C_TooltipInfo = { GetBagItem = function(bag, slot)
        if world.bind["|Hitem:7|h"] == nil and bag == 0 and slot == 6 then
            return { lines = { { leftText = "Retrieving item information", leftColor = RED } } }
        end
        return { lines = { { leftText = "Item", leftColor = WHITE } } }
    end }
    local loaded = {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end,
                 ContinueOnItemLoad = function(_, fn) loaded[bag .. ":" .. slot] = fn end }
    end }
    open(ns)
    local late = ns.Bags.buttons[0][6]
    T.falsy(late.dluiUnusable, "not loaded: not tinted")
    world.bind["|Hitem:7|h"] = 3
    loaded["0:6"]()
    T.falsy(late.dluiUnusable, "loaded and usable: still not tinted")
    _G.Item, _G.C_TooltipInfo = nil, nil
end)

T.test("bags: an item whose bind type isn't loaded yet gets it once it loads", function()
    local ns = login()
    local loaded = {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end,
                 ContinueOnItemLoad = function(_, fn) loaded[bag .. ":" .. slot] = fn end }
    end }
    open(ns)
    local late = ns.Bags.buttons[0][6]
    T.falsy(ns.Items.Parts(late).bind:IsShown(), "not known yet")
    T.truthy(loaded["0:6"], "asked to be told when it loads")
    world.bind["|Hitem:7|h"] = 3
    loaded["0:6"]()
    T.eq(ns.Items.Parts(late).bind:GetText(), "BoU", "filled in once loaded")
    _G.Item = nil
end)

T.test("bags: the search language: kinds, quality, names, # for keywords only", function()
    local ns = login()
    local S = ns.Search
    local function m(text, facts) return S.Parse(text)(facts) == true end
    local sword = { classID = 2, subClassID = 7, quality = 2, name = "Rusty Sword" }
    local bread = { classID = 0, subClassID = 5, quality = 1, name = "Tough Hunk of Bread" }
    local potion = { classID = 0, subClassID = 1, quality = 1, name = "Minor Healing Potion" }
    local ore = { classID = 7, subClassID = 7, quality = 1, name = "Copper Ore" }
    local task = { classID = 12, quality = 1, name = "Wolf Pelt", questItem = true }
    local gray = { classID = 15, quality = 0, name = "Broken Fang" }
    T.isnil(S.Parse("  "), "no search")
    T.truthy(m("gear", sword)); T.falsy(m("gear", bread))
    T.truthy(m("food", bread)); T.truthy(m("drink", bread), "food and drink share a subclass")
    T.truthy(m("potion", potion)); T.falsy(m("potion", bread))
    T.truthy(m("reagent", ore)); T.truthy(m("quest", task)); T.truthy(m("junk", gray))
    T.truthy(m("uncommon", sword)); T.falsy(m("rare", sword))
    T.truthy(m("q>common", sword)); T.falsy(m("q>uncommon", sword)); T.truthy(m("q>=2", sword))
    T.truthy(m("q<uncommon", bread))
    T.truthy(m("healing", potion), "any other word is a name")
    T.truthy(m("BREAD", bread), "case doesn't matter")
    T.truthy(m("pelt", task))
    T.truthy(m("rusty", sword)); T.falsy(m("#rusty", sword), "# is the keyword only: unknown matches nothing")
    T.truthy(m("#gear", sword))
    local named = { classID = 15, quality = 1, name = "Gear Wheel" }
    T.truthy(m("gear", named), "a plain keyword also finds names containing it")
    T.falsy(m("#gear", named), "but not with #")
end)

T.test("bags: the search joins terms: & all, | any, ! not; binding, item level and equipment sets", function()
    local ns = login()
    local S = ns.Search
    local function m(text, facts) return S.Parse(text)(facts) == true end
    local boe = { classID = 4, quality = 2, name = "Fine Gloves", bindType = 2, bound = false, itemLevel = 18 }
    local mine = { classID = 2, quality = 3, name = "Old Blade", bindType = 2, bound = true, itemLevel = 25,
                   inSet = true, setNames = "Tank,PvP" }
    local bread = { classID = 0, subClassID = 5, quality = 1, name = "Bread", bindType = 0 }
    T.truthy(m("boe", boe)); T.falsy(m("boe", mine), "bound now: not BoE")
    T.truthy(m("soulbound", mine)); T.falsy(m("soulbound", boe))
    T.truthy(m("set", mine)); T.falsy(m("#set", boe))
    T.truthy(m("pvp", mine), "an equipment set's name finds its items")
    T.truthy(m("ilvl>20", mine)); T.falsy(m("ilvl>20", boe)); T.truthy(m("ilvl<=18", boe))
    T.truthy(m("ilvl15-20", boe)); T.falsy(m("ilvl 19 - 30", boe), "a range, both ends in")
    T.falsy(m("ilvl>0", bread), "no item level: never matches a level")
    T.truthy(m("boe & q>common", boe)); T.falsy(m("boe & q>uncommon", boe))
    T.truthy(m("food | boe", bread)); T.truthy(m("food | boe", boe)); T.falsy(m("food | boe", mine))
    T.truthy(m("gear & !set", boe)); T.falsy(m("gear & !set", mine))
    T.truthy(m("!!set", mine), "!! cancels out")
    T.truthy(m("weapon & set | food", bread), "& binds tighter than |")
    T.truthy(m("boe &", boe), "a half-typed join is left out")
    T.isnil(S.Parse(" ! & | "), "nothing but joins: no search")
    T.truthy(m("food; boe", bread)); T.truthy(m("food;boe", boe)); T.falsy(m("food; boe", mine), "; is | too")
    T.truthy(m("weapon & set; food", bread), "& binds tighter than ;")
    T.truthy(S.HELP:find("; works like |", 1, true), "the search's help teaches ;")
end)

T.test("bags: the tool row's icons keep their colors", function()
    local ns = login()
    local f = open(ns)
    T.truthy(#f.tools > 0)
    for _, b in ipairs(f.tools) do
        T.falsy(b.icon:IsDesaturated(), "in color, not gray")
    end
end)

T.test("bags: the Disenchant button: shown to enchanters; hovered, the secure button lies over it above the bag", function()
    local ns = login()
    local known = false
    _G.IsPlayerSpell = function(id) return id == ns.Disenchant.SPELL and known end
    stub.FireEvent("SPELLS_CHANGED")
    local f = open(ns)
    local b = f.disenchantButton
    T.falsy(b:IsShown(), "not an enchanter: no button")
    T.eq(select(2, f.search:GetPoint(2)), f.viewButton, "the search ends at the last tool shown")
    known = true
    stub.FireEvent("SPELLS_CHANGED")
    T.truthy(b:IsShown())
    T.eq(select(2, f.search:GetPoint(2)), b, "the search ends at it")
    -- Where the bag button is on screen, since the fake game has no positions.
    b.GetLeft, b.GetBottom = function() return 400 end, function() return 300 end
    b:SetSize(28, 28)
    stub.secure = true
    T.isnil(ns.Disenchant.caster.button, "nothing secure until the mouse comes: never over another window")
    b:GetScript("OnEnter")(b)
    local o = ns.Disenchant.caster.button
    T.truthy(o and o:IsShown(), "the secure button lies over ours")
    T.eq(o:GetAttribute("type1"), "spell"); T.eq(o:GetAttribute("spell"), ns.Disenchant.SPELL)
    T.eq(o:GetParent(), UIParent, "never inside the bag: the bag still closes in a fight")
    T.eq(o:GetFrameStrata(), "HIGH", "a strata above the bag: at the bag's own, its icon keeps the mouse")
    T.eq(o:GetAttribute("useOnKeyDown"), false, "the hand comes after the press, not during it")
    local _, rel, _, x, y = o:GetPoint(1)
    T.eq(rel, UIParent); T.eq(x, 400); T.eq(y, 300)
    -- It takes the mouse, and the bag button keeps its light and tooltip through it.
    o:GetScript("OnEnter")(o)
    T.truthy(o:IsShown())
    o:GetScript("OnLeave")(o)
    T.falsy(o:IsShown(), "the mouse left: it goes")
    b:GetScript("OnEnter")(b)
    stub.EnterCombat()
    T.falsy(o:IsShown(), "hidden as the fight starts")
    b:GetScript("OnEnter")(b)
    T.falsy(o:IsShown(), "and stays hidden in it")
    stub.LeaveCombat()
    b:GetScript("OnEnter")(b)
    T.truthy(o:IsShown(), "back at the next hover after the fight")
    f:Hide()
    T.falsy(o:IsShown(), "the bag closed: it goes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.secure = false
    _G.IsPlayerSpell = nil
end)

T.test("bags: the secure Disenchant button goes where ours is, each time the mouse comes", function()
    local ns = login()
    _G.IsPlayerSpell = function(id) return id == ns.Disenchant.SPELL end
    stub.FireEvent("SPELLS_CHANGED")
    local f = open(ns)
    local b = f.disenchantButton
    local left = 400
    b.GetLeft, b.GetBottom = function() return left end, function() return 300 end
    b:SetSize(28, 28)
    stub.secure = true
    b:GetScript("OnEnter")(b)
    local o = ns.Disenchant.caster.button
    T.eq(select(4, o:GetPoint(1)), 400)
    o:GetScript("OnLeave")(o)
    left = 440       -- the row closed up, or the bag moved
    b:GetScript("OnEnter")(b)
    T.eq(select(4, o:GetPoint(1)), 440)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.secure = false
    _G.IsPlayerSpell = nil
end)

T.test("bags: gear's item level in the bottom left corner, off by default; the bank follows", function()
    local ns = login()
    local instant, detailed = C_Item.GetItemInfoInstant, C_Item.GetDetailedItemLevelInfo
    C_Item.GetItemInfoInstant = function(link)
        if link == "|Hitem:4|h" then return 4, "Armor", "Cloth", "INVTYPE_HAND", 1, 4, 1 end
        return 1, "Misc", "Junk", "", 1, 15, 0
    end
    C_Item.GetDetailedItemLevelInfo = function(link) if link == "|Hitem:4|h" then return 17.6 end end
    open(ns)
    local Items = ns.Items
    local gloves, other = ns.Bags.buttons[0][4], ns.Bags.buttons[0][1]
    T.falsy(Items.Parts(gloves).level:IsShown(), "off by default")
    DaylightUI:Set("Bags", "showLevel", true)
    stub.RunTimers()
    T.truthy(Items.Parts(gloves).level:IsShown())
    T.eq(Items.Parts(gloves).level:GetText(), "18", "rounded")
    T.falsy(Items.Parts(other).level:IsShown(), "not gear: nothing")
    T.eq(ns.DEFAULTS.bank.showLevel, false, "the bank has its own copy, off too")
    T.truthy(ns.BANK_SHARED.showLevel, "and follows the bags unless it has its own look")
    C_Item.GetItemInfoInstant, C_Item.GetDetailedItemLevelInfo = instant, detailed
end)

T.test("bags: every options page is valid", function()
    login()
    local n = 0
    for id, page in DaylightUI.Options.Pages() do
        if page.section == "Bags" then
            T.eq(#DaylightUI.Options.ValidatePage(page), 0, id)
            n = n + 1
        end
    end
    T.eq(n, 4, "Bags, Bank, Bank and alts and Categories")
    T.falsy(stub.ChatContains("Options ("))
end)

-- Categories: item classes for the fake items (GetItemInfoInstant), and what stacks.
local function categoryWorld()
    world.class = { [1] = 2, [2] = 2, [4] = 4, [5] = 7, [6] = 4, [7] = 4, [8] = 0, [9] = 0 }
    world.maxStack = { [5] = 20, [8] = 20, [9] = 20 }
    world.items[0][1].itemID = 1        -- a rare weapon
    world.items[0][2].itemID = 2        -- a gray weapon, so Junk wins
    world.items[0][4].itemID = 4
    world.items[0][5].itemID = 6
    world.items[0][6].itemID = 7
    world.items[5][1].itemID = 5        -- trade goods in the profession bag
    world.items[0][8] = { iconFileID = 108, stackCount = 5, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    world.items[1][1] = { iconFileID = 108, stackCount = 7, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    world.items[1][2] = { iconFileID = 109, stackCount = 2, quality = 1, hyperlink = "|Hitem:9|h", itemID = 9, itemName = "Apple" }
    C_Item.GetItemInfoInstant = function(id)
        local itemID = type(id) == "number" and id or tonumber(string.match(tostring(id), "item:(%d+)"))
        return itemID, "", "", "", 0, world.class[itemID], 0
    end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        local itemID = tonumber(string.match(tostring(link), "item:(%d+)"))
        if world.maxStack[itemID] then return "name", link, 1, 1, 1, "", "", world.maxStack[itemID], "", 1, 1, 0, 0, 0 end
        return getInfo(link)
    end
end

local function catLogin()
    local ns = login({ view = "categories" })
    categoryWorld()
    local f = open(ns)
    ns.Relayout()
    ns.FillAll()
    return ns, f
end

local function groupOf(ns, btn)
    for _, g in ipairs(ns.Layout.Groups(ns.module.db, ns.window)) do
        for _, e in ipairs(g.entries) do
            if e.button == btn then return g.key end
            for _, x in ipairs(e.extra or {}) do if x == btn then return g.key, true end end
        end
    end
end

T.test("bags: categories put each item in its group; the most specific wins", function()
    local ns = catLogin()
    local B = ns.Bags
    T.eq(groupOf(ns, B.buttons[0][1]), "weapon")
    T.eq(groupOf(ns, B.buttons[0][2]), "junk", "a gray weapon is Junk")
    T.eq(groupOf(ns, B.buttons[0][4]), "sets", "in an equipment set")
    T.eq(groupOf(ns, B.buttons[0][5]), "armor")
    T.eq(groupOf(ns, B.buttons[5][1]), "tradegoods", "the profession bag's items too")
    T.eq(groupOf(ns, B.buttons[0][3]), "empty")
end)

T.test("bags: stacks of the same item show as one, with the total", function()
    local ns = catLogin()
    local B = ns.Bags
    local first, other = B.buttons[0][8], B.buttons[1][1]
    T.eq(groupOf(ns, first), "consumable")
    local _, hidden = groupOf(ns, other)
    T.truthy(hidden, "the second stack is folded into the first")
    T.falsy(other:IsShown())
    T.eq(first.dluiCount, 12, "the total on the one that shows")
    T.eq(first.calls.count, 12)
    DaylightUI:Set("Bags", "view", "grid")
    stub.RunTimers()
    T.truthy(other:IsShown(), "the grid shows every slot")
    T.isnil(first.dluiCount)
end)

T.test("bags: a combined stack splits only its own stack", function()
    local ns = catLogin()
    local first = ns.Bags.buttons[0][8]
    T.eq(first.calls.count, 12, "the total shows")
    T.truthy(first.count < 12, "the split box offers the real stack")
end)

-- The game's pick up and put down, as far as stacking goes. Dropping on the same
-- item tops it up and the rest stays where it was. A split of n put in a free slot
-- makes a stack of n there. world.held is what's on the cursor.
local function cursorWorld()
    world.held = nil
    _G.CursorHasItem = function() return world.held ~= nil end
    _G.ClearCursor = function() world.held = nil end
    C_Container.SplitContainerItem = function(bag, slot, n) world.held = { bag = bag, slot = slot, n = n } end
    C_Container.PickupContainerItem = function(bag, slot)
        local here, held = world.items[bag][slot], world.held
        if not held then world.held = { bag = bag, slot = slot }; return end
        local from = world.items[held.bag][held.slot]
        if not here then
            local n = held.n or from.stackCount
            local copy = {}
            for k, v in pairs(from) do copy[k] = v end
            copy.stackCount = n
            world.items[bag][slot] = copy
            from.stackCount = from.stackCount - n
            if from.stackCount == 0 then world.items[held.bag][held.slot] = nil end
            world.held = nil
            return
        end
        local id = tonumber(string.match(from.hyperlink, "item:(%d+)"))
        local room = (world.maxStack[id] or 1) - here.stackCount
        local n = math.min(room, from.stackCount)
        here.stackCount = here.stackCount + n
        from.stackCount = from.stackCount - n
        if from.stackCount == 0 then world.items[held.bag][held.slot] = nil end
        world.held = nil
    end
end

-- A shift-click and OK in the split box, as the game does them. The click sets
-- the button's SplitStack afresh every time (ContainerFrame.lua).
local function shiftSplit(btn, n)
    btn.SplitStack = function(self, split)
        C_Container.SplitContainerItem(self:GetParent():GetID(), self:GetID(), split)
    end
    StackSplitFrame.owner, StackSplitFrame.split = btn, n
    StackSplitOkayButton_OnClick()
end

T.test("bags: a split while trading lands in a free slot and comes back on the cursor as its own stack", function()
    local ns = catLogin()
    cursorWorld()
    local bread = ns.Bags.buttons[1][1]                -- 7 Bread
    shiftSplit(bread, 3)
    stub.RunTimers()
    T.eq(world.held.n, 3, "not trading: the split just stays on the cursor")
    T.isnil(world.held.slot ~= 1 and world.held or nil)
    ClearCursor()
    stub.FireEvent("TRADE_SHOW")
    shiftSplit(bread, 3)
    stub.RunTimers()
    T.eq(world.items[1][1].stackCount, 4, "4 left behind")
    local at = world.held
    T.truthy(at and not at.n, "a whole stack on the cursor")
    T.eq(world.items[at.bag][at.slot].stackCount, 3, "of just the 3")
    T.eq(world.items[0][3].stackCount, 3, "put down in the first free slot")
end)

T.test("bags: opening the bag merges part stacks of one item into as few slots as can be", function()
    local ns = catLogin()
    cursorWorld()
    world.items[1][3] = { iconFileID = 108, stackCount = 18, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8 }
    ns.Stack.Run()
    stub.RunTimers()
    T.eq(world.items[0][8].stackCount, 20, "5 + 7 + 18 Bread: the first fills up")
    T.isnil(world.items[1][1], "the 7 went in")
    T.eq(world.items[1][3].stackCount, 10, "the rest stays put")
    T.eq(world.items[1][2].stackCount, 2, "a lone stack is left alone")
    T.falsy(CursorHasItem(), "nothing left on the cursor")
end)

T.test("bags: no stacking in combat, while trading, or with the setting off", function()
    local ns = catLogin()
    cursorWorld()
    stub.EnterCombat()
    ns.Stack.Run(); stub.RunTimers()
    T.eq(world.items[1][1].stackCount, 7, "in combat")
    stub.LeaveCombat()
    stub.FireEvent("TRADE_SHOW")
    ns.Stack.Run(); stub.RunTimers()
    T.eq(world.items[1][1].stackCount, 7, "a split to trade stays split")
    stub.FireEvent("TRADE_CLOSED")
    DaylightUI:Set("Bags", "autoStack", false)
    ns.Stack.Run(); stub.RunTimers()
    T.eq(world.items[1][1].stackCount, 7, "setting off")
    DaylightUI:Set("Bags", "autoStack", true)
    ns.Stack.Run(); stub.RunTimers()
    T.isnil(world.items[1][1], "on again: merged")
end)

T.test("bags: stacks show apart while trading, at the mail and auction house, or with combining off", function()
    local ns = catLogin()
    local B = ns.Bags
    local first, other = B.buttons[0][8], B.buttons[1][1]
    for _, ev in ipairs({ { "TRADE_SHOW", "TRADE_CLOSED" }, { "MAIL_SHOW", "MAIL_CLOSED" },
                          { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" } }) do
        stub.FireEvent(ev[1])
        stub.RunTimers()
        T.truthy(other:IsShown(), ev[1] .. ": every stack shows")
        T.isnil(first.dluiCount)
        stub.FireEvent(ev[2])
        stub.RunTimers()
        T.falsy(other:IsShown(), ev[2] .. ": combined again")
        T.eq(first.dluiCount, 12)
    end
    DaylightUI:Set("Bags", "combineStacks", false)
    stub.RunTimers()
    T.truthy(other:IsShown(), "combining off")
    T.isnil(first.dluiCount)
end)

T.test("bags: soul shards (which don't stack) show as one stack, with the count; apart with the setting off", function()
    local ns = login({ view = "categories" })
    categoryWorld()
    world.class[6265] = 15
    world.maxStack[6265] = 1
    for _, s in ipairs({ 3, 4, 5 }) do
        world.items[1][s] = { iconFileID = 134075, stackCount = 1, quality = 1, hyperlink = "|Hitem:6265|h", itemID = 6265, itemName = "Soul Shard" }
    end
    open(ns); ns.Relayout(); ns.FillAll()
    local B = ns.Bags
    local first = B.buttons[1][3]
    T.truthy(first:IsShown())
    T.falsy(B.buttons[1][4]:IsShown(), "the other shards fold into the first")
    T.falsy(B.buttons[1][5]:IsShown())
    T.eq(first.dluiCount, 3, "the count on the one that shows")
    T.eq(first.calls.count, 3)
    stub.FireEvent("TRADE_SHOW"); stub.RunTimers()
    T.truthy(B.buttons[1][4]:IsShown(), "apart while trading, like any stack")
    stub.FireEvent("TRADE_CLOSED"); stub.RunTimers()
    T.eq(first.dluiCount, 3)
    DaylightUI:Set("Bags", "stackShards", false)
    stub.RunTimers()
    T.truthy(B.buttons[1][4]:IsShown(), "setting off: every shard on its own")
    T.isnil(first.dluiCount)
    DaylightUI:Set("Bags", "stackShards", true)
    DaylightUI:Set("Bags", "combineStacks", false)
    stub.RunTimers()
    T.eq(first.dluiCount, 3, "shards stack even with combining off")
    T.truthy(B.buttons[1][1]:IsShown(), "while Bread shows apart")
end)

T.test("bags: groups flow with headings; a heading folds its group; dropping an item on one pins it", function()
    local ns, f = catLogin()
    local B, Cat = ns.Bags, ns.Categories
    local h
    for _, x in ipairs(f.headings) do if x:IsShown() and x.key == "weapon" then h = x end end
    T.truthy(h, "a heading for Weapons")
    T.eq(h.name, "Weapons")
    h:GetScript("OnClick")(h)
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)   -- its items fade out
    T.truthy(Cat.IsCollapsed("weapon"))
    T.falsy(B.buttons[0][1]:IsShown(), "folded: its items out of sight")
    T.eq(h.count:GetText(), "1", "its count on the heading")
    h:GetScript("OnClick")(h)
    stub.RunTimers()
    T.truthy(B.buttons[0][1]:IsShown(), "open again")
    -- An apple dropped on Weapons stays there.
    _G.GetCursorInfo = function() return "item", 9 end
    local cleared = false
    _G.ClearCursor = function() cleared = true end
    h:GetScript("OnReceiveDrag")(h)
    T.eq(Cat.PinOf(9), "weapon")
    T.truthy(cleared, "the item goes back to its slot")
    ns.Relayout()
    T.eq(groupOf(ns, B.buttons[1][2]), "weapon")
    _G.GetCursorInfo = nil
    Cat.Unpin(9)
    T.eq(groupOf(ns, B.buttons[1][2]), "consumable")
end)

T.test("bags: group headings read upper case in the accent with a count and chevron", function()
    local ns, f = catLogin()
    local Style, Cat = DaylightUI.Style, ns.Categories
    local function headOf(key)
        for _, x in ipairs(f.headings) do if x:IsShown() and x.key == key then return x end end
    end
    local h = headOf("weapon")
    T.truthy(h, "a heading for Weapons")
    T.eq(h.text:GetText(), string.upper(h.name), "name in upper case")
    local r, g, b = h.text:GetTextColor()
    local ar, ag, ab = Style.Accent()
    T.near(r, ar, 0.01); T.near(g, ag, 0.01); T.near(b, ab, 0.01)
    T.eq(h.count:GetText(), "1")
    T.eq(h.chev.__rotation or 0, 0, "open: the chevron points down")
    h:GetScript("OnClick")(h)
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    h = headOf("weapon")
    local lr, lg, lb = h.text:GetTextColor()
    T.near(lr, Style.INK.LABEL[1], 0.01); T.near(lg, Style.INK.LABEL[2], 0.01); T.near(lb, Style.INK.LABEL[3], 0.01)
    T.near(h.chev.__rotation or 0, math.pi / 2, 0.001, "folded: the chevron points right")
    h:GetScript("OnClick")(h)
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and slot == 5 end }
    local now, getTime = stub.now, _G.GetTime
    stub.now = 1000
    _G.GetTime = function() return stub.now end
    DaylightUI:Set("general", "accent", "gradient")
    local ok, err = pcall(function()
        ns.Relayout()
        local rec = headOf("recent")
        T.truthy(rec, "a Recent heading")
        T.truthy(string.find(rec.text:GetText(), "|c", 1, true), "Recent paints letter by letter under a gradient accent")
    end)
    DaylightUI:Set("general", "accent", nil)
    _G.C_NewItems = nil
    stub.now, _G.GetTime = now, getTime
    T.truthy(ok, tostring(err))
end)

-- A folded heading beside open groups left a hole under it and pushed them about,
-- and since the fold is saved the odd shape stayed. Folded headings now take a line
-- of their own (side by side when they follow each other), and open groups keep theirs.
T.test("bags: a folded group's heading takes its own line, never beside an open group", function()
    local ns, f = catLogin()
    local Cat = ns.Categories
    local function top(key)
        for _, x in ipairs(f.headings) do
            if x:IsShown() and x.key == key then return select(5, x:GetPoint(1)) end
        end
    end
    T.eq(top("consumable"), top("sets"), "open: side by side")
    Cat.ToggleCollapsed("sets")
    stub.RunTimers()
    local foldTop = top("sets")
    T.truthy(foldTop < top("consumable"), "below the open groups before it")
    T.truthy(top("weapon") < foldTop, "the open groups after it on the next line")
    T.eq(top("weapon"), top("armor"), "which still sit side by side")
    T.eq(foldTop - top("weapon"), ns.Layout.HEAD + ns.Layout.ROW_GAP, "a folded line is only its heading tall")
    Cat.ToggleCollapsed("weapon")
    stub.RunTimers()
    T.eq(top("weapon"), top("sets"), "folded ones that follow each other share the line")
    Cat.ToggleCollapsed("sets"); Cat.ToggleCollapsed("weapon")
    stub.RunTimers()
    T.eq(top("consumable"), top("weapon"), "all open: the flow as before")
end)

-- Folding a group should animate.
T.test("bags: folding a group eases: its items fade out, the rest glide, the window glides to its size", function()
    local ns, f = catLogin()
    local B = ns.Bags
    local Motion, Feel = DaylightUI.Motion, DaylightUI.Win.Feel
    local function settle()
        local d = Motion.Driver()
        if d then stub.RunOnUpdate(d, 1) end
        d = Feel.Driver()
        if d then stub.RunOnUpdate(d, 1) end
    end
    -- One driver, by the anchor (Feel.Glide), never a Translation animation. Those
    -- moved in whole pixels on their own curve and the icons jittered in game.
    local function gliding(b)
        T.falsy(b.__duiMotion and b.__duiMotion.glide and b.__duiMotion.glide:IsPlaying(), "no Translation")
        return Feel.Moving(b)
    end
    local function click(key)
        for _, x in ipairs(f.headings) do
            if x:IsShown() and x.key == key then x:GetScript("OnClick")(x, "LeftButton") end
        end
    end
    settle()
    local setItem, weapon = B.buttons[0][4], B.buttons[0][1]
    local h0 = f:GetHeight()
    local y0 = select(5, weapon:GetPoint(1))
    click("sets")
    T.truthy(setItem:IsShown(), "the folded item fades, it doesn't vanish")
    T.truthy(gliding(weapon), "a group pushed down glides there")
    T.eq(select(5, weapon:GetPoint(1)), y0, "from where it was")
    T.eq(f:GetHeight(), h0, "the window starts from its old size")
    stub.RunOnUpdate(Feel.Driver(), Motion.NORMAL / 2)
    local midY, midH = select(5, weapon:GetPoint(1)), f:GetHeight()
    T.truthy(midY < y0 and midH > h0, "halfway, slot and window both on their way")
    settle()
    T.truthy(select(5, weapon:GetPoint(1)) < midY, "the slot at its new spot")
    T.falsy(setItem:IsShown(), "gone once faded")
    T.truthy(f:GetHeight() > h0, "and the window got there")
    click("sets")
    T.truthy(setItem:IsShown())
    T.eq(setItem:GetAlpha(), 0, "an opened group's items fade in")
    settle()
    T.eq(setItem:GetAlpha(), 1)
    T.eq(f:GetHeight(), h0)
    -- Anything else that lays it out (loot, a sort) applies at once.
    settle()
    ns.Categories.Pin(9, "sets")
    T.falsy(gliding(weapon), "no glide but a fold's")
    ns.Categories.Unpin(9)
    -- A fold mid-fade then laid out again: the faded item comes back whole.
    click("sets")
    ns.Relayout()
    click("sets")
    settle()
    T.eq(setItem:GetAlpha(), 1, "back at full")
    T.truthy(setItem:IsShown())
end)

T.test("bags: your own groups, from a search, come first; rename and reorder", function()
    local ns = catLogin()
    local B, Cat = ns.Bags, ns.Categories
    local key = Cat.AddCustom("Shinies", "q>=rare")
    T.eq(groupOf(ns, B.buttons[0][1]), key, "the rare weapon in the custom group")
    T.eq(Cat.Order()[2], key, "after Recent")
    Cat.Rename("armor", "Clothes")
    T.eq(Cat.Get("armor").name, "Clothes")
    local before = Cat.Order()
    local i
    for n, k in ipairs(before) do if k == "armor" then i = n end end
    Cat.Move("armor", -1)
    T.eq(Cat.Order()[i - 1], "armor", "moved up one")
    Cat.DeleteCustom(key)
    T.isnil(Cat.Get(key))
    T.eq(groupOf(ns, B.buttons[0][1]), "weapon")
end)

T.test("bags: a built-in group can be deleted (its items go where they'd go next) and brought back", function()
    local ns = catLogin()
    local B, Cat = ns.Bags, ns.Categories
    T.eq(groupOf(ns, B.buttons[0][1]), "weapon")
    T.truthy(Cat.CanDelete("weapon"))
    T.eq(Cat.CanDelete("other"), false, "Other catches what's left: it stays")
    T.eq(Cat.CanDelete("empty"), false, "and so do the empty slots")
    Cat.Delete("weapon")
    T.isnil(Cat.Get("weapon"), "gone")
    for _, k in ipairs(Cat.Order()) do T.truthy(k ~= "weapon", "out of the order") end
    T.eq(groupOf(ns, B.buttons[0][1]), "other", "the weapon falls to Other")
    Cat.Pin(9, "weapon")
    T.isnil(Cat.PinOf(9), "nothing can be moved into a deleted group")
    T.eq(Cat.Removed()[1], "weapon", "listed to bring back")
    Cat.Restore("weapon")
    T.truthy(Cat.Get("weapon"))
    T.eq(groupOf(ns, B.buttons[0][1]), "weapon", "back where it was")
    -- Sets and quest items come before Junk so they're never sold. Deleting those
    -- groups mustn't make a gray set or quest item junk.
    Cat.Delete("sets"); Cat.Delete("quest")
    T.eq(Cat.TESTS.junk({ quality = 0, inSet = true }), false, "a gray set item is never junk")
    Cat.Restore("sets"); Cat.Restore("quest")
    -- In the options list a built-in line's delete works, but Other's doesn't.
    local list
    for _, page in ipairs(ns.OPTIONS.pages) do
        for _, card in ipairs(page.groups or {}) do
            for _, item in ipairs(card.items) do if item.label == "Groups" then list = item end end
        end
    end
    local row = CreateFrame("Frame")
    list.build(row); list.update(row)
    local armor
    for _, line in ipairs(row.lines) do if line.key == "armor" then armor = line end end
    armor.delete:GetScript("OnClick")(armor.delete)
    armor.delete:GetScript("OnClick")(armor.delete)
    T.isnil(Cat.Get("armor"), "two clicks delete Armor")
    Cat.Restore("armor")
end)

T.test("bags: Add a group asks only its name, and the empty group waits in the bag to be filled", function()
    local ns, f = catLogin()
    local Cat = ns.Categories
    local add
    for _, page in ipairs(ns.OPTIONS.pages) do
        for _, card in ipairs(page.groups or {}) do
            for _, item in ipairs(card.items) do if item.label == "Add a group" then add = item end end
        end
    end
    local row = CreateFrame("Frame")
    add.build(row)
    row.add:GetScript("OnClick")(row.add)
    stub.popup.data.onAccept("Keepers")
    stub.RunTimers()
    local key = Cat.Custom()[1] and Cat.Custom()[1].key
    T.truthy(key, "one box, and the group exists")
    T.eq(Cat.Get(key).name, "Keepers")
    T.isnil(Cat.Get(key).search, "no search: it takes only what you move to it")
    -- With nothing in it yet, no heading clutters the bag until you hold Shift
    -- with an item on the cursor.
    local function headingOf()
        for _, x in ipairs(f.headings) do if x:IsShown() and x.key == key then return x end end
    end
    T.isnil(headingOf(), "an empty group of yours stays out of the bag")
    _G.CursorHasItem = function() return true end
    stub.FireEvent("CURSOR_CHANGED")
    T.isnil(headingOf(), "an item on the cursor alone moves nothing")
    _G.IsShiftKeyDown = function() return true end
    stub.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    local h = headingOf()
    T.truthy(h, "Shift with an item held shows it, to drop on")
    T.truthy(string.find(h.count:GetText(), "drag items here", 1, true), "and says what it's for")
    local hr, hg, hb = h.count:GetTextColor()
    local ink = DaylightUI.Style.INK.LABEL
    T.near(hr, ink[1], 0.01); T.near(hg, ink[2], 0.01); T.near(hb, ink[3], 0.01)
    _G.GetCursorInfo = function() return "item", 9 end
    _G.ClearCursor = function() _G.CursorHasItem = nil end
    h:GetScript("OnReceiveDrag")(h)
    _G.GetCursorInfo = nil
    stub.FireEvent("CURSOR_CHANGED")
    _G.IsShiftKeyDown = nil
    stub.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
    ns.Relayout()
    T.eq(groupOf(ns, ns.Bags.buttons[1][2]), key, "dropped in")
    T.eq(headingOf().text:GetText(), "KEEPERS", "the hint goes once it holds something")
    T.eq(headingOf().count:GetText(), "1", "and the count takes its place")
    -- A search can be set and taken away again.
    Cat.SetSearch(key, "q>=rare")
    T.eq(Cat.Get(key).search, "q>=rare")
    Cat.SetSearch(key, "")
    T.isnil(Cat.Get(key).search)
    T.eq(groupOf(ns, ns.Bags.buttons[1][2]), key, "what you moved stays")
    Cat.DeleteCustom(key)
end)

T.test("bags: any item marked as junk sells with the rest; the menu in any view, and a key for the item under the mouse", function()
    local ns = catLogin()
    local Cat, B = ns.Categories, ns.Bags
    local bread = B.buttons[0][8]
    local function sold(id)
        for _, j in ipairs(ns.Junk.Items()) do if string.find(j.link or "", "item:" .. id .. "|", 1, true) then return true end end
        return false
    end
    local grayIn = #ns.Junk.Items() > 0
    T.truthy(Cat.ToggleJunk(8, "Bread"))
    T.eq(Cat.PinOf(8), "junk")
    ns.Relayout()
    T.eq(groupOf(ns, bread), "junk")
    if grayIn then T.truthy(sold(8), "sold at a vendor like a gray") end
    -- Its tooltip carries the junk coin and says it sells.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:Show()
    local added, addLine = {}, GameTooltip.AddLine
    GameTooltip.AddLine = function(_, text) added[#added + 1] = text end
    ns.Junk.OnTip(GameTooltip, { id = 8 })
    ns.Junk.OnTip(GameTooltip, { id = 9 })
    GameTooltip.AddLine = addLine
    T.eq(#added, 1, "one line added, only for the marked item")
    T.truthy(ns.Junk.TipText(8):find("bags-junkcoin", 1, true), "the game's junk coin")
    T.truthy(ns.Junk.TipText(8):find("next vendor", 1, true), "says it sells while selling is on")
    DaylightUI:Set("Bags", "sellJunk", false)
    T.falsy(ns.Junk.TipText(8):find("vendor", 1, true), "just Junk with selling off")
    DaylightUI:Set("Bags", "sellJunk", true)
    T.isnil(ns.Junk.TipText(9), "an item not marked: nothing")
    GameTooltip:Hide()
    -- The Alt-right-click menu has the row in bag-by-bag view too.
    ns.module.db.view = "grid"
    local keys, pick
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, k, _, _, onPick) keys, pick = k, onPick end
    Cat.Menu(bread)
    DaylightUI.Widgets.OpenMenu = openMenu
    local has = false
    for _, k in ipairs(keys) do has = has or k == "junkmark" end
    T.truthy(has, "Sell as junk / Not junk in the menu")
    pick("junkmark")
    T.isnil(Cat.PinOf(8), "Not junk: back to its own group")
    -- The key binding acts on the item under the mouse.
    _G.GetMouseFoci = function() return { bread } end
    T.truthy(BINDING_NAME_DAYLIGHTUI_BAGS_JUNK)
    T.truthy(BINDING_HEADER_DAYLIGHTUI_BAGS, "its own key bindings heading")
    DaylightUI.BagsMarkJunk()
    T.eq(Cat.PinOf(8), "junk")
    _G.GetMouseFoci = function() return { UIParent } end
    DaylightUI.BagsMarkJunk()
    T.eq(Cat.PinOf(8), "junk", "not over a bag item: nothing")
    _G.GetMouseFoci = nil
    -- A locked item marked as junk is unlocked, since you asked for it to go.
    Cat.ToggleLock(9)
    Cat.ToggleJunk(9, "Apple")
    T.falsy(Cat.IsLocked(9))
end)

T.test("bags: your own groups shared as text and imported back", function()
    local ns = catLogin()
    local Cat = ns.Categories
    -- A stand-in for the game's encoder (as in test_profiles): a store behind a token.
    local store = {}
    _G.C_EncodingUtil = {
        SerializeCBOR = function(v) store[#store + 1] = v; return "cbor" .. #store end,
        DeserializeCBOR = function(s) local v = store[tonumber(string.match(s, "^cbor(%d+)$") or "")]
            if not v then error("bad cbor") end; return v end,
        CompressString = function(s) return s end, DecompressString = function(s) return s end,
        EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
    }
    T.isnil(Cat.Export(), "nothing of your own to share yet")
    local shiny = Cat.AddCustom("Shinies", "q>=rare")
    local keep = Cat.AddCustom("Keepers")
    Cat.Pin(6948, keep)
    local text = Cat.Export()
    T.eq(string.sub(text, 1, #Cat.SHARE_PREFIX), Cat.SHARE_PREFIX)
    -- Another character gets only Keepers, with another search.
    Cat.DeleteCustom(shiny)
    Cat.SetSearch(keep, "potion")
    Cat.Unpin(6948)
    local list, said = Cat.ReadShared(text)
    T.eq(#list, 2, said)
    T.eq(Cat.ImportShared(list), 2)
    local names = {}
    for _, g in ipairs(Cat.Custom()) do names[g.name] = g end
    T.eq(#Cat.Custom(), 2, "Keepers updated, Shinies added")
    T.eq(names.Shinies.search, "q>=rare")
    T.eq(names.Keepers.search, "potion", "a group shared without a search keeps the one it had")
    T.eq(Cat.PinOf(6948), keep, "the moved item back in Keepers")
    T.isnil(Cat.ReadShared("hello"), "not ours")
    T.isnil(Cat.ReadShared(""), "nothing pasted")
    _G.C_EncodingUtil = nil
end)

T.test("bags: an empty group of yours can wait only in the bag, never in the bank or a saved copy", function()
    local ns = catLogin()
    local key = ns.Categories.AddCustom("Keepers")
    local function has(window)
        for _, g in ipairs(ns.Layout.Groups(ns.module.db, window)) do
            if g.key == key then return true end
        end
        return false
    end
    T.eq(has(ns.window), false, "hidden while empty")
    ns.module.db.emptyGroups = true
    T.eq(has(ns.window), true, "Show empty groups keeps it in the bag")
    local other = { set = ns.window.set, held = {} }
    T.eq(has(other), false)
    ns.module.db.emptyGroups = nil
    ns.Categories.DeleteCustom(key)
end)

T.test("W.Prompt: what you accept runs after the box has closed, so a second box isn't closed with it", function()
    catLogin()
    local W = DaylightUI.Widgets
    local ran, data = 0, nil
    W.Prompt("First", "", function() ran = ran + 1 end)
    data = stub.popup.data
    local box = { GetText = function() return " Keepers " end }
    -- StaticPopup_OnClick hides the dialog after OnAccept if it still has the same
    -- `which`, and a second W.Prompt reuses that same dialog.
    StaticPopupDialogs.DAYLIGHTUI_PROMPT.OnAccept({ editBox = box }, data)
    T.eq(ran, 0, "not inside the game's click")
    stub.RunTimers()
    T.eq(ran, 1)
    -- Empty is refused unless the question lets it be cleared.
    W.Prompt("Second", "", function() ran = ran + 10 end)
    StaticPopupDialogs.DAYLIGHTUI_PROMPT.OnAccept({ editBox = { GetText = function() return "" end } }, stub.popup.data)
    stub.RunTimers()
    T.eq(ran, 1)
    local got
    W.Prompt("Third", "old", function(v) got = v end, { empty = true })
    StaticPopupDialogs.DAYLIGHTUI_PROMPT.OnAccept({ editBox = { GetText = function() return "" end } }, stub.popup.data)
    stub.RunTimers()
    T.eq(got, "")
end)

T.test("bags: recent items first, for a while", function()
    local ns = catLogin()
    local Cat = ns.Categories
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and slot == 5 end }
    local now, getTime = stub.now, _G.GetTime
    stub.now = 1000
    _G.GetTime = function() return stub.now end
    ns.Relayout()
    T.eq(groupOf(ns, ns.Bags.buttons[0][5]), "recent")
    _G.C_NewItems.IsNewItem = function() return false end
    stub.now = 1000 + 16 * 60
    ns.Relayout()
    T.eq(groupOf(ns, ns.Bags.buttons[0][5]), "armor", "after the timeout, its own group")
    _G.C_NewItems = nil
    stub.now, _G.GetTime = now, getTime
end)

T.test("bags: right-clicking the Recent heading clears it", function()
    local ns = catLogin()
    local cleared = 0
    _G.C_NewItems = { IsNewItem = function(bag, slot) return cleared == 0 and bag == 0 and slot == 5 end,
                      ClearAll = function() cleared = cleared + 1 end }
    ns.Relayout()
    T.eq(groupOf(ns, ns.Bags.buttons[0][5]), "recent")
    local head
    for _, h in ipairs(ns.window.headings) do if h.key == "recent" and h:IsShown() then head = h end end
    T.truthy(head, "the Recent heading")
    local picked, keys
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, k, _, _, onPick) keys, picked = k, onPick end
    head:GetScript("OnClick")(head, "RightButton")
    DaylightUI.Widgets.OpenMenu = openMenu
    T.falsy(ns.Categories.IsCollapsed("recent"), "a right-click doesn't fold it")
    T.eq(keys and keys[1], "clear")
    picked("clear")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(cleared, 1, "the game's new flags cleared too")
    T.eq(groupOf(ns, ns.Bags.buttons[0][5]), "armor", "back in its own group")
    _G.C_NewItems = nil
end)

-- A blank slot in Recent. The slot filled empty, then the item came, and another
-- bag's change laid it out as Recent while only refilling that other bag.
T.test("bags: an item a layout finds in a bag that didn't change gets its icon", function()
    local ns = catLogin()
    open(ns)
    local slot = ns.Bags.buttons[1][3]
    T.isnil(slot.calls.SetItemButtonTexture[1], "empty to start")
    _G.C_NewItems = { IsNewItem = function(bag, s) return bag == 1 and s == 3 end }
    world.items[1][3] = { iconFileID = 777, stackCount = 1, quality = 1, hyperlink = "|Hitem:77|h", itemID = 77 }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(groupOf(ns, slot), "recent")
    T.eq(slot.calls.SetItemButtonTexture[1], 777, "its icon, without a hover")
    T.eq(slot.icon:GetAlpha(), 1)
    _G.C_NewItems = nil
end)

T.test("bags: an item the game hasn't given an icon yet gets it once it loads", function()
    local ns = login()
    local loaded = {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end,
                 ContinueOnItemLoad = function(_, fn) loaded[bag .. ":" .. slot] = fn end }
    end }
    open(ns)
    local slot = ns.Bags.buttons[0][3]
    world.items[0][3] = { stackCount = 1, quality = 1, hyperlink = "|Hitem:2318|h", itemID = 2318 }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.truthy(loaded["0:3"], "asked to be told when it loads")
    world.items[0][3].iconFileID = 2318
    loaded["0:3"]()
    T.eq(slot.calls.SetItemButtonTexture[1], 2318, "its icon, without a hover")
    T.eq(slot.icon:GetAlpha(), 1)
    _G.Item = nil
end)

T.test("bags: opening a vendor sells the Junk group, one at a time, and says what it came to", function()
    local ns = catLogin()
    local Cat = ns.Categories
    local sold = {}
    C_Container.UseContainerItem = function(bag, slot) sold[#sold + 1] = bag .. ":" .. slot end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        local r = { getInfo(link) }
        if link == "|Hitem:2|h" or link == "|Hitem:9|h" then
            return "name", link, 0, 1, 1, "", "", 20, "", 1, 25, 0, 0, 0
        end
        return unpack(r)
    end
    Cat.Pin(9, "junk")                       -- apples you marked as junk
    world.items[0][7] = { iconFileID = 107, stackCount = 1, quality = 0, hyperlink = "|Hitem:10|h", itemID = 10, hasNoValue = true }
    stub.FireEvent("MERCHANT_SHOW")
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(table.concat(sold, ","), "0:2,1:2", "the gray item and your own junk; nothing without a price")
    T.truthy(stub.ChatContains("Sold 2 junk items for"), "one line in chat")
    sold = {}
    DaylightUI:Set("Bags", "sellJunk", false)
    stub.FireEvent("MERCHANT_SHOW")
    stub.RunTimers()
    T.eq(#sold, 0, "off: nothing sold")
end)

T.test("bags: junk selling never sells a gray item in an equipment set or a gray quest item", function()
    local ns = catLogin()
    local sold = {}
    C_Container.UseContainerItem = function(bag, slot) sold[#sold + 1] = bag .. ":" .. slot end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:2|h" or link == "|Hitem:11|h" then
            return "name", link, 0, 1, 1, "", "", 1, "", 1, 25, 0, 0, 0
        end
        return getInfo(link)
    end
    C_Container.GetContainerItemEquipmentSetInfo = function(bag, slot) return bag == 0 and slot == 2 end
    world.class[11] = 12                    -- a gray quest item
    world.items[0][7] = { iconFileID = 107, stackCount = 1, quality = 0, hyperlink = "|Hitem:11|h", itemID = 11 }
    ns.Relayout()
    T.eq(groupOf(ns, ns.Bags.buttons[0][2]), "sets", "a gray weapon in a set shows with the sets")
    T.eq(groupOf(ns, ns.Bags.buttons[0][7]), "quest", "a gray quest item shows with the quest items")
    stub.FireEvent("MERCHANT_SHOW")
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(#sold, 0, "neither is sold")
    C_Container.GetContainerItemEquipmentSetInfo = nil
end)

T.test("bags: a repair vendor mends your gear: own money, guild money when allowed, says when short", function()
    local ns = catLogin()
    local repaired
    local vendor = { can = true, cost = 500, ok = true, guildCan = true, guildMoney = -1, money = 10000, guildBank = 10000 }
    _G.CanMerchantRepair = function() return vendor.can end
    _G.GetRepairAllCost = function()
        if repaired == "guild" or repaired == "self" then return 0, false end
        return vendor.cost, vendor.ok
    end
    _G.RepairAllItems = function(guild)
        if guild and vendor.guildBank < vendor.cost then repaired = "guild failed"; return end
        repaired = guild and "guild" or "self"
    end
    _G.CanGuildBankRepair = function() return vendor.guildCan end
    _G.GetGuildBankWithdrawMoney = function() return vendor.guildMoney end
    _G.GetMoney = function() return vendor.money end
    local function visit() repaired = nil; stub.FireEvent("MERCHANT_SHOW"); stub.RunTimers() end

    visit()
    T.eq(repaired, "self", "repairs with your own money")
    T.truthy(stub.ChatContains("Repaired for"), "says what it cost")

    vendor.can = false; visit()
    T.eq(repaired, nil, "a vendor that can't repair: nothing")
    vendor.can = true

    DaylightUI:Set("Bags", "repairGuild", true)
    visit()
    T.eq(repaired, "guild", "guild money when on and allowed")
    vendor.guildMoney = 100; visit()
    T.eq(repaired, "self", "guild allowance too small: your own money")
    vendor.guildMoney = -1

    for k in pairs(stub.chat) do stub.chat[k] = nil end
    vendor.guildBank = 100; visit()
    T.eq(repaired, "self", "the guild bank itself short: your own money after all")
    T.falsy(stub.ChatContains("(guild)"), "and it doesn't say the guild paid")
    T.truthy(stub.ChatContains("Repaired for"))
    vendor.guildBank = 10000

    vendor.money = 10; vendor.guildCan = false; visit()
    T.eq(repaired, nil, "can't afford it")
    T.truthy(stub.ChatContains("Not enough money to repair"), "says so")
    vendor.money = 10000

    DaylightUI:Set("Bags", "autoRepair", false)
    visit()
    T.eq(repaired, nil, "off: nothing")
end)

-- ---------------------------------------------------------------------
-- The bank
-- ---------------------------------------------------------------------

local function bankWorld()
    local bank = { calls = {}, tabs = { [0] = { { ID = 6 }, { ID = 7 } }, [2] = { { ID = 12 } } },
                   view = { [0] = true, [2] = true }, gold = 5000 }
    _G.Enum.BankType = { Character = 0, Account = 2 }
    _G.Enum.BagIndex = { Characterbanktab = -8, CharacterBankTab_1 = 6 }
    world.sizes[6], world.sizes[7], world.sizes[12] = 8, 4, 10
    world.items[6] = { [1] = { iconFileID = 601, stackCount = 3, quality = 2, hyperlink = "|Hitem:61|h", itemID = 61 } }
    world.items[12] = { [2] = { iconFileID = 1201, stackCount = 1, quality = 4, hyperlink = "|Hitem:121|h", itemID = 121 } }
    _G.C_Bank = {
        CanViewBank = function(t) return bank.view[t] == true end,
        FetchPurchasedBankTabData = function(t) return bank.tabs[t] end,
        FetchNumPurchasedBankTabs = function(t) return #bank.tabs[t] end,
        FetchMaxNumBankTabs = function() return 6 end,
        CloseBankFrame = function() bank.calls.close = (bank.calls.close or 0) + 1 end,
        CanPurchaseBankTab = function(t) return t == 0 end,
        FetchNextPurchasableBankTabData = function() return { tabCost = bank.cost or 10000 } end,
        -- Restricted (HasRestrictions in BankDocumentation). Only the game's own
        -- code may buy, or a secure click (clickSecure's env).
        PurchaseBankTab = function() error("ADDON_ACTION_FORBIDDEN: C_Bank.PurchaseBankTab") end,
        DoesBankTypeSupportMoneyTransfer = function(t) return t == 2 end,
        FetchDepositedMoney = function() return bank.gold end,
        CanDepositMoney = function() return true end,
        CanWithdrawMoney = function() return true end,
        AutoDepositItemsIntoBank = function(t) bank.calls.deposit = t end,
        DoesBankTypeSupportAutoDeposit = function(t) return t == 0 end,
    }
    -- The game's purchase button (BankPanelPurchaseTabButtonMixin:OnClick in
    -- BankFrameTemplates.lua). Its own code shows the CONFIRM_BUY_BANK_TAB pop-up
    -- for the overrideBankType attribute.
    stub.TEMPLATES.BankPanelPurchaseButtonScriptTemplate = function(btn)
        btn:SetScript("OnClick", function(self)
            bank.calls.gamePopup = self:GetAttribute("overrideBankType")
        end)
    end
    C_Container.SortBank = function(t) bank.calls.sort = t end
    -- The game's bank frame (BankFrame.xml, BankFrameTemplates.lua). Its BankPanel
    -- starts hidden, and a right-click in your bags deposits into
    -- BankFrame:GetActiveBankType(), which is nil while that panel is hidden.
    local frame = CreateFrame("Frame", "BankFrame", UIParent)
    local panel = CreateFrame("Frame", nil, frame)
    panel:Hide()
    frame.BankPanel = panel
    -- Only addon code calls SetBankType in this world (the game's own tabs never
    -- run here), so the field it writes is tainted.
    function panel:SetBankType(t) self.bankType = t; stub.Mark(self, "bankType", "DaylightUI") end
    function panel:GetActiveBankType() return self.bankType end
    function frame:GetActiveBankType()
        return self.BankPanel:IsShown() and self.BankPanel:GetActiveBankType() or nil
    end
    -- Forever's own OnShow (BankFrameMixin in Camelot/BankFrame.lua): the first tab
    -- costs 0, and SetTab's PurchaseFirstSlot buys it, as the game's code does. A
    -- frame under a hidden parent gets no OnShow, so it never gets that.
    frame:SetScript("OnShow", function(self)
        panel:Show()
        panel.bankType = 0
        if #bank.tabs[0] == 0 and bank.cost == 0 then
            bank.tabs[0] = { { ID = 6 } }
            bank.cost = 10000
            bank.calls.gameBought = (bank.calls.gameBought or 0) + 1
        end
    end)
    frame:SetScript("OnHide", function() panel:Hide() end)
    frame:Hide()
    return bank
end

-- The game's way in and out of a banker (BankFrame_Open: ShowUIPanel).
local function gameOpensBank()
    BankFrame:Show()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
end

local function gameClosesBank()
    BankFrame:Hide()
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.RunTimers()
end

-- A right-click on a bag slot, the game's way (ContainerFrame.lua):
-- C_Container.UseContainerItem(bag, slot, nil, BankFrame:GetActiveBankType()).
-- A bank type written by addon code taints the call and the game blocks it. In
-- game this showed as "the game blocked UNKNOWN()" when drinking after a bank visit.
local function rightClickSlot()
    local panel = BankFrame.BankPanel
    local bankType = BankFrame:GetActiveBankType()
    if panel:IsShown() and not issecurevariable(panel, "bankType") then
        error("ADDON_ACTION_BLOCKED: UseContainerItem")
    end
    return bankType
end

local function bankLogin(newCharacter)
    local bank
    local ns
    stub.Load({ bags = true, before = function()
        setup()
        bank = bankWorld()
        if newCharacter then bank.tabs[0], bank.cost = {}, 0 end
    end })
    stub.RunTimers()
    DaylightUI:Set("Bags", "view", "grid")
    DaylightUI:Set("Bags", "bank.view", "grid")
    stub.RunTimers()
    ns = stub.bags
    return ns, bank
end

T.test("bank: portrait header, sub line stops at the tabs, tabs on the title row", function()
    local ns = bankLogin()
    local f = ns.bank
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    headerFits(f, f.bankTabs)
    tabsOnTitleRow(f, f.bankTabs)
    T.truthy(f.sub:GetText():find(" of ", 1, true), "free slots in the sub line")
end)


-- Same pieces as the bags: chips, free bar, plain-money footer, no Sell junk.
local function sameLook(f, what)
    T.truthy(f.portrait:IsShown(), what .. ": portrait shows")
    T.truthy(f.sub:GetText() ~= nil, what .. ": sub line")
    T.truthy(#f.chips > 1, what .. ": chip row")
    T.truthy(f.freeBar:IsShown(), what .. ": free bar")
    T.eq(f.sellJunk, nil, what .. ": no Sell junk")
end

T.test("bank: same header, chips and footer as the bags", function()
    local ns = bankLogin()
    local f = ns.bank
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    sameLook(f, "bank")
    T.truthy(f.sub:GetText():find("of 12 free", 1, true), "N of M free")
    headerFits(f, f.bankTabs)
    tabsOnTitleRow(f, f.bankTabs)
    for _, view in ipairs({ "grid", "categories" }) do
        DaylightUI:Set("Bags", "bank.view", view)
        stub.RunTimers()
        ns.Window.Relayout(f)
        ns.Window.PickChip(f, f.chips[2].id)
        ns.Window.Relayout(f)
        ns.Window.PickChip(f, nil)
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(f.buyTab:IsShown(), "a tab to buy")
    local _, _, _, _, by = f.buyTab:GetPoint(1)
    local _, _, _, _, my = f.money:GetPoint(1)
    T.truthy(by > my, "Buy tab sits on the bar's row, above the money")
    T.truthy(f.freeBar:GetWidth() > 0)
end)

T.test("bank: gold in the account bank is drawn in coins like the bags", function()
    local ns, bank = bankLogin()
    bank.gold = 123456
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local f = ns.bank
    local account
    for _, t in ipairs(f.bankTabs) do if t.bankType == 2 then account = t end end
    account:GetScript("OnClick")(account)
    stub.RunTimers()
    T.truthy(f.deposit:IsShown(), "the account bank's gold buttons show")
    T.eq(f.money:GetText(), DaylightUI.Widgets.Money(123456), "the account bank's gold in our coins")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bank: before its first tab, the window still builds", function()
    local ns = bankLogin(true)
    local f = ns.bank
    T.eq(ns.Bank.HasTab(), false)
    ns.Window.Relayout(f)
    f:Show()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(f.sub:GetText() or "", "", "no \"0 of 0 free\" before a tab")
    sameLook(f, "bank, no tab")
    local sub = (f.sub:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.truthy(sub == "" or sub:find("0 of 0 free", 1, true), "sub empty or 0 of 0: " .. sub)
end)

T.test("bank: opens with the bank, the character tabs' slots in our look; the game's bank out of sight", function()
    local ns, bank = bankLogin()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local f = ns.bank
    T.eq(BankFrame:GetParent() ~= UIParent, true, "the game's bank window hidden")
    T.falsy(f:IsShown())
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.truthy(f:IsShown(), "ours opens with the bank")
    T.noerror(rightClickSlot, "a right-click in your bags at the bank isn't blocked")
    T.truthy(IsAnyBagOpen(), "your bags open with it, as the game's bank frame does")
    T.eq(world.opener, nil, "with no name: the game's who-opened-them local stays untouched")
    local set = ns.Bank.set
    T.eq(set.holders[6]:GetID(), 6, "a holder per tab: the tab's container")
    T.eq(#set.buttons[6], 8); T.eq(#set.buttons[7], 4)
    T.falsy(set.buttons[12], "not the account bank's yet")
    T.eq(set.buttons[6][1].calls.SetItemButtonTexture[1], 601, "filled the game's way")
    T.eq(f.free:GetText(), "11 / 12")
    T.truthy(f.buyTab:IsShown(), "a tab to buy")
    T.falsy(f.deposit:IsShown(), "no gold in the character bank")
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.FinishFade(f)
    T.falsy(f:IsShown(), "and closes with it")
    T.falsy(IsAnyBagOpen(), "your bags close with it too")
    T.eq(world.closeAll, 0, "by hiding its windows")
    T.noerror(rightClickSlot, "nor after the bank (a drink, a potion)")
end)

T.test("bank: a new character's first visit gets the game's free first tab, and its slots", function()
    local ns, bank = bankLogin(true)
    local f = ns.bank
    gameOpensBank()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(bank.calls.gameBought, 1, "the game's own bank code bought the free tab")
    T.eq(#ns.Bank.set.buttons[6], 8, "and the bank has slots to drop items in")
    T.eq(f.free:GetText(), "7 / 8")
    T.falsy(BankFrame:GetParent() == UIParent, "the game's bank window stays out of sight")
    gameClosesBank()
    stub.FinishFade(f)
    -- From now on it's parked. The game's panel stays hidden, so right-clicks
    -- follow the bank you're looking at.
    gameOpensBank()
    T.falsy(BankFrame.BankPanel:IsVisible(), "the game's panel never shows again")
    T.eq(bank.calls.gameBought, 1, "and nothing else is bought")
    T.noerror(rightClickSlot)
end)

T.test("bank: a character who has a tab keeps the game's bank frame parked: it never runs or buys", function()
    local ns, bank = bankLogin()
    gameOpensBank()
    T.falsy(BankFrame.BankPanel:IsVisible())
    T.falsy(bank.calls.gameBought)
    T.truthy(ns.bank:IsShown())
end)

T.test("bank: a character whose tab shows only once at the banker isn't veiled again next login", function()
    local ns, bank = bankLogin()
    DaylightUI.DB.Character().inventory = { bank = { { size = 8, items = {} } } }
    bank.tabs[0] = {}
    ns.Bank.Park()
    T.truthy(ns.Bank.HasTab(), "the saved copy says this character has one")
    T.falsy(BankFrame:IsVisible())
    gameOpensBank()
    T.falsy(BankFrame.BankPanel:IsVisible())
end)

T.test("bank: the Account tab, with its gold in and out; switching never touches the game's bank type", function()
    local ns, bank = bankLogin()
    local f = ns.bank
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local account
    for _, t in ipairs(f.bankTabs) do if t.bankType == 2 then account = t end end
    account:GetScript("OnClick")(account)
    T.noerror(rightClickSlot, "picking a tab never taints the game's bank type")
    local set = ns.Bank.set
    T.eq(#set.buttons[12], 10, "the account tab's slots")
    T.falsy(set.buttons[6][1]:IsShown(), "the character tabs' out of sight")
    T.truthy(f.deposit:IsShown()); T.truthy(f.withdraw:IsShown())
    T.eq(f.money:GetText(), "money:5000", "the account bank's gold")
    T.falsy(f.buyTab:IsShown())
    bank.view[2] = false
    account:GetScript("OnClick")(account)
    T.eq(ns.Bank.bankType, 2)
    -- Opening again shows the tab you looked at last.
    bank.view[2] = true
    account:GetScript("OnClick")(account)
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.eq(ns.Bank.bankType, 2, "the account tab again")
    T.noerror(rightClickSlot, "and a right-click still works")
end)

T.test("bank: its own settings, search, sort and deposit; closing ours closes the bank", function()
    local ns, bank = bankLogin()
    local f = ns.bank
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    DaylightUI:Set("Bags", "bank.columns", 4)
    stub.RunTimers()
    local _, _, _, x5, y5 = ns.Bank.set.buttons[6][5]:GetPoint(1)
    T.eq(x5, 0, "four across in the bank")
    T.eq(DaylightUI:Get("Bags", "columns"), 10, "the bag keeps its own")
    f.search:SetText("rare")
    f.search:GetScript("OnTextChanged")(f.search, true)
    T.eq(ns.Bank.set.buttons[6][1].calls.SetMatchesSearch[1], false, "the bank's search dims the bank")
    T.isnil(ns.window.match, "not the bag")
    f.sort:GetScript("OnClick")(f.sort)
    T.eq(bank.calls.sort, 0, "sorts the bank being looked at")
    f.depositButton:GetScript("OnClick")(f.depositButton)
    T.eq(bank.calls.deposit, 0, "reagents into it")
    f.close:GetScript("OnClick")(f.close)
    T.eq(bank.calls.close, 1, "our X closes the game's bank")
end)

T.test("bank: Same look as your bags: the shared settings follow the bags, columns stay its own", function()
    local ns = bankLogin()
    local f = ns.bank
    DaylightUI:Set("Bags", "iconSize", 30)
    DaylightUI:Set("Bags", "bank.iconSize", 44)
    stub.RunTimers()
    T.eq(f.Setting("iconSize"), 30, "the bags' slot size")
    T.eq(f.Setting("columns"), 14, "its own columns")
    T.eq(f.Cfg().iconSize, 30, "the layout reads the same")
    f.Set("view", "categories")
    T.eq(DaylightUI:Get("Bags", "view"), "categories", "its view button switches the bags' too")
    DaylightUI:Set("Bags", "bank.ownLook", true)
    T.eq(f.Setting("iconSize"), 44, "its own look: its own size")
    T.eq(f.Cfg().iconSize, 44)
end)

T.test("bank: the upgrade keeps a bank that looked unlike the bags on its own look, once", function()
    local ns = bankLogin()
    local p = { modules = { Bags = { iconSize = 30, bank = { iconSize = 30, columns = 18 } } } }
    ns.UpgradeBank(p)
    T.isnil(p.modules.Bags.bank.ownLook, "it looked the same: follows the bags")
    T.eq(p.modules.Bags.bankLook1, true)
    p = { modules = { Bags = { bank = { spacing = 12 } } } }
    ns.UpgradeBank(p)
    T.eq(p.modules.Bags.bank.ownLook, true, "a different spacing: keeps its own")
    p = { modules = { Bags = { bankLook1 = true, bank = { spacing = 12 } } } }
    ns.UpgradeBank(p)
    T.isnil(p.modules.Bags.bank.ownLook, "only once")
end)

T.test("bank: the categories view, empty slots and all", function()
    local ns = bankLogin()
    DaylightUI:Set("Bags", "bank.view", "categories")
    stub.RunTimers()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local groups = ns.Layout.Groups(ns.module.db.bank, ns.bank)
    local keys = {}
    for _, g in ipairs(groups) do keys[#keys + 1] = g.key end
    T.truthy(table.concat(keys, ","):find("empty", 1, true), "the bank's empty slots in Empty")
    local empty
    for _, g in ipairs(groups) do if g.key == "empty" then empty = g end end
    T.eq(#empty.entries, 11, "every empty bank slot")
    DaylightUI:Set("Bags", "bank.emptySlots", "grouped")
    stub.RunTimers()
    groups = ns.Layout.Groups(ns.module.db.bank, ns.bank)
    for _, g in ipairs(groups) do if g.key == "empty" then empty = g end end
    T.eq(#empty.entries, 1, "or one tile"); T.eq(empty.entries[1].free, 11)
end)

T.test("bags: junk you've just looted is sold too", function()
    local ns = catLogin()
    local sold = {}
    C_Container.UseContainerItem = function(bag, slot) sold[#sold + 1] = bag .. ":" .. slot end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:2|h" then return "name", link, 0, 1, 1, "", "", 20, "", 1, 25, 0, 0, 0 end
        return getInfo(link)
    end
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and slot == 2 end }
    stub.FireEvent("MERCHANT_SHOW")
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(table.concat(sold, ","), "0:2", "sold though it's still Recent")
    _G.C_NewItems = nil
end)

T.test("bank: deposit reagents only where the bank takes it", function()
    local ns = bankLogin()
    local f = ns.bank
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.truthy(f.depositButton:IsShown(), "the character bank takes it")
    for _, t in ipairs(f.bankTabs) do if t.bankType == 2 then t:GetScript("OnClick")(t) end end
    T.falsy(f.depositButton:IsShown(), "the account bank doesn't here")
end)

-- Buying a tab. C_Bank.PurchaseBankTab is restricted (HasRestrictions). The
-- game's CONFIRM_BUY_BANK_TAB pop-up (Camelot/BankFrame.lua) calls it with its
-- data.bankType. Shown from addon code, that data is tainted and the game blocks
-- the call ("the game blocked PurchaseBankTab()"). A secure macro button's /run
-- counts as the game running it from a click.
T.test("bank: Buy tab is the game's own purchase button (its pop-up buys, never our code)", function()
    local ns, bank = bankLogin()
    local f = ns.bank
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.truthy(f.buyTab:IsShown())
    T.eq(f.buyTab.__template, "BankPanelPurchaseButtonScriptTemplate", "made from the game's template")
    T.eq(f.buyTab:GetAttribute("overrideBankType"), 0, "told which bank")
    T.truthy(string.find(f.buyTab.text:GetText(), "Buy tab: ", 1, true), "with the cost")
    T.noerror(function() f.buyTab:GetScript("OnClick")(f.buyTab) end)
    T.eq(bank.calls.gamePopup, 0, "the game's pop-up for the character bank")
end)

-- On Forever the bank's base slots are its first tab, there from the start. The
-- tab list and slot counts reach the client a moment after BANKFRAME_OPENED, so a
-- first visit showed no slots and a "0 copper" tab. EllesmereUI reads again the
-- frame after.
T.test("bank: tabs that arrive after the open still show (read again), no 0 copper tab", function()
    local ns, bank = bankLogin()
    local f = ns.bank
    local tabs = bank.tabs[0]
    bank.tabs[0] = {}
    bank.cost = 0
    stub.FireEvent("BANKFRAME_OPENED")
    T.eq(f.buyTab.text:GetText(), "Buy tab", "no cost shown before the game knows it")
    -- The server's answer lands with no event of its own.
    bank.tabs[0] = tabs
    bank.cost = 1000
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(ns.Bank.set.buttons[6] and #ns.Bank.set.buttons[6] == 8, "the bank's slots show")
    T.truthy(ns.Bank.set.buttons[6][1]:IsShown())
    T.truthy(string.find(f.buyTab.text:GetText(), "Buy tab: ", 1, true), "and the real cost")
end)

-- The bank's strip is built from the bags' strip pieces (Slots.NewButton).
T.test("bank: the bank bag strip shows its tabs and hovering one lights its slots", function()
    local ns, bank = bankLogin()
    DaylightUI:Set("Bags", "bank.showSlots", true)
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local strip = ns.Bank.strip
    T.truthy(strip and #strip.slots > 0, "a button per bank tab")
    ns.Bank.RefreshStrip()
    T.truthy(strip:IsShown(), "shown with the setting")
    local b = strip.slots[1]
    T.eq(b.icon:GetTexture(), ns.Slots.EMPTY_ICON, "no bag in it: the empty slot")
    b:GetScript("OnEnter")(b)
    local slot = ns.Bank.set.buttons[6][1]
    local r = DaylightUI.Style.Accent()
    T.eq(ns.Items.Parts(slot).shell.opts.borderColor[1], r, "the tab's slots outlined in the accent")
    b:GetScript("OnLeave")(b)
    T.eq(ns.Items.Parts(slot).shell.opts.borderColor, ns.Items.Parts(slot).color, "back to its own outline")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the bank's position stays out of shared profiles", function()
    login()
    DaylightUI:Set("Bags", "bank.position", { 10, 20 })
    local p = DaylightUI.Profiles.Snapshot()
    local bank = p.modules.Bags and p.modules.Bags.bank
    T.isnil(bank and bank.position, "not exported")
end)

-- ---------------------------------------------------------------------
-- Currencies in the footer
-- ---------------------------------------------------------------------

T.test("bags: tracked currencies show in the footer, right to left from the money", function()
    local ns = login()
    local f = open(ns)
    local list = { { name = "Badge", quantity = 42, iconFileID = 999, currencyTypesID = 7 },
                   { name = "Mark", quantity = 3, iconFileID = 998, currencyTypesID = 8 } }
    _G.C_CurrencyInfo = { GetBackpackCurrencyInfo = function(i) return list[i] end }
    ns.Window.UpdateFooter(f)
    T.eq(f.currencySlots[1].count:GetText(), "42")
    T.eq(f.currencySlots[1].icon.__texture, 999)
    T.eq(f.currencySlots[2].count:GetText(), "3")
    local shown = 0
    for _, s in ipairs(f.currencySlots) do if s:IsShown() then shown = shown + 1 end end
    T.eq(shown, 2, "only the two tracked")
    DaylightUI:Set("Bags", "showCurrency", false)
    ns.Window.UpdateFooter(f)
    T.falsy(f.currencySlots[1]:IsShown(), "off: none shown")
    _G.C_CurrencyInfo = nil
end)

T.test("bags: the bag and bank windows get unlock-mode handles", function()
    local ns = bankLogin()
    local bag = DaylightUI.Movers.Get("bags.bag")
    T.truthy(bag and bag.proxy, "the bag: a proxy (it's hidden most of the time)")
    T.truthy(DaylightUI.Movers.Get("bags.bank"), "the bank too")
end)

T.test("bags: moving the handle sets the window's own top-left; reset clears it", function()
    local ns = login()
    local DUI = DaylightUI
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("bags.bag")
    h:SetSize(400, 300)
    DUI.DB.Positions()["bags.bag"] = { 0, 0 }
    DUI.Movers.Get("bags.bag").onMoved("bags.bag")
    stub.RunTimers()
    local pos = ns.module.db.position
    T.eq(pos[1], UIParent:GetWidth() / 2 - 200, "left edge")
    T.eq(pos[2], UIParent:GetHeight() / 2 + 150, "top edge")
    T.isnil(DUI.DB.Positions()["bags.bag"], "kept only in the bag's own setting")
    DUI.Movers.Reset("bags.bag")
    stub.RunTimers()
    T.isnil(ns.module.db.position, "back to the default spot")
    DUI.Movers.Lock()
end)

-- Swapping a bag for one that isn't empty: a bag (item 50) waiting in the
-- backpack, the cursor on top of cursorWorld (a held item's slot is locked and
-- GetCursorInfo says what it is), and the game's PutItemInBag, which only swaps
-- an empty bag (the old one, item 99, lands where the new one was).
local function swapWorld()
    cursorWorld()
    world.maxStack = {}
    local function unlock()
        local h = world.held
        if h and world.items[h.bag][h.slot] then world.items[h.bag][h.slot].isLocked = nil end
    end
    local pick = C_Container.PickupContainerItem
    C_Container.PickupContainerItem = function(bag, slot)
        local held = world.held
        unlock()
        pick(bag, slot)
        if not held and world.held then world.items[bag][slot].isLocked = true end
    end
    _G.ClearCursor = function() unlock(); world.held = nil end
    _G.GetCursorInfo = function()
        local h = world.held
        if h then return "item", world.items[h.bag][h.slot].itemID end
    end
    C_Item.GetItemInfoInstant = function(id)
        if id == 50 then return id, "Container", "Bag", "INVTYPE_BAG", 1, 1, 0 end
        return id, "Miscellaneous", "Junk", "", 1, 15, 0
    end
    world.puts = 0
    _G.PutItemInBag = function(inv)
        world.puts = world.puts + 1
        local bag, h = inv - 30, world.held
        if next(world.items[bag]) then return end      -- the game refuses: "that bag isn't empty"
        world.items[h.bag][h.slot] = { itemID = 99, hyperlink = "|Hitem:99|h", stackCount = 1, iconFileID = 1 }
        world.sizes[bag] = 16
        world.held = nil
    end
    -- The game's rule for a special bag (a profession bag, a quiver): an item
    -- only goes in when its family shares a bit with the bag's. A refused item
    -- stays on the cursor.
    world.itemFamily = {}
    C_Item.GetItemFamily = function(id) return world.itemFamily[id] or 0 end
    local put = C_Container.PickupContainerItem
    C_Container.PickupContainerItem = function(bag, slot)
        local h, fam = world.held, (world.family or {})[bag] or 0
        if h and fam ~= 0 and not world.items[bag][slot] then
            local id = world.items[h.bag][h.slot].itemID
            if bit.band(world.itemFamily[id] or 0, fam) == 0 then return end
        end
        put(bag, slot)
    end
    world.items[0][3] = { itemID = 50, hyperlink = "|Hitem:50|h", stackCount = 1, iconFileID = 50 }
    for s = 1, 3 do world.items[1][s] = { itemID = 60 + s, hyperlink = "|Hitem:" .. (60 + s) .. "|h", stackCount = 1, iconFileID = 1 } end
    world.printed = {}
    DaylightUI.Print = function(msg) world.printed[#world.printed + 1] = msg end
end

-- Fills the backpack's free slots but `leave` with junk (item 70).
local function fillBackpack(leave)
    local n = 0
    for s = 1, 16 do
        if not world.items[0][s] then
            n = n + 1
            if n > leave then world.items[0][s] = { itemID = 70, hyperlink = "|Hitem:70|h", stackCount = 1, iconFileID = 1 } end
        end
    end
end

T.test("bags: a full bag swap merges half stacks first when that makes the room", function()
    local ns = login()
    swapWorld()
    fillBackpack(2)                                       -- 2 free, 3 to move
    world.maxStack[80] = 20
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:80|h" then return "name", link, 1, 1, 1, "", "", 20, "", 1, 1, 0, 0, 0 end
        return getInfo(link)
    end
    world.items[0][15] = { itemID = 80, hyperlink = "|Hitem:80|h", stackCount = 5, iconFileID = 1 }
    world.items[0][16] = { itemID = 80, hyperlink = "|Hitem:80|h", stackCount = 5, iconFileID = 1 }
    C_Container.PickupContainerItem(0, 3)
    T.truthy(ns.Swap.Try(1, 31))
    stub.RunTimers()
    T.eq(world.sizes[1], 16, "the new bag is in")
    T.eq(#world.printed, 0, tostring(world.printed[1]))
end)

T.test("bags: a full bag swap puts what fits in a profession bag, plain things in the plain bags", function()
    local ns = login()
    swapWorld()
    fillBackpack(2)                                       -- 2 free, 3 to move
    world.family = { [1] = 0, [5] = 32 }                  -- bag 5: herbs only
    world.itemFamily[61] = 32                             -- 61 is a herb
    C_Container.PickupContainerItem(0, 3)
    T.truthy(ns.Swap.Try(1, 31))
    stub.RunTimers()
    T.eq(world.sizes[1], 16, "the new bag is in")
    local herb
    for _, it in pairs(world.items[5]) do if it.itemID == 61 then herb = true end end
    T.truthy(herb, "the herb went in the herb bag")
    T.eq(#world.printed, 0, tostring(world.printed[1]))
    world.family = nil
end)

T.test("bags: a full bag swap at a banker puts the rest in the bank and says so", function()
    local ns = login()
    swapWorld()
    fillBackpack(1)                                       -- 1 free, 3 to move
    _G.Enum = _G.Enum or {}
    Enum.BankType = Enum.BankType or { Character = 0, Account = 2 }
    world.sizes[6], world.items[6] = 4, {}
    local list = ns.Bank.List
    ns.Bank.List = function() return { { id = 6, section = "bank" } } end
    ns.Bank.open, ns.Bank.bankType = true, Enum.BankType.Character
    C_Container.PickupContainerItem(0, 3)
    T.truthy(ns.Swap.Try(1, 31))
    stub.RunTimers()
    T.eq(world.sizes[1], 16, "the new bag is in")
    local banked = 0
    for _ in pairs(world.items[6]) do banked = banked + 1 end
    T.eq(banked, 2, "two went to the bank")
    T.truthy(world.printed[1] and world.printed[1]:find("2 items went to your bank"), tostring(world.printed[1]))
    ns.Bank.List, ns.Bank.open, ns.Bank.bankType = list, false, nil
end)

T.test("bags: dropping a bag on a full one empties it into the other bags, then swaps", function()
    local ns = login()
    swapWorld()
    C_Container.PickupContainerItem(0, 3)               -- the new bag in hand
    T.truthy(ns.Swap.Try(1, 31), "handled")
    stub.RunTimers()
    T.isnil(next(world.items[1]) and world.items[1][1] or nil, "bag 1's things moved out")
    T.eq(world.sizes[1], 16, "the new bag is in")
    T.eq(world.items[0][3].itemID, 99, "the old bag is where the new one was")
    local n = 0
    for _, it in pairs(world.items[0]) do if it.itemID and it.itemID > 60 and it.itemID < 64 then n = n + 1 end end
    T.eq(n, 3, "all three things are in the backpack")
    T.falsy(CursorHasItem(), "nothing left on the cursor")
    T.eq(#world.printed, 0)
end)

T.test("bags: no room to empty the bag: nothing moves and a chat line says how many slots to free", function()
    local ns = login()
    swapWorld()
    for s = 7, 15 do world.items[0][s] = { itemID = 70, hyperlink = "|Hitem:70|h", stackCount = 1, iconFileID = 1 } end
    C_Container.PickupContainerItem(0, 3)
    T.truthy(ns.Swap.Try(1, 31))
    stub.RunTimers()
    T.eq(world.items[1][1].itemID, 61, "nothing moved")
    T.eq(world.puts, 0)
    T.truthy(world.printed[1] and world.printed[1]:find("free 2 more slots"), tostring(world.printed[1]))
end)

T.test("bags: an empty bag slot, a non-bag item, or combat is left to the game", function()
    local ns = login()
    swapWorld()
    C_Container.PickupContainerItem(0, 3)
    T.falsy(ns.Swap.Try(2, 32), "bag 2 is empty: the game swaps it")
    ClearCursor()
    C_Container.PickupContainerItem(0, 1)
    world.items[0][1].itemID = 1
    T.falsy(ns.Swap.Try(1, 31), "not a bag: it goes in the bag")
    ClearCursor()
    stub.EnterCombat()
    C_Container.PickupContainerItem(0, 3)
    T.falsy(ns.Swap.Try(1, 31), "in combat")
    stub.LeaveCombat()
end)

-- Opening only fades, and nothing in the grid or its slots moves. A lift moved
-- every slot each frame (~10 fps), and pinning the grid for one re-placed every
-- piece of every slot on each opening (~280 ms frozen in game).
T.test("bags: opening only fades; neither the grid nor a slot is re-anchored", function()
    local ns = login()
    local f = ns.window
    open(ns)
    CloseAllBags(); f:Hide(); stub.RunTimers()
    T.truthy(#ns.Bags.Slots() > 30, "a real bag's worth of slots")
    local moved = 0
    local function watch(obj)
        local sp, ca = obj.SetPoint, obj.ClearAllPoints
        obj.SetPoint = function(...) moved = moved + 1; return sp(...) end
        obj.ClearAllPoints = function(...) moved = moved + 1; return ca(...) end
    end
    watch(f.items)
    for _, s in ipairs(ns.Bags.Slots()) do watch(s.button) end
    open(ns)
    T.truthy(f:IsShown())
    T.truthy(f.__duiMotion and f.__duiMotion.appearFade and f.__duiMotion.appearFade:IsPlaying(), "fades in")
    T.falsy(f.__duiMotion.appearLift, "no lift")
    T.truthy(f.items:IsShown(), "the grid shows at once")
    T.eq(moved, 0, "nothing re-anchored")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Ready while closed (Prep.lua): quiet work on idle frames, so opening only
-- fills what changed.
-- ---------------------------------------------------------------------

-- Counts fills from here on.
local function countFills(ns)
    local c = { n = 0 }
    local fill = ns.Items.Fill
    ns.Items.Fill = function(btn, ...) c.n = c.n + 1; return fill(btn, ...) end
    return c
end

-- Runs the quiet worker until it's done (or for `frames` frames), past the wait
-- after the last change (Prep.SETTLE).
local function quietly(ns, frames)
    local w = ns.Prep.worker
    stub.Advance(ns.Prep.SETTLE)
    for _ = 1, frames or 500 do
        if not w:IsShown() then return end
        stub.RunOnUpdate(w, 0.016)
    end
end

local function bagChanged(bag)
    stub.FireEvent("BAG_UPDATE", bag)
    stub.FireEvent("BAG_UPDATE_DELAYED")
end

T.test("bags: made ready quietly after login; the first open fills nothing", function()
    local ns = login()
    local c = countFills(ns)
    T.truthy(ns.Prep.worker:IsShown(), "the worker runs once login's done")
    quietly(ns)
    T.eq(c.n, 32, "every slot filled while closed")
    T.falsy(ns.Prep.worker:IsShown(), "and then it stops")
    c.n = 0
    local f = open(ns)
    T.eq(c.n, 0, "opening fills nothing: it's all ready")
    T.eq(freeText(f), "23 / 3", "the footer's still right")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: categories view open, a change refills that bag and moved stack totals only", function()
    local ns = catLogin()
    local c = countFills(ns)
    world.items[1][3] = { iconFileID = 113, stackCount = 1, quality = 1, hyperlink = "|Hitem:13|h", itemID = 13 }
    bagChanged(1)
    T.eq(c.n, 12, "bag 1's 12 slots, not every slot")
    T.eq(ns.Bags.buttons[1][3].calls.SetItemButtonTexture[1], 113)
    c.n = 0
    -- More Bread. The combined total sits on the backpack's Bread, so the backpack
    -- refills too.
    world.items[1][3] = { iconFileID = 108, stackCount = 2, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    bagChanged(1)
    T.eq(c.n, 12 + 16, "bag 1 and the backpack")
    T.eq(ns.Bags.buttons[0][8].calls.count, 14, "5 + 7 + 2 Bread on one tile")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Selling fast: while the bag is open, a slot that empties keeps its place so no
-- item slides under the cursor. The next open groups it again.
local function spot(btn)
    local _, _, _, x, y = btn:GetPoint(1)
    return x, y
end

T.test("bags: categories view open, an item sold leaves its slot in place until reopened", function()
    local ns = catLogin()
    local B = ns.Bags
    local weapon, junk = B.buttons[0][1], B.buttons[0][2]
    local wx, wy = spot(weapon)
    local jx, jy = spot(junk)
    world.items[0][1] = nil
    bagChanged(0)
    T.truthy(weapon:IsShown(), "the emptied slot stays")
    T.deq({ spot(weapon) }, { wx, wy }, "where it was")
    T.deq({ spot(junk) }, { jx, jy }, "nothing else moved")
    T.isnil(weapon.calls.SetItemButtonTexture[1], "shown empty")
    ns.window:Hide()
    open(ns)
    T.eq(groupOf(ns, weapon), "empty", "reopened: grouped again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: categories view open, a combined stack sold: the next stack takes its spot", function()
    local ns = catLogin()
    local B = ns.Bags
    local first, other = B.buttons[0][8], B.buttons[1][1]
    local x, y = spot(first)
    world.items[0][8] = nil
    bagChanged(0)
    T.truthy(other:IsShown(), "the other bread shows")
    T.deq({ spot(other) }, { x, y }, "in the same spot")
    T.falsy(first:IsShown())
    T.eq(other.calls.count, 7, "with what's left")
    -- That one sold too, and the spot stays, empty.
    world.items[1][1] = nil
    bagChanged(1)
    T.truthy(other:IsShown())
    T.deq({ spot(other) }, { x, y })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: grouped empty slots, open: an item sold leaves its slot in place", function()
    local ns = login()
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    stub.RunTimers()
    local f = open(ns)
    local btn = ns.Bags.buttons[0][1]
    local x, y = spot(btn)
    world.items[0][1] = nil
    bagChanged(0)
    T.truthy(btn:IsShown())
    T.deq({ spot(btn) }, { x, y })
    f:Hide()
    open(ns)
    T.falsy(select(1, spot(btn)) == x and select(2, spot(btn)) == y, "reopened: now the free tile, after the items")
end)

T.test("bags: closed and opened again with no change fills nothing", function()
    local ns = login()
    local f = open(ns)
    f:Hide()
    quietly(ns)
    local c = countFills(ns)
    open(ns)
    T.eq(c.n, 0)
end)

T.test("bags: a change while closed refills only that bag, on open or quietly", function()
    local ns = login()
    quietly(ns)
    local f = open(ns)
    f:Hide()
    quietly(ns)
    local c = countFills(ns)
    world.items[1][3] = { iconFileID = 113, stackCount = 1, quality = 1, hyperlink = "|Hitem:13|h" }
    bagChanged(1)
    T.eq(c.n, 0, "closed: only noted")
    open(ns)
    T.eq(c.n, 12, "opening fills bag 1's 12 slots, nothing else")
    T.eq(ns.Bags.buttons[1][3].calls.SetItemButtonTexture[1], 113)
    f:Hide()
    quietly(ns)
    c.n = 0
    world.items[0][9] = { iconFileID = 119, stackCount = 1, quality = 1, hyperlink = "|Hitem:19|h" }
    bagChanged(0)
    quietly(ns)
    T.eq(c.n, 16, "or quietly, the backpack's 16")
    c.n = 0
    open(ns)
    T.eq(c.n, 0, "and then opening fills nothing")
    T.eq(ns.Bags.buttons[0][9].calls.SetItemButtonTexture[1], 119)
end)

T.test("bags: a search, closed, reopened mid-way through quiet work: nothing dimmed", function()
    local ns = login()
    quietly(ns)
    local f = open(ns)
    -- A search, then closed: the next open shows nothing dimmed.
    f.search:SetText("potion")
    T.eq(ns.Bags.buttons[0][1].calls.SetMatchesSearch[1], false, "dimmed while searching")
    f:Hide()
    -- Something to fill quietly (clearing the search on close fills nothing).
    ns.FillAll()
    ns.Prep.BUDGET = 0
    quietly(ns, 3)
    T.truthy(ns.Prep.worker:IsShown(), "still going")
    open(ns)
    ns.Prep.BUDGET = 2
    for _, s in ipairs(ns.Bags.Slots()) do
        T.eq(s.button.calls.SetMatchesSearch[1], true, "nothing dimmed: bag " .. s.bag .. " slot " .. s.button:GetID())
    end
end)

T.test("bags: a bag changed again while it's being filled is filled from the start", function()
    local ns = login()
    quietly(ns)
    ns.Prep.BUDGET = 0
    bagChanged(0)
    quietly(ns, 4)
    world.items[0][1] = { iconFileID = 201, stackCount = 1, quality = 1, hyperlink = "|Hitem:21|h" }
    bagChanged(0)
    quietly(ns)
    ns.Prep.BUDGET = 2
    T.eq(ns.Bags.buttons[0][1].calls.SetItemButtonTexture[1], 201, "slot 1 filled again")
end)

T.test("bags: no quiet work in combat; it goes on after", function()
    local ns = login()
    local c = countFills(ns)
    stub.EnterCombat()
    stub.RunOnUpdate(ns.Prep.worker, 0.016)
    T.eq(c.n, 0, "nothing in combat")
    T.falsy(ns.Prep.worker:IsShown())
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(ns.Prep.worker:IsShown(), "back after combat")
    quietly(ns)
    T.eq(c.n, 32)
end)

T.test("bags: categories view changed while closed is grouped right on open, laid out quietly", function()
    local ns = login({ view = "categories" })
    categoryWorld()
    quietly(ns)
    local B = ns.Bags
    -- Bread into the backpack's empty slot 3 folds into the bread stack.
    world.items[0][3] = { iconFileID = 108, stackCount = 3, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    bagChanged(0)
    T.truthy(ns.window.stale, "closed: the groups wait")
    quietly(ns)
    T.falsy(ns.window.stale, "laid out quietly")
    local relayouts = 0
    local relayout = ns.Window.Relayout
    ns.Window.Relayout = function(...) relayouts = relayouts + 1; return relayout(...) end
    local c = countFills(ns)
    open(ns)
    ns.Window.Relayout = relayout
    T.eq(relayouts, 0, "opening doesn't lay it out again")
    T.eq(c.n, 0)
    T.eq(groupOf(ns, B.buttons[0][3]), "consumable")
    T.eq(B.buttons[0][3].calls.count or B.buttons[0][8].calls.count, 15, "the total of all the bread")
end)

T.test("bags: closed, a burst of loot is laid out once, a moment after the last", function()
    local ns = login({ view = "categories" })
    categoryWorld()
    quietly(ns)
    local relayouts = 0
    local relayout = ns.Window.Relayout
    ns.Window.Relayout = function(...) relayouts = relayouts + 1; return relayout(...) end
    world.items[0][3] = { iconFileID = 108, stackCount = 3, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    bagChanged(0)
    for _ = 1, 5 do stub.RunOnUpdate(ns.Prep.worker, 0.016) end
    T.eq(relayouts, 0, "waits while more may come")
    stub.Advance(ns.Prep.SETTLE / 2)
    bagChanged(0)
    stub.Advance(ns.Prep.SETTLE / 2)
    stub.RunOnUpdate(ns.Prep.worker, 0.016)
    T.eq(relayouts, 0, "the wait starts again at each change")
    quietly(ns)
    ns.Window.Relayout = relayout
    T.eq(relayouts, 1, "then one layout")
    T.falsy(ns.window.stale)
end)

-- ---------------------------------------------------------------------
-- The gold counts
-- ---------------------------------------------------------------------

local function runDrivers(dt)
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, dt) end
    end
end

-- The footer's money is one part a coin ("money:9500 money:92"): add them up.
local function amount(f)
    local sum, any = 0, false
    for n in f.money:GetText():gmatch("money:(%d+)") do sum = sum + tonumber(n); any = true end
    return any and sum or nil
end

T.test("bags: the footer gold counts to a new amount, tinted on a gain", function()
    local ns = login()
    local f = open(ns)
    ns.Window.UpdateFooter(f)
    T.eq(amount(f), 9592, "the first reading just sets")
    local money = 12000
    _G.GetMoney = function() return money end
    stub.FireEvent("PLAYER_MONEY")
    T.eq(amount(f), 9592, "starts from what was shown")
    T.eq(f.money.__textColor and f.money.__textColor[1], ns.MoneyRoll.GAIN[1], "a gain is tinted")
    runDrivers(0.2)
    local mid = amount(f)
    T.truthy(mid > 9592 and mid < 12000, "midway")
    ns.Window.UpdateFooter(f)   -- another reason to refresh the footer
    T.eq(amount(f), mid, "the count is not snapped")
    runDrivers(1)
    T.eq(amount(f), 12000, "ends on the new amount")
    T.eq(f.rollColor, nil, "tint put back")
    -- a loss counts down, without the tint
    money = 5000
    stub.FireEvent("PLAYER_MONEY")
    T.eq(f.rollColor, nil, "no tint on a loss")
    runDrivers(1)
    T.eq(amount(f), 5000)
    -- again mid-count, from what is shown to the latest
    money = 8000
    stub.FireEvent("PLAYER_MONEY")
    runDrivers(0.1)
    local shown = amount(f)
    money = 100
    stub.FireEvent("PLAYER_MONEY")
    T.eq(amount(f), shown, "a new count starts from what is shown")
    runDrivers(1)
    T.eq(amount(f), 100)
    _G.GetMoney = function() return 9592 end
end)

T.test("bags: gold just sets while hidden, with the setting off, or with motion off", function()
    local ns = login()
    local f = open(ns)
    ns.Window.UpdateFooter(f)
    f:Hide()
    _G.GetMoney = function() return 500 end
    stub.FireEvent("PLAYER_MONEY")
    f:Show()
    T.eq(amount(f), 500, "hidden: opens on the new amount")
    runDrivers(1)
    T.eq(amount(f), 500, "no count when it opens")
    DaylightUI:Set("Bags", "moneyRoll", false)
    _G.GetMoney = function() return 900 end
    stub.FireEvent("PLAYER_MONEY")
    T.eq(amount(f), 900, "setting off: set at once")
    DaylightUI:Set("Bags", "moneyRoll", true)
    DaylightUI.DB.General().motion = false
    _G.GetMoney = function() return 1300 end
    stub.FireEvent("PLAYER_MONEY")
    T.eq(amount(f), 1300, "motion off: set at once")
    DaylightUI.DB.General().motion = true
    _G.GetMoney = function() return 9592 end
end)

-- ---------------------------------------------------------------------
-- No work done twice
-- ---------------------------------------------------------------------

local function countCalls(tbl, key)
    local c = { n = 0 }
    local orig = tbl[key]
    tbl[key] = function(...) c.n = c.n + 1; return orig(...) end
    c.undo = function() tbl[key] = orig end
    return c
end

T.test("bags: a burst of cooldown events is one pass over the open bag, the frame after", function()
    local ns = login()
    open(ns)
    local B = ns.Bags
    T.truthy(rawequal(B.Slots(), B.Slots()), "the slot list is kept, not built per ask")
    local c = countCalls(ns.Items, "FillCooldown")
    for _ = 1, 5 do stub.FireEvent("BAG_UPDATE_COOLDOWN") end
    T.eq(c.n, 0, "nothing yet")
    stub.RunTimers()
    T.eq(c.n, 32, "one pass: each slot once")
    T.truthy(B.buttons[0][1].calls.UpdateCooldown, "the cooldowns are drawn")
    c.undo()
    -- A bag that grows: the next list has its new slots.
    local before = B.Slots()
    world.sizes[2] = 4
    bagChanged(2)
    T.truthy(not rawequal(before, B.Slots()), "a new list once the bags change")
    T.eq(#B.Slots(), 36)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a closed bag's cooldowns are filled a frame's budget at a time; opening finishes them", function()
    local ns = login()
    quietly(ns)
    local c = countCalls(ns.Items, "FillCooldown")
    stub.FireEvent("BAG_UPDATE_COOLDOWN")
    stub.RunTimers()
    ns.Prep.BUDGET = 0
    quietly(ns, 3)
    T.eq(c.n, 3, "one slot a frame at the smallest budget, not all 32 in one")
    T.truthy(ns.Prep.worker:IsShown(), "still going")
    ns.Prep.BUDGET = 2
    quietly(ns)
    T.eq(c.n, 32, "each slot once")
    -- Cut short by opening, the open fills them all.
    stub.FireEvent("BAG_UPDATE_COOLDOWN")
    stub.RunTimers()
    ns.Prep.BUDGET = 0
    quietly(ns, 2)
    c.n = 0
    open(ns)
    ns.Prep.BUDGET = 2
    T.eq(c.n, 32, "the open does the rest")
    c.undo()
end)

T.test("bags: quest progress in a burst fills the bag once, the frame after", function()
    local ns = login()
    open(ns)
    local c = countFills(ns)
    stub.FireEvent("QUEST_ACCEPTED")
    for _ = 1, 4 do stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "player") end
    stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "party1")
    T.eq(c.n, 0, "nothing yet")
    stub.RunTimers()
    T.eq(c.n, 32, "every slot once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a bag change with grouped empty slots syncs the slots once", function()
    local ns = login()
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    stub.RunTimers()
    open(ns)
    local c = countCalls(ns.Bags, "Sync")
    world.items[1][3] = { iconFileID = 113, stackCount = 1, quality = 1, hyperlink = "|Hitem:13|h" }
    bagChanged(1)
    c.undo()
    T.eq(c.n, 1, "synced once, laid out after")
    T.eq(ns.Bags.buttons[1][3].calls.SetItemButtonTexture[1], 113)
end)

T.test("bags: a closed window's footer waits for it to open", function()
    local ns = login()
    local f = open(ns)
    f:Hide()
    local c = countCalls(ns.Bags, "Free")
    _G.GetMoney = function() return 700 end
    stub.FireEvent("PLAYER_MONEY")
    stub.FireEvent("CURRENCY_DISPLAY_UPDATE")
    T.eq(c.n, 0, "nothing for a closed window")
    world.items[0][3] = { iconFileID = 103, stackCount = 1, quality = 1, hyperlink = "|Hitem:3|h" }
    bagChanged(0)
    open(ns)
    c.undo()
    T.eq(freeText(f), "22 / 3", "opened: the free slots are right")
    T.eq(amount(f), 700, "and the gold, no count")
    _G.GetMoney = function() return 9592 end
end)

T.test("bank: closed, its buttons are hidden once, not on every bag update", function()
    local ns, bank = bankLogin()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    stub.FireEvent("BANKFRAME_CLOSED")
    bank.view[0], bank.view[2] = false, false
    stub.FinishFade(ns.bank)
    local set = ns.Bank.set
    bagChanged(0)
    T.falsy(set.buttons[6][1]:IsShown(), "hidden once the bank's gone")
    local hides = 0
    for _, id in ipairs({ 6, 7 }) do
        for _, btn in ipairs(set.buttons[id]) do
            local hide = btn.Hide
            btn.Hide = function(self) hides = hides + 1; return hide(self) end
        end
    end
    for _ = 1, 3 do bagChanged(0) end
    T.eq(hides, 0, "nothing hidden again")
    -- Back at the bank, shown as before.
    bank.view[0], bank.view[2] = true, true
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.truthy(set.buttons[6][1]:IsShown(), "shown again at the bank")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bank: the account bank's gold changing updates the footer, nothing else", function()
    local ns, bank = bankLogin()
    local f = ns.bank
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local account
    for _, t in ipairs(f.bankTabs) do if t.bankType == 2 then account = t end end
    account:GetScript("OnClick")(account)
    local c = countCalls(ns.Bank.set, "Sync")
    bank.gold = 6500
    stub.FireEvent("ACCOUNT_MONEY")
    c.undo()
    T.eq(c.n, 0, "no relayout")
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end   -- the gold counts there (SLOW)
    T.eq(f.money:GetText(), "money:6500", "the new gold shows")
end)

T.test("bags: the built-in groups show in the player's language; a renamed one as written", function()
    stub.Load({ bags = true, before = function() setup() end, locale = function(L) L["Weapons"] = "Waffen" end })
    local Cat = stub.bags.Categories
    T.eq(Cat.Get("weapon").name, "Waffen")
    Cat.Rename("weapon", "Swords")
    T.eq(Cat.Get("weapon").name, "Swords")
end)

T.test("bags: warm text; free slots amber then red as the bags fill", function()
    local ns = login()
    local f = open(ns)
    local INK = DaylightUI.Style.INK
    local function is(fs, c, why)
        local r, g, b = fs:GetTextColor()
        T.near(r, c[1], 0.01, why); T.near(g, c[2], 0.01, why); T.near(b, c[3], 0.01, why)
    end
    T.deq(ns.Window.DIM, INK.LABEL, "dim = warm label")
    T.deq(ns.Layout.HEAD_DIM, INK.LABEL, "category heads")
    is(f.free, { DaylightUI.Style.Pop() }, "23 free: a plain value pops in the accent")
    local real = f.set.Free
    f.set.Free = function() return 4, 32 end
    ns.Window.UpdateFooter(f)
    is(f.free, INK.WARN, "4 free: amber")
    f.set.Free = function() return 0, 32 end
    ns.Window.UpdateFooter(f)
    is(f.free, INK.BAD, "full: red")
    f.set.Free = real
    local c = ns.Items.BIND_COLOR
    T.near(c[1], INK.GOOD[1], 0.01, "BoE in good green"); T.near(c[2], INK.GOOD[2], 0.01)
end)

T.test("bags: categories view open, something else sold: a stack folded into another stays hidden", function()
    local ns = catLogin()
    local B = ns.Bags
    local other = B.buttons[1][1]
    T.falsy(other:IsShown(), "folded into the first bread")
    world.items[0][1] = nil
    bagChanged(0)
    T.falsy(other:IsShown(), "still folded, not shown at an old spot")
    world.items[1][2] = nil
    bagChanged(1)
    T.falsy(other:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Work only where something changed
-- ---------------------------------------------------------------------

T.test("bags: quest objective ticks fill nothing; accepting or dropping a quest fills once", function()
    local ns = login()
    open(ns)
    local c = countFills(ns)
    for _ = 1, 4 do stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "player") end
    stub.RunTimers()
    T.eq(c.n, 0, "an objective ticking changes no slot's quest mark")
    stub.FireEvent("QUEST_REMOVED", 7, false)
    stub.FireEvent("QUEST_ACCEPTED", 8)
    stub.RunTimers()
    T.eq(c.n, 32, "a quest dropped (or turned in) and one taken: every slot once")
end)

T.test("bags: changing gear refills no bag (the bag updates say which slots moved)", function()
    local ns = login()
    open(ns)
    local c = countFills(ns)
    local s = countCalls(ns.Bags, "Sync")
    for slot = 1, 3 do stub.FireEvent("PLAYER_EQUIPMENT_CHANGED", slot, false) end
    stub.RunTimers()
    s.undo()
    T.eq(c.n, 0, "no fill")
    T.eq(s.n, 0, "no sync")
end)

T.test("bags: typing a search only dims and lights the slots, it fills none", function()
    local ns = login()
    local f = open(ns)
    local c = countFills(ns)
    f.search:SetText("rare")
    f.search:GetScript("OnTextChanged")(f.search, true)
    T.eq(c.n, 0, "no fill per keystroke")
    T.eq(ns.Bags.buttons[0][1].calls.SetMatchesSearch[1], true)
    T.eq(ns.Bags.buttons[0][2].calls.SetMatchesSearch[1], false)
    T.eq(ns.Bags.buttons[0][3].calls.SetMatchesSearch[1], true, "an empty slot never dims")
    f:Hide()
    T.eq(c.n, 0, "the search cleared on close fills nothing either")
    T.eq(ns.Bags.buttons[0][2].calls.SetMatchesSearch[1], true, "nothing dimmed for the next open")
    T.falsy(f.dirtyAll, "and nothing left to fill")
end)

T.test("bags: the footer counts and colors the plain bags, as the data text does", function()
    local ns = login()
    local f = open(ns)
    T.eq(freeText(f), "23 / 3", "the profession bag's slots counted apart")
    -- Fill every plain slot. The profession bag still has room.
    for s = 1, 16 do world.items[0][s] = world.items[0][s] or { iconFileID = 900, stackCount = 1, quality = 1, hyperlink = "|Hitem:90|h" } end
    for s = 1, 12 do world.items[1][s] = { iconFileID = 900, stackCount = 1, quality = 1, hyperlink = "|Hitem:90|h" } end
    bagChanged(0); bagChanged(1)
    T.eq(freeText(f), "0 / 3")
    local r, g, b = f.free:GetTextColor()
    local bad = DaylightUI.Style.INK.BAD
    T.near(r, bad[1], 0.01, "full: red, even with the profession bag's room")
    T.near(g, bad[2], 0.01); T.near(b, bad[3], 0.01)
end)

T.test("bags: an item still loading asks once to be told, however often it's filled", function()
    local ns = login()
    local asks, loaded = 0, {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end,
                 ContinueOnItemLoad = function(_, fn) asks = asks + 1; loaded[bag .. ":" .. slot] = fn end }
    end }
    local late = ns.Bags.buttons[0][6]
    for _ = 1, 5 do ns.Items.Fill(late) end
    T.eq(asks, 1, "one wait per slot, not one per fill")
    world.bind["|Hitem:7|h"] = 3
    loaded["0:6"]()
    T.eq(ns.Items.Parts(late).bind:GetText(), "BoU", "filled once loaded")
    T.isnil(late.dluiWaiting, "no longer waiting")
    _G.Item = nil
end)

-- Loaded and still no bind type (a keystone: or battlepet: cage link). The load
-- refilled it, the fill asked again, and the game answered again
-- (ITEM_DATA_LOAD_RESULT for a cached item), giving a fill every frame.
T.test("bags: an item that loads still half empty is waited for once, not again on each load", function()
    local ns = login()
    local asks, loaded = 0, {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end,
                 ContinueOnItemLoad = function(_, fn) asks = asks + 1; loaded[bag .. ":" .. slot] = fn end }
    end }
    local late = ns.Bags.buttons[0][6]
    ns.Items.Fill(late)
    T.eq(asks, 1)
    for _ = 1, 3 do
        local fn = loaded["0:6"]
        loaded["0:6"] = nil
        if fn then fn() end
    end
    ns.Items.Fill(late)
    T.eq(asks, 1, "loaded once: never asked again for the same item")
    -- Another item in the slot is its own wait.
    world.items[0][6].hyperlink = "|Hitem:9|h"
    world.items[0][6].itemID = 9
    ns.Items.Fill(late)
    T.eq(asks, 2, "a new item in the slot asks for itself")
    _G.Item = nil
end)

T.test("bags: grouped empty slots, an item sold while open: the free tile counts it", function()
    local ns = login()
    local f = open(ns)
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    stub.RunTimers()
    local tile = ns.Bags.buttons[0][3]
    T.eq(ns.Items.Parts(tile).free:GetText(), 23)
    world.items[0][1] = nil
    bagChanged(0)
    T.truthy(f.stale, "held still: laid out on the next open")
    T.eq(ns.Items.Parts(tile).free:GetText(), 24, "one more free")
end)

-- A link the item info never gives a stack size for, loaded or not (a keystone:
-- or battlepet: cage). The game answers each request with ITEM_DATA_LOAD_RESULT
-- (RequestLoadItemDataByID), so asking on every layout laid the open bag out
-- again every frame.
T.test("bags: categories view, a link with no stack size is waited for once, not every layout", function()
    local ns = catLogin()
    local asks, loaded = 0, {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end,
                 ContinueOnItemLoad = function(_, fn) asks = asks + 1; loaded[#loaded + 1] = fn end }
    end }
    world.maxStack[8] = nil
    ns.Relayout()
    ns.FillAll()
    T.truthy(asks >= 1, "asked to be told when it loads")
    for round = 1, 3 do
        local now = loaded
        loaded = {}
        for _, fn in ipairs(now) do fn() end
        stub.RunTimers()
        ns.Relayout()
    end
    local was = asks
    ns.Relayout(); stub.RunTimers()
    T.eq(asks, was, "loaded and still no stack size: never asked again")
    T.eq(#loaded, 0, "nothing left to lay it out again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.Item = nil
end)

T.test("bags: categories view, an item whose stack size loads late combines once it has", function()
    local ns = catLogin()
    local B = ns.Bags
    local loaded = {}
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end,
                 ContinueOnItemLoad = function(_, fn) loaded[#loaded + 1] = fn end }
    end }
    world.maxStack[8] = nil
    ns.Relayout()
    ns.FillAll()
    local first, other = B.buttons[0][8], B.buttons[1][1]
    T.truthy(other:IsShown(), "not known to stack yet: shown apart")
    T.truthy(#loaded >= 1, "asked to be told when it loads")
    world.maxStack[8] = 20
    local now = {}
    for i, fn in ipairs(loaded) do now[i] = fn end
    for _, fn in ipairs(now) do fn() end
    stub.RunTimers()
    T.falsy(other:IsShown(), "folded into the first once loaded")
    T.eq(first.dluiCount, 12)
    _G.Item = nil
end)

T.test("bags: a herb bag's free slots follow the plain count, in the herb bag's color", function()
    local ns = login()
    world.family = { [1] = 32 }
    local f = open(ns)
    ns.Window.UpdateFooter(f)
    local herb = ns.Items.BAG_COLORS[ns.Items.BagKind(1)].color
    T.eq(freeText(f), "11 / 12 / 3", "plain bags, the herb bag, the profession bag")
    T.truthy(f.free:GetText():find(DaylightUI.Win.Parts.Hex(herb) .. "12|r", 1, true), "12 in the herb bag's green")
    world.family = nil
end)

T.test("bags: a locked item: the menu locks it, a padlock shows, never junk, never sold", function()
    local ns = catLogin()
    local sold = {}
    C_Container.UseContainerItem = function(bag, slot) sold[#sold + 1] = bag .. ":" .. slot end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:2|h" then return "name", link, 0, 1, 1, "", "", 1, "", 1, 25, 0, 0, 0 end
        return getInfo(link)
    end
    local gray = ns.Bags.buttons[0][2]
    local id = C_Container.GetContainerItemInfo(0, 2).itemID
    T.eq(groupOf(ns, gray), "junk")
    local Cat = ns.Categories
    -- In the Alt-right-click menu, the first row locks it.
    local picked
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, keys, values, _, onPick, _, opts)
        picked = { keys = keys, values = values, pick = onPick, opts = opts }
    end
    Cat.Menu(gray)
    T.eq(picked.keys[1], "lock", "on top: the menu's usual 12 rows hid it at the bottom")
    T.truthy(#picked.keys > 12 and picked.opts.rows >= #picked.keys, "every row shows with no scrolling")
    picked.pick("lock")
    T.truthy(Cat.IsLocked(id))
    stub.RunTimers()
    T.truthy(ns.Items.Parts(gray).lock:IsShown(), "a padlock on it")
    T.truthy(groupOf(ns, gray) ~= "junk", "a locked gray item isn't junk")
    T.truthy(ns.Search.Parse("locked")(Cat.Facts(0, 2, C_Container.GetContainerItemInfo(0, 2))), "the search finds it")
    stub.FireEvent("MERCHANT_SHOW")
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(#sold, 0, "never sold")
    Cat.Menu(gray)
    T.eq(picked.values.lock, DaylightUI.L["Unlock"])
    picked.pick("lock")
    stub.RunTimers()
    T.falsy(ns.Items.Parts(gray).lock:IsShown(), "unlocked: the padlock goes")
    DaylightUI.Widgets.OpenMenu = openMenu
    C_Item.GetItemInfo = getInfo
end)

T.test("bags: a locked item's slot takes no clicks at a vendor or under Disenchant; Alt-right-click still unlocks it", function()
    local ns = catLogin()
    local gray = ns.Bags.buttons[0][2]
    local other = ns.Bags.buttons[0][1]
    local id = C_Container.GetContainerItemInfo(0, 2).itemID
    local Cat = ns.Categories
    Cat.ToggleLock(id)
    stub.RunTimers()
    local clicks = function(b) return #(b.__clicks or {}) end
    T.falsy(gray.dluiGuarded, "no vendor: a locked item clicks like any other")

    stub.FireEvent("MERCHANT_SHOW")
    T.truthy(gray.dluiGuarded)
    T.eq(clicks(gray), 0, "at a vendor no click reaches the game's sale")
    T.eq(#gray.__drag, 0, "and it can't be dragged onto the vendor")
    T.falsy(other.dluiGuarded, "the item beside it sells as ever")
    gray:GetScript("OnMouseUp")(gray, "RightButton")
    T.truthy(stub.ChatContains("is locked"), "a click says why nothing happened")
    stub.FireEvent("MERCHANT_CLOSED")
    T.falsy(gray.dluiGuarded)
    T.eq(clicks(gray), 2, "the vendor gone: the game's two clicks back")
    T.eq(gray.__drag[1], "LeftButton")

    local current = false
    C_Spell.IsCurrentSpell = function(id2) return current and id2 == ns.Disenchant.SPELL end
    current = true
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    T.eq(clicks(gray), 0, "Disenchant on the cursor: no click reaches the game")
    current = false
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    T.eq(clicks(gray), 2, "the hand gone: back")

    stub.FireEvent("MERCHANT_SHOW")
    local menu
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, _, _, _, onPick) menu = onPick end
    local alt = _G.IsAltKeyDown
    _G.IsAltKeyDown = function() return true end
    gray:GetScript("OnMouseUp")(gray, "RightButton")
    _G.IsAltKeyDown = alt
    DaylightUI.Widgets.OpenMenu = openMenu
    menu("lock")
    stub.RunTimers()
    T.eq(clicks(gray), 2, "unlocked at the vendor: it sells again")
    stub.FireEvent("MERCHANT_CLOSED")
end)

T.test("bags: Sell junk leaves a locked gray item, and the game's sell-all button stays off for it", function()
    local game = 0
    local ns = catLogin()
    C_MerchantFrame = C_MerchantFrame or {}
    C_MerchantFrame.SellAllJunkItems = function() game = game + 1 end
    local sold = {}
    C_Container.UseContainerItem = function(bag, slot) sold[#sold + 1] = bag .. ":" .. slot end
    world.items[0][2].itemID = 2
    world.items[0][7] = { iconFileID = 107, stackCount = 1, quality = 0, hyperlink = "|Hitem:21|h", itemID = 21 }
    DaylightUI:Set("Bags", "sellJunk", false)
    stub.FireEvent("MERCHANT_SHOW")
    T.falsy(DaylightUI.SellJunkAroundLocks(), "nothing locked: the game's own sale")
    ns.Categories.ToggleLock(2)
    T.eq(DaylightUI.ItemLocked(2), true)
    local b = CreateFrame("Button", "MerchantSellAllJunkButton", UIParent)
    b:SetEnabled(true)
    ns.Junk.GameButton()
    T.falsy(b:IsEnabled(), "the game's button would take the locked one")
    T.truthy(DaylightUI.SellJunkAroundLocks())
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(table.concat(sold, ","), "0:7", "only the other gray item")
    T.eq(game, 0)
    _G.MerchantSellAllJunkButton = nil
    stub.FireEvent("MERCHANT_CLOSED")
end)

-- A messy bag and the game's rule for moves: a slot being moved stays locked
-- until the server answers a beat later.
local function keepWorld()
    world.items[0] = {}
    world.items[1] = {}
    local function item(id, name, count)
        return { iconFileID = id, stackCount = count or 1, quality = 1, itemID = id, itemName = name,
                 hyperlink = "|Hitem:" .. id .. "|h" }
    end
    world.items[0][3] = item(30, "Cherry")
    world.items[0][9] = item(10, "Apple")
    world.items[0][2] = item(20, "Banana")
    world.items[1][4] = item(40, "Date")
    C_Item.GetItemInfo = function(link) return "name", link, 1, 1, 1, "", "", 1, "", 1, 1 end
    cursorWorld()
    world.maxStack = {}
    -- The game's rule: an item put on a different one swaps with it.
    local put = C_Container.PickupContainerItem
    C_Container.PickupContainerItem = function(bag, slot)
        local held, here = world.held, world.items[bag][slot]
        if held and here and here.itemID ~= world.items[held.bag][held.slot].itemID then
            world.items[bag][slot], world.items[held.bag][held.slot] = world.items[held.bag][held.slot], here
            world.held = nil
            return
        end
        return put(bag, slot)
    end
    return item
end

T.test("bags: Clean Up leaves a kept slot alone and sorts the rest around it; with none kept it's the game's sort", function()
    local ns = login({ view = "grid" })
    keepWorld()
    local f = open(ns)
    ns.FillAll()
    local Keep = ns.Keep
    T.falsy(Keep.Any())
    f.sort:GetScript("OnClick")(f.sort)
    T.eq(world.sorted, 1, "nothing kept: the game's own sort")
    Keep.Toggle(0, 3, 30)
    T.truthy(ns.Items.Parts(ns.Bags.buttons[0][3]).keep:IsShown(), "a line on the kept slot")
    T.falsy(ns.Items.Parts(ns.Bags.buttons[0][2]).keep:IsShown())
    f.sort:GetScript("OnClick")(f.sort)
    T.eq(world.sorted, 1, "kept: not the game's sort, which would move it")
    for _ = 1, 10 do stub.RunTimers() end
    T.eq(world.items[0][3].itemName, "Cherry", "the kept item never moved")
    T.eq(world.items[0][1].itemName, "Apple")
    T.eq(world.items[0][2].itemName, "Banana")
    T.eq(world.items[0][4].itemName, "Date", "the rest flows around it")
    T.isnil(world.items[1][4], "and leaves the bag it came from")
    T.falsy(CursorHasItem(), "nothing left on the cursor")
    -- Already tidy, so not one move.
    local picks = 0
    local pick = C_Container.PickupContainerItem
    C_Container.PickupContainerItem = function(...) picks = picks + 1; return pick(...) end
    f.sort:GetScript("OnClick")(f.sort)
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(picks, 0, "nothing to do")
end)

T.test("bags: a kept item that wandered off comes back; a kept slot with its item gone stays free", function()
    local ns = login({ view = "grid" })
    keepWorld()
    local f = open(ns)
    local Keep = ns.Keep
    Keep.Toggle(0, 5, 20)       -- Banana lives at 0:5, but it's at 0:2
    Keep.Toggle(0, 1, 99)       -- this one's item is gone
    f.sort:GetScript("OnClick")(f.sort)
    for _ = 1, 10 do stub.RunTimers() end
    T.eq(world.items[0][5].itemName, "Banana", "home")
    T.isnil(world.items[0][1], "kept free for its item")
    T.eq(world.items[0][2].itemName, "Apple", "the rest starts after it")
end)

T.test("bags: Clean Up with kept slots stops in a fight and never moves a locked slot", function()
    local ns = login({ view = "grid" })
    keepWorld()
    local f = open(ns)
    ns.Keep.Toggle(0, 3, 30)
    world.items[0][9].isLocked = true
    f.sort:GetScript("OnClick")(f.sort)
    stub.RunTimers()
    T.eq(world.items[0][9].itemName, "Apple", "a locked slot waits")
    world.items[0][9].isLocked = nil
    stub.EnterCombat()
    stub.RunTimers()
    T.truthy(stub.ChatContains("Clean up stopped"), "says why")
    T.eq(world.items[0][9].itemName, "Apple")
    stub.LeaveCombat()
end)

T.test("bags: topping up stacks never empties a kept slot", function()
    local ns = login({ view = "grid" })
    local item = keepWorld()
    C_Item.GetItemInfo = function(link) return "name", link, 1, 1, 1, "", "", 20, "", 1, 1 end
    world.maxStack = { [50] = 20 }
    world.items[0][1] = item(50, "Bread", 5)
    world.items[0][6] = item(50, "Bread", 5)
    ns.Keep.Toggle(0, 6, 50)
    open(ns)
    ns.Stack.Run(); stub.RunTimers(); stub.RunTimers()
    T.eq(world.items[0][6].stackCount, 10, "the kept slot took the other")
    T.isnil(world.items[0][1])
end)

T.test("bags: the item menu offers the slot only bag by bag; an empty kept slot can be let go", function()
    local ns = login({ view = "grid" })
    keepWorld()
    open(ns)
    local Cat, Keep = ns.Categories, ns.Keep
    local keys, values, pick
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, k, v, _, onPick) keys, values, pick = k, v, onPick end
    local btn = ns.Bags.buttons[0][3]
    Cat.Menu(btn)
    T.eq(table.concat(keys, ","), "lock,keep,junkmark", "bag by bag: these and Sell as junk, no groups")
    T.eq(values.keep, DaylightUI.L["Keep in this slot"])
    pick("keep")
    T.eq(Keep.At(0, 3), 30)
    world.items[0][3] = nil
    keys = nil
    Cat.Menu(btn)
    T.eq(#keys, 1, "empty: only the way to free it")
    T.eq(values.keep, DaylightUI.L["Stop keeping in this slot"])
    pick("keep")
    T.isnil(Keep.At(0, 3))
    keys = nil
    Cat.Menu(btn)
    T.isnil(keys, "an empty slot not kept has no menu")
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    world.items[0][3] = { iconFileID = 1, stackCount = 1, itemID = 30, hyperlink = "|Hitem:30|h" }
    Cat.Menu(btn)
    for _, k in ipairs(keys) do T.truthy(k ~= "keep", "no slots in the categories view") end
    DaylightUI.Widgets.OpenMenu = openMenu
end)

-- ---------------------------------------------------------------------
-- The viewer: your bank anywhere, and your other characters' bags (Saved.lua, Viewer.lua)
-- ---------------------------------------------------------------------

T.test("viewer: the bank seen at a banker shows anywhere after, look only", function()
    local ns = bankLogin()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local inv = DaylightUI.DB.Character().inventory
    T.truthy(inv and inv.bank, "the bank saved while it's open")
    T.eq(#inv.bank, 2, "both character tabs")
    T.eq(inv.bank[1].items[1][1], "|Hitem:61|h")
    T.truthy(DaylightUI.DB.Root().accountBank, "the account bank saved once for all")
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.RunTimers()
    ns.Viewer.Open()
    stub.RunTimers()
    local f = ns.Viewer.window
    T.truthy(f:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(#ns.Viewer.set.Slots(), 12, "8 + 4 slots, away from the bank")
    local first = ns.Viewer.set.Slots()[1].button
    T.eq(first.dluiTexture, 601, "the saved item's icon")
    T.falsy(first.calls, "a plain item button, never the game's bag button")
    T.truthy(f.empty and not f.empty:IsShown(), "no empty line with slots")
    -- The live bag's slots still read the game.
    T.eq(ns.Items.InfoAt(0, 1).iconFileID, 101)
end)

-- The game at PLAYER_LOGOUT, where the bags and gold already read empty. Every
-- character's saved file on the modern client showed bags = {} and money = 0.
local function logout()
    for id in pairs(world.sizes) do world.sizes[id] = 0 end
    _G.GetMoney = function() return 0 end
    stub.FireEvent("PLAYER_LOGOUT")
end

T.test("viewer: logging out at a banker keeps the saved bank and gold", function()
    local ns = bankLogin()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local inv = DaylightUI.DB.Character().inventory
    T.eq(#inv.bank, 2)
    T.eq(inv.money, 9592)
    logout()
    T.eq(#inv.bank, 2, "the empty read at logout keeps the bank")
    T.eq(inv.bank[1].items[1][1], "|Hitem:61|h")
    T.truthy(DaylightUI.DB.Root().accountBank, "and the account bank")
    T.eq(inv.money, 9592, "and the gold")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: a bank still arriving never replaces a fuller saved copy", function()
    local ns, bank = bankLogin()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local inv = DaylightUI.DB.Character().inventory
    T.eq(#inv.bank, 2, "both character tabs saved")
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.RunTimers()
    -- The next visit: the second tab's slots haven't arrived yet (they read 0).
    world.sizes[7] = 0
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.eq(#inv.bank, 2, "a tab still reading 0 slots: the full copy stays")
    -- Then the tab list itself only has the first tab so far.
    world.sizes[7] = 4
    local tabs = bank.tabs[0]
    bank.tabs[0] = { tabs[1] }
    ns.Saved.SaveBank()
    T.eq(#inv.bank, 2, "fewer tabs than were bought: the full copy stays")
    bank.tabs[0] = tabs
    ns.Saved.SaveBank()
    T.eq(#inv.bank, 2)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: your own character is in the picker on a first session, nothing saved yet", function()
    local ns = login()
    DaylightUI.DB.Character().inventory = nil
    local own = DaylightUI.DB.CharKey()
    local found
    for _, c in ipairs(ns.Saved.Characters()) do if c.key == own then found = c end end
    T.truthy(found, "you're listed, to switch back to")
    T.truthy(found and found.own)
end)

T.test("viewer: your bags and gold are saved while you play, never emptied by the logout", function()
    local ns = login()
    stub.RunTimers()
    local mine = DaylightUI.DB.Character().inventory
    T.truthy(mine and mine.bags and #mine.bags > 0, "saved soon after login")
    T.eq(mine.money, 9592)
    world.items[1][3] = { iconFileID = 113, stackCount = 1, quality = 1, hyperlink = "|Hitem:13|h" }
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(mine.bags[2].items[3][1], "|Hitem:13|h", "a new item saved after the change")
    logout()
    T.eq(mine.bags[1].items[1][1], "|Hitem:1|h", "the logout's empty read keeps the good copy")
    T.eq(mine.money, 9592, "and the gold")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: another character's bags, saved at their logout; tabs and gold follow", function()
    local ns = login()
    stub.FireEvent("PLAYER_LOGOUT")
    local mine = DaylightUI.DB.Character().inventory
    T.truthy(mine and mine.bags, "your bags saved at logout")
    T.eq(mine.bags[1].items[1][1], "|Hitem:1|h")
    T.eq(mine.bags[#mine.bags].section, "profession")
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", money = 123, time = time() - 7200,
        bags = { { section = "bags", size = 4, items = { [2] = { "|Hitem:9|h", 3, 909, 2 } } } } } }
    T.truthy(#ns.Saved.Characters() >= 2, "both characters listed")
    ns.Viewer.Open(alt, "bags")
    stub.RunTimers()
    local f = ns.Viewer.window
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(f.title:GetText(), "Alt")
    T.eq(#ns.Viewer.set.Slots(), 4)
    T.eq(ns.Viewer.set.Button(ns.Saved.BASE + 1, 2).dluiTexture, 909)
    T.eq(ns.Viewer.set.Button(ns.Saved.BASE + 1, 2).count, 3)
    T.eq(f.money:GetText(), DaylightUI.Widgets.Money(123), "their gold")
    T.truthy(f.free:GetText():find("3 / 4"), "free / all")
    -- Their bank was never seen, so one line says so and there are no slots.
    ns.Viewer.Show(alt, "bank")
    stub.RunTimers()
    T.eq(#ns.Viewer.set.Slots(), 0)
    T.truthy(f.empty:IsShown(), "nothing saved yet, said")
    -- Yours has no Bags tab, since your bag is the bag window.
    ns.Viewer.Show(DaylightUI.DB.CharKey(), "bags")
    T.eq(ns.Viewer.part, "bank")
    for _, t in ipairs(f.viewTabs) do
        if t.part == "bags" then T.falsy(t:IsShown()) end
    end
    -- The bags changing never lays the viewer out.
    world.items[0][3] = { iconFileID = 103, stackCount = 1, quality = 1, hyperlink = "|Hitem:3|h" }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: removing a character takes their bags, gold and mail name, and the window moves off them", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { money = 123, mailName = "Alt", install = "installed",
        inventory = { class = "MAGE", money = 123, time = time(),
        bags = { { section = "bags", size = 4, items = { [2] = { "|Hitem:9|h", 3, 909, 2 } } } } } }
    local bag = open(ns)
    ns.Viewer.Open(alt, "bags")
    stub.RunTimers()
    local menu
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(owner, keys, values, _, onPick, _, opts)
        menu = { owner = owner, keys = keys, values = values, pick = onPick, opts = opts }
    end
    ns.Viewer.PickMenu(ns.Viewer.window.charsButton)
    T.eq(menu.keys[#menu.keys], "remove", "the picker's list ends with the way to remove one")
    T.truthy(menu.opts.more.remove, "a chevron: it opens another list")
    menu.pick("remove")
    T.eq(menu.owner, ns.Viewer.window.charsButton)
    T.truthy(menu.opts.confirm[alt], "asks first")
    menu.pick(alt)
    DaylightUI.Widgets.OpenMenu = openMenu
    T.eq(ns.Saved.Of(alt), nil, "their saved bags are gone")
    T.eq(DaylightUI.DB.Root().characters[alt].mailName, nil, "off the mail window's names")
    T.eq(DaylightUI.DB.Root().characters[alt].install, "installed", "their setup stays")
    T.eq(ns.Viewer.who, DaylightUI.DB.CharKey(), "the window goes back to you")
    T.eq(ns.Viewer.part, "bank")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: yourself can't be removed, and alone the picker's list has no such row", function()
    local ns = login()
    local own = DaylightUI.DB.CharKey()
    T.eq(DaylightUI.Alts.Forget(own), false)
    T.eq(#DaylightUI.Alts.List(), 0)
    local bag = open(ns)
    local menu
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, keys) menu = keys end
    ns.Viewer.PickMenu(ns.Viewer.window.charsButton)
    DaylightUI.Widgets.OpenMenu = openMenu
    for _, k in ipairs(menu) do T.truthy(k ~= "remove") end
end)

T.test("viewer: switching to nothing saved glides the window and fades the line in, never a jump", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", money = 1, time = time(),
        bags = { { section = "bags", size = 4, items = { [2] = { "|Hitem:9|h", 3, 909, 2 } } } } } }
    ns.Viewer.Open(alt, "bags")
    stub.RunTimers()
    local f = ns.Viewer.window
    local h0 = f:GetHeight()
    ns.Viewer.Show(alt, "bank")
    T.eq(f:GetHeight(), h0, "the height starts where it was")
    T.truthy(f.empty:IsShown())
    T.eq(f.empty:GetAlpha(), 0, "the line fades in from nothing")
    local feel = DaylightUI.Win.Feel.Driver()
    feel:GetScript("OnUpdate")(feel, 1)
    local motion = DaylightUI.Motion.Driver()
    if motion and motion:GetScript("OnUpdate") then motion:GetScript("OnUpdate")(motion, 1) end
    T.truthy(f:GetHeight() ~= h0, "then glides to its new size")
    T.eq(f.empty:GetAlpha(), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: the Alts tab opens it; the search dims a saved copy too", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", money = 1, time = time(),
        bags = { { section = "bags", size = 2, items = { [1] = { "|cff1eff00|Hitem:9|h[Wand]|h|r", 1, 909, 2 },
                                                         [2] = { "|Hitem:8|h[Bread]|h", 5, 808, 1 } } } } } }
    local bag = open(ns)
    -- The Alts tab opens the window on another character's bags; the picker in
    -- the window lists everyone and switches between them.
    T.falsy(ns.Viewer.window:IsShown())
    bag.tabs[3]:Click()
    stub.RunTimers()
    local f = ns.Viewer.window
    T.truthy(f:IsShown(), "opened from the bag")
    T.eq(ns.Viewer.who, alt)
    T.eq(ns.Viewer.part, "bags", "on their bags")
    local menu
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(owner, keys, values, _, onPick) menu = { owner = owner, keys = keys, values = values, pick = onPick } end
    ns.Viewer.PickMenu(f.charsButton)
    DaylightUI.Widgets.OpenMenu = openMenu
    T.truthy(menu.values[alt]:find("Alt"), "by name")
    T.truthy(menu.values[alt]:find("|c"), "in their class color")
    menu.pick(DaylightUI.DB.CharKey())
    T.eq(ns.Viewer.who, DaylightUI.DB.CharKey())
    ns.Viewer.Show(alt, "bags")
    stub.RunTimers()
    f.search:SetText("wand")
    stub.RunTimers()
    local wand, bread = ns.Viewer.set.Button(ns.Saved.BASE + 1, 1), ns.Viewer.set.Button(ns.Saved.BASE + 1, 2)
    T.truthy(ns.Search.Matches(ns.Saved.BASE + 1, 1, ns.Items.InfoAt(ns.Saved.BASE + 1, 1), f.match), "the wand matches")
    T.falsy(ns.Search.Matches(ns.Saved.BASE + 1, 2, ns.Items.InfoAt(ns.Saved.BASE + 1, 2), f.match), "the bread doesn't")
    T.truthy(wand and bread)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: switched off, the Alts tab goes (the others close up), nothing new is saved", function()
    local ns = login()
    local bag = open(ns)
    T.falsy(bag.viewerButton, "no chest button in the tool row any more")
    local alts, bank = bag.tabs[3], bag.tabs[2]
    T.truthy(alts:IsShown())
    local _, relOn = bank:GetPoint(1)
    T.eq(relOn, alts, "Bank sits beside Alts")
    DaylightUI:Set("Bags", "viewer.enabled", false)
    stub.RunTimers()
    T.falsy(alts:IsShown(), "the Alts tab goes")
    local _, rel = bank:GetPoint(1)
    T.eq(rel, bag.close, "Bank takes Alts' place")
    headerFits(bag, { bag.tabs[1] })
    ns.Viewer.Toggle()
    stub.RunTimers()
    T.falsy(ns.Viewer.window:IsShown(), "/dui bank says it's off instead")
    T.truthy(stub.ChatContains("Bank and alts is off"))
    DaylightUI.DB.Character().inventory = nil
    stub.FireEvent("PLAYER_LOGOUT")
    T.falsy(DaylightUI.DB.Character().inventory, "nothing saved while off")
    DaylightUI:Set("Bags", "viewer.enabled", true)
    stub.RunTimers()
    T.truthy(alts:IsShown(), "back on: the tab's back")
    local _, rel2 = bank:GetPoint(1)
    T.eq(rel2, alts)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the header tabs open the bank and the alts viewer", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", money = 1, time = time(),
        bags = { { section = "bags", size = 4, items = {} } } } }
    local bag = open(ns)
    T.eq(#bag.tabs, 3)
    T.eq(bag.tab, "bags", "Bags is picked on open")
    headerFits(bag, bag.tabs)
    tabsOnTitleRow(bag, bag.tabs)
    -- Away from a banker: the saved bank, in the viewer.
    bag.tabs[2]:Click()
    stub.RunTimers()
    local v = ns.Viewer.window
    T.truthy(v:IsShown(), "the saved bank opens")
    T.eq(ns.Viewer.part, "bank")
    T.eq(ns.Viewer.who, DaylightUI.DB.CharKey())
    T.eq(bag.tab, "bags", "the Bags tab stays picked")
    -- At a banker: the live bank.
    ns.Viewer.Close()
    stub.RunTimers()
    ns.Bank.open = true
    bag.tabs[2]:Click()
    stub.RunTimers()
    T.truthy(ns.Bank.window:IsShown(), "the live bank opens")
    T.falsy(DaylightUI.Motion.Shown(v), "not the viewer")
    ns.Bank.open = false
    -- Alts: another character's bags.
    bag.tabs[3]:Click()
    stub.RunTimers()
    T.truthy(v:IsShown())
    T.eq(ns.Viewer.part, "bags")
    T.eq(ns.Viewer.who, alt)
    T.eq(bag.tab, "bags")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: its own columns, and its own look once Same look as your bags is off", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    DaylightUI.DB.Root().characters["Alt-" .. realm] = { inventory = { class = "MAGE", money = 1, time = time(),
        bags = { { section = "bags", size = 20, items = {} } } } }
    DaylightUI:Set("Bags", "viewer.view", "grid")
    DaylightUI:Set("Bags", "view", "grid")
    stub.RunTimers()
    ns.Viewer.Open("Alt-" .. realm, "bags")
    stub.RunTimers()
    local f = ns.Viewer.window
    local w14 = f:GetWidth()
    DaylightUI:Set("Bags", "viewer.columns", 10)
    stub.RunTimers()
    T.truthy(f:GetWidth() < w14, "fewer columns: narrower")
    T.eq(f.Setting("iconSize"), DaylightUI:Get("Bags", "iconSize"), "follows the bags' slot size")
    DaylightUI:Set("Bags", "viewer.ownLook", true)
    DaylightUI:Set("Bags", "viewer.iconSize", 24)
    stub.RunTimers()
    T.eq(f.Setting("iconSize"), 24, "its own once it has its own look")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bank: DaylightUI.BankWindow() is our bank window (DaylightMogul docks to it)", function()
    local ns = bankLogin()
    T.truthy(DaylightUI.BankWindow() == ns.bank, "the real bank window")
end)

T.test("bags: closing ours never runs the game's CloseAllBags: its who-opened-them local would be tainted", function()
    local ns = login()
    local f = ns.window
    OpenAllBags()
    stub.RunTimers()
    f.close:GetScript("OnClick")(f.close)
    stub.RunTimers()
    stub.FinishFade(f)
    T.falsy(IsAnyBagOpen(), "the X still closes the game's bags")
    T.eq(world.closeAll, 0, "by hiding its windows")
    OpenAllBags()
    stub.RunTimers()
    f:Hide()
    T.falsy(IsAnyBagOpen(), "any other close too")
    T.eq(world.closeAll, 0)
end)

T.test("bags: with the controller UI on they close with the character window, as the game's own does", function()
    local ns = login()
    local f = ns.window
    OpenAllBags()
    stub.RunTimers()
    DaylightUI.Fire("CharacterWindowClosed")
    stub.RunTimers()
    T.truthy(IsAnyBagOpen(), "with a mouse the bag stays")
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    DaylightUI.Fire("CharacterWindowClosed")
    stub.RunTimers()
    stub.FinishFade(f)
    _G.InputUtil, _G.GamepadMode = nil, nil
    T.falsy(IsAnyBagOpen(), "the game's bags closed")
    T.falsy(f:IsShown(), "and ours")
end)

-- A stream of bag changes (looting, a vendor) leads to one read of every slot once
-- it stops. A fight waits for its end.
T.test("viewer: bags are saved once the changes stop, never in a fight", function()
    local ns = login()
    stub.RunTimers()
    local saves, save = 0, ns.Saved.SaveBags
    ns.Saved.SaveBags = function(...) saves = saves + 1; return save(...) end
    local waits, after = {}, C_Timer.After
    C_Timer.After = function(_, fn) waits[#waits + 1] = fn end
    ns.Saved.SaveBagsSoon()
    ns.Saved.SaveBagsSoon()
    C_Timer.After = after
    T.eq(#waits, 2, "the second change starts the wait again")
    waits[1]()
    T.eq(saves, 0, "not after the first change")
    waits[2]()
    T.eq(saves, 1, "after the last")
    stub.combat = true
    ns.Saved.SaveBagsSoon()
    stub.RunTimers()
    T.eq(saves, 1, "not in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(saves, 2, "when it ends")
    ns.Saved.SaveBags = save
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: on a controller the D-pad starts on the first item, once an opening", function()
    local ns = login()
    local f = ns.window
    OpenAllBags()
    stub.RunTimers()
    local want
    for i, s in ipairs(f.set.Slots()) do   -- the fake game has no screen positions, so use the grid's, first row highest
        s.button:Show()
        s.button.GetTop = function() return 100 - math.floor((i - 1) / 4) end
        s.button.GetLeft = function() return 10 + (i - 1) % 4 end
        want = want or s.button
    end
    local first = ns.Window.FirstSlot(f)
    T.eq(first, want, "top left")
    CloseAllBags()
    stub.RunTimers()
    stub.FinishFade(f)
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    local aimed, m = 0, {}
    function m:FrameShown(frame) frame:FocusGamepad() end
    function m:FrameHidden() end
    _G.GamepadMode = { FrameControlsManager = m }
    _G.SmartNavigation = { RefreshButtonGroups = function() end, GetCurrentButton = function() end,
        SetTargetButtonForFrame = function(_, _, b) aimed = aimed + 1; T.eq(b, first) end }
    OpenAllBags()
    stub.RunTimers()
    T.eq(aimed, 1)
    f:FocusGamepad()                -- back from a menu, it stays where it was
    stub.RunTimers()
    T.eq(aimed, 1)
    f:UnfocusGamepad()
    _G.InputUtil, _G.GamepadMode, _G.SmartNavigation = nil, nil, nil
end)

T.test("viewer: a right-click on the bag's title bar opens your bank, again closes it", function()
    local ns = login()
    local bag = open(ns)
    local v = ns.Viewer.window
    bag.handle:GetScript("OnMouseUp")(bag.handle, "LeftButton")
    stub.RunTimers()
    T.falsy(v:IsShown(), "a left click on the title bar does nothing")
    bag.handle:GetScript("OnMouseUp")(bag.handle, "RightButton")
    stub.RunTimers()
    T.truthy(v:IsShown(), "the title bar's right-click: the bank")
    T.eq(ns.Viewer.part, "bank")
    T.eq(ns.Viewer.who, DaylightUI.DB.CharKey(), "your own")
    bag.handle:GetScript("OnMouseUp")(bag.handle, "RightButton")
    stub.RunTimers()
    T.falsy(DaylightUI.Motion.Shown(v), "again: it closes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Other addons' bag marks. A plugin written for Baganator's bags draws on
-- Daylight UI's slots through the same calls (Plugins.lua).
local function upArrow(rule)
    return function(button)
        local m = CreateFrame("Frame", nil, button)
        m:SetSize(10, 10)
        return m
    end, function(_, d) return rule(d) end
end

T.test("bags: a Baganator corner widget shows on Daylight UI's slots, in its corner", function()
    local ns = login()
    T.truthy(Baganator and Baganator.API and Baganator.API.RegisterCornerWidget, "Baganator's plugin calls are there while Baganator is off")
    local want = "|Hitem:1|h"
    local seen
    local init, update = upArrow(function(d) if d.itemLink == "|Hitem:1|h" then seen = d end; return d.itemLink == want end)
    Baganator.API.RegisterCornerWidget("Up arrows", "up", update, init, { corner = "top_left", priority = 1 })
    T.truthy(Baganator.API.IsCornerWidgetActive("up"), "listed as in use")
    open(ns)
    stub.RunTimers()
    local P, B = ns.Plugins, ns.Bags
    local w1, w2 = P.Widget(B.buttons[0][1], "up"), P.Widget(B.buttons[0][2], "up")
    T.truthy(w1 and w1:IsShown(), "the item the plugin picks gets its mark")
    T.truthy(w2 and not w2:IsShown(), "the others don't")
    T.eq((w1:GetPoint(1)), "TOPLEFT", "in the corner it asked for")
    T.eq(seen.bagID, 0, "the plugin is told the bag"); T.eq(seen.slotID, 1, "and slot")
    T.truthy(seen.itemID ~= nil or seen.itemLink ~= nil, "and the item")
    T.falsy(P.Widget(B.buttons[0][3], "up") and P.Widget(B.buttons[0][3], "up"):IsShown(), "an empty slot: no mark")
    want = "|Hitem:2|h"
    Baganator.API.RequestItemButtonsRefresh()
    stub.RunTimers()
    T.falsy(w1:IsShown(), "a refresh asked by the plugin: the old mark goes")
    T.truthy(w2:IsShown(), "and the new one shows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.Baganator = nil
end)

T.test("bags: Baganator plugin calls Daylight UI doesn't use don't break, nor a plugin's own error", function()
    local ns = login()
    Baganator.API.RegisterJunkPlugin("Junk", "junk", function() return false end)
    Baganator.API.RegisterItemSetSource("Sets", "sets", function() end)
    local init, update = upArrow(function() error("plugin broke") end)
    Baganator.API.RegisterCornerWidget("Broken", "broken", update, init)
    open(ns)
    stub.RunTimers()
    T.eq(#stub.errors, 1, "the plugin's error is reported once, not once per slot")
    T.truthy(ns.Bags.buttons[0][1].calls.SetItemButtonTexture, "the slots still fill")
    _G.Baganator = nil
end)

T.test("bags: an upgrade plugin answers the 'upgrade' search", function()
    local ns = login()
    Baganator.API.RegisterUpgradePlugin("Up", "up", function(link) return link == "|Hitem:2|h" end)
    T.truthy(Baganator.API.IsUpgradePluginActive("up"))
    local f = open(ns)
    f.search:SetText("upgrade")
    f.search:GetScript("OnTextChanged")(f.search, true)
    local B = ns.Bags
    T.eq(B.buttons[0][2].calls.SetMatchesSearch[1], true, "the upgrade stands out")
    T.eq(B.buttons[0][1].calls.SetMatchesSearch[1], false, "the rest dim")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.Baganator = nil
end)

T.test("bags: with Baganator itself on, its own calls are left to it", function()
    _G.Baganator = nil
    stub.Load({ bags = true, before = function()
        setup()
        stub.addonState.Baganator = { ["*"] = true }
    end })
    T.eq(_G.Baganator, nil, "no stand-in made: Baganator answers its own calls")
end)

-- DaylightUI.API 1.3: bag slots are frames plugins paint ("bagslot", unit
-- "bag:slot"; icon, count, border), painted after every fill of the slot.
T.test("bags: plugins paint the slots after each fill, with the item", function()
    local ns = login()
    local API = DaylightUI.API
    local got = {}
    API.For("Neon").Paint("bagslot", function(btn, parts, info)
        if info and info.bag == 0 and info.slot == 1 then got[#got + 1] = { btn, parts, info } end
    end)
    open(ns)
    T.truthy(#got >= 1, "the first slot painted")
    local last = got[#got]
    local btn = ns.Bags.buttons[0][1]
    T.eq(last[1], btn)
    T.eq(last[3].link, "|Hitem:1|h")
    T.eq(last[3].quality, 3)
    T.truthy(last[2].icon, "its icon")
    local found
    for f, unit in API.Frames("bagslot") do if f == btn then found = unit end end
    T.eq(found, "0:1")
    local n = #got
    world.items[0][1].stackCount = 4
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.truthy(#got > n, "painted again after the bag changed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's controller window list, enough to focus the bag (FrameControlsManager).
local function padOn()
    local m = { shownFrames = {} }
    function m:GetActiveFrame() return self.focused end
    function m:FrameShown(frame)
        table.insert(self.shownFrames, frame)
        self.focused = frame
        if frame.FocusGamepad then frame:FocusGamepad() end
    end
    function m:FrameHidden(frame)
        for i, f in ipairs(self.shownFrames) do if f == frame then table.remove(self.shownFrames, i) end end
        if self.focused == frame then self.focused = nil; if frame.UnfocusGamepad then frame:UnfocusGamepad() end end
    end
    _G.GamepadMode = { FrameControlsManager = m }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
end

T.test("bags on a controller: X does an item's right click through a secure key, Y its more actions", function()
    local ns = login()
    world.items[0][1].itemID = 1
    world.items[0][2].itemID = 2
    C_Item.GetItemSpell = function(id) if id == 1 then return "Drink", 430 end end
    C_Item.IsEquippableItem = function() return false end
    padOn()
    local B = ns.Bags
    local at = B.buttons[0][1]
    _G.SmartNavigation = { GetCurrentButton = function() return at end }
    local f = open(ns)
    stub.RunTimers()
    local o = stub.overrides.PAD3
    T.truthy(o, "X is bound on a usable item")
    T.eq(o.button, "RightButton")
    local s = _G[o.click]
    T.eq(s:GetAttribute("type"), "click")
    T.eq(s:GetAttribute("clickbutton"), at)
    local said = {}
    for _, row in ipairs(DaylightUI.Pad.HintList(f)) do said[#said + 1] = row[2] end
    said = table.concat(said, "|")
    T.truthy(said:find(CONTEXT_ACTION_LABEL_USE or "Use", 1, true), said)
    at = B.buttons[0][2]
    stub.RunTimers()
    T.eq(stub.overrides.PAD3, nil, "an item a right click does nothing with leaves X alone")
    T.truthy(stub.overrides.PAD4, "Y still has more actions")
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- The game's delete question can't be asked from addon code: it opens inside
-- the call and carries the addon's taint into the controller (tests/test_guards).
-- So the menu row itself asks ("Click again"), and only then is it deleted.
T.test("bags on a controller: Destroy asks in the menu first, then deletes that slot", function()
    local ns = login()
    world.items[0][2].itemID = 2
    local deleted
    local made = _G.ItemLocation
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    C_Item.GetItemGUID = function(loc) return "Item-" .. loc.bag .. "-" .. loc.slot end
    C_Item.DeleteItem = function(guid) deleted = guid end
    local W = DaylightUI.Widgets
    local realOpen, seen = W.OpenMenu, nil
    W.OpenMenu = function(owner, keys, values, current, onPick, width, opts)
        seen = { keys = keys, onPick = onPick, opts = opts }
    end
    ns.Window.PadMore(ns.Bags.buttons[0][2])
    W.OpenMenu = realOpen
    T.truthy(seen, "Y opens the more-actions menu")
    T.truthy(seen.opts and seen.opts.confirm and seen.opts.confirm.destroy, "Destroy asks again before it goes through")
    seen.onPick("destroy")
    T.eq(deleted, "Item-0-2")
    deleted = nil
    ns.Window.PadDestroy(ns.Bags.buttons[0][3])
    T.eq(deleted, nil, "an empty slot has nothing to destroy")
    _G.ItemLocation = made
end)

local function headingsShown(f)
    local out = {}
    for _, h in ipairs(f.headings or {}) do if h:IsShown() and h.key then out[h.key] = true end end
    return out
end

T.test("bags: a chip shows only its groups in the categories view", function()
    local ns, f = catLogin()
    local W = ns.Window
    local all = headingsShown(f)
    T.truthy(all.junk and all.weapon and all.consumable, "everything with no chip")
    W.PickChip(f, "junk")
    stub.RunTimers()
    local only = headingsShown(f)
    T.truthy(only.junk, "the Junk heading stays")
    T.eq(only.weapon, nil, "other headings go")
    T.eq(only.consumable, nil)
    local weapon = ns.Bags.buttons[0][1]
    T.truthy(not weapon:IsShown() or (f.fading and f.fading[weapon]), "the rare weapon's slot hides (or fades out)")
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, 1) end
    end
    T.eq(weapon:IsShown(), false, "once the fade ends it is hidden and takes no clicks")
    T.eq(ns.Bags.buttons[0][2]:IsShown(), true, "the gray one shows")
    W.PickChip(f, "all")
    stub.RunTimers()
    T.truthy(headingsShown(f).weapon, "All brings everything back")
end)

T.test("bags: a chip dims the rest in the grid view", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    local f = open(ns)
    ns.FillAll()
    local B = ns.Bags
    local seen = {}
    for _, b in ipairs({ B.buttons[0][1], B.buttons[0][2] }) do
        local set = b.SetMatchesSearch
        b.SetMatchesSearch = function(self, v) seen[self] = v; if set then set(self, v) end end
    end
    ns.Window.PickChip(f, "junk")
    T.eq(seen[B.buttons[0][2]], true, "the gray item stays lit")
    T.eq(seen[B.buttons[0][1]], false, "the weapon dims")
    f.match = function() return false end
    ns.Window.MatchAll(f)
    T.eq(seen[B.buttons[0][2]], false, "a search on top narrows further")
    f.match = nil
    -- A refill (loot, a bag update) keeps the chip's dimming.
    ns.Window.MatchAll(f)
    world.items[0][1].hyperlink = "|Hitem:1|h"
    ns.Items.Fill(B.buttons[0][1])
    T.eq(seen[B.buttons[0][1]], false, "a refilled non-junk slot stays dimmed")
end)

T.test("bags: a chip picked in the grid view leaves nothing dimmed after closing", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    local f = open(ns)
    ns.FillAll()
    local weapon = ns.Bags.buttons[0][1]
    local lit
    local set = weapon.SetMatchesSearch
    weapon.SetMatchesSearch = function(self, v) lit = v; if set then set(self, v) end end
    ns.Window.PickChip(f, "junk")
    T.eq(lit, false, "the weapon dims under Junk")
    f:Hide()
    stub.RunTimers()
    f:Show()
    stub.RunTimers()
    T.eq(lit, true, "the weapon is lit again on the next open")
end)

-- New loot sits in Recent, but a chip still judges it by the group it would
-- otherwise fall in, so a fresh weapon shows under Gear.
T.test("bags: new loot stays in view under its chip", function()
    local ns, f = catLogin()
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and (slot == 1 or slot == 8) end }
    ns.Relayout()
    local weapon, bread = ns.Bags.buttons[0][1], ns.Bags.buttons[0][8]
    T.eq(groupOf(ns, weapon), "recent")
    T.eq(groupOf(ns, bread), "recent")
    ns.Window.PickChip(f, "gear")
    stub.RunTimers()
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, 1) end
    end
    T.truthy(headingsShown(f).recent, "Recent stays with a new weapon in it")
    T.eq(weapon:IsShown(), true, "the new weapon shows under Gear")
    T.eq(bread:IsShown(), false, "new food doesn't")
    _G.C_NewItems = nil
end)

T.test("bags: new loot stays lit under its chip in the grid view", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and (slot == 1 or slot == 8) end }
    local f = open(ns)
    ns.FillAll()
    local seen = {}
    local weapon, bread = ns.Bags.buttons[0][1], ns.Bags.buttons[0][8]
    for _, b in ipairs({ weapon, bread }) do
        local set = b.SetMatchesSearch
        b.SetMatchesSearch = function(self, v) seen[self] = v; if set then set(self, v) end end
    end
    ns.Window.PickChip(f, "gear")
    T.eq(seen[weapon], true, "the new weapon stays lit")
    T.eq(seen[bread], false, "new food dims")
    _G.C_NewItems = nil
end)

T.test("bags: the chip row wraps when the grid is narrower than the chips", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    DaylightUI:Set("Bags", "columns", 3)
    local f = open(ns)
    ns.Relayout()
    local first, last = f.chips[1], f.chips[#f.chips]
    local _, _, _, _, y1 = first:GetPoint(1)
    local _, _, _, _, y2 = last:GetPoint(1)
    T.truthy(y2 < y1, "the last chip is on a second line")
    DaylightUI:Set("Bags", "columns", 14)
    ns.Relayout()
    _, _, _, _, y2 = last:GetPoint(1)
    T.eq(y2, y1, "one line when the grid is wide")
end)

T.test("bags: chips reset when the bag closes, and a chip in combat lays out nothing protected", function()
    local ns, f = catLogin()
    ns.Window.PickChip(f, "gear")
    T.eq(f.chip, "gear")
    f:Hide()
    stub.RunTimers()
    T.eq(f.chip, nil, "closing clears the chip")
    f:Show()
    stub.RunTimers()
    local back = headingsShown(f)
    T.truthy(back.weapon and back.junk and back.consumable, "every group is back on the next open")
    stub.EnterCombat()
    ns.Window.PickChip(f, "quest")
    T.eq(#stub.errors, 0)
    T.eq(f.chip, "quest", "the pick is kept in combat")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(headingsShown(f).weapon, nil, "the filter applies once combat ends")
end)

T.test("bags: a heading's rule fades out to the right, softer under the Classic look", function()
    local ns, f = catLogin()
    local function rule()
        for _, x in ipairs(f.headings) do if x:IsShown() then return x.rule end end
    end
    local g = rule().__gradient
    T.truthy(g, "drawn as a gradient")
    T.eq(g[1], "HORIZONTAL")
    T.eq(g[2].a, ns.Layout.RULE_ALPHA.daylight, "starts at the Daylight strength")
    T.eq(g[3].a, 0, "and fades to nothing")
    -- The Classic look may not be in this build; check it only when it is.
    if DaylightUI.Style.LOOKS and DaylightUI.Style.LOOKS.classic then
        DaylightUI:Set("general", "look", "classic")
        stub.RunTimers()
        ns.Relayout()
        T.eq(rule().__gradient[2].a, ns.Layout.RULE_ALPHA.classic, "softer on the Classic gold")
        DaylightUI:Set("general", "look", nil)
        stub.RunTimers()
    end
end)

T.test("bags: the new-item glow never spills into the next slot", function()
    local ns = login()
    open(ns)
    local Items, B = ns.Items, ns.Bags
    local function glowAt(spacing)
        DaylightUI:Set("Bags", "spacing", spacing)
        stub.RunTimers()
        local p = Items.Parts(B.buttons[0][1])
        return p.newGlow:GetWidth(), p.newDot:GetWidth()
    end
    local glow, dot = glowAt(7)
    T.truthy(glow > dot, "a glow around the dot at the default spacing")
    T.truthy(glow <= (7 - 1) * 2, "reaching at most a pixel past the gap")
    glow, dot = glowAt(2)
    T.eq(glow, dot, "no glow at all when the slots nearly touch")
    DaylightUI:Set("Bags", "spacing", nil)
    stub.RunTimers()
end)

T.test("bags: the tour names the Alts tab only while it's there", function()
    local ns = login()
    open(ns)
    local stop
    for _, d in ipairs(DaylightUI.Tour.stops) do if d.id == "bags" then stop = d end end
    T.truthy(stop, "the bags tour stop")
    T.truthy(stop.text():find("Alts", 1, true), "Alts named while the viewer is on")
    DaylightUI:Set("Bags", "viewer.enabled", false)
    stub.RunTimers()
    T.falsy(stop.text():find("Alts", 1, true), "not named once the tab is gone")
    DaylightUI:Set("Bags", "viewer.enabled", true)
    stub.RunTimers()
end)
