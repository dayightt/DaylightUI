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
-- Class buffs and mage armors (Task 4), EllesmereUI's lists and rules
-- ---------------------------------------------------------------------

local function on(key, v) DaylightUI:Set("Buffs", "settings.reminder.self." .. key, v) end

T.test("buffs reminder self: class buffs: each class's list with his on defaults; unticked never reminds", function()
    local BL = login(party("PRIEST"), { known = { 588, 15473 } })
    T.truthy(entry(BL.Reminder.Collect(), "innerfire"), "Inner Fire on by default")
    T.isnil(entry(BL.Reminder.Collect(), "shadowform"), "Shadowform off by default")
    on("picks.shadowform", true)
    T.truthy(entry(BL.Reminder.Collect(), "shadowform"), "ticked: shown")
    on("picks.innerfire", false)
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "unticked: never")
    local D = BL.ReminderData.CLASS_BUFFS
    local keys = {}
    for class, list in pairs(D) do
        for _, b in ipairs(list) do keys[#keys + 1] = class .. ":" .. b.key .. "=" .. tostring(b.on == true) end
    end
    table.sort(keys)
    T.deq(keys, { "DRUID:thorns=false", "HUNTER:aspect=true", "HUNTER:trueshot=true", "PALADIN:blessing=true",
                  "PALADIN:paladinaura=true", "PALADIN:rfury=false", "PRIEST:innerfire=true", "PRIEST:shadowform=false",
                  "SHAMAN:shield=true", "WARLOCK:demonarmor=true" })
end)

T.test("buffs reminder self: a click casts the highest rank you know; the label is his short name", function()
    local BL = login(party("PRIEST"), { known = { 588, 7128, 602 } })
    local e = entry(BL.Reminder.Collect(), "innerfire")
    T.eq(e.kind, "self"); T.eq(e.section, "self")
    T.eq(e.spell, 602, "the highest rank known")
    T.eq(e.short, "Inner", "the first word, as his labels")
    T.truthy(e.macro:find("[nocombat", 1, true))
    stub.SetAuras("player", "HELPFUL", { { name = "Inner Fire", spellId = 588 } })
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "rank 1 up counts")
end)

T.test("buffs reminder self: own: another hunter's aspect reads absent", function()
    local BL = login(party("HUNTER"), { known = { 13165, 5118 } })
    T.truthy(entry(BL.Reminder.Collect(), "aspect"))
    stub.SetAuras("player", "HELPFUL", { { name = "Aspect of the Cheetah", spellId = 5118, sourceUnit = "player" } })
    T.isnil(entry(BL.Reminder.Collect(), "aspect"), "any line of yours")
    stub.SetAuras("player", "HELPFUL", { { name = "Aspect of the Pack", spellId = 13159, sourceUnit = "party1" } })
    T.truthy(entry(BL.Reminder.Collect(), "aspect"), "another hunter's aspect isn't yours")
end)

T.test("buffs reminder self: ownMemory: anyone's blessing holds it back, only yours is remembered", function()
    local BL = login(party("PALADIN"), { known = { 19742, 19740, 20217 } })
    T.truthy(entry(BL.Reminder.Collect(), "blessing"))
    stub.SetAuras("player", "HELPFUL", { { name = "Greater Blessing of Kings", spellId = 25898, sourceUnit = "party1" } })
    T.isnil(entry(BL.Reminder.Collect(), "blessing"), "another paladin's Greater Kings holds it back")
    T.isnil(DaylightUI.DB.Character().buffReminder.last.blessing, "not remembered")
    stub.SetAuras("player", "HELPFUL", { { name = "Blessing of Might", spellId = 19740, sourceUnit = "player" } })
    T.isnil(entry(BL.Reminder.Collect(), "blessing"))
    T.eq(DaylightUI.DB.Character().buffReminder.last.blessing, 3, "your Might remembered")
    stub.SetAuras("player", "HELPFUL", {})
    T.eq(entry(BL.Reminder.Collect(), "blessing").spell, 19740, "the click casts Might, last seen")
end)

