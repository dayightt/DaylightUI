-- Zone title shown when entering a new zone: the name rises in the accent color
-- with a line under it, then the subzone and PvP status. A subzone change alone
-- shows just the small subzone line.
-- Replaces the game's zone text. Its four strings stay at alpha 0 while this is
-- on; the game only fades their parent frames, so one SetAlpha holds.

local _, ns = ...
local DUI = DaylightUI
local secret = DUI.IsSecret
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local ZoneTitle = {
    Y = -192,           -- the name's middle from the screen's top: the game's ZoneTextString (ZoneText.xml)
    WIDTH = 360,        -- the line at full spread
    LINE = 1,           -- its thickness
    NAME = 26, SUB = 15, PVP = 13,
    RISE = 12,          -- px the name rises as it comes in
    HOLD = 2.5,         -- seconds the whole title stays (zoneTitleHold)
    SUB_HOLD = 1.5,     -- seconds a subzone alone stays
    DRIFT = 6,          -- px it rises as it goes
    MOVER = "qol.zone",
    FONT = "qol.zone.font",     -- its font's Media slot (zoneTitleFont)
    TEST_PART = "zone",
    GLOW = DUI.MEDIA .. "char-glow.png",
    GEM = DUI.MEDIA .. "shape-diamond.png",
    GEM_SIZE = 9,       -- the diamond in the line's middle
    SHINE_W = 110,      -- the light that runs across the name
    SHINE_ALPHA = 0.45,
    HAZE_ALPHA = 0.3,
    -- The game's PvP colors (SetZoneText), softened like the Daylight tooltips'.
    COLORS = {
        sanctuary = { 0.55, 0.80, 0.92 },
        friendly = { 0.55, 0.85, 0.55 },
        contested = { 0.95, 0.72, 0.32 },
        hostile = { 0.93, 0.36, 0.30 },
    },
    -- The preview's place (the game sends the real ones).
    SAMPLE = { L["Elwynn Forest"], L["Goldshire"], "contested" },
}
ZoneTitle.COLORS.arena = ZoneTitle.COLORS.hostile
ZoneTitle.COLORS.combat = ZoneTitle.COLORS.hostile
ns.ZoneTitle = ZoneTitle
ns.features[#ns.features + 1] = ZoneTitle

DUI.Media.RegisterSlot(ZoneTitle.FONT, "QoL", "zoneTitleFont", "font")

local GAME_TEXTS = { "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString" }
local WARM = Style.INK.TEXT

local mod, f, holder, wired, lastZone
local sample = false    -- the still copy unlock and test mode show
local held              -- a change that came while busy(): "zone" (the whole title) or "sub"
local run = 0           -- each show's id: a newer one stops the older one's timers
local full = -1         -- the id of the last whole-title show

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.zoneTitle == true end

local function db(key)
    if mod and mod.db and mod.db[key] ~= nil then return mod.db[key] end
    return ns.DEFAULTS[key]
end
local function on(key) return db(key) == true end
local function num(key, fallback) return tonumber(db(key)) or fallback end

-- A plain string from one of the game's zone getters, or nil.
local function read(fn)
    if type(fn) ~= "function" then return nil end
    local s = fn()
    if type(s) ~= "string" or secret(s) then return nil end
    return s
end

local function build()
    if f then return f end
    -- The holder stays put for the unlock handle and carries the scale; the
    -- title drifts inside it.
    holder = CreateFrame("Frame", "DaylightUIZoneTitleHolder", UIParent)
    holder:SetSize(ZoneTitle.WIDTH, 80)
    holder:EnableMouse(false)
    f = CreateFrame("Frame", "DaylightUIZoneTitle", holder)
    f:SetSize(ZoneTitle.WIDTH, 1)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()
    -- The top is free again: a reputation banner that waited plays now.
    f:SetScript("OnHide", function() if ns.RepBanner then ns.RepBanner.Resume() end end)

    -- A soft haze behind the name, in its color.
    f.haze = f:CreateTexture(nil, "BACKGROUND")
    f.haze:SetTexture(ZoneTitle.GLOW)
    f.haze:SetBlendMode("ADD")
    f.haze:SetPoint("CENTER", f, "CENTER", 0, 14)
    f.haze:SetSize(ZoneTitle.WIDTH * 1.1, 90)
    f.haze:SetAlpha(0)

    -- The line: two halves from the middle out (painted per show, paint()).
    f.left = f:CreateTexture(nil, "ARTWORK")
    f.left:SetColorTexture(1, 1, 1, 1)
    f.left:SetPoint("RIGHT", f, "CENTER", 0, 0)
    f.right = f:CreateTexture(nil, "ARTWORK")
    f.right:SetColorTexture(1, 1, 1, 1)
    f.right:SetPoint("LEFT", f, "CENTER", 0, 0)
    f.left:SetHeight(ZoneTitle.LINE)
    f.right:SetHeight(ZoneTitle.LINE)
    -- A small diamond where the line starts from.
    f.gem = f:CreateTexture(nil, "OVERLAY")
    f.gem:SetTexture(ZoneTitle.GEM)
    f.gem:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.gem:SetSize(1, 1)
    f.gem:Hide()

    f.name = Style.Text(f, ZoneTitle.NAME, "CENTER", ZoneTitle.FONT)
    f.sub = Style.Text(f, ZoneTitle.SUB, "CENTER", ZoneTitle.FONT)
    f.sub:SetPoint("TOP", f, "CENTER", 0, -8)
    f.pvp = Style.Text(f, ZoneTitle.PVP, "CENTER", ZoneTitle.FONT)

    -- The band over the name that a light runs across as it lands.
    f.band = CreateFrame("Frame", nil, f)
    f.band:SetPoint("BOTTOMLEFT", f, "LEFT", 0, 0)
    f.band:SetPoint("BOTTOMRIGHT", f, "RIGHT", 0, 0)
    f.band:SetHeight(ZoneTitle.NAME + 12)
    f.shine = f.band:CreateTexture(nil, "OVERLAY")
    f.shine:SetTexture(ZoneTitle.GLOW)
    f.shine:SetBlendMode("ADD")
    f.shine:Hide()

    DUI.Movers.Register(holder, ZoneTitle.MOVER, "Zone title", { "CENTER", nil, "TOP", 0, ZoneTitle.Y },
        { active = enabled })
    return f
end

-- Text sizes from the settings; the band, shine and haze follow the name's.
local function size()
    local nameSize = num("zoneTitleNameSize", ZoneTitle.NAME)
    local subSize = num("zoneTitleSubSize", ZoneTitle.SUB)
    Style.SetTextSize(f.name, nameSize)
    Style.SetTextSize(f.sub, subSize)
    Style.SetTextSize(f.pvp, math.max(Style.SIZE.tiny, subSize - 2))
    f.band:SetHeight(nameSize + 12)
    f.shine:SetSize(ZoneTitle.SHINE_W, nameSize * 2)
    f.haze:SetSize(ZoneTitle.WIDTH * 1.1, nameSize * 3.5)
end

-- A color setting's pick as { r, g, b }, or nil when it means the accent
-- (or the zone's PvP color in a zone that has none). "zone" is the zone's own
-- PvP color: green friendly, red hostile and so on.
local function colorOf(key, pvpColor)
    local mode = db(key)
    if mode == "zone" then return pvpColor end
    if mode == "white" then return Style.INK.VALUE end
    if mode == "label" then return Style.INK.LABEL end
    if mode == "custom" then
        local c = db(key .. "Custom")
        if type(c) == "table" then return c end
    end
    return nil
end

-- The accent's ends and middle, along it when it's a gradient.
local function accentStops()
    if Style.GradientAccent() then
        return { Style.AccentAt(0) }, { Style.AccentAt(0.5) }, { Style.AccentAt(1) }
    end
    local m = { Style.Accent() }
    return m, m, m
end

-- The subzone and PvP lines in their picked colors. Read at paint time, so a
-- new accent shows on the next title.
local function paintSmall(pvpColor)
    local c = colorOf("zoneTitleSubColor", pvpColor)
    if db("zoneTitleSubColor") == "name" then c = f.nameRGB end
    if db("zoneTitleSubColor") == "accent" then c = { Style.Accent() } end
    c = c or Style.INK.LABEL
    f.sub:SetTextColor(c[1], c[2], c[3])
    local p = colorOf("zoneTitlePvPColor", f.pvpColor) or WARM
    f.pvp:SetTextColor(p[1], p[2], p[3])
end

-- Paints the name in the accent (letter by letter along a gradient accent) or
-- in the color picked, and the line under it the same way, or in its own
-- color. The line is bright in the middle and fades out at the ends; the
-- haze, diamond and shine take the line's middle color.
local function paint(zone, pvpColor)
    if on("zoneTitleCaps") then zone = Style.Upper(zone) end
    local na, nm, nb
    local c = colorOf("zoneTitleColor", pvpColor)
    if c then
        f.name:SetText(zone)
        f.name:SetTextColor(c[1], c[2], c[3])
        na, nm, nb = c, c, c
    else
        Style.PaintAccentText(f.name, zone)
        na, nm, nb = accentStops()
    end
    f.nameRGB = nm

    local a, m, b = na, nm, nb
    if db("zoneTitleLineColor") ~= "name" then
        local l = db("zoneTitleLineColor") ~= "accent" and colorOf("zoneTitleLineColor", pvpColor)
        if l then a, m, b = l, l, l else a, m, b = accentStops() end
    end
    f.left:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 0), CreateColor(m[1], m[2], m[3], 1))
    f.right:SetGradient("HORIZONTAL", CreateColor(m[1], m[2], m[3], 1), CreateColor(b[1], b[2], b[3], 0))
    f.haze:SetVertexColor(m[1], m[2], m[3])
    f.gem:SetVertexColor(m[1], m[2], m[3])
    -- The light is the middle's color lifted most of the way to white.
    f.shineColor = { m[1] + (1 - m[1]) * 0.6, m[2] + (1 - m[2]) * 0.6, m[3] + (1 - m[3]) * 0.6 }
