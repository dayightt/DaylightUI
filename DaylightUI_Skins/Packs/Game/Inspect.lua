-- The game's own Inspect window, in the Daylight UI look, for players who pick it over
-- Daylight UI's (Win.Swap). Never walked while Daylight UI's window covers it.

local _, ns = ...
local Engine = ns.Engine

local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
                "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand",
                "Ranged", "Ammo" }

local function covered()
    local I = DaylightUI.Inspect and DaylightUI.Inspect.Window
    return type(I) == "table" and type(I.Covers) == "function" and I.Covers() == true
end

-- Its equipment slots: the slot art goes, the icon sits on a dark square with its
-- quality outline, like the bags and Daylight UI's own inspect window.
local function slot(Kit, b)
    if type(b) ~= "table" then return end
    Kit.Hide(b.BorderFrame)
    Kit.Item(b)
end

local hooked = false
Engine.Window({ key = "inspect", pack = "system", addon = "Blizzard_InspectUI", frame = "InspectFrame",
    watch = true, skip = covered,
    after = function(Kit)
        for _, s in ipairs(SLOTS) do slot(Kit, _G["Inspect" .. s .. "Slot"]) end
        -- The game shows and hides an empty slot's border by hand, not through
        -- SetItemButtonQuality, so the outline is recolored after each update.
        if not hooked and type(InspectPaperDollItemSlotButton_Update) == "function" then
            hooked = true
            hooksecurefunc("InspectPaperDollItemSlotButton_Update", Kit.SlotQuality)
        end
    end })
