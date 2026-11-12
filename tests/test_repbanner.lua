local stub = require("stub")

-- The reputation banner (QoL/RepBanner.lua): a standing gone up shows at the
-- top of the screen; a gain inside the same standing doesn't; it waits for
-- the level-up and plays after it.

local factions   -- factionID -> FactionData, as C_Reputation gives it
local order      -- the ids the faction list shows (a folded group's aren't in it)

local function faction(id, name, reaction, now, lo, hi)
    factions[id] = { factionID = id, name = name, reaction = reaction, currentStanding = now,
        currentReactionThreshold = lo, nextReactionThreshold = hi }
end

local function login(on)
    factions, order = {}, { 72, 47 }
    faction(72, "Stormwind", 5, 8000, 3000, 9000)
    faction(47, "Ironforge", 4, 100, 0, 3000)
    faction(54, "Gnomeregan", 5, 8900, 3000, 9000)   -- in a folded group
    stub.Load({ qol = true, before = function()
        _G.FACTION_STANDING_LABEL5 = "Friendly"
        _G.FACTION_STANDING_LABEL6 = "Honored"
        _G.FACTION_STANDING_INCREASED = "Your reputation with %s has increased by %d."
        -- The game's own bonus lines (Forever's GlobalStrings, enUS): a %.1f in them.
        _G.FACTION_STANDING_INCREASED_BONUS = "Reputation with %s increased by %d. (+%.1f Recruit A Friend bonus)"
        _G.FACTION_STANDING_INCREASED_DOUBLE_BONUS = "Reputation with %s increased by %d. (+%.1f Recruit A Friend bonus) (+%.1f bonus)"
        _G.FACTION_STANDING_INCREASED_ACH_BONUS = "Reputation with %s increased by %d. (+%.1f bonus)"
        _G.C_Reputation = {
            GetNumFactions = function() return #order end,
            GetFactionDataByIndex = function(i) return factions[order[i]] end,
            GetFactionDataByID = function(id) return factions[id] end,
        }
    end })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    if on ~= nil then DaylightUI:Set("QoL", "repBanner", on) end
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    return stub.qol.RepBanner
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 200 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 30)
    end
end

-- Lets the one-frame look run, without the banner's later steps.
local function nextFrame() stub.RunTimers() end

T.test("rep banner: a standing gone up shows, then goes away", function()
    login()
    faction(72, "Stormwind", 6, 9600, 9000, 21000)
    stub.FireEvent("FACTION_STANDING_CHANGED", 72, 9600)
    stub.RunTimers()
    local f = _G.DaylightUIRepBanner
    T.truthy(f and f:IsShown(), "shown")
    T.eq(f.standing:GetText(), "Honored")
    T.eq(f.faction:GetText(), "Stormwind")
    T.falsy(f:IsMouseEnabled(), "takes no clicks")
    settle()
    T.falsy(f:IsShown(), "gone after the hold")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rep banner: a gain inside the same standing shows nothing", function()
    login()
    faction(72, "Stormwind", 5, 8500, 3000, 9000)
    stub.FireEvent("UPDATE_FACTION")
    nextFrame()
    local f = _G.DaylightUIRepBanner
    T.falsy(f and f:IsShown(), "not shown")
end)

T.test("rep banner: a faction in a folded group shows when its gain crossed in", function()
    login()
    faction(54, "Gnomeregan", 6, 9100, 9000, 21000)
    stub.FireEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your reputation with Gnomeregan has increased by 200.")
    stub.FireEvent("FACTION_STANDING_CHANGED", 54, 9100)
    nextFrame()
    local f = _G.DaylightUIRepBanner
    T.truthy(f and f:IsShown(), "shown")
    T.eq(f.faction:GetText(), "Gnomeregan")
end)

