local stub = require("stub")

-- What the game's own bag window does that Daylight UI's bag must do too: the
-- junk coin at a vendor, the bag strip's lock and cursor light, the tracked
-- currencies' clicks, the bags the game's Sell Junk leaves alone, and the
-- controller's B and X (Mainline ContainerFrame.lua, MainMenuBarBagButtons,
-- Camelot Blizzard_TokenUI).

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
        GetContainerItemCooldown = function(bag, slot)
            local c = world.cooldowns and world.cooldowns[bag .. ":" .. slot]
            if c then return c[1], c[2], c[3] end
            return 0, 0, 1
        end,
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
    -- Called from addon code, OpenAllBags runs all of the game's bag code tainted
    -- (ContainerFrame_GenerateFrame: its windows, settings manager and anchors), and
    -- the game later refused SetPreferredGamepadInteractTarget. Counted per call.
    world.openAll = 0
    _G.OpenAllBags = function(frame)
        world.openAll = world.openAll + 1
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
            -- The quality frame sits centered on the button (ItemButtonTemplate.xml).
            f.IconBorder = f:CreateTexture()
            f.IconBorder:SetPoint("CENTER")
            -- The template's own SetAlpha (ItemButtonMixin) passes the alpha on to its
            -- icon, quality frame and count, never the button itself.
            function f:SetAlpha(a)
                self.icon:SetAlpha(a); self.IconBorder:SetAlpha(a); self.Count:SetAlpha(a)
            end
            f.JunkIcon = f:CreateTexture()
            f.UpgradeIcon = f:CreateTexture()
            f.calls = {}
            for _, m in ipairs({ "SetHasItem", "SetItemButtonTexture", "UpdateExtended", "UpdateQuestItem", "UpdateNewItem",
                                 "UpdateJunkItem", "UpdateItemContextMatching", "UpdateCooldown", "SetReadable",
                                 "CheckUpdateTooltip", "SetMatchesSearch" }) do
                f[m] = function(self, ...) self.calls[m] = { ... } end
            end
            -- The game's SetItemButtonTexture puts the whole picture back on every
            -- call (ItemButtonTemplate.lua: SetTexCoord(0, 1, 0, 1)).
            function f:SetItemButtonTexture(...)
                self.calls.SetItemButtonTexture = { ... }
                self.icon:SetTexCoord(0, 1, 0, 1)
            end
            -- The game's UpdateCooldown colors the icon on every call: white, or dim
            -- gray while the item can't be used yet (ContainerFrame.lua, SetItemButtonTextureVertexColor).
            function f:UpdateCooldown(...)
                self.calls.UpdateCooldown = { ... }
                self:SetHasItem(...)
                if ... then self.icon:SetVertexColor(1, 1, 1) end
            end
            -- The template's key (ContainerFrame.xml) and the two fields the game's
            -- controller code reads straight off a bag button (ContainerFrame.lua:
            -- SetHasItem, SetReadable, and UpdateCooldown calls SetHasItem). A field
            -- keeps the taint of whoever ran the method that wrote it.
            f.buttonContext = "ButtonContext_ContainerFrameItemButton"
            function f:SetHasItem(has)
                self.calls.SetHasItem = { has }
                self.hasItem = has and 1 or nil
                if (stub.inSecure or 0) == 0 then stub.Mark(self, "hasItem", "DaylightUI_Bags") end
            end
            function f:SetReadable(readable)
                self.calls.SetReadable = { readable }
                self.readable = readable
                if (stub.inSecure or 0) == 0 then stub.Mark(self, "readable", "DaylightUI_Bags") end
            end
            function f:HasItem() return self.hasItem end
            function f:IsReadable() return self.readable end
            function f:GetBagID() return self.bagID or self:GetParent():GetID() end
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
    -- Cooldown.lua: a running cooldown is set, anything else cleared.
    _G.CooldownFrame_Set = function(cd, start, duration, enable)
        cd.set = (enable and enable ~= 0 and start > 0 and duration > 0) and { start, duration } or nil
    end
    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    function GameTooltip:SetOwner() end
    function GameTooltip:SetInventoryItem() return true end
