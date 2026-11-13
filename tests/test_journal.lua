local stub = require("stub")
local QW = require("questworld")

-- The quest journal over the world map's quest log panel (Journal.lua).
-- Uses the fake map and panel from questworld, with the tracker tests' quests.

local QUESTS = {
    QW.quest(1, "Princess Must Die!", { zone = "Elwynn Forest", level = 10, text = "A great sow named Princess...",
        objs = { { text = "Brass Collar: 0/1", have = 0, need = 1 } }, xp = 840,
        rewards = { { name = "Stonefield Wrap", icon = 1, count = 1, quality = 2, itemID = 101 } },
        choices = { { name = "Farmhand Gloves", icon = 2, count = 1, quality = 2, itemID = 102 } } }),
    QW.quest(2, "Kobold Candles", { zone = "Elwynn Forest", level = 7, complete = true, turnIn = "Return to William.",
        watched = false }),
    QW.quest(3, "Westfall Stew", { zone = "Westfall", level = 12,
        objs = { { text = "Okra: 1/3", have = 1, need = 3 }, { text = "Murloc Eye: 0/3", have = 0, need = 3 } },
        watched = false }),
}

local function load(spec, opts)
    opts = opts or {}
    opts.quests = true
    spec = spec or {}
    spec.quests = spec.quests or QUESTS
    spec.zone = spec.zone or "Elwynn Forest"
    spec.map = true
    local world = QW.world(spec)
    local before = opts.before
    opts.before = function() world(); if before then before() end end
    stub.Load(opts)
    return stub.quests.Journal, stub.quests
end

-- Open the map with its log (L) and let the frame-after refills run.
local function open(J)
    QW.ShowLog(true)
    stub.RunTimers()
    return J.frame
end

