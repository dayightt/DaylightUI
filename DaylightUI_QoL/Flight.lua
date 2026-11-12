-- Flight timer: a bar at the top of the screen with the destination and time
-- left while on a flight path. Times are learned from your own flights and
-- saved per account by route. An unknown route shows "Learning..." and counts up.
-- The destination comes from a post-hook on the global TakeTaxiNode.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion

local Flight = {
    WIDTH = 260, HEIGHT = 20,
    SLANT = 0.6,        -- the angled end's cut, as a share of the height (the breath bar's)
    TEXT = 12,
    PAD = 8,            -- text inset from the ends
    RISE = 10,          -- px it glides down as it comes in
    TICK = 0.1,         -- seconds between updates while flying
    START_WAIT = 10,    -- seconds after picking a flight point to wait for take-off
    MIN_LEARN = 5,      -- a shorter "flight" is a hiccup, not a route: not learned
    RESUME_MAX = 3600,  -- a saved flight older than this is stale (after a /reload)
    LEARNING_ALPHA = 0.35,  -- the fill while a route is being learned (no progress to show)
    SOON = 10,              -- seconds left under which the time turns amber
    MOVER = "qol.flight",
    GRADIENT = "TIMER_FLIGHT",
    TEST_PART = "flight",
    -- The test-mode sample.
    SAMPLE = { name = L["Stormwind"], total = 102, elapsed = 41 },
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
local pending                  -- { key, name, at }: picked, not in the air yet
local flight                   -- { key, name, start, total?, early? }: in the air
local vis = 0                  -- 0 hidden .. 1 fully in

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

-- ---------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------

local function layout()
    if not holder then return end
    local box = holder.box
    local T = Pixel.Px(box, Style.BorderPx(box))
    local height = 2 * Pixel.Snap(holder, Flight.HEIGHT / 2)
    local width = 2 * Pixel.Snap(holder, Flight.WIDTH / 2)
    holder:SetSize(width, height)
    box:SetSize(width, height)
    local cut = (mod and mod.db and mod.db.flightTimerSlant == false) and 0 or Pixel.Snap(box, height * Flight.SLANT)
    Style.Slant(box, "right", cut)
    Style.AngleFill(box.bar, "right", cut * (height - 2 * T) / height)
    box.bar:ClearAllPoints()
    box.bar:SetPoint("TOPLEFT", box, "TOPLEFT", T, -T)
    box.bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -T, T)
    box.time:ClearAllPoints()
    box.time:SetPoint("RIGHT", box, "RIGHT", -(cut + Flight.PAD), 0)
    box.name:ClearAllPoints()
    box.name:SetPoint("LEFT", box, "LEFT", Flight.PAD, 0)
    box.name:SetPoint("RIGHT", box.time, "LEFT", -Flight.PAD, 0)
end

local function paint()
    if not holder then return end
    local G = DUI.Gradients
    if G then G.Paint(holder.box.bar, G.Has(Flight.GRADIENT) and Flight.GRADIENT or "FALLBACK") end
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "DaylightUIFlightTimer", UIParent)
    holder:SetSize(Flight.WIDTH, Flight.HEIGHT)
    holder:Hide()
    local box = CreateFrame("Frame", nil, holder)
    holder.box = box
    box:SetPoint("TOP", holder, "TOP", 0, 0)
    Style.Shell(box)
    Style.Slant(box, nil, 0)
    box.bar = Style.Bar(box)
    Style.Clip(box, box.bar:GetStatusBarTexture(), "inner")
    Style.Clip(box, Style.BarBack(box.bar), "inner")
    local overlay = CreateFrame("Frame", nil, box)
    overlay:SetAllPoints(box)
    overlay:SetFrameLevel(box.bar:GetFrameLevel() + 3)
    box.name = Style.Text(overlay, Flight.TEXT, "LEFT")
    box.name:SetWordWrap(false)
    box.time = Style.Text(overlay, Flight.TEXT, "RIGHT")
    Style.InkText(box.name, "VALUE")
    Style.InkText(box.time, "VALUE")
    box.time.flightWarn = false
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

