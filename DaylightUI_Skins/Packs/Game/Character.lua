-- The game's own Character window, in the Daylight UI look, for players who pick it over
-- Daylight UI's (Win.Swap), and while Daylight UI's lends it out for a currency
-- transfer. Never walked while Daylight UI's window covers it.
-- The paper doll (slots outlined in their quality, model buttons), the stats list
-- (the game's value colors stay: they show what's buffed), the side tabs and the
-- pages' lists through the shared walk. The currency page is left as the game draws
-- it, since touching it can break transfers.

local _, ns = ...
local Engine = ns.Engine

local function g(name) return _G[name] end

local function covered()
    local F = DaylightUI.Char and DaylightUI.Char.Follow
    return type(F) == "table" and type(F.Covers) == "function" and F.Covers() == true
end

local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
                "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand",
                "Ranged", "Ammo" }

local STAT_DIVIDER = 0.06     -- faint line under each stat
local STAT_HEADER_BAND = 0.35 -- band behind each stats header
local PORTRAIT_CROP = 0.15    -- crops a round portrait to fill its square

-- An equipment slot: the item look, plus the slot ring the game draws around it.
local slotted = setmetatable({}, { __mode = "k" })
local function slot(Kit, b)
    if type(b) ~= "table" or not b.CreateTexture then return end
    Kit.Item(b)
    if slotted[b] then return end
    slotted[b] = true
    Kit.Strip(b.BorderFrame)
    Kit.Hide(b.BorderFrame)
    for _, r in ipairs({ b:GetRegions() }) do
        local atlas = Kit.Kind(r) == "Texture" and r.GetAtlas and r:GetAtlas()
        if type(atlas) == "string" and string.find(atlas, "GearSlot", 1, true) then r:SetAlpha(0) end
    end
    -- Some slots hide their border by hand when shown (the ammo slot).
    if b.HookScript then b:HookScript("OnShow", Kit.SlotQuality) end
    Kit.SlotQuality(b)
end

-- A stats list element: a header (title on a band) or a stat (label, value in the
-- game's color).
local elements = setmetatable({}, { __mode = "k" })
local function statElement(Kit, e)
    if type(e) ~= "table" or not e.CreateTexture then return end
    Kit.Hide(e.Background)
    local Style = DaylightUI.Style
    if type(e.Title) == "table" then
        if not elements[e] then
            elements[e] = true
            local band = e:CreateTexture(nil, "BACKGROUND", nil, -7)
            band:SetColorTexture(0, 0, 0, STAT_HEADER_BAND)
            band:SetAllPoints(e)
        end
        Kit.Font(e.Title, Style.SIZE.head)
        Kit.Light(e.Title)
    elseif type(e.Label) == "table" or type(e.Value) == "table" then
        if not elements[e] then
            elements[e] = true
            local line = e:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 1, 1, STAT_DIVIDER)
            line:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", 6, 0)
            line:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -6, 0)
            line:SetHeight(1)
        end
        Kit.Font(e.Label, Style.SIZE.body)
        Kit.Light(e.Label, Kit.DIM)
        Kit.Font(e.Value, Style.SIZE.body)
    end
end

local function statsPane(Kit, pane)
    if type(pane) ~= "table" then return end
    Kit.Strip(pane)
    Kit.ScrollBar(pane.ScrollBar)
    Kit.EachRow(pane.ScrollBox or pane, function(e) statElement(Kit, e) end)
end

local dressed, hooked = false, false

-- The parts the walk doesn't know by shape, done once.
local function paperDoll(Kit, f)
    Kit.Font(g("CharacterLevelText"), DaylightUI.Style.SIZE.small)
    Kit.Hide(g("CharacterLevelTextBackground"))
    local right = f.RightPaneHost
    Kit.Strip(f.LeftPaneHost)
    if type(right) == "table" then
        Kit.Inset(right)
        Kit.Hide(right.StoneBg)
    end
    Kit.Strip(g("PaperDollFrame"))
    Kit.Strip(g("CharacterModelScene"))

    -- The stats pane's collapse arrow becomes a page button pointing its way. The
    -- pane's own show and hide say when it turned.
    local toggle = f.RightPaneToggleButton
    if type(toggle) == "table" and toggle.HookScript then
        local c = Kit.PageButton(toggle, "left")
        local function point()
            local collapsed = type(right) == "table" and right.IsShown and not right:IsShown()
            if c and c.SetRotation then c:SetRotation(collapsed and Kit.ROTATION.right or Kit.ROTATION.left) end
        end
        if type(right) == "table" and right.HookScript then
            right:HookScript("OnShow", point)
            right:HookScript("OnHide", point)
        end
        toggle:HookScript("OnClick", point)
        point()
    end

    -- The side tabs (character, reputation, skills...); the first is your round
    -- portrait, cropped square. Then the three buttons above the stats.
    local tabs = type(f.ModeTabs) == "table" and type(f.ModeTabs.Tabs) == "table" and f.ModeTabs.Tabs or {}
    for i = 1, 8 do
        Kit.SideTab(tabs[i] or g("CharacterFrameModeTab" .. i), nil, i == 1 and PORTRAIT_CROP or Kit.SIDE_TAB_CROP)
    end
    for i = 1, 3 do Kit.SideTab(g("PaperDollSidebarTab" .. i), nil, i == 1 and PORTRAIT_CROP or nil) end

    local scene = g("CharacterModelScene")
    local controls = type(scene) == "table" and scene.ControlFrame
    if type(controls) == "table" then
        for _, key in ipairs({ "zoomInButton", "zoomOutButton", "rotateLeftButton", "rotateRightButton", "resetButton" }) do
            Kit.IconButton(controls[key])
        end
    end
end

-- The game sets the slots' borders by hand, so each update recolors the outline.
-- Global functions only, hooked once.
local function hookGame(Kit)
    if hooked then return end
    hooked = true
    if type(PaperDollItemSlotButton_Update) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_Update", Kit.SlotQuality)
    end
    if type(PaperDollFrame_UpdateSidebarTabs) == "function" then
        hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", Kit.RepaintRows)
    end
end

Engine.Window({ key = "character", pack = "system", frame = "CharacterFrame", watch = true,
    auto = { skip = { "TokenFrame" } }, skip = covered,
    after = function(Kit, f)
        if not dressed then
            dressed = true
            paperDoll(Kit, f)
            hookGame(Kit)
        end
        for _, s in ipairs(SLOTS) do slot(Kit, g("Character" .. s .. "Slot")) end
        statsPane(Kit, g("CharacterStatsPaneScrollBox"))
        statsPane(Kit, g("CharacterStatsPanePetScrollBox"))
    end })
