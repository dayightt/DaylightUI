-- A plate's auras through the client's aura containers. Nothing reads aura data,
-- so they stay current in combat. Placement is a setting (Plate.PlaceSpots); by
-- default:
-- * your debuffs in a row centered above the name, growing both ways;
-- * crowd control on the unit as one larger icon beside the bar's right end;
-- * a big defensive (Divine Shield, Ice Block...) as one larger icon past it;
-- * buffs you can purge or steal in a row above your debuffs, from the right end,
--   each with a soft halo;
-- * friendly plates only: your own buffs and HoTs centered above the name.
-- Nothing is ever anchored to a container (the client refuses that once it holds
-- aura groups); the containers are anchored to the plate's bar or its marks.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Auras = {}
ns.Auras = Auras

Auras.GAP = 2 -- gap between icons
Auras.ABOVE = 2 -- gap between the name and the first row
-- Target aura look: slightly wider than tall, art cropped rather than squashed,
-- a 2 px edge in the dispel type's color (dark wine when there's none), a soft
-- inner shadow, and the time on the top edge.
Auras.ASPECT = 0.88
Auras.BORDER_PX = 2
Auras.TIME_COLOR = DUI.Style.INK.VALUE
Auras.NO_DISPEL = { 0.6, 0.16, 0.18 }
Auras.DISPEL_COLORS = {
    None = Auras.NO_DISPEL, Magic = { 0.25, 0.55, 0.95 }, Curse = { 0.62, 0.3, 0.9 },
    Disease = { 0.7, 0.5, 0.18 }, Poison = { 0.3, 0.7, 0.25 }, Bleed = { 0.78, 0.14, 0.14 },
}

-- Dispel type color: the unit frames' Colors page pick (colors.dispelMagic...)
-- when that module is on, else ours (like the buffs' BL.DispelColor). Read when a
-- button is made, so edges already on screen pick up a change after /reload, as
-- on the unit frames.
function Auras.DispelColor(key)
    local c = DUI:Get("UnitFrames", "colors.dispel" .. key)
    if type(c) == "table" then return c end
    return Auras.DISPEL_COLORS[key]
end
Auras.KINDS = {
    debuffs = { key = "mine", filter = "HARMFUL|PLAYER|!CROWD_CONTROL" },
    cc = { key = "cc", filter = "HARMFUL|CROWD_CONTROL" },
    -- The client flags big defensives itself, so no spell list here either.
    defensives = { key = "big", filter = "HELPFUL|BIG_DEFENSIVE" },
    -- The client picks these from what you (and your group) can remove, so no spell
    -- list here. Use a filter string, never candidateFilters: those read aura data,
    -- which is secret on enemies in PvP, and the row would show nothing.
    buffs = { key = "steal", filter = "HELPFUL|RAID_PLAYER_DISPELLABLE" },
    helps = { key = "helps", filter = "HELPFUL|PLAYER", friendly = true }, -- friendly plates: your buffs and HoTs
}

local buttons = setmetatable({}, { __mode = "k" })   -- button -> { kind, pieces }

local function call(c, name, ...)
    local fn = c[name]
    if type(fn) == "function" then return pcall(fn, c, ...) end
end

-- Text on the client's buttons is kept out of the global repaint (which would read
-- them) and set here when the plate is laid out.
local UNTRACKED = { untracked = true }
local function text(btn, justify)
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH(justify)
    Style.DressText(fs, 9, UNTRACKED)
    return fs
end

local function font(fs, size) Style.DressText(fs, size, UNTRACKED) end

