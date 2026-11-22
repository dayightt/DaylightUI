local stub = require("stub")

local function login() return stub.Load({ module = true }) end

-- Revealed for the layout editor.

local shownSamples = stub.ShownCount

local function groupKeys(ns)
    return { { "unitframes.party", "Party" }, { "unitframes.raid", "Raid" }, { ns.Raid.SpotKey(20), "Raid" }, { ns.Raid.SpotKey(40), "Raid" } }
end

local function reveal(DUI, key, on) DUI.Fire("RevealFrame", key, on) end

-- The raid size a raid key's reveal shows: Raid 10's holder, or a size's own spot.
local function revealedRaidSize(ns, key)
    return ({ ["unitframes.raid"] = 10, [ns.Raid.SpotKey(20)] = 20, [ns.Raid.SpotKey(40)] = 40 })[key]
end

local function groupLook(ns, unit)
    return { samples = shownSamples(ns[unit].preview), headerAlpha = ns[unit].header:GetAlpha() }
end

local function outwardGroupState(DUI, ns, unit)
    local module, name = ns[unit], unit:lower()
    local holder, mover = module.holder, DUI.Movers.Get("unitframes." .. name)
    return { revealed = module.group.revealed, previewing = module.group:Previewing(), look = groupLook(ns, unit),
             headerShown = module.header:IsShown(), holderShown = holder:IsShown(),
             width = holder:GetWidth(), height = holder:GetHeight(), point = { holder:GetPoint(1) },
             placedAt = module.placedAt, moverSuspended = mover ~= nil and mover.suspended == true }
end

-- { name, previews once revealed, setup }
local GROUP_STARTS = {
    { "alone", true, function() end },
    { "in test mode", true, function(DUI) DUI.SetTestMode(true) end },
    { "after /dui test raid came and went", true, function(DUI)
        DUI.RunCommand("test raid")
        stub.RunTimers()
        DUI.RunCommand("test raid")
    end },
    { "switched off", false, function(DUI, unit) DUI:Set("UnitFrames", unit:lower() .. ".enabled", false) end },
}

-- Test mode's look, the raid shown at the size the key names.
local function testModeLookFor(ns, key, unit)
    local raidSize = revealedRaidSize(ns, key)
    if raidSize then
        ns.Raid.SetEditing(raidSize)
        stub.RunTimers()
        T.eq(groupLook(ns, "Raid").samples, raidSize, key .. ": test mode shows the raid at the edited size")
    end
    return groupLook(ns, unit)
end

T.test("revealed by any group key, even twice: test mode's preview at the key's raid size (none while off); one end leaves the group exactly as before", function()
    local testModeDUI, testModeNs = login()
    testModeDUI.SetTestMode(true)
    stub.RunTimers()
    local testModeLooks = {}
    for _, keyAndUnit in ipairs(groupKeys(testModeNs)) do
        testModeLooks[keyAndUnit[1]] = testModeLookFor(testModeNs, keyAndUnit[1], keyAndUnit[2])
    end
    for _, keyAndUnit in ipairs(groupKeys(testModeNs)) do
        local key, unit = keyAndUnit[1], keyAndUnit[2]
        local testModeLook = testModeLooks[key]
        T.truthy(testModeLook.samples > 0, unit .. ": test mode shows samples")
        for _, start in ipairs(GROUP_STARTS) do
            for reveals = 1, 2 do
                local DUI, ns = login()
                T.falsy(IsInGroup(), "solo")
                local label = string.format("%s, %s, revealed %dx", key, start[1], reveals)
                start[3](DUI, unit)
                stub.RunTimers()
                local before = outwardGroupState(DUI, ns, unit)
                for _ = 1, reveals do reveal(DUI, key, true) end
                if start[2] then
                    T.truthy(ns[unit].group:Previewing(), label .. ": previewing")
                    T.deq(groupLook(ns, unit), testModeLook, label .. ": test mode's preview")
                else
                    T.eq(shownSamples(ns[unit].preview), 0, label .. ": nothing previewed")
                end
                reveal(DUI, key, false)
                T.deq(outwardGroupState(DUI, ns, unit), before, label)
                DUI.SetTestMode(false)
            end
        end
    end
end)

T.test("revealed with Raid 40 on its own spot: the preview sits there, and ended, the raid is back on its own", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid40.ownSpot", true)
    stub.RunTimers()
    local before = outwardGroupState(DUI, ns, "Raid")
    T.isnil(before.placedAt, "alone: on Raid 10's spot")
    reveal(DUI, ns.Raid.SpotKey(40), true)
    T.eq(ns.Raid.placedAt, 40, "the forty-player preview on Raid 40's spot")
    T.truthy(DUI.Movers.Get("unitframes.raid").suspended, "the raid's own mover suspended meanwhile")
    reveal(DUI, ns.Raid.SpotKey(40), false)
    T.deq(outwardGroupState(DUI, ns, "Raid"), before)
end)

-- { the size with its own spot, the key revealed, where the preview sits }
local OWN_SPOT_REVEALS = {
    { 40, "unitframes.raid", nil },
    { 20, 20, 20 },
}

