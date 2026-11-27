local stub = require("stub")

-- Proc Alerts' engine (DaylightUI_Procs/Engine.lua): it reads the boosted
-- spell itself (usable, cast time, cost, cooldown), since buffs are hidden
-- from addons in a fight, and shows or hides each proc's flare.

local OVERPOWER, REVENGE, EXECUTE, VICTORY = 7384, 6572, 5308, 402927

local function load(class, known, before)
    stub.Load({ procs = true, before = function()
        stub.SpellReads()
        stub.SetUnits({ player = { name = "Me", class = class or "WARRIOR", isPlayer = true },
                        target = { name = "Mob", reaction = 2, health = 100, maxHealth = 100 } })
        for _, id in ipairs(known or {}) do stub.knownSpells[id] = true end
        if before then before() end
    end })
    return stub.procs
end

-- A moment passes: events handled, the poll runs.
local function step(dt)
    if dt then stub.Advance(dt) end
    stub.RunTimers()
    stub.RunTickers()
    stub.RunTimers()
end

local function usable(id, yes, short) stub.spellUsable[id] = { yes, short } end
local function cast(id) stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id) end

local function polling()
    for _, t in ipairs(stub.tickers) do
        if not t.cancelled and t.interval == 0.2 then return true end
    end
    return false
end

T.test("procs: a proc shows its flare in a fight and hides it when the spell is cast", function()
    local ns = load("WARRIOR", { OVERPOWER })
    stub.EnterCombat()
    step()
    T.falsy(ns.Flares.Shown("overpower"), "nothing until the game says usable")
    usable(OVERPOWER, true)
    stub.FireEvent("SPELL_UPDATE_USABLE")
    step()
    T.truthy(ns.Flares.Shown("overpower"))
    cast(OVERPOWER)
    step()
    T.falsy(ns.Flares.Shown("overpower"), "gone as it's cast")
    step(3)
    T.falsy(ns.Flares.Shown("overpower"), "held for its cooldown though the game still says usable")
    step(2.1)
    T.truthy(ns.Flares.Shown("overpower"), "back once the cooldown is over and it's still usable")
end)

T.test("procs: a 'no' shorter than 0.3 s does not hide the flare", function()
    local ns = load("WARRIOR", { OVERPOWER })
    stub.EnterCombat()
    usable(OVERPOWER, true)
    step()
    T.truthy(ns.Flares.Shown("overpower"))
    usable(OVERPOWER, false)
    step(0.1)
    T.truthy(ns.Flares.Shown("overpower"), "a moment's no is ignored")
    usable(OVERPOWER, true)
    step(0.1)
    T.truthy(ns.Flares.Shown("overpower"))
    usable(OVERPOWER, false)
    step(0.1)
    step(0.31)
    T.falsy(ns.Flares.Shown("overpower"), "a real no hides it")
end)

T.test("procs: usable but short of rage still counts for Overpower and Revenge, not for Execute", function()
    local ns = load("WARRIOR", { OVERPOWER, REVENGE, EXECUTE })
    stub.EnterCombat()
    usable(OVERPOWER, false, true)
    usable(REVENGE, false, true)
    usable(EXECUTE, false, true)
    step()
    T.truthy(ns.Flares.Shown("overpower"))
    T.truthy(ns.Flares.Shown("revenge"))
    T.falsy(ns.Flares.Shown("execute"), "Execute needs the rage now")
    usable(EXECUTE, true)
    step()
    T.truthy(ns.Flares.Shown("execute"))
end)

T.test("procs: Execute is not hidden by its own cast", function()
    local ns = load("WARRIOR", { EXECUTE })
    stub.EnterCombat()
    usable(EXECUTE, true)
    step()
    cast(EXECUTE)
    step()
    T.truthy(ns.Flares.Shown("execute"))
end)

