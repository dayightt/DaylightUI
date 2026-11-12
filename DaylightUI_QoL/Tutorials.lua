-- Hide tutorial pop-ups: turns off the game's new-player tips.

local _, ns = ...

local Tutorials = {}
ns.Tutorials = Tutorials
ns.features[#ns.features + 1] = Tutorials

local mod, applied

local function hideFrames()
    for _, name in ipairs({ "TutorialFrame", "TutorialFrameAlertButton" }) do
        local f = _G[name]
        if type(f) == "table" and type(f.Hide) == "function" then f:Hide() end
    end
end

-- keep: the player just turned it on, so what they had is kept for turning it off.
local function apply(on, keep)
    applied = on
    if keep then ns.KeepCVar("showTutorials") end
    local v = on and "0" or (ns.GiveBackCVar("showTutorials") or "1")
    if type(SetCVar) == "function" then SetCVar("showTutorials", v) end
    if on then hideFrames() end
end

local function wanted() return mod and mod.db and mod.db.hideTutorials == true end

-- Only acts when the setting changes (or on login while it is on), so a player
-- who never touches it keeps their own game setting.
function Tutorials.Enable(m)
    mod = m
    if wanted() then apply(true) else applied = false end
end

function Tutorials.Refresh(m)
    mod = m
    local on = wanted()
    if on ~= applied then apply(on, on) end
end
