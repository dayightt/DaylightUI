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
                function np:SetStackingBoundsFrame() end
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

T.test("platefix: after every step with no yes, the report says none did", function()
    local NP = login()
    for _ = 1, NP.Manager.FIX_STEPS do NP.Manager.Fix() end
    local said = NP.Manager.Fix()
    T.truthy(said:find("every step", 1, true), said)
    local text = shownText()
    T.truthy(text and text:find("no step brought them back", 1, true), tostring(text))
    T.truthy(text:find("  4. ", 1, true), "all four steps listed")
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

-- /dui platelog is on for every player and kept over /reload in
-- DaylightUIDB.plateLog. A mark opens a report to copy.
T.test("platelog: records from login, a state row once plates change", function()
    local NP = login()
    local d = _G.DaylightUIDB.plateLog
    T.truthy(type(d) == "table" and d.on, "on by default")
    local seen = {}
    for _, row in ipairs(d.log) do seen[row.what] = true end
    T.truthy(seen.login, "a login row")
    NP.PlateLog.Sample()
    local last = d.log[#d.log]
    T.truthy(last.what == "state" or last.what == "tick", tostring(last.what))
end)

T.test("platelog: mark opens a report that fits one Discord report", function()
    local NP = login()
    for i = 1, 300 do NP.PlateLog.Note("filler", { n = i }) end
    DaylightUI.RunCommand("platelog mark")
    local text = shownText()
    T.truthy(text and text:find("platelog", 1, true), tostring(text))
    T.truthy(text:find("Log, newest first:", 1, true), text)
    T.truthy(#text <= NP.PlateLog.REPORT_MAX, #text)
    local log = _G.DaylightUIDB.plateLog.log
    T.eq(log[#log].what, "MARK")
end)

T.test("platelog: keeps only the newest MAX rows; off writes nothing", function()
    local NP = login()
    local d = _G.DaylightUIDB.plateLog
    for i = 1, NP.PlateLog.MAX + 50 do NP.PlateLog.Note("filler", { n = i }) end
    T.eq(#d.log, NP.PlateLog.MAX)
    T.eq(d.log[#d.log].n, NP.PlateLog.MAX + 50, "the newest kept")
    DaylightUI.RunCommand("platelog")
    T.eq(d.on, false)
    local n = #d.log
    NP.PlateLog.Note("x")
    T.eq(#d.log, n)
end)
