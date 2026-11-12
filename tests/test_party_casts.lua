local stub = require("stub")

local function login(before) return stub.Load({ module = true, before = before }) end

-- A party button as the header would make it, on unit.
local function button(ns, i, unit, data)
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton" .. i, h)
    b:SetAttribute("unit", unit)
    if data then stub.units[unit] = data end
    h.initialConfigFunction(h, b:GetName())
    stub.RunTimers()
    return b
end

local function priest(spell)
    local u = { name = "Lift", isPlayer = true, class = "PRIEST", health = 8, maxHealth = 10 }
    if spell then u.cast = { name = spell, notInterruptible = false, duration = stub.Duration(2) } end
    return u
end

T.test("each party member gets a cast bar inside the power bar by default", function()
    local _, ns = login()
    local b = button(ns, 1, "party1", priest())
    local c = b.casts
    T.truthy(c, "made with the button's layout")
    T.eq(c.inside.into, b.power, "covers the power bar")
    T.eq(c.inside.unit, "party1")
    stub.units.party1.cast = { name = "Flash Heal", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "party1")
    T.truthy(c.inside:IsShown())
    T.eq(c.inside.text.__text, "Flash Heal")
    T.falsy(c.own:IsShown(), "the bar of its own stays down")
end)

T.test("the bars follow the member when the header re-sorts", function()
    local _, ns = login()
    local b = button(ns, 1, "party1", priest())
    stub.units.party3 = priest("Renew")
    b:SetAttribute("unit", "party3")
    T.eq(b.casts.inside.unit, "party3")
    T.eq(b.casts.own.unit, "party3")
    T.truthy(b.casts.inside:IsShown(), "a cast under way shows at once")
    T.eq(b.casts.inside.text.__text, "Renew")
end)

T.test("slide: the bar hangs under its frame, in a clip inside the frame", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", priest())
    DUI:Set("UnitFrames", "partyCastbar.at", "slide")
    stub.RunTimers()
    local own = b.casts.own
    T.truthy(own.column, "hung")
    T.eq(own.column.f, b)
    T.eq(own.clip:GetParent(), b, "fades with its frame")
    stub.units.party1.cast = { name = "Smite", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "party1")
    T.truthy(own:IsShown())
    T.falsy(b.casts.inside:IsShown())
end)

T.test("detached: its own size, beside the frame on the picked side", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", priest())
    DUI:Set("UnitFrames", "partyCastbar.at", "free")
    DUI:Set("UnitFrames", "partyCastbar.spot", "left")
    DUI:Set("UnitFrames", "partyCastbar.width", 150)
    stub.RunTimers()
    local own = b.casts.own
    T.isnil(own.column)
    T.eq(own:GetParent(), b)
    T.near(own:GetWidth(), 150, 1)
    local p, rel, rp = own:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, b); T.eq(rp, "LEFT")
end)

T.test("switched off, no party cast shows", function()
    local DUI, ns = login()
    local b = button(ns, 1, "party1", priest())
    DUI:Set("UnitFrames", "partyCastbar.enabled", false)
    stub.RunTimers()
    stub.units.party1.cast = { name = "Smite", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "party1")
    T.falsy(b.casts.inside:IsShown())
    T.falsy(b.casts.own:IsShown())
end)
