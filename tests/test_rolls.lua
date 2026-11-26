local stub = require("stub")

-- Two epics and the group from the mockups, used by every roll test below.
local RING = "|cffa335ee|Hitem:17063|h[Band of Accuria]|h|r"
local ROBE = "|cffa335ee|Hitem:19145|h[Robe of Volatile Power]|h|r"
local SEVEN = {
    { name = "Bram Holloway", class = "WARRIOR" },
    { name = "Kaelith Dawnmere", class = "MAGE" },
    { name = "Mira Calloway", class = "HUNTER", self = true },
    { name = "Tomas Reed", class = "ROGUE" },
    { name = "Sera Voss", class = "PRIEST" },
    { name = "Ilyra Fenwick", class = "DRUID" },
    { name = "Doran Ashby", class = "PALADIN" },
}

-- Logs in with the skins and a fake loot roll world. opts.history = false is the
-- world where C_LootHistory knows nothing; opts.enabled = false switches the
-- Daylight UI roll window off before load.
local function rollsLogin(opts)
    opts = opts or {}
    local RW = require("rollworld")
    stub.Load({ skins = true, before = function()
        RW.Install()
        RW.GameFrames()
        if opts.history == false then RW.UseHistory(false) end
        if opts.enabled == false then
            _G.DaylightUIDB = { modules = { Skins = { rolls = { enabled = false } } } }
        end
        if opts.before then opts.before() end
    end })
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    return stub.skins, RW
end

T.test("rollworld: a drop starts a roll the way the game does", function()
    local RW = require("rollworld")
    stub.Load({ skins = true, before = function() RW.Install(); RW.GameFrames() end })
    local rollID, historyID = RW.Drop({ name = "Band of Accuria", link = "|cffa335ee|Hitem:17063::::::::60:::::|h[Band of Accuria]|h|r", quality = 4, bop = true,
        players = { { name = "Bram", class = "WARRIOR" }, { name = "Mira", class = "HUNTER", self = true } } })
    local _, name, _, quality, bop, canNeed = GetLootRollItemInfo(rollID)
    T.eq(name, "Band of Accuria"); T.eq(quality, 4); T.eq(bop, true); T.eq(canNeed, true)
    T.eq(GetActiveLootRollIDs()[1], rollID)
    T.eq(C_LootHistory.GetSortedInfoForDrop(1, historyID).rollInfos[1].state, Enum.EncounterLootDropRollState.NoRoll)
    RollOnLoot(rollID, 1)
    T.eq(RW.rolled[1].id, 1, "Need is 1")
end)


