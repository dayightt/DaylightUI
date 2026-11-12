local stub = require("stub")
local QW = require("questworld")

-- The in-world quest marker (Nav.lua), its map pin (Route.lua), the TomTom-style
-- arrow (Arrow.lua) and the quest spots from QuestieDB (Spots.lua).

-- The client's navigation: one frame on the target's screen spot.
local function navWorld(nav)
    nav.frame = nav.frame or CreateFrame("Frame", nil, UIParent)
    nav.frame:SetSize(1, 1)
    nav.frame.__center = { nav.x or 400, nav.y or 300 }   -- the fake game's GetCenter
    _G.C_Navigation = {
        GetFrame = function() return nav.on ~= false and nav.frame or nil end,
        GetDistance = function() return nav.distance or 120 end,
        GetTargetState = function() return nav.state or 2 end,
        HasValidScreenPosition = function() return true end,
        WasClampedToScreen = function() return nav.clamped == true end,
    }
    -- The game's own marker and its pieces.
    local g = CreateFrame("Frame", "SuperTrackedFrame", UIParent)
    for _, k in ipairs({ "Icon", "Arrow", "IconBorder" }) do g[k] = g:CreateTexture() end
    g.DistanceText = g:CreateFontString()
end

-- QuestieDB as its API says: spots by AreaID in 0-100.
local function questie(db)
    _G.LibQuestieDB = {
        RequireContract = function() return true end,
        Support = { Get = function() return { private = { areaIdToUiMapId = "return { [40] = 52 }" } } end },
    }
    local function entity(t)
        return { Get = function(id, key) local e = t[id]; return e and e[key] end }
    end
    _G.QuestDB = entity(db.quests or {})
    _G.NpcDB = entity(db.npcs or {})
    _G.ObjectDB = entity(db.objects or {})
    _G.ItemDB = entity(db.items or {})
end

-- The map: the player's spot and a waypoint the client keeps.
local function mapWorld(m)
    m.waypoint = nil
    local C = _G.C_Map
    C.GetBestMapForUnit = function() return 52 end
    C.GetPlayerMapPosition = function() return { x = m.px or 0.5, y = m.py or 0.5 } end
    C.GetMapWorldSize = function() return 1000, 1000 end
    C.CanSetUserWaypointOnMap = function() return true end
    C.SetUserWaypoint = function(p) m.waypoint = p end
    C.ClearUserWaypoint = function() m.waypoint = nil end
    C.HasUserWaypoint = function() return m.waypoint ~= nil end
    C.GetUserWaypoint = function() return m.waypoint end
    C.GetUserWaypointPositionForMap = function(map)
        if m.waypoint and m.waypoint.uiMapID == map then return m.waypoint.position end
    end
    _G.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, position = { x = x, y = y } } end }
    _G.GetPlayerFacing = function() return m.facing or 0 end
    local ST = _G.C_SuperTrack
    ST.SetSuperTrackedUserWaypoint = function(on) m.trackingWaypoint = on end
    ST.IsSuperTrackingUserWaypoint = function() return m.trackingWaypoint == true and m.waypoint ~= nil end
end

local function load(spec)
    local nav, map = { on = true }, {}
    local world = QW.world(spec.world or { quests = {} })
    stub.Load({ quests = true, before = function()
        world()
        navWorld(nav)
        mapWorld(map)
        _G.LibQuestieDB, _G.QuestDB, _G.NpcDB, _G.ObjectDB, _G.ItemDB = nil, nil, nil, nil, nil
        if spec.questie then questie(spec.questie) end
        -- A /reload: what was saved, and the waypoint the client kept.
        if spec.saved then _G.DaylightUIDB = spec.saved end
        if spec.waypoint then map.waypoint = spec.waypoint end
        if spec.before then spec.before() end
    end })
    -- Both are off by default: the marker tests turn the marker on.
    for k, v in pairs(spec.settings or { ["nav.marker"] = true }) do DaylightUI:Set("Quests", k, v) end
    stub.quests.Nav.Refresh()
    stub.quests.Arrow.Refresh()
    return stub.quests, nav, map
end

local DB = {
    quests = {
        [100] = { objectives = { { { 7 } } }, finishedBy = { { 9 } } },
    },
    npcs = {
        [7] = { spawns = { [40] = { { 10, 10 }, { 60, 50 } } } },
        [9] = { spawns = { [40] = { { 52, 52 } } } },
    },
}

