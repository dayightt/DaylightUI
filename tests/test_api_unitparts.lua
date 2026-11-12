local stub = require("stub")

-- DaylightUI.API 1.3: unit frames and party/raid tiles hand plugins their pieces by
-- name, painted after each recolor and layout but never per health tick. A claimed
-- piece is left to the plugin (Colors.lua: UF.Owned).

local function tile(ns, group, i, unit)
    local h = group.header
    local b = CreateFrame("Button", "DaylightUI" .. (group == ns.Raid and "Raid" or "Party") .. "HeaderUnitButton" .. i, h)
    b:SetAttribute("unit", unit)
    stub.units[unit] = stub.units[unit] or { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    h.initialConfigFunction(h, b:GetName())
    return b
end

local function load()
    local DUI, ns = stub.Load({ module = true })
    return DUI, ns, DUI.API
end

T.test("api unit parts: the player frame's pieces by name", function()
    local _, ns, API = load()
    local f = ns.frames.player
    local p = API.Parts(f)
    T.truthy(p, "parts")
    T.eq(p.health, f.health)
    T.eq(p.healthFill, f.health:GetStatusBarTexture())
    T.eq(p.name, f.nameText)
    T.eq(p.power, f.power)
    T.eq(p.portrait, f.portrait)
    T.truthy(type(p.border) == "table", "the border's pieces")
end)

T.test("api unit parts: painted on a target swap, not on health ticks", function()
    local _, ns, API = load()
    local n = 0
    API.For("Neon").Paint("unit", function(f) if f == ns.frames.target then n = n + 1 end end)
    stub.units.target = { name = "Hogger", reaction = 2, health = 50, maxHealth = 100 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    local after = n
    T.truthy(after >= 1, "painted for the new target")
    for i = 1, 20 do
        stub.units.target.health = 50 - i
        stub.FireEvent("UNIT_HEALTH", "target")
    end
    stub.RunTimers()
    T.eq(n, after, "health ticks paint nothing")
end)

T.test("api unit parts: a claimed health fill keeps the plugin's color through health changes", function()
    local _, ns, API = load()
    ns.UF.colors.health = "gradient"
    stub.units.player = stub.units.player or { name = "Me", isPlayer = true, class = "WARRIOR", health = 100, maxHealth = 100 }
    local f = ns.frames.player
    local n = 0
    API.For("Neon").Paint("unit", function(fr, parts)
        if fr == f then n = n + 1 end
        parts.healthFill:SetVertexColor(1, 0, 1, 1)
    end, { owns = { "healthFill" } })
    local was = n
    for i = 1, 10 do
        stub.units.player.health = (stub.units.player.maxHealth or 100) - i
        stub.FireEvent("UNIT_HEALTH", "player")
    end
    stub.RunTimers()
    local v = f.health:GetStatusBarTexture().__vertex
    T.eq(v[1], 1); T.eq(v[2], 0); T.eq(v[3], 1)
    local bc = f.health.__barColor
    T.eq(bc[1], 1); T.eq(bc[2], 1); T.eq(bc[3], 1, "Daylight UI's bar color stays white under it")
    T.eq(n, was, "and no paint per tick")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api unit parts: raid tiles are painted when made and on a roster change, also in a fight", function()
    local _, ns, API = load()
    stub.SetGroup(true, true, 10)
    local seen = {}
    API.For("Neon").Paint("raid", function(f, parts, unit) seen[#seen + 1] = unit or false; parts.healthFill:SetVertexColor(0, 1, 1, 1) end)
    local b = tile(ns, ns.Raid, 1, "raid3")
    stub.RunTimers()
    T.truthy(#seen >= 1, "painted")
    stub.EnterCombat()
    local before = #seen
    stub.units.raid4 = { name = "Shallan", isPlayer = true, class = "MAGE", health = 5, maxHealth = 10 }
    b:SetAttribute("unit", "raid4")
    stub.RunTimers()
    T.truthy(#seen > before, "painted after the roster change")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api unit parts: giving the fill back paints the class color again", function()
    local _, ns, API = load()
    ns.UF.colors.health = "class"
    local f = ns.frames.player
    local h = API.For("Neon").Paint("unit", function(fr, parts) parts.healthFill:SetVertexColor(1, 0, 1, 1) end,
        { owns = { "healthFill" } })
    T.eq(f.health:GetStatusBarTexture().__vertex[2], 0)
    API.Off(h)
    local r, g, b = ns.UF.UnitColor("player")
    local c = f.health.__barColor
    T.eq(c[1], r); T.eq(c[2], g); T.eq(c[3], b)
end)