end

-- The line at fraction p of its full spread. Hidden at zero, otherwise its
-- 1 px middle shows as a dot above a lone subzone.
local function spread(p)
    local w = math.max(1, ZoneTitle.WIDTH * p)
    f.left:SetWidth(w / 2)
    f.right:SetWidth(w / 2)
    f.left:SetShown(p > 0)
    f.right:SetShown(p > 0)
    -- The diamond grows in over the second half, once the line is under way.
    local g = on("zoneTitleGem") and math.max(0, p * 2 - 1) or 0
    f.gem:SetShown(g > 0)
    if g > 0 then
        local px = math.max(1, ZoneTitle.GEM_SIZE * g)
        f.gem:SetSize(px, px)
        f.gem:SetAlpha(g)
    end
    f.haze:SetAlpha(on("zoneTitleHaze") and ZoneTitle.HAZE_ALPHA * p or 0)
end

local function place(p)
    f:ClearAllPoints()
    f:SetPoint("CENTER", holder, "CENTER", 0, ZoneTitle.DRIFT * p)
end

-- A soft light runs across the name as it lands.
local function shine()
    if not on("zoneTitleShine") then return end
    Motion.Sweep(f.shine, f.band, { width = ZoneTitle.SHINE_W, dur = Motion.SLOW * 2,
        alpha = ZoneTitle.SHINE_ALPHA, color = f.shineColor, key = "zonetitle:shine" })
