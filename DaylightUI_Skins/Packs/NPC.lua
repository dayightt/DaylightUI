-- NPC pack: the game's windows from talking to NPCs that Daylight UI has no
-- window of its own for: flight maps, books and letters, tabards, petitions,
-- the stable. Its quest, gossip, vendor, trainer and bank windows have their
-- own, so with those switched off the game's stay exactly as the game draws
-- them.

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
-- Everything else NPCs show, via Engine.Window.
-- ---------------------------------------------------------------------

-- Books, letters and plaques. The game draws them for parchment: a serif page,
-- a gold page number under the title, and the spellbook's yellow arrows.
-- A new letter sets the font, the colors and the parchment insets again, and
-- each page turn moves the text back down, so this runs on open and on
-- ITEM_TEXT_READY. The HTML box has no GetText, and it only picks up a new
-- font when its text is set, so the text comes from ItemTextGetText.
local LETTER_TAGS = { P = "body", H1 = "title", H2 = "head", H3 = "head" }
local LETTER_GAP = 16 -- the dark box, the same distance from the title and the three edges
local LETTER_PAD = 12 -- the text, in from the dark box
local LETTER_BTN = 22
local LETTER_ROW = 8 -- between a page chevron and the number
local letterListening = false
local letterFonts = {}
local letterSkin

local function letterLabels(Kit, btn)
    if type(btn) ~= "table" or not btn.GetRegions then return end
    for _, r in ipairs({ btn:GetRegions() }) do
        if Kit.Kind(r) == "FontString" then r:SetAlpha(0) end
    end
end

local function shown(f) return type(f) == "table" and f.IsShown and f:IsShown() == true end

local letterBars = setmetatable({}, { __mode = "k" })

-- The panel scroll bar keeps its track even when the page fits, and the track
-- starts below the first line, so that line reads as sitting outside the text.
-- The track spans the text, and it goes away until there is something to scroll.
local function letterScrollBar(scroll)
    if type(scroll) ~= "table" then return end
    local bar = scroll.ScrollBar
    if type(bar) ~= "table" then
        local name = scroll.GetName and scroll:GetName()
        bar = type(name) == "string" and _G[name .. "ScrollBar"]
    end
    if type(bar) == "table" then return bar end
end

local function placeLetterBar(scroll)
    local bar = letterScrollBar(scroll)
    if not bar or not bar.SetPoint then return end
    if not letterBars[bar] then
        letterBars[bar] = true
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
        if scroll.HookScript then
            scroll:HookScript("OnScrollRangeChanged", function(self) placeLetterBar(self) end)
        end
    end
    local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()
    if type(range) == "number" and range > 1 then
        if bar.Show then bar:Show() end
    elseif bar.Hide then
        bar:Hide()
    end
end

-- One font object per role, kept by DressText so a font setting reaches every
-- letter that uses it. SimpleHTML takes the object, not a hand-built SetFont.
local function letterFont(role)
    local Style = DaylightUI.Style
    local obj = letterFonts[role]
    if not obj and type(CreateFont) == "function" then
        obj = CreateFont("DaylightUILetter" .. role)
        letterFonts[role] = obj
    end
    if obj and Style.DressText then Style.DressText(obj, Style.SIZE[role]) end
    return obj
end

-- The game measured the scroll child for the parchment width and the serif.
-- Width and font are different now, so the child's height is measured again.
local function fitLetter(scroll, page)
    if type(page) ~= "table" or type(page.GetContentHeight) ~= "function" then return end
    local height = page:GetContentHeight()
    if type(height) ~= "number" or height <= 0 or not page.SetHeight then return end
    page:SetHeight(height)
    local child = type(scroll) == "table" and scroll.GetScrollChild and scroll:GetScrollChild()
    if type(child) == "table" and child ~= page and child.SetHeight then child:SetHeight(height) end
    if type(scroll) == "table" and type(scroll.UpdateScrollChildRect) == "function" then
        scroll:UpdateScrollChildRect()
    end
end