T.test("procs: leaving combat hides combat-only flares and stops the ticker; entering again starts it", function()
    local ns = load("WARRIOR", { OVERPOWER, VICTORY })
    step()
    T.falsy(polling(), "idle out of combat")
    stub.EnterCombat()
    step()
    T.truthy(polling(), "polls in a fight")
    usable(OVERPOWER, true)
    usable(VICTORY, true)
    step()
    T.truthy(ns.Flares.Shown("overpower"))
    stub.LeaveCombat()
    usable(OVERPOWER, false)
    step()
    T.falsy(ns.Flares.Shown("overpower"), "combat only")
    T.truthy(ns.Flares.Shown("victoryrush"), "Victory Rush stays after the fight")
    T.truthy(polling(), "still polling while a flare is up")
    usable(VICTORY, false)
    step(0.5)
    step(0.5)
    T.falsy(ns.Flares.Shown("victoryrush"))
    T.falsy(polling(), "stopped once nothing is up")
    stub.EnterCombat()
    step()
    T.truthy(polling(), "starts again")
end)

T.test("procs: a secret cast time, cost or usable answer changes nothing and raises no error", function()
    local ns = load("WARRIOR", { OVERPOWER, EXECUTE })
    stub.EnterCombat()
    usable(OVERPOWER, true)
    step()
    T.truthy(ns.Flares.Shown("overpower"))
    stub.secretSpellReads = true
    usable(OVERPOWER, false)
    step(0.5)
    step()
    T.truthy(ns.Flares.Shown("overpower"), "a secret answer keeps the last one")
    T.falsy(ns.Flares.Shown("execute"))
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    stub.secretSpellReads = nil
    step(0.5)
    step(0.5)
    T.falsy(ns.Flares.Shown("overpower"))
end)

T.test("procs: only the player's class procs (and enabled gear) are watched", function()
    local ns = load("WARRIOR", { OVERPOWER })
    step()
    T.truthy(ns.Engine.Watched("overpower"), "a warrior's")
    T.falsy(ns.Engine.Watched("clearcasting"), "never a mage's")
    T.falsy(ns.Engine.Watched("edward"), "gear procs start off")
    ns.Alerts.Set("edward", "enabled", true)
    step()
    T.truthy(ns.Engine.Watched("edward"), "on once ticked")
end)

T.test("procs: a proc turned off never shows", function()
    local ns = load("WARRIOR", { OVERPOWER })
    ns.Alerts.Set("overpower", "enabled", false)
    stub.EnterCombat()
    usable(OVERPOWER, true)
    step()
    T.falsy(ns.Flares.Shown("overpower"))
    ns.Alerts.Set("overpower", "enabled", true)
    step()
    T.truthy(ns.Flares.Shown("overpower"))
end)

T.test("procs: a usable window ends after its length even while the game still says yes", function()
    local ns = load("WARRIOR", { OVERPOWER })
    stub.EnterCombat()
    usable(OVERPOWER, true)
    step()
    local f = ns.Flares.live.overpower
    T.near(f.info.left, 5, 0.01, "five seconds to use it")
    step(5.1)
    T.falsy(ns.Flares.Shown("overpower"), "its time is up")
end)

-- Cast time and cost --------------------------------------------------------

local SHADOWBOLT, SOULFIRE, FROSTBOLT, FIREBALL, MISSILES = 686, 6353, 116, 133, 5143
local LIGHTNING, CHAIN, NOVA, SMITE = 403, 421, 15237, 585

local function cost(id, n) stub.spellCosts[id] = { { cost = n } } end

T.test("procs: Shadow Bolt going instant shows Shadow Trance; its cast time coming back hides it", function()
    local ns = load("WARLOCK", { SHADOWBOLT })
    stub.EnterCombat()
    stub.castTimes[SHADOWBOLT] = 3000
    step()
    T.falsy(ns.Flares.Shown("trance"))
    stub.castTimes[SHADOWBOLT] = 0
    step(0.2)
    T.truthy(ns.Flares.Shown("trance"), "instant Shadow Bolt")
    stub.castTimes[SHADOWBOLT] = 3000
    step(0.2)
    T.falsy(ns.Flares.Shown("trance"), "back to its cast time")
end)

