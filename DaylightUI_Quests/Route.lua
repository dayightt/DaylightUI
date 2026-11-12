-- The quest marker's pin: one steady pin on the quest's own map spot (where the
-- world map draws its icon, or the quest giver's "?" once it's ready) for the
-- current quest (picked with its icon in the tracker). The game's spot for a quest
-- is the nearest edge of its area and slides along it as the player moves; this
-- picks a point and keeps it. With nothing for the quest on the current map, the
-- game's own marker handles it. The pin is a map waypoint (C_Map.SetUserWaypoint),
-- and the player's own waypoints are left alone. The pinned quest is remembered
-- (Route.quest), because tracking the waypoint may clear the game's quest pick, so
-- it's restored on release. Smart routing (pinning the nearest mob still needed)
-- was dropped: in play it felt the same as this pin.

local _, ns = ...
local DUI = DaylightUI

local Route = {
    EVERY = 2,      -- seconds between checks while pinning
    SAME = 0.002,   -- map units; closer is the same spot (the client may round what it stores)
    ARRIVE = 20,    -- yards; this close to the pin counts as arrived
    LEAVE = 150,    -- yards from the arrival spot before it counts as leaving
}
ns.Route = Route

local mod, ticker, listening
local ours          -- { map, x, y }: the waypoint this file set
local arrived       -- { map, x, y }: that waypoint, once reached

local function db() return mod and mod.db and mod.db.nav end
local function enabled()
    local n = db()
    return n ~= nil and n.marker == true
end

local function call(t, name, ...)
    t = _G[t]
    if type(t) ~= "table" or type(t[name]) ~= "function" then return nil end
    local ok, a, b = pcall(t[name], ...)
    if ok then return a, b end
end

local function pickedQuest()
    local id = call("C_SuperTrack", "GetSuperTrackedQuestID")
    return type(id) == "number" and id > 0 and id or nil
end

local function ready(questID)
    local done = call("C_QuestLog", "ReadyForTurnIn", questID)
    if done == nil then done = call("C_QuestLog", "IsComplete", questID) end
    return done == true
end

local function inLog(questID)
    return call("C_QuestLog", "GetLogIndexForQuestID", questID) ~= nil
end

-- Still followed: in the tracker and picked (the quest itself, or the pin tracked
-- in its place). A quest no longer tracked clears its map pin, otherwise one could
-- be left behind.
local function stillPicked(questID)
    local T = ns.Tracker
    if T and T.Shown and not T.Shown(questID) then return false end
    local picked = pickedQuest()
    if picked then return picked == questID end
    return call("C_SuperTrack", "IsSuperTrackingUserWaypoint") ~= false
end

-- Player position: map, x, y (0-1). nil inside an instance.
local function here()
    local map = call("C_Map", "GetBestMapForUnit", "player")
    if type(map) ~= "number" then return nil end
    local pos = call("C_Map", "GetPlayerMapPosition", map, "player")
    if type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if type(pos.GetXY) == "function" then x, y = pos:GetXY() end
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return map, x, y
end

-- The quest's own spot on this map, where the world map draws its icon (the quest
-- giver's "?" once ready). A list of one, or empty.
local function mapSpot(questID, map)
    local list = call("C_QuestLog", "GetQuestsOnMap", map)
    if type(list) ~= "table" then return {} end
    for _, info in ipairs(list) do
        if type(info) == "table" and info.questID == questID and type(info.x) == "number" and type(info.y) == "number" then
            return { { map = map, x = info.x, y = info.y } }
        end
    end
    return {}
end

-- QuestieDB spots the quest still needs (the turn-in once ready), the map's dots.
-- Empty without QuestieDB. The marker fades near them (Nav.lua).
function Route.Needed(questID)
    if not (ns.Spots and ns.Spots.Ready()) then return {} end
    return ready(questID) and ns.Spots.TurnIn(questID) or ns.Spots.Objectives(questID)
end


-- Yards between two spots on the same map.
local function yards(map, x1, y1, x2, y2)
    local w, h = call("C_Map", "GetMapWorldSize", map)
    if type(w) ~= "number" or type(h) ~= "number" or w == 0 then w, h = 1000, 1000 end
    local dx, dy = (x2 - x1) * w, (y2 - y1) * h
    return math.sqrt(dx * dx + dy * dy)
