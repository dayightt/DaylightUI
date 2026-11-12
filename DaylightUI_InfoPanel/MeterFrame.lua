-- Frames for the player-made meter windows. Moved and resized in unlock mode,
-- faded with the panel. `frame` belongs to the mover and the panel's fade;
-- `body` inside it holds the shell and meter and does the show/hide easing.
--
-- One host per window id, created on first use and kept. A removed window's
-- host fades out and never draws again (ids are never reused).

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel
local Windows_KINDS = { meter = true, threat = true, summary = true }

local MF = {}
ns.MeterFrame = MF

MF.GAP = 8                 -- between a new window's first spot and the one beside it
MF.PART = "meters"         -- the test box's one tick for every window of the player's
MF.hosts = {}

DUI.RegisterTestPart(MF.PART, "Meter windows", 92, function()
    return ns.module ~= nil and #ns.Windows.Own() > 0
end)

function MF.Key(id) return "infopanel.meter." .. id end

-- Shows or hides a host's window, easing (the fade owns `frame`'s alpha).
local function ease(h, on)
    local body, frame = h.body, h.frame
    if on then
        if not frame:IsShown() then
            body:SetAlpha(0)
            frame:Show()
        end
        DUI.Motion.Tween(h.key, body:GetAlpha(), 1, DUI.Motion.FAST, function(a) body:SetAlpha(a) end)
    elseif frame:IsShown() then
        DUI.Motion.Tween(h.key, body:GetAlpha(), 0, DUI.Motion.FAST, function(a) body:SetAlpha(a) end,
            function() frame:Hide() end)
    end
end

