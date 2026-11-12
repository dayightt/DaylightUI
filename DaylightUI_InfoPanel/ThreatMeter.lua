-- Threat meter. By default it slides out from behind the damage meter's outer
-- edge (TM.Side) in combat while grouped. A tab on its edge toggles it by hand
-- until the next fight starts or ends. Its contents come from ThreatView.lua:
-- one row per group member on the mob's threat list, and a pull line at 110%
-- of the tank's threat in melee or 130% at range.
--
-- threat.at = "below" docks it along the damage meter's bottom, and the meter's
-- rows make room (Meter.Reserve). Docked either way, it only shows with the
-- meter. threat.at = "free" makes it its own movable, resizable window.
--
-- Against bosses the numbers are secret: they go straight into bars and text,
-- never sorted or compared. Rows then use a fixed order (tanks, you, the
-- rest) and there's no pull line.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel = DUI.Style, DUI.Pixel

local TM = {}
ns.ThreatMeter = TM

TM.TICK = 0.2               -- seconds between redraws while it's out
TM.MARGIN = 6               -- room round the window for its shadow, inside the clip
TM.TAB = { 10, 22 }         -- the slide tab's width and height
TM.TAB_TOP = 6              -- from the window's top edge
TM.GLYPH = { 6, 2, 2 }      -- the tab's little meter mark: bar width, height, gap
TM.PAD = 3                  -- inside the window's border
TM.PAGE = "InfoPanel.meter"   -- the Meters page; its sample shows while the threat meter is picked there
-- Header: the accent (a pop, repainted on a style change); "No target": a warm label.
TM.MIN_ROWS = 2             -- the window is never shorter than this many rows
TM.ARROW_CLEAR = 4          -- the window this close above the panel's fold tab counts as over it
TM.BELOW_GAP = 4
TM.MOVER = "infopanel.threat"
TM.FREE_MIN_W, TM.FREE_MAX_W = 100, 280   -- the Width slider's range
TM.ROWS_RANGE = { 2, 10 }                 -- the Rows slider's range            -- under the meter: between the meter's last row and it

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A sample group for test mode and the options page: a tank, you close to
-- pulling, the rest below. Scaled percent and raw threat, as the game gives.
TM.SAMPLE = {
    { name = "Kaladin", class = "WARRIOR", scaled = 100, value = 12400, tank = true },
    { me = true, scaled = 84, value = 11458 },
    { name = "Shallan", class = "MAGE", scaled = 70, value = 11284 },
    { name = "Jasnah", class = "WARLOCK", scaled = 61, value = 9833 },
    { name = "Lift", class = "ROGUE", scaled = 48, value = 6547 },
    { name = "Navani", class = "PRIEST", scaled = 20, value = 3224 },
}
TM.SAMPLE_TARGET = "Sadeas"
TM.SAMPLE_PULL = 13640       -- your pull line in the sample: the tank's threat x 1.1

DUI.RegisterTestPart("threat", "Threat meter", 91, function()
    return ns.module ~= nil and ns.module.db.threat.enabled == true
end)

-- An anchor at the panel's top-left that widens by however far the threat
-- meter sticks out, so the buffs slide aside with it. Created at file load
-- because the Buffs module finds it by name.
local edge = CreateFrame("Frame", "DaylightUIInfoPanelEdge", ns.Panel.panel)
edge:SetPoint("TOPRIGHT", ns.Panel.panel, "TOPLEFT", 0, 0)
edge:SetSize(0.001, 1)
TM.edge = edge

local cfg
local clip, win, tab, slider, line, free, grip
local rows = {}
TM.manual = nil              -- the tab's choice (true/false) until the next fight starts or ends

-- Test mode with its box ticked, or its options page open: the sample.
function TM.Sample()
    if DUI.testMode and DUI.TestPartShown("threat") then return true end
    if DUI.Movers.unlocked and cfg and cfg.at == "free" and cfg.enabled then return true end
    local P = DUI.OptionsPanel
    return P ~= nil and P.IsShown() and P.Current() == TM.PAGE and ns.MeterOptions ~= nil and ns.MeterOptions.picked == "threat"
end

