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

-- The footer's free slots without their color codes.
local function freeText(f) return (f.free:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function open(ns)
    OpenAllBags()
    stub.RunTimers()
    return ns.window
end




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
    T.eq(subRel, f.titleLine, "the sub line hangs under the title's line, which the tabs never squeeze")
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


-- Right-clicks the bag's portrait and returns the menu it opened.
local function portraitMenu(bag)
    local menu
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(owner, keys, values, current, onPick, width, opts)
        menu = { owner = owner, keys = keys, values = values, current = current, pick = onPick, opts = opts }
    end
    local b = bag.portraitButton
    b:GetScript("OnClick")(b, "RightButton")
    DaylightUI.Widgets.OpenMenu = openMenu
    return menu
end


-- Item counts in tooltips: what each character holds, from their saved bags and
-- bank, and this character's bags as they are now.
local function tipRows(ns, data)
    local rows, addLine, addDouble = {}, GameTooltip.AddLine, GameTooltip.AddDoubleLine
    GameTooltip.AddLine = function(_, text) rows[#rows + 1] = { text } end
    GameTooltip.AddDoubleLine = function(_, l, r) rows[#rows + 1] = { l, r } end
    ns.Saved.OnTip(GameTooltip, data)
    GameTooltip.AddLine, GameTooltip.AddDoubleLine = addLine, addDouble
    return rows
end
local function plainText(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function countWorld()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", time = time(),
        bags = { { section = "bags", size = 4, items = { [1] = { "|Hitem:1|h", 3 }, [2] = { "|Hitem:9|h", 1 } } } },
        bank = { { section = "bank", size = 4, items = { [2] = { "|Hitem:1|h", 4 }, [3] = { "|Hitem:1|h", 3 } } } } } }
    DaylightUI.DB.Root().accountBank = { time = time(), tabs = { { section = "account", size = 4,
        items = { [1] = { "|Hitem:1|h", 2 }, [2] = { "|Hitem:4|h", 1 } } } } }
    local own = DaylightUI.DB.Character()
    own.inventory = own.inventory or {}
    own.inventory.bank = { { section = "bank", size = 4, items = { [1] = { "|Hitem:1|h", 6 } } } }
    stub.RunTimers()
    return ns, alt
end












-- Loot shine: a new item of uncommon or better gets one glint across its icon
-- and a bright border that settles, once per bag:slot:item per session, and only
-- where it can be seen (looted with the bag open, or the first open after).





-- From the mailbox: the bag update came before the item was there, so the slot
-- filled empty. The unlock that followed found it and lit the border, but there
-- was no icon until a hover refilled it.

-- The game held an item in the slot before it had the item's data, so the slot
-- read empty at its bag update, and no bag update came once the data arrived.
-- That left a blank slot whose hover showed the item.





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

















-- The bag closing under a resting mouse (a vendor walked away from, Escape)
-- sends no leave, and the other bags stayed dimmed through every later open.

-- A bag update re-shows a hovered bag's tooltip, but only while the mouse is
-- really there: after leaving, it lit that bag again with no leave to follow.

-- A bag swapped while the mouse rests on its slot: the tooltip kept the old bag.








-- Kravel's Crate is a consumable bound as a quest item. The slot's quest info
-- read false at times, and it landed under Consumables.










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

-- A Shelf two slots wide: no two groups fit side by side, so each group sits
-- over the next and folding or emptying one moves everything under it.
local function narrowLogin()
    local ns, f = catLogin()
    DaylightUI:Set("Bags", "columns", 2)
    stub.RunTimers()
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


-- The keyring's free slots looked exactly like free bag slots under Empty, and
-- its keys mixed with the bags' own under Keys.



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









-- Folding a group gives its room back: a folded heading never sits beside an
-- open group (it left a hole under it there and saved no room), folded ones in a
-- row share one, and opening them all again puts everything back.

-- The packer on its own, with the groups of a real bag (10 columns, 35 px slots).
local function packWorld(L, f, counts)
    local cfg = f.Cfg()
    local size, gap, cols = 35, 2, 10
    local top = L.SlotTop(f, cfg)
    local inset = L.Ref(f, cfg, L.REF.inset)
    local boxes = {}
    for _, c in ipairs(counts) do
        local key, n, headW = c[1], c[2], c[3] + 2 * inset
        local function shape(across)
            local rows = math.ceil(n / across)
            return { w = math.max(across * size + (across - 1) * gap, headW), h = top + rows * size + (rows - 1) * gap,
                     across = across, lines = rows }
        end
        boxes[#boxes + 1] = { key = key, n = n, cols = cols, shape = shape }
    end
    return boxes, cols * size + (cols - 1) * gap, L.GroupGap(f, cfg), L.RowGap(f, cfg)
end

-- The bag seen in game, with name widths about as wide as its headings read there.
local USER_BAG = { { "recent", 1, 60 }, { "hearthstone", 1, 88 }, { "consumable", 4, 104 }, { "quest", 12, 98 },
                   { "weapon", 4, 76 }, { "tradegoods", 1, 104 }, { "recipe", 1, 70 }, { "empty", 2, 50 } }

local function rects(boxes, spots)
    local out = {}
    for i, b in ipairs(boxes) do
        local sh = spots[i].shape
        out[i] = { x = spots[i].x, y = spots[i].y, w = sh.w, h = sh.h, key = b.key, lines = sh.lines }
    end
    return out
end






-- Seen in game: Consumables folded beside an open Quest Items left a hole under
-- its heading, and folding it saved no room at all.

-- Seen in game: each group's line ran along the top of its slots and the rings
-- (with their shadow) drew over it, and the gaps between groups looked uneven.

-- The Shelf's spacing follows the approved picture (a 70 px slot, rings and all), scaled to the
-- slot size, so a bigger slot keeps the same proportions.

-- Seen in game: new loot easing into Recent wore the game's bright white frame.
-- The template's SetAlpha also sets its quality frame's alpha, so any fade of a
-- slot showed it again.

-- The template's SetAlpha only reaches the icon and count, so fading slots
-- through it left the ring popping in and undid an empty or greyed icon.

-- Folding a group should animate.

-- An eased layout moves each item from where it was on screen, not each button:
-- a button that now shows another item starts at that item's old spot.
local function easedRelayout(ns)
    ns.Layout.easing = true
    ns.Relayout()
    ns.Layout.easing = false
end

local function settleFeel()
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
    d = DaylightUI.Win.Feel.Driver()
    if d then stub.RunOnUpdate(d, 1) end
end

local function at(btn)
    local _, _, _, x, y = btn:GetPoint(1)
    return x, y
end




-- Two stacks of one item in different groups: folding the group of one must not
-- send the other off to the folded one's spot.

-- Loot with the bag open: a new weapon lands in bag 0 slot 3 (empty in this world).
local function lootWeapon(itemID, slot)
    itemID, slot = itemID or 10, slot or 3
    if world.class then world.class[itemID] = 2 end
    world.items[0][slot] = { iconFileID = 100 + itemID, stackCount = 1, quality = 2,
        hyperlink = "|Hitem:" .. itemID .. "|h", itemID = itemID, itemName = "Axe " .. itemID }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
end



-- If GetPoint hands back a spot a hair off the one set (rounding in the client;
-- Feel's rest() allows half a pixel for it), the cross-fade must still land every
-- piece. Seen in game: after big eased layouts (loot, mail, a cleanup), slots and
-- headings sat scattered over the new layout until the view was switched or the
-- UI reloaded.






-- A cleanup the game's way: SortBags only asks the server, and the moves come
-- back over several bag updates. Each step swaps two slots of one bag.
local function sortStep(a, b, bag)
    bag = bag or 0
    world.items[bag][a], world.items[bag][b] = world.items[bag][b], world.items[bag][a]
    stub.FireEvent("BAG_UPDATE", bag)
    stub.FireEvent("BAG_UPDATE_DELAYED")
end

-- Where each item sits on screen now, by its link.
local function itemSpots(f)
    local out = {}
    for _, s in ipairs(f.set.Slots()) do
        local b = s.button
        local info = world.items[s.bag] and world.items[s.bag][b:GetID()]
        if b:IsShown() and info then out[info.hyperlink] = { at(b) } end
    end
    return out
end

local function buttonOf(f, link)
    for _, s in ipairs(f.set.Slots()) do
        local info = world.items[s.bag] and world.items[s.bag][s.button:GetID()]
        if s.button:IsShown() and info and info.hyperlink == link then return s.button end
    end
end

-- Every shown slot's icon is what the bag holds now.
local function filledRight(f)
    for _, s in ipairs(f.set.Slots()) do
        local info = world.items[s.bag] and world.items[s.bag][s.button:GetID()]
        if s.button:IsShown() and (info and info.iconFileID) ~= s.button.dluiTexture then return false end
    end
    return true
end




-- Timers that keep their due time: runDue() runs only those due by now
-- (stub.RunTimers runs every one at once, however far off).
local function timedTimers()
    local pending = {}
    C_Timer.After = function(d, fn) pending[#pending + 1] = { due = GetTime() + (d or 0), fn = fn } end
    return function()
        for _ = 1, 10 do
            local ran = false
            for i = #pending, 1, -1 do
                local t = pending[i]
                if t.due <= GetTime() + 1e-9 then
                    table.remove(pending, i)
                    t.fn()
                    ran = true
                end
            end
            if not ran then return end
        end
    end
end











-- A small JSON reader standing in for the game's C_EncodingUtil.DeserializeJSON
-- (it errors on bad text, as the game's does).
local function readJSON(s)
    local i = 1
    local function ws() i = string.find(s, "%S", i) or #s + 1 end
    local value
    local function str()
        local out = {}
        i = i + 1
        while true do
            local c = string.sub(s, i, i)
            if c == "" then error("unfinished string") end
            if c == '"' then i = i + 1; return table.concat(out) end
            if c == "\\" then
                i = i + 1
                c = string.sub(s, i, i)
                if c == "n" then c = "\n" end
            end
            out[#out + 1] = c
            i = i + 1
        end
    end
    function value()
        ws()
        local c = string.sub(s, i, i)
        if c == "{" then
            local t = {}
            i = i + 1; ws()
            if string.sub(s, i, i) == "}" then i = i + 1; return t end
            while true do
                ws()
                if string.sub(s, i, i) ~= '"' then error("key expected") end
                local k = str(); ws()
                if string.sub(s, i, i) ~= ":" then error("colon expected") end
                i = i + 1
                t[k] = value(); ws()
                c = string.sub(s, i, i); i = i + 1
                if c == "}" then return t end
                if c ~= "," then error("comma expected") end
            end
        elseif c == "[" then
            local t = {}
            i = i + 1; ws()
            if string.sub(s, i, i) == "]" then i = i + 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                c = string.sub(s, i, i); i = i + 1
                if c == "]" then return t end
                if c ~= "," then error("comma expected") end
            end
        elseif c == '"' then
            return str()
        end
        local num = string.match(s, "^-?%d+%.?%d*", i)
        if num then i = i + #num; return tonumber(num) end
        if string.sub(s, i, i + 3) == "true" then i = i + 4; return true end
        if string.sub(s, i, i + 4) == "false" then i = i + 5; return false end
        if string.sub(s, i, i + 3) == "null" then i = i + 4; return nil end
        error("bad JSON at " .. i)
    end
    local v = value(); ws()
    if i <= #s then error("trailing text") end
    return v
end

-- An export as Baganator's category options write it (one line, keys in any
-- order, as its JSON encoder gives them).
local BAGANATOR = '{"hidden":["default_toy"],"version":1,"order":["default_hearthstone","_Gear","My Gear","Shinies",'
    .. '"__end","----","default_junk","Toys and Pets","default_other","default_special_empty"],'
    .. '"categories":[{"name":"Shinies","priority":250,"search":"#epic|#rare&~#junk"},'
    .. '{"name":"My Gear","search":"#gear&>40&#boe","priority":350},'
    .. '{"search":"#toy|#socket|#locked","priority":50,"name":"Toys and Pets"},'
    .. '{"search":"","priority":50,"name":"Keepers"}],'
    .. '"modifications":[{"source":"Keepers","items":[6948,2589]},{"items":[4306],"source":"default_junk"},'
    .. '{"source":"default_gem","items":[818]},{"source":"Toys and Pets","pets":[1234],"group":"expansion"}]}'


-- Newer Baganator exports pack the table: "BGR!1!", CBOR, compressed, Base64.
local function baganatorCodec()
    local store = {}
    _G.C_EncodingUtil = {
        SerializeCBOR = function(v) store[#store + 1] = v; return "cbor" .. #store end,
        DeserializeCBOR = function(s) local v = store[tonumber(string.match(s, "^cbor(%d+)$") or "")]
            if not v then error("bad cbor") end; return v end,
        CompressString = function(s) return s end, DecompressString = function(s) return s end,
        EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
    }
    return function(t) return "BGR!1!" .. _G.C_EncodingUtil.SerializeCBOR(t) end
end
















-- A blank slot in Recent. The slot filled empty, then the item came, and another
-- bag's change laid it out as Recent while only refilling that other bag.





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



-- Same pieces as the bags: chips, free bar, plain-money footer, no Sell junk.
local function sameLook(f, what)
    T.truthy(f.portrait:IsShown(), what .. ": portrait shows")
    T.truthy(f.sub:GetText() ~= nil, what .. ": sub line")
    T.truthy(#f.chips > 1, what .. ": chip row")
    T.truthy(f.freeBar:IsShown(), what .. ": free bar")
    T.eq(f.sellJunk, nil, what .. ": no Sell junk")
end


















-- Buying a tab. C_Bank.PurchaseBankTab is restricted (HasRestrictions). The
-- game's CONFIRM_BUY_BANK_TAB pop-up (Camelot/BankFrame.lua) calls it with its
-- data.bankType. Shown from addon code, that data is tainted and the game blocks
-- the call ("the game blocked PurchaseBankTab()"). A secure macro button's /run
-- counts as the game running it from a click.

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
    local slot = ns.Bank.set.buttons[7][1]
    local r = DaylightUI.Style.Accent()
    T.eq(ns.Items.Parts(slot).shell.opts.borderColor[1], r, "the tab's slots outlined in the accent")
    b:GetScript("OnLeave")(b)
    T.eq(ns.Items.Parts(slot).shell.opts.borderColor, ns.Items.Parts(slot).color, "back to its own outline")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- What the game's own Forever bank does (Camelot/BankFrame.lua, Mainline
-- BankFrameTemplates.lua) that Daylight UI's bank must do too. The game's
-- BankPanel never shows here (writing its bank type tainted every bag
-- right-click), so none of its OnShow, OnHide or events run.
-- ---------------------------------------------------------------------

local function pickBank(f, bankType)
    for _, t in ipairs(f.bankTabs) do
        if t.bankType == bankType then t:GetScript("OnClick")(t) end
    end
    stub.RunTimers()
end

local function atBank(ns)
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    return ns.bank
end

-- The game's bag row starts at the second tab: "We skip the first bag as we
-- start with the first bag purchased" (Camelot BankFrame.lua RefreshBagButtons).
-- The first tab is the bank's own slots, not a bag slot.
T.test("bank game: the bag strip starts at the second tab, the first is the bank itself", function()
    local ns = bankLogin()
    DaylightUI:Set("Bags", "bank.showSlots", true)
    atBank(ns)
    local strip = ns.Bank.strip
    T.eq(#strip.slots, 5, "tabs 2 to 6: one button per bag slot")
    T.eq(strip.slots[1].index, 2)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A bank bag swapped: the game's bag buttons refresh on BAG_CONTAINER_UPDATE.
T.test("bank game: a bank bag swapped shows at once on the strip", function()
    local ns = bankLogin()
    DaylightUI:Set("Bags", "bank.showSlots", true)
    atBank(ns)
    local b = ns.Bank.strip.slots[1]
    T.eq(b.icon:GetTexture(), ns.Slots.EMPTY_ICON)
    world.items[-8] = { [2] = { iconFileID = 77, stackCount = 1, quality = 1, hyperlink = "|Hitem:77|h", itemID = 77 } }
    stub.FireEvent("BAG_CONTAINER_UPDATE")
    T.eq(b.icon:GetTexture(), 77, "the new bag's icon")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- BankAutoSortButtonMixin: UI_BAG_SORTING_01, and nothing to sort with no tab.
T.test("bank game: Clean Up plays the sorting sound, and sorts nothing with no tab bought", function()
    local ns, bank = bankLogin()
    local played = {}
    _G.SOUNDKIT = { UI_BAG_SORTING_01 = 55 }
    _G.PlaySound = function(kit) played[#played + 1] = kit end
    local f = atBank(ns)
    f.sort:GetScript("OnClick")(f.sort, "LeftButton")
    T.eq(bank.calls.sort, 0, "the character bank sorted")
    T.deq(played, { 55 }, "the game's sorting sound")
    bank.calls.sort = nil
    bank.tabs[0] = {}
    f.sort:GetScript("OnClick")(f.sort, "LeftButton")
    T.isnil(bank.calls.sort, "no tab: nothing to sort")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The bank's Clean Up is the game's (SortBank), which reads the same direction
-- flag as its bag sort. The flag didn't hold in game, so it's written right
-- before each Clean Up from the switch, both ways (EllesmereUI does the same).
T.test("bank game: Clean Up tells the game the switch's direction right before it sorts", function()
    local ns, bank = bankLogin()
    local flag, atSort = true, {}
    C_Container.GetSortBagsRightToLeft = function() return flag end
    C_Container.SetSortBagsRightToLeft = function(v) flag = v end
    C_Container.SortBank = function(t) bank.calls.sort = t; atSort[#atSort + 1] = flag end
    local f = atBank(ns)
    DaylightUI:Set("Bags", "sortToEnd", true)
    flag = true   -- the game lost it
    f.sort:GetScript("OnClick")(f.sort, "LeftButton")
    T.eq(atSort[1], false, "toward the end: right to left off as the bank sorts")
    DaylightUI:Set("Bags", "sortToEnd", false)
    f.sort:GetScript("OnClick")(f.sort, "LeftButton")
    T.eq(atSort[2], true, "switch off: the game's normal fill")
    C_Container.GetSortBagsRightToLeft, C_Container.SetSortBagsRightToLeft = nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The account bank's gold: Daylight UI's own gold box (never the game's
-- BANK_MONEY_* pop-ups, opened from addon code they taint), a second click on
-- the same button closes it, and leaving the bank closes it
-- (BankPanelMixin:CloseAllBankPopups).
T.test("bank game: Deposit and Withdraw ask in Daylight UI's gold box, toggle, and close with the bank", function()
    local ns, bank = bankLogin()
    local W = DaylightUI.Widgets
    local moved, errors = {}, {}
    C_Bank.DepositMoney = function(t, c) moved[#moved + 1] = { "in", t, c } end
    C_Bank.WithdrawMoney = function(t, c) moved[#moved + 1] = { "out", t, c } end
    local showError = DaylightUI.ShowError
    DaylightUI.ShowError = function(text) errors[#errors + 1] = text end
    _G.GetMoney = function() return 50000 end
    local f = atBank(ns)
    pickBank(f, 2)
    stub.popup = nil
    f.deposit:GetScript("OnClick")(f.deposit, "LeftButton")
    stub.RunTimers()
    T.isnil(stub.popup, "not the game's pop-up")
    local spec = W.Asking()
    T.truthy(spec and spec.money, "Daylight UI's gold box")
    local box = _G.DaylightUIAsk
    box.coins.gold:SetText("2")
    W.Answer(true)
    T.deq(moved, { { "in", 2, 20000 } }, "2 gold into the account bank")
    -- More than you carry: the game's error, nothing moved.
    f.deposit:GetScript("OnClick")(f.deposit, "LeftButton")
    stub.RunTimers()
    box.coins.gold:SetText("9")
    W.Answer(true)
    T.eq(#moved, 1); T.eq(#errors, 1, "said why")
    -- Withdraw: more than the bank holds (5000) is refused too.
    f.withdraw:GetScript("OnClick")(f.withdraw, "LeftButton")
    stub.RunTimers()
    box.coins.silver:SetText("60")
    W.Answer(true)
    T.eq(#moved, 1); T.eq(#errors, 2)
    f.withdraw:GetScript("OnClick")(f.withdraw, "LeftButton")
    stub.RunTimers()
    box.coins.silver:SetText("40")
    W.Answer(true)
    T.deq(moved[2], { "out", 2, 4000 })
    -- A second click on the same button closes the box.
    f.withdraw:GetScript("OnClick")(f.withdraw, "LeftButton")
    stub.RunTimers()
    T.truthy(W.Asking())
    f.withdraw:GetScript("OnClick")(f.withdraw, "LeftButton")
    T.isnil(W.Asking(), "closed by the second click")
    -- Walking away with it open closes it, nothing moved.
    f.deposit:GetScript("OnClick")(f.deposit, "LeftButton")
    stub.RunTimers()
    T.truthy(W.Asking())
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.RunTimers()
    T.isnil(W.Asking(), "gone with the bank")
    T.eq(#moved, 2)
    DaylightUI.ShowError = showError
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- BankPanelLockPromptMixin: a locked bank says why instead of an empty window,
-- and the gold buttons say why they're off.
T.test("bank game: a locked bank says why", function()
    local ns = bankLogin()
    _G.Enum.BankLockedReason = { None = 0, BankDisabled = 1, BankConversionFailed = 2, NoAccountInventoryLock = 3 }
    _G.BANK_LOCKED_REASON_NO_ACCOUNT_INVENTORY_LOCK = "Needs an authenticator."
    C_Bank.FetchBankLockedReason = function(t) if t == 2 then return 3 end end
    C_Bank.CanDepositMoney = function() return false end
    local f = atBank(ns)
    T.falsy(f.bankNote and f.bankNote:IsShown(), "the character bank isn't locked")
    pickBank(f, 2)
    T.truthy(f.bankNote and f.bankNote:IsShown(), "the reason shows")
    T.truthy(string.find(f.bankNote:GetText() or "", "Needs an authenticator.", 1, true))
    T.eq(ns.Bank.WhyOff(), "Needs an authenticator.", "the gold buttons say why they're off")
    pickBank(f, 0)
    T.falsy(f.bankNote:IsShown(), "gone on the character bank")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- BankPanelPurchasePromptMixin: an account bank with no tab bought explains
-- itself with the game's own title and text, its cost red when you're short.
T.test("bank game: the account bank with no tab says what it is; a cost you can't pay is red", function()
    local ns, bank = bankLogin()
    bank.tabs[2] = {}
    C_Bank.CanPurchaseBankTab = function() return true end
    local afford = true
    C_Bank.FetchNextPurchasableBankTabData = function()
        return { tabCost = 10000, canAfford = afford, purchasePromptTitle = "Warband Bank",
                 purchasePromptBody = "Share items between characters." }
    end
    local f = atBank(ns)
    T.falsy(f.bankNote and f.bankNote:IsShown(), "the character bank has tabs")
    local red = DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.BAD)
    T.falsy(string.find(f.buyTab.text:GetText(), red, 1, true), "you can pay: not red")
    afford = false
    stub.FireEvent("PLAYER_MONEY")
    T.truthy(string.find(f.buyTab.text:GetText(), red, 1, true), "short of gold: the cost in red")
    pickBank(f, 2)
    T.truthy(f.bankNote:IsShown(), "the account bank explains itself")
    T.truthy(string.find(f.bankNote:GetText(), "Share items between characters.", 1, true))
    T.truthy(string.find(f.bankNote:GetText(), "Warband Bank", 1, true))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- BankPanelMoneyFrameMoneyDisplayMixin: the character bank shows your own gold
-- (type PLAYER), the account bank its own. Title by the bank shown
-- (RequestTitleRefresh: BANK or ACCOUNT_BANK_PANEL_TITLE).
T.test("bank game: the character bank shows your gold, and the title names the bank", function()
    local ns = bankLogin()
    _G.BANK, _G.ACCOUNT_BANK_PANEL_TITLE = "Bank", "Warband Bank"
    local f = atBank(ns)
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
    local sum = 0
    for n in f.money:GetText():gmatch("money:(%d+)") do sum = sum + tonumber(n) end
    T.eq(sum, 9592, "your own gold")
    T.eq(f.title:GetText(), "Bank")
    pickBank(f, 2)
    if d then stub.RunOnUpdate(d, 1) end
    T.eq(f.money:GetText(), "money:5000", "the account's gold")
    T.eq(f.title:GetText(), "Warband Bank")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ItemButtonUtil.GetItemContext: with the bank open the bags dim what can't go
-- into the bank shown (BankDepositing, C_Bank.IsItemAllowedInBankType).
T.test("bank game: at the account bank the bags dim what can't go there", function()
    local ns = bankLogin()
    local made = _G.ItemLocation
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    C_Bank.IsItemAllowedInBankType = function(t, loc) return not (t == 2 and loc.bag == 0 and loc.slot == 1) end
    local f = atBank(ns)
    local one = ns.Bags.buttons[0][1]
    T.truthy(ns.window:IsShown())
    T.eq(one.calls.SetMatchesSearch[1], true, "the character bank takes it")
    pickBank(f, 2)
    T.eq(one.calls.SetMatchesSearch[1], false, "soulbound: dimmed at the account bank")
    T.eq(ns.Bags.buttons[0][2].calls.SetMatchesSearch[1], true, "the rest stays lit")
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.RunTimers()
    T.eq(one.calls.SetMatchesSearch[1], true, "lit again once the bank closes")
    _G.ItemLocation = made
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's bank window makes no sound of its own: the bags it opens play
-- theirs. Under the game's sounds Daylight UI's bank played the character
-- window's.
T.test("bank game: under the game's window sounds the bank plays none of its own", function()
    local ns = bankLogin()
    DaylightUI:Set("general", "soundKinds.windows", "game")
    stub.RunTimers()
    local kits = {}
    _G.SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2, IG_BACKPACK_OPEN = 3, IG_BACKPACK_CLOSE = 4 }
    _G.PlaySound = function(kit) kits[#kits + 1] = kit end
    stub.Advance(1)
    atBank(ns)
    for _, k in ipairs(kits) do T.truthy(k ~= 1, "never the character window's open") end
    T.truthy(#kits > 0 and kits[#kits] == 3, "the bags opening with it play theirs")
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
    _G.DaylightUIBag:SetSize(400, 300)
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

-- The held bag's tooltip size line ("12 Slot Bag").
-- Returns a function that puts the game's back.
local function bagTooltip(slots)
    _G.C_TooltipInfo = _G.C_TooltipInfo or {}
    local real = C_TooltipInfo.GetBagItem
    C_TooltipInfo.GetBagItem = function(bag, slot)
        local it = world.items[bag] and world.items[bag][slot]
        if it and it.itemID == 50 then
            return { lines = { { leftText = "Traveler's Bag" }, { leftText = slots .. " Slot Bag" } } }
        end
        return { lines = {} }
    end
    return function() C_TooltipInfo.GetBagItem = real end
end

-- A 10 slot bag full of items, swapped for a 12 slot one with the other bags full:
-- the game swaps them itself and moves the items into the new bag (seen in game),
-- so Daylight UI leaves the drop to it instead of asking for free slots.
T.test("bags: a bag at least as big as the old one is left to the game", function()
    local ns = login()
    swapWorld()
    fillBackpack(0)                                       -- no free slots at all
    local restore = bagTooltip(14)                        -- the old bag has 12
    C_Container.PickupContainerItem(0, 3)
    T.falsy(ns.Swap.Try(1, 31), "left to the game")
    T.eq(#world.printed, 0, tostring(world.printed[1]))
    T.eq(world.puts, 0, "Daylight UI moved nothing")
    restore()
end)

-- Only a bigger bag was seen swapping in game, so a smaller one empties first even
-- when the items would fit in it.
T.test("bags: a smaller bag that would hold the items still empties the old one first", function()
    local ns = login()
    swapWorld()
    fillBackpack(0)
    local restore = bagTooltip(8)                         -- 8 slots, 3 items, old bag 12
    C_Container.PickupContainerItem(0, 3)
    T.truthy(ns.Swap.Try(1, 31), "handled here")
    restore()
end)

T.test("bags: a bag too small for the old one's items still empties it first", function()
    local ns = login()
    swapWorld()
    fillBackpack(0)
    local restore = bagTooltip(2)                         -- 2 slots, 3 items
    C_Container.PickupContainerItem(0, 3)
    T.truthy(ns.Swap.Try(1, 31), "handled here")
    T.truthy(world.printed[1] and world.printed[1]:find("free 3 more slots", 1, true), tostring(world.printed[1]))
    restore()
end)

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
    world.cooldowns = { ["0:1"] = { 100, 30, 1 } }
    for _ = 1, 5 do stub.FireEvent("BAG_UPDATE_COOLDOWN") end
    T.eq(c.n, 0, "nothing yet")
    stub.RunTimers()
    T.eq(c.n, 32, "one pass: each slot once")
    T.deq(B.buttons[0][1].Cooldown.set, { 100, 30 }, "the cooldowns are drawn")
    T.isnil(B.buttons[0][2].Cooldown.set, "none where nothing is cooling down")
    T.isnil(B.buttons[0][1].calls.UpdateCooldown, "never through the button's own UpdateCooldown")
    world.cooldowns = nil
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

T.test("bags: with the lock on, an equipment set item can't be sold or disenchanted", function()
    local ns = catLogin()
    local gear, other = ns.Bags.buttons[0][2], ns.Bags.buttons[0][1]
    world.sets["0:2"] = true
    T.falsy(ns.Categories.Guarded(0, 2, C_Container.GetContainerItemInfo(0, 2)), "off by default")
    DaylightUI:Set("Bags", "lockSets", true)
    stub.RunTimers()
    local clicks = function(b) return #(b.__clicks or {}) end
    T.truthy(ns.Categories.Guarded(0, 2, C_Container.GetContainerItemInfo(0, 2)))
    T.falsy(ns.Categories.IsLocked(C_Container.GetContainerItemInfo(0, 2).itemID), "not locked by hand")
    stub.FireEvent("MERCHANT_SHOW")
    T.truthy(gear.dluiGuarded)
    T.eq(clicks(gear), 0, "at a vendor no click reaches the game's sale")
    T.falsy(other.dluiGuarded, "the item beside it sells as ever")
    gear:GetScript("OnMouseUp")(gear, "RightButton")
    T.truthy(stub.ChatContains("is in an equipment set"), "a click says why nothing happened")
    stub.FireEvent("MERCHANT_CLOSED")
    T.falsy(gear.dluiGuarded)

    local current = true
    C_Spell.IsCurrentSpell = function(id) return current and id == ns.Disenchant.SPELL end
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    T.eq(clicks(gear), 0, "Disenchant on the cursor: no click reaches the game")
    current = false
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    T.eq(clicks(gear), 2)

    DaylightUI:Set("Bags", "lockSets", false)
    stub.RunTimers()
    stub.FireEvent("MERCHANT_SHOW")
    T.falsy(gear.dluiGuarded, "switched off: it sells like any other item")
    stub.FireEvent("MERCHANT_CLOSED")
    world.sets["0:2"] = nil
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
    stub.Advance(ns.Window.SORT_FIRST)
    stub.RunTimers()
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

T.test("bags: Clean Up puts items marked as junk at the end, with the gray junk", function()
    local ns = login({ view = "grid" })
    keepWorld()
    local f = open(ns)
    ns.FillAll()
    world.items[0][7] = { iconFileID = 50, stackCount = 1, quality = 0, itemID = 50, itemName = "Bone",
                          hyperlink = "|Hitem:50|h" }
    T.falsy(ns.Keep.AnyMarkedJunk(f), "nothing marked: the game's sort")
    ns.Categories.ToggleJunk(10, "Apple")
    T.truthy(ns.Keep.AnyMarkedJunk(f))
    f.sort:GetScript("OnClick")(f.sort)
    T.eq(world.sorted or 0, 0, "not the game's sort: it knows only gray junk")
    for _ = 1, 10 do stub.RunTimers() end
    T.eq(world.items[0][1].itemName, "Banana")
    T.eq(world.items[0][2].itemName, "Cherry")
    T.eq(world.items[0][3].itemName, "Date")
    T.eq(world.items[0][4].itemName, "Apple", "the marked item after the rest")
    T.eq(world.items[0][5].itemName, "Bone", "beside the gray junk")
    ns.Categories.ToggleJunk(10, "Apple")
end)

T.test("bags: with Clean up toward the end on, kept-slot Clean Up fills from the last slot back", function()
    local ns = login({ view = "grid" })
    keepWorld()
    DaylightUI:Set("Bags", "sortToEnd", true)
    -- The game's flag says the normal fill: the switch decides, not this.
    C_Container.GetSortBagsRightToLeft = function() return true end
    local f = open(ns)
    ns.Keep.Toggle(0, 3, 30)
    f.sort:GetScript("OnClick")(f.sort)
    for _ = 1, 10 do stub.RunTimers() end
    local last = ns.Bags.NumSlots(1)
    T.eq(world.items[0][3].itemName, "Cherry", "the kept item never moved")
    T.eq(world.items[1][last].itemName, "Apple", "the first item in the very last slot")
    T.eq(world.items[1][last - 1].itemName, "Banana")
    T.isnil(world.items[0][1], "the front left empty")
    C_Container.GetSortBagsRightToLeft = nil
end)

-- Ticket (2.4.0): with the switch on, "Clean Up in bags: it doesn't work". In
-- game the game's direction flag didn't hold what was written, so its sort
-- can't be trusted to pack toward the end: Daylight UI's own moves do it.
T.test("bags: Clean up toward the end packs every item into the last slots, nothing kept", function()
    local ns = login({ view = "grid" })
    keepWorld()
    local writes = {}
    C_Container.GetSortBagsRightToLeft = function() return true end
    C_Container.SetSortBagsRightToLeft = function(v) writes[#writes + 1] = v end
    DaylightUI:Set("Bags", "sortToEnd", true)
    local f = open(ns)
    T.falsy(ns.Keep.Any(), "no kept slots")
    f.sort:GetScript("OnClick")(f.sort)
    for _ = 1, 10 do stub.RunTimers() end
    local last = ns.Bags.NumSlots(1)
    T.eq(world.sorted, 0, "not left to the game's sort")
    T.eq(world.items[1][last].itemName, "Apple", "the first item in the very last slot")
    T.eq(world.items[1][last - 1].itemName, "Banana")
    T.eq(world.items[1][last - 2].itemName, "Cherry")
    T.eq(world.items[1][last - 3].itemName, "Date")
    for slot = 1, ns.Bags.NumSlots(0) do T.isnil(world.items[0][slot], "the backpack left empty") end
    T.eq(writes[#writes], false, "the game is told too, for anything that reads it")
    C_Container.GetSortBagsRightToLeft, C_Container.SetSortBagsRightToLeft = nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    stub.Advance(1)
    stub.RunTimers()
    T.truthy(f.sorting, "the bag holds while Clean Up is still running")
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
    T.eq(values.keep, DaylightUI.L["Stop keeping"])
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
    local bag = { iconFileID = 5, stackCount = 1, hyperlink = "|Hitem:5|h", itemID = 5 }
    world.items[-8] = { [1] = bag, [2] = bag }   -- both tabs are bags in their slots
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

-- A bought bank bag slot with no bag in it reads 0 slots for good. It used to
-- look like a tab still arriving, so the bank was never saved at all.
T.test("viewer: a bought bank bag slot with no bag in it doesn't stop the save", function()
    local ns = bankLogin()
    local bag = { iconFileID = 5, stackCount = 1, hyperlink = "|Hitem:5|h", itemID = 5 }
    world.items[-8] = { [1] = bag }          -- a bag in the first slot, none in the second
    world.sizes[7] = 0
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local inv = DaylightUI.DB.Character().inventory
    T.truthy(inv and inv.bank, "the bank saved without the empty slot")
    T.eq(#inv.bank, 1, "only the tab with a bag")
    T.eq(inv.bank[1].items[1][1], "|Hitem:61|h")
    -- A bag goes in the second slot while the bank is open: saved with it.
    world.items[-8][2] = bag
    world.sizes[7] = 4
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(#inv.bank, 2, "both tabs once the second has a bag")
    -- And taken out again: the saved copy drops that tab.
    world.items[-8][2] = nil
    world.sizes[7] = 0
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(#inv.bank, 1, "the tab goes once its bag is taken out")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("viewer: a tab with a bag but no slots yet is still arriving, nothing saved", function()
    local ns = bankLogin()
    local bag = { iconFileID = 5, stackCount = 1, hyperlink = "|Hitem:5|h", itemID = 5 }
    world.items[-8] = { [1] = bag, [2] = bag }
    world.sizes[7] = 0
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local inv = DaylightUI.DB.Character().inventory
    T.falsy(inv and inv.bank, "a half-read bank isn't saved")
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
    carryOn()
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
    portraitMenu(bag).pick("alts")
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

T.test("viewer: switched off, Alts leaves the portrait's menu, nothing new is saved", function()
    local ns = login()
    local bag = open(ns)
    T.falsy(bag.viewerButton, "no chest button in the tool row any more")
    T.eq(table.concat(portraitMenu(bag).keys, ","), "bank,alts")
    DaylightUI:Set("Bags", "viewer.enabled", false)
    stub.RunTimers()
    T.eq(table.concat(portraitMenu(bag).keys, ","), "bank", "only the bank while the viewer is off")
    headerFits(bag)
    ns.Viewer.Toggle()
    stub.RunTimers()
    T.falsy(ns.Viewer.window:IsShown(), "/dui bank says it's off instead")
    T.truthy(stub.ChatContains("Bank and alts is off"))
    DaylightUI.DB.Character().inventory = nil
    stub.FireEvent("PLAYER_LOGOUT")
    carryOn()
    T.falsy(DaylightUI.DB.Character().inventory, "nothing saved while off")
    DaylightUI:Set("Bags", "viewer.enabled", true)
    stub.RunTimers()
    T.eq(table.concat(portraitMenu(bag).keys, ","), "bank,alts", "back on: Alts is back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a right-click on the portrait opens the bank and the alts viewer", function()
    local ns = login()
    local realm = DaylightUI.DB.CharKey():match("%-(.*)$")
    local alt = "Alt-" .. realm
    DaylightUI.DB.Root().characters[alt] = { inventory = { class = "MAGE", money = 1, time = time(),
        bags = { { section = "bags", size = 4, items = {} } } } }
    local bag = open(ns)
    T.isnil(bag.tabs, "no header tabs")
    headerFits(bag)
    local b = bag.portraitButton
    T.truthy(b, "a mouse frame over the portrait")
    T.eq(select(2, b:GetPoint(1)), bag.portrait, "lying on the portrait")
    T.truthy(b:GetFrameLevel() > bag.handle:GetFrameLevel(), "above the title bar's drag handle")
    -- Hover: our tooltip names it and says what the right-click does.
    b:GetScript("OnEnter")(b)
    T.truthy(GameTooltip:IsShown(), "a tooltip on hover")
    b:GetScript("OnLeave")(b)
    local m = portraitMenu(bag)
    T.eq(m.owner, b, "dropped under the portrait")
    T.falsy(m.opts and m.opts.atCursor, "not at the cursor")
    T.eq(table.concat(m.keys, ","), "bank,alts")
    T.eq(m.values.bank, BANK or "Bank")
    T.eq(m.values.alts, "Alts")
    -- A left click opens nothing.
    local opened
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function() opened = true end
    b:GetScript("OnClick")(b, "LeftButton")
    DaylightUI.Widgets.OpenMenu = openMenu
    T.falsy(opened, "only the right button")
    -- Away from a banker: the saved bank, in the viewer.
    m.pick("bank")
    stub.RunTimers()
    local v = ns.Viewer.window
    T.truthy(v:IsShown(), "the saved bank opens")
    T.eq(ns.Viewer.part, "bank")
    T.eq(ns.Viewer.who, DaylightUI.DB.CharKey())
    -- At a banker: the live bank.
    ns.Viewer.Close()
    stub.RunTimers()
    ns.Bank.open = true
    portraitMenu(bag).pick("bank")
    stub.RunTimers()
    T.truthy(ns.Bank.window:IsShown(), "the live bank opens")
    T.falsy(DaylightUI.Motion.Shown(v), "not the viewer")
    ns.Bank.open = false
    -- Alts: another character's bags.
    portraitMenu(bag).pick("alts")
    stub.RunTimers()
    T.truthy(v:IsShown())
    T.eq(ns.Viewer.part, "bags")
    T.eq(ns.Viewer.who, alt)
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
    -- An item with a spell is used by bag and slot: clicking this addon's item
    -- button ran the game's click code tainted (CloseAllBags in the use).
    T.eq(s:GetAttribute("type"), "macro")
    T.eq(s:GetAttribute("macrotext"), "/use 0 1")
    T.eq(s:GetAttribute("clickbutton"), nil)
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

-- The game's own bag marks an X pick as from a bag, and the game then opens its
-- character window for an enchant some worn piece takes
-- (GameEvent.HandleEnchantSpellSelected). X here uses by bag and slot, so the
-- character window opens itself: ENCHANT_SPELL_SELECTED fires inside the use.
T.test("bags on a controller: an oil or armor kit picked with X goes on to the character window", function()
    local ns = login()
    world.items[0][1].itemID = 1
    C_Item.GetItemSpell = function(id) if id == 1 then return "Wizard Oil", 25123 end end
    C_Item.IsEquippableItem = function() return false end
    padOn()
    local at = ns.Bags.buttons[0][1]
    _G.SmartNavigation = { GetCurrentButton = function() return at end }
    local f = open(ns)
    stub.RunTimers()
    local o = stub.overrides.PAD3
    T.truthy(o, "X is bound")
    local s = _G[o.click]
    local CP = DaylightUI.Char.CharacterPage
    local was, opened = CP.OpenForEnchant, 0
    CP.OpenForEnchant = function() opened = opened + 1; return true end
    -- The use fires the event inside the secure click, before X's follow-up.
    stub.SecureClick(s, "RightButton", false)
    T.eq(opened, 0, "a drink: nothing more")
    s:SetScript("PreClick", function() stub.FireEvent("ENCHANT_SPELL_SELECTED") end)
    stub.SecureClick(s, "RightButton", false)
    stub.RunTimers()
    T.eq(opened, 1, "an enchant picked with X: the character window opens")
    s:SetScript("PreClick", nil)
    -- The other way round: the event a moment after the press.
    stub.Advance(2)
    stub.SecureClick(s, "RightButton", false)
    stub.FireEvent("ENCHANT_SPELL_SELECTED")
    stub.RunTimers()
    T.eq(opened, 2, "the event after the press works too")
    -- An enchant from the action bars: no X press near it.
    stub.Advance(2)
    stub.FireEvent("ENCHANT_SPELL_SELECTED")
    stub.RunTimers()
    stub.Advance(2)
    stub.SecureClick(s, "RightButton", false)
    stub.RunTimers()
    T.eq(opened, 2, "an enchant from elsewhere, then a later X: the bag leaves it to the game")
    CP.OpenForEnchant = was
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- With the mailbox open a right click attaches a usable item instead of using it,
-- so X keeps the item button's own right click there.
T.test("bags on a controller: X attaches a usable item at the mailbox", function()
    local ns = login()
    world.items[0][1].itemID = 1
    C_Item.GetItemSpell = function(id) if id == 1 then return "Drink", 430 end end
    C_Item.IsEquippableItem = function() return false end
    padOn()
    local at = ns.Bags.buttons[0][1]
    _G.SmartNavigation = { GetCurrentButton = function() return at end }
    _G.MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
    local f = open(ns)
    stub.RunTimers()
    local a = ns.Window.PadUseSecure(f, at)
    T.eq(a.type, "click"); T.eq(a.clickbutton, at)
    _G.MailFrame:Hide()
    a = ns.Window.PadUseSecure(f, at)
    T.eq(a.type, "macro"); T.eq(a.macrotext, "/use 0 1")
    -- Equipping goes the same way; selling keeps the right click.
    local equippable = C_Item.IsEquippableItem
    C_Item.IsEquippableItem = function() return true end
    a = ns.Window.PadUseSecure(f, at)
    T.eq(a.type, "macro"); T.eq(a.macrotext, "/use 0 1")
    _G.MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
    a = ns.Window.PadUseSecure(f, at)
    T.eq(a.type, "click"); T.eq(a.clickbutton, at)
    _G.MerchantFrame:Hide()
    _G.MerchantFrame = nil
    C_Item.IsEquippableItem = equippable
    _G.MailFrame = nil
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- In game: a mouse right-click on a usable item ran the slot's own click, the game's
-- click code ran tainted, and the use left the game's state tainted until a reload.
-- One secure button follows the pointer and uses the item by bag and slot.
T.test("bags on a controller: a right-click goes through a secure use on the slot under the pointer, out of combat only", function()
    local ns = login()
    padOn()
    local f = open(ns)
    local slotButton = ns.Bags.buttons[0][1]
    local enter, leave = slotButton:GetScript("OnEnter"), slotButton:GetScript("OnLeave")
    local modifierDown = false
    local isModifierKeyDown = _G.IsModifierKeyDown
    _G.IsModifierKeyDown = function() return modifierDown end
    enter(slotButton)
    local useButton = _G.DaylightUIBagUse
    T.truthy(useButton and useButton:IsShown(), "on the hovered slot")
    T.eq(useButton:GetAttribute("type2"), "macro")
    T.eq(useButton:GetAttribute("macrotext"), "/use 0 1", "that slot, by bag and slot")
    T.eq(useButton:GetFrameStrata(), "HIGH", "a strata above the bag's, so raising the bag on a click can't cover it")
    leave(slotButton)
    T.falsy(useButton:IsShown(), "off when the pointer leaves")
    modifierDown = true
    enter(slotButton)
    T.falsy(useButton:IsShown(), "a modified right-click keeps the slot's own click")
    modifierDown = false
    _G.MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
    enter(slotButton)
    T.falsy(useButton:IsShown(), "at a vendor a right-click sells: the slot's own click")
    _G.MerchantFrame:Hide(); _G.MerchantFrame = nil
    _G.GuildBankFrame = CreateFrame("Frame", "GuildBankFrame", UIParent)
    enter(slotButton)
    T.falsy(useButton:IsShown(), "at the guild bank a right-click deposits: the slot's own click")
    _G.GuildBankFrame:Hide(); _G.GuildBankFrame = nil
    enter(slotButton)
    T.truthy(useButton:IsShown())
    stub.EnterCombat()
    T.falsy(useButton:IsShown(), "off as a fight starts, before the lockdown")
    leave(slotButton); enter(slotButton)
    T.falsy(useButton:IsShown(), "and nothing in the fight")
    -- The fight ends with the pointer still on the slot: back without a new hover.
    local getMouseFoci = _G.GetMouseFoci
    _G.GetMouseFoci = function() return { slotButton } end
    stub.LeaveCombat()
    T.truthy(useButton:IsShown(), "back after the fight, the pointer still on the slot")
    -- Something opened over the slot meanwhile: the button stays off it.
    modifierDown = true
    stub.FireEvent("MODIFIER_STATE_CHANGED")
    T.falsy(useButton:IsShown())
    _G.GetMouseFoci = function() return { UIParent } end
    modifierDown = false
    stub.FireEvent("MODIFIER_STATE_CHANGED")
    T.falsy(useButton:IsShown(), "a menu over the slot keeps the pointer")
    _G.GetMouseFoci = getMouseFoci
    leave(slotButton)
    _G.IsModifierKeyDown = isModifierKeyDown
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
    T.truthy(f)
end)

-- With the controller UI off, a mouse player's right-click stays the game's own.
T.test("bags: with the controller UI off, a right-click is the slot's own click", function()
    local ns = login()
    _G.GamepadMode, _G.InputUtil = nil, nil
    open(ns)
    local slotButton = ns.Bags.buttons[0][1]
    slotButton:GetScript("OnEnter")(slotButton)
    local useButton = _G.DaylightUIBagUse
    T.falsy(useButton and useButton:IsShown(), "no secure button over the slot")
    slotButton:GetScript("OnLeave")(slotButton)
end)

-- A locked slot's clicks are off under Disenchant (Guard.lua). The secure use by
-- bag and slot would go around that and disenchant it.
T.test("bags on a controller: no secure use while a spell is targeting or on a locked slot", function()
    local ns = login()
    categoryWorld()   -- item 2 is a weapon, so it can be disenchanted and locked
    padOn()
    open(ns)
    local locked, other = ns.Bags.buttons[0][2], ns.Bags.buttons[0][1]
    ns.Categories.ToggleLock(C_Container.GetContainerItemInfo(0, 2).itemID)
    stub.RunTimers()
    local disenchanting = false
    local isCurrentSpell, spellIsTargeting = C_Spell.IsCurrentSpell, _G.SpellIsTargeting
    C_Spell.IsCurrentSpell = function(id) return disenchanting and id == ns.Disenchant.SPELL end
    _G.SpellIsTargeting = function() return disenchanting end
    local getMouseFoci = _G.GetMouseFoci
    local underPointer = other
    _G.GetMouseFoci = function() return { underPointer } end

    other:GetScript("OnEnter")(other)
    local useButton = _G.DaylightUIBagUse
    T.truthy(useButton:IsShown(), "no spell: the secure use")
    disenchanting = true
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    T.falsy(useButton:IsShown(), "Disenchant on the cursor: the slot's own click, even on an unlocked item")
    disenchanting = false
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    T.truthy(useButton:IsShown(), "the cast gone: back")
    other:GetScript("OnLeave")(other)

    disenchanting = true
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    T.truthy(locked.dluiGuarded, "Disenchant on the cursor locks the slot")
    underPointer = locked
    locked:GetScript("OnEnter")(locked)
    T.falsy(useButton:IsShown(), "a locked slot under Disenchant: no secure use")
    -- Even if the game said nothing was targeting, the lock still holds.
    _G.SpellIsTargeting = function() return false end
    stub.FireEvent("MODIFIER_STATE_CHANGED")
    T.falsy(useButton:IsShown(), "a locked slot: no secure use")
    local isEquippable = C_Item.IsEquippableItem
    C_Item.IsEquippableItem = function() return true end
    local action = ns.Window.PadUseSecure(ns.window, locked)
    T.eq(action.type, "click", "X on a locked slot keeps its own (switched off) click")
    T.eq(action.clickbutton, locked)
    C_Item.IsEquippableItem = isEquippable
    locked:GetScript("OnLeave")(locked)

    disenchanting = false
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED")
    C_Spell.IsCurrentSpell, _G.SpellIsTargeting, _G.GetMouseFoci = isCurrentSpell, spellIsTargeting, getMouseFoci
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- At a vendor only an item with a value is sold; one without is used, and the
-- mouse and X agree on it (Window.HandsOver).
T.test("bags on a controller: at a vendor an item with no value is used securely, by the mouse and X alike", function()
    local ns = login()
    world.items[0][1].itemID = 1
    world.items[0][1].hasNoValue = true
    C_Item.GetItemSpell = function(id) if id == 1 then return "Drink", 430 end end
    C_Item.IsEquippableItem = function() return false end
    padOn()
    local f = open(ns)
    local slotButton = ns.Bags.buttons[0][1]
    _G.MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
    _G.MerchantFrame.selectedTab = 1
    T.truthy(C_Container.GetContainerItemInfo(0, 1).hasNoValue)
    local action = ns.Window.PadUseSecure(f, slotButton)
    T.eq(action.type, "macro"); T.eq(action.macrotext, "/use 0 1")
    slotButton:GetScript("OnEnter")(slotButton)
    T.truthy(_G.DaylightUIBagUse:IsShown(), "the mouse too")
    slotButton:GetScript("OnLeave")(slotButton)
    _G.MerchantFrame.selectedTab = 2
    T.truthy(ns.Window.HandsOver(C_Container.GetContainerItemInfo(0, 1)), "the buyback tab: the game's click, which does nothing")
    _G.MerchantFrame:Hide(); _G.MerchantFrame = nil
    world.items[0][1].hasNoValue = nil
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
end)

-- The game's side of a bag click with the controller UI on, line for line where
-- it reads something an addon could have written.
--   ContainerFrameItemButton_OnClick ends in the "ContainerFrameItemButton.OnItemClicked"
--   event, and the game's own (parked) combined bag answers it by refreshing its
--   controller footer (Gamepad_OnItemClicked). QUEST_ACCEPTED and a bag update
--   refresh it too while the game counts its bags open (UpdateIfShown, Update).
--   The footer's conditions run on SmartNavigation's current button whenever it
--   carries the bag button template's buttonContext, so on a Daylight UI slot
--   too: they read button.hasItem, button:IsReadable() and button:GetBagID().
--   The refresh then makes a new binding group (RefreshBindingGroup), and
--   GamepadMode.CreateBindingGroup reads and writes one file-local counter,
--   nextBindingGroupId (BindingSetFactory.lua).
-- So one tainted read there leaves the counter tainted for the session. Every
-- footer refresh of any game window reads it afterwards, puts its bindings on the
-- stack tainted, and the interact icon's SetPreferredGamepadInteractTarget
-- (MainActionBarFrame.lua UpdateInteractIcons) is refused, named after the addon.
local function padGame(current)
    local game = { blocked = {}, counter = nil }
    local by   -- the addon the running game code is tainted by
    local function read(t, k)
        local secure, who = issecurevariable(t, k)
        if not secure then by = by or who end
        return t[k]
    end
    local function createBindingGroup()
        by = by or game.counter
        game.counter = by
    end
    local function refreshBagFooter()
        local button = current()
        if button and read(button, "buttonContext") == "ButtonContext_ContainerFrameItemButton" then
            read(button, "hasItem")     -- Gamepad_IsClickContextActionValid and four more
            read(button, "readable")    -- Gamepad_IsReadActionValid, through IsReadable
            read(button, "bagID")       -- GetBagID, before the holder's ID
        end
        createBindingGroup()
    end
    local function run(fn)
        by = nil
        stub.inSecure = (stub.inSecure or 0) + 1
        local ok, err = pcall(fn)
        stub.inSecure = stub.inSecure - 1
        by = nil
        if not ok then error(err, 0) end
    end
    _G.SmartNavigation = { GetCurrentButton = function() return current() end }
    -- A click on a bag button (the mouse, or the controller's key through a secure
    -- button's clickbutton), and an event that refreshes the footer.
    function game.Click() run(refreshBagFooter) end
    function game.Event() run(refreshBagFooter) end
    -- Any game window taking the controller afterwards (the world map, a vendor),
    -- then the interact icon as the soft target changes.
    function game.Later()
        run(function()
            createBindingGroup()
            if by then
                game.blocked[#game.blocked + 1] = by
                stub.FireEvent("ADDON_ACTION_FORBIDDEN", by, "SetPreferredGamepadInteractTarget()")
            end
        end)
    end
    return game
end

T.test("bags on a controller: a click on an item leaves nothing tainted for the game's controller to read", function()
    local ns = login()
    world.items[0][1].isReadable = true
    padOn()
    local f = open(ns)
    stub.RunTimers()
    local at = ns.Bags.buttons[0][1]
    local game = padGame(function() return at end)
    local ok, err = pcall(function()
        -- The mouse sells an item at a vendor (the slot's own click), then the
        -- player walks away and comes near an innkeeper.
        game.Click()
        game.Later()
        T.deq(game.blocked, {}, "the game's own controller call goes through")
        for _, k in ipairs({ "buttonContext", "hasItem", "readable", "bagID" }) do
            local secure, who = issecurevariable(at, k)
            T.truthy(secure, "the slot's " .. k .. " is the game's own, not written by " .. tostring(who))
        end
        -- A quest accepted with the bag open, a slot that emptied and filled again.
        world.items[0][1] = nil
        stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
        world.items[0][1] = { iconFileID = 101, stackCount = 1, quality = 1, hyperlink = "|Hitem:1|h", isReadable = true }
        stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
        stub.FireEvent("BAG_UPDATE_COOLDOWN"); stub.RunTimers()
        game.Event()
        for _, row in pairs(ns.Bags.buttons) do
            for _, slotButton in pairs(row) do
                at = slotButton
                game.Click()
            end
        end
        game.Later()
        T.deq(game.blocked, {}, "after every slot was filled, emptied and clicked")
        T.falsy(stub.ChatContains("blocked"), "and no line in chat")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        T.truthy(f:IsShown())
    end)
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
    if not ok then error(err, 0) end
end)

-- What the button's own SetHasItem, SetReadable and UpdateCooldown did for a
-- player, now done without them.
T.test("bags: cooldown, dimmed icon, pointer and tooltip without the button's own item fields", function()
    local ns = login()
    world.items[0][1].isReadable = true
    -- A cooldown that hasn't started counting (enable 0) dims the icon, as the game's does.
    world.cooldowns = { ["0:1"] = { 100, 30, 0 }, ["0:2"] = { 100, 30, 1 } }
    open(ns)
    local B = ns.Bags
    local letter, plain, empty = B.buttons[0][1], B.buttons[0][2], B.buttons[0][3]
    stub.FireEvent("BAG_UPDATE_COOLDOWN"); stub.RunTimers()
    local r = letter.icon:GetVertexColor()
    T.near(r, 0.4, 0.001, "dim while it can't be used yet")
    T.isnil(letter.Cooldown.set)
    T.deq(plain.Cooldown.set, { 100, 30 }, "the sweep on a running cooldown")
    T.falsy(empty.Cooldown:IsShown(), "an empty slot shows none")
    for _, b in ipairs({ letter, plain, empty }) do
        T.isnil(b.calls.SetHasItem); T.isnil(b.calls.SetReadable); T.isnil(b.calls.UpdateCooldown)
    end
    -- The pointer: a magnifier on something to read, or with the dressing-room key
    -- held, never at a vendor (the sell pointer) or while a spell is targeting.
    local cursor, dress, selling, targeting = nil, false, false, false
    local olds = { ShowInspectCursor, IsModifiedClick, CanSellItems, SpellIsTargeting }
    _G.ShowInspectCursor = function() cursor = "inspect" end
    _G.IsModifiedClick = function(action) return action == "DRESSUP" and dress end
    _G.CanSellItems = function() return selling end
    _G.SpellIsTargeting = function() return targeting end
    local owner
    GameTooltip.GetOwner = function() return owner end
    local function hover(b)
        cursor = nil
        b:GetScript("OnEnter")(b)
        owner = b
        return cursor
    end
    local function refresh()   -- the game's slot resets the pointer, then the tooltip's update ends
        cursor = nil
        local update = GameTooltip:GetScript("OnUpdate")
        if update then update(GameTooltip, 0.2) end
        return cursor
    end
    T.eq(hover(letter), "inspect", "a letter reads")
    T.eq(refresh(), "inspect", "and stays so through the tooltip's refresh")
    selling = true
    T.isnil(refresh(), "the sell pointer at a vendor")
    selling, targeting = false, true
    T.isnil(refresh(), "a targeting spell keeps its own")
    targeting = false
    letter:GetScript("OnLeave")(letter)
    T.isnil(refresh(), "nothing once the pointer left")
    T.isnil(hover(plain), "a plain item has none")
    dress = true
    T.eq(refresh(), "inspect", "the dressing-room key held over an item")
    plain:GetScript("OnLeave")(plain)
    T.isnil(hover(empty), "never on an empty slot")
    empty:GetScript("OnLeave")(empty)
    dress = false
    -- The tooltip of the slot under the pointer follows a refill, and goes with the item.
    local updated, hidden = 0, 0
    plain.UpdateTooltip = function() updated = updated + 1 end
    local hide = GameTooltip.Hide
    GameTooltip.Hide = function() hidden = hidden + 1 end
    ns.Items.Fill(plain, plain)
    T.eq(updated, 1); T.eq(hidden, 0)
    world.items[0][2] = nil
    ns.Items.Fill(plain, plain)
    T.eq(updated, 1); T.eq(hidden, 1, "the item left: so does its tooltip")
    ns.Items.Fill(plain, letter)
    T.eq(hidden, 1, "another slot's tooltip is left alone")
    GameTooltip.Hide, GameTooltip.GetOwner = hide, nil
    _G.ShowInspectCursor, _G.IsModifiedClick, _G.CanSellItems, _G.SpellIsTargeting = olds[1], olds[2], olds[3], olds[4]
    world.cooldowns = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    local function going(key)
        for _, h in ipairs(f.headings) do
            if h.key == key and h:IsShown() and not (f.fading and f.fading[h]) then return false end
        end
        return true
    end
    T.truthy(headingsShown(f).junk, "the Junk heading stays")
    T.truthy(going("weapon"), "other headings go (fading out)")
    T.truthy(going("consumable"))
    local weapon = ns.Bags.buttons[0][1]
    T.truthy(not weapon:IsShown() or (f.fading and f.fading[weapon]), "the rare weapon's slot hides (or fades out)")
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, 1) end
    end
    T.eq(weapon:IsShown(), false, "once the fade ends it is hidden and takes no clicks")
    local only = headingsShown(f)
    T.eq(only.weapon, nil, "faded headings are hidden")
    T.eq(only.consumable, nil)
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
    f.search:SetFocus()
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

-- ItemTree (another addon) judges items through its public API, ItemTreeAPI:
-- keep it, sell it, use it now. Its own marks never find these bags, so the
-- bags draw its answer: a dot top right, search words, and junk selling that
-- leaves its keeps alone. A stand-in with the API's real shape (version 1).
local function fakeItemTree(facts, ready)
    local api = { version = 1, demo = { on = false }, ready = ready ~= false, readyFns = {}, changeFns = {}, asked = 0 }
    api.IsReady = function() return api.ready end
    api.RequestData = function() return api.ready end
    api.RegisterReadyCallback = function(fn)
        if api.ready then fn() else api.readyFns[#api.readyFns + 1] = fn end
        return true
    end
    api.RegisterChangeCallback = function(fn) api.changeFns[#api.changeFns + 1] = fn; return true end
    api.GetItemFacts = function(id)
        api.asked = api.asked + 1
        if not api.ready then return nil end
        return facts[id]
    end
    api.GetHeldCounts = function() return 0, 0, 0 end
    api.BecomeReady = function()
        api.ready = true
        for _, fn in ipairs(api.readyFns) do fn() end
    end
    return api
end

local function verdict(tags, extra)
    local keep = { marked = tags[1] == "keep", tags = tags }
    for k, v in pairs(extra or {}) do keep[k] = v end
    return { keep = keep, quests = { needs = {} } }
end

local function slotAt(ns, bag, slot)
    for _, s in ipairs(ns.Bags.Slots()) do
        if s.bag == bag and s.button:GetID() == slot then return s.button end
    end
end

local function itDot(ns, bag, slot)
    local p = ns.Items.Parts(slotAt(ns, bag, slot))
    return p.itDot ~= nil and p.itDot:IsShown() and p.itDot or nil
end

T.test("bags: ItemTree's verdicts show as a dot on each slot, in the color of what to do", function()
    _G.ItemTreeAPI = fakeItemTree({
        [4] = verdict({ "keep" }),
        [6] = verdict({ "auction" }),
        [7] = verdict({}, { action = { kind = "open", words = "Open it", now = true } }),
        [2] = verdict({ "vendor" }),
    })
    local ns = login()
    world.items[0][4].itemID, world.items[0][5].itemID, world.items[0][6].itemID, world.items[0][2].itemID = 4, 6, 7, 2
    open(ns)
    ns.FillAll(); stub.RunTimers()
    local INK = DaylightUI.Style.INK
    T.truthy(itDot(ns, 0, 4), "a keep")
    T.rgb(itDot(ns, 0, 4).__vertexColor or { itDot(ns, 0, 4):GetVertexColor() }, INK.GOOD, "keep is green")
    T.rgb(itDot(ns, 0, 5).__vertexColor or { itDot(ns, 0, 5):GetVertexColor() }, INK.MONEY, "auction is gold")
    T.rgb(itDot(ns, 0, 6).__vertexColor or { itDot(ns, 0, 6):GetVertexColor() }, { DaylightUI.Style.Accent() }, "open it now: the accent")
    T.isnil(itDot(ns, 0, 2), "a gray item to vendor is already dimmed as junk")
    T.isnil(itDot(ns, 0, 1), "nothing said about it")
    -- The switch takes them away.
    DaylightUI:Set("Bags", "itemTreeMarks", false)
    stub.Advance(1); stub.RunTimers()
    T.isnil(itDot(ns, 0, 4), "off: no dots")
    DaylightUI:Set("Bags", "itemTreeMarks", true)
    stub.Advance(1); stub.RunTimers()
    -- Its answer moves (a setting of ItemTree's): every slot asks again.
    ItemTreeAPI.GetItemFacts = function(id) if id == 4 then return verdict({ "vendor" }) end end
    for _, fn in ipairs(ItemTreeAPI.changeFns) do fn("setting") end
    stub.RunTimers()
    T.rgb(itDot(ns, 0, 4).__vertexColor or { itDot(ns, 0, 4):GetVertexColor() }, INK.MONEY, "now a sell")
    T.isnil(itDot(ns, 0, 6), "no longer said")
    _G.ItemTreeAPI = nil
end)

T.test("bags: ItemTree's dots wait for its data, and never judge another character's saved bags", function()
    local api = fakeItemTree({ [4] = verdict({ "keep" }) }, false)
    _G.ItemTreeAPI = api
    local ns = login()
    world.items[0][4].itemID = 4
    open(ns)
    ns.FillAll(); stub.RunTimers()
    T.isnil(itDot(ns, 0, 4), "data not in yet")
    T.eq(#api.readyFns, 1, "waits for it")
    api.BecomeReady()
    stub.RunTimers()
    T.truthy(itDot(ns, 0, 4), "drawn once it's in")
    T.isnil(ns.ItemTree.Facts(4, nil, ns.Saved.BASE), "a saved copy is never asked")
    _G.ItemTreeAPI = nil
end)

T.test("bags: ItemTree's search words, only with ItemTree there", function()
    local ns = login()
    T.isnil(ns.Search.KEYWORDS.keep, "no ItemTree: keep is a name search")
    T.falsy(ns.ItemTree.Installed())
    _G.ItemTreeAPI = fakeItemTree({ [4] = verdict({ "keep" }), [6] = verdict({ "disenchant" }),
        [1] = { keep = { tags = {} }, quests = { needs = { 101 } } } })
    ns.ItemTree.Hook()
    world.items[0][4].itemID, world.items[0][5].itemID, world.items[0][1].itemID = 4, 6, 1
    local function finds(text, slot)
        return ns.Search.Parse(text)(ns.Search.Facts(0, slot, C_Container.GetContainerItemInfo(0, slot))) == true
    end
    T.truthy(finds("keep", 4)); T.falsy(finds("keep", 5))
    T.truthy(finds("sell", 5)); T.truthy(finds("disenchant", 5)); T.falsy(finds("vendor", 5))
    T.truthy(finds("needed", 1)); T.falsy(finds("needed", 4))
    T.truthy(finds("!keep", 5), "negated too")
    _G.ItemTreeAPI = nil
end)

T.test("bags: Sell junk leaves a gray item ItemTree keeps, and its tooltip says why", function()
    _G.ItemTreeAPI = fakeItemTree({ [2] = verdict({ "keep" }), [21] = verdict({ "vendor" }) })
    local ns = catLogin()
    local sold = {}
    C_Container.UseContainerItem = function(bag, slot) sold[#sold + 1] = bag .. ":" .. slot end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:2|h" or link == "|Hitem:21|h" then return "name", link, 0, 1, 1, "", "", 20, "", 1, 5, 0, 0, 0 end
        return getInfo(link)
    end
    world.items[0][2].itemID = 2
    world.items[0][7] = { iconFileID = 107, stackCount = 1, quality = 0, hyperlink = "|Hitem:21|h", itemID = 21 }
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    local junk = {}
    for _, j in ipairs(ns.Junk.Items()) do junk[#junk + 1] = j.bag .. ":" .. j.slot end
    T.eq(table.concat(junk, ","), "0:7", "the kept one isn't junk")
    DaylightUI:Set("Bags", "sellJunk", false)
    stub.FireEvent("MERCHANT_SHOW")
    T.truthy(DaylightUI.SellJunkAroundLocks(), "sells around it, not the game's sell-all")
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(table.concat(sold, ","), "0:7")
    stub.FireEvent("MERCHANT_CLOSED")
    -- Moved to Junk by hand: still kept, and the tooltip says so.
    ns.Categories.ToggleJunk(2)
    T.eq(#ns.Junk.Items(), 1, "still not sold")
    T.truthy(string.find(ns.Junk.TipText(2), "ItemTree", 1, true))
    -- The switch off: it sells like any junk.
    DaylightUI:Set("Bags", "itemTreeKeep", false)
    stub.RunTimers()
    T.eq(#ns.Junk.Items(), 2, "off: sold with the rest")
    C_Item.GetItemInfo = getInfo
    _G.ItemTreeAPI = nil
end)

-- Unlocked, every nudge of the bank (arrow keys or typed numbers) also moved
-- it 3 px up, seen in game: the window is shorter than its handle's least
-- height, its top was taken from the handle's, and the handle then sat back on
-- the window's middle, 3 px lower than the move had put it.
T.test("bags: a handle move puts the window's middle on the handle's middle", function()
    local ns = bankLogin()
    local DUI = DaylightUI
    local f = _G.DaylightUIBank
    local fh, fw = f:GetHeight(), f:GetWidth()
    T.truthy(fh < ns.Window.MOVER_MIN[2], "a bank shorter than the handle's least height")
    DUI.Movers.Unlock()
    stub.RunTimers()
    local e, h = DUI.Movers.Get("bags.bank"), DUI.Movers.Handle("bags.bank")
    DUI.Movers.PlaceHandle(e, h)
    T.eq(h:GetHeight(), ns.Window.MOVER_MIN[2], "the handle is taller than the window")
    DUI.DB.Positions()["bags.bank"] = { 10, -20 }
    e.onMoved("bags.bank")
    stub.RunTimers()
    local pos = f.Setting("position")
    T.near(pos[1], UIParent:GetWidth() / 2 + 10 - fw / 2, 0.01, "left edge")
    T.near(pos[2], UIParent:GetHeight() / 2 - 20 + fh / 2, 0.01, "top edge: half the window above the middle, not half the handle")
    DUI.Movers.Lock()
end)

-- A player's ask: feed the pet from the bag, like Comprehend Scroll's button.
T.test("bags: the Feed Pet button: shown to hunters who know it, beside the other tools; hovered, it casts Feed Pet", function()
    local ns = login()
    local FP = ns.FeedPet
    T.truthy(FP, "a Feed Pet tool")
    T.eq(FP.SPELL, 6991)
    local known = {}
    _G.IsPlayerSpell = function(id) return known[id] == true end
    stub.FireEvent("SPELLS_CHANGED")
    local f = open(ns)
    local b = f.feedPetButton
    T.truthy(b, "its button in the tool row")
    T.falsy(b:IsShown(), "not a hunter: no button")
    T.eq(select(2, f.search:GetPoint(2)), f.viewButton, "the search ends at the last tool shown")
    known[FP.SPELL] = true
    stub.FireEvent("SPELLS_CHANGED")
    T.truthy(b:IsShown())
    T.eq(select(2, f.search:GetPoint(2)), b, "the search ends at it")
    T.truthy(tostring(b.icon:GetTexture()):find("ui%-feed%.png"), "a flat icon like the rest of the row")
    b.GetLeft, b.GetBottom = function() return 360 end, function() return 300 end
    b:SetSize(28, 28)
    stub.secure = true
    b:GetScript("OnEnter")(b)
    local o = FP.caster.button
    T.truthy(o and o:IsShown(), "the secure button lies over ours")
    T.truthy(o ~= ns.Disenchant.caster.button and o ~= ns.Comprehend.caster.button, "its own secure button")
    T.eq(o:GetAttribute("type1"), "spell"); T.eq(o:GetAttribute("spell"), FP.SPELL)
    T.eq(o:GetParent(), UIParent, "never inside the bag")
    stub.EnterCombat()
    T.falsy(o:IsShown(), "hidden as the fight starts")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The Auction House addon takes a bag item on its Sell tab. A plain right
-- click and an Alt-left-click both reach it, each saying which click it was;
-- Alt-right-click stays the group menu and other modifiers reach nothing.
T.test("bags: right-click and Alt-click hand the item to the Auction House", function()
    local ns = login()
    open(ns)
    local got = {}
    DaylightUI.AuctionHouseSell = function(bag, slot, click) got[#got + 1] = { bag, slot, click }; return true end
    local menu = ns.Categories.Menu
    local menus = 0
    ns.Categories.Menu = function() menus = menus + 1 end
    local btn = ns.Bags.buttons[0][1]
    local click = btn:GetScript("OnClick")
    click(btn, "RightButton")
    stub.alt = true
    click(btn, "LeftButton")
    click(btn, "RightButton")
    stub.shift = true
    click(btn, "LeftButton")
    stub.alt, stub.shift = false, false
    click(btn, "LeftButton")
    ns.Categories.Menu = menu
    DaylightUI.AuctionHouseSell = nil
    T.eq(#got, 2, "a right click and an Alt-left-click")
    T.eq(got[1][3], "right"); T.eq(got[1][1], 0); T.eq(got[1][2], 1)
    T.eq(got[2][3], "alt")
    T.eq(menus, 1, "Alt-right-click is the group menu")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