T.test("a raid key reveals its own size: Raid 10's holder stays on its spot, and Raid 20's spot shows the twenty-player preview there", function()
    for _, case in ipairs(OWN_SPOT_REVEALS) do
        local ownSpotSize, placedAt = case[1], case[3]
        local DUI, ns = login()
        local key = type(case[2]) == "number" and ns.Raid.SpotKey(case[2]) or case[2]
        local context = key .. " with Raid " .. ownSpotSize .. " on its own spot"
        DUI:Set("UnitFrames", "raid" .. ownSpotSize .. ".ownSpot", true)
        stub.RunTimers()
        local before = outwardGroupState(DUI, ns, "Raid")
        reveal(DUI, key, true)
        T.eq(ns.Raid.placedAt, placedAt, context .. ": where the preview sits")
        T.eq(groupLook(ns, "Raid").samples, revealedRaidSize(ns, key), context .. ": the key's raid size previewed")
        reveal(DUI, key, false)
        T.deq(outwardGroupState(DUI, ns, "Raid"), before, context .. ": ended, as before")
    end
end)

-- { group, its real frames showing: the group joined }
local REAL_GROUPS = {
    { "a party", "Party", function() stub.SetGroup(true, false, 3) end },
    { "a raid", "Raid", function() stub.SetGroup(true, true, 15) end },
}

T.test("in a party or raid whose own frames show, a reveal leaves the real frames up and shows no samples", function()
    for _, group in ipairs(REAL_GROUPS) do
        local unit = group[2]
        local DUI, ns = stub.Load({ module = true, before = group[3] })
        stub.FireEvent("GROUP_ROSTER_UPDATE")
        stub.RunTimers()
        local key = "unitframes." .. unit:lower()
        local before = outwardGroupState(DUI, ns, unit)
        T.eq(before.look.headerAlpha, 1, group[1] .. ": the real frames shown")
        reveal(DUI, key, true)
        T.falsy(ns[unit].group.revealed, group[1] .. ": not revealed")
        T.deq(groupLook(ns, unit), before.look, group[1] .. ": the header's alpha and the samples untouched")
        reveal(DUI, key, false)
        T.deq(outwardGroupState(DUI, ns, unit), before, group[1] .. ": ended, as before")
    end
end)

local function revealedLooks(ns, shownFor)
    local personal = ns.Personal.frame
    return { personal = { revealed = shownFor[ns.Personal.FADE], shown = personal:IsShown(), alpha = personal:GetAlpha() },
             Party = { revealed = ns.Party.group.revealed, look = groupLook(ns, "Party") },
             Raid = { revealed = ns.Raid.group.revealed, look = groupLook(ns, "Raid"), placedAt = ns.Raid.placedAt } }
end

T.test("the Personal Display, the party and the raid each answer only their own reveal keys", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "personal.enabled", true)
    local shownFor, show = {}, DUI.Fade.Show
    DUI.Fade.Show = function(key, why, on)
        shownFor[key] = on or nil
        return show(key, why, on)
    end
    local owners = { [ns.Personal.KEY] = "personal" }
    for _, keyAndUnit in ipairs(groupKeys(ns)) do owners[keyAndUnit[1]] = keyAndUnit[2] end
    local quiet = revealedLooks(ns, shownFor)
    for _, key in ipairs(stub.RevealKeys(ns)) do
        DUI.Fire("RevealFrame", key, true)
        local now = revealedLooks(ns, shownFor)
        for frame, look in pairs(now) do
            if owners[key] == frame then
                T.truthy(look.revealed, key .. " reveals the " .. frame)
            else
                T.deq(look, quiet[frame], key .. " leaves the " .. frame .. " alone")
            end
        end
        DUI.Fire("RevealFrame", key, false)
        T.deq(revealedLooks(ns, shownFor), quiet, key .. " ended")
    end
    DUI.Fade.Show = show
end)

-- Other changes that show or hide samples: { name, change, undo }
local function changeWidth(DUI, unit, by)
    local path = unit:lower() .. ".width"
    DUI:Set("UnitFrames", path, DUI:Get("UnitFrames", path) + by)
end
local GROUP_INTERRUPTIONS = {
    { "test mode", function(DUI) DUI.SetTestMode(true) end, function(DUI) DUI.SetTestMode(false) end },
    { "/dui test raid on, then off", function(DUI)
        DUI.RunCommand("test raid")
        stub.RunTimers()
        DUI.RunCommand("test raid")
    end, function() end },
    { "test part unticked", function(DUI, unit) DUI.SetTestPartShown(unit:lower(), false) end,
        function(DUI, unit) DUI.SetTestPartShown(unit:lower(), true) end },
    { "width changed", function(DUI, unit) changeWidth(DUI, unit, 20) end, function(DUI, unit) changeWidth(DUI, unit, -20) end },
    { "a fight ending test mode", function(DUI)
        DUI.SetTestMode(true)
        stub.RunTimers()
        stub.EnterCombat()
        T.falsy(DUI.testMode, "the fight ended test mode")
    end, function() stub.LeaveCombat() end },
}

T.test("while revealed, nothing else that shows or hides a group's samples undoes the reveal", function()
    local _, keysWorld = login()
    for _, keyAndUnit in ipairs(groupKeys(keysWorld)) do
        local key, unit = keyAndUnit[1], keyAndUnit[2]
        for _, interruption in ipairs(GROUP_INTERRUPTIONS) do
            local DUI, ns = login()
            local context = key .. ", " .. interruption[1]
            local before = outwardGroupState(DUI, ns, unit)
            reveal(DUI, key, true)
            local revealed = groupLook(ns, unit)
            T.truthy(revealed.samples > 0, context .. ": revealed")
            for step = 2, 3 do
                interruption[step](DUI, unit)
                stub.RunTimers()
                T.truthy(ns[unit].group.revealed, context .. ": still revealed")
                T.deq(groupLook(ns, unit), revealed, context .. ": the reveal's samples and header alpha kept")
            end
            reveal(DUI, key, false)
            T.deq(outwardGroupState(DUI, ns, unit), before, context .. ": the reveal ended, as before")
        end
    end
end)
