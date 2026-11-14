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
    T.eq(np.UnitFrame:GetAlpha(), 0, "the game's own frame is still hidden")
end)

T.test("platefix: step 6 puts the plates back and leaves the game's frame alone", function()
    local NP = login()
    runTo(NP, 5)
    local np = C_NamePlate.GetNamePlateForUnit("nameplate1")
    local before = np.stackSet
    runTo(NP, 1)
    local p = NP.Manager.byUnit.nameplate1
    T.truthy(p, "the plate is back on")
    T.eq(np.UnitFrame:GetAlpha(), 1, "the game's own frame stays visible")
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
    T.eq(C_NamePlate.GetNamePlateForUnit("nameplate1").UnitFrame:GetAlpha(), 0, "the game's own frame is hidden again")
    T.truthy(p.stack:IsShown())
end)

T.test("platefix: a round where nothing helped leaves the takeover whole", function()
    local NP = login()
    runTo(NP, NP.Manager.FIX_STEPS)
    NP.Manager.Fix()
    T.isnil(NP.Manager.fixWithout)
end)