T.test("buffs reminder self: absence only (no running low)", function()
    local BL = login(party("PRIEST"), { known = { 588 } })
    local now = GetTime()
    stub.SetAuras("player", "HELPFUL", { { name = "Inner Fire", spellId = 588, duration = 1800, expirationTime = now + 30 } })
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "30 s left: still up")
    T.isnil(BL.Reminder.nextLook, "nothing armed")
end)

T.test("buffs reminder self: fallback = the strongest (last) line known: a mage with nothing seen casts Mage Armor", function()
    local BL = login(party("MAGE"), { known = { 168, 7300, 7302, 7320, 6117 } })
    T.isnil(entry(BL.Reminder.Collect(), "magearmor"), "mage armors off by default")
    T.eq(BL.DEFAULTS.settings.reminder.self.mageArmor, false)
    on("mageArmor", true)
    local e = entry(BL.Reminder.Collect(), "magearmor")
    T.eq(e.spell, 6117, "nothing seen yet: the strongest line, Mage Armor")
    T.eq(e.short, "Armor")
    stub.SetAuras("player", "HELPFUL", { { name = "Ice Armor", spellId = 7320 } })
    T.isnil(entry(BL.Reminder.Collect(), "magearmor"), "Ice Armor up")
    stub.SetAuras("player", "HELPFUL", {})
    e = entry(BL.Reminder.Collect(), "magearmor")
    T.eq(e.spell, 7320, "the line last seen up, its highest rank")
    T.eq(DaylightUI.DB.Character().buffReminder.mageArmor, 2, "kept for this character")
end)

T.test("buffs reminder self: a spell not learned yet: no icon", function()
    local BL = login(party("WARLOCK"))
    T.isnil(entry(BL.Reminder.Collect(), "demonarmor"))
    stub.knownSpells[687] = true
    T.truthy(entry(BL.Reminder.Collect(), "demonarmor"))
end)

T.test("buffs reminder self: under a restriction your own buff shows only when the client says it's readable", function()
    local BL = login(party("PRIEST"), { known = { 588 } })
    stub.SetRestriction("Map", true)
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "unknown: no icon")
    stub.SetRestriction("Map", false)
end)

T.test("buffs reminder self: where to show and PvP: the self section's places", function()
    local BL = login(party("PRIEST"), { known = { 588 } })
    on("where.dungeon", false)
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "dungeons unticked")
    on("where.dungeon", true)
    stub.SetInstance("pvp"); stub.difficulty = 0
    T.isnil(entry(BL.Reminder.Collect(), "innerfire"), "not in PvP")
end)

-- Hunter Target Tracking: in a fight, the tracking for the target's kind.
local function hunterWorld(known)
    local BL = login(party("HUNTER"), { known = known })
    on("hunterTracking", true)
    stub.tracking = {}
    for i, id in ipairs(BL.ReminderData.TRACKING) do
        stub.tracking[i] = { spellID = id, type = "spell", active = false, name = "Track " .. i }
    end
    stub.units.target = { name = "Wolf", attackable = true, creatureType = "Beast", creatureTypeID = 1 }
    return BL
end

T.test("buffs reminder self: target tracking: a hostile beast target, Track Beasts known and off, in a fight: shown, no click; plain creature type", function()
    local BL = hunterWorld({ 1494 })
    T.isnil(entry(BL.Reminder.Collect(), "huntertracking"), "out of combat: none")
    stub.EnterCombat()
    local e = entry(BL.Reminder.Collect(), "huntertracking")
    T.truthy(e, "in a fight")
    T.eq(e.kind, "track"); T.eq(e.spell, 1494)
    T.isnil(e.macro, "no click")
    stub.tracking[1].active = true
    stub.FireEvent("MINIMAP_UPDATE_TRACKING")
    T.isnil(entry(BL.Reminder.Collect(), "huntertracking"), "already tracking beasts")
    stub.tracking[1].active = false
    stub.FireEvent("MINIMAP_UPDATE_TRACKING")
    stub.units.target.creatureTypeID = 7
    T.isnil(entry(BL.Reminder.Collect(), "huntertracking"), "a humanoid: Track Humanoids not known")
    stub.units.target.creatureTypeID = 1
    stub.units.target.attackable = false
    T.isnil(entry(BL.Reminder.Collect(), "huntertracking"), "a friend: none")
    stub.LeaveCombat()
end)

