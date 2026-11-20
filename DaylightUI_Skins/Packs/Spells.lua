-- The professions book (system pack) and the stable (NPC pack). Each is
-- Engine.Window plus its own art. The spellbook, talents and profession window
-- have their own Daylight UI windows, so no skin here.

local _, ns = ...
local Engine = ns.Engine


-- A profession panel on the overview page (name, spells, skill bar): art
-- removed, row look, the Daylight font.
local function professionPanel(Kit, panel)
    if not Kit.ShellOf(panel) then
        Kit.Strip(panel)
        Kit.Shell(panel, "row")
    end
    for _, r in ipairs({ panel:GetRegions() }) do
        if Kit.Kind(r) == "FontString" then Kit.Font(r) end
    end
    -- The skill bar's expansion picker (retail's Classic/Outland/... lines).
    -- Forever has one line per profession, so it's just a stray box at the
    -- end of the bar. Faded out and made click-through.
    local bar = panel.StatusBar
    local pick = type(bar) == "table" and bar.ExpansionDropdownButton
    if type(pick) == "table" then
        Kit.Hide(pick)
        if pick.EnableMouse then pick:EnableMouse(false) end
    end
end

local function professionPanels(Kit, frame, depth)
    if type(frame) ~= "table" or not frame.GetChildren or depth > 6 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if Kit.Kind(frame.ProfessionName) == "FontString" and Kit.Kind(frame.Background) == "Texture" then
        professionPanel(Kit, frame)
        return
    end
    for _, c in ipairs({ frame:GetChildren() }) do professionPanels(Kit, c, depth + 1) end
end

-- The professions book: each profession panel gets the row look and the Daylight font.
-- Its skill bars are drawn their own way and left alone.
local PROFESSION_PANELS = { "PrimaryProfession1", "PrimaryProfession2",
                            "SecondaryProfession1", "SecondaryProfession2", "SecondaryProfession3" }
