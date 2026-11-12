-- Your DoTs' damage left on the target frame and enemy nameplates
-- (DotsDraw.lua through UnitFrames.lua and Plate.lua).
local stub = require("stub")
local COR, n = 172, 0
local SPELLS = { [COR] = { name = "Corruption", desc = "Corrupts the target, causing 40 Shadow damage over 12 sec." } }

local function login(extra)
    local DUI, UF = stub.Load{ module = true, before = function()
        stub.units.player = { name = "Me", isPlayer = true, class = "WARLOCK", guid = "Player-1" }
        stub.units.target = { name = "Kobold", reaction = 2, guid = "Creature-1", health = 30, maxHealth = 300 }
        stub.spells = SPELLS
        if extra then extra() end
    end }
    DUI.Dots.Forget()
    return DUI, UF
end

local function cast(id)
    n = n + 1
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-" .. n, id)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id)
end

T.test("target frame: a DoT shows the veil, lethal shows the skull", function()
    local _, UF = login()
    local f = UF.frames.target
    T.truthy(f.dotVeil); T.truthy(f.dotSkull)
    T.falsy(f.dotVeil:IsShown())
    cast(COR)
    T.truthy(f.dotVeil:IsShown()); T.eq(f.dotVeil.bar.__value, 40)
    T.eq(f.dotVeil.bar.__max, 300, "the veil is fed max health")
    T.truthy(f.dotSkull:IsShown())
    T.eq(stub.Plain(f.dotSkull.bar.__max), 30, "the skull bar is fed current health")
end)

T.test("target frame: another mob's DoTs changing doesn't redraw it", function()
    local DUI, UF = login()
    local n, orig = 0, UF.UF.UpdateDots
    UF.UF.UpdateDots = function(...) n = n + 1; return orig(...) end
    DUI.Fire("DotsChanged", "Creature-99")
    T.eq(n, 0, "a nameplate mob's tick: nothing here")
    DUI.Fire("DotsChanged", "Creature-1")
    T.eq(n, 1, "the target's own")
    DUI.Fire("DotsChanged", nil)
    T.eq(n, 2, "any number of mobs: redrawn")
    UF.UF.UpdateDots = orig
end)

T.test("target frame: secret health and max (a boss) still draw", function()
    local _, UF = login(function()
        stub.units.target.health, stub.units.target.maxHealth = stub.Secret(30), stub.Secret(300)
    end)
    local f = UF.frames.target
    stub.EnterCombat()
    T.noerror(function() cast(COR) end)
    T.truthy(f.dotVeil:IsShown())
    stub.LeaveCombat()
end)

T.test("target frame: a dead target shows nothing", function()
    local _, UF = login()
    local f = UF.frames.target
    cast(COR)
    stub.units.target.dead = true
    stub.FireEvent("UNIT_HEALTH", "target")
    T.falsy(f.dotVeil:IsShown()); T.falsy(f.dotSkull:IsShown())
end)

T.test("target frame: switching target repaints", function()
    local _, UF = login()
    local f = UF.frames.target
    cast(COR)
    stub.units.target = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.falsy(f.dotVeil:IsShown())
end)

T.test("target frame: the switches turn each piece off", function()
    local DUI, UF = login()
    local f = UF.frames.target
    DUI:Set("UnitFrames", "target.dotSkull", false)
    stub.RunTimers()
    cast(COR)
    T.truthy(f.dotVeil:IsShown()); T.falsy(f.dotSkull:IsShown())
    DUI:Set("UnitFrames", "target.dotTint", false)
    stub.RunTimers()
    T.falsy(f.dotVeil:IsShown())
    T.isnil(DUI.Dots.Left("target"), "nobody wants it: the tracker stops")
end)

T.test("target frame: test mode shows a sample veil and skull", function()
    local DUI, UF = login()
    DUI.SetTestMode(true)
    local f = UF.frames.target
    T.truthy(f.dotVeil:IsShown()); T.truthy(f.dotSkull:IsShown())
    DUI.SetTestMode(false)
end)

T.test("target frame: only the target has the pieces", function()
    local _, UF = login()
    T.isnil(UF.frames.player.dotVeil)
    T.isnil(UF.frames.focus.dotVeil)
end)

