-- Rows: what the Auction House showed, one plain row per price key, shared
-- by the full scan (Game/Replicate.lua, Prices/Scan.lua) and targeted
-- searches (Game/Search.lua):
--   { key = "7429:-15", base = "7429", unit = lowest copper each, qty = how many }
--
--   local set = ns.Rows.New()
--   ns.Rows.Add(set, key, base, unit, qty)   -- set.list: the rows, in the order first seen
--   ns.Rows.Records(set.list) -> records, bases   -- what ns.Store.Record gets

local _, ns = ...

local Rows = {}
ns.Rows = Rows

function Rows.New()
    return { list = {}, byKey = {} }
end

-- Adds a sighting: the key's lowest unit and summed quantity. The unit is
-- floored to whole copper; a sighting under a copper each (it can't be
-- stored and would otherwise be the "lowest") or of no quantity is skipped.
-- Returns whether it counted.
function Rows.Add(set, key, base, unit, qty)
    if key == nil or type(unit) ~= "number" or type(qty) ~= "number" or qty <= 0 then return false end
    unit = math.floor(unit)
    if unit < 1 then return false end
    local row = set.byKey[key]
    if not row then
        row = { key = key, base = base or key, unit = unit, qty = 0 }
        set.byKey[key] = row
        set.list[#set.list + 1] = row
    elseif unit < row.unit then
        row.unit = unit
    end
    row.qty = row.qty + qty
    return true
end

-- What to record: each suffixed key with its own row, and each plain key
-- once with every row of that item (the cheapest of its own and its
-- suffixes', all of them counted). bases: plain key -> its record.
function Rows.Records(rows)
    local out, bases = {}, {}
    for _, row in ipairs(rows) do
        if row.key ~= row.base then out[#out + 1] = row end
        local b = bases[row.base]
        if not b then
            b = { key = row.base, unit = row.unit, qty = 0 }
            bases[row.base] = b
            out[#out + 1] = b
        elseif row.unit < b.unit then
            b.unit = row.unit
        end
        b.qty = b.qty + row.qty
    end
    return out, bases
end
