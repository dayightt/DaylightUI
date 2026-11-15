local stub = require("stub")

-- DaylightUI.API 1.4: nameplates hand plugins their pieces by name ("nameplate"),
-- painted after each recolor, never per health tick, with claimed pieces left to
-- the plugin (Plate.Owned). A plate's cast bar is its own kind, "platecast", with
-- the unit frames' cast bar pieces (Cast.Painted).

local function world()
    local frames = {}
    local function newPlate(i)
        local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
        np.UnitFrame = CreateFrame("Button", nil, np)
        np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
        np.UnitFrame.WidgetContainer = CreateFrame("Frame", nil, np.UnitFrame)
        np.UnitFrame.name = np.UnitFrame:CreateFontString(nil, "OVERLAY")
        function np:CanChangeHitTestPoints() return true end
        function np:SetAllHitTestPoints() end
        function np:SetHitTestPoints() end
        function np:ClearAllHitTestPoints() end
        function np:SetStackingBoundsFrame() end
        return np
    end
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        local i = tonumber(string.match(unit, "%d+"))
        if not i or not stub.units[unit] then return nil end
        frames[i] = frames[i] or newPlate(i)
        return frames[i]
    end }
    _G.issecure = function() return false end
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    _G.UnitReaction = function(u) local x = stub.units[u]; return x and x.reaction end
    _G.IsInInstance = function() return false end
    _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
    Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
    _G.C_TooltipInfo = { GetUnit = function() return nil end }
    stub.units = { player = { name = "Me", class = "PRIEST", isPlayer = true } }
end

local function load()
    stub.Load({ nameplates = true, before = world })
    stub.RunTimers()
    DaylightUI:Set("Nameplates", "healthColor", "class")
    stub.RunTimers()
    stub.units.nameplate1 = { name = "Searing Whelp", hostile = true, reaction = 2, level = 12,
        health = 60, maxHealth = 100, pct = 60 }
    return DaylightUI.API, stub.nameplates
end

local function show(ns, unit)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", unit or "nameplate1")
    stub.RunTimers()
    return ns.Manager.byUnit[unit or "nameplate1"]
end