-- The mob a threat window reads: target, focus, or "smart" (your target if
-- attackable, else your target's target, for healers). nil when there's none.
local function attackable(u)
    if not UnitExists(u) then return false end
    local ok, v = pcall(UnitCanAttack, "player", u)
    return not ok or isSecret(v) or v == true
end
function TM.Mob(pick)
    if pick == "focus" then return attackable("focus") and "focus" or nil end
    if pick == "smart" then
        if attackable("target") then return "target" end
        if attackable("targettarget") then return "targettarget" end
        return nil
    end
    return "target"
end

-- Whether a player-made threat window should show: in combat, only when
-- someone else could hold the mob (never solo), and only as tank if set so.
function TM.WindowWanted(cfg, sample)
    if not (cfg and cfg.enabled) then return false end
    if sample then return true end
    -- The panel's own flag: set before it lays the windows out on a pull.
    if not (ns.Panel.inCombat and DUI.Threat.Shared()) then return false end
    if cfg.auto == "tank" and not DUI.Threat.IsTank() then return false end
    return true
end

-- Whether it should be out right now.
function TM.Wanted()
    if not (cfg and cfg.enabled and TM.host) then return false end
    if TM.Sample() then return true end
    if TM.manual ~= nil then return TM.manual end
    local auto = cfg.auto
    if auto ~= "group" and auto ~= "tank" then return false end
    if not (TM.inCombat and DUI.Threat.Shared()) then return false end
    if auto == "tank" and not DUI.Threat.IsTank() then return false end
    return true
end

-- ---------------------------------------------------------------------
-- What to show
-- ---------------------------------------------------------------------

-- The group's units, worked out again only when the roster changes (or its
-- size or raid flag does): this runs five times a second in a fight.
local units = {}
local RAID, PARTY = {}, {}
for i = 1, 40 do RAID[i] = "raid" .. i end
for i = 1, 4 do PARTY[i] = "party" .. i end
local rosterDirty, lastRaid, lastN = true, nil, nil
-- true / false, nil when the client won't say (secret): asked again next time.
local function isPlayer(u)
    local ok, v = pcall(UnitIsUnit, u, "player")
    if not ok or isSecret(v) then return nil end
    return v == true
