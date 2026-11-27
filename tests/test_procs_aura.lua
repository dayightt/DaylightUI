local stub = require("stub")

-- Proc Alerts' game-shown flares (DaylightUI_Procs/Game.lua): a buff-only proc
-- (nothing an addon can read changes) is handed to the client's aura
-- container, which shows its flare while the buff is up, in a fight too.

local HAMMER = 24275

local function load(class, before)
    stub.Load({ procs = true, before = function()
        stub.SpellReads()
        stub.SetUnits({ player = { name = "Me", class = class or "PALADIN", isPlayer = true },
                        target = { name = "Mob", reaction = 2, health = 100, maxHealth = 100 } })
        if before then before() end
    end })
    stub.RunTimers()
    return stub.procs
end

local function inside(region, owner)
    local p = region:GetParent()
    while p do
        if p == owner then return true end
        p = p:GetParent()
    end
    return false
end

local function enabledSlots(ns, key)
    local out = {}
    for n, s in pairs(ns.Game.slots[key] or {}) do
        if s.enabled then out[#out + 1] = n end
    end
    table.sort(out)
    return out
end

T.test("procs aura: a buff-only proc gets a game-shown flare built inside the aura button", function()
    local ns = load()
    local c = _G.DaylightUIProcsAuras
    T.truthy(c, "one container for the module")
    local slot = ns.Game.slots.redoubt[1]
    T.truthy(slot and slot.button, "Redoubt has a slot")
    local part = slot.parts[1]
    T.truthy(inside(part.tex, slot.button), "its light is inside the button")
    T.truthy(inside(part.core, slot.button))
    T.truthy(string.find(part.tex:GetTexture(), "flare%-ring%.png$"), "its design")
    T.truthy(part.tex.__gradient, "tinted with its colors")
    T.near(part.frame:GetWidth(), 304, 0.01, "sized from the mock-up's numbers")
    local _, _, _, _, y = part.frame:GetPoint(1)
    T.near(y, -118, 0.01)
    T.eq(c.__slots["DaylightUIProcs_redoubt_1"].filter, "HELPFUL")
    T.deq(c.__slots["DaylightUIProcs_redoubt_1"].opts.candidateFilters.includeSpellIDs,
        { [20128] = true, [20131] = true, [20132] = true, [20133] = true, [20134] = true })
    -- Its lane is held, since Daylight UI can't see when the game shows it.
    local held = {}
    for _, k in pairs(ns.Flares.lanes.side or {}) do held[k] = true end
    T.truthy(held.vengeance and held.reckoning and held.sealecho, "every game-shown side flare holds a lane")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

-- The client's includeSpellIDs is a map of id -> true (Blizzard_AuraContainerUtil
-- DoesAuraPassCandidateFilters reads includeSpellIDs[auraData.spellId]); a plain
-- list of ids matches no real buff, so no game-shown flare could ever come up.
T.test("procs aura: every buff a game-shown proc lists passes its slot's filter, by the client's rule", function()
    local shows = require("aura_rules")
    local you = { groupMember = true, canAssist = true }
    for _, class in ipairs({ "PALADIN", "DRUID", "PRIEST", "ROGUE", "HUNTER" }) do
        local ns = load(class)
        local c = _G.DaylightUIProcsAuras
        for _, p in ipairs(ns.Data.Mine()) do
            if p.mode == "aura" and #(p.buffIds or {}) > 0 then
                for n = 1, p.stacks or 1 do
                    local slot = c.__slots[string.format("DaylightUIProcs_%s_%d", p.key, n)]
                    T.truthy(slot, p.key .. " slot " .. n)
                    for _, id in ipairs(p.buffIds) do
                        T.truthy(shows(slot, you, { spellId = id }), p.key .. " shows on buff " .. id)
                    end
                    T.falsy(shows(slot, you, { spellId = 1 }), p.key .. " ignores other buffs")
                end
            end
        end
    end
end)

-- Unsealed Wrath stores an Echo of the seal that's up (the client's Cooldown
-- Manager catalogue links these six to it; Seal of the Crusader has none).
T.test("procs aura: Unsealed Wrath watches every seal's Echo", function()
    local ns = load()
    local want = { 1311701, 1311703, 1311704, 1311705, 1328198, 1328206 }
    local got = {}
    for _, id in ipairs(ns.Data.BY.sealecho.buffIds) do got[#got + 1] = id end
    table.sort(got)
    T.deq(got, want)
end)

T.test("procs aura: the flare's loop is added as the button's shown animation", function()
    local ns = load()
    local slot = ns.Game.slots.redoubt[1]
    local btn = slot.button
    T.truthy(btn.__shownAnims and #btn.__shownAnims > 0, "handed to the client")
    stub.EnterCombat()
    stub.AuraVisible(btn, true)
    T.truthy(slot.parts[1].breathe:IsPlaying(), "Redoubt breathes while its buff is up, in a fight too")
    stub.AuraVisible(btn, false)
    T.falsy(slot.parts[1].breathe:IsPlaying())
    T.eq(stub.lockErrors, 0)
end)

T.test("procs aura: a stacking proc gets one bar per stack count from Show from up", function()
    local ns = load()
    T.deq(enabledSlots(ns, "vengeance"), {}, "Only in combat: off between fights")
    stub.EnterCombat()
    T.deq(enabledSlots(ns, "vengeance"), { 5 }, "from its most by default")
    local s5 = ns.Game.slots.vengeance[5]
    T.truthy(s5.bar, "a bar the client shows at 5 stacks or more")
    T.eq(s5.button.__appBarOpts.minApplications, 5)
    T.truthy(inside(s5.parts[1].tex, s5.bar), "the light lives in the bar, so it shows with it")
    ns.Alerts.Set("vengeance", "fromStacks", 3)
    stub.RunTimers()
    T.deq(enabledSlots(ns, "vengeance"), { 3, 4, 5 })
    stub.AuraVisible(s5.button, true, 4)
    T.falsy(s5.bar:IsShown(), "4 stacks: the 5 bar stays down")
    stub.AuraVisible(ns.Game.slots.vengeance[3].button, true, 4)
    T.truthy(ns.Game.slots.vengeance[3].bar:IsShown(), "the 3 bar is up")
end)

T.test("procs aura: a design change under restrictions waits for AfterRestrictions and raises no error", function()
    local ns = load()
    stub.SetRestriction("PvPMatch", true)
    ns.Alerts.Set("redoubt", "design", "wave")
    ns.Alerts.Set("redoubt", "size", 1.5)
    stub.RunTimers()
    local part = ns.Game.slots.redoubt[1].parts[1]
    T.eq(stub.lockErrors, 0, "nothing touched the locked button")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.truthy(string.find(part.tex:GetTexture(), "flare%-wave%.png$"), "restyled once the match is over")
    T.near(part.frame:GetWidth(), 304 * 1.5, 0.01)
end)

T.test("procs aura: no container leaves the other procs working and reports once", function()
    local ns = load("PALADIN", function() stub.noAuraContainer = true end)
    stub.knownSpells[HAMMER] = true
    stub.FireEvent("SPELLS_CHANGED")
    stub.EnterCombat()
    stub.spellUsable[HAMMER] = { true, false }
    stub.RunTimers()
    stub.RunTickers()
    stub.RunTimers()
    T.truthy(ns.Flares.Shown("hammer"), "Hammer of Wrath still shows")
    local n = 0
    for _, line in ipairs(stub.chat) do
        if string.find(tostring(line), "aura container", 1, true) then n = n + 1 end
    end
    T.eq(n, 1, "one line in chat")
    stub.noAuraContainer = nil
end)

-- Fingers of Frost's only signal was the game's alert event, and players saw no
-- flare from it (in a fight too). The client's aura frame shows it from its buff
-- instead (both of Forever's ids), as the reference addon does.
T.test("procs aura: Fingers of Frost is shown by the client from its buff, so a missed alert can't lose it", function()
    local ns = load("MAGE")
    local slot = ns.Game.slots.fingers and ns.Game.slots.fingers[1]
    T.truthy(slot and slot.button, "Fingers of Frost has a game-shown slot")
    local c = _G.DaylightUIProcsAuras
    T.deq(c.__slots["DaylightUIProcs_fingers_1"].opts.candidateFilters.includeSpellIDs,
        { [400670] = true, [400669] = true })
    stub.EnterCombat()
    T.deq(enabledSlots(ns, "fingers"), { 1 }, "on in a fight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("procs aura: these procs default to no sound", function()
    local ns = load()
    for _, p in ipairs(ns.Data.PROCS) do
        if p.mode == "aura" and not p.overlayIds then T.eq(ns.Alerts.Get(p.key, "sound"), "none", p.key) end
    end
end)

T.test("procs aura: turning an alert or the module off switches its slot off", function()
    local ns = load()
    stub.EnterCombat()
    T.deq(enabledSlots(ns, "redoubt"), { 1 })
    ns.Alerts.Set("redoubt", "enabled", false)
    stub.RunTimers()
    T.deq(enabledSlots(ns, "redoubt"), {})
    ns.Alerts.Set("redoubt", "enabled", true)
    T.deq(enabledSlots(ns, "redoubt"), { 1 })
    DaylightUI:Set("Procs", "enabled", false)
    stub.RunTimers()
    T.deq(enabledSlots(ns, "redoubt"), {})
    DaylightUI:Set("Procs", "enabled", true)
    ns.Alerts.Set("redoubt", "combatOnly", false)
    stub.LeaveCombat()
    T.deq(enabledSlots(ns, "redoubt"), { 1 }, "Only in combat off: between fights too")
end)

T.test("procs aura: a game-shown alert takes its Animation speed once nothing locks it", function()
    local ns = load()
    local slot = ns.Game.slots.redoubt[1]
    stub.EnterCombat()
    ns.Alerts.Set("redoubt", "speed", 2)
    T.eq(slot.parts[1].speed, 1, "waits while the button is locked")
    stub.LeaveCombat()
    T.eq(slot.parts[1].speed, 2)
    -- The breathing (the flicker also runs at half speed on Breathe).
    local t
    for _, x in ipairs(slot.parts[1].times) do if x[5] ~= "live" then t = x; break end end
    T.near(t[1]:GetDuration(), t[2] / 2, 0.0001)
    T.eq(stub.lockErrors, 0)
end)

-- Moving game-shown flares: the client plays what it was handed while the buff
-- is up. Daylight UI never learns when it shows or hides, so no strike, no burn.
local function has(list, g)
    for _, x in ipairs(list or {}) do if x == g then return true end end
    return false
end

T.test("procs aura: a game-shown flare hands the client its loops and its sparks", function()
    local own = { strike = {}, breathe = { "breathe" }, pulse = { "beat" }, impact = { "wave" }, flash = { "gleam" } }
    for _, anim in ipairs({ "strike", "breathe", "pulse", "impact", "flash" }) do
        local ns = load()
        ns.Alerts.Set("sealecho", "anim", anim)
        stub.RunTimers()
        local slot = ns.Game.slots.sealecho[1]
        local btn = slot.button
        local shown = btn.__shownAnims
        for i = 1, 2 do
            local part = slot.parts[i]
            T.truthy(has(shown, part.live), anim .. ": piece " .. i .. "'s flicker")
            T.truthy(has(shown, part.embers), anim .. ": piece " .. i .. "'s embers")
            for _, name in ipairs(own[anim]) do T.truthy(has(shown, part[name]), anim .. ": its " .. name) end
            T.truthy(inside(part.liveTex, btn), anim .. ": the sheet is inside the client's button")
            T.truthy(inside(part.emberTex, btn))
            T.truthy(part.liveTex:IsShown() and part.emberTex:IsShown(), anim .. ": shown with the button")
            T.falsy(part.burnTex:IsShown(), anim .. ": no burn")
            T.falsy(part.frontFrame:IsShown(), anim .. ": no strike front")
            T.near(part.liveFrame:GetWidth(), 1.2 * 256, 0.5, anim .. ": whole")
        end
        T.truthy(slot.burst and has(shown, slot.burst.group), anim .. ": the sparks as it comes up")
        T.truthy(inside(slot.burst.left, btn))
        T.eq(slot.reveal, 1)
        T.eq(stub.lockErrors, 0)
        T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    end
end)

T.test("procs aura: a game-shown flare changed in a PvP match waits for the match to end", function()
    local ns = load()
    ns.Alerts.Set("sealecho", "anim", "pulse")
    stub.RunTimers()
    local slot = ns.Game.slots.sealecho[1]
    local part = slot.parts[1]
    stub.SetRestriction("PvPMatch", true)
    ns.Alerts.Set("sealecho", "anim", "flash")
    ns.Alerts.Set("sealecho", "design", "flames")
    stub.RunTimers()
    T.eq(stub.lockErrors, 0, "nothing touched the locked button")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    T.truthy(has(slot.button.__shownAnims, part.beat), "still Pulse during the match")
    T.truthy(part.liveTex:GetTexture():find("flare%-wings%-live%.png$"), "still the old design")
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.truthy(part.liveTex:GetTexture():find("flare%-flames%-live%.png$"), "the new sheet once the match is over")
    T.truthy(has(slot.button.__shownAnims, part.gleam), "and Flash's gleam")
    T.falsy(has(slot.button.__shownAnims, part.beat), "Pulse's beat handed back")
end)

T.test("procs aura: Embers off: a game-shown flare hands the client no embers", function()
    local ns = load()
    ns.Alerts.Set("sealecho", "anim", "strike")
    ns.Alerts.Set("sealecho", "embers", false)
    stub.RunTimers()
    local slot = ns.Game.slots.sealecho[1]
    for i = 1, 2 do
        local part = slot.parts[i]
        T.falsy(has(slot.button.__shownAnims, part.embers), "piece " .. i .. ": no embers handed over")
        T.falsy(part.emberTex:IsShown())
        T.truthy(has(slot.button.__shownAnims, part.live), "the flicker still is")
    end
end)