T.test("procs: instant needs a real cast time seen first", function()
    local ns = load("SHAMAN", { LIGHTNING })
    stub.EnterCombat()
    stub.castTimes[LIGHTNING] = 0
    step()
    step(0.2)
    T.falsy(ns.Flares.Shown("maelstrom"), "instant from the start is not a proc")
    stub.castTimes[LIGHTNING] = 2000
    step(0.2)
    stub.castTimes[LIGHTNING] = 0
    step(0.2)
    T.truthy(ns.Flares.Shown("maelstrom"))
end)

T.test("procs: haste on both spells is not a proc; the usual ratio is learned again after a talent change", function()
    local ns = load("WARLOCK", { SHADOWBOLT, SOULFIRE })
    stub.EnterCombat()
    stub.castTimes[SOULFIRE], stub.castTimes[SHADOWBOLT] = 4000, 3000
    step()
    stub.castTimes[SOULFIRE], stub.castTimes[SHADOWBOLT] = 2800, 2100
    step(0.2)
    T.falsy(ns.Flares.Shown("decimation"), "both 30% faster: haste")
    stub.castTimes[SOULFIRE], stub.castTimes[SHADOWBOLT] = 2400, 3000
    step(0.2)
    T.truthy(ns.Flares.Shown("decimation"), "Soul Fire alone faster")
    stub.castTimes[SOULFIRE], stub.castTimes[SHADOWBOLT] = 4000, 3000
    step(0.2)
    T.falsy(ns.Flares.Shown("decimation"))
    -- A talent makes Soul Fire faster for good: that's its new usual speed.
    stub.castTimes[SOULFIRE] = 2400
    stub.FireEvent("PLAYER_TALENT_UPDATE")
    step(0.2)
    step(0.2)
    T.falsy(ns.Flares.Shown("decimation"), "learned again, not a proc")
    stub.castTimes[SOULFIRE] = 1400
    step(0.2)
    T.truthy(ns.Flares.Shown("decimation"), "faster than the new usual")
end)

T.test("procs: a free spell shows Clearcasting; Missile Barrage does not show while Clearcasting explains it", function()
    local ns = load("MAGE", { FROSTBOLT, FIREBALL, MISSILES })
    stub.EnterCombat()
    cost(FROSTBOLT, 100); cost(FIREBALL, 120); cost(MISSILES, 200)
    step()
    cost(FROSTBOLT, 0); cost(FIREBALL, 0); cost(MISSILES, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("clearcasting"))
    T.falsy(ns.Flares.Shown("missilebarrage"), "Clearcasting explains the free Missiles")
    cost(FROSTBOLT, 100); cost(FIREBALL, 120)
    step(0.2)
    T.falsy(ns.Flares.Shown("clearcasting"))
    T.truthy(ns.Flares.Shown("missilebarrage"), "only Missiles free")
end)

-- A mage who turned the Clearcasting alert off still gets Clearcasting itself:
-- every free Arcane Missiles it gives must not light Missile Barrage.
T.test("procs: with the Clearcasting alert off, Clearcasting still never shows as Missile Barrage", function()
    local ns = load("MAGE", { FROSTBOLT, FIREBALL, MISSILES })
    ns.Alerts.Set("clearcasting", "enabled", false)
    stub.EnterCombat()
    cost(FROSTBOLT, 100); cost(FIREBALL, 120); cost(MISSILES, 200)
    step()
    cost(FROSTBOLT, 0); cost(FIREBALL, 0); cost(MISSILES, 0)
    stub.FireEvent("UNIT_AURA", "player")
    step(0.2)
    step(0.2)
    T.falsy(ns.Flares.Shown("clearcasting"), "its alert is off")
    T.falsy(ns.Flares.Shown("missilebarrage"), "Clearcasting explains the free Missiles")
    T.falsy(ns.Engine.Watched("clearcasting"), "not counted as an alert watched")
    -- Frostbolt spends Clearcasting; a real Missile Barrage after it still shows.
    cost(FROSTBOLT, 100); cost(FIREBALL, 120); cost(MISSILES, 200)
    step(0.2)
    cost(MISSILES, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("missilebarrage"), "only Missiles free")
end)