T.test("buffs reminder self: target tracking: its events only while it can show", function()
    local BL = hunterWorld({ 1494 })
    BL.Reminder.Refresh()
    local ev = BL.Reminder.events
    T.truthy(ev:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    T.truthy(ev:IsEventRegistered("MINIMAP_UPDATE_TRACKING"))
    on("hunterTracking", false)
    BL.Reminder.Refresh()
    T.falsy(ev:IsEventRegistered("PLAYER_TARGET_CHANGED"), "off: not watched")
end)

T.test("buffs reminder self: secret creature type: the strip's value is set, nothing compared", function()
    local BL = hunterWorld({ 1494, 19883 })
    stub.units.target.creatureTypeID = stub.Secret(7)
    stub.EnterCombat()
    local e
    T.noerror(function() e = entry(BL.Reminder.Collect(), "huntertracking") end)
    T.truthy(e, "shown without knowing the kind")
    T.truthy(e.secretType ~= nil)
    BL.ReminderRow.Set({ e })
    local t = BL.ReminderRow.active[1]
    T.truthy(t.strip and t.strip:IsShown(), "the strip of seven")
    T.eq(stub.Plain(t.strip.bar:GetValue()), 7, "the client picks the column")
    T.falsy(t.icon:IsShown(), "the plain icon gives way")
    stub.LeaveCombat()
end)

-- ---------------------------------------------------------------------
-- Weapons (Task 5): imbues and poisons in Self Buffs, stones and oils in
-- Consumables, each hand on its own, EllesmereUI's picks and rules
-- ---------------------------------------------------------------------

local IMBUE, TEMP = 3, 2

local function weapons(class, known)
    local BL = login(party(class), { bags = true, known = known })
    stub.equipped[16] = { id = 1001, class = 2, subClass = 15 } -- a dagger
    stub.equipped[17] = { id = 1002, class = 2, subClass = 15 }
    return BL
end

local function hands(class, key, v) DaylightUI:Set("Buffs", "settings.reminder.hands." .. class .. "." .. key, v) end
local function item(key, v) DaylightUI:Set("Buffs", "settings.reminder.items." .. key, v) end

T.test("buffs reminder weapons: imbues and stones are off by default", function()
    local BL = weapons("ROGUE")
    stub.bagItems[6949] = 5
    stub.bagItems[2862] = 5
    T.deq(only(BL.Reminder.Collect(), "weapon"), {})
    T.eq(BL.DEFAULTS.settings.reminder.self.imbue, false)
    T.eq(BL.DEFAULTS.settings.reminder.items.oil, false)
end)

T.test("buffs reminder weapons: imbue and temp read apart: a rogue with a stone on is still reminded of poison", function()
    local BL = weapons("ROGUE")
    on("imbue", true)
    item("oil", true)
    stub.bagItems[6949] = 5      -- Instant Poison II
    stub.bagItems[2862] = 5      -- Rough Sharpening Stone
    local list = only(BL.Reminder.Collect(), "weapon")
    T.deq(keys(list), { "weapon_mh_imbue", "weapon_oh_imbue", "weapon_mh_temp", "weapon_oh_temp" })
    T.eq(list[1].section, "self"); T.eq(list[3].section, "items")
    T.eq(list[1].item, 6949)
    T.eq(list[1].macro, "/use [nocombat] item:6949\n/use 16", "the poison, then the hand's slot")
    T.eq(list[2].macro, "/use [nocombat] item:6949\n/use 17")
    T.eq(list[1].short, "Main"); T.eq(list[2].short, "Off")
    T.eq(list[1].count, 5, "the bag count")
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, enchantID = 1, enchantType = TEMP, timeLeft = 1800000 } })
    T.deq(keys(only(BL.Reminder.Collect(), "weapon")), { "weapon_mh_imbue", "weapon_oh_imbue", "weapon_oh_temp" },
          "a stone on the main hand: still no poison there")
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, enchantID = 7, enchantType = IMBUE, timeLeft = 1800000 },
                             { slot = Enum.WeaponSlot.MainHand, enchantID = 1, enchantType = TEMP, timeLeft = 1800000 } })
    T.deq(keys(only(BL.Reminder.Collect(), "weapon")), { "weapon_oh_imbue", "weapon_oh_temp" })
