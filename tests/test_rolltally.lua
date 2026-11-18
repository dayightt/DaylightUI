local stub = require("stub")
local RW = require("rollworld")

-- Loot roll counts and tooltips (QoL/RollData.lua, RollTally.lua,
-- RollSample.lua), on the fake loot rolls of tests/rollworld.lua.

T.test("loot rolls world: the loot history lists each encounter's drops with their rolls", function()
    stub.Load({ before = RW.Install })
    RW.SetDrop(7, 2, { link = RW.SWORD, rolls = { { "Dusk", "ROGUE", "greed", 40 } } })
    RW.SetDrop(7, 1, { link = RW.CLOAK, rolls = { { "Brannoc", "WARRIOR", "need", 87, winner = true },
        { "Corvina", "PALADIN", "none", secret = { playerName = true } } } })
    local encounters = C_LootHistory.GetAllEncounterInfos()
    T.eq(#encounters, 1)
    T.eq(encounters[1].encounterID, 7)
    local drops = C_LootHistory.GetSortedDropsForEncounter(7)
    T.eq(#drops, 2, "both drops")
    T.eq(drops[1].lootListKey, 2, "in the order they were first set")
    local cloak = drops[2]
    T.eq(cloak.itemHyperlink, RW.CLOAK)
    T.eq(cloak.rollInfos[1].state, Enum.EncounterLootDropRollState.NeedMainSpec)
    T.eq(cloak.winner, cloak.rollInfos[1], "the winner's roll")
    T.truthy(issecretvalue(cloak.rollInfos[2].playerName), "a field the game keeps secret")
    T.eq(cloak.rollInfos[2].state, Enum.EncounterLootDropRollState.NoRoll)
end)

T.test("loot rolls world: a roll opens a popup, and its buttons show the game's own tooltip", function()
    stub.Load({ before = RW.Install })
    local started
    local f = CreateFrame("Frame")
    f:RegisterEvent("START_LOOT_ROLL")
    f:SetScript("OnEvent", function(_, _, id) started = id end)
    RW.Open({ rollID = 11, link = RW.CLOAK, canNeed = false })
    T.truthy(RW.Popup(1):IsShown())
    T.eq(started, 11, "START_LOOT_ROLL")
    T.eq(GetLootRollItemLink(11), RW.CLOAK)
    T.eq(GroupLootContainer.rollFrames[1], RW.Popup(1))
    T.deq(RW.LineTexts(RW.Hover(RW.Button(1, "need"))), { "Need", RW.CANT_NEED })
    RW.Unhover(RW.Button(1, "need"))
    T.deq(RW.Lines(), {}, "gone on leave")
    RW.Open({ rollID = 12, link = RW.SWORD, frame = 2, queued = true })
    T.eq(started, 11, "a popup from the queue sends no event")
    RW.Close(11)
    T.falsy(RW.Popup(1):IsShown())
end)

T.test("loot rolls world: the loot roll skin dresses the fake popups", function()
    stub.Load({ skins = true, before = RW.Install })
    stub.RunTimers()
    RW.Open({ rollID = 11, link = RW.CLOAK })
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local S = stub.skins
    T.truthy(S.LootRoll.Of(RW.Popup(1)), "the skin's pieces on it")
    T.eq(RW.Button(1, "need"):GetWidth(), S.LootRoll.BUTTON, "its buttons the skin's size")
end)

-- The data: drops read from the loot history, popups paired with drops, Tallies.

local function data()
    stub.Load({ qol = true, before = RW.Install })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    return stub.qol.RollData
end

local function needers(n)
    local rolls = {}
    for i = 1, n do rolls[i] = { "Needer" .. i, "WARRIOR", "need" } end
    return rolls
end

local function popup(rollID, link) return { rollID = rollID, link = link, itemID = tonumber(link:match("item:(%d+)")) } end

T.test("loot rolls data: drops in the history's order, each roll's choice, rows the game keeps secret left out", function()
    local D = data()
    RW.SetDrop(1, 2, { link = RW.SWORD, rolls = { { "Dusk", "ROGUE", "transmog", 20 } }, allPassed = true })
    RW.SetDrop(1, 1, { link = RW.CLOAK, rolls = {
        { "Brannoc", "WARRIOR", "need", 87, winner = true }, { "Corvina", "PALADIN", "offspec", 64, self = true },
        { "Garrow", "HUNTER", "none" }, { "Fenwick", "MAGE", "pass" },
        { "Isolde", "PRIEST", "need", 12, secret = { roll = true } }, { "Jory", "SHAMAN", "pass", secret = { isSelf = true } } } })
    RW.SetDrop(2, 1, { link = RW.CLOAK, rolls = needers(1) })
    local drops = D.Drops()
    local keys = {}
    for i, d in ipairs(drops) do keys[i] = d.key end
    T.deq(keys, { "1:1", "1:2", "2:1" }, "encounters in order, each one's drops by list ID")
    T.deq({ drops[1].inProgress, drops[2].inProgress, drops[3].inProgress }, { false, false, true }, "won, all passed, open")
    T.eq(drops[1].itemID, 21701)
    T.deq(drops[1].rows, {
        { name = "Brannoc", class = "WARRIOR", choice = "need", roll = 87, winner = true, isSelf = false },
        { name = "Corvina", class = "PALADIN", choice = "offspec", roll = 64, winner = false, isSelf = true },
        { name = "Garrow", class = "HUNTER", choice = "undecided", winner = false, isSelf = false },
        { name = "Fenwick", class = "MAGE", choice = "pass", winner = false, isSelf = false },
    })
    T.eq(drops[2].rows[1].choice, "greed", "Transmog counts as Greed")
end)

T.test("loot rolls data: no loot history in the client means no drops", function()
    local D = data()
    _G.C_LootHistory = nil
    T.deq(D.Drops(), {})
end)

T.test("loot rolls data: a Tally sorts by roll, highest first, then by name, and cuts each section at 15", function()
    local D = data()
    local rows = {
        { name = "Zed", choice = "greed" }, { name = "Abe", choice = "greed" }, { name = "Mia", choice = "greed", roll = 30 },
        { name = "Kit", choice = "greed", roll = 99 }, { name = "Lou", choice = "greed", roll = 30 },
        { name = "Bo", choice = "offspec", roll = 2 }, { name = "Cy", choice = "undecided" },
    }
    for i = 1, 20 do rows[#rows + 1] = { name = string.format("P%02d", i), choice = "pass", roll = i } end
    local tally = D.Tally(rows)
    local names = {}
    for i, r in ipairs(tally.greed.rows) do names[i] = r.name end
    T.deq(names, { "Kit", "Lou", "Mia", "Abe", "Zed" })
    T.deq({ tally.greed.total, tally.greed.more }, { 5, 0 })
    T.deq({ tally.need.total, tally.need.rows[1].name }, { 1, "Bo" }, "Off-spec Need counts as Need")
    T.deq({ tally.undecided.total, tally.undecided.rows[1].name }, { 1, "Cy" })
    T.deq({ #tally.pass.rows, tally.pass.total, tally.pass.more }, { 15, 20, 5 }, "cut at 15, the total kept")
    T.eq(tally.pass.rows[1].name, "P20")
end)

T.test("loot rolls data: identical items pair lowest roll ID with lowest drop, once every copy's drop is there", function()
    local D = data()
    local popups = { popup(12, RW.CLOAK), popup(11, RW.CLOAK) }
    RW.SetDrop(1, 2, { link = RW.CLOAK, rolls = needers(1) })
    T.deq(D.Pair(popups, D.Drops(), {}), {}, "one copy's history alone pairs neither")
    RW.SetDrop(1, 1, { link = RW.CLOAK, rolls = needers(2) })
    T.deq(D.Pair(popups, D.Drops(), {}), { [11] = "1:1", [12] = "1:2" })
end)

T.test("loot rolls data: the exact link wins over the same item with another suffix", function()
    local D = data()
    RW.SetDrop(1, 1, { link = RW.CLOAK, rolls = needers(2) })
    RW.SetDrop(1, 2, { link = RW.CLOAK_OF_THE_BEAR, rolls = needers(1) })
    T.deq(D.Pair({ popup(11, RW.CLOAK_OF_THE_BEAR), popup(12, RW.CLOAK) }, D.Drops(), {}), { [11] = "1:2", [12] = "1:1" })
end)

T.test("loot rolls data: a drop still being rolled for wins over a finished one of the same item", function()
    local D = data()
    RW.SetDrop(1, 1, { link = RW.CLOAK, rolls = { { "Brannoc", "WARRIOR", "need", 90, winner = true } } })
    RW.SetDrop(2, 1, { link = RW.CLOAK, rolls = needers(1) })
    T.deq(D.Pair({ popup(11, RW.CLOAK) }, D.Drops(), {}), { [11] = "2:1" })
end)

T.test("loot rolls data: a popup keeps its drop while it's rolled for, and no other popup takes it", function()
    local D = data()
    RW.SetDrop(1, 1, { link = RW.CLOAK, rolls = needers(2) })
    local paired = D.Pair({ popup(11, RW.CLOAK) }, D.Drops(), {})
    T.deq(paired, { [11] = "1:1" })
    paired = D.Pair({ popup(11, RW.CLOAK), popup(12, RW.CLOAK) }, D.Drops(), paired)
    T.deq(paired, { [11] = "1:1" }, "the second copy waits for its own drop")
    RW.SetDrop(1, 2, { link = RW.CLOAK, rolls = needers(3) })
    T.deq(D.Pair({ popup(11, RW.CLOAK), popup(12, RW.CLOAK) }, D.Drops(), paired), { [11] = "1:1", [12] = "1:2" })
end)
