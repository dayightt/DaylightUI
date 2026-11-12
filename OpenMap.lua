-- OpenMap is another author's seamless world map (MIT, read-only API
-- OpenMapAPI). When it's installed and on, it becomes the world map and the
-- quest markers go on top of it:
--   * the quest highlight sits over its stitched art (OM.Level lifts frames
--     above the canvas art);
--   * things it already draws step aside while its map shows: dungeon,
--     flight and boat pins, unexplored areas, coordinates;
--   * it owns its window (moving and sizing the map), so the map mover and
--     grip stand down while it's loaded (OM.Loaded). The slim top row stays.
-- Other maps (dungeons, battlegrounds) are Blizzard's and behave as usual.
-- Lives in core because Quests and Skins both use it. Its callback is
-- re-fired as the DUI event "OpenMapStitched".

local _, DUI = ...

local OM = {
    ABOVE = 4, -- levels above its art: over Questie's lifted icons (+1), under OpenMap's own
}
DUI.OpenMap = OM

local function api()
    local a = _G.OpenMapAPI
    return type(a) == "table" and a or nil
end

local function num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end

local function ask(name, ...)
    local a = api()
    if not a or type(a[name]) ~= "function" then return nil end
    local ok, r1, r2, r3 = pcall(a[name], ...)
    if ok then return r1, r2, r3 end
end

-- OpenMap is loaded. It owns the map window then, whether stitched or not.
function OM.Loaded() return api() ~= nil end

-- The world map shows OpenMap's stitched map now.
function OM.Stitched() return ask("IsStitched") == true end

-- A canvas frame level for one of our frames at `level`. While the stitched
-- art shows it is raised `lift` levels over the art (default OM.ABOVE),
-- otherwise left as is.
function OM.Level(level, lift)
    if not OM.Stitched() then return level end
    local top = ask("ArtTopLevel")
    if not num(top) then return level end
    return math.max(level, top + (lift or OM.ABOVE))
end

-- Re-fire its callback as a DUI event once it's loaded (at login, after all
-- addons' files).
local hooked
function OM.Hook()
    local a = api()
    if hooked or not a or type(a.RegisterCallback) ~= "function" then return end
    hooked = true
    pcall(a.RegisterCallback, OM, "OpenMap_StitchedChanged", function(_, on) DUI.Fire("OpenMapStitched", on == true) end)
end

DUI.RegisterEvent("PLAYER_LOGIN", function() OM.Hook() end)
