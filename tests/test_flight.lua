local stub = require("stub")

-- The flight timer (QoL/Flight.lua): a banner while on a flight path, with the
-- time left from your own earlier flights or the game's path lengths.

local onTaxi, taken, mapNodes, hops, earlyAsked, mapHere

-- A flight master in Stormwind (slot 1, node 2) with Ironforge (slot 2, node 6)
-- and Menethil Harbor (slot 3, node 7, by way of Ironforge) reachable.
-- ids = false means a client without C_TaxiMap (names only).
local function world(ids)
    onTaxi, taken, earlyAsked, mapHere = false, {}, 0, 1453
    _G.C_Map = _G.C_Map or {}
    _G.C_Map.GetBestMapForUnit = function(unit) if unit == "player" then return mapHere end end
    mapNodes = {
        { slotIndex = 1, nodeID = 2, name = "Stormwind, Elwynn", state = 0 },
        { slotIndex = 2, nodeID = 6, name = "Ironforge, Dun Morogh", state = 1 },
        { slotIndex = 3, nodeID = 7, name = "Menethil Harbor, Wetlands", state = 1 },
    }
    -- Each slot's hops as { from slot, to slot }, like the flight master's map.
    hops = { [2] = { { 1, 2 } }, [3] = { { 1, 2 }, { 2, 3 } } }
    _G.GetNumRoutes = function(slot) return hops[slot] and #hops[slot] or 0 end
    _G.TaxiGetNodeSlot = function(slot, i, source)
        local h = hops[slot] and hops[slot][i]
        return h and (source and h[1] or h[2])
    end
    _G.UnitOnTaxi = function(unit) return unit == "player" and onTaxi end
    _G.TakeTaxiNode = function(slot) taken[#taken + 1] = slot end
    _G.TaxiRequestEarlyLanding = function() earlyAsked = earlyAsked + 1 end
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

-- No path times from the game's table: every route is one you have to fly first.
local function noPaths() stub.qol.FlightPaths = {} end

-- Opens the map, picks Ironforge (or another slot) and takes off.
local function fly(F, slot)
    slot = slot or 2
    stub.FireEvent("TAXIMAP_OPENED", 1)
    TakeTaxiNode(slot)
    T.eq(taken[#taken], slot, "the game's TakeTaxiNode still runs")
    onTaxi = true
    F.Tick()
end

local function land(F)
    onTaxi = false
    F.Tick()
    settle()
end

local function welcome() return _G.DaylightUIFlightWelcome end
local function welcomed() local w = welcome(); return w ~= nil and w:IsShown() end

-- After the welcome has held, it fades away.
local function leave()
    stub.RunTimers()
    settle()
end

T.test("flight: on by default, the option is on its own page", function()
    login()
    T.eq(DaylightUI:Get("QoL", "flightTimer"), true)
    local page = DaylightUI.Options.GetPage("QoL.flight")
    local found = false
    for _, g in ipairs(page.groups) do
        for _, item in ipairs(g.items) do if item.key == "flightTimer" then found = true end end
    end
    T.truthy(found, "the toggle is on the page")
end)

T.test("flight: a route with no time anywhere counts up, then is learned on landing", function()
    local F = login()
    noPaths()
    fly(F)
    settle()
    T.truthy(shown(), "the banner is up")
    local box = bar().f
    T.eq(box.name:GetText(), "Ironforge", "destination, short name")
    T.eq(box.from:GetText(), "Stormwind", "where from, short name")
    T.eq(box.time:GetText(), "0:00", "no Learning word, just the clock")
    stub.Advance(83)
    F.Tick()
    T.eq(box.time:GetText(), "1:23")
    land(F)
    T.falsy(shown(), "the banner glides out on landing")
    T.truthy(welcomed(), "the welcome comes in")
    T.eq(welcome().name:GetText(), "Ironforge", "with the destination")
    leave()
    T.falsy(welcomed(), "then fades away")
    T.eq(F.Routes()["2>6"], 83, "the route's time, keyed by the two node ids")
    T.isnil(DaylightUI.DB.Character().flight, "the in-flight note is cleared")
end)

T.test("flight: a first flight counts down from the game's path length", function()
    local F = login()
    stub.qol.FlightPaths = { ["2>6"] = 60, ["7>6"] = 40 }
    fly(F, 3)
    local box = bar().f
    T.eq(box.name:GetText(), "Menethil Harbor")
    T.eq(box.time:GetText(), "1:40", "both legs added up, the second known only the other way")
    T.truthy(box.stops[1] and box.stops[1]:IsShown(), "a dot for the stop at Ironforge")
    T.near(select(4, box.stops[1]:GetPoint(1)), 0.6 * F.WIDTH, 0.01, "at its share of the way")
    stub.Advance(70)
    F.Tick()
    T.eq(box.time:GetText(), "0:30")
    land(F)
    T.eq(F.Routes()["2>7"], 70, "your own time is learned all the same")
    leave()
    fly(F, 3)
    T.eq(box.time:GetText(), "1:10", "and beats the path's guess next time")
end)

T.test("flight: pointing at a stop's dot names it", function()
    local F = login()
    stub.qol.FlightPaths = { ["2>6"] = 60, ["7>6"] = 40 }
    fly(F, 3)
    settle()
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner = o end
    function tip:IsOwned(o) return self.__owner == o end
    local hit = bar().f.stops[1].hit
    T.truthy(hit and hit:IsShown(), "the dot takes the mouse")
    local Tips, title = DaylightUI.Tips
    local was = Tips.Title
    Tips.Title = function(text, ...) title = text return was(text, ...) end
    hit:GetScript("OnEnter")(hit)
    Tips.Title = was
    T.truthy(GameTooltip:IsShown() and GameTooltip:IsOwned(hit), "a tooltip at once, over the dot")
    T.eq(title, "Ironforge", "with the stop's name")
    hit:GetScript("OnLeave")(hit)
    T.falsy(GameTooltip:IsShown(), "gone with the mouse")
end)

T.test("flight: the land-early button heads for the next stop", function()
    local F = login()
    stub.qol.FlightPaths = { ["2>6"] = 60, ["7>6"] = 40 }
    fly(F, 3)
    settle()
    local box = bar().f
    T.truthy(box.leave:IsShown(), "shown with a stop ahead")
    T.eq(F.LeaveTip(), "Get off at Ironforge", "its tooltip names the next stop")
    stub.Advance(20)
    F.Tick()
    box.leave:GetScript("OnClick")(box.leave, "LeftButton")
    T.eq(earlyAsked, 1, "asks the game to land early")
    T.eq(box.name:GetText(), "Ironforge", "now flying to the stop")
    T.eq(box.time:GetText(), "0:40", "the time left to it")
    settle()
    T.falsy(box.leave:IsShown(), "gone once asked")
    land(F)
    T.isnil(F.Routes()["2>7"], "not learned")
    T.falsy(welcomed(), "no welcome to the old destination")
    leave()
    fly(F, 2)
    settle()
    T.falsy(box.leave:IsShown(), "a direct flight has no stop to land at")
end)

T.test("flight: the shipped path table covers Stormwind to Ironforge", function()
    local F = login()
    fly(F)
    T.eq(bar().f.time:GetText(), F.FormatTime(stub.qol.FlightPaths["2>6"]))
end)

T.test("flight: a learned route shows the time left and fills as you fly", function()
    local F = login()
    F.Routes()["2>6"] = 100
    fly(F)
    local box = bar().f
    T.eq(box.time:GetText(), "1:40")
    stub.Advance(40)
    F.Tick()
    T.eq(box.time:GetText(), "1:00")
    T.near(select(1, box.time:GetTextColor()), (DaylightUI.Style.Pop()), 0.001, "the time in the accent")
    stub.Advance(55)
    F.Tick()
    T.near(select(1, box.time:GetTextColor()), DaylightUI.Style.INK.WARN[1], 0.001, "under 10 s: amber")
    stub.Advance(-55)
    F.Tick()
    T.near(select(1, box.time:GetTextColor()), (DaylightUI.Style.Pop()), 0.001, "back to the accent")
    T.near(box.bar:GetValue(), 0.4, 0.001, "two fifths of the way")
    stub.Advance(65)
    F.Tick()
    T.eq(box.time:GetText(), "Almost there", "past the learned time")
    land(F)
    T.eq(F.Routes()["2>6"], 105, "the newest flight's time replaces the old one")
end)

T.test("flight: without the client's flight point list, names are the key", function()
    local F = login(false)
    noPaths()
    fly(F)
    stub.Advance(30)
    land(F)
    T.eq(F.Routes()["Stormwind, Elwynn>Ironforge, Dun Morogh"], 30)
end)

T.test("flight: a map opened before the client has its points still learns the route", function()
    local F = login()
    local later = mapNodes
    mapNodes = {}
    stub.FireEvent("TAXIMAP_OPENED", 1)
    mapNodes = later
    TakeTaxiNode(2)
    onTaxi = true
    F.Tick()
    stub.Advance(40)
    land(F)
    T.eq(F.Routes()["2>6"], 40, "read again at the pick: from and to known")
end)

T.test("flight: a route flown only the other way counts down from that time", function()
    local F = login()
    noPaths()
    F.Routes()["6>2"] = 90
    fly(F)
    T.eq(bar().f.time:GetText(), "1:30", "the way back's time")
    stub.Advance(95)
    land(F)
    T.eq(F.Routes()["2>6"], 95, "this way is learned on landing")
    T.eq(F.Routes()["6>2"], 90, "the way back keeps its own")
end)

T.test("flight: a flight carried on after a login isn't learned", function()
    local F = login()
    DaylightUI.DB.Character().flight = { key = "2>6", name = "Ironforge", wall = time() - 30 }
    onTaxi = true
    F.Resume()
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    T.truthy(shown(), "still shown")
    stub.Advance(20)
    land(F)
    T.isnil(F.Routes()["2>6"], "the time logged out isn't flying")
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

-- The druids' flight out of Nighthaven starts from the flight master's words,
-- not his map: no TakeTaxiNode, no TAXIMAP_OPENED. Taking it closes the talk
-- and takes control away; the taxi flag can come a moment after either.
local function inMoonglade(faction)
    mapHere = 1450
    stub.units.player = stub.units.player or { name = "Tester", isPlayer = true }
    stub.units.player.faction = faction
end

T.test("flight: the druid flight from Nighthaven to Thunder Bluff shows the timer", function()
    local F = login()
    inMoonglade("Horde")
    stub.FireEvent("GOSSIP_CLOSED", false)
    stub.FireEvent("PLAYER_CONTROL_LOST")
    F.Tick()
    T.falsy(shown(), "nothing until the taxi flag is on")
    onTaxi = true
    F.Tick()
    settle()
    T.truthy(shown(), "the banner is up for a flight started by talking")
    local box = bar().f
    T.eq(box.name:GetText(), "Thunder Bluff", "the destination is known without the map")
    T.eq(box.from:GetText(), "Nighthaven", "and where it left from")
    T.eq(box.time:GetText(), "9:04", "counts down from the game's own path length")
    stub.Advance(530)
    land(F)
    T.truthy(welcomed(), "welcomed on landing")
    T.eq(welcome().name:GetText(), "Thunder Bluff")
    T.eq(F.Routes()["63>22"], 530, "the flight is learned like any other route")
    leave()
end)

T.test("flight: the Alliance druid flight from Nighthaven heads for Rut'theran Village", function()
    local F = login()
    inMoonglade("Alliance")
    -- Only the control event this time, with the taxi flag already on.
    onTaxi = true
    stub.FireEvent("PLAYER_CONTROL_LOST")
    F.Tick()
    settle()
    T.truthy(shown(), "the banner is up")
    T.eq(bar().f.name:GetText(), "Rut'theran Village")
    T.eq(bar().f.time:GetText(), "2:32")
end)

T.test("flight: the druid flight is caught from the talk closing alone", function()
    local F = login()
    inMoonglade("Horde")
    stub.FireEvent("GOSSIP_CLOSED", false)
    stub.Advance(1)
    F.Tick()
    onTaxi = true
    F.Tick()
    T.truthy(shown(), "no control event needed")
    T.eq(bar().f.name:GetText(), "Thunder Bluff")
end)

T.test("flight: a stun in Moonglade shows nothing and stops watching", function()
    local F = login()
    inMoonglade("Horde")
    stub.FireEvent("PLAYER_CONTROL_LOST")
    F.Tick()
    stub.Advance(F.START_WAIT + 1)
    F.Tick()
    onTaxi = true
    F.Tick()
    T.falsy(shown(), "a taxi much later isn't taken for the druid flight")
end)

T.test("flight: the flight master's map in Moonglade still names the picked point", function()
    local F = login()
    inMoonglade("Horde")
    stub.FireEvent("TAXIMAP_OPENED", 1)
    TakeTaxiNode(2)
    stub.FireEvent("PLAYER_CONTROL_LOST")
    onTaxi = true
    F.Tick()
    T.truthy(shown())
    T.eq(bar().f.name:GetText(), "Ironforge", "the map's pick wins over the druid flight")
end)

T.test("flight: elsewhere a taxi without a pick still shows nothing", function()
    local F = login()
    inMoonglade("Horde")
    mapHere = 1453
    stub.FireEvent("GOSSIP_CLOSED", false)
    stub.FireEvent("PLAYER_CONTROL_LOST")
    onTaxi = true
    F.Tick()
    T.falsy(shown())
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
    T.eq(bar().f.time:GetText(), "1:10")
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
    T.eq(bar().f.name:GetText(), "Stormwind")
    DaylightUI.SetTestMode(false)
    settle()
    T.falsy(shown(), "gone with test mode")
end)

T.test("flight: an early landing has no welcome", function()
    local F = login()
    fly(F)
    settle()
    stub.Advance(30)
    TaxiRequestEarlyLanding()
    land(F)
    T.falsy(shown())
    T.falsy(welcomed())
end)

T.test("flight: the welcome slides up into place and the zone title waits for it", function()
    local F = login()
    local Z = stub.qol.ZoneTitle
    fly(F)
    stub.Advance(30)
    land(F)
    local w = welcome()
    T.near(select(5, w.body:GetPoint(1)), 0, 0.01, "slid up to its place")
    T.near(w.body:GetAlpha(), 1, 0.01, "faded in")
    T.truthy(F.Welcoming())
    _G.GetZoneText = function() return "Ironforge" end
    _G.GetSubZoneText = function() return "" end
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    T.falsy(Z.Showing(), "the zone title waits")
    leave()
    T.falsy(welcomed())
    T.truthy(Z.Showing(), "and plays once the welcome has gone")
end)

T.test("flight: a level-up sends the welcome away", function()
    local F = login()
    F.PreviewWelcome()
    T.truthy(welcomed())
    stub.qol.LevelUp.Play(10, 1, 1, 0)
    settle()
    T.falsy(welcomed())
end)

T.test("flight: the line moves on every frame in the air, the text on the tick", function()
    local F = login()
    F.Routes()["2>6"] = 100
    fly(F)
    local box = bar().f
    T.near(box.bar:GetValue(), 0, 0.0001)
    stub.Advance(0.5)
    F.Step(0.01)
    T.near(box.bar:GetValue(), 0.005, 0.0001, "half a second along, between ticks")
    T.eq(box.time:GetText(), "1:40", "the time waits for the tick")
    T.near(select(4, box.head:GetPoint(1)), 0.005 * F.WIDTH, 0.0001, "the light at the exact spot, between pixels")
    T.near(select(4, box.spark:GetPoint(1)), 0.005 * F.WIDTH, 0.0001)
    F.Step(F.TICK)
    T.eq(box.time:GetText(), "1:40", "rounded to the second")
end)

T.test("flight: each piece turned off gives its room back", function()
    login()
    DaylightUI.SetTestMode(true)
    settle()
    local f = bar().f
    local full = bar():GetHeight()
    DaylightUI:Set("QoL", "flightLabel", false)
    T.falsy(f.label:IsShown(), "no Flying to")
    T.truthy(bar():GetHeight() < full, "shorter without it")
    DaylightUI:Set("QoL", "flightLine", false)
    T.falsy(f.bar:IsShown(), "no route line")
    T.falsy(f.head:IsShown(), "and no light")
    DaylightUI:Set("QoL", "flightFrom", false)
    DaylightUI:Set("QoL", "flightTime", false)
    T.falsy(f.from:IsShown())
    T.falsy(f.time:IsShown())
    T.truthy(f.name:IsShown(), "the destination stays")
    DaylightUI.SetTestMode(false)
end)

T.test("flight: width, sizes and the box follow their settings", function()
    login()
    DaylightUI.SetTestMode(true)
    settle()
    DaylightUI:Set("QoL", "flightWidth", 440)
    T.eq(bar():GetWidth(), 440)
    local f = bar().f
    T.near(select(4, f.stops[1]:GetPoint(1)), stub.qol.Flight.SAMPLE.stops[1] * 440, 0.01, "the stop moves with the width")
    local tall = bar():GetHeight()
    DaylightUI:Set("QoL", "flightNameSize", 30)
    T.eq(bar():GetHeight(), tall + 8, "a bigger name makes room for itself")
    DaylightUI:Set("QoL", "flightAccentLine", false)
    T.falsy(f.box.topLine:IsShown(), "no accent line")
    DaylightUI:Set("QoL", "flightBack", false)
    DaylightUI:Set("QoL", "flightFrame.global", false)
    DaylightUI:Set("QoL", "flightFrame.borderAlpha", 0)
    T.truthy(f.name:IsShown(), "the text without a box")
    DaylightUI.SetTestMode(false)
end)

T.test("flight: the welcome can be switched off and has its own handle", function()
    local F = login()
    F.PreviewWelcome()
    T.truthy(DaylightUI.Movers.Get("qol.welcome"), "movable in unlock mode")
    leave()
    DaylightUI:Set("QoL", "flightWelcome", false)
    fly(F)
    stub.Advance(30)
    land(F)
    T.falsy(welcomed(), "no welcome")
end)

T.test("flight: unlock mode shows the welcome too, standing still", function()
    local F = login()
    DaylightUI.Movers.unlocked = true
    F.Update()
    settle()
    T.truthy(welcomed(), "the welcome sample")
    T.falsy(F.Welcoming(), "a sample doesn't hold the zone title up")
    DaylightUI.Movers.unlocked = false
    F.Update()
    T.falsy(welcomed())
end)
