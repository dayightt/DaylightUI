-- Ruleset: which Auction House prices belong to. Forever has no realms for
-- trading: each ruleset (PvE, PvP, RP, RPvP, Hardcore) is one megaserver with
-- one cross-faction Auction House, and the game says which one you're on.
-- A client that still has realms gets one Auction House per realm.
--
--   ns.Ruleset.Key() -> "US-PvE" | "US-Realm Name" | nil while unknown
--   ns.On("RulesetChanged", function(key) end)

local _, ns = ...
local DUI = DaylightUI

local Ruleset = {}
ns.Ruleset = Ruleset

local REGIONS = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }

function Ruleset.Region()
    return REGIONS[GetCurrentRegion and GetCurrentRegion()] or "XX"
end

-- The ruleset the game says, nil when it can't (a client with realms, or one
-- missing the rules). The core works it out, as the alts' lists need it too.
function Ruleset.FromGame()
    return DUI.Alts.FromGame()
end

local function realm()
    local name = GetRealmName and GetRealmName()
    if type(name) == "string" and name ~= "" then return name end
end

local kept           -- the key, once worked out after login
local keeping = false

local function work()
    local kind = Ruleset.FromGame()
    if kind then return Ruleset.Region() .. "-" .. kind end
    -- Without realms, only the game's rules say which one: wait for them.
    if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then return nil end
    local name = realm()
    if name then return Ruleset.Region() .. "-" .. name end
end

-- Every price read asks (tooltips on each fill), so it's kept from login on.
function Ruleset.Key()
    if kept then return kept end
    local key = work()
    if keeping then kept = key end
    return key
end

ns.On("Login", function()
    kept = nil
    keeping = true
end)

local function recheck()
    if not keeping then return end
    local before = kept
    kept = nil
    local now = Ruleset.Key()
    if now ~= before then ns.Fire("RulesetChanged", now) end
end
ns.RegisterEvent("GAME_RULES_CHANGED", recheck)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", recheck)
