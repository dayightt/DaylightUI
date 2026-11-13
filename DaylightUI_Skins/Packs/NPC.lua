-- NPC pack: the windows you see when talking to NPCs. Quests (detail, progress,
-- reward and greeting panels), gossip, merchants, class and profession
-- trainers, and the flight map.
--
-- Quest and gossip text is printed dark for the game's parchment. On our dark
-- panels bodies are made light and titles gold, every time the game refills
-- the window.

local _, ns = ...
local Engine = ns.Engine


local function g(name) return _G[name] end

-- ---------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------

local QUEST_TITLES = { "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader",
                       "QuestProgressTitleText", "QuestProgressRequiredItemsText", "CurrentQuestsText",
                       "AvailableQuestsText" }
local QUEST_TEXT = { "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoGroupSize",
                     "QuestInfoRewardText", "QuestInfoQuestType", "QuestProgressText",
                     "QuestProgressRequiredMoneyText", "GreetingText" }
local REWARD_TEXT = { "ItemChooseText", "ItemReceiveText", "PlayerTitleText" }

-- Relights quest text the game may have just filled. Also used for quests
-- opened from the map's log (System pack), which must work without this pack.
function ns.LightQuestInfo(Kit)
    for _, n in ipairs(QUEST_TITLES) do Kit.Light(g(n), Kit.HEADER) end
    for _, n in ipairs(QUEST_TEXT) do Kit.Light(g(n)) end
    local rewards = g("QuestInfoRewardsFrame")
    if type(rewards) == "table" then
        Kit.Light(rewards.Header, Kit.HEADER)
        for _, key in ipairs(REWARD_TEXT) do Kit.Light(rewards[key]) end
        if type(rewards.XPFrame) == "table" then Kit.Light(rewards.XPFrame.ReceiveText) end
    end
    local objectives = g("QuestInfoObjectivesFrame")
    if type(objectives) == "table" and type(objectives.Objectives) == "table" then
        for _, fs in ipairs(objectives.Objectives) do Kit.Light(fs) end
    end
end

-- Relights every quest text the game may have just filled.
local function lightQuest(Kit)
    ns.LightQuestInfo(Kit)
    -- The greeting panel's quest buttons come from a pool and have no names,
    -- so search the whole panel. Its headers keep their gold (above).
    local function buttonsIn(frame, depth)
        if type(frame) ~= "table" or not frame.GetChildren or depth > 6 then return end
        for _, c in ipairs({ frame:GetChildren() }) do
            if Kit.Kind(c) == "Button" then Kit.LightAll(c) end
            buttonsIn(c, depth + 1)
        end
    end
    buttonsIn(g("QuestFrameGreetingPanel"), 0)
end

-- The Daylight UI NPC window replaces the quest and gossip windows while it's
-- on, so their skins step aside (read at login, before the skins start).
local function ours() return DaylightUI.npcOwnWindow == true end
-- DaylightMogul's vendor parks the game's merchant frame, so leave it alone too.
local function oursShop()
    return (DaylightUI.npcOwnWindow == true and DaylightUI.npcOwnVendor == true) or DaylightUI.vendorMogul == true
end

