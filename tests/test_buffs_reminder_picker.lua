local stub = require("stub")

-- The missing buffs action picker (DaylightUI_Buffs/ReminderPicker.lua on the
-- shared W.IconRing): right-click a class buff, a spell group, Well Fed or a
-- scroll to choose what its icon uses; scroll over a spell to choose its rank.
-- The picked mock-up: a ring round the cursor, 38 px cells, 34 px art, the
-- current pick ringed, a rank or bag count in each corner.

local RW = require("reminderworld")
local login, entry, settle = RW.Login, RW.Entry, RW.Settle

local function party(class)
    return { player = { name = "Me", class = class, level = 60 }, party1 = { name = "War", class = "WARRIOR" } }
end

local function picker(on) DaylightUI:Set("Buffs", "settings.reminder.picker", on) end

-- A hunter knowing Hawk ranks 1-3 and Cheetah.
local function hunter()
    local BL = login(party("HUNTER"), { known = { 13165, 14318, 14319, 5118 }, mine = false })
    for i, id in ipairs({ 13165, 14318, 14319 }) do stub.spells[id] = { name = "Aspect of the Hawk", rank = "Rank " .. i } end
    picker(true)
    BL.Reminder.Refresh(); settle()
    return BL
end

local function tileOf(BL, key)
    for _, t in ipairs(BL.ReminderRow.active) do if t.key == key then return t end end
end

local function rightClick(BL, key)
    local t = tileOf(BL, key)
    t:GetScript("OnMouseUp")(t, "RightButton")
    return DaylightUI.Widgets.IconRingOpen()
end

T.test("buffs reminder picker: off: right-click does nothing", function()
    local BL = hunter()
    picker(false)
    BL.Reminder.Refresh()
    T.isnil(rightClick(BL, "aspect"))
end)

