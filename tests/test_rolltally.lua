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

-- What a player sees on the game's popups. Each test runs on the plain popups
-- and again with the loot roll skin on.

local function both(name, fn)
    T.test("loot rolls: " .. name, function() fn(false) end)
    T.test("loot rolls: " .. name .. " (loot roll skin)", function() fn(true) end)
end

local function login(skins, before)
    stub.Load({ qol = true, skins = skins, before = function()
        RW.Install()
        if before then before() end
    end })
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end

local function settle()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end

local function set(key, value) DaylightUI:Set("QoL", key, value) end

-- The counts a player reads on popup i.
local function counts(i)
    return { need = (RW.Count(RW.Button(i, "need"))), greed = (RW.Count(RW.Button(i, "greed"))),
        pass = (RW.Count(RW.Button(i, "pass"))) }
end

local function hover(i, kind) return RW.Hover(RW.Button(i, kind or "need")) end
local function texts(lines) return RW.LineTexts(lines) end

-- A cloak on popup 1 with these rolls.
local function rolling(skins, rolls, spec)
    login(skins)
    local s = { rollID = 11, link = RW.CLOAK }
    for k, v in pairs(spec or {}) do s[k] = v end
    RW.Open(s)
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = rolls })
    settle()
end

local BUSY = {
    { "Brannoc", "WARRIOR", "need", 87, winner = true }, { "Corvina", "PALADIN", "offspec", 64 },
    { "Isolde", "PRIEST", "need", 12, self = true }, { "Dusk", "ROGUE", "greed" }, { "Eldra", "DRUID", "greed" },
    { "Fenwick", "MAGE", "pass" }, { "Garrow", "HUNTER", "none" }, { "Aelwyn", "MAGE", "none" },
}

local function hex(c) return DaylightUI.Win.Parts.Hex(c) end
local function ink(role) return DaylightUI.Style.INK[role] end
local function classColor(class) return { DaylightUI.Style.ClassTextColor(class) } end

-- The color a player sees `word` in, within a line drawn in `base`: |cAARRGGBB
-- sets the color and |r goes back to the line's own, as the game draws it.
local function colorOf(text, word, base)
    local at = RW.Plain(text):find(word, 1, true)
    assert(at, "no " .. word .. " in " .. RW.Plain(text))
    local color, seen, i = hex(base), 0, 1
    while i <= #text do
        local code = text:match("^|c(%x%x%x%x%x%x%x%x)", i)
        if code then
            color, i = "|cff" .. code:sub(3):lower(), i + 10
        elseif text:sub(i, i + 1) == "|r" then
            color, i = hex(base), i + 2
        else
            seen = seen + 1
            if seen == at then return color end
            i = i + 1
        end
    end
end

-- The first line whose plain text is `text`.
local function line(lines, text)
    for _, l in ipairs(lines) do
        if RW.Plain(l.text) == text then return l end
    end
    error("no line " .. text .. " in " .. table.concat(texts(lines), " / "), 2)
end

-- Counts

both("each button counts the players who picked its choice, Off-spec Need on the Need button", function(skins)
    rolling(skins, BUSY)
    T.deq(counts(1), { need = "3", greed = "2", pass = "1" })
end)

both("a choice nobody picked shows no count, never a 0", function(skins)
    rolling(skins, { { "Brannoc", "WARRIOR", "need" }, { "Garrow", "HUNTER", "none" } })
    T.deq(counts(1), { need = "1", greed = "", pass = "" })
end)

both("counts stay blank until the drop's history arrives, then fill in and follow each pick", function(skins)
    login(skins)
    RW.Open({ rollID = 11, link = RW.CLOAK })
    settle()
    T.deq(counts(1), { need = "", greed = "", pass = "" }, "before the history")
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = { { "Dusk", "ROGUE", "greed" }, { "Garrow", "HUNTER", "none" } } })
    settle()
    T.deq(counts(1), { need = "", greed = "1", pass = "" }, "once it arrives")
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = { { "Dusk", "ROGUE", "greed" }, { "Garrow", "HUNTER", "greed" } } })
    settle()
    T.deq(counts(1), { need = "", greed = "2", pass = "" }, "after another pick")
