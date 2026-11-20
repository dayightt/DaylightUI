local stub = require("stub")

local function login() return stub.Load({ module = true }) end

local function petTile(ns, unit)
    local h = ns.RaidPets.header
    local b = CreateFrame("Button", "DaylightUIRaidPetHeaderUnitButton1", h)
    b:SetAttribute("unit", unit)
    h.initialConfigFunction(h, b:GetName())
    return b
end

T.test("raid pets: the game's pet header, off until switched on", function()
    local DUI, ns = login()
    local h = ns.RaidPets.header
    T.eq(h.__template, "SecureGroupPetHeaderTemplate")
    T.eq(h:GetAttribute("useOwnerUnit"), false)
    T.eq(h:GetAttribute("filterOnPet"), false, "groups shown filter by the owner's group")
    T.isnil(h.__stateDriver and h.__stateDriver.visibility, "off by default")
    DUI:Set("UnitFrames", "raid.showPets", true)
    stub.RunTimers()
    T.eq(h.__stateDriver.visibility, "[@raid1,exists] show; hide")
    T.eq(h:GetAttribute("groupBy"), "GROUP", "by the owner's group")
    T.eq(h:GetAttribute("sortMethod"), "INDEX")
    T.eq(h:GetAttribute("unitWidth"), ns.Raid.header:GetAttribute("unitWidth"), "raid tile size")
    DUI:Set("UnitFrames", "raid.enabled", false)
    stub.RunTimers()
    T.isnil(h.__stateDriver.visibility, "raid frames off: no pets either")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("raid pets: one switch for every raid size", function()
    local _, ns = login()
    T.truthy(ns.RAID_SHARED.showPets)
    T.eq(ns.DEFAULTS.raid.showPets, false)
end)

T.test("raid pets: the block hangs off the raid header's far edge", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.showPets", true)
    stub.RunTimers()
    local holder = ns.RaidPets.holder
    local p, to, rel, x = holder:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(to, ns.Raid.header); T.eq(rel, "TOPRIGHT")
    T.eq(x, DUI:Get("UnitFrames", "raid.groupSpacing"))
    DUI:Set("UnitFrames", "raid.direction", "rows")
    stub.RunTimers()
    p, to, rel = holder:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(to, ns.Raid.header); T.eq(rel, "BOTTOMLEFT", "rows: under the last row")
    DUI:Set("UnitFrames", "raid.sortBy", "grouprole")
    DUI:Set("UnitFrames", "raid.groups", 4)
    stub.RunTimers()
    _, to = holder:GetPoint(1)
    T.eq(to, ns.Raid.group.headers[4], "group, then role: after the last shown group")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("raid pets: a pet tile is a raid tile that reports as a party pet", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.showPets", true)
    stub.RunTimers()
    stub.units.raidpet2 = { name = "Wolf", friend = true, health = 30, maxHealth = 60, inRange = false }
    local made
    DUI.API.On("FrameMade", function(kind, _, unit) if unit == "raidpet2" then made = kind end end)
    local b = petTile(ns, "raidpet2")
    T.eq(b.nameText.__text, "Wolf")
    T.eq(made, "partypet")
    T.isnil(b.roleIcon); T.isnil(b.leaderIcon)
    -- A pet is in your group, so the game's range check fades it.
    ns.UF.UpdateRange(b)
    T.eq(stub.Plain(b:GetAlpha()), b.rangeAlpha, "out of range fades")
    stub.units.raidpet2.inRange = true
    ns.UF.UpdateRange(b)
    T.eq(stub.Plain(b:GetAlpha()), 1)
    stub.units.raidpet2 = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("raid pets: test mode shows sample pets beside the sample raid", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    T.isnil(ns.RaidPets.group.preview, "switch off: no samples built")
    DUI:Set("UnitFrames", "raid.showPets", true)
    stub.RunTimers()
    local shown = 0
    for _, b in ipairs(ns.RaidPets.group.preview) do if b:IsShown() then shown = shown + 1 end end
    T.eq(shown, #ns.RaidPets.SAMPLES)
    T.eq(ns.RaidPets.group.preview[1].nameText.__text, "Wolf")
    local _, to = ns.RaidPets.holder:GetPoint(1)
    T.eq(to, ns.Raid.holder, "beside the sample raid")
    DUI.SetTestMode(false)
    T.falsy(ns.RaidPets.group.preview[1]:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The pet header sorts by the owner's group, class or name (its ROLE is the raid's
-- main tank or assist, and it has no ASSIGNEDROLE), so the pets follow "Sort frames
-- by" where they can and keep the owner's group otherwise.
T.test("raid pets: they follow Sort frames by where the pet header can", function()
    local DUI, ns = login()
    local h = ns.RaidPets.header
    DUI:Set("UnitFrames", "raid.showPets", true)
    for sortBy, want in pairs({ class = "CLASS", name = false, role = "GROUP", grouprole = "GROUP", group = "GROUP" }) do
        DUI:Set("UnitFrames", "raid.sortBy", sortBy)
        stub.RunTimers()
        if want then
            T.eq(h:GetAttribute("groupBy"), want, sortBy)
        else
            T.isnil(h:GetAttribute("groupBy"), sortBy)
            T.eq(h:GetAttribute("sortMethod"), "NAME", sortBy .. ": by the owner's name")
        end
        T.truthy(h:GetAttribute("groupBy") ~= "ASSIGNEDROLE", sortBy .. ": never a grouping the pet header lacks")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Pet tiles stay the friendly green, not their owner's class color, so a pet
-- reads apart from a player.
T.test("raid pets: tiles stay the friendly green", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.showPets", true)
    stub.RunTimers()
    stub.units.raid3 = { name = "Rexx", isPlayer = true, class = "HUNTER", raid = true }
    stub.units.raidpet3 = { name = "Wolf", friend = true, health = 30, maxHealth = 60 }
    local b = petTile(ns, "raidpet3")
    T.isnil(b.ownerClass, "no owner class")
    T.isnil(ns.RaidPets.SampleFor(1).class, "samples friendly too")
    T.eq(ns.RaidPets.SampleFor(1).reaction, 5)
    stub.units.raid3, stub.units.raidpet3 = nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("raid pets: a pet tile is a raid tile without role, leader or group threat", function()
    local _, ns = login()
    local R, P = ns.Raid.SPEC, ns.RaidPets.SPEC
    for k, v in pairs(R) do
        if k ~= "role" and k ~= "leaderIcon" and k ~= "groupThreat" then T.eq(P[k], v, k) end
    end
    T.isnil(P.role); T.isnil(P.leaderIcon); T.isnil(P.groupThreat)
end)

-- The owner's name in a small line under the pet's: <Owner>.
T.test("raid pets: the owner's name under the pet's, kept current", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.showPets", true)
    stub.RunTimers()
    stub.units.raid3 = { name = "Rexx", isPlayer = true, class = "HUNTER", raid = true }
    stub.units.raidpet3 = { name = "Wolf", friend = true, health = 30, maxHealth = 60 }
    local b = petTile(ns, "raidpet3")
    stub.RunTimers()
    T.truthy(b.ownerText and b.ownerText:IsShown(), "shown")
    T.eq(b.ownerText.__text, "<Rexx>")
    T.eq(select(2, b.ownerText:GetPoint(1)), b.nameText, "under the pet's name")
    -- The name rises half a line, so the pair sits inside the tile.
    local y = select(5, b.nameText:GetPoint(1))
    T.eq(y, b.tileName.y + (ns.RaidPets.OWNER_SIZE + 1) / 2, "name lifted")
    -- A name change re-places the name and keeps the lift.
    stub.units.raidpet3.name = "Wolfie"; stub.FireEvent("UNIT_NAME_UPDATE", "raidpet3"); stub.RunTimers()
    T.eq(select(5, b.nameText:GetPoint(1)), y, "kept after a name change")
    ns.RaidPets.PaintOwner(b)
    T.eq(select(5, b.nameText:GetPoint(1)), y, "lift applied once")
    -- Names off: no owner line, and the name's spot is left as laid out.
    DUI:Set("UnitFrames", "raid.showName", false); stub.RunTimers()
    T.falsy(b.ownerText:IsShown(), "hidden with the name")
    T.eq(b.nameLift, 0)
    DUI:Set("UnitFrames", "raid.showName", true); stub.RunTimers()
    T.truthy(b.ownerText:IsShown(), "back with the name")
    -- The roster moves someone else onto raid3.
    stub.units.raid3 = { name = "Mio", isPlayer = true, class = "WARLOCK", raid = true }
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.eq(b.ownerText.__text, "<Mio>", "follows the roster")
    -- No owner to be found: <Unknown>.
    stub.units.raid3 = nil
    stub.FireEvent("UNIT_PET", "raid3"); stub.RunTimers()
    T.truthy(b.ownerText:IsShown())
    T.eq(b.ownerText.__text, "<" .. DUI.L["Unknown"] .. ">")
    stub.units.raidpet3 = nil
    -- Samples carry an owner too.
    DUI.SetTestMode(true)
    local s = ns.RaidPets.group.preview[1]
    T.eq(s.ownerText.__text, "<Rock>")
    DUI.SetTestMode(false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
