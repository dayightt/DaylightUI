local stub = require("stub")

-- Missing buffs (DaylightUI_Buffs/Reminder.lua finds them, ReminderRow.lua draws
-- them): a row of tiles above you, in a group, of the raid buffs you give (with
-- how many have them, a click casts), the ones others give that you lack, your
-- class's own buff and your weapons.

local RW = require("reminderworld")
local login, keys, entry, settle = RW.Login, RW.Keys, RW.Entry, RW.Settle

local PARTY = {
    player = { name = "Me", class = "WARRIOR" },
    party1 = { name = "Pri", class = "PRIEST" },
    party2 = { name = "Mag", class = "MAGE" },
    party3 = { name = "Pal", class = "PALADIN" },
}

-- ---------------------------------------------------------------------
-- Giving (Task 1, A1)
-- ---------------------------------------------------------------------

local PRIESTS = {
    player = { name = "Me", class = "PRIEST" },
    party1 = { name = "Ann", class = "WARRIOR" },
    party2 = { name = "Bo", class = "ROGUE" },
    party3 = { name = "Cy", class = "MAGE" },
    party4 = { name = "Di", class = "DRUID" },
}

T.test("buffs reminder: giver: a priest sees Fortitude 2/5 and the cast goes to the first one lacking it", function()
    local BL = login(PRIESTS, { known = { 1243, 1244, 10938 } })
    stub.SetAuras("party1", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 10938 } })
    stub.SetAuras("party3", "HELPFUL", { { name = "Prayer of Fortitude", spellId = 21564 } })
    local e = entry(BL.Reminder.Collect(), "fortitude")
    T.truthy(e, "a Fortitude entry")
    T.eq(e.kind, "give")
    T.eq(e.have, 2); T.eq(e.total, 5)
    T.eq(e.unit, "player", "you lack it first")
    T.eq(e.spell, 10938, "the highest single rank you know (no group version known)")
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 10938 } })
    e = entry(BL.Reminder.Collect(), "fortitude")
    T.eq(e.unit, "party2", "the first other one lacking it")
end)

-- As EllesmereUI picks it: the group version on you while it can be cast now
-- (its reagent in the bags), else the single one on the first lacking it.
T.test("buffs reminder: giver: the group version while you could cast it, else the single one", function()
    local BL = login(PRIESTS, { known = { 1243, 10938, 21562 } })
    local usable = C_Spell.IsSpellUsable
    local candles = true
    C_Spell.IsSpellUsable = function(id) if id == 21562 then return candles, false end return true, false end
    local e = entry(BL.Reminder.Collect(), "fortitude")
    T.eq(e.spell, 21562, "Prayer of Fortitude")
    T.eq(e.unit, "player")
    candles = false
    e = entry(BL.Reminder.Collect(), "fortitude")
    T.eq(e.spell, 10938, "no candle: the single version")
    T.eq(e.unit, "player", "on the first lacking it: you")
    C_Spell.IsSpellUsable = usable
end)

T.test("buffs reminder: giver: Battle Shout counts only melee and is cast on yourself", function()
    local BL = login({ player = { name = "Me", class = "WARRIOR" }, party1 = { name = "Mag", class = "MAGE" },
                       party2 = { name = "Rog", class = "ROGUE" }, party3 = { name = "Pri", class = "PRIEST" } },
                     { known = { 6673, 5242 } })
    local e = entry(BL.Reminder.Collect(), "shout")
    T.truthy(e)
    T.eq(e.total, 2, "the warrior and the rogue")
    T.eq(e.unit, "player"); T.eq(e.spell, 5242)
end)

T.test("buffs reminder: giver: someone out of sight, dead or offline isn't counted", function()
    local units = {}
    for k, v in pairs(PRIESTS) do units[k] = { name = v.name, class = v.class } end
    local BL = login(units, { known = { 1243 } })
    T.eq(entry(BL.Reminder.Collect(), "fortitude").total, 5)
    units.party1.visible = false
    units.party2.offline = true
    units.party3.dead = true
    T.eq(entry(BL.Reminder.Collect(), "fortitude").total, 2)
end)

T.test("buffs reminder: unknown is never missing (a boss room: the client says the buff is secret)", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    stub.SetRestriction("Encounter", true)
    local list
    T.noerror(function() list = BL.Reminder.Collect() end)
    T.isnil(entry(list, "fortitude"), "secret: no tile")
    local reads = 0
    local byIndex = C_UnitAuras.GetAuraDataByIndex
    C_UnitAuras.GetAuraDataByIndex = function(...) reads = reads + 1; return byIndex(...) end
    for _, id in ipairs(BL.ReminderData.byKey.fortitude.ids) do stub.neverSecretAuras[id] = true end
    -- The client hands out never-secret auras by name too.
    local byName = C_UnitAuras.GetAuraDataBySpellName
    local rule = stub.AurasRestricted
    stub.AurasRestricted = function() return false end
    T.truthy(entry(BL.Reminder.Collect(), "fortitude"), "readable again: back")
    stub.AurasRestricted = rule
    C_UnitAuras.GetAuraDataByIndex = byIndex
    T.eq(reads, 0, "nothing read by index")
    T.truthy(byName)
    stub.SetRestriction("Encounter", false)
end)