-- Default position: bottom-right of the screen, to the left of earlier windows
-- that are still at their default spots.
function MF.Home(id)
    local P = ns.Panel
    local x = -P.EDGE
    local db = ns.module and ns.module.db
    local positions = DUI.DB.Positions()
    if db and db.meter.detached and not DUI.Movers.Valid(positions["infopanel.meter"]) then
        x = x - P.meterFrame:GetWidth() - MF.GAP
    end
    for _, e in ipairs(ns.Windows.Own()) do
        if e.id == id then break end
        local h = MF.hosts[e.id]
        if h and not h.dead and e.cfg.enabled and not DUI.Movers.Valid(positions[MF.Key(e.id)]) then
            x = x - h.frame:GetWidth() - MF.GAP
        end
    end
    return { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", x, DUI.Movers.Above(P.EDGE) }
end

-- A threat window's view (ThreatView.lua) and its drawing: the list of
-- whichever mob its "unit" setting follows (ThreatMeter's TM.Collect).
MF.THREAT_ROWS = { 2, 10 }   -- the rows a threat window can show
MF.SUMMARY_MIN = { 330, 80 }  -- a summary's size limits: its columns need the width
MF.SUMMARY_MAX = { 700, 500 }

local function threatHost(h)
    local TM = ns.ThreatMeter
    h.view = ns.ThreatView.New(h.body)
    h.snap = true
    function h.Sample()
        if DUI.Movers.unlocked and h.cfg and h.cfg.enabled then return true end
        return DUI.testMode and DUI.TestPartShown(MF.PART) or false
    end
    function h.Draw()
        local cfg = h.cfg
        if not (cfg and h.geo) or h.dead then return end
        local sample = h.Sample()
        local mob = not sample and TM.Mob(cfg.unit) or nil
        local data, secret, pull, top
        if sample or mob then data, secret, pull, top = TM.Collect(cfg.rows, mob, sample) end
        local name = ""
        if data and sample then name = TM.SAMPLE_TARGET elseif data then name = DUI.UnitName(mob, "threat") end
        h.view.empty:SetShown(not data)
        ns.ThreatView.Draw(h.view, cfg, data, secret, pull, top, name, (not sample) and mob or nil, h.geo, h.snap)
        h.snap = false
    end
end

-- Builds a window's contents for its kind: shell, area and view (meter, threat
-- or summary). If an id comes back as another kind (profile switch), the
-- contents are rebuilt inside the same frame, keeping its mover and grip.
local function fill(h, e, mod)
    local body = CreateFrame("Frame", nil, h.frame)
    body:SetAllPoints(h.frame)
    Style.Shell(body)
    h.body, h.area, h.kind = body, CreateFrame("Frame", nil, body), e.kind
    h.snap, h.geo, h.cfg = true, nil, nil
    if e.kind == "threat" then
        threatHost(h)
    elseif e.kind == "summary" then
        h.view = ns.Summary.New(h, MF.PART)
        ns.Meter.Register(h.view)
    else
        h.view = ns.Meter.New(nil, { id = h.id, path = e.path, part = MF.PART })
        h.view.Build(h.area, mod)
    end
end

local function make(e, mod)
    local id = e.id
    local frame = CreateFrame("Frame", "DaylightUIMeterWindow_" .. id, UIParent)
    frame:SetFrameStrata("LOW")
    frame:Hide()
    local h = { id = id, frame = frame, key = "infopanel:meterWindow:" .. id }
    -- A threat window's grip sets the width and as many rows as fit; the
    -- others', the width and height.
    local path = e.path
    h.grip = ns.Panel.MeterGrip(frame, MF.Key(id), path, function() return h.body end, function(w, ht)
        if h.kind == "threat" then return MF.ThreatResized(h, w, ht) end
        DUI:Set("InfoPanel", path .. ".width", w)
        DUI:Set("InfoPanel", path .. ".height", ht)
    end)
    DUI.Movers.Register(frame, MF.Key(id), ns.Windows.Name(e), function() return MF.Home(id) end, { bottom = true })
    fill(h, e, mod)
    MF.hosts[id] = h
    return h
end

function MF.UpdateGrip(h, cfg)
    h.grip:SetShown(DUI.Movers.unlocked and not h.dead and cfg.enabled == true and h.frame:IsShown() or false)
end

-- Whether a window should be up right now.
function MF.Wanted(e, h)
    if h and h.dead then return false end
    if h and h.kind == "threat" then return ns.ThreatMeter.WindowWanted(e.cfg, h.Sample()) end
    return ns.Panel.MeterWanted(e.cfg, nil, h and h.view.Sample())
end

-- A threat window's height for n rows (the box, inside its border).
local function threatHeight(h, cfg, n)
    local head = cfg.header ~= "off" and ns.ThreatView.HEAD or 0
    return head + n * (cfg.rowHeight + ns.Meter.SPACING) - ns.Meter.SPACING
end

-- Let go of a threat window's grip: its width, and as many rows as fit.
function MF.ThreatResized(h, w, ht)
    local cfg = h.cfg
    if not cfg then return end
    local step = cfg.rowHeight + ns.Meter.SPACING
    local head = cfg.header ~= "off" and ns.ThreatView.HEAD or 0
    local n = math.floor((ht - head + ns.Meter.SPACING) / step)
    n = math.max(MF.THREAT_ROWS[1], math.min(MF.THREAT_ROWS[2], n))
    DUI:Set("InfoPanel", ns.Windows.Path(h.id) .. ".width", w)
    DUI:Set("InfoPanel", ns.Windows.Path(h.id) .. ".rows", n)
end

-- A threat window laid out: its size from its width and rows.
local function layoutThreat(db, h, e)
    local P, cfg = ns.Panel, e.cfg
    h.cfg = cfg
    local edge = Pixel.Px(h.body, Style.BorderPx(h.body)) + P.PAD
    local n = math.max(MF.THREAT_ROWS[1], math.min(MF.THREAT_ROWS[2], tonumber(cfg.rows) or 6))
    local W = cfg.width
    h.frame:SetSize(W + 2 * edge, threatHeight(h, cfg, n) + 2 * edge)
    h.frame:SetResizeBounds(100 + 2 * edge, threatHeight(h, cfg, MF.THREAT_ROWS[1]) + 2 * edge,
        280 + 2 * edge, threatHeight(h, cfg, MF.THREAT_ROWS[2]) + 2 * edge)
    local rowsTop, barLeft, barWidth = ns.ThreatView.Layout(h.view, cfg, edge, W + 2 * edge, n, ns.Meter.SPACING)
    h.geo = { barLeft = barLeft, barWidth = barWidth, rowsTop = rowsTop, rowH = cfg.rowHeight, gap = ns.Meter.SPACING }
    h.view.empty:ClearAllPoints()
    h.view.empty:SetPoint("CENTER", h.body, "CENTER", 0, -(rowsTop - edge) / 2)
    h.snap = true
end

-- Sizes and shows one window from its settings.
function MF.Layout(db, h, e)
    local P, cfg = ns.Panel, e.cfg
    P.Look(h.body, P.MeterBack(db, cfg), cfg.border)
    local edge = Pixel.Px(h.body, Style.BorderPx(h.body)) + P.PAD
    if h.kind == "threat" then
        layoutThreat(db, h, e)   -- as tall as its rows
    else
        h.frame:SetSize(cfg.width + 2 * edge, cfg.height + 2 * edge)
        local lo, hi = P.METER_MIN, P.METER_MAX
        if h.kind == "summary" then lo, hi = MF.SUMMARY_MIN, MF.SUMMARY_MAX end
        h.frame:SetResizeBounds(lo[1] + 2 * edge, lo[2] + 2 * edge, hi[1] + 2 * edge, hi[2] + 2 * edge)
    end
    Style.LayoutShell(Style.GetShell(h.body))
    -- Pinned by two corners, so it stretches with the window as it's resized.
    h.area:ClearAllPoints()
    h.area:SetPoint("TOPLEFT", h.body, "TOPLEFT", edge, -edge)
    h.area:SetPoint("BOTTOMRIGHT", h.body, "BOTTOMRIGHT", -edge, edge)
    if h.kind ~= "threat" then h.area:SetSize(cfg.width, cfg.height) end   -- (its size before the first layout)
    local wanted = MF.Wanted(e, h)
    h.laidWanted = wanted
    ease(h, wanted)
    DUI.Movers.Suspend(MF.Key(h.id), cfg.enabled ~= true)
    MF.UpdateGrip(h, cfg)
    if h.kind == "threat" then
        if wanted then h.Draw() end
    else
        h.view.Apply(cfg)
    end
end

-- The threat meter's ticker (5 a second while anything's out) draws the
-- player's own threat windows that show; snap: a new target, no glide.
function MF.ThreatTick(snap)
    for _, h in pairs(MF.hosts) do
        if h.kind == "threat" and not h.dead and h.frame:IsShown() then
            if snap then h.snap = true end
            h.Draw()
        end
    end
