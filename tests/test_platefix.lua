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

T.test("platefix: the report fits one Discord report", function()
    local NP = login()
    NP.Manager.Fix()
    T.truthy(#NP.Manager.FixReport(1) <= NP.Manager.REPORT_MAX)
    T.eq(NP.Manager.REPORT_PLATES, 2)
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
    T.truthy(said:find("5/7", 1, true), said)
    local p = NP.Manager.byUnit.nameplate1
    T.truthy(p, "the plate is back on")
    T.eq(np.stackSet, before, "the game was handed no stacking frame")
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