end)

T.test("buffs reminder weapons: per-hand picks: Off, a named poison, Auto", function()
    local BL = weapons("ROGUE")
    on("imbue", true)
    stub.bagItems[6949] = 5      -- Instant
    stub.bagItems[2893] = 3      -- Deadly II
    T.eq(entry(BL.Reminder.Collect(), "weapon_mh_imbue").item, 6949, "Auto: the first kind you carry, Instant")
    hands("ROGUE", "mhImbue", "deadly")
    T.eq(entry(BL.Reminder.Collect(), "weapon_mh_imbue").item, 2893, "named: Deadly")
    hands("ROGUE", "ohImbue", "off")
    T.isnil(entry(BL.Reminder.Collect(), "weapon_oh_imbue"), "Off: nothing for that hand")
end)

T.test("buffs reminder weapons: rank to use lowest", function()
    local BL = weapons("ROGUE")
    on("imbue", true)
    stub.bagItems[6947] = 1      -- Instant I
    stub.bagItems[8928] = 1      -- Instant VI
    T.eq(entry(BL.Reminder.Collect(), "weapon_mh_imbue").item, 8928, "the highest you carry")
    on("lowRank", true)
    T.eq(entry(BL.Reminder.Collect(), "weapon_mh_imbue").item, 6947, "the lowest")
end)

T.test("buffs reminder weapons: hide when none in bags off: a named item you lack shows gray, red 0, no click", function()
    local BL = weapons("ROGUE")
    on("imbue", true)
    hands("ROGUE", "mhImbue", "wound")
    T.isnil(entry(BL.Reminder.Collect(), "weapon_mh_imbue"), "hidden by default")
    on("hideNoItem", false)
    local e = entry(BL.Reminder.Collect(), "weapon_mh_imbue")
    T.truthy(e, "shown")
    T.eq(e.count, 0); T.isnil(e.macro, "no click")
    T.eq(e.tipItem, 10922, "the last listed one's icon and tooltip")
    T.isnil(entry(BL.Reminder.Collect(), "weapon_oh_imbue"), "Auto never picks what you don't have")
end)

T.test("buffs reminder weapons: a shaman's Auto is the first imbue he lists that you know; a click casts it", function()
    local BL = weapons("SHAMAN", { 8017, 8018, 8024 })
    stub.equipped[17] = nil
    on("imbue", true)
    local e = entry(BL.Reminder.Collect(), "weapon_mh_imbue")
    T.eq(e.spell, 8024, "Flametongue comes before Rockbiter in his list")
    T.eq(e.macro, "/cast [nocombat] Flametongue Weapon")
end)

T.test("buffs reminder weapons: warlock with no Firestone: Create Firestone", function()
    local BL = weapons("WARLOCK", { 6366 })
    stub.equipped[17] = nil
    on("imbue", true)
    local e = entry(BL.Reminder.Collect(), "weapon_mh_imbue")
    T.eq(e.spell, 6366, "Create Firestone")
    stub.bagItems[1254] = 1
    e = entry(BL.Reminder.Collect(), "weapon_mh_imbue")
    T.eq(e.item, 1254, "carried: use it")
end)

T.test("buffs reminder weapons: fishing pole and shield skipped; a stone fits the weapon's edge", function()
    local BL = weapons("WARRIOR")
    item("oil", true)
    stub.equipped[16] = { id = 1004, class = 2, subClass = 20 } -- a fishing pole
    stub.equipped[17] = { id = 1005, class = 4, subClass = 6 }  -- a shield
    stub.bagItems[2862] = 2 -- a sharpening stone: blades only
    stub.bagItems[3239] = 2 -- a weightstone: blunt only
    T.deq(only(BL.Reminder.Collect(), "weapon"), {}, "nothing for a fishing pole or a shield")
    stub.equipped[16] = { id = 1006, class = 2, subClass = 4 } -- a mace
    local e = entry(BL.Reminder.Collect(), "weapon_mh_temp")
    T.eq(e.item, 3239, "the weightstone for a mace")
end)

