local stub = require("stub")

-- Missing buffs, the Consumables section (DaylightUI_Buffs/ReminderItems.lua):
-- Camp Benefits, the sleeping bag and its sleep timer, Well Fed, the Arcane
-- Censer, scrolls and elixirs, as EllesmereUI's WoW Forever section works.

local RW = require("reminderworld")
local login, entry = RW.Login, RW.Entry

local function set(key, v) DaylightUI:Set("Buffs", "settings.reminder.items." .. key, v) end

local function world(class, opts)
    opts = opts or {}
    local BL = login({ player = { name = "Me", class = class or "WARRIOR", level = opts.level or 60 },
                       party1 = { name = "War", class = "WARRIOR" } },
                     { bags = true, known = opts.known, where = opts.where, mine = false })
    return BL
end

T.test("buffs reminder items: every consumable is off by default", function()
    local BL = world()
    local d = BL.DEFAULTS.settings.reminder.items
    T.falsy(d.camp or d.bag or d.wellFed or d.censer or d.oil)
    T.deq(d.stats, {})
    stub.bagItems[211527] = 1
    T.deq(RW.Keys(BL.Reminder.Collect()), {})
end)

T.test("buffs reminder items: camp by id, display only", function()
    local BL = world()
    set("camp", true)
    local e = entry(BL.Reminder.Collect(), "camp")
    T.truthy(e); T.isnil(e.macro, "nothing to click")
    T.eq(e.short, "Camp")
    stub.SetAuras("player", "HELPFUL", { { name = "Something Else", spellId = 1229741 } })
    T.isnil(entry(BL.Reminder.Collect(), "camp"), "read by its id")
end)

-- ---------------------------------------------------------------------
-- The sleeping bag
-- ---------------------------------------------------------------------

local function bagWorld()
    local BL = world("WARRIOR", { level = 20 })
    _G.GetMaxLevelForPlayerExpansion = function() return 60 end
    stub.bagItems[211527] = 1
    set("bag", true)
    return BL
end

T.test("buffs reminder items: sleeping bag: missing or under 3 stacks below max level; a click uses the bag", function()
    local BL = bagWorld()
    local e = entry(BL.Reminder.Collect(), "sleepingbag")
    T.truthy(e)
    T.eq(e.short, "Sleeping")
    T.eq(e.macro, "/use [nocombat] item:211527")
    stub.SetAuras("player", "HELPFUL", { { name = "Well Rested", spellId = 429959, applications = 2 } })
    T.truthy(entry(BL.Reminder.Collect(), "sleepingbag"), "two stacks: not yet")
    stub.SetAuras("player", "HELPFUL", { { name = "Well Rested", spellId = 429959, applications = 3 } })
    T.isnil(entry(BL.Reminder.Collect(), "sleepingbag"))
    stub.SetAuras("player", "HELPFUL", {})
    stub.units.player.level = 60
    T.isnil(entry(BL.Reminder.Collect(), "sleepingbag"), "at max level: never")
end)

T.test("buffs reminder items: sleeping bag: show below at 3 stacks", function()
    local BL = bagWorld()
    local now = GetTime()
    stub.SetAuras("player", "HELPFUL", { { name = "Well Rested", spellId = 429959, applications = 3, expirationTime = now + 240 } })
    T.isnil(entry(BL.Reminder.Collect(), "sleepingbag"), "Show Below 0: only under 3 stacks")
    set("bagBelow", 5)
    local e = entry(BL.Reminder.Collect(), "sleepingbag")
    T.near(e.expireAt, now + 240, 0.01, "4 of 5 minutes: its countdown")
end)

T.test("buffs reminder items: sleeping bag: the sleep timer counts to 3/3 and survives a /reload, not a login", function()
    local BL = bagWorld()
    stub.resting = true
    stub.SetAuras("player", "HELPFUL", { { name = "Sleeping", spellId = 1331671 },
                                         { name = "Well Rested", spellId = 429959, applications = 1 } })
    local list = BL.Reminder.Collect()
    T.deq(RW.Keys(list), { "sleepingbag" }, "resting: only the sleep timer")
    local e = list[1]
    T.eq(e.badge, "1/3")
    T.near(e.expireAt, GetTime() + 120, 0.01, "two stacks to go, a minute each")
    T.isnil(e.macro, "nothing to click while asleep")
    stub.Advance(30)
    stub.SetAuras("player", "HELPFUL", { { name = "Sleeping", spellId = 1331671 },
                                         { name = "Well Rested", spellId = 429959, applications = 2 } })
    e = BL.Reminder.Collect()[1]
    T.eq(e.badge, "2/3")
    T.near(e.expireAt, GetTime() + 60, 0.01, "a stack landed: counted again from now")
    -- A /reload keeps it.
    local ends = e.expireAt
    BL.Reminder.handlers.items("PLAYER_LOGOUT")
    BL.ReminderItems.ForgetSleep()
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    e = BL.Reminder.Collect()[1]
    T.near(e.expireAt, ends, 0.01, "after a /reload: the same countdown")
    -- A fresh login doesn't.
    BL.Reminder.handlers.items("PLAYER_LOGOUT")
    BL.ReminderItems.ForgetSleep()
    stub.Advance(10)
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    e = BL.Reminder.Collect()[1]
    T.near(e.expireAt, GetTime() + 60, 0.01, "a login starts it again")
    set("bagTimer", false)
    T.deq(RW.Keys(BL.Reminder.Collect()), {}, "timer off: nothing while resting")
    stub.resting = nil
end)

