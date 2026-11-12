-- World map pins: dungeon and raid entrances, flight masters (yours, or both
-- factions'), boats and zeppelins. Icons by Wawis (Media/mappin-*.png); the
-- flight boot is white and tinted by faction.
--
-- Entrances and flight masters come from the game's own tables (MapPinsData.lua,
-- built by tools/make_mapdata.py) in world coordinates, which
-- C_Map.GetMapPosFromWorldPos turns into map positions once per map. Boats and
-- zeppelins are a hand-made list of Forever's docks (Pins.TRAVEL), also in world
-- coordinates. Only zone maps get pins. Pins that land on the same spot
-- (Blackrock Mountain, a zeppelin tower) merge into one that lists them all.
--
-- Like the map reveal, everything is our own frame over the map canvas at the
-- game's dungeon entrance level. The map's id, canvas and level table are only
-- read. Pins keep their on-screen size as the map zooms.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Pins = {}
ns.MapPins = Pins

Pins.SIZE = 24 -- on screen, before the map's own scale
Pins.HOVER = 1.25           -- grows under the mouse
Pins.MERGE = 0.015 -- pins closer than this (fraction of the map) merge
Pins.LEVEL = 2100 -- PIN_FRAME_LEVEL_DUNGEON_ENTRANCE, if its table can't be read
Pins.ZONE = 3               -- Enum.UIMapType.Zone

Pins.COLORS = {
    alliance = { 0.44, 0.63, 0.91 },
    horde = { 0.88, 0.42, 0.35 },
    both = { 0.91, 0.76, 0.48 },
}

-- Boats and zeppelins: { kind, continent, world x, world y, destination area,
-- fallback name }. Each dock is a stop on one of Forever's transport paths
-- (TaxiPathNode, build 1.60.1.70334, path id in the trailing comment). The
-- destination name comes from the game (AreaTable, C_Map.GetAreaInfo).
Pins.TRAVEL = {
    { "boat", 0, -3905, -586, 513, "Theramore Isle" },          -- 292 Menethil Harbor
    { "boat", 1, -4016, -4741, 150, "Menethil Harbor" },        -- 292 Theramore
    { "boat", 0, -3709, -575, 271, "Southshore" },              -- 11167 Menethil Harbor
    { "boat", 0, -3709, -575, 442, "Auberdine" },
    { "boat", 0, -1103, -555, 150, "Menethil Harbor" },         -- 11167 Southshore
    { "boat", 0, -1103, -555, 442, "Auberdine" },
    { "boat", 1, 6406, 823, 271, "Southshore" },                -- 11167 Auberdine
    { "boat", 1, 6406, 823, 150, "Menethil Harbor" },
    { "boat", 1, 6594, 760, 702, "Rut'theran Village" },        -- 293 Auberdine
    { "boat", 1, 8532, 1024, 442, "Auberdine" },                -- 293 Rut'theran Village
    { "boat", 1, 6548, 942, 17203, "Stormwind Harbor" },        -- 11616 Auberdine
    { "boat", 0, -8654, 1344, 442, "Auberdine" },               -- 11616 Stormwind Harbor
    { "boat", 0, -14278, 583, 392, "Ratchet" },                 -- 241 Booty Bay
    { "boat", 1, -1006, -3842, 35, "Booty Bay" },               -- 241 Ratchet
    { "boat", 1, -4197, 3287, 1108, "The Forgotten Coast" },    -- 303 Feathermoon
    { "boat", 1, -4348, 2444, 1116, "Feathermoon Stronghold" }, -- 303 the coast
    { "boat", 1, -6933, -4951, 16727, "Powderfuse Port" },      -- 11391 Steamwheedle Port
    { "boat", 0, -8232, -5801, 977, "Steamwheedle Port" },      -- 11391 Powderfuse Port
    { "zeppelin", 1, 1318, -4658, 1497, "Undercity" },          -- 302 Orgrimmar
    { "zeppelin", 0, 2062, 293, 1637, "Orgrimmar" },            -- 302 Undercity
    { "zeppelin", 1, 1361, -4631, 117, "Grom'gol Base Camp" },  -- 285 Orgrimmar
    { "zeppelin", 0, -12464, 232, 1637, "Orgrimmar" },          -- 285 Grom'gol
    { "zeppelin", 0, 2063, 235, 117, "Grom'gol Base Camp" },    -- 301 Undercity
    { "zeppelin", 0, -12407, 212, 1497, "Undercity" },          -- 301 Grom'gol
    { "zeppelin", 0, 545, 424, 16638, "Valanaar" },             -- 11398 Dalaran
    { "zeppelin", 2991, 1848, 569, 279, "Dalaran" },            -- 11398 Valanaar
    { "zeppelin", 1, -802, 367, 16638, "Valanaar" },            -- 11457 Skywatcher Plateau
    { "zeppelin", 2991, 1953, 1019, 17045, "Skywatcher Plateau" }, -- 11457 Valanaar
}