local KILL = QW.quest(100, "Wolves", { objs = { { text = "Wolf slain", have = 1, need = 5, type = "monster" } } })

T.test("quest marker: rides the client's frame and hides the game's pieces", function()
    local ns, nav = load({})
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local f = ns.Nav.Frame()
    T.truthy(f and f:IsShown(), "our marker is up")
    T.eq(SuperTrackedFrame.Icon:GetAlpha(), 0, "the game's icon is hidden")
    T.eq(SuperTrackedFrame.DistanceText:GetAlpha(), 0, "the game's distance is hidden")
    stub.RunOnUpdate(f, 1)
    local _, _, _, x, y = f:GetPoint()
    T.near(x, 400, 1); T.near(y, 300, 1)
    T.truthy(stub.Text(f.dist):find("120"), "the distance shows")
end)

-- Seen in game: a picked quest with a screen spot and a distance, but
-- GetTargetState() = 0 (Invalid). The marker and its trail sat at alpha 0.
T.test("quest marker: an Invalid state with a spot on the screen still shows", function()
    local ns, nav = load({})
    nav.state, nav.distance = 0, 54
    local f = ns.Nav.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(f, 0.1) end
    T.truthy(f:GetAlpha() > 0.9, "the marker shows, alpha " .. tostring(f:GetAlpha()))
    T.truthy(ns.Nav.Trail():GetAlpha() > 0.9, "the breadcrumbs show")
end)

T.test("quest marker: off gives the game's marker back", function()
    local ns = load({})
    DaylightUI:Set("Quests", "nav.marker", false)
    stub.RunTimers()
    T.eq(SuperTrackedFrame.Icon:GetAlpha(), 1, "the game's icon is back")
    T.falsy(ns.Nav.Frame():IsShown(), "ours is gone")
end)

T.test("quest marker: every look builds and off-screen shows the arrow", function()
    local ns, nav = load({})
    for _, look in ipairs(ns.Nav.STYLES) do
        DaylightUI:Set("Quests", "nav.style", look)
        stub.RunTimers()
        stub.RunOnUpdate(ns.Nav.Frame(), 0.1)
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    nav.clamped = true
    stub.RunOnUpdate(ns.Nav.Frame(), 0.1)
    local f = ns.Nav.Frame()
    T.truthy(f.arrow:IsShown(), "the arrow points the way")
    T.truthy(f.arrow:GetAlpha() > 0 and f.arrow:GetAlpha() < 1, "fading in, not popped")
    T.truthy(f.body:IsShown() and f.body:GetAlpha() < 1, "the marker fading out meanwhile")
    for _ = 1, 10 do stub.RunOnUpdate(f, 0.1) end
    T.eq(f.arrow:GetAlpha(), 1); T.falsy(f.body:IsShown(), "the marker gone once the arrow's in")
    nav.clamped = false
    stub.RunOnUpdate(f, 0.05)
    T.truthy(f.body:IsShown() and f.arrow:IsShown(), "back on screen: both, crossing")
    for _ = 1, 10 do stub.RunOnUpdate(f, 0.1) end
    T.falsy(f.arrow:IsShown()); T.eq(f.body:GetAlpha(), 1)
end)

