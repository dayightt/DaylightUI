local stub = require("stub")

-- The game's NPC windows, as far as the skins touch them.
local function window(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(380, 440)
    f.NineSlice = CreateFrame("Frame", nil, f)
    f.Bg = f:CreateTexture()
    f.TitleContainer = CreateFrame("Frame", nil, f)
    f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
    f.CloseButton = CreateFrame("Button", name .. "CloseButton", f)
    local normal = f.CloseButton:CreateTexture()
    function f.CloseButton:GetNormalTexture() return normal end
    f.Inset = CreateFrame("Frame", name .. "Inset", f)
    f.Inset.Bg = f.Inset:CreateTexture()
    return f
end

local function button(name, parent)
    local b = CreateFrame("Button", name, parent)
    b.Left, b.Middle, b.Right = b:CreateTexture(), b:CreateTexture(), b:CreateTexture()
    local label = b:CreateFontString()
    function b:GetFontString() return label end
    return b
end

-- A scrolling list with rows, as the game's ScrollBox.lua makes them. Callbacks
-- get their owner first. Update fills the rows, then fires OnUpdate.
_G.ScrollBoxListMixin = { Event = { OnUpdate = "OnUpdate", OnInitializedFrame = "OnInitializedFrame" } }
local function list(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.rows = {}
    box.callbacks = {}
    function box:ForEachFrame(fn) for _, r in ipairs(self.rows) do fn(r) end end
    function box:RegisterCallback(event, fn, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        self.callbacks[event][owner] = fn
    end
    function box:TriggerEvent(event, ...)
        for owner, fn in pairs(self.callbacks[event] or {}) do fn(owner, ...) end
    end
    -- fill(row) is the game's row initializer, run before the callback fires.
    function box:Update(fill)
        for _, r in ipairs(self.rows) do
            if fill then fill(r) end
            self:TriggerEvent("OnInitializedFrame", r, {})
        end
        self:TriggerEvent("OnUpdate")
    end
    return box
end

-- A list's rows, each given its element data as the game's scroll list does.
local function rows(...)
    local list = { ... }
    for _, r in ipairs(list) do function r:GetElementData() return {} end end
    return list
end

local function world()
    -- The game's item button border functions (ItemButtonTemplate.lua,
    -- SetItemButtonBorder_Base / SetItemButtonBorderVertexColor_Base).
    _G.SetItemButtonBorder = function(button, asset)
        button.IconBorder:SetShown(asset ~= nil)
        if asset then button.IconBorder:SetTexture(asset) end
    end
    _G.SetItemButtonBorderVertexColor = function(button, r, g, b)
        if button.IconBorder then button.IconBorder:SetVertexColor(r, g, b) end
    end
    local q = window("QuestFrame")
    CreateFrame("Frame", "QuestFrameDetailPanel", q).parchment = nil
    _G.QuestFrameDetailPanel:CreateTexture()
    button("QuestFrameAcceptButton", q)
    button("QuestFrameDeclineButton", q)
    for _, n in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoObjectivesText" }) do
        _G[n] = q:CreateFontString(n)
    end
    _G.QuestInfo_Display = function() end
    local gsp = window("GossipFrame")
    gsp.GreetingPanel = CreateFrame("Frame", nil, gsp)
    gsp.GreetingPanel.GoodbyeButton = button(nil, gsp.GreetingPanel)
    gsp.GreetingPanel.ScrollBox = list(gsp.GreetingPanel)
    local m = window("MerchantFrame")
    button("MerchantFrameTab1", m)
    for _, n in ipairs({ "MerchantPrevPageButton", "MerchantNextPageButton" }) do
        local pb = CreateFrame("Button", n, m)
        local normal = pb:CreateTexture()
        function pb:GetNormalTexture() return normal end
        pb.label = pb:CreateFontString()
        pb.label:SetTextColor(1, 0.82, 0)
    end
    local slot = CreateFrame("Frame", "MerchantItem1", m)
    local ib = CreateFrame("Button", "MerchantItem1ItemButton", slot)
    ib.icon = ib:CreateTexture()
    ib.IconBorder = ib:CreateTexture()
    slot:CreateTexture("MerchantItem1SlotTexture")
    _G.MerchantItem1SlotTexture = slot:CreateTexture()

    local trade = window("TradeFrame")
    trade.TradeButton = button("TradeFrameTradeButton", trade)
    trade.CancelButton = button("TradeFrameCancelButton", trade)
    _G.TradeFramePlayerNameText = trade:CreateFontString("TradeFramePlayerNameText")
    _G.TradeFrameRecipientNameText = trade:CreateFontString("TradeFrameRecipientNameText")
    trade.RecipientOverlay = CreateFrame("Frame", nil, trade)
    trade.RecipientOverlay.portrait = trade.RecipientOverlay:CreateTexture()
    trade.RecipientOverlay.portraitFrame = trade.RecipientOverlay:CreateTexture()
    local ti = CreateFrame("Button", "TradePlayerItem1", trade)
    ti.icon = ti:CreateTexture()
    ti.IconBorder = ti:CreateTexture()
    local mf = CreateFrame("Frame", "TradePlayerInputMoneyFrame", trade)
    mf.Bg = mf:CreateTexture()
end

-- With the NPC window off, a player gets these skins on the game's own gossip
-- and quest windows. With it on, they are moved aside (see test_npc).
local function login(before)
    stub.Load({ skins = true, before = function()
        world()
        _G.DaylightUIDB = { modules = { NPC = { enabled = false }, Professions = { enabled = false }, Social = { enabled = false } } }   -- the game's windows, not the addon's
        if before then before() end
    end })
    stub.RunTimers()
    return stub.skins
end

T.test("skins: a window gets our border and panel, the game's art goes, our close X", function()
    login()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local f = QuestFrame
    T.eq(f.NineSlice:GetAlpha(), 0, "the game's frame art gone")
    T.eq(f.Bg:GetAlpha(), 0)
    T.truthy(stub.skins.Kit.ShellOf(f), "our border and panel")
    T.eq(f.TitleContainer.TitleText.__font[1], DaylightUI.Style.FONT, "our font on the title")
    local title = f.TitleContainer.TitleText
    local point, rel, relPoint, x = title:GetPoint(1)
    T.eq(point, "TOPLEFT", "the title on the left, as our windows' header")
    T.eq(rel, f); T.eq(relPoint, "TOPLEFT"); T.eq(x, stub.skins.Kit.TITLE_X)
    T.eq(title:GetJustifyH(), "LEFT")
    T.eq(f.CloseButton:GetNormalTexture():GetAlpha(), 0, "the game's close art gone")
    local ours = false
    for _, r in ipairs({ f.CloseButton:GetRegions() }) do
        if r.__texture == DaylightUI.MEDIA .. "ui-close.png" then ours = true end
    end
    T.truthy(ours, "our X")
    T.eq(f.Inset.Bg:GetAlpha(), 0, "the inset's art gone too")
end)

T.test("skins: buttons wear our one button look (W.Button's): the warm band and fill, the mouse traces it in the accent", function()
    login()
    local b = QuestFrameAcceptButton
    T.eq(b.Left:GetAlpha(), 0); T.eq(b.Middle:GetAlpha(), 0); T.eq(b.Right:GetAlpha(), 0)
    local Kit, W = stub.skins.Kit, DaylightUI.Widgets
    local s = Kit.ButtonOf(b)
    T.truthy(s, "our button look")
    T.isnil(rawget(b, "band"), "nothing of ours written on the game's button")
    T.rgb(s.band.__vertex, W.BUTTON.band, "the warm band at rest")
    T.eq(s.text, b:GetFontString(), "the game's own words, kept")
    T.eq(b:GetFontString().__font[1], DaylightUI.Style.FONT, "in our font")
    local tr = Kit.TraceOf(b)
    T.truthy(tr, "a hover trace")
    b:SetSize(100, 22)
    b:GetScript("OnEnter")(b)
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02) end
    T.eq(tr.p, 1, "the mouse traces it all round")
    T.truthy(tr.right:IsShown(), "down the right too")
    b:GetScript("OnMouseDown")(b)
    T.falsy(s.lit:IsShown(), "a press: the lit top line goes, the fill turns over")
    b:GetScript("OnMouseUp")(b)
    T.truthy(s.lit:IsShown())
    b:GetScript("OnLeave")(b)
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02) end
    T.eq(tr.p, 0, "and draws back")
    b:Disable()
    T.truthy(s.off, "disabled: dimmed")
    T.rgb(s.band.__vertex, W.BUTTON.bandOff)
    b:Enable()
    T.falsy(s.off)
end)

-- The game menu's buttons come from a pool. Each time the menu opens, AddButton
-- (MainMenuFrameTemplates.lua) clears their OnEnter/OnLeave before showing them.
-- That removed the skin's hooks, so from the second opening on hover lit nothing.
T.test("skins: a button whose OnEnter/OnLeave the game clears still lights when shown again", function()
    login()
    local b = QuestFrameAcceptButton
    local Kit = stub.skins.Kit
    b:SetSize(100, 22)
    b:Hide()
    b:SetScript("OnEnter", nil)
    b:SetScript("OnLeave", nil)
    b:Show()
    local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
    T.truthy(enter and leave, "our hover hooks are back")
    enter(b)
    local tr = Kit.TraceOf(b)
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02) end
    T.eq(tr.p, 1, "the mouse traces it")
    leave(b)
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02) end
    T.eq(tr.p, 0, "and it draws back")
    -- A disabled one gets the game's tooltip scripts instead, and the skin's join them.
    b:Hide()
    local tipped = false
    b:SetScript("OnEnter", function() tipped = true end)
    b:Show()
    b:GetScript("OnEnter")(b)
    T.truthy(tipped, "the game's own OnEnter still runs")
    -- Shown again with the hooks still there, it isn't hooked twice.
    local before = b:GetScript("OnEnter")
    b:Hide(); b:Show()
    T.eq(b:GetScript("OnEnter"), before, "hooked once")
end)

T.test("skins: text the game colors again, or prints dark into the string, is light again as the game fills it", function()
    login()
    local body = QuestInfoDescriptionText
    QuestInfo_Display()
    -- The game's next fill colors and fills the text, then the skin follows.
    body:SetTextColor(0.2, 0.1, 0)
    body:SetText("|cff000000Elmore's Task|r and |cffff2020red|r")
    QuestInfo_Display()
    T.truthy(body.__textColor[1] > 0.8, "put back")
    T.truthy(not body:GetText():find("|cff000000", 1, true), "the dark run rewritten")
    T.truthy(body:GetText():find("|cffff2020", 1, true), "other colors left")
    for _, m in ipairs({ "SetTextColor", "SetText", "SetFormattedText" }) do
        T.isnil(rawget(body, m), "no hook on the game's text: " .. m)
    end
end)

T.test("skins: a book's pages stay light after a page turn", function()
    login(function()
        local f = CreateFrame("Frame", "ItemTextFrame", UIParent)
        f:Hide()
        CreateFrame("SimpleHTML", "ItemTextPageText", f)
    end)
    local page = _G.ItemTextPageText
    -- ITEM_TEXT_BEGIN: the game sets the parchment's dark brown per tag.
    for _, tag in ipairs({ "P", "H1", "H2", "H3" }) do page:SetTextColor(tag, 0.18, 0.12, 0.06) end
    ItemTextFrame:Show()
    stub.RunTimers()
    local ink = DaylightUI.Style.INK
    T.eq(page.__tagColor.P[1], ink.TEXT[1], "body text light")
    T.eq(page.__tagColor.H1[1], ink.TITLE[1], "headings light")
    -- A page turn only refills the text; the tag colors carry over.
    page:SetText("Page two")
    T.eq(page.__tagColor.P[1], ink.TEXT[1], "still light on the next page")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: gossip text a few frames deep in a row is made light, also the frame after", function()
    login()
    local box = GossipFrame.GreetingPanel.ScrollBox
    local row = CreateFrame("Frame", nil, box)
    local inner = CreateFrame("Frame", nil, CreateFrame("Frame", nil, row))
    local text = inner:CreateFontString()
    box.rows[1] = row
    box:Update()
    text:SetTextColor(0.15, 0.09, 0.04)          -- the game fills it after its update
    local late = CreateFrame("Frame", nil, box)
    local lateText = late:CreateFontString()
    lateText:SetTextColor(0, 0, 0)
    box.rows[2] = late
    stub.RunTimers()
    T.truthy(text.__textColor[1] > 0.8, "kept light")
    T.truthy(lateText.__textColor[1] > 0.8, "the next frame's pass")
end)

T.test("skins: quest text the game prints dark is made light, again each time it fills it", function()
    login()
    local body = QuestInfoDescriptionText
    body:SetTextColor(0.2, 0.1, 0)     -- the game's parchment ink
    QuestInfo_Display()
    T.truthy(body.__textColor[1] > 0.8, "light text")
    T.eq(QuestInfoTitleHeader.__textColor[1], stub.skins.Kit.HEADER[1], "titles in the accent")
end)

T.test("skins: gossip rows are made light as the list shows them", function()
    login()
    local panel = GossipFrame.GreetingPanel
    local row = CreateFrame("Button", nil, panel.ScrollBox)
    local text = row:CreateFontString()
    text:SetTextColor(0, 0, 0)
    panel.ScrollBox.rows[1] = row
    panel.ScrollBox:Update()
    stub.RunTimers()   -- rows are gone over the frame after the list updates
    T.truthy(text.__textColor[1] > 0.8, "a row the list just made")
end)

T.test("skins: merchant slots and tabs", function()
    login()
    T.eq(MerchantItem1SlotTexture:GetAlpha(), 0, "the slot art gone")
    T.eq(MerchantItem1ItemButton.icon.__texCoord[1], 0.08, "the icon cropped")
    local ib = MerchantItem1ItemButton
    ib.IconBorder:SetVertexColor(1, 1, 1); ib.IconBorder:Show()          -- a white item
    T.eq(stub.skins.Kit.ShellOf(ib).opts.borderColor[1], 1, "outlined like the slots, white too")
    T.eq(ib.IconBorder:GetAlpha(), 0, "the game's own border gone")
    T.truthy(stub.skins.Kit.TabOf(MerchantFrameTab1), "our tab look")
    local prev = MerchantPrevPageButton
    T.eq(prev:GetNormalTexture():GetAlpha(), 0, "the page button's art gone")
    T.truthy(stub.skins.Kit.ShellOf(prev), "outlined like the rest")
    T.truthy(prev.label.__textColor[1] > 0.8, "its label light")
end)

T.test("skins: trade slots, money frames and the Trade/Cancel buttons", function()
    login()
    T.eq(TradePlayerItem1.IconBorder:GetAlpha(), 0, "the slot's own border gone, our outline instead")
    T.truthy(stub.skins.Kit.ShellOf(TradePlayerItem1), "the item look")
    T.eq(TradePlayerInputMoneyFrame.Bg:GetAlpha(), 0, "the money box's own art gone")
    T.truthy(stub.skins.Kit.ButtonOf(TradeFrameTradeButton), "the Trade button, flat")
    T.truthy(stub.skins.Kit.ButtonOf(TradeFrameCancelButton), "the Cancel button, flat")
    -- the other player's portrait and its gold ring are erased (their own
    -- frame, over the names), and their name gets its whole side
    T.eq(TradeFrame.RecipientOverlay.portrait:GetAlpha(), 0, "their portrait gone")
    T.eq(TradeFrame.RecipientOverlay.portraitFrame:GetAlpha(), 0, "its gold ring gone")
    local _, _, _, left = TradeFrameRecipientNameText:GetPoint(1)
    T.eq(left, -166, "their name starts at their side, not after the portrait")
end)

T.test("skins: a window from a game addon that loads later is skinned when it loads", function()
    login()
    T.isnil(stub.skins.Kit.ShellOf(_G.ClassTrainerFrame or {}), "not there yet")
    local f = window("ClassTrainerFrame")
    button("ClassTrainerTrainButton", f)
    f.FilterDropdown = CreateFrame("Button", nil, f)
    f.FilterDropdown.Background = f.FilterDropdown:CreateTexture()
    f.FilterDropdown.Text = f.FilterDropdown:CreateFontString()
    f.ScrollBox = list(f)
    local r = CreateFrame("Button", nil, f.ScrollBox)
    r.icon, r.disabledBG, r.selectedTex = r:CreateTexture(), r:CreateTexture(), r:CreateTexture()
    r.name = r:CreateFontString()
    r.name:SetTextColor(1, 0.1, 0.1)             -- can't learn it yet
    r.selectedTex:Hide()
    f.ScrollBox.rows[1] = r
    -- The game's (Blizzard_TrainerUI.lua): the only code showing or hiding a row's selection art.
    _G.ClassTrainerFrame_InitServiceButton = function(b) end
    stub.FireEvent("ADDON_LOADED", "Blizzard_TrainerUI")
    stub.loadedAddOns.Blizzard_TrainerUI = true
    stub.FireEvent("ADDON_LOADED", "Blizzard_TrainerUI")
    T.truthy(stub.skins.Kit.ShellOf(f), "skinned once its addon is in")
    T.truthy(stub.skins.Kit.ButtonOf(ClassTrainerTrainButton))
    T.eq(f.FilterDropdown.Background:GetAlpha(), 0, "the dropdown's art gone")
    T.truthy(stub.skins.Kit.ShellOf(f.FilterDropdown), "a button like the rest")
    T.eq(r.disabledBG:GetAlpha(), 0, "the row's box art gone")
    T.eq(r.icon:GetAlpha(), 1, "its icon kept")
    T.eq(r.name.__textColor[1], 1, "the game's colors kept")
    local s = stub.skins.Kit.ShellOf(r)
    T.eq(s.opts.borderColor, stub.skins.Kit.ROW_BORDER, "not selected: the row's gray outline")
    r.selectedTex:Show()
    ClassTrainerFrame_InitServiceButton(r)
    T.eq(s.opts.borderColor, stub.skins.Kit.SELECTED, "the soft light gray round the selected row")
    for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
        T.isnil(rawget(r.selectedTex, m), "no hook on the selection art's " .. m)
    end
    _G.ClassTrainerFrame_InitServiceButton = nil
end)

T.test("skins: a pack switched off leaves its windows as the game draws them", function()
    login(function()
        _G.DaylightUIDB = { modules = { Skins = { packs = { npc = false } }, NPC = { enabled = false } } }
    end)
    T.isnil(stub.skins.Kit.ShellOf(QuestFrame))
    T.eq(QuestFrame.NineSlice:GetAlpha(), 1)
    DaylightUI:Set("Skins", "packs.npc", true)
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ShellOf(QuestFrame), "on again: skinned now")
end)