-- The client lists every cost a spell can have; one tied to an aura (a form,
-- a buff) applies only while the caster has that aura (hasRequiredAura).
T.test("procs: a cost tied to an aura the player lacks is not read as the spell's cost", function()
    local ns = load("MAGE", { FROSTBOLT, FIREBALL, MISSILES })
    stub.EnterCombat()
    cost(FROSTBOLT, 100); cost(FIREBALL, 120)
    local function missiles(barrage)
        stub.spellCosts[MISSILES] = {
            { cost = 0, requiredAuraID = 400589, hasRequiredAura = barrage },
            { cost = 200, requiredAuraID = 0, hasRequiredAura = false },
        }
    end
    missiles(false)
    step()
    step(0.2)
    T.falsy(ns.Flares.Shown("missilebarrage"), "the free cost needs a buff the player hasn't got")
    missiles(true)
    step(0.2)
    T.truthy(ns.Flares.Shown("missilebarrage"), "the buff is there: free")
    missiles(false)
    step(0.2)
    T.falsy(ns.Flares.Shown("missilebarrage"), "gone with the buff")
end)

-- Clearcasting frees every spell, Arcane Missiles too, so once it's up the cost
-- alone can't tell whether Missile Barrage is there. One already shown stays
-- until Arcane Missiles is cast (Missile Barrage pays for it before
-- Clearcasting) or its 15 s are over.
T.test("procs: Clearcasting landing while Missile Barrage is up keeps both flares", function()
    local ns = load("MAGE", { FROSTBOLT, FIREBALL, MISSILES })
    stub.EnterCombat()
    cost(FROSTBOLT, 100); cost(FIREBALL, 120); cost(MISSILES, 200)
    step()
    cost(MISSILES, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("missilebarrage"), "Missiles free alone")
    cost(FROSTBOLT, 0); cost(FIREBALL, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("clearcasting"), "Clearcasting lands")
    T.truthy(ns.Flares.Shown("missilebarrage"), "Missile Barrage stays")
    local mb, cc = ns.Flares.live.missilebarrage, ns.Flares.live.clearcasting
    T.truthy(mb.spot ~= cc.spot, "each at its own spot, both readable")
    -- Frostbolt spends Clearcasting: Missile Barrage is still there.
    cast(FROSTBOLT)
    cost(FROSTBOLT, 100); cost(FIREBALL, 120)
    step(0.2)
    T.falsy(ns.Flares.Shown("clearcasting"))
    T.truthy(ns.Flares.Shown("missilebarrage"), "still up after Clearcasting ends")
    cast(MISSILES)
    cost(MISSILES, 200)
    step(0.2)
    step(0.4)
    T.falsy(ns.Flares.Shown("missilebarrage"), "gone once Missiles is cast")
end)

T.test("procs: casting Missiles under both spends Missile Barrage and leaves Clearcasting", function()
    local ns = load("MAGE", { FROSTBOLT, FIREBALL, MISSILES })
    stub.EnterCombat()
    cost(FROSTBOLT, 100); cost(FIREBALL, 120); cost(MISSILES, 200)
    step()
    cost(MISSILES, 0)
    step(0.2)
    cost(FROSTBOLT, 0); cost(FIREBALL, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("missilebarrage") and ns.Flares.Shown("clearcasting"))
    cast(MISSILES)
    step(0.2)
    step(0.4)
    T.falsy(ns.Flares.Shown("missilebarrage"), "Missile Barrage paid for it")
    T.truthy(ns.Flares.Shown("clearcasting"), "Clearcasting stays, everything still free")
end)