end

-- The plain grid unless categories are asked for. Most of these tests are about
-- the grid, and the categories view has its own.
-- The game stops at logout. A test that plays on afterwards puts back the
-- defaults the logout stripped from the saved profile.
local function carryOn() DaylightUI.DB.Fill(DaylightUI.DB.Active()) end

local function login(opts)
    stub.Load({ bags = true, before = function() setup(opts) end })
    stub.RunTimers()
    DaylightUI:Set("Bags", "view", opts and opts.view or "grid")
    stub.RunTimers()
    return stub.bags
end

local function open(ns)
    OpenAllBags()
    stub.RunTimers()
    return ns.window
end

-- The game's UpdateJunkItem (ContainerFrame.lua): the coin goes on a gray item
-- with a price only while a vendor's window is open.
local function gameJunk(ns)
    for _, s in ipairs(ns.Bags.Slots()) do
        local b = s.button
        function b:UpdateJunkItem(quality, noValue)
            self.calls.UpdateJunkItem = { quality, noValue }
            local atVendor = _G.MerchantFrame ~= nil and MerchantFrame:IsShown()
            self.JunkIcon:SetShown(quality == 0 and not noValue and atVendor)
        end
    end
end

local function vendor(shown)
    _G.MerchantFrame = _G.MerchantFrame or CreateFrame("Frame", "MerchantFrame", UIParent)
    MerchantFrame:SetShown(shown)
    stub.FireEvent(shown and "MERCHANT_SHOW" or "MERCHANT_CLOSED")
    stub.RunTimers()
end

