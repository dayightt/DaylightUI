-- Flight timer: while on a flight path, a banner floats near the top of the
-- screen with the destination, the route as a line with a dot for each stop,
-- a light gliding along it and the time left.
--
-- The time: your own last flight of that route when you have one (saved per
-- account), else the game's own path lengths (FlightPaths.lua) added up over
-- the stops the flight master's map says the flight makes. A route neither
-- covers is timed on the way and learned on landing.
-- The destination comes from a post-hook on the global TakeTaxiNode.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local Flight = {
    WIDTH = 320,
    NAME = 22,          -- the destination's size: display text, like the level-up's
    LINE = 3,           -- the route line's thickness
    DOT = 7,            -- a stop on the line
    SPARK = 26,         -- the light at the front of the fill
    FLARE = 90,         -- the flash over the name on landing
    RISE = 10,          -- px it glides down as it comes in
    LANDED = 1.4,       -- seconds "Arrived" holds before it leaves
    TICK = 0.1,         -- seconds between updates while flying
    START_WAIT = 10,    -- seconds after picking a flight point to wait for take-off
    MIN_LEARN = 5,      -- a shorter "flight" is a hiccup, not a route: not learned
    RESUME_MAX = 3600,  -- a saved flight older than this is stale (after a /reload)
    SOON = 10,          -- seconds left under which the time turns amber
    GLOW = DUI.MEDIA .. "char-glow.png",
    CIRCLE = DUI.MEDIA .. "shape-circle.png",
    MOVER = "qol.flight",
    GRADIENT = "TIMER_FLIGHT",
    TEST_PART = "flight",
    -- The test-mode sample.
    SAMPLE = { name = L["Stormwind"], from = L["Ironforge"], total = 102, elapsed = 41, stops = { 0.55 } },
}
ns.Flight = Flight
ns.features[#ns.features + 1] = Flight

-- Its color pair, on General > Gradients with the breath bar's.
if DUI.Gradients then
    DUI.Gradients.Register(Flight.GRADIENT, { group = "timer", label = "Flight",
        lo = { 0.40, 0.30, 0.55 }, hi = { 1.00, 0.78, 0.55 } })
end

local mod, wired, holder
local nodes, here = {}, nil   -- the open taxi map's points: slot -> { name, id }; where you are
local pending                  -- { key, back, name, from, guess, stops, at }: picked, not in the air yet
local flight                   -- { key, name, from, start, total?, stops, early? }: in the air
local vis = 0                  -- 0 hidden .. 1 fully in
local landing = 0              -- each landing's id: a new flight stops the old one's timer

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.flightTimer == true end

local function onTaxi()
    return type(UnitOnTaxi) == "function" and UnitOnTaxi("player") == true
end

-- Learned route times (seconds), per account.
function Flight.Routes()
    local root = DUI.DB.Root()
    if type(root.flightTimes) ~= "table" then root.flightTimes = {} end
    return root.flightTimes
end

-- The flight in the air, kept per character so a /reload mid-flight resumes it.
local function saved(v)
    local c = DUI.DB.Character()
    if v == nil then return c.flight end
    c.flight = v ~= false and v or nil
end

-- "Stormwind, Elwynn" -> "Stormwind".
function Flight.ShortName(name)
    if type(name) ~= "string" then return "" end
    return (name:match("^([^,]+)") or name)
end

-- A route's key: the two points' ids when the client gives them (the same
-- in every language), else their names.
function Flight.Key(from, to)
    if not (from and to) then return nil end
    local a = from.id or from.name
    local b = to.id or to.name
    if a == nil or b == nil then return nil end
    return tostring(a) .. ">" .. tostring(b)
end

function Flight.FormatTime(s)
    return DUI.FormatClock(math.max(0, math.floor((s or 0) + 0.5)))
end

-- One leg's time from the game's path table; a leg listed only the other way
-- flies the same line back.
local function leg(a, b)
    local P = ns.FlightPaths
    if not (P and a and b) then return nil end
    return P[a .. ">" .. b] or P[b .. ">" .. a]
end

-- The legs the game will fly to a slot, as node ids: the flight master's map
-- gives each hop's two slots. Nil when the map doesn't say.
function Flight.Hops(slot)
    if type(GetNumRoutes) ~= "function" or type(TaxiGetNodeSlot) ~= "function" then return nil end
    local n = GetNumRoutes(slot)
    if type(n) ~= "number" or n < 1 then return nil end
    local hops = {}
    for i = 1, n do
        local a = nodes[TaxiGetNodeSlot(slot, i, true)]
        local b = nodes[TaxiGetNodeSlot(slot, i, false)]
        if not (a and a.id and b and b.id) then return nil end
        hops[i] = { a.id, b.id }
    end
    return hops
end

-- The guessed time over those legs, and where each stop falls along the way
-- (0..1). Without the legs, the straight path between the two points.
function Flight.Guess(from, to, hops)
    if not hops then
        if from and to and from.id and to.id then hops = { { from.id, to.id } } else return nil end
    end
    local total, at = 0, {}
    for i, h in ipairs(hops) do
        local s = leg(h[1], h[2])
        if not s then return nil end
        total = total + s
        if i < #hops then at[i] = total end
    end
    if total <= 0 then return nil end
    for i = 1, #at do at[i] = at[i] / total end
    return total, at
end

-- ---------------------------------------------------------------------
-- The banner
-- ---------------------------------------------------------------------

local function dot(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Flight.CIRCLE)
    t:SetSize(size, size)
    return t
end

-- A long flight moves the line well under a pixel a frame: snapped to the
-- pixel grid, the fill, its gradient layer, its edge masks and the light
-- would hop a pixel at a time. Done after every paint, which can make new layers.
local function free(t)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    if t.GetNumMaskTextures then
        for i = 1, t:GetNumMaskTextures() do
            local m = t:GetMaskTexture(i)
            if m then free(m) end
        end
    end
end

local function unsnap(f)
    for _, r in ipairs({ f.bar:GetRegions() }) do free(r) end
    free(f.bar:GetStatusBarTexture())
    free(f.spark)
    free(f.head)
end

local function paint()
    if not holder then return end
    local G = DUI.Gradients
    if G then G.Paint(holder.f.bar, G.Has(Flight.GRADIENT) and Flight.GRADIENT or "FALLBACK") end
    local f = holder.f
    unsnap(f)
    f.spark:SetVertexColor(Style.SplashAt(0.85))
    f.flare:SetVertexColor(Style.SplashAt(0.85))
    Style.PaintAccentText(f.label, Style.Upper(L["Flying to"]))
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "DaylightUIFlightTimer", UIParent)
    holder:SetSize(Flight.WIDTH, 80)
    holder:EnableMouse(false)
    holder:Hide()
    local f = CreateFrame("Frame", nil, holder)
    holder.f = f
    f:SetSize(Flight.WIDTH, 80)
    f:SetPoint("TOP", holder, "TOP", 0, 0)

    f.label = Style.Text(f, Style.SIZE.small, "CENTER")
    f.label:SetPoint("TOP", f, "TOP", 0, 0)
    f.name = Style.Text(f, Flight.NAME, "CENTER")
    f.name:SetPoint("TOP", f.label, "BOTTOM", 0, -3)
    f.name:SetWidth(Flight.WIDTH)
    f.name:SetWordWrap(false)
    Style.InkText(f.name, "TITLE")

    f.flare = f:CreateTexture(nil, "BACKGROUND")
    f.flare:SetTexture(Flight.GLOW)
    f.flare:SetSize(Flight.FLARE * 2.4, Flight.FLARE)
    f.flare:SetPoint("CENTER", f.name, "CENTER", 0, 0)
    f.flare:SetBlendMode("ADD")
    f.flare:Hide()

    f.bar = Style.Bar(f)
    f.bar:SetHeight(Flight.LINE)
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(Flight.NAME + 30))
    f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(Flight.NAME + 30))

    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints(f)
    over:SetFrameLevel(f.bar:GetFrameLevel() + 3)
    f.over = over
    f.start = dot(over, Flight.DOT)
    f.start:SetPoint("CENTER", f.bar, "LEFT", 0, 0)
    f.finish = dot(over, Flight.DOT + 3)
    f.finish:SetPoint("CENTER", f.bar, "RIGHT", 0, 0)
    f.stops = {}
    f.spark = over:CreateTexture(nil, "ARTWORK")
    f.spark:SetTexture(Flight.GLOW)
    f.spark:SetBlendMode("ADD")
    f.spark:SetSize(Flight.SPARK, Flight.SPARK)
    f.spark:SetPoint("CENTER", f.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    f.head = dot(over, Flight.DOT)
    f.head:SetPoint("CENTER", f.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    f.head:SetVertexColor(1, 1, 1, 1)

    f.from = Style.Text(f, Style.SIZE.small, "LEFT")
    f.from:SetPoint("TOPLEFT", f.bar, "BOTTOMLEFT", 0, -8)
    f.from:SetPoint("RIGHT", f, "CENTER", -8, 0)
    f.from:SetWordWrap(false)
    Style.InkText(f.from, "LABEL")
    f.time = Style.Text(f, Style.SIZE.head, "RIGHT")
    f.time:SetPoint("TOPRIGHT", f.bar, "BOTTOMRIGHT", 0, -6)
    f.time.tone = nil
    paint()
    DUI.Movers.Register(holder, Flight.MOVER, "Flight timer", { "TOP", nil, "TOP", 0, -88 },
        { active = enabled })
end

-- Text only on a change: this runs ten times a second in flight.
local function setText(fs, text)
    if fs.flightText == text then return end
    fs.flightText = text
    fs:SetText(text)
end

local function tone(fs, role)
    if fs.tone == role then return end
    fs.tone = role
    Style.InkText(fs, role)
end

-- A dot for each stop between, lit once you're past it.
local function placeStops(stops, p)
    local f = holder.f
    stops = stops or {}
    for i = 1, math.max(#stops, #f.stops) do
        local at = stops[i]
        local d = f.stops[i]
        if at then
            if not d then d = dot(f.over, Flight.DOT - 1); f.stops[i] = d end
            d:ClearAllPoints()
            -- The fixed width, not GetWidth: the line may not be laid out yet on its first show.
            d:SetPoint("CENTER", f.bar, "LEFT", at * Flight.WIDTH, 0)
            d:Show()
        elseif d then
            d:Hide()
        end
    end
    local lr, lg, lb = Style.SplashAt(0.85)
    local dim = Style.INK.LABEL
    local function light(t, passed)
        if passed then t:SetVertexColor(lr, lg, lb, 1) else t:SetVertexColor(dim[1], dim[2], dim[3], 0.9) end
    end
    light(f.start, true)
    for i, at in ipairs(stops) do light(f.stops[i], p >= at) end
    light(f.finish, p >= 1)
end

-- What the banner shows: where to, from where, how far along, the time.
local function show(name, from, elapsed, total, stops)
    local f = holder.f
    setText(f.name, Flight.ShortName(name))
    setText(f.from, Flight.ShortName(from))
    local p
    if total and total > 0 then
        p = math.min(1, elapsed / total)
        local left = total - elapsed
        setText(f.time, left > 0 and Flight.FormatTime(left) or L["Almost there"])
        tone(f.time, (left > 0 and left < Flight.SOON) and "WARN" or "pop")
        f.spark:Show()
        f.head:Show()
    else
        -- No time to count down from: the clock counts up, the line waits empty.
        p = 0
        setText(f.time, Flight.FormatTime(elapsed))
        tone(f.time, "VALUE")
        f.spark:Hide()
        f.head:Hide()
    end
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(p)
    placeStops(stops, p)
end

-- The glide: alpha and a short drop from above, from wherever it is.
local function place(p)
    vis = p
    holder.f:SetAlpha(p)
    holder.f:ClearAllPoints()
    holder.f:SetPoint("TOP", holder, "TOP", 0, Flight.RISE * (1 - p))
end

local function glide(on)
    local goal = on and 1 or 0
    if on and not holder:IsShown() then
        holder:Show()
        place(0)
    end
    if not holder:IsShown() then return end
    Motion.Tween("qol:flight", vis, goal, on and Motion.SLOW or Motion.CLOSE, place, function()
        if not on then holder:Hide() end
    end)
end

local function sampleWanted()
    if DUI.testMode and DUI.TestPartShown(Flight.TEST_PART) then return true end
    return DUI.Movers and DUI.Movers.unlocked == true
end

-- Shows or hides the banner for what's going on now, and fills it in.
function Flight.Update()
    if not enabled() then
        if holder and holder:IsShown() then glide(false) end
        return
    end
    build()
    if flight then
        landing = landing + 1
        show(flight.name, flight.from, GetTime() - flight.start, flight.total, flight.stops)
    elseif landing < 0 then
        return  -- "Arrived" is up; it leaves by itself
    elseif sampleWanted() then
        local s = Flight.SAMPLE
        show(s.name, s.from, s.elapsed, s.total, s.stops)
    else
        glide(false)
        return
    end
    glide(true)
end

-- Landed: the line fills, the name flares, "Arrived", then it leaves.
local function arrive()
    if not (holder and holder:IsShown()) then return Flight.Update() end
    local f = holder.f
    f.bar:SetValue(1)
    placeStops(nil, 1)
    for _, d in ipairs(f.stops) do d:Hide() end
    setText(f.time, L["Arrived"])
    tone(f.time, "GOOD")
    Motion.Flash(f.flare, Motion.SLOW * 2)
    landing = -1
    C_Timer.After(Flight.LANDED, function()
        if landing ~= -1 then return end
        landing = 0
        Flight.Update()
    end)
end

-- ---------------------------------------------------------------------
-- Following a flight
-- ---------------------------------------------------------------------

local driver, acc = nil, 0

-- Every frame in the air, the line alone moves on; the text waits for the tick.
local function moveLine()
    if not (flight and flight.total and flight.total > 0 and holder and holder:IsShown()) then return end
    holder.f.bar:SetValue(math.min(1, (GetTime() - flight.start) / flight.total))
end

local function stopDriver() if driver then driver:Hide() end end

local function land()
    local f = flight
    flight = nil
    saved(false)
    stopDriver()
    local took = GetTime() - f.start
    if f.key and not f.early and took >= Flight.MIN_LEARN then
        Flight.Routes()[f.key] = math.floor(took + 0.5)
    end
    if f.early then Flight.Update() else arrive() end
end

-- Your own last flight of the route first; then the game's paths; then the
-- way back's flight, close enough to count down from.
local function knownTime(key, back, guess)
    local routes = Flight.Routes()
    return (key and routes[key]) or guess or (back and routes[back]) or nil
end

local function remember()
    saved({ key = flight.key, back = flight.back, name = flight.name, from = flight.from,
            guess = flight.guess, stops = flight.stops, early = flight.early or nil,
            wall = time() - (GetTime() - flight.start) })
end

local function takeOff(p, start)
    flight = { key = p.key, back = p.back, name = p.name, from = p.from, guess = p.guess,
               stops = p.stops, start = start or GetTime(), early = p.early }
    flight.total = knownTime(p.key, p.back, p.guess)
    pending = nil
    remember()
    Flight.Update()
end

function Flight.Tick()
    if flight then
        if not onTaxi() then land() return end
        if holder and holder:IsShown() then
            show(flight.name, flight.from, GetTime() - flight.start, flight.total, flight.stops)
        end
    elseif pending then
        if onTaxi() then takeOff(pending)
        elseif GetTime() - pending.at > Flight.START_WAIT then pending = nil stopDriver() end
    else
        stopDriver()
    end
end

-- One frame in the air: the line every frame, the rest on the tick.
function Flight.Step(dt)
    moveLine()
    acc = acc + (dt or 0)
    if acc < Flight.TICK then return end
    acc = 0
    Flight.Tick()
end

-- A parentless frame, so it keeps watching with the interface hidden (Alt-Z):
-- the landing must be seen on time or the learned time would be too long.
local function startDriver()
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", function(_, dt) Flight.Step(dt) end)
    end
    acc = 0
    driver:Show()
end

-- The open taxi map's points. The client's flight point list first (ids),
-- then the plain functions for anything it didn't give.
function Flight.ReadMap()
    nodes, here = {}, nil
    local C = C_TaxiMap
    local mapID = type(GetTaxiMapID) == "function" and GetTaxiMapID() or nil
    if C and type(C.GetAllTaxiNodes) == "function" and type(mapID) == "number" then
        local ok, list = pcall(C.GetAllTaxiNodes, mapID)
        if ok and type(list) == "table" then
            local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0
            for _, info in ipairs(list) do
                if type(info) == "table" and type(info.slotIndex) == "number" then
                    local n = { name = info.name, id = info.nodeID }
                    nodes[info.slotIndex] = n
                    if info.state == current then here = n end
                end
            end
        end
    end
    if type(NumTaxiNodes) == "function" and type(TaxiNodeName) == "function" then
        for i = 1, NumTaxiNodes() or 0 do
            local n = nodes[i] or {}
            nodes[i] = n
            n.name = n.name or TaxiNodeName(i)
            if not here and type(TaxiNodeGetType) == "function" and TaxiNodeGetType(i) == "CURRENT" then here = n end
        end
    end
end

-- The player picked a flight point (after the game took it).
function Flight.OnTake(slot)
    if not enabled() or type(slot) ~= "number" then return end
    -- The map can open before the client has its points: read it again now,
    -- while it's still open, or the route would have no start and never be learned.
    if not (here and nodes[slot]) then Flight.ReadMap() end
    local to = nodes[slot]
    if not (to and to.name) and type(TaxiNodeName) == "function" then
        to = { name = TaxiNodeName(slot) }
    end
    if not (to and type(to.name) == "string" and to.name ~= "") then return end
    local guess, stops = Flight.Guess(here, to, Flight.Hops(slot))
    pending = { key = Flight.Key(here, to), back = Flight.Key(to, here), name = to.name,
                from = here and here.name or nil, guess = guess, stops = stops, at = GetTime() }
    startDriver()
end

-- After a /reload (or a login) mid-flight: carry on from the saved take-off.
-- After a login the time logged out counted as flying, so that flight isn't learned.
function Flight.Resume(login)
    if flight or not enabled() then return end
    local s = saved()
    if type(s) ~= "table" then return end
    local ago = type(s.wall) == "number" and time() - s.wall or nil
    if not onTaxi() or not ago or ago < 0 or ago > Flight.RESUME_MAX then
        saved(false)
        return
    end
    takeOff({ key = s.key, back = s.back, name = s.name, from = s.from, guess = s.guess,
              stops = type(s.stops) == "table" and s.stops or nil, early = s.early or login or nil },
            GetTime() - ago)
    startDriver()
end

-- ---------------------------------------------------------------------
-- Feature hooks
-- ---------------------------------------------------------------------

function Flight.Enable(m)
    mod = m
    if not wired then
        wired = true
        if type(TakeTaxiNode) == "function" then
            hooksecurefunc("TakeTaxiNode", function(slot) Flight.OnTake(slot) end)
        end
        -- Asking to land early: that flight's time isn't the route's.
        if type(TaxiRequestEarlyLanding) == "function" then
            hooksecurefunc("TaxiRequestEarlyLanding", function() if flight then flight.early = true remember() end end)
        end
        DUI.RegisterEvent("TAXIMAP_OPENED", function() if enabled() then Flight.ReadMap() end end)
        DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin)
            -- Enable resumed it already, not knowing yet whether this is a login.
            if isLogin == true and flight and not flight.early then
                flight.early = true
                remember()
            end
            Flight.Resume(isLogin == true)
        end)
        DUI.RegisterTestPart(Flight.TEST_PART, "Flight timer", 95, enabled)
        DUI.On("TestModeChanged", Flight.Update)
        DUI.On("TestPartChanged", function(key) if key == Flight.TEST_PART then Flight.Update() end end)
        DUI.On("UnlockChanged", Flight.Update)
        DUI.On("StyleChanged", paint)
        DUI.On("SettingChanged", function(scope) if scope == "general" then paint() end end)
    end
    if enabled() then build() end
    Flight.Resume()
end

function Flight.Refresh(m)
    mod = m
    if not enabled() then
        pending = nil
        if flight then flight = nil stopDriver() end
        landing = 0
    else
        Flight.Resume()
    end
    Flight.Update()
end