T.test("rep banner: waits for a level-up and plays after it", function()
    login()
    stub.qol.LevelUp.Preview()
    faction(72, "Stormwind", 6, 9600, 9000, 21000)
    stub.FireEvent("FACTION_STANDING_CHANGED", 72, 9600)
    local f = _G.DaylightUIRepBanner
    T.truthy(_G.DaylightUILevelUp:IsShown(), "level-up up")
    stub.RunTimers()
    settle()
    -- The level-up's hold ran out and it hid: the banner played then.
    T.falsy(_G.DaylightUILevelUp:IsShown(), "level-up gone")
    f = _G.DaylightUIRepBanner
    T.truthy(f and f:IsShown(), "the banner plays once the top is free")
    T.eq(f.faction:GetText(), "Stormwind")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rep banner: a level-up sends it back to wait", function()
    local RB = login()
    RB.Preview()
    local f = _G.DaylightUIRepBanner
    T.truthy(f:IsShown(), "preview shows")
    stub.qol.LevelUp.Preview()
    settle()
    T.falsy(f:IsShown() and _G.DaylightUILevelUp:IsShown(), "never both at once")
end)

T.test("rep banner: switched off, nothing plays", function()
    login(false)
    faction(72, "Stormwind", 6, 9600, 9000, 21000)
    stub.FireEvent("FACTION_STANDING_CHANGED", 72, 9600)
    stub.FireEvent("UPDATE_FACTION")
    nextFrame()
    local f = _G.DaylightUIRepBanner
    T.falsy(f and f:IsShown(), "not shown")
end)

T.test("rep banner: the preview and /dui rep play it", function()
    login()
    DaylightUI.RunCommand("rep")
    T.truthy(_G.DaylightUIRepBanner:IsShown(), "the command plays it")
end)

T.test("rep banner: a gain line with a bonus (the game's %.1f) is read too", function()
    local RB = login()
    local name, n = RB.ParseGain("Reputation with Stormwind increased by 250. (+25.0 Recruit A Friend bonus)")
    T.eq(name, "Stormwind"); T.eq(n, 250)
    name, n = RB.ParseGain("Reputation with Ironforge increased by 100. (+10.0 Recruit A Friend bonus) (+5.5 bonus)")
    T.eq(name, "Ironforge"); T.eq(n, 100)
    name, n = RB.ParseGain("Reputation with Darnassus increased by 75. (+7.5 bonus)")
    T.eq(name, "Darnassus"); T.eq(n, 75)
    name, n = RB.ParseGain("Your reputation with Gnomeregan has increased by 200.")
    T.eq(name, "Gnomeregan"); T.eq(n, 200)
end)

-- The preview plays now, like the level-up's and the zone title's: with the
-- banner switched off and with the zone title up; and a sample sent back by
-- a level-up never plays again later.
T.test("rep banner: the preview plays at once, even switched off or under the zone title", function()
    local RB = login(false)
    RB.Preview()
    local f = _G.DaylightUIRepBanner
    T.truthy(f and f:IsShown(), "switched off, the preview still plays")
    stub.RunTimers()
    settle()
    T.falsy(f:IsShown())
    DaylightUI:Set("QoL", "repBanner", true)
    stub.qol.ZoneTitle.Preview()
    RB.Preview()
    T.truthy(f:IsShown(), "the zone title steps aside for it")
    stub.RunTimers()
    settle()
    T.falsy(f:IsShown() and _G.DaylightUIZoneTitle:IsShown(), "never both at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rep banner: a preview sent back by a level-up doesn't play again later", function()
    local RB = login()
    RB.Preview()
    local f = _G.DaylightUIRepBanner
    stub.qol.LevelUp.Preview()
    stub.RunTimers()
    settle()
    T.falsy(_G.DaylightUILevelUp:IsShown(), "level-up gone")
    T.falsy(f:IsShown(), "no stale sample after it")
end)

-- UPDATE_FACTION comes in bursts: a faction in the list and already known is
-- looked at once a scan, not twice.
T.test("rep banner: one scan looks at each faction once", function()
    login()
    local asks, get = {}, C_Reputation.GetFactionDataByID
    C_Reputation.GetFactionDataByID = function(id)
        asks[id] = (asks[id] or 0) + 1
        return get(id)
    end
    stub.FireEvent("UPDATE_FACTION")
    stub.RunTimers()
    T.eq(asks[72], 1, "listed and known")
    T.eq(asks[47], 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
