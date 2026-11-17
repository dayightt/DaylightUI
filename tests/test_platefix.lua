local stub = require("stub")

-- /dui platefix's report. Once a step brought the plates back (or none did),
-- it gives one text to copy and send in: which step, what each step did, where
-- the player was, the game's plate settings, and the plates as they were
-- before step 1.

local function login()
    local plates = {}
    stub.Load({ nameplates = true, before = function()
        -- One mob with a game plate, a small copy of test_nameplates.lua's world.
        _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
            local i = tonumber(string.match(unit, "%d+"))
            if not i or not stub.units[unit] then return nil end
            if not plates[i] then
                local np = CreateFrame("Frame", nil, UIParent)
                np.UnitFrame = CreateFrame("Button", nil, np)
                function np:SetStackingBoundsFrame(f) self.stackSet = (self.stackSet or 0) + 1; self.stackFrame = f end
                plates[i] = np
            end
            return plates[i]
        end }
        _G.issecure = function() return false end
        _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
        _G.IsInInstance = function() return false end
        stub.units = {
            player = { name = "Me", class = "PRIEST", isPlayer = true },
            nameplate1 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 },
        }
    end })
    stub.RunTimers()
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.RunTimers()
    local cvars = {}
    _G.SetCVar = function(k, v) cvars[k] = v end
    _G.GetCVar = function(k) return cvars[k] end
    _G.C_CVar = _G.C_CVar or {}
    C_CVar.GetCVarDefault = function(k) return "default:" .. k end
    cvars.nameplateShowEnemies = "1"
    return stub.nameplates, cvars
end

local function shownText()
    local box = _G.DaylightUIProfileBox
    return box and box:IsShown() and box.edit:GetText() or nil
end

T.test("platefix: yes after a step opens a report naming that step", function()
    local NP = login()
    NP.Manager.Fix()
    local said = NP.Manager.Fix()
    T.truthy(said:find("/dui platefix yes", 1, true), said)
    DaylightUI.RunCommand("platefix yes")
    local text = shownText()
    T.truthy(text, "the copy box is up")
    T.truthy(text:find("step 2 brought them back", 1, true), text)
    T.truthy(text:find("  1. the plate size", 1, true), "what step 1 did")
    T.truthy(text:find("  2. ", 1, true), "what step 2 did")
    T.truthy(text:find("Before step 1:", 1, true), "the plates as they were")
    T.truthy(text:find("Game plates 1, ours 1", 1, true), text)
    T.truthy(text:find("ShowEnemies=1", 1, true), "the game's plate settings")
    T.truthy(text:find("min since login", 1, true), "how long into the session")
    T.isnil(NP.Manager.fixStep, "the round is over")
end)

-- Every report carries the player's screen setup, so reports can be lined up
-- to see what the players who get vanishing plates share.
T.test("platefix: the report says how the game is shown on screen", function()
    local NP, cvars = login()
    cvars.gxMaximize, cvars.gxapi, cvars.maxFPS, cvars.maxFPSBk = "1", "D3D12", "144", "30"
    cvars.useUiScale, cvars.uiScale = "1", "0.71"
    stub.physW, stub.physH = 2560, 1080
    _G.GetMonitorCount = function() return 2 end
    _G.C_VideoOptions = { GetGxAdapterInfo = function() return { { name = "AMD Radeon RX 7800 XT" } } end }
    stub.FireEvent("UI_SCALE_CHANGED")
    stub.FireEvent("UI_SCALE_CHANGED")
    stub.FireEvent("DISPLAY_SIZE_CHANGED")
    local text = table.concat(NP.Manager.ReportWorld(), "\n")
    for _, want in ipairs({ "2560x1080", "monitors=2", "maximized=1", "api=D3D12", "AMD Radeon RX 7800 XT",
        "maxFPS=144", "background=30", "uiScale=0.71", "UIParent=", "scale changes 2", "display changes 1" }) do
        T.truthy(text:find(want, 1, true), want .. " in: " .. text)
    end
    _G.GetMonitorCount, _G.C_VideoOptions = nil, nil
end)

T.test("platefix: after every step with no yes, the report says none did", function()
    local NP = login()
    for _ = 1, NP.Manager.FIX_STEPS do NP.Manager.Fix() end
    local said = NP.Manager.Fix()
    T.truthy(said:find("every step", 1, true), said)
    local text = shownText()
    T.truthy(text and text:find("no step brought them back", 1, true), tostring(text))
    T.truthy(text:find("  7. ", 1, true), "every step listed")
end)