-- ---------------------------------------------------------------------
-- Well Fed
-- ---------------------------------------------------------------------

local function foodWorld()
    local BL = world("WARRIOR", { level = 40 })
    stub.spells[1248377] = { name = "Food" }
    stub.spells[19705] = { name = "Well Fed" }
    stub.bagSlots = { { id = 5001, count = 4 }, { id = 5002, count = 2 }, { id = 5003, count = 1 } }
    stub.itemSpells[5001] = { "Food", 111 }
    stub.itemSpells[5002] = { "Food", 112 }
    stub.itemSpells[5003] = { "Food", 113 }
    stub.itemInfo[5001] = { minLevel = 25, ilvl = 25, class = 0 }
    stub.itemInfo[5002] = { minLevel = 35, ilvl = 35, class = 0 }
    stub.itemInfo[5003] = { minLevel = 45, ilvl = 45, class = 0 }
    for id, n in pairs({ [5001] = 4, [5002] = 2, [5003] = 1 }) do stub.bagItems[id] = n end
    set("wellFed", true)
    return BL
end

T.test("buffs reminder items: Well Fed: click eats the best food for your level, else the one last eaten", function()
    local BL = foodWorld()
    local e = entry(BL.Reminder.Collect(), "wellfed")
    T.truthy(e)
    T.eq(e.short, "Well Fed")
    T.eq(e.item, 5002, "the highest food at or below level 40")
    T.eq(e.macro, "/use [nocombat] item:5002")
    T.eq(e.count, 2, "the bag count")
    -- Eating a 5001: its count drops, it's remembered.
    stub.bagSlots[1].count = 3; stub.bagItems[5001] = 3
    stub.FireEvent("BAG_UPDATE_DELAYED")
    T.eq(entry(BL.Reminder.Collect(), "wellfed").item, 5001, "the food this character last ate")
    stub.SetAuras("player", "HELPFUL", { { name = "Well Fed", spellId = 24799 } })
    T.isnil(entry(BL.Reminder.Collect(), "wellfed"))
    stub.SetAuras("player", "HELPFUL", { { name = "Nightfin Soup", spellId = 18194 } })
    T.isnil(entry(BL.Reminder.Collect(), "wellfed"), "a food buff with its own name, by id")
end)

T.test("buffs reminder items: Well Fed: no food in the bags: display only; show below", function()
    local BL = foodWorld()
    stub.bagSlots = {}
    for id in pairs(stub.bagItems) do stub.bagItems[id] = 0 end
    stub.FireEvent("BAG_UPDATE_DELAYED")
    local e = entry(BL.Reminder.Collect(), "wellfed")
    T.truthy(e); T.isnil(e.macro)
    local now = GetTime()
    stub.SetAuras("player", "HELPFUL", { { name = "Well Fed", spellId = 24799, expirationTime = now + 120 } })
    T.isnil(entry(BL.Reminder.Collect(), "wellfed"))
    set("wellFedBelow", 3)
    T.near(entry(BL.Reminder.Collect(), "wellfed").expireAt, now + 120, 0.01, "3 minutes of Show Below")
end)

-- ---------------------------------------------------------------------
-- The Arcane Censer
-- ---------------------------------------------------------------------

T.test("buffs reminder items: censer only in a dungeon with one in the bags", function()
    local BL = world()
    set("censer", true)
    T.isnil(entry(BL.Reminder.Collect(), "censer"), "none carried")
    stub.bagItems[281371] = 1
    local e = entry(BL.Reminder.Collect(), "censer")
    T.eq(e.item, 281371, "the Elemental Attractor does the same")
    T.eq(e.macro, "/use [nocombat] item:281371")
    stub.SetInstance(nil); stub.difficulty = 0
    T.isnil(entry(BL.Reminder.Collect(), "censer"), "the open world: no")
    stub.SetInstance("party"); stub.difficulty = 1
    stub.SetAuras("player", "HELPFUL", { { name = "Magical Awareness", spellId = 1297774 } })
    T.isnil(entry(BL.Reminder.Collect(), "censer"), "its buff up")
end)

-- ---------------------------------------------------------------------
-- Scrolls and elixirs
-- ---------------------------------------------------------------------

local function stat(class, key, on) DaylightUI:Set("Buffs", "settings.reminder.items.stats." .. class .. "." .. key, on) end

