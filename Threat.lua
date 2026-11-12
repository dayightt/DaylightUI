-- Threat for every module that shows it (unit frames, nameplates, the threat
-- meter): where you stand on a mob and whether you're the tank. Only plain
-- answers are read here. Against a boss the numbers can be secret (drawable,
-- never comparable), and then these return nothing and callers draw the
-- secret values directly.
--
-- UnitThreatSituation: 0 not tanking, below the tank. 1 not tanking, above the
-- tank (about to pull). 2 tanking but someone else is higher (losing it).
-- 3 tanking securely. UnitDetailedThreatSituation adds the scaled percent
-- (100 means it turns on you, which is 110% of the tank's threat in melee and
-- 130% at range), the raw percent of the tank's threat, and the threat value.

local _, DUI = ...

local Threat = {}
DUI.Threat = Threat

-- Scaled percent where you're close to pulling (orange) while still below the
-- tank, leaving room to stop before 100.
Threat.WARN_PCT = 80
-- The pull threshold as a share of the tank's threat when the game hasn't
-- given one (you have no threat yet). Uses melee's, the lower of the two.
Threat.PULL = 1.1

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A plain number, or nil if missing, refused or secret.
local function number(v)
    if type(v) ~= "number" or isSecret(v) then return nil end
    return v
end
Threat.Number = number

-- Whether the game will hide unit's threat numbers (or state) on mob. Asks
-- the predicate first as the game's docs advise, otherwise checks the answers.
function Threat.ValuesSecret(unit, mob)
    local S = C_Secrets
    if type(S) == "table" and type(S.ShouldUnitThreatValuesBeSecret) == "function" then
        local ok, v = pcall(S.ShouldUnitThreatValuesBeSecret, unit, mob)
        if ok and not isSecret(v) then return v == true end
    end
    return false
end

-- Your (or unit's) standing on mob from the plain answers: "aggro" (it's on
-- you), "warn" (close to pulling), "safe" (on its list, well below), or nil
-- (not on its list, or the game won't say). Returns the status second.
function Threat.Level(unit, mob)
    if type(UnitThreatSituation) ~= "function" then return nil end
    local ok, status = pcall(UnitThreatSituation, unit, mob)
    status = ok and number(status) or nil
    if not status then return nil end
    if status >= 2 then return "aggro", status end
    if status == 1 then return "warn", status end
    if type(UnitDetailedThreatSituation) == "function" then
        local ok2, _, _, scaled = pcall(UnitDetailedThreatSituation, unit, mob)
        scaled = ok2 and number(scaled) or nil
        if scaled and scaled >= Threat.WARN_PCT then return "warn", status end
    end
    return "safe", status
end

-- Whether someone else could hold a mob: you're grouped or have a pet. Solo,
-- every mob is on you, so there's nothing worth showing.
function Threat.Shared()
    return IsInGroup() == true or UnitExists("pet") == true
end

-- Whether you're the tank: your assigned role, else your talents'. Asked on
-- every threat event, so it's cached and refreshed when role or talents may
-- have changed, and at the start of each fight.
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v
end

local function readTank()
    if plain(UnitGroupRolesAssigned, "player") == "TANK" then return true end
    if GetSpecialization and GetSpecializationRole then
        local spec = plain(GetSpecialization)
        if spec then return plain(GetSpecializationRole, spec) == "TANK" end
    end
    return false
end

local tankCache
function Threat.IsTank()
    if tankCache == nil then tankCache = readTank() end
    return tankCache
end
function Threat.Forget() tankCache = nil end
for _, e in ipairs({ "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
                     "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
    pcall(DUI.RegisterEvent, e, Threat.Forget)
end