end

local function rise(p)
    f.name:SetPoint("BOTTOM", f, "CENTER", 0, 6 - ZoneTitle.RISE * (1 - p))
end

-- The PvP line under the subzone, or under the line with no subzone.
local function setPvP(text, color)
    f.pvp:ClearAllPoints()
    if f.sub:GetText() ~= nil and f.sub:GetText() ~= "" then
        f.pvp:SetPoint("TOP", f.sub, "BOTTOM", 0, -4)
    else
        f.pvp:SetPoint("TOP", f, "CENTER", 0, -8)
    end
    f.pvp:SetText(text or "")
    f.pvpColor = color
    paintSmall(color)
end

-- Starts a show: a new id, everything at rest, the frame up.
local function begin()
    build()
    size()
    sample = false
    run = run + 1
    local id = run
    local function later(t, fn)
        C_Timer.After(t, function() if id == run then fn() end end)
    end
    f.name:SetAlpha(0)
    f.shine:Hide()
    Motion.Fade(f.sub, 0, 0, 0)   -- stops a fade-in still playing from the last show
    Motion.Fade(f.pvp, 0, 0, 0)
    spread(0)
    rise(0)
    place(0)
    f:SetAlpha(1)
    f:Show()
    return id, later
end

-- It drifts up and fades away.
local function out(id)
    Motion.Tween("zonetitle:out", 0, 1, Motion.CLOSE, function(p)
        if id ~= run then return end
        place(p)
        f:SetAlpha(1 - p)
    end, function() if id == run then f:Hide() end end)
end