local function dressLetter(Kit)
    if not (letterSkin and ns.Engine.Wanted(letterSkin)) then return end
    local Style = DaylightUI.Style
    local frame = _G.ItemTextFrame
    local page = _G.ItemTextPageText
    if type(page) == "table" and type(page.SetTextColor) == "function" then
        local ink = Style.INK
        if type(page.SetFontObject) == "function" then
            for tag, role in pairs(LETTER_TAGS) do
                local obj = letterFont(role)
                if obj then page:SetFontObject(tag, obj) end
            end
        end
        page:SetTextColor("P", ink.TEXT[1], ink.TEXT[2], ink.TEXT[3])
        for _, tag in ipairs({ "H1", "H2", "H3" }) do
            page:SetTextColor(tag, ink.TITLE[1], ink.TITLE[2], ink.TITLE[3])
        end
        Kit.LightAll(page, nil, 0)
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", 0, 0)
    end
    -- Prev, the number and next share one row at the bottom right of the dark
    -- box, clear of the voice button VoiceOver drops in the bottom center.
    -- The game still shows only the end that exists.
    local nextb = _G.ItemTextNextPageButton
    local prev = _G.ItemTextPrevPageButton
    local num = _G.ItemTextCurrentPage
    local paging = shown(nextb) or shown(prev) or shown(num)
    local scroll = _G.ItemTextScrollFrame
    local inset
    if type(frame) == "table" then
        inset = frame.Inset
        if type(inset) ~= "table" then
            local name = frame.GetName and frame:GetName()
            inset = type(name) == "string" and _G[name .. "Inset"]
        end
    end
    local title = type(frame) == "table" and type(frame.TitleContainer) == "table" and frame.TitleContainer.TitleText
    if type(inset) == "table" and inset.SetPoint and type(frame) == "table" then
        inset:ClearAllPoints()
        if type(title) == "table" then
            inset:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -LETTER_GAP)
        else
            inset:SetPoint("TOPLEFT", frame, "TOPLEFT", LETTER_GAP, -(LETTER_GAP + 28))
        end
        inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LETTER_GAP, LETTER_GAP)
    end
    local box = type(inset) == "table" and inset or frame
    if type(box) == "table" and type(scroll) == "table" and scroll.SetPoint then
        local foot = paging and (LETTER_PAD + LETTER_BTN + LETTER_ROW) or LETTER_PAD
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", box, "TOPLEFT", LETTER_PAD, -LETTER_PAD)
        scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -LETTER_PAD, foot)
        placeLetterBar(scroll)
    end
    if type(page) == "table" and page.SetWidth and type(frame) == "table" then
        local width = frame.GetWidth and frame:GetWidth()
        local line = type(width) == "number" and width - 2 * LETTER_GAP - 2 * LETTER_PAD
        if type(line) == "number" and line > 40 then page:SetWidth(line) end
        -- Set after the width, so the box wraps to the new line before it is measured.
        -- The game adds the sender under a player's letter, so it goes back on too.
        local text = type(_G.ItemTextGetText) == "function" and _G.ItemTextGetText()
        local creator = type(_G.ItemTextGetCreator) == "function" and _G.ItemTextGetCreator()
        if type(text) == "string" and type(creator) == "string" and creator ~= "" then
            text = text .. "\n\n" .. (_G.ITEM_TEXT_FROM or "From") .. "\n" .. creator .. "\n"
        end
        if type(text) == "string" and text ~= "" and page.SetText then page:SetText(text) end
    end
    fitLetter(scroll, page)
    -- The close and the title sit where our own windows put them. The game's
    -- corner button and its title row sit higher and further right.
    local close = type(frame) == "table" and frame.CloseButton
    if type(close) == "table" and close.SetPoint then
        local size = DaylightUI.Widgets and DaylightUI.Widgets.CLOSE or 24
        close:SetSize(size, size)
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", DaylightUI.Win.CLOSE_X, DaylightUI.Win.CloseY(false))
    end
    if type(title) == "table" and title.SetPoint then
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", DaylightUI.Win.EDGE, DaylightUI.Win.TITLE_Y)
        if type(close) == "table" then
            title:SetPoint("RIGHT", close, "LEFT", -12, 0)
        else
            title:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
        end
        if title.SetJustifyH then title:SetJustifyH("LEFT") end
        if title.SetWordWrap then title:SetWordWrap(false) end
    end
    if type(frame) ~= "table" or type(nextb) ~= "table" then return end
    Kit.PageButton(nextb, "right")
    Kit.PageButton(prev, "left")
    letterLabels(Kit, nextb)
    letterLabels(Kit, prev)
    nextb:SetSize(LETTER_BTN, LETTER_BTN)
    if type(prev) == "table" then prev:SetSize(LETTER_BTN, LETTER_BTN) end
    local level = type(inset) == "table" and inset.GetFrameLevel and inset:GetFrameLevel()
    if type(level) == "number" then
        nextb:SetFrameLevel(level + 2)
        if type(prev) == "table" and prev.SetFrameLevel then prev:SetFrameLevel(level + 2) end
    end
    nextb:ClearAllPoints()
    nextb:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -LETTER_PAD, LETTER_PAD)
    if type(num) == "table" then
        num:ClearAllPoints()
        num:SetPoint("RIGHT", nextb, "LEFT", -LETTER_ROW, 0)
        if num.SetJustifyH then num:SetJustifyH("CENTER") end
        if num.SetJustifyV then num:SetJustifyV("MIDDLE") end
        if num.SetWidth then num:SetWidth(24) end
        Kit.Font(num, Style.SIZE.small)
        Kit.Light(num, Kit.DIM)
    end
    if type(prev) == "table" then
        prev:ClearAllPoints()
        prev:SetPoint("RIGHT", type(num) == "table" and num or nextb, "LEFT", -LETTER_ROW, 0)
    end
end

letterSkin = { key = "itemtext", pack = "npc", frame = "ItemTextFrame", light = true,
    after = function(Kit)
        dressLetter(Kit)
        if letterListening then return end
        letterListening = true
        -- Wanted is false once the pack is off, and dressLetter stops there.
        DaylightUI.On("StyleChanged", function() dressLetter(Kit) end)
        local frame = _G.ItemTextFrame
        if type(frame) == "table" and frame.HookScript then
            frame:HookScript("OnEvent", function(_, event)
                if event == "ITEM_TEXT_READY" then dressLetter(Kit) end
            end)
        end
    end }
Engine.Window(letterSkin)
Engine.Window({ key = "tabard", pack = "npc", frame = "TabardFrame" })
Engine.Window({ key = "petition", pack = "npc", frame = "PetitionFrame", light = true })
Engine.Window({ key = "registrar", pack = "npc", frame = "GuildRegistrarFrame", light = true })
-- The old flight map draws the map into the window's InsetBg, so that's kept
-- with our window around it.
Engine.Window({ key = "taxi", pack = "npc", frame = "TaxiFrame", window = { keep = { "InsetBg" } } })