Engine.Register({ key = "quest", pack = "npc", skip = ours, apply = function(Kit)
    local f = g("QuestFrame")
    if not f then return end
    Kit.Window(f)
    for _, n in ipairs({ "QuestFrameDetailPanel", "QuestFrameRewardPanel", "QuestFrameProgressPanel", "QuestFrameGreetingPanel" }) do
        Kit.Strip(g(n))
    end
    for _, n in ipairs({ "QuestDetailScrollFrame", "QuestRewardScrollFrame", "QuestProgressScrollFrame", "QuestGreetingScrollFrame" }) do
        local sf = g(n)
        Kit.Strip(sf)
        if type(sf) == "table" then Kit.ScrollBar(sf.ScrollBar or g(n .. "ScrollBar")) end
    end
    for _, n in ipairs({ "QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteQuestButton",
                         "QuestFrameCompleteButton", "QuestFrameGoodbyeButton", "QuestFrameGreetingGoodbyeButton" }) do
        Kit.Button(g(n))
    end
    -- The game fills (and colors) the text every time the window shows.
    local function relight() lightQuest(Kit) end
    for _, fn in ipairs({ "QuestInfo_Display", "QuestFrameProgressItems_Update", "QuestFrameGreetingPanel_OnShow" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, relight) end
    end
    for _, fn in ipairs({ "QuestFrame_SetTextColor", "QuestFrame_SetTitleTextColor" }) do
        if type(_G[fn]) == "function" then
            local header = fn == "QuestFrame_SetTitleTextColor"
            hooksecurefunc(fn, function(fs) Kit.Light(fs, header and Kit.HEADER or nil) end)
        end
    end
    f:HookScript("OnShow", relight)
    -- The greeting page, on show and again next frame (its quest buttons may
    -- be filled in just after).
    local greeting = g("QuestFrameGreetingPanel")
    if type(greeting) == "table" and greeting.HookScript then
        greeting:HookScript("OnShow", function()
            relight()
            C_Timer.After(0, relight)
        end)
    end
    relight()
end })

-- ---------------------------------------------------------------------
-- Gossip
-- ---------------------------------------------------------------------

Engine.Register({ key = "gossip", pack = "npc", skip = ours, apply = function(Kit)
    local f = g("GossipFrame")
    if not f then return end
    Kit.Window(f)
    local panel = f.GreetingPanel
    if type(panel) == "table" then
        Kit.Strip(panel)
        Kit.Button(panel.GoodbyeButton)
        Kit.ScrollBar(panel.ScrollBar)
        -- Each greeting and option row gets light text. The greeting's text
        -- sits a few levels down in its row.
        Kit.EachRow(panel.ScrollBox, function(row) Kit.LightAll(row, nil, 3) end)
    end
end })

-- ---------------------------------------------------------------------
-- Merchants
-- ---------------------------------------------------------------------

Engine.Register({ key = "merchant", pack = "npc", skip = oursShop, apply = function(Kit)
    local f = g("MerchantFrame")
    if not f then return end
    Kit.Window(f)
    for i = 1, 4 do Kit.Tab(g("MerchantFrameTab" .. i)) end
    local function item(prefix)
        local slot = g(prefix)
        if not slot then return false end
        Kit.Item(g(prefix .. "ItemButton"))
        Kit.Hide(g(prefix .. "SlotTexture"))
        Kit.Hide(g(prefix .. "NameFrame"))
        Kit.Font(g(prefix .. "Name"), nil, Kit.TEXT)
        return true
    end
    for i = 1, 12 do item("MerchantItem" .. i) end
    Kit.PageButton(g("MerchantPrevPageButton"), "left")
    Kit.PageButton(g("MerchantNextPageButton"), "right")
    Kit.Dropdown(f.FilterDropdown or g("MerchantFrameFilterDropdown"))
    item("MerchantBuyBackItem")
    for _, n in ipairs({ "MerchantMoneyInset", "MerchantExtraCurrencyInset" }) do Kit.Inset(g(n)) end
    for _, n in ipairs({ "MerchantMoneyBg", "MerchantExtraCurrencyBg" }) do Kit.Hide(g(n)) end
    Kit.Light(g("MerchantPageText"), Kit.DIM)
end })

-- ---------------------------------------------------------------------
-- Trainers (load on demand)
-- ---------------------------------------------------------------------

local trainerHooked = false
Engine.Register({ key = "trainer", pack = "npc", addon = "Blizzard_TrainerUI", apply = function(Kit)
    local f = g("ClassTrainerFrame")
    if not f then return end
    Kit.Window(f)
    Kit.Inset(f.BottomInset or g("ClassTrainerFrameBottomInset"))
    Kit.Button(g("ClassTrainerTrainButton"))
    Kit.Dropdown(f.FilterDropdown or g("ClassTrainerFrameFilterDropdown"))
    Kit.ScrollBar(f.ScrollBar)
    Kit.StatusBar(g("ClassTrainerStatusBar"), { 0.35, 0.55, 0.9 })
    -- Skill rows and the profession's own row at the top: row look, accent on
    -- the selected one. The game's text colors stay (they show what you can
    -- learn).
    local function row(r)
        if type(r) ~= "table" then return end
        local icon = r.icon or r.Icon
        Kit.Row(r, icon and { [icon] = true } or nil, r.selectedTex)
        if icon and icon.SetTexCoord then DaylightUI.Style.CropIcon(icon) end
        Kit.Font(r.name)
        Kit.Font(r.subText)
    end
    row(g("ClassTrainerFrameSkillStepButton"))
    Kit.Hide(g("ClassTrainerFrameSkillStepButtonHighlight"))
    Kit.EachRow(f.ScrollBox, row)
    -- Only ClassTrainerFrame_InitServiceButton shows or hides a row's selection
    -- art (when filling the list, and for the old and new row on a pick), so we
    -- repaint after it rather than hooking the art.
    if not trainerHooked and type(ClassTrainerFrame_InitServiceButton) == "function" then
        trainerHooked = true
        hooksecurefunc("ClassTrainerFrame_InitServiceButton", function(b) Kit.RepaintRow(b) end)
    end
end })