-- Forever's new dungeons. The game's Map table has no corpse point for them and
-- C_EncounterJournal.GetDungeonEntrancesForMap returns nothing, so their entrances
-- come from the Forever guides: { kind, instance map id, zone map, x, y, players,
-- name }. If the game's data gains one later, that wins and it can be dropped
-- here. Manor Mistmantle's entrance isn't known yet.
Pins.ENTRANCES = {
    { "dungeon", 2998, 1437, 0.534, 0.653, 5, "Excavation Site: Wetlands" },
    { "dungeon", 2999, 1420, 0.633, 0.675, 5, "Ruins of Lordaeron" },
    { "dungeon", 3065, 1455, 0.435, 0.520, 5, "The Hall of Thanes" },
    { "dungeon", 2959, 1421, 0.696, 0.461, 5, "City of Dalaran" },
}

local cfg, frame, drawnFor, drawnW, drawnScale
local pool, used = {}, 0
local spots = {} -- [mapID] = pins on that map (cached, the data never changes)

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function map()
    local f = _G.WorldMapFrame
    local sc = type(f) == "table" and f.ScrollContainer
    local child = type(sc) == "table" and sc.Child
    if type(child) ~= "table" then return nil end
    return f, child
end

local function level(f)
    local m = f.pinFrameLevelsManager
    local d = type(m) == "table" and type(m.definitions) == "table" and m.definitions.PIN_FRAME_LEVEL_DUNGEON_ENTRANCE
    return type(d) == "table" and type(d.startLevel) == "number" and d.startLevel or Pins.LEVEL
end

local function want(key) return cfg ~= nil and cfg[key] ~= false end
-- Pin size on screen and opacity, from the settings.
function Pins.Size() return Pins.SIZE * (cfg and tonumber(cfg.mapPinScale) or 1) end
function Pins.Alpha() return cfg and tonumber(cfg.mapPinAlpha) or 1 end

function Pins.On() return want("mapDungeons") or want("mapFlights") or want("mapTravel") end

-- A world point's position on this map, or nil if it's off the map.
function Pins.Spot(continent, wx, wy, mapID)
    local vec = type(CreateVector2D) == "function" and CreateVector2D(wx, wy)
    if not vec then return nil end
    local _, pos = call(C_Map and C_Map.GetMapPosFromWorldPos, continent, vec, mapID)
    if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
    local x, y = pos:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function areaName(id)
    local name = call(C_Map and C_Map.GetAreaInfo, id)
    return type(name) == "string" and name ~= "" and name or nil
end

-- One tooltip line for a pin: title and what it is.
local function instanceLine(e)
    local name = call(GetRealZoneText, e[2])
    if type(name) ~= "string" or name == "" then name = e[7] end
    if e[1] == "raid" then return name, string.format(L["Raid, %d players"], e[6]) end
    return name, L["Dungeon"]
end

