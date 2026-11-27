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

-- The bank's strip is built from the bags' strip pieces (Slots.NewButton).


-- ---------------------------------------------------------------------
-- Currencies in the footer
-- ---------------------------------------------------------------------




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

-- Only a bigger bag was seen swapping in game, so a smaller one empties first even
-- when the items would fit in it.








-- Opening only fades, and nothing in the grid or its slots moves. A lift moved
-- every slot each frame (~10 fps), and pinning the grid for one re-placed every
-- piece of every slot on each opening (~280 ms frozen in game).

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



-- Selling fast: while the bag is open, a slot that empties keeps its place so no
-- item slides under the cursor. The next open groups it again.
local function spot(btn)
    local _, _, _, x, y = btn:GetPoint(1)
    return x, y
end











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











-- ---------------------------------------------------------------------
-- Work only where something changed
-- ---------------------------------------------------------------------






-- Loaded and still no bind type (a keystone: or battlepet: cage link). The load
-- refilled it, the fill asked again, and the game answered again
-- (ITEM_DATA_LOAD_RESULT for a cached item), giving a fill every frame.


-- A link the item info never gives a stack size for, loaded or not (a keystone:
-- or battlepet: cage). The game answers each request with ITEM_DATA_LOAD_RESULT
-- (RequestLoadItemDataByID), so asking on every layout laid the open bag out
-- again every frame.







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








-- ---------------------------------------------------------------------
-- The viewer: your bank anywhere, and your other characters' bags (Saved.lua, Viewer.lua)
-- ---------------------------------------------------------------------


-- The game at PLAYER_LOGOUT, where the bags and gold already read empty. Every
-- character's saved file on the modern client showed bags = {} and money = 0.
local function logout()
    for id in pairs(world.sizes) do world.sizes[id] = 0 end
    _G.GetMoney = function() return 0 end
    stub.FireEvent("PLAYER_LOGOUT")
end



-- A bought bank bag slot with no bag in it reads 0 slots for good. It used to
-- look like a tab still arriving, so the bank was never saved at all.















-- A stream of bag changes (looting, a vendor) leads to one read of every slot once
-- it stops. A fight waits for its end.



-- Other addons' bag marks. A plugin written for Baganator's bags draws on
-- Daylight UI's slots through the same calls (Plugins.lua).
local function upArrow(rule)
    return function(button)
        local m = CreateFrame("Frame", nil, button)
        m:SetSize(10, 10)
        return m
    end, function(_, d) return rule(d) end
end





-- DaylightUI.API 1.3: bag slots are frames plugins paint ("bagslot", unit
-- "bag:slot"; icon, count, border), painted after every fill of the slot.

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


-- With the mailbox open a right click attaches a usable item instead of using it,
-- so X keeps the item button's own right click there.

-- In game: a mouse right-click on a usable item ran the slot's own click, the game's
-- click code ran tainted, and the use left the game's state tainted until a reload.
-- One secure button follows the pointer and uses the item by bag and slot.

-- With the controller UI off, a mouse player's right-click stays the game's own.

-- A locked slot's clicks are off under Disenchant (Guard.lua). The secure use by
-- bag and slot would go around that and disenchant it.

-- At a vendor only an item with a value is sold; one without is used, and the
-- mouse and X agree on it (Window.HandsOver).

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


-- What the button's own SetHasItem, SetReadable and UpdateCooldown did for a
-- player, now done without them.

-- The game's delete question can't be asked from addon code: it opens inside
-- the call and carries the addon's taint into the controller (tests/test_guards).
-- So the menu row itself asks ("Click again"), and only then is it deleted.

local function headingsShown(f)
    local out = {}
    for _, h in ipairs(f.headings or {}) do if h:IsShown() and h.key then out[h.key] = true end end
    return out
end




-- New loot sits in Recent, but a chip still judges it by the group it would
-- otherwise fall in, so a fresh weapon shows under Gear.



-- The window's top to the grid: the header, the tool row and, while shown, the filters.
local function gridTop(f)
    local _, _, _, _, y = f.items:GetPoint(1)
    return -y
end

local function filtersShown(f)
    for _, b in ipairs(f.chips) do if not b:IsShown() then return false end end
    return true
end

local function runMotion(n, dt)
    for _ = 1, n or 1 do
        for _, fr in ipairs(stub.frames or {}) do
            if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, dt or 1) end
        end
    end
end

