local stub = require("stub")

-- Nameplate pieces built on the threat, cast and group answers: plate size by
-- threat, the interrupt-ready mark, execute icons, the group focus mark and the
-- cast's target.

local plates

local function newPlate(i)
    local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
    np.UnitFrame = CreateFrame("Button", nil, np)
    np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
    function np:CanChangeHitTestPoints() return true end
    function np:SetAllHitTestPoints(f) self.__hit = f end
    function np:SetHitTestPoints() self.__hit = "the game's" end
    function np:ClearAllHitTestPoints() self.__hit = nil end
    function np:SetStackingBoundsFrame(f) self.__stack = f end
    return np
end

local function world()
    plates = {}
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        local i = tonumber(string.match(unit, "%d+"))
        if not i or not stub.units[unit] then return nil end
        plates[i] = plates[i] or newPlate(i)
        return plates[i]
    end }
    _G.issecure = function() return false end
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    _G.UnitReaction = function(u) local x = stub.units[u]; return x and x.reaction end
    _G.IsInInstance = function() return false end
    _G.UnitGroupRolesAssigned = function() return stub.role or "DAMAGER" end
    stub.units = {
        player = { name = "Me", class = "WARRIOR", isPlayer = true },
        nameplate1 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 },
        nameplate2 = { name = "Dark Hound", hostile = true, reaction = 2, health = 90, maxHealth = 100, pct = 90 },
    }
end

local function login(before)
    stub.Load({ nameplates = true, before = function()
        world()
        if before then before() end
    end })
    stub.RunTimers()
    return stub.nameplates
end

local function added(unit)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", unit)
    stub.RunTimers()
    return stub.nameplates.Manager.byUnit[unit]
end

local function threatOn(unit, status, scaled)
    stub.units[unit].threatList = { player = { status = status, scaled = scaled or 0, raw = 0, value = 0 } }
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", unit)
end

T.test("nameplates: plate size by threat is off as shipped and works without threat colors", function()
    local NP = login(function() stub.role = "TANK" end)
    T.eq(NP.DEFAULTS.threatSize, false, "off as shipped")
    local p = added("nameplate1")
    local ui = UIParent:GetEffectiveScale()
    stub.inGroup = true
    threatOn("nameplate1", 0, 40)
    T.near(p:GetScale(), ui, 1e-6, "off: normal size")
    DaylightUI:Set("Nameplates", "threat", false)
    DaylightUI:Set("Nameplates", "threatSize", true)
    stub.RunTimers()
    threatOn("nameplate1", 0, 40)
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6, "a tank who lost it: big")
    threatOn("nameplate1", 2, 100)
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeWarn, 1e-6, "about to lose it")
    threatOn("nameplate1", 3, 100)
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeAggro, 1e-6, "held: small")
    stub.units.nameplate1.threatList = nil
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.near(p:GetScale(), ui, 1e-6, "out of the fight: normal")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: a threat size change is one zoom, never a new layout, and your target keeps its own size", function()
    local NP = login(function() stub.role = "TANK" end)
    DaylightUI:Set("Nameplates", "threatSize", true)
    stub.RunTimers()
    local p = added("nameplate1")
    local ui = UIParent:GetEffectiveScale()
    stub.inGroup = true
    threatOn("nameplate1", 3, 100)
    local laid = p.laid
    local gen = laid.gen
    local layouts = 0
    local real = NP.Body.Layout
    NP.Body.Layout = function(...) layouts = layouts + 1; return real(...) end
    threatOn("nameplate1", 0, 40)
    NP.Body.Layout = real
    T.eq(layouts, 0, "no borders redrawn")
    T.eq(p.laid.gen, gen, "the layout cache kept")
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6)
    -- Your target: its own size wins.
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(p:GetScale(), ui * NP.DEFAULTS.target.scale, 1e-6, "the target's size, not the threat's")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6, "no longer your target: back to its threat size")
    -- Switched off: every plate back to normal.
    DaylightUI:Set("Nameplates", "threatSize", false)
    stub.RunTimers()
    T.near(p:GetScale(), ui, 1e-6, "off: normal")
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: plate size by threat in a boss fight, where the numbers are secret", function()
    local NP = login(function() stub.role = "TANK" end)
    DaylightUI:Set("Nameplates", "threatSize", true)
    stub.RunTimers()
    local p = added("nameplate1")
    local ui = UIParent:GetEffectiveScale()
    stub.inGroup = true
    stub.units.nameplate1.boss = true
    stub.EnterCombat()
    stub.SetRestriction("Encounter", true)
    threatOn("nameplate1", 0, 40)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6, "the state stays plain: sized")
    stub.SetRestriction("Encounter", false)
    stub.LeaveCombat()
    stub.units.nameplate1.boss = nil
    stub.inGroup = false
    stub.role = nil
end)