-- ---------------------------------------------------------------------
-- Flight map (load on demand): our border around the map, no panel over it.
-- ---------------------------------------------------------------------

Engine.Register({ key = "flightmap", pack = "npc", addon = "Blizzard_FlightMap", apply = function(Kit)
    local f = g("FlightMapFrame")
    if not f then return end
    local border = f.BorderFrame or f
    Kit.Window(border, { noBackground = true })
end })

-- ---------------------------------------------------------------------
-- Everything else NPCs show, via Engine.Window. The windows above get it too,
-- for anything their skins don't cover.
-- ---------------------------------------------------------------------

-- Books, letters and plaques. The game draws them for parchment: a serif page,
-- a gold page number under the title, and the spellbook's yellow arrows.
-- A new letter sets the font, the colors and the parchment insets again, and
-- each page turn moves the text back down, so this runs on open and on
-- ITEM_TEXT_READY. The HTML box only picks up a new font when its text is set.
local LETTER_TAGS = { P = "body", H1 = "title", H2 = "head", H3 = "head" }
local LETTER_EDGE, LETTER_TOP, LETTER_BAR, LETTER_BOTTOM = 16, 36, 26, 16
local LETTER_BTN = 22
local LETTER_FOOT = 46 -- text stops above the page row
local letterListening = false

local function letterLabels(Kit, btn)
    if type(btn) ~= "table" or not btn.GetRegions then return end
    for _, r in ipairs({ btn:GetRegions() }) do
        if Kit.Kind(r) == "FontString" then r:SetAlpha(0) end
    end
end

local function shown(f) return type(f) == "table" and f.IsShown and f:IsShown() == true end

