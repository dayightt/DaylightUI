local stub = require("stub")

-- The buff reminder (DaylightUI_Buffs/Reminder.lua): on a ready check, or entering
-- a dungeon or raid in a group, a banner lists the group buffs you're missing that
-- someone in your group can give.

local function world(units)
    _G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    CreateFrame("Frame", "BuffFrame", UIParent)
    CreateFrame("Frame", "DebuffFrame", UIParent)
    stub.units = units
end

local function login(units, opts)
    opts = opts or {}
    stub.Load({ buffs = true, before = function()
        world(units)
        if opts.before then opts.before() end
    end })
    stub.RunTimers()
    stub.SetGroup(true, false)
    return stub.buffs
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 5) end
end

-- The names the banner shows, in order.
local function shown()
    local f = DaylightUIBuffReminder
    if not f:IsShown() then return nil end
    local out = {}
    for _, e in ipairs(f.entries) do
        if e.name:IsShown() then out[#out + 1] = e.name:GetText() end
    end
    return out
end

local PARTY = {
    player = { name = "Me", class = "WARRIOR" },
    party1 = { name = "Pri", class = "PRIEST" },
    party2 = { name = "Mag", class = "MAGE" },
    party3 = { name = "Pal", class = "PALADIN" },
}

T.test("buffs reminder: a ready check lists what you miss, by who's in the group and your class", function()
    login(PARTY)
    T.falsy(DaylightUIBuffReminder:IsShown(), "nothing until asked")
    stub.FireEvent("READY_CHECK", "Pri", 35)
    -- A warrior means no Intellect, no druid means no Mark, and one paladin gives one blessing, Might first.
    T.deq(shown(), { "Fortitude", "Might" })
    T.falsy(DaylightUIBuffReminder:IsMouseEnabled(), "never takes a click")
end)

T.test("buffs reminder: a caster wants Intellect and Wisdom; Spirit only when someone wears it", function()
    local units = {
        player = { name = "Me", class = "PRIEST" },
        party1 = { name = "Mag", class = "MAGE" },
        party2 = { name = "Pal", class = "PALADIN" },
        party3 = { name = "Dru", class = "DRUID" },
    }
    login(units)
    stub.FireEvent("READY_CHECK", "Pal", 35)
    T.deq(shown(), { "Fortitude", "Mark of the Wild", "Intellect", "Wisdom" })
    DaylightUI.Motion.Tween("buffs.reminder", 0, 0, 0)
    stub.buffs.Reminder.Hide(true)
    stub.SetAuras("party1", "HELPFUL", { { name = "Divine Spirit", spellId = 27841 } })
    stub.FireEvent("READY_CHECK", "Pal", 35)
    T.deq(shown(), { "Fortitude", "Mark of the Wild", "Intellect", "Spirit", "Wisdom" })
end)

T.test("buffs reminder: what you have is left out (any rank, the group version too)", function()
    login(PARTY)
    stub.SetAuras("player", "HELPFUL", { { name = "Prayer of Fortitude", spellId = 21564 } })
    stub.FireEvent("READY_CHECK", "Pri", 35)
    T.deq(shown(), { "Might" })
end)

T.test("buffs reminder: a buff landing takes its name off; the last one fades the banner", function()
    local BL = login(PARTY)
    -- Only frame-after timers run here (not the banner's own fade timer).
    local after = C_Timer.After
    C_Timer.After = function(d, fn) if d == 0 then after(d, fn) end end
    stub.FireEvent("READY_CHECK", "Pri", 35)
    T.deq(shown(), { "Fortitude", "Might" })
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 10938 } })
    stub.FireEvent("UNIT_AURA", "player")
    stub.FireEvent("UNIT_AURA", "player")
    stub.RunTimers()      -- once on the frame after, however many came
    T.deq(shown(), { "Might" })
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 10938 },
        { name = "Greater Blessing of Might", spellId = 25916 } })
    stub.FireEvent("UNIT_AURA", "player")
    stub.RunTimers()
    settle()
    T.falsy(DaylightUIBuffReminder:IsShown(), "all there: gone")
    T.falsy(BL.Reminder.sample)
    C_Timer.After = after