T.test("procs: Missile Barrage kept under Clearcasting still ends after its 15 s", function()
    local ns = load("MAGE", { FROSTBOLT, FIREBALL, MISSILES })
    stub.EnterCombat()
    cost(FROSTBOLT, 100); cost(FIREBALL, 120); cost(MISSILES, 200)
    step()
    cost(MISSILES, 0)
    step(0.2)
    step(10)
    cost(FROSTBOLT, 0); cost(FIREBALL, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("missilebarrage"))
    step(5.2)
    T.falsy(ns.Flares.Shown("missilebarrage"), "its time is up, Clearcasting alone explains the free Missiles")
    T.truthy(ns.Flares.Shown("clearcasting"))
end)

T.test("procs: Elemental Focus ignores a Lightning Bolt that is instant", function()
    local ns = load("SHAMAN", { LIGHTNING, CHAIN })
    stub.EnterCombat()
    cost(LIGHTNING, 100); cost(CHAIN, 200)
    stub.castTimes[LIGHTNING], stub.castTimes[CHAIN] = 2000, 2000
    step()
    cost(LIGHTNING, 0)
    stub.castTimes[LIGHTNING] = 0
    step(0.2)
    T.falsy(ns.Flares.Shown("elemfocus"), "free and instant: Maelstrom's doing")
    T.truthy(ns.Flares.Shown("maelstrom"))
    cost(CHAIN, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("elemfocus"), "Chain Lightning free too")
end)

T.test("procs: Searing Light does not show when Smite is free too", function()
    local ns = load("PRIEST", { NOVA, SMITE })
    stub.EnterCombat()
    cost(NOVA, 100); cost(SMITE, 50)
    step()
    cost(NOVA, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("searinglight"))
    cost(SMITE, 0)
    step(0.2)
    T.falsy(ns.Flares.Shown("searinglight"), "every spell free: Inner Focus")
end)

