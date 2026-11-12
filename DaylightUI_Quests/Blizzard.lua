-- Stops the game's quest tracker before it starts so this one is the only one.
-- The game sets up its tracker once, after PLAYER_ENTERING_WORLD and
-- VARIABLES_LOADED (ObjectiveTrackerManager:Init), through three functions nothing
-- else calls: AddContainer, AssignModulesOrder and SetModuleContainer. Emptied
-- while this addon loads, no container is ever registered, so the game's tracker
-- never gets its sections and never draws. UpdateAll is left alone: Edit Mode's
-- text size calls it, and with no container it loops over nothing. The tracker
-- frame's own events (sorting the watch list on zone change, watching a quest on
-- accept) keep running. Never Hide() it: it's a managed frame and its OnHide would
-- re-lay out the right-side frames from addon code. What's left goes to alpha 0
-- and stops taking the mouse.

local _, ns = ...
local DUI = DaylightUI

local B = {}
ns.Blizzard = B

-- On: this tracker draws.
B.ENABLED = true
B.EMPTIED = { "AddContainer", "AssignModulesOrder", "SetModuleContainer" }
-- Trackers that replace the game's. With one loaded, this one stays off. They load
-- first because the .toc lists them as OptionalDeps.
B.CLASHES = DUI.InstallerPages.ClashesFor("Quests")   -- the setup guide's list

local function noop() end

function B.Clash()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(loaded) ~= "function" then return nil end
    for _, c in ipairs(B.CLASHES) do
        if loaded(c.addon) then return c end
    end
    return nil
end

-- True when the game's tracker won't start.
function B.Starve()
    if B.starved then return true end
    local m = ObjectiveTrackerManager
    if type(m) ~= "table" or B.Clash() then return false end
    for _, name in ipairs(B.EMPTIED) do m[name] = noop end
    if DUI.Taint then
        local known = DUI.Taint.KNOWN.ObjectiveTrackerManager or {}
        for _, name in ipairs(B.EMPTIED) do known[name] = true end
        DUI.Taint.KNOWN.ObjectiveTrackerManager = known
    end
    B.starved = true
    DUI.questsOwnTracker = true
    return true
end

local muted = setmetatable({}, { __mode = "k" })
local function mute(f)
    if type(f) ~= "table" or type(f.EnableMouse) ~= "function" or muted[f] then return end
    muted[f] = true
    f:EnableMouse(false)
end

-- The empty frame left behind: transparent and click-through.
function B.Mute()
    local f = ObjectiveTrackerFrame
    if not (B.starved and type(f) == "table") then return end
    f:SetAlpha(0)
    -- Its background too. Only the emptied AddContainer would have set it to the Edit
    -- Mode opacity, so it sits at full alpha and full frame height: a big black box
    -- whenever the frame returns to alpha 1 (seen on a new character with controller
    -- mode on).
    if type(f.NineSlice) == "table" and f.NineSlice.SetAlpha then f.NineSlice:SetAlpha(0) end
    mute(f)
    if type(f.Header) == "table" then
        mute(f.Header)
        mute(f.Header.MinimizeButton)
    end
    mute(QuestTimerFrame)
end

if B.ENABLED then B.Starve() end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function() B.Mute() end)
