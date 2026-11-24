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
    T.truthy(text:find("=> same, the plate size and click area", 1, true), "what step 1 did: " .. text)
    T.truthy(text:find("  2: ", 1, true), "what step 2 did")
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
    for _ = 1, NP.Manager.FIX_STEPS do NP.Manager.Fix(); stub.RunTimers(); stub.RunTimers() end
    local said = NP.Manager.Fix()
    T.truthy(said:find("every step", 1, true), said)
    local text = shownText()
    T.truthy(text and text:find("no step brought them back", 1, true), tostring(text))
    T.truthy(text:find("  7: ", 1, true), "every step listed")
end)

T.test("platefix: a fight in the gap can't leave the game's plates switched off", function()
    local _, cvars = login()
    local set = _G.SetCVar
    _G.SetCVar = function(k, v) if not InCombatLockdown() then set(k, v) end end -- refused in combat, as in game
    cvars.nameplateShowFriendlyPlayers = "0"
    local after = 0
    DaylightUI.PlateReport.CycleShowSwitches(0.5, function() after = after + 1 end)
    T.eq(cvars.nameplateShowEnemies, "0", "off for the gap")
    stub.EnterCombat()
    stub.RunTimers()
    T.eq(after, 1, "the step carries on")
    T.eq(cvars.nameplateShowEnemies, "0", "refused in the fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(cvars.nameplateShowEnemies, "1", "back on after the fight")
    T.eq(cvars.nameplateShowFriendlyPlayers, "0", "a switch that was off stays off")
end)

T.test("platefix: logging out in the gap puts the switches back first", function()
    local _, cvars = login()
    DaylightUI.PlateReport.CycleShowSwitches(0.5, function() end)
    T.eq(cvars.nameplateShowEnemies, "0")
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(cvars.nameplateShowEnemies, "1")
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
    local addons = C_AddOns
    _G.C_AddOns = setmetatable({
        GetNumAddOns = function() return 65 end,
        GetAddOnInfo = function(i) return "AnotherLoadedAddon" .. i end,
        IsAddOnLoaded = function() return true end,
    }, { __index = addons })
    for i = 1, 200 do
        stub.Advance(7)
        stub.FireEvent("CVAR_UPDATE", "Sound_SFXVolume", tostring(i / 201))
    end
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    local before = table.concat(NP.Manager.CheckLines(1), "\n")
    for _ = 1, NP.Manager.FIX_STEPS do NP.Manager.Fix(); stub.RunTimers(); stub.RunTimers() end
    NP.Manager.Fix()
    local text = shownText()
    _G.C_AddOns = addons
    T.truthy(#text <= DaylightUI.PlateReport.REPORT_MAX, #text)
    T.truthy(text:find(before, 1, true), "the complete pre-step plate snapshot survives all eight steps")
    T.truthy(text:find("  8: ", 1, true), "the last step's counts survive")
    T.truthy(text:find("fight over", 1, true), "the event closest to the failure survives")
    T.truthy(text:find("[Further report lines omitted]", 1, true), "the reader knows when detail was dropped")
    T.truthy(text:find("Daylight UI now:", 1, true), "a busy log never pushes out the held-open count")
    T.truthy(text:find("World UI:", 1, true), "a busy log never pushes out the world switch line")
end)

-- Lines as long as a real 2.1.3 report from a player, whose setup lines took
-- the whole box and left the log of what happened before with no line at all.
T.test("platefix: a report as long as a real one still keeps the moments before step 1", function()
    login()
    local R = DaylightUI.PlateReport
    local snap = { "1", "1", "1", game = 3, ours = 3 }
    local run = { did = {}, trace = {}, log = {}, before = {
        "Daylight UI 2.1.3. Game plates 1, ours 1, spare 39, hidden by platefps=false",
        "Settings: scale=1 offsetY=14 dimOthers=false minions=true friendly bars=false",
        "Game: MinAlpha=0.600000 MaxAlpha=1.000000 OccludedAlphaMult=0.400000 GlobalScale=nil MinScale=1 MaxScale=1 "
            .. "SelectedScale=1 MaxDistance=60 Stacking enemy=true friendly=false",
        "Plate settings: clean",
        "nameplate1: friendly, player=false, minion=false, target=false, behindCamera=false",
        "  game plate shown=true visible=true alpha=0.60 effective=0.60 strata=WORLD scale=0.64 rectValid=true box=can't measure",
        "  above it WorldFrame shown=true visible=true alpha=1.00 effective=1.00 strata=WORLD scale=1.00 rectValid=true "
            .. "box=0,0 1835x768",
        "  game frame onPlate=false held=true clicks=ours box=ours",
        "  ours shown=true visible=true alpha=1.00 effective=0.60 strata=MEDIUM scale=0.64 rectValid=true box=can't measure",
        "  on this plate=true friendly=true nameOnly=true minion=false bar=false name=true group=nil",
        "Nothing looks wrong.",
    } }
    for n = 1, 8 do
        run.trace[n] = { before = snap, after = snap }
        run.did[n] = "the game's plates rebuilt, Daylight UI's back on over the game's own, which stay visible "
            .. "(wait two seconds, and say which of the two you see)"
    end
    for i = 30, 1, -1 do run.log[#run.log + 1] = string.format("  -0:%02d plates +2 -1, moment %d", i, i) end
    local world = { "Other addons: " .. string.rep("SomeAddOn, ", 60) .. "LastAddOn" }
    for i = 1, 10 do
        world[#world + 1] = (i == 9 and "Daylight UI now: " or "Setup line: ") .. string.rep("word=1 ", 18)
    end
    local text = R.BuildFixReport("Daylight UI 2.1.3 platefix: no step brought them back", run, world)
    T.truthy(#text <= R.REPORT_MAX, #text)
    T.truthy(text:find("moment 1\n", 1, true), "the moment closest to step 1 survives: " .. text)
    local kept = 0
    for _ in text:gmatch("plates %+2 %-1, moment") do kept = kept + 1 end
    T.truthy(kept >= 8, "the last minute or so of the log survives, kept " .. kept)
    T.truthy(text:find("  8: ", 1, true), "every step's counts survive")
    T.truthy(text:find("Nothing looks wrong.", 1, true), "the plate's verdict survives")
    T.truthy(text:find("Daylight UI now:", 1, true), "the setup lines survive")
    T.truthy(text:find("Other addons: SomeAddOn", 1, true), "the start of the addon list survives")
    T.truthy(text:find("Other addons:", 1, true), "a busy log never pushes out the addon list")
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
    local log = (text .. "\n\n"):match("(What happened before step 1.-)\n\n")
    T.truthy(log, text)
    local _, fights = log:gsub("fight\n", "")
    T.eq(fights, 1, "the fight after step 1 isn't in it")
    T.falsy(log:find("party1", 1, true), "another unit's vehicle isn't noted")
    T.falsy(log:find("0.50", 1, true), "the UI's fade on the way isn't noted, only out and back")
    T.truthy(log:find("-1:55 fight", 1, true), "minutes and seconds before step 1: " .. log)
    T.truthy(R.LogSize() <= R.LOG_SIZE, "kept to a size")
end)

T.test("platefix: the last loading screen, zone change and lost control stay in the report past the log", function()
    local NP = login()
    local R = DaylightUI.PlateReport
    _G.GetRealZoneText = function() return "Tirisfal Glades" end
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    stub.Advance(300)
    stub.FireEvent("PLAYER_CONTROL_LOST")
    stub.Advance(95)
    stub.FireEvent("PLAYER_CONTROL_GAINED")
    _G.GetRealZoneText = function() return "Undercity" end
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    -- A busy minute pushes all of it out of the log.
    for i = 1, R.LOG_SIZE + 5 do R.Note("thing" .. i) end
    stub.Advance(60)
    local line = R.Travel()
    T.truthy(line:find("loading screens 1 (last -7:35 into Tirisfal Glades)", 1, true), line)
    T.truthy(line:find("zone change -1:00 into Undercity", 1, true), line)
    T.truthy(line:find("control last back -1:00 after 95 s", 1, true), line)
    NP.Manager.Fix()
    local text = NP.Manager.FixReport(1)
    T.truthy(text:find("Travel: loading screens 1", 1, true), "in the report: " .. text)
end)

T.test("platefix: the log keeps only the latest moments, and the same thing again counts up", function()
    login()
    local R = DaylightUI.PlateReport
    for i = 1, R.LOG_SIZE + 10 do R.Note("thing" .. i) end
    T.eq(R.LogSize(), R.LOG_SIZE)
    local text = table.concat(R.LogLines(), "\n")
    T.falsy(text:find("thing1\n", 1, true), "the oldest went")
    T.truthy(text:find("thing" .. (R.LOG_SIZE + 10), 1, true), text)
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.FireEvent("CVAR_UPDATE", "same", "1")
    stub.FireEvent("CVAR_UPDATE", "same", "1")
    text = table.concat(R.LogLines(), "\n")
    T.truthy(text:find("same=1 (x2)", 1, true), text)
end)

T.test("platefix: an addon easing the sound takes one line, not the whole log", function()
    login()
    local R = DaylightUI.PlateReport
    R.Note("fight")
    local base = R.LogSize()
    for step = 1, 9 do
        local k = step / 10
        stub.FireEvent("CVAR_UPDATE", "Sound_MusicVolume", tostring(0.3 + k / 10))
        stub.FireEvent("CVAR_UPDATE", "Sound_AmbienceVolume", tostring(0.5 + k / 10))
        stub.FireEvent("CVAR_UPDATE", "Sound_SFXVolume", tostring(0.9 + k / 10))
        stub.Advance(0.1)
    end
    T.eq(R.LogSize(), base + 1, "one line for the sound")
    local text = table.concat(R.LogLines(), "\n")
    T.truthy(text:find("settings Sound_MusicVolume=0.39 Sound_AmbienceVolume=0.59 Sound_SFXVolume=0.99 (27 changes)",
        1, true), text)
    -- A setting changed long after starts its own line, and one setting alone reads as before.
    stub.Advance(R.FOLD_GAP.settings + 1)
    stub.FireEvent("CVAR_UPDATE", "nameplateShowEnemies", "0")
    stub.FireEvent("CVAR_UPDATE", "nameplateShowEnemies", "1")
    T.eq(R.LogSize(), base + 2)
    text = table.concat(R.LogLines(), "\n")
    T.truthy(text:find("setting nameplateShowEnemies=1 (x2)", 1, true), text)
    -- More settings than fit name the first ones and count the rest.
    stub.Advance(R.FOLD_GAP.settings + 1)
    for i = 1, R.FOLD_NAMES + 3 do stub.FireEvent("CVAR_UPDATE", "s" .. i, "1") end
    text = table.concat(R.LogLines(), "\n")
    T.truthy(text:find("s6=1 +3 more (9 changes)", 1, true), text)
end)

T.test("platefix: a visit to an NPC is one line with its windows and quests", function()
    login()
    local R = DaylightUI.PlateReport
    _G.Enum = _G.Enum or {}
    _G.Enum.PlayerInteractionType = { Gossip = 3, QuestGiver = 4, Trainer = 7 }
    _G.C_QuestLog = _G.C_QuestLog or {}
    _G.C_QuestLog.GetTitleForQuestID = function(id) return id == 452 and "Pyrewood Ambush" or nil end
    R.Note("fight")
    local base = R.LogSize()
    stub.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 3)
    stub.Advance(2)
    stub.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 3)
    stub.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 4)
    stub.Advance(30)
    stub.FireEvent("QUEST_ACCEPTED", 452)
    stub.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 4)
    T.eq(R.LogSize(), base + 1)
    local text = table.concat(R.LogLines(), "\n")
    T.truthy(text:find("NPC Gossip, closed, QuestGiver, took quest Pyrewood Ambush, closed", 1, true), text)
    -- A quest handed in with no NPC window, after a fight, has its own line by its number.
    R.Note("fight")
    stub.FireEvent("QUEST_TURNED_IN", 999, 0, 0)
    text = table.concat(R.LogLines(), "\n")
    T.truthy(text:find("handed in quest 999", 1, true), text)
    T.falsy(text:find("NPC handed in", 1, true), "not called an NPC visit: " .. text)
    -- A secret kind never reaches a comparison.
    stub.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", stub.Secret(7))
    T.truthy(table.concat(R.LogLines(), "\n"):find("NPC ", 1, true))
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
    stub.RunTimers()
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
    T.truthy(said:find("5/" .. NP.Manager.FIX_STEPS, 1, true), said)
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
    T.truthy(#text <= DaylightUI.PlateReport.REPORT_MAX)
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
    for _ = 1, NP.Manager.FIX_STEPS do NP.Manager.Fix(); stub.RunTimers(); stub.RunTimers() end
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
    DaylightUI.RunCommand("flatoff")
    T.eq(printed[1], "flatoff: Nameplates is off")
    printed = {}
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
    local log = (text .. "\n\n"):match("(What happened before step 1.-)\n\n")
    T.truthy(log, text)
    for _, want in ipairs({ "whole UI and plates off by SomeAfkAddon", "UI hidden", "UI shown",
        "plates and bubbles off by a key or the client" }) do
        T.truthy(log:find(want, 1, true), want .. " in: " .. log)
    end
    T.truthy(text:find("World UI: plates and bubbles switch last set off by a key or the client (switch changes: "
        .. "off by SomeAfkAddon -0:00, off by a key or the client -0:00), UI shown true", 1, true),
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

T.test("platefix: step 8 brings the switch for plates and bubbles back", function()
    local NP = login()
    SetInWorldUIVisibility(false)
    T.falsy(stub.inWorldUI, "the UI is up, plates and bubbles aren't")
    local said
    for _ = 1, 8 do
        said = NP.Manager.Fix()
        stub.RunTimers()
        stub.RunTimers()
    end
    T.truthy(said:find("8/" .. NP.Manager.FIX_STEPS, 1, true) and said:find("off and back on", 1, true), said)
    T.truthy(stub.inWorldUI, "plates and bubbles back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Caught live once: the plates and a fresh bubble were there and "visible" to
-- Lua, the switch was never touched, and nothing drew. Setting it on when it's
-- already on may do nothing, so the step switches it off and then back on.
T.test("platefix: step 8 switches plates and bubbles off, then back on", function()
    local NP = login()
    local calls, was = {}, _G.SetInWorldUIVisibility
    _G.SetInWorldUIVisibility = function(v) calls[#calls + 1] = v; was(v) end
    for _ = 1, 7 do NP.Manager.Fix(); stub.RunTimers(); stub.RunTimers() end
    local said = NP.Manager.Fix()
    T.eq(calls[1], false, "off first")
    T.eq(#calls, 1, "on only after a moment")
    stub.RunTimers()
    _G.SetInWorldUIVisibility = was
    T.eq(calls[2], true, "then back on")
    T.truthy(stub.inWorldUI)
    T.truthy(said:find("off and back on", 1, true), said)
    T.truthy(DaylightUI.PlateReport.WorldUI():find("last set on by /dui platefix", 1, true))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Caught live on two PCs: a square made on WorldFrame didn't draw while one on
-- UIParent did, and every Lua read of WorldFrame matched a healthy session.
-- Steps 9 on each change one thing on WorldFrame for a moment and put it back.
local function worldFrame()
    _G.WorldFrame = CreateFrame("Frame", "WorldFrame")
    WorldFrame:SetFrameLevel(1)
    WorldFrame:SetClipsChildren(true)
    return WorldFrame
end

T.test("platefix: steps 9 on change the plates' layer for a moment, then put it back as it was", function()
    local NP = login()
    local wf = worldFrame()
    for _ = 1, 8 do NP.Manager.Fix(); stub.RunTimers(); stub.RunTimers() end
    T.eq(NP.Manager.FIX_STEPS, 8 + #DaylightUI.PlateReport.WORLD_STEPS)
    local seen = {}
    for n = 9, NP.Manager.FIX_STEPS do
        local said = NP.Manager.Fix()
        T.truthy(said:find(n .. "/" .. NP.Manager.FIX_STEPS, 1, true), said)
        T.truthy(said:find("drawn on", 1, true), said)
        seen[n] = { alpha = wf:GetAlpha(), level = wf:GetFrameLevel(), clips = wf:DoesClipChildren(), shown = wf:IsShown() }
        T.truthy(DaylightUI.PlateReport.FixBusy(), "the next step waits until it's put back")
        stub.RunTimers()
        stub.RunTimers()
        T.eq(wf:GetAlpha(), 1, "alpha back after step " .. n)
        T.eq(wf:GetFrameLevel(), 1, "level back after step " .. n)
        T.eq(wf:DoesClipChildren(), true, "clipping back after step " .. n)
        T.truthy(wf:IsShown(), "shown after step " .. n)
    end
    T.truthy(seen[9].alpha < 1, "9 fades it a hair")
    T.eq(seen[10].level, 2, "10 moves it up a level")
    T.eq(seen[11].clips, false, "11 switches the edge cut")
    T.falsy(seen[12].shown, "12 hides it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.WorldFrame = nil
end)

T.test("platefix: a fight starting mid-step puts the plates' layer back once it's over", function()
    local NP = login()
    local wf = worldFrame()
    for _ = 1, 11 do NP.Manager.Fix(); stub.RunTimers(); stub.RunTimers() end
    NP.Manager.Fix() -- step 12 hides it
    T.falsy(wf:IsShown())
    stub.EnterCombat()
    stub.RunTimers()
    T.falsy(wf:IsShown(), "left alone in the fight")
    T.falsy(DaylightUI.PlateReport.FixBusy(), "the run isn't stuck waiting on the fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(wf:IsShown(), "shown again after the fight")
    _G.WorldFrame = nil
end)

T.test("platefix: with the Nameplates module off, the plates' layer steps run too", function()
    stub.Load({ before = function()
        _G.C_NamePlate = { GetNamePlateForUnit = function() end }
        stub.units = { player = { name = "Me", class = "PRIEST", isPlayer = true } }
    end })
    _G.SetCVar = function() end
    _G.GetCVar = function() end
    local wf = worldFrame()
    local R = DaylightUI.PlateReport
    T.eq(#R.FIX, 3 + #R.WORLD_STEPS)
    local said
    for _ = 1, 4 do said = R.Fix(); stub.RunTimers(); stub.RunTimers() end
    T.truthy(said:find("4/" .. #R.FIX, 1, true) and said:find("drawn on", 1, true), said)
    T.eq(wf:GetAlpha(), 1)
    _G.WorldFrame = nil
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

-- The switch has been left off while the UI came back. After a loading screen,
-- a landing, a cinematic, a movie, the UI showing again or a whole-UI fade
-- returning, Daylight UI turns it back on, unless the UI is hidden (Alt+Z) or
-- a fight is on.
T.test("platefix: the switch comes back on after the moments it was lost", function()
    login()
    for _, event in ipairs({ "LOADING_SCREEN_DISABLED", "PLAYER_CONTROL_GAINED", "CINEMATIC_STOP", "STOP_MOVIE" }) do
        SetInWorldUIVisibility(false)
        stub.FireEvent(event)
        T.truthy(stub.inWorldUI, event)
    end
    SetUIVisibility(false)
    UIParent:Show()
    T.truthy(stub.inWorldUI, "the UI shown again")
    SetInWorldUIVisibility(false)
    DaylightUI.Fire("UIAlpha", 0)
    T.falsy(stub.inWorldUI, "not while the UI is faded out")
    DaylightUI.Fire("UIAlpha", 1)
    T.truthy(stub.inWorldUI, "the fade back")
    local text = DaylightUI.PlateReport.WorldUI()
    T.truthy(text:find("last set on by Daylight UI after UI faded back", 1, true), text)
    T.falsy(text:find("switch changes: .-Daylight UI after"), "kept out of the switch changes: " .. text)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("platefix: the switch stays off under Alt+Z and in a fight", function()
    login()
    SetUIVisibility(false)
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    T.falsy(stub.inWorldUI, "Alt+Z kept")
    T.falsy(UIParent:IsShown(), "the UI stays hidden")
    UIParent:Show()
    SetInWorldUIVisibility(false)
    stub.combat = true
    stub.FireEvent("PLAYER_CONTROL_GAINED")
    stub.combat = false
    T.falsy(stub.inWorldUI, "not in a fight")
end)

T.test("platefix: the last step turns the whole UI's switch on too", function()
    login()
    local calls, was = {}, _G.SetUIVisibility
    _G.SetUIVisibility = function(v) calls[#calls + 1] = v; was(v) end
    DaylightUI.PlateReport.InWorldBack()
    T.eq(#calls, 0, "not before the cycle")
    stub.RunTimers()
    _G.SetUIVisibility = was
    T.eq(calls[1], true, "after the cycle, though the plates' switch took")
    T.truthy(DaylightUI.PlateReport.WorldUI():find("last set on by /dui platefix", 1, true))
end)

-- The game re-adds its plates a moment after the switch comes back on. A
-- step that ends at once reads zero plates "after" while they're returning.
T.test("platefix: the last step finishes only after the plates had time to come back", function()
    login()
    local R = DaylightUI.PlateReport
    local queue, was = {}, C_Timer.After
    C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
    R.InWorldBack()
    table.remove(queue, 1)() -- the switch back on
    T.truthy(R.FixBusy(), "still waiting for the game's plates")
    C_Timer.After = was
    for _, fn in ipairs(queue) do fn() end
    T.falsy(R.FixBusy(), "done once they had their moment")
end)

-- Steps 3 and 5 to 8 finish a moment after they're typed. Running the next one
-- (or answering yes) before then mixes two steps, so "step N brought them
-- back" would name the wrong one.
T.test("platefix: the next step waits until the last one has finished", function()
    local NP = login()
    for _ = 1, 2 do NP.Manager.Fix() end
    NP.Manager.Fix() -- step 3 switches the game's plates off and back on, then puts ours back
    local said = NP.Manager.Fix()
    T.truthy(said:find("still finishing", 1, true), said)
    T.eq(NP.Manager.fixStep, 3, "no step used up")
    DaylightUI.RunCommand("platefix yes")
    T.isnil(shownText(), "no report while a step is running")
    stub.RunTimers()
    stub.RunTimers()
    said = NP.Manager.Fix()
    T.truthy(said:find("platefix 4/", 1, true), said)
end)

-- The report's sections freeze at step 1. A short line per step says what the
-- show switches and plate counts were before and after it, and at "yes", near
-- the top so a long report's cut can't reach it.
T.test("platefix: the report traces each step's switches and plates near the top", function()
    local NP, cvars = login()
    cvars.nameplateShowFriendlyPlayers, cvars.nameplateShowFriendlyNpcs = "1", "0"
    C_NamePlate.GetNamePlates = function() return { C_NamePlate.GetNamePlateForUnit("nameplate1") } end
    for _ = 1, 3 do NP.Manager.Fix(); stub.RunTimers(); stub.RunTimers() end
    cvars.nameplateShowEnemies = "0"
    DaylightUI.RunCommand("platefix yes")
    local text = shownText()
    T.truthy(text, "the copy box is up")
    local trace = text:find("Each step, before => after", 1, true)
    T.truthy(trace and trace < text:find(", the plate size", 1, true), text)
    T.truthy(text:find("  3: E1 FP1 FN0 G1 O0 => E1 FP1 FN0 G1 O1, the game", 1, true), text)
    T.truthy(text:find("  At yes: E0 FP1 FN0 G1 O1", 1, true), text)
end)

T.test("platefix: switch changes stay in the report after the log has filled", function()
    local NP = login()
    withStack("", function() SetInWorldUIVisibility(false) end)
    for i = 1, 30 do DaylightUI.PlateReport.Note("someThing" .. i) end
    withStack("", function() SetInWorldUIVisibility(true) end)
    NP.Manager.Fix()
    local text = NP.Manager.FixReport(1)
    local log = (text .. "\n\n"):match("(What happened before step 1.-)\n\n")
    T.truthy(log, text)
    T.falsy(log:find("plates and bubbles off", 1, true), "gone from the log")
    T.truthy(text:find("switch changes: off by a key or the client -0:00, on by a key or the client -0:00", 1, true),
        text)
end)

-- The game can refuse a call in the middle of a step. The step must say so
-- instead of reporting what it only tried.
T.test("platefix: step 2 counts a plate the game refused to take back as failed, and a retry still gives it back", function()
    local NP = login()
    local M = NP.Manager
    local np = C_NamePlate.GetNamePlateForUnit("nameplate1")
    local uf = np.UnitFrame
    T.truthy(M.IsHeld(uf), "Daylight UI holds the game's frame")
    local setParent = uf.SetParent
    uf.SetParent = function() error("refused") end
    M.Fix()
    local said = M.Fix()
    uf.SetParent = setParent
    T.truthy(said:find("0 of 1 plates handed back", 1, true), said)
    T.truthy(said:find("1 refused", 1, true), said)
    T.truthy(#stub.errors >= 1, "the refusal reached the error log")
    T.truthy(M.IsHeld(uf), "still marked as held, so it can be given back later")
    T.truthy(uf:GetParent() ~= np, "not on the plate")
    M.GiveBackFrame(uf, np)
    T.eq(uf:GetParent(), np, "the retry put it back")
    T.falsy(M.IsHeld(uf), "and let it go")
end)

T.test("platefix: step 1 says so when the game refuses the plate size", function()
    local NP = login()
    C_NamePlate.SetNamePlateSize = function() error("size refused") end
    local said = NP.Manager.Fix()
    C_NamePlate.SetNamePlateSize = nil
    T.truthy(said:find("refused", 1, true), said)
    T.truthy(#stub.errors >= 1, "the refusal reached the error log")
    local text = NP.Manager.FixReport(1)
    T.truthy(text:find("size refused", 1, true), "the report carries the game's words")
end)

-- A player with every kind of plate switched off in the game's settings (the
-- game's "Show enemy nameplates" key flips one of them) has no plates to bring
-- back. platefix says so instead of running its steps, and the check says so
-- instead of "Nothing looks wrong".
T.test("platefix: with every plate kind switched off it says so and runs no step", function()
    local NP, cvars = login()
    cvars.nameplateShowEnemies, cvars.nameplateShowFriendlyPlayers, cvars.nameplateShowFriendlyNpcs = "0", "0", "0"
    local said = NP.Manager.Fix()
    T.truthy(said:find("switched off", 1, true), said)
    T.eq(NP.Manager.fixStep, nil, "no step ran")
    local lines = NP.Manager.CheckLines()
    T.truthy(lines[#lines]:find("switched off", 1, true), lines[#lines])
    cvars.nameplateShowFriendlyNpcs = "1"
    said = NP.Manager.Fix()
    T.truthy(said:find("platefix 1/", 1, true), "one kind on: the steps run, " .. said)
end)

T.test("platefix: with the Nameplates module off, every plate kind switched off is said too", function()
    stub.Load({ before = function()
        _G.C_NamePlate = { GetNamePlateForUnit = function() end }
        stub.units = { player = { name = "Me", class = "PRIEST", isPlayer = true } }
    end })
    _G.SetCVar = function() end
    _G.GetCVar = function() return "0" end
    local R = DaylightUI.PlateReport
    local said = R.Fix()
    T.truthy(said:find("switched off", 1, true), said)
    local lines = R.CheckLines()
    T.truthy(lines[#lines]:find("switched off", 1, true), lines[#lines])
end)
