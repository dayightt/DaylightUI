-- Flight timer: while on a flight path, a banner floats near the top of the
-- screen with the destination, the route as a line with a dot for each stop,
-- a light gliding along it and the time left.
--
-- The time: your own last flight of that route when you have one (saved per
-- account), else the game's own path lengths (FlightPaths.lua) added up over
-- the stops the flight master's map says the flight makes. A route neither
-- covers is timed on the way and learned on landing.
-- The destination comes from a post-hook on the global TakeTaxiNode, or for a
-- flight started by talking to the flight master, from Flight.TALKED.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local Flight = {
    WIDTH = 320,
    NAME = 22,          -- the destination's size: display text, like the level-up's
    LINE = 3,           -- the route line's thickness
    DOT = 7,            -- a stop on the line
    STOP_HIT = 16,      -- the room around a stop's dot that names it on hover
    SPARK = 26,         -- the light at the front of the fill
    HEIGHT = 74,        -- from the top of "Flying to" to under the time
    PAD_X = 18,         -- room inside the box at the sides
    PAD_Y = 12,         -- and at the top and bottom
    RISE = 10,          -- px it glides down as it comes in
    -- The welcome on landing.
    WELCOME_Y = -250,   -- its middle from the screen's top, under the flight timer
    WELCOME_NAME = 30,
    WELCOME_W = 380,    -- its line at full spread
    WELCOME_RISE = 18,  -- px it slides up as it comes in
    WELCOME_HOLD = 2.6, -- seconds it stays
    WELCOME_DRIFT = 8,  -- px it rises as it fades
    TICK = 0.1,         -- seconds between updates while flying
    START_WAIT = 10,    -- seconds after picking a flight point to wait for take-off
    MIN_LEARN = 5,      -- a shorter "flight" is a hiccup, not a route: not learned
    RESUME_MAX = 3600,  -- a saved flight older than this is stale (after a /reload)
    SOON = 10,          -- seconds left under which the time turns amber
    LEAVE_INSET = 5,    -- the land-early button's room from the box's top right corner
    GLOW = DUI.MEDIA .. "char-glow.png",
    CIRCLE = DUI.MEDIA .. "shape-circle.png",
    MOVER = "qol.flight",
    WELCOME_MOVER = "qol.welcome",
    FONT = "qol.flight.font",   -- its font's Media slot (flightFont)
    GRADIENT = "TIMER_FLIGHT",
    TEST_PART = "flight",
    -- The test-mode sample.
    SAMPLE = { name = L["Stormwind"], from = L["Ironforge"], total = 102, elapsed = 41, stops = { 0.55 },
               names = { L["Thelsamar"] } },
    -- Flights a flight master starts from his words instead of his map, so the
    -- game never calls TakeTaxiNode: the druids' flights out of Nighthaven.
    -- By the map you leave from, then your faction: the two flight points'
    -- node ids (as in FlightPaths.lua) and their names.
    TALKED = {
        [1450] = {   -- Moonglade
            Horde = { from = 63, to = 22, fromName = L["Nighthaven, Moonglade"], name = L["Thunder Bluff, Mulgore"] },
            Alliance = { from = 62, to = 27, fromName = L["Nighthaven, Moonglade"],
                         name = L["Rut'theran Village, Teldrassil"] },
        },
    },
}
ns.Flight = Flight
ns.features[#ns.features + 1] = Flight

-- Its color pair, on General > Gradients with the breath bar's.
if DUI.Gradients then
    DUI.Gradients.Register(Flight.GRADIENT, { group = "timer", label = "Flight",
        lo = { 0.40, 0.30, 0.55 }, hi = { 1.00, 0.78, 0.55 } })
end

DUI.Media.RegisterSlot(Flight.FONT, "QoL", "flightFont", "font")

local mod, wired, holder
local nodes, here = {}, nil   -- the open taxi map's points: slot -> { name, id }; where you are
local pending                  -- { key, back, name, from, guess, stops, at }: picked, not in the air yet
local flight                   -- { key, name, from, start, total?, stops, early? }: in the air
local vis = 0                  -- 0 hidden .. 1 fully in
local welcome                  -- the landing splash
local welcomeRun = 0           -- each splash's id: a newer one stops the older one's timers
local welcomeSample = false    -- the welcome is up as the unlock / test mode sample

local function db(key) return mod and mod.db and mod.db[key] end
-- A piece's switch: on unless it was turned off.
local function on(key) return db(key) ~= false end
local function width() return tonumber(db("flightWidth")) or Flight.WIDTH end

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
        hops[i] = { a.id, b.id, b.name }
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

-- Each stop's name along the way, in order (the last hop's end is the
-- destination, not a stop).
local function stopNames(hops)
    if not hops then return nil end
    local names = {}
    for i = 1, #hops - 1 do names[i] = hops[i][3] or false end
    return names
