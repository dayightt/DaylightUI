-- Quick looks: one click sets where a frame's auras and name sit. A look names
-- a few settings and resets every other aura and name setting to its default,
-- so looks never stack. Keys like perLine and showDispel are only set by the
-- looks that name them.

local _, ns = ...
local DUI = DaylightUI

local Looks = {}
ns.Looks = Looks

Looks.ORDER = { "daylight", "healer", "dps", "battleground", "minimal" }
Looks.LABELS = { daylight = "DaylightUI", healer = "Healer", dps = "DPS / Tank", battleground = "Battleground",
                 minimal = "Minimal" }

Looks.KEYS = { "namePos" }
for _, def in ipairs(ns.AuraGroups.DEFS) do
    for _, field in ipairs(ns.AuraGroups.FIELDS) do
        Looks.KEYS[#Looks.KEYS + 1] = "auras." .. def.key .. "." .. field
    end
end

Looks.VALUES = {
    daylight = {},
    -- Your heals over time along the top; debuffs stay in their corner.
    healer = { ["auras.buffs.show"] = true, ["auras.buffs.which"] = "heals", ["auras.buffs.spot"] = "top",
               ["auras.buffs.grow"] = "center", ["auras.buffs.size"] = 12, ["auras.buffs.max"] = 3,
               ["showDispel"] = true },
    -- Only the debuffs that matter in a fight.
    dps = { ["auras.debuffs.which"] = "raid" },
    battleground = { ["auras.debuffs.show"] = false, ["auras.cc.size"] = 20, ["namePos"] = "outright",
                     ["perLine"] = 20 },
    minimal = { ["auras.debuffs.show"] = false, ["auras.cc.show"] = false, ["showDispel"] = true },
}

-- Only set by the looks that name them, but a look that leaves one out still
-- only matches at its default. Applying DaylightUI after Battleground keeps
-- 20 per line and reads as "custom".
Looks.NOTICE = { "perLine" }

-- A setting's shipped default (ns.DEFAULTS) by dotted key.
local function default(frame, key)
    local t = ns.DEFAULTS[frame]
    for part in string.gmatch(key, "[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

-- Writes every key straight into the settings, then sets the last one through
-- DUI:Set so the frames and options refresh once for the whole look.
-- Keys the look leaves out get their default written explicitly, since nil
-- would not read back as the default.
function Looks.Apply(look, frame)
    local values = Looks.VALUES[look]
    local db = ns.module and ns.module.db
    if not values or type(db) ~= "table" then return false end
    local list, done = {}, {}
    for _, key in ipairs(Looks.KEYS) do
        local v = values[key]
        if v == nil then v = default(frame, key) end
        list[#list + 1] = { key, v }
        done[key] = true
    end
    for key, v in pairs(values) do
        if not done[key] then list[#list + 1] = { key, v } end
    end
    for i = 1, #list - 1 do DUI.DB.SetPath(db, frame .. "." .. list[i][1], list[i][2]) end
    DUI:Set("UnitFrames", frame .. "." .. list[#list][1], list[#list][2])
    return true
end

-- The look the frame's settings match now, or "custom".
function Looks.Current(frame)
    for _, look in ipairs(Looks.ORDER) do
        local values, match = Looks.VALUES[look], true
        for _, key in ipairs(Looks.KEYS) do
            local want = values[key]
            if want == nil then want = default(frame, key) end
            if DUI:Get("UnitFrames", frame .. "." .. key) ~= want then match = false; break end
        end
        if match then
            for _, key in ipairs(Looks.NOTICE) do
                local want = values[key]
                if want == nil then want = default(frame, key) end
                if DUI:Get("UnitFrames", frame .. "." .. key) ~= want then match = false; break end
            end
        end
        if match then
            for key, v in pairs(values) do
                if DUI:Get("UnitFrames", frame .. "." .. key) ~= v then match = false; break end
            end
        end
        if match then return look end
    end
    return "custom"
end