T.test("platefix: yes with no step run asks for a run first, and opens nothing", function()
    local NP = login()
    local box = _G.DaylightUIProfileBox
    if box then box:Hide() end
    DaylightUI.RunCommand("platefix yes")
    T.isnil(shownText())
    T.isnil(NP.Manager.fixStep)
end)

T.test("platefix: the report fits one Discord report, log and all", function()
    local NP = login()
    for i = 1, 200 do
        stub.Advance(7)
        stub.FireEvent("CVAR_UPDATE", "someLongSettingName" .. i, "1")
    end
    NP.Manager.Fix()
    local text = NP.Manager.FixReport(1)
    T.truthy(#text <= NP.Manager.REPORT_MAX, #text)
    T.truthy(text:find("Before step 1:", 1, true), "the log doesn't push the plates out")
    T.truthy(text:find("nameplate1:", 1, true), text)
    T.eq(NP.Manager.REPORT_PLATES, 1)
end)

-- Players can't say what they did before the plates went (their reasons have
-- been wrong before), so the report carries a log of what happened in the
-- game and in Daylight UI in the minutes before step 1. Events only: nothing
-- runs each frame for it.
T.test("platefix: the report carries a log of what happened before step 1", function()
    local NP = login()
    local R = DaylightUI.PlateReport
    stub.Advance(30)
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.Advance(20)
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.Advance(5)
    stub.FireEvent("LOADING_SCREEN_ENABLED")
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    stub.FireEvent("CVAR_UPDATE", "nameplateShowFriendlyNpcs", "1")
    stub.FireEvent("UI_SCALE_CHANGED")
    stub.FireEvent("DISPLAY_SIZE_CHANGED")
    stub.FireEvent("CINEMATIC_START")
    stub.FireEvent("PLAYER_CONTROL_LOST")
    stub.FireEvent("UNIT_ENTERED_VEHICLE", "party1")
    stub.FireEvent("UNIT_ENTERED_VEHICLE", "player")
    stub.FireEvent("ADDON_RESTRICTION_STATE_CHANGED", 1, 2)
    DaylightUI.Fire("AfkScreenShown")
    DaylightUI.Fade.SetUIAlpha(0.5)
    DaylightUI.Fade.SetUIAlpha(0)
    DaylightUI.Fade.SetUIAlpha(0)
    DaylightUI.Fade.SetUIAlpha(1)
    local f = CreateFrame("Frame", nil, UIParent)
    f.SetFlattensRenderLayers = function() end
    f.SetIsFrameBuffer = function() end
    DaylightUI.Fade.Whole(f, "test", true)
    stub.RunTimers()
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.Advance(90)
    NP.Manager.Fix()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    local text = NP.Manager.FixReport(1)
    T.truthy(text:find("What happened before step 1", 1, true), text)
    for _, want in ipairs({ "fight", "fight over", "loading screen", "zone ", "nameplateShowFriendlyNpcs=1",
        "UI scale changed", "screen size changed", "cinematic", "lost control", "vehicle",
        "restriction 1=2", "AFK screen", "UI faded out", "UI back", "buffers drawn 1", "plates +1 -1" }) do
        T.truthy(text:find(want, 1, true), want .. " in: " .. text)
    end
    local log = text:match("What happened before step 1.-Before step 1:")
    T.truthy(log, text)
    local _, fights = log:gsub("fight\n", "")
    T.eq(fights, 1, "the fight after step 1 isn't in it")
    T.falsy(log:find("party1", 1, true), "another unit's vehicle isn't noted")
    T.falsy(log:find("0.50", 1, true), "the UI's fade on the way isn't noted, only out and back")
    T.truthy(log:find("-1:55 fight", 1, true), "minutes and seconds before step 1: " .. log)
    T.truthy(R.LogSize() <= R.LOG_SIZE, "kept to a size")
end)

