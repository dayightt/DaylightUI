-- Debug only, not for release. /dui questlog records the tracker's fade state
-- twice a second for a minute into DaylightUIDB.questLog, which the game writes
-- to WTF/Account/<account>/SavedVariables/DaylightUI.lua on /reload or logout.
-- /dui questlog clear removes it.

local _, ns = ...
local DUI = DaylightUI

local Debug = { EVERY = 0.5, FOR = 60 }
ns.Debug = Debug

local ticker

local function line(start)
    local F, t, items = DUI.Fade, _G.DaylightUIQuestTracker, _G.DaylightUIQuestItems
    local now, goal = F.State("Quests.tracker")
    return string.format("%.1f shown=%s alpha=%.2f items=%.2f awake=%s fighting=%s lockdown=%s hushed=%s ui=%.2f fade=%s->%s",
        GetTime() - start, tostring(t and t:IsShown()), t and t:GetAlpha() or -1, items and items:GetAlpha() or -1,
        tostring(ns.Items and ns.Items.Awake and ns.Items.Awake()), tostring(F.fighting), tostring(InCombatLockdown()),
        tostring(F.Hushed()), UIParent:GetAlpha(), tostring(now), tostring(goal))
end

function Debug.Run(rest)
    if ticker then ticker:Cancel(); ticker = nil end
    if rest == "clear" then
        DaylightUIDB.questLog = nil
        print("Daylight UI questlog: cleared, /reload to save")
        return
    end
    local log, start, n, total = {}, GetTime(), 0, Debug.FOR / Debug.EVERY
    DaylightUIDB.questLog = log
    log[1] = line(start)
    ticker = C_Timer.NewTicker(Debug.EVERY, function()
        n = n + 1
        log[#log + 1] = line(start)
        if n >= total then
            ticker = nil
            print("Daylight UI questlog: done, /reload to save it")
        end
    end, total)
    print("Daylight UI questlog: recording for " .. Debug.FOR .. " s")
end

DUI.RegisterCommand("questlog", Debug.Run)