T.test("bags: the junk coin comes with a vendor and goes with it, bag open or not", function()
    local ns = login()
    DaylightUI:Set("Bags", "showJunk", true)
    gameJunk(ns)
    vendor(false)
    local f = open(ns)
    ns.FillAll(); stub.RunTimers()
    local gray = ns.Bags.Button(0, 2)
    T.falsy(gray.JunkIcon:IsShown(), "no vendor: no coin")
    -- The bag already open when the vendor's window comes up: nothing refills.
    vendor(true)
    T.truthy(gray.JunkIcon:IsShown(), "at the vendor: the coin, as on the game's bag")
    T.falsy(ns.Bags.Button(0, 1).JunkIcon:IsShown(), "only on the gray item")
    vendor(false)
    T.falsy(gray.JunkIcon:IsShown(), "gone again once the vendor closes")
    -- Shut while the vendor opens, then opened by it.
    f:Hide(); stub.RunTimers()
    vendor(true)
    OpenAllBags(MerchantFrame); stub.RunTimers()
    T.truthy(gray.JunkIcon:IsShown(), "opened by the vendor: the coin is there")
    vendor(false)
    _G.MerchantFrame = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a bag picked up from the strip goes gray, and a bag on the cursor lights the slots it fits", function()
    local locked, fits = {}, {}
    _G.GetInventoryItemTexture = function(_, inv) return (inv == 31 or inv == 32) and 777 or nil end
    _G.GetInventoryItemQuality = function() return 1 end
    _G.IsInventoryItemLocked = function(inv) return locked[inv] == true end
    _G.C_PaperDollInfo = { CursorCanGoInSlot = function(inv) return fits[inv] == true end }
    local ns = login()
    open(ns)
    DaylightUI:Set("Bags", "showSlots", true); stub.RunTimers()
    local one, two = ns.Slots.strip.slots[1], ns.Slots.strip.slots[2]
    T.eq(one.bag, 1); T.eq(two.bag, 2)
    local lit = {}
    for _, b in ipairs({ one, two }) do
        function b:LockHighlight() lit[self] = true end
        function b:UnlockHighlight() lit[self] = nil end
    end
    T.falsy(one.icon:IsDesaturated(), "in its slot: in color")
    -- The game's bag slot reads the lock on ITEM_LOCK_CHANGED with no slot
    -- (PaperDollItemSlotButton_OnEvent, Camelot PaperDollFrame.lua).
    locked[31] = true
    stub.FireEvent("ITEM_LOCK_CHANGED", 31)
    T.truthy(one.icon:IsDesaturated(), "on the cursor: gray, as the game's bag slot")
    T.falsy(two.icon:IsDesaturated(), "the other bag stays in color")
    locked[31] = nil
    stub.FireEvent("ITEM_LOCK_CHANGED", 31)
    T.falsy(one.icon:IsDesaturated(), "back in its slot: in color again")
    -- A bag on the cursor: the slots it can go in light up (CursorCanGoInSlot).
    fits[32] = true
    stub.FireEvent("CURSOR_CHANGED")
    T.truthy(lit[two], "the slot it fits lights")
    T.falsy(lit[one], "not the others")
    fits[32] = nil
    stub.FireEvent("CURSOR_CHANGED")
    T.falsy(lit[two], "the cursor let go: no light")
    _G.C_PaperDollInfo, _G.IsInventoryItemLocked = nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a tracked currency's click opens Currency; Shift links it while typing, else stops tracking it", function()
    local ns = login()
    local f = open(ns)
    local list = { { name = "Badge", quantity = 42, iconFileID = 999, currencyTypesID = 7 },
                   { name = "Mark", quantity = 3, iconFileID = 998, currencyTypesID = 8 } }
    local untracked, opened, linked
    _G.C_CurrencyInfo = {
        GetBackpackCurrencyInfo = function(i) return list[i] end,
        GetCurrencyLink = function(id) return "|Hcurrency:" .. id .. "|h[Badge]|h" end,
        SetCurrencyBackpackByID = function(id, on)
            untracked = id
            if not on then table.remove(list, 1) end
        end,
    }
    local mods, typing = {}, false
    local isMod, toggle, util = _G.IsModifiedClick, _G.ToggleCharacter, _G.ChatFrameUtil
    _G.IsModifiedClick = function(k) if k == nil then return next(mods) ~= nil end return mods[k] == true end
    _G.ToggleCharacter = function(page) opened = page end
    _G.ChatFrameUtil = { InsertLink = function(link) if typing then linked = link; return true end return false end }
    ns.Window.UpdateFooter(f)
    local badge = f.currencySlots[1]
    local click = badge:GetScript("OnClick")
    T.truthy(click, "it takes a click")
    -- A plain click: the currency page (CharacterFrame:ToggleTokenFrame in the game).
    click(badge, "LeftButton")
    T.eq(opened, "TokenFrame", "a click opens the Currency page")
    -- Shift while typing: the link goes in the chat box, nothing else.
    mods = { CHATLINK = true, TOKENWATCHTOGGLE = true }
    typing = true
    opened = nil
    click(badge, "LeftButton")
    T.eq(linked, "|Hcurrency:7|h[Badge]|h", "Shift while typing: its link in the chat box")
    T.isnil(untracked, "still tracked")
    T.isnil(opened)
    -- Shift with no chat box open: no longer shown in the bag.
    typing = false
    click(badge, "LeftButton")
    T.eq(untracked, 7, "Shift: stops tracking it, as TOKENWATCHTOGGLE does")
    T.isnil(opened)
    T.eq(f.currencySlots[1].count:GetText(), "3", "the footer shows what's still tracked at once")
    T.falsy(f.currencySlots[2]:IsShown())
    -- Its tooltip says how, as the game's does.
    local lines = {}
    local tip = GameTooltip
    _G.GameTooltip = { Hide = function() end, SetOwner = function() end, Show = function() end,
        SetBackpackToken = function() lines[#lines + 1] = "token" end, SetText = function(_, t) lines[#lines + 1] = t end,
        AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function(_, t) lines[#lines + 1] = t end,
        GetOwner = function() end, IsShown = function() return false end }
    local mark = f.currencySlots[1]
    mark:GetScript("OnEnter")(mark)
    mark:GetScript("OnLeave")(mark)
    _G.GameTooltip = tip
    local said = table.concat(lines, " / ")
    T.truthy(said:find("token", 1, true), "the currency's own tooltip")
    T.truthy(said:find("Shift-click", 1, true), "then the Shift-click hint: " .. said)
    _G.IsModifiedClick, _G.ToggleCharacter, _G.ChatFrameUtil = isMod, toggle, util
    _G.C_CurrencyInfo = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the tracked currencies follow a change made on the Currency page while the bag is open", function()
    local ns = login()
    local f = open(ns)
    local list = { { name = "Badge", quantity = 42, iconFileID = 999, currencyTypesID = 7 } }
    _G.C_CurrencyInfo = { GetBackpackCurrencyInfo = function(i) return list[i] end }
    ns.Window.UpdateFooter(f)
    T.truthy(f.currencySlots[1]:IsShown())
    -- The game's own page updates the backpack's list right after its call
    -- (Camelot Blizzard_TokenUI.lua): no event comes for it.
    list[2] = { name = "Mark", quantity = 3, iconFileID = 998, currencyTypesID = 8 }
    DaylightUI.Fire("BackpackCurrencyChanged")
    stub.RunTimers()
    T.truthy(f.currencySlots[2] and f.currencySlots[2]:IsShown(), "the newly tracked one shows at once")
    _G.C_CurrencyInfo = nil
end)

T.test("bags: Sell junk leaves the bags the game's Sell Junk is told to leave alone", function()
    local ns = login()
    local flags, backpackOff = {}, false
    Enum.BagSlotFlags = Enum.BagSlotFlags or { DisableAutoSort = 1, ClassEquipment = 2, ExcludeJunkSell = 64 }
    C_Container.GetBagSlotFlag = function(bag, flag) return flags[bag .. ":" .. flag] == true end
    C_Container.GetBackpackSellJunkDisabled = function() return backpackOff end
    world.items[0][2].itemID = 2
    world.items[1][3] = { iconFileID = 103, stackCount = 1, quality = 0, hyperlink = "|Hitem:22|h", itemID = 22 }
    C_Item.GetItemInfo = function(link) return "name", link, 0, 1, 1, "", "", 1, "", 1, 5 end
    open(ns)
    ns.FillAll(); stub.RunTimers()
    local function where(list)
        local out = {}
        for _, e in ipairs(list) do out[#out + 1] = e.bag .. ":" .. e.slot end
        table.sort(out)
        return table.concat(out, ",")
    end
    T.eq(where(ns.Junk.Items()), "0:2,1:3", "both gray items, nothing flagged")
    flags["1:" .. Enum.BagSlotFlags.ExcludeJunkSell] = true
    T.eq(where(ns.Junk.Items()), "0:2", "bag 1 is left alone")
    T.eq(where((ns.Junk.Grays())), "0:2", "the game's sale wouldn't take it either")
    backpackOff = true
    T.eq(where(ns.Junk.Items()), "", "nor the backpack once it's told to")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: on a controller B puts a held item back before closing, and X says nothing on the buyback tab", function()
    local ns = login()
    local f = open(ns)
    local back
    for _, e in ipairs(f.padKeys or {}) do if e.key == "B" then back = e end end
    T.truthy(back and back.follow, "the bag has its own B, while it acts")
    if back then
        local held = true
        local has, clear = _G.CursorHasItem, _G.ClearCursor
        _G.CursorHasItem = function() return held end
        _G.ClearCursor = function() held = false end
        T.truthy(back.when(nil), "an item held: B acts")
        back.run(nil)
        T.falsy(held, "B put it back (Gamepad_DoBackAction)")
        T.falsy(back.when(nil), "nothing held: B is the window's own Back again")
        _G.CursorHasItem, _G.ClearCursor = has, clear
    end
    -- The vendor's buyback tab: the game's right click does nothing there, and
    -- its footer offers nothing (CanSellItems, Gamepad_IsItemUseBlocked).
    _G.MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
    MerchantFrame:Show()
    world.items[0][1].itemID = 1
    local slot = ns.Bags.Button(0, 1)
    MerchantFrame.selectedTab = 1
    T.eq(ns.Window.PadUseLabel(f, slot), CONTEXT_ACTION_LABEL_SELL or "Sell", "the buy tab: Sell")
    MerchantFrame.selectedTab = 2
    T.isnil(ns.Window.PadUseLabel(f, slot), "the buyback tab: X says nothing")
    MerchantFrame:Hide()
    _G.MerchantFrame = nil
end)

-- The game's bag menu (Mainline ContainerFrame.lua, ContainerFrame_AddButtons_BagFilters
-- and _BagCleanup): per bag, what it holds (a plain bag only) and whether Clean Up
-- and Sell Junk skip it, all the game's own flags.
local function flagWorld()
    local w = { flags = {}, cleanBackpack = false, sellBackpack = false }
    Enum.BagSlotFlags = { DisableAutoSort = 1, ClassEquipment = 2, ClassConsumables = 4, ClassProfessionGoods = 8,
        ClassJunk = 16, ClassQuestItems = 32, ExcludeJunkSell = 64, ClassReagents = 128 }
    C_Container.GetBagSlotFlag = function(bag, flag) return w.flags[bag .. ":" .. flag] == true end
    C_Container.SetBagSlotFlag = function(bag, flag, on) w.flags[bag .. ":" .. flag] = on end
    C_Container.GetBackpackAutosortDisabled = function() return w.cleanBackpack end
    C_Container.SetBackpackAutosortDisabled = function(on) w.cleanBackpack = on end
    C_Container.GetBackpackSellJunkDisabled = function() return w.sellBackpack end
    C_Container.SetBackpackSellJunkDisabled = function(on) w.sellBackpack = on end
    _G.BAG_FILTER_EQUIPMENT, _G.BAG_FILTER_JUNK = "Equipment", "Junk"
    _G.BAG_FILTER_ASSIGNED_TO = "Assigned to: %s"
    return w
end

local function catchMenu()
    local menu = {}
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(owner, keys, values, current, onPick, width, opts)
        menu.owner, menu.keys, menu.values, menu.pick, menu.opts = owner, keys, values, onPick, opts
    end
    return menu, function() DaylightUI.Widgets.OpenMenu = openMenu end
end

T.test("bags: a strip bag's right-click sets what it holds and what skips it; Clean Up's lists every bag", function()
    local ns = login()
    local w = flagWorld()   -- after login, which makes the bag world's C_Container
    open(ns)
    DaylightUI:Set("Bags", "showSlots", true); stub.RunTimers()
    local menu, done = catchMenu()
    local bag1 = ns.Slots.strip.slots[1]
    T.eq(bag1.bag, 1)
    bag1:GetScript("OnClick")(bag1, "RightButton")
    T.eq(menu.owner, bag1, "a menu opens on the bag")
    T.deq(menu.keys, { "holds", "ClassEquipment", "ClassConsumables", "ClassProfessionGoods", "ClassJunk",
        "ClassQuestItems", "ClassReagents", "skips", "clean", "sell" }, "what it holds, then what skips it")
    T.truthy(menu.opts.titles.holds and menu.opts.titles.skips and menu.opts.keepOpen, "switches under two headings")
    T.truthy(menu.values.holds:find("holds", 1, true), menu.values.holds)
    T.eq(menu.values.ClassEquipment, "Equipment", "the game's own word")
    T.falsy(menu.opts.checked("ClassEquipment"))
    menu.pick("ClassEquipment")
    T.truthy(w.flags["1:2"], "the game's own flag")
    T.truthy(menu.opts.checked("ClassEquipment"))
    menu.pick("sell")
    T.truthy(w.flags["1:64"], "Sell junk leaves it alone now")
    T.truthy(ns.Junk.BagSkipped(1))
    menu.pick("clean")
    T.truthy(ns.Keep.Skipped(1), "and Clean Up")
    -- Its tooltip names what it holds, as the game's bag slot does.
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
    T.truthy(said:find("Assigned to: Equipment", 1, true), said)
    -- A profession bag holds what it holds: only what skips it (the game's rule).
    local prof = ns.Slots.strip.slots[5]
    T.eq(prof.bag, 5)
    prof:GetScript("OnClick")(prof, "RightButton")
    T.deq(menu.keys, { "skips", "clean", "sell" }, "a profession bag: no holds rows")
    -- An empty bag slot has nothing to set.
    menu.keys = nil
    local empty = ns.Slots.strip.slots[2]
    empty:GetScript("OnClick")(empty, "RightButton")
    T.isnil(menu.keys, "no bag: no menu")
    -- The Clean Up button: every bag for Clean Up, then for Sell junk, backpack first.
    local sort = ns.window.sort
    sort:GetScript("OnClick")(sort, "RightButton")
    T.eq(menu.owner, sort)
    T.deq(menu.keys, { "head", "bag0", "bag1", "bag5", "sellhead", "sell0", "sell1", "sell5" })
    T.truthy(menu.opts.checked("sell1"), "bag 1 is ticked there too")
    menu.pick("sell0")
    T.truthy(w.sellBackpack, "the backpack's own switch")
    T.truthy(ns.Junk.BagSkipped(0))
    done()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's backpack money: a click asks how much to pick up, then puts it on the
-- cursor for a trade or a letter (Mainline MoneyInputFrame.lua: MoneyInputFrame_OpenPopup,
-- MoneyInputFrame_PickupPlayerMoney). Daylight UI asks in its own box, never the
-- game's PICKUP_MONEY pop-up.
T.test("bags: a click on the bag's gold asks how much, over the money, and picks it up", function()
    local ns = login()
    local f = open(ns)
    local picked, errors = {}, {}
    _G.PickupPlayerMoney = function(copper) picked[#picked + 1] = copper end
    _G.GetMoney = function() return 200000 end
    local showError = DaylightUI.ShowError
    DaylightUI.ShowError = function(text) errors[#errors + 1] = text end
    local W = DaylightUI.Widgets
    T.truthy(f.moneyButton, "the money takes a click")
    f.moneyButton:GetScript("OnClick")(f.moneyButton, "LeftButton")
    stub.RunTimers()
    local spec = W.Asking()
    T.truthy(spec and spec.money, "Daylight UI's own box, asking for an amount")
    local box = _G.DaylightUIAsk
    T.truthy(box.coins and box.coins:IsShown(), "the mail window's gold, silver and copper boxes")
    -- Over the money, as the mock-up.
    local _, rel = box:GetPoint(1)
    T.eq(rel, f.money, "placed over the money")
    box.coins.gold:SetText("12")
    box.coins.silver:SetText("50")
    W.Answer(true)
    T.deq(picked, { 125000 }, "12 gold 50 silver on the cursor")
    -- More than you have: the game's error, nothing picked up.
    f.moneyButton:GetScript("OnClick")(f.moneyButton, "LeftButton")
    stub.RunTimers()
    box.coins.gold:SetText("30")
    W.Answer(true)
    T.eq(#picked, 1, "nothing more picked up")
    T.eq(#errors, 1, "said why")
    -- Cancel picks up nothing.
    f.moneyButton:GetScript("OnClick")(f.moneyButton, "LeftButton")
    stub.RunTimers()
    box.coins.gold:SetText("1")
    W.Answer(false)
    T.eq(#picked, 1, "cancelled: nothing")
    T.isnil(W.Asking())
    DaylightUI.ShowError = showError
    _G.PickupPlayerMoney = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