local function cast(unit, spellID)
    stub.units[unit].cast = { name = "Fireball", texture = 1, notInterruptible = false, spellID = spellID or 133,
        duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", unit)
end

T.test("api plates: a plate's pieces by name, its cast bar a frame of its own", function()
    local API, ns = load()
    local p = show(ns)
    local parts = API.Parts(p)
    T.truthy(parts, "parts")
    T.eq(parts.health, p.health)
    T.eq(parts.healthFill, p.health:GetStatusBarTexture())
    T.eq(parts.healthBack, DaylightUI.Style.BarBack(p.health))
    T.eq(parts.name, p.name)
    T.eq(parts.guild, p.sub)
    T.eq(parts.level, p.level)
    T.eq(parts.dragon, p.dragon)
    T.eq(parts.cast, p.cast)
    T.eq(parts.powerFill, p.power.bar:GetStatusBarTexture())
    local seen
    for f, unit in API.Frames("platecast") do if f == p.cast then seen = unit end end
    T.eq(seen, "nameplate1", "the cast bar is listed with its plate's unit")
    local cp = API.Parts(p.cast)
    T.eq(cp.fill, p.cast.bar:GetStatusBarTexture())
    T.eq(cp.name, p.cast.text)
    T.eq(cp.time, p.cast.time)
    T.eq(cp.icon, p.cast.icon)
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    seen = nil
    for f in API.Frames("platecast") do if f == p.cast then seen = true end end
    T.isnil(seen, "gone with its plate")
end)

T.test("api plates: painted on a new unit and a recolor, not on health ticks", function()
    local API, ns = load()
    local n, units = 0, {}
    API.For("Neon").Paint("nameplate", function(f, parts, unit)
        n = n + 1
        units[#units + 1] = unit
    end)
    local p = show(ns)
    T.truthy(n >= 1, "painted when it came up")
    T.eq(units[#units], "nameplate1", "with its unit")
    local after = n
    for i = 1, 20 do
        stub.units.nameplate1.health = 60 - i
        stub.FireEvent("UNIT_HEALTH", "nameplate1")
    end
    stub.RunTimers()
    T.eq(n, after, "health ticks paint nothing")
    stub.units.nameplate1.reaction = 4
    stub.FireEvent("UNIT_FLAGS", "nameplate1")
    T.truthy(n > after, "a reaction change repaints")
    T.truthy(p, "plate")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: a plugin painting before the first plate paints it as it comes", function()
    local API, ns = load()
    local got
    API.For("Neon").Paint("nameplate", function(f) got = f end)
    local p = show(ns)
    T.eq(got, p)
end)

T.test("api plates: a claimed health fill keeps the plugin's color", function()
    local API, ns = load()
    DaylightUI:Set("Nameplates", "healthColor", "gradient")
    stub.RunTimers()
    local p = show(ns)
    API.For("Neon").Paint("nameplate", function(f, parts) parts.healthFill:SetVertexColor(1, 0, 1, 1) end,
        { owns = { "healthFill" } })
    for i = 1, 5 do
        stub.units.nameplate1.health = 60 - i * 10
        stub.FireEvent("UNIT_HEALTH", "nameplate1")
    end
    stub.units.nameplate1.reaction = 4
    stub.FireEvent("UNIT_FLAGS", "nameplate1")
    local v = p.health:GetStatusBarTexture().__vertex
    T.eq(v[1], 1); T.eq(v[2], 0); T.eq(v[3], 1)
end)

T.test("api plates: a claimed name and level keep their color", function()
    local API, ns = load()
    local p = show(ns)
    API.For("Neon").Paint("nameplate", function(f, parts)
        parts.name:SetTextColor(0, 1, 0)
        parts.level:SetTextColor(0, 0, 1)
    end, { owns = { "name", "level" } })
    DaylightUI:Set("Nameplates", "nameColor", "white")
    DaylightUI:Set("Nameplates", "levelColor", "white")
    stub.RunTimers()
    local r, g = p.name:GetTextColor()
    T.eq(r, 0); T.eq(g, 1)
    local _, _, b = p.level:GetTextColor()
    T.eq(b, 1)
    T.eq(p.name:GetText(), "Searing Whelp")
end)

T.test("api plates: letting go gives the plate its own look back at once", function()
    local API, ns = load()
    local p = show(ns)
    local h = API.For("Neon").Paint("nameplate", function(f, parts)
        parts.healthFill:SetVertexColor(1, 0, 1, 1)
        parts.name:SetTextColor(0, 1, 0)
    end, { owns = { "healthFill", "name" } })
    API.Off(h)
    -- The bar's own color again (SetStatusBarColor colors the fill in the client).
    local r, g, b = DaylightUI.Style.ReactionColor(2)
    local bc = p.health.__barColor
    T.eq(bc[1], r); T.eq(bc[2], g); T.eq(bc[3], b)
    local nr, ng = p.name:GetTextColor()
    T.eq(nr == 0 and ng == 1, false, "not the plugin's name color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: a plate's cast bar is painted after every cast and interrupt", function()
    local API, ns = load()
    local p = show(ns)
    local calls = {}
    API.For("Neon").Paint("platecast", function(f, parts, info) calls[#calls + 1] = info or false end)
    local start = #calls
    cast("nameplate1", 133)
    T.eq(#calls, start + 1)
    local info = calls[#calls]
    T.eq(info.unit, "nameplate1"); T.eq(info.spellID, 133); T.eq(info.channel, false)
    stub.units.nameplate1.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1")
    T.eq(calls[#calls].interrupted, true, "the interrupt is painted over too")
    T.truthy(p.cast:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: a claimed cast fill keeps the plugin's texture, the interrupt too", function()
    local API, ns = load()
    local p = show(ns)
    API.For("Neon").Paint("platecast", function(f, parts) parts.fill:SetTexture("Interface\\AddOns\\Neon\\rainbow") end,
        { owns = { "fill" } })
    for i = 1, 3 do
        cast("nameplate1", 100 + i)
        local fill = p.cast.bar:GetStatusBarTexture()
        T.eq(fill.__texture, "Interface\\AddOns\\Neon\\rainbow", "cast " .. i)
        T.eq(fill.__vertex[1], 1); T.eq(fill.__vertex[2], 1); T.eq(fill.__vertex[3], 1)
    end
    stub.units.nameplate1.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1")
    T.eq(p.cast.bar:GetStatusBarTexture().__vertex[2], 1, "no red over it")
end)

T.test("api plates: a secret cast flag in a restricted fight is handed on whole", function()
    local API, ns = load()
    show(ns)
    local got
    API.For("Neon").Paint("platecast", function(f, parts, info) if info then got = info end end)
    stub.EnterCombat()
    stub.SetRestriction("PvPMatch", true)
    local flag = stub.Secret(true)
    stub.units.nameplate1.cast = { name = "Fear", texture = 1, notInterruptible = flag, duration = stub.Duration(1.5) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.truthy(got, "painted")
    T.eq(got.notInterruptible, flag)
    stub.SetRestriction("PvPMatch", false)
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: the options preview is painted as a preview", function()
    local API, ns = load()
    local got = {}
    API.For("Neon").Paint("nameplate", function(f) got[f] = true end, { owns = { "healthFill" } })
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetSize(300, 200)
    local s = ns.Sample.New("plates", box)
    s.Refresh(300, 200)
    T.truthy(got[s.p], "the preview plate")
    T.eq(s.p.health:GetStatusBarTexture().__vertex[1], 1, "its fill left white for the plugin")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
