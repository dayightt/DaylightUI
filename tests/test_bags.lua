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
    T.isnil(f.tabs, "no header tabs: the bank and alts are on the portrait")
    headerFits(f)
    T.eq(ns.Window.TITLE, DaylightUI.Win.HEADER)
end)

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

T.test("bags: item tooltips count each character's bags and bank, the account bank and a total", function()
    local ns = countWorld()
    local rows = tipRows(ns, { id = 1 })
    T.eq(plainText(rows[1][1]), " ", "a gap above the counts")
    local me = DaylightUI.DB.CharKey():match("^(.-)%-")
    T.eq(rows[2][1], me, "this character first")
    T.eq(plainText(rows[2][2]), "Bags 5 · Bank 6", "its bags as they are now and its bank as last seen")
    T.eq(rows[3][1], "Alt")
    T.eq(plainText(rows[3][2]), "Bags 3 · Bank 7", "stacks added up")
    T.eq(rows[4][1], "Account")
    T.eq(plainText(rows[4][2]), "2")
    T.eq(rows[5][1], "Total")
    T.eq(plainText(rows[5][2]), "23")
    T.eq(#rows, 5)
    -- Labels tan, the numbers in the accent the row is painted in.
    T.truthy(rows[3][2]:find(DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.LABEL), 1, true), "Bags and Bank in the label color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: item counts show only when another character has some", function()
    local ns = countWorld()
    T.eq(#tipRows(ns, { id = 6 }), 0, "only in this character's bags: nothing added")
    T.eq(#tipRows(ns, { id = 4 }), 0, "this character and the account bank: nothing either")
    local rows = tipRows(ns, { id = 9 })
    T.eq(rows[2][1], "Alt", "only on another character: just that one")
    T.eq(plainText(rows[2][2]), "Bags 1")
    T.eq(#rows, 3, "and the total")
    T.eq(#tipRows(ns, { id = 77 }), 0, "nobody has it")
    T.eq(#tipRows(ns, {}), 0, "no item")
    T.eq(#tipRows(ns, { id = stub.Secret(1) }), 0, "a secret item id is left alone")
end)

T.test("bags: item counts follow this character's bags as they change", function()
    local ns = countWorld()
    T.eq(plainText(tipRows(ns, { id = 1 })[2][2]), "Bags 5 · Bank 6")
    world.items[0][1].stackCount = 9
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(plainText(tipRows(ns, { id = 1 })[2][2]), "Bags 9 · Bank 6", "a new stack size counts at once")
    world.items[0][1] = nil
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(plainText(tipRows(ns, { id = 1 })[2][2]), "Bank 6", "none left in the bags")
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

T.test("bags: new items get no glow frame, flash or pulse from the game", function()
    local ns = login()
    open(ns)
    local rare = ns.Bags.buttons[0][1]
    T.eq(rare.calls.UpdateNewItem[1], 3, "the game's new-item update still runs")
    T.falsy(rare.flashAnim:IsPlaying(), "the sweep stopped")
    T.falsy(rare.newitemglowAnim:IsPlaying(), "the pulse stopped")
    T.falsy(rare.flash:IsShown(), "the flash texture hidden")
    T.falsy(rare.NewItemTexture:IsShown(), "the game's glow frame is hidden: Recent and the new-item dot mark new loot")
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

T.test("bags: a slot's hover ring settles after a shine and when the bag closes", function()
    local ns = login()
    _G.C_NewItems = { IsNewItem = function(bag, slot) return slot == 7 end }
    local f = open(ns)
    local Items, B = ns.Items, ns.Bags
    local function drive() stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2) end
    world.items[0][7] = { iconFileID = 207, stackCount = 1, quality = 2, hyperlink = "|Hitem:207|h", itemID = 207 }
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    local green = B.buttons[0][7]
    local q = Items.QualityColor(2)
    local p = Items.Parts(green)
    T.truthy(p.shell.opts.borderColor[1] > q[1] + 0.1, "flashing")
    green:GetScript("OnEnter")(green)
    drive()
    local r = DaylightUI.Style.Accent()
    T.near(p.shell.opts.borderColor[1], r, 1e-6, "hovered during the flash: the accent")
    green:GetScript("OnLeave")(green)
    drive()
    T.near(p.shell.opts.borderColor[1], q[1], nil, "left: its quality color, not mid-flash")
    -- The pointer is on a slot when its window hides: no leave comes.
    local rare = B.buttons[0][1]
    rare:GetScript("OnEnter")(rare)
    drive()
    f:Hide(); drive()
    f:Show(); drive()
    T.near(Items.Parts(rare).shell.opts.borderColor[1], 0.3, nil, "reopened: no stuck accent ring")
end)

T.test("bags: a slot is a ring between two black lines, with no shadow", function()
    local ns = login()
    open(ns)
    local B, Items = ns.Bags, ns.Items
    local Style, Pixel = DaylightUI.Style, DaylightUI.Pixel
    local rare, poor, empty = B.buttons[0][1], B.buttons[0][2], B.buttons[0][3]
    local function opts(b) return Items.Parts(b).shell.opts end
    local p = Items.Parts(rare)
    -- Outside in: a black backing the size of the button, the ring one pixel in,
    -- then the icon one more pixel inside the ring.
    T.eq(p.back:GetNumPoints(), 1); T.eq(select(2, p.back:GetPoint(1)), rare, "the black backing covers the button")
    T.eq(p.back.__color[1], Items.BLACK[1]); T.eq(p.back.__color[4], 1)
    local e = Pixel.Px(rare, 1)
    local sp, srel, _, sx, sy = p.shell:GetPoint(1)
    T.eq(sp, "TOPLEFT"); T.eq(srel, rare); T.near(sx, e, 1e-6, "the ring starts a pixel in"); T.near(sy, -e, 1e-6)
    T.eq(Style.BorderPx(rare), 2, "a two pixel ring")
    T.eq(Items.EDGE_PX, 1); T.eq(Items.GAP_PX, 1)
    local _, irel, _, ix, iy = rare.icon:GetPoint(1)
    T.eq(irel, rare); T.near(ix, Pixel.Px(rare, 4), 1e-6, "the icon starts past both black lines and the ring"); T.near(iy, -Pixel.Px(rare, 4), 1e-6)
    T.eq(opts(rare).shadowPx, 0, "no shadow around a slot")
    T.eq(opts(rare).shadowAlpha, 0)
    -- Every item has a ring: common a light gray, poor a darker one, better ones their quality.
    T.near(Items.COMMON[1], 0.6, 0.02, "common: light gray")
    T.eq(Items.COMMON[1], Items.COMMON[2]); T.eq(Items.COMMON[2], Items.COMMON[3])
    T.truthy(Items.POOR[1] < Items.COMMON[1], "poor: darker")
    T.eq(opts(poor).borderColor, Items.POOR)
    T.near(opts(rare).borderColor[1], 0.3, nil, "rare: its quality color")
    for _, b in ipairs({ rare, poor, empty }) do
        T.eq(opts(b).bandColor, opts(b).borderColor, "no second tone")
    end
    -- An empty slot: a thin dim ring around a dark well.
    T.eq(Style.BorderPx(empty), Items.THIN_PX, "an empty slot: a thinner ring")
    T.eq(opts(empty).borderColor, Items.EMPTY)
    local well = Items.Parts(empty).well
    T.truthy(well:IsShown(), "a dark well inside")
    T.near(select(4, well:GetPoint(1)), Pixel.Px(empty, 3), 1e-6, "inside the thin ring's black line")
    T.falsy(p.well:IsShown(), "none under an item")
    -- Hover lights the ring in the accent and lets go.
    local r = DaylightUI.Style.Accent()
    rare:GetScript("OnEnter")(rare)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    T.near(opts(rare).borderColor[1], r, 1e-6, "hovered: the accent")
    rare:GetScript("OnLeave")(rare)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    T.near(opts(rare).borderColor[1], 0.3, nil, "left: its quality color again")
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

T.test("bags: the tool row is flat icons in Daylight UI's own art", function()
    local ns = login()
    local f = open(ns)
    local M = DaylightUI.MEDIA
    T.truthy(#f.tools > 0)
    for _, b in ipairs(f.tools) do
        T.truthy(b.SetIcon, "a W.IconButton")
        T.eq(b.icon:GetTexture():sub(1, #M), M, "Media art, not a game icon")
    end
    T.eq(f.sort.icon:GetTexture(), M .. "ui-sort.png")
    T.eq(f.viewButton.icon:GetTexture(), M .. "ui-view.png")
    T.eq(f.disenchantButton.icon:GetTexture(), M .. "ui-disenchant.png")
    T.eq(f.slotsButton.icon:GetTexture(), M .. "ui-section-bags.png")
    -- Tan at rest, the accent on hover, with the tooltip saying what it does.
    local b = f.viewButton
    T.near((b.icon:GetVertexColor()), DaylightUI.Style.INK.LABEL[1], 0.01, "tan at rest")
    b:GetScript("OnEnter")(b)
    T.truthy(GameTooltip:IsShown(), "its tooltip at once")
    local Driver = DaylightUI.Motion.Driver()
    if Driver then stub.RunOnUpdate(Driver, 1) end
    T.near((b.icon:GetVertexColor()), (DaylightUI.Style.Accent()), 0.01, "the accent on hover")
    b:GetScript("OnLeave")(b)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

T.test("bags: group headings read upper case in the group's color with a count and chevron", function()
    local ns, f = catLogin()
    local Style, Cat = DaylightUI.Style, ns.Categories
    local function headOf(key)
        for _, x in ipairs(f.headings) do if x:IsShown() and x.key == key then return x end end
    end
    local h = headOf("weapon")
    T.truthy(h, "a heading for Weapons")
    T.eq(h.text:GetText(), string.upper(h.name), "name in upper case")
    local r, g, b = h.text:GetTextColor()
    local wr, wg, wb = Cat.Color("weapon")
    T.near(r, wr, 0.01); T.near(g, wg, 0.01); T.near(b, wb, 0.01)
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
        local ar, ag, ab = DaylightUI.Style.Accent()
        T.near(rec.rule.__color[1], ar, 0.01, "its line uses the accent")
        T.near(rec.rule.__color[2], ag, 0.01); T.near(rec.rule.__color[3], ab, 0.01)
    end)
    DaylightUI:Set("general", "accent", nil)
    _G.C_NewItems = nil
    stub.now, _G.GetTime = now, getTime
    T.truthy(ok, tostring(err))
end)

-- A folded group collapses where it is: its heading keeps its spot and the width it
-- has open, so nothing beside it moves. What's stacked under it in its column moves
-- up, and a row shrinks only when its tallest column does.
T.test("bags: a folded group keeps its spot and width; what's under it moves up, nothing beside it", function()
    local ns, f = catLogin()
    local Cat, L = ns.Categories, ns.Layout
    local function spot(key)
        for _, x in ipairs(f.headings) do
            if x:IsShown() and x.key == key then
                local _, _, _, px, py = x:GetPoint(1)
                return px, py, x:GetWidth()
            end
        end
    end
    local keys = { "consumable", "sets", "weapon", "armor", "tradegoods", "junk", "empty" }
    local before = {}
    for _, k in ipairs(keys) do before[k] = { spot(k) } end
    -- This bag packs as Consumables over Armor beside the tall Empty, then a row
    -- of Sets, Weapons, Trade goods and Junk.
    T.eq(before.consumable[1], before.armor[1], "armor stacks under consumables")
    T.truthy(before.armor[2] < before.consumable[2])
    T.eq(before.consumable[2], before.empty[2], "beside the tall Empty")
    T.eq(before.sets[2], before.weapon[2], "sets and weapons side by side")
    local function unchanged(but, what)
        for _, k in ipairs(keys) do
            if not but[k] then
                local x, y, w = spot(k)
                T.eq(x, before[k][1], k .. " stays in its column " .. what)
                T.eq(y, before[k][2], k .. " stays on its row " .. what)
                T.eq(w, before[k][3], k .. " keeps its width " .. what)
            end
        end
    end
    Cat.ToggleCollapsed("sets")
    stub.RunTimers()
    unchanged({}, "(sets folded)")
    Cat.ToggleCollapsed("weapon")
    stub.RunTimers()
    unchanged({}, "(weapons folded too)")
    Cat.ToggleCollapsed("consumable")
    stub.RunTimers()
    T.eq(select(2, spot("armor")), -(L.HeadH(f) + L.RowGap(f)), "armor moves up under the folded heading")
    unchanged({ armor = true }, "(consumables folded)")
    Cat.ToggleCollapsed("empty")
    stub.RunTimers()
    local column = L.HeadH(f) + L.RowGap(f) + L.SlotTop(f) + f.Cfg().iconSize
    T.eq(select(2, spot("sets")), -(column + L.RowGap(f)), "the top row shrinks to its tallest column")
    T.eq(select(1, spot("sets")), before.sets[1], "and the row below only moves up")
    for _, k in ipairs({ "sets", "weapon", "consumable", "empty" }) do Cat.ToggleCollapsed(k) end
    stub.RunTimers()
    unchanged({}, "(all open again)")
end)

-- The packer on its own, with the groups of a real bag (10 columns, 35 px slots).
local function packWorld(L, f, counts)
    local cfg = f.Cfg()
    local size, gap, cols = 35, 2, 10
    local top, headH = L.SlotTop(f, cfg), L.HeadH(f, cfg)
    local inset = L.Ref(f, cfg, L.REF.inset)
    local boxes = {}
    for _, c in ipairs(counts) do
        local key, n, headW = c[1], c[2], c[3] + 2 * inset
        local function shape(across)
            local rows = math.ceil(n / across)
            return { w = math.max(across * size + (across - 1) * gap, headW), h = top + rows * size + (rows - 1) * gap,
                     fill = n * (size + gap) ^ 2, across = across }
        end
        local shapes = {}
        if n <= cols then
            shapes[1] = shape(n)
        else
            local least = math.ceil(n / cols)
            shapes[1] = shape(math.ceil(n / least))
            shapes[2] = shape(math.ceil(n / (least + 1)))
        end
        boxes[#boxes + 1] = { key = key, shapes = shapes, drawnH = c.folded and headH or nil, n = n, headW = headW }
    end
    return boxes, cols * size + (cols - 1) * gap, L.GroupGap(f, cfg), L.RowGap(f, cfg), top, size, gap, cols
end

-- The flow before packing: left to right in order, a new row when the next group
-- doesn't fit, each group as wide as a full row allows.
local function flowHeight(boxes, maxW, gapX, gapY, top, size, gap, cols)
    local x, y, lineH = 0, 0, 0
    for _, b in ipairs(boxes) do
        local across = math.min(b.n, cols)
        local rows = math.ceil(b.n / across)
        local w = math.max(across * size + (across - 1) * gap, b.headW)
        if x > 0 and x + w > maxW then y, x, lineH = y + lineH + gapY, 0, 0 end
        lineH = math.max(lineH, top + rows * size + (rows - 1) * gap)
        x = x + w + gapX
    end
    return y + lineH
end

-- The bag seen in game, with name widths about as wide as its headings read there.
local USER_BAG = { { "hearthstone", 1, 88 }, { "consumable", 8, 104 }, { "quest", 16, 98 }, { "weapon", 3, 76 },
                   { "armor", 2, 50 }, { "tradegoods", 16, 104 }, { "junk", 5, 42 }, { "empty", 1, 50 } }

local function rects(boxes, spots)
    local out = {}
    for i, b in ipairs(boxes) do
        local sh = b.shapes[spots[i].shape]
        out[i] = { x = spots[i].x, y = spots[i].y, w = sh.w, h = b.drawnH or sh.h, key = b.key }
    end
    return out
end

T.test("bags: the Shelf packs a real bag into less height, nothing overlapping", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy, top, size, gap, cols = packWorld(L, f, USER_BAG)
    local spots, height, memo = L.Pack(boxes, maxW, gx, gy)
    local was = flowHeight(boxes, maxW, gx, gy, top, size, gap, cols)
    T.truthy(height < was, "shorter than the old flow: " .. height .. " vs " .. was)
    local r = rects(boxes, spots)
    for i, a in ipairs(r) do
        T.truthy(a.x >= 0 and a.x + a.w <= maxW + 0.01, a.key .. " inside the bag's width")
        for k = i + 1, #r do
            local b = r[k]
            local apart = a.x + a.w + gx <= b.x + 0.01 or b.x + b.w + gx <= a.x + 0.01
                or a.y + a.h + gy <= b.y + 0.01 or b.y + b.h + gy <= a.y + 0.01
            T.truthy(apart, a.key .. " and " .. b.key .. " keep their gap")
        end
    end
    local row = memo.hearthstone.row
    local mates = 0
    for k, m in pairs(memo) do if k ~= "hearthstone" and m.row == row then mates = mates + 1 end end
    T.truthy(mates > 0, "the Hearthstone no longer takes a row alone")
    -- Each row starts with the first group not yet placed: a group only ever moves
    -- earlier, into a gap, never later than its turn.
    local rows = {}
    for i, b in ipairs(boxes) do
        local n = memo[b.key].row
        rows[n] = rows[n] or {}
        table.insert(rows[n], i)
    end
    local placed = {}
    for n = 1, #rows do
        local first
        for i = 1, #boxes do if not placed[i] then first = i break end end
        T.eq(rows[n][1], first, "row " .. n .. " starts with the earliest group left")
        for _, i in ipairs(rows[n]) do placed[i] = true end
    end
    -- Side by side, groups read in their order.
    for i, a in ipairs(r) do
        for k = i + 1, #r do
            if r[k].y == a.y then T.truthy(a.x < r[k].x, a.key .. " before " .. r[k].key .. " on its row") end
        end
    end
end)

T.test("bags: the Shelf's packing is the same every time and moves little when a count changes", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy = packWorld(L, f, USER_BAG)
    local a, ha, memo = L.Pack(boxes, maxW, gx, gy)
    local b, hb = L.Pack(boxes, maxW, gx, gy)
    T.eq(ha, hb)
    for i = 1, #boxes do T.deq(a[i], b[i], boxes[i].key .. ": the same spot") end
    -- One more consumable.
    local more = {}
    for i, c in ipairs(USER_BAG) do more[i] = { c[1], c[2] + (c[1] == "consumable" and 1 or 0), c[3] } end
    local boxes2 = packWorld(L, f, more)
    local c = L.Pack(boxes2, maxW, gx, gy, memo)
    local kept = 0
    for i = 1, #boxes do if c[i].x == a[i].x and c[i].y == a[i].y then kept = kept + 1 end end
    T.truthy(kept >= #boxes / 2, "most groups keep their spots: " .. kept .. " of " .. #boxes)
end)

T.test("bags: a folded group packs where it would stand open", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy = packWorld(L, f, USER_BAG)
    local open, h0 = L.Pack(boxes, maxW, gx, gy)
    local folded = {}
    for i, c in ipairs(USER_BAG) do folded[i] = { c[1], c[2], c[3], folded = c[1] == "quest" } end
    local fb = packWorld(L, f, folded)
    local now, h1 = L.Pack(fb, maxW, gx, gy)
    T.truthy(h1 <= h0, "never taller")
    for i, b in ipairs(fb) do
        T.eq(now[i].x, open[i].x, b.key .. ": the same column")
        T.eq(now[i].shape, open[i].shape, b.key .. ": the same shape")
    end
end)

T.test("bags: folding a group moves no other heading or slot while its row has an open group", function()
    local ns, f = catLogin()
    local B = ns.Bags
    local function snapshot()
        local t = {}
        for _, x in ipairs(f.headings) do
            if x:IsShown() and x.key and x.key ~= "sets" then t[x.key] = { select(4, x:GetPoint(1)), select(5, x:GetPoint(1)) } end
        end
        for _, s in ipairs(f.set.Slots()) do
            if s.button:IsShown() and s.button ~= B.buttons[0][4] then t[s.button] = { select(4, s.button:GetPoint(1)), select(5, s.button:GetPoint(1)) } end
        end
        return t
    end
    local before = snapshot()
    ns.Categories.ToggleCollapsed("sets")
    stub.RunTimers()
    local after = snapshot()
    local n = 0
    for k, p in pairs(before) do
        n = n + 1
        T.truthy(after[k], "still there")
        T.eq(after[k][1], p[1], "same x")
        T.eq(after[k][2], p[2], "same y")
    end
    T.truthy(n > 5, "several headings and slots checked")
end)

-- Seen in game: each group's line ran along the top of its slots and the rings
-- (with their shadow) drew over it, and the gaps between groups looked uneven.
T.test("bags: the Shelf gives each heading's line room, and every gap between groups is the same", function()
    local ns, f = catLogin()
    local L, Pixel = ns.Layout, DaylightUI.Pixel
    DaylightUI:Set("Bags", "columns", 4)
    stub.RunTimers()
    ns.Categories.ToggleCollapsed("sets")
    stub.RunTimers()
    local cfg = f.Cfg()
    local size, gap = cfg.iconSize, cfg.spacing
    local HEAD = L.HeadH(f, cfg)
    local heads, buttons = {}, {}
    for _, h in ipairs(f.headings) do if h:IsShown() and h.key then heads[#heads + 1] = h end end
    for _, s in ipairs(f.set.Slots()) do if s.button:IsShown() then buttons[#buttons + 1] = s.button end end
    for _, t in ipairs(f.tiles or {}) do if t.button:IsShown() then buttons[#buttons + 1] = t.button end end
    local function spot(r) local _, _, _, x, y = r:GetPoint(1); return x, -y end
    -- Rows of headings, top to bottom, each left to right.
    local rows = {}
    for _, h in ipairs(heads) do
        local x, top = spot(h)
        local row
        for _, r in ipairs(rows) do if r.top == top then row = r end end
        if not row then row = { top = top, heads = {} }; rows[#rows + 1] = row end
        row.heads[#row.heads + 1] = { h = h, x = x }
    end
    table.sort(rows, function(a, b) return a.top < b.top end)
    T.truthy(#rows >= 3, "several rows to compare")
    local folded, measured = false, 0
    -- A heading starts and ends this far inside its group's rings.
    local inset = L.Ref(f, cfg, L.REF.inset)
    for i, row in ipairs(rows) do
        table.sort(row.heads, function(a, b) return a.x < b.x end)
        row.bottom = row.top + HEAD
        for k, e in ipairs(row.heads) do
            local h = e.h
            -- The line is the heading's bottom edge, as wide as the group.
            local p, rel, relP = h.rule:GetPoint(1)
            T.eq(rel, h); T.eq(p, "BOTTOMLEFT"); T.eq(relP, "BOTTOMLEFT")
            T.eq(h:GetHeight(), HEAD)
            if h.folded then folded = true end
            local left = e.x - inset
            local mine, right = {}, left
            for _, b in ipairs(buttons) do
                local bx, by = spot(b)
                local nextTop = rows[i + 1] and rows[i + 1].top or math.huge
                if by > row.top and by < nextTop and bx >= left - 0.01 and bx < left + h:GetWidth() + 2 * inset then
                    mine[#mine + 1] = b
                    right = math.max(right, bx + size)
                    -- From the line down to the ring's outer edge (the button's).
                    T.truthy(by - (row.top + HEAD) >= L.Ref(f, cfg, L.REF.toRing) - 0.01,
                        h.key .. ": the rings stay clear of the line")
                    row.bottom = math.max(row.bottom, by + size)
                end
            end
            if #mine > 0 and h.text:GetStringWidth() + 5 + h.count:GetStringWidth() < right - left - 2 * inset then
                T.near(h:GetWidth(), right - left - 2 * inset, 0.01, h.key .. ": the line spans its slots, inside the rings")
                measured = measured + 1
            end
            local nxt = row.heads[k + 1]
            if nxt then
                T.near(nxt.x - (e.x + h:GetWidth()), L.GroupGap(f, cfg) + 2 * inset, 0.01, "the same gap beside every group")
            end
        end
        if i > 1 then
            T.near(row.top - rows[i - 1].bottom, L.RowGap(f, cfg), 0.01, "the same gap under every row")
        end
    end
    T.truthy(folded, "a folded row among them")
    T.truthy(measured > 0, "a group wider than its name")
    -- The window holds the last row's rings.
    local _, h = L.Categories(f, cfg)
    T.near(h, rows[#rows].bottom, 0.01, "the height reaches the last ring's outer edge")
end)

-- The Shelf's spacing follows the approved picture (a 70 px slot, rings and all), scaled to the
-- slot size, so a bigger slot keeps the same proportions.
T.test("bags: the Shelf's gaps are the picture's, scaled to the slot size", function()
    local ns, f = catLogin()
    local L, Pixel = ns.Layout, DaylightUI.Pixel
    local function want(px, size) return math.max(1, math.floor(px * size / 70 + 0.5)) end
    for _, size in ipairs({ 24, 35, 50 }) do
        DaylightUI:Set("Bags", "iconSize", size)
        stub.RunTimers()
        local cfg = f.Cfg()
        T.eq(cfg.iconSize, size)
        T.eq(L.Ref(f, cfg, 6), want(6, size), size .. ": the room under a heading's text")
        T.eq(L.SlotTop(f, cfg) - L.HeadH(f, cfg), want(4, size), size .. ": line to the first ring")
        T.eq(L.RowGap(f, cfg), want(10, size), size .. ": last ring to the next heading")
        local clear = L.HEAD_REACH + L.HEAD_AIR - 2 * want(4, size)
        T.eq(L.GroupGap(f, cfg), math.max(want(18, size), clear), size .. ": ring to ring between groups")
        if size >= 35 then T.eq(L.GroupGap(f, cfg), want(18, size), size .. ": the picture's own gap") end
        -- Heading to heading: the gap plus each heading's inset inside its rings.
        local apart = L.GroupGap(f, cfg) + 2 * L.Ref(f, cfg, L.REF.inset)
        T.truthy(apart - L.HEAD_REACH >= 2, size .. ": the click areas of headings side by side never overlap")
        T.truthy(apart - (L.HEAD_CHEV + L.HEAD_CHEV_GAP) >= 2, size .. ": a count never meets the next chevron")
        T.eq(cfg.spacing, 2, "slots nearly touch by default, as in the picture")
        T.truthy(L.GroupGap(f, cfg) > cfg.spacing * 2, size .. ": groups stand clearly apart from their slots")
        T.truthy(L.GroupGap(f, cfg) > L.HEAD_CHEV + L.HEAD_CHEV_GAP, size .. ": the next chevron never reaches the heading before it")
        local line = L.LineH(f, cfg)
        T.truthy(line >= Pixel.Px(f.items, 2) - 1e-6, size .. ": the line is at least two pixels")
        T.truthy(line >= 2 * size / 70 - Pixel.Px(f.items, 1), size .. ": and grows with the slot")
        T.eq(L.HeadH(f, cfg), L.HEAD_TEXT + want(6, size) + math.ceil(line - 0.001))
        -- The first slot of a group sits right under its heading by that much.
        local h
        for _, x in ipairs(f.headings) do if x:IsShown() and x.key == "weapon" then h = x end end
        local _, _, _, hx, hy = h:GetPoint(1)
        local found
        for _, s in ipairs(f.set.Slots()) do
            local b = s.button
            if b:IsShown() then
                local _, _, _, bx, by = b:GetPoint(1)
                if bx == hx - L.Ref(f, cfg, L.REF.inset) and by == hy - L.SlotTop(f, cfg) then found = true end
            end
        end
        T.truthy(found, size .. ": a slot at the measured spot")
    end
end)

-- Seen in game: new loot easing into Recent wore the game's bright white frame.
-- The template's SetAlpha also sets its quality frame's alpha, so any fade of a
-- slot showed it again.
T.test("bags: a new item's ring matches every other slot's after it fades in", function()
    local ns = login()
    local newSlots = {}
    _G.C_NewItems = { IsNewItem = function(bag, slot) return newSlots[bag .. ":" .. slot] == true end }
    local f = open(ns)
    local Items, B = ns.Items, ns.Bags
    world.items[0][7] = { iconFileID = 207, stackCount = 1, quality = 1, hyperlink = "|Hitem:207|h", itemID = 207 }
    world.items[0][8] = { iconFileID = 208, stackCount = 1, quality = 2, hyperlink = "|Hitem:208|h", itemID = 208 }
    newSlots["0:7"], newSlots["0:8"] = true, true
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    local common, green = B.buttons[0][7], B.buttons[0][8]
    -- The ways a slot's alpha is set: a fade in, and a bag hovered in the strip.
    common:SetAlpha(0); common:SetAlpha(1)
    ns.Slots.Light(f.set.Slots(), 0); ns.Slots.Light(f.set.Slots(), nil)
    for _, b in ipairs({ common, green }) do
        local border = b.IconBorder
        T.truthy(border:GetAlpha() == 0 or border:GetNumPoints() == 0, "the game's quality frame can't draw")
        T.falsy(b.NewItemTexture:IsShown(), "nor its new-item glow")
    end
    T.eq(Items.Parts(common).shell.opts.borderColor, Items.COMMON, "a new common item: the common ring")
    T.near(Items.Parts(green).shell.opts.borderColor[1], Items.QualityColor(2)[1], nil, "a new green ends on its quality ring")
    _G.C_NewItems = nil
end)

-- The template's SetAlpha only reaches the icon and count, so fading slots
-- through it left the ring popping in and undid an empty or greyed icon.
T.test("bags: slots fade as a whole and keep their own icon look", function()
    local ns = login()
    DaylightUI:Set("Bags", "greyPoor", true)
    local f = open(ns)
    local B, Items = ns.Bags, ns.Items
    local poor, empty = B.buttons[0][2], B.buttons[0][3]
    Items.Fill(poor); Items.Fill(empty)
    ns.Slots.Light(f.set.Slots(), 5)
    T.near(poor:GetAlpha(), ns.Slots.DIM, 1e-6, "another bag hovered: the whole slot dims, ring and all")
    ns.Slots.Light(f.set.Slots(), nil)
    T.eq(poor:GetAlpha(), 1)
    local fade = Items.Fader(empty)
    fade:SetAlpha(0)
    DaylightUI.Motion.AlphaTo(fade, 1, DaylightUI.Motion.NORMAL)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.05)
    local mid = empty:GetAlpha()
    T.truthy(mid > 0 and mid < 1, "a fading slot is part way, ring included")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    T.eq(empty:GetAlpha(), 1)
    T.eq(empty.icon:GetAlpha(), 0, "the empty slot keeps no picture")
    T.eq(poor.icon:GetAlpha(), Items.POOR_ALPHA, "the poor item stays greyed")
end)

-- Folding a group should animate.
T.test("bags: folding a group eases: its items fade out, the rest glide, the window glides to its size", function()
    local ns, f = narrowLogin()
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
    -- Junk sits alone on its row: folding it lifts the row below and shrinks the window.
    local setItem, weapon = B.buttons[0][2], B.buttons[0][3]
    local h0 = f:GetHeight()
    local y0 = select(5, weapon:GetPoint(1))
    click("junk")
    T.truthy(setItem:IsShown(), "the folded item fades, it doesn't vanish")
    T.truthy(gliding(weapon), "a group pushed up glides there")
    T.eq(select(5, weapon:GetPoint(1)), y0, "from where it was")
    T.eq(f:GetHeight(), h0, "the window starts from its old size")
    stub.RunOnUpdate(Feel.Driver(), Motion.NORMAL / 2)
    local midY, midH = select(5, weapon:GetPoint(1)), f:GetHeight()
    T.truthy(midY > y0 and midH < h0, "halfway, slot and window both on their way")
    settle()
    T.truthy(select(5, weapon:GetPoint(1)) > midY, "the slot at its new spot")
    T.falsy(setItem:IsShown(), "gone once faded")
    T.truthy(f:GetHeight() < h0, "and the window got there")
    click("junk")
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
    click("junk")
    ns.Relayout()
    click("junk")
    settle()
    T.eq(setItem:GetAlpha(), 1, "back at full")
    T.truthy(setItem:IsShown())
end)

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

T.test("bags: a swapped pair glides from each other's spot", function()
    -- Grid: buttons keep their slots, so the items cross over.
    local ns = login()
    local Feel = DaylightUI.Win.Feel
    open(ns)
    ns.Relayout()
    settleFeel()
    local a, b = ns.Bags.buttons[0][1], ns.Bags.buttons[0][4]
    local ax, ay = at(a)
    local bx, by = at(b)
    world.items[0][1], world.items[0][4] = world.items[0][4], world.items[0][1]
    easedRelayout(ns)
    T.truthy(Feel.Moving(a) and Feel.Moving(b), "grid: both glide")
    T.eq(select(4, a:GetPoint(1)), bx, "grid: the first starts where its item was")
    T.eq(select(5, a:GetPoint(1)), by)
    T.eq(select(4, b:GetPoint(1)), ax, "grid: the second too")
    T.eq(select(5, b:GetPoint(1)), ay)
    settleFeel()
    T.eq(select(4, a:GetPoint(1)), ax, "grid: each ends at its own slot")
    T.eq(select(4, b:GetPoint(1)), bx)

    -- Shelf: two items of one group swap slots. Each item stays where it is on
    -- screen, so its new button starts on the item's old spot.
    ns = catLogin()
    settleFeel()
    a, b = ns.Bags.buttons[0][5], ns.Bags.buttons[0][6]
    ax, ay = at(a)
    bx, by = at(b)
    T.truthy(ax ~= bx or ay ~= by, "two spots")
    world.items[0][5], world.items[0][6] = world.items[0][6], world.items[0][5]
    easedRelayout(ns)
    T.eq(select(4, a:GetPoint(1)), bx, "shelf: the first starts where its item was")
    T.eq(select(5, a:GetPoint(1)), by)
    T.eq(select(4, b:GetPoint(1)), ax, "shelf: the second too")
    T.eq(select(5, b:GetPoint(1)), ay)
    settleFeel()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: grid view eases like the shelf", function()
    local ns = login()
    local Feel = DaylightUI.Win.Feel
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    stub.RunTimers()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local gray = ns.Bags.buttons[0][2]
    local x0, y0 = at(gray)
    local h0 = f:GetHeight()
    -- The first item leaves: the rest close up, gliding there.
    world.items[0][1] = nil
    easedRelayout(ns)
    T.truthy(Feel.Moving(gray), "a slot that moved glides")
    T.falsy(gray.__duiMotion and gray.__duiMotion.glide and gray.__duiMotion.glide:IsPlaying(), "by its anchor, no Translation")
    T.eq(select(4, gray:GetPoint(1)), x0, "from where it was")
    T.eq(select(5, gray:GetPoint(1)), y0)
    T.eq(f:GetHeight(), h0)
    settleFeel()
    local x1 = at(gray)
    T.truthy(x1 < x0, "now at the front")
    -- A layout that isn't eased places at once.
    world.items[0][1] = { iconFileID = 101, stackCount = 5, quality = 3, hyperlink = "|Hitem:1|h" }
    ns.Relayout()
    T.falsy(Feel.Moving(gray), "no glide unless eased")
    T.eq(at(gray), x0)
    -- Motion off: at once too.
    DaylightUI.DB.General().motion = false
    world.items[0][1] = nil
    easedRelayout(ns)
    T.falsy(Feel.Moving(gray), "motion off: no glide")
    T.eq(at(gray), x1)
    DaylightUI.DB.General().motion = true
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a stack that grew keeps its spot, the merged-away one fades", function()
    local ns = login({ view = "categories" })
    local Feel = DaylightUI.Win.Feel
    DaylightUI:Set("Bags", "combineStacks", false)
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    stub.RunTimers()
    categoryWorld()
    local f = open(ns)
    ns.Relayout()
    ns.FillAll()
    settleFeel()
    local first, second = ns.Bags.buttons[0][8], ns.Bags.buttons[1][1]
    T.truthy(first:IsShown() and second:IsShown(), "two stacks of Bread, apart")
    local fx, fy = at(first)
    -- The second stack of Bread merges into the first.
    world.items[0][8].stackCount = 12
    world.items[1][1] = nil
    easedRelayout(ns)
    T.eq(select(4, first:GetPoint(1)), fx, "the stack that grew starts from its own spot")
    T.eq(select(5, first:GetPoint(1)), fy)
    T.truthy(f.fading and f.fading[second], "the merged-away one fades out")
    T.truthy(second:IsShown(), "where it was")
    settleFeel()
    T.falsy(second:IsShown(), "gone once faded")
    -- Keys: the item, then its place among stacks of the same item.
    world.items[1][1] = { iconFileID = 108, stackCount = 7, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8 }
    T.eq(ns.Layout.ItemKey(first), "8")
    T.eq(ns.Layout.ItemKey(ns.Bags.buttons[0][3]), nil, "an empty slot has no key")
    local seen = {}
    T.eq(ns.Layout.ItemKey(first, seen), "8#1")
    T.eq(ns.Layout.ItemKey(second, seen), "8#2")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Two stacks of one item in different groups: folding the group of one must not
-- send the other off to the folded one's spot.
T.test("bags: folding one of two stacks leaves the other's glide its own", function()
    local ns, f = catLogin()
    world.sets["0:8"] = true
    ns.Relayout()
    ns.FillAll()
    settleFeel()
    local inSet, other = ns.Bags.buttons[0][8], ns.Bags.buttons[1][1]
    T.eq(groupOf(ns, inSet), "sets")
    T.eq(groupOf(ns, other), "consumable")
    local ox, oy = at(other)
    for _, h in ipairs(f.headings) do
        if h:IsShown() and h.key == "sets" then h:GetScript("OnClick")(h, "LeftButton") end
    end
    T.eq(select(4, other:GetPoint(1)), ox, "starts from its own spot")
    T.eq(select(5, other:GetPoint(1)), oy)
    settleFeel()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Loot with the bag open: a new weapon lands in bag 0 slot 3 (empty in this world).
local function lootWeapon(itemID, slot)
    itemID, slot = itemID or 10, slot or 3
    if world.class then world.class[itemID] = 2 end
    world.items[0][slot] = { iconFileID = 100 + itemID, stackCount = 1, quality = 2,
        hyperlink = "|Hitem:" .. itemID .. "|h", itemID = itemID, itemName = "Axe " .. itemID }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
end

T.test("bags: loot arriving while open glides the rest aside", function()
    local ns, f = catLogin()
    local Feel = DaylightUI.Win.Feel
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and slot == 3 end }
    local ok, err = pcall(function()
        settleFeel()
        local axe = ns.Bags.buttons[0][3]
        local spots = {}
        for _, s in ipairs(f.set.Slots()) do
            if s.button:IsShown() and s.button ~= axe then spots[s.button] = { at(s.button) } end
        end
        local w0, h0 = f:GetWidth(), f:GetHeight()
        local sized = 0
        local realSize = Feel.Size
        Feel.Size = function(...) sized = sized + 1 return realSize(...) end
        lootWeapon()
        Feel.Size = realSize
        T.eq(groupOf(ns, axe), "recent", "new, it goes in Recent")
        T.truthy(axe:IsShown(), "the new item shows")
        T.eq(axe:GetAlpha(), 0, "and fades in")
        T.truthy(Feel.Moving(axe), "dropping into place")
        T.eq(sized, 1, "the window glides to its new size")
        T.eq(f:GetWidth(), w0, "from its old one")
        T.eq(f:GetHeight(), h0)
        local moved = 0
        for b, xy in pairs(spots) do
            if b:IsShown() then
                local x, y = at(b)
                T.eq(x, xy[1], "every other slot starts where it was")
                T.eq(y, xy[2])
                if Feel.Moving(b) then moved = moved + 1 end
            end
        end
        T.truthy(moved > 0, "the groups after it glide aside")
        T.truthy(ns.Items.Parts(axe).glint:IsShown(), "the loot shine still plays")
        T.truthy(ns.Items.Parts(axe).newDot:IsShown(), "and the new-item dot shows")
        settleFeel()
        T.eq(axe:GetAlpha(), 1)
        local landed = 0
        for b, xy in pairs(spots) do
            local x, y = at(b)
            if b:IsShown() and (x ~= xy[1] or y ~= xy[2]) then landed = landed + 1 end
        end
        T.eq(landed, moved, "each glide ends at the new layout's spot")
    end)
    _G.C_NewItems = nil
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: loot in a burst glides on from where things are", function()
    local ns, f = catLogin()
    local Feel, Motion = DaylightUI.Win.Feel, DaylightUI.Motion
    settleFeel()
    lootWeapon()
    stub.RunOnUpdate(Feel.Driver(), Motion.NORMAL / 2)
    local second = ns.Bags.buttons[0][7]
    local mid, moving = {}, 0
    for _, s in ipairs(f.set.Slots()) do
        local b = s.button
        if b:IsShown() and b ~= second then
            mid[b] = { at(b) }
            if Feel.Moving(b) then moving = moving + 1 end
        end
    end
    T.truthy(moving > 0, "the first loot is still gliding")
    local h = f:GetHeight()
    lootWeapon(11, 7)
    T.truthy(second:IsShown(), "the second loot is in")
    for b, xy in pairs(mid) do
        if b:IsShown() then
            local x, y = at(b)
            T.eq(x, xy[1], "no slot jumps when more loot lands mid-glide")
            T.eq(y, xy[2])
        end
    end
    T.eq(f:GetHeight(), h, "nor the window")
    settleFeel()
    local ends = {}
    for _, s in ipairs(f.set.Slots()) do
        if s.button:IsShown() then ends[s.button] = { at(s.button) } end
    end
    ns.Relayout()
    for b, xy in pairs(ends) do
        T.eq(select(4, b:GetPoint(1)), xy[1], "and each lands on its spot")
        T.eq(select(5, b:GetPoint(1)), xy[2])
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: an extra stack of an item you have fades in, the others keep their spots", function()
    local ns, f = catLogin()
    local Feel = DaylightUI.Win.Feel
    DaylightUI:Set("Bags", "combineStacks", false)
    stub.RunTimers()
    ns.Relayout()
    settleFeel()
    -- Bread sits in bag 0 slot 8 and bag 1 slot 1; a third stack lands in bag 0 slot 3, before both.
    local a, b = ns.Bags.buttons[0][8], ns.Bags.buttons[1][1]
    local ax, ay = at(a)
    local bx, by = at(b)
    world.items[0][3] = { iconFileID = 108, stackCount = 1, quality = 1, hyperlink = "|Hitem:8|h", itemID = 8, itemName = "Bread" }
    ns.Layout.easing = true
    ns.Relayout()
    ns.Layout.easing = false
    local extra = ns.Bags.buttons[0][3]
    T.eq(extra:GetAlpha(), 0, "the new stack fades in")
    T.eq(select(4, a:GetPoint(1)), ax, "the first stack starts from its own spot")
    T.eq(select(5, a:GetPoint(1)), ay)
    T.eq(select(4, b:GetPoint(1)), bx, "the second too")
    T.eq(select(5, b:GetPoint(1)), by)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a section line no longer needed fades out", function()
    local ns = login()
    local Feel = DaylightUI.Win.Feel
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local shown = 0
    for _, l in ipairs(f.lines or {}) do if l:IsShown() then shown = shown + 1 end end
    T.truthy(shown > 0, "lines between sections")
    local last = f.lines[shown]
    -- The profession bag goes: one section and its line less.
    world.sizes[5] = 0
    world.items[5] = {}
    ns.Layout.easing = true
    ns.Relayout()
    ns.Layout.easing = false
    T.truthy(last:IsShown(), "the line stays while it fades")
    settleFeel()
    T.falsy(last:IsShown(), "then it's gone")
    ns.Relayout()
    T.falsy(last:IsShown(), "and the next layout leaves it hidden")
    T.eq(last:GetAlpha(), 1, "whole again for when it's needed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: loot during a fold glide settles and glides on", function()
    local ns, f = narrowLogin()
    local Feel, Motion = DaylightUI.Win.Feel, DaylightUI.Motion
    settleFeel()
    local setItem = ns.Bags.buttons[0][2]
    for _, h in ipairs(f.headings) do
        if h:IsShown() and h.key == "junk" then h:GetScript("OnClick")(h, "LeftButton") end
    end
    stub.RunOnUpdate(Feel.Driver(), Motion.NORMAL / 2)
    T.truthy(f.fading and f.fading[setItem], "the fold is still fading")
    lootWeapon()
    T.falsy(setItem:IsShown(), "the folded item put away at once")
    local axe = ns.Bags.buttons[0][3]
    T.truthy(Feel.Moving(axe), "the new item glides in")
    settleFeel()
    -- The same layout made at once ends in the same spots.
    local ends = {}
    for _, s in ipairs(f.set.Slots()) do
        if s.button:IsShown() then ends[s.button] = { at(s.button) } end
    end
    local hEnd = f:GetHeight()
    ns.Relayout()
    for b, xy in pairs(ends) do
        T.truthy(b:IsShown())
        T.eq(select(4, b:GetPoint(1)), xy[1], "glided to its spot")
        T.eq(select(5, b:GetPoint(1)), xy[2])
    end
    T.eq(f:GetHeight(), hEnd)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: loot in a fight lays out at once", function()
    local ns, f = catLogin()
    local Feel = DaylightUI.Win.Feel
    settleFeel()
    local axe = ns.Bags.buttons[0][3]
    stub.combat = true
    lootWeapon()
    stub.RunTimers()
    for _, s in ipairs(f.set.Slots()) do
        T.falsy(Feel.Moving(s.button), "no slot glides in a fight")
    end
    T.falsy(Feel.Moving(f), "nor the window")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.RunTimers()
    T.truthy(axe:IsShown(), "the new item is in")
    T.eq(axe:GetAlpha(), 1, "whole")
    for _, s in ipairs(f.set.Slots()) do
        T.falsy(Feel.Moving(s.button), "the layout after the fight is at once too")
    end
    -- Under the client's restrictions, the same.
    stub.SetRestriction("PvPMatch", true)
    lootWeapon(11, 7)
    for _, s in ipairs(f.set.Slots()) do
        T.falsy(Feel.Moving(s.button), "no glide under restrictions")
    end
    stub.SetRestriction("PvPMatch", false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: grid with a free tile, loot glides the tile and the section line", function()
    local ns = login()
    local Feel = DaylightUI.Win.Feel
    DaylightUI:Set("Bags", "emptySlots", "grouped")
    DaylightUI:Set("Bags", "columns", 6)
    stub.RunTimers()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local B = ns.Bags
    -- Five items and the free tile fill one row; the loot needs a second one.
    local tile = B.buttons[0][3]
    T.truthy(tile:IsShown() and ns.Items.Parts(tile).free:IsShown(), "slot 3 is the free tile")
    local tx, ty = at(tile)
    local rule = f.lines[1]
    T.truthy(rule:IsShown(), "a line before the next section")
    local _, _, _, lx, ly = rule:GetPoint(1)
    lootWeapon()
    local newTile = B.buttons[0][7]
    T.truthy(Feel.Moving(newTile), "the next empty slot is the tile now, gliding")
    T.eq(select(4, newTile:GetPoint(1)), tx, "from where the tile was")
    T.eq(select(5, newTile:GetPoint(1)), ty)
    T.eq(tile:GetAlpha(), 0, "the loot fades in")
    T.truthy(Feel.Moving(rule), "the line glides down with the rows")
    T.eq(select(5, rule:GetPoint(1)), ly, "from its old spot")
    T.eq(select(4, rule:GetPoint(1)), lx)
    settleFeel()
    T.truthy(select(5, rule:GetPoint(1)) < ly, "and lands a row lower")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

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

T.test("bags: a cleanup holds its moves and glides once it settles", function()
    for _, view in ipairs({ "grid", "categories" }) do
        local ns, f
        if view == "grid" then
            ns = login()
            f = open(ns)
            ns.Relayout()
        else
            ns, f = catLogin()
        end
        local Feel, W = DaylightUI.Win.Feel, ns.Window
        settleFeel()
        local before = itemSpots(f)
        local fills = 0
        local realFill = ns.Items.Fill
        ns.Items.Fill = function(...) fills = fills + 1 return realFill(...) end
        local ok, err = pcall(function()
            f.sort:GetScript("OnClick")(f.sort)
            T.eq(world.sorted, 1, view .. ": the game sorts")
            T.truthy(f.sorting, view .. ": the window holds")
            sortStep(1, 4)
            stub.Advance(0.1)
            sortStep(5, 6)
            stub.Advance(0.1)
            sortStep(2, 3)
            stub.RunTimers()
            T.eq(fills, 0, view .. ": no fill while the server moves things")
            for _, s in ipairs(f.set.Slots()) do
                T.falsy(Feel.Moving(s.button), view .. ": nothing moves yet")
            end
            T.truthy(f.sorting, view .. ": still settling")
            stub.Advance(W.SORT_SETTLE)
            stub.RunTimers()
            T.isnil(f.sorting, view .. ": settled")
            T.truthy(fills > 0, view .. ": filled once")
            T.truthy(filledRight(f), view .. ": every icon is what's there now")
            local checked, moving = 0, 0
            for _, link in ipairs({ "|Hitem:1|h", "|Hitem:4|h", "|Hitem:6|h", "|Hitem:7|h", "|Hitem:2|h" }) do
                local b = buttonOf(f, link)
                if b and before[link] then
                    checked = checked + 1
                    local x, y = at(b)
                    T.eq(x, before[link][1], view .. ": " .. link .. " starts where it was")
                    T.eq(y, before[link][2])
                    if Feel.Moving(b) then moving = moving + 1 end
                end
            end
            T.truthy(checked >= 4, view .. ": the moved items are shown")
            T.truthy(moving >= 4, view .. ": and glide to their new slots")
            settleFeel()
            for _, s in ipairs(f.set.Slots()) do T.falsy(Feel.Moving(s.button)) end
        end)
        ns.Items.Fill = realFill
        T.truthy(ok, tostring(err))
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

T.test("bags: a cleanup that never settles is let go after SORT_MAX", function()
    local ns = login()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local W = ns.Window
    f.sort:GetScript("OnClick")(f.sort)
    for i = 1, math.floor(W.SORT_MAX / 0.2) - 1 do
        sortStep(1, 4)
        if i == 1 then T.falsy(filledRight(f), "the icons wait") end
        stub.Advance(0.2)
        stub.RunTimers()
        T.truthy(f.sorting, "still moving: held")
    end
    sortStep(1, 4)
    stub.Advance(0.3)
    stub.RunTimers()
    T.isnil(f.sorting, "let go")
    T.truthy(filledRight(f), "the bag shows what's there")
    -- From here bag updates fill as they come.
    sortStep(1, 4)
    T.truthy(filledRight(f), "the next move shows at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a cleanup waits for the server's first move", function()
    local ns = login()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local Feel, W = DaylightUI.Win.Feel, ns.Window
    local a, b = ns.Bags.buttons[0][1], ns.Bags.buttons[0][4]
    local ax, ay = at(a)
    f.sort:GetScript("OnClick")(f.sort)
    -- The server is slow to answer: the first move lands well after SORT_SETTLE.
    stub.Advance(0.4)
    stub.RunTimers()
    T.truthy(f.sorting, "still waiting for the first move")
    sortStep(1, 4)
    T.falsy(filledRight(f), "held")
    stub.Advance(W.SORT_SETTLE)
    stub.RunTimers()
    T.isnil(f.sorting, "settled after the moves")
    T.truthy(filledRight(f))
    T.truthy(Feel.Moving(b), "played as one glide")
    T.eq(select(4, b:GetPoint(1)), ax, "from where its item was")
    T.eq(select(5, b:GetPoint(1)), ay)
    settleFeel()
    -- A cleanup with nothing to move lets go once the server has had its time.
    f.sort:GetScript("OnClick")(f.sort)
    stub.Advance(W.SORT_FIRST)
    stub.RunTimers()
    T.isnil(f.sorting, "nothing came: let go")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

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

T.test("bags: a quick cleanup glides as soon as it settles", function()
    local ns = login()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local Feel, W = DaylightUI.Win.Feel, ns.Window
    local ok, err = pcall(function()
        local runDue = timedTimers()
        local b = ns.Bags.buttons[0][4]
        f.sort:GetScript("OnClick")(f.sort)
        stub.Advance(0.05)
        runDue()
        sortStep(1, 4)
        stub.Advance(0.2)
        runDue()
        T.truthy(f.sorting, "still moving")
        sortStep(5, 6)
        stub.Advance(W.SORT_SETTLE + 0.01)
        runDue()
        T.isnil(f.sorting, "played a moment after the last move, not at SORT_FIRST")
        T.truthy(Feel.Moving(b), "as a glide")
        T.truthy(filledRight(f))
        settleFeel()
        -- A game cleanup asked while the open's merge is held waits for the server too.
        local hold = W.BeginSort(f, true, true)
        f.sort:GetScript("OnClick")(f.sort)
        W.EndSort(f, nil, hold)        -- the merge is done
        T.truthy(f.sorting, "the cleanup still holds")
        stub.Advance(0.1)
        runDue()
        sortStep(1, 4)
        T.truthy(f.sorting, "its moves are held")
        stub.Advance(W.SORT_SETTLE + 0.01)
        runDue()
        T.isnil(f.sorting, "and then played")
        T.truthy(filledRight(f))
    end)
    stub.ResetTimers()
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: touching a slot mid-cleanup ends the hold before the click lands", function()
    local ns = login()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local btn = ns.Bags.buttons[0][4]
    -- Hovering.
    f.sort:GetScript("OnClick")(f.sort)
    sortStep(1, 4)
    T.truthy(f.sorting)
    T.falsy(filledRight(f), "held: the slot shows what it held")
    btn:GetScript("OnEnter")(btn)
    T.isnil(f.sorting, "a hover lets go")
    T.truthy(filledRight(f), "every slot shows its real item")
    settleFeel()
    -- A click that never hovered (a key binding, a controller).
    f.sort:GetScript("OnClick")(f.sort)
    sortStep(1, 4)
    local trueAtClick
    btn:HookScript("OnClick", function() trueAtClick = filledRight(f) end)
    btn:Click("RightButton")
    T.isnil(f.sorting, "a click lets go")
    T.truthy(trueAtClick, "the slot was true before the click's use")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: a fight or the client's restrictions end a cleanup's hold at once", function()
    local ns = login()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local Feel = DaylightUI.Win.Feel
    f.sort:GetScript("OnClick")(f.sort)
    sortStep(1, 4)
    -- A cooldown starting mid-hold waits for its end too.
    local cds = 0
    local realCd = ns.Items.FillCooldown
    ns.Items.FillCooldown = function(...) cds = cds + 1 return realCd(...) end
    stub.FireEvent("BAG_UPDATE_COOLDOWN")
    stub.RunTimers()
    T.eq(cds, 0, "no cooldown fill while held")
    stub.EnterCombat()
    stub.RunTimers()
    T.isnil(f.sorting, "a fight lets go")
    T.truthy(filledRight(f), "and fills at once")
    for _, s in ipairs(f.set.Slots()) do T.falsy(Feel.Moving(s.button), "no glide in a fight") end
    T.falsy(f.cdDirty, "the cooldowns filled with it")
    ns.Items.FillCooldown = realCd
    stub.LeaveCombat()
    stub.RunTimers()
    f.sort:GetScript("OnClick")(f.sort)
    T.truthy(f.sorting)
    stub.SetRestriction("PvPMatch", true)
    sortStep(1, 4)
    T.isnil(f.sorting, "restricted: let go")
    T.truthy(filledRight(f))
    for _, s in ipairs(f.set.Slots()) do T.falsy(Feel.Moving(s.button), "no glide under restrictions") end
    stub.SetRestriction("PvPMatch", false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: closing mid-cleanup opens with everything in place, no glide", function()
    local ns = login()
    local f = open(ns)
    ns.Relayout()
    settleFeel()
    local Feel = DaylightUI.Win.Feel
    f.sort:GetScript("OnClick")(f.sort)
    sortStep(1, 4)
    f:Hide()
    stub.RunTimers()
    settleFeel()
    T.falsy(f:IsShown())
    T.isnil(f.sorting, "closing lets the cleanup go")
    sortStep(5, 6)
    stub.Advance(1)
    stub.RunTimers()
    open(ns)
    T.truthy(f:IsShown())
    for _, s in ipairs(f.set.Slots()) do T.falsy(Feel.Moving(s.button), "no glide on the open") end
    T.truthy(filledRight(f), "every icon is what's there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: stacks merged on open fill at once, no glide", function()
    local ns, f = catLogin()
    local Feel = DaylightUI.Win.Feel
    cursorWorld()
    -- The game's bag update for each merge, as it lands.
    local pickup = C_Container.PickupContainerItem
    C_Container.PickupContainerItem = function(bag, slot)
        local held = world.held
        pickup(bag, slot)
        if held and not world.held then
            stub.FireEvent("BAG_UPDATE", bag)
            stub.FireEvent("BAG_UPDATE", held.bag)
            stub.FireEvent("BAG_UPDATE_DELAYED")
        end
    end
    f:Hide()
    stub.RunTimers()
    settleFeel()
    open(ns)
    T.isnil(world.items[1][1], "the Bread merged")
    T.eq(world.items[0][8].stackCount, 12)
    T.isnil(f.sorting, "let go when the merging is done")
    for _, s in ipairs(f.set.Slots()) do T.falsy(Feel.Moving(s.button), "no glide while the bag fades in") end
    T.truthy(filledRight(f), "every icon is what's there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

T.test("bags: Baganator's categories come over as your own groups", function()
    local ns = catLogin()
    local Cat = ns.Categories
    _G.C_EncodingUtil = { DeserializeJSON = readJSON }
    local list, said = Cat.ReadShared(BAGANATOR)
    T.truthy(list, said)
    -- Highest priority first, since the first group here that matches wins.
    local names = {}
    for _, g in ipairs(list) do if g.name then names[#names + 1] = g.name end end
    T.eq(table.concat(names, ","), "My Gear,Shinies,Toys and Pets,Keepers")
    local notes = table.concat(list.notes, "; ")
    T.truthy(notes:find("Toys and Pets (left out: #toy, #socket, #locked)", 1, true), notes)
    T.truthy(notes:find("items moved to Gems", 1, true), "the category by a name, not Baganator's key: " .. notes)
    T.truthy(notes:find("battle pets", 1, true), notes)
    T.truthy(notes:find("grouping", 1, true), notes)
    T.truthy(notes:find("sections and dividers", 1, true), notes)
    T.truthy(notes:find("hidden categories", 1, true), notes)

    local mine = Cat.AddCustom("Shinies", "q=1")
    local n, moved = Cat.ImportShared(list)
    T.eq(n, 4, "four groups; the Junk pins aren't a group")
    T.eq(moved.junk, 1)
    local lines = table.concat(Cat.ImportLines(n, moved, list.notes), "\n")
    T.truthy(lines:find("Imported 4 bag groups.", 1, true), lines)
    T.truthy(lines:find("1 item marked as junk. It'll be sold at the next vendor.", 1, true), "said, since a vendor sells them: " .. lines)
    T.truthy(lines:find("Not brought over from Baganator: ", 1, true), lines)
    local by = {}
    for _, g in ipairs(Cat.Custom()) do by[g.name] = g end
    T.eq(#Cat.Custom(), 4, "Shinies updated, not doubled")
    T.eq(by.Shinies.key, mine)
    T.eq(by.Shinies.search, "#epic | #rare & !#junk")
    T.eq(by["My Gear"].search, "#gear & ilvl>40 & #boe")
    T.isnil(by["Toys and Pets"].search, "nothing of its search has a match here")
    T.isnil(by.Keepers.search)
    T.eq(Cat.PinOf(6948), by.Keepers.key, "its moved items pinned")
    T.eq(Cat.PinOf(2589), by.Keepers.key)
    T.eq(Cat.PinOf(4306), "junk", "moved to Baganator's Junk: the Junk group here")
    T.isnil(Cat.PinOf(818))
    -- The translated search works.
    local m = ns.Search.Parse(by["My Gear"].search)
    T.truthy(m({ classID = 4, itemLevel = 50, bindType = 2 }))
    T.falsy(m({ classID = 4, itemLevel = 30, bindType = 2 }))
    _G.C_EncodingUtil = nil
end)

T.test("bags: Syndicator searches turned into the bag search", function()
    local S = catLogin().Search
    local function as(text) return (S.FromSyndicator(text)) end
    T.eq(as("#potion|#food"), "#potion | #food")
    T.eq(as("~#junk&#trade goods"), "!#junk & #tradegoods")
    T.eq(as("200-300"), "ilvl200-300")
    T.eq(as("<=10"), "ilvl<=10")
    T.eq(as("123"), "ilvl=123")
    T.eq(as("(#armor|#weapon)"), "#armor | #weapon", "brackets around all of it")
    T.eq(as("hearthstone"), "hearthstone", "a name stays a name")
    local s, dropped = S.FromSyndicator("#armor&(#cloth|#leather)")
    T.isnil(s, "brackets inside can't be followed")
    T.eq(#dropped, 1)
    -- Leaving out one term of an & would let in more than it should: the whole
    -- & part goes. Leaving out one side of | only lets in less.
    s, dropped = S.FromSyndicator("#gear&#boa")
    T.isnil(s, "not every piece of gear")
    T.eq(dropped[1], "#gear & #boa")
    s, dropped = S.FromSyndicator("#potion|#boa")
    T.eq(s, "#potion")
    T.eq(dropped[1], "#boa")
    T.isnil(as("#locked"), "a keyword only Daylight UI has isn't one of Baganator's")
    T.isnil(as("locked"))
    T.isnil(as(""))
end)

T.test("bags: a Baganator export with spaces survives the paste box", function()
    local ns = catLogin()
    local Cat = ns.Categories
    _G.C_EncodingUtil = { DeserializeJSON = readJSON }
    local shown = DaylightUI.Profiles.Wrap(BAGANATOR)
    T.falsy(shown:find("Toys and Pets", 1, true), "the box took the spaces out")
    local list = Cat.ReadShared(Cat.Unwrapped(shown, BAGANATOR))
    T.eq(list[3].name, "Toys and Pets")
    T.eq(Cat.Unwrapped("other", BAGANATOR), "other", "text changed since: what's shown")
    _G.C_EncodingUtil = nil
end)

T.test("bags: text that isn't a bag groups string is refused politely", function()
    local ns = catLogin()
    local Cat = ns.Categories
    _G.C_EncodingUtil = { DeserializeJSON = readJSON }
    local list, why = Cat.ReadShared("{not json")
    T.isnil(list)
    T.eq(why, "that isn't a Daylight UI or Baganator bag groups string")
    T.isnil(Cat.ReadShared('{"version":9,"layout":[1,2]}'), "a different export of Baganator's")
    list, why = Cat.ReadShared('{"version":9,"categories":[{"priority":1}]}')
    T.isnil(list, "no category with a name")
    T.eq(why, "it has no groups in it")
    -- A newer export with fields this doesn't know still brings its categories.
    list = Cat.ReadShared('{"version":3,"categories":[{"name":"Ore","search":"ore","color":"ff0000","sections":[1]}]}')
    T.eq(list[1].search, "ore")
    _G.C_EncodingUtil = nil
    list, why = Cat.ReadShared('{"categories":[]}')
    T.isnil(list, "a client without the reader")
    T.eq(why, "this game client can't read bag groups")
end)

T.test("bags: Baganator moves to built-in categories: game names, deleted groups and long names", function()
    local ns = catLogin()
    local Cat = ns.Categories
    _G.C_EncodingUtil = { DeserializeJSON = readJSON }
    local long = string.rep("Long name ", 7)
    Cat.Delete("weapon")
    local had = C_Item.GetItemClassInfo
    C_Item.GetItemClassInfo = function(id) return id == 3 and "Gem" or nil end
    local list = Cat.ReadShared('{"categories":[{"name":"' .. long .. '","search":""}],"modifications":['
        .. '{"source":"' .. long .. '","items":[25]},{"source":"default_weapon","items":[2589]},'
        .. '{"source":"default_gem","items":[818]},{"source":"default_auto_inventory_slots","items":[17]},'
        .. '{"source":"default_hearthstone","items":[6948]}]}')
    C_Item.GetItemClassInfo = had
    local notes = table.concat(list.notes, "; ")
    T.truthy(notes:find("items moved to Gem, Gear by slot", 1, true), "the game's own word, else a plain one: " .. notes)
    T.truthy(notes:find("items moved to Weapons, a group you deleted", 1, true), notes)
    local n, moved = Cat.ImportShared(list)
    T.eq(n, 1)
    T.eq(Cat.PinOf(25), Cat.Custom()[1].key, "a name over 60 letters still finds its items")
    T.isnil(Cat.PinOf(2589), "never pinned to a deleted group")
    T.eq(moved.hearthstone, 1)
    -- Only moves to built-in groups: nothing reads "Imported 0".
    n, moved = Cat.ImportShared(Cat.ReadShared('{"categories":[],"modifications":[{"source":"default_hearthstone","items":[6948]}]}'))
    local lines = table.concat(Cat.ImportLines(n, moved, {}), "\n")
    T.falsy(lines:find("Imported 0", 1, true), lines)
    T.truthy(lines:find("1 item moved to Hearthstone.", 1, true), lines)
    _G.C_EncodingUtil = nil
end)

T.test("bags: Import groups in the options takes a Baganator export, spaces and all", function()
    local ns = catLogin()
    local Cat = ns.Categories
    _G.C_EncodingUtil = { DeserializeJSON = readJSON }
    local printed = {}
    local print0 = DaylightUI.Print
    DaylightUI.Print = function(msg) printed[#printed + 1] = msg end
    local share
    for _, page in ipairs(ns.OPTIONS.pages) do
        for _, card in ipairs(page.groups or {}) do
            for _, item in ipairs(card.items) do if item.label == "Share your groups" then share = item end end
        end
    end
    local row = CreateFrame("Frame")
    share.build(row)
    row.inn:GetScript("OnClick")(row.inn)
    local box = _G.DaylightUIProfileBox
    local changed = box.edit:GetScript("OnTextChanged")
    -- A paste: the box puts the long text in lines, taking its spaces out.
    box.edit.__text = BAGANATOR
    changed(box.edit, true)
    T.falsy(box.edit:GetText():find("Toys and Pets", 1, true), "wrapped in the box")
    local status = box.status.__text
    T.truthy(status:find("Toys and Pets", 1, true), status)
    T.truthy(status:find("Some Baganator rules have no match here.", 1, true), status)
    -- Typing in the wrapped text can't bring the spaces back: say so.
    box.edit.__text = string.gsub(box.edit:GetText(), "Keepers", "Keeper")
    changed(box.edit, true)
    T.truthy(box.status.__text:find("paste it again", 1, true), box.status.__text)
    -- Pasted again whole, it imports with its spaces.
    box.edit.__text = BAGANATOR
    changed(box.edit, true)
    box.go:GetScript("OnClick")()
    local names = {}
    for _, g in ipairs(Cat.Custom()) do names[g.name] = true end
    T.truthy(names["Toys and Pets"], "its spaces kept")
    local said = table.concat(printed, "\n")
    T.truthy(said:find("Imported 4 bag groups.", 1, true), said)
    T.truthy(said:find("marked as junk", 1, true), said)
    T.truthy(said:find("Not brought over from Baganator:", 1, true), said)
    DaylightUI.Print = print0
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

T.test("bank: sorting the bank glides the bank, the open bag stays put", function()
    local ns, bank = bankLogin()
    local Feel = DaylightUI.Win.Feel
    world.items[6][3] = { iconFileID = 603, stackCount = 1, quality = 1, hyperlink = "|Hitem:63|h", itemID = 63 }
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local f, bag = ns.bank, ns.window
    T.truthy(f:IsShown() and bag:IsShown(), "the bank opens the bags too")
    ns.Relayout()
    settleFeel()
    local one, three = ns.Bank.set.buttons[6][1], ns.Bank.set.buttons[6][3]
    local x1, y1 = at(one)
    local x3, y3 = at(three)
    f.sort:GetScript("OnClick")(f.sort)
    T.eq(bank.calls.sort, 0, "the game sorts the bank")
    T.truthy(f.sorting, "the bank holds")
    T.isnil(bag.sorting, "the bag doesn't")
    sortStep(1, 3, 6)
    stub.RunTimers()
    T.falsy(Feel.Moving(three), "nothing moves while it's sorting")
    stub.Advance(ns.Window.SORT_SETTLE)
    stub.RunTimers()
    T.isnil(f.sorting, "settled")
    T.truthy(Feel.Moving(one) and Feel.Moving(three), "both bank slots glide")
    T.eq(select(4, three:GetPoint(1)), x1, "the item that moved starts where it was")
    T.eq(select(5, three:GetPoint(1)), y1)
    T.eq(select(4, one:GetPoint(1)), x3)
    T.eq(select(5, one:GetPoint(1)), y3)
    T.truthy(filledRight(f), "the bank shows what's there")
    for _, s in ipairs(bag.set.Slots()) do T.falsy(Feel.Moving(s.button), "the bag stays put") end
    settleFeel()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    T.truthy(ns.bank.packed and next(ns.bank.packed), "the bank's Shelf is packed like the bags'")
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