T.test("buffs reminder: a raid buff the client keeps secret isn't read in a fight", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    local reads = 0
    local U = C_UnitAuras
    local wrap = {}
    for _, k in ipairs({ "GetAuraDataByIndex", "GetAuraDataBySpellName", "GetUnitAuraBySpellID" }) do
        wrap[k] = U[k]
        U[k] = function(...) reads = reads + 1; return wrap[k](...) end
    end
    stub.EnterCombat()
    T.deq(keys(BL.Reminder.Collect()), {}, "secret in a fight: nothing missing, the row holds what it had")
    stub.FireEvent("UNIT_AURA", "player")
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    for k, f in pairs(wrap) do U[k] = f end
    T.eq(reads, 0)
    stub.LeaveCombat()
end)

-- ---------------------------------------------------------------------
-- Receiving (A2: today's rules, as entries)
-- ---------------------------------------------------------------------

T.test("buffs reminder: receiver: a warrior with a priest and a paladin sees Fortitude and Might, not clickable", function()
    local BL = login(PARTY)
    T.deq(keys(BL.Reminder.Collect()), { "fortitude", "might" })
    local e = entry(BL.Reminder.Collect(), "fortitude")
    T.eq(e.kind, "get")
    T.falsy(BL.ReminderRow.Clickable(e))
end)

T.test("buffs reminder: receiver: a caster wants Intellect and Wisdom; never Spirit (a talent)", function()
    local BL = login({
        player = { name = "Me", class = "PRIEST" },
        party1 = { name = "Mag", class = "MAGE" },
        party2 = { name = "Pal", class = "PALADIN" },
        party3 = { name = "Dru", class = "DRUID" },
        party4 = { name = "Pri", class = "PRIEST" },
    }, { known = { 1243 } })
    T.deq(keys(BL.Reminder.Collect()), { "fortitude", "wild", "intellect", "wisdom" }, "Fortitude as its giver")
    stub.SetAuras("party1", "HELPFUL", { { name = "Divine Spirit", spellId = 27841 } })
    T.deq(keys(BL.Reminder.Collect()), { "fortitude", "wild", "intellect", "wisdom" }, "worn or not: another priest may lack the talent")
end)

T.test("buffs reminder: receiver: what you have is left out (any rank, the group version too)", function()
    local BL = login(PARTY)
    stub.SetAuras("player", "HELPFUL", { { name = "Prayer of Fortitude", spellId = 21564 } })
    T.deq(keys(BL.Reminder.Collect()), { "might" })
end)

T.test("buffs reminder: receiver: two paladins, two blessings; a tank isn't asked to take Salvation", function()
    local units = {
        player = { name = "Me", class = "WARRIOR", role = "TANK" },
        party1 = { name = "Pal", class = "PALADIN" },
        party2 = { name = "Pal2", class = "PALADIN" },
    }
    local BL = login(units)
    stub.SetAuras("player", "HELPFUL", { { name = "Blessing of Might", spellId = 19838 } })
    T.deq(keys(BL.Reminder.Collect()), { "kings" })
    units.player.role = nil
    units.party3 = { name = "Pal3", class = "PALADIN", isPlayer = true }
    T.deq(keys(BL.Reminder.Collect()), { "kings", "salvation" })
end)

T.test("buffs reminder: receiver: in a raid every member counts once, you included", function()
    local me = { name = "Me", class = "MAGE" }
    local BL = login({ player = me, raid1 = me, raid2 = { name = "Dru", class = "DRUID" }, raid3 = { name = "Pal", class = "PALADIN" } },
                     { known = { 1459 } })
    stub.SetGroup(true, true)
    T.deq(keys(BL.Reminder.Collect()), { "wild", "intellect", "wisdom" }, "your own Intellect as a giver")
    T.eq(entry(BL.Reminder.Collect(), "intellect").kind, "give")
end)

T.test("buffs reminder: receiver: nobody here can give it: nothing", function()
    local BL = login({ player = { name = "Me", class = "WARRIOR" }, party1 = { name = "Rog", class = "ROGUE" },
                       party2 = { name = "Pal", class = "PALADIN", offline = true } })
    T.deq(keys(BL.Reminder.Collect()), {}, "an offline paladin gives nothing")
end)

T.test("buffs reminder: in a battleground raid (names, classes and who-is-who secret) nothing errors or shows", function()
    local me = { name = "Me", class = "MAGE" }
    local BL = login({ player = me, raid1 = me, raid2 = { name = "Dru", class = "DRUID" }, raid3 = { name = "Pal", class = "PALADIN" } })
    stub.SetGroup(true, true)
    stub.SetRestriction("PvPMatch", true)
    local list
    T.noerror(function() list = BL.Reminder.Collect() end)
    T.deq(keys(list), {}, "not read")
    T.noerror(function() stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers() end)
    T.noerror(function() stub.buffs.Scan.Group() end, "/dui buffs scan")
    stub.SetRestriction("PvPMatch", false)
end)

-- ---------------------------------------------------------------------
-- When (A6, A7)
-- ---------------------------------------------------------------------

-- His hide gate: a vehicle, mounted and flying, dead, resting. A flight path
-- hides too (kept from before). Mounted on the ground keeps the row.
T.test("buffs reminder: gate: vehicle, mounted+flying, dead, resting hide; mounted on the ground doesn't; a taxi hides (kept)", function()
    local BL = login(PARTY)
    local R = BL.Reminder
    local cases = {
        { "resting", function(on) stub.resting = on end, "PLAYER_UPDATE_RESTING" },
        { "dead", function(on) PARTY.player.dead = on or nil end, "PLAYER_DEAD", "PLAYER_ALIVE" },
        { "taxi", function(on) stub.taxi = on end, "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" },
        { "vehicle", function(on) stub.vehicle = on end, "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" },
        { "mounted and flying", function(on) stub.mounted = on; stub.flying = on end, "PLAYER_MOUNT_DISPLAY_CHANGED" },
    }
    stub.RunTimers()
    T.eq(#BL.ReminderRow.active, 2, "two tiles to start")
    for _, c in ipairs(cases) do
        c[2](true)
        stub.FireEvent(c[3], "player")
        stub.RunTimers(); settle()
        T.eq(#BL.ReminderRow.active, 0, c[1] .. ": gone")
        T.deq(keys(R.Collect()), {}, c[1])
        c[2](false)
        stub.FireEvent(c[4] or c[3], "player")
        stub.RunTimers(); settle()
        T.eq(#BL.ReminderRow.active, 2, c[1] .. ": back")
    end
    stub.mounted = true
    stub.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED"); stub.RunTimers(); settle()
    T.eq(#BL.ReminderRow.active, 2, "mounted on the ground: still shown")
    stub.mounted, stub.flying = nil, true
    T.eq(#R.Collect(), 2, "flying without a mount (a flight form): his gate is mounted and flying")
    stub.mounted, stub.flying = nil, nil
end)

T.test("buffs reminder: buckets: party diff 1/2 = dungeon, raid diff 9/148 = raid, no instance = open world, a battleground shows always", function()
    local BL = login(PARTY)
    local R = BL.Reminder
    local function at(kind, diff) stub.SetInstance(kind); stub.difficulty = diff; return R.Bucket() end
    for _, d in ipairs({ 1, 2, 8, 23, 24, 205 }) do T.eq(at("party", d), "dungeon", "party " .. d) end
    for _, d in ipairs({ 9, 148, 14, 3, 4, 17, 7, 33, 15, 5, 6, 16, 233 }) do T.eq(at("raid", d), "raid", "raid " .. d) end
    T.eq(at(nil, 0), "open_world")
    T.isnil(at("pvp", 0), "a battleground")
    T.isnil(at("arena", 0), "an arena")
    T.isnil(at("party", 99), "a dungeon difficulty he doesn't map")
    T.isnil(at("scenario", 0))
    -- The sections' gate: a place set to false is left out, the rest show.
    at(nil, 0)
    T.falsy(R.Shows({ open_world = false }, false))
    T.truthy(R.Shows({}, false))
    at("pvp", 0)
    T.truthy(R.Shows({ open_world = false, dungeon = false, raid = false }, false), "PvP always shows")
    T.falsy(R.Shows({ in_combat = false }, true), "in a fight with In combat unticked")
    -- The default raid buffs: left out in the open world.
    at(nil, 0)
    T.deq(keys(R.Collect()), {}, "the open world: no raid buffs by default")
    at("raid", 9)
    T.deq(keys(R.Collect()), { "fortitude", "might" }, "a 40-player raid")
end)

T.test("buffs reminder: solo shows (no solo gate)", function()
    local BL = login({ player = { name = "Me", class = "PRIEST" } }, { known = { 1243, 588 }, where = "world" })
    T.truthy(entry(BL.Reminder.Collect(), "innerfire"), "solo in the open world: your own buff")
    stub.SetInstance("party"); stub.difficulty = 1
    T.truthy(entry(BL.Reminder.Collect(), "fortitude"), "solo in a dungeon: Fortitude missing on you")
    T.isnil(BL.DEFAULTS.settings.reminder.solo, "no solo switch")
end)

T.test("buffs reminder: order: raid, self, consumables", function()
    local BL = login({ player = { name = "Me", class = "PRIEST" }, party1 = { name = "War", class = "WARRIOR" } },
                     { known = { 1243, 588 }, bags = true })
    DaylightUI:Set("Buffs", "settings.reminder.items.camp", true)
    T.deq(keys(BL.Reminder.Collect()), { "fortitude", "innerfire", "camp" })
    local sections = {}
    for _, e in ipairs(BL.Reminder.Collect()) do sections[#sections + 1] = e.section end
    T.deq(sections, { "raid", "self", "items" })
end)

T.test("buffs reminder: sound: once when a key newly appears, never on the first pass, never for a dismissed one", function()
    local BL = login(PRIESTS, { known = { 1243, 588 } })
    local played = {}
    local alert = DaylightUI.Sound.Alert
    DaylightUI.Sound.Alert = function(key) played[#played + 1] = key end
    DaylightUI:Set("Buffs", "settings.reminder.raid.sound", "dui:quest")
    DaylightUI:Set("Buffs", "settings.reminder.self.sound", "dui:done")
    stub.SetAuras("player", "HELPFUL", { { name = "Inner Fire", spellId = 588 } })
    for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local list = stub.auras[u] and stub.auras[u].HELPFUL or {}
        list[#list + 1] = { name = "Power Word: Fortitude", spellId = 1243 }
        stub.SetAuras(u, "HELPFUL", list)
    end
    BL.Reminder.Refresh()
    T.deq(played, {}, "nothing missing")
    stub.SetAuras("party2", "HELPFUL", {})
    BL.Reminder.Refresh()
    T.deq(played, { "dui:quest" }, "Fortitude newly missing: the raid section's sound")
    BL.Reminder.Refresh()
    T.deq(played, { "dui:quest" }, "still missing: once")
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243 } })
    BL.Reminder.Refresh()
    T.deq(played, { "dui:quest", "dui:done" }, "Inner Fire gone: the self section's sound")
    -- Dismissed: no sound when it comes back.
    BL.Reminder.hidden.innerfire = true
    stub.SetAuras("player", "HELPFUL", { { name = "Inner Fire", spellId = 588 }, { name = "Power Word: Fortitude", spellId = 1243 } })
    BL.Reminder.Refresh()
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243 } })
    BL.Reminder.Refresh()
    T.eq(#played, 2, "dismissed: silent")
    DaylightUI.Sound.Alert = alert
end)

T.test("buffs reminder: sound: never on the first pass after login", function()
    local played = 0
    local BL = login(PRIESTS, { known = { 1243 } })
    local alert = DaylightUI.Sound.Alert
    DaylightUI.Sound.Alert = function() played = played + 1 end
    DaylightUI:Set("Buffs", "settings.reminder.raid.sound", "dui:quest")
    BL.Reminder.ResetSounds()
    BL.Reminder.Refresh()
    T.truthy(entry(BL.Reminder.Collect(), "fortitude"))
    T.eq(played, 0, "the first look after a login is silent")
    DaylightUI.Sound.Alert = alert
end)

-- ---------------------------------------------------------------------
-- The row (Task 2)
-- ---------------------------------------------------------------------

local function sample4()
    return {
        { key = "a", kind = "give", have = 3, total = 5, spell = 1459, unit = "party1", short = "Intellect" },
        { key = "b", kind = "get", short = "Fortitude" },
        { key = "c", kind = "self", spell = 6117, macro = "/cast [nocombat,@player] Mage Armor", short = "Mage Armor" },
        { key = "d", kind = "weapon", item = 20750, macro = "/use [nocombat] item:20750\n/use 16", short = "Wizard Oil" },
    }
end

T.test("buffs reminder: the row: one tile per entry, centered, 14 px apart, names under", function()
    local BL = login(PARTY)
    local Row = BL.ReminderRow
    Row.Set(sample4())
    local xs, names = {}, {}
    for i, t in ipairs(Row.active) do
        local p, rel, rp, x, y = t:GetPoint(1)
        T.eq(p, "CENTER"); T.eq(rel, DaylightUIBuffRemindersHolder); T.eq(rp, "CENTER"); T.eq(y, 0)
        xs[i] = x
        names[i] = t.name:GetText()
        T.eq(t:GetWidth(), 40, "a 40 px icon, his default")
        T.truthy(t.icon:GetWidth() < 40, "the icon inside its border")
    end
    T.deq(xs, { -81, -27, 27, 81 })
    T.deq(names, { "Intellect", "Fortitude", "Mage Armor", "Wizard Oil" })
    local _, _, _, _, ny = Row.active[1].name:GetPoint(1)
    T.eq(ny, -5, "the name under the tile")
end)

T.test("buffs reminder: a tile leaving glides the rest; motion off snaps", function()
    local BL = login(PARTY)
    local Row = BL.ReminderRow
    local M = DaylightUI.Motion
    local glides = 0
    local glide = M.Glide
    M.Glide = function(...) glides = glides + 1; return glide(...) end
    Row.Set(sample4())
    local list = sample4()
    table.remove(list, 2)
    Row.Set(list)
    T.eq(glides, 3, "the three left glide to their new spot")
    local _, _, _, x = Row.active[1]:GetPoint(1)
    T.eq(x, -54, "re-centered")
    settle()
    DaylightUI:Set("general", "motion", false)
    glides = 0
    Row.Set(sample4())
    local reals = 0
    for _, t in ipairs(Row.tiles) do if t:IsShown() then reals = reals + 1 end end
    T.eq(reals, 4)
    Row.Set({ sample4()[1] })
    reals = 0
    for _, t in ipairs(Row.tiles) do if t:IsShown() then reals = reals + 1 end end
    T.eq(reals, 1, "motion off: gone at once")
    M.Glide = glide
    DaylightUI:Set("general", "motion", true)
end)

T.test("buffs reminder: a giver tile shows 3/5 in the accent; a receiver tile shows no count and has no button", function()
    local BL = login(PARTY)
    local Row = BL.ReminderRow
    Row.Set(sample4())
    local give, get = Row.active[1], Row.active[2]
    T.truthy(give.count:IsShown()); T.eq(give.count:GetText(), "3/5")
    local r, g, b = DaylightUI.Style.Accent()
    T.rgb({ give.count:GetTextColor() }, { r, g, b }, "the count in the accent")
    T.falsy(get.count:IsShown())
    local tiles = {}
    for _, btn in ipairs(Row.buttons) do if btn:IsShown() then tiles[btn.tile] = true end end
    T.truthy(tiles[give]); T.falsy(tiles[get], "a receiver tile takes no click")
end)

T.test("buffs reminder: the banner is gone; a ready check adds nothing", function()
    local BL = login(PARTY)
    T.isnil(_G.DaylightUIBuffReminder, "no banner frame")
    stub.RunTimers()
    local before = #BL.ReminderRow.active
    stub.FireEvent("READY_CHECK", "Pri", 35)
    stub.RunTimers()
    T.eq(#BL.ReminderRow.active, before, "the row already shows the gaps")
end)

T.test("buffs reminder: movable, with its own handle", function()
    login(PARTY)
    local e = DaylightUI.Movers.Get("buffs.reminders")
    T.truthy(e, "registered")
    T.eq(e.frame, DaylightUIBuffRemindersHolder)
    T.isnil(DaylightUI.Movers.Get("buffs.reminder"), "the banner's handle is gone")
end)

T.test("buffs reminder: the switch off shows nothing; test mode shows the sample until it ends", function()
    local BL = login(PARTY)
    stub.RunTimers()
    T.eq(#BL.ReminderRow.active, 2)
    DaylightUI:Set("Buffs", "settings.reminder.enabled", false)
    stub.RunTimers(); settle()
    T.eq(#BL.ReminderRow.active, 0)
    DaylightUI:Set("Buffs", "settings.reminder.enabled", true)
    DaylightUI.SetTestMode(true)
    local names = {}
    for _, t in ipairs(BL.ReminderRow.active) do names[#names + 1] = t.name:GetText() end
    T.deq(names, { "Intellect", "Fortitude", "Armor", "Main" }, "the sample's four icons, his short names")
    stub.FireEvent("UNIT_AURA", "player"); stub.RunTimers()
    T.eq(#BL.ReminderRow.active, 4, "a change doesn't replace the sample")
    for _, b in ipairs(BL.ReminderRow.buttons) do T.falsy(b:IsShown(), "the sample takes no click") end
    DaylightUI.SetTestMode(false)
    stub.RunTimers(); settle()
    T.eq(#BL.ReminderRow.active, 2, "back to the real gaps")
end)

-- ---------------------------------------------------------------------
-- Clicks (Task 3)
-- ---------------------------------------------------------------------

T.test("buffs reminder: a giver tile's button casts the spell at the first lacking; no unsuffixed type", function()
    local BL = login(PRIESTS, { known = { 1243, 10938 } })
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 10938 } })
    BL.Reminder.Refresh()
    local b = DaylightUIBuffReminderCast1
    T.truthy(b and b:IsShown(), "a button")
    T.eq(b:GetAttribute("type1"), "spell")
    T.eq(b:GetAttribute("spell1"), 10938)
    T.eq(b:GetAttribute("unit1"), "party1")
    T.isnil(b:GetAttribute("type"), "middle and right clicks never cast")
    T.eq(b:GetParent(), UIParent)
    local _, rel = b:GetPoint(1)
    T.eq(rel, UIParent, "never anchored to the tile")
end)

T.test("buffs reminder: a self buff or weapon tile: macrotext1 carries [nocombat]", function()
    local BL = login(PARTY)
    BL.ReminderRow.Set(sample4())
    local macros = {}
    for _, b in ipairs(BL.ReminderRow.buttons) do
        if b:IsShown() and b:GetAttribute("type1") == "macro" then macros[#macros + 1] = b:GetAttribute("macrotext1") end
    end
    T.eq(#macros, 2)
    for _, m in ipairs(macros) do T.truthy(m:find("[nocombat", 1, true), m) end
end)

T.test("buffs reminder: middle-click hides Fortitude until the next loading screen", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    BL.Reminder.Refresh()
    local b = DaylightUIBuffReminderCast1
    T.eq(b.entry.key, "fortitude")
    b:GetScript("PostClick")(b, "MiddleButton")
    stub.RunTimers(); settle()
    local function shown()
        for _, t in ipairs(BL.ReminderRow.active) do if t.key == "fortitude" then return true end end
        return false
    end
    T.isnil(entry(BL.Reminder.Collect(), "fortitude"), "hidden")
    T.falsy(shown())
    stub.FireEvent("UNIT_AURA", "player"); stub.RunTimers()
    T.falsy(shown(), "stays hidden on UNIT_AURA")
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false); stub.RunTimers()
    T.truthy(shown(), "back after a loading screen")
    -- A tile without a button: its own middle-click.
    BL.ReminderRow.Set({ { key = "might", kind = "get", short = "Might" } })
    BL.ReminderRow.active[1]:GetScript("OnMouseUp")(BL.ReminderRow.active[1], "MiddleButton")
    T.truthy(BL.Reminder.hidden.might)
end)

T.test("buffs reminder: buttons are only touched out of combat", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    BL.Reminder.Refresh()
    stub.secure = true
    stub.EnterCombat()
    T.noerror(function()
        BL.ReminderRow.Set(sample4())
        stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    end, "a changed list in a fight writes no attribute")
    T.eq(DaylightUIBuffReminderCast1:GetAttribute("spell1"), 1243, "still the pull's spell")
    stub.LeaveCombat()
    stub.secure = false
    stub.RunTimers()
    T.eq(DaylightUIBuffReminderCast1:GetAttribute("type1"), "spell", "placed again after the fight")
end)

T.test("buffs reminder: the tooltip names who lacks it and what a click does", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    BL.Reminder.Refresh()
    local text = {}
    GameTooltip.AddLine = function(_, t) text[#text + 1] = t end
    GameTooltip.AddDoubleLine = function(_, a, b) text[#text + 1] = a .. " " .. b end
    local b = DaylightUIBuffReminderCast1
    b:GetScript("OnEnter")(b)
    local all = table.concat(text, "\n")
    T.truthy(all:find("Missing on 5 of 5", 1, true), all)
    T.truthy(all:find("Ann", 1, true), all)
    T.truthy(all:find("Middle-click", 1, true), all)
end)

-- ---------------------------------------------------------------------
-- Options and settings (Task 8)
-- ---------------------------------------------------------------------

T.test("buffs reminder: options: the five cards with every row and its default", function()
    local BL = login(PARTY)
    local cards = {}
    for _, g in ipairs(BL.OPTIONS.pages[1].groups) do cards[g.label] = g end
    local keys, labels, preview = {}, {}, nil
    for _, name in ipairs({ "Missing buffs", "Missing buffs look", "Raid buffs", "Self buffs", "Consumables" }) do
        T.truthy(cards[name], name)
        for _, it in ipairs(cards[name].items) do
            if it.key then keys[it.key] = true end
            labels[it.label] = true
            if it.type == "button" and it.label == "Preview the missing buffs" then preview = it end
        end
    end
    local R = "settings.reminder."
    for _, k in ipairs({ "enabled", "cursor", "cursorCombat", "tooltips", "picker", "size", "shape", "zoom", "crop", "grow",
                         "strata", "gap", "border", "borderPx", "borderColor", "borderShiftX", "borderShiftY", "borderBehind",
                         "names", "nameFont", "nameSize", "nameAnchor", "nameX", "nameY", "nameColor", "count", "countFont",
                         "countSize", "countX", "countY", "glow", "glowColor", "glowCustom", "opacity", "fightAlpha",
                         "raid.others", "raid.mine", "raid.sound", "raid.on.fortitude", "raid.on.wild", "raid.on.intellect",
                         "raid.on.spirit", "raid.on.shout", "raid.blessings", "raid.shadow",
                         "self.sound", "self.mageArmor", "self.imbue", "self.hideNoItem", "self.weaponBelow", "self.sacrifice",
                         "self.demon", "self.gather", "self.gatherClassTrack", "self.treasure",
                         "items.sound", "items.camp", "items.bag", "items.bagBelow", "items.bagTimer", "items.wellFed",
                         "items.wellFedBelow", "items.censer", "items.separate", "items.stronger", "items.statBelow", "items.oil" }) do
        T.truthy(keys[R .. k], k)
    end
    for _, l in ipairs({ "Raid buffs: where to show", "Self buffs: where to show", "Consumables: where to show", "Class buffs",
                         "Custom spells", "Spell groups", "Scrolls and elixirs", "Weapon rank to use", "Main hand stone or oil" }) do
        T.truthy(labels[l], l)
    end
    T.truthy(preview, "Preview")
    preview.func()
    T.eq(#BL.ReminderRow.active, 4, "the sample shows")
    preview.func()
    stub.RunTimers(); settle()
    T.falsy(BL.Reminder.sample, "and hides again")
    local d = BL.DEFAULTS.settings.reminder
    for _, k in ipairs({ "solo", "give", "get", "weapons", "food", "scrolls", "sleepingBag", "lowMinutes" }) do
        T.isnil(d[k], "the old " .. k .. " is gone")
    end
end)

T.test("buffs reminder: options: every row validates; a profile switch and a new character keep working", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    local errs = {}
    for _, g in ipairs(BL.OPTIONS.pages[1].groups) do DaylightUI.Options.Validate(g.items, BL.DEFAULTS, errs, g.label) end
    T.deq(errs, {}, "no option errors")
    local DUI = DaylightUI
    T.noerror(function()
        DUI.Profiles.Replace(DUI.DB.ActiveName(), DUI.Profiles.ReadyData("DPS/Tank"))
        stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers(); settle()
    end)
    T.truthy(#BL.ReminderRow.active > 0, "the fresh profile shows the row")
    local store = DUI.DB.Character().buffReminder
    T.isnil(store and store.mageArmor, "a new character remembers no armor")
    T.isnil(store and store.food, "nor a food")
end)

T.test("buffs reminder: the switch off: no tile, no events left registered", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    BL.Reminder.Refresh()
    T.truthy(BL.Reminder.Registered() > 0, "watching while on")
    T.truthy(BL.Reminder.watchers[1].a, "the group's auras watched while you give a raid buff")
    DaylightUI:Set("Buffs", "settings.reminder.enabled", false)
    stub.RunTimers(); settle()
    T.eq(#BL.ReminderRow.active, 0)
    T.eq(BL.Reminder.Registered(), 0, "nothing left registered")
    for _, b in ipairs(BL.ReminderRow.buttons) do T.falsy(b:IsShown(), "no button left") end
end)

T.test("buffs reminder: only a giver watches the group's auras", function()
    local BL = login(PARTY)
    BL.Reminder.Refresh()
    for _, f in ipairs(BL.Reminder.watchers) do T.isnil(f.a, "a warrior receiving only: none") end
end)

T.test("buffs reminder: the profile made over again: the next look reads its settings", function()
    local BL = login(PARTY)
    BL.Reminder.Refresh()
    T.eq(#BL.ReminderRow.active, 2)
    local DUI = DaylightUI
    local fresh = DUI.Profiles.ReadyData("DPS/Tank")
    fresh.modules = fresh.modules or {}
    fresh.modules.Buffs = fresh.modules.Buffs or {}
    fresh.modules.Buffs.settings = { reminder = { enabled = false } }
    DUI.Profiles.Replace(DUI.DB.ActiveName(), fresh)
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers(); settle()
    T.eq(#BL.ReminderRow.active, 0, "off in the new profile")
end)

T.test("buffs reminder: a bigger icon size lays the row out again", function()
    local BL = login(PARTY)
    BL.Reminder.Refresh()
    DaylightUI:Set("Buffs", "settings.reminder.size", 48)
    DaylightUI:Set("Buffs", "settings.reminder.gap", 12)
    stub.RunTimers()
    local t = BL.ReminderRow.active[1]
    T.eq(t:GetWidth(), 48)
    local _, _, _, x = t:GetPoint(1)
    T.eq(x, -30, "two tiles 60 apart")
    DaylightUI:Set("Buffs", "settings.reminder.names", false)
    stub.RunTimers()
    T.falsy(t.name:IsShown())
end)

-- Seen in game: clicking the Battle Shout tile cast nothing. The client acts on a
-- secure button's down half while ActionButtonUseKeyDown is on (its default),
-- and the button only took the up half of a click.
T.test("buffs reminder: a real mouse click casts it (the key-down setting on, as by default)", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    BL.Reminder.Refresh()
    local b = DaylightUIBuffReminderCast1
    local cast = {}
    stub.CastSpell = function(id) cast[#cast + 1] = id end
    stub.keyDownCVar = nil
    for _, half in ipairs(b.__clicks or {}) do
        if half:find("^LeftButton") or half:find("^Any") then
            stub.SecureClick(b, "LeftButton", half:find("Down") ~= nil)
        end
    end
    stub.CastSpell = nil
    T.deq(cast, { 1243 }, "cast once")
end)

-- Seen in game: Battle Shout lasts 2 minutes, always under the 5 minute "running
-- low" line, so its tile never went away after casting it.
T.test("buffs reminder: Battle Shout just cast clears its tile, near its end too (raid buffs: there or not)", function()
    local BL = login({ player = { name = "Me", class = "WARRIOR" }, party1 = { name = "Rog", class = "ROGUE" } },
                     { known = { 6673 } })
    local now = GetTime()
    for _, u in ipairs({ "player", "party1" }) do
        stub.SetAuras(u, "HELPFUL", { { name = "Battle Shout", spellId = 6673, duration = 120, expirationTime = now + 118 } })
    end
    T.isnil(entry(BL.Reminder.Collect(), "shout"), "just cast: gone")
    for _, u in ipairs({ "player", "party1" }) do
        stub.SetAuras(u, "HELPFUL", { { name = "Battle Shout", spellId = 6673, duration = 120, expirationTime = now + 20 } })
    end
    T.isnil(entry(BL.Reminder.Collect(), "shout"), "20 s left: still there")
    stub.SetAuras("party1", "HELPFUL", {})
    local e = entry(BL.Reminder.Collect(), "shout")
    T.eq(e.have, 1); T.eq(e.total, 2)
end)

T.test("buffs reminder: the row moved in unlock mode: its click buttons follow", function()
    local BL = login(PRIESTS, { known = { 1243 } })
    BL.Reminder.Refresh()
    local b = DaylightUIBuffReminderCast1
    local _, _, _, x1, y1 = b:GetPoint(1)
    local holder = DaylightUIBuffRemindersHolder
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "CENTER", 100, -50)
    DaylightUI.Fire("MoverApplied", "buffs.reminders")
    local _, _, _, x2, y2 = b:GetPoint(1)
    T.truthy(x2 ~= x1 or y2 ~= y1, "placed again")
end)

-- ---------------------------------------------------------------------
-- The plugin API (1.17)
-- ---------------------------------------------------------------------

T.test("buffs reminder api: each icon is a frame of kind buffreminder; the row is GetFrame(\"reminders\")", function()
    local BL = login(PARTY)
    local API = DaylightUI.API
    local made, gone = {}, {}
    API.On("FrameMade", function(kind, _, unit, preview) if kind == "buffreminder" and not preview then made[#made + 1] = unit end end)
    API.On("FrameRemoved", function(kind, _, unit) if kind == "buffreminder" then gone[#gone + 1] = unit end end)
    BL.Reminder.Refresh()
    local units = {}
    for _, unit in API.Frames("buffreminder") do units[#units + 1] = unit end
    table.sort(units)
    T.deq(units, { "fortitude", "might" })
    T.eq(API.GetFrame("reminders"), DaylightUIBuffRemindersHolder)
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243 } })
    BL.Reminder.Refresh()
    T.deq(gone, { "fortitude" }, "the icon leaving is removed")
    DaylightUI.SetTestMode(true)
    for _, unit in API.Frames("buffreminder") do T.truthy(unit ~= "intellect", "samples never come from the lookups") end
    DaylightUI.SetTestMode(false)
end)

T.test("buffs reminder api: a plugin's own missing buff shows while none of its spells is on you", function()
    local BL = login({ player = { name = "Me", class = "MAGE" }, party1 = { name = "War", class = "WARRIOR" } },
                     { known = { 7777 } })
    stub.spells[7777] = { name = "Frost Ward" }
    local me = DaylightUI.API.For("Wards")
    local want = true
    T.eq(me.AddBuffReminder("ward", { label = "Ward", spells = { 7777 }, when = function() return want end }), true)
    stub.RunTimers()
    local e = entry(BL.Reminder.Collect(), "Wards:ward")
    T.truthy(e, "shown")
    T.eq(e.short, "Ward")
    T.eq(e.macro, "/cast [nocombat] Frost Ward", "a click casts it")
    want = false
    T.isnil(entry(BL.Reminder.Collect(), "Wards:ward"), "its when() says no")
    want = true
    stub.SetAuras("player", "HELPFUL", { { name = "Frost Ward", spellId = 7777 } })
    T.isnil(entry(BL.Reminder.Collect(), "Wards:ward"), "on you: gone")
    stub.SetAuras("player", "HELPFUL", {})
    T.eq(me.AddBuffReminder("bad", { label = "x" }), false, "no spells: refused")
    T.eq(me.RemoveBuffReminder("ward"), true)
    T.isnil(entry(BL.Reminder.Collect(), "Wards:ward"))
    T.eq(me.RemoveBuffReminder("ward"), false)
    -- A when() that errors is reported, and the icon stays away.
    me.AddBuffReminder("boom", { label = "Boom", spells = { 7777 }, when = function() error("oops") end })
    T.isnil(entry(BL.Reminder.Collect(), "Wards:boom"))
end)

-- ---------------------------------------------------------------------
-- Raid Buffs section (Task 3)
-- ---------------------------------------------------------------------

T.test("buffs reminder raid: where to show: off in the open world by default, on in a dungeon and a raid", function()
    local BL = login(PRIESTS, { known = { 1243 }, where = "world" })
    T.isnil(entry(BL.Reminder.Collect(), "fortitude"), "open world")
    stub.SetInstance("party"); stub.difficulty = 2
    T.truthy(entry(BL.Reminder.Collect(), "fortitude"), "a heroic dungeon")
    DaylightUI:Set("Buffs", "settings.reminder.raid.where.dungeon", false)
    T.isnil(entry(BL.Reminder.Collect(), "fortitude"), "dungeons unticked")
    stub.SetInstance(nil); stub.difficulty = 0
    DaylightUI:Set("Buffs", "settings.reminder.raid.where.open_world", true)
    T.truthy(entry(BL.Reminder.Collect(), "fortitude"), "open world ticked")
end)

T.test("buffs reminder raid: a buff unticked never reminds, in either view", function()
    local BL = login(PARTY)
    T.deq(keys(BL.Reminder.Collect()), { "fortitude", "might" })
    DaylightUI:Set("Buffs", "settings.reminder.raid.on.fortitude", false)
    T.deq(keys(BL.Reminder.Collect()), { "might" }, "receiver view")
    local BL2 = login(PRIESTS, { known = { 1243 } })
    DaylightUI:Set("Buffs", "settings.reminder.raid.on.fortitude", false)
    T.isnil(entry(BL2.Reminder.Collect(), "fortitude"), "giver view")
    DaylightUI:Set("Buffs", "settings.reminder.raid.blessings", false)
    T.isnil(entry(BL2.Reminder.Collect(), "might"))
end)

T.test("buffs reminder raid: show when: I'm missing others' buffs is off by default; others missing mine on", function()
    local BL = login(PARTY, { mine = false })
    T.deq(keys(BL.Reminder.Collect()), {}, "the receiver view is off by default")
    local d = BL.DEFAULTS.settings.reminder.raid
    T.eq(d.others, true); T.eq(d.mine, false)
    local BL2 = login(PRIESTS, { known = { 1243 }, mine = false })
    T.eq(entry(BL2.Reminder.Collect(), "fortitude").total, 5)
    DaylightUI:Set("Buffs", "settings.reminder.raid.others", false)
    local e = entry(BL2.Reminder.Collect(), "fortitude")
    T.truthy(e, "you lack it yourself")
    T.isnil(e.total, "no group count")
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243 } })
    T.isnil(entry(BL2.Reminder.Collect(), "fortitude"), "you have it: others don't matter")
end)

T.test("buffs reminder raid: Arcane Intellect counts as present under a stronger Elixir of Greater Intellect", function()
    stub.spells[11396] = { name = "Greater Intellect" }
    local BL = login({ player = { name = "Me", class = "MAGE" }, party1 = { name = "Pri", class = "PRIEST" } },
                     { known = { 1459, 1460 } })
    stub.spells[11396] = { name = "Greater Intellect" }
    stub.SetAuras("party1", "HELPFUL", { { name = "Greater Intellect", spellId = 11396 } })
    local e = entry(BL.Reminder.Collect(), "intellect")
    T.eq(e.have, 1, "the elixir (25) beats rank 2 (7)")
    stub.knownSpells[10157] = true
    e = entry(BL.Reminder.Collect(), "intellect")
    T.eq(e.have, 0, "rank 5 (31) beats it: the elixir doesn't count")
end)

T.test("buffs reminder raid: 40 in a raid: 20 watch frames, nothing per frame", function()
    local units = { player = { name = "Me", class = "PRIEST" } }
    units.raid1 = units.player
    for i = 2, 40 do units["raid" .. i] = { name = "M" .. i, class = "WARRIOR" } end
    local BL = login(units, { known = { 1243 }, where = "raid", difficulty = 9 })
    stub.SetGroup(true, true)
    BL.Reminder.Refresh()
    local e = entry(BL.Reminder.Collect(), "fortitude")
    T.eq(e.total, 40, "everyone counted")
    local n = 0
    for _, f in ipairs(BL.Reminder.watchers) do if f.a then n = n + 1 end end
    T.eq(n, 20, "39 others, two a frame")
    for _, f in ipairs(BL.Reminder.watchers) do T.isnil(f:GetScript("OnUpdate"), "events only") end
end)
