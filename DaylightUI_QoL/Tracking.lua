-- Keep tracking on: what you track with a spell (Find Minerals, Find Herbs...)
-- is kept per character and turned back on when the game drops it: after a
-- logout, a loading screen or dying. Turning it off yourself sticks.

local _, ns = ...
local DUI = DaylightUI

local Tracking = {}
ns.Tracking = Tracking
ns.features[#ns.features + 1] = Tracking

Tracking.DELAY = 1    -- seconds after arriving: the client fills its list late
Tracking.SETTLE = 2   -- seconds after turning things on before changes count as the player's

local mod, hooked, was
local settled = false  -- false: a change now is the game's doing, not the player's
local turn = 0         -- each arrival takes over from the one before it

local function wanted() return mod and mod.db and mod.db.keepTracking == true end

local function dead()
    return type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") == true
end

-- Runs fn(index, info) for each kind of tracking a spell turns on.
local function eachSpell(fn)
    local M = C_Minimap
    if type(M) ~= "table" or type(M.GetNumTrackingTypes) ~= "function" then return end
    for i = 1, M.GetNumTrackingTypes() or 0 do
        local info = M.GetTrackingInfo(i)
        if info and info.spellID then fn(i, info) end
    end
end

local function activeSpells()
    local list = {}
    eachSpell(function(_, info)
        if info.active then list[#list + 1] = info.spellID end
    end)
    return list
end

local function remember(list)
    DUI.DB.Character().tracking = #list > 0 and list or nil
end

local function turnBackOn()
    local keep = DUI.DB.Character().tracking
    if type(keep) ~= "table" then return end
    local want = {}
    for _, id in ipairs(keep) do want[id] = true end
    eachSpell(function(i, info)
        if want[info.spellID] and not info.active then C_Minimap.SetTracking(i, true) end
    end)
end

local function arrive()
    settled = false
    turn = turn + 1
    local mine = turn
    C_Timer.After(Tracking.DELAY, function()
        if mine ~= turn or dead() then return end   -- dead: PLAYER_ALIVE / UNGHOST come back here
        DUI.AfterCombat(function()
            if mine ~= turn or dead() then return end
            if wanted() then turnBackOn() end
            C_Timer.After(Tracking.SETTLE, function()
                if mine ~= turn then return end
                settled = true
                -- What the game kept on by itself counts too; nothing on keeps
                -- the list, or a turn-on that failed would forget it.
                local list = activeSpells()
                if wanted() and #list > 0 then remember(list) end
            end)
        end, "qolTracking")
    end)
end

local function changed()
    if settled and wanted() and not dead() then remember(activeSpells()) end
end

local function leave()
    settled = false
    turn = turn + 1
end

function Tracking.Enable(m)
    mod = m
    was = wanted()
    if hooked then return end
    hooked = true
    DUI.RegisterEvent("MINIMAP_UPDATE_TRACKING", changed)
    DUI.RegisterEvent("PLAYER_LEAVING_WORLD", leave)
    DUI.RegisterEvent("PLAYER_DEAD", leave)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        DUI.RegisterEvent(event, arrive)
    end
    arrive()
end

function Tracking.Refresh(m)
    mod = m
    local on = wanted()
    if on and not was then remember(activeSpells()) end
    was = on
end
