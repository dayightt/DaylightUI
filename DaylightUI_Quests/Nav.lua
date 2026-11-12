-- In-world quest marker, drawn over the game's (Blizzard_QuestNavigation). The
-- client keeps one frame on the screen position of whatever is tracked
-- (C_Navigation.GetFrame(): a quest, a waypoint, a corpse) and reports the
-- distance and whether it's visible, occluded or off-screen. This marker rides
-- that frame in one of three styles (nav.style):
--   beacon   an angled diamond in the accent with a soft glow, distance below
--   pillar   a beam in the accent standing on the spot, visible from far away
--   minimal  a small chevron and the distance
-- Off-screen it slides to the edge of an ellipse around the screen center and an
-- arrow points the way (same as the game, SuperTrackedFrame.lua). A new target
-- glides into place, it calms down up close, and pulses on arrival. Breadcrumbs
-- (nav.trail) lie on the ground from the player to it and drift slowly forward.
-- Inside the quest's area on the map (the game's own area blob) everything fades
-- out so the player can just play.
--
-- The game's marker is hidden by setting its own pieces (Icon, Arrow,
-- DistanceText, IconBorder) to alpha 0. The game sets the frame's alpha every
-- frame but never the pieces'. No hook. Restored when this marker is off.

local _, ns = ...
local DUI = DaylightUI
local Style, Motion = DUI.Style, DUI.Motion

local Nav = {
    ART = {
        diamond = DUI.MEDIA .. "waypoint-diamond.png",
        beam = DUI.MEDIA .. "waypoint-beam.png",
        arrow = DUI.MEDIA .. "waypoint-arrow.png",
        crumb = DUI.MEDIA .. "waypoint-crumb.png",
        glow = DUI.MEDIA .. "glow.png",
        chevron = DUI.MEDIA .. "ui-chevron.png",
    },
    STYLES = { "beacon", "pillar", "minimal" },
    -- Alpha per navigation state (Enum.NavigationState): Invalid, Occluded, InRange,
    -- Disabled. Occluded is softer. Invalid still shows: in game, a picked quest with
    -- an on-screen spot and a distance read Invalid, and the game's 0 left nothing on
    -- screen. HasValidScreenPosition decides whether there's a spot at all; inside the
    -- quest's area the zone check fades it.
    STATE_ALPHA = { [0] = 1, 0.6, 1, 0 },
    -- Up close, the game's spot lies on the ground and slides down the screen toward
    -- the player's feet, so a marker that kept its size looked like it was walking
    -- toward them. Instead it grows like an object standing there (normal size at
    -- SIZE_REF yards, clamped to SIZE_MIN..SIZE_MAX) and fades out from NEAR to GONE
    -- yards.
    SIZE_REF = 30, SIZE_MIN = 0.7, SIZE_MAX = 1.6,
    NEAR = 15, GONE = 5,
    FIGHT_ALPHA = 0.4,   -- in combat (nav.fightFade)
    EDGE_X = 0.42, EDGE_Y = 0.36,   -- off-screen ellipse, as fractions of the screen
    PILLAR_H = 150,
    -- Breadcrumbs: count, size near and far (they lie flat, half as tall as wide),
    -- drift speed (crumb steps per second), and where the path starts on screen (as
    -- fractions of width and height, under the character with the usual camera).
    CRUMBS = 14, CRUMB_NEAR = 22, CRUMB_FAR = 6, CRUMB_FLAT = 0.5,
    DRIFT = 0.8, FEET_X = 0.5, FEET_Y = 0.3,
    ZONE_EVERY = 0.5,    -- seconds between checks for being in the quest's area
    THERE = 50, THERE_OUT = 60,   -- yards from a needed spot to count as there, and to count as left
    -- The game's marker pieces that get hidden.
    GAME_PIECES = { "Icon", "Arrow", "DistanceText", "IconBorder" },
}
ns.Nav = Nav

local mod, f, trail, gameHidden, listening
local cur = { alpha = 0, x = nil, y = nil }
local glide          -- { fx, fy, t } while gliding to a new spot

local function db() return mod and mod.db and mod.db.nav end
local function enabled()
    local n = db()
    return n ~= nil and n.marker == true
end
local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

local function api(name)
    local t = _G.C_Navigation
    return type(t) == "table" and type(t[name]) == "function" and t[name] or nil
end

local function navCall(name)
    local fn = api(name)
    if not fn then return nil end
    local ok, v = pcall(fn)
    if ok then return v end
