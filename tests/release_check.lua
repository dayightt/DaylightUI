-- What a returning player sees: every setting's value and where each nameplate
-- piece sits. tests/release_snapshot.lua writes these for a release into
-- tests/release_data.lua, and tests/test_release_moves.lua checks today's code
-- gives a player from that release the same, so nobody's setup moves on update.
local stub = require("stub")

local Check = {}

Check.MODULES = { module = true, actionbars = true, buffs = true, skins = true, bags = true,
    nameplates = true, tooltip = true, qol = true, chat = true, infopanel = true, quests = true }

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
Check.Copy = copy

-- The game's nameplates, enough to put one enemy plate on screen.
local function newPlate(i)
    local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
    np.UnitFrame = CreateFrame("Button", nil, np)
    np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
    np.UnitFrame.WidgetContainer = CreateFrame("Frame", nil, np.UnitFrame)
    np.UnitFrame.name = np.UnitFrame:CreateFontString(nil, "OVERLAY")
    function np:CanChangeHitTestPoints() return true end
    function np:SetAllHitTestPoints(f) self.__hit = f end
    function np:SetHitTestPoints() self.__hit = "the game's" end
    function np:ClearAllHitTestPoints() self.__hit = nil end
    function np:SetStackingBoundsFrame(f) self.__stack = f end
    return np
end

local function world()
    local plates = {}
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        local i = tonumber(string.match(unit, "%d+"))
        if not i or not stub.units[unit] then return nil end
        plates[i] = plates[i] or newPlate(i)
        return plates[i]
    end }
    _G.issecure = function() return false end
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    _G.UnitReaction = function(u) local x = stub.units[u]; return x and x.reaction end
    _G.IsInInstance = function() return false end
    stub.units = {
        player = { name = "Me", class = "PRIEST", isPlayer = true },
        nameplate1 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 },
    }
end

-- Logs in with every module, on saved data sv (nil: a brand new player).
function Check.Load(sv)
    local opts = copy(Check.MODULES)
    opts.before = function()
        world()
        if sv then _G.DaylightUIDB = copy(sv) end
    end
    local DUI = stub.Load(opts)
    stub.RunTimers()
    return DUI
end

-- The saved data a player has after one session with nothing changed. They
-- finished the setup guide, so the profile is kept: until then it's a stand-in
-- that's dropped at logout.
function Check.Saved()
    local DUI = Check.Load(nil)
    DUI.DB.Active().unsaved = nil
    stub.FireEvent("PLAYER_LOGOUT")
    return copy(_G.DaylightUIDB)
end

-- Every setting of the profile in use, flattened: "Module.a.b" (or "general.a.b")
-- -> value. Only settings with a default count: saved bookkeeping like an
-- upgrade counter changes with every new upgrade step.
function Check.Values(DUI)
    local out = {}
    local function walk(t, def, path)
        for k, v in pairs(t) do
            local d = nil
            if type(def) == "table" then d = def[k] end
            local p = path .. "." .. tostring(k)
            if type(v) == "table" then
                if type(d) == "table" then walk(v, d, p) end
            elseif d ~= nil and type(v) ~= "function" then
                out[p] = v
            end
        end
    end
    local p, defaults = DUI.DB.Active(), DUI.DB.Fill({})
    walk(p.general or {}, defaults.general, "general")
    for name, t in pairs(p.modules or {}) do walk(t, defaults.modules and defaults.modules[name], name) end
    return out
end

-- Where every nameplate piece sits: with the defaults, then each piece moved on
-- its own to each spot. "<case>|<region>" -> "POINT rel RELPOINT x y".
-- Every piece the enemy plate has in that release's code (your buffs' row is
-- the friendly plate's).
Check.SPOTS = { "above", "below", "outleft", "outright", "outtopleft", "outtopright", "outbottomleft",
                "outbottomright", "left", "right", "center" }

