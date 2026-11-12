local stub = require("stub")

local function login(before) return stub.Load({ module = true, before = before }) end

-- A party button as the header would make it, on unit.
local function button(ns, i, unit, data)
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton" .. i, h)
    b:SetAttribute("unit", unit)
    if data then stub.units[unit] = data end
    h.initialConfigFunction(h, b:GetName())
    return b
end

local HUNTER = { name = "Rell", isPlayer = true, class = "HUNTER", health = 8, maxHealth = 10 }
local WOLF = { name = "Ash", reaction = 5, health = 3, maxHealth = 6, power = 50, maxPower = 100 }

local function petsOn(DUI)
    DUI:Set("UnitFrames", "partyPet.enabled", true)
    stub.RunTimers()
end

T.test("party pets are off by default: no pet button is made", function()
    local DUI, ns = login()
    T.eq(DUI:Get("UnitFrames", "partyPet.enabled"), false)
    local b = button(ns, 1, "party1", HUNTER)
    stub.RunTimers()
    T.isnil(b.pet)
end)

T.test("switched on, each member gets a secure pet button that follows them", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", HUNTER)
    stub.units.partypet1 = WOLF
    petsOn(DUI)
    local p = b.pet
    T.truthy(p, "made once pets are on")
    T.eq(p:GetParent(), b, "hung on its owner: the header's sorting carries it")
    T.eq(p:GetAttribute("useparent-unit"), true)
    T.eq(p:GetAttribute("unitsuffix"), "pet", "a click reads the owner's unit + pet, in combat too")
    T.eq(p:GetAttribute("*type1"), "target")
    T.truthy(p.__unitWatch, "the game's unit watch shows it while the pet is out")
    T.eq(p.unitToken, "partypet1")
    T.eq(p.nameText.__text, "Ash")
    T.near(p:GetWidth(), DUI:Get("UnitFrames", "partyPet.width"), 1)
    -- The header re-sorts: the owner is now party3, so is its pet.
    stub.units.party3, stub.units.partypet3 = HUNTER, { name = "Cinder", reaction = 5, health = 5, maxHealth = 5 }
    b:SetAttribute("unit", "party3")
    T.eq(p.unitToken, "partypet3")
    T.eq(p.nameText.__text, "Cinder")
end)

T.test("a pet wears its owner's class colors, or the usual ones", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", HUNTER)
    stub.units.partypet1 = WOLF
    petsOn(DUI)
    T.eq(b.pet.ownerClass, "HUNTER")
    DUI:Set("UnitFrames", "partyPet.color", "own")
    stub.RunTimers()
    T.isnil(b.pet.ownerClass)
end)

T.test("a new pet (UNIT_PET) is redrawn", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", HUNTER)
    stub.units.partypet1 = WOLF
    petsOn(DUI)
    stub.units.partypet1 = { name = "Boar", reaction = 5, health = 4, maxHealth = 4 }
    stub.FireEvent("UNIT_PET", "party1")
    T.eq(b.pet.nameText.__text, "Boar")
end)

T.test("switched off again, the watch goes and the pet hides", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", HUNTER)
    stub.units.partypet1 = WOLF
    petsOn(DUI)
    DUI:Set("UnitFrames", "partyPet.enabled", false)
    stub.RunTimers()
    T.falsy(b.pet.__unitWatch)
    T.falsy(b.pet:IsShown())
end)

T.test("a member who joins mid-fight gets a pet once the fight ends, nothing blocked", function()
    local DUI, ns = login()
    petsOn(DUI)
    stub.secure = true
    stub.EnterCombat()
    stub.units.partypet2 = WOLF
    local b = button(ns, 2, "party2", HUNTER)
    T.isnil(b.pet, "secure attributes and the unit watch wait for the fight to end")
    stub.LeaveCombat()
    stub.RunTimers()
    stub.secure = false
    T.truthy(b.pet)
    T.truthy(b.pet.__unitWatch)
    T.eq(b.pet.unitToken, "partypet2")
end)

T.test("pets beside the frames: aura rows on that side start past them", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", HUNTER)
    local before = ns.AuraGroups.Box(b, DUI:Get("UnitFrames", "party")).outR
    petsOn(DUI)
    local box = ns.AuraGroups.Box(b, DUI:Get("UnitFrames", "party"))
    T.eq(box.outR, before + DUI:Get("UnitFrames", "partyPet.width") + ns.PartyPets.GAP)
    DUI:Set("UnitFrames", "partyPet.spot", "below")
    stub.RunTimers()
    box = ns.AuraGroups.Box(b, DUI:Get("UnitFrames", "party"))
    T.eq(box.below, DUI:Get("UnitFrames", "partyPet.height") + ns.PartyPets.GAP, "the rows under the frame drop past it")
end)

T.test("test mode: the warlock's sample has its imp, in her class colors; you never get one", function()
    local DUI, ns = login()
    petsOn(DUI)
    DUI.SetTestMode(true)
    stub.RunTimers()
    local shallan = ns.Party.preview[3]
    T.eq(shallan.test.name, "Shallan")
    T.truthy(shallan.pet:IsShown())
    T.eq(shallan.pet.nameText.__text, "Grimlix")
    T.eq(shallan.pet.test.class, "WARLOCK")
    T.falsy(ns.Party.preview[1].pet:IsShown(), "the warrior has none")
    DUI.SetTestMode(false)
    stub.RunTimers()
    T.falsy(shallan.pet:IsShown())
end)

T.test("the Party page's preview shows a pet once they're on, and makes room for it", function()
    local DUI, ns = login()
    local s = ns.PageSample.New("party", UIParent)
    s.Refresh(600, 400)
    local b = s.members[1]
    T.falsy(b.pet:IsShown(), "off by default")
    petsOn(DUI)
    s.Refresh(600, 400)
    T.truthy(b.pet:IsShown())
    local _, _, _, right = ns.PageSample.GroupReach(DUI:Get("UnitFrames", "party"), b)
    T.truthy(right >= DUI:Get("UnitFrames", "partyPet.width"), "the preview reaches past the pet")
end)

T.test("a new member on the owner's same unit word: the pet redraws with the new owner", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", HUNTER)
    stub.units.partypet1 = WOLF
    petsOn(DUI)
    local p = b.pet
    T.eq(p.ownerClass, "HUNTER")
    -- Someone else is party1 now (the header keeps the word, sends nothing).
    stub.units.party1 = { name = "Vex", isPlayer = true, class = "WARLOCK", health = 8, maxHealth = 10 }
    stub.units.partypet1 = { name = "Grik", reaction = 5, health = 3, maxHealth = 6 }
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(p.ownerClass, "WARLOCK", "the new owner's class")
    T.eq(p.nameText.__text, "Grik", "the new owner's pet")
end)