T.test("buffs reminder weapons: show below 1 min: countdown; 0: only once it has run out", function()
    local BL = weapons("MAGE")
    stub.equipped[17] = nil
    item("oil", true)
    stub.bagItems[20750] = 1
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, enchantID = 2, enchantType = TEMP, timeLeft = 90000 } })
    T.isnil(entry(BL.Reminder.Collect(), "weapon_mh_temp"), "90 s left: fine (Show Below 1 min)")
    T.near(BL.Reminder.nextLook, GetTime() + 30, 0.01, "looks again at the crossing")
    stub.SetWeaponEnchants({ { slot = Enum.WeaponSlot.MainHand, enchantID = 2, enchantType = TEMP, timeLeft = 40000 } })
    local e = entry(BL.Reminder.Collect(), "weapon_mh_temp")
    T.near(e.expireAt, GetTime() + 40, 0.01, "its countdown")
    BL.Reminder.Refresh()
    local t
    for _, x in ipairs(BL.ReminderRow.active) do if x.key == "weapon_mh_temp" then t = x end end
    T.truthy(t.time:IsShown())
    T.rgb({ t.time:GetTextColor() }, DaylightUI.Style.INK.WARN)
    on("weaponBelow", 0)
    T.isnil(entry(BL.Reminder.Collect(), "weapon_mh_temp"), "0: only once it has run out")
end)

T.test("buffs reminder weapons: the bag event only while a weapon or item reminder is on", function()
    local BL = weapons("MAGE")
    BL.Reminder.Refresh()
    T.falsy(BL.Reminder.events:IsEventRegistered("BAG_UPDATE_DELAYED"), "off: not watched")
    item("oil", true)
    stub.RunTimers()
    T.truthy(BL.Reminder.events:IsEventRegistered("BAG_UPDATE_DELAYED"))
    T.truthy(BL.Reminder.events:IsEventRegistered("WEAPON_ENCHANT_CHANGED"))
end)

-- ---------------------------------------------------------------------
-- Demonic Sacrifice, gathering tracking, Find Treasure (Task 6)
-- ---------------------------------------------------------------------

local function warlock(known)
    local BL = login(party("WARLOCK"), { known = known or { 18788, 688, 697 } })
    on("sacrifice", true)
    return BL
end

T.test("buffs reminder self: sacrifice: with 18788, no buff: imp out -> click sacrifices; no pet -> click summons the imp; a picked demon", function()
    local BL = warlock()
    T.eq(BL.DEFAULTS.settings.reminder.self.sacrifice, false, "off by default")
    local e = entry(BL.Reminder.Collect(), "demonicsacrifice")
    T.eq(e.spell, 688, "no pet: summon the Imp")
    stub.units.pet = { name = "Imp", family = "Imp", familyID = 23 }
    e = entry(BL.Reminder.Collect(), "demonicsacrifice")
    T.eq(e.spell, 18788, "the Imp is out: sacrifice it")
    stub.units.pet = { name = "Void", family = "Voidwalker", familyID = 16 }
    T.eq(entry(BL.Reminder.Collect(), "demonicsacrifice").spell, 18788, "Auto: the demon that is out")
    on("demon", "imp")
    T.eq(entry(BL.Reminder.Collect(), "demonicsacrifice").spell, 688, "the Imp picked: summon it first")
    stub.SetAuras("player", "HELPFUL", { { name = "Burning Wish", spellId = 18789 } })
    T.isnil(entry(BL.Reminder.Collect(), "demonicsacrifice"), "the Imp's buff up")
    on("demon", "voidwalker")
    T.truthy(entry(BL.Reminder.Collect(), "demonicsacrifice"), "the Voidwalker's is wanted")
    on("demon", "auto")
    T.isnil(entry(BL.Reminder.Collect(), "demonicsacrifice"), "Auto: any sacrifice buff counts")
end)

