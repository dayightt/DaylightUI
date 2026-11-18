-- The level range of the zone under the mouse on the world map, after its name
-- ("Wetlands (20-30)"), colored by how hard it is for you. The game does the same
-- with C_Map.GetMapLevels, but that returns nothing on Forever, so the ranges are
-- kept here: classic zones by their usual ranges, Forever's own zones by the
-- levels of their quests.
--
-- The game writes the hovered zone's name into its area label only when it
-- changes. A script hook on the label reads that name back, and when it is a zone
-- below, writes the name again with the range added, colored the way the game's
-- own label colors it. Nothing else of the map is touched.

local _, ns = ...
local DUI = DaylightUI

local Levels = {}
ns.MapLevels = Levels

-- [uiMapID] = { lowest, highest }
Levels.ZONES = {
    -- Eastern Kingdoms
    [1426] = { 1, 10 },   -- Dun Morogh
    [1429] = { 1, 10 },   -- Elwynn Forest
    [1420] = { 1, 10 },   -- Tirisfal Glades
    [1432] = { 10, 20 },  -- Loch Modan
    [1421] = { 10, 20 },  -- Silverpine Forest
    [1436] = { 10, 20 },  -- Westfall
    [1433] = { 15, 25 },  -- Redridge Mountains
    [1431] = { 18, 30 },  -- Duskwood
    [1437] = { 20, 30 },  -- Wetlands
    [1424] = { 20, 35 },  -- Hillsbrad Foothills
    [1416] = { 30, 40 },  -- Alterac Mountains
    [1417] = { 30, 40 },  -- Arathi Highlands
    [1434] = { 30, 45 },  -- Stranglethorn Vale
    [1418] = { 35, 45 },  -- Badlands
    [1435] = { 35, 45 },  -- Swamp of Sorrows
    [1425] = { 40, 50 },  -- The Hinterlands
    [1427] = { 45, 50 },  -- Searing Gorge
    [1419] = { 45, 55 },  -- Blasted Lands
    [1428] = { 50, 58 },  -- Burning Steppes
    [1422] = { 51, 58 },  -- Western Plaguelands
    [1423] = { 53, 60 },  -- Eastern Plaguelands
    [1430] = { 55, 60 },  -- Deadwind Pass
    -- Kalimdor
    [1411] = { 1, 10 },   -- Durotar
    [1412] = { 1, 10 },   -- Mulgore
    [1438] = { 1, 10 },   -- Teldrassil
    [1439] = { 10, 20 },  -- Darkshore
    [1413] = { 10, 25 },  -- The Barrens
    [1442] = { 15, 27 },  -- Stonetalon Mountains
    [1440] = { 18, 30 },  -- Ashenvale
    [1441] = { 25, 35 },  -- Thousand Needles
    [1443] = { 30, 40 },  -- Desolace
    [1445] = { 35, 45 },  -- Dustwallow Marsh
    [1444] = { 40, 50 },  -- Feralas
    [1446] = { 40, 50 },  -- Tanaris
    [1447] = { 45, 55 },  -- Azshara
    [1448] = { 48, 55 },  -- Felwood
    [1449] = { 48, 55 },  -- Un'Goro Crater
    [1452] = { 53, 60 },  -- Winterspring
    [1450] = { 55, 60 },  -- Moonglade
    [1451] = { 55, 60 },  -- Silithus
    -- Added by Forever
    [2521] = { 1, 13 },   -- Zephras Isle
    [2548] = { 36, 45 },  -- Riverglades
    [2482] = { 56, 60 },  -- Mount Hyjal
}

local cfg, label
local byName       -- the game's (localized) zone name -> its range
local written      -- the text last written, so it's not done twice
local plainName    -- the game's own text before the range was added

function Levels.On() return cfg ~= nil and cfg.mapLevels ~= false end

local function names()
    if byName then return byName end
    byName = {}
    local info = C_Map and C_Map.GetMapInfo
    if type(info) ~= "function" then return byName end
    for id, range in pairs(Levels.ZONES) do
        local ok, m = pcall(info, id)
        if ok and type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
            byName[m.name] = range
        end
    end
    return byName
end

-- The game's own color for a zone at this level: red to green, yellow while
-- you're inside the range. A zone just below you isn't yellow any more.
function Levels.Color(low, high, level)
    local all = _G.QuestDifficultyColors
    local get = _G.GetQuestDifficultyColor
    local c
    if type(get) == "function" and level < low then
        c = get(low)
    elseif type(get) == "function" and level > high then
        c = get(high - 2)
    elseif type(all) == "table" then
        c = all.difficult
    end
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return DUI.Style.INK.LABEL
end

-- "Wetlands" -> "Wetlands (20-30)", or nil for a name with no range.
function Levels.Text(name, level)
    local range = type(name) == "string" and names()[name]
    if not range then return nil end
    local low, high = range[1], range[2]
    local span = low == high and tostring(high) or (low .. "-" .. high)
    local hex = DUI.Win.Parts.Hex(Levels.Color(low, high, level or UnitLevel("player") or 1))
    return name .. hex .. " (" .. span .. ")|r"
end

local stale -- a level up or a switch: write the name shown again

local function update()
    local fs = label and label.Name
    if type(fs) ~= "table" then return end
    local now = fs:GetText()
    if now == written and not stale then return end
    stale = false
    local name = (now == written) and plainName or now
    local text = Levels.On() and Levels.Text(name) or nil
    if not text then
        -- Off, or a name without a range: the game's own name, as it wrote it.
        if now == written and plainName then fs:SetText(plainName) end
        written, plainName = nil, nil
        return
    end
    plainName, written = name, text
    if text ~= now then fs:SetText(text) end
end

-- The map's area label belongs to one of its data providers.
local function findLabel()
    local f = _G.WorldMapFrame
    local list = type(f) == "table" and f.dataProviders
    if type(list) ~= "table" then return nil end
    for provider in pairs(list) do
        local l = type(provider) == "table" and provider.Label
        if type(l) == "table" and type(l.Name) == "table" and l.HookScript then return l end
    end
end

ns.Engine.Register({ key = "worldmap.levels", apply = function()
    if label then return end
    label = findLabel()
    if not label then return false end
    label:HookScript("OnUpdate", update)
    -- A level up recolors the range under the mouse.
    DUI.RegisterEvent("PLAYER_LEVEL_UP", function() stale = true end)
end })

function Levels.Start(c)
    cfg = c
    stale = true
    -- The label only runs while the map is shown; switched off with it shut,
    -- the name is put back here.
    if label and not Levels.On() then update() end
end
