local stub = require("stub")

-- /dui worldtest and the session recorder (WorldWatch.lua): tools for plates
-- and speech bubbles that stop drawing until a reload.

local shots
local function login()
    shots = 0
    stub.Load({ before = function()
        _G.WorldFrame = CreateFrame("Frame", "WorldFrame")
        _G.Screenshot = function() shots = shots + 1; stub.FireEvent("SCREENSHOT_SUCCEEDED") end
    end })
    stub.RunTimers()
    return DaylightUI.PlateReport.Watch, DaylightUI.PlateReport
end

local function boxText()
    local box = _G.DaylightUIProfileBox
    return box and box:IsShown() and box.edit:GetText() or nil
end

T.test("worldtest: five squares on five layers, UIParent hidden and back, two screenshots, a report", function()
    local W = login()
    local hidden, squares
    local said = W.Run()
    T.truthy(said:find("hold still", 1, true), said)
    T.truthy(W.Run():find("already running", 1, true), "a second run waits for the first")
    UIParent:HookScript("OnHide", function() hidden = true end)
    stub.RunTimers()
    T.truthy(hidden, "UIParent was hidden for a moment")
    T.truthy(UIParent:IsShown(), "and is back")
    T.eq(shots, 2, "two screenshots")
    local text = boxText()
    T.truthy(text, "the copy box is up")
    T.truthy(text:find("With the UI shown:", 1, true), text)
    T.truthy(text:find("With UIParent hidden:", 1, true), text)
    T.truthy(text:find("WorldFrame: shown", 1, true), text)
    T.truthy(text:find("WorldFrame children: plates 0", 1, true), text)
    T.truthy(text:find("screenshots saved 2", 1, true), text)
    T.truthy(text:find("Session: game stood still", 1, true), "the recorder's lines ride along")
    squares = 0
    for _, c in ipairs({ WorldFrame:GetChildren() }) do if c:IsShown() then squares = squares + 1 end end
    T.eq(squares, 0, "the squares on WorldFrame are gone again")
end)

T.test("worldtest: refused in a fight, nothing hidden", function()
    local W = login()
    stub.combat = true
    T.truthy(W.Run():find("leave combat", 1, true))
    stub.RunTimers()
    T.truthy(UIParent:IsShown())
    T.eq(shots, 0)
    stub.combat = false
end)

T.test("recorder: a long frame is noted, a loading screen is not", function()
    local W, R = login()
    W.Tick()
    stub.Advance(1); W.Tick()
    T.eq(W.stalls.count, 0, "a normal second")
    stub.Advance(4); W.Tick()
    T.eq(W.stalls.count, 1, "four seconds between looks")
    T.truthy(W.stalls.longest >= 4)
    local found
    for _, line in ipairs(R.LogLines()) do if line:find("game stood still", 1, true) then found = true end end
    T.truthy(found, "in the plate log")
    stub.FireEvent("LOADING_SCREEN_ENABLED")
    stub.Advance(10); W.Tick()
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    stub.Advance(1); W.Tick()
    T.eq(W.stalls.count, 1, "a loading screen isn't a stall")
end)

T.test("recorder: the frame rate dropping to the background cap and back", function()
    local W = login()
    local cvars = { useMaxFPSBk = "1", maxFPSBk = "30", useMaxFPS = "0" }
    _G.GetCVar = function(k) return cvars[k] end
    local fps = 140
    _G.GetFramerate = function() return fps end
    W.Tick()
    T.eq(W.capped.count, 0)
    fps = 30; stub.Advance(1); W.Tick()
    T.eq(W.capped.count, 1, "down to the cap")
    T.truthy(W.capped.now)
    fps = 144; stub.Advance(1); W.Tick()
    T.falsy(W.capped.now, "back")
    cvars.useMaxFPSBk = "0"
    T.truthy(W.Lines()[1]:find("can't tell", 1, true), "no cap set: says so")
end)

T.test("recorder: memory samples and graphics restarts reach the report", function()
    local W = login()
    W.Tick()
    stub.FireEvent("GX_RESTARTED")
    local lines = W.Lines()
    T.truthy(lines[1]:find("graphics restarts 1", 1, true), lines[1])
    T.truthy(lines[2]:find("Lua memory", 1, true), lines[2])
    T.falsy(lines[2]:find("none yet", 1, true), "a sample was taken")
end)