function Check.Plates(DUI)
    local NP = stub.nameplates
    local Plate = NP.Plate
    Check.PIECES = {}
    for piece, k in pairs(Plate.SPOT_KEYS) do
        if not k.friendly then Check.PIECES[#Check.PIECES + 1] = piece end
    end
    table.sort(Check.PIECES)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.RunTimers()
    local p = NP.Manager.byUnit.nameplate1
    local SINGLE = { marker = "marker", percent = "percent", level = "level", threatPct = "threatPct",
                     skull = "dotSkull", execIcon = "execIcon" }
    local function region(piece)
        if piece == "name" then return p.name end
        if piece == "quest" then return p.quest end
        if SINGLE[piece] then return p[SINGLE[piece]] end
        return p.auras and p.auras[piece]
    end
    local names = { [p.hp] = "bar", [p.questCount] = "questCount", [p.sub] = "sub" }
    for _, piece in ipairs(Check.PIECES) do
        local r = region(piece)
        if r then names[r] = piece end
    end
    local out = {}
    local function record(case)
        for _, piece in ipairs(Check.PIECES) do
            local r = region(piece)
            if r and r.GetPoint then
                local point, rel, relPoint, x, y = r:GetPoint(1)
                out[case .. "|" .. piece] = string.format("%s %s %s %g %g", tostring(point),
                    names[rel] or tostring(rel ~= nil), tostring(relPoint), stub.Plain(x) or 0, stub.Plain(y) or 0)
            end
        end
    end
    record("defaults")
    for _, piece in ipairs(Check.PIECES) do
        local key = Plate.SPOT_KEYS[piece].spot
        local was = DUI:Get("Nameplates", key)
        for _, spot in ipairs(Check.SPOTS) do
            DUI:Set("Nameplates", key, spot)
            stub.RunTimers()
            record(piece .. "@" .. spot)
        end
        DUI:Set("Nameplates", key, was)
        stub.RunTimers()
    end
    return out
end

-- Where every movable frame sits for a player who never moved it: its saved
-- spot, else its default. key -> "POINT rel RELPOINT x y". The keys are read
-- from Movers.Labels' own list, so this works on any release's code without a
-- new function there.
function Check.Frames(DUI)
    local M = DUI.Movers
    local order
    for i = 1, 10 do
        local name, v = debug.getupvalue(M.Labels, i)
        if not name then break end
        if name == "order" then order = v end
    end
    local saved = DUI.DB.Positions()
    local function relName(rel)
        if type(rel) == "table" and rel.GetName then return rel:GetName() or "a frame" end
        return tostring(rel or "UIParent")
    end
    local out = {}
    for _, key in ipairs(order or {}) do
        local at = saved[key]
        if at == nil then
            local e = M.Get(key)
            at = e and e.default
            if type(at) == "function" then at = at() end
        end
        if type(at) == "table" then
            local parts = {}
            for i = 1, #at do
                local v = at[i]
                parts[i] = type(v) == "number" and string.format("%.1f", v) or relName(v)
            end
            out[key] = table.concat(parts, " ")
        end
    end
    return out
end

-- A table as Lua source, keys sorted so a new release's file diffs cleanly.
function Check.Write(path, t)
    local lines = { "-- Written by tests/release_snapshot.lua. Don't edit by hand.", "return {" }
    local function quote(v)
        if type(v) == "string" then return string.format("%q", v) end
        return tostring(v)
    end
    local function dump(v, indent)
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local x = v[k]
            local key = "[" .. quote(k) .. "]"
            if type(x) == "table" then
                lines[#lines + 1] = indent .. key .. " = {"
                dump(x, indent .. "  ")
                lines[#lines + 1] = indent .. "},"
            elseif type(x) ~= "function" then
                lines[#lines + 1] = indent .. key .. " = " .. quote(x) .. ","
            end
        end
    end
    dump(t, "  ")
    lines[#lines + 1] = "}"
    local f = assert(io.open(path, "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
end

return Check
