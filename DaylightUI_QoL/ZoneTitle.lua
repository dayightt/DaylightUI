-- Zone title shown when entering a new zone: the name rises in the accent color
-- with a line under it, then the subzone and PvP status. A subzone change alone
-- shows just the small subzone line.
-- Replaces the game's zone text. Its four strings stay at alpha 0 while this is
-- on; the game only fades their parent frames, so one SetAlpha holds.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local ZoneTitle = {
    Y = -192,           -- the name's middle from the screen's top: the game's ZoneTextString (ZoneText.xml)
    WIDTH = 360,        -- the line at full spread
    LINE = 1,           -- its thickness
    NAME = 26, SUB = 15, PVP = 13,
    RISE = 12,          -- px the name rises as it comes in
    HOLD = 2.5,         -- seconds the whole title stays
    SUB_HOLD = 1.5,     -- seconds a subzone alone stays
    DRIFT = 6,          -- px it rises as it goes
    -- The game's PvP colors (SetZoneText), softened like our tooltips'.
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

local GAME_TEXTS = { "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString" }
local WARM = Style.INK.TEXT

local mod, f, wired, lastZone
local held              -- a change that came while busy(): "zone" (the whole title) or "sub"
local run = 0           -- each show's id: a newer one stops the older one's timers
local full = -1         -- the id of the last whole-title show

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.zoneTitle == true end

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- A plain string from one of the game's zone getters, or nil.
local function read(fn)
    if type(fn) ~= "function" then return nil end
    local s = fn()
    if type(s) ~= "string" or secret(s) then return nil end
    return s
end

local function build()
    if f then return f end
    f = CreateFrame("Frame", "DaylightUIZoneTitle", UIParent)
    DUI.Movers.FollowScale(f)
    f:SetSize(ZoneTitle.WIDTH, 1)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()
    -- The top is free again: a reputation banner that waited plays now.
    f:SetScript("OnHide", function() if ns.RepBanner then ns.RepBanner.Resume() end end)

    -- The line: two halves from the middle out (painted per show, paint()).
    f.left = f:CreateTexture(nil, "ARTWORK")
    f.left:SetColorTexture(1, 1, 1, 1)
    f.left:SetPoint("RIGHT", f, "CENTER", 0, 0)
    f.right = f:CreateTexture(nil, "ARTWORK")
    f.right:SetColorTexture(1, 1, 1, 1)
    f.right:SetPoint("LEFT", f, "CENTER", 0, 0)
    f.left:SetHeight(ZoneTitle.LINE)
    f.right:SetHeight(ZoneTitle.LINE)

    f.name = Style.Text(f, ZoneTitle.NAME, "CENTER")
    f.sub = Style.Text(f, ZoneTitle.SUB, "CENTER")
    f.sub:SetPoint("TOP", f, "CENTER", 0, -8)
    Style.InkText(f.sub, "LABEL")
    f.pvp = Style.Text(f, ZoneTitle.PVP, "CENTER")
    return f
end

-- Paints the name and line in the accent, following it along a gradient accent.
-- The line is bright in the middle and fades out at the ends.
local function paint(zone)
    local a, m, b
    Style.PaintAccentText(f.name, zone)
    if Style.GradientAccent() then
        a, m, b = { Style.AccentAt(0) }, { Style.AccentAt(0.5) }, { Style.AccentAt(1) }
    else
        m = { Style.Accent() }
        a, b = m, m
    end
    f.left:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 0), CreateColor(m[1], m[2], m[3], 1))
    f.right:SetGradient("HORIZONTAL", CreateColor(m[1], m[2], m[3], 1), CreateColor(b[1], b[2], b[3], 0))
end

-- The line at fraction p of its full spread. Hidden at zero, otherwise its
-- 1 px middle shows as a dot above a lone subzone.
local function spread(p)
    local w = math.max(1, ZoneTitle.WIDTH * p)
    f.left:SetWidth(w / 2)
    f.right:SetWidth(w / 2)
    f.left:SetShown(p > 0)
    f.right:SetShown(p > 0)
end

local function place(p)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "TOP", 0, ZoneTitle.Y + ZoneTitle.DRIFT * p)
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
    local c = color or WARM
    f.pvpColor = c
    f.pvp:SetTextColor(c[1], c[2], c[3])
end

-- Starts a show: a new id, everything at rest, the frame up.
local function begin()
    build()
    run = run + 1
    local id = run
    local function later(t, fn)
        C_Timer.After(t, function() if id == run then fn() end end)
    end
    f.name:SetAlpha(0)
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

-- Our level-up or reputation banner, or the game's toasts, have the top of the screen. The game's
-- IsCurrentlyToasting hands back the toast frame (or nil), and a right-click
-- hides the manager with it still set (EventToastManager.lua).
local function busy()
    if ns.LevelUp and ns.LevelUp.Showing() then return true end
    if ns.RepBanner and ns.RepBanner.Showing() then return true end
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
    local id, later = begin()
    full = id
    paint(zone)
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
    -- 3. It holds, then goes.
    later(Motion.SLOW + ZoneTitle.HOLD, function() out(id) end)
end

-- Just the subzone (and an arena's PvP line), small, where it sits under the
-- title. While the whole title shows, its subzone line changes in place.
function ZoneTitle.Sub(sub, pvp, color)
    if type(sub) ~= "string" or sub == "" then return end
    if f and f:IsShown() and full == run then
        if f.sub:GetText() == sub then return end   -- the game often sends two events at once
        f.sub:SetText(sub)
        setPvP(f.pvp:GetText(), f.pvpColor)
        Motion.Fade(f.sub, 0, 1, Motion.NORMAL)
        return
    end
    local id, later = begin()
    f.name:SetText("")
    f.sub:SetText(sub)
    setPvP(pvp, color)
    Motion.Fade(f.sub, 0, 1, Motion.NORMAL)
    if pvp then Motion.Fade(f.pvp, 0, 1, Motion.NORMAL) end
    later(Motion.NORMAL + ZoneTitle.SUB_HOLD, function() out(id) end)
end

-- Up on screen (the reputation banner waits for it).
function ZoneTitle.Showing() return f ~= nil and f:IsShown() end

-- Steps aside at once (a level-up takes the spot, or it was switched off).
function ZoneTitle.Stop()
    if not (f and f:IsShown()) then return end
    run = run + 1
    out(run)
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
end

-- The game's zone texts: hidden while ours is on.
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
    if not enabled() and f then run = run + 1; f:Hide() end
end