end
local function groupUnits()
    local ok, raid = pcall(IsInRaid)
    raid = ok and raid == true
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if isSecret(n) or type(n) ~= "number" then n = 0; rosterDirty = true end
    if not rosterDirty and raid == lastRaid and n == lastN then return units end
    rosterDirty, lastRaid, lastN = false, raid, n
    for i = #units, 1, -1 do units[i] = nil end
    units[1] = "player"
    units[2] = "pet"         -- none out: the game has no answer for it, so no row
    if raid then
        for i = 1, math.min(n, #RAID) do
            local me = isPlayer(RAID[i])
            if me == nil then rosterDirty = true end
            if not me then units[#units + 1] = RAID[i] end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            if UnitExists(PARTY[i]) then units[#units + 1] = PARTY[i] end
        end
    end
    return units
end
function TM.RosterChanged() rosterDirty = true end

local function classOf(u)
    if UnitClassBase then
        local ok, c = pcall(UnitClassBase, u)
        if ok then return c end
    end
    local ok, _, c = pcall(UnitClass, u)
    if ok then return c end
end

local function role(u)
    local ok, r = pcall(UnitGroupRolesAssigned, u)
    if ok and not isSecret(r) then return r end
end

-- Entries are kept and reused (this runs five times a second in a fight).
local pool, list, ordered = {}, {}, {}
local function entry(i)
    local e = pool[i] or {}
    pool[i] = e
    e.unit, e.name, e.class, e.scaled, e.value, e.tank, e.me, e.taken = nil, nil, nil, nil, nil, nil, nil, nil
    return e
end
local function byThreat(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.tank == true and b.tank ~= true
end

-- Returns the rows, whether they're secret (no sorting, no pull line), the
-- pull line's value and the bars' max, or nil without a mob. `mob` defaults to
-- the target; `sample` uses sample data. The list is reused by the next call,
-- so draw it first.
function TM.Collect(maxRows, mob, sample)
    for i = #list, 1, -1 do list[i] = nil end
    if sample == nil then sample = TM.Sample() end
    mob = mob or "target"
    if sample then
        for i, s in ipairs(TM.SAMPLE) do
            local e = entry(i)
            e.scaled, e.value, e.tank, e.me = s.scaled, s.value, s.tank, s.me
            if s.me then
                e.unit, e.name, e.class = "player", DUI.UnitName("player", "threat"), classOf("player")
            else
                e.name, e.class = s.name, s.class
            end
            list[#list + 1] = e
        end
        table.sort(list, byThreat)
        for i = #list, maxRows + 1, -1 do list[i] = nil end
        return list, false, TM.SAMPLE_PULL, TM.SAMPLE_PULL
    end
    if not UnitExists(mob) then return nil end
    local ok, attackable = pcall(UnitCanAttack, "player", mob)
    if ok and not isSecret(attackable) and attackable ~= true then return nil end
    local secret = DUI.Threat.ValuesSecret("player", mob)
    local n = 0
    for _, u in ipairs(groupUnits()) do
        local fine, tanking, status, scaled, _, value = pcall(UnitDetailedThreatSituation, u, mob)
        if fine and type(status) ~= "nil" then
            if isSecret(status) or isSecret(scaled) or isSecret(value) or isSecret(tanking) then secret = true end
            n = n + 1
            local e = entry(n)
            e.unit, e.scaled, e.value, e.tank, e.me = u, scaled, value, tanking, u == "player"
            list[n] = e
        end
    end
    if secret then
        -- Tanks (by role), you, then the group's order: never by the numbers.
        for i = #ordered, 1, -1 do ordered[i] = nil end
        for pass = 1, 3 do
            for _, e in ipairs(list) do
                if not e.taken and #ordered < maxRows
                   and (pass == 3 or (pass == 1 and role(e.unit) == "TANK") or (pass == 2 and e.me)) then
                    e.taken = true
                    ordered[#ordered + 1] = e
                end
            end
        end
        for i = #list, 1, -1 do list[i] = nil end
        for i, e in ipairs(ordered) do e.tank = nil; list[i] = e end
    else
        for _, e in ipairs(list) do
            if type(e.value) ~= "number" then e.value = 0 end
            if type(e.scaled) ~= "number" then e.scaled = 0 end
            e.tank = e.tank == true
        end
        table.sort(list, byThreat)
        -- The top ones, and you even when you're further down.
        local mine
        for i, e in ipairs(list) do if e.me then mine = i end end
        if mine and mine > maxRows and maxRows > 0 then list[maxRows] = list[mine] end
        for i = #list, maxRows + 1, -1 do list[i] = nil end
    end
    for _, e in ipairs(list) do
        e.name = DUI.UnitName(e.unit, "threat")
        e.class = classOf(e.unit == "pet" and "player" or e.unit)   -- a pet wears its owner's color
    end
    if secret then return list, true end
    -- The pull line: where your threat would turn it, from the game's own
    -- percent (it knows your range); with none yet, the tank's x 1.1.
    local pull, tankValue, top = nil, nil, 0
    local me
    for _, e in ipairs(list) do
        if e.tank then tankValue = e.value end
        if e.me then me = e end
        if e.value > top then top = e.value end
    end
    if me and not me.tank and me.scaled > 0 and me.value > 0 then
        pull = me.value * 100 / me.scaled
    elseif tankValue and not (me and me.tank) then
        pull = tankValue * DUI.Threat.PULL
    end
    if pull and pull > top then top = pull end
    if top <= 0 then top = 1 end
    return list, false, pull, top
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

function TM.Draw()
    if not (win and cfg) then return end
    local n = TM.RowCount()
    local data, secret, pull, top = TM.Collect(n)
    local mob, mobUnit = "", nil
    if data and TM.Sample() then
        mob = TM.SAMPLE_TARGET
    elseif data then
        mob, mobUnit = DUI.UnitName("target", "threat"), "target"
    end
    local count = data and #data or 0
    -- As tall as the rows it shows (at least TM.MIN_ROWS), so a small party
    -- doesn't sit in a box of empty rows; without a target, that small body
    -- holds "No target" in its middle.
    local fresh = not data and not win.empty:IsShown()
    win.empty:SetShown(not data)
    if fresh then DUI.Motion.Fade(win.empty, 0, 1, DUI.Motion.FAST) end   -- eases in, never waits
    local fit = math.min(n, math.max(count, TM.MIN_ROWS))
    if fit ~= TM.shown then
        TM.shown = fit
        local g = TM.geo
        TM.height = g.H - (n - fit) * (g.rowH + ns.Meter.SPACING)
        win:SetHeight(TM.height)
        if not (TM.below or TM.free) then clip:SetHeight(TM.height + 2 * TM.MARGIN) end
        TM.ApplySlide()
    end
    ns.ThreatView.Draw(TM.view, cfg, data, secret, pull, top, mob, mobUnit, TM.geo, TM.snap)
    TM.snap = false
end

-- ---------------------------------------------------------------------
-- Layout and the slide
-- ---------------------------------------------------------------------

-- The frame it attaches to: the detached meter window if shown, else the
-- panel. Docked, it goes away entirely while the damage meter is hidden.
local function host()
    local P = ns.Panel
    if P.laidWanted ~= true then return nil end
    if ns.module.db.meter.detached and P.meterFrame:IsShown() then return P.meterFrame end
    if P.panel:IsShown() then return P.panel end
    return nil
end

-- Under the meter: picked, and the meter laid out in view (in the panel or
-- its own window).
function TM.Below()
    if not (cfg and cfg.at == "below") then return false end
    return ns.Panel.laidWanted == true and ns.module.db.meter.enabled == true
end

-- The header's height (ThreatView.HEAD; none with threat.header "off").
function TM.HeadHeight()
    return (cfg and cfg.header == "off") and 0 or ns.ThreatView.HEAD
end

-- How many rows it can show where it is.
function TM.RowCount()
    if TM.below then return cfg.belowRows or 3 end
    return cfg.rows
end

-- The side it slides out of: the panel's meter side, or for a detached meter
-- window, the side facing the screen's middle.
function TM.Side(h)
    local P = ns.Panel
    if h ~= nil and h == P.panel then return P.side == "right" and "right" or "left" end
    if h ~= nil and h == P.meterFrame then
        local x = DUI.Movers.Position("infopanel.meter")
        if type(x) == "number" and x < 0 then return "right" end
    end
    return "left"
end

-- The size its host is drawn at, by the host's mover.
local function hostScale(h)
    local key = "infopanel"
    if h == free then key = TM.MOVER elseif h ~= nil and h == ns.Panel.meterFrame then key = "infopanel.meter" end
    return DUI.Movers.Scale(key)
end

function TM.Layout()
    local own = cfg.at == "free"
    TM.free = own
    local h = own and free or host()
    TM.host = h
    local below = not own and TM.Below() and h ~= nil
    TM.below = below
    TM.side = TM.Side(h)
    local right = TM.side == "right"
    DUI.Movers.Suspend(TM.MOVER, not own)
    TM.UpdateGrip()
    local s = Style.GetShell(win)
    -- Under the meter it's part of the panel: no box of its own, a hairline
    -- over it instead.
    local framed = cfg.border ~= false and not below
    s.opts.bgAlpha = below and 0 or ns.Panel.BackAlpha(ns.module and ns.module.db or {})
    s.opts.noBorder = not framed
    s.opts.shadowAlpha = not framed and 0 or nil
    s.opts.noBevel = not framed
    win.divider:SetShown(below)
    local T = below and 0 or Pixel.Px(win, Style.BorderPx(win))
    local inset = below and 0 or T + TM.PAD
    local rowH, gap = cfg.rowHeight, ns.Meter.SPACING
    local headH = TM.HeadHeight()
    local n = TM.RowCount()
    local W = below and ns.module.db.meter.width or cfg.width
    local H = 2 * inset + headH + n * (rowH + gap) - gap
    win:SetSize(W, H)
    Style.LayoutShell(s)
    local rowsTop, barLeft, barWidth = ns.ThreatView.Layout(TM.view, cfg, inset, W, n, gap)
    win.empty:ClearAllPoints()
    win.empty:SetPoint("CENTER", win, "TOP", 0, -(inset + headH + (math.min(n, TM.MIN_ROWS) * (rowH + gap) - gap) / 2))
    win.divider:ClearAllPoints()
    win.divider:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    win.divider:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    win.divider:SetHeight(Pixel.Px(win, 1))
    TM.geo = { barLeft = barLeft, barWidth = barWidth, rowsTop = rowsTop, rowH = rowH, gap = gap,
               W = W, H = H, T = T }
    TM.height = H
    clip:ClearAllPoints()
    win:ClearAllPoints()
    if below then
        -- Into the meter's bottom: the clip grows up from its bottom edge and
        -- the window rises into it.
        local area = ns.Panel.meterArea
        clip:SetParent(area)
        clip:SetFrameLevel(area:GetFrameLevel() + 5)
        win:SetFrameLevel(clip:GetFrameLevel() + 1)
        clip:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT")
        clip:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
        win:SetPoint("TOPLEFT", clip, "TOPLEFT")
        win:SetPoint("TOPRIGHT", clip, "TOPRIGHT")
        local hT = Pixel.Px(h, Style.BorderPx(h))
        TM.hostT = hT
        tab:SetFrameLevel(math.max(0, h:GetFrameLevel() - 1))
        tab:SetSize(TM.TAB[1] + hT, TM.TAB[2])
        Style.LayoutShell(Style.GetShell(tab))
        TM.Restore()
    elseif own then
        -- Its own window: the clip fills it (the room for the shadow round
        -- the box), the box at its top, as tall as its rows.
        clip:SetParent(free)
        clip:SetAllPoints(free)
        clip:SetFrameLevel(free:GetFrameLevel())
        win:SetFrameLevel(free:GetFrameLevel() + 1)
        free:SetSize(W + 2 * TM.MARGIN, H + 2 * TM.MARGIN)
        free:SetResizeBounds(TM.FREE_MIN_W + 2 * TM.MARGIN, TM.MinHeight() + 2 * TM.MARGIN,
            TM.FREE_MAX_W + 2 * TM.MARGIN, TM.MaxHeight() + 2 * TM.MARGIN)
        ns.Meter.Reserve(0)
        TM.Restore()
    else
        clip:SetParent(UIParent)
        clip:SetFrameStrata("LOW")
        ns.Meter.Reserve(0)
    end
    -- On UIParent beside its host: drawn at the host's size (the master
    -- Scale times the host's own); inside the meter or its own window it
    -- takes theirs.
    local size = hostScale(h)
    clip:SetScale((below or own) and 1 or size)
    tab:SetScale(size)
    -- Into the clip, which grows out of the host's edge on its side.
    local M = TM.MARGIN
    if not below then
        if right and not own then
            win:SetPoint("TOPRIGHT", clip, "TOPRIGHT", -M, -M)
        else
            win:SetPoint("TOPLEFT", clip, "TOPLEFT", M, -M)
        end
    end
    if h and not below and not own then
        local hT = Pixel.Px(h, Style.BorderPx(h))
        TM.hostT = hT
        -- Top edges level as they're seen: a box with no border starts its
        -- background a border's width inside its frame.
        local drop = (Style.GetShell(h).opts.noBorder and hT or 0) - (framed and 0 or T)
        TM.hostDrop = drop
        if right then
            clip:SetPoint("TOPLEFT", h, "TOPRIGHT", -hT, M - drop)
        else
            clip:SetPoint("TOPRIGHT", h, "TOPLEFT", hT, M - drop)
        end
        clip:SetHeight(H + 2 * M)
        -- Behind the host, so it tucks under its edge.
        local level = math.max(0, h:GetFrameLevel() - 3)
        clip:SetFrameLevel(level)
        win:SetFrameLevel(level + 1)
        tab:SetFrameLevel(level + 1)
        tab:SetSize(TM.TAB[1] + hT, TM.TAB[2])
        Style.LayoutShell(Style.GetShell(tab))
    end
    TM.shown = nil            -- the next draw fits the height to its rows
    TM.snap = true
    -- The first layout jumps; later ones (a setting) carry on from where it is.
    TM.Update(TM.placed == true)
    TM.placed = true
end

-- Out or in: towards where it should be (glide = slide, else jump).
function TM.Update(glide)
    if not slider then return end
    local goal = TM.Wanted() and 1 or 0
    if glide and TM.host and TM.host:IsVisible() then slider:To(goal) else slider:Jump(goal) end
    TM.ApplySlide()
end

-- The panel's fold tab back on the panel's own edge (the beside spot moves it).
function TM.Restore()
    ns.Panel.PlaceArrow(0)
end

-- Its own window: fades in and out where it was put.
local function slideFree(on, p)
    clip:SetShown(on and (p > 0 or slider.goal == 1))
    tab:Hide()
    if TM.pushed ~= 0 then
        TM.pushed = 0
        edge:SetWidth(0.001)
    end
    win:SetAlpha(p)
end

-- Under the meter. Out (or on its way) the meter's rows stop short of it;
-- the room goes back once it's all the way in.
local function slideBelow(on, p)
    clip:SetShown(on and (p > 0 or slider.goal == 1))
    tab:SetShown(on)
    if TM.pushed ~= 0 then
        TM.pushed = 0
        edge:SetWidth(0.001)
    end
    local out = on and (p > 0 or slider.goal == 1)
    ns.Meter.Reserve(out and TM.height + TM.BELOW_GAP or 0)
    if not on then return end
    clip:SetHeight(math.max(0.01, p * TM.height))
    win:SetAlpha(p)
    -- The tab on the host's edge on the meter's side, level with it.
    tab:ClearAllPoints()
    local y = (ns.Panel.inset or 0) + math.max(0, (TM.height - TM.TAB[2]) / 2)
    if TM.side == "right" then
        tab:SetPoint("BOTTOMLEFT", TM.host, "BOTTOMRIGHT", -(TM.hostT or 0), y)
    else
        tab:SetPoint("BOTTOMRIGHT", TM.host, "BOTTOMLEFT", TM.hostT or 0, y)
    end
end

function TM.ApplySlide()
    if not (slider and TM.geo) then return end
    local p, g, h = slider.p, TM.geo, TM.host
    local on = h ~= nil and cfg.enabled == true
    if TM.below or TM.free then
        if TM.below then slideBelow(on, p) else slideFree(on, p) end
        if on and p > 0 and not TM.drawn then
            TM.drawn = true
            TM.Draw()
        end
        if p == 0 then TM.drawn = nil end
        return
    end
    clip:SetShown(on and (p > 0 or slider.goal == 1))
    tab:SetShown(on)
    local right = TM.side == "right"
    -- Only out of the panel's left edge does it push the buffs' anchor.
    local push = (on and h == ns.Panel.panel and not right) and p * (g.W - g.T) or 0
    if push ~= TM.pushed then
        TM.pushed = push
        edge:SetWidth(math.max(0.001, push))
    end
    if not on then return end
    clip:SetWidth(math.max(0.01, p * (g.W + TM.MARGIN)))
    win:SetAlpha(p)
    -- The tab rides the window's outer edge (the host's while it's in).
    local hT = TM.hostT or 0
    local out = p * (g.W - g.T)
    local y = -(TM.TAB_TOP + hT + (TM.hostDrop or 0))
    tab:ClearAllPoints()
    if right then
        tab:SetPoint("TOPLEFT", h, "TOPRIGHT", out - hT, y)
    else
        tab:SetPoint("TOPRIGHT", h, "TOPLEFT", hT - out, y)
    end
    -- The panel's fold tab (centered on its edge) stays there, unless
    -- the window reaches down over it: then it rides the window's edge.
    -- Pushed out past a short window it floated in the open.
    local P = ns.Panel
    if h == P.panel and P.arrow then
        local tabTop = (P.panel:GetHeight() - ns.Panel.TAB[2]) / 2
        local covered = (TM.height or g.H) + TM.ARROW_CLEAR > tabTop
        P.PlaceArrow(covered and out or 0)
    end
    if p > 0 and not TM.drawn then
        TM.drawn = true
        TM.Draw()
    end
    if p == 0 then TM.drawn = nil end
end

-- The mouse over it or its tab: the panel's fold tab and this one show.
function TM.MouseNear()
    if not (clip and clip:IsShown()) then return false end
    return (win:IsMouseOver() or tab:IsMouseOver()) == true
end

-- ---------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------

function TM.Build(mod)
    cfg = mod.db.threat
    clip = CreateFrame("Frame", nil, UIParent)
    clip:SetFrameStrata("LOW")
    clip:SetClipsChildren(true)
    clip:Hide()
    TM.clip = clip
    win = CreateFrame("Frame", "DaylightUIThreatMeter", clip)
    Style.Shell(win, {})
    win.divider = win:CreateTexture(nil, "ARTWORK")
    win.divider:SetColorTexture(1, 1, 1, 0.08)
    win.divider:Hide()
    local view = ns.ThreatView.New(win)
    TM.view = view
    win.header, win.empty = view.mob, view.empty
    DUI.On("StyleChanged", function() ns.ThreatView.Paint(view) end)
    rows, line = view.rows, view.line
    TM.win, TM.line, TM.rows = win, line, rows

    -- The tab: framed like the panel's fold tab, with a tiny meter mark
    -- (three bars, shortest at the bottom), gray and the accent on hover.
    tab = CreateFrame("Button", nil, UIParent)
    tab:SetFrameStrata("LOW")
    Style.Shell(tab, { borderPx = ns.Panel.XP_BORDER })
    tab.glyph = {}
    local gw, gh, gap = TM.GLYPH[1], TM.GLYPH[2], TM.GLYPH[3]
    for i = 1, 3 do
        local t = tab:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSize(gw * (1.15 - i * 0.2), gh)
        t:SetPoint("TOPLEFT", tab, "CENTER", -gw / 2 - 1, (gh + gap) * 1.5 - (i - 1) * (gh + gap))
        tab.glyph[i] = t
    end
    local function tint(r, g, b) for _, t in ipairs(tab.glyph) do t:SetVertexColor(r, g, b, 1) end end
    local grey = ns.Panel.ARROW_COLOR
    tint(grey[1], grey[2], grey[3])
    tab:SetScript("OnClick", function()
        TM.manual = not TM.Wanted()
        TM.Update(true)
    end)
    tab:SetScript("OnEnter", function()
        -- Each bar of the glyph its spot along the accent, top to bottom.
        local n = #tab.glyph
        for i, t in ipairs(tab.glyph) do t:SetVertexColor(Style.AccentAt(n > 1 and (i - 1) / (n - 1) or nil)) end
        if GameTooltip then
            GameTooltip:SetOwner(tab, TM.side == "right" and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
            DUI.Tips.Clear()
            DUI.Tips.Title(L["Threat meter"])
            DUI.Tips.Hint(L["Click: slide it out or back"])
            DUI.Tips.Flush(GameTooltip)
            GameTooltip:Show()
        end
    end)
    tab:SetScript("OnLeave", function()
        tint(grey[1], grey[2], grey[3])
        if GameTooltip then GameTooltip:Hide() end
    end)
    TM.tab = tab

    -- Its own window (threat.at = "free"): a frame of ours the unlock mode
    -- moves, starting just left of the panel, and its resize grip.
    free = CreateFrame("Frame", "DaylightUIThreatMeterFrame", UIParent)
    free:SetFrameStrata("LOW")
    free:SetSize(cfg.width + 2 * TM.MARGIN, 100)
    free:SetResizable(true)
    TM.freeFrame = free
    DUI.Movers.Register(free, TM.MOVER, "Threat Meter", { "TOPRIGHT", "DaylightUIInfoPanel", "TOPLEFT", -30, 0 },
        { active = function() return cfg and cfg.enabled and cfg.at == "free" end })
    DUI.Movers.Suspend(TM.MOVER, cfg.at ~= "free")
    grip = CreateFrame("Button", nil, free)
    grip:SetSize(ns.Panel.GRIP, ns.Panel.GRIP)
    grip:SetPoint("BOTTOMRIGHT", free, "BOTTOMRIGHT", -TM.MARGIN - 2, TM.MARGIN + 2)
    -- Above unlock mode's handles, which cover the window.
    grip:SetFrameStrata("FULLSCREEN")
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() free:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        free:StopMovingOrSizing()
        TM.Resized(free:GetWidth() - 2 * TM.MARGIN, free:GetHeight() - 2 * TM.MARGIN)
    end)
    grip:Hide()
    TM.grip = grip
    DUI.On("UnlockChanged", function()
        TM.UpdateGrip()
        TM.snap = true
        TM.Update(true)
    end)
    -- Hidden until the mouse is near the panel, window or tab, like the
    -- panel's fold tab.
    tab:SetAlpha(0)
    local near, alpha = false, 0
    local function paint(v) alpha = v; tab:SetAlpha(v) end
    local function watch(_, snap)
        local h = TM.host
        local reach = TM.TAB[1] + 10
        local left = TM.side ~= "right"
        local now = (h and h:IsMouseOver(0, 0, left and -reach or 0, left and 0 or reach))
            or ns.Panel.holder:IsMouseOver() or TM.MouseNear() or false
        now = now == true
        if now ~= near or snap then
            near = now
            DUI.Motion.Tween("infopanel:threatTab", alpha, now and 1 or 0, snap and 0 or DUI.Motion.FAST, paint)
        end
    end
    ns.Panel.WatchHover(tab, watch)

    slider = DUI.Motion.Slider(function() TM.ApplySlide() end, { p = 0, dur = DUI.Motion.NORMAL })
    TM.slider = slider

    -- The player's own threat windows fade with it too.
    local fadeList = {}
    DUI.Fade.Register{ key = "InfoPanel.threat", scope = "InfoPanel", path = "threat.fade", page = TM.PAGE, whole = true,
        frames = function()
            for i = #fadeList, 1, -1 do fadeList[i] = nil end
            fadeList[1] = clip
            return ns.MeterFrame.Frames("threat", fadeList)
        end }

    -- A new fight (or its end) hands the slide back to the automatic rule.
    -- (Its own flag: the lockdown starts just after the event.)
    TM.inCombat = InCombatLockdown() and true or false
    local function fight(event)
        TM.inCombat = event == "PLAYER_REGEN_DISABLED"
        TM.manual = nil
        TM.Update(true)
    end
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", fight)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", fight)
    DUI.RegisterEvent("GROUP_ROSTER_UPDATE", function() TM.RosterChanged(); TM.Update(true) end)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", TM.RosterChanged)
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function()
        TM.snap = true
        if clip:IsShown() then TM.Draw() end
        ns.MeterFrame.ThreatTick(true)
    end)
    DUI.On("TestModeChanged", function() TM.snap = true; TM.Update(true) end)
    DUI.On("TestPartChanged", function(key) if key == "threat" then TM.snap = true; TM.Update(true) end end)
    DUI.On("SettingChanged", function()
        for _, row in ipairs(rows) do row.painted, row.mine = nil, nil end
    end)
    -- Five times a second: follows the options page opening, and redraws
    -- while it's out.
    C_Timer.NewTicker(TM.TICK, function()
        if not cfg then return end
        local goal = TM.Wanted() and 1 or 0
        if goal ~= slider.goal then TM.Update(true) end
        if clip:IsShown() and (slider.p > 0) then TM.Draw() end
        ns.MeterFrame.ThreatTick()
    end)
end

-- The grip shows on its own window while the UI is unlocked.
function TM.UpdateGrip()
    if grip then grip:SetShown(DUI.Movers.unlocked and cfg and cfg.enabled and cfg.at == "free" or false) end
end

-- The window's height for a number of rows (the box, not the room round it).
local function heightFor(n)
    local T = Pixel.Px(win, Style.BorderPx(win))
    local inset = T + TM.PAD
    return 2 * inset + TM.HeadHeight() + n * (cfg.rowHeight + ns.Meter.SPACING) - ns.Meter.SPACING
end
function TM.MinHeight() return heightFor(TM.ROWS_RANGE[1]) end
function TM.MaxHeight() return heightFor(TM.ROWS_RANGE[2]) end

-- Let go of the grip: keeps where it sits, then the width and as many rows
-- as fit the height (the box snaps to whole rows).
function TM.Resized(w, h)
    local step = cfg.rowHeight + ns.Meter.SPACING
    local n = math.floor((h - heightFor(0) - ns.Meter.SPACING) / step + 0.5)
    n = math.max(TM.ROWS_RANGE[1], math.min(TM.ROWS_RANGE[2], n))
    w = math.max(TM.FREE_MIN_W, math.min(TM.FREE_MAX_W, math.floor(w + 0.5)))
    DUI.Movers.Save(TM.MOVER)
    DUI:Set("InfoPanel", "threat.width", w)
    DUI:Set("InfoPanel", "threat.rows", n)
    TM.Layout()
end

function TM.Apply(c)
    cfg = c
    TM.Layout()
    TM.Draw()
end