end

-- The first stop still ahead at p (0..1): its place and its number, or nil
-- when none is left.
local function nextStop(p, stops)
    if not stops then return nil end
    for i, at in ipairs(stops) do
        if at > p + 0.005 then return at, i end
    end
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
    Style.PaintAccent(f.box.topLine, 0.7)
    Style.PaintAccentText(f.label, Style.Upper(L["Flying to"]))
end

-- Where the box's border, shadow and background come from (Style.LookOf).
local LOOK = { "QoL", "flightFrame" }

-- Its border: the Daylight UI one, the accent or the player's own color (a
-- color is picked with the timer's own look; the global style has none).
local function paintBorder(s)
    local mode = Style.LookOwn(LOOK) and db("flightBorderColor") or "normal"
    local c = db("flightBorderCustom")
    if mode == "accent" then
        Style.LightShell(s)
    elseif mode == "custom" and type(c) == "table" then
        Style.SetShellColors(s, { c[1], c[2], c[3] })
    else
        Style.SetShellColors(s, nil)
    end
end

-- Lays the banner out from its settings: what shows, the sizes, the width,
-- the background and border. Each piece turned off gives its room back.
local function layout()
    if not holder then return end
    local f, w = holder.f, width()
    local nameSize = tonumber(db("flightNameSize")) or Flight.NAME
    local textSize = tonumber(db("flightTextSize")) or Style.SIZE.small
    local timeSize = tonumber(db("flightTimeSize")) or Style.SIZE.head
    Style.SetTextSize(f.label, textSize)
    Style.SetTextSize(f.name, nameSize)
    Style.SetTextSize(f.from, textSize)
    Style.SetTextSize(f.time, timeSize)

    local y = 0
    f.label:ClearAllPoints()
    f.label:SetShown(on("flightLabel"))
    if on("flightLabel") then
        f.label:SetPoint("TOP", f, "TOP", 0, 0)
        y = textSize + 3
    end
    f.name:ClearAllPoints()
    f.name:SetPoint("TOP", f, "TOP", 0, -y)
    f.name:SetWidth(w)
    y = y + nameSize + 8

    local line = on("flightLine")
    holder.lineOn = line
    f.bar:SetShown(line)
    f.start:SetShown(line)
    f.finish:SetShown(line)
    if line then
        y = y + 4
        f.bar:ClearAllPoints()
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        f.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        y = y + Flight.LINE + 7
    end

    local from, time = on("flightFrom"), on("flightTime")
    f.from:SetShown(from)
    f.time:SetShown(time)
    f.from:ClearAllPoints()
    f.from:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(y + 2))
    f.from:SetPoint("RIGHT", f, "CENTER", -8, 0)
    f.time:ClearAllPoints()
    f.time:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
    if from or time then y = y + math.max(from and textSize + 2 or 0, time and timeSize or 0) end

    holder:SetSize(w, y)
    f:SetSize(w, y)
    local back, border = on("flightBack"), Style.LookOf(LOOK).borderAlpha ~= 0
    f.box.shell = Style.Shell(f.box, { look = LOOK, noBackground = not back, noBevel = not back,
        shadowAlpha = (not back and not border) and 0 or nil })
    paintBorder(f.box.shell)
    f.box.topLine:SetShown(on("flightAccentLine"))
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "DaylightUIFlightTimer", UIParent)
    holder:SetSize(Flight.WIDTH, Flight.HEIGHT)
    holder:EnableMouse(false)
    holder:Hide()
    local f = CreateFrame("Frame", nil, holder)
    holder.f = f
    f:SetSize(Flight.WIDTH, Flight.HEIGHT)
    f:SetPoint("TOP", holder, "TOP", 0, 0)

    -- The box behind it all, so it reads over bright ground: the window shell
    -- with the windows' accent line along its top.
    f.box = CreateFrame("Frame", nil, f)
    f.box:SetFrameLevel(f:GetFrameLevel())
    f.box:SetPoint("TOPLEFT", f, "TOPLEFT", -Flight.PAD_X, Flight.PAD_Y)
    f.box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", Flight.PAD_X, -Flight.PAD_Y)
    f.box.shell = Style.Shell(f.box)
    DUI.Win.Lines(f.box)

    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints(f)
    over:SetFrameLevel(f:GetFrameLevel() + 8)
    f.over = over

    f.label = Style.Text(over, Style.SIZE.small, "CENTER", Flight.FONT)
    f.name = Style.Text(over, Flight.NAME, "CENTER", Flight.FONT)
    f.name:SetWordWrap(false)
    Style.InkText(f.name, "TITLE")

    f.bar = Style.Bar(f)
    f.bar:SetFrameLevel(f:GetFrameLevel() + 4)
    f.bar:SetHeight(Flight.LINE)

    f.start = dot(over, Flight.DOT)
    f.start:SetPoint("CENTER", f.bar, "LEFT", 0, 0)
    f.finish = dot(over, Flight.DOT + 3)
    f.finish:SetPoint("CENTER", f.bar, "RIGHT", 0, 0)
    f.stops = {}
    f.spark = over:CreateTexture(nil, "ARTWORK")
    f.spark:SetTexture(Flight.GLOW)
    f.spark:SetBlendMode("ADD")
    f.spark:SetSize(Flight.SPARK, Flight.SPARK)
    f.spark:SetPoint("CENTER", f.bar, "LEFT", 0, 0)
    f.head = dot(over, Flight.DOT)
    f.head:SetPoint("CENTER", f.bar, "LEFT", 0, 0)
    f.head:SetVertexColor(1, 1, 1, 1)

    f.from = Style.Text(over, Style.SIZE.small, "LEFT", Flight.FONT)
    f.from:SetWordWrap(false)
    Style.InkText(f.from, "LABEL")
    f.time = Style.Text(over, Style.SIZE.head, "RIGHT", Flight.FONT)
    f.time.tone = nil

    -- Land at the next stop: the game's own early landing, the one its
    -- leave-vehicle button asks for in flight, with the game's own words.
    f.leave = DUI.Widgets.IconButton(f.box, "ui-leave.png", Flight.LeaveTip,
        function() Flight.LandEarly() end)
    f.leave:SetFrameLevel(f:GetFrameLevel() + 10)
    f.leave:SetPoint("TOPRIGHT", f.box, "TOPRIGHT", -Flight.LEAVE_INSET, -Flight.LEAVE_INSET)
    f.leave.vis = 0
    f.leave:SetAlpha(0)
    f.leave:Hide()
    layout()
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

