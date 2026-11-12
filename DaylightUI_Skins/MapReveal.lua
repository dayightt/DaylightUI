-- Shows the world map's unexplored areas, dimmed (setting mapReveal, brightness
-- mapRevealDim). The client only gives addons the explored pieces
-- (C_MapExplorationInfo.GetExploredMapTextures). Every piece of every map comes
-- from the game's tables (MapRevealData.lua, built by tools/make_mapdata.py), and
-- the unexplored ones are drawn the way MapExplorationPinMixin:RefreshOverlays
-- draws explored ones: tiles of the art layer's size from each piece's top-left.
--
-- It's all our own frame and textures over the map canvas at the game's
-- exploration level. Nothing on the map is called or written; canvas, map id and
-- level table are only read. A map change is detected by its id, checked each
-- frame while the map is shown.

local _, ns = ...
local DUI = DaylightUI

local Reveal = {}
ns.MapReveal = Reveal

Reveal.DIM = 0.6 -- fallback if the setting can't be read
Reveal.LEVEL = 2002 -- PIN_FRAME_LEVEL_MAP_EXPLORATION, if its table can't be read
Reveal.TILE = 256

local cfg, frame, drawnFor
local pool, used = {}, 0

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

local function map()
    local f = _G.WorldMapFrame
    local sc = type(f) == "table" and f.ScrollContainer
    local child = type(sc) == "table" and sc.Child
    if type(child) ~= "table" then return nil end
    return f, child
end

function Reveal.On() return cfg ~= nil and cfg.mapReveal == true end

function Reveal.Dim()
    local d = cfg and cfg.mapRevealDim
    if type(d) ~= "number" then return Reveal.DIM end
    return math.max(0.1, math.min(1, d))
end

local function level(f)
    local m = f.pinFrameLevelsManager
    local d = type(m) == "table" and type(m.definitions) == "table" and m.definitions.PIN_FRAME_LEVEL_MAP_EXPLORATION
    return type(d) == "table" and type(d.startLevel) == "number" and d.startLevel or Reveal.LEVEL
end

-- "w:h:x:y" for every explored piece on this map.
function Reveal.Explored(mapID)
    local out = {}
    local list = call(C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures, mapID)
    if type(list) ~= "table" then return out end
    for _, t in ipairs(list) do
        if type(t) == "table" then
            out[(t.textureWidth or 0) .. ":" .. (t.textureHeight or 0) .. ":" .. (t.offsetX or 0) .. ":" .. (t.offsetY or 0)] = true
        end
    end
    return out
end

local function tileSize(mapID)
    local layers = call(C_Map and C_Map.GetMapArtLayers, mapID)
    local l = type(layers) == "table" and layers[1]
    local w = type(l) == "table" and l.tileWidth or Reveal.TILE
    local h = type(l) == "table" and l.tileHeight or Reveal.TILE
    return w, h
end

local function texture()
    used = used + 1
    local t = pool[used]
    if not t then
        t = frame:CreateTexture(nil, "ARTWORK")
        pool[used] = t
    end
    t:Show()
    return t
end

-- Same tiling as MapExplorationPinMixin:RefreshOverlays: full tiles, then the
-- last row and column trimmed to what's left, from a file sized to the next
-- power of two.
local function fileSize(px) local s = 16; while s < px do s = s * 2 end return s end

function Reveal.DrawPiece(w, h, x, y, ids, tw, th, dim)
    local wide, tall = math.ceil(w / tw), math.ceil(h / th)
    for j = 1, tall do
        local ph, fh = th, th
        if j == tall then
            ph = h % th
            if ph == 0 then ph = th end
            fh = fileSize(ph)
        end
        for k = 1, wide do
            local id = ids[(j - 1) * wide + k]
            if id then
                local pw, fw = tw, tw
                if k == wide then
                    pw = w % tw
                    if pw == 0 then pw = tw end
                    fw = fileSize(pw)
                end
                local t = texture()
                t:SetSize(pw, ph)
                t:SetTexCoord(0, pw / fw, 0, ph / fh)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", frame, "TOPLEFT", x + tw * (k - 1), -(y + th * (j - 1)))
                t:SetTexture(id, nil, nil, "TRILINEAR")
                t:SetVertexColor(dim, dim, dim, 1)
            end
        end
    end
end

function Reveal.Draw()
    if not frame then return end
    for i = 1, used do pool[i]:Hide() end
    used = 0
    local f = map()
    drawnFor = f and f.mapID or nil
    -- OpenMap's stitched map has its own art for unexplored areas.
    if not Reveal.On() or type(drawnFor) ~= "number" or DUI.OpenMap.Stitched() then return end
    local list = ns.MapRevealData and ns.MapRevealData[drawnFor]
    if not list then return end
    frame:SetFrameLevel(level(f))
    local seen = Reveal.Explored(drawnFor)
    local tw, th = tileSize(drawnFor)
    local dim = Reveal.Dim()
    for _, piece in ipairs(list) do
        local w, h, x, y, files = piece:match("^(%d+):(%d+):(%d+):(%d+):(.+)$")
        if w and not seen[w .. ":" .. h .. ":" .. x .. ":" .. y] then
            local ids = {}
            for id in files:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
            Reveal.DrawPiece(tonumber(w), tonumber(h), tonumber(x), tonumber(y), ids, tw, th, dim)
        end
    end
end

local function build()
    local f, child = map()
    if not f then return false end
    frame = CreateFrame("Frame", nil, child)
    frame:SetAllPoints(child)
    frame:EnableMouse(false)
    Reveal.frame = frame
    frame:SetScript("OnShow", function() Reveal.Draw() end)
    DUI.On("OpenMapStitched", function() if frame:IsVisible() then Reveal.Draw() end end)
    -- A new map (zone picked, or up a level in the nav bar) changes the id.
    frame:SetScript("OnUpdate", function()
        if f.mapID ~= drawnFor then Reveal.Draw() end
    end)
    -- Map closed: draw nothing now; its OnShow redraws on open.
    frame:SetScript("OnEvent", function() if frame:IsVisible() then Reveal.Draw() end end)
    frame:RegisterEvent("MAP_EXPLORATION_UPDATED")
    return true
end

-- Waits for the map like a skin (retried as addons load) but in no pack, so it
-- works whether or not the map is skinned.
ns.Engine.Register({ key = "worldmap.reveal", apply = function()
    if frame then return end
    if not build() then return false end
    -- Off: hidden, so the per-frame map id check costs nothing.
    frame:SetShown(Reveal.On())
    Reveal.Draw()
end })

function Reveal.Start(c)
    cfg = c
    if frame then
        frame:SetShown(Reveal.On())
        Reveal.Draw()
    end
end