T.test("quest marker: a secret distance shows nothing, no error", function()
    local ns, nav = load({})
    nav.distance = stub.Secret(50)
    stub.RunOnUpdate(ns.Nav.Frame(), 0.1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(stub.Text(ns.Nav.Frame().dist) or "", "")
end)

-- Walking up to it, the marker seemed to move toward you. The game's spot does
-- stay put and slides down the screen toward your feet, as a spot on the ground
-- does, but a marker that never grew read as coming closer. It now grows as you
-- near it and fades out at the spot.
T.test("quest marker: grows as you near it and fades out at the spot", function()
    local ns, nav = load({ settings = { ["nav.marker"] = true, ["nav.style"] = "pillar" } })
    local f = ns.Nav.Frame()
    local function at(yards)
        nav.distance = yards
        for _ = 1, 30 do stub.RunOnUpdate(f, 0.1) end
        return f.look.frame:GetScale(), f:GetAlpha()
    end
    local far, farA = at(80)
    local mid, midA = at(30)
    local near = at(16)
    T.truthy(far < mid and mid < near, "bigger as you near it: " .. far .. ", " .. mid .. ", " .. near)
    T.truthy(near <= ns.Nav.SIZE_MAX and far >= ns.Nav.SIZE_MIN, "within its limits")
    T.truthy(farA > 0.9 and midA > 0.9, "shows on the way")
    local _, fading = at(10)
    T.truthy(fading > 0.05 and fading < 0.9, "fading in the last yards, alpha " .. fading)
    local _, gone = at(4)
    T.truthy(gone < 0.05, "gone at the spot, alpha " .. gone)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quest marker: breadcrumbs lie from your feet to the marker and drift forward", function()
    local ns = load({})
    local f = ns.Nav.Frame()
    for _ = 1, 30 do stub.RunOnUpdate(f, 0.1) end
    local trail = ns.Nav.Trail()
    T.truthy(trail and trail:GetAlpha() > 0.5, "the trail shows")
    local c = trail.crumbs[5]
    local _, _, _, x1, y1 = c:GetPoint()
    stub.RunOnUpdate(f, 0.2)
    local _, _, _, x2, y2 = c:GetPoint()
    T.truthy(y2 > y1, "a crumb moved on toward the marker")
    local w1 = trail.crumbs[2]:GetWidth()
    T.truthy(trail.crumbs[12]:GetWidth() < w1, "smaller far off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quest marker: breadcrumbs off leaves only the marker", function()
    local ns = load({})
    DaylightUI:Set("Quests", "nav.trail", false)
    stub.RunTimers()
    for _ = 1, 30 do stub.RunOnUpdate(ns.Nav.Frame(), 0.1) end
    T.truthy(ns.Nav.Trail():GetAlpha() < 0.05, "no trail")
end)

T.test("quest marker: in the quest's area on the map everything fades away, and comes back outside", function()
    local ns = load({ world = { quests = { KILL }, focus = 100 } })
    local f = ns.Nav.Frame()
    for _ = 1, 30 do stub.RunOnUpdate(f, 0.1) end
    local zone = ns.Nav.ZoneFrame()
    T.truthy(zone, "a quest area frame of ours")
    T.eq(zone:GetObjectType(), "QuestPOIFrame")
    local inside = true
    local drawn
    zone.DrawBlob = function(_, id) drawn = id end
    zone.UpdateMouseOverTooltip = function() return inside and 100 or nil end
    ns.Nav.ForgetZone()
    for _ = 1, 40 do stub.RunOnUpdate(f, 0.1) end
    T.eq(drawn, 100, "the picked quest's area")
    T.truthy(ns.Nav.InZone(), "in the zone")
    T.truthy(f:GetAlpha() < 0.05, "the marker is gone")
    T.truthy(ns.Nav.Trail():GetAlpha() < 0.05, "the trail is gone")
    inside = false
    for _ = 1, 40 do stub.RunOnUpdate(f, 0.1) end
    T.truthy(f:GetAlpha() > 0.9, "back outside the area")
end)

-- Standing among the quest's dots, the marker stayed up because the game's area
-- check never said "in". Near any spot the quest still needs (QuestieDB's or the
-- map's) everything fades; away from all of them it comes back.
T.test("quest marker: near the quest's spots it fades away, and comes back away from them", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB })
    local f = ns.Nav.Frame()
    map.px, map.py = 0.3, 0.3              -- far from both wolves
    for _ = 1, 30 do stub.RunOnUpdate(f, 0.1) end
    T.truthy(f:GetAlpha() > 0.9, "shows on the way")
    map.px, map.py = 0.12, 0.13            -- among the wolves at 10, 10
    for _ = 1, 40 do stub.RunOnUpdate(f, 0.1) end
    T.truthy(ns.Nav.InZone(), "you're there")
    T.truthy(f:GetAlpha() < 0.05, "the marker is gone, alpha " .. f:GetAlpha())
    map.px, map.py = 0.152, 0.12           -- 56 yards off: inside the margin, no flicker
    for _ = 1, 10 do stub.RunOnUpdate(f, 0.1) end
    T.truthy(ns.Nav.InZone(), "still there at the edge")
    map.px, map.py = 0.3, 0.3
    for _ = 1, 40 do stub.RunOnUpdate(f, 0.1) end
    T.truthy(f:GetAlpha() > 0.9, "back once you leave")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quest spots: the spawns of what's still needed", function()
    local ns = load({ world = { quests = { KILL } }, questie = DB })
    local list = ns.Spots.Objectives(100)
    T.eq(#list, 2, "both wolf spawns")
    T.eq(list[1].map, 52, "on the map QuestieDB's area maps to")
    T.near(list[2].x, 0.6, 0.001); T.near(list[2].y, 0.5, 0.001)
end)

T.test("quest spots: a quest's turn-in is its quest giver", function()
    local ns = load({ world = { quests = { KILL } }, questie = DB })
    local list = ns.Spots.TurnIn(100)
    T.eq(#list, 1)
    T.near(list[1].x, 0.52, 0.001)
end)

T.test("quest arrow: puts no pin on the map and leaves the quest pick alone", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    for _ = 1, 10 do
        stub.FireEvent("QUEST_LOG_UPDATE")
        stub.Advance(2)
        stub.RunOnUpdate(ns.Arrow.Frame(), 0.1)
    end
    T.isnil(map.waypoint, "no map pin")
    T.falsy(map.trackingWaypoint)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The quest's own spot on the map (where the world map draws its icon):
-- the marker's pin goes there.
local function onMap()
    C_QuestLog.GetQuestsOnMap = function(m)
        if m ~= 52 then return {} end
        return { { questID = 100, mapID = 52, x = 0.4, y = 0.7 } }
    end
end

T.test("marker pin: the player's own waypoint wins", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 },
        settings = { ["nav.marker"] = true }, before = onMap })
    ns.Route.Refresh()
    T.truthy(map.waypoint, "our pin")
    map.waypoint = { uiMapID = 52, position = { x = 0.9, y = 0.9 } }
    ns.Route.Tick()
    T.near(map.waypoint.position.x, 0.9, 0.001, "theirs stays")
    T.isnil(ns.Route.quest, "we let go")
end)

-- A quest no longer tracked clears its map pin. One used to be left on the map
-- with nothing picked.
T.test("marker pin: untracking its quest clears the pin", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 },
        settings = { ["nav.marker"] = true }, before = onMap })
    ns.Route.Refresh()
    T.truthy(map.waypoint, "our pin")
    C_QuestLog.RemoveQuestWatch(100)
    stub.FireEvent("QUEST_WATCH_LIST_CHANGED")
    stub.RunTimers()
    stub.RunTickers()
    T.isnil(map.waypoint, "the pin goes with the quest out of the tracker")
    T.isnil(ns.Route.quest)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("marker pin: nothing picked any more clears the pin", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 },
        settings = { ["nav.marker"] = true }, before = onMap })
    ns.Route.Refresh()
    T.truthy(map.waypoint, "our pin")
    -- The game: nothing super-tracked, neither the quest nor our pin.
    QW.state.focus = nil
    map.trackingWaypoint = false
    stub.FireEvent("SUPER_TRACKING_CHANGED")
    stub.RunTimers()
    stub.RunTickers()
    T.isnil(map.waypoint, "the pin goes once nothing's picked")
    T.isnil(ns.Route.quest)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- QUEST_LOG_UPDATE comes in bursts, many a second in a fight. The marker looks
