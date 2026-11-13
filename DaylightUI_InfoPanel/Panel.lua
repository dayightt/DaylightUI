-- The top-right panel: the XP bar across the top, and below it one frame
-- holding the damage meter and the minimap, with data texts under the map.
-- The whole thing moves as one in unlock mode.
--
-- The meter slides out of the minimap's left or right side (Panel.Side). A tab
-- on that edge toggles it, its group/combat options can hide it, and it can
-- be detached into its own window.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Panel = {}
ns.Panel = Panel

Panel.EDGE = 12              -- from the screen's top-right corner
Panel.PAD = 5                -- inside the panel's border, and between its parts
Panel.GAP = 4                -- between the XP frame and the panel
Panel.METER_ONLY_HEIGHT = 150
Panel.ARROW = 12             -- the fold tab's chevron
Panel.TAB = { 14, 34 }       -- the fold tab's width and height
Panel.ARROW_COLOR = { 0.55, 0.55, 0.58 }
-- The detached meter's size limits, as its width and height options'.
Panel.METER_MIN = { 120, 80 }
Panel.METER_MAX = { 320, 500 }
-- The detached experience bar's size limits, as its width and height options'.
Panel.XP_MIN = { 100, 4 }
Panel.XP_MAX = { 2500, 60 }
Panel.GRIP = 16
Panel.SLIDE = 0.3            -- seconds the panel takes to open or fold the meter
-- The XP frame's border: lighter than the panel's, it's a thin strip.
Panel.XP_BORDER = function(px) return math.max(3, math.floor(px * 0.5 + 0.5)) end
-- Default spot for the detached XP bar, under the main action bar. Updated on
-- every layout; the mover keeps this table, so an unmoved bar follows along.
Panel.xpDefault = { "BOTTOM", nil, "BOTTOM", 0, 6 }
Panel.XP_EDGE = 12           -- an upright bar's gap from the screen edge, with no action bar to stand by

-- Hides a game frame by parking it under a hidden parent (never destroyed).
local hidden = CreateFrame("Frame")
hidden:Hide()
Panel.hiddenParent = hidden

function Panel.Park(frame)
    if type(frame) ~= "table" or not frame.SetParent then return end
    if frame:GetParent() ~= hidden then frame:SetParent(hidden) end
end

-- Whether the meter should be up right now: switched on, and in a group or
-- in combat when it's set to wait for those.
-- Test mode with the meter's sample wanted (its test box can untick it:
-- then the meter shows as it would, with the real fights).
function Panel.MeterSample()
    return DUI.testMode and DUI.TestPartShown("meter")
end

DUI.RegisterTestPart("meter", "Meter", 90, function()
    return ns.module ~= nil and ns.module.db.meter.enabled == true
end)

-- rules: whose "only in a group / in combat" (the second meter follows the
-- first's); sample: its test sample wanted (the first meter's by default).
function Panel.MeterWanted(m, rules, sample)
    if not m.enabled then return false end
    if sample == nil then sample = Panel.MeterSample() end
    if sample then return true end
    rules = rules or m
    if rules.inGroup and not IsInGroup() then return false end
    if rules.inCombat and not Panel.inCombat then return false end
    if rules.inInstance and not Panel.InInstance() then return false end
    return true
end

