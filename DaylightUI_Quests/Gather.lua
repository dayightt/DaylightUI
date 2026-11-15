-- Gathering nodes from GatherMate2, when the player has it on (a separate addon,
-- never bundled), for the quest arrow. Read only, through its own public calls,
-- and every read goes through a pcall so a changed GatherMate gives nothing
-- instead of an error.
--
-- Which nodes count is GatherMate's own choice: the kinds it shows on the maps
-- (GatherMate2.Visible, from its Show setting per kind: always, with the
-- profession, while tracking) and the nodes its filter lets through
-- (FindNearbyNode skips the ones switched off in its filter). Its spots are
-- uiMapID coordinates in 0-1, the same the map and the arrow use.

local _, ns = ...

local Gather = {
    KEEP = 1.3,     -- a picked node stays picked until this many times the range away
}
ns.Gather = Gather

local function gm() return _G.GatherMate2 end

function Gather.Loaded()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(loaded) ~= "function" or loaded("GatherMate2") ~= true then return false end
    local G = gm()
    return type(G) == "table" and type(G.FindNearbyNode) == "function" and type(G.db_types) == "table"
end

local function search(map, px, py, w, h, range, keep, skip)
    local G = gm()
    local shown = G.Visible
    if type(shown) ~= "table" then return nil end
    -- GatherMate keeps a phased copy of a zone under the zone's own id.
    local zone = type(G.phasing) == "table" and G.phasing[map] or map
    local keepRange = range * Gather.KEEP
    local best, bestD, kept
    for _, kind in ipairs(G.db_types) do
        if shown[kind] == true then
            local passed = skip and skip[kind]
            -- Walked to the end every time: GatherMate reuses its iterator's table
            -- only once it runs out.
            for coord, id in G:FindNearbyNode(zone, px, py, kind, keepRange) do
                if not (passed and passed[coord]) then
                    local x, y = G:DecodeLoc(coord)
                    local dx, dy = (x - px) * w, (y - py) * h
                    local d = dx * dx + dy * dy
                    if keep and keep.kind == kind and keep.coord == coord then
                        kept = true
                    elseif d <= range * range and (not bestD or d < bestD) then
                        best, bestD = { map = map, x = x, y = y, kind = kind, coord = coord, id = id }, d
                    end
                end
            end
        end
    end
    if kept then return keep end
    if best and type(G.GetNameForNode) == "function" then
        local name = G:GetNameForNode(best.kind, best.id)
        best.name = type(name) == "string" and name or nil
    end
    return best
end

-- The nearest node GatherMate shows within `range` yards of the player (map
-- spot px, py on a map w by h yards): { map, x, y, kind, coord, id, name }, or
-- nil. `keep`, the node picked last time, is handed back while it's still there
-- and within KEEP times the range, so the arrow doesn't flip between two herbs.
-- `skip` = { [kind] = { [coord] = true } } leaves out the nodes already reached.
function Gather.Nearest(map, px, py, w, h, range, keep, skip)
    if not Gather.Loaded() then return nil end
    local ok, node = pcall(search, map, px, py, w, h, range, keep, skip)
    if ok then return node end
end