T.test("buffs reminder self: sacrifice: no talent, nothing; a secret pet family, nothing", function()
    local BL = warlock({ 688 })
    T.isnil(entry(BL.Reminder.Collect(), "demonicsacrifice"), "no Demonic Sacrifice")
    stub.knownSpells[18788] = true
    stub.units.pet = { name = "Imp", family = stub.Secret("Imp"), familyID = stub.Secret(23) }
    local list
    T.noerror(function() list = BL.Reminder.Collect() end)
    T.isnil(entry(list, "demonicsacrifice"), "which demon is out is unknown: nothing offered")
end)

local function trackers(BL, list)
    stub.tracking = {}
    for i, t in ipairs(list) do stub.tracking[i] = { spellID = t[1], type = "spell", active = t[2], name = "T" .. i } end
    stub.FireEvent("MINIMAP_UPDATE_TRACKING")
end

T.test("buffs reminder self: gathering: no Find Herbs/Minerals aura, knows Herbs: casts Herbs first", function()
    stub.spells[2383] = { name = "Find Herbs" }
    stub.spells[2580] = { name = "Find Minerals" }
    local BL = login(party("WARRIOR"), { known = { 2383, 2580 } })
    stub.spells[2383] = { name = "Find Herbs" }
    stub.spells[2580] = { name = "Find Minerals" }
    T.isnil(entry(BL.Reminder.Collect(), "gather"), "off by default")
    on("gather", true)
    local e = entry(BL.Reminder.Collect(), "gather")
    T.eq(e.spell, 2383, "Herbs first")
    stub.SetAuras("player", "HELPFUL", { { name = "Find Minerals", spellId = 2580 } })
    T.isnil(entry(BL.Reminder.Collect(), "gather"), "Find Minerals up")
end)

T.test("buffs reminder self: gathering: class tracking active hides it (option on)", function()
    local BL = login(party("HUNTER"), { known = { 2383, 1494 } })
    on("gather", true)
    trackers(BL, { { 1494, true }, { 2481, false } })
    T.isnil(entry(BL.Reminder.Collect(), "gather"), "Track Beasts on")
    on("gatherClassTrack", false)
    T.truthy(entry(BL.Reminder.Collect(), "gather"), "option off: shown anyway")
    on("gatherClassTrack", true)
    trackers(BL, { { 1494, false }, { 2481, true } })
    T.truthy(entry(BL.Reminder.Collect(), "gather"), "Find Treasure doesn't count as class tracking")
end)

T.test("buffs reminder self: treasure: a dwarf with 2481 off on the minimap", function()
    local BL = login(party("WARRIOR"), { known = { 2481 } })
    on("treasure", true)
    trackers(BL, { { 2481, false } })
    local e = entry(BL.Reminder.Collect(), "treasure")
    T.truthy(e)
    T.eq(e.spell, 2481)
    trackers(BL, { { 2481, true } })
    T.isnil(entry(BL.Reminder.Collect(), "treasure"), "on")
    stub.knownSpells[2481] = nil
    trackers(BL, { { 2481, false } })
    T.isnil(entry(BL.Reminder.Collect(), "treasure"), "not a dwarf")
end)


-- ---------------------------------------------------------------------
-- Custom spells and spell groups (Task 7)
-- ---------------------------------------------------------------------

T.test("buffs reminder self: custom: a typed id reminds while no rank of its name is up; unticked class: not", function()
    local BL = login(party("MAGE"), { known = { 7777 } })
    stub.spells[7777] = { name = "Frost Ward" }
    stub.spells[8888] = { name = "Frost Ward" }
    local S = BL.ReminderSelf
    T.eq(S.AddCustom("7777"), true)
    local e = entry(BL.Reminder.Collect(), "custom:7777")
    T.truthy(e, "missing: shown")
    T.eq(e.section, "self")
    T.eq(e.short, "Frost")
    T.eq(e.macro, "/cast [nocombat,@player] Frost Ward", "cast by name: the highest rank")
    stub.SetAuras("player", "HELPFUL", { { name = "Frost Ward", spellId = 8888 } })
    T.isnil(entry(BL.Reminder.Collect(), "custom:7777"), "another rank of its name is up")
    stub.SetAuras("player", "HELPFUL", {})
    S.SetCustomClass(7777, "MAGE", false)
    T.isnil(entry(BL.Reminder.Collect(), "custom:7777"), "unticked for mages")
    S.SetCustomClass(7777, "MAGE", true)
    T.truthy(entry(BL.Reminder.Collect(), "custom:7777"))
    stub.knownSpells[7777] = nil
    e = entry(BL.Reminder.Collect(), "custom:7777")
    T.truthy(e, "not known: still shown")
    T.isnil(e.macro, "display only")
    T.eq(S.RemoveCustom(7777), true)
    T.isnil(entry(BL.Reminder.Collect(), "custom:7777"))
end)

