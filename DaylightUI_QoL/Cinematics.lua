-- Skip cinematics: cutscenes and movies end at once, unless Shift is held.

local _, ns = ...
local L = DaylightUI.L

local Cinematics = {}
ns.Cinematics = Cinematics
ns.features[#ns.features + 1] = Cinematics

local mod, registered

local function wanted()
    if not (mod and mod.db and mod.db.skipCinematics == true) then return false end
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then return false end
    return true
end

function Cinematics.OnCinematicStart()
    if not wanted() then return end
    if type(CinematicFrame_CancelCinematic) == "function" then
        CinematicFrame_CancelCinematic()
    elseif type(StopCinematic) == "function" then
        StopCinematic()
    else
        return
    end
    DaylightUI.Print(L["Skipped a cinematic (hold Shift to watch)."])
end

function Cinematics.OnPlayMovie()
    if not wanted() then return end
    if type(MovieFrame) ~= "table" or type(MovieFrame.StopMovie) ~= "function" then return end
    MovieFrame:StopMovie()
    DaylightUI.Print(L["Skipped a cinematic (hold Shift to watch)."])
end

function Cinematics.Enable(m)
    mod = m
    if registered then return end
    registered = true
    DaylightUI.RegisterEvent("CINEMATIC_START", Cinematics.OnCinematicStart)
    DaylightUI.RegisterEvent("PLAY_MOVIE", Cinematics.OnPlayMovie)
end

function Cinematics.Refresh(m) mod = m end
