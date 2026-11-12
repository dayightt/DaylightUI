-- TomTom-style arrow (nav.arrow, off by default). A rotating on-screen arrow that
-- points to the nearest spot still needed for the picked quest (a mob, an object),
-- then to the quest giver once it's ready, with the distance in yards below it.
-- With no quest picked it uses the nearest spot of every quest in the tracker
-- (otherwise it had nothing to point at). Spots come from QuestieDB (Spots.lua).
-- While the game shows a quest marker, the arrow points where the marker is.
--
-- Nothing goes on the map: no waypoint, no pin, and the game's quest pick is left
-- alone (a pin here pinged the map and minimap every time it moved). Direction is
-- worked out from the player's map position, the map's size in yards and the
-- facing (GetPlayerFacing: 0 = north, increasing counterclockwise, same as
-- SetRotation).

local _, ns = ...
local DUI = DaylightUI
local Style, Motion = DUI.Style, DUI.Motion

local Arrow = {
    MOVER = "quests.arrow",
    DEFAULT = { "TOP", nil, "TOP", 0, -150 },
    SIZE = 44,
    EVERY = 1,          -- seconds between nearest-spot picks
    SOON = 0.25,        -- seconds; after a quest log change, pick again within this
    NEAR = 10,          -- yards; within this the arrow calms down
    ARRIVE = 20,        -- yards; within this it rests (same as the marker pin's Route.ARRIVE)
    LEAVE = 150,        -- yards from where it rested before it counts as leaving
    SAME = 0.002,       -- map units; closer than this is the same spot
    NEAR_ALPHA = 0.35,
    FIGHT_ALPHA = 0.4,  -- in combat (nav.fightFade)
    SAMPLE = { yards = 120, turn = 0.6 },   -- unlock mode preview
}
ns.Arrow = Arrow

local mod, f, listening
local target          -- { map, x, y }
local reached         -- { map, x, y }: the spot reached, while resting there
local pickWait = 0
local cur = { alpha = 0, turn = nil }

local function db() return mod and mod.db and mod.db.nav end
local function enabled()
    local n = db()
    return n ~= nil and n.arrow == true
end
local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function num(v) return type(v) == "number" and not secret(v) end

local function call(t, name, ...)
    t = _G[t]
    if type(t) ~= "table" or type(t[name]) ~= "function" then return nil end
    local ok, a, b = pcall(t[name], ...)
    if ok then return a, b end
end

-- The picked quest. With the marker on, the game tracks its map pin instead of the
-- quest, so Route.lua remembers which quest that is (Route.quest).
local function pickedQuest()
    if ns.Route and ns.Route.quest then return ns.Route.quest end
    local id = call("C_SuperTrack", "GetSuperTrackedQuestID")
    return num(id) and id > 0 and id or nil
end

local function ready(questID)
    local done = call("C_QuestLog", "ReadyForTurnIn", questID)
    if done == nil then done = call("C_QuestLog", "IsComplete", questID) end
    return done == true
end

-- Player position: map, x, y (0-1). nil inside an instance or under restrictions.
local function here()
    local map = call("C_Map", "GetBestMapForUnit", "player")
    if not num(map) then return nil end
    local pos = call("C_Map", "GetPlayerMapPosition", map, "player")
    if type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if type(pos.GetXY) == "function" then x, y = pos:GetXY() end
    if not (num(x) and num(y)) then return nil end
    return map, x, y
end

-- Map size in yards. nil = unknown, then no arrow (a wrong direction is worse).
local function size(map)
    local w, h = call("C_Map", "GetMapWorldSize", map)
    if not (num(w) and num(h)) or w <= 0 or h <= 0 then return nil end
    return w, h
end

-- Yards east and south of the player, and the distance.
local function offset(map, px, py, tx, ty)
    local w, h = size(map)
    if not w then return nil end
    local dx, dy = (tx - px) * w, (ty - py) * h
    return dx, dy, math.sqrt(dx * dx + dy * dy)
end

-- Quests to point for: the picked one, else every quest in the tracker.
local function quests()
    local q = pickedQuest()
    if q then return { q } end
    local out = {}
    -- What the tracker shows (Tracker.Shown, every log quest in log mode).
    if ns.Tracker and ns.Tracker.built then
        for _, id in ipairs(ns.Tracker.ShownIDs()) do out[#out + 1] = id end
        return out
    end
    local n = call("C_QuestLog", "GetNumQuestWatches")
    for i = 1, num(n) and n or 0 do
        local id = call("C_QuestLog", "GetQuestIDForQuestWatchIndex", i)
        if num(id) then out[#out + 1] = id end
    end
    return out
end

-- Every spot still needed: objectives, or the quest giver of a ready quest. A list
-- of Spots' cached lists (thousands of spots), never copied, read only.
local function spots()
    local lists = {}
    for _, q in ipairs(quests()) do
        lists[#lists + 1] = ready(q) and ns.Spots.TurnIn(q) or ns.Spots.Objectives(q)
    end
    return lists
end

-- Where the game is guiding the player on this map: the spot its marker (and the
-- addon's, Nav.lua) stands on, or the marker's pin when that's on. nil when the
-- game guides nowhere here. Only 0-1 map spots count. A tracked map pin (from
-- routing, the marker or the player) is where the marker stands:
-- GetNextWaypointForMap returned nothing for one in game, and the arrow pointed
-- at its own spot in the opposite direction.
local function onMap(x, y)
    return num(x) and num(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end
local function guided(map)
    if not (_G.C_Navigation and call("C_Navigation", "GetFrame")) then return nil end
    local x, y = call("C_Navigation", "GetNextWaypointForMap", map)
    if onMap(x, y) then return x, y end
    if call("C_SuperTrack", "IsSuperTrackingUserWaypoint") ~= true then return nil end
    local pos = call("C_Map", "GetUserWaypointPositionForMap", map)
    if type(pos) ~= "table" then return nil end
    x, y = pos.x, pos.y
    if type(pos.GetXY) == "function" then x, y = pos:GetXY() end
    if onMap(x, y) then return x, y end
end

local function same(s, x, y)
    return math.abs(s.x - x) < Arrow.SAME and math.abs(s.y - y) < Arrow.SAME
end

-- Still resting at the spot reached: close to it, and it's still needed (or it's
-- still where the game's marker stands).
local function resting(map, px, py, lists, gx, gy)
    if reached.map ~= map then return false end
    local _, _, d = offset(map, px, py, reached.x, reached.y)
    if not d or d >= Arrow.LEAVE then return false end
    if gx and same(reached, gx, gy) then return true end
    for _, list in ipairs(lists) do
        for _, s in ipairs(list) do
            if s.map == map and same(s, reached.x, reached.y) then return true end
        end
    end
    return false
end

-- The target is still one of the spots needed on this map.
local function stillNeeded(map, lists)
    if not (target and target.map == map) then return false end
    for _, list in ipairs(lists) do
        for _, s in ipairs(list) do
            if s.map == map and s.x == target.x and s.y == target.y then return true end
        end
    end
    return false
end

-- Where the arrow points. While the game shows a marker, the same spot, since two
-- things pointing different ways was confusing. Without a marker, the nearest
-- needed spot on the current map. That one stays put while it's still needed (like
-- the marker's pin) and only changes when the step is done, the quest is ready, or
-- the zone changes. Once reached it rests (so it doesn't point back while fighting
-- around a camp) until the spot isn't needed or the player walks away. It also
-- rests together with the marker's pin.
function Arrow.Pick()
    local map, px, py = here()
    if not map then target = nil; return end
    local gx, gy = guided(map)
    local lists = (ns.Spots and ns.Spots.Ready()) and spots() or {}
    if ns.Route and ns.Route.Arrived() then target = nil; return end
    if reached then
        if resting(map, px, py, lists, gx, gy) then target = nil; return end
        reached = nil
    end
    if gx then target = { map = map, x = gx, y = gy }; return end
    if not (ns.Spots and ns.Spots.Ready()) then target = nil; return end
    -- The current target stays while it's needed, so skip measuring the rest.
    if stillNeeded(map, lists) then return end
    -- Nearest by squared yards; map size is read once rather than per spot.
    local w, h = size(map)
    if not w then target = nil; return end
    local best, bestD
    for _, list in ipairs(lists) do
        for _, s in ipairs(list) do
            if s.map == map then
                local dx, dy = (s.x - px) * w, (s.y - py) * h
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then best, bestD = s, d end
            end
        end
    end
    if not best then target = nil; return end
    target = { map = best.map, x = best.x, y = best.y }
end

local function build()
    if f then return f end
    f = CreateFrame("Frame", "DaylightUIQuestArrow", UIParent)
    f:SetSize(Arrow.SIZE + 40, Arrow.SIZE + 34)
    f:SetFrameStrata("LOW")
    f:EnableMouse(false)
    f:SetAlpha(0)
    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetTexture(ns.Nav.ART.arrow)
    f.arrow:SetSize(Arrow.SIZE, Arrow.SIZE)
    f.arrow:SetPoint("TOP")
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture(ns.Nav.ART.glow)
    f.glow:SetBlendMode("ADD")
    f.glow:SetSize(Arrow.SIZE * 1.8, Arrow.SIZE * 1.8)
    f.glow:SetPoint("CENTER", f.arrow)
    f.dist = Style.Text(f, Style.SIZE.body, "CENTER")
    f.dist:SetPoint("TOP", f.arrow, "BOTTOM", 0, -2)
    DUI.Movers.Register(f, Arrow.MOVER, "Quest arrow", Arrow.DEFAULT, { active = enabled,
        scale = function(s)
            local n = db()
            f:SetScale(((n and n.arrowScale) or 1) * s)
        end })
    return f
end

-- Arrow color (nav.arrowColorMode, same modes as the tracker's bars): the accent
-- (its gradient for a gradient accent), the class color, or a custom color. The
-- glow uses the same color.
function Arrow.Color()
    local n = db() or {}
    local mode = n.arrowColorMode
    if mode == "class" then
        local r, g, b = Style.ClassColor(select(2, UnitClass("player")))
        return r, g, b, false
    end
    if mode == "custom" and type(n.arrowColor) == "table" then
        local c = n.arrowColor
        return c[1] or 1, c[2] or 1, c[3] or 1, false
    end
    local r, g, b = Style.Accent()
    return r, g, b, true
end

local function paint()
    if not f then return end
    local n = db() or {}
    local r, g, b, accent = Arrow.Color()
    if accent then
        Style.PaintAccent(f.arrow, 1, "VERTICAL")
    else
        f.arrow:SetVertexColor(r, g, b, 1)
    end
    f.glow:SetShown(n.arrowGlow ~= false)
    f.glow:SetVertexColor(r, g, b, tonumber(n.arrowGlowAlpha) or 0.35)
    f.dist:SetShown(n.arrowDistance ~= false)
    Style.InkText(f.dist, "VALUE")
end

local function ease(from, to, dt, dur)
    if not Motion.On() then return to end
    return from + (to - from) * math.min(1, dt / dur)
end

-- Turns the short way around (FAST), snaps with motion off.
local function turnTo(want, dt)
    if not cur.turn or not Motion.On() then cur.turn = want; return want end
    local d = (want - cur.turn + math.pi) % (2 * math.pi) - math.pi
    cur.turn = cur.turn + d * math.min(1, dt / Motion.FAST)
    return cur.turn
end

local function distText(d)
    local n = math.floor(d + 0.5)
    local s = n < 1000 and tostring(n) or AbbreviateNumbers(n)
    local fmt = _G.IN_GAME_NAVIGATION_RANGE
    return type(fmt) == "string" and string.format(fmt, s) or s
end

local function showText(text)
    if f.distShown ~= text then
        f.distShown = text
        f.dist:SetText(text)
    end
end

local function sampleWanted()
    return enabled() and DUI.Movers ~= nil and DUI.Movers.unlocked == true
end

local function onUpdate(_, dt)
    pickWait = pickWait - dt
    if pickWait <= 0 then
        pickWait = Arrow.EVERY
        Arrow.Pick()
    end

    local want, turn, d = 0, nil, nil
    if sampleWanted() then
        want, turn, d = 1, Arrow.SAMPLE.turn, Arrow.SAMPLE.yards
    elseif target then
        local map, px, py = here()
        local facing = type(GetPlayerFacing) == "function" and GetPlayerFacing() or nil
        if map == target.map and num(facing) then
            local dx, dy
            dx, dy, d = offset(map, px, py, target.x, target.y)
            if d then
                -- North is up, away from the player: the bearing to it, rotated by the facing.
                turn = math.atan2(-dx, -dy) - facing
                want = d < Arrow.NEAR and Arrow.NEAR_ALPHA or 1
                if d < Arrow.ARRIVE then reached, target, want = target, nil, 0 end
                local n = db()
                if n and n.fightFade and InCombatLockdown() then want = math.min(want, Arrow.FIGHT_ALPHA) end
            end
        end
    end

    if turn then
        f.arrow:SetRotation(turnTo(turn, dt))
        showText(distText(d))
    end
    cur.alpha = ease(cur.alpha, want, dt, Motion.FAST)
    f:SetAlpha(cur.alpha)
    if want == 0 and cur.alpha < 0.01 then
        f:SetAlpha(0)
        cur.alpha, cur.turn = 0, nil
        -- Nothing to point at: sleep until the pick, the log or a setting changes
        -- (resting at a spot keeps checking, so walking away wakes it).
        if not target and not reached and not (ns.Route and ns.Route.Arrived()) then f:SetScript("OnUpdate", nil) end
    end
end

-- Starts the driver (it stops itself when there's nothing to point at).
function Arrow.Wake()
    if not (f and enabled()) then return end
    pickWait = 0
    f:SetScript("OnUpdate", onUpdate)
end

-- The quest log changed (many times a second in combat): pick again shortly, not
-- on every event.
function Arrow.LogChanged()
    if not (f and enabled()) then return end
    if f:GetScript("OnUpdate") ~= onUpdate then return Arrow.Wake() end
    pickWait = math.min(pickWait, Arrow.SOON)
end

function Arrow.Refresh()
    if not mod then return end
    if not enabled() then
        target, reached = nil, nil
        if f then
            f:SetScript("OnUpdate", nil)
            f:SetAlpha(0)
            f:Hide()
        end
        return
    end
    build()
    paint()
    local n = db()
    f:SetScale((n and n.arrowScale) or 1)
    f:Show()
    Arrow.Wake()
end

function Arrow.OnStyleChanged() paint() end

function Arrow.Enable(m)
    mod = m
    if not listening then
        listening = true
        DUI.RegisterEvent("SUPER_TRACKING_CHANGED", Arrow.Wake)
        DUI.RegisterEvent("QUEST_LOG_UPDATE", Arrow.LogChanged)
        DUI.RegisterEvent("ZONE_CHANGED_NEW_AREA", Arrow.Wake)
        DUI.On("UnlockChanged", Arrow.Wake)
    end
    Arrow.Refresh()
end

-- for the tests
Arrow.Frame = function() return f end
Arrow.Target = function() return target end