-- What the bar shows: a flight's name, how far along, the time text.
local function show(name, elapsed, total)
    local box = holder.box
    setText(box.name, Flight.ShortName(name))
    local fill = box.bar:GetStatusBarTexture()
    if total and total > 0 then
        box.bar:SetMinMaxValues(0, total)
        box.bar:SetValue(math.min(elapsed, total))
        fill:SetAlpha(1)
        local left = total - elapsed
        setText(box.time, left > 0 and Flight.FormatTime(left) or L["Almost there"])
        local warn = left > 0 and left < Flight.SOON
        if box.time.flightWarn ~= warn then
            box.time.flightWarn = warn
            Style.InkText(box.time, warn and "WARN" or "VALUE")
        end
    else
        box.bar:SetMinMaxValues(0, 1)
        box.bar:SetValue(1)
        fill:SetAlpha(Flight.LEARNING_ALPHA)
        setText(box.time, L["Learning... %s"]:format(Flight.FormatTime(elapsed)))
    end
end

-- The glide: alpha and a short drop from above, from wherever it is.
local function place(p)
    vis = p
    holder.box:SetAlpha(p)
    holder.box:ClearAllPoints()
    holder.box:SetPoint("TOP", holder, "TOP", 0, Flight.RISE * (1 - p))
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

-- Shows or hides the bar for what's going on now, and fills it in.
function Flight.Update()
    if not enabled() then
        if holder and holder:IsShown() then glide(false) end
        return
    end
    build()
    if flight then
        show(flight.name, GetTime() - flight.start, flight.total)
    elseif sampleWanted() then
        local s = Flight.SAMPLE
        show(s.name, s.elapsed, s.total)
    else
        glide(false)
        return
    end
    glide(true)
end

-- ---------------------------------------------------------------------
-- Following a flight
-- ---------------------------------------------------------------------

local driver, acc = nil, 0

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
end

local function takeOff(p, start)
    flight = { key = p.key, name = p.name, start = start or GetTime() }
    flight.total = p.key and Flight.Routes()[p.key] or nil
    pending = nil
    saved({ key = p.key, name = p.name, wall = time() - (GetTime() - flight.start) })
    Flight.Update()
end

function Flight.Tick()
    if flight then
        if not onTaxi() then land() return end
        if holder and holder:IsShown() then show(flight.name, GetTime() - flight.start, flight.total) end
    elseif pending then
        if onTaxi() then takeOff(pending)
        elseif GetTime() - pending.at > Flight.START_WAIT then pending = nil stopDriver() end
    else
        stopDriver()
    end
end

-- A parentless frame, so it keeps watching with the interface hidden (Alt-Z):
-- the landing must be seen on time or the learned time would be too long.
local function startDriver()
    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", function(_, dt)
            acc = acc + (dt or 0)
            if acc < Flight.TICK then return end
            acc = 0
            Flight.Tick()
        end)
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
    local to = nodes[slot]
    if not (to and to.name) and type(TaxiNodeName) == "function" then
        to = { name = TaxiNodeName(slot) }
    end
    if not (to and type(to.name) == "string" and to.name ~= "") then return end
    pending = { key = Flight.Key(here, to), name = to.name, at = GetTime() }
    startDriver()
end

-- After a /reload (or a login) mid-flight: carry on from the saved take-off.
function Flight.Resume()
    if flight or not enabled() then return end
    local s = saved()
    if type(s) ~= "table" then return end
    local ago = type(s.wall) == "number" and time() - s.wall or nil
    if not onTaxi() or not ago or ago < 0 or ago > Flight.RESUME_MAX then
        saved(false)
        return
    end
    takeOff({ key = s.key, name = s.name }, GetTime() - ago)
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
            hooksecurefunc("TaxiRequestEarlyLanding", function() if flight then flight.early = true end end)
        end
        DUI.RegisterEvent("TAXIMAP_OPENED", function() if enabled() then Flight.ReadMap() end end)
        DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function() Flight.Resume() end)
        DUI.RegisterTestPart(Flight.TEST_PART, "Flight timer", 95, enabled)
        DUI.On("TestModeChanged", Flight.Update)
        DUI.On("TestPartChanged", function(key) if key == Flight.TEST_PART then Flight.Update() end end)
        DUI.On("UnlockChanged", Flight.Update)
        local function restyle()
            if not holder then return end
            layout()
            paint()
        end
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
    else
        Flight.Resume()
    end
    layout()
    Flight.Update()
end
