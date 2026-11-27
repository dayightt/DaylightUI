-- A hunter pet's experience bar: a strip in the pet frame, or a bar of its own.
local stub = require("stub")

local function login(spec)
    spec = spec or {}
    return stub.Load({ module = true, before = function()
        stub.units.player = { name = "Hunts", isPlayer = true, class = spec.class or "HUNTER" }
        stub.units.pet = { name = "Rex", class = "HUNTER", reaction = 5, health = 50, maxHealth = 100 }
        stub.xp = spec.xp or { 1200, 5000 }
        _G.HasPetUI = function() return spec.pet ~= false, spec.hunter ~= false end
        _G.GetPetExperience = function() return stub.xp[1], stub.xp[2] end
    end })
end

local function turnOn(DUI, key, value)
    DUI:Set("UnitFrames", key, value)
    stub.RunTimers()
end

T.test("pet xp bar: off by default, no strip and no bar", function()
    local _, ns = login()
    T.falsy(ns.frames.pet.xp:IsShown())
    T.eq(ns.frames.pet.xpH, 0)
    T.falsy(ns.petXp:IsShown())
end)

T.test("pet xp bar: in the frame it is a strip under the power bar, which the frame makes room for", function()
    local DUI, ns = login()
    local f = ns.frames.pet
    turnOn(DUI, "pet.xpBar", true)
    T.truthy(f.xp:IsShown()); T.truthy(f.xpSep:IsShown())
    T.truthy(f.xpH > 0)
    local _, rel, _, _, xpY = f.xp:GetPoint(1)
    T.eq(rel, f); T.eq(f.xp:GetHeight(), f.xpH)
    local _, _, _, _, powerY = f.power:GetPoint(1)
    T.truthy(powerY > xpY, "the power bar stands over it")
    T.eq(select(2, f.xp:GetMinMaxValues()), 5000)
    T.eq(f.xp:GetValue(), 1200)
    T.falsy(ns.petXp:IsShown(), "no bar of its own")
end)

T.test("pet xp bar: the strip's height is its own setting", function()
    local DUI, ns = login()
    turnOn(DUI, "pet.xpBar", true)
    turnOn(DUI, "pet.xpBarHeight", 2)
    local thin = ns.frames.pet.xpH
    turnOn(DUI, "pet.xpBarHeight", 6)
    T.truthy(ns.frames.pet.xpH > thin)
end)

T.test("pet xp bar: in the frame, the numbers are on the frame's tooltip", function()
    local DUI, ns = login()
    turnOn(DUI, "pet.xpBar", true)
    local lines = {}
    _G.GameTooltip = { SetOwner = function() end, AddLine = function(_, t) lines[#lines + 1] = t end,
                       AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. "|" .. b end,
                       SetUnit = function() end, Show = function() end, Hide = function() end }
    _G.GameTooltip_SetDefaultAnchor = function() end
    ns.UF.OnEnter(ns.frames.pet)
    local seen = false
    for _, l in ipairs(lines) do if l:find("1,200", 1, true) then seen = true end end
    T.truthy(seen, table.concat(lines, " / "))
end)

T.test("pet xp bar: on its own, the strip is gone and the bar takes its size, with the numbers on it", function()
    local DUI, ns = login()
    turnOn(DUI, "pet.xpBar", true)
    turnOn(DUI, "pet.xpBarMode", "free")
    turnOn(DUI, "pet.xpBarWidth", 200)
    turnOn(DUI, "pet.xpBarFreeHeight", 14)
    local f, bar = ns.frames.pet, ns.petXp
    T.falsy(f.xp:IsShown(), "no strip in the frame")
    T.eq(f.xpH, 0)
    T.truthy(bar:IsShown())
    T.eq(bar:GetWidth(), 200); T.eq(bar:GetHeight(), 14)
    T.truthy(bar.text:IsShown())
    T.truthy(bar.text:GetText():find("1,200", 1, true), bar.text:GetText())
    turnOn(DUI, "pet.xpBarOrientation", "vertical")
    T.eq(bar:GetWidth(), 14); T.eq(bar:GetHeight(), 200, "upright: the length turns")
    T.eq(bar.bar:GetOrientation(), "VERTICAL")
end)

T.test("pet xp bar: a demon, no pet, or a pet at the top level shows no fill", function()
    for _, spec in ipairs({ { hunter = false }, { pet = false }, { xp = { 0, 0 } } }) do
        local DUI, ns = login(spec)
        turnOn(DUI, "pet.xpBar", true)
        turnOn(DUI, "pet.xpBarMode", "free")
        T.falsy(ns.petXp:IsShown())
    end
    -- The strip of a demon's frame isn't made at all: no room taken for a bar that can't fill.
    local DUI, ns = login({ class = "WARLOCK", hunter = false })
    turnOn(DUI, "pet.xpBar", true)
    T.eq(ns.frames.pet.xpH, 0)
end)

T.test("pet xp bar: it follows the pet's XP as it comes in", function()
    local DUI, ns = login()
    turnOn(DUI, "pet.xpBar", true)
    stub.xp = { 2500, 5000 }
    stub.FireEvent("UNIT_PET_EXPERIENCE", "pet")
    T.eq(ns.frames.pet.xp:GetValue(), 2500)
end)

T.test("pet xp bar: the independent bar can show the percent, and its text size is a setting", function()
    local DUI, ns = login()
    turnOn(DUI, "pet.xpBar", true)
    turnOn(DUI, "pet.xpBarMode", "free")
    T.falsy(ns.petXp.text:GetText():find("%%"), "no percent by default")
    turnOn(DUI, "pet.xp.showPercent", true)
    T.truthy(ns.petXp.text:GetText():find("24%%"), ns.petXp.text:GetText())
end)

T.test("pet xp bar: its colors follow its own color setting", function()
    local DUI, ns = login()
    turnOn(DUI, "pet.xp.color", "custom")
    local stops = ns.PetXP.Stops(DUI:Get("UnitFrames", "pet.xp"))
    T.truthy(#stops >= 2, "the custom gradient's own colors")
    turnOn(DUI, "pet.xp.color", "blue")
    stops = ns.PetXP.Stops(DUI:Get("UnitFrames", "pet.xp"))
    T.truthy(stops[#stops][3] > stops[#stops][1], "blue")
end)

T.test("pet xp bar: the independent bar fades on its own", function()
    local DUI, ns = login()
    turnOn(DUI, "pet.xpBar", true)
    turnOn(DUI, "pet.xpBarMode", "free")
    T.truthy(DUI:Get("UnitFrames", "pet.xp.fade") ~= nil)
end)