-- again once per burst, the same way the tracker does (LOG_WAIT).
T.test("quest marker: a burst of quest log updates looks again once", function()
    local ns = load({ world = { quests = { KILL }, focus = 100 }, settings = { ["nav.marker"] = true } })
    ns.Route.Refresh()
    stub.RunTimers()
    T.truthy(ns.Route.quest, "following the picked quest")
    local looks, tick = 0, ns.Route.Tick
    ns.Route.Tick = function(...) looks = looks + 1; return tick(...) end
    for _ = 1, 5 do stub.FireEvent("QUEST_LOG_UPDATE") end
    T.eq(looks, 0, "not on each event")
    stub.RunTimers()
    T.eq(looks, 1, "once for the burst")
    ns.Route.Tick = tick
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's own spot for a quest slides along the edge of the quest's area as
-- you move. The marker instead plants a pin on the quest's spot on the map,
-- where the world map draws its icon (C_QuestLog.GetQuestsOnMap), and stays.
T.test("quest marker: plants on the quest's spot on the map and stays there", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 },
        settings = { ["nav.marker"] = true },
        before = function()
            C_QuestLog.GetQuestsOnMap = function(m)
                if m ~= 52 then return {} end
                return { { questID = 100, mapID = 52, x = 0.4, y = 0.7 } }
            end
        end })
    ns.Route.Refresh()
    T.truthy(map.waypoint, "a pin of ours")
    T.near(map.waypoint.position.x, 0.4, 0.001, "on the quest's spot")
    T.near(map.waypoint.position.y, 0.7, 0.001)
    T.truthy(map.trackingWaypoint, "the marker stands on it")
    -- Side to side and closer: it stays.
    for _, p in ipairs({ { 0.45, 0.5 }, { 0.35, 0.55 }, { 0.42, 0.6 } }) do
        map.px, map.py = p[1], p[2]
        stub.FireEvent("QUEST_LOG_UPDATE")
        stub.Advance(2)
        T.near(map.waypoint.position.x, 0.4, 0.001, "still on the quest's spot")
        T.near(map.waypoint.position.y, 0.7, 0.001)
    end
    -- Marker off: the pin goes and the quest pick comes back.
    DaylightUI:Set("Quests", "nav.marker", false)
    stub.RunTimers()
    T.isnil(map.waypoint, "no pin left behind")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The arrow's turn, kept in -pi..pi to compare.
