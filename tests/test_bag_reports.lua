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
            -- The store glow (Interface\Store\store-item-highlight, a soft blue
            -- square): ContainerFrame.xml gives it no hidden flag, so it shows from
            -- the start, and UpdateNewItem shows it instead of the new-item glow
            -- while C_Container.IsBattlePayItem says so.
            f.BattlepayItemTexture = f:CreateTexture()
            f.BattlepayItemTexture:SetSize(64, 64)
            local rec = f.UpdateNewItem
            f.UpdateNewItem = function(self, ...)
                rec(self, ...)
                local key = self:GetBagID() .. ":" .. self:GetID()
                if world.battlepay and world.battlepay[key] then
                    self.NewItemTexture:Hide(); self.BattlepayItemTexture:Show()
                else
                    self.BattlepayItemTexture:Hide(); self.NewItemTexture:Show()
                end
                self.flash:Show()
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


-- Ticket: a quest item that can also be worn (a monogrammed sash from an elite)
-- was equipped by a right click in the bag instead of starting its quest. The
-- game's own right click is UseContainerItem, which starts the quest. With the
-- controller UI on, the mouse's right click and X go through a secure button;
-- its "item" action equips anything wearable by name first (SECURE_ACTIONS.item),
-- so the quest never started. Both must use the slot as the game's click does.
local function sashWorld()
    world.items[0][1] = { iconFileID = 133693, stackCount = 1, quality = 1, hyperlink = "|Hitem:16784|h", itemID = 16784,
                          isBound = true }
    C_Container.GetContainerItemLink = function(bag, slot)
        local info = world.items[bag] and world.items[bag][slot]
        return info and info.hyperlink
    end
    C_Container.GetContainerItemQuestInfo = function(bag, slot)
        if bag == 0 and slot == 1 then return { isQuestItem = true, questID = 800, isActive = false } end
        return {}
    end
    local did = {}
    C_Container.UseContainerItem = function(bag, slot) did[#did + 1] = "use " .. bag .. " " .. slot end
    C_Item.IsEquippableItem = function(item) return item == "|Hitem:16784|h" or item == 16784 end
    C_Item.IsEquippedItem = function() return false end
    C_Item.EquipItemByName = function(item) did[#did + 1] = "equip " .. tostring(item) end
    C_Item.GetItemSpell = function() return nil end
    return did
end

T.test("bags on a controller: a right-click on a wearable quest starter uses it, as the game's click does", function()
    local ns = login()
    local did = sashWorld()
    padOn()
    open(ns)
    local slotButton = ns.Bags.buttons[0][1]
    slotButton:GetScript("OnEnter")(slotButton)
    local useButton = _G.DaylightUIBagUse
    T.truthy(useButton and useButton:IsShown(), "the secure use button is on the slot")
    stub.SecureClick(useButton, "RightButton", true)
    stub.SecureClick(useButton, "RightButton", false)
    T.deq(did, { "use 0 1" }, "used by bag and slot: the quest starts, nothing is equipped")
    slotButton:GetScript("OnLeave")(slotButton)
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

T.test("bags on a controller: X on a wearable quest starter uses it, as the game's click does", function()
    local ns = login()
    local did = sashWorld()
    padOn()
    local f = open(ns)
    local slotButton = ns.Bags.buttons[0][1]
    -- X's secure twin, armed with what the bag hands it for this slot.
    local twin = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    twin:SetAttribute("useOnKeyDown", false)
    for k, v in pairs(ns.Window.PadUseSecure(f, slotButton)) do twin:SetAttribute(k, v) end
    stub.SecureClick(twin, "RightButton", false)
    T.deq(did, { "use 0 1" }, "used by bag and slot: the quest starts, nothing is equipped")
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- Ticket: with the controller UI on, X did nothing on an item that only starts a
-- quest (no use spell, can't be worn). The game's bag footer offers Use on it
-- (ContainerFrame.lua: useAction when C_Item.IsUsableItem), and a right click
-- starts the quest through UseContainerItem.
T.test("bags on a controller: X on an item that starts a quest uses it", function()
    local ns = login()
    local did = sashWorld()
    C_Item.IsEquippableItem = function() return false end
    padOn()
    local f = open(ns)
    local slotButton = ns.Bags.buttons[0][1]
    T.eq(ns.Window.PadUseLabel(f, slotButton), CONTEXT_ACTION_LABEL_USE or "Use", "X says Use, as the game's footer does")
    local action = ns.Window.PadUseSecure(f, slotButton)
    T.truthy(action, "X acts on it")
    local twin = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    twin:SetAttribute("useOnKeyDown", false)
    for k, v in pairs(action or {}) do twin:SetAttribute(k, v) end
    stub.SecureClick(twin, "RightButton", false)
    T.deq(did, { "use 0 1" }, "used by bag and slot: the quest starts")
    -- A quest it started already: nothing to use.
    C_Container.GetContainerItemQuestInfo = function() return { isQuestItem = true, questID = 800, isActive = true } end
    T.isnil(ns.Window.PadUseLabel(f, slotButton), "a quest already taken: X says nothing")
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- Ticket: a hunter on a controller found no Feed Pet in the bag's More actions,
-- which the game's own bag has for food the pet eats (ContainerFrame.lua
-- Gamepad_FeedToPet). Feeding casts a spell, so A on that row must go through a
-- secure button: the spell, then the food in that slot.
T.test("bags on a controller: Y's menu feeds the pet the food under the D-pad", function()
    local ns = login()
    world.items[0][1].itemID = 117   -- Tough Jerky
    local cast, used = {}, {}
    local hand = false
    local saved = { IsPlayerSpell = _G.IsPlayerSpell, UnitExists = _G.UnitExists, PetInfo = _G.C_PetInfo,
                    usable = C_Spell.IsSpellUsable, can = _G.SpellCanTargetItem }
    _G.IsPlayerSpell = function(id) return id == 6991 end
    _G.UnitExists = function(u) return u == "pet" or u == "player" end
    _G.C_PetInfo = { CanPetEatItem = function(id) return id == 117 end }
    C_Spell.IsSpellUsable = function(id) return id == 6991, false end
    stub.CastSpell = function(spell) cast[#cast + 1] = tonumber(spell); hand = true end
    _G.SpellCanTargetItem = function() return hand end
    C_Container.UseContainerItem = function(bag, slot) if hand then used[#used + 1] = bag .. ":" .. slot; hand = false end end
    stub.FireEvent("SPELLS_CHANGED")

    padOn()
    local m = _G.GamepadMode.FrameControlsManager
    function m:HandlePopupShown(frame)
        local old = self.focused
        if old and old.UnfocusGamepad then old:UnfocusGamepad() end
        self:FrameShown(frame)
    end
    function m:HandlePopupHide(frame) self:FrameHidden(frame) end
    local f = open(ns)
    local W = DaylightUI.Widgets
    local function feedRow()
        for i = 1, 10 do
            local r = W.MenuRow(i)
            if r and r.key == "feed" then return r end
        end
    end
    _G.SmartNavigation = { GetCurrentButton = function() return feedRow() end }
    stub.secure = true
    ns.Window.PadMore(ns.Bags.buttons[0][1])
    local row = feedRow()
    T.truthy(row, "a Feed Pet row for food the pet eats")
    T.eq(row and row.text:GetText(), CONTEXT_ACTION_LABEL_FEED_TO_PET or "Feed Pet")
    local a = stub.overrides.PAD1
    T.truthy(a, "A is bound on the Feed Pet row")
    if a then stub.SecureClick(_G[a.click], a.button or "LeftButton", false) end
    T.deq(cast, { 6991 }, "Feed Pet is cast")
    T.deq(used, { "0:1" }, "on the food in that slot")
    T.falsy(W.menuOwner, "the menu closes")

    -- Food the pet won't eat, or no pet: no row.
    W.CloseMenu()
    _G.C_PetInfo = { CanPetEatItem = function() return false end }
    ns.Window.PadMore(ns.Bags.buttons[0][1])
    T.isnil(feedRow(), "no row for food the pet won't eat")
    W.CloseMenu()

    stub.secure, stub.CastSpell = false, nil
    _G.IsPlayerSpell, _G.UnitExists, _G.C_PetInfo = saved.IsPlayerSpell, saved.UnitExists, saved.PetInfo
    C_Spell.IsSpellUsable, _G.SpellCanTargetItem = saved.usable, saved.can
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- Ticket: blue glows stayed in bag slots, empty ones too, after selling and
-- moving things around. The blue is the game's store glow on its bag button
-- (BattlepayItemTexture); Daylight UI hid the new-item glow but not this one.
-- Whether the client still calls an emptied slot new isn't known, so the fake
-- game keeps both flags after the item leaves: the worst case.
local function glowing(btn)
    local t = btn.BattlepayItemTexture
    return t:IsShown() and (t:GetAlpha() or 1) > 0
end

T.test("bags: the game's blue store glow never shows on a slot, filled or emptied", function()
    local ns = login()
    world.battlepay = { ["0:1"] = true, ["0:3"] = true }
    world.items[0][3] = { iconFileID = 103, stackCount = 1, quality = 1, hyperlink = "|Hitem:3|h" }
    local f = open(ns)
    ns.FillAll(); stub.RunTimers()
    local a, b, empty
    for _, s in ipairs(f.set.Slots()) do
        local id = s.button:GetID()
        if s.bag == 0 and id == 1 then a = s.button end
        if s.bag == 0 and id == 3 then b = s.button end
        if s.bag == 0 and id == 9 then empty = s.button end
    end
    T.falsy(glowing(a), "a store item gets no blue glow")
    T.falsy(glowing(b))
    T.falsy(glowing(empty), "nor a slot that never held anything")
    -- Sold (or moved) while the bag is open: the slot empties, its flags stay.
    world.items[0][3] = nil
    ns.Window.Changed(f, { [0] = true })
    stub.RunTimers()
    T.falsy(glowing(b), "the emptied slot keeps no glow")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
