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

-- The quest text the world map's quest log borrows from the game's quest
-- window (QuestInfo_Display moves it to whichever shows a quest). The rewards
-- have a frame of their own on the map, so they aren't here.
local QUEST_TITLES = { "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader" }
local QUEST_TEXT = { "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoGroupSize",
                     "QuestInfoRewardText", "QuestInfoQuestType" }

local function objectiveLines()
    local objectives = g("QuestInfoObjectivesFrame")
    return type(objectives) == "table" and type(objectives.Objectives) == "table" and objectives.Objectives or {}
end

-- Lights that text for a quest opened from the map's log (System pack), which
-- must work without this pack.
function ns.LightQuestInfo(Kit)
    for _, n in ipairs(QUEST_TITLES) do Kit.Light(g(n), Kit.HEADER) end
    for _, n in ipairs(QUEST_TEXT) do Kit.Light(g(n)) end
    for _, fs in ipairs(objectiveLines()) do Kit.Light(fs) end
end

-- Hands that text back when the game's own quest window shows it. The game
-- colors it again only when the parchment changes, so its colors are put back
-- here the way QuestInfo_Display picks them. Objective lines it colors each
-- time, so they only stop being relit.
function ns.DarkQuestInfo(Kit)
    local text, title
    if type(GetMaterialTextColors) == "function" then
        local info = g("QuestInfoFrame")
        local contrast = _G.QuestTextContrast
        local stone = type(contrast) == "table" and type(contrast.UseLightText) == "function"
            and contrast.UseLightText() == true
        text, title = GetMaterialTextColors(stone and "Stone" or (type(info) == "table" and info.material or nil))
    end
    for _, n in ipairs(QUEST_TITLES) do Kit.Unlight(g(n), title) end
    for _, n in ipairs(QUEST_TEXT) do Kit.Unlight(g(n), text) end
    for _, fs in ipairs(objectiveLines()) do Kit.Unlight(fs) end
end

-- ---------------------------------------------------------------------
-- Flight map (load on demand): the Daylight border around the map, no panel over it.
-- ---------------------------------------------------------------------

Engine.Register({ key = "flightmap", pack = "npc", addon = "Blizzard_FlightMap", apply = function(Kit)
    local f = g("FlightMapFrame")
    if not f then return end
    local border = f.BorderFrame or f
    Kit.Window(border, { noBackground = true })
end })

-- ---------------------------------------------------------------------
-- Beast Training. The NPC window's trainer page replaces the game's trainer
-- window, but buying there is only allowed from the game's own window, so the
-- NPC window lends it back for Beast Training. Dressed the first time that
-- happens; a class trainer's window stays hidden and bare.
-- ---------------------------------------------------------------------

local trainerHooked = false
local beastTraining = { key = "trainer", pack = "npc",
    -- Dressed while it shows as itself: Beast Training lent back, the game's trainer
    -- picked over Daylight UI's, or the trainer page switched off.
    skip = function()
        local N = DaylightUI.Npc
        if not N then return true end
        if N.trainerLent then return false end
        local W = N.Window
        return not (type(W) == "table" and type(W.Covers) == "function") or W.Covers("trainer") == true
    end,
    apply = function(Kit)
        local f = g("ClassTrainerFrame")
        if not f then return false end
        Kit.Window(f)
        Kit.Inset(f.BottomInset or g("ClassTrainerFrameBottomInset"))
        Kit.Button(g("ClassTrainerTrainButton"))
        Kit.Dropdown(f.FilterDropdown or g("ClassTrainerFrameFilterDropdown"))
        Kit.ScrollBar(f.ScrollBar)
        Kit.StatusBar(g("ClassTrainerStatusBar"), { 0.35, 0.55, 0.9 })
        -- The game's text colors stay: they show what you can learn.
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
        -- Only this function shows or hides a row's selection art, when the list
        -- fills and on a pick, so the row is repainted after it.
        if not trainerHooked and type(ClassTrainerFrame_InitServiceButton) == "function" then
            trainerHooked = true
            hooksecurefunc("ClassTrainerFrame_InitServiceButton", function(b) Kit.RepaintRow(b) end)
        end
    end }
Engine.Register(beastTraining)
DaylightUI.On("TrainerLent", function() Engine.Try(beastTraining) end)

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
    -- The close and the title sit where Daylight UI windows put them. The game's
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
-- with a Daylight window around it. The game puts the map 4 px from the left, 6 from
-- the right and bottom and straight under a 24 px title strip, with the title and the
-- X in its corners. Here the title and the X sit where every Daylight UI window has
-- them and the map has the same room on every side, the window growing to make it.
-- Only InsetBg is moved: the route and the flight points hang from it (the route map
-- is anchored to its corners, each button to its bottom left), so they go with it.
local TAXI_MARGIN = 12 -- px between the window's edge (or the header) and the map
local taxiMap = setmetatable({}, { __mode = "k" }) -- window -> the map's size, from the game's anchors

local function taxiPlace(frame, want)
    local same = frame:GetNumPoints() == #want
    for i = 1, same and #want or 0 do
        local point, rel, relPoint, x, y = frame:GetPoint(i)
        local w = want[i]
        if point ~= w[1] or rel ~= w[2] or relPoint ~= w[3] or type(x) ~= "number" or type(y) ~= "number"
            or math.abs(x - w[4]) > 0.01 or math.abs(y - w[5]) > 0.01 then
            same = false
            break
        end
    end
    if same then return end
    frame:ClearAllPoints()
    for _, w in ipairs(want) do frame:SetPoint(w[1], w[2], w[3], w[4], w[5]) end
end

local function taxiLayout(f)
    local Win = DaylightUI.Win
    local bg = f.InsetBg
    if type(bg) ~= "table" or not bg.SetPoint or not f.SetSize or Win.Held(f) then return end
    -- The map's size as the game anchors it, read once: after that InsetBg's own size
    -- follows the window's, which is what is being set here.
    local map = taxiMap[f]
    if not map then
        local w, h = bg:GetWidth(), bg:GetHeight()
        if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
        map = { w = w, h = h }
        taxiMap[f] = map
    end
    local m, head = TAXI_MARGIN, Win.COMPACT
    local width, height = m + map.w + m, head + m + map.h + m
    taxiPlace(bg, {
        { "TOPLEFT", f, "TOPLEFT", m, -(head + m) },
        { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -m, m },
    })
    local w, h = f:GetWidth(), f:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or math.abs(w - width) > 0.01 or math.abs(h - height) > 0.01 then
        f:SetSize(width, height)
        -- The panel manager places its neighbours by these.
        Win.PanelAttr(f, "width", width)
        Win.PanelAttr(f, "height", height)
    end
    local close = f.CloseButton
    if type(close) == "table" and close.SetPoint then
        local size = DaylightUI.Widgets and DaylightUI.Widgets.CLOSE or 24
        close:SetSize(size, size)
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", Win.CLOSE_X, Win.CloseY(true))
    end
    local title = f.TitleText
    if type(title) == "table" and title.SetPoint then
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", f, "TOPLEFT", Win.EDGE, Win.TITLE_Y)
        if type(close) == "table" then title:SetPoint("RIGHT", close, "LEFT", -12, 0) end
    end
end

Engine.Window({ key = "taxi", pack = "npc", frame = "TaxiFrame", window = { keep = { "InsetBg" } },
    after = function(_, f) taxiLayout(f) end })