-- Adds a pin, or merges it into a nearby one of the same family.
local function add(list, family, kind, x, y, title, sub)
    for _, p in ipairs(list) do
        if p.family == family and math.abs(p.x - x) < Pins.MERGE and math.abs(p.y - y) < Pins.MERGE then
            p.lines[#p.lines + 1] = { title, sub }
            if kind == "raid" then p.kind = "raid" end
            return
        end
    end
    list[#list + 1] = { family = family, kind = kind, x = x, y = y, lines = { { title, sub } } }
end

-- All pins on a zone map, computed once.
function Pins.For(mapID)
    if spots[mapID] then return spots[mapID] end
    local list = {}
    local info = call(C_Map and C_Map.GetMapInfo, mapID)
    if type(info) == "table" and info.mapType == Pins.ZONE then
        local data = ns.MapPinsData or {}
        local known = {}
        for _, e in ipairs(data.instances or {}) do
            known[e[2]] = true
            local x, y = Pins.Spot(e[3], e[4], e[5], mapID)
            if x then add(list, "instance", e[1], x, y, instanceLine(e)) end
        end
        for _, e in ipairs(Pins.ENTRANCES) do
            if e[3] == mapID and not known[e[2]] then add(list, "instance", e[1], e[4], e[5], instanceLine(e)) end
        end
        for _, e in ipairs(data.flights or {}) do
            local x, y = Pins.Spot(e[2], e[3], e[4], mapID)
            if x then
                list[#list + 1] = { family = "flight", kind = "flight", side = e[5], x = x, y = y,
                    lines = { { L[e[6]], L["Flight master"] } } }
            end
        end
        for _, e in ipairs(Pins.TRAVEL) do
            local x, y = Pins.Spot(e[2], e[3], e[4], mapID)
            if x then
                local to = areaName(e[5]) or e[6]
                local title = e[1] == "boat" and string.format(L["Boat to %s"], to) or string.format(L["Zeppelin to %s"], to)
                add(list, "travel", e[1], x, y, title, nil)
            end
        end
    end
    spots[mapID] = list
    return list
end

-- side: 1 Alliance, 2 Horde, 3 both. Whether you can use that flight master
-- (always, with mapFlightsAll on).
function Pins.Usable(side)
    if side == 3 or (cfg and cfg.mapFlightsAll == true) then return true end
    local mine = call(UnitFactionGroup, "player")
    if mine == "Alliance" then return side == 1 end
    if mine == "Horde" then return side == 2 end
    return true
end

function Pins.Shows(p)
    if p.family == "instance" then return want("mapDungeons") end
    if p.family == "travel" then return want("mapTravel") end
    return want("mapFlights") and Pins.Usable(p.side)
end

-- Only the flight boot is tinted by faction; other pins keep their colors.
local WHITE = { 1, 1, 1 }
function Pins.Color(p)
    if p.kind == "flight" then
        return Pins.COLORS[p.side == 1 and "alliance" or p.side == 2 and "horde" or "both"]
    end
    return WHITE
end

local function grow(b, on)
    local from = b.at or 1
    local to = on and Pins.HOVER or 1
    DUI.Motion.Tween(b, from, to, DUI.Motion.FAST, function(v)
        b.at = v
        b.icon:SetSize(Pins.Size() * v, Pins.Size() * v)
    end)
end

local function onEnter(b)
    grow(b, true)
    local p = b.pin
    if not p then return end
    GameTooltip:Hide()
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local Tips = DUI.Tips
    Tips.Clear()
    for i, line in ipairs(p.lines) do
        if i > 1 then Tips.Gap() end
        Tips.Title(line[1])
        if line[2] then Tips.Sub(line[2]) end
    end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function onLeave(b)
    grow(b, false)
    GameTooltip:Hide()
end

local function button()
    used = used + 1
    local b = pool[used]
    if not b then
        b = CreateFrame("Frame", nil, frame)
        b:SetSize(Pins.SIZE, Pins.SIZE)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("CENTER")
        b.icon:SetSize(Pins.SIZE, Pins.SIZE)
        b.fade = {} -- tween key for its fade (the grow uses the button)
        b:EnableMouse(true)
        -- Hover only, so clicks still reach the map (zoom, pick a zone).
        if b.SetMouseClickEnabled then b:SetMouseClickEnabled(false) end
        b:SetScript("OnEnter", onEnter)
        b:SetScript("OnLeave", onLeave)
        pool[used] = b
    end
    return b
end

-- Scales and places every shown pin, also after a zoom or canvas resize. The
-- canvas grows as the map zooms, so pins shrink by the same factor.
function Pins.Place()
    local _, child = map()
    if not child then return end
    local w, h = child:GetWidth(), child:GetHeight()
    drawnW, drawnScale = w, child:GetScale()
    local s = drawnScale and drawnScale > 0 and 1 / drawnScale or 1
    for i = 1, used do
        local b = pool[i]
        b:SetScale(s)
        b:ClearAllPoints()
        b:SetPoint("CENTER", frame, "TOPLEFT", b.pin.x * w / s, -b.pin.y * h / s)
    end
end

function Pins.Draw()
    if not frame then return end
    for i = 1, used do pool[i]:Hide(); pool[i].pin = nil end
    used = 0
    local f = map()
    drawnFor = f and f.mapID or nil
    -- OpenMap's stitched map draws its own entrances, flight paths and boats.
    if not Pins.On() or type(drawnFor) ~= "number" or DUI.OpenMap.Stitched() then return end
    frame:SetFrameLevel(level(f))
    for _, p in ipairs(Pins.For(drawnFor)) do
        if Pins.Shows(p) then
            local b = button()
            b.pin = p
            b.icon:SetTexture(DUI.MEDIA .. "mappin-" .. p.kind .. ".png")
            local c = Pins.Color(p)
            b.icon:SetVertexColor(c[1], c[2], c[3])
            b.at = 1
            b:SetSize(Pins.Size(), Pins.Size())
            b.icon:SetSize(Pins.Size(), Pins.Size())
            b:Show()
            b:SetAlpha(0)
            DUI.Motion.Tween(b.fade, 0, Pins.Alpha(), DUI.Motion.FAST, function(v) b:SetAlpha(v) end)
        end
    end
    Pins.Place()
end

local function build()
    local f, child = map()
    if not f then return false end
    frame = CreateFrame("Frame", nil, child)
    frame:SetAllPoints(child)
    frame:EnableMouse(false)
    Pins.frame = frame
    frame:SetScript("OnShow", function() Pins.Draw() end)
    DUI.On("OpenMapStitched", function() if frame:IsVisible() then Pins.Draw() end end)
    -- Redraw on a new map id, or a zoom or canvas resize (scale or width change).
    frame:SetScript("OnUpdate", function()
        if f.mapID ~= drawnFor then Pins.Draw()
        elseif child:GetWidth() ~= drawnW or child:GetScale() ~= drawnScale then Pins.Place() end
    end)
    return true
end

-- Waits for the map like a skin, but in no pack, so it works whether or not
-- the map is skinned.
ns.Engine.Register({ key = "worldmap.pins", apply = function()
    if frame then return end
    if not build() then return false end
    -- All off: hidden, so the per-frame map check costs nothing.
    frame:SetShown(Pins.On())
    Pins.Draw()
end })

function Pins.Start(c)
    cfg = c
    if frame then
        frame:SetShown(Pins.On())
        Pins.Draw()
    end
end
