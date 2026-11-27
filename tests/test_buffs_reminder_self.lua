local stub = require("stub")

-- Missing buffs of your own (DaylightUI_Buffs/Reminder.lua): your class's own
-- buff, weapon oils, poisons and imbues you carry, and the consumables each
-- behind its own switch.

local RW = require("reminderworld")
local login, entry, keys = RW.Login, RW.Entry, RW.Keys

local function party(class)
    return { player = { name = "Me", class = class, level = 60 }, party1 = { name = "War", class = "WARRIOR" } }
end

local function only(list, kind)
    local out = {}
    for _, e in ipairs(list or {}) do if e.kind == kind then out[#out + 1] = e end end
    return out
end

-- ---------------------------------------------------------------------
-- Your class's own buff (Task 5, A3)
-- ---------------------------------------------------------------------

T.test("buffs reminder self: a priest without Inner Fire sees it; with any rank, not; a click casts the highest rank", function()
    local BL = login(party("PRIEST"), { known = { 588, 7128, 602 } })
    local e = entry(BL.Reminder.Collect(), "innerfire")
    T.truthy(e, "missing")
    T.eq(e.kind, "self")
    T.eq(e.spell, 602, "the highest rank known")
    T.eq(e.macro, "/cast [nocombat,@player] Inner Fire")
    stub.SetAuras("player", "HELPFUL", { { name = "Inner Fire", spellId = 588 } })
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "rank 1 up counts")
end)

T.test("buffs reminder self: a mage with Ice Armor up: no tile; with none, the tile casts Ice Armor (last seen)", function()
    local BL = login(party("MAGE"), { known = { 168, 7300, 7302, 7320, 6117 } })
    local e = entry(BL.Reminder.Collect(), "armor")
    T.eq(e.spell, 7300, "nothing seen yet: the first line known, Frost Armor")
    stub.SetAuras("player", "HELPFUL", { { name = "Ice Armor", spellId = 7320 } })
    T.isnil(entry(BL.Reminder.Collect(), "armor"), "Ice Armor up")
    stub.SetAuras("player", "HELPFUL", {})
    e = entry(BL.Reminder.Collect(), "armor")
    T.eq(e.spell, 7320, "the line last seen up")
    T.eq(e.short, "Ice Armor")
    T.eq(DaylightUI.DB.Character().buffReminder.last.armor, 2, "kept for this character")
end)

T.test("buffs reminder self: a hunter in Aspect of the Cheetah counts as having an aspect", function()
    local BL = login(party("HUNTER"), { known = { 13165, 5118 } })
    T.truthy(entry(BL.Reminder.Collect(), "aspect"))
    stub.SetAuras("player", "HELPFUL", { { name = "Aspect of the Cheetah", spellId = 5118, sourceUnit = "player" } })
    T.isnil(entry(BL.Reminder.Collect(), "aspect"), "any line")
    stub.SetAuras("player", "HELPFUL", { { name = "Aspect of the Pack", spellId = 13159, sourceUnit = "party1" } })
    T.truthy(entry(BL.Reminder.Collect(), "aspect"), "another hunter's aspect isn't yours")
end)

T.test("buffs reminder self: a spell not learned yet: no tile", function()
    local BL = login(party("WARLOCK"))
    T.isnil(entry(BL.Reminder.Collect(), "demonarmor"))
    stub.knownSpells[687] = true
    T.truthy(entry(BL.Reminder.Collect(), "demonarmor"))
end)

T.test("buffs reminder self: under a restriction your own buff shows only when the client says it's readable", function()
    local BL = login(party("PRIEST"), { known = { 588 } })
    stub.SetRestriction("Map", true)
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "unknown: no tile")
    stub.SetRestriction("Map", false)
end)

-- ---------------------------------------------------------------------
-- Weapons (Task 6, A4)
-- ---------------------------------------------------------------------