-- The Daylight level-up or reputation banner, or the game's toasts, have the top of the screen. The game's
-- IsCurrentlyToasting hands back the toast frame (or nil), and a right-click
-- hides the manager with it still set (EventToastManager.lua).
local function busy()
    if ns.LevelUp and ns.LevelUp.Showing() then return true end
    if ns.RepBanner and ns.RepBanner.Showing() then return true end
    if ns.Flight and ns.Flight.Welcoming() then return true end
    local m = _G.EventToastManagerFrame
    return type(m) == "table" and type(m.IsCurrentlyToasting) == "function" and m:IsShown()
        and m:IsCurrentlyToasting() ~= nil
end

-- The zone's PvP line and color, from the game's own strings. isSub means the
-- game shows it with the subzone (an arena inside a zone, a combat zone).
function ZoneTitle.PvP()
    local get = C_PvP and C_PvP.GetZonePVPInfo
    if type(get) ~= "function" then return "" end
    local kind, isSub, faction = get()
    if type(kind) ~= "string" or secret(kind) then return "" end
    local text
    if kind == "sanctuary" then text = SANCTUARY_TERRITORY
    elseif kind == "arena" then text = FREE_FOR_ALL_TERRITORY
    elseif kind == "contested" then text = CONTESTED_TERRITORY
    elseif kind == "combat" then text = COMBAT_ZONE; isSub = true
    elseif (kind == "friendly" or kind == "hostile") and type(faction) == "string" and not secret(faction)
        and faction ~= "" and type(FACTION_CONTROLLED_TERRITORY) == "string" then
        text = string.format(FACTION_CONTROLLED_TERRITORY, faction)
    end
    if type(text) ~= "string" then return "" end
    return text, ZoneTitle.COLORS[kind], isSub == true
end

-- The whole title: zone name, line, subzone, PvP line.
function ZoneTitle.Play(zone, sub, pvp, color)
    if type(zone) ~= "string" or zone == "" then return end
    if not on("zoneTitleSub") then sub = "" end
    if not on("zoneTitlePvP") then pvp = nil end
    local id, later = begin()
    full = id
    paint(zone, color)
    f.sub:SetText(sub or "")
    setPvP(pvp, color)

    -- 1. The name rises in as the line draws out from the middle.
    Motion.Tween("zonetitle:in", 0, 1, Motion.SLOW, function(p)
        if id ~= run then return end
        rise(p)
        f.name:SetAlpha(p)
        spread(p)
    end)
    -- 2. The subzone and PvP line under it.
    later(0.25, function()
        Motion.Fade(f.sub, 0, 1, Motion.NORMAL)
        Motion.Fade(f.pvp, 0, 1, Motion.NORMAL)
    end)
    -- 3. As the name lands, a light runs across it.
    later(Motion.SLOW * 0.6, shine)
    -- 4. It holds, then goes.
    later(Motion.SLOW + num("zoneTitleHold", ZoneTitle.HOLD), function() out(id) end)
end

