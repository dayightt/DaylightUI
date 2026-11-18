local stub = require("stub")

local function login()
    local np
    stub.Load({ nameplates = true, before = function()
        stub.units = {
            player = { name = "Me", class = "PRIEST", isPlayer = true },
            nameplate1 = { name = "Enemy", isPlayer = false, hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 },
        }
        _G.C_NamePlate = { GetNamePlateForUnit = function(unit) return unit == "nameplate1" and np or nil end }
        _G.UnitCanAttack = function(_, u) return stub.units[u] and stub.units[u].hostile == true end
        _G.UnitReaction = function(u) return stub.units[u] and stub.units[u].reaction end
        _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
        _G.IsInInstance = function() return false end
        _G.issecure = function() return false end
    end })
    stub.RunTimers()
    np = CreateFrame("Frame", "NamePlate1", WorldFrame)
    np.UnitFrame = CreateFrame("Button", nil, np)
    np.UnitFrame.HealthBarsContainer = CreateFrame("Frame", nil, np.UnitFrame)
    np.UnitFrame.HealthBarsContainer.healthBar = CreateFrame("StatusBar", nil, np.UnitFrame.HealthBarsContainer)
    np.UnitFrame.name = np.UnitFrame:CreateFontString(nil, "OVERLAY")
    np.hitWrites = 0
    function np:CanChangeHitTestPoints() return true end
    function np:SetHitTestPoints(points) self.hitWrites = self.hitWrites + 1; self.hitPoints = points end
    function np:SetAllHitTestPoints(frame)
        self:SetHitTestPoints({ {relativeTo = frame}, {relativeTo = frame} })
    end
    function np:ClearAllHitTestPoints() self:SetHitTestPoints({}) end
    function np:GetHitTestPoints() return self.hitPoints end
    function np:SetStackingBoundsFrame(frame) self.stackFrame = frame end
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.RunTimers()
    return stub.nameplates.Manager, np
end

local function check(manager, np, expected, wrongExpected)
    local writes = np.hitWrites
    local lines, wrong = manager.CheckOne("nameplate1", np)
    local text = table.concat(lines, "\n")
    T.truthy(text:find("clicks=" .. expected .. " ", 1, true), text)
    if wrongExpected ~= nil then T.eq(wrong, wrongExpected, text) end
    T.eq(np.hitWrites, writes, "diagnostic never changes click anchors")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    return text
end

T.test("plate hit-test readback: native CVar callback can overwrite clicks without changing our cache", function()
    local manager, np = login()
    check(manager, np, "ours", false)
    local requested = manager.clickOf[np]
    T.truthy(requested)
    T.falsy(np.UnitFrame:IsVisible(), "native frame is parked")
    -- Blizzard_NamePlateUnitFrame UpdateWidgetsOnlyMode calls UpdateHitTestArea
    -- via its separate CVar registry even after UnregisterAllEvents. Model only
    -- its documented anchor write, not a claimed effect on native rendering.
    local function nativeCVarCallback()
        np:SetHitTestPoints({
            {relativeTo = np.UnitFrame.name},
            {relativeTo = np.UnitFrame.HealthBarsContainer.healthBar},
        })
    end
    nativeCVarCallback()
    stub.FireEvent("CVAR_UPDATE", "nameplateShowFriendlyNpcs", "1")
    stub.RunTimers()
    T.eq(manager.clickOf[np], requested, "requested owner did not change")
    local text = check(manager, np, "game", true)
    T.truthy(text:find("clicksExpected=ours", 1, true), text)
    T.truthy(text:find("click area differs", 1, true), text)
end)

T.test("plate hit-test readback: mixed and empty anchors are real mismatches for a clickable enemy", function()
    local manager, np = login()
    np:SetHitTestPoints({ {relativeTo = manager.clickOf[np]}, {relativeTo = np.UnitFrame.name} })
    check(manager, np, "mixed", true)
    np:ClearAllHitTestPoints()
    check(manager, np, "none", true)
end)

T.test("plate hit-test readback: name-only friendly and widgets-only empty clicks are expected", function()
    local manager, np = login()
    local unit = stub.units.nameplate1
    unit.isPlayer, unit.friend, unit.hostile, unit.reaction = true, true, false, 5
    local get = GetCVar
    _G.GetCVar = function(name) if name == manager.NAME_ONLY_CVAR then return "1" end return get(name) end
    np:ClearAllHitTestPoints()
    local text = check(manager, np, "none", false)
    T.truthy(text:find("clicksExpected=none", 1, true), text)
    unit.isPlayer, unit.widgetsOnly = false, true
    text = check(manager, np, "none", false)
    T.truthy(text:find("clicksExpected=none", 1, true), text)
end)

T.test("plate hit-test readback: unreadable eligibility never invents a mismatch", function()
    local manager, np = login()
    np:ClearAllHitTestPoints()
    _G.UnitNameplateShowsWidgetsOnly = function() return stub.Secret(false) end
    local text = check(manager, np, "none", false)
    T.truthy(text:find("clicksExpected=unknown", 1, true), text)
end)

T.test("plate hit-test readback: refused missing and secret getters stay unknown", function()
    local manager, np = login()
    np.GetHitTestPoints = function() error("read refused") end
    check(manager, np, "unknown", false)
    np.GetHitTestPoints = false
    check(manager, np, "unknown", false)
    np.GetHitTestPoints = stub.Secret(function() end)
    check(manager, np, "unknown", false)
    np.GetHitTestPoints = function() return stub.Secret({}) end
    check(manager, np, "unknown", false)
end)

T.test("plate hit-test readback: secret anchors keys and references stay unknown", function()
    local manager, np = login()
    local cases = {
        {stub.Secret({})},
        {{relativeTo = stub.Secret(np.UnitFrame.name)}},
        {[stub.Secret(1)] = {relativeTo = np.UnitFrame.name}},
    }
    for _, points in ipairs(cases) do
        np.hitPoints = points
        check(manager, np, "unknown", false)
    end
end)

T.test("plate hit-test readback: malformed anchors and foreign targets stay unknown", function()
    local manager, np = login()
    local cases = {
        false,
        {false},
        {{}},
        {{relativeTo = "not a frame"}},
        {[2] = {relativeTo = np.UnitFrame}},
        {bad = {relativeTo = np.UnitFrame}},
        {{relativeTo = CreateFrame("Frame", nil, np)}},
    }
    for _, points in ipairs(cases) do
        np.hitPoints = points
        check(manager, np, "unknown", false)
    end
end)

T.test("plate hit-test readback: inaccessible or cyclic ancestry stays unknown", function()
    local manager, np = login()
    local frame = CreateFrame("Frame")
    np.hitPoints = {{relativeTo = frame}}
    frame.GetParent = function() error("parent refused") end
    check(manager, np, "unknown", false)
    frame.GetParent = function() return stub.Secret(np.UnitFrame) end
    check(manager, np, "unknown", false)
    frame.GetParent = function() return frame end
    check(manager, np, "unknown", false)
end)

T.test("plate hit-test readback: platefix leaving game plates visible has no Daylight click expectation", function()
    local manager, np = login()
    manager.fixWithout = "hide"
    np:SetHitTestPoints({{relativeTo = np.UnitFrame.name}})
    local text = check(manager, np, "game", false)
    T.truthy(text:find("clicksExpected=unknown", 1, true), text)
    T.truthy(text:find("boxRequested=ours", 1, true), text)
end)
