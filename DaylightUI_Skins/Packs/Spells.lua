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
-- `PetStableFrame` (retail's `StableFrame` doesn't exist here) with three pet
-- slots (PetStableSlotTemplate). Their slot art is atlases the game shows and
-- hides by state, so they're erased to stay gone. The lock and the empty slot's
-- paw stay, since they tell you what the slot is.
local STABLE_SLOTS = { "PetStableCurrentPet", "PetStableStabledPet1", "PetStableStabledPet2" }
local STABLE_ART = { "currentBackground", "unlockedBackground", "lockedBackground", "currentGlow" }

Engine.Window({ key = "stable", pack = "npc", addon = "Blizzard_StableUI", frame = "PetStableFrame", watch = true,
    after = function(Kit)
        for _, name in ipairs(STABLE_SLOTS) do
            local slot = _G[name]
            if type(slot) == "table" then
                for _, key in ipairs(STABLE_ART) do Kit.Erase(slot[key]) end
                Kit.Item(slot)
            end
        end
    end })