-- Just the subzone (and an arena's PvP line), small, where it sits under the
-- title. While the whole title shows, its subzone line changes in place.
function ZoneTitle.Sub(sub, pvp, color)
    if type(sub) ~= "string" or sub == "" or not on("zoneTitleSub") then return end
    if not on("zoneTitlePvP") then pvp = nil end
    if f and f:IsShown() and full == run and not sample then
        if f.sub:GetText() == sub then return end   -- the game often sends two events at once
        f.sub:SetText(sub)
        setPvP(f.pvp:GetText(), f.pvpColor)
        Motion.Fade(f.sub, 0, 1, Motion.NORMAL)
        return
    end
    if not on("zoneTitleSubAlone") then return end
    local id, later = begin()
    f.nameRGB = colorOf("zoneTitleColor", color) or { Style.Accent() }
    f.name:SetText("")
    f.sub:SetText(sub)
    setPvP(pvp, color)
    Motion.Fade(f.sub, 0, 1, Motion.NORMAL)
    if pvp then Motion.Fade(f.pvp, 0, 1, Motion.NORMAL) end
    later(Motion.NORMAL + ZoneTitle.SUB_HOLD, function() out(id) end)
end

-- Up on screen (the reputation banner waits for it). The still sample in
-- unlock or test mode doesn't hold anything up.
function ZoneTitle.Showing() return f ~= nil and f:IsShown() and not sample end

-- Steps aside at once (a level-up takes the spot, or it was switched off).
function ZoneTitle.Stop()
    if not ZoneTitle.Showing() then return end
    run = run + 1
    out(run)
end

local function sampleWanted()
    if not enabled() then return false end
    if DUI.Movers.unlocked == true then return true end
    return DUI.testMode == true and DUI.TestPartShown(ZoneTitle.TEST_PART) == true
end

local function resample()
    if sample and f then
        sample = false
        f:Hide()
    end
    ZoneTitle.Sample()
end

-- The title standing still while unlock or test mode wants it, so it can be
-- placed and its settings seen. A real zone change plays over it.
function ZoneTitle.Sample()
    if sampleWanted() then
        if ZoneTitle.Showing() then return end
        build()
        size()
        sample = true
        run = run + 1
        full = run
        local s = ZoneTitle.SAMPLE
        local color = ZoneTitle.COLORS[s[3]]
        paint(s[1], color)
        f.sub:SetText(on("zoneTitleSub") and s[2] or "")
        setPvP(on("zoneTitlePvP") and (CONTESTED_TERRITORY or L["Contested Territory"]) or nil, color)
        f.name:SetAlpha(1)
        f.sub:SetAlpha(1)
        f.pvp:SetAlpha(1)
        rise(1)
        spread(1)
        place(0)
        f:SetAlpha(1)
        f:Show()
    elseif sample and f then
        sample = false
        run = run + 1
        f:Hide()
    end
end

function ZoneTitle.Preview()
    local s = ZoneTitle.SAMPLE
    ZoneTitle.Play(s[1], s[2], CONTESTED_TERRITORY or L["Contested Territory"], ZoneTitle.COLORS[s[3]])
end

-- Same rules as the game: a new area or a changed zone name shows the whole
-- title, otherwise a real subzone shows small. While the top of the screen is
-- busy the change is held and shown later by ZoneTitle.Resume.
local function show(newZone)
    local zone, sub = read(GetZoneText), read(GetSubZoneText) or ""
    if not zone then return end
    local pvp, color, isSub = ZoneTitle.PvP()
    if newZone then
        ZoneTitle.Play(zone, sub ~= zone and sub or "", pvp ~= "" and pvp or nil, color)
    elseif sub ~= "" and sub ~= zone then
        ZoneTitle.Sub(sub, isSub and pvp or nil, color)
    end
end

local function onZone(event)
    local zone = read(GetZoneText)
    if not zone then return end
    local newZone = event == "ZONE_CHANGED_NEW_AREA" or zone ~= lastZone
    lastZone = zone
    if not enabled() then return end
    if busy() then
        held = (newZone or held == "zone") and "zone" or "sub"
        return
    end
    held = nil
    show(newZone)
end

-- The level-up or the game's toast has gone (LevelUp calls it): a held change plays now.
function ZoneTitle.Resume()
    if not held or busy() then return end
    local whole = held == "zone"
    held = nil
    if enabled() then show(whole) end
end

local function wire()
    if wired then return end
    wired = true
    DUI.RegisterEvent("ZONE_CHANGED_NEW_AREA", onZone)
    DUI.RegisterEvent("ZONE_CHANGED", onZone)
    DUI.RegisterEvent("ZONE_CHANGED_INDOORS", onZone)
    DUI.RegisterCommand("zone", ZoneTitle.Preview, L["/dui zone - preview the zone title"])
    DUI.RegisterTestPart(ZoneTitle.TEST_PART, "Zone title", 98, enabled)
    DUI.On("TestModeChanged", ZoneTitle.Sample)
    DUI.On("TestPartChanged", function(key) if key == ZoneTitle.TEST_PART then ZoneTitle.Sample() end end)
    DUI.On("UnlockChanged", ZoneTitle.Sample)
    -- The accent or font changed: the sample shows it at once.
    DUI.On("StyleChanged", resample)
    -- The unlock handle needs the holder from the start.
    build()
end

-- The game's zone texts: hidden while this one is on.
local function gameTexts()
    local a = enabled() and 0 or 1
    for _, name in ipairs(GAME_TEXTS) do
        local fs = _G[name]
        if type(fs) == "table" and fs.SetAlpha then fs:SetAlpha(a) end
    end
end

function ZoneTitle.Enable(m)
    mod = m
    wire()
    gameTexts()
end

function ZoneTitle.Refresh(m)
    mod = m
    gameTexts()
    if not enabled() then held = nil end
    if not enabled() and f then run = run + 1; sample = false; f:Hide() end
    -- A setting changed while the sample shows: draw it again with the change.
    resample()
end