end)

both("each popup counts its own item, and one whose drop never shows up stays blank", function(skins)
    login(skins)
    RW.Open({ rollID = 11, link = RW.CLOAK, frame = 1 })
    RW.Open({ rollID = 12, link = RW.SWORD, frame = 2 })
    RW.Open({ rollID = 13, link = RW.RING, frame = 3 })
    RW.UpdateDrop(1, 1, { link = RW.SWORD, rolls = needers(4) })
    RW.UpdateDrop(1, 2, { link = RW.CLOAK, rolls = BUSY })
    RW.UpdateDrop(1, 3, { link = RW.SWORD, rolls = needers(1), allPassed = true })
    settle()
    T.deq(counts(1), { need = "3", greed = "2", pass = "1" }, "the cloak")
    T.deq(counts(2), { need = "4", greed = "", pass = "" }, "the sword")
    T.deq(counts(3), { need = "", greed = "", pass = "" }, "the ring: its drop never came")
end)

both("two identical cloaks drop and the second drop's history arrives first", function(skins)
    login(skins)
    RW.Open({ rollID = 11, link = RW.CLOAK, frame = 1 })
    RW.Open({ rollID = 12, link = RW.CLOAK, frame = 2 })
    RW.UpdateDrop(1, 2, { link = RW.CLOAK, rolls = needers(1) })
    settle()
    T.deq({ counts(1).need, counts(2).need }, { "", "" }, "while only the second drop is known")
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = needers(2) })
    settle()
    T.deq({ counts(1).need, counts(2).need }, { "2", "1" }, "each its own drop")
end)

both("a popup that opens from the queue with no event gets its counts", function(skins)
    login(skins)
    RW.SetDrop(1, 1, { link = RW.CLOAK, rolls = BUSY })
    RW.Open({ rollID = 11, link = RW.CLOAK, queued = true })
    settle()
    T.deq(counts(1), { need = "3", greed = "2", pass = "1" })
end)

both("after a reload the counts come back on the popups still open", function(skins)
    login(skins, function()
        RW.SetDrop(1, 1, { link = RW.CLOAK, rolls = BUSY })
        RW.Open({ rollID = 11, link = RW.CLOAK, queued = true })
    end)
    T.deq(counts(1), { need = "3", greed = "2", pass = "1" })
end)

both("a popup reused for the next roll drops the last roll's counts and list, and shows its own", function(skins)
    rolling(skins, BUSY)
    RW.Close(11)
    RW.UpdateDrop(1, 2, { link = RW.SWORD, rolls = needers(5) })
    settle()
    RW.Open({ rollID = 13, link = RW.SWORD })
    T.deq(counts(1), { need = "", greed = "", pass = "" }, "as it opens")
    T.deq(texts(hover(1, "need")), { "Need", " ", "No roll data yet." }, "its tooltip as it opens")
    RW.Unhover(RW.Button(1, "need"))
    settle()
    T.deq(counts(1), { need = "5", greed = "", pass = "" }, "a frame later")
end)

both("with Transmog in Greed's place, its button counts Greed and Transmog rolls", function(skins)
    rolling(skins, { { "Dusk", "ROGUE", "greed" }, { "Eldra", "DRUID", "transmog" } }, { transmog = true })
    T.eq((RW.Count(RW.Button(1, "transmog"))), "2")
end)

both("rows the game keeps secret aren't counted", function(skins)
    rolling(skins, { { "Brannoc", "WARRIOR", "need", 87 }, { "Corvina", "PALADIN", "need", 64, secret = { roll = true } },
        { "Dusk", "ROGUE", "greed", secret = { playerName = true } }, { "Fenwick", "MAGE", "pass", secret = { state = true } } })
    T.deq(counts(1), { need = "1", greed = "", pass = "" })
end)