T.test("buffs reminder self: custom: unknown id refused; digits only; no duplicates", function()
    local BL = login(party("MAGE"))
    stub.spells[7777] = { name = "Frost Ward" }
    local S = BL.ReminderSelf
    T.eq(S.AddCustom("abc"), false, "not a number")
    T.eq(S.AddCustom("123456789"), false, "the client doesn't know it")
    T.eq(S.AddCustom("7777"), true)
    T.eq(S.AddCustom("7777"), false, "already there")
    T.deq(DaylightUI:Get("Buffs", "settings.reminder.self.custom.ids"), { 7777 })
end)

T.test("buffs reminder self: custom: a custom Fortitude id counts Prayer of Fortitude", function()
    local BL = login(party("PRIEST"), { known = { 1243 } })
    BL.ReminderSelf.AddCustom("1243")
    T.truthy(entry(BL.Reminder.Collect(), "custom:1243"))
    stub.SetAuras("player", "HELPFUL", { { name = "Prayer of Fortitude", spellId = 21564 } })
    T.isnil(entry(BL.Reminder.Collect(), "custom:1243"), "the group version counts")
end)

T.test("buffs reminder self: custom: a ticked class buff covering it stands it down", function()
    local BL = login(party("PRIEST"), { known = { 588 } })
    BL.ReminderSelf.AddCustom("588")
    T.isnil(entry(BL.Reminder.Collect(), "custom:588"), "Inner Fire is a ticked class buff")
    T.truthy(entry(BL.Reminder.Collect(), "innerfire"), "shown once, as the class buff")
    DaylightUI:Set("Buffs", "settings.reminder.self.picks.innerfire", false)
    T.truthy(entry(BL.Reminder.Collect(), "custom:588"), "unticked: the custom one is back")
end)

T.test("buffs reminder self: groups: shows while none of its members is up, only for a character that knows one", function()
    local BL = login(party("MAGE"), { known = { 6143 } })
    stub.spells[6143] = { name = "Frost Ward" }
    stub.spells[543] = { name = "Fire Ward" }
    local S = BL.ReminderSelf
    S.NewGroup("Wards")
    S.AddToGroup(1, "543")
    S.AddToGroup(1, "6143")
    local e = entry(BL.Reminder.Collect(), "g1")
    T.truthy(e, "neither ward up")
    T.eq(e.short, "Wards", "the group's name")
    T.eq(e.spell, 6143, "the first member you know")
    stub.SetAuras("player", "HELPFUL", { { name = "Fire Ward", spellId = 543 } })
    T.isnil(entry(BL.Reminder.Collect(), "g1"), "one member up")
    stub.SetAuras("player", "HELPFUL", {})
    stub.knownSpells[6143] = nil
    T.isnil(entry(BL.Reminder.Collect(), "g1"), "knows none: a group made on another class shows nothing")
end)

T.test("buffs reminder self: groups: rename, remove a member, remove the group", function()
    local BL = login(party("MAGE"), { known = { 6143 } })
    stub.spells[6143] = { name = "Frost Ward" }
    local S = BL.ReminderSelf
    S.NewGroup("Wards")
    S.AddToGroup(1, "6143")
    S.RenameGroup(1, "My wards")
    T.eq(entry(BL.Reminder.Collect(), "g1").short, "My wards")
    T.eq(S.AddToGroup(1, "99999999"), false, "unknown id refused")
    S.RemoveFromGroup(1, 6143)
    T.isnil(entry(BL.Reminder.Collect(), "g1"), "no members: nothing")
    S.RemoveGroup(1)
    T.deq(DaylightUI:Get("Buffs", "settings.reminder.self.groups"), {})
end)