-- Time text size for an icon (the target's: 9 on 16, 12 on 26).
local function timeSize(size) return math.max(8, math.floor(size * 0.3 + 4 + 0.5)) end

-- An icon's height for its width.
local function heightOf(size) return math.floor(size * Auras.ASPECT + 0.5) end

-- Crops the art top and bottom so a wide icon doesn't squash it.
local function iconCoords(w, h)
    local span = 0.84 * h / w
    return 0.08, 0.92, 0.5 - span / 2, 0.5 + span / 2
end

-- The edge takes the aura's dispel type color, chosen by the client since the type
-- can be secret: our colors via the enum style and color objects, or the client's
-- own if ours are refused.
local function dispelEdge(btn, edge, helpful)
    Style.DispelEdge(btn, edge, function(key) return Auras.DispelColor(key) or Auras.NO_DISPEL end,
        { helpful = helpful })
end

-- A debuff, crowd control (or buff) icon in the target aura look.
local function initSquare(btn, what)
    local b = {}
    b.edge = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.edge:SetAllPoints(btn)
    local w = Auras.NO_DISPEL
    b.edge:SetVertexColor(w[1], w[2], w[3], 1)
    dispelEdge(btn, b.edge, what == "buffs" or what == "helps" or what == "defensives")
    -- Purgeable buffs also get a soft halo.
    if what == "buffs" then b.halo = Style.AuraHalo(btn, Auras.DispelColor, false, true) end
    b.icon = btn:CreateTexture(nil, "ARTWORK")
    btn:SetIcon(b.icon)
    b.shade = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    b.shade:SetTexture(DUI.MEDIA .. "inner-shadow.png")
    b.shade:SetVertexColor(0, 0, 0, 1)
    -- The time is a number: no clock sweep, no countdown numbers.
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
    if ok and cd then
        pcall(cd.SetDrawSwipe, cd, false)
        pcall(cd.SetDrawEdge, cd, false)
        pcall(cd.SetDrawBling, cd, false)
        pcall(cd.SetHideCountdownNumbers, cd, true)
        cd:EnableMouse(false)
        pcall(btn.SetDurationCooldown, btn, cd)
        b.cd = cd
    end
    b.time = text(btn, "CENTER")
    local c = Auras.TIME_COLOR
    b.time:SetTextColor(c[1], c[2], c[3])
    Style.SetAuraTime(btn, b.time)
    b.count = text(btn, "RIGHT")
    btn:SetApplicationCount(b.count)
    buttons[btn] = b
    return b
end

local function sizeOf(what)
    local c = ns.cfg
    if what == "debuffs" then return c.debuffSize end
    if what == "cc" then return c.ccSize end
    if what == "defensives" then return c.defensiveSize end
    if what == "helps" then return c.friendly.myBuffSize end
    return c.buffSize
end

-- The buttons belong to the client, which can close one to addons at any time.
-- Nothing here reads a button (its pixel size comes from the plate, which has the
-- same scale), and a refused change is skipped rather than erroring.
local function fitNow(btn, size, p)
    local b = buttons[btn]
    if not b then return end
    local T = Pixel.Px(p, Auras.BORDER_PX)
    b.size, b.T = size, T -- what it was last fitted to (Auras.Layout)
    local h = heightOf(size)
    btn:SetSize(size, h)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", T, -T)
    b.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
    b.icon:SetTexCoord(iconCoords(size, h))
    Style.PlaceAuraHalo(b.halo, btn, size)
    b.shade:ClearAllPoints()
    b.shade:SetAllPoints(b.icon)
    if b.cd then
        b.cd:ClearAllPoints()
        b.cd:SetAllPoints(b.icon)
    end
    font(b.time, timeSize(size))
    b.time:ClearAllPoints()
    b.time:SetPoint("CENTER", btn, "TOP", 0, 0)
    font(b.count, timeSize(size))
    b.count:ClearAllPoints()
    b.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 0)
end

local function fit(btn, size, p)
    pcall(fitNow, btn, size, p)
end

-- Resizes buttons the client already made. They're locked to addons in combat and
-- under the client's restrictions (a battleground, even between fights), so only
-- a real change is made, and only once those lift.
local pending = setmetatable({}, { __mode = "k" }) -- plate -> true

local function refit(p)
    for what, c in pairs(p.auras or {}) do
        local size = sizeOf(what)
        local T = Pixel.Px(p, Auras.BORDER_PX)
        for _, btn in ipairs(c.buttons or {}) do
            local b = buttons[btn]
            if b and (b.size ~= size or b.T ~= T) then fit(btn, size, p) end
        end
    end
end

local function needsFit(p)
    for what, c in pairs(p.auras or {}) do
        local size = sizeOf(what)
        local T = Pixel.Px(p, Auras.BORDER_PX)
        for _, btn in ipairs(c.buttons or {}) do
            local b = buttons[btn]
            if b and (b.size ~= size or b.T ~= T) then return true end
        end
    end
    return false
end

function Auras.FitPending()
    for p in pairs(pending) do
        pending[p] = nil
        if p.unit and (not ns.Manager or ns.Manager.Usable(p)) then refit(p) end
    end
end

function Auras.Fit(p)
    if not needsFit(p) then return end
    if DUI.Restricted() then
        pending[p] = true
        DUI.AfterRestrictions(Auras.FitPending, "nameplates:aurafit")
    else
        refit(p)
    end
end