local barPaths = {}
for _, key in ipairs(PROFESSION_PANELS) do
    barPaths[#barPaths + 1] = ".ProfessionsContentFrame." .. key .. ".StatusBar"
end

Engine.Window({ key = "professionsbook", pack = "system", addon = "Blizzard_ProfessionsBook", frame = "ProfessionsBookFrame",
    watch = true, auto = { skip = barPaths },
    after = function(Kit, f) professionPanels(Kit, f.ProfessionsContentFrame, 0) end })

-- The game's profession window, for players who pick it over Daylight UI's (or
-- while Daylight UI's lends it out: the guild's crafters, an NPC's crafting). Too
-- much its own for the whole template: only its controls go through it (close,
-- scroll bars, dropdowns, search boxes), the rest by name. Its skill bars keep
-- their own look. Never walked while Daylight UI's window covers it, nor while
-- DaylightMogul's does.
local function professionsCovered()
    if DaylightUI.craftMogul == true then return true end
    local W = DaylightUI.Craft and DaylightUI.Craft.Window
    return type(W) == "table" and type(W.Covers) == "function" and W.Covers() == true
end

local professions = Engine.Window({ key = "professions", pack = "system", addon = "Blizzard_Professions", frame = "ProfessionsFrame",
    watch = true, auto = { controlsOnly = true, rows = false }, skip = professionsCovered,
    after = function(Kit, f)
        Kit.SideTab(f.ProfessionsOverviewTab, nil, Kit.SIDE_TAB_CROP)
        for i = 1, 7 do Kit.SideTab(f["Professions" .. i .. "Tab"], nil, Kit.SIDE_TAB_CROP) end
        professionPanels(Kit, f.BookPage, 0)
        local page = f.CraftingPage
        if type(page) == "table" then
            Kit.Strip(page)
            for _, key in ipairs({ "CreateButton", "CreateAllButton", "ViewGuildCraftersButton" }) do Kit.Button(page[key]) end
            local list = page.RecipeList
            if type(list) == "table" then
                Kit.Inset(list)
                Kit.Hide(list.BackgroundNineSlice)
            end
            local form = page.SchematicForm
            if type(form) == "table" then
                Kit.Inset(form)
                Kit.Hide(form.NineSlice)
                if type(form.OutputIcon) == "table" then Kit.Item(form.OutputIcon) end
            end
        end
    end })

-- The game re-checks its side tabs when a profession opens or a skill changes,
-- with the window already open.
local function professionsAgain()
    local f = _G.ProfessionsFrame
    if type(f) ~= "table" or not f:IsShown() or professionsCovered() then return end
    if professions.again then professions.again() else Engine.Try(professions) end
    ns.Kit.RepaintSoon()
end
DaylightUI.RegisterEvent("TRADE_SKILL_SHOW", professionsAgain)
DaylightUI.RegisterEvent("SKILL_LINES_CHANGED", professionsAgain)

-- The hunter's stable. Forever uses the Camelot one (Blizzard_StableUI/Camelot):
-- `PetStableFrame` (retail's `StableFrame` doesn't exist here). The gold rules,
-- the coin box and the frame around the pet sit on their own pieces, above the
-- window strip. Slot frames are atlases the game shows and hides by state, so
-- they're erased to stay gone. The lock and the empty slot's paw stay.
local STABLE_SLOTS = { "PetStableCurrentPet", "PetStableStabledPet1", "PetStableStabledPet2" }
local STABLE_ART = { "currentBackground", "unlockedBackground", "lockedBackground", "currentGlow" }
local STABLE_MONEY = { "PetStableMoneyFrame", "PetStableCostMoneyFrame" }
local askHold = setmetatable({}, { __mode = "k" })
local stableWatched = false
local STABLE_W = 448 -- a little under the 480 pass; the game's panel is 384
local STABLE_H = 570 -- the game's frame is 522; the extra is the gap under the pet
local STABLE_MODEL_Y = -84 -- under the name and the two lines
local STABLE_MODEL_BOTTOM = 182 -- was 150; keeps the pet's own height and opens the gap

-- The number is the part worth a glance. One flat accent color, not the
-- gradient sweep: a two-digit level would show each digit in another shade.
local function accent(value)
    return DaylightUI.Win.Parts.Hex({ DaylightUI.Style.Accent() }) .. tostring(value) .. "|r"
end

local function join(a, b)
    a, b = a or "", b or ""
    if a == "" then return b end
    if b == "" then return a end
    return a .. DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.LABEL) .. " | |r" .. b
end

local function sizeStable(f)
    if type(f) ~= "table" or not f.SetSize then return end
    if InCombatLockdown() then
        DaylightUI.AfterCombat(function() sizeStable(f) end, "skins:stable:size")
        return
    end
    -- Its panel layout keeps the game's own size: an attribute written here
    -- would carry this addon's taint into the game's next ShowUIPanel.
    f:SetSize(STABLE_W, STABLE_H)
end

local function placeSlots(f)
    local scene = type(f) == "table" and f.modelScene
    local current = _G.PetStableCurrentPet
    local first = _G.PetStableStabledPet1
    local second = _G.PetStableStabledPet2
    if type(scene) ~= "table" or type(current) ~= "table" or not current.ClearAllPoints then return end
    -- The game clusters the three slots under the middle. Current pet on the
    -- left edge, the stabled pair on the right, across the footer.
    current:ClearAllPoints()
    current:SetPoint("TOPLEFT", scene, "BOTTOMLEFT", 28, -34)
    if type(second) == "table" and second.ClearAllPoints then
        second:ClearAllPoints()
        second:SetPoint("TOPRIGHT", scene, "BOTTOMRIGHT", -28, -34)
    end
    if type(first) == "table" and type(second) == "table" and first.ClearAllPoints then
        first:ClearAllPoints()
        first:SetPoint("RIGHT", second, "LEFT", -12, 0)
    end
end

-- Name on its own line, then level | family, then loyalty name | loyalty rank.
-- The game writes one run-on line; this replaces it each time a pet is picked.
local function paintPet(frame, index)
    local api = _G.C_StableInfo
    if type(api) ~= "table" or type(api.GetStablePetInfo) ~= "function" then return end
    -- Nothing is picked yet when the window first opens, and the call wants a
    -- real index.
    local id = index or (type(frame) == "table" and frame.selectedPet)
    if type(id) ~= "number" then return end
    local ok, pet = pcall(api.GetStablePetInfo, id)
    if not ok or type(pet) ~= "table" or type(pet.name) ~= "string" then return end
    local name, detail = _G.PetStableLevelText, _G.PetStableLoyaltyText
    if type(name) ~= "table" or type(detail) ~= "table" then return end
    local Kit = ns.Kit
    local ink = DaylightUI.Style.INK
    Kit.Font(name, DaylightUI.Style.SIZE.head)
    name:SetText(pet.name)
    Kit.Light(name, ink.TITLE)
    if name.SetJustifyH then name:SetJustifyH("CENTER") end
    local level = ""
    if type(pet.level) == "number" and type(_G.UNIT_LEVEL_TEMPLATE) == "string" then
        level = string.format(_G.UNIT_LEVEL_TEMPLATE, pet.level)
        level = (level:gsub(tostring(pet.level), function() return accent(pet.level) end, 1))
    end
    local family = type(pet.familyName) == "string" and pet.familyName or ""
    -- A pet named after its family (a Wolf called "Wolf") says it once, as the game does.
    if family == pet.name then family = "" end
    local loyal = type(pet.loyaltyName) == "string" and pet.loyaltyName or ""
    -- The game's loyalty name already carries the rank ("(Loyalty level 6) Best
    -- Friend"), so the number is colored where it is. Only a name without it
    -- gets the rank appended.
    local rank = ""
    if pet.loyaltyLevel ~= nil then
        local num = tostring(pet.loyaltyLevel)
        local found
        loyal, found = loyal:gsub(num, function() return accent(num) end, 1)
        if found == 0 then rank = accent(num) end
    end
    local row = join(level, family)
    local rest = join(loyal, rank)
    if rest ~= "" then row = row .. "\n" .. rest end
    Kit.Font(detail, DaylightUI.Style.SIZE.small)
    detail:SetText(row)
    Kit.Light(detail, ink.TEXT)
    if detail.SetJustifyH then detail:SetJustifyH("CENTER") end
end

-- The pet's lines and the slots' places are redone a frame after anything that
-- changes them, once however many arrive together, never inside the game's own
-- call. Nothing hooks the game's methods: its callbacks, events and the frame's
-- and slots' own scripts say when.
local stableQueued = false
local function refreshStable()
    if stableQueued then return end
    stableQueued = true
    C_Timer.After(0, function()
        stableQueued = false
        local f = _G.PetStableFrame
        if type(f) ~= "table" or not (f.IsShown and f:IsShown()) then return end
        DaylightUI.SafeCall(paintPet, f)
        DaylightUI.SafeCall(placeSlots, f)
    end)
end

local function watchStable(f)
    if stableWatched then return end
    stableWatched = true
    f:HookScript("OnShow", refreshStable)
    -- A click on a pet slot picks it. The slots are ours to script, the frame's
    -- method that writes the lines is not.
    for _, name in ipairs(STABLE_SLOTS) do
        local slot = _G[name]
        if type(slot) == "table" and slot.HookScript then slot:HookScript("OnClick", refreshStable) end
    end
    local R = _G.EventRegistry
    if type(R) == "table" and R.RegisterCallback then
        for _, e in ipairs({ "StableFrameMixin.PetSelected", "StableFrameMixin.OnSelectedPetChanged" }) do
            DaylightUI.SafeCall(R.RegisterCallback, R, e, refreshStable, "DaylightUI.stable")
        end
    end
    for _, e in ipairs({ "PET_STABLE_UPDATE", "PLAYER_MONEY" }) do
        DaylightUI.RegisterEvent(e, refreshStable)
    end
    DaylightUI.RegisterUnitEvent("UNIT_PET", refreshStable, "player")
end

Engine.Window({ key = "stable", pack = "npc", addon = "Blizzard_StableUI", frame = "PetStableFrame", watch = true,
    after = function(Kit, f)
        local ink = DaylightUI.Style.INK
        local Win = DaylightUI.Win
        -- Portrait frames hang the X off the corner, so it sits in the header like
        -- our own windows'. The title's spot is Kit.Window's, as for every window.
        local close = f.CloseButton
        if type(close) == "table" and close.SetPoint then
            close:SetSize(DaylightUI.Widgets.CLOSE, DaylightUI.Widgets.CLOSE)
            close:ClearAllPoints()
            close:SetPoint("TOPRIGHT", f, "TOPRIGHT", Win.CLOSE_X, Win.CloseY(false))
        end
        for _, name in ipairs(STABLE_SLOTS) do
            local slot = _G[name]
            if type(slot) == "table" then
                for _, key in ipairs(STABLE_ART) do Kit.Erase(slot[key]) end
                if slot.GetCheckedTexture then Kit.Hide(slot:GetCheckedTexture()) end
                Kit.Item(slot)
                Kit.Font(slot.Text, DaylightUI.Style.SIZE.small)
                Kit.Light(slot.Text, ink.LABEL)
            end
        end
        -- Rules across the pet, drawn on frames above the window.
        Kit.Hide(f.TopDividerFrame)
        Kit.Hide(f.BottomDividerFrame)
        Kit.Hide(f.insideFrameBottom)
        local scene = f.modelScene
        if type(scene) == "table" then
            Kit.Strip(scene.Inset)
            if scene.ClearAllPoints then
                scene:ClearAllPoints()
                scene:SetPoint("TOPLEFT", f, "TOPLEFT", 6, STABLE_MODEL_Y)
                scene:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, STABLE_MODEL_BOTTOM)
            end
        end
        for _, name in ipairs(STABLE_MONEY) do
            local mf = _G[name]
            if type(mf) == "table" then Kit.Hide(mf.Border) end
        end
        Kit.Button(f.purchaseButton)
        local bar = f.expBar
        if type(bar) == "table" then
            Kit.ProgressBar(bar)
            Kit.Hide(bar.overlay)
            Kit.Light(bar.Text, ink.TEXT)
        end
        -- The game's panel layout reads the size from the frame's panel
        -- attributes, so they're set through the game's own call (out of
        -- combat), never by writing into UIPanelWindows.
        sizeStable(f)
        -- The pet's name is set again each time you pick one.
        Kit.Font(_G.PetStableLevelText, DaylightUI.Style.SIZE.head)
        Kit.Light(_G.PetStableLevelText, ink.TITLE)
        Kit.Light(_G.PetStableCostLabel, ink.LABEL)
        paintPet(f)
        placeSlots(f)
        watchStable(f)
        -- The buy-a-slot line sits lower in the gap, in the same ink as the slot labels.
        local ask = _G.PetStableSlotText
        local above = _G.PetStableCurrentPet
        local below = f.purchaseButton
        if type(ask) == "table" and type(above) == "table" and type(below) == "table" then
            local hold = askHold[f]
            if not hold then
                hold = CreateFrame("Frame", nil, f)
                hold:EnableMouse(false)
                askHold[f] = hold
            end
            hold:ClearAllPoints()
            hold:SetPoint("TOP", above, "BOTTOM", 0, -28)
            hold:SetPoint("BOTTOM", below, "TOP", 0, 4)
            hold:SetPoint("LEFT", f, "LEFT", 16, 0)
            hold:SetPoint("RIGHT", f, "RIGHT", -16, 0)
            ask:ClearAllPoints()
            ask:SetAllPoints(hold)
            if ask.SetWordWrap then ask:SetWordWrap(false) end
            if ask.SetJustifyH then ask:SetJustifyH("CENTER") end
            if ask.SetJustifyV then ask:SetJustifyV("MIDDLE") end
            Kit.Font(ask, DaylightUI.Style.SIZE.body)
            Kit.Light(ask, ink.LABEL)
        end
    end })
