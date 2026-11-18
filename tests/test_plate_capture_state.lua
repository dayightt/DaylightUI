local stub = require("stub")

local function login(change)
    local np
    local cvars = { nameplateShowEnemies = "1", nameplateShowFriendlyPlayers = "1",
        nameplateShowFriendlyNpcs = "1", nameplateShowEnemyMinions = "1" }
    stub.Load({ nameplates = true, before = function()
        stub.units = {
            player = { name = "Private player", class = "PRIEST", isPlayer = true },
            nameplate1 = { name = "Private mob", isPlayer = false, hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 },
        }
        if change then change(stub.units.nameplate1) end
        _G.C_NamePlate = { GetNamePlateForUnit = function(unit) return unit == "nameplate1" and np or nil end }
        _G.C_NamePlateManager = { IsNamePlateUnitBehindCamera = function() return false end }
        _G.UnitCanAttack = function(_, u) return stub.units[u] and stub.units[u].hostile == true end
        _G.UnitReaction = function(u) return stub.units[u] and stub.units[u].reaction end
        _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
        _G.UnitIsDeadOrGhost = function() return false end
        _G.IsInInstance = function() return false end
        _G.issecure = function() return false end
    end })
    stub.RunTimers()
    np = CreateFrame("Frame", "NamePlate1", WorldFrame)
    np.UnitFrame = CreateFrame("Button", nil, np)
    np.CanBeAccessedInContext = function() return true end
    np.CanChangeHitTestPoints = function() return true end
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.RunTimers()
    local ns = stub.nameplates
    local p = ns.Manager.byUnit.nameplate1
    for _, f in ipairs({p, p.hp, p.name, p.badge}) do f.CanBeAccessedInContext = function() return true end end
    local get = GetCVar
    _G.GetCVar = function(key) if cvars[key] ~= nil then return cvars[key] end return get(key) end
    return ns.Manager, np, p, cvars, ns
end

local function sample(manager, np, reason)
    local state = manager.CaptureState("nameplate1", np)
    T.eq(state.reason, reason)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    return state
end

T.test("plate capture state: healthy snapshot contains only allowlisted state and ephemeral identity", function()
    local manager, np, p = login()
    local state = sample(manager, np)
    T.eq(state.owned, true)
    T.eq(state.expected, true)
    T.eq(state.identity, p)
    T.eq(state.attached, true)
    T.eq(state.nativeShown, true)
    T.eq(state.nativeVisible, true)
    T.eq(state.oursShown, true)
    T.eq(state.oursVisible, true)
    T.eq(state.width, 1, "root is intentionally one unit wide")
    T.eq(state.height, 1, "root is intentionally one unit high")
    local keys = { owned=true, expected=true, reason=true, identity=true, nativeShown=true, nativeVisible=true,
        nativeAlpha=true, nativeScale=true, oursShown=true, oursVisible=true, oursAlpha=true, oursScale=true,
        width=true, height=true, attached=true, barShown=true, nameShown=true, badgeShown=true, minion=true, nameOnly=true }
    for key, value in pairs(state) do
        T.truthy(keys[key], "allowlisted key: " .. key)
        if key ~= "identity" then T.truthy(type(value) == "boolean" or type(value) == "number", key) end
    end
end)

T.test("plate capture state: actual own hide opacity and parent contradictions are distinguishable", function()
    local manager, np, p = login()
    p:Hide()
    T.eq(sample(manager, np, "owned_hidden").expected, true)
    p:Show()
    p:SetAlpha(0)
    sample(manager, np, "owned_alpha_zero")
    p:SetAlpha(1)
    p:SetParent(UIParent)
    sample(manager, np, "owned_detached")
    p:SetParent(np)
    p.nameplate = UIParent
    sample(manager, np, "owned_detached")
    p.nameplate = np
    p.IsVisible = function() return false end
    sample(manager, np, "owned_invisible")
end)

T.test("plate capture state: badges slim minions and friendly name-only plates are legitimate", function()
    local manager, np, p = login(function(u) u.minion = true end)
    T.eq(p.minion, true)
    T.eq(p.hp:IsShown(), false)
    T.eq(p.name:IsShown(), false)
    local state = sample(manager, np)
    T.eq(state.expected, true)
    T.eq(state.badgeShown, true)
    T.eq(state.minion, true)
    DaylightUI:Set("Nameplates", "minionStyle", "bar")
    stub.RunTimers()
    T.eq(p.minionBar, true)
    T.eq(sample(manager, np).expected, true)
    manager, np, p = login(function(u) u.isPlayer, u.friend, u.hostile, u.reaction = true, true, false, 5 end)
    state = sample(manager, np)
    T.eq(state.expected, true)
    T.eq(state.nameOnly, true)
    T.eq(state.barShown, false)
    T.eq(state.nameShown, true)
end)

T.test("plate capture state: corpse and sticky soft-only hides remain intentional", function()
    local manager, np, p = login()
    p:Hide()
    p.corpse = true
    T.eq(sample(manager, np).expected, false)
    p.corpse, p.softOnly = false, true
    T.eq(sample(manager, np).expected, false)
    p.softOnly = false
    stub.units.nameplate1.dead = true
    T.eq(sample(manager, np).expected, false)
    stub.units.nameplate1.dead, stub.units.nameplate1.widgetsOnly = false, true
    T.eq(sample(manager, np).expected, false)
end)