T.test("procs: when the cost can no longer be read the flare ends after the proc's usual length", function()
    local ns = load("MAGE", { FROSTBOLT, FIREBALL })
    stub.EnterCombat()
    cost(FROSTBOLT, 100); cost(FIREBALL, 120)
    step()
    cost(FROSTBOLT, 0); cost(FIREBALL, 0)
    step(0.2)
    T.truthy(ns.Flares.Shown("clearcasting"))
    stub.secretSpellReads = true
    step(5)
    T.truthy(ns.Flares.Shown("clearcasting"), "kept while unreadable")
    step(11)
    T.falsy(ns.Flares.Shown("clearcasting"), "gone after its 15 s")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("procs: Maelstrom Weapon counts stacks from Lightning Bolt's cost, 20% a stack", function()
    local ns = load("SHAMAN", { LIGHTNING })
    ns.Alerts.Set("maelstrom", "fromStacks", 1)
    stub.EnterCombat()
    cost(LIGHTNING, 100)
    stub.castTimes[LIGHTNING] = 2000
    step()
    T.falsy(ns.Flares.Shown("maelstrom"))
    cost(LIGHTNING, 60)
    step(0.2)
    T.truthy(ns.Flares.Shown("maelstrom"))
    T.eq(ns.Flares.live.maelstrom.info.stacks, 2)
    cost(LIGHTNING, 0)
    stub.castTimes[LIGHTNING] = 0
    step(0.2)
    T.eq(ns.Flares.live.maelstrom.info.stacks, 5, "instant at the most")
end)

-- The game's own alert, resets and casts --------------------------------------

local STORMSTRIKE, ARCANEBLAST = 17364, 400574

local function overlay(id, on)
    if on then
        stub.FireEvent("SPELL_ACTIVATION_OVERLAY_SHOW", id, 449489, 0, 1, 255, 255, 255)
    else
        stub.FireEvent("SPELL_ACTIVATION_OVERLAY_HIDE", id)
    end
end

-- Fingers of Frost's picture is the client's aura frame (test_procs_aura); the
-- game's alert event still tells when it lands, so its sound plays from it, once,
-- and Daylight UI draws no second flare of its own.
T.test("procs: the game's alert for Fingers of Frost plays its sound and draws no second flare", function()
    for _, id in ipairs({ 400670, 400669, 400647, 44544 }) do
        local ns = load("MAGE")
        local played = {}
        local alert = DaylightUI.Sound.Alert
        DaylightUI.Sound.Alert = function(name) played[#played + 1] = name end
        stub.EnterCombat()
        step()
        overlay(id, true)
        step()
        T.eq(#played, 1, "its sound, spell " .. id)
        T.falsy(ns.Flares.Shown("fingers"), "no flare of Daylight UI's own: the client shows it")
        overlay(id, true)
        step()
        T.eq(#played, 1, "the same alert again plays nothing more")
        overlay(id, false)
        overlay(id, true)
        step()
        T.eq(#played, 2, "a new one after it ended")
        ns.Alerts.Set("fingers", "enabled", false)
        step()
        overlay(id, false)
        overlay(id, true)
        step()
        T.eq(#played, 2, "turned off: silent")
        DaylightUI.Sound.Alert = alert
    end
end)

T.test("procs: Shadow Trance shows from the game's alert OR an instant Shadow Bolt, once", function()
    local ns = load("WARLOCK", { SHADOWBOLT })
    local played = 0
    local real = DaylightUI.Sound.Alert
    DaylightUI.Sound.Alert = function() played = played + 1 end
    stub.EnterCombat()
    stub.castTimes[SHADOWBOLT] = 3000
    step()
    overlay(17941, true)
    step()
    T.truthy(ns.Flares.Shown("trance"), "the game's alert alone")
    stub.castTimes[SHADOWBOLT] = 0
    step(0.2)
    T.truthy(ns.Flares.Shown("trance"))
    T.eq(played, 1, "both signals: one flare, one sound")
    overlay(17941, false)
    step(0.2)
    T.truthy(ns.Flares.Shown("trance"), "still instant")
    stub.castTimes[SHADOWBOLT] = 3000
    step(0.2)
    T.falsy(ns.Flares.Shown("trance"))
    DaylightUI.Sound.Alert = real
end)

T.test("procs: a Stormstrike cooldown that ends early shows the reset flare; a normal 8 s one does not", function()
    local ns = load("SHAMAN", { STORMSTRIKE })
    stub.EnterCombat()
    step()
    -- A normal cooldown: on for 8 s.
    cast(STORMSTRIKE)
    stub.spellCooldowns[STORMSTRIKE] = true
    for _ = 1, 37 do step(0.2) end
    T.falsy(ns.Flares.Shown("stormstrike"), "still on its cooldown")
    stub.spellCooldowns[STORMSTRIKE] = nil
    step(0.2)
    step(0.2)
    T.falsy(ns.Flares.Shown("stormstrike"), "its usual end is not a reset")
    -- Reset after 2 s.
    cast(STORMSTRIKE)
    stub.spellCooldowns[STORMSTRIKE] = true
    step(0.5)
    stub.spellCooldowns[STORMSTRIKE] = nil
    step(0.2)
    T.falsy(ns.Flares.Shown("stormstrike"), "the first second is skipped")
    stub.spellCooldowns[STORMSTRIKE] = true
    step(1)
    stub.spellCooldowns[STORMSTRIKE] = nil
    step(0.2)
    T.truthy(ns.Flares.Shown("stormstrike"), "ended early: reset")
    cast(STORMSTRIKE)
    step()
    T.falsy(ns.Flares.Shown("stormstrike"), "used")
    -- Only the global cooldown left, told in SPELL_UPDATE_COOLDOWN.
    stub.spellCooldowns[STORMSTRIKE] = true
    step(1.5)
    stub.spellCooldowns[STORMSTRIKE] = "gcd"
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    step()
    T.truthy(ns.Flares.Shown("stormstrike"), "the global cooldown alone is a reset")
end)

T.test("procs: Arcane Blast counts a stack per cast up to 4 and clears 18 s after the first", function()
    local ns = load("MAGE", { ARCANEBLAST })
    stub.EnterCombat()
    step()
    for i = 1, 5 do
        cast(ARCANEBLAST)
        step(1)
        T.truthy(ns.Flares.Shown("arcaneblast"))
        T.eq(ns.Flares.live.arcaneblast.info.stacks, math.min(i, 4), "cast " .. i)
    end
    T.near(ns.Flares.live.arcaneblast.info.left, 13, 0.01, "its time runs from the first cast")
    step(13.1)
    T.falsy(ns.Flares.Shown("arcaneblast"), "gone 18 s after the first")
end)

T.test("procs: the module puts the game's alert setting back when it is turned off", function()
    local cvars = { displaySpellActivationOverlays = "1" }
    local function world()
        _G.GetCVar = function(k) return cvars[k] end
        _G.SetCVar = function(k, v) cvars[k] = tostring(v) end
    end
    local ns = load("WARLOCK", { SHADOWBOLT }, world)
    step()
    T.eq(cvars.displaySpellActivationOverlays, "0", "the game's art would double Shadow Trance's flare")
    DaylightUI:Set("Procs", "enabled", false)
    step()
    T.eq(cvars.displaySpellActivationOverlays, "1", "the player's own value back")
    DaylightUI:Set("Procs", "enabled", true)
    step()
    T.eq(cvars.displaySpellActivationOverlays, "0")
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(cvars.displaySpellActivationOverlays, "1", "back at logout, so turning the module off in the AddOns list leaves it right")
    -- A mage's Fingers of Frost has no other signal: the game's alert stays as the player set it.
    cvars.displaySpellActivationOverlays = "1"
    load("MAGE", nil, world)
    step()
    T.eq(cvars.displaySpellActivationOverlays, "1")
    cvars.displaySpellActivationOverlays = "0"
    load("WARLOCK", { SHADOWBOLT }, world)
    DaylightUI:Set("Procs", "enabled", false)
    step()
    T.eq(cvars.displaySpellActivationOverlays, "0", "a player who had it off keeps it off")
end)

local HOLYLIGHT, FLASHLIGHT = 635, 19750

T.test("procs: Infusion of Light shows when the proc comes with a spells-changed event", function()
    local ns = load("PALADIN", { HOLYLIGHT, FLASHLIGHT })
    stub.EnterCombat()
    stub.castTimes[HOLYLIGHT], stub.castTimes[FLASHLIGHT] = 2500, 1500
    step()
    step(0.2)
    T.falsy(ns.Flares.Shown("infusion"))
    -- The buff changes Holy Light's cast time, and the client also says the
    -- spells changed: the usual speed must not be forgotten for that.
    stub.castTimes[HOLYLIGHT] = 1500
    stub.FireEvent("SPELLS_CHANGED")
    step(0.2)
    step(0.2)
    T.truthy(ns.Flares.Shown("infusion"), "faster Holy Light")
    stub.castTimes[HOLYLIGHT] = 2500
    step(0.2)
    T.falsy(ns.Flares.Shown("infusion"), "used up")
end)

T.test("procs: with Only in combat off, Infusion of Light shows out of a fight when the buff lands", function()
    local ns = load("PALADIN", { HOLYLIGHT, FLASHLIGHT })
    ns.Alerts.Set("infusion", "combatOnly", false)
    stub.castTimes[HOLYLIGHT], stub.castTimes[FLASHLIGHT] = 2500, 1500
    step()
    T.falsy(polling(), "idle out of a fight")
    stub.castTimes[HOLYLIGHT] = 1500
    stub.FireEvent("UNIT_AURA", "player")
    step()
    T.truthy(ns.Flares.Shown("infusion"), "seen at once")
end)