-- ---------------------------------------------------------------------
-- Nameplates (the game's plate set up as tests/test_nameplates.lua does)
-- ---------------------------------------------------------------------

local function gamePlates()
    local made = {}
    local function newPlate(i)
        local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
        np.UnitFrame = CreateFrame("Button", nil, np)
        np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
        np.UnitFrame.WidgetContainer = CreateFrame("Frame", nil, np.UnitFrame)
        np.UnitFrame.name = np.UnitFrame:CreateFontString(nil, "OVERLAY")
        function np:CanChangeHitTestPoints() return true end
        function np:SetAllHitTestPoints(f) self.__hit = f end
        function np:SetHitTestPoints() self.__hit = "the game's" end
        function np:ClearAllHitTestPoints() self.__hit = nil end
        function np:SetStackingBoundsFrame(f) self.__stack = f end
        return np
    end
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        local i = tonumber(string.match(unit, "%d+"))
        if not i or not stub.units[unit] then return nil end
        made[i] = made[i] or newPlate(i)
        return made[i]
    end }
    _G.issecure = function() return false end
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    _G.IsInInstance = function() return false end
    _G.C_TooltipInfo = { GetUnit = function() return nil end }
end

local function plates(extra)
    local DUI = stub.Load{ nameplates = true, before = function()
        gamePlates()
        stub.units.player = { name = "Me", isPlayer = true, class = "WARLOCK", guid = "Player-1" }
        stub.units.target = { name = "Kobold", reaction = 2, hostile = true, guid = "Creature-1", health = 30, maxHealth = 300 }
        stub.units.nameplate1 = stub.units.target
        stub.spells = SPELLS
        if extra then extra() end
    end }
    stub.RunTimers()
    DUI.Dots.Forget()
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.RunTimers()
    return DUI, stub.nameplates
end

T.test("plates: your DoTs veil the plate, lethal adds the skull past its right end", function()
    local _, ns = plates()
    local p = ns.Manager.byUnit.nameplate1
    T.truthy(p.dotVeil); T.falsy(p.dotVeil:IsShown())
    cast(COR)
    T.truthy(p.dotVeil:IsShown()); T.eq(p.dotVeil.bar.__value, 40)
    T.truthy(p.dotSkull:IsShown())
    local pt, rel, rp = p.dotSkull:GetPoint(1)
    T.eq(pt, "LEFT"); T.eq(rel, p.hp); T.eq(rp, "RIGHT")
end)

T.test("plates: the skull switch is its own", function()
    local DUI, ns = plates()
    DUI:Set("Nameplates", "dotSkull", false)
    stub.RunTimers()
    cast(COR)
    local p = ns.Manager.byUnit.nameplate1
    T.truthy(p.dotVeil:IsShown()); T.falsy(p.dotSkull:IsShown())
end)

T.test("plates work with the unit frames off", function()
    local DUI, ns = plates()
    T.isnil(DUI:GetModule("UnitFrames") and DUI:GetModule("UnitFrames").enabled or nil)
    cast(COR)
    T.truthy(ns.Manager.byUnit.nameplate1.dotVeil:IsShown())
end)

T.test("plates: a health change keeps the skull fed", function()
    local _, ns = plates()
    cast(COR)
    local p = ns.Manager.byUnit.nameplate1
    stub.units.nameplate1.health = 120
    stub.FireEvent("UNIT_HEALTH", "nameplate1")
    T.eq(stub.Plain(p.dotSkull.bar.__max), 120)
end)

T.test("plates: a friendly plate never shows DoTs", function()
    local _, ns = plates(function()
        stub.units.nameplate1 = { name = "Ally", reaction = 5, guid = "Creature-1", isPlayer = true, health = 100, maxHealth = 100 }
    end)
    cast(COR)
    local p = ns.Manager.byUnit.nameplate1
    T.falsy(p and p.dotVeil and p.dotVeil:IsShown())
end)

T.test("plates: the veil color from Unit Frames > Colors reaches plates already up", function()
    local DUI, ns = plates()
    local mod = DUI:GetModule("UnitFrames")
    if not (mod and mod.enabled) then
        -- Only the nameplates loaded: load both.
        DUI = stub.Load{ module = true, nameplates = true, before = function()
            gamePlates()
            stub.units.player = { name = "Me", isPlayer = true, class = "WARLOCK", guid = "Player-1" }
            stub.units.target = { name = "Kobold", reaction = 2, hostile = true, guid = "Creature-1", health = 30, maxHealth = 300 }
            stub.units.nameplate1 = stub.units.target
            stub.spells = SPELLS
        end }
        stub.RunTimers()
        stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
        stub.RunTimers()
        ns = stub.nameplates
    end
    DUI:Set("UnitFrames", "colors.dotTint", { 0.5, 0.1, 0.1, 0.6 })
    stub.RunTimers()
    local p = ns.Manager.byUnit.nameplate1
    local c = p.dotVeil.bar.__barColor or { p.dotVeil.bar:GetStatusBarColor() }
    T.near(c[1], 0.5, 0.001); T.near(c[4], 0.6, 0.001)
end)
