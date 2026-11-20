local stub = require("stub")

-- Nameplate crests and the plates the game gives to what you face, as players
-- reported them.

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
        player = { name = "Me", class = "WARRIOR", isPlayer = true, faction = "Alliance" },
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

-- The PvP crest says "attacking this flags you", which means nothing on a player
-- of your own faction you can't attack. With "Other faction's crest" off, a
-- flagged guildmate still wore a crest, and the switch looked broken.
T.test("nameplates: the PvP flag crest stays off friendly plates you can't attack", function()
    login()
    local DUI = DaylightUI
    DUI:Set("Nameplates", "factionIcon", false)
    DUI:Set("Nameplates", "pvpIcon", true)
    stub.RunTimers()
    stub.units.nameplate1 = { name = "Oscovo", isPlayer = true, class = "SHAMAN", reaction = 5, faction = "Alliance",
        pvp = true, health = 100, maxHealth = 100 }
    stub.units.nameplate2 = { name = "Grukk", isPlayer = true, class = "WARRIOR", reaction = 2, hostile = true,
        faction = "Horde", pvp = true, health = 100, maxHealth = 100 }
    local friend, foe = added("nameplate1"), added("nameplate2")
    T.truthy(friend.friendly, "a friendly plate")
    T.falsy(friend.factionIcon:IsShown(), "a flagged player of your own faction: no crest")
    T.truthy(foe.factionIcon:IsShown(), "a flagged enemy you could attack keeps it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game hands the object you face (a mailbox, a herb) a plate for its
-- interact icon. With friendly NPC plates switched off, Daylight UI still wrote
-- the object's name over it.
T.test("nameplates: an object you face shows no name while friendly NPC plates are off", function()
    local cvars = { nameplateShowFriendlyPlayers = "0", nameplateShowFriendlyNpcs = "0" }
    login(function()
        _G.SetCVar = function(k, v) cvars[k] = v end
        _G.GetCVar = function(k) return cvars[k] end
    end)
    local mailbox = { name = "Mailbox", guid = "GameObject-0-1-2-3-4-5", reaction = 4, health = 0, maxHealth = 0 }
    stub.units.nameplate3 = mailbox
    stub.units.softinteract = mailbox
    local p = added("nameplate3")
    T.truthy(p == nil or not p:IsShown(), "friendly NPC plates off: nothing of Daylight UI's on the mailbox")
    cvars.nameplateShowFriendlyNpcs = "1"
    stub.FireEvent("CVAR_UPDATE", "nameplateShowFriendlyNpcs", "1")
    stub.RunTimers()
    T.truthy(p and p:IsShown(), "switched on: its name shows")
    stub.units.softinteract = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
