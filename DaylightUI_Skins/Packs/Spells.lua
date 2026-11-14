-- The professions book (system pack) and the stable (NPC pack). Each is
-- Engine.Window plus its own art. The spellbook, talents and profession window
-- have their own Daylight UI windows, so no skin here.

local _, ns = ...
local Engine = ns.Engine


-- A profession panel on the overview page (name, spells, skill bar): art
-- removed, row look, our font.
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

-- The professions book: each profession panel gets the row look and our font.
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

-- The hunter's stable. Forever uses the Camelot one (Blizzard_StableUI/Camelot):
-- `PetStableFrame` (retail's `StableFrame` doesn't exist here). The gold rules,
-- the coin box and the frame around the pet sit on their own pieces, above the
-- window strip. Slot frames are atlases the game shows and hides by state, so
-- they're erased to stay gone. The lock and the empty slot's paw stay.
local STABLE_SLOTS = { "PetStableCurrentPet", "PetStableStabledPet1", "PetStableStabledPet2" }
local STABLE_ART = { "currentBackground", "unlockedBackground", "lockedBackground", "currentGlow" }
local STABLE_MONEY = { "PetStableMoneyFrame", "PetStableCostMoneyFrame" }
local askHold = setmetatable({}, { __mode = "k" })
local stableHooked = false
local STABLE_W = 448 -- a little under the 480 pass; the game's panel is 384
local STABLE_H = 570 -- the game's frame is 522; the extra is the gap under the pet
local STABLE_MODEL_Y = -84 -- under the name and the two lines
local STABLE_MODEL_BOTTOM = 182 -- was 150; keeps the pet's own height and opens the gap

local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end

-- The number is the part worth a glance. One flat accent color, not the
-- gradient sweep: a two-digit level would show each digit in another shade.
local function accent(value)
    local r, g, b = DaylightUI.Style.Accent()
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), tostring(value))
end

local function join(a, b)
    a, b = a or "", b or ""
    if a == "" then return b end
    if b == "" then return a end
    return a .. hex(DaylightUI.Style.INK.LABEL) .. " | |r" .. b
end

local function sizeStable(f)
    if type(f) ~= "table" or not f.SetSize then return end
    if InCombatLockdown() then
        DaylightUI.AfterCombat(function() sizeStable(f) end, "skins:stable:size")
        return
    end
    f:SetSize(STABLE_W, STABLE_H)
    if type(_G.SetUIPanelAttribute) == "function" then
        pcall(_G.SetUIPanelAttribute, f, "width", STABLE_W)
        pcall(_G.SetUIPanelAttribute, f, "height", STABLE_H)
    end
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
-- The frame's SelectPet writes one run-on line; this replaces it on each click.
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

Engine.Window({ key = "stable", pack = "npc", addon = "Blizzard_StableUI", frame = "PetStableFrame", watch = true,
    after = function(Kit, f)
        local ink = DaylightUI.Style.INK
        local Win = DaylightUI.Win
        -- Portrait frames hang the X off the corner and leave the title in the
        -- portrait's old spot. Both sit in the header, like our own windows.
        local close = f.CloseButton
        if type(close) == "table" and close.SetPoint then
            close:SetSize(DaylightUI.Widgets.CLOSE, DaylightUI.Widgets.CLOSE)
            close:ClearAllPoints()
            close:SetPoint("TOPRIGHT", f, "TOPRIGHT", Win.CLOSE_X, Win.CloseY(false))
        end
        local title = type(f.TitleContainer) == "table" and f.TitleContainer.TitleText
        if type(title) == "table" and title.SetPoint then
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", f, "TOPLEFT", Win.EDGE, Win.TITLE_Y)
            title:SetPoint("RIGHT", f, "RIGHT", -40, 0)
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
        if not stableHooked and type(hooksecurefunc) == "function" then
            stableHooked = true
            -- The frame keeps its own copy of the mixin methods, so hooking the
            -- mixin table never sees a click.
            -- Ours runs a frame later, not inside the game's own call.
            if type(f.SelectPet) == "function" then
                hooksecurefunc(f, "SelectPet", function(self, index)
                    C_Timer.After(0, function() paintPet(self, index) end)
                end)
            end
            if type(f.Update) == "function" then
                hooksecurefunc(f, "Update", function(self)
                    C_Timer.After(0, function() placeSlots(self) end)
                end)
            end
        end
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