both("the count sits in the button's bottom right corner, in small text in the value color", function(skins)
    rolling(skins, BUSY)
    local b = RW.Button(1, "greed")
    local _, fs = RW.Count(b)
    local point, rel, relPoint, x, y = fs:GetPoint(1)
    T.eq(rel, b, "on its button")
    T.deq({ point, relPoint, x, y }, { "BOTTOMRIGHT", "BOTTOMRIGHT", 2, -2 })
    T.rgb({ fs:GetTextColor() }, ink("VALUE"))
    local _, size = fs:GetFont()
    T.near(size, DaylightUI.Style.SIZE.small * DaylightUI.DB.General().fontScale, 1e-6, "small text")
end)

both("nothing is written on the game's popups or their buttons", function(skins)
    local before = {}
    local function fields(t)
        local out = {}
        for k in pairs(t) do
            if type(k) ~= "string" or (k:sub(1, 2) ~= "__" and k ~= "rollID") then out[#out + 1] = tostring(k) end
        end
        table.sort(out)
        return table.concat(out, " ")
    end
    local function frames()
        local list = { GroupLootContainer }
        for i = 1, RW.POPUPS do
            local f = RW.Popup(i)
            list[#list + 1] = f
            list[#list + 1] = f.LootButtonContainer
            for _, kind in ipairs({ "need", "greed", "pass", "transmog" }) do list[#list + 1] = RW.Button(i, kind) end
        end
        return list
    end
    login(skins, function() for _, f in ipairs(frames()) do before[f] = fields(f) end end)
    RW.Open({ rollID = 11, link = RW.CLOAK, frame = 1 })
    RW.Open({ rollID = 12, link = RW.SWORD, frame = 2, queued = true })
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = BUSY })
    settle()
    hover(1)
    RW.Close(11)
    stub.FireEvent("CANCEL_ALL_LOOT_ROLLS")
    settle()
    for _, f in ipairs(frames()) do T.eq(fields(f), before[f], tostring(f:GetName() or f:GetObjectType())) end
end)

-- The button's tooltip

both("hovering a button keeps its own line on top and lists who picked it, Undecided last", function(skins)
    rolling(skins, BUSY)
    T.deq(texts(hover(1, "need")), { "Need",
        " ", "Need (3)", "Brannoc | 87", "Corvina (Off Spec) | 64", "Isolde (you) | 12",
        " ", "Undecided (2)", "Aelwyn", "Garrow" })
end)

both("the game's reason a button is off stays above the list", function(skins)
    rolling(skins, BUSY, { canNeed = false })
    local lines = texts(hover(1, "need"))
    T.deq({ lines[1], lines[2], lines[3], lines[4] }, { "Need", RW.CANT_NEED, " ", "Need (3)" })
end)

both("the Greed, Transmog and Pass buttons list their own choice, each ending with Undecided", function(skins)
    rolling(skins, BUSY)
    T.deq(texts(hover(1, "greed")), { "Greed", " ", "Greed (2)", "Dusk", "Eldra", " ", "Undecided (2)", "Aelwyn", "Garrow" })
    T.deq(texts(hover(1, "pass")), { "Pass", " ", "Pass (1)", "Fenwick", " ", "Undecided (2)", "Aelwyn", "Garrow" })
    RW.Close(11)
    RW.Open({ rollID = 12, link = RW.SWORD, transmog = true })
    RW.UpdateDrop(1, 2, { link = RW.SWORD, rolls = { { "Dusk", "ROGUE", "greed", 20 }, { "Eldra", "DRUID", "transmog", 55 } } })
    settle()
    T.deq(texts(hover(1, "transmog")), { "Transmog", " ", "Greed (2)", "Eldra | 55", "Dusk | 20" })
end)

both("names are in their class color, rolls in the value color, the line in the text color", function(skins)
    rolling(skins, BUSY)
    local lines = hover(1, "need")
    local row = line(lines, "Corvina (Off Spec)")
    T.eq(colorOf(row.text, "Corvina", row.color), hex(classColor("PALADIN")), "the name")
    T.falsy(hex(classColor("PALADIN")) == hex(ink("TEXT")), "a class color, not the line's")
    T.rgb(row.rightColor, ink("VALUE"), "the roll")
    T.rgb(row.color, ink("TEXT"), "the line")
    T.rgb(line(lines, "Need (3)").color, ink("LABEL"), "the section's word")
end)

both("the winner's row is all in the good color", function(skins)
    rolling(skins, BUSY)
    local row = line(hover(1, "need"), "Brannoc")
    T.eq(row.text, "Brannoc", "no class color over it")
    T.rgb(row.color, ink("GOOD"), "the name")
    T.rgb(row.rightColor, ink("GOOD"), "the roll")
end)

both("an Off-spec Need carries the game's off-spec tag, muted, wherever the language puts it", function(skins)
    rolling(skins, BUSY)
    local lines = hover(1, "need")
    local row = line(lines, "Corvina (Off Spec)")
    T.eq(colorOf(row.text, "(Off Spec)", row.color), hex(ink("OFF")), "the tag")
    T.eq(colorOf(row.text, "Corvina", row.color), hex(classColor("PALADIN")), "the name")
    T.falsy(line(lines, "Brannoc").text:find("Off Spec", 1, true), "a main-spec Need has none")
    _G.LOOT_HISTORY_OFF_SPEC_FMT = "[Nebenspez.] %s"
    row = line(hover(1, "need"), "[Nebenspez.] Corvina")
    T.eq(colorOf(row.text, "[Nebenspez.]", row.color), hex(ink("OFF")), "a tag before the name")
    T.eq(colorOf(row.text, "Corvina", row.color), hex(classColor("PALADIN")))
    _G.LOOT_HISTORY_OFF_SPEC_FMT = nil
    row = line(hover(1, "need"), "Corvina (off spec)")
    T.eq(colorOf(row.text, "(off spec)", row.color), hex(ink("OFF")), "ours, when the client has none")
end)

both("a winning Off-spec Need keeps the good color on the name and mutes only the tag; (you) is in the line's color", function(skins)
    rolling(skins, { { "Corvina", "PALADIN", "offspec", 64, winner = true }, { "Isolde", "PRIEST", "offspec", 12, self = true } })
    local lines = hover(1, "need")
    local row = line(lines, "Corvina (Off Spec)")
    T.eq(colorOf(row.text, "Corvina", row.color), hex(ink("GOOD")), "the winner's name")
    T.eq(colorOf(row.text, "(Off Spec)", row.color), hex(ink("OFF")), "the tag")
    local mine = line(lines, "Isolde (Off Spec) (you)")
    T.eq(colorOf(mine.text, "(you)", mine.color), hex(ink("TEXT")))
end)

both("a long list is cut with +N more while the count says how many", function(skins)
    local rolls = {}
    for i = 1, 20 do rolls[i] = { string.format("Needer%02d", i), "WARRIOR", "need", 100 - i } end
    rolling(skins, rolls)
    T.eq(counts(1).need, "20", "the count")
    local lines = hover(1, "need")
    local t = texts(lines)
    T.deq({ #t, t[3], t[4], t[18], t[19] }, { 19, "Need (20)", "Needer01 | 99", "Needer15 | 85", "+5 more" })
    T.rgb(lines[19].color, ink("OFF"), "muted")
end)

both("an Undecided player leaves that list as soon as they pick", function(skins)
    rolling(skins, { { "Dusk", "ROGUE", "greed" }, { "Garrow", "HUNTER", "none" } })
    T.deq(texts(hover(1, "greed")), { "Greed", " ", "Greed (1)", "Dusk", " ", "Undecided (1)", "Garrow" })
    RW.Unhover(RW.Button(1, "greed"))
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = { { "Dusk", "ROGUE", "greed" }, { "Garrow", "HUNTER", "greed" } } })
    settle()
    T.deq(texts(hover(1, "greed")), { "Greed", " ", "Greed (2)", "Dusk", "Garrow" })
end)

both("a popup without roll data says so, and its open tooltip fills in when the data arrives", function(skins)
    login(skins)
    RW.Open({ rollID = 11, link = RW.CLOAK })
    settle()
    local lines = hover(1, "need")
    T.deq(texts(lines), { "Need", " ", "No roll data yet." })
    T.rgb(lines[3].color, ink("OFF"), "muted")
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = { { "Brannoc", "WARRIOR", "need" } } })
    settle()
    T.deq(texts(RW.Lines()), { "Need", " ", "Need (1)", "Brannoc" }, "without moving the mouse")
end)