end

-- A window no longer on the list: away for good.
local function retire(h)
    h.dead = true
    if h.view then h.view.dead = true end
    if ns.BreakdownWindow then ns.BreakdownWindow.MeterGone(h.view) end
    -- The report open for it goes too.
    local R = ns.Report
    if R and R.meter == h.view and R.frame and DUI.Motion.Shown(R.frame) then
        R.meter, R.who = nil, nil
        DUI.Motion.Vanish(R.frame)
    end
    h.laidWanted = false
    ease(h, false)
    DUI.Movers.Suspend(MF.Key(h.id), true)
    h.grip:Hide()
end

-- Every window on the list made and laid out; any no longer there, retired.
function MF.Sync(mod)
    local db = mod.db
    ns.Windows.Fill(db)
    local live = {}
    for _, e in ipairs(ns.Windows.Own(db)) do
        if Windows_KINDS[e.kind] then
            live[e.id] = true
            local h = MF.hosts[e.id]
            -- The same id as another kind now (a profile refilled in place):
            -- the old inside put away, a new one of its kind in the same frame.
            if h and h.kind ~= e.kind then
                if not h.dead then retire(h) end
                h.view.dead = true
                h.body:Hide()
                fill(h, e, mod)
            end
            h = h or make(e, mod)
            h.dead, h.view.dead = false, false
            -- Each on its own: one that fails can't keep the rest from showing.
            DUI.SafeCall(MF.Layout, db, h, e)
        end
    end
    for id, h in pairs(MF.hosts) do
        if not live[id] and not h.dead then retire(h) end
    end
end

-- Whether any window's visibility should change (combat, roster, zone).
-- Runs on every roster change, which is frequent in raids, so it allocates nothing.
local probe = {}
function MF.Changed(db)
    local m = db.meters
    if type(m) ~= "table" or type(m.windows) ~= "table" then return false end
    for id, h in pairs(MF.hosts) do
        local cfg = m.windows[id]
        if not h.dead and type(cfg) == "table" then
            probe.id, probe.cfg = id, cfg
            if MF.Wanted(probe, h) ~= h.laidWanted then return true end
        end
    end
    return false
end

-- Each live window's meter.
function MF.MarkDirty()
    for _, h in pairs(MF.hosts) do
        if not h.dead and h.view.MarkDirty then h.view.MarkDirty() end
    end
end

-- The shown windows of a kind (the fades' lists): out is refilled.
function MF.Frames(kind, out)
    for _, h in pairs(MF.hosts) do
        if h.kind == kind and not h.dead and h.frame:IsShown() then out[#out + 1] = h.frame end
    end
    return out
end

function MF.Build(mod)
    -- Unlocked, a threat window is out with its sample, to be placed (test
    -- mode lays the whole panel out again already).
    DUI.On("UnlockChanged", function() DUI.SafeCall(MF.Sync, mod) end)
    DUI.On("StyleChanged", function()
        for _, h in pairs(MF.hosts) do
            if h.kind == "threat" then ns.ThreatView.Paint(h.view) end
        end
    end)
end