T.test("buffs reminder self: a rogue with Instant Poison in the bags and none on the blades sees one tile per hand", function()
    local BL = login(party("ROGUE"), { bags = true })
    stub.equipped[16] = { id = 1001, class = 2, subClass = 15 }
    stub.equipped[17] = { id = 1002, class = 2, subClass = 15 }
    T.deq(only(BL.Reminder.Collect(), "weapon"), {}, "no poison in the bags: nothing")
    stub.bagItems[6949] = 5
    local list = only(BL.Reminder.Collect(), "weapon")
    T.deq(keys(list), { "weapon:main", "weapon:off" })
    T.eq(list[1].item, 6949)
    T.eq(list[1].macro, "/use [nocombat] item:6949\n/use 16", "the poison, then the hand's slot")
    T.eq(list[2].macro, "/use [nocombat] item:6949\n/use 17")
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, hasEnchant = true, enchantID = 1, enchantType = 2, timeLeft = 1800000 } })
    T.deq(keys(only(BL.Reminder.Collect(), "weapon")), { "weapon:off" }, "the main hand has one")
end)

T.test("buffs reminder self: a shaman without an imbue: the tile casts the last imbue cast, else Rockbiter", function()
    local BL = login(party("SHAMAN"), { known = { 8017, 8018, 8024 }, bags = true })
    stub.equipped[16] = { id = 1003, class = 2, subClass = 4 }
    local e = entry(BL.Reminder.Collect(), "weapon:main")
    T.eq(e.spell, 8018, "Rockbiter, its highest rank")
    T.eq(e.macro, "/cast [nocombat] Rockbiter Weapon")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8024)
    e = entry(BL.Reminder.Collect(), "weapon:main")
    T.eq(e.spell, 8024, "Flametongue, the one cast last")
end)

T.test("buffs reminder self: an off hand with no weapon (a shield): no off-hand tile; a stone fits the weapon's edge", function()
    local BL = login(party("WARRIOR"), { bags = true })
    stub.equipped[16] = { id = 1004, class = 2, subClass = 4 } -- a mace
    stub.equipped[17] = { id = 1005, class = 4, subClass = 6 } -- a shield
    stub.bagItems[2862] = 2 -- a sharpening stone: blades only
    T.deq(only(BL.Reminder.Collect(), "weapon"), {}, "no stone for a mace")
    stub.bagItems[3239] = 2 -- a weightstone
    T.deq(keys(only(BL.Reminder.Collect(), "weapon")), { "weapon:main" })
    T.eq(entry(BL.Reminder.Collect(), "weapon:main").item, 3239)
end)

T.test("buffs reminder self: 4 minutes left on an oil: the time in warn; 6 minutes: no tile", function()
    local BL = login(party("MAGE"), { bags = true })
    stub.equipped[16] = { id = 1006, class = 2, subClass = 10 }
    stub.bagItems[20750] = 1
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, hasEnchant = true, enchantID = 2, enchantType = 2, timeLeft = 1800000 } })
    T.isnil(entry(BL.Reminder.Collect(), "weapon:main"), "just put on, 30 minutes")
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, hasEnchant = true, enchantID = 2, enchantType = 2, timeLeft = 360000 } })
    T.isnil(entry(BL.Reminder.Collect(), "weapon:main"))
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, hasEnchant = true, enchantID = 2, enchantType = 2, timeLeft = 240000 } })
    local e = entry(BL.Reminder.Collect(), "weapon:main")
    T.truthy(e and e.expireAt, "running low")
    BL.Reminder.Refresh()
    local t
    for _, x in ipairs(BL.ReminderRow.active) do if x.key == "weapon:main" then t = x end end
    T.truthy(t.time:IsShown())
    T.rgb({ t.time:GetTextColor() }, DaylightUI.Style.INK.WARN)
end)

T.test("buffs reminder self: the weapon switch off: no weapon tiles and no bag events", function()
    local BL = login(party("MAGE"), { bags = true })
    stub.equipped[16] = { id = 1006, class = 2, subClass = 10 }
    stub.bagItems[20750] = 1
    T.truthy(entry(BL.Reminder.Collect(), "weapon:main"))
    T.truthy(BL.Reminder.events:IsEventRegistered("BAG_UPDATE_DELAYED"), "bags watched while a weapon tile can show")
    DaylightUI:Set("Buffs", "settings.reminder.weapons", false)
    stub.RunTimers()
    T.isnil(entry(BL.Reminder.Collect(), "weapon:main"))
    T.falsy(BL.Reminder.events:IsEventRegistered("BAG_UPDATE_DELAYED"))
end)

-- ---------------------------------------------------------------------
-- Consumables (Task 7, A13: one switch each, off)
-- ---------------------------------------------------------------------