end
Route.Yards = yards

-- Is the map's waypoint still the one set here?
local function stillOurs()
    if not ours then return false end
    if call("C_Map", "HasUserWaypoint") ~= true then return false end
    local p = call("C_Map", "GetUserWaypoint")
    if type(p) ~= "table" or p.uiMapID ~= ours.map or type(p.position) ~= "table" then return false end
    local x, y = p.position.x, p.position.y
    if type(p.position.GetXY) == "function" then x, y = p.position:GetXY() end
    return type(x) == "number" and math.abs(x - ours.x) < Route.SAME and math.abs(y - ours.y) < Route.SAME
end

-- The waypoint is remembered per character, so after a /reload it's still known
-- as this addon's and turning the marker off clears it (it used to stay on the
-- map, tracked instead of the quest).
local function remember(p)
    ours = p
    local c = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if type(c) == "table" then c.questRoutePin = p end
end

-- The client fires USER_WAYPOINT_UPDATED inside Set/ClearUserWaypoint
-- (SynchronousEvent). With the world map open, its pin then gets created tainted,
-- and the player's shift-click to share it can't copy ("the game blocked
-- CopyToClipboard"). So the map's pin is only touched while the map is closed;
-- with it open, the latest change waits for it to close.
local pending, hooked
local function mapOpen()
    local f = _G.WorldMapFrame
    return type(f) == "table" and f:IsShown()
end
-- Map closed: apply the waiting change, then check again.
local function mapShut()
    if mapOpen() then return end
    local p = pending
    pending = nil
    if p then DUI.SafeCall(p) end
    if Route.quest then DUI.SafeCall(Route.Tick) end
end
local function watchMap()
    if hooked then return end
    hooked = true
    WorldMapFrame:HookScript("OnHide", function() C_Timer.After(0, mapShut) end)
end
local function whenMapShut(fn)
    if not mapOpen() then fn(); return end
    pending = fn
    watchMap()
end

local function setWaypoint(map, x, y)
    local point = _G.UiMapPoint
    if type(point) ~= "table" or type(point.CreateFromCoordinates) ~= "function" then return end
    if call("C_Map", "CanSetUserWaypointOnMap", map) == false then return end
    whenMapShut(function()
        call("C_Map", "SetUserWaypoint", point.CreateFromCoordinates(map, x, y))
        call("C_SuperTrack", "SetSuperTrackedUserWaypoint", true)
    end)
    remember({ map = map, x = x, y = y })
    if ns.Nav then ns.Nav.Glide() end
end

-- Releases the waypoint and gives the game's quest marker back.
function Route.Release()
    -- A pin still waiting for the map to close: never set it now.
    if pending then
        pending = nil
    elseif ours and stillOurs() then
        local q = Route.quest
        whenMapShut(function()
            call("C_Map", "ClearUserWaypoint")
            if q and inLog(q) then call("C_SuperTrack", "SetSuperTrackedQuestID", q) end
        end)
    end
    remember(nil)
end

local function stop()
    if ticker then ticker:Cancel(); ticker = nil end
    arrived = nil
end

-- Is spot p in the list for this map?
local function needed(list, map, p)
    if p.map ~= map then return false end
    for _, s in ipairs(list) do
        if s.map == map and math.abs(s.x - p.x) < Route.SAME and math.abs(s.y - p.y) < Route.SAME then return true end
    end
    return false
end

-- Reached the waypoint: remove it (it used to stay, and the arrow pointed back at
-- it while fighting around the camp). The player is where the step is, so nothing
-- new is set while that spot is still needed and they're near it (a new pin at the
-- nearest spawn made the marker jump closer). Walking away moves it on.
local function arrive()
    arrived = ours
    if stillOurs() then whenMapShut(function() call("C_Map", "ClearUserWaypoint") end) end
    remember(nil)
end

-- The game drops a reached pin and everything tracked (SuperTrackedFrame's
-- OnDestinationReached). Never seen firing in game, so Tick checks the distance too.
local function onReached(_, isWaypoint)
    if isWaypoint or not ours or not Route.quest then return end
    if call("C_Map", "HasUserWaypoint") == true and not stillOurs() then return end
    arrive()
end