local function turnOf(ns)
    local r = ns.Arrow.Frame().arrow.__rotation or 0
    return (r + math.pi) % (2 * math.pi) - math.pi
end

T.test("defaults: the marker and the arrow are off, the game's marker is left alone", function()
    local ns = load({ settings = {} })
    local f = ns.Nav.Frame()
    T.truthy(not f or not f:IsShown(), "no marker of ours")
    T.eq(SuperTrackedFrame.Icon:GetAlpha(), 1, "the game's icon shows")
    local a = ns.Arrow.Frame()
    T.truthy(not a or not a:IsShown(), "no arrow")
end)

T.test("quest arrow: points to the nearest spawn still needed, with the yards", function()
    local ns = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    local a = ns.Arrow.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.near(ns.Arrow.Target().x, 0.6, 0.001, "the wolf at 60, 50 is nearer than 10, 10")
    T.near(turnOf(ns), -math.pi / 2, 0.01, "facing north, the wolf to the east: the arrow points right")
    T.truthy(stub.Text(a.dist):find("100"), "100 yards, got " .. tostring(stub.Text(a.dist)))
    T.truthy(a:GetAlpha() > 0.9, "it shows")
end)

-- Seen in game: the marker on the game's spot, the arrow on the nearest wolf
-- 83 yards the other way. While the game shows a marker, the arrow points there.
T.test("quest arrow: points where the game's marker stands", function()
    local ns, nav = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    C_Navigation.GetNextWaypointForMap = function(map) if map == 52 then return 0.5, 0.3, "" end end
    local a = ns.Arrow.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.near(ns.Arrow.Target().x, 0.5, 0.001, "the marker's spot, not the wolf")
    T.near(ns.Arrow.Target().y, 0.3, 0.001)
    T.near(turnOf(ns), 0, 0.01, "facing north, the marker due north: straight up")
    -- The game guides you nowhere: the nearest spot again.
    nav.on = false
    ns.Arrow.Wake()
    for _ = 1, 5 do stub.RunOnUpdate(a, 0.1) end
    T.near(ns.Arrow.Target().x, 0.6, 0.001, "the wolf")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a map pin tracked, the marker on it 507 yards ahead, and
-- GetNextWaypointForMap returning nothing, so the arrow pointed at a wolf
-- 569 yards behind. A tracked pin is where the marker stands, so point there.
T.test("quest arrow: points at the tracked map pin when the game names no next step", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    C_Navigation.GetNextWaypointForMap = function() end
    map.waypoint = { uiMapID = 52, position = { x = 0.5, y = 0.2 } }
    map.trackingWaypoint = true
    local a = ns.Arrow.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.near(ns.Arrow.Target().x, 0.5, 0.001, "the pin, not the wolf")
    T.near(ns.Arrow.Target().y, 0.2, 0.001)
    T.near(turnOf(ns), 0, 0.01, "facing north, the pin due north: straight up")
    -- The pin no longer tracked: the nearest spot again.
    map.trackingWaypoint = false
    ns.Arrow.Wake()
    for _ = 1, 5 do stub.RunOnUpdate(a, 0.1) end
    T.near(ns.Arrow.Target().x, 0.6, 0.001, "the wolf")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quest arrow: turns with your facing", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    map.facing = 3 * math.pi / 2   -- east
    local a = ns.Arrow.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.near(turnOf(ns), 0, 0.01, "facing the wolf: straight up")
end)

T.test("quest arrow: a ready quest points to the quest giver", function()
    local ready = QW.quest(100, "Wolves", { complete = true, objs = { { text = "Wolf slain", have = 5, need = 5, done = true } } })
    local ns = load({ world = { quests = { ready }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    for _ = 1, 5 do stub.RunOnUpdate(ns.Arrow.Frame(), 0.1) end
    T.near(ns.Arrow.Target().x, 0.52, 0.001, "the turn-in NPC")
end)

T.test("quest arrow: without QuestieDB it stays away, no error", function()
    local ns = load({ world = { quests = { KILL }, focus = 100 }, settings = { ["nav.arrow"] = true } })
    local a = ns.Arrow.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.isnil(ns.Arrow.Target())
    T.eq(a:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- With the marker on, the game tracks its map pin, not the quest
-- (GetSuperTrackedQuestID gives 0): the arrow follows the pin's quest.
T.test("quest arrow: with the marker's pin tracked it still finds the quest", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB,
        settings = { ["nav.marker"] = true, ["nav.arrow"] = true }, before = onMap })
    C_SuperTrack.GetSuperTrackedQuestID = function() return map.trackingWaypoint and 0 or 100 end
    local a = ns.Arrow.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.truthy(map.trackingWaypoint, "the pin is tracked")
    T.truthy(ns.Arrow.Target(), "the arrow has somewhere to point")
    T.truthy(a:GetAlpha() > 0.9, "and shows")
end)

-- Seen in game: nothing picked (GetSuperTrackedQuestID returned nil), so the
-- arrow had nothing to point at. It falls back to the tracker's quests.
T.test("quest arrow: nothing picked, it points to the nearest spot of the tracked quests", function()
    local ns = load({ world = { quests = { KILL } }, questie = DB, settings = { ["nav.arrow"] = true } })
    C_SuperTrack.GetSuperTrackedQuestID = function() return nil end
    local a = ns.Arrow.Frame()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.truthy(ns.Arrow.Target(), "a spot of the tracked quest")
    T.near(ns.Arrow.Target().x, 0.6, 0.001)
    T.truthy(a:GetAlpha() > 0.9, "it shows")
end)

-- After a /reload with the marker off, the pin stayed on the map, tracked in
-- place of the quest. It's remembered as ours and cleared.
T.test("marker pin: after a reload, turning the marker off clears its pin", function()
    local _, _, map = load({ world = { quests = { KILL }, focus = 100 },
        settings = { ["nav.marker"] = true }, before = onMap })
    local pin = map.waypoint
    T.truthy(pin, "the marker set its pin")
    -- Saved with the marker off (the default), the pin still on the map.
    local saved = _G.DaylightUIDB
    local function unmark(t)
        for k, v in pairs(t) do
            if k == "marker" then t[k] = nil elseif type(v) == "table" then unmark(v) end
        end
    end
    unmark(saved)
    local _, _, map2 = load({ world = { quests = { KILL }, focus = 100 },
        saved = saved, waypoint = pin, settings = {}, before = onMap })
    T.isnil(map2.waypoint, "the old pin is gone")
end)

T.test("quest arrow options: a custom color, no glow, no yards", function()
    local ns = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = {
        ["nav.arrow"] = true, ["nav.arrowColorMode"] = "custom", ["nav.arrowColor"] = { 0.2, 0.4, 0.6 },
        ["nav.arrowGlow"] = false, ["nav.arrowDistance"] = false } })
    local a = ns.Arrow.Frame()
    local r, g, b = a.arrow:GetVertexColor()
    T.near(r, 0.2, 0.01); T.near(g, 0.4, 0.01); T.near(b, 0.6, 0.01)
    T.falsy(a.glow:IsShown(), "no glow")
    T.falsy(a.dist:IsShown(), "no yards")
end)

T.test("quest arrow options: class color, the glow's strength", function()
    local ns = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = {
        ["nav.arrow"] = true, ["nav.arrowColorMode"] = "class", ["nav.arrowGlowAlpha"] = 0.8 } })
    local a = ns.Arrow.Frame()
    local r, g, b = a.arrow:GetVertexColor()
    local cr, cg, cb = DaylightUI.Style.ClassColor(select(2, UnitClass("player")))
    T.near(r, cr, 0.01); T.near(g, cg, 0.01); T.near(b, cb, 0.01)
    local _, _, _, ga = a.glow:GetVertexColor()
    T.near(ga, 0.8, 0.01)
    T.truthy(a.glow:IsShown())
end)