T.test("platefix: the log keeps only the latest moments, and the same thing again counts up", function()
    login()
    local R = DaylightUI.PlateReport
    for i = 1, R.LOG_SIZE + 10 do
        stub.FireEvent("CVAR_UPDATE", "setting" .. i, "1")
    end
    T.eq(R.LogSize(), R.LOG_SIZE)
    local text = table.concat(R.LogLines(), "\n")
    T.falsy(text:find("setting1=1\n", 1, true), "the oldest went")
    T.truthy(text:find("setting" .. (R.LOG_SIZE + 10) .. "=1", 1, true), text)
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.FireEvent("CVAR_UPDATE", "same", "1")
    stub.FireEvent("CVAR_UPDATE", "same", "1")
    text = table.concat(R.LogLines(), "\n")
    T.truthy(text:find("same=1 (x2)", 1, true), text)
end)

T.test("platefix: the log is in the report with the Nameplates module off too", function()
    stub.Load({ before = function()
        _G.C_NamePlate = { GetNamePlateForUnit = function() end }
        stub.units = { player = { name = "Me", class = "PRIEST", isPlayer = true } }
    end })
    _G.SetCVar = function() end
    _G.GetCVar = function() end
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    DaylightUI.RunCommand("platefix")
    DaylightUI.RunCommand("platefix yes")
    local text = shownText()
    T.truthy(text and text:find("What happened before step 1", 1, true), tostring(text))
    T.truthy(text:find("fight", 1, true), text)
end)

-- Steps 5 to 7 rebuild the game's plates like step 3, then put the Daylight UI
-- plates back with one part of the takeover left out, to find the part that
-- stops them drawing.
local function runTo(NP, step)
    local said
    for _ = 1, step do
        said = NP.Manager.Fix()
        stub.RunTimers()
        stub.RunTimers()
    end
    return said
end

T.test("platefix: step 5 puts the plates back without the stacking frame", function()
    local NP = login()
    runTo(NP, 4)
    local np = C_NamePlate.GetNamePlateForUnit("nameplate1")
    local before = np.stackSet
    local said = runTo(NP, 1)
    T.truthy(said:find("5/8", 1, true), said)
    local p = NP.Manager.byUnit.nameplate1
    T.truthy(p, "the plate is back on")
    T.truthy(np.stackSet > before, "the game's plate was pointed somewhere new")
    T.eq(np.stackFrame, np, "at itself: spaced by nothing of ours")
    T.falsy(p.stack:IsShown(), "and the stacking frame is put away")
    T.falsy(np.UnitFrame:GetParent() == np, "the game's own frame is still off its plate")
end)

T.test("platefix: step 6 puts the plates back and leaves the game's frame alone", function()
    local NP = login()
    runTo(NP, 5)
    local np = C_NamePlate.GetNamePlateForUnit("nameplate1")
    local before = np.stackSet
    runTo(NP, 1)
    local p = NP.Manager.byUnit.nameplate1
    T.truthy(p, "the plate is back on")
    T.eq(np.UnitFrame:GetParent(), np, "the game's own frame stays on its plate")
    T.truthy(np.UnitFrame:IsVisible(), "and visible")
    T.truthy(np.stackSet > before, "the stacking frame is handed over again")
    T.truthy(p.stack:IsShown())
end)

T.test("platefix: step 7 puts the plates back on newly built plates", function()
    local NP = login()
    local old = NP.Manager.byUnit.nameplate1
    runTo(NP, 7)
    local p = NP.Manager.byUnit.nameplate1
    T.truthy(p, "the plate is back on")
    T.truthy(p ~= old, "a plate built just now, not one from login")
    local np = C_NamePlate.GetNamePlateForUnit("nameplate1")
    T.falsy(np.UnitFrame:GetParent() == np, "the game's own frame is off its plate again")
    T.truthy(p.stack:IsShown())
end)