end

-- Hides the game's marker pieces while this marker is on, restores them when off.
local function hideGame(on)
    local g = _G.SuperTrackedFrame
    if type(g) ~= "table" then return end
    for _, key in ipairs(Nav.GAME_PIECES) do
        local p = g[key]
        if type(p) == "table" and type(p.SetAlpha) == "function" then p:SetAlpha(on and 0 or 1) end
    end
    gameHidden = on
end

-- Pieces for one style, created the first time it's picked.
local function tex(parent, file, layer, blend)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(file)
    if blend then t:SetBlendMode(blend) end
    return t
end

local builders = {}

function builders.beacon(p)
    local s = {}
    s.light = tex(p, Nav.ART.glow, "BACKGROUND", "ADD")
    s.light:SetSize(56, 56)
    s.light:SetPoint("CENTER")
    s.mark = tex(p, Nav.ART.diamond, "ARTWORK")
    s.mark:SetSize(26, 26)
    s.mark:SetPoint("CENTER")
    s.textAt = { "TOP", s.mark, "BOTTOM", 0, -5 }
    s.pulse = s.mark
    return s
end

function builders.pillar(p)
    local s = {}
    s.light = tex(p, Nav.ART.glow, "BACKGROUND", "ADD")
    s.light:SetSize(46, 22)
    s.light:SetPoint("CENTER")
    s.beam = tex(p, Nav.ART.beam, "ARTWORK", "ADD")
    s.beam:SetSize(22, Nav.PILLAR_H)
    s.beam:SetPoint("BOTTOM", p, "CENTER", 0, -4)
    s.mark = tex(p, Nav.ART.diamond, "OVERLAY")
    s.mark:SetSize(12, 12)
    s.mark:SetPoint("CENTER")
    s.textAt = { "TOP", s.mark, "BOTTOM", 0, -4 }
    s.pulse = s.light
    return s
end

function builders.minimal(p)
    local s = {}
    s.mark = tex(p, Nav.ART.chevron, "ARTWORK")
    s.mark:SetSize(14, 14)
    s.mark:SetPoint("CENTER")
    s.textAt = { "TOP", s.mark, "BOTTOM", 0, -2 }
    s.pulse = s.mark
    return s
end

local function style()
    local n = db()
    local name = n and n.style
    return builders[name] and name or "beacon"
end

-- Paints a style in the accent, read now so it follows the player's choice.
local function paint(s)
    local r, g, b = Style.Accent()
    if s.light then s.light:SetVertexColor(r, g, b, 0.55) end
    if s.mark then Style.PaintAccent(s.mark, 1, "VERTICAL") end
    if s.beam then s.beam:SetVertexColor(r, g, b, 0.9) end
end

local function build()
    if f then return f end
    f = CreateFrame("Frame", "DaylightUIQuestMarker", UIParent)
    f:SetSize(40, 40)
    -- Same strata as the game's own marker: below every window.
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f:SetAlpha(0)
    f:Hide()
    f.looks = {}
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetAllPoints()
    f.dist = Style.Text(f.body, Style.SIZE.small, "CENTER")
    Style.InkText(f.dist, "VALUE")
    f.arrow = tex(f, Nav.ART.arrow, "OVERLAY")
    f.arrow:SetSize(18, 18)
    f.arrow:Hide()
    return f
end

-- Shows the picked style and hides the others.
local function useLook()
    local name = style()
    for k, s in pairs(f.looks) do
        if k ~= name then s.frame:Hide() end
    end
    local s = f.looks[name]
    if not s then
        local holder = CreateFrame("Frame", nil, f.body)
        holder:SetAllPoints()
        s = builders[name](holder)
        s.frame = holder
        f.looks[name] = s
    end
    s.frame:Show()
    paint(s)
    f.dist:ClearAllPoints()
    f.dist:SetPoint(unpack(s.textAt))
    f.look = s
    f.sizeShown = nil   -- the size applies to the new style next frame
    local n = db()
    f:SetScale(((n and n.scale) or 1) * DUI.Movers.Scale())
    return s
end

-- Where the client's frame is, in this frame's units (nil = nowhere).
local function navSpot(nav)
    local ok, x, y = pcall(nav.GetCenter, nav)
    if not ok or type(x) ~= "number" or type(y) ~= "number" or secret(x) then return nil end
    local k = nav:GetEffectiveScale() / f:GetEffectiveScale()
    return x * k, y * k