-- Pointing at a stop's dot names it above the dot, and the dot swells a little.
-- The hover area is a bit bigger than the dot, which is only a few pixels.
local function stopHover(d)
    local hit = CreateFrame("Frame", nil, holder.f.over)
    hit:SetSize(Flight.STOP_HIT, Flight.STOP_HIT)
    hit:SetPoint("CENTER", d, "CENTER", 0, 0)
    hit:EnableMouse(true)
    -- Only the hover: a click still reaches the world, to turn the camera.
    if hit.SetMouseClickEnabled then hit:SetMouseClickEnabled(false) end
    d.size = Flight.DOT - 1
    local function grow(big)
        Motion.Tween(d, d.size, big and Flight.DOT + 2 or Flight.DOT - 1, Motion.FAST, function(v)
            d.size = v
            d:SetSize(v, v)
        end)
    end
    hit:SetScript("OnEnter", function(self)
        if type(d.stopName) ~= "string" or d.stopName == "" then return end
        grow(true)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        DUI.Tips.Clear()
        DUI.Tips.Title(d.stopName)
        DUI.Tips.Flush()
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function(self)
        grow(false)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    d.hit = hit
end

-- A dot for each stop between, lit once you're past it, named on hover.
local function placeStops(stops, p, names)
    local f = holder.f
    stops = stops or {}
    for i = 1, math.max(#stops, #f.stops) do
        local at = stops[i]
        local d = f.stops[i]
        if at then
            if not d then
                d = dot(f.over, Flight.DOT - 1)
                f.stops[i] = d
                stopHover(d)
            end
            d:ClearAllPoints()
            -- The fixed width, not GetWidth: the line may not be laid out yet on its first show.
            d:SetPoint("CENTER", f.bar, "LEFT", at * width(), 0)
            d:Show()
            local name = names and names[i]
            d.stopName = type(name) == "string" and Flight.ShortName(name) or nil
            d.hit:SetShown(d.stopName ~= nil)
        elseif d then
            d:Hide()
            d.hit:Hide()
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

-- The front of the line at p (0..1). The fill's own edge is hard, so on screen
-- it can only step a whole pixel at a time; the soft light and dot over it are
-- placed at the exact spot every frame and glide between pixels.
local function setFront(p)
    local f = holder.f
    f.bar:SetValue(p)
    local x = p * width()
    f.spark:SetPoint("CENTER", f.bar, "LEFT", x, 0)
    f.head:SetPoint("CENTER", f.bar, "LEFT", x, 0)
end

-- The land-early button eases in while there's a stop ahead to land at, and
-- out once asked (or past the last stop).
local function showLeave(want)
    local b = holder.f.leave
    if b.want == want then return end
    b.want = want
    if want then b:Show() end
    Motion.Tween("qol:flightLeave", b.vis, want and 1 or 0, Motion.FAST, function(v)
        b.vis = v
        b:SetAlpha(v)
    end, function() if not want then b:Hide() end end)
end

-- What the banner shows: where to, from where, how far along, the time.
-- landAt: asked to land early, at that stop's place along the line.
local function show(name, from, elapsed, total, stops, landAt, canLeave, names)
    local f = holder.f
    setText(f.name, Flight.ShortName(name))
    setText(f.from, Flight.ShortName(from))
    local p
    if total and total > 0 then
        p = math.min(1, elapsed / total)
        local left = (landAt or 1) * total - elapsed
        setText(f.time, left > 0 and Flight.FormatTime(left) or L["Almost there"])
        tone(f.time, (left > 0 and left < Flight.SOON) and "WARN" or "pop")
        f.spark:SetShown(holder.lineOn == true)
        f.head:SetShown(holder.lineOn == true)
    else
        -- No time to count down from: the clock counts up, the line waits empty.
        p = 0
        setText(f.time, Flight.FormatTime(elapsed))
        tone(f.time, "VALUE")
        f.spark:Hide()
        f.head:Hide()
    end
    f.bar:SetMinMaxValues(0, 1)
    setFront(p)
    placeStops((holder.lineOn and on("flightStops")) and stops or nil, p, names)
    -- A direct flight has no stop to land at; without the map's stops it may.
    showLeave(canLeave == true and (stops == nil or nextStop(p, stops) ~= nil))
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
        show(flight.name, flight.from, GetTime() - flight.start, flight.total, flight.stops,
            flight.landAt, not flight.early, flight.names)
    elseif sampleWanted() then
        local s = Flight.SAMPLE
        show(s.name, s.from, s.elapsed, s.total, s.stops, nil, true, s.names)
    else
        glide(false)
        Flight.WelcomeSample(false)
        return
    end
    glide(true)
    Flight.WelcomeSample(sampleWanted() and on("flightWelcome"))
end

-- ---------------------------------------------------------------------
-- The welcome on landing
-- ---------------------------------------------------------------------

local function buildWelcome()
    if welcome then return welcome end
    -- The holder stays put for the unlock handle; the splash drifts inside it.
    local wh = CreateFrame("Frame", "DaylightUIFlightWelcomeHolder", UIParent)
    wh:SetSize(Flight.WELCOME_W, 80)
    wh:EnableMouse(false)
    local w = CreateFrame("Frame", "DaylightUIFlightWelcome", wh)
    w.holder = wh
    w:SetSize(Flight.WELCOME_W, 1)
    w:SetFrameStrata("HIGH")
    w:EnableMouse(false)
    w:Hide()
    -- The top is free again: a zone or reputation change that waited plays now.
    w:SetScript("OnHide", function()
        if ns.ZoneTitle then ns.ZoneTitle.Resume() end
        if ns.RepBanner then ns.RepBanner.Resume() end
    end)
    w.haze = w:CreateTexture(nil, "BACKGROUND")
    w.haze:SetTexture(Flight.GLOW)
    w.haze:SetBlendMode("ADD")
    w.haze:SetPoint("CENTER", w, "CENTER", 0, 10)
    w.haze:SetSize(Flight.WELCOME_W * 1.1, 90)
    -- The line: two halves from the middle out, gone at the ends.
    w.left = w:CreateTexture(nil, "ARTWORK")
    w.left:SetColorTexture(1, 1, 1, 1)
    w.left:SetPoint("RIGHT", w, "CENTER", 0, 0)
    w.left:SetHeight(1)
    w.right = w:CreateTexture(nil, "ARTWORK")
    w.right:SetColorTexture(1, 1, 1, 1)
    w.right:SetPoint("LEFT", w, "CENTER", 0, 0)
    w.right:SetHeight(1)
    w.body = CreateFrame("Frame", nil, w)
    w.body:SetSize(Flight.WELCOME_W, 80)
    w.label = Style.Text(w.body, Style.SIZE.body, "CENTER", Flight.FONT)
    w.name = Style.Text(w.body, Flight.WELCOME_NAME, "CENTER", Flight.FONT)
    w.name:SetPoint("BOTTOM", w.body, "BOTTOM", 0, 6)
    w.name:SetWidth(Flight.WELCOME_W)
    w.name:SetWordWrap(false)
    Style.InkText(w.name, "TITLE")
    welcome = w
    DUI.Movers.Register(wh, Flight.WELCOME_MOVER, "Flight welcome", { "TOP", nil, "TOP", 0, Flight.WELCOME_Y + 40 },
        { active = function() return enabled() and on("flightWelcome") end })
    return w
end

-- Its text size from the setting; the label sits just above the name.
local function sizeWelcome(w)
    local size = tonumber(db("flightWelcomeSize")) or Flight.WELCOME_NAME
    Style.SetTextSize(w.name, size)
    w.label:ClearAllPoints()
    w.label:SetPoint("BOTTOM", w.body, "BOTTOM", 0, size + 10)
end

local function paintWelcome(w)
    local r1, g1, b1 = Style.SplashAt(0)
    local rm, gm, bm = Style.SplashAt(0.5)
    local r2, g2, b2 = Style.SplashAt(1)
    w.left:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 0), CreateColor(rm, gm, bm, 1))
    w.right:SetGradient("HORIZONTAL", CreateColor(rm, gm, bm, 1), CreateColor(r2, g2, b2, 0))
    w.haze:SetVertexColor(Style.SplashAt(0.85))
    Style.PaintAccentText(w.label, Style.Upper(L["Welcome to"]))
