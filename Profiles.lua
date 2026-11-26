-- Profiles. Every setting lives in a profile (stored by DB.lua). Each
-- character uses one, or one per talent set with dual spec, and changes on
-- every page go into the active profile. This file handles creating,
-- renaming and deleting profiles, choosing this character's, switching when
-- talents change, and sharing a profile as text.
--
-- A profile holds the general settings, every module's settings, frame
-- positions from unlock mode, and has its own Edit Mode layout (EditMode.lua).
-- When shared it leaves out what's learned as you play (the buff bar's history
-- and spell names) and window positions tied to one screen (spellbook, inspect
-- window, world map). The bag, bank and alts windows' spots travel with the
-- frame positions (WINDOW_SPOTS).
--
-- As text it's "!DUI1_" followed by the profile packed by the game itself
-- (CBOR, compressed, then Base64 via C_EncodingUtil), so reading one back never
-- runs any code. Switching profiles takes a reload, which applies everything.

local _, DUI = ...
local Style, EditMode = DUI.Style, DUI.EditMode
local SIZE = DUI.Style.SIZE -- the text size scale
local L = DUI.L

local Profiles = {}
DUI.Profiles = Profiles

Profiles.PREFIX = "!DUI1_"
Profiles.VERSION = 1
Profiles.MAX_NAME = 32
Profiles.SWITCH_DELAY = 1 -- seconds between writing the layout and the reload, so the game can save it
-- Per module: what a shared profile leaves out (learned as you play, or tied to one screen).
Profiles.SKIP = {
    Buffs = { history = true, spells = true, learned = true },
    Bags = { position = true, ["bank.position"] = true, ["viewer.position"] = true },
    Character = { folded = true }, -- old profiles' stat folds, per character, until each logs in (Stats.Folds)
    Book = { spot = true },
    Inspect = { spot = true },
    Skins = { mapSpot = true, windowSpots = true },
}
-- Window spots a module keeps as its own settings ({ x, y, at }: point `at`
-- of the window, from the screen's bottom left) that a shared profile carries
-- with the frame positions instead, under the window's unlock mode key. There
-- they follow the "Frame positions" switch and get fitted to another screen;
-- an import puts them back into the module's settings.
Profiles.WINDOW_SPOTS = {
    Bags = { position = "bags.bag", ["bank.position"] = "bags.bank", ["viewer.position"] = "bags.viewer" },
}

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- A module's window spot as a frame position: its center and the point it
-- hangs from, both from the screen's middle.
local function spotToShared(key, v)
    if type(v) ~= "table" or not (finite(v[1]) and finite(v[2])) then return nil end
    local M = DUI.Movers
    local at = M.ANCHOR_SIGN[v.at] and v.at or "TOPLEFT"
    local ax, ay = v[1] - UIParent:GetWidth() / 2, v[2] - UIParent:GetHeight() / 2
    local w, h = M.SizeOf(key)
    local sg = M.ANCHOR_SIGN[at]
    return { ax - sg[1] * (w or 0) / 2, ay - sg[2] * (h or 0) / 2, at = at, ax = ax, ay = ay }
end

-- The other way, for the module's settings.
local function spotFromShared(v)
    if type(v) ~= "table" then return nil end
    local at = DUI.Movers.ANCHOR_SIGN[v.at] and v.at or "TOPLEFT"
    local ax, ay = v.ax, v.ay
    if not (finite(ax) and finite(ay)) then ax, ay = v[1], v[2] end
    if not (finite(ax) and finite(ay)) then return nil end
    return { ax + UIParent:GetWidth() / 2, ay + UIParent:GetHeight() / 2, at = at }
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do
        if type(x) ~= "function" then out[k] = copy(x) end
    end
    return out
end

local function refresh()
    if DUI.OptionsPanel and DUI.OptionsPanel.Refresh then DUI.OptionsPanel.Refresh() end
end

local function data() return DUI.DB.Root().profileData end

-- A profile to share: its settings, only what differs from the defaults

function Profiles.Snapshot(name)
    local DB = DUI.DB
    name = name or DB.ActiveName()
    local src = DB.Fill(data()[name])
    local p = { v = Profiles.VERSION, general = copy(src.general), modules = {}, positions = copy(src.positions) }
    DB.StripDefaults(p.general, DB.GENERAL_DEFAULTS)
    for mod, t in pairs(src.modules) do
        if type(t) == "table" then
            local c = copy(t)
            for k in pairs(Profiles.SKIP[mod] or {}) do DB.SetPath(c, k, nil) end
            local m = DUI:GetModule(mod)
            if m and m.defaults then DB.StripDefaults(c, m.defaults) end
            p.modules[mod] = c
        end
    end
    for mod, paths in pairs(Profiles.WINDOW_SPOTS) do
        local t = src.modules[mod]
        for path, key in pairs(paths) do
            local v = type(t) == "table" and spotToShared(key, DB.GetPath(t, path))
            if v then p.positions[key] = v end
        end
    end
    p.layout = EditMode.Export(name) or src.pendingLayout
    -- The screen's shape it was made on, so an import on a wider or narrower
    -- screen can bring the frames to the same places.
    p.screen = { UIParent:GetWidth(), UIParent:GetHeight() }
    return p
end

-- As text

local function codec()
    local E = C_EncodingUtil
    if type(E) == "table" and E.SerializeCBOR and E.DeserializeCBOR and E.CompressString
        and E.DecompressString and E.EncodeBase64 and E.DecodeBase64 then
        return E
    end
end

-- Packs any table into text starting with prefix (a profile, a bag's groups):
-- CBOR, compressed, Base64. Returns the text, or nil and a reason.
function Profiles.Pack(t, prefix)
    local E = codec()
    if not E then return nil, L["this game client can't pack profiles"] end
    local ok, s = pcall(E.SerializeCBOR, t)
    if ok then ok, s = pcall(E.CompressString, s) end
    if ok then ok, s = pcall(E.EncodeBase64, s) end
    if not ok or type(s) ~= "string" then return nil, L["the profile couldn't be packed"] end
    return prefix .. s
end

-- Pack's table back from text (spaces and line breaks ignored), or nil and a
-- reason: "empty", "prefix" (wrong prefix), "client" or "damaged".
function Profiles.Unpack(text, prefix)
    if type(text) ~= "string" then return nil, "empty" end
    text = string.gsub(text, "%s", "")
    if text == "" then return nil, "empty" end
    if string.sub(text, 1, #prefix) ~= prefix then return nil, "prefix" end
    local E = codec()
    if not E then return nil, "client" end
    local ok, v = pcall(E.DecodeBase64, string.sub(text, #prefix + 1))
    if ok then ok, v = pcall(E.DecompressString, v) end
    if ok then ok, v = pcall(E.DeserializeCBOR, v) end
    if not ok or type(v) ~= "table" then return nil, "damaged" end
    return v
end

function Profiles.Encode(p)
    return Profiles.Pack(p, Profiles.PREFIX)
end

-- A profile from text, or nil and a reason.
function Profiles.Decode(text)
    local v, why = Profiles.Unpack(text, Profiles.PREFIX)
    if not v then
        local said = { empty = L["nothing pasted"], prefix = L["that isn't a DaylightUI profile"],
                       client = L["this game client can't read profiles"],
                       damaged = L["the profile is damaged (was all of it copied?)"] }
        return nil, said[why]
    end
    return Profiles.Check(v)
end

-- Validates a shared profile table the way Decode does (a pack may hand one
-- over directly). Returns the profile, or nil and a reason.
function Profiles.Check(v)
    if type(v) ~= "table" then return nil, L["the profile is damaged"] end
    if type(v.v) ~= "number" or v.v > Profiles.VERSION then
        return nil, L["it's from a newer DaylightUI; update to import it"]
    end
    for _, key in ipairs({ "general", "modules", "positions" }) do
        if v[key] ~= nil and type(v[key]) ~= "table" then return nil, L["the profile is damaged"] end
    end
    local s = v.screen
    if not (type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" and s[1] > 0 and s[2] > 0
            and s[1] < math.huge and s[2] < math.huge) then
        v.screen = nil
    end
    -- A damaged position would leave its frame unplaced at every login, so drop it.
    for key, pos in pairs(v.positions or {}) do
        if not DUI.Movers.Valid(pos) then v.positions[key] = nil end
    end
    return v
end

-- A one-line summary of what a profile holds.
function Profiles.Summary(p)
    local names = {}
    for name in pairs(p.modules or {}) do
        local mod = DUI:GetModule(name)
        names[#names + 1] = L[mod and (mod.label or mod.name) or name]
    end
    table.sort(names)
    local parts = {}
    if p.general and next(p.general) then parts[#parts + 1] = L["appearance"] end
    if #names > 0 then parts[#parts + 1] = table.concat(names, ", ") end
    if p.positions and next(p.positions) then parts[#parts + 1] = L["frame positions"] end
    if type(p.layout) == "string" then parts[#parts + 1] = L["the Edit Mode layout"] end
    if #parts == 0 then return L["Nothing but the defaults."] end
    return string.format(L["Settings for %s."], table.concat(parts, "; "))
end

-- The parts of a shared profile that can be taken on their own, in the order
-- the import box lists them: appearance, each module A to Z, frame positions,
-- the Edit Mode layout. Each is { key, label }; a module's key is its name.
-- Only parts that hold something are listed, and only modules this player
-- has: the maker's other add-ons can keep their settings in the profile too.
Profiles.GENERAL, Profiles.POSITIONS, Profiles.LAYOUT = "general", "positions", "layout"

local function holds(t) return type(t) == "table" and next(t) ~= nil end

function Profiles.Parts(p)
    local out = {}
    if holds(p.general) then out[#out + 1] = { key = Profiles.GENERAL, label = L["Appearance"] } end
    local mods = {}
    for name, t in pairs(p.modules or {}) do
        local mod = DUI:GetModule(name)
        if mod and holds(t) then
            mods[#mods + 1] = { key = name, label = L[mod.label or mod.name or name] }
        end
    end
    table.sort(mods, function(a, b) return a.label < b.label end)
    for _, m in ipairs(mods) do out[#out + 1] = m end
    if holds(p.positions) then out[#out + 1] = { key = Profiles.POSITIONS, label = L["Frame positions"] } end
    if type(p.layout) == "string" then out[#out + 1] = { key = Profiles.LAYOUT, label = L["Edit Mode layout"] } end
    return out
end

-- A shared profile with only the parts in take (a set of Parts keys) kept;
-- every other listed part is swapped for the active profile's own, so turning
-- a part off on import means keeping yours. Parts the list never offered come
-- as shared, the same as a whole import, and a part the string doesn't carry
-- at all (left out on export) is yours too.
function Profiles.Take(shared, take)
    local mine = Profiles.Snapshot()
    local offered = {}
    for _, part in ipairs(Profiles.Parts(shared)) do offered[part.key] = true end
    local function theirs(key) return take[key] or not offered[key] end
    local p = { v = shared.v, screen = shared.screen, modules = {} }
    p.general = copy(theirs(Profiles.GENERAL) and shared.general or mine.general)
    p.positions = copy(theirs(Profiles.POSITIONS) and shared.positions or mine.positions)
    p.layout = theirs(Profiles.LAYOUT) and shared.layout or mine.layout
    local mods = shared.modules or {}
    for name, t in pairs(mods) do
        p.modules[name] = copy(theirs(name) and t or mine.modules[name])
    end
    for name, t in pairs(mine.modules) do
        if mods[name] == nil then p.modules[name] = copy(t) end
    end
    return p
end

-- A profile to share with only the parts in take (a set of Parts keys); the
-- rest are left out, so whoever imports it keeps their own for those.
function Profiles.Only(p, take)
    local out = { v = p.v, screen = p.screen, modules = {} }
    if take[Profiles.GENERAL] then out.general = copy(p.general) end
    if take[Profiles.POSITIONS] then out.positions = copy(p.positions) end
    if take[Profiles.LAYOUT] then out.layout = p.layout end
    for name, t in pairs(p.modules or {}) do
        if take[name] then out.modules[name] = copy(t) end
    end
    return out
end

-- Fitting a shared profile's frames to another screen

-- Shapes named in the import message, and how close a screen must be to one
-- to be called it (3440x1440 is 2.39, sold as 21:9).
Profiles.SHAPES = { { 4 / 3, "4:3" }, { 5 / 4, "5:4" }, { 16 / 10, "16:10" }, { 16 / 9, "16:9" },
                    { 21 / 9, "21:9" }, { 32 / 9, "32:9" } }
Profiles.SHAPE_NEAR = 0.04

-- A width over a height as players know it ("21:9"), else "2.10:1".
function Profiles.ShapeName(aspect)
    local best, gap
    for _, s in ipairs(Profiles.SHAPES) do
        local g = math.abs(aspect - s[1]) / s[1]
        if not gap or g < gap then best, gap = s[2], g end
    end
    if gap <= Profiles.SHAPE_NEAR then return best end
    return string.format("%.2f:1", aspect)
end

-- A profile made on another screen (p.screen, UIParent's size there) is
-- fitted to this one so it looks as it did there: the same arrangement, each
-- piece the same size for the screen. Sizes follow the height (k, this
-- screen's height over that one's), so a UI made at another UI scale keeps
-- its share of the screen, and at the same UI scale nothing changes size.
-- Up and down, a piece stays the same share of the height from the middle.
-- Across, on a wider screen a piece in the middle half of the old one stays
-- that far from the middle (times k), and one further out keeps its distance
-- from its own side's edge, so the room the wider screen adds goes between
-- the middle and the sides. On a narrower screen the middle (FIT_MIDDLE of
-- the new screen's half width) keeps its distances from the middle and the
-- edges (FIT_EDGE of it) their gaps, and what's between them is squeezed
-- evenly into the room left, so nothing jumps and the order across stays.
-- Only spots and sizes change.
Profiles.FIT_NEAR = 0.01 -- screens this close in height and shape count as the same one
Profiles.FIT_SHRINK = 0.5 -- the smallest a side shrinks to make room on a narrower screen
Profiles.FIT_STEPS = 12 -- halvings in the search for how far it shrinks
Profiles.FIT_MIDDLE = 0.5 -- on a narrower screen, the share of its half width kept as it was in the middle
Profiles.FIT_EDGE = 0.25 -- and at each edge

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Both screens and k, or nil when they're the same one (or either isn't known).
-- On a narrower screen also, in the old screen's units: half its width (half),
-- the new one's (room), and how far out the middle reaches (mid) and how far
-- in the edges do (edge).
local function screens(s)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not (type(s) == "table" and w and h and w > 0 and h > 0) then return nil end
    local k, near = h / s[2], Profiles.FIT_NEAR
    if math.abs(k - 1) <= near and math.abs(w / h - s[1] / s[2]) <= near * w / h then return nil end
    local fs = { sw = s[1], sh = s[2], w = w, h = h, k = k }
    local half, room = s[1] / 2, w / 2 / k
    if room < half * (1 - near) then
        fs.narrow, fs.half, fs.room = true, half, room
        fs.mid, fs.edge = room * Profiles.FIT_MIDDLE, room * Profiles.FIT_EDGE
    end
    return fs
end

-- The part of the old screen that x (from the middle) is in: -1 the left
-- side, 0 the middle, 1 the right side.
local function sideOf(fs, x)
    if math.abs(x) <= (fs.narrow and fs.mid or fs.sw / 4) then return 0 end
    return x < 0 and -1 or 1
end

-- x on this screen, for a spot on `side`. shrink (1 when not given) brings a
-- side's spot toward its edge, or the middle's toward the middle.
local function fitX(fs, side, x, shrink)
    local s = shrink or 1
    if side == 0 then return x * fs.k * s end
    local nx
    if fs.narrow then
        local u, away = math.abs(x), 0
        if fs.half - u <= fs.edge then
            away = fs.room - (fs.half - u)
        else
            away = fs.mid + (u - fs.mid) * (fs.room - fs.edge - fs.mid) / (fs.half - fs.edge - fs.mid)
        end
        nx = side * away * fs.k
    else
        nx = side * fs.w / 2 + (x - side * fs.sw / 2) * fs.k
    end
    return side * fs.w / 2 + (nx - side * fs.w / 2) * s
end

local function box(x, y, w, h) return { l = x - w / 2, r = x + w / 2, b = y - h / 2, t = y + h / 2 } end
local function overlap(a, b) return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t end

-- Fits the spots in `at` (changed in place). size(key): how much bigger the
-- profile draws a piece than it's drawn here now. grow: how much every piece
-- grows on this screen (k, or less where the Scale reached its end, or 1
-- when the profile's Scale isn't taken). general: the profile's General
-- settings when taken, where a piece shrunk to make room is made smaller.
--
-- When sizes change, the pieces never moved get a spot too, worked out on
-- the screen the profile was made on, since a start spot doesn't grow with
-- them. Otherwise they stay at their start spots and are only in the way.
-- On a narrower screen a piece at a side that now runs into another (where
-- it didn't before) shrinks toward its edge, its gap and itself together, as
-- little as clears it. Pieces nearest their edge go first. A piece it would
-- still run into at FIT_SHRINK is in the way at any size and isn't counted:
-- small and still covered helps no one. The middle shrinks if it's wider
-- than the screen. Last, each piece is
-- kept on the screen, as far off it as it was on the old one. Sizes are the
-- frames' here, so a piece whose own settings the import changes is measured
-- as it is now.
local function fitPositions(fs, at, size, grow, general)
    local M = DUI.Movers
    local resize = math.abs(fs.k - 1) > Profiles.FIT_NEAR
    -- A piece only shrinks when its smaller size is saved too. Otherwise it would
    -- be placed for a size it never gets and stick out past its neighbors.
    local function canShrink(it) return general ~= nil and M.Scalable(it.key) end
    local list = {}
    local function add(key, x, y, point, ax, ay)
        local w, h = M.SizeOf(key)
        local s = size(key)
        local it = { key = key, at = point, ax = ax, ay = ay, w = (w or 0) * s, h = (h or 0) * s }
        local sg = point and M.ANCHOR_SIGN[point]
        if not x then x, y = ax - sg[1] * it.w / 2, ay - sg[2] * it.h / 2 end
        it.x, it.y, it.side, it.from = x, y, sideOf(fs, x), box(x, y, it.w, it.h)
        list[#list + 1] = it
        return it, sg
    end
    for key, v in pairs(at) do add(key, v[1], v[2], v.at, v.ax, v.ay).saved = v end
    for _, key in ipairs(M.Keys()) do
        if not at[key] then
            local point, ax, ay = M.DefaultSpot(key, fs.sw, fs.sh)
            if point then
                local it, sg = add(key, nil, nil, point, ax, ay)
                if not resize then
                    local _, bx, by = M.DefaultSpot(key)
                    local w, h = it.w * grow, it.h * grow
                    it.fixed = box(bx - sg[1] * w / 2, by - sg[2] * h / 2, w, h)
                end
            end
        end
    end
    local function place(it)
        if it.fixed then return it.fixed end
        local s = it.shrink or 1
        local x, y, g = fitX(fs, it.side, it.x, s), it.y * fs.k, grow * s
        return box(x, y, it.w * g, it.h * g), x, y, g
    end
    -- Whether a, where it would go now, runs into a piece it was clear of
    -- before, other than those in skip.
    local function clash(a, skip)
        local ra = place(a)
        for _, b in ipairs(list) do
            if b ~= a and b.w > 0 and not (skip and skip[b]) and overlap(ra, place(b))
                    and not overlap(a.from, b.from) then
                return true
            end
        end
        return false
    end
    local l, r
    for _, it in ipairs(list) do
        if it.side == 0 and not it.fixed and it.w > 0 then
            local b = place(it)
            l, r = math.min(l or b.l, b.l), math.max(r or b.r, b.r)
        end
    end
    if l and r - l > fs.w then
        local s = math.max(Profiles.FIT_SHRINK, fs.w / (r - l))
        for _, it in ipairs(list) do
            if it.side == 0 and not it.fixed and canShrink(it) then it.shrink = s end
        end
    end
    -- Each side piece's gap from its own edge on the old screen.
    local outer = {}
    for _, it in ipairs(list) do
        if it.side ~= 0 and not it.fixed and it.w > 0 then
            it.gap = fs.sw / 2 - it.side * it.x - it.w / 2
            outer[#outer + 1] = it
        end
    end
    table.sort(outer, function(a, b)
        if a.gap ~= b.gap then return a.gap < b.gap end
        return a.key < b.key
    end)
    for _, it in ipairs(outer) do
        if canShrink(it) and clash(it) then
            -- What it still runs into at its smallest is in the way at any
            -- size: shrinking for that only makes it small and still covered.
            it.shrink = Profiles.FIT_SHRINK
            local stuck, ra = {}, place(it)
            for _, b in ipairs(list) do
                if b ~= it and b.w > 0 and overlap(ra, place(b)) then stuck[b] = true end
            end
            it.shrink = nil
            if clash(it, stuck) then
                local lo, hi = Profiles.FIT_SHRINK, 1
                for _ = 1, Profiles.FIT_STEPS do
                    it.shrink = (lo + hi) / 2
                    if clash(it, stuck) then hi = it.shrink else lo = it.shrink end
                end
                it.shrink = lo
            end
        end
    end
    for _, it in ipairs(list) do
        if not it.fixed and (it.saved or resize) then
            local b, x, y, g = place(it)
            -- On the screen, or as far off it as it was on the old one.
            local f = it.from
            local offL, offR = math.max(0, -fs.sw / 2 - f.l) * g, math.max(0, f.r - fs.sw / 2) * g
            local offB, offT = math.max(0, -fs.sh / 2 - f.b) * g, math.max(0, f.t - fs.sh / 2) * g
            x = x + math.max(0, -fs.w / 2 - offL - b.l) - math.max(0, b.r - fs.w / 2 - offR)
            y = y + math.max(0, -fs.h / 2 - offB - b.b) - math.max(0, b.t - fs.h / 2 - offT)
            local v = copy(it.saved) or {}
            v[1], v[2] = x, y
            if it.at and it.at ~= "CENTER" and type(it.ax) == "number" and type(it.ay) == "number" then
                v.at, v.ax, v.ay = it.at, x + (it.ax - it.x) * g, y + (it.ay - it.y) * g
            end
            at[it.key] = v
            local s = it.shrink or 1
            if s < 1 then
                if type(general.frameScales) ~= "table" then general.frameScales = {} end
                general.frameScales[it.key] = clamp((tonumber(general.frameScales[it.key]) or 1) * s, M.MIN, M.MAX)
            end
        end
    end
end

-- Edit Mode settings that size a piece, by system: the system's setting enum
-- and its size sliders (in percent). They're scaled through the game's own
-- slider ranges, so a size lands on the slider's nearest step, inside its range.
Profiles.LAYOUT_SIZES = {
    ActionBar = { "EditModeActionBarSetting", "IconSize" },
    ArchaeologyBar = { "EditModeArchaeologyBarSetting", "Size" },
    AuraFrame = { "EditModeAuraFrameSetting", "IconSize" },
    Bags = { "EditModeBagsSetting", "Size" },
    CastBar = { "EditModeCastBarSetting", "BarSize" },
    CooldownViewer = { "EditModeCooldownViewerSetting", "IconSize" },
    DurabilityFrame = { "EditModeDurabilityFrameSetting", "Size" },
    EncounterEvents = { "EditModeEncounterEventsSetting", "IconSize", "OverallSize" },
    GroupFinder = { "EditModeGroupFinderSetting", "Size" },
    LossOfControl = { "EditModeLossOfControlSetting", "Size" },
    MicroMenu = { "EditModeMicroMenuSetting", "Size" },
    Minimap = { "EditModeMinimapSetting", "Size", "IconScale" },
    PersonalResourceDisplay = { "EditModePersonalResourceDisplaySetting", "Size" },
    StatusTrackingBar = { "EditModeStatusTrackingBarSetting", "Size" },
    SwingTimer = { "EditModeSwingTimerSetting", "Scale" },
    TimerBars = { "EditModeTimerBarsSetting", "Size" },
    UnitFrame = { "EditModeUnitFrameSetting", "FrameSize", "BuffIconSize", "DebuffIconSize", "BigDefensiveIconSize" },
    VehicleSeatIndicator = { "EditModeVehicleSeatIndicatorSetting", "Size" },
}

-- LAYOUT_SIZES by the game's numbers: system -> { [setting] = true }.
local function layoutSizes()
    local out = {}
    for sys, t in pairs(Profiles.LAYOUT_SIZES) do
        local id, enum = Enum.EditModeSystem and Enum.EditModeSystem[sys], Enum[t[1]]
        if id ~= nil and type(enum) == "table" then
            out[id] = {}
            for i = 2, #t do
                if enum[t[i]] ~= nil then out[id][enum[t[i]]] = true end
            end
        end
    end
    return out
end

-- One size setting times k, stored the way the game's slider stores it.
local function fitSetting(system, row, k)
    local D = EditModeSettingDisplayInfoManager
    local map = D and D.GetSystemSettingDisplayInfoMap and D:GetSystemSettingDisplayInfoMap(system)
    local info = map and map[row.setting]
    local slider = Enum.EditModeSettingDisplayType and Enum.EditModeSettingDisplayType.Slider
    if not (info and info.type == slider and type(row.value) == "number" and type(info.minValue) == "number"
            and type(info.maxValue) == "number" and type(info.stepSize) == "number" and info.stepSize > 0) then
        return
    end
    local shown = info.ConvertValueForDisplay and info:ConvertValueForDisplay(row.value) or row.value
    local v = clamp(shown * k, info.minValue, info.maxValue)
    v = math.min(info.maxValue, info.minValue + math.floor((v - info.minValue) / info.stepSize + 0.5) * info.stepSize)
    row.value = info.ConvertValue and info:ConvertValue(v, false) or v
end

-- An Edit Mode anchor fitted like a piece's spot. One held by another frame
-- (snapped to it) only has its gap times k; it follows that frame.
local function fitAnchor(fs, a)
    if type(a) ~= "table" or type(a.offsetX) ~= "number" or type(a.offsetY) ~= "number" then return end
    if a.relativeTo ~= nil and a.relativeTo ~= "UIParent" then
        a.offsetX, a.offsetY = a.offsetX * fs.k, a.offsetY * fs.k
        return
    end
    local sg = DUI.Movers.ANCHOR_SIGN[a.relativePoint]
    if not sg then return end
    -- Edit Mode keeps each piece from the nearer half's edge, so the spot
    -- is taken from the middle first and given its side like ours.
    -- A point placed off the old screen on purpose (a bar tucked under the
    -- bottom edge) keeps its overhang, times k.
    local x, y = sg[1] * fs.sw / 2 + a.offsetX, sg[2] * fs.sh / 2 + a.offsetY
    local nx, ny = fitX(fs, sideOf(fs, x), x), y * fs.k
    if math.abs(x) <= fs.sw / 2 then nx = clamp(nx, -fs.w / 2, fs.w / 2) end
    if math.abs(y) <= fs.sh / 2 then ny = clamp(ny, -fs.h / 2, fs.h / 2) end
    x, y = nx, ny
    a.offsetX, a.offsetY = x - sg[1] * fs.w / 2, y - sg[2] * fs.h / 2
end

-- The Edit Mode layout text fitted to this screen: the spots of pieces moved
-- off their default (the game places the rest from the edges) and the size
-- sliders. Read and written back by the game itself; text it can't read
-- comes back as it is.
local function fitLayout(text, fs)
    local E = C_EditMode
    local layout = type(E and E.ConvertLayoutInfoToString) == "function" and EditMode.FromText(text)
    if not layout then return text end
    local sizes = layoutSizes()
    for _, entry in ipairs(layout.systems) do
        if type(entry) == "table" then
            if not entry.isInDefaultPosition then
                fitAnchor(fs, entry.anchorInfo)
                fitAnchor(fs, entry.anchorInfo2)
            end
            local own = sizes[entry.system]
            if own and type(entry.settings) == "table" then
                for _, row in ipairs(entry.settings) do
                    if type(row) == "table" and own[row.setting] then fitSetting(entry.system, row, fs.k) end
                end
            end
        end
    end
    local done, s = DUI.SafeReturn(E.ConvertLayoutInfoToString, layout)
    return done and type(s) == "string" and s or text
end

-- The shared profile p fitted to this screen, for the parts in take (a set
-- of Parts keys; every part when not given): its frame spots, its Scale
-- (with Appearance) and its Edit Mode layout. Returns a copy and the shapes
-- (from, to), or p itself when it was made on this screen or doesn't say
-- which (a string from before screens were saved).
function Profiles.Fit(p, take)
    local fs = screens(p.screen)
    if not fs then return p end
    local M = DUI.Movers
    local function taken(key) return not take or take[key] end
    local spots = holds(p.positions) and taken(Profiles.POSITIONS)
    local layout = type(p.layout) == "string" and taken(Profiles.LAYOUT)
    local out = copy(p)
    local general = holds(out.general) and taken(Profiles.GENERAL) and out.general or nil
    if not (general or spots or layout) then return p end
    local master, grow = 1, 1
    if general then
        -- The same range as the Scale slider.
        master = tonumber(general.scale) or 1
        if master <= 0 then master = 1 end
        local scale = clamp(master * fs.k, M.MIN, M.MAX)
        grow = scale / master
        general.scale = math.abs(scale - 1) >= 0.001 and scale or nil
    end
    if spots then
        local function size(key)
            if not (general and M.Scalable(key)) then return 1 end
            local own = type(general.frameScales) == "table" and tonumber(general.frameScales[key]) or 1
            return master * own / M.Scale(key)
        end
        fitPositions(fs, out.positions, size, grow, general)
    end
    if layout then out.layout = fitLayout(out.layout, fs) end
    return out, Profiles.ShapeName(fs.sw / fs.sh), Profiles.ShapeName(fs.w / fs.h)
end

-- The profiles

-- Every saved profile's name, the standard one (DPS/Tank) first if present,
-- then A to Z. Empty until the setup guide has created one.
function Profiles.Names()
    local out = {}
    for name, p in pairs(data()) do
        if name ~= DUI.DB.DEFAULT and type(p) == "table" and not p.unsaved then out[#out + 1] = name end
    end
    table.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)
    if DUI.DB.Saved(DUI.DB.DEFAULT) then table.insert(out, 1, DUI.DB.DEFAULT) end
    return out
end

function Profiles.Current() return DUI.DB.ActiveName() end

-- A valid name for a new (or renamed) profile: the name tidied, or nil and a
-- reason. `except` is the profile being renamed, whose own name (any case) is allowed.
function Profiles.CheckName(name, except)
    name = type(name) == "string" and strtrim(name) or ""
    if name == "" then return nil, L["give it a name"] end
    if #name > Profiles.MAX_NAME then return nil, L["that name is too long"] end
    for n, p in pairs(data()) do
        if n ~= except and string.lower(n) == string.lower(name) and not (type(p) == "table" and p.unsaved) then
            return nil, string.format(L["there's a profile called %s already"], n)
        end
    end
    return name
end

-- A new profile: a copy of the active one (including its layout) or of
-- another (from), or built from a shared one (with what sharing leaves out
-- taken from the active one). Returns its name, or nil and a reason.
function Profiles.Create(name, shared, from)
    local why
    name, why = Profiles.CheckName(name)
    if not name then return nil, why end
    data()[name] = Profiles.Build(shared, from)
    return name
end

-- A shared setting of the wrong kind for its default (a word where a number
-- goes, from a hand-edited or damaged string) would error in every module
-- that reads it, so it's dropped and the default fills in. Keys with no
-- default (lists, positions, learned data) are kept. Runs after the
-- upgrades, which may still convert an old kind to the current one.
local function dropWrongKinds(t, defaults)
    for k, v in pairs(t) do
        local d = defaults[k]
        if d ~= nil then
            if type(v) ~= type(d) then
                t[k] = nil
            elseif type(d) == "table" then
                dropWrongKinds(v, d)
            end
        end
    end
end

-- A profile table built the way Create builds one, not saved anywhere yet.
-- keep is the profile that what sharing leaves out comes from (the active one
-- when not given).
function Profiles.Build(shared, from, keep)
    local DB = DUI.DB
    local current = DB.Active()
    local p
    if shared then
        p = { general = copy(shared.general) or {}, modules = copy(shared.modules) or {},
              positions = copy(shared.positions) or {}, pendingLayout = shared.layout }
        local mine = keep or current
        for mod, paths in pairs(Profiles.SKIP) do
            local from = mine.modules[mod]
            if type(from) == "table" then
                if type(p.modules[mod]) ~= "table" then p.modules[mod] = {} end
                for path in pairs(paths) do DB.SetPath(p.modules[mod], path, copy(DB.GetPath(from, path))) end
            end
        end
        -- Window spots that came with the frame positions go back where the module reads them.
        for mod, paths in pairs(Profiles.WINDOW_SPOTS) do
            for path, key in pairs(paths) do
                local v = spotFromShared(p.positions[key])
                p.positions[key] = nil
                if v then
                    if type(p.modules[mod]) ~= "table" then p.modules[mod] = {} end
                    DB.SetPath(p.modules[mod], path, v)
                end
            end
        end
    else
        local src = from and DB.Fill(data()[from]) or current
        p = { general = copy(src.general), modules = copy(src.modules), positions = copy(src.positions),
              pendingLayout = EditMode.Export(from) or src.pendingLayout }
    end
    -- Created now, so it's already past the one-time gradient swap (DB.lua).
    -- Without this the next load would turn its plain "class" picks into
    -- gradients. Same for bars 5-8 (its hidden ones would show again) and the
    -- local font (a Korean or Chinese client's "off" would turn back on).
    p.gradients1 = true
    p.hiddenBars1 = true
    p.localFont1 = true
    p.backs1 = true
    p.tagLetters1 = true   -- a new profile starts on the player's own letters (a copy keeps the pick it copied)
    p.tipStyle1 = true     -- and in Rich tooltips, the default
    p.procsOff1 = true     -- and with Proc Alerts on, the default
    p.plateLow1 = true     -- and with nameplates at today's height
    -- A shared or blank profile picks up this client's font now, like a brand
    -- new profile does (DB.lua). A copy keeps the pick of the one it copies.
    if shared and DB.NonLatinClient() and p.general.localFont == nil then p.general.localFont = true end
    -- Copied from a profile that may be older than a module's upgrades, so upgrade it now.
    DB.RunUpgrades(p)
    if shared then
        dropWrongKinds(p.general, DB.GENERAL_DEFAULTS)
        for mod, t in pairs(p.modules) do
            local m = DUI:GetModule(mod)
            if type(t) == "table" and m and type(m.defaults) == "table" then dropWrongKinds(t, m.defaults) end
        end
    end
    return DB.Fill(p)
end

-- The characters ("Name-Realm") whose choices name a profile. One the player
-- removed (DUI.Alts) is left out until it logs in again.
function Profiles.UsersOf(name)
    local out = {}
    for key, c in pairs(DUI.DB.Root().characters) do
        if type(c) == "table" and not DUI.Alts.Forgotten(c) and (c.profile == name or c.padProfile == name or (type(c.specProfiles) == "table"
                and (c.specProfiles[1] == name or c.specProfiles[2] == name))) then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end

-- Changes every character's choice of one profile to another (nil = unset).
local function reassign(from, to)
    for _, c in pairs(DUI.DB.Root().characters) do
        if type(c) == "table" then
            if c.profile == from then c.profile = to end
            if c.padProfile == from then c.padProfile = to end
            if type(c.specProfiles) == "table" then
                for i = 1, 2 do
                    if c.specProfiles[i] == from then c.specProfiles[i] = to end
                end
            end
        end
    end
end

-- Returns true, or false and a reason. The standard profile keeps its name.
function Profiles.Rename(old, new)
    local DB = DUI.DB
    if old == DB.DEFAULT then return false, string.format(L["%s keeps its name"], DB.DEFAULT) end
    if type(data()[old]) ~= "table" then return false, string.format(L["there's no profile called %s"], tostring(old)) end
    local why
    new, why = Profiles.CheckName(new, old)
    if not new then return false, why end
    if new == old then return true end
    local p = data()[old]
    -- Its layout is renamed too. If the game won't rename it now, the old name
    -- is kept so the layout is taken over the next time it's put in place
    -- (EditMode.Install), plus a copy in case it's gone by then.
    local ok = EditMode.RenameLayout(old, new)
    if not ok then
        if not p.pendingLayout then p.pendingLayout = EditMode.Export(old) end
        if EditMode.Exists(old) and not p.layoutFrom then p.layoutFrom = old end
    end
    data()[new], data()[old] = p, nil
    reassign(old, new)
    if DB.activeName == old then DB.activeName = new end
    return true
end

-- Returns true, or false and a reason. Not the active profile (switch first).
-- Characters that chose it fall back to their other choice, else the
-- standard one, else the first one left. Its Edit Mode layout stays (Edit
-- Mode can delete it).
function Profiles.Delete(name)
    local DB = DUI.DB
    if name == DB.ActiveName() then return false, L["it's the one in use; switch to another first"] end
    if type(data()[name]) ~= "table" then return false, string.format(L["there's no profile called %s"], tostring(name)) end
    data()[name] = nil
    reassign(name, nil)
    return true
end

-- This character's choice, and switching

-- The profile chosen for "character", talent set 1 or 2 (with dual spec, a
-- set with none chosen uses the character's), or "pad" (used while the
-- game's controller UI is on; Profiles.NONE when there's none).
Profiles.NONE = "none"
function Profiles.Chosen(slot)
    local c = DUI.DB.Character()
    local DB = DUI.DB
    if slot == "pad" then
        return type(c.padProfile) == "string" and data()[c.padProfile] and c.padProfile or Profiles.NONE
    end
    if slot == 1 or slot == 2 then
        local n = type(c.specProfiles) == "table" and c.specProfiles[slot]
        if type(n) == "string" and data()[n] then return n end
    end
    if type(c.profile) == "string" and data()[c.profile] then return c.profile end
    return DB.Fallback()
end

-- Quietly sets the profile for "character", talent set 1 or 2, or "pad"
-- (Profiles.NONE or nil means none).
function Profiles.Assign(slot, name)
    local c = DUI.DB.Character()
    if slot == "pad" then
        c.padProfile = name ~= Profiles.NONE and name or nil
    elseif slot == 1 or slot == 2 then
        if type(c.specProfiles) ~= "table" then c.specProfiles = {} end
        c.specProfiles[slot] = name
    else
        c.profile = name
    end
end

-- Chooses a profile for "character" or talent set 1 or 2, and asks to reload
-- if that changes which profile this character should be on now.
function Profiles.Choose(slot, name)
    Profiles.Assign(slot, name)
    refresh()
    Profiles.CheckSwitch()
end

-- The talent set a choice is made for: the active one with dual spec.
function Profiles.CurrentSlot()
    return DUI.DB.DualSpec() and DUI.DB.SpecGroup() or "character"
end

-- Ready-made profiles: the standard one with a few settings changed

Profiles.PRESETS = {
    -- The standard profile itself (DB.DEFAULT), always present, with the standard
    -- Edit Mode layout "DaylightUI - DPS/Tank". The micro menu in the corner
    -- comes from DB.StandardStart, like every new profile.
    ["DPS/Tank"] = {
        UnitFrames = {},
    },
    -- A starting point for healers, built only from ordinary Party and Raid
    -- settings (anything here can be set by hand on those pages): the group as
    -- square tiles in a row under you, you included, with missing health shown and
    -- dispels easy to see, and a raid as the same tiles in columns.
    Healer = {
        UnitFrames = {
            party = { width = 60, height = 56, spacing = 4, groupSpacing = 4, direction = "rows", perLine = 5,
                      hideSelf = false, portrait = "none", nameOnBar = true, slant = false,
                      showLevel = false, showPvP = false, bigNumber = false, showPercent = true,
                      healthText = "missing", powerHeight = 4, markerSize = 11, showDispel = true, dispelSize = 14,
                      auras = { debuffs = { show = false }, buffs = { spot = "bottomleft", grow = "right" } },
                      indicators = { show = true } },
            partyText = { name = 11, percent = 10, big = 12 },
            raid = { width = 60, height = 56, spacing = 4, groupSpacing = 4, direction = "columns", perLine = 5,
                     showPercent = true, healthText = "missing", powerHeight = 4, dispelSize = 14,
                     auras = { buffs = { show = true } }, indicators = { show = true } },
            raidText = { name = 11 },
        },
    },
    -- Calm for questing without hiding anything: the main bars dim a while after
    -- a fight, bars 3 and 4 wait for the mouse (not a target), the other side
    -- bars and your own frames float (hidden out of combat, back in combat or
    -- when something changes), and the info panel and quest tracker dim in
    -- combat. The meter only shows in a group, the minimap is slightly smaller,
    -- and NPC talk is immersive. The micro menu sits in the corner as in
    -- DPS/Tank but waits for the mouse, faint (0.2) so a new player finds it.
    -- Its General part (PRESET_GENERAL) shows everything inside dungeons,
    -- raids, battlegrounds and arenas.
    ["Immersive Preset"] = {
        ActionBars = {
            microMenuFade = { mode = "always", alpha = 0.2, delay = 2 },
            padBarsFade = { mode = "ooc", alpha = 0.2, delay = 2 },
            bars = {
                main = { fade = { mode = "ooc", alpha = 0.2, delay = 2 } },
                bar2 = { fade = { mode = "ooc", alpha = 0.2, delay = 2 } },
                stance = { fade = { mode = "ooc", alpha = 0.2, delay = 2 } },
                pet = { fade = { mode = "ooc", delay = 2 } },
                left = { fade = { mode = "always", target = false, delay = 2 } },
                right = { fade = { mode = "always", target = false, delay = 2 } },
                bar5 = { fade = { mode = "float", delay = 2 } },
                bar6 = { fade = { mode = "float", delay = 2 } },
                bar7 = { fade = { mode = "float", delay = 2 } },
                bar8 = { fade = { mode = "float", delay = 2 } },
                possess = { fade = { mode = "float", delay = 2 } },
                totem = { fade = { mode = "float", delay = 2 } },
            },
        },
        UnitFrames = {
            player = { fade = { mode = "float", delay = 2 } },
            pet = { fade = { mode = "float", delay = 2 } },
            party = { fade = { mode = "float", delay = 2 } },
            raid = { fade = { mode = "float", delay = 2 } },
            personal = { fade = { mode = "float", delay = 2 } },
            target = { fade = { delay = 2 } },
            targettarget = { fade = { delay = 2 } },
            focus = { fade = { delay = 2 } },
        },
        Buffs = {
            settings = { fade = { mode = "float", delay = 2 }, debuff = { fade = { mode = "float" } } },
        },
        InfoPanel = {
            fade = { mode = "combat", alpha = 0.5, delay = 1.5 },
            threat = { fade = { mode = "float" } },
            meter = { enabled = false }, -- folded; one click on the panel's tab brings it out
            map = { size = 204 },
            xp = { showPercent = true },
        },
        Quests = { fade = { mode = "combat", alpha = 0.5, delay = 1.5 } },
        NPC = { look = "immersive" }, -- talking to NPCs: the card beside them, camera over your shoulder
    },
}
-- A ready-made profile's General settings (PRESETS holds its modules').
Profiles.PRESET_GENERAL = {
    ["Immersive Preset"] = { fadeOpenWorldOnly = true },
}
-- Where its frames start (unlock mode's center offsets from the middle of the
-- screen); each can be moved freely after that. The healer layout as set up
-- in game: player and target on either side of a full raid, level with its
-- top rows, the pet past the player, target of target under the target, and
-- party and raid centered below (they never show at the same time).
Profiles.PRESET_POSITIONS = {
    Healer = {
        ["unitframes.player"] = { -351.8, -143.9 }, ["unitframes.target"] = { 351.8, -143.9 },
        ["unitframes.pet"] = { -576.3, -143.9 }, ["unitframes.targettarget"] = { 304.5, -208.5 },
        ["unitframes.party"] = { 0, -253 }, ["unitframes.raid"] = { 0, -253 },
    },
}
-- The UIParent size those were set up on (2560x1600 at a raised UI scale). On
-- a smaller screen the chat and tracker, pinned to the corners at their own
-- size, take up more of it, so the spots there are pulled in with the width
-- and keep their height above the bottom (over the chat and action bars).
Profiles.PRESET_SCREEN = { 1705.6, 1066 }
-- Once pulled in, the player row no longer fits beside a full raid (8
-- columns, 508 wide), so it goes above it, all lifted together: the first key
-- no lower than "rise" above the raid's center (a full raid's half height,
-- 148, plus how far the row reaches below that key, 76 down to the bottom of
-- the target of target, plus a gap).
Profiles.PRESET_OVER = {
    Healer = { under = "unitframes.raid", rise = 228,
               keys = { "unitframes.player", "unitframes.target", "unitframes.pet", "unitframes.targettarget" } },
}

local function fitToScreen(key, at)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local refW, refH = Profiles.PRESET_SCREEN[1], Profiles.PRESET_SCREEN[2]
    -- The game returns sizes slightly off; treat the screen it was made on as equal.
    local narrower = w < refW - 1
    local function fit(v)
        local x, y = v[1], v[2]
        if narrower then x = x * w / refW end
        if h < refH then y = y + (refH - h) / 2 end
        local out = copy(v)
        out[1], out[2] = x, y
        return out
    end
    local out = {}
    for k, v in pairs(at) do out[k] = fit(v) end
    local over = Profiles.PRESET_OVER[key]
    local first = over and out[over.keys[1]]
    if narrower and first and out[over.under] then
        local lift = out[over.under][2] + over.rise - first[2]
        if lift > 0 then
            for _, k in ipairs(over.keys) do
                if out[k] then out[k][2] = out[k][2] + lift end
            end
        end
    end
    return out
end

local function merge(into, from)
    for k, v in pairs(from) do
        if type(v) == "table" then
            if type(into[k]) ~= "table" then into[k] = {} end
            merge(into[k], v)
        else
            into[k] = v
        end
    end
end

-- Creates a ready-made profile, built clean (Profiles.ReadyData) and named
-- after it. If it already exists, that one is used as is (and the unsaved
-- stand-in is saved from now on). Returns its name, or nil and a reason. as
-- creates it under that name instead (the setup guide's own copy of one not
-- created yet, which leaves the ready-made one uncreated).
function Profiles.AddPreset(key, as)
    local entry = Profiles.PackOf(key)
    if entry then return Profiles.AddPackProfile(entry, as) end
    if not Profiles.PRESETS[key] then return nil, string.format(L["there's no ready-made profile called %s"], tostring(key)) end
    local have = data()[as or key]
    if type(have) == "table" then
        have.unsaved = nil
        return as or key
    end
    local name, why = Profiles.CheckName(as or key)
    if not name then return nil, why end
    data()[name] = Profiles.ReadyData(key)
    return name
end

-- Profile packs: ready-made profiles that another addon provides

-- Another addon (a pack, like ElvUI's UI packs) can provide profiles made with
-- DaylightUI, as share strings (/dui export) or tables, through
-- DaylightUI.RegisterPack. They're offered alongside ours in the setup guide
-- and on the Profiles page, created only when picked (Profiles.AddPreset) and
-- used as is after that, like Healer. Reading a pack runs no code. Its extras
-- (setting up other addons) are its own code, run on the setup guide's Finish
-- unless the player turns them off.
--
-- DaylightUI.RegisterPack("MyPack", {
--     label = "My UI", author = "Me", version = "1.2", website = "...",
--     desc = "One line on what it is.",
--     screen = { 1920, 1080 },     -- UIParent size it was made on, for strings that don't say (Profiles.Fit)
--     updates = "offer",           -- "never" (default): once created, a profile belongs to the player
--     profiles = { { name = "My UI Healer", text = "!DUI1_...", sub = "One line.", role = "Healer" } },
--     extras = { { addon = "Details", label = "Details!", apply = function() ... end } },
-- })

Profiles.PACKS, Profiles.PACK_ORDER = {}, {}
Profiles.PACK_ROLES = { ["DPS/Tank"] = true, Healer = true, ["Immersive Preset"] = true } -- the drawings a pack profile can use
local packOf = {} -- pack profile name, lowercased -> its entry

-- A mistake by a pack author: raise an error naming the call, pointing at their file.
local function packError(text) error("DaylightUI.RegisterPack: " .. text, 3) end

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

-- Called as DaylightUI.RegisterPack(id, spec) or
-- DaylightUI:RegisterPack(id, spec), like RegisterModule.
function Profiles.RegisterPack(id, spec, extra)
    if id == DUI then id, spec = spec, extra end
    if not str(id) then packError("the pack needs an id (a string)") end
    if Profiles.PACKS[id] then packError(string.format("there's a pack called %s already", id)) end
    if type(spec) ~= "table" or type(spec.profiles) ~= "table" or #spec.profiles == 0 then
        packError("the pack needs profiles = { { name = ..., text = ... } }")
    end
    local screen = spec.screen
    if not (type(screen) == "table" and type(screen[1]) == "number" and type(screen[2]) == "number"
            and screen[1] > 0 and screen[2] > 0) then
        screen = nil
    end
    local pack = { id = id, label = str(spec.label) or id, author = str(spec.author), website = str(spec.website),
                   desc = str(spec.desc), version = spec.version, screen = screen and { screen[1], screen[2] },
                   updates = spec.updates == "offer" and "offer" or "never", profiles = {}, extras = {} }
    if pack.version ~= nil and type(pack.version) ~= "string" and type(pack.version) ~= "number" then
        packError("version is a string or a number")
    end
    for _, e in ipairs(spec.profiles) do
        local name = type(e) == "table" and type(e.name) == "string" and strtrim(e.name) or ""
        if name == "" then packError("each profile needs a name") end
        if #name > Profiles.MAX_NAME then
            packError(string.format("%s is longer than %d letters", name, Profiles.MAX_NAME))
        end
        if not (str(e.text) or type(e.data) == "table") then
            packError(string.format("%s needs text (a share string from /dui export) or data", name))
        end
        local low = string.lower(name)
        for ours in pairs(Profiles.PRESETS) do
            if string.lower(ours) == low then packError(string.format("%s is one of DaylightUI's own", name)) end
        end
        if packOf[low] then
            -- Two packs that both include it: the player's setup, not a mistake.
            DUI.Print(string.format(L["%s: %s comes with %s already, so it's left out."], pack.label, name,
                packOf[low].pack.label))
        else
            local entry = { name = name, text = str(e.text), data = e.data, sub = str(e.sub), pack = pack,
                            role = Profiles.PACK_ROLES[e.role] and e.role or nil }
            pack.profiles[#pack.profiles + 1] = entry
            packOf[low] = entry
        end
    end
    for _, x in ipairs(type(spec.extras) == "table" and spec.extras or {}) do
        if type(x) ~= "table" or not str(x.addon) or type(x.apply) ~= "function" then
            packError("each extra needs addon (its folder name) and apply (a function)")
        end
        pack.extras[#pack.extras + 1] = { addon = x.addon, label = str(x.label) or x.addon, apply = x.apply, pack = pack }
    end
    Profiles.PACKS[id] = pack
    Profiles.PACK_ORDER[#Profiles.PACK_ORDER + 1] = id
    DUI.Fire("PacksChanged", id)
    return pack
end
DUI.RegisterPack = Profiles.RegisterPack

-- A pack profile's entry by name (any case), or nil.
function Profiles.PackOf(name)
    return type(name) == "string" and packOf[string.lower(name)] or nil
end

-- A pack profile's settings, read once. Returns the profile, or nil and a
-- reason. One that can't be read says so in chat once, naming the pack.
function Profiles.PackProfile(entry)
    if entry.decoded then return entry.decoded end
    if entry.bad then return nil, entry.bad end
    local p, why
    if entry.text then
        p, why = Profiles.Decode(entry.text)
    else
        local t = copy(entry.data)
        if t.v == nil then t.v = Profiles.VERSION end
        p, why = Profiles.Check(t)
    end
    if not p then
        entry.bad = why
        DUI.Print(string.format(L["%s: %s can't be read (%s), so it's left out."], entry.pack.label, entry.name, tostring(why)))
        return nil, why
    end
    entry.decoded = p
    return p
end

-- A pack's readable profiles, in its order.
function Profiles.PackProfiles(pack)
    local out = {}
    for _, e in ipairs(pack.profiles) do
        if Profiles.PackProfile(e) then out[#out + 1] = e end
    end
    return out
end

-- Every readable pack profile, pack by pack.
function Profiles.PackNames()
    local out = {}
    for _, id in ipairs(Profiles.PACK_ORDER) do
        for _, e in ipairs(Profiles.PackProfiles(Profiles.PACKS[id])) do out[#out + 1] = e.name end
    end
    return out
end

-- Whether name is a ready-made profile, ours or a pack's.
function Profiles.IsReady(name)
    return Profiles.PRESETS[name] ~= nil or Profiles.PackOf(name) ~= nil
end

-- Every ready-made profile's name: ours, then the packs'.
function Profiles.ReadyNames()
    local out = {}
    for name in pairs(Profiles.PRESETS) do out[#out + 1] = name end
    table.sort(out)
    for _, name in ipairs(Profiles.PackNames()) do out[#out + 1] = name end
    return out
end

-- A pack profile fitted to this screen (Profiles.Fit), by the screen its
-- string was made on, else the one the pack says.
local function packFitted(entry, p)
    if not p.screen and entry.pack.screen then
        p = copy(p)
        p.screen = { entry.pack.screen[1], entry.pack.screen[2] }
    end
    return (Profiles.Fit(p))
end

-- A ready-made profile's table (ours or a pack's), not saved anywhere yet.
-- Always built clean from the defaults plus its own settings and positions,
-- never copied from the saved DPS/Tank (a player may have changed that, and
-- every new character would get those changes under a card that shows the
-- standard layout). What sharing leaves out comes from `keep` (a profile
-- table), else the active profile. Returns nil and a reason on failure.
function Profiles.ReadyData(key, keep)
    local entry = Profiles.PackOf(key)
    if entry then
        local p, why = Profiles.PackProfile(entry)
        if not p then return nil, why end
        local t = Profiles.Build(packFitted(entry, p), nil, keep)
        t.fromPack = { id = entry.pack.id, name = entry.name, version = entry.pack.version }
        return t
    end
    local preset = Profiles.PRESETS[key]
    if not preset then return nil, string.format(L["there's no ready-made profile called %s"], tostring(key)) end
    local t = Profiles.Build({ general = {}, modules = DUI.DB.StandardStart(), positions = {},
                               layout = EditMode.Export(DUI.DB.DEFAULT) }, nil, keep)
    merge(t.modules, preset)
    if Profiles.PRESET_GENERAL[key] then merge(t.general, Profiles.PRESET_GENERAL[key]) end
    local at = Profiles.PRESET_POSITIONS[key]
    if at then
        for k, v in pairs(fitToScreen(key, at)) do t.positions[k] = v end
    end
    return t
end

-- Replaces a saved profile's contents in place (the active profile is this
-- very table, and the caller reloads into it). Its module tables are new, so
-- modules are pointed at them and a change made before that reload (prompt
-- answered with Later) isn't lost.
function Profiles.Replace(name, new)
    local t = data()[name]
    if type(t) ~= "table" then return end
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(new) do t[k] = v end
    if name == DUI.DB.ActiveName() then DUI.DB.Repoint() end
end

-- Brings the parts in take (a set of Parts keys) of a shared profile into the
-- profile in use, in place. Parts switched off stay as they are, and so does
-- what sharing leaves out. When the Edit Mode layout is taken it replaces the
-- profile's own (after the fight, in one). Asks to reload. Returns the
-- profile's name and, when its frames were fitted to this screen, the shapes
-- from and to.
function Profiles.ImportInto(shared, take)
    local name = Profiles.Current()
    local old = DUI.DB.Fill(data()[name])
    local from, to
    shared, from, to = Profiles.Fit(shared, take)
    local new = Profiles.Build(Profiles.Take(shared, take), nil, old)
    -- What the profile carries besides its settings stays: the pack it came
    -- from, the upgrades it already had.
    for k, v in pairs(old) do
        if new[k] == nil and k ~= "pendingLayout" then new[k] = v end
    end
    new.pendingLayout = old.pendingLayout
    Profiles.Replace(name, new)
    local layout = take[Profiles.LAYOUT] and shared.layout
    if type(layout) == "string" then
        DUI.AfterCombat(function()
            local ok, why = EditMode.Replace(layout, name)
            if not ok then
                DUI.Print(string.format(L["Couldn't bring in its Edit Mode layout: %s."], tostring(why)))
            end
        end, "profile import layout")
    end
    Profiles.AskReload()
    return name, from, to
end

-- Creates a pack's profile, like AddPreset does for ours (under its name, or
-- `as`; an existing one is used as is). Returns its name, or nil and a reason.
function Profiles.AddPackProfile(entry, as)
    local name = as or entry.name
    local have = data()[name]
    if type(have) == "table" then
        have.unsaved = nil
        return name
    end
    local why
    name, why = Profiles.CheckName(name)
    if not name then return nil, why end
    local t
    t, why = Profiles.ReadyData(entry.name)
    if not t then return nil, why end
    data()[name] = t
    return name
end

-- The pack entry a saved profile can be updated to, when its pack offers
-- updates and has a different version than the one it was made from.
function Profiles.PackUpdate(name)
    local t = data()[name]
    local from = type(t) == "table" and t.fromPack
    if type(from) ~= "table" then return nil end
    local entry = Profiles.PackOf(from.name)
    local pack = entry and entry.pack
    if not (pack and pack.id == from.id and pack.updates == "offer") then return nil end
    if pack.version == nil or pack.version == from.version then return nil end
    if not Profiles.PackProfile(entry) then return nil end
    return entry
end

-- Updates a profile made from a pack to the pack's version. Its settings and
-- frame positions become the pack's (the player's changes to them are lost),
-- what sharing leaves out stays, and its Edit Mode layout is kept. The active
-- profile asks to reload. Returns true, or false and a reason.
function Profiles.UpdateFromPack(name)
    local entry = Profiles.PackUpdate(name)
    if not entry then return false, L["there's nothing newer to bring in"] end
    local p = Profiles.PackProfile(entry)
    local t = data()[name]
    local new = Profiles.Build(packFitted(entry, p), nil, DUI.DB.Fill(t))
    new.pendingLayout = t.pendingLayout
    new.fromPack = { id = entry.pack.id, name = entry.name, version = entry.pack.version }
    -- In place, since the active profile is this very table.
    Profiles.Replace(name, new)
    if name == DUI.DB.ActiveName() then Profiles.AskReload() end
    return true
end

-- Puts a saved ready-made profile back the way it comes (Profiles.ReadyData):
-- its settings and frame positions replace the player's, what sharing leaves
-- out stays, and its Edit Mode layout is kept. The active profile asks to
-- reload. Returns true, or false and a reason.
function Profiles.ResetPreset(name)
    if not DUI.DB.Saved(name) then return false, string.format(L["there's no profile called %s"], tostring(name)) end
    local old = data()[name]
    local new, why = Profiles.ReadyData(name, DUI.DB.Fill(old))
    if not new then return false, why end
    if old.pendingLayout then new.pendingLayout = old.pendingLayout end
    Profiles.Replace(name, new)
    if name == DUI.DB.ActiveName() then Profiles.AskReload() end
    return true
end

-- Bringing action bar positions into a new profile

-- Whether "name" (the active profile when not given) has moved a bar in unlock
-- mode, which is worth offering to a ready-made profile that would otherwise
-- start from DPS/Tank (DaylightUI_ActionBars/Layout.lua stores them as
-- "actionbars.<key>" in the profile's positions).
function Profiles.HasBarPositions(name)
    local p = data()[name or DUI.DB.ActiveName()]
    if type(p) ~= "table" then return false end
    for k in pairs(DUI.DB.Fill(p).positions) do
        if string.match(k, "^actionbars%.") then return true end
    end
    return false
end

-- Copies every "actionbars.*" position from one profile to another,
-- overwriting only those and leaving the rest of "to" as is. A bar's spot and
-- the old bars' spot the new action bars kept for it ("actionbars.old.<bar>",
-- DaylightUI_ActionBars/Bars.lua) travel together; copying one without the
-- other drops the other's.
function Profiles.CopyActionBarPositions(from, to)
    local src, dst = data()[from], data()[to]
    if type(src) ~= "table" or type(dst) ~= "table" then return end
    DUI.DB.Fill(src)
    DUI.DB.Fill(dst)
    for k, v in pairs(src.positions) do
        if string.match(k, "^actionbars%.") then dst.positions[k] = copy(v) end
    end
    for k in pairs(src.positions) do
        local bar = string.match(k, "^actionbars%.([^%.]+)$")
        if bar and src.positions["actionbars.old." .. bar] == nil then dst.positions["actionbars.old." .. bar] = nil end
    end
end

-- Adds a ready-made profile (Profiles.AddPreset). It always starts from the
-- standard setup, so a character on its own profile would lose that profile's
-- action bar arrangement. When there's one to bring along, ask first (Accept
-- copies it). Returns right away like Profiles.AddPreset; the question, if
-- any, follows after.
function Profiles.AddPresetOffering(key)
    local isNew = type(data()[key]) ~= "table"
    local from = Profiles.Current()
    local made, why = Profiles.AddPreset(key)
    if made and isNew and from ~= DUI.DB.DEFAULT and Profiles.HasBarPositions(from) then
        DUI.Widgets.Ask({ key = "profileBars", text = string.format(L["Copy %s's action bar positions into %s too?"], from, made),
            onYes = function() Profiles.CopyActionBarPositions(from, made) end })
    end
    return made, why
end

-- If this character should be on another profile now (its choice or talents
-- changed), asks to reload into it. "Later" leaves it for the next reload or
-- login, which picks it anyway.
function Profiles.CheckSwitch(text)
    local want = DUI.DB.Pick()
    if want == DUI.DB.ActiveName() then return end
    DUI.Widgets.Ask({ key = "profile", text = string.format(text or L["Switch to the profile %s?"], want)
        .. " " .. L["It takes a reload."], yes = RELOADUI or L["Reload"], no = LATER or L["Later"], reload = true,
        onYes = function() Profiles.SwitchNow(want, true) end })
end

-- ReloadUI is blocked unless a click calls it directly, so anything that had
-- to wait (the layout save, combat) ends with this button instead.
function Profiles.AskReload()
    local I = DUI.Installer
    if I and I.HoldReload and I.HoldReload(Profiles.AskReload) then return end
    DUI.Widgets.Ask({ key = "profileReload", text = L["The profile is ready. Reload to use it."],
        yes = RELOADUI or L["Reload"], no = LATER or L["Later"], reload = true })
end

-- Installs the profile's Edit Mode layout, then reloads, and the reload picks
-- the profile itself (DB.Pick). A layout that can't be set now is set after
-- the reload instead (EditMode.lua). `clicked` means this runs inside the
-- question box's secure Reload click, whose /reload follows right after with
-- the layout just written (the game keeps it over a reload, and if it didn't,
-- the load check puts it in place). Otherwise a Reload button is shown.
function Profiles.SwitchNow(name, clicked)
    if InCombatLockdown() then
        DUI.Print(L["Switching profile after combat."])
        DUI.AfterCombat(function() Profiles.SwitchNow(name) end, "profile switch")
        return
    end
    -- The controller UI keeps its own Edit Mode layouts, and installing ours then
    -- crashes the game (EditMode.GamepadMode), so just reload.
    if DUI.DB.PadUI() then
        if clicked then return end
        C_Timer.After(0, Profiles.AskReload)
        return
    end
    local ok, why = EditMode.UseProfile(name)
    if not ok then DUI.Print(string.format(L["The profile's Edit Mode layout will be set after the reload (%s)."], tostring(why))) end
    if clicked then return end
    C_Timer.After(ok and Profiles.SWITCH_DELAY or 0, Profiles.AskReload)
end

-- Talents swapped: switch to the new set's profile if it's different.
function Profiles.OnTalentsChanged()
    DUI.DB.AdoptOldKeys()
    DUI.DB.Character().lastSpec = DUI.DB.SpecGroup()
    Profiles.CheckSwitch(L["These talents use the profile %s. Switch to it?"])
end

pcall(DUI.RegisterEvent, "ACTIVE_TALENT_GROUP_CHANGED", function() Profiles.OnTalentsChanged() end)

-- The game's controller UI was turned on or off (Settings > Gameplay >
-- Gamepad): switch to or from its controller profile if that's different.
function Profiles.OnPadChanged()
    Profiles.CheckSwitch(DUI.DB.PadUI() and L["Controller mode uses the profile %s. Switch to it?"]
        or L["Without the controller, this character uses the profile %s. Switch to it?"])
end

pcall(DUI.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function() Profiles.OnPadChanged() end)

-- In case the game didn't know the talent set at login, run the same check
-- once in the world.
local entered = false
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if entered then return end
    entered = true
    Profiles.OnTalentsChanged()
end)

-- A one-line question with a text box (a new profile's name, a rename)

function Profiles.Prompt(text, initial, onAccept) DUI.Widgets.Prompt(text, initial, onAccept) end

-- fail is the whole sentence, with a hole for the reason ("Couldn't rename it: %s.").
local function said(ok, why, fail)
    if ok then return true end
    DUI.Print(string.format(fail, tostring(why)))
    return false
end

function Profiles.AskNew()
    Profiles.Prompt(string.format(L["A name for the new profile (a copy of %s):"], Profiles.Current()), "", function(name)
        local made, why = Profiles.Create(name)
        if said(made, why, L["Couldn't make it: %s."]) then
            DUI.Print(string.format(L["Made the profile %s. Choose it for this character to use it."], made))
            refresh()
        end
    end)
end

function Profiles.AskRename(old)
    Profiles.Prompt(string.format(L["Rename the profile %s to:"], old), old, function(name)
        if name == old then return end
        local ok, why = Profiles.Rename(old, name)
        if said(ok, why, L["Couldn't rename it: %s."]) then refresh() end
    end)
end

-- The share window: a profile to copy, or a place to paste one

Profiles.BOX = { 520, 320 }
Profiles.WRAP = 64 -- characters per line in the window (a profile has no spaces to wrap at)

local box

-- A profile's text split into lines so it fits the box. Reading ignores spaces
-- and line breaks, so copying it this way still works.
function Profiles.Wrap(s)
    s = string.gsub(s or "", "%s", "")
    local out = {}
    for i = 1, #s, Profiles.WRAP do out[#out + 1] = string.sub(s, i, i + Profiles.WRAP - 1) end
    return table.concat(out, "\n")
end

-- Puts the status line and the parts above the mode row while it shows.
local function placeRows()
    local E = DUI.Win.EDGE
    box.status:ClearAllPoints()
    box.status:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", E, 46 + box.lift)
    box.status:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    box.parts:ClearAllPoints()
    box.parts:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", E, 66 + box.lift)
    box.parts:SetPoint("RIGHT", box, "RIGHT", -E, 0)
end

local function buildBox()
    local W = DUI.Widgets
    local C = W.COLORS
    box = CreateFrame("Frame", "DaylightUIProfileBox", UIParent)
    DUI.Movers.FollowScale(box)
    box:SetSize(Profiles.BOX[1], Profiles.BOX[2])
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    -- Above the options window, which is itself a dialog (and comes to the front
    -- when clicked).
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetToplevel(true)
    box:EnableMouse(true)
    Style.Shell(box)
    -- The window kit's title row: title, X, accent line.
    local Win = DUI.Win
    local E = Win.EDGE
    Win.Header(box, { compact = true, onClose = function() DUI.Motion.Vanish(box) end })
    box.x = box.close -- the header's X (box.close is the footer's Close)
    box.hint = W.Font(box, W.BODY, SIZE.small, C.dim, "LEFT")
    box.hint:SetPoint("TOPLEFT", box, "TOPLEFT", E, -Win.COMPACT - 4)
    box.hint:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    -- The scrolling text.
    local area = W.TextArea(box, { width = Profiles.BOX[1] - 2 * E, onEscape = function() DUI.Motion.Vanish(box) end })
    area:SetPoint("TOPLEFT", box.hint, "BOTTOMLEFT", 0, -14)
    area:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    -- The parts to take, between the text and the status line: no height and
    -- hidden until a profile is pasted (Profiles.ShowParts).
    local parts = CreateFrame("Frame", nil, box)
    parts:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    parts:SetHeight(1)
    parts:Hide()
    parts.head = W.Font(parts, W.BODY, SIZE.small, C.dim, "LEFT")
    parts.head:SetPoint("TOPLEFT", parts, "TOPLEFT", 0, -6)
    parts.rows = {}
    box.parts = parts
    area:SetPoint("BOTTOM", parts, "TOP", 0, 0)
    box.area, box.edit = area, area.edit
    box.status = W.Font(box, W.BODY, SIZE.small, C.dim, "LEFT")
    box.status:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    -- Where an import goes: a new profile, or into the one in use. Only the
    -- import shows it (Profiles.ShowMode).
    local mode = CreateFrame("Frame", nil, box)
    mode:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", E, 46)
    mode:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    mode:SetHeight(W.CHIP_HEIGHT)
    mode.new = W.Chip(mode, L["New profile"])
    mode.new:SetPoint("LEFT", mode, "LEFT", 0, 0)
    mode.into = W.Chip(mode, "")
    mode.into:SetPoint("LEFT", mode.new, "RIGHT", W.CHIP_GAP, 0)
    mode:Hide()
    box.mode = mode
    box.lift = 0
    placeRows()
    box.close = W.Button(box, CLOSE or L["Close"], 26)
    box.close:SetWidth(100)
    box.close:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -E, 12)
    box.close:SetScript("OnClick", function() DUI.Motion.Vanish(box) end)
    box.go = W.Button(box, L["Import"], 26)
    box.go:SetWidth(120)
    box.go.SetActive(true)
    box.go.SetGlow(true)
    box.go:SetPoint("RIGHT", box.close, "LEFT", -8, 0)
    -- The name an imported profile is saved under.
    local name = W.Input(box, { hint = L["Name this profile"] })
    name:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", E, 12)
    name:SetPoint("RIGHT", box.go, "LEFT", -8, 0)
    name:SetScript("OnEscapePressed", function(self) self:ClearFocus(); DUI.Motion.Vanish(box) end)
    box.name = name
    box:Hide()
    -- Glides in, fades out (Escape too).
    DUI.Motion.Window(box, 6)
end

Profiles.PART_ROW = 22 -- a part's row in the import box
Profiles.PART_HEAD = 26 -- the line over them
Profiles.PART_GIVE = 90 -- how much the pasted text gives up for them (it's read by then)

-- One part's row: its name, and a switch at the right. A click anywhere on
-- the row flips it, like an options row.
local function partRow(parts, i)
    local W = DUI.Widgets
    local row = parts.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, parts)
    row:SetHeight(Profiles.PART_ROW)
    row.text = W.Font(row, W.BODY, SIZE.body, W.COLORS.text, "LEFT")
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.switch = W.Switch(row)
    row.switch:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row.text:SetPoint("RIGHT", row.switch, "LEFT", -8, 0)
    row.switch:SetScript("OnClick", function() row.Flip() end)
    row:SetScript("OnClick", function() row.switch:Click() end)
    parts.rows[i] = row
    return row
end

Profiles.MODE_ROW = 32 -- the import's New profile / Into row, over the buttons

-- The box's height for the mode row and the parts as they are right now.
local function sizeBox()
    local v = box.parts.cur or 0
    box:SetHeight(Profiles.BOX[2] + box.lift + v - math.min(v, Profiles.PART_GIVE))
end

-- Shows or hides the mode row, the status line and parts easing up over it.
local function showMode(on)
    local M = DUI.Motion
    local goal = on and Profiles.MODE_ROW or 0
    local function apply(v)
        box.lift = v
        placeRows()
        sizeBox()
    end
    if box:IsShown() then
        M.Tween(box.mode, box.lift, goal, M.NORMAL, apply)
        M.AlphaTo(box.mode, on and 1 or 0, M.NORMAL, true)
    else
        M.Tween(box.mode, goal, goal, 0)
        apply(goal)
        M.AlphaTo(box.mode, on and 1 or 0, 0, true)
    end
end

-- Grows (or shrinks) the box so the parts fit, easing its height.
local function fitParts(h)
    local parts = box.parts
    local from = parts.h or 0
    parts.h = h
    DUI.Motion.Tween(parts, from, h, DUI.Motion.NORMAL, function(v)
        parts:SetHeight(math.max(1, v))
        parts.cur = v
        sizeBox()
    end)
    DUI.Motion.AlphaTo(parts, h > 0 and 1 or 0, DUI.Motion.NORMAL, true)
end

-- Lists list (Profiles.Parts) as switches, all on; onChange(take) runs with
-- the set of parts switched on whenever one flips. nil list hides them.
-- head is the line over them (the import's when not given).
function Profiles.ShowParts(list, onChange, head)
    if not box then buildBox() end
    local parts = box.parts
    if not list or #list == 0 then
        fitParts(0)
        return
    end
    parts.head:SetText(head or L["Take these parts. Whatever you switch off stays as yours."])
    local take = {}
    local half = math.ceil(#list / 2)
    local colW = (Profiles.BOX[1] - 2 * DUI.Win.EDGE) / 2
    for i, part in ipairs(list) do
        local row = partRow(parts, i)
        local col, line = (i > half) and 1 or 0, (i - 1) % half
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parts, "TOPLEFT", col * colW, -Profiles.PART_HEAD - line * Profiles.PART_ROW)
        row:SetWidth(colW)
        row.text:SetText(part.label)
        take[part.key] = true
        row.switch.SetOn(true)
        function row.Flip()
            take[part.key] = not take[part.key] or nil
            row.switch.SetOn(take[part.key] == true)
            onChange(take)
        end
        row:Show()
    end
    for i = #list + 1, #parts.rows do parts.rows[i]:Hide() end
    fitParts(Profiles.PART_HEAD + half * Profiles.PART_ROW + 4)
    onChange(take)
end

local function showBox(title, hint, withMode)
    if not box then buildBox() end
    DUI.Win.Repaint(box) -- the accent line in the current accent
    box.title:SetText(title)
    box.hint:SetText(hint)
    box.status:SetText("")
    box.edit:SetScript("OnTextChanged", nil)
    if not box:IsShown() then
        -- Opened afresh: back to its own size, no parts.
        DUI.Motion.Tween(box.parts, 0, 0, 0)
        box.parts.h, box.parts.cur = 0, 0
        box.parts:Hide()
        box:SetHeight(Profiles.BOX[2])
    else
        Profiles.ShowParts(nil)
    end
    showMode(withMode == true)
    box:Show()
    box:Raise()
    return box
end

function Profiles.ShowExport()
    local snap = Profiles.Snapshot()
    local b = showBox(L["Export profile"], string.format(L["The profile %s: its settings, frame positions and Edit Mode layout. "
        .. "Ctrl+C to copy, then share it."], Profiles.Current()))
    b.go:Hide()
    b.name:Hide()
    local list = Profiles.Parts(snap)
    local count = #list
    -- The text for the parts switched on, remade on each flip.
    local function show(take)
        local W = DUI.Widgets
        local n = 0
        for _ in pairs(take) do n = n + 1 end
        if count > 0 and n == 0 then
            b.area.Lock("", false)
            b.edit:SetText("")
            b.status:SetText(L["Switch on at least one part to share."])
            W.TextColor(b.status, W.COLORS.warn)
            return
        end
        local text, why = Profiles.Encode(n == count and snap or Profiles.Only(snap, take))
        text = text and Profiles.Wrap(text)
        b.edit:SetText(text or "")
        if not text then
            b.status:SetText(string.format(L["Couldn't export: %s."], tostring(why)))
            W.TextColor(b.status, W.COLORS.warn)
            return
        end
        local pop = DUI.Win.Parts.Hex({ Style.Pop() })
        if n == count then
            b.status:SetText(count == 0 and "" or string.format(L["Shares all %s parts."], pop .. n .. "|r"))
        else
            b.status:SetText(string.format(L["Shares %s of %s parts. Whoever imports it keeps their own for the rest."],
                pop .. n .. "|r", count))
        end
        W.TextColor(b.status, W.COLORS.text)
        -- Typing can't change it: restore the profile text, selected.
        b.area.Lock(text, true)
        b.edit:SetFocus()
        b.edit:HighlightText()
    end
    if count > 0 then
        Profiles.ShowParts(list, show, L["Share these parts. Whatever you switch off, they keep their own."])
    else
        show({})
    end
end

-- The same box for any text to copy out (a report to send in), selected and
-- read-only.
function Profiles.ShowText(title, hint, text)
    local b = showBox(title, hint)
    b.go:Hide()
    b.name:Hide()
    b.edit:SetText(text)
    b.area.Lock(text, true)
    b.edit:SetFocus()
    b.edit:HighlightText()
end

local currentSlot = Profiles.CurrentSlot

function Profiles.ShowImport()
    -- A character still on its stand-in has no profile of its own to bring parts into.
    local canInto = not DUI.DB.Unsaved()
    local b = showBox(L["Import profile"], canInto
        and L["Paste a DaylightUI profile (Ctrl+V). Make it a new profile, or bring parts into the one in use."]
        or L["Paste a DaylightUI profile (Ctrl+V) and name it. It becomes a new profile, "
        .. "chosen for this character (these talents, with dual spec); yours stay as they are."], canInto)
    b.go:Show()
    b.go.text:SetText(L["Import"]) -- ShowPaste may have changed its label
    b.name:Show()
    b.name:SetAlpha(1)
    b.name:SetText("")
    b.edit:SetText("")
    local pending, take, count, shown
    local into = false
    local current = Profiles.Current()
    local function named() return strtrim(b.name:GetText() or "") end
    local function picked()
        local n = 0
        for _ in pairs(take or {}) do n = n + 1 end
        return n
    end
    -- A profile of only defaults lists no parts and imports whole.
    local function enough() return count == 0 or picked() > 0 end
    local function ready() b.go:SetAlpha((pending and enough() and (into or named() ~= "")) and 1 or 0.4) end
    -- How many parts it takes, the number in the accent.
    local function said()
        local W = DUI.Widgets
        local n = picked()
        if count == 0 then
            b.status:SetText(L["Nothing but the defaults."])
            W.TextColor(b.status, W.COLORS.text)
            return
        end
        if n == 0 then
            b.status:SetText(L["Switch on at least one part to import."])
            W.TextColor(b.status, W.COLORS.warn)
            return
        end
        local pop = DUI.Win.Parts.Hex({ Style.Pop() })
        if into and n == count then
            b.status:SetText(string.format(L["Takes all %s parts into %s."], pop .. n .. "|r", current))
        elseif into then
            b.status:SetText(string.format(L["Takes %s of %s parts into %s. The rest stay as they are."],
                pop .. n .. "|r", count, current))
        elseif n == count then
            b.status:SetText(string.format(L["Takes all %s parts."], pop .. n .. "|r"))
        else
            b.status:SetText(string.format(L["Takes %s of %s parts. The rest stay as yours."], pop .. n .. "|r", count))
        end
        W.TextColor(b.status, W.COLORS.text)
    end
    -- New profile or into the one in use: the name box only matters for a new one.
    local function pick(on)
        into = on
        b.mode.new.SetOn(not on)
        b.mode.into.SetOn(on)
        DUI.Motion.AlphaTo(b.name, on and 0 or 1, DUI.Motion.FAST, true)
        if on then b.name:ClearFocus() end
        if pending then said() end
        ready()
    end
    b.mode.into.text:SetText(string.format(L["Into %s"], current))
    b.mode.new.FitWidth()
    b.mode.into.FitWidth()
    b.mode.new:SetScript("OnClick", function() pick(false) end)
    b.mode.into:SetScript("OnClick", function() pick(true) end)
    pick(false)
    local function check(_, user)
        -- Pasted as one long line: shown in lines so it fits the box.
        local now = b.edit:GetText()
        if user and #now > Profiles.WRAP and not string.find(now, "\n", 1, true) then
            b.edit:SetText(Profiles.Wrap(now))
            return
        end
        local p, why = Profiles.Decode(b.edit:GetText())
        local W = DUI.Widgets
        if p then
            -- The same string pasted again keeps the switches as they are.
            if now ~= shown then
                local list = Profiles.Parts(p)
                count, take = #list, {}
                Profiles.ShowParts(list, function(t) take = t; said(); ready() end)
            end
            pending, shown = p, now
            said()
        else
            pending, take, shown = nil, nil, nil
            Profiles.ShowParts(nil)
            b.status:SetText(now == "" and "" or string.format(L["Can't import: %s."], why))
            W.TextColor(b.status, W.COLORS.warn)
        end
        ready()
    end
    b.edit:SetScript("OnTextChanged", check)
    b.name:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        ready()
    end)
    local function warn(text)
        b.status:SetText(text)
        DUI.Widgets.TextColor(b.status, DUI.Widgets.COLORS.warn)
    end
    local function go()
        if not pending then return end
        if not enough() then return end
        if into then
            local made, from, to = Profiles.ImportInto(pending, take)
            b:Hide()
            if from and from ~= to then
                DUI.Print(string.format(L["Brought the picked parts into %s, its frames fitted from a %s screen to your %s one."],
                    made, from, to))
            else
                DUI.Print(string.format(L["Brought the picked parts into %s."], made))
            end
            return
        end
        if named() == "" then
            warn(L["Give it a name first."])
            b.name:SetFocus()
            return
        end
        local shared, from, to = Profiles.Fit(pending, take)
        -- Always through Take: a string shared with parts left out gets yours for those.
        shared = Profiles.Take(shared, take)
        local made, why = Profiles.Create(named(), shared)
        if not made then
            warn(string.format(L["Can't import: %s."], tostring(why)))
            return
        end
        b:Hide()
        if from and from ~= to then
            DUI.Print(string.format(L["Imported the profile %s, its frames fitted from a %s screen to your %s one."],
                made, from, to))
        else
            DUI.Print(string.format(L["Imported the profile %s."], made))
        end
        Profiles.Choose(currentSlot(), made)
    end
    b.go:SetScript("OnClick", go)
    b.name:SetScript("OnEnterPressed", go)
    check()
    b.edit:SetFocus()
end

-- The same box for any other text to paste in (the Cooldown Manager's layout
-- strings). spec = { title, hint, read = fn(text) -> what, summary | nil, why;
-- button = fn(what) -> its label; go = fn(what) -> nil | why }. There's no
-- name to give, and it closes once go accepts.
function Profiles.ShowPaste(spec)
    local b = showBox(spec.title, spec.hint)
    local W = DUI.Widgets
    b.go:Show()
    b.name:Hide()
    b.edit:SetText("")
    local pending
    local function label(what)
        b.go.text:SetText(spec.button and spec.button(what) or L["Import"])
    end
    local function check(_, user)
        local now = b.edit:GetText()
        if user and #now > Profiles.WRAP and not string.find(now, "\n", 1, true) then
            b.edit:SetText(Profiles.Wrap(now))
            return
        end
        local what, said = spec.read(now)
        pending = what
        if what then
            b.status:SetText(said or "")
            W.TextColor(b.status, W.COLORS.text)
        else
            b.status:SetText(now == "" and "" or string.format(L["Can't import: %s."], tostring(said)))
            W.TextColor(b.status, W.COLORS.warn)
        end
        label(what)
        b.go:SetAlpha(what and 1 or 0.4)
    end
    b.edit:SetScript("OnTextChanged", check)
    b.go:SetScript("OnClick", function()
        if not pending then return end
        local why = spec.go(pending)
        if why then
            b.status:SetText(string.format(L["Can't import: %s."], tostring(why)))
            W.TextColor(b.status, W.COLORS.warn)
            return
        end
        DUI.Motion.Vanish(b)
    end)
    check()
    b.edit:SetFocus()
    return b
end

-- The Profiles page

local LINE = 34

local function choices()
    local values, keys = {}, Profiles.Names()
    for _, n in ipairs(keys) do values[n] = n end
    return values, keys
end

local function chooser(slot, label, desc, hidden)
    return { type = "dropdown", label = label, desc = desc, choices = choices, hidden = hidden,
             get = function() return Profiles.Chosen(slot) end,
             set = function(v) Profiles.Choose(slot, v) end }
end

local function dual() return DUI.DB.DualSpec() end
local function single() return not DUI.DB.DualSpec() end

-- The profiles, each with Rename and Delete. "New" copies the active one.
local list = {
    type = "custom", label = "Profiles",
    build = function(row)
        local W = DUI.Widgets
        local C = W.COLORS
        row.new = W.Button(row, L["New profile"], 26)
        row.new:SetWidth(140)
        row.new:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8)
        row.new:SetScript("OnClick", function() Profiles.AskNew() end)
        row.newHint = W.Font(row, W.BODY, SIZE.small, C.dim, "LEFT")
        row.newHint:SetPoint("LEFT", row.new, "RIGHT", 12, 0)
        row.newHint:SetText(L["A copy of the one in use, layout and all."])
        row.lines = {}
    end,
    update = function(row)
        local W = DUI.Widgets
        local C = W.COLORS
        local names = Profiles.Names()
        local current = Profiles.Current()
        for i, n in ipairs(names) do
            local line = row.lines[i]
            if not line then
                line = CreateFrame("Frame", nil, row)
                line:SetHeight(LINE)
                line.label = W.Font(line, W.BODY, SIZE.body, C.text, "LEFT")
                line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
                line.tag = W.Font(line, W.BODY, SIZE.small, C.dim, "LEFT")
                line.tag:SetPoint("LEFT", line.label, "RIGHT", 8, 0)
                line.delete = W.Button(line, DELETE or L["Delete"], 24)
                line.delete:SetWidth(90)
                line.delete:SetPoint("RIGHT", line, "RIGHT", 0, 0)
                line.rename = W.Button(line, L["Rename"], 24)
                line.rename:SetWidth(90)
                line.rename:SetPoint("RIGHT", line.delete, "LEFT", -8, 0)
                row.lines[i] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -(44 + (i - 1) * LINE))
            line:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
            line.label:SetText(n)
            local users = #Profiles.UsersOf(n)
            local tag = n == current and L["in use"] or ""
            if users > 0 then
                local who = string.format(users == 1 and L["%d character"] or L["%d characters"], users)
                tag = tag ~= "" and string.format(L["%s, %s"], tag, who) or who
            end
            line.tag:SetText(tag ~= "" and ("(" .. tag .. ")") or "")
            line.rename:SetShown(n ~= DUI.DB.DEFAULT)
            line.delete:SetShown(n ~= current)
            line.rename:SetScript("OnClick", function() Profiles.AskRename(n) end)
            -- Deleting loses it, so it takes a second click.
            W.Confirm(line.delete, DELETE or L["Delete"], function()
                local ok, why = Profiles.Delete(n)
                if said(ok, why, L["Couldn't delete it: %s."]) then refresh() end
            end)
            line:Show()
        end
        for i = #names + 1, #row.lines do row.lines[i]:Hide() end
        row.count = #names
    end,
    height = function(row) return 44 + (row.count or #Profiles.Names()) * LINE + 6 end,
}

-- A pack's card: its author, then an Add button per profile (and Update when
-- the pack offers updates and has a newer one than the profile was made from).
local function packGroup(pack)
    local by = pack.author and string.format(L["By %s."], pack.author) or nil
    local desc = by and pack.desc and (by .. " " .. pack.desc) or by or pack.desc
    local items = {}
    for _, e in ipairs(Profiles.PackProfiles(pack)) do
        items[#items + 1] = { type = "button", label = e.name, text = "Add",
            -- The pack's own line stays as written; only the fixed sentence is translated.
            desc = (e.sub and (e.sub .. " ") or "") .. L["Made the first time you add it; after that, the one you have is used as it is. Choose it above to use it."],
            hidden = function() return type(data()[e.name]) == "table" and Profiles.PackUpdate(e.name) ~= nil end,
            func = function()
                local made, why = Profiles.AddPresetOffering(e.name)
                if said(made, why, L["Couldn't add it: %s."]) then
                    DUI.Print(string.format(L["The profile %s is ready. Choose it for this character (or a talent set) to use it."], made))
                    refresh()
                end
            end }
        if pack.updates == "offer" then
            items[#items + 1] = { type = "button", label = e.name, text = "Update", confirm = true,
                desc = "Brings in the pack's newer version of this profile: its settings and frame positions replace yours. Your Edit Mode layout stays as it is.",
                hidden = function() return Profiles.PackUpdate(e.name) == nil end,
                func = function()
                    local ok, why = Profiles.UpdateFromPack(e.name)
                    if said(ok, why, L["Couldn't update it: %s."]) then
                        DUI.Print(string.format(L["%s now has %s's newest settings."], e.name, pack.label))
                        refresh()
                    end
                end }
        end
    end
    if #items == 0 then return nil end
    return { label = pack.label, desc = desc, items = items }
end

local function profileGroups(base)
    local groups = {}
    for _, g in ipairs(base) do
        groups[#groups + 1] = g
        if g.label == "Ready-made" then
            for _, id in ipairs(Profiles.PACK_ORDER) do
                groups[#groups + 1] = packGroup(Profiles.PACKS[id])
            end
        end
    end
    return groups
end

-- Our ready-made profiles ({ name, desc }): Add while one isn't saved (the
-- setup guide may have made only one, or it was deleted), Reset once it is.
local function readyMade(list)
    local items = {}
    for _, e in ipairs(list) do
        local name = e[1]
        items[#items + 1] = { type = "button", label = name, text = "Add", desc = e[2],
            hidden = function() return DUI.DB.Saved(name) end,
            func = function()
                local made, why = Profiles.AddPresetOffering(name)
                if said(made, why, L["Couldn't add it: %s."]) then
                    DUI.Print(string.format(L["The profile %s is ready. Choose it for this character (or a talent set) to use it."], made))
                    refresh()
                end
            end }
        items[#items + 1] = { type = "button", label = name, text = "Reset", confirm = true,
            desc = "Puts this profile back the way it comes: its settings and frame positions replace yours. Your Edit Mode layout stays as it is.",
            hidden = function() return not DUI.DB.Saved(name) end,
            func = function()
                local ok, why = Profiles.ResetPreset(name)
                if said(ok, why, L["Couldn't reset it: %s."]) then
                    DUI.Print(string.format(L["%s is back the way it comes."], name))
                    refresh()
                end
            end }
    end
    return items
end

local PAGE_GROUPS -- the page's own cards, with the packs' placed among them
local profilesPage = DUI.Options.RegisterPage({
    id = "profiles", section = "core", label = "Profiles", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "Each character uses a profile (one per talent set, with dual spec). Everything on every page changes the profile in use.",
    groups = {
        { label = "This character", items = {
            { type = "text", label = function() return string.format(L["In use: %s"], Profiles.Current()) end },
            chooser("character", "Profile", "The profile this character uses. Changing it asks to reload.", dual),
            chooser(1, "Primary talents", "The profile for your first talent set. Changing it asks to reload.", single),
            chooser(2, "Secondary talents", "The profile for your second talent set; swapping talents asks to switch.", single),
            { type = "dropdown", label = "Controller mode", since = "1.7.0",
              desc = "The profile this character uses while the game's controller UI is on (Settings > Gameplay > Gamepad). Turning it on or off asks to switch. With None, it uses the same profile as without it.",
              choices = function()
                  local values, keys = choices()
                  values[Profiles.NONE] = NONE or L["None"]
                  table.insert(keys, 1, Profiles.NONE)
                  return values, keys
              end,
              get = function() return Profiles.Chosen("pad") end,
              set = function(v) Profiles.Choose("pad", v) end },
        } },
        { label = "Profiles", desc = "Kept for every character on this account, each with its own Edit Mode layout.",
          items = { list } },
        { label = "Ready-made", desc = "Built from DPS/Tank (the standard profile) the first time you add one; after that, the one you have is used as it is. Reset puts it back the way it comes.", items = readyMade({
            { "DPS/Tank", "The standard profile, as it comes. Choose it above to use it. "
                  .. "If the profile you're on has moved action bars, it offers to bring them along." },
            { "Healer", "DPS/Tank with your party and raid as square tiles under you (you included, missing health on them, dispels easy to see), and your frame and your target's raised a little. Everything it sets is on the Party and Raid pages; move any of them in unlock mode. Choose it above to use it. "
                  .. "If the profile you're on has moved action bars, it offers to bring them along." },
            { "Immersive Preset", "DPS/Tank made calm for questing: your action bars and your own frame fade a while after a fight (back under the mouse, in a fight or when you're hurt), the damage meter starts folded (one click on the panel's tab brings it out), the minimap is a little smaller and the XP bar shows its percent. Nothing fades in dungeons, raids, battlegrounds or arenas (General > Fade, Fade only in the open world). Choose it above to use it. "
                  .. "If the profile you're on has moved action bars, it offers to bring them along." },
        }) },
        { label = "Share", desc = "Settings, frame positions and the Edit Mode layout; not what's learned as you play.", items = {
            { type = "button", label = "Export", text = "Export",
              desc = "The profile in use as text to copy and share.", func = function() Profiles.ShowExport() end },
            { type = "button", label = "Import", text = "Import",
              desc = "Paste someone's profile. It becomes a new profile; yours stay as they are.",
              func = function() Profiles.ShowImport() end },
        } },
    },
})
-- A card per pack under Ready-made. Packs register as their addons load,
-- before the window first draws the page (like the Gradients page's late pairs).
PAGE_GROUPS = profilesPage.groups
DUI.On("PacksChanged", function() profilesPage.groups = profileGroups(PAGE_GROUPS) end)

DUI.RegisterCommand("export", function() Profiles.ShowExport() end, function() return L["/dui export - the profile in use as text to share"] end)
DUI.RegisterCommand("import", function() Profiles.ShowImport() end, function() return L["/dui import - add a shared DaylightUI profile"] end)