end

-- Edge position for an off-screen target: where the line from the screen center
-- to it meets the ellipse (SuperTrackedFrameMixin:ClampElliptical).
local function edge(x, y)
    local w, h = UIParent:GetWidth() / f:GetScale(), UIParent:GetHeight() / f:GetScale()
    local cx, cy = w / 2, h / 2
    local a, b = w * Nav.EDGE_X, h * Nav.EDGE_Y
    local px, py = x - cx, y - cy
    local d = math.sqrt(a * a * py * py + b * b * px * px)
    if d == 0 then return x, y, 0 end
    local k = a * b / d
    -- Arrow rotation: up is 0, measured the same way as SetRotation.
    return cx + px * k, cy + py * k, math.atan2(-px, py)
end

local function yards()
    local d = navCall("GetDistance")
    if type(d) ~= "number" or secret(d) then return nil end
    return d
end

local function distText(d)
    if not d then return "" end
    local n = math.floor(d + 0.5)
    local s = n < 1000 and tostring(n) or AbbreviateNumbers(n)
    local fmt = _G.IN_GAME_NAVIGATION_RANGE
    return type(fmt) == "string" and string.format(fmt, s) or s
end

local function targetAlpha(clamped, d)
    if navCall("HasValidScreenPosition") ~= true then return 0 end
    local state = navCall("GetTargetState")
    local a = (type(state) == "number" and not secret(state)) and Nav.STATE_ALPHA[state] or 1
    if a > 0 and clamped then a = 1 end
    -- Arrived: fade out over the last few yards (on the edge too, since an arrow
    -- pointing back at the player's feet doesn't help).
    if d and d < Nav.NEAR then a = a * math.max(0, (d - Nav.GONE) / (Nav.NEAR - Nav.GONE)) end
    local n = db()
    if n and n.fightFade and InCombatLockdown() then a = math.min(a, Nav.FIGHT_ALPHA) end
    return a
end

-- Quest area check. A hidden quest area frame (the client's QuestPOIFrame, the
-- kind the map uses to draw quest areas; the journal makes one too) draws the
-- quest's area for the current map and is asked whether the player's spot is in
-- it (UpdateMouseOverTooltip(x, y) returns the quest whose area holds that spot).
-- Never shown. A client that can't create one never reports "in".
local zoneFrame, zoneKey, zoneWait = nil, nil, 0
local inZone = false

local function zoneQuest()
    if ns.Route and ns.Route.quest then return ns.Route.quest end
    local ST = _G.C_SuperTrack
    local ok, id = pcall(ST and ST.GetSuperTrackedQuestID)
    return ok and type(id) == "number" and id > 0 and id or nil
end