end

-- p 0..1: in from below, the line drawing out from the middle.
local function welcomeIn(w, p)
    w.body:ClearAllPoints()
    w.body:SetPoint("BOTTOM", w, "CENTER", 0, -Flight.WELCOME_RISE * (1 - p))
    w.body:SetAlpha(p)
    local half = math.max(0.5, Flight.WELCOME_W * p / 2)
    w.left:SetWidth(half)
    w.right:SetWidth(half)
    w.haze:SetAlpha(0.35 * p)
end

local function welcomePlace(w, drift)
    w:ClearAllPoints()
    w:SetPoint("CENTER", w.holder, "CENTER", 0, drift)
end

-- "Welcome to Stormwind": slides gently up into place, holds, and fades away
-- rising. It takes no clicks and steps aside for a level-up.
function Flight.Welcome(name)
    name = Flight.ShortName(name)
    if not on("flightWelcome") then return end
    if name == "" or (ns.LevelUp and ns.LevelUp.Showing()) then return end
    if ns.ZoneTitle then ns.ZoneTitle.Stop() end
    if ns.RepBanner then ns.RepBanner.Stop() end
    local w = buildWelcome()
    paintWelcome(w)
    sizeWelcome(w)
    welcomeSample = false
    welcomeRun = welcomeRun + 1
    local id = welcomeRun
    w.name:SetText(name)
    welcomePlace(w, 0)
    welcomeIn(w, 0)
    w:SetAlpha(1)
    w:Show()
    Motion.Tween("qol:welcome", 0, 1, Motion.SLOW, function(p)
        if id == welcomeRun then welcomeIn(w, p) end
    end)
    C_Timer.After(Motion.SLOW + Flight.WELCOME_HOLD, function()
        if id ~= welcomeRun then return end
        Motion.Tween("qol:welcome", 0, 1, Motion.SLOW, function(p)
            if id ~= welcomeRun then return end
            welcomePlace(w, Flight.WELCOME_DRIFT * p)
            w:SetAlpha(1 - p)
        end, function() if id == welcomeRun then w:Hide() end end)
    end)