end)

T.test("buffs reminder: auras are only looked at while the banner shows, through the buffs' own player events", function()
    local BL = login(PARTY)
    local R = BL.Reminder
    local looks, recheck = 0, R.Recheck
    R.Recheck = function(...) looks = looks + 1; return recheck(...) end
    stub.FireEvent("UNIT_AURA", "player"); stub.RunTimers()
    T.eq(looks, 0, "no banner: a buff changing reads nothing")
    stub.FireEvent("READY_CHECK", "Pri", 35)
    stub.FireEvent("UNIT_AURA", "player"); stub.RunTimers()
    T.eq(looks, 1, "showing: looked at once")
    R.Hide(true)
    stub.FireEvent("UNIT_AURA", "player"); stub.RunTimers()
    T.eq(looks, 1, "hidden again: nothing")
    R.Recheck = recheck
end)

T.test("buffs reminder: two paladins, two blessings; a tank isn't asked to take Salvation", function()
    local units = {
        player = { name = "Me", class = "WARRIOR", role = "TANK" },
        party1 = { name = "Pal", class = "PALADIN" },
        party2 = { name = "Pal2", class = "PALADIN" },
    }
    login(units)
    stub.SetAuras("player", "HELPFUL", { { name = "Blessing of Might", spellId = 19838 } })
    stub.FireEvent("READY_CHECK", "Pal", 35)
    T.deq(shown(), { "Kings" })
    units.player.role = nil
    units.party3 = { name = "Pal3", class = "PALADIN" }
    stub.FireEvent("READY_CHECK", "Pal", 35)
    T.deq(shown(), { "Kings", "Salvation" })
end)

T.test("buffs reminder: in a raid every member counts once, you included", function()
    local me = { name = "Me", class = "MAGE" }
    login({ player = me, raid1 = me, raid2 = { name = "Dru", class = "DRUID" }, raid3 = { name = "Pal", class = "PALADIN" } })
    stub.SetGroup(true, true)
    stub.FireEvent("READY_CHECK", "Dru", 35)
    T.deq(shown(), { "Mark of the Wild", "Intellect", "Wisdom" }, "your own Intellect too: you can cast it")
end)

T.test("buffs reminder: nobody here can give it, or you're solo: nothing", function()
    login({ player = { name = "Me", class = "WARRIOR" }, party1 = { name = "Rog", class = "ROGUE" },
            party2 = { name = "Pal", class = "PALADIN", offline = true } })
    stub.FireEvent("READY_CHECK", "Rog", 35)
    T.falsy(DaylightUIBuffReminder:IsShown(), "an offline paladin gives nothing")
    stub.SetGroup(false, false)
    stub.units.party1 = nil
    stub.FireEvent("READY_CHECK", "Me", 35)
    T.falsy(DaylightUIBuffReminder:IsShown())
end)

T.test("buffs reminder: secret auras (a fight, a boss, a battleground) are never read", function()
    login(PARTY)
    for _, r in ipairs({ "Encounter", "PvPMatch", "ChallengeMode" }) do
        stub.SetRestriction(r, true)
        local reads = 0
        local get = C_UnitAuras.GetAuraDataByIndex
        C_UnitAuras.GetAuraDataByIndex = function(...) reads = reads + 1; return get(...) end
        T.noerror(function() stub.FireEvent("READY_CHECK", "Pri", 35) end)
        C_UnitAuras.GetAuraDataByIndex = get
        T.eq(reads, 0, r .. ": nothing read")
        T.falsy(DaylightUIBuffReminder:IsShown(), r)
        stub.SetRestriction(r, false)
    end
end)

T.test("buffs reminder: in a battleground raid (names, classes and who-is-who secret) nothing errors", function()
    local me = { name = "Me", class = "MAGE" }
    login({ player = me, raid1 = me, raid2 = { name = "Dru", class = "DRUID" }, raid3 = { name = "Pal", class = "PALADIN" } })
    stub.SetGroup(true, true)
    stub.SetRestriction("PvPMatch", true)
    T.noerror(function() stub.FireEvent("READY_CHECK", "Dru", 35) end)
    T.falsy(DaylightUIBuffReminder:IsShown(), "not read")
    T.noerror(function() stub.buffs.Scan.Group() end, "/dui buffs scan")
    T.noerror(function() stub.buffs.Scan.PrintGroup() end)
    stub.SetRestriction("PvPMatch", false)
end)