-- Reaching the pin used to leave it there, so the arrow pointed back at it as
-- you fought around. Now the pin goes once reached and stays gone while you're
-- at that spot. Walk away and it's back.
T.test("marker pin: reaching it wipes it, the arrow rests, leaving brings it back", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB,
        settings = { ["nav.marker"] = true, ["nav.arrow"] = true }, before = onMap })
    T.near(map.waypoint.position.x, 0.4, 0.001, "on the quest's spot")
    local a = ns.Arrow.Frame()
    map.px, map.py = 0.4, 0.71           -- 10 yards from the pin
    stub.RunTickers()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.isnil(map.waypoint, "the pin is wiped once you're there")
    map.px, map.py = 0.4, 0.76           -- 60 yards off, still there
    stub.RunTickers()
    for _ = 1, 20 do stub.RunOnUpdate(a, 0.1) end
    T.isnil(map.waypoint, "no pin back while you're at that spot")
    T.truthy(a:GetAlpha() < 0.05, "the arrow doesn't point back, alpha " .. tostring(a:GetAlpha()))
    T.eq(ns.Route.quest, 100, "still follows the quest")
    map.px, map.py = 0.1, 0.1            -- walked off
    stub.RunTickers()
    T.truthy(map.waypoint, "the pin is back once you leave")
    T.near(map.waypoint.position.x, 0.4, 0.001)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("quest arrow: reaching its spot it fades out, and comes back once you leave", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    local a = ns.Arrow.Frame()
    for _ = 1, 5 do stub.RunOnUpdate(a, 0.3) end
    T.near(ns.Arrow.Target().x, 0.6, 0.001)
    map.px, map.py = 0.6, 0.51
    for _ = 1, 10 do stub.RunOnUpdate(a, 0.3) end
    map.px, map.py = 0.6, 0.56
    for _ = 1, 10 do stub.RunOnUpdate(a, 0.3) end
    T.truthy(a:GetAlpha() < 0.05, "gone at the spot, alpha " .. tostring(a:GetAlpha()))
    map.px, map.py = 0.2, 0.2
    for _ = 1, 10 do stub.RunOnUpdate(a, 0.3) end
    T.near(ns.Arrow.Target().x, 0.1, 0.001, "the next spot")
    T.truthy(a:GetAlpha() > 0.9, "back once you leave")
end)