local function groupLayout(what)
    local s = sizeOf(what)
    return { layoutIndex = 1, elementWidth = s, elementHeight = heightOf(s), elementSpacing = Auras.GAP,
             lineSpacing = Auras.GAP + math.ceil(timeSize(s) / 2) }
end

local function newContainer(p, what)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, p, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    c:EnableMouse(false)
    local k = Auras.KINDS[what]
    c.kind = what
    c.buttons = {}
    local ok2, err = pcall(c.AddAuraGroup, c, k.key, k.filter, {
        candidateFilters = k.candidateFilters,
        sortMethod = AuraContainerSortMethod.ExpirationOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        maxFrameCount = 0,
        layout = groupLayout(what),
        initializeFrame = function(btn)
            initSquare(btn, what)
            pcall(btn.SetTooltipAnchorPoint, btn, "ANCHOR_TOP")
            c.buttons[#c.buttons + 1] = btn
            fit(btn, sizeOf(what), p)
        end,
    })
    if not ok2 then DUI.Print(string.format(DUI.L["Nameplate auras (%s): %s"], what, tostring(err))) end
    return c
end

function Auras.Create(p)
    p.auras = {}
    for _, what in ipairs({ "debuffs", "cc", "defensives", "buffs", "helps" }) do
        p.auras[what] = newContainer(p, what)
    end
end

local function flow(c, point, h, v, line)
    local fd = AnchorUtil and AnchorUtil.FlowDirection
    call(c, "SetFlowLayoutAnchorPoint", point)
    if fd then call(c, "SetFlowLayoutGrowthDirection", fd[h], fd[v]) end
    call(c, "SetFlowLayoutMaximumLineSize", line)
end

-- Places a row (a client container, or the preview's stand-in row) where
-- Plate.PlaceSpots decided: at = { L = Spots.Layout's result, rel }.
-- Your debuffs (and a friendly plate's buffs) are never sized: the client sizes
-- the container to its icons, so anchored by its bottom center the row stays
-- centered and grows both ways. The purgeable buff row is the bar's width when it
-- grows from one end. The time sits on each icon's top edge, so no space is
-- reserved below.
function Auras.Place(f, what, at, p)
    local cfg, L = ns.cfg, at.L
    f:ClearAllPoints()
    f:SetPoint(L.point, at.rel, L.relPoint, L.x, L.y)
    if what == "cc" or what == "defensives" then
        local s = sizeOf(what)
        f:SetSize(s, heightOf(s))
        flow(f, "LEFT", "Right", "Up", s)
        return
    end
    if what == "buffs" and L.point ~= "BOTTOM" and L.point ~= "TOP" then
        f:SetSize(p.hp:GetWidth(), cfg.buffSize)
    end
    flow(f, L.flowAnchor, L.hDir, L.vDir, L.line)
end

-- A row's footprint: across, every icon it can show; up, an icon with its time
-- above it (crowd control: just the icon).
function Auras.Room(what)
    local c = ns.cfg
    local s = sizeOf(what)
    local n = 1
    if what == "debuffs" then n = c.maxDebuffs
    elseif what == "buffs" then n = c.maxBuffs
    elseif what == "helps" then n = type(c.friendly) == "table" and c.friendly.maxMyBuffs end
    n = math.max(1, tonumber(n) or 1)
    local single = what == "cc" or what == "defensives"
    local up = heightOf(s) + (single and 0 or math.ceil(timeSize(s) / 2))
    return n * s + (n - 1) * Auras.GAP, up
end

function Auras.Layout(p)
    local cfg = ns.cfg
    local a = p.auras
    -- Where each row goes is set by Plate.PlaceSpots after this.
    local d = a.debuffs
    if d then
        call(d, "SetAuraGroupLayout", "mine", groupLayout("debuffs"))
        call(d, "SetAuraGroupMaxFrameCount", "mine", cfg.debuffs and cfg.maxDebuffs or 0)
    end
    local cc = a.cc
    if cc then
        call(cc, "SetAuraGroupLayout", "cc", groupLayout("cc"))
        call(cc, "SetAuraGroupMaxFrameCount", "cc", cfg.cc and 1 or 0)
    end
    local big = a.defensives
    if big then
        call(big, "SetAuraGroupLayout", "big", groupLayout("defensives"))
        call(big, "SetAuraGroupMaxFrameCount", "big", cfg.defensives and 1 or 0)
    end
    local b = a.buffs
    if b then
        call(b, "SetAuraGroupLayout", "steal", groupLayout("buffs"))
        call(b, "SetAuraGroupMaxFrameCount", "steal", cfg.buffs and cfg.maxBuffs or 0)
    end
    local m = a.helps
    if m then
        local f = type(cfg.friendly) == "table" and cfg.friendly or {}
        call(m, "SetAuraGroupLayout", "helps", groupLayout("helps"))
        call(m, "SetAuraGroupMaxFrameCount", "helps", f.myBuffs and f.maxMyBuffs or 0)
    end
    -- Resize buttons that already exist.
    Auras.Fit(p)
end

-- ---------------------------------------------------------------------
-- Options preview (Sample.lua)
-- ---------------------------------------------------------------------

-- A client container only shows a real unit's auras, so the preview draws
-- stand-ins: plain icons with the same look (dispel-colored edge, cropped art,
-- inner shadow, time on the top edge, halo on a purgeable buff), fitted by the
-- same code as the client's buttons.
local function newSample(row, what)
    local btn = CreateFrame("Frame", nil, row)
    local b = {}
    b.edge = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.edge:SetAllPoints(btn)
    if what == "buffs" then
        b.halo = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        b.halo:SetTexture(Style.AURA_HALO)
        b.halo:SetBlendMode("ADD")
    end
    b.icon = btn:CreateTexture(nil, "ARTWORK")
    b.shade = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    b.shade:SetTexture(DUI.MEDIA .. "inner-shadow.png")
    b.shade:SetVertexColor(0, 0, 0, 1)
    b.time = text(btn, "CENTER")
    local c = Auras.TIME_COLOR
    b.time:SetTextColor(c[1], c[2], c[3])
    b.count = text(btn, "RIGHT")
    buttons[btn] = b
    return btn
end

-- The stand-in row for what ("debuffs", "cc", "buffs", "helps") on a preview
-- plate, created on first use.
local function sampleRow(p, what)
    p.sampleAuras = p.sampleAuras or {}
    local row = p.sampleAuras[what]
    if not row then
        row = CreateFrame("Frame", nil, p)
        row.icons = {}
        p.sampleAuras[what] = row
    end
    return row
end

-- Shows list (icons: { icon, time, dispel, count }) in the what row, laid out the
-- way the client lays out its own (flow and spacing). An empty list hides it.
-- Returns the row.
function Auras.ShowSample(p, what, list)
    local row = sampleRow(p, what)
    local n = #list
    if n == 0 then
        row:Hide()
        return row
    end
    local size = sizeOf(what)
    local h, gap = heightOf(size), Auras.GAP
    -- Where Plate.PlaceSpots put the row (or here, for a new one), sized to its icons
    -- and filled from the end it grows away from.
    local at = p.spotAt and p.spotAt[what]
    if at then Auras.Place(row, what, at, p) end
    row:SetSize(n * size + (n - 1) * gap, h)
    local fromRight = at ~= nil and at.L.hDir == "Left"
    for i, aura in ipairs(list) do
        local btn = row.icons[i] or newSample(row, what)
        row.icons[i] = btn
        local b = buttons[btn]
        fitNow(btn, size, p)
        btn:ClearAllPoints()
        local x = (i - 1) * (size + gap)
        if fromRight then
            btn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -x, 0)
        else
            btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
        end
        local col = Auras.DispelColor(aura.dispel or "None") or Auras.NO_DISPEL
        b.edge:SetVertexColor(Style.Soften(col[1], col[2], col[3]))
        if b.halo then
            local m = Auras.DispelColor(aura.dispel or "Magic") or Auras.DispelColor("Magic")
            b.halo:SetVertexColor(Style.Soften(m[1], m[2], m[3]))
        end
        b.icon:SetTexture(aura.icon)
        b.time:SetText(aura.time or "")
        b.count:SetText(aura.count and tostring(aura.count) or "")
        btn:Show()
    end
    for i = n + 1, #row.icons do row.icons[i]:Hide() end
    row:Show()
    return row
end

-- Points the containers at the plate's unit (nil = none). Enemy plates get all of
-- them; friendly plates only the one for your own buffs (when enabled).
function Auras.SetUnit(p, unit)
    local fc = ns.cfg.friendly
    local mine = type(fc) == "table" and fc.myBuffs == true
    for what, c in pairs(p.auras or {}) do
        local friendly = Auras.KINDS[what].friendly == true
        if unit and friendly == (p.friendly == true) and (mine or not friendly) then
            call(c, "SetUnit", unit)
            call(c, "SetEnabled", true)
            c:Show()
        else
            call(c, "SetEnabled", false)
            c:Hide()
        end
    end
end