-- All 40 plates built in one frame froze the game for a moment, and the
-- plates' flash was missed.
T.test("platefix: step 7 builds its plates a few a frame, then rebuilds the game's", function()
    local NP, cvars = login()
    runTo(NP, 6)
    local P = NP.Plate
    -- Each timer's run counts as a frame of its own.
    local create, after, frames = P.Create, C_Timer.After, { 0 }
    P.Create = function(...)
        frames[#frames] = frames[#frames] + 1
        return create(...)
    end
    C_Timer.After = function(t, fn) return after(t, function() frames[#frames + 1] = 0; fn() end) end
    NP.Manager.Fix()
    for _ = 1, 3 do stub.RunTimers() end
    P.Create, C_Timer.After = create, after
    local made, most, busy = 0, 0, 0
    for _, n in ipairs(frames) do
        made, most = made + n, math.max(most, n)
        if n > 0 then busy = busy + 1 end
    end
    T.eq(made, NP.Manager.PREPARE, "every plate built")
    T.truthy(most <= NP.Manager.FRESH_PER_FRAME, "only a few in any one frame: " .. most)
    T.eq(busy, NP.Manager.PREPARE / NP.Manager.FRESH_PER_FRAME, "spread over frames")
    T.eq(cvars.nameplateShowEnemies, "1", "the game's plates switched off and on after")
    T.truthy(NP.Manager.byUnit.nameplate1, "and Daylight UI's back on")
end)

T.test("platefix: a round where nothing helped leaves the takeover whole", function()
    local NP = login()
    runTo(NP, NP.Manager.FIX_STEPS)
    NP.Manager.Fix()
    T.isnil(NP.Manager.fixWithout)
end)

-- The copy box came up empty in game with the real report. The report carried
-- the stacking setting's raw value (shown as a box glyph in chat: a byte that
-- isn't a letter) and, on a Chinese client, zone and addon names whose last
-- character the length cut could split in half.
local function clean(text)
    for i = 1, #text do
        local b = text:byte(i)
        if (b < 32 and b ~= 10) or b == 127 then return false, "control byte " .. b .. " at " .. i end
    end
    local i = 1
    while i <= #text do
        local b = text:byte(i)
        local n = b < 0x80 and 0 or (b >= 0xF0 and b < 0xF8) and 3 or (b >= 0xE0) and 2 or (b >= 0xC2) and 1 or -1
        if n < 0 then return false, "bad UTF-8 at " .. i end
        for k = 1, n do
            local c = text:byte(i + k)
            if not c or c < 0x80 or c > 0xBF then return false, "cut UTF-8 at " .. i end
        end
        i = i + n + 1
    end
    if text:gsub("||", ""):find("|", 1, true) then return false, "a lone | (the box reads it as a code)" end
    return true
end

T.test("platefix: the report is plain text the copy box can show, and goes to chat too", function()
    local NP = login()
    C_CVar.GetCVar = function(k)
        if k == "nameplateStackingTypes" then return "\001A" end
        return GetCVar(k)
    end
    _G.Enum = _G.Enum or {}
    Enum.NamePlateStackType = { None = 0, Enemy = 1, Friendly = 2 }
    C_CVar.GetCVarBitfield = function(_, i) return i == 1 end
    _G.GetRealZoneText = function() return "暴风城|cffff0000" .. string.rep("区", 900) end
    NP.Manager.Fix()
    local printed = {}
    local was = DaylightUI.Print
    DaylightUI.Print = function(msg) printed[#printed + 1] = tostring(msg) end
    DaylightUI.RunCommand("platefix yes")
    DaylightUI.Print = was
    local text = shownText()
    T.truthy(text and #text > 0, "the box has the report")
    local ok, why = clean(text)
    T.truthy(ok, why)
    T.truthy(#text <= NP.Manager.REPORT_MAX)
    T.truthy(text:find("Stacking enemy=true friendly=false", 1, true), "the stacking setting in words")
    local chat = table.concat(printed, "\n")
    T.truthy(chat:find("step 1 brought them back", 1, true), "the report is in chat as well: " .. chat)
end)

-- The report says which parts of Daylight UI were on, and the live state of the
-- things only Daylight UI does outside its plates, so reports from players who
-- lose their plates can be lined up.
T.test("platefix: the report names Daylight UI's modules and its own global pieces as they are", function()
    local NP = login()
    local text = table.concat(NP.Manager.ReportWorld(), "\n")
    T.truthy(text:find("Daylight UI modules on: Nameplates", 1, true), text)
    T.truthy(text:find("off: UnitFrames", 1, true), text)
    T.truthy(text:find("buffers drawn 0", 1, true), text)
    T.truthy(text:find("UIParent alpha 1.00", 1, true), text)
    local f = CreateFrame("Frame", nil, UIParent)
    f.SetFlattensRenderLayers = function() end
    f.SetIsFrameBuffer = function() end
    DaylightUI.Fade.Whole(f, "test", true)
    stub.RunTimers()
    text = table.concat(NP.Manager.ReportWorld(), "\n")
    T.truthy(text:find("buffers drawn 1", 1, true), text)
end)

-- Players send a screenshot with the platefix report, so the dots that show
-- where the game has each plate go up with step 1 and stay to the end.
T.test("platefix: the dots go up at step 1, follow new plates and stay until the run is over", function()
    local NP = login()
    local R = DaylightUI.PlateReport
    local printed = {}
    local was = DaylightUI.Print
    DaylightUI.Print = function(msg) printed[#printed + 1] = tostring(msg) end
    NP.Manager.Fix()
    T.truthy(R.marksOn, "up with the first step")
    T.truthy(table.concat(printed, "\n"):find("numbered dot", 1, true), "and the player is told what they are")
    local np = C_NamePlate.GetNamePlateForUnit("nameplate1")
    T.eq(select(2, R.marks[1].dot:GetPoint(1)), np, "pinned to the game's plate")
    stub.RunTimers()
    stub.RunTimers()
    T.truthy(R.marksOn, "still up: they don't time out during a run")
    stub.units.nameplate2 = { name = "Whelp", hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 }
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
    stub.RunTimers()
    T.truthy(R.marks[2] and R.marks[2].dot:IsShown(), "a plate that shows up later gets its dot")
    T.truthy(R.marksOn)
    printed = {}
    DaylightUI.RunCommand("platefix yes")
    DaylightUI.Print = was
    T.truthy(table.concat(printed, "\n"):find("screenshot", 1, true), "the end asks for the screenshot")
    T.truthy(R.marksOn, "the dots are still there for it")
    stub.RunTimers()
    T.falsy(R.marksOn, "and go a while after")
    stub.units.nameplate2 = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("platefix: a run where no step helped ends with the dots up for the screenshot", function()
    local NP = login()
    local R = DaylightUI.PlateReport
    for _ = 1, NP.Manager.FIX_STEPS do NP.Manager.Fix() end
    stub.RunTimers()
    stub.RunTimers()
    T.truthy(R.marksOn, "up through every step")
    local printed = {}
    local was = DaylightUI.Print
    DaylightUI.Print = function(msg) printed[#printed + 1] = tostring(msg) end
    DaylightUI.RunCommand("platefix")
    DaylightUI.Print = was
    T.truthy(table.concat(printed, "\n"):find("screenshot", 1, true), table.concat(printed, "\n"))
    T.truthy(R.marksOn)
    stub.RunTimers()
    T.falsy(R.marksOn)
end)

-- It happens with the Nameplates module off too, so the check and the fix
-- steps that don't need it work without it.
T.test("platefix: /dui platecheck and /dui platefix work with the Nameplates module off", function()
    local cvars = {}
    stub.Load({ before = function()
        local np = CreateFrame("Frame", nil, UIParent)
        _G.C_NamePlate = { GetNamePlateForUnit = function(unit) if unit == "nameplate1" then return np end end }
        _G.issecure = function() return false end
        stub.units = {
            player = { name = "Me", class = "PRIEST", isPlayer = true },
            nameplate1 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 60, maxHealth = 100 },
        }
    end })
    _G.SetCVar = function(k, v) cvars[k] = v end
    _G.GetCVar = function(k) return cvars[k] end
    _G.C_CVar = _G.C_CVar or {}
    C_CVar.GetCVarDefault = function(k) return "default:" .. k end
    cvars.nameplateShowEnemies = "1"
    local printed = {}
    local was = DaylightUI.Print
    DaylightUI.Print = function(msg) printed[#printed + 1] = tostring(msg) end
    DaylightUI.RunCommand("platecheck")
    local check = table.concat(printed, "\n")
    T.truthy(check:find("Nameplates module off", 1, true), check)
    T.truthy(check:find("Game plates 1", 1, true), check)
    T.truthy(check:find("nameplate1", 1, true), check)
    T.truthy(check:find("1 marker", 1, true), "the markers work without the module: " .. check)
    printed = {}
    DaylightUI.RunCommand("platefix")
    T.eq(cvars.nameplateShowEnemies, "0", "the game's plates switched off")
    stub.RunTimers()
    stub.RunTimers()
    T.eq(cvars.nameplateShowEnemies, "1", "and on again")
    T.truthy(DaylightUI.PlateReport.marksOn, "the dots stay up through the run without the module too")
    DaylightUI.RunCommand("platefix")
    T.eq(cvars.nameplateMaxDistance, "default:nameplateMaxDistance", "plate settings to the game's defaults")
    printed = {}
    DaylightUI.RunCommand("platefix yes")
    T.truthy(table.concat(printed, "\n"):find("screenshot", 1, true), "the end asks for the screenshot")
    DaylightUI.Print = was
    local text = shownText()
    T.truthy(text and text:find("step 2 brought them back", 1, true), tostring(text))
    T.truthy(text:find("Daylight UI modules on:", 1, true), text)
    T.truthy(text:find("Nameplates module off", 1, true), text)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Speech bubbles vanish with the plates, and /reload brings both back. The
-- client hides both under one switch of its own (SetUIVisibility on Alt+Z,
-- SetInWorldUIVisibility alone), which Lua can't read. So the log notes every
-- call and who made it, the report counts bubbles, and the last step turns the
-- switch back on.
local function withStack(text, fn)
    local was = _G.debugstack
    _G.debugstack = function() return text end
    local ok, err = pcall(fn)
    _G.debugstack = was
    if not ok then error(err, 0) end
end

T.test("platefix: the log names who switched the plates and bubbles off", function()
    local NP = login()
    withStack('[string "@Interface/AddOns/DaylightUI/PlateReport.lua"]:1: in function\n'
        .. '[string "@Interface/AddOns/SomeAfkAddon/Afk.lua"]:40: in function', function()
        SetUIVisibility(false)
    end)
    UIParent:Show()
    withStack("", function() SetInWorldUIVisibility(false) end)
    NP.Manager.Fix()
    local text = NP.Manager.FixReport(1)
    local log = text:match("What happened before step 1.-Before step 1:")
    T.truthy(log, text)
    for _, want in ipairs({ "whole UI and plates off by SomeAfkAddon", "UI hidden", "UI shown",
        "plates and bubbles off by a key or the client" }) do
        T.truthy(log:find(want, 1, true), want .. " in: " .. log)
    end
    T.truthy(text:find("World UI: plates and bubbles switch last set off by a key or the client, UI shown true", 1, true),
        text)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("platefix: the report counts speech bubbles", function()
    login()
    local shown, hidden = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    hidden:Hide()
    stub.SetBubbles({ shown, hidden })
    local line = DaylightUI.PlateReport.WorldUI()
    T.truthy(line:find("speech bubbles 2 (1 visible)", 1, true), line)
    T.truthy(line:find("never set this session", 1, true), line)
end)

T.test("platefix: the last step turns the game's switch for plates and bubbles back on", function()
    local NP = login()
    SetUIVisibility(false)
    UIParent:Show()
    T.falsy(stub.inWorldUI, "the UI is back, plates and bubbles aren't")
    local said
    for _ = 1, NP.Manager.FIX_STEPS do
        said = NP.Manager.Fix()
        stub.RunTimers()
        stub.RunTimers()
    end
    T.truthy(said:find("8/8", 1, true) and said:find("speech bubbles turned on", 1, true), said)
    T.truthy(stub.inWorldUI, "plates and bubbles back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("platefix: with the Nameplates module off, the last step turns the switch back on too", function()
    stub.Load({ before = function()
        _G.C_NamePlate = { GetNamePlateForUnit = function() end }
        stub.units = { player = { name = "Me", class = "PRIEST", isPlayer = true } }
    end })
    _G.SetCVar = function() end
    _G.GetCVar = function() end
    SetInWorldUIVisibility(false)
    local R = DaylightUI.PlateReport
    for _ = 1, #R.FIX do R.Fix(); stub.RunTimers() end
    T.truthy(stub.inWorldUI)
end)

T.test("platefix: a refused switch says why, and tries the whole UI's switch", function()
    login()
    local was = _G.SetInWorldUIVisibility
    _G.SetInWorldUIVisibility = function() error("blocked") end
    SetUIVisibility(false)
    UIParent:Show()
    local said = DaylightUI.PlateReport.InWorldBack()
    _G.SetInWorldUIVisibility = was
    T.truthy(said:find("UI switch turned on", 1, true), said)
    T.truthy(stub.inWorldUI)
    _G.SetUIVisibility, was = function() error("no") end, _G.SetUIVisibility
    _G.SetInWorldUIVisibility = function() error("blocked") end
    said = DaylightUI.PlateReport.InWorldBack()
    _G.SetUIVisibility = was
    _G.SetInWorldUIVisibility = function(v) stub.inWorldUI = v == true end
    T.truthy(said:find("refused", 1, true) and said:find("blocked", 1, true), said)
end)
