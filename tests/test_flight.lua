local stub = require("stub")

-- The flight timer (QoL/Flight.lua): a bar while on a flight path, with the
-- time left from routes learned on earlier flights.

local onTaxi, taken, mapNodes

-- A flight master in Stormwind (slot 1, node 2) with Ironforge (slot 2, node 6)
-- reachable. ids = false means a client without C_TaxiMap (names only).
local function world(ids)
    onTaxi, taken = false, {}
    mapNodes = {
        { slotIndex = 1, nodeID = 2, name = "Stormwind, Elwynn", state = 0 },
        { slotIndex = 2, nodeID = 6, name = "Ironforge, Dun Morogh", state = 1 },
    }
    _G.UnitOnTaxi = function(unit) return unit == "player" and onTaxi end
    _G.TakeTaxiNode = function(slot) taken[#taken + 1] = slot end
    _G.TaxiRequestEarlyLanding = function() end
    _G.NumTaxiNodes = function() return #mapNodes end
    _G.TaxiNodeName = function(i) return mapNodes[i] and mapNodes[i].name end
    _G.TaxiNodeGetType = function(i) return mapNodes[i] and (mapNodes[i].state == 0 and "CURRENT" or "REACHABLE") end
    _G.GetTaxiMapID = function() return 1415 end
    if ids == false then
        _G.C_TaxiMap = nil
    else
        _G.C_TaxiMap = { GetAllTaxiNodes = function(mapID)
            T.eq(mapID, 1415, "asks for the taxi map's id")
            return mapNodes
        end }
    end
end

local function login(ids, flightTimer)
    stub.Load({ qol = true, before = function() world(ids) end })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    if flightTimer ~= nil then DaylightUI:Set("QoL", "flightTimer", flightTimer) end
    return stub.qol.Flight
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

local function bar() return _G.DaylightUIFlightTimer end
local function shown() local h = bar(); return h ~= nil and h:IsShown() end

-- Opens the map, picks Ironforge and takes off.
local function fly(F)
    stub.FireEvent("TAXIMAP_OPENED", 1)
    TakeTaxiNode(2)
    T.eq(taken[1], 2, "the game's TakeTaxiNode still runs")
    onTaxi = true
    F.Tick()
end

local function land(F)
    onTaxi = false
    F.Tick()
    settle()
end

T.test("flight: on by default, the option is on the QoL page", function()
    login()
    T.eq(DaylightUI:Get("QoL", "flightTimer"), true)
    local page = DaylightUI.Options.GetPage("QoL.qol")
    local found = false
    for _, g in ipairs(page.groups) do
        for _, item in ipairs(g.items) do if item.key == "flightTimer" then found = true end end
    end
    T.truthy(found, "the toggle is on the page")
end)

T.test("flight: an unknown route shows Learning and counts up, then is learned on landing", function()
    local F = login()
    fly(F)
    settle()
    T.truthy(shown(), "the bar is up")
    local box = bar().box
    T.eq(box.name:GetText(), "Ironforge", "destination, short name")
    T.eq(box.time:GetText(), "Learning... 0:00")
    stub.Advance(83)
    F.Tick()
    T.eq(box.time:GetText(), "Learning... 1:23")
    land(F)
    T.falsy(shown(), "glides out on landing")
    T.eq(F.Routes()["2>6"], 83, "the route's time, keyed by the two node ids")
    T.isnil(DaylightUI.DB.Character().flight, "the in-flight note is cleared")
end)

T.test("flight: a learned route shows the time left and fills as you fly", function()
    local F = login()
    F.Routes()["2>6"] = 100
    fly(F)
    local box = bar().box
    T.eq(box.time:GetText(), "1:40")
    stub.Advance(40)
    F.Tick()
    T.eq(box.time:GetText(), "1:00")
    T.near(select(1, box.time:GetTextColor()), DaylightUI.Style.INK.VALUE[1], 0.001, "time warm")
    stub.Advance(55)
    F.Tick()
    T.near(select(1, box.time:GetTextColor()), DaylightUI.Style.INK.WARN[1], 0.001, "under 10 s: amber")
    stub.Advance(-55)
    F.Tick()
    T.near(select(1, box.time:GetTextColor()), DaylightUI.Style.INK.VALUE[1], 0.001, "back to warm")
    local lo, hi = box.bar:GetMinMaxValues()
    T.eq(lo, 0) T.eq(hi, 100)
    T.near(box.bar:GetValue(), 40, 0.01)
    stub.Advance(65)
    F.Tick()
    T.eq(box.time:GetText(), "Almost there", "past the learned time")
    land(F)
    T.eq(F.Routes()["2>6"], 105, "the newest flight's time replaces the old one")
end)

T.test("flight: without the client's flight point list, names are the key", function()
    local F = login(false)
    fly(F)
    stub.Advance(30)
    land(F)
    T.eq(F.Routes()["Stormwind, Elwynn>Ironforge, Dun Morogh"], 30)
end)

T.test("flight: an early landing and a hiccup aren't learned", function()
    local F = login()
    fly(F)
    stub.Advance(30)
    TaxiRequestEarlyLanding()
    land(F)
    T.isnil(F.Routes()["2>6"], "asked to land early")
    fly(F)
    stub.Advance(2)
    land(F)
    T.isnil(F.Routes()["2>6"], "too short to be a route")
end)

T.test("flight: no take-off within the wait drops the pick", function()
    local F = login()
    stub.FireEvent("TAXIMAP_OPENED", 1)
    TakeTaxiNode(2)
    stub.Advance(F.START_WAIT + 1)
    F.Tick()
    onTaxi = true
    F.Tick()
    T.falsy(shown(), "a later taxi ride without a pick shows nothing")
end)

T.test("flight: switched off, nothing shows and nothing is learned", function()
    local F = login(nil, false)
    fly(F)
    T.falsy(shown())
    stub.Advance(30)
    land(F)
    T.isnil(F.Routes()["2>6"])
end)

T.test("flight: switching it off mid-flight glides the bar out", function()
    local F = login()
    fly(F)
    settle()
    T.truthy(shown())
    DaylightUI:Set("QoL", "flightTimer", false)
    settle()
    T.falsy(shown())
end)

T.test("flight: a /reload mid-flight carries on from the take-off", function()
    local F = login()
    F.Routes()["2>6"] = 100
    DaylightUI.DB.Character().flight = { key = "2>6", name = "Ironforge, Dun Morogh", wall = time() - 30 }
    onTaxi = true
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    settle()
    T.truthy(shown())
    T.eq(bar().box.time:GetText(), "1:10")
end)

T.test("flight: a saved flight is dropped when you're no longer on a taxi", function()
    local F = login()
    DaylightUI.DB.Character().flight = { key = "2>6", name = "Ironforge", wall = time() - 30 }
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.falsy(shown())
    T.isnil(DaylightUI.DB.Character().flight)
    T.truthy(F, "loaded")
end)

T.test("flight: test mode shows a sample, and it has a mover", function()
    login()
    T.truthy(DaylightUI.Movers.Get("qol.flight"), "movable")
    DaylightUI.SetTestMode(true)
    settle()
    T.truthy(shown(), "sample in test mode")
    T.eq(bar().box.name:GetText(), "Stormwind")
    DaylightUI.SetTestMode(false)
    settle()
    T.falsy(shown(), "gone with test mode")
end)

T.test("flight: switching the angled end off in play takes every mask off, the bar hidden or shown", function()
    login()
    local function masked(f, out)
        out = out or {}
        for _, r in ipairs({ f:GetRegions() }) do
            if r.__masks and #r.__masks > 0 then out[#out + 1] = r end
        end
        for _, c in ipairs({ f:GetChildren() }) do masked(c, out) end
        return out
    end
    local h = bar()
    T.truthy(#masked(h) > 0, "angled: the pieces are masked")
    DaylightUI:Set("QoL", "flightTimerSlant", false)
    T.eq(#masked(h), 0, "off while hidden: nothing masked")
    DaylightUI:Set("QoL", "flightTimerSlant", true)
    DaylightUI.SetTestMode(true)
    settle()
    T.truthy(#masked(h) > 0, "angled again")
    -- In game the client kept the cut after RemoveMaskTexture, so what was a mask
    -- now holds nothing that could cut.
    local function cutters(f, out)
        out = out or {}
        for _, r in ipairs({ f:GetRegions() }) do
            if r.cutting then out[#out + 1] = r end
        end
        for _, c in ipairs({ f:GetChildren() }) do cutters(c, out) end
        return out
    end
    T.truthy(#cutters(h) > 0, "angled: the masks hold the cut")
    DaylightUI:Set("QoL", "flightTimerSlant", false)
    T.eq(#masked(h), 0, "off while shown: nothing masked")
    T.eq(#cutters(h), 0, "every mask blanked")
    DaylightUI.SetTestMode(false)
end)

T.test("flight: the angled end has its own switch; off, the end and the fill are straight", function()
    login()
    local Style = DaylightUI.Style
    DaylightUI.SetTestMode(true)
    settle()
    local box = bar().box
    T.truthy(Style.GetSlant(box).cut > 0, "angled by default")
    local room = select(4, box.time:GetPoint(1))
    DaylightUI:Set("QoL", "flightTimerSlant", false)
    T.eq(Style.GetSlant(box).cut, 0, "straight end")
    local mask = Style.GetFillMask(box.bar)
    T.truthy(not mask or not mask.added, "the fill straight too")
    T.truthy(select(4, box.time:GetPoint(1)) > room, "the time moves into the room the cut kept")
    DaylightUI:Set("QoL", "flightTimerSlant", true)
    T.truthy(Style.GetSlant(box).cut > 0, "angled again")
    DaylightUI.SetTestMode(false)
end)