end

-- Up on screen (the zone title and reputation banner wait for it). The
-- sample in unlock or test mode doesn't hold them up.
function Flight.Welcoming() return welcome ~= nil and welcome:IsShown() and not welcomeSample end

-- The welcome standing still as a sample while unlock or test mode wants it.
function Flight.WelcomeSample(want)
    want = want == true and enabled()
    if want then
        if Flight.Welcoming() then return end
        local w = buildWelcome()
        paintWelcome(w)
        sizeWelcome(w)
        welcomeSample = true
        welcomeRun = welcomeRun + 1
        w.name:SetText(Flight.ShortName(Flight.SAMPLE.name))
        welcomePlace(w, 0)
        welcomeIn(w, 1)
        w:SetAlpha(1)
        w:Show()
    elseif welcomeSample and welcome then
        welcomeSample = false
        welcomeRun = welcomeRun + 1
        welcome:Hide()
    end
end

-- Steps aside at once (a level-up takes the spot, or it was switched off).
function Flight.StopWelcome()
    if not Flight.Welcoming() then return end
    welcomeRun = welcomeRun + 1
    local id, w = welcomeRun, welcome
    Motion.Tween("qol:welcome", 0, 1, Motion.FAST, function(p)
        if id == welcomeRun then w:SetAlpha(1 - p) end
    end, function() if id == welcomeRun then w:Hide() end end)
