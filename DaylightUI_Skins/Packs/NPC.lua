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

-- Books, letters and plaques, printed for parchment.
-- The page is an HTML text box that rebuilds its lines on every page turn in the
-- colors set per tag, so the tags themselves get the light colors; lighting the
-- lines alone lasted only until the next page.
Engine.Window({ key = "itemtext", pack = "npc", frame = "ItemTextFrame", light = true,
    after = function(Kit)
        local page = _G.ItemTextPageText
        if type(page) ~= "table" or type(page.SetTextColor) ~= "function" then return end
        local ink = DaylightUI.Style.INK
        page:SetTextColor("P", ink.TEXT[1], ink.TEXT[2], ink.TEXT[3])
        for _, tag in ipairs({ "H1", "H2", "H3" }) do
            page:SetTextColor(tag, ink.TITLE[1], ink.TITLE[2], ink.TITLE[3])
        end
        Kit.LightAll(page, nil, 0)
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