local function statWorld(class, known)
    local BL = world(class, { known = known, level = 60 })
    for _, s in ipairs(BL.ReminderData.STATS) do
        for _, it in ipairs(s.items) do stub.itemInfo[it[1]] = { minLevel = 1, class = 0 } end
        for _, it in ipairs(s.health and s.health.items or {}) do stub.itemInfo[it[1]] = { minLevel = 1, class = 0 } end
    end
    return BL
end

T.test("buffs reminder items: scrolls and elixirs: ticked stats only; one icon unless separate", function()
    local BL = statWorld("WARRIOR")
    stub.bagItems[10310] = 2     -- Scroll of Strength IV
    stub.bagItems[3012] = 1      -- Scroll of Agility I
    T.isnil(entry(BL.Reminder.Collect(), "scrollsAndElixirs"), "nothing ticked")
    stat("WARRIOR", "strength", true)
    stat("WARRIOR", "agility", true)
    local e = entry(BL.Reminder.Collect(), "scrollsAndElixirs")
    T.eq(e.item, 10310, "one icon, the first stat in order")
    T.eq(e.short, "Strength")
    T.eq(e.macro, "/use [@player,nocombat] item:10310")
    set("separate", true)
    local list = BL.Reminder.Collect()
    T.truthy(entry(list, "stat:strength")); T.truthy(entry(list, "stat:agility"), "one per stat")
    stub.SetAuras("player", "HELPFUL", { { name = "Strength", spellId = 12179 } })
    T.isnil(entry(BL.Reminder.Collect(), "stat:strength"), "its buff up")
end)

T.test("buffs reminder items: scrolls and elixirs: a locked stat (a mage knowing Arcane Intellect) never reminds", function()
    local BL = statWorld("MAGE", { 1459 })
    stub.bagItems[10308] = 1
    stat("MAGE", "intellect", true)
    T.isnil(entry(BL.Reminder.Collect(), "scrollsAndElixirs"))
    T.truthy(BL.ReminderItems.Locked("intellect", "MAGE"))
end)

T.test("buffs reminder items: scrolls and elixirs: a raid buff of the stat holds it back unless Show stronger buffs and the item beats it", function()
    local BL = statWorld("WARRIOR")
    stub.bagItems[10307] = 1     -- Scroll of Stamina IV (+16)
    stat("WARRIOR", "stamina", true)
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1244 } })
    T.isnil(entry(BL.Reminder.Collect(), "scrollsAndElixirs"), "Fortitude rank 2 up")
    set("stronger", true)
    T.eq(entry(BL.Reminder.Collect(), "scrollsAndElixirs").item, 10307, "+16 beats rank 2's +10")
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 10938 } })
    T.isnil(entry(BL.Reminder.Collect(), "scrollsAndElixirs"), "rank 6's +70 beats it")
end)

T.test("buffs reminder items: scrolls and elixirs: rank lowest, level requirement, show below, cooldown swipe", function()
    local BL = statWorld("WARRIOR")
    stub.bagItems[10310] = 1     -- Strength IV
    stub.bagItems[954] = 1       -- Strength I
    stat("WARRIOR", "strength", true)
    T.eq(entry(BL.Reminder.Collect(), "scrollsAndElixirs").item, 10310, "the strongest")
    set("statLowRank", true)
    T.eq(entry(BL.Reminder.Collect(), "scrollsAndElixirs").item, 954, "the weakest")
    set("statLowRank", false)
    stub.itemInfo[10310].minLevel = 70
    T.eq(entry(BL.Reminder.Collect(), "scrollsAndElixirs").item, 954, "too high a level: the next one")
    stub.itemCooldowns[954] = { GetTime() - 5, 60 }
    T.deq(entry(BL.Reminder.Collect(), "scrollsAndElixirs").cooldown, { GetTime() - 5, 60 }, "its cooldown swipes")
    local now = GetTime()
    stub.SetAuras("player", "HELPFUL", { { name = "Strength", spellId = 8118, expirationTime = now + 100 } })
    T.isnil(entry(BL.Reminder.Collect(), "scrollsAndElixirs"))
    set("statBelow", 2)
    T.near(entry(BL.Reminder.Collect(), "scrollsAndElixirs").expireAt, now + 100, 0.01)
end)

T.test("buffs reminder items: scrolls and elixirs: a camp's First Aid Kit skips Stamina", function()
    local BL = statWorld("WARRIOR")
    stub.spells[1307244] = { name = "First Aid Kit" }
    stub.bagItems[10307] = 1
    stat("WARRIOR", "stamina", true)
    T.truthy(entry(BL.Reminder.Collect(), "scrollsAndElixirs"))
    stub.SetAuras("player", "HELPFUL", { { name = "Camp Benefits", spellId = 1229741, auraInstanceID = 77, expirationTime = GetTime() + 600 } })
    _G.C_TooltipInfo = { GetUnitAuraByAuraInstanceID = function() return { lines = { { leftText = "First Aid Kit: heals you" } } } end }
    T.isnil(entry(BL.Reminder.Collect(), "scrollsAndElixirs"), "the camp's kit")
    _G.C_TooltipInfo = nil
end)