local function consumableWorld()
    local BL = login(party("WARRIOR"), { bags = true })
    stub.bagItems[10310] = 2        -- Scroll of Strength IV
    stub.itemSpells[10310] = { "Strength", 12179 }
    stub.bagItems[211527] = 1       -- Cozy Sleeping Bag
    local had = _G.GetMaxPlayerLevel
    _G.GetMaxPlayerLevel = function() return 70 end
    stub.onReset = stub.onReset or {}
    stub.onReset[#stub.onReset + 1] = function() _G.GetMaxPlayerLevel = had end
    return BL
end

T.test("buffs reminder self: food, scrolls, camp and sleeping bag are off by default: nothing", function()
    local BL = consumableWorld()
    T.deq(only(BL.Reminder.Collect(), "item"), {})
end)

T.test("buffs reminder self: food on: Well Fed missing shows; eaten, gone", function()
    local BL = consumableWorld()
    DaylightUI:Set("Buffs", "settings.reminder.food", true)
    T.truthy(entry(BL.Reminder.Collect(), "food"))
    stub.SetAuras("player", "HELPFUL", { { name = "Well Fed", spellId = 24799 } })
    T.isnil(entry(BL.Reminder.Collect(), "food"), "any Well Fed by name")
end)

T.test("buffs reminder self: scrolls on: shows while carried and missing; a click uses it", function()
    local BL = consumableWorld()
    DaylightUI:Set("Buffs", "settings.reminder.scrolls", true)
    local e = entry(BL.Reminder.Collect(), "scroll:strength")
    T.truthy(e)
    T.eq(e.macro, "/use [nocombat] item:10310")
    stub.SetAuras("player", "HELPFUL", { { name = "Strength", spellId = 12179 } })
    T.isnil(entry(BL.Reminder.Collect(), "scroll:strength"))
    stub.SetAuras("player", "HELPFUL", {})
    stub.bagItems[10310] = 0
    T.isnil(entry(BL.Reminder.Collect(), "scroll:strength"), "none carried")
end)

T.test("buffs reminder self: camp on: shows while the buff is missing", function()
    local BL = consumableWorld()
    DaylightUI:Set("Buffs", "settings.reminder.camp", true)
    T.truthy(entry(BL.Reminder.Collect(), "camp"))
    stub.SetAuras("player", "HELPFUL", { { name = "Camp Benefits", spellId = 1229741 } })
    T.isnil(entry(BL.Reminder.Collect(), "camp"))
end)

T.test("buffs reminder self: sleeping bag on: below max level, carried, under 3 stacks", function()
    local BL = consumableWorld()
    DaylightUI:Set("Buffs", "settings.reminder.sleepingBag", true)
    local e = entry(BL.Reminder.Collect(), "sleepingBag")
    T.truthy(e)
    T.eq(e.macro, "/use [nocombat] item:211527")
    stub.SetAuras("player", "HELPFUL", { { name = "Well Rested", spellId = 429959, applications = 2 } })
    T.truthy(entry(BL.Reminder.Collect(), "sleepingBag"), "two stacks: not yet")
    stub.SetAuras("player", "HELPFUL", { { name = "Well Rested", spellId = 429959, applications = 3 } })
    T.isnil(entry(BL.Reminder.Collect(), "sleepingBag"))
    stub.SetAuras("player", "HELPFUL", {})
    stub.units.player.level = 70
    T.isnil(entry(BL.Reminder.Collect(), "sleepingBag"), "at max level: no")
end)

-- A shaman's imbue lasts 5 minutes: it mustn't count as running low its whole life.
T.test("buffs reminder self: a fresh 5 minute imbue isn't running low; near its end it is", function()
    local BL = login(party("SHAMAN"), { known = { 8017 }, bags = true })
    stub.equipped[16] = { id = 1003, class = 2, subClass = 4 }
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, hasEnchant = true, enchantID = 29, enchantType = 3, timeLeft = 300000 } })
    T.isnil(entry(BL.Reminder.Collect(), "weapon:main"), "just put on")
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, hasEnchant = true, enchantID = 29, enchantType = 3, timeLeft = 240000 } })
    T.isnil(entry(BL.Reminder.Collect(), "weapon:main"), "4 of 5 minutes left: fine")
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, hasEnchant = true, enchantID = 29, enchantType = 3, timeLeft = 60000 } })
    T.truthy(entry(BL.Reminder.Collect(), "weapon:main"), "1 minute left: running low")
end)