T.test("quest arrow: its spot stays put as you walk toward another spawn", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 }, questie = DB, settings = { ["nav.arrow"] = true } })
    local a = ns.Arrow.Frame()
    for _ = 1, 5 do stub.RunOnUpdate(a, 0.3) end
    T.near(ns.Arrow.Target().x, 0.6, 0.001)
    map.px, map.py = 0.12, 0.12
    for _ = 1, 10 do stub.RunOnUpdate(a, 0.3) end
    T.near(ns.Arrow.Target().x, 0.6, 0.001, "still the first one")
end)


T.test("marker pin: never touches the map pin while the world map is open", function()
    local ns, _, map = load({ world = { quests = { KILL }, focus = 100 },
        settings = { ["nav.marker"] = true },
        before = function() onMap(); CreateFrame("Frame", "WorldMapFrame", UIParent) end })
    WorldMapFrame:Show()
    ns.Route.Refresh()
    T.isnil(map.waypoint, "no pin set with the map open")
    WorldMapFrame:Hide()
    stub.RunTimers()
    T.truthy(map.waypoint, "set once the map closes")
    T.near(map.waypoint.position.x, 0.4, 0.001)
    WorldMapFrame:Show()
    ns.Route.Follow(nil)
    T.truthy(map.waypoint, "not cleared with the map open")
    WorldMapFrame:Hide()
    stub.RunTimers()
    T.isnil(map.waypoint, "cleared once the map closes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("plate kind: a mob your quest needs is a kill, in the accent", function()
    load({ world = { quests = { KILL } }, questie = DB, settings = {} })
    local kind, r, g, b = DaylightUI.QuestKindForUnit("Creature-0-1-2-3-7-0")
    T.eq(kind, "kill")
    local ar, ag, ab = DaylightUI.Style.Accent()
    T.eq(r, ar); T.eq(g, ag); T.eq(b, ab)
    T.isnil(DaylightUI.QuestKindForUnit("Creature-0-1-2-3-99-0"), "one no quest needs")
    T.isnil(DaylightUI.QuestKindForUnit("Player-1-0001"), "a player")
end)