-- In a dungeon, raid, battleground or arena (asked again on each loading
-- screen: the meters' "only in an instance").
function Panel.InInstance()
    if type(IsInInstance) ~= "function" then return false end
    return IsInInstance() == true
end

-- Created at file load, before Edit Mode lays out at login: a saved layout may
-- anchor the durability figure to the body by name, and the game errors if
-- that name doesn't exist yet. The buff bars also find it by name.
Panel.holder = CreateFrame("Frame", "DaylightUIInfoPanel", UIParent)
Panel.panel = CreateFrame("Frame", "DaylightUIInfoPanelBody", Panel.holder)

-- The fold tabs show while the mouse is near. One shared check every
-- HOVER_EVERY s covers all shown tabs, plus an immediate check when one shows.
Panel.HOVER_EVERY = 0.05
local hoverWatch = {}
function Panel.WatchHover(frame, fn)
    hoverWatch[#hoverWatch + 1] = { frame = frame, fn = fn }
    frame:SetScript("OnShow", function(self) fn(self, true) end)
    if Panel.hoverDriver then return end
    local d, t = CreateFrame("Frame"), 0
    d:SetScript("OnUpdate", function(_, dt)
        t = t + (dt or 0)
        if t < Panel.HOVER_EVERY then return end
        t = 0
        for _, w in ipairs(hoverWatch) do
            if w.frame:IsVisible() then w.fn(w.frame, false) end
        end
    end)
    Panel.hoverDriver = d
end

function Panel.Build(mod)
    local holder = Panel.holder
    holder:SetFrameStrata("LOW")

    local xp = CreateFrame("Frame", nil, holder)
    Style.Shell(xp, { borderPx = Panel.XP_BORDER })
    Panel.xp = xp

    local panel = Panel.panel
    Style.Shell(panel)

    -- The meter's own window, for when it's detached.
    local own = CreateFrame("Frame", "DaylightUIDamageMeter", UIParent)
    own:SetFrameStrata("LOW")
    Style.Shell(own)
    own:Hide()
    Panel.meterFrame = own
    Panel.BuildGrip(own, mod)

    -- The parts' areas. The meter sits in a clipping frame that grows with
    -- the panel as it slides open, so the meter comes out from behind the
    -- minimap rather than jumping in.
    Panel.meterClip = CreateFrame("Frame", nil, panel)
    Panel.meterClip:SetClipsChildren(true)
    Panel.meterArea = CreateFrame("Frame", nil, Panel.meterClip)
    Panel.mapArea = CreateFrame("Frame", nil, panel)
    -- The data texts' strip: under the minimap (or the meter, with no map).
    Panel.dataArea = CreateFrame("Frame", nil, panel)
    -- How far the meter is out of the panel (0 folded, 1 open).
    Panel.slide = DUI.Motion.Slider(function() Panel.ApplySlide() end, { dur = Panel.SLIDE })

    -- The fold tab on the meter's side of the panel. Tucks the meter away
    -- behind the minimap and brings it back.
    local arrow = CreateFrame("Button", nil, holder)
    arrow:SetSize(Panel.TAB[1], Panel.TAB[2])
    arrow:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
    Style.Shell(arrow, { borderPx = Panel.XP_BORDER })
    arrow.icon = arrow:CreateTexture(nil, "OVERLAY")
    arrow.icon:SetTexture(DUI.MEDIA .. "ui-chevron.png")
    arrow.icon:SetSize(Panel.ARROW, Panel.ARROW)
    arrow.icon:SetPoint("CENTER", arrow, "CENTER", -1, 0)
    arrow.icon:SetVertexColor(Panel.ARROW_COLOR[1], Panel.ARROW_COLOR[2], Panel.ARROW_COLOR[3])
    arrow:SetScript("OnClick", function()
        DUI:Set("InfoPanel", "meter.enabled", not mod.db.meter.enabled)
    end)
    arrow:SetScript("OnEnter", function(self) self.icon:SetVertexColor(Style.Accent()) end)
    arrow:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(Panel.ARROW_COLOR[1], Panel.ARROW_COLOR[2], Panel.ARROW_COLOR[3])
    end)
    Panel.arrow = arrow
    -- Hidden until the mouse is over the panel or the tab. Only watched while
    -- the tab is shown, and checked again as it shows so it's never stale.
    arrow:SetAlpha(0)
    local near, alpha = false, 0
    local function paint(v) alpha = v; arrow:SetAlpha(v) end
    local function watch(_, snap)
        -- The panel and a tab's width past its meter's side.
        local reach = Panel.TAB[1] + 10
        local left = Panel.side ~= "right"
        local now = holder:IsMouseOver(0, 0, left and -reach or 0, left and 0 or reach) or arrow:IsMouseOver()
            or ns.ThreatMeter.MouseNear() or false
        if now ~= near or snap then
            near = now
            DUI.Motion.Tween("infopanel:arrow", alpha, now and 1 or 0, snap and 0 or DUI.Motion.FAST, paint)
        end
    end
    Panel.WatchHover(arrow, watch)

    -- Pinned by the minimap's outer corner (Panel.Pin): the meter sliding
    -- out widens the panel on its own side and the map stays put.
    DUI.Movers.Register(holder, "infopanel", "Info Panel",
        { "TOPRIGHT", nil, "TOPRIGHT", -Panel.EDGE, -Panel.EDGE }, { corner = "TOPRIGHT" })
    -- A separate meter starts in the screen's bottom-right corner, as chat
    -- sits in the bottom-left.
    DUI.Movers.Register(own, "infopanel.meter", "Damage Meter",
        function() return { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -Panel.EDGE, DUI.Movers.Above(Panel.EDGE) } end,
        { bottom = true })
    DUI.Movers.Register(xp, "infopanel.xp", "Experience Bar", Panel.xpDefault)
    Panel.BuildXPGrip(xp, mod)
end

-- Bottom-right resize grip for a meter window, shown only while unlocked.
-- Releasing saves the size under `path`. `shell` is the bordered frame when
-- it isn't the window itself.
function Panel.MeterGrip(own, key, path, shell, done)   -- shell: a frame, or a function giving it
    local grip = CreateFrame("Button", nil, own)
    grip:SetSize(Panel.GRIP, Panel.GRIP)
    grip:SetPoint("BOTTOMRIGHT", own, "BOTTOMRIGHT", -2, 2)
    -- Above unlock mode's handles, which cover the window.
    grip:SetFrameStrata("FULLSCREEN")
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    own:SetResizable(true)
    grip:SetScript("OnMouseDown", function() own:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        own:StopMovingOrSizing()
        if type(shell) == "function" then shell = shell() end
        local T = Pixel.Px(own, Style.BorderPx(shell or own))
        local edge = 2 * (T + Panel.PAD)
        local w = math.floor(own:GetWidth() - edge + 0.5)
        local h = math.floor(own:GetHeight() - edge + 0.5)
        -- Within the window's own limits (each kind its own), else a meter's.
        local lw, lh, hw, hh = own:GetResizeBounds()
        if type(hw) == "number" and hw > 0 then
            w = math.max(lw - edge, math.min(hw - edge, w))
            h = math.max(lh - edge, math.min(hh - edge, h))
        else
            w = math.max(Panel.METER_MIN[1], math.min(Panel.METER_MAX[1], w))
            h = math.max(Panel.METER_MIN[2], math.min(Panel.METER_MAX[2], h))
        end
        -- Keep where it now sits, then its size (done: the caller's own way).
        DUI.Movers.Save(key)
        if done then return done(w, h) end
        DUI:Set("InfoPanel", path .. ".width", w)
        DUI:Set("InfoPanel", path .. ".height", h)
    end)
    grip:Hide()
    return grip
end

-- The first meter's, for when it's detached.
function Panel.BuildGrip(own, mod)
    Panel.grip = Panel.MeterGrip(own, "infopanel.meter", "meter")
    DUI.On("UnlockChanged", function() Panel.UpdateGrip(mod.db) end)
end

function Panel.UpdateGrip(db)
    if Panel.grip then
        Panel.grip:SetShown(DUI.Movers.unlocked and db.meter.detached and Panel.meterFrame:IsShown() or false)
    end
end

-- The same corner grip for the detached XP and reputation bars, placed on the
-- bar itself. done(w, h) receives the new inner size, clamped to the limits.
-- vertical() says whether the bar stands upright: its length is then its
-- height, and the grip's drag is read that way round.
function Panel.BarGrip(xp, done, vertical)
    local grip = CreateFrame("Button", nil, xp)
    grip:SetSize(Panel.GRIP, Panel.GRIP)
    grip:SetPoint("BOTTOMRIGHT", xp, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameStrata("FULLSCREEN")
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    xp:SetResizable(true)
    -- Its own limits (the options' sliders'), not the client's default ones.
    if xp.SetResizeBounds then
        xp:SetResizeBounds(Panel.XP_MIN[1], Panel.XP_MIN[2], Panel.XP_MAX[1], Panel.XP_MAX[2] + 2 * Panel.GRIP)
    end
    grip:SetScript("OnMouseDown", function() xp:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        xp:StopMovingOrSizing()
        local xT = Pixel.Px(xp, Style.BorderPx(xp))
        local w = math.floor(xp:GetWidth() + 0.5)
        local h = math.floor(xp:GetHeight() - 2 * xT + 0.5)
        if vertical and vertical() then
            w, h = math.floor(xp:GetHeight() + 0.5), math.floor(xp:GetWidth() - 2 * xT + 0.5)
        end
        w = math.max(Panel.XP_MIN[1], math.min(Panel.XP_MAX[1], w))
        h = math.max(Panel.XP_MIN[2], math.min(Panel.XP_MAX[2], h))
        done(w, h)
    end)
    grip:Hide()
    return grip
end

-- Sizes a separate bar from its length and thickness (the width and height
-- settings) plus its border T, standing upright when vertical; the grip's
-- limits turn with it.
function Panel.SizeBar(f, length, thick, T, vertical)
    local lo, hi = Panel.XP_MIN, Panel.XP_MAX
    if vertical then
        f:SetSize(thick + 2 * T, length)
        if f.SetResizeBounds then f:SetResizeBounds(lo[2] + 2 * T, lo[1], hi[2] + 2 * T, hi[1]) end
    else
        f:SetSize(length, thick + 2 * T)
        if f.SetResizeBounds then f:SetResizeBounds(lo[1], lo[2] + 2 * T, hi[1], hi[2] + 2 * T) end
    end
end

function Panel.BuildXPGrip(xp, mod)
    Panel.xpGrip = Panel.BarGrip(xp, function(w, h)
        DUI.Movers.Save("infopanel.xp")
        -- Sized by hand now, so no longer the action bars' width.
        DUI:Set("InfoPanel", "xp.matchBars", false)
        DUI:Set("InfoPanel", "xp.width", w)
        DUI:Set("InfoPanel", "xp.height", h)
    end, function() return ns.XP.vertical end)
    DUI.On("UnlockChanged", function() Panel.UpdateXPGrip(mod.db) end)
end

function Panel.UpdateXPGrip(db)
    if Panel.xpGrip then
        Panel.xpGrip:SetShown(DUI.Movers.unlocked and db.xp.detached and Panel.xp:IsShown() or false)
    end
end

-- The main action bar's extent in the XP bar's units: { left, right, bottom },
-- or nil while not shown. Only read, never anchored to: the buttons are protected.
function Panel.BarsSpan(xp)
    local left, right, bottom
    -- Our own bar 1 when the action bars draw their own, else the game's.
    local own = DUI.ActionBarButtons and DUI.ActionBarButtons("main")
    for i = 1, 12 do
        local b = own and own[i] or _G["ActionButton" .. i]
        if type(b) == "table" and b:IsShown() then
            local l, r, y = b:GetLeft(), b:GetRight(), b:GetBottom()
            if type(l) == "number" and type(r) == "number" and type(y) == "number" then
                local s = b:GetEffectiveScale() / xp:GetEffectiveScale()
                l, r, y = l * s, r * s, y * s
                left = left and math.min(left, l) or l
                right = right and math.max(right, r) or r
                bottom = bottom and math.min(bottom, y) or y
            end
        end
    end
    if not left or right - left < 1 then return nil end
    return { left = left, right = right, bottom = bottom }
end

-- The minimap's size: the Size setting.
function Panel.MapSize(db)
    return db.map.size
end

-- How solid a box is, and whether it has a border (0 shows none); laid
-- out by its owner afterwards.
function Panel.Look(f, alpha, border)
    local s = Style.GetShell(f)
    if s then
        s.opts.bgAlpha = alpha
        s.opts.noBorder = border == false
        -- The shadow traces the frame's edge, so it reads as a ghost border.
        s.opts.shadowAlpha = border == false and 0 or nil
        -- And the 1px light and dark lines along the box's top and bottom.
        s.opts.noBevel = border == false
    end
end

-- How solid the boxes are (every window's, or the panel's own: also the
-- meters' and threat meter's windows), and whether they have a border.
function Panel.BackAlpha(db)
    return Style.BackAlpha(db.panelAlphaOwn, db.panelAlpha)
end

-- Background and border settings for the minimap box (map.alphaOwn,
-- map.alpha, map.border). Without a map it's just the meter's box.
function Panel.BoxLook(db)
    local map = db.map
    if not map.enabled then return Panel.BackAlpha(db), db.panelBorder end
    return Style.BackAlpha(map.alphaOwn, map.alpha), map.border
end

-- A meter's own window (m: its settings, Windows.List's cfg): its own background
-- (alphaOwn / alpha), else the panel's.
function Panel.MeterBack(db, m)
    if m.alphaOwn == true and type(m.alpha) == "number" then return m.alpha end
    return Panel.BackAlpha(db)
end

function Panel.ApplyAlpha(db)
    local set, back = Panel.Look, Panel.BackAlpha(db)
    set(Panel.xp, back, db.panelBorder)
    local boxBack, boxBorder = Panel.BoxLook(db)
    set(Panel.panel, boxBack, boxBorder)
    set(Panel.arrow, boxBack, boxBorder)
    -- The meter's own window keeps its own background and border.
    set(Panel.meterFrame, Panel.MeterBack(db, db.meter), db.meter.border)
end

-- Which side of the minimap the meter slides out of. "auto" picks the side
-- facing the screen's middle, judged from the panel's anchor point (the map's
-- outer edge), which doesn't move as the meter slides, so it never flips mid-slide.
-- At the default top-right spot that's left.
function Panel.Side(db)
    local pick = db.map.meterSide
    if pick == "left" or pick == "right" then return pick end
    local pos = DUI.DB.Positions()["infopanel"]
    if not DUI.Movers.Valid(pos) then return "left" end
    local x = (pos.at and type(pos.ax) == "number") and pos.ax or pos[1]
    return x < 0 and "right" or "left"
end

-- The panel pinned by the map's outer top corner (the one away from the
-- meter), so the meter opening never moves the map, wherever it was put.
function Panel.Pin(side)
    DUI.Movers.SetPin("infopanel", side == "right" and "TOPLEFT" or "TOPRIGHT")
end

-- Sizes everything from the settings; each part is optional.
function Panel.Layout(db)
    local holder, xp, panel, own = Panel.holder, Panel.xp, Panel.panel, Panel.meterFrame
    -- First, while the panel still has its old width: pinned where it is.
    local side = Panel.Side(db)
    Panel.side = side
    local right = side == "right"
    Panel.Pin(side)
    Panel.ApplyAlpha(db)
    local T = Pixel.Px(panel, Style.BorderPx(panel))
    local xT = Pixel.Px(xp, Style.BorderPx(xp))
    local pad = Panel.PAD
    local m = db.meter
    local wanted = Panel.MeterWanted(m)
    Panel.laidWanted = wanted
    local detached = m.detached
    local meterIn = wanted and not detached
    local mapOn = db.map.enabled
    local map = Panel.MapSize(db)
    Panel.mapSize = map
    local inner = mapOn and map or Panel.METER_ONLY_HEIGHT
    -- The gap between meter and map matches the gap to the panel's edge
    -- (border plus padding); padding alone looked too narrow.
    -- The slide eases between the width without the meter and with it.
    -- The data text strip sits under the map; the meter reaches down beside
    -- it. With no map the strip spans the meter's width, kept even when the
    -- meter is folded.
    local room = ns.DataTexts.Room(db)
    local stripOn = room > 0
    local stripAlone = stripOn and not mapOn
    local base = 2 * (T + pad) + (mapOn and map or 0) + (stripAlone and m.width or 0)
    Panel.geo = { base = base, room = stripAlone and 0 or (m.width + (mapOn and (T + pad) or 0)), width = m.width }
    local panelH = 2 * (T + pad) + inner + room
    local meterH = mapOn and (inner + room) or inner
    local xpDetached = db.xp.detached
    -- Free to move, it's no longer part of the panel's own size.
    local xpH = (db.xp.enabled and not xpDetached) and (db.xp.height + 2 * xT) or 0
    local panelOn = meterIn or mapOn or stripOn

    -- The width is set by the slide, at the end.
    holder:SetHeight(xpH + ((xpH > 0 and panelOn) and Panel.GAP or 0) + (panelOn and panelH or 0))

    xp:SetShown(db.xp.enabled)
    xp:ClearAllPoints()
    if xpDetached then
        xp:SetParent(UIParent)
        local h = db.xp.height + 2 * xT
        local span = Panel.BarsSpan(xp)
        local vertical = db.xp.orientation == "vertical"
        local d = Panel.xpDefault
        if span and vertical then
            -- Upright: standing on the bars' bottom, just left of them.
            d[1], d[3] = "BOTTOMRIGHT", "BOTTOMLEFT"
            d[4], d[5] = span.left - Panel.GAP, span.bottom
        elseif vertical then
            -- No action bar to stand by: the right edge's middle, out of the way.
            d[1], d[3], d[4], d[5] = "RIGHT", "RIGHT", -Panel.XP_EDGE, 0
        elseif span then
            -- Centered in the gap between the bar's buttons and the screen's
            -- bottom edge (or the data bar along it).
            d[1], d[3] = "BOTTOM", "BOTTOMLEFT"
            local room = DUI.Movers.BottomRoom()
            d[4], d[5] = (span.left + span.right) / 2, room + math.max(0, math.floor((span.bottom - room - h) / 2))
        else
            d[1], d[3], d[4], d[5] = "BOTTOM", "BOTTOM", 0, 6
        end
        local width = (db.xp.matchBars and span and not vertical) and (span.right - span.left) or db.xp.width
        Panel.SizeBar(xp, width, db.xp.height, xT, vertical)
        -- Positioned by its own mover, below.
    else
        xp:SetParent(holder)
        xp:SetPoint("TOPLEFT", holder, "TOPLEFT")
        xp:SetPoint("TOPRIGHT", holder, "TOPRIGHT")
        xp:SetHeight(math.max(xpH, 1))
    end
    Style.LayoutShell(Style.GetShell(xp))
    Panel.PlaceXPFade(db)
    DUI.Movers.Suspend("infopanel.xp", not xpDetached)
    Panel.UpdateXPGrip(db)

    panel:SetShown(panelOn)
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
    panel:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT")
    panel:SetHeight(panelH)
    Style.LayoutShell(Style.GetShell(panel))

    local area = Panel.mapArea
    area:SetShown(mapOn)
    area:ClearAllPoints()
    -- On the side away from the meter.
    if right then
        area:SetPoint("TOPLEFT", panel, "TOPLEFT", T + pad, -(T + pad))
    else
        area:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(T + pad), -(T + pad))
    end
    area:SetSize(map, map)

    local strip = Panel.dataArea
    strip:SetShown(stripOn)
    strip:ClearAllPoints()
    if mapOn then
        strip:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 0, -pad)
    else
        strip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", T + pad, T + pad)
    end
    strip:SetSize(mapOn and map or m.width, math.max(1, room - pad))

    Panel.inset = T + pad     -- from the panel's edge to its contents

    -- The meter: in the panel, in its own window, or away.
    local ma = Panel.meterArea
    ma:ClearAllPoints()
    if detached then
        local h = m.height
        own:SetSize(m.width + 2 * (T + pad), h + 2 * (T + pad))
        own:SetResizeBounds(Panel.METER_MIN[1] + 2 * (T + pad), Panel.METER_MIN[2] + 2 * (T + pad),
            Panel.METER_MAX[1] + 2 * (T + pad), Panel.METER_MAX[2] + 2 * (T + pad))
        Style.LayoutShell(Style.GetShell(own))
        own:SetShown(wanted)
        ma:SetParent(own)
        -- Pinned by two corners, so it stretches with the window while it's
        -- being resized.
        ma:SetPoint("TOPLEFT", own, "TOPLEFT", T + pad, -(T + pad))
        ma:SetPoint("BOTTOMRIGHT", own, "BOTTOMRIGHT", -(T + pad), T + pad)
        ma:SetShown(wanted)
    else
        own:Hide()
        local clip = Panel.meterClip
        clip:ClearAllPoints()
        local at = right and "TOPRIGHT" or "TOPLEFT"
        clip:SetPoint(at, panel, at, right and -(T + pad) or (T + pad), -(T + pad))
        clip:SetHeight(meterH)
        ma:SetParent(clip)
        -- Rides the panel's edge on its side as it slides; shown by the slide.
        ma:SetPoint(at, clip, at)
        ma:SetSize(m.width, meterH)
    end
    DUI.Movers.Suspend("infopanel.meter", not detached)
    Panel.PlaceMeterFade(db)
    Panel.UpdateGrip(db)

    -- The fold arrow: on the panel's edge on the meter's side whenever the
    -- meter could be in the panel; it points toward where the meter will go.
    local arrow = Panel.arrow
    -- Shown to hide the meter while it's up, or to bring it back while it's
    -- switched off; not while it's on but waiting for a group or combat
    -- (a click then would switch it off, not show it).
    arrow:SetShown(panelOn and not detached and (wanted or not m.enabled))
    Panel.PlaceArrow(0)
    arrow:SetSize(Panel.TAB[1] + T, Panel.TAB[2])
    arrow.icon:ClearAllPoints()
    arrow.icon:SetPoint("CENTER", arrow, "CENTER", (right and T or -T) / 2, 0)
    Style.LayoutShell(Style.GetShell(arrow))
    -- The chevron points down; turned a quarter to point toward the map
    -- (fold into it) or away from it (bring the meter back out).
    arrow.icon:SetRotation((m.enabled and 1 or -1) * (right and -1 or 1) * math.pi / 2)

    -- Slides only with the minimap there to slide against, while it's on
    -- screen; anything else (the first layout, the panel coming or going)
    -- jumps straight there.
    local glide = mapOn and Panel.lastMapOn and holder:IsVisible() or false
    Panel.lastMapOn = mapOn
    Panel.SlideMeter(meterIn and 1 or 0, glide)
    return xT