both("the tooltip being read follows each new pick", function(skins)
    rolling(skins, { { "Brannoc", "WARRIOR", "need", 87 } })
    hover(1, "need")
    RW.UpdateDrop(1, 1, { link = RW.CLOAK, rolls = { { "Brannoc", "WARRIOR", "need", 87 }, { "Corvina", "PALADIN", "need", 91 } } })
    settle()
    T.deq(texts(RW.Lines()), { "Need", " ", "Need (2)", "Corvina | 91", "Brannoc | 87" })
    T.eq(counts(1).need, "2")
end)

-- The two switches (QoL page, Loot rolls)

T.test("loot rolls: two switches on the Quality of Life page after Items and loot, both on, new in 1.9.6", function()
    login(false)
    local page = DaylightUI.Options.GetPage("QoL.qol")
    local at
    for i, g in ipairs(page.groups) do if g.label == "Loot rolls" then at = i end end
    T.truthy(at, "the group")
    T.eq(page.groups[at - 1].label, "Items and loot", "right after Items and loot")
    local rows = {}
    for _, item in ipairs(page.groups[at].items) do
        if item.type == "toggle" then
            rows[#rows + 1] = item.label
            T.eq(item.since, "1.9.6", item.label)
            T.eq(DaylightUI:Get("QoL", item.key), true, item.label .. " on")
        end
    end
    T.deq(rows, { "Roll counts on loot rolls", "Who rolled what in the button tooltip" })
end)

both("roll counts off blanks the counts at once and keeps the tooltip's list", function(skins)
    rolling(skins, BUSY)
    set("rollCounts", false)
    T.deq(counts(1), { need = "", greed = "", pass = "" })
    line(hover(1, "need"), "Need (3)")
    set("rollCounts", true)
    T.deq(counts(1), { need = "3", greed = "2", pass = "1" }, "back at once")
end)

both("who rolled what off leaves the button's own tooltip alone and keeps the counts", function(skins)
    rolling(skins, BUSY)
    set("rollTooltip", false)
    T.deq(texts(hover(1, "need")), { "Need" })
    T.eq(counts(1).need, "3")
end)

both("with both off, a popup gets no count and its tooltip nothing more", function(skins)
    rolling(skins, BUSY)
    set("rollTooltip", false)
    set("rollCounts", false)
    T.deq(counts(1), { need = "", greed = "", pass = "" }, "an open popup")
    RW.Open({ rollID = 12, link = RW.SWORD, frame = 2 })
    RW.UpdateDrop(1, 2, { link = RW.SWORD, rolls = needers(2) })
    settle()
    T.deq(counts(2), { need = "", greed = "", pass = "" }, "a new popup")
    T.deq(texts(hover(2, "need")), { "Need" })
    set("rollCounts", true)
    T.eq(counts(2).need, "2", "back at once")
end)

both("counts and lists take Daylight UI's text colors as they are when drawn", function(skins)
    rolling(skins, BUSY)
    local INK = DaylightUI.Style.INK
    local value, text = INK.VALUE, INK.TEXT
    INK.VALUE, INK.TEXT = { 0.8, 0.9, 1 }, { 0.9, 0.85, 0.8 }
    DaylightUI.Fire("StyleChanged")
    local _, fs = RW.Count(RW.Button(1, "need"))
    local color = { fs:GetTextColor() }
    local row = line(hover(1, "need"), "Corvina (Off Spec)")
    INK.VALUE, INK.TEXT = value, text
    T.rgb(color, { 0.8, 0.9, 1 }, "the count")
    T.rgb(row.color, { 0.9, 0.85, 0.8 }, "a tooltip line")
end)
