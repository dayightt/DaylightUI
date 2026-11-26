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
    -- The game's ForEachFrame asks its view with no check (ScrollBox.lua:595),
    -- so a list whose view isn't set up yet errors.
    box.view = { ForEachFrame = function(_, fn) for _, r in ipairs(box.rows) do fn(r) end end }
    function box:GetView() return self.view end
    function box:ForEachFrame(fn) return self:GetView():ForEachFrame(fn) end
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

-- A frame that is a callback registry, as CommunitiesFrame is (CallbackRegistryMixin).
local function registry(frame, names)
    frame.Event, frame.callbacks = {}, {}
    for _, name in ipairs(names) do frame.Event[name] = name end
    function frame:RegisterCallback(event, fn, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        self.callbacks[event][owner] = fn
    end
    function frame:TriggerEvent(event, ...)
        for owner, fn in pairs(self.callbacks[event] or {}) do fn(owner, ...) end
    end
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
    -- The game's quest window: Daylight UI has its own, so no skin touches it.
    local q = window("QuestFrame")
    button("QuestFrameAcceptButton", q)
    for _, n in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoObjectivesText" }) do
        _G[n] = q:CreateFontString(n)
    end
    _G.QuestInfo_Display = function() end
    window("TabardFrame")

    local trade = window("TradeFrame")
    trade.TradeButton = button("TradeFrameTradeButton", trade)
    trade.CancelButton = button("TradeFrameCancelButton", trade)
    _G.TradeFramePlayerNameText = trade:CreateFontString("TradeFramePlayerNameText")
    _G.TradeFrameRecipientNameText = trade:CreateFontString("TradeFrameRecipientNameText")
    trade.RecipientOverlay = CreateFrame("Frame", nil, trade)
    trade.RecipientOverlay.portrait = trade.RecipientOverlay:CreateTexture()
    trade.RecipientOverlay.portraitFrame = trade.RecipientOverlay:CreateTexture()
    -- TradeItemTemplate: a plain row with the slot art, a name frame and the
    -- item button inside (TradeFrame.xml).
    local ti = CreateFrame("Frame", "TradePlayerItem1", trade)
    ti:SetSize(153, 37)
    ti.SlotTexture = ti:CreateTexture("TradePlayerItem1SlotTexture")
    _G.TradePlayerItem1NameFrame = ti:CreateTexture("TradePlayerItem1NameFrame")
    local slot = CreateFrame("Button", "TradePlayerItem1ItemButton", ti)
    slot:SetSize(37, 37)
    slot.icon = slot:CreateTexture()
    slot.IconBorder = slot:CreateTexture()
    -- MoneyInputFrameTemplate: three boxes, each with its coin (MoneyInputFrame.xml).
    local mf = CreateFrame("Frame", "TradePlayerInputMoneyFrame", trade)
    mf.Bg = mf:CreateTexture()
    for _, coin in ipairs({ "gold", "silver", "copper" }) do
        local box = CreateFrame("EditBox", "TradePlayerInputMoneyFrame" .. coin, mf)
        box.left, box.right = box:CreateTexture(), box:CreateTexture()
        box.Left, box.Right, box.Middle = box.left, box.right, box:CreateTexture()
        box.texture = box:CreateTexture()
        box.texture:SetAtlas("coin-" .. coin)
        mf[coin] = box
    end
    -- TradeFrame_OnLoad: TradePlayerInputMoneyFrame:SetForbidden().
    mf.__forbidden = true
    -- TradeHighlightTemplate: green art, shown while that side has accepted.
    local h = CreateFrame("Frame", "TradeHighlightRecipient", trade)
    h.art = h:CreateTexture()
    h:Hide()
    -- The game's money redraw (MoneyFrame.lua); the skin post-hooks it.
    _G.MoneyFrame_Update = function() end
    -- SmallMoneyFrameTemplate: a coin button per coin (MoneyFrame.xml).
    local rm = CreateFrame("Frame", "TradeRecipientMoneyFrame", trade)
    for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        local b = CreateFrame("Button", nil, rm)
        local tex = b:CreateTexture()
        tex:SetAtlas("coin-gold")
        function b:GetNormalTexture() return tex end
        rm[key] = b
    end
end

-- Daylight UI's own windows off: the game's own ones are what a player sees.
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
    local f = TradeFrame
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
    local b = TradeFrameTradeButton
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

-- The game menu's buttons carry the game's GameFontHighlightLarge as their
-- normal, highlight and disabled fonts, and the client puts it back on the
-- label each time the mouse comes onto one or leaves it. The label grew to
-- the game's large font under the mouse.
T.test("skins: a button keeps the Daylight font under the mouse, after it and when disabled", function()
    login(function()
        local big = CreateFont("GameFontHighlightLarge")
        big:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
        big:SetTextColor(1, 0.82, 0)
        local b = TradeFrameTradeButton
        b:SetNormalFontObject(big)
        b:SetHighlightFontObject(big)
        b:SetDisabledFontObject("GameFontHighlightLarge")
    end)
    local Style, W = DaylightUI.Style, DaylightUI.Widgets
    local b = TradeFrameTradeButton
    local label = b:GetFontString()
    local file, size = label:GetFont()
    T.eq(file, Style.FONT, "dressed in the Daylight font")
    local function same(why)
        local f, s = label:GetFont()
        T.eq(f, file, why); T.eq(s, size, why .. ", same size")
        T.rgb(label.__textColor, W.BUTTON.text, why .. ", the button's ink")
    end
    stub.MouseEnter(b); same("under the mouse")
    stub.MouseLeave(b); same("after the mouse leaves")
    b:Disable(); same("disabled")
    b:Enable(); same("enabled again")
    -- The player picks another font: the hover font follows it.
    DaylightUI:Set("general", "font", "fira")
    stub.RunTimers()
    file = Style.FONTS.fira.file
    T.eq((label:GetFont()), file, "the label takes the new font")
    stub.MouseEnter(b); same("the new font under the mouse")
    stub.MouseLeave(b)
    DaylightUI:Set("general", "font", nil)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A style change (every General change, every UI scale or window size change)
-- put the three font objects back on every skinned game button of the session,
-- even when each already had them. Only a button whose font really changed is written.
T.test("skins: a style change with nothing new leaves a button's state fonts alone", function()
    login(function()
        local big = CreateFont("GameFontHighlightLarge")
        big:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
        local b = TradeFrameTradeButton
        b:SetNormalFontObject(big)
        b:SetHighlightFontObject(big)
        b:SetDisabledFontObject(big)
    end)
    local b = TradeFrameTradeButton
    local face = b:GetNormalFontObject()
    T.truthy(face and face ~= _G.GameFontHighlightLarge, "dressed")
    local writes = 0
    for _, m in ipairs({ "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject" }) do
        local real = b[m]
        rawset(b, m, function(self, f) writes = writes + 1; return real(self, f) end)
    end
    DaylightUI.Fire("StyleChanged")
    T.eq(writes, 0, "already wearing the Daylight face")
    b:Disable(); b:Enable()
    T.eq(writes, 0, "nor on enable and disable")
    DaylightUI:Set("general", "font", "fira")
    stub.RunTimers()
    T.truthy(writes > 0, "a new font is still written")
    T.truthy(b:GetNormalFontObject() ~= face, "the new face")
    for _, m in ipairs({ "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject" }) do rawset(b, m, nil) end
    DaylightUI:Set("general", "font", nil)
    stub.RunTimers()
end)

-- The game menu's buttons come from a pool. Each time the menu opens, AddButton
-- (MainMenuFrameTemplates.lua) clears their OnEnter/OnLeave before showing them.
-- That removed the skin's hooks, so from the second opening on hover lit nothing.
T.test("skins: a button whose OnEnter/OnLeave the game clears still lights when shown again", function()
    login()
    local b = TradeFrameTradeButton
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
    local contents
    login(function()
        DaylightUIDB.modules.Skins = { packs = { npc = false } }   -- the game's quest window undressed
        local map = window("WorldMapFrame")
        local qm = CreateFrame("Frame", "QuestMapFrame", map)
        qm.DetailsFrame = CreateFrame("Frame", nil, qm)
        contents = CreateFrame("Frame", nil, qm.DetailsFrame)
    end)
    WorldMapFrame:Show()
    stub.RunTimers()
    local body = QuestInfoDescriptionText
    -- The game's next fill colors and fills the text, then the skin follows.
    body:SetTextColor(0.2, 0.1, 0)
    body:SetText("|cff000000Elmore's Task|r and |cffff2020red|r")
    QuestInfo_Display(nil, contents)
    T.truthy(body.__textColor[1] > 0.8, "put back")
    T.truthy(not body:GetText():find("|cff000000", 1, true), "the dark run rewritten")
    T.truthy(body:GetText():find("|cffff2020", 1, true), "other colors left")
    for _, m in ipairs({ "SetTextColor", "SetText", "SetFormattedText" }) do
        T.isnil(rawget(body, m), "no hook on the game's text: " .. m)
    end
    -- The game's own quest window fills through the same function and keeps its
    -- dark ink on its parchment.
    body:SetTextColor(0.2, 0.1, 0)
    QuestInfo_Display(nil, QuestFrame)
    T.eq(body.__textColor[1], 0.2, "the game's quest window left as the game draws it")
end)

T.test("skins: a book's pages stay light after a page turn", function()
    login(function()
        local f = CreateFrame("Frame", "ItemTextFrame", UIParent)
        f:Hide()
        f:SetSize(338, 424)
        f.TitleContainer = CreateFrame("Frame", nil, f)
        f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
        f.CloseButton = CreateFrame("Button", "ItemTextFrameCloseButton", f)
        f.Inset = CreateFrame("Frame", "ItemTextFrameInset", f)
        f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -60)
        f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 26)
        local scroll = CreateFrame("ScrollFrame", "ItemTextScrollFrame", f)
        local bar = CreateFrame("Slider", "ItemTextScrollFrameScrollBar", scroll)
        scroll.ScrollBar = bar
        function scroll:GetVerticalScrollRange() return self.__range or 0 end
        CreateFrame("SimpleHTML", "ItemTextPageText", f)
        _G.ItemTextGetText = function() return "A letter" end
        f:CreateFontString("ItemTextCurrentPage")
        for _, spec in ipairs({ { "ItemTextPrevPageButton", "Ant." }, { "ItemTextNextPageButton", "Sig." } }) do
            local b = CreateFrame("Button", spec[1], f)
            local normal = b:CreateTexture()
            function b:GetNormalTexture() return normal end
            b.label = b:CreateFontString()
            b.label:SetText(spec[2])
        end
    end)
    local page = _G.ItemTextPageText
    -- ITEM_TEXT_BEGIN: the game sets the parchment's dark brown and its serif.
    for _, tag in ipairs({ "P", "H1", "H2", "H3" }) do
        page:SetTextColor(tag, 0.18, 0.12, 0.06)
        page:SetFont(tag, "Fonts\\MORPHEUS.ttf", 15, "")
    end
    ItemTextFrame:Show()
    stub.RunTimers()
    local Style = DaylightUI.Style
    local ink = Style.INK
    local file = Style.FontFile(Style.WINDOW_SLOT)
    local scale = DaylightUI:Get("general", "fontScale") or 1
    T.eq(page.__tagColor.P[1], ink.TEXT[1], "body text light")
    T.eq(page.__tagColor.H1[1], ink.TITLE[1], "headings light")
    T.eq(page:GetText(), "A letter", "the page is reset from ItemTextGetText, since SimpleHTML has no GetText")
    local bodyFont, headFont = page.__fontObject.P, page.__fontObject.H1
    T.eq(bodyFont:GetFont(), file, "the window font, not the quest serif")
    T.eq(select(2, bodyFont:GetFont()), Style.SIZE.body * scale, "body size")
    T.eq(select(2, headFont:GetFont()), Style.SIZE.title * scale, "a heading at the title size")
    T.eq(page.__fontObject.H2, page.__fontObject.H3, "the smaller headings share one font object")
    function page:GetContentHeight() return 480 end
    page:SetHeight(10)
    ItemTextFrame:Hide()
    ItemTextFrame:Show()
    stub.RunTimers()
    T.eq(page:GetHeight(), 480, "the scroll child is measured again after the new width and font")
    local nextb = _G.ItemTextNextPageButton
    T.eq(nextb:GetNormalTexture():GetAlpha(), 0, "the spellbook arrow gone")
    T.eq(nextb.label:GetAlpha(), 0, "the Sig. label gone")
    local chev
    for _, r in ipairs({ nextb:GetRegions() }) do
        if r.__texture == DaylightUI.MEDIA .. "ui-chevron.png" then chev = r end
    end
    T.truthy(chev, "our chevron")
    T.eq(chev.__rotation, math.pi / 2, "pointing to the next page")
    T.truthy(stub.skins.Kit.ShellOf(nextb), "a button, like the other window controls")
    local point, rel, relPoint, x, y = nextb:GetPoint(1)
    T.eq(point, "BOTTOMRIGHT"); T.eq(rel, ItemTextFrame.Inset); T.eq(relPoint, "BOTTOMRIGHT")
    T.eq(x, -12); T.eq(y, 12, "the page row sits inside the dark box, in from the corner")
    T.eq(nextb:GetWidth(), 22, "big enough to hit")
    T.truthy(nextb:GetFrameLevel() > ItemTextFrame.Inset:GetFrameLevel(), "the page buttons sit above the dark box")
    point, rel, relPoint = _G.ItemTextCurrentPage:GetPoint(1)
    T.eq(point, "RIGHT"); T.eq(rel, nextb); T.eq(relPoint, "LEFT", "the number sits against the next chevron")
    T.eq(_G.ItemTextCurrentPage.__textColor[1], ink.LABEL[1], "the number in label ink")
    local prevPoint, prevRel = _G.ItemTextPrevPageButton:GetPoint(1)
    T.eq(prevPoint, "RIGHT"); T.eq(prevRel, _G.ItemTextCurrentPage, "the previous chevron on the number's other side")
    local scroll = _G.ItemTextScrollFrame
    local inset = ItemTextFrame.Inset
    local ip, irel, irp, ix, iy = inset:GetPoint(1)
    T.eq(ip, "TOPLEFT"); T.eq(irel, ItemTextFrame.TitleContainer.TitleText); T.eq(irp, "BOTTOMLEFT")
    T.eq(ix, 0); T.eq(iy, -16, "the same gap under the title as along the other sides")
    local bp2, brel2, brp2, bx, by2 = inset:GetPoint(2)
    T.eq(bp2, "BOTTOMRIGHT"); T.eq(brel2, ItemTextFrame); T.eq(brp2, "BOTTOMRIGHT")
    T.eq(bx, -16); T.eq(by2, 16, "the right and bottom gaps match")
    local sp, srel, srp, sx, sy = scroll:GetPoint(1)
    T.eq(sp, "TOPLEFT"); T.eq(srel, inset); T.eq(srp, "TOPLEFT")
    T.eq(sx, 12); T.eq(sy, -12, "the text starts in from the dark box")
    T.eq(select(5, scroll:GetPoint(2)), 42, "the text stops above the page buttons")
    local bar = _G.ItemTextScrollFrameScrollBar
    T.eq(bar:IsShown(), false, "no track when the page fits")
    local bp, brel, brp, _, by = bar:GetPoint(1)
    T.eq(bp, "TOPLEFT"); T.eq(brel, scroll); T.eq(brp, "TOPRIGHT"); T.eq(by, 0, "the track starts with the first line")
    scroll.__range = 200
    scroll:GetScript("OnScrollRangeChanged")(scroll)
    T.eq(bar:IsShown(), true, "the track comes back when the page is longer than the window")
    scroll.__range = 0
    scroll:GetScript("OnScrollRangeChanged")(scroll)
    T.eq(page:GetWidth(), 338 - 2 * 16 - 2 * 12, "the line keeps the inner padding")
    local title = ItemTextFrame.TitleContainer.TitleText
    local tp, trel, trp, tx, ty = title:GetPoint(1)
    T.eq(tp, "TOPLEFT"); T.eq(trel, ItemTextFrame); T.eq(trp, "TOPLEFT")
    T.eq(tx, DaylightUI.Win.EDGE); T.eq(ty, DaylightUI.Win.TITLE_Y, "the title sits in the header, like our windows")
    local _, titleRel = title:GetPoint(2)
    T.eq(titleRel, ItemTextFrame.CloseButton, "a long title stops at the close button")
    local cp, crel, crp, cx, cy = ItemTextFrame.CloseButton:GetPoint(1)
    T.eq(cp, "TOPRIGHT"); T.eq(crel, ItemTextFrame); T.eq(crp, "TOPRIGHT")
    T.eq(cx, DaylightUI.Win.CLOSE_X); T.eq(cy, DaylightUI.Win.CloseY(false), "the close button sits in the header")
    T.eq(ItemTextFrame.CloseButton:GetWidth(), DaylightUI.Widgets.CLOSE)
    local bar = stub.skins.WindowMove.bars.ItemTextFrame
    T.truthy(bar, "the title bar drags the window")
    T.eq(bar:GetParent(), ItemTextFrame)
    -- A page turn puts the parchment layout and the serif back. The letter follows.
    _G.ItemTextGetText = function() return "Page two" end
    page:SetText("stale")
    page:SetHeight(10)
    page:SetFont("P", "Fonts\\MORPHEUS.ttf", 15, "")
    scroll:SetPoint("TOPLEFT", ItemTextFrame, "TOPLEFT", 6, -63)
    ItemTextFrame:GetScript("OnEvent")(ItemTextFrame, "ITEM_TEXT_READY")
    T.eq(page:GetText(), "Page two", "the new page is read from ItemTextGetText")
    -- A letter from a player ends with who wrote it, the way the game sets it.
    _G.ITEM_TEXT_FROM = "From"
    _G.ItemTextGetCreator = function() return "Ana" end
    ItemTextFrame:GetScript("OnEvent")(ItemTextFrame, "ITEM_TEXT_READY")
    T.eq(page:GetText(), "Page two\n\nFrom\nAna\n", "the sender's line stays under the letter")
    _G.ItemTextGetCreator = nil
    T.eq(page.__tagColor.P[1], ink.TEXT[1], "still light on the next page")
    T.eq(page.__fontObject.P:GetFont(), file, "still our font")
    T.eq(page:GetHeight(), 480, "the new page is measured again")
    T.eq(select(2, scroll:GetPoint(1)), ItemTextFrame.Inset, "the text comes back into the dark box")
    T.eq(select(5, scroll:GetPoint(1)), -12, "with the same inner padding")
    -- The pack is off. A style change must not dress the letter again.
    scroll:SetPoint("TOPLEFT", ItemTextFrame, "TOPLEFT", 6, -63)
    DaylightUI:Set("Skins", "packs.npc", false)
    stub.RunTimers()
    DaylightUI.Fire("StyleChanged")
    T.eq(select(5, scroll:GetPoint(1)), -63, "with the skin off, a style change leaves the letter alone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: trade slots, money frames and the Trade/Cancel buttons", function()
    login()
    local Kit = stub.skins.Kit
    local slot = TradePlayerItem1ItemButton
    T.eq(slot.IconBorder:GetAlpha(), 0, "the slot's own border gone, our outline instead")
    T.truthy(Kit.ShellOf(slot), "the slot wears the item look")
    T.truthy(Kit.RowOf(TradePlayerItem1), "the row is a list line")
    T.falsy(Kit.ShellOf(TradePlayerItem1), "no box round the row")
    T.eq(TradePlayerItem1.SlotTexture:GetAlpha(), 0, "the row's slot art gone")
    T.eq(TradePlayerItem1NameFrame:GetAlpha(), 0, "the row's name frame gone")
    -- The same item edge as the bags: a full shell, the band a dimmer copy.
    Kit.Paint(Kit.ShellOf(slot), { 0, 0.44, 0.87 })
    local band = Kit.ShellOf(slot).opts.bandColor
    T.truthy(band and math.abs(band[3] - 0.87 * DaylightUI.Char.Slots.BAND_DIM) < 1e-6, "the band dimmed like the bags'")
    -- Your money boxes are forbidden in game: left alone, and nothing errors.
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(Kit.InputOf(rawget(TradePlayerInputMoneyFrame, "gold")), "the forbidden boxes untouched")
    local gold = TradeRecipientMoneyFrame.GoldButton:GetNormalTexture()
    T.truthy(tostring(gold:GetTexture()):find("coin-gold.png", 1, true), "their money in our coins")
    T.truthy(stub.skins.Kit.ButtonOf(TradeFrameTradeButton), "the Trade button, flat")
    T.truthy(stub.skins.Kit.ButtonOf(TradeFrameCancelButton), "the Cancel button, flat")
    -- the other player's portrait and its gold ring are erased (their own
    -- frame, over the names), and their name gets its whole side
    T.eq(TradeFrame.RecipientOverlay.portrait:GetAlpha(), 0, "their portrait gone")
    T.eq(TradeFrame.RecipientOverlay.portraitFrame:GetAlpha(), 0, "its gold ring gone")
    local Trade = stub.skins.Trade
    local _, rel, relPoint, left = TradeFrameRecipientNameText:GetPoint(1)
    T.eq(rel, TradeFrame); T.eq(relPoint, "TOPLEFT")
    T.eq(left, Trade.THEIR_X, "their name heads their column, not after the portrait")
    -- An empty slot is just its outline, as in the bags.
    slot.icon:SetTexture(nil)
    Kit.SlotQuality(slot)
    local backs = 0
    for _, r in ipairs({ slot:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r:GetDrawLayer() == "BACKGROUND" and r:IsShown() and r:GetAlpha() > 0 then backs = backs + 1 end
    end
    T.eq(backs, 0, "no black square under an empty slot")
    -- Trade and Cancel: a footer, centered, the same width.
    T.eq(select(3, TradeFrameTradeButton:GetPoint(1)), "BOTTOM")
    T.eq(select(3, TradeFrameCancelButton:GetPoint(1)), "BOTTOM")
    T.eq(TradeFrameTradeButton:GetWidth(), TradeFrameCancelButton:GetWidth())
end)

-- The game's own trade layout (tests/tradeworld.lua): each side's item, enchant
-- and money boxes are InsetFrameTemplates with marble art, named but not keyed,
-- so the window walk never finds them as insets.
T.test("skins: trade's marble boxes become the dark inset every skinned window has", function()
    local TW, f = require("tradeworld"), nil
    local S = login(function() f = TW.Install() end)
    TW.Fill(f, { mine = { { name = "Linen Cloth" } } })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    for _, name in ipairs({ "TradePlayerItemsInset", "TradePlayerEnchantInset", "TradePlayerInputMoneyInset",
                            "TradeRecipientItemsInset", "TradeRecipientEnchantInset", "TradeRecipientMoneyInset" }) do
        T.eq(_G[name].Bg:GetAlpha(), 0, name .. ": the marble gone")
        T.truthy(S.Kit.ShadeOf(_G[name]), name .. ": the dark inset instead")
    end
end)

T.test("skins: trade shows the other side's accept in the good color, easing in", function()
    login()
    local h = TradeHighlightRecipient
    local art = h.art
    TradeFrame:Show()
    stub.RunTimers()
    T.eq(art:GetAlpha(), 0, "the game's green art gone")
    local ours = h:GetChildren()
    T.truthy(ours, "a look of ours on it")
    h:Show()
    T.truthy(ours:GetAlpha() < 1, "eases in, never pops")
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02) end
    T.eq(ours:GetAlpha(), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: a window from a game addon that loads later is skinned when it loads", function()
    login()
    T.isnil(stub.skins.Kit.ShellOf(_G.CalendarFrame or {}), "not there yet")
    local f = window("CalendarFrame")
    stub.FireEvent("ADDON_LOADED", "Blizzard_Calendar")
    stub.loadedAddOns.Blizzard_Calendar = true
    stub.FireEvent("ADDON_LOADED", "Blizzard_Calendar")
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ShellOf(f), "skinned once its addon is in")
    T.eq(f.NineSlice:GetAlpha(), 0, "the game's art gone")
end)

-- A game window the player picks over Daylight UI's (Win.Swap) wears the Daylight UI
-- look. The bank, which the bags stand in for without a swap, stays as the game draws it.
T.test("skins: the game's windows picked over Daylight UI's wear its look, the bank stays plain", function()
    local made = {}
    login(function()
        _G.DaylightUIDB = { modules = { Character = { enabled = false }, Inspect = { enabled = false },
            Social = { enabled = false }, Mailbox = { enabled = false }, GroupFinder = { enabled = false } } }
        for _, name in ipairs({ "BankFrame", "CharacterFrame", "MailFrame", "LFGParentFrame" }) do
            made[name] = window(name)
        end
    end)
    for _, pair in ipairs({ { "InspectFrame", "Blizzard_InspectUI" },
                            { "SocialUIFrame", "Blizzard_SocialUI" } }) do
        made[pair[1]] = window(pair[1])
        stub.loadedAddOns[pair[2]] = true
        stub.FireEvent("ADDON_LOADED", pair[2])
    end
    stub.RunTimers()
    for name, f in pairs(made) do
        f:Hide(); f:Show()
        stub.RunTimers()
        if name == "BankFrame" then
            T.isnil(stub.skins.Kit.ShellOf(f), name .. ": no shell of ours")
            T.eq(f.NineSlice:GetAlpha(), 1, name .. ": the game's art kept")
        else
            T.truthy(stub.skins.Kit.ShellOf(f), name .. ": in the Daylight UI look")
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: a pack switched off leaves its windows as the game draws them", function()
    login(function()
        _G.DaylightUIDB = { modules = { Skins = { packs = { npc = false } }, NPC = { enabled = false } } }
    end)
    T.isnil(stub.skins.Kit.ShellOf(TabardFrame))
    T.eq(TabardFrame.NineSlice:GetAlpha(), 1)
    DaylightUI:Set("Skins", "packs.npc", true)
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ShellOf(TabardFrame), "on again: skinned now")
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

T.test("skins: /dui skins dump lists what a window is made of", function()
    login(function()
        local host = CreateFrame("Frame", nil, window("DumpTestFrame"))
        DumpTestFrame.RightPaneHost = host
        CreateFrame("Frame", "DumpTestScrollBox", host)
        host.StoneBg = host:CreateTexture()
    end)
    DaylightUI.RunCommand("skins dump DumpTestFrame.RightPaneHost 2")
    T.truthy(stub.ChatContains("DumpTestScrollBox"), "a named child")
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

-- The game's macro window, as Blizzard_MacroUI.xml builds it.
local function macroWindow()
    local f = window("MacroFrame")
    f.SelectedMacroButton = CreateFrame("CheckButton", "MacroFrameSelectedMacroButton", f)
    f.SelectedMacroButton.Icon = f.SelectedMacroButton:CreateTexture()
    f.MacroSelector = CreateFrame("Frame", nil, f)
    local box = list(f.MacroSelector)
    box.ScrollTarget = CreateFrame("Frame", nil, box)
    f.MacroSelector.ScrollBox = box
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, box.ScrollTarget)
        b:SetSize(36, 36)
        -- SelectorButtonTemplate: its icon is its normal texture.
        b.Icon = b:CreateTexture()
        function b:GetNormalTexture() return self.Icon end
        b.Name = b:CreateFontString()
        box.rows[i] = b
    end
    rows(unpack(box.rows))
    local bar = CreateFrame("EventFrame", nil, f.MacroSelector)
    bar.Track = CreateFrame("Frame", nil, bar)
    bar.Track.Thumb = CreateFrame("Button", nil, bar.Track)
    bar.Back, bar.Forward = CreateFrame("Button", nil, bar), CreateFrame("Button", nil, bar)
    f.MacroSelector.ScrollBar = bar
    local sf = CreateFrame("ScrollFrame", "MacroFrameScrollFrame", f)
    CreateFrame("EditBox", "MacroFrameText", sf)
    for _, name in ipairs({ "MacroEditButton", "MacroCancelButton", "MacroSaveButton",
                            "MacroDeleteButton", "MacroNewButton", "MacroExitButton" }) do
        local b = button(name, f)
        b:GetFontString():SetText(name)
    end
    for i = 1, 2 do
        -- PanelTopTabButtonTemplate
        local tab = CreateFrame("Button", "MacroFrameTab" .. i, f)
        tab:SetID(i)
        tab.Left, tab.Middle, tab.Right = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
        tab.LeftActive, tab.MiddleActive, tab.RightActive = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
        tab.Text = tab:CreateFontString()
        tab.Text:SetText(i == 1 and "General Macros" or "Character Macros")
    end
    return f
end

-- With the controller UI on, the macro window's footer (X binds a macro to the
-- controller bars) refreshes at the end of each tab switch, right after the game
-- enables and disables the New, Edit and Delete buttons, the macro slots and the
-- tabs. Daylight UI code on any of those ran first and tainted the footer, and
-- the game then refused SetPreferredGamepadInteractTarget, blamed on the skins.
T.test("skins: no Daylight UI code runs inside the macro window while the game switches its tab", function()
    local f
    login(function() f = macroWindow() end)
    stub.loadedAddOns.Blizzard_MacroUI = true
    stub.FireEvent("ADDON_LOADED", "Blizzard_MacroUI")
    stub.RunTimers()
    f:Show()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(f), "our window")
    T.truthy(Kit.ButtonOf(MacroNewButton), "our buttons")
    T.truthy(Kit.TabOf(MacroFrameTab2), "our tabs")
    local inside = stub.AddonScriptsInside(f, { "OnShow", "OnHide", "OnSizeChanged", "OnEnable", "OnDisable" })
    T.eq(#inside, 0, "Daylight UI code inside the macro window: " .. table.concat(inside, ", "))

    -- The quiet pieces still follow the game: a grayed-out button, the picked tab.
    MacroDeleteButton:Disable()
    Kit.quietPoller:GetScript("OnUpdate")(Kit.quietPoller, 0.016)
    T.truthy(Kit.ButtonOf(MacroDeleteButton).off, "a disabled button shows as off")
    f.selectedTab = 2
    MacroFrameTab2:Disable()
    Kit.quietPoller:GetScript("OnUpdate")(Kit.quietPoller, 0.016)
    T.truthy(Kit.TabOf(MacroFrameTab2).picked or Kit.TabOf(MacroFrameTab2).on, "the character tab shows as picked")
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

T.test("skins: the role check pop-ups: our window and buttons, the role icons kept", function()
    local poll, check, tank
    login(function()
        -- RolePoll.xml and LFDFrame.xml: a DialogBorderTemplate box, an unnamed
        -- title, role buttons with their own art, UIPanelButtonTemplate buttons.
        poll = CreateFrame("Frame", "RolePollPopup", UIParent)
        poll:SetSize(306, 160)
        poll.title = poll:CreateFontString()
        poll.Border = CreateFrame("Frame", nil, poll)
        poll.Border.art = poll.Border:CreateTexture()
        poll.CloseButton = button("RolePollPopupCloseButton", poll)
        tank = CreateFrame("Button", "RolePollPopupRoleButtonTank", poll)
        tank.icon = tank:CreateTexture()
        poll.acceptButton = button("RolePollPopupAcceptButton", poll)
        check = CreateFrame("Frame", "LFDRoleCheckPopup", UIParent)
        check:SetSize(306, 180)
        check.Text = check:CreateFontString()
        check.Border = CreateFrame("Frame", nil, check)
        button("LFDRoleCheckPopupAcceptButton", check)
        button("LFDRoleCheckPopupDeclineButton", check)
        local desc = CreateFrame("Frame", "LFDRoleCheckPopupDescription", check)
        desc:CreateFontString("LFDRoleCheckPopupDescriptionText")
        desc.SubText = desc:CreateFontString()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(poll), "the role poll in our window")
    T.eq(poll.Border:GetAlpha(), 0, "the game's gold border gone")
    T.truthy(Kit.ButtonOf(poll.acceptButton), "Accept is our button")
    T.eq(tank.icon:GetAlpha(), 1, "the role icons stay")
    T.truthy(Kit.ShellOf(check), "the dungeon finder's role check too")
    T.eq(check.Border:GetAlpha(), 0)
    T.truthy(Kit.ButtonOf(LFDRoleCheckPopupAcceptButton))
    T.truthy(Kit.ButtonOf(LFDRoleCheckPopupDeclineButton))
    poll:Hide(); poll:Show()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

T.test("skins: a walk caught by a fight waits hidden, then finishes after it", function()
    login()
    local Kit = stub.skins.Kit
    local budget = Kit.AUTO_BUDGET
    Kit.AUTO_BUDGET = 5
    local f = CreateFrame("Frame", nil, UIParent)
    local buttons = {}
    for i = 1, 30 do buttons[i] = button(nil, CreateFrame("Frame", nil, f)) end
    Kit.Auto(f)
    T.truthy(Kit.walker:IsShown(), "walking")
    stub.EnterCombat()
    stub.RunOnUpdate(Kit.walker, 1 / 60)
    T.falsy(Kit.walker:IsShown(), "hidden for the fight, so no work per frame")
    T.isnil(Kit.ButtonOf(buttons[30]), "paused")
    stub.LeaveCombat()
    T.truthy(Kit.walker:IsShown(), "back once the fight ends")
    for _ = 1, 40 do stub.RunOnUpdate(Kit.walker, 1 / 60) end
    T.truthy(Kit.ButtonOf(buttons[30]), "and the walk finishes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    Kit.AUTO_BUDGET = budget
end)

T.test("skins: money (gold, silver, copper) wears Daylight UI's coins, never a button look", function()
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
    T.eq(money.CopperButton.coin:GetAlpha(), 1, "the coin shown")
    T.truthy(tostring(money.CopperButton.coin:GetTexture()):find("coin-copper.png", 1, true), "our copper coin")
    -- The game puts its coin back only when colorblind mode flips; ours follows.
    money.GoldButton.coin:SetAtlas("coin-gold")
    MoneyFrame_Update(money, 10000)
    T.truthy(tostring(money.GoldButton.coin:GetTexture()):find("coin-gold.png", 1, true), "ours again after the game's redraw")
    T.isnil(stub.skins.Kit.ShellOf(money.GoldButton), "no button look on it")
    T.eq(coin:GetAlpha(), 1, "a coin beside an amount isn't button art")
    T.isnil(stub.skins.Kit.ShellOf(loose))
    -- A money input that isn't forbidden (the auction house's): our boxes and coins.
    local input = CreateFrame("Frame", nil, f)
    for _, c in ipairs({ "gold", "silver", "copper" }) do
        local box = CreateFrame("EditBox", nil, input)
        box.Left, box.Right, box.Middle = box:CreateTexture(), box:CreateTexture(), box:CreateTexture()
        box.texture = box:CreateTexture()
        box.texture:SetAtlas("coin-" .. c)
        input[c] = box
    end
    Kit.Auto(f)
    for _, c in ipairs({ "gold", "silver", "copper" }) do
        T.truthy(tostring(input[c].texture:GetTexture()):find("coin-" .. c .. ".png", 1, true), "our " .. c .. " coin in its box")
        T.truthy(Kit.InputOf(input[c]), "the " .. c .. " box in our text box look")
    end
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

T.test("skins: a list with no view yet is left until its rows come, with no error", function()
    login()
    local Kit = stub.skins.Kit
    local box = list(UIParent)
    box.rows[1] = CreateFrame("Frame", nil, box)
    local view = box.view
    box.view = nil
    local calls = 0
    Kit.EachRow(box, function() calls = calls + 1 end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(calls, 0)
    box.view = view
    box:Update()
    stub.RunTimers()
    T.eq(calls, 1, "its rows done once the list fills")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The players' stack: a window's walk (Kit.Auto) reaches a list whose view
-- isn't set yet, as the macro window's lists are right after /m.
T.test("skins: a window walk past a list with no view yet makes no error", function()
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    local box = list(f)
    box.ScrollTarget = CreateFrame("Frame", nil, box)
    box.rows[1] = button(nil, box.ScrollTarget)
    local view = box.view
    box.view = nil
    Kit.Auto(f)
    for _ = 1, 10 do stub.RunOnUpdate(Kit.walker, 1 / 60) end
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    box.view = view
    box:Update()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(Kit.ShellOf(box.rows[1]), "its rows styled once the list fills")
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
    local b = TradeFrameTradeButton
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

-- TaxiFrame as the game builds it (dumped from a client): a 590 x 608 window, the map
-- drawn into InsetBg (4 px from the left, 6 from the right and bottom, under a 24 px
-- strip, 580 x 580), the route map anchored to InsetBg's corners and each flight point
-- to its bottom left, the title and the X in the window's corners.
T.test("skins: the flight map's title and X sit where our windows have them, with the same room round the map", function()
    local f, route, button, title, close
    login(function()
        f = CreateFrame("Frame", "TaxiFrame", UIParent)
        f:SetSize(590, 608)
        f.InsetBg = f:CreateTexture("TaxiFrameInsetBg")
        f.InsetBg:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -24)
        f.InsetBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
        f.InsetBg:SetSize(580, 580)   -- the fake game has no layout
        f.Bg = f:CreateTexture()
        title = f:CreateFontString()
        f.TitleText = title
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -6)
        title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -6)
        close = CreateFrame("Button", nil, f)
        f.CloseButton = close
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 3)
        route = CreateFrame("Frame", "TaxiRouteMap", f)
        route:SetPoint("TOPLEFT", f.InsetBg, "TOPLEFT", 0, 0)
        route:SetPoint("BOTTOMRIGHT", f.InsetBg, "BOTTOMRIGHT", 0, 0)
        button = CreateFrame("Button", "TaxiButton1", f)
        button:SetPoint("CENTER", f.InsetBg, "BOTTOMLEFT", 248, 434)
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Win = DaylightUI.Win
    local m = 12
    local function pointOf(frame, name)
        for i = 1, frame:GetNumPoints() do
            local p, rel, rp, x, y = frame:GetPoint(i)
            if p == name then return rel, rp, x, y end
        end
    end
    -- The map has the same room on every side: the header over it, the edges round it.
    local rel, rp, x, y = pointOf(f.InsetBg, "TOPLEFT")
    T.eq(rel, f); T.eq(x, m, "left"); T.eq(-y, Win.COMPACT + m, "under the header, with the room")
    rel, rp, x, y = pointOf(f.InsetBg, "BOTTOMRIGHT")
    T.eq(rel, f); T.eq(-x, m, "right"); T.eq(y, m, "bottom")
    T.eq(f:GetWidth(), m + 580 + m, "the window grew to make the room")
    T.eq(f:GetHeight(), Win.COMPACT + m + 580 + m)
    -- The route and the flight points still hang from the map, untouched.
    rel, rp, x, y = pointOf(route, "TOPLEFT")
    T.eq(rel, f.InsetBg); T.eq(x, 0); T.eq(y, 0)
    rel, rp, x, y = pointOf(button, "CENTER")
    T.eq(rel, f.InsetBg, "the flight point is still on the map"); T.eq(rp, "BOTTOMLEFT"); T.eq(x, 248); T.eq(y, 434)
    -- The title and the X where every window has them.
    rel, _, x, y = pointOf(close, "TOPRIGHT")
    T.eq(rel, f); T.eq(x, Win.CLOSE_X); T.eq(y, Win.CloseY(true), "level with the title")
    T.eq(close:GetWidth(), DaylightUI.Widgets.CLOSE, "the same size")
    rel, _, x, y = pointOf(title, "TOPLEFT")
    T.eq(rel, f); T.eq(x, Win.EDGE); T.eq(y, Win.TITLE_Y)
    -- Opening it again changes nothing: no growing, nothing moved twice.
    for _ = 1, 3 do f:Hide(); f:Show(); stub.RunTimers() end
    T.eq(f:GetWidth(), m + 580 + m, "the same width after opening it again")
    T.eq(f:GetHeight(), Win.COMPACT + m + 580 + m)
    rel, rp, x, y = pointOf(f.InsetBg, "TOPLEFT")
    T.eq(x, m); T.eq(-y, Win.COMPACT + m)
    -- The game sets the window's size again: the room is made again, from the same map.
    f:SetSize(590, 608)
    f:Hide(); f:Show(); stub.RunTimers()
    T.eq(f:GetWidth(), m + 580 + m, "the room made again")
    T.eq(f:GetHeight(), Win.COMPACT + m + 580 + m)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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

T.test("skins: the game's quest window keeps its dark text after the map lit the same text", function()
    login(function()
        DaylightUIDB.modules.Skins = { packs = { npc = false } }   -- the game's quest window undressed
        local map = window("WorldMapFrame")
        local qm = CreateFrame("Frame", "QuestMapFrame", map)
        qm.DetailsFrame = CreateFrame("Frame", nil, qm)
        _G.QuestMapFrame_ShowQuestDetails = function() end
        -- The game's rule (QuestInfo.lua, forever): the shared quest text moves to
        -- whichever window shows it, and its colors are set again only when the
        -- material changes. Map pages pass no material.
        _G.QuestInfoFrame = CreateFrame("Frame", "QuestInfoFrame", UIParent)
        _G.GetMaterialTextColors = function(material)
            if material == "Stone" then return { 1, 1, 1 }, { 1, 0.8, 0 } end
            return { 0.18, 0.12, 0.06 }, { 0, 0, 0 }
        end
        _G.QuestInfo_Display = function(_, parent, _, material)
            for _, n in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionText" }) do _G[n]:SetParent(parent) end
            if QuestInfoFrame.material ~= material then
                QuestInfoFrame.material = material
                local text, title = GetMaterialTextColors(material)
                QuestInfoTitleHeader:SetTextColor(title[1], title[2], title[3])
                QuestInfoDescriptionText:SetTextColor(text[1], text[2], text[3])
            end
        end
    end)
    WorldMapFrame:Show()
    stub.RunTimers()
    local body, title = QuestInfoDescriptionText, QuestInfoTitleHeader
    -- A quest opened on the map: light text there.
    QuestInfo_Display(nil, QuestMapFrame.DetailsFrame)
    T.truthy(body.__textColor[1] > 0.8, "light on the map")
    -- Then one from an NPC, twice (same material, so the game paints only once).
    QuestFrame:Show()
    QuestInfo_Display(nil, QuestFrame, nil, "Parchment")
    T.eq(body.__textColor[1], 0.18, "the game's dark ink in its own window")
    T.eq(title.__textColor[1], 0, "and its dark title")
    QuestInfo_Display(nil, QuestFrame, nil, "Parchment")
    -- The skin runs again (a /reload, a repaint, the map shown again).
    WorldMapFrame:Hide(); WorldMapFrame:Show()
    stub.skins.Kit.RepaintSoon(); stub.RunTimers()
    stub.skins.Kit.RelightIn(QuestFrame, 3)
    T.eq(body.__textColor[1], 0.18, "still the game's dark ink")
    T.eq(title.__textColor[1], 0, "still its dark title")
    -- Back on the map, light again.
    QuestInfo_Display(nil, QuestMapFrame.DetailsFrame)
    T.truthy(body.__textColor[1] > 0.8, "light on the map again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A roll popup as the game's template makes it (tests/rollworld.lua).
local function rollPopup()
    require("rollworld").GameFrames()
    local roll = _G.GroupLootFrame1
    roll.rollID = 7
    return roll
end

T.test("skins: a loot roll popup gets our look: quality line and icon outline, the buttons in a row, our timer", function()
    local roll
    local S = login(function()
        -- This skin dresses the game's popups only with Daylight UI's roll window off.
        DaylightUIDB.modules.Skins = { rolls = { enabled = false } }
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

-- The game's NewRecipeLearnedAlertFrameTemplate: an unnamed gold atlas, a round
-- profession icon (masked by the game on every SetUp), Title and Name.
T.test("skins: the new recipe toast wears the window look, its gold art gone and its icon kept", function()
    local S = login(function()
        _G.NewRecipeLearnedAlertSystem = {}
        _G.AlertFrame_ShowNewAlert = function(f) f:Show() end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = S.Kit
    local t = CreateFrame("Button", nil, UIParent)
    t:SetSize(312, 89)
    t.queue = NewRecipeLearnedAlertSystem
    local art = t:CreateTexture(nil, "BACKGROUND"); art:SetAtlas("recipetoast-bg", true)
    t.Icon = t:CreateTexture(nil, "BACKGROUND"); t.Icon:SetTexture("cooking")
    t.glow, t.shine = t:CreateTexture(nil, "OVERLAY"), t:CreateTexture(nil, "OVERLAY")
    t.Title, t.Name = t:CreateFontString(), t:CreateFontString()
    t.Title:SetText("New Recipe Learned!"); t.Name:SetText("Seasoned Wolf Kabob")
    AlertFrame_ShowNewAlert(t)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(art:GetAlpha(), 0, "the gold toast gone")
    T.truthy(Kit.Erased(art), "erased for good, as the loot toast's background")
    T.truthy(Kit.Erased(t.glow) and Kit.Erased(t.shine), "its glow and shine erased")
    T.eq(t.Icon:GetAlpha(), 1, "the profession icon stays")
    local box = S.RecipeToast.boxes[t]
    T.truthy(box and Kit.ShellOf(box), "a window-look box behind it")
    local c = DaylightUI.Style.INK.LABEL
    T.near(select(1, t.Title:GetTextColor()), c[1], 0.01, "the heading tan")
    -- The game reuses it: one box, however many recipes.
    AlertFrame_ShowNewAlert(t)
    T.eq(S.RecipeToast.boxes[t], box, "the same box")
    _G.NewRecipeLearnedAlertSystem, _G.AlertFrame_ShowNewAlert = nil, nil
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

-- The loot window's header sits where every window's does, the rows have the
-- same room on every side, the window is as tall as its rows need, and the bar
-- shows only once they don't fit.
T.test("skins: the loot window's title and X sit where our windows have them, with the same room on every side of the rows", function()
    local LW, f = require("lootworld"), nil
    local S = login(function() f = LW.Install() end)
    local Win, L = DaylightUI.Win, S.LootLayout
    local function pointOf(frame, name)
        for i = 1, frame:GetNumPoints() do
            local p, rel, rp, x, y = frame:GetPoint(i)
            if p == name then return rel, rp, x, y end
        end
    end
    local function corpse(n)
        local out = {}
        for i = 1, n do out[i] = { name = "Linen Cloth " .. i, link = "item:3", quality = 1, icon = 132889 } end
        return out
    end
    LW.Open(f, LW.Corpse())
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local rel, _, x, y = pointOf(f.ClosePanelButton, "TOPRIGHT")
    T.eq(rel, f); T.eq(x, Win.CLOSE_X, "the X where every window has it"); T.eq(y, Win.CloseY(true), "level with the title")
    T.eq(f.ClosePanelButton:GetWidth(), DaylightUI.Widgets.CLOSE, "the same size")
    rel, _, x, y = pointOf(f.TitleContainer.TitleText, "TOPLEFT")
    T.eq(rel, f); T.eq(x, Win.EDGE, "the title on the window's left edge"); T.eq(y, Win.TITLE_Y)
    -- The same room on every side: the list's inset plus the game's padding in it
    -- is MARGIN on the left, the right and the bottom (a row's last 2 px of its
    -- slot are empty), and under the header on top.
    local pad = L.PAD
    local _, _, lx, ly = pointOf(f.ScrollBox, "TOPLEFT")
    local _, _, rx, ry = pointOf(f.ScrollBox, "BOTTOMRIGHT")
    T.eq(lx + pad, L.MARGIN, "left")
    T.eq(-rx + pad, L.MARGIN, "right")
    T.eq(ry + pad + L.ROW_GAP, L.MARGIN, "bottom")
    T.eq(-ly + pad - L.HEAD, L.MARGIN, "top, under the header")
    -- Tall enough for the rows and no more: 4 rows, 12 of padding, the list's insets.
    local n = #LW.Corpse()
    local rows = n * L.ROW_SLOT + (n - 1) * L.SLOT_GAP + 2 * pad
    T.eq(f:GetHeight(), -ly + ry + rows + 0, "as tall as the rows need")
    T.falsy(f.ScrollBar:IsShown(), "everything fits: no bar")
    -- Rows keep their slots but draw shorter. The icon is smaller and in the
    -- middle, clear of the row's own outline, the name sits below the rarity.
    for _, row in ipairs(f.ScrollBox.rows) do
        T.eq(row:GetHeight(), L.ROW_SLOT - L.ROW_GAP, "a row draws shorter than its slot")
        local p, rrel, _, ix, iy = row.Item:GetPoint(1)
        T.eq(p, "LEFT"); T.eq(rrel, row); T.eq(ix, L.ITEM_X, "the icon clear of the row's edge"); T.eq(iy, 0, "in the middle")
        T.eq(row.Item:GetWidth(), L.ICON, "smaller, so its outline clears the row's")
        -- The quality outline sticks out ~2.5 px past the button each side.
        T.truthy((row:GetHeight() - row.Item:GetHeight() - 5) / 2 >= 4, "room above and below the icon's outline")
        for _, k in ipairs({ "MARGIN", "HEAD", "PAD", "ROW_GAP", "ICON", "ITEM_X", "TEXT_GAP", "TEXT_DROP", "TAG_X", "TAG_Y", "BAR_W" }) do
            T.eq(type(L[k]), "number", "the layout number " .. k)
        end
        T.eq(L.TAG_X, -10); T.eq(L.TAG_Y, -5)
        local _, nrel, _, nx, ny = row.Text:GetPoint(1)
        T.eq(nrel, row.Item); T.eq(nx, L.TEXT_GAP, "the name clear of the icon")
        if row.QualityText then
            T.eq(ny, -L.TEXT_DROP, "the name below the middle")
            local tp, trel, _, tx, ty = row.QualityText:GetPoint(1)
            T.eq(tp, "TOPRIGHT"); T.eq(trel, row); T.eq(tx, L.TAG_X); T.eq(ty, L.TAG_Y, "the rarity in the corner")
        else
            T.eq(ny, 0, "coin: its one line level with the icon")
        end
    end
    -- A name that wraps to two lines is centered in the row, not dropped, or its
    -- second line would touch the row's bottom edge. A coin row has no rarity.
    LW.Close(f); stub.RunTimers()
    LW.Open(f, { { name = string.rep("x", 40), link = "item:3", quality = 0, icon = 132889 } })
    stub.RunTimers()
    local long = f.ScrollBox.rows[1]
    T.eq(long.Text:GetStringHeight(), 30, "the name wraps")
    local _, _, _, _, longY = long.Text:GetPoint(1)
    T.eq(longY, 0, "two lines: centered in the row")
    -- Its right edge stops short of the rarity in the corner, which it shares a height with.
    local tagW = long.QualityText:GetStringWidth()
    local nameLeft = L.ITEM_X + L.ICON + L.TEXT_GAP
    T.truthy(nameLeft + long.Text:GetWidth() <= long:GetWidth() + L.TAG_X - tagW, "a two-line name ends before the rarity")
    -- The button answers over the row's whole height, not just the icon's 30 px.
    local hit = long.Item.__hitRect
    T.truthy(hit, "the item button's hit area was set")
    T.eq(long.Item:GetHeight() - hit[3] - hit[4], long:GetHeight(), "it reaches the row's top and bottom")
    -- And across its whole width: hovering or clicking the name or the empty part of the
    -- row takes the item and lights the row, not only the icon.
    T.eq(hit[1], -L.ITEM_X, "from the row's left edge")
    T.eq(long.Item:GetWidth() - hit[1] - hit[2], long:GetWidth(), "to its right edge")
    -- The row's width changes (the bar showing or hiding): the hit area follows.
    long:SetWidth(long:GetWidth() - 14)
    local resized = long:GetScript("OnSizeChanged")
    T.truthy(resized, "the row's size is watched")
    resized(long, long:GetWidth(), long:GetHeight())
    T.eq(long.Item:GetWidth() - long.Item.__hitRect[1] - long.Item.__hitRect[2], long:GetWidth(), "still to its right edge")
    LW.Close(f); stub.RunTimers()
    LW.Open(f, LW.Corpse())
    stub.RunTimers()
    local one = f.ScrollBox.rows[2]
    local _, _, _, _, oneY = one.Text:GetPoint(1)
    T.eq(oneY, -L.TEXT_DROP, "one line: below the rarity again")
    T.eq(one.Text:GetWidth(), 150, "and the game's own width again")
    -- Nothing keeps changing while it sits there.
    local height = f:GetHeight()
    for _ = 1, 3 do f.ScrollBox:TriggerEvent("OnUpdate"); stub.RunTimers() end
    T.eq(f:GetHeight(), height, "the same height after more updates")
    _, _, lx, ly = pointOf(f.ScrollBox, "TOPLEFT")
    T.eq(-ly + pad - L.HEAD, L.MARGIN, "and the list stays where it is")
    -- The game lays a row out again at its own height: it is shortened again.
    f.ScrollBox.rows[1]:SetHeight(L.ROW_SLOT)
    f.ScrollBox:TriggerEvent("OnUpdate"); stub.RunTimers()
    T.eq(f.ScrollBox.rows[1]:GetHeight(), L.ROW_SLOT - L.ROW_GAP, "shortened again")
    -- A smaller corpse: the game gives its own height, ours follows the rows.
    LW.Close(f); stub.RunTimers()
    LW.Open(f, corpse(1))
    stub.RunTimers()
    T.eq(f:GetHeight(), L.Plan(1, f.panelMaxHeight).height, "one row: as tall as one row needs")
    T.falsy(f.ScrollBar:IsShown())
    -- Four rows still fit under the game's maximum, five don't: then the list
    -- scrolls, the bar shows and the right side leaves room for it.
    T.eq(L.Plan(4, f.panelMaxHeight).scrolls, false, "four rows fit")
    T.eq(L.Plan(5, f.panelMaxHeight).scrolls, true, "five don't")
    -- Exactly five: the game sizes the window for them and hides its bar, but ours
    -- scroll, so the bar must be shown (not just made opaque).
    LW.Close(f); stub.RunTimers()
    LW.Open(f, corpse(5))
    stub.RunTimers()
    T.falsy(L.Plan(5, f.panelMaxHeight).height < f.panelMaxHeight and false, "five rows reach the maximum")
    T.truthy(f.ScrollBar:IsShown(), "five rows scroll here: the bar shows though the game hid it")
    T.eq(f.ScrollBar:GetAlpha(), 1)
    LW.Close(f); stub.RunTimers()
    LW.Open(f, corpse(6))
    stub.RunTimers()
    T.eq(f:GetHeight(), f.panelMaxHeight, "never taller than the game's own maximum")
    T.truthy(f.ScrollBar:IsShown(), "the rows scroll: the bar shows")
    _, _, rx, ry = pointOf(f.ScrollBox, "BOTTOMRIGHT")
    T.eq(-rx + pad, L.BAR_INSET + L.BAR_W + L.BAR_GAP, "the rows stop short of the bar")
    local brel, brp, bx, by = pointOf(f.ScrollBar, "TOPLEFT")
    T.eq(brel, f); T.eq(brp, "TOPRIGHT"); T.eq(bx, -(L.BAR_INSET + L.BAR_W), "the bar near the window's right edge")
    T.eq(by, -(L.HEAD + L.MARGIN), "level with the rows' top")
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
    stub.Load({ skins = true, before = function() world(); QuestFrame:Hide() end })
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
        local m = CreateFrame("Button", "ShardTransferImminentMinimizeButton", UIParent)
        m:SetSize(24, 24)
        m.red = m:CreateTexture()
        m.red:SetAtlas("RedButton-Expand")
        m:SetNormalTexture(m.red)
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, M, f = stub.skins.Kit, DaylightUI.Motion, ShardTransferImminentFrame
    T.truthy(Kit.ShellOf(f), "skinned")
    local red = ShardTransferImminentMinimizeButton.red
    T.falsy(red:IsShown() and red:GetAlpha() > 0, "the game's red arrow is gone from the minimize button")
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

-- The controller's focus glow on the game menu (FrameGlowMixin): its piece
-- around the dialog header framed nothing once the header was gone, and the
-- game set the glow's opacity and color only when the setting changed, so after
-- a login it showed at full strength even at 0, in the art's own color.
T.test("skins: the game menu's controller focus glow has no header piece and keeps its opacity and color", function()
    local getCVar, opacity = _G.GetCVar, "0"
    _G.GetCVar = function(k)
        if k == "GamepadFocusStateOpacity" then return opacity end
        if k == "GamepadFocusStateColor" then return "3" end
    end
    login(function()
        local f = window("GameMenuFrame")
        f.TitleContainer = nil
        f.Header = CreateFrame("Frame", nil, f)
        f.Header.Text = f.Header:CreateFontString()
        f.FrameGlow = CreateFrame("Frame", nil, f)
        f.FrameGlow.GlowTexture = f.FrameGlow:CreateTexture()
        f.FrameGlow.HeaderGlowTexture = f.FrameGlow:CreateTexture()
        f.FrameGlow:Hide()
        f:Hide()
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local glow = GameMenuFrame.FrameGlow
    T.eq(glow.HeaderGlowTexture:GetAlpha(), 0, "no outline where the game's header was")
    T.eq(glow.GlowTexture:GetAlpha(), 1, "the window's own glow stays")
    T.eq(glow:GetAlpha(), 0, "the saved opacity, from the start")
    local r, g, b = glow.GlowTexture:GetVertexColor()
    T.eq(r, 0.3); T.eq(g, 0.5); T.eq(b, 1, "the saved Focus Color (blue), from the start")
    opacity = "0.6"
    GameMenuFrame:Show(); glow:Show()
    T.eq(glow:GetAlpha(), 0.6, "read again as it shows")
    _G.GetCVar = getCVar
end)

-- The world map keeps its focus glow on its BorderFrame (FocusFrameParent in
-- Blizzard_WorldMap.xml), so it stayed at full strength with Focus Opacity at 0.
T.test("skins: a glow kept on a child (the world map's BorderFrame) keeps the opacity too", function()
    local getCVar = _G.GetCVar
    _G.GetCVar = function(k) if k == "GamepadFocusStateOpacity" then return "0" end end
    login()
    local Kit = stub.skins.Kit
    local f = CreateFrame("Frame", nil, UIParent)
    f.FocusFrameParent = "BorderFrame"
    f.BorderFrame = CreateFrame("Frame", nil, f)
    f.BorderFrame.FrameGlow = CreateFrame("Frame", nil, f.BorderFrame)
    f.BorderFrame.FrameGlow.GlowTexture = f.BorderFrame.FrameGlow:CreateTexture()
    Kit.FocusGlow(f)
    T.eq(f.BorderFrame.FrameGlow:GetAlpha(), 0, "the saved opacity on the child's glow")
    _G.GetCVar = getCVar
end)

-- Glows on windows no skin dresses (the minimap's tracking menu) kept
-- full strength too. Every glow registers for the opacity setting with
-- CVarCallbackRegistry, so they're all found there: at start, and each time the
-- controller's focus moves (a menu's glow is made when it first opens).
T.test("skins: every controller focus glow keeps the saved opacity, made before or after login", function()
    local getCVar, registry, events = _G.GetCVar, _G.CVarCallbackRegistry, _G.EventRegistry
    local listeners = {}
    _G.EventRegistry = { RegisterCallback = function(_, event, fn, owner) listeners[event] = function() fn(owner) end end }
    _G.GetCVar = function(k)
        if k == "GamepadFocusStateOpacity" then return "0" end
        if k == "GamepadFocusStateColor" then return "3" end
    end
    local glows = {}
    _G.CVarCallbackRegistry = { GetCallbacksByEvent = function(_, kind, event)
        if kind == 2 and event == "GamepadFocusStateOpacity" then return glows end
    end }
    local function glow()
        local g = CreateFrame("Frame", nil, UIParent)
        g.GlowTexture = g:CreateTexture()
        g.glowTextures = { g.GlowTexture }
        glows[g] = function() end
        return g
    end
    local early = glow()
    login()
    T.eq(early:GetAlpha(), 0, "a glow made before login")
    local r, g, b = early.GlowTexture:GetVertexColor()
    T.eq(r, 0.3); T.eq(g, 0.5); T.eq(b, 1, "and its saved color")
    local menu = glow()
    T.eq(menu:GetAlpha(), 1, "a menu's glow, made later, starts at full strength")
    T.truthy(listeners["Gamepad.RefreshFrameFocus"], "listens for the controller's focus moving")
    listeners["Gamepad.RefreshFrameFocus"]()
    T.eq(menu:GetAlpha(), 0, "fixed when the controller's focus moves")
    _G.GetCVar, _G.CVarCallbackRegistry, _G.EventRegistry = getCVar, registry, events
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
    local mapSet = {}
    login(function()
        -- The game's EventRegistry: callbacks get their owner first.
        _G.EventRegistry = { RegisterCallback = function(_, event, fn, owner)
            if event == "MapCanvas.MapSet" then mapSet[#mapSet + 1] = function(...) fn(owner, ...) end end
        end }
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
    T.eq(R.frame:GetFrameLevel(), 2001, "just under the game's exploration level")
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
    -- Another map is redrawn for it when the game's canvas announces it, with
    -- nothing polled per frame.
    T.isnil(R.frame:GetScript("OnUpdate"), "no per-frame watcher")
    f.mapID = 947        -- Azeroth: no pieces
    for _, fn in ipairs(mapSet) do fn(947) end
    shown = 0
    for _, r in ipairs({ R.frame:GetRegions() }) do if r:IsShown() then shown = shown + 1 end end
    T.eq(shown, 0)
    DaylightUI:Set("Skins", "mapReveal", false)
    stub.RunTimers()
    T.eq(R.frame:IsShown(), false)
end)

-- The game draws the explored pieces on its exploration pin (MapExplorationPinMixin,
-- one frame at PIN_FRAME_LEVEL_MAP_EXPLORATION's startLevel, tiles on ARTWORK).
-- Two frames at one level draw in no set order, tile by tile, so an explored
-- piece's bright tiles and Daylight UI's dimmed ones overlapping it came out in a
-- different mix on each open: sharp bright squares in the dimmed areas (seen in
-- game in Duskwood, gone after a /reload). The dimmed tiles must sit under the
-- game's, on every map and every open, and still over the map's own art.
T.test("skins: unexplored areas always draw under the game's explored pieces, on every map and open", function()
    local f, defs
    local mapSet = {}
    login(function()
        _G.EventRegistry = { RegisterCallback = function(_, event, fn, owner)
            if event == "MapCanvas.MapSet" then mapSet[#mapSet + 1] = function(...) fn(owner, ...) end end
        end }
        f = window("WorldMapFrame")
        f.ScrollContainer = CreateFrame("ScrollFrame", nil, f)
        f.ScrollContainer.Child = CreateFrame("Frame", nil, f.ScrollContainer)
        f.mapID = 1431   -- Duskwood
        defs = { PIN_FRAME_LEVEL_DEFAULT = { startLevel = 2000, range = 1 },
                 PIN_FRAME_LEVEL_WOW_LABS_AREA = { startLevel = 2001, range = 1 },
                 PIN_FRAME_LEVEL_MAP_EXPLORATION = { startLevel = 2002, range = 1 } }
        f.pinFrameLevelsManager = { definitions = defs }
        _G.C_MapExplorationInfo = { GetExploredMapTextures = function(id)
            -- The Twilight Grove explored; its neighbors' art overlaps it.
            if id == 1431 then return { { textureWidth = 384, textureHeight = 512, offsetX = 298, offsetY = 79,
                fileDataIDs = { 8061711, 8061712, 8061713, 8061714 } } } end
            return {}
        end }
        _G.C_Map = _G.C_Map or {}
        C_Map.GetMapArtLayers = function() return { { tileWidth = 256, tileHeight = 256 } } end
    end)
    local R = stub.skins.MapReveal
    -- The game's own pieces: its detail layer (the map's art) and its exploration
    -- pin, as MapCanvasMixin and MapExplorationPinMixin:ApplyFrameLevel place them.
    local canvas = f.ScrollContainer.Child
    local detail = CreateFrame("Frame", nil, canvas)
    local pin = CreateFrame("Frame", nil, canvas)
    local function gamePin() pin:SetFrameLevel(defs.PIN_FRAME_LEVEL_MAP_EXPLORATION.startLevel) end
    gamePin()
    f:Show()
    DaylightUI:Set("Skins", "mapReveal", true)
    stub.RunTimers()
    local function check(why)
        T.truthy(R.frame:GetFrameLevel() < pin:GetFrameLevel(), why .. ": under the explored pieces ("
            .. R.frame:GetFrameLevel() .. " vs the game's " .. pin:GetFrameLevel() .. ")")
        T.truthy(R.frame:GetFrameLevel() > detail:GetFrameLevel(), why .. ": over the map's own art")
    end
    check("opened")
    for _, id in ipairs({ 1429, 1431, 1436, 1431 }) do   -- Elwynn, Duskwood, Westfall, Duskwood
        f.mapID = id
        for _, fn in ipairs(mapSet) do fn(id) end
        check("map " .. id)
    end
    -- Another addon's pin level put under the exploration level moves it up; the
    -- game's pin follows on its next refresh, and so does the overlay on the next open.
    defs.PIN_FRAME_LEVEL_MAP_EXPLORATION.startLevel = 2003
    f:Hide()
    gamePin()
    f:Show()
    check("reopened after the pin levels moved")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The client draws the game's quest area pin (a Blob) at its own alpha, so it
-- stayed at full strength while the map faded as you moved (seen in game).
T.test("skins: the game's quest area on the world map fades with the map", function()
    local f, blob, fill, border
    login(function()
        f = window("WorldMapFrame")
        blob = CreateFrame("Frame", nil, f)
        blob.SetFillAlpha = function(_, v) fill = v end
        blob.SetBorderAlpha = function(_, v) border = v end
        blob:SetScript("OnUpdate", function() end)    -- QuestBlobPinMixin:OnUpdate
        f.EnumeratePinsByTemplate = function(_, template)
            local done = template ~= "QuestBlobPinTemplate"
            return function() if not done then done = true; return blob end end
        end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    f:Show()
    local tick = blob:GetScript("OnUpdate")
    f:SetAlpha(0.5)                                    -- the game's map fade while moving
    tick(blob, 0.016)
    T.eq(fill, 64, "half faded map: half the fill")
    T.eq(border, 96, "and half the outline")
    f:SetAlpha(1)
    tick(blob, 0.016)
    T.eq(fill, 128, "back with the map")
    T.eq(border, 192)
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
    P.MapSet()   -- the game's "MapCanvas.MapSet"
    T.eq(#shown(), 0)
    -- Forever's new dungeons have no corpse point. The addon's own list puts
    -- Excavation Site on the Wetlands, using the game's name when it has one.
    local info = C_Map.GetMapInfo
    C_Map.GetMapInfo = function(id)
        if id == 1437 then return { mapType = 3, name = "Wetlands" } end
        return info(id)
    end
    f.mapID = 1437
    P.MapSet()   -- the game's "MapCanvas.MapSet"
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

-- The zone under the mouse on a continent map gets its level range after its
-- name, colored like the game's own label (MapLevels.lua). The game writes the
-- name into its area label only when it changes.
T.test("skins: a hovered zone on the world map shows its level range, colored for you", function()
    local label
    login(function()
        local f = window("WorldMapFrame")
        label = CreateFrame("Frame", nil, f)
        label.Name = label:CreateFontString(nil, "OVERLAY")
        f.dataProviders = { [{ Label = label }] = true }
        _G.C_Map = _G.C_Map or {}
        C_Map.GetMapInfo = function(id)
            if id == 1437 then return { mapType = 3, name = "Wetlands" } end
        end
        _G.GetQuestDifficultyColor = function(level)
            local d = level - UnitLevel("player")
            if d >= 5 then return QuestDifficultyColors.impossible end
            if d >= -2 then return QuestDifficultyColors.difficult end
            return QuestDifficultyColors.standard
        end
        stub.SetUnits({ player = { level = 12 } })
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local run = function() label:GetScript("OnUpdate")(label, 0) end
    label.Name:SetText("Wetlands")
    run()
    T.eq(label.Name:GetText(), "Wetlands|cffff1a1a (20-30)|r", "red at level 12")
    run()
    T.eq(label.Name:GetText(), "Wetlands|cffff1a1a (20-30)|r", "written once, not again")
    -- Inside the range it's yellow, as the game's own label does it.
    stub.SetUnits({ player = { level = 25 } })
    stub.FireEvent("PLAYER_LEVEL_UP", 25)
    run()
    T.eq(label.Name:GetText(), "Wetlands|cffffd100 (20-30)|r", "yellow in range")
    -- A name without a range, or none, is left alone.
    label.Name:SetText("Ironforge")
    run()
    T.eq(label.Name:GetText(), "Ironforge")
    label.Name:SetText("")
    run()
    T.eq(label.Name:GetText(), "")
    -- Switched off, the game's own name comes back.
    label.Name:SetText("Wetlands")
    run()
    DaylightUI:Set("Skins", "mapLevels", false)
    stub.RunTimers()
    T.eq(label.Name:GetText(), "Wetlands")
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

-- Clicking a guild member opens their card (GuildRoster.lua DisplayMember). On
-- the way the game resizes the card, shows or hides the rank menu and enables or
-- disables Remove, then reads the member's details, which can be secret: only
-- the game's own untainted code may compare them. Daylight UI code on any piece
-- inside the card ran first and tainted the rest, so the card never opened and
-- promote, demote and remove were out of reach.
T.test("skins: no Daylight UI code runs inside the guild member card while the game fills it", function()
    local f, memberCard
    login(function()
        f = guildWindow()
        memberCard = f.GuildMemberDetailFrame
        -- GuildRoster.xml: CommunitiesGuildMemberDetailFrameTemplate's pieces.
        memberCard.CloseButton = CreateFrame("Button", nil, memberCard)
        local xArt = memberCard.CloseButton:CreateTexture()
        function memberCard.CloseButton:GetNormalTexture() return xArt end
        memberCard.RemoveButton = button(nil, memberCard)
        memberCard.RemoveButton:GetFontString():SetText("Remove")
        memberCard.GroupInviteButton = button(nil, memberCard)
        memberCard.GroupInviteButton:GetFontString():SetText("Group Invite")
        local dd = CreateFrame("Button", nil, memberCard)
        dd:SetSize(120, 24)
        dd.Text = dd:CreateFontString()
        dd.Arrow, dd.Background = dd:CreateTexture(), dd:CreateTexture()
        memberCard.RankDropdown = dd
        memberCard.OfficerNoteBackground = CreateFrame("Frame", nil, memberCard)
        memberCard.Name = memberCard:CreateFontString()
        memberCard:Hide()
        stub.loadedAddOns.Blizzard_Communities = true
    end)
    f:Show()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(memberCard), "the card still a panel of ours")
    T.truthy(Kit.ButtonOf(memberCard.RemoveButton), "Remove still our button")
    T.truthy(Kit.ButtonOf(memberCard.GroupInviteButton), "Group Invite still our button")
    local inside = stub.AddonScriptsInside(memberCard, { "OnShow", "OnHide", "OnSizeChanged", "OnEnable", "OnDisable" })
    T.eq(#inside, 0, "Daylight UI code inside the member card: " .. table.concat(inside, ", "))
    local own = memberCard:GetScript("OnSizeChanged")
    T.falsy(own and stub.IsAddonHandler(own), "nor on the card's own resize")

    -- The quiet buttons still follow the game while the card is up.
    memberCard:Show()
    memberCard.RemoveButton:Disable()
    Kit.quietPoller:GetScript("OnUpdate")(Kit.quietPoller, 0.016)
    T.truthy(Kit.ButtonOf(memberCard.RemoveButton).off, "Remove grays out when the game disables it")
    memberCard:Hide()
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
    login()
    local Kit = stub.skins.Kit
    local slot = CreateFrame("Button", nil, UIParent)
    slot.icon = slot:CreateTexture()
    slot.IconBorder = slot:CreateTexture()
    slot.IconBorder:SetVertexColor(0.64, 0.21, 0.93)
    slot.IconBorder:Show()
    Kit.Item(slot)
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
    local title = TradeFrame.TitleContainer.TitleText
    TradeFrame:Hide()
    title:SetTextColor(1, 0.82, 0)                   -- the game, while it was closed
    TradeFrame:Show()
    T.truthy(title.__textColor[3] > 0.6, "light again, not the game's gold")
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
        for _, c in ipairs({ m:GetParent():GetChildren() }) do if Kit.ShellOf(c) then ours = true end end
        T.truthy(ours, "our look behind it")
        T.eq(m.text.__textColor[1], 0.5, "the game's colors kept")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The barber shop hides UIParent and makes its own frame the top one
-- (SetAlternateTopLevelParent, Blizzard_BarberShopUI). Its menus have no parent,
-- so a look parented to UIParent was hidden and the list drew over the rows.
T.test("skins: a menu opened in the barber shop gets its look on the barber shop's frame", function()
    local callbacks = {}
    login(function()
        _G.EventRegistry = {
            RegisterCallback = function(_, event, fn, owner) callbacks[event] = function(...) fn(owner, ...) end end,
        }
    end)
    local Kit = stub.skins.Kit
    local barber = CreateFrame("Frame", "BarberShopFrame")
    _G.GetAppropriateTopLevelParent = function() return barber end
    UIParent:Hide()
    local menu = CreateFrame("Frame")                  -- the game's menus have no parent
    menu.bg = menu:CreateTexture()
    callbacks["MenuProxy.OnShow"](menu)
    stub.RunTimers()
    local holder
    for _, c in ipairs({ barber:GetChildren() }) do if Kit.ShellOf(c) then holder = c end end
    local seen = holder and holder:IsVisible()
    UIParent:Show()
    _G.GetAppropriateTopLevelParent = nil
    T.truthy(holder, "our look on the barber shop's frame, not the hidden UIParent")
    T.truthy(seen, "and seen")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A row's focus glow (FocusEffectTemplates) can have secret anchoring, and
-- then its size getters return secret numbers, as the API docs say. A player
-- got "attempt to compare local 'h' (a secret number value)" 26 times.
T.test("skins: a menu row whose glow has a secret height is checked without comparing it", function()
    local callbacks = {}
    login(function()
        _G.EventRegistry = {
            RegisterCallback = function(_, event, fn, owner) callbacks[event] = function(...) fn(owner, ...) end end,
        }
    end)
    local Kit = stub.skins.Kit
    local menu = CreateFrame("Frame", nil, UIParent)
    menu.bg = menu:CreateTexture()
    local row = CreateFrame("Frame", nil, menu)
    row.GlowTexture = row:CreateTexture()
    row.GlowTexture:SetTexture(130841)
    function row.GlowTexture:GetHeight() return stub.Secret(12) end
    function row.GlowTexture:GetWidth() return stub.Secret(120) end
    callbacks["MenuProxy.OnShow"](menu)
    stub.RunTimers()
    local holder
    for _, c in ipairs({ menu:GetParent():GetChildren() }) do if Kit.ShellOf(c) then holder = c end end
    T.truthy(holder, "our look behind it")
    local tick = holder.__scripts and holder.__scripts.OnUpdate
    T.truthy(tick, "it watches the menu")
    -- In game a secret number answers type() with "number" and only errors
    -- when compared. The fake secret is a table, so make it answer like the
    -- game's for this one look.
    local realType, realCheck = type, issecretvalue
    local function fake(v) return realType(v) == "table" and rawget(v, "__secret") == true end
    _G.issecretvalue = fake
    _G.type = function(v)
        if fake(v) and realType(rawget(v, "__value")) == "number" then return "number" end
        return realType(v)
    end
    local ok, err = pcall(tick, holder, 0.2)
    _G.type, _G.issecretvalue = realType, realCheck
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("skins: a unit menu's rows, tick, arrow and raid icons take our look", function()
    local callbacks = {}
    login(function()
        _G.EventRegistry = {
            RegisterCallback = function(_, event, fn, owner) callbacks[event] = function(...) fn(owner, ...) end end,
        }
    end)
    local function atlas(tex, name)
        function tex:GetAtlas() return name end
        return tex
    end
    local menu = CreateFrame("Frame", nil, UIParent)
    menu.bg = menu:CreateTexture()
    menu.bg:SetAtlas("common-dropdown-bg")
    local title = CreateFrame("Frame", nil, menu)
    title.text = title:CreateFontString()
    title.text:SetTextColor(1, 0.82, 0)                 -- NORMAL_FONT_COLOR, a heading
    local plain = CreateFrame("Button", nil, menu)
    plain.text = plain:CreateFontString()
    plain.text:SetTextColor(1, 1, 1)
    plain.arrow = plain:CreateTexture()
    plain.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    plain.highlight = plain:CreateTexture()
    plain.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local kept = CreateFrame("Button", nil, menu)
    kept.text = kept:CreateFontString()
    kept.text:SetTextColor(0, 0.44, 0.87)               -- a class color
    local off = CreateFrame("Button", nil, menu)
    off.text = off:CreateFontString()
    off.text:SetTextColor(0.5, 0.5, 0.5)
    local function marker(parent, coords, color)
        local row = CreateFrame("Button", nil, parent)
        row.leftTexture1 = atlas(row:CreateTexture(), "common-dropdown-tickradial")
        row.leftTexture2 = atlas(row:CreateTexture(), "common-dropdown-icon-radialtick-yellow")
        row.text = row:CreateFontString()
        row.text:SetTextColor(color[1], color[2], color[3])
        row.icon = row:CreateTexture()
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        row.icon:SetSize(16, 16)
        return row
    end
    local skull = marker(menu, { 0.75, 1, 0.25, 0.5 }, { 1, 1, 1 })       -- index 8, and the chosen one
    local circle = marker(menu, { 0.25, 0.5, 0, 0.25 }, { 0.98, 0.57, 0 }) -- index 2
    circle.leftTexture2:Hide()
    local box = CreateFrame("Button", nil, menu)
    box.leftTexture1 = atlas(box:CreateTexture(), "common-dropdown-ticksquare")
    box.leftTexture2 = atlas(box:CreateTexture(), "common-dropdown-icon-checkmark-yellow")
    box.text = box:CreateFontString()
    box.text:SetTextColor(1, 1, 1)
    local rule = CreateFrame("Frame", nil, menu)
    rule.divider = rule:CreateTexture()
    rule.divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    -- CreateDivider never sets frame.divider, and in game GetTexture() is a file id.
    local bare = CreateFrame("Frame", nil, menu)
    bare.line = bare:CreateTexture()
    bare.line:SetTexture(130841)
    bare.line:SetHeight(13)
    _G.RAID_TARGET_1 = "Estrella"
    local star = CreateFrame("Button", nil, menu)
    star.text = star:CreateFontString()
    star.text:SetText("Estrella")
    star.text:SetTextColor(1, 1, 1)
    star.icon = star:CreateTexture()
    star.icon:SetTexture(137010)
    star.icon:SetTexCoord(0, 0.25, 0, 0.25)
    star.icon:SetSize(16, 16)
    -- The row is named after the marker, and the hover covers the whole row.
    star.highlight = star:CreateTexture()
    star.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    star.highlight:SetBlendMode("ADD")
    star.highlight:SetSize(180, 20)
    -- A checkbox row with a small grid icon that is not a raid marker (minimap tracking).
    local track = CreateFrame("Button", nil, menu)
    track.leftTexture1 = atlas(track:CreateTexture(), "common-dropdown-ticksquare")
    track.icon = track:CreateTexture()
    track.icon:SetTexture(424242)
    track.icon:SetTexCoord(0, 0.25, 0, 0.25)
    track.icon:SetSize(16, 16)
    track.text = track:CreateFontString()
    track.text:SetText("Subastador")
    track.text:SetTextColor(1, 1, 1)
    callbacks["MenuProxy.OnShow"](menu)
    stub.RunTimers()
    local Style = DaylightUI.Style
    local ar, ag, ab = Style.Accent()
    local ink = Style.INK.TEXT
    T.eq(menu.bg:GetAlpha(), 0, "the game's background gone")
    T.eq(title.text.__textColor[1], ar, "a gold heading takes the accent")
    T.eq(title.text.__textColor[2], ag)
    T.eq(plain.text.__textColor[1], ink[1], "a white row takes our text")
    T.eq(plain.arrow:GetTexture(), DaylightUI.MEDIA .. "ui-chevron.png")
    T.eq(plain.arrow.__rotation, math.pi / 2, "the chevron points at the submenu")
    T.eq(plain.highlight:GetBlendMode(), "ADD")
    local wash = plain.highlight.__vertex
    T.eq(wash[4], stub.skins.Kit.ROW_PICK, "the row wash uses the accent strength")
    if plain.highlight.__gradient then
        T.eq(wash[1], 1, "a gradient wash stays white")
    else
        T.eq(wash[1], ar, "a flat wash is the accent, not a typed brown")
        T.eq(wash[2], ag)
        T.eq(wash[3], ab)
    end
    T.eq(kept.text.__textColor[2], 0.44, "a class color stays")
    T.eq(off.text.__textColor[1], 0.5, "a disabled row stays gray")
    T.eq(skull.leftTexture1:GetAlpha(), 0, "the empty radio is gone")
    T.eq(skull.leftTexture2:GetTexture(), DaylightUI.MEDIA .. "ui-check.png", "the chosen row gets our tick")
    T.eq(skull.text.__textColor[1], ar, "the chosen row is the accent")
    T.eq(skull.icon:GetTexture(), DaylightUI.MEDIA .. "marker-8.png", "skull uses our marker")
    T.eq(circle.icon:GetTexture(), DaylightUI.MEDIA .. "marker-2.png", "circle uses our marker")
    T.eq(circle.text.__textColor[1], ink[1], "a marker's name is our text, not the game's orange")
    T.eq(box.leftTexture2:GetTexture(), DaylightUI.MEDIA .. "ui-check.png")
    T.eq(box.text.__textColor[1], ink[1], "a ticked checkbox stays body text")
    T.eq(rule.divider:GetTexture(), "Interface\\Buttons\\WHITE8x8", "the divider is a plain line")
    T.eq(bare.line:GetTexture(), "Interface\\Buttons\\WHITE8x8", "a divider with no .divider field still gets the line")
    T.eq(bare.line:GetHeight(), 1)
    T.eq(star.icon:GetTexture(), DaylightUI.MEDIA .. "marker-1.png", "a raid icon known by file id uses our marker")
    _G.RAID_TARGET_8 = "Calavera"
    local marked = CreateFrame("Button", nil, menu)
    marked.text = marked:CreateFontString()
    marked.text:SetText("Calavera")
    marked.text:SetTextColor(1, 1, 1)
    marked.icon = marked:CreateTexture()
    marked.icon:SetTexture(137010)
    marked.icon:SetTexCoord(0.75, 1, 0.25, 0.5)
    marked.icon:SetSize(16, 16)
    marked.wash = marked:CreateTexture()
    marked.wash:SetTexture(130722)
    marked.wash:SetAllPoints(marked)
    callbacks["MenuProxy.OnShow"](menu)
    stub.RunTimers()
    T.eq(marked.icon:GetTexture(), DaylightUI.MEDIA .. "marker-8.png", "the small icon stays the marker")
    T.eq(marked.wash:GetTexture(), "Interface\\Buttons\\WHITE8x8", "the row hover is the wash, not the marker")
    T.eq(marked.wash.__vertex[4], stub.skins.Kit.ROW_PICK, "that hover is the same accent as other rows")
    T.eq(star.highlight:GetTexture(), "Interface\\Buttons\\WHITE8x8", "a marker row's hover is the wash, not the icon")
    T.eq(track.icon:GetTexture(), 424242, "a tracking menu's icon is left alone")
    -- The menu pools its textures, so the raid icon can come back still in ADD
    -- blend from an earlier row's hover. It is still the icon, not the hover.
    _G.RAID_TARGET_3 = "Diamante"
    local reused = CreateFrame("Button", nil, menu)
    reused.text = reused:CreateFontString()
    reused.text:SetText("Diamante")
    reused.text:SetTextColor(1, 1, 1)
    reused.icon = reused:CreateTexture()
    reused.icon:SetBlendMode("ADD")
    reused.icon:SetSize(16, 16)
    reused.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    reused.icon:SetSpriteSheetCell(3, 4, 4)
    _G.RAID_TARGET_NONE = "Ninguno"
    local none = CreateFrame("Button", nil, menu)
    none.text = none:CreateFontString()
    none.text:SetText("Ninguno")
    none.text:SetTextColor(1, 1, 1)
    none.icon = none:CreateTexture()
    none.icon:SetBlendMode("ADD")
    none.icon:SetSize(16, 16)
    none.icon:SetTexture("")
    callbacks["MenuProxy.OnShow"](menu)
    stub.RunTimers()
    T.eq(reused.icon:GetTexture(), DaylightUI.MEDIA .. "marker-3.png", "a reused raid icon still gets our marker")
    T.eq(reused.icon:GetBlendMode(), "BLEND", "our marker draws plainly, not as a glow")
    T.eq(none.icon:GetTexture(), "", "the None row's empty spot is not painted as a hover box")
    -- A target's menu holds the target's name, a secret, and every size on it
    -- then reads back secret (seen in game). The row's icon sits on one point
    -- (SetPoint "RIGHT", 16 x 16); the hover is pinned to the row on two. The
    -- sheet's file id in game is 137009.
    _G.RAID_TARGET_7 = "Cruz"
    local function secretRow(text, coords)
        local row = CreateFrame("Button", nil, menu)
        row.text = row:CreateFontString()
        row.text:SetText(text)
        row.text:SetTextColor(1, 1, 1)
        row.highlight = row:CreateTexture()
        row.highlight:SetTexture(136810)
        row.highlight:SetBlendMode("ADD")
        row.highlight:SetPoint("TOPLEFT", row)
        row.highlight:SetPoint("BOTTOMRIGHT", row)
        row.icon = row:CreateTexture()
        row.icon:SetPoint("RIGHT")
        row.icon:SetSize(16, 16)
        if coords then
            row.icon:SetTexture(137009)
            row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            row.icon:SetTexture("")
        end
        for _, w in ipairs({ row, row.highlight, row.icon, row.text }) do stub.HeldSecret(w) end
        return row
    end
    local cross = secretRow("Cruz", { 0.5, 0.75, 0.25, 0.5 })
    local blank = secretRow("Ninguno")
    callbacks["MenuProxy.OnShow"](menu)
    stub.RunTimers()
    T.eq(cross.icon:GetTexture(), DaylightUI.MEDIA .. "marker-7.png", "a marker shows on a menu whose sizes are secret")
    T.eq(cross.icon:GetBlendMode(), "BLEND", "and draws plainly, not as a hover glow")
    T.eq(blank.icon:GetTexture(), "", "the None row's empty spot stays empty on that menu")
    T.eq(blank.icon:GetBlendMode(), "BLEND", "and is not lit as a hover box")
    T.eq(cross.highlight:GetTexture(), "Interface\\Buttons\\WHITE8x8", "the row's real hover is still our wash")
    local holder
    for _, c in ipairs({ menu:GetParent():GetChildren() }) do
        if c.ignoreInLayout and c.GetScript and c:GetScript("OnUpdate") then holder = c end
    end
    T.truthy(holder, "our frame watches while the menu stays open")
    T.truthy(holder:GetParent() ~= menu, "our panel is not inside the menu, so it cannot cover the rows")
    menu:SetFrameStrata("TOOLTIP")
    callbacks["MenuProxy.OnShow"](menu)
    stub.RunTimers()
    T.eq(holder:GetFrameStrata(), "FULLSCREEN_DIALOG", "the panel sits under the whole menu")
    box.leftTexture2:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    holder:GetScript("OnUpdate")(holder, 0.016)
    stub.RunTimers()
    T.eq(box.leftTexture2:GetTexture(), "Interface\\Buttons\\UI-CheckBox-Check", "the rows are not walked every frame")
    holder:GetScript("OnUpdate")(holder, 0.1)
    stub.RunTimers()
    T.eq(box.leftTexture2:GetTexture(), DaylightUI.MEDIA .. "ui-check.png", "a checkbox refresh keeps our tick")
    -- A tick rebuilds every row with the game's own font (Compositor.lua,
    -- SetFontStringToDefaults) while the menu stays open. Our font is back in
    -- the same frame, before it is drawn, with the row's color kept.
    T.eq((plain.text:GetFont()), Style.FONT, "the row starts in our font")
    local gameFont = CreateFont("TestMenuGameFont")
    gameFont:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    plain.text:SetFontObject(gameFont)
    plain.text:SetTextColor(0.5, 0.6, 0.7, 1)
    local gameFile = plain.text:GetFont()
    T.truthy(gameFile ~= Style.FONT, "the fake game's default font is not ours")
    holder:GetScript("OnUpdate")(holder, 0.016)
    T.eq((plain.text:GetFont()), Style.FONT, "a refresh's text is back in our font at once")
    T.eq(plain.text.__textColor[2], 0.6, "with the color the game gave it")
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

T.test("window scale: the game's windows follow the Daylight UI scale, a Ctrl + wheel size on top", function()
    stub.Load({ skins = true })
    local f = CreateFrame("Frame", "DemoGamePanel", UIParent)
    _G.UIPanelWindows = _G.UIPanelWindows or {}
    _G.UIPanelWindows.DemoGamePanel = { area = "left" }
    stub.FireEvent("ADDON_LOADED", "Blizzard_Demo")
    stub.RunTimers()
    T.near(f:GetScale(), 1, 1e-6, "at a Daylight UI scale of 1, the game's own size")
    DaylightUI:Set("general", "scale", 0.8)
    stub.RunTimers()
    T.near(f:GetScale(), 0.8, 1e-6, "smaller with the rest of the UI")
    _G.IsControlKeyDown = function() return true end
    f:GetScript("OnMouseWheel")(f, 1)
    T.near(DaylightUI:Get("Skins", "windowScales").DemoGamePanel, 1.05, 1e-6, "the wheel saves its own size")
    T.near(f:GetScale(), 0.84, 1e-6, "its own size times the Daylight UI scale")
    f:SetScale(1)                     -- the game laid its panels out again
    f:Hide(); f:Show()
    T.near(f:GetScale(), 0.84, 1e-6)
    DaylightUI.Movers.ResetAll()
    T.near(f:GetScale(), 0.8, 1e-6, "/dui reset: the Daylight UI scale alone")
    DaylightUI:Set("general", "scale", 1)
    stub.RunTimers()
    T.near(f:GetScale(), 1, 1e-6, "back to 1 with it")
    _G.IsControlKeyDown = nil
    _G.UIPanelWindows.DemoGamePanel = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The loot window is in the game's UIPanelWindows too, but its unlock handle sizes
-- it. Skins start before that handle is made at login, so the window scale must
-- not take it over and set it back to 1 each time it opens.
T.test("window scale: the loot window keeps its handle's size every time it opens", function()
    stub.Load({ skins = true, before = function()
        Enum.EditModeSystem = { LootFrame = 10 }
        DaylightUIDB = { installerSeen = 1e9, general = { scale = 0.9 } }
        _G.UIPanelWindows = _G.UIPanelWindows or {}
        _G.UIPanelWindows.LootFrame = { area = "left", pushable = 0 }
        local f = CreateFrame("Frame", "LootFrame", UIParent)
        f:SetSize(260, 300)
        f:SetPoint("LEFT", UIParent, "LEFT", 16, 116)
        f:Hide()
    end })
    stub.RunTimers()
    local Movers = DaylightUI.Movers
    T.truthy(Movers.Get("game.LootFrame"), "the loot window has its handle")
    Movers.SetPieceScale("game.LootFrame", 0.5)
    T.near(LootFrame:GetScale(), 0.45, 1e-6, "the handle's size on the Daylight UI scale")
    LootFrame:Show()
    T.near(LootFrame:GetScale(), 0.45, 1e-6, "kept as it opens")
    LootFrame:Hide()
    Movers.SetPieceScale("game.LootFrame", 0.8)
    LootFrame:Show()
    T.near(LootFrame:GetScale(), 0.72, 1e-6, "a new size shows the next time it opens")
    _G.UIPanelWindows.LootFrame = nil
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

-- The guild window's club icon (CommunitiesFrame.xml PortraitOverlay) and its
-- maximize/minimize pair beside the X. The game hides the icon while the window
-- is small and hangs it off the corner when large. It stays in the header, and
-- a guild with no tabard can repaint the emblem (SetVertexColor 1,1,1,1) without
-- it landing behind the title.
T.test("skins: the guild window keeps its icon in the header; maximize and minimize sit level with the X", function()
    local f, overlay, dragon
    login(function()
        f = guildWindow()
        overlay = CreateFrame("Frame", nil, f)
        overlay:SetFrameLevel(300)
        overlay:Hide()
        for _, k in ipairs({ "Portrait", "TabardBackground", "TabardEmblem", "TabardBorder" }) do
            overlay[k] = overlay:CreateTexture()
        end
        f.PortraitOverlay = overlay
        f.MaximizeMinimizeFrame = CreateFrame("Frame", nil, f)
        f.MaximizeMinimizeFrame.MaximizeButton = artButton(f.MaximizeMinimizeFrame)
        f.MaximizeMinimizeFrame.MinimizeButton = artButton(f.MaximizeMinimizeFrame)
        local finder = CreateFrame("Frame", nil, f)
        f.GuildFinderFrame = finder
        local disabled = CreateFrame("Frame", nil, finder)
        finder.DisabledFrame = disabled
        dragon = disabled:CreateTexture()
        disabled.Title = disabled:CreateFontString()
        disabled.Description = disabled:CreateFontString()
        disabled.Description:SetTextColor(1, 0.82, 0)
        _G.ERR_GUILD_PLAYER_NOT_IN_GUILD = "No estás en una hermandad."
        stub.loadedAddOns.Blizzard_Communities = true
        registry(f, { "ClubSelected", "DisplayModeChanged" })
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit = stub.skins.Kit
    T.truthy(overlay:IsShown(), "the icon stays while the window is small")
    T.eq(overlay.Portrait:GetWidth(), DaylightUI.Win.PORTRAIT, "the same size as our windows' portrait")
    local point, rel, relPoint, x, y = overlay.Portrait:GetPoint(1)
    T.eq(point, "TOPLEFT"); T.eq(rel, f); T.eq(relPoint, "TOPLEFT")
    T.eq(x, DaylightUI.Win.EDGE); T.eq(y, -8, "in the header, not hanging off the corner")
    local _, _, _, titleX, titleY = f.TitleContainer.TitleText:GetPoint(1)
    T.eq(titleX, DaylightUI.Win.EDGE + DaylightUI.Win.PORTRAIT + 12, "the title starts after the icon")
    T.eq(titleY, DaylightUI.Win.TITLE_Y, "level with the portrait, like the spellbook")
    local sub
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetText and r:GetText() == "No estás en una hermandad." then sub = r end
    end
    T.truthy(sub, "a line under the title when no guild is selected")
    local sp, sr, srp, _, sy = sub:GetPoint(1)
    T.eq(sp, "TOPLEFT"); T.eq(sr, f.TitleContainer.TitleText); T.eq(srp, "BOTTOMLEFT")
    T.eq(sy, -2, "tucked under the title")
    T.eq(sub.__font[2], DaylightUI.Style.SIZE.small)
    T.eq(sub.__textColor[1], DaylightUI.Style.INK.LABEL[1])
    T.eq(overlay.Portrait.__texCoord[1], DaylightUI.Style.ICON_CROP[1], "the icon's square border cropped off")
    local rim
    for _, r in ipairs({ overlay:GetRegions() }) do
        if r.__texture == DaylightUI.MEDIA .. "portrait-rim.png" then rim = r end
    end
    T.truthy(rim, "the same rim as the spellbook portrait")
    local cp, cr, crp, _, cy = f.CloseButton:GetPoint(1)
    T.eq(cp, "TOPRIGHT"); T.eq(cr, f); T.eq(crp, "TOPRIGHT")
    T.eq(cy, DaylightUI.Win.CloseY(false), "the close button sits in the header, not in the corner")
    -- The game's UpdatePortrait for a guild without a design. The emblem stays put.
    overlay.TabardEmblem:SetShown(true)
    overlay.TabardEmblem:SetTexture("Interface\\GuildFrame\\GuildLogo-NoLogo")
    overlay.TabardEmblem:SetVertexColor(1, 1, 1, 1)
    T.eq(overlay.TabardEmblem:GetWidth(), DaylightUI.Win.PORTRAIT, "the tabard uses the same slot")
    T.eq(dragon:GetAlpha(), 0, "the finder splash's dragon gone")
    T.eq(f.GuildFinderFrame.DisabledFrame.Description.__textColor[1], DaylightUI.Style.INK.TEXT[1], "its text in our ink")
    local mm = f.MaximizeMinimizeFrame
    point, rel, relPoint, x, y = mm:GetPoint(1)
    T.eq(point, "RIGHT"); T.eq(rel, f.CloseButton); T.eq(relPoint, "LEFT")
    T.eq(y, 0, "level with the close button")
    for _, k in ipairs({ "MinimizeButton", "MaximizeButton" }) do
        local b = mm[k]
        T.eq(b:GetNormalTexture():GetAlpha(), 0, k .. ": the game's art gone")
        T.isnil(Kit.ShellOf(b), k .. ": a bare chevron, no box over the top edge")
    end
    -- Shrinking the window hides the icon. The click puts it back.
    overlay:Hide()
    mm.MinimizeButton:Click()
    T.truthy(overlay:IsShown(), "shrinking the window doesn't drop the icon")
    -- The finder page disables minimize. The chevron goes dim so it doesn't look live.
    local chev
    for _, r in ipairs({ mm.MinimizeButton:GetRegions() }) do
        if r.__texture == DaylightUI.MEDIA .. "ui-chevron.png" then chev = r end
    end
    mm.MinimizeButton:Disable()
    T.eq(chev.__vertex[1], DaylightUI.Style.INK.OFF[1], "a disabled minimize chevron reads as off")
    function f:GetSelectedClubId() return 7 end
    _G.C_Club = { GetClubInfo = function() return { name = "Luz de Elune" } end }
    f:Hide()
    f:Show()
    stub.RunTimers()
    T.eq(sub:GetText(), "Luz de Elune", "the selected community replaces the empty line")
    _G.C_Club.GetClubInfo = function() return { name = "Circulo de la Luna" } end
    f:TriggerEvent("ClubSelected", 7)
    T.eq(sub:GetText(), "Luz de Elune", "the line waits for the next frame, outside the game's own call")
    stub.RunTimers()
    T.eq(sub:GetText(), "Circulo de la Luna", "switching club while the window stays open updates the line")
    -- A new display mode (the game moves the icon as the window grows) puts it back.
    overlay.Portrait:ClearAllPoints()
    overlay.Portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 99, -99)
    f:TriggerEvent("DisplayModeChanged", 2)
    stub.RunTimers()
    T.eq(select(4, overlay.Portrait:GetPoint(1)), DaylightUI.Win.EDGE, "a new display mode puts the icon back in the header")
end)

-- The accent flare our own windows play around their portrait as they open
-- (spells, professions). The guild window's club icon gets it too, every time
-- the window shows, from its OnShow script, a frame later.
T.test("skins: the guild window's club icon plays the same flare each time it opens, and not with motion off", function()
    local f, overlay
    login(function()
        f = guildWindow()
        overlay = CreateFrame("Frame", nil, f)
        overlay:SetFrameLevel(300)   -- CommunitiesFrame.xml: the icon frame's own level
        for _, k in ipairs({ "Portrait", "TabardBackground", "TabardEmblem", "TabardBorder" }) do
            overlay[k] = overlay:CreateTexture()
        end
        f.PortraitOverlay = overlay
        stub.loadedAddOns.Blizzard_Communities = true
        registry(f, { "ClubSelected", "DisplayModeChanged" })
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local glow
    for _, child in ipairs({ f:GetChildren() }) do
        if child.halo and child.embers then glow = child end
    end
    T.truthy(glow, "a flare is made once for the icon")
    local function settle()
        for _ = 1, 90 do
            local m = DaylightUI.Motion.Driver()
            if m then stub.RunOnUpdate(m, 1 / 30) end
        end
    end
    T.eq(glow:IsShown(), false, "nothing before the window shows")
    f:Hide(); f:Show()
    T.eq(glow:IsShown(), false, "a frame after the show, once the icon is in place")
    stub.RunTimers()
    T.eq(glow:IsShown(), true, "the flare plays")
    T.truthy(glow:GetFrameLevel() > overlay:GetFrameLevel(), "over the game's icon, not hidden behind it")
    T.truthy(glow.halo:GetAlpha() > 0, "the halo shows")
    settle()
    T.eq(glow:IsShown(), false, "once, then gone: never a standing alert")
    f:Hide(); f:Show(); stub.RunTimers()
    T.eq(glow:IsShown(), true, "again on the next open")
    settle()
    local count = 0
    for _, child in ipairs({ f:GetChildren() }) do
        if child.halo and child.embers then count = count + 1 end
    end
    T.eq(count, 1, "still the one flare")
    -- A guild is selected: the game hides the club's icon and shows the tabard in
    -- its place (UpdatePortrait). The flare plays round the tabard.
    overlay.Portrait:Hide()
    overlay.TabardEmblem:Show()
    f:Hide(); f:Show(); stub.RunTimers()
    T.eq(glow:IsShown(), true, "a guild's tabard gets the flare too")
    settle()
    overlay.TabardEmblem:Hide(); overlay.TabardBackground:Hide()
    f:Hide(); f:Show(); stub.RunTimers()
    T.eq(glow:IsShown(), false, "nothing of the icon showing: no flare")
    overlay.Portrait:Show()
    DaylightUI.DB.General().motion = false
    f:Hide(); f:Show(); stub.RunTimers()
    T.eq(glow:IsShown(), false, "motion off: no flare")
end)

T.test("skins: with no community the join action sits under the guild text", function()
    local f, disabled
    login(function()
        stub.loadedAddOns.Blizzard_Communities = true
        f = guildWindow()
        f.CommunitiesList:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 170, 29)
        -- The game has already filled the list (its own OnShow ran once).
        f.CommunitiesList.ScrollBox.GetDataProvider = function()
            return { GetSize = function() return #_G.C_Club.GetSubscribedClubs() + 1 end }
        end
        local finder = CreateFrame("Frame", nil, f)
        f.GuildFinderFrame = finder
        disabled = CreateFrame("Frame", nil, finder)
        finder.DisabledFrame = disabled
        disabled.Title = disabled:CreateFontString()
        disabled.Description = disabled:CreateFontString()
        disabled:Show()
        _G.COMMUNITIES_JOIN_COMMUNITY = "Unirse o crear una comunidad"
        _G.C_Club = { GetSubscribedClubs = function() return {} end }
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local x
    for i = 1, f.CommunitiesList:GetNumPoints() do
        local p, _, _, px = f.CommunitiesList:GetPoint(i)
        if p == "BOTTOMRIGHT" then x = px end
    end
    T.eq(x, 0, "the empty column closes")
    T.eq(f.CommunitiesList:IsShown(), false, "the column, and the rule beside it, go")
    local b
    for _, child in ipairs({ disabled:GetChildren() }) do
        if child.text and child.text.GetText and child.text:GetText() == "Unirse o crear una comunidad" then b = child end
    end
    T.truthy(b and b:IsShown(), "a button inside the window")
    local p, rel, rp, _, y = b:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, f); T.eq(rp, "BOTTOM")
    T.eq(y, 22, "above the bottom edge, not outside the frame")
    -- Already in a guild: the column comes back and the button does not stay.
    _G.C_Club.GetSubscribedClubs = function() return { { clubId = 1 } } end
    _G.IsInGuild = function() return true end
    f:Hide()
    f:Show()
    stub.RunTimers()
    T.eq(f.CommunitiesList:IsShown(), true, "the club list is back")
    local back
    for i = 1, f.CommunitiesList:GetNumPoints() do
        local point, _, _, px = f.CommunitiesList:GetPoint(i)
        if point == "BOTTOMRIGHT" then back = px end
    end
    T.eq(back, 170, "the column has its width again")
    T.truthy(not b:IsShown() or b:GetAlpha() == 0, "the empty-state button fades out")
    -- A list rebuild while the window stays open does the same.
    _G.C_Club.GetSubscribedClubs = function() return {} end
    _G.IsInGuild = function() return false end
    f.CommunitiesList.ScrollBox:Update()
    stub.RunTimers()
    T.eq(f.CommunitiesList:IsShown(), false, "the empty column closes again without reopening the window")
    T.truthy(b:IsShown(), "the join button fades back in")
    _G.C_Club.GetSubscribedClubs = function() return { { clubId = 1 } } end
    _G.IsInGuild = function() return true end
    f.CommunitiesList.ScrollBox:Update()
    stub.RunTimers()
    T.eq(f.CommunitiesList:IsShown(), true, "the list returns on the rebuild")
    T.truthy(not b:IsShown() or b:GetAlpha() == 0, "and the button fades out again")
end)

T.test("skins: a window with no community keeps its club list shown until the game has filled it", function()
    -- The game fills the club list in the list's own OnShow, then the window's
    -- OnShow scrolls it to the selected club. A list hidden before that has no
    -- data, so the scroll fails with "attempt to index a nil value".
    local f, provider, visible
    login(function()
        stub.loadedAddOns.Blizzard_Communities = true
        f = guildWindow()
        f.CommunitiesList:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 170, 29)
        f.CommunitiesList.ScrollBox.GetDataProvider = function() return provider end
        _G.C_Club = { GetSubscribedClubs = function() return {} end }
        _G.IsInGuild = function() return false end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    visible = f.CommunitiesList:IsShown()
    T.eq(visible, true, "no data yet: the list is not hidden, so its OnShow still runs")
    T.eq(f.CommunitiesList:GetAlpha(), 0, "but it can't be seen")
    -- The game fills it; the next rebuild can close the empty column.
    provider = { GetSize = function() return 1 end }
    f.CommunitiesList.ScrollBox:Update()
    stub.RunTimers()
    T.eq(f.CommunitiesList:IsShown(), false, "with its data in place the empty column closes")
    -- A club shows up: the column returns whole.
    provider = { GetSize = function() return 2 end }
    f.CommunitiesList.ScrollBox:Update()
    stub.RunTimers()
    T.eq(f.CommunitiesList:IsShown(), true)
    T.eq(f.CommunitiesList:GetAlpha(), 1, "and fully visible")
end)

T.test("skins: joining a community opens the game's dialog, which we leave alone", function()
    local opened, toggle
    local f, disabled
    login(function()
        stub.loadedAddOns.Blizzard_Communities = true
        _G.COMMUNITIES_JOIN_COMMUNITY = "Unirse o crear una comunidad"
        function _G.AddCommunitiesFlow_Toggle() opened = true end
        toggle = _G.AddCommunitiesFlow_Toggle
        _G.C_Club = { GetSubscribedClubs = function() return {} end }
        f = guildWindow()
        local finder = CreateFrame("Frame", nil, f)
        f.GuildFinderFrame = finder
        disabled = CreateFrame("Frame", nil, finder)
        finder.DisabledFrame = disabled
        disabled.Title = disabled:CreateFontString()
        disabled.Description = disabled:CreateFontString()
        disabled:Show()
        local locked = CreateFrame("Frame", "CommunitiesAddDialog", UIParent)
        locked.__forbidden = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(_G.AddCommunitiesFlow_Toggle, toggle, "the game's toggle is still the game's")
    T.isnil(_G.DaylightCommunitiesAdd, "we do not build a replacement window")
    T.isnil(stub.skins.Kit.ShellOf(_G.CommunitiesAddDialog), "the locked dialog is not touched")
    local b
    for _, child in ipairs({ disabled:GetChildren() }) do
        if child.text and child.text.GetText and child.text:GetText() == "Unirse o crear una comunidad" then b = child end
    end
    T.truthy(b, "the empty page still has the join button")
    b:Click()
    T.eq(opened, true, "that button opens the game's dialog")
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

T.test("skins: the crowd control alert switch off leaves the game's own alert as it is", function()
    local LW, game = require("locworld"), nil
    local S = login(function()
        game = LW.Install()
        _G.DaylightUIDB.modules.Skins = { ccAlert = false }
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.isnil(S.CcAlert.frame, "none of ours")
    T.eq(game.Icon:GetAlpha(), 1, "the game's art still shows")
    DaylightUI:Set("Skins", "ccAlert", true)
    stub.RunTimers()
    T.truthy(S.CcAlert.frame, "on again: ours")
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

-- Every game window the skins dress that stands on its own drags the same way,
-- including the ones a game addon makes later (the auction house, macros...).
T.test("skins: every skinned game window drags by its title bar, its spot kept after the game lays out", function()
    login(function()
        _G.ShowUIPanel = function(p) p:Show() end
        _G.UpdateUIPanelPositions = function() end
    end)
    local Move = stub.skins.WindowMove
    T.truthy(#Move.WINDOWS >= 25, "the skinned windows, not just a few")
    local made = {}
    for _, name in ipairs(Move.WINDOWS) do
        if not _G[name] then made[name] = window(name) end
    end
    stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local db = DaylightUI.DB.Active().modules.Skins
    for _, name in ipairs(Move.WINDOWS) do
        local f, bar = _G[name], Move.bars[name]
        T.truthy(bar, name .. " gets a strip")
        T.eq(bar:GetParent(), f, name)
        local _, rel, rp, x, y = bar:GetPoint(1)
        T.eq(rel, f); T.eq(rp, "TOPLEFT"); T.eq(x, 0); T.eq(y, 0, name .. ": along the top")
        T.truthy(select(4, bar:GetPoint(2)) <= -Move.BUTTONS, name .. ": the close button left free")
    end
    -- The calendar's month arrows (about 226-433 px in from its left on its 659
    -- px width, Blizzard_Calendar.xml) and filter button stay clickable.
    T.eq(select(4, Move.bars.CalendarFrame:GetPoint(2)), -440, "the calendar drags by the left of its title row")
    T.eq(Move.bars.FlightMapFrame:GetHeight(), 20, "the flight map's canvas starts 20 down")
    for _, name in ipairs({ "AuctionHouseFrame", "GameMenuFrame", "TimeManagerFrame", "TaxiFrame" }) do
        local f, bar = _G[name], Move.bars[name]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
        f:Show()
        bar:GetScript("OnDragStart")(bar, "LeftButton")
        T.truthy(f.__moving, name .. " moves")
        f.__center = { 640, 400 }
        bar:GetScript("OnDragStop")(bar)
        T.truthy(Move.Spot(name), name .. ": its spot saved under its own name")
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
        UpdateUIPanelPositions(f)
        T.eq(select(3, f:GetPoint(1)), "BOTTOMLEFT", name .. ": back on its spot after the game lays out")
        f:Hide()
    end
    -- Scaled with Ctrl + wheel, a window that loaded after the scaler started keeps its corner too.
    _G.IsControlKeyDown = function() return true end
    _G.UIPanelWindows = { AuctionHouseFrame = { area = "doublewide" } }
    stub.skins.WindowScale.Scan()
    local ah = AuctionHouseFrame
    ah:Show()
    local x = select(4, ah:GetPoint(1))
    ah:GetScript("OnMouseWheel")(ah, 1)
    T.eq(ah:GetScale(), 1.05)
    T.near(select(4, ah:GetPoint(1)) * 1.05, x, 0.01, "the corner stayed")
    -- /dui reset forgets them all.
    DaylightUI.Movers.ResetAll()
    for name in pairs(made) do T.isnil(db.windowSpots[name], name) end
end)

-- Beast Training lends the game's trainer window back; for a class trainer the
-- NPC window keeps it out of sight under a parent of its own, and it stays there.
T.test("skins: the trainer window drags only while Beast Training lends it back", function()
    login(function()
        window("ClassTrainerFrame")
        _G.UpdateUIPanelPositions = function() end
    end)
    local Move, f = stub.skins.WindowMove, ClassTrainerFrame
    T.truthy(Move.bars.ClassTrainerFrame)
    DaylightUI.DB.Active().modules.Skins.windowSpots.ClassTrainerFrame = { 300, 700 }
    local aside = DaylightUI.Win.Followers.aside
    f:SetParent(aside)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", aside, "TOPLEFT", 0, 0)
    f:Show()
    UpdateUIPanelPositions(f)
    T.eq(select(2, f:GetPoint(1)), aside, "parked: left where it was put")
    local bar = Move.bars.ClassTrainerFrame
    bar:GetScript("OnDragStart")(bar, "LeftButton")
    T.falsy(f.__moving, "and can't be dragged out")
    f:SetParent(UIParent)
    UpdateUIPanelPositions(f)
    T.eq(select(3, f:GetPoint(1)), "BOTTOMLEFT", "lent: on its spot")
end)

-- The collections journal holds secure buttons (the toy box, mounts), so in a
-- fight it can't be moved: it waits for the fight to end.
T.test("skins: a window with secure buttons isn't moved in a fight, only after it", function()
    login(function()
        _G.UpdateUIPanelPositions = function() end
    end)
    local f = window("CollectionsJournal")
    CreateFrame("CheckButton", nil, f, "SecureActionButtonTemplate")
    stub.FireEvent("ADDON_LOADED", "Blizzard_Collections")
    stub.RunTimers()
    local Move, bar = stub.skins.WindowMove, stub.skins.WindowMove.bars.CollectionsJournal
    T.truthy(bar)
    T.truthy(f:IsProtected(), "protected through its buttons")
    DaylightUI.DB.Active().modules.Skins.windowSpots.CollectionsJournal = { 300, 700 }
    -- Open as the fight starts, the game's spot not yet put back.
    f:Show()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -100)
    stub.secure = true
    stub.EnterCombat()
    UpdateUIPanelPositions(f)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(select(3, f:GetPoint(1)), "TOPLEFT", "left where the game put it")
    bar:GetScript("OnDragStart")(bar, "LeftButton")
    T.falsy(f.__moving, "no drag in a fight")
    stub.LeaveCombat()
    stub.secure = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(select(3, f:GetPoint(1)), "BOTTOMLEFT", "on its spot once the fight ends")
end)

-- The hunter's stable on Forever is the Camelot one
-- (Blizzard_StableUI/Camelot/Blizzard_StableUI.xml): PetStableFrame is a
-- PortraitFrameTemplate whose pet slots are CheckButtons (PetStableSlotTemplate)
-- with a named icon and their own current/unlocked/locked slot art. The gold
-- rules and the coin box are their own frames.
T.test("skins: the hunter's stable (PetStableFrame) wears our window look, its pet slots our item look", function()
    local f, slot, bar, stabled, panelAttr, ownSelect, ownUpdate
    login(function()
        f = window("PetStableFrame")
        slot = CreateFrame("CheckButton", "PetStableCurrentPet", f)
        slot:SetSize(37, 37)
        slot.icon = slot:CreateTexture("PetStableCurrentPetIconTexture")
        slot.currentBackground = slot:CreateTexture()
        slot.unlockedBackground = slot:CreateTexture()
        slot.lockedBackground = slot:CreateTexture()
        slot.currentGlow = slot:CreateTexture()
        slot.Text = slot:CreateFontString()
        CreateFrame("CheckButton", "PetStableStabledPet1", f)
        stabled = CreateFrame("CheckButton", "PetStableStabledPet2", f)
        function f:SelectPet(index)
            self.selectedPet = index
            _G.PetStableLevelText:SetText("run on")
            _G.PetStableLoyaltyText:SetText("loyalty")
        end
        function f:Update()
            slot:ClearAllPoints()
            slot:SetPoint("TOP", f.modelScene, "BOTTOM", -69, -34)
        end
        ownSelect, ownUpdate = f.SelectPet, f.Update
        -- The game's callback registry (only what the skin uses of it).
        local cbs = {}
        _G.EventRegistry = {
            RegisterCallback = function(_, e, fn, owner) cbs[e] = cbs[e] or {}; cbs[e][#cbs[e] + 1] = { fn, owner } end,
            TriggerEvent = function(_, e, ...) for _, c in ipairs(cbs[e] or {}) do c[1](c[2], ...) end end,
        }
        -- Clicking a slot runs the game's own OnClick, which picks the pet.
        slot:SetScript("OnClick", function() f:SelectPet(2) end)
        f.TopDividerFrame = CreateFrame("Frame", nil, f)
        f.BottomDividerFrame = CreateFrame("Frame", nil, f)
        f.modelScene = CreateFrame("Frame", nil, f)
        f.modelScene.Inset = CreateFrame("Frame", nil, f.modelScene)
        f.modelScene.Inset.Bg = f.modelScene.Inset:CreateTexture()
        local money = CreateFrame("Frame", "PetStableMoneyFrame", f)
        money.Border = CreateFrame("Frame", nil, money)
        bar = CreateFrame("Frame", nil, f)
        f.expBar = bar
        bar.Fill = bar:CreateTexture()
        bar.Fill:SetHeight(15)
        bar.Mask = bar:CreateMaskTexture()
        bar.Text = bar:CreateFontString()
        bar.overlay = CreateFrame("Frame", nil, bar)
        _G.PetStableLevelText = f:CreateFontString()
        _G.PetStableLoyaltyText = f:CreateFontString()
        _G.PetStableSlotText = f:CreateFontString()
        f.purchaseButton = CreateFrame("Button", nil, f)
        f.selectedPet = 1
        _G.UNIT_LEVEL_TEMPLATE = "Nivel %d"
        _G.StableFrameMixin = { SelectPet = function() end }
        _G.C_StableInfo = { GetStablePetInfo = function(id)
            if id == 2 then
                return { name = "Lobo", level = 10, familyName = "Lobo", loyaltyName = "(Nivel de lealtad 3) Amigo", loyaltyLevel = 3 }
            end
            return { name = "Kaelen", level = 18, familyName = "Ave rapaz", loyaltyName = "Mejor amigo", loyaltyLevel = 6 }
        end }
        panelAttr = {}
        _G.SetUIPanelAttribute = function(frame, name, value) panelAttr[name] = value end
        stub.loadedAddOns.Blizzard_StableUI = true
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(f.NineSlice:GetAlpha(), 0, "the game's frame art gone")
    T.truthy(stub.skins.Kit.ShellOf(f), "our border and panel")
    T.eq(slot.currentBackground:GetAlpha(), 0, "the slot's own art gone")
    T.eq(slot.unlockedBackground:GetAlpha(), 0)
    T.eq(slot.lockedBackground:GetAlpha(), 0)
    T.eq(f.TopDividerFrame:GetAlpha(), 0, "the rule above the pet gone")
    T.eq(f.BottomDividerFrame:GetAlpha(), 0, "the rule under the pet gone")
    T.eq(f.modelScene.Inset.Bg:GetAlpha(), 0, "the box around the pet gone")
    T.eq(_G.PetStableMoneyFrame.Border:GetAlpha(), 0, "the coin box gone")
    T.eq(f:GetWidth(), 448, "a little narrower than the wide pass")
    T.eq(f:GetHeight(), 570, "taller than the game's frame")
    T.isnil(panelAttr.width, "the game's panel layout keeps its own size: a write would taint it")
    T.isnil(panelAttr.height)
    local own = type(_G.UIPanelWindows) == "table" and _G.UIPanelWindows.PetStableFrame
    T.falsy(own and (own.width or own.height), "nothing written into the game's own panel table")
    local _, _, _, _, my = f.modelScene:GetPoint(1)
    T.eq(my, -84, "the pet starts under the three lines")
    local _, _, _, _, by = f.modelScene:GetPoint(2)
    T.eq(by, 182, "the extra height opens the gap under the pet")
    T.eq(_G.PetStableLevelText:GetText(), "Kaelen", "the name on its own line")
    local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local detail = plain(_G.PetStableLoyaltyText:GetText())
    T.eq(detail, "Nivel 18 | Ave rapaz\nMejor amigo | 6")
    f.selectedPet = nil
    local strict, bad = _G.C_StableInfo.GetStablePetInfo, 0
    _G.C_StableInfo.GetStablePetInfo = function(id)
        if type(id) ~= "number" then bad = bad + 1 end
        return strict(id)
    end
    f:SelectPet(nil)
    stub.RunTimers()
    T.eq(bad, 0, "no pet picked yet: the game's call is never made without an index")
    T.eq(#stub.errors, 0)
    -- Nothing hooks the game's methods: its own are still the ones on the frame.
    T.truthy(f.SelectPet == ownSelect and f.Update == ownUpdate, "no hooksecurefunc on the stable")
    slot:Click()
    T.eq(_G.PetStableLevelText:GetText(), "run on", "ours waits for the next frame, not inside the game's call")
    stub.RunTimers()
    T.eq(_G.PetStableLevelText:GetText(), "Lobo", "a click on a slot keeps the name on its own line")
    -- A pet named after its family says it once.
    T.eq(plain(_G.PetStableLoyaltyText:GetText()), "Nivel 10\n(Nivel de lealtad 3) Amigo", "the family not repeated when it's the name")
    -- The game's callbacks and events redo the lines and the slots too.
    f.selectedPet = 1
    f:SelectPet(1)
    EventRegistry:TriggerEvent("StableFrameMixin.PetSelected", 1)
    stub.RunTimers()
    T.eq(_G.PetStableLevelText:GetText(), "Kaelen", "its PetSelected callback")
    f:SelectPet(2)
    EventRegistry:TriggerEvent("StableFrameMixin.OnSelectedPetChanged")
    stub.RunTimers()
    T.eq(_G.PetStableLevelText:GetText(), "Lobo", "its OnSelectedPetChanged callback")
    f.selectedPet = 2
    f:SelectPet(1); f.selectedPet = 1
    stub.FireEvent("PET_STABLE_UPDATE")
    stub.RunTimers()
    T.eq(_G.PetStableLevelText:GetText(), "Kaelen", "a stable update")
    _G.PetStableLevelText:SetText("run on")
    stub.FireEvent("PLAYER_MONEY")
    stub.RunTimers()
    T.eq(_G.PetStableLevelText:GetText(), "Kaelen", "money changing")
    f:Update()
    stub.FireEvent("PET_STABLE_UPDATE")
    stub.RunTimers()
    local sp, sr, srp, sx, sy = slot:GetPoint(1)
    T.eq(sp, "TOPLEFT"); T.eq(sr, f.modelScene); T.eq(srp, "BOTTOMLEFT")
    T.eq(sx, 28); T.eq(sy, -34, "the current pet stays on the left after a refresh")
    local rp, rr, rrp = stabled:GetPoint(1)
    T.eq(rp, "TOPRIGHT"); T.eq(rr, f.modelScene); T.eq(rrp, "BOTTOMRIGHT", "the stabled pets stay on the right")
    T.eq(_G.PetStableLevelText.__textColor[1], DaylightUI.Style.INK.TITLE[1], "the pet's name in our ink")
    local cp, cr, crp, cx, cy = f.CloseButton:GetPoint(1)
    T.eq(cp, "TOPRIGHT"); T.eq(cr, f); T.eq(crp, "TOPRIGHT")
    T.eq(cx, DaylightUI.Win.CLOSE_X); T.eq(cy, DaylightUI.Win.CloseY(false), "the X sits in the header")
    T.eq(f.CloseButton:GetWidth(), DaylightUI.Widgets.CLOSE)
    local tp, tr, trp, tx, ty = f.TitleContainer.TitleText:GetPoint(1)
    T.eq(tp, "TOPLEFT"); T.eq(tr, f); T.eq(trp, "TOPLEFT")
    T.eq(tx, stub.skins.Kit.TITLE_X); T.eq(ty, -stub.skins.Kit.TITLE_TOP, "the title where Kit.Window puts every window's")
    T.eq(_G.PetStableSlotText.__font[2], DaylightUI.Style.SIZE.body, "the buy-a-slot line is a step under the heading")
    T.eq(_G.PetStableSlotText.__textColor[1], DaylightUI.Style.INK.LABEL[1], "the same ink as the slot labels")
    local ap, ar = _G.PetStableSlotText:GetPoint(1)
    T.eq(ap, "ALL"); T.eq(ar:GetParent(), f)
    local hp, hr, hrp, _, hy = ar:GetPoint(1)
    T.eq(hp, "TOP"); T.eq(hr, slot); T.eq(hrp, "BOTTOM"); T.eq(hy, -28, "it sits lower in the gap")
    local bp, br, brp, _, by = ar:GetPoint(2)
    T.eq(bp, "BOTTOM"); T.eq(br, f.purchaseButton); T.eq(brp, "TOP"); T.eq(by, 4, "and stops above the cost")
    local dressed
    for _, child in ipairs({ bar:GetChildren() }) do
        if stub.skins.Kit.ShellOf(child) then dressed = true end
    end
    T.truthy(dressed, "the experience bar wears our bar")
    local barDrag = stub.skins.WindowMove.bars.PetStableFrame
    T.truthy(barDrag, "the title bar drags it, like the other npc windows")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Show()
    barDrag:GetScript("OnDragStart")(barDrag, "LeftButton")
    T.truthy(f.__moving, "it moves")
    f.__center = { 500, 400 }
    barDrag:GetScript("OnDragStop")(barDrag)
    T.truthy(stub.skins.WindowMove.Spot("PetStableFrame"), "its spot saved")
end)

-- A game button whose frame has secret anchoring (the guild roster's member
-- details showing a name under the client's restrictions) answers its size
-- with secret numbers. Closing the window mid-dungeon hides it, and the trace
-- resets: a player got "attempt to perform arithmetic on local 'w' (a secret
-- number value)" from tr.Draw. A tween already running hit it on its next tick too.
T.test("skins: a traced game button with a secret size hides and tweens without doing math on it", function()
    login()
    local Kit = stub.skins.Kit
    local holder = CreateFrame("Frame", nil, UIParent)
    local b = button(nil, holder)
    b:SetSize(96, 22)
    Kit.Button(b)
    local tr = Kit.TraceOf(b)
    T.truthy(tr, "the hover trace")
    b:GetScript("OnEnter")(b)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02)
    T.truthy(tr.p > 0 and tr.p < 1, "half traced")
    stub.HeldSecret(b)
    -- In game a secret number answers type() with "number"; the fake one is a table.
    local realType, realCheck = type, issecretvalue
    local function fake(v) return realType(v) == "table" and rawget(v, "__secret") == true end
    _G.issecretvalue = fake
    _G.type = function(v)
        if fake(v) and realType(rawget(v, "__value")) == "number" then return "number" end
        return realType(v)
    end
    local ok1, err1 = pcall(stub.RunOnUpdate, DaylightUI.Motion.Driver(), 0.02)
    local ok2, err2 = pcall(holder.Hide, holder)
    _G.type, _G.issecretvalue = realType, realCheck
    T.truthy(ok1, tostring(err1))
    T.truthy(ok2, tostring(err2))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(tr.p, 0, "back at rest")
    T.falsy(tr.top:IsShown() or tr.left:IsShown(), "no half-drawn trace left for the next show")
    -- Plain again: the trace draws as before.
    stub.HeldSecret(b, false)
    holder:Show()
    b:GetScript("OnEnter")(b)
    for _ = 1, 40 do stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.02) end
    T.eq(tr.p, 1)
    T.truthy(tr.right:IsShown(), "traced all round")
end)

T.test("bar ends: the breath bar's ends each on their own, its fill leans with the right end", function()
    local t
    local S = login(function()
        local c = CreateFrame("Frame", "MirrorTimerContainer", UIParent)
        t = CreateFrame("Frame", nil, c)
        t.StatusBar = CreateFrame("StatusBar", nil, t)
        t.Text = t:CreateFontString()
        t.Setup = function() end
        c.mirrorTimers = { t }
    end)
    local Style = DaylightUI.Style
    local h = S.Breath.holders[t]
    DaylightUI:Set("Skins", "breathSlantLeft", true)
    DaylightUI:Set("Skins", "breathUnder", true)
    local sl = Style.GetSlant(h)
    T.eq(sl.side, "both"); T.eq(sl.under, "right", "both ends angled, the right one flipped")
    local _, _, under = Style.GetFillAngle(h.bar)
    T.eq(under, true, "the fill leans like the right end")
    DaylightUI:Set("Skins", "breathSlant", false)
    T.eq(Style.GetSlant(h).side, "left", "the left end alone")
    T.falsy(Style.GetFillAngle(h.bar), "the fill square toward a straight end")
end)