end

-- Places the fold tab tucked behind the panel's border. `out` pushes it further
-- out when the threat meter covers that edge.
function Panel.PlaceArrow(out)
    local arrow, panel = Panel.arrow, Panel.panel
    if not arrow then return end
    local T = Pixel.Px(panel, Style.BorderPx(panel))
    arrow:ClearAllPoints()
    if Panel.side == "right" then
        arrow:SetPoint("LEFT", panel, "RIGHT", out - T, 0)
    else
        arrow:SetPoint("RIGHT", panel, "LEFT", T - out, 0)
    end
end

-- Decides which fade owns the XP bar's alpha: its own, the panel's, or none
-- (attached, it inherits the panel's as a child). Called from Layout so a
-- change applies at once; otherwise the old owner's alpha would stick.
function Panel.PlaceXPFade(db)
    local owner = db.xp.ownFade == true and "own" or db.xp.detached == true and "panel" or "parent"
    local was = Panel.xpFadeOwner
    if owner == was then return end
    Panel.xpFadeOwner = owner
    local xp = Panel.xp
    xp:SetIgnoreParentAlpha(owner == "own")
    if owner == "parent" then xp:SetAlpha(1) end
    -- (The first layout: the fades paint what they registered themselves.)
    if was then DUI.Fade.Hold(owner == "own" and "InfoPanel.xp" or "InfoPanel.panel", false) end
end

-- The same for the damage meters: the panel's fade, or their own. Inside the
-- panel the meter then ignores the panel's alpha, so the two fade apart; in
-- its own window that window is faded instead.
function Panel.PlaceMeterFade(db)
    local own = db.meter.ownFade == true
    local owner = not own and "panel" or db.meter.detached == true and "window" or "inside"
    local was = Panel.meterFadeOwner
    if owner == was then return end
    Panel.meterFadeOwner = owner
    local ma = Panel.meterArea
    ma:SetIgnoreParentAlpha(owner == "inside")
    if owner ~= "inside" then ma:SetAlpha(1) end
    if was then DUI.Fade.Hold(own and "InfoPanel.meter" or "InfoPanel.panel", false) end
end

-- The first layout always jumps (nothing on screen to slide from).
function Panel.SlideMeter(goal, glide)
    local s = Panel.slide
    if glide and Panel.placed then s:To(goal) else s:Jump(goal) end
    Panel.placed = true
    Panel.ApplySlide()
end

-- The panel's width, and how much of the meter shows, for the slide's spot.
function Panel.ApplySlide()
    local s, g = Panel.slide, Panel.geo
    if not (s and g) then return end
    local p = s.p
    Panel.holder:SetWidth(g.base + p * g.room)
    local clip = Panel.meterClip
    clip:SetWidth(math.max(p * g.width, 0.01))
    clip:SetAlpha(p)
    local ma = Panel.meterArea
    if ma:GetParent() == clip then ma:SetShown(s.goal == 1 or p > 0) end
end

-- ---------------------------------------------------------------------
-- Build and refresh
-- ---------------------------------------------------------------------

function ns.Build(mod)
    ns.module = mod
    DUI.WarnIfLoaded("EllesmereUIMinimap", "EllesmereUI Minimap", DUI.L["minimap"])
    DUI.WarnIfLoaded("EllesmereUIDamageMeters", "EllesmereUI Damage Meters", DUI.L["damage meter"])
    -- The old second meter becomes the player's first window (its own
    -- upgrade, on the profile in use, before anything is built from it).
    DUI.SafeCall(ns.Windows.Upgrade, DUI.DB.Active())
    Panel.Build(mod)
    Panel.inCombat = InCombatLockdown()
    local list = {}   -- (one table, refilled: the fade asks often)
    DUI.Fade.Register{ key = "InfoPanel.panel", scope = "InfoPanel", path = "fade",
        page = { "InfoPanel.panel", "InfoPanel.data", "InfoPanel.meter" },
        frames = function()
            for i = #list, 1, -1 do list[i] = nil end
            list[1] = Panel.holder
            -- The meters, separate or not, fade with the panel unless they
            -- have a fade of their own.
            if not mod.db.meter.ownFade then
                if Panel.meterFrame:IsShown() then list[#list + 1] = Panel.meterFrame end
                ns.MeterFrame.Frames("meter", list)
                ns.MeterFrame.Frames("summary", list)
            end
            -- Attached, it fades with the panel (a child of it); detached, it's
            -- its own frame and needs listing separately. With its own fade
            -- it's InfoPanel.xp's.
            if mod.db.xp.detached and not mod.db.xp.ownFade and Panel.xp:IsShown() then list[#list + 1] = Panel.xp end
            local rep = ns.RepBar.frame
            if rep and rep:IsShown() then list[#list + 1] = rep end
            return list
        end }
    local xpList = {}
    DUI.Fade.Register{ key = "InfoPanel.xp", scope = "InfoPanel", path = "xp.fade", page = "InfoPanel.panel", whole = true,
        frames = function()
            xpList[1] = mod.db.xp.ownFade and Panel.xp:IsShown() and Panel.xp or nil
            return xpList
        end }
    local meterList = {}
    DUI.Fade.Register{ key = "InfoPanel.meter", scope = "InfoPanel", path = "meter.fade", page = ns.MeterOptions.PAGE,
        frames = function()
            for i = #meterList, 1, -1 do meterList[i] = nil end
            if not mod.db.meter.ownFade then return meterList end
            if Panel.meterFrame:IsShown() then
                meterList[1] = Panel.meterFrame
            elseif Panel.meterArea:IsShown() then
                meterList[1] = Panel.meterArea
            end
            ns.MeterFrame.Frames("meter", meterList)
            return ns.MeterFrame.Frames("summary", meterList)
        end }
    -- Float: XP or money coming in (or going out) brings the panel
    -- back for a while; a reputation gain too (XP.RepGain).
    for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY" }) do
        pcall(DUI.RegisterEvent, e, function()
            DUI.Fade.Wake("InfoPanel.panel")
            if e ~= "PLAYER_MONEY" then DUI.Fade.Wake("InfoPanel.xp") end
        end)
    end
    ns.XP.Build(Panel.xp)
    ns.RepBar.Build(mod)
    ns.Meter.Build(Panel.meterArea, mod)
    ns.MeterFrame.Build(mod)
    ns.ThreatMeter.Build(mod)
    ns.Minimap.Build(Panel.mapArea)
    ns.DataTexts.Build(Panel.dataArea, mod)
    ns.DataBar.Build(mod)
    -- The game draws minimap icons at full strength regardless of alpha, so
    -- once the panel fades fully out the map is made transparent too. Never
    -- hidden: a hidden minimap came back blank.
    local mapHidden = false
    hooksecurefunc(Panel.holder, "SetAlpha", function(_, a)
        -- Shown and at full strength (most calls): nothing can change.
        if not mapHidden and (type(a) ~= "number" or a >= 1 or not mod.db.map.enabled) then return end
        -- Whatever took it there (its own fade, opacity 0, the campfire's hush).
        local _, goal = DUI.Fade.State("InfoPanel.panel")
        local faded = mod.db.map.enabled and type(a) == "number" and type(goal) == "number"
            and goal <= 0.001 and a <= 0.001
        if faded ~= mapHidden then
            mapHidden = faded
            DUI.Fade.MapAway("infopanel", faded)
        end
    end)
    ns.Tracker.Build(mod)
    -- The quest tracker hangs from a spot under the panel; moving the panel
    -- in unlock mode moves that spot when unlocking ends.
    DUI.On("UnlockChanged", function(unlocked)
        if not unlocked then DUI.SafeCall(ns.Tracker.Apply, mod.db.tracker) end
    end)
    local function relayout() ns.Refresh(mod) end
    -- Group and combat state only affect the meters, so re-layout happens only
    -- when a meter actually shows or hides, and only for the panel and meters.
    local function follow()
        if Panel.MeterWanted(mod.db.meter) ~= Panel.laidWanted
           or ns.MeterFrame.Changed(mod.db) then return ns.RefreshMeters(mod) end
        -- The meters still draw the fight's last numbers.
        ns.Meter.MarkDirty()
        ns.MeterFrame.MarkDirty()
    end
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        Panel.inCombat = true
        follow()
    end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        Panel.inCombat = false
        follow()
    end)
    DUI.RegisterEvent("GROUP_ROSTER_UPDATE", follow)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", follow)   -- in or out of an instance
    -- A separate experience bar sits under the action bars, which the game
    -- places once the world is up and whenever its layout changes.
    local function afterBars()
        if mod.db.xp.detached then C_Timer.After(0, relayout) end
    end
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", afterBars)
    pcall(DUI.RegisterEvent, "EDIT_MODE_LAYOUTS_UPDATED", afterBars)
    pcall(DUI.RegisterEvent, "PLAYER_SPECIALIZATION_CHANGED", afterBars)
    -- Our own bars re-lay out live (a setting, a move): follow bar 1.
    DUI.On("ActionBarLaidOut", function(key) if key == "main" then afterBars() end end)
    -- Moving past the screen's middle (auto side) or a reset flips the meter
    -- and its threat meter to the other side. Detached windows do the same.
    DUI.On("MoverApplied", function(key)
        if key == "infopanel" and Panel.Side(mod.db) ~= Panel.side then
            ns.RefreshMeters(mod)
        elseif key == "infopanel.meter" and ns.ThreatMeter.host == Panel.meterFrame
           and ns.ThreatMeter.Side(Panel.meterFrame) ~= ns.ThreatMeter.side then
            DUI.SafeCall(ns.ThreatMeter.Apply, mod.db.threat)
        end
    end)
    DUI.On("TestModeChanged", relayout)
    DUI.On("TestPartChanged", function(key)
        if key == "meter" or key == ns.MeterFrame.PART or key == "datatexts" then relayout() end
    end)
    ns.Refresh(mod)
end

-- A meter showing or hiding only resizes the panel and the meters. The full
-- Apply of the minimap, data texts and XP bar re-registers events and
-- requests the guild roster, so it's skipped here.
function ns.RefreshMeters(mod)
    local db = mod.db
    Panel.Layout(db)
    DUI.SafeCall(ns.Meter.Apply, db.meter)
    DUI.SafeCall(ns.MeterFrame.Sync, mod)
    DUI.SafeCall(ns.ThreatMeter.Apply, db.threat)
    -- With no map or data texts the panel comes and goes with the meter:
    -- the tracker under it follows.
    DUI.SafeCall(ns.Tracker.Apply, db.tracker)
end

function ns.Refresh(mod)
    local db = mod.db
    DUI.Movers.SetBottomRoom(ns.DataBar.Room(db))
    local xT = Panel.Layout(db)
    DUI.SafeCall(ns.XP.Apply, db.xp, xT)
    DUI.SafeCall(ns.RepBar.Apply, db)
    DUI.SafeCall(ns.Meter.Apply, db.meter)
    DUI.SafeCall(ns.MeterFrame.Sync, mod)
    DUI.SafeCall(ns.ThreatMeter.Apply, db.threat)
    DUI.SafeCall(ns.Minimap.Apply, db.map)
    DUI.SafeCall(ns.DataTexts.Apply, db.data)
    DUI.SafeCall(ns.DataBar.Apply, db)
    DUI.SafeCall(ns.Tracker.Apply, db.tracker)
end

-- ---------------------------------------------------------------------
-- Tour stops: the meter (slid out with its sample) and the data texts.
-- ---------------------------------------------------------------------

-- New setups start with the meter folded (DB.StandardStart): the stop slides
-- it out for the look and folds it again as it leaves.
local foldedForTour = false

DUI.Tour.Add("meter", {
    order = 10,
    title = DUI.L["Damage meter"],
    text = function()
        local L, pop = DUI.L, DUI.Tour.Pop
        local text = string.format(L["Damage, healing and more for every fight, beside the minimap: the mode, the fight and its length on top, and its buttons there while the mouse is over it (which fight, what it counts, %s, reset, %s). Hover a name for their spells; click it for everything. More windows: %s."],
            pop(L["Report"]), pop(L["new window"]), pop(L["Info Panel > Meters"]))
        if not foldedForTour then return text end
        return text .. " " .. L["It starts folded away: the tab on the panel's edge slides it out."]
    end,
    available = function() return ns.module ~= nil end,
    enter = function()
        if ns.module.db.meter.enabled ~= true then
            foldedForTour = true
            DUI:Set("InfoPanel", "meter.enabled", true)
        end
        DUI.SetTestSolo({ "meter" })
    end,
    leave = function()
        DUI.SetTestSolo(nil)
        if foldedForTour then
            foldedForTour = false
            DUI:Set("InfoPanel", "meter.enabled", false)
        end
    end,
    settle = Panel.SLIDE + 0.15,
    part = function()
        if Panel.meterFrame and Panel.meterFrame:IsShown() then return Panel.meterFrame end
        return Panel.meterArea
    end,
})

DUI.Tour.Add("datatexts", {
    order = 15,
    title = DUI.L["At a glance"],
    text = DUI.L["Gold, gear, free bag slots and who's online, turning amber then red when gear or bags run low. Hover one for details, click it for its window."],
    available = function() return ns.module ~= nil and ns.module.db.data.enabled == true end,
    part = function() return Panel.dataArea end,
})