-- The spot arrived at, while the pin rests there (the arrow rests too).
function Route.Arrived() return arrived end

-- One check: the quest's spot on the current map.
function Route.Tick()
    -- Map open: its pin can't be read or moved now (see whenMapShut), check again after.
    if mapOpen() then watchMap(); return end
    local q = Route.quest
    if not enabled() or not q or not inLog(q) or not stillPicked(q) then
        Route.Release()
        Route.quest = nil
        stop()
        return
    end
    -- Arrived and the player placed their own waypoint: theirs.
    if arrived and not ours and call("C_Map", "HasUserWaypoint") == true then
        Route.quest = nil
        stop()
        return
    end
    -- The player placed their own waypoint: theirs wins.
    if ours and not stillOurs() and call("C_Map", "HasUserWaypoint") == true then
        remember(nil)
        Route.quest = nil
        stop()
        return
    end
    local map, px, py = here()
    if not map then Route.Release(); return end
    local list = mapSpot(q, map)
    if ours and stillOurs() and ours.map == map and yards(map, px, py, ours.x, ours.y) < Route.ARRIVE then arrive() end
    -- The arrival spot is still needed and the player is near it: nothing new.
    if arrived then
        if needed(list, map, arrived) and yards(map, px, py, arrived.x, arrived.y) < Route.LEAVE then return end
        arrived = nil
    end
    local best, bestD
    for _, s in ipairs(list) do
        if s.map == map then
            local d = yards(map, px, py, s.x, s.y)
            if not bestD or d < bestD then best, bestD = s, d end
        end
    end
    if not best then Route.Release(); return end
    -- The pin stays put while its spot is still needed (it used to creep closer,
    -- hopping to nearer spawns). It only moves when the step is done, the quest is
    -- ready, or the zone changes.
    if ours and stillOurs() and needed(list, map, ours) then return end
    setWaypoint(map, best.x, best.y)
end

-- Routes a quest (nil = none).
function Route.Follow(questID)
    if questID == Route.quest then return end
    arrived = nil
    if not questID then Route.Release() end
    Route.quest = questID
    if questID and enabled() then
        if not ticker then ticker = C_Timer.NewTicker(Route.EVERY, function() DUI.SafeCall(Route.Tick) end) end
        Route.Tick()
    else
        stop()
    end
end

-- Check on the next frame. Setting the pin changes what's tracked, and its second
-- half (tracking the pin) hasn't run yet when that event fires.
local function lookSoon()
    C_Timer.After(0, function()
        if Route.quest then DUI.SafeCall(Route.Tick) end
    end)
end

-- A bare QUEST_LOG_UPDATE comes in bursts (many per second in combat): one check
-- LOG_WAIT after the first, same as the tracker (Tracker.LOG_WAIT).
Route.LOG_WAIT = 0.15
local logWaiting = false
local function logSoon()
    if logWaiting or not Route.quest then return end
    logWaiting = true
    C_Timer.After(Route.LOG_WAIT, function()
        logWaiting = false
        if Route.quest then DUI.SafeCall(Route.Tick) end
    end)
end

local function onTracking()
    -- Tracking the addon's own waypoint isn't a new pick; picking a quest is.
    local q = pickedQuest()
    if q then Route.Follow(q) else lookSoon() end
end

function Route.Refresh()
    if not mod then return end
    if not enabled() then
        Route.Release()
        Route.quest = nil
        stop()
        return
    end
    Route.Follow(pickedQuest() or Route.quest)
    if Route.quest then Route.Tick() end
end

function Route.Enable(m)
    mod = m
    local c = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if type(c) == "table" and type(c.questRoutePin) == "table" then ours = c.questRoutePin end
    if not listening then
        listening = true
        DUI.RegisterEvent("SUPER_TRACKING_CHANGED", onTracking)
        -- A step done or the quest ready: check again soon (once per burst).
        DUI.RegisterEvent("QUEST_LOG_UPDATE", logSoon)
        DUI.RegisterEvent("QUEST_WATCH_LIST_CHANGED", lookSoon)
        DUI.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
            if Route.quest then DUI.SafeCall(Route.Tick) end
        end)
        DUI.RegisterEvent("NAVIGATION_DESTINATION_REACHED", onReached)
    end
    Route.Refresh()
end
