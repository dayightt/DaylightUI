-- The game's character window. Part of the system pack with no switch of its
-- own, since it only shows while the Daylight UI character window is off.
-- Covers the paper doll (slots outlined in quality color, model zoom and rotate
-- buttons), the stats list (the game's value colors are kept, they show what's
-- buffed), the three buttons above it, the side tabs, and the reputation tab.

local _, ns = ...
local Engine = ns.Engine


local function g(name) return _G[name] end

local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
                "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand",
                "Ranged", "Ammo" }

Engine.STAT_DIVIDER = 0.06 -- faint line under each stat
Engine.PORTRAIT_CROP = 0.15 -- crops a round portrait to fill its square
Engine.STAT_HEADER_BAND = 0.35 -- band behind each stats header

-- A stats list element: a header (title with a band behind it) or a stat
-- (dim label, value in the game's color).
local elements = setmetatable({}, { __mode = "k" })

local function statElement(Kit, e)
    if type(e) ~= "table" or not e.CreateTexture then return end
    Kit.Hide(e.Background)
    if type(e.Title) == "table" then
        if not elements[e] then
            elements[e] = true
            local band = e:CreateTexture(nil, "BACKGROUND", nil, -7)
            band:SetColorTexture(0, 0, 0, Engine.STAT_HEADER_BAND)
            band:SetAllPoints(e)
            local line = e:CreateTexture(nil, "ARTWORK")
            line:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", 0, 0)
            line:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0)
            line:SetHeight(2)
            local c = Kit.ROW_BORDER
            line:SetColorTexture(c[1], c[2], c[3], 0.8)
        end
        Kit.Font(e.Title, DaylightUI.Style.SIZE.head)
        Kit.Light(e.Title)
    elseif type(e.Label) == "table" or type(e.Value) == "table" then
        if not elements[e] then
            elements[e] = true
            local line = e:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 1, 1, Engine.STAT_DIVIDER)
            line:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", 6, 0)
            line:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -6, 0)
            line:SetHeight(1)
        end
        Kit.Font(e.Label, DaylightUI.Style.SIZE.body)
        Kit.Light(e.Label, Kit.DIM)
        Kit.Font(e.Value, DaylightUI.Style.SIZE.body)
    end
end

-- A stats pane: box art removed, our scroll bar, elements as above.
local function statsPane(Kit, pane)
    if type(pane) ~= "table" then return end
    Kit.Strip(pane)
    Kit.ScrollBar(pane.ScrollBar)
    Kit.EachRow(pane.ScrollBox or pane, function(e) statElement(Kit, e) end)
end

Engine.Register({ key = "character", pack = "system", apply = function(Kit)
    local f = g("CharacterFrame")
    if not f then return end
    Kit.Window(f)
    Kit.Font(g("CharacterLevelText"), DaylightUI.Style.SIZE.small)
    Kit.Hide(g("CharacterLevelTextBackground"))

    -- Panes: art removed, the stats side a shade darker like an inset.
    local left, right = f.LeftPaneHost, f.RightPaneHost
    Kit.Strip(left)
    if type(right) == "table" then
        Kit.Inset(right)
        Kit.Hide(right.StoneBg)
        for _, child in ipairs({ right:GetChildren() }) do
            if child ~= g("CharacterStatsPaneScrollBox") and child ~= g("CharacterStatsPanePetScrollBox") then
                Kit.Strip(child)
            end
        end
    end
    Kit.Strip(g("PaperDollFrame"))
    Kit.Strip(g("CharacterModelScene"))

    -- The stats pane's collapse arrow becomes a page button pointing its way.
    local toggle = f.RightPaneToggleButton
    if type(toggle) == "table" then
        local c = Kit.PageButton(toggle, "left")
        local function point()
            local collapsed = f.IsRightPaneCollapsed and f:IsRightPaneCollapsed()
            if c then c:SetRotation(collapsed and Kit.ROTATION.right or Kit.ROTATION.left) end
        end
        -- SetRightPaneCollapsed (the arrow, or picking a skill or currency)
        -- shows or hides the pane via RefreshRightPane, so OnShow/OnHide tell
        -- us. No hooks on the window's methods.
        if type(right) == "table" and right.HookScript then
            right:HookScript("OnShow", point)
            right:HookScript("OnHide", point)
        end
        toggle:HookScript("OnClick", point)
        f:HookScript("OnShow", point)
        point()
    end

    -- Equipment slots, recolored as the game updates them.
    for _, s in ipairs(SLOTS) do Kit.Slot(g("Character" .. s .. "Slot")) end
    if type(PaperDollItemSlotButton_Update) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_Update", Kit.SlotQuality)
    end

    statsPane(Kit, g("CharacterStatsPaneScrollBox"))
    statsPane(Kit, g("CharacterStatsPanePetScrollBox"))

    -- The side tabs (character, reputation, skills...). Their icons have the
    -- game's tab frame drawn in, which gets cropped off. The first is your
    -- round portrait, cropped square.
    local modeTabs = f.ModeTabs
    local tabs = {}
    if type(modeTabs) == "table" and type(modeTabs.Tabs) == "table" then tabs = modeTabs.Tabs end
    for i = 1, 8 do
        local tab = tabs[i] or g("CharacterFrameModeTab" .. i)
        Kit.SideTab(tab, nil, i == 1 and Engine.PORTRAIT_CROP or Kit.SIDE_TAB_CROP)
    end

    -- The three buttons above the stats (stats, titles, equipment sets). The
    -- first is your portrait; the others are cut from a sheet and left as is.
    for i = 1, 3 do Kit.SideTab(g("PaperDollSidebarTab" .. i), nil, i == 1 and Engine.PORTRAIT_CROP or nil) end
    if type(PaperDollFrame_UpdateSidebarTabs) == "function" then
        hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", Kit.RepaintRows)
    end
    -- ToggleCharacter checks the side tabs, however the window or a tab is
    -- opened (keybind, micro menu, click).
    if type(ToggleCharacter) == "function" then
        hooksecurefunc("ToggleCharacter", Kit.RepaintSoon)
    end
    f:HookScript("OnShow", Kit.RepaintSoon)

    -- Model zoom and rotate buttons.
    local scene = g("CharacterModelScene")
    local controls = type(scene) == "table" and scene.ControlFrame
    if type(controls) == "table" then
        for _, key in ipairs({ "zoomInButton", "zoomOutButton", "rotateLeftButton", "rotateRightButton", "resetButton" }) do
            Kit.IconButton(controls[key])
        end
    end
end })