local function dressLetter(Kit)
    local Style = DaylightUI.Style
    local frame = _G.ItemTextFrame
    local page = _G.ItemTextPageText
    if type(page) == "table" and type(page.SetTextColor) == "function" then
        local ink = Style.INK
        local file = Style.FontFile(Style.WINDOW_SLOT)
        local scale = DaylightUI:Get("general", "fontScale") or 1
        local flags = Style.Outline()
        if type(page.SetFont) == "function" and type(file) == "string" then
            for tag, role in pairs(LETTER_TAGS) do
                page:SetFont(tag, file, Style.SIZE[role] * scale, flags)
            end
        end
        page:SetTextColor("P", ink.TEXT[1], ink.TEXT[2], ink.TEXT[3])
        for _, tag in ipairs({ "H1", "H2", "H3" }) do
            page:SetTextColor(tag, ink.TITLE[1], ink.TITLE[2], ink.TITLE[3])
        end
        local text = page.GetText and page:GetText()
        if type(text) == "string" and text ~= "" and page.SetText then page:SetText(text) end
        Kit.LightAll(page, nil, 0)
        -- The parchment inset (18, -15) sits inside the scroll. The scroll
        -- itself is the margin, same 16px as a talk window.
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", 0, 0)
        local width = type(frame) == "table" and frame.GetWidth and frame:GetWidth()
        if type(width) == "number" and width > LETTER_EDGE + LETTER_BAR + 40 and page.SetWidth then
            page:SetWidth(width - LETTER_EDGE - LETTER_BAR)
        end
    end
    -- Prev, the number and next share one row at the bottom right, clear of
    -- the title and of the voice button VoiceOver drops in the bottom center.
    -- The game still shows only the end that exists.
    local nextb = _G.ItemTextNextPageButton
    local prev = _G.ItemTextPrevPageButton
    local num = _G.ItemTextCurrentPage
    local paging = shown(nextb) or shown(prev) or shown(num)
    local scroll = _G.ItemTextScrollFrame
    if type(frame) == "table" and type(scroll) == "table" then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LETTER_EDGE, -LETTER_TOP)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LETTER_BAR, paging and LETTER_FOOT or LETTER_BOTTOM)
    end
    if type(frame) ~= "table" or type(nextb) ~= "table" then return end
    Kit.PageButton(nextb, "right")
    Kit.PageButton(prev, "left")
    letterLabels(Kit, nextb)
    letterLabels(Kit, prev)
    nextb:SetSize(LETTER_BTN, LETTER_BTN)
    if type(prev) == "table" then prev:SetSize(LETTER_BTN, LETTER_BTN) end
    nextb:ClearAllPoints()
    nextb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LETTER_EDGE, 12)
    if type(num) == "table" then
        num:ClearAllPoints()
        num:SetPoint("RIGHT", nextb, "LEFT", -8, 0)
        if num.SetJustifyH then num:SetJustifyH("CENTER") end
        if num.SetJustifyV then num:SetJustifyV("MIDDLE") end
        if num.SetWidth then num:SetWidth(24) end
        Kit.Font(num, Style.SIZE.small)
        Kit.Light(num, Kit.DIM)
    end
    if type(prev) == "table" then
        prev:ClearAllPoints()
        prev:SetPoint("RIGHT", type(num) == "table" and num or nextb, "LEFT", -8, 0)
    end
    local title = type(frame.TitleContainer) == "table" and frame.TitleContainer.TitleText
    if type(title) == "table" and title.SetPoint then
        title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Kit.TITLE_RIGHT, -Kit.TITLE_TOP)
    end
end

Engine.Window({ key = "itemtext", pack = "npc", frame = "ItemTextFrame", light = true,
    after = function(Kit)
        dressLetter(Kit)
        if letterListening then return end
        letterListening = true
        DaylightUI.On("StyleChanged", function() dressLetter(Kit) end)
        local frame = _G.ItemTextFrame
        if type(frame) == "table" and frame.HookScript then
            frame:HookScript("OnEvent", function(_, event)
                if event == "ITEM_TEXT_READY" then dressLetter(Kit) end
            end)
        end
    end })
Engine.Window({ key = "bank", pack = "npc", frame = "BankFrame", watch = true })
Engine.Window({ key = "tabard", pack = "npc", frame = "TabardFrame" })
Engine.Window({ key = "petition", pack = "npc", frame = "PetitionFrame", light = true })
Engine.Window({ key = "registrar", pack = "npc", frame = "GuildRegistrarFrame", light = true })
-- The old flight map draws the map into the window's InsetBg, so that's kept
-- with our window around it.
Engine.Window({ key = "taxi", pack = "npc", frame = "TaxiFrame", window = { keep = { "InsetBg" } } })

for _, win in ipairs({ { "quest", "QuestFrame", ours }, { "gossip", "GossipFrame", ours }, { "merchant", "MerchantFrame", oursShop } }) do
    Engine.Window({ key = win[1] .. ":parts", pack = "npc", frame = win[2], window = false, watch = true, skip = win[3] })
end
Engine.Window({ key = "trainer:parts", pack = "npc", addon = "Blizzard_TrainerUI", frame = "ClassTrainerFrame",
    window = false, watch = true })