T.test("bags: the filters are words like the header tabs, hidden until the search is used", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    local f = open(ns)
    local W, Feel = ns.Window, DaylightUI.Win.Feel
    for _, b in ipairs(f.chips) do
        T.truthy(b.Pick and b.line, "a W.Tab, not a boxed chip")
        T.isnil(b.SetOn, "no chip fill")
    end
    T.falsy(f.chips[1]:IsShown(), "at rest: no filters")
    local rest, h0 = gridTop(f), f:GetHeight()
    T.eq(rest, W.TITLE + W.GAP + W.ROW + W.GAP, "and no room kept for them")
    -- Focus shows them, the window grows by their row.
    f.search:SetFocus()
    stub.RunTimers()
    T.truthy(filtersShown(f), "focus: the filters show")
    Feel.Settle(f); Feel.Settle(f.items)
    T.eq(gridTop(f), rest + DaylightUI.Widgets.TAB_H + W.GAP, "the grid moves down under them")
    T.eq(f:GetHeight(), h0 + DaylightUI.Widgets.TAB_H + W.GAP, "the window grows by their row")
    T.truthy(f.chips[1].picked, "All picked")
    -- A filter picked keeps them after the search loses focus.
    f.chips[6]:Click()
    T.eq(f.chip, "junk")
    T.truthy(f.chips[6].picked and not f.chips[1].picked, "the picked word in the accent")
    f.search:ClearFocus()
    stub.RunTimers()
    T.truthy(filtersShown(f), "a filter picked: they stay")
    -- Back to All with an empty search and no focus: they go.
    f.chips[1]:Click()
    stub.RunTimers()
    runMotion()
    T.falsy(f.chips[1]:IsShown(), "All, nothing typed: hidden again")
    Feel.Settle(f); Feel.Settle(f.items)
    T.eq(gridTop(f), rest, "and they take no room")
    T.eq(f:GetHeight(), h0)
    -- Text typed keeps them after a blur too.
    f.search:SetFocus()
    f.search:SetText("bread")
    f.search:ClearFocus()
    stub.RunTimers()
    runMotion()
    T.truthy(filtersShown(f), "text in the search: they stay")
    f.search:SetText("")
    stub.RunTimers()
    runMotion()
    T.falsy(f.chips[1]:IsShown(), "emptied without focus: they go")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the filters fade in dropping a little, the window and grid glide with them", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    local f = open(ns)
    local Feel = DaylightUI.Win.Feel
    local rest = gridTop(f)
    f.search:SetFocus()
    local b = f.chips[2]
    T.truthy(b:IsShown())
    T.truthy(b:GetAlpha() < 1, "fading in")
    T.truthy(Feel.Moving(b), "dropping in")
    T.truthy(Feel.Moving(f), "the window eases to its new size")
    T.eq(gridTop(f), rest, "the grid starts where it was")
    runMotion(30, 0.05)
    T.eq(b:GetAlpha(), 1)
    T.falsy(Feel.Moving(f.items))
    T.eq(gridTop(f), rest + DaylightUI.Widgets.TAB_H + ns.Window.GAP, "and ends under them")
    -- Going, they fade out where they are.
    f.search:ClearFocus()
    T.truthy(b:IsShown(), "fading out")
    runMotion(30, 0.05)
    T.falsy(b:IsShown(), "then gone")
    -- In a fight they come at once.
    stub.EnterCombat()
    f.search:SetFocus()
    T.truthy(b:IsShown()); T.eq(b:GetAlpha(), 1, "at once in a fight")
    T.falsy(Feel.Moving(f), "no glide in a fight")
    f.search:ClearFocus()
    T.falsy(b:IsShown(), "and go at once")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: closing hides the filters again", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    local f = open(ns)
    local rest = gridTop(f)
    f.search:SetFocus()
    ns.Window.PickChip(f, "gear")
    f:Hide()
    stub.RunTimers()
    T.falsy(f.chips[1]:IsShown(), "closed: no filters")
    T.eq(gridTop(f), rest, "the next open starts without their row")
    f:Show()
    stub.RunTimers()
    T.falsy(f.chips[1]:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

T.test("bags: a heading's name starts over its first slot, the chevron hangs to its left", function()
    local ns, f = catLogin()
    local Layout = ns.Layout
    local h
    for _, x in ipairs(f.headings) do if x:IsShown() and x.key == "weapon" then h = x end end
    T.truthy(h, "a heading for Weapons")
    local function point(r, i)
        local p, rel, rp, x, y = r:GetPoint(i or 1)
        return p, rel, rp, x, y
    end
    local p, rel, rp, x = point(h.text)
    T.eq(rel, h, "the name hangs off the heading itself")
    T.eq(p, "LEFT"); T.eq(rp, "TOPLEFT", "on the heading's text row")
    T.eq(x, 0, "and starts at its left edge, where the group's first slot starts")
    local _, hrel, _, hx = point(h)
    local first
    for _, s in ipairs(f.set.Slots()) do
        if s.button:IsShown() and s.button:GetNumPoints() == 1 then
            local _, _, _, bx, by = s.button:GetPoint(1)
            local _, _, _, ox, oy = h:GetPoint(1)
            local inset = Layout.Ref(f, f.Cfg(), Layout.REF.inset)
            if bx == ox - inset and by == oy - Layout.SlotTop(f) then first = s.button end
        end
    end
    T.truthy(first, "a slot's ring sits just outside the heading's left edge, its icon right under the name")
    local cp, crel, crp, cx = point(h.chev)
    T.eq(crel, h.text, "the chevron hangs off the name")
    T.eq(cp, "RIGHT"); T.eq(crp, "LEFT")
    T.truthy(cx < 0, "to the left of it")
    T.truthy(-cx + Layout.HEAD_CHEV <= ns.Window.EDGE + Layout.SHELF_INSET - 2, "and stays clear of the window edge")
end)

T.test("bags: the Shelf leaves room for the hanging chevron, the Grid keeps its margin", function()
    local ns, f = catLogin()
    local E = ns.Window.EDGE
    local _, _, _, x = f.items:GetPoint(1)
    T.eq(x, E + ns.Layout.SHELF_INSET, "the Shelf's items start a little in")
    T.eq(f:GetWidth(), f.items:GetWidth() + E * 2 + ns.Layout.SHELF_INSET, "the window grows by the same")
    ns.module.db.view = "grid"
    ns.Relayout()
    _, _, _, x = f.items:GetPoint(1)
    T.eq(x, E, "the Grid is unchanged")
    T.eq(f:GetWidth(), f.items:GetWidth() + E * 2)
end)

T.test("bags: a heading is underlined in its color, as wide as its group", function()
    local ns, f = catLogin()
    local Layout, INK = ns.Layout, DaylightUI.Style.INK
    local function headOf(key)
        for _, x in ipairs(f.headings) do if x:IsShown() and x.key == key then return x end end
    end
    local h = headOf("weapon")
    local c = h.rule.__color
    T.truthy(c, "a solid line")
    local gr, gg, gb = ns.Categories.Color("weapon")
    T.near(c[1], gr, 0.01); T.near(c[2], gg, 0.01); T.near(c[3], gb, 0.01)
    T.near(c[4], Layout.RULE_ALPHA, 0.001, "at about half strength")
    local lp, lrel = h.rule:GetPoint(1)
    local rp, rrel = h.rule:GetPoint(2)
    T.eq(lrel, h); T.eq(rrel, h)
    T.eq(lp, "BOTTOMLEFT"); T.eq(rp, "BOTTOMRIGHT")
    local px = DaylightUI.Pixel.Px(f.items, 1)
    T.truthy(h.rule:GetHeight() >= 2 * px - 1e-6, "never thinner than two pixels")
    T.near(h.rule:GetHeight(), Layout.LineH(f), 1e-6)
    local r, g, b, a = h.count:GetTextColor()
    T.near(r, gr, 0.01, "the count is in the group's color")
    T.truthy(a < 1, "a little dimmer")
    ns.Categories.ToggleCollapsed("weapon")
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    h = headOf("weapon")
    c = h.rule.__color
    local want = ns.Items.EMPTY
    T.near(c[1], want[1], 0.01, "folded: the plain dark line of an empty slot's ring")
    T.near(c[2], want[2], 0.01); T.near(c[3], want[3], 0.01)
    r, g, b = h.count:GetTextColor()
    T.near(r, INK.LABEL[1], 0.01, "folded: the count reads label, not accent")
    T.near(g, INK.LABEL[2], 0.01); T.near(b, INK.LABEL[3], 0.01)
    ns.Categories.ToggleCollapsed("weapon")
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
end)

T.test("bags: the line is as wide as the group even when the name is wider", function()
    local ns, f = catLogin()
    for _, h in ipairs(f.headings) do
        if h:IsShown() and not h.folded then
            local w = h:GetWidth()
            T.truthy(w >= h.text:GetStringWidth(), "the heading is at least as wide as its name")
        end
    end
end)

T.test("bags: Empty's count is the free slots, not the tiles", function()
    local ns, f = catLogin()
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    ns.Relayout()
    local h
    for _, x in ipairs(f.headings) do if x:IsShown() and x.key == "empty" then h = x end end
    T.truthy(h, "an Empty heading")
    local free, tiles = 0, 0
    for _, g in ipairs(ns.Layout.Groups(ns.module.db, f)) do
        if g.key == "empty" then
            for _, e in ipairs(g.entries) do free, tiles = free + (e.free or 1), tiles + 1 end
        end
    end
    T.truthy(free > tiles, "the free tiles stand for more slots than there are tiles")
    T.eq(h.count:GetText(), tostring(free), "and the heading says the same number")
    DaylightUI:Set("Bags", "emptySlots", "all")
    ns.Relayout()
    for _, x in ipairs(f.headings) do if x:IsShown() and x.key == "empty" then h = x end end
    T.eq(h.count:GetText(), tostring(free), "one tile per slot reads the same")
end)

T.test("bags: the corner dots' glow never spills into the next slot", function()
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
    -- The cheapest junk's dot follows the same rule.
    glow, dot = glowAt(7)
    ns.Items.PaintCheap(B.buttons[0][1], true)
    local p = Items.Parts(B.buttons[0][1])
    T.near(p.cheapGlow:GetWidth(), glow, 1e-6, "the junk dot's glow: the same size")
    DaylightUI:Set("Bags", "spacing", 2)
    stub.RunTimers()
    ns.Items.PaintCheap(B.buttons[0][1], true)
    T.near(p.cheapGlow:GetWidth(), p.cheapDot:GetWidth(), 1e-6, "and none when the slots nearly touch")
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

T.test("bags: every group has a color; the player's wins and reset brings the default back", function()
    local ns = catLogin()
    local Cat, INK = ns.Categories, DaylightUI.Style.INK
    local function is(key, c, why)
        local r, g, b = Cat.Color(key)
        T.near(r, c[1], 0.01, why); T.near(g, c[2], 0.01, why); T.near(b, c[3], 0.01, why)
    end
    is("weapon", { 0.96, 0.52, 0.42 }, "weapons")
    is("hearthstone", { 0.45, 0.72, 1.0 }, "hearthstone")
    is("misc", INK.LABEL, "misc reads label")
    is("other", INK.LABEL, "other reads label")
    is("empty", INK.LABEL, "empty reads label")
    -- The fake game answers 0.1 * quality, 0.5, 0.9.
    is("junk", { 0, 0.5, 0.9 }, "junk is the game's poor quality color")
    T.isnil(Cat.Color("recent"), "recent keeps the accent")
    local mine = Cat.AddCustom("Mine")
    is(mine, INK.TEXT, "a custom group starts soft white")
    Cat.SetColor("weapon", { 0.1, 0.2, 0.3 })
    is("weapon", { 0.1, 0.2, 0.3 }, "the player's own color")
    T.truthy(Cat.HasOwnColor("weapon"))
    Cat.SetColor(mine, { 1, 0, 0 })
    is(mine, { 1, 0, 0 }, "custom group's own color")
    Cat.ResetColor("weapon")
    is("weapon", { 0.96, 0.52, 0.42 }, "reset brings the default back")
    T.falsy(Cat.HasOwnColor("weapon"))
    Cat.DeleteCustom(mine)
    T.isnil(ns.module.db.groupColors[mine], "a deleted group's color goes with it")
end)

T.test("bags: a heading wears its group's color, folded ones read label, the rule tints", function()
    local ns, f = catLogin()
    local Cat, INK = ns.Categories, DaylightUI.Style.INK
    local function headOf(key)
        for _, x in ipairs(f.headings) do if x:IsShown() and x.key == key then return x end end
    end
    local h = headOf("weapon")
    local function is(fs, c, why)
        local r, g, b = fs:GetTextColor()
        T.near(r, c[1], 0.01, why); T.near(g, c[2], 0.01, why); T.near(b, c[3], 0.01, why)
    end
    is(h.text, { 0.96, 0.52, 0.42 }, "name")
    is(h.count, { 0.96, 0.52, 0.42 }, "count")
    T.near(h.rule.__color[1], 0.96, 0.01, "the line is in the group's color")
    Cat.SetColor("weapon", { 0.2, 0.4, 0.6 })
    ns.Relayout()
    h = headOf("weapon")
    is(h.text, { 0.2, 0.4, 0.6 }, "the player's color")
    Cat.ToggleCollapsed("weapon")
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    h = headOf("weapon")
    is(h.text, INK.LABEL, "folded: label")
    Cat.ToggleCollapsed("weapon")
    stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
end)

T.test("bags: the group menus list groups in their color and the lock row is short", function()
    local ns = login({ view = "categories" })
    categoryWorld()
    open(ns)
    ns.Relayout(); ns.FillAll()
    local Cat = ns.Categories
    local keys, values
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, k, v) keys, values = k, v end
    Cat.Menu(ns.Bags.buttons[0][1])
    DaylightUI.Widgets.OpenMenu = openMenu
    local L = DaylightUI.L
    T.eq(values.lock, L["Lock"], "a short lock row")
    local hex = DaylightUI.Win.Parts.Hex({ Cat.Color("weapon") })
    T.eq(values.weapon, hex .. Cat.Get("weapon").name .. "|r", "weapons in their color")
    T.truthy(#L["Lock"] <= 10)
end)

T.test("bags: a group's color travels in a shared string", function()
    local ns = catLogin()
    local Cat = ns.Categories
    local store = {}
    _G.C_EncodingUtil = {
        SerializeCBOR = function(v) store[#store + 1] = v; return "cbor" .. #store end,
        DeserializeCBOR = function(s) local v = store[tonumber(string.match(s, "^cbor(%d+)$") or "")]
            if not v then error("bad cbor") end; return v end,
        CompressString = function(s) return s end, DecompressString = function(s) return s end,
        EncodeBase64 = function(s) return s end, DecodeBase64 = function(s) return s end,
    }
    local a = Cat.AddCustom("Tinted")
    Cat.AddCustom("Plain")
    Cat.SetColor(a, { 0.3, 0.5, 0.7 })
    local text = Cat.Export()
    Cat.DeleteCustom(a)
    local list = Cat.ReadShared(text)
    T.eq(#list, 2)
    Cat.ImportShared(list)
    local key
    for _, g in ipairs(Cat.Custom()) do if g.name == "Tinted" then key = g.key end end
    local r, g, b = Cat.Color(key)
    T.near(r, 0.3, 0.01); T.near(g, 0.5, 0.01); T.near(b, 0.7, 0.01)
    for _, g2 in ipairs(Cat.Custom()) do
        if g2.name == "Plain" then T.falsy(Cat.HasOwnColor(g2.key), "no color shared, none set") end
    end
    _G.C_EncodingUtil = nil
end)

-- A vendor that takes what's used: the item leaves its slot and the bag updates
-- (late = the bag updates only when land() is called, as when the server is slow).
local function sellingWorld(late)
    local sold, pending = {}, {}
    C_Container.UseContainerItem = function(bag, slot)
        sold[#sold + 1] = bag .. ":" .. slot
        if late then
            pending[#pending + 1] = { bag, slot }
        else
            world.items[bag][slot] = nil
            bagChanged(bag)
        end
    end
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:2|h" or link == "|Hitem:9|h" then return "name", link, 0, 1, 1, "", "", 20, "", 1, 25, 0, 0, 0 end
        return getInfo(link)
    end
    local function land()
        for _, p in ipairs(pending) do
            world.items[p[1]][p[2]] = nil
            bagChanged(p[1])
        end
        wipe(pending)
    end
    return sold, land
end

-- The bag with a gray weapon (0:2) and apples marked as junk (1:2), free slots
-- grouped so a sold slot leaves the grid, a vendor open.
local function junkAtVendor(late, narrow)
    local ns, f = (narrow and narrowLogin or catLogin)()
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    DaylightUI:Set("Bags", "sellJunk", false)
    stub.RunTimers()
    ns.Categories.Pin(9, "junk")
    ns.Relayout()
    ns.FillAll()
    settleFeel()
    local sold, land = sellingWorld(late)
    stub.FireEvent("MERCHANT_SHOW")
    stub.RunTimers()
    return ns, f, sold, land
end

local function nothingMoves(f, what)
    local Feel = DaylightUI.Win.Feel
    for _, s in ipairs(f.set.Slots()) do T.falsy(Feel.Moving(s.button), what) end
    for _, h in ipairs(f.headings or {}) do T.falsy(Feel.Moving(h), what) end
end

T.test("bags: Sell junk fades the junk out and glides the rest up", function()
    local ns, f, sold = junkAtVendor(false, true)
    local Feel = DaylightUI.Win.Feel
    -- The weapon's slot becomes the free tile (the first free slot); the apples'
    -- slot leaves the grid.
    local gray, apple = ns.Bags.buttons[0][2], ns.Bags.buttons[1][2]
    local gx, gy = at(gray)
    local ax, ay = at(apple)
    local before = itemSpots(f)
    f.sellJunk:GetScript("OnClick")(f.sellJunk)
    T.eq(#sold, 1, "one at a time")
    T.truthy(gray:IsShown(), "mid-sale the sold slot keeps its spot")
    T.deq({ at(gray) }, { gx, gy })
    nothingMoves(f, "nothing moves mid-sale")
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(table.concat(sold, ","), "0:2,1:2")
    T.truthy(f.fading and f.fading[apple], "a sold slot fades out")
    T.truthy(apple:IsShown(), "where it was")
    T.deq({ at(apple) }, { ax, ay })
    T.truthy(f.tiles[1].button == gray and Feel.Moving(gray), "the other glides to be the free tile")
    for link, spot0 in pairs(before) do
        local b = buttonOf(f, link)
        if b then T.deq({ at(b) }, spot0, link .. " starts from where it was") end
    end
    -- Junk was the last group here: what follows it (the free slots) glides up.
    local up = 0
    for _, h in ipairs(f.headings) do
        if h:IsShown() and h.key == "empty" and Feel.Moving(h) then up = up + 1 end
    end
    T.eq(up, 1, "the free slots' heading glides up")
    local junkHead
    for _, h in ipairs(f.headings) do if h.key == "junk" then junkHead = h end end
    T.truthy(junkHead and f.fading and f.fading[junkHead], "the emptied Junk heading fades out")
    T.truthy(junkHead:IsShown() and junkHead:GetAlpha() > 0, "where it was")
    for _, h in ipairs(f.headings) do
        if h ~= junkHead and h:IsShown() then T.truthy(h.key ~= "junk", "no other heading reads Junk") end
    end
    T.truthy(Feel.Moving(f), "the window glides to its new size")
    settleFeel()
    T.falsy(apple:IsShown(), "gone once faded")
    T.falsy(junkHead:IsShown(), "and its heading")
    T.falsy(f.stale, "laid out: nothing left for the next open")
    nothingMoves(f, "all landed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: Sell junk waits for the last sale to leave the bag", function()
    local ns, f, sold, land = junkAtVendor(true)
    local Feel = DaylightUI.Win.Feel
    local apple = ns.Bags.buttons[1][2]
    local ax, ay = at(apple)
    f.sellJunk:GetScript("OnClick")(f.sellJunk)
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(#sold, 2)
    T.falsy(f.fading and f.fading[apple], "the server hasn't answered: nothing closes up yet")
    T.deq({ at(apple) }, { ax, ay })
    land()
    T.truthy(apple:IsShown() and f.stale, "the sold slots hold their spots")
    stub.RunTimers()
    T.truthy(f.fading and f.fading[apple], "landed: now it closes up")
    settleFeel()
    nothingMoves(f, "settled")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    -- A sale that never lands is let go after SETTLE.
    ns, f, sold = junkAtVendor(true)
    local gray = ns.Bags.buttons[0][2]
    f.sellJunk:GetScript("OnClick")(f.sellJunk)
    for _ = 1, 5 do stub.RunTimers() end
    local laid = 0
    local relayout = ns.Window.EaseRelayout
    ns.Window.EaseRelayout = function(...) laid = laid + 1 return relayout(...) end
    stub.RunTimers()
    T.eq(laid, 0, "still waiting")
    stub.Advance(ns.Junk.SETTLE)
    stub.RunTimers()
    ns.Window.EaseRelayout = relayout
    T.eq(laid, 1, "then lays out once")
    T.falsy(Feel.Moving(gray))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a right-click sell still holds the spot", function()
    local ns, f = junkAtVendor()
    local spots = {}
    for _, s in ipairs(f.set.Slots()) do
        if s.button:IsShown() then spots[s.button] = { at(s.button) } end
    end
    local weapon = ns.Bags.buttons[0][1]
    -- What the game's right-click does at a vendor.
    C_Container.UseContainerItem(0, 1)
    for _ = 1, 5 do stub.RunTimers() end
    T.truthy(weapon:IsShown(), "the sold slot stays")
    for b, spot0 in pairs(spots) do T.deq({ at(b) }, spot0, "nothing else moved") end
    nothingMoves(f, "no glide")
    T.falsy(f.fading and next(f.fading), "nothing fades")
    T.truthy(f.stale, "the next open lays it out")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Ticket: after selling junk the Junk group kept its emptied spots until the
-- bag was closed and opened again. A sale Daylight UI didn't start (the game's
-- own vendor button, another vendor addon) and right-click sales hold their
-- spots while the vendor is open; walking away closes them up.
T.test("bags: spots held at a vendor close up when the vendor closes", function()
    local ns, f = junkAtVendor()
    local gray, weapon = ns.Bags.buttons[0][2], ns.Bags.buttons[0][1]
    -- The game's sell-all: every gray item goes at once, nothing of Daylight UI's asked.
    world.items[0][2] = nil
    bagChanged(0)
    -- And one more sold by right-click.
    C_Container.UseContainerItem(0, 1)
    for _ = 1, 5 do stub.RunTimers() end
    T.truthy(f.stale, "held while the vendor is open")
    T.truthy(weapon:IsShown(), "the right-clicked slot keeps its spot")
    local laid = 0
    local relayout = ns.Window.EaseRelayout
    ns.Window.EaseRelayout = function(...) laid = laid + 1 return relayout(...) end
    stub.FireEvent("MERCHANT_CLOSED")
    for _ = 1, 3 do stub.RunTimers() end
    ns.Window.EaseRelayout = relayout
    T.eq(laid, 1, "the vendor closed: one eased layout")
    T.falsy(f.stale, "no reopen needed")
    T.truthy(DaylightUI.Win.Feel.Moving(gray) or (f.fading and f.fading[gray]), "the emptied spot moves off, eased")
    settleFeel()
    nothingMoves(f, "settled")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: more than EASE_MAX moves cross-fade instead", function()
    local ns = login()
    local L, Motion = ns.Layout, DaylightUI.Motion
    T.eq(L.EASE_MAX, 60)
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    stub.RunTimers()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local ok, err = pcall(function()
        L.EASE_MAX = 2
        local gray = ns.Bags.buttons[0][2]
        local x0, y0 = at(gray)
        world.items[0][1] = nil
        easedRelayout(ns)
        nothingMoves(f, "no slot glides")
        T.truthy(f.crossing, "the grid cross-fades")
        T.deq({ at(gray) }, { x0, y0 }, "the old picture fades out where it was")
        stub.RunOnUpdate(Motion.Driver(), Motion.FAST + 0.01)
        T.truthy(at(gray) < x0, "then each piece is at its new spot")
        T.truthy(f.items:GetAlpha() < 0.5, "fading back in")
        stub.RunOnUpdate(Motion.Driver(), Motion.NORMAL + 0.01)
        T.eq(f.items:GetAlpha(), 1)
        T.isnil(f.crossing, "done")
        -- A layout made mid-way lands the cross-fade first.
        world.items[0][1] = { iconFileID = 101, stackCount = 5, quality = 3, hyperlink = "|Hitem:1|h" }
        easedRelayout(ns)
        T.truthy(f.crossing)
        stub.RunOnUpdate(Motion.Driver(), Motion.FAST / 2)
        local mid = f.items:GetAlpha()
        T.truthy(mid < 1, "half faded")
        L.EASE_MAX = 60
        world.items[0][1] = nil
        easedRelayout(ns)
        T.isnil(f.crossing, "the new layout glides")
        T.truthy(f.items:GetAlpha() <= mid, "the grid comes back from where it was, no snap")
        L.EASE_MAX = 2
        settleFeel()
        T.eq(f.items:GetAlpha(), 1)
        T.isnil(f.crossing)
        T.truthy(at(gray) < x0, "where the last layout put it")
        -- Few moves still glide.
        L.EASE_MAX = 60
        world.items[0][1] = { iconFileID = 101, stackCount = 5, quality = 3, hyperlink = "|Hitem:1|h" }
        easedRelayout(ns)
        T.isnil(f.crossing)
        T.truthy(DaylightUI.Win.Feel.Moving(gray), "glides")
        settleFeel()
    end)
    L.EASE_MAX = 60
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: combat mid-glide settles everything at once", function()
    local ns, f = narrowLogin()
    local Feel, L = DaylightUI.Win.Feel, ns.Layout
    settleFeel()
    local function click(key)
        for _, h in ipairs(f.headings) do
            if h:IsShown() and h.key == key then return h:GetScript("OnClick")(h, "LeftButton") end
        end
    end
    -- Fold a group, then open it again: its items fade in, the rest glide, the window resizes.
    click("junk")
    settleFeel()
    click("junk")
    local bread = ns.Bags.buttons[0][2]
    T.truthy(bread:GetAlpha() < 1, "an opened group's items are fading in")
    T.truthy(Feel.Moving(f), "the window is resizing")
    local glided = false
    for _, s in ipairs(f.set.Slots()) do glided = glided or Feel.Moving(s.button) end
    T.truthy(glided, "slots glide")
    stub.EnterCombat()
    nothingMoves(f, "a fight lands every glide")
    T.falsy(Feel.Moving(f), "and the window's size")
    T.eq(bread:GetAlpha(), 1, "fading pieces are whole")
    stub.LeaveCombat()
    stub.RunTimers()
    -- Folding again: the folded group's items fade out where they were.
    click("junk")
    T.truthy(f.fading and f.fading[bread], "fading out")
    stub.EnterCombat()
    T.falsy(bread:IsShown(), "gone at once")
    T.falsy(f.fading and next(f.fading))
    stub.LeaveCombat()
    stub.RunTimers()
    -- A cross-fade lands too.
    local ok, err = pcall(function()
        L.EASE_MAX = 0
        click("junk")
        T.truthy(f.crossing)
        stub.EnterCombat()
        T.isnil(f.crossing)
        T.eq(f.items:GetAlpha(), 1, "the grid shows whole")
    end)
    L.EASE_MAX = 60
    stub.LeaveCombat()
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: motion off lays out at once", function()
    local ns, f, sold = junkAtVendor()
    local Feel = DaylightUI.Win.Feel
    local apple = ns.Bags.buttons[1][2]
    DaylightUI.DB.General().motion = false
    local ok, err = pcall(function()
        f.sellJunk:GetScript("OnClick")(f.sellJunk)
        for _ = 1, 5 do stub.RunTimers() end
        T.eq(#sold, 2)
        T.falsy(apple:IsShown(), "the sold slot is gone at once")
        T.falsy(f.fading and next(f.fading), "nothing fades")
        nothingMoves(f, "nothing glides")
        T.falsy(Feel.Moving(f), "the window takes its size at once")
        T.isnil(f.crossing)
        T.falsy(f.stale)
    end)
    DaylightUI.DB.General().motion = true
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the NPC window's own Sell junk closes up the bag too", function()
    local ns, f = junkAtVendor()
    local Feel = DaylightUI.Win.Feel
    -- The game's sale: every gray item goes, a moment later.
    C_MerchantFrame = C_MerchantFrame or {}
    local gray = ns.Bags.buttons[0][2]
    local laid = 0
    local relayout = ns.Window.EaseRelayout
    ns.Window.EaseRelayout = function(...) laid = laid + 1 return relayout(...) end
    local ok, err = pcall(function()
        T.falsy(DaylightUI.SellJunkAroundLocks(), "nothing locked: the game sells")
        T.eq(laid, 0)
        world.items[0][2] = nil
        bagChanged(0)
        T.truthy(f.stale, "the sold slot holds its spot first")
        for _ = 1, 3 do stub.RunTimers() end
        T.eq(laid, 1, "then one eased layout")
        T.falsy(f.stale)
        T.truthy(Feel.Moving(gray), "the emptied slot glides to the free tile")
        settleFeel()
    end)
    ns.Window.EaseRelayout = relayout
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: hovering Lock in the item menu says what it does, leaving hides it", function()
    local ns, f = catLogin()
    local W = DaylightUI.Widgets
    local btn = ns.Bags.buttons[0][4]
    local said, addLine = {}, GameTooltip.AddLine
    GameTooltip.AddLine = function(self, text, ...) said[#said + 1] = text; return addLine(self, text, ...) end
    local function lockRow()
        for i = 1, 30 do
            local r = W.MenuRow(i)
            if not r then return end
            if r.key == "lock" then return r end
        end
    end
    GameTooltip:Hide()
    ns.Categories.Menu(btn)
    local r = lockRow()
    T.truthy(r, "the menu has a Lock row")
    r:GetScript("OnEnter")(r)
    T.truthy(GameTooltip:IsShown(), "hovering Lock shows a tip")
    local text = table.concat(said, "\n")
    T.truthy(text:find(DaylightUI.L["Never sold or disenchanted."], 1, true), "it says what Lock does: " .. text)
    r:GetScript("OnLeave")(r)
    T.falsy(GameTooltip:IsShown(), "leaving the row hides it")
    -- Hovering another row hides it too, and closing the menu.
    r:GetScript("OnEnter")(r)
    T.truthy(GameTooltip:IsShown())
    local other = W.MenuRow(2)
    if other and other ~= r then
        other:GetScript("OnEnter")(other)
        T.falsy(GameTooltip:IsShown(), "another row: no Lock tip")
        r:GetScript("OnEnter")(r)
    end
    W.CloseMenu()
    T.falsy(GameTooltip:IsShown(), "closing the menu hides it")
    -- Locked, the row says Unlock and what that does.
    ns.Categories.ToggleLock(C_Container.GetContainerItemInfo(0, 4).itemID)
    stub.RunTimers()
    wipe(said)
    ns.Categories.Menu(btn)
    r = lockRow()
    r:GetScript("OnEnter")(r)
    T.truthy(table.concat(said, "\n"):find(DaylightUI.L["Can be sold again."], 1, true), "Unlock says what it does")
    W.CloseMenu()
    GameTooltip.AddLine = addLine
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a heading, a filter, the tools and the search end a cleanup's hold at once", function()
    local ns, f = catLogin()
    settleFeel()
    local function hold(what)
        f.sort:GetScript("OnClick")(f.sort)
        sortStep(1, 4)
        T.truthy(f.sorting, what .. ": held")
    end
    hold("heading")
    local h
    for _, x in ipairs(f.headings) do
        if x:IsShown() and x.key then h = x break end
    end
    local key = h.key
    h:GetScript("OnClick")(h, "LeftButton")
    T.isnil(f.sorting, "a heading click lets go")
    T.truthy(ns.Categories.IsCollapsed(key), "the group folds")
    T.truthy(h.folded, "and its heading shows folded at once")
    T.truthy(filledRight(f), "every slot shows its real item")
    ns.Categories.ToggleCollapsed(key)
    settleFeel()
    hold("filter")
    f.chips[6]:Click()
    T.isnil(f.sorting, "a filter word lets go")
    f.chips[1]:Click()
    settleFeel()
    hold("view")
    f.viewButton:GetScript("OnClick")(f.viewButton, "LeftButton")
    T.isnil(f.sorting, "Shelf or grid lets go")
    settleFeel()
    hold("slots")
    f.slotsButton:GetScript("OnClick")(f.slotsButton, "LeftButton")
    T.isnil(f.sorting, "the slots tool lets go")
    settleFeel()
    hold("focus")
    f.search:SetFocus()
    T.isnil(f.sorting, "clicking into the search lets go")
    f.search:ClearFocus()
    settleFeel()
    hold("typing")
    local held
    local parse = ns.Search.Parse
    ns.Search.Parse = function(t) held = f.sorting ~= nil; return parse(t) end
    f.search:SetText("bread")
    ns.Search.Parse = parse
    T.isnil(f.sorting, "typing lets go")
    T.eq(held, false, "before the search matches anything")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the filters go once the mouse leaves them after Escape left the search", function()
    local ns = login({ view = "grid" })
    categoryWorld()
    local f = open(ns)
    local chip = f.chips[3]
    f.search:SetFocus()
    stub.RunTimers()
    T.truthy(filtersShown(f))
    chip.IsMouseOver = function() return true end
    f.search:ClearFocus()   -- Escape with the mouse resting on a filter word
    stub.RunTimers()
    T.truthy(filtersShown(f), "the mouse on a word: they wait")
    chip.IsMouseOver = function() return false end
    chip:GetScript("OnLeave")(chip)
    stub.RunTimers()
    runMotion(30, 0.05)
    T.falsy(chip:IsShown(), "the mouse left: they go")
    chip.IsMouseOver = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Move what you searched for: the matches go where a right-click would send them.
local function moveWorld(opts)
    -- The client's switch for the mail's send page, there before any addon loads.
    _G.SetSendMailShowing = _G.SetSendMailShowing or function() end
    local ns = opts and opts.bank and bankLogin() or login()
    world.items[0][1].itemName, world.items[0][1].itemID = "Copper Ore", 1
    world.items[0][4].itemName, world.items[0][4].itemID = "Copper Bar", 4
    world.items[0][5].itemName = "Linen Cloth"
    local used = {}
    C_Container.UseContainerItem = function(bag, slot)
        used[#used + 1] = bag .. ":" .. slot
        world.items[bag][slot] = nil
        bagChanged(bag)
    end
    local f = open(ns)
    f.search:SetText("copper")
    stub.RunTimers()
    return ns, f, used
end

local function moveButton(f)
    runMotion(20, 0.05)
    for _, b in ipairs({ f.move, f.moveSell }) do
        if b and b:IsShown() and b:GetAlpha() > 0 then return b end
    end
end

local function runMoves()
    for _ = 1, 20 do stub.Advance(0.2); stub.RunTimers() end
end

T.test("bags: Move what you searched for shows while searching with a trade open", function()
    local ns, f, used = moveWorld()
    T.falsy(moveButton(f), "nowhere to move to: no button")
    local offered = {}
    _G.GetTradePlayerItemLink = function(i) return offered[i] end
    stub.FireEvent("TRADE_SHOW")
    stub.RunTimers()
    local b = moveButton(f)
    T.truthy(b, "a trade open: the button")
    T.eq(b.text:GetText(), "Move 2 to trade")
    T.eq(select(2, b:GetPoint(1)), f, "on the filter row")
    b:GetScript("OnClick")(b)
    runMoves()
    T.eq(table.concat(used, ","), "0:1,0:4", "each match, as a right-click would")
    T.falsy(moveButton(f), "nothing left to move")
    stub.FireEvent("TRADE_CLOSED")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: Move what you searched for moves only what fits", function()
    local ns, f, used = moveWorld()
    local offered = { "a", "b", "c", "d", "e" }
    _G.GetTradePlayerItemLink = function(i) return offered[i] end
    stub.FireEvent("TRADE_SHOW")
    stub.RunTimers()
    T.eq(moveButton(f).text:GetText(), "Move 1 to trade", "one trade slot left")
    offered[6] = "f"
    stub.FireEvent("TRADE_PLAYER_ITEM_CHANGED", 6)
    stub.RunTimers()
    runMotion(20, 0.05)
    T.falsy(moveButton(f), "a full trade: no button")
    stub.FireEvent("TRADE_CLOSED")
    stub.RunTimers()
    -- The send page of the mail: the client takes right-clicked items while it shows.
    local attached = {}
    _G.HasSendMailItem = function(i) return attached[i] == true end
    stub.FireEvent("MAIL_SHOW")
    stub.RunTimers()
    T.falsy(moveButton(f), "the inbox: nothing takes items")
    SetSendMailShowing(true)
    stub.RunTimers()
    T.eq(moveButton(f).text:GetText(), "Move 2 to mail")
    for i = 1, 11 do attached[i] = true end
    stub.FireEvent("MAIL_SEND_INFO_UPDATE")
    stub.RunTimers()
    T.eq(moveButton(f).text:GetText(), "Move 1 to mail", "one attachment left")
    local b = moveButton(f)
    b:GetScript("OnClick")(b)
    runMoves()
    T.eq(#used, 1, "only what fits")
    SetSendMailShowing(false)
    stub.FireEvent("MAIL_CLOSED")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: Move what you searched for sells at a vendor on a second click", function()
    local ns, f, used = moveWorld()
    world.sets = {}   -- an equipment set item would be kept back
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:1|h" or link == "|Hitem:4|h" then return "name", link, 2, 1, 1, "", "", 20, "", 1, 25, 0, 0, 0 end
        return getInfo(link)
    end
    stub.FireEvent("MERCHANT_SHOW")
    stub.RunTimers()
    local b = moveButton(f)
    T.eq(b, f.moveSell)
    T.eq(b.text:GetText(), "Sell 2")
    b:GetScript("OnClick")(b)
    T.eq(#used, 0, "the first click only asks")
    T.eq(b.text:GetText(), "Click again")
    stub.Advance(1)
    b:GetScript("OnClick")(b)
    runMoves()
    T.eq(table.concat(used, ","), "0:1,0:4", "sold")
    stub.FireEvent("MERCHANT_CLOSED")
    C_Item.GetItemInfo = getInfo
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: Move what you searched for keeps locked and priceless items from the vendor", function()
    local ns, f, used = moveWorld()
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:1|h" then return "name", link, 2, 1, 1, "", "", 20, "", 1, 25, 0, 0, 0 end
        return getInfo(link)
    end
    world.items[0][4].hasNoValue = true
    stub.FireEvent("MERCHANT_SHOW")
    stub.RunTimers()
    T.eq(moveButton(f).text:GetText(), "Sell 1", "no price: not sold")
    ns.Categories.ToggleLock(1)
    stub.RunTimers()
    runMotion(20, 0.05)
    T.falsy(moveButton(f), "locked: kept")
    stub.FireEvent("MERCHANT_CLOSED")
    C_Item.GetItemInfo = getInfo
end)

T.test("bags: Move what you searched for sends matches to the open bank", function()
    local ns, f, used = moveWorld({ bank = true })
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local b = moveButton(f)
    T.eq(b and b.text:GetText(), "Move 2 to bank")
    b:GetScript("OnClick")(b)
    runMoves()
    T.eq(table.concat(used, ","), "0:1,0:4")
    stub.FireEvent("BANKFRAME_CLOSED")
    stub.RunTimers()
    f.search:SetText("linen")
    stub.RunTimers()
    T.falsy(moveButton(f), "the bank closed: gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Bag addons whose Baganator support lives inside Baganator itself, or only wakes
-- when Baganator is really loaded, are hooked up by Daylight UI directly.
local function loadAddon(name)
    stub.FireEvent("ADDON_LOADED", name)
    stub.RunTimers()
end

T.test("bags: Pawn's upgrade arrows show on gear and answer the upgrade search", function()
    local ns, f = catLogin()
    local registered
    _G.PawnRegisterThirdPartyBag = function(name, o) registered = { name = name, o = o } end
    _G.PawnShouldItemLinkHaveUpgradeArrow = function(link) return link == "|Hitem:6|h" end
    loadAddon("Pawn")
    ns.FillAll()
    stub.RunTimers()
    local P, B = ns.Plugins, ns.Bags
    local armor, weapon = P.Widget(B.buttons[0][5], "pawn"), P.Widget(B.buttons[0][1], "pawn")
    T.truthy(armor and armor:IsShown(), "the upgrade gets Pawn's arrow")
    T.eq((armor:GetPoint(1)), "TOPLEFT", "top left, as in Baganator")
    T.falsy(weapon and weapon:IsShown(), "gear that isn't an upgrade: none")
    T.truthy(P.IsUpgrade("|Hitem:6|h"), "the upgrade search asks Pawn")
    T.eq(registered and registered.name, "Daylight UI", "Pawn knows these bags")
    T.eq(type(registered.o.RefreshAll), "function", "so it refreshes them when gear or scales change")
    _G.PawnRegisterThirdPartyBag, _G.PawnShouldItemLinkHaveUpgradeArrow = nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Caerdon Wardrobe, BetterBags and BaudBag list Pawn as an optional dependency
-- and sort before DaylightUI_Bags, so the client loads Pawn first. The hook then
-- runs while the bags' own files are still loading.
T.test("bags: Pawn loaded before the bags still hooks up, with no error at load", function()
    local registered
    _G.PawnRegisterThirdPartyBag = function(name, o) registered = { name = name, o = o } end
    _G.PawnShouldItemLinkHaveUpgradeArrow = function(link) return link == "|Hitem:6|h" end
    stub.Load({ bags = true, before = function()
        setup()
        categoryWorld()
        stub.loadedAddOns.Pawn = true
    end })
    stub.RunTimers()
    local ns = stub.bags
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(registered and registered.name, "Daylight UI", "Pawn knows these bags")
    T.eq(type(ns.Search.KEYWORDS.upgrade), "function", "the upgrade search word is there")
    T.truthy(ns.Plugins.IsUpgrade("|Hitem:6|h"), "and asks Pawn")
    _G.PawnRegisterThirdPartyBag, _G.PawnShouldItemLinkHaveUpgradeArrow = nil, nil
end)

T.test("bags: Can I Mog It marks show on gear, told the bag and slot", function()
    local ns, f = catLogin()
    local asked = {}
    _G.CIMI_AddToFrame = function(btn)
        local o = CreateFrame("Frame", nil, btn)
        o.CIMIIconTexture = o:CreateTexture(nil, "OVERLAY")
        btn.CanIMogItOverlay = o
    end
    _G.CIMI_SetIcon = function(frame, _, text) frame.cimiText = text end
    _G.CanIMogIt = { GetTooltipText = function(_, link, bag, slot)
        asked[#asked + 1] = { link, bag, slot }
        return "Learned"
    end, RegisterMessage = function() end }
    loadAddon("CanIMogIt")
    ns.FillAll()
    stub.RunTimers()
    local P, B = ns.Plugins, ns.Bags
    local w = P.Widget(B.buttons[0][1], "can_i_mog_it")
    T.truthy(w and w:IsShown(), "a weapon gets its mark")
    T.eq(w.cimiText, "Learned")
    T.eq((w:GetPoint(1)), "TOPRIGHT")
    local bread = P.Widget(B.buttons[0][8], "can_i_mog_it")
    T.falsy(bread and bread:IsShown(), "food: nothing to collect")
    local found = false
    for _, a in ipairs(asked) do if a[1] == "|Hitem:1|h" and a[2] == 0 and a[3] == 1 then found = true end end
    T.truthy(found, "asked with the item's bag and slot")
    _G.CIMI_AddToFrame, _G.CIMI_SetIcon, _G.CanIMogIt = nil, nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: Simple Item Levels shows its item level and answers the upgrade search", function()
    local ns, f = catLogin()
    _G.SimpleItemLevel = { API = {
        ItemLevel = function(link) return link == "|Hitem:1|h" and 17 or nil end,
        ItemIsUpgrade = function(link) return link == "|Hitem:1|h" end,
    } }
    loadAddon("SimpleItemLevel")
    ns.FillAll()
    stub.RunTimers()
    local P, B = ns.Plugins, ns.Bags
    local w = P.Widget(B.buttons[0][1], "simpleitemlevel-ilvl")
    T.truthy(w and w:IsShown(), "gear with a level shows it")
    T.eq(w:GetText(), "17")
    T.truthy(P.IsUpgrade("|Hitem:1|h"))
    T.falsy(P.IsUpgrade("|Hitem:6|h"))
    _G.SimpleItemLevel = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: Caerdon Wardrobe draws through a Daylight UI feature of its own", function()
    local ns, f = catLogin()
    local features, updates = {}, {}
    _G.CaerdonItem = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.CaerdonWardrobe = {
        RegisterFeature = function(self, m) features[m:GetName()] = setmetatable({}, { __index = m }) end,
        GetFeature = function(self, name) return features[name] end,
        UpdateButton = function(self, btn, item, feature, where)
            updates[#updates + 1] = { btn = btn, item = item, feature = feature, where = where }
            if not btn.caerdon then
                btn.caerdon = { mogStatus = CreateFrame("Frame", nil, btn), bindsOnText = btn:CreateFontString() }
            end
        end,
        GetCaerdonButton = function(self, btn) return btn.caerdon end,
    }
    loadAddon("CaerdonWardrobe")
    ns.FillAll()
    stub.RunTimers()
    T.truthy(features["Daylight UI"], "registered as one of its bag features")
    local P, B = ns.Plugins, ns.Bags
    local w = P.Widget(B.buttons[0][1], "caerdon_wardrobe_status")
    T.truthy(w and w:IsShown(), "its status shows on an item")
    local told = false
    for _, u in ipairs(updates) do
        if u.btn == B.buttons[0][1] and u.item and u.where and u.where.bag == 0 and u.where.slot == 1 then
            told = u.feature == features["Daylight UI"]
        end
    end
    T.truthy(told, "updated with the item, its slot and the Daylight UI feature")
    _G.CaerdonItem, _G.CaerdonWardrobe = nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a corner asked for as default_position is honored, and plugins get itemLocation", function()
    local ns = login()
    local seen
    local init, update = upArrow(function(d) seen = seen or d; return true end)
    Baganator.API.RegisterCornerWidget("Low", "low", update, init, { default_position = "bottom_left", priority = 1 })
    open(ns)
    stub.RunTimers()
    local w = ns.Plugins.Widget(ns.Bags.buttons[0][1], "low")
    T.eq((w:GetPoint(1)), "BOTTOMLEFT")
    T.eq(seen.itemLocation and seen.itemLocation.bagID, seen.bagID)
    T.eq(seen.itemLocation.slotIndex, seen.slotID)
    _G.Baganator = nil
end)

-- The list view: the Shelf's groups as headings, a row per item under each.
local function listLogin()
    local ns, f = catLogin()
    DaylightUI:Set("Bags", "view", "list")
    stub.RunTimers()
    return ns, f
end

local function rowsOf(f)
    local out = {}
    for _, s in ipairs(f.set.Slots()) do
        local b = s.button
        if b:IsShown() and b.dluiRow and b.dluiRow:IsShown() then
            local _, _, _, x, y = b:GetPoint(1)
            out[#out + 1] = { b = b, x = x, y = -y, row = b.dluiRow }
        end
    end
    table.sort(out, function(a, b) return a.y < b.y end)
    return out
end

local function headingY(f, key)
    for _, h in ipairs(f.headings or {}) do
        if h:IsShown() and h.key == key then return -select(5, h:GetPoint(1)) end
    end
end

T.test("bags: the list view puts a row per item under its group's heading", function()
    local ns, f = listLogin()
    local L = ns.Layout
    L.ListView = function() return 10000 end
    ns.Relayout()
    local rows = rowsOf(f)
    T.truthy(#rows >= 6, "a row per shown item: " .. #rows)
    local icon = L.ListIcon(f.Cfg())
    local width = f.items:GetWidth()
    for i, r in ipairs(rows) do
        T.eq(r.x, width - r.row:GetWidth(), "rows start at the left edge, past the chevrons' room")
        T.eq(r.b:GetWidth(), icon, "the slot stays square, at the row's height")
        local hit = r.b.__hitRect
        T.deq(hit, { 0, -(r.row:GetWidth() - icon), 0, 0 }, "its click area covers the whole row")
        if i > 1 then T.truthy(r.y >= rows[i - 1].y + icon, "rows never overlap") end
    end
    -- Every group's rows sit under its heading and above the next one.
    local groups = ns.Layout.Groups(f.Cfg(), f)
    local tops = {}
    for _, g in ipairs(groups) do tops[#tops + 1] = { key = g.key, y = headingY(f, g.key), g = g } end
    table.sort(tops, function(a, b) return a.y < b.y end)
    for i, t in ipairs(tops) do
        local below = tops[i + 1] and tops[i + 1].y or math.huge
        for _, e in ipairs(t.g.entries) do
            local _, _, _, _, y = e.button:GetPoint(1)
            T.truthy(-y > t.y and -y < below, t.key .. ": its rows under its heading")
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: list rows read name, kind, level, count and sell value", function()
    local ns, f = listLogin()
    local B = ns.Bags
    local getInfo, instant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
    C_Item.GetItemInfo = function(link)
        if link == "|Hitem:8|h" then return "Bread", link, 1, 5, 1, "Consumable", "Food", 20, "", 1, 25, 0, 0, 0 end
        return getInfo(link)
    end
    C_Item.GetItemInfoInstant = function(id)
        local itemID = type(id) == "number" and id or tonumber(string.match(tostring(id), "item:(%d+)"))
        return itemID, itemID == 8 and "Consumable" or "", "", "", 0, world.class[itemID], 0
    end
    ns.Relayout()
    ns.FillAll()
    local row = B.buttons[0][8].dluiRow
    T.eq(row.name:GetText(), "Bread")
    T.eq(row.kind:GetText(), "Consumable")
    T.eq(row.count:GetText(), "12", "both stacks of bread, combined")
    T.truthy(row.value:GetText():find("3", 1, true), "12 x 25 copper: " .. tostring(row.value:GetText()))
    T.eq(row.level:GetText(), "", "no item level on food")
    C_Item.GetItemInfo, C_Item.GetItemInfoInstant = getInfo, instant
end)

T.test("bags: a sold item's list row no longer reads its name", function()
    local ns, f = listLogin()
    world.items[0][9] = { iconFileID = 109, stackCount = 1, quality = 1, hyperlink = "|Hitem:777|h", itemID = 777, itemName = "Iron Star" }
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    ns.Relayout()
    local b = ns.Bags.buttons[0][9]
    T.truthy(b.dluiRow and b.dluiRow:IsShown(), "the item has a row")
    T.eq(b.dluiRow.name:GetText(), "Iron Star")
    -- sold to a vendor: the slot empties, items only leaving hold their spots
    world.items[0][9] = nil
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    -- The row keeps its spot until the next layout, and reads the slot again
    -- each time it's painted (the slot's fill paints it).
    ns.Layout.PaintRow(b)
    T.eq(b.dluiRow.name:GetText(), "", "the row reads blank, not the sold item")
    T.eq(b.dluiRow.count:GetText(), "")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: list columns sort inside each group, a second click flips", function()
    local ns, f = listLogin()
    local head = f.listHead
    T.truthy(head and head:IsShown(), "column heads over the rows")
    world.items[0][9] = { iconFileID = 109, stackCount = 1, quality = 1, hyperlink = "|Hitem:9|h", itemID = 9, itemName = "Apple" }
    world.items[0][10] = { iconFileID = 108, stackCount = 2, quality = 1, hyperlink = "|Hitem:11|h", itemID = 11, itemName = "Cheese" }
    world.class[11] = 0
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    local function order()
        local names = {}
        for _, r in ipairs(rowsOf(f)) do
            for _, g in ipairs(ns.Layout.Groups(f.Cfg(), f)) do
                if g.key == "consumable" then
                    for _, e in ipairs(g.entries) do if e.button == r.b then names[#names + 1] = r.row.name:GetText() end end
                end
            end
        end
        return table.concat(names, ",")
    end
    head.cells.name:GetScript("OnClick")(head.cells.name)
    stub.RunTimers()
    T.eq(DaylightUI:Get("Bags", "listSort"), "name")
    T.eq(order(), "Apple,Bread,Cheese", "by name")
    head.cells.name:GetScript("OnClick")(head.cells.name)
    stub.RunTimers()
    T.eq(order(), "Cheese,Bread,Apple", "flipped")
    head.cells.count:GetScript("OnClick")(head.cells.count)
    stub.RunTimers()
    T.eq(order(), "Bread,Apple,Cheese", "by count, most first (12, 3 with the other stack, 2)")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a folded group in the list is its heading alone; leaving the list squares the slots again", function()
    local ns, f = listLogin()
    local B = ns.Bags
    local bread = B.buttons[0][8]
    T.truthy(bread.dluiRow:IsShown())
    ns.Categories.ToggleCollapsed("consumable")
    stub.RunTimers()
    T.falsy(bread:IsShown() and bread:GetAlpha() > 0 and bread.dluiRow:IsShown() and not (f.fading and f.fading[bread]),
        "its rows go")
    ns.Categories.ToggleCollapsed("consumable")
    stub.RunTimers()
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    for _, s in ipairs(f.set.Slots()) do
        local b = s.button
        T.deq(b.__hitRect or { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, "square click areas again")
        T.falsy(b.dluiRow and b.dluiRow:IsShown(), "no row text")
    end
    T.falsy(f.listHead:IsShown(), "no column heads")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: list columns fit their headings and their widest words", function()
    local ns, f = listLogin()
    local instant = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(id)
        local itemID = type(id) == "number" and id or tonumber(string.match(tostring(id), "item:(%d+)"))
        return itemID, "Miscellaneous", "", "", 0, world.class[itemID], 0
    end
    ns.Relayout()
    local head = f.listHead
    for id, cell in pairs(head.cells) do
        if id ~= "icon" and id ~= "name" then
            T.truthy(cell:GetWidth() >= cell.text:GetStringWidth() + DaylightUI.Widgets.SORT_ARROW + 4,
                id .. ": its heading whole with the chevron")
        end
    end
    T.truthy(head.cells.kind:GetWidth() >= #"Miscellaneous" * 7, "the kind column fits its widest word")
    local row = ns.Bags.buttons[0][8].dluiRow
    T.truthy(row.name:GetWidth() >= ns.Layout.LIST_NAME_MIN, "a name keeps its room")
    C_Item.GetItemInfoInstant = instant
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a long list stops growing and scrolls, its column heads staying put", function()
    local ns, f = listLogin()
    local L = ns.Layout
    local view = L.ListView
    L.ListView = function() return 80 end
    ns.Relayout()
    T.eq(f.items:GetHeight(), 80, "the list's room stops at its height")
    T.truthy(f.listContent > 80, "more rows than that: " .. tostring(f.listContent))
    T.truthy(f.items.__clips, "rows past the room are cut off")
    T.truthy(f.items.__wheel, "the wheel scrolls it")
    local first = rowsOf(f)[1]
    local y0 = first.y
    local headY = select(5, f.listHead:GetPoint(1))
    f.listBar.To(30)
    T.eq(f.listOffset, 30)
    local _, _, _, _, y = first.b:GetPoint(1)
    T.eq(-y, y0 - 30, "rows move up")
    T.eq(select(5, f.listHead:GetPoint(1)), headY, "the column heads stay")
    for _, s in ipairs(f.set.Slots()) do
        local b = s.button
        if b:IsShown() and b.dluiEntry then
            local _, _, _, _, by = b:GetPoint(1)
            T.truthy(-by + b:GetHeight() > 0 and -by < 80, "only rows in view are shown")
            local hit = b.__hitRect
            T.truthy(hit[3] >= 0 and hit[4] >= 0, "a cut row clicks only where it shows")
        end
    end
    f.listBar.To(10000)
    T.eq(f.listOffset, f.listContent - 80, "never past the end")
    f.items:GetScript("OnMouseWheel")(f.items, 1)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    T.truthy(f.listOffset < f.listContent - 80, "the wheel scrolls back up: " .. f.listOffset .. " of " .. f.listContent)
    L.ListView = function() return 10000 end
    ns.Relayout()
    T.eq(f.listOffset, 0, "a list that fits sits at its top")
    T.eq(f.items:GetHeight(), f.listContent)
    L.ListView = view
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    T.falsy(f.items.__clips, "the Shelf never cuts its slots")
    T.falsy(f.items.__wheel)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the view button goes Shelf, Grid, List and round again", function()
    local ns, f = catLogin()
    local b = f.viewButton
    local seen = {}
    for _ = 1, 3 do
        b:GetScript("OnClick")(b)
        stub.RunTimers()
        seen[#seen + 1] = DaylightUI:Get("Bags", "view")
    end
    T.eq(table.concat(seen, ","), "grid,list,categories")
end)

T.test("bags: a plugin's group takes what its match says, after your own groups", function()
    local ns = catLogin()
    local B, Cat = ns.Bags, ns.Categories
    local me = DaylightUI.API.For("Angler")
    local asked
    T.eq(me.AddBagGroup("food", { label = "Picnic", match = function(item)
        asked = item
        return item.itemID == 8 or item.itemID == 9
    end }), true)
    stub.RunTimers()
    T.eq(groupOf(ns, B.buttons[0][8]), "Angler:food", "bread in the plugin's group")
    T.eq(groupOf(ns, B.buttons[1][2]), "Angler:food", "and the apple")
    T.truthy(asked and asked.quality ~= nil, "the match gets the item's facts")
    T.eq(Cat.Get("Angler:food").name, "Picnic")
    T.falsy(Cat.CanDelete("Angler:food"), "it goes with its addon, not deleted by hand")
    local mine = Cat.AddCustom("Bread only", "bread")
    T.eq(groupOf(ns, B.buttons[0][8]), mine, "your own group wins")
    me.AddBagGroup("broken", { label = "Broken", match = function() error("nope") end })
    stub.RunTimers()
    T.eq(groupOf(ns, B.buttons[1][2]), "Angler:food", "a broken one is skipped")
    T.eq(me.RemoveBagGroup("food"), true)
    stub.RunTimers()
    T.isnil(Cat.Get("Angler:food"))
    T.truthy(groupOf(ns, B.buttons[1][2]) ~= "Angler:food", "back where it was")
end)

T.test("bags: compare off keeps the worn item away from a bag item's tooltip", function()
    local ns = login()
    open(ns)
    local btn = ns.Bags.buttons[0][1]
    local hidden, suppressed = 0, nil
    local saved = _G.GameTooltip
    local tip = { shoppingTooltips = {}, GetOwner = function() return btn end }
    _G.GameTooltip = tip
    _G.GameTooltip_SuppressAutomaticCompareItem = function(t) suppressed = t end
    _G.GameTooltip_HideShoppingTooltips = function() hidden = hidden + 1 end
    ns.Items.NoCompare(btn)
    T.isnil(suppressed, "on: the game's compare setting decides")
    DaylightUI:Set("Bags", "compareItems", false)
    stub.RunTimers()
    ns.Items.NoCompare(btn)
    T.eq(suppressed, tip, "off: the refresh won't bring it back")
    T.eq(hidden, 1, "off: the one just shown goes")
    _G.IsModifiedClick = function(k) return k == "COMPAREITEMS" end
    ns.Items.NoCompare(btn)
    T.eq(hidden, 1, "Shift held: it stays")
    _G.IsModifiedClick = nil
    _G.GameTooltip_SuppressAutomaticCompareItem, _G.GameTooltip_HideShoppingTooltips = nil, nil
    _G.GameTooltip = saved
end)

-- Folds, loot, use, chips, sorts, fights and reopening in a random mix, cut off
-- mid-glide: once things settle every slot stands where a plain layout puts it.
T.test("bags: eased layouts always land where a plain layout would", function()
    for seed = 1, 12 do
        math.randomseed(seed)
        local ns, f = catLogin()
        ns.Layout.EASE_MAX = (seed % 2 == 0) and 2 or 60
        local Feel, Motion = DaylightUI.Win.Feel, DaylightUI.Motion
        local log = {}
        local function step(dt)
            local d = Motion.Driver(); if d then stub.RunOnUpdate(d, dt) end
            d = Feel.Driver(); if d then stub.RunOnUpdate(d, dt) end
        end
        for i = 1, 25 do
            local r = math.random(12)
            if r == 1 then
                local hs = {}
                for _, x in ipairs(f.headings) do if x:IsShown() and x.key then hs[#hs + 1] = x end end
                local h = hs[math.random(math.max(1, #hs))]
                if h then
                    log[#log + 1] = "fold " .. tostring(h.key)
                    h:GetScript("OnClick")(h, "LeftButton")
                end
            elseif r == 2 then
                log[#log + 1] = "ease"
                ns.Layout.easing = true; ns.Relayout(); ns.Layout.easing = false
            elseif r == 3 then
                log[#log + 1] = "plain"
                ns.Relayout()
            elseif r == 4 then
                log[#log + 1] = "light"
                ns.Slots.Light(f.set.Slots(), math.random(2) == 1 and 0 or nil)
            elseif r == 5 then
                log[#log + 1] = "easeRelayout"
                ns.Window.EaseRelayout(f)
            elseif r == 7 then
                local bag = math.random(0, 1)
                local slot = math.random(1, 8)
                if world.items[bag] and world.items[bag][slot] and math.random(2) == 1 then
                    log[#log + 1] = "use " .. bag .. ":" .. slot
                    world.items[bag][slot] = nil
                elseif world.items[bag] then
                    log[#log + 1] = "loot " .. bag .. ":" .. slot
                    local id = math.random(1, 9)
                    world.items[bag][slot] = { iconFileID = 100 + id, stackCount = 1, quality = math.random(0, 3), hyperlink = "|Hitem:" .. id .. "|h", itemID = id, itemName = "I" .. id }
                end
                stub.FireEvent("BAG_UPDATE", bag)
                stub.FireEvent("BAG_UPDATE_DELAYED")
                if math.random(2) == 1 then stub.RunTimers() end
            elseif r == 9 then
                stub.combat = not stub.combat
                log[#log + 1] = "combat " .. tostring(stub.combat)
                stub.FireEvent(stub.combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
            elseif r == 10 then
                log[#log + 1] = "reopen"
                CloseAllBags(); f:Hide(); stub.RunTimers(); open(ns)
            elseif r == 11 then
                log[#log + 1] = "sort"
                f.sort:GetScript("OnClick")(f.sort)
                stub.Advance(1); stub.RunTimers()
            elseif r == 12 then
                local c = ({ 2, 4, 6, 10 })[math.random(4)]
                log[#log + 1] = "columns " .. c
                DaylightUI:Set("Bags", "columns", c)
                if math.random(2) == 1 then stub.RunTimers() end
            elseif r == 6 then
                local ids = { nil, "gear", "trade", "junk" }
                local c = ids[math.random(4)]
                log[#log + 1] = "chip " .. tostring(c)
                ns.Window.PickChip(f, c)
            end
            local dt = ({ 0, 0.03, 0.1, 0.3, 1 })[math.random(5)]
            log[#log + 1] = "dt " .. dt
            step(dt)
        end
        if stub.combat then stub.combat = false; stub.FireEvent("PLAYER_REGEN_ENABLED") end
        stub.Advance(4)
        stub.RunTimers()
        if not f.sorting then ns.Window.EaseRelayout(f) end
        step(2)
        local got = {}
        for _, s in ipairs(f.set.Slots()) do
            local b = s.button
            if b:IsShown() then got[b] = { select(4, b:GetPoint(1)) } end
        end
        ns.Relayout()
        for _, s in ipairs(f.set.Slots()) do
            local b = s.button
            local want = b:IsShown() and { select(4, b:GetPoint(1)) } or nil
            local g = got[b]
            local same = (g == nil and want == nil) or (g and want and g[1] == want[1] and g[2] == want[2])
            if not same then
                error("seed " .. seed .. " slot " .. s.bag .. ":" .. b:GetID() .. " got " .. (g and (g[1] .. "," .. g[2]) or "hidden")
                    .. " want " .. (want and (want[1] .. "," .. want[2]) or "hidden") .. "\n" .. table.concat(log, " | "))
            end
        end
    end
end)

T.test("bags: the search tooltip lists what to type, one labeled row each, with a gap between groups", function()
    local ns = login()
    local S = ns.Search
    local lines = {}
    local tip = { SetMinimumWidth = function(self, w) self.minW = w end }
    function tip:AddLine(text, r, g, b, wrap) lines[#lines + 1] = { text = text, wrap = wrap } end
    function tip:AddDoubleLine() end
    S.Tip(tip)
    local function plain(i) return (lines[i].text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    T.eq(lines[1].text, (_G.SEARCH or "Search"), "the title")
    T.eq(plain(2), "Type a name or a keyword. You can combine several.", "what to do first")
    T.eq(plain(3):match("^[^:]+"), (_G.TYPE or "Type"), "the game's own word for Type")
    T.truthy(plain(3):find("gear, weapon, armor", 1, true))
    T.truthy(plain(3):find("junk, open", 1, true))
    T.eq(plain(4), "Kind or slot: the game's own name for it, like herb, cloth, trinket or shield")
    T.eq(plain(5), "Binding: boe (binds on equip), bou (binds on use), soulbound")
    T.eq(plain(6), "Equipment set: set, or the set's name")
    T.truthy(plain(8):find("poor, common, uncommon, rare, epic, legendary", 1, true))
    T.eq(plain(9), "Compare: q>rare, q>=uncommon, q<epic")
    T.eq(plain(10), "Item level: ilvl>20, ilvl<=10, ilvl20-30")
    T.eq(lines[11].text, " ", "a gap between the things to type and how to join them")
    T.eq(plain(12), "Combine terms: & means all, | means any, ! means not")
    T.eq(plain(13), "Example: boe & q>common, food | potion, gear & !set")
    T.eq(lines[14].text, " ")
    T.truthy(lines[15].text:find("Any other word searches names", 1, true))
    T.truthy(lines[#lines].text:find("; works like |", 1, true))
    T.truthy(lines[3].text:find("|c", 1, true), "the label is colored")
    T.truthy(lines[3].wrap, "rows wrap")
    T.eq(tip.minW, S.TIP_WIDTH, "wide enough")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the search tooltip shows the player's own keywords, the ones the box accepts", function()
    local ns = login()
    local S = ns.Search
    local saved = { potion = S.WORD.potion, common = S.WORD.common, food = S.WORD.food, set = S.WORD.set }
    rawset(S.WORD, "potion", "poción"); rawset(S.WORD, "common", "común"); rawset(S.WORD, "food", "comida"); rawset(S.WORD, "set", "conjunto")
    local lines = {}
    local tip = {}
    function tip:AddLine(text) lines[#lines + 1] = text end
    function tip:AddDoubleLine() end
    S.Tip(tip)
    local all = table.concat(lines, "\n")
    T.truthy(all:find("comida, bebida", 1, true) or all:find("comida, drink", 1, true), "kinds in Spanish")
    T.truthy(all:find("poción", 1, true), "with its accent")
    T.truthy(all:find("boe & q>común, comida | poción, gear & !conjunto", 1, true), "the example uses them")
    for k, v in pairs(saved) do rawset(S.WORD, k, v) end
end)

-- A stand-in for the game's controller list (FrameControlsManager): the windows
-- it lists, and for each close whether it left the list empty. Emptying it from
-- addon code is what the game refuses.
local function padList()
    local m = { shown = {}, emptied = {} }
    function m:GetActiveFrame() return self.shown[#self.shown] end
    function m:FrameShown(frame)
        for _, f in ipairs(self.shown) do if f == frame then return end end
        table.insert(self.shown, frame)
    end
    function m:FrameHidden(frame)
        for i, f in ipairs(self.shown) do
            if f == frame then table.remove(self.shown, i); break end
        end
        self.emptied[frame] = #self.shown == 0
    end
    _G.GamepadMode = { FrameControlsManager = m }
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    return m
end
local function listed(m, frame)
    for _, f in ipairs(m.shown) do if f == frame then return true end end
    return false
end
local function noPad() _G.GamepadMode, _G.InputUtil = nil, nil end

T.test("bags: walking away from a merchant with the bag open tells the controller while the merchant is still listed", function()
    local ns = login()
    local m = padList()
    local merchant = CreateFrame("Frame", nil, UIParent)
    local f = open(ns)
    stub.RunTimers()
    T.eq(listed(m, f), true, "the bag is listed")
    -- Only the two windows that matter: the game's merchant window and the bag.
    m.shown = { merchant, f }
    -- Walking away: the game closes its bags first, then its merchant window.
    CloseAllBags()
    m:FrameHidden(merchant)
    for _ = 1, 5 do stub.RunTimers() end
    T.eq(listed(m, f), false, "the bag left the list")
    T.eq(m.emptied[f], false, "it left while the merchant was still listed, so its close never emptied the list")
    noPad()
end)

T.test("bags: in a fight, Win.Held reads the bag's table of held slots without calling it", function()
    local ns = login()
    local f = open(ns)
    T.eq(type(f.held), "table", "the bag keeps its held slots in a table")
    stub.EnterCombat()
    local ok, held = pcall(DaylightUI.Win.Held, f)
    T.eq(ok, true, "no error grabbing the bag in a fight")
    T.eq(held, f:IsProtected() == true)
    stub.LeaveCombat()
end)


T.test("bags: a long cleanup in batches ends with every slot in place and filled", function()
    for _, view in ipairs({ "grid", "categories" }) do
        local ns, f
        if view == "grid" then ns = login(); f = open(ns); ns.Relayout() else ns, f = catLogin() end
        local W, Feel = ns.Window, DaylightUI.Win.Feel
        local ok, err = pcall(function()
            local runDue = timedTimers()
            -- Scatter items through both bags, with stacks of the same item.
            for _, bag in ipairs({ 0, 1 }) do
                for s = 1, world.sizes[bag] do world.items[bag][s] = nil end
            end
            local n = 0
            for _, spot in ipairs({ {0,2},{0,5},{0,9},{0,11},{0,14},{0,16},{1,1},{1,4},{1,7},{1,8},{1,12} }) do
                n = n + 1
                local id = (n % 4) + 1
                world.items[spot[1]][spot[2]] = { iconFileID = 900 + n, stackCount = n, quality = 1, hyperlink = "|Hitem:" .. (20 + id) .. "|h" }
            end
            stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE", 1)
            stub.FireEvent("BAG_UPDATE_DELAYED")
            stub.Advance(2); runDue()
            settleFeel()
            f.sort:GetScript("OnClick")(f.sort)
            -- The server packs everything to the front, a move at a time, in slow batches.
            local list = {}
            for _, bag in ipairs({ 0, 1 }) do
                for s = 1, world.sizes[bag] do list[#list + 1] = { bag, s } end
            end
            local step = 0
            for i, to in ipairs(list) do
                if not world.items[to[1]][to[2]] then
                    for j = i + 1, #list do
                        local from = list[j]
                        if world.items[from[1]][from[2]] then
                            world.items[to[1]][to[2]] = world.items[from[1]][from[2]]
                            world.items[from[1]][from[2]] = nil
                            stub.FireEvent("BAG_UPDATE", to[1])
                            if from[1] ~= to[1] then stub.FireEvent("BAG_UPDATE", from[1]) end
                            stub.FireEvent("BAG_UPDATE_DELAYED")
                            break
                        end
                    end
                    step = step + 1
                    stub.Advance(step % 2 == 0 and 0.45 or 0.05)
                    runDue()
                    local d = DaylightUI.Win.Feel.Driver()
                    if d then stub.RunOnUpdate(d, 0.05) end
                end
            end
            stub.Advance(5); runDue()
            settleFeel()
            T.isnil(f.sorting, view .. ": the hold let go")
            T.truthy(filledRight(f), view .. ": every icon is what's there")
            for _, s in ipairs(f.set.Slots()) do T.falsy(Feel.Moving(s.button), view .. ": nothing still moving") end
            -- Laid out again from scratch, nothing should move.
            local spots = {}
            for _, s in ipairs(f.set.Slots()) do if s.button:IsShown() then spots[s.button] = { at(s.button) } end end
            f.stale = true
            ns.Relayout()
            for _, s in ipairs(f.set.Slots()) do
                if s.button:IsShown() and spots[s.button] then
                    local x, y = at(s.button)
                    T.eq(x, spots[s.button][1], view .. ": slot " .. s.bag .. ":" .. s.button:GetID() .. " x in place")
                    T.eq(y, spots[s.button][2], view .. ": slot " .. s.bag .. ":" .. s.button:GetID() .. " y in place")
                else
                    T.truthy(not s.button:IsShown() or spots[s.button], view .. ": no slot appears on a fresh layout")
                end
            end
        end)
        stub.ResetTimers()
        T.truthy(ok, tostring(err))
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)