-- ---------------------------------------------------------------------
-- The other character tabs: header/row lists with a detail pane (reputation,
-- skills, statistics), PvP rank, and currency. Same template for all: rows via
-- Kit.ListRow, the scroll bar, the lines above and below, and Kit.SidePane.
-- ---------------------------------------------------------------------

-- A tab's list: rows, scroll bar, and the lines above and below it.
local function tabList(Kit, box, bar)
    Kit.ScrollBar(bar)
    if type(box) ~= "table" or not box.GetChildren then return end
    for _, child in ipairs({ box:GetChildren() }) do
        if child ~= box.ScrollTarget and not child.GetElementData then Kit.Strip(child) end
    end
    Kit.EachRow(box, Kit.ListRow)
end

local function listTab(key, frameName, pane, addon)
    Engine.Register({ key = key, pack = "system", addon = addon, apply = function(Kit)
        local f = g(frameName)
        if not f then return end
        Kit.Dropdown(f.filterDropdown or f.FilterDropdown)
        tabList(Kit, f.ScrollBox, f.ScrollBar)
        if pane then Kit.SidePane(f[pane]) end
    end })
end

listTab("reputation", "ReputationFrame", "ReputationDetailFrame")
listTab("skills", "SkillsFrame", "SkillDetailFrame")
listTab("statistics", "StatisticsFrame", nil, "Blizzard_Statistics")

-- PvP rank: the rank display on our panel, plus the detail pane.
Engine.Register({ key = "pvp", pack = "system", apply = function(Kit)
    local f = g("PVPRankFrame")
    if not f then return end
    local info = f.MainInfoFrame
    if type(info) == "table" then
        Kit.Hide(info.Line)
        Kit.LightAll(info, nil, 2)
    end
    Kit.Font(f.SeasonTimerField)
    Kit.SidePane(f.DetailFrame)
end })

-- Inspecting another player: the window and their equipment slots. The
-- Daylight UI inspect window replaces it while that's on.
local inspectHooked = false
local function oursInspect() return DaylightUI.inspectOwnWindow == true end
Engine.Window({ key = "inspect", pack = "system", addon = "Blizzard_InspectUI", frame = "InspectFrame", watch = true,
    skip = oursInspect,
    after = function(Kit)
        for _, s in ipairs(SLOTS) do Kit.Slot(g("Inspect" .. s .. "Slot")) end
        -- Empty slot borders are hidden by hand (no SetItemButtonQuality),
        -- so recolor after each update.
        if not inspectHooked and type(InspectPaperDollItemSlotButton_Update) == "function" then
            inspectHooked = true
            hooksecurefunc("InspectPaperDollItemSlotButton_Update", Kit.SlotQuality)
        end
    end })

-- The character window itself, for anything not covered above.
Engine.Window({ key = "character:parts", pack = "system", frame = "CharacterFrame", window = false, watch = true,
    auto = { skip = { "TokenFrame" } } })

-- Currency: only the scroll bar and detail pane. The list and everything to do
-- with transferring currency between characters are left alone, since touching
-- them can break transfers.
Engine.Register({ key = "currency", pack = "system", addon = "Blizzard_TokenUI", apply = function(Kit)
    local f = g("TokenFrame")
    if not f then return end
    Kit.Dropdown(f.filterDropdown or f.FilterDropdown)
    Kit.ScrollBar(f.ScrollBar)
    local d = f.DetailFrame or g("TokenDetailFrame")
    if type(d) == "table" then
        Kit.SidePane(d, { [d.CurrencyTransferToggleButton or false] = true })
    end
end })