T.test("buffs reminder: a fight starting fades it out", function()
    login(PARTY)
    stub.FireEvent("READY_CHECK", "Pri", 35)
    T.truthy(DaylightUIBuffReminder:IsShown())
    stub.EnterCombat()
    settle()
    T.falsy(DaylightUIBuffReminder:IsShown())
    stub.LeaveCombat()
end)

T.test("buffs reminder: it fades by itself after its seconds", function()
    login(PARTY)
    stub.FireEvent("READY_CHECK", "Pri", 35)
    stub.RunTimers()
    settle()
    T.falsy(DaylightUIBuffReminder:IsShown())
end)

T.test("buffs reminder: entering a dungeon in a group looks once things settle; a /reload doesn't", function()
    login(PARTY)
    _G.IsInInstance = function() return true, "party" end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    stub.RunTimers()
    T.falsy(DaylightUIBuffReminder:IsShown(), "a reload")
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.falsy(DaylightUIBuffReminder:IsShown(), "not before it settles")
    stub.RunTimers()
    -- The timer that showed it may also have run its fade timer: the check
    -- happens, then RunTimers runs the queue again.
    T.truthy(DaylightUIBuffReminder.shown and #DaylightUIBuffReminder.shown == 2, "it looked")
    _G.IsInInstance = function() return false, "none" end
    DaylightUIBuffReminder.shown = nil
    stub.buffs.Reminder.Hide(true)
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    stub.RunTimers()
    T.isnil(DaylightUIBuffReminder.shown, "out in the world: no")
    _G.IsInInstance = nil
end)

T.test("buffs reminder: the switch off shows nothing; test mode shows a sample until it ends", function()
    login(PARTY)
    DaylightUI:Set("Buffs", "settings.reminder.enabled", false)
    stub.FireEvent("READY_CHECK", "Pri", 35)
    T.falsy(DaylightUIBuffReminder:IsShown())
    DaylightUI:Set("Buffs", "settings.reminder.enabled", true)
    DaylightUI.SetTestMode(true)
    T.deq(shown(), { "Fortitude", "Intellect", "Kings" })
    stub.RunTimers()
    T.truthy(DaylightUIBuffReminder:IsShown(), "stays while testing")
    stub.FireEvent("READY_CHECK", "Pri", 35)
    T.deq(shown(), { "Fortitude", "Intellect", "Kings" }, "a ready check doesn't replace the sample")
    DaylightUI.SetTestMode(false)
    T.falsy(DaylightUIBuffReminder:IsShown())
end)

T.test("buffs reminder: movable, with its own handle", function()
    login(PARTY)
    local e = DaylightUI.Movers.Get("buffs.reminder")
    T.truthy(e, "registered")
    T.eq(e.frame, DaylightUIBuffReminderHolder)
end)

-- The options' "Show sample" used to leave the banner up with no way to close it.
-- A small x in its corner closes it (the real banner too). Only the x takes the
-- click, so the banner stays out of the way.
T.test("buffs reminder: the x in its corner closes it, sample or real", function()
    local BL = login(PARTY)
    BL.Reminder.ShowSample(true)
    local f = DaylightUIBuffReminder
    T.truthy(f:IsShown())
    T.truthy(f.close, "an x")
    T.truthy(f.close:IsMouseEnabled(), "the x takes the click")
    T.falsy(f:IsMouseEnabled(), "the banner itself still doesn't")
    f.close:GetScript("OnClick")(f.close, "LeftButton")
    settle()
    T.falsy(f:IsShown(), "closed")
    stub.FireEvent("READY_CHECK", "Pri", 35)
    T.truthy(f:IsShown())
    f.close:GetScript("OnClick")(f.close, "LeftButton")
    settle()
    T.falsy(f:IsShown(), "the real one closes too")
end)