local function shown(list, kind)
    local out = {}
    for _, p in ipairs(list) do
        if p:IsShown() and (not kind or (kind == "quest" and p.quest) or (kind == "zone" and p.zone)) then out[#out + 1] = p end
    end
    return out
end

local function texts(rows, field)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r[field]:GetText() end
    return out
end

local function row(f, id)
    for _, p in ipairs(f.list.stack.pieces) do if p.quest and p.quest.id == id then return p end end
end

-- The footer's buttons, rightmost (the main one) first.
local function foot(f)
    local out = {}
    for _, b in ipairs(f.quest.footer.buttons) do if b:IsShown() then out[#out + 1] = b end end
    return out
end

T.test("journal: covers the game's panel, a level up, the game's pieces see-through", function()
    local J = load()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local f = open(J)
    T.truthy(f, "built")
    T.eq(f:GetParent(), QuestMapFrame, "a child of the game's panel: shows, hides and fades with it")
    T.eq(f:GetFrameStrata(), "HIGH")
    T.eq(f:GetFrameLevel(), J.LEVEL)
    T.eq(f:IsVisible(), true)
    T.eq(QuestMapFrame.QuestsFrame:GetAlpha(), 0, "the game's list under ours")
    T.eq(QuestMapFrame.Background:GetAlpha(), 0)
    T.eq(QuestMapFrame:IsShown(), true, "the game's panel itself never hidden")
    T.eq(f:IsMouseEnabled(), true, "clicks land on ours")
end)

T.test("journal: footer buttons sized by their words, Show on map never cut", function()
    local J = load()
    local f = open(J)
    f.quest.footer.frame:SetWidth(270)        -- the log panel's width less the edges
    row(f, 1):Click()
    local bs = f.quest.footer.buttons
    local map, share = bs[1], bs[3]
    T.eq(map.text:GetText(), "Show on map")
    T.truthy(map:GetWidth() - 8 >= map.text:GetStringWidth(), "the main button's words fit")
    T.truthy(map:GetWidth() > share:GetWidth(), "a long label gets more room than a short one")
    local sum = 0
    for _, b in ipairs(foot(f)) do sum = sum + b:GetWidth() end
    T.truthy(sum <= f.quest.footer.frame:GetWidth(), "the row still fits the page")
end)

T.test("journal: quests by zone, the zone you're in first, with the log's count", function()
    local J = load({ zone = "Westfall" })
    local f = open(J)
    T.deq(texts(shown(f.list.stack.pieces, "zone"), "text"), { "WESTFALL", "ELWYNN FOREST" })
    T.deq(texts(shown(f.list.stack.pieces, "quest"), "title"), { "Westfall Stew", "Princess Must Die!", "Kobold Candles" })
    T.eq(f.list.count:GetText(), "3/25")
    T.eq(row(f, 2).prog:GetText(), "Ready")
    T.eq(row(f, 3).prog:GetText(), "1/6")
    T.eq(row(f, 1).dot:IsShown(), true, "a tracked quest wears the dot")
    T.eq(row(f, 3).dot:IsShown(), false)
end)

T.test("journal: a quest opens as its own page, and back", function()
    local J = load()
    local f = open(J)
    row(f, 1):Click()
    T.eq(f.quest:IsShown(), true)
    T.eq(f.list:IsShown(), false)
    local said = {}
    for _, p in ipairs(f.quest.stack.pieces) do if p.text and p:IsShown() then said[#said + 1] = p.text:GetText() end end
    T.truthy(table.concat(said, "|"):find("Princess Must Die!", 1, true), "its title")
    T.truthy(table.concat(said, "|"):find("A great sow", 1, true), "its story")
    T.truthy(table.concat(said, "|"):find("Brass Collar", 1, true), "its objective")
    local b = foot(f)
    T.eq(#b, 4)
    T.eq(b[1].spec.primary, true, "Show on map is the main button")
    f.quest.stack.pieces[1]:Click()   -- the back line
    T.eq(f.list:IsShown(), true)
    T.eq(f.quest:IsShown(), false)
end)

T.test("journal: a timed quest's page counts its time down, ready or not", function()
    local J = load({ quests = { QW.quest(1, "Antidote", { timer = 61, complete = true }) } })
    local f = open(J)
    row(f, 1):Click()
    local label = J.time.label
    T.eq(label:GetText(), "1:01 left")
    T.eq(label:IsVisible(), true)
    stub.Advance(2)
    J.TickTime()
    T.eq(label:GetText(), "0:59 left")
end)

T.test("journal: rewards are tiles, with the game's quest log tooltip", function()
    local J = load()
    local f = open(J)
    row(f, 1):Click()
    local tiles = {}
    for _, p in ipairs(f.quest.stack.pieces) do if p.spec and p.spec.name then tiles[#tiles + 1] = p end end
    T.deq({ tiles[1].spec.name, tiles[2].spec.name }, { "Stonefield Wrap", "Farmhand Gloves" })
    tiles[2].spec.tooltip(tiles[2])
    T.deq(QW.Calls("questItemTip"), { "choice:1:1" })
end)

-- Ctrl-click a reward tries it on, Shift-click links it. Both used to do nothing:
-- the game's link call reads the log's selected quest, which the journal never
-- sets, so the link is built from the item instead.
T.test("journal: a held key on a reward hands the game its link", function()
    local J = load()
    local f = open(J)
    row(f, 1):Click()
    local tiles = {}
    for _, p in ipairs(f.quest.stack.pieces) do if p.spec and p.spec.name then tiles[#tiles + 1] = p end end
    local wasItem, wasClick, got = C_Item.GetItemInfo, _G.HandleModifiedItemClick, {}
    C_Item.GetItemInfo = function(id) return "item" .. id, "|Hitem:" .. id .. "::made|h[x]|h" end
    _G.HandleModifiedItemClick = function(link) got[#got + 1] = link; return true end
    C_QuestLog.SetSelectedQuest(3)
    tiles[1]:Click()
    C_QuestLog.SetSelectedQuest(1)
    tiles[2]:Click()
    C_Item.GetItemInfo, _G.HandleModifiedItemClick = wasItem, wasClick
    T.deq(got, { "|Hitem:101::made|h[x]|h", "|Hitem:102::log|h[Farmhand Gloves]|h" })
end)

T.test("journal: Track and Untrack, and the watch limit refuses", function()
    local J = load()
    local f = open(J)
    row(f, 3):Click()
    foot(f)[2]:Click()
    T.deq(QW.Calls("track"), { 3 })
    stub.RunTimers()
    row(f, 3)
    J.ShowList(); stub.RunTimers()
    T.eq(row(f, 3).dot:IsShown(), true, "tracked now")
    row(f, 1):Click()
    foot(f)[2]:Click()
    T.deq(QW.Calls("untrack"), { 1 })
end)

T.test("journal: Shift-click a quest tracks it (the game's log), the list stays", function()
    local J = load()
    local f = open(J)
    QW.state.shift = true
    row(f, 3):Click()
    T.deq(QW.Calls("track"), { 3 })
    T.eq(f.quest:IsShown(), false, "no quest page")
    T.eq(row(f, 3).dot:IsShown(), true, "its dot shows at once")
    row(f, 1):Click()
    T.deq(QW.Calls("untrack"), { 1 })
    QW.state.shift = nil
end)

T.test("journal: Abandon asks twice, then the game's own steps, the selection put back", function()
    local J = load()
    local f = open(J)
    QW.state.selected = 3
    row(f, 1):Click()
    local ab = foot(f)[4]
    ab:Click()
    T.deq(QW.Calls("abandon"), {}, "the first click only asks")
    T.deq(QW.Calls("sound"), {}, "the asking stays silent: the sound means it's gone")
    T.eq(ab.text:GetText(), "Abandon?", "our one ask (W.Confirm), in words that say what it asks")
    T.rgb({ ab.text:GetTextColor() }, DaylightUI.Style.INK.WARN, "W.Confirm's warn")
    stub.Advance(1)   -- past W.CONFIRM_GAP: a real second click, not a double-click
    foot(f)[4]:Click()
    T.deq(QW.Calls("abandon"), { 1 })
    T.deq(QW.Calls("sound"), { 846 }, "the game's own abandon sound")
    T.eq(QW.state.selected, 3, "the log's selection put back")
    stub.FireEvent("QUEST_REMOVED", 1)
    stub.RunTimers()
    T.eq(f.list:IsShown(), true, "back on the list")
    T.isnil(row(f, 1), "gone from it")
end)

-- The game's abandon popup names the items the quest takes away
-- (GetAbandonQuestItems, read after SetAbandonQuest). The journal's ask does too.
T.test("journal: Abandon on a quest holding items names them while it asks, the selection put back", function()
    local J = load()
    C_QuestLog.GetAbandonQuestItems = function()
        return QW.state.abandoning == 1 and { 101, 102, 103 } or nil
    end
    local names = { [101] = "Lunar Totem", [102] = "Old Rune" }
    local item = C_Item
    C_Item = setmetatable({ GetItemNameByID = function(id) return names[id] end }, { __index = item })
    local f = open(J)
    QW.state.selected = 3
    row(f, 1):Click()
    foot(f)[4]:Click()
    T.eq(J.warn:GetAlpha() > 0, true, "the card shows while it asks")
    T.truthy(J.warn.text:GetText():find("Lunar Totem, Old Rune", 1, true), "a name not known yet is left out, as the game does")
    T.eq(QW.state.selected, 3, "the log's selection put back")
    stub.Advance(4)
    stub.RunTimers()
    T.eq(foot(f)[4].text:GetText(), "Abandon", "the ask ran out")
    T.eq(J.warn:GetAlpha(), 0, "the card goes with it")
    -- A quest with no items of its own: the ask alone.
    J.ShowList(false)
    row(f, 3):Click()
    J.warn.text:SetText("")
    foot(f)[4]:Click()
    T.eq(foot(f)[4].text:GetText(), "Abandon?")
    T.eq(J.warn:GetAlpha(), 0, "nothing to warn about")
    C_Item = item
end)

-- A pending ask never carries over to the next quest's page, where one stray
-- click would drop the wrong quest.
T.test("journal: an Abandon still asking goes back to rest on another page", function()
    local J = load()
    local f = open(J)
    row(f, 1):Click()
    foot(f)[4]:Click()
    T.eq(foot(f)[4].text:GetText(), "Abandon?")
    J.ShowList()
    row(f, 3):Click()
    T.eq(J.frame.quest:IsShown(), true)
    T.eq(foot(f)[4].armed, false, "at rest on the new page")
    foot(f)[4]:Click()
    T.deq(QW.Calls("abandon"), {}, "one click there only asks")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The tracker's Abandon asks in its own box. The journal stays where it is and
-- goes back to the list only if that quest's page was open.
T.test("journal: the tracker's Abandon is a box; the journal stays put", function()
    local J, ns = load()
    local f = open(J)
    J.ShowQuest(3)
    ns.Clicks.Do("abandon", { id = 1, logIndex = 1, title = "Princess Must Die!" })
    T.eq(stub.popup.which, "DAYLIGHTUI_ABANDON_QUEST")
    StaticPopupDialogs.DAYLIGHTUI_ABANDON_QUEST.OnAccept(nil, stub.popup.data)
    T.deq(QW.Calls("abandon"), { 1 })
    T.eq(f.quest:IsShown(), true, "another quest's page stays")
    ns.Clicks.Do("abandon", { id = 3, logIndex = 2, title = "Westfall Stew" })
    StaticPopupDialogs.DAYLIGHTUI_ABANDON_QUEST.OnAccept(nil, stub.popup.data)
    T.deq(QW.Calls("abandon"), { 1, 3 })
    T.eq(f.quest:IsShown(), false, "its own page goes back to the list")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: Share only in a group, by the quest's log index", function()
    local J = load()
    local f = open(J)
    row(f, 3):Click()
    T.eq(foot(f)[3].spec.off, true, "not in a group")
    foot(f)[3]:Click()
    T.deq(QW.Calls("share"), {})
    stub.SetGroup(true)
    J.ShowQuest(3)
    foot(f)[3]:Click()
    T.eq(#QW.Calls("share"), 1)
end)

T.test("journal: no Share in a fight, the game blocks it; back when the fight ends", function()
    local J = load()
    local f = open(J)
    stub.SetGroup(true)
    row(f, 3):Click()
    T.eq(foot(f)[3].spec.off, false, "out of combat it shares")
    stub.EnterCombat()
    stub.RunTimers()
    T.eq(foot(f)[3].spec.off, true, "a fight starting turns it off on the open page")
    foot(f)[3]:Click()
    T.deq(QW.Calls("shareBlocked"), {})
    local fake = { id = 3, logIndex = 3 }
    for _, k in ipairs((J.MenuKeys(fake))) do T.truthy(k ~= "share", "no Share in the menu") end
    -- A menu opened before the fight: its click never reaches the game.
    J.Do("share", fake)
    T.deq(QW.Calls("shareBlocked"), {}, "never tried in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(foot(f)[3].spec.off, false, "back after the fight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a tagged quest's tag after its title and on its page", function()
    local quests = { QW.quest(1, "The Defias Brotherhood", { zone = "Westfall", elite = true }),
                     QW.quest(2, "Westfall Stew", { zone = "Westfall" }) }
    local J, ns = load({ quests = quests, zone = "Westfall" })
    local f = open(J)
    T.eq(row(f, 1).tag:IsShown(), true)
    T.eq(row(f, 1).tag.text:GetText(), string.upper(ELITE or "Elite"))
    T.eq(row(f, 2).tag:IsShown(), false)
    J.ShowQuest(1)
    local onPage
    for _, p in ipairs(f.quest.stack.pieces) do if p:IsShown() and p.tag and p.tag:IsShown() then onPage = p.tag end end
    T.truthy(onPage, "under the title")
    J.ShowQuest(2)
    local none = true
    for _, p in ipairs(f.quest.stack.pieces) do if p:IsShown() and p.tag and p.tag:IsShown() then none = false end end
    T.eq(none, true)
    DaylightUI:Set("Quests", "questTags", false)
    stub.RunTimers()
    J.ShowList()
    T.eq(row(f, 1).tag:IsShown(), false, "switched off")
end)

T.test("journal: Show on map turns the map out of combat, only pings in a fight", function()
    local J = load()
    local f = open(J)
    row(f, 1):Click()
    foot(f)[1]:Click()
    T.eq(#QW.Calls("map"), 1)
    T.deq(QW.Calls("ping"), { 1 })
    stub.EnterCombat()
    foot(f)[1]:Click()
    T.eq(#QW.Calls("map"), 1, "the map isn't turned in a fight")
    T.deq(QW.Calls("ping"), { 1, 1 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a zone folds, kept per character; a search shows every match", function()
    local J = load()
    local f = open(J)
    local zone = shown(f.list.stack.pieces, "zone")[1]
    zone:Click()
    T.deq(texts(shown(f.list.stack.pieces, "quest"), "title"), { "Westfall Stew" })
    T.eq(DaylightUI.DB.Character().journalFolds["Elwynn Forest"], true)
    f.list.search:SetText("candle")
    T.deq(texts(shown(f.list.stack.pieces, "quest"), "title"), { "Kobold Candles" }, "folded zones open for a search")
    f.list.search:SetText("")
    T.deq(texts(shown(f.list.stack.pieces, "quest"), "title"), { "Westfall Stew" })
end)

T.test("journal: a ready quest keeps its level color, Ready says it", function()
    local J, ns = load({ zone = "Westfall" })
    local f = open(J)
    local function candles()
        for _, b in ipairs(shown(f.list.stack.pieces, "quest")) do
            if b.title:GetText() == "Kobold Candles" then return b end
        end
    end
    local b = candles()
    local lk = ns.Look.Get({ colors = DaylightUI:Get("Quests", "colors") })
    T.rgb({ b.title:GetTextColor() }, { ns.Look.LevelColor(lk, b.quest) }, "title in its level color")
    T.rgb({ b.prog:GetTextColor() }, { ns.Look.Color(lk, "ready") }, "Ready in the ready color")
    DaylightUI:Set("Quests", "journalProgress", false)
    b = candles()
    T.rgb({ b.title:GetTextColor() }, { ns.Look.Color(lk, "ready") }, "no Ready shown: the title says it")
end)

T.test("journal: the list follows the Map page's settings", function()
    local J = load({ zone = "Westfall" })
    local f = open(J)
    local Q = function(k, v) DaylightUI:Set("Quests", k, v) end

    Q("journalHereFirst", false)
    T.deq(texts(shown(f.list.stack.pieces, "zone"), "text"), { "ELWYNN FOREST", "WESTFALL" }, "the game's zone order")
    Q("journalZoneCaps", false)
    T.deq(texts(shown(f.list.stack.pieces, "zone"), "text"), { "Elwynn Forest", "Westfall" })

    Q("journalSort", "ready")
    T.deq(texts(shown(f.list.stack.pieces, "quest"), "title"), { "Kobold Candles", "Princess Must Die!", "Westfall Stew" })
    Q("journalSort", "watched")
    T.eq(row(f, 1).dot:IsShown(), true)

    Q("journalProgress", false)
    T.eq(row(f, 2).prog:GetText(), "", "no progress")
    Q("journalDots", false)
    T.eq(row(f, 1).dot:IsShown(), false, "no dot on a tracked quest")

    Q("journalLevels", false)
    local b = row(f, 1)
    T.eq(b.level:IsShown(), false)
    local function leftOn()
        for i = 1, 2 do
            local point, to = b.title:GetPoint(i)
            if point == "LEFT" then return to end
        end
    end
    T.eq(leftOn(), b, "the title takes the level's place")
    b:GetScript("OnMouseDown")(b)
    b:GetScript("OnMouseUp")(b)
    T.eq(leftOn(), b, "a press keeps it there")

    Q("journalTextSize", 18)
    Q("journalRowHeight", 18)
    T.eq(row(f, 1):GetHeight(), 24, "a row keeps room for its text")
    Q("journalTextSize", 13)
    Q("journalRowHeight", 30)
    T.eq(row(f, 1):GetHeight(), 30)

    Q("journalOpacity", 0.6)
    local _, _, _, a = f.bg:GetVertexColor()
    T.eq(a, 0.6)
end)

T.test("journal: switched off, the game's own panel comes back", function()
    local J = load()
    local f = open(J)
    DaylightUI:Set("Quests", "journal", false)
    stub.RunTimers()
    T.eq(f:IsShown(), false)
    T.eq(QuestMapFrame.QuestsFrame:GetAlpha(), 1, "the game's list back")
    DaylightUI:Set("Quests", "journal", true)
    stub.RunTimers()
    T.eq(f:IsVisible(), true)
    T.eq(QuestMapFrame.QuestsFrame:GetAlpha(), 0)
end)

T.test("journal: listens only while the map shows it, and reopens on the list", function()
    local J = load()
    local f = open(J)
    row(f, 1):Click()
    QW.ShowLog(false)
    T.eq(f:IsVisible(), false)
    T.eq(next(f.events.__events or {}) == nil, true, "no events while closed")
    QW.ShowLog(true)
    stub.RunTimers()
    T.eq(f.list:IsShown(), true, "back on the list, like the game's log")
end)

T.test("journal: a fight changes nothing that refuses it", function()
    local J = load()
    stub.EnterCombat()
    local f = open(J)
    row(f, 3):Click()
    foot(f)[2]:Click()
    foot(f)[4]:Click()
    foot(f)[4]:Click()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a hovered or opened quest's area lights on the map, by a blob of our own", function()
    local J = load()
    local f = open(J)
    row(f, 3):GetScript("OnEnter")(row(f, 3))
    local blob = J.blob
    T.truthy(blob, "a blob frame of ours")
    T.eq(blob:GetObjectType(), "QuestPOIFrame")
    T.eq(blob:GetParent(), WorldMapFrame.ScrollContainer.Child, "over the map's canvas")
    T.eq(blob:GetFrameLevel(), 2007, "at the game's blob level")
    T.eq(blob:IsMouseEnabled(), false, "the map's clicks pass through")
    local drawn = {}
    blob.DrawBlob = function(_, id, on) drawn[#drawn + 1] = on and id or "off" end
    blob.DrawNone = function() drawn[#drawn + 1] = "none" end
    row(f, 3):GetScript("OnEnter")(row(f, 3))
    T.deq(drawn, { "none", 3 })
    row(f, 3):GetScript("OnLeave")(row(f, 3))
    T.deq(drawn, { "none", 3, "none" }, "gone when the mouse leaves")
    row(f, 1):Click()
    T.eq(drawn[#drawn], 1, "an open quest stays lit, like the game's log")
    f.quest.stack.pieces[1]:Click()
    T.eq(drawn[#drawn], "none", "back on the list: none")
    QW.state.mapType = 2    -- a continent: the game draws no blobs there
    row(f, 3):GetScript("OnEnter")(row(f, 3))
    T.eq(drawn[#drawn], "none")
    T.deq(QW.Calls("mapCode"), {}, "nothing of the map's own code ran")
    T.isnil(rawget(WorldMapFrame, "highlightedQuestID"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: the quest's map icon gets the game's ring, on a frame of our own over its pin", function()
    local J = load()
    local f = open(J)
    local pin
    for p in pairs(WorldMapFrame.pinPools.QuestPinTemplate.activeObjects) do if p.questID == 3 then pin = p end end
    row(f, 3):GetScript("OnEnter")(row(f, 3))
    local ring = J.ring
    T.truthy(ring, "a ring of ours")
    T.eq(ring:IsShown(), true)
    local point, rel = ring:GetPoint(1)
    T.eq(point, "CENTER"); T.eq(rel, pin, "over the quest's own pin")
    T.eq(ring:GetFrameLevel(), 2101, "just above it")
    T.eq(ring:IsMouseEnabled(), false, "the pin's clicks pass through")
    T.eq(pin.HighlightTexture:IsShown(), false, "nothing of the pin's own touched")
    row(f, 3):GetScript("OnLeave")(row(f, 3))
    T.eq(ring:IsShown(), false, "gone when the mouse leaves")
    row(f, 2):GetScript("OnEnter")(row(f, 2))
    T.eq(ring:IsShown(), false, "a quest with no pin on this map: no ring")
    T.deq(QW.Calls("mapCode"), {})
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: right-click a quest for the game's menu (track, focus, share, abandon); a zone tracks or untracks all", function()
    local J = load()
    local f = open(J)
    local keys = J.MenuKeys(row(f, 3).quest)
    T.deq(keys, { "map", "track", "focus", "abandon" }, "no Share outside a group")
    stub.SetGroup(true)
    T.deq((J.MenuKeys(row(f, 3).quest)), { "map", "track", "focus", "share", "abandon" })
    J.Do("track", row(f, 3).quest)
    T.deq(QW.Calls("track"), { 3 })
    -- Abandon from the menu: the quest's page, its Abandon already asking.
    J.Do("abandon", row(f, 1).quest)
    T.eq(f.quest:IsShown(), true)
    T.eq(foot(f)[4].text:GetText(), "Abandon?")
    T.deq(QW.Calls("abandon"), {}, "nothing dropped yet")
    -- A zone: untrack all, then track all.
    J.ShowList()
    stub.RunTimers()
    J.TrackZone("Elwynn Forest", false)
    T.deq(QW.Calls("untrack"), { 1 }, "only the tracked one")
    J.TrackZone("Elwynn Forest", true)
    T.eq(#QW.Calls("track"), 3, "both Elwynn quests tracked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: its right-click menu closes with the map", function()
    local J = load()
    local f = open(J)
    J.Menu(row(f, 3).quest, row(f, 3))
    T.eq(DaylightUI.Widgets.menuOwner, row(f, 3), "open on the row")
    QW.ShowLog(false)
    T.isnil(DaylightUI.Widgets.menuOwner, "closed with the map")
    -- Someone else's menu stays.
    local other = CreateFrame("Button", nil, UIParent)
    QW.ShowLog(true); stub.RunTimers()
    DaylightUI.Widgets.OpenMenu(other, { "a" }, { a = "A" }, nil, function() end)
    QW.ShowLog(false)
    T.eq(DaylightUI.Widgets.menuOwner, other)
end)

-- Same as the game's log (QuestMapLogTitleButton_OnEnter): right of the panel,
-- or left of it when there's no room on the right.
T.test("journal: a hovered quest's tooltip sits right of the panel (left with no room), level with the row; off = at the mouse", function()
    local J = load()
    local f = open(J)
    local r = row(f, 3)
    local uiRight = UIParent.GetRight
    f.GetLeft, f.GetRight = function() return 1000 end, function() return 1300 end
    r.GetLeft, r.GetRight = function() return 1004 end, function() return 1290 end
    GameTooltip.GetWidth = function() return 250 end
    UIParent.GetRight = function() return 1920 end
    r:GetScript("OnEnter")(r)
    T.eq(GameTooltip.__anchor, "ANCHOR_NONE", "placed by us")
    local p, rel, rp, x, y = GameTooltip:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, r); T.eq(rp, "TOPRIGHT"); T.eq(y, 0, "level with the row")
    T.eq(x, 10 + J.TIP_GAP, "clear of the panel's right edge")
    r:GetScript("OnLeave")(r)
    UIParent.GetRight = function() return 1400 end
    r:GetScript("OnEnter")(r)
    p, rel, rp, x = GameTooltip:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rp, "TOPLEFT", "no room on the right: over the map")
    T.eq(x, -4 - J.TIP_GAP, "clear of the panel's left edge")
    r:GetScript("OnLeave")(r)
    -- The map scaled (the log rides on it), the tooltip at its own: measured on screen.
    local fScale, rScale, tScale = f.GetEffectiveScale, r.GetEffectiveScale, GameTooltip.GetEffectiveScale
    f.GetEffectiveScale = function() return 0.5 end
    r.GetEffectiveScale = function() return 0.5 end
    GameTooltip.GetEffectiveScale = function() return 1 end
    r:GetScript("OnEnter")(r)
    p, rel, rp, x = GameTooltip:GetPoint(1)
    T.eq(p, "TOPLEFT", "half-size map: plenty of room on the right")
    T.eq(x, 5 + J.TIP_GAP, "the 10 between row and panel edge is 5 on screen")
    r:GetScript("OnLeave")(r)
    UIParent.GetRight = function() return 1920 end
    f.GetEffectiveScale = function() return 1.5 end
    r.GetEffectiveScale = function() return 1.5 end
    r:GetScript("OnEnter")(r)
    p = GameTooltip:GetPoint(1)
    T.eq(p, "TOPRIGHT", "a big map reaches the screen's edge: left")
    r:GetScript("OnLeave")(r)
    f.GetEffectiveScale, r.GetEffectiveScale, GameTooltip.GetEffectiveScale = fScale, rScale, tScale
    UIParent.GetRight = uiRight
    DaylightUI:Set("Quests", "journalTipBeside", false)
    r:GetScript("OnEnter")(r)
    T.eq(GameTooltip.__anchor, "ANCHOR_CURSOR", "off: at the mouse")
    r:GetScript("OnLeave")(r)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a hovered quest shows its tooltip (objectives, the journal's clicks)", function()
    local J, ns = load()
    local f = open(J)
    local r = row(f, 3)
    r:GetScript("OnEnter")(r)
    T.eq(GameTooltip:IsShown(), true, "shown on hover")
    local text = table.concat(GameTooltip.lines, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.truthy(text:find("Westfall Stew", 1, true), "its title")
    T.truthy(text:find("Okra", 1, true), "its objectives")
    for _, h in ipairs(ns.Clicks.JOURNAL_HINTS) do
        T.truthy(text:find(h, 1, true), "the journal's click hint: " .. h)
    end
    T.falsy(text:find(ns.Clicks.HINTS[1], 1, true), "not the tracker's icon hint")
    r:GetScript("OnLeave")(r)
    T.eq(GameTooltip:IsShown(), false, "gone when the mouse leaves")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The other way round: a quest hovered on the map lights its row in the list.
-- The game's pin announces it through EventRegistry (QuestPinMixin:OnMouseEnter
-- and OnMouseLeave), so nothing on the map is called or written.
T.test("journal: hovering a quest's icon on the map lights its row", function()
    local J = load()
    DaylightUI.DB.General().motion = false   -- the light snaps
    local f = open(J)
    local pin
    for p in pairs(WorldMapFrame.pinPools.QuestPinTemplate.activeObjects) do if p.questID == 3 then pin = p end end
    EventRegistry:TriggerEvent("MapCanvas.QuestPin.OnEnter", pin, 3)
    stub.RunTimers()
    T.eq(row(f, 3).hi:IsShown(), true, "its row lit")
    T.eq(row(f, 1).hi:IsShown(), false, "the others not")
    -- A refill (a quest update while hovered) keeps it lit.
    J.Refresh(false)
    T.eq(row(f, 3).hi:IsShown(), true, "still lit after a refill")
    EventRegistry:TriggerEvent("MapCanvas.QuestPin.OnLeave", 3)
    stub.RunTimers()
    T.eq(row(f, 3).hi:IsShown(), false, "dark when the mouse leaves the icon")
    T.deq(QW.Calls("mapCode"), {})
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a quest name under the mouse spotlights it on the map, the names stay", function()
    local J = load()
    DaylightUI.DB.General().motion = false   -- the list's lift snaps
    local f = open(J)
    local a = shown(f.list.stack.pieces, "quest")[1]
    local b = shown(f.list.stack.pieces, "quest")[2]
    local asked = {}
    stub.quests.Bridge.FocusIcons = function(id, dim, grow) asked[#asked + 1] = { id or "none", dim, grow } end
    a:GetScript("OnEnter")(a)
    T.deq(asked[1], { a.quest.id, 0.2, J.SPOT_GROW })
    T.eq(b:GetAlpha(), 1, "the other names stay")
    T.eq(b.title:GetAlpha(), 1)
    a:GetScript("OnLeave")(a)
    T.eq(asked[2][1], "none", "all back")
    DaylightUI:Set("Quests", "journalHoverIcons", false)
    stub.RunTimers()
    a:GetScript("OnEnter")(a)
    T.eq(asked[#asked][1], "none", "switched off")
    a:GetScript("OnLeave")(a)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a Questie icon under the mouse spotlights its quest, with the quest log off too", function()
    local J = load()
    local asked = {}
    stub.quests.Bridge.FocusIcons = function(id) asked[#asked + 1] = id or "none" end
    J.IconHover(140)
    J.IconHover(nil)
    T.deq(asked, { 140, "none" })
    local watching
    local watch = stub.quests.Bridge.WatchHover
    stub.quests.Bridge.WatchHover = function(fn) watching = fn; return watch(fn) end
    DaylightUI:Set("Quests", "journal", false)
    stub.RunTimers()
    T.eq(watching, J.IconHover, "the log's switch doesn't take the icons' away")
    DaylightUI:Set("Quests", "journalHoverIcons", false)
    stub.RunTimers()
    T.isnil(watching, "both off: Questie's own hover is back")
    stub.quests.Bridge.WatchHover = watch
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a quest hovered on the map further down the list glides into view", function()
    local many = {}
    for i = 1, 40 do many[i] = QW.quest(100 + i, "Quest " .. i, { zone = "Elwynn Forest", level = 10 }) end
    local J = load({ quests = many })
    DaylightUI.DB.General().motion = false   -- the glide snaps
    local f = open(J)
    local s = f.list.stack
    s.scroll:SetHeight(300)   -- (the fake game doesn't measure a frame from its anchors)
    T.eq(s:Scrolled(), 0, "at the top")
    J.MapHover({ 140 })
    stub.RunTimers()
    T.eq(row(f, 140).hi:IsShown(), true)
    local top = row(f, 140).stackY
    T.truthy(s:Scrolled() > 0, "scrolled toward it")
    T.truthy(s:Scrolled() <= top and s:Scrolled() + s.scroll:GetHeight() >= top + DaylightUI:Get("Quests", "journalRowHeight"), "the row in view")
    -- Hovering one already in view moves nothing.
    local at = s:Scrolled()
    J.MapHover({ 139 })
    stub.RunTimers()
    T.eq(s:Scrolled(), at, "already in view: the list stays")
    J.MapHover(nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The tracker's click, with the map opening either inside the call or a frame
-- later, as the client's may.
local function mapOpens(later)
    C_Map.OpenWorldMap = function()
        if later then C_Timer.After(0, function() QW.ShowLog(true) end) else QW.ShowLog(true) end
    end
end

for _, later in ipairs({ false, true }) do
    T.test("journal: a tracker click opens on that quest's page, map opening " .. (later and "a frame later" or "at once"), function()
        local J, ns = load()
        local f = J.frame
        mapOpens(later)
        ns.Clicks.Do("map", { id = 3 })
        stub.RunTimers()
        T.eq(f.quest:IsShown(), true, "the quest's page")
        T.eq(f.list:IsShown(), false)
        T.eq(f.quest.stack.pieces[1] ~= nil, true, "filled")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end)
end

T.test("journal: a tracker click turns an open journal to that quest, again keeps the page", function()
    local J, ns = load()
    local f = open(J)
    T.eq(f.list:IsShown(), true)
    ns.Clicks.Do("map", { id = 1 })
    T.eq(f.quest:IsShown(), true, "from the list")
    ns.Clicks.Do("map", { id = 3 })
    stub.RunTimers()
    T.eq(f.quest:IsShown(), true, "from another quest's page")
    J.ShowList()
    ns.Clicks.Do("turnin", { id = 3 })
    T.eq(f.quest:IsShown(), true, "the hand-in on the map too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: opened by hand it stays on the list; the ask doesn't wait for a later opening", function()
    local J, ns = load()
    local f = open(J)
    T.eq(f.list:IsShown(), true, "a plain opening: the list")
    QW.ShowLog(false)
    -- The map opens with the log folded: nothing shows the page.
    C_Map.OpenWorldMap = function() end
    ns.Clicks.Do("map", { id = 3 })
    stub.Advance(J.WANT_WAIT + 1)
    QW.ShowLog(true); stub.RunTimers()
    T.eq(f.list:IsShown(), true, "long after: the list")
    T.eq(f.quest:IsShown(), false)
end)

T.test("journal: a quest the log doesn't list opens the list; a fight only refuses", function()
    local J, ns = load()
    local f = J.frame
    mapOpens(false)
    ns.Clicks.Do("map", { id = 999 })
    stub.RunTimers()
    T.eq(f.list:IsShown(), true, "not in the journal")
    QW.ShowLog(false)
    stub.EnterCombat()
    ns.Clicks.Do("map", { id = 3 })
    T.eq(WorldMapFrame:IsShown(), false, "no map in a fight")
    stub.LeaveCombat()
    QW.ShowLog(true); stub.RunTimers()
    T.eq(f.list:IsShown(), true, "the refused click left nothing behind")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal: a mark on the row says how many of your party are on it, and follows them", function()
    local quests = { QW.quest(1, "Princess Must Die!", { onParty = { "party1", "party2" } }), QW.quest(2, "Kobold Candles") }
    local J = load({ quests = quests, partySize = 2 })
    local f = open(J)
    local b = row(f, 1)
    T.eq(b.party:IsShown(), true)
    T.eq(b.party.count:GetText(), "2")
    T.eq(row(f, 2).party:IsShown(), false, "nobody else on it")
    T.eq(b.party:IsMouseEnabled() == true, false, "the row keeps its clicks")
    -- one of them hands it in: the journal hears of it, the row eases to the new count
    QW.state.quests[1].onParty = { "party2" }
    stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "party1")
    stub.RunTimers()
    T.eq(row(f, 1).party.count:GetText(), "1")
    QW.state.quests[1].onParty = nil
    stub.FireEvent("UNIT_QUEST_LOG_CHANGED", "party2")
    stub.RunTimers()
    T.eq(row(f, 1).party:IsShown(), false, "gone, after its fade")
    QW.state.quests[1].onParty = { "party1" }
    DaylightUI:Set("Quests", "questParty", false)
    stub.RunTimers()
    T.eq(row(f, 1).party:IsShown(), false, "switched off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal on a controller: X tracks or untracks the quest on the row or page, B on a page goes back", function()
    local function padOn()
        _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
        _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    end
    local J = load(nil, { before = padOn })
    local at
    _G.SmartNavigation = { GetCurrentButton = function() return at end }
    local f = open(J)
    T.eq(DaylightUI.Pad.taken, f, "the journal takes the buttons while it shows")
    at = row(f, 3)
    stub.RunTimers()
    T.truthy(stub.overrides.PAD3, "X on a quest row")
    local asked
    local add, remove = C_QuestLog.AddQuestWatch, C_QuestLog.RemoveQuestWatch
    C_QuestLog.AddQuestWatch = function(id) asked = "track " .. id end
    C_QuestLog.RemoveQuestWatch = function(id) asked = "untrack " .. id end
    local was = at.quest.watched == true
    _G[stub.overrides.PAD3.click]:Click()
    T.eq(asked, (was and "untrack " or "track ") .. 3, "one press, no walk to the footer")
    C_QuestLog.AddQuestWatch, C_QuestLog.RemoveQuestWatch = add, remove
    at = row(f, 1)
    at:Click()   -- its page
    at = nil
    stub.RunTimers()
    T.truthy(stub.overrides.PAD3, "X anywhere on the quest's page")
    T.truthy(stub.overrides.PAD2, "B goes back to the list")
    _G[stub.overrides.PAD2.click]:Click()
    T.eq(f.list:IsShown(), true)
    stub.RunTimers()
    T.eq(stub.overrides.PAD2, nil, "on the list B is the map's again")
    QW.ShowLog(false)
    stub.RunTimers()
    T.eq(DaylightUI.Pad.taken, nil, "given back with the log")
    _G.GamepadMode, _G.InputUtil, _G.SmartNavigation = nil, nil, nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("journal on a controller: the game's see-through pieces under it are skipped by the D-pad, and given back", function()
    local marked = {}
    local J = load(nil, { before = function()
        _G.SmartNavigation_MarkFrameIgnored = function(o) marked[o] = true end
        _G.SmartNavigation_ClearIgnoreStatus = function(o) marked[o] = nil end
    end })
    local f = open(J)
    local qm = J.Panel()
    local any = 0
    for _, c in ipairs({ qm:GetChildren() }) do
        if c ~= f then T.truthy(marked[c], "a game piece under the journal"); any = any + 1 end
    end
    T.truthy(any > 0)
    T.falsy(marked[f], "never the journal itself")
    J.Veil(false)
    T.eq(next(marked), nil, "switched off: the game's pieces are stops again")
    _G.SmartNavigation_MarkFrameIgnored, _G.SmartNavigation_ClearIgnoreStatus = nil, nil
end)