T.test("buffs reminder picker: right-click a class buff with two known lines opens the ring", function()
    local BL = hunter()
    local ring = rightClick(BL, "aspect")
    T.truthy(ring, "open")
    T.eq(#ring.cells, 2, "Cheetah and Hawk")
    local c = ring.cells[1]
    T.eq(c:GetWidth(), 38); T.eq(c.art:GetWidth(), 34)
    local picked = 0
    for _, cell in ipairs(ring.cells) do if cell.ring:IsShown() then picked = picked + 1 end end
    T.eq(picked, 1, "the current pick ringed")
    T.eq(ring:GetFrameStrata(), "FULLSCREEN_DIALOG")
end)

T.test("buffs reminder picker: a pick is cast with its rank", function()
    local BL = hunter()
    local ring = rightClick(BL, "aspect")
    local cheetah
    for _, cell in ipairs(ring.cells) do if cell.key == 5118 then cheetah = cell end end
    cheetah:GetScript("OnClick")(cheetah, "LeftButton")
    stub.RunTimers()
    T.isnil(DaylightUI.Widgets.IconRingOpen(), "a pick closes it")
    local e = entry(BL.Reminder.Collect(), "aspect")
    T.eq(e.spell, 5118, "the Cheetah from now on")
    T.eq(DaylightUI:Get("Buffs", "settings.reminder.self.classActions").aspect.castSpellID, 5118)
end)

T.test("buffs reminder picker: wheel up steps to the higher rank, top rank clears the pin", function()
    local BL = hunter()
    local e = entry(BL.Reminder.Collect(), "aspect")
    T.eq(e.spell, 14319, "Hawk, its top rank")
    local ring = rightClick(BL, "aspect")
    local hawk
    for _, cell in ipairs(ring.cells) do if cell.key == 13165 then hawk = cell end end
    hawk:GetScript("OnMouseWheel")(hawk, -1)
    e = entry(BL.Reminder.Collect(), "aspect")
    T.eq(e.spell, 14318, "a rank down")
    T.eq(e.macro, "/cast [nocombat,@player] Aspect of the Hawk(Rank 2)")
    T.eq(hawk.badge:GetText(), "2", "the cell's rank badge")
    hawk:GetScript("OnMouseWheel")(hawk, 1)
    e = entry(BL.Reminder.Collect(), "aspect")
    T.eq(e.spell, 14319, "back at the top")
    T.eq(e.macro, "/cast [nocombat,@player] Aspect of the Hawk")
    local actions = DaylightUI:Get("Buffs", "settings.reminder.self.classActions").aspect
    T.isnil(actions.castRanks and actions.castRanks[13165], "the top rank clears the pin")
end)

T.test("buffs reminder picker: Well Fed pick eats it", function()
    local BL = login(party("WARRIOR"), { bags = true, mine = false })
    stub.spells[1248377] = { name = "Food" }
    stub.spells[19705] = { name = "Well Fed" }
    stub.bagSlots = { { id = 5001, count = 4 }, { id = 5002, count = 2 } }
    for id, lvl in pairs({ [5001] = 20, [5002] = 30 }) do
        stub.itemSpells[id] = { "Food", 1 }
        stub.itemInfo[id] = { minLevel = lvl, class = 0 }
        stub.bagItems[id] = 1
    end
    DaylightUI:Set("Buffs", "settings.reminder.items.wellFed", true)
    picker(true)
    BL.Reminder.Refresh(); settle()
    T.eq(entry(BL.Reminder.Collect(), "wellfed").item, 5002)
    local ring = rightClick(BL, "wellfed")
    T.eq(#ring.cells, 2)
    for _, cell in ipairs(ring.cells) do
        if cell.key == 5001 then
            T.eq(cell.badge:GetText(), "4", "the bag count")
            cell:GetScript("OnClick")(cell, "LeftButton")
        end
    end
    T.eq(entry(BL.Reminder.Collect(), "wellfed").item, 5001, "eats the picked one")
end)

T.test("buffs reminder picker: scrolls pick, auto clears it", function()
    local BL = login(party("WARRIOR"), { bags = true, mine = false })
    for _, s in ipairs(BL.ReminderData.STATS) do
        for _, it in ipairs(s.items) do stub.itemInfo[it[1]] = { minLevel = 1, class = 0 } end
    end
    stub.bagItems[10310] = 1
    stub.bagItems[954] = 1
    DaylightUI:Set("Buffs", "settings.reminder.items.stats.WARRIOR.strength", true)
    picker(true)
    BL.Reminder.Refresh(); settle()
    T.eq(entry(BL.Reminder.Collect(), "scrollsAndElixirs").item, 10310)
    local ring = rightClick(BL, "scrollsAndElixirs")
    local offered = {}
    for _, cell in ipairs(ring.cells) do offered[#offered + 1] = cell.key end
    table.sort(offered)
    T.deq(offered, { 954, 10310 }, "only the two scrolls in the bags, never one you don't carry")
    for _, cell in ipairs(ring.cells) do if cell.key == 954 then cell:GetScript("OnClick")(cell, "LeftButton") end end
    T.eq(entry(BL.Reminder.Collect(), "scrollsAndElixirs").item, 954, "the pinned one")
    BL.Reminder.Refresh(); settle()
    ring = rightClick(BL, "scrollsAndElixirs")
    for _, cell in ipairs(ring.cells) do if cell.key == 10310 then cell:GetScript("OnClick")(cell, "LeftButton") end end
    T.isnil(DaylightUI:Get("Buffs", "settings.reminder.items.statPick").WARRIOR, "the automatic one clears the pin")
end)

T.test("buffs reminder picker: closes in combat and when the pick goes stale", function()
    local BL = hunter()
    T.truthy(rightClick(BL, "aspect"))
    stub.EnterCombat()
    T.isnil(DaylightUI.Widgets.IconRingOpen(), "the pull closes it")
    stub.LeaveCombat()
    stub.RunTimers(); settle()
    T.truthy(rightClick(BL, "aspect"))
    stub.SetAuras("player", "HELPFUL", { { name = "Aspect of the Hawk", spellId = 14319, sourceUnit = "player" } })
    BL.Reminder.Refresh(); settle()
    T.isnil(DaylightUI.Widgets.IconRingOpen(), "its icon went away")
    stub.SetAuras("player", "HELPFUL", {})
    BL.Reminder.Refresh(); settle()
    local t = tileOf(BL, "aspect")
    stub.EnterCombat()
    t:GetScript("OnMouseUp")(t, "RightButton")
    T.isnil(DaylightUI.Widgets.IconRingOpen(), "never opens in a fight")
    stub.LeaveCombat()
end)

T.test("buffs reminder picker: the ring springs out round the cursor and a second ring takes more than eight", function()
    local BL = hunter()
    local W = DaylightUI.Widgets
    _G.GetCursorPosition = function() return 400, 300 end
    local items = {}
    for i = 1, 11 do items[i] = { key = i, icon = 134400, badge = tostring(i) } end
    local ring = W.IconRing({ items = items, onPick = function() end })
    T.eq(#ring.cells, 11)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 30)
    local far = 0
    for i, cell in ipairs(ring.cells) do
        local _, _, _, x, y = cell:GetPoint(1)
        local r = math.sqrt(x * x + y * y)
        if i <= 8 then T.near(r, W.ICON_RING.radius, 0.5, "the first eight on the inner ring") else far = far + 1; T.near(r, W.ICON_RING.radius + W.ICON_RING.step, 0.5) end
    end
    T.eq(far, 3)
    W.CloseIconRing()
    T.isnil(W.IconRingOpen())
end)
