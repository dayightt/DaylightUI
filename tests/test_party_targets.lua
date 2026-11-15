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

local PRIEST = { name = "Rell", isPlayer = true, class = "PRIEST", health = 8, maxHealth = 10 }
local MOB = { name = "Kobold Miner", reaction = 2, health = 30, maxHealth = 60, power = 10, maxPower = 20 }

local function on(DUI)
    DUI:Set("UnitFrames", "partyTarget.enabled", true)
    stub.RunTimers()
end

T.test("party targets are off by default: no button is made", function()
    local DUI, ns = login()
    T.eq(DUI:Get("UnitFrames", "partyTarget.enabled"), false)
    local b = button(ns, 1, "party1", PRIEST)
    stub.RunTimers()
    T.isnil(b.ptarget)
end)

T.test("switched on, each member gets a secure button on their target that follows them", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", PRIEST)
    stub.units.party1target = MOB
    on(DUI)
    local p = b.ptarget
    T.truthy(p, "made once they're on")
    T.eq(p:GetParent(), b, "hung on its member: the header's sorting carries it")
    T.eq(p:GetAttribute("useparent-unit"), true)
    T.eq(p:GetAttribute("unitsuffix"), "target", "a click reads the member's unit + target, in combat too")
    T.truthy(p.__unitWatch, "the game's unit watch shows it while they have a target")
    T.eq(p.unitToken, "party1target")
    T.eq(p.nameText.__text, "Kobold Miner")
    T.near(p:GetWidth(), DUI:Get("UnitFrames", "partyTarget.width"), 1)
    T.eq(ns.UF.FrameKey(p.spec), "partyTarget", "reads its own page's settings")
    -- The header re-sorts: the member is now party3, so is the target.
    stub.units.party3, stub.units.party3target = PRIEST, { name = "Gnoll", reaction = 2, health = 5, maxHealth = 5 }
    b:SetAttribute("unit", "party3")
    T.eq(p.unitToken, "party3target")
    T.eq(p.nameText.__text, "Gnoll")
end)

T.test("a member's new target (UNIT_TARGET) is redrawn at once", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", PRIEST)
    stub.units.party1target = MOB
    on(DUI)
    stub.units.party1target = { name = "Murloc", reaction = 2, health = 4, maxHealth = 4 }
    stub.FireEvent("UNIT_TARGET", "party1")
    T.eq(b.ptarget.nameText.__text, "Murloc")
end)

T.test("a setting on its page reaches the frames", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", PRIEST)
    stub.units.party1target = MOB
    on(DUI)
    DUI:Set("UnitFrames", "partyTarget.width", 120)
    stub.RunTimers()
    T.near(b.ptarget:GetWidth(), 120, 1)
    DUI:Set("UnitFrames", "partyTarget.enabled", false)
    stub.RunTimers()
    T.falsy(b.ptarget.__unitWatch)
    T.falsy(b.ptarget:IsShown())
end)

T.test("a member who joins mid-fight gets one once the fight ends", function()
    local DUI, ns = login()
    on(DUI)
    stub.secure = true
    stub.EnterCombat()
    local b = button(ns, 2, "party2", PRIEST)
    T.isnil(b.ptarget, "secure attributes and the unit watch wait for the fight to end")
    stub.LeaveCombat()
    stub.RunTimers()
    stub.secure = false
    T.truthy(b.ptarget)
    T.eq(b.ptarget.unitToken, "party2target")
end)

T.test("on the pet's side it sits past the pet, and aura rows past both", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", PRIEST)
    stub.units.party1target = MOB
    on(DUI)
    local _, _, _, x1 = b.ptarget:GetPoint(1)
    local before = ns.AuraGroups.Box(b, DUI:Get("UnitFrames", "party")).outR
    DUI:Set("UnitFrames", "partyPet.enabled", true)
    stub.RunTimers()
    local _, _, _, x2 = b.ptarget:GetPoint(1)
    T.eq(x2, x1 + DUI:Get("UnitFrames", "partyPet.width") + ns.PartyPets.GAP, "past the pet")
    local box = ns.AuraGroups.Box(b, DUI:Get("UnitFrames", "party"))
    T.eq(box.outR, before + DUI:Get("UnitFrames", "partyPet.width") + ns.PartyPets.GAP)
    DUI:Set("UnitFrames", "partyTarget.spot", "left")
    stub.RunTimers()
    T.eq(select(1, b.ptarget:GetPoint(1)), "RIGHT", "on the other side, no pet in the way")
end)

T.test("test mode and the Party page's preview show sample targets", function()
    local DUI, ns = login()
    on(DUI)
    DUI.SetTestMode(true)
    stub.RunTimers()
    T.truthy(ns.Party.preview[1].ptarget:IsShown())
    T.eq(ns.Party.preview[1].ptarget.nameText.__text, ns.PartyTargets.SAMPLES[1].name)
    DUI.SetTestMode(false)
    stub.RunTimers()
    T.falsy(ns.Party.preview[1].ptarget:IsShown())
    local s = ns.PageSample.New("party", UIParent)
    s.Refresh(600, 400)
    T.truthy(s.members[1].ptarget:IsShown())
end)

T.test("its own options page, with a preview", function()
    local DUI, ns = login()
    local found
    for _, page in ipairs(ns.OPTIONS.pages) do if page.id == "partyTarget" then found = page end end
    T.truthy(found, "a Party Targets page")
    local s = ns.PageSample.New("partyTarget", UIParent)
    s.Refresh(600, 400)
    T.eq(s.f.nameText.__text, ns.PartyTargets.SAMPLES[1].name)
end)