-- Near a spot the quest still needs (QuestieDB's, the map's dots). Within THERE
-- yards counts as there, until THERE_OUT (so it doesn't flicker at the edge). The
-- game's area check never reported "in" when tested in game.
local function nearSpots(q, map, x, y)
    local R = ns.Route
    if not (R and R.Needed and R.Yards) then return false end
    local reach = inZone and Nav.THERE_OUT or Nav.THERE
    for _, s in ipairs(R.Needed(q)) do
        if s.map == map and R.Yards(map, x, y, s.x, s.y) < reach then return true end
    end
    return false
end

local function checkZone()
    local q = zoneQuest()
    local C = _G.C_Map
    if not q or type(C) ~= "table" then return false end
    local ok, map = pcall(C.GetBestMapForUnit, "player")
    if not ok or type(map) ~= "number" then return false end
    local pos
    ok, pos = pcall(C.GetPlayerMapPosition, map, "player")
    if not ok or type(pos) ~= "table" then return false end
    local x, y = pos.x, pos.y
    if type(pos.GetXY) == "function" then x, y = pos:GetXY() end
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    if nearSpots(q, map, x, y) then return true end
    if Nav.noZone then return false end
    if not zoneFrame then
        local made, b = pcall(CreateFrame, "QuestPOIFrame", nil, UIParent)
        if not made or type(b) ~= "table" then Nav.noZone = true; return false end
        b:SetSize(100, 100)
        b:SetPoint("CENTER")
        b:SetAlpha(0)
        b:EnableMouse(false)
        zoneFrame = b
    end
    local key = map .. ":" .. q
    if key ~= zoneKey then
        pcall(zoneFrame.SetMapID, zoneFrame, map)
        pcall(zoneFrame.DrawNone, zoneFrame)
        pcall(zoneFrame.DrawBlob, zoneFrame, q, true)
        zoneKey = key
    end
    local asked, id = pcall(zoneFrame.UpdateMouseOverTooltip, zoneFrame, x, y)
    return asked and id == q
end

-- The quest's area changes as objectives finish, so redraw it next time.
function Nav.ForgetZone() zoneKey = nil end

-- Eases toward a value; snaps with motion off.
local function ease(from, to, dt, dur)
    if not Motion.On() then return to end
    return from + (to - from) * math.min(1, dt / dur)
end

-- Breadcrumbs: a full-screen frame below every window.
local function buildTrail()
    if trail then return trail end
    trail = CreateFrame("Frame", nil, UIParent)
    trail:SetAllPoints(UIParent)
    trail:SetFrameStrata("BACKGROUND")
    trail:EnableMouse(false)
    trail:SetAlpha(0)
    trail.alpha = 0
    trail.phase = 0
    trail.crumbs = {}
    for i = 1, Nav.CRUMBS do
        trail.crumbs[i] = tex(trail, Nav.ART.crumb, "ARTWORK")
    end
    return trail
end

-- Accent color at a point along the path: the gradient pair from the player
-- (dark end) to the marker (light end), otherwise the single color.
local function crumbColor(k)
    local a, b = Style.AccentPair()
    if a then
        return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
    end
    return Style.Accent()
end

-- Lays the crumbs from the feet position to (tx, ty) in UIParent units, drifting
-- forward. Nearer the marker they get smaller and closer together, like steps
-- receding on the ground.
local function layTrail(dt, tx, ty)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local sx, sy = w * Nav.FEET_X, h * Nav.FEET_Y
    if Motion.On() then trail.phase = (trail.phase + dt * Nav.DRIFT) % 1 end
    local n = Nav.CRUMBS
    for i, c in ipairs(trail.crumbs) do
        local u = ((i - 1) + trail.phase) / n
        local k = 1 - (1 - u) ^ 1.8
        local size = Nav.CRUMB_NEAR + (Nav.CRUMB_FAR - Nav.CRUMB_NEAR) * k
        c:SetSize(size, size * Nav.CRUMB_FLAT)
        c:ClearAllPoints()
        c:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx + (tx - sx) * k, sy + (ty - sy) * k)
        -- Fade in just ahead of the feet, fade out before the marker.
        local a = math.min(1, math.max(0, (u - 0.06) / 0.12)) * math.min(1, (1 - u) / 0.15)
        local r, g, b = crumbColor(k)
        c:SetVertexColor(r, g, b, a * 0.9)
    end
end