-- A "Talking to NPCs" switch read as the switch for the NPC window, which it
-- never was. Packs are named only after what they really skin.
T.test("skins: the Packs card has no switch named after a window Daylight UI rebuilt", function()
    login()
    local page = DaylightUI.Options.GetPage("Skins.skins")
    local keys, labels = {}, {}
    for _, item in ipairs(page.groups[1].items) do
        keys[#keys + 1] = item.key
        labels[#labels + 1] = item.label
    end
    T.eq(table.concat(keys, ","), "packs.npc,packs.social,packs.collections,packs.system")
    local all = table.concat(labels, "|")
    for _, word in ipairs({ "NPC", "Character", "Friends", "mail" }) do
        T.isnil(all:find(word, 1, true), word .. " isn't a pack's name")
    end
end)

T.test("skins: the game's character window follows Menus, loot and items; an old Character switch does nothing", function()
    local f
    login(function()
        _G.DaylightUIDB = { modules = { Skins = { packs = { character = false } }, Character = { enabled = false } } }
        f = window("CharacterFrame")
    end)
    T.truthy(stub.skins.Kit.ShellOf(f), "the old switch left off doesn't strand it")
    login(function()
        _G.DaylightUIDB = { modules = { Skins = { packs = { system = false } }, Character = { enabled = false } } }
        f = window("CharacterFrame")
    end)
    T.isnil(stub.skins.Kit.ShellOf(f))
end)

-- The character window, as far as the skin touches it.
local function character()
    local f = window("CharacterFrame")
    f.LeftPaneHost = CreateFrame("Frame", nil, f)
    f.LeftPaneHost:CreateTexture()
    f.RightPaneHost = CreateFrame("Frame", nil, f)
    f.RightPaneHost.StoneBg = f.RightPaneHost:CreateTexture()
    local collapsed = false
    function f:IsRightPaneCollapsed() return collapsed end
    -- As the game's (CharacterFrame.lua): RefreshRightPane shows or hides the pane.
    function f:SetRightPaneCollapsed(v)
        collapsed = v
        self.RightPaneHost:SetShown(not v)
    end
    f.RightPaneToggleButton = CreateFrame("Button", nil, f)
    _G.ToggleCharacter = function() end
    CreateFrame("Frame", "PaperDollFrame", f)
    _G.CharacterLevelText = f:CreateFontString()
    local slot = CreateFrame("Button", "CharacterHeadSlot", f)
    slot:SetID(1)
    slot.BorderFrame = CreateFrame("Frame", nil, slot)
    slot.BorderFrame.art = slot.BorderFrame:CreateTexture()
    slot.IconBorder = slot:CreateTexture()
    slot.icon = slot:CreateTexture()
    _G.CharacterHeadSlotNormalTexture = slot:CreateTexture()
    _G.PaperDollItemSlotButton_Update = function() end
    local pane = CreateFrame("Frame", "CharacterStatsPaneScrollBox", f.RightPaneHost)
    pane.ScrollBox = list(pane)
    local header = CreateFrame("Frame", nil, pane.ScrollBox)
    header.Background = header:CreateTexture()
    header.Title = header:CreateFontString()
    local stat = CreateFrame("Frame", nil, pane.ScrollBox)
    stat.Background = stat:CreateTexture()
    stat.Label, stat.Value = stat:CreateFontString(), stat:CreateFontString()
    stat.Value:SetTextColor(0.1, 1, 0.1)         -- buffed: the game's green
    pane.ScrollBox.rows = rows(header, stat)
    -- A tab down the window's side: a frame, its selection a texture.
    f.ModeTabs = CreateFrame("Frame", "CharacterFrameModeTabs", f)
    local mode = CreateFrame("Frame", "CharacterFrameModeTab1", f.ModeTabs)
    mode.Background = mode:CreateTexture()
    mode.Icon = mode:CreateTexture()
    mode.SelectedTexture = mode:CreateTexture()
    function mode:SetChecked(on) self.SelectedTexture:SetShown(on) end
    f.ModeTabs.Tabs = { mode }
    -- A button over the stats: a check button.
    local tab = CreateFrame("CheckButton", "PaperDollSidebarTab1", f)
    tab.art = tab:CreateTexture()
    tab.Icon = tab:CreateTexture()
    local checked = true
    function tab:GetChecked() return checked end
    function tab:SetChecked(v) checked = v end
    _G.PaperDollFrame_UpdateSidebarTabs = function() end
    -- The model's buttons.
    local scene = CreateFrame("Frame", "CharacterModelScene", f)
    scene.ControlFrame = CreateFrame("Frame", nil, scene)
    local zoom = CreateFrame("Button", nil, scene.ControlFrame)
    zoom.Icon = zoom:CreateTexture()
    local zn = zoom:CreateTexture()
    function zoom:GetNormalTexture() return zn end
    scene.ControlFrame.zoomInButton = zoom
    return f
end

T.test("skins: the character window: slots outlined in their item's quality color, stats, side tabs", function()
    local f
    login(function()
        f = character()
        CharacterHeadSlot.IconBorder:SetVertexColor(0.64, 0.21, 0.93)     -- the game: an epic
        CharacterHeadSlot.IconBorder:Show()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(stub.skins.Kit.ShellOf(f), "our window")
    local slot = CharacterHeadSlot
    T.eq(slot.BorderFrame.art:GetAlpha(), 0, "the slot's frame art gone")
    T.eq(slot.IconBorder:GetAlpha(), 0, "the game's quality ring gone")
    T.eq(slot.icon.__texCoord[1], 0.08, "the icon cropped")
    local Kit = stub.skins.Kit
    local s = Kit.ShellOf(slot)
    T.eq(s.opts.borderColor[1], 0.64, "our outline in the item's quality color")
    SetItemButtonBorderVertexColor(slot, 1, 1, 1)                         -- a white item
    T.eq(s.opts.borderColor[1], 1, "a white item: a white outline")
    SetItemButtonBorder(slot)                                             -- nothing in it
    T.eq(s.opts.borderColor[1], stub.skins.Kit.EMPTY_ITEM_BORDER[1], "empty: dim, still there")
    for _, m in ipairs({ "Show", "Hide", "SetShown", "SetVertexColor", "SetTexture", "SetAtlas" }) do
        T.isnil(rawget(slot.IconBorder, m), "no hook on the border's " .. m .. " (it sits on secure item buttons)")
    end
    local rows = CharacterStatsPaneScrollBox.ScrollBox.rows
    T.eq(rows[1].Background:GetAlpha(), 0, "the header's art gone")
    T.eq(rows[1].Title.__font[1], DaylightUI.Style.FONT)
    T.eq(rows[2].Value.__textColor[2], 1, "the game's value color kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(rows[2].Label.__textColor[1] < 0.8, "the label dim")
    local selected = Kit.SELECTED[1]
    local tab = PaperDollSidebarTab1
    T.eq(tab.art:GetAlpha(), 0, "the button's art gone")
    T.eq(tab.Icon:GetAlpha(), 1, "its icon kept")
    local ts = Kit.ShellOf(tab)
    T.eq(ts.opts.borderColor[1], selected, "the soft light gray round the selected one")
    tab:SetChecked(false)
    PaperDollFrame_UpdateSidebarTabs()
    T.eq(ts.opts.borderColor, Kit.TAB_BORDER, "repainted as the game updates them: the dim outline")
    local mode = CharacterFrameModeTab1
    T.eq(mode.Background:GetAlpha(), 0, "the side tab's art gone")
    local ms = Kit.ShellOf(mode)
    mode:SetChecked(true)
    ToggleCharacter("PaperDollFrame")                       -- the game checks the tabs in it
    T.eq(ms.opts.borderColor[1], selected, "the selected side tab")
    mode:SetChecked(false)
    mode:GetScript("OnMouseUp")(mode, "LeftButton", true)   -- another tab clicked
    T.eq(ms.opts.borderColor, Kit.TAB_BORDER)
    for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
        T.isnil(rawget(mode.SelectedTexture, m), "no hook on the selection art's " .. m)
    end
    T.eq(mode.Icon.__texCoord[1], stub.skins.Engine.PORTRAIT_CROP, "the portrait cropped square")
    T.eq(ms.opts.flat, true, "a control's flat outline, as our buttons")
    mode.Icon:SetTexCoord(0.03, 0.97, 0.03, 0.97)            -- the game, on selecting it
    T.eq(mode.Icon.__texCoord[1], stub.skins.Engine.PORTRAIT_CROP, "and kept so")
    local zoom = CharacterModelScene.ControlFrame.zoomInButton
    T.eq(zoom:GetNormalTexture():GetAlpha(), 0, "the model button's art gone")
    T.eq(Kit.ShellOf(zoom).opts.borderColor, Kit.CONTROL_BORDER, "outlined like a button")
    -- The stats pane's arrow follows the pane (shown or hidden by the game), no hook on the window.
    local arrow
    for _, r in ipairs({ f.RightPaneToggleButton:GetRegions() }) do
        if r.__texture == DaylightUI.MEDIA .. "ui-chevron.png" then arrow = r end
    end
    T.eq(arrow.__rotation, Kit.ROTATION.left, "open: pointing to fold it away")
    f:SetRightPaneCollapsed(true)
    T.eq(arrow.__rotation, Kit.ROTATION.right, "folded: pointing to open it")
    f:SetRightPaneCollapsed(false)
    T.eq(arrow.__rotation, Kit.ROTATION.left)
    _G.ToggleCharacter = nil
end)

T.test("skins: reputation: headers on our plates, bars in our look with the game's colors", function()
    login(function()
        character()
        local rep = CreateFrame("Frame", "ReputationFrame", CharacterFrame)
        rep.ScrollBox = list(rep)
        local header = CreateFrame("Button", nil, rep.ScrollBox)
        header.art = header:CreateTexture()
        header.StateIcon = header:CreateTexture()
        header.Name = header:CreateFontString()
        local entry = CreateFrame("Button", nil, rep.ScrollBox)
        entry.Content = CreateFrame("Frame", nil, entry)
        local hl = CreateFrame("Frame", nil, entry.Content)
        hl.TextureRegions = { hl:CreateTexture(), hl:CreateTexture() }
        entry.Content.BackgroundHighlight = hl
        local bar = CreateFrame("Frame", nil, entry.Content)
        bar.bg = bar:CreateTexture()
        bar.Fill = bar:CreateTexture()
        bar.Fill:SetVertexColor(0, 0.6, 0.1)     -- friendly
        bar.Text = bar:CreateFontString()
        entry.Content.ReputationBar = bar
        entry.Content.Name = entry.Content:CreateFontString()
        rep.ScrollBox.rows = rows(header, entry)
        rep.ReputationDetailFrame = CreateFrame("Frame", nil, rep)
        local cb = CreateFrame("CheckButton", nil, rep.ReputationDetailFrame)
        cb.Label = cb:CreateFontString()
        rep.ReputationDetailFrame.AtWarCheckbox = cb
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    local header, entry = unpack(ReputationFrame.ScrollBox.rows)
    T.eq(header.art:GetAlpha(), 0, "the header's art gone")
    T.eq(header.StateIcon:GetAlpha(), 1, "its +/- kept")
    T.truthy(Kit.ShellOf(header), "on our plate")
    local bar = entry.Content.ReputationBar
    T.eq(bar.bg:GetAlpha(), 0, "the bar's art gone")
    T.eq(bar.Fill.__texture, DaylightUI.Style.BAR.fill, "our fill")
    T.eq(bar.Fill.__vertex[2], 0.6, "the standing's color kept")
    T.eq(entry.Content.BackgroundHighlight.TextureRegions[1].__color[1], 1, "a flat highlight")
    T.truthy(Kit.SwitchOf(ReputationFrame.ReputationDetailFrame.AtWarCheckbox), "a checkbox as our switch")
end)

T.test("skins: /dui skins dump lists what a window is made of", function()
    login(function() character() end)
    DaylightUI.RunCommand("skins dump CharacterFrame.RightPaneHost 2")
    T.truthy(stub.ChatContains("CharacterStatsPaneScrollBox"), "a named child")
    T.truthy(stub.ChatContains(".StoneBg Texture"), "a keyed region")
    DaylightUI.RunCommand("skins dump NoSuchFrame")
    T.truthy(stub.ChatContains("no frame NoSuchFrame"))
end)

-- ---------------------------------------------------------------------
-- The template
-- ---------------------------------------------------------------------

-- A window like most of the game's, with every standard part once.
local function standardWindow(name)
    local f = window(name)
    local ok = button(name .. "OkayButton", f)                           -- three pieces
    local tab = CreateFrame("Button", name .. "Tab1", f)
    tab.Left, tab.Middle, tab.Right = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
    tab.LeftActive, tab.MiddleActive = tab:CreateTexture(), tab:CreateTexture()
    local dd = CreateFrame("DropdownButton", nil, f)
    dd.Background, dd.Arrow = dd:CreateTexture(), dd:CreateTexture()
    dd.Text = dd:CreateFontString()
    f.FilterDropdown = dd
    local search = CreateFrame("EditBox", nil, f)
    search.Left, search.Middle, search.Right = search:CreateTexture(), search:CreateTexture(), search:CreateTexture()
    search.searchIcon = search:CreateTexture()
    f.SearchBox = search
    local check = CreateFrame("CheckButton", nil, f)
    check.Text = check:CreateFontString()
    local item = CreateFrame("Button", nil, f)
    item.icon, item.IconBorder = item:CreateTexture(), item:CreateTexture()
    local bar = CreateFrame("EventFrame", nil, f)
    bar.Track = CreateFrame("Frame", nil, bar)
    bar.Track.Thumb = CreateFrame("Button", nil, bar.Track)
    bar.Back, bar.Forward = CreateFrame("Button", nil, bar), CreateFrame("Button", nil, bar)
    local progress = CreateFrame("Frame", nil, f)
    progress.bg = progress:CreateTexture()
    progress.Fill, progress.Mask = progress:CreateTexture(), progress:CreateTexture()
    local deep = CreateFrame("Frame", nil, CreateFrame("Frame", nil, CreateFrame("Frame", nil, f)))
    local deepButton = button(nil, deep)
    local box = list(f)
    box.ScrollTarget = CreateFrame("Frame", nil, box)
    local parts = { ok = ok, tab = tab, dd = dd, search = search, check = check, item = item, bar = bar,
                    progress = progress, deepButton = deepButton, box = box }
    return f, parts
end

T.test("skins: a window's pages are watched for being shown, a list's rows aren't", function()
    local f, box, page
    login(function()
        f = CreateFrame("Frame", "TestPagesFrame", UIParent)
        page = CreateFrame("Frame", nil, f)
        button(nil, page)
        box = list(f)
        box.ScrollTarget = CreateFrame("Frame", nil, box)
    end)
    local row = CreateFrame("Frame", nil, box.ScrollTarget)
    button(nil, row)
    box.rows[1] = row
    local shown = 0
    stub.skins.Kit.Auto(f, { onPage = function() shown = shown + 1 end })
    box:Update()
    stub.RunTimers()
    row:Hide(); row:Show()
    T.eq(shown, 0, "a row shown on a scroll step is no page")
    page:Hide(); page:Show()
    T.eq(shown, 1, "a page turned is")
end)

T.test("skins: the template skins every standard part of a window, however deep", function()
    local f, p
    login(function() f, p = standardWindow("TestWindowFrame") end)
    local Kit = stub.skins.Kit
    Kit.Window(f)
    Kit.Auto(f)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local S = stub.skins.Kit.ShellOf
    T.truthy(stub.skins.Kit.ButtonOf(p.ok), "a three-piece button"); T.eq(p.ok.Left:GetAlpha(), 0)
    T.truthy(Kit.TabOf(p.tab), "a tab"); T.eq(p.tab.LeftActive:GetAlpha(), 0)
    T.truthy(S(p.dd), "a dropdown"); T.eq(p.dd.Background:GetAlpha(), 0)
    T.truthy(Kit.InputOf(p.search), "a search box"); T.eq(p.search.Middle:GetAlpha(), 0)
    T.truthy(Kit.SwitchOf(p.check), "a checkbox")
    T.truthy(Kit.ShellOf(p.item), "an item, outlined"); T.eq(p.item.IconBorder:GetAlpha(), 0)
    T.eq(p.bar.Back:GetAlpha(), 1, "a scroll bar's arrows stay clickable")
    T.eq(p.progress.bg:GetAlpha(), 0, "a progress bar"); T.eq(p.progress.Fill.__texture, DaylightUI.Style.BAR.fill)
    T.truthy(Kit.ButtonOf(p.deepButton), "three frames down, still")
    -- A list's rows, as the list makes them later.
    local row = button(nil, p.box.ScrollTarget)
    p.box.rows[1] = row
    p.box:Update()
    stub.RunTimers()   -- rows are gone over the frame after the list updates
    T.truthy(S(row), "a row the list made later")
end)

T.test("skins: a dropdown's label is colored once, never hooked (the game's menu code sets it)", function()
    local f, p
    login(function() f, p = standardWindow("TestDropdownWindow") end)
    local Kit = stub.skins.Kit
    Kit.LightAll(f, nil, 5)          -- lit before the dropdown is skinned, too
    Kit.Window(f)
    Kit.Auto(f)
    local label = p.dd.Text
    -- The game sets it from protected menu code (securecallfunction). With a hook
    -- on it that call fails with "attempt to call a nil value".
    T.isnil(rawget(label, "SetText"), "no hook on its SetText")
    T.isnil(rawget(label, "SetTextColor"), "or its SetTextColor")
    T.eq(label.__textColor and label.__textColor[1], Kit.TEXT[1], "in our text color")
end)

T.test("skins: one change to a look reaches every window that uses it", function()
    local a, b
    login(function() a = standardWindow("TestWindowA"); b = standardWindow("TestWindowB") end)
    local Kit = stub.skins.Kit
    for _, f in ipairs({ a, b }) do Kit.Window(f); Kit.Auto(f) end
    local S = stub.skins.Kit.ShellOf
    Kit.SetLook("window", "bgAlpha", 0.42)
    T.eq(S(a).opts.bgAlpha, 0.42, "one window")
    T.eq(S(b).opts.bgAlpha, 0.42, "and the other")
    local search = S(a.FilterDropdown)
    local outline = search.opts.borderColor
    Kit.SetLook("input", "borderPx", 3)
    T.eq(search.opts.borderPx, 3, "a control")
    T.eq(S(b.FilterDropdown).opts.borderPx, 3)
    T.eq(search.opts.borderColor, outline, "its outline color kept")
    Kit.LOOK.window.bgAlpha = nil
    Kit.SetLook("input", "borderPx", 2)
end)

T.test("skins: a window's template in one call, from a game addon that loads later", function()
    login()
    local Engine = stub.skins.Engine
    local f, p
    Engine.Window({ key = "test:later", pack = "npc", addon = "Blizzard_TestUI", frame = "TestLateFrame",
        hide = { ".Bg" } })
    f, p = standardWindow("TestLateFrame")
    stub.loadedAddOns.Blizzard_TestUI = true
    stub.FireEvent("ADDON_LOADED", "Blizzard_TestUI")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(stub.skins.Kit.ShellOf(f), "our window")
    T.truthy(stub.skins.Kit.ButtonOf(p.ok), "its parts")
end)

T.test("skins: currency's list and transfer button are left as the game draws them", function()
    login(function()
        character()
        local tok = CreateFrame("Frame", "TokenFrame", CharacterFrame)
        tok.ScrollBox = list(tok)
        local row = CreateFrame("Button", nil, tok.ScrollBox)
        row.art = row:CreateTexture()
        tok.ScrollBox.rows = rows(row)
        tok.DetailFrame = CreateFrame("Frame", nil, tok)
        local transfer = button(nil, tok.DetailFrame)
        tok.DetailFrame.CurrencyTransferToggleButton = transfer
        local cb = CreateFrame("CheckButton", nil, tok.DetailFrame)
        cb.Label = cb:CreateFontString()
        tok.DetailFrame.InactiveCheckbox = cb
        stub.loadedAddOns.Blizzard_TokenUI = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local d = TokenFrame.DetailFrame
    T.truthy(stub.skins.Kit.SwitchOf(d.InactiveCheckbox), "its pane's checkbox")
    T.isnil(stub.skins.Kit.ShellOf(d.CurrencyTransferToggleButton), "the transfer button untouched")
    T.eq(TokenFrame.ScrollBox.rows[1].art:GetAlpha(), 1, "its list rows untouched")
end)

T.test("skins: the confirm boxes: our window and buttons, the warning icon kept", function()
    local pop
    login(function()
        pop = CreateFrame("Frame", "StaticPopup1", UIParent)
        pop.BG = CreateFrame("Frame", nil, pop)
        pop.AlertIcon = pop:CreateTexture()
        pop.Text = pop:CreateFontString()
        pop.ButtonContainer = CreateFrame("Frame", nil, pop)
        local b = CreateFrame("Button", "StaticPopup1Button1", pop.ButtonContainer)
        local normal = b:CreateTexture()
        function b:GetNormalTexture() return normal end
        pop.ButtonContainer.Button1 = b
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(stub.skins.Kit.ShellOf(pop), "our window")
    T.eq(pop.AlertIcon:GetAlpha(), 1, "the warning icon kept")
    T.eq(pop.BG:GetAlpha(), 0, "the game's panel gone")
    T.truthy(stub.skins.Kit.ButtonOf(StaticPopup1Button1), "our buttons")
    T.eq(StaticPopup1Button1:GetNormalTexture():GetAlpha(), 0)
end)

-- With the controller UI on, the game stores a confirm box's focus actions as
-- the box opens. Any addon code on the pieces inside it runs first and taints
-- them, and cancelling a logout was then blocked. Only the box's own hooks
-- (which run after the game's) may run Daylight UI code.
T.test("skins: no Daylight UI code runs inside a confirm box while the game opens it", function()
    local pop
    login(function()
        pop = CreateFrame("Frame", "StaticPopup1", UIParent)
        pop:SetSize(320, 120)
        pop.Text = pop:CreateFontString()
        pop.ButtonContainer = CreateFrame("Frame", nil, pop)
        for i = 1, 2 do
            local b = CreateFrame("Button", "StaticPopup1Button" .. i, pop.ButtonContainer)
            b:SetSize(120, 24)
            b:SetText(i == 1 and "Okay" or "Cancel")
            pop.ButtonContainer["Button" .. i] = b
        end
        pop.ExtraButton = CreateFrame("Button", nil, pop)
        pop.EditBox = CreateFrame("EditBox", nil, pop)
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(stub.skins.Kit.ButtonOf(StaticPopup1Button1), "still our buttons")
    local inside = stub.AddonScriptsInside(pop)
    T.eq(#inside, 0, "Daylight UI code inside the box: " .. table.concat(inside, ", "))

    -- The quiet buttons still look disabled and pressed while the box is up.
    local Kit = stub.skins.Kit
    local s1, s2 = Kit.ButtonOf(StaticPopup1Button1), Kit.ButtonOf(StaticPopup1Button2)
    pop:Hide()
    pop:Show()
    T.truthy(Kit.quietPoller:IsShown(), "watching while the box is up")
    StaticPopup1Button1:Disable()
    StaticPopup1Button2:SetButtonState("PUSHED")
    Kit.quietPoller:GetScript("OnUpdate")(Kit.quietPoller, 0.016)
    T.truthy(s1.off, "a disabled button shows as off")
    T.truthy(s2.down, "a pressed button shows as down")
    pop:Hide()
    T.falsy(Kit.quietPoller:IsShown(), "nothing runs once the box is gone")
    T.falsy(s2.down, "back to rest when the box closes")
end)

T.test("skins: the stack split box: our window, arrows and buttons, the amount in the accent", function()
    local f
    login(function()
        f = CreateFrame("Frame", "StackSplitFrame", UIParent)
        f:SetSize(172, 96)
        f.SingleItemSplitBackground = f:CreateTexture()
        f.MultiItemSplitBackground = f:CreateTexture()
        f.StackSplitText = f:CreateFontString()
        f.StackItemCountText = f:CreateFontString()
        for _, key in ipairs({ "LeftButton", "RightButton" }) do
            local b = CreateFrame("Button", nil, f)
            b:SetSize(16, 16)
            local normal = b:CreateTexture()
            function b:GetNormalTexture() return normal end
            f[key] = b
        end
        f.OkayButton = button(nil, f)
        f.CancelButton = button(nil, f)
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(f), "our window")
    T.eq(f.SingleItemSplitBackground:GetAlpha(), 0, "the game's backgrounds gone")
    T.eq(f.MultiItemSplitBackground:GetAlpha(), 0)
    f.MultiItemSplitBackground:Show()
    T.eq(f.MultiItemSplitBackground:GetAlpha(), 0, "and stay gone when the game shows one")
    T.truthy(Kit.ButtonOf(f.OkayButton), "our buttons")
    T.truthy(Kit.ButtonOf(f.CancelButton))
    T.eq(f.LeftButton:GetNormalTexture():GetAlpha(), 0, "the game's arrows gone")
    local ar, ag, ab = DaylightUI.Style.Pop()
    local r, g, b = f.StackSplitText:GetTextColor()
    T.near(r, ar, 0.01); T.near(g, ag, 0.01); T.near(b, ab, 0.01)
    f:Hide(); f:Show()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: a statistics sub-header's collapse button: ours, pointing the way the group is", function()
    login()
    local Kit = stub.skins.Kit
    local row = CreateFrame("Button", nil, UIParent)
    row.Content = CreateFrame("Frame", nil, row)
    local tcb = CreateFrame("Button", nil, row)
    local normal = tcb:CreateTexture()
    function tcb:GetNormalTexture() return normal end
    row.ToggleCollapseButton = tcb
    normal:SetAtlas("campaign_headericon_closed")
    function normal:GetAtlas() return self.__atlas end
    Kit.ListRow(row)
    T.truthy(Kit.ShellOf(tcb), "our control")
    T.eq(normal:GetAlpha(), 0, "the game's red art gone")
    local chev
    for _, r in ipairs({ tcb:GetRegions() }) do
        if r.__texture == DaylightUI.MEDIA .. "ui-chevron.png" then chev = r end
    end
    T.eq(chev.__rotation, Kit.ROTATION.right, "closed: pointing right")
    -- The game swaps the art as it fills the row (RefreshIcon from Initialize),
    -- then the list's OnInitializedFrame runs Kit.RelightIn through Kit.EachRow.
    normal:SetAtlas("campaign_headericon_open")
    Kit.RelightIn(row, Kit.ROW_LIGHT_DEPTH)
    T.eq(chev.__rotation, Kit.ROTATION.down, "open: pointing down")
    normal:SetAtlas("campaign_headericon_closed")
    Kit.ListRow(row)                                    -- the pass over the rows after an update
    T.eq(chev.__rotation, Kit.ROTATION.right, "closed again")
    T.truthy(Kit.Erased(normal), "the game's art erased for good")
    T.isnil(rawget(normal, "SetAtlas"), "no hook on the game's art")
end)

T.test("skins: dropdowns: a plain outline, a down chevron, the game's text size; found by key too", function()
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    local dd = CreateFrame("Button", nil, f)
    dd.Arrow = dd:CreateTexture()
    dd.Text = dd:CreateFontString()
    dd.Text:SetFont("x", 10, "")
    function dd.Text:GetFont() return "x", 10, "" end
    f.SearchOptionsDropdown = dd
    Kit.Auto(f)
    local s = stub.skins.Kit.ShellOf(dd)
    T.truthy(s, "found by its key")
    T.isnil(s.opts.borderColor, "a plain outline")
    T.eq(dd.Text.__font[2], 10, "the game's text size")
    dd:GetScript("OnEnter")(dd)
    T.truthy(s.opts.borderColor, "lighter under the mouse")
end)

T.test("skins: the professions book: panels on our look, its skill bars and spell buttons left alone", function()
    local panel, bar, spell
    login(function()
        local f = window("ProfessionsBookFrame")
        f.ProfessionsContentFrame = CreateFrame("Frame", nil, f)
        panel = CreateFrame("Frame", nil, f.ProfessionsContentFrame)
        panel.Background = panel:CreateTexture()
        panel.ProfessionName = panel:CreateFontString()
        f.ProfessionsContentFrame.PrimaryProfession1 = panel
        bar = CreateFrame("Frame", nil, panel)
        bar.Fill, bar.Mask, bar.bg = bar:CreateTexture(), bar:CreateTexture(), bar:CreateTexture()
        panel.StatusBar = bar
        bar.ExpansionDropdownButton = CreateFrame("Button", nil, bar)
        spell = CreateFrame("CheckButton", nil, panel)
        spell.IconTexture = spell:CreateTexture()
        stub.loadedAddOns.Blizzard_ProfessionsBook = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(panel.Background:GetAlpha(), 0, "the panel's art gone")
    T.truthy(stub.skins.Kit.ShellOf(panel), "on our row look")
    T.eq(bar.bg:GetAlpha(), 1, "the skill bar left as it is")
    T.isnil(bar.Fill.__texture, "its fill untouched")
    local dd = bar.ExpansionDropdownButton
    T.eq(dd:GetAlpha(), 0, "the bar's expansion dropdown faded out (one skill line per profession on Forever)")
    T.falsy(dd:IsMouseEnabled(), "and it takes no clicks")
    T.isnil(stub.skins.Kit.ShellOf(spell), "a spell button isn't a checkbox")
end)

T.test("skins: a bar drawn its own way (a profession's skill bar) is left alone, and what's in it", function()
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    local bar = CreateFrame("Frame", nil, f)
    bar.Background, bar.Fill, bar.Mask, bar.Border = bar:CreateTexture(), bar:CreateTexture(), bar:CreateTexture(), bar:CreateTexture()
    bar.ExpansionDropdownButton = CreateFrame("DropdownButton", nil, bar)
    f.RankBar = bar
    Kit.Auto(f)
    T.eq(bar.Background:GetAlpha(), 1, "its art kept")
    T.isnil(bar.Fill.__texture, "its fill kept")
    T.isnil(stub.skins.Kit.ShellOf(bar.ExpansionDropdownButton), "and what's in it")
end)

T.test("skins: in a list, a header of three pieces is a quiet row (its +/- kept), not an accent button", function()
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    local box = list(f)
    box.ScrollTarget = CreateFrame("Frame", nil, box)
    local header = button(nil, box.ScrollTarget)
    header.CollapseIcon = header:CreateTexture()
    box.rows[1] = header
    Kit.Auto(f)
    local s = stub.skins.Kit.ShellOf(header)
    T.truthy(s, "on the row look")
    T.eq(s.opts.borderColor, stub.skins.Kit.ROW_BORDER, "the row's gray outline, not the accent")
    T.eq(header.Left:GetAlpha(), 0, "its pieces gone")
    T.eq(header.CollapseIcon:GetAlpha(), 1, "its +/- kept")
end)

T.test("skins: a favorite star isn't a checkbox", function()
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    local star = CreateFrame("CheckButton", nil, f)
    local normal = star:CreateTexture()
    normal:SetAtlas("auctionhouse-icon-favorite")
    function normal:GetAtlas() return self.__atlas end
    function star:GetNormalTexture() return normal end
    Kit.Auto(f)
    T.isnil(stub.skins.Kit.ShellOf(star))
    T.eq(normal:GetAlpha(), 1, "its star kept")
end)

T.test("skins: the template doesn't look again at what it has done, nor re-read keys that haven't changed", function()
    login()
    local Kit = stub.skins.Kit
    local f, p = standardWindow("TestWindowRepeat")
    Kit.Auto(f)
    local calls = 0
    local realPart = p.ok.GetFontString
    p.ok.GetFontString = function(...) calls = calls + 1 return realPart(...) end
    for _ = 1, 5 do Kit.Auto(f) end
    T.eq(calls, 0, "a done button isn't looked at again")
end)

T.test("skins: a big window is dressed over a few frames, not all at once, lists and all", function()
    login()
    local Kit = stub.skins.Kit
    local budget = Kit.AUTO_BUDGET
    Kit.AUTO_BUDGET = 5
    local f = CreateFrame("Frame", nil, UIParent)
    local buttons = {}
    for i = 1, 30 do
        local holder = CreateFrame("Frame", nil, f)
        buttons[i] = button(nil, holder)
    end
    local box = list(f)
    box.ScrollTarget = CreateFrame("Frame", nil, box)
    for i = 1, 8 do box.rows[i] = button(nil, box.ScrollTarget) end
    Kit.Auto(f)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.isnil(stub.skins.Kit.ShellOf(buttons[30]), "not all in the first frame")
    for _ = 1, 40 do stub.RunOnUpdate(Kit.walker, 1 / 60) end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    for i = 1, 30 do T.truthy(stub.skins.Kit.ButtonOf(buttons[i]), "button " .. i) end
    T.truthy(stub.skins.Kit.ShellOf(box.rows[8]), "the list's rows too")
    T.falsy(Kit.walker:IsShown(), "and it stops")
    Kit.AUTO_BUDGET = budget
end)

T.test("skins: money (gold, silver, copper) keeps the game's coins", function()
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    local money = CreateFrame("Frame", nil, f)
    for _, k in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        local b = CreateFrame("Button", nil, money)
        b:SetSize(40, 13)
        local coin = b:CreateTexture()
        coin:SetSize(13, 13)
        local label = b:CreateFontString()
        function b:GetNormalTexture() return coin end
        function b:GetFontString() return label end
        b.coin = coin
        money[k] = b
    end
    f.MoneyFrame = money
    -- A lone coin button, not in a money frame, by its shape alone.
    local loose = CreateFrame("Button", nil, f)
    loose:SetSize(40, 13)
    local coin = loose:CreateTexture()
    coin:SetSize(13, 13)
    local label = loose:CreateFontString()
    function loose:GetNormalTexture() return coin end
    function loose:GetFontString() return label end
    Kit.Auto(f)
    T.eq(money.CopperButton.coin:GetAlpha(), 1, "the coin kept")
    T.isnil(stub.skins.Kit.ShellOf(money.GoldButton), "no button look on it")
    T.eq(coin:GetAlpha(), 1, "a coin beside an amount isn't button art")
    T.isnil(stub.skins.Kit.ShellOf(loose))
end)

T.test("skins: a window is gone over again when its pages are shown, only what's shown, not on a timer", function()
    login()
    local Engine = stub.skins.Engine
    local f = window("TestPagedFrame")
    local pageA = CreateFrame("Frame", nil, f)
    button(nil, pageA)
    local pageB = CreateFrame("Frame", nil, f)
    button(nil, pageB)
    pageB:Hide()
    Engine.Window({ key = "test:paged", pack = "npc", frame = "TestPagedFrame", watch = true })
    stub.RunTimers()
    -- A button made later on page B while it's hidden isn't styled yet.
    local late = button(nil, pageB)
    f:GetScript("OnShow")(f)
    stub.RunTimers()
    T.isnil(stub.skins.Kit.ShellOf(late), "a hidden page isn't gone over")
    -- Once the page shows, it's styled the frame after.
    pageB:Show()
    pageB:GetScript("OnShow")(pageB)
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ButtonOf(late), "shown, it is")
end)

T.test("skins: a window opened is gone over once more the frame after only when something's new", function()
    login()
    local Kit, Engine = stub.skins.Kit, stub.skins.Engine
    local f = window("TestOnceFrame")
    button(nil, f)
    Engine.Window({ key = "test:once", pack = "npc", frame = "TestOnceFrame" })
    stub.RunTimers()
    local walks, real = 0, Kit.Auto
    Kit.Auto = function(...) walks = walks + 1 return real(...) end
    f:GetScript("OnShow")(f)
    stub.RunTimers()
    T.eq(walks, 1, "nothing new the frame after: one walk")
    -- Anything the game makes right after opening is styled the frame after.
    walks = 0
    f:GetScript("OnShow")(f)
    local late = button(nil, f)
    stub.RunTimers()
    Kit.Auto = real
    T.eq(walks, 2, "something new: walked again")
    T.truthy(Kit.ButtonOf(late), "and dressed")
end)

T.test("skins: a font is set once, not again on every update of the list it's in", function()
    login()
    local Kit = stub.skins.Kit
    local fs = UIParent:CreateFontString()
    local sets = 0
    local real = fs.SetFont
    fs.SetFont = function(...) sets = sets + 1 return real(...) end
    for _ = 1, 10 do Kit.Font(fs, 12) end
    T.eq(sets, 1, "once")
    Kit.Font(fs, 14)
    T.eq(sets, 2, "again for a new size")
end)

T.test("skins: a list's rows are gone over once a frame however often it updates", function()
    login()
    local Kit = stub.skins.Kit
    local box = list(UIParent)
    box.rows[1] = CreateFrame("Frame", nil, box)
    local calls = 0
    Kit.EachRow(box, function() calls = calls + 1 end)
    calls = 0
    for _ = 1, 8 do box:Update() end
    T.eq(calls, 0, "not on each update")
    stub.RunTimers()
    T.eq(calls, 1, "once, the frame after")
end)

T.test("skins: /dui skins profile toggles", function()
    login()
    DaylightUI.RunCommand("skins profile")
    T.truthy(stub.skins.Kit.Profiling)
    T.truthy(stub.ChatContains("skins profile on"))
    DaylightUI.RunCommand("skins profile")
    T.falsy(stub.skins.Kit.Profiling)
end)

T.test("skins: with profiling on, opening a window prints what its first frames cost", function()
    login()
    local Engine = stub.skins.Engine
    standardWindow("TestProfiledFrame")
    Engine.Window({ key = "test:profiled", pack = "npc", frame = "TestProfiledFrame" })
    stub.RunTimers()
    DaylightUI.RunCommand("skins profile")
    TestProfiledFrame:GetScript("OnShow")(TestProfiledFrame)
    stub.RunOnUpdate(Engine.profiler, 0.05)
    T.truthy(stub.ChatContains("frame 1 took 50ms"), "a line for the frame")
    DaylightUI.RunCommand("skins profile")
end)

T.test("skins: what a window makes as it opens (a menu's buttons) is dressed in that same frame", function()
    login()
    local Engine = stub.skins.Engine
    local f = window("TestMenuFrame")
    Engine.Window({ key = "test:menu", pack = "npc", frame = "TestMenuFrame" })
    stub.RunTimers()
    -- The game makes the menu's buttons as it opens (its OnShow runs first).
    local made
    f:SetScript("OnShow", function() made = button(nil, f) end)
    Engine.Window({ key = "test:menu2", pack = "npc", frame = "TestMenuFrame" })
    f:GetScript("OnShow")(f)
    T.truthy(stub.skins.Kit.ButtonOf(made), "dressed at once, not a frame later")
end)

T.test("skins: what a window fills in just after it opens (the spellbook's pages) is dressed the frame after", function()
    login()
    local Engine = stub.skins.Engine
    local f = window("TestBookFrame")
    local fill
    Engine.Window({ key = "test:book", pack = "npc", frame = "TestBookFrame",
        after = function(_, _, again) fill = again end })
    stub.RunTimers()
    f:GetScript("OnShow")(f)                 -- opened: gone over at once
    local later = button(nil, f)             -- the game fills its pages in, same frame
    fill()                                   -- and says so (a tab set)
    T.isnil(stub.skins.Kit.ShellOf(later), "not twice in the frame")
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ButtonOf(later), "the frame after, it is")
end)

T.test("skins: the world map: our window under the map, its border frame's buttons kept, the quest log's headers", function()
    local f
    login(function()
        f = CreateFrame("Frame", "WorldMapFrame", UIParent)
        f.BorderFrame = CreateFrame("Frame", nil, f)
        f.BorderFrame.art = f.BorderFrame:CreateTexture()
        f.BorderFrame.CloseButton = CreateFrame("Button", nil, f.BorderFrame)
        f.NavBar = CreateFrame("Frame", nil, f)
        f.NavBar.art = f.NavBar:CreateTexture()
        local home = CreateFrame("Button", nil, f.NavBar)
        home.text = home:CreateFontString()
        f.NavBar.homeButton = home
        local qm = CreateFrame("Frame", "QuestMapFrame", f)
        qm.Background = qm:CreateTexture()
        local qs = CreateFrame("Frame", "QuestScrollFrame", qm)
        qs.Contents = CreateFrame("Frame", nil, qs)
        local header = CreateFrame("Button", nil, qs.Contents)
        header.Left, header.Middle, header.Right = header:CreateTexture(), header:CreateTexture(), header:CreateTexture()
        header.ButtonText = header:CreateFontString()
        header.CollapseButton = CreateFrame("Button", nil, header)
        qs.header = header
        local questRow = CreateFrame("Button", nil, qs.Contents)
        questRow.art = questRow:CreateTexture()
        qs.questRow = questRow
        local count = CreateFrame("Frame", nil, qs.Contents)
        count.art = count:CreateTexture()
        count.Text = count:CreateFontString()
        count.Text:SetText("Quests: 15/40")
        qs.Contents.QuestCount = count
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(f), "our window, under the map")
    T.eq(f.BorderFrame:GetAlpha(), 1, "its border frame kept (close, title)")
    T.eq(f.BorderFrame.art:GetAlpha(), 0, "its art gone")
    T.truthy(Kit.ShellOf(f.NavBar), "the navigation bar")
    T.eq(QuestMapFrame.Background:GetAlpha(), 0, "the quest log's background gone")
    T.truthy(Kit.ShellOf(QuestScrollFrame.header), "a zone header on our row look")
    T.eq(QuestScrollFrame.questRow.art:GetAlpha(), 1, "a quest row left as it is")
    local count = QuestScrollFrame.Contents.QuestCount
    T.truthy(Kit.ShellOf(count), "the quest count box, our look")
    T.eq(count.art:GetAlpha(), 0, "its own art gone")
end)

T.test("skins: a gossip option's quest name, set through its button in the game's black, is light at once", function()
    login()
    local box = GossipFrame.GreetingPanel.ScrollBox
    local b = CreateFrame("Button", nil, box)
    local fs = b:CreateFontString()
    function b:GetFontString() return fs end
    function b:SetText(text) fs.__text = text end          -- the client sets its label itself
    local setText, update = b.SetText, box.Update
    box.rows[1] = b
    box:Update(function(row) row:SetText("|cff000000A Token of Good Faith|r") end)
    stub.RunTimers()                                        -- a new row: made light the frame after
    T.truthy(not fs:GetText():find("|cff000000", 1, true), "rewritten")
    -- The row reused for another option is relit in the same frame the game
    -- fills it, so there's no frame of black text.
    box:Update(function(row)
        row:SetText("|cff000000Another Quest|r")
        fs:SetTextColor(0, 0, 0)
    end)
    T.truthy(not fs:GetText():find("|cff000000", 1, true), "rewritten at once")
    T.truthy(fs.__textColor[1] > 0.8, "light at once")
    T.eq(b.SetText, setText, "no hook on the button")
    T.eq(box.Update, update, "no hook on the list")
end)

T.test("skins: a window that isn't there yet is skinned once a game addon brings it", function()
    login()
    local Engine = stub.skins.Engine
    Engine.Window({ key = "test:lfg", pack = "social", frame = "TestLateLFGFrame" })
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local f = window("TestLateLFGFrame")           -- its addon loads it later
    stub.FireEvent("ADDON_LOADED", "Blizzard_SomethingElse")
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ShellOf(f), "skinned when it turned up")
end)

T.test("skins: window skins take the accent only on hover and selection", function()
    login()
    local Kit = stub.skins.Kit
    DaylightUI:Set("general", "accentColor", { 1, 0, 0 })
    DaylightUI:Set("general", "accent", "custom")
    stub.RunTimers()
    local b = QuestFrameAcceptButton
    local s = Kit.ButtonOf(b)
    T.rgb(s.band.__vertex, DaylightUI.Widgets.BUTTON.band, "a button at rest: still its quiet band")
    b:SetSize(100, 22)
    b:GetScript("OnEnter")(b)
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02) end
    T.rgb(Kit.TraceOf(b).right.__vertex, { 1, 0, 0 }, "under the mouse: traced in the player's accent")
    b:GetScript("OnLeave")(b)
    local row = CreateFrame("Button", nil, UIParent)
    local sel = row:CreateTexture()
    Kit.Row(row, nil, sel)
    T.eq(Kit.ShellOf(row).opts.borderColor, Kit.SELECTED, "a selected row: the soft light gray")
end)

T.test("skins: the quest greeting's quest buttons (from a pool, no names) are light, their quest names too", function()
    login(function()
        local panel = CreateFrame("Frame", "QuestFrameGreetingPanel", QuestFrame)
        _G.QuestFrameGreetingPanel_OnShow = function() end
        panel.child = CreateFrame("Frame", nil, panel)
    end)
    local b = CreateFrame("Button", nil, QuestFrameGreetingPanel.child)
    local fs = b:CreateFontString()
    function b:GetFontString() return fs end
    function b:SetFormattedText(fmt, ...) fs.__text = string.format(fmt, ...) end
    b:SetFormattedText("|cff000000%s|r", "Drive Them Out")
    fs:SetTextColor(0, 0, 0)
    QuestFrameGreetingPanel_OnShow()
    T.truthy(fs.__textColor[1] > 0.8, "light")
    T.truthy(not fs:GetText():find("|cff000000", 1, true), "its name's black rewritten")
    b:SetFormattedText("|cff000000%s|r", "Dwarven Digging")          -- reused for another quest
    QuestFrameGreetingPanel_OnShow()                                  -- (the game's greeting fill)
    T.truthy(not fs:GetText():find("|cff000000", 1, true), "and again as it's reused")
end)

T.test("skins: the old flight map keeps its map (drawn into the window's inset background)", function()
    local f
    login(function()
        f = CreateFrame("Frame", "TaxiFrame", UIParent)
        f.InsetBg = f:CreateTexture("TaxiFrameInsetBg")
        f.Bg = f:CreateTexture()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(stub.skins.Kit.ShellOf(f), "our window")
    T.eq(f.InsetBg:GetAlpha(), 1, "the map kept")
    T.eq(f.Bg:GetAlpha(), 0, "its frame art gone")
end)







T.test("skins: a quest opened from the map: parchment and frame gone, our buttons, rewards outlined", function()
    local d, rewards
    login(function()
        local map = window("WorldMapFrame")
        local qm = CreateFrame("Frame", "QuestMapFrame", map)
        d = CreateFrame("Frame", nil, qm)
        qm.DetailsFrame = d
        d.Bg = d:CreateTexture()
        d.SealMaterialBG = d:CreateTexture()
        d.BorderFrame = CreateFrame("Frame", nil, d)
        d.BorderFrame.Border = d.BorderFrame:CreateTexture()
        d.BackFrame = CreateFrame("Frame", nil, d)
        d.BackFrame.art = d.BackFrame:CreateTexture()
        d.BackFrame.BackButton = button(nil, d.BackFrame)
        for _, key in ipairs({ "AbandonButton", "ShareButton", "TrackButton" }) do d[key] = button(nil, d) end
        d.ShareButton.divider = d.ShareButton:CreateTexture()
        d.RewardsFrameContainer = CreateFrame("Frame", nil, d)
        local rf = CreateFrame("Frame", nil, d.RewardsFrameContainer)
        d.RewardsFrameContainer.RewardsFrame = rf
        rf.Top, rf.Bottom, rf.Background = rf:CreateTexture(), rf:CreateTexture(), rf:CreateTexture()
        rf.Label = rf:CreateFontString()
        rewards = CreateFrame("Frame", "MapQuestInfoRewardsFrame", d)
        local item = CreateFrame("Button", nil, rewards)
        item.Icon, item.IconBorder = item:CreateTexture(), item:CreateTexture()
        rewards.RewardButtons = { item }
        _G.QuestMapFrame_ShowQuestDetails = function() end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    WorldMapFrame:Show()
    stub.RunTimers()
    local Kit = stub.skins.Kit
    T.eq(d.Bg:GetAlpha(), 0, "the parchment gone")
    T.eq(d.BorderFrame.Border:GetAlpha(), 0, "the gold frame gone")
    T.eq(d.BackFrame.art:GetAlpha(), 0, "the art behind Back gone")
    T.truthy(Kit.ButtonOf(d.BackFrame.BackButton), "Back is our button")
    T.eq(d.ShareButton.divider:GetAlpha(), 0, "Share's dividers gone")
    T.truthy(Kit.ButtonOf(d.AbandonButton))
    -- A second quest opened: our outline on Share is left alone.
    local new = CreateFrame("Button", nil, rewards)
    new.Icon, new.IconBorder = new:CreateTexture(), new:CreateTexture()
    rewards.RewardButtons[2] = new
    QuestMapFrame_ShowQuestDetails()
    T.truthy(Kit.ShellOf(new), "a reward made for the new quest is outlined")
    T.truthy(Kit.ShellOf(rewards.RewardButtons[1]), "and the first")
    T.eq(d.RewardsFrameContainer.RewardsFrame.Top:GetAlpha(), 0, "the rewards header's frame gone")
end)

T.test("skins: a quest opened from the map has light text, even with the NPC pack off", function()
    login(function()
        _G.DaylightUIDB = { modules = { Skins = { packs = { npc = false } } } }
        local map = window("WorldMapFrame")
        local qm = CreateFrame("Frame", "QuestMapFrame", map)
        qm.DetailsFrame = CreateFrame("Frame", nil, qm)
        _G.QuestMapFrame_ShowQuestDetails = function() end
    end)
    WorldMapFrame:Show()
    stub.RunTimers()
    QuestInfoDescriptionText:SetTextColor(0.2, 0.1, 0)     -- the game's parchment ink
    QuestMapFrame_ShowQuestDetails()
    T.truthy(QuestInfoDescriptionText.__textColor[1] > 0.8, "light text on our dark panel")
    T.eq(QuestInfoTitleHeader.__textColor[1], stub.skins.Kit.HEADER[1], "titles in the accent")
end)

-- A roll popup as the game's template makes it (GroupLootFrame.xml, forever).
local function rollPopup()
    local roll = CreateFrame("Frame", "GroupLootFrame1", UIParent)
    roll:SetSize(277, 67)
    roll.Background = roll:CreateTexture(); roll.Background:SetTexture("gold frame")
    roll.rollID = 7
    roll.IconFrame = CreateFrame("Button", nil, roll)
    roll.IconFrame:SetSize(34, 34)
    roll.IconFrame.Icon = roll.IconFrame:CreateTexture()
    roll.IconFrame.Border = roll.IconFrame:CreateTexture()
    roll.Name = roll:CreateFontString()
    roll.Timer = CreateFrame("StatusBar", nil, roll)
    roll.Timer:SetMinMaxValues(0, 60000)
    local box = CreateFrame("Frame", nil, roll)
    roll.LootButtonContainer = box
    for _, key in ipairs({ "NeedButton", "GreedButton", "PassButton", "TransmogButton" }) do
        local b = CreateFrame("Button", nil, box)
        b:SetSize(32, 32)
        local art, glow = b:CreateTexture(), b:CreateTexture()
        art:SetTexture("dice"); glow:SetTexture("dice glow")
        function b:GetNormalTexture() return art end
        function b:GetHighlightTexture() return glow end
        box[key] = b
    end
    roll:Hide()
    return roll
end

T.test("skins: a loot roll popup gets our look: quality line and icon outline, the buttons in a row, our timer", function()
    local roll
    local S = login(function()
        roll = rollPopup()
        _G.GetLootRollItemInfo = function(id) if id == 7 then return "icon", "Sword", 1, 3, true end end
        _G.GetItemQualityColor = function(q) return 0, 0.44, 0.87 end
        _G.GetLootRollItemLink = function() return "item:1" end
        if C_Item then C_Item.GetItemQualityColor = _G.GetItemQualityColor end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    roll:Show()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = S.Kit
    T.eq(roll.Background:GetAlpha(), 0, "the gold frame gone")
    T.truthy(Kit.ShellOf(roll), "our window look")
    local s = Kit.ShellOf(roll.IconFrame)
    T.truthy(s, "the icon outlined")
    T.eq(s.opts.borderColor[3], 0.87, "in the item's quality color")
    T.eq(roll.IconFrame.Border:GetAlpha(), 0, "the game's quality ring hidden")
    local need = roll.LootButtonContainer.NeedButton
    T.eq(need:GetNormalTexture():GetAlpha(), 1, "the dice stay")
    T.eq(need:GetHighlightTexture():GetAlpha(), 0, "the game's hover glow gone")
    T.truthy(Kit.TraceOf(need) or Kit.ShellOf(need), "the dice in our control box")
    T.eq(need:GetWidth(), S.LootRoll.BUTTON, "the buttons our size")
    local r = S.LootRoll.Of(roll)
    T.truthy(r, "our pieces on it")
    T.eq(roll.Timer:GetAlpha(), 0, "the game's timer unseen")
    T.truthy(r.sub:GetText():find("BoP", 1, true), "a bind-on-pickup item says so")
    -- The game fires OnValueChanged on SetValue (the fake game doesn't).
    local function tick(v) roll.Timer:SetValue(v); roll.Timer:GetScript("OnValueChanged")(roll.Timer, v) end
    tick(42000)
    T.eq(r.bar:GetValue(), 42000, "our timer follows the game's")
    T.eq(r.time:GetText(), "42s", "the seconds left")
    T.falsy(r.low, "not low yet")
    tick(9000)
    T.truthy(r.low, "the last quarter warns")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.GetLootRollItemInfo, _G.GetItemQualityColor, _G.GetLootRollItemLink = nil, nil, nil
end)

T.test("skins: a loot toast gets our look as it shows, its icon outlined in the item's quality; the roll icon stays", function()
    local S = login(function()
        _G.LootAlertSystem, _G.MoneyWonAlertSystem = {}, {}
        _G.AlertFrame_ShowNewAlert = function(f) f:Show() end
        _G.GetItemInfo = function(link) if link == "sword" then return "Sword", link, 3 end end
        _G.GetItemQualityColor = function(q) return 0, 0.44, 0.87 end
        if C_Item then C_Item.GetItemQualityColor, C_Item.GetItemInfo = _G.GetItemQualityColor, _G.GetItemInfo end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = S.Kit
    local t = CreateFrame("Button", nil, UIParent)
    t.queue = LootAlertSystem
    t.Background = t:CreateTexture(); t.Background:SetTexture("gold toast")
    t.glow = t:CreateTexture()
    t.RollTypeIcon = t:CreateTexture(); t.RollTypeIcon:SetTexture("dice")
    t.Label, t.ItemName, t.RollValue = t:CreateFontString(), t:CreateFontString(), t:CreateFontString()
    t.lootItem = CreateFrame("Button", nil, t)
    t.lootItem.Icon = t.lootItem:CreateTexture()
    t.lootItem.IconBorder = t.lootItem:CreateTexture()
    t.hyperlink = "sword"
    AlertFrame_ShowNewAlert(t)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(t.Background:GetAlpha(), 0, "the gold toast gone")
    T.truthy(Kit.Erased(t.Background), "erased for good: in game its alpha came back by the next toast")
    t.glow:Show()                                     -- the game, as it animates the toast
    T.truthy(Kit.Erased(t.glow), "its gold glow erased for good (a see-through mask)")
    T.eq(t.glow.__masks[1].__texture, Kit.ERASE)
    T.isnil(rawget(t.glow, "Show"), "no hook on the glow's Show")
    T.eq(t.RollTypeIcon:GetAlpha(), 1, "the dice stay")
    T.eq(t.lootItem.IconBorder:GetAlpha(), 0, "the game's quality ring hidden")
    local s = Kit.ShellOf(t.lootItem)
    T.truthy(s, "the icon outlined")
    T.eq(s.opts.borderColor[3], 0.87, "in the item's quality color")
    -- The game reuses the toast: dressed once, recolored each time.
    _G.GetItemInfo = function() return "Rag", "rag", 0 end
    _G.GetItemQualityColor = function() return 0.6, 0.6, 0.6 end
    if C_Item then C_Item.GetItemQualityColor, C_Item.GetItemInfo = _G.GetItemQualityColor, _G.GetItemInfo end
    t.hyperlink = "rag"
    AlertFrame_ShowNewAlert(t)
    T.eq(Kit.ShellOf(t.lootItem), s, "the same outline")
    T.eq(s.opts.borderColor[3], 0.6, "in the new item's color")
    -- Money won: its coin outlined.
    local m = CreateFrame("Button", nil, UIParent)
    m.queue = MoneyWonAlertSystem
    m.Background = m:CreateTexture(); m.Background:SetTexture("gold toast")
    m.Icon, m.IconBorder = m:CreateTexture(), m:CreateTexture()
    m.Label, m.Amount = m:CreateFontString(), m:CreateFontString()
    AlertFrame_ShowNewAlert(m)
    T.eq(m.Background:GetAlpha(), 0, "the money toast's gold gone")
    T.truthy(Kit.Erased(m.Background), "the money toast's erased for good too")
    T.eq(m.IconBorder:GetAlpha(), 0, "its gold ring gone")
    -- Any other toast is left as the game draws it.
    local o = CreateFrame("Button", nil, UIParent)
    o.Background = o:CreateTexture(); o.Background:SetTexture("achievement")
    AlertFrame_ShowNewAlert(o)
    T.eq(o.Background:GetAlpha(), 1, "another toast untouched")
    _G.LootAlertSystem, _G.MoneyWonAlertSystem, _G.AlertFrame_ShowNewAlert = nil, nil, nil
    _G.GetItemInfo, _G.GetItemQualityColor = nil, nil
end)

-- The loot window (Packs/System.lua). The fake is the game's own template and
-- what its Init writes (tests/lootworld.lua). Skinned only, with no motion of its own.
T.test("skins: the loot window's rows are our rows: the game's card and glow gone, our outline lit on hover", function()
    local LW, f = require("lootworld"), nil
    local S = login(function() f = LW.Install() end)
    LW.Open(f, LW.Corpse())
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = S.Kit
    local row = f.ScrollBox.rows[2]
    for _, key in ipairs({ "NameFrame", "BorderFrame", "HighlightNameFrame", "PushedNameFrame", "QualityStripe" }) do
        T.eq(row[key]:GetAlpha(), 0, "the game's " .. key .. " gone")
    end
    T.eq(row.IconQuestTexture:GetAlpha(), 1, "a quest item's mark stays")
    local s = Kit.ShellOf(row)
    T.truthy(s, "the row look")
    T.eq(s.opts.borderColor, Kit.ROW_BORDER, "at rest: the row's quiet outline")
    row.Item:GetScript("OnEnter")(row.Item)
    T.truthy(s.opts.borderColor ~= Kit.ROW_BORDER, "the mouse over the item: lit")
    row.Item:GetScript("OnLeave")(row.Item)
    T.eq(s.opts.borderColor, Kit.ROW_BORDER, "and quiet again")
    T.isnil(S.LootWindow, "no light sweep")
    -- Taking an item and closing leaves no errors and nothing of the skin behind.
    LW.Take(f, 1)
    LW.Close(f)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: the breath bar's angled end has its own switch; off, the end and the fill are straight", function()
    local t
    local S = login(function()
        local c = CreateFrame("Frame", "MirrorTimerContainer", UIParent)
        t = CreateFrame("Frame", nil, c)
        t.StatusBar = CreateFrame("StatusBar", nil, t)
        t.Text = t:CreateFontString()
        t.Setup = function() end
        c.mirrorTimers = { t }
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Style = DaylightUI.Style
    local h = S.Breath.holders[t]
    T.truthy(Style.GetSlant(h).cut > 0, "angled by default")
    DaylightUI:Set("Skins", "breathSlant", false)
    T.eq(Style.GetSlant(h).cut, 0, "straight end")
    local mask = Style.GetFillMask(h.bar)
    T.truthy(not mask or not mask.added, "the fill straight too")
    DaylightUI:Set("Skins", "breathSlant", true)
    T.truthy(Style.GetSlant(h).cut > 0, "angled again")
    -- The client kept the cut after RemoveMaskTexture (seen on the flight timer).
    -- Every mask is removed and also blanked, whether the bar is shown or not.
    local function count(f, out)
        out = out or { masked = 0, cutting = 0 }
        for _, r in ipairs({ f:GetRegions() }) do
            if r.__masks and #r.__masks > 0 then out.masked = out.masked + 1 end
            if r.cutting then out.cutting = out.cutting + 1 end
        end
        for _, c in ipairs({ f:GetChildren() }) do count(c, out) end
        return out
    end
    for _, hidden in ipairs({ false, true }) do
        t:SetShown(not hidden)
        local on = count(h)
        T.truthy(on.masked > 0 and on.cutting > 0, "angled: masked")
        DaylightUI:Set("Skins", "breathSlant", false)
        local off = count(h)
        T.eq(off.masked, 0, "nothing masked")
        T.eq(off.cutting, 0, "every mask blanked")
        DaylightUI:Set("Skins", "breathSlant", true)
    end
end)

T.test("skins: the breath bar is one of our bars: framed, angled, its label inside, its gradient each time it starts", function()
    local t
    local S = login(function()
        local c = CreateFrame("Frame", "MirrorTimerContainer", UIParent)
        t = CreateFrame("Frame", nil, c)
        t:Hide()                                    -- hidden="true" in the game's template
        t.StatusBar = CreateFrame("StatusBar", nil, t)
        t.Text = t:CreateFontString()
        t.Border = t:CreateTexture(); t.Border:SetTexture("gold frame")
        t.TextBorder = t:CreateTexture(); t.TextBorder:SetTexture("label box")
        t.Setup = function(self, timer, value, maxvalue, paused, label)
            self.timer = timer
            self.StatusBar:SetStatusBarTexture("ui-castingbar-filling-applyingcrafting")
            self.StatusBar:SetMinMaxValues(0, maxvalue / 1000)
            self.StatusBar:SetValue(value / 1000)
            self.Text:SetText(label)
        end
        c.mirrorTimers = { t }
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Style, G = DaylightUI.Style, DaylightUI.Gradients
    local h = S.Breath.holders[t]
    T.truthy(h, "our bar built")
    T.eq(t.Border:GetAlpha(), 0, "the gold frame gone")
    T.eq(t.TextBorder:GetAlpha(), 0, "the label's box gone")
    T.eq(t.StatusBar:GetAlpha(), 0, "the game's bar unseen")
    T.eq(t.Text:GetAlpha(), 0, "and its label")
    T.truthy(Style.GetShell(h), "our border, from the border settings")
    T.eq(Style.GetSlant(h).side, "right", "angled like the other bars")
    T.truthy(Style.GetFillMask(h.bar), "the fill's edge angled too")
    -- The border goes around the fill, never into it. The default 8 px at a small
    -- scale covered a fixed 16 px bar entirely, so it showed black.
    local Pixel = DaylightUI.Pixel
    local B = Pixel.Px(h, Style.BorderPx(h))
    T.truthy(B > 0, "a border")
    T.near(h:GetHeight() - 2 * B, Pixel.Snap(h, S.Breath.HEIGHT), 0.01, "the fill keeps its own height inside the border")
    t:Setup("BREATH", 30000, 60000, 0, "Breath")
    t:Show()                                            -- the game's UpdateShownState
    T.eq(h.text:GetText(), "Breath", "the label inside ours, as it shows")
    local _, hi = h.bar:GetMinMaxValues()
    T.eq(hi, 60, "the game's range copied")
    T.eq(h.bar:GetValue(), 30, "and its value")
    t.StatusBar:SetValue(29)
    stub.RunOnUpdate(h, 0.016)                          -- the next frame
    T.eq(h.bar:GetValue(), 29, "following it as it runs down")
    local g = h.bar:GetStatusBarTexture().__gradient
    T.truthy(g, "a gradient")
    T.eq(g[2], (G.Colors("TIMER_BREATH")), "breath's pair")
    t:Setup("EXHAUSTION", 60000, 60000, 0, "Fatigue")
    stub.RunOnUpdate(h, 0.016)
    T.eq(h.bar:GetStatusBarTexture().__gradient[2], (G.Colors("TIMER_EXHAUSTION")), "fatigue's pair")
    T.eq(h.text:GetText(), "Fatigue")
    for _, m in ipairs({ "SetMinMaxValues", "SetValue" }) do
        T.isnil(rawget(t.StatusBar, m), "no hook on the game's bar: " .. m)
    end
end)



T.test("skins: a row gets a soft wash under the mouse; a button its trace", function()
    local btn, row
    login(function()
        local f = window("QuestFrame")
        btn = CreateFrame("Button", "SomeSkinButton", f)
        row = CreateFrame("Button", nil, f)
    end)
    local Kit = stub.skins.Kit
    Kit.Button(btn)
    Kit.Row(row)
    local function wash(b)
        for _, r in ipairs({ b:GetRegions() }) do
            if r.__layer == "HIGHLIGHT" and r.__color and r.__color[4] == Kit.HOVER_WASH then return r end
        end
    end
    T.isnil(wash(btn), "the button: no wash, its trace says it")
    T.truthy(Kit.TraceOf(btn), "the trace")
    T.truthy(wash(row), "the row")
end)

-- ---------------------------------------------------------------------
-- Guild bank search
-- ---------------------------------------------------------------------

local function guildWorld()
    local f = window("GuildBankFrame")
    for c = 1, 7 do
        local col = CreateFrame("Frame", nil, f)
        for b = 1, 14 do
            local btn = CreateFrame("Button", nil, col)
            btn:SetID((c - 1) * 14 + b)
            btn.icon = btn:CreateTexture()
            btn.IconBorder = btn:CreateTexture()
            col["Button" .. b] = btn
        end
        f["Column" .. c] = col
    end
    CreateFrame("EditBox", "GuildItemSearchBox", f)
    _G.GetCurrentGuildBankTab = function() return 1 end
    local links = { [1] = "|Hitem:1|h[Rare Sword]|h", [2] = "|Hitem:2|h[Cloth Robe]|h" }
    _G.GetGuildBankItemLink = function(_, slot) return links[slot] end
    stub.loadedAddOns.Blizzard_GuildBankUI = true
    return f
end

local function guildLogin()
    local f
    stub.Load({ skins = true, before = function()
        world()
        f = guildWorld()
    end })
    stub.RunTimers()
    return f
end

T.test("skins: the quest and gossip skins step aside while our NPC window is on", function()
    stub.Load({ skins = true, before = world })
    stub.RunTimers()
    T.isnil(stub.skins.Kit.ShellOf(QuestFrame), "the parked quest window isn't dressed")
    T.isnil(stub.skins.Kit.ShellOf(GossipFrame))
end)

T.test("skins: guild bank search dims items that don't match, by name", function()
    local f = guildLogin()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local sword, robe = f.Column1.Button1, f.Column1.Button2
    T.eq(sword:GetAlpha(), 1, "nothing typed: full")
    T.eq(robe:GetAlpha(), 1)
    GuildItemSearchBox:SetText("sword")
    T.eq(sword:GetAlpha(), 1, "matches")
    T.eq(robe:GetAlpha(), 0.3, "doesn't")
    GuildItemSearchBox:SetText("")
    T.eq(robe:GetAlpha(), 1, "cleared: back to full")
end)

T.test("skins: guild bank search re-applies as its items change", function()
    local f = guildLogin()
    GuildItemSearchBox:SetText("robe")
    T.eq(f.Column1.Button1:GetAlpha(), 0.3)
    T.eq(f.Column1.Button2:GetAlpha(), 1)
    stub.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
    T.eq(f.Column1.Button1:GetAlpha(), 0.3, "still filtered the same way")
    T.eq(f.Column1.Button2:GetAlpha(), 1)
end)

T.test("skins: guild bank search leaves the slots alone while the search box is empty", function()
    local f = guildLogin()
    local sword = f.Column1.Button1
    local writes = 0
    local set = sword.SetAlpha
    sword.SetAlpha = function(self, a) writes = writes + 1; return set(self, a) end
    stub.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
    T.eq(writes, 0, "nothing typed: no pass over the slots")
    GuildItemSearchBox:SetText("robe")
    T.eq(sword:GetAlpha(), 0.3)
    GuildItemSearchBox:SetText("")
    T.eq(sword:GetAlpha(), 1, "cleared: back to full")
    writes = 0
    stub.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
    T.eq(writes, 0, "and quiet again")
end)

T.test("skins: a game window fades in on open, out of combat only; its Hide stays instant", function()
    local f, map
    login(function()
        f = window("TestFadeWindow"); f:Hide()
        map = window("TestFadeMap"); map:Hide()
    end)
    local Kit = stub.skins.Kit
    Kit.Window(f)
    Kit.Window(map, { noBackground = true })
    local M = DaylightUI.Motion
    f:Show()
    T.truthy(M.FadingIn(f), "fades in")
    f:Hide()
    T.falsy(f:IsShown(), "closes at once")
    stub.combat = true
    f:Show()
    T.falsy(M.FadingIn(f), "no fade in combat")
    stub.combat = false
    map:Show()
    T.falsy(M.FadingIn(map), "a map window keeps the game's own")
end)

-- Closing leaves a fading ghost for every skinned window, except map windows
-- and the names listed in Kit.GHOST.
T.test("skins: a closed window leaves a ghost, except map and opted-out windows", function()
    local a, map, off
    login(function()
        a = window("TestGhostWindow"); a:Hide()
        map = window("TestGhostMap"); map:Hide()
        off = window("TestGhostOptOut"); off:Hide()
    end)
    local Kit = stub.skins.Kit
    local ghosted = {}
    local real = DaylightUI.Motion.Ghost
    DaylightUI.Motion.Ghost = function(frame) ghosted[frame] = true end
    Kit.GHOST.TestGhostOptOut = true
    Kit.Window(a)
    Kit.Window(map, { noBackground = true })
    Kit.Window(off)
    for _, f in ipairs({ a, map, off }) do f:Show(); f:Hide() end
    DaylightUI.Motion.Ghost = real
    Kit.GHOST.TestGhostOptOut = nil
    T.truthy(ghosted[a], "an ordinary window ghosts")
    T.falsy(ghosted[map], "not a map window")
    T.falsy(ghosted[off], "not an opted-out window")
end)

-- The world map and the game menu fade in like any other window. An alpha
-- animation broke them (the map stayed blank, the menu's button art came back),
-- so FadeIn steps their alpha instead.
T.test("skins: the world map and the game menu fade in", function()
    login(function()
        window("WorldMapFrame"):Hide()
        window("GameMenuFrame"):Hide()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, M = stub.skins.Kit, DaylightUI.Motion
    for _, f in ipairs({ WorldMapFrame, GameMenuFrame }) do
        T.truthy(Kit.ShellOf(f), f:GetName() .. " skinned")
        f:Show()
        T.truthy(M.FadingIn(f), f:GetName() .. " fades in")
    end
end)

-- The game's alert frames fade themselves in (SocialToast.xml animIn, played by
-- AlertFrame_ShowNewAlert). The skin's fade set the layering notice to 0, saw the
-- animation move the alpha, assumed someone else owned it and stopped. The
-- notice stayed at 0, shown but invisible.
T.test("skins: the layering notice keeps the game's own fade in and stays at full alpha as it shows", function()
    login(function()
        stub.loadedAddOns.Blizzard_SocialToast = true
        local f = CreateFrame("Button", "ShardTransferImminentFrame", UIParent)
        f.animIn = f:CreateAnimationGroup()
        f.Text = f:CreateFontString("ShardTransferImminentFrameText")
        f.glow = f:CreateTexture("ShardTransferImminentFrameGlowFrame")
        f:Hide()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, M, f = stub.skins.Kit, DaylightUI.Motion, ShardTransferImminentFrame
    T.truthy(Kit.ShellOf(f), "skinned")
    local ghosted = false
    local real = M.Ghost
    M.Ghost = function() ghosted = true end
    f:Show()
    T.falsy(M.FadingIn(f), "no fade of ours on top of the game's")
    T.eq(f:GetAlpha(), 1, "our fade never takes it to 0")
    f:Hide()
    M.Ghost = real
    T.truthy(ghosted, "it still leaves with a ghost: the game just hides it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A friend logging on, using the game's BNet.xml toast. It fades itself like the
-- layering notice, and BNToastMixin grays its last line on every toast with
-- either a color code or SetTextColor (BNet.lua).
T.test("skins: the Battle.net toast wears our look, keeps its icon, and its last line goes tan on every toast", function()
    login(function()
        stub.loadedAddOns.Blizzard_BNet = true
        local f = CreateFrame("Button", "BNToastFrame", UIParent)
        f.animIn = f:CreateAnimationGroup()
        f.IconTexture = f:CreateTexture("BNToastFrameIconTexture")
        f.glow = f:CreateTexture("BNToastFrameGlowFrame")
        f.TopLine = f:CreateFontString("BNToastFrameTopLine")
        f.MiddleLine = f:CreateFontString("BNToastFrameMiddleLine")
        f.BottomLine = f:CreateFontString("BNToastFrameBottomLine")
        f.DoubleLine = f:CreateFontString("BNToastFrameDoubleLine")
        f.TooltipFrame = CreateFrame("Frame", nil, f)
        f.TooltipFrame.Text = f.TooltipFrame:CreateFontString()
        f.CloseButton = CreateFrame("Button", nil, f)
        f:Hide()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, M, f = stub.skins.Kit, DaylightUI.Motion, BNToastFrame
    local INK, SIZE = DaylightUI.Style.INK, DaylightUI.Style.SIZE
    T.truthy(Kit.ShellOf(f), "skinned")
    T.truthy(Kit.ShellOf(f.TooltipFrame), "its broadcast tooltip too")
    T.eq(f.IconTexture:GetAlpha(), 1, "its icon stays")
    T.eq(f.glow:GetAlpha(), 0, "the game's glow goes")
    T.eq(f.TopLine.__font[1], DaylightUI.Style.FontFile(DaylightUI.Style.WINDOW_SLOT), "our font")
    T.eq(f.BottomLine.__font[2], SIZE.small)
    local function tan()
        local r, g, b = f.BottomLine:GetTextColor()
        T.eq(r, INK.LABEL[1]); T.eq(g, INK.LABEL[2]); T.eq(b, INK.LABEL[3])
    end
    -- The online toast is grayed by a color code. In combat the skin's passes wait.
    stub.EnterCombat()
    f.BottomLine:SetText("|cff808080has come online.|r")
    f:Show()
    T.eq(f.BottomLine:GetText(), "has come online.", "the gray code comes off")
    tan()
    T.falsy(M.FadingIn(f), "no fade of ours on top of the game's")
    T.eq(f:GetAlpha(), 1)
    f:Hide()
    -- The offline toast is grayed by SetTextColor.
    f.BottomLine:SetText("has gone offline.")
    f.BottomLine:SetTextColor(0.5, 0.5, 0.5)
    f:Show()
    tan()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game menu's title sits in a dialog header on its top edge
-- (DialogFrameWithHeaderTemplate). Kit.Window finds it there and moves it into
-- the title row under the accent line, like every other window.
T.test("skins: the game menu's header title goes in the title row", function()
    login(function()
        local f = window("GameMenuFrame")
        f.TitleContainer = nil   -- the real menu has none, its title is in the header
        f.Header = CreateFrame("Frame", nil, f)
        f.Header.Text = f.Header:CreateFontString()
        f:Hide()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, title = stub.skins.Kit, GameMenuFrame.Header.Text
    local point, rel, relPoint, x, y = title:GetPoint(1)
    T.eq(point, "TOPLEFT"); T.eq(rel, GameMenuFrame); T.eq(relPoint, "TOPLEFT")
    T.eq(x, Kit.TITLE_X); T.eq(y, -Kit.TITLE_TOP)
    T.eq(title.__font[1], DaylightUI.Style.FONT, "our font")
end)

-- The achievements title sits in its header art's plaque (Header.Title in
-- Blizzard_AchievementUI.xml) and is moved into the title row too.
T.test("skins: the achievements' header title goes in the title row", function()
    login(function()
        local f = window("AchievementFrame")
        f.TitleContainer = nil   -- the real one has none
        f.Header = CreateFrame("Frame", nil, f)
        f.Header.Title = f.Header:CreateFontString()
        f:Hide()
        stub.loadedAddOns.Blizzard_AchievementUI = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, title = stub.skins.Kit, AchievementFrame.Header.Title
    local point, rel, relPoint, x, y = title:GetPoint(1)
    T.eq(point, "TOPLEFT"); T.eq(rel, AchievementFrame); T.eq(relPoint, "TOPLEFT")
    T.eq(x, Kit.TITLE_X); T.eq(y, -Kit.TITLE_TOP)
end)

-- The border is its own frame and fades as a frame. Fading each texture's alpha
-- lost their tint in game (a gradient border went white).
T.test("skins: a ghost is the window's background, with its border a frame of its own", function()
    login()
    local Kit = stub.skins.Kit
    local g = CreateFrame("Frame", nil, UIParent)
    local edge = Kit.GhostDress(g)
    local back, front = Kit.ShellOf(g), Kit.ShellOf(edge)
    T.truthy(back and front, "both in the window look")
    T.eq(edge:GetParent(), g, "the border frame is the ghost's")
    T.truthy(back.bg:IsShown(), "the background")
    T.truthy(back.opts.noBorder, "no border on the background")
    T.eq(back.opts.shadowAlpha, 0, "nor a shadow")
    T.falsy(front.bg:IsShown(), "the border frame has no background")
    T.falsy(front.opts.noBorder)
end)

T.test("skins: the world map drags by its title bar, keeps its spot when the game docks it, right-click puts it back", function()
    local f
    login(function()
        f = window("WorldMapFrame")
        f.BorderFrame = CreateFrame("Frame", nil, f)
        _G.ShowUIPanel = function(p) p:Show() end
        _G.UpdateUIPanelPositions = function() end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local MapMove = stub.skins.MapMove
    local bar = MapMove.bar
    T.truthy(bar, "a strip over the title bar")
    T.eq(bar:GetParent(), f)
    local db = DaylightUI.DB.Active().modules.Skins
    -- The game docks it on the left, then it's dragged from there.
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Show()
    bar:GetScript("OnDragStart")(bar, "LeftButton")
    T.truthy(f.__moving, "the map moves")
    f.__center = { 600, 500 }
    bar:GetScript("OnDragStop")(bar)
    T.falsy(f.__moving)
    local x, y = DaylightUI.Pixel.Snap(UIParent, 410), DaylightUI.Pixel.Snap(UIParent, 720)
    T.eq(db.mapSpot[1], x, "its left edge saved, on a whole pixel")
    T.eq(db.mapSpot[2], y, "its top edge saved")
    -- The game lays its windows out again, and it goes back to the saved spot.
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    UpdateUIPanelPositions(f)
    local p, rel, rp, px, py = f:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, UIParent); T.eq(rp, "BOTTOMLEFT"); T.eq(px, x); T.eq(py, y)
    -- Maximized, the game owns the position.
    f.isMaximized = true
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, 0)
    UpdateUIPanelPositions(f)
    T.eq(f:GetPoint(1), "TOP", "left where the game put it")
    bar:GetScript("OnDragStart")(bar, "LeftButton")
    T.falsy(f.__moving, "and won't drag")
    f.isMaximized = false
    -- Right-click forgets the spot, so the game's is used from then on.
    bar:GetScript("OnMouseUp")(bar, "RightButton")
    T.isnil(db.mapSpot)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    UpdateUIPanelPositions(f)
    T.eq(f:GetPoint(1), "TOPLEFT")
    T.eq(select(3, f:GetPoint(1)), "TOPLEFT", "the game's spot kept")
    -- /dui reset forgets it too.
    db.mapSpot = { 100, 600 }
    DaylightUI.Movers.ResetAll()
    T.isnil(db.mapSpot)
end)

T.test("skins: a damaged world map spot (a bad import) is left alone, not an error", function()
    local f
    login(function()
        f = window("WorldMapFrame")
        f.BorderFrame = CreateFrame("Frame", nil, f)
        _G.ShowUIPanel = function(p) p:Show() end
        _G.UpdateUIPanelPositions = function() end
    end)
    DaylightUI.DB.Active().modules.Skins.mapSpot = { "x", {} }
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Show()
    T.noerror(function() stub.skins.MapMove.Apply() end)
    T.eq(select(3, f:GetPoint(1)), "TOPLEFT", "the game's spot kept")
    T.noerror(function() stub.skins.MapMove.grip:GetScript("OnMouseDown")(stub.skins.MapMove.grip, "LeftButton") end)
end)

-- The map's top in one slim row (MapMove.Slim). The game's two rows (title, then
-- zone buttons) take 67 px over the map. Skinned and windowed, the zone buttons
-- move up into the title row and the window shrinks by the difference while the
-- map keeps its size. Maximized, the map fills the freed row instead.
local function mapWithTop()
    local f = window("WorldMapFrame")
    f.BorderFrame = CreateFrame("Frame", nil, f)
    f.BorderFrame.TitleContainer = CreateFrame("Frame", nil, f.BorderFrame)
    f.BorderFrame.TitleContainer.TitleText = f.BorderFrame.TitleContainer:CreateFontString()
    f.BorderFrame.MaximizeMinimizeFrame = CreateFrame("Frame", nil, f.BorderFrame)
    -- The game's layout (Blizzard_WorldMap.xml, WorldMapMixin; Camelot's
    -- NAVBAR_X_OFFSET).
    _G.WorldMapConstants = { NAVBAR_X_OFFSET = -50 }
    f.minimizedWidth, f.minimizedHeight, f.questLogWidth = 702, 534, 333
    f:SetSize(702 + 333, 534)
    local spacer = CreateFrame("Frame", nil, f)
    f.TitleCanvasSpacerFrame = spacer
    spacer:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
    spacer:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -3 - 333, -67)
    f.ScrollContainer = CreateFrame("ScrollFrame", nil, f)
    f.ScrollContainer:SetPoint("TOPLEFT", spacer, "BOTTOMLEFT", 0, 0)
    f.ScrollContainer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
    f.ScrollContainer:SetPoint("RIGHT", spacer)
    f.NavBar = CreateFrame("Frame", nil, f)
    f.NavBar:SetPoint("TOPLEFT", spacer, "TOPLEFT", 64, -25)
    f.NavBar:SetPoint("BOTTOMRIGHT", spacer, "BOTTOMRIGHT", -50, 9)
    f.QuestLog = CreateFrame("Frame", nil, f)
    _G.ShowUIPanel = function(p) p:Show() end
    _G.UpdateUIPanelPositions = function() end
    return f
end

-- The anchor the client would hold for a point. SetPoint replaces the one with
-- the same name; the fake game keeps them all, so the last one counts.
local function anchor(frame, point)
    local found
    for i = 1, frame:GetNumPoints() do
        local p = { frame:GetPoint(i) }
        if p[1] == point then found = p end
    end
    return found
end

T.test("skins: the map's top is one slim row, the zone buttons in the title row, maximized too", function()
    local f
    login(function() f = mapWithTop() end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local MapMove = stub.skins.MapMove
    f:Show()
    stub.RunTimers()
    local cut = MapMove.TOP - MapMove.SLIM
    T.truthy(cut > 20, "a real row's worth")
    T.eq(f:GetHeight(), 534 - cut, "the window loses the second row")
    local sc = anchor(f.ScrollContainer, "TOPLEFT")
    T.eq(sc[2], f.TitleCanvasSpacerFrame); T.eq(sc[3], "BOTTOMLEFT")
    T.eq(sc[5], cut, "the map moves up by as much: its own size kept")
    local tl = anchor(f.NavBar, "TOPLEFT")
    T.eq(tl[2], f.TitleCanvasSpacerFrame); T.eq(tl[5], -MapMove.NAV_Y, "the zone buttons in the top row")
    local br = anchor(f.NavBar, "BOTTOMRIGHT")
    T.eq(br[3], "TOPRIGHT"); T.eq(br[4], -50, "ends where the game ends it, beside the quest log")
    T.eq(br[5], -(MapMove.NAV_Y + MapMove.NAV_H))
    T.eq(f.BorderFrame.TitleContainer:GetAlpha(), 0, "the title makes room")
    -- The drag strip lies under the zone buttons, so they keep their clicks and
    -- the empty part of the row drags.
    T.eq(MapMove.bar:GetFrameStrata(), f.NavBar:GetFrameStrata())
    T.eq(MapMove.bar:GetFrameLevel(), f.NavBar:GetFrameLevel())
    T.eq(MapMove.bar:GetHeight(), MapMove.SLIM)
    -- Without the quest log the buttons stop short of maximize and close.
    f.QuestLog:Hide()
    MapMove.Apply()
    T.eq(anchor(f.NavBar, "BOTTOMRIGHT")[4], -50 - MapMove.BUTTONS)
    f.QuestLog:Show()
    MapMove.Apply()
    -- Maximized (the event comes first, then the game's own size and anchor).
    f.isMaximized = true
    MapMove.Apply()
    f:SetSize(1500, 900)
    f.NavBar:SetPoint("TOPLEFT", f.TitleCanvasSpacerFrame, "TOPLEFT", 8, -25)
    MapMove.Apply()
    -- The game's maximized size with the slim top. The map grows into the row the
    -- title gave up. With the quest list beside it, the window widens by the list
    -- (mapLogBeside) and the map keeps its size.
    local pw, ph = f:GetParent():GetSize()
    local full = (ph - MapMove.SLIM) * 702 / (534 - MapMove.TOP)
    local w = math.min(pw - 30, full + 333)
    T.eq(f:GetWidth(), math.floor(w))
    T.eq(f:GetHeight(), math.floor((ph - MapMove.SLIM) * ((w - 333) / full) + MapMove.SLIM))
    if full + 333 <= pw - 30 then
        T.eq(f:GetHeight(), math.floor(ph), "room for both: the map as big as with no list")
    end
    f.QuestLog:Hide()
    MapMove.Apply()
    local w0 = math.min(pw - 30, full)
    T.eq(f:GetWidth(), math.floor(w0), "the list closed: the window narrows back")
    DaylightUI:Set("Skins", "mapLogBeside", false)
    stub.RunTimers()
    f.QuestLog:Show()
    MapMove.Apply()
    T.eq(f:GetWidth(), math.floor(w0), "switched off: the game's way, the list takes its room out of the map")
    DaylightUI:Set("Skins", "mapLogBeside", true)
    stub.RunTimers()
    MapMove.Apply()
    T.eq(anchor(f.ScrollContainer, "TOPLEFT")[5], cut, "one row big too")
    T.eq(anchor(f.NavBar, "TOPLEFT")[5], -MapMove.NAV_Y)
    T.eq(f.BorderFrame.TitleContainer:GetAlpha(), 0, "no title over the accent line")
    T.eq(MapMove.bar:GetHeight(), MapMove.SLIM)
    -- Back to small, the game sets its size and anchor again, then the skin does.
    f.isMaximized = false
    f:SetSize(702 + 333, 534)
    f.NavBar:SetPoint("TOPLEFT", f.TitleCanvasSpacerFrame, "TOPLEFT", 64, -25)
    MapMove.Apply()
    T.eq(f:GetHeight(), 534 - cut)
    T.eq(anchor(f.NavBar, "TOPLEFT")[5], -MapMove.NAV_Y)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The top row's buttons (zone arrows, filter, maximize) have no boxes, just the
-- chevron. The filter's red "changed" badge is added by the skin.
T.test("skins: the map's top row buttons are bare chevrons, the filters badge a small X in the accent", function()
    local f, arrow, filter
    login(function()
        f = mapWithTop()
        local home = CreateFrame("Button", nil, f.NavBar)
        home.text = home:CreateFontString()
        arrow = CreateFrame("Button", nil, home)
        home.MenuArrowButton = arrow
        f.NavBar.homeButton = home
        local mm = f.BorderFrame.MaximizeMinimizeFrame
        mm.MaximizeButton = CreateFrame("Button", nil, mm)
        mm.MinimizeButton = CreateFrame("Button", nil, mm)
        filter = CreateFrame("DropdownButton", nil, f)
        filter:SetSize(32, 32)
        filter.Icon = filter:CreateTexture()
        filter.Icon:SetAtlas("common-dropdown-a-button")
        filter.ResetButton = CreateFrame("Button", nil, filter)
        local red = filter.ResetButton:CreateTexture()
        function filter.ResetButton:GetNormalTexture() return red end
        filter.ResetButton.red = red
        f.WorldMapTrackingOptionsButton = filter
        f.overlayFrames = { f.NavBar, filter }
    end)
    f:Show()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    for name, b in pairs({ arrow = arrow, filter = filter,
                           maximize = f.BorderFrame.MaximizeMinimizeFrame.MaximizeButton }) do
        T.isnil(Kit.ShellOf(b), name .. ": no box")
        local chevrons = 0
        for _, r in ipairs({ b:GetRegions() }) do
            if r.GetTexture and type(r:GetTexture()) == "string" and r:GetTexture():find("ui%-chevron") then chevrons = chevrons + 1 end
        end
        T.eq(chevrons, 1, name .. ": our chevron")
    end
    T.eq(filter.Icon:GetAlpha(), 0, "the game's arrow art gone")
    T.eq(filter.ResetButton.red:GetAlpha(), 0, "the red badge gone")
    local x
    for _, r in ipairs({ filter.ResetButton:GetRegions() }) do
        if r.GetTexture and type(r:GetTexture()) == "string" and r:GetTexture():find("ui%-close") then x = r end
    end
    T.truthy(x, "a small X of ours instead")
end)

T.test("skins: the map's top stays the game's when the map isn't skinned", function()
    local f
    login(function()
        _G.DaylightUIDB = { modules = { Skins = { packs = { system = false } } } }
        f = mapWithTop()
    end)
    f:Show()
    stub.RunTimers()
    T.eq(f:GetHeight(), 534)
    T.eq(anchor(f.ScrollContainer, "TOPLEFT")[5], 0)
end)

-- The world map's unexplored areas (MapReveal.lua). The game's own map pieces
-- (MapRevealData) minus the ones the client says are explored, drawn the game's
-- way on an addon frame over the canvas.
T.test("skins: unexplored areas show dimmed on the map, from the game's pieces less the explored ones", function()
    local f
    login(function()
        f = window("WorldMapFrame")
        f.ScrollContainer = CreateFrame("ScrollFrame", nil, f)
        f.ScrollContainer.Child = CreateFrame("Frame", nil, f.ScrollContainer)
        f.mapID = 1411   -- Durotar
        f.pinFrameLevelsManager = { definitions = { PIN_FRAME_LEVEL_MAP_EXPLORATION = { startLevel = 2002 } } }
        -- Its first piece explored (C_MapExplorationInfo's shape).
        _G.C_MapExplorationInfo = { GetExploredMapTextures = function(id)
            if id == 1411 then return { { textureWidth = 256, textureHeight = 256, offsetX = 427, offsetY = 78, fileDataIDs = { 8073637 } } } end
            return {}
        end }
        _G.C_Map = _G.C_Map or {}
        C_Map.GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256 } } end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local R = stub.skins.MapReveal
    f:Show()
    T.eq(R.frame:IsShown(), false, "off by default: nothing drawn, nothing polled")
    DaylightUI:Set("Skins", "mapReveal", true)
    stub.RunTimers()
    T.eq(R.frame:IsShown(), true)
    T.eq(R.frame:GetParent(), f.ScrollContainer.Child, "over the map's canvas")
    T.eq(R.frame:GetFrameLevel(), 2002, "at the game's exploration level")
    -- Every Durotar tile but the explored piece's one.
    local want = 0
    for _, piece in ipairs(stub.skins.MapRevealData[1411]) do
        local w, h, x, y, ids = piece:match("^(%d+):(%d+):(%d+):(%d+):(.+)$")
        if not (x == "427" and y == "78") then for _ in ids:gmatch("%d+") do want = want + 1 end end
    end
    local shown, first = 0, nil
    for _, r in ipairs({ R.frame:GetRegions() }) do
        if r:IsShown() then shown = shown + 1; first = first or r end
    end
    T.eq(shown, want)
    T.truthy(want > 0)
    local cr = first:GetVertexColor()
    T.near(cr, 0.6, 0.001, "dimmed")
    -- A piece 512 wide: two full tiles side by side at its offset.
    local p, rel, rp, x, y = first:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, R.frame)
    -- Another map is redrawn for it, since its id is read each frame.
    f.mapID = 947        -- Azeroth: no pieces
    stub.RunOnUpdate(R.frame)
    shown = 0
    for _, r in ipairs({ R.frame:GetRegions() }) do if r:IsShown() then shown = shown + 1 end end
    T.eq(shown, 0)
    DaylightUI:Set("Skins", "mapReveal", false)
    stub.RunTimers()
    T.eq(R.frame:IsShown(), false)
end)

-- The world map's pins (MapPins.lua). Entrances and flight masters placed by the
-- client, plus the addon's boats and zeppelins. Pins on the same spot merge into
-- one, and pins keep their size as the map zooms.
T.test("skins: world map pins show entrances, your flight masters and boats, merged on one spot", function()
    local f
    login(function()
        f = window("WorldMapFrame")
        f.ScrollContainer = CreateFrame("ScrollFrame", nil, f)
        f.ScrollContainer.Child = CreateFrame("Frame", nil, f.ScrollContainer)
        f.ScrollContainer.Child:SetSize(1000, 700)
        f.mapID = 1434   -- Stranglethorn Vale
        f.pinFrameLevelsManager = { definitions = { PIN_FRAME_LEVEL_DUNGEON_ENTRANCE = { startLevel = 2100 } } }
        _G.C_Map = _G.C_Map or {}
        C_Map.GetMapInfo = function(id)
            if id == 1434 then return { mapType = 3, name = "Stranglethorn Vale" } end
            if id == 1413 then return { mapType = 3, name = "The Barrens" } end
            if id == 1458 then return { mapType = 3, name = "Undercity" } end
            if id == 1454 then return { mapType = 3, name = "Orgrimmar" } end
            if id == 947 then return { mapType = 1, name = "Azeroth" } end
        end
        -- The client's answer: world x/y straight to a spot, only on Stranglethorn.
        _G.CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
        C_Map.GetMapPosFromWorldPos = function(cont, v, id)
            local x, y = v:GetXY()
            local spots = {
                ["-11916.1"] = { 0.53, 0.17 },     -- Zul'Gurub
                ["-14271.8"] = { 0.27, 0.77 },     -- Booty Bay, neutral flight (side 0: left out)
                ["-14444.3"] = { 0.27, 0.78 },     -- Booty Bay, Horde
                ["-14473"] = { 0.28, 0.79 },       -- Booty Bay, Alliance
                ["-12414.2"] = { 0.32, 0.29 },     -- Grom'gol, Horde
                ["-14278"] = { 0.26, 0.73 },       -- Booty Bay's boat
                ["-12464"] = { 0.314, 0.303 },     -- Grom'gol's zeppelin to Orgrimmar
                ["-12407"] = { 0.315, 0.291 },     -- and to Undercity
            }
            local s = id == 1434 and cont == 0 and spots[tostring(x)]
            if s then return id, { GetXY = function() return s[1], s[2] end } end
        end
        -- The game names a boat's destination by its area. Undercity is left
        -- unanswered so the addon's English name is used.
        C_Map.GetAreaInfo = function(id) if id == 1637 then return "Orgrimmar" end end
        stub.SetUnits({ player = { faction = "Horde" } })
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local P = stub.skins.MapPins
    f:Show()
    T.eq(P.frame:IsShown(), true, "on by default")
    T.eq(P.frame:GetFrameLevel(), 2100, "at the game's dungeon entrance level")
    local function shown()
        local out = {}
        for _, b in ipairs({ P.frame:GetChildren() }) do
            if b:IsShown() and b.pin then out[#out + 1] = b end
        end
        return out
    end
    local kinds = {}
    for _, b in ipairs(shown()) do kinds[b.pin.kind] = (kinds[b.pin.kind] or 0) + 1 end
    T.eq(kinds.raid, 1, "Zul'Gurub")
    T.eq(kinds.flight, 2, "Booty Bay and Grom'gol for the Horde, not the Alliance one")
    T.eq(kinds.zeppelin, 1, "Grom'gol's two zeppelins are one pin")
    T.eq(kinds.boat, 1, "Booty Bay to Ratchet")
    for _, b in ipairs(shown()) do
        if b.pin.kind == "zeppelin" then
            T.eq(#b.pin.lines, 2)
            T.eq(b.pin.lines[1][1], "Zeppelin to Orgrimmar")
            T.eq(b.pin.lines[2][1], "Zeppelin to Undercity")
        end
        if b.pin.kind == "boat" then T.eq(b.pin.lines[1][1], "Boat to Ratchet") end
        if b.pin.kind == "raid" then
            local p, rel, rp, x, y = b:GetPoint(1)
            T.eq(rel, P.frame); T.eq(rp, "TOPLEFT")
            T.near(x, 530, 0.01); T.near(y, -119, 0.01)
            local r, g = b.icon:GetVertexColor()
            T.eq(r, 1, "the raid icon wears its own colors")
        end
        if b.pin.kind == "flight" then
            local r = b.icon:GetVertexColor()
            T.eq(r, P.Color(b.pin)[1], "flight boots tinted by faction")
            T.truthy(r < 1, "not left white")
        end
    end
    -- Zoomed in 2x, pins are at half scale on the same canvas spot.
    f.ScrollContainer.Child:SetScale(2)
    stub.RunOnUpdate(P.frame)
    for _, b in ipairs(shown()) do
        T.eq(b:GetScale(), 0.5)
        if b.pin.kind == "raid" then
            local _, _, _, x, y = b:GetPoint(1)
            T.near(x, 1060, 0.01)
        end
    end
    -- The other faction's flight masters, and the symbols' size and opacity.
    DaylightUI:Set("Skins", "mapFlightsAll", true)
    DaylightUI:Set("Skins", "mapPinScale", 1.5)
    DaylightUI:Set("Skins", "mapPinAlpha", 0.5)
    stub.RunTimers()
    kinds = {}
    for _, b in ipairs(shown()) do
        kinds[b.pin.kind] = (kinds[b.pin.kind] or 0) + 1
        T.eq(b.icon:GetWidth(), P.SIZE * 1.5)
        T.eq(b:GetWidth(), P.SIZE * 1.5, "the hover area grows with it")
    end
    T.eq(kinds.flight, 3, "the Alliance one too")
    T.eq(P.Alpha(), 0.5)
    DaylightUI:Set("Skins", "mapFlightsAll", false)
    DaylightUI:Set("Skins", "mapPinScale", 1)
    DaylightUI:Set("Skins", "mapPinAlpha", 1)
    -- Turning a switch off removes those pins.
    DaylightUI:Set("Skins", "mapFlights", false)
    stub.RunTimers()
    kinds = {}
    for _, b in ipairs(shown()) do kinds[b.pin.kind] = true end
    T.isnil(kinds.flight)
    T.truthy(kinds.raid)
    -- No pins on a map that isn't a zone.
    f.mapID = 947
    stub.RunOnUpdate(P.frame)
    T.eq(#shown(), 0)
    -- Forever's new dungeons have no corpse point. The addon's own list puts
    -- Excavation Site on the Wetlands, using the game's name when it has one.
    local info = C_Map.GetMapInfo
    C_Map.GetMapInfo = function(id)
        if id == 1437 then return { mapType = 3, name = "Wetlands" } end
        return info(id)
    end
    f.mapID = 1437
    stub.RunOnUpdate(P.frame)
    local got = {}
    for _, b in ipairs(shown()) do
        if b.pin.family == "instance" then got[#got + 1] = b end
    end
    T.eq(#got, 1, "Excavation Site's entrance (Menethil's boats aside)")
    T.eq(got[1].pin.kind, "dungeon")
    T.eq(got[1].pin.lines[1][1], "Excavation Site: Wetlands")
    T.near(got[1].pin.x, 0.534, 0.0001)
    -- With every switch off the pins are hidden and nothing is polled.
    DaylightUI:Set("Skins", "mapDungeons", false)
    DaylightUI:Set("Skins", "mapTravel", false)
    stub.RunTimers()
    T.eq(P.frame:IsShown(), false)
end)

T.test("skins: the world map's corner grip scales it from its top-left, kept; maximized it's the game's size", function()
    local f
    login(function()
        f = window("WorldMapFrame")
        f.BorderFrame = CreateFrame("Frame", nil, f)
        _G.ShowUIPanel = function(p) p:Show() end
        _G.UpdateUIPanelPositions = function() end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local MapMove = stub.skins.MapMove
    local grip = MapMove.grip
    T.truthy(grip, "a grip in the corner")
    -- The quest journal covers that corner (strata HIGH, level 500), so the grip
    -- must sit above it or it can't be seen or grabbed.
    T.eq(grip:GetFrameStrata(), "HIGH")
    T.truthy(grip:GetFrameLevel() > 500, "above the journal")
    local db = DaylightUI.DB.Active().modules.Skins
    f:SetSize(700, 500)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f.__center = { 366, 450 }
    f:Show()
    stub.cursorPos = { 716, 200 }   -- on the grip, the map's right edge
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    T.truthy(db.mapSpot, "its spot saved first: from here we place it")
    stub.cursorPos = { 506, 200 }   -- 210 px in: 490 wide of 700
    MapMove.SizeStep()
    T.near(f:GetScale(), 0.7, 0.011)
    stub.cursorPos = { 2000, 200 }
    MapMove.SizeStep()
    T.eq(f:GetScale(), MapMove.MAX, "no bigger than the most")
    stub.cursorPos = { 506, 200 }
    grip:GetScript("OnMouseUp")(grip, "LeftButton")
    T.eq(db.mapScale, 0.7, "kept")
    T.falsy(grip:GetScript("OnUpdate"), "the drag ends")
    -- Maximized uses the game's size and has no grip. Back to small, the saved size returns.
    f.isMaximized = true
    MapMove.Apply()
    T.eq(f:GetScale(), 1)
    T.eq(grip:IsShown(), false)
    f.isMaximized = false
    MapMove.Apply()
    T.eq(f:GetScale(), 0.7)
    -- Right-click on the title bar restores the game's spot and size.
    MapMove.bar:GetScript("OnMouseUp")(MapMove.bar, "RightButton")
    T.isnil(db.mapScale)
    T.eq(f:GetScale(), 1)
end)

-- The friends window as this client rebuilt it (Blizzard_SocialUI): one window
-- with pooled icon tabs down its side, a Battle.net bar, pages built in Lua, and
-- friends as "cards" in a scrolling list.
local function socialWindow()
    local f = window("SocialUIFrame")
    f.TopFade, f.BottomFade = f:CreateTexture(), f:CreateTexture()
    f.BattleNetBar = CreateFrame("Frame", nil, f)
    f.BattleNetBar.Background = f.BattleNetBar:CreateTexture()
    local tab = CreateFrame("Button", nil, f)
    tab.Background, tab.Icon, tab.SelectedTexture = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
    f.socialTabPool = { EnumerateActive = function() return pairs({ [tab] = true }) end }
    local page = CreateFrame("Frame", nil, f)
    f.FriendsList = page
    page.ActionButton = button(nil, page)
    page.FilterBar = CreateFrame("Frame", nil, page)
    local search = CreateFrame("EditBox", nil, page.FilterBar)
    search.Background, search.searchIcon = search:CreateTexture(), search:CreateTexture()
    page.FilterBar.SearchBar = search
    page.ScrollBox = list(page)
    local card = CreateFrame("Button", nil, page.ScrollBox)
    card.Background = card:CreateTexture()
    card.PresenceHolder = CreateFrame("Frame", nil, card)
    card.TextHolder = CreateFrame("Frame", nil, card)
    card.PartyButton = CreateFrame("Button", nil, card)
    card.PartyButton.ActionIcon = card.PartyButton:CreateTexture()
    local normal = card.PartyButton:CreateTexture()
    function card.PartyButton:GetNormalTexture() return normal end
    page.ScrollBox.rows = rows(card)
    return f, tab, card
end

T.test("skins: the rebuilt friends window: our window, its side tabs, friend cards as rows", function()
    local f, tab, card
    login(function()
        f, tab, card = socialWindow()
        stub.loadedAddOns.Blizzard_SocialUI = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(f), "our window")
    T.eq(f.TopFade:GetAlpha(), 0, "the game's fades gone")
    T.eq(f.BottomFade:GetAlpha(), 0)
    T.eq(f.BattleNetBar.Background:GetAlpha(), 0, "the Battle.net bar's art gone")
    T.eq(tab.Background:GetAlpha(), 0, "the side tab's art gone")
    T.eq(tab.Icon:GetAlpha(), 1, "its icon kept")
    T.truthy(Kit.ShellOf(tab), "the side tab look")
    local ts = Kit.ShellOf(tab)
    T.truthy(ts.host == tab or DaylightUI.Style.GetShell(tab) == ts, "the whole tab outlined, against the window (no gap to the icon)")
    local search = f.FriendsList.FilterBar.SearchBar
    T.eq(search.Background:GetAlpha(), 0, "the search box's own black art gone")
    T.truthy(Kit.InputOf(search), "the input look")
    T.truthy(Kit.ButtonOf(f.FriendsList.ActionButton), "Add New Friend, flat")
    T.eq(card.Background:GetAlpha(), 0, "the card's art gone")
    T.truthy(Kit.ShellOf(card), "the row look")
    T.eq(card.PartyButton:GetNormalTexture():GetAlpha(), 0, "the invite button's art gone")
    T.truthy(Kit.ShellOf(card.PartyButton), "an icon button like ours")
    -- When the list adds more friends they're styled the frame after.
    local more = CreateFrame("Button", nil, f.FriendsList.ScrollBox)
    more.Background = more:CreateTexture()
    more.PresenceHolder = CreateFrame("Frame", nil, more)
    more.TextHolder = CreateFrame("Frame", nil, more)
    function more:GetElementData() return {} end
    table.insert(f.FriendsList.ScrollBox.rows, more)
    f.FriendsList.ScrollBox:Update()
    stub.RunTimers()
    T.eq(more.Background:GetAlpha(), 0, "a new card dressed too")
    T.truthy(Kit.ShellOf(more))
end)

-- The guild window (Blizzard_Communities, CommunitiesFrame.xml). Icon tabs down
-- its right side (RightSideTabTemplate), guilds and communities as cards on the
-- left, the roster rows, info and news, and the member card.
local function guildWindow()
    local f = window("CommunitiesFrame")
    local tab = CreateFrame("CheckButton", nil, f)
    tab.Icon, tab.IconOverlay = tab:CreateTexture(), tab:CreateTexture()
    tab.art = tab:CreateTexture()
    f.RosterTab = tab
    local clubs = CreateFrame("Frame", nil, f)
    f.CommunitiesList = clubs
    clubs.Bg, clubs.TopFiligree = clubs:CreateTexture(), clubs:CreateTexture()
    clubs.FilligreeOverlay = CreateFrame("Frame", nil, clubs)
    clubs.FilligreeOverlay.TLCorner = clubs.FilligreeOverlay:CreateTexture()
    clubs.InsetFrame = CreateFrame("Frame", nil, clubs)
    clubs.InsetFrame:SetFrameLevel(200)   -- CommunitiesList.xml: over the cards, a border
    clubs.ScrollBox = list(clubs)
    local card = CreateFrame("Button", nil, clubs.ScrollBox)
    for _, k in ipairs({ "Background", "Selection", "Icon", "GuildTabardEmblem", "GuildTabardBorder", "IconRing", "NewCommunityFlash" }) do
        card[k] = card:CreateTexture()
    end
    card.Selection:Hide()
    clubs.ScrollBox.rows = rows(card)
    local members = CreateFrame("Frame", nil, f)
    f.MemberList = members
    members.Background = members:CreateTexture()
    members.InsetFrame = CreateFrame("Frame", nil, members)
    members.InsetFrame:SetFrameLevel(100)   -- CommunitiesMemberList.xml: over the rows, a border
    members.ScrollBox = list(members)
    local row = CreateFrame("Button", nil, members.ScrollBox)
    row.NameFrame = CreateFrame("Frame", nil, row)
    row.Class = row:CreateTexture()
    local normal = row:CreateTexture()
    function row:GetNormalTexture() return normal end
    members.ScrollBox.rows = rows(row)
    local details = CreateFrame("Frame", nil, f)
    f.GuildDetailsFrame = details
    details.Info = CreateFrame("Frame", nil, details)
    details.Info.Header1 = details.Info:CreateTexture()
    local challenge = CreateFrame("Frame", nil, details.Info)
    challenge.BG, challenge.check = challenge:CreateTexture(), challenge:CreateTexture()
    details.Info.Challenges = { challenge }
    details.News = CreateFrame("Frame", nil, details)
    local memberCard = CreateFrame("Frame", nil, f)
    f.GuildMemberDetailFrame = memberCard
    memberCard.Border = CreateFrame("Frame", nil, memberCard)
    memberCard.NoteBackground = CreateFrame("Frame", nil, memberCard)
    -- The guild log (GuildInfo.xml). Its X and its "Close" text button are both
    -- $parentCloseButton with no key, and the text button, made last, holds the name.
    local log = CreateFrame("Frame", "CommunitiesGuildLogFrame", UIParent)
    log:SetSize(384, 432)
    log.Bg = log:CreateTexture()
    log.Container = CreateFrame("Frame", nil, log)
    local x = CreateFrame("Button", "CommunitiesGuildLogFrameCloseButton", log)
    x:SetSize(24, 24)
    local xArt = x:CreateTexture()
    function x:GetNormalTexture() return xArt end
    local text = button("CommunitiesGuildLogFrameCloseButton", log)
    text:SetSize(96, 22)
    log.x, log.text = x, text
    return f, tab, card, row, log
end

T.test("skins: the guild window: its side tabs, guild cards and roster rows ours, the game's layout kept", function()
    local f, tab, card, row, log
    login(function()
        f, tab, card, row, log = guildWindow()
        stub.loadedAddOns.Blizzard_Communities = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(f), "our window")
    T.truthy(Kit.ShellOf(tab), "the side tab look")
    local ts = Kit.ShellOf(tab)
    T.truthy(ts.host == tab or DaylightUI.Style.GetShell(tab) == ts, "the whole tab, against the window's edge (no outline floating round the icon)")
    T.eq(tab.Icon:GetAlpha(), 1, "its icon kept")
    T.eq(tab.art:GetAlpha(), 0, "the spellbook tab art gone")
    local list = f.CommunitiesList
    T.eq(list.Bg:GetAlpha(), 0, "the list's parchment gone")
    T.eq(list.FilligreeOverlay.TLCorner:GetAlpha(), 0, "its filigree gone")
    T.truthy(Kit.RowOf(card).line, "a guild card is a line of ours")
    T.falsy(Kit.ShellOf(card), "no box on it")
    T.eq(card.Background:GetAlpha(), 0, "the blue card art gone")
    T.eq(card.IconRing:GetAlpha(), 0, "the gold ring gone")
    T.eq(card.GuildTabardEmblem:GetAlpha(), 1, "the guild's banner kept")
    T.eq(card.Icon:GetAlpha(), 1, "the community's icon kept")
    T.eq(f.MemberList.Background:GetAlpha(), 0, "the roster's marble gone")
    T.truthy(Kit.RowOf(row).line, "a member is a line of ours")
    T.falsy(Kit.ShellOf(row), "no box on it")
    T.eq(row:GetNormalTexture():GetAlpha(), 0, "the game's stripe gone")
    T.eq(row.Class:GetAlpha(), 1, "the class icon kept")
    -- The game keeps these insets over their lists as borders (Bg hidden, high
    -- frame level), so shading the inset itself covered every name.
    local shade = Kit.ShadeOf(f.MemberList.InsetFrame)
    T.truthy(shade, "the roster's inset has its shade")
    T.truthy(shade:GetParent():GetFrameLevel() < row:GetFrameLevel(), "under the members' names, never over them")
    T.eq(shade:GetAlpha(), 1, "and still there after the window is gone over again")
    shade = Kit.ShadeOf(list.InsetFrame)
    T.truthy(shade:GetParent():GetFrameLevel() < card:GetFrameLevel(), "under the guild cards too")
    local details = f.GuildDetailsFrame
    T.eq(details.Info.Header1:GetAlpha(), 0, "the info's header art gone")
    T.eq(details.Info.Challenges[1].BG:GetAlpha(), 0)
    T.eq(details.Info.Challenges[1].check:GetAlpha(), 1, "a challenge's tick kept")
    T.truthy(Kit.ShellOf(f.GuildMemberDetailFrame), "the member card a panel of ours")
    T.eq(f.GuildMemberDetailFrame.Border:GetAlpha(), 0, "its dialog border gone")
    T.truthy(Kit.ShellOf(log), "the guild log our window")
    T.eq(log.x:GetNormalTexture():GetAlpha(), 0, "its X ours")
    T.truthy(Kit.ButtonOf(log.text), "its Close text button a button, not an X")
    -- Once picked, the card's selection shows, painted after the click.
    card.Selection:Show()
    card:GetScript("OnMouseUp")(card, "LeftButton")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(Kit.RowOf(card).fill:GetAlpha(), 1, "the picked card washed in the accent")
    card.Selection:Hide()
    card:GetScript("OnMouseUp")(card, "LeftButton")
    stub.RunTimers()
    T.eq(Kit.RowOf(card).fill:GetAlpha(), 0, "and clear again")
end)

-- The collections journal's lists (Blizzard_MountCollection.xml,
-- Classic/Blizzard_PetCollection.xml, Shared/Blizzard_Wardrobe_Sets.xml). Each
-- row has a gray bar atlas background under its icon and name.
T.test("skins: the collections journal's rows are lines: the game's gray bars gone, the pick read from its art", function()
    local f, mount, set
    login(function()
        f = window("CollectionsJournal")
        local box = list(f)
        box.ScrollTarget = CreateFrame("Frame", nil, box)
        mount = CreateFrame("Button", nil, box.ScrollTarget)
        mount.background, mount.selectedTexture = mount:CreateTexture(), mount:CreateTexture()
        mount.icon = mount:CreateTexture()
        mount.selectedTexture:Hide()
        set = CreateFrame("Button", nil, box.ScrollTarget)
        set.Background, set.SelectedTexture, set.HighlightTexture = set:CreateTexture(), set:CreateTexture(), set:CreateTexture()
        box.rows = { mount, set }
        stub.loadedAddOns.Blizzard_Collections = true
    end)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.eq(mount.background:GetAlpha(), 0, "the gray bar gone")
    T.eq(mount.icon:GetAlpha(), 1, "its icon kept")
    T.truthy(Kit.RowOf(mount).line, "a line of ours")
    T.falsy(Kit.ShellOf(mount), "no box on it")
    T.eq(set.Background:GetAlpha(), 0, "a wardrobe set's too")
    T.eq(set.HighlightTexture:GetAlpha(), 0, "its own hover art gone")
    T.eq(Kit.RowOf(mount).fill:GetAlpha(), 0, "not picked")
    mount.selectedTexture:Show()
    mount:GetScript("OnMouseUp")(mount, "LeftButton")
    stub.RunTimers()
    T.eq(Kit.RowOf(mount).fill:GetAlpha(), 1, "picked: the game's art says so")
end)

-- An icon tab's frame is wider than its icon (the game's tab art filled it).
-- The selected tint and hover wash stay inside the icon's outline instead of
-- covering the whole frame.
T.test("skins: an icon side tab's selected tint and hover wash stay inside its outline", function()
    login()
    local t = CreateFrame("Button", nil, UIParent)
    t.Background, t.Icon, t.SelectedTexture = t:CreateTexture(), t:CreateTexture(), t:CreateTexture()
    stub.skins.Kit.SideTab(t, nil, stub.skins.Kit.SIDE_TAB_CROP)
    local own = { [t.Background] = true, [t.Icon] = true, [t.SelectedTexture] = true }
    local n = 0
    for _, r in ipairs({ t:GetRegions() }) do
        if not own[r] then
            n = n + 1
            local _, rel = r:GetPoint(1)
            T.truthy(rel ~= nil and rel ~= t, "anchored to the outline, not the tab's frame")
        end
    end
    T.truthy(n >= 2, "the tint and the wash")
end)

-- ---------------------------------------------------------------------
-- No work done twice (the redundant-work sweep)
-- ---------------------------------------------------------------------

T.test("skins: an item's outline isn't painted again for the color it already has", function()
    login(function()
        character()
        CharacterHeadSlot.IconBorder:SetVertexColor(0.64, 0.21, 0.93)
        CharacterHeadSlot.IconBorder:Show()
    end)
    local Kit = stub.skins.Kit
    local slot = CharacterHeadSlot
    local s = Kit.ShellOf(slot)
    local paints, paint = 0, Kit.Paint
    Kit.Paint = function(...) paints = paints + 1; return paint(...) end
    -- The game's update shows, colors and textures the ring over and over.
    for _ = 1, 3 do
        SetItemButtonBorder(slot, "x")
        SetItemButtonBorderVertexColor(slot, 0.64, 0.21, 0.93)
    end
    T.eq(paints, 0, "the same color: nothing to paint")
    SetItemButtonBorderVertexColor(slot, 0.12, 0.5, 1)              -- a rare now
    Kit.Paint = paint
    T.eq(paints, 1, "a new color is painted")
    T.eq(s.opts.borderColor[3], 1, "our outline in the new color")
    SetItemButtonBorder(slot)
    T.eq(s.opts.borderColor, Kit.EMPTY_ITEM_BORDER, "empty: dim")
end)

T.test("skins: a row's hover and selected colors aren't made anew on every paint", function()
    login()
    local Kit = stub.skins.Kit
    local row = CreateFrame("Button", nil, UIParent)
    Kit.Row(row)
    local s = Kit.ShellOf(row)
    local enter, leave = row:GetScript("OnEnter"), row:GetScript("OnLeave")
    enter(row)
    local hover = s.opts.borderColor
    T.truthy(hover[1] > Kit.ROW_BORDER[1], "lighter on hover")
    leave(row)
    T.eq(s.opts.borderColor, Kit.ROW_BORDER)
    enter(row)
    T.truthy(rawequal(s.opts.borderColor, hover), "the same hover color, not a new one")
    leave(row)
    -- Selected with the Daylight accent it takes the class color, from one table.
    DaylightUI:Set("general", "accent", "daylight")
    stub.SetUnits({ player = { name = "Ann", class = "MAGE" } })
    local picked = CreateFrame("Button", nil, UIParent)
    local sel = picked:CreateTexture()
    sel:Show()
    Kit.Row(picked, nil, sel)
    local first = Kit.ShellOf(picked).opts.borderColor
    local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
    T.eq(first[1], c.r, "the class color")
    Kit.Row(picked, nil, sel)
    T.truthy(rawequal(Kit.ShellOf(picked).opts.borderColor, first), "the same table on the next paint")
end)

T.test("skins: the quest log's headers are gone over only when the log has new ones", function()
    local qs
    login(function()
        local f = CreateFrame("Frame", "WorldMapFrame", UIParent)
        local qm = CreateFrame("Frame", "QuestMapFrame", f)
        qs = CreateFrame("Frame", "QuestScrollFrame", qm)
        qs.Contents = CreateFrame("Frame", nil, qs)
        _G.QuestLogQuests_Update = function() end
    end)
    local Kit = stub.skins.Kit
    local function header()
        local h = CreateFrame("Button", nil, qs.Contents)
        h.Left, h.Middle, h.Right = h:CreateTexture(), h:CreateTexture(), h:CreateTexture()
        h.ButtonText = h:CreateFontString()
        h.CollapseButton = CreateFrame("Button", nil, h)
        return h
    end
    local first = header()
    QuestLogQuests_Update()
    T.truthy(Kit.ShellOf(first), "a header in our row look")
    local rows, row = 0, Kit.Row
    Kit.Row = function(...) rows = rows + 1; return row(...) end
    for _ = 1, 5 do QuestLogQuests_Update() end
    T.eq(rows, 0, "the same headers: nothing to do")
    local second = header()
    QuestLogQuests_Update()
    Kit.Row = row
    T.truthy(Kit.ShellOf(second), "a new header is done at once")
    T.eq(first.Left:GetAlpha(), 0)
    T.eq(second.Left:GetAlpha(), 0, "its art gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: art the game shows again is erased with a see-through mask, never hooked; no room for a mask: faded", function()
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    local glow = f:CreateTexture()
    Kit.Erase(glow)
    glow:Show(); glow:SetAlpha(1); glow:SetAtlas("spellbook-item-backplate")   -- the game fades it in
    T.truthy(Kit.Erased(glow), "masked")
    T.eq(glow.__masks[1].__texture, Kit.ERASE, "by the see-through mask")
    local second = f:CreateTexture()
    Kit.Erase(second)
    T.eq(second.__masks[1], glow.__masks[1], "one mask per frame, shared")
    Kit.Erase(glow)
    T.eq(#glow.__masks, 1, "erased once")
    local full = f:CreateTexture()
    for _ = 1, 3 do full:AddMaskTexture(f:CreateMaskTexture()) end
    Kit.Erase(full)
    T.falsy(Kit.Erased(full), "no room for a fourth mask")
    T.eq(full:GetAlpha(), 0, "faded instead")
    Kit.Erase(f)                                      -- not a texture: left alone
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: a window's title the game recolors is light again as the window opens", function()
    login()
    local title = QuestFrame.TitleContainer.TitleText
    QuestFrame:Hide()
    title:SetTextColor(1, 0.82, 0)                   -- the game, while it was closed
    QuestFrame:Show()
    T.truthy(title.__textColor[3] > 0.6, "light again, not the game's gold")
end)

T.test("skins: an equipment slot that hides its border by hand as it shows (ammo) is recolored after", function()
    login(function()
        character()
        CharacterHeadSlot.IconBorder:SetVertexColor(0.64, 0.21, 0.93)
        CharacterHeadSlot.IconBorder:Show()
        CharacterHeadSlot:SetScript("OnShow", function(self) self.IconBorder:Hide() end)   -- the game's XML
    end)
    local Kit = stub.skins.Kit
    local slot = CharacterHeadSlot
    T.eq(Kit.ShellOf(slot).opts.borderColor[1], 0.64)
    slot:Hide(); slot:Show()
    T.eq(Kit.ShellOf(slot).opts.borderColor, Kit.EMPTY_ITEM_BORDER, "its border hidden: our outline dim")
end)

T.test("skins: the game's pop-up menus, every level, are dressed as they show (EventRegistry, no hooks)", function()
    local callbacks = {}
    login(function()
        -- The game's EventRegistry (CallbackRegistry.lua): callbacks get their owner first.
        _G.EventRegistry = {
            RegisterCallback = function(_, event, fn, owner) callbacks[event] = function(...) fn(owner, ...) end end,
        }
    end)
    local Kit = stub.skins.Kit
    T.truthy(callbacks["MenuProxy.OnShow"], "listening for menus")
    local function menu()
        local m = CreateFrame("Frame", nil, UIParent)
        m.bg = m:CreateTexture()
        m.text = m:CreateFontString()
        m.text:SetTextColor(0.5, 0.5, 0.5)            -- a gray (disabled) entry
        return m
    end
    local root, sub = menu(), menu()
    callbacks["MenuProxy.OnShow"](root)                -- MenuProxyMixin:OnShow
    callbacks["MenuProxy.OnShow"](sub)                 -- a sub-menu, its own frame
    T.isnil(Kit.ShellOf(root), "nothing done inside the game's menu code")
    stub.RunTimers()
    for _, m in ipairs({ root, sub }) do
        T.eq(m.bg:GetAlpha(), 0, "the game's background gone")
        local ours = false
        for _, c in ipairs({ m:GetChildren() }) do if Kit.ShellOf(c) then ours = true end end
        T.truthy(ours, "our look behind it")
        T.eq(m.text.__textColor[1], 0.5, "the game's colors kept")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: tabs and list parts follow the game's changes with no hook on its methods (hook review area 4)", function()
    login()
    local Kit = stub.skins.Kit
    -- A tab-system tab (TabSystemButtonArtMixin:SetTabSelected keeps isSelected
    -- and switches the selected tab off).
    local bar = CreateFrame("Frame", nil, UIParent)
    local tab = CreateFrame("Button", nil, bar)
    tab.Left, tab.LeftActive = tab:CreateTexture(), tab:CreateTexture()
    tab.Text = tab:CreateFontString()
    local function SetTabSelected(self, on)
        self.isSelected = on
        self:SetEnabled(not on)
    end
    tab.SetTabSelected = SetTabSelected
    Kit.Tab(tab)
    T.eq(tab.SetTabSelected, SetTabSelected, "no hook on SetTabSelected")
    local function line()
        local t = Kit.TabOf(tab)
        return t.line:IsShown() and t.line or nil
    end
    T.isnil(line(), "not selected: no accent line")
    tab:SetTabSelected(true)
    T.truthy(line(), "selected: the accent line")
    tab:SetTabSelected(false)
    T.isnil(line(), "and gone again")

    -- A side tab: the game shows its selection art (SidePanelTabButtonMixin:SetChecked).
    local side = CreateFrame("Frame", nil, UIParent)
    side.Icon, side.SelectedTexture = side:CreateTexture(), side:CreateTexture()
    side.SelectedTexture:Hide()
    local function SetChecked(self, on) self.SelectedTexture:SetShown(on) end
    side.SetChecked = SetChecked
    Kit.SideTab(side)
    T.eq(side.SetChecked, SetChecked, "no hook on SetChecked")
    local s = Kit.ShellOf(side)
    side:SetChecked(true)
    Kit.RepaintSoon()                                  -- a window's page shown, the game's event...
    T.eq(s.opts.borderColor, Kit.SELECTED, "repainted selected")
    local walks, walk = 0, Kit.RepaintRows
    Kit.RepaintRows = function() walks = walks + 1; return walk() end
    stub.RunTimers()
    walks = 0
    side:Hide(); side:Show(); side:Hide(); side:Show()   -- a window of many tabs showing
    T.eq(walks, 1, "one walk now, not one per tab")
    stub.RunTimers()
    T.eq(walks, 2, "and the frame after")
    Kit.RepaintRows = walk
    side:SetChecked(false)
    side:Hide(); side:Show()                           -- its window opened again
    T.eq(s.opts.borderColor, Kit.TAB_BORDER, "repainted as it shows")

    -- A skill bar in a list row: the game sets its fill's art as it fills the row.
    local row = CreateFrame("Button", nil, UIParent)
    local pb = CreateFrame("Frame", nil, row)
    pb.Fill = pb:CreateTexture()
    Kit.ProgressBar(pb)
    local ours = pb.Fill.__texture
    pb.Fill:SetAtlas("common-stat-bar-blue")
    pb.Fill.__texture = "game art"
    Kit.RelightIn(row, Kit.ROW_LIGHT_DEPTH)           -- the list's OnInitializedFrame
    T.eq(pb.Fill.__texture, ours, "our bar texture back on")
    T.isnil(rawget(pb.Fill, "SetAtlas"), "no hook on the fill")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's windows sized by Ctrl + the wheel over them (WindowScale.lua).
T.test("window scale: Ctrl + wheel sizes a game window, kept and put back, never in a fight", function()
    stub.Load({ skins = true })
    local WS = stub.skins.WindowScale
    local f = CreateFrame("Frame", "DemoGamePanel", UIParent)
    _G.UIPanelWindows = _G.UIPanelWindows or {}
    _G.UIPanelWindows.DemoGamePanel = { area = "left" }
    stub.FireEvent("ADDON_LOADED", "Blizzard_Demo")
    stub.RunTimers()
    local wheel = f:GetScript("OnMouseWheel")
    T.truthy(wheel, "picked up as its addon loads")
    wheel(f, 1)
    T.near(f:GetScale(), 1, 1e-6, "no Ctrl: the game's size")
    _G.IsControlKeyDown = function() return true end
    wheel(f, 1); wheel(f, 1)
    T.near(f:GetScale(), 1.1)
    T.near(DaylightUI:Get("Skins", "windowScales").DemoGamePanel, 1.1)
    f:SetScale(1)                     -- the game laid its panels out again
    f:Hide(); f:Show()
    T.near(f:GetScale(), 1.1, 1e-6, "back to its size as it shows")
    stub.EnterCombat()
    wheel(f, -1)
    T.near(f:GetScale(), 1.1, 1e-6, "not in a fight")
    stub.LeaveCombat()
    for _ = 1, 40 do wheel(f, -1) end
    T.near(f:GetScale(), WS.MIN, 1e-6, "kept within the range")
    DaylightUI.Movers.ResetAll()
    T.near(f:GetScale(), 1, 1e-6, "/dui reset: the game's size")
    T.isnil(DaylightUI:Get("Skins", "windowScales").DemoGamePanel)
    _G.IsControlKeyDown = nil
    _G.UIPanelWindows.DemoGamePanel = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The dressing room as DressUpFrames.xml makes it, as far as the skin touches
-- it, plus the small one beside the auction house.
local function artButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 24, size or 24)
    local normal = b:CreateTexture()
    normal:SetTexture("game art")
    function b:GetNormalTexture() return normal end
    return b
end

local function modelScene(parent)
    local scene = CreateFrame("Frame", nil, parent)
    scene.ControlFrame = CreateFrame("Frame", nil, scene)
    for _, key in ipairs({ "zoomInButton", "zoomOutButton", "rotateLeftButton", "rotateRightButton", "resetButton" }) do
        local b = artButton(scene.ControlFrame, 32)
        b.Icon = b:CreateTexture()
        scene.ControlFrame[key] = b
    end
    return scene
end

local function dressingRoom()
    local f = window("DressUpFrame")
    f.ModelScene = modelScene(f)
    f.ModelScene.BGTopLeft = f.ModelScene:CreateTexture()
    f.MaximizeMinimizeFrame = CreateFrame("Frame", nil, f)
    f.MaximizeMinimizeFrame.MaximizeButton = artButton(f.MaximizeMinimizeFrame)
    f.MaximizeMinimizeFrame.MinimizeButton = artButton(f.MaximizeMinimizeFrame)
    f.ToggleCustomSetDetailsButton = artButton(f, 25)
    f.CustomSetDropdown = CreateFrame("DropdownButton", nil, f)
    f.CustomSetDropdown.SaveButton = button(nil, f.CustomSetDropdown)
    f.ResetButton = button(nil, f)
    f.LinkButton = button(nil, f)
    button("DressUpFrameCancelButton", f)
    -- The item list: one slot filled with an epic item, one not collected yet.
    local panel = CreateFrame("Frame", nil, f)
    panel.BlackBackground = panel:CreateTexture()
    f.CustomSetDetailsPanel = panel
    local function slot(r, g, b, state, quality)
        local s = CreateFrame("Frame", nil, panel)
        s:SetSize(272, 24)
        s.Icon = s:CreateTexture()
        s.Icon:SetSize(20, 20)
        s.IconBorder = s:CreateTexture()
        s.Name = s:CreateFontString()
        s.Name:SetTextColor(r, g, b)
        s.item, s.slotState, s.transmogID = { GetItemQuality = function() return quality end }, state, 100
        return s
    end
    local epic = slot(0.64, 0.21, 0.93, nil, 4)
    local missing = slot(0.5, 0.5, 0.5, 2, 4)
    local common = slot(1, 1, 1, nil, 1)
    local empty = slot(0.5, 0.5, 0.5)
    empty.item, empty.transmogID = nil, nil
    -- A set's list with one picked row of a rare item.
    local sets = CreateFrame("Frame", nil, f)
    sets.SetName = sets:CreateFontString()
    sets.ScrollBox = list(sets)
    local row = CreateFrame("Button", nil, sets.ScrollBox)
    row:SetSize(350, 32)
    for _, key in ipairs({ "BackgroundTexture", "SelectedTexture", "HighlightTexture", "Icon", "IconBorder" }) do
        row[key] = row:CreateTexture()
    end
    row.Icon:SetSize(24, 24)
    row.ItemName, row.ItemSlot = row:CreateFontString(), row:CreateFontString()
    row.elementData = { itemQuality = 3, itemUsable = true }
    sets.ScrollBox.rows = rows(row)
    f.SetSelectionPanel = sets
    f:Hide()
    local side = CreateFrame("Frame", "SideDressUpFrame", UIParent)
    side.BGTopLeft, side.BGBottomLeft = side:CreateTexture(), side:CreateTexture()
    side.Top = side:CreateTexture()
    side.ModelScene = modelScene(side)
    side.CloseButton = artButton(side)
    return f, epic, missing, row, side, common, empty
end

T.test("skins: the dressing room in our look: model buttons, bare chevrons, the list arrow, item rows in their quality", function()
    local f, epic, missing, row, side, common, empty
    local S = login(function()
        f, epic, missing, row, side, common, empty = dressingRoom()
        _G.CUSTOM_SET_SLOT_STATE_UNCOLLECTED, _G.CUSTOM_SET_SLOT_STATE_ERROR = 2, 3
        _G.GetItemQualityColor = function(q) if q == 3 then return 0, 0.44, 0.87 end end
        if C_Item then C_Item.GetItemQualityColor = _G.GetItemQualityColor end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    f:Show()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, INK = S.Kit, DaylightUI.Style.INK
    T.truthy(Kit.ShellOf(f), "our window look")
    T.truthy(Kit.ShellOf(f.CustomSetDetailsPanel), "the item list on our panel look")
    T.eq(f.CustomSetDetailsPanel.BlackBackground:GetAlpha(), 0, "its black backdrop gone")
    local zoom = f.ModelScene.ControlFrame.zoomInButton
    T.eq(zoom:GetNormalTexture():GetAlpha(), 0, "the zoom button's art gone")
    T.truthy(Kit.ShellOf(zoom), "our icon button")
    T.eq(f.ModelScene.BGTopLeft:GetAlpha(), 1, "the race backdrop behind the model stays")
    local max = f.MaximizeMinimizeFrame.MaximizeButton
    T.eq(max:GetNormalTexture():GetAlpha(), 0, "maximize's art gone")
    T.isnil(Kit.ShellOf(max), "maximize is a bare chevron, no box")
    T.eq(f.ToggleCustomSetDetailsButton:GetNormalTexture():GetAlpha(), 0, "the list button's art gone")
    T.truthy(Kit.ShellOf(f.ToggleCustomSetDetailsButton), "our page arrow")
    -- The item list's slots.
    T.eq(epic.IconBorder:GetAlpha(), 0, "the game's quality ring hidden")
    local s = Kit.ShellOf(epic)
    T.truthy(s, "the icon outlined")
    T.eq(s.opts.borderColor[3], 0.93, "in the item's quality color")
    T.eq(epic.Name.__font[1], DaylightUI.Style.FONT, "our font on the name")
    local r, g, b = missing.Name:GetTextColor()
    T.eq(r, INK.OFF[1], "not collected: dimmed warm, not the game's gray")
    T.eq(b, INK.OFF[3])
    r, g, b = common.Name:GetTextColor()
    T.eq(r, INK.TEXT[1], "a common item: our row text, not the game's pure white")
    T.eq(Kit.ShellOf(common).opts.borderColor, Kit.EMPTY_ITEM_BORDER, "and a quiet outline")
    r = empty.Name:GetTextColor()
    T.eq(r, INK.OFF[1], "an empty slot dimmed warm")
    T.truthy(Kit.ButtonOf(f.CustomSetDropdown.SaveButton), "Save in our button look")
    T.eq(f.CustomSetDropdown.SaveButton.Left:GetAlpha(), 0, "its gray art gone")
    local point, rel, _, x = f.ResetButton:GetPoint(1)
    T.eq(rel, _G.DressUpFrameCancelButton, "Reset beside Close")
    T.truthy(x < 0, "with a gap between them")
    -- Refilled when a new item is tried on, and repainted as it shows.
    epic:Hide()
    epic.Name:SetTextColor(0, 0.44, 0.87)
    epic:Show()
    T.eq(Kit.ShellOf(epic).opts.borderColor[3], 0.87, "repainted in its new quality")
    -- The set's list.
    T.eq(row.BackgroundTexture:GetAlpha(), 0, "the pet list art gone")
    T.eq(row.HighlightTexture:GetAlpha(), 0, "the game's hover glow gone")
    T.eq(Kit.ShellOf(row).opts.borderColor[3], 0.87, "the row's icon in its quality")
    -- The small dressing room.
    side:Show()
    stub.RunTimers()
    T.truthy(Kit.ShellOf(side), "the auction house dressing room in our look")
    T.eq(side.Top:GetAlpha(), 0, "its frame art gone")
    T.eq(side.BGTopLeft:GetAlpha(), 1, "its race backdrop stays")
    T.truthy(Kit.ShellOf(side.ModelScene.ControlFrame.zoomInButton), "its model buttons ours")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.GetItemQualityColor, _G.CUSTOM_SET_SLOT_STATE_UNCOLLECTED, _G.CUSTOM_SET_SLOT_STATE_ERROR = nil, nil, nil
end)

-- The guild window's round portrait (CommunitiesFrame.xml PortraitOverlay) and its
-- maximize/minimize pair beside the X. A guild with no tabard design gets the
-- "no logo" emblem with SetVertexColor(1, 1, 1, 1) on every UpdatePortrait
-- (GuildUtil.lua SetGuildTabardTextures), which brought it back behind the title.
T.test("skins: the guild window's portrait stays gone after the game repaints it; maximize and minimize are bare chevrons", function()
    local f, overlay
    login(function()
        f = guildWindow()
        overlay = CreateFrame("Frame", nil, f)
        overlay:SetFrameLevel(300)
        for _, k in ipairs({ "Portrait", "TabardBackground", "TabardEmblem", "TabardBorder" }) do
            overlay[k] = overlay:CreateTexture()
        end
        f.PortraitOverlay = overlay
        f.MaximizeMinimizeFrame = CreateFrame("Frame", nil, f)
        f.MaximizeMinimizeFrame.MaximizeButton = artButton(f.MaximizeMinimizeFrame)
        f.MaximizeMinimizeFrame.MinimizeButton = artButton(f.MaximizeMinimizeFrame)
        stub.loadedAddOns.Blizzard_Communities = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    -- The game's UpdatePortrait for a guild without a design.
    overlay.TabardEmblem:SetShown(true)
    overlay.TabardEmblem:SetTexture("Interface\\GuildFrame\\GuildLogo-NoLogo")
    overlay.TabardEmblem:SetVertexColor(1, 1, 1, 1)
    overlay.TabardBackground:SetVertexColor(0.2245, 0.2088, 0.1794)
    for _, k in ipairs({ "Portrait", "TabardBackground", "TabardEmblem", "TabardBorder" }) do
        T.truthy(Kit.Erased(overlay[k]), k .. " erased, so the game's vertex color can't bring it back")
    end
    for _, k in ipairs({ "MinimizeButton", "MaximizeButton" }) do
        local b = f.MaximizeMinimizeFrame[k]
        T.eq(b:GetNormalTexture():GetAlpha(), 0, k .. ": the game's art gone")
        T.isnil(Kit.ShellOf(b), k .. ": a bare chevron by the X, no box over the top edge")
    end
end)

T.test("skins: the game's windows wear our header, tabs, text boxes, switches and text colors", function()
    local f, p
    login(function() f, p = standardWindow("TestOurPiecesWindow") end)
    local Kit = stub.skins.Kit
    local INK = DaylightUI.Style.INK
    local yellow = f:CreateFontString()
    yellow:SetTextColor(1, 0.82, 0)                   -- the game's GameFontNormal
    local gray = f:CreateFontString()
    gray:SetTextColor(0.5, 0.5, 0.5)
    local red = f:CreateFontString()
    red:SetTextColor(1, 0.1, 0.1)                     -- meaningful, so kept
    Kit.Window(f)
    Kit.Auto(f)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    -- The header: a white title and the accent line along the top.
    T.eq(f.TitleContainer.TitleText.__textColor[1], INK.VALUE[1], "the title white")
    T.truthy(Kit.TopLineOf(f), "the accent line along the top")
    -- The game's text colors in ours.
    T.eq(yellow.__textColor[1], INK.LABEL[1], "yellow labels tan")
    T.eq(gray.__textColor[1], INK.OFF[1], "gray our warm dim")
    T.eq(red.__textColor[2], 0.1, "a red kept")
    -- A tab is words only, in the accent with its line once selected.
    local tab = CreateFrame("Button", nil, f)
    tab.Left, tab.LeftActive = tab:CreateTexture(), tab:CreateTexture()
    tab.Text = tab:CreateFontString()
    Kit.Tab(tab)
    local t = Kit.TabOf(tab)
    T.isnil(t.picked, "not selected")
    T.eq(tab.Text.__textColor[1], INK.LABEL[1], "tan at rest")
    tab.isSelected = true                             -- the game's tab system picks it
    tab:SetEnabled(false)
    T.truthy(t.picked, "selected")
    T.truthy(t.line:IsShown(), "its line")
    T.eq(tab.Text.__textColor[1], Kit.SELECTED[1], "its words in the accent")
    T.isnil(Kit.ShellOf(tab), "no box round it")
    -- A text box: rounded, with its accent outline off at rest.
    local s = Kit.InputOf(p.search)
    T.eq(s.glow, 0, "the outline at rest")
    T.isnil(rawget(p.search, "glow"), "nothing written on the game's box")
    -- A checkbox becomes a switch that follows the game's SetChecked.
    local sw = Kit.SwitchOf(p.check)
    T.eq(sw.on, false, "off")
    p.check:SetChecked(true)
    stub.RunOnUpdate(Kit.checkPoller, 1)
    T.eq(sw.on, true, "checked by the game: on")
    T.isnil(rawget(p.check, "on"), "nothing written on the game's checkbox")
end)

-- The auction house lists (Blizzard_AuctionHouseTableBuilder.xml). A row button
-- whose name cell is a plain frame with the item's Icon and a gray square
-- IconBorder atlas around it.
T.test("skins: a list row's item icons are cropped, the game's gray square gone", function()
    local f, row, cell
    login(function()
        f = CreateFrame("Frame", "TestAuctionList", UIParent)
        f.ScrollBox = list(f)
        f.ScrollBox.ScrollTarget = CreateFrame("Frame", nil, f.ScrollBox)
        row = CreateFrame("Button", nil, f.ScrollBox.ScrollTarget)
        cell = CreateFrame("Frame", nil, row)
        cell.Icon = cell:CreateTexture(nil, "BACKGROUND")
        cell.IconBorder = cell:CreateTexture(nil, "BACKGROUND")
        cell.rowData = { itemKey = { itemID = 1 } }
        f.ScrollBox.rows = rows(row)
    end)
    local Kit = stub.skins.Kit
    _G.C_AuctionHouse = { GetItemKeyInfo = function() return { quality = 2 } end }
    local was = C_Item and C_Item.GetItemQualityColor
    _G.GetItemQualityColor = function(q) if q == 2 then return 0.1, 1, 0 end end
    if C_Item then C_Item.GetItemQualityColor = _G.GetItemQualityColor end
    Kit.Auto(f)
    stub.RunTimers()
    _G.C_AuctionHouse, _G.GetItemQualityColor = nil, nil
    if C_Item then C_Item.GetItemQualityColor = was end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(Kit.Erased(cell.IconBorder), "the gray square erased for good")
    local shell
    for _, c in ipairs({ cell:GetChildren() }) do shell = shell or DaylightUI.Style.GetShell(c) end
    T.truthy(shell, "the character window's item edge round the icon")
    T.eq(shell.opts.borderColor[2], 1, "in the item's quality color (green)")
    cell.IconBorder:SetAlpha(0.5)   -- a sold auction (the game sets it again)
    T.truthy(Kit.Erased(cell.IconBorder), "still out of sight")
end)

-- ---------------------------------------------------------------------
-- OpenMap (DUI.OpenMap) draws its own entrances, flight paths, boats and
-- unexplored areas on its stitched map and owns its window. The skin's map
-- layers step aside while it shows, and the mover while it's loaded.
-- ---------------------------------------------------------------------

local function fakeOpenMap(stitched)
    local api = { stitched = stitched }
    function api.IsStitched() return api.stitched end
    function api.ArtTopLevel() return 3000 end
    return api
end

T.test("openmap: our world map pins step aside on its stitched map, back on Blizzard's", function()
    local f, api
    login(function()
        api = fakeOpenMap(true)
        _G.OpenMapAPI = api
        f = window("WorldMapFrame")
        f.ScrollContainer = CreateFrame("ScrollFrame", nil, f)
        f.ScrollContainer.Child = CreateFrame("Frame", nil, f.ScrollContainer)
        f.ScrollContainer.Child:SetSize(1000, 700)
        f.mapID = 1434
        _G.C_Map = _G.C_Map or {}
        C_Map.GetMapInfo = function(id) if id == 1434 then return { mapType = 3, name = "Stranglethorn Vale" } end end
        _G.CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
        C_Map.GetMapPosFromWorldPos = function(_, v, id)
            local x = v:GetXY()
            if id == 1434 and tostring(x) == "-11916.1" then return id, { GetXY = function() return 0.53, 0.17 end } end
        end
        stub.SetUnits({ player = { faction = "Horde" } })
    end)
    local P = stub.skins.MapPins
    local function count()
        local n = 0
        for _, b in ipairs({ P.frame:GetChildren() }) do if b:IsShown() and b.pin then n = n + 1 end end
        return n
    end
    f:Show()
    P.Draw()
    T.eq(count(), 0, "none over OpenMap's own")
    api.stitched = false
    DaylightUI.Fire("OpenMapStitched", false)
    T.truthy(count() > 0, "Blizzard's map (a dungeon, a battleground): ours again")
    _G.OpenMapAPI = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("openmap: unexplored areas step aside on its stitched map", function()
    local f, api
    login(function()
        api = fakeOpenMap(true)
        _G.OpenMapAPI = api
        f = window("WorldMapFrame")
        f.ScrollContainer = CreateFrame("ScrollFrame", nil, f)
        f.ScrollContainer.Child = CreateFrame("Frame", nil, f.ScrollContainer)
        f.mapID = 1411
        _G.C_MapExplorationInfo = { GetExploredMapTextures = function() return {} end }
        _G.C_Map = _G.C_Map or {}
        C_Map.GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256 } } end
    end)
    local R = stub.skins.MapReveal
    local function shown()
        local n = 0
        for _, r in ipairs({ R.frame:GetRegions() }) do if r:IsShown() then n = n + 1 end end
        return n
    end
    f:Show()
    DaylightUI:Set("Skins", "mapReveal", true)
    stub.RunTimers()
    T.eq(shown(), 0, "OpenMap has its own")
    api.stitched = false
    DaylightUI.Fire("OpenMapStitched", false)
    T.truthy(shown() > 0, "Blizzard's map: ours again")
    _G.OpenMapAPI = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("openmap: loaded, the map window is its own: no strip, no grip, no saved spot put back", function()
    local f
    login(function()
        _G.OpenMapAPI = fakeOpenMap(false)
        f = window("WorldMapFrame")
        f.BorderFrame = CreateFrame("Frame", nil, f)
        _G.ShowUIPanel = function(p) p:Show() end
        _G.UpdateUIPanelPositions = function() end
    end)
    local MapMove = stub.skins.MapMove
    DaylightUI.DB.Active().modules.Skins.mapSpot = { 100, 600 }
    DaylightUI.DB.Active().modules.Skins.mapScale = 1.2
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Show()
    UpdateUIPanelPositions(f)
    T.eq(select(3, f:GetPoint(1)), "TOPLEFT", "left where OpenMap (here the game) put it")
    T.eq(f:GetScale(), 1, "not scaled by ours")
    T.falsy(MapMove.bar and MapMove.bar:IsShown(), "no drag strip over its title bar")
    T.falsy(MapMove.grip and MapMove.grip:IsShown(), "no grip over its own")
    _G.OpenMapAPI = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- From a player report: with OpenMap the skin still drew the slim top (bare
-- buttons, quest journal up to the window's top), but the map's top kept the
-- game's two rows, so the tall header cut off the journal's search. The slim top
-- now applies with OpenMap too, while the window's size and spot stay OpenMap's.
T.test("openmap: the map's top is one slim row with it too, the window's size left to OpenMap", function()
    local f
    login(function()
        _G.OpenMapAPI = fakeOpenMap(false)
        f = mapWithTop()
    end)
    local MapMove = stub.skins.MapMove
    T.truthy(MapMove.slim, "the skin asks for the slim top")
    f:SetSize(900, 600)       -- OpenMap's saved size
    f:Show()
    stub.RunTimers()
    local cut = MapMove.TOP - MapMove.SLIM
    T.eq(anchor(f.ScrollContainer, "TOPLEFT")[5], cut, "the map up into the freed row")
    T.eq(anchor(f.NavBar, "TOPLEFT")[5], -MapMove.NAV_Y, "the zone buttons in the top row")
    T.eq(f.BorderFrame.TitleContainer:GetAlpha(), 0, "the title makes room")
    T.eq(f:GetWidth(), 900); T.eq(f:GetHeight(), 600, "its size is OpenMap's: never set by ours")
    T.falsy(MapMove.bar and MapMove.bar:IsShown(), "still no drag strip of ours")
    -- Maximized: the game's size and OpenMap's full width. The skin sets neither.
    f.isMaximized = true
    f:SetSize(1500, 900)
    MapMove.Apply()
    T.eq(f:GetWidth(), 1500); T.eq(f:GetHeight(), 900)
    T.eq(anchor(f.ScrollContainer, "TOPLEFT")[5], cut, "one row big too")
    f.isMaximized = false
    f:SetSize(900, 600)
    MapMove.Apply()
    T.eq(f:GetHeight(), 600)
    _G.OpenMapAPI = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The crowd control alert (Packs/LossOfControl.lua; fake: tests/locworld.lua).
local function ccLogin()
    local LW, game = require("locworld"), nil
    local S = login(function() game = LW.Install() end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    return S.CcAlert, game, LW
end

T.test("skins: the crowd control alert: the game's art unseen, ours a light line with no box, in the game's spot and size", function()
    local Alert, game = ccLogin()
    local Style = DaylightUI.Style
    local h = Alert.frame
    T.truthy(h, "ours built")
    T.eq(h:GetParent(), game, "a child: the game's spot, scale, alpha and showing")
    T.eq(h:GetWidth(), game:GetWidth()); T.eq(h:GetHeight(), game:GetHeight())
    for _, k in ipairs({ "blackBg", "RedLineTop", "RedLineBottom", "Icon", "AbilityName", "TimeLeft", "Cooldown" }) do
        T.eq(game[k]:GetAlpha(), 0, k .. " unseen")
    end
    T.falsy(Style.GetShell(h), "no box")
    T.truthy(Style.GetShell(h.art), "the icon wears our border")
    T.eq(h.name.__font and h.name.__font[2] or Style.SIZE.title, Style.SIZE.title, "the window title's size")
end)

T.test("skins: the crowd control alert shows the game's words, icon and time as it lands and as they change", function()
    local Alert, game, LW = ccLogin()
    local h = Alert.frame
    local duration = { "a duration object" }
    LW.Land(game, "Stunned", 135860, "4.2", 2, duration)
    T.eq(h.name:GetText(), "Stunned", "at once, never a frame late")
    T.eq(h.icon:GetTexture(), 135860)
    T.eq(h.time:GetText(), "4.2")
    T.eq(h.bar.__timer[1], duration, "the client runs the bar")
    T.eq(h.bar.__timer[3], Enum.StatusBarTimerDirection.RemainingTime, "running down")
    T.truthy(h.bar:IsShown())
    game.TimeLeft.NumberText:SetText("3.9")
    stub.RunOnUpdate(h, 0.016)
    T.eq(h.time:GetText(), "3.9", "following it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: a short crowd control alert has no bar, and one with no time no time line", function()
    local Alert, game, LW = ccLogin()
    local h = Alert.frame
    LW.Land(game, "Interrupted", 135860, nil, 1, { "not for an alert" })
    T.falsy(h.bar:IsShown(), "an alert isn't timed")
    T.falsy(h.time:IsShown(), "no time line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: the crowd control alert takes secret words, icon and time under restrictions", function()
    local Alert, game, LW = ccLogin()
    local h = Alert.frame
    local duration = { "d" }
    LW.Land(game, stub.Secret("Stunned"), stub.Secret(135860), stub.Secret("4.2"), 2, duration)
    stub.RunOnUpdate(h, 0.016)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(stub.secretArgErrors or 0, 0, "nothing refused")
    T.eq(h.bar.__timer[1], duration, "the bar runs: displayType stays plain")
    game.GetRect = function() return 800, 500, 256, 58 end
    game:Hide()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(Alert.ghost:IsShown(), "and it leaves the same way")
end)

T.test("skins: the crowd control alert listens only while it shows; leaving, a ghost fades out", function()
    local Alert, game, LW = ccLogin()
    local h = Alert.frame
    LW.Land(game, "Stunned", 135860, "1.0", 2, { "d" })
    game.GetRect = function() return 800, 500, 256, 58 end      -- the fake game has no layout
    T.truthy(h:IsEventRegistered("LOSS_OF_CONTROL_UPDATE"))
    game:Hide()
    T.falsy(h:IsEventRegistered("LOSS_OF_CONTROL_UPDATE"), "nothing runs with no alert up")
    T.truthy(Alert.ghost and Alert.ghost:IsShown(), "the ghost in its place")
    T.eq(Alert.ghost.name:GetText(), "Stunned", "the same alert, going")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: the crowd control alert lands again when a new effect takes over; the line ends at full width", function()
    local Alert, game, LW = ccLogin()
    local h = Alert.frame
    LW.Land(game, "Stunned", 135860, "4.2", 2, { "d" })
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    T.eq(h.bar:GetWidth(), h:GetWidth(), "drawn out")
    local pops = 0
    local pop = DaylightUI.Motion.Pop
    DaylightUI.Motion.Pop = function(...) pops = pops + 1; return pop(...) end
    h:GetScript("OnEvent")(h, "LOSS_OF_CONTROL_UPDATE")
    T.eq(pops, 0, "the same effect ticking along stays still")
    h:GetScript("OnEvent")(h, "LOSS_OF_CONTROL_ADDED")
    DaylightUI.Motion.Pop = pop
    T.eq(pops, 1, "a new one lands")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: the crowd control alert has a test mode sample on the game's spot", function()
    local Alert = ccLogin()
    DaylightUI.SetTestMode(true)
    T.truthy(Alert.sample and Alert.sample:IsShown(), "a sample to place and judge")
    DaylightUI.SetTestMode(false)
    T.falsy(Alert.sample:IsShown())
end)

T.test("skins: the dressing room drags by its title bar, stays there when the game lays out, right-click puts it back", function()
    local f
    login(function()
        f = dressingRoom()
        _G.ShowUIPanel = function(p) p:Show() end
        _G.UpdateUIPanelPositions = function() end
        _G.IsControlKeyDown = function() return true end
        _G.UIPanelWindows = { DressUpFrame = { area = "left", pushable = 2 } }
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Move = stub.skins.WindowMove
    local bar = Move.bars.DressUpFrame
    T.truthy(bar, "a strip over the title bar")
    T.eq(bar:GetParent(), f)
    T.truthy(bar:GetFrameLevel() > f.ModelScene:GetFrameLevel(), "over the model, so it gets the mouse")
    local db = DaylightUI.DB.Active().modules.Skins
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 70, -104)
    f:Show()
    bar:GetScript("OnDragStart")(bar, "LeftButton")
    T.truthy(f.__moving, "it moves")
    f.__center = { 600, 500 }
    bar:GetScript("OnDragStop")(bar)
    T.falsy(f.__moving)
    local x, y = DaylightUI.Pixel.Snap(UIParent, 410), DaylightUI.Pixel.Snap(UIParent, 720)
    T.eq(db.windowSpots.DressUpFrame[1], x, "its left edge saved, on a whole pixel")
    T.eq(db.windowSpots.DressUpFrame[2], y, "its top edge saved")
    -- The game lays its windows out again (another opens, maximize), and it returns to the saved spot.
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 70, -104)
    UpdateUIPanelPositions(f)
    local p, rel, rp, px, py = f:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, UIParent); T.eq(rp, "BOTTOMLEFT"); T.eq(px, x); T.eq(py, y)
    -- Scaled with Ctrl + mouse wheel, its corner stays on the spot.
    f:GetScript("OnMouseWheel")(f, 1)
    T.eq(f:GetScale(), 1.05, "sized")
    T.near(select(4, f:GetPoint(1)) * 1.05, x, 0.01, "the corner stayed")
    f:SetScale(1)
    db.windowScales = {}
    -- Right-click forgets the spot and puts it back where the game had it, for good.
    bar:GetScript("OnMouseUp")(bar, "RightButton")
    T.isnil(db.windowSpots.DressUpFrame)
    p, rel, rp, px, py = f:GetPoint(1)
    T.eq(rp, "TOPLEFT"); T.eq(px, 70); T.eq(py, -104)
    UpdateUIPanelPositions(f)
    T.eq(select(3, f:GetPoint(1)), "TOPLEFT")
    -- /dui reset forgets it too, and a corrupt saved spot is ignored.
    db.windowSpots.DressUpFrame = { 100, 600 }
    DaylightUI.Movers.ResetAll()
    T.isnil(db.windowSpots.DressUpFrame)
    db.windowSpots.DressUpFrame = { "x", {} }
    T.noerror(function() Move.Apply("DressUpFrame") end)
    T.eq(select(3, f:GetPoint(1)), "TOPLEFT")
end)

-- The guild window is movable in CommunitiesFrame.xml, but nothing in the game
-- drags it, so the skin makes its title bar drag it. Its dropdowns and calendar button
-- start 26 to 28 px down, under the strip.
T.test("skins: the guild window drags by its title bar like the dressing room, its spot kept by name", function()
    local f
    login(function()
        f = guildWindow()
        f:SetSize(814, 426)
        _G.ShowUIPanel = function(p) p:Show() end
        _G.UpdateUIPanelPositions = function() end
        _G.UIPanelWindows = { CommunitiesFrame = { area = "left", pushable = 1 } }
        stub.loadedAddOns.Blizzard_Communities = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Move = stub.skins.WindowMove
    local bar = Move.bars.CommunitiesFrame
    T.truthy(bar, "a strip over the title bar")
    T.eq(bar:GetParent(), f)
    T.truthy(bar:GetHeight() <= 26, "above the dropdowns and calendar button, 26 down")
    local db = DaylightUI.DB.Active().modules.Skins
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Show()
    bar:GetScript("OnDragStart")(bar, "LeftButton")
    T.truthy(f.__moving, "it moves")
    f.__center = { 700, 500 }
    bar:GetScript("OnDragStop")(bar)
    T.truthy(Move.Spot("CommunitiesFrame"), "its spot saved")
    T.isnil(db.windowSpots.DressUpFrame, "under its own name")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    UpdateUIPanelPositions(f)
    T.eq(select(3, f:GetPoint(1)), "BOTTOMLEFT", "back on its spot after the game lays out")
end)

-- The hunter's stable on Forever is the Camelot one
-- (Blizzard_StableUI/Camelot/Blizzard_StableUI.xml): PetStableFrame is a
-- PortraitFrameTemplate whose pet slots are CheckButtons (PetStableSlotTemplate)
-- with a named icon and their own current/unlocked/locked slot art.
T.test("skins: the hunter's stable (PetStableFrame) wears our window look, its pet slots our item look", function()
    local f, slot
    login(function()
        f = window("PetStableFrame")
        slot = CreateFrame("CheckButton", "PetStableCurrentPet", f)
        slot:SetSize(37, 37)
        slot.icon = slot:CreateTexture("PetStableCurrentPetIconTexture")
        slot.currentBackground = slot:CreateTexture()
        slot.unlockedBackground = slot:CreateTexture()
        slot.lockedBackground = slot:CreateTexture()
        slot.currentGlow = slot:CreateTexture()
        stub.loadedAddOns.Blizzard_StableUI = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(f.NineSlice:GetAlpha(), 0, "the game's frame art gone")
    T.truthy(stub.skins.Kit.ShellOf(f), "our border and panel")
    T.eq(slot.currentBackground:GetAlpha(), 0, "the slot's own art gone")
    T.eq(slot.unlockedBackground:GetAlpha(), 0)
    T.eq(slot.lockedBackground:GetAlpha(), 0)
end)
