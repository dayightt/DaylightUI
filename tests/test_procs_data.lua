local stub = require("stub")

-- Proc Alerts' proc table (DaylightUI_Procs/Data.lua).

local function load(class)
    stub.Load({ procs = true, before = function()
        stub.SpellReads()
        stub.SetUnits({ player = { name = "Me", class = class or "WARRIOR", isPlayer = true } })
    end })
    return stub.procs
end

T.test("procs data: every proc has a known mode, design and animation", function()
    local ns = load()
    for _, p in ipairs(ns.Data.PROCS) do
        T.truthy(ns.Data.MODES[p.mode], p.key .. " mode " .. tostring(p.mode))
        T.truthy(ns.Data.DESIGNS[p.design], p.key .. " design " .. tostring(p.design))
        T.truthy(ns.Data.ANIMS[p.anim], p.key .. " anim " .. tostring(p.anim))
        T.truthy(type(p.dur) == "number" and p.dur > 0, p.key .. " has a length")
    end
end)

T.test("procs data: no two procs of one class share a design", function()
    local ns = load()
    local seen = {}
    for _, p in ipairs(ns.Data.PROCS) do
        if p.class ~= "GEAR" then
            seen[p.class] = seen[p.class] or {}
            T.isnil(seen[p.class][p.design], p.class .. ": " .. p.key .. " and " .. tostring(seen[p.class][p.design]))
            seen[p.class][p.design] = p.key
        end
    end
end)

T.test("procs data: every key is unique", function()
    local ns = load()
    local seen = {}
    for _, p in ipairs(ns.Data.PROCS) do
        T.isnil(seen[p.key], p.key)
        seen[p.key] = true
    end
end)

T.test("procs data: every rank list is lowest rank first", function()
    local ns = load()
    for name, list in pairs(ns.Data.RANKS) do
        T.truthy(#list > 0, name)
    end
    T.eq(ns.Data.RANKS.overpower[1], 7384)
end)

T.test("procs data: every alert moves by default", function()
    local ns = load()
    for _, p in ipairs(ns.Data.PROCS) do
        T.truthy(p.anim ~= "still", p.key .. " moves")
    end
end)
