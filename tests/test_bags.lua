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

T.test("bags: dragging the corner grip adds whole columns, saved on release", function()
    local ns = login()
    local f = open(ns)
    local cfg = f.Cfg()
    local step = cfg.iconSize + cfg.spacing
    local cols, wide = cfg.columns, f:GetWidth()
    f.GetLeft = function() return 300 end
    f.GetTop = function() return 700 end
    local cx = 1000
    local old = GetCursorPosition
    GetCursorPosition = function() return cx, 200 end
    local grip = f.grip
    T.truthy(grip, "the grip")
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    cx = 1000 + 3 * step + 2
    grip:GetScript("OnUpdate")(grip, 0.01)
    T.eq(f.Cfg().columns, cols + 3, "three more columns while dragging")
    T.eq(DaylightUI:Get("Bags", "columns"), cols, "not saved yet")
    T.eq(f:GetWidth(), wide + 3 * step, "the window widened by three slots")
    grip:GetScript("OnMouseUp")(grip, "LeftButton")
    stub.RunTimers()
    GetCursorPosition = old
    T.eq(DaylightUI:Get("Bags", "columns"), cols + 3, "saved on release")
    T.eq(f.Cfg().columns, cols + 3)
    grip:GetScript("OnMouseUp")(grip, "RightButton")
    stub.RunTimers()
    T.eq(DaylightUI:Get("Bags", "columns"), cols, "right-click puts the default back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: with the header off the search tops the window and a bank button sits by the X", function()
    local ns = login()
    local f = open(ns)
    local _, _, _, _, withY = f.search:GetPoint(1)
    local tall = f:GetHeight()
    DaylightUI:Set("Bags", "showHeader", false)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(f.portrait:IsShown(), "no portrait")
    T.falsy(f.title:IsShown(), "no title")
    T.falsy(f.sub:IsShown(), "no free count line")
    T.truthy(f.bankButton and f.bankButton:IsShown(), "the bank button shows")
    local _, rel = f.bankButton:GetPoint(1)
    T.eq(rel, f.close, "beside the X")
    local _, _, _, _, y = f.search:GetPoint(1)
    T.truthy(y > withY, "the search moved up")
    T.eq(f:GetHeight(), tall - (ns.Window.TITLE - ns.Window.Top(f)), "the window lost the header's height")
    T.truthy(f:GetScript("OnDragStart"), "the window drags by itself")
    local opened = 0
    ns.Viewer.ToggleBank = function() opened = opened + 1 end
    f.bankButton:GetScript("OnClick")(f.bankButton, "LeftButton")
    T.eq(opened, 1, "a click opens the bank")
    DaylightUI:Set("Bags", "showHeader", true)
    stub.RunTimers()
    T.truthy(f.portrait:IsShown() and f.title:IsShown(), "the header is back")
    T.falsy(f.bankButton:IsShown(), "the bank button goes with it")
    T.isnil(f:GetScript("OnDragStart"))
    T.eq(f:GetHeight(), tall)
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

T.test("bags: the tooltip counts switch off", function()
    local ns = countWorld()
    DaylightUI:Set("Bags", "viewer.tipCounts", false)
    T.eq(#tipRows(ns, { id = 1 }), 0, "nothing added")
    DaylightUI:Set("Bags", "viewer.tipCounts", true)
    T.eq(#tipRows(ns, { id = 1 }), 5, "back on")
end)

T.test("bags: item counts show only when some are outside this character's bags", function()
    local ns = countWorld()
    T.eq(#tipRows(ns, { id = 6 }), 0, "only in this character's bags: nothing added")
    local banked = tipRows(ns, { id = 4 })
    T.eq(#banked, 4, "this character and the account bank: both counted, then the total")
    T.eq(plainText(banked[2][2]), "Bags 1")
    T.eq(plainText(banked[3][2]), "1", "the account bank")
    T.eq(plainText(banked[4][2]), "2", "the total")
    local rows = tipRows(ns, { id = 9 })
    T.eq(rows[2][1], "Alt", "only on another character: just that one")
    T.eq(plainText(rows[2][2]), "Bags 1")
    T.eq(#rows, 3, "and the total")
    T.eq(#tipRows(ns, { id = 77 }), 0, "nobody has it")
    T.eq(#tipRows(ns, {}), 0, "no item")
    T.eq(#tipRows(ns, { id = stub.Secret(1) }), 0, "a secret item id is left alone")
end)

T.test("bags: characters on another ruleset are left out of counts and the viewer", function()
    local was = _G.GetRealmName
    _G.GetRealmName = function() return "CAMWOW US1 Realm 8 PvP" end
    local ns = login()
    local chars = DaylightUI.DB.Root().characters
    local bags = function(n) return { { section = "bags", size = 4, items = { [1] = { "|Hitem:9|h", n } } } } end
    chars["Twin-CAMWOW US2 Realm 3 PvP"] = { inventory = { class = "MAGE", time = time(), bags = bags(2) } }
    chars["Brave-CAMWOW US1 Realm 3 Hardcore"] = { inventory = { class = "ROGUE", time = time(), bags = bags(5) } }
    ns.Saved.ForgetCounts()
    local names = {}
    for _, c in ipairs(ns.Saved.Characters()) do names[c.name] = true end
    T.truthy(names.Twin, "the same ruleset on another realm is listed")
    T.falsy(names.Brave, "Hardcore isn't, from a PvP character")
    local rows = tipRows(ns, { id = 9 })
    T.eq(rows[2][1], "Twin")
    T.eq(#rows, 3, "Twin and the total, nothing from Hardcore")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.GetRealmName = was
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
    local l, r, t, b = slot.icon:GetTexCoord()
    T.eq(l, ns.Items.CROP[1], "the icon stays cropped after the game sets its picture (no frame inside the ring)")
    T.eq(b, ns.Items.CROP[4])
    C_Item.GetItemIconByID = oldIcon
    _G.Item = nil
end)

T.test("bags: a stack that loses its icon after one is used keeps its picture", function()
    local ns = login()
    _G.Item = { CreateFromBagAndSlot = function(_, bag, slot)
        return { IsItemEmpty = function() return false end, ContinueOnItemLoad = function(_, fn) fn() end }
    end }
    local oldIcon, oldInstant = C_Item.GetItemIconByID, C_Item.GetItemInfoInstant
    C_Item.GetItemIconByID = function() return nil end
    C_Item.GetItemInfoInstant = function() return nil end
    open(ns)
    local slot = ns.Bags.buttons[0][3]
    world.items[0][3] = { stackCount = 5, quality = 1, hyperlink = "|Hitem:17031|h", itemID = 17031, iconFileID = 134419 }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(slot.calls.SetItemButtonTexture[1], 134419)
    -- one rune used: the slot reports the smaller stack with no icon
    world.items[0][3] = { stackCount = 4, quality = 1, hyperlink = "|Hitem:17031|h", itemID = 17031 }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(slot.calls.SetItemButtonTexture[1], 134419, "the same picture, not a blank tile")
    T.eq(slot.icon:GetAlpha(), 1, "shown")
    -- an item never seen with an icon: its basic info has one
    C_Item.GetItemInfoInstant = function(id) return id, "", "", "", 999 end
    world.items[0][4] = { stackCount = 1, quality = 1, hyperlink = "|Hitem:4|h", itemID = 4 }
    stub.FireEvent("BAG_UPDATE", 0)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    T.eq(ns.Bags.buttons[0][4].calls.SetItemButtonTexture[1], 999, "the icon from the item's basic info")
    C_Item.GetItemIconByID, C_Item.GetItemInfoInstant = oldIcon, oldInstant
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
    T.eq(DaylightUI:Get("Bags", "markCheapJunk"), false, "off as shipped")
    DaylightUI:Set("Bags", "markCheapJunk", true)
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

T.test("bags: a warlock over their Soul Shard limit gets a button that deletes the extra ones, one a click after a second click", function()
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
    DaylightUI:Set("Bags", "shardsKeep", 2)
    stub.Advance(1); stub.RunTimers()
    T.truthy(b:IsShown(), "5 shards, keep 2")
    T.eq(b.text:GetText(), "Delete 1 of 3 extra shards", "one a click, and how many are over")
    -- In a raid its own limit counts.
    DaylightUI:Set("Bags", "shardsKeepRaid", 10)
    stub.inRaid = true
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.Advance(1); stub.RunTimers()
    T.falsy(b:IsShown(), "keep 10 in a raid")
    stub.inRaid = false
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.Advance(1); stub.RunTimers()
    T.truthy(b:IsShown())
    -- The game's cursor and delete, recorded. Seen in game: one item deleted per
    -- click; the delete reaches the server a moment later, the slot locked till then.
    local deleted, pending = {}, {}
    C_Container.PickupContainerItem = function(bag, slot)
        local it = world.items[bag] and world.items[bag][slot]
        stub.cursor = it and { "item", it.itemID, bag, slot } or nil
    end
    _G.DeleteCursorItem = function()
        local c = stub.cursor
        if c then
            deleted[#deleted + 1] = c[3] .. ":" .. c[4]
            world.items[c[3]][c[4]].isLocked = true
            pending[#pending + 1] = c
        end
        stub.cursor = nil
    end
    local function server()
        for _, c in ipairs(pending) do world.items[c[3]][c[4]] = nil end
        pending = {}
        stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.Advance(1); stub.RunTimers()
    end
    _G.CursorHasItem = function() return stub.cursor ~= nil end
    b:GetScript("OnClick")(b)
    T.eq(#deleted, 0, "the first click only asks")
    T.eq(b.text:GetText(), "Click again")
    stub.Advance(1)
    b:GetScript("OnClick")(b)
    T.eq(table.concat(deleted, ","), "0:11", "one shard, from the last slot back")
    T.eq(b.text:GetText(), "Delete 1 of 2 extra shards", "the one on its way no longer counts")
    -- Quick clicks before the server answers: each the next shard, never past the limit.
    b:GetScript("OnClick")(b)
    b:GetScript("OnClick")(b)
    T.eq(table.concat(deleted, ","), "0:11,0:10,0:9", "no asking again, and never under the limit")
    server()
    T.falsy(b:IsShown(), "at the limit: gone")
    T.truthy(stub.ChatContains("Deleted 3 Soul Shards."), "the total said once")
    T.truthy(world.items[0][7] and world.items[0][8], "the 2 kept stay")
    T.truthy(world.items[1][1], "the item that isn't a shard stays")
    -- Something else on the cursor after picking up: nothing deleted.
    world.items[0][12] = { iconFileID = 600, stackCount = 1, quality = 1, hyperlink = "|Hitem:6265|h", itemID = 6265 }
    stub.FireEvent("BAG_UPDATE", 0); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.Advance(1); stub.RunTimers()
    C_Container.PickupContainerItem = function() stub.cursor = { "item", 1234 } end
    deleted = {}
    T.eq(ns.Junk.DeleteShards(), 0)
    T.eq(#deleted, 0, "the cursor didn't hold a shard: put back, nothing deleted")
    T.isnil(stub.cursor)
    -- A soul bag stays full: the extra shards go from the other bags first.
    C_Container.PickupContainerItem = function(bag, slot)
        local it = world.items[bag] and world.items[bag][slot]
        stub.cursor = it and { "item", it.itemID, bag, slot } or nil
    end
    world.family = { [1] = 4 }
    world.items[1][5] = { iconFileID = 600, stackCount = 1, quality = 1, hyperlink = "|Hitem:6265|h", itemID = 6265 }
    world.items[1][6] = { iconFileID = 600, stackCount = 1, quality = 1, hyperlink = "|Hitem:6265|h", itemID = 6265 }
    stub.FireEvent("BAG_UPDATE", 1); stub.FireEvent("BAG_UPDATE_DELAYED"); stub.Advance(1); stub.RunTimers()
    deleted = {}
    T.eq(ns.Junk.DeleteShards(), 1)
    T.eq(ns.Junk.DeleteShards(), 1)
    T.eq(ns.Junk.DeleteShards(), 1)
    T.eq(ns.Junk.DeleteShards(), 0, "at the limit")
    T.truthy(world.items[1][5] and world.items[1][6], "the soul bag's shards stay")
    T.truthy(not deleted[1]:find("^1:"), "the first one deleted is from a plain bag")
    world.family = nil
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

-- The bag closing under a resting mouse (a vendor walked away from, Escape)
-- sends no leave, and the other bags stayed dimmed through every later open.
T.test("bags: a bag hovered in the strip as the window closes leaves nothing dimmed", function()
    local ns = login()
    local f = open(ns)
    DaylightUI:Set("Bags", "showSlots", true); stub.RunTimers()   -- the strip shows
    local B, Items, Slots = ns.Bags, ns.Items, ns.Slots
    local bag1 = Slots.strip.slots[1]
    stub.MouseEnter(bag1)
    T.eq(B.buttons[0][1]:GetAlpha(), Slots.DIM, "dimmed while the bag is hovered")
    f:Hide()
    stub.RunTimers()
    open(ns)
    T.eq(B.buttons[0][1]:GetAlpha(), 1, "the next open shows every slot whole")
    T.falsy(Items.Parts(B.buttons[1][7]).lit, "and no bag still outlined")
end)

-- A bag update re-shows a hovered bag's tooltip, but only while the mouse is
-- really there: after leaving, it lit that bag again with no leave to follow.
T.test("bags: a bag update never lights a strip bag the mouse has left", function()
    local ns = login()
    open(ns)
    DaylightUI:Set("Bags", "showSlots", true); stub.RunTimers()
    local B, Slots = ns.Bags, ns.Slots
    local bag1 = Slots.strip.slots[1]
    local tip = GameTooltip
    local realOwner, realShown, realHide = tip.GetOwner, tip.IsShown, tip.Hide
    tip.GetOwner = function() return bag1 end
    tip.IsShown = function() return true end   -- still fading out, or held by another addon
    tip.Hide = function() end
    stub.MouseEnter(bag1)
    stub.MouseLeave(bag1)
    stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
    T.eq(B.buttons[0][1]:GetAlpha(), 1, "the mouse is elsewhere: nothing dims")
    tip.GetOwner, tip.IsShown, tip.Hide = realOwner, realShown, realHide
end)

-- A bag swapped while the mouse rests on its slot: the tooltip kept the old bag.
T.test("bags: a hovered bag slot's tooltip follows a swap under the mouse", function()
    local ns = login()
    open(ns)
    DaylightUI:Set("Bags", "showSlots", true); stub.RunTimers()   -- the strip shows
    local bag1 = ns.Slots.strip.slots[1]
    T.truthy(ns.Slots.strip:IsVisible(), "the strip is up")
    local owner, shown, asked = nil, false, 0
    local tip = GameTooltip
    local realOwner, realSetOwner, realShown, realInv, realShow, realHide =
        tip.GetOwner, tip.SetOwner, tip.IsShown, tip.SetInventoryItem, tip.Show, tip.Hide
    tip.SetOwner = function(_, o) owner = o end
    tip.GetOwner = function() return owner end
    tip.Show = function() shown = true end
    tip.Hide = function() shown = false end
    tip.IsShown = function() return shown end
    tip.SetInventoryItem = function() asked = asked + 1; return true end
    stub.MouseEnter(bag1)
    T.eq(asked, 1, "hovered")
    stub.FireEvent("BAG_CONTAINER_UPDATE"); stub.RunTimers()
    T.eq(asked, 2, "swapped under the mouse: shown again")
    stub.MouseLeave(bag1)
    stub.FireEvent("BAG_CONTAINER_UPDATE"); stub.RunTimers()
    T.eq(asked, 2, "not hovered: left alone")
    tip.GetOwner, tip.SetOwner, tip.IsShown, tip.SetInventoryItem, tip.Show, tip.Hide =
        realOwner, realSetOwner, realShown, realInv, realShow, realHide
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

    -- A strip refresh repaints the bag slots, never the key.
    ns.module.db.showSlots = true
    ns.Slots.Apply()
    Slots.Refresh()
    T.eq(key.icon:GetTexture(), Slots.KEY_ICON, "refreshed: still the key icon")
    ns.module.db.showSlots = nil

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
    T.truthy(Items.Parts(boe).set:IsShown(), "in a set: marked")
    T.falsy(Items.Parts(rare).set:IsShown())
    T.eq(boe.JunkIcon:GetAlpha(), 0, "the junk coin off by default")
    T.eq(boe.UpgradeIcon:GetAlpha(), 0, "no upgrade arrow")
    DaylightUI:Set("Bags", "showSet", false)
    stub.RunTimers()
    T.falsy(Items.Parts(boe).set:IsShown(), "the set mark switched off")
    DaylightUI:Set("Bags", "showSet", true)
    DaylightUI:Set("Bags", "showJunk", true)
    DaylightUI:Set("Bags", "showBind", false)
    stub.RunTimers()
    T.truthy(Items.Parts(boe).set:IsShown())
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
    -- Seen in game: the cooldown update after login (the game's UpdateCooldown
    -- whitens the icon) took the red off until the setting was switched.
    stub.FireEvent("BAG_UPDATE_COOLDOWN")
    stub.RunTimers()
    T.eq(tint(bad), RED_ICON, "a cooldown update keeps the red")
    T.eq(tint(fine), "1.00 1.00 1.00")
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

T.test("bags: a recipe your profession skill is too low for wears the red, not one whose made item needs a level", function()
    local ns = login()
    -- Seen in game: IsUsableItem says yes to a cooking recipe with the skill too low;
    -- only the recipe's own red "Requires Cooking (110)" line tells.
    local RED, WHITE = { r = 1, g = 0.125, b = 0.125 }, { r = 1, g = 1, b = 1 }
    _G.ITEM_MIN_SKILL = "Requires %s (%d)"
    C_Item.GetItemInfoInstant = function() return 1, "Recipe", "Cooking", "", 1, ns.Items.RECIPE, 5 end
    C_Item.IsUsableItem = function() return true end
    local skill = RED
    _G.C_TooltipInfo = { GetBagItem = function(bag, slot)
        return { lines = { { leftText = "Recipe: Big Bear Steak", leftColor = WHITE },
                           { leftText = "Big Bear Steak", leftColor = WHITE },
                           { leftText = "Requires Level 50", leftColor = RED },
                           { leftText = "Use: Teaches you how to cook a Big Bear Steak.", leftColor = WHITE },
                           { leftText = "Requires Cooking (110)", leftColor = skill } } }
    end }
    open(ns)
    local recipe = ns.Bags.buttons[0][1]
    T.truthy(recipe.dluiUnusable, "skill too low: red")
    skill = WHITE
    ns.Items.ForgetUsable()
    ns.FillAll(); stub.RunTimers()
    T.falsy(recipe.dluiUnusable, "the made item's red level alone doesn't count")
    C_Item.IsUsableItem = nil
    _G.C_TooltipInfo = nil
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

-- Kravel's Crate is a consumable bound as a quest item. The slot's quest info
-- read false at times, and it landed under Consumables.
T.test("bags: an item bound as a quest item is a quest item, whatever its class", function()
    local ns = login()
    local crate = { classID = 0, subClassID = 8, quality = 1, name = "Kravel's Crate", bindType = 4, questItem = false }
    T.truthy(ns.Search.Parse("quest")(crate), "the quest search finds it")
    T.truthy(ns.Categories.TESTS.quest(crate), "in Quest items")
    T.falsy(ns.Categories.TESTS.junk({ classID = 0, quality = 0, bindType = 4 }), "never Junk")
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
    local help = {}
    local tip = {}
    function tip:AddLine(text) help[#help + 1] = text end
    function tip:AddDoubleLine() end
    S.Tip(tip)
    T.truthy(table.concat(help, "\n"):find("; works like |", 1, true), "the search's help teaches ;")
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

-- Shift-click keeps Disenchant on: a cast button follows the pointer over each
-- item that can take it and names the slot (target-bag, target-slot), so every
-- click disenchants until the button is clicked again, the bag closes or a
-- fight starts.
T.test("bags: Shift-click keeps Disenchant on for every item clicked until the button, a close or a fight ends it", function()
    local ns = login()
    local DE = ns.Disenchant
    _G.IsPlayerSpell = function(id) return id == DE.SPELL end
    stub.FireEvent("SPELLS_CHANGED")
    -- Items 4 and 7 are green armor; the rest of the bag isn't gear.
    local armor = { [4] = true, [7] = true }
    local getInstant = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(id)
        local n = type(id) == "number" and id or tonumber(string.match(tostring(id), "item:(%d+)"))
        return n, "", "", "", 0, armor[n] and 4 or 0, 0
    end
    -- The spell's hand: up after the cast, gone once an item is handed to it.
    local hand, casts, used = false, 0, {}
    stub.CastSpell = function(spell) if tonumber(spell) == DE.SPELL then casts = casts + 1; hand = true end end
    _G.SpellCanTargetItem = function() return hand end
    C_Container.UseContainerItem = function(bag, slot)
        if hand then used[#used + 1] = bag .. ":" .. slot; hand = false end
    end
    local f = open(ns)
    stub.secure = true
    local b = f.disenchantButton
    b.GetLeft, b.GetBottom = function() return 400 end, function() return 300 end
    b:SetSize(28, 28)
    local function place(slotButton, x)
        slotButton.GetLeft, slotButton.GetBottom = function() return x end, function() return 200 end
        slotButton:SetSize(37, 37)
    end
    local green, green2, gray = ns.Bags.buttons[0][4], ns.Bags.buttons[0][6], ns.Bags.buttons[0][2]
    place(green, 100); place(green2, 140); place(gray, 180)
    local function shiftClick()
        b:GetScript("OnEnter")(b)
        stub.shift = true
        stub.SecureClick(DE.caster.button, "LeftButton")
        stub.shift = nil
    end

    -- Shift-click: nothing cast, it stays on, held in the accent.
    shiftClick()
    T.eq(casts, 0, "Shift-click casts nothing: type1 is the plain click only")
    T.truthy(DE.on, "Shift-click turns it on")
    T.falsy(DE.caster.button:IsShown(), "on, the button casts nothing: its plain click turns it off")
    local Driver = DaylightUI.Motion.Driver()
    if Driver then stub.RunOnUpdate(Driver, 1) end
    T.near((b.icon:GetVertexColor()), (DaylightUI.Style.Accent()), 0.01, "held in the accent while on")
    T.truthy(ns.Items.Fits(0, 4, C_Container.GetContainerItemInfo(0, 4), f), "green armor stands out")
    T.falsy(ns.Items.Fits(0, 2, C_Container.GetContainerItemInfo(0, 2), f), "what it can't take dims")

    -- The first item.
    green:GetScript("OnEnter")(green)
    local o = DE.slotCaster.button
    T.truthy(o and o:IsShown(), "a cast button over the item")
    T.eq(o:GetParent(), UIParent, "never inside the bag")
    T.eq(o:GetAttribute("type1"), "spell"); T.eq(o:GetAttribute("spell"), DE.SPELL)
    T.eq(o:GetAttribute("target-bag"), 0); T.eq(o:GetAttribute("target-slot"), 4)
    stub.SecureClick(o, "LeftButton")
    T.deq(used, { "0:4" }, "the click disenchants that item")
    o:GetScript("OnLeave")(o)
    T.falsy(o:IsShown(), "the pointer left: it goes")

    -- The second, with no new Shift-click.
    green2:GetScript("OnEnter")(green2)
    T.truthy(o:IsShown())
    T.eq(o:GetAttribute("target-slot"), 6)
    stub.SecureClick(o, "LeftButton")
    T.deq(used, { "0:4", "0:6" }, "the next click disenchants the next item")
    T.truthy(DE.on, "still on")
    o:GetScript("OnLeave")(o)

    -- An item it can't take keeps its own click.
    gray:GetScript("OnEnter")(gray)
    T.falsy(o:IsShown(), "a gray item: no cast button")
    gray:GetScript("OnLeave")(gray)

    -- A plain click on the button turns it off.
    green:GetScript("OnEnter")(green)
    T.truthy(o:IsShown())
    b:GetScript("OnClick")(b, "LeftButton")
    T.falsy(DE.on, "a plain click turns it off")
    T.falsy(o:IsShown(), "and the cast button over the item goes")
    T.truthy(ns.Items.Fits(0, 2, C_Container.GetContainerItemInfo(0, 2), f), "nothing dims any more")
    green:GetScript("OnEnter")(green)
    T.falsy(o:IsShown(), "off: the item's own click again")

    -- Closing the bag turns it off.
    shiftClick()
    T.truthy(DE.on)
    f:Hide()
    T.falsy(DE.on, "closing the bag turns it off")

    -- So does a fight, and none starts in one.
    f = open(ns)
    shiftClick()
    T.truthy(DE.on)
    green:GetScript("OnEnter")(green)
    T.truthy(o:IsShown())
    stub.EnterCombat()
    T.falsy(DE.on, "a fight turns it off")
    T.falsy(o:IsShown(), "and the cast button goes before the lockdown")
    DE.Clicked()
    stub.shift = true; DE.Clicked(); stub.shift = nil
    T.falsy(DE.on, "never turned on in a fight")
    stub.LeaveCombat()

    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.secure, stub.CastSpell, _G.SpellCanTargetItem, _G.IsPlayerSpell = false, nil, nil, nil
    C_Item.GetItemInfoInstant = getInstant
end)

T.test("bags: the Pick Lock button: shown to rogues who know it, last beside the search, casting Pick Lock", function()
    local ns = login()
    local PL = ns.PickLock
    T.eq(PL.SPELL, 1804)
    local known = {}
    _G.IsPlayerSpell = function(id) return known[id] == true end
    stub.FireEvent("SPELLS_CHANGED")
    local f = open(ns)
    local b = f.pickLockButton
    T.falsy(b:IsShown(), "not known: no button")
    known[PL.SPELL] = true
    stub.FireEvent("SPELLS_CHANGED")
    T.truthy(b:IsShown())
    T.eq(select(2, f.search:GetPoint(2)), b, "the search ends at it")
    T.truthy(tostring(b.icon:GetTexture()):find("ui%-lock%.png"), "a flat icon like the rest of the row")
    b.GetLeft, b.GetBottom = function() return 360 end, function() return 300 end
    b:SetSize(28, 28)
    stub.secure = true
    b:GetScript("OnEnter")(b)
    local o = PL.caster.button
    T.truthy(o and o:IsShown(), "the secure button lies over it")
    T.eq(o:GetAttribute("type1"), "spell"); T.eq(o:GetAttribute("spell"), PL.SPELL)
    stub.secure = nil
    _G.IsPlayerSpell = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: the Comprehend Scroll button: shown to those who know it, beside Disenchant; hovered, it casts the spell", function()
    local ns = login()
    local CS, DE = ns.Comprehend, ns.Disenchant
    T.eq(CS.SPELL, 1296017)
    local known = {}
    _G.IsPlayerSpell = function(id) return known[id] == true end
    local getTex = C_Spell.GetSpellTexture
    C_Spell.GetSpellTexture = function(id) return id == CS.SPELL and 134937 or nil end
    stub.FireEvent("SPELLS_CHANGED")
    local f = open(ns)
    local b = f.comprehendButton
    T.falsy(b:IsShown(), "spell not known: no button")
    T.eq(select(2, f.search:GetPoint(2)), f.viewButton, "the search ends at the last tool shown")
    known[CS.SPELL] = true
    stub.FireEvent("SPELLS_CHANGED")
    T.truthy(b:IsShown())
    T.falsy(f.disenchantButton:IsShown(), "Disenchant still follows its own spell")
    T.eq(select(2, f.search:GetPoint(2)), b, "the search ends at it")
    T.truthy(tostring(b.icon:GetTexture()):find("ui%-micro%-quests%.png"), "a flat icon like the rest of the row")
    known[DE.SPELL] = true
    stub.FireEvent("SPELLS_CHANGED")
    T.truthy(f.disenchantButton:IsShown(), "both known: both shown")
    T.eq(select(2, f.search:GetPoint(2)), b, "Comprehend Scroll sits next to the search")
    b.GetLeft, b.GetBottom = function() return 360 end, function() return 300 end
    b:SetSize(28, 28)
    stub.secure = true
    T.isnil(CS.caster.button, "nothing secure until the mouse comes")
    b:GetScript("OnEnter")(b)
    local o = CS.caster.button
    T.truthy(o and o:IsShown(), "the secure button lies over ours")
    T.truthy(o ~= DE.caster.button, "its own secure button, not Disenchant's")
    T.eq(o:GetAttribute("type1"), "spell"); T.eq(o:GetAttribute("spell"), CS.SPELL)
    T.eq(o:GetParent(), UIParent, "never inside the bag: the bag still closes in a fight")
    T.eq(o:GetFrameStrata(), "HIGH")
    stub.EnterCombat()
    T.falsy(o:IsShown(), "hidden as the fight starts")
    stub.LeaveCombat()
    b:GetScript("OnEnter")(b)
    known[CS.SPELL] = nil
    stub.FireEvent("SPELLS_CHANGED")
    T.falsy(b:IsShown(), "forgotten: the button goes")
    T.falsy(o:IsShown(), "and its secure button with it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.secure = false
    _G.IsPlayerSpell = nil
    C_Spell.GetSpellTexture = getTex
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

-- The keyring's free slots looked exactly like free bag slots under Empty, and
-- its keys mixed with the bags' own under Keys.
T.test("bags: on the Shelf the keyring is its own group, its free slots out of Empty", function()
    local ns = login({ keyring = true, keyringSize = 4, view = "categories" })
    categoryWorld()
    world.items[-2] = { [1] = { iconFileID = 901, stackCount = 1, quality = 1, hyperlink = "|Hitem:90|h", itemID = 90 } }
    ns.module.db.showKeyring = true
    ns.Refresh(ns.module)
    local f = open(ns)
    ns.Relayout()
    ns.FillAll()
    local B = ns.Bags
    T.eq(groupOf(ns, B.buttons[-2][1]), "keyring", "a key on the keyring")
    T.eq(groupOf(ns, B.buttons[-2][2]), "keyring", "a free keyring slot stays with the keyring")
    local counts = {}
    for _, h in ipairs(f.headings) do
        if h:IsShown() then counts[h.key] = h.count:GetText() end
    end
    T.eq(counts.keyring, "1", "the heading counts the keys, not the free slots")
    local bagFree = 0
    for bag = 0, 5 do
        for slot = 1, world.sizes[bag] or 0 do
            if not (world.items[bag] and world.items[bag][slot]) then bagFree = bagFree + 1 end
        end
    end
    T.eq(counts.empty, tostring(bagFree), "Empty counts the bags' free slots only")
    -- Deleting the Keyring group puts its slots back where they were before.
    ns.Categories.Delete("keyring")
    T.eq(groupOf(ns, B.buttons[-2][1]), "key")
    T.eq(groupOf(ns, B.buttons[-2][2]), "empty")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

T.test("bags on a controller: Split stack picks an amount from a menu and puts it in a free slot", function()
    local ns = catLogin()
    cursorWorld()
    world.items[1][1].itemID = 7
    local bread = ns.Bags.buttons[1][1]                -- 7 Bread
    local W = DaylightUI.Widgets
    local realOpen, seen = W.OpenMenu, nil
    W.OpenMenu = function(_, keys, values, _, onPick) seen = { keys = keys, values = values, onPick = onPick } end
    ns.Window.PadMore(bread)
    T.truthy(seen and seen.values.split, "a Split stack row for a stack")
    seen.onPick("split")
    stub.RunTimers()
    T.eq(table.concat(seen.keys, " "), "1 2 3 4 5 6", "every amount for a small stack")
    T.eq(seen.values[3], "3 (half)")
    seen.onPick(2)
    W.OpenMenu = realOpen
    T.eq(world.items[1][1].stackCount, 5, "5 left behind")
    T.eq(world.items[0][3].stackCount, 2, "the 2 put down in the first free slot")
    T.falsy(CursorHasItem(), "nothing left on the cursor")
    T.eq(table.concat(ns.Stack.SplitAmounts(200), " "), "1 2 5 10 20 50 100", "a big stack: round numbers and half")
    T.eq(table.concat(ns.Stack.SplitAmounts(30), " "), "1 2 5 10 15 20")
    T.eq(#ns.Stack.SplitAmounts(1), 0, "a single item can't be split")
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

T.test("bags: a trade opens the bags and closes them again; bags already open stay open", function()
    local ns = catLogin()
    if ns.window:IsShown() then ns.OpenClose.CloseAll(); stub.RunTimers(); stub.FinishFade(ns.window) end
    T.falsy(IsAnyBagOpen())
    local calls = world.openAll
    stub.FireEvent("TRADE_SHOW"); stub.RunTimers()
    T.truthy(ns.window:IsShown(), "the trade opens this bag")
    T.eq(world.openAll, calls, "without the game's OpenAllBags (it would run tainted)")
    T.eq(world.opener, nil, "the game's local stays untouched")
    stub.FireEvent("TRADE_CLOSED"); stub.RunTimers(); stub.FinishFade(ns.window)
    T.falsy(ns.window:IsShown(), "closed with the trade")
    OpenAllBags(); stub.RunTimers()
    stub.FireEvent("TRADE_SHOW"); stub.RunTimers()
    stub.FireEvent("TRADE_CLOSED"); stub.RunTimers()
    T.truthy(IsAnyBagOpen(), "open before the trade: still open after")
    T.truthy(ns.window:IsShown())
    -- Held open for a trade, the bag key closes it, and an NPC closing its own
    -- window (CloseAllBags with a frame) leaves it be.
    CloseAllBags(); stub.RunTimers(); stub.FinishFade(ns.window)
    stub.FireEvent("TRADE_SHOW"); stub.RunTimers()
    CloseAllBags(UIParent); stub.RunTimers()
    T.truthy(ns.window:IsShown(), "another window's close leaves it")
    ToggleAllBags(); stub.RunTimers(); stub.FinishFade(ns.window)
    T.falsy(ns.window:IsShown(), "the bag key closes it")
    T.falsy(IsAnyBagOpen())
    stub.FireEvent("TRADE_CLOSED"); stub.RunTimers()
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

-- Folding a group gives its room back: a folded heading never sits beside an
-- open group (it left a hole under it there and saved no room), folded ones in a
-- row share one, and opening them all again puts everything back.
T.test("bags: a folded group gives its room back; folded headings share rows only with each other", function()
    local ns, f = catLogin()
    local Cat = ns.Categories
    local function spots()
        local t = {}
        for _, x in ipairs(f.headings) do
            if x:IsShown() and x.key then
                local _, _, _, px, py = x:GetPoint(1)
                t[x.key] = { px, py, x:GetWidth() }
            end
        end
        return t
    end
    local before = spots()
    local h0 = f.items:GetHeight()
    local topY, first = nil, {}
    for _, p in pairs(before) do topY = math.max(topY or p[2], p[2]) end
    for k, p in pairs(before) do if p[2] == topY then first[#first + 1] = k end end
    table.sort(first, function(a, b) return before[a][1] < before[b][1] end)
    T.truthy(#first > 1, "several groups share the first row")
    -- Fold the last group of the first row: it leaves the row of open groups.
    local last = first[#first]
    Cat.ToggleCollapsed(last)
    stub.RunTimers()
    local now = spots()
    for k, p in pairs(now) do
        T.truthy(k == last or p[2] ~= now[last][2], k .. " never shares a row with the folded " .. last)
    end
    -- Fold every group: all headings, packed together, and the bag gets shorter.
    for k in pairs(before) do if not Cat.IsCollapsed(k) then Cat.ToggleCollapsed(k) end end
    stub.RunTimers()
    now = spots()
    local rows = {}
    for _, p in pairs(now) do rows[p[2]] = true end
    local n = 0
    for _ in pairs(rows) do n = n + 1 end
    local groups = 0
    for _ in pairs(now) do groups = groups + 1 end
    T.truthy(n < groups, "folded headings share rows")
    T.truthy(f.items:GetHeight() < h0, "and the bag gets shorter")
    for k in pairs(before) do Cat.ToggleCollapsed(k) end
    stub.RunTimers()
    now = spots()
    for k, p in pairs(before) do T.deq(now[k], p, k .. " back where it was, all open again") end
end)

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

T.test("bags: the Shelf lays groups in level rows, in order, nothing overlapping", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy = packWorld(L, f, USER_BAG)
    local spots = L.Pack(boxes, maxW, gx, gy)
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
    T.eq(r[1].y, r[2].y, "Recent shares its row with the Hearthstone")
    -- Rows read top to bottom, each left to right, in group order.
    for i = 2, #r do
        local a, b = r[i - 1], r[i]
        T.truthy(b.y > a.y or (b.y == a.y and b.x > a.x), b.key .. " comes after " .. a.key)
    end
    -- Quest items (12) wrap to more lines than one, never stacked under another group.
    local quest = r[4]
    T.truthy(quest.lines > 1 and quest.lines <= 3, "quest items fold into a few lines: " .. quest.lines)
end)

T.test("bags: the Shelf's groups on a row wrap to the same number of lines where they can", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local bag = { { "consumable", 9, 104 }, { "quest", 12, 98 }, { "tradegoods", 16, 104 } }
    local boxes, maxW, gx, gy = packWorld(L, f, bag)
    local r = rects(boxes, L.Pack(boxes, maxW, gx, gy))
    for i = 2, #r do
        if r[i].y == r[1].y then T.eq(r[i].lines, r[1].lines, r[i].key .. " as many lines as " .. r[1].key) end
    end
end)

T.test("bags: a group alone on its row fills the bag's width", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy = packWorld(L, f, { { "quest", 12, 98 }, { "empty", 32, 50 } })
    boxes[2].breakBefore = true
    local r = rects(boxes, L.Pack(boxes, maxW, gx, gy))
    T.truthy(32 > boxes[2].cols, "more empty slots than the bag is wide")
    T.eq(r[2].w, maxW, "the empty slots run the bag's whole width")
end)

T.test("bags: a shared row gives its spare width to the groups that wrap, adding no line", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy = packWorld(L, f, { { "quest", 11, 98 }, { "weapon", 2, 76 } })
    local r = rects(boxes, L.Pack(boxes, maxW, gx, gy))
    T.eq(r[1].y, r[2].y, "both on one row")
    local size = (maxW - (boxes[1].cols - 1) * gx) / boxes[1].cols
    T.truthy(maxW - (r[2].x + r[2].w) < size + gx, "the row reaches the bag's edge, less than a slot short")
    T.eq(r[1].lines, 2, "quest items still two lines")
end)

T.test("bags: the Shelf's packing is the same every time and moves little when a count changes", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy = packWorld(L, f, USER_BAG)
    local a, ha = L.Pack(boxes, maxW, gx, gy)
    local b, hb = L.Pack(boxes, maxW, gx, gy)
    T.eq(ha, hb)
    for i = 1, #boxes do T.eq(a[i].x, b[i].x); T.eq(a[i].y, b[i].y); T.eq(a[i].shape.w, b[i].shape.w) end
    -- One more consumable.
    local more = {}
    for i, c in ipairs(USER_BAG) do more[i] = { c[1], c[2] + (c[1] == "consumable" and 1 or 0), c[3] } end
    local boxes2 = packWorld(L, f, more)
    local c = L.Pack(boxes2, maxW, gx, gy)
    local kept = 0
    for i = 1, #boxes do if c[i].x == a[i].x and c[i].y == a[i].y then kept = kept + 1 end end
    T.truthy(kept >= #boxes / 2, "most groups keep their spots: " .. kept .. " of " .. #boxes)
end)

-- Seen in game: Consumables folded beside an open Quest Items left a hole under
-- its heading, and folding it saved no room at all.
T.test("bags: a folded group packs as a heading on a row of folded ones", function()
    local ns, f = catLogin()
    local L = ns.Layout
    local boxes, maxW, gx, gy = packWorld(L, f, USER_BAG)
    local _, h0 = L.Pack(boxes, maxW, gx, gy)
    local headH = L.HeadH(f, f.Cfg())
    local fb = packWorld(L, f, USER_BAG)
    for _, b in ipairs(fb) do
        if b.key == "consumable" or b.key == "weapon" or b.key == "tradegoods" then
            b.folded, b.n = true, 0
            local w = b.shape(1).w
            b.shape = function() return { w = w, h = headH, across = 0 } end
        end
    end
    local now, h1 = L.Pack(fb, maxW, gx, gy)
    T.truthy(h1 < h0, "folding gives room back")
    for i, b in ipairs(fb) do
        for j, o in ipairs(fb) do
            if i ~= j and now[i].y == now[j].y then
                T.eq(b.folded or false, o.folded or false, b.key .. " and " .. o.key .. " share a row only when both fold or both open")
            end
        end
    end
    local wpn, tg
    for i, b in ipairs(fb) do
        if b.key == "weapon" then wpn = now[i] elseif b.key == "tradegoods" then tg = now[i] end
    end
    T.eq(wpn.y, tg.y, "folded groups next to each other share a row")
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

-- If GetPoint hands back a spot a hair off the one set (rounding in the client;
-- Feel's rest() allows half a pixel for it), the cross-fade must still land every
-- piece. Seen in game: after big eased layouts (loot, mail, a cleanup), slots and
-- headings sat scattered over the new layout until the view was switched or the
-- UI reloaded.
T.test("bags: a cross-fade made mid-glide lands every piece on the new layout", function()
    local real, realGet = stub.Widget.SetPoint, stub.Widget.GetPoint
    stub.Widget.GetPoint = function(self, i)
        local point, rel, relPoint, x, y = realGet(self, i)
        if type(x) == "number" then x = x + 1e-4 end
        if type(y) == "number" then y = y - 1e-4 end
        return point, rel, relPoint, x, y
    end
    local ns, f = catLogin()
    local max = ns.Layout.EASE_MAX
    local ok, err = pcall(function()
        local Feel, Motion = DaylightUI.Win.Feel, DaylightUI.Motion
        settleFeel()
        lootWeapon()
        stub.RunOnUpdate(Feel.Driver(), Motion.NORMAL / 3)
        -- Past this many moves the grid cross-fades; here the next loot does.
        ns.Layout.EASE_MAX = 0
        lootWeapon(11, 7)
        T.truthy(f.crossing, "the second loot cross-fades")
        settleFeel()
        settleFeel()
        local spots = {}
        for _, s in ipairs(f.set.Slots()) do
            if s.button:IsShown() then spots[s.button] = { at(s.button) } end
        end
        local heads = {}
        for _, h in ipairs(f.headings or {}) do
            if h:IsShown() then heads[h] = { at(h) } end
        end
        ns.Layout.EASE_MAX = max
        ns.Relayout()
        for b, xy in pairs(spots) do
            local x, y = at(b)
            T.truthy(math.abs(x - xy[1]) < 0.5 and math.abs(y - xy[2]) < 0.5,
                "slot " .. b:GetID() .. " landed on its spot: " .. xy[1] .. "," .. xy[2] .. " vs " .. x .. "," .. y)
        end
        for h, xy in pairs(heads) do
            local x, y = at(h)
            T.truthy(math.abs(x - xy[1]) < 0.5 and math.abs(y - xy[2]) < 0.5, "heading " .. tostring(h.key) .. " landed on its spot")
        end
    end)
    stub.Widget.SetPoint, stub.Widget.GetPoint = real, realGet
    ns.Layout.EASE_MAX = max
    T.truthy(ok, tostring(err))
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
    stub.Reply("Keepers")
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
    T.eq(BINDING_HEADER_DAYLIGHTUI, "Daylight UI", "in the Daylight UI key bindings")
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
    T.truthy(notes:find("items moved to Gem", 1, true), "the category by a name, not Baganator's key: " .. notes)
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

T.test("bags: Baganator's packed BGR!1! export comes over too", function()
    local ns = catLogin()
    local Cat = ns.Categories
    local pack = baganatorCodec()
    -- As its third export version writes it: priority with the modifications.
    local text = pack({ version = 3, addon = "Baganator", kind = "categories",
        categories = { { name = "Low", search = "#potion", source = "a" }, { name = "High", search = "#food", source = "b" } },
        modifications = { { source = "a", priority = 0 }, { source = "b", priority = 3, items = { 6948 } },
                          { source = "default_junk", items = { 4306 }, hideIn = {} } },
        hidden = {}, order = {} })
    -- The paste box wraps long text with line breaks.
    local list, said = Cat.ReadShared(string.sub(text, 1, 4) .. "\n" .. string.sub(text, 5))
    T.truthy(list, said)
    T.eq(list[1].name, "High", "the higher priority first")
    T.eq(list[2].name, "Low")
    T.eq(list[1].items[1], 6948)
    local n, moved = Cat.ImportShared(list)
    T.eq(n, 2)
    T.eq(moved.junk, 1)
    T.isnil(Cat.ReadShared("BGR!1!cbor999"), "damaged")
    _G.C_EncodingUtil = nil
end)

T.test("bags: a whole Baganator profile export brings its categories", function()
    local ns = catLogin()
    local Cat = ns.Categories
    local pack = baganatorCodec()
    local text = pack({ version = 3, addon = "Baganator", kind = "profile",
        custom_categories = { ["1"] = { name = "Ore", search = "ore" } },
        category_modifications = { ["1"] = { addedItems = { ["i:2770"] = true, ["p:12"] = true } },
                                   default_junk = { addedItems = { ["i:4306"] = true } } },
        category_hidden = { default_toy = true }, category_display_order = { "1", "default_junk" } })
    local list, said = Cat.ReadShared(text)
    T.truthy(list, said)
    T.eq(list[1].name, "Ore")
    T.eq(list[1].search, "ore")
    T.eq(list[1].items[1], 2770)
    local notes = table.concat(list.notes, "; ")
    T.truthy(notes:find("battle pets", 1, true), notes)
    T.truthy(notes:find("hidden categories", 1, true), notes)
    _G.C_EncodingUtil = nil
end)

T.test("bags: Syndicator searches turned into the bag search", function()
    local S = catLogin().Search
    stub.SlotNames()
    local function as(text) return (S.FromSyndicator(text)) end
    T.eq(as("#potion|#food"), "#potion | #food")
    T.eq(as("~#junk&#trade goods"), "!#junk & #tradegoods")
    T.eq(as("200-300"), "ilvl200-300")
    T.eq(as("<=10"), "ilvl<=10")
    T.eq(as("123"), "ilvl=123")
    T.eq(as("(#armor|#weapon)"), "#armor | #weapon", "brackets around all of it")
    T.eq(as("hearthstone"), "hearthstone", "a name stays a name")
    -- Brackets inside are multiplied out.
    local s, dropped = S.FromSyndicator("#armor&(#cloth|#leather)")
    T.eq(s, "#armor & #cloth | #armor & #leather")
    T.eq(#dropped, 0)
    T.eq(as("!gear&(#cloth|#tailoring|#first aid)"), "!gear & #cloth | !gear & #tailoring | !gear & #first aid")
    s, dropped = S.FromSyndicator("#armor&((#cloth|#leather)&#boe)")
    T.isnil(s, "brackets in brackets aren't followed")
    T.eq(#dropped, 1)
    -- The game's own names for types and slots, "&" taken out as Baganator does.
    T.eq(as("#herb|#alchemy"), "#herb | #alchemy")
    T.eq(as("#metal stone|#parts"), "#metal stone | #parts")
    T.eq(as("#tabard|#shirt"), "#tabard | #shirt")
    T.eq(as("#open"), "#open")
    T.eq(as("#crafting reagent|#reagent"), "#reagent", "the same word twice comes once")
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

T.test("bags: the game's own type and slot names are search words", function()
    local S = catLogin().Search
    stub.SlotNames()
    local function hit(text, facts) return S.Parse(text)(facts) == true end
    T.truthy(hit("#herb", { classID = 7, subClassID = 9 }))
    T.falsy(hit("#herb", { classID = 7, subClassID = 7 }))
    T.truthy(hit("#metal stone", { classID = 7, subClassID = 7 }), "Metal & Stone without its &")
    T.truthy(hit("#trinket", { classID = 4, subClassID = 0, equipLoc = "INVTYPE_TRINKET" }))
    T.truthy(hit("#shields", { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD" }))
    T.truthy(hit("#leather", { classID = 4, subClassID = 2 }), "leather armor")
    T.truthy(hit("#leather", { classID = 7, subClassID = 6 }), "and leather to craft with")
    T.truthy(hit("#cloth", { classID = 4, subClassID = 1, equipLoc = "INVTYPE_CHEST" }))
    T.falsy(hit("#cloth", { classID = 4, subClassID = 1, equipLoc = "INVTYPE_CLOAK" }), "every cloak is cloth")
    T.truthy(hit("#fishing", { classID = 9, subClassID = 9 }))
    T.truthy(hit("#open", { openable = true }))
    T.falsy(hit("#open", { openable = false }))
    T.truthy(hit("#weapon", { classID = 2 }), "Daylight UI's own keyword still answers")
    T.falsy(hit("#nothing like it", { classID = 7, subClassID = 9 }))
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

T.test("W.Prompt: a box asked from an accepted one stays open", function()
    catLogin()
    local W = DaylightUI.Widgets
    local got
    W.Prompt("First", "", function(v)
        got = v
        W.Prompt("Second", "", function() end)
    end)
    stub.Reply(" Keepers ")
    T.eq(got, "Keepers", "trimmed, inside the click")
    T.truthy(stub.AskText() == "Second" and _G.DaylightUIAsk:IsShown(), "the second box is up")
    stub.Dismiss()
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

T.test("bags: with the option on, a new item shows in Recent and in its own group", function()
    local ns = catLogin()
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and slot == 5 end }
    local item = ns.Bags.buttons[0][5]
    ns.Relayout()
    local function copies()
        local where = {}
        for _, g in ipairs(ns.Layout.Groups(ns.module.db, ns.window)) do
            for _, e in ipairs(g.entries) do
                if e.button == item or e.twinOf == item then where[#where + 1] = g.key end
            end
        end
        return table.concat(where, ",")
    end
    T.eq(copies(), "recent", "off by default: only in Recent")
    DaylightUI:Set("Bags", "recentInGroup", true)
    ns.Relayout()
    T.eq(copies(), "recent,armor", "on: in Recent and in Armor")
    local twin = ns.Bags.Twin(0, 5)
    T.truthy(twin:IsShown(), "the copy is placed")
    T.eq(twin:GetParent():GetID(), 0, "the copy is the same bag")
    T.eq(twin:GetID(), 5, "and the same slot")
    _G.C_NewItems.IsNewItem = function() return false end
    ns.Categories.ClearRecent()
    ns.Relayout()
    T.eq(copies(), "armor", "no longer new: once, in its group")
    T.falsy(twin:IsShown(), "the copy goes")
    DaylightUI:Set("Bags", "recentInGroup", false)
    _G.C_NewItems = nil
end)

T.test("bags: an item marked as junk wears the junk coin like a gray one", function()
    local ns = catLogin()
    local Cat, B = ns.Categories, ns.Bags
    local bread = B.buttons[0][8]
    T.falsy(ns.Keep.AnyMarkedJunk(ns.window), "nothing marked yet")
    Cat.ToggleJunk(8, "Bread")
    ns.Relayout()
    ns.Items.Fill(bread)
    T.eq(bread.calls.UpdateJunkItem[1], 0, "the game's coin is asked for as on a gray item")
    T.truthy(ns.Keep.AnyMarkedJunk(ns.window))
    Cat.ToggleJunk(8, "Bread")
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

T.test("bags: Recent can be turned off from its heading and back on", function()
    local ns = catLogin()
    local Cat = ns.Categories
    _G.C_NewItems = { IsNewItem = function(bag, slot) return bag == 0 and slot == 5 end }
    ns.Relayout()
    T.eq(groupOf(ns, ns.Bags.buttons[0][5]), "recent")
    local head
    for _, h in ipairs(ns.window.headings) do if h.key == "recent" and h:IsShown() then head = h end end
    local picked, keys
    local openMenu = DaylightUI.Widgets.OpenMenu
    DaylightUI.Widgets.OpenMenu = function(_, k, _, _, onPick) keys, picked = k, onPick end
    head:GetScript("OnClick")(head, "RightButton")
    DaylightUI.Widgets.OpenMenu = openMenu
    T.eq(keys and keys[2], "off")
    picked("off")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(Cat.RecentShown(), "off")
    T.eq(groupOf(ns, ns.Bags.buttons[0][5]), "armor", "a new item goes straight to its own group")
    Cat.SetRecentShown(true)
    stub.RunTimers()
    T.truthy(Cat.RecentShown())
    T.eq(groupOf(ns, ns.Bags.buttons[0][5]), "recent", "back on, new items gather again")
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
    local calls = world.openAll
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    T.truthy(f:IsShown(), "ours opens with the bank")
    T.noerror(rightClickSlot, "a right-click in your bags at the bank isn't blocked")
    T.truthy(ns.window:IsShown(), "your bags open with it, as the game's bank frame does")
    T.eq(world.openAll, calls, "without the game's OpenAllBags: called from addon code it runs tainted")
    T.eq(world.opener, nil, "the game's who-opened-them local stays untouched")
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
    stub.RunTimers()
    stub.FinishFade(ns.window)
    T.falsy(ns.window:IsShown(), "your bags close with it too")
    T.falsy(IsAnyBagOpen())
    T.eq(world.closeAll, 0, "never through the game's CloseAllBags")
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
    T.eq(BankFrame:GetParent(), DaylightUI.Win.Followers.aside, "held aside for its first show")
    T.isnil(stub.ClipAncestor(BankFrame), "never under a clipping frame")
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

T.test("bank: a character whose tab shows only once at the banker isn't held aside again next login", function()
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
    local heads = 0
    for _, h in ipairs(ns.bank.headings or {}) do if h:IsShown() then heads = heads + 1 end end
    T.truthy(heads > 0, "the bank's Shelf is packed like the bags'")
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

T.test("bank: categories view open, one stack of a combined pile taken out: the rest still shows", function()
    local function spot(btn)
        local _, _, _, x, y = btn:GetPoint(1)
        return x, y
    end
    local ns = bankLogin()
    categoryWorld()
    world.maxStack[70] = 20
    for slot, n in pairs({ [2] = 20, [3] = 20, [4] = 20, [5] = 4 }) do
        world.items[6][slot] = { iconFileID = 700, stackCount = n, quality = 1, hyperlink = "|Hitem:70|h", itemID = 70, itemName = "Clam" }
    end
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local set = ns.Bank.set
    local shown
    for slot = 2, 5 do
        local b = set.buttons[6][slot]
        if b:IsShown() then T.falsy(shown, "one tile for the pile"); shown = b end
    end
    T.truthy(shown, "the pile shows")
    T.eq(shown.calls.count, 64, "all 64 on it")
    local x, y = spot(shown)
    -- The game moves only that slot's 20 into the bags.
    local taken = shown:GetID()
    world.items[6][taken] = nil
    world.items[1][5] = { iconFileID = 700, stackCount = 20, quality = 1, hyperlink = "|Hitem:70|h", itemID = 70, itemName = "Clam" }
    world.items[6][taken] = { iconFileID = 700, stackCount = 20, quality = 1, hyperlink = "|Hitem:70|h", itemID = 70, itemName = "Clam", isLocked = true }
    stub.FireEvent("ITEM_LOCK_CHANGED", 6, taken)
    world.items[6][taken] = nil
    stub.FireEvent("BAG_UPDATE", 6)
    stub.FireEvent("BAG_UPDATE", 1)
    stub.FireEvent("ITEM_LOCK_CHANGED", 6, taken)
    stub.FireEvent("PLAYERBANKSLOTS_CHANGED", taken)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunTimers()
    local now
    for slot = 2, 5 do
        local b = set.buttons[6][slot]
        if b:IsShown() and world.items[6][slot] then now = b end
    end
    T.truthy(now, "another stack of it shows in the bank")
    T.eq(now.calls.count, 44, "with the 44 left")
    T.deq({ spot(now) }, { x, y }, "in the same spot")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bank: stacks that only combine on a later eased layout, one taken out: the next one shows", function()
    local function spot(btn)
        local _, _, _, x, y = btn:GetPoint(1)
        return x, y
    end
    local ns = bankLogin()
    categoryWorld()
    for slot, n in pairs({ [2] = 20, [3] = 20, [4] = 20, [5] = 4 }) do
        world.items[6][slot] = { iconFileID = 700, stackCount = n, quality = 1, hyperlink = "|Hitem:70|h", itemID = 70, itemName = "Clam" }
    end
    DaylightUI:Set("Bags", "view", "categories")
    stub.RunTimers()
    stub.FireEvent("BANKFRAME_OPENED")
    stub.RunTimers()
    local set = ns.Bank.set
    local function shownClams()
        local out = {}
        for slot = 2, 5 do
            local b = set.buttons[6][slot]
            if b:IsShown() and world.items[6][slot] then out[#out + 1] = b end
        end
        return out
    end
    T.eq(#shownClams(), 4, "stack size not known yet: four stacks apart")
    -- The stack size loads, and something new lands in the bank: one eased layout.
    world.maxStack[70] = 20
    world.items[6][6] = { iconFileID = 113, stackCount = 1, quality = 1, hyperlink = "|Hitem:13|h", itemID = 13 }
    stub.FireEvent("BAG_UPDATE", 6)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    local list = shownClams()
    local pile
    for _, b in ipairs(list) do if b.calls.count == 64 then pile = b end end
    T.truthy(pile, "now combined: 64 on one tile")
    local x, y = spot(pile)
    world.items[6][pile:GetID()] = nil
    world.items[1][5] = { iconFileID = 700, stackCount = 20, quality = 1, hyperlink = "|Hitem:70|h", itemID = 70, itemName = "Clam" }
    stub.FireEvent("BAG_UPDATE", 6)
    stub.FireEvent("BAG_UPDATE", 1)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 2)
    local now
    for _, b in ipairs(shownClams()) do
        local bx, by = spot(b)
        if bx == x and by == y then now = b end
    end
    T.truthy(now, "another stack takes the spot")
    T.eq(now.calls.count, 44, "with the 44 left")
    T.eq(now:GetAlpha(), 1, "and it can be seen")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