end

function Flight.PreviewWelcome() Flight.Welcome(L["Stormwind"]) end

-- ---------------------------------------------------------------------
-- Following a flight
-- ---------------------------------------------------------------------

local driver, acc = nil, 0

-- Every frame in the air, the line alone moves on; the text waits for the tick.
local function moveLine()
    if not (flight and flight.total and flight.total > 0 and holder and holder:IsShown()) then return end
    setFront(math.min(1, (GetTime() - flight.start) / flight.total))
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
    Flight.Update()
    if not f.early then Flight.Welcome(f.name) end
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
            names = flight.names, landAt = flight.landAt, wall = time() - (GetTime() - flight.start) })
end

local function takeOff(p, start)
    flight = { key = p.key, back = p.back, name = p.name, from = p.from, guess = p.guess,
               stops = p.stops, names = p.names, landAt = p.landAt,
               start = start or GetTime(), early = p.early }
    flight.total = knownTime(p.key, p.back, p.guess)
    pending = nil
    remember()
    Flight.Update()
end

function Flight.Tick()
    if flight then
        if not onTaxi() then land() return end
        if holder and holder:IsShown() then
            show(flight.name, flight.from, GetTime() - flight.start, flight.total, flight.stops,
                flight.landAt, not flight.early, flight.names)
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
    local hops = Flight.Hops(slot)
    local guess, stops = Flight.Guess(here, to, hops)
    pending = { key = Flight.Key(here, to), back = Flight.Key(to, here), name = to.name,
                from = here and here.name or nil, guess = guess, stops = stops,
                names = stopNames(hops), at = GetTime() }
    startDriver()
end

-- The flight a flight master's words would start where you stand, or nil.
function Flight.TalkedRoute()
    local maps = C_Map
    if type(maps) ~= "table" or type(maps.GetBestMapForUnit) ~= "function" then return nil end
    local byFaction = Flight.TALKED[maps.GetBestMapForUnit("player")]
    if not byFaction or type(UnitFactionGroup) ~= "function" then return nil end
    return byFaction[UnitFactionGroup("player")]
end