T.test("rolls quiet: the game's popups are unseen and take no mouse", function()
    local S, RW = rollsLogin()
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local f = _G.GroupLootFrame1
    T.truthy(f:IsShown(), "the game's popup still runs")
    T.eq(f:GetAlpha(), 0)
    T.eq(f:IsMouseEnabled(), false)
    T.eq(f.LootButtonContainer.NeedButton:IsMouseEnabled(), false)
    T.eq(f.LootButtonContainer.PassButton:IsMouseEnabled(), false)
    T.eq(f.IconFrame:IsMouseEnabled(), false)
    stub.RunTimers()
    T.isnil(S.LootRoll.Of(f), "the old popup skin stays off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls quiet: with the switch off the game's popups are skinned as before", function()
    local S, RW = rollsLogin({ enabled = false })
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    stub.RunTimers()
    T.eq(_G.GroupLootFrame1:IsMouseEnabled(), true)
    T.truthy(S.LootRoll.Of(_G.GroupLootFrame1))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls quiet: with both switches off the game's popups are the game's own", function()
    local S, RW = rollsLogin({ enabled = false, before = function()
        DaylightUIDB.modules.Skins.rolls.popups = false
    end })
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    stub.RunTimers()
    local f = _G.GroupLootFrame1
    T.truthy(f:IsShown())
    T.eq(f:GetAlpha(), 1)
    T.eq(f:IsMouseEnabled(), true)
    T.isnil(S.LootRoll.Of(f), "not restyled")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls popups: each button counts the players who picked it", function()
    local S, RW = rollsLogin({ enabled = false })
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    stub.RunTimers()
    local f = _G.GroupLootFrame1
    local r = S.LootRoll.Of(f)
    T.truthy(r and r.counts and r.counts.need, "the buttons have counts")
    T.eq(r.counts.need:IsShown(), false, "nobody picked yet: no number")
    RW.Pick(id, "Bram Holloway", "need")
    RW.Pick(id, "Kaelith Dawnmere", "need")
    RW.Pick(id, "Sera Voss", "greed")
    RW.Pick(id, "Ilyra Fenwick", "disenchant")
    RW.Pick(id, "Doran Ashby", "pass")
    stub.RunTimers()
    T.eq(r.counts.need:GetText(), "2")
    T.eq(r.counts.need:IsShown(), true)
    T.eq(r.counts.greed:GetText(), "2", "disenchant counts as greed")
    T.eq(r.counts.pass:GetText(), "1")
    -- Your pick ends the popup, and its roll data with it.
    RollOnLoot(id, 1)
    stub.RunTimers()
    T.isnil(S.RollData.drops[id], "the roll's data is let go once its popup is gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls popups: a popup reused for the next roll starts at nothing", function()
    local S, RW = rollsLogin({ enabled = false })
    local first = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(first, "Bram Holloway", "need")
    stub.RunTimers()
    RollOnLoot(first, 0)
    stub.RunTimers()
    RW.Drop({ name = "Robe of Volatile Power", link = ROBE, players = SEVEN })
    stub.RunTimers()
    local r = S.LootRoll.Of(_G.GroupLootFrame1)
    T.eq(r.counts.need:IsShown(), false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls quiet: the controller UI keeps the game's own roll window", function()
    local S = rollsLogin({ before = function()
        _G.InputUtil = _G.InputUtil or {}
        InputUtil.IsGamepadUIEnabled = function() return true end
    end })
    T.eq(S.RollStack.On(), false)
    InputUtil.IsGamepadUIEnabled = function() return false end
    T.eq(S.RollStack.On(), true)
end)
T.test("rolls chat: every English roll line parses with its drop id", function()
    local C = rollsLogin().RollChat
    local link = RING
    local l = C.Parse(LOOT_ROLL_NEED:format(41, "Bram Holloway", link))
    T.eq(l.kind, "pick"); T.eq(l.pick, "need"); T.eq(l.who, "Bram Holloway"); T.eq(l.link, link); T.eq(l.historyID, 41)
    l = C.Parse(LOOT_ROLL_ROLLED_GREED:format(41, 98, link, "Sera Voss"))
    T.eq(l.kind, "roll"); T.eq(l.pick, "greed"); T.eq(l.roll, 98); T.eq(l.who, "Sera Voss")
    l = C.Parse(LOOT_ROLL_YOU_WON:format(41, link)); T.eq(l.kind, "won"); T.eq(l.self, true); T.isnil(l.who)
    l = C.Parse(LOOT_ROLL_WON:format(41, "Kaelith Dawnmere", link)); T.eq(l.kind, "won"); T.eq(l.who, "Kaelith Dawnmere")
    l = C.Parse(LOOT_ROLL_WON_NO_SPAM_NEED:format(41, "Bram Holloway", 91, link)); T.eq(l.kind, "won"); T.eq(l.pick, "need"); T.eq(l.roll, 91)
    l = C.Parse(LOOT_ROLL_YOU_WON_NO_SPAM_GREED:format(41, 55, link)); T.eq(l.kind, "won"); T.eq(l.self, true); T.eq(l.pick, "greed"); T.eq(l.roll, 55)
    l = C.Parse(LOOT_ROLL_PASSED_AUTO:format("Doran", link)); T.eq(l.pick, "pass"); T.isnil(l.historyID); T.eq(l.who, "Doran")
    l = C.Parse(LOOT_ROLL_PASSED_SELF_AUTO:format(41, link)); T.eq(l.pick, "pass"); T.eq(l.self, true)
    l = C.Parse(LOOT_ROLL_PASSED:format(41, "Doran Ashby", link)); T.eq(l.pick, "pass"); T.eq(l.who, "Doran Ashby")
    l = C.Parse(LOOT_ROLL_NEED_SELF:format(41, link)); T.eq(l.kind, "pick"); T.eq(l.pick, "need"); T.eq(l.self, true)
    l = C.Parse(LOOT_ROLL_ROLLED_DE:format(12, link, "Ilyra Fenwick")); T.eq(l.kind, "roll"); T.eq(l.pick, "disenchant"); T.eq(l.roll, 12)
    l = C.Parse(LOOT_ROLL_LOST_ROLL:format(41, NEED, 37, link)); T.eq(l.kind, "roll"); T.eq(l.self, true); T.eq(l.pick, "need"); T.eq(l.roll, 37)
    l = C.Parse(LOOT_ROLL_ALL_PASSED:format(41, link)); T.eq(l.kind, "allpassed"); T.eq(l.historyID, 41)
    l = C.Parse(LOOT_ROLL_STARTED:format(41, link)); T.eq(l.kind, "started"); T.eq(l.link, link)
    l = C.Parse(LOOT_ROLL_NEED:format(41, "Bram Holloway-Stormrage", link)); T.eq(l.who, "Bram Holloway", "the realm is cut")
    T.isnil(C.Parse("Bram receives loot: " .. link), "a loot line is not a roll line")
end)

T.test("rolls chat: positional holes in another language", function()
    local C = rollsLogin().RollChat
    _G.LOOT_ROLL_ROLLED_NEED = "|HlootHistory:%1$d|h[Beute]|h: Bedarf - %2$d für %3$s von %4$s"
    _G.LOOT_ROLL_WON = "|HlootHistory:%1$d|h[Beute]|h: %3$s gewonnen von %2$s"
    C.Build()
    local l = C.Parse("|HlootHistory:7|h[Beute]|h: [Ring] gewonnen von Bram")
    T.eq(l.kind, "won"); T.eq(l.who, "Bram"); T.eq(l.link, "[Ring]"); T.eq(l.historyID, 7)
    l = C.Parse("|HlootHistory:7|h[Beute]|h: Bedarf - 64 für [Ring] von Bram")
    T.eq(l.roll, 64); T.eq(l.who, "Bram")
end)

T.test("rolls chat: a secret line is skipped without an error", function()
    local C = rollsLogin().RollChat
    T.isnil(C.Parse(stub.Secret(LOOT_ROLL_NEED:format(1, "Bram", "[Ring]"))))
    T.isnil(C.Parse(nil))
    T.eq(#stub.errors, 0)
end)

T.test("rolls chat: a name's first word", function()
    local C = rollsLogin().RollChat
    local first, full = C.Names("Bram Holloway")
    T.eq(first, "Bram"); T.eq(full, "Bram Holloway")
    T.eq((C.Names("Doran")), "Doran")
end)
T.test("rolls data: picks, rolls and the winner from chat", function()
    local S, RW = rollsLogin({ history = false })
    local D = S.RollData
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(id, "Bram Holloway", "need"); RW.Pick(id, "Sera Voss", "greed"); RW.Pick(id, "Doran Ashby", "pass")
    local d = D.drops[id]
    T.truthy(d, "the roll is held")
    T.eq(d.name, "Band of Accuria"); T.eq(d.duration, 60)
    T.eq(d.players.Bram.pick, "need"); T.eq(d.players.Sera.pick, "greed"); T.eq(d.players.Doran.pick, "pass")
    RW.Roll(id, "Bram Holloway", 91); RW.Roll(id, "Sera Voss", 98)
    T.eq(d.players.Bram.roll, 91)
    RW.Win(id, "Bram Holloway")
    T.eq(d.winner, "Bram"); T.eq(d.done, true); T.eq(d.players.Bram.won, true)
    local order = D.Sorted(d, "best")
    T.eq(order[1].first, "Bram", "Need 91 beats Greed 98")
    T.eq(order[2].first, "Sera")
    T.eq(order[3].pick, "pass", "a pass below the rolls")
    T.eq(#order, 4, "chat alone knows only who spoke, and you")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls data: two copies keep their own picks by history id", function()
    local S, RW = rollsLogin({ history = false })
    local D = S.RollData
    local a = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local b = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(b, "Bram Holloway", "need"); RW.Pick(a, "Bram Holloway", "pass")
    T.eq(D.drops[a].players.Bram.pick, "pass"); T.eq(D.drops[b].players.Bram.pick, "need")
    T.eq((D.TwinIndex(D.drops[a])), 1); T.eq((D.TwinIndex(D.drops[b])), 2)
    T.eq(select(2, D.TwinIndex(D.drops[a])), 2)
    T.eq(D.Twins(D.drops[a])[1], D.drops[b])
    RW.Win(a, "Kaelith Dawnmere")
    T.eq(D.drops[b].players.Kaelith.hasOne, true, "her twin knows she has one")
end)

T.test("rolls data: the history path fills states, rolls and the winner", function()
    local S, RW = rollsLogin()
    local D = S.RollData
    -- The picks below change only the history, with no chat line.
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local d = D.drops[id]
    T.eq(d.lootListKey, RW.drops[id].historyID, "paired with its history drop")
    T.eq(d.players.Mira.self, true, "you, from the history")
    T.eq(d.players.Kaelith.class, "MAGE")
    RW.drops[id].players[1].state = Enum.EncounterLootDropRollState.NeedOffSpec
    RW.drops[id].players[5].state = Enum.EncounterLootDropRollState.Greed
    stub.FireEvent("LOOT_HISTORY_UPDATE_DROP", 1, RW.drops[id].historyID)
    T.eq(d.players.Bram.pick, "need"); T.eq(d.players.Bram.offSpec, true); T.eq(d.players.Sera.pick, "greed")
    T.isnil(d.players.Tomas.pick, "still choosing")
    RW.drops[id].players[1].roll = 91; RW.drops[id].players[1].won = true
    stub.FireEvent("LOOT_HISTORY_UPDATE_DROP", 1, RW.drops[id].historyID)
    T.eq(d.players.Bram.roll, 91); T.eq(d.winner, "Bram"); T.eq(d.done, true)
end)

T.test("rolls data: a history drop with a bare [Name] pairs by the name", function()
    local S, RW = rollsLogin()
    local D = S.RollData
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local d = D.drops[id]
    d.lootListKey, d.historyID = nil, nil
    RW.drops[id].link = "[Band of Accuria]"
    RW.drops[id].historyID = 900
    RW.drops[id].players[2].state = Enum.EncounterLootDropRollState.Greed
    stub.FireEvent("LOOT_HISTORY_UPDATE_DROP", 1, 900)
    T.eq(d.lootListKey, 900); T.eq(d.players.Kaelith.pick, "greed")
end)

T.test("rolls data: a reload rebuilds open rolls from the game", function()
    local S, RW = rollsLogin({ history = false })
    local D = S.RollData
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    stub.Advance(20)
    for k in pairs(D.drops) do D.drops[k] = nil end
    D.Rebuild(GetTime())
    local d = D.drops[id]
    T.truthy(d, "back")
    T.near(d.start + d.duration - GetTime(), 40, 0.5, "the time left is the game's")
end)

T.test("rolls data: a secret chat line is skipped", function()
    local S, RW = rollsLogin({ history = false })
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    -- The game's docs don't mark CHAT_MSG_LOOT secret in chat lockdown; a secret
    -- line handed over anyway must still be skipped quietly.
    stub.FireEvent("CHAT_MSG_LOOT", stub.Secret(LOOT_ROLL_NEED:format(RW.drops[id].historyID, "Bram Holloway", RING)), "")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local p = S.RollData.drops[id].players.Bram
    T.isnil(p and p.pick)
end)

T.test("rolls data: a roll with no result expires", function()
    local S, RW = rollsLogin({ history = false })
    local D = S.RollData
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN, time = 60000 })
    stub.Advance(60 + D.GRACE - 1)
    D.Expire(GetTime())
    T.falsy(D.drops[id].done)
    stub.Advance(1.1)
    D.Expire(GetTime())
    T.eq(D.drops[id].done, true); T.eq(D.drops[id].expired, true)
end)

T.test("rolls data: your Need number shows before the chat line", function()
    local S, RW = rollsLogin({ history = false })
    local D = S.RollData
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN, myNeed = 64 })
    D.Mine(id, "need")
    RollOnLoot(id, D.ID.need)
    T.eq(D.drops[id].myRoll, 64)
    T.eq(D.drops[id].mine, "need"); T.falsy(D.drops[id].timedOut)
end)

T.test("rolls data: time running out passes for you", function()
    local S, RW = rollsLogin({ history = false })
    local D = S.RollData
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    stub.FireEvent("CANCEL_LOOT_ROLL", id)
    T.eq(D.drops[id].mine, "pass"); T.eq(D.drops[id].timedOut, true)
end)

T.test("rolls data: leaving the group ends every roll", function()
    local S, RW = rollsLogin({ history = false })
    local D = S.RollData
    local a = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local b = RW.Drop({ name = "Robe of Volatile Power", link = ROBE, players = SEVEN })
    RW.CancelAll()
    T.eq(D.drops[a].done, true); T.eq(D.drops[b].done, true)
end)

T.test("rolls data: every change is told", function()
    local S, RW = rollsLogin({ history = false })
    local seen = {}
    DaylightUI.On("RollChanged", function(id, what) seen[#seen + 1] = what end)
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91); RW.Win(id, "Bram Holloway")
    local text = table.concat(seen, " ")
    T.truthy(text:find("start", 1, true)); T.truthy(text:find("pick", 1, true))
    T.truthy(text:find("roll", 1, true)); T.truthy(text:find("won", 1, true))
end)

T.test("rolls data: the Loot History seating the group is told, so the card shows everyone", function()
    local S, RW = rollsLogin()
    local seen = {}
    DaylightUI.On("RollChanged", function(_, what) seen[#seen + 1] = what end)
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    T.truthy(table.concat(seen, " "):find("seat", 1, true), "told")
    local card = S.RollStack.Cards()[1]
    local ticks = 0
    for _, t in ipairs(card.tickBars) do if t:IsShown() then ticks = ticks + 1 end end
    T.eq(ticks, 7, "a tick for each of the seven")
    T.eq(S.RollData.drops[id].lootListKey ~= nil, true)
end)
T.test("widgets: a button with an icon keeps the icon's colors and centers the pair", function()
    rollsLogin()
    local W = DaylightUI.Widgets
    local b = W.Button(UIParent, NEED, 30)
    b:SetWidth(120)
    W.ButtonIcon(b, "roll-need.png")
    T.truthy(b.icon, "an icon on it")
    T.truthy(b.icon:GetTexture():find("roll%-need%.png"), "our art")
    T.eq(select(1, b.icon:GetVertexColor()), 1, "no tint")
    T.eq(b.icon:GetWidth(), 22, "the button's height less 8")
    -- The pair sits in the middle: icon left of the word, the word right of it.
    local _, _, _, ix = b.icon:GetPoint(1)
    local _, _, _, tx = b.text:GetPoint(1)
    T.truthy(ix < 0 and tx > 0, "icon left, word right, around the middle")
    b.SetOff(true)
    T.eq(b.icon:IsDesaturated(), true, "off grays it")
    T.eq(b.icon:GetAlpha(), 0.5)
    b.SetOff(false)
    T.eq(b.icon:IsDesaturated(), false)
    -- No word: the icon alone in the middle.
    b.SetWords("")
    local _, _, _, alone = b.icon:GetPoint(1)
    T.eq(alone, 0)
    T.eq(b.text:GetText(), "")
    -- The game's own icon by its atlas.
    b.SetIcon("lootroll-toast-icon-need-up", true)
    T.eq(b.icon:GetAtlas(), "lootroll-toast-icon-need-up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("widgets: a button's icon grows and tilts under the mouse, and settles back", function()
    rollsLogin()
    local W = DaylightUI.Widgets
    local b = W.Button(UIParent, GREED, 30)
    W.ButtonIcon(b, "roll-greed.png")
    local function settle() local d = DaylightUI.Motion.Driver(); if d then stub.RunOnUpdate(d, 1) end end
    stub.MouseEnter(b)
    settle()
    T.near(b.icon:GetWidth(), 22 * W.BUTTON_ICON_HOVER, 0.01)
    T.truthy((b.icon.__rotation or 0) ~= 0, "tilted")
    stub.MouseLeave(b)
    settle()
    T.near(b.icon:GetWidth(), 22, 0.01); T.near(b.icon.__rotation or 0, 0, 1e-6)
end)
-- One card filled from a held roll, the way the stack draws it.
local function cardOf(S, id, look)
    local card = S.RollCard.New(UIParent)
    look = look or {}
    look.mode = look.mode or "full"
    look.settings = look.settings or S.RollStack.Settings()
    S.RollCard.Fill(card, S.RollData.drops[id], look)
    return card, look
end
local function settle()
    for _ = 1, 30 do
        local d = DaylightUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 0.1) end
    end
end
local function rgbOf(fs) local c = fs.__textColor or {}; return { c[1], c[2], c[3] } end

T.test("rolls card: buttons follow what the game lets you roll", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Robe of Volatile Power", link = ROBE, canNeed = false, reasonNeed = 2, players = SEVEN })
    local card = cardOf(S, id)
    T.eq(card.buttons.need.off, true, "Need off")
    T.eq(card.buttons.need.reason, LOOT_ROLL_INELIGIBLE_REASON2, "and why, for its tooltip")
    T.truthy(card.buttons.greed:IsShown()); T.falsy(card.buttons.transmog:IsShown())
    T.falsy(card.buttons.disenchant:IsShown())
    T.truthy(card.buttons.pass:IsShown())
    T.eq(card.name:GetText(), "Robe of Volatile Power")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game (Spanish): "Rodela de degollador de ag..." (an item name is the game's own words
-- and can be long). It shrinks, then takes a second row, rather than end in dots.
T.test("rolls card: a long item name shrinks, then wraps, instead of ending in dots", function()
    local S, RW = rollsLogin()
    stub.measure = function(fs, unbounded)
        local w = #(fs.__text or "") * (fs.__font and fs.__font[2] or 12) * 0.5
        local set = fs:GetWidth() or 0
        if unbounded or set <= 0 or fs.__wrap == false then return w, 14 end
        local lines = math.max(1, math.ceil(w / set))
        return math.min(w, set), lines * 14
    end
    local short = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local sc = cardOf(S, short)
    local size = DaylightUI.Style.SIZE.head
    T.eq(sc.name.__font[2], size, "a short name keeps its size")
    T.falsy(sc.name.__wrap, "and one row")
    local mid = RW.Drop({ name = "Rodela de degollador de aguas", link = RING, players = SEVEN })
    local mc = cardOf(S, mid)
    T.truthy(mc.name.__font[2] < size and mc.name.__font[2] >= size * S.RollCard.NAME_MIN - 0.01, "a long name shrinks, to a floor")
    local long = RW.Drop({ name = "Rodela de degollador de aguasoscuras del abismo infinito", link = RING, players = SEVEN })
    local lc = cardOf(S, long)
    T.truthy(lc.name.__wrap ~= false and lc.name.__maxLines == 2, "one still too long takes a second row")
    T.near(lc.name.__font[2], size * S.RollCard.NAME_MIN, 0.01, "at the floor")
    T.truthy((lc.nameExtra or 0) > 0 and lc:GetHeight() > sc:GetHeight(), "and the card grows for it")
    T.eq(sc.nameExtra or 0, 0, "a one row name adds nothing")
    stub.measure = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game (Spanish and German): the words in the roll buttons ran past the button.
T.test("rolls card: the words in the buttons fit them, with the icon, without it, or leave the icon alone", function()
    local S, RW = rollsLogin()
    local factor = 0.55
    stub.measure = function(fs, unbounded)
        return #(fs.__text or "") * (fs.__font and fs.__font[2] or 12) * factor, 14
    end
    local function words(card, shown)
        local out = {}
        for _, kind in ipairs(shown) do out[#out + 1] = card.buttons[kind] end
        return out
    end
    local function width(b) return #b.text:GetText() * b.text.__font[2] * factor end
    local function inside(card, n)
        return (card:GetWidth() - 2 * S.RollCard.PAD - S.RollCard.GAP * (n - 1)) / n - 2 * S.RollCard.BUTTON_PAD
    end
    -- Words that fit with their icons: both stay, at the size they come at.
    factor = 0.3
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardOf(S, id)
    local need = card.buttons.need
    T.truthy(need.baseWord, "the size the words come at")
    T.truthy(need.icon:IsShown() and need.text:GetText() ~= "", "icon and word together")
    T.eq(need.text.__font[2], need.baseWord, "at full size")
    -- Too wide beside the icon, not alone: the word stays, the icon goes.
    factor = 1
    local c2 = cardOf(S, (RW.Drop({ name = "Ring of Accuria", link = RING, players = SEVEN })))
    for _, b in ipairs(words(c2, { "need", "greed", "pass" })) do
        if b.text:GetText() ~= "" then
            T.truthy(width(b) <= inside(c2, 3) + 0.5, "the word fits its button")
            T.falsy(b.icon:IsShown() and width(b) > inside(c2, 3) - 28 - 6 + 0.5, "never over the icon")
        end
    end
    T.eq(c2.buttons.need.icon:IsShown(), false, "no icon: the word has the button")
    T.truthy(c2.buttons.need.text:GetText() ~= "", "the word stays")
    T.eq(c2.buttons.need.text.__font[2], c2.buttons.pass.text.__font[2], "the same size on every button")
    T.eq(c2.buttons.need.icon:IsShown(), c2.buttons.pass.icon:IsShown(), "the same on every button")
    -- Wider than any button: the icons stand alone.
    factor = 2
    local c3 = cardOf(S, (RW.Drop({ name = "Band of Accuria", link = RING, canDisenchant = true, players = SEVEN })))
    T.eq(c3.buttons.need.text:GetText(), "", "icons alone when no word fits")
    T.truthy(c3.buttons.need.icon:IsShown(), "and the icon is shown")
    stub.measure = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls card: a long summary line shrinks, then takes a second row", function()
    local S, RW = rollsLogin()
    local factor = 0.3
    stub.measure = function(fs, unbounded)
        local t = (fs.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local w = #t * (fs.__font and fs.__font[2] or 12) * factor
        if not unbounded and fs.__wrap ~= false and (fs.__maxLines or 0) > 0 then return math.min(w, 250), math.ceil(w / 250) * 14 end
        return w, 14
    end
    local function won()
        local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
        RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91)
        RW.Pick(id, "Mira Calloway", "greed"); RW.Roll(id, "Mira Calloway", 40)
        RW.Win(id, "Bram Holloway")
        return cardOf(S, id)
    end
    local short = won()
    T.eq(short.sumExtra or 0, 0, "fits: one row")
    -- A little too wide: the letters shrink, the row stays.
    factor = 0.65
    local mid = won()
    T.eq(mid.sumExtra or 0, 0, "shrunk, one row")
    T.truthy(mid.sum.__font[2] < DaylightUI.Style.SIZE.small, "smaller letters")
    -- Far too wide: a second row, the box taller by what it needs.
    factor = 1.5
    local long = won()
    T.truthy((long.sumExtra or 0) > 0, "two rows")
    T.near(long.sumBox:GetHeight(), S.RollCard.SUM + long.sumExtra, 1, "its box grew")
    T.truthy(long.sum.__font[2] >= DaylightUI.Style.SIZE.small * S.RollCard.SUM_MIN - 0.01, "not past the least")
    stub.measure = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls card: the item's tooltip redraws while hovered, so Shift compares", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local icon = cardOf(S, id).icon
    local drawn, compared, shift = 0, 0, false
    local shop = { shown = false }
    function shop:IsShown() return self.shown end
    function shop:Hide() self.shown = false end
    local realTip, realCompare, realMod, realUtil = _G.GameTooltip, _G.GameTooltip_ShowCompareItem, _G.IsModifiedClick, _G.TooltipUtil
    _G.TooltipUtil = nil
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end, IsOwned = function() return true end,
        shoppingTooltips = { shop },
        SetLootRollItem = function() drawn = drawn + 1 end, SetHyperlink = function() drawn = drawn + 1 end }
    _G.GameTooltip_ShowCompareItem = function() compared = compared + 1; shop.shown = true end
    _G.IsModifiedClick = function(what) return what == "COMPAREITEMS" and shift end
    icon:GetScript("OnEnter")(icon)
    T.eq(compared, 0, "no compare without Shift")
    T.eq(type(icon.UpdateTooltip), "function", "the game's tooltip timer has something to call")
    shift = true
    icon:UpdateTooltip()
    T.eq(drawn, 2, "it draws the item again")
    T.eq(compared, 1, "Shift pressed mid-hover compares")
    shift = false
    icon:UpdateTooltip()
    T.falsy(shop.shown, "letting go of Shift takes the compare away")
    icon:GetScript("OnLeave")(icon)
    T.isnil(icon.UpdateTooltip, "nothing left to redraw once the mouse leaves")
    _G.GameTooltip, _G.GameTooltip_ShowCompareItem, _G.IsModifiedClick, _G.TooltipUtil = realTip, realCompare, realMod, realUtil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls card: a button's tooltip shows only when it adds something", function()
    local S, RW = rollsLogin()
    stub.measure = function(fs) return #(fs.__text or "") * 4, 14 end
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardOf(S, id)
    local b = card.buttons.need
    local shown = false
    local realTip, realTips = _G.GameTooltip, DaylightUI.Tips
    _G.GameTooltip = { SetOwner = function() end, Show = function() shown = true end,
        Hide = function() shown = false end, IsShown = function() return shown end }
    DaylightUI.Tips = { Clear = function() end, Title = function() end, Text = function() end, Flush = function() end }
    local function hover()
        shown = false
        b:GetScript("OnEnter")(b)
        return shown
    end
    T.truthy(b.text:GetText() ~= "", "the word is on the button")
    T.falsy(hover(), "no tooltip repeating the word")
    b.reason = "Your class cannot roll Need."
    T.truthy(hover(), "a reason is worth one")
    b.reason = nil
    b.SetWords("")
    T.truthy(hover(), "an icon alone says what it is")
    _G.GameTooltip, DaylightUI.Tips = realTip, realTips
    stub.measure = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls card: \"choosing\" in a longer language gets the room it needs on a list row", function()
    local S, RW = rollsLogin()
    stub.measure = function(fs) return #(fs.__text or "") * 7, 14 end
    local realWord = S.RollCard.TEXT.choosing
    S.RollCard.TEXT.choosing = "eligiendo"
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91)
    RW.Win(id, "Bram Holloway")
    local card = cardOf(S, id, { open = true })
    local waiting, rolled
    for _, row in ipairs(card.rows) do
        if row.num:GetText() == "eligiendo" then waiting = row end
        if row.num:GetText() == "91" then rolled = row end
    end
    T.truthy(waiting, "a player still choosing")
    T.truthy(waiting.num:GetWidth() >= 9 * 7, "the word fits its room")
    T.eq(rolled.num:GetWidth(), S.RollCard.NUM_W, "a roll keeps the usual room")
    S.RollCard.TEXT.choosing = realWord
    stub.measure = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls card: Transmog takes Greed's place when the game offers it", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, canTransmog = true, players = SEVEN })
    local card = cardOf(S, id)
    T.truthy(card.buttons.transmog:IsShown()); T.falsy(card.buttons.greed:IsShown())
end)

T.test("rolls card: a press rolls with the game's number and folds the buttons", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card, look = cardOf(S, id)
    local before = S.RollCard.Height(card, look)
    card.buttons.greed:Click()
    T.eq(RW.rolled[1].rollID, id); T.eq(RW.rolled[1].id, 2, "Greed is 2")
    local d = S.RollData.drops[id]
    T.eq(d.mine, "greed"); T.falsy(d.timedOut, "a pick, not a timeout")
    T.eq(card.buttons.greed.active, true)
    settle()
    T.near(card.buttonBox:GetHeight(), 0, 0.01, "the buttons fold away")
    T.truthy(#card.rows > 0, "and the group's list opens once you've picked")
    T.truthy(before > 0)
    T.truthy(card.sum:GetText():find(GREED, 1, true), "says what you picked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls card: rows sort best first and the winner wears the accent", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local picks = { { "Bram Holloway", "need", 91 }, { "Kaelith Dawnmere", "need", 64 }, { "Mira Calloway", "need", 72 },
        { "Tomas Reed", "greed", 37 }, { "Sera Voss", "greed", 98 }, { "Ilyra Fenwick", "greed", 22 }, { "Doran Ashby", "pass" } }
    for _, p in ipairs(picks) do RW.Pick(id, p[1], p[2]) end
    for _, p in ipairs(picks) do if p[3] then RW.Roll(id, p[1], p[3]) end end
    RW.Win(id, "Bram Holloway")
    local card = cardOf(S, id, { open = true })
    T.eq(card.rows[1].name:GetText(), "Bram", "first names unless asked for full ones")
    T.eq(card.rows[2].name:GetText(), "Mira")
    T.eq(card.rows[4].name:GetText(), "Sera", "Greed 98 under every Need")
    T.eq(card.rows[7].name:GetText(), "Doran")
    T.eq(card.rows[1].lit, true, "the winner lit")
    T.rgb(rgbOf(card.rows[1].num), { DaylightUI.Style.Pop() }, "the winning number pops")
    T.eq(card.rows[1].num:GetText(), "91")
    T.eq(card.rows[2].tag:GetText(), DaylightUI.L["you"])
    T.near(card.rows[7].frame:GetAlpha(), 0.6, 0.01, "a pass is dimmed")
    T.truthy(card.sum:GetText():find("Bram", 1, true))
    DaylightUI:Set("general", "lastNames.rolls", true)
    S.RollCard.Fill(card, S.RollData.drops[id], { mode = "full", open = true, settings = S.RollStack.Settings() })
    T.eq(card.rows[1].name:GetText(), "Bram Holloway", "full names when asked")
end)

T.test("rolls card: text colors follow the look rules", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91)
    RW.Pick(id, "Mira Calloway", "need")
    local card = cardOf(S, id, { open = true })
    local Style = DaylightUI.Style
    T.rgb(rgbOf(card.rows[1].name), { Style.ClassTextColor("WARRIOR") }, "a name in its class color")
    T.rgb(rgbOf(card.sum), Style.INK.LABEL, "the summary is a label")
    T.rgb(rgbOf(card.rows[1].num), Style.INK.VALUE, "a number is a value")
    T.rgb(rgbOf(card.time), { Style.Pop() }, "time left pops")
    stub.Advance(50)
    S.RollCard.Tick(card, GetTime())
    T.rgb(rgbOf(card.time), Style.INK.WARN, "the last quarter warns")
end)

T.test("rolls card: everyone passed, a tie and no result each say so", function()
    local S, RW = rollsLogin()
    local C = S.RollCard
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.AllPass(id)
    local card = cardOf(S, id)
    T.eq(card.sum:GetText(), DaylightUI.L[C.TEXT.allPassed])
    local d = S.RollData.drops[id]
    d.allPassed, d.tied, d.done = nil, true, nil
    C.Fill(card, d, { mode = "full", settings = S.RollStack.Settings() })
    T.eq(card.sum:GetText(), DaylightUI.L[C.TEXT.tied])
    d.tied, d.done, d.expired = nil, true, true
    C.Fill(card, d, { mode = "full", settings = S.RollStack.Settings() })
    T.eq(card.sum:GetText(), DaylightUI.L[C.TEXT.noResult])
end)

T.test("rolls card: compact shows ticks, not rows, unless open", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(id, "Bram Holloway", "need"); RW.Pick(id, "Sera Voss", "greed")
    local card, look = cardOf(S, id, { mode = "compact" })
    T.truthy(card.ticks:IsShown(), "a row of ticks")
    T.falsy(card.rows[1] and card.rows[1].frame:IsShown(), "no rows")
    local shut = S.RollCard.Height(card, look)
    look.open = true
    S.RollCard.Fill(card, S.RollData.drops[id], look)
    T.falsy(card.rows[1] and card.rows[1].frame:IsShown(), "no list before you've picked, even asked")
    RW.Pick(id, "Mira Calloway", "greed")
    S.RollCard.Fill(card, S.RollData.drops[id], look)
    T.truthy(S.RollCard.Height(card, look) > shut, "open adds the list")
end)

T.test("rolls card: motion off snaps every change", function()
    local S, RW = rollsLogin()
    DaylightUI:Set("general", "motion", false)
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardOf(S, id)
    card.buttons.need:Click()
    T.near(card.buttonBox:GetHeight(), 0, 0.01, "folded at once")
    RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91)
    S.RollCard.Fill(card, S.RollData.drops[id], { mode = "full", open = true, settings = S.RollStack.Settings() })
    T.eq(card.rows[1].num:GetText(), "91", "the number at once")
end)
local function cardFor(S, id)
    for i, d in ipairs(S.RollStack.Shown()) do
        if d.rollID == id then return S.RollStack.Cards()[i] end
    end
end
local function tick(S, seconds)
    local steps = math.max(1, math.floor(seconds / 0.1 + 0.5))
    for _ = 1, steps do
        stub.Advance(seconds / steps)
        local f = S.RollStack.frame
        if f and f:GetScript("OnUpdate") then stub.RunOnUpdate(f, seconds / steps) end
    end
end

T.test("rolls stack: one roll shows in full with its list", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local St = S.RollStack
    T.eq(St.Mode(), "full"); T.isnil(St.Open(), "small until you've picked")
    T.truthy(St.frame:IsShown())
    St.Cards()[1].buttons.need:Click()
    T.eq(St.Open(), S.RollData.drops[id], "the list opens after your roll")
    T.eq(#St.Cards(), 1)
    T.truthy(St.Cards()[1]:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls stack: a click on the card folds or opens its list", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = St.Cards()[1]
    local function click() card:GetScript("OnMouseUp")(card, "LeftButton") end
    click()
    T.isnil(St.Open(), "nothing to open before your pick")
    card.buttons.need:Click()
    T.eq(St.Open(), S.RollData.drops[id], "open after your roll")
    click()
    T.isnil(St.Open(), "a click folds it")
    stub.MouseEnter(card)
    T.isnil(St.Open(), "and the mouse over it doesn't undo that")
    click()
    T.eq(St.Open(), S.RollData.drops[id], "another click opens it")
    stub.MouseLeave(card)

    -- Compact, a click opens a list besides the one the stack picked.
    local ids = {}
    for i = 1, 3 do ids[i] = RW.Drop({ name = "Item " .. i, link = "|cffa335ee|Hitem:" .. (950 + i) .. "|h[Item " .. i .. "]|h|r", players = SEVEN }) end
    T.eq(St.Mode(), "compact")
    local c2 = cardFor(S, ids[2])
    c2.buttons.greed:Click()
    c2:GetScript("OnMouseUp")(c2, "LeftButton")
    T.truthy(c2.look.open, "opened by the click, the mouse elsewhere")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls stack: four drops go compact with one list open at a time", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local ids = {}
    for i = 1, 4 do ids[i] = RW.Drop({ name = "Item " .. i, link = "|cffa335ee|Hitem:" .. (900 + i) .. "|h[Item " .. i .. "]|h|r", players = SEVEN }) end
    T.eq(St.Mode(), "compact")
    T.isnil(St.Open(), "no list until one is won or hovered")
    RW.Pick(ids[3], "Bram Holloway", "need"); RW.Roll(ids[3], "Bram Holloway", 50); RW.Win(ids[3], "Bram Holloway")
    T.eq(St.Open(), S.RollData.drops[ids[3]], "the one just won")
    stub.MouseEnter(cardFor(S, ids[1]))
    T.isnil(St.Open() == S.RollData.drops[ids[1]] or nil, "not before you've picked it")
    cardFor(S, ids[1]).buttons.greed:Click()
    T.eq(St.Open(), S.RollData.drops[ids[1]], "the one under the mouse")
    stub.MouseLeave(cardFor(S, ids[1]))
end)

T.test("rolls stack: a fifth drop waits its turn", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local ids = {}
    for i = 1, 5 do ids[i] = RW.Drop({ name = "Item " .. i, link = "|cffa335ee|Hitem:" .. (900 + i) .. "|h[Item " .. i .. "]|h|r", players = SEVEN }) end
    T.eq(#St.Shown(), 4); T.eq(St.Waiting(), 1)
    T.truthy(St.waiting:IsShown()); T.eq(St.waiting:GetText(), DaylightUI.L["%d more waiting"]:format(1))
    RW.AllPass(ids[1])
    tick(S, St.Settings().linger + 0.5)
    T.isnil(S.RollData.drops[ids[1]], "the finished one left")
    T.eq(St.Shown()[4].rollID, ids[5], "the fifth shows")
    T.eq(St.Waiting(), 0)
end)

T.test("rolls stack: twins sit together with a bracket", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local a = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local b = RW.Drop({ name = "Robe of Volatile Power", link = ROBE, players = SEVEN })
    local a2 = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local order = St.Shown()
    T.eq(order[1].rollID, a); T.eq(order[2].rollID, a2); T.eq(order[3].rollID, b)
    T.eq(cardFor(S, a).dup:GetText(), DaylightUI.L["%d of %d"]:format(1, 2))
    T.truthy(St.brackets[1] and St.brackets[1]:IsShown(), "a bracket joins them")
end)

T.test("rolls stack: a finished roll stays for its linger, longer under the mouse", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91); RW.Win(id, "Bram Holloway")
    tick(S, 4.9)
    T.truthy(S.RollData.drops[id], "still up")
    local card = cardFor(S, id)
    stub.MouseEnter(card)
    tick(S, 3)
    T.truthy(S.RollData.drops[id], "held under the mouse")
    stub.MouseLeave(card)
    tick(S, 0.3)
    T.isnil(S.RollData.drops[id], "gone once the mouse leaves")
end)

T.test("rolls stack: an expired roll leaves", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardFor(S, id)
    tick(S, 60 + S.RollData.GRACE + 0.3)
    T.eq(card.sum:GetText(), S.RollCard.TEXT.noResult)
    tick(S, S.RollStack.Settings().linger + 0.3)
    T.isnil(S.RollData.drops[id])
end)

T.test("rolls stack: in a fight rolls stay compact and lists open only on hover", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    stub.EnterCombat()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    T.eq(St.Mode(), "compact"); T.isnil(St.Open())
    cardFor(S, id).buttons.pass:Click()
    T.isnil(St.Open(), "picked, still closed in a fight")
    stub.MouseEnter(cardFor(S, id))
    T.eq(St.Open(), S.RollData.drops[id])
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls stack: cards come back after PLAYER_ENTERING_WORLD", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    stub.Advance(20)
    for k in pairs(S.RollData.drops) do S.RollData.drops[k] = nil end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    local d = S.RollData.drops[id]
    T.truthy(d, "back")
    T.near(d.start + d.duration - GetTime(), 40, 0.5)
    T.truthy(cardFor(S, id), "with its card")
end)

T.test("rolls stack: no driver while nothing is open", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    T.truthy(St.frame:GetScript("OnUpdate"), "running while a roll is up")
    RW.AllPass(id)
    tick(S, St.Settings().linger + 0.5)
    T.isnil(St.frame:GetScript("OnUpdate"), "stopped")
end)

T.test("rolls stack: follows the Loot Rolls handle's scale", function()
    local S, RW = rollsLogin()
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local want = DaylightUI.Movers.Scale("game.GroupLootContainer")
    T.near(S.RollStack.frame:GetScale(), want, 0.001)
    local gm = false
    for _, spec in ipairs(DaylightUI.GameMovers.FRAMES) do
        if spec.name == "GroupLootContainer" then
            for _, n in ipairs(spec.pieces) do if n == "DaylightUIRollStack" then gm = true end end
        end
    end
    T.truthy(gm, "a piece of the Loot Rolls handle, so its wheel and the master Scale reach it")
end)

T.test("rolls stack: grow down puts new rolls under the handle", function()
    local S, RW = rollsLogin()
    DaylightUI:Set("Skins", "rolls.grow", "down")
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local point = S.RollStack.frame:GetPoint(1)
    T.eq(point, "TOP")
    DaylightUI:Set("Skins", "rolls.grow", "up")
    stub.RunTimers()
    T.eq((S.RollStack.frame:GetPoint(1)), "BOTTOM")
end)

T.test("rolls stack: the game's popup clicks pass through where no card sits", function()
    local S, RW = rollsLogin()
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    T.eq(S.RollStack.frame:IsMouseEnabled(), false, "the stack's own frame takes no mouse")
end)
T.test("rolls options: every setting changes the window", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RW.Pick(id, "Doran Ashby", "pass"); RW.Pick(id, "Bram Holloway", "need"); RW.Pick(id, "Mira Calloway", "need")
    local St = S.RollStack
    local card = St.Cards()[1]
    local function set(key, v) DaylightUI:Set("Skins", "rolls." .. key, v); stub.RunTimers() end
    set("width", 360); T.near(card:GetWidth(), 360, 0.5, "width")
    set("buttonWords", false); T.eq(card.buttons.need.text:GetText(), "", "button words")
    set("icons", "game"); T.eq(card.buttons.need.icon:GetAtlas(), "lootroll-toast-icon-need-up", "the game's icons")
    set("buttonSize", 36); T.eq(card.buttons.need:GetHeight(), 36, "button size")
    set("timerText", false); T.falsy(card.time:IsShown(), "seconds left")
    set("qualityLine", false); T.falsy(card.line:IsShown(), "quality line")
    set("showPass", false)
    for _, row in ipairs(card.rows) do T.falsy(row.name:GetText() == "Doran", "a pass left out") end
    set("showPass", true)
    set("sort", "picked"); T.eq(card.rows[1].name:GetText(), "Doran", "as they picked")
    set("list", "off"); T.eq(#card.rows, 0, "no list")
    set("list", "auto")
    set("rollBars", false); RW.Roll(id, "Bram Holloway", 50); T.falsy(card.rows[2].bar:IsShown(), "no roll bars")
    set("grow", "down"); T.eq((St.frame:GetPoint(1)), "TOP", "grow direction")
    set("spacing", 12)
    RW.Drop({ name = "Robe of Volatile Power", link = ROBE, players = SEVEN })
    T.eq(St.Mode(), "compact")
    set("compact", false); T.eq(St.Mode(), "full", "compact off")
    set("maxShown", 1); T.eq(#St.Shown(), 1); T.eq(St.Waiting(), 1, "max shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls options: the page and its sample", function()
    local S = rollsLogin()
    local page
    for _, p in ipairs(S.OPTIONS and S.OPTIONS.pages or {}) do if p.id == "rolls" then page = p end end
    T.truthy(page, "an options page")
    local keys = {}
    for _, g in ipairs(page.groups) do for _, it in ipairs(g.items) do if it.key then keys[it.key] = it end end end
    for key in pairs(S.DEFAULTS.rolls) do T.truthy(keys["rolls." .. key], "a row for rolls." .. key) end
    local s = S.RollSample.New(UIParent)
    local h = s.Refresh(400, 600)
    T.truthy(h > 100, "it has a height")
    for _, part in ipairs(s.Parts()) do
        T.truthy(part.region, "a part's region")
        for _, k in ipairs(part.keys) do T.truthy(keys[k], "the part's key is a row: " .. k) end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls test mode: no sample rolls, and none in its list", function()
    local S = rollsLogin()
    local St = S.RollStack
    DaylightUI.testMode = true
    DaylightUI.Fire("TestModeChanged", true)
    T.eq(#St.Shown(), 0, "no made-up rolls")
    T.falsy(St.frame and St.frame:IsShown())
    for _, p in ipairs(DaylightUI.TestBox.parts) do T.falsy(p.key == "rolls", "not a test mode part") end
    DaylightUI.testMode = false
    DaylightUI.Fire("TestModeChanged", false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
-- Fixes from the review.
T.test("rolls stack: a roll still waiting on your pick always shows", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local ids = {}
    for i = 1, 5 do ids[i] = RW.Drop({ name = "Item " .. i, link = "|cffa335ee|Hitem:" .. (900 + i) .. "|h[Item " .. i .. "]|h|r", players = SEVEN }) end
    for i = 1, 4 do cardFor(S, ids[i]).buttons.greed:Click() end
    local shown = {}
    for _, d in ipairs(St.Shown()) do shown[d.rollID] = true end
    T.truthy(shown[ids[5]], "the fifth, not picked yet, takes a place before picked ones still rolling")
    T.eq(#St.Shown(), 4)
end)

T.test("rolls card: cancelling the game's bind box keeps your buttons", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, bop = true, players = SEVEN })
    local card = cardFor(S, id)
    card.buttons.need:Click()
    T.eq(RW.confirming, id, "the game asks first: it binds")
    settle()
    T.truthy(card.buttonBox:GetHeight() > 0, "the buttons stay until the game takes the pick")
    T.eq(card.buttons.need.active, true, "Need shows as pressed")
    card.buttons.greed:Click()
    T.eq(RW.rolled[2].id, 2, "you can pick again after saying no")
    RW.Confirm(id)
    local d = S.RollData.drops[id]
    T.eq(d.mine, "greed"); T.falsy(d.timedOut)
    settle()
    T.near(card.buttonBox:GetHeight(), 0, 0.01, "folded once the game took it")
end)

T.test("rolls data: your own line from the game wins over what you pressed", function()
    local S, RW = rollsLogin()
    local D = S.RollData
    local id = RW.Drop({ name = "Band of Accuria", link = RING, bop = true, players = SEVEN })
    D.Press(id, "need")
    stub.FireEvent("CANCEL_LOOT_ROLL", id)    -- time ran out with the bind box still open
    RW.Pick(id, "Mira Calloway", "pass")
    T.eq(D.drops[id].mine, "pass")
end)

-- Two copies whose history keys run the other way from their roll ids: the first
-- guess pairs them backwards. Your pick and the win on one copy must not end the
-- other, which you haven't rolled on yet.
local function crossedTwins(history)
    local S, RW = rollsLogin({ history = history })
    local a = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN, announce = false })
    local b = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN, announce = false })
    RW.Announce(b); RW.Announce(a)
    T.eq(S.RollData.drops[a].historyID, RW.drops[b].historyID, "the first guess pairs them backwards")
    return S, RW, a, b
end

for _, history in ipairs({ true, false }) do
    local how = history and "history" or "chat only"
    T.test("rolls data: crossed twins, winning one leaves the other open (" .. how .. ")", function()
        local S, RW, a, b = crossedTwins(history)
        local D = S.RollData
        RW.Pick(a, "Bram Holloway", "need"); RW.Pick(b, "Bram Holloway", "greed")
        cardFor(S, a).buttons.need:Click()
        T.eq(D.drops[a].mine, "need", "your pick stays on the card you clicked")
        T.isnil(D.drops[b].mine, "the other copy still waits on you")
        RW.Roll(a, "Mira Calloway", 40); RW.Roll(a, "Bram Holloway", 90)
        RW.Win(a, "Bram Holloway")
        T.eq(D.drops[a].done, true); T.eq(D.drops[a].winner, "Bram")
        T.falsy(D.drops[b].done, "the copy you haven't rolled on isn't over")
        T.isnil(D.drops[b].winner)
        T.eq(D.drops[b].players.Bram.pick, "greed", "Bram's pick on the other copy follows it")
        tick(S, 10)
        local card = cardFor(S, b)
        T.truthy(card, "its card is still up")
        T.truthy(card.buttons.need:IsShown(), "with its buttons")
        card.buttons.greed:Click()
        T.eq(D.drops[b].mine, "greed")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end)
end

T.test("rolls data: two copies' history records pair in order, whichever comes first", function()
    local S, RW = rollsLogin()
    local D = S.RollData
    local a = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local b = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    for _, id in ipairs({ a, b }) do D.drops[id].lootListKey, D.drops[id].encounterID, D.drops[id].historyID = nil, nil, nil end
    RW.drops[b].players[1].state = Enum.EncounterLootDropRollState.Greed
    stub.FireEvent("LOOT_HISTORY_UPDATE_DROP", 1, RW.drops[b].historyID)
    T.eq(D.drops[b].lootListKey, RW.drops[b].historyID, "the second record to the second copy")
    T.eq(D.drops[b].players.Bram.pick, "greed"); T.isnil(D.drops[a].players.Bram and D.drops[a].players.Bram.pick)
end)

T.test("rolls stack: a roll you already picked comes back after a reload", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    cardFor(S, id).buttons.need:Click()
    for k in pairs(S.RollData.drops) do S.RollData.drops[k] = nil end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    local back
    for _, d in pairs(S.RollData.drops) do back = d end
    T.truthy(back, "back from the Loot History")
    T.eq(back.mine, "need", "with your pick")
    T.eq(back.name, "Band of Accuria")
    T.eq(#S.RollStack.Cards(), 1)
end)

T.test("rolls data: a picked roll rebuilt after a reload keeps the time it had left", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN, time = 180000 })
    cardFor(S, id).buttons.greed:Click()
    stub.Advance(60)
    for k in pairs(S.RollData.drops) do S.RollData.drops[k] = nil end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    local back
    for _, d in pairs(S.RollData.drops) do back = d end
    T.truthy(back, "back from the Loot History")
    local left = back.start + back.duration - GetTime()
    T.truthy(left > 115 and left < 125, "about two minutes left, not " .. tostring(left))
end)

T.test("rolls data: a picked roll whose time ran out stays gone after a reload", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN, time = 180000 })
    cardFor(S, id).buttons.greed:Click()
    stub.Advance(400)
    for k in pairs(S.RollData.drops) do S.RollData.drops[k] = nil end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    T.isnil(next(S.RollData.drops), "no card for a roll that is over")
end)

T.test("rolls stack: leaving the group ends every roll and its card leaves", function()
    local S, RW = rollsLogin()
    local a = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local b = RW.Drop({ name = "Robe of Volatile Power", link = ROBE, players = SEVEN })
    cardFor(S, b).buttons.greed:Click()
    RW.LeaveGroup()
    T.eq(S.RollData.drops[a].done, true, "the roll waiting on you ended")
    T.eq(S.RollData.drops[b].done, true, "the roll you picked ended")
    T.eq(cardFor(S, a).sum:GetText(), S.RollCard.TEXT.leftGroup)
    tick(S, S.RollStack.Settings().linger + 0.5)
    T.isnil(next(S.RollData.drops), "no card stays")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls data: after leaving the group a reload brings no roll back", function()
    local S, RW = rollsLogin()
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local b = RW.Drop({ name = "Robe of Volatile Power", link = ROBE, players = SEVEN })
    cardFor(S, b).buttons.greed:Click()
    RW.LeaveGroup()
    for k in pairs(S.RollData.drops) do S.RollData.drops[k] = nil end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)
    T.isnil(next(S.RollData.drops), "nothing rebuilt while you're not in a group")
end)

T.test("rolls stack: a right-click puts away a roll you've picked, never one waiting on you", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardFor(S, id)
    card:GetScript("OnMouseUp")(card, "RightButton")
    T.truthy(S.RollData.drops[id], "still waiting on your pick")
    card.buttons.greed:Click()
    card:GetScript("OnMouseUp")(card, "RightButton")
    T.isnil(S.RollData.drops[id], "put away")
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.isnil(next(S.RollData.drops), "a zone change doesn't bring it back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls stack: if a card can't be drawn the game's popup comes back", function()
    local S, RW = rollsLogin()
    local fill = S.RollCard.Fill
    S.RollCard.Fill = function() error("broken") end
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    S.RollCard.Fill = fill
    T.truthy(#stub.errors > 0, "the error is reported")
    for k in pairs(stub.errors) do stub.errors[k] = nil end
    T.eq(_G.GroupLootFrame1:GetAlpha(), 1, "the game's popup in sight again")
    T.eq(_G.GroupLootFrame1:IsMouseEnabled(), true)
    T.eq(_G.GroupLootFrame1.LootButtonContainer.NeedButton:IsMouseEnabled(), true, "its buttons work")
end)

T.test("rolls data: two players with one first name keep their own rows", function()
    local S, RW = rollsLogin()
    local players = { { name = "Bram Holloway", class = "WARRIOR" }, { name = "Bram Stone", class = "MAGE" },
        { name = "Mira Calloway", class = "HUNTER", self = true } }
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = players })
    RW.Pick(id, "Bram Holloway", "need"); RW.Pick(id, "Bram Stone", "pass")
    local d, n = S.RollData.drops[id], 0
    for _ in pairs(d.players) do n = n + 1 end
    T.eq(n, 3, "two Brams")
    local picks = {}
    for _, p in pairs(d.players) do if p.name then picks[p.name] = p.pick end end
    T.eq(picks["Bram Holloway"], "need"); T.eq(picks["Bram Stone"], "pass")
end)
T.test("rolls card: a roll that ends while time is low stops its timer's pulse", function()
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardFor(S, id)
    stub.Advance(50)
    S.RollCard.Tick(card, GetTime())
    T.eq(card.timer.low, true)
    RW.AllPass(id)
    T.falsy(card.timer.low, "no longer low once done")
    T.eq(card.bar.fill:GetAlpha(), 1)
end)

T.test("rolls card: a reused card keeps no rows for players it no longer shows", function()
    local S, RW = rollsLogin()
    local card = S.RollCard.New(UIParent)
    local look = { mode = "full", open = true, settings = S.RollStack.Settings() }
    for i = 1, 3 do
        local players = {}
        for j = 1, 5 do players[j] = { name = "Player" .. i .. "x" .. j .. " Name", class = "MAGE" } end
        local id = RW.Drop({ name = "Item " .. i, link = "|cffa335ee|Hitem:" .. (900 + i) .. "|h[Item " .. i .. "]|h|r", players = players })
        for j = 1, 5 do RW.Pick(id, players[j].name, "greed") end
        S.RollCard.Fill(card, S.RollData.drops[id], look)
    end
    local n = 0
    for _ in pairs(card.rowOf) do n = n + 1 end
    T.truthy(n <= 6, "rows reused, not one per name ever seen: " .. n)
end)
T.test("rolls stack: the stack stays on screen", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local room = 320
    St.Room = function() return room end
    local ids = {}
    for i = 1, 4 do ids[i] = RW.Drop({ name = "Item " .. i, link = "|cffa335ee|Hitem:" .. (900 + i) .. "|h[Item " .. i .. "]|h|r", players = SEVEN }) end
    cardFor(S, ids[1]).buttons.greed:Click()
    local total = 0
    for _, card in ipairs(St.Cards()) do total = total + S.RollCard.Height(card, card.look) + St.Settings().spacing end
    T.truthy(total <= room, "the cards fit the room: " .. total)
    T.truthy(#St.Cards() < 4, "the rest wait")
    T.truthy(St.waiting:IsShown()); T.eq(St.waiting:GetText(), DaylightUI.L["%d more waiting"]:format(4 - #St.Cards()))
    for _, card in ipairs(St.Cards()) do T.falsy(card.drop.mine, "rolls you still have to pick keep their place") end
    -- The one under the mouse keeps its list; with room for it the others fold theirs.
    room = 2000
    St.Layout()
    T.eq(#St.Cards(), 4, "all four with room")
    T.truthy(St.frame:IsClampedToScreen(), "kept inside the screen as a last guard")
end)

-- Whether anything on a frame, or inside it, takes the mouse.
local function takesMouse(f)
    if f:IsMouseEnabled() then return true end
    for _, child in ipairs({ f:GetChildren() }) do
        if child:IsShown() and takesMouse(child) then return true end
    end
    return false
end

-- Every card of the stack that is in sight but not one of its placed cards:
-- one fading out where it stood is fine, as long as nothing on it takes a
-- click meant for the card gliding into its spot.
local function strayCards(St)
    local placed, out = {}, {}
    for _, card in ipairs(St.Cards()) do placed[card] = true end
    for _, child in ipairs({ St.frame:GetChildren() }) do
        if child.buttons and not placed[child] and child:IsShown() and child:GetAlpha() > 0
            and (not child.leaving or takesMouse(child)) then
            out[#out + 1] = child
        end
    end
    return out
end

T.test("rolls stack: with room for two, three to five drops never leave a card over another", function()
    for n = 3, 5 do
        local S, RW = rollsLogin()
        local St = S.RollStack
        local one = RW.Drop({ name = "Item 0", link = "|cffa335ee|Hitem:900|h[Item 0]|h|r", players = SEVEN })
        St.Layout()
        local h = S.RollCard.Height(St.Cards()[1], St.Cards()[1].look)
        S.RollData.Remove(one)
        tick(S, 1); settle()
        local room = 2 * (h + St.Settings().spacing) + DaylightUI.Style.SIZE.small + St.Settings().spacing + 1
        St.Room = function() return room end
        local ids = {}
        -- All at once, the way a boss's loot comes, then out of order: a pick
        -- from someone else on the newest while the others wait.
        for i = 1, n do ids[i] = RW.Drop({ name = "Item " .. i, link = "|cffa335ee|Hitem:" .. (900 + i) .. "|h[Item " .. i .. "]|h|r", players = SEVEN }) end
        RW.Pick(ids[n], "Bram Holloway", "need")
        tick(S, 1); settle()
        T.eq(#St.Cards(), 2, n .. " drops: two fit")
        T.eq(#strayCards(St), 0, n .. " drops: only the placed cards show once settled")
        -- The mouse going over a card, and more picks from the group: each lays
        -- the stack out again.
        for round = 1, 3 do
            stub.MouseEnter(St.Cards()[1]); St.Cards()[1]:GetScript("OnEnter")(St.Cards()[1])
            T.eq(#strayCards(St), 0, n .. " drops, hover " .. round .. ": no card comes back over the others")
            stub.MouseLeave(St.Cards()[1]); St.Cards()[1]:GetScript("OnLeave")(St.Cards()[1])
            RW.Pick(ids[1], SEVEN[round].name, "greed")
            T.eq(#strayCards(St), 0, n .. " drops, pick " .. round .. ": no card comes back over the others")
        end
        -- Each placed card sits on its own row, under the next one.
        local cards = St.Cards()
        for i = 2, #cards do
            T.truthy(cards[i].y >= cards[i - 1].y + cards[i - 1]:GetHeight(), n .. " drops: card " .. i .. " clear of the one below")
        end
        -- Your buttons on a waiting roll still work.
        local drop = cards[1].drop
        cards[1].buttons.need:Click()
        T.truthy(drop.pending or drop.mine, n .. " drops: the press is taken")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

T.test("rolls card: a folded part is never sized 0 and hides its pieces", function()
    -- The game reads a size of 0 as no size: what hangs below it loses its place
    -- and the clipping stops, so a fold is a sliver, then hidden.
    local S, RW = rollsLogin()
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardFor(S, id)
    local sizes = {}
    local set = card.buttonBox.SetHeight
    card.buttonBox.SetHeight = function(self, h) sizes[#sizes + 1] = h; return set(self, h) end
    card.buttons.greed:Click()
    settle()
    for _, h in ipairs(sizes) do T.truthy(h > 0, "never 0: " .. tostring(h)) end
    T.falsy(card.buttonBox:IsShown(), "hidden once folded")
    for _, box in ipairs(card.boxes) do T.truthy(box:GetHeight() > 0, "no part at 0") end
end)

-- Whether a frame has a place on screen: every point leads, frame by frame, to
-- UIParent. A frame with no points has none, and nothing hung from it shows.
local function placed(f, seen)
    seen = seen or {}
    if f == UIParent then return true end
    if seen[f] or f:GetNumPoints() == 0 then return false end
    seen[f] = true
    for i = 1, f:GetNumPoints() do
        local _, rel = f:GetPoint(i)
        if not placed(rel or f:GetParent(), seen) then return false end
    end
    return true
end

T.test("rolls stack: the result stays on screen when the game's popups are all gone", function()
    -- The last pick ends the roll at once (seen in game): the game drops its last
    -- popup, hides its roll container and clears the container's points.
    local S, RW = rollsLogin()
    local St = S.RollStack
    local FIVE = {
        { name = "Faera Duskveil", class = "PRIEST" }, { name = "Saki Shimmergloom", class = "MAGE" },
        { name = "Kevin Shiver", class = "ROGUE" }, { name = "Adorias Ashvale", class = "HUNTER" },
        { name = "Raging Daylight", class = "WARRIOR", self = true },
    }
    local id = RW.Drop({ name = "Jouster's Wristguards", quality = 2, canNeed = false, players = FIVE })
    T.truthy(placed(St.frame), "on screen while the game's popup is up")
    for _, n in ipairs({ "Faera Duskveil", "Saki Shimmergloom", "Kevin Shiver", "Adorias Ashvale" }) do RW.Pick(id, n, "greed") end
    cardFor(S, id).buttons.greed:Click()
    T.falsy(_G.GroupLootContainer:IsShown(), "the game's container is gone")
    T.truthy(placed(St.frame), "still on screen after your pick")
    RW.Roll(id, "Saki Shimmergloom", 95); RW.Roll(id, "Raging Daylight", 5)
    RW.Win(id, "Saki Shimmergloom")
    tick(S, 1); settle()
    T.truthy(St.frame:IsShown()); T.truthy(placed(St.frame), "the result shows")
    T.truthy(cardFor(S, id).list:GetHeight() > 1, "with everyone's rolls")
end)

T.test("rolls stack: a moved Loot Rolls handle keeps the rolls at its spot", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    DaylightUI.DB.Positions()["game.GroupLootContainer"] = { 330, 147 }
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    cardFor(S, id).buttons.pass:Click()
    T.truthy(placed(St.frame), "on screen with the container gone")
    local point, rel, rp, x, y = St.frame:GetPoint(1)
    T.eq(point, "BOTTOM"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.near(x, 330, 0.5); T.near(y, 147 - 50, 0.5, "the bottom of the handle's first slot")
end)

T.test("rolls stack: in unlock mode the Loot Rolls handle stays one slot and the rolls follow it", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local key = "game.GroupLootContainer"
    DaylightUI.DB.Positions()[key] = { 330, 147 }
    T.truthy(DaylightUI.Movers.Unlock())
    local h = DaylightUI.Movers.Handle(key)
    T.truthy(h and h:IsShown(), "the handle is up")
    for i = 1, 3 do RW.Drop({ name = "Band of Accuria " .. i, link = RING, players = SEVEN }) end
    T.near(_G.GroupLootContainer:GetHeight(), 300, 0.5, "the game's container grew a slot per popup")
    DaylightUI.Movers.PlaceHandle(DaylightUI.Movers.Get(key), h)
    T.near(h:GetHeight(), 100, 0.5, "the handle stays the first slot, where the rolls hang")
    local _, _, _, hx, hy = h:GetPoint(1)
    local _, _, _, x, y = St.frame:GetPoint(1)
    T.near(x, hx, 0.5); T.near(y, hy - 50, 0.5, "the rolls start at the handle's bottom")
    -- Dragged: the rolls come along each frame, not on the next roll change.
    -- The fake game has no layout, so the handle is told where it is.
    h.GetCenter = function() return UIParent:GetWidth() / 2 - 200, UIParent:GetHeight() / 2 + 40 end
    h:GetScript("OnDragStart")(h)
    h:GetScript("OnUpdate")(h, 0.016)
    _, _, _, x, y = St.frame:GetPoint(1)
    T.near(x, -200, 0.5); T.near(y, 40 - 50, 0.5, "the rolls follow while it's dragged")
    h:GetScript("OnDragStop")(h)
    stub.RunTimers()
    local saved = DaylightUI.DB.Positions()[key]
    _, _, _, x, y = St.frame:GetPoint(1)
    T.near(x, saved[1], 0.5); T.near(y, saved[2] - 50, 0.5, "and stay at the spot it was dropped on")
    DaylightUI.Movers.Lock()
end)

T.test("rolls stack: an unmoved Loot Rolls handle stands over where the rolls hang", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local key = "game.GroupLootContainer"
    RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    T.truthy(DaylightUI.Movers.Unlock())
    local h = DaylightUI.Movers.Handle(key)
    local _, _, _, hx, hy = h:GetPoint(1)
    local _, _, _, x, y = St.frame:GetPoint(1)
    T.near(x, hx, 0.5); T.near(y, hy - h:GetHeight() / 2, 0.5)
    DaylightUI.Movers.Lock()
end)

T.test("rolls stack: the last roll fades out before the stack hides", function()
    local S, RW = rollsLogin()
    local St = S.RollStack
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardFor(S, id)
    RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91); RW.Win(id, "Bram Holloway")
    settle()
    tick(S, St.Settings().linger + 0.2)
    T.isnil(S.RollData.drops[id], "the roll left")
    T.truthy(St.frame:IsShown(), "the stack stays up while its card fades")
    T.truthy(card:IsShown() and card:GetAlpha() > 0, "the card is still fading")
    settle()
    T.near(card:GetAlpha(), 0, 0.01, "faded out")
    T.falsy(St.frame:IsShown(), "then the stack hides")
end)

-- The game's "You won" toast (LOOT_ITEM_ROLL_WON): AlertFrame_ShowNewAlert and a
-- loot toast the way AlertFrames.lua and LootWonAlertFrame_SetUp leave it.
local function gameToasts()
    _G.LootAlertSystem, _G.MoneyWonAlertSystem = {}, {}
    _G.AlertFrame_ShowNewAlert = function(f) f:Show(); f.animIn:Play() end
end
local function lootToast(link, roll)
    local t = CreateFrame("Button", nil, UIParent)
    t:Hide()
    t.queue = LootAlertSystem
    t.animIn, t.waitAndAnimOut = t:CreateAnimationGroup(), t:CreateAnimationGroup()
    t.RollTypeIcon, t.RollValue = t:CreateTexture(), t:CreateFontString()
    t.RollTypeIcon:SetShown(roll ~= nil); t.RollValue:SetShown(roll ~= nil)
    t.hyperlink = link
    return t
end

T.test("rolls stack: the game's won toast stays away while the card shows the win", function()
    local S, RW = rollsLogin({ before = gameToasts })
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    cardFor(S, id).buttons.greed:Click()
    RW.Roll(id, "Mira Calloway", 77)
    RW.Win(id, "Mira Calloway")
    tick(S, 0.5)
    local won = lootToast(RING, 77)
    AlertFrame_ShowNewAlert(won)
    T.falsy(won:IsShown(), "the card already says you won: no second box over it")
    -- A toast for an item no card shows, or plain loot, is the game's as always.
    local other = lootToast(ROBE, 50)
    AlertFrame_ShowNewAlert(other)
    T.truthy(other:IsShown(), "a roll no card holds keeps its toast")
    local plain = lootToast(RING, nil)
    AlertFrame_ShowNewAlert(plain)
    T.truthy(plain:IsShown(), "looted, not rolled: the toast stays")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls stack: with the roll window off the won toast stays", function()
    local _, RW = rollsLogin({ enabled = false, before = gameToasts })
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    RollOnLoot(id, 2)
    RW.Win(id, "Mira Calloway")
    local won = lootToast(RING, 77)
    AlertFrame_ShowNewAlert(won)
    T.truthy(won:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- DaylightUI.API 1.13: another addon finds the roll cards, hears them come
-- and go, and paints them.
T.test("rolls api: a card is told to plugins, found by its roll and painted", function()
    local S, RW = rollsLogin()
    local API = DaylightUI.API
    local me = API.For("Lootbook")
    local log, calls = {}, {}
    for _, ev in ipairs({ "FrameMade", "FrameUnitChanged", "FrameRemoved" }) do
        me.On(ev, function(kind, _, unit) if kind == "rollcard" then log[#log + 1] = ev .. ":" .. tostring(unit) end end)
    end
    T.truthy(me.Paint("rollcard", function(_, parts, info)
        calls[#calls + 1] = { parts = parts, info = info }
        parts.line:SetVertexColor(0, 1, 0, 1)
        parts.name:SetTextColor(0, 1, 0)
    end, { owns = { "line", "name" } }))
    T.eq(API.GetFrame("rolls"), S.RollStack.frame, "the cards' holder by name")
    local id = RW.Drop({ name = "Band of Accuria", link = RING, players = SEVEN })
    local card = cardFor(S, id)
    T.eq(API.GetRollCard(id), card, "found by the game's roll id")
    T.eq(log[1], "FrameMade:" .. id)
    local last = calls[#calls]
    T.truthy(last, "painted")
    T.eq(last.parts.card, card)
    T.eq(last.parts.name, card.name)
    T.eq(last.parts.buttons.need, card.buttons.need)
    T.eq(last.info.rollID, id)
    T.eq(last.info.link, RING)
    T.eq(#last.info.players, 7, "the whole group")
    T.eq(rgbOf(card.name)[2], 1, "a claimed name keeps the plugin's color")
    -- Picks and rolls repaint it, with the list's rows once it opens.
    card.buttons.need:Click()
    RW.Pick(id, "Bram Holloway", "need"); RW.Roll(id, "Bram Holloway", 91); RW.Win(id, "Bram Holloway")
    last = calls[#calls]
    T.eq(last.info.done, true)
    T.eq(last.info.winner, "Bram Holloway")
    T.truthy(#last.parts.rows > 0, "the list's rows")
    T.eq(last.parts.rows[1].player, "Bram Holloway", "best first")
    -- Gone once it leaves.
    tick(S, S.RollStack.Settings().linger + 0.5)
    T.isnil(API.GetRollCard(id), "not found after it left")
    T.eq(log[#log], "FrameRemoved:" .. id)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls api: a painter that stops gives the card its own colors back", function()
    local S, RW = rollsLogin()
    local me = DaylightUI.API.For("Lootbook")
    local id = RW.Drop({ name = "Band of Accuria", link = RING, quality = 4, players = SEVEN })
    local card = cardFor(S, id)
    local own = rgbOf(card.name)
    local h = me.Paint("rollcard", function(_, parts) parts.name:SetTextColor(0, 1, 0) end, { owns = { "name" } })
    T.eq(rgbOf(card.name)[2], 1, "painted on a card already up")
    DaylightUI.API.Off(h)
    T.eq(rgbOf(card.name)[1], own[1]); T.eq(rgbOf(card.name)[2], own[2])
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rolls api: the options page's sample cards are previews, never found", function()
    local S = rollsLogin()
    local made = {}
    DaylightUI.API.On("FrameMade", function(kind, f, _, isPreview) if kind == "rollcard" then made[f] = isPreview end end)
    local sample = S.RollSample.New(UIParent)
    sample.Refresh(300, 400)
    local n = 0
    for _, isPreview in pairs(made) do n = n + 1; T.eq(isPreview, true) end
    T.eq(n, 2)
    T.isnil(DaylightUI.API.GetRollCard(-1))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