T.test("plate capture state: disabled show switches and intentional dim zero never alert", function()
    local manager, np, p, cvars = login()
    p:Hide()
    cvars.nameplateShowEnemies = "0"
    T.eq(sample(manager, np).expected, false)
    cvars.nameplateShowEnemies = "1"
    p.dimGoal = 0
    T.eq(sample(manager, np).expected, false)
    p.dimGoal = 1
    stub.units.nameplate1.minion = true
    cvars.nameplateShowEnemyMinions = "0"
    T.eq(sample(manager, np).expected, false)
    manager, np, p, cvars = login(function(u) u.isPlayer, u.friend, u.hostile, u.reaction = true, true, false, 5 end)
    p:Hide()
    cvars.nameplateShowFriendlyPlayers = "0"
    T.eq(sample(manager, np).expected, false)
end)

T.test("plate capture state: test and recovery modes suppress owned contradictions", function()
    local manager, np, p = login()
    p:Hide()
    for _, key in ipairs({"testHidden", "fixPaused", "fixStep", "fixWithout"}) do
        manager[key] = true
        T.eq(sample(manager, np).expected, false, key)
        manager[key] = nil
    end
    p.isSample = true
    T.eq(sample(manager, np).expected, false)
end)

T.test("plate capture state: native hidden off-camera and occlusion alpha cannot implicate our plate", function()
    local manager, np, p = login()
    p:Hide()
    np:Hide()
    T.eq(sample(manager, np).expected, false)
    np:Show()
    C_NamePlateManager.IsNamePlateUnitBehindCamera = function() return true end
    T.eq(sample(manager, np).expected, false)
    C_NamePlateManager.IsNamePlateUnitBehindCamera = function() return false end
    np:SetAlpha(0)
    T.eq(sample(manager, np).expected, false)
    np:SetAlpha(0.05)
    T.eq(sample(manager, np).expected, false)
    np:SetAlpha(0.6)
    p:Show()
    T.eq(sample(manager, np).expected, true, "ordinary positive native fading is not a fault")
end)

T.test("plate capture state: missing ours or incomplete assignment cannot establish an expectation", function()
    local manager, np, p = login()
    manager.byUnit.nameplate1 = nil
    local state = sample(manager, np)
    T.eq(state.owned, false)
    T.isnil(state.expected)
    T.isnil(state.identity)
    manager.byUnit.nameplate1 = p
    p:Hide()
    p.unit = nil
    T.isnil(sample(manager, np).expected)
    p.unit, p.laid = "nameplate1", nil
    T.isnil(sample(manager, np).expected)
end)

T.test("plate capture state: forbidden and inaccessible native or owned frames cannot alert", function()
    local manager, np, p = login()
    p:Hide()
    for _, frame in ipairs({np, p}) do
        frame.IsForbidden = function() return true end
        T.isnil(sample(manager, np).expected)
        frame.IsForbidden = function() return false end
        frame.CanBeAccessedInContext = function() return false end
        T.isnil(sample(manager, np).expected)
        frame.CanBeAccessedInContext = function() return true end
    end
end)

T.test("plate capture state: refused secret and malformed root reads never become contradictions", function()
    local manager, np, p = login()
    p:Hide()
    for _, frame in ipairs({np, p}) do
        for _, method in ipairs({"IsShown", "IsVisible", "GetEffectiveAlpha", "GetEffectiveScale", "CanBeAccessedInContext"}) do
            local original = frame[method]
            frame[method] = function() error("private native error") end
            sample(manager, np)
            frame[method] = function() return stub.Secret(0) end
            sample(manager, np)
            frame[method] = function() return "private native result" end
            sample(manager, np)
            frame[method] = original
        end
    end
    local original = p.GetParent
    p.GetParent = function() return stub.Secret(np) end
    sample(manager, np)
    p.GetParent = original
    np.GetEffectiveAlpha = function() return 0/0 end
    sample(manager, np)
end)

T.test("plate capture state: unknown camera unit or CVar reads cannot alert", function()
    local manager, np, p, cvars = login()
    p:Hide()
    local camera = C_NamePlateManager.IsNamePlateUnitBehindCamera
    C_NamePlateManager.IsNamePlateUnitBehindCamera = function() return stub.Secret(false) end
    T.isnil(sample(manager, np).expected)
    C_NamePlateManager.IsNamePlateUnitBehindCamera = camera
    for _, name in ipairs({"UnitExists", "UnitNameplateShowsWidgetsOnly", "UnitIsDead", "UnitIsPlayer", "UnitCanAttack", "UnitIsMinion"}) do
        local fn = _G[name]
        _G[name] = function() return stub.Secret(false) end
        T.isnil(sample(manager, np).expected, name)
        _G[name] = fn
    end
    cvars.nameplateShowEnemies = stub.Secret("1")
    T.isnil(sample(manager, np).expected)
end)

T.test("plate capture state: capture reads no identifying content and writes no frame state", function()
    local manager, np, p = login()
    for _, name in ipairs({"UnitName", "UnitGUID", "UnitFullName"}) do
        _G[name] = function() error("identifying API must not be read") end
    end
    for _, frame in ipairs({np, p, p.hp, p.name, p.badge}) do
        frame.GetName = function() error("frame name must not be read") end
        frame.GetRect = function() error("coordinates must not be read") end
        for _, method in ipairs({"Show", "Hide", "SetAlpha", "SetScale", "SetParent", "SetPoint", "SetSize", "SetAllHitTestPoints"}) do
            frame[method] = function() error("capture must not write") end
        end
    end
    T.eq(sample(manager, np).expected, true)
end)