-- The talk closing or control going away where a talked flight starts: watch
-- for the taxi as after a pick on the map. The taxi flag can come a moment
-- after either, and a stun or a closed talk with no flight is dropped after
-- START_WAIT like an unused pick. A pick on the map is never overwritten.
function Flight.OnTalked()
    if not enabled() or flight or pending then return end
    local r = Flight.TalkedRoute()
    if not r then return end
    local from, to = { id = r.from, name = r.fromName }, { id = r.to, name = r.name }
    pending = { key = Flight.Key(from, to), back = Flight.Key(to, from), name = to.name,
                from = from.name, guess = Flight.Guess(from, to), at = GetTime() }
    startDriver()
    -- Already in the air when the event came: take off now, not a tick later.
    if onTaxi() then takeOff(pending) end
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
              stops = type(s.stops) == "table" and s.stops or nil,
              names = type(s.names) == "table" and s.names or nil,
              landAt = type(s.landAt) == "number" and s.landAt or nil,
              early = s.early or login or nil },
            GetTime() - ago)
    startDriver()
end

-- Asked to land early (the banner's button or the game's own): that flight's
-- time isn't the route's. The banner now heads for the next stop when the
-- map said where it is: its name and the time left to it.
function Flight.OnEarly()
    if not flight or flight.early then return end
    flight.early = true
    if flight.total and flight.total > 0 then
        local at, i = nextStop((GetTime() - flight.start) / flight.total, flight.stops)
        if at then
            flight.landAt = at
            local name = flight.names and flight.names[i]
            if type(name) == "string" and name ~= "" then flight.name = name end
        end
    end
    remember()
    Flight.Update()
end

-- The name of the stop an early landing would set you down at, or nil when
-- the map didn't say (no stops known, no time to place them, none left).
function Flight.NextStopName()
    if not (flight and flight.total and flight.total > 0) then return nil end
    local _, i = nextStop((GetTime() - flight.start) / flight.total, flight.stops)
    local name = i and flight.names and flight.names[i]
    if type(name) == "string" and name ~= "" then return Flight.ShortName(name) end
end

-- The land-early button's tooltip: where you'd get off, when that's known.
function Flight.LeaveTip()
    local name = Flight.NextStopName()
    if name then return L["Get off at %s"]:format(name), false end
    return TAXI_CANCEL or L["Exit flight"], TAXI_CANCEL_DESCRIPTION or L["You will land at the next flight point."]
end

-- The banner's button.
function Flight.LandEarly()
    if not (flight and onTaxi()) or flight.early then return end
    if type(TaxiRequestEarlyLanding) == "function" then TaxiRequestEarlyLanding() end
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
            hooksecurefunc("TaxiRequestEarlyLanding", function() Flight.OnEarly() end)
        end
        DUI.RegisterEvent("TAXIMAP_OPENED", function() if enabled() then Flight.ReadMap() end end)
        DUI.RegisterEvent("GOSSIP_CLOSED", Flight.OnTalked)
        DUI.RegisterEvent("PLAYER_CONTROL_LOST", Flight.OnTalked)
        DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin)
            -- Enable resumed it already, not knowing yet whether this is a login.
            if isLogin == true and flight and not flight.early then
                flight.early = true
                remember()
            end
            Flight.Resume(isLogin == true)
        end)
        DUI.RegisterTestPart(Flight.TEST_PART, "Flight timer", 95, enabled)
        DUI.RegisterCommand("landing", Flight.PreviewWelcome, L["/dui landing - preview the welcome on landing"])
        DUI.On("TestModeChanged", Flight.Update)
        DUI.On("TestPartChanged", function(key) if key == Flight.TEST_PART then Flight.Update() end end)
        DUI.On("UnlockChanged", Flight.Update)
        local function restyle() layout() paint() end
        DUI.On("StyleChanged", restyle)
        DUI.On("SettingChanged", function(scope) if scope == "general" then restyle() end end)
    end
    if enabled() then build() end
    Flight.Resume()
end

function Flight.Refresh(m)
    mod = m
    if not enabled() then
        pending = nil
        if flight then flight = nil stopDriver() end
        Flight.StopWelcome()
    else
        Flight.Resume()
    end
    if not on("flightWelcome") then Flight.StopWelcome() Flight.WelcomeSample(false) end
    layout()
    paint()
    Flight.Update()
end