local function onUpdate(_, dt)
    local nav = api("GetFrame") and navCall("GetFrame")
    if type(nav) ~= "table" then
        -- Nothing tracked: fade out, then stop until the client creates a frame.
        cur.alpha = ease(cur.alpha, 0, dt, Motion.FAST)
        f:SetAlpha(cur.alpha)
        if trail then trail:SetAlpha(trail.alpha * cur.alpha) end
        if cur.alpha < 0.01 then
            f:SetAlpha(0)
            cur.alpha, cur.x, cur.edge = 0, nil, nil
            f:SetScript("OnUpdate", nil)
        end
        return
    end
    local x, y = navSpot(nav)
    if not x then return end
    local clamped = navCall("WasClampedToScreen") == true
    local turn
    if clamped then x, y, turn = edge(x, y) end

    -- New target: glide from the previous spot (NORMAL).
    if glide and cur.x then
        glide.t = glide.t + dt
        local k = Motion.On() and math.min(1, glide.t / Motion.NORMAL) or 1
        k = 1 - (1 - k) * (1 - k)
        x, y = glide.fx + (x - glide.fx) * k, glide.fy + (y - glide.fy) * k
        if k >= 1 then glide = nil end
    end
    cur.x, cur.y = x, y
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

    -- Marker and edge arrow crossfade (FAST) as the spot leaves the screen edge and
    -- comes back, which happens often while turning.
    cur.edge = ease(cur.edge or (clamped and 1 or 0), clamped and 1 or 0, dt, Motion.FAST)
    if cur.edge > 0.99 then cur.edge = 1 elseif cur.edge < 0.01 then cur.edge = 0 end
    f.arrow:SetShown(cur.edge > 0)
    f.arrow:SetAlpha(cur.edge)
    f.body:SetShown(cur.edge < 1)
    f.body:SetAlpha(1 - cur.edge)
    if clamped then
        f.arrow:ClearAllPoints()
        f.arrow:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.arrow:SetRotation(turn)
    end

    local d = yards()
    -- Size by distance, eased since a new target's distance jumps.
    local size = d and math.min(Nav.SIZE_MAX, math.max(Nav.SIZE_MIN, Nav.SIZE_REF / math.max(d, 1))) or 1
    cur.size = ease(cur.size or size, size, dt, Motion.NORMAL)
    local look = f.look and f.look.frame
    if look and math.abs(cur.size - (f.sizeShown or 0)) > 0.005 then
        f.sizeShown = cur.size
        look:SetScale(cur.size)
    end

    local n = db()
    if n and n.distance ~= false and not clamped then
        local text = distText(d)
        if f.distShown ~= text then
            f.distShown = text
            f.dist:SetText(text)
        end
    elseif f.distShown ~= "" then
        f.distShown = ""
        f.dist:SetText("")
    end

    -- Inside the quest's area everything fades out slowly, and comes back the same
    -- way when the player walks out.
    zoneWait = zoneWait - dt
    if zoneWait <= 0 then
        zoneWait = Nav.ZONE_EVERY
        inZone = checkZone()
    end
    local want = inZone and 0 or targetAlpha(clamped, d)
    cur.alpha = ease(cur.alpha, want, dt, inZone and Motion.SLOW or Motion.FAST)
    f:SetAlpha(cur.alpha)

    -- Breadcrumbs only toward an on-screen marker in front of the player.
    if trail then
        local tx, ty = x * f:GetScale(), y * f:GetScale()
        local show = n and n.trail == true and not clamped and not inZone
            and (not d or d > Nav.NEAR) and ty > UIParent:GetHeight() * Nav.FEET_Y
        trail.alpha = ease(trail.alpha, show and 1 or 0, dt, Motion.SLOW)
        trail:SetAlpha(trail.alpha * cur.alpha)
        if trail.alpha > 0.01 then layTrail(dt, tx, ty) end
    end
end

-- Starts a glide from the current spot.
function Nav.Glide()
    if cur.x then glide = { fx = cur.x, fy = cur.y, t = 0 } end
end

-- Arrival pulse.
function Nav.Arrive()
    if not f or not f:IsShown() or not f.look then return end
    Motion.Bump(f.look.pulse, 1.5, Motion.SLOW)
end

-- Applies on/off, style and scale from the settings.
function Nav.Refresh()
    if not mod then return end
    if not enabled() then
        if f then
            f:SetScript("OnUpdate", nil)
            f:Hide()
        end
        if trail then trail:Hide() end
        if gameHidden then hideGame(false) end
        return
    end
    build()
    useLook()
    buildTrail():Show()
    hideGame(true)
    f:SetScript("OnUpdate", onUpdate)
    f:Show()
end

function Nav.OnStyleChanged()
    if f and f.look then
        paint(f.look)
        Style.InkText(f.dist, "VALUE")
        local n = db()
        f:SetScale(((n and n.scale) or 1) * DUI.Movers.Scale())
    end
end

function Nav.Enable(m)
    mod = m
    if not listening then
        listening = true
        DUI.RegisterEvent("SUPER_TRACKING_CHANGED", function()
            if enabled() then Nav.Glide() end
        end)
        -- The client created a frame for a new target: run the driver again.
        DUI.RegisterEvent("NAVIGATION_FRAME_CREATED", function()
            if enabled() and f then f:SetScript("OnUpdate", onUpdate) end
        end)
        DUI.RegisterEvent("NAVIGATION_DESTINATION_REACHED", function()
            if enabled() then Nav.Arrive() end
        end)
        DUI.RegisterEvent("QUEST_LOG_UPDATE", Nav.ForgetZone)
        DUI.RegisterEvent("SUPER_TRACKING_CHANGED", Nav.ForgetZone)
        -- The game's marker loads with its own addon; hide it once it's there.
        DUI.RegisterEvent("ADDON_LOADED", function(_, name)
            if name == "Blizzard_QuestNavigation" and enabled() then hideGame(true) end
        end)
    end
    Nav.Refresh()
end

-- for the tests
Nav.Frame = function() return f end
Nav.Trail = function() return trail end
Nav.InZone = function() return inZone end
Nav.ZoneFrame = function() return zoneFrame end
