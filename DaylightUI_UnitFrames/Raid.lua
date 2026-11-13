-- Raid frames: small tiles, one column per group, groups left to right, built
-- and placed by the group engine (Group.lua). A secure group header sits in a
-- plain holder that carries the position and mover (or, when sorted by group
-- then role, one header per group). Test mode shows a sample raid of plain,
-- non-secure tiles.

local _, ns = ...
local DUI = DaylightUI
local UF = ns.UF

local Raid = {}
ns.Raid = Raid

Raid.GROUPS = 8
Raid.PER_GROUP = 5

-- What a raid tile is made of: a compact frame with the name on the bar, a thin
-- border like the name tabs, an optional power bar, and aggro on the border.
Raid.SPEC = {
    group = "raid", compact = true, slant = "right", power = true, marker = true, leaderIcon = true, range = true, groupThreat = true,
    threatOnFrame = true, role = true, shell = { borderPx = UF.TAB_BORDER },
}

local function db() return ns.module and ns.module.db end

Raid.SAMPLE_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "PALADIN", "HUNTER", "WARLOCK", "DRUID", "SHAMAN" }
Raid.SAMPLE_NAMES = {
    "Kaladin", "Lift", "Jasnah", "Lopen", "Adolin", "Rock", "Shallan", "Renarin", "Skar", "Teft",
    "Dalinar", "Navani", "Sigzil", "Drehy", "Peet", "Leyten", "Hobber", "Moash", "Szeth", "Wit",
    "Kabsal", "Taravangian", "Eshonai", "Venli", "Rlain", "Zahel", "Nale", "Ym", "Lirin", "Hesina",
    "Tien", "Elhokar", "Gavilar", "Sja-anat", "Palona", "Shalash", "Taln", "Ishar", "Kelek", "Vev",
}

function Raid.SampleFor(i)
    local class = Raid.SAMPLE_CLASSES[(i - 1) % #Raid.SAMPLE_CLASSES + 1]
    local hp = 100 - ((i * 37) % 60)
    local s = { name = Raid.SAMPLE_NAMES[i] or string.format(DUI.L["Member %d"], i), class = class, health = hp,
                healthValue = hp * 30, power = 60, powerValue = 1500, powerToken = class == "WARRIOR" and "RAGE" or
                (class == "ROGUE" and "ENERGY" or "MANA"), portraitClass = class }
    if i == 1 then s.threat = "aggro"; s.marker = 8; s.leader = true end
    if i == 7 then s.marker = 2 end
    if i == 4 then s.target = true end   -- your target, shown with its outline
    if i == 4 then s.heals = 20 end
    if i == 9 then s.absorbs = 15 end
    -- A tank and a healer here and there, not always at the top of a group.
    local roles = { [1] = "TANK", [2] = "HEALER", [9] = "TANK", [7] = "HEALER", [15] = "HEALER",
                    [18] = "TANK", [24] = "HEALER", [33] = "HEALER" }
    s.role = roles[i] or "DAMAGER"
    -- A few have something you could dispel.
    local dispels = { [3] = "Magic", [12] = "Curse", [18] = "Poison", [27] = "Disease" }
    s.dispel = dispels[i]
    return s
end

-- The Raid page's single preview tile. Every piece that can show is on (marker,
-- crown, role, dispel, ready check), but no aggro border, and a mana bar.
function Raid.FullSample()
    local s = Raid.SampleFor(1)
    s.class, s.portraitClass, s.powerToken = "PALADIN", "PALADIN", "MANA"
    s.health, s.healthValue = 70, 2100
    s.threat, s.dispel, s.target, s.ready = nil, "Magic", true, "ready"
    return s
end

Raid.ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }

-- Sample for preview slot i, in order, or when sorting by group then role, the
-- samples of i's group of five in role order, as the headers would sort them.
function Raid.PreviewSample(i, cfg)
    if not (cfg and cfg.sortBy == "grouprole") then return Raid.SampleFor(i) end
    local first = i - (i - 1) % Raid.PER_GROUP
    local list = {}
    for k = first, first + Raid.PER_GROUP - 1 do list[#list + 1] = Raid.SampleFor(k) end
    table.sort(list, function(a, b)
        local ra, rb = Raid.ROLE_RANK[a.role], Raid.ROLE_RANK[b.role]
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list[i - first + 1]
end

-- Setups by raid size. Up to 10 players use raid / raidText, 11 to 20 use
-- raid20, 21 to 40 use raid40 (Defaults.lua), unless that size follows 10
-- (the default). Switches, fade, textures and fonts are always raid's
-- (ns.RAID_SHARED). The header is laid out for one size at a time
-- (Raid.laidKey). When a raid grows past 10 or 20 it swaps after combat,
-- since that's protected, and the header keeps adding tiles at the old size.

Raid.SIZES = { 10, 20, 40 }
-- The size the last shown Raid 10 / 20 / 40 page edits (not saved). Test mode
-- shows it too. nil before any page opens, and test mode then shows 40.
Raid.editing = nil

-- The size a group of n players runs: 10, 20 or 40.
function Raid.SizeFor(n)
    if n <= 10 then return 10 elseif n <= 20 then return 20 end
    return 40
end

-- Players in the group now, 0 when alone.
function Raid.Members()
    local n = GetNumGroupMembers and GetNumGroupMembers()
    if issecretvalue and issecretvalue(n) then return 0 end
    return type(n) == "number" and n or 0
end

-- The settings key a size uses: "raid", or "raid20" / "raid40" once that size
-- stops following 10.
function Raid.KeyFor(d, size)
    if size == 10 or type(d) ~= "table" then return "raid" end
    local own = d["raid" .. tostring(size)]
    if type(own) ~= "table" or own.follow ~= false then return "raid" end
    return "raid" .. size
end

-- The size the raid pages edit: the last one shown, or 40 before any.
function Raid.Editing()
    return Raid.editing or 40
end

-- The size shown now: the page's pick in test mode, otherwise the raid's.
function Raid.ShownSize()
    if Raid.group:Previewing() then return Raid.Editing() end
    return Raid.SizeFor(Raid.Members())
end

-- The settings in use for size (defaults to the size shown now): cfg, text, key.
function Raid.Config(d, size)
    local key = Raid.KeyFor(d, size or Raid.ShownSize())
    return d[key], d[key .. "Text"], key
end

-- Whether size (defaults to the one the pages edit) follows 10. If so, its
-- page's rows are grayed out.
function Raid.Locked(size)
    size = size or Raid.Editing()
    return size ~= 10 and Raid.KeyFor(db(), size) == "raid"
end

-- Maps a raid page key ("raid.width", "raidText.name") to the key size uses
-- ("raid20.width"). size defaults to the edited one. Shared keys stay raid's.
function Raid.MapKey(key, size)
    if type(key) ~= "string" then return key end
    local d = db()
    local to = d and Raid.KeyFor(d, size or Raid.Editing()) or "raid"
    if to == "raid" then return key end
    local field, rest = string.match(key, "^raid%.([^%.]+)(.*)$")
    if field then
        if ns.RAID_SHARED[field] then return key end
        return to .. "." .. field .. rest
    end
    local t = string.match(key, "^raidText%.(.+)$")
    if t then return to .. "Text." .. t end
    return key
end

-- What a raid page button acts on ("raid" means the size being edited).
function Raid.PageFrame(frame)
    if frame ~= "raid" then return frame end
    local d = db()
    return d and Raid.KeyFor(d, Raid.Editing()) or "raid"
end

-- Sets the size a raid page edits, as it opens or when a row is used. Its
-- preview and test mode show that size.
function Raid.SetEditing(size)
    if Raid.editing == size then return end
    Raid.editing = size
    local d = db()
    if d and DUI.testMode then DUI.AfterCombat(function() Raid.LayoutNow(d) end, "raid:preview") end
end

-- A size's Follow 10 switch. The first time it's turned off, the size's own
-- setup starts as a copy of 10's (raid, raidText) so nothing jumps.
function Raid.SetFollow(size, on)
    local d = db()
    if not d then return end
    local key = "raid" .. tostring(size)
    if on or d[key].own == true then
        DUI:Set("UnitFrames", key .. ".follow", on == true)
        return
    end
    Raid.CopyTen(size)
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- Copies the 10-player setup onto size, which then has its own.
function Raid.CopyTen(size)
    local d = db()
    if not d then return end
    local key = "raid" .. tostring(size)
    local t = {}
    for k, v in pairs(d.raid) do
        if not ns.RAID_SHARED[k] then t[k] = copy(v) end
    end
    t.own, t.follow = true, false
    t.ownSpot = d[key].ownSpot   -- its position isn't part of its look
    DUI.DB.SetPath(d, key .. "Text", copy(d.raidText))
    DUI:Set("UnitFrames", key, t)
end

-- Test mode's raid: the size the pages edit, or forty before any page opens.
function Raid.PreviewCount() return Raid.Editing() end

-- The 10-player settings hold the raid's switches, shared by every size.
local function base()
    local d = db()
    return d and d.raid
end

Raid.group = ns.Group.New({
    key = "raid", name = "DaylightUIRaid", spec = Raid.SPEC, maxCount = Raid.GROUPS * Raid.PER_GROUP,
    auraGroups = true,
    groupHeaders = Raid.GROUPS,
    attrs = { showRaid = true, showParty = false, showPlayer = true, showSolo = false },
    -- The size the header is laid out for. A tile created mid-fight matches it.
    config = function()
        local d = db()
        if not d then return nil end
        local key = Raid.laidKey or Raid.KeyFor(d, Raid.ShownSize())
        if type(d[key]) ~= "table" then key = "raid" end
        return d[key], d[key .. "Text"], d
    end,
    isOn = function() local b = base(); return b ~= nil and b.enabled == true end,
    count = function(cfg) return ns.Group.GroupsShown(cfg, Raid.GROUPS) * Raid.PER_GROUP end,
    previewCount = Raid.PreviewCount,
    visibility = function()
        local G = ns.Group
        return G.IN_RAID .. (Raid.InParty(base()) and G.IN_PARTY or "") .. " show; hide"
    end,
    sampleFor = function(i, cfg) return Raid.PreviewSample(i, cfg) end,
    fullSample = function() return Raid.FullSample() end,
    sampleUnit = function(i) return "raid" .. i end,
    dress = function(b) Raid.DressSample(b) end,
    showSample = function(b, i, cfg) Raid.ShowSample(b, i, cfg) end,
    hideSample = function(b) Raid.HideSample(b) end,
})
Raid.buttons = Raid.group.buttons   -- every button set up so far (Group:Take)

-- Sample tiles (test mode, the Raid page preview) carry the aura groups on
-- stand-ins, placed and filled from the settings.
function Raid.DressSample(b)
    if b.preview then b.sampleSet = ns.AuraGroups.PlainSet(b) end
end

function Raid.ShowSample(b, i, cfg)
    local box, n = ns.AuraGroups.Box(b, cfg), not b.fullSample and i or nil
    ns.AuraGroups.ShowSample(b.sampleSet, b, cfg.auras, box, n)
    ns.Indicators.ShowSample(b.sampleSet, b, cfg.indicators, box, n)
end

function Raid.HideSample(b)
    ns.AuraGroups.HideSample(b.sampleSet)
    ns.Indicators.HideSample(b.sampleSet)
end

function Raid.Create()
    local holder = Raid.group:Create()
    Raid.holder, Raid.header = holder, Raid.group.header
    return holder
end

function Raid.CreatePreview()
    Raid.group:CreatePreview()
    Raid.preview = Raid.group.preview
end

-- "Use raid frames in a party": the raid tiles show in a party too and the
-- party frames step aside (Party's visibility checks this).
function Raid.InParty(cfg)
    return type(cfg) == "table" and cfg.enabled ~= false and cfg.showInParty == true
end

-- Protected (header attributes, sizes), so only call through DUI.AfterCombat.
function Raid.Layout(cfg, text, range)
    local inParty = Raid.InParty(base())
    Raid.group.header:SetAttribute("showParty", inParty)
    for _, gh in ipairs(Raid.group.headers) do gh:SetAttribute("showParty", inParty) end
    Raid.group:Layout(cfg, text, range)
end

-- Lays the raid out for the size shown now. Protected, use DUI.AfterCombat.
function Raid.LayoutNow(d)
    local cfg, text, key = Raid.Config(d)
    Raid.laidKey = key
    Raid.Layout(cfg, text, d.range)
    Raid.PlaceHolder(Raid.ShownSize())
end

-- An optional spot per raid size (raid20.ownSpot / raid40.ownSpot, off by
-- default), because a growing raid could run over other panels. Each size's
-- spot is a plain frame with its own mover ("unitframes.raid20"...), whose
-- handle only shows while the switch is on. The holder (Raid 10's mover) sits
-- on the spot of the size in use, with its own mover suspended meanwhile.
-- Following 10's settings doesn't affect this, so a size can keep Raid 10's
-- look and still sit elsewhere.

Raid.spots = {}
function Raid.SpotKey(size) return "unitframes.raid" .. tostring(size) end

function Raid.OwnSpot(size)
    if size == 10 then return false end
    local d = db()
    local t = d and d["raid" .. tostring(size)]
    return type(t) == "table" and t.ownSpot == true
end

function Raid.CreateSpots()
    for _, n in ipairs(ns.RAID_SIZES) do
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(200, 100)
        Raid.spots[n] = f
    end
    return Raid.spots
end

-- A spot's size: the holder's as last laid out for it, in UIParent units since
-- a spot has no scale of its own. Its handle then shows where the raid goes.
function Raid.FitSpot(size)
    local spot, holder = Raid.spots[size], Raid.holder
    if not (spot and holder) then return end
    local w, h = holder:GetWidth(), holder:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
    local k = holder:GetEffectiveScale() / spot:GetEffectiveScale()
    spot:SetSize(w * k, h * k)
end

-- Moves the holder onto the spot of size, or back to Raid 10's own. Protected,
-- called through DUI.AfterCombat (from LayoutNow).
function Raid.PlaceHolder(size)
    local holder, Movers = Raid.holder, DUI.Movers
    if not holder or not Movers.Get("unitframes.raid") then return end
    local spot = Raid.OwnSpot(size) and Raid.spots[size]
    if spot then
        Raid.FitSpot(size)
        Movers.Suspend("unitframes.raid", true)
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", spot, "CENTER", 0, 0)
        Raid.placedAt = size
    elseif Raid.placedAt then
        Raid.placedAt = nil
        Movers.Suspend("unitframes.raid", false)
    end
    for _, n in ipairs(ns.RAID_SIZES) do
        if Movers.Get(Raid.SpotKey(n)) then Movers.Recheck(Raid.SpotKey(n)) end
    end
end

-- A spot that was never moved starts where Raid 10's frames are now.
function Raid.SpotDefault()
    local x, y = DUI.Movers.Position("unitframes.raid")
    if type(x) ~= "number" or type(y) ~= "number" then return { "TOPLEFT", nil, "TOPLEFT", 20, -220 } end
    return { "CENTER", nil, "CENTER", x, y }
end
function Raid.ShowPreview(on) Raid.group:ShowPreview(on) end

local function preview(on)
    local d = db()
    if d then DUI.AfterCombat(function() Raid.LayoutNow(d) end, "raid:preview") end
    Raid.ShowPreview(on and d ~= nil and d.raid.enabled)
end
DUI.On("TestModeChanged", preview)

-- The raid grew or shrank past 10 or 20. Switch to its size's setup after combat.
DUI.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local d = db()
    if not (d and Raid.group.header) then return end
    local _, _, key = Raid.Config(d)
    if key == Raid.laidKey then return end
    DUI.AfterCombat(function()
        local now = db()
        if now then Raid.LayoutNow(now) end
    end, "raid:size")
end)

DUI.RegisterTestPart("raid", "Raid", 70, function()
    local d = db()
    return d ~= nil and d.raid.enabled == true
end)
DUI.On("TestPartChanged", function(key) if key == "raid" then preview(DUI.testMode) end end)
